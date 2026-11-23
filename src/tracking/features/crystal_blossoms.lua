local Vars = require("src/tracking/core/vars")
local Clock = require("src/tracking/core/game_clock")
local Access = require("src/tracking/core/access")

local Blossoms = {}
local option = {key = "scheduled-crystal-blossoms", group = "Daily", label = "Crystal tree blossoms",
    kind = "scheduled", defaultTarget = 30, varName = "ELFCITY_CRYSTAL_BLOSSOMS_AVAILABLE",
    objId = id.Obj.CRYSTAL_TREE_BLOSSOM, statusOnly = true,
    description = "A planted crystal tree stores up to 30 harvest charges, gaining one each day at 00:00 UTC.",
    hint = "Requires Plague's End and a planted crystal tree. Planting requires 94 Farming. Shows stored charges, not a completion goal."}

function Blossoms.info() return option end

function Blossoms.progress()
    local reason = Access.Quest(id.Quest.PLAGUES_END, "Requires Plague's End")
    if reason then return Access.Blocked(reason, option.defaultTarget) end
    local count = Vars.readEntry(Vars.resolveVar(option.varName))
    if type(count) ~= "number" or count ~= count or count < 0 or count > 30 or count % 1 ~= 0 then
        return {current = nil, target = 30, fraction = 0, complete = false, owned = false, statusOnly = true,
            text = "Waiting for your crystal tree charges"}
    end
    local text = tostring(count) .. " / 30 charges"
    if count == 30 then
        text = text .. "\n<col=00ff00>Storage full</col>"
    else
        if count > 0 then text = text .. "\n<col=00ff00>Available</col>" end
        local day = Clock.Day()
        text = text .. "\n" .. (day and "Next recharge: " .. Clock.DateText((day + 1) * 1440) .. " at 00:00 UTC"
            or "Next recharge: waiting for the game clock")
    end
    return {current = count, target = 30, fraction = count / 30, complete = false,
        owned = false, statusOnly = true, text = text}
end

return Blossoms
