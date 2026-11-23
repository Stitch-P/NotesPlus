-- Goals that are "finish all of these achievements": The Insane Reaper, Final Boss, Insane Final Boss. The game's own
-- achievement lists its requirements, each one another achievement with a live done flag, so the list, the names, the
-- descriptions, the progress and the reward all come from the game and stay right when it adds to them.

local ConfigReader = require("src/tracking/core/config_reader")
local Vars = require("src/tracking/core/vars")
local Objects = require("src/tracking/core/objects")
local findObjectID, objectDisplayName = Objects.findObjectID, Objects.objectDisplayName
local PetObjects = require("src/tracking/core/pet_objects")

local AchievementGoals = {}

AchievementGoals.GROUP = "Combat"
AchievementGoals.CAPES = "Completionist"
AchievementGoals.FARM = "Player Owned Farm" -- every breed, tracked under Gathering
AchievementGoals.LOGS = "Breeding logs" -- the two whole breeding logs
AchievementGoals.SKILLING = "Skilling" -- the skilling pet titles (the combat ones sit under Combat)
-- A real variable the note can carry; these goals read achievements, not a variable.
AchievementGoals.PLACEHOLDER_VAR = "RAND_REWARD_TOKENS"

local ORDER = { "insane-reaper", "final-boss", "insane-final-boss", "quest-cape", "master-quest-cape", "completionist-cape",
    "trimmed-completionist-cape", "master-completionist-cape", "master-trimmed-completionist-cape", "max-cape", "friends-with-max", "pof-manor", "pof-anachronia",
    "jack-of-blades", "jack-of-all-blades", "jack-of-trades", "jack-of-all-trades", "master-of-all" }
-- need: how many of the listed achievements the title asks for (all of them when left out).
local GOALS = {
    ["jack-of-blades"] = { sprite = 30108, achievement = "CHEEVO_COMBAT_SKILLPETS_TITLE_1", need = 3, noun = "pets", hint = "Collect 3 combat skilling pets." },
    ["jack-of-all-blades"] = { sprite = 30108, achievement = "CHEEVO_COMBAT_SKILLPETS_TITLE_2", noun = "pets", hint = "Collect all combat skilling pets." },
    ["jack-of-trades"] = { group = "Skilling", sprite = 30108, achievement = "CHEEVO_NONCOMBAT_SKILLPETS_TITLE_1", need = 5, noun = "pets", hint = "Collect 5 non-combat skilling pets." },
    ["jack-of-all-trades"] = { group = "Skilling", sprite = 30108, achievement = "CHEEVO_NONCOMBAT_SKILLPETS_TITLE_2", noun = "pets", hint = "Collect all non-combat skilling pets." },
    ["master-of-all"] = { group = "Skilling", sprite = 30108, achievement = "CHEEVO_INSANE_SKILLPETS_TITLE", noun = "pets", hint = "Collect all skilling pets." },
    ["insane-reaper"] = { achievement = "ITEMLOG_BOSSES_COMPLETE", hint = "Finish every boss collection log." },
    ["final-boss"] = { achievement = "CHEEVO_PVM_FINAL_BOSS", hint = "Finish every achievement listed." },
    ["insane-final-boss"] = { achievement = "CHEEVO_PVM_INSANE_FINAL_BOSS", hint = "Finish every achievement listed." },
    ["quest-cape"] = { group = "Completionist", quests = true, obj = "SKILLCAPE_QP", achievement = "CHEEVO_ALL_QUESTS", hint = "Complete every quest." },
    ["master-quest-cape"] = { group = "Completionist", obj = "SKILLCAPE_MQC", achievement = "CHEEVO_MQC_META", hint = "Finish every requirement listed." },
    ["completionist-cape"] = { group = "Completionist", obj = "SKILLCAPE_COMPLETIONIST", achievement = "CHEEVO_COMP_CAPE_META", hint = "Finish every achievement listed." },
    ["trimmed-completionist-cape"] = { group = "Completionist", obj = "SKILLCAPE_COMPLETIONIST_INSANE", achievement = "CHEEVO_TRIM_CAPE_META", hint = "Finish every achievement listed." },
    ["master-completionist-cape"] = { group = "Completionist", obj = "SKILLCAPE_COMPLETIONIST", achievement = "CHEEVO_120_ALL_COMP_CAPE_META", hint = "Finish both achievements listed." },
    ["max-cape"] = { group = "Completionist", label = "Master Max Cape", obj = "SKILLCAPE_120_ALL", objIds = { 53863 }, achievement = "CHEEVO_120_ALL_CAPE", hint = "Finish every requirement listed." },
    ["friends-with-max"] = { group = "Completionist", label = "Max Cape", obj = "SKILLCAPE_MAX", objIds = { 20747 }, achievement = "CHEEVO_FRIENDS_WITH_MAX", hint = "Finish every requirement listed." },
    ["pof-manor"] = { group = "Breeding logs", sprite = 30108, label = "Manor Farm breeding log", achievement = "CHEEVO_POF_BREED_ALL", hint = "Breed every animal in the Manor Farm log." },
    ["pof-anachronia"] = { group = "Breeding logs", sprite = 30108, label = "Anachronia breeding log", achievement = "CHEEVO_POF_BREED_ALL_DINO", hint = "Breed every animal in the Ranch Out of Time log." },
    ["master-trimmed-completionist-cape"] = { group = "Completionist", obj = "SKILLCAPE_COMPLETIONIST_INSANE", achievement = "CHEEVO_120_ALL_TRIM_COMP_CAPE_META", hint = "Finish both achievements listed." },
}

