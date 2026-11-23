-- Variants are keyed by the selected boss's native Reaper struct name.
return {
    ["Amascut"] = {
        npc = "AMASCUT_BOSS", animation = "AMASCUT_BOSS_IDLE", modelType = "NPC_MODEL",
        viewDistance = 1700, screenX = -47, screenY = -16,
        rowHeight = 160,
    },
    ["Araxxi"] = {
        npc = "SB_BOSS2", animation = "SB_SPIDER_BOSS_02_WALK", modelType = "NPC_MODEL",
        viewDistance = 2600, screenX = 20, screenY = -50,
        rowHeight = 160,
    },
    ["Arch-Glacor"] = {
        npc = "EGWD_WEN_BOSS", animation = "EGWD_WEN_BOSS_GLACOR_IDLE", modelType = "NPC_MODEL",
        viewDistance = 6200, screenX = 0, screenY = 0,
        rowHeight = 160,
    },
    ["Barrows"] = {
        models = {
            {
                label = "Dharok",
                npc = "BARROWS_DHAROK", animation = "BARROW_DHAROK_READY", modelType = "NPC_MODEL",
                viewDistance = 1000, screenX = -80, screenY = -80,
            },
            {
                label = "Ahrim",
                npc = "BARROWS_AHRIM", animation = "HUMAN_STAFFREADY", modelType = "NPC_MODEL",
                viewDistance = 1000, screenX = -204, screenY = -80,
            },
            {
                label = "Guthan",
                npc = "BARROWS_GUTHAN", animation = "HUMAN_STAFFREADY", modelType = "NPC_MODEL",
                viewDistance = 1000, screenX = -340, screenY = -80,
            },
            {
                label = "Karil",
                npc = "BARROWS_KARIL", animation = "HUMAN_READY", modelType = "NPC_MODEL",
                viewDistance = 1000, screenX = -80, screenY = -70,
            },
            {
                label = "Torag",
                npc = "BARROWS_TORAG", animation = "HUMAN_READY", modelType = "NPC_MODEL",
                viewDistance = 1000, screenX = -212, screenY = -70,
            },
            {
                label = "Verac",
                npc = "BARROWS_VERAC", animation = "BARROW_GUTHAN_READY", modelType = "NPC_MODEL",
                viewDistance = 1000, screenX = -344, screenY = -70,
            },
        },
        columns = 3,
        rowHeight = 110,
    },
    ["Chaos Elemental"] = {
        npc = "CHAOSELEMENTAL", animation = "ELEMENTAL_UPDATE_CHAOS_READY", modelType = "NPC_MODEL",
        viewDistance = 800, screenX = -16, screenY = 4,
        rowHeight = 160,
    },
    ["Commander Zilyana"] = {
        npc = "GODWARS_SARADOMIN_AVATAR", animation = "GODWARS_SARADOMIN_READY", modelType = "NPC_MODEL",
        viewDistance = 900, screenX = -34, screenY = -24,
        rowHeight = 160,
    },
    ["Corporeal Beast"] = {
        npc = "SUM2_SPIRIT_BEAST_CORPOREAL", animation = "SUM1_SPIRIT_BEAST_READY", modelType = "NPC_MODEL",
        viewDistance = 2100, screenX = -14, screenY = -32,
        rowHeight = 160,
    },
    ["Croseus"] = {
        npc = "EGWD_BIK_BOSS", animation = "EGWD_BIK_BOSS_CROESUS_IDLE", modelType = "NPC_MODEL",
        viewDistance = 4400, screenX = 1, screenY = -20,
        rowHeight = 160,
    },
    ["Dagannoth Kings"] = {
        models = {
            {
                label = "Dagannoth Rex",
                npc = "DAGCAVE_MELEE_BOSS", animation = "DAGANNOTH_KINGS_2016_UPDATE_MELEE_IDLE", modelType = "NPC_MODEL",
                viewDistance = 2000, screenX = -19, screenY = -52,
            },
            {
                label = "Dagannoth Supreme",
                npc = "DAGCAVE_RANGED_BOSS", animation = "DAGANNOTH_KINGS_2016_UPDATE_RANGE_IDLE", modelType = "NPC_MODEL",
                viewDistance = 2000, screenX = -98, screenY = -52,
            },
            {
                label = "Dagannoth Prime",
                npc = "DAGCAVE_MAGIC_BOSS", animation = "DAGANNOTH_KINGS_2016_UPDATE_MAGIC_IDLE", modelType = "NPC_MODEL",
                viewDistance = 2000, screenX = -183, screenY = -48,
            },
        },
        columns = 3,
        rowHeight = 130,
    },
    ["Dragonkin Laboratory"] = {
        npc = "DUNGEON_DRAGONFORT_BOSS3", animation = "DUNGEON_WILDERNESS_ASTELLARN_IDLE", modelType = "NPC_MODEL",
        viewDistance = 1900, screenX = 41, screenY = -24,
        variants = {
            ["BSLAY_DUNGEON_DRAGONFORT1"] = {
                npc = "DUNGEON_DRAGONFORT_BOSS1", animation = "DUNGEON_WILDERNESS_ASTELLARN_IDLE", modelType = "NPC_MODEL",
                preset = false,
                viewDistance = 2500, screenX = 40, screenY = 0,
                rowHeight = 160,
            },
            ["BSLAY_DUNGEON_DRAGONFORT2"] = {
                npc = "DUNGEON_DRAGONFORT_BOSS2", animation = "BTW_KBD_2017_READY", modelType = "NPC_MODEL",
                preset = false,
                viewDistance = 2240, screenX = 12, screenY = 32,
                rowHeight = 160,
            },
        },
        rowHeight = 160,
    },
    ["Elidinis"] = {
        npc = "ELIDINIS_BOSS_CORRUPT", animation = "ELIDINIS_BOSS_IDLE", modelType = "NPC_MODEL",
        viewDistance = 3500, screenX = -23, screenY = -16,
        rowHeight = 160,
    },
    ["Flesh-hatcher Mhekarnahz"] = {
        npc = "STALKER_BOSS", animation = "STALKER_2022_IDLE", modelType = "NPC_MODEL",
        viewDistance = 2500, screenX = -3, screenY = 12,
        rowHeight = 160,
    },
    ["General Graardor"] = {
        npc = "GODWARS_BANDOS_AVATAR", animation = "GODWARS_GENERAL_GRAARDOR_2012_READY", modelType = "NPC_MODEL",
        viewDistance = 1400, screenX = -15, screenY = -12,
        rowHeight = 160,
    },
    ["Giant Mole"] = {
        npc = "MOLE2_GIANT", animation = "MOLE2_GIANT_MOLE_IDLE", modelType = "NPC_MODEL",
        viewDistance = 900, screenX = -3, screenY = -44,
        rowHeight = 160,
    },
    ["Gregorovic"] = {
        npc = "GWD2_SLISKE_BOSS", animation = "GWD2_SLISKE_GENERAL_IDLE", modelType = "NPC_MODEL",
        viewDistance = 800, screenX = -39, screenY = -32,
        rowHeight = 160,
    },
    ["Helwyr"] = {
        npc = "GWD2_SEREN_BOSS", animation = "GWD2_SEREN_GENERAL_IDLE", modelType = "NPC_MODEL",
        viewDistance = 1600, screenX = -7, screenY = -20,
        rowHeight = 160,
    },
    ["Hermod"] = {
        npc = "HERMOD_BOSS", animation = "HERMOD_IDLE", modelType = "NPC_MODEL",
        viewDistance = 1300, screenX = -19, screenY = -16,
        rowHeight = 160,
    },
    ["Ivar, King of Bones"] = {
        npc = "WENDLE_GIANT_BOSS", animation = "GIANT_STANDARD_IDLE", modelType = "NPC_MODEL",
        viewDistance = 1000, screenX = -11, screenY = -16,
        rowHeight = 160,
    },
    ["K'ril Tsutsaroth"] = {
        npc = "GODWARS_ZAMORAK_AVATAR", animation = "RAND_BOSS_DEMON_GHAN_KO_READY", modelType = "NPC_MODEL",
        viewDistance = 2200, screenX = -11, screenY = -20,
        rowHeight = 160,
    },
    ["Kalphite King"] = {
        npc = "KK_KING_MELEE", animation = "KK_KALPHITE_KING_READY", modelType = "NPC_MODEL",
        viewDistance = 1400, screenX = 17, screenY = -16,
        rowHeight = 160,
    },
    ["Kalphite Queen"] = {
        npc = "KALPHITE_QUEEN", animation = "KALPHITE_QUEEN_2014_READY", modelType = "NPC_MODEL",
        viewDistance = 1000, screenX = 17, screenY = -40,
        rowHeight = 160,
    },
    ["Kerapac"] = {
        npc = "EGWD_JAS_BOSS", animation = "EGWD_JAS_BOSS_KERAPAC_IDLE_STAFF", modelType = "NPC_MODEL",
        viewDistance = 1100, screenX = -15, screenY = -16,
        rowHeight = 160,
    },
    ["King Black Dragon"] = {
        npc = "KING_DRAGON", animation = "DRAGON_UPDATE_2012_KBD_READY", modelType = "NPC_MODEL",
        viewDistance = 1900, screenX = -11, screenY = -12,
        rowHeight = 160,
    },
    ["Kree'arra"] = {
        npc = "GODWARS_ARMADYL_AVATAR", animation = "GODWARS_KREE_ARRA_2012_READY", modelType = "NPC_MODEL",
        viewDistance = 1500, screenX = -19, screenY = -20,
        rowHeight = 160,
    },
    ["Legiones"] = {
        models = {
            {
                label = "Legio Primus",
                npc = "ASC_LEGIO_1", animation = "ASC_LEGIO_IDLE", modelType = "NPC_MODEL",
                viewDistance = 1300, screenX = -59, screenY = -64,
            },
            {
                label = "Legio Secundus",
                npc = "ASC_LEGIO_2", animation = "ASC_LEGIO_IDLE", modelType = "NPC_MODEL",
                viewDistance = 1300, screenX = -175, screenY = -64,
            },
            {
                label = "Legio Tertius",
                npc = "ASC_LEGIO_3", animation = "ASC_LEGIO_IDLE", modelType = "NPC_MODEL",
                viewDistance = 1300, screenX = -291, screenY = -64,
            },
            {
                label = "Legio Quartus",
                npc = "ASC_LEGIO_4", animation = "ASC_LEGIO_IDLE", modelType = "NPC_MODEL",
                viewDistance = 1300, screenX = -59, screenY = -80,
            },
            {
                label = "Legio Quintus",
                npc = "ASC_LEGIO_5", animation = "ASC_LEGIO_IDLE", modelType = "NPC_MODEL",
                viewDistance = 1300, screenX = -175, screenY = -80,
            },
            {
                label = "Legio Sextus",
                npc = "ASC_LEGIO_6", animation = "ASC_LEGIO_IDLE", modelType = "NPC_MODEL",
                viewDistance = 1300, screenX = -291, screenY = -80,
            },
        },
        columns = 3,
        rowHeight = 160,
    },
    ["Magister"] = {
        npc = "MENAPHOS_SLAYER_BOSS", animation = "MENAPHOS_OREB_IDLE", modelType = "NPC_MODEL",
        viewDistance = 600, screenX = 13, screenY = -4,
        rowHeight = 160,
    },
    ["Mazcab"] = {
        npc = "RAID1_BEASTMASTER", animation = "TUSKA_RAIDS_BEASTMASTER_IDLE", modelType = "NPC_MODEL",
        viewDistance = 1700, screenX = -7, screenY = -16,
        variants = {
            ["BSLAY_YAKAMARU"] = {
                npc = "RAID1_WATERBOSS", animation = "TUSKA_RAIDS_WATERBOSS_IDLE", modelType = "NPC_MODEL",
                viewDistance = 2820, screenX = -28, screenY = -60,
                rowHeight = 160,
            },
        },
        rowHeight = 160,
    },
    ["Nex"] = {
        npc = "GODWARS2_ZAROS_AVATAR", animation = "GODWARS_NEX_2012_READY", modelType = "NPC_MODEL",
        viewDistance = 1000, screenX = -7, screenY = -12,
        rowHeight = 160,
    },
    ["Nex: Angel of Death"] = {
        npc = "NEX2", animation = "GODWARS_NEX_2012_READY", modelType = "NPC_MODEL",
        viewDistance = 1600, screenX = -7, screenY = -12,
        rowHeight = 160,
    },
    ["Osseous"] = {
        npc = "REXKINGS_NECRO_BOSS", animation = "REXKINGS_NECRO_BOSS_IDLE", modelType = "NPC_MODEL",
        viewDistance = 2700, screenX = 1, screenY = -12,
        rowHeight = 160,
    },
    ["Queen Black Dragon"] = {
        npc = "QBD2_BOSS", animation = "QBD2_QBD_READY", modelType = "NPC_MODEL",
        viewDistance = 6300, screenX = -23, screenY = -44,
        rowHeight = 160,
    },
    ["Raksha"] = {
        npc = "DINO_BOSS", animation = "DINO_BOSS_IDLE", modelType = "NPC_MODEL",
        viewDistance = 3400, screenX = -11, screenY = -16,
        rowHeight = 160,
    },
    ["Rasial"] = {
        npc = "RASIAL_BOSS", animation = "HUMAN_ACTOR_COMBAT_ARMED_IDLE", modelType = "NPC_MODEL",
        viewDistance = 700, screenX = -47, screenY = -16,
        rowHeight = 160,
    },
    ["Rex Matriarchs"] = {
        models = {
            {
                label = "Pthentraken",
                npc = "REXKINGS_MAGIC_BOSS", animation = "BIG_GAME_TYRANNOSAUR_IDLE", modelType = "NPC_MODEL",
                viewDistance = 3100, screenX = -39, screenY = -16,
            },
            {
                label = "Orikalka",
                npc = "REXKINGS_MELEE_BOSS", animation = "BIG_GAME_TYRANNOSAUR_IDLE", modelType = "NPC_MODEL",
                viewDistance = 3100, screenX = -123, screenY = -16,
            },
            {
                label = "Rathis",
                npc = "REXKINGS_RANGED_BOSS", animation = "BIG_GAME_TYRANNOSAUR_IDLE", modelType = "NPC_MODEL",
                viewDistance = 3100, screenX = -200, screenY = -16,
            },
        },
        columns = 3,
        rowHeight = 160,
    },
    ["Rise of the Six"] = {
        models = {
            {
                label = "Ahrim",
                npc = "BARROWS2_AHRIM", animation = "HUMAN_ACTOR_COMBAT_ARMED_IDLE", modelType = "NPC_MODEL",
                viewDistance = 900, screenX = -48, screenY = -80,
            },
            {
                label = "Dharok",
                npc = "BARROWS2_DHAROK", animation = "HUMAN_ACTOR_COMBAT_ARMED_MAUL_IDLE", modelType = "NPC_MODEL",
                viewDistance = 900, screenX = -174, screenY = -80,
            },
            {
                label = "Guthan",
                npc = "BARROWS2_GUTHAN", animation = "HUMAN_ACTOR_COMBAT_ARMED_TWO_HANDED_SPEAR_IDLE", modelType = "NPC_MODEL",
                viewDistance = 900, screenX = -308, screenY = -80,
            },
            {
                label = "Karil",
                npc = "BARROWS2_KARIL", animation = "HUMAN_ACTOR_COMBAT_ARMED_IDLE", modelType = "NPC_MODEL",
                viewDistance = 900, screenX = -48, screenY = -72,
            },
            {
                label = "Torag",
                npc = "BARROWS2_TORAG", animation = "HUMAN_ACTOR_COMBAT_ARMED_MAUL_IDLE", modelType = "NPC_MODEL",
                viewDistance = 900, screenX = -174, screenY = -72,
            },
            {
                label = "Verac",
                npc = "BARROWS2_VERAC", animation = "HUMAN_ACTOR_COMBAT_ARMED_MAUL_IDLE", modelType = "NPC_MODEL",
                viewDistance = 900, screenX = -308, screenY = -72,
            },
        },
        columns = 3,
        rowHeight = 110,
    },
    ["Sanctum of Rebirth"] = {
        npc = "RAID_REBIRTH1_SLAYER_MASTER_BOSS", animation = "RAID_REBIRTH1_SLAYER_MASTER_BOSS_IDLE", modelType = "NPC_MODEL",
        viewDistance = 1300, screenX = -3, screenY = -20,
        variants = {
            ["BSLAY_RAID_REBIRTH1_BEAST_BOSS"] = {
                npc = "RAID_REBIRTH1_BEAST_BOSS", animation = "RAID_REBIRTH1_DARK_BEAST_BOSS_IDLE", modelType = "NPC_MODEL",
                viewDistance = 1700, screenX = -27, screenY = -16,
                rowHeight = 160,
            },
            ["BSLAY_RAID_REBIRTH1_WYRM_BOSS"] = {
                npc = "RAID_REBIRTH1_WYRM_BOSS", animation = "DUNGEON_ULTHVEN_CRASSIAN_LEVIATHAN_IDLE", modelType = "NPC_MODEL",
                viewDistance = 1640, screenX = -16, screenY = -60,
                rowHeight = 160,
            },
        },
        rowHeight = 160,
    },
    ["Silverquill"] = {
        npc = "WENDLE_HEDGEHOG_BOSS", animation = "WENDLE_HEDGEHOG_BOSS_IDLE", modelType = "NPC_MODEL",
        viewDistance = 600, screenX = -27, screenY = -28,
        rowHeight = 160,
    },
    ["Solak"] = {
        npc = "NATURE_BOSS_MAIN", animation = "NATURE_BOSS_SOLAK_IDLE", modelType = "NPC_MODEL",
        viewDistance = 2400, screenX = 21, screenY = -12,
        rowHeight = 160,
    },
    ["Telos"] = {
        npc = "GWD2_SOLO_BOSS", animation = "GWD2_SOLO_BOSS_IDLE", modelType = "NPC_MODEL",
        viewDistance = 2400, screenX = -3, screenY = -12,
        rowHeight = 160,
    },
    ["Temple of Aminishi"] = {
        npc = "DUNGEON_AMINISHI_BOSS3", animation = "DUNGEON_AMINISHI_EVIL_SEIRYU_HEAD_IDLE", modelType = "NPC_MODEL",
        viewDistance = 4200, screenX = 1, screenY = -12,
        rowHeight = 160,
    },
    ["The Ghrazi Blood Knights"] = {
        models = {
            {
                label = "Lady Karmina Ghrazi",
                npc = "BLOOD_KNIGHT_BOSS_LADY_GHRAZI", animation = "GHRAZI_LADY_IDLE", modelType = "NPC_MODEL",
                viewDistance = 1200, screenX = -43, screenY = -16,
            },
            {
                label = "Lord Vasily Ghrazi",
                npc = "BLOOD_KNIGHT_BOSS_LORD_GHRAZI", animation = "GHRAZI_LORD_IDLE", modelType = "NPC_MODEL",
                viewDistance = 1200, screenX = -135, screenY = 4,
            },
        },
        columns = 2,
        rowHeight = 160,
    },
    ["The Shadow Reef"] = {
        npc = "DUNGEON_ULTHVEN_BOSS3", animation = "DUNGEON_ULTHVEN_AMBASSADOR_IDLE", modelType = "NPC_MODEL",
        viewDistance = 1600, screenX = -11, screenY = 8,
        variants = {
            ["BSLAY_DUNGEON_ULTHVEN1"] = {
                npc = "DUNGEON_ULTHVEN_BOSS1", animation = "DUNGEON_ULTHVEN_CRASSIAN_LEVIATHAN_IDLE", modelType = "NPC_MODEL",
                preset = false,
                viewDistance = 1320, screenX = 8, screenY = 0,
                rowHeight = 160,
            },
            ["BSLAY_DUNGEON_ULTHVEN2"] = {
                npc = "DUNGEON_ULTHVEN_BOSS2", animation = "DOV_TARSHAK_STAGE_2_IDLE", modelType = "NPC_MODEL",
                preset = false,
                viewDistance = 980, screenX = 0, screenY = 28,
                rowHeight = 160,
            },
        },
        rowHeight = 160,
    },
    ["Twin Furies"] = {
        models = {
            {
                npc = "GWD2_ZAM_BOSS_MELEE", animation = "GWD2_ZAMORAK_GENERAL_BLACK_IDLE", modelType = "NPC_MODEL",
                viewDistance = 1100, screenX = 84, screenY = -12,
            },
            {
                npc = "EGWD_CITY_NYMORA", animation = "GWD2_ZAMORAK_GENERAL_BLACK_IDLE", modelType = "NPC_MODEL",
                viewDistance = 1100, screenX = -250, screenY = -12,
            },
        },
        columns = 2,
        rowHeight = 160,
    },
    ["TzHaar"] = {
        npc = "TZKILN_SQUID_HEAD", animation = "TZHAAR2_TOKHAAR_SQUID_BOSS_READY", modelType = "NPC_MODEL",
        viewDistance = 1900, screenX = -3, screenY = -28,
        variants = {
            ["BSLAY_JAD"] = {
                npc = "TZHAAR_FIGHTCAVE_SWARM_BOSS", animation = "TZHAAR_2011_TOR_JAD_READY", modelType = "NPC_MODEL",
                viewDistance = 1900, screenX = 1, screenY = -12,
                rowHeight = 160,
            },
        },
        rowHeight = 160,
    },
    ["Vindicta"] = {
        models = {
            {
                label = "Vindicta",
                npc = "GWD2_ZAROS_BOSS_VINDICTA", animation = "GWD2_ZAROS_GENERAL_GROUNDED_IDLE", modelType = "NPC_MODEL",
                viewDistance = 900, screenX = -39, screenY = -20,
            },
            {
                label = "Gorvek",
                npc = "GWD2_ZAROS_BOSS_GORVEK", animation = "GWD2_ZAROS_GENERAL_DRAGON_IDLE", modelType = "NPC_MODEL",
                viewDistance = 1300, screenX = -75, screenY = 0,
            },
        },
        columns = 2,
        rowHeight = 160,
    },
    ["Vorago"] = {
        npc = "LRC2_BOSS", animation = "BOSS2_BOSS_IDLE", modelType = "NPC_MODEL",
        viewDistance = 3600, screenX = -19, screenY = -12,
        rowHeight = 160,
    },
    ["Vorkath"] = {
        models = {
            {
                label = "Vorkath",
                npc = "FORT_BOSS_VORKATH", animation = "DRAGON_BOSS_VORKATH_IDLE", modelType = "NPC_MODEL",
                viewDistance = 1900, screenX = 69, screenY = -32,
            },
            {
                label = "Zemouregal",
                npc = "FORT_BOSS_ZEMOUREGAL", animation = "Q200_ZEMOUREGAL_IDLE", modelType = "NPC_MODEL",
                viewDistance = 1300, screenX = 45, screenY = -32,
            },
        },
        columns = 2,
        rowHeight = 160,
    },
    ["Zamorak"] = {
        npc = "EGWD_ZAMORAK_BOSS", animation = "ZAMORAK_IDLE", modelType = "NPC_MODEL",
        viewDistance = 2800, screenX = -27, screenY = -4,
        rowHeight = 160,
    },
    ["Zuk"] = {
        npc = "EGWD_FUL_BOSS_SHOWDOWN", animation = "EGWD_FUL_BOSS_IDLE", modelType = "NPC_MODEL",
        viewDistance = 2700, screenX = 45, screenY = -4,
        rowHeight = 160,
    },
}
