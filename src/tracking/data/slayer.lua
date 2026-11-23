-- Slayer areas: the area names that saved notes refer to, and each area's "log complete" title variable.
-- The drops, sprites and texts are read from the game (core/slayer_source.lua).
-- AREAS = { { name, title variable, sprite, text, { items } } }

local AREAS = {
    { "Asgarnia & Misthalin", "ITEMLOG_SLAYER_ASGARNIA_MISTHALIN_TITLE", nil, nil, {} },
    { "Daemonheim", "ITEMLOG_SLAYER_DAEMONHEIM_TITLE", nil, nil, {} },
    { "Desert", "ITEMLOG_SLAYER_DESERT_TITLE", nil, nil, {} },
    { "Feldip", "ITEMLOG_SLAYER_FELDIP_TITLE", nil, nil, {} },
    { "Fremennik", "ITEMLOG_SLAYER_FREMENNIK_TITLE", nil, nil, {} },
    { "Kandarin", "ITEMLOG_SLAYER_KANDARIN_TITLE", nil, nil, {} },
    { "Karamja", "ITEMLOG_SLAYER_KARAMJA_TITLE", nil, nil, {} },
    { "Keldagrim", "ITEMLOG_SLAYER_KELDAGRIM_TITLE", nil, nil, {} },
    { "Lost Lands", "ITEMLOG_SLAYER_LOST_LANDS_TITLE", nil, nil, {} },
    { "Morytania", "ITEMLOG_SLAYER_MORYTANIA_TITLE", nil, nil, {} },
    { "Off-world", "ITEMLOG_SLAYER_OFF_WORLD_TITLE", nil, nil, {} },
    { "Wilderness", "ITEMLOG_SLAYER_WILDERNESS_TITLE", nil, nil, {} },
    { "Senntisten", "ITEMLOG_SLAYER_SENNTISTEN_TITLE", nil, nil, {} },
    { "Havenhythe", "ITEMLOG_SLAYER_HAVENHYTHE_TITLE", nil, nil, {} },
    { "General", nil, nil, nil, {} },
}

return { AREAS = AREAS }
