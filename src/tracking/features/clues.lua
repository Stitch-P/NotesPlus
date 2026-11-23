-- The Clues type: outfit pieces and completion counters.
local constants_m = require("src/tracking/constants")
local categoryIndex = constants_m.categoryIndex
local objects_m = require("src/tracking/core/objects")
local objectDisplayName = objects_m.objectDisplayName
local vars_m = require("src/tracking/core/vars")
local readEntry, resolveVar = vars_m.readEntry, vars_m.resolveVar
local data_m = require("src/tracking/data/clues")
local CLUE_ITEMS, ITEM_OBJECT_OVERRIDES = data_m.CLUE_ITEMS, data_m.ITEM_OBJECT_OVERRIDES
local CURRENCY_VAR, GLOBETROTTER, CLUE_TIERS = data_m.CURRENCY_VAR, data_m.GLOBETROTTER, data_m.CLUE_TIERS
local SHOP_UNLOCKS = data_m.SHOP_UNLOCKS
local GROUP_COUNTERS, GROUP_GLOBETROTTER = data_m.GROUP_COUNTERS, data_m.GROUP_GLOBETROTTER
local GROUP_ORDER, itemGroup = data_m.GROUP_ORDER, data_m.itemGroup

-- The Clues type
local Clues = {
    type = categoryIndex("Clues"),
    currencyVar = CURRENCY_VAR,
    selected = 1,
    pieces = GLOBETROTTER,
    tiers = CLUE_TIERS,
}

