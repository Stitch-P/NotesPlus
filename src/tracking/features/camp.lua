-- Anachronia Base Camp: the six resources stored at the camp (DINO_BASE_CAMP_RESOURCE_<NAME>, a plain count) and the
-- buildings (DINO_BASE_CAMP_BUILDING_TIER_<NAME>, the tier built). Each building has a database row
-- (dino_base_camp_building_<name>) with its name, its tiers and what each costs, and a "prereq" row (named in its last
-- column) with what each tier needs first: other buildings at a tier, skill levels, an item.

local ConfigReader = require("src/tracking/core/config_reader")
local Sprites = require("src/tracking/core/sprites")
local Vars = require("src/tracking/core/vars")
local Objects = require("src/tracking/core/objects")
local Skills = require("src/tracking/features/skills")
local Mining = require("src/tracking/features/mining").Mining

local Camp = {}

Camp.GROUP = "Anachronia"
Camp.RESOURCES = "Base Camp (Resources)"
Camp.BUILDINGS = "Base Camp (Buildings)"
Camp.WORKERS = "Base Camp (Workers)"
Camp.IAIA = "Dream of Iaia"
-- The Anachronia Dinosaur Farm's upgrades (a reward shop, see data/reward_shops.lua) as a section of Anachronia.
Camp.FARM_SHOP = "Dinosaur Farm"
-- A single note (no list to pick from): the skillcape on the base camp's Skillcape Rack.
Camp.CAPE_RACK = "Skillcape Rack"
local CAPE_RACK_VAR = "DINO_BASE_CAMP_SKILLCAPE_STAND_STATE"
local CAPE_RACK_LODGE_TIER = 3 -- the rack can only be used with the Player Lodge at tier 3
local RackData = require("src/tracking/data/skillcape_rack")
local DEFAULT_CAPE = 9777 -- the Thieving cape, for the picker's picture while the rack is empty
-- A single note: whether a helmet is stored on the base camp's Slayer Helmet Stand (which helmet can't be read yet).
Camp.HELM_STAND = "Slayer Helmet Stand"
local HELM_STAND_VAR = "DINO_BASE_CAMP_SLAYER_STAND_STATE" -- 0 not built, 1 ready, 2 helmet on the stand
local HELM_STAND_OBJ = 40377 -- a slayer helmet, for the note's picture
-- Dream of Iaia: the same six resources, kept in quest variables (the quest's permanent store) instead of at the camp.
-- Stone starts at the lowest whole number a variable can hold (-2147483648), so its amount is how far above that it is.
local IAIA_VARS = { WOOD = "QUEST_EGW_FINALE_PERM_8", VINES = "QUEST_EGW_FINALE_PERM_9", LEAVES = "QUEST_EGW_FINALE_PERM_4",
    PELTS = "QUEST_EGW_FINALE_PERM_7", STONE = "QUEST_EGW_FINALE_PERM_2", CLAY = "QUEST_EGW_FINALE_PERM_3" }
local IAIA_OFFSET = { STONE = 2147483648 }
-- Every assigned worker gathers this many of the resource an hour.
local PER_WORKER = 60

local RESOURCES = { "WOOD", "VINES", "LEAVES", "PELTS", "STONE", "CLAY" }
local BUILDINGS = { "TOWNHALL", "STOREHOUSE", "SLEEPING_QUARTERS", "SPA", "HUNTER_LODGE", "SLAYER_LODGE", "PLAYER_LODGE",
    "BANK_CHEST", "LODESTONE" }
-- The most tiers a building could have, when its row can't say.
local FALLBACK_TIERS = { TOWNHALL = 3, STOREHOUSE = 3, SLEEPING_QUARTERS = 3, SPA = 3, HUNTER_LODGE = 3, SLAYER_LODGE = 3,
    PLAYER_LODGE = 3, BANK_CHEST = 1, LODESTONE = 1 }
-- SkillType order used by the game's requirements.
local SKILL_TYPES = { "ATTACK", "DEFENCE", "STRENGTH", "HITPOINTS", "RANGED", "PRAYER", "MAGIC", "COOKING", "WOODCUTTING",
    "FLETCHING", "FISHING", "FIREMAKING", "CRAFTING", "SMITHING", "MINING", "HERBLORE", "AGILITY", "THIEVING", "SLAYER",
    "FARMING", "RUNECRAFTING", "HUNTER", "CONSTRUCTION", "SUMMONING", "DUNGEONEERING", "DIVINATION", "INVENTION",
    "ARCHAEOLOGY", "NECROMANCY" }
local MAX_RESOURCE = 1000000000

local function prettify(name)
    return (name:lower():gsub("_", " "):gsub("(%a)(%w*)", function(a, b) return a:upper() .. b end))
end

local function text(value)
    if type(value) == "string" and value ~= "" and value ~= "null" then return value end
end

-- The first sprite the game knows among these names (as written, upper and lower case, with and without the "_0" frame).
local function findSprite(names)
    for _, name in ipairs(names) do
        for _, variant in ipairs({ name, name .. "_0", name:upper(), name:upper() .. "_0", name:lower(), name:lower() .. "_0" }) do
            local ok, sprite = pcall(Sprites.spriteByName, variant)
            if ok and type(sprite) == "number" and sprite > 0 then return sprite end
        end
    end
end

-- Or, failing that, the shortest sprite name that has all these words (the client lists its sprite names a little at a time,
-- so this can come up empty at first and works on a later look).
local function searchSprite(queries)
    for _, query in ipairs(queries) do
        local ok, sprite = pcall(Sprites.findSprite, query)
        if ok and type(sprite) == "number" and sprite > 0 then return sprite end
    end
end

local function words(suffix)
    local list = {}
    for word in suffix:lower():gmatch("[^_]+") do list[#list + 1] = word:sub(1, 1):upper() .. word:sub(2) end
    return list
end

-- The Player Lodge has no picture of its own: it wears the Slayer Lodge's.
local SPRITE_ALIAS = { PLAYER_LODGE = "SLAYER_LODGE" }

local function spriteNames(suffix, tier)
    suffix = SPRITE_ALIAS[suffix] or suffix
    local list = words(suffix)
    local forms = { table.concat(list), table.concat(list, "_"), (table.concat(list):gsub("^(%u)(.*)$", function(a, b) return a .. b:lower() end)) }
    local names = {}
    for _, form in ipairs(forms) do
        names[#names + 1] = "art_building_" .. form .. "_tier" .. tier
        names[#names + 1] = "art_building_" .. form .. tier
    end
    if tier == 1 then
        for _, form in ipairs(forms) do names[#names + 1] = "art_building_" .. form end
    end
    return names
end

local resources, buildings, byKey, bySuffix

-- A building's picture, looked up on every ask until it is found.
local function spriteOf(entry)
    if entry.sprite then return entry.sprite end
    local suffix = (SPRITE_ALIAS[entry.suffix] or entry.suffix):lower():gsub("_", " ")
    entry.sprite = findSprite(spriteNames(entry.suffix, 1)) or searchSprite({ "art building " .. suffix .. " tier1",
        "art building " .. suffix })
    return entry.sprite
end

-- A resource's picture is its compacted item ("Compacted wood"); its own row names it.
local function objectOf(entry)
    if entry.obj == nil then
        local row = ConfigReader.Available() and ConfigReader.Row("DINO_BASE_CAMP_RESOURCE_" .. entry.suffix) or nil
        local fromRow = row and ConfigReader.Value(row, 4)
        entry.obj = type(fromRow) == "number" and fromRow > 0 and fromRow
            or Objects.findObjectID("DINO_BASE_CAMP_RARE_RESOURCE_" .. entry.suffix) or false
    end
    return entry.obj or nil
end

local function nameOfConfig(kind, id)
    local object = id and ConfigReader.Config(kind, id)
    local name = object and ConfigReader.Field(object, "name")
    return text(name)
end

-- A reference to another row comes back as the row itself or as its id; either way, the row (or nil).
local function rowOf(value)
    if type(value) == "number" then return ConfigReader.Row(value) end
    if type(value) == "table" or type(value) == "userdata" then return value end
end

-- A number, or the id of a config object.
local function idOf(value)
    if type(value) == "number" then return value end
    local id = (type(value) == "table" or type(value) == "userdata") and ConfigReader.Field(value, "id")
    return type(id) == "number" and id or nil
end

-- Which of the six resources a cost refers to (the row in the building's cost columns), by its row's name.
local function resourceOf(value)
    local row = rowOf(value)
    -- The six resource rows are ids 1726 to 1731, in this order; used when the row itself can't be read.
    if not row then return type(value) == "number" and RESOURCES[value - 1725] or nil end
    local found = (tostring(ConfigReader.Field(row, "configName") or "") .. " " .. tostring(ConfigReader.Value(row, 2) or "")):upper()
    for _, suffix in ipairs(RESOURCES) do
        if found:find(suffix, 1, true) then return suffix end
    end
    if found:find("HIDES", 1, true) then return "PELTS" end
end

-- Which building a row is ("dino_base_camp_building_storehouse" -> STOREHOUSE), or nil.
local function buildingOf(value)
    local row = rowOf(value)
    local name = row and ConfigReader.Field(row, "configName")
    -- The building rows are ids 1732 to 1740, in this order.
    if type(name) ~= "string" then return type(value) == "number" and BUILDINGS[value - 1731] or nil end
    name = name:upper():gsub("^DINO_BASE_CAMP_BUILDING_", ""):gsub("^DINO_BASE_CAMP_", "")
    for _, suffix in ipairs(BUILDINGS) do
        if name == suffix then return suffix end
    end
end

-- How many columns to look through (the row may not say; then up to 20, empty ones are skipped).
local function columns(row)
    local count = ConfigReader.ColumnCount(row)
    if type(count) ~= "number" or count <= 0 then count = 20 end
    return math.min(count, 40)
end

-- How many values a column holds (the count it reports can be the number of lists, not of values).
local function size(column)
    if not column then return 0 end
    local values = type(column.values) == "table" and #column.values or 0
    return values > 0 and values or column.count or 0
end

-- Every column that holds one resource row id is followed by that resource's amount at each tier.
local function readCosts(row)
    local costs, tiers = {}, 0
    local count = columns(row)
    for column = 1, count - 1 do
        local id = ConfigReader.Column(row, column)
        local resource = id and size(id) == 1 and resourceOf(id.values[1])
        if resource then
            local amounts = ConfigReader.Column(row, column + 1)
            if amounts and size(amounts) > 0 then
                tiers = math.max(tiers, size(amounts))
                for tier = 1, size(amounts) do
                    local value = amounts.values[tier]
                    if type(value) == "number" and value > 0 then
                        costs[tier] = costs[tier] or {}
                        costs[tier][#costs[tier] + 1] = { resource = resource, amount = value }
                    end
                end
            end
        end
    end
    return costs, tiers
end

-- What each tier needs first, from the building's prereq row:
-- { [tier] = { buildings = {{ suffix, tier }}, skills = {{ skill, level }}, items = { id } } }.
local function readNeeds(row, tiers, suffix)
    local needs = {}
    for tier = 1, tiers do needs[tier] = { buildings = {}, skills = {}, items = {} } end
    local prereq = row and rowOf(ConfigReader.Value(row, 12)) or nil
    if not prereq and suffix then prereq = ConfigReader.Row("DINO_BASE_CAMP_BUILDING_PREREQ_" .. suffix) end
    if not prereq then return needs end
    for column = 2, columns(prereq) do
        local data = ConfigReader.Column(prereq, column)
        if data and size(data) > 0 then
            local first = data.values[1]
            if size(data) == 1 then
                -- One item, needed for the last tier.
                local item = not buildingOf(first) and idOf(first)
                local last = needs[tiers]
                if item and item >= 10000 and last then last.items[#last.items + 1] = item end
            elseif size(data) % 2 == 0 then
                for tier = 1, math.min(tiers, size(data) / 2) do
                    local a, b = data.values[tier * 2 - 1], data.values[tier * 2]
                    local other = buildingOf(a)
                    if other then
                        if type(b) == "number" and b > 0 then
                            local list = needs[tier].buildings
                            list[#list + 1] = { suffix = other, tier = b }
                        end
                    elseif type(a) == "number" and SKILL_TYPES[a + 1] and type(b) == "number" and b > 0 then
                        local list = needs[tier].skills
                        list[#list + 1] = { skill = SKILL_TYPES[a + 1], level = b }
                    end
                end
            end
        end
    end
    return needs
end

local function build()
    if resources then return end
    resources, buildings, byKey, bySuffix = {}, {}, {}, {}
    for _, suffix in ipairs(RESOURCES) do
        local resourceRow = ConfigReader.Available() and ConfigReader.Row("DINO_BASE_CAMP_RESOURCE_" .. suffix) or nil
        local worker = { key = "camp-wrk:" .. suffix:lower(), suffix = suffix, var = "DINO_BASE_CAMP_WORKER_ASSIGNED_" .. suffix,
            kind = "worker" }
        local entry = { key = "camp-res:" .. suffix:lower(), name = resourceRow and text(ConfigReader.Value(resourceRow, 2)) or prettify(suffix), suffix = suffix,
            var = "DINO_BASE_CAMP_RESOURCE_" .. suffix, kind = "resource" }
        resources[#resources + 1], byKey[entry.key] = entry, entry
        worker.name, worker.resource = entry.name .. " workers", entry
        byKey[worker.key] = worker
        local dream = { key = "camp-iai:" .. suffix:lower(), suffix = suffix, name = entry.name, var = IAIA_VARS[suffix],
            kind = "iaia", resource = entry }
        byKey[dream.key] = dream
    end
    for _, suffix in ipairs(BUILDINGS) do
        local row
        if ConfigReader.Available() then
            row = ConfigReader.Row("DINO_BASE_CAMP_BUILDING_" .. suffix) or ConfigReader.Row("DINO_BASE_CAMP_" .. suffix)
        end
        local costs, tiers = {}, 0
        if row then costs, tiers = readCosts(row) end
        local descriptions = {}
        local column = row and ConfigReader.Column(row, 11)
        for tier = 1, size(column) do descriptions[tier] = text(column.values[tier]) end
        -- Every building goes to tier 3 in its variable, except the Bank Chest and the Lodestone.
        tiers = FALLBACK_TIERS[suffix] or math.max(1, tiers)
        local entry = {
            key = "camp-bld:" .. suffix:lower(), name = row and text(ConfigReader.Value(row, 2)) or prettify(suffix), suffix = suffix,
            var = "DINO_BASE_CAMP_BUILDING_TIER_" .. suffix, tiers = tiers, costs = costs, descriptions = descriptions,
            needs = readNeeds(row, tiers, suffix), kind = "building",
        }
        buildings[#buildings + 1], byKey[entry.key], bySuffix[suffix] = entry, entry, entry
    end
end

-- The choices under "Anachronia"; the first is whatever the group already offered (its unlocks), when it has any.
function Camp.sections(withUnlocks)
    local list = {}
    if withUnlocks then list[#list + 1] = { name = "Unlocks" } end
    list[#list + 1] = { name = Camp.RESOURCES }
    list[#list + 1] = { name = Camp.BUILDINGS }
    list[#list + 1] = { name = Camp.WORKERS }
    list[#list + 1] = { name = Camp.IAIA }
    list[#list + 1] = { name = Camp.CAPE_RACK }
    list[#list + 1] = { name = Camp.HELM_STAND }
    return list
end

function Camp.isStandSection(name) return name == Camp.CAPE_RACK or name == Camp.HELM_STAND end
function Camp.isStandKey(key) return key == "camp-std:cape" or key == "camp-std:helm" end

function Camp.isSection(name) return name == Camp.RESOURCES or name == Camp.BUILDINGS or name == Camp.WORKERS or name == Camp.IAIA end

-- Which section a saved key belongs to.
function Camp.sectionOf(key)
    if type(key) ~= "string" then return nil end
    if key:match("^camp%-res:") then return Camp.RESOURCES end
    if key:match("^camp%-bld:") then return Camp.BUILDINGS end
    if key:match("^camp%-wrk:") then return Camp.WORKERS end
    if key:match("^camp%-iai:") then return Camp.IAIA end
    if key == "camp-std:cape" then return Camp.CAPE_RACK end
    if key == "camp-std:helm" then return Camp.HELM_STAND end
end

-- A saved key looks right whether or not the game data is ready (notes load before it).
function Camp.isKey(key) return type(key) == "string" and key:match("^camp%-%a%a%a:[%w_]+$") ~= nil end
function Camp.isBuildingKey(key) return type(key) == "string" and key:match("^camp%-bld:[%w_]+$") ~= nil end

-- The highest target a key accepts: a resource count, or a building's tiers.
function Camp.maxTarget(key)
    if type(key) ~= "string" then return nil end
    if key:match("^camp%-res:") or key:match("^camp%-iai:") then return MAX_RESOURCE end
    if key:match("^camp%-bld:") then return 7 end
    if key:match("^camp%-wrk:") then return 1000 end
end

function Camp.info(key) build() return byKey[key] end

function Camp.isIaiaKey(key) return type(key) == "string" and key:match("^camp%-iai:[%w_]+$") ~= nil end

-- A Dream of Iaia reading as an amount: Stone's variable counts up from -2147483648 (and may be handed over unsigned).
function Camp.iaiaAmount(key, value)
    if type(value) ~= "number" or type(key) ~= "string" then return value end
    local offset = IAIA_OFFSET[(key:match("^camp%-iai:(.+)$") or ""):upper()]
    if not offset then return value end
    return (value + offset) % (offset * 2)
end

local function number(value) return Vars.withCommas and Vars.withCommas(value) or tostring(value) end

local function readVar(name)
    local entry = Vars.resolveVar(name)
    local value = entry and Vars.readEntry(entry)
    return type(value) == "number" and value or nil
end

-- How far a building is built (0 = not at all), or nil when the game can't say.
local function builtTier(building) return readVar(building.var) end

-- The tier a new note aims for: the next one to build (the last, once everything is built).
function Camp.nextTier(key)
    local building = Camp.info(key)
    if not building then return 1 end
    local built = builtTier(building) or 0
    return math.max(1, math.min(building.tiers, built + 1))
end

-- 7500 -> "7.5k", 120000 -> "120k", 1500000 -> "1.5m": the short form shown beside a resource's icon.
local function compact(value)
    local function trim(number) return (string.format("%.1f", number):gsub("%.0$", "")) end
    if value >= 1000000 then return trim(value / 1000000) .. "m" end
    if value >= 1000 then return trim(value / 1000) .. "k" end
    return tostring(value)
end

-- How many of an item are in the backpack (read at most every couple of seconds).
local carried = {}
local function inBackpack(item)
    local now = type(os) == "table" and os.clock and os.clock() or 0
    local kept = carried[item]
    if kept and now > 0 and now - kept.at < 2 then return kept.count end
    local ok, count = pcall(Mining.inventoryCount, "INV", item)
    if not ok then count = nil end
    carried[item] = { at = now, count = count }
    return count
end

-- The needs of one tier, ready to show: resources, buildings, skills and items, each marked met or not.
local function needsOf(building, tier)
    local list = {}
    for _, cost in ipairs(building.costs[tier] or {}) do
        local resource = byKey["camp-res:" .. cost.resource:lower()]
        if resource then
            local have = readVar(resource.var)
            list[#list + 1] = { kind = "item", name = resource.name, level = cost.amount, have = have, text = compact(cost.amount),
                met = have ~= nil and have >= cost.amount, icon = objectOf(resource) }
        end
    end
    local needs = building.needs[tier]
    if needs then
        for _, need in ipairs(needs.buildings) do
            local other = bySuffix[need.suffix]
            if other then
                local have = builtTier(other)
                list[#list + 1] = { kind = "quest", name = other.name .. " (tier " .. need.tier .. ")", sprite = spriteOf(other),
                    met = have ~= nil and have >= need.tier, metText = " (built)", unmetText = " (not built yet)" }
            end
        end
        for _, need in ipairs(needs.skills) do
            local entry = Skills.SKILL_BY_TYPE[need.skill]
            if entry then
                local have = Skills.readSkillLevel(entry)
                list[#list + 1] = { kind = "skill", skill = entry, name = entry.name, level = need.level, have = have,
                    met = have ~= nil and have >= need.level, icon = Skills.skillIconRef(entry) }
            end
        end
        for _, item in ipairs(needs.items) do
            local have = inBackpack(item)
            list[#list + 1] = { kind = "item", name = nameOfConfig("Obj", item) or "Required item", level = 1, have = have,
                met = have ~= nil and have >= 1, icon = item }
        end
    end
    return list
end

local function lineOf(need)
    if need.kind == "skill" then return need.level .. " " .. need.name end
    if need.kind == "item" then return (need.level > 1 and (number(need.level) .. " ") or "") .. need.name end
    return need.name
end

-- What the next tier of a building needs, as one line; "Fully built" when there is no next tier.
local function nextLine(building)
    local built = builtTier(building)
    if built and built >= building.tiers then return "Fully built (tier " .. building.tiers .. ")." end
    local tier = (built or 0) + 1
    local parts = {}
    for _, need in ipairs(needsOf(building, tier)) do parts[#parts + 1] = lineOf(need) end
    local line = "Next: tier " .. tier .. "."
    if #parts > 0 then line = line .. " Needs " .. table.concat(parts, ", ") .. "." end
    if building.descriptions[tier] then line = line .. " " .. building.descriptions[tier] end
    return line
end

function Camp.options(section)
    build()
    local options = {}
    if section == Camp.BUILDINGS then
        for _, building in ipairs(buildings) do
            -- Ones built to the top need nothing more, so they are left out.
            local built = builtTier(building)
            if not (built and built >= building.tiers) then
            options[#options + 1] = {
                kind = "camp", key = building.key, label = building.name, varName = building.var,
                defaultTarget = Camp.nextTier(building.key),
                spriteName = spriteOf(building) and ("#" .. building.sprite) or nil,
                description = nextLine(building) .. " Tracking it aims for the next tier.", maxTarget = building.tiers,
            }
            end
        end
    elseif section == Camp.IAIA then
        for _, resource in ipairs(resources) do
            local dream = byKey["camp-iai:" .. resource.suffix:lower()]
            options[#options + 1] = {
                kind = "camp", key = dream.key, label = dream.name, varName = dream.var, defaultTarget = 1,
                objId = objectOf(resource),
                description = "The " .. resource.name:lower() .. " you have given to the Dream of Iaia. Set how many to reach.",
            }
        end
    elseif section == Camp.WORKERS then
        for _, resource in ipairs(resources) do
            local worker = byKey["camp-wrk:" .. resource.suffix:lower()]
            options[#options + 1] = {
                kind = "camp", key = worker.key, label = worker.name, varName = worker.var, defaultTarget = 1,
                objId = objectOf(resource),
                description = "Workers assigned to gathering " .. resource.name:lower() .. ", " .. PER_WORKER
                    .. " an hour each. Set how many to reach.",
            }
        end
    else
        for _, resource in ipairs(resources) do
            options[#options + 1] = {
                kind = "camp", key = resource.key, label = resource.name, varName = resource.var, defaultTarget = 1,
                objId = objectOf(resource),
                description = "The " .. resource.name:lower() .. " stored at your Anachronia base camp. Set how many to reach.",
            }
        end
    end
    return options
end

-- The rack's single goal: the note is simply added, there is nothing to pick.
function Camp.standOption(section)
    if section == Camp.HELM_STAND then
        return { kind = "stand", key = "camp-std:helm", label = Camp.HELM_STAND, varName = HELM_STAND_VAR, defaultTarget = 1,
            objId = HELM_STAND_OBJ, description = "Shows whether a Slayer helmet is stored on the base camp's helmet stand." }
    end
    if section ~= Camp.CAPE_RACK then return nil end
    return { kind = "stand", key = "camp-std:cape", label = Camp.CAPE_RACK, varName = CAPE_RACK_VAR, defaultTarget = 1,
        objId = Camp.standObject("camp-std:cape") or DEFAULT_CAPE,
        description = "Shows the skillcape stored on the base camp's rack, and the perk it gives you while it's there." }
end

-- { skill name, cape item, perk } stored on the rack, or nil when it is empty / unreadable.
local function storedCape()
    local value = readVar(CAPE_RACK_VAR)
    return value and value > 0 and RackData.CAPES[value] or nil, value
end

function Camp.standProgress(key)
    if key == "camp-std:helm" then
        local state = readVar(HELM_STAND_VAR)
        if state == nil then return { current = nil, target = 1, fraction = 0, complete = false, text = "Waiting for your Slayer Helmet Stand" } end
        if state >= 2 then return { current = 1, target = 1, fraction = 1, complete = true, text = "Slayer helmet stored" } end
        if state == 1 then return { current = 0, target = 1, fraction = 0, complete = false, text = "Ready for a Slayer helmet" } end
        return { current = 0, target = 1, fraction = 0, complete = false, text = "Stand not built yet" }
    end
    local cape, value = storedCape()
    if value == nil then return { current = nil, target = 1, fraction = 0, complete = false, text = "Waiting for your Skillcape Rack" } end
    if not cape then return { current = 0, target = 1, fraction = 0, complete = false, text = "No skillcape stored" } end
    return { current = 1, target = 1, fraction = 1, complete = true, text = cape[1] .. " cape stored" }
end

-- The stored cape's item, for the note's picture (nil when the rack is empty).
function Camp.standObject(key)
    if key == "camp-std:helm" then return HELM_STAND_OBJ end
    local cape = key == "camp-std:cape" and storedCape()
    return cape and cape[2] or nil
end

-- The rack needs the Player Lodge at tier 3: shown as a requirement only while it isn't.
function Camp.standRequirements(key)
    if key ~= "camp-std:cape" then return {} end
    build()
    local lodge = bySuffix["PLAYER_LODGE"]
    local have = lodge and builtTier(lodge)
    if have ~= nil and have >= CAPE_RACK_LODGE_TIER then return {} end
    return { { kind = "quest", name = "Player Lodge (tier " .. CAPE_RACK_LODGE_TIER .. ")", sprite = lodge and spriteOf(lodge) or nil,
        met = false, metText = " (built)", unmetText = " (not built yet)" } }
end

function Camp.standCard(key)
    local function safe_(value) return (tostring(value):gsub("<br>", "\n"):gsub("<", "["):gsub(">", "]"):gsub("\n", "<br>")) end
    if key == "camp-std:helm" then
        return { key = key, body = Camp.HELM_STAND .. "<br>" .. safe_(Camp.standProgress(key).text) }
    end
    local lines = { Camp.CAPE_RACK, "<br>" .. safe_(Camp.standProgress(key).text) }
    local cape = storedCape()
    if cape and cape[3] ~= "" then lines[#lines + 1] = "<br><col=55FF55>Perk:</col> " .. safe_(cape[3]) end
    if #Camp.standRequirements(key) > 0 then
        lines[#lines + 1] = "<br>Needs the Player Lodge at tier " .. CAPE_RACK_LODGE_TIER .. " to use the rack."
    end
    return { key = key, body = table.concat(lines) }
end

-- Everything a building tier needs, for the note's requirement row.
function Camp.requirements(key, tier)
    local building = Camp.info(key)
    if not building or building.kind ~= "building" then return {} end
    return needsOf(building, math.max(1, math.min(building.tiers, tier or 1)))
end

local function safe(value) return (tostring(value):gsub("<", "["):gsub(">", "]")) end

-- Workers assigned and what they bring in an hour, for a worker note (one worker or a collection), or nil for any other.
function Camp.workerSummary(tracking)
    local children = tracking and (tracking.items or { tracking }) or {}
    if #children == 0 then return nil end
    local assigned = 0
    for _, child in ipairs(children) do
        if type(child.key) ~= "string" or not child.key:match("^camp%-wrk:") then return nil end
        local value = readVar(child.variable)
        if value == nil then return nil end
        assigned = assigned + value
    end
    return { assigned = assigned, perHour = assigned * PER_WORKER }
end

-- The hover card: where a resource or building stands, and for a building what its next tier needs.
function Camp.card(key, target)
    local entry = Camp.info(key)
    if not entry then return nil end
    local value = readVar(entry.var)
    if entry.kind == "iaia" then
        value = Camp.iaiaAmount(key, value)
        local lines = { safe(entry.name), "<br>Dream of Iaia: " .. (value and number(value) or "Unknown") }
        if type(target) == "number" and target > 1 then
            lines[#lines + 1] = "<br>Target: " .. number(target)
                .. (value and value >= target and "<br><col=55FF55>Target reached</col>" or "<br>Target not reached")
        end
        return { key = key, body = table.concat(lines) }
    end
    if entry.kind == "worker" then
        local lines = { safe(entry.name), "<br>Assigned: " .. (value and number(value) or "Unknown") }
        if value then lines[#lines + 1] = "<br>" .. number(value * PER_WORKER) .. " " .. safe(entry.resource.name:lower()) .. " an hour" end
        if type(target) == "number" and target > 1 then
            lines[#lines + 1] = "<br>Target: " .. number(target) .. (value and value >= target and "<br><col=55FF55>Target reached</col>" or "<br>Target not reached")
        end
        return { key = key, body = table.concat(lines) }
    end
    if entry.kind == "resource" then
        local lines = { safe(entry.name), "<br>In your base camp: " .. (value and number(value) or "Unknown") }
        -- The workers gathering it, and what they bring in.
        local workers = readVar("DINO_BASE_CAMP_WORKER_ASSIGNED_" .. entry.suffix)
        if workers then lines[#lines + 1] = "<br>Workers: " .. number(workers) .. " (" .. number(workers * PER_WORKER) .. " an hour)" end
        if type(target) == "number" and target > 1 then
            lines[#lines + 1] = "<br>Target: " .. number(target)
                .. (value and value >= target and "<br><col=55FF55>Target reached</col>" or "<br>Target not reached")
        end
        return { key = key, body = table.concat(lines) }
    end
    local lines = { safe(entry.name) .. (value and (value > 0 and (" - tier " .. value .. " built") or " - not built yet") or "") }
    if value and value >= entry.tiers then
        lines[#lines + 1] = "<br><col=55FF55>Fully built</col>"
    else
        local tier = (value or 0) + 1
        lines[#lines + 1] = "<br>Next: tier " .. tier
        for _, need in ipairs(needsOf(entry, tier)) do
            local mark = need.met and "<col=55FF55>" or "<col=FF5555>"
            lines[#lines + 1] = "<br>" .. mark .. safe(lineOf(need)) .. "</col>"
        end
        if entry.descriptions[tier] then lines[#lines + 1] = "<br>" .. safe(entry.descriptions[tier]) end
    end
    return { key = key, body = table.concat(lines) }
end

return { Camp = Camp }