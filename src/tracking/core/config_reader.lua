-- Safe, cached, read-only access to the game's own config data (structs, database rows, enums).
-- Every call is wrapped so a missing config or a changed layout returns nil instead of raising, which lets the
-- data features fall back to the snapshots baked into the plugin.

local ConfigReader = {}

local cache = { row = {}, struct = {}, enum = {}, columns = {}, quest = {}, achievement = {} }

local function safe(fn, ...)
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
    return nil
end

local function lookup(kind, key)
    if key == nil or type(config) ~= "table" and type(config) ~= "userdata" then return nil end
    local group = safe(function() return config[kind] end)
    if not group then return nil end
    if type(key) == "number" then return safe(function() return group.FromID(key) end) end
    -- Config names are upper case in the API (config.DBRow.INVENT_PERK_LOOTING); the dumps list them in lower case.
    return safe(function() return group[key:upper()] end) or safe(function() return group[key] end)
end

-- Any config object by kind ("Loc", "Struct", "Obj"...) and config name or id.
function ConfigReader.Config(kind, key) return lookup(kind, key) end

function ConfigReader.Available()
    return (safe(function() return config.DBRow ~= nil and config.Enum ~= nil and config.Struct ~= nil end)) == true
end

local function remember(store, key, build)
    if key == nil then return nil end -- a name the game no longer knows arrives as nil
    local hit = store[key]
    if hit ~= nil then return hit or nil end
    local value = build()
    store[key] = value == nil and false or value
    return value
end

-- A database row by config name or id.
function ConfigReader.Row(key) return remember(cache.row, key, function() return lookup("DBRow", key) end) end
function ConfigReader.Quest(key) return remember(cache.quest, key, function() return lookup("Quest", key) end) end
function ConfigReader.Achievement(key) return remember(cache.achievement, key, function() return lookup("Achievement", key) end) end
function ConfigReader.Struct(key) return remember(cache.struct, key, function() return lookup("Struct", key) end) end
function ConfigReader.Enum(key) return remember(cache.enum, key, function() return lookup("Enum", key) end) end

-- All values in one column of a row: { values = {..}, types = {..}, count = n }. Column indexes are 1-based.
function ConfigReader.Column(row, index)
    if not row then return nil end
    local count = safe(function() return row:GetColumnValueCount(index) end)
    if not count then return nil end
    local values = safe(function() return row:GetColumnValues(index) end) or {}
    local types = safe(function() return row:GetColumnValueTypes(index) end) or {}
    return { values = values, types = types, count = count }
end

-- The first value of a column, or nil when the column is empty.
function ConfigReader.Value(row, index)
    local column = ConfigReader.Column(row, index)
    if column and column.count > 0 then return column.values[1] end
end

function ConfigReader.ColumnCount(row)
    return row and safe(function() return row.columnCount end) or 0
end

-- Enum helpers.
function ConfigReader.EnumValue(enum, key)
    if type(enum) ~= "table" and type(enum) ~= "userdata" then enum = ConfigReader.Enum(enum) end
    if not enum then return nil end
    return safe(function() return enum:GetOutputValue(key) end)
end

function ConfigReader.EnumPairs(enum)
    if type(enum) == "string" or type(enum) == "number" then enum = ConfigReader.Enum(enum) end
    if not enum then return {} end
    return safe(function() return enum.values end) or {}
end

-- Struct helpers.
function ConfigReader.StructParam(struct, param)
    if type(struct) == "string" or type(struct) == "number" then struct = ConfigReader.Struct(struct) end
    if type(param) == "string" then param = lookup("Param", param) end
    if not struct or not param then return nil end
    if not safe(function() return struct:HasParam(param) end) then return nil end
    return safe(function() return struct:GetParamValue(param) end)
end

-- Every database row that belongs to a table, by table config name (e.g. "INVENT_MATERIAL_TABLE"). The API has no
-- "list the rows of a table" call, so the row ids are walked once and grouped by the table each row reports; the result
-- is kept for the rest of the session. Returns a list of { id =, name =, row = } in id order.
local MAX_ROW_ID, MAX_ROW_GAP = 200000, 1500
local scanned

local function scanRows()
    local byTable, misses = {}, 0
    local started = type(os) == "table" and os.clock and os.clock() or 0
    for index = 0, MAX_ROW_ID do
        local row = lookup("DBRow", index)
        if row then
            misses = 0
            local owner = safe(function() return row.ownerDBTable end)
            local tableName = owner and safe(function() return owner.configName end)
            if type(tableName) == "string" then
                local list = byTable[tableName:upper()]
                if not list then list = {}; byTable[tableName:upper()] = list end
                list[#list + 1] = { id = index, name = safe(function() return row.configName end), row = row }
            end
        else
            misses = misses + 1
            if misses > MAX_ROW_GAP then break end
        end
    end
    byTable.seconds = type(os) == "table" and os.clock and (os.clock() - started) or 0
    return byTable
end

function ConfigReader.TableRows(tableName)
    if not scanned then scanned = scanRows() end
    local list = scanned[tostring(tableName):upper()] or {}
    local copy = {}
    for index, entry in ipairs(list) do copy[index] = entry end
    return copy
end

-- Every achievement, in id order: { id =, name = configName, achievement = }. Walked once and kept for the session.
local achievementList
function ConfigReader.AchievementList()
    if achievementList then return achievementList end
    local list, misses = {}, 0
    for index = 0, 100000 do
        local achievement = lookup("Achievement", index)
        if achievement then
            misses = 0
            list[#list + 1] = { id = index, name = safe(function() return achievement.configName end), achievement = achievement }
        else
            misses = misses + 1
            if misses > (#list == 0 and 3000 or 1500) then break end
        end
    end
    achievementList = list
    return list
end

function ConfigReader.Clear()
    scanned = nil
    achievementList = nil
    cache = { row = {}, struct = {}, enum = {}, columns = {}, quest = {}, achievement = {} }
end

-- Reads a named property of any config object, or nil.
function ConfigReader.Field(object, name)
    if object == nil then return nil end
    return safe(function() return object[name] end)
end

-- A param value from a quest, achievement or struct, by param name (e.g. "QUEST_DESCRIPTION").
function ConfigReader.Param(object, paramName)
    if object == nil then return nil end
    local param = lookup("Param", paramName)
    if not param then return nil end
    if not safe(function() return object:HasParam(param) end) then return nil end
    return safe(function() return object:GetParamValue(param) end)
end

return ConfigReader