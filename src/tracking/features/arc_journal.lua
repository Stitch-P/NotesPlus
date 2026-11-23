local Vars = require("src/tracking/core/vars")
local ConfigReader = require("src/tracking/core/config_reader")
local Access = require("src/tracking/core/access")
local Clock = require("src/tracking/core/game_clock")
local pages = require("src/tracking/data/arc_journal")

local Journal = {}
Journal.GROUP = "Arc journal"
local items = {}
local weekdays = {"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"}

local function access()
    return Access.Quest(id.Quest.ELR0, "Complete Impressing the Locals to access the Arc.")
end

local function read(entry, values)
    if entry.quest then
        local value = ConfigReader.Field(ConfigReader.Quest(entry.quest), "hasFinishedQuest")
        if type(value) == "boolean" then return value end
        return nil
    end
    local value = values and values[entry.variable]
    if value == nil then
        value = Vars.readEntry(Vars.resolveVar(entry.variable))
        if values then values[entry.variable] = value or false end
    end
    if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then return nil end
    if entry.bit then return math.floor(value / 2 ^ entry.bit) % 2 == 1 end
    return value > 0
end

function Journal.isPage(key) return pages[key] ~= nil end
function Journal.info(key) return pages[key] end

function Journal.options()
    local options = {}
    for key, page in pairs(pages) do
        options[#options + 1] = {kind = "journal", key = key, label = page.name, defaultTarget = #page.entries,
            varName = page.entries[1].variable, spriteName = page.spriteName}
    end
    return options
end

function Journal.items(key)
    local page = pages[key]
    if not page then return nil end
    if items[key] then return items[key] end
    local list = {}
    for index, entry in ipairs(page.entries) do
        list[index] = {category = "Unlocks", group = Journal.GROUP, key = key .. ":" .. index,
            label = entry.name, variable = entry.variable, target = 1, hideComplete = true,
            journalKey = key, journalIndex = index}
    end
    items[key] = list
    return list
end

function Journal.progress(key, includeSlots)
    local page = pages[key]
    if not page then return nil end
    local requirement = access()
    if requirement then return Access.Blocked(requirement, #page.entries) end
    local done, known, values = 0, 0, {}
    local slots = includeSlots and {} or nil
    for index, entry in ipairs(page.entries) do
        local state = read(entry, values)
        if state ~= nil then
            known = known + 1
            if state then done = done + 1 end
        end
        if slots then slots[index] = {key = key .. ":" .. index, label = entry.name, complete = state} end
    end
    local total = #page.entries
    local fraction = done / total
    return {current = known > 0 and done or nil, target = total, fraction = fraction,
        complete = done == total, owned = false, slots = slots,
        text = known == 0 and "Waiting for your journal" or tostring(done) .. " / " .. tostring(total) .. " " .. page.noun
            .. " (" .. tostring(math.floor(fraction * 100)) .. "%)" .. (done == total and " - Complete" or "")}
end

local function entryFor(item)
    local page = item and pages[item.journalKey]
    return page and page.entries[item.journalIndex]
end

function Journal.readItem(item)
    local entry = entryFor(item)
    if not entry then return nil end
    local requirement = access()
    if requirement then return Access.Blocked(requirement, 1) end
    local state = read(entry)
    local current
    if state ~= nil then current = state and 1 or 0 end
    return {current = current, target = 1, fraction = state and 1 or 0, complete = state == true, owned = false,
        text = state == nil and "Waiting for your journal" or state and "Done" or "Not done yet"}
end

function Journal.sprite(item)
    local entry = entryFor(item)
    return entry and entry.sprite
end

local function includes(days, day)
    for _, candidate in ipairs(days or {}) do if candidate == day then return true end end
    return false
end

local function available(entry)
    if not entry.namedWeekdays and not entry.unchartedWeekdays then return false end
    local day = Clock.Weekday()
    return day ~= nil and (includes(entry.namedWeekdays, day) or includes(entry.unchartedWeekdays, day))
end

local function bottleSchedule(entry)
    local day = Clock.Day()
    if not day then return nil end
    local phase = (day + entry.cycleOffset) % entry.cycleDays
    return phase == 0, (day + entry.cycleDays - phase) * 1440
end

function Journal.label(item)
    local entry = entryFor(item)
    if not entry then return item and item.label end
    if access() then return entry.name end
    local status
    if entry.cycleDays then
        status = bottleSchedule(entry) and "Bottle Available" or nil
    elseif available(entry) then status = "Available today" end
    return entry.name .. (status and " - " .. status or ""), status
end

local function scheduleText(days)
    local names = {}
    for _, day in ipairs(days) do names[#names + 1] = weekdays[day] .. "s" end
    local today = Clock.Weekday()
    local status = today == nil and "Waiting for the game clock"
        or includes(days, today) and "<col=00ff00>Available today</col>" or "Not scheduled today"
    return "Appears on " .. table.concat(names, ", ") .. ".<br>" .. status
end

function Journal.card(item)
    local entry = entryFor(item)
    if not entry then return nil end
    local requirement = access()
    if requirement then
        return {key = item.key .. ":access:" .. requirement, body = entry.name .. "<br>" .. requirement}
    end
    local body = entry.name .. "<br>" .. entry.location
    if entry.namedWeekdays then
        body = body .. "<br>" .. scheduleText(entry.namedWeekdays)
        if not entry.requiresDuskSkybox then body = body .. "<br>Appears for 10 minutes every 30.5 minutes." end
    end
    if entry.unchartedWeekdays then
        if entry.namedWeekdays then body = body .. "<br><br>Uncharted Isles." end
        body = body .. "<br>" .. scheduleText(entry.unchartedWeekdays)
    end
    if entry.alternativeLocation then body = body .. "<br><br>" .. entry.alternativeLocation end
    if entry.cycleDays then
        local active, nextMinute = bottleSchedule(entry)
        local status = active == nil and "Waiting for the game clock"
            or active and "<col=00ff00>Bottle Available</col>" or "Not scheduled today"
        body = body .. "<br>" .. status
        if nextMinute then body = body .. "<br>Next spawn: " .. Clock.DateText(nextMinute) .. " at 00:00 UTC" end
    end
    local scheduled = entry.namedWeekdays or entry.unchartedWeekdays or entry.cycleDays
    return {key = item.key .. (scheduled and ":" .. tostring(Clock.Day()) or ""), body = body}
end

function Journal.Clear() items = {} end

return {ArcJournal = Journal}
