local Vars = require("src/tracking/core/vars")
local Access = require("src/tracking/core/access")
local Skills = require("src/tracking/features/skills")

local Tears = {}
local definition = {
    key = "scheduled-tears-of-guthix", group = "Weekly", kind = "scheduled", label = "Tears of Guthix",
    defaultTarget = 1, varName = "TOG_TEARS_COMPLETE", token = "TOKEN_DD_TEARS_OF_GUTHIX",
    objId = id.Obj.TOG_BOWL, quest = id.Quest.TEARS_OF_GUTHIX,
    requirement = "Complete Tears of Guthix to collect tears for Juna.",
    description = "Collect tears for experience in your lowest-level skill.",
    hint = "Resets on Wednesdays at 00:00 UTC. Gain 100,000 XP or one quest point between visits. Your first visit does not require this progress.",
}

function Tears.info() return definition end

local function read(name)
    local value = Vars.readEntry(Vars.resolveVar(name))
    if type(value) == "number" and value == value and value >= 0 and value < math.huge and value % 1 == 0 then
        return value
    end
end

local function progress(current, text)
    return {current = current, target = 1, fraction = current or 0, complete = current == 1,
        owned = false, recurring = true, text = text}
end

local function remainingXP()
    local target = read("TOG_XP_BEFORE_RETURN")
    local billions = read("TOG_XP_BEFORE_RETURN_BILLIONS")
    if target == nil or billions == nil then return nil end
    target = target + billions * 1000000000
    local total = 0
    for _, skill in ipairs(Skills.SKILLS) do
        local ok, value = pcall(function() return Player.GetXPUncapped(SkillType[skill.skill]) end)
        if not ok or type(value) ~= "number" or value ~= value or value < 0 or value == math.huge then return nil end
        total = total + value
    end
    return Vars.clamp(target - total, 0, 100000)
end

function Tears.progress()
    local reason = Access.Quest(definition.quest, definition.requirement)
    if reason then return Access.Blocked(reason, definition.defaultTarget) end
    local complete = read(definition.varName)
    if complete == 1 then return progress(1, "Complete") end
    if complete ~= 0 then return progress(nil, "Waiting for your Tears of Guthix progress") end
    local points = read("QP")
    local needed = read("TOG_QP_BEFORE_RETURN")
    if points == nil or needed == nil then return progress(nil, "Waiting for your Tears of Guthix requirements") end
    if points >= needed then return progress(0, "<col=00ff00>Available</col>") end
    local xp = remainingXP()
    if xp == nil then return progress(nil, "Waiting for your Tears of Guthix requirements") end
    if xp == 0 then return progress(0, "<col=00ff00>Available</col>") end
    return progress(0, "Gain " .. Vars.withCommas(math.ceil(xp)) .. " XP or one quest point to play.")
end

return Tears
