local Vars = require("src/tracking/core/vars")

local Meg = {}
local definition = {
    key = "scheduled-meg", group = "Weekly", kind = "scheduled", label = "Meg",
    defaultTarget = 1, dynamicTarget = true, varName = "POP_MEG_ONMISSION",
    spriteName = id.Sprite.ICON_ITEM_MEG_QPS and ("#" .. id.Sprite.ICON_ITEM_MEG_QPS) or nil,
    description = "Give Meg advice for her weekly adventure at your Player-owned Port.",
    hint = "Completes when Meg leaves on her adventure. Resets on Wednesdays at 00:00 UTC.",
}

function Meg.info() return definition end

function Meg.progress()
    local value = Vars.readEntry(Vars.resolveVar(definition.varName))
    if type(value) ~= "number" or value < 0 or value > 3 or value % 1 ~= 0 then
        return {current = nil, target = 1, fraction = 0, complete = false, owned = false, recurring = true,
            text = "Waiting for Meg's adventure status"}
    end
    local complete = value == 1
    return {current = complete and 1 or 0, target = 1, fraction = complete and 1 or 0,
        complete = complete, owned = false, recurring = true,
        text = complete and "Advice given - Complete" or "<col=00ff00>Available</col>"}
end

return Meg
