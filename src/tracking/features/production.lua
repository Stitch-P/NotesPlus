-- Production: track how many of something you've made (arrows, bars, armour, runes...).
-- Counting watches your backpack for NEW items; your bank is only watched so that taking things out of it
-- (or putting them back) isn't mistaken for making them.

local data_m = require("src/tracking/data/production")
local GROUPS = data_m.GROUPS

local Mining = require("src/tracking/features/mining").Mining
local SkillGuideSource = require("src/tracking/core/skillguide_source")

local UrnSource = require("src/tracking/features/urn_source").UrnSource

local Production = {}

-- Urns: a group per tier ("Crafting: Exquisite urns" in Production = the empty ones, "Exquisite urns" in Training = the full ones), each
-- listing that tier's urn for every skill so you can pick the skill you want. Found by name by urn_source.lua.
local CRAFT_PREFIX, FULL_PREFIX = "Crafting: ", "Skilling: "
local GUIDE_URNS = "Crafting: Urns" -- the game's guide list (every skill at every tier), replaced by the tier groups
local urnItems = {}

local function urnItem(objId, group)
    local key = "production:urn-obj:" .. objId
    local item = urnItems[key]
    if not item then
        local ok, name = pcall(function() return config.Obj.FromID(objId).name end)
        name = ok and type(name) == "string" and name or ("Urn " .. objId)
        local gameName = name
        local entry = UrnSource.Entry(objId)
        -- The game marks the empty urn "(r)"; call it what it is.
        if entry and entry.stage == "empty" then name = name:gsub("%s*%b()%s*$", "") .. " (empty)" end
        item = { key = key, group = group, objId = objId, name = name, gameName = gameName }
        urnItems[key] = item
    end
    return item
end

