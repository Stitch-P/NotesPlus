local Skills = require("src/tracking/features/skills")
local Bosses = require("src/tracking/data/bosses").BOSSES
local Clues = require("src/tracking/data/clues")
local Quests = require("src/tracking/features/quests").Quests
local Vars = require("src/tracking/core/vars")
local KILLS_PREFIX = require("src/tracking/constants").KILLS_PREFIX
local Goals = require("src/tracking/features/achievement_goals").AchievementGoals
local Combat = require("src/tracking/features/combat").Combat
local Tasks = require("src/tracking/features/tasks").Tasks

local Randomizer = {}
local Job = {}
Job.__index = Job

local SUPPORTED = {Skills = true, Bossing = true, Combat = true, Clues = true, Quests = true, Gathering = true, Tasks = true}
local FULL_POOL = {Bossing = true, Combat = true, Gathering = true, Tasks = true}
local CANDIDATES_PER_STEP = 4
local EXISTING_PER_STEP = 12
local MAX_ATTEMPTS = 64
local INCREMENTS = {1, 3, 5}
local EASY_CLUES = "TRAIL_EASY_CLUES_COMPLETED"
local SKILL_XP_CAP = 200000000
local SKILL_XP_INCREASES = {10, 15, 20}

local function identity(category, objective)
    return category .. ":" .. objective
end

local function integer(value)
    return type(value) == "number" and value == value and value >= 0 and value < math.huge and value % 1 == 0
end

local function read(name)
    return Vars.readEntry(Vars.resolveVar(name))
end

