local Vars = require("src/tracking/core/vars")
local Sprites = require("src/tracking/core/sprites")
local Icons = require("src/tracking/features/icons")
local Bossing = require("src/tracking/features/bossing")
local Clues = require("src/tracking/features/clues").Clues
local Combat = require("src/tracking/features/combat").Combat
local Currencies = require("src/tracking/features/currencies")
local Skills = require("src/tracking/features/skills")
local Tasks = require("src/tracking/features/tasks").Tasks
local Quests = require("src/tracking/features/quests").Quests
local Mining = require("src/tracking/features/mining").Mining
local Production = require("src/tracking/features/production").Production
local Relics = require("src/tracking/features/relics").Relics
local Fort = require("src/tracking/features/fort").Fort
local Camp = require("src/tracking/features/camp").Camp
local Necromancy = require("src/tracking/features/necromancy").Necromancy
local Arch = require("src/tracking/features/archaeology").Archaeology
local Timers = require("src/tracking/features/boss_timers")
local Unlocks = require("src/tracking/features/unlocks").Unlocks
local ReaperCrew = require("src/tracking/features/reaper_crew").ReaperCrew
local Goals = require("src/tracking/features/achievement_goals").AchievementGoals
local Journal = require("src/tracking/features/journals")
local Raven = require("src/tracking/features/prif_raven").PrifRaven
local Recipes = require("src/tracking/features/recipe_shop").Recipes
local Cheevos = require("src/tracking/features/cheevos").Cheevos
local ModelPresets = require("src/tracking/core/model_presets")
local PetModelPresets = require("src/tracking/data/pet_model_presets")
local Floors = require("src/tracking/features/floors").Floors
local Scheduled = require("src/tracking/features/scheduled")
local Ports = require("src/tracking/features/ports").Ports
local Invention = require("src/tracking/features/invention").Invention
local SlayerTask = require("src/tracking/features/slayer_task").SlayerTask
local Slayer = require("src/tracking/features/slayer").Slayer
local Objects = require("src/tracking/core/objects")
local Registry = require("src/tracking/core/registry").Registry
local CollectionFormat = require("src/tracking/core/collection_format")
local Clock = require("src/tracking/core/game_clock")

local Tracking = {}
Tracking.MAX_COLLECTION_ITEMS = 60
Tracking.MAX_COLLECTION_EXPORT = 20000
Tracking.MAX_TRACKING_EXPORT = 30000
local categories = {"Bossing", "Clues", "Combat", "Currencies", "Gathering", "Invention", "Ports", "Production", "Quests", "Scheduled", "Skills", "Slayer", "Tasks", "Training", "Unlocks"}
local categorySet = {}
for _, name in ipairs(categories) do categorySet[name] = true end
local entryCache = {}
local optionCache = {}

-- Slayer drops work just like boss drops: log items you pick from a grid.
local function bossLike(category)
    return category == "Bossing" or category == "Slayer"
end

-- Production and Gathering both count new items from backpack readings, so they share the item-grid collection.
-- Training (finished urns) is counted exactly like Production: new items in the backpack.
local function isProd(category) return category == "Production" or category == "Training" end
local function counted(category) return isProd(category) or category == "Gathering" end
local function countedInfo(category, key)
    return category == "Gathering" and Mining.info(key) or isProd(category) and Production.info(key) or nil
end
local function countedPrefix(category) return category == "Gathering" and "gathering-selection:" or "production-selection:" end

function Tracking.IsSkillXP(category, group)
    return category == "Skills" and (type(group) == "table" and group.name or group) == "XP"
end

-- Skills notes that track levels or XP (not the Combat / Skilling Pets groups, which track pets).
local function skillLevels(category, group)
    return category == "Skills" and not Cheevos.isPetGroup(type(group) == "table" and group.name or group)
end
Tracking.IsSkillLevels = skillLevels

-- The Clues reward shop is offered under Unlocks (category "Clues"); it behaves like the old Clues collection.
local function clueShop(category, group)
    return category == "Unlocks" and (type(group) == "table" and group.name or group) == Clues.SHOP_CATEGORY
end

-- The variable a shop piece is tracked by: its currency balance, or (no balance to read) its ownership variable.
local function pieceVariable(piece)
    if piece.noBalance then return (piece.owned or ""):gsub(">=%d+$", "") end
    return piece.currencyVar or Clues.currencyVar
end

local function collectionKind(category, group)
    local name = type(group) == "table" and group.name or group
    if category == "Bossing" then return "boss" end
    -- The Memorial to Guthix is a list of goals even when it has no sections left (every engram handed in).
    if category == "Unlocks" and name == Cheevos.HOG_GROUP then return "cheevo" end
    if category == "Unlocks" and name == Cheevos.HOM_GROUP then return "cheevo" end
    if category == "Unlocks" and name == Cheevos.MUSIC_GROUP then return "cheevo" end
    if category == "Unlocks" and name == Cheevos.VARROCK_GROUP and not (type(group) == "table" and group.sub == Cheevos.KUDOS_SECTION) then return "cheevo" end
    if category == "Unlocks" and type(group) == "table" and group.sub then
        -- The base camp's stands are single notes, not lists.
        if name == Camp.GROUP and Camp.isStandSection(group.sub) then return nil end
        if name == Camp.GROUP and group.sub == Camp.FARM_SHOP then return "shop" end
        if Cheevos.isSection(name, group.sub) then return "cheevo" end
        if name == Relics.GROUP and group.sub == Clues.SHOP_SECTION then return "shop" end
    end
    if category == "Unlocks" and Unlocks.isShop(name) then return "shop" end
    if category == "Training" and Floors.isGroup(name) then return "floor" end
    if clueShop(category, group) then return "clue" end
    if category == "Unlocks" and name == Recipes.GROUP and type(group) == "table" and group.sub == Recipes.SECTION then return "recipe" end
    if category == "Clues" and Clues.isCollectionGroup(name) then return "clue" end
    if category == "Slayer" and Cheevos.isCodexGroup(name) then return "cheevo" end
    if category == "Slayer" and Slayer.hasItems(name) then return "boss" end
    if category == "Currencies" and name == nil then return "currency" end
    if category == "Skills" and Cheevos.isPetGroup(name) then return "cheevo" end
    if category == "Skills" and (name == nil or name == "Level" or name == "XP") then return "skill" end
    if Cheevos.isScrollGroup(category, name) then return "cheevo" end
    if category == "Ports" and name == "Trade Goods" then return "good" end
    if category == "Ports" and name == "Ports Resources" then return "resource" end
    if category == "Invention" and name == "Components" then return "component" end
    if category == "Invention" and name == "Research: Components" then return "research" end
    if category == "Gathering" and name == Goals.FARM then return "breed" end
    if category == "Gathering" and Arch.isGroup(name) then return "artefact" end
    if category == "Training" and Timers.isGroup(name) then return nil end
    if counted(category) and name ~= nil then return "production" end
    if category == "Unlocks" and name == Relics.GROUP then return "relic" end
    if category == "Unlocks" and name == Fort.GROUP then return "building" end
    if category == "Unlocks" and name == Camp.GROUP and type(group) == "table" and Camp.isSection(group.sub) then return "camp" end
end

-- Sections that hold one goal only (the Prifddinas ravens): the Track list is left out and the goal is simply the section.
function Tracking.IsSingleOption(category, group)
    if category == "Unlocks" and (type(group) == "table" and group.name or group) == Cheevos.MUSIC_GROUP then return true end
    if category == "Unlocks" and type(group) == "table" and group.name == Camp.GROUP and Camp.isStandSection(group.sub) then return true end
    if category == "Unlocks" and type(group) == "table" and group.name == Cheevos.VARROCK_GROUP and group.sub == Cheevos.KUDOS_SECTION then return true end
    return category == "Unlocks" and type(group) == "table" and group.name == Recipes.GROUP and group.sub == Recipes.RAVENS
end

function Tracking.IsCollection(category, group)
    return collectionKind(category, group) ~= nil
end

local function quantityKind(category, group, option)
    local kind = collectionKind(category, group)
    if bossLike(category) or category == "Clues" then
        local variable = option and (option.varName or option.variable or option.var)
        if not option and (kind == "boss" or kind == "clue")
            or option and not option.piece and not option.ownedVar and type(variable) == "string"
                and variable:upper():match("^ITEMLOG_ITEM_") then return "drop" end
    end
    if kind == "currency" or kind == "component" or kind == "good" or kind == "resource"
        or category == "Unlocks" and option and type(option.key) == "string" and (option.key:match("^camp%-res:") or option.key:match("^camp%-iai:"))
        or kind == "camp" and not option and type(group) == "table" and (group.sub == Camp.RESOURCES or group.sub == Camp.IAIA) then return "stock" end
end

function Tracking.CollectionHint(category, group, option)
    local kind = quantityKind(category, group, option)
    if kind == "drop" then return "Leave targets blank to count one lifetime drop. Enter a number to count new drops from now" end
    if kind == "stock" and type(group) == "table" and group.sub == Camp.IAIA then
        return "Enter the total you want to reach. What you already have counts towards it."
    end
    if kind == "stock" then return "Leave targets blank to count one you already have. Enter a number to track an increase from your current quantity." end
end

function Tracking.CollectionNames(category, group)
    local kind = collectionKind(category, group)
    if kind == "skill" then return "skill", "skills" end
    if kind == "good" then return "trade good", "trade goods" end
    if kind == "resource" then return "resource", "resources" end
    if kind == "research" then return "research unlock", "research unlocks" end
    if kind == "component" then return "component", "components" end
    if kind == "production" then return "item", "items" end
    if kind == "relic" then return "relic", "relics" end
    if kind == "recipe" then return "recipe", "recipes" end
    if kind == "cheevo" and category == "Skills" then return "pet", "pets" end
    if kind == "cheevo" and (type(group) == "table" and group.name or group) == Cheevos.HOG_GROUP then
        if type(group) == "table" and group.sub == Cheevos.HOG_ENGRAMS then return "engram", "engrams" end
        return "passive effect", "passive effects"
    end
    if kind == "cheevo" and (type(group) == "table" and group.name or group) == Cheevos.HOM_GROUP then return "bot", "bots" end
    if kind == "cheevo" and (type(group) == "table" and group.name or group) == Cheevos.MUSIC_GROUP then return "track", "tracks" end
    if kind == "cheevo" and (type(group) == "table" and group.name or group) == Cheevos.TITLES_GROUP then return "title", "titles" end
    if kind == "cheevo" and Cheevos.isScrollGroup(category, type(group) == "table" and group.name or group) then return "scroll", "scrolls" end
    if kind == "cheevo" and Cheevos.isStatueGroup(type(group) == "table" and group.name or group, type(group) == "table" and group.sub or nil) then
        return "skill", "skills"
    end
    if kind == "cheevo" and Cheevos.isCodexGroup(type(group) == "table" and group.name or group) then return "soul", "souls" end
    if kind == "cheevo" then return "achievement", "achievements" end
    if kind == "floor" then return "floor", "floors" end
    if kind == "breed" then return "breed", "breeds" end
    if kind == "artefact" then return "artefact", "artefacts" end
    if kind == "camp" then
        if type(group) == "table" and group.sub == Camp.BUILDINGS then return "building", "buildings" end
        if type(group) == "table" and group.sub == Camp.WORKERS then return "worker group", "worker groups" end
        return "resource", "resources"
    end
    if kind == "building" then return "building", "buildings" end
    if kind == "currency" then return "currency", "currencies" end
    if kind == "shop" then return "unlock", "unlocks" end
    return "item", "items"
end

function Tracking.CollectionFixedTarget(category, group)
    local kind = collectionKind(category, group)
    -- Base camp buildings aim for their next tier by themselves, so they take no target either.
    if kind == "camp" and type(group) == "table" and group.sub == Camp.BUILDINGS then return 1 end
    return (kind == "research" or kind == "relic" or kind == "breed" or kind == "artefact" or kind == "recipe" or kind == "floor" or kind == "cheevo") and 1 or nil
end

function Tracking.CollectionDefaultTarget(category, group)
    local kind = collectionKind(category, group)
    return (quantityKind(category, group) or kind == "skill" or kind == "clue" or kind == "shop") and "" or "1"
end

-- The reward shop item a tracked unlock is ({cost, currencyName, description}), or nil for anything else. Works for
-- shops that are sections of a group too (Anachronia > Dinosaur Farm).
function Tracking.ShopPiece(tracking)
    if type(tracking) ~= "table" or tracking.category ~= "Unlocks" or type(tracking.key) ~= "string" then return nil end
    local entry = Unlocks.entry(tracking.group, tracking.key)
    local piece = entry and entry.piece
    if not piece or not piece.cost then return nil end
    return { cost = piece.cost, currencyName = piece.currencyName, description = entry.description, owned = piece.owned }
end

function Tracking.CollectionTargetEditable(category, group, option)
    if option and (option.available == false or option.kind == "unavailable" or option.items) then return false end
    if option and Camp.isBuildingKey(option.key) then return false end
    local kind = collectionKind(category, group)
    if not kind or kind == "research" or kind == "relic" or kind == "breed" or kind == "artefact" or kind == "recipe" or kind == "floor" or kind == "cheevo" then return false end
    if kind == "boss" then
        local variable = option and (option.varName or option.variable)
        return type(variable) == "string" and (variable:upper():match("^ITEMLOG_ITEM_") ~= nil or Timers.isVar(variable))
    end
    return true
end

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function boundedText(value, maximum, empty)
    return type(value) == "string" and #value <= maximum and (empty or value ~= "")
        and not value:find("[%z\1-\31\127]")
end

local function integer(value)
    return finite(value) and value >= 0 and value <= 2147483647 and value % 1 == 0
end

local function escapedLength(value)
    local text = tostring(value or "")
    local _, count = text:gsub("[^A-Za-z0-9 _%.%-]", "")
    return #text + count * 2
end

-- Archaeology and Necromancy hold several kinds of goals under one group name: what a saved note is follows from its first goal.
local function refineKind(category, groupName, kind, items)
    if category ~= "Unlocks" or type(items) ~= "table" then return kind end
    local key = items[1] and items[1].key
    if (groupName == Relics.GROUP or groupName == Necromancy.GROUP or groupName == Cheevos.GIM_GROUP or groupName == Cheevos.HOG_GROUP
        or groupName == Cheevos.HOM_GROUP or groupName == Cheevos.MUSIC_GROUP or groupName == Cheevos.TITLES_GROUP or groupName == Cheevos.VARROCK_GROUP or groupName == Cheevos.PRIF_GROUP) and Cheevos.isKey(key) then return "cheevo" end
    if groupName == Relics.GROUP and type(key) == "string" and not Relics.info(key) and Unlocks.entry(groupName, key) then return "shop" end
    if groupName == Camp.GROUP and type(key) == "string" and not Camp.isKey(key) and Unlocks.entry(groupName, key) then return "shop" end
    return kind
end

