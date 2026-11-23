-- Area tasks, built from the game's own achievements (the CHEEVO_AT<area>_<tier>_* set): name, description, sprite,
-- the variables that track them, their steps and parts, and the skill and quest requirements. New tasks and new
-- areas turn up on their own. Returns nil when the data can't be read, and the Tasks feature then shows no tasks.

local ConfigReader = require("src/tracking/core/config_reader")
local QuestSource = require("src/tracking/core/quest_source")

local TaskSource = {}

-- Tier words as they appear in names ("MED" is used as often as "MEDIUM").
local TIERS = { BEGINNER = "Beginner", BEG = "Beginner", EASY = "Easy", MEDIUM = "Medium", MED = "Medium", HARD = "Hard", ELITE = "Elite" }
local MIN_TASKS = 100

local function prettify(text)
    return (text:lower():gsub("_", " "):gsub("(%a)(%w*)", function(a, b) return a:upper() .. b end))
end

local function categoryName(value)
    if type(value) ~= "number" or value < 0 then return nil end
    local ok, name = pcall(function() return id.Category.FromID(value) end)
    if ok and type(name) == "string" then return name end
    if ok and name ~= nil then
        local configName = ConfigReader.Field(name, "configName")
        if type(configName) == "string" then return configName end
    end
end

local function descriptionOf(achievement)
    local text
    for _, entry in ipairs(ConfigReader.Field(achievement, "descriptions") or {}) do
        local kind = ConfigReader.Field(entry, "type")
        local line = ConfigReader.Field(entry, "text")
        if type(line) == "string" and line ~= "" and (text == nil or kind == 0) then text = line end
    end
    return text
end

local function varNameOf(var)
    local name = ConfigReader.Field(var, "configName")
    return type(name) == "string" and name ~= "" and name or nil
end

