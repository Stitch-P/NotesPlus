-- Which kill counters and drops the Bossing type offers for each boss.

local constants_m = require("src/tracking/constants")
local ITEMLOG_PREFIX, KILLS_PREFIX = constants_m.ITEMLOG_PREFIX, constants_m.KILLS_PREFIX
local objects_m = require("src/tracking/core/objects")
local findObjectID, objectDisplayName = objects_m.findObjectID, objects_m.objectDisplayName
local vars_m = require("src/tracking/core/vars")
local resolveVar = vars_m.resolveVar
local bosses_m = require("src/tracking/data/bosses")
local BOSSES, HIDDEN_ITEMS, OBJ_PAIR_OVERRIDES = bosses_m.BOSSES, bosses_m.HIDDEN_ITEMS, bosses_m.OBJ_PAIR_OVERRIDES
local catalog_m = require("src/tracking/data/catalog")
local CATALOG = catalog_m.CATALOG
local icons_m = require("src/tracking/features/icons")
local isExcluded = icons_m.isExcluded
local BossSource = require("src/tracking/core/boss_source")
local SlayerTaskSource = require("src/tracking/core/slayer_task_source")
local ConfigReader = require("src/tracking/core/config_reader")
local ModelPresets = require("src/tracking/core/model_presets")
local BossModelPresets = require("src/tracking/data/boss_model_presets")
local Timers = require("src/tracking/features/boss_timers")

local bossList = {}

-- Enrage and kill-streak records per boss: { label, variable, highest the game allows (nil: no known cap) }.
-- Enrage variables hold the percentage itself (4000 = 4,000%).
local RECORDS = {
    ["Telos"] = {
        { "Highest enrage", "GWD2_SOLO_HIGHEST_ENRAGE", 4000 }, { "Current enrage", "GWD2_SOLO_CURRENT_ENRAGE", 4000 },
        { "Highest kill streak", "GWD2_SOLO_HIGHEST_STREAK", 200 }, { "Current kill streak", "GWD2_SOLO_CURRENT_STREAK", 200 },
    },
    ["Arch-Glacor"] = {
        { "Highest enrage", "EGWD_WEN_BOSS_HIGHEST_ENRAGE", 4000 }, { "Current enrage", "EGWD_WEN_BOSS_CURRENT_ENRAGE", 4000 },
        { "Highest kill streak", "EGWD_WEN_BOSS_HIGHEST_STREAK", 200 }, { "Current kill streak", "EGWD_WEN_BOSS_CURRENT_STREAK", 200 },
    },
    ["Amascut"] = {
        { "Highest enrage", "AMASCUT_BOSS_HIGHEST_ENRAGE", 4000 },
    },
    ["Zamorak"] = {
        { "Highest enrage", "EGWD_ZAMORAK_BOSS_HIGHEST_ENRAGE_GROUP", 60000 },
        { "Highest enrage (solo)", "EGWD_ZAMORAK_BOSS_HIGHEST_ENRAGE_GROUP_SIZE_1", 60000 },
        { "Highest enrage (duo)", "EGWD_ZAMORAK_BOSS_HIGHEST_ENRAGE_GROUP_SIZE_2", 60000 },
        { "Highest enrage (trio)", "EGWD_ZAMORAK_BOSS_HIGHEST_ENRAGE_GROUP_SIZE_3", 60000 },
        { "Highest enrage (4 players)", "EGWD_ZAMORAK_BOSS_HIGHEST_ENRAGE_GROUP_SIZE_4", 60000 },
        { "Highest enrage (5 players)", "EGWD_ZAMORAK_BOSS_HIGHEST_ENRAGE_GROUP_SIZE_5", 60000 },
        { "Current enrage", "EGWD_ZAMORAK_BOSS_CURRENT_ENRAGE", 60000 },
    },
    ["The Ghrazi Blood Knights"] = {
        { "Highest enrage", "BLOOD_KNIGHT_BOSS_HIGHEST_ENRAGE" },
    },
}
local recordByVariable = {}
for _, list in pairs(RECORDS) do
    for _, row in ipairs(list) do
        recordByVariable[row[2]] = { label = row[1], max = row[3], enrage = row[2]:find("ENRAGE", 1, true) ~= nil }
    end
end

