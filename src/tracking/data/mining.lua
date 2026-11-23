-- Ores and bars you can keep in the metal bank (and, for ores, in the ore box).
-- { Obj id, name, ore box varp (nil for bars) }. The ore box has a normal and an UPGRADED varp; both are added up.

local ORES = {
    { 436, "Copper ore", "MINING_OREBOX_COPPER" },
    { 438, "Tin ore", "MINING_OREBOX_TIN" },
    { 440, "Iron ore", "MINING_OREBOX_IRON" },
    { 453, "Coal", "MINING_OREBOX_COAL" },
    { 442, "Silver ore", "MINING_OREBOX_SILVER" },
    { 444, "Gold ore", "MINING_OREBOX_GOLD" },
    { 447, "Mithril ore", "MINING_OREBOX_MITHRIL" },
    { 449, "Adamantite ore", "MINING_OREBOX_ADAMANTITE" },
    { 451, "Runite ore", "MINING_OREBOX_RUNITE" },
    { 44820, "Luminite", "MINING_OREBOX_LUMINITE" },
    { 44822, "Orichalcite ore", "MINING_OREBOX_ORICHALCITE" },
    { 44824, "Drakolith", "MINING_OREBOX_DRAKOLITH" },
    { 44826, "Necrite ore", "MINING_OREBOX_NECRITE" },
    { 44828, "Phasmatite", "MINING_OREBOX_PHASMATITE" },
    { 21778, "Banite ore", "MINING_OREBOX_BANITE" },
    { 44830, "Light animica", "MINING_OREBOX_LIGHT_ANIMICA" },
    { 44832, "Dark animica", "MINING_OREBOX_DARK_ANIMICA" },
    { 59207, "Platinum ore", "MINING_OREBOX_PLATINUM" },
    { 57175, "Primal novite ore", "MINING_OREBOX_PRIMAL_NOVITE" },
    { 57177, "Primal bathus ore", "MINING_OREBOX_PRIMAL_BATHUS" },
    { 57179, "Primal marmaros ore", "MINING_OREBOX_PRIMAL_MARMAROS" },
    { 57181, "Primal kratonium ore", "MINING_OREBOX_PRIMAL_KRATONIUM" },
    { 57183, "Primal fractite ore", "MINING_OREBOX_PRIMAL_FRACTITE" },
    { 57185, "Primal zephyrium ore", "MINING_OREBOX_PRIMAL_ZEPHYRIUM" },
    { 57187, "Primal argonite ore", "MINING_OREBOX_PRIMAL_ARGONITE" },
    { 57189, "Primal katagon ore", "MINING_OREBOX_PRIMAL_KATAGON" },
    { 57191, "Primal gorgonite ore", "MINING_OREBOX_PRIMAL_GORGONITE" },
    { 57193, "Primal promethium ore", "MINING_OREBOX_PRIMAL_PROMETHIUM" },
}

local BARS = {
    { 2349, "Bronze bar" },
    { 2351, "Iron bar" },
    { 2353, "Steel bar" },
    { 2355, "Silver bar" },
    { 2357, "Gold bar" },
    { 2359, "Mithril bar" },
    { 2361, "Adamantite bar" },
    { 2363, "Runite bar" },
    { 44842, "Banite bar" },
    { 44840, "Necronium bar" },
    { 44844, "Elder rune bar" },
    { 45984, "Masterwork bar (tier 1)" },
    { 45986, "Masterwork bar (tier 2)" },
}

return { ORES = ORES, BARS = BARS }