local function candidates(category, skillGroup)
    if category == "Skills" then
        local list = {}
        for _, entry in ipairs(Skills.SKILLS) do
            if skillGroup ~= "XP" then list[#list + 1] = {entry = entry, group = "Level"} end
            list[#list + 1] = {entry = entry, group = "XP"}
        end
        return list
    end
    if category == "Clues" then return Clues.CLUE_TIERS end
    if category == "Quests" then return Quests.loadedEntries() end
    if category == "Gathering" then return require("src/tracking/model").Groups(category) end
    if category == "Combat" then return Combat.loadedGroups() end
    if category == "Tasks" then
        local list = {}
        for _, area in ipairs(Tasks.areas()) do
            for _, option in ipairs(Tasks.options(area)) do
                list[#list + 1] = {area = area, option = option}
            end
        end
        return list
    end
    local list, seen = {}, {}
    for _, boss in ipairs(Bosses) do
        for _, kill in ipairs(boss.kills or {}) do
            local variable = KILLS_PREFIX .. kill[2]
            if not kill[2]:find("HARDMODE", 1, true) and not seen[variable] then
                seen[variable] = true
                list[#list + 1] = {boss = boss, label = kill[1], variable = variable}
            end
        end
    end
    return list
end

local function skillObjective(skill, group)
    return group == "XP" and "XP:" .. skill or skill
end

local function candidateIdentity(category, candidate)
    local objective = category == "Skills" and skillObjective(candidate.entry.skill, candidate.group)
        or category == "Gathering" and (candidate.option.kind == "mining" and candidate.option.key or candidate.option.varName)
        or category == "Tasks" and candidate.option.key
        or category == "Bossing" and candidate.variable or candidate.var
    return identity(category, objective)
end

local function result(category, groupName, option, targetText, key)
    local group = groupName and {name = groupName, key = groupName, label = groupName} or nil
    return {category = category, group = group, option = option, targetText = targetText, identity = key}
end

local function clueResult(candidate, mode, target, key)
    local variable = candidate.var
    return result("Clues", Clues.GROUP_COUNTERS, {
        key = mode .. ":" .. variable,
        label = candidate.name .. " clues: " .. (mode == "total" and "Total completions" or "Individual completions"),
        kind = "clues", mode = mode, vars = {variable}, varName = variable,
        obj = candidate.obj, objId = candidate.obj, group = Clues.GROUP_COUNTERS,
    }, tostring(target), key)
end

local function evaluate(category, candidate, key)
    if category == "Combat" then
        local option = Combat.randomCandidate(candidate.boss, candidate.var)
        return option and result(category, candidate.boss.name, option, "1", key) or nil
    end
    if category == "Gathering" then
        local option = candidate.option
        local target = 1
        if option.kind == "mining" then
            target = INCREMENTS[math.random(#INCREMENTS)]
        elseif (option.kind == "breed" and not Goals.randomBreedAvailable(option)) or read(option.varName) ~= 0 then
            return nil
        end
        local generated = result(category, candidate.group.name, option, tostring(target), key)
        generated.group.sub = candidate.group.sub
        return generated
    end
    if category == "Skills" then
        local entry = candidate.entry
        local target
        if candidate.group == "XP" then
            local xp = Skills.readSkillXP(entry)
            if type(xp) ~= "number" or not (xp >= 0 and xp < SKILL_XP_CAP) then return nil end
            local percent = SKILL_XP_INCREASES[math.random(#SKILL_XP_INCREASES)]
            local increase = math.max(xp, 10000) * percent / 100
            target = math.min(SKILL_XP_CAP, math.ceil((xp + increase) / 1000) * 1000)
        else
            local level = Skills.readSkillLevel(entry)
            if not integer(level) or level < 1 or level >= Skills.MaxLevel(entry.skill) then return nil end
            target = level + 1
        end
        if entry.skill == "INVENTION" then
            for _, name in ipairs({"SMITHING", "CRAFTING", "DIVINATION"}) do
                local required = Skills.SKILL_BY_TYPE[name]
                local have = required and Skills.readSkillLevel(required)
                if not integer(have) or have < 80 then return nil end
            end
        end
        return result(category, candidate.group, {key = entry.skill, label = entry.name, kind = "skill",
            skill = entry.skill, entry = entry}, tostring(target), key)
    end
    if category == "Quests" then
        local group, option = Quests.randomCandidate(candidate)
        return option and result(category, group, option, "1", key) or nil
    end
    if category == "Tasks" then
        local option = candidate.option
        local progress = require("src/tracking/model").Preview("Tasks", candidate.area, option)
        if not progress or not integer(progress.current) or progress.complete then return nil end
        for _, requirement in ipairs(Tasks.requirements(option.varName)) do
            if not requirement.met then return nil end
        end
        return result(category, candidate.area.name, option, tostring(option.steps or 1), key)
    end
    local variable = category == "Bossing" and candidate.variable or candidate.var
    local entry = Vars.resolveVar(variable)
    local current = Vars.readEntry(entry)
    if category == "Clues" and variable == EASY_CLUES and entry and current == nil then
        return clueResult(candidate, "total", 1, key)
    end
    if not integer(current) then return nil end
    if category == "Clues" and current == 0 and variable ~= EASY_CLUES then return nil end
    local increment = current == 0 and 1 or INCREMENTS[math.random(#INCREMENTS)]
    if category == "Bossing" then
        if current + increment > 1e15 then return nil end
        return result(category, candidate.boss.name, {key = variable, label = candidate.label,
            kind = "kills", varName = variable}, tostring(current + increment), key), current == 0
    end
    return clueResult(candidate, "individual", increment, key)
end

function Randomizer.Supports(category)
    return SUPPORTED[category] == true
end

function Randomizer.New(category, existingTrackings, recentKeys, group)
    local recent = {}
    for key, value in pairs(recentKeys or {}) do
        if type(key) == "string" and value then recent[key] = 1
        elseif type(key) == "number" and type(value) == "string" then
            recent[value] = math.max(recent[value] or 0, key)
        end
    end
    return setmetatable({category = category, skillGroup = group, existing = {}, recent = recent, attempts = 0,
        stack = {{items = existingTrackings or {}, index = 1}}, pool = {}}, Job)
end

local function pick(list, pool, remaining)
    local selected = math.random(remaining)
    local index = pool[selected] or selected
    pool[selected] = pool[remaining] or remaining
    pool[remaining] = nil
    return list[index], remaining - 1
end

function Job:_hasCandidates()
    return self.remaining > 0 or (self.sectionRemaining or 0) > 0 or (self.itemRemaining or 0) > 0
        or (self.achievementRemaining or 0) > 0
end

function Job:_nextGatheringCandidate()
    if (self.itemRemaining or 0) > 0 then
        local option
        option, self.itemRemaining = pick(self.gatheringItems, self.itemPool, self.itemRemaining)
        return {group = self.gatheringGroup, option = option}
    end
    if (self.sectionRemaining or 0) == 0 then
        self.group, self.remaining = pick(self.candidates, self.pool, self.remaining)
        self.sections = self.group.subs or {}
        self.sectionPool, self.sectionRemaining = {}, #self.sections
    end
    local section
    if self.sectionRemaining > 0 then
        section, self.sectionRemaining = pick(self.sections, self.sectionPool, self.sectionRemaining)
    end
    self.gatheringGroup = {name = self.group.name, sub = section and section.name}
    if self.group.name == Goals.FARM then
        if not self.farmAnimals then
            self.farmAnimals = {}
            for _, animal in ipairs(Goals.loadedFarmAnimals() or {}) do self.farmAnimals[animal.animal] = animal end
        end
        local animal = section and self.farmAnimals[section.name]
        self.gatheringItems = animal and Goals.randomBreeds(animal) or {}
    else
        self.gatheringItems = require("src/tracking/model").CollectionOptions("Gathering", self.gatheringGroup)
    end
    self.itemPool, self.itemRemaining = {}, #self.gatheringItems
end

function Job:_nextCandidate()
    if self.category == "Combat" then
        if (self.achievementRemaining or 0) > 0 then
            local variable
            variable, self.achievementRemaining = pick(self.achievements, self.achievementPool, self.achievementRemaining)
            return {boss = self.boss, var = variable}
        end
        self.boss, self.remaining = pick(self.candidates, self.pool, self.remaining)
        self.achievements = self.boss.achievements or {}
        self.achievementPool, self.achievementRemaining = {}, #self.achievements
        return
    end
    if self.category == "Gathering" then return self:_nextGatheringCandidate() end
    local candidate
    candidate, self.remaining = pick(self.candidates, self.pool, self.remaining)
    return candidate
end

function Job:_indexExisting()
    for _ = 1, EXISTING_PER_STEP do
        local frame = self.stack[#self.stack]
        if not frame then return true end
        local tracking = frame.items[frame.index]
        frame.index = frame.index + 1
        if tracking == nil then
            self.stack[#self.stack] = nil
        elseif type(tracking) == "table" then
            local category = tracking.category or frame.category
            local group = tracking.group or frame.group
            if type(tracking.items) == "table" then
                self.stack[#self.stack + 1] = {items = tracking.items, index = 1, category = category, group = group}
            elseif type(category) == "string"
                and not (category == "Clues" and type(tracking.vars) == "table" and #tracking.vars > 1) then
                local objective = tracking.skill or tracking.variable
                if type(objective) == "string" and objective ~= "" then
                    if category == "Skills" and tracking.skill then objective = skillObjective(objective, group) end
                    self.existing[identity(category, objective)] = true
                end
                if category == "Gathering" and type(tracking.key) == "string" then
                    self.existing[identity(category, tracking.key)] = true
                end
                for _, variable in ipairs(tracking.vars or {}) do
                    self.existing[identity(category, variable)] = true
                end
            end
        end
    end
    return #self.stack == 0
end

function Job:Step()
    if self.done then return self.result, true, self.message end
    if not Randomizer.Supports(self.category) then
        self.done, self.message = true, "Random goals aren't available for this type yet."
        return nil, true, self.message
    end
    if not self:_indexExisting() then return nil, false end
    if not self.candidates then
        self.candidates = candidates(self.category, self.skillGroup)
        if not self.candidates then
            self.done = true
            self.message = self.category == "Combat" and "Combat achievements aren't available yet. Select Combat again, then try again."
                or "The quest list isn't ready. Select Quests again, then try again."
            return nil, true, self.message
        end
        self.remaining = #self.candidates
        self.attemptLimit = FULL_POOL[self.category] and math.huge or MAX_ATTEMPTS
    end
    for _ = 1, CANDIDATES_PER_STEP do
        if not self:_hasCandidates() or self.attempts >= self.attemptLimit then break end
        self.attempts = self.attempts + 1
        local candidate = self:_nextCandidate()
        local key = candidate and candidateIdentity(self.category, candidate)
        if key and not self.existing[key] then
            local generated, firstKill = evaluate(self.category, candidate, key)
            if generated then
                local rank = self.recent[key]
                if firstKill then
                    local firstRank = rank or 0
                    if not self.firstKillResult or firstRank < self.firstKillRank then
                        self.firstKillResult, self.firstKillRank = generated, firstRank
                    end
                elseif not rank then
                    self.done, self.result = true, generated
                    return generated, true
                elseif not self.recentRank or rank < self.recentRank then
                    self.recentResult, self.recentRank = generated, rank
                end
            end
        end
    end
    if self:_hasCandidates() and self.attempts < self.attemptLimit then return nil, false end
    self.done = true
    self.result = self.recentResult or self.firstKillResult
    if self.result then
        return self.result, true
    end
    self.message = "No eligible goal found. You may have completed all eligible tracking or this Type isn't supported. "
    return nil, true, self.message
end

return Randomizer