-- vars, steps, parts for one achievement; nil when it has no variable to track.
local function trackingOf(achievement)
    local requirements = ConfigReader.Field(achievement, "requirements")
    if type(requirements) ~= "table" then return nil end
    local totals = type(requirements.varTotals) == "table" and requirements.varTotals or {}
    local bits = type(requirements.varTestBits) == "table" and requirements.varTestBits or {}
    local vars, seen, parts = {}, {}, {}
    local function addVar(name)
        if name and not seen[name] then seen[name] = true; vars[#vars + 1] = name end
    end
    for _, test in ipairs(totals) do
        local list = ConfigReader.Field(test, "vars")
        local first
        for _, var in ipairs(type(list) == "table" and list or {}) do
            local name = varNameOf(var)
            first = first or name
            addVar(name)
        end
        local description = ConfigReader.Field(test, "description")
        local total = ConfigReader.Field(test, "totalValue")
        if first and type(description) == "string" and description ~= "" and type(total) == "number" then
            parts[#parts + 1] = { description, first, total }
        end
    end
    for _, test in ipairs(bits) do addVar(varNameOf(ConfigReader.Field(test, "var"))) end
    if #vars == 0 then return nil end
    local steps = ConfigReader.Field(achievement, "totalRequirementCount")
    if type(steps) ~= "number" or steps < 1 then steps = 1 end
    -- "Do it 5 times" is one requirement with a total of 5.
    if #totals == 1 and #bits == 0 then
        local total = ConfigReader.Field(totals[1], "totalValue")
        if type(total) == "number" and total > 1 then steps = total end
    end
    return vars, steps, (#totals > 1 and #parts == #totals) and parts or nil
end

local function requirementsOf(achievement)
    local prereqs = ConfigReader.Field(achievement, "prereqs")
    if type(prereqs) ~= "table" then return nil end
    local skills, quests = {}, {}
    for _, test in ipairs(type(prereqs.skills) == "table" and prereqs.skills or {}) do
        local types = ConfigReader.Field(test, "skillTypes")
        local level = ConfigReader.Field(test, "totalLevels")
        if type(types) == "table" and #types == 1 and type(level) == "number" then
            local name = QuestSource.skillName(types[1])
            if name then skills[#skills + 1] = { name, level } end
        end
    end
    for _, test in ipairs(type(prereqs.quests) == "table" and prereqs.quests or {}) do
        local questId = ConfigReader.Field(ConfigReader.Field(test, "quest"), "id")
        if type(questId) == "number" then quests[#quests + 1] = questId end
    end
    if #skills == 0 and #quests == 0 then return nil end
    return { skills = #skills > 0 and skills or nil, quests = #quests > 0 and quests or nil }
end

-- baked: the snapshot (TIERS, AREAS, TASKS) for area labels and ordering.
function TaskSource.Load(baked)
    if not ConfigReader.Available() then return nil end
    local candidates, categories = {}, {}
    for _, entry in ipairs(ConfigReader.AchievementList()) do
        local name = entry.name
        local area, tier
        -- The area is letters and digits (New Varrock is ATQ200).
        if type(name) == "string" then area, tier = name:match("^CHEEVO_AT([%u%d]+)_(%u+)_") end
        local tierName = tier and TIERS[tier]
        if area and not tierName then
            -- Some names put the tier elsewhere; the sub category ("ARDOUGNE_EASY") ends with it.
            local sub = categoryName(ConfigReader.Field(entry.achievement, "subCategory"))
            local suffix = sub and sub:match("_(%u+)$")
            tierName = suffix and TIERS[suffix]
        end
        if area and tierName then
            local category = ConfigReader.Field(entry.achievement, "category")
            candidates[#candidates + 1] = { entry = entry, area = area:lower(), tier = tierName, category = category }
            categories[category] = (categories[category] or 0) + 1
        end
    end
    -- The area tasks all share one category; anything else that looks similar is left out.
    local taskCategory, best
    for category, count in pairs(categories) do
        if not best or count > best then taskCategory, best = category, count end
    end

    local labels, order, known, anyCategory = {}, {}, {}, {}
    for _, area in ipairs(baked.AREAS) do
        labels[area[1]] = area[2]
        anyCategory[area[1]] = area[3] == true
        order[#order + 1] = area[1]
        known[area[1]] = true
    end
    local tasks, requirements, areaCount = {}, {}, {}
    local total = 0
    for _, item in ipairs(candidates) do
        if item.category == taskCategory or anyCategory[item.area] then
            local achievement = item.entry.achievement
            local vars, steps, parts = trackingOf(achievement)
            local name = ConfigReader.Field(achievement, "name")
            if vars and type(name) == "string" and name ~= "" then
                local sprite = ConfigReader.Field(achievement, "spriteID")
                local task = { vars, name, descriptionOf(achievement) or "", type(sprite) == "number" and sprite > 0 and sprite or nil,
                    item.tier, steps, parts }
                tasks[item.area] = tasks[item.area] or {}
                table.insert(tasks[item.area], task)
                local needs = requirementsOf(achievement)
                if needs then requirements[vars[1]] = needs end
                total = total + 1
                if not known[item.area] then
                    known[item.area] = true
                    order[#order + 1] = item.area
                    local sub = categoryName(ConfigReader.Field(achievement, "subCategory"))
                    labels[item.area] = sub and prettify((sub:gsub("_[A-Z]+$", ""))) or prettify(item.area)
                end
            end
        end
    end
    if total < MIN_TASKS then return nil end

    local tierRank = {}
    for index, tier in ipairs(baked.TIERS) do tierRank[tier] = index end
    for _, list in pairs(tasks) do
        table.sort(list, function(a, b)
            if a[5] ~= b[5] then return (tierRank[a[5]] or 99) < (tierRank[b[5]] or 99) end
            return a[2]:lower() < b[2]:lower()
        end)
    end
    local areas = {}
    for _, key in ipairs(order) do
        if tasks[key] then areas[#areas + 1] = { key, labels[key] or prettify(key) } end
    end
    return { TIERS = baked.TIERS, AREAS = areas, TASKS = tasks, REQUIREMENTS = requirements, total = total }
end

-- A quest an area task needs: { name, sprite, done } read live, or nil.
function TaskSource.QuestNeed(questId)
    local quest = ConfigReader.Quest(questId)
    if not quest then return nil end
    local name = ConfigReader.Field(quest, "name")
    if type(name) ~= "string" then return nil end
    local sprite = ConfigReader.Field(quest, "iconID")
    return { name = name, sprite = type(sprite) == "number" and sprite > 0 and sprite or nil,
        done = ConfigReader.Field(quest, "hasFinishedQuest") }
end

return TaskSource
