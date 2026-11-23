-- Invention: material counts, and which device blueprints you have unlocked.
local baked = require("src/tracking/data/invention")
local componentPerks = require("src/tracking/data/component_perks")
local InventionSource = require("src/tracking/core/invention_source")
local COMPONENTS, PARTS, DEVICES, RESEARCH_GROUPS

local Invention = {}

local GROUP_COMPONENTS = "Components"
local MAX_PER_GROUP = 30 -- the dropdown stops being usable well before this, so long lists are split

-- Long lists are cut into even, alphabetical chunks named by their first and last letters.
local function chunked(name, options)
    table.sort(options, function(a, b) return a.label:lower() < b.label:lower() end)
    if #options <= MAX_PER_GROUP then return { { name = name, options = options } } end
    local count = math.ceil(#options / MAX_PER_GROUP)
    local size = math.ceil(#options / count)
    local result = {}
    for first = 1, #options, size do
        local last = math.min(first + size - 1, #options)
        local slice = {}
        for index = first, last do slice[#slice + 1] = options[index] end
        local from, to = slice[1].label:sub(1, 1):upper(), slice[#slice].label:sub(1, 1):upper()
        result[#result + 1] = { name = name .. " (" .. from .. (from ~= to and ("-" .. to) or "") .. ")", options = slice }
    end
    return result
end

local groupCache
local groupByName, optionByKey = {}, {}
local materialOptionByKey, researchComponentByKey, researchMaterialByKey = {}, {}, {}
local materialByName, materialByKey = {}, {}

-- The lists come from the game's own data the first time they're needed, with the snapshot in data/invention.lua as
-- the base and the fallback.
local loaded, liveReport
local function dataset()
    if loaded then return end
    loaded = true
    local ok, source = pcall(InventionSource.Load, baked)
    if ok and source then
        COMPONENTS, PARTS, DEVICES, RESEARCH_GROUPS = source.COMPONENTS, source.PARTS, source.DEVICES, source.RESEARCH_GROUPS
        liveReport = source.report
    else
        COMPONENTS, PARTS, DEVICES, RESEARCH_GROUPS = baked.COMPONENTS, baked.PARTS, baked.DEVICES, baked.RESEARCH_GROUPS
    end
    for _, list in ipairs({COMPONENTS, PARTS}) do
        for _, item in ipairs(list) do
            materialByName[item[1]], materialByKey[item[2]] = item, item
        end
    end
end

local function describe(item)
    local perks = item and componentPerks[item[2]]
    if not perks then return nil end
    local lines = {}
    for _, group in ipairs({{"weapon", "Weapon"}, {"armour", "Armour"}, {"tool", "Tool"}}) do
        local names = perks[group[1]]
        if names and #names > 0 then lines[#lines + 1] = group[2] .. ": " .. table.concat(names, ", ") end
    end
    if #lines == 0 then lines[1] = "No perks." end
    if perks.ancient then lines[#lines + 1] = "Ancient gizmos only." end
    if item[5] then lines[#lines + 1] = "Disassembly sources: " .. item[5] end
    return table.concat(lines, "\n")
end

local function materialOptions()
    dataset()
    local options = {}
    for _, list in ipairs({ COMPONENTS, PARTS }) do
        for _, item in ipairs(list) do
            options[#options + 1] = {
                kind = "material", varName = item[2], key = item[2], label = item[1], spriteName = item[3],
                description = describe(item),
            }
        end
    end
    return options
end

-- Blueprints are one bit each in a run of 32-bit varps; the bit rides along in the key.
local function blueprintOptions(list, researchComponents)
    local options = {}
    for _, item in ipairs(list) do
        local name, blueprint, sprite, details = item[1], item[2], item[3], item[4]
        if researchComponents then details = describe(materialByName[name]) end
        local varName = "INVENT_BLUEPRINT_UNLOCKED_" .. math.floor(blueprint / 32)
        options[#options + 1] = {
            kind = "blueprint", varName = varName, key = varName .. ":" .. (blueprint % 32), label = name,
            spriteName = type(sprite) == "string" and sprite or "#" .. sprite, description = details, steps = 1, defaultTarget = 1,
        }
    end
    return options
end

local function allGroups()
    if groupCache then return groupCache end
    dataset()
    local components = materialOptions()
    table.sort(components, function(a, b) return a.label:lower() < b.label:lower() end)
    groupCache = {{name = GROUP_COMPONENTS, options = components}}
    for _, name in ipairs(RESEARCH_GROUPS) do
        local options = blueprintOptions(DEVICES[name] or {}, name == "Components")
        local groups = chunked("Research: " .. name, options)
        if name == "Components" then groups = {{name = "Research: Components", options = options}} end
        for _, group in ipairs(groups) do
            groupCache[#groupCache + 1] = group
        end
    end
    for _, group in ipairs(groupCache) do
        groupByName[group.name] = group
        for _, option in ipairs(group.options) do
            optionByKey[option.key] = optionByKey[option.key] or option
            if group.name == GROUP_COMPONENTS then
                materialOptionByKey[option.key] = option
            elseif group.name == "Research: Components" then
                researchComponentByKey[option.key] = option
                researchMaterialByKey[option.key] = materialByName[option.label]
            end
        end
    end
    return groupCache
end

-- "game" when the lists were refreshed from the game's data, plus what the game added that the plugin didn't know.
function Invention.source()
    dataset()
    return liveReport and "game" or "snapshot", liveReport
end

function Invention.groups()
    local list = {}
    for _, group in ipairs(allGroups()) do list[#list + 1] = { name = group.name } end
    return list
end

function Invention.options(group)
    allGroups()
    local entry = group and groupByName[group.name]
    local copy = {}
    if entry then
        for index, option in ipairs(entry.options) do copy[index] = option end
    end
    return copy
end

function Invention.materialOption(key)
    allGroups()
    return materialOptionByKey[key]
end

function Invention.researchComponentOption(key)
    allGroups()
    return researchComponentByKey[key]
end

function Invention.perks(key)
    if componentPerks[key] then return componentPerks[key] end
    allGroups()
    local material = researchMaterialByKey[key]
    return material and componentPerks[material[2]] or nil
end

function Invention.sources(key)
    dataset()
    local material = materialByKey[key]
    if not material then
        allGroups()
        material = researchMaterialByKey[key]
    end
    return material and material[5] or nil
end

-- For the tooltip on notes that are already saved.
function Invention.description(key)
    allGroups()
    local option = optionByKey[key]
    return option and option.description or nil
end

-- "Research: Tools" -> "Research". Materials get no prefix at all (nil): the name says enough.
function Invention.titleName(name)
    if name:match("^Research") then return "Research" end
    return nil
end

-- Is the blueprint bit in this key set in the varp value? Returns nil if the key isn't a bit key.
function Invention.bitOf(key)
    local bit = type(key) == "string" and key:match("^INVENT_BLUEPRINT_UNLOCKED_%d+:(%d+)$")
    return bit and tonumber(bit) or nil
end

function Invention.readBit(value, bit)
    if value < 0 then value = value + 4294967296 end
    return math.floor(value / 2 ^ bit) % 2 == 1 and 1 or 0
end

return { Invention = Invention }