-- { label, max, enrage } for a record variable, or nil.
local function recordOf(variable)
    return type(variable) == "string" and recordByVariable[variable:upper()] or nil
end

local entries = nil
local indexNext = 1
local previewGroups
local modelAliases = {
    CHAOSELEMENTAL = "BSLAY_CHAOS_ELEMENTAL",
    GWD_ZILYANA = "BSLAY_ZILYANA",
    CORPBEAST = "BSLAY_CORP_BEAST",
    DAGANNOTHKINGS = "BSLAY_DAG_KINGS",
    GWD_GRAARDOR = "BSLAY_GRAARDOR",
    GIANTMOLE = "BSLAY_MOLE",
    GWD_KRIL = "BSLAY_KRIL",
    KALPHITEKING = "BSLAY_KALPHITE_KING",
    KALPHITEQUEEN = "BSLAY_KALPHITE_QUEEN",
    KINGBLACKDRAGON = "BSLAY_KBD",
    GWD_KREEARRA = "BSLAY_KREEARRA",
    MAZCAB_HOUND = "BSLAY_BEASTMASTER",
    GWD_NEX = "BSLAY_NEX",
    QUEENBLACKDRAGON = "BSLAY_QBD",
    BARROWSROTS = "BSLAY_ROTS",
    DINO_BOSS_DUO = "BSLAY_DINO_BOSS",
}
local groupModels = {
    ["Osseous"] = "BSLAY_REXKINGS_OSSEOUS",
    ["Sanctum of Rebirth"] = "BSLAY_RAID_REBIRTH1_SLAYER_MASTER_BOSS",
    ["TzHaar"] = "BSLAY_HARAKEN",
    ["The Ghrazi Blood Knights"] = "BSLAY_BLOOD_KNIGHT_BOSS",
}
local combatGroups = {
    dinoboss = {boss = "Raksha"},
    durzag = {boss = "Mazcab"},
    beastmasterdurzag = {boss = "Mazcab"},
    haraken = {boss = "TzHaar"},
    tzhaar = {boss = "TzHaar", variant = "BSLAY_JAD"},
    jad = {boss = "TzHaar", variant = "BSLAY_JAD"},
    tztokjad = {boss = "TzHaar", variant = "BSLAY_JAD"},
    yakamaru = {boss = "Mazcab", variant = "BSLAY_YAKAMARU"},
    croesus = {boss = "Croseus"},
    gateofelidinis = {boss = "Elidinis"},
    nakatra = {boss = "Sanctum of Rebirth"},
    nakatradevourereternal = {boss = "Sanctum of Rebirth"},
    kezalam = {boss = "Sanctum of Rebirth", variant = "BSLAY_RAID_REBIRTH1_BEAST_BOSS"},
    kezalamthewanderer = {boss = "Sanctum of Rebirth", variant = "BSLAY_RAID_REBIRTH1_BEAST_BOSS"},
    vermyx = {boss = "Sanctum of Rebirth", variant = "BSLAY_RAID_REBIRTH1_WYRM_BOSS"},
    vermyxbroodmother = {boss = "Sanctum of Rebirth", variant = "BSLAY_RAID_REBIRTH1_WYRM_BOSS"},
    sanctumguardian = {boss = "Temple of Aminishi", native = "BSLAY_DUNGEON_AMINISHI1", animation = "MTXBEACH_BOSS_IDLE"},
    masutatheascended = {boss = "Temple of Aminishi", native = "BSLAY_DUNGEON_AMINISHI2", animation = "HUMAN_ACTOR_COMBAT_ARMED_MAUL_IDLE"},
    seiryutheazureserpent = {boss = "Temple of Aminishi"},
    astellarn = {boss = "Dragonkin Laboratory", native = "BSLAY_DUNGEON_DRAGONFORT1", animation = "DUNGEON_WILDERNESS_ASTELLARN_IDLE"},
    veraklith = {boss = "Dragonkin Laboratory", native = "BSLAY_DUNGEON_DRAGONFORT2", animation = "BTW_KBD_2017_READY"},
    blackstonedragon = {boss = "Dragonkin Laboratory"},
    crassianleviathan = {boss = "The Shadow Reef", native = "BSLAY_DUNGEON_ULTHVEN1", animation = "DUNGEON_ULTHVEN_CRASSIAN_LEVIATHAN_IDLE"},
    taraketthenecromancer = {boss = "The Shadow Reef", native = "BSLAY_DUNGEON_ULTHVEN2", animation = "DOV_TARSHAK_STAGE_2_IDLE"},
    ambassador = {boss = "The Shadow Reef"},
}
local dungeonTimerModels = {
    AMINISHI1 = combatGroups.sanctumguardian,
    AMINISHI2 = combatGroups.masutatheascended,
    DRAGONFORT1 = combatGroups.astellarn,
    DRAGONFORT2 = combatGroups.veraklith,
    ULTHVEN1 = combatGroups.crassianleviathan,
    ULTHVEN2 = combatGroups.taraketthenecromancer,
}
local combatVariants = {
    {boss = "Sanctum of Rebirth", prefix = "CHEEVO_RAID_REBIRTH1_BEAST_BOSS_", variant = "BSLAY_RAID_REBIRTH1_BEAST_BOSS"},
    {boss = "Sanctum of Rebirth", prefix = "CHEEVO_RAID_REBIRTH1_WYRM_BOSS_", variant = "BSLAY_RAID_REBIRTH1_WYRM_BOSS"},
    {boss = "Temple of Aminishi", prefix = "CHEEVO_DUNGEON_AMINISHI1_", route = combatGroups.sanctumguardian},
    {boss = "Temple of Aminishi", prefix = "CHEEVO_DUNGEON_AMINISHI2_", route = combatGroups.masutatheascended},
    {boss = "Dragonkin Laboratory", prefix = "CHEEVO_DUNGEON_DRAGONFORT1_", route = combatGroups.astellarn},
    {boss = "Dragonkin Laboratory", prefix = "CHEEVO_DUNGEON_DRAGONFORT2_", route = combatGroups.veraklith},
    {boss = "The Shadow Reef", prefix = "CHEEVO_DUNGEON_ULTHVEN1_", route = combatGroups.crassianleviathan},
    {boss = "The Shadow Reef", prefix = "CHEEVO_DUNGEON_ULTHVEN2_", route = combatGroups.taraketthenecromancer},
    {boss = "The Shadow Reef", prefix = "CHEEVO_DUNGEON_ULTHVEN_BOSS1_", route = combatGroups.crassianleviathan},
    {boss = "The Shadow Reef", prefix = "CHEEVO_DUNGEON_ULTHVEN_BOSS2_", route = combatGroups.taraketthenecromancer},
}
local collectionRules = {
    MENAPHOS_SLAYER_LORE_BOOK_1 = {variable = "MENAPHOS_SLAYER_MAGISTER_JOURNAL", group = "Magister", threshold = 1},
    MENAPHOS_SLAYER_LORE_BOOK_2 = {variable = "MENAPHOS_SLAYER_MAGISTER_JOURNAL", group = "Magister", threshold = 2},
    MENAPHOS_SLAYER_LORE_BOOK_3 = {variable = "MENAPHOS_SLAYER_MAGISTER_JOURNAL", group = "Magister", threshold = 3},
    MENAPHOS_SLAYER_LORE_BOOK_4 = {variable = "MENAPHOS_SLAYER_MAGISTER_JOURNAL", group = "Magister", threshold = 4},
    MENAPHOS_SLAYER_LORE_BOOK_5 = {variable = "MENAPHOS_SLAYER_MAGISTER_JOURNAL", group = "Magister", threshold = 5},
}