-- "Crafting: Exquisite urns" -> "Exquisite", "empty"; "Skilling: Exquisite urns" -> "Exquisite", "full".
local function urnGroup(name)
    if type(name) ~= "string" then return nil end
    local stage, tier = "empty", name:sub(1, #CRAFT_PREFIX) == CRAFT_PREFIX and name:sub(#CRAFT_PREFIX + 1):match("^(%a+) urns$") or nil
    if not tier then stage, tier = "full", name:match("^(%a+) urns$") end
    if not tier then return nil end
    for _, known in ipairs(UrnSource.TIERS) do
        if known == tier then return tier, stage end
    end
end

local items, byKey, byGroup = {}, {}, {}
local groupNames = {}
local resolved = false
local resolveAll
local source = "snapshot"

local function prettify(configName)
    local words = {}
    for word in configName:lower():gmatch("[^_]+") do words[#words + 1] = word end
    local text = table.concat(words, " ")
    return (text:gsub("^%l", string.upper))
end

local function objectId(name)
    local ok, value = pcall(function() return id.Obj[name] end)
    return ok and type(value) == "number" and value >= 0 and value or nil
end

local function displayName(objId, configName)
    local ok, name = pcall(function() return config.Obj.FromID(objId).name end)
    if ok and type(name) == "string" and name ~= "" and name ~= "null" then return name end
    return prettify(configName)
end

-- Herb potions come in a version for every extra ("Vulnerability bomb (+2)"): only the plain one is offered. The others
-- stay known, so notes that already track one keep working.
local function isExtraVersion(groupName, name)
    return type(groupName) == "string" and groupName:sub(1, 9) == "Herblore:" and type(name) == "string"
        and name:find("%+%d") ~= nil
end

local function addItem(objId, configName, groupName, list, inGroup)
    if inGroup[objId] then return end
    local item = byKey["production:" .. objId]
    if not item then
        item = { objId = objId, key = "production:" .. objId, configName = configName, group = groupName }
        item.name = displayName(objId, configName or ("Item " .. objId))
        items[#items + 1], byKey[item.key] = item, item
    end
    inGroup[objId] = true
    if not isExtraVersion(groupName, item.name) then list[#list + 1] = item end
end

-- Item ids come from the game's own table the first time they're needed. The lists in data/production.lua are the
-- curated base; the game's skill guides add the groups and items they don't have.
function resolveAll()
    if resolved then return end
    resolved = true
    for _, group in ipairs(GROUPS) do
        local list = {}
        for _, configName in ipairs(group[2]) do
            local objId = objectId(configName)
            if objId and not byKey["production:" .. objId] then
                local item = { objId = objId, key = "production:" .. objId, configName = configName, group = group[1] }
                item.name = displayName(objId, configName)
                items[#items + 1], byKey[item.key], list[#list + 1] = item, item, item
            end
        end
        byGroup[group[1]] = list
        groupNames[#groupNames + 1] = group[1]
    end
    -- Bars (they used to be in Gathering): counted in the backpack and the metal bank.
    do
        local list, inGroup = {}, {}
        for _, row in ipairs(require("src/tracking/data/mining").BARS) do addItem(row[1], nil, "Smithing: Bars", list, inGroup) end
        byGroup["Smithing: Bars"] = list
        groupNames[#groupNames + 1] = "Smithing: Bars"
    end
    local ok, guide = pcall(SkillGuideSource.Groups)
    if ok and guide then
        source = "game"
        for _, entry in ipairs(guide) do
          if entry.target == "production" then
            local list = byGroup[entry.name]
            if not list then
                list = {}
                byGroup[entry.name] = list
                groupNames[#groupNames + 1] = entry.name
            end
            local inGroup = {}
            for _, item in ipairs(list) do inGroup[item.objId] = true end
            for _, objId in ipairs(entry.objs) do addItem(objId, nil, entry.name, list, inGroup) end
          end
        end
    end
end

function Production.source()
    resolveAll()
    return source
end

function Production.groups()
    resolveAll()
    local list = {}
    for _, name in ipairs(groupNames) do
        if #(byGroup[name] or {}) > 0 and name ~= GUIDE_URNS then list[#list + 1] = { name = name } end
    end
    for _, tier in ipairs(UrnSource.TIERS) do list[#list + 1] = { name = CRAFT_PREFIX .. tier .. " urns" } end
    return list
end

-- The finished-urn groups of the Training type: "Cracked urns" ... "Exquisite urns".
function Production.urnGroups()
    local list = {}
    for _, tier in ipairs(UrnSource.TIERS) do list[#list + 1] = { name = tier .. " urns" } end
    return list
end

function Production.info(key)
    resolveAll()
    if type(key) == "string" then
        local objId = key:match("^production:urn%-obj:(%d+)$") or key:match("^production:urn%-full:(%d+)$")
        if objId then return urnItem(tonumber(objId)) end
        -- Notes made with an earlier version's tier entries still load (they just don't count anything now).
        if key:match("^production:urn%-tier:") then
            local old = urnItems[key]
            if not old then
                old = { key = key, group = "Urns", name = "Urns" }
                urnItems[key] = old
            end
            return old
        end
    end
    return byKey[key]
end

function Production.options(group)
    resolveAll()
    local name = type(group) == "table" and group.name or group
    local options = {}
    local tier, stage = urnGroup(name)
    if tier then
        for _, entry in ipairs(UrnSource.Urns(tier, stage)) do
            local item = urnItem(entry.id, name)
            options[#options + 1] = {
                kind = "production", key = item.key, label = item.name, objId = item.objId, item = item,
                description = stage == "full" and "Counts finished (full) urns that show up in your backpack from when you set this note."
                    or "Counts empty urns (ready to start gathering) that show up in your backpack from when you set this note.",
            }
        end
        return options
    end
    for _, item in ipairs(byGroup[name] or {}) do
        options[#options + 1] = {
            kind = "production", key = item.key, label = item.name, objId = item.objId, item = item,
            description = Production.description(item.key),
        }
    end
    return options
end

function Production.description()
    return "Counts new ones that show up in your backpack from when you set this note. "
        .. "Banking them or taking them back out doesn't count."
end

-- Backpack (counts) and bank (only offsets moves).
function Production.places(item)
    return Mining.inventoryCount("INV", item.objId), Mining.inventoryCount("BANK", item.objId),
        Mining.inventoryCount("METAL_BANK", item.objId)
end

return { Production = Production }