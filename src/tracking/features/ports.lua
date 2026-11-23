-- Ports: exploration progress, split into the map's regions.
local data_m = require("src/tracking/data/ports")
local EXPLORED_VAR, REGIONS, TRADE_GOODS = data_m.EXPLORED_VAR, data_m.REGIONS, data_m.TRADE_GOODS
local PORT_RESOURCES = data_m.PORT_RESOURCES
local vars_m = require("src/tracking/core/vars")
local withCommas = vars_m.withCommas

--Let's ensure we can never track progress to the Arc (since we start there!)
local START_REGION = "The Arc"

local Ports = {}

local GROUP_REGIONS, GROUP_GOODS, GROUP_RESOURCES = "Regions", "Trade Goods", "Ports Resources"

function Ports.groups()
    return { { name = GROUP_REGIONS }, { name = GROUP_GOODS }, { name = GROUP_RESOURCES } }
end

-- One option per region.
local function regionOptions()
    local options = {}
    for index, region in ipairs(REGIONS) do
        local name, first, last, sprite = region[1], region[2], region[3], region[4]
        local goal = last + 1
        options[#options + 1] = {
            kind = "region", varName = EXPLORED_VAR, key = EXPLORED_VAR .. ":" .. name, label = name,
            spriteName = sprite, rank = index, steps = goal, defaultTarget = goal,
            description = "Explored " .. withCommas(first) .. " to " .. withCommas(last) .. " in "
                .. (REGIONS[index - 1] and REGIONS[index - 1][1] or START_REGION) .. ".",
        }
    end
    return options
end

-- Trade goods and port resources are counted as they are.
local function stockOptions(list)
    local options = {}
    for index, item in ipairs(list) do
        options[#options + 1] = {
            kind = "good", varName = item[2], key = item[2], label = item[1], spriteName = item[3], rank = index,
        }
    end
    return options
end

local optionGroups, stockByGroup, regionByKey

local function allOptions()
    if optionGroups then return optionGroups end
    optionGroups = {
        [GROUP_REGIONS] = regionOptions(),
        [GROUP_GOODS] = stockOptions(TRADE_GOODS),
        [GROUP_RESOURCES] = stockOptions(PORT_RESOURCES),
    }
    stockByGroup, regionByKey = {}, {}
    for _, option in ipairs(optionGroups[GROUP_REGIONS]) do regionByKey[option.key] = option end
    for _, name in ipairs({GROUP_GOODS, GROUP_RESOURCES}) do
        local byKey = {}
        for _, option in ipairs(optionGroups[name]) do byKey[option.key] = option end
        stockByGroup[name] = byKey
    end
    return optionGroups
end

function Ports.options(group)
    local name = group and group.name
    if name ~= GROUP_GOODS and name ~= GROUP_RESOURCES then name = GROUP_REGIONS end
    local copy = {}
    for index, option in ipairs(allOptions()[name]) do
        local entry = {}
        for key, value in pairs(option) do entry[key] = value end
        copy[index] = entry
    end
    return copy
end

function Ports.stockOption(group, key)
    local name = type(group) == "table" and group.name or group
    if name ~= GROUP_GOODS and name ~= GROUP_RESOURCES then return nil end
    allOptions()
    return stockByGroup[name][key]
end

function Ports.description(key)
    allOptions()
    local option = regionByKey[key]
    return option and option.description or nil
end

return { Ports = Ports }
