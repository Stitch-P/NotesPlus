local ConfigReader = require("src/tracking/core/config_reader")

local Access = {}

function Access.Quest(quest, requirement)
    -- A quest the game no longer lists (its id arrives as nil) cannot gate anything.
    if quest == nil then return nil end
    local finished = ConfigReader.Field(ConfigReader.Quest(quest), "hasFinishedQuest")
    if finished == true then return nil end
    return finished == false and requirement or "Waiting for your quest status"
end

function Access.Level(skill, minimum, requirement)
    local ok, level = pcall(function() return Player.GetLevelUncapped(SkillType[skill]) end)
    if not ok or type(level) ~= "number" or level ~= level or level < 1 or level == math.huge or level % 1 ~= 0 then
        return "Waiting for your skill levels"
    end
    if level < minimum then return requirement end
end

function Access.Blocked(text, target)
    return {current = nil, target = target, fraction = 0, complete = false, owned = false,
        statusOnly = true, unavailable = true, text = text}
end

return Access
