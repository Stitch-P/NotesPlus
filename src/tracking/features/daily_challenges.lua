local Vars = require("src/tracking/core/vars")
local ConfigReader = require("src/tracking/core/config_reader")

local Challenges = {}
local definition = {
    key = "scheduled-daily-challenges", group = "Daily", kind = "scheduled", label = "Daily Challenges",
    defaultTarget = 3, dynamicTarget = true, varName = "OMGE_CHALLENGE_LAST_GENERATED",
    spriteName = id.Sprite.RS3_ICON_DAILY_CHALLENGE_1 and ("#" .. id.Sprite.RS3_ICON_DAILY_CHALLENGE_1) or nil,
    description = "Complete your assigned daily challenges. Completed challenges drop off the list.",
    hint = "New challenges are assigned after logging in following the daily reset at 00:00 UTC. Claim completed rewards before they expire.",
}
local children, definitions = {}, {}
for slot = 1, 3 do
    children[slot] = {category = "Scheduled", group = definition.group, key = definition.key .. ":" .. slot,
        label = "Challenge " .. slot, variable = "OMGE_CHALLENGE_CURRENT_PROGRESS_" .. slot,
        target = 1, hideComplete = true, scheduleKey = definition.key, scheduleIndex = slot}
end

function Challenges.info() return definition end
function Challenges.items() return children end

local function read(name)
    local value = Vars.readEntry(Vars.resolveVar(name))
    if type(value) == "number" and value == value and value >= 0 and value < math.huge and value % 1 == 0 then
        return value
    end
end

local function details(skill, challenge)
    local key = skill .. ":" .. challenge
    if definitions[key] then return definitions[key] end
    local list = ConfigReader.EnumValue("OMGE_CHALLENGE_LISTS", skill)
    local row = list and ConfigReader.EnumValue(list, challenge)
    if not row then return nil end
    local target = ConfigReader.StructParam(row, "CHALLENGE_TARGET")
    local name = ConfigReader.StructParam(row, "TASK_NAME")
    if type(target) ~= "number" or target <= 0 or type(name) ~= "string" or name == "" then return nil end
    local subname = ConfigReader.StructParam(row, "CHALLENGE_SUBNAME")
    if type(subname) == "string" and subname ~= "" then name = name .. ": " .. subname end
    local kind = ConfigReader.StructParam(row, "CHALLENGE_TYPE")
    local entry = {target = target, name = name, description = ConfigReader.StructParam(row, "TASK_DETAILS"),
        sprite = ConfigReader.StructParam(row, "TASK_ICON"), kind = kind, daily = kind == nil or kind == 0}
    definitions[key] = entry
    return entry
end

local function state(slot)
    if not children[slot] then return nil end
    local skill = read("OMGE_CHALLENGE_CURRENT_SKILL_" .. slot)
    local challenge = read("OMGE_CHALLENGE_CURRENT_ID_" .. slot)
    local current = read("OMGE_CHALLENGE_CURRENT_PROGRESS_" .. slot)
    if skill == nil or challenge == nil or current == nil then return nil end
    if skill == 0 or challenge == 0 then return {assigned = false} end
    local entry = details(skill, challenge)
    if not entry then return nil end
    if not entry.daily then return {assigned = false, basic = entry.kind == 1} end
    return {assigned = true, entry = entry, current = current, complete = current >= entry.target}
end

function Challenges.readItem(item)
    local status = state(item and item.scheduleIndex)
    if not status then
        return {current = nil, target = 1, fraction = 0, complete = false, owned = false,
            text = "Waiting for your daily challenge"}
    end
    if not status.assigned then
        return {current = nil, target = 1, fraction = 0, complete = true, owned = false, text = "Not assigned"}
    end
    return {current = status.current, target = status.entry.target,
        fraction = Vars.clamp(status.current / status.entry.target, 0, 1), complete = status.complete,
        owned = false, text = status.current .. " / " .. status.entry.target}
end

function Challenges.label(item)
    local status = state(item and item.scheduleIndex)
    if not status then return item and item.label end
    if not status.assigned then return "Not assigned" end
    return status.entry.name .. ": " .. status.current .. " / " .. status.entry.target
end

function Challenges.sprite(item)
    local status = state(item and item.scheduleIndex)
    local sprite = status and status.entry and status.entry.sprite
    if type(sprite) == "number" and sprite >= 0 then return sprite end
end

function Challenges.card(item)
    local status = state(item and item.scheduleIndex)
    if not status or not status.assigned then return nil end
    local safe = function(value) return (tostring(value):gsub("<", "["):gsub(">", "]")) end
    local body = safe(status.entry.name)
    if type(status.entry.description) == "string" and status.entry.description ~= "" then
        body = body .. "<br>" .. safe(status.entry.description)
    end
    return {key = item.key .. ":" .. status.entry.name .. ":" .. status.current,
        body = body .. "<br>" .. status.current .. " / " .. status.entry.target}
end

function Challenges.progress(includeSlots)
    local generated = read(definition.varName)
    local assigned, completed, known, basic = 0, 0, true, false
    local slots = includeSlots and {} or nil
    for slot = 1, #children do
        local status = state(slot)
        if not status then known = false
        elseif status.assigned then
            assigned = assigned + 1
            if status.complete then completed = completed + 1 end
            if slots then slots[#slots + 1] = {key = children[slot].key, label = status.entry.name, complete = status.complete} end
        elseif status.basic then basic = true end
    end
    local period = generated and (definition.key .. ":" .. generated) or nil
    if not known or generated == nil then
        return {current = nil, target = definition.defaultTarget, fraction = 0, complete = false, owned = false,
            recurring = true, period = period, slots = slots, text = "Waiting for your daily challenges"}
    end
    if assigned == 0 then
        return {current = nil, target = definition.defaultTarget, fraction = 0, complete = false, owned = false,
            statusOnly = true, recurring = true, period = period,
            text = basic and "Finish or skip the basic challenges to receive daily challenges." or "No daily challenges remaining"}
    end
    local fraction = completed / assigned
    local remaining = assigned - completed
    local text = remaining == 0 and "Ready to claim - Complete"
        or remaining .. (remaining == 1 and " challenge remaining" or " challenges remaining")
    if completed > 0 and remaining > 0 then text = text .. "\n" .. completed .. " ready to claim" end
    return {current = completed, target = assigned, fraction = fraction, complete = completed == assigned,
        owned = false, recurring = true, period = period, slots = slots,
        text = text}
end

function Challenges.Clear() definitions = {} end

return Challenges
