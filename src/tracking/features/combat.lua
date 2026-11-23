-- Combat achievements: names, difficulty tiers and descriptions.

local constants_m = require("src/tracking/constants")
local categoryIndex = constants_m.categoryIndex
local objects_m = require("src/tracking/core/objects")
local findObjectID = objects_m.findObjectID
local sprites_m = require("src/tracking/core/sprites")
local spriteByName = sprites_m.spriteByName
local vars_m = require("src/tracking/core/vars")
local resolveVar, trim = vars_m.resolveVar, vars_m.trim
local bosses_m = require("src/tracking/data/bosses")
local BOSSES = bosses_m.BOSSES
local combat_achievements_m = require("src/tracking/data/combat_achievements")
local COMBAT_ACHIEVEMENTS = combat_achievements_m.COMBAT_ACHIEVEMENTS

-- Combat: the game's own achievement name (config.Achievement).
local Combat = { cache = {}, type = categoryIndex("Combat"), bosses = {} }
function Combat.achievementName(configName)
    local cached = Combat.cache[configName]
    if cached then return cached end
    local ok, name = pcall(function() return config.Achievement[configName].name end)
    if not ok or type(name) ~= "string" or trim(name) == "" then
        local words = {}
        local rest = configName:gsub("^CHEEVO_", "")
        for word in rest:gmatch("[^_]+") do words[#words + 1] = word:sub(1, 1) .. word:sub(2):lower() end
        name = table.concat(words, " ")
    else
        name = trim(name)
    end
    Combat.cache[configName] = name
    return name
end

local petByBoss = {}
for _, boss in ipairs(BOSSES) do petByBoss[boss.name] = boss.pet end

local function buildBosses(groups)
    local list = {}
    for _, group in ipairs(groups) do
        list[#list + 1] = { name = group.boss, pet = petByBoss[group.boss], achievements = group, fromGame = group.isNew or nil }
    end
    table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
    return list
end
Combat.bosses = buildBosses(COMBAT_ACHIEVEMENTS)

local loaded, sourceName, report = false, "snapshot", nil

-- The boss list, extended with whatever the game lists that the snapshot doesn't. Read once, on first use.
function Combat.groups()
    if loaded then return Combat.bosses end
    loaded = true
    local ok, result = pcall(function()
        local tiers = {}
        for sprite in pairs(Combat.SPRITE_TIERS) do tiers[sprite] = true end
        return require("src/tracking/core/combat_source").Load(COMBAT_ACHIEVEMENTS, tiers)
    end)
    if ok and result then
        Combat.bosses = buildBosses(result.groups)
        sourceName, report = "game", result.report
    end
    return Combat.bosses
end

function Combat.source()
    Combat.groups()
    return sourceName, report
end

function Combat.loadedGroups()
    return loaded and Combat.bosses or nil
end

-- For the speedkiller challenges we don't need to display the Boss name so we can strip the label of said boss.
function Combat.stripBoss(label, bossName)
    local names = { bossName }
    local short = bossName:match("^([^,]+),")
    if short then names[#names + 1] = short end
    for _, name in ipairs(names) do
        if label:lower():sub(1, #name) == name:lower() then
            local rest = label:sub(#name + 1)
            rest = rest:gsub("^'s%f[%A]", "")
            if not rest:match("^%a") then
                rest = rest:gsub("^,%s*[Tt]he%s+%a+%s+", ""):gsub("^[%s:,%-]+", "")
                if rest ~= "" then return (rest:gsub("^%l", string.upper)) end
            end
        end
    end
    return label
end

--We have to identify the tier of the Combat Achievement then assign the right sprite.
Combat.TIERS = {
    { "GRANDMASTER", 6 }, { "MASTER", 5 }, { "ELITE", 4 }, { "HARD", 3 }, { "MEDIUM", 2 }, { "EASY", 1 },
}

Combat.TIER_SPRITES = {
    "ACHIEVEMENT_ICON_COMBAT_MASTERY_T1", "ACHIEVEMENT_ICON_COMBAT_MASTERY_T2",
    "ACHIEVEMENT_ICON_COMBAT_MASTERY_T3", "ACHIEVEMENT_ICON_COMBAT_MASTERY_T4",
    "ACHIEVEMENT_ICON_COMBAT_MASTERY_T5", "ACHIEVEMENT_ICON_COMBAT_MASTERY_T6",
}

Combat.SPRITE_TIERS = {}
for tier, name in ipairs(Combat.TIER_SPRITES) do
    local sprite = spriteByName(name)
    if sprite then Combat.SPRITE_TIERS[sprite] = tier end
end
function Combat.hasTierSprite(configName)
    local ok, spriteId = pcall(function() return config.Achievement[configName].spriteID end)
    if not ok or type(spriteId) ~= "number" then return true end
    return Combat.SPRITE_TIERS[spriteId] ~= nil
end

function Combat.tier(configName, displayName)
    local okSprite, spriteId = pcall(function() return config.Achievement[configName].spriteID end)
    if okSprite and Combat.SPRITE_TIERS[spriteId] then return Combat.SPRITE_TIERS[spriteId] end
    local upper = configName:upper():gsub("HARD_MODE", "HM")
    for _, pair in ipairs(Combat.TIERS) do
        if ("_" .. upper .. "_"):find("_" .. pair[1] .. "_", 1, true) then return pair[2] end
    end
    local shown = " " .. tostring(displayName):upper():gsub("[^%a]+", " ") .. " "
    for _, pair in ipairs(Combat.TIERS) do
        if shown:find(" " .. pair[1] .. " ", 1, true) then return pair[2] end
    end
    return nil
end

-- The achievement's description text (on mouseover).
function Combat.description(configName)
    local ok, text = pcall(function()
        local list = config.Achievement[configName].descriptions
        local first
        for _, entry in pairs(list) do
            local body = entry.text or entry[2]
            if type(body) == "string" and trim(body) ~= "" then
                first = first or body
                if tostring(entry.type or entry[1]):upper():find("DEFAULT", 1, true) then return body end
            end
        end
        return first
    end)
    if not ok or type(text) ~= "string" then return nil end
    text = text:gsub("<br>", " "):gsub("<[^>]*>", ""):gsub("%s+", " ")
    text = trim(text)
    return text ~= "" and text or nil
end

-- Splits text into lines of at most `width` characters (at most `maxLines`).
function Combat.wrap(text, width, maxLines)
    local lines, current = {}, ""
    for word in text:gmatch("%S+") do
        if current ~= "" and #current + 1 + #word > width then
            lines[#lines + 1] = current
            current = word
        else
            current = (current == "") and word or (current .. " " .. word)
        end
    end
    if current ~= "" then lines[#lines + 1] = current end
    if #lines > maxLines then
        lines[maxLines] = lines[maxLines]:sub(1, math.max(1, width - 3)):gsub("%s+$", "") .. "..."
        for i = #lines, maxLines + 1, -1 do lines[i] = nil end
    end
    return lines
end

local function achievementOption(boss, configName, petId)
    if not resolveVar(configName) or not Combat.hasTierSprite(configName) then return nil end
    local fullName = Combat.achievementName(configName)
    local option = {
        label = Combat.stripBoss(fullName, boss.name),
        kind = "item", varName = configName,
        objId = petId, target = 1,
    }
    local tier = Combat.tier(configName, fullName)
    if tier then
        local spriteId = spriteByName(Combat.TIER_SPRITES[tier])
        if spriteId then
            option.icon = { sprite = spriteId }
            option.spriteName = Combat.TIER_SPRITES[tier]
            option.objId = nil
        end
    end
    return option
end

function Combat.options(boss)
    local options = {}
    local petId = boss.pet and findObjectID(boss.pet) or nil
    for _, configName in ipairs(boss.achievements or {}) do
        local option = achievementOption(boss, configName, petId)
        if option then options[#options + 1] = option end
    end
    return options
end

function Combat.randomCandidate(boss, configName)
    if vars_m.readEntry(resolveVar(configName)) ~= 0 then return nil end
    local option = achievementOption(boss, configName, boss.pet and findObjectID(boss.pet) or nil)
    if option then option.key = configName end
    return option
end

return {
    Combat = Combat,
}