function Tracking.Normalize(saved, collectionItem)
    if saved == nil then return nil end
    if type(saved) ~= "table" then return nil, "Invalid note tracking." end
    if collectionItem and saved.items ~= nil then return nil, "Item collections cannot be nested." end
    saved = Registry.migrate(saved)
    -- Achievement notes used to carry a stand-in variable; they are tracked by key alone.
    do
        local PLACEHOLDER = "RAND_REWARD_TOKENS"
        local function byKey(entry)
            return type(entry) == "table" and (Cheevos.isKey(entry.key) or Goals.isGoal(entry.key))
        end
        local function clean(entry)
            if entry.variable ~= PLACEHOLDER or not byKey(entry) then return entry end
            local moved = {}
            for key, value in pairs(entry) do moved[key] = value end
            moved.variable, moved.varId = "", nil
            return moved
        end
        local first = type(saved.items) == "table" and saved.items[1]
        if byKey(saved) or byKey(first) then
            if saved.variable == PLACEHOLDER or first and first.variable == PLACEHOLDER then
                local moved = {}
                for key, value in pairs(saved) do moved[key] = value end
                if saved.variable == PLACEHOLDER then moved.variable, moved.varId = "", nil end
                if type(saved.items) == "table" then
                    moved.items = {}
                    for index, item in ipairs(saved.items) do moved.items[index] = clean(item) end
                end
                saved = moved
            end
        end
    end
    -- Notes made while Archaeology was its own type now live under Unlocks.
    if saved.category == "Gathering" and type(saved.items) == "table" and Goals.isLegacyFarmGroup(saved.group) then
        local moved = {}
        for key, value in pairs(saved) do moved[key] = value end
        moved.group, moved.key, moved.items = Goals.FARM, "unlocks-selection:" .. Goals.FARM, {}
        for index, item in ipairs(saved.items) do
            local child = {}
            if type(item) == "table" then for key, value in pairs(item) do child[key] = value end end
            child.group = Goals.FARM
            moved.items[index] = child
        end
        saved = moved
    end
    -- The breeding logs moved from Gathering to Unlocks.
    if saved.category == "Gathering" and saved.group == Goals.LOGS then
        local moved = {}
        for key, value in pairs(saved) do moved[key] = value end
        moved.category = "Unlocks"
        saved = moved
    end
    -- The Heist reward shop is now "Dodgy Derek (Thieving)".
    if saved.category == "Unlocks" and saved.group == "Heist" then
        local renamed = {}
        for key, value in pairs(saved) do renamed[key] = value end
        renamed.group, renamed.key = "Dodgy Derek (Thieving)", "unlocks-selection:Dodgy Derek (Thieving)"
        if type(saved.items) == "table" then
            renamed.items = {}
            for index, item in ipairs(saved.items) do
                local child = {}
                if type(item) == "table" then for key, value in pairs(item) do child[key] = value end end
                child.group = renamed.group
                renamed.items[index] = child
            end
        end
        saved = renamed
    end
    -- The reward shop moved from the Clues type to Unlocks (Clues > Reward Shop).
    if Clues.isShopNote(saved) then
        local function move(note)
            local moved = {}
            for key, value in pairs(note) do moved[key] = value end
            moved.category, moved.group = "Unlocks", Clues.SHOP_CATEGORY
            return moved
        end
        local moved = move(saved)
        if type(saved.items) == "table" then
            moved.key = "clues-selection:" .. Clues.SHOP_CATEGORY
            moved.items = {}
            for index, item in ipairs(saved.items) do moved.items[index] = type(item) == "table" and move(item) or item end
        end
        saved = moved
    end
    -- The Anachronia Dinosaur Farm's upgrades moved into Anachronia (Unlocks > Anachronia > Dinosaur Farm).
    if saved.category == "Unlocks" and saved.group == "Anachronia Dinosaur Farm" then
        local function move(note)
            local moved = {}
            for key, value in pairs(note) do moved[key] = value end
            moved.group = Camp.GROUP
            return moved
        end
        local moved = move(saved)
        if type(saved.items) == "table" then
            moved.key = "unlocks-selection:" .. Camp.GROUP
            moved.items = {}
            for index, item in ipairs(saved.items) do moved.items[index] = type(item) == "table" and move(item) or item end
        end
        saved = moved
    end
    if saved.category == "Archaeology" then
        local moved = {}
        for key, value in pairs(saved) do moved[key] = value end
        moved.category, moved.group = "Unlocks", Relics.GROUP
        saved = moved
    end
    if not boundedText(saved.category, 40, false) or not finite(saved.target)
        or saved.target <= 0 or saved.target > 1e15 then return nil, "Invalid tracking target or category." end
    local copy = {category = saved.category, target = saved.target}
    for key, maximum in pairs({group = 120, key = 240, label = 300, variable = 160,
        ownedVar = 160, iconSprite = 160}) do
        local value = saved[key]
        if value ~= nil then
            if not boundedText(value, maximum, key == "variable") then return nil, "Invalid tracking " .. key .. "." end
            copy[key] = value
        end
    end
    if copy.category == "Skills" and copy.group == "Level" then copy.group = nil end
    if saved.skill ~= nil then
        if type(saved.skill) ~= "string" or not Skills.SKILL_BY_TYPE[saved.skill] then return nil, "Invalid tracked skill." end
        if saved.target % 1 ~= 0 then return nil, "Invalid tracked skill target." end
        if not Tracking.IsSkillXP(copy.category, copy.group) and saved.target > Skills.MaxLevel(saved.skill) then return nil, "Invalid tracked skill level." end
        copy.skill = saved.skill
    end
    copy.variable = copy.variable or ""
    if copy.category == "Scheduled" then
        local option = Scheduled.info(copy.key)
        if not option or copy.group ~= option.group or copy.variable ~= option.varName
            or (not option.userTarget and not option.dynamicTarget and copy.target ~= option.defaultTarget) or copy.target % 1 ~= 0
            or copy.skill or saved.items ~= nil or saved.vars ~= nil
            or saved.base ~= nil or saved.gained ~= nil or copy.ownedVar then
            return nil, "Invalid scheduled activity."
        end
    end
    local byKey = Cheevos.isKey(copy.key) or Goals.isGoal(copy.key)
        or type(saved.items) == "table" and type(saved.items[1]) == "table" and (Cheevos.isKey(saved.items[1].key) or Goals.isGoal(saved.items[1].key))
    if not copy.skill and copy.variable == "" and not byKey and copy.category ~= "Gathering" and not isProd(copy.category) and not (saved.items ~= nil and copy.category == "Skills") then
        return nil, "Tracking needs a variable or skill."
    end
    for _, key in ipairs({"varId", "iconObj"}) do
        if saved[key] ~= nil then
            local valid = key == "varId" and finite(saved[key]) and saved[key] >= -2147483648
                and saved[key] <= 2147483647 and saved[key] % 1 == 0 or key == "iconObj" and integer(saved[key])
            if not valid then return nil, "Invalid tracking " .. key .. "." end
            copy[key] = saved[key]
        end
    end
    if saved.gained ~= nil then
        if not finite(saved.gained) or saved.gained < 0 or saved.gained > 1e15 then return nil, "Invalid gathered amount." end
        copy.gained = saved.gained
    end
    if saved.base ~= nil then
        if not finite(saved.base) or saved.base < 0 or saved.base > 1e15 then return nil, "Invalid tracking starting value." end
        copy.base = saved.base
    end
    if saved.noIcon ~= nil then
        if type(saved.noIcon) ~= "boolean" then return nil, "Invalid tracking icon setting." end
        copy.noIcon = saved.noIcon
    end
    if saved.vars ~= nil then
        if type(saved.vars) ~= "table" or #saved.vars == 0 or #saved.vars > 100 then return nil, "Invalid tracked variables." end
        copy.vars = {}
        for index, name in ipairs(saved.vars) do
            if not boundedText(name, 160, false) then return nil, "Invalid tracked variable." end
            copy.vars[index] = name
        end
        for index in pairs(saved.vars) do
            if not integer(index) or index < 1 or index > #copy.vars then return nil, "Invalid tracked variables." end
        end
    end
    local rule = Bossing.collectionRule(copy.key)
    if rule and (copy.category ~= "Bossing" or copy.group ~= rule.group or copy.variable ~= rule.variable
        or copy.target ~= 1 or copy.base ~= nil or saved.items ~= nil or copy.skill or copy.vars or copy.ownedVar) then
        return nil, "Invalid collection item rule."
    end
    if saved.items ~= nil then
        local kind = refineKind(copy.category, copy.group, collectionKind(copy.category, copy.group), saved.items)
        if not kind and copy.category == "Unlocks" and copy.group == Camp.GROUP and type(saved.items) == "table"
            and saved.items[1] and Camp.isKey(saved.items[1].key) then kind = "camp" end
        if not kind and copy.category == "Unlocks" and copy.group == Recipes.GROUP and type(saved.items) == "table"
            and saved.items[1] and Recipes.isKey(saved.items[1].key) then kind = "recipe" end
        local components, currencies, boss = kind == "component", kind == "currency", kind == "boss"
        local skills, research = kind == "skill", kind == "research"
        local stock = kind == "good" or kind == "resource"
        local production = kind == "production"
        local relic = kind == "relic" or kind == "building" or kind == "breed" or kind == "camp" or kind == "artefact" or kind == "recipe" or kind == "floor" or kind == "cheevo"
        local building = kind == "building"
        local clues = kind == "clue" or kind == "shop"
        if not kind or type(saved.items) ~= "table" or #saved.items == 0
            or #saved.items > Tracking.MAX_COLLECTION_ITEMS or copy.target ~= #saved.items
            or copy.skill or copy.vars or copy.ownedVar or copy.base ~= nil
            or components and (copy.group ~= "Components" or copy.key ~= "invention-components")
            or currencies and (copy.group ~= nil or copy.key ~= "currency-selection")
            or skills and (copy.group ~= nil and copy.group ~= "XP" or copy.key ~= "skills-selection")
            or stock and copy.key ~= "ports-selection:" .. copy.group
            or research and copy.key ~= "invention-research:Components"
            or clues and copy.key ~= (kind == "shop" and "unlocks-selection:" or "clues-selection:") .. copy.group
            or relic and copy.key ~= "unlocks-selection:" .. tostring(copy.group)
            or production and copy.key ~= countedPrefix(copy.category) .. copy.group then
            return nil, "Invalid item collection."
        end
        copy.items = {}
        local seen, variables = {}, {}
        for index, item in ipairs(saved.items) do
            local child, message = Tracking.Normalize(item, true)
            if not child then return nil, message end
            local childRule = boss and Bossing.collectionRule(child.key)
            local researchOption = research and Invention.researchComponentOption(child.key)
            local clueOption = kind == "shop" and Unlocks.entry(copy.group, child.key)
                or clues and Clues.collectionOption(clueShop(copy.category, copy.group) and Clues.SHOP_GROUP or copy.group, child.key) or nil
            local cluePiece = clueOption and clueOption.piece
            local key = skills and child.skill or (childRule or research or production or relic or clues) and child.key or child.variable
            local sharedVariable = childRule ~= nil and childRule ~= false or researchOption ~= nil and researchOption ~= false or cluePiece ~= nil or kind == "cheevo"
            if child.category ~= copy.category or not skills and child.skill or child.vars
                or child.ownedVar and not cluePiece or child.base ~= nil and not quantityKind(copy.category, copy.group, child) or seen[key]
                or not skills and not production and variables[child.variable] ~= nil and not (sharedVariable and variables[child.variable])
                or (child.group ~= nil and child.group ~= copy.group)
                or skills and (not child.skill or child.variable ~= "" or child.key ~= child.skill or child.group ~= copy.group)
                or not skills and (child.key ~= nil and child.key ~= child.variable and not childRule and not research and not production and not relic and not clues)
                or clues and (not clueOption or child.target % 1 ~= 0
                    or child.variable ~= (cluePiece and pieceVariable(cluePiece) or clueOption.var)
                    or cluePiece and (child.base ~= nil or child.ownedVar ~= nil and child.ownedVar ~= cluePiece.owned))
                or production and (child.target % 1 ~= 0 or not countedInfo(copy.category, child.key))
                or kind == "relic" and (child.target ~= 1 or not Relics.info(child.key))
                or kind == "recipe" and (child.target ~= 1 or not Recipes.isKey(child.key))
                or kind == "cheevo" and (child.target ~= 1 or not Cheevos.isKey(child.key))
                or kind == "floor" and (child.target ~= 1 or not Floors.isKey(child.key))
                or kind == "breed" and (child.target ~= 1 or not Goals.isBreedKey(child.key))
                or kind == "artefact" and (child.target ~= 1 or not Arch.isKey(child.key))
                or kind == "camp" and (child.target % 1 ~= 0 or not Camp.isKey(child.key) or child.target > (Camp.maxTarget(child.key) or 0))
                or building and (child.target % 1 ~= 0 or child.target > 15 or not Fort.isKey(child.key))
                or components and (child.target % 1 ~= 0 or not Invention.materialOption(child.variable))
                or currencies and (child.target % 1 ~= 0 or not Currencies.isCurrency(child.variable))
                or stock and (child.target % 1 ~= 0 or not Ports.stockOption(copy.group, child.variable))
                or research and (not researchOption or child.variable ~= researchOption.varName or child.target ~= 1) then
                return nil, "Invalid collection item."
            end
            seen[key], variables[child.variable] = true, sharedVariable
            -- Shop ownership follows its known item key, including after sharing a collection.
            if cluePiece then child.ownedVar = cluePiece.owned end
            child.group, child.key = copy.group, key
            copy.items[index] = child
        end
        local extended, keyed, expanded = CollectionFormat.Shape(copy)
        local encodedSize = 0
        for _, child in ipairs(copy.items) do
            encodedSize = encodedSize + escapedLength(child.variable) + escapedLength(child.label)
                + escapedLength(child.iconSprite) + #tostring(child.iconObj or "")
                + #tostring(child.varId or "") + 7 + (extended and #tostring(child.target) + #tostring(child.base or "") + 2
                    or components and #tostring(child.target) + 1 or 0)
                + (keyed and escapedLength(child.key) + 1 or 0)
                + (expanded and escapedLength(child.skill) + 1 or 0)
            if encodedSize > Tracking.MAX_COLLECTION_EXPORT then return nil, "The item collection is too large." end
        end
        for index in pairs(saved.items) do
            if not integer(index) or index < 1 or index > #copy.items then return nil, "Invalid item collection." end
        end
        if copy.variable ~= copy.items[1].variable then return nil, "Invalid collection variable." end
    end
    return copy
end

local readVariable
function readVariable(name, variableID)
    -- "VAR>=N" is a tier variable: 1 once it reaches N, otherwise 0.
    local tierBase, tierMin = name:match("^(.-)>=(%d+)$")
    if tierBase then
        local tier = readVariable(tierBase)
        return tier ~= nil and (tier >= tonumber(tierMin) and 1 or 0) or nil
    end
    if Timers.isDG(name) then
        local value = Timers.readDG(name, readVariable)
        return finite(value) and value or nil
    end
    local key = name ~= "" and name or tostring(variableID or "")
    if key == "" then return nil end
    local entry = entryCache[key]
    if not entry then
        entry = Vars.resolveVar(key)
        if not entry and variableID then entry = Vars.resolveVar(tostring(variableID)) end
        entryCache[key] = entry
    end
    local value = Vars.readEntry(entry)
    return finite(value) and value or nil
end

local function sumVariables(names)
    local total = 0
    for _, name in ipairs(names) do
        local value = readVariable(name)
        if value == nil then return nil end
        total = total + value
    end
    return total
end

-- Reaper crew: one boss per kill-count variable list, done once any of them reaches 1. The bosses come from the game's
-- own list, so the note's list (Tracking.DerivedItems) and its count are built from it each time rather than saved.
local function isCrew(tracking) return tracking and tracking.category == "Unlocks" and tracking.key == ReaperCrew.KEY end

local function crewProgress(includeSlots)
    local bosses = ReaperCrew.bosses()
    if not bosses then return {current = nil, target = 1, fraction = 0, complete = false, owned = false, text = "Waiting for the Reaper boss list"} end
    local done, partial = 0, 0
    local slots = includeSlots and {} or nil
    for index, boss in ipairs(bosses) do
        local kills = sumVariables(boss.vars)
        if kills == nil then partial = partial + 1 elseif kills >= 1 then done = done + 1 end
        if slots then
            local slot = {key = "reaper:" .. tostring(boss.id), label = boss.name}
            if kills ~= nil then slot.complete = kills >= 1 end
            slots[index] = slot
        end
    end
    local total = #bosses
    if partial == total then
        return {current = nil, target = total, fraction = 0, complete = false, owned = false, slots = slots, text = "Waiting for your boss kills"}
    end
    local fraction = Vars.clamp(done / total, 0, 1)
    return {current = done, target = total, fraction = fraction, complete = done >= total, owned = false, slots = slots,
        text = Vars.withCommas(done) .. " / " .. Vars.withCommas(total) .. " bosses (" .. tostring(math.floor(fraction * 100)) .. "%)"
            .. (done >= total and " - Complete" or "")}
end

-- "Finish all of these achievements" notes (The Insane Reaper, Final Boss, Insane Final Boss): the game says which are done.
local function isGoal(tracking) return tracking and (tracking.category == "Unlocks" or tracking.category == "Gathering") and Goals.isGoal(tracking.key) end
local function isJournal(tracking) return tracking and tracking.category == "Unlocks" and Journal.isPage(tracking.key) end
local function isRaven(tracking) return tracking and tracking.category == "Unlocks" and tracking.key == Raven.KEY end
local function isScheduled(tracking) return tracking and tracking.category == "Scheduled" and Scheduled.isKey(tracking.key) end

local function goalProgress(key, includeSlots)
    local info = Goals.info(key)
    if not info then return {current = nil, target = 1, fraction = 0, complete = false, owned = false, text = "Waiting for the achievement list"} end
    local done, total, slots = Goals.progress(key, includeSlots)
    -- Titles that ask for some of the list (Jack of Trades: 5 of the 19 pets) are complete at that many.
    if info.need then total = info.need end
    if done == nil then return {current = nil, target = total, fraction = 0, complete = false, owned = false, slots = slots, text = "Waiting for your achievements"} end
    local fraction = Vars.clamp(done / total, 0, 1)
    local shown = math.min(done, total)
    return {current = shown, target = total, fraction = fraction, complete = done >= total, owned = false, slots = slots,
        text = Vars.withCommas(shown) .. " / " .. Vars.withCommas(total) .. " " .. (info.noun or "achievements")
            .. " (" .. tostring(math.floor(fraction * 100)) .. "%)"
            .. (done >= total and " - Complete" or "")}
end

