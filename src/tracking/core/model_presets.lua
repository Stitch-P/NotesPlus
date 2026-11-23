local ConfigReader = require("src/tracking/core/config_reader")

local ModelPresets = {}
local presetModels = {}

local function presetModel(preset)
    if type(preset) ~= "table" then return nil end
    if preset.models ~= nil then
        if type(preset.models) ~= "table" or #preset.models == 0 then return nil end
        local models = {}
        for index, member in ipairs(preset.models) do
            models[index] = presetModel(member)
            if not models[index] then return nil end
        end
        return {models = models, rowHeight = preset.rowHeight, columns = preset.columns}
    end
    if type(preset.npc) ~= "string" or preset.npc == "" then return nil end
    local resolved = presetModels[preset]
    if not resolved then
        local npc = ConfigReader.Field(ConfigReader.Config("NPC", preset.npc), "id")
        if type(npc) ~= "number" or npc < 0 or npc % 1 ~= 0 then return nil end
        local animation = -1
        if type(preset.animation) == "string" then animation = ConfigReader.Field(ConfigReader.Config("Seq", preset.animation), "id")
        elseif preset.animation ~= nil and preset.animation ~= -1 then return nil end
        if type(animation) ~= "number" or animation < -1 or animation % 1 ~= 0 then return nil end
        resolved = {npc = npc, animation = animation}
        presetModels[preset] = resolved
    end
    local reference = {}
    for key, value in pairs(preset) do if key ~= "variants" then reference[key] = value end end
    reference.npc, reference.animation, reference.preset = resolved.npc, resolved.animation, preset.preset ~= false
    return reference
end

function ModelPresets.Preview(root, variant)
    if type(root) ~= "table" then return nil end
    local selected = type(root.variants) == "table" and root.variants[variant]
    return presetModel(selected or root)
end

function ModelPresets.Clear()
    presetModels = {}
end

return ModelPresets
