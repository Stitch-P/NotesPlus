-- Archaeology relics. The list of relics is the curated base (the unlock variables are named after each relic); the name and
-- the description come from the relic's own database row (ARCH_RELIC_<NAME>) and the picture from its combat buff sprite
-- (COMBAT_BUFF_ICON_ARCH_RELIC_<NAME>), so wording changes in the game show up by themselves.

local ConfigReader = require("src/tracking/core/config_reader")
local Sprites = require("src/tracking/core/sprites")
local Vars = require("src/tracking/core/vars")

local Relics = {}

Relics.GROUP = "Archaeology"

local NAMES = {
    "FONT_OF_LIFE", "SLAYER_INTROSPECTION", "DIVINE_CONVERSION", "ENDURANCE", "FURY_OF_THE_SMALL", "POUCH_PROTECTOR",
    "CONSERVATION_OF_ENERGY", "ABYSSAL_LINK", "DEATHLESS", "NEXUS_MOD", "PHARM_ECOLOGY", "ALWAYS_ADZE", "PERSISTENT_RAGE",
    "STICKY_FINGERS", "BERSERKERS_FURY", "DEATH_WARD", "INSPIRE_AWE", "INSPIRE_EFFORT", "INSPIRE_GENIUS", "INSPIRE_LOVE",
    "RING_OF_LUCK", "RING_OF_WEALTH", "RING_OF_FORTUNE", "UNEXPECTED_DIPLOMACY", "HEIGHTENED_SENSES", "LUCK_OF_THE_DWARVES",
}

local function prettify(name)
    return (name:lower():gsub("_", " "):gsub("(%a)(%w*)", function(a, b) return a:upper() .. b end))
end

local function text(value)
    if type(value) == "string" and value ~= "" and value ~= "null" then return (value:gsub("<br%s*/?>", "\n")) end
end

local list, byKey

local function build()
    if list then return end
    list, byKey = {}, {}
    for _, name in ipairs(NAMES) do
        local row = ConfigReader.Available() and ConfigReader.Row("ARCH_RELIC_" .. name) or nil
        local label = row and text(ConfigReader.Value(row, 2)) or prettify(name)
        local description = row and text(ConfigReader.Value(row, 3)) or nil
        local sprite = Sprites.spriteByName("COMBAT_BUFF_ICON_ARCH_RELIC_" .. name)
        if not sprite and row then
            -- The row carries sprite ids in its last columns; the last one is the relic's picture.
            for _, column in ipairs({ 10, 9 }) do
                local value = ConfigReader.Value(row, column)
                if type(value) == "number" and value > 0 then sprite = value break end
            end
        end
        local entry = {
            key = "arch-relic:" .. name:lower(), name = label, description = description,
            unlocked = "ARCH_RELIC_" .. name .. "_UNLOCKED", acquired = "ARCH_RELIC_" .. name .. "_ACQUIRED",
            sprite = sprite,
        }
        list[#list + 1], byKey[entry.key] = entry, entry
    end
    table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
end

function Relics.info(key)
    build()
    return byKey[key]
end

function Relics.active(name)
    local relic = ConfigReader.Value(ConfigReader.Row("ARCH_RELIC_" .. name), 1)
    local loadout = Vars.readEntry(Vars.resolveVar("ARCH_RELIC_LOADOUT"))
    if type(relic) ~= "number" or relic <= 0 or type(loadout) ~= "number"
        or loadout < 0 or loadout > 3 or loadout % 1 ~= 0 then return nil end
    local unknown = false
    for slot = 1, 4 do
        local value = Vars.readEntry(Vars.resolveVar(string.format("ARCH_RELIC_LOADOUT_%d_SLOT_%d_ID", loadout, slot)))
        if value == relic then return true end
        if value == nil then unknown = true end
    end
    if not unknown then return false end
end

function Relics.options()
    build()
    local options = {}
    for _, relic in ipairs(list) do
        options[#options + 1] = {
            kind = "relic", key = relic.key, label = relic.name, defaultTarget = 1, varName = relic.unlocked,
            spriteName = relic.sprite and ("#" .. relic.sprite) or nil,
            description = (relic.description or "An Archaeology relic.") .. " Unlocking it completes the goal.",
        }
    end
    return options
end

local function yesNo(name)
    local entry = Vars.resolveVar(name)
    local value = entry and Vars.readEntry(entry)
    if value == nil then return "Unknown" end
    return value > 0 and "Yes" or "No"
end

-- The hover card of a relic note: what it does, and whether you have it.
function Relics.card(key)
    local relic = Relics.info(key)
    if not relic then return nil end
    local function safe(value) return (tostring(value):gsub("<", "["):gsub(">", "]"):gsub("\n", "<br>")) end
    return {
        key = key,
        body = safe(relic.name) .. "<br>" .. safe(relic.description or "An Archaeology relic.") .. "<br><br>Unlocked: "
            .. yesNo(relic.unlocked) .. "<br>Acquired: " .. yesNo(relic.acquired),
    }
end

return { Relics = Relics }
