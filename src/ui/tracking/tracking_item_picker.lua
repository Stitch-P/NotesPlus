local Components = require("src/ui/shared/components")
local Tracking = require("src/tracking/model")
local Vars = require("src/tracking/core/vars")
local Timers = require("src/tracking/features/boss_timers")
local Pouch = require("src/tracking/core/pouch")
local WindowStyle = require("src/ui/window/window_style")
local Detached = require("src/ui/shared/detached_ui")
local ComponentTooltip = require("src/ui/tracking/component_perk_tooltip")

local Picker = {}
Picker.__index = Picker

local SLOT, CELL_WIDTH, CELL_HEIGHT = 32, 48, 54
local TARGET_WIDTH, TARGET_HEIGHT = 80, 80
local MAX_VISIBLE = 96
local GREEN = 0x55FF55FF

local function sizeSlot(control)
    control.root:SetSize(SLOT, SLOT)
    control.background:SetSize(SLOT, SLOT)
    for _, name in ipairs({"item", "dragItem", "disabledOverlay"}) do
        local sprite = control[name]
        if sprite then
            sprite:SetPos(3, 3)
            sprite:SetSize(SLOT - 6, SLOT - 6)
        end
    end
end

local function plain(value)
    return tostring(value or ""):gsub("<[Bb][Rr]%s*/?>", " "):gsub("<", "["):gsub(">", "]"):gsub("[%c]", " ")
end

