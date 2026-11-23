-- The boss pages of the game's collection log, read from the collection_boss_* database rows: each page's name and the
-- items on it. Used by the Bossing feature on top of its own lists, so a boss or drop the game adds shows up without
-- a plugin update. Returns nil when the rows can't be read.

local ConfigReader = require("src/tracking/core/config_reader")

local BossSource = {}

local NAME_COLUMN, ITEMS_COLUMN = 5, 14
local ROW_PREFIX = "COLLECTION_BOSS_"
local MIN_PAGES = 10

local function number(value)
    if type(value) == "number" then return value end
    local id = ConfigReader.Field(value, "id")
    if type(id) == "number" then return id end
end

-- { { key =, name =, items = { { objId =, objName = } } } } in row order, or nil.
function BossSource.Pages()
    if not ConfigReader.Available() then return nil end
    local pages = {}
    for _, entry in ipairs(ConfigReader.TableRows("COLLECTION")) do
        local rowName = type(entry.name) == "string" and entry.name:upper() or nil
        if rowName and rowName:sub(1, #ROW_PREFIX) == ROW_PREFIX then
            local name = ConfigReader.Value(entry.row, NAME_COLUMN)
            local column = ConfigReader.Column(entry.row, ITEMS_COLUMN)
            local items = {}
            for _, object in ipairs(column and type(column.values) == "table" and column.values or {}) do
                local objId = number(object)
                if objId then
                    local objName = ConfigReader.Field(object, "configName")
                    items[#items + 1] = { objId = objId, objName = type(objName) == "string" and objName ~= "" and objName:upper() or nil }
                end
            end
            if type(name) == "string" and name ~= "" and #items > 0 then
                pages[#pages + 1] = { key = rowName:sub(#ROW_PREFIX + 1), name = name, items = items }
            end
        end
    end
    if #pages < MIN_PAGES then return nil end
    return pages
end

return BossSource
