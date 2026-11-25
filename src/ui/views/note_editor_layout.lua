local Components = require("src/ui/shared/components")
local Base = require("src/ui/views/view")
local Notes = require("src/notes/notes")
local Sprites = require("src/data/sprite_catalog")
local Settings = require("src/core/settings")
local TextLayout = require("src/ui/shared/text_layout")
local WordWrap = require("src/ui/shared/word_wrap")
local Overlay = require("src/ui/window/overlay")
local WindowStyle = require("src/ui/window/window_style")
local DropdownLayout = require("src/ui/shared/dropdown_layout")

local Layout = {}
local TAB_NAMES = {"tracking", "note", "gear", "actionBar"}
local TAB_LABELS = {"Tracking", "Note", "Gear", "Action bar"}
local GOLD = 0xE7D7B0FF

local function place(component, x, y, width, height)
    width, height = math.max(1, width), math.max(1, height)
    if component.x ~= x or component.y ~= y then component:SetPos(x, y) end
    if component.width ~= width or component.height ~= height then component:SetSize(width, height) end
end

local function contentHeight(host, height)
    local scroll = host._scroll or host
    height = math.max(0, math.floor(height))
    if scroll.requestedContentHeight ~= height or scroll.width ~= scroll.root.width
        or scroll.height ~= scroll.root.height then host:SetContentHeight(height) end
end

local function textField(self, parent, value, placeholder, limit, changed)
    local frame = Base.EditorFrame(parent, self.width)
    local field = self:TrackField(prettyui.TextField.new(parent, Components.Options({
        text = "", placeholder = placeholder, maxLength = limit,
        stylesheetID = id.StyleSheet.INPUT_INVISIBLE,
        contentMargin = ui.Margin.new(12, 10, 12, 10),
        width = self.width, height = 38,
        onChange = function(_, _, content)
            if self.destroyed or self.clearing then return end
            if changed(content) then self:LayoutEditor(true) end
        end
    })))
    field.editorFrame = frame
    field.root.text.alignHorizontal = ui.AlignMode.TOPLEFT
    field.root.text.alignVertical = ui.AlignMode.TOPLEFT
    return WordWrap.Bind(field, value)
end

local function titleField(self, parent, value)
    local frame = Base.EditorFrame(parent, self.width)
    local field = self:TrackField(prettyui.TextField.new(parent, Components.Options({
        text = value, placeholder = "Title", maxLength = Notes.MAX_TITLE,
        stylesheetID = id.StyleSheet.INPUT_INVISIBLE,
        contentMargin = ui.Margin.new(12, 8, 12, 8),
        width = self.width, height = 38,
        onChange = function(_, _, content)
            if not self.destroyed and not self.clearing then self.draft.title = content end
        end
    })))
    field.editorFrame = frame
    field.root.text.alignHorizontal = ui.AlignMode.TOPLEFT
    field.root.text.alignVertical = ui.AlignMode.CENTRE
    field.root.text.maxLines = 1
    field.root.scrollbar.visible, field.root.scrollbar.size = false, 0
    return field
end

local function layoutTitle(field, font, fontID, color, x, y, width, height)
    place(field.root, x, y, width, height)
    place(field.editorFrame, x, y, width, height)
    if field.root.text.font ~= fontID then field.root.text.font = fontID end
    if field.root.text.rgba ~= color then field.root.text.rgba = color end
    local lineHeight = math.max(font.baseline, font.maxAscent + font.maxDescent)
    local margin = math.max(0, math.floor((height - lineHeight) / 2))
    if field.verticalMargin ~= margin then
        field.verticalMargin = margin
        field.root.contentMargin = ui.Margin.new(12, margin, 12, margin)
    end
end

local function textHeight(field, font, width)
    local text = field:GetText()
    local measured = field.heightMeasurement
    if measured and measured.text == text and measured.font == font and measured.width == width
        and measured.revision == field.displayRevision then
        return measured.height
    end
    local count = #TextLayout.Lines(field:DisplayText(font, width), font, width)
    local height = count * font.baseline + 20
    field.heightMeasurement = {text = text, font = font, width = width, height = height,
        revision = field.displayRevision}
    return height
end

