-- The Memorial to Guthix: its 12 engrams (handed in once HOG_ECHO_<n>_PROGRESS is set, as the Memories of Guthix achievement
-- checks) and the 12 passive effects the Fountain of Energy offers (on while HOG_REWARD_<n>_ACTIVE is set). Effect n is
-- the n-th box of the fountain's grid, read left to right, and shares engram n's picture.

local ENGRAMS = {
    "Naragi engram", "Elder Sword engram", "Fairy engram", "Gnome engram", "World Gate engram", "Druid engram",
    "Stone of Jas engram", "Sheep engram", "Time engram", "Sword of Edicts engram", "Guardians of Guthix engram",
    "Balance Elemental engram",
}

local EFFECTS = {
    "Harmony of Naragun", "Time-worn Memories", "Fairy Fire", "Argento's Kindness", "Ethereal Connection", "Shared Knowledge",
    "Stored Power", "Wisp Herder", "Sempiternal Souvenirs", "Decree of Mortality", "Guardian of Life", "Abyssal Transit",
}

-- What each effect does, and the Divination level it needs (effect n is engram n's).
local EFFECT_INFO = {
    { "Guthixian butterflies will spawn instead of chronicles. This does not affect elder chronicles.", 1 },
    { "The experience from converting memories inside Daemonheim is quadrupled.", 10 },
    { "Fire spirits from firemaking are upgraded to divine fire spirits, granting Divination experience, divine energy, and divine energy products.", 85 },
    { "Divine eggs may appear instead of bird's nests while woodcutting, granting Divination experience, divine energy, and divine energy products.", 90 },
    { "The duration of Divination springs is increased.", 40 },
    { "Divine locations will grant you 125% experience but yield no items.", 50 },
    { "The benefits from fully completing a Guthixian Cache will be bottled for later use.", 95 },
    { "Converting memories has a small chance to spawn an additional wisp.", 70 },
    { "Pickpocketing now has a chance to yield memory shards. Memory shards can be transmuted into Divine energy products.", 80 },
    { "Checking Hunting traps has a chance to yield memory shards. Memory shards can be transmuted into Divine energy products.", 20 },
    { "Planting seeds has a chance to yield memory shards. Memory shards can be transmuted into Divine energy products.", 30 },
    { "Chronicles are now worth twice the amount when empowering the rift.", 60 },
}

return {
    ENGRAMS = ENGRAMS,
    EFFECTS = EFFECTS,
    EFFECT_INFO = EFFECT_INFO,
    ACHIEVEMENT = "cheevo_guthix_memories",
    PRESTIGE_VAR = "HOG_OVERALL_PRESTIGE",
    CURRENCY_VAR = "CURRENCY_HOG_MOTE",
    engramVar = function(n) return "HOG_ECHO_" .. n .. "_PROGRESS" end,
    effectVar = function(n) return "HOG_REWARD_" .. n .. "_ACTIVE" end,
    engramObject = function(n) return "HOG_ENGRAM_" .. n .. "_ATTUNED" end,
}
