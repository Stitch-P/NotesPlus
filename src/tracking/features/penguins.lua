local Vars = require("src/tracking/core/vars")
local ConfigReader = require("src/tracking/core/config_reader")

local Penguins = {}
local definition = {
    key = "scheduled-penguins", group = "Weekly", kind = "scheduled", label = "Penguin Hide and Seek",
    defaultTarget = 13, dynamicTarget = true, varName = "PENG_SPY_WEEK_PENG",
    token = "TOKEN_DD_PENGUIN_HIDE_SEEK", objId = id.Obj.PENG_SPY_DEVICE,
    description = "Find this week's disguised penguins and, when unlocked, the polar bear.",
    hint = "Counts the penguins available through your quest unlocks, plus the polar bear when unlocked. Resets on Wednesdays at 00:00 UTC. Penguin agents are separate.",
}

function Penguins.info() return definition end

local function questDone(quest)
    local value = ConfigReader.Field(ConfigReader.Quest(quest), "hasFinishedQuest")
    if type(value) == "boolean" then return value end
end

local function read(name, maximum)
    local value = Vars.readEntry(Vars.resolveVar(name))
    if type(value) == "number" and value == value and value >= 0 and value <= maximum and value % 1 == 0 then
        return value
    end
end

local function waiting(text)
    return {current = nil, target = definition.defaultTarget, fraction = 0, complete = false,
        owned = false, recurring = true, text = text}
end

function Penguins.progress()
    local shadow = questDone(id.Quest.SOME_LIKE_IT_COLD)
    local extra = questDone(id.Quest.PENG_BTTF)
    local polar = questDone(id.Quest.HUNT_FOR_RED_RAKTUBER)
    if shadow == nil or extra == nil or polar == nil then return waiting("Waiting for your penguin quest status") end
    local penguinTarget = 10 + (shadow and 1 or 0) + (extra and 1 or 0)
    local spotted = read(definition.varName, penguinTarget)
    local bear = 0
    if polar then bear = read("PENG_SPY_BEAR_FOUND", 1) end
    if spotted == nil or bear == nil then return waiting("Waiting for your penguin sightings") end
    local current, target = spotted + bear, penguinTarget + (polar and 1 or 0)
    local fraction, complete = current / target, current == target
    local text = tostring(current) .. " / " .. tostring(target) .. (polar and " sightings" or " penguins")
        .. " (" .. tostring(math.floor(fraction * 100)) .. "%)" .. (complete and " - Complete" or "")
    if polar then text = text .. "\nPolar bear: " .. (bear == 1 and "Spotted" or "Not spotted") end
    return {current = current, target = target, fraction = fraction, complete = complete,
        owned = false, recurring = true, text = text}
end

return Penguins
