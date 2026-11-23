local ModelPreview = require("src/ui/tracking/model_preview")

local ModelScene = {}
ModelScene.__index = ModelScene

function ModelScene.new(parent)
    return setmetatable({parent = parent, members = {}, ready = false, hidden = true}, ModelScene)
end

function ModelScene:Apply(reference)
    if self.destroyed then return nil, "The model preview is closed." end
    local references = type(reference) == "table" and (reference.models or {reference})
    if type(references) ~= "table" or #references == 0 then
        self.ready = false
        self:SetHidden(true)
        return nil, "Choose an NPC model to preview."
    end
    local rowHeight = reference.rowHeight
    if rowHeight ~= nil and (type(rowHeight) ~= "number" or rowHeight % 1 ~= 0
        or rowHeight < 100 or rowHeight > 4096) then
        self.ready = false
        self:SetHidden(true)
        return nil, "Row height must be from 100 to 4,096, using whole numbers."
    end
    local columns = reference.columns
    if columns ~= nil and (type(columns) ~= "number" or columns % 1 ~= 0 or columns < 1 or columns > 3) then
        self.ready = false
        self:SetHidden(true)
        return nil, "Model columns must be a whole number from 1 to 3."
    end
    for index, value in ipairs(references) do
        local member, message = self.members[index]
        if not member then
            member, message = ModelPreview.new(self.parent)
            if member then self.members[index] = member end
        end
        local ok
        if member then ok, message = member:Apply(value) end
        if not ok then
            self.ready = false
            self:SetHidden(true)
            return nil, message
        end
    end
    for index = #self.members, #references + 1, -1 do
        self.members[index]:Destroy()
        self.members[index] = nil
    end
    self.rowHeight, self.columns = rowHeight, columns
    self.layoutSize = 0
    for _, member in ipairs(self.members) do self.layoutSize = math.max(self.layoutSize, member.layoutSize) end
    self.ready = true
    self:SetHidden(false)
    return true
end

function ModelScene:Measure(width)
    if not self.ready then return 0, 0 end
    -- Tuned screen offsets can depend on a fixed arrangement of model cells.
    local cellSize = self.columns and self.layoutSize or math.min(self.layoutSize, math.max(1, width))
    local columns = math.min(#self.members, self.columns or math.min(3, math.max(1, math.floor(width / cellSize))))
    local rowHeight = self.rowHeight or cellSize * 1.5
    return columns * cellSize, math.ceil(#self.members / columns) * rowHeight, columns, cellSize, rowHeight
end

function ModelScene:SetBounds(x, y, width)
    if self.destroyed or not self.ready then return end
    local _, _, columns, cellSize, rowHeight = self:Measure(width)
    self.x, self.y = x, y
    for index, member in ipairs(self.members) do
        local column, row = (index - 1) % columns, math.floor((index - 1) / columns)
        local frameSize = math.min(member.frameSize, cellSize)
        if member.model.width ~= frameSize or member.model.height ~= frameSize then
            member.model:SetSize(frameSize, frameSize)
        end
        member.blockY = y + row * rowHeight
        local authoredX = x + column * cellSize + (cellSize - frameSize) / 2
        -- A displaced model still needs its native frame inside the viewport to render.
        local frameX = math.min(authoredX, x + math.max(0, width - frameSize))
        member:SetPos(frameX, member.blockY + cellSize / 2, authoredX - frameX)
        member.clipBottom = math.min(member.model.y + member.model.height, member.blockY + rowHeight)
    end
    self:UpdateVisibility()
end

function ModelScene:UpdateVisibility()
    if self.destroyed then return end
    for _, member in ipairs(self.members) do
        local model = member.model
        local clipped = self.clipOffset ~= nil and ((member.blockY or 0) + self.clipOffset < 0
            or (member.clipBottom or model.y + model.height) + self.clipOffset > self.clipHeight)
        member:SetHidden(self.hidden or clipped)
    end
end

function ModelScene:SetHidden(hidden)
    if self.destroyed then return end
    self.hidden = hidden == true or not self.ready
    self:UpdateVisibility()
end

function ModelScene:Clip(offsetY, viewportHeight)
    if self.destroyed then return end
    self.clipOffset, self.clipHeight = offsetY, viewportHeight
    self:UpdateVisibility()
end

function ModelScene:Hide()
    self:SetHidden(true)
end

function ModelScene:Destroy(detached)
    if self.destroyed then return end
    self.destroyed = true
    for _, member in ipairs(self.members) do member:Destroy(detached) end
    self.members, self.parent, self.ready = {}, nil, false
end

return ModelScene
