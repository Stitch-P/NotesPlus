local Detached = require("src/ui/shared/detached_ui")
local Components = require("src/ui/shared/components")
local SafeValues = require("src/core/safe_values")
local Hotkeys = require("src/core/hotkeys")
local Settings = require("src/core/settings")
local WindowStyle = require("src/ui/window/window_style")
local SettingsControls = require("src/ui/settings/settings_controls")

local Menu = {}
local owners = setmetatable({}, {__mode = "k"})

local function cleanup(callback)
    local ok, err = pcall(callback)
    if not ok then log("Notes: UI cleanup failed", tostring(err)) end
end

local SIDE_WIDTH = 780
local TOP_DOWN_WIDTH = 470
local MAX_HEIGHT = 620
local TOP_DOWN_HEIGHT = 468
local TOP_DOWN_VIEWPORT_TOP = 80
local LEFT = 12
local RIGHT = 50
local COLUMN_GAP = 18
local SIDE_COLUMN_WIDTH = math.floor((SIDE_WIDTH - LEFT - RIGHT - COLUMN_GAP) / 2)
local CONTROL_WIDTH = 136
local CONTROL_OFFSET = 172
local ROW_HEIGHT = 30
local LABEL_COLOR = 0xD8D8D8
local MUTED_COLOR = 0xA8A8A8
local ACCENT_COLOR = 0xFFAA00
local SCROLL_STEP = 48
local SETTING_TOOLTIPS = {
    enabled = "Enable Notes-Plus.",
    menuLayout = "Choose two columns or a scrolling layout.",
    showOnLogin = "Open your notes when the plugin starts.",
    notesHotkey = "Press one or two keys to bind. Press to open or close your notes.",
    notesOpacity = "Adjust the notes window opacity.",
    fontSize = "Set the note text from 10 to 24 pixels.",
    showSubject = "Show or hide all note subjects and task steps. Individual arrows can change them afterward.",
    showProgressBars = "Show progress bars on tracked notes.",
    compactNotes = "Shows each tracked note as a title and one line of progress. Hover a note for everything else: steps, requirements and details."
}

local collapsedSections = {
    menu = false,
    notes = false,
    window = false
}
local safeNumber = SafeValues.Number

local function componentSize(component)
    if component == nil then return nil, nil end
    local ok, width, height = pcall(function() return component.width, component.height end)
    if not ok then return nil, nil end
    return width > 1 and math.floor(width) or nil, height > 1 and math.floor(height) or nil
end
local function safeFont()
    if id ~= nil and id.Font ~= nil and id.Font.NOTOSANS_13 ~= nil then
        return tonumber(id.Font.NOTOSANS_13) or id.Font.NOTOSANS_13
    end
    return id ~= nil and id.Font ~= nil and id.Font.MUSEO_SANS_13PT_REGULAR or nil
end
local function safeModalStyle()
    return id.StyleSheet.GROUPBOX_MAIN_MODAL_TITLED
end
local function setStyle(component, style)
    if component ~= nil and style ~= nil then
        pcall(function()
            component.stylesheetID = style
        end)
    end
end
local function moveToFront(component)
    if component ~= nil then
        pcall(function()
            component:MoveToFront()
        end)
    end
end
local setRGB = SettingsControls.SetTextColour
local function setHeaderText(component, text)
    pcall(function()
        component.headerText.content = text
        component.headerText.font = safeFont()
    end)
end
local function newPanel(parent)
    return Components.Host(parent, nil, ui.GroupBox or ui.Panel)
end
local function addText(parent, text, x, y, width, height, color)
    return SettingsControls.Text(parent, text, x, y, width, height, color or LABEL_COLOR)
