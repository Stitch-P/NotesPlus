-- Quests: pick a series, then a quest. Progress is 0 or 1 (finished or not); the note also says if it's been started.

local QuestSource = require("src/tracking/core/quest_source")

local Vars = require("src/tracking/core/vars")
local ConfigReader = require("src/tracking/core/config_reader")
local Skills = require("src/tracking/features/skills")

local Quests = {}

local STANDALONE, STANDALONE_MINI = "Standalone quests", "Standalone miniquests"

-- The quest list comes from the game's own data the first time it's needed; if it can't be read the list
-- is empty. Loaded lazily so the plugin start isn't slowed down.
local ENTRIES, LOOKUP, byId, byKey, live
local function dataset()
    if ENTRIES then return end
    local ok, source = pcall(QuestSource.Load)
    if ok and source then
        ENTRIES, live = source.ENTRIES, true
        LOOKUP = setmetatable({}, { __index = function(_, id) return source.LOOKUP(id) end })
    else
        ENTRIES, LOOKUP = {}, setmetatable({}, { __index = function() return nil end })
    end
    byId, byKey = {}, {}
    for _, quest in ipairs(ENTRIES) do
        quest.key = "quest:" .. quest.id
        byId[quest.id], byKey[quest.key] = quest, quest
    end
end

function Quests.source() dataset(); return live and "game" or "snapshot" end

local function groupName(quest)
    return quest.series or (quest.mini and STANDALONE_MINI or STANDALONE)
end

-- A quest's sprite id from its name (achievement config names don't match quest config names), or nil.
local byName
local function nameKey(name) return (tostring(name):lower():gsub("[^%w]", "")) end
function Quests.spriteByName(name)
    dataset()
    if not byName then
        byName = {}
        for _, quest in ipairs(ENTRIES) do
            if quest.sprite and type(quest.name) == "string" then byName[nameKey(quest.name)] = quest.sprite end
        end
    end
    return type(name) == "string" and byName[nameKey(name)] or nil
end

function Quests.info(key)
    dataset()
    return byKey[key]
end

function Quests.loadedEntries()
    return ENTRIES
end

local function readValue(name)
    local entry = Vars.resolveVar(name)
    return entry and Vars.readEntry(entry) or nil
end

