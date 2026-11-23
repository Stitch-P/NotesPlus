-- Achievement goals under Unlocks: Necromancy > Kili's Knowledge, and Archaeology > Qualifications, Research and Mysteries.
-- Each goal is one of the game's own achievements, done once the game marks it complete (so finished ones are not offered).
-- Kili's Knowledge and the qualifications are single achievements. Research and Mysteries have one goal per dig site, whose
-- individual research / mysteries are shown as sub tasks (done or not), like an Area task.

local ConfigReader = require("src/tracking/core/config_reader")
local Archaeology = require("src/tracking/data/archaeology")
local Necromancy = require("src/tracking/features/necromancy").Necromancy
local Data = { KILI = Necromancy.KILI, QUALIFICATIONS = Archaeology.QUALIFICATIONS, SITES = Archaeology.SITES, RESEARCHERS = Archaeology.RESEARCHERS,
    SPECS = Archaeology.SPECS, DESCRIPTIONS = Archaeology.DESCRIPTIONS }
local Vars = require("src/tracking/core/vars")
local PetObjects = require("src/tracking/core/pet_objects")

local Cheevos = {}

Cheevos.NECRO_GROUP = "Necromancy"
Cheevos.ARCH_GROUP = "Archaeology"
Cheevos.KILI = "Kili's Knowledge"
Cheevos.QUALIFICATIONS = "Qualifications"
Cheevos.RESEARCH = "Research"
Cheevos.MYSTERIES = "Mysteries"
Cheevos.RESEARCHERS = "Researchers"
-- Skills > Combat Pets / Skilling Pets: one goal per pet, done once its achievement is (or, for the newest three, once
-- the game says the pet is owed to you).
Cheevos.COMBAT_PETS = "Combat Pets"
Cheevos.SKILLING_PETS = "Skilling Pets"

-- The pets' achievements, as listed by Jack of All Blades / Jack of All Trades.
local COMBAT_PET_IDS = { 1215, 1219, 1220, 1230, 3298, 1232, 1233, 1235, 1237, 1238 }
local SKILLING_PET_IDS = { 1213, 1214, 1216, 1217, 1218, 1221, 1222, 1223, 1224, 1225, 1226, 1227, 1228, 1229, 1231, 1234,
    1236, 1239, 1240 }
-- Set once the pet has dropped but not been claimed yet; counts as having it.
local PET_OWED = { PRAYER = "SKILLPETS_PRAYER_PET_OWED", MAGIC = "SKILLPETS_MAGIC_PET_OWED",
    SUMMONING = "SKILLPETS_SUMMONING_PET_OWED" }
-- The pet's own item, shown as its picture. The newest pets' items are known; the others are tried by the same naming.
local PET_OBJECTS = { PRAYER = "SKILLPETS_PRAYER_PET_DROP", MAGIC = "SKILLPETS_MAGIC_PET_DROP",
    SUMMONING = "SKILLPETS_SUMMONING_PET_DROP" }
local PET_SPRITE_FALLBACK = 30108

function Cheevos.isPetGroup(name) return name == Cheevos.COMBAT_PETS or name == Cheevos.SKILLING_PETS end

