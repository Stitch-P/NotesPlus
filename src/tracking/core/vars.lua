-- This is a lot of Variable stuff to do here... eek

local Pouch = require("src/tracking/core/pouch")

-- Variables the game keeps at a fraction of the real amount: read as value * scale (produce points are kept in tens).
local SCALE = { LUNARFM_PRODUCE_POINTS = 10 }

local function trim(text)
    return (tostring(text or ""):match("^%s*(.-)%s*$"))
end

local function resolveVar(input)
    input = trim(input)
    if input == "" then return nil end

    -- A currency held in the currency pouch reads like a variable.
    if Pouch.isName(input) then
        if not Pouch.known(input) then return nil end
        local name = Pouch.PREFIX .. input:sub(#Pouch.PREFIX + 1):upper()
        return setmetatable({ configName = name }, { __index = function(_, key)
            if key == "value" then return Pouch.count(name) end
        end }), name, nil
    end

    local entry
    if input:match("^%-?%d+$") then
        local numericId = tonumber(input)
        local ok, found = pcall(function()
            return var.VarPlayer.FromID(numericId)
        end)
        if ok then entry = found end
    else
        local ok, found = pcall(function()
            return var.VarPlayer[input:upper()]
        end)
        if ok then entry = found end
    end
    if not entry then return nil end

    local okName, name = pcall(function() return entry.configName end)
    if not okName or type(name) ~= "string" or name == "" then return nil end

    local okId, varId = pcall(function() return entry.id end)
    if not okId or type(varId) ~= "number" then varId = nil end

    local scale = SCALE[name:upper()]
    if scale then
        local raw = entry
        entry = setmetatable({ configName = name, id = varId }, { __index = function(_, key)
            if key == "value" then
                local ok, value = pcall(function() return raw.value end)
                return ok and type(value) == "number" and value * scale or nil
            end
        end })
    end

    return entry, name, varId
end

-- Returns the numeric value of a resolved VarPlayer entry, or nil.
local function readEntry(entry)
    if not entry then return nil end
    local ok, value = pcall(function()
        return entry.value
    end)
    if ok and type(value) == "number" then
        return value
    end
    return nil
end

-- I like commas, and others should also!
local function withCommas(number)
    local text = tostring(math.floor(number))
    local sign, digits = text:match("^(%-?)(%d+)$")
    if not digits then return text end
    digits = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return sign .. digits
end

local function clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

-- A typed amount: "137000000", "137,000,000", "137m", "1.5k" or "2b". nil when it isn't a number.
local SUFFIXES = { k = 1e3, m = 1e6, b = 1e9 }
local function parseNumber(text)
    local value = trim(text):gsub(",", ""):gsub("%s+", "")
    local plain = tonumber(value)
    if plain then return plain end
    local digits, suffix = value:match("^(%d*%.?%d+)([kKmMbB])$")
    if not digits then return nil end
    local number = tonumber(digits)
    if not number then return nil end
    number = number * SUFFIXES[suffix:lower()]
    -- Whole amounts stay whole numbers (137m is 137000000, not 1.37e8).
    return number == math.floor(number) and math.floor(number) or number
end

return {
    trim = trim,
    parseNumber = parseNumber,
    resolveVar = resolveVar,
    readEntry = readEntry,
    withCommas = withCommas,
    clamp = clamp,
}
