local Components = require("src/ui/shared/components")
local WindowStyle = require("src/ui/window/window_style")
local Detached = require("src/ui/shared/detached_ui")
local Overlay = {}
Overlay.__index = Overlay

function Overlay.Clamp(parent, x, y, width, height)
    return clamp(x, 0, math.max(0, parent.width - width)),
        clamp(y, 0, math.max(0, parent.height - height))
end

function Overlay.Mouse(parent)
    local mouse = Mouse.GetPosition()
    local origin = parent.xyGlobal
    return mouse.x - origin.x, mouse.y - origin.y
end

function Overlay.Mount(parent, settings, onClose, onResize, onMove)
    local self = setmetatable({parent = parent, settings = settings, onResize = onResize, onMove = onMove}, Overlay)
    local width = math.min(settings.notesWidth, parent.width)
    local height = math.min(settings.notesHeight, parent.height)
    self.chrome = WindowStyle.New(parent, {
        title = "Notes-Plus",
        x = settings.notesX, y = settings.notesY, width = width, height = height,
        minWidth = math.min(200, parent.width), minHeight = math.min(200, parent.height),
        maxWidth = 1400, maxHeight = 1000,
        resizable = true, scrollable = false, onClose = onClose,
        onPositionChange = function(_, x, y)
            if self.destroyed then return end
            local lastX, lastY = self.lastX, self.lastY
            self:SetPosition(math.floor(x), math.floor(y))
            if self.lastX ~= lastX or self.lastY ~= lastY then
                self.settings.notesX, self.settings.notesY = self.positionX, self.positionY
                if self.onMove then self.onMove(self.positionX, self.positionY) end
            end
        end
    })
    self.root = self.chrome.root
    self.root:Subscribe(ui.Hook.ONCLICK, function() return false end)
    self.root:Subscribe(ui.Hook.ONHOLD, function() return false end)
    self.root.alpha = settings.notesOpacity / 100
    self.chrome.viewport.hidden = true
    self.background = self.chrome.background
    self.background.alpha = settings.notesOpacity / 100
    self.width = math.max(1, width - 16)
    self.height = math.max(1, height - 40)
    self.body = Components.Host(self.root)
    self.body:SetPos(8, 32)
    self.body:SetSize(self.width, self.height)
    self.body.clickthrough = false

    self.close = self.chrome.closeButton
    self.close:MoveToFront()
    self:SyncSize()
    self:SetPosition(settings.notesX, settings.notesY)
    self.chrome:Show()
    return self
end

function Overlay:SyncResize()
    if self.sizing or self.destroyed or self:IsDragging() then return end
    if self.root.width == self.lastWidth and self.root.height == self.lastHeight then return end
    self.positionX, self.positionY = math.floor(self.root.x), math.floor(self.root.y)
    self:ClampPosition()
    self.settings.notesX, self.settings.notesY = self.positionX, self.positionY
    self:SyncSize()
    if self.onResize then self.onResize(self.root.width, self.root.height, self.positionX, self.positionY) end
end

function Overlay:SyncSize()
    self.lastWidth, self.lastHeight = self.root.width, self.root.height
    self.width = math.max(1, self.root.width - 16)
    self.height = math.max(1, self.root.height - 40)
    self.body:SetSize(self.width, self.height)
end

function Overlay:SetSize(width, height)
    self.chrome.minWidth = math.min(200, self.parent.width)
    self.chrome.minHeight = math.min(math.max(200, self.chrome.minHeight), self.parent.height)
    if self.chrome.resize then
        self.chrome.resize.minWidth, self.chrome.resize.minHeight = self.chrome.minWidth, self.chrome.minHeight
    end
    width = clamp(math.ceil(width), 1, math.max(1, math.min(1400, self.parent.width)))
    height = clamp(math.ceil(height), 1, math.max(1, math.min(1000, self.parent.height)))
    if self.root.width ~= width or self.root.height ~= height then
        self.sizing = true
        self.chrome:SetSize(width, height)
        self.sizing = false
        self:SyncSize()
    elseif self.lastWidth ~= self.root.width or self.lastHeight ~= self.root.height then
        self:SyncSize()
    end
    self:ClampPosition()
end

function Overlay:SetHeight(height)
    self:SetSize(self.root.width, height)
end

function Overlay:SetJournal(enabled)
    self.journal, self.journalBounds = enabled == true, nil
    local chrome = self.chrome
    for _, name in ipairs({"background", "leftBorder", "rightBorder", "bottomBorder", "bottomLeft", "bottomRight",
        "titleLeft", "titleCentreLeft", "titleCentre", "titleCentreRight", "titleRight", "titleText", "closeButton"}) do
        if chrome[name] then chrome[name].hidden = self.journal end
    end
    self:ClampPosition()
end

function Overlay:SetPosition(x, y)
    self.positionX, self.positionY = x, y
    self:ClampPosition()
end

function Overlay:GetPosition(useAnchor)
    self:SyncResize()
    if useAnchor then return self.positionX, self.positionY end
    return self.lastX, self.lastY
end

function Overlay:ClampPosition()
    if self:IsDragging() then return end
    local x, y = Overlay.Clamp(self.parent, self.positionX, self.positionY, self.root.width, self.root.height)
    local rootMoved = self.root.x ~= x or self.root.y ~= y
    local moved = rootMoved or x ~= self.lastX or y ~= self.lastY
    if rootMoved then self.root:SetPos(x, y) end
    self.lastX, self.lastY = x, y
    if self.chrome.dragBounds then self.chrome.dragBounds:RememberPosition() end
    local header = self.chrome.titleDrag
    local bounds = self.journal and self.journalBounds
    local left, top = x + (bounds and bounds.x or 0), y + (bounds and bounds.y or 0)
    local width = bounds and bounds.width or self.root.width - 34
    if header.x ~= left or header.y ~= top then header:SetPos(left, top) end
    if header.width ~= width or header.height ~= 32 then header:SetSize(width, 32) end
    if moved then
        self.chrome:_SyncOverlays(self.root.hidden == true)
    end
end

function Overlay:IsDragging()
    return self.chrome.titleDrag.height > 32
end

function Overlay:Destroy(detached)
    if self.destroyed then return end
    self.destroyed = true
    if detached then Detached.Window(self.chrome) else self.chrome:Destroy() end
end

return Overlay
