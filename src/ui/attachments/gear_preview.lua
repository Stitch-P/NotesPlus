local Components = require("src/ui/shared/components")
local Gear = require("src/notes/gear")
local WindowStyle = require("src/ui/window/window_style")
local Detached = require("src/ui/shared/detached_ui")

local Preview = {}
Preview.__index = Preview

local NATIVE_WIDTH, NATIVE_HEIGHT = 156, 196
local SLOT_BACKGROUND = "RS3_ICON_SLOT_STANDARD"
local SLOTS = {
    head = {x = 60, y = 0, icon = "RS3_ICON_WORN_EQUIPMENT_0"},
    pocket = {x = 100, y = 0, icon = "RS3_ICON_WORN_EQUIPMENT_12"},
    cape = {x = 20, y = 40, icon = "RS3_ICON_WORN_EQUIPMENT_1"},
    neck = {x = 60, y = 40, icon = "RS3_ICON_WORN_EQUIPMENT_2"},
    ammo = {x = 100, y = 40, icon = "RS3_ICON_WORN_EQUIPMENT_10"},
    mainhand = {x = 0, y = 80, icon = "RS3_ICON_WORN_EQUIPMENT_3"},
    body = {x = 60, y = 80, icon = "RS3_ICON_WORN_EQUIPMENT_5"},
    offhand = {x = 120, y = 80, icon = "RS3_ICON_WORN_EQUIPMENT_6"},
    legs = {x = 60, y = 120, icon = "RS3_ICON_WORN_EQUIPMENT_7"},
    hands = {x = 0, y = 160, icon = "RS3_ICON_WORN_EQUIPMENT_8"},
    feet = {x = 60, y = 160, icon = "RS3_ICON_WORN_EQUIPMENT_9"},
    ring = {x = 120, y = 160, icon = "RS3_ICON_WORN_EQUIPMENT_4"}
}
local CONNECTORS = {
    {x = 56, y = 53, width = 4, height = 10, sprite = "AIF_WORN_CONCT_HORZ_LINE_2_1"},
    {x = 96, y = 53, width = 4, height = 10, sprite = "AIF_WORN_CONCT_HORZ_LINE_2_1"},
    {x = 36, y = 93, width = 24, height = 10, sprite = "AIF_WORN_CONCT_HORZ_LINE_2_1"},
    {x = 96, y = 93, width = 24, height = 10, sprite = "AIF_WORN_CONCT_HORZ_LINE_2_1", tiled = true},
    {x = 73, y = 36, width = 10, height = 4, sprite = "AIF_WORN_CONCT_VERT_LINE_2_1"},
    {x = 73, y = 76, width = 10, height = 4, sprite = "AIF_WORN_CONCT_VERT_LINE_2_1"},
    {x = 73, y = 116, width = 10, height = 4, sprite = "AIF_WORN_CONCT_VERT_LINE_2_1"},
    {x = 73, y = 156, width = 10, height = 4, sprite = "AIF_WORN_CONCT_VERT_LINE_2_1"},
    {x = 13, y = 116, width = 10, height = 44, sprite = "AIF_WORN_CONCT_VERT_LINE_2_1"},
    {x = 133, y = 116, width = 10, height = 44, sprite = "AIF_WORN_CONCT_VERT_LINE_2_1"}
}

local function spriteID(name)
    local ok, value = pcall(function() return id.Sprite[name] end)
    return ok and type(value) == "number" and value >= 0 and value % 1 == 0 and value or -1
end

local function plain(value)
    return tostring(value or ""):gsub("<[Bb][Rr]%s*/?>", " "):gsub("<", "["):gsub(">", "]")
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

