local Components = require("src/ui/shared/components")
local ActionBar = require("src/notes/action_bar")
local WindowStyle = require("src/ui/window/window_style")
local Detached = require("src/ui/shared/detached_ui")

local Preview = {}
Preview.__index = Preview

local SLOT, CELL_WIDTH, CELL_HEIGHT = 32, 36, 48
local TEXT, MUTED = 0xE7D7B0FF, 0xB7B1A7FF

local function plain(value)
    return tostring(value or ""):gsub("<[Bb][Rr]%s*/?>", " "):gsub("<", "["):gsub(">", "]")
end

local function objectFor(value)
    if type(value) ~= "number" then return nil end
    local ok, object = pcall(function() return config.Obj.FromID(value) end)
    return ok and object or nil
end

local function contextFor(parent)
    local collection = parent
    while collection do
        local context = prettyui.Tooltip.getContext(collection)
        if context then return context, collection end
        collection = collection.parent
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

local function label(parent, text, colour)
    local result = prettyui.Text.new(parent, Components.Options({text = plain(text), width = 1, height = 20,
        colour = colour or TEXT, font = id.Font.MUSEO_SANS_13PT_REGULAR, shadowed = true, maxLines = 0}))
    result.clickthrough = true
    return result
end

function Preview.new(parent, bar, callbacks, options)
    options = options or {}
    local self = setmetatable({callbacks = callbacks or {}, slots = {},
        editable = options.editable == true and options.passive ~= true, passive = options.passive == true,
        width = math.max(1, options.width or 504)}, Preview)
    self.root = Components.Host(parent)
    self.root.clickthrough = true
    local context, collection = contextFor(parent)
    self.clipBase = collection or parent
    local tooltipParent = context and context.parent or parent
    if not self.passive then
        self.tooltipContext = prettyui.Tooltip.registerContext(self.root, tooltipParent, function(target)
            return position(target, tooltipParent)
        end, context)
        self.tooltipTarget = Components.New(ui.Layer, self.root)
        self.tooltipTarget.hidden, self.tooltipTarget.clickthrough = true, true
        self.sharedTooltip = prettyui.Tooltip.attach(self.tooltipTarget, self.root,
            Components.Options({text = "Action bar slot", placement = "right", maxWidth = 280}))
        WindowStyle.ApplyTooltip(self.sharedTooltip)
    end
    self.name = label(self.root, "Action bar")
    self.name.maxLines = 1
    for index = 1, ActionBar.SLOT_COUNT do
        local entry = {index = index}
        entry.control = prettyui.ItemSlot.new(self.root, nil, Components.Options({
            backgroundSpriteID = id.Sprite.RS3_ICON_SLOT_STANDARD, itemInset = 3, clickthrough = self.passive}))
        entry.control.background.rgba, entry.control.background.alpha = 0xFFFFFFFF, 175 / 255
        entry.sprite = Components.New(ui.Sprite, entry.control.root)
        entry.sprite.spriteID, entry.sprite.rgba = -1, 0xFFFFFFFF
        entry.sprite.clickthrough, entry.sprite.hidden = true, true
        if self.passive then
            entry.objectSprite = Components.New(ui.Sprite, entry.control.root)
            entry.objectSprite.rgba = 0xFFFFFFFF
            entry.objectSprite.clickthrough, entry.objectSprite.hidden = true, true
        end
        entry.number = label(self.root, index, MUTED)
        entry.number.maxLines = 1
        if not self.passive then
            entry.control.root:Subscribe(ui.Hook.ONMOUSEOVER, "notes_action_bar_preview", function()
                self:ShowSlotTooltip(entry)
                return true
            end)
            entry.control.root:Subscribe(ui.Hook.ONMOUSELEAVE, "notes_action_bar_preview", function()
                if self.hoveredSlot == entry then self:HideTooltip() end
                return true
            end)
        end
        self.slots[index] = entry
    end
    local normalized = ActionBar.Normalize(bar)
    self.selectedPreset = options.selectedPreset or normalized and normalized.preset or 1
    if self.editable then
        local choices = {}
        for index, entry in ipairs(ActionBar.Presets()) do
            choices[index] = {id = entry.id, label = plain(entry.label), order = index}
        end
        self.preset = prettyui.ComboBox.new(self.root, Components.Options({entries = choices,
            selectedID = self.selectedPreset, maxVisibleEntries = 8, height = 28,
            onChange = function(_, value)
                if not self.destroyed then self.selectedPreset = value end
            end}))
        if self.callbacks.capture then
            self.captureButton = prettyui.SimpleButton.new(self.root, "Copy action bar", function()
                if not self.destroyed then self.callbacks.capture(self.selectedPreset) end
            end, Components.Options({height = 28}))
            self.captureButton.content.font = id.Font.MUSEO_SANS_13PT_REGULAR
        end
        if self.callbacks.remove then
            self.removeButton = prettyui.SimpleButton.new(self.root, "Remove action bar", function()
                if not self.destroyed then self.callbacks.remove() end
            end, Components.Options({height = 28}))
            self.removeButton.content.font = id.Font.MUSEO_SANS_13PT_REGULAR
        end
        self.hint = label(self.root, "Display the selected bar in game, then copy.", MUTED)
    end
    self:SetBar(normalized)
    self:SetBounds(options.x or 0, options.y or 0, self.width)
    return self