local function layoutText(field, font, fontID, color, x, y, width, height, contentHeight, forceWrap)
    local changed = field.root.width ~= width or field.root.height ~= height or field.root.text.font ~= fontID
    place(field.root, x, y, width, height)
    place(field.editorFrame, x, y, width, height)
    if field.root.text.font ~= fontID then field.root.text.font = fontID end
    if field.root.text.rgba ~= color then field.root.text.rgba = color end
    field.root.text.maxLines = 255
    local overflow = contentHeight > height
    field.root.scrollbar.visible, field.root.scrollbar.size = overflow, overflow and 16 or 0
    field.root.scrollbar.autohide = true
    local margin = math.min(10, math.max(0, math.floor((height - font.baseline) / 2)))
    if field.verticalMargin ~= margin then
        field.verticalMargin = margin
        field.root.contentMargin = ui.Margin.new(12, margin, 12, margin)
        changed = true
    end
    local wrapWidth = math.max(1, width - 32 - (overflow and 16 or 0))
    if forceWrap or field.wrapWidth ~= wrapWidth or field.wrapFont ~= fontID then
        field:Wrap(font, wrapWidth)
        field.wrapWidth, field.wrapFont = wrapWidth, fontID
        changed = true
    end
    if changed then field.root:UpdateLayout() end
end

