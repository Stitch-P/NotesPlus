-- Slayer: the drops in each area's Slayer log, plus the area's "log complete" title.
local baked = require("src/tracking/data/slayer")
local SlayerSource = require("src/tracking/core/slayer_source")
local resolveVar = require("src/tracking/core/vars").resolveVar
local objects_m = require("src/tracking/core/objects")
local findObjectID, objectDisplayName = objects_m.findObjectID, objects_m.objectDisplayName
local OBJ_PAIR_OVERRIDES = require("src/tracking/data/bosses").OBJ_PAIR_OVERRIDES

local Slayer = {}

-- The logs come from the game's own data the first time they're needed; data/slayer.lua only keeps the
-- area names and title variables.
local AREAS, live
local function dataset()
    if AREAS then return end
    local ok, areas = pcall(SlayerSource.Load, baked.AREAS)
    if ok and areas then AREAS, live = areas, true else AREAS = baked.AREAS end
end

function Slayer.source() dataset(); return live and "game" or "snapshot" end

local function prettify(text)
    return (text:lower():gsub("_", " "):gsub("(%a)(%w*)", function(a, b) return a:upper() .. b end))
end

-- An item's collection log variable is ITEMLOG_ITEM_<Obj config name>. A few items are logged under a different name
-- (the same pairing the Bossing lists use), which the reverse of OBJ_PAIR_OVERRIDES covers. No variable = skipped.
local reverseOverrides
local function overrideSuffix(objName)
    if not reverseOverrides then
        reverseOverrides = {}
        for suffix, name in pairs(OBJ_PAIR_OVERRIDES) do reverseOverrides[name:upper()] = suffix end
    end
    return reverseOverrides[objName]
end

-- Log items the game has no ITEMLOG_ITEM_<name> counter for: their own unlock/ownership variable stands in (1 once you have it).
local VARIABLE_OVERRIDES = {
    ASC_KEYSTONE_1 = "ITEMLOG_ASCENSION_KEYS",
    OCT18_ADRENALINE_URN = "OCT18_ADRENALINE_URN_UNLOCKED",
    STALKER_SOULGAZER_PET_POH = "STALKER_SOULGAZER_PET_UNLOCKED",
    LORE_EDIMMU_PET_DROP = "ELFCITY_EDIMMU_PET_OWNED",
    NJDUNG_KALGERION_TITLE = "RAND_KALGERION_TITLES",
}

local function itemVariable(item)
    local object = item[3] or findObjectID(item[1])
    local varName = item[2]
    if not varName and object then
        local ok, name = pcall(function() return config.Obj.FromID(object).configName end)
        if ok and type(name) == "string" and name ~= "" then
            name = name:upper()
            local override = VARIABLE_OVERRIDES[name]
            if override and resolveVar(override) then return override, object end
            local candidates = { name, overrideSuffix(name) }
            for _, suffix in ipairs(candidates) do
                if resolveVar("ITEMLOG_ITEM_" .. suffix) then varName = "ITEMLOG_ITEM_" .. suffix; break end
            end
        end
    end
    return varName, object
end

function Slayer.groups()
    dataset()
    local list = {}
    for _, area in ipairs(AREAS) do list[#list + 1] = { name = area[1] } end
    return list
end

local function groupName(group)
    return type(group) == "table" and group.name or group
end

-- Does this group have drops to pick from (so it works as a collection)?
function Slayer.hasItems(group)
    dataset()
    local name = groupName(group)
    for _, area in ipairs(AREAS) do
        if area[1] == name then return #area[5] > 0 end
    end
    return false
end

local function findArea(group)
    dataset()
    for _, area in ipairs(AREAS) do
        if group and area[1] == group.name then return area end
    end
    return nil
end

function Slayer.options(group)
    local options = {}
    local area = findArea(group)
    if not area then return options end
    -- Areas with drops are tracked through the "Collection items" picker; the title is only offered where there are none.
    if area[2] and #area[5] == 0 then
        options[#options + 1] = {
            kind = "area", varName = area[2], key = area[2], label = "Log complete",
            spriteName = area[3] and ("#" .. area[3]) or nil, description = area[4], steps = 1, defaultTarget = 1,
        }
    end
    for _, item in ipairs(area[5]) do
        local varName, object = itemVariable(item)
        if varName then
            options[#options + 1] = {
                kind = "item", varName = varName, key = varName, objId = object, target = 1,
                label = objectDisplayName(object) or prettify(item[1] or varName:gsub("^ITEMLOG_ITEM_", "")),
            }
        end
    end
    return options
end

-- The area's achievement sprite (used as the icon on its collection notes).
function Slayer.areaSprite(name)
    dataset()
    for _, area in ipairs(AREAS) do
        if area[1] == name then return area[3] end
    end
    return nil
end

-- The drop option for a variable in an area (used to check saved collections), or nil.
function Slayer.itemOption(group, varName)
    for _, option in ipairs(Slayer.options({ name = groupName(group) })) do
        if option.varName == varName then return option end
    end
    return nil
end

-- For the tooltip on saved notes (only the "log complete" entries have one).
function Slayer.description(key)
    dataset()
    for _, area in ipairs(AREAS) do
        if area[2] == key then return area[4] end
    end
    return nil
end

return { Slayer = Slayer }