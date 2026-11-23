-- Daemonheim floors: one goal per floor (1-60), done once you have completed it. Normal and Hard mode are separate groups,
-- each with its own set of variables (RAND_COMPLETED_FLOOR_n / RAND_HARD_MODE_FLOOR_n). Floors come in themes, shown in the tooltip.

local Floors = {}

Floors.COUNT = 60
Floors.NORMAL = "Daemonheim floors"
Floors.HARD = "Daemonheim hard mode floors"

local MODES = {
    [Floors.NORMAL] = { prefix = "RAND_COMPLETED_FLOOR_", noun = "floor" },
    [Floors.HARD] = { prefix = "RAND_HARD_MODE_FLOOR_", noun = "hard mode floor" },
}

local THEMES = {
    { name = "Frozen", from = 1, to = 11 },
    { name = "Abandoned 1", from = 12, to = 17 },
    { name = "Furnished", from = 18, to = 29 },
    { name = "Abandoned 2", from = 30, to = 35 },
    { name = "Occult", from = 36, to = 47 },
    { name = "Warped", from = 48, to = 60 },
}

function Floors.isGroup(name) return MODES[name] ~= nil end

function Floors.groups()
    return { { name = Floors.NORMAL }, { name = Floors.HARD } }
end

function Floors.theme(floor)
    for _, theme in ipairs(THEMES) do
        if floor >= theme.from and floor <= theme.to then return theme end
    end
end

-- "RAND_COMPLETED_FLOOR_12" -> 12, only for variables of either mode.
function Floors.isKey(key)
    if type(key) ~= "string" then return false end
    for _, mode in pairs(MODES) do
        local number = key:match("^" .. mode.prefix .. "(%d+)$")
        if number and tonumber(number) >= 1 and tonumber(number) <= Floors.COUNT then return true end
    end
    return false
end

-- Hover text for a floor, from its variable.
function Floors.describe(variable)
    if not Floors.isKey(variable) then return nil end
    local floor = tonumber(variable:match("(%d+)$"))
    local theme = Floors.theme(floor)
    return (theme and theme.name .. " theme (floors " .. theme.from .. " to " .. theme.to .. ")\n" or "")
        .. "Done once you have completed this floor" .. (variable:match("^RAND_HARD_MODE_") and " in hard mode." or ".")
end

-- "10, 24, 30-33" from a list of floor numbers.
local function ranges(numbers)
    table.sort(numbers)
    local parts, start, previous = {}, nil, nil
    local function flush()
        if not start then return end
        parts[#parts + 1] = start == previous and tostring(start) or (start .. "-" .. previous)
    end
    for _, number in ipairs(numbers) do
        if previous and number == previous + 1 then previous = number
        else flush(); start, previous = number, number end
    end
    flush()
    return table.concat(parts, ", ")
end

-- The lines a floor note shows when the floors picked fill whole themes: one entry per full theme, then one for the rest.
-- Returns nil when no theme is complete (the note keeps its row of numbered tiles). Each entry: { key, name, vars, label }.
function Floors.summary(group, floorKeys)
    local mode = MODES[group]
    if not mode then return nil end
    local picked = {}
    for _, key in ipairs(floorKeys) do
        local number = Floors.isKey(key) and tonumber(key:match("(%d+)$"))
        if number then picked[number] = true end
    end
    local lines, used = {}, {}
    for _, theme in ipairs(THEMES) do
        local whole = true
        for floor = theme.from, theme.to do if not picked[floor] then whole = false; break end end
        if whole then
            local vars = {}
            for floor = theme.from, theme.to do vars[#vars + 1] = mode.prefix .. floor; used[floor] = true end
            lines[#lines + 1] = { key = "floor-theme:" .. theme.name, vars = vars, name = theme.name,
                prefix = theme.name .. ": " .. theme.from .. " - " .. theme.to }
        end
    end
    if #lines == 0 then return nil end
    local rest, vars = {}, {}
    for floor = 1, Floors.COUNT do
        if picked[floor] and not used[floor] then rest[#rest + 1] = floor; vars[#vars + 1] = mode.prefix .. floor end
    end
    if #rest > 0 then
        lines[#lines + 1] = { key = "floor-theme:other", vars = vars, name = "Other floors",
            prefix = (#rest == 1 and "Floor " or "Floors ") .. ranges(rest) }
    end
    return lines
end

function Floors.options(group)
    local mode = MODES[group]
    local options = {}
    if not mode then return options end
    for floor = 1, Floors.COUNT do
        local var = mode.prefix .. floor
        local theme = Floors.theme(floor)
        options[#options + 1] = {
            kind = "floor", key = var, varName = var, label = "Floor " .. floor, tileText = tostring(floor), rank = floor,
            defaultTarget = 1,
            description = (theme and theme.name .. " theme (floors " .. theme.from .. " to " .. theme.to .. ")" or "")
                .. "\nDone once you have completed this floor" .. (group == Floors.HARD and " in hard mode." or "."),
        }
    end
    return options
end

return { Floors = Floors }
