-- What the game knows about Slayer assignments: for each assignable monster its name, description, requirements and an
-- NPC to show (the structs in the Slayer masters' enums), and for each Reaper boss the same (the boss list enum).
-- Your current task variables hold the monster's / boss's id, so this is the lookup from that id to the details.

local ConfigReader = require("src/tracking/core/config_reader")

local SlayerTaskSource = {}

local MASTER_LIST = "SLAYER_MASTER_ENUM"
local MASTER_FALLBACK = { "TURAEL", "JACQUELYN", "MAZCHNA", "RAPTOR", "VANNAKA", "CHAELDAR", "DURADEL", "SUMONA",
    "KURADAL", "MORVRAN", "MANDRITH", "LANIAKEA" }
local BOSS_LIST = "BSLAYER_BOSS_LIST_ENUM"

local function structOf(value)
    if type(value) == "number" then return value >= 0 and ConfigReader.Struct(value) or nil end
    if value == nil then return nil end
    if ConfigReader.Field(value, "configName") ~= nil then return value end
    local structId = ConfigReader.Field(value, "id")
    return type(structId) == "number" and ConfigReader.Struct(structId) or nil
end

local function param(struct, name)
    return ConfigReader.StructParam(struct, name)
end

local function text(value)
    return type(value) == "string" and value ~= "" and value or nil
end

local function number(value)
    return type(value) == "number" and value or nil
end

-- An NPC parameter comes back as an NPC object (or a plain id); either way, the id when it is a real one.
local function npcId(value)
    local id = number(value)
    if id == nil and value ~= nil then id = number(ConfigReader.Field(value, "id")) end
    return id and id >= 0 and id or nil
end

local function enumsOfMasters()
    local list, seen = {}, {}
    local function add(enum)
        if enum ~= nil and not seen[enum] then seen[enum] = true; list[#list + 1] = enum end
    end
    for _, pair in ipairs(ConfigReader.EnumPairs(MASTER_LIST)) do
        local value = pair[2]
        if type(value) == "number" and value >= 0 then add(ConfigReader.Enum(value))
        elseif value ~= nil then add(value) end
    end
    if #list == 0 then
        for _, name in ipairs(MASTER_FALLBACK) do add(ConfigReader.Enum("SLAYER_MASTER_" .. name .. "_ENUM")) end
    end
    return list
end

local monsters, bosses
local bossModels = {}

local function bossInfo(struct)
    local bossId = struct and number(param(struct, "BSLAY_ID"))
    if not bossId then return nil end
    return {
        struct = struct, id = bossId, name = text(param(struct, "BSLAY_NAME")), description = text(param(struct, "CHEEVO_DETAILS")),
        npc = npcId(param(struct, "BSLAY_NPC")), zoom = number(param(struct, "BSLAY_ZOOM")),
        yoffset = number(param(struct, "BSLAY_YOFFSET")), combatLevel = number(param(struct, "BSLAY_COMBAT_LEVEL")),
        requirement = number(param(struct, "BSLAY_COMBAT_REQ")), minKills = number(param(struct, "BSLAY_MIN_NO")),
        maxKills = number(param(struct, "BSLAY_MAX_NO")), points = number(param(struct, "BSLAY_POINTS")),
    }
end

function SlayerTaskSource.BossModel(name)
    if type(name) ~= "string" or name == "" then return nil end
    if bossModels[name] == nil then bossModels[name] = bossInfo(ConfigReader.Struct(name)) or false end
    return bossModels[name] or nil
end

-- { [task id] = { id, name, description, npc, level, combat } }, or nil when unreadable.
function SlayerTaskSource.Monsters()
    if monsters ~= nil then return monsters or nil end
    monsters = false
    if not ConfigReader.Available() then return nil end
    local found, count = {}, 0
    for _, enum in ipairs(enumsOfMasters()) do
        for _, pair in ipairs(ConfigReader.EnumPairs(enum)) do
            local struct = structOf(pair[2])
            local taskId = struct and number(param(struct, "SLAYER_TYPE"))
            if taskId and not found[taskId] then
                found[taskId] = {
                    struct = struct, id = taskId, name = text(param(struct, "SLAYER_NAME")), description = text(param(struct, "SLAYER_DESCRIPTION")),
                    npc = npcId(param(struct, "SLAYER_EXAMPLE_NPC")), level = number(param(struct, "SLAYER_SL_REQ")),
                    combat = number(param(struct, "SLAYER_CL_REQ")),
                }
                count = count + 1
            end
        end
    end
    if count < 20 then return nil end
    monsters = found
    return found
end

-- { [boss id] = { id, name, description, npc, zoom, yoffset, combatLevel, requirement, minKills, maxKills, points } }.
function SlayerTaskSource.Bosses()
    if bosses ~= nil then return bosses or nil end
    bosses = false
    if not ConfigReader.Available() then return nil end
    local found, count = {}, 0
    for _, pair in ipairs(ConfigReader.EnumPairs(BOSS_LIST)) do
        local struct = structOf(pair[2])
        local bossId = struct and number(param(struct, "BSLAY_ID"))
        if bossId and not found[bossId] then
            found[bossId] = bossInfo(struct)
            count = count + 1
        end
    end
    if count < 10 then return nil end
    bosses = found
    return found
end

function SlayerTaskSource.Clear() monsters, bosses, bossModels = nil, nil, {} end

return SlayerTaskSource
