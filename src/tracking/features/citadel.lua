local Clock = require("src/tracking/core/game_clock")
local Profiles = require("src/core/character_profiles")

local Citadel = {}
local definition = {key = "scheduled-citadel", group = "Weekly", kind = "scheduled", label = "Clan citadel",
    defaultTarget = 1, statusOnly = true, varName = "CLOCK_TIME_DATE_MINUTES", spriteName = "AIF_CLAN_INTERFACE_AND_PRIORITY_BUTTONS_1",
    description = "Shows your citadel's next build tick.",
    hint = "Open your own citadel management to save its reset time automatically. Open it again after changing clans or a moved build tick."}

local timerComponents = {
    id.Component.CLAN_STRONGHOLD_MAIN_MAP__BUILD_TIME_TEXT,
    id.Component.CLAN_STRONGHOLD_MAIN_RESOURCES__BUILD_TIME_TEXT,
    id.Component.CLAN_STRONGHOLD_MAIN_BUILDINGS__BUILD_TIME_TEXT,
    id.Component.CLAN_STRONGHOLD_MAIN_DECOR__BUILD_TIME_TEXT,
}
local deadline, lastReading, owner, loaded, persisted, nextPoll, readFailed

function Citadel.info() return definition end

local function validMinute(value)
    return type(value) == "number" and value == value and value > 0 and value <= 2147483647 and value % 1 == 0
end

local function load(retry)
    local token = Profiles.Token()
    if token ~= owner then
        deadline, lastReading, loaded, persisted, nextPoll, readFailed = nil, nil, false, nil, nil, false
        owner = token
    end
    local characterID = Profiles.ID()
    if not characterID then return end
    local key = Profiles.Key("notes_plus_citadel_reset_v1", characterID)
    if not loaded or retry and readFailed then
        loaded = true
        local ok, saved = pcall(function() return PersistentDB:GetStructuredData(key) end)
        readFailed = not ok
        if ok and type(saved) == "table" and validMinute(saved.resetMinute) then
            persisted = saved.resetMinute
            if not lastReading then deadline = persisted end
        end
    end
    return key
end

local function managementOpen()
    for _, componentID in ipairs(timerComponents) do
        local ok, component = pcall(function() return ui.Interfaces:GetComponent(componentID) end)
        if ok and component and component.visibleGlobal == true then return true end
    end
    return false
end

local function read(name, maximum)
    local ok, value = pcall(function() return var.VarClient[name].value end)
    if ok and type(value) == "number" and value == value and value >= 0 and value <= maximum and value % 1 == 0 then
        return value
    end
end

local function capture(minute)
    if not minute or not managementOpen() then return end
    local days = read("CLAN_STRONGHOLD_UPDATE_DAYS", 7)
    local hours = read("CLAN_STRONGHOLD_UPDATE_HOURS", 23)
    local minutes = read("CLAN_STRONGHOLD_UPDATE_MINUTES", 59)
    if days == nil or hours == nil or minutes == nil then return end
    local remaining = days * 1440 + hours * 60 + minutes
    if remaining <= 0 or remaining > 7 * 1440 then return end
    if not validMinute(minute + remaining) then return end
    local reading = tostring(days) .. ":" .. tostring(hours) .. ":" .. tostring(minutes)
    if reading ~= lastReading then deadline, lastReading = minute + remaining, reading end
end

function Citadel.Poll(elapsed)
    if type(elapsed) ~= "number" or elapsed ~= elapsed or elapsed == math.huge or elapsed == -math.huge then return false end
    local previous = deadline
    local key = load(nextPoll ~= nil and elapsed >= nextPoll)
    if not key or nextPoll and elapsed < nextPoll then return deadline ~= previous end
    nextPoll = elapsed + 1
    capture(Clock.Minutes())
    if deadline and deadline ~= persisted then
        local ok, saved = pcall(function() return PersistentDB:SetStructuredData(key, {resetMinute = deadline}) end)
        if ok and saved == true then persisted, readFailed = deadline, false end
    end
    return deadline ~= previous
end

local function timeLeft(minutes)
    local days = math.floor(minutes / 1440)
    local hours = math.floor(minutes % 1440 / 60)
    return tostring(days) .. "d " .. tostring(hours) .. "h " .. tostring(minutes % 60) .. "m"
end

function Citadel.progress()
    local key = load()
    local minute = Clock.Minutes()
    if key then capture(minute) end
    local text
    if not deadline then
        text = "Open your own citadel management to load its reset time."
    elseif minute and minute >= deadline then
        text = "Reset time reached\nOpen your own citadel management to refresh."
    else
        local time = deadline % 1440
        text = "Next reset: " .. Clock.DateText(deadline) .. " at "
            .. string.format("%02d:%02d UTC", math.floor(time / 60), time % 60)
        text = text .. "\nTime left: " .. (minute and timeLeft(deadline - minute) or "waiting for the game clock")
    end
    return {current = nil, target = 1, fraction = 0, complete = false, owned = false, statusOnly = true, text = text}
end

function Citadel.Clear()
    deadline, lastReading, owner, loaded, persisted, nextPoll, readFailed = nil, nil, nil, false, nil, nil, false
end

return Citadel