local function norm(word)
    word = tostring(word):lower()
    if #word > 3 and word:sub(-1) == "s" and word:sub(-2) ~= "ss" then
        word = word:sub(1, -2)
    end
    return word
end

local function addWords(entry, set, text)
    for word in tostring(text or ""):gmatch("%w+") do
        set[norm(word)] = true
    end
    local count = 0
    for _ in pairs(entry.words) do count = count + 1 end
    entry.wordCount = count
end

local function prettify(suffix)
    return (suffix:lower():gsub("_", " "):gsub("(%a)(%w*)", function(a, b)
        return a:upper() .. b
    end))
end

local function newEntry(fields, internalText)
    local entry = fields
    entry.internal = {}
    entry.words = {}
    addWords(entry, entry.internal, internalText)
    for word in pairs(entry.internal) do entry.words[word] = true end
    addWords(entry, entry.words, "")
    return entry
end

local function buildEntries()
    entries = {}
    for _, row in ipairs(CATALOG) do
        local varId, suffix, objId = row[1], row[2], row[3]
        local override = OBJ_PAIR_OVERRIDES[suffix]
        if override then objId = findObjectID(override) or objId end
        local varName = ITEMLOG_PREFIX .. suffix
        if not HIDDEN_ITEMS[suffix] and not isExcluded(varName) then
            entries[#entries + 1] = newEntry({
                varName = varName,
                varId = varId,
                objId = (objId and objId > 0) and objId or nil,
                label = prettify(suffix),
            }, suffix)
        end
    end