function Preview.new(parent, gear, callbacks, options)
    options = options or {}
    local self = setmetatable({callbacks = callbacks or {}, slots = {},
        editable = options.editable == true and options.passive ~= true,
        passive = options.passive == true, width = options.width or NATIVE_WIDTH}, Preview)
    self.root = Components.Host(parent)
    self.root.clickthrough = true
    local context, collection = contextFor(parent)
    self.clipBase = collection or parent
    local tooltipParent = context and context.parent or parent
    self.tooltipContext = prettyui.Tooltip.registerContext(self.root, tooltipParent, function(target)
        return position(target, tooltipParent)
    end, context)
    self.lines = {}
    for index, definition in ipairs(CONNECTORS) do
        local line = Components.New(ui.Sprite, self.root)
        line.spriteID = spriteID(definition.sprite)
        line.rgba = 0xFFFFFFFF
        line.alpha = 105 / 255
        line.clickthrough = true
        line.isTiling = definition.tiled == true
        self.lines[index] = line
    end
    if not self.passive then
        self.tooltipTarget = Components.New(ui.Layer, self.root)
        self.tooltipTarget.hidden, self.tooltipTarget.clickthrough = true, true
        self.sharedTooltip = prettyui.Tooltip.attach(self.tooltipTarget, self.root,
            Components.Options({text = "Gear slot", placement = "right", maxWidth = 280}))
        WindowStyle.ApplyTooltip(self.sharedTooltip)
    end
    for _, definition in ipairs(Gear.Slots) do
        local entry = {definition = definition}
        local control = prettyui.ItemSlot.new(self.root, nil, Components.Options({clickthrough = self.passive,
            backgroundSpriteID = spriteID(SLOT_BACKGROUND), itemInset = 2}))
        entry.control = control
        control.background.rgba = 0xFFFFFFFF
        control.background.alpha = 175 / 255
        entry.emptySprite = Components.New(ui.Sprite, control.root)
        local icon = SLOTS[definition.key].icon
        entry.emptySprite.spriteID = spriteID(icon)
        entry.emptySprite.rgba, entry.emptySprite.clickthrough = 0xFFFFFFFF, true
        entry.emptySprite.alpha = 1
        if not self.passive then
            control.root:Subscribe(ui.Hook.ONCLICK, function()
                if not self.destroyed and self.editable and self.callbacks.choose then
                    self.callbacks.choose(definition.key)
                end
                return false
            end)
            control.root:Subscribe(ui.Hook.ONMOUSEOVER, "notes_gear_preview", function()
                self:ShowSlotTooltip(entry)
                return true
            end)
            control.root:Subscribe(ui.Hook.ONMOUSELEAVE, "notes_gear_preview", function()
                if self.hoveredSlot == entry then self:HideTooltip() end
                return true
            end)
        end
        self.slots[definition.key] = entry
    end
    if self.editable and self.callbacks.capture then
        self.captureButton = prettyui.SimpleButton.new(self.root, "Use equipped gear", function()
            if not self.destroyed then self.callbacks.capture() end
        end, Components.Options({height = 28}))
        self.captureButton.content.font = id.Font.MUSEO_SANS_13PT_REGULAR
        self.captureButton:SetTooltip("Replace this setup with your currently equipped items. Empty worn slots clear the corresponding setup slots.")
        WindowStyle.ApplyTooltip(self.captureButton.tooltip)
    end
    if self.editable and self.callbacks.remove then
        self.removeButton = prettyui.SimpleButton.new(self.root, "Remove gear setup", function()
            if not self.destroyed then self.callbacks.remove() end
        end, Components.Options({height = 28}))
        self.removeButton.content.font = id.Font.MUSEO_SANS_13PT_REGULAR
    end
    self:SetBounds(options.x or 0, options.y or 0, self.width)
    self:SetGear(gear)
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
    local item = Gear.GetItem(entry.token)
    local value = item and item.label or entry.token and (entry.token:sub(6):gsub("_", " "):lower() .. " (unavailable)") or "Empty"
    local hint = self.editable and "<br>Click to choose an item." or ""
    self.sharedTooltip:SetText(plain(entry.definition.label) .. ": " .. plain(value) .. hint)
    self.sharedTooltip:Show()
end

function Preview:SetGear(gear)
    if self.destroyed then return end
    self.gear = Gear.Normalize(gear) or {}
    self:HideTooltip()
    for _, definition in ipairs(Gear.Slots) do
        local entry = self.slots[definition.key]
        local token = self.gear[definition.key]
        local object = Gear.Object(token)
        local objectID = object and object.id
        if entry.token ~= token or entry.objectID ~= objectID then entry.control:SetObject(object) end
        entry.token, entry.objectID = token, objectID
        entry.emptySprite.hidden = object ~= nil
    end
    self:Layout()
end

