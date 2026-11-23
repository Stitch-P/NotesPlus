-- Invention materials and device blueprints, refreshed from the game's own database rows
-- (INVENT_MATERIAL_TABLE and INVENT_BLUEPRINT_TABLE). The baked lists in data/invention.lua stay the base: the game's
-- names, descriptions and sprites replace them, and anything the game has added since appears as a new entry.

local ConfigReader = require("src/tracking/core/config_reader")

local InventionSource = {}

-- Material row columns: 2 name, 3 flavour text, 4 what produces it, 5 or 6 sprite (worked out below).
-- Blueprint row columns: 1 blueprint number, 2 name, 4 description, 6 sprite, 10 the group it is listed under.
local MATERIAL_NAME, MATERIAL_FLAVOUR, MATERIAL_SOURCES = 2, 3, 4
local BLUEPRINT_INDEX, BLUEPRINT_NAME, BLUEPRINT_DETAILS, BLUEPRINT_SPRITE, BLUEPRINT_GROUP = 1, 2, 4, 6, 10

local function text(value)
    return type(value) == "string" and value ~= "" and value or nil
end

local function copyList(list)
    local copy = {}
    for index, item in ipairs(list) do
        local entry = {}
        for key, value in pairs(item) do entry[key] = value end
        copy[index] = entry
    end
    return copy
end

local function spriteId(name)
    local ok, value = pcall(function() return id.Sprite[name] end)
    return ok and type(value) == "number" and value or nil
end

local function resolvable(varName)
    local ok, Vars = pcall(require, "src/tracking/core/vars")
    if not ok then return true end
    local found, entry = pcall(Vars.resolveVar, varName)
    return found and entry ~= nil
end

-- Which of columns 5 and 6 holds the material's sprite: whichever agrees with the sprites we already know by name.
local function spriteColumn(rows, baked)
    local score = { [5] = 0, [6] = 0 }
    local byVar = {}
    for _, entry in ipairs(rows) do byVar[entry.name and entry.name:upper()] = entry end
    for _, list in ipairs({ baked.COMPONENTS, baked.PARTS }) do
        for _, item in ipairs(list) do
            local entry, sprite = byVar[item[2]], type(item[3]) == "string" and spriteId(item[3]) or nil
            if entry and sprite then
                for column = 5, 6 do
                    if ConfigReader.Value(entry.row, column) == sprite then score[column] = score[column] + 1 end
                end
            end
        end
    end
    return score[6] > score[5] and 6 or 5
end

local function refreshMaterials(rows, baked, report)
    local column = spriteColumn(rows, baked)
    report.spriteColumn = column
    local components, parts = copyList(baked.COMPONENTS), copyList(baked.PARTS)
    local seen = {}
    for _, list in ipairs({ components, parts }) do
        for _, item in ipairs(list) do seen[item[2]] = item end
    end
    for _, entry in ipairs(rows) do
        local varName = entry.name and entry.name:upper()
        if varName then
            local name = text(ConfigReader.Value(entry.row, MATERIAL_NAME))
            local flavour = text(ConfigReader.Value(entry.row, MATERIAL_FLAVOUR))
            local sources = text(ConfigReader.Value(entry.row, MATERIAL_SOURCES))
            local item = seen[varName]
            if item then
                item[1] = name or item[1]
                item[4] = flavour or item[4]
                item[5] = sources or item[5]
            elseif name and resolvable(varName) then
                local sprite = ConfigReader.Value(entry.row, column)
                local added = { name, varName, type(sprite) == "number" and sprite > 0 and ("#" .. sprite) or nil, flavour or "", sources }
                local list = name:lower():find("parts$") and parts or components
                list[#list + 1] = added
                seen[varName] = added
                report.newMaterials[#report.newMaterials + 1] = name
            end
        end
    end
    return components, parts
end

local function refreshBlueprints(rows, baked, report)
    local devices, byIndex, votes = {}, {}, {}
    for group, list in pairs(baked.DEVICES) do
        devices[group] = copyList(list)
        for _, item in ipairs(devices[group]) do byIndex[item[2]] = { item = item, group = group } end
    end
    local live = {}
    for _, entry in ipairs(rows) do
        local index = ConfigReader.Value(entry.row, BLUEPRINT_INDEX)
        if type(index) == "number" then
            live[#live + 1] = { index = index, entry = entry, groupKey = ConfigReader.Value(entry.row, BLUEPRINT_GROUP) }
        end
    end
    -- Learn which value of the group column means which group from the blueprints we already file.
    for _, item in ipairs(live) do
        local known = byIndex[item.index]
        if known and item.groupKey ~= nil then
            votes[item.groupKey] = votes[item.groupKey] or {}
            votes[item.groupKey][known.group] = (votes[item.groupKey][known.group] or 0) + 1
        end
    end
    local groupOf = {}
    for key, counts in pairs(votes) do
        local best, bestCount
        for group, count in pairs(counts) do
            if not bestCount or count > bestCount then best, bestCount = group, count end
        end
        groupOf[key] = best
    end
    for _, item in ipairs(live) do
        local row = item.entry.row
        local name = text(ConfigReader.Value(row, BLUEPRINT_NAME))
        local details = text(ConfigReader.Value(row, BLUEPRINT_DETAILS))
        local sprite = ConfigReader.Value(row, BLUEPRINT_SPRITE)
        local known = byIndex[item.index]
        if known then
            known.item[1] = name or known.item[1]
            known.item[3] = type(sprite) == "number" and sprite > 0 and sprite or known.item[3]
            known.item[4] = details or known.item[4]
        else
            local group = groupOf[item.groupKey]
            if name and group and type(sprite) == "number" and sprite > 0 and details then
                devices[group] = devices[group] or {}
                devices[group][#devices[group] + 1] = { name, item.index, sprite, details }
                report.newBlueprints[#report.newBlueprints + 1] = name
            end
        end
    end
    return devices
end

-- { COMPONENTS, PARTS, DEVICES, RESEARCH_GROUPS, report } or nil.
function InventionSource.Load(baked)
    if not ConfigReader.Available() then return nil end
    local materials = ConfigReader.TableRows("INVENT_MATERIAL_TABLE")
    local blueprints = ConfigReader.TableRows("INVENT_BLUEPRINT_TABLE")
    if #materials < 10 or #blueprints < 20 then return nil end
    local report = { newMaterials = {}, newBlueprints = {}, materials = #materials, blueprints = #blueprints }
    local components, parts = refreshMaterials(materials, baked, report)
    local devices = refreshBlueprints(blueprints, baked, report)
    return { COMPONENTS = components, PARTS = parts, DEVICES = devices, RESEARCH_GROUPS = baked.RESEARCH_GROUPS, report = report }
end

return InventionSource