local function multiline(value)
    local lines = {}
    for line in (tostring(value or ""):gsub("<[Bb][Rr]%s*/?>", "\n"):gsub("\r\n", "\n"):gsub("\r", "\n") .. "\n"):gmatch("(.-)\n") do
        lines[#lines + 1] = plain(line)
    end
    return table.concat(lines, "<br>")
end

local function keyOf(option)
    return type(option) == "table" and (option.key or option.varName
        or option.currency and option.currency.var or option.variable) or option
end

local function copyTargets(targets)
    local result = {}
    for key, value in pairs(targets or {}) do
        if type(key) == "string" and (type(value) == "string" or type(value) == "number") then
            result[key] = tostring(value)
        end
    end
    return result
end

local function contextOf(parent)
    while parent do
        local context = prettyui.Tooltip.getContext(parent)
        if context then return context end
        parent = parent.parent
    end
end

local function position(target, parent)
    local point, base = target.xyGlobal, parent.xyGlobal
    local x, y = point.x - base.x, point.y - base.y
    local ancestor = target.parent
    while ancestor and ancestor ~= parent do
        x = x - (ancestor.scrollX or 0)
        y = y - (ancestor.scrollY or 0)
        ancestor = ancestor.parent
    end
    return x, y
end

local function read(category, group, option)
    local ok, progress = pcall(Tracking.Preview, category, group, option)
    return ok and progress or {}
end

-- The price under an item, kept short for the cell: "750 pts", "9.3k", "1.4m" (the tooltip has the full price and currency).
local function priceText(price, unit)
    unit = unit == "points" and "pts" or unit or "pts"
    local function short(value, divisor, suffix)
        return string.format("%.1f", value / divisor):gsub("%.0$", "") .. suffix
    end
    local text = price >= 1e6 and short(price, 1e6, "m") or price >= 1000 and short(price, 1e3, "k") or tostring(math.floor(price))
    local full = text .. " " .. unit
    return #full <= 8 and full or text
end

local function quantity(value)
    if type(value) ~= "number" then return "?" end
    if value >= 1000000 then return tostring(math.floor(value / 1000000)) .. "M" end
    if value >= 10000 then return tostring(math.floor(value / 1000)) .. "K" end
    return tostring(math.floor(value))
end

function Picker.new(parent, options, selectedKeys, callbacks, settings)
    settings = settings or {}
    local category = settings.category or "Invention"
    local singular, plural = Tracking.CollectionNames(category, settings.group)
    local noun = settings.noun or plural
    local self = setmetatable({options = options or {}, selected = {}, pending = {}, cells = {},
        callbacks = callbacks or {}, maxSelected = settings.maxSelected or 40, showStatus = settings.showStatus ~= false,
        unsupported = {}, unavailableKeys = {},
        category = category, group = settings.group, noun = noun,
        words = category == "Slayer" and {unavailable = "Drop status is not available yet.", done = "Obtained", notDone = "Not obtained yet"}
            or category == "Training" and {unavailable = "Floor status is not available yet.", done = "Completed", notDone = "Not completed yet"}
            or {unavailable = "Unlock status is not available yet.", done = "Unlocked", notDone = "Not unlocked yet"},
        levels = Tracking.IsSkillLevels(category, settings.group) and not Tracking.IsSkillXP(category, settings.group), xp = Tracking.IsSkillXP(category, settings.group),
        research = Tracking.CollectionFixedTarget(category, settings.group) ~= nil,
        nounSingular = settings.nounSingular or singular, targets = copyTargets(settings.targets),
        defaultTarget = tostring(settings.defaultTarget or Tracking.CollectionDefaultTarget(category, settings.group)),
        targetFields = {}, targetOrder = {}}, Picker)
    self.inlineTargets = false
    for _, option in ipairs(self.options) do
        if self:_TargetShown(option) then self.inlineTargets = true; break end
    end
    self.cellWidth = self.inlineTargets and TARGET_WIDTH or CELL_WIDTH
    self.cellHeight = self.inlineTargets and TARGET_HEIGHT or CELL_HEIGHT
    self.maxViewHeight = settings.viewHeight or self.cellHeight * 4 + 2
    self.viewHeight = self.maxViewHeight
    self.height = self.viewHeight + (self.showStatus and 24 or 0)
    self.unavailableCount = 0
    for _, option in ipairs(self.options) do
        if option.available == false then
            self.unavailableKeys[keyOf(option)] = true
            self.unavailableCount = self.unavailableCount + 1
        end
    end
    self.root = Components.Host(parent)
    self.root.clickthrough = true
    local context = contextOf(parent)
    local tooltipParent = context and context.parent or parent
    self.tooltipContext = prettyui.Tooltip.registerContext(self.root, tooltipParent, function(target)
        return position(target, tooltipParent)
    end, context)
    self.view = prettyui.SimpleView.new(self.root, Components.Options({x = 0, y = 0,
        width = 1, height = self.viewHeight, scrollStep = self.cellHeight}))
    self.view.isVisible = function() return self:_ViewVisible() end
    self.view.onLayout = function() self:DrawCells() end
    self.tooltipTarget = Components.New(ui.Layer, self.view.content)
    self.tooltipTarget.hidden, self.tooltipTarget.clickthrough = true, true
    self.sharedTooltip = prettyui.Tooltip.attach(self.tooltipTarget, self.view.content,
        Components.Options({text = self.nounSingular, placement = "above", maxWidth = 300}))
    WindowStyle.ApplyTooltip(self.sharedTooltip, function() self:HideTooltip() end)
    if self.category == "Invention" then ComponentTooltip.Prepare(self.sharedTooltip) end
    self.status = prettyui.Text.new(self.root, Components.Options({text = "", width = 1, height = 22,
        font = id.Font.MUSEO_SANS_13PT_REGULAR, colour = 0xD8D8D8FF, shadowed = false}))
    self.status.clickthrough = true
    self.status.hidden = not self.showStatus
    self:SetSelected(selectedKeys or {})
    self:SetBounds(settings.x or 0, settings.y or 0, settings.width or 300)
    return self
end

function Picker:_TargetEditable(option)
    return option and option.available ~= false
        and Tracking.CollectionTargetEditable(self.category, self.group, option) == true
end

function Picker:_TargetShown(option)
    return option and option.available ~= false
        and (self:_TargetEditable(option) or (self.category == "Bossing" or self.category == "Slayer") and option.kind == "item")
end

-- The target a goal starts with: its own price when it has one (an unlock's cost), else the shared default.
function Picker:_StartTarget(option)
    if self.defaultTarget == "" and type(option.defaultTarget) == "number" and option.defaultTarget > 1 then
        return tostring(option.defaultTarget)
    end
    return self.defaultTarget
end

function Picker:_InitializeTargets()
    for _, option in ipairs(self.options) do
        local key = keyOf(option)
        if self.selected[key] and self:_TargetShown(option) then
            if not self:_TargetEditable(option) then self.targets[key] = "1"
            elseif self.targets[key] == nil then self.targets[key] = self:_StartTarget(option) end
        end
    end
end

function Picker:_EnsureTargets()
    self:_InitializeTargets()
    for _, option in ipairs(self.options) do
        local key = keyOf(option)
        if self.selected[key] and self:_TargetShown(option) then
            local entry = self.targetFields[key]
            if not entry then
                entry = {key = key, fixed = not self:_TargetEditable(option)}
                if entry.fixed then
                    entry.status = prettyui.Text.new(self.view.content, Components.Options({text = "", width = self.cellWidth - 8,
                        height = 26, font = id.Font.MUSEO_SANS_13PT_REGULAR, colour = 0xD8D8D8FF,
                        shadowed = false, alignHorizontal = ui.AlignMode.CENTRE}))
                    entry.status.clickthrough = true
                    entry.root = entry.status
                else
                    entry.control = prettyui.TextField.new(self.view.content, Components.Options({width = self.cellWidth - 8,
                        height = 26, text = self.targets[key], maxLength = 16,
                        font = id.Font.MUSEO_SANS_13PT_REGULAR,
                        placeholder = (self.category == "Clues" or option.clueShop) and tostring(option.defaultTarget or (option.kind == "item" and "1" or "Target"))
                            or Tracking.CollectionHint(self.category, self.group) and "1" or self.levels and "Level" or self.xp and "XP" or "Target",
                        onChange = function(control, _, content)
                            if self.destroyed then return end
                            self.targets[key] = tostring(content or control:GetText())
                            if self.callbacks.targetChanged then self.callbacks.targetChanged(key, self.targets[key]) end
                        end}))
                    WindowStyle.ApplyInput(entry.control.root)
                    entry.control.root.text.maxLines = 1
                    entry.control.root.scrollbar.visible = false
                    entry.control.root.scrollbar.size = 0
                    entry.control.root:Subscribe(ui.Hook.ONCLICK, function()
                        if not self.destroyed and self.callbacks.focus then self.callbacks.focus(entry.control) end
                        return true
                    end)
                    entry.control.root:Subscribe(ui.Hook.ONSCROLLWHEEL, function(_, rotation)
                        local before = self.view.scrollY
                        self.view:ScrollBy(rotation * self.cellHeight)
                        return self.view.scrollY == before
                    end)
                    entry.root = entry.control.root
                end
                self.targetFields[key] = entry
                self.targetOrder[#self.targetOrder + 1] = key
                entry.root.hidden = true
            elseif entry.control and entry.control:GetText() ~= self.targets[key] then
                entry.control:SetText(self.targets[key], false)
            end
        end
    end
    local index = 1
    while #self.targetOrder > MAX_VISIBLE and index <= #self.targetOrder do
        local key = self.targetOrder[index]
        if not self.selected[key] then
            local entry = self.targetFields[key]
            if entry.control then entry.control:Destroy() else entry.root:Destroy() end
            self.targetFields[key] = nil
            table.remove(self.targetOrder, index)
        else index = index + 1 end
    end
end

function Picker:_HideTarget(entry)
    entry.root.hidden = true
    if entry.control then entry.control:_SetContentClipped(true) end
end

function Picker:_PositionTarget(cell, x, y)
    local entry = cell.option and self.targetFields[keyOf(cell.option)]
    if not entry or not self.selected[entry.key] then return end
    cell.targetEntry = entry
    entry.root:SetPos(x + 4, y + SLOT + 20)
end

function Picker:_ViewVisible()
    if self.destroyed or self.root.hidden then return false end
    if not self.clipHeight then return true end
    local top = self.root.y + (self.clipOffset or 0) - self.clipScroll
    return top >= 0 and top + self.viewHeight <= self.clipHeight
end

function Picker:HideTooltip()
    self.hoveredCell = nil
    if self.sharedTooltip then self.sharedTooltip:Hide() end
end

function Picker:ShowCellTooltip(cell)
    if self.destroyed or self.root.hidden or cell.control.root.hidden or not cell.option then return end
    self:HideTooltip()
    self.hoveredCell = cell
    self.tooltipTarget:SetPos(cell.control.root.x, cell.control.root.y)
    self.tooltipTarget:SetSize(cell.control.root.width, cell.control.root.height)
    local option, progress = cell.option, cell.progress or {}
    local available = option.available ~= false
    local current = type(progress.current) == "number" and Vars.withCommas(progress.current) or "Unavailable"
    local ok, perks = pcall(Tracking.ComponentPerks, option)
    if ok and perks then
        local title = plain(option.label or keyOf(option))
        local details
        if self.research then
            details = {progress.current == nil and self.words.unavailable
                or progress.complete and self.words.done or self.words.notDone}
        else title = title .. ": " .. current end
        if ComponentTooltip.Set(self.sharedTooltip, title, perks,
            {details = details, sources = Tracking.ComponentSources(option), maxWidth = 300}) then
            self.sharedTooltip:Show()
            return
        end
    end
    ComponentTooltip.Clear(self.sharedTooltip)
    local state = not available and "Completion tracking is not available yet."
        or self.selected[keyOf(option)] and "<col=55FF55>Selected</col>" or "Click to select"
    local description = available and option.description and multiline(option.description) or ""
    local detail = option.kind == "timer" and ("Best time: " .. (type(progress.current) == "number" and progress.current > 0
            and Timers.format(progress.current, option.varName) or "no time yet"))
        or (self.category == "Clues" or option.price) and option.piece and (progress.current == nil and "Current value is not available yet."
        or progress.owned and "Already unlocked"
        or option.piece.noBalance and ("Costs " .. Vars.withCommas(option.price) .. " " .. (option.priceUnit or "points"))
        or "You have " .. current .. " " .. (option.priceUnit or "points")
            .. (option.defaultTarget and " (cost: " .. Vars.withCommas(option.defaultTarget) .. ")"
                .. (type(progress.current) == "number" and (progress.current >= option.defaultTarget
                    and " - ready to unlock" or " - " .. Vars.withCommas(option.defaultTarget - progress.current) .. " more needed") or "") or ""))
        or self.research and (progress.current == nil and self.words.unavailable
        or progress.complete and self.words.done or self.words.notDone)
        or (self.xp and "Current XP: " or self.levels and "Current level: " or (self.category == "Bossing" or self.category == "Slayer" or self.category == "Clues") and "In your item log: " or (self.category == "Production" or self.category == "Training" and not (option and option.tileText) or self.category == "Gathering") and "In your backpack: " or "You have: ") .. current
    -- A pouch currency shows "?" until the game has sent the pouch (when it is opened): say so.
    local pouchNote = available and type(progress.current) ~= "number" and option.currency and Pouch.reason(option.currency.var)
    -- Titles show as the game shows them, in their own colours (the text is made safe where it is read).
    self.sharedTooltip:SetText(plain(option.label or keyOf(option)) .. (option.preview and ("<br>" .. option.preview) or "")
        .. (available and "<br>" .. detail or "")
        .. (description ~= "" and "<br>" .. description or "") .. (pouchNote and ("<br>" .. pouchNote) or "") .. "<br>" .. state)
    self.sharedTooltip:Show()
end

function Picker:_NewCell()
    local cell = {}
    cell.control = prettyui.ItemSlot.new(self.view.content, nil, Components.Options({clickthrough = false,
        quantityMode = ui.ObjectQuantityDisplayMode.NEVER}))
    sizeSlot(cell.control)
    cell.image = Components.New(ui.Sprite, cell.control.root)
    cell.image:SetPos(3, 3)
    cell.image:SetSize(SLOT - 6, SLOT - 6)
    cell.image.rgba, cell.image.clickthrough, cell.image.hidden = 0xFFFFFFFF, true, true
    -- A 3D model for options that have one instead of an item or sprite (Fort Forinthry buildings).
    local okModel, model = pcall(function() return Components.New(ui.Model, cell.control.root) end)
    if okModel and model then
        model:SetPos(2, 2)
        model:SetSize(SLOT - 4, SLOT - 4)
        model.clickthrough, model.hidden = true, true
        cell.model = model
    end
    cell.border = Components.New(ui.Rectangle, cell.control.root)
    cell.border:SetSize(SLOT, SLOT)
    cell.border.fill, cell.border.rgba, cell.border.clickthrough = false, GREEN, true
    cell.border.outlineThickness = 2
    cell.count = prettyui.Text.new(self.view.content, Components.Options({text = "", width = self.cellWidth, height = 18,
        font = id.Font.MUSEO_SANS_13PT_REGULAR, colour = 0xFFFFFFFF, shadowed = true,
        alignHorizontal = ui.AlignMode.CENTRE}))
    cell.count.clickthrough = true
    cell.control.root:Subscribe(ui.Hook.ONCLICK, function()
        if not self.destroyed and not self.root.hidden and not cell.control.root.hidden
            and cell.option and cell.option.available ~= false then
            self.pending[#self.pending + 1] = keyOf(cell.option)
        end
        return false
    end)
    cell.control.root:Subscribe(ui.Hook.ONMOUSEOVER, function()
        self:ShowCellTooltip(cell)
        return true
    end)
    cell.control.root:Subscribe(ui.Hook.ONMOUSELEAVE, function()
        if self.hoveredCell == cell then self:HideTooltip() end
        return true
    end)
    cell.control.root:Subscribe(ui.Hook.ONSCROLLWHEEL, function(_, rotation)
        local before = self.view.scrollY
        self.view:ScrollBy(rotation * self.cellHeight)
        return self.view.scrollY == before
    end)
    self.cells[#self.cells + 1] = cell
    return cell
end

function Picker:_RefreshCell(cell)
    local option = cell.option
    if not option then return end
    local ok, ref = pcall(Tracking.Icon, option)
    if not ok then ref = nil end
    -- Options shown as text only (Daemonheim floors): the number is written on the tile and no picture is used.
    if option.tileText then ref = nil end
    if not ref and not option.tileText then
        local okGroup, groupRef = pcall(Tracking.GroupIcon, self.category, self.group)
        if okGroup then ref = groupRef end
    end
    if not ref and (self.category == "Currencies" or option.available == false) then
        ok, ref = pcall(Tracking.CategoryIcon, self.category)
        if not ok then ref = nil end
    end
    local modelId = option.modelId
    if cell.model and modelId ~= cell.shownModel then
        cell.shownModel = modelId
        local shown = false
        if modelId then
            shown = pcall(function()
                local types = ui.ModelType
                local kind = types and (types.MODEL or types.LOC_MODEL or types.OBJ_MODEL or types.RAW_MODEL or types.BASE_MODEL)
                if not kind then error("no model type") end
                cell.model:SetModel(kind, modelId)
            end)
        end
        cell.model.hidden = not shown
        cell.modelOn = shown
    end
    if cell.modelOn then ref = nil end
    local signature = type(ref) == "table" and "sprite:" .. tostring(ref.sprite) or "item:" .. tostring(ref)
    if cell.iconSignature ~= signature then
        cell.iconSignature = signature
        cell.image.hidden = true
        if type(ref) == "number" then cell.control:SetObject({id = ref}, 1)
        else
            cell.control:SetObject(nil)
            if type(ref) == "table" and ref.sprite ~= nil then
                cell.image.sprite, cell.image.hidden = ref.sprite, false
            end
        end
        sizeSlot(cell.control)
    end
    if option.tileText then
        if not cell.tile then
            cell.tile = prettyui.Text.new(cell.control.root, Components.Options({text = "", width = SLOT, height = 20,
                font = id.Font.MUSEO_SANS_13PT_REGULAR, colour = 0xFFFFFFFF, shadowed = true, alignHorizontal = ui.AlignMode.CENTRE}))
            cell.tile.clickthrough = true
        end
        cell.tile.content = option.tileText
        cell.tile:SetPos(0, math.floor((SLOT - 20) / 2))
        cell.tile.hidden = false
    elseif cell.tile then
        cell.tile.hidden = true
    end
    local available = option.available ~= false
    cell.progress = available and read(self.category, self.group, option) or {}
    if cell.targetEntry and cell.targetEntry.status then
        cell.targetEntry.status.content = cell.progress.current == nil and "Unavailable"
            or cell.progress.complete and "Owned" or "Not owned"
    end
    -- A reward shop piece shows its price (the number under it is not how many you can buy); the tooltip has your balance.
    cell.count.content = option.kind == "timer" and Timers.format(cell.progress.current, option.varName)
        or (self.category == "Clues" or option.price) and option.piece and cell.progress.owned and "Owned"
        or option.price and option.piece and priceText(option.price, option.priceUnit)
        or self.category == "Clues" and option.piece and option.defaultTarget and Vars.withCommas(option.defaultTarget) .. " pts"
        or self.research and "" or (self.inlineTargets and self.levels and "Level " or "")
        .. quantity(cell.progress.current)
    local selected = available and self.selected[keyOf(option)] == true
    cell.border.hidden = not selected
    local colour = available and 0xFFFFFFFF or 0xFFFFFF66
    local alpha = not available and 0.4 or self.research and (cell.progress.complete and 1 or 0.35) or selected and 1 or 0.8
    if cell.control.item then
        cell.control.item.rgba = colour
        cell.control.item.alpha = alpha
    end
    cell.image.rgba = colour
    cell.image.alpha = alpha
end

function Picker:_Status()
    local count, unavailable = 0, self.unavailableCount
    for _ in pairs(self.selected) do count = count + 1 end
    for _, option in ipairs(self.unsupported) do
        if self.selected[option.key] then unavailable = unavailable + 1 end
    end
    self.selectedCount = count
    self.status.content = count .. " / " .. self.maxSelected .. " " .. self.noun .. " selected"
        .. (unavailable > 0 and " (" .. unavailable .. " unavailable)" or "")
end

function Picker:DrawCells()
    if self.destroyed or not self.columns then return end
    self:HideTooltip()
    local activeTargets = {}
    local firstRow = math.floor(self.view.scrollY / self.cellHeight)
    local count = math.min(#self.options, MAX_VISIBLE,
        self.columns * (math.ceil(self.viewHeight / self.cellHeight) + 1))
    local left = 0
    for slot = 1, count do
        local cell = self.cells[slot] or self:_NewCell()
        local index = firstRow * self.columns + slot
        cell.option, cell.optionIndex = self.options[index], index
        cell.targetEntry = nil
        local x = left + ((index - 1) % self.columns) * self.cellWidth
        local y = math.floor((index - 1) / self.columns) * self.cellHeight + 2
        cell.control.root:SetPos(x + (self.cellWidth - SLOT) / 2, y)
        cell.count:SetPos(x, y + SLOT + 2)
        self:_PositionTarget(cell, x, y)
        if cell.targetEntry then activeTargets[cell.targetEntry.key] = true end
        self:_RefreshCell(cell)
        self:_ClipCell(cell)
    end
    for index = count + 1, #self.cells do
        local cell = self.cells[index]
        cell.option, cell.targetEntry = nil, nil
        cell.control.root.hidden, cell.count.hidden = true, true
    end
    for key, entry in pairs(self.targetFields) do
        if not activeTargets[key] then self:_HideTarget(entry) end
    end
end

function Picker:_ClipCell(cell)
    local top = cell.control.root.y - self.view.scrollY
    local extent = cell.targetEntry and self.cellHeight - 2 or SLOT + 20
    local bottom = top + extent
    local visible = cell.option ~= nil and not self.root.hidden and top >= 0 and bottom <= self.viewHeight
    if visible and self.clipHeight then
        local outerTop = self.root.y + (self.clipOffset or 0) + top - self.clipScroll
        visible = outerTop >= 0 and outerTop + extent <= self.clipHeight
    end
    cell.control.root.hidden, cell.count.hidden = not visible, not visible or self.research
    if cell.targetEntry then
        local entry = cell.targetEntry
        entry.root.hidden = not visible
        if entry.control then entry.control:_SetContentClipped(not visible) end
    end
end

function Picker:SetBounds(x, y, width)
    if self.destroyed then return end
    width = math.max(1, math.floor(width))
    self.root:SetPos(x, y)
    local maxColumns = math.max(1, math.floor(MAX_VISIBLE / (math.ceil(self.maxViewHeight / self.cellHeight) + 1)))
    self.columns = math.max(1, math.min(maxColumns, math.floor((width - 18) / self.cellWidth)))
    local contentHeight = math.ceil(#self.options / self.columns) * self.cellHeight + 2
    self.viewHeight = math.min(self.maxViewHeight, contentHeight)
    self.height = self.viewHeight + (self.showStatus and 24 or 0)
    self.root:SetSize(width, self.height)
    self.view:SetSize(width, self.viewHeight)
    self.status:SetPos(0, self.viewHeight + 2)
    self.status:SetSize(width, 22)
    self.view:SetContentHeight(contentHeight)
    self:DrawCells()
end

function Picker:SetSelected(keys)
    if self.destroyed then return end
    local requested = {}
    for key, value in pairs(keys or {}) do
        local selectedKey = value == true and key or keyOf(value)
        if selectedKey ~= nil and value ~= false then requested[selectedKey] = true end
    end
    self.selected, self.pending, self.unsupported = {}, {}, {}
    local known = {}
    local count = 0
    for _, option in ipairs(self.options) do
        local key = keyOf(option)
        known[key] = true
        if requested[key] and option.available ~= false and count < self.maxSelected then
            self.selected[key], count = true, count + 1
        end
    end
    local unsupportedKeys = {}
    for key in pairs(requested) do
        if type(key) == "string" and not known[key] then unsupportedKeys[#unsupportedKeys + 1] = key end
    end
    table.sort(unsupportedKeys)
    for _, key in ipairs(unsupportedKeys) do
        if count >= self.maxSelected then break end
        self.selected[key], count = true, count + 1
        self.unsupported[#self.unsupported + 1] = {key = key, varName = key, label = key}
    end
    self:_Status()
    self.controlsDirty = nil
    self:_EnsureTargets()
    if self.columns then self:DrawCells() end
end

function Picker:FlushSelection()
    if self.destroyed or #self.pending == 0 then return end
    local pending, changed, limited = self.pending, false, false
    self.pending = {}
    for _, key in ipairs(pending) do
        if not self.unavailableKeys[key] then
            if self.selected[key] then
                self.selected[key], self.selectedCount, changed = nil, self.selectedCount - 1, true
            elseif self.selectedCount < self.maxSelected then
                self.selected[key], self.selectedCount, changed = true, self.selectedCount + 1, true
            else limited = true end
        end
    end
    self:_Status()
    self:_InitializeTargets()
    self.controlsDirty = true
    if changed and self.callbacks.changed then self.callbacks.changed(self:GetSelected(), pending[#pending]) end
    if limited and self.callbacks.limit then self.callbacks.limit(self.maxSelected) end
end

function Picker:GetSelected()
    self:FlushSelection()
    local result = {}
    for _, option in ipairs(self.options or {}) do
        if option.available ~= false and self.selected[keyOf(option)] then result[#result + 1] = option end
    end
    for _, option in ipairs(self.unsupported or {}) do
        if self.selected[option.key] then result[#result + 1] = option end
    end
    return result
end

function Picker:GetTargets()
    self:FlushSelection()
    for key, entry in pairs(self.targetFields) do self.targets[key] = entry.fixed and "1" or entry.control:GetText() end
    return copyTargets(self.targets)
end

function Picker:SetTargets(targets)
    if self.destroyed then return end
    self.targets = copyTargets(targets)
    for key, entry in pairs(self.targetFields) do
        local text = entry.fixed and "1" or self.targets[key]
        if entry.fixed then self.targets[key] = text end
        if text == nil then
            local found = {}
            for _, option in ipairs(self.options) do if keyOf(option) == key then found = option break end end
            text = self:_StartTarget(found)
            self.targets[key] = text
        end
        if entry.control and entry.control:GetText() ~= text then entry.control:SetText(text, false) end
    end
    self:_EnsureTargets()
    if self.columns then self:DrawCells() end
end

function Picker:SetDefaultTarget(text)
    if self.destroyed then return end
    self.defaultTarget = tostring(text or "")
end

function Picker:SetAllTargets(text)
    if self.destroyed then return end
    self:FlushSelection()
    text = tostring(text or "")
    for _, option in ipairs(self.options) do
        local key = keyOf(option)
        if self.selected[key] and self:_TargetEditable(option) then
            self.targets[key] = text
            local entry = self.targetFields[key]
            if entry and entry.control:GetText() ~= text then entry.control:SetText(text, false) end
            if self.callbacks.targetChanged then self.callbacks.targetChanged(key, text) end
        end
    end
end

function Picker:Refresh()
    if self.destroyed then return end
    for _, cell in ipairs(self.cells) do self:_RefreshCell(cell) end
    if self.hoveredCell then self:ShowCellTooltip(self.hoveredCell) end
end

function Picker:Clip(scrollY, viewportHeight, contentOffset)
    if self.destroyed then return end
    self.clipScroll, self.clipHeight, self.clipOffset = scrollY or 0, viewportHeight, contentOffset or 0
    self:HideTooltip()
    for _, cell in ipairs(self.cells) do self:_ClipCell(cell) end
    self.view:Refresh()
end

function Picker:Tick()
    if self.destroyed then return end
    self:FlushSelection()
    if self.controlsDirty then
        self.controlsDirty = nil
        self:_EnsureTargets()
        self:DrawCells()
    end
    if self.root.hidden then self:HideTooltip(); return end
    self.refreshTicks = (self.refreshTicks or 0) + 1
    if self.refreshTicks >= 20 then self.refreshTicks = 0; self:Refresh() end
end

function Picker:Destroy(detached)
    if self.destroyed then return end
    self.destroyed = true
    self.pending, self.hoveredCell = {}, nil
    self.view.onLayout = nil
    if self.sharedTooltip then
        ComponentTooltip.Destroy(self.sharedTooltip, detached)
        if detached then Detached.Tooltip(self.sharedTooltip) end
        self.sharedTooltip:Destroy()
        self.sharedTooltip = nil
    end
    if detached then Detached.Tooltips(self.root) end
    for _, entry in pairs(self.targetFields) do
        if entry.control then
            if detached then Detached.Control(entry.control) else entry.control:Destroy() end
        elseif not detached then entry.root:Destroy() end
    end
    for _, cell in ipairs(self.cells) do
        if detached then Detached.Control(cell.control) else cell.control:Destroy() end
    end
    if detached then Detached.Control(self.view) else self.view:Destroy() end
    local context = self.tooltipContext
    local children = context and context.parentContext and context.parentContext.children
    for index = #(children or {}), 1, -1 do
        if children[index] == context then table.remove(children, index); break end
    end
    prettyui.Tooltip.unregisterContext(self.root)
    if not detached then self.root:Destroy() end
    self.root, self.tooltipContext, self.tooltipTarget, self.view = nil, nil, nil, nil
    self.cells, self.options, self.selected, self.unsupported, self.callbacks = {}, {}, {}, {}, {}
    self.targets, self.targetFields, self.targetOrder = {}, {}, {}
end

return Picker