function Layout.Build(self)
    local draft = self.draft
    self:Heading(draft.index and "Edit note" or "New note")
    local chrome = self.window.chrome
    self.previousMinHeight = chrome.minHeight
    self.previousResizeMinHeight = chrome.resize and chrome.resize.minHeight
    local minimumHeight = math.min(self.parent.height, 360)
    chrome.minHeight = math.max(chrome.minHeight, minimumHeight)
    if chrome.resize then chrome.resize.minHeight = math.max(chrome.resize.minHeight, minimumHeight) end
    if self.window.root.height < minimumHeight then
        self.window:SetHeight(minimumHeight)
    end
    self.height = self.window.height
    self.header = prettyui.SimpleView.new(self.surface, Components.Options({x = 8, y = 6, width = self.width,
        height = 110, contentHeight = 110, scrollStep = 40}))
    local body = self.header.content
    self.titleLabel = Base.Label(body, "Title", 8, 0, 60, 24, GOLD)
    self.titleField = titleField(self, body, draft.title)
    self.categoryLabel = Base.Label(body, "Category", 8, 0, 100, 20, GOLD)
    self.categoryField = self:Track(prettyui.ComboBox.new(body, Components.Options({
        entries = self:CategoryEntries(false), selectedID = draft.categoryID,
        font = id.Font.MUSEO_SANS_13PT_REGULAR,
        onChange = function(control, categoryID)
            if self.destroyed or self.clearing or self.categoryField ~= control then return end
            self:ChooseCategory(categoryID)
        end
    })))
    DropdownLayout.FitToWindow(self.categoryField)
    self.iconLabel = Base.Label(body, "Icon", 8, 0, 80, 20, GOLD)
    self.iconSlot = self:Track(prettyui.ItemSlot.new(body, nil, Components.Options({
        backgroundSpriteID = id.Sprite.RS3_ICON_SLOT_STANDARD,
        quantityMode = ui.ObjectQuantityDisplayMode.NEVER, clickthrough = false
    })))
    self.icon = Components.New(ui.Sprite, self.iconSlot.root)
    self.icon:SetPos(4, 4)
    self.icon:SetSize(32, 32)
    self.icon.clickthrough = true
    self.icon.hidden = not Sprites.Apply(self.icon, draft.skill)
    local function chooseIcon()
        if self.destroyed or self.clearing then return end
        self:SyncDraftFields()
        self:Navigate("sprites", {draft = draft})
    end
    self.iconSlot.root:Subscribe(ui.Hook.ONCLICK, function() chooseIcon(); return false end)
    local surface = self.surface
    self.surface = body
    self.spriteButton = self:Button("Choose icon", 0, 0, 120, chooseIcon)
    self.colorLabel = Base.Label(body, "Color", 8, 0, 80, 20, GOLD)
    self.hexField = self:Field(draft.color, 0, 0, 100, 28, 7, function(_, value)
        local color = value:gsub("^#", ""):upper()
        if draft.color == color then return end
        draft.color = color
        if draft.color:match("^%x%x%x%x%x%x$") then
            self.picker:SetValue(tonumber(draft.color, 16) * 256 + 255, false)
            self:LayoutEditor()
        end
    end)
    self.surface = surface
    self.picker = self:Track(prettyui.ColourPicker.new(body, Components.Options({
        width = 28, height = 28, value = tonumber(Settings.NormalizeHex(draft.color), 16) * 256 + 255,
        windowParent = self.parent, windowTitle = "Note color", alphaSlider = false,
        onChange = function(_, value)
            if self.destroyed or self.clearing then return end
            local color = string.format("%06X", math.floor(value / 256) % 0x1000000)
            if draft.color == color then return end
            draft.color = color
            self.hexField:SetText(draft.color, false)
            self:LayoutEditor()
        end
    })))
    local open = self.picker.Open
    function self.picker.Open(picker)
        picker.options.windowX, picker.options.windowY = Overlay.Clamp(self.parent,
            self.window.root.x + 20, self.window.root.y + 30, 220, 300)
        return open(picker)
    end
    local tabs = {}
    for index, name in ipairs(TAB_NAMES) do tabs[index] = {text = TAB_LABELS[index], value = name} end
    self.tabs = prettyui.Tabs.new(self.surface, tabs, Components.Options({x = 8, y = 120, width = self.width,
        height = math.max(60, self.height - 240), scrollable = true, scrollStep = 40,
        onChange = function(_, _, name) self:ActivateTab(name) end}))
    self.pages = {}
    local choices = {}
    for index, name in ipairs(TAB_NAMES) do
        local page = self.tabs:GetPage(index)
        self.pages[name] = page
        local syncScroll = page._scroll.onLayout
        page._scroll.onLayout = function(controller)
            syncScroll(controller)
            if not self.clearing then self:ClipEditorFields() end
        end
        choices[index] = {id = index, label = TAB_LABELS[index], order = index}
    end
    self.sectionCombo = self:Track(prettyui.ComboBox.new(self.surface, Components.Options({
        entries = choices, height = 28, onChange = function(_, index) self:SelectTab(TAB_NAMES[index]) end
    })))
    DropdownLayout.FitToWindow(self.sectionCombo)
    self.subjectLabel = Base.Label(self.pages.note.content, "Subject", 8, 0, self.width, 20, GOLD)
    self.editor = textField(self, self.pages.note.content, draft.text, "Write your subject here", Notes.MAX_TEXT,
        function(value)
            if draft.text == value then return false end
            draft.text = value
            return true
        end)
    self.editorText = {self.titleField.root.text, self.editor.root.text}
    self.surface = self.pages.tracking.content
    self.notificationChecks = self:Track(prettyui.CheckboxButton.new(self.surface, {
        {text = "Chat notifications", value = "notifyChat", selected = draft.notifyChat == true,
            tooltip = "Show chat messages for completed goals, completed collection entries, and quests ready to start."},
        {text = "Popup notifications", value = "notifyPopup", selected = draft.notifyPopup == true,
            tooltip = "Show popups for completed goals, completed collection entries, and quests ready to start."}
    }, Components.Options({inline = true, width = self.width, onChange = function(control, _, key, selected)
        if not self.destroyed and not self.clearing and self.notificationChecks == control then draft[key] = selected == true end
    end})))
    self.notificationChecks.root.clickthrough = true
    for _, item in ipairs(self.notificationChecks.items) do WindowStyle.ApplyTooltip(item.tooltipAttachment) end
    self.surface = surface
    self.footerDivider = self:Track(prettyui.Divider.new(self.surface, Components.Options({width = self.width})))
    self.status = Base.Label(self.surface, draft.editorStatus or "", 8, 0, self.width, 24, 0xFFAA77FF)
    draft.editorStatus = nil
    self.editorButtons = {}
    local function button(name, action)
        local control = self:Button(name, 0, 0, 80, action)
        self.editorButtons[#self.editorButtons + 1] = control
        return control
    end
    self.shareButton = button("Share", function() self:TransferDraft("share") end)
    self.copyButton = button("Copy", function() self:TransferDraft("copy") end)
    self.cancelButton = button("Cancel", function() self:ShowList() end)
    if draft.index then
        self.deleteButton = button("Delete", function() self:ConfirmDelete() end)
    end
    self.saveButton = self:Track(prettyui.FancyButton.new(self.surface, "Save Note", function()
        if not self.destroyed and not self.clearing then self:SaveDraft() end
    end, Components.Options({variant = "positive", width = 130})))
    self.saveButtonWidth, self.saveButtonHeight = self.saveButton.root.width, self.saveButton.root.height
    self.header.onLayout = function() self:ClipEditorFields() end
    self.layout = function() self:LayoutEditor() end
    self:LayoutEditor()
    if draft.trackingExpanded then self:MountTrackingEditor() end
    self:SelectTab(draft.editorTab or "tracking")
    self:LayoutEditor()
end

function Layout.Notifications(self, top)
    local control = self.notificationChecks
    local visible = self.draft.tracking ~= nil or self.trackingEditor ~= nil
    local option = self.trackingEditor and self.trackingEditor:SelectedOption()
    if option and option.statusOnly then visible = false end
    self.notificationControlsVisible = visible
    control.root.hidden = not visible
    control:SetDisabled(not visible)
    if not visible then return top end
    local width = math.max(1, self.pages.tracking.contentWidth - 16)
    local font = config.Font.MUSEO_SANS_13PT_REGULAR
    local x, y, rowHeight = 0, 0, 0
    for _, item in ipairs(control.items) do
        local lines = TextLayout.Lines(item.text, font, math.max(1, width - 22))
        local textWidth = 0
        for _, line in ipairs(lines) do textWidth = math.max(textWidth, font:GetStringWidth(line, true)) end
        local itemWidth = math.min(width, textWidth + 26)
        local itemHeight = math.max(22, #lines * font.baseline + 2)
        if x > 0 and x + itemWidth > width then x, y, rowHeight = 0, y + rowHeight + 4, 0 end
        place(item.row, x, y, itemWidth, itemHeight)
        place(item.box, 0, 4, 14, 14)
        place(item.label, 22, 0, itemWidth - 22, itemHeight)
        item.label.font, item.label.maxLines = id.Font.MUSEO_SANS_13PT_REGULAR, 0
        item.label.alignVertical = ui.AlignMode.TOPLEFT
        rowHeight = math.max(rowHeight, itemHeight)
        x = x + itemWidth + 12
    end
    place(control.root, 8, top, width, y + rowHeight)
    return top + y + rowHeight + 8
end

function Layout.Update(self, heightOnly)
    if not self.editor or not self.editorButtons or self.layingOutEditor then return end
    self.layingOutEditor = true
    local minimumHeight = math.min(self.parent.height, math.max(self.previousMinHeight, 360))
    self.window.chrome.minHeight = minimumHeight
    if self.window.chrome.resize then self.window.chrome.resize.minHeight = minimumHeight end
    local width, height = math.max(1, self.width), self.height
    if self.surface.width ~= self.window.width or self.surface.height ~= height then
        self.surface:SetSize(self.window.width, height)
    end
    local wide = width >= 640
    local secondaryCount = self.deleteButton and 4 or 3
    local secondaryGroupWidth = secondaryCount * 80 + (secondaryCount - 1) * 8
    local compactFooter = width < math.max(520, self.saveButtonWidth + 8 + 90 + 16 + secondaryGroupWidth)
    local footerHeight = compactFooter and 104 or 96
    footerHeight = math.min(footerHeight, math.max(80, math.floor(height * 0.45)))
    local fontName = Base.NoteFont(self.settings)
    if self.editorFontName ~= fontName then
        self.editorFontName, self.editorFont = fontName, config.Font[fontName]
    end
    local font, fontID = self.editorFont, id.Font[fontName]
    local color = tonumber(Settings.NormalizeHex(self.draft.color), 16) * 256 + 255
    self.editorColor = color
    local trackingHeight
    for pass = 1, 2 do
        local titleX, titleY = wide and 72 or 8, wide and 0 or 20
        local titleHeight = 38
        local actionsHeight = 0
        local available = math.max(1, height - footerHeight - actionsHeight - 12)
        local headerContent = titleY + titleHeight + 10 + (wide and 68 or width >= 400 and 124 or 180)
        local headerHeight = math.min(headerContent, math.max(28, math.floor(available * 0.38)))
        local compactTabs = width < 440 or available - headerHeight < 100
        local selectorHeight = compactTabs and 32 or 0
        headerHeight = math.max(1, math.min(headerHeight,
            available - selectorHeight - (compactTabs and 48 or 90)))
        titleHeight = math.min(titleHeight, math.max(1, headerHeight - titleY))
        headerContent = titleY + titleHeight + 10 + (wide and 68 or width >= 400 and 124 or 180)
        place(self.header.root, 8, 6, width, headerHeight)
        contentHeight(self.header, headerContent)
        local headerWidth = self.header.contentWidth - 16
        local titleWidth = math.max(1, headerWidth - (titleX - 8))
        place(self.titleLabel, 8, wide and 6 or 0, 60, 20)
        layoutTitle(self.titleField, font, fontID, color, titleX, titleY, titleWidth, titleHeight)
        local rowY = titleY + titleHeight + 10
        local categoryWidth, iconWidth, colorWidth
        local iconX, iconY, colorX, colorY
        if wide then
            categoryWidth = math.floor((headerWidth - 16) * 0.40)
            iconWidth = math.floor((headerWidth - 16) * 0.34)
            colorWidth = headerWidth - categoryWidth - iconWidth - 16
            iconX, iconY = 8 + categoryWidth + 8, rowY
            colorX, colorY = iconX + iconWidth + 8, rowY
        elseif width >= 400 then
            categoryWidth = headerWidth
            iconWidth = math.floor((headerWidth - 8) * 0.55)
            colorWidth = headerWidth - iconWidth - 8
            iconX, iconY, colorX, colorY = 8, rowY + 56, iconWidth + 16, rowY + 56
        else
            categoryWidth, iconWidth, colorWidth = headerWidth, headerWidth, headerWidth
            iconX, iconY, colorX, colorY = 8, rowY + 56, 8, rowY + 124
        end
        place(self.categoryLabel, 8, rowY, categoryWidth, 18)
        place(self.categoryField.root, 8, rowY + (wide and 26 or 20), categoryWidth, 28)
        place(self.iconLabel, iconX, iconY, iconWidth, 18)
        place(self.iconSlot.root, iconX, iconY + 20, 40, 40)
        place(self.spriteButton.root, iconX + 48, iconY + 26, iconWidth - 48, 28)
        place(self.colorLabel, colorX, colorY, colorWidth, 18)
        place(self.picker.root, colorX, colorY + (width >= 400 and 26 or 20), 28, 28)
        place(self.hexField.root, colorX + 36, colorY + (width >= 400 and 26 or 20), colorWidth - 36, 28)
        local tabY = headerHeight + 12
        self.sectionCombo.root.hidden = not compactTabs
        place(self.sectionCombo.root, 8, tabY, width, 28)
        tabY = tabY + selectorHeight
        place(self.tabs.root, 8, tabY, width, math.max(1, height - footerHeight - tabY - actionsHeight))
        if self.trackingEditor then
        end
        self.tabs.divider.hidden = compactTabs
        for _, tab in ipairs(self.tabs.tabs) do tab.visual.hidden, tab.hit.hidden = compactTabs, compactTabs end
        if self.compactTabs ~= compactTabs then
            self.compactTabs = compactTabs
            self.tabs.content:SetPos(0, compactTabs and 0 or 42)
            self.tabs.content:SetSize(0, compactTabs and 0 or -42, 1.0, 1.0)
        end
        local activePage = self.pages[self.activeTab or "note"]
        contentHeight(activePage, activePage._scroll.requestedContentHeight)
        local pageWidth = activePage.contentWidth
        if not self.activeTab or self.activeTab == "note" then
            local note = self.pages.note
            contentHeight(note, note._scroll.root.height)
            local noteWidth = math.max(1, note.contentWidth - 16)
            local subjectHeight = math.max(1, note.viewport.height - 36)
            local subjectContent = textHeight(self.editor, font, math.max(1, noteWidth - 32))
            place(self.subjectLabel, 8, 4, noteWidth, 20)
            layoutText(self.editor, font, fontID, color, 8, 28, noteWidth, subjectHeight, subjectContent,
                not heightOnly and pass == 1)
            contentHeight(note, 28 + subjectHeight + 8)
        end
        if self.activeTab == "tracking" then
            local tracking = self.pages.tracking
            self.editorWidth = math.max(1, tracking.contentWidth - 16)
            local bottom = 0
            if self.trackingEditor then
                local footerY = self.trackingEditor.footerY
                local notificationsHeight = Layout.Notifications(self, footerY) - footerY
                local changed = self.trackingEditor.width ~= self.editorWidth
                    or self.trackingEditor.footerHeight ~= notificationsHeight
                self.trackingEditor.footerHeight = notificationsHeight
                if changed then self.trackingEditor:SetBounds(0, 0, self.editorWidth) end
                local notificationRoot = self.notificationChecks.root
                place(notificationRoot, 8, self.trackingEditor.footerY, notificationRoot.width, notificationRoot.height)
                bottom = 8 + self.trackingEditor.height
            else bottom = Layout.Notifications(self, bottom) end
            contentHeight(tracking, bottom)
            trackingHeight = 40 + headerContent + 12 + selectorHeight + (compactTabs and 0 or 42)
                + bottom + actionsHeight + footerHeight
        end
        if self.activeTab == "gear" and self.gearEditor then
            local gearWidth = math.max(1, self.pages.gear.contentWidth - 16)
            if self.gearEditor.width ~= gearWidth then self.gearEditor:SetBounds(8, 8, gearWidth) end
            contentHeight(self.pages.gear, self.gearEditor.height + 16)
        end
        if self.activeTab == "actionBar" and self.actionBarEditor then
            local barWidth = math.max(1, self.pages.actionBar.contentWidth - 16)
            if self.actionBarEditor.width ~= barWidth then self.actionBarEditor:SetBounds(8, 8, barWidth) end
            contentHeight(self.pages.actionBar, self.actionBarEditor.height + 16)
        end
        if activePage.contentWidth == pageWidth then break end
    end
    self.footerDivider.root.hidden = height < 320
    place(self.footerDivider.root, 8, height - footerHeight - 28, width, 60)
    local compact = compactFooter
    if self.compactFooter ~= compact then
        self.compactFooter = compact
        self.saveButton:SetText(compact and "Save" or "Save Note")
    end
    for _, button in ipairs(self.editorButtons) do button.content.font = id.Font.MUSEO_SANS_13PT_REGULAR end
    local statusY = height - (compact and 104 or 70)
    place(self.status, 8, math.max(height - footerHeight, statusY), width, 24)
    local group = {self.shareButton, self.copyButton, self.deleteButton, self.cancelButton}
    local ordered = {}
    for index = 1, 4 do if group[index] then ordered[#ordered + 1] = group[index] end end
    if compact then
        local secondaryWidth = math.max(1, math.min(80, math.floor((width - (secondaryCount - 1) * 8) / secondaryCount)))
        local groupWidth = secondaryCount * secondaryWidth + (secondaryCount - 1) * 8
        local secondaryX = width + 8 - groupWidth
        for index, control in ipairs(ordered) do
            place(control.root, secondaryX + (index - 1) * (secondaryWidth + 8), height - 34, secondaryWidth, 28)
        end
        local saveEdges = self.saveButton.left.width + self.saveButton.right.width
        local minimumSaveWidth = saveEdges + config.Font.CINZEL_13PT_BOLD:GetStringWidth("Save", false) + 4
        local saveWidth = math.max(math.floor((width - 8) / 2), minimumSaveWidth)
        saveWidth = math.min(saveWidth, math.max(1, width - 16))
        place(self.saveButton.root, 8, height - 70, saveWidth, self.saveButtonHeight)
    else
        place(self.saveButton.root, 8, height - 34, self.saveButtonWidth, self.saveButtonHeight)
        local secondaryX = width + 8 - secondaryGroupWidth
        for index, control in ipairs(ordered) do
            place(control.root, secondaryX + (index - 1) * 88, height - 34, 80, 28)
        end
    end
    self:RestoreScrolls()
    self.layingOutEditor = false
    self:ClipEditorFields()
    if trackingHeight and self.callbacks.fitEditor then
        self.callbacks.fitEditor(trackingHeight)
        if self.height ~= self.window.height then self:Resize(self.window.width - 16, self.window.height) end
    end
end

local function clip(control, scroll, height)
    local root = control.root or control
    local top = root.y - scroll
    root.hidden = top < 0 or top + root.height > height
    if root.hidden and control._Close then control:_Close() end
end

function Layout.Clip(self)
    if not self.editor or not self.pages or self.layingOutEditor then return end
    local header = self.header
    for _, control in ipairs({self.titleField, self.categoryField, self.iconSlot, self.spriteButton, self.hexField, self.picker}) do
        clip(control, header.scrollY, header.viewport.height)
    end
    local note = self.pages.note
    clip(self.editor, note.scrollY, note.viewport.height)
    local tracking = self.pages.tracking
    if self.trackingEditor then self.trackingEditor:Clip(tracking.scrollY, tracking.viewport.height) end
    for _, item in ipairs(self.notificationChecks.items) do
        local top = self.notificationChecks.root.y + item.row.y - tracking.scrollY
        item.row.hidden = not self.notificationControlsVisible or top < 0 or top + item.row.height > tracking.viewport.height
    end
    if self.gearEditor then self.gearEditor:Clip(self.pages.gear.scrollY, self.pages.gear.viewport.height) end
    if self.actionBarEditor then self.actionBarEditor:Clip(self.pages.actionBar.scrollY, self.pages.actionBar.viewport.height) end
end

return Layout
