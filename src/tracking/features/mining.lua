-- Mining: track how many ores (metal bank + ore box) or bars (metal bank) you have.

local data_m = require("src/tracking/data/mining")
local ORES, BARS = data_m.ORES, data_m.BARS

local Vars = require("src/tracking/core/vars")

local Mining = {}

local SkillGuideSource = require("src/tracking/core/skillguide_source")

local GROUP_ORES, GROUP_BARS, GROUP_ENERGIES = "Mining: Gems & Ores", "Bars", "Divination: Energies"
local GROUP_ARCH = "Archaeology: Materials"
local items, byKey, byGroup, groupNames = {}, {}, {}, {}
local resolved = false
local source = "snapshot"
for _, row in ipairs(ORES) do items[#items + 1] = { objId = row[1], name = row[2], box = row[3], group = GROUP_ORES } end
for _, row in ipairs(BARS) do items[#items + 1] = { objId = row[1], name = row[2], group = GROUP_BARS } end
for _, item in ipairs(items) do
    item.key = "mining:" .. item.objId
    byKey[item.key] = item
    byGroup[item.group] = byGroup[item.group] or {}
    table.insert(byGroup[item.group], item)
end
groupNames = { GROUP_ORES, GROUP_BARS }

local WOODBOX_TIERS = { OAK = true, WILLOW = true, TEAK = true, MAPLE = true, ACADIA = true, MAHOGANY = true,
    YEW = true, MAGIC = true, ELDER = true, ETERNAL = true }

-- The wood box keeps a count per log type, named after the tier ("Oak logs" -> WOODCUTTING_WOODBOX_OAK).
local function woodBoxVariable(name)
    local lower = tostring(name):lower()
    if lower == "logs" then return "WOODCUTTING_WOODBOX_BASIC" end
    local tier = lower:match("^(%a+) logs$") or lower:match("^(%a+) magic logs$")
    tier = tier and tier:upper()
    if tier and WOODBOX_TIERS[tier] then return "WOODCUTTING_WOODBOX_" .. tier end
end

local function objectName(objId)
    local ok, name = pcall(function() return config.Obj.FromID(objId).name end)
    if ok and type(name) == "string" and name ~= "" and name ~= "null" then return name end
    return "Item " .. objId
end

-- The lists above are the curated base; the game's skill guides add the groups and items they don't have.
local function resolve()
    if resolved then return end
    resolved = true
    -- Divination energies (Pale to Incandescent, plus Positive, Negative, Ancestral and Elder) aren't in the skill guide, which only lists memories.
    local energies = {}
    local ids = {}
    for objId = 29313, 29324 do ids[#ids + 1] = objId end
    -- Positive, Negative and Ancestral (Arc) energy, then Elder energy.
    for _, objId in ipairs({ 38612, 38617, 38622, 31312 }) do ids[#ids + 1] = objId end
    for _, objId in ipairs(ids) do
        local key = "mining:" .. objId
        local item = { objId = objId, name = objectName(objId), group = GROUP_ENERGIES, key = key }
        items[#items + 1], byKey[key], energies[#energies + 1] = item, item, item
    end
    byGroup[GROUP_ENERGIES] = energies
    groupNames[#groupNames + 1] = GROUP_ENERGIES
    -- Archaeology materials: counted from the backpack and Material Storage (where the Porters' deliveries end up too).
    local materials = {}
    for _, row in ipairs(require("src/tracking/data/archaeology").MATERIALS) do
        local key = "mining:" .. row[1]
        local item = { objId = row[1], name = objectName(row[1]), group = GROUP_ARCH, key = key, storage = true }
        if item.name == "Item " .. row[1] then item.name = row[2] end
        items[#items + 1], byKey[key], materials[#materials + 1] = item, item, item
    end
    byGroup[GROUP_ARCH] = materials
    groupNames[#groupNames + 1] = GROUP_ARCH
    local ok, guide = pcall(SkillGuideSource.Groups)
    if not ok or not guide then return end
    source = "game"
    for _, entry in ipairs(guide) do
        if entry.target == "gathering" then
            local list = byGroup[entry.name]
            if not list then
                list = {}
                byGroup[entry.name] = list
                groupNames[#groupNames + 1] = entry.name
            end
            local inGroup = {}
            for _, item in ipairs(list) do inGroup[item.objId] = true end
            for _, objId in ipairs(entry.objs) do
                if not inGroup[objId] then
                    inGroup[objId] = true
                    local key = "mining:" .. objId
                    local item = byKey[key]
                    if not item then
                        item = { objId = objId, name = objectName(objId), group = entry.name, key = key }
                        if entry.name == "Woodcutting: Logs" then item.box = woodBoxVariable(item.name) end
                        items[#items + 1], byKey[key] = item, item
                    end
                    -- The skill guide's catch-all "Various logs" entry isn't a log you can hold: it is no longer offered,
                    -- but stays known so a note that already tracks it still loads.
                    if item.name:lower() ~= "various logs" then list[#list + 1] = item end
                end
            end
        end
    end
end

function Mining.source()
    resolve()
    return source
end

function Mining.groups()
    resolve()
    local list = {}
    for _, name in ipairs(groupNames) do
        -- Bars moved to Production ("Smithing: Bars"); notes that already track them keep working.
        if name ~= GROUP_BARS and #(byGroup[name] or {}) > 0 then list[#list + 1] = { name = name } end
    end
    return list
end

function Mining.info(key)
    resolve()
    return byKey[key]
end

function Mining.options(group)
    resolve()
    local name = type(group) == "table" and group.name or group
    if name == "Ores" then name = GROUP_ORES end -- the group's old name, kept for notes made before it was renamed
    local options = {}
    for _, item in ipairs(byGroup[name] or {}) do
        options[#options + 1] = {
            kind = "mining", key = item.key, label = item.name, objId = item.objId, item = item,
            varName = item.box and (item.box) or nil,
            description = Mining.description(item.key),
        }
    end
    return options
end

-- The slots of a named inventory (METAL_BANK, INV for the backpack), or nil when the game hasn't given them to us.
-- The second result says what went wrong, for the one-off report below.
local function inventorySlots(name)
    if Inventory == nil or type(Inventory.Find) ~= "function" then return nil, "Inventory.Find is not available" end
    local candidates, notes = {}, {}
    local ok, configured = pcall(function() return config.Inv[name] end)
    if ok and configured ~= nil then candidates[#candidates + 1] = configured else notes[#notes + 1] = "config.Inv." .. name .. " missing" end
    local idOK, invId = pcall(function() return id.Inv[name] end)
    if idOK and type(invId) == "number" and invId >= 0 then candidates[#candidates + 1] = invId else notes[#notes + 1] = "id.Inv." .. name .. " missing" end
    for _, candidate in ipairs(candidates) do
        local found, slots = pcall(function()
            local inventory = Inventory.Find(candidate)
            if inventory == nil then return nil, "Find returned nothing" end
            local contents = inventory:GetSlots()
            if type(contents) ~= "table" then return nil, "GetSlots gave " .. type(contents) end
            return contents
        end)
        if found and type(slots) == "table" then return slots end
        notes[#notes + 1] = tostring(found and "no slots" or slots)
    end
    return nil, table.concat(notes, "; ")
end

function Mining.inventoryCount(name, objId)
    local slots = inventorySlots(name)
    if not slots then return nil end
    local total = 0
    for _, slot in pairs(slots) do
        local ok, matches, count = pcall(function()
            local obj = slot.obj
            return obj ~= nil and obj.id == objId, slot.count
        end)
        if ok and matches then total = total + (type(count) == "number" and count or 1) end
    end
    return total
end

local function readNumber(name)
    local entry = Vars.resolveVar(name)
    return entry and Vars.readEntry(entry) or nil
end

-- Ore / wood box total: the normal box or the upgraded box, whichever holds the items.
local function boxCount(item)
    if not item.box then return 0 end
    local normal, upgraded = readNumber(item.box), readNumber(item.box .. "_UPGRADED")
    if normal == nil and upgraded == nil then return nil end
    -- Only one box is in use; the larger reading is taken so the same logs are never counted twice if both variables move.
    return math.max(normal or 0, upgraded or 0)
end

-- Archaeology's Material Storage is an inventory of its own; the first of these names the game knows is the one used.
local STORAGE_NAMES = { "ARCH_MATERIAL_STORAGE", "ARCH_MATERIALS", "ARCH_MATERIAL_STORE", "ARCHAEOLOGY_MATERIAL_STORAGE",
    "MATERIAL_STORAGE", "ARCH_STORAGE" }
local storageName, storageLooked = nil, nil
local STORAGE_RETRY = 30

local function storageCount(objId)
    if storageName then return Mining.inventoryCount(storageName, objId) end
    local now = type(os) == "table" and os.time and os.time() or nil
    if now and storageLooked and now - storageLooked < STORAGE_RETRY then return nil end
    storageLooked = now
    for _, name in ipairs(STORAGE_NAMES) do
        local count = Mining.inventoryCount(name, objId)
        if count ~= nil then
            storageName = name
            return count
        end
    end
    return nil
end

-- What's in each place right now: metal bank, ore box, backpack (each nil when it can't be read).
-- Archaeology materials have Material Storage in the first place instead of the metal bank.
function Mining.places(item)
    local bank = item.storage and storageCount(item.objId) or not item.storage and Mining.inventoryCount("METAL_BANK", item.objId) or nil
    return bank, boxCount(item), Mining.inventoryCount("INV", item.objId)
end

function Mining.description(key)
    local item = byKey[key]
    if not item then return nil end
    if item.group == GROUP_ARCH then
        return "Counts new materials from when you set this note: ones you dig up, and ones sent to Material Storage by "
            .. "your Porters. Moving them between your backpack and Material Storage doesn't count twice."
    end
    if item.group ~= GROUP_BARS and item.group ~= GROUP_ORES then
        return "Counts new ones that show up in your backpack from when you set this note. "
            .. "Dropping, banking or storing them and taking them back doesn't count twice."
    end
    return "Counts new " .. (item.group == GROUP_BARS and "bars" or "ore") .. " from when you set this note. "
        .. "Moving them between your backpack, ore box and metal bank doesn't count twice."
end

return { Mining = Mining }
