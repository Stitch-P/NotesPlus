local Nemi = {}
local definition = {
    key = "scheduled-nemi-forest", group = "Daily", kind = "scheduled", label = "Nemi Forest",
    defaultTarget = 9, varName = "RAID1_FOREST_TOTEM", objId = id.Obj.RAID1_TRINKS_TRINKET,
    unit = "activities", itemWaiting = "Waiting for your Nemi Forest activities", itemIncomplete = "Not completed today",
    description = "Complete each of the nine daily activities in Nemi Forest on Mazcab.",
    hint = "Each activity gives its reward once per day. Completed activities drop off the list. Resets at 00:00 UTC.",
    entries = {
        {name = "Obelisk", variable = "RAID1_FOREST_TOTEM", spriteName = "SKILL_PRAYER"},
        {name = "Water pool", variable = "RAID1_FOREST_POOL", spriteName = "SKILL_PRAYER"},
        {name = "Injured explorer", variable = "RAID1_FOREST_KNIGHT", spriteName = "SKILL_PRAYER"},
        {name = "Dead monk", variable = "RAID1_FOREST_MONK", spriteName = "SKILL_PRAYER"},
        {name = "Fungal growth", variable = "RAID1_FOREST_FUNGUS", spriteName = "SKILL_DUNGEONEERING"},
        {name = "Chest", variable = "RAID1_FOREST_CHEST", spriteName = "SKILL_DUNGEONEERING"},
        {name = "Mushrooms", variable = "RAID1_FOREST_MUSHROOM", spriteName = "SKILL_FARMING"},
        {name = "Red rocks", variable = "RAID1_FOREST_ORE", spriteName = "SKILL_MINING"},
        {name = "Mysterious flowers", variable = "RAID1_FOREST_FLOWERS", spriteName = "SKILL_FARMING"},
    },
}

function Nemi.info() return definition end

return Nemi
