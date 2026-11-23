-- Production items read from the game's own skill guides (the skillguide_<skill> enums and the structs they point to).
-- Each guide entry carries the item it is about and the filter ("Ammo", "Potions"...) it is listed under, so the groups
-- below are just a choice of which skill and filters to turn into a picker group. The Production feature keeps its own
-- lists as the curated base and adds whatever shows up here that they don't have.

local ConfigReader = require("src/tracking/core/config_reader")

local SkillGuideSource = {}

-- group: name shown in the picker; skill: the guide's skill key; filters: guide filter names that belong to the group.
local SPECS = {
    -- Production: things you make (counted when new ones show up in your backpack).
    { group = "Fletching: Ammunition", skill = "FLETCHING", filters = { "Ammo", "Thrown" } },
    { group = "Fletching: Weapons", skill = "FLETCHING", filters = { "Weapons" } },
    { group = "Runecrafting: Runes", skill = "RUNECRAFT", filters = { "Runes" } },
    { group = "Crafting: Armour", skill = "CRAFTING", filters = { "Armour" } },
    { group = "Crafting: Jewellery", skill = "CRAFTING", filters = { "Jewellery" } },
    { group = "Crafting: Urns", skill = "CRAFTING", filters = { "Urns" } },
    { group = "Crafting: Objects", skill = "CRAFTING", filters = { "Objects" } },
    { group = "Cooking: Meats", skill = "COOKING", filters = { "Meats" } },
    { group = "Cooking: Drinks", skill = "COOKING", filters = { "Drinks" } },
    { group = "Herblore: Potions", skill = "HERBLORE", filters = { "Potions" } },
    { group = "Herblore: Combination potions", skill = "HERBLORE", filters = { "Combination" } },
    { group = "Herblore: Barbarian mixes", skill = "HERBLORE", filters = { "Barbarian" } },
    { group = "Herblore: Bombs", skill = "HERBLORE", filters = { "Bombs" } },
    { group = "Herblore: Powerbursts", skill = "HERBLORE", filters = { "Powerbursts" } },
    { group = "Herblore: Herbs", skill = "HERBLORE", filters = { "Herbs" } },
    { group = "Firemaking: Incense", skill = "FIREMAKING", filters = { "Incense" } },
    { group = "Smithing: Secondary equipment", skill = "SMITHING", filters = { "Secondary Equipment" } },
    { group = "Smithing: Crafting items", skill = "SMITHING", filters = { "Crafting" } },
    { group = "Farming: Allotments", skill = "FARMING", filters = { "Allotments" } },
    { group = "Farming: Bushes", skill = "FARMING", filters = { "Bushes" } },
    { group = "Farming: Flowers", skill = "FARMING", filters = { "Flowers" } },
    { group = "Farming: Fruit trees", skill = "FARMING", filters = { "Fruit Trees" } },
    { group = "Farming: Herbs", skill = "FARMING", filters = { "Herbs" } },
    { group = "Farming: Hops", skill = "FARMING", filters = { "Hops" } },
    { group = "Farming: Special", skill = "FARMING", filters = { "Special" } },
    -- Refined planks (Fort Forinthry) and the contract planks sit among a lot of other entries, so pick by item name.
    { group = "Construction: Planks", skill = "CONSTRUCTION", filters = { "Fort Forinthry", "Other" }, match = { "PLANK" } },
    -- Gathering: things you collect.
    { target = "gathering", group = "Mining: Gems & Ores", skill = "MINING", filters = { "Resources" } },
    { target = "gathering", group = "Woodcutting: Logs", skill = "WOODCUTTING", filters = { "Trees" }, match = { "LOG" }, exclude = { "DUMMY", "THATCHING", "CURSED" } },
    { target = "gathering", group = "Fishing: Catches", skill = "FISHING", filters = { "Catches" } },
    { target = "gathering", group = "Hunter: Implings & butterflies", skill = "HUNTER", filters = { "Butterflies, Moths, and Implings" },
        -- Lua patterns on the item's lower-case name, so nets, scrimshaws and guide placeholders stay out.
        -- (the jars may be named "... impling jar", so the word only has to appear somewhere).
        names = { "impling", "butterfly", "^charming moth" }, exclude = { "NET" } },
}

