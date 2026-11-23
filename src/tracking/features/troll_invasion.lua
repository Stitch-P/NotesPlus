local Vars = require("src/tracking/core/vars")

local Troll = {}
local definition = {
    key = "scheduled-troll-invasion", group = "Monthly", kind = "scheduled", label = "Troll Invasion",
    defaultTarget = 1, varName = "DNDTRACKER_TROLL_INVASION_LIMIT", token = "TOKEN_DD_TROLL_INVASION",
    objId = id.Obj.WOF_DD_TOKEN_TROLL_INVASION,
    description = "Earn this month's Troll Invasion reward by fighting trolls or defending the gatehouse.",
    hint = "Speak to Captain Jute in Burthorpe. Resets on the first day of each month at 00:00 UTC. Practice runs remain available after using the monthly reward.",
}

function Troll.info() return definition end

function Troll.progress()
    local value = Vars.readEntry(Vars.resolveVar(definition.varName))
    local current = (value == 0 or value == 1) and value or nil
    return {current = current, target = 1, fraction = current or 0, complete = current == 1,
        owned = false, recurring = true, text = current == nil and "Waiting for your Troll Invasion progress"
            or current == 1 and "Monthly reward used" or "<col=00ff00>Available</col>"}
end

return Troll
