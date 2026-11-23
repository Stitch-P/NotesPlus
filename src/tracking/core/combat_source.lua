-- Combat achievements, read from the game's own achievements: the boss achievement categories, the ones carrying a
-- Combat Mastery tier icon and a mechanical, speed or fun challenge name, grouped by the boss (sub category) they
-- belong to. The baked list in data/combat_achievements.lua stays the base; challenges the game has added since turn up
-- as extra entries, and a boss the plugin doesn't know yet gets a group of its own.

local ConfigReader = require("src/tracking/core/config_reader")

local CombatSource = {}

local KINDS = { "_MECHANICAL_", "_SPEED_", "_FUN_" }
local MIN_PER_CATEGORY = 5

local function isChallenge(name)
    local padded = "_" .. name .. "_"
    for _, kind in ipairs(KINDS) do
        if padded:find(kind, 1, true) then return true end
    end
    return false
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

local function prettify(text)
    return (text:lower():gsub("_", " "):gsub("(%a)(%w*)", function(a, b) return a:upper() .. b end))
end

-- baked: COMBAT_ACHIEVEMENTS ({ boss =, "CHEEVO_..." ... }); tierSprites: set of the Combat Mastery tier sprite ids.
-- Returns { groups, newBosses, newAchievements } or nil.
function CombatSource.Load(baked, tierSprites)
    if not ConfigReader.Available() or next(tierSprites or {}) == nil then return nil end
    local list = ConfigReader.AchievementList()
    if #list < 500 then return nil end
    local byName = {}
    for _, entry in ipairs(list) do
        if type(entry.name) == "string" then byName[entry.name:upper()] = entry end
    end

    -- Which categories hold the combat achievements, and which boss each sub category is, from what we already list.
    local categoryCounts, bossOfName, subVotes = {}, {}, {}
    for _, group in ipairs(baked) do
        for _, configName in ipairs(group) do
            bossOfName[configName] = group.boss
            local entry = byName[configName]
            if entry then
                local category = ConfigReader.Field(entry.achievement, "category")
                categoryCounts[category] = (categoryCounts[category] or 0) + 1
                local sub = ConfigReader.Field(entry.achievement, "subCategory")
                subVotes[sub] = subVotes[sub] or {}
                subVotes[sub][group.boss] = (subVotes[sub][group.boss] or 0) + 1
            end
        end
    end
    local categories, found = {}, 0
    for category, count in pairs(categoryCounts) do
        if count >= MIN_PER_CATEGORY then categories[category] = true; found = found + 1 end
    end
    if found == 0 then return nil end
    local bossOfSub = {}
    for sub, votes in pairs(subVotes) do
        local best, bestCount
        for boss, count in pairs(votes) do
            if not bestCount or count > bestCount then best, bestCount = boss, count end
        end
        bossOfSub[sub] = best
    end

    local groups, byBoss = {}, {}
    for _, group in ipairs(baked) do
        local copy = { boss = group.boss }
        for index, configName in ipairs(group) do copy[index] = configName end
        groups[#groups + 1] = copy
        byBoss[group.boss] = copy
    end
    local have = {}
    for configName in pairs(bossOfName) do have[configName] = true end

    local report = { newBosses = {}, newAchievements = {} }
    for _, entry in ipairs(list) do
        local configName = type(entry.name) == "string" and entry.name:upper()
        if configName and not have[configName] and isChallenge(configName) then
            local achievement = entry.achievement
            local sprite = ConfigReader.Field(achievement, "spriteID")
            local category = ConfigReader.Field(achievement, "category")
            if tierSprites[sprite] and categories[category] then
                local sub = ConfigReader.Field(achievement, "subCategory")
                local boss = bossOfSub[sub]
                if not boss then
                    local label = categoryName(sub)
                    boss = label and prettify((label:gsub("^SUB_", ""))) or ("Boss " .. tostring(sub))
                    bossOfSub[sub] = boss
                end
                local group = byBoss[boss]
                if not group then
                    group = { boss = boss, isNew = true }
                    groups[#groups + 1] = group
                    byBoss[boss] = group
                    report.newBosses[#report.newBosses + 1] = boss
                end
                group[#group + 1] = configName
                have[configName] = true
                report.newAchievements[#report.newAchievements + 1] = configName
            end
        end
    end
    return { groups = groups, report = report }
end

return CombatSource
