-- The two skill statues: Dahmaroc's in Varrock (STATUE_*) and Rhiannon's in Prifddinas (ELFCITY_STATUE_*). Each skill's
-- piece is added once its <PREFIX><SKILL>_ADDED flag is set; <PREFIX>STATE counts how many have been. Rows are
-- { skill type (for the icon), name shown, flag }. Prifddinas has one piece for all of melee (shown with the Attack icon).
local VARROCK = {
    { "AGILITY", "Agility", "STATUE_AGILITY_ADDED" },
    { "CONSTRUCTION", "Construction", "STATUE_CONSTRUCTION_ADDED" },
    { "COOKING", "Cooking", "STATUE_COOKING_ADDED" },
    { "CRAFTING", "Crafting", "STATUE_CRAFTING_ADDED" },
    { "FARMING", "Farming", "STATUE_FARMING_ADDED" },
    { "FIREMAKING", "Firemaking", "STATUE_FIREMAKING_ADDED" },
    { "FISHING", "Fishing", "STATUE_FISHING_ADDED" },
    { "FLETCHING", "Fletching", "STATUE_FLETCHING_ADDED" },
    { "HERBLORE", "Herblore", "STATUE_HERBLORE_ADDED" },
    { "HUNTER", "Hunter", "STATUE_HUNTER_ADDED" },
    { "MINING", "Mining", "STATUE_MINING_ADDED" },
    { "RUNECRAFTING", "Runecrafting", "STATUE_RUNECRAFTING_ADDED" },
    { "SMITHING", "Smithing", "STATUE_SMITHING_ADDED" },
    { "THIEVING", "Thieving", "STATUE_THIEVING_ADDED" },
    { "WOODCUTTING", "Woodcutting", "STATUE_WOODCUTTING_ADDED" },
}

local PRIFDDINAS = {
    { "AGILITY", "Agility", "ELFCITY_STATUE_AGILITY_ADDED" },
    { "CONSTRUCTION", "Construction", "ELFCITY_STATUE_CONSTRUCTION_ADDED" },
    { "CRAFTING", "Crafting", "ELFCITY_STATUE_CRAFTING_ADDED" },
    { "DIVINATION", "Divination", "ELFCITY_STATUE_DIVINATION_ADDED" },
    { "DUNGEONEERING", "Dungeoneering", "ELFCITY_STATUE_DUNGEONEERING_ADDED" },
    { "FARMING", "Farming", "ELFCITY_STATUE_FARMING_ADDED" },
    { "HERBLORE", "Herblore", "ELFCITY_STATUE_HERBLORE_ADDED" },
    { "MAGIC", "Magic", "ELFCITY_STATUE_MAGIC_ADDED" },
    { "ATTACK", "Melee", "ELFCITY_STATUE_MELEE_ADDED" },
    { "MINING", "Mining", "ELFCITY_STATUE_MINING_ADDED" },
    { "PRAYER", "Prayer", "ELFCITY_STATUE_PRAYER_ADDED" },
    { "RANGED", "Ranged", "ELFCITY_STATUE_RANGED_ADDED" },
    { "SLAYER", "Slayer", "ELFCITY_STATUE_SLAYER_ADDED" },
    { "SMITHING", "Smithing", "ELFCITY_STATUE_SMITHING_ADDED" },
    { "SUMMONING", "Summoning", "ELFCITY_STATUE_SUMMONING_ADDED" },
    { "WOODCUTTING", "Woodcutting", "ELFCITY_STATUE_WOODCUTTING_ADDED" },
}

return { VARROCK = VARROCK, PRIFDDINAS = PRIFDDINAS, VARROCK_STATE = "STATUE_STATE", PRIFDDINAS_STATE = "ELFCITY_STATUE_STATE" }
