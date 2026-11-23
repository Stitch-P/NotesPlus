local Vars = require("src/tracking/core/vars")

local Clock = {}
local minute, elapsed, nextCheck, used = nil, 0, 0, false
local MONTHS = {"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"}
local MONTH_DAYS = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}

local function leap(year)
    return year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)
end

function Clock.DateText(value)
    local days, year = math.floor(value / 1440), 1970
    while true do
        local span = leap(year) and 366 or 365
        if days < span then break end
        days, year = days - span, year + 1
    end
    for month, length in ipairs(MONTH_DAYS) do
        local span = month == 2 and leap(year) and 29 or length
        if days < span then return MONTHS[month] .. " " .. tostring(days + 1) .. ", " .. tostring(year) end
        days = days - span
    end
end

local function refresh()
    local value = Vars.readEntry(Vars.resolveVar("CLOCK_TIME_DATE_MINUTES"))
    local previous = minute
    minute = type(value) == "number" and value == value and value > 0 and value < math.huge and math.floor(value) or nil
    nextCheck = elapsed + 60
    return minute ~= previous
end

function Clock.Minutes()
    if not used then used = true; refresh() end
    return minute
end

function Clock.Day()
    local value = Clock.Minutes()
    return value and math.floor(value / 1440) or nil
end

function Clock.Weekday()
    local day = Clock.Day()
    return day and (day + 4) % 7 + 1 or nil
end

function Clock.Tick(now)
    if type(now) ~= "number" then return false end
    elapsed = now
    if not used or elapsed < nextCheck then return false end
    return refresh()
end

function Clock.Clear()
    minute, elapsed, nextCheck, used = nil, 0, 0, false
end

return Clock