local function number(value)
    if type(value) == "number" then return value end
    local id = ConfigReader.Field(value, "id")
    if type(id) == "number" then return id end
end

local function struct(value)
    if type(value) == "number" then return value >= 0 and ConfigReader.Struct(value) or nil end
    if value == nil then return nil end
    if ConfigReader.Field(value, "configName") ~= nil then return value end
    local id = ConfigReader.Field(value, "id")
    return type(id) == "number" and ConfigReader.Struct(id) or nil
end

local function nameHits(object, patterns)
    for _, field in ipairs({ "configName", "name" }) do
        local okField, value = pcall(function() return object[field] end)
        if okField and type(value) == "string" then
            local upper = value:upper()
            for _, pattern in ipairs(patterns) do
                if upper:find(pattern, 1, true) then return true end
            end
        end
    end
    return false
end

local function usableItem(objId, spec)
    local okObj, object = pcall(function() return config.Obj.FromID(objId) end)
    if not okObj or not object then return false end
    -- Either the config name or the item's own name has to mention it (whichever the client exposes).
    if spec.match and not nameHits(object, spec.match) then return false end
    if spec.exclude and nameHits(object, spec.exclude) then return false end
    if spec.names then
        local okLabel, label = pcall(function() return object.name end)
        label = okLabel and type(label) == "string" and label:lower() or ""
        local hit = false
        for _, pattern in ipairs(spec.names) do
            if label:find(pattern) then hit = true break end
        end
        if not hit then return false end
    end
    local okName, name = pcall(function() return object.name end)
    if not okName or type(name) ~= "string" or name == "" or name == "null" then return false end
    local okConfig, configName = pcall(function() return object.configName end)
    if okConfig and type(configName) == "string" and configName:upper():match("^LEAGUE") then return false end
    return true
end

-- Filter number -> filter name for one skill.
local function filterNames(skill)
    local names = {}
    for _, pair in ipairs(ConfigReader.EnumPairs("SKILLGUIDE_" .. skill .. "_FILTERS")) do
        if type(pair[2]) == "string" then names[pair[1]] = pair[2]:lower() end
    end
    return names
end

-- { { name = <group>, objs = { <Obj id>, ... } }, ... }, or nil when the guides can't be read.
local cached, cachedAt

function SkillGuideSource.Groups()
    if cachedAt then return cached end
    cachedAt = true
    cached = SkillGuideSource.Read()
    return cached
end

function SkillGuideSource.Read()
    if not ConfigReader.Available() then return nil end
    local bySkill, groups, total = {}, {}, 0
    for _, spec in ipairs(SPECS) do
        local skill = bySkill[spec.skill]
        if skill == nil then
            skill = { filters = filterNames(spec.skill), entries = {} }
            for _, pair in ipairs(ConfigReader.EnumPairs("SKILLGUIDE_" .. spec.skill)) do
                local entry = struct(pair[2])
                if entry then
                    local filter = ConfigReader.StructParam(entry, "SKILLGUIDE_FILTER")
                    local obj = number(ConfigReader.StructParam(entry, "SKILLGUIDE_ITEM"))
                    if obj then skill.entries[#skill.entries + 1] = { filter = number(filter), obj = obj } end
                end
            end
            bySkill[spec.skill] = skill
        end
        local wanted = {}
        for _, name in ipairs(spec.filters) do wanted[name:lower()] = true end
        local group, seen = { name = spec.group, target = spec.target or "production", objs = {} }, {}
        for _, entry in ipairs(skill.entries) do
            local filterName = entry.filter and skill.filters[entry.filter]
            if filterName and wanted[filterName] and not seen[entry.obj] and usableItem(entry.obj, spec) then
                seen[entry.obj] = true
                group.objs[#group.objs + 1] = entry.obj
            end
        end
        if #group.objs > 0 then groups[#groups + 1] = group; total = total + #group.objs end
    end
    if total < 50 then return nil end
    return groups
end

return SkillGuideSource