-- "finished" is the end value; "started" is the start value (nil when the variable can't be read yet).
function Quests.state(quest)
    if quest.ref then
        local finished = ConfigReader.Field(quest.ref, "hasFinishedQuest")
        if finished == true then return "done" end
        local started = ConfigReader.Field(quest.ref, "hasStartedQuest")
        if started ~= nil then return started and "started" or "new" end
    end
    local value = readValue(quest.var)
    if value == nil then return nil end
    if value >= quest.finish then return "done" end
    return value >= quest.start and "started" or "new"
end

function Quests.randomCandidate(quest)
    if not ENTRIES or Quests.state(quest) ~= "new" then return nil end
    for _, need in ipairs(quest.skills or {}) do
        local skill = Skills.SKILL_BY_TYPE[need[1]]
        local level = skill and Skills.readSkillLevel(skill)
        if level == nil or level < need[2] then return nil end
    end
    for _, questId in ipairs(quest.quests or {}) do
        local required = byId[questId]
        if required then
            if Quests.state(required) ~= "done" then return nil end
        else
            local requiredInfo = LOOKUP[questId]
            if not requiredInfo then return nil end
            local finished = requiredInfo[5] and ConfigReader.Field(requiredInfo[5], "hasFinishedQuest")
            if finished ~= true then
                if finished == false then return nil end
                local value = readValue(requiredInfo[3])
                if value == nil or type(requiredInfo[4]) ~= "number" or value < requiredInfo[4] then return nil end
            end
        end
    end
    return groupName(quest), {
        kind = "quest", key = quest.key, label = quest.name, varName = quest.var, varId = quest.varId,
        spriteName = quest.sprite and ("#" .. quest.sprite) or nil,
        rank = quest.num or 999, steps = 1, defaultTarget = 1, quest = quest,
    }
end

-- Series in alphabetical order, with the standalone quests last. A series you've finished completely
-- has nothing left to track, so it isn't listed.
function Quests.groups()
    dataset()
    local names, seen = {}, {}
    for _, quest in ipairs(ENTRIES) do
        local name = groupName(quest)
        if not seen[name] and Quests.state(quest) ~= "done" then seen[name] = true; names[#names + 1] = name end
    end
    table.sort(names, function(a, b)
        local left, right = a == STANDALONE or a == STANDALONE_MINI, b == STANDALONE or b == STANDALONE_MINI
        if left ~= right then return right end
        if left and right then return a == STANDALONE end
        return a:lower() < b:lower()
    end)
    local list = {}
    for index, name in ipairs(names) do list[index] = { name = name } end
    return list
end

function Quests.options(group)
    dataset()
    local name = type(group) == "table" and group.name or group
    local options = {}
    for _, quest in ipairs(ENTRIES) do
        if groupName(quest) == name then
            options[#options + 1] = {
                kind = "quest", key = quest.key, label = quest.name, varName = quest.var, varId = quest.varId,
                description = Quests.summary(quest), spriteName = quest.sprite and ("#" .. quest.sprite) or nil,
                rank = quest.num or 999, steps = 1, defaultTarget = 1, quest = quest,
            }
        end
    end
    return options
end

local function lines(text) return text and text ~= "" and text or nil end

local function itemName(entry)
    local ok, name = pcall(function() return config.Obj.FromID(entry[1]).name end)
    local text = ok and type(name) == "string" and name ~= "" and name ~= "null" and name or ("Item " .. entry[1])
    if entry[2] and entry[2] > 1 then text = entry[2] .. " x " .. text end
    if entry[3] and entry[3] ~= "" then text = text .. " " .. entry[3] end
    return text
end

local MAX_ITEM_REQUIREMENTS = 6

local function itemLines(list)
    local parts = {}
    for _, entry in ipairs(list or {}) do parts[#parts + 1] = itemName(entry) end
    return #parts > 0 and table.concat(parts, "\n") or nil
end

-- The tooltip text breaks lines with <br>, not newlines.
local function breaks(text) return (text:gsub("\n", "<br>")) end

local function section(title, body)
    return body and ("<col=FFD27F>" .. title .. "</col><br>" .. breaks(body)) or nil
end

local function startText(quest)
    local start = lines(quest.startPoint)
    if start and quest.place then start = start .. " (" .. quest.place .. ")" end
    return start or lines(quest.place)
end

-- Plain one-paragraph version for the editor (no colour tags or line breaks).
function Quests.summary(quest)
    local parts = { lines(quest.desc) }
    local start = startText(quest)
    if start then parts[#parts + 1] = "Start: " .. start end
    return table.concat(parts, " ")
end

-- The hover text: description, start point, difficulty, combat, items needed and rewards.
local descriptionCache = {}
function Quests.description(key)
    dataset()
    if descriptionCache[key] then return descriptionCache[key] end
    local quest = byKey[key]
    if not quest then return nil end
    local parts = {}
    parts[#parts + 1] = lines(quest.desc) and breaks(quest.desc)
    local facts = {}
    if quest.diff and quest.diff ~= "" then facts[#facts + 1] = "Difficulty: " .. quest.diff end
    if quest.length and quest.length ~= "" then facts[#facts + 1] = "Length: " .. quest.length end
    if quest.qp then facts[#facts + 1] = "Quest points: " .. quest.qp end
    if #facts > 0 then parts[#parts + 1] = "<col=AAAAAA>" .. table.concat(facts, "<br>") .. "</col>" end
    parts[#parts + 1] = section("Start point", startText(quest))
    parts[#parts + 1] = section("Combat", lines(quest.combat))
    parts[#parts + 1] = section("Items", lines(quest.items) or itemLines(quest.reqItems))
    local rewards = {}
    for _, text in ipairs({ quest.xp, quest.xp_prayer, quest.xp_defence, quest.xp_constitution, quest.xp_invention,
        itemLines(quest.rewardItems), quest.other }) do
        if text and text ~= "" then rewards[#rewards + 1] = text end
    end
    parts[#parts + 1] = section("Rewards", #rewards > 0 and table.concat(rewards, "\n") or nil)
    local text = table.concat(parts, "<br><br>")
    descriptionCache[key] = text
    return text
end

-- The hover text split up so the interface can show item icons: body text, then item rows for what the quest needs and
-- what it gives. Returns nil when the quest has no items to show (the plain hover text is used then).
function Quests.rich(key)
    dataset()
    local quest = byKey[key]
    if not quest then return nil end
    local function rows(list)
        local result = {}
        for _, entry in ipairs(list or {}) do
            result[#result + 1] = { obj = entry[1], label = itemName(entry) }
        end
        return result
    end
    local needRows, rewardRows = rows(quest.reqItems), rows(quest.rewardItems)
    if #needRows == 0 and #rewardRows == 0 then return nil end
    local parts = {}
    parts[#parts + 1] = lines(quest.desc) and breaks(quest.desc)
    local facts = {}
    if quest.diff and quest.diff ~= "" then facts[#facts + 1] = "Difficulty: " .. quest.diff end
    if quest.length and quest.length ~= "" then facts[#facts + 1] = "Length: " .. quest.length end
    if quest.qp then facts[#facts + 1] = "Quest points: " .. quest.qp end
    if #facts > 0 then parts[#parts + 1] = "<col=AAAAAA>" .. table.concat(facts, "<br>") .. "</col>" end
    parts[#parts + 1] = section("Start point", startText(quest))
    parts[#parts + 1] = section("Combat", lines(quest.combat))
    local rewardText = {}
    for _, text in ipairs({ quest.xp, quest.xp_prayer, quest.xp_defence, quest.xp_constitution, quest.xp_invention, quest.other }) do
        if text and text ~= "" then rewardText[#rewardText + 1] = breaks(text) end
    end
    return {
        key = key, body = table.concat(parts, "<br><br>"),
        needText = #needRows == 0 and lines(quest.items) and breaks(quest.items) or nil, needRows = needRows,
        rewardText = #rewardText > 0 and table.concat(rewardText, "<br>") or nil, rewardRows = rewardRows,
    }
end

local function questNeed(id)
    local quest = byId[id]
    local name, sprite, var, finish, ref
    if quest then name, sprite, var, finish, ref = quest.name, quest.sprite, quest.var, quest.finish, quest.ref
    elseif LOOKUP[id] then name, sprite, var, finish, ref = LOOKUP[id][1], LOOKUP[id][2], LOOKUP[id][3], LOOKUP[id][4], LOOKUP[id][5]
    else return nil end
    local done = ref and ConfigReader.Field(ref, "hasFinishedQuest")
    if done ~= nil then return { kind = "quest", name = name, sprite = sprite, met = done == true } end
    local value = readValue(var)
    return { kind = "quest", name = name, sprite = sprite, met = value == nil or value >= finish }
end

-- Skill and quest requirements, each flagged met or not (same shape as the area task ones).
function Quests.requirements(key)
    dataset()
    local quest = byKey[key]
    local list = {}
    if not quest then return list end
    for _, need in ipairs(quest.skills or {}) do
        local entry = Skills.SKILL_BY_TYPE[need[1]]
        if entry then
            local have = Skills.readSkillLevel(entry)
            list[#list + 1] = { kind = "skill", skill = entry, name = entry.name, level = need[2], have = have,
                met = have == nil or have >= need[2], icon = Skills.skillIconRef(entry) }
        end
    end
    for _, id in ipairs(quest.quests or {}) do
        local need = questNeed(id)
        if need then list[#list + 1] = need end
    end
    -- Items the quest needs: shown as the item's icon and how many, up to MAX_ITEM_REQUIREMENTS (the hover text lists all).
    local shown = 0
    for _, entry in ipairs(quest.reqItems or {}) do
        if shown >= MAX_ITEM_REQUIREMENTS then break end
        shown = shown + 1
        local name = itemName({ entry[1], 1, entry[3] })
        list[#list + 1] = { kind = "item", name = name, level = entry[2] or 1, icon = entry[1], met = true }
    end
    return list
end

-- Whether a quest you haven't started can be started now: every skill and quest requirement met (items are not
-- checked) and the quest not begun. nil when that can't be told yet. Also gives the quest's name and where it starts.
function Quests.readiness(key)
    dataset()
    local quest = byKey[key]
    if not quest then return nil end
    local state = Quests.state(quest)
    if state == nil then return nil end
    local ready = state == "new"
    for _, need in ipairs(Quests.requirements(key)) do
        if need.kind == "skill" and need.have == nil then return nil end
        if need.kind ~= "item" and not need.met then ready = false end
    end
    local start = startText(quest)
    start = start and start:gsub("<[^>]*>", ""):gsub("%s*\n%s*", ", ") or nil
    return { ready = ready, name = quest.name or key, start = start }
end

return { Quests = Quests }
