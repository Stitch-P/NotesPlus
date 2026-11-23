local Vars = require("src/tracking/core/vars")
local Access = require("src/tracking/core/access")

local Oyster = {}
local definition = {
    key = "scheduled-giant-oyster", group = "Monthly", kind = "scheduled", label = "Giant Oyster", defaultTarget = 1,
    varName = "TUTISLAND_REWARD_STATE", token = "TOKEN_DD_OYSTER", objId = id.Obj.OYSTERSHELL,
    quest = id.Quest.BENEATH_CURSED_TIDES, requirement = "Complete Beneath Cursed Tides to feed the Giant Oyster.",
    description = "Feed the Giant Oyster with delicious seaweed and a sea cucumber. Its treasure can be collected the following month.",
    hint = "Complete this goal by feeding the oyster. Loot any waiting treasure before feeding it again.",
}

function Oyster.info() return definition end

function Oyster.progress()
    local reason = Access.Quest(definition.quest, definition.requirement)
    if reason then return Access.Blocked(reason, definition.defaultTarget) end
    local state = Vars.readEntry(Vars.resolveVar(definition.varName))
    local current, text
    if state == 1 then
        current, text = 0, "<col=00ff00>Ready to feed</col>"
    elseif state == 2 then
        current, text = 1, "Fed"
    elseif state == 0 or state == 3 then
        current, text = 0, "<col=00ff00>Reward ready</col>\nLoot the oyster, then feed it again."
    else
        text = "Waiting for your oyster progress"
    end
    return {current = current, target = 1, fraction = current or 0, complete = current == 1,
        owned = false, recurring = true, text = text}
end

return Oyster