-- Player Owned Farm: one goal per animal type, made from the two breeding-log achievements' own lists (the "pof:" keys).
local FARM_LOGS = {
    { achievement = "CHEEVO_POF_BREED_ALL", name = "Manor Farm" },
    { achievement = "CHEEVO_POF_BREED_ALL_DINO", name = "Anachronia" },
}
local FARM_SPRITE = 30108
local dynamic, dynamicOrder

local function farmGoals()
    if dynamic then return dynamic end
    if not ConfigReader.Available() then return {} end
    dynamic, dynamicOrder = {}, {}
    for _, farm in ipairs(FARM_LOGS) do
        local achievement = ConfigReader.Achievement(farm.achievement)
        local requirements = achievement and ConfigReader.Field(achievement, "requirements")
        local list = requirements and ConfigReader.Field(requirements, "achievements")
        if type(list) == "table" or type(list) == "userdata" then
            for index = 1, #list do
                local child = ConfigReader.Field(list[index], "achievement")
                local configName = child and ConfigReader.Field(child, "configName")
                if type(configName) == "string" and configName ~= "" then
                    local animal = configName:upper():gsub("^CHEEVO_POF_BREED_", ""):gsub("_DINO$", ""):gsub("_", " ")
                    animal = animal:lower():gsub("(%a)(%w*)", function(a, b) return a:upper() .. b end)
                    -- The game's own breed list names the animal better ("Arcane apoterrasaur" -> Apoterrasaur (Arcane)).
                    local suffix = configName:upper():gsub("^CHEEVO_POF_BREED_", ""):gsub("_DINO$", "")
                    local enum = ConfigReader.Enum("CHEEVO_POF_" .. suffix .. "_BREED_LIST")
                    local first = enum and ConfigReader.EnumValue(enum, 0)
                    if type(first) == "string" then
                        local words = {}
                        for word in first:gmatch("%S+") do words[#words + 1] = word:sub(1, 1):upper() .. word:sub(2):lower() end
                        local last = words[#words] and words[#words]:lower()
                        if last == "apoterrasaur" and #words >= 2 then animal = "Apoterrasaur (" .. words[1] .. ")"
                        elseif last == "rex" and #words == 2 then animal = words[1]
                        elseif #words == 1 then animal = words[1] end
                    end
                    local key = "pof:" .. configName:lower()
                    dynamic[key] = { group = "Player Owned Farm", sprite = FARM_SPRITE, achievement = configName,
                        label = farm.name .. ": " .. animal, hint = "Breed every one in this animal's log." }
                    dynamicOrder[#dynamicOrder + 1] = key
                end
            end
        end
    end
    return dynamic
end

local function goalOf(key)
    if type(key) ~= "string" then return nil end
    return GOALS[key] or (key:sub(1, 4) == "pof:" and farmGoals()[key]) or nil
end

function AchievementGoals.isGoal(key) return GOALS[key] ~= nil or type(key) == "string" and key:sub(1, 4) == "pof:" end

-- An object by name, or the first of several names that exists.
local function objectId(names, ids)
    if type(names) == "string" then return findObjectID(names) end
    for _, name in ipairs(names or {}) do
        local id = findObjectID(name)
        if id then return id end
    end
    -- Known object ids, used when the config name above isn't found.
    for _, id in ipairs(ids or {}) do
        return id
    end
end

local function text(value) return type(value) == "string" and value ~= "" and value or nil end

local function achievementKey(achievement)
    local name = text(ConfigReader.Field(achievement, "configName"))
    if name then return name end
    local value = ConfigReader.Field(achievement, "id")
    if type(value) == "number" and value >= 0 and value % 1 == 0 then return value end
end

local function prettify(value)
    return (tostring(value):lower():gsub("^cheevo_", ""):gsub("_", " "):gsub("(%a)(%w*)", function(a, b) return a:upper() .. b end))
end

local function descriptionOf(achievement)
    local found
    for _, entry in ipairs(ConfigReader.Field(achievement, "descriptions") or {}) do
        local kind = ConfigReader.Field(entry, "type")
        local line = text(ConfigReader.Field(entry, "text"))
        if line and (found == nil or kind == 0) then found = line end
    end
    return found
end

local cache = {}

-- The breed variables an achievement tests (its "total" tests list them), by config name.
local function varList(achievement)
    local found, seen = {}, {}
    local requirements = achievement and ConfigReader.Field(achievement, "requirements")
    local totals = type(requirements) == "table" and requirements.varTotals
    for _, test in ipairs(type(totals) == "table" and totals or {}) do
        local vars = ConfigReader.Field(test, "vars")
        for _, var in ipairs(type(vars) == "table" and vars or {}) do
            local name = ConfigReader.Field(var, "configName")
            if type(name) == "string" and name ~= "" and not seen[name] then
                seen[name] = true
                found[#found + 1] = name
            end
        end
    end
    return found
end

-- POF_COLLECTION_BREED_OCULI_APOTERRASAUR_SHINY -> "Oculi Apoterrasaur (Shiny)".
local function varLabel(name)
    local base = name:upper():gsub("^POF_COLLECTION_BREED_", "")
    local shiny = base:match("_SHINY$") ~= nil
    base = base:gsub("_SHINY$", ""):gsub("_", " "):lower():gsub("(%a)(%w*)", function(a, b) return a:upper() .. b end)
    return shiny and (base .. " (Shiny)") or base
end

-- { key, label, reward, description, hint, children = { { name, description, achievementKey, sourceIndex } } }, or nil.
function AchievementGoals.info(key)
    local goal = goalOf(key)
    if not goal then return nil end
    if cache[key] ~= nil then return cache[key] or nil end
    if not ConfigReader.Available() then return nil end
    cache[key] = false
    local achievement = ConfigReader.Achievement(goal.achievement)
    if not achievement then return nil end
    local requirements = ConfigReader.Field(achievement, "requirements")
    local list = requirements and ConfigReader.Field(requirements, "achievements")
    if type(list) ~= "table" and type(list) ~= "userdata" then list = {} end
    local children = {}
    if #list == 0 then
        -- No sub-achievements: the achievement tests variables instead (one per breed), each done once it is set.
        for _, name in ipairs(varList(achievement)) do
            children[#children + 1] = { name = varLabel(name), var = name }
        end
    end
    for index = 1, #list do
        local item = list[index]
        local child = item and ConfigReader.Field(item, "achievement")
        if child then
            local name = text(ConfigReader.Field(child, "name")) or prettify(ConfigReader.Field(child, "configName") or index)
            children[#children + 1] = { name = name, achievementKey = achievementKey(child), sourceIndex = index }
        end
    end
    if #children == 0 then return nil end
    -- Pet titles: "Agility - Dojo Mojo" reads as "Dojo Mojo (Agility)", and each line shows the pet.
    if goal.noun == "pets" then
        for _, child in ipairs(children) do
            local pet, skill = PetObjects.split(child.name)
            if pet and skill then
                child.name, child.petName, child.petSkill = pet .. " (" .. skill .. ")", pet, skill:upper():gsub("%s+", "_")
            end
        end
    end
    -- Farm logs: the game lists each animal's breeds in an enum (CHEEVO_POF_<ANIMAL>_BREED_LIST), in the log's order.
    if goal.group == AchievementGoals.FARM then
        local animal = type(goal.achievement) == "string" and goal.achievement:upper():match("^CHEEVO_POF_BREED_(.+)$")
        animal = animal and animal:gsub("_DINO$", "")
        local enum = animal and ConfigReader.Enum("CHEEVO_POF_" .. animal .. "_BREED_LIST")
        if enum and not children[1].var then
            for index, child in ipairs(children) do
                local breed = ConfigReader.EnumValue(enum, (child.sourceIndex or index) - 1)
                if type(breed) == "string" and breed ~= "" and breed ~= "null" then
                    child.name, child.breed = breed, breed
                end
            end
        elseif enum then
            -- Breed variables name the same breeds in another word order ("Chinchompa Grey"): match by the words.
            local function words(text)
                local list = {}
                for word in text:lower():gmatch("%a+") do if word ~= "shiny" then list[#list + 1] = word end end
                table.sort(list)
                return table.concat(list, " ")
            end
            local byWords = {}
            for index = 0, 30 do
                local breed = ConfigReader.EnumValue(enum, index)
                if type(breed) == "string" and breed ~= "" and breed ~= "null" then
                    breed = breed:gsub("^%s+", ""):gsub("%s+$", "")
                    breed = breed:sub(1, 1):upper() .. breed:sub(2)
                    byWords[words(breed)] = breed
                end
            end
            for _, child in ipairs(children) do
                local breed = byWords[words(child.name)]
                if breed then
                    child.breed = breed
                    child.name = child.name:find("Shiny") and (breed .. " (Shiny)") or breed
                end
            end
        end
    end
    local info = {
        key = key, hint = goal.hint, children = children, group = goal.group or AchievementGoals.GROUP,
        label = goal.label or text(ConfigReader.Field(achievement, "name")) or prettify(goal.achievement),
        reward = text(ConfigReader.Field(achievement, "reward")), description = descriptionOf(achievement),
        objId = goal.obj and objectId(goal.obj, goal.objIds) or nil, quests = goal.quests == true,
        need = goal.need and math.min(goal.need, #children) or nil, noun = goal.noun,
    }
    cache[key] = info
    return info
end

-- A requirement's description, looked up only when it is hovered.
function AchievementGoals.describe(child)
    if child.description == nil then
        local achievement = child.achievementKey and ConfigReader.Achievement(child.achievementKey)
        child.description = descriptionOf(achievement) or false
    end
    return child.description or nil
end

-- A requirement's picture. The Quest Cape's are quests, so each one gets its quest's icon (read when first shown).
function AchievementGoals.childSprite(key, index)
    local info = AchievementGoals.info(key)
    local child = info and info.quests and info.children[index]
    if not child then return nil end
    if child.sprite == nil then
        child.sprite = false
        local achievement = child.achievementKey and ConfigReader.Achievement(child.achievementKey)
        local configName = ConfigReader.Field(achievement, "configName")
        local quest = type(configName) == "string" and ConfigReader.Quest(configName)
        local sprite = quest and ConfigReader.Field(quest, "iconID")
        if type(sprite) ~= "number" or sprite <= 0 then
            sprite = quest and ConfigReader.Param(quest, "QUEST_ICON_BIG")
        end
        if type(sprite) ~= "number" or sprite <= 0 then
            -- Config names often differ between the achievement and the quest, so fall back to the quest's name.
            local okQuests, Quests = pcall(require, "src/tracking/features/quests")
            local okName, byName = false, nil
            if okQuests and type(Quests) == "table" and Quests.spriteByName then
                okName, byName = pcall(Quests.spriteByName, child.name)
            end
            sprite = okName and byName or nil
        end
        if type(sprite) ~= "number" or sprite <= 0 then
            -- No quest sprite of its own: use the Quests category icon.
            local okSprites, Sprites = pcall(require, "src/tracking/core/sprites")
            local okCat, generic = false, nil
            if okSprites and type(Sprites) == "table" and Sprites.spriteByName then
                okCat, generic = pcall(Sprites.spriteByName, "ACHIEVEMENT_ICON_LORE_28PX_0")
            end
            sprite = okCat and generic or nil
        end
        if type(sprite) == "number" and sprite > 0 then child.sprite = sprite end
    end
    return child.sprite or nil
end

--These animals were missing and not displayed.
local BREED_OBJECTS = {
    RABBIT_BROWN = id.Obj.POF_ANIMAL_RABBIT_DUMMY,
    CHINCHOMPA_GREY = id.Obj.POF_ANIMAL_CHINCHOMPA,
    SPIDER_SPIRIT = id.Obj.POF_ANIMAL_SPIDER_DUMMY,
    ZYGOMITE_MORT_MYRE = id.Obj.POF_ANIMAL_ZYGOMITE_DUMMY,
    ZYGOMITE_MORCHELLA = id.Obj.POF_ANIMAL_ZYGOMITE_ZANARIAN_DUMMY,
    COW_BASIC = id.Obj.POF_ANIMAL_COW_DUMMY,
    YAK_FREMENNIK = id.Obj.POF_ANIMAL_YAK_DUMMY,
    DRAGON_GREEN = id.Obj.POF_ANIMAL_DRAGON_DUMMY,
    DRAGON_SHINY = id.Obj.POF_ANIMAL_DRAGON_SHINY_DUMMY,
}

function AchievementGoals.breedObject(variable)
    local suffix = type(variable) == "string" and variable:upper():match("^POF_COLLECTION_BREED_(.+)$")
    return suffix and BREED_OBJECTS[suffix] or nil
end

function AchievementGoals.childObject(key, index)
    local goal = goalOf(key)
    if goal and goal.noun == "pets" then
        local info = AchievementGoals.info(key)
        local child = info and info.children[index]
        return child and child.petName and PetObjects.find(child.petSkill, child.petName) or nil
    end
    if not goal or goal.group ~= AchievementGoals.FARM then return nil end
    local info = AchievementGoals.info(key)
    local child = info and info.children[index]
    if not child then return nil end
    if child.obj == nil then
        child.obj = false
        local suffixes = {}
        local achievement = child.achievementKey and ConfigReader.Achievement(child.achievementKey)
        local names = {}
        if child.var then names[#names + 1] = child.var end
        for _, name in ipairs(achievement and varList(achievement) or {}) do names[#names + 1] = name end
        for _, name in ipairs(names) do
            local suffix = name:upper():match("^POF_COLLECTION_BREED_(.+)$")
            if suffix then suffixes[#suffixes + 1] = suffix end
        end
        local configName = achievement and ConfigReader.Field(achievement, "configName")
        if type(configName) == "string" then
            local suffix = configName:upper():match("^CHEEVO_POF_BREED_(.+)$")
            if suffix then suffixes[#suffixes + 1] = suffix end
        end
        if child.breed then
            -- "Oculi apoterrasaur" -> OCULI_APOTERRASAUR (the plain breed is "..._BASIC" in the item names).
            local base = child.breed:upper():gsub("[^%w]+", "_")
            suffixes[#suffixes + 1] = base
            suffixes[#suffixes + 1] = base .. "_BASIC"
        end
        for _, suffix in ipairs(suffixes) do
            local found = BREED_OBJECTS[suffix] or findObjectID("POF_ANIMAL_" .. suffix .. "_UNCHECKED")
                or findObjectID("POF_ANIMAL_" .. suffix)
            if found then child.obj = found break end
        end
    end
    return child.obj or nil
end

-- Just the name, reward icon and size of a goal, for the picker: cheap, without reading every requirement's name.
local summaries = {}
function AchievementGoals.summary(key)
    local goal = goalOf(key)
    if not goal then return nil end
    if summaries[key] ~= nil then return summaries[key] or nil end
    if not ConfigReader.Available() then return nil end
    summaries[key] = false
    local achievement = ConfigReader.Achievement(goal.achievement)
    local requirements = achievement and ConfigReader.Field(achievement, "requirements")
    local list = requirements and ConfigReader.Field(requirements, "achievements")
    if type(list) ~= "table" and type(list) ~= "userdata" then list = {} end
    local count = #list
    if count == 0 then count = #varList(achievement) end
    if count == 0 then return nil end
    local result = { key = key, group = goal.group or AchievementGoals.GROUP, count = goal.need and math.min(goal.need, count) or count, hint = goal.hint,
        label = goal.label or text(ConfigReader.Field(achievement, "name")) or prettify(goal.achievement),
        description = descriptionOf(achievement), objId = goal.obj and objectId(goal.obj, goal.objIds) or nil,
        sprite = goal.sprite }
    if key:sub(1, 4) == "pof:" then
        -- A farm animal shows its own animal item (like the urns), not the shared farm sprite.
        local obj = AchievementGoals.childObject(key, 1)
        if obj then result.objId, result.sprite = obj, nil end
    end
    summaries[key] = result
    return result
end

-- Which requirements are done. The lists can be hundreds long and the note list asks many times a second, so the answer is
-- kept until Expire() (called from the main loop every few seconds) clears it. { [index] = true/false/nil }.
local states = {}

local function readStates(key)
    local info = AchievementGoals.info(key)
    if not info then return nil end
    local kept = states[key]
    if kept then return kept.list end
    -- Read a little at a time by Pump(), so a list of hundreds never stalls one frame.
    kept = {list = {}, cursor = 1, info = info}
    states[key] = kept
    return kept.list
end

-- Reads up to `budget` requirements per call, for whichever goals are on screen; call once per frame.
local PUMP_BUDGET = 12
function AchievementGoals.Pump(budget)
    budget = budget or PUMP_BUDGET
    for key, kept in pairs(states) do
        local children = kept.info.children
        if budget > 0 and kept.cursor <= #children then
            local achievement = ConfigReader.Achievement(goalOf(key).achievement)
            local requirements = ConfigReader.Field(achievement, "requirements")
            local list = requirements and ConfigReader.Field(requirements, "achievements")
            if type(list) ~= "table" and type(list) ~= "userdata" then list = nil end
            while budget > 0 and kept.cursor <= #children do
                local index = kept.cursor
                kept.cursor = index + 1
                budget = budget - 1
                local varChild = children[index].var
                if varChild then
                    local entry = Vars.resolveVar(varChild)
                    local value = entry and Vars.readEntry(entry)
                    if type(value) == "number" then kept.list[index] = value > 0 end
                elseif list then
                    local child = children[index]
                    local item = ConfigReader.Field(list, child.sourceIndex)
                    local current = ConfigReader.Field(item, "achievement")
                    if child.achievementKey ~= nil and achievementKey(current) == child.achievementKey then
                        local ok, value = pcall(function() return item.isComplete end)
                        if ok and type(value) == "boolean" then kept.list[index] = value end
                    else
                        kept.list[index] = nil
                    end
                end
            end
        end
        if budget <= 0 then return end
    end
end

-- Whether requirement number `index` of the goal is done, or nil when the game can't say.
function AchievementGoals.isDone(key, index)
    local list = readStates(key)
    return list and list[index]
end

-- done, total (done is nil when none can be read).
function AchievementGoals.progress(key, includeSlots)
    local info = AchievementGoals.info(key)
    local list = info and readStates(key)
    if not list then return nil end
    local done, known = 0, 0
    local slots, keys = includeSlots and {} or nil, includeSlots and {} or nil
    for index = 1, #info.children do
        local state = list[index]
        if state ~= nil then known = known + 1; if state then done = done + 1 end end
        if slots then
            local child = info.children[index]
            local slotKey = child.achievementKey ~= nil and "achievement:" .. tostring(child.achievementKey)
                or child.var and "var:" .. child.var or "goal:" .. key .. ":" .. index
            if keys[slotKey] then slotKey = slotKey .. ":" .. index end
            keys[slotKey] = true
            slots[index] = {key = slotKey, label = child.name, complete = state}
        end
    end
    return known > 0 and done or nil, #info.children, slots
end

function AchievementGoals.options(group)
    local options = {}
    local keys = {}
    for _, key in ipairs(ORDER) do keys[#keys + 1] = key end
    for _, key in ipairs(keys) do
        local info = AchievementGoals.summary(key)
        if info and (group == nil or info.group == group) then
            options[#options + 1] = {
                kind = "goal", key = key, label = info.label, varName = AchievementGoals.PLACEHOLDER_VAR,
                defaultTarget = info.count, objId = info.objId,
                spriteName = info.sprite and ("#" .. info.sprite) or not info.objId and "AIF_BOSS_SLAYER_POINTS_ICON_SML" or nil,
                description = (info.description or info.hint or "Finish every achievement listed.")
                    .. " Ones you have finished drop off the list.",
            }
        end
    end
    return options
end

-- Player Owned Farm animals are groups of their own ("Manor Farm: Rabbit"); picking one lists its breeds, each with the
-- animal's picture, to choose from like a collection log. The prefix test needs no game data (saved notes load before it).
-- Notes made when each animal was a group of its own ("Manor Farm: Rabbit") are moved to the one farm group.
function AchievementGoals.isLegacyFarmGroup(name)
    return type(name) == "string" and (name:sub(1, 12) == "Manor Farm: " or name:sub(1, 11) == "Anachronia:")
end

function AchievementGoals.isBreedKey(key)
    return type(key) == "string" and key:match("^pof%-breed:pof_collection_breed_") ~= nil
end

-- The animals of the farm sub-type ("Manor Farm: Dragons"), in order.
function AchievementGoals.animals()
    farmGoals()
    local names = {}
    for _, key in ipairs(dynamicOrder or {}) do names[#names + 1] = { name = dynamic[key].label } end
    return names
end

local breedLists, randomBreedLists, breedPrerequisites = {}, {}, {}

function AchievementGoals.loadedFarmAnimals()
    if not dynamic then return nil end
    local animals = {}
    for _, key in ipairs(dynamicOrder or {}) do
        animals[#animals + 1] = {key = key, animal = dynamic[key].label, achievement = dynamic[key].achievement}
    end
    return animals
end

function AchievementGoals.randomBreeds(animal)
    local goal = dynamic and dynamic[animal.key]
    if not goal then return {} end
    local achievement = ConfigReader.Achievement(goal.achievement)
    local progress = ConfigReader.Field(achievement, "progress")
    if progress ~= nil and progress == AchievementProgressType.COMPLETE then return {} end
    if ConfigReader.Field(achievement, "prereqsComplete") ~= true then return {} end
    if randomBreedLists[animal.key] then return randomBreedLists[animal.key] end
    local info = AchievementGoals.info(animal.key)
    local options = {}
    for _, child in ipairs(info and info.children or {}) do
        local variable = child.var
        if not variable and child.achievementKey ~= nil then
            variable = varList(ConfigReader.Achievement(child.achievementKey))[1]
        end
        if variable then
            breedPrerequisites[variable] = child.achievementKey
            options[#options + 1] = {kind = "breed", key = "pof-breed:" .. variable:lower(),
                label = child.name, varName = variable, defaultTarget = 1,
                description = "Track this animal, once it breeds, it'll be completed in your log."}
        end
    end
    randomBreedLists[animal.key] = options
    return options
end

function AchievementGoals.randomBreedAvailable(option)
    local achievement = breedPrerequisites[option.varName]
    return achievement == nil or ConfigReader.Field(ConfigReader.Achievement(achievement), "prereqsComplete") == true
end

-- The breeds of one animal, each with the animal's picture.
function AchievementGoals.breedOptions(animal)
    if not ConfigReader.Available() then return {} end
    farmGoals()
    if animal == nil then animal = dynamic[dynamicOrder and dynamicOrder[1]] and dynamic[dynamicOrder[1]].label end
    if breedLists[animal] then return breedLists[animal] end
    local options = {}
    for _, key in ipairs(dynamicOrder or {}) do
        if dynamic[key].label == animal then
            local info = AchievementGoals.info(key)
            for index, child in ipairs(info and info.children or {}) do
                local var = child.var
                if not var and child.achievementKey ~= nil then
                    var = varList(ConfigReader.Achievement(child.achievementKey))[1]
                end
                if var then
                    options[#options + 1] = {
                        kind = "breed", key = "pof-breed:" .. var:lower(), label = child.name,
                        varName = var, defaultTarget = 1,
                        objId = AchievementGoals.childObject(key, index),
                        description = "Track this animal, once it breeds, it'll be completed in your log.",
                    }
                end
            end
            break
        end
    end
    breedLists[animal] = options
    return options
end

-- Which animal a saved breed belongs to (to reopen a note on the right animal), or nil.
function AchievementGoals.animalOf(key)
    for _, animal in ipairs(AchievementGoals.animals()) do
        for _, option in ipairs(AchievementGoals.breedOptions(animal.name)) do
            if option.key == key then return animal.name end
        end
    end
end

-- Marks every list to be read again (gradually); the answers already known stay until replaced.
-- Called every few seconds (EXPIRE_STEP); long lists (the capes) are only re-read every few minutes, short ones every minute.
local EXPIRE_STEP, SHORT_SECONDS, LONG_SECONDS, LONG_COUNT = 4, 60, 300, 100
function AchievementGoals.Expire()
    for _, kept in pairs(states) do
        kept.age = (kept.age or 0) + EXPIRE_STEP
        local interval = #kept.info.children > LONG_COUNT and LONG_SECONDS or SHORT_SECONDS
        if kept.age >= interval then kept.age = 0; kept.cursor = 1 end
    end
end

function AchievementGoals.Clear() cache, states, summaries, breedLists, randomBreedLists, breedPrerequisites = {}, {}, {}, {}, {}, {} end

return { AchievementGoals = AchievementGoals }
