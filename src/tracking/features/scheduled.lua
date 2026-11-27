local Vars = require("src/tracking/core/vars")
local Sprites = require("src/tracking/core/sprites")
local Clock = require("src/tracking/core/game_clock")
local ConfigReader = require("src/tracking/core/config_reader")
local Access = require("src/tracking/core/access")
local Blossoms = require("src/tracking/features/crystal_blossoms")
local Oyster = require("src/tracking/features/giant_oyster")
local Penguins = require("src/tracking/features/penguins")
local SoulObelisks = require("src/tracking/features/soul_obelisks")
local Citadel = require("src/tracking/features/citadel")
local Nemi = require("src/tracking/features/nemi_forest")
local Agoroth = require("src/tracking/features/agoroth")
local Tears = require("src/tracking/features/tears_of_guthix")
local TrollInvasion = require("src/tracking/features/troll_invasion")
local Meg = require("src/tracking/features/meg")

local Scheduled = {}
local definitions = {
    {key = "scheduled-thalmund", group = "Weekly", label = "Thalmund", defaultTarget = 1,
        varName = "CLOCK_TIME_DATE_MINUTES", objId = id.Obj.QUEST_NECROMANCY_CITY_SMITH_KILI_TOOLS,
        weekday = 4, statusOnly = true,
        quest = id.Quest.NECROMANCY_CITY_SMITH, requirement = "Complete Kili Row to visit Thalmund.",
        description = "Thalmund visits the City of Um smithy on Wednesdays.",
        hint = "Shows his next visit. Visiting or buying from him does not complete this note."},
    {key = "scheduled-barmaid-tip", group = "Weekly", label = "Barmaid's Tip", defaultTarget = 1,
        varName = "CLOCK_TIME_DATE_MINUTES", objId = id.Obj.BEER,
        weekday = 5, statusOnly = true,
        description = "Ask Surula at your Player-owned Port for a bonus voyage on Thursdays.",
        hint = "Requires the Player-owned Ports tutorial. Shows the scheduled day. Claiming the tip does not complete this note."},
    {key = "scheduled-herby-werby", group = "Weekly", label = "Herby Werby", defaultTarget = 100,
        varName = "DINO_HERBLORE_DND_COMPLETED", points = "DINO_HERBLORE_DND_POINTS",
        token = "TOKEN_DD_DINO_HERBLORE", objId = id.Obj.DINO_HEBLORE_DND_CURRENCY_OBJ,
        description = "Earn up to 100 points each week at Herby Werby on Anachronia.",
        hint = "Resets on Wednesdays at 00:00 UTC."},
    {key = "scheduled-effigy-incubator", group = "Monthly", label = "Effigy Incubator", defaultTarget = 1,
        varName = "KERAPAC_DND_MONTHLY_COMPLETE", token = "TOKEN_DD_KERAPAC_DND",
        objId = id.Obj.KERAPAC_DND_RESOURCE_EFFIGY_CASING,
        quest = id.Quest.KERAPAC_DND, requirement = "Complete Sins of the Father to use the Effigy Incubator.",
        description = "Complete the monthly Effigy Incubator activity on Anachronia.",
        hint = "Resets on the first day of each month at 00:00 UTC."},
    {key = "scheduled-god-statues", group = "Monthly", label = "God Statues", defaultTarget = 5,
        varName = "GODSS_USED_TAVERLEY", token = "TOKEN_DD_GOD_STATUE", objId = id.Obj.CHISEL,
        unit = "statues", itemWaiting = "Waiting for your statues", itemIncomplete = "Not completed this month",
        description = "Build each monthly God Statue. Completed locations drop off the list.",
        hint = "Requires completing or turning off tutorial mode, completing 60 achievements, or completing Let Them Eat Pie. Resets on the first day of each month at 00:00 UTC.",
        entries = {
            {name = "Taverley", variable = "GODSS_USED_TAVERLEY", object = id.Obj.GODSS_HAMMER_CHISEL_PLAYER_GUTHIX},
            {name = "Falador", variable = "GODSS_USED_FALADOR", object = id.Obj.GODSS_HAMMER_CHISEL_PLAYER_SARADOMIN},
            {name = "Canifis", variable = "GODSS_USED_CANIF", object = id.Obj.GODSS_HAMMER_CHISEL_PLAYER_ZAMORAK},
            {name = "Gu'Tanoth", variable = "GODSS_USED_GUT", object = id.Obj.GODSS_HAMMER_CHISEL_PLAYER_BANDOS},
            {name = "Prifddinas", variable = "GODSS_USED_PRIFDDINAS", object = id.Obj.GODSS_HAMMER_CHISEL_PLAYER_SEREN,
                quest = id.Quest.PLAGUES_END,
                requirement = "Requires Plague's End."},
        }},
}
local blossom = Blossoms.info()
blossom.readProgress = Blossoms.progress
definitions[#definitions + 1] = blossom
local oyster = Oyster.info()
oyster.readProgress = Oyster.progress
definitions[#definitions + 1] = oyster
local penguins = Penguins.info()
penguins.readProgress = Penguins.progress
definitions[#definitions + 1] = penguins
local soulObelisks = SoulObelisks.info()
soulObelisks.readProgress = SoulObelisks.progress
definitions[#definitions + 1] = soulObelisks
local citadel = Citadel.info()
citadel.readProgress = Citadel.progress
definitions[#definitions + 1] = citadel
definitions[#definitions + 1] = Nemi.info()
local agoroth = Agoroth.info()
agoroth.readProgress = Agoroth.progress
definitions[#definitions + 1] = agoroth
local tears = Tears.info()
tears.readProgress = Tears.progress
definitions[#definitions + 1] = tears
local trollInvasion = TrollInvasion.info()
trollInvasion.readProgress = TrollInvasion.progress
definitions[#definitions + 1] = trollInvasion
local meg = Meg.info()
meg.readProgress = Meg.progress
definitions[#definitions + 1] = meg
local byKey, itemLists = {}, {}
for _, definition in ipairs(definitions) do
    definition.kind = "scheduled"
    byKey[definition.key] = definition
end

local portSkills = {"AGILITY", "CONSTRUCTION", "COOKING", "DIVINATION", "DUNGEONEERING", "FISHING",
    "HERBLORE", "HUNTER", "PRAYER", "RUNECRAFTING", "SLAYER", "THIEVING"}

local function portAccess()
    local requirement = "Requires level 90 in at least one Ports adventurer skill."
    local waiting
    for _, skill in ipairs(portSkills) do
        local reason = Access.Level(skill, 90, requirement)
        if reason == nil then return nil end
        if reason ~= requirement then waiting = reason end
    end
    return waiting or requirement
end

local MONTH_DAYS = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
local cachedDay, cachedCalendar

local function read(name)
    local value = Vars.readEntry(Vars.resolveVar(name))
    if type(value) == "number" and value == value and value >= 0 and value < math.huge and value % 1 == 0 then
        return value
    end
end

local function flag(name)
    local value = read(name)
    if value == 0 or value == 1 then return value == 1 end
end

local function questDone(quest)
    local value = ConfigReader.Field(ConfigReader.Quest(quest), "hasFinishedQuest")
    if type(value) == "boolean" then return value end
end

local function leap(year)
    return year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)
end

local function calendar()
    local day = Clock.Day()
    if day == nil then return nil end
    if day == cachedDay then return cachedCalendar end
    local remaining, year = day, 1970
    while remaining >= (leap(year) and 366 or 365) do
        remaining, year = remaining - (leap(year) and 366 or 365), year + 1
    end
    for month, length in ipairs(MONTH_DAYS) do
        local span = month == 2 and leap(year) and 29 or length
        if remaining < span then
            local weekday = (day + 4) % 7 + 1
            cachedDay, cachedCalendar = day, {day = day, weekday = weekday, year = year, month = month,
                nextMonth = (day - remaining + span) * 1440,
                week = day - (weekday - 4) % 7}
            return cachedCalendar
        end
        remaining = remaining - span
    end
end

local function nextReset(definition, date)
    if not date then return "Next reset: waiting for the game clock" end
    local minute = definition.group == "Daily" and (date.day + 1) * 1440
        or definition.group == "Weekly" and (date.week + 7) * 1440 or date.nextMonth
    return "Next reset: " .. Clock.DateText(minute) .. " at 00:00 UTC"
end

local function period(definition, date)
    if not date then return nil end
    local token = ""
    if definition.token then
        local value = read(definition.token)
        if value ~= 0 and value ~= 1 then return nil end
        token = ":" .. value
    end
    local key = definition.group == "Daily" and "day:" .. date.day
        or definition.group == "Weekly" and "week:" .. date.week or "month:" .. date.year .. ":" .. date.month
    return key .. token
end

function Scheduled.groups()
    return {{name = "Daily"}, {name = "Weekly"}, {name = "Monthly"}}
end

function Scheduled.info(key) return byKey[key] end
function Scheduled.isKey(key) return byKey[key] ~= nil end

function Scheduled.options(group)
    local name = type(group) == "table" and group.name or group
    local result = {}
    for _, definition in ipairs(definitions) do
        if not name or definition.group == name then
            local option = {}
            for key, value in pairs(definition) do option[key] = value end
            result[#result + 1] = option
        end
    end
    return result
end

function Scheduled.items(key)
    local definition = byKey[key]
    if not definition or not definition.entries then return nil end
    if itemLists[key] then return itemLists[key] end
    local result = {}
    for index, entry in ipairs(definition.entries) do
        result[index] = {category = "Scheduled", group = definition.group, key = key .. ":" .. index,
            label = entry.name, variable = entry.variable, target = 1, hideComplete = true,
            scheduleKey = key, scheduleIndex = index}
    end
    itemLists[key] = result
    return result
end

local function entryFor(item)
    local definition = item and byKey[item.scheduleKey]
    return definition and definition.entries and definition.entries[item.scheduleIndex]
end

function Scheduled.readItem(item)
    local entry = entryFor(item)
    if not entry then return nil end
    if entry.quest then
        local reason = Access.Quest(entry.quest, entry.requirement)
        if reason then return Access.Blocked(reason, 1) end
    end
    local state = flag(entry.variable)
    return {current = state ~= nil and (state and 1 or 0) or nil, target = 1,
        fraction = state and 1 or 0, complete = state == true, owned = false,
        text = state == nil and byKey[item.scheduleKey].itemWaiting
            or state and "Complete" or byKey[item.scheduleKey].itemIncomplete}
end

function Scheduled.object(item)
    local entry = entryFor(item)
    return entry and entry.object
end

function Scheduled.sprite(item)
    local entry = entryFor(item)
    return entry and entry.spriteName and Sprites.spriteByName(entry.spriteName) or nil
end

function Scheduled.label(item)
    local entry = entryFor(item)
    if not entry then return item and item.label end
    local reason = entry.quest and Access.Quest(entry.quest, entry.requirement)
    return entry.name .. (reason and " - " .. reason or "")
end

function Scheduled.card(item)
    local entry = entryFor(item)
    if not entry then return nil end
    local body = entry.name
    if entry.requirement and questDone(entry.quest) ~= true then body = body .. "<br>" .. entry.requirement end
    return {key = item.key .. ":" .. tostring(Clock.Day()), body = body .. "<br>" .. nextReset(byKey[item.scheduleKey], calendar())}
end

function Scheduled.progress(key, includeSlots, tracking)
    local definition = byKey[key]
    if not definition then return nil end
    local reason = definition.quest and Access.Quest(definition.quest, definition.requirement)
    if not reason and (key == "scheduled-barmaid-tip" or key == "scheduled-meg") then reason = portAccess() end
    if reason then return Access.Blocked(reason, tracking and tracking.target or definition.defaultTarget) end
    if definition.readProgress then
        local progress = definition.readProgress(includeSlots, tracking)
        if progress.recurring and not progress.unavailable then
            local date = calendar()
            progress.period = progress.period or period(definition, date)
            progress.text = progress.text .. "\n" .. nextReset(definition, date)
        end
        return progress
    end
    local date = calendar()
    if definition.statusOnly then
        local text = "Waiting for the game clock"
        if date then
            local active = date.weekday == definition.weekday
            text = active and "<col=00ff00>Available today</col>" or "Not scheduled today"
            if not definition.quest and active then
                text = "<col=00ff00>Tip day today</col>"
            end
            local days = (definition.weekday - date.weekday) % 7
            if days == 0 then days = 7 end
            text = text .. "\nNext " .. (key == "scheduled-thalmund" and "visit" or "tip day") .. ": "
                .. Clock.DateText((date.day + days) * 1440) .. " at 00:00 UTC"
        end
        return {current = nil, target = 1, fraction = 0, complete = false, owned = false, statusOnly = true, text = text}
    end
    local current, complete, slots
    if definition.entries then
        local done, known = 0, 0
        slots = includeSlots and {} or nil
        for index, entry in ipairs(definition.entries) do
            local eligible = not entry.quest or questDone(entry.quest)
            local state
            if eligible == true then state = flag(entry.variable)
            elseif eligible == false then state = false end
            if state ~= nil then known = known + 1; if state then done = done + 1 end end
            if slots then slots[index] = {key = key .. ":" .. index, label = entry.name, complete = state} end
        end
        if known == #definition.entries then current, complete = done, done == #definition.entries end
    else
        local state = flag(definition.varName)
        if state ~= nil then
            if definition.points then
                local points = read(definition.points)
                if state then current, complete = definition.defaultTarget, true
                elseif points and points <= definition.defaultTarget then current, complete = points, points == definition.defaultTarget end
            else
                current, complete = state and 1 or 0, state
            end
        end
    end
    local text
    if current == nil then text = "Waiting for your activity progress"
    elseif definition.entries then
        text = current .. " / " .. definition.defaultTarget .. " " .. definition.unit .. " (" .. math.floor(current / definition.defaultTarget * 100)
            .. "%)" .. (complete and " - Complete" or "")
    elseif definition.points then
        text = current .. " / " .. definition.defaultTarget .. " points (" .. math.floor(current / definition.defaultTarget * 100)
            .. "%)" .. (complete and " - Complete" or "")
    else text = complete and "Complete" or "<col=00ff00>Available</col>" end
    return {current = current, target = definition.defaultTarget, fraction = current and current / definition.defaultTarget or 0,
        complete = complete == true and current ~= nil, owned = false, slots = slots, recurring = true,
        period = period(definition, date), text = text .. "\n" .. nextReset(definition, date)}
end

function Scheduled.Poll(elapsed)
    return Citadel.Poll(elapsed)
end

function Scheduled.Clear()
    itemLists, cachedDay, cachedCalendar = {}, nil, nil
    Citadel.Clear()
end

return Scheduled
