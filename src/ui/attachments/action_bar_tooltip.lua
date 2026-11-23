local Detached = require("src/ui/shared/detached_ui")
local Components = require("src/ui/shared/components")
local ActionBar = require("src/notes/action_bar")
local ActionBarPreview = require("src/ui/attachments/action_bar_preview")
local WindowStyle = require("src/ui/window/window_style")

local ActionBarTooltip = {}
ActionBarTooltip.__index = ActionBarTooltip

local GRID_WIDTH, GRID_HEIGHT = 504, 72
local PADDING, MARGIN = 12, 6

local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

function ActionBarTooltip.new(parent)
    local self = setmetatable({interfaceID = parent.interfaceID}, ActionBarTooltip)
    self.target = Components.New(ui.Layer, parent)
    self.target.hidden, self.target.clickthrough = true, true
    self.tooltip = prettyui.Tooltip.attach(self.target, parent,
        Components.Options({text = "", width = GRID_WIDTH + PADDING * 2, height = GRID_HEIGHT + PADDING * 2,
            placement = "right", boundsMargin = MARGIN}))
    self.target.clickthrough = true
    self.root = self.tooltip.root
    self.root.clickthrough = true
    self.tooltip.label.hidden = true
    WindowStyle.ApplyTooltip(self.tooltip)
    self.preview = ActionBarPreview.new(self.root, nil, {},
        {x = PADDING, y = PADDING, width = GRID_WIDTH, editable = false, passive = true})
    return self
end

function ActionBarTooltip:Show(target, bar)
    if self.destroyed or not self.tooltip or not self.tooltip.root then return false end
    local normalized = ActionBar.Normalize(bar)
    if target == nil or normalized == nil then self:Hide(); return false end
    local ok, x, y, width, height, hidden, interfaceID = pcall(function()
        return target.x, target.y, target.width, target.height,
            target.hidden == true or target.visibleGlobal == false, target.interfaceID
    end)
    if not ok or hidden or not finite(x) or not finite(y) or not finite(width) or not finite(height)
        or width <= 0 or height <= 0 then self:Hide(); return false end
    if ui.Interfaces:GetInterface(interfaceID) == nil
        or ui.Interfaces:GetInterface(self.tooltip.interfaceID) == nil then self:Hide(); return false end
    local parent = self.tooltip.parent
    local parentWidth, parentHeight = parent.width, parent.height
    if parentWidth < 21 or parentHeight < 21 then self:Hide(); return false end
    local margin = math.min(MARGIN, math.floor((math.min(parentWidth, parentHeight) - 21) / 2))
    local availableWidth, availableHeight = parentWidth - margin * 2, parentHeight - margin * 2
    local padding = math.min(PADDING, math.floor((math.min(availableWidth, availableHeight) - 15) / 2))
    local gridWidth = math.max(1, math.min(GRID_WIDTH, availableWidth - padding * 2))
    local gridHeight = math.max(1, availableHeight - padding * 2)
    self.preview:SetBounds(padding, padding, gridWidth, gridHeight)
    self.preview:SetBar(normalized)
    local popupWidth = math.max(21, gridWidth + padding * 2)
    local popupHeight = math.max(21, self.preview.height + padding * 2)
    self.target:SetPos(x, y)
    self.target:SetSize(width, height)
    self.tooltip.options.width, self.tooltip.options.height = popupWidth, popupHeight
    self.tooltip.options.boundsMargin = margin
    self.tooltip:SetText("")
    self.hoverTarget = target
    self.tooltip:Show()
    return self.root.hidden == false
end

function ActionBarTooltip:Hide()
    self.hoverTarget = nil
    if self.tooltip then self.tooltip:Hide() end
end

function ActionBarTooltip:Tick()
    if self.destroyed or self.hoverTarget == nil then return end
    local ok, hidden = pcall(function()
        return self.hoverTarget.hidden == true or self.hoverTarget.visibleGlobal == false
            or self.hoverTarget.isMouseOver == false
    end)
    if not ok or hidden then self:Hide() end
end

function ActionBarTooltip:Destroy(detached)
    if self.destroyed then return end
    self.destroyed = true
    if self.preview then self.preview:Destroy(detached); self.preview = nil end
    if self.tooltip then
        if detached then Detached.Tooltip(self.tooltip) end
        self.tooltip:Destroy()
        self.tooltip = nil
    end
    if not detached and self.target and ui.Interfaces:GetInterface(self.interfaceID) ~= nil then self.target:Destroy() end
    self.target, self.root, self.hoverTarget = nil, nil, nil
end

return ActionBarTooltip
