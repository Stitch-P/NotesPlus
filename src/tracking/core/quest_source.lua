-- Builds the quest list from the game's own quest configs (config.Quest), its params and the quest list enums, so new
-- and changed quests show up without a plugin update. Returns nil when the game data can't be read, and the Quests
-- feature then shows no quests.

local ConfigReader = require("src/tracking/core/config_reader")

local QuestSource = {}

local MAX_ID, MAX_GAP, MIN_QUESTS = 2000, 200, 50
local NO_SERIES = 42

-- SkillType order used by the client; also accepts the skill's own name.
local SKILLS = { "ATTACK", "DEFENCE", "STRENGTH", "HITPOINTS", "RANGED", "PRAYER", "MAGIC", "COOKING", "WOODCUTTING",
    "FLETCHING", "FISHING", "FIREMAKING", "CRAFTING", "SMITHING", "MINING", "HERBLORE", "AGILITY", "THIEVING", "SLAYER",
    "FARMING", "RUNECRAFTING", "HUNTER", "CONSTRUCTION", "SUMMONING", "DUNGEONEERING", "DIVINATION", "INVENTION",
    "ARCHAEOLOGY", "NECROMANCY" }
local SKILL_ALIASES = { CONSTITUTION = "HITPOINTS", RANGE = "RANGED", RANGING = "RANGED", HUNTING = "HUNTER" }

local function skillName(value)
    if type(value) == "number" then return SKILLS[value + 1] end
    if type(value) == "string" then
        local name = value:upper()
        return SKILL_ALIASES[name] or name
    end
    if value ~= nil then
        local id = ConfigReader.Field(value, "id")
        if type(id) == "number" then return SKILLS[id + 1] end
        local name = ConfigReader.Field(value, "configName") or ConfigReader.Field(value, "name")
        if type(name) == "string" then return skillName(name) end
        local text = tostring(value):match("([%a_]+)$")
        if text then return skillName(text) end
    end
end

