-- Area task layout: the tier order and the area labels and order. The tasks themselves are read from the game's achievements
-- (core/task_source.lua).

local TIERS = { "Beginner", "Easy", "Medium", "Hard", "Elite" }

-- { key, label [, any category] }, in the order they appear in the Area dropdown.
local AREAS = {
    { "ar", "Ardougne" },
    { "dun", "Daemonheim" },
    { "des", "Desert" },
    { "fal", "Falador" },
    { "frem", "Fremennik" },
    { "jun", "Karamja" },
    { "lum", "Lumbridge" },
    { "mo", "Morytania" },
    -- A third value of true: the area's tasks are taken whatever category the game files them under (New Varrock's tasks
    -- are filed with the exploration achievements, not with the other area tasks).
    { "q200", "New Varrock", true },
    { "seer", "Seers' Village" },
    { "elf", "Tirannwn" },
    { "um", "Underworld" },
    { "var", "Varrock" },
    { "wild", "Wilderness" },
}

return { TIERS = TIERS, AREAS = AREAS }