-- Unlocks > Group Ironman: the Journey Tiers (each a goal with its tasks as sub tasks) and the tasks one by one. Only
-- offered to Group Ironmen. Task wording (and targets) depend on the group's size.
Cheevos.GIM_GROUP = "Group Ironman"
Cheevos.GIM_TIERS = "Journey Tiers"
Cheevos.GIM_TASKS = "Tasks"
Cheevos.GIM_ICON = 33651 -- the Group Ironman helmet (Journey Tier 0's picture)
local GIM_ENABLED_VAR = "GROUP_IRONMAN_ENABLED"
local GIM_SIZE_VAR = "GROUP_IRONMAN_CACHE_GROUP_SIZE"
-- The group's running totals, for the total level / Quest Points tasks.
local GIM_TOTALS = { ["Total level"] = "GROUP_IRONMAN_ACHIEVEMENT_TOTAL_PLAYER_CACHE_TOTAL_LEVEL",
    ["Total Quest Points"] = "GROUP_IRONMAN_ACHIEVEMENT_TOTAL_PLAYER_CACHE_TOTAL_QUESTPOINTS" }
local GimData = require("src/tracking/data/group_ironman")

-- Unlocks > Memorial to Guthix: the engrams (and the Memories of Guthix achievement, with every engram as a sub task),
-- and the Fountain of Energy's passive effects (a goal is done while the effect is on).
Cheevos.HOG_GROUP = "Memorial to Guthix"
Cheevos.HOG_ENGRAMS = "Engrams"
Cheevos.HOG_EFFECTS = "Passive effects"
local HogData = require("src/tracking/data/memorial_guthix")

-- Unlocks > Hall of Memories: the five memory-storage bots of the "Data Recovery" achievement. DIVCHAMBER_RECOVERY_PROGRESS
-- counts the core memory data recovered: bot n is back once it reaches n + 1. Each bot gives a perk (enum
-- divchamber_recovery_bot_unlock, keyed 8..12 for bots 1..5).
Cheevos.HOM_GROUP = "Hall of Memories"
Cheevos.HOM_BOTS = "Memory-storage bots"
local HOM_PROGRESS_VAR = "DIVCHAMBER_RECOVERY_PROGRESS"
local HOM_BOTS = {
    { "Memory-storage bot (Aagi)", "Extra passive effect from the Memorial to Guthix fountain of energy." },
    { "Memory-storage bot (Seren)", "Increased memory strand gain whilst in the Hall of Memories." },
    { "Memory-storage bot (Juna)", "Increased chance to spawn a chronicle fragment." },
    { "Memory-storage bot (Edicts)", "Increased memory gain when harvesting from faded memories." },
    { "Memory-storage bot (Cres)", "Increased energy gain when converting memories." },
}
Cheevos.HOM_ICON_OBJECT = "DIVCHAMBER_RECOVERY_BOT_1"

-- Unlocks > Music: one "Music Maestro" goal that counts how many of all the tracks you have unlocked and how many are left.
-- The track list is read from the game (data/music.lua), so tracks added later are counted by themselves.
Cheevos.MUSIC_GROUP = "Music"
Cheevos.MUSIC_MAESTRO = "Music Maestro"
Cheevos.MUSIC_OBJECT = "GRIM_MUSICSHEET"
local MusicData = require("src/tracking/data/music")

-- Unlocks > Titles: the player titles you can earn and that the game lets us tell you own (data/titles.lua), in two
-- sections: those given by an achievement and those given by an event or other reward. A title is shown the way it appears
-- in the game, in its own colours, read from the game's title enum.
Cheevos.TITLES_GROUP = "Titles"
Cheevos.TITLES_ACHIEVEMENTS = "Achievements"
Cheevos.TITLES_REWARDS = "Events and rewards"
local TitleData = require("src/tracking/data/titles")
local TITLE_SPRITE = 30108

-- Slayer > Slayer Codex: every monster an ushabti can capture. Monster at codex position p is captured once bit
-- (p - 1) % 32 of SLAYER_CODEX_<n> is set (data/slayer_codex.lua).
Cheevos.CODEX_GROUP = "Slayer Codex"
local CodexData = require("src/tracking/data/slayer_codex")
Cheevos.CODEX_OBJECT, Cheevos.USHABTI_OBJECT = CodexData.CODEX, CodexData.USHABTI
function Cheevos.isCodexGroup(name) return name == Cheevos.CODEX_GROUP end

-- Ports > Scrolls: the player-owned ports scrolls, each done once all four of its pieces are found.
Cheevos.SCROLLS_GROUP = "Scrolls"
Cheevos.SCROLL_SPRITE = 15701 -- the voyage scroll icon (pop_voyage_scroll_icons' default)
local ScrollData = require("src/tracking/data/pop_scrolls")
function Cheevos.isScrollGroup(category, name) return category == "Ports" and name == Cheevos.SCROLLS_GROUP end

-- The skill statues: Dahmaroc's in Varrock (Unlocks > Varrock, a group of its own) and Rhiannon's in Prifddinas
-- (Unlocks > Prifddinas > Statue of Rhiannon, a section).
-- A skill's goal is done once its piece has been added to the statue; each goal wears the skill's icon.
local StatueData = require("src/tracking/data/dahmaroc_statues")
Cheevos.VARROCK_GROUP = "Varrock"
Cheevos.VARROCK_STATUE = "Statue of Dahmaroc" -- the Varrock section (and its goal list)
-- Varrock's sections: the statue and the Varrock Museum's kudos (VM_KUDOS, at most 198 - the "Kudos to You" achievement).
Cheevos.VARROCK_STATUE_SECTION, Cheevos.KUDOS_SECTION = "Statue of Dahmaroc", "Museum Kudos"
Cheevos.KUDOS_KEY, Cheevos.KUDOS_VAR, Cheevos.KUDOS_MAX = "varrock-kudos", "VM_KUDOS", 198
Cheevos.VARROCK_TASK_SPRITE = 4383 -- the Varrock area tasks' icon
function Cheevos.kudosOption()
    return { kind = "kudos", key = Cheevos.KUDOS_KEY, label = "Museum kudos", varName = Cheevos.KUDOS_VAR,
        defaultTarget = Cheevos.KUDOS_MAX, spriteName = "#" .. Cheevos.VARROCK_TASK_SPRITE,
        description = "Kudos earned at the Varrock Museum (" .. Cheevos.KUDOS_MAX .. " is the most there is)." }
end
Cheevos.PRIF_GROUP = "Prifddinas"
Cheevos.PRIF_STATUE = "Statue of Rhiannon"
-- The statues' "list" items, worn by their notes.
Cheevos.VARROCK_STATUE_OBJECT, Cheevos.PRIF_STATUE_OBJECT = 15520, 32154
function Cheevos.isStatueGroup(group, sub)
    return group == Cheevos.VARROCK_GROUP and sub ~= Cheevos.KUDOS_SECTION or group == Cheevos.PRIF_GROUP and sub == Cheevos.PRIF_STATUE
end
-- The statue a goal's section belongs to: the list to show for a group (and section).
function Cheevos.statueSection(group, sub)
    if group == Cheevos.VARROCK_GROUP and sub ~= Cheevos.KUDOS_SECTION then return Cheevos.VARROCK_STATUE end
    if group == Cheevos.PRIF_GROUP and sub == Cheevos.PRIF_STATUE then return Cheevos.PRIF_STATUE end
    return nil
end
-- A real variable the note can carry; these goals read achievements, not a variable.
-- Your Archaeology qualification: 1 Intern, 2 Assistant, 3 Associate, 4 Professor, 5 Guildmaster.
Cheevos.QUALIFICATION_VAR = "-46469"
Cheevos.PLACEHOLDER_VAR = "RAND_REWARD_TOKENS"

local PREFIX = "cheevo:"
local KILI_SPRITE_FALLBACK = 30937

local function objectId(name)
    if type(name) == "number" then return name >= 0 and name or nil end
    local ok, value = pcall(function() return id.Obj[name] end)
    return ok and type(value) == "number" and value >= 0 and value or nil
end

function Cheevos.isKey(key) return type(key) == "string" and key:sub(1, #PREFIX) == PREFIX end

-- Which sections each group has.
function Cheevos.isSection(group, sub)
    if group == Cheevos.GIM_GROUP then return sub == Cheevos.GIM_TIERS or sub == Cheevos.GIM_TASKS end
    if group == Cheevos.HOG_GROUP then return sub == Cheevos.HOG_ENGRAMS or sub == Cheevos.HOG_EFFECTS end
    if group == Cheevos.NECRO_GROUP then return sub == Cheevos.KILI end
    if group == Cheevos.HOM_GROUP then return sub == Cheevos.HOM_BOTS end
    if group == Cheevos.MUSIC_GROUP then return Cheevos.musicSectionExists(sub) end
    if group == Cheevos.PRIF_GROUP and sub == Cheevos.PRIF_STATUE then return true end
    if group == Cheevos.ARCH_GROUP then return sub == Cheevos.QUALIFICATIONS or sub == Cheevos.RESEARCH or sub == Cheevos.MYSTERIES or sub == Cheevos.RESEARCHERS end
    return false
end

-- The section a saved goal belongs to (to reopen a note on it), from its key.
function Cheevos.sectionOf(key)
    local entry = Cheevos.info(key)
    return entry and entry.section or nil
end

local function text(value) return type(value) == "string" and value ~= "" and value ~= "null" and value or nil end

local function keyOf(config) return PREFIX .. tostring(config):lower() end
local function configOf(key) local name = key:sub(#PREFIX + 1); return tonumber(name) or name end

-- Whether the game says this achievement is finished: true / false, or nil when it can't be read.
local function achievementDone(config)
    local achievement = ConfigReader.Achievement(config)
    if not achievement then return nil end
    local okProgress, progress = pcall(function() return achievement.progress end)
    local complete = type(AchievementProgressType) == "table" and AchievementProgressType.COMPLETE
    if okProgress and progress ~= nil and complete ~= nil and complete ~= false then return progress == complete end
    local okFlag, flag = pcall(function() return achievement.isComplete end)
    if okFlag and type(flag) == "boolean" then return flag end
    return nil
end

local sections, byKey
local build, partsOf

-- Done / total of the parts of a site goal, and whether they could all be read.
local function partCount(entry)
    local done, total, unknown = 0, 0, false
    for _, part in ipairs(partsOf(entry)) do
        total = total + 1
        if part.done then done = done + 1 elseif part.done == nil then unknown = true end
    end
    return done, total, unknown
end

local resolvePet

local gimDone

-- Music: whether one track is unlocked (nil when its variable can't be read yet). The variable is looked up once per track.
local musicEntries, musicLive = {}, false
local function trackOwned(entry)
    if entry.varEntry == nil then entry.varEntry = Vars.resolveVar(entry.flag) or false end
    if not entry.varEntry then return nil end
    local value = Vars.readEntry(entry.varEntry)
    if type(value) ~= "number" then return nil end
    return value >= 1
end

-- How many of the tracks are unlocked and how many there are; nil for the count while no track can be read.
-- Counted at most twice a second: a note asks several times per refresh and there are well over a thousand tracks.
local countedAt, countedDone, countedOf
local function musicCount()
    local now = type(os) == "table" and os.clock and os.clock() or nil
    if now and countedAt and now - countedAt < 0.5 and countedOf == #musicEntries then return countedDone, countedOf end
    local done, readable = 0, false
    for _, entry in ipairs(musicEntries) do
        local owned = trackOwned(entry)
        if owned ~= nil then readable = true end
        if owned then done = done + 1 end
    end
    countedAt, countedDone, countedOf = now, readable and done or nil, #musicEntries
    return countedDone, countedOf
end

function Cheevos.done(key)
    if not Cheevos.isKey(key) then return nil end
    build()
    local entry = byKey[key]
    if entry and entry.pet then
        resolvePet(entry)
        if entry.owed then
            local owed = Vars.readEntry(Vars.resolveVar(entry.owed))
            if type(owed) == "number" and owed > 0 then return true end
        end
    end
    if entry and entry.gim then return gimDone(entry.gim) end
    if entry and entry.track then return trackOwned(entry) end
    if entry and entry.achs then
        -- A title given by achievements: owned once any of them is complete.
        local unknown = true
        for _, achievementID in ipairs(entry.achs) do
            local finished = achievementDone(achievementID)
            if finished then return true end
            if finished ~= nil then unknown = false end
        end
        if not entry.flag then
            if unknown then return nil end
            return false
        end
    end
    if entry and entry.counter then
        local done, total = entry.counter()
        if done == nil or total == 0 then return nil end
        return done >= total
    end
    if entry and entry.flag then
        -- "VAR>=N": done once the variable reaches N; "VAR&B": once bit B is set; a plain flag once it is set.
        local base, minimum = entry.flag:match("^(.-)>=(%d+)$")
        local bitBase, bit = entry.flag:match("^(.-)&(%d+)$")
        local value = Vars.readEntry(Vars.resolveVar(base or bitBase or entry.flag))
        if type(value) ~= "number" then return nil end
        if bitBase then
            if value < 0 then value = value + 4294967296 end
            return math.floor(value / 2 ^ tonumber(bit)) % 2 == 1
        end
        return value >= (tonumber(minimum) or 1)
    end
    if entry and entry.tier then
        -- Your qualification level (1 Intern ... 5 Guildmaster) says which ones you hold.
        local level = Vars.readEntry(Vars.resolveVar(Cheevos.QUALIFICATION_VAR))
        if level ~= nil then return level >= entry.tier end
    end
    if entry and entry.parts then
        local done, total, unknown = partCount(entry)
        if total > 0 and done == total then return true end
        -- Partly unreadable: the game's own achievement flag settles it.
        if unknown then return achievementDone(configOf(key)) end
        return false
    end
    return achievementDone(configOf(key))
end

local function add(section, entry)
    entry.section, entry.key = section, keyOf(entry.config)
    if byKey[entry.key] then return end
    sections[section][#sections[section] + 1] = entry
    byKey[entry.key] = entry
end

-- A title as the game shows it, for a tooltip: its colour tags kept, <name> turned into a stand-in for your name, and
-- anything else that looks like markup made harmless.
local function titleMarkup(raw, nameText)
    -- Placeholders hold the tags that are kept while everything else that looks like markup is made harmless. Some of the
    -- game's colours are written RRGGBB, #RRGGBB or 0xRRGGBB; they are kept as RRGGBB, the form the rest of the plugin uses.
    raw = tostring(raw or ""):gsub("<name>", "\1")
        :gsub("<col=#?0?x?(%x%x%x%x%x%x)>", "\2%1\3"):gsub("</col>", "\4")
        :gsub("<str=#?0?x?(%x%x%x%x%x%x)>", "\5%1\3"):gsub("</str>", "\6"):gsub("<str>", "\7")
    raw = raw:gsub("<", "["):gsub(">", "]")
    return (raw:gsub("\1", nameText or "Name"):gsub("\2(%x%x%x%x%x%x)\3", "<col=%1>"):gsub("\4", "</col>")
        :gsub("\5(%x%x%x%x%x%x)\3", "<str=%1>"):gsub("\6", "</str>"):gsub("\7", "<str>"))
end

-- The text of a title: the game's own (read live) or the copy kept in data/titles.lua.
local function titleDisplay(entry)
    if entry.shown then return entry.shown end
    local live = ConfigReader.EnumValue(TitleData.ENUM, entry.titleId)
    local raw = type(live) == "string" and live:match("%S") and live ~= "<name>" and live or entry.display
    entry.rawText = raw
    local shown = titleMarkup(raw)
    if type(live) == "string" and live:match("%S") then entry.shown = shown end -- kept once the game's text was read
    return shown
end

-- Just the title's own words, in the game's colours, without the stand-in for your name and the commas and spaces that
-- joined it (", the Unpredictable" becomes "the Unpredictable").
local function titleNameMarkup(entry)
    titleDisplay(entry)
    local text = titleMarkup(entry.rawText, "")
    text = text:gsub("^(<col=%x+>)[,%s]+", "%1"):gsub("^[,%s]+", "")
    text = text:gsub("[,%s]+(</col>)$", "%1"):gsub("[,%s]+$", "")
    return text
end

-- The music track numbers: the snapshot in data/music.lua plus any track the game has added since (a named entry in its
-- music enum with a variable of its own that the achievement does not leave out). The second value is true when the game's
-- list could be read.
local function musicTrackList()
    local found, live = {}, false
    for _, number in ipairs(MusicData.TRACKS) do found[number] = true end
    local enum = ConfigReader.Enum(MusicData.ENUM)
    if enum then
        for number = 0, MusicData.LAST + MusicData.SCAN_PAST do
            local name = ConfigReader.EnumValue(enum, number)
            name = type(name) == "string" and name:match("^%s*(.-)%s*$") or ""
            if name ~= "" then
                live = true
                if not found[number] and not MusicData.SKIPPED[number] and Vars.resolveVar(MusicData.VAR_PREFIX .. number) then found[number] = true end
            end
        end
    end
    local list = {}
    for number in pairs(found) do list[#list + 1] = number end
    table.sort(list)
    return list, live
end

-- Adds the Music Maestro goal and the variable of every track it counts (the tracks themselves are not goals). Safe to
-- repeat until the game's list has been read once (the list may not be readable the first time).
local function addMusic()
    if musicLive then return end
    local maestro = "music:" .. Cheevos.MUSIC_MAESTRO
    sections[maestro] = sections[maestro] or {}
    add(maestro, { config = "music_maestro", name = Cheevos.MUSIC_MAESTRO, obj = Cheevos.MUSIC_OBJECT, noun = "tracks",
        counter = musicCount, description = "Unlock all music tracks.", doneText = "All tracks unlocked" })
    local list, live = musicTrackList()
    musicLive = live
    local known = {}
    for _, entry in ipairs(musicEntries) do known[entry.flag] = true end
    for _, number in ipairs(list) do
        local flag = MusicData.VAR_PREFIX .. number
        if not known[flag] then musicEntries[#musicEntries + 1] = { flag = flag, track = true } end
    end
end

-- The Music sections to choose from: just the Music Maestro goal.
function Cheevos.musicSections()
    build()
    if not musicLive then addMusic() end
    return { Cheevos.MUSIC_MAESTRO }
end

function Cheevos.musicSectionExists(sub)
    for _, name in ipairs(Cheevos.musicSections()) do if name == sub then return true end end
    return false
end

-- The name the Music section's goals are kept under.
function Cheevos.musicKey(sub) return "music:" .. tostring(sub or Cheevos.MUSIC_MAESTRO) end

-- Whether one research / mystery is done: true / false, or nil when it can't be read.
local function gimNumber(variable)
    local value = Vars.readEntry(Vars.resolveVar(variable))
    return type(value) == "number" and value or nil
end

-- Whether this character is a Group Ironman: true / false, or nil when the game hasn't said yet.
function Cheevos.gimEnabled()
    local value = gimNumber(GIM_ENABLED_VAR)
    if value == nil then return nil end
    return value > 0
end

-- The group's size (2 to 5), or nil when unknown.
function Cheevos.gimSize()
    local value = gimNumber(GIM_SIZE_VAR)
    return value and value >= 2 and value <= 5 and value or nil
end

-- A task's wording for this group's size.
local function gimText(task)
    local size = Cheevos.gimSize()
    return size and task[4][size] or task[4][0] or ""
end

-- "(5,643 / 6,000)" for the total level / Quest Points tasks, or nil.
local function gimTotals(task)
    local variable = GIM_TOTALS[task[2]]
    if not variable then return nil end
    local current = gimNumber(variable)
    local target = tonumber((gimText(task):match("(%d[%d,]*)") or ""):gsub(",", "") .. "")
    if not current or not target then return nil end
    return "(" .. Vars.withCommas(math.min(current, target)) .. " / " .. Vars.withCommas(target) .. ")"
end

-- Whether the group has done a task: the game's own achievement first, then the task's flag.
gimDone = function(task)
    local state = achievementDone(task[1])
    if state == true then return true end
    local flag = task[3] and gimNumber(task[3])
    if flag ~= nil then return flag > 0 end
    return state
end

local function partDone(part)
    if part.gim then return gimDone(part.gim) end
    if part[4] then return achievementDone(part[4]) end
    local value = Vars.readEntry(Vars.resolveVar(tostring(part[2])))
    if value == nil then return nil end
    if part[3] then return math.floor((value % 4294967296) / 2 ^ part[3]) % 2 == 1 end
    return value >= 1
end

local function readNumber(variable)
    return Vars.readEntry(Vars.resolveVar(tostring(variable)))
end

local function bitSet(value, bit) return math.floor((value % 4294967296) / 2 ^ bit) % 2 == 1 end

-- { current, target, unit } for the measure behind a qualification sub achievement, or nil when it can't be read.
local function measure(spec)
    local kind = spec[1]
    if kind == "skill" then
        local Skills = require("src/tracking/features/skills")
        local entry = Skills.SKILL_BY_TYPE[spec[2]]
        local level = entry and Skills.readSkillLevel(entry)
        return level and { level, spec[3], "level" }
    elseif kind == "var" then
        local value = readNumber(spec[2])
        if value == nil then return nil end
        if spec[4] == "hours" then return { math.floor(value / 3600), math.floor(spec[3] / 3600), "hours" } end
        return { math.min(value, spec[3]), spec[3] }
    elseif kind == "count" then
        local total, readable = 0, false
        for _, variable in ipairs(spec[2]) do
            local value = readNumber(variable)
            if value ~= nil then readable = true; if value >= 1 then total = total + 1 end end
        end
        return readable and { math.min(total, spec[3]), spec[3] } or nil
    elseif kind == "bits" then
        local total, readable = 0, false
        for _, pair in ipairs(spec[2]) do
            local value = readNumber(pair[1])
            if value ~= nil then readable = true; if bitSet(value, pair[2]) then total = total + 1 end end
        end
        return readable and { math.min(total, spec[3]), spec[3] } or nil
    elseif kind == "qual" then
        local level = readNumber(Cheevos.QUALIFICATION_VAR)
        return level and { math.min(level, spec[2]), spec[2], "qualification" }
    end
end

-- The tooltip of a sub achievement: what it asks for and how far along you are.
local function tipFor(part, done)
    if part.gim then
        local totals = gimTotals(part.gim)
        return part[1] .. "<br>" .. gimText(part.gim) .. (totals and (" " .. totals) or "") .. "<br>" .. (done and "Complete" or "Not complete yet")
    end
    local config = part[4]
    local spec = config and Data.SPECS[config]
    if not spec then return nil end
    local lines = { part[1] }
    local text = Data.DESCRIPTIONS[config]
    if text then lines[#lines + 1] = text end
    local got = measure(spec)
    if done then lines[#lines + 1] = "Complete"
    elseif got and got[3] == "level" then lines[#lines + 1] = "Archaeology level: " .. got[1] .. " / " .. got[2]
    elseif got and got[3] == "qualification" then lines[#lines + 1] = "Not qualified yet"
    elseif got then lines[#lines + 1] = "Progress: " .. Vars.withCommas(got[1]) .. " / " .. Vars.withCommas(got[2]) .. (got[3] and (" " .. got[3]) or "")
    else lines[#lines + 1] = "Progress is not available yet." end
    return table.concat(lines, "<br>")
end

local function achievementText(achievement)
    local found
    for _, line in ipairs(ConfigReader.Field(achievement, "descriptions") or {}) do
        local kind = ConfigReader.Field(line, "type")
        local value = text(ConfigReader.Field(line, "text"))
        if value and (found == nil or kind == 0) then found = value end
    end
    return found
end

-- The skill an achievement's text names ("... the Mining pet"), longest name first so Runecrafting isn't read as Crafting.
local skillNames
local function skillIn(...)
    if not skillNames then
        skillNames = {}
        local ok, Skills = pcall(require, "src/tracking/features/skills")
        for _, entry in ipairs(ok and Skills.SKILLS or {}) do skillNames[#skillNames + 1] = entry end
        table.sort(skillNames, function(a, b) return #a.name > #b.name end)
    end
    local haystack = table.concat({...}, " "):lower():gsub("_", " ")
    for _, entry in ipairs(skillNames) do
        if haystack:find("%f[%a]" .. entry.name:lower() .. "%f[%A]") then return entry end
    end
end

-- Fills in a pet goal's name, skill, picture and description from the game (once the game's data can be read).
resolvePet = function(entry)
    if entry.resolved or not ConfigReader.Available() then return end
    local achievement = ConfigReader.Achievement(entry.config)
    if not achievement then return end
    entry.resolved = true
    local name = text(ConfigReader.Field(achievement, "name"))
    local configName = text(ConfigReader.Field(achievement, "configName"))
    local description = achievementText(achievement)
    local skill = skillIn(name or "", description or "", configName or "")
    entry.skill = skill and skill.skill or nil
    -- "Agility - Dojo Mojo" reads as "Dojo Mojo (Agility)", like the castaways and other lists.
    local petName = PetObjects.split(name)
    entry.petName = petName
    entry.name = petName and skill and (petName .. " (" .. skill.name .. ")") or petName or skill and (skill.name .. " pet") or entry.name
    entry.description = description or entry.description
    entry.reward = text(ConfigReader.Field(achievement, "reward"))
    if entry.skill then
        entry.owed = PET_OWED[entry.skill]
        for _, objectName in ipairs({ PET_OBJECTS[entry.skill], "SKILLPETS_" .. entry.skill .. "_PET_DROP",
            "SKILLPETS_" .. entry.skill .. "_PET" }) do
            if objectId(objectName) then entry.obj = objectName break end
        end
    end
    -- The achievement's own sprite (the skill's icon) only until the pet's item is found.
    local sprite = ConfigReader.Field(achievement, "spriteID")
    if type(sprite) == "number" and sprite > 0 then entry.sprite = sprite end
end

-- The pet's own item (its model), or nil while it is still being looked for.
function Cheevos.petObject(key)
    local entry = Cheevos.isKey(key) and Cheevos.info(key)
    if not entry or not entry.pet then return nil end
    if entry.obj and objectId(entry.obj) then return objectId(entry.obj) end
    return PetObjects.find(entry.skill, entry.petName)
end

function partsOf(entry)
    local parts = {}
    for _, part in ipairs(entry.parts or {}) do
        local done = partDone(part)
        parts[#parts + 1] = { text = part[1], done = done, tip = tipFor(part, done) }
    end
    return parts
end

function build()
    if sections then return end
    sections, byKey = { [Cheevos.KILI] = {}, [Cheevos.QUALIFICATIONS] = {}, [Cheevos.RESEARCH] = {}, [Cheevos.MYSTERIES] = {}, [Cheevos.RESEARCHERS] = {},
        [Cheevos.COMBAT_PETS] = {}, [Cheevos.SKILLING_PETS] = {} }, {}
    sections[Cheevos.HOG_ENGRAMS], sections[Cheevos.HOG_EFFECTS] = {}, {}
    for n, name in ipairs(HogData.ENGRAMS) do
        add(Cheevos.HOG_ENGRAMS, { config = "hog_engram_" .. n, name = name, obj = HogData.engramObject(n), flag = HogData.engramVar(n),
            description = "Attune this engram and hand it in to the Memorial to Guthix.", doneText = "Handed in" })
    end
    for n, name in ipairs(HogData.EFFECTS) do
        local info = HogData.EFFECT_INFO[n] or {}
        add(Cheevos.HOG_EFFECTS, { config = "hog_effect_" .. n, name = name, obj = HogData.engramObject(n), flag = HogData.effectVar(n),
            description = info[1] or "A passive effect of the Fountain of Energy.", divination = info[2], doneText = "Active",
            notDoneText = "Not active", keepDone = true })
    end
    for section, rows in pairs({ [Cheevos.VARROCK_STATUE] = StatueData.VARROCK, [Cheevos.PRIF_STATUE] = StatueData.PRIFDDINAS }) do
        sections[section] = {}
        local prefix = section == Cheevos.VARROCK_STATUE and "statue_varrock_" or "statue_prif_"
        local statue = section == Cheevos.VARROCK_STATUE and "the Statue of Dahmaroc in Varrock" or "the Statue of Rhiannon in Prifddinas"
        for _, row in ipairs(rows) do
            add(section, { config = prefix .. row[1]:lower() .. (row[2] == "Melee" and "_melee" or ""), name = row[2],
                skillIcon = row[1], flag = row[3], doneText = "Added to the statue", notDoneText = "Not added yet",
                description = "Add the " .. row[2] .. " piece to " .. statue .. "." })
        end
    end
    sections[Cheevos.SCROLLS_GROUP] = {}
    for n, row in ipairs(ScrollData.SCROLLS) do
        add(Cheevos.SCROLLS_GROUP, { config = "pop_scroll_" .. n, name = row[1], sprite = row[3],
            flag = ScrollData.VAR(n) .. ">=" .. ScrollData.PIECES, pieces = ScrollData.VAR(n), doneText = "All pieces found",
            description = row[2] .. (row[4] and "" or "\n(Not part of the Scrolling in the Deep achievement.)") })
    end
    sections[Cheevos.CODEX_GROUP] = {}
    for _, row in ipairs(CodexData.MONSTERS) do
        local position = (row[2] - 1) * 32 + row[3] + 1
        add(Cheevos.CODEX_GROUP, { config = "codex_" .. position, name = row[1], obj = row[4],
            flag = CodexData.VAR_PREFIX .. row[2] .. "&" .. row[3], doneText = "Captured", notDoneText = "Not captured yet",
            description = "Capture this monster's soul in an ushabti for the Slayer Codex." })
    end
    sections[Cheevos.HOM_BOTS] = {}
    for n, bot in ipairs(HOM_BOTS) do
        add(Cheevos.HOM_BOTS, { config = "hom_bot_" .. n, name = bot[1], obj = "DIVCHAMBER_RECOVERY_BOT_" .. n,
            flag = HOM_PROGRESS_VAR .. ">=" .. (n + 1), perk = bot[2], divination = 95, doneText = "Recovered",
            notDoneText = "Not recovered yet",
            description = "Help the Archivist recover this bot's core memory data in the Hall of Memories." })
    end
    sections[Cheevos.GIM_TIERS], sections[Cheevos.GIM_TASKS] = {}, {}
    for _, tier in ipairs(GimData.TIERS) do
        local parts = {}
        for _, task in ipairs(tier.tasks) do
            parts[#parts + 1] = { task[2], nil, nil, task[1], gim = task }
            add(Cheevos.GIM_TASKS, { config = task[1], name = tier.name .. ": " .. task[2], sprite = tier.sprite, gim = task })
        end
        add(Cheevos.GIM_TIERS, { config = tier.id, name = tier.name, sprite = tier.sprite, description = tier.description,
            parts = parts, noun = "tasks" })
    end
    for section, ids in pairs({ [Cheevos.COMBAT_PETS] = COMBAT_PET_IDS, [Cheevos.SKILLING_PETS] = SKILLING_PET_IDS }) do
        for _, achievementID in ipairs(ids) do
            add(section, { config = achievementID, name = "Pet " .. achievementID, pet = true,
                description = "Get this pet." })
        end
    end
    for _, row in ipairs(Data.KILI) do
        add(Cheevos.KILI, { config = row[1], name = row[2], description = row[3], obj = row[4] })
    end
    for index, row in ipairs(Data.QUALIFICATIONS) do
        add(Cheevos.QUALIFICATIONS, { config = row[1], name = row[2], description = row[3], sprite = row[4], reward = row[5], tier = index,
            parts = row[6] and #row[6] > 0 and row[6] or nil, noun = "achievements" })
    end
    for _, site in ipairs(Data.SITES) do
        add(Cheevos.RESEARCH, { config = site.research, name = site.name, sprite = site.sprite, parts = site.researchParts,
            noun = "research", description = "Complete all of the research at " .. site.name .. "." })
        add(Cheevos.MYSTERIES, { config = site.mysteries, name = site.name, sprite = site.sprite, parts = site.mysteryParts,
            noun = "mysteries", reward = site.reward, description = "Solve all of the mysteries at " .. site.name .. "." })
    end
    add(Cheevos.RESEARCHERS, { config = Data.RESEARCHERS.config, name = Data.RESEARCHERS.name, sprite = Data.RESEARCHERS.sprite,
        parts = Data.RESEARCHERS.parts, noun = "researchers", description = "Unlock all of the researchers." })
    musicEntries, musicLive = {}, false
    addMusic()
    for _, section in ipairs({ Cheevos.TITLES_ACHIEVEMENTS, Cheevos.TITLES_REWARDS }) do sections["titles:" .. section] = {} end
    for _, row in ipairs(TitleData.ROWS) do
        local hasAchievements = #row[4] > 0
        add("titles:" .. (hasAchievements and Cheevos.TITLES_ACHIEVEMENTS or Cheevos.TITLES_REWARDS), {
            config = "title_" .. row[1], name = row[2], title = true, titleId = row[1], display = row[3], sprite = TITLE_SPRITE,
            achs = hasAchievements and row[4] or nil, flag = row[5], hideUnreadable = true,
            doneText = "Unlocked", notDoneText = "Not unlocked yet",
            description = row[6] ~= "" and row[6] or "Earn this title in the game." })
    end
end

-- A saved title's name in the game's colours (every colour, not just the first), or nil.
function Cheevos.titleNameMarkup(key)
    local entry = Cheevos.info(key)
    return entry and entry.title and titleNameMarkup(entry) or nil
end

-- The colour (RRGGBB) of the first colour tag in a saved title, or nil: the note wears it.
function Cheevos.titleColour(key)
    local entry = Cheevos.info(key)
    return entry and entry.title and titleDisplay(entry):match("<col=(%x%x%x%x%x%x)>") or nil
end

-- The name the Titles goals are kept under.
function Cheevos.titleKey(sub) return "titles:" .. tostring(sub or Cheevos.TITLES_ACHIEVEMENTS) end

-- "Prestige: 1" and the passive effects that are on, for Memorial to Guthix notes and memory strand currency notes.
function Cheevos.hogLines()
    local lines = {}
    local prestige = Vars.readEntry(Vars.resolveVar(HogData.PRESTIGE_VAR))
    if type(prestige) == "number" then lines[#lines + 1] = "Prestige: " .. prestige end
    local active, readable = {}, false
    for n, name in ipairs(HogData.EFFECTS) do
        local value = Vars.readEntry(Vars.resolveVar(HogData.effectVar(n)))
        if type(value) == "number" then
            readable = true
            if value >= 1 then active[#active + 1] = name end
        end
    end
    if readable then lines[#lines + 1] = "Active: " .. (#active > 0 and table.concat(active, ", ") or "none") end
    return #lines > 0 and table.concat(lines, "\n") or nil
end

-- The Divination level a passive effect needs, as a requirement row with the skill's icon; {} for anything else.
function Cheevos.requirements(key)
    local entry = Cheevos.info(key)
    if not entry or not entry.divination then return {} end
    local ok, Skills = pcall(require, "src/tracking/features/skills")
    local skill = ok and Skills.SKILL_BY_TYPE.DIVINATION
    if not skill then return {} end
    local have = Skills.readSkillLevel(skill)
    return { { kind = "skill", skill = skill, name = skill.name, level = entry.divination, have = have,
        met = have == nil or have >= entry.divination, icon = Skills.skillIconRef(skill) } }
end

-- True once every engram has been handed in (nil while that can't be read).
function Cheevos.hogEngramsDone()
    local all = true
    for n in ipairs(HogData.ENGRAMS) do
        local value = Vars.readEntry(Vars.resolveVar(HogData.engramVar(n)))
        if type(value) ~= "number" then return nil end
        if value < 1 then all = false end
    end
    return all
end

Cheevos.HOG_ICON_OBJECT = "HOG_MOTE"

function Cheevos.isHogCurrency(variable) return type(variable) == "string" and variable:upper() == HogData.CURRENCY_VAR end

-- The Slayer Codex monsters of a Slayer task (its SLAYER_TARGET type), each { name, captured } where captured is
-- true / false / nil (unreadable). One for most tasks, several for tasks that cover a family (gemstone dragons); nil when
-- the task has no codex monster.
local codexByName
function Cheevos.codexForTask(taskType)
    if type(taskType) ~= "number" then return nil end
    local positions = {}
    if CodexData.TASKS[taskType] then positions[1] = CodexData.TASKS[taskType]
    elseif CodexData.TASK_GROUPS[taskType] then
        if not codexByName then
            codexByName = {}
            for _, row in ipairs(CodexData.MONSTERS) do codexByName[row[1]] = (row[2] - 1) * 32 + row[3] + 1 end
        end
        for _, name in ipairs(CodexData.TASK_GROUPS[taskType]) do positions[#positions + 1] = codexByName[name] end
    end
    local list = {}
    for _, position in ipairs(positions) do
        local key = keyOf("codex_" .. position)
        local entry = Cheevos.info(key)
        if entry then list[#list + 1] = { name = entry.name, captured = Cheevos.done(key) } end
    end
    return #list > 0 and list or nil
end

-- A list that came from the game's own data is worth reading again when it was empty the first time.
function Cheevos.Clear() sections, byKey, musicEntries, musicLive = nil, nil, {}, false end

function Cheevos.info(key)
    if not Cheevos.isKey(key) then return nil end
    build()
    local entry = byKey[key]
    if entry and entry.pet then resolvePet(entry) end
    return entry
end

local function sectionList(section)
    build()
    if not musicLive then addMusic() end
    return sections[section] or {}
end

local function description(entry)
    local lines = {}
    if entry.title then
        -- A title: how it is earned, and the achievement that gives it.
        lines[1] = entry.description
        local names = {}
        for _, achievementID in ipairs(entry.achs or {}) do
            local name = ConfigReader.Field(ConfigReader.Achievement(achievementID), "name")
            if type(name) == "string" and name ~= "" then names[#names + 1] = name end
        end
        if #names > 0 then lines[2] = (#names > 1 and "Given by the achievements: " or "Given by the achievement: ") .. table.concat(names, ", ") end
        return table.concat(lines, "\n")
    end
    if entry.gim then
        local totals = gimTotals(entry.gim)
        lines[#lines + 1] = gimText(entry.gim) .. (totals and (" " .. totals) or "")
    end
    if entry.description then lines[#lines + 1] = entry.description end
    if entry.perk then lines[#lines + 1] = "Perk: " .. entry.perk end
    if entry.reward and entry.reward ~= "" then lines[#lines + 1] = "Reward: " .. (entry.reward:gsub("\\n", ", "):gsub("\n", ", ")) end
    if entry.divination then lines[#lines + 1] = "Requires level " .. entry.divination .. " Divination." end
    if entry.pet then lines[#lines + 1] = "Getting the pet completes the goal."
    elseif not entry.parts and not entry.flag and not entry.counter then lines[#lines + 1] = "Completing the achievement completes the goal." end
    return table.concat(lines, "\n")
end

-- A saved title's hover text (how it is earned), or nil for any other goal.
function Cheevos.titleDescription(key)
    local entry = Cheevos.info(key)
    return entry and entry.title and description(entry) or nil
end

-- The goals of a section that are not finished yet, as picker options.
-- The Track option for one entry.
local function optionOf(entry, rank)
    -- The item when the game has one (the tier's gear, the pet itself), else the entry's sprite, else the group's.
    local object = entry.pet and Cheevos.petObject(entry.key) or entry.obj and objectId(entry.obj) or nil
    -- Statue pieces wear their skill's icon (its cape when the icon can't be found).
    local skillSprite
    if entry.skillIcon then
        local okSkills, Skills = pcall(require, "src/tracking/features/skills")
        local icon = okSkills and Skills.skillIconRef(Skills.SKILL_BY_TYPE[entry.skillIcon])
        if type(icon) == "table" and icon.sprite then skillSprite = icon.sprite
        elseif type(icon) == "number" and icon >= 0 then object = icon end
    end
    return {
        kind = "cheevo", key = entry.key, label = entry.name, noVariable = true, defaultTarget = 1,
        rank = rank, description = description(entry), objId = object,
        preview = entry.title and titleDisplay(entry) or nil, markup = entry.title and titleDisplay(entry) or nil,
        spriteName = not object and ("#" .. (skillSprite or entry.sprite or (entry.pet and PET_SPRITE_FALLBACK or KILI_SPRITE_FALLBACK))) or nil,
    }
end

-- The option of a goal that is saved in a note even when the list leaves it out (a title that is owned by now).
function Cheevos.optionOf(key)
    local entry = Cheevos.info(key)
    return entry and optionOf(entry, 1) or nil
end

function Cheevos.options(section)
    local options = {}
    local list = sectionList(section)
    if Cheevos.isPetGroup(section) then
        local sorted = {}
        for index, entry in ipairs(list) do resolvePet(entry); sorted[index] = entry end
        table.sort(sorted, function(a, b) return tostring(a.name):lower() < tostring(b.name):lower() end)
        list = sorted
    end
    for _, entry in ipairs(list) do
        if entry.hideUnreadable and Cheevos.done(entry.key) == nil then
            -- A title whose state the game has not sent (or that this client does not know) can't be tracked: not offered.
        elseif entry.keepDone or Cheevos.done(entry.key) ~= true then
            options[#options + 1] = optionOf(entry, #options + 1)
        end
    end
    return options
end

-- "1,200 / 1,401 tracks (85%) - 201 to go": a count of everything in a list and how much of it is left.
function Cheevos.counterText(done, total, noun, complete)
    local percent = total > 0 and math.floor(done / total * 100) or 0
    return Vars.withCommas(done) .. " / " .. Vars.withCommas(total) .. " " .. (noun or "achievements") .. " (" .. percent .. "%)"
        .. (complete and " - Complete" or (" - " .. Vars.withCommas(math.max(0, total - done)) .. " to go"))
end

-- The count behind a goal that counts a whole list (Music Maestro): done, total and what is counted; nil for other goals.
function Cheevos.counter(key)
    local entry = Cheevos.info(key)
    if not entry or not entry.counter then return nil end
    local done, total = entry.counter()
    if done == nil then return nil end
    return done, total, entry.noun
end

-- Progress of one saved goal: 1 of 1 once the achievement is complete.
function Cheevos.progress(key)
    local state = Cheevos.done(key)
    if state == nil then
        return { current = nil, target = 1, fraction = 0, complete = false, owned = false, text = "Waiting for the achievement" }
    end
    local entry = Cheevos.info(key)
    -- Music Maestro: how many of all the tracks are unlocked, and how many are left.
    if entry and entry.counter then
        local done, total = entry.counter()
        done = done or 0
        local fraction = total > 0 and done / total or 0
        return { current = state and 1 or 0, target = 1, fraction = fraction, complete = state, owned = false,
            text = Cheevos.counterText(done, total, entry.noun, state) }
    end
    -- Ports scrolls: how many of the four pieces are found.
    if entry and entry.pieces then
        local found = Vars.readEntry(Vars.resolveVar(entry.pieces)) or 0
        found = math.max(0, math.min(ScrollData.PIECES, found))
        return { current = state and 1 or 0, target = 1, fraction = found / ScrollData.PIECES, complete = state, owned = false,
            text = state and entry.doneText or (found .. " / " .. ScrollData.PIECES .. " pieces found") }
    end
    if entry and entry.parts then
        local done, total = partCount(entry)
        if state and done < total then done = total end
        return { current = state and 1 or 0, target = 1, fraction = total > 0 and done / total or 0, complete = state, owned = false,
            text = done .. " / " .. total .. " " .. entry.noun
                .. " (" .. math.floor((total > 0 and done / total or 0) * 100) .. "%)" .. (state and " - Complete" or "") }
    end
    return { current = state and 1 or 0, target = 1, fraction = state and 1 or 0, complete = state, owned = false,
        text = state and (entry and entry.doneText or "Complete") or (entry and entry.notDoneText or "Not complete yet") }
end

function Cheevos.card(key)
    local entry = Cheevos.info(key)
    if not entry then return nil end
    local function safe(value) return (tostring(value):gsub("<", "["):gsub(">", "]")) end
    local state = Cheevos.done(key)
    local body = (entry.title and titleDisplay(entry) or safe(entry.name)) .. "<br>" .. (state and ("<col=55FF55>" .. (entry.doneText or "Complete") .. "</col>")
        or (entry.pieces or entry.counter) and Cheevos.progress(key).text or (entry.notDoneText or "Not complete yet"))
    if entry.divination then body = body .. "<br>Requires level " .. entry.divination .. " Divination" end
    if entry.gim then
        local totals = gimTotals(entry.gim)
        body = body .. "<br>" .. safe(gimText(entry.gim) .. (totals and (" " .. totals) or ""))
    end
    if entry.perk then body = body .. "<br><col=55FF55>Perk:</col> " .. safe(entry.perk)
    elseif entry.description then body = body .. "<br>" .. safe(entry.description) end
    if entry.reward and entry.reward ~= "" then body = body .. "<br>Reward: " .. safe((entry.reward:gsub("\\n", ", "):gsub("\n", ", "))) end
    return { key = key, body = body }
end

-- The research / mysteries of a site goal with whether each is done, for the note's sub tasks; nil for other goals.
function Cheevos.parts(key)
    local entry = Cheevos.info(key)
    if not entry or not entry.parts then return nil end
    local list = partsOf(entry)
    local complete = Cheevos.done(key) == true
    for _, part in ipairs(list) do if complete then part.done = true; if part.tip then part.tip = part.tip:gsub("<br>[^<]*$", "<br>Complete") end end end
    return #list > 0 and list or nil
end

return { Cheevos = Cheevos }