end

function Preview:HideTooltip()
    self.hoveredSlot = nil
    if self.sharedTooltip then self.sharedTooltip:Hide() end
end

function Preview:ShowSlotTooltip(entry)
    if self.destroyed or self.passive or entry.control.root.hidden then return end
    self:HideTooltip()
    self.hoveredSlot = entry
    self.tooltipTarget:SetPos(entry.control.root.x, entry.control.root.y)
    self.tooltipTarget:SetSize(entry.control.root.width, entry.control.root.height)
    local text = ActionBar.Label(entry.slot)
    self.sharedTooltip:SetText("Slot " .. tostring(entry.index) .. ": " .. plain(text))
    self.sharedTooltip:Show()
end

function Preview:SetBar(bar)
    if self.destroyed then return end
    self.bar = ActionBar.Normalize(bar)
    self:HideTooltip()
    self.name.content = plain(self.bar and self.bar.name or "Action bar")
    for index, entry in ipairs(self.slots) do
        local slot = self.bar and self.bar.slots[index] or {}
        local icon = ActionBar.Icon(slot)
        local objectID = type(icon) == "number" and icon or nil
        if self.passive then
            if entry.objectID ~= objectID and objectID ~= nil then
                entry.objectSprite:SetAssociatedObject(objectID)
                entry.objectSprite.associatedObjectQuantity = 1
                entry.objectSprite.associatedObjectQuantityMode = ui.ObjectQuantityDisplayMode.NEVER
            end
            entry.objectSprite.hidden = objectID == nil
        elseif entry.objectID ~= objectID then
            entry.control:SetObject(objectFor(objectID))
        end
        entry.slot, entry.objectID = slot, objectID
        entry.sprite.spriteID = type(icon) == "table" and icon.sprite or -1
        entry.sprite.hidden = entry.sprite.spriteID < 0
    end
    self:Layout()
end

