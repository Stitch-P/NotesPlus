local Components = require("src/ui/shared/components")
local Drag = {}
Drag.__index = Drag

local function origin(component, parent)
    local point, base = component.xyGlobal, parent.xyGlobal
    local x, y = point.x - base.x, point.y - base.y
    local ancestor = component.parent
    while ancestor and ancestor ~= parent do
        x = x - (ancestor.scrollX or 0)
        y = y - (ancestor.scrollY or 0)
        ancestor = ancestor.parent
    end
    return x, y
end

local function line(parent, colour)
    local component = Components.New(ui.Rectangle, parent)
    component.fill = true
    component.rgba = colour
    component.clickthrough = true
    component.hidden = true
    return component
end

function Drag:Pointer(component, x, y)
    if self.destroyed or type(x) ~= "number" or type(y) ~= "number" then return end
    local left, top = origin(component, self.parent)
    self.x, self.y = left + x, top + y
end

function Drag.new(sidebar, row, component, x, y)
    if not row.category or type(x) ~= "number" or type(y) ~= "number" then return end
    local self = setmetatable({sidebar = sidebar, row = row, parent = sidebar.overlayParent}, Drag)
    self:Pointer(component, x, y)
    local left, top = origin(sidebar.scroll.root, self.parent)
    if self.x < left or self.x >= left + sidebar.scroll.contentWidth or self.y < top
        or self.y >= top + sidebar.scroll.root.height then return end
    self.startX, self.startY = self.x, self.y
    self.mouseStart = Mouse.GetPosition()
    local base = self.parent.xyGlobal
    local absoluteX, absoluteY = self.x + base.x, self.y + base.y
    local scale = game and game.options and game.options.InterfaceScale
    self.mouseScale = scale and tonumber(scale.setting) and tonumber(scale.setting) / 100 or 1
    if self.mouseStart and absoluteX >= 32 and absoluteY >= 32 then
        local sx, sy = self.mouseStart.x / absoluteX, self.mouseStart.y / absoluteY
        if sx >= 0.5 and sx <= 4 and math.abs(sx - sy) <= sx * 0.1 then self.mouseScale = (sx + sy) / 2 end
    end
    self.mouseScale = math.max(0.5, self.mouseScale)
    self.capture = component
    self.marker = line(self.parent, 0xFFB347FF)
    self.dividers = {line(sidebar.scroll.root, 0xFFB347B0), line(sidebar.scroll.root, 0xFFB347B0)}
    return self
end

function Drag:Tick(scroll)
    if self.destroyed then return end
    local sidebar, viewport = self.sidebar, self.sidebar.scroll
    local mouse = Mouse.GetPosition()
    if mouse and self.mouseStart then
        self.x = self.startX + (mouse.x - self.mouseStart.x) / self.mouseScale
        self.y = self.startY + (mouse.y - self.mouseStart.y) / self.mouseScale
    end
    if math.abs(self.x - self.startX) >= 6 or math.abs(self.y - self.startY) >= 6 then self.moved = true end
    local left, top = origin(viewport.root, self.parent)
    local x, y = self.x - left, self.y - top
    self.inside = x >= 0 and x < viewport.contentWidth and y >= 0 and y < viewport.root.height
    self.marker.hidden = not self.moved or not self.inside
    self.destination = nil
    if self.moved then
        prettyui.Tooltip.hideContextTooltips(viewport.content)
        sidebar:HoverRow(nil)
        sidebar:LayoutInput()
        self.capture:MoveToFront()
        self.marker:MoveToFront()
    end
    if self.moved and self.inside and scroll then
        local edge = math.min(28, viewport.root.height / 4)
        if y < edge then viewport:ScrollBy(-8)
        elseif y > viewport.root.height - edge then viewport:ScrollBy(8) end
    end
    for index, divider in ipairs(self.dividers) do
        local edge = self.row.root.y + (index == 1 and 0 or self.row.root.height - 2) - viewport.scrollY
        local startY, endY = math.max(0, edge), math.min(viewport.root.height, edge + 2)
        divider.hidden = not self.moved or endY <= startY
        if not divider.hidden then
            divider:SetPos(0, startY)
            divider:SetSize(viewport.contentWidth, endY - startY)
        end
    end
    if not self.moved or not self.inside then return end
    local contentY = y + viewport.scrollY
    local destination, boundary = 1, self.row.root.y
    for _, candidate in ipairs(sidebar.rows) do
        if candidate.category and candidate ~= self.row then
            if contentY < candidate.root.y + candidate.root.height / 2 then
                boundary = candidate.root.y
                break
            end
            destination = destination + 1
            boundary = candidate.root.y + candidate.root.height
        end
    end
    self.destination = destination
    self.marker:SetPos(left, top + clamp(boundary - viewport.scrollY, 0, math.max(0, viewport.root.height - 2)))
    self.marker:SetSize(viewport.contentWidth, 2)
end

function Drag:Finish(component, x, y)
    if self.destroyed then return end
    self:Pointer(component, x, y)
    self:Tick(false)
    local sidebar, row = self.sidebar, self.row
    local moved, inside, destination = self.moved, self.inside, self.destination
    sidebar.drag = nil
    self:Destroy()
    if moved then
        if inside and destination and sidebar.callbacks.reorder then sidebar.callbacks.reorder(row.categoryID, destination) end
    elseif inside then row.button.action() end
end

function Drag:Destroy(detached)
    if self.destroyed then return end
    self.destroyed = true
    if not detached then
        if self.marker then self.marker:Destroy() end
        for _, divider in ipairs(self.dividers or {}) do divider:Destroy() end
    end
    if not detached then self.sidebar:LayoutInput() end
    self.capture, self.marker, self.dividers = nil, nil, nil
end

return Drag
