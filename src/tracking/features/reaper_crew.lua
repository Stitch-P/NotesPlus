-- Reaper Crew: kill every Reaper boss at least once. The boss list is the game's own (the Soul Reaper's boss list enum);
-- each boss's achievement says which kill-count variables to look at (normal and hard mode both count). Nothing here is
-- typed in by hand except the pet icon matching, so a boss the game adds turns up by itself.

local ConfigReader = require("src/tracking/core/config_reader")
local Vars = require("src/tracking/core/vars")

local ReaperCrew = {}

ReaperCrew.KEY = "reaper-crew"
ReaperCrew.GROUP = "Combat"
ReaperCrew.SPRITE = "AIF_BOSS_SLAYER_POINTS_ICON_SML"

local BOSS_LIST = "BSLAYER_BOSS_LIST_ENUM"
local KILLS_PREFIX = "BSLAY_KILLS_"

local list

local function structOf(value)
    if type(value) == "number" then return value >= 0 and ConfigReader.Struct(value) or nil end
    if value == nil then return nil end
    if ConfigReader.Field(value, "configName") ~= nil then return value end
    local structId = ConfigReader.Field(value, "id")
    return type(structId) == "number" and ConfigReader.Struct(structId) or nil
end

local function varName(var)
    local name = ConfigReader.Field(var, "configName")
    return type(name) == "string" and name ~= "" and name or nil
end

-- The kill-count variables a boss's achievement tests (the "total 1" tests on BSLAY_KILLS_*).
local function killVars(achievement)
    local found, seen = {}, {}
    local requirements = achievement and ConfigReader.Field(achievement, "requirements")
    local totals = type(requirements) == "table" and requirements.varTotals
    for _, test in ipairs(type(totals) == "table" and totals or {}) do
        local vars = ConfigReader.Field(test, "vars")
        for _, var in ipairs(type(vars) == "table" and vars or {}) do
            local name = varName(var)
            if name and name:sub(1, #KILLS_PREFIX) == KILLS_PREFIX and not seen[name] then
                seen[name] = true
                found[#found + 1] = name
            end
        end
    end
    return found
end

-- The same boss's pet as its picture, borrowed from the Bossing lists (matched by the boss's kill-count name).
local function petIcon(vars)
    local ok, icon = pcall(function()
        local first = vars[1]
        if not first then return nil end
        local suffix = first:sub(#KILLS_PREFIX + 1):gsub("_HARDMODE$", ""):gsub("_SOLO$", "")
        local findObjectID = require("src/tracking/core/objects").findObjectID
        local Icons = require("src/tracking/features/icons")
        for _, boss in ipairs(require("src/tracking/data/bosses").BOSSES) do
            for _, kill in ipairs(boss.kills or {}) do
                if kill[2] == suffix then
                    local pet = boss.pet or boss.pets and boss.pets[1]
                    return pet and (Icons.bossPetIcon(pet) or findObjectID(pet)) or nil
                end
            end
        end
    end)
    return ok and icon or nil
end

-- { { id, name, vars = { "BSLAY_KILLS_..." }, iconObj } } in the game's order, or nil when the data can't be read.
function ReaperCrew.bosses()
    if list ~= nil then return list or nil end
    list = false
    if not ConfigReader.Available() then return nil end
    local byId, order = {}, {}
    for _, pair in ipairs(ConfigReader.EnumPairs(BOSS_LIST)) do
        local struct = structOf(pair[2])
        local bossId = struct and ConfigReader.StructParam(struct, "BSLAY_ID")
        local name = struct and ConfigReader.StructParam(struct, "BSLAY_NAME")
        local configName = struct and ConfigReader.Field(struct, "configName")
        if type(bossId) == "number" and type(name) == "string" and name ~= "" then
            local vars = killVars(ConfigReader.StructParam(struct, "BSLAY_ACHIEVEMENT"))
            -- The same boss can be listed twice (Rex Matriarchs); keep the plainer entry.
            local known = byId[bossId]
            if #vars > 0 and (not known or #tostring(configName) < #tostring(known.configName)) then
                if not known then order[#order + 1] = bossId end
                byId[bossId] = { id = bossId, name = name, vars = vars, configName = configName }
            end
        end
    end
    if #order < 10 then return nil end
    table.sort(order)
    local result = {}
    for _, bossId in ipairs(order) do
        local boss = byId[bossId]
        boss.iconObj = petIcon(boss.vars)
        result[#result + 1] = boss
    end
    list = result
    return result
end

-- What the achievement gives: the game's own reward text ("'the Reaper' title. Permanent +2 Prayer Bonus, +20 Armour, ...")
-- split into the title and one line per bonus, each with the skill whose icon goes beside it.
local BONUS_SKILLS = {
    { "prayer", "PRAYER" }, { "armour", "DEFENCE" }, { "life point", "HITPOINTS" }, { "melee", "ATTACK" },
    { "ranged", "RANGED" }, { "magic", "MAGIC" }, { "necromancy", "NECROMANCY" },
}

local function bonusSkill(text)
    local lower = text:lower()
    for _, entry in ipairs(BONUS_SKILLS) do
        if lower:find(entry[1], 1, true) then return entry[2] end
    end
end

-- Pure text split, kept apart so it can be checked without the game.
function ReaperCrew.parseReward(text)
    if type(text) ~= "string" or text == "" then return nil end
    text = text:gsub("%s+", " ")
    local head, rest = text:match("^(.-)%s*[Pp]ermanent%s+(.*)$")
    local lines = {}
    local function trim(value) return (value:gsub("^[%s%.]+", ""):gsub("[%s%.]+$", "")) end
    if not head then
        lines[1] = { text = trim(text), skill = nil, title = true }
        return lines
    end
    head = trim(head)
    if head ~= "" then lines[#lines + 1] = { text = head, title = true } end
    for part in (rest .. ","):gmatch("%s*(.-)%s*,") do
        local item = trim(part)
        if item ~= "" then lines[#lines + 1] = { text = item, skill = bonusSkill(item) } end
    end
    return lines
end

local rewardLines
function ReaperCrew.reward()
    if rewardLines ~= nil then return rewardLines or nil end
    rewardLines = false
    if not ConfigReader.Available() then return nil end
    local achievement = ConfigReader.Achievement("CHEEVO_REAPER_CREW") or ConfigReader.Achievement(1779)
    local lines = ReaperCrew.parseReward(achievement and ConfigReader.Field(achievement, "reward"))
    if not lines or #lines == 0 then return nil end
    rewardLines = lines
    return lines
end

function ReaperCrew.Clear() list, rewardLines = nil, nil end

return { ReaperCrew = ReaperCrew }