local goalItems = {}
local crewItems
-- The bosses of a Reaper crew note, one per boss, with kills counted: { category, key, label, variable, vars, bossId, ... }.
function Tracking.DerivedItems(tracking)
    -- Floor notes whose floors fill whole themes list the themes ("Frozen: 1 - 11 (45% done)").
    if tracking and tracking.category == "Training" and Floors.isGroup(tracking.group) and type(tracking.items) == "table" then
        local keys = {}
        for _, child in ipairs(tracking.items) do keys[#keys + 1] = child.variable end
        local lines = Floors.summary(tracking.group, keys)
        if not lines then return nil end
        local items = {}
        for _, line in ipairs(lines) do
            items[#items + 1] = {category = "Training", group = tracking.group, key = line.key, label = line.prefix, variable = line.vars[1],
                target = #line.vars, floorVars = line.vars, floorPrefix = line.prefix, keepComplete = true}
        end
        return items
    end
    if isScheduled(tracking) then return Scheduled.items(tracking.key) end
    if isJournal(tracking) then return Journal.items(tracking.key) end
    if isGoal(tracking) then
        local info = Goals.info(tracking.key)
        if not info then return nil end
        if goalItems[tracking.key] and goalItems[tracking.key].source == info then return goalItems[tracking.key].list end
        local items = {}
        for index, child in ipairs(info.children) do
            items[#items + 1] = {category = "Unlocks", group = info.group, key = "goal:" .. tracking.key .. ":" .. index,
                label = child.name, variable = Goals.PLACEHOLDER_VAR, target = 1, goalKey = tracking.key, goalIndex = index,
                hideComplete = true}
        end
        goalItems[tracking.key] = {source = info, list = items}
        return items
    end
    if not isCrew(tracking) then return nil end
    local bosses = ReaperCrew.bosses()
    if not bosses then return nil end
    if crewItems and crewItems.source == bosses then return crewItems.list end
    local items = {}
    for _, boss in ipairs(bosses) do
        items[#items + 1] = {category = "Unlocks", group = ReaperCrew.GROUP, key = "reaper:" .. boss.id, label = boss.name,
            variable = boss.vars[1], vars = #boss.vars > 1 and boss.vars or nil, target = 1, bossId = boss.id,
            iconObj = boss.iconObj, iconSprite = not boss.iconObj and ReaperCrew.SPRITE or nil, hideComplete = true}
    end
    crewItems = {source = bosses, list = items}
    return items
end

-- The Reaper crew's reward as lines to show: { text, icon } with the skill icon (or the Reaper skull for the title).
function Tracking.CrewReward(tracking)
    local lines
    if isGoal(tracking) then
        local info = Goals.info(tracking.key)
        lines = info and ReaperCrew.parseReward(info.reward)
    elseif isCrew(tracking) then
        lines = ReaperCrew.reward()
    else
        return nil
    end
    if not lines then return nil end
    local result = {}
    for _, line in ipairs(lines) do
        local icon
        if line.skill then
            local ok, ref = pcall(function() return Skills.skillIconRef(Skills.SKILL_BY_TYPE[line.skill]) end)
            icon = ok and ref or nil
        elseif line.title then
            local info = isGoal(tracking) and Goals.info(tracking.key)
            if info and info.objId then icon = info.objId
            else
                local ok, ref = pcall(Tracking.Icon, {iconSprite = ReaperCrew.SPRITE}, true)
                icon = ok and ref or nil
            end
        end
        result[#result + 1] = {text = line.text, icon = icon, title = line.title, scale = line.skill == "PRAYER" and 1.4 or nil}
    end
    return result
end

-- A picture for a derived list entry (the Quest Cape's quests), or nil.
function Tracking.ItemSprite(item)
    if item and item.scheduleKey then return Scheduled.sprite(item) end
    if item and item.journalKey then return Journal.sprite(item) end
    if item and item.goalKey then return Goals.childSprite(item.goalKey, item.goalIndex) end
    return nil
end

-- The item picture of a derived list entry (a farm animal), or nil.
function Tracking.ItemObject(item)
    if item and item.scheduleKey then return Scheduled.object(item) end
    if item and item.journalKey then return Journal.object(item) end
    if item and item.goalKey then return Goals.childObject(item.goalKey, item.goalIndex) end
    return nil
end

-- Progress through the floors of one line of a floor note (a theme, or the other floors picked).
local function floorLine(item)
    local done, readable = 0, false
    for _, variable in ipairs(item.floorVars) do
        local value = readVariable(variable)
        if value ~= nil then readable = true; if value >= 1 then done = done + 1 end end
    end
    local total = #item.floorVars
    if not readable then return {current = nil, target = total, fraction = 0, complete = false, owned = false, text = "Waiting for your floors"} end
    local fraction = done / total
    return {current = done, target = total, fraction = fraction, complete = done >= total, owned = false,
        text = done >= total and "Complete" or math.floor(fraction * 100) .. "% done"}
end

function Tracking.ItemLabel(item)
    if item and item.floorVars then
        local progress = floorLine(item)
        local status = progress.current == nil and "" or progress.complete and " (Complete)" or " (" .. progress.text .. ")"
        return item.floorPrefix .. status, status
    end
    if item and item.scheduleKey then return Scheduled.label(item) end
    if item and item.journalKey then return Journal.label(item) end
    return item and item.label
end

function Tracking.BossCard(tracking)
    if tracking and tracking.scheduleKey then return Scheduled.card(tracking) end
    if tracking and tracking.journalKey then return Journal.card(tracking) end
    if tracking and type(tracking.key) == "string" and tracking.key:match("^arch%-relic:") then return Relics.card(tracking.key) end
    if tracking and type(tracking.key) == "string" and tracking.key:match("^fort:") then return Fort.card(tracking.key) end
    if tracking and Camp.isStandKey(tracking.key) then return Camp.standCard(tracking.key) end
    if tracking and Camp.isKey(tracking.key) then return Camp.card(tracking.key, tracking.target) end
    if tracking and Necromancy.isKey(tracking.key) then return Necromancy.card(tracking.key) end
    if tracking and Cheevos.isKey(tracking.key) then return Cheevos.card(tracking.key) end
    if tracking and Arch.isKey(tracking.key) then return Arch.card(tracking.key) end
    if tracking and tracking.goalKey then
        local info = Goals.info(tracking.goalKey)
        local child = info and info.children[tracking.goalIndex]
        if not child then return nil end
        local function safe(value) return (tostring(value):gsub("<", "["):gsub(">", "]")) end
        local description = Goals.describe(child)
        local body = description and (safe(child.name) .. "<br>" .. safe(description)) or safe(child.name)
        return {key = "goal:" .. tracking.goalKey .. ":" .. tracking.goalIndex, body = body}
    end
    if not tracking or not tracking.bossId then return nil end
    return SlayerTask.BossCard(tracking.bossId)
end

-- The name shown for a Type (the saved name stays the same, so existing notes keep working).
local CATEGORY_LABELS = { Combat = "Combat Achievements" }
function Tracking.CategoryLabel(category) return CATEGORY_LABELS[category] or category end

function Tracking.Categories()
    local copy = {}
    for index, name in ipairs(categories) do copy[index] = name end
    return copy
end

function Tracking.TrainingGroups()
    local list = Production.urnGroups()
    for _, group in ipairs(Floors.groups()) do list[#list + 1] = group end
    for _, group in ipairs(Timers.dgGroups()) do list[#list + 1] = group end
    return list
end

function Tracking.Groups(category)
    local groups = category == "Bossing" and Bossing.groups() or category == "Combat" and Combat.groups()
        or category == "Clues" and Clues.groups() or category == "Tasks" and Tasks.areas()
        or category == "Ports" and (function() local list = Ports.groups(); list[#list + 1] = { name = Cheevos.SCROLLS_GROUP }; return list end)()
        or category == "Quests" and Quests.groups() or category == "Gathering" and Mining.groups() or category == "Production" and Production.groups() or category == "Training" and Tracking.TrainingGroups()
        or category == "Invention" and Invention.groups() or category == "Slayer" and Slayer.groups() or category == "Unlocks" and Unlocks.groups()
        or category == "Scheduled" and Scheduled.groups() or category == "Skills" and {{name = "Level"}, {name = "XP"}, {name = Cheevos.COMBAT_PETS}, {name = Cheevos.SKILLING_PETS}} or {}
    if category == "Gathering" and #Goals.options(Goals.LOGS) > 0 then
        local withFarm = {}
        for index, group in ipairs(groups) do withFarm[index] = group end
        local animals = Goals.animals()
        withFarm[#withFarm + 1] = { name = Goals.FARM, subs = #animals > 0 and animals or nil, subLabel = "Animal" }
        groups = withFarm
    end
    if category == "Gathering" then
        local withArch = {}
        for index, group in ipairs(groups) do withArch[index] = group end
        for _, faction in ipairs(Arch.groups()) do withArch[#withArch + 1] = faction end
        groups = withArch
    end
    if category == "Unlocks" then
        local withRelics = {}
        for index, group in ipairs(groups) do withRelics[index] = group end
        withRelics[#withRelics + 1] = { name = Relics.GROUP, subLabel = "Section", subs = { { name = "Relics" },
            { name = Cheevos.QUALIFICATIONS }, { name = Cheevos.RESEARCH }, { name = Cheevos.MYSTERIES }, { name = Cheevos.RESEARCHERS }, { name = Clues.SHOP_SECTION } } }
        withRelics[#withRelics + 1] = { name = Fort.GROUP }
        withRelics[#withRelics + 1] = { name = Clues.SHOP_CATEGORY, subs = { { name = Clues.SHOP_SECTION } }, subLabel = "Section" }
        -- Anachronia keeps what it already had (as "Unlocks") and gains the base camp.
        local existing
        for _, group in ipairs(withRelics) do if group.name == Camp.GROUP then existing = group end end
        if existing then
            existing.subs, existing.subLabel = Camp.sections(true), "Section"
        else
            existing = { name = Camp.GROUP, subs = Camp.sections(false), subLabel = "Section" }
            withRelics[#withRelics + 1] = existing
        end
        if Unlocks.shopOf(Camp.GROUP) then existing.subs[#existing.subs + 1] = { name = Camp.FARM_SHOP } end
        for _, entry in ipairs(withRelics) do
            if entry.name == Necromancy.GROUP then
                entry.subs, entry.subLabel = { { name = "Abilities" }, { name = Cheevos.KILI } }, "Section"
            end
            if entry.name == Recipes.GROUP then
                entry.subs = { { name = Recipes.RAVENS }, { name = Recipes.SECTION }, { name = Cheevos.PRIF_STATUE } }
                entry.subLabel = "Section"
            end
        end
        -- Once every engram is handed in only the passive effects are left, so there is no Section to choose.
        if Cheevos.hogEngramsDone() == true then
            withRelics[#withRelics + 1] = { name = Cheevos.HOG_GROUP }
        else
            withRelics[#withRelics + 1] = { name = Cheevos.HOG_GROUP, subLabel = "Section",
                subs = { { name = Cheevos.HOG_ENGRAMS }, { name = Cheevos.HOG_EFFECTS } } }
        end
        withRelics[#withRelics + 1] = { name = Cheevos.HOM_GROUP }
        -- Music: the one Music Maestro goal (how many of the tracks are unlocked, and how many are left).
        withRelics[#withRelics + 1] = { name = Cheevos.MUSIC_GROUP }
        withRelics[#withRelics + 1] = { name = Cheevos.TITLES_GROUP, subLabel = "Section",
            subs = { { name = Cheevos.TITLES_ACHIEVEMENTS }, { name = Cheevos.TITLES_REWARDS } } }
        withRelics[#withRelics + 1] = { name = Cheevos.VARROCK_GROUP, subLabel = "Section",
            subs = { { name = Cheevos.VARROCK_STATUE_SECTION }, { name = Cheevos.KUDOS_SECTION } } }
        -- Group Ironman achievements, only for Group Ironmen.
        if Cheevos.gimEnabled() == true then
            withRelics[#withRelics + 1] = { name = Cheevos.GIM_GROUP, subLabel = "Section",
                subs = { { name = Cheevos.GIM_TIERS }, { name = Cheevos.GIM_TASKS } } }
        end
        groups = withRelics
    end
    if category == "Slayer" then
        local withTask = {}
        for index, group in ipairs(groups) do withTask[index] = group end
        withTask[#withTask + 1] = { name = SlayerTask.GROUP }
        withTask[#withTask + 1] = { name = Cheevos.CODEX_GROUP }
        groups = withTask
    end
    for _, group in ipairs(groups) do group.label, group.key = group.name, group.name end
    -- Skills keep their own order: Level (the default), XP, then the pets.
    if category == "Skills" then return groups end
    -- Alphabetical, so a group is easy to find however many the game adds.
    local sorted = {}
    for index, group in ipairs(groups) do sorted[index] = group end
    table.sort(sorted, function(left, right)
        local a, b = tostring(left.name):lower(), tostring(right.name):lower()
        return a == b and tostring(left.name) < tostring(right.name) or a < b
    end)
    return sorted
end

local function groupFrom(category, group)
    if type(group) == "table" then return group end
    for _, entry in ipairs(Tracking.Groups(category)) do
        if entry.key == group or entry.name == group then return entry end
    end
    return nil
end

-- Reward shop pieces you don't own yet, as options of the Unlocks type.
function Tracking.ClueShopOptions()
    local options = {}
    for _, option in ipairs(Clues.sorted()) do
        if option.kind == "piece" and option.group == Clues.SHOP_GROUP then
            local owned = false
            if option.piece.owned then
                local value = readVariable(option.piece.owned)
                owned = value ~= nil and value > 0
            end
            if not owned then
                option.key = option.piece.owned or option.piece.key
                option.defaultTarget = option.piece.cost
                option.varName = option.piece.currencyVar or Clues.currencyVar
                option.objId = option.obj or option.piece.obj
                option.clueShop = true
                option.price, option.priceUnit = option.piece.cost, "points"
                options[#options + 1] = option
            end
        end
    end
    return options
end

-- Recipes you haven't unlocked yet.
function Tracking.RecipeOptions()
    local options = {}
    for _, option in ipairs(Recipes.options()) do
        local value = readVariable(option.varName)
        if not (value ~= nil and value > 0) then options[#options + 1] = option end
    end
    return options
end

function Tracking.Options(category, group)
    group = groupFrom(category, group)
    local cacheKey = category .. ":" .. (group and (group.name .. (group.sub and ("/" .. group.sub) or "")) or "")
    local options = {}
    if category == "Bossing" or category == "Combat" then
        options = group and (category == "Bossing" and Bossing.bossOptions(group) or Combat.options(group)) or {}
        for _, option in ipairs(options) do
            option.key = option.key or option.varName
            if category == "Combat" then option.description = Combat.description(option.varName) end
        end
    elseif category == "Clues" then
        for _, option in ipairs(Clues.sorted()) do
            -- Reward shop unlocks you already own are not offered again.
            local owned = false
            if option.kind == "piece" and option.piece.owned then
                local value = readVariable(option.piece.owned)
                owned = value ~= nil and value > 0
            end
            -- The reward shop is offered under Unlocks (it is listed here only for notes made before it moved).
            local shopPiece = option.kind == "piece"
            if not owned and (group and option.group == group.name or not group and not shopPiece) then options[#options + 1] = option end
        end
        for _, option in ipairs(options) do
            option.key = option.kind == "piece" and (option.piece.owned or option.piece.key)
                or option.kind == "item" and option.var
                or option.mode .. ":" .. table.concat(option.vars, ",")
            if option.kind == "piece" then option.defaultTarget = option.piece.cost end
            option.varName = option.var or option.piece and (option.piece.currencyVar or Clues.currencyVar)
            option.objId = option.obj or option.piece and option.piece.obj
        end
    elseif category == "Ports" then
        options = group and Cheevos.isScrollGroup(category, group.name) and Cheevos.options(Cheevos.SCROLLS_GROUP) or Ports.options(group)
    elseif category == "Invention" then
        options = Invention.options(group)
    elseif category == "Slayer" then
        options = group and group.name == SlayerTask.GROUP and SlayerTask.options()
            or group and Cheevos.isCodexGroup(group.name) and Cheevos.options(Cheevos.CODEX_GROUP) or Slayer.options(group)
    elseif category == "Tasks" then
        -- Tasks you've already finished aren't worth tracking, so leave them out.
        for _, option in ipairs(Tasks.options(group)) do
            local progress = Tracking.Read({category = "Tasks", key = option.key, variable = option.varName,
                vars = option.taskVars, target = option.steps})
            if not (progress and progress.complete) then options[#options + 1] = option end
        end
    elseif category == "Gathering" then
        options = group and group.name == Goals.FARM and Goals.breedOptions(group.sub)
            or group and Arch.isGroup(group.name) and Arch.options(group.name, group.sub) or Mining.options(group)
    elseif category == "Training" and group and Floors.isGroup(group.name) then
        options = Floors.options(group.name)
    elseif category == "Training" and group and Timers.isGroup(group.name) then
        options = Timers.dgOptions(group.name)
    elseif isProd(category) then
        options = Production.options(group)
    elseif category == "Unlocks" then
        options = group and group.name == Relics.GROUP and group.sub and group.sub ~= "Relics" and (Cheevos.isSection(group.name, group.sub) and Cheevos.options(group.sub)
                or group.sub == Clues.SHOP_SECTION and Unlocks.options({ name = Unlocks.shopOf(group.name) }))
            or group and group.name == Necromancy.GROUP and Cheevos.isSection(group.name, group.sub) and Cheevos.options(group.sub)
            or group and group.name == Cheevos.GIM_GROUP and Cheevos.options(group.sub or Cheevos.GIM_TIERS)
            or group and group.name == Cheevos.HOM_GROUP and Cheevos.options(Cheevos.HOM_BOTS)
            or group and group.name == Cheevos.MUSIC_GROUP and Cheevos.options(Cheevos.musicKey(group.sub))
            or group and group.name == Cheevos.TITLES_GROUP and Cheevos.options(Cheevos.titleKey(group.sub))
            or group and group.name == Cheevos.VARROCK_GROUP and group.sub == Cheevos.KUDOS_SECTION and { Cheevos.kudosOption() }
            or group and Cheevos.statueSection(group.name, group.sub) and Cheevos.options(Cheevos.statueSection(group.name, group.sub))
            or group and group.name == Cheevos.HOG_GROUP
                and Cheevos.options(group.sub or (Cheevos.hogEngramsDone() == true and Cheevos.HOG_EFFECTS or Cheevos.HOG_ENGRAMS))
            or group and group.name == Relics.GROUP and Relics.options() or group and group.name == Fort.GROUP and Fort.options()
            or group and group.name == Camp.GROUP and group.sub == Camp.FARM_SHOP and Unlocks.options({ name = Unlocks.shopOf(Camp.GROUP) })
            or group and group.name == Camp.GROUP and Camp.isStandSection(group.sub) and { Camp.standOption(group.sub) }
            or group and group.name == Camp.GROUP and Camp.isSection(group.sub) and Camp.options(group.sub)
            or group and group.name == Clues.SHOP_CATEGORY and Tracking.ClueShopOptions()
            or group and group.name == Recipes.GROUP and group.sub == Recipes.SECTION and Tracking.RecipeOptions() or Unlocks.options(group)
    elseif category == "Scheduled" then
        options = Scheduled.options(group)
    elseif category == "Quests" then
        -- Finished quests aren't worth tracking, so leave them out.
        for _, option in ipairs(Quests.options(group)) do
            if Quests.state(option.quest) ~= "done" then options[#options + 1] = option end
        end
    elseif category == "Currencies" then
        for _, item in ipairs(Currencies.sortedCurrencies()) do
            options[#options + 1] = {key = item.currency.var, label = item.label, kind = "currency", currency = item.currency}
        end
    elseif category == "Skills" and group and Cheevos.isPetGroup(group.name) then
        options = Cheevos.options(group.name)
    elseif category == "Skills" then
        for _, skill in ipairs(Skills.SKILLS) do
            options[#options + 1] = {key = skill.skill, label = skill.name, kind = "skill", skill = skill.skill, entry = skill}
        end
    end
    table.sort(options, function(a, b)
        if a.rank and b.rank and a.rank ~= b.rank then return a.rank < b.rank end
        local left, right = a.label:lower(), b.label:lower()
        return left == right and a.key < b.key or left < right
    end)
    for _, saved in ipairs(optionCache[cacheKey] or {}) do options[#options + 1] = saved end
    return options
end

function Tracking.DefaultTarget(category, group, option)
    if option and option.savedTracking and option.savedTracking.items then
        return tostring(not bossLike(category) and option.savedTracking.items[1].target or #option.savedTracking.items)
    end
    if quantityKind(category, group, option) then return "" end
    if option and option.defaultTarget then return tostring(option.defaultTarget) end
    if category == "Combat" then return "1" end
    if category == "Tasks" or category == "Quests" then return "1" end
    if category == "Ports" and option and option.defaultTarget then return tostring(option.defaultTarget) end
    return ""
end

-- The editor locks fixed targets; only automatic targets override the supplied value when building a goal.
function Tracking.TargetPolicy(category, option)
    if not option then return false end
    local kind = option.kind
    if kind == "scheduled" and option.userTarget then return false end
    if option.savedTracking and option.savedTracking.items then return true end
    if kind == "crew" or kind == "goal" or kind == "journal" or kind == "raven" or kind == "scheduled" or kind == "necro" or kind == "stand" then
        return true, option.defaultTarget
    end
    if category == "Combat" or category == "Quests" or kind == "slayertask" or kind == "blueprint" or kind == "area" then
        return true, 1
    end
    if kind == "relic" or kind == "breed" or kind == "artefact" or kind == "recipe" or kind == "floor" or kind == "cheevo" or category == "Tasks" and (option.steps or 1) <= 1 then return true end
    return false
end

local function maxSkillLevel(option)
    return Skills.MaxLevel(option and (option.skill or option.savedTracking and option.savedTracking.skill))
end

function Tracking.Hint(category, group, option)
    if category == "Scheduled" and option then return option.hint end
    if option and option.savedTracking and option.savedTracking.items then
        if collectionKind(category, option.savedTracking.group) == "research" then return "Each selected research entry is complete when unlocked." end
        local hint = Tracking.CollectionHint(category, option.savedTracking.group)
        if hint then return hint end
        if skillLevels(category, group) then return Tracking.IsSkillXP(category, group) and "Total XP to reach for each selected skill." or "Level to reach for each selected skill." end
        if Cheevos.isScrollGroup(category, option.savedTracking.group) then return "Each selected scroll is complete once all four of its pieces are found." end
        if category == "Ports" then return "Quantity to reach for each selected " .. Tracking.CollectionNames(category, option.savedTracking.group) .. "." end
        if category == "Clues" then return "Track each selected clue reward with its own target." end
        return "Collect one of every item in this boss collection log."
    end
    local hint = Tracking.CollectionHint(category, group, option)
    if hint then return hint end
    if skillLevels(category, group) then return Tracking.IsSkillXP(category, group) and "Total XP to reach, including XP you already have." or "Target level from 1 to " .. maxSkillLevel(option) .. "." end
    if category == "Combat" then return "Complete this combat achievement." end
    if option and option.kind == "blueprint" then return "Unlock this blueprint." end
    if option and option.kind == "area" then return "Complete this Slayer log." end
    if (category == "Ports" and option and option.kind == "good") or category == "Invention" then return "How many you want to track." end
    if category == "Ports" and (option and option.kind == "cheevo" or Cheevos.isScrollGroup(category, type(group) == "table" and group.name or group)) then
        return "Each selected scroll is complete once all four of its pieces are found."
    end
    if category == "Ports" then return "Total explored points needed to finish this region. Change the target for a smaller goal." end
    if option and option.kind == "slayertask" then return "Shows your current task, its monster and the kills left." end
    if isProd(category) and not (option and option.kind == "timer") then return "How many new ones to make. Banking them or taking them back out doesn't count." end
    if category == "Gathering" then return "How many new ones to gather. Moving them between your backpack, ore box and metal bank doesn't count." end
    if category == "Quests" then return "Finished or not. The note also says if you've started the quest." end
    if category == "Tasks" then
        if option and option.steps and option.steps > 1 then
            return "This task counts up to " .. option.steps .. ". Change the target if the game says otherwise."
        end
        return "Complete this area task."
    end
    if category == "Training" and option and option.kind == "timer" then
        return "A time to beat, like 45 or 12:30. Leave blank to beat your current best by one second. Complete once your best is at or under it."
    end
    if category == "Bossing" and option and option.kind == "timer" then
        return "A time to beat, like 45 or 1:05.4. Leave blank to beat your current best by one tick (0.6s). Complete once your best is at or under it."
    end
    if option and option.kind == "stand" then return "Nothing to set: the note shows what is stored and updates by itself." end
    if option and option.kind == "record" then
        local unit = option.enrage and "%" or ""
        return option.max and ("Up to " .. Vars.withCommas(option.max) .. unit .. ". Leave blank to aim for the highest possible.")
            or "Leave blank to aim one above your current best."
    end
    if option and option.kind == "kudos" then
        return "Kudos to reach, from 1 to " .. Cheevos.KUDOS_MAX .. ". Leave blank to aim for all " .. Cheevos.KUDOS_MAX .. "."
    end
    if category == "Bossing" and option and option.kind == "kills" then
        return "Leave blank to track your next kill. Enter a number for a total kill-count goal."
    end
    if category == "Bossing" and option and option.kind == "item" then
        return "Blank tracks one lifetime drop; a target counts new drops from now."
    end
    if category == "Clues" and option then
        if option.kind == "piece" then return "Points needed; owning this outfit piece completes the goal." end
        if option.kind == "item" then return "Leave targets blank to count one lifetime drop. Enter a number to count new drops from now" end
        if option.mode == "individual" then return "How many more clues to complete, starting from now." end
        return "Total clue completions to reach."
    end
    if category == "Currencies" then return "Current currency balance to reach." end
    if option and option.kind == "goal" then return "Finish each achievement listed. Ones you have finished drop off the list." end
    if option and option.kind == "crew" then return "Kill each Reaper boss once. Bosses you have killed drop off the list." end
    if option and option.kind == "journal" then return "Collect each entry on this journal page. Collected entries drop off the list." end
    if option and option.kind == "raven" then return "Spot 13 ravens. The next spawn date uses the game's UTC clock." end
    if category == "Unlocks" then return "The price in the shop's currency. Owning the unlock completes the goal." end
    return "Target number above zero."
end

local function sameOption(previous, category, option)
    if not previous or previous.category ~= category then return false end
    if category == "Skills" and option.savedTracking and previous.group ~= option.savedTracking.group then return false end
    if previous.items and not (option.savedTracking and option.savedTracking.items) then return false end
    if previous.key then return previous.key == option.key end
    if option.vars then
        local names = previous.vars or {previous.variable}
        if #names ~= #option.vars or (option.mode == "individual") ~= (previous.base ~= nil) then return false end
        for index, name in ipairs(names) do
            if name ~= option.vars[index] then return false end
        end
        return true
    end
    if option.piece then
        if option.piece.owned then return previous.ownedVar == option.piece.owned end
        return previous.key == option.key
    end
    return previous.variable == option.varName or (option.skill and previous.skill == option.skill)
        or (option.currency and previous.variable == option.currency.var)
end

-- What Notes+ itself would show for a single tracking (label and icon), or nil when it can't tell.
-- Shared notes leave out whatever matches this and the importer fills it in again.
function Tracking.Reference(tracking)
    if type(tracking) ~= "table" or tracking.items ~= nil or not categorySet[tracking.category] then return nil end
    local ok, built = pcall(function()
        local group = groupFrom(tracking.category, tracking.group)
        if tracking.group ~= nil and not group then return nil end
        -- A group with sections (Archaeology: Relics / Reward Shop...) is searched section by section.
        local candidates = {group}
        for _, sub in ipairs(group and group.subs or {}) do
            candidates[#candidates + 1] = {name = group.name, label = group.label, subs = group.subs,
                subLabel = group.subLabel, sub = sub.name}
        end
        for _, candidate in ipairs(candidates) do
            for _, entry in ipairs(Tracking.Options(tracking.category, candidate)) do
                if not entry.savedTracking and sameOption(tracking, tracking.category, entry) then
                    return (Tracking.Build(tracking.category, candidate, entry, tostring(tracking.target or 1)))
                end
            end
        end
    end)
    if not ok or type(built) ~= "table" or built.variable ~= tracking.variable or built.key ~= tracking.key then return nil end
    return {label = built.label, iconObj = built.iconObj, iconSprite = built.iconSprite, noIcon = built.noIcon}
end

function Tracking.Title(category, group, option, targetText)
    if type(option) ~= "table" then return nil end
    local saved = option.savedTracking
    local label = saved and saved.label or option.label
    if type(label) ~= "string" then return nil end
    if skillLevels(category, group) then
        local target = Vars.parseNumber(targetText)
        if Tracking.IsSkillXP(category, group) then
            return finite(target) and target > 0 and (label .. " " .. Vars.withCommas(target) .. " XP") or label
        end
        return finite(target) and target > 0 and (label .. " " .. tostring(target)) or label
    end
    if category == "Unlocks" and (option.kind == "building" or type(option.key) == "string" and option.key:match("^fort:")) then
        -- "Command Centre 3": the building and the tier being built.
        local tier = tonumber(targetText)
        return finite(tier) and tier > 0 and not label:match(" %d+$") and (label .. " " .. tostring(math.floor(tier))) or label
    end
    if category == "Unlocks" and type(option.key) == "string" and option.key:match("^camp%-bld:") then
        local tier = tonumber(targetText)
        return finite(tier) and tier > 0 and not label:match(" %d+$") and (label .. " " .. tostring(math.floor(tier))) or label
    end
    if category == "Quests" or category == "Gathering" or isProd(category) and option.kind ~= "timer" or category == "Unlocks" or category == "Scheduled" or option.kind == "slayertask" then return label end
    local name = saved and saved.group or type(group) == "table" and group.name or type(group) == "string" and group
    if not name then return label end
    -- Invention groups are split up to keep the dropdown short; the note only says "Research" or "Components".
    if category == "Invention" then name = Invention.titleName(name) end
    if not name then return label end
    local prefix = name .. ": "
    return saved and label:sub(1, #prefix) == prefix and label or prefix .. label
end

function Tracking.Build(category, group, option, targetText, previous)
    if not categorySet[category] or type(option) ~= "table" then return nil, "Choose what to track first." end
    group = groupFrom(category, group)
    if option.savedTracking and option.savedTracking.items and Tracking.IsCollection(category, group)
        and (not bossLike(category) or type(targetText) == "table") then
        return Tracking.BuildCollection(category, group, Tracking.CollectionSelection(option.savedTracking), targetText, previous or option.savedTracking)
    end
    local text = Vars.trim(targetText)
    -- Records accept "1,000%" as well as 1000.
    if option.kind == "record" then text = text:gsub("[%%,%s]", "") end
    local target = Vars.parseNumber(text)
    local rule = category == "Bossing" and Bossing.collectionRule(option.key)
    local kills = category == "Bossing" and option.kind == "kills"
    local quantity = quantityKind(category, group, option)
    local _, fixedTarget = Tracking.TargetPolicy(category, option)
    if option.kind == "timer" then
        -- A time to beat, saved in ticks; blank means one tick faster than the current best.
        target = Timers.parse(text, option.varName)
        if text ~= "" and not target then return nil, "Enter a time like 45 or 1:05.4." end
        if not target then
            local best = readVariable(option.varName)
            if not best then return nil, "Cannot read your current time yet. Enter a time to beat." end
            if best < 2 then return nil, "Enter a time to beat, like 1:05.4." end
            target = best - 1
        end
    end
    if option.savedTracking and option.savedTracking.items then target = #option.savedTracking.items end
    if option.kind == "record" and text == "" then
        -- Blank: the highest the game allows, or one above your current best when there is no known cap.
        if option.max then target = option.max
        else
            local best = readVariable(option.varName)
            if not finite(best) then return nil, "Cannot read your current value yet. Enter a target." end
            target = best + 1
        end
    end
    if option.kind == "record" and option.max and finite(target) and target > option.max then
        return nil, "Enter a target from 1 to " .. Vars.withCommas(option.max) .. (option.enrage and "%" or "") .. "."
    end
    if option.kind == "record" then
        -- (target set above)
    elseif rule then target = 1
    elseif kills and text == "" then target = 1
    elseif quantity and text == "" then target = 1
    elseif Camp.isBuildingKey(option.key) then target = Camp.nextTier(option.key)
    elseif fixedTarget ~= nil then target = fixedTarget
    elseif category == "Tasks" and text == "" then target = option.steps or 1
    elseif category == "Ports" and text == "" then target = option.defaultTarget
    elseif text == "" and option.kind == "item" then target = 1
    elseif text == "" and option.piece then target = option.defaultTarget or option.piece.cost end
    if option.kind == "kudos" and text == "" then target = Cheevos.KUDOS_MAX end
    if not finite(target) or target <= 0 or target > 1e15 then return nil, "Enter a target number above zero." end
    if option.kind == "kudos" and target > Cheevos.KUDOS_MAX then
        return nil, "Enter a kudos target from 1 to " .. Cheevos.KUDOS_MAX .. "."
    end
    if (quantity or category == "Skills" or category == "Clues" or category == "Currencies" or category == "Ports" or category == "Invention" or category == "Slayer" or category == "Gathering" or isProd(category) or category == "Unlocks" or category == "Scheduled") and target % 1 ~= 0 then
        return nil, "Enter a whole target number above zero."
    end
    if skillLevels(category, group) and not Tracking.IsSkillXP(category, group) and target > maxSkillLevel(option) then
        return nil, "Enter a target level from 1 to " .. maxSkillLevel(option) .. "."
    end
    if option.savedTracking then
        local saved, message = Tracking.Normalize(option.savedTracking)
        if not saved then return nil, message end
        saved.target = target
        return Tracking.Normalize(saved), Tracking.Title(category, group, option, target)
    end
    local tracking = {category = category, group = group and group.name or nil, key = option.key,
        label = option.label, variable = "", target = target}
    local label = Tracking.Title(category, group, option, target)
    if skillLevels(category, group) then
        tracking.skill = option.skill
    elseif category == "Gathering" or isProd(category) and option.kind ~= "timer" then
        -- Bars have no variable; the count comes from the metal bank.
        tracking.variable, tracking.iconObj = option.varName or "", option.objId
        if option.kind == "goal" then tracking.iconSprite = option.spriteName end
    elseif option.noVariable then
        -- Achievements are tracked by their key; there is no variable to read.
        tracking.variable, tracking.iconObj, tracking.iconSprite = "", option.objId, option.spriteName
    else
        local variable = option.varName or option.currency and option.currency.var
            or option.piece and pieceVariable(option.piece)
            or option.vars and option.vars[1] or option.var
        local entry, name, variableID = Vars.resolveVar(variable)
        if not entry then return nil, "The game does not know " .. tostring(variable) .. "." end
        tracking.variable, tracking.varId = name, variableID
        tracking.iconObj, tracking.iconSprite = option.objId, option.spriteName
        if option.currency then
            tracking.iconObj, tracking.iconSprite = option.currency.obj, option.currency.sprite
            if not tracking.iconObj and not tracking.iconSprite then tracking.noIcon = true end
        elseif option.piece then
            tracking.iconObj, tracking.ownedVar = option.piece.obj, option.piece.owned
            if option.piece.sprite then tracking.iconSprite = "#" .. option.piece.sprite end
        elseif option.kind == "item" and option.var then
            tracking.iconObj = option.obj
            if not tracking.iconObj then tracking.iconSprite = Sprites.CATEGORY_SPRITE_NAMES.Clues end
        elseif option.vars then
            -- For clue counting, we need to read the players current clue counts via Variables.
            tracking.iconObj = option.obj
            if not tracking.iconObj then tracking.iconSprite = Sprites.CATEGORY_SPRITE_NAMES.Clues end
            for _, variableName in ipairs(option.vars) do
                if not Vars.resolveVar(variableName) then return nil, "The game does not know " .. variableName .. "." end
            end
            if #option.vars > 1 then
                tracking.vars = {}
                for index, variableName in ipairs(option.vars) do tracking.vars[index] = variableName end
            end
        end
        if option.taskVars then
            tracking.vars = {}
            for index, variableName in ipairs(option.taskVars) do
                if not Vars.resolveVar(variableName) then return nil, "The game does not know " .. variableName .. "." end
                tracking.vars[index] = variableName
            end
        end
        if rule then
            tracking.base = nil
        elseif kills then
            if text == "" then
                if sameOption(previous, category, option) and previous.target == 1 and previous.base ~= nil then
                    tracking.base = previous.base
                else
                    local current = Vars.readEntry(entry)
                    if not finite(current) then return nil, "Cannot read your current count yet. Try again in a moment." end
                    tracking.base = current
                end
            end
        elseif quantity then
            -- Dream of Iaia amounts are a total to reach, not an increase from now.
            if text ~= "" and not Camp.isIaiaKey(option.key) then
                if sameOption(previous, category, option) and previous.base ~= nil then
                    tracking.base = previous.base
                else
                    local current = Camp.iaiaAmount(option.key, Vars.readEntry(entry))
                    if not finite(current) then return nil, "Cannot read your current count yet. Try again in a moment." end
                    tracking.base = current
                end
            end
        elseif option.kind == "timer" then
            -- Progress runs from the time you had when you set the goal down to the time to beat.
            local best = readVariable(option.varName)
            if sameOption(previous, category, option) and previous.base ~= nil then tracking.base = previous.base
            elseif finite(best) and best > 0 then tracking.base = best end
        elseif sameOption(previous, category, option) then
            tracking.base = previous.base
        elseif category == "Clues" and option.mode == "individual" then
            -- If we're typing a target we're assuming the player wants to track NEW drops, so let's try and nail that.
            local current
            if option.vars then current = sumVariables(option.vars)
            else current = Vars.readEntry(entry) end
            if not finite(current) then return nil, "Cannot read your current count yet. Try again in a moment." end
            tracking.base = current
        end
    end
    if category == "Gathering" or isProd(category) and option.kind ~= "timer" then
        tracking.gained = previous and sameOption(previous, category, option) and previous.gained or 0
    end
    local normalized, message = Tracking.Normalize(tracking)
    return normalized, normalized and label or message
end

function Tracking.IsComponents(category, group)
    return category == "Invention" and (type(group) == "table" and group.name or group) == "Components"
end

function Tracking.ComponentSelection(tracking)
    local selected, target, targets, mixed, common = {}, "", {}, false, nil
    if not tracking or tracking.category ~= "Invention" then return selected, target, targets end
    if tracking.items then
        for _, item in ipairs(tracking.items) do
            local key = item.key or item.variable
            local text = item.base == nil and item.target == 1 and "" or tostring(item.target)
            selected[key], targets[key] = true, text
            if common ~= nil and common ~= text then mixed = true end
            common = text
            target = text
        end
    elseif type(tracking.variable) == "string" and (Invention.materialOption(tracking.variable)
        or type(tracking.group) == "string" and tracking.group:match("^Components")
        or tracking.variable:match("^INVENT_MATERIAL_")) then
        local key = tracking.key or tracking.variable
        target = tracking.base == nil and tracking.target == 1 and "" or tostring(tracking.target)
        selected[key], targets[key] = true, target
    end
    return selected, mixed and "" or target, targets
end

local function collectionTargetText(target, option, fixed)
    if fixed then return "1" end
    if type(target) ~= "table" then return Vars.trim(target) end
    local value = target[option.key]
    if type(value) ~= "string" and type(value) ~= "number" then
        return nil, "Set a target for " .. tostring(option.label or "each selected item") .. "."
    end
    return Vars.trim(value)
end

local function collectionSelectedKeys(values, lookup, invalidOption, invalidValue, skillKeys)
    local selected = {}
    for key, value in pairs(values) do
        local name = type(value) == "table" and (value.key or value.varName or skillKeys and value.skill)
            or type(value) == "string" and value or value == true and key or nil
        if name ~= nil then
            if not lookup(name) then return nil, invalidOption end
            selected[name] = true
        elseif value ~= false then return nil, invalidValue end
    end
    return selected
end

local function collectionOptionLookup(options)
    local byKey = {}
    for _, option in ipairs(options) do byKey[option.key] = option end
    return function(key) return byKey[key] end
end

local function collectionTargetNumber(text, whole)
    local target = text == "" and 1 or Vars.parseNumber(text)
    if not finite(target) or target <= 0 or target > 1e15 or whole and target % 1 ~= 0 then
        return nil, "Enter a whole target number above zero."
    end
    return target
end

local function buildCollectionParent(category, group, key, label, items)
    local tracking, message = Tracking.Normalize({category = category, group = group and group.name,
        key = key, label = label, variable = items[1].variable, target = #items, noIcon = true, items = items})
    return tracking, tracking and Tracking.CollectionTitle(category, group, items) or message
end

function Tracking.BuildComponents(group, selectedOptions, targetText, previous)
    group = groupFrom("Invention", group)
    if not Tracking.IsComponents("Invention", group) or type(selectedOptions) ~= "table" then
        return nil, "Choose the components to track."
    end
    local text = type(targetText) ~= "table" and Vars.trim(targetText) or nil
    local selected, message = collectionSelectedKeys(selectedOptions, Invention.materialOption,
        "Choose valid components to track.", "Choose valid components to track.")
    if not selected then return nil, message end
    local previousItems = {}
    if previous and previous.category == "Invention" then
        for _, item in ipairs(previous.items or {previous}) do previousItems[item.key or item.variable] = item end
    end
    local items = {}
    for _, option in ipairs(Invention.options(group)) do
        if selected[option.key] then
            if #items >= Tracking.MAX_COLLECTION_ITEMS then
                return nil, "Choose up to " .. Tracking.MAX_COLLECTION_ITEMS .. " components."
            end
            local itemText, message = collectionTargetText(text or targetText, option)
            if not itemText then return nil, message end
            local target
            target, message = collectionTargetNumber(itemText, true)
            if not target then return nil, message end
            local child
            child, message = Tracking.Build("Invention", group, option, itemText, previousItems[option.key])
            if not child then return nil, message end
            items[#items + 1] = child
        end
    end
    if #items == 0 then return nil, "Select at least one component to track." end
    return buildCollectionParent("Invention", group, "invention-components",
        #items == 1 and items[1].label or "Components", items)
end

function Tracking.CollectionOptions(category, group, includeUnavailable)
    group = groupFrom(category, group)
    local result, seen = {}, {}
    local currentPages = category == "Bossing" and Vars.resolveVar("ITEMLOG_ITEM_SOLAK_GRIMOIRE_PAGES2") ~= nil
    for _, option in ipairs(Tracking.Options(category, group)) do
        local valid = bossLike(category) and option.kind == "item"
            or (category == "Clues" or clueShop(category, group)) and collectionKind(category, group) == "clue" and (option.kind == "item" or option.kind == "piece")
            or category == "Currencies" and option.kind == "currency"
            or Tracking.IsComponents(category, group) and option.kind == "material"
            or category == "Skills" and option.kind == "skill"
            or category == "Ports" and collectionKind(category, group) and option.kind == "good"
            or collectionKind(category, group) == "research" and option.kind == "blueprint"
            or collectionKind(category, group) == "relic" and option.kind == "relic"
            or collectionKind(category, group) == "recipe" and option.kind == "recipe"
            or collectionKind(category, group) == "cheevo" and option.kind == "cheevo"
            or collectionKind(category, group) == "floor" and option.kind == "floor"
            or collectionKind(category, group) == "shop" and option.kind == "piece"
            or collectionKind(category, group) == "breed" and option.kind == "breed"
            or collectionKind(category, group) == "artefact" and option.kind == "artefact"
            or collectionKind(category, group) == "building" and option.kind == "building"
            or collectionKind(category, group) == "camp" and option.kind == "camp"
            or counted(category) and collectionKind(category, group) and (option.kind == "production" or option.kind == "mining")
        local name = option.varName or option.currency and option.currency.var or option.skill
            or (option.kind == "production" or option.kind == "mining" or option.noVariable) and option.key or nil
        local key = option.key or name
        if valid and name and not seen[key]
            and not (name == "ITEMLOG_ITEM_SOLAK_GRIMOIRE_PAGES" and currentPages)
            and not (name == "ITEMLOG_ITEM_SOLAK_GRIMOIRE_PAGES2" and not currentPages) then
            seen[key] = true
            result[#result + 1] = option
        end
    end
    if includeUnavailable and category == "Bossing" and group then
        for _, item in ipairs(group.unavailableItems or {}) do
            result[#result + 1] = {key = "unavailable:" .. (item.obj or item.label),
                label = item.label, kind = "unavailable", available = false,
                objId = item.obj and Objects.findObjectID(item.obj) or nil,
                description = "Completion tracking is not available for this item."}
        end
    end
    return result
end

function Tracking.CollectionTitle(category, group, items, targetText)
    if items and #items == 1 then
        if type(targetText) == "table" then
            local item = items[1]
            targetText = targetText[item.key or item.skill or item.varName or item.variable]
        end
        if targetText == "" then targetText = nil end
        return Tracking.Title(category, group, items[1], targetText or items[1].target or Tracking.CollectionDefaultTarget(category, group))
    end
    if category == "Currencies" then return "Currencies" end
    if category == "Skills" and not skillLevels(category, group) then return type(group) == "table" and group.name or group end
    if category == "Skills" then return "Skills" end
    if category == "Clues" then return type(group) == "table" and group.name or group end
    if clueShop(category, group) then return Clues.SHOP_SECTION end
    if category == "Invention" then return collectionKind(category, group) == "research" and "Research: Components" or "Components" end
    local name = type(group) == "table" and group.name or group
    if collectionKind(category, group) == "breed" then return type(group) == "table" and group.sub or "Farm breeds" end
    if collectionKind(category, group) == "artefact" then return type(group) == "table" and group.sub or name end
    if collectionKind(category, group) == "camp" then return type(group) == "table" and group.sub or "Anachronia base camp" end
    if category == "Ports" or counted(category) and name then return name end
    if collectionKind(category, group) == "recipe" then return Recipes.SECTION end
    -- Lists of goals with sections are named after the section; those without (Hall of Memories) after the group.
    if collectionKind(category, group) == "cheevo" and name == Cheevos.VARROCK_GROUP then return "Statue of Dahmaroc" end
    if collectionKind(category, group) == "cheevo" and name == Cheevos.PRIF_GROUP then return Cheevos.PRIF_STATUE end
    if collectionKind(category, group) == "cheevo" then return type(group) == "table" and group.sub or name end
    if collectionKind(category, group) == "shop" then return (name == Relics.GROUP or name == Camp.GROUP) and Unlocks.shopOf(name) or name end
    if collectionKind(category, group) == "relic" then return "Archaeology relics" end
    if collectionKind(category, group) == "building" then return "Fort Forinthry buildings" end
    return name and name .. ": Collection items" or "Collection items"
end

local function loggedDrop(variable)
    return type(variable) == "string" and variable:upper():match("^ITEMLOG_ITEM_") ~= nil
end

function Tracking.CollectionSelection(tracking)
    if tracking and tracking.category == "Invention" and (Tracking.IsComponents(tracking.category, tracking.group)
        or not tracking.items and type(tracking.variable) == "string" and tracking.variable:match("^INVENT_MATERIAL_")) then
        return Tracking.ComponentSelection(tracking)
    end
    local category = tracking and tracking.category
    local selected, target, targets, common, mixed = {}, Tracking.CollectionDefaultTarget(category, tracking and tracking.group), {}, nil, false
    if not tracking then return selected, target, targets end
    local kind = refineKind(category, tracking.group, collectionKind(category, tracking.group), tracking.items)
    if not kind and category == "Unlocks" and tracking.group == Camp.GROUP and type(tracking.items) == "table"
        and tracking.items[1] and Camp.isKey(tracking.items[1].key) then kind = "camp" end
    if not kind and category == "Unlocks" and tracking.group == Recipes.GROUP and type(tracking.items) == "table"
        and tracking.items[1] and Recipes.isKey(tracking.items[1].key) then kind = "recipe" end
    if not kind and category == "Invention" and type(tracking.group) == "string"
        and tracking.group:match("^Research: Components") and Invention.researchComponentOption(tracking.key) then kind = "research" end
    if not kind and category == "Clues" and tracking.group == nil
        and Clues.collectionOption(nil, tracking.key or tracking.ownedVar or tracking.variable) then kind = "clue" end
    if not kind then return selected, target, targets end
    local function select(item)
        local key = item.key or item.skill or (category == "Clues" or clueShop(category, tracking.group)) and item.ownedVar or item.variable
        local text = quantityKind(category, tracking.group, item) and item.base == nil and item.target == 1 and ""
            or Timers.isVar(item.variable) and Timers.format(item.target, item.variable):gsub("^%-%-$", "")
            or bossLike(category) and not loggedDrop(item.variable) and "1" or tostring(item.target)
        selected[key], targets[key] = true, text
        if common ~= nil and common ~= text then mixed = true end
        common = text
        target = text
    end
    if tracking.items then
        for _, item in ipairs(tracking.items) do
            select(item)
        end
    elseif type(tracking.variable) == "string" then
        local valid = category ~= "Bossing" or tracking.variable:match("^ITEMLOG_ITEM_")
        if not valid then
            for _, option in ipairs(Tracking.CollectionOptions(category, tracking.group)) do
                if option.varName == tracking.variable and (tracking.key == nil or option.key == tracking.key) then
                    valid = true break
                end
            end
        end
        if valid then
            select(tracking)
        end
    end
    return selected, mixed and Tracking.CollectionDefaultTarget(category, tracking.group) or target, targets
end

local function buildAdditionalCollection(category, group, selectedOptions, targetText, previous)
    if type(selectedOptions) ~= "table" then return nil, "Choose what to track first." end
    local options = Tracking.CollectionOptions(category, group)
    local selected, message = collectionSelectedKeys(selectedOptions, collectionOptionLookup(options),
        "Choose valid tracking options.", "Choose valid tracking options.", true)
    if not selected then return nil, message end
    local previousItems = {}
    if previous and previous.category == category then
        for _, item in ipairs(previous.items or {previous}) do
            local key = item.key or item.ownedVar or item.variable
            if key then previousItems[key] = item end
        end
    end
    local items = {}
    for _, option in ipairs(options) do
        if selected[option.key] then
            if #items >= Tracking.MAX_COLLECTION_ITEMS then return nil, "Choose up to " .. Tracking.MAX_COLLECTION_ITEMS .. " items." end
            local text, message = collectionTargetText(targetText, option, Tracking.CollectionFixedTarget(category, group))
            if not text then return nil, message end
            if skillLevels(category, group) and text == "" then
                if Tracking.IsSkillXP(category, group) then return nil, "Enter a target XP for " .. option.label .. "." end
                return nil, "Enter a target level for " .. option.label .. " from 1 to " .. maxSkillLevel(option) .. "."
            end
            if text == "" and category ~= "Clues" and not clueShop(category, group) and collectionKind(category, group) ~= "shop" then text = Tracking.CollectionDefaultTarget(category, group) end
            local target
            target, message = collectionTargetNumber(text, true)
            if not target then return nil, message end
            local child
            child, message = Tracking.Build(category, group, option, text, previousItems[option.key])
            if not child then return nil, message end
            items[#items + 1] = child
        end
    end
    if #items == 0 then return nil, "Select at least one tracking option." end
    -- One clue reward is a note of its own. Reward shop unlocks stay a list even with one ("0 / 1 unlocks"), its tile showing
    -- the currency still needed.
    if (category == "Clues" or clueShop(category, group)) and #items == 1 then
        return items[1], Tracking.CollectionTitle(category, group, items, targetText)
    end
    local kind = collectionKind(category, group)
    local name = group and group.name
    local label = #items == 1 and items[1].label or Tracking.CollectionTitle(category, group)
    return buildCollectionParent(category, group,
        kind == "skill" and "skills-selection" or kind == "research" and "invention-research:Components"
            or kind == "clue" and "clues-selection:" .. name
            or kind == "production" and countedPrefix(category) .. name
            or (kind == "relic" or kind == "building" or kind == "breed" or kind == "camp" or kind == "artefact" or kind == "recipe" or kind == "floor" or kind == "cheevo" or kind == "shop") and "unlocks-selection:" .. name
            or "ports-selection:" .. name,
        label, items)
end

function Tracking.BuildCollection(category, group, selectedOptions, targetText, previous)
    if Tracking.IsComponents(category, group) then return Tracking.BuildComponents(group, selectedOptions, targetText, previous) end
    group = groupFrom(category, group)
    local kind = collectionKind(category, group)
    if kind == "skill" or kind == "research" or kind == "good" or kind == "resource" or kind == "production" or kind == "relic" or kind == "building" or kind == "breed" or kind == "camp" or kind == "artefact" or kind == "recipe" or kind == "floor" or kind == "cheevo" or kind == "shop" or kind == "clue" then
        return buildAdditionalCollection(category, group, selectedOptions, targetText, previous)
    end
    if (not bossLike(category) and category ~= "Currencies") or bossLike(category) and not group
        or type(selectedOptions) ~= "table" then return nil, "Choose what to track first." end
    local options = Tracking.CollectionOptions(category, group)
    local selected, message = collectionSelectedKeys(selectedOptions, collectionOptionLookup(options),
        "Choose valid " .. (category == "Currencies" and "currencies" or "collection items") .. " to track.",
        "Choose valid items to track.")
    if not selected then return nil, message end
    local previousItems = {}
    if previous and previous.category == category and (not bossLike(category) or previous.group == group.name) then
        for _, item in ipairs(previous.items or {previous}) do previousItems[item.key or item.variable] = item end
    end
    local items = {}
    for _, option in ipairs(options) do
        if selected[option.key] then
            if #items >= Tracking.MAX_COLLECTION_ITEMS then return nil, "Choose up to " .. Tracking.MAX_COLLECTION_ITEMS .. " items." end
            local text, message = collectionTargetText(targetText, option,
                type(targetText) == "table" and not Tracking.CollectionTargetEditable(category, group, option))
            if not text then return nil, message end
            local target
            target, message = collectionTargetNumber(text, category == "Currencies" or type(targetText) == "table")
            if not target then return nil, message end
            local child
            child, message = Tracking.Build(category, group, option, text, previousItems[option.key])
            if not child then return nil, message end
            if bossLike(category) then
                child.target = loggedDrop(option.varName) and target or 1
            end
            items[#items + 1] = child
        end
    end
    if #items == 0 then return nil, "Select at least one " .. (category == "Currencies" and "currency" or "collection item") .. "." end
    return buildCollectionParent(category, group, bossLike(category) and "boss-items:" .. group.name or "currency-selection",
        #items == 1 and items[1].label or bossLike(category) and "Collection items" or "Currencies", items)
end

-- I'm unsure if I want to bring this as a feature or Debug... but its useful for me! Adds every item (or boss achievement) in one go.
function Tracking.Bulk(category, group, existing)
    local found, result, skipped = {}, {}, 0
    for _, saved in ipairs(existing or {}) do
        local tracking = saved.tracking or saved
        if type(tracking.variable) == "string" and tracking.variable ~= "" then found[tracking.variable] = true end
    end
    if category ~= "Combat" then return result, skipped end
    for _, option in ipairs(Tracking.Options(category, group)) do
        if option.kind == "item" then
            local tracking, label = Tracking.Build(category, group, option, "")
            if tracking and not found[tracking.variable] then
                found[tracking.variable] = true
                result[#result + 1] = {tracking = tracking, label = label}
            else skipped = skipped + 1 end
        end
    end
    return result, skipped
end

-- For a collection of achievements whose goals have parts (qualifications, research, mysteries): how many of all the
-- parts are done, how many there are, and what they are called. nil for anything else.
local function cheevoPartTotals(tracking)
    if not tracking or type(tracking.items) ~= "table" or #tracking.items == 0 then return nil end
    local done, total, noun, withParts, counted = 0, 0, nil, false, false
    for _, item in ipairs(tracking.items) do
        if not Cheevos.isKey(item.key) then return nil end
        local list = Cheevos.parts(item.key)
        local counterDone, counterTotal, counterNoun = Cheevos.counter(item.key)
        if counterDone then
            -- A goal that counts a whole list (Music Maestro): its own count, with no parts to list.
            counted = true
            noun = noun or counterNoun
            done, total = done + counterDone, total + counterTotal
        elseif list then
            withParts = true
            local entry = Cheevos.info(item.key)
            noun = noun or entry and entry.noun
            for _, part in ipairs(list) do
                total = total + 1
                if part.done == true then done = done + 1 end
            end
        else
            -- A goal without parts counts as one part of its own.
            total = total + 1
            if Cheevos.done(item.key) == true then done = done + 1 end
        end
    end
    if not (withParts or counted) or total == 0 then return nil end
    return done, total, noun or "achievements", withParts
end

-- Notes whose progress is told by their sub tasks (an achievement made of parts): the tiles of the goals themselves add
-- nothing, and the sub tasks are shown unless the note has been collapsed.
function Tracking.TasksOnly(tracking)
    local _, _, _, listed = cheevoPartTotals(tracking)
    return listed == true
end

-- Parts of a multi-part task with whether each one is done, or nil.
function Tracking.SubTasks(tracking)
    if tracking and tracking.key and not tracking.items and Cheevos.isKey(tracking.key) then return Cheevos.parts(tracking.key) end
    if tracking and tracking.items and #tracking.items > 0 then
        -- A collection of achievements lists the parts of each (named after it when there are several).
        local list = {}
        for _, item in ipairs(tracking.items) do
            if not Cheevos.isKey(item.key) then return nil end
            local entry = Cheevos.info(item.key)
            for _, part in ipairs(Cheevos.parts(item.key) or {}) do
                list[#list + 1] = {text = #tracking.items > 1 and entry and (entry.name .. ": " .. part.text) or part.text, done = part.done, tip = part.tip}
            end
        end
        return #list > 0 and list or nil
    end
    if not tracking or tracking.category ~= "Tasks" or not tracking.key then return nil end
    local parts = Tasks.parts(tracking.key)
    if not parts then return nil end
    local list = {}
    for _, part in ipairs(parts) do
        if part[1] ~= "" then
            local value = readVariable(part[2])
            list[#list + 1] = {text = part[1], done = value ~= nil and value >= part[3]}
        end
    end
    return #list > 0 and list or nil
end

local function countParts(parts)
    local done, readable = 0, false
    for _, part in ipairs(parts) do
        local value = readVariable(part[2])
        if value ~= nil then
            readable = true
            if value >= part[3] then done = done + 1 end
        end
    end
    return readable and done or nil
end

function Tracking.Read(tracking, includeSlots)
    if not tracking then return nil end
    if tracking.floorVars then return floorLine(tracking) end
    if Cheevos.isKey(tracking.key) and not tracking.items then return Cheevos.progress(tracking.key) end
    if Camp.isStandKey(tracking.key) and not tracking.items then return Camp.standProgress(tracking.key) end
    if tracking.scheduleKey then return Scheduled.readItem(tracking) end
    if isScheduled(tracking) then return Scheduled.progress(tracking.key, includeSlots, tracking) end
    if isRaven(tracking) then return Raven.progress() end
    if isJournal(tracking) then return Journal.progress(tracking.key, includeSlots) end
    if tracking.journalKey then
        local status = Journal.readItem(tracking)
        if status then return status end
    end
    if isCrew(tracking) then return crewProgress(includeSlots) end
    if isGoal(tracking) then return goalProgress(tracking.key, includeSlots) end
    if tracking.goalKey then
        local state = Goals.isDone(tracking.goalKey, tracking.goalIndex)
        return {current = state == nil and nil or state and 1 or 0, target = 1, fraction = state and 1 or 0, complete = state == true,
            owned = false, text = state and "Done" or "Not done yet"}
    end
    if tracking.category == "Slayer" and SlayerTask.isTask(tracking.key) then
        local progress = SlayerTask.Progress(tracking)
        progress.owned = false
        return progress
    end
    local current, owned, barFraction, slots
    local parts = tracking.category == "Tasks" and tracking.key and Tasks.parts(tracking.key)
    local mining = tracking.category == "Gathering" and Mining.info(tracking.key)
        or isProd(tracking.category) and Production.info(tracking.key)
    local quest = tracking.category == "Quests" and Quests.info(tracking.key)
    local questState
    local rule = tracking.category == "Bossing" and tracking.group == "Magister"
        and tracking.variable == "MENAPHOS_SLAYER_MAGISTER_JOURNAL" and Bossing.collectionRule(tracking.key)
    if tracking.items then
        current = 0
        local partial = 0
        slots = includeSlots and {} or nil
        for index, item in ipairs(tracking.items) do
            local status = Tracking.Read(item)
            if slots then
                local slot = {key = item.key or item.skill or item.variable, label = item.label or item.skill or item.variable}
                if status.current ~= nil then slot.complete = status.complete == true end
                slots[index] = slot
            end
            if status.current == nil then
                current = nil
                if not slots then break end
            elseif current ~= nil and status.complete then current = current + 1 end
            partial = partial + (status.fraction or 0)
        end
        -- Component collections fill the bar by quantity, so 34/50 shows progress before it's complete.
        if current and (tracking.category == "Invention" or tracking.category == "Currencies" or counted(tracking.category) or Tracking.IsSkillXP(tracking.category, tracking.group)) and #tracking.items > 0 then
            barFraction = partial / #tracking.items
        end
    elseif mining then
        current = tracking.gained or 0
    elseif quest then
        questState = Quests.state(quest)
        if questState ~= nil then current = questState == "done" and 1 or 0 end
    elseif rule then
        local value = readVariable(tracking.variable, tracking.varId)
        if value ~= nil then current = value >= rule.threshold and 1 or 0 end
    elseif tracking.skill then
        local read = Tracking.IsSkillXP(tracking.category, tracking.group) and Skills.readSkillXP or Skills.readSkillLevel
        current = read(Skills.SKILL_BY_TYPE[tracking.skill])
    elseif parts then
        current = countParts(parts)
        if current and current > tracking.target then current = tracking.target end
    else
        local bit = tracking.category == "Invention" and Invention.bitOf(tracking.key)
        if tracking.vars then current = sumVariables(tracking.vars)
        else current = readVariable(tracking.variable, tracking.varId) end
        if Camp.isIaiaKey(tracking.key) then current = Camp.iaiaAmount(tracking.key, current) end
        if bit and current ~= nil then current = Invention.readBit(current, bit) end
        if current ~= nil and tracking.base ~= nil and not Timers.isVar(tracking.variable) then current = math.max(0, current - tracking.base) end
        if tracking.ownedVar then
            local value = readVariable(tracking.ownedVar)
            if value and value > 0 then owned, current = true, tracking.target
            elseif value ~= nil then owned = false end
        end
    end
    if not finite(current) then current = nil end
    if Timers.isVar(tracking.variable) and not tracking.items then
        -- A time to beat: lower is better, and 0 means no kill yet.
        local target = tracking.target
        if current == nil then
            return {current = nil, target = target, fraction = 0, text = "Waiting for variable: " .. tracking.variable, complete = false, owned = false}
        end
        local done = current > 0 and current <= target
        -- The bar shows how close the best time is to the target (target / best), the same figure as the percentage.
        local fraction = done and 1 or current > 0 and Vars.clamp(target / current, 0, 1) or 0
        return {current = current, target = target, fraction = fraction, complete = done, owned = false,
            text = "Target: " .. Timers.format(target, tracking.variable) .. " (PB: " .. (current > 0 and Timers.format(current, tracking.variable) or "none yet")
                .. (done and " - Complete" or current > 0 and (" - " .. tostring(math.floor(Vars.clamp(target / current, 0, 1) * 100)) .. "%") or "") .. ")"}
    end
    -- Keep the bar at the target once the region is finished.
    if current and tracking.variable == "POP_EXPLORED" and current > tracking.target then current = tracking.target end
    local target = tracking.target
    local fraction = current and Vars.clamp(current / target, 0, 1) or 0
    local shownFraction = barFraction or fraction
    local complete = current ~= nil and current >= target
    -- Enough to buy an unlock you don't own yet: not done until it is bought.
    local readyToBuy = complete and owned == false and not tracking.items
    if readyToBuy then complete = false end
    local text
    if owned then text = "Unlocked - Complete"
    elseif current == nil then
        local _, plural = Tracking.CollectionNames(tracking.category, tracking.group)
        text = tracking.items and ("Waiting for " .. plural)
        or tracking.skill and (Tracking.IsSkillXP(tracking.category, tracking.group) and "Waiting for skill XP" or "Waiting for skill level") or "Waiting for variable: " .. tracking.variable
    else
        local xp = Tracking.IsSkillXP(tracking.category, tracking.group)
        local format = (xp or tracking.category == "Clues" or tracking.category == "Currencies" or tracking.category == "Ports" or tracking.category == "Invention" or tracking.category == "Slayer" or tracking.category == "Gathering" or isProd(tracking.category) or tracking.category == "Unlocks") and Vars.withCommas or tostring
        local _, plural = Tracking.CollectionNames(tracking.category, tracking.group)
        -- A reward shop that is a section of a group (Anachronia > Dinosaur Farm) still counts unlocks.
        if tracking.items and tracking.items[1] and tracking.category == "Unlocks"
            and (tracking.group == Camp.GROUP or tracking.group == Relics.GROUP)
            and Unlocks.entry(tracking.group, tracking.items[1].key) then plural = "unlocks" end
        if tracking.items and tracking.items[1] and Cheevos.isKey(tracking.items[1].key) then
            plural = tracking.category == "Skills" and Cheevos.isPetGroup(tracking.group) and "pets"
                or tracking.group == Cheevos.HOG_GROUP and (Cheevos.sectionOf(tracking.items[1].key) == Cheevos.HOG_ENGRAMS
                    and "engrams" or "effects active")
                or tracking.group == Cheevos.HOM_GROUP and "bots recovered"
                or tracking.group == Cheevos.MUSIC_GROUP and "tracks"
                or tracking.group == Cheevos.TITLES_GROUP and "titles"
                or Cheevos.isCodexGroup(tracking.group) and "monsters captured"
                or Cheevos.isScrollGroup(tracking.category, tracking.group) and "scrolls complete"
                or (tracking.group == Cheevos.VARROCK_GROUP or tracking.group == Cheevos.PRIF_GROUP) and "skills added"
                or "achievements"
        end
        text = (tracking.skill and not xp and "Level " or "") .. format(current) .. " / " .. format(target) .. (tracking.skill and xp and " XP" or "")
            .. (tracking.items and (" " .. plural) or "")
            .. " (" .. tostring(math.floor(shownFraction * 100)) .. "%)" .. (complete and " - Complete" or readyToBuy and " - Ready to unlock" or "")
    end
    if current ~= nil and tracking.items then
        -- Achievements made of parts show how far through all the parts you are (4 / 7 achievements (57%)).
        local partsDone, partsTotal, noun, listed = cheevoPartTotals(tracking)
        if partsDone then
            shownFraction = complete and 1 or partsDone / partsTotal
            if complete then partsDone = partsTotal end
            text = partsDone .. " / " .. partsTotal .. " " .. noun .. " (" .. tostring(math.floor(shownFraction * 100)) .. "%)"
                .. (complete and " - Complete" or "")
            -- A count of a whole list (Music Maestro) also says how many are left.
            if not listed then text = Cheevos.counterText(partsDone, partsTotal, noun, complete) end
        end
    end
    -- Enrage / kill-streak records: "Highest enrage: 1,234% / 4,000% (30%)".
    local record = current ~= nil and not tracking.items and Bossing.recordOf(tracking.variable)
    if record then
        local unit = record.enrage and "%" or ""
        text = record.label .. ": " .. Vars.withCommas(current) .. unit .. " / " .. Vars.withCommas(target) .. unit
            .. " (" .. tostring(math.floor(shownFraction * 100)) .. "%)" .. (complete and " - Complete" or "")
    end
    if current ~= nil and tracking.category == "Unlocks" and tracking.group == Camp.GROUP then
        local workers = Camp.workerSummary(tracking)
        if workers then
            text = Vars.withCommas(workers.assigned) .. " workers assigned - " .. Vars.withCommas(workers.perHour) .. "/hr"
        end
    end
    if quest and current ~= nil and not complete then
        text = text .. (questState == "started" and " - In progress" or " - Not started")
    end
    if current ~= nil and tracking.category == "Invention" and Invention.bitOf(tracking.key) then
        text = complete and "Unlocked - Complete" or "Not unlocked yet"
    end
    if current ~= nil and tracking.items and not complete and tracking.category == "Unlocks" then
        -- Unlocks you have the points for but have not bought yet.
        local ready = 0
        for _, item in ipairs(tracking.items) do
            if type(item) == "table" and item.ownedVar then
                local okItem, itemProgress = pcall(Tracking.Read, item)
                if okItem and type(itemProgress) == "table" and itemProgress.ready then ready = ready + 1 end
            end
        end
        if ready > 0 then text = text .. " - " .. ready .. " ready to unlock" end
    end
    return {current = current, target = target, fraction = shownFraction, text = text, complete = complete, owned = owned == true, slots = slots,
        ready = readyToBuy == true}
end

-- Memorial to Guthix notes, and notes that count memory strands, also show your prestige and the passive effects on.
local readTracking = Tracking.Read
local function wantsHogLines(tracking)
    if type(tracking) ~= "table" then return false end
    if tracking.category == "Unlocks" and tracking.group == Cheevos.HOG_GROUP then return true end
    if tracking.category ~= "Currencies" then return false end
    if Cheevos.isHogCurrency(tracking.variable) then return true end
    for _, item in ipairs(type(tracking.items) == "table" and tracking.items or {}) do
        if Cheevos.isHogCurrency(item.variable) then return true end
    end
    return false
end
-- Unlocks that come strictly one after another (the Livid Farm spells): "VAR>=N" counts how many you have.
local IN_ORDER = { LUNARFM_SPELLS_UNLOCKED = true }
Tracking.LIVID_FARM_GROUP, Tracking.LIVID_FARM_OBJECT = "Livid Farm", 42290

-- The place of an in-order unlock (N of "VAR>=N"), or nil for anything else.
function Tracking.OrderedTier(tracking)
    local base, tier = (type(tracking) == "table" and tracking.ownedVar or ""):match("^(.-)>=(%d+)$")
    if base and IN_ORDER[base] then return tonumber(tier), base end
    return nil
end

function Tracking.Read(tracking, includeSlots)
    local result = readTracking(tracking, includeSlots)
    -- An in-order unlock whose turn hasn't come yet (an earlier one is still locked) reads as locked: no progress shown.
    local tier, tierVar = Tracking.OrderedTier(tracking)
    if tier and type(result) == "table" and not result.complete and not tracking.items then
        local have = readVariable(tierVar)
        if have ~= nil and have < tier - 1 then
            local copy = {}
            for key, value in pairs(result) do copy[key] = value end
            copy.locked, copy.fraction = true, 0
            copy.text = "Locked: unlock the spells before it first"
            return copy
        end
    end
    if type(result) ~= "table" or not wantsHogLines(tracking) or tracking.isItem then return result end
    local lines = Cheevos.hogLines()
    if not lines then return result end
    local copy = {}
    for key, value in pairs(result) do copy[key] = value end
    copy.text = (copy.text or "") .. "\n" .. lines
    return copy
end

function Tracking.IsPetGroup(category, group)
    return category == "Skills" and Cheevos.isPetGroup(type(group) == "table" and group.name or group)
end

function Tracking.PreviewModel(category, group, option)
    if Tracking.IsPetGroup(category, group) and option then
        local pet = Cheevos.info(option.key)
        if pet and pet.pet and pet.skill then return ModelPresets.Preview(PetModelPresets[pet.skill]) end
    end
    if category == "Combat" then return Bossing.combatPreviewModel(groupFrom(category, group), option) end
    if category ~= "Bossing" then return nil end
    return Bossing.previewModel(groupFrom(category, group), option)
end

function Tracking.Preview(category, group, option, targetText)
    if not option then return nil end
    local tracking = {category = category, target = option.defaultTarget or 1, variable = option.varName or ""}
    if option.userTarget and targetText ~= nil then tracking.target = Vars.parseNumber(targetText) or 0 end
    local rule = category == "Bossing" and Bossing.collectionRule(option.key)
    if option.kind == "task" or option.kind == "quest" or option.kind == "mining" or option.kind == "production" or option.kind == "blueprint" or option.kind == "crew" or option.kind == "goal" or option.kind == "journal" or option.kind == "raven" or option.kind == "scheduled" or option.kind == "cheevo" or option.kind == "stand" or rule then
        tracking.key = option.key
        tracking.group = type(group) == "table" and group.name or group or rule and rule.group
    end
    -- Dream of Iaia amounts are read through their key (Stone is stored as an offset).
    if Camp.isIaiaKey(option.key) then tracking.key = option.key end
    if option.savedTracking then tracking = option.savedTracking
    elseif option.skill then
        tracking.skill = option.skill
        tracking.group = type(group) == "table" and group.name or group
    elseif option.currency then tracking.variable = option.currency.var
    elseif option.piece then
        tracking.variable, tracking.ownedVar = option.piece.currencyVar or Clues.currencyVar, option.piece.owned
        if option.piece.noBalance then tracking.variable = (option.piece.owned or ""):gsub(">=%d+$", "") end
    elseif option.kind == "task" then tracking.variable, tracking.vars = option.varName, option.taskVars
    elseif option.kind == "item" and option.var then tracking.variable = option.var
    elseif option.vars then tracking.variable, tracking.vars = option.vars[1], option.vars end
    local status = Tracking.Read(tracking)
    if option.kind == "raven" or option.kind == "scheduled" then
        if option.kind == "scheduled" then status.text = status.text:gsub("<col=%x+>", ""):gsub("</col>", "") end
        status.text = status.text:gsub("\n", " | ")
        return status
    end
    if option.savedTracking and option.savedTracking.items then return status end
    if option.kind == "slayertask" then
        local task = SlayerTask.Current(option.key)
        status.current, status.complete = task and task.id or nil, false
        status.text = task == nil and "Waiting for your task" or task.id == 0 and "No active task right now"
            or "Now: " .. tostring(task.info and task.info.name or ("task " .. task.id)) .. " (" .. tostring(task.left) .. " left)"
        return status
    end
    if (option.kind == "production" or option.kind == "mining") and option.item then
        -- The grid shows what you hold right now; the note itself only counts new ones.
        local ok, held = pcall(function()
            if option.kind == "mining" then return select(3, Mining.places(option.item)) end
            return (Production.places(option.item))
        end)
        status.current = ok and finite(held) and held or nil
        status.text = status.current and "In your backpack: " .. Vars.withCommas(status.current) or "Current value is not available yet."
        return status
    end
    if status.current == nil then status.text = "Current value is not available yet."
    elseif option.kind == "crew" or option.kind == "goal" or option.kind == "journal" or option.kind == "cheevo" or option.kind == "stand" then status.text = status.text
    elseif option.piece then status.text = status.owned and "Already unlocked" or "You have " .. Vars.withCommas(status.current) .. " " .. (option.piece.currencyName or "points")
        .. (not status.owned and option.piece.cost and status.current >= option.piece.cost and " - ready to unlock" or "")
    elseif option.kind == "area" then status.text = status.complete and "Log complete" or "Not completed yet"
    elseif option.kind == "record" then status.text = "Currently: " .. Vars.withCommas(status.current) .. (option.enrage and "%" or "")
    elseif category == "Slayer" then status.text = "In your item log: " .. Vars.withCommas(status.current)
    elseif option.kind == "timer" then status.text = "Your fastest time: " .. (status.current > 0 and Timers.format(status.current, option.varName) or "none yet")
    elseif option.kind == "blueprint" then status.text = status.complete and "Already unlocked" or "Not unlocked yet"
    elseif category == "Invention" then status.text = "You have: " .. Vars.withCommas(status.current)
    elseif category == "Ports" and option.kind == "good" then status.text = "In stock: " .. Vars.withCommas(status.current)
    elseif category == "Ports" then
        status.text = status.current >= option.steps and "Region fully explored" or ("Explored so far: " .. Vars.withCommas(status.current) .. " / " .. Vars.withCommas(option.steps))
    elseif category == "Gathering" or isProd(category) then status.text = "Counts new ones from when you apply this"
    elseif category == "Quests" then
        local state = Quests.state(option.quest)
        status.text = status.complete and "Completed" or state == "started" and "In progress" or "Not started"
    elseif category == "Tasks" then
        local steps = option.steps or 1
        status.text = status.complete and "Completed" or steps > 1 and ("Progress: " .. tostring(status.current) .. " / " .. steps) or "Not completed yet"
    elseif skillLevels(category, group) then status.text = Tracking.IsSkillXP(category, group) and "Current XP: " .. Vars.withCommas(status.current) or "Current level: " .. tostring(status.current)
    elseif category == "Clues" and option.kind == "item" then status.text = "In your item log: " .. Vars.withCommas(status.current)
    elseif category == "Clues" then status.text = "Completed so far: " .. Vars.withCommas(status.current)
    else status.text = "Current: " .. Vars.withCommas(status.current) end
    return status
end

local function collectionIcon(tracking)
    local name = tracking.group
    if skillLevels(tracking.category, name) and #tracking.items == 1 then
        return Tracking.Icon(tracking.items[1], true)
    end
    if type(name) ~= "string" then return nil end
    if tracking.category == "Bossing" then
        for _, boss in ipairs(Bossing.groups()) do
            if boss.name == name then
                local pet = boss.pet or boss.pets and boss.pets[1]
                return pet and Objects.findObjectID(pet) or nil
            end
        end
    elseif tracking.category == "Slayer" then
        local sprite = Slayer.areaSprite(name)
        return sprite and { sprite = sprite } or nil
    end
    return nil
end

-- Groups that predate the "Skill: Name" naming.
local GROUP_SKILL = { Ores = "MINING", Bars = "SMITHING" }

local function groupSkillIcon(group)
    local skillName = GROUP_SKILL[group] or (group:match("^([^:]+):") or ""):upper()
    local entry = Skills.SKILL_BY_TYPE[skillName]
    return entry and Skills.skillIconRef(entry) or nil
end

-- The number written on a Daemonheim floor's tile (floors have no picture), or nil for anything else.
function Tracking.TileText(tracking)
    local variable = tracking and tracking.category == "Training" and tracking.variable
    if not Floors.isKey(variable) then return nil end
    return variable:match("(%d+)$")
end

function Tracking.Icon(tracking, itemOwn)
    if not tracking then return nil end
    if (tracking.kind == "timer" or tracking.variable ~= nil) and Timers.isDG(tracking.varName or tracking.variable) then
        return Skills.skillIconRef(Skills.SKILL_BY_TYPE.DUNGEONEERING)
    end
    -- Floor notes wear the Dungeoneering skill icon; their tiles show the floor number instead of a picture.
    if tracking.category == "Training" and Floors.isGroup(tracking.group) then
        if itemOwn then return nil end
        return Skills.skillIconRef(Skills.SKILL_BY_TYPE.DUNGEONEERING)
    end
    -- A building's own tile shows the building's item.
    if itemOwn and tracking.category == "Unlocks" and tracking.group == Fort.GROUP and Fort.isKey(tracking.key) then
        local building = Fort.info(tracking.key)
        if building and building.obj then return building.obj end
    end
    -- Breeding notes wear the Farming skill icon (each animal's own picture stays on its tile).
    if not itemOwn and (tracking.category == "Gathering" and tracking.group == Goals.FARM
        or tracking.category == "Unlocks" and tracking.group == Goals.LOGS) then
        return Skills.skillIconRef(Skills.SKILL_BY_TYPE.FARMING)
    end
    if itemOwn and tracking.category == "Gathering" and Goals.isBreedKey(tracking.key) and not tracking.iconObj then
        local object = Goals.breedObject(tracking.variable)
        if object then return object end
    end
    -- Artefact notes wear the Archaeology skill icon.
    if not itemOwn and tracking.category == "Gathering" and Arch.isGroup(tracking.group) then
        return Skills.skillIconRef(Skills.SKILL_BY_TYPE.ARCHAEOLOGY)
    end
    -- Reward shops tied to a skill wear its icon (Crux Eqal, the farms: Farming); a shop that is a section of a group
    -- (Anachronia > Dinosaur Farm) is found from its first item.
    if not itemOwn and tracking.category == "Unlocks" then
        local first = tracking.items and tracking.items[1] or tracking
        local shop = (Unlocks.headerSkill(tracking.group) or Unlocks.headerObj(tracking.group)) and tracking.group
            or Unlocks.shopOf(tracking.group) and Unlocks.entry(tracking.group, first.key) and Unlocks.shopOf(tracking.group)
        local shopSkill = shop and Unlocks.headerSkill(shop)
        if shopSkill and Skills.SKILL_BY_TYPE[shopSkill] then return Skills.skillIconRef(Skills.SKILL_BY_TYPE[shopSkill]) end
        local shopObj = shop and Unlocks.headerObj(shop)
        if shopObj then return shopObj end
    end
    -- Base camp notes (resources and buildings) wear the Anachronia lodestone insignia.
    if not itemOwn and tracking.category == "Unlocks" and tracking.group == Camp.GROUP then
        local first = tracking.items and tracking.items[1] or tracking
        -- The Skillcape Rack wears the stored cape (the insignia while it is empty).
        local cape = Camp.isStandKey(first.key) and Camp.standObject(first.key)
        if cape then return cape end
        if Camp.isKey(first.key) then
            local sprite = Sprites.spriteByName(first.key:match("^camp%-wrk:") and "ICON_WORKERS" or "RS3_ICON_LODESTONE_INSIGNIA_27")
            if sprite then return {sprite = sprite} end
        end
    end
    -- Pet notes (and each pet's tile) wear the pet itself: its item once found, else what was saved with the note.
    if tracking.category == "Skills" and Cheevos.isPetGroup(tracking.group) then
        local first = (not itemOwn and tracking.items and tracking.items[1]) or tracking
        local object = Cheevos.petObject(first.key)
        if object then return object end
        if first.iconObj then return first.iconObj end
        local numeric = type(first.iconSprite) == "string" and tonumber(first.iconSprite:match("^#(%d+)$"))
        if numeric then return {sprite = numeric} end
    end
    -- Livid Farm notes wear a livid plant (each spell keeps its own icon on its tile).
    if not itemOwn and tracking.category == "Unlocks" and tracking.group == Tracking.LIVID_FARM_GROUP then
        return Tracking.LIVID_FARM_OBJECT
    end
    -- Statue notes wear their statue's list (each skill keeps its own icon on its tile).
    if not itemOwn and tracking.category == "Unlocks" and (tracking.group == Cheevos.VARROCK_GROUP or tracking.group == Cheevos.PRIF_GROUP) then
        local first = tracking.items and tracking.items[1] or tracking
        local entry = Cheevos.isKey(first.key) and Cheevos.info(first.key)
        if entry and entry.skillIcon then
            return tracking.group == Cheevos.VARROCK_GROUP and Cheevos.VARROCK_STATUE_OBJECT or Cheevos.PRIF_STATUE_OBJECT
        end
    end
    -- Ports scroll notes wear a scroll: the one their scrolls share (all melee, say), otherwise the plain voyage scroll.
    if not itemOwn and Cheevos.isScrollGroup(tracking.category, tracking.group) then
        local shared
        for _, entry in ipairs(tracking.items or {tracking}) do
            local info = Cheevos.isKey(entry.key) and Cheevos.info(entry.key)
            local sprite = info and info.sprite
            if not sprite or (shared and shared ~= sprite) then shared = nil break end
            shared = sprite
        end
        return {sprite = shared or Cheevos.SCROLL_SPRITE}
    end
    -- Slayer Codex notes wear the codex (each monster keeps its own picture on its tile).
    if not itemOwn and tracking.category == "Slayer" and Cheevos.isCodexGroup(tracking.group) then return Cheevos.CODEX_OBJECT end
    -- Music notes wear a sheet of music (each track keeps its own picture on its tile).
    if not itemOwn and tracking.category == "Unlocks" and tracking.group == Cheevos.MUSIC_GROUP then
        local object = Objects.findObjectID(Cheevos.MUSIC_OBJECT)
        if object then return object end
    end
    -- Hall of Memories notes wear a memory-storage bot (each bot keeps its own picture on its tile).
    if not itemOwn and tracking.category == "Unlocks" and tracking.group == Cheevos.HOM_GROUP then
        local object = Objects.findObjectID(Cheevos.HOM_ICON_OBJECT)
        if object then return object end
    end
    -- Memorial to Guthix notes wear a memory strand (each engram / effect keeps its own picture on its tile).
    if not itemOwn and tracking.category == "Unlocks" and tracking.group == Cheevos.HOG_GROUP then
        local object = Objects.findObjectID(Cheevos.HOG_ICON_OBJECT)
        if object then return object end
    end
    -- Group Ironman notes wear their Journey Tier's picture; notes spanning several tiers wear the Group Ironman helmet.
    if not itemOwn and tracking.category == "Unlocks" and tracking.group == Cheevos.GIM_GROUP then
        local sprite
        for _, entry in ipairs(tracking.items or {tracking}) do
            local info = Cheevos.isKey(entry.key) and Cheevos.info(entry.key)
            local own = info and info.sprite
            if own and sprite and own ~= sprite then sprite = Cheevos.GIM_ICON break end
            sprite = sprite or own
        end
        return {sprite = sprite or Cheevos.GIM_ICON}
    end
    -- Kili's Knowledge (Necromancy achievements) wears the Necromancy skill icon; each tier's gear stays on its tile.
    if not itemOwn and tracking.category == "Unlocks" and tracking.group == Necromancy.GROUP then
        local first = tracking.items and tracking.items[1] or tracking
        if Cheevos.isKey(first.key) then return Skills.skillIconRef(Skills.SKILL_BY_TYPE.NECROMANCY) end
    end
    -- Relic notes wear the Archaeology skill icon (each relic's own picture stays on its tile).
    if not itemOwn and tracking.category == "Unlocks" and tracking.group == Relics.GROUP and tracking.key ~= nil then
        return Skills.skillIconRef(Skills.SKILL_BY_TYPE.ARCHAEOLOGY)
    end
    -- A Fort building note wears the skill its building needs (Construction), the level showing beside it.
    if tracking.category == "Unlocks" and tracking.group == Fort.GROUP and not itemOwn and (tracking.items == nil or #tracking.items == 1) then
        return Skills.skillIconRef(Skills.SKILL_BY_TYPE.CONSTRUCTION)
    end
    if (tracking.category == "Slayer" or tracking.kind == "slayertask") and SlayerTask.isTask(tracking.key) then
        -- The Reaper task wears the Reaper skull; the Slayer task the Slayer skill icon.
        if tracking.key == "task:reaper" then
            local skull = Sprites.spriteByName("AIF_BOSS_SLAYER_POINTS_ICON_SML")
            if skull then return {sprite = skull} end
        end
        return Skills.skillIconRef(Skills.SKILL_BY_TYPE.SLAYER)
    end
    -- Every Invention note (components, devices, research...) wears the Invention skill icon (collection tiles pass itemOwn to keep their own sprite).
    if tracking.category == "Invention" and not itemOwn then return Skills.skillIconRef(Skills.SKILL_BY_TYPE.INVENTION) end
    if tracking.skill then return Skills.skillIconRef(Skills.SKILL_BY_TYPE[tracking.skill]) end
    if tracking.icon then return tracking.icon end
    local scheduled = isScheduled(tracking) and Scheduled.info(tracking.key)
    if scheduled and scheduled.objId then return scheduled.objId end
    -- Currency notes whose header wears a skill's icon (Crux Eqal favour: Farming); a collection does when all its currencies do.
    if not itemOwn and tracking.category == "Currencies" then
        local skill
        for _, entry in ipairs(tracking.items or {tracking}) do
            local own = Currencies.headerSkillFor(entry.variable)
            if not own or (skill and own ~= skill) then skill = nil break end
            skill = own
        end
        if skill and Skills.SKILL_BY_TYPE[skill] then return Skills.skillIconRef(Skills.SKILL_BY_TYPE[skill]) end
    end
    -- A currency note of a single currency wears that currency's own picture.
    if not itemOwn and tracking.category == "Currencies" and type(tracking.items) == "table" and #tracking.items == 1 then
        local own = Tracking.Icon(tracking.items[1], true)
        if own then return own end
    end
    -- Currencies that use a skill's icon (Slayer Points) instead of a sprite or item.
    local currencyVar = tracking.variable or tracking.currency and tracking.currency.var
    local skillIcon = tracking.currency and tracking.currency.skillIcon
        or tracking.category == "Currencies" and currencyVar and Currencies.skillIconFor(currencyVar) or nil
    if skillIcon and Skills.SKILL_BY_TYPE[skillIcon] then return Skills.skillIconRef(Skills.SKILL_BY_TYPE[skillIcon]) end
    -- One picked item (not a collection) wears its own object, like the item it counts.
    if counted(tracking.category) and not tracking.items and not itemOwn and tracking.key then
        local item = countedInfo(tracking.category, tracking.key)
        if item and type(item.objId) == "number" then return item.objId end
    end
    -- A Production / Gathering group wears the icon of the skill it belongs to ("Fletching: Ammunition" -> Fletching).
    if counted(tracking.category) and type(tracking.group) == "string" and not itemOwn then
        local icon = groupSkillIcon(tracking.group)
        if icon then return icon end
    end
    if tracking.items and not tracking.skill then
        local icon = collectionIcon(tracking)
        if icon then return icon end
    end
    local spriteName = scheduled and scheduled.spriteName or tracking.iconSprite or tracking.spriteName
        or tracking.currency and tracking.currency.sprite
        or tracking.piece and tracking.piece.sprite and "#" .. tracking.piece.sprite
    if spriteName then
        local numeric = tostring(spriteName):match("^#(%d+)$")
        local sprite = numeric and tonumber(numeric) or Sprites.spriteByName(spriteName)
        if sprite then return {sprite = sprite} end
    end
    if tracking.noIcon then return nil end
    local object = tracking.iconObj or tracking.objId or tracking.obj
        or tracking.piece and tracking.piece.obj or tracking.currency and tracking.currency.obj
    local variable = tracking.variable or tracking.varName or tracking.currency and tracking.currency.var
    object = Icons.bossPetIcon(variable) or object
    if variable == "CURRENCY_POF" and (object == nil or object == id.Obj.POF_CURRENCY) then
        object = id.Obj.POF_CURRENCY5
    end
    return object or Icons.iconObjectForNote({variable = tracking.variable or tracking.varName,
        text = tracking.label or ""})
end

function Tracking.Description(tracking)
    if isScheduled(tracking) then return Scheduled.info(tracking.key).description end
    if isRaven(tracking) then return Raven.DESCRIPTION end
    if tracking and tracking.category == "Tasks" then return Tasks.description(tracking.variable) end
    if tracking and tracking.category == "Ports" then return Ports.description(tracking.key) end
    if tracking and tracking.category == "Quests" then return Quests.description(tracking.key) end
    if tracking and tracking.category == "Gathering" then return Mining.description(tracking.key) end
    if tracking and tracking.category == "Training" and Floors.isKey(tracking.variable) then return Floors.describe(tracking.variable) end
    if tracking and isProd(tracking.category) then return Production.description(tracking.key) end
    if tracking and tracking.category == "Invention" then return Invention.description(tracking.key) end
    if tracking and tracking.category == "Slayer" then return Slayer.description(tracking.key) end
    if tracking and tracking.category == "Unlocks" and not tracking.items and Cheevos.isKey(tracking.key) then
        local title = Cheevos.titleDescription(tracking.key)
        if title then return title end
    end
    return tracking and tracking.category == "Combat" and Combat.description(tracking.variable) or nil
end

-- A title note's name with all of the game's colours in it, or nil.
function Tracking.TitleMarkup(tracking)
    if tracking and tracking.category == "Unlocks" and not tracking.items and Cheevos.isKey(tracking.key) then
        return Cheevos.titleNameMarkup(tracking.key)
    end
end

-- The colour (RRGGBB) a title note's name is shown in, or nil.
function Tracking.TitleColour(tracking)
    if tracking and tracking.category == "Unlocks" and not tracking.items and Cheevos.isKey(tracking.key) then
        return Cheevos.titleColour(tracking.key)
    end
end

function Tracking.ComponentPerks(tracking)
    if not tracking or tracking.category ~= nil and tracking.category ~= "Invention" then return nil end
    if tracking.category == nil and tracking.kind ~= "material" and tracking.kind ~= "blueprint" then return nil end
    return Invention.perks(tracking.key or tracking.variable or tracking.varName)
end

function Tracking.ComponentSources(tracking)
    if not tracking or tracking.category ~= nil and tracking.category ~= "Invention" then return nil end
    if tracking.category == nil and tracking.kind ~= "material" and tracking.kind ~= "blueprint" then return nil end
    return Invention.sources(tracking.key or tracking.variable or tracking.varName)
end

-- A quest's hover text split into body and item rows (for the icon tooltip), or nil.
local codexRows -- defined with the title badge below
function Tracking.QuestTooltip(tracking)
    if tracking and tracking.category == "Quests" and tracking.key then return Quests.rich(tracking.key) end
    if tracking and tracking.category == "Slayer" and SlayerTask.isTask(tracking.key) then
        local card = SlayerTask.Card(tracking.key)
        local rows, signature = codexRows(tracking.key)
        if card and rows then
            card.codexRows, card.key = rows, card.key .. ":codex:" .. signature
        end
        return card
    end
    if isGoal(tracking) then
        local info = Goals.info(tracking.key)
        local rows = {}
        for _, line in ipairs(Tracking.CrewReward(tracking) or {}) do
            local icon = line.icon
            rows[#rows + 1] = {label = line.text, spriteId = type(icon) == "table" and icon.sprite or nil,
                obj = type(icon) == "number" and icon or nil, scale = line.scale}
        end
        return {key = "goal:" .. tracking.key, body = info and (info.description or info.hint) or "", rewardRows = rows}
    end
    if isCrew(tracking) then
        local rows = {}
        for _, line in ipairs(Tracking.CrewReward(tracking) or {}) do
            local icon = line.icon
            rows[#rows + 1] = {label = line.text, spriteId = type(icon) == "table" and icon.sprite or nil,
                obj = type(icon) == "number" and icon or nil, scale = line.scale}
        end
        return {key = "reaper-crew", body = "Kill every Reaper boss at least once.", rewardRows = rows}
    end
    return nil
end

-- Slayer task notes carry a badge on their title line: an ushabti with a tick or cross for whether the task's monster
-- is in your Slayer Codex. HasTitleBadge says whether a note can show one at all; TitleBadge is the current state
-- ({obj, met, tip}), or nil while there is no task or it isn't a single codex monster.
-- The Slayer Codex is only tracked as a list of souls to capture (no single-monster notes).
function Tracking.CollectionPickerLabel(category, group)
    local name = type(group) == "table" and group.name or group
    if category == "Slayer" and Cheevos.isCodexGroup(name) then return "Souls to Capture", true end
    return "Collection items", false
end

function Tracking.HasTitleBadge(tracking)
    return type(tracking) == "table" and tracking.category == "Slayer" and tracking.key == "task:slayer" and not tracking.items
end

function Tracking.TitleBadge(tracking)
    if not Tracking.HasTitleBadge(tracking) then return nil end
    local task = SlayerTask.Current(tracking.key)
    if not task or task.id == 0 or (task.left or 0) <= 0 then return nil end
    local codex = Cheevos.codexForTask(task.id)
    if not codex then return nil end
    -- A family of monsters (gemstone dragons) is ticked once every one of them is captured.
    local done = 0
    for _, monster in ipairs(codex) do
        if monster.captured == nil then return nil end
        if monster.captured then done = done + 1 end
    end
    if #codex == 1 then
        return { obj = Cheevos.USHABTI_OBJECT, met = done == 1,
            tip = codex[1].name .. (done == 1 and ": captured for your Slayer Codex" or ": not captured for your Slayer Codex yet") }
    end
    return { obj = Cheevos.USHABTI_OBJECT, met = done == #codex,
        tip = "Slayer Codex: " .. done .. " / " .. #codex .. " of this task's monsters captured" }
end

-- The Slayer Codex rows of a task's hover card: each of the task's codex monsters with a tick or a cross.
codexRows = function(key)
    if key ~= "task:slayer" then return nil end
    local task = SlayerTask.Current(key)
    if not task or task.id == 0 or (task.left or 0) <= 0 then return nil end
    local codex = Cheevos.codexForTask(task.id)
    if not codex then return nil end
    local tick, cross = Sprites.spriteByName("AIF_TICK_CROSS_ICON_0"), Sprites.spriteByName("AIF_TICK_CROSS_ICON_1")
    local rows, signature = {}, {}
    for _, monster in ipairs(codex) do
        local state = monster.captured == true and "Captured" or monster.captured == false and "Not captured" or "Unknown"
        rows[#rows + 1] = { spriteId = monster.captured and tick or cross, label = monster.name .. " - " .. state }
        signature[#signature + 1] = state:sub(1, 1)
    end
    return rows, table.concat(signature)
end

-- Skill / quest requirements of a task, each flagged met or not (Tasks only).
function Tracking.Requirements(tracking)
    -- One Memorial to Guthix passive effect: the Divination level it needs.
    if tracking and tracking.category == "Unlocks" and (tracking.group == Cheevos.HOG_GROUP or tracking.group == Cheevos.HOM_GROUP) then
        local child = tracking.items and #tracking.items == 1 and tracking.items[1] or (not tracking.items and tracking) or nil
        return child and Cheevos.isKey(child.key) and Cheevos.requirements(child.key) or {}
    end
    -- One Fort building: the skill levels its tier needs (a Fort collection of several shows none).
    if tracking and tracking.category == "Unlocks" and tracking.group == Fort.GROUP then
        local child = tracking.items and #tracking.items == 1 and tracking.items[1] or (not tracking.items and tracking) or nil
        if child and type(child.key) == "string" and child.key:match("^fort:") then
            return Fort.requirements(child.key, child.target)
        end
        return {}
    end
    -- The Skillcape Rack: the Player Lodge tier it needs, while it isn't built.
    if tracking and tracking.category == "Unlocks" and tracking.group == Camp.GROUP and not tracking.items and Camp.isStandKey(tracking.key) then
        return Camp.standRequirements(tracking.key)
    end
    -- One base camp building: the resources its tier costs.
    if tracking and tracking.category == "Unlocks" and tracking.group == Camp.GROUP then
        local child = tracking.items and #tracking.items == 1 and tracking.items[1] or (not tracking.items and tracking) or nil
        if child and type(child.key) == "string" and child.key:match("^camp%-bld:") then
            return Camp.requirements(child.key, child.target)
        end
        return {}
    end
    -- One Necromancy ability: the souls its tier of the Well asks for.
    if tracking and tracking.category == "Unlocks" and tracking.group == Necromancy.GROUP then
        local child = tracking.items and #tracking.items == 1 and tracking.items[1] or (not tracking.items and tracking) or nil
        if child and type(child.key) == "string" and Necromancy.isKey(child.key) then return Necromancy.requirements(child.key) end
        return {}
    end
    if tracking and tracking.category == "Tasks" then return Tasks.requirements(tracking.variable) end
    if tracking and tracking.category == "Quests" then return Quests.requirements(tracking.key) end
    return {}
end

-- The skill icon of a Production / Gathering group ("Mining: Gems & Ores" -> Mining), or nil.
function Tracking.GroupIcon(category, group)
    if counted(category) and type(group) == "string" then return groupSkillIcon(group) end
    return nil
end

function Tracking.CategoryIcon(category)
    if category == "Scheduled" then return {sprite = id.Sprite.SEPT16_ICON_CALENDAR_1} end
    -- Invention uses the same icon as the Invention skill.
    if category == "Invention" then return Skills.skillIconRef(Skills.SKILL_BY_TYPE.INVENTION) end
    if category == "Slayer" then return Skills.skillIconRef(Skills.SKILL_BY_TYPE.SLAYER) end
    if category == "Gathering" then return Skills.skillIconRef(Skills.SKILL_BY_TYPE.MINING) end
    if category == "Production" then return Skills.skillIconRef(Skills.SKILL_BY_TYPE.SMITHING) end
    if category == "Unlocks" then return Skills.skillIconRef(Skills.SKILL_BY_TYPE.DUNGEONEERING) end
    -- Training (urns and the like): a training sprite if the game has one, else the Crafting icon the urns come from.
    if category == "Training" then return Sprites.categoryIconRef(category) or Skills.skillIconRef(Skills.SKILL_BY_TYPE.CRAFTING) end
    return Sprites.categoryIconRef(category)
end

function Tracking.Selection(tracking)
    if not tracking then return categories[1], Tracking.Groups(categories[1])[1], nil, "" end
    -- Titles used to be picked several at a time; a note holding one title reopens as the single goal it is now.
    if tracking.category == "Unlocks" and tracking.group == Cheevos.TITLES_GROUP and type(tracking.items) == "table"
        and #tracking.items == 1 and type(tracking.items[1]) == "table" and tracking.items[1].key then
        local item = tracking.items[1]
        local single = {}
        for field, value in pairs(tracking) do single[field] = value end
        for field, value in pairs(item) do single[field] = value end
        single.items, single.key, single.target = nil, item.key, item.target or 1
        tracking = single
    end
    local category = categorySet[tracking.category] and tracking.category or categories[1]
    local groups = Tracking.Groups(category)
    local group = groupFrom(category, tracking.group)
    -- A farm note reopens on its animal (the third dropdown).
    if group and group.subs and type(tracking.items) == "table" and tracking.items[1] then
        local firstKey = tracking.items[1].key
        local animal = group.name == Camp.GROUP and (Camp.sectionOf(tracking.items[1].key)
                or Unlocks.entry(group.name, tracking.items[1].key) and Camp.FARM_SHOP)
            or (group.name == Relics.GROUP or group.name == Necromancy.GROUP or group.name == Cheevos.GIM_GROUP or group.name == Cheevos.HOG_GROUP or group.name == Cheevos.PRIF_GROUP or group.name == Cheevos.VARROCK_GROUP or group.name == Cheevos.MUSIC_GROUP or group.name == Cheevos.TITLES_GROUP or group.name == Cheevos.HOM_GROUP) and Cheevos.isKey(firstKey) and Cheevos.sectionOf(firstKey)
            or group.name == Relics.GROUP and type(firstKey) == "string" and (Relics.info(firstKey) and "Relics" or Unlocks.entry(group.name, firstKey) and Clues.SHOP_SECTION)
            or group.name == Necromancy.GROUP and Necromancy.isKey(firstKey) and "Abilities"
            or Arch.isGroup(group.name) and Arch.collectionOf(tracking.items[1].key) or Goals.animalOf(tracking.items[1].key)
        if animal then group = {name = group.name, key = group.key, label = group.label, subs = group.subs, subLabel = group.subLabel, sub = animal} end
    elseif group and group.subs and type(tracking.key) == "string" then
        -- A note tracking a single goal carries its key itself: Archaeology (Relics / Qualifications / Research / Mysteries /
        -- Reward Shop) and Necromancy (Kili's Knowledge) reopen on the goal's section.
        local key = tracking.key
        local section = (group.name == Relics.GROUP or group.name == Necromancy.GROUP or group.name == Cheevos.GIM_GROUP or group.name == Cheevos.HOG_GROUP or group.name == Cheevos.PRIF_GROUP or group.name == Cheevos.VARROCK_GROUP or group.name == Cheevos.MUSIC_GROUP or group.name == Cheevos.TITLES_GROUP or group.name == Cheevos.HOM_GROUP) and Cheevos.isKey(key) and Cheevos.sectionOf(key)
            or group.name == Relics.GROUP and (Relics.info(key) and "Relics" or Unlocks.entry(group.name, key) and Clues.SHOP_SECTION)
            or group.name == Necromancy.GROUP and Necromancy.isKey(key) and "Abilities"
            or group.name == Camp.GROUP and (Camp.sectionOf(key) or Unlocks.entry(group.name, key) and Camp.FARM_SHOP)
            or group.name == Cheevos.VARROCK_GROUP and key == Cheevos.KUDOS_KEY and Cheevos.KUDOS_SECTION
            or nil
        if section and group.name == Cheevos.TITLES_GROUP then section = section:gsub("^titles:", "") end
        if section then group = {name = group.name, key = group.key, label = group.label, subs = group.subs, subLabel = group.subLabel, sub = section} end
    end
    local derivedGroup = group and group.sub and group or nil
    local option
    local function find(candidate)
        for _, entry in ipairs(Tracking.Options(category, candidate)) do
            if sameOption(tracking, category, entry) then return entry end
        end
    end
    if group or #groups == 0 then option = find(group) end
    if not option and group and group.sub and type(tracking.key) == "string" and Cheevos.isKey(tracking.key) then
        -- A goal that is finished (or whose state isn't known yet) is left out of the list but is still the one saved: keep it.
        local extra = Cheevos.optionOf(tracking.key)
        if extra then
            option = extra
            local cacheKey = category .. ":" .. group.name .. "/" .. group.sub
            optionCache[cacheKey] = optionCache[cacheKey] or {}
            table.insert(optionCache[cacheKey], option)
        end
    end
    if not option then
        for _, candidate in ipairs(groups) do
            option = find(candidate)
            if option then group = candidate break end
        end
    end
    if option and option.savedTracking then
        option.savedTracking = Tracking.Normalize(tracking)
        option.label = tracking.label or tracking.variable
        option.skill, option.varName = tracking.skill, tracking.variable
        option.iconObj, option.iconSprite, option.noIcon = tracking.iconObj, tracking.iconSprite, tracking.noIcon
        option.description = Tracking.Description(tracking)
    end
    if not option then
        group = group or groups[1]
        local saved = Tracking.Normalize(tracking)
        if saved then
            option = {key = saved.key or "saved:" .. (saved.skill or saved.variable), label = saved.label or saved.variable,
                kind = saved.skill and "skill" or "saved", savedTracking = saved, skill = saved.skill,
                varName = saved.variable, iconObj = saved.iconObj, iconSprite = saved.iconSprite,
                noIcon = saved.noIcon, description = Tracking.Description(saved)}
            local cacheKey = category .. ":" .. (group and group.name or "")
            optionCache[cacheKey] = optionCache[cacheKey] or {}
            optionCache[cacheKey][#optionCache[cacheKey] + 1] = option
        end
    end
    local target = tracking.target
    if not bossLike(category) and tracking.items then target = tracking.items[1].target end
    local targetText = tostring(target)
    if category == "Bossing" and option and option.kind == "kills" and tracking.target == 1 and tracking.base ~= nil then
        targetText = ""
    end
    if not tracking.items and Timers.isVar(tracking.variable) then targetText = Timers.format(target, tracking.variable) end
    group = group or groups[1]
    if derivedGroup and group and group.name == derivedGroup.name then group = derivedGroup end
    return category, group, option, targetText
end

function Tracking.FromLegacy(note)
    if type(note) ~= "table" then return nil, "Invalid saved Notes-Plus note." end
    local category = type(note.category) == "string" and note.category or ""
    if category == "Combat Achievements" then category = "Combat" end
    if note.skill then category = "Skills" end
    if not note.skill and (type(note.variable) ~= "string" or note.variable == "") then return nil, nil, category end
    if category == "" and tostring(note.variable):match("^BSLAY_KILLS_") then category = "Bossing" end
    if category == "" and tostring(note.variable):match("^BPETS_") then category = "Bossing" end
    if category == "" and tostring(note.variable):match("^ITEMLOG_ITEM_") then category = "Bossing" end
    if category == "" then category = "Tracking" end
    local saved = {}
    for _, key in ipairs({"variable", "varId", "target", "skill", "base", "vars", "ownedVar", "iconObj", "iconSprite", "noIcon"}) do
        saved[key] = note[key]
    end
    saved.category = category
    saved.label = tostring(note.text or ""):gsub("[%z\1-\31\127]", " "):sub(1, 300)
    if saved.label == "" then saved.label = tostring(note.variable or note.skill or "Tracking") end
    saved.target = tonumber(saved.target) or 1
    if saved.target <= 0 then saved.target = 1 end
    saved.varId = saved.varId and tonumber(saved.varId) or nil
    saved.iconObj = saved.iconObj and tonumber(saved.iconObj) or nil
    saved.base = saved.base and tonumber(saved.base) or nil
    local tracking, message = Tracking.Normalize(saved)
    return tracking, tracking and saved.label or message, category
end

function Tracking.Poll(skipSpriteDiscovery, elapsed)
    if not skipSpriteDiscovery then Sprites.poll() end
    local ok = pcall(Bossing.indexStep)
    if not ok then Bossing.giveUpIndexing() end
    local changed = Clock.Tick(elapsed)
    return Scheduled.Poll(elapsed) or changed
end

function Tracking.IconRevision()
    return Sprites.revision()
end

-- Imported notes may only track variables Notes+ itself uses. A name is accepted when
--   1. it is carried by an option the plugin lists (the fields that hold variables; rebuilt when a name is missed, because
--      some lists, such as the boss kill counts, fill in as game data loads), or
--   2. it is in the generated list of every variable the tracking features and data name (or is a kill count / item log
--      entry made from one), or belongs to one of the families the features build their names from, AND it is a real game
--      variable. Sprite, object and other names never are.
-- Anything else is refused.
local allowedNames, rebuilds
local VARIABLE_FIELDS = {varName = true, variable = true, var = true, vars = true, taskVars = true, owned = true,
    ownedVar = true, currencyVar = true, unlocked = true, acquired = true}
-- Names the features build from game data at run time (prefix + row name + suffix); each must also resolve to a real variable.
local FAMILIES = {"^INVENT_BLUEPRINT_UNLOCKED_%d+$", "^ARCH_RELIC_[A-Z0-9_]+_UNLOCKED$",
    "^ARCH_RELIC_[A-Z0-9_]+_ACQUIRED$", "^PLAYER_FORT_[A-Z0-9_]+$", "^DINO_BASE_CAMP_[A-Z0-9_]+$",
    "^COMBATV2_ABILITY_NECROMANCY_[A-Z0-9_]+_UNLOCKED$", "^RAND_[A-Z0-9_]+_FASTEST_TIME[A-Z_]*$",
    "^TRH103_WARPED_[A-Z0-9_]+_OWNED$", "^WOODCUTTING_WOODBOX_[A-Z0-9_]+$", "^SKILL_[A-Z0-9_]+$",
    "^COLLECTION_SLAYER_[A-Z0-9_]+$", "^BSLAY_[A-Z0-9_]+$", "^POUCH:[A-Z0-9_]+$", "^SKILLPETS_[A-Z0-9_]+$",
    "^GROUP_IRONMAN_[A-Z0-9_]+$", "^HOG_[A-Z0-9_]+$", "^BOSS_INSTANCE_SCORES_[A-Z0-9_]+$"}
local knownNames

local function addNames(set, value, depth, seen, collecting)
    if type(value) == "string" then
        if collecting then
            set[value:upper()] = true
            local base = value:match("^(.-)>=%d+$")
            if base then set[base:upper()] = true end
        end
    elseif type(value) == "table" and depth < 6 and not seen[value] then
        seen[value] = true
        for key, inner in pairs(value) do
            addNames(set, inner, depth + 1, seen, collecting or (type(key) == "string" and VARIABLE_FIELDS[key] == true))
        end
    end
end

local function knownVariables()
    if knownNames then return knownNames end
    local set = {}
    local data = require("src/tracking/data/known_variables")
    for name in tostring(type(data) == "table" and data.names or data):gmatch("[^\n]+") do set[name:upper()] = true end
    knownNames = set
    return set
end

local function allowedVariables()
    if allowedNames then return allowedNames end
    local set, seen = {}, {}
    local function scan(category, group)
        local ok, options = pcall(Tracking.Options, category, group)
        if ok and type(options) == "table" then addNames(set, options, 0, seen, false) end
    end
    for _, category in ipairs(categories) do
        scan(category, nil)
        local ok, groups = pcall(Tracking.Groups, category)
        for _, group in ipairs(ok and type(groups) == "table" and groups or {}) do
            if type(group) == "table" and group.name then
                scan(category, {name = group.name})
                for _, sub in ipairs(group.subs or {}) do
                    if type(sub) == "table" and sub.name then scan(category, {name = group.name, sub = sub.name}) end
                end
            end
        end
    end
    addNames(set, Unlocks.variables(), 0, seen, true)
    local okClues, shop = pcall(Clues.shopUnlocks)
    if okClues then addNames(set, shop, 0, seen, true) end
    allowedNames = set
    return set
end

-- 1 = written out in the generated list; 2 = made from one (kill count / item log entry) or in a family, so it must also
-- be a real game variable; nil = not ours.
local function knownKind(base)
    local known = knownVariables()
    if known[base] then return 1 end
    local suffix = base:match("^BSLAY_KILLS_(.+)$") or base:match("^ITEMLOG_ITEM_(.+)$")
    if suffix and known[suffix] then return 2 end
    for _, family in ipairs(FAMILIES) do
        if base:match(family) then return 2 end
    end
    return nil
end

local function variableAllowed(name, allowed)
    local base = (name:match("^(.-)>=%d+$") or name):upper()
    if allowed[base] then return true end
    local kind = knownKind(base)
    if kind == 1 or base:sub(1, 6) == "POUCH:" and kind ~= nil then return true end
    if kind == nil then return false end
    return Vars.resolveVar(name:match("^(.-)>=%d+$") or name) ~= nil
end

-- Names the plugin's own option lists produce that the generated list lacks (empty when the list is complete).
function Tracking.MissingKnownVariables()
    local missing = {}
    for name in pairs(allowedVariables()) do
        if knownKind(name) ~= 1 then missing[#missing + 1] = name end
    end
    table.sort(missing)
    return missing
end

local function checkVariables(tracking, allowed)
    local names = {tracking.variable, tracking.ownedVar}
    for _, name in ipairs(tracking.vars or {}) do names[#names + 1] = name end
    for _, name in ipairs(names) do
        if type(name) == "string" and name ~= "" and not variableAllowed(name, allowed) then
            return false, "Import blocked: this note tracks a variable Notes+ does not allow (" .. name:sub(1, 60) .. ")."
        end
    end
    if tracking.variable and tracking.varId and tracking.variable ~= "" then
        local _, _, resolvedId = Vars.resolveVar(tracking.variable)
        if resolvedId ~= nil and resolvedId ~= tracking.varId then return false, "This note has a variable id that does not match its variable." end
    end
    return true
end

-- Whether an imported (already normalised) tracking only uses variables Notes+ offers; false and a message when not.
local function checkPlace(tracking)
    if not categorySet[tracking.category] then return false, "This note tracks a type Notes+ does not offer." end
    local group = tracking.group
    if group == nil or Registry.GROUPS[group] ~= nil then return true end
    local groups = Tracking.Groups(tracking.category)
    if #groups == 0 then return true end
    for _, entry in ipairs(groups) do
        if entry.name == group or entry.key == group then return true end
    end
    return false, "This note tracks a group Notes+ does not offer (" .. tostring(group):sub(1, 40) .. ")."
end

function Tracking.CheckImported(tracking)
    if type(tracking) ~= "table" then return true end
    local placed, placeMessage = checkPlace(tracking)
    if not placed then return false, placeMessage end
    local function checkAll()
        local allowed = allowedVariables()
        local ok, message = checkVariables(tracking, allowed)
        if not ok then return false, message end
        for _, item in ipairs(tracking.items or {}) do
            ok, message = checkVariables(item, allowed)
            if not ok then return false, message end
        end
        return true
    end
    local ok, message = checkAll()
    if not ok and (rebuilds or 0) < 3 then
        -- Some option lists fill in as game data loads: look again with fresh lists before refusing.
        rebuilds = (rebuilds or 0) + 1
        allowedNames = nil
        ok, message = checkAll()
    end
    return ok, message
end

function Tracking.Reset()
    allowedNames, rebuilds = nil, nil
    entryCache = {}
    optionCache = {}
    goalItems, crewItems = {}, nil
    Goals.Clear()
    Journal.Clear()
    Clock.Clear()
    Raven.Clear()
    Cheevos.Clear()
    Scheduled.Clear()
    ReaperCrew.Clear()
    for key in pairs(Objects.objectNameCache) do Objects.objectNameCache[key] = nil end
    for key in pairs(Combat.cache) do Combat.cache[key] = nil end
    Bossing.resetIndexing()
    Sprites.reset()
    Skills.resetIcons()
end

return Tracking
