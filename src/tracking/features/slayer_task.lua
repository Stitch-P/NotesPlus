-- Your current Slayer task and Reaper (boss Slayer) task as notes: shows the monster (name, description, requirements and
-- its model in the hover card) and how many kills are left.
--
-- The game keeps the task in two variables each: SLAYER_TARGET holds the monster's id and SLAYER_COUNT the kills left;
-- BSLAY_TARGET holds the boss's id and BSLAY_KILLS_LEFT the kills left. The details come from the game's own structs
-- (core/slayer_task_source.lua). The note remembers the biggest "kills left" it has seen for the current task
-- (tracking.base) and which task that was (tracking.gained), so the bar can fill as the count drops.

local Vars = require("src/tracking/core/vars")
local Source = require("src/tracking/core/slayer_task_source")

local SlayerTask = {}

SlayerTask.GROUP = "Current task"

local KINDS = {
    ["task:slayer"] = { label = "Slayer task", target = "SLAYER_TARGET", left = "SLAYER_COUNT", streak = "SMKI_MISSION_COUNT", reaper = false },
    ["task:reaper"] = { label = "Reaper task", target = "BSLAY_TARGET", left = "BSLAY_KILLS_LEFT", streak = "BSLAY_TASK_STREAK", reaper = true },
}
local ORDER = { "task:slayer", "task:reaper" }

function SlayerTask.isTask(key) return KINDS[key] ~= nil end

function SlayerTask.options()
    local options = {}
    for _, key in ipairs(ORDER) do
        local kind = KINDS[key]
        options[#options + 1] = {
            kind = "slayertask", key = key, label = kind.label, varName = kind.left, defaultTarget = 1, rank = #options + 1,
            description = SlayerTask.description(key),
        }
    end
    return options
end

function SlayerTask.description(key)
    local kind = KINDS[key]
    if not kind then return nil end
    return kind.reaper and "Shows your current Reaper task: the boss, how many kills are left and its details."
        or "Shows your current Slayer task: the monster, how many kills are left and its details."
end

-- The game stores a monster's weakness as a number on its NPC (COMBATV2_WEAKNESS). It is shown as a combat style
-- (the combat triangle): 1-4 elemental spells and 11 are Magic, 5-7 Stab/Slash/Crush are Melee, 8-10 Arrows/Bolts/Thrown are
-- Ranged (1-10 confirmed against the wiki; 11 and 21 are best guesses; 21 is Necromancy, which has no triangle icon).
local STYLE_OF = { "Magic", "Magic", "Magic", "Magic", "Melee", "Melee", "Melee", "Ranged", "Ranged", "Ranged", [11] = "Magic", [21] = "Necromancy" }
-- The game's own combat triangle icons (COMBATV2_COMBAT_TRIANGLE_WEAKNESS_ICONS: 1 Magic, 2 Melee, 3 Ranged).
-- The exact weakness shown as text; the combat style only picks the icon.
local WEAKNESS_NAME = { "Air spells", "Water spells", "Earth spells", "Fire spells", "Stab", "Slash", "Crush", "Arrows", "Bolts",
    "Thrown", [11] = "Magic", [21] = "Necromancy" }
local STYLE_ICON_FALLBACK = { Magic = 202, Melee = 197, Ranged = 200 }
local STYLE_INDEX = { Magic = 1, Melee = 2, Ranged = 3 }

local function styleSprite(style)
    local index = STYLE_INDEX[style]
    if not index then return nil end
    local ConfigReader = require("src/tracking/core/config_reader")
    for _, pair in ipairs(ConfigReader.EnumPairs("COMBATV2_COMBAT_TRIANGLE_WEAKNESS_ICONS")) do
        if pair[1] == index and type(pair[2]) == "number" and pair[2] > 0 then return pair[2] end
    end
    return STYLE_ICON_FALLBACK[style]
end

local function weaknessRow(npcId)
    if not npcId then return nil end
    local ConfigReader = require("src/tracking/core/config_reader")
    local okNpc, npc = pcall(function() return config.NPC.FromID(npcId) end)
    local value = okNpc and npc and ConfigReader.StructParam(npc, "COMBATV2_WEAKNESS")
    local style = type(value) == "number" and STYLE_OF[value]
    if not style then return nil end
    return { label = "Weakness: " .. (WEAKNESS_NAME[value] or style), spriteId = styleSprite(style) }
end

local function readName(name)
    local entry = Vars.resolveVar(name)
    local value = entry and Vars.readEntry(entry)
    return type(value) == "number" and value == value and value or nil
end

-- { id, left, info } for the current task of that kind. id is 0 when there is none; nil when unreadable.
function SlayerTask.Current(key)
    local kind = KINDS[key]
    if not kind then return nil end
    local taskId, left = readName(kind.target), readName(kind.left)
    if taskId == nil then return nil end
    local details
    if taskId > 0 then
        local ok, table_ = pcall(kind.reaper and Source.Bosses or Source.Monsters)
        details = ok and table_ and table_[taskId] or nil
    end
    return { id = taskId, left = left or 0, info = details }