function Preview:Layout()
    local columns = self.width >= CELL_WIDTH * 14 and 14
        or self.width >= CELL_WIDTH * 7 and 7 or math.max(1, math.floor(self.width / CELL_WIDTH))
    local scale = self.passive and self.maxHeight
        and math.min(1, self.maxHeight / (24 + math.ceil(ActionBar.SLOT_COUNT / columns) * CELL_HEIGHT)) or 1
    local function scaled(value) return math.max(1, math.floor(value * scale)) end
    local y = 0
    self.name:SetPos(0, y)
    self.name:SetSize(self.width, scaled(20))
    y = y + scaled(24)
    if self.editable then
        local controls = {self.preset, self.captureButton or false, self.removeButton or false}
        local desired = {180, 150, 160}
        local x = 0
        for index, control in ipairs(controls) do
            if control then
                local width = math.min(self.width, desired[index])
                if x > 0 and x + width > self.width then x, y = 0, y + 34 end
                control.root:SetPos(x, y)
                control.root:SetSize(width, 28)
                x = x + width + 8
            end
        end
        y = y + 36
        local hintHeight = self.width >= 300 and 20 or 36
        self.hint:SetPos(0, y)
        self.hint:SetSize(self.width, hintHeight)
        y = y + hintHeight + 6
    end
    local cellWidth = math.min(scaled(CELL_WIDTH), self.width)
    local size = math.min(scaled(SLOT), cellWidth)
    local cellHeight = scaled(CELL_HEIGHT)
    local inset = math.min(math.floor(size / 2), math.floor(3 * scale))
    local left = math.max(0, math.floor((self.width - columns * cellWidth) / 2))
    for index, entry in ipairs(self.slots) do
        local x = left + ((index - 1) % columns) * cellWidth
        local top = y + math.floor((index - 1) / columns) * cellHeight
        local control = entry.control
        control.root:SetPos(x + math.floor((cellWidth - size) / 2), top)
        control.root:SetSize(size, size)
        control.background:SetSize(size, size)
        for _, sprite in ipairs({control.item or false, control.dragItem or false,
            control.disabledOverlay or false, entry.sprite, entry.objectSprite or false}) do
            if sprite then
                sprite:SetPos(inset, inset)
                sprite:SetSize(math.max(1, size - inset * 2), math.max(1, size - inset * 2))
            end
        end
        local numberY = self.passive and math.min(cellHeight - 1, size + math.floor(scale)) or size + 1
        local numberHeight = self.passive and math.max(1, math.min(scaled(16), cellHeight - numberY)) or 16
        entry.number:SetPos(x, top + numberY)
        entry.number:SetSize(cellWidth, numberHeight)
        entry.number.alignHorizontal = ui.AlignMode.CENTRE
    end
    self.height = y + math.ceil(ActionBar.SLOT_COUNT / columns) * cellHeight
    self.root:SetSize(self.width, self.height)
    if self.clipScroll ~= nil then self:Clip(self.clipScroll, self.clipHeight, self.clipOffset) end
end

function Preview:SetBounds(x, y, width, maxHeight)
    if self.destroyed then return end
    self:HideTooltip()
    self.width = math.max(1, width)
    self.maxHeight = self.passive and maxHeight and math.max(1, maxHeight) or nil
    self.root:SetPos(x, y)
    self:Layout()
end

function Preview:Clip(scrollY, viewportHeight, contentOffset)
    if self.destroyed then return end
    self.clipScroll, self.clipHeight, self.clipOffset = scrollY, viewportHeight, contentOffset
    local contentY = self.root.y
    if contentOffset ~= nil then
        contentY = contentY + contentOffset
    else
        local ancestor = self.root.parent
        while ancestor and ancestor ~= self.clipBase do
            contentY = contentY + (ancestor.y or 0) - (ancestor.scrollY or 0)
            ancestor = ancestor.parent
        end
    end
    local function clip(component)
        local top = contentY + component.y - scrollY
        component.hidden = top < 0 or top + component.height > viewportHeight
    end
    clip(self.name)
    for _, entry in ipairs(self.slots) do
        clip(entry.control.root)
        clip(entry.number)
    end
    for _, control in ipairs({self.preset or false, self.captureButton or false, self.removeButton or false}) do
        if control then clip(control.root) end
    end
    if self.preset and self.preset.root.hidden and self.preset.open then self.preset:_Close() end
    if self.hint then clip(self.hint) end
    if self.hoveredSlot and self.hoveredSlot.control.root.hidden then self:HideTooltip() end
end

function Preview:Destroy(detached)
    if self.destroyed then return end
    self.destroyed = true
    self.hoveredSlot = nil
    if self.sharedTooltip then
        if detached then Detached.Tooltip(self.sharedTooltip) end
        self.sharedTooltip:Destroy()
    end
    if detached then Detached.Tooltips(self.root) end
    for _, entry in ipairs(self.slots) do
        if detached then Detached.Control(entry.control) else entry.control:Destroy() end
    end
    for _, control in ipairs({self.preset or false, self.captureButton or false, self.removeButton or false}) do
        if control then
            if detached then Detached.Control(control) else control:Destroy() end
        end
    end
    local context = self.tooltipContext
    local children = context and context.parentContext and context.parentContext.children
    for index = #(children or {}), 1, -1 do
        if children[index] == context then table.remove(children, index); break end
    end
    if self.tooltipContext then prettyui.Tooltip.unregisterContext(self.root) end
    if not detached then self.root:Destroy() end
    self.root, self.slots, self.callbacks, self.bar = nil, {}, nil, nil
    self.name, self.hint, self.preset, self.captureButton, self.removeButton = nil, nil, nil, nil, nil
    self.tooltipContext, self.clipBase, self.sharedTooltip, self.tooltipTarget = nil, nil, nil, nil
end

return Preview
