-- Treasure Trails data read from the game: the reward items on the clue scroll collection pages
-- (collection_cluescroll_*) and the reward shop entries (the trail17_reward_shop_list enum and the structs it points to).
-- The Clues feature keeps its own lists as the base and adds whatever turns up here that they don't have.

local ConfigReader = require("src/tracking/core/config_reader")

local ClueSource = {}

local ROW_PREFIX = "COLLECTION_CLUESCROLL_"
local ITEMS_COLUMN = 14
local SHOP_STRUCT, SHOP_ENUM = "TRAIL17_REWARD_SHOP_STRUCT", "TRAIL17_REWARD_SHOP_LIST"

local function number(value)
    if type(value) == "number" then return value end
    local id = ConfigReader.Field(value, "id")
    if type(id) == "number" then return id end
end

-- Every reward item on the clue pages: { name = <Obj config name>, obj = <Obj id> }, or nil when unreadable.
function ClueSource.RewardItems()
    if not ConfigReader.Available() then return nil end
    local items, seen, pages = {}, {}, 0
    for _, entry in ipairs(ConfigReader.TableRows("COLLECTION")) do
        local rowName = type(entry.name) == "string" and entry.name:upper() or nil
        if rowName and rowName:sub(1, #ROW_PREFIX) == ROW_PREFIX then
            pages = pages + 1
            local column = ConfigReader.Column(entry.row, ITEMS_COLUMN)
            for _, object in ipairs(column and type(column.values) == "table" and column.values or {}) do
                local objId = number(object)
                local objName = ConfigReader.Field(object, "configName")
                if objId and type(objName) == "string" and objName ~= "" and not seen[objId] then
                    seen[objId] = true
                    items[#items + 1] = { name = objName:upper(), obj = objId }
                end
            end
        end
    end
    if pages < 3 or #items < 50 then return nil end
    return items
end

local function param(struct, name)
    return ConfigReader.StructParam(struct, name)
end

-- An object id from whatever the struct hands back: the number itself (REWARDSHOP_OBJ, e.g. 42015), a numeric string,
-- or the object, which is read by its id and then by its config name.
local function objectId(value)
    if type(value) == "string" then value = tonumber(value) end
    if type(value) == "number" then return value >= 0 and value or nil end
    if value == nil then return nil end
    local objectNumber = ConfigReader.Field(value, "id")
    if type(objectNumber) == "number" and objectNumber >= 0 then return objectNumber end
    local configName = ConfigReader.Field(value, "configName")
    local okLookup, byName = pcall(function() return type(configName) == "string" and id.Obj[configName:upper()] end)
    if okLookup and type(byName) == "number" and byName >= 0 then return byName end
    return nil
end

-- Reward shop entries: { struct = <config name>, label, cost, obj, multi = bool }, or nil when unreadable.
function ClueSource.ShopEntries()
    if not ConfigReader.Available() then return nil end
    local list = param(SHOP_STRUCT, "REWARDSHOP_ITEM_LIST")
    local enum
    if type(list) == "number" then enum = ConfigReader.Enum(list) elseif list ~= nil then enum = list end
    enum = enum or ConfigReader.Enum(SHOP_ENUM)
    local pairsList = enum and ConfigReader.EnumPairs(enum) or {}
    local entries = {}
    for _, pair in ipairs(pairsList) do
        local value = pair[2]
        local struct
        if type(value) == "number" then
            if value >= 0 then struct = ConfigReader.Struct(value) end
        elseif value ~= nil then
            -- The enum may hand back the struct itself (or something that carries its id).
            struct = value
            if ConfigReader.Field(value, "configName") == nil then
                local structId = ConfigReader.Field(value, "id")
                struct = type(structId) == "number" and ConfigReader.Struct(structId) or nil
            end
        end
        if struct then
            local name = ConfigReader.Field(struct, "configName")
            local label = param(struct, "REWARDSHOP_ITEM_NAME")
            local cost = param(struct, "REWARDSHOP_COST")
            if type(name) == "string" and type(label) == "string" and label ~= "" and type(cost) == "number" and cost > 0 then
                -- The sold object comes back as a number or as the object itself; -1 means none.
                local obj = objectId(param(struct, "REWARDSHOP_OBJ"))
                local icon = param(struct, "REWARDSHOP_ICON")
                entries[#entries + 1] = {
                    struct = name:upper(), label = label, cost = cost, obj = obj,
                    sprite = type(icon) == "number" and icon > 0 and icon or nil,
                    multi = param(struct, "REWARDSHOP_BUY_OPTION_2") ~= nil,
                }
            end
        end
    end
    ClueSource.lastShopCount = #pairsList
    if #entries < 5 then return nil end
    return entries
end

return ClueSource