local function clean(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub("%s*<br%s*/?>%s*", "\n"):gsub("^%s+", ""):gsub("%s+$", "")
    return text ~= "" and text or nil
end

local function number(value)
    if type(value) == "number" then return value end
    if value ~= nil then
        local id = ConfigReader.Field(value, "id")
        if type(id) == "number" then return id end
    end
end

local function enumText(enum, key)
    if key == nil then return nil end
    local value = ConfigReader.EnumValue(enum, key)
    return type(value) == "string" and value ~= "" and value or nil
end

local function itemList(quest, prefix)
    local list = {}
    for index = 1, 12 do
        local obj = number(ConfigReader.Param(quest, prefix .. index))
        if obj then
            local quantity = number(ConfigReader.Param(quest, prefix .. index .. "_QTY")) or 1
            local suffix = ConfigReader.Param(quest, prefix .. index .. "_SUFFIX")
            list[#list + 1] = { obj, quantity, type(suffix) == "string" and suffix or "" }
        end
    end
    return #list > 0 and list or nil
end

local function progressVar(quest)
    local list = ConfigReader.Field(quest, "masterQuestVars")
    local first = type(list) == "table" and list[1] or nil
    if not first then return nil end
    local var = ConfigReader.Field(first, "varPlayer")
    local name = ConfigReader.Field(var, "configName")
    local varId = ConfigReader.Field(var, "id")
    local start, finish = ConfigReader.Field(first, "startState"), ConfigReader.Field(first, "endState")
    if type(name) ~= "string" or name == "" or type(start) ~= "number" or type(finish) ~= "number" then return nil end
    return name, varId, start, finish
end

-- Params like QUEST_DISABLED are flags; a stored 0 or false means off.
local function flag(value)
    return value ~= nil and value ~= false and value ~= 0
end

local function listed(quest)
    if ConfigReader.Field(quest, "deprecated") == true then return false end
    local name = ConfigReader.Field(quest, "name")
    if type(name) ~= "string" or name == "" then return false end
    if ConfigReader.Param(quest, "QUEST_ID") == nil then return false end
    if flag(ConfigReader.Param(quest, "QUEST_DISABLED")) or flag(ConfigReader.Param(quest, "QUEST_HIDDEN")) then return false end
    return progressVar(quest) ~= nil
end

local function build(quest, enums)
    local var, varId, start, finish = progressVar(quest)
    local entry = {
        id = ConfigReader.Field(quest, "id"), name = ConfigReader.Field(quest, "name"), ref = quest,
        var = var, varId = varId, start = start, finish = finish,
        members = ConfigReader.Field(quest, "isMembers") == true,
    }
    local series = ConfigReader.Param(quest, "QUEST_SERIES")
    if type(series) == "number" and series ~= NO_SERIES then entry.series = enumText(enums.series, series) end
    local num = ConfigReader.Param(quest, "QUEST_SERIES_NUMBER")
    if type(num) == "number" then entry.num = num end
    if flag(ConfigReader.Param(quest, "QUEST_SUBLIST")) then entry.mini = true end
    local sprite = ConfigReader.Field(quest, "iconID")
    if type(sprite) ~= "number" or sprite <= 0 then sprite = number(ConfigReader.Param(quest, "QUEST_ICON_BIG")) end
    if type(sprite) == "number" and sprite > 0 then entry.sprite = sprite end
    entry.diff = enumText(enums.difficulty, ConfigReader.Field(quest, "difficulty"))
    entry.length = enumText(enums.length, ConfigReader.Param(quest, "QUEST_LENGTH"))
    entry.place = enumText(enums.location, ConfigReader.Param(quest, "QUEST_START_LOCATION"))
    local combat = enumText(enums.combat, ConfigReader.Param(quest, "QUEST_COMBAT_DIFFICULTY"))
    if combat and combat ~= "None" and combat ~= "Seasonal" then entry.combatLevel = combat end
    local points = ConfigReader.Field(quest, "questPoints")
    if type(points) == "number" and points > 0 then entry.qp = points end

    local skills = {}
    for _, need in ipairs(ConfigReader.Field(quest, "preReqSkills") or {}) do
        local name = skillName(ConfigReader.Field(need, "skillType"))
        local level = ConfigReader.Field(need, "minimumLevel")
        if name and type(level) == "number" then skills[#skills + 1] = { name, level } end
    end
    if #skills > 0 then entry.skills = skills end
    local quests = {}
    for _, need in ipairs(ConfigReader.Field(quest, "preReqQuests") or {}) do
        local id = ConfigReader.Field(need, "id")
        if type(id) == "number" then quests[#quests + 1] = id end
    end
    if #quests > 0 then entry.quests = quests end

    entry.desc = clean(ConfigReader.Param(quest, "QUEST_DESCRIPTION"))
    entry.startPoint = clean(ConfigReader.Param(quest, "QUEST_START_POINT"))
    entry.combat = clean(ConfigReader.Param(quest, "QUEST_COMBAT"))
    entry.items = clean(ConfigReader.Param(quest, "QUEST_REQ_ITEMS"))
    entry.xp = clean(ConfigReader.Param(quest, "QUEST_REWARDS_XP"))
    entry.other = clean(ConfigReader.Param(quest, "QUEST_REWARDS_OTHER"))
    entry.xp_prayer = clean(ConfigReader.Param(quest, "QUEST_REWARDS_XP_PRAYER"))
    entry.xp_defence = clean(ConfigReader.Param(quest, "QUEST_REWARDS_XP_DEFENCE"))
    entry.xp_constitution = clean(ConfigReader.Param(quest, "QUEST_REWARDS_XP_CONSTITUTION"))
    entry.xp_invention = clean(ConfigReader.Param(quest, "QUEST_REWARDS_XP_INVENTION"))
    entry.reqItems = itemList(quest, "QUEST_REQ_ITEM")
    entry.rewardItems = itemList(quest, "QUEST_REWARDS_ITEM")
    return entry
end

-- { ENTRIES = {...}, LOOKUP = function(id) } or nil.
function QuestSource.Load()
    if not ConfigReader.Available() then return nil end
    local enums = {
        series = ConfigReader.Enum("ql4_quest_categories_series"),
        difficulty = ConfigReader.Enum("ql4_quest_categories_difficulty"),
        length = ConfigReader.Enum("ql4_quest_categories_length"),
        location = ConfigReader.Enum("ql4_quest_categories_start_location"),
        combat = ConfigReader.Enum("ql4_quest_categories_combat_difficulty"),
    }
    local entries, misses = {}, 0
    for index = 0, MAX_ID do
        local quest = ConfigReader.Quest(index)
        if quest then
            misses = 0
            if listed(quest) then entries[#entries + 1] = build(quest, enums) end
        else
            misses = misses + 1
            if misses > MAX_GAP then break end
        end
    end
    if #entries < MIN_QUESTS then return nil end
    table.sort(entries, function(a, b) return a.name:lower() < b.name:lower() end)

    -- Quests another quest needs but that aren't tracked themselves: name, sprite, variable name and finish value.
    local function lookup(id)
        local quest = ConfigReader.Quest(id)
        if not quest then return nil end
        local var, _, _, finish = progressVar(quest)
        local sprite = ConfigReader.Field(quest, "iconID")
        if not var then return nil end
        return { ConfigReader.Field(quest, "name"), type(sprite) == "number" and sprite > 0 and sprite or nil, var, finish, quest }
    end
    return { ENTRIES = entries, LOOKUP = lookup }
end

QuestSource.skillName = skillName

return QuestSource
