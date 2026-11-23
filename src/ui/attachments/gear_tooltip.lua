local Detached = require("src/ui/shared/detached_ui")
local Components = require("src/ui/shared/components")
local GearPreview = require("src/ui/attachments/gear_preview")
local WindowStyle = require("src/ui/window/window_style")

local GearTooltip = {}
GearTooltip.__index = GearTooltip

local GRID_WIDTH, GRID_HEIGHT = 156, 196
local PADDING, MARGIN = 12, 6

function GearTooltip.new(parent)
    local self = setmetatable({parent = parent, interfaceID = parent.interfaceID}, GearTooltip)
    self.target = Components.New(ui.Layer, parent)
    self.target.hidden, self.target.clickthrough = true, true
    self.tooltip = prettyui.Tooltip.attach(self.target, parent,
        Components.Options({text = "", width = GRID_WIDTH + PADDING * 2, height = GRID_HEIGHT + PADDING * 2,
            placement = "right", boundsMargin = MARGIN}))
    self.target.clickthrough = true
    self.root = self.tooltip.root
    self.tooltip.label.hidden = true
    WindowStyle.ApplyTooltip(self.tooltip)
    return self
end

function GearTooltip:Show(target, gear)
    if self.destroyed or not self.tooltip or not self.tooltip.root then return false end
    if target == nil or type(gear) ~= "table" then self:Hide(); return false end
    local ok, x, y, width, height, hidden, interfaceID = pcall(function()
        return target.x, target.y, target.width, target.height,
            target.hidden == true or target.visibleGlobal == false, target.interfaceID
    end)
    if not ok or hidden then self:Hide(); return false end
    if ui.Interfaces:GetInterface(interfaceID) == nil
        or ui.Interfaces:GetInterface(self.tooltip.interfaceID) == nil then self:Hide(); return false end
    local parent = self.tooltip.parent
    local parentWidth, parentHeight = parent.width, parent.height
    if parentWidth < 21 or parentHeight < 21 then self:Hide(); return false end
    local margin = math.min(MARGIN, math.floor((math.min(parentWidth, parentHeight) - 21) / 2))
    local availableWidth, availableHeight = parentWidth - margin * 2, parentHeight - margin * 2
    local padding = math.min(PADDING, math.floor((math.min(availableWidth, availableHeight) - 1) / 2))
    local gridWidth = math.max(1, math.floor(math.min(GRID_WIDTH, availableWidth - padding * 2,
        (availableHeight - padding * 2) * GRID_WIDTH / GRID_HEIGHT)))
    local gridHeight = math.floor(GRID_HEIGHT * gridWidth / GRID_WIDTH)
    local popupWidth = math.max(21, gridWidth + padding * 2)
    local popupHeight = math.max(21, gridHeight + padding * 2)
    self.target:SetPos(x, y)
    self.target:SetSize(width, height)
    self.tooltip.options.width, self.tooltip.options.height = popupWidth, popupHeight
    self.tooltip.options.boundsMargin = margin
    self.tooltip:SetText("")
    local insetX, insetY = math.floor((popupWidth - gridWidth) / 2), math.floor((popupHeight - gridHeight) / 2)
    if not self.preview then
        self.preview = GearPreview.new(self.root, gear, {},
            {x = insetX, y = insetY, width = gridWidth, editable = false, passive = true})
    else
        self.preview:SetBounds(insetX, insetY, gridWidth)
        self.preview:SetGear(gear)
    end
    self.hoverTarget = target
    self.tooltip:Show()
    return self.root.hidden == false
end

function GearTooltip:Hide()
    self.hoverTarget = nil
    if self.tooltip then self.tooltip:Hide() end
end

function GearTooltip:Destroy(detached)
    if self.destroyed then return end
    self.destroyed = true
    if self.preview then self.preview:Destroy(detached); self.preview = nil end
    if self.tooltip then
        if detached then Detached.Tooltip(self.tooltip) end
        self.tooltip:Destroy()
        self.tooltip = nil
    end
    if not detached and self.target and ui.Interfaces:GetInterface(self.interfaceID) ~= nil then self.target:Destroy() end
    self.target, self.root, self.parent, self.hoverTarget = nil, nil, nil, nil
end

return GearTooltip
