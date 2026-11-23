local Sprites = require("src/data/sprite_catalog")
local field = require("src/core/safe_values").Field
local Gear = {}

Gear.Slots = {
    {key = "head", label = "Head", column = 2, row = 1},
    {key = "pocket", label = "Pocket", column = 3, row = 1},
    {key = "cape", label = "Cape", column = 1, row = 2},
    {key = "neck", label = "Neck", column = 2, row = 2},
    {key = "ammo", label = "Ammo", column = 3, row = 2},
    {key = "mainhand", label = "Main hand", column = 1, row = 3},
    {key = "body", label = "Body", column = 2, row = 3},
    {key = "offhand", label = "Off hand", column = 3, row = 3},
    {key = "legs", label = "Legs", column = 2, row = 4},
    {key = "hands", label = "Hands", column = 1, row = 5},
    {key = "feet", label = "Feet", column = 2, row = 5},
    {key = "ring", label = "Ring", column = 3, row = 5}
}

local slots = {}
for _, slot in ipairs(Gear.Slots) do slots[slot.key] = true end

local WORN_INDICES = {head = 1, cape = 2, neck = 3, mainhand = 4, body = 5, offhand = 6,
    legs = 8, hands = 10, feet = 11, ring = 13, ammo = 14, pocket = 18}

local function integer(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge and value % 1 == 0
end

local function validToken(token)
    return type(token) == "string" and #token <= Sprites.MAX_NAME_LENGTH
        and token:match("^item/[A-Z0-9_]+$") ~= nil
end

function Gear.Normalize(saved)
    if saved == nil then return nil end
    if type(saved) ~= "table" then return nil, "Choose valid gear setup items." end
    local copy = {}
    for key, token in pairs(saved) do
        if not slots[key] or not validToken(token) then return nil, "Choose an item for an existing gear slot." end
        copy[key] = token
    end
    return copy
end

function Gear.Count(gear)
    if type(gear) ~= "table" then return 0 end
    local count = 0
    for _, slot in ipairs(Gear.Slots) do if gear[slot.key] ~= nil then count = count + 1 end end
    return count
end

function Gear.GetItem(token)
    if not validToken(token) or type(Sprites.Get) ~= "function" then return nil end
    local ok, choice = pcall(Sprites.Get, token)
    return ok and choice and type(choice.objectID) == "number" and choice.objectID >= 0
        and choice.objectID % 1 == 0 and choice or nil
end

function Gear.Object(token)
    local choice = Gear.GetItem(token)
    if not choice then return nil end
    local ok, object = pcall(function() return config.Obj.FromID(choice.objectID) end)
    return ok and object and object.id == choice.objectID and object or nil
end

local function wornInventory()
    if Inventory == nil or type(Inventory.Find) ~= "function" then return nil end
    local configOK, wornConfig = pcall(function() return config.Inv.WORN end)
    local idOK, wornID = pcall(function() return id.Inv.WORN end)
    if not idOK or not integer(wornID) or wornID < 0 then
        local ok, value = pcall(function() return wornConfig.id end)
        wornID = ok and integer(value) and value >= 0 and value or nil
    end
    local candidates = configOK and wornConfig ~= nil and {wornConfig, wornID} or {wornID}
    for _, candidate in ipairs(candidates) do
        local ok, inventory, contents = pcall(function()
            local value = Inventory.Find(candidate)
            if value == nil or field(value, "isValid", "valid") == false then return nil end
            local contents = value:GetSlots()
            if type(contents) ~= "table" then return nil end
            return value, contents
        end)
        if ok and inventory ~= nil then return inventory, contents end
    end
end

local function equippedToken(object)
    local objectID = object.id
    local function resolve(name)
        if type(name) ~= "string" or not validToken("item/" .. name) then return nil end
        local ok, mappedID = pcall(function() return id.Obj[name] end)
        if not ok or mappedID ~= objectID then return nil end
        local token = "item/" .. name
        local item = Gear.GetItem(token)
        return item and item.objectID == objectID and token or nil
    end
    local ok, name = pcall(function() return object.configName end)
    local token = ok and resolve(name) or nil
    if token then return token end
    ok, name = pcall(function() return id.Obj.FromID(objectID) end)
    return ok and resolve(name) or nil
end

function Gear.CaptureEquipped()
    local ok, result, message = pcall(function()
        local inventory, contents = wornInventory()
        if not inventory then return nil, "Could not read equipped items." end
        local gear = {}
        for _, definition in ipairs(Gear.Slots) do
            local slot = contents[WORN_INDICES[definition.key]]
            if slot ~= nil then
                local count = slot.count
                if count ~= nil and (not integer(count) or count < 0) then
                    return nil, "Could not read the equipped " .. definition.label:lower() .. " item."
                end
                if count ~= 0 then
                    local object = slot.obj
                    if object == nil then
                        if count ~= nil and count > 0 then
                            return nil, "Could not read the equipped " .. definition.label:lower() .. " item."
                        end
                    else
                        local objectID = object.id
                        if not integer(objectID) then
                            return nil, "Could not read the equipped " .. definition.label:lower() .. " item."
                        end
                        if objectID >= 0 then
                            local token = equippedToken(object)
                            if not token then return nil, "Could not read the equipped " .. definition.label:lower() .. " item." end
                            gear[definition.key] = token
                        end
                    end
                end
            end
        end
        if field(inventory, "isValid", "valid") == false then
            return nil, "Equipped gear changed while reading it. Try again."
        end
        return gear
    end)
    if not ok then return nil, "Could not read equipped items." end
    return result, message
end

return Gear