function Preview:Layout()
    local scale = math.min(1, self.width / NATIVE_WIDTH)
    local gridWidth, gridHeight = math.floor(NATIVE_WIDTH * scale), math.floor(NATIVE_HEIGHT * scale)
    local left = math.max(0, math.floor((self.width - gridWidth) / 2))
    local function place(component, x, y, width, height, offset)
        local scaledX, scaledY = math.floor(x * scale), math.floor(y * scale)
        component:SetPos((offset or 0) + scaledX, scaledY)
        component:SetSize(math.max(1, math.floor((x + width) * scale) - scaledX),
            math.max(1, math.floor((y + height) * scale) - scaledY))
    end
    for _, definition in ipairs(Gear.Slots) do
        local entry = self.slots[definition.key]
        local control = entry.control
        local native = SLOTS[definition.key]
        place(control.root, native.x, native.y, 36, 36, left)
        control.background:SetSize(control.root.width, control.root.height)
        for _, sprite in ipairs({control.item or false, control.dragItem or false, control.disabledOverlay or false}) do
            if sprite then place(sprite, 2, 2, 32, 30) end
        end
        place(entry.emptySprite, 2, 2, 32, 30)
    end
    for index, definition in ipairs(CONNECTORS) do
        place(self.lines[index], definition.x, definition.y, definition.width, definition.height, left)
    end
    self.height = gridHeight
    for _, button in ipairs({self.captureButton or false, self.removeButton or false}) do
        if button then
            button.root:SetPos(math.max(0, math.floor((self.width - math.min(160, self.width)) / 2)), self.height + 8)
            button.root:SetSize(math.min(160, self.width), 28)
            self.height = self.height + 36
        end
    end
    self.root:SetSize(self.width, self.height)
    if self.clipScroll ~= nil then self:Clip(self.clipScroll, self.clipHeight) end
end

function Preview:SetBounds(x, y, width)
    if self.destroyed then return end
    self:HideTooltip()
    self.width = math.max(1, width)
    self.root:SetPos(x, y)
    self:Layout()
end

function Preview:Clip(scrollY, viewportHeight)
    if self.destroyed then return end
    self.clipScroll, self.clipHeight = scrollY, viewportHeight
    local contentY, ancestor = self.root.y, self.root.parent
    while ancestor and ancestor ~= self.clipBase do
        contentY = contentY + (ancestor.y or 0) - (ancestor.scrollY or 0)
        ancestor = ancestor.parent
    end
    local function clip(control)
        local top = contentY + control.root.y - scrollY
        control.root.hidden = top < 0 or top + control.root.height > viewportHeight
        if control.root.hidden and control.tooltip then control.tooltip:Hide() end
    end
    for _, entry in pairs(self.slots) do clip(entry.control) end
    for _, line in ipairs(self.lines) do clip({root = line}) end
    if self.removeButton then clip(self.removeButton) end
    if self.captureButton then clip(self.captureButton) end
    if self.hoveredSlot and self.hoveredSlot.control.root.hidden then self:HideTooltip() end
end

function Preview:Destroy(detached)
    if self.destroyed then return end
    self.destroyed = true
    self.hoveredSlot = nil
    if self.sharedTooltip then
        if detached then Detached.Tooltip(self.sharedTooltip) end
        self.sharedTooltip:Destroy()
        self.sharedTooltip = nil
    end
    if detached then Detached.Tooltips(self.root) end
    for _, entry in pairs(self.slots) do
        if detached then Detached.Control(entry.control) else entry.control:Destroy() end
    end
    if self.removeButton then
        if detached then Detached.Control(self.removeButton) else self.removeButton:Destroy() end
    end
    if self.captureButton then
        if detached then Detached.Control(self.captureButton) else self.captureButton:Destroy() end
    end
    local context = self.tooltipContext
    local children = context and context.parentContext and context.parentContext.children
    for index = #(children or {}), 1, -1 do
        if children[index] == context then table.remove(children, index); break end
    end
    prettyui.Tooltip.unregisterContext(self.root)
    if not detached then self.root:Destroy() end
    self.root, self.slots, self.callbacks = nil, {}, nil
    self.tooltipTarget, self.removeButton, self.captureButton, self.lines, self.gear = nil, nil, nil, nil, nil
    self.tooltipContext, self.clipBase = nil, nil
end

return Preview