-- Clue reward items (coming from data\clues.lua)
local itemCache
function Clues.items()
    if itemCache then return itemCache end
    local items = {}
    for _, name in ipairs(CLUE_ITEMS) do
        local objName = ITEM_OBJECT_OVERRIDES[name] or name
        local ok, objId = pcall(function() return id.Obj[objName] end)
        if not ok or type(objId) ~= "number" then objId = nil end
        local label = objectDisplayName(objId)
        if not label then
            label = name:gsub("^TRAIL%d*_", ""):gsub("_", " "):lower()
            label = label:sub(1, 1):upper() .. label:sub(2)
        end
        items[#items + 1] = { name = name, obj = objId, label = label, var = "ITEMLOG_ITEM_" .. name, group = itemGroup(name) }
    end
    -- Reward items the game lists on its clue scroll pages that the list above doesn't have, as long as the game has
    -- a collection log counter for them.
    local okSource, extra = pcall(function() return require("src/tracking/core/clue_source").RewardItems() end)
    if okSource and extra then
        local known, reverse = {}, {}
        for _, item in ipairs(items) do known[item.name] = true end
        for name, objName in pairs(ITEM_OBJECT_OVERRIDES) do reverse[objName] = name end
        for _, entry in ipairs(extra) do
            local name = reverse[entry.name] or entry.name
            local var = "ITEMLOG_ITEM_" .. name
            if not known[name] and resolveVar(var) then
                known[name] = true
                local label = objectDisplayName(entry.obj)
                if not label then
                    label = name:gsub("^TRAIL%d*_", ""):gsub("_", " "):lower()
                    label = label:sub(1, 1):upper() .. label:sub(2)
                end
                items[#items + 1] = { name = name, obj = entry.obj, label = label, var = var, group = itemGroup(name), fromGame = true }
                Clues.newItems = (Clues.newItems or 0) + 1
            end
        end
        Clues.itemsFromGame = true
    end
    itemCache = items
    return items
end

-- Reward shop details come from the shop struct
local function shopParam(struct, paramName)
    local ok, value = pcall(function()
        local param = config.Param[paramName]
        if not param then return nil end
        if struct.HasParam and not struct:HasParam(param) then return nil end
        return struct:GetParamValue(param)
    end)
    if ok then return value end
    return nil
end

local function shopStruct(unlock)
    local base = unlock.owned:gsub("_OWNED$", ""):gsub("_UNLOCKED$", "")
    local tries = { base .. "_SHOP" }
    for _, name in ipairs(unlock.structs or {}) do tries[#tries + 1] = name end
    for _, name in ipairs(tries) do
        local ok, struct = pcall(function() return config.Struct[name] end)
        if ok and struct then
            do
                local label = shopParam(struct, "REWARDSHOP_ITEM_NAME")
                local cost = shopParam(struct, "REWARDSHOP_COST")
                if type(label) ~= "string" or label == "" then label = nil end
                if type(cost) ~= "number" or cost <= 0 then cost = nil end
                local sold = shopParam(struct, "REWARDSHOP_OBJ")
                if type(sold) ~= "number" or sold < 0 then sold = nil end
                if label or cost then return { label = label, cost = cost, obj = sold } end
            end
        end
    end
    return nil
end

local shopCache
function Clues.shopUnlocks()
    if shopCache then return shopCache end
    local list = {}
    local byOwned = {}
    for _, unlock in ipairs(SHOP_UNLOCKS) do
        local found = shopStruct(unlock)
        local row = {
            name = found and found.label or unlock.name,
            obj = found and found.obj or unlock.obj, owned = unlock.owned, cost = found and found.cost,
            fromStruct = found and found.label ~= nil,
        }
        list[#list + 1] = row
        byOwned[unlock.owned] = row
    end
    -- The game's own shop list: refresh the Globetrotter prices and add one-off unlocks we don't know yet.
    local okShop, entries = pcall(function() return require("src/tracking/core/clue_source").ShopEntries() end)
    if okShop and entries then
        local knownOwned, knownObj, titleObj = {}, {}, {}
        for _, piece in ipairs(Clues.pieces) do knownOwned[piece.owned] = true; if piece.obj then knownObj[piece.obj] = piece end end
        for _, unlock in ipairs(SHOP_UNLOCKS) do knownOwned[unlock.owned] = true; if unlock.obj then titleObj[unlock.obj] = true end end
        local names = {}
        for _, row in ipairs(list) do names[row.name:lower()] = true end
        for _, piece in ipairs(Clues.pieces) do names[(piece.name or ""):lower()] = true end
        for _, entry in ipairs(entries) do
            local charge = entry.struct:find("CHARGE", 1, true) ~= nil
            local piece = entry.obj and knownObj[entry.obj]
            if piece and not charge and not entry.multi then
                piece.cost = entry.cost
            elseif entry.struct ~= "TRAIL17_PET_SHOP" then
                local base = entry.struct:gsub("_SHOP$", "")
                local owned
                if not entry.multi and not charge then
                    for _, candidate in ipairs({ base .. "_OWNED", base .. "_UNLOCKED", base }) do
                        if knownOwned[candidate] then
                            -- Already listed: the game's shop struct is the source of its name and price.
                            local row = byOwned[candidate]
                            if row then
                                row.name = entry.label
                                row.cost = entry.cost
                                row.obj = entry.obj or row.obj
                            end
                            owned = false
                            break
                        end
                        if not owned and resolveVar(candidate) then owned = candidate end
                    end
                end
                if owned then
                    knownOwned[owned] = true
                    list[#list + 1] = { name = entry.label, obj = entry.obj, sprite = entry.sprite, owned = owned, cost = entry.cost, fromGame = true }
                    byOwned[owned] = list[#list]
                    names[entry.label:lower()] = true
                    Clues.newShopUnlocks = (Clues.newShopUnlocks or 0) + 1
                elseif owned == nil and not names[entry.label:lower()] then
                    -- Charges, clue scrolls, skip tickets, rerolls and anything else you can buy again: tracked as points towards the price.
                    names[entry.label:lower()] = true
                    list[#list + 1] = { name = entry.label, obj = entry.obj, sprite = entry.sprite, key = "shop:" .. entry.struct, cost = entry.cost, fromGame = true }
                    Clues.newShopUnlocks = (Clues.newShopUnlocks or 0) + 1
                end
            end
        end
        Clues.shopFromGame = true
    end
    shopCache = list
    return list
end

-- Where the lists came from, and how much the game added: for the probe log.
function Clues.source()
    Clues.items()
    Clues.shopUnlocks()
    return (Clues.itemsFromGame and "game" or "snapshot"), (Clues.shopFromGame and "game" or "snapshot"),
        Clues.newItems or 0, Clues.newShopUnlocks or 0
end

-- Section names for the dropdown that sits above the Track list.
function Clues.groups()
    local list = {}
    -- The reward shop lives under Unlocks (Clues > Reward Shop), so it isn't a section here.
    for _, name in ipairs(GROUP_ORDER) do
        if name ~= GROUP_GLOBETROTTER then list[#list + 1] = { name = name } end
    end
    return list
end

-- Where the reward shop is offered: the Unlocks type, category "Clues", section "Reward Shop".
Clues.SHOP_CATEGORY = "Clues"
Clues.SHOP_SECTION = "Reward Shop"
Clues.SHOP_GROUP = GROUP_GLOBETROTTER

-- True when a saved note was made for the reward shop back when it was a section of the Clues type.
function Clues.isShopNote(saved)
    if type(saved) ~= "table" or saved.category ~= "Clues" then return false end
    if saved.group == GROUP_GLOBETROTTER then return true end
    local first = type(saved.items) == "table" and saved.items[1] or saved
    if type(first) ~= "table" or saved.group ~= nil and first ~= saved then return false end
    local key = first.key or first.ownedVar
    local option = type(key) == "string" and Clues.collectionOption(nil, key)
    return option ~= nil and option ~= false and option.kind == "piece"
end

function Clues.isCollectionGroup(group)
    local name = type(group) == "table" and group.name or group
    if name == GROUP_COUNTERS then return false end
    for _, candidate in ipairs(GROUP_ORDER) do
        if name == candidate then return true end
    end
    return false
end

function Clues.sorted()
    local list = {}
    Clues.shopUnlocks()
    for _, item in ipairs(Clues.items()) do
        list[#list + 1] = { kind = "item", item = item, obj = item.obj, var = item.var, label = item.label, group = item.group }
    end
    for _, piece in ipairs(Clues.pieces) do
        list[#list + 1] = { kind = "piece", piece = piece, label = objectDisplayName(piece.obj) or piece.name, group = GROUP_GLOBETROTTER }
    end
    for _, unlock in ipairs(Clues.shopUnlocks()) do
        list[#list + 1] = { kind = "piece", piece = unlock, label = unlock.name, group = GROUP_GLOBETROTTER }
    end
    local allVars = {}
    for _, tier in ipairs(Clues.tiers) do allVars[#allVars + 1] = tier.var end
    local function addCounter(name, vars, obj, totalOnly, noun)
        noun = noun or " clues"
        if not totalOnly then
            list[#list + 1] = { kind = "clues", mode = "individual", vars = vars, obj = obj, group = GROUP_COUNTERS,
                label = name .. noun .. ": Individual completions" }
        end
        list[#list + 1] = { kind = "clues", mode = "total", vars = vars, obj = obj, group = GROUP_COUNTERS,
            label = name .. noun .. ": Total completions" }
    end
    for _, tier in ipairs(Clues.tiers) do addCounter(tier.name, { tier.var }, tier.obj) end
    addCounter("All", allVars, nil, true)
    -- Tetracompasses restored through Archaeology count like a tier, but are not part of the "All" total.
    addCounter("Tetracompass", { "ARCH_RESTORATION_TETRACOMPASS" }, 49957, false, "")
    table.sort(list, function(a, b)
        local x, y = a.label:lower(), b.label:lower()
        if x ~= y then return x < y end
        return false
    end)
    return list
end

local collectionOptions, collectionOptionsByKey
function Clues.collectionOption(group, key)
    local name = type(group) == "table" and group.name or group
    if type(key) ~= "string" or name ~= nil and not Clues.isCollectionGroup(name) then return nil end
    if not collectionOptions then
        collectionOptions, collectionOptionsByKey = {}, {}
        for _, option in ipairs(Clues.sorted()) do
            if option.kind == "item" or option.kind == "piece" then
                local options = collectionOptions[option.group]
                if not options then options = {}; collectionOptions[option.group] = options end
                local optionKey = option.piece and (option.piece.owned or option.piece.key) or option.var
                options[optionKey], collectionOptionsByKey[optionKey] = option, option
            end
        end
    end
    if name == nil then return collectionOptionsByKey[key] end
    return collectionOptions[name] and collectionOptions[name][key]
end

-- Sum of the given variables, or nil when any can't be read (yet).
function Clues.sumVars(names, cache)
    local total = 0
    for _, name in ipairs(names) do
        local entry = cache and cache[name]
        if not entry then
            entry = resolveVar(name)
            if cache then cache[name] = entry end
        end
        local value = readEntry(entry)
        if not value then return nil end
        total = total + value
    end
    return total
end

return {
    Clues = Clues,
}