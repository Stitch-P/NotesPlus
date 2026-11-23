local Vars = require("src/tracking/core/vars")
local Access = require("src/tracking/core/access")

local Agoroth = {}
local definition = {
    key = "scheduled-agoroth", group = "Weekly", kind = "scheduled", label = "Agoroth",
    defaultTarget = 2, dynamicTarget = true, varName = "ASH1_REPLAY_DEFEATED",
    spriteName = id.Sprite.ASH1_2014_AGOROTH and ("#" .. id.Sprite.ASH1_2014_AGOROTH) or nil,
    quest = id.Quest.ASH1, requirement = "Complete A Shadow over Ashdale to fight Agoroth again.",
    description = "Defeat Agoroth for his weekly rewards after A Shadow over Ashdale.",
    hint = "Complete two fights each week. Claim each reward from the dead man's chest. Resets on Wednesdays at 00:00 UTC.",
}

function Agoroth.info() return definition end

local function read(name, maximum)
    local value = Vars.readEntry(Vars.resolveVar(name))
    if type(value) == "number" and value == value and value >= 0 and value <= maximum and value % 1 == 0 then
        return value
    end
end

function Agoroth.progress()
    local reason = Access.Quest(definition.quest, definition.requirement)
    if reason then return Access.Blocked(reason, definition.defaultTarget) end
    local current = read(definition.varName, 2)
    if current == nil then
        return {current = nil, target = definition.defaultTarget, fraction = 0, complete = false,
            owned = false, recurring = true, text = "Waiting for your Agoroth progress"}
    end
    local target = definition.defaultTarget
    local fraction = Vars.clamp(current / target, 0, 1)
    local complete = current >= target
    return {current = current, target = target, fraction = fraction, complete = complete,
        owned = false, recurring = true,
        text = current .. " / " .. target .. " kills (" .. math.floor(fraction * 100) .. "%)"
            .. (complete and " - Complete" or "")}
end

return Agoroth
