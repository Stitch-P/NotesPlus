local Layout = require("src/ui/notes/note_layout")
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

function Drag:Pointer(component, x, y)
    if self.destroyed or type(x) ~= "number" or type(y) ~= "number" then return end
    local left, top = origin(component, self.view.parent)
    self.x, self.y = left + x, top + y
end

function Drag.new(view, row, component, x, y)
    local self = setmetatable({view = view, row = row}, Drag)
    self:Pointer(component, x, y)
    if not self.x then return end
    local left, top = origin(view.listScroll.root, view.parent)
    local localX, localY = self.x - left, self.y - top
    if localY < 0 or localY >= view.listScroll.root.height
        or Layout.Hit(view.noteRows, localX, localY + view.listScroll.scrollY) ~= row then return end
    self.startX, self.startY = self.x, self.y
    self.mouseStart = Mouse.GetPosition()
    local base = view.parent.xyGlobal
    local absoluteX, absoluteY = self.x + base.x, self.y + base.y
    local scale = game and game.options and game.options.InterfaceScale
    self.mouseScale = scale and tonumber(scale.setting) and tonumber(scale.setting) / 100 or 1
    if self.mouseStart and absoluteX >= 32 and absoluteY >= 32 then
        local sx, sy = self.mouseStart.x / absoluteX, self.mouseStart.y / absoluteY
        if sx >= 0.5 and sx <= 4 and math.abs(sx - sy) <= sx * 0.1 then
            self.mouseScale = (sx + sy) / 2
        end
    end
    self.mouseScale = math.max(0.5, self.mouseScale)
    self.capture = component
    if view.alphabetical then return self end
    self.marker = Components.New(ui.Rectangle, view.parent)
    self.marker:SetSize(row.width, 2)
    self.marker.fill = true
    self.marker.rgba = 0xFFB347FF
    self.marker.clickthrough = true
    self.marker.hidden = true
    self.dividers = {}
    for index = 1, 2 do
        local divider = Components.New(ui.Rectangle, view.listScroll.root)
        divider:SetSize(row.width, 2)
        divider.fill = true
        divider.rgba = 0xFFB347B0
        divider.clickthrough = true
        divider.hidden = true
        self.dividers[index] = divider
    end
    return self
end

function Drag:Tick(scroll)
    if self.destroyed then return end
    local view, row = self.view, self.row
    local viewport = view.listScroll
    local mouse = Mouse.GetPosition()
    if mouse and self.mouseStart then

        self.x = self.startX + (mouse.x - self.mouseStart.x) / self.mouseScale
        self.y = self.startY + (mouse.y - self.mouseStart.y) / self.mouseScale
    end
    if math.abs(self.x - self.startX) >= 6 or math.abs(self.y - self.startY) >= 6 then
        self.moved = true
    end
    local left, top = origin(viewport.root, view.parent)
    local x, y = self.x - left, self.y - top
    local bodyWidth = row.columns and row.columns > 1 and viewport.contentWidth or (row.bodyWidth or row.width)
    self.inside = x >= 0 and x < bodyWidth and y >= 0 and y < viewport.root.height
    self.hitRow = Layout.Hit(view.noteRows, x, y + viewport.scrollY)
    if view.alphabetical then return end
    self.marker.hidden = not self.moved or not self.inside
    self.destination = nil
    if self.moved and self.inside and scroll then
        local edge = math.min(28, viewport.root.height / 4)
        if y < edge then viewport:ScrollBy(-8)
        elseif y > viewport.root.height - edge then viewport:ScrollBy(8) end
    end
    if self.moved then
        self.captureExpanded = true
        self.capture.hidden = false
        self.capture:SetPos(0, 0)
        self.capture:SetSize(view.noteHit.width, view.noteHit.height)
        self.capture:MoveToFront()
        self.marker:MoveToFront()
    end
    for index, divider in ipairs(self.dividers) do
        local edge = row.y + (index == 1 and 0 or row.height - 2) - viewport.scrollY
        local startY = math.max(0, edge)
        local endY = math.min(viewport.root.height, edge + 2)
        divider.hidden = not self.moved or endY <= startY
        if not divider.hidden then
            divider:SetPos(row.x or 0, startY)
            divider:SetSize(row.width, endY - startY)
        end
    end
    if not self.moved or not self.inside then return end
    local contentY = y + viewport.scrollY
    local marker
    self.destination, marker = Layout.Drop(view.noteRows, row, x, contentY)
    if marker.vertical then
        local startY = math.max(0, marker.y - viewport.scrollY)
        local endY = math.min(viewport.root.height, marker.y + marker.height - viewport.scrollY)
        self.marker.hidden = endY <= startY
        self.marker:SetPos(left + clamp(marker.x, 0, math.max(0, viewport.contentWidth - 2)), top + startY)
        self.marker:SetSize(2, math.max(1, endY - startY))
    else
        self.marker:SetPos(left + marker.x,
            top + clamp(marker.y - viewport.scrollY, 0, math.max(0, viewport.root.height - 2)))
        self.marker:SetSize(marker.width, 2)
    end
end

function Drag:Finish(component, x, y)
    if self.destroyed then return end
    self:Pointer(component, x, y)
    self:Tick(false)
    local view, row = self.view, self.row
    local destination = self.destination
    local moved, inside = self.moved, self.inside
    view.scroll = view.listScroll.scrollY
    view.noteDrag = nil
    self:Destroy()
    if moved then
        if inside and destination then view:MoveNote(row.position, destination) end
    elseif inside and self.hitRow == row then
        for index, note in ipairs(view.data.notes) do
            if note == row.note then view:Edit(index); break end
        end
    end
end

function Drag:Destroy()
    if self.destroyed then return end
    self.destroyed = true
    if self.marker then self.marker:Destroy() end
    for _, divider in ipairs(self.dividers or {}) do divider:Destroy() end
    self.captureExpanded = false
    if self.view.LayoutNoteHits and not self.view.destroyed and not self.view.clearing then
        self.view:LayoutNoteHits()
    end
    self.capture = nil
end

return Drag
