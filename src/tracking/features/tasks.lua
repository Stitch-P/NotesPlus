-- Area tasks: one Area dropdown, then the tasks in it, easiest first.

local baked = require("src/tracking/data/tasks")
local TaskSource = require("src/tracking/core/task_source")
local TIERS, AREAS, TASKS

local Vars = require("src/tracking/core/vars")
local Skills = require("src/tracking/features/skills")
local REQUIREMENTS = {}

local Tasks = {}

local tierRank = {}

-- The tasks come from the game's own achievements the first time they're needed. If they can't be read the list is
-- empty (data/tasks.lua only holds the tier order and area labels).
local loaded, live, liveTotal
local function dataset()
    if loaded then return end
    loaded = true
    local ok, source = pcall(TaskSource.Load, baked)
    if ok and source then
        TIERS, AREAS, TASKS, REQUIREMENTS = source.TIERS, source.AREAS, source.TASKS, source.REQUIREMENTS
        live, liveTotal = true, source.total
    else
        TIERS, AREAS, TASKS = baked.TIERS, {}, {}
    end
    for index, name in ipairs(TIERS) do tierRank[name] = index end
end

function Tasks.source()
    dataset()
    return live and "game" or "snapshot", liveTotal
end

-- var -> task, for the description tooltip on notes that are already saved.
local byVar
local function index()
    dataset()
    if byVar then return byVar end
    byVar = {}
    for _, list in pairs(TASKS) do
        for _, task in ipairs(list) do byVar[task[1][1]] = task end
    end
    return byVar
end

function Tasks.areas()
    dataset()
    local list = {}
    for _, area in ipairs(AREAS) do list[#list + 1] = { id = area[1], name = area[2] } end
    return list
end

-- Options for one area
function Tasks.options(area)
    dataset()
    local options = {}
    for _, task in ipairs(area and TASKS[area.id] or {}) do
        local vars, name, details, icon, tier, target, steps = task[1], task[2], task[3], task[4], task[5], task[6], task[7]
        options[#options + 1] = {
            kind = "task", varName = vars[1], taskVars = #vars > 1 and vars or nil, key = vars[1],
            label = tier .. ": " .. name, description = details, spriteName = icon and ("#" .. icon) or nil,
            rank = tierRank[tier] or 99, steps = target, defaultTarget = target, parts = steps,
        }
    end
    return options
end

-- The named parts of a multi-part task:
function Tasks.parts(var)
    local task = index()[var]
    return task and task[7] or nil
end

function Tasks.description(var)
    local task = index()[var]
    return task and task[3] or nil
end

-- This tracks to see if we've met the requirements for our Area tasks.
function Tasks.requirements(var)
    dataset()
    local wanted = REQUIREMENTS[var]
    local list = {}
    if not wanted then return list end
    for _, need in ipairs(wanted.skills or {}) do
        local entry = Skills.SKILL_BY_TYPE[need[1]]
        if entry then
            local have = Skills.readSkillLevel(entry)
            list[#list + 1] = { kind = "skill", skill = entry, name = entry.name, level = need[2], have = have,
                met = have == nil or have >= need[2], icon = Skills.skillIconRef(entry) }
        end
    end
    for _, questId in ipairs(wanted.quests or {}) do
        local need = live and TaskSource.QuestNeed(questId)
        if need then
            list[#list + 1] = { kind = "quest", name = need.name, sprite = need.sprite, met = need.done == nil or need.done == true }
        end
    end
    return list
end

return { Tasks = Tasks }