end

-- Progress for Tracking.Read: current/target/fraction/text/complete.
-- "\nTask streak: 66" for the line under the task, or "" when the streak can't be read.
local function streakLine(kind)
    local streak = kind.streak and readName(kind.streak)
    return streak and ("\nTask streak: " .. Vars.withCommas(streak)) or ""
end

function SlayerTask.Progress(tracking)
    local kind = KINDS[tracking.key]
    local task = SlayerTask.Current(tracking.key)
    if not task then return {current = nil, target = 1, fraction = 0, complete = false, text = "Waiting for your task"} end
    if task.id == 0 or task.left <= 0 then
        return {current = 0, target = 1, fraction = 0, complete = false,
            text = "No active " .. (kind.reaper and "Reaper" or "Slayer") .. " task" .. streakLine(kind)}
    end
    local base = tracking.base
    -- Only trust the remembered size if it belongs to this task.
    if tracking.gained ~= task.id or type(base) ~= "number" or base < task.left then base = task.left end
    local done = base - task.left
    local fraction = base > 0 and math.max(0, math.min(1, done / base)) or 0
    local name = task.info and task.info.name or ("Task " .. task.id)
    return {current = done, target = base, fraction = fraction, complete = false,
        text = string.format("%s: %s left (%d%%)", (name:gsub("^%l", string.upper)), Vars.withCommas(task.left), math.floor(fraction * 100))
            .. streakLine(kind)}
end

-- The hover card: {key, body, model = {npc, zoom}}.
function SlayerTask.Card(key)
    local kind = KINDS[key]
    if not kind then return nil end
    local task = SlayerTask.Current(key)
    if not task or task.id == 0 or task.left <= 0 then
        return {key = key .. ":none", body = "You don't have an active " .. (kind.reaper and "Reaper" or "Slayer") .. " task."}
    end
    local info = task.info
    if not info then return {key = key .. ":" .. task.id, body = "Task " .. task.id .. " (no details found for it)."} end
    local lines = {}
    if info.description then lines[#lines + 1] = info.description end
    local extraRows = {}
    if #lines > 0 then lines[#lines + 1] = "" end
    if kind.reaper then
        if info.combatLevel then lines[#lines + 1] = "Combat level: " .. info.combatLevel end
        if info.points then
            local okSprite, spriteId = pcall(function() return id.Sprite["AIF_BOSS_SLAYER_POINTS_ICON_SML"] end)
            extraRows[#extraRows + 1] = { spriteId = okSprite and spriteId or nil, label = "Reaper points: " .. info.points }
        end
    else
        if info.combat then lines[#lines + 1] = "Combat level: " .. info.combat end
        local weakness = weaknessRow(info.npc)
        if weakness then extraRows[#extraRows + 1] = weakness end
    end
    while lines[#lines] == "" do lines[#lines] = nil end
    return {
        key = key .. ":" .. task.id, body = table.concat(lines, "<br>"),
        model = info.npc and { npc = info.npc, zoom = info.zoom } or nil, extraRows = extraRows,
    }
end

-- The same card for any Reaper boss by its id (the Reaper crew list).
function SlayerTask.BossCard(bossId)
    local bosses = Source.Bosses()
    local info = bosses and bosses[bossId]
    if not info then return nil end
    local lines = {}
    if info.description then lines[#lines + 1] = info.description; lines[#lines + 1] = "" end
    if info.combatLevel then lines[#lines + 1] = "Combat level: " .. info.combatLevel end
    local extraRows = {}
    if info.points then
        local okSprite, spriteId = pcall(function() return id.Sprite["AIF_BOSS_SLAYER_POINTS_ICON_SML"] end)
        extraRows[#extraRows + 1] = { spriteId = okSprite and spriteId or nil, label = "Reaper points: " .. info.points }
    end
    while lines[#lines] == "" do lines[#lines] = nil end
    return {
        key = "boss:" .. bossId, body = table.concat(lines, "<br>"),
        model = info.npc and { npc = info.npc, zoom = info.zoom } or nil, extraRows = extraRows,
    }
end

-- Remembers the size of the current assignment on each task note. Returns true when a note changed.
function SlayerTask.Poll(notes)
    local changed = false
    for _, note in ipairs(notes) do
        local tracking = note.tracking
        if tracking and tracking.category == "Slayer" and KINDS[tracking.key] then
            local task = SlayerTask.Current(tracking.key)
            if task then
                if task.id == 0 or task.left <= 0 then
                    if tracking.gained ~= 0 then tracking.gained, tracking.base, changed = 0, nil, true end
                elseif tracking.gained ~= task.id then
                    tracking.gained, tracking.base, changed = task.id, task.left, true
                elseif type(tracking.base) ~= "number" or task.left > tracking.base then
                    tracking.base, changed = task.left, true
                end
            end
        end
    end
    return changed
end

return { SlayerTask = SlayerTask }