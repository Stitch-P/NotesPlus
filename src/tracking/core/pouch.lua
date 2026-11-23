-- Currencies that have no variable of their own live in the currency pouch, an inventory holding one stack per currency
-- (Chronotes, say). A "pouch:<OBJECT>" name stands for the stack of that object.
-- The game only sends the pouch when it changes (or is opened), so every sighting is kept: in memory, and on disk so the
-- balance is known straight after logging in.
local Profiles = require("src/core/character_profiles")
local Pouch = {}

Pouch.PREFIX = "pouch:"
local STORE_KEY = "notes_plus_currency_pouch_v1"
local EVENT = "notes_plus_pouch"

local snapshot -- the stacks of the pouch the last time it was seen: {id, config, shown, title, count}
local totals   -- last known balance per pouch name, also kept on disk
local known    -- every currency the pouch has held: { [CONFIG_NAME] = { id =, name = } }, also kept on disk
local knownDirty = false
local loaded, onChange, owner = false, nil, nil

function Pouch.isName(name) return type(name) == "string" and name:sub(1, #Pouch.PREFIX):lower() == Pouch.PREFIX end

local function objectId(name)
    local ok, value = pcall(function() return id.Obj[name] end)
    return ok and type(value) == "number" and value >= 0 and value or nil
end

-- Whether the game knows the currency's object.
function Pouch.known(name)
    return Pouch.isName(name) and objectId(name:sub(#Pouch.PREFIX + 1):upper()) ~= nil
end

local function words(text) return (tostring(text or ""):lower():gsub("[^%a]", "")) end

-- The stacks in a list of slots, in a plain form.
local function records(slots)
    local list = {}
    for _, slot in pairs(slots) do
        local ok, record = pcall(function()
            local obj = slot.obj
            if obj == nil then return nil end
            if type(obj) == "number" then return {id = obj, count = slot.count} end
            local configName = obj.configName
            return {id = obj.id, config = type(configName) == "string" and configName:lower() or nil,
                shown = words(obj.name), title = type(obj.name) == "string" and obj.name or nil, count = slot.count}
        end)
        if ok and record then list[#list + 1] = record end
    end
    return list
end

local function slotsOf()
    if Inventory == nil or type(Inventory.Find) ~= "function" then return nil end
    local candidates = {}
    local okConfig, configured = pcall(function() return config.Inv.CURRENCY_POUCH end)
    if okConfig and configured ~= nil then candidates[#candidates + 1] = configured end
    local okId, invId = pcall(function() return id.Inv.CURRENCY_POUCH end)
    if okId and type(invId) == "number" and invId >= 0 then candidates[#candidates + 1] = invId end
    for _, candidate in ipairs(candidates) do
        local ok, slots = pcall(function()
            local inventory = Inventory.Find(candidate)
            return inventory ~= nil and inventory:GetSlots() or nil
        end)
        if ok and type(slots) == "table" and next(slots) ~= nil then return slots end
    end
    return nil
end

local function totalOf(list, name)
    local objId = objectId(name:sub(#Pouch.PREFIX + 1):upper())
    local wanted = name:sub(#Pouch.PREFIX + 1):lower()
    local wantedWords = words(wanted)
    local total = 0
    for _, record in ipairs(list) do
        local matches = record.id == objId or record.config == wanted
            -- The pouch names its stacks plainly ("Chronotes"), so the object's own name counts as well.
            or (record.shown ~= nil and #record.shown >= 4 and wantedWords:find(record.shown, 1, true) ~= nil)
        if matches then total = total + (type(record.count) == "number" and record.count or 1) end
    end
    return total
end

-- Balances belong to a character: a different one starts again from nothing.
local function storeKey()
    local characterID = Profiles.ID()
    return characterID and Profiles.Key(STORE_KEY, characterID) or nil
end

local function checkOwner()
    local current = Profiles.ID()
    if owner ~= current then owner, snapshot, totals, loaded, known, knownDirty = current, nil, nil, false, nil, false end
end

local function load()
    checkOwner()
    if loaded then return end
    loaded = true
    totals = {}
    local key = storeKey()
    if not key then return end
    local ok, saved = pcall(function() return PersistentDB:GetStructuredData(key) end)
    if ok and type(saved) == "table" then
        for name, value in pairs(saved) do
            if type(name) == "string" and type(value) == "number" then totals[name] = value end
        end
    end
end

local function remember(name, value)
    load()
    if totals[name] == value then return end
    totals[name] = value
    local key = storeKey()
    if key then pcall(function() PersistentDB:SetStructuredData(key, totals) end) end
end

-- The currencies the pouch has held. The plugin's own currency list cannot know a currency the game adds later, but the pouch
-- itself names every stack it holds, so each one seen is remembered (per character, on disk) and offered as a currency.
local KNOWN_KEY = "notes_plus_currency_pouch_stacks_v1"

local function knownKey()
    local characterID = Profiles.ID()
    return characterID and Profiles.Key(KNOWN_KEY, characterID) or nil
end

local function loadKnown()
    checkOwner()
    if known then return end
    known = {}
    local key = knownKey()
    if not key then return end
    local ok, saved = pcall(function() return PersistentDB:GetStructuredData(key) end)
    if ok and type(saved) == "table" then
        for name, entry in pairs(saved) do
            if type(name) == "string" and type(entry) == "table" and type(entry.id) == "number" and type(entry.name) == "string" then
                known[name] = { id = entry.id, name = entry.name }
            end
        end
    end
end

-- Remembers the stacks of a pouch reading that have not been seen before (a stack needs an object name to be offered).
local function learn(list)
    loadKnown()
    for _, record in ipairs(list) do
        local name = type(record.config) == "string" and record.config:upper() or nil
        if name and known[name] == nil and type(record.id) == "number" and type(record.title) == "string" and record.title ~= "" then
            known[name] = { id = record.id, name = record.title }
            knownDirty = true
        end
    end
    if knownDirty then
        local key = knownKey()
        if key and pcall(function() return PersistentDB:SetStructuredData(key, known) end) then knownDirty = false end
    end
end

-- Every currency the pouch has held: { { var = "pouch:NAME", obj = object id, name = display name } }, by name.
function Pouch.stacks()
    local slots = slotsOf()
    if slots then
        snapshot = records(slots)
        learn(snapshot)
    end
    loadKnown()
    local list = {}
    for name, entry in pairs(known) do list[#list + 1] = { var = Pouch.PREFIX .. name, obj = entry.id, name = entry.name } end
    table.sort(list, function(a, b) return a.var < b.var end)
    return list
end

-- What to tell the player when a pouch currency has no balance to show: the game only sends the pouch when it is opened or
-- changes, so the balance is unknown until then. nil for anything that is not a pouch currency.
function Pouch.reason(name)
    if not Pouch.isName(name) then return nil end
    return "Please open your Currency Pouch so Notes+ can access the value for tracking"
end

-- Whether a "pouch:NAME" variable is a currency the pouch has held (no inventory read).
function Pouch.isStack(name)
    if not Pouch.isName(name) then return false end
    loadKnown()
    return known[name:sub(#Pouch.PREFIX + 1):upper()] ~= nil
end

-- How many of the currency the pouch holds (0 when it has none), or nil when it has never been seen.
function Pouch.count(name)
    if not Pouch.isName(name) or not objectId(name:sub(#Pouch.PREFIX + 1):upper()) then return nil end
    checkOwner()
    local slots = slotsOf()
    if slots then snapshot = records(slots) end
    if snapshot then
        local total = totalOf(snapshot, name)
        remember(name, total)
        return total
    end
    load()
    return totals[name]
end

local function isPouch(inventory)
    local ok, matches = pcall(function()
        local configured = config.Inv.CURRENCY_POUCH
        if inventory.id ~= nil and configured.id ~= nil then return inventory.id == configured.id end
        local name = inventory.configName
        return type(name) == "string" and name:upper() == "CURRENCY_POUCH"
    end)
    return ok and matches == true
end

local function seen(event)
    local inventory = event and event.inv
    if inventory == nil or not isPouch(inventory) then return end
    local ok, slots = pcall(function() return inventory:GetSlots() end)
    if not ok or type(slots) ~= "table" then return end
    checkOwner()
    snapshot = records(slots)
    learn(snapshot)
    if onChange then onChange() end
end

-- Starts listening for the pouch (the callback runs when it changes).
function Pouch.Attach(callback)
    onChange = callback
    for _, name in ipairs({"InventoryAdded", "InventoryUpdated"}) do
        pcall(function() Event[name].Subscribe(EVENT, seen) end)
    end
end

function Pouch.Detach()
    onChange = nil
    for _, name in ipairs({"InventoryAdded", "InventoryUpdated"}) do
        pcall(function() Event[name].Unsubscribe(EVENT) end)
    end
end

return Pouch
