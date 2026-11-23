local Vars = require("src/tracking/core/vars")
local Clock = require("src/tracking/core/game_clock")
local Access = require("src/tracking/core/access")

local Raven = {}
Raven.GROUP = "Prifddinas"
Raven.KEY = "prif-raven"
Raven.VAR = "ELFCITY_TITLE_RAVENSFOUND"
Raven.TARGET = 13
Raven.DESCRIPTION = "Spot 13 ravens to unlock the Ravensworn title. Ravens appear every 13 days at 00:00 UTC and leave at 23:50 UTC."

local FIRST_SPAWN = 16347 * 1440 -- October 4, 2014 at 00:00 UTC.
local PERIOD, WINDOW = 13 * 1440, 23 * 60 + 50
local cachedMinute, cachedSchedule

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

function Raven.schedule(minute)
    if not finite(minute) or minute < 0 or minute > 2 ^ 31 - 1 then return nil end
    minute = math.floor(minute)
    local start = FIRST_SPAWN + math.floor((minute - FIRST_SPAWN) / PERIOD) * PERIOD
    local nextMinute = math.max(FIRST_SPAWN, start + PERIOD)
    return {active = minute >= FIRST_SPAWN and minute < start + WINDOW,
        nextMinute = nextMinute, nextDate = Clock.DateText(nextMinute), endsMinute = start + WINDOW}
end

function Raven.options()
    return {{kind = "raven", key = Raven.KEY, label = "Prifddinas ravens", varName = Raven.VAR,
        defaultTarget = Raven.TARGET, objId = id.Obj.LORE_RAVEN_1, description = Raven.DESCRIPTION}}
end

function Raven.progress()
    local requirement = Access.Quest(id.Quest.PLAGUES_END, "Complete Plague's End to access Prifddinas.")
    if requirement then return Access.Blocked(requirement, Raven.TARGET) end
    local current = Vars.readEntry(Vars.resolveVar(Raven.VAR))
    if not finite(current) or current < 0 or current % 1 ~= 0 then current = nil end
    local fraction = current and Vars.clamp(current / Raven.TARGET, 0, 1) or 0
    local complete = current ~= nil and current >= Raven.TARGET
    local text = current == nil and "Waiting for your raven sightings" or Vars.withCommas(current) .. " / " .. Raven.TARGET
        .. " ravens spotted (" .. math.floor(fraction * 100) .. "%)" .. (complete and " - Complete" or "")
    local minute = Clock.Minutes()
    if minute ~= cachedMinute then cachedMinute, cachedSchedule = minute, Raven.schedule(minute) end
    if cachedSchedule then
        if cachedSchedule.active then text = text .. "\nRaven day today (until 23:50 UTC)" end
        text = text .. "\nNext spawn: " .. cachedSchedule.nextDate .. " at 00:00 UTC"
    else
        text = text .. "\nNext spawn: waiting for the game clock"
    end
    return {current = current, target = Raven.TARGET, fraction = fraction, complete = complete, owned = false, text = text}
end

function Raven.Clear()
    cachedMinute, cachedSchedule = nil, nil
end

return {PrifRaven = Raven}
