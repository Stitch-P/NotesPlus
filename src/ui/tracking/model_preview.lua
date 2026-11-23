local Components = require("src/ui/shared/components")
local ModelPreview = {}
ModelPreview.__index = ModelPreview

local DEFAULT_FRAME_SIZE = 120
local PRESET_FRAME_SIZE = 160
local PRESET_LAYOUT_SIZE = 200
local PRESET_MODEL_SCALE = 1.25
local DEFAULT_DISTANCE = 1400
local NUMERIC_FIELDS = {"screenX", "screenY", "worldX", "worldY", "worldZ"}

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function integer(value)
    return finite(value) and value == math.floor(value)
end

local function settings(reference)
    if type(reference) ~= "table" or not integer(reference.npc) or reference.npc < 0 then
        return nil, "Choose an NPC model to preview."
    end
    local value = {
        npc = reference.npc,
        modelType = reference.modelType or "NPC_MODEL",
        frameSize = reference.preset == true and PRESET_FRAME_SIZE or DEFAULT_FRAME_SIZE,
        layoutSize = reference.preset == true and PRESET_LAYOUT_SIZE or DEFAULT_FRAME_SIZE,
        animation = reference.animation == nil and -1 or reference.animation,
    }
    if value.modelType ~= "NPC_MODEL" and value.modelType ~= "NPC_HEAD" then
        return nil, "Choose a body or head model."
    end
    value.scale = reference.preset == true and PRESET_MODEL_SCALE or 1
    local zoom = reference.zoom
    value.viewDistance = reference.viewDistance
    if value.viewDistance == nil then
        value.viewDistance = finite(zoom) and zoom > 0 and math.floor(zoom * 1.6) or DEFAULT_DISTANCE
    end
    if not integer(value.viewDistance) or value.viewDistance < 1 or value.viewDistance > 1000000 then
        return nil, "The camera distance must be from 1 to 1,000,000."
    end
    if not integer(value.animation) or value.animation < -1 or value.animation > 2147483647 then
        return nil, "Choose a valid animation or turn animation off."
    end
    for _, key in ipairs(NUMERIC_FIELDS) do
        value[key] = reference[key] == nil and 0 or reference[key]
        if not finite(value[key]) then return nil, "Enter a valid number for " .. key .. "." end
    end
    return value
end

local function offset(model, property, x, y, z)
    local value = model[property]
    value.x, value.y = x, y
    if z ~= nil then value.z = z end
    model[property] = value
end

function ModelPreview.new(parent)
    local ok, model = pcall(function() return Components.New(ui.Model, parent) end)
    if not ok or not model then return nil, "The model preview is not available." end
    model.clickthrough, model.hidden = true, true
    return setmetatable({model = model, frameSize = DEFAULT_FRAME_SIZE, layoutSize = DEFAULT_FRAME_SIZE, ready = false}, ModelPreview)
end

function ModelPreview:UpdateScreenOffset(value, force)
    local x = value.screenX + (self.layoutOffsetX or 0)
    if force or self.renderedScreenX ~= x or self.renderedScreenY ~= value.screenY then
        offset(self.model, "screenOffset", x, value.screenY)
        self.renderedScreenX, self.renderedScreenY = x, value.screenY
    end
end

function ModelPreview:Apply(reference)
    if self.destroyed then return nil, "The model preview is closed." end
    local value, message = settings(reference)
    if not value then
        self.ready = false
        self:SetHidden(true)
        return nil, message
    end
    local applied = self.applied or {}
    local setting = "model"
    local ok, reason = pcall(function()
        local changed = applied.npc ~= value.npc or applied.modelType ~= value.modelType
        local model = self.model
        if changed then model:SetModel(ui.ModelType[value.modelType], value.npc) end
        if changed or applied.frameSize ~= value.frameSize then model:SetSize(value.frameSize, value.frameSize) end
        setting = "camera distance"
        if changed or applied.viewDistance ~= value.viewDistance then model.viewDistance = value.viewDistance end
        setting = "screen offset"
        self:UpdateScreenOffset(value, changed)
        setting = "world offset"
        if changed or applied.worldX ~= value.worldX or applied.worldY ~= value.worldY or applied.worldZ ~= value.worldZ then
            offset(model, "worldOffset", value.worldX, value.worldY, value.worldZ)
        end
        setting = "model transform"
        if changed or applied.scale ~= value.scale then
            model:SetTransform(Vector3.new(0, 0, 0),
                Vector3.new(0, 0, 0),
                Vector3.new(value.scale, value.scale, value.scale), 0)
        end
        setting = "animation"
        if changed or applied.animation ~= value.animation then model.animID = value.animation end
    end)
    if not ok then
        self.applied, self.ready = nil, false
        self:SetHidden(true)
        return nil, "Could not apply " .. setting .. ": " .. tostring(reason)
    end
    self.applied, self.frameSize, self.ready = value, value.frameSize, true
    self.layoutSize = value.layoutSize
    self:SetHidden(false)
    return true
end

function ModelPreview:SetPos(x, y, layoutOffsetX)
    if self.destroyed then return end
    self.layoutOffsetX = layoutOffsetX or 0
    if self.applied then self:UpdateScreenOffset(self.applied) end
    if self.model.x ~= x or self.model.y ~= y then self.model:SetPos(x, y) end
end

function ModelPreview:SetHidden(hidden)
    if self.destroyed then return end
    hidden = hidden == true or not self.ready
    if self.model.hidden ~= hidden then self.model.hidden = hidden end
end

function ModelPreview:Hide()
    self:SetHidden(true)
end

function ModelPreview:Destroy(detached)
    if self.destroyed then return end
    self.destroyed = true
    if not detached and self.model then self.model:Destroy() end
    self.applied, self.model, self.ready = nil, nil, false
    self.layoutOffsetX, self.renderedScreenX, self.renderedScreenY = nil, nil, nil
end

return ModelPreview
