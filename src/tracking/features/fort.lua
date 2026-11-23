-- Fort Forinthry buildings. Each building is a database row (BUILDING_INFO_<NAME>) holding its name, picture and what each
-- tier unlocks; how far it is built is a 4-bit variable (PLAYER_FORT_BUILDING_<NAME>: 0 = not built, then the tier).
-- Rows are found by walking the row list a little each frame (Pump), so buildings the game adds show up by themselves.

local ConfigReader = require("src/tracking/core/config_reader")
local Vars = require("src/tracking/core/vars")
local Skills = require("src/tracking/features/skills")

local Fort = {}

Fort.GROUP = "Fort Forinthry"
local PREFIX = "BUILDING_INFO_"
local SEEDS = { "TOWNHALL", "TOWN_HALL", "COMMAND_CENTRE", "CHAPEL", "WORKSHOP" }
local MAX_ID, PER_FRAME = 40000, 400

local cursor, done = 0, false
local rows, order = {}, {}      -- rows[suffix] = row
local built, byKey

local function addRow(suffix, row)
    if rows[suffix] then return end
    rows[suffix] = row
    order[#order + 1] = suffix
    built = nil
end

-- Walks a slice of the row list; call once per frame.
function Fort.Pump()
    if done then return end
    local last = math.min(MAX_ID, cursor + PER_FRAME - 1)
    local ok = pcall(function()
        for index = cursor, last do
            local okRow, row = pcall(function() return config.DBRow.FromID(index) end)
            if okRow and row then
                local okName, name = pcall(function() return row.configName end)
                if okName and type(name) == "string" and name:upper():sub(1, #PREFIX) == PREFIX then
                    addRow(name:upper():sub(#PREFIX + 1), row)
                end
            end
        end
    end)
    cursor = last + 1
    if not ok or cursor > MAX_ID then
        done = true
    end
end

local function text(value)
    if type(value) == "string" and value ~= "" and value ~= "null" then return value end
end

local function prettify(name)
    return (name:lower():gsub("_", " "):gsub("(%a)(%w*)", function(a, b) return a:upper() .. b end))
end

local function varFor(suffix)
    for _, candidate in ipairs({ suffix, (suffix:gsub("_", "")) }) do
        local name = "PLAYER_FORT_BUILDING_" .. candidate
        if Vars.resolveVar(name) then return name end
    end
end

-- SkillType order used by the game's recipe requirements (type 22 = Construction).
local SKILL_TYPES = { "ATTACK", "DEFENCE", "STRENGTH", "HITPOINTS", "RANGED", "PRAYER", "MAGIC", "COOKING", "WOODCUTTING",
    "FLETCHING", "FISHING", "FIREMAKING", "CRAFTING", "SMITHING", "MINING", "HERBLORE", "AGILITY", "THIEVING", "SLAYER",
    "FARMING", "RUNECRAFTING", "HUNTER", "CONSTRUCTION", "SUMMONING", "DUNGEONEERING", "DIVINATION", "INVENTION",
    "ARCHAEOLOGY", "NECROMANCY" }
local CONFIG_KINDS = { "Loc", "Struct", "Obj", "NPC", "DBRow" }

-- The config object of one tier of a building ("player_fort_command_centre_tier3").
local function tierConfig(suffix, tier)
    for _, name in ipairs({ suffix, (suffix:gsub("_", "")), (suffix:gsub("^TOWNHALL$", "TOWN_HALL")) }) do
        for _, kind in ipairs(CONFIG_KINDS) do
            local object = ConfigReader.Config(kind, "PLAYER_FORT_" .. name .. "_TIER" .. tier)
            if object then return object, kind end
        end
    end
end

-- What a tier needs to build: { { skill = SkillType name, level = n }, ... } from its recipe requirement params.
local function requirementsOf(suffix, tier)
    local object, kind = tierConfig(suffix, tier)
    local list = {}
    if not object then return list, nil end
    -- When the tier is an item of its own (the bench you see in the game), its picture is that item's icon.
    local objectId = kind == "Obj" and ConfigReader.Field(object, "id") or nil
    for index = 1, 6 do
        local skillType = ConfigReader.Param(object, "RECIPE_REQUIREMENT_TYPE_" .. index)
        local level = ConfigReader.Param(object, "RECIPE_REQUIREMENT_VALUE_" .. index)
        if type(skillType) == "number" and type(level) == "number" and SKILL_TYPES[skillType + 1] then
            list[#list + 1] = { skill = SKILL_TYPES[skillType + 1], level = level }
        end
    end
    return list, kind, type(objectId) == "number" and objectId or nil
end

local function build()
    if built then return end
    if ConfigReader.Available() then
        for _, suffix in ipairs(SEEDS) do
            local row = ConfigReader.Row(PREFIX .. suffix)
            if row then addRow(suffix, row) end
        end
    end
    built, byKey = {}, {}
    local seenVar = {}
    for _, suffix in ipairs(order) do
        local row = rows[suffix]
        local var = varFor(suffix)
        if var and not seenVar[var] then
            seenVar[var] = true
            local tiers = {}
            for column = 4, 6 do
                local data = ConfigReader.Column(row, column)
                local lines = {}
                for _, value in ipairs(data and data.values or {}) do
                    if text(value) then lines[#lines + 1] = value end
                end
                if #lines > 0 then tiers[#tiers + 1] = lines end
            end
            local model = ConfigReader.Value(row, 3)
            local needs, itemId = {}, nil
            for tier = 1, math.max(1, #tiers) do
                local list, kind, objectId = requirementsOf(suffix, tier)
                needs[tier] = list
                itemId = objectId or itemId
            end
            local entry = {
                key = "fort:" .. suffix:lower(), name = text(ConfigReader.Value(row, 2)) or prettify(suffix), var = var, suffix = suffix,
                model = type(model) == "number" and model > 0 and model or nil, obj = itemId, tiers = tiers, needs = needs,
            }
            built[#built + 1], byKey[entry.key] = entry, entry
        end
    end
    table.sort(built, function(a, b) return a.name:lower() < b.name:lower() end)
end

function Fort.buildings() build() return built end
function Fort.info(key) build() return byKey[key] end

-- A saved building key looks right, whether or not its row has been found yet (the rows are read a few per frame, so
-- they may not all be known when notes load).
function Fort.isKey(key) return type(key) == "string" and key:match("^fort:[%w_]+$") ~= nil end

function Fort.options()
    build()
    local options = {}
    for _, building in ipairs(built) do
        local description = "Set the tier to reach (1 to " .. math.max(1, #building.tiers) .. "). Building it to that tier completes the goal."
        for tier, list in ipairs(building.needs or {}) do
            local parts = {}
            for _, need in ipairs(list) do
                local entry = Skills.SKILL_BY_TYPE[need.skill]
                parts[#parts + 1] = (entry and entry.name or need.skill) .. " " .. need.level
            end
            if #parts > 0 then description = description .. " Tier " .. tier .. ": " .. table.concat(parts, ", ") .. "." end
        end
        options[#options + 1] = {
            kind = "building", key = building.key, label = building.name, varName = building.var, defaultTarget = 1,
            objId = building.obj, modelId = not building.obj and building.model or nil, building = building, description = description,
        }
    end
    return options
end

-- The skill levels a tier needs, each marked met or not, for the note's requirement row.
function Fort.requirements(key, tier)
    local building = Fort.info(key)
    local list = {}
    if not building then return list end
    for _, need in ipairs(building.needs and building.needs[tier or 1] or {}) do
        local entry = Skills.SKILL_BY_TYPE[need.skill]
        if entry then
            local have = Skills.readSkillLevel(entry)
            list[#list + 1] = { kind = "skill", skill = entry, name = entry.name, level = need.level, have = have,
                met = have == nil or have >= need.level, icon = Skills.skillIconRef(entry) }
        end
    end
    return list
end

local function safe(value) return (tostring(value):gsub("<", "["):gsub(">", "]")) end

-- The hover card: what each tier unlocks, and which ones you have built.
function Fort.card(key)
    local building = Fort.info(key)
    if not building then return nil end
    local entry = Vars.resolveVar(building.var)
    local level = entry and Vars.readEntry(entry)
    local lines = { safe(building.name) .. (level and (level > 0 and (" - tier " .. level .. " built") or " - not built yet") or "") }
    for index, tier in ipairs(building.tiers) do
        local state = level and (level >= index and "built" or "not built") or "unknown"
        lines[#lines + 1] = "<br>Tier " .. index .. " (" .. state .. "):"
        for _, line in ipairs(tier) do lines[#lines + 1] = "<br>- " .. safe(line) end
    end
    return { key = key, body = table.concat(lines) }
end

return { Fort = Fort }