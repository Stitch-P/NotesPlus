-- Necromancy unlocks: the abilities bought at the Well of Souls. Each has a variable that says it is unlocked
-- (COMBATV2_ABILITY_NECROMANCY_<NAME>_UNLOCKED); the Well's own tree says which level of the Well it belongs to.
-- Each ability wears its own picture, found by name (the client lists its sprite names a little at a time, so one can take
-- a moment to turn up).

local Sprites = require("src/tracking/core/sprites")
local Vars = require("src/tracking/core/vars")
local ConfigReader = require("src/tracking/core/config_reader")

local Necromancy = {}

Necromancy.GROUP = "Necromancy"
-- The souls you hold: the low 18 bits of NECRO_HUB_PERM_2 (the game's name for them is NECRO_HUB_VESSEL_CAPACITY).
local SOULS_VAR = "NECRO_HUB_VESSEL_CAPACITY"
local KEY_PREFIX = "necro:"

-- Kili's Knowledge: the equipment upgrade achievements, { config name, name, description, a body piece of that tier }.
Necromancy.KILI = {
    { "cheevo_necromancy_underworld_equipment_upgrade_t30", "Kili's Knowledge I", "Learn how to upgrade your Death Skull and Deathwarden equipment to tier 30 from Kili.", "NECRO_UNDERWORLD_BODY_T30" },
    { "cheevo_necromancy_underworld_equipment_upgrade_t40", "Kili's Knowledge II", "Learn how to upgrade your Death Skull and Deathwarden equipment to tier 40 from Kili.", "NECRO_UNDERWORLD_BODY_T40" },
    { "cheevo_necromancy_underworld_equipment_upgrade_t50", "Kili's Knowledge III", "Learn how to upgrade your Death Skull and Deathwarden equipment to tier 50 from Kili.", "NECRO_UNDERWORLD_BODY_T50" },
    { "cheevo_necromancy_underworld_equipment_upgrade_t60", "Kili's Knowledge IV", "Learn how to upgrade your Death Skull and Deathwarden equipment to tier 60 from Kili.", "NECRO_UNDERWORLD_BODY_T60" },
    { "cheevo_necromancy_underworld_equipment_upgrade_t70_tank", "Kili's Knowledge V", "Learn how to upgrade your Death Skull and Deathwarden equipment to tier 70 from Kili.", "NECRO_UNDERWORLD_BODY_T70" },
    { "cheevo_necromancy_underworld_equipment_upgrade_t70_power", "Kili's Knowledge V (power)", "Learn how to upgrade your Death Skull equipment to tier 70, and upgrade your Deathwarden equipment to tier 70 Deathdealer from Kili.", "NECRO_UNDERWORLD_POWER_BODY_T70" },
    { "cheevo_necromancy_underworld_equipment_upgrade_t80_tank", "Kili's Knowledge VI", "Learn how to upgrade your Death Skull and Deathwarden equipment to tier 80 from Kili.", "NECRO_UNDERWORLD_BODY_T80" },
    { "cheevo_necromancy_underworld_equipment_upgrade_t80_power", "Kili's Knowledge VI (power)", "Learn how to upgrade your Death Skull and Deathdealer equipment to tier 80 from Kili.", "NECRO_UNDERWORLD_POWER_BODY_T80" },
    { "cheevo_necromancy_underworld_equipment_upgrade_t90_tank", "Kili's Knowledge VII", "Learn how to upgrade your Death Skull and Deathwarden equipment to tier 90 from Kili.", "NECRO_UNDERWORLD_BODY_T90" },
    { "cheevo_necromancy_underworld_equipment_upgrade_t90_power", "Kili's Knowledge VII (power)", "Learn how to upgrade your Death Skull and Deathdealer equipment to tier 90 from Kili.", "NECRO_UNDERWORLD_POWER_BODY_T90" },
}

-- { name, variable name, Well of Souls level (nil when the Well's tree doesn't list it) }
local ABILITIES = {
    { "Conjure Skeleton Warrior", "CONJURE_SKELETON_WARRIOR", 1 },
    { "Command Skeleton Warrior", "COMMAND_SKELETON_WARRIOR", 2 },
    { "Conjure Putrid Zombie", "CONJURE_PUTRID_ZOMBIE", 3 },
    { "Conjure Vengeful Ghost", "CONJURE_VENGEFUL_GHOST", 3 },
    { "Threads of Fate", "THREADS_OF_FATE", 3 },
    { "Command Putrid Zombie", "COMMAND_PUTRID_ZOMBIE", 4 },
    { "Command Vengeful Ghost", "COMMAND_VENGEFUL_GHOST", 4 },
    { "Spectral Scythe", "SPECTRAL_SCYTHE", 4 },
    { "Lesser Bone Shield", "LESSER_BONE_SHIELD", nil },
    { "Greater Bone Shield", "GREATER_BONE_SHIELD", 5 },
    { "Life Transfer", "LIFE_TRANSFER", 5 },
    { "Spectral Scythe Upgrade 1", "SPECTRAL_SCYTHE_RECAST_1", 5 },
    { "Darkness", "DARKNESS", 6 },
    { "Invoke Death", "INVOKE_DEATH", 6 },
    { "Spectral Scythe Upgrade 2", "SPECTRAL_SCYTHE_RECAST_2", 6 },
    { "Split Soul", "SPLIT_SOUL", 7 },
    { "Conjure Undead Army", "CONJURE_UNDEAD_ARMY", 7 },
}

local entries, byKey = {}, {}
for _, row in ipairs(ABILITIES) do
    local entry = { key = KEY_PREFIX .. row[2]:lower(), name = row[1], suffix = row[2], level = row[3],
        var = "COMBATV2_ABILITY_NECROMANCY_" .. row[2] .. "_UNLOCKED" }
    entries[#entries + 1], byKey[entry.key] = entry, entry
end

function Necromancy.isKey(key) return type(key) == "string" and key:sub(1, #KEY_PREFIX) == KEY_PREFIX end

-- The ability's own picture, looked up on every ask until it is found.
local function spriteOf(entry)
    if entry.sprite then return entry.sprite end
    -- The ability's struct (combatv2_ability_necromancy_<name>) names its icon sprite directly.
    local icon = ConfigReader.Available() and ConfigReader.StructParam("COMBATV2_ABILITY_NECROMANCY_" .. entry.suffix, "COMBATV2_ABILITY_ICON")
    if type(icon) == "number" and icon > 0 then entry.sprite = icon; return icon end
    local names = {}
    for _, form in ipairs({ "COMBATV2_ABILITY_NECROMANCY_", "COMBATV2_ABILITY_", "ABILITY_NECROMANCY_", "COMBAT_ABILITY_NECROMANCY_",
        "NECROMANCY_ABILITY_", "ABILITY_ICON_NECROMANCY_", "COMBATV2_ABILITY_ICON_NECROMANCY_" }) do
        names[#names + 1] = form .. entry.suffix
    end
    for _, name in ipairs(names) do
        for _, variant in ipairs({ name, name .. "_0" }) do
            local ok, sprite = pcall(Sprites.spriteByName, variant)
            if ok and type(sprite) == "number" and sprite > 0 then entry.sprite = sprite; return sprite end
        end
    end
    local ok, sprite = pcall(Sprites.findSprite, "necromancy " .. entry.suffix:lower():gsub("_", " "))
    if ok and type(sprite) == "number" and sprite > 0 then entry.sprite = sprite end
    return entry.sprite
end

local function readVar(name)
    local entry = Vars.resolveVar(name)
    local value = entry and Vars.readEntry(entry)
    return type(value) == "number" and value or nil
end

-- What each tier of the Well asks for ({ Necromancy level, vessel souls }), read off the tier's information pop-up. The
-- game's data doesn't carry these, taken from the wiki table. Tiers are the Well levels in the tree.
local TIER_REQUIREMENTS = { [1] = { 1, 1 }, [2] = { 20, 50 }, [3] = { 40, 400 }, [4] = { 60, 2000 }, [5] = { 70, 4500 },
    [6] = { 80, 8500 }, [7] = { 90, 35000 } }

local function soulsNeeded(entry)
    local tier = entry.level and TIER_REQUIREMENTS[entry.level]
    return tier and tier[2] or nil
end

local function souls()
    local held = readVar(SOULS_VAR)
    if held then return held end
    local perm = readVar("NECRO_HUB_PERM_2")
    return perm and perm % 262144 or nil -- low 18 bits (0x3ffff)
end

local function number(value) return Vars.withCommas and Vars.withCommas(value) or tostring(value) end

local function describe(entry)
    local where = entry.level and ("Unlocked at level " .. entry.level .. " of the Well of Souls.") or "Unlocked at the Well of Souls."
    local cost = soulsNeeded(entry)
    return where .. (cost and (" Needs " .. number(cost) .. " vessel souls (and Necromancy level " .. TIER_REQUIREMENTS[entry.level][1] .. ").") or "") .. " Unlocking it completes the goal."
end

function Necromancy.options()
    local options = {}
    for _, entry in ipairs(entries) do
        -- Ones you already have need nothing more, so they aren't offered.
        if (readVar(entry.var) or 0) < 1 then
            local sprite = spriteOf(entry)
            options[#options + 1] = {
                kind = "necro", key = entry.key, label = entry.name, varName = entry.var, defaultTarget = 1,
                spriteName = sprite and ("#" .. sprite) or nil, description = describe(entry),
            }
        end
    end
    return options
end

function Necromancy.info(key) return byKey[key] end

-- "Requires: <souls icon> 35,000 Souls": what the ability's tier of the Well asks for, lit once you hold that many.
local soulsSprite
function Necromancy.requirements(key)
    local entry = byKey[key]
    local cost = entry and soulsNeeded(entry)
    if not cost then return {} end
    if soulsSprite == nil then
        local ok, sprite = pcall(Sprites.spriteByName, "SKILL_TREE_ICON_NECROMANCY_SOULS")
        soulsSprite = ok and type(sprite) == "number" and sprite > 0 and sprite or false
    end
    local held = souls()
    return { { kind = "skill", name = "Souls", level = cost, have = held, text = number(cost) .. " Souls",
        met = held ~= nil and held >= cost, tip = held and ("You have: " .. number(held)) or "Your souls are not available yet", icon = soulsSprite and { sprite = soulsSprite } or nil } }
end

function Necromancy.card(key)
    local entry = byKey[key]
    if not entry then return nil end
    local value = readVar(entry.var)
    local lines = { (entry.name:gsub("<", "["):gsub(">", "]")) }
    lines[#lines + 1] = (value and value >= 1) and "<br><col=55FF55>Unlocked</col>" or "<br>Not unlocked yet"
    lines[#lines + 1] = "<br>" .. describe(entry):gsub("<", "["):gsub(">", "]")
    local held = souls()
    if held then lines[#lines + 1] = "<br>Your souls: " .. number(held) end
    return { key = key, body = table.concat(lines) }
end

return { Necromancy = Necromancy }