end
local function addButton(parent, text, x, y, width, height, onPress)
    local button = SettingsControls.Button(parent, text, x, y, width, height, onPress, LABEL_COLOR)
    local owner = owners[parent]
    if owner ~= nil then owner.prettyComponents[#owner.prettyComponents + 1] = button end
    return button
end
local function componentText(component)
    return component.content
end
local function setComponentText(component, value)
    component.content = tostring(value or "")
end
local function addInput(parent, value, x, y, width, height)
    local field = prettyui.TextField.new(parent, Components.Options({
        text = tostring(value or ""), x = x, y = y, width = width, height = height
    }))
    local input = field.root
    input.scrollbar.visible = false
    input.scrollbar.size = 0
    WindowStyle.ApplyInput(input)
    local owner = owners[parent]
    if owner ~= nil then owner.prettyComponents[#owner.prettyComponents + 1] = field end
    return {
        component = input,
        prettyComponent = field,
        get = function() return field:GetText() end,
        set = function(nextValue) field:SetText(tostring(nextValue or ""), false) end
    }
end
local function groupedInteger(value)
    local text = tostring(math.floor(safeNumber(value, 0)))
    local grouped = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return grouped:sub(1, 1) == "," and grouped:sub(2) or grouped
end
local function addNumberInput(parent, value, x, y, width, height)
    local input = addInput(parent, groupedInteger(value), x, y, width, height)
    function input.get()
        return componentText(input.component):gsub("[,%.]", ""):match("%-?%d+") or ""
    end
    function input.set(nextValue)
        setComponentText(input.component, groupedInteger(nextValue))
    end
    return input
end
local function addCheck(parent, value, x, y, onChange)
    local group = prettyui.CheckboxButton.new(parent, {
        {text = "", value = "checked", selected = value == true}
    }, Components.Options({
        x = x, y = y + 1, width = 28, onChange = onChange
    }))
    return {
        component = group.root,
        prettyComponent = group,
        get = function() return group:IsSelected("checked") end,
        set = function(nextValue) group:SetSelected("checked", nextValue == true, false) end
    }
end
local function indexOf(options, value)
    for index, option in ipairs(options or {}) do
        if option == value then
            return index
        end
    end
    return 1
end
local function addCycle(parent, value, options, x, y, width, height, onChange)
    local state = { value = Settings.NormalizeChoice(value, options, options[1]) }
    local button
    button = addButton(parent, state.value, x, y, width, height, function()
        local index = indexOf(options, state.value) + 1
        if index > #options then
            index = 1
        end
        state.value = options[index]
        button.content.content = state.value
        if onChange ~= nil then
            onChange()
        end
    end)
    return {
        component = button.root,
        get = function()
            return state.value
        end,
        set = function(nextValue)
            state.value = Settings.NormalizeChoice(nextValue, options, options[1])
            button.content.content = state.value
        end
    }
end
local copySettings = Settings.DeepCopy
function Menu.Read(menu)
    if menu == nil then
        return nil
    end
    if menu.syncPosition ~= nil then menu.syncPosition() end
    local nextSettings = copySettings(menu.baseSettings)
    for key, control in pairs(menu.controls or {}) do
        if control.get ~= nil then
            nextSettings[key] = control.get()
        end
    end
    return Settings.Normalize(nextSettings)
end
function Menu.SyncSettings(menu, settings, keys)
    if menu == nil then return end
    local incoming = Settings.Normalize(settings)
    local normalized = incoming
    local selectedKeys = keys
    if selectedKeys ~= nil then
        normalized = Menu.Read(menu)
        if normalized == nil then return end
        for _, key in ipairs(selectedKeys) do normalized[key] = incoming[key] end
        normalized = Settings.Normalize(normalized)
    else
        selectedKeys = {}
        for key, control in pairs(menu.controls or {}) do
            if control.set ~= nil then selectedKeys[#selectedKeys + 1] = key end
        end
        table.sort(selectedKeys)
    end
    local layoutChanged = menu.baseSettings.menuLayout ~= normalized.menuLayout
    if menu.page ~= nil and (layoutChanged or menu.page.name ~= normalized.activePage) then
        menu.page.settings = Menu.Read(menu)
        menu.baseSettings = normalized
        menu.render(not layoutChanged)
        return
    end
    menu.baseSettings = normalized
    for _, key in ipairs(selectedKeys) do
        local control = menu.controls ~= nil and menu.controls[key] or nil
        if control ~= nil and control.set ~= nil then control.set(normalized[key]) end
    end
end

function Menu.Mount(parent, settings, callbacks, embedded)
    callbacks = callbacks or {}
    local onApply = callbacks.onApply
    local onClose = callbacks.onClose
    local onOpenNotes = callbacks.onOpenNotes
    if parent == nil then
        return nil
    end

    local menu = {
        component = nil,
        parent = parent,
        baseSettings = Settings.Normalize(settings),
        controls = {},
        onApply = onApply,
        prettyComponents = {},
        pages = {},
    }
    local pageScrollOffsets = {}
    local render
    local function destroyPrettyComponents()
        for index = #menu.prettyComponents, 1, -1 do
            local component = menu.prettyComponents[index]
            if component ~= nil then
                cleanup(function()
                    component:Destroy()
                end)
            end
        end
        menu.prettyComponents = {}
    end
    local function stopPageInput()
        for _, control in pairs(menu.controls) do
            if control.cancelListening ~= nil then control.cancelListening() end
            if control.cancelDragging ~= nil then control.cancelDragging() end
        end
    end

    local function destroySurface()
        stopPageInput()
        for _, page in pairs(menu.pages) do
            cleanup(function() prettyui.Tooltip.unregisterContext(page) end)
        end
        if menu.chrome ~= nil and menu.component == menu.chrome.root then menu.component = nil end
        destroyPrettyComponents()
        if menu.component ~= nil then
            cleanup(function() menu.component:Destroy() end)
            menu.component = nil
        end
        menu.chrome, menu.panel, menu.syncPosition, menu.fitPage = nil, nil, nil, nil
        menu.pages, menu.page, menu.tabs, menu.controls = {}, nil, nil, {}
        menu.pageApplyPending = nil
    end

    local function commit(rebuild)
        menu.pageApplyPending = nil
        menu.baseSettings = Menu.Read(menu)
        if onApply ~= nil then
            onApply(menu.baseSettings)
        end
        if rebuild then
            render()
        end
    end
    local function showPage(page)
        local previous = menu.page
        if previous ~= nil and previous ~= page then
            prettyui.Tooltip.hideContextTooltips(previous)
            previous.root.hidden = true
            if previous.scroll ~= nil then previous.scroll:Refresh() end
        end
        menu.page, menu.controls = page, page.controls
        for key, control in pairs(page.controls) do
            local value = menu.baseSettings[key]
            if page.settings[key] ~= value and control.get ~= nil and control.set ~= nil then
                control.set(value)
            end
        end
        page.settings = menu.baseSettings
        page.root.hidden = false
        menu.fitPage(page.height)
        if page.scroll ~= nil then page.scroll:Refresh() end
        for name, tab in pairs(menu.tabs) do
            setRGB(tab, name == page.name and ACCENT_COLOR or LABEL_COLOR)
        end
    end

    function render(keepShell)
        local parentWidth, parentHeight = componentSize(parent)
        if keepShell and parentWidth == menu.parentWidth and parentHeight == menu.parentHeight then
            stopPageInput()
            local cached = menu.pages[menu.baseSettings.activePage]
            if cached ~= nil then
                showPage(cached)
                return
            end
        else
            destroySurface()
        end
        menu.parentWidth, menu.parentHeight = parentWidth, parentHeight
        local headerGap = embedded and 30 or 0
        local pageTop = 38 - headerGap
        local contentStart = embedded and 50 or TOP_DOWN_VIEWPORT_TOP
        local normalized = Settings.Normalize(menu.baseSettings)
        menu.baseSettings = normalized
        local activePage = normalized.activePage
        local topDown = normalized.menuLayout == "Top to bottom"
            or (not embedded and (parent.width < SIDE_WIDTH or parent.height < MAX_HEIGHT))
        local frameWidth = math.min(parent.width, topDown and TOP_DOWN_WIDTH or SIDE_WIDTH)
        local frameHeight = math.min(parent.height, topDown and (TOP_DOWN_HEIGHT - headerGap) or MAX_HEIGHT)
        local viewportHeight = math.max(1, frameHeight - 152 + headerGap)
        local panelWidth = frameWidth
        local panelHeight = frameHeight
        local panelX = embedded and 0 or normalized.menuX
        local panelY = embedded and 0 or normalized.menuY
        local frameRoot, chrome, panel = menu.component, menu.chrome, menu.panel
        local createShell = panel == nil
        if createShell then
            menu.menuBackground = nil
            if not embedded then
                chrome = WindowStyle.New(parent, {
                    title = "Notes-Plus", x = panelX, y = panelY, width = frameWidth, height = frameHeight,
                    minWidth = 1, minHeight = 1, scrollable = false
                })
                frameRoot = chrome.root
                chrome.viewport.hidden = true
                menu.prettyComponents[#menu.prettyComponents + 1] = chrome
                menu.chrome = chrome
            end
            panel = embedded and Components.Host(parent) or newPanel(frameRoot or parent)
            if not embedded then setStyle(panel, safeModalStyle()) end
            panel:SetSize(frameWidth, frameHeight)
            panel.clickthrough = false
            if not embedded then
                panel.contentBackgroundSprite.rgba = 0
                panel.headerBackgroundSprite.rgba = 0
                setHeaderText(panel, "")
            end
            panel:SetPos(0, 0)
            frameRoot = frameRoot or panel
            frameRoot:SetPos(panelX, panelY)
            frameRoot.alpha = 1
            moveToFront(frameRoot)
            menu.component, menu.panel = frameRoot, panel
            owners[panel] = menu
        end

        local function movePanel(x, y)
            if embedded then
                panelX, panelY = 0, 0
                frameRoot:SetPos(0, 0)
                return 0, 0
            end
            local parentWidth, parentHeight = componentSize(parent)
            local maxX = parentWidth ~= nil and math.max(0, parentWidth - (panelWidth <= parentWidth and panelWidth or 120)) or 3000
            local maxY = parentHeight ~= nil and math.max(0, parentHeight - (panelHeight <= parentHeight and panelHeight or 32)) or 3000
            panelX = Settings.ClampInt(x, 0, maxX, panelX)
            panelY = Settings.ClampInt(y, 0, maxY, panelY)
            if frameRoot.x ~= panelX or frameRoot.y ~= panelY then frameRoot:SetPos(panelX, panelY) end
            menu.baseSettings.menuX, menu.baseSettings.menuY = panelX, panelY
            if chrome ~= nil and not Menu.IsDragging(menu) then
                local header = chrome.titleDrag
                if header.x ~= panelX or header.y ~= panelY then header:SetPos(panelX, panelY) end
                if header.width ~= panelWidth - 34 or header.height ~= 32 then header:SetSize(panelWidth - 34, 32) end
            end
            return panelX, panelY
        end
        if createShell then
            function menu.syncPosition()
                if not embedded and not Menu.IsDragging(menu) then
                    movePanel(menu.baseSettings.menuX, menu.baseSettings.menuY)
                end
            end
            local function closeMenu()
                commit(false)
                if onClose ~= nil then
                    onClose()
                end
            end
            if not embedded then
                chrome.onClose = closeMenu
                function chrome.onPositionChange(_, x, y)
                    local previousX, previousY = menu.baseSettings.menuX, menu.baseSettings.menuY
                    local newX, newY = movePanel(x, y)
                    if newX ~= previousX or newY ~= previousY then commit(false) end
                end
                chrome.closeButton:MoveToFront()
            end
        end

        local function selectPage(name)
            local previous = menu.page
            if name == previous.name then return true end
            local nextSettings = Menu.Read(menu)
            previous.settings = nextSettings
            nextSettings.activePage = name
            menu.baseSettings = nextSettings
            local ok, err = pcall(render, true)
            if not ok then
                menu.baseSettings.activePage = previous.name
                destroySurface()
                if onClose ~= nil then onClose() end
                error(err)
            end
            menu.pageApplyPending = onApply ~= nil
            return true
        end

        if createShell then
            menu.tabs = {}
            local pageGap = topDown and 6 or 8
            local pageWidth = topDown and 92 or 140
            local pageStartX = LEFT
            for index, page in ipairs(Settings.OPTIONS.activePage) do
                local selectedPage = page
                local button = addButton(
                    panel,
                    page,
                    pageStartX + (index - 1) * (pageWidth + pageGap),
                    pageTop,
                    pageWidth,
                    28,
                    function() selectPage(selectedPage) end
                )
                menu.tabs[page] = button
            end
            local divider = prettyui.Divider.new(panel, Components.Options({
                x = LEFT,
                y = pageTop - 14,
                width = frameWidth - LEFT - RIGHT
            }))
            menu.prettyComponents[#menu.prettyComponents + 1] = divider
        end

        local page = {name = activePage, root = Components.Host(panel), controls = {}, settings = normalized}
        menu.pages[activePage] = page
        page.root:SetSize(0, 0, 1, 1)
        page.root.clickthrough = true
        page.root.hidden = true
        local controls = page.controls
        prettyui.Tooltip.registerContext(page, parent, function(target)
            local targetPosition = target.xyGlobal
            local parentPosition = parent.xyGlobal
            local x = targetPosition.x - parentPosition.x
            local y = targetPosition.y - parentPosition.y
            local ancestor = target.parent
            while ancestor ~= nil and ancestor ~= parent do
                x = x - (ancestor.scrollX or 0)
                y = y - (ancestor.scrollY or 0)
                ancestor = ancestor.parent
            end
            return x, y
        end)

        local contentParent = page.root
        local contentScroll = nil
        local viewportWidth = frameWidth - LEFT - RIGHT
        if topDown then
            contentScroll = prettyui.SimpleView.new(page.root, Components.Options({
                x = LEFT,
                y = contentStart,
                width = viewportWidth,
                height = viewportHeight,
                contentHeight = viewportHeight + 1,
                scrollStep = SCROLL_STEP
            }))
            menu.prettyComponents[#menu.prettyComponents + 1] = contentScroll
            page.scroll = contentScroll
            function contentScroll.isVisible()
                return not page.root.hidden and page.root.visibleGlobal
            end
            contentParent = contentScroll.content
        end

        owners[contentParent] = menu
        local currentColumn = 1
        local currentColumnWidth = topDown
            and contentScroll.contentWidth
            or SIDE_COLUMN_WIDTH
        local columnLeft = topDown and 0 or LEFT
        local columnControlX = columnLeft + CONTROL_OFFSET
        local y = topDown and 0 or contentStart
        local columnBottoms = {}
        local function rememberColumnHeight()
            columnBottoms[currentColumn] = math.max(columnBottoms[currentColumn] or 0, y)
        end
        local function setColumn(index)
            rememberColumnHeight()
            currentColumn = index
            if topDown then
                y = y + 8
                return
            end
            columnLeft = LEFT + (index - 1) * (SIDE_COLUMN_WIDTH + COLUMN_GAP)
            columnControlX = columnLeft + CONTROL_OFFSET
            currentColumnWidth = SIDE_COLUMN_WIDTH
            y = contentStart
        end
        local function addRowTooltip(tooltipText, tooltipX, tooltipY)
            if tooltipText == nil then
                return
            end
            local info = prettyui.SpriteButton.new(contentParent, "INFO", function() end, Components.Options({
                x = tooltipX or (columnLeft + currentColumnWidth - 22),
                y = tooltipY or (y + 2),
                size = 20,
                hoverCursor = config.Cursor.CURSOR_DEFAULT,
            }))
            menu.prettyComponents[#menu.prettyComponents + 1] = info
            prettyui.Tooltip.bind(info, info.root, page, Components.Options({
                text = tooltipText,
                placement = "right",
                maxWidth = 190
            }))
            WindowStyle.ApplyTooltip(info.tooltip)
        end
        local function boolRow(key, label, rebuild, exclusiveKeys)
            addText(contentParent, label, columnLeft, y + 4, CONTROL_OFFSET - 10, 22, LABEL_COLOR)
            local control = addCheck(
                contentParent,
                normalized[key],
                columnControlX + CONTROL_WIDTH - 28,
                y + 2,
                function()
                    if exclusiveKeys ~= nil and controls[key].get() then
                        for _, otherKey in ipairs(exclusiveKeys) do
                            controls[otherKey].set(false)
                        end
                    end
                    commit(rebuild == true)
                end
            )
            controls[key] = control
            if control.prettyComponent ~= nil then
                menu.prettyComponents[#menu.prettyComponents + 1] = control.prettyComponent
            end
            addRowTooltip(SETTING_TOOLTIPS[key])
            y = y + ROW_HEIGHT
        end
        local function choiceRow(key, label, options, rebuild)
            addText(contentParent, label, columnLeft, y + 4, CONTROL_OFFSET - 10, 22, LABEL_COLOR)
            controls[key] = addCycle(
                contentParent,
                normalized[key],
                options,
                columnControlX,
                y,
                CONTROL_WIDTH,
                24,
                function() commit(rebuild == true) end
            )
            addRowTooltip(SETTING_TOOLTIPS[key])
            y = y + ROW_HEIGHT
        end
        local function hotkeyRow(key, label)
            addText(contentParent, label, columnLeft, y + 4, CONTROL_OFFSET - 10, 22, LABEL_COLOR)
            local selectedKey = normalized[key]
            local field = prettyui.KeybindField.new(contentParent, Components.Options({
                x = columnControlX, y = y, width = CONTROL_WIDTH, height = 24,
                value = Hotkeys.GetKeys(selectedKey),
                defaultValue = Hotkeys.GetKeys(Settings.Normalize({})[key]),
                font = safeFont(), colour = LABEL_COLOR * 256 + 255, shadowed = false,
                onChange = function(_, keys)
                    selectedKey = Hotkeys.FromKeys(keys)
                    commit(false)
                end,
            }))
            menu.prettyComponents[#menu.prettyComponents + 1] = field
            controls[key] = {
                component = field.root,
                prettyComponent = field,
                get = function() return selectedKey end,
                cancelListening = function() field:CancelListening() end,
                set = function(value)
                    if value == selectedKey then return end
                    selectedKey = value
                    field:SetValue(Hotkeys.GetKeys(value), false)
                end,
            }
            addRowTooltip(SETTING_TOOLTIPS[key])
            y = y + ROW_HEIGHT
        end
        local function numberRow(key, label)
            addText(contentParent, label, columnLeft, y + 4, CONTROL_OFFSET - 10, 22, LABEL_COLOR)
            controls[key] = addNumberInput(
                contentParent,
                normalized[key],
                columnControlX,
                y,
                CONTROL_WIDTH,
                24
            )
            local control = controls[key]
            function control.prettyComponent.onChange()
                if tonumber(control.get()) == nil then return end
                local nextSettings = Menu.Read(menu)
                if nextSettings[key] ~= menu.baseSettings[key] then commit(false) end
            end
            addRowTooltip(SETTING_TOOLTIPS[key])
            y = y + ROW_HEIGHT
        end
        local function opacityRow()
            local value = normalized.notesOpacity
            local sliderWidth = CONTROL_WIDTH - 40
            addText(contentParent, "Window opacity", columnLeft, y + 4, CONTROL_OFFSET - 10, 22, LABEL_COLOR)
            local percentage = addText(contentParent, tostring(value) .. "%", columnControlX + sliderWidth + 4,
                y + 4, 36, 22, LABEL_COLOR)
            local slider = prettyui.Slider.new(contentParent, Components.Options({
                x = columnControlX, y = y, width = sliderWidth, min = 10, max = 100, step = 1,
                value = value,
                onChange = function(_, nextValue)
                    percentage.content = tostring(nextValue) .. "%"
                    commit(false)
                end,
            }))
            menu.prettyComponents[#menu.prettyComponents + 1] = slider
            controls.notesOpacity = {
                prettyComponent = slider,
                get = function() return slider:GetValue() end,
                set = function(nextValue)
                    slider:SetValue(nextValue, false)
                    percentage.content = tostring(slider:GetValue()) .. "%"
                end,
                cancelDragging = function()
                    if slider.thumbPressed then
                        slider:SetDisabled(true)
                        slider:SetDisabled(false)
                    end
                end,
            }
            addRowTooltip(SETTING_TOOLTIPS.notesOpacity)
            y = y + ROW_HEIGHT
        end
        local function actionRow(label, text, tooltipText, onPress)
            addText(contentParent, label, columnLeft, y + 4, CONTROL_OFFSET - 10, 22, LABEL_COLOR)
            local button = addButton(contentParent, text, columnControlX, y, CONTROL_WIDTH, 24, onPress)
            addRowTooltip(tooltipText)
            y = y + ROW_HEIGHT
            return button
        end
        local function section(key, title)
            local collapsed = collapsedSections[key] == true
            addButton(contentParent, collapsed and "+" or "-", columnLeft, y, 24, 22, function()
                menu.baseSettings = Menu.Read(menu)
                collapsedSections[key] = not collapsed
                render()
            end)
            addText(contentParent, title, columnLeft + 34, y + 1, currentColumnWidth - 34, 22, ACCENT_COLOR)
            y = y + 28
            return not collapsed
        end
        local function detailLine(text, tooltipText)
            addText(contentParent, text, columnLeft, y + 3, currentColumnWidth - 28, 22, MUTED_COLOR)
            addRowTooltip(tooltipText, columnLeft + currentColumnWidth - 22, y + 2)
            y = y + ROW_HEIGHT
        end

        if activePage == "General" and section("menu", "Menu") then
            boolRow("enabled", "Enabled")
            choiceRow("menuLayout", "Menu layout", Settings.OPTIONS.menuLayout, true)
        end

        if activePage == "General" then setColumn(2) end
        if activePage == "General" and section("notes", "Notes") then
            actionRow("Notes window", "Open notes", "Open your notes.", function()
                commit(false)
                onOpenNotes()
            end)
            hotkeyRow("notesHotkey", "Notes window hotkey")
            boolRow("showOnLogin", "Open on startup")
        end
        if activePage == "Display" and section("window", "Notes Window") then
            opacityRow()
            numberRow("fontSize", "Font size")
            boolRow("showSubject", "Show subject")
            boolRow("showProgressBars", "Show progress bars")
            boolRow("compactNotes", "Compact notes")
            actionRow("Completion popup", "Set position", "Choose where note completion popups appear.", function()
                commit(false)
                if callbacks.onPositionPopup then callbacks.onPositionPopup() end
            end)
        end
        if activePage == "Display" then setColumn(2) end
        if activePage == "Display" and section("notes", "Notes") then
            detailLine("Use + to add a note.", "Write a note and choose its color.")
            detailLine("Click a note to edit it.", "Edit, reorder, or delete the selected note.")
            detailLine("Share your notes.", "Share titles, subjects, colors, and sprites.")
            detailLine("Import shared notes.", "Imported notes are added to your existing notes.")
        end

        rememberColumnHeight()
        if topDown and contentScroll ~= nil then
            local contentExtent = math.max(viewportHeight, y + 8)
            local maxScroll = math.max(0, contentExtent - viewportHeight)
            local scrollOffset = Settings.ClampInt(pageScrollOffsets[activePage], 0, maxScroll, 0)
            contentScroll:SetContentHeight(contentExtent)
            function contentScroll.onLayout(controller)
                pageScrollOffsets[activePage] = controller.scrollY or 0
            end
            contentScroll:SetScrollPosition(scrollOffset)
            page.height = (TOP_DOWN_HEIGHT - headerGap)
        else
            local bottom = contentStart
            for _, columnBottom in pairs(columnBottoms) do
                bottom = math.max(bottom, columnBottom)
            end
            local contentHeight = clamp(bottom + 76, 220, MAX_HEIGHT)
            page.height = contentHeight
        end

        if createShell then
            local authorWidth = math.max(180, frameWidth - LEFT - RIGHT - 116)
            local author = addText(panel, "Notes-Plus | Created by Pavy and Shauny", LEFT, 0, authorWidth, 20, MUTED_COLOR)
            author.alignHorizontal = ui.AlignMode.TOPLEFT
            author.clickthrough = true
            local version = addText(panel, "Version 1.0", frameWidth - RIGHT - 100, 0, 100, 20, 0xFFFFFF)
            version.alignHorizontal = ui.AlignMode.BOTTOMRIGHT
            version.clickthrough = true

            function menu.fitPage(height)
                panelHeight = height
                panel:SetSize(frameWidth, height)
                if chrome ~= nil then
                    chrome:SetSize(frameWidth, height)
                    movePanel(menu.baseSettings.menuX, menu.baseSettings.menuY)
                    chrome:Show()
                    menu.menuBackground = chrome.background
                end
                local y = height - 48 - 24
                author:SetY(y)
                version:SetY(y)
            end
        end
        showPage(page)
    end

    function menu.refreshBounds()
        menu.baseSettings = Menu.Read(menu)
        render()
    end
    menu.render, menu.destroySurface = render, destroySurface
    local ok, err = pcall(render)
    if not ok then
        Menu.Destroy(menu)
        error(err)
    end
    return menu
end
function Menu.MoveToFront(menu)
    if menu ~= nil then
        if menu.chrome ~= nil then menu.chrome:Show() else moveToFront(menu.component) end
        if menu.page ~= nil then
            prettyui.Tooltip.moveContextTooltipsToFront(menu.page)
        end
    end
end
function Menu.Destroy(menu)
    if menu ~= nil and menu.destroySurface ~= nil then
        menu.destroySurface()
        menu.destroySurface, menu.render, menu.refreshBounds = nil, nil, nil
    end
end

function Menu.Abandon(menu)
    if menu == nil then return end
    for _, page in pairs(menu.pages) do
        local hotkey = page.controls.notesHotkey
        local field = hotkey ~= nil and hotkey.prettyComponent or nil
        if field ~= nil then
            field.root, field.input.root = nil, nil
            cleanup(function()
                field:SetDisabled(true)
                field:Destroy()
            end)
        end
        local opacity = page.controls.notesOpacity
        local slider = opacity ~= nil and opacity.prettyComponent or nil
        if slider ~= nil then
            slider.root, slider.thumbDrag = nil, nil
            cleanup(function() slider:Destroy() end)
        end
        Detached.Tooltips(page)
    end
    menu.component, menu.chrome, menu.syncPosition = nil, nil, nil
    menu.pages, menu.page, menu.tabs, menu.panel, menu.fitPage = {}, nil, nil, nil, nil
    menu.destroySurface, menu.render, menu.refreshBounds, menu.pageApplyPending = nil, nil, nil, nil
    menu.prettyComponents, menu.controls = {}, {}
end

function Menu.IsDragging(menu)
    if menu == nil then return false end
    local header = menu.chrome ~= nil and menu.chrome.titleDrag or nil
    local opacity = menu.controls.notesOpacity
    return (header ~= nil and header.height > 32) or (opacity ~= nil and opacity.prettyComponent.thumbPressed == true)
end

function Menu.Tick(menu)
    if menu == nil then
        return
    end
    if menu.pageApplyPending then
        menu.pageApplyPending = nil
        menu.onApply(Menu.Read(menu))
    end
end

return Menu
