local Vars = require("src/tracking/core/vars")
local Clock = require("src/tracking/core/game_clock")
local Access = require("src/tracking/core/access")
local pages = require("src/tracking/data/menaphos_journal")

local Journal = {}
Journal.GROUP = "Menaphos journal"

local items = {}

local function access()
    return Access.Quest(id.Quest.OZAN3, "Complete The Jack of Spades to access Menaphos.")
end

function Journal.isPage(key)
    return pages[key] ~= nil
end

function Journal.info(key)
    return pages[key]
end

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
    local done, readable = 0, 0
    local slots = includeSlots and {} or nil
    for index, entry in ipairs(page.entries) do
        local value = Vars.readEntry(Vars.resolveVar(entry.variable))
        local slot = slots and {key = key .. ":" .. index, label = entry.name}
        if type(value) == "number" and value == value then
            readable = readable + 1
            if value > 0 then done = done + 1 end
            if slot then slot.complete = value > 0 end
        end
        if slot then slots[index] = slot end
    end
    local total = #page.entries
    local fraction = done / total
    return {current = readable > 0 and done or nil, target = total, fraction = fraction,
        complete = done == total, owned = false, slots = slots,
        text = readable == 0 and "Waiting for your journal" or tostring(done) .. " / " .. tostring(total) .. " " .. page.noun
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
    local value = Vars.readEntry(Vars.resolveVar(entry.variable))
    local current
    if type(value) == "number" and value == value and math.abs(value) < math.huge then current = value > 0 and 1 or 0 end
    return {current = current, target = 1, fraction = current or 0, complete = current == 1, owned = false,
        text = current == nil and "Waiting for your journal" or current == 1 and "Done" or "Not done yet"}
end

function Journal.sprite(item)
    local entry = entryFor(item)
    return entry and entry.sprite
end

function Journal.object(item)
    local entry = entryFor(item)
    return entry and entry.object
end

local function spawned(entry)
    if not entry.weekday then return false end
    return Clock.Weekday() == entry.weekday
end

function Journal.label(item)
    local entry = entryFor(item)
    if not entry then return item and item.label end
    if access() then return entry.name end
    local status = spawned(entry) and "Cat Spawned!" or nil
    return entry.name .. (status and " - " .. status or ""), status
end

function Journal.card(item)
    local entry = entryFor(item)
    if not entry then return nil end
    local requirement = access()
    if requirement then
        return {key = item.key .. ":access:" .. requirement, body = entry.name .. "<br>" .. requirement}
    end
    local body = entry.name .. "<br>" .. entry.location
    local day
    if entry.weekday then
        local active = spawned(entry)
        day = Clock.Day()
        body = body .. "<br>" .. (day == nil and "Waiting for the game clock"
            or active and "<col=00ff00>Cat Spawned!</col>" or "Not spawned today.")
    end
    return {key = item.key .. (entry.weekday and ":" .. tostring(day) or ""), body = body}
end

function Journal.Clear()
    items = {}
end

return {MenaphosJournal = Journal}
