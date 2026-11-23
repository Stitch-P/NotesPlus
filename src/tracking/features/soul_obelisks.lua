local Vars = require("src/tracking/core/vars")
local Objects = require("src/tracking/core/objects")
local Access = require("src/tracking/core/access")
local ConfigReader = require("src/tracking/core/config_reader")
local Relics = require("src/tracking/features/relics").Relics

local Obelisks = {}
local definition = {
    key = "scheduled-soul-obelisks", group = "Daily", kind = "scheduled", label = "Soul obelisks",
    defaultTarget = 25075, dynamicTarget = true, varName = "MENAPHOS_SOUL_OBELISK_DRAINED_AMOUNT",
    objId = Objects.findObjectID("CONSTRUCTION_HOUSE_FURNITURE_FUNCTIONAL_WILDERNESS_OBELISK"),
    quest = id.Quest.OZAN3, requirement = "Complete The Jack of Spades to use Soul obelisks in Menaphos.",
    description = "Track your daily Soul obelisk usage in Menaphos. The daily limit resets at 00:00 UTC.",
    hint = "The daily target includes completed Menaphos quests and the active Unexpected Diplomacy relic. Obelisk spawns vary by world.",
}
local questCaps = {
    {quest = id.Quest.CROCODILE_TEARS, target = 30090},
    {quest = id.Quest.OUR_MAN_IN_THE_NORTH, target = 35105},
    {quest = id.Quest.PHITE_CLUB, target = 40120},
    {quest = id.Quest.QUEST_DESERT_LEELA, target = 50150},
}

function Obelisks.info() return definition end

local function integer(value)
    return type(value) == "number" and value == value and value >= 0 and value < math.huge and value % 1 == 0
end

local function dailyCap()
    local target = definition.defaultTarget
    for index = #questCaps, 1, -1 do
        local entry = questCaps[index]
        local finished = ConfigReader.Field(ConfigReader.Quest(entry.quest), "hasFinishedQuest")
        if finished == true then target = entry.target break end
        if finished ~= false then return nil end
    end
    local boosted = Relics.active("UNEXPECTED_DIPLOMACY")
    if boosted == nil then return nil end
    return boosted and target * 11 / 10 or target
end

function Obelisks.progress()
    local reason = Access.Quest(definition.quest, definition.requirement)
    if reason then return Access.Blocked(reason, definition.defaultTarget) end
    local target = dailyCap()
    if target == nil then
        return {current = nil, target = nil, fraction = 0, complete = false, owned = false, recurring = true,
            text = "Waiting for your Soul obelisk daily limit"}
    end
    local current = Vars.readEntry(Vars.resolveVar(definition.varName))
    if not integer(current) then
        return {current = nil, target = target, fraction = 0, complete = false, owned = false, recurring = true,
            text = "Waiting for your Soul obelisk progress"}
    end
    local fraction = Vars.clamp(current / target, 0, 1)
    local complete = current >= target
    local targetText = Vars.withCommas(target)
    if target % 1 ~= 0 then targetText = targetText .. string.format("%.1f", target % 1):sub(2) end
    return {current = current, target = target, fraction = fraction, complete = complete, owned = false,
        recurring = true, text = "Daily usage: " .. Vars.withCommas(current) .. " / " .. targetText
            .. " (" .. tostring(math.floor(fraction * 100)) .. "%)" .. (complete and " - Complete" or "")}
end

return Obelisks