end

local function indexStep()
    if not entries then buildEntries() end
    local budget = 30
    while indexNext <= #entries and budget > 0 do
        local entry = entries[indexNext]
        indexNext = indexNext + 1
        budget = budget - 1
        if entry.objId and not entry.custom then
            local ok, cfg = pcall(function() return config.Obj.FromID(entry.objId) end)
            if ok and cfg then
                local okName, name = pcall(function() return cfg.name end)
                if okName and type(name) == "string" and name ~= "" and name ~= "null" then
                    entry.label = name
                    addWords(entry, entry.words, name)
                end
                local okConfig, configName = pcall(function() return cfg.configName end)
                if okConfig and type(configName) == "string" then
                    if isExcluded(configName) then entry.excluded = true end
                    addWords(entry, entry.internal, configName)
                    addWords(entry, entry.words, configName)
                end
            end
        end
    end
end

for _, boss in ipairs(BOSSES) do bossList[#bossList + 1] = boss end
table.sort(bossList, function(a, b) return a.name:lower() < b.name:lower() end)

local function itemMatches(suffix, prefix)
    local mark = prefix:sub(1, 1)
    if mark == "=" then return suffix == prefix:sub(2) end
    if mark == "*" then return suffix:find(prefix:sub(2), 1, true) ~= nil end
    return suffix:sub(1, #prefix) == prefix
end

local function bossMatches(boss, suffix)
    for _, prefix in ipairs(boss.items or {}) do
        if itemMatches(suffix, prefix) then return true end
    end
    return false
end

local function plainName(name)
    return (tostring(name):lower():gsub("^the%s+", ""):gsub("[^%w]", ""))
end

-- The game's boss pages, paired with the bosses listed above: each page's items become extra options for its boss,
-- and a page no listed boss claims becomes a boss of its own.
local extended, sourceName = false, "snapshot"
local pageItems = {}   -- boss -> list of { varName, objId, suffix }

local reverseOverrides
local function suffixOf(objName)
    if not reverseOverrides then
        reverseOverrides = {}
        for suffix, name in pairs(OBJ_PAIR_OVERRIDES) do reverseOverrides[name:upper()] = suffix end
    end
    return reverseOverrides[objName] or objName
end

local function extendFromGame()
    if extended then return end
    extended = true
    local ok, pages = pcall(BossSource.Pages)
    if not ok or not pages then return end
    local byName = {}
    for _, boss in ipairs(bossList) do byName[plainName(boss.name)] = boss end
    local added = false
    for _, page in ipairs(pages) do
        local items = {}
        for _, item in ipairs(page.items) do
            local suffix = item.objName and suffixOf(item.objName)
            if suffix and not HIDDEN_ITEMS[suffix] then
                local varName = ITEMLOG_PREFIX .. suffix
                if resolveVar(varName) and not isExcluded(varName) then
                    items[#items + 1] = { varName = varName, objId = item.objId, suffix = suffix }
                end
            end
        end
        local best, bestVotes = byName[plainName(page.name)], 0
        if not best then
            local votes = {}
            for _, item in ipairs(items) do
                for _, boss in ipairs(bossList) do
                    if bossMatches(boss, item.suffix) then votes[boss] = (votes[boss] or 0) + 1 end
                end
            end
            for boss, count in pairs(votes) do
                if count > bestVotes then best, bestVotes = boss, count end
            end
        end
        if not best and #items > 0 then
            best = { name = page.name, items = {}, kills = {}, fromGame = true }
            local killVar = KILLS_PREFIX .. page.key
            if resolveVar(killVar) then best.kills = { { "Kill count", page.key } } end
            bossList[#bossList + 1] = best
            byName[plainName(page.name)] = best
            added = true
        end
        if best then
            pageItems[best] = pageItems[best] or {}
            for _, item in ipairs(items) do table.insert(pageItems[best], item) end
        end
    end
    if added then table.sort(bossList, function(a, b) return a.name:lower() < b.name:lower() end) end
    sourceName = "game"
end

local function groups()
    extendFromGame()
    return bossList
end

local function counterModel(variable, prefix)
    prefix = prefix or KILLS_PREFIX
    if type(variable) ~= "string" or variable:sub(1, #prefix) ~= prefix then return nil end
    local suffix = variable:sub(#prefix + 1):gsub("_HARDMODE$", ""):gsub("_SOLO$", ""):gsub("_HARD$", "")
    return modelAliases[suffix] or "BSLAY_" .. suffix
end

local function nativePreview(route)
    local variant = route.native
    local root = BossModelPresets[route.boss]
    if root and root.variants and root.variants[variant] then return ModelPresets.Preview(root, variant) end

    local info = SlayerTaskSource.BossModel(variant)
    if not info or not info.npc then return nil end
    local idle = route.animation
    local animation = idle and ConfigReader.Field(ConfigReader.Config("Seq", idle), "id")
    return {npc = info.npc, zoom = info.zoom, animation = animation}
end

local function groupModel(name)
    if not previewGroups then
        local records = SlayerTaskSource.Bosses()
        if not records then return nil end
        previewGroups = {}
        for _, record in pairs(records) do
            if record.name then previewGroups[plainName(record.name)] = record end
        end
    end
    return previewGroups[plainName(name)]
end

local function presetPreview(name, variant)
    return ModelPresets.Preview(BossModelPresets[name], variant)
end

local function previewModel(boss, option)
    if type(boss) ~= "table" or type(boss.name) ~= "string" then return nil end
    local variable = option and (option.varName or option.variable
        or option.savedTracking and option.savedTracking.variable)
    local timer = Timers.rowOf(variable)
    local route = timer and timer[1] == boss.name and dungeonTimerModels[timer[3]:gsub("_HARD$", "")]
    if route then return nativePreview(route) end
    if BossModelPresets[boss.name] ~= nil then
        local prefix = Timers.isVar(variable) and Timers.PREFIX or KILLS_PREFIX
        return presetPreview(boss.name, counterModel(variable, prefix))
    end
    local name
    -- Osseous shares a counter with the other Matriarchs, but has her own model.
    if boss.name == "Osseous" then name = groupModels[boss.name]
    else
        name = counterModel(variable) or groupModels[boss.name]
        if not name and boss.kills and boss.kills[1] then name = counterModel(KILLS_PREFIX .. boss.kills[1][2]) end
    end
    local info = name and SlayerTaskSource.BossModel(name) or groupModel(boss.name)
    if info and info.npc then return {npc = info.npc, zoom = info.zoom} end
    return nil
end

local function combatPreviewModel(boss, option)
    if type(boss) ~= "table" or type(boss.name) ~= "string" then return nil end
    local route = combatGroups[plainName(boss.name)]
    local name = route and route.boss or boss.name
    local variable = option and (option.varName or option.variable
        or option.savedTracking and option.savedTracking.variable)
    if type(variable) == "string" then
        for _, candidate in ipairs(combatVariants) do
            if candidate.boss == name and variable:sub(1, #candidate.prefix) == candidate.prefix then
                route = candidate.route or candidate
                break
            end
        end
    end
    local variant, native = route and route.variant, route and route.native
    if native then return nativePreview(route) end
    if BossModelPresets[name] ~= nil then return presetPreview(name, variant) end
    for presetName in pairs(BossModelPresets) do
        if plainName(presetName) == plainName(name) then return presetPreview(presetName, variant) end
    end
    return previewModel(boss)
end

local function bossOptions(boss)
    extendFromGame()
    local options = {}
    local petName = boss.pet or boss.pets and boss.pets[1]
    local petId = petName and findObjectID(petName) or nil

    for _, kill in ipairs(boss.kills or {}) do
        local varName = KILLS_PREFIX .. kill[2]
        if not isExcluded(varName) then
            options[#options + 1] = {
                label = kill[1], kind = "kills", varName = varName, objId = icons_m.bossPetIcon(varName) or petId,
            }
        end
    end

    -- Enrage and kill-streak records, after the kill counts.
    for _, row in ipairs(RECORDS[boss.name] or {}) do
        if resolveVar(row[2]) then
            local enrage = row[2]:find("ENRAGE", 1, true) ~= nil
            local current = row[1]:find("^Current") ~= nil
            options[#options + 1] = {
                label = row[1], kind = "record", varName = row[2], key = row[2], objId = petId, max = row[3], enrage = enrage,
                description = (current and "Your enrage / streak right now; it resets when it ends." or "Your best so far.")
                    :gsub("enrage / streak", enrage and "enrage" or "kill streak"),
            }
        end
    end

    -- Fastest kill times (BOSS_INSTANCE_SCORES_*), listed after the kill counts.
    for _, option in ipairs(Timers.optionsFor(boss.name, boss.kills)) do
        option.objId = petId
        options[#options + 1] = option
    end

    if not entries then buildEntries() end
    local seen = {}
    for _, entry in ipairs(entries) do
        if not entry.custom and not entry.excluded and not seen[entry.varName] then
            local suffix = entry.varName:sub(#ITEMLOG_PREFIX + 1)
            for _, prefix in ipairs(boss.items or {}) do
                local matches
                if prefix:sub(1, 1) == "=" then
                    matches = suffix == prefix:sub(2)
                elseif prefix:sub(1, 1) == "*" then
                    matches = suffix:find(prefix:sub(2), 1, true) ~= nil
                else
                    matches = suffix:sub(1, #prefix) == prefix
                end
                if matches then
                    seen[entry.varName] = true
                    options[#options + 1] = {
                        label = objectDisplayName(entry.objId) or entry.label, kind = "item",
                        varName = entry.varName, objId = entry.objId, target = 1,
                    }
                    break
                end
            end
        end
    end
    for _, item in ipairs(boss.trackedItems or {}) do
        local entry, varName = resolveVar(item.var)
        local key = item.key or varName
        if entry and not isExcluded(varName) and not seen[key] then
            seen[key] = true
            local object = icons_m.bossPetIcon(varName) or item.obj and findObjectID(item.obj) or nil
            options[#options + 1] = {
                label = item.label or objectDisplayName(object) or prettify(varName), kind = "item",
                varName = varName, key = key, objId = object, target = 1,
            }
        end
    end
    -- Boss pet: BPETS_<NAME>_UNLOCKED, if the game has such a variable.
    for _, pet in ipairs(boss.pets or (boss.pet and {boss.pet} or {})) do
        local base = pet:gsub("_PET_DROP$", ""):gsub("_DROP$", "")
        local varName = base .. "_UNLOCKED"
        if not seen[varName] and not isExcluded(varName) and resolveVar(varName) then
            seen[varName] = true
            local object = icons_m.bossPetIcon(varName) or findObjectID(pet)
            options[#options + 1] = {
                label = objectDisplayName(object) or "Boss pet", kind = "item", varName = varName,
                objId = object, target = 1,
            }
        end
    end

    -- Items the game lists on this boss's page that the lists above don't cover.
    local haveObj = {}
    for _, option in ipairs(options) do
        if option.kind == "item" and option.objId then haveObj[option.objId] = true end
    end
    for _, item in ipairs(pageItems[boss] or {}) do
        if not seen[item.varName] and not haveObj[item.objId] then
            seen[item.varName] = true
            haveObj[item.objId] = true
            options[#options + 1] = {
                label = objectDisplayName(item.objId) or prettify(item.suffix), kind = "item",
                varName = item.varName, objId = item.objId, target = 1,
            }
        end
    end

    return options
end

-- Stop reading display names (called if indexing keeps failing).
local function giveUpIndexing()
    indexNext = math.huge
end

local function resetIndexing()
    entries, indexNext = nil, 1
    previewGroups = nil
    ModelPresets.Clear()
    SlayerTaskSource.Clear()
end

return {
    bossList = bossList,
    recordOf = recordOf,
    groups = groups,
    source = function() extendFromGame(); return sourceName end,
    pageItemCount = function(boss) extendFromGame(); return #(pageItems[boss] or {}) end,
    indexStep = indexStep,
    bossOptions = bossOptions,
    previewModel = previewModel,
    combatPreviewModel = combatPreviewModel,
    giveUpIndexing = giveUpIndexing,
    resetIndexing = resetIndexing,
    collectionRule = function(key) return collectionRules[key] end,
}
