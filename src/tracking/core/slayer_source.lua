-- Builds the Slayer logs from the game's own data: the collection_slayer_* database rows (area name, achievement,
-- drop list) and their achievements (title, sprite, text). New Slayer areas turn up on their own when the game adds
-- an ITEMLOG_SLAYER_* achievement. Returns nil when it can't read enough, and the Slayer feature then uses the
-- snapshot baked into data/slayer.lua.

local ConfigReader = require("src/tracking/core/config_reader")

local SlayerSource = {}

local NAME_COLUMN, ACHIEVEMENT_COLUMN, ITEMS_COLUMN = 5, 10, 14
local TITLE_PREFIX = "ITEMLOG_SLAYER_"

local function keyFromTitle(title)
    if type(title) ~= "string" then return nil end
    return title:match("^ITEMLOG_SLAYER_(.+)_TITLE$")
end

-- Area keys the game has an ITEMLOG_SLAYER_* achievement for.
local function discoverKeys()
    local keys = {}
    for _, entry in ipairs(ConfigReader.AchievementList()) do
        local name = entry.name
        if type(name) == "string" and name:sub(1, #TITLE_PREFIX) == TITLE_PREFIX then
            local key = name:sub(#TITLE_PREFIX + 1)
            if not key:find("TITLE$") and not key:find("^ALL_LOGS") then keys[#keys + 1] = key end
        end
    end
    return keys
end

local function number(value)
    if type(value) == "number" then return value end
    local id = ConfigReader.Field(value, "id")
    if type(id) == "number" then return id end
end

local function achievementText(achievement)
    local name = ConfigReader.Field(achievement, "name")
    local reward = ConfigReader.Field(achievement, "reward")
    local text
    for _, entry in ipairs(ConfigReader.Field(achievement, "descriptions") or {}) do
        local kind = ConfigReader.Field(entry, "type")
        local line = ConfigReader.Field(entry, "text")
        if type(line) == "string" and line ~= "" and (text == nil or kind == 0) then text = line end
    end
    if type(name) ~= "string" or name == "" then return nil end
    local parts = { name .. ":" }
    if text then parts[#parts + 1] = text end
    if type(reward) == "string" and reward ~= "" then parts[#parts + 1] = "Reward: " .. reward end
    return table.concat(parts, " ")
end

local function titleVar(achievement, key)
    local requirements = ConfigReader.Field(achievement, "requirements")
    local totals = type(requirements) == "table" and requirements.varTotals
    local first = type(totals) == "table" and totals[1] or nil
    local vars = first and ConfigReader.Field(first, "vars")
    local name = type(vars) == "table" and vars[1] and ConfigReader.Field(vars[1], "configName")
    if type(name) == "string" and name ~= "" then return name end
    return TITLE_PREFIX .. key .. "_TITLE"
end

-- baked: the snapshot AREAS, used for the area names saved notes already refer to and as the list of known areas.
function SlayerSource.Load(baked)
    if not ConfigReader.Available() then return nil end
    local known, order = {}, {}
    local nameByKey, bakedByKey = {}, {}
    for _, area in ipairs(baked or {}) do
        local key = keyFromTitle(area[2]) or (area[1] == "General" and "GENERAL" or nil)
        if key then
            known[key] = true
            order[#order + 1] = key
            nameByKey[key] = area[1]
            bakedByKey[key] = area
        end
    end
    -- Areas the plugin doesn't know yet go before "General", which stays last.
    local general = false
    for index, key in ipairs(order) do
        if key == "GENERAL" then table.remove(order, index); general = true; break end
    end
    for _, key in ipairs(discoverKeys()) do
        if not known[key] then known[key] = true; order[#order + 1] = key end
    end
    if general then order[#order + 1] = "GENERAL" end

    local areas = {}
    for _, key in ipairs(order) do
        local row = ConfigReader.Row("COLLECTION_SLAYER_" .. key)
        local column = row and ConfigReader.Column(row, ITEMS_COLUMN)
        if column and type(column.values) == "table" and #column.values > 0 then
            local achievement = ConfigReader.Value(row, ACHIEVEMENT_COLUMN)
            local name = nameByKey[key] or ConfigReader.Value(row, NAME_COLUMN)
            if type(name) == "string" and name ~= "" then
                local items = {}
                for _, object in ipairs(column.values) do
                    local objId = number(object)
                    if objId then
                        local objName = ConfigReader.Field(object, "configName")
                        items[#items + 1] = { type(objName) == "string" and objName ~= "" and objName or nil, nil, objId }
                    end
                end
                if achievement then
                    local sprite = ConfigReader.Field(achievement, "spriteID")
                    areas[#areas + 1] = { name, titleVar(achievement, key), type(sprite) == "number" and sprite > 0 and sprite or nil,
                        achievementText(achievement), items }
                else
                    areas[#areas + 1] = { name, nil, nil, nil, items }
                end
            end
        elseif bakedByKey[key] then
            areas[#areas + 1] = bakedByKey[key]
        end
    end
    if #areas < 3 then return nil end
    return areas
end

return SlayerSource
