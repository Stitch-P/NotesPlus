-- Archaeology artefacts, tracked under Gathering. The artefacts are split by faction ("Archaeology: Zarosian"), then by the
-- collection they belong to (the third dropdown: "Soran: Zarosian I"). Each artefact has a variable per collection
-- (COLLECTION_<NPC>_<nn>_ARCH_<ARTEFACT>) that is set once it is in that collection. A collection starts again after it is
-- handed in, and the notes start again with it, like the game's own log.
-- The materials live with the other gathered items ("Archaeology: Materials", see mining.lua).

local Vars = require("src/tracking/core/vars")
local Objects = require("src/tracking/core/objects")
local data = require("src/tracking/data/archaeology")

local Archaeology = {}

Archaeology.PREFIX = "Archaeology: "
Archaeology.MATERIALS = "Archaeology: Materials"
local KEY_PREFIX = "arch-art:"

local byKey, byGroup, groupList, built = {}, {}, {}, false

local function build()
    if built then return end
    built = true
    for _, faction in ipairs(data.FACTIONS) do
        local group = { name = Archaeology.PREFIX .. faction.name, subs = {}, collections = {} }
        for _, collection in ipairs(faction.collections) do
            local entry = { id = collection.id, label = collection.collector .. ": " .. collection.name, faction = faction.name,
                group = group.name, collector = collection.collector, location = collection.location,
                rewards = collection.rewards, complete = collection.complete, items = {} }
            group.subs[#group.subs + 1] = { name = entry.label }
            group.collections[entry.label] = entry
            for _, item in ipairs(collection.items) do
                local artefact = { key = KEY_PREFIX .. item[3]:lower(), obj = item[1], fallback = item[2], var = item[3], collection = entry }
                entry.items[#entry.items + 1] = artefact
                byKey[artefact.key] = artefact
            end
        end
        groupList[#groupList + 1] = group
        byGroup[group.name] = group
    end
end

local function safe(value) return (tostring(value):gsub("<", "["):gsub(">", "]")) end

local function nameOf(artefact)
    local name = Objects.objectDisplayName(artefact.obj)
    return name or artefact.fallback
end

local function readVar(name)
    local entry = Vars.resolveVar(name)
    local value = entry and Vars.readEntry(entry)
    return type(value) == "number" and value or nil
end

function Archaeology.isKey(key) return type(key) == "string" and key:sub(1, #KEY_PREFIX) == KEY_PREFIX end

-- Whether a Gathering group name is one of the faction groups (needs no game data, saved notes load before it).
function Archaeology.isGroup(name)
    if type(name) ~= "string" or name == Archaeology.MATERIALS or name:sub(1, #Archaeology.PREFIX) ~= Archaeology.PREFIX then
        return false
    end
    build()
    return byGroup[name] ~= nil
end

-- The faction groups for the second dropdown, each with its collections as the third.
function Archaeology.groups()
    build()
    local list = {}
    for _, group in ipairs(groupList) do list[#list + 1] = { name = group.name, subs = group.subs, subLabel = "Collection" } end
    return list
end

function Archaeology.options(groupName, sub)
    build()
    local group = byGroup[groupName]
    if not group then return {} end
    local collection = sub and group.collections[sub] or group.collections[group.subs[1].name]
    if not collection then return {} end
    local options = {}
    for _, artefact in ipairs(collection.items) do
        options[#options + 1] = {
            kind = "artefact", key = artefact.key, label = nameOf(artefact), varName = artefact.var, defaultTarget = 1,
            objId = artefact.obj,
            description = "Counts once it is in this collection. Handing the collection in starts it again, and the note with it.",
        }
    end
    return options
end

-- The collection a saved artefact belongs to (to reopen a note on the right one), or nil.
function Archaeology.collectionOf(key)
    build()
    local artefact = byKey[key]
    return artefact and artefact.collection.label or nil, artefact and artefact.collection.group or nil
end

local function progressLine(collection)
    local have = 0
    for _, artefact in ipairs(collection.items) do
        local value = readVar(artefact.var)
        if value and value >= 1 then have = have + 1 end
    end
    return have, #collection.items
end

function Archaeology.card(key)
    build()
    local artefact = byKey[key]
    if not artefact then return nil end
    local collection = artefact.collection
    local value = readVar(artefact.var)
    local lines = { safe(nameOf(artefact)), "<br>" .. safe(collection.label) }
    lines[#lines + 1] = (value and value >= 1) and "<br><col=55FF55>In the collection</col>" or "<br>Not in the collection yet"
    local have, total = progressLine(collection)
    lines[#lines + 1] = "<br>" .. have .. " / " .. total .. " in this collection"
    lines[#lines + 1] = "<br>Hand in to " .. safe(collection.collector) .. " (" .. safe(collection.location) .. ")"
    if #collection.rewards > 0 then lines[#lines + 1] = "<br>Reward: " .. safe(table.concat(collection.rewards, ", ")) end
    if collection.complete then
        local done = readVar(collection.complete)
        if done and done >= 1 then lines[#lines + 1] = "<br>You have handed this collection in before" end
    end
    return { key = key, body = table.concat(lines) }
end

return { Archaeology = Archaeology }
