-- Unlocks: things you buy once with a currency (reward-shop upgrades, recipes, scrolls). Each shop is a group; each unlock
-- is tracked as your balance of that shop's currency towards its price, and completes when you own it.
--
-- The shops' own item lists in the game (their REWARDSHOP_ITEM_LIST enum) supply the names, prices and objects, so new
-- unlocks show up by themselves. What the game doesn't tell us is the variable that says you already own one, so those
-- are kept here (OWNED, keyed by the unlock's struct name). Anything without one still tracks the balance against the price.

local ConfigReader = require("src/tracking/core/config_reader")

local Vars = require("src/tracking/core/vars")
local ReaperCrew = require("src/tracking/features/reaper_crew").ReaperCrew
local Goals = require("src/tracking/features/achievement_goals").AchievementGoals
local Journals = require("src/tracking/features/journals")
local Objects = require("src/tracking/core/objects")
local Raven = require("src/tracking/features/prif_raven").PrifRaven
local Necromancy = require("src/tracking/features/necromancy").Necromancy

local RewardShops = require("src/tracking/data/reward_shops").SHOPS

local Unlocks = {}

-- True when the variable that marks this unlock as bought says you have it.
local function isOwned(varName)
    if not varName then return false end
    -- "VAR>=N": a tier variable, owned once it reaches N.
    local base, minimum = varName:match("^(.-)>=(%d+)$")
    local ok, value = pcall(function() return Vars.readEntry(Vars.resolveVar(base or varName)) end)
    return ok and type(value) == "number" and value >= (tonumber(minimum) or 1)
end

-- False when this is a later tier (VAR>=N, N above 1) and the tier before it isn't owned yet, so it can't be bought yet.
-- Unreadable variables don't hide anything.
local function isAvailable(varName)
    local base, minimum = (varName or ""):match("^(.-)>=(%d+)$")
    minimum = tonumber(minimum)
    if not base or not minimum or minimum <= 1 then return true end
    local ok, value = pcall(function() return Vars.readEntry(Vars.resolveVar(base)) end)
    if not ok or type(value) ~= "number" then return true end
    return value >= minimum - 1
end

-- Shops: the name shown, the struct of the shop in the game, the currency variable and the item shown for it.
local SHOPS = {
    {
        name = "Daemonheim", struct = "RAND_REWARDS_SHOP", currencyVar = "RAND_REWARD_TOKENS", currencyName = "tokens",
        currencyObj = id.Obj.RAND_COINS,
        skip = { "RAND_REWARDS_SHOP_DUNGEONEERING_EXPERIENCE" },
        discounted = true,
        -- Used as is when the game's list can't be read. owned = the variable that says you have it.
        base = {
            { struct = "DUNGEON_ULTHVEN_REWARD_STRUCT_BANK_UNLOCK", name = "Elite dungeon chest upgrade", cost = 750000, owned = "DUNGEON_CHEST_UPGRADE_UNLOCKED" },
            { struct = "DUNGEON_ULTHVEN_REWARD_STRUCT_ARROW_UNLOCK", name = "Recipe: Black stone arrows", cost = 350000, owned = "DUNGEON_REWARD_SHOP_ULTHVEN_ARROW_UNLOCKED" },
            { struct = "DUNGEON_ULTHVEN_REWARD_STRUCT_ABILITY_BOOK_UNDEAD_UNLOCK", name = "Undead slayer ability codex blueprint", cost = 100000, owned = "DUNGEON_REWARD_SHOP_ABILITY_BOOK_UNDEAD_UNLOCKED" },
            { struct = "DUNGEON_ULTHVEN_REWARD_STRUCT_ABILITY_BOOK_DRAGON_UNLOCK", name = "Dragon slayer ability codex blueprint", cost = 100000, owned = "DUNGEON_REWARD_SHOP_ABILITY_BOOK_DRAGON_UNLOCKED" },
            { struct = "DUNGEON_ULTHVEN_REWARD_STRUCT_ABILITY_BOOK_DEMON_UNLOCK", name = "Demon slayer ability codex blueprint", cost = 100000, owned = "DUNGEON_REWARD_SHOP_ABILITY_BOOK_DEMON_UNLOCKED" },
            { struct = "DUNGEON_REWARD_STRUCT_CORRUPTION_SCROLL", name = "Scrimshaw of corruption+ scroll", cost = 250000, owned = "DUNGEON_REWARD_SHOP_SCRIMSHAW_CORRUPTION_UNLOCK" },
            { struct = "DUNGEON_REWARD_STRUCT_SACRIFICE_SCROLL", name = "Scrimshaw of sacrifice+ scroll", cost = 250000, owned = "DUNGEON_REWARD_SHOP_SCRIMSHAW_SACRIFICE_UNLOCK" },
            { struct = "DUNGEON_REWARD_STRUCT_AGGRESSION_SCROLL", name = "Scrimshaw of aggression+ scroll", cost = 250000, owned = "DUNGEON_REWARD_SHOP_SCRIMSHAW_AGGRESSION_UNLOCK" },
            { struct = "DUNGEON_REWARD_STRUCT_DG_DOOR_BOOST", name = "Daemonheim skill door boost", cost = 600000, owned = "DUNGEON_REWARD_SHOP_DG_DOOR_BOOST_UNLOCK" },
            { struct = "DUNGEON_REWARD_STRUCT_ELITE_DG_OUTFIT_BLUEPRINT", name = "Gorajan trailblazer outfit blueprint", cost = 100000, owned = "DUNGEON_REWARD_SHOP_ELITE_DG_OUTFIT_UNLOCK" },
            { struct = "DUNGEON_REWARD_STRUCT_NOTEPAPER_BLUEPRINT", name = "Notepaper blueprint", cost = 200000, owned = "DUNGEON_REWARD_SHOP_NOTEPAPER_UNLOCK" },
            { struct = "RAND_REWARDS_SHOP_DUNGEONEERING_SKILL_BOOSTER", name = "Scroll of gathering", cost = 80000, owned = "OCT18_RAND_GATHERING_SKILL_BOOSTER_UNLOCKED" },
            { struct = "RAND_REWARDS_SHOP_QUICK_TELEPORT_REWARD", name = "Scroll of quick teleportation", cost = 50000, owned = "RAND_REWARD_QUICK_TELE_UNLOCKED" },
            { struct = "RAND_REWARDS_SHOP_ARCHAEOLOGY_SCROLL", name = "Scroll of restoration", cost = 20000, owned = "RAND_REWARD_ARCHAEOLOGY_SCROLL" },
            { struct = "RAND_REWARDS_SHOP_CRAFTING_SCROLL", name = "Scroll of dexterity", cost = 20000, owned = "RAND_REWARD_CRAFTING_SCROLL" },
            { struct = "RAND_REWARDS_SHOP_CONSTRUCTION_SCROLL", name = "Scroll of proficiency", cost = 20000, owned = "RAND_REWARD_CONSTRUCTION_SCROLL" },
            { struct = "RAND_REWARDS_SHOP_RAPID_RENEWAL_UNLOCKER", name = "Scroll of renewal", cost = 38000, owned = "RAND_REWARD_RAPID_RENEWAL_PRAYER" },
            { struct = "RAND_REWARDS_SHOP_WASTELESS_SMITHING_UNLOCKER", name = "Scroll of efficiency", cost = 20000, owned = "RAND_WASTELESS_SMITHING" },
            { struct = "RAND_REWARDS_SHOP_WASTELESS_HERBLORE_UNLOCKER", name = "Scroll of cleansing", cost = 20000, owned = "RAND_WASTELESS_HERBLORE" },
            { struct = "RAND_REWARDS_SHOP_FARMING_CONSERVATION_UNLOCKER", name = "Scroll of life", cost = 10000, owned = "RAND_REWARD_FARMING_CONSERVATION" },
            { struct = "RAND_REWARDS_SHOP_WILD_CARD_SINKHOLES", name = "Wild card", cost = 20000, owned = "RAND_REWARD_WILD_CARD_SINKHOLES" },
            { struct = "RAND_REWARDS_CONSTRUCTION_HOUSE_ROOM_FLOOR_STYLE_TILE_TEMPLE_BLUEPRINT", name = "Floor plans: Temple tile", cost = 50000, owned = "CONSTRUCTION_HOUSE_ROOM_FLOOR_STYLE_TILE_TEMPLE_RECIPE_UNLOCKED" },
            { struct = "RAND_REWARDS_CONSTRUCTION_DUNGEONEERING_MONOLITH_BLUEPRINT", name = "Furniture plans: Ritual marker", cost = 500000, owned = "CONSTRUCTION_HOUSE_FURNITURE_FUNCTIONAL_DUNGEONEERING_MONOLITH_BLUEPRINT_OWNED" },
            { struct = "RAND_REWARDS_CONSTRUCTION_DUNGEONEERING_MONOLITH_TIED_BLUEPRINT", name = "Furniture plans: Tied ritual marker", cost = 50000, owned = "CONSTRUCTION_HOUSE_FURNITURE_FUNCTIONAL_DUNGEONEERING_MONOLITH_TIED_BLUEPRINT_OWNED" },
            { struct = "RAND_REWARDS_CONSTRUCTION_DUNGEONEERING_MONOLITH_WARPED_BLUEPRINT", name = "Furniture plans: Warped ritual marker", cost = 100000, owned = "CONSTRUCTION_HOUSE_FURNITURE_FUNCTIONAL_DUNGEONEERING_MONOLITH_WARPED_BLUEPRINT_OWNED" },
        },
    },
    {
        -- The Livid Farm's Lunar spells: unlocked one after another (LUNARFM_SPELLS_UNLOCKED counts them) as produce points
        -- reach each spell's amount. Not a game shop list, so the spells are all written out here.
        -- anyTier: every spell not yet unlocked is offered, not only the next one.
        name = "Livid Farm", currencyVar = "LUNARFM_PRODUCE_POINTS", currencyName = "produce points", currencyObj = 42290,
        anyTier = true,
        base = {
            { struct = "MAGIC_TELEPORT_SOUTH_FALADOR", name = "Teleport to South Falador", cost = 10000, sprite = 14444, owned = "LUNARFM_SPELLS_UNLOCKED>=1",
                description = "Unlocked from the Livid Farm at 10,000 produce points." },
            { struct = "MAGIC_REPAIR_POUCH", name = "Repair Rune Pouch", cost = 20000, sprite = 14445, owned = "LUNARFM_SPELLS_UNLOCKED>=2",
                description = "Unlocked from the Livid Farm at 20,000 produce points." },
            { struct = "MAGIC_NORTH_ARDOUGNE", name = "Teleport to North Ardougne", cost = 35000, sprite = 14446, owned = "LUNARFM_SPELLS_UNLOCKED>=3",
                description = "Unlocked from the Livid Farm at 35,000 produce points." },
            { struct = "MAGIC_REMOTE_FARM", name = "Remote Farming", cost = 45000, sprite = 14447, owned = "LUNARFM_SPELLS_UNLOCKED>=4",
                description = "Unlocked from the Livid Farm at 45,000 produce points." },
            { struct = "MAGIC_SPIRITUAL_HEALING", name = "Spiritualise Food", cost = 60000, sprite = 14449, owned = "LUNARFM_SPELLS_UNLOCKED>=5",
                description = "Unlocked from the Livid Farm at 60,000 produce points." },
            { struct = "MAGIC_MAKE_LEATHER", name = "Make Leather", cost = 75000, sprite = 14448, owned = "LUNARFM_SPELLS_UNLOCKED>=6",
                description = "Unlocked from the Livid Farm at 75,000 produce points." },
            { struct = "MAGIC_DISRUPTION_SHIELD", name = "Disruption Shield", cost = 90000, sprite = 14450, owned = "LUNARFM_SPELLS_UNLOCKED>=7",
                description = "Unlocked from the Livid Farm at 90,000 produce points." },
            { struct = "MAGIC_VENGEANCE_GROUP", name = "Vengeance Group", cost = 100000, sprite = 14451, owned = "LUNARFM_SPELLS_UNLOCKED>=8",
                description = "Unlocked from the Livid Farm at 100,000 produce points." },
            { struct = "MAGIC_TELEPORT_TROLLHEIM_FARM", name = "Teleport to Trollheim", cost = 110000, sprite = 14453, owned = "LUNARFM_SPELLS_UNLOCKED>=9",
                description = "Unlocked from the Livid Farm at 110,000 produce points. Also needs the quest 'My Arm's Big Adventure'." },
            { struct = "MAGIC_TELE_GROUP_TROLLHEIM", name = "Teleport Group to Trollheim", cost = 120000, sprite = 14454, owned = "LUNARFM_SPELLS_UNLOCKED>=10",
                description = "Unlocked from the Livid Farm at 120,000 produce points. Also needs the quest 'My Arm's Big Adventure'." },
            { struct = "MAGIC_BORROWED_POWER", name = "Borrowed Power", cost = 130000, sprite = 12509, owned = "LUNARFM_SPELLS_UNLOCKED>=11",
                description = "Unlocked from the Livid Farm at 130,000 produce points." },
        },
    },
}


-- Ownership variables for unlocks the game lists but the base above doesn't cover (struct name -> variable). None known yet.
local OWNED = {}

local resolved, groupNames, byGroup, source, discountedGroups = nil, nil, nil, nil, {}
local parents = {}

-- Owning every piece of the Warped outfit takes 7% off Daemonheim prices for good.
local WARPED_PIECES = { "FEET", "LEGS", "HANDS", "BODY", "HEAD" }
Unlocks.WARPED_DISCOUNT = 0.07
function Unlocks.warpedDiscount()
    for _, part in ipairs(WARPED_PIECES) do
        local ok, value = pcall(function() return Vars.readEntry(Vars.resolveVar("TRH103_WARPED_" .. part .. "_OWNED")) end)
        if not ok or value ~= 1 then return false end
    end
    return true
end

local function number(value) return type(value) == "number" and value == value and value or nil end
-- Game text can carry its own markup (line breaks, colours): breaks become new lines and the rest is dropped.
local function text(value)
    if type(value) ~= "string" or value == "" or value == "null" then return nil end
    return (value:gsub("<[Bb][Rr]%s*/?>", "\n"):gsub("</?[%w=#]+[^>]*>", ""))
end

local function objId(value)
    local direct = number(value)
    if direct then return direct >= 0 and direct or nil end
    if value == nil then return nil end
    local fromObject = number(ConfigReader.Field(value, "id"))
    return fromObject and fromObject >= 0 and fromObject or nil
end

local function structOf(value)
    if type(value) == "number" then return value >= 0 and ConfigReader.Struct(value) or nil end
    if value == nil then return nil end
    if ConfigReader.Field(value, "configName") ~= nil then return value end
    local structId = ConfigReader.Field(value, "id")
    return type(structId) == "number" and ConfigReader.Struct(structId) or nil
end

local function item(shop, entry)
    -- The picture the shop itself shows for this unlock: its own icon sprite, else the object it hands over.
    if ConfigReader.Available() and entry.struct and not entry.sprite then
        local struct = ConfigReader.Struct(entry.struct)
        if struct then
            local icon = number(ConfigReader.StructParam(struct, "REWARDSHOP_ICON"))
            if icon and icon > 0 then entry.sprite = icon end
            entry.obj = entry.obj or objId(ConfigReader.StructParam(struct, "REWARDSHOP_OBJ"))
        end
    end
    return {
        kind = "piece", key = (entry.struct or entry.name), label = entry.name, group = shop.name,
        piece = { name = entry.name, sprite = entry.sprite, obj = entry.obj or (not entry.sprite and shop.currencyObj or nil), cost = entry.cost, owned = entry.owned,
            currencyVar = shop.currencyVar, currencyName = shop.currencyName, noBalance = shop.noBalance, anyTier = shop.anyTier },
        description = entry.description,
    }
end

-- One of the game's reward shops: the unlock-type items of the tabs asked for, with the game's own names and prices.
local function gameShop(shop)
    local list = {}
    if not ConfigReader.Available() then return list end
    local struct = ConfigReader.Struct(shop.struct)
    local enum = struct and ConfigReader.StructParam(struct, "REWARDSHOP_ITEM_LIST")
    local pairsList = enum and ConfigReader.EnumPairs(enum) or {}
    if #pairsList == 0 then return list end
    source = "game"
    -- The list is one long list with a gap between each tab.
    local sections, current = {}, nil
    for _, pair in ipairs(pairsList) do
        local itemStruct = structOf(pair[2])
        local structName = itemStruct and ConfigReader.Field(itemStruct, "configName")
        structName = type(structName) == "string" and structName:upper() or nil
        if not itemStruct or not structName or structName == "UNKNOWN" then
            current = nil
        else
            if not current then current = { items = {} }; sections[#sections + 1] = current end
            current.items[#current.items + 1] = { struct = itemStruct, name = structName }
        end
    end
    local wanted
    if shop.tabs then
        wanted = {}
        for _, tab in ipairs(shop.tabs) do wanted[tab:lower()] = true end
    end
    local skip = {}
    for _, name in ipairs(shop.skip or {}) do skip[name] = true end
    local tabCount = 0
    while text(ConfigReader.StructParam(struct, "REWARDSHOP_TAB" .. (tabCount + 1))) do tabCount = tabCount + 1 end
    for index, section in ipairs(sections) do
        local tab = text(ConfigReader.StructParam(struct, "REWARDSHOP_TAB" .. index))
        -- When the game's tabs don't line up with its list, every tab is offered rather than none.
        local offered = not wanted or #sections ~= tabCount or tab and wanted[tab:lower()]
        if offered then
            for _, entry in ipairs(section.items) do
                local name = text(ConfigReader.StructParam(entry.struct, "REWARDSHOP_ITEM_NAME"))
                local cost = number(ConfigReader.StructParam(entry.struct, "REWARDSHOP_COST"))
                -- Items named only by the object they hand over (the Archaeology outfits) take the object's name.
                if not name then
                    local given = objId(ConfigReader.StructParam(entry.struct, "REWARDSHOP_OBJ"))
                    local ok, objectName = pcall(Objects.objectDisplayName, given)
                    if given and ok then name = text(objectName) end
                end
                local repeatable = ConfigReader.StructParam(entry.struct, "REWARDSHOP_BUY_OPTION_2") ~= nil
                local owned = shop.owned and shop.owned[entry.name]
                if name and cost and cost > 0 and not repeatable and not skip[entry.name] and (owned or not shop.noBalance)
                    and (owned or not shop.onlyOwned) then
                    local obj = objId(ConfigReader.StructParam(entry.struct, "REWARDSHOP_OBJ"))
                    list[#list + 1] = item(shop, { struct = entry.name, name = name, cost = cost, obj = obj, owned = owned,
                        description = text(ConfigReader.StructParam(entry.struct, "REWARDSHOP_TOOLTIP")) })
                end
            end
        end
    end
    return list
end

local function resolve()
    if resolved then return end
    resolved = true
    groupNames, byGroup, source = {}, {}, "snapshot"
    for _, shop in ipairs(SHOPS) do
        local list, seen = {}, {}
        for _, entry in ipairs(shop.base) do
            seen[entry.struct] = true
            list[#list + 1] = item(shop, entry)
        end
        -- Everything else the game's own list for this shop holds that is a one-time unlock, from every tab.
        for _, entry in ipairs(not shop.struct and {} or gameShop({ struct = shop.struct, name = shop.name, currencyVar = shop.currencyVar, currencyName = shop.currencyName,
                currencyObj = shop.currencyObj, skip = shop.skip, owned = OWNED })) do
            if not seen[entry.key] then
                seen[entry.key] = true
                list[#list + 1] = entry
            end
        end
        if #list > 0 then
            groupNames[#groupNames + 1] = shop.name
            byGroup[shop.name] = list
            if shop.discounted then discountedGroups[shop.name] = true end
        end
    end
    -- The other reward shops, straight from the game's lists.
    for _, shop in ipairs(RewardShops) do
        local list = gameShop(shop)
        if #list > 0 then
            -- A shop with a parent is a section of another group (Archaeology > Reward Shop), not a group of its own.
            if not shop.parent then groupNames[#groupNames + 1] = shop.name end
            byGroup[shop.name] = list
            if shop.parent then parents[shop.name] = shop.parent end
        end
    end
end

function Unlocks.source()
    resolve()
    return source
end

function Unlocks.groups()
    resolve()
    local list = {}
    -- Combat goals that come from the game's own lists rather than a shop.
    if ReaperCrew.bosses() or #Goals.options(Goals.GROUP) > 0 then list[#list + 1] = { name = ReaperCrew.GROUP } end
    if #Goals.options(Goals.CAPES) > 0 then list[#list + 1] = { name = Goals.CAPES } end
    if #Goals.options(Goals.SKILLING) > 0 then list[#list + 1] = { name = Goals.SKILLING } end
    if #Goals.options(Goals.LOGS) > 0 then list[#list + 1] = { name = Goals.LOGS } end
    for _, group in ipairs(Journals.groups()) do list[#list + 1] = group end
    list[#list + 1] = { name = Raven.GROUP }
    list[#list + 1] = { name = Necromancy.GROUP }
    for _, name in ipairs(groupNames) do list[#list + 1] = { name = name } end
    return list
end

function Unlocks.options(group)
    resolve()
    local name = type(group) == "table" and group.name or group
    if Journals.isGroup(name) then return Journals.options(name) end
    if name == Raven.GROUP then return Raven.options() end
    if name == Necromancy.GROUP then return Necromancy.options() end
    if name == ReaperCrew.GROUP then
        local bosses = ReaperCrew.bosses()
        local combat = Goals.options(Goals.GROUP)
        if bosses then
            combat[#combat + 1] = {
                kind = "crew", key = ReaperCrew.KEY, label = "Reaper crew", varName = bosses[1].vars[1], defaultTarget = #bosses,
                spriteName = ReaperCrew.SPRITE,
                description = "Kill every Reaper boss at least once. Bosses you have already killed drop off the list.",
            }
        end
        return combat
    end
    if name == Goals.CAPES then return Goals.options(Goals.CAPES) end
    if name == Goals.SKILLING then return Goals.options(Goals.SKILLING) end
    if name == Goals.LOGS then return Goals.options(Goals.LOGS) end
    local options = {}
    local discount = discountedGroups[name] and Unlocks.warpedDiscount()
    for _, entry in ipairs(byGroup[name] or {}) do
      -- Already bought: nothing left to track, so it isn't offered.
      if not isOwned(entry.piece.owned) and (entry.piece.anyTier or isAvailable(entry.piece.owned)) then
        options[#options + 1] = {
            kind = entry.kind, key = entry.key, label = entry.label, piece = entry.piece, description = entry.description,
            defaultTarget = entry.piece.cost, price = entry.piece.cost, priceUnit = entry.piece.currencyName,
            varName = entry.piece.noBalance and (entry.piece.owned or ""):gsub(">=%d+$", "") or entry.piece.currencyVar,
        }
        if discount and entry.piece.cost then
            local piece = {}
            for k, v in pairs(entry.piece) do piece[k] = v end
            piece.cost = math.floor(piece.cost * (1 - Unlocks.WARPED_DISCOUNT))
            options[#options].piece, options[#options].defaultTarget, options[#options].price = piece, piece.cost, piece.cost
            options[#options].description = (entry.description and entry.description .. "\n" or "") .. "Price includes your permanent 7% Warped outfit discount."
        end
        -- Tracked by ownership alone (no balance to compare): a tier item is done at its tier, anything else at 1.
        if entry.piece.noBalance then
            options[#options].defaultTarget = tonumber((entry.piece.owned or ""):match(">=(%d+)$")) or 1
        end
      end
    end
    return options
end

-- Every variable name the shops can track, bought items included (the lists offered leave those out).
function Unlocks.variables()
    resolve()
    local names = {}
    for _, list in pairs(byGroup) do
        for _, entry in ipairs(list) do
            local piece = entry.piece or {}
            names[#names + 1] = piece.currencyVar
            names[#names + 1] = piece.owned
        end
    end
    return names
end

-- True when the group is one of the shops that are tracked as a multi-select (Daemonheim and the other game shops).
function Unlocks.isShop(name)
    resolve()
    return byGroup[name] ~= nil
end

-- The skill icon a shop's notes wear in their header (Crux Eqal: Farming), or nil.
function Unlocks.headerSkill(group)
    for _, shop in ipairs(RewardShops) do
        if shop.name == group then return shop.headerSkill end
    end
    return nil
end

-- The item a shop's notes wear in their header (Raid Rewards: teci), or nil.
function Unlocks.headerObj(group)
    for _, shop in ipairs(RewardShops) do
        if shop.name == group then return shop.headerObj end
    end
    return nil
end

-- The shop that is a section of this group (Archaeology > Reward Shop), or nil.
function Unlocks.shopOf(group)
    resolve()
    for shop, parent in pairs(parents) do
        if parent == group then return shop end
    end
    return nil
end

-- One item of a shop, by key (owned ones included, so a saved note keeps its items). For a group with a shop as a section the
-- shop's items are looked up too.
function Unlocks.entry(group, key)
    resolve()
    for _, name in ipairs({ group, Unlocks.shopOf(group) }) do
        for _, entry in ipairs(byGroup[name] or {}) do
            if entry.key == key then
                return { kind = entry.kind, key = entry.key, label = entry.label, piece = entry.piece, description = entry.description }
            end
        end
    end
    return nil
end

return { Unlocks = Unlocks }
