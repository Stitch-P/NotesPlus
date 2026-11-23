-- Boss timers: your fastest kill time for each boss, read from the BOSS_INSTANCE_SCORES_<boss> variables.
-- A value counts game ticks (0.6 seconds each) and is 0 until the boss has been beaten. A goal is a time to beat:
-- it is complete once your best time is at or under the target. Targets are saved in ticks.

local Vars = require("src/tracking/core/vars")

local Timers = {}

Timers.PREFIX = "BOSS_INSTANCE_SCORES_"
local TICK = 0.6

-- { boss group name (for its icon), label, variable suffix }
local BOSSES = {
    { "Amascut", "Amascut", "AMASCUT_BOSS" }, { "Amascut", "Amascut (hard mode)", "AMASCUT_BOSS_HARD" },
    { "Araxxi", "Araxxi", "ARAXXI" },
    { "Commander Zilyana", "Commander Zilyana", "ZILYANA" }, { "Commander Zilyana", "Commander Zilyana (hard mode)", "ZILYANA_HARD" },
    { "General Graardor", "General Graardor", "GRAARDOR" }, { "General Graardor", "General Graardor (hard mode)", "GRAARDOR_HARD" },
    { "K'ril Tsutsaroth", "K'ril Tsutsaroth", "KRIL" }, { "K'ril Tsutsaroth", "K'ril Tsutsaroth (hard mode)", "KRIL_HARD" },
    { "Kree'arra", "Kree'arra", "KREEARRA" }, { "Kree'arra", "Kree'arra (hard mode)", "KREEARRA_HARD" },
    { "Corporeal Beast", "Corporeal Beast", "CORP_BEAST" },
    { "Kalphite King", "Kalphite King", "KK" },
    { "Kalphite Queen", "Kalphite Queen", "KQ" },
    { "King Black Dragon", "King Black Dragon", "KBD" },
    { "Queen Black Dragon", "Queen Black Dragon", "QBD" },
    { "Giant Mole", "Giant Mole", "MOLE" }, { "Giant Mole", "Giant Mole (hard mode)", "MOLE_HARD" },
    { "Vorago", "Vorago", "VORAGO" }, { "Vorago", "Vorago (hard mode)", "VORAGO_HARD" },
    { "Nex", "Nex", "NEX" },
    { "Nex: Angel of Death", "Nex: Angel of Death", "NEX2" },
    { "Telos", "Telos", "TELOS" },
    { "Solak", "Solak", "SOLAK" }, { "Solak", "Solak (duo)", "SOLAK_DUO" },
    { "Vindicta", "Vindicta", "VINDICTA" }, { "Vindicta", "Vindicta (hard mode)", "VINDICTA_HARD" },
    { "Gregorovic", "Gregorovic", "SLISKE" }, { "Gregorovic", "Gregorovic (hard mode)", "SLISKE_HARD" },
    { "Helwyr", "Helwyr", "HELWYR" }, { "Helwyr", "Helwyr (hard mode)", "HELWYR_HARD" },
    { "Twin Furies", "Twin Furies", "TWINDEMONS" }, { "Twin Furies", "Twin Furies (hard mode)", "TWINDEMONS_HARD" },
    { "Legiones", "Legiones", "LEGIONES" },
    { "Zuk", "Zuk", "EGWD_FUL_BOSS" }, { "Zuk", "Zuk (hard mode)", "EGWD_FUL_BOSS_HARD" },
    { "Kerapac", "Kerapac", "EGWD_JAS_BOSS" }, { "Kerapac", "Kerapac (hard mode)", "EGWD_JAS_BOSS_HARD" },
    { "Croseus", "Croseus", "EGWD_BIK_BOSS" },
    { "Zamorak", "Zamorak", "EGWD_ZAMORAK_BOSS" }, { "Zamorak", "Zamorak (hard mode)", "EGWD_ZAMORAK_BOSS_HARD" },
    { "Arch-Glacor", "Arch-Glacor", "EGWD_WEN_BOSS" }, { "Arch-Glacor", "Arch-Glacor (hard mode)", "EGWD_WEN_BOSS_HARD" },
    { "Hermod", "Hermod", "HERMOD_BOSS" },
    { "Elidinis", "Elidinis", "ELIDINIS_BOSS" },
    { "Rasial", "Rasial", "RASIAL_BOSS" },
    { "Vorkath", "Vorkath", "FORT_BOSS_ZEMO_VORKATH" }, { "Vorkath", "Vorkath (hard mode)", "FORT_BOSS_ZEMO_VORKATH_HARD" },
    { "Raksha", "Raksha (solo)", "DINO_BOSS_SOLO" }, { "Raksha", "Raksha (duo)", "DINO_BOSS_DUO" },
    { "Magister", "Magister", "MENAPHOS_SLAYER_BOSS" },
    { "Flesh-hatcher Mhekarnahz", "Flesh-hatcher Mhekarnahz", "STALKER_BOSS" },
    { "Ivar, King of Bones", "Ivar, King of Bones", "WENDLE_GIANT_BOSS" },
    { "Silverquill", "Silverquill", "WENDLE_HEDGEHOG_BOSS" },
    { "TzHaar", "TzHaar-Ket-Rak (Jad)", "JAD" }, { "TzHaar", "Har-Aken", "HARAKEN" },
    { "Mazcab", "Beastmaster Durzag", "BEASTMASTER" }, { "Mazcab", "Yakamaru", "YAKAMARU" },
    { "Rise of the Six", "Rise of the Six", "ROTS" },
    { "Temple of Aminishi", "Temple of Aminishi: Boss 1", "AMINISHI1" }, { "Temple of Aminishi", "Temple of Aminishi: Boss 2", "AMINISHI2" },
    { "Temple of Aminishi", "Temple of Aminishi: Boss 3", "AMINISHI3" },
    { "Temple of Aminishi", "Temple of Aminishi: Boss 1 (hard mode)", "AMINISHI1_HARD" },
    { "Temple of Aminishi", "Temple of Aminishi: Boss 2 (hard mode)", "AMINISHI2_HARD" },
    { "Temple of Aminishi", "Temple of Aminishi: Boss 3 (hard mode)", "AMINISHI3_HARD" },
    { "Dragonkin Laboratory", "Dragonkin Laboratory: Boss 1", "DRAGONFORT1" }, { "Dragonkin Laboratory", "Dragonkin Laboratory: Boss 2", "DRAGONFORT2" },
    { "Dragonkin Laboratory", "Dragonkin Laboratory: Boss 3", "DRAGONFORT3" },
    { "Dragonkin Laboratory", "Dragonkin Laboratory: Boss 1 (hard mode)", "DRAGONFORT1_HARD" },
    { "Dragonkin Laboratory", "Dragonkin Laboratory: Boss 2 (hard mode)", "DRAGONFORT2_HARD" },
    { "Dragonkin Laboratory", "Dragonkin Laboratory: Boss 3 (hard mode)", "DRAGONFORT3_HARD" },
    { "The Shadow Reef", "The Shadow Reef: Boss 1", "ULTHVEN1" }, { "The Shadow Reef", "The Shadow Reef: Boss 2", "ULTHVEN2" },
    { "The Shadow Reef", "The Shadow Reef: Boss 3", "ULTHVEN3" },
    { "The Shadow Reef", "The Shadow Reef: Boss 1 (hard mode)", "ULTHVEN1_HARD" },
    { "The Shadow Reef", "The Shadow Reef: Boss 2 (hard mode)", "ULTHVEN2_HARD" },
    { "The Shadow Reef", "The Shadow Reef: Boss 3 (hard mode)", "ULTHVEN3_HARD" },
    { "Sanctum of Rebirth", "Sanctum of Rebirth: Wyrm", "RAID_REBIRTH1_WYRM_BOSS" },
    { "Sanctum of Rebirth", "Sanctum of Rebirth: Beast", "RAID_REBIRTH1_BEAST_BOSS" },
    { "Sanctum of Rebirth", "Sanctum of Rebirth: Slayer master", "RAID_REBIRTH1_SLAYER_MASTER_BOSS" },
    { "Sanctum of Rebirth", "Sanctum of Rebirth: Wyrm (hard mode)", "RAID_REBIRTH1_WYRM_BOSS_HARD" },
    { "Sanctum of Rebirth", "Sanctum of Rebirth: Beast (hard mode)", "RAID_REBIRTH1_BEAST_BOSS_HARD" },
    { "Sanctum of Rebirth", "Sanctum of Rebirth: Slayer master (hard mode)", "RAID_REBIRTH1_SLAYER_MASTER_BOSS_HARD" },
    { "Heist", "Heist: Kharidet", "HEIST_KHARIDET" }, { "Heist", "Heist: Dragonkin", "HEIST_DRAGONKIN" },
}

local byVar = {}
for _, row in ipairs(BOSSES) do byVar[Timers.PREFIX .. row[3]] = row end

-- Daemonheim: your fastest time per theme, solo and in a group. These are kept as whole seconds (minutes and seconds
-- are stored in their own variables), so their times are in seconds rather than ticks.
Timers.SOLO = "Daemonheim solo times"
Timers.GROUP = "Daemonheim group times"
local DG_MODES = { [Timers.SOLO] = "SOLO", [Timers.GROUP] = "GROUP" }
local DG_THEMES = {
    { "FROZEN", "Frozen", "floors 1 to 11" }, { "ABANDONED_1", "Abandoned 1", "floors 12 to 17" },
    { "FURNISHED", "Furnished", "floors 18 to 29" }, { "ABANDONED_2", "Abandoned 2", "floors 30 to 35" },
    { "OCCULT", "Occult", "floors 36 to 47" }, { "WARPED", "Warped", "floors 48 to 60" },
    { "SPEEDRUN", "Speedrun", "all floors" },
}
local dgVars = {}
for _, mode in pairs(DG_MODES) do
    for _, theme in ipairs(DG_THEMES) do dgVars["RAND_" .. theme[1] .. "_" .. mode .. "_FASTEST_TIME"] = true end
end

function Timers.isGroup(name) return DG_MODES[name] ~= nil end
function Timers.isDG(name) return type(name) == "string" and dgVars[name] == true end
-- Any BOSS_INSTANCE_SCORES_<boss> variable holds a time in ticks (their _MINUTES / _SECONDS companions do not), so a boss
-- found through the game's own data (see liveRows) is read and shown like the listed ones.
function Timers.isVar(name)
    if type(name) ~= "string" then return false end
    if byVar[name] ~= nil or dgVars[name] == true then return true end
    return name:sub(1, #Timers.PREFIX) == Timers.PREFIX and not name:find("_MINUTES$") and not name:find("_SECONDS$")
end
function Timers.rowOf(name) return byVar[name] end
-- Seconds in one unit of a variable's value: a game tick for bosses, a second for Daemonheim.
local function unit(name) return dgVars[name] and 1 or TICK end

function Timers.dgGroups() return { { name = Timers.SOLO }, { name = Timers.GROUP } } end

function Timers.dgOptions(groupName)
    local mode = DG_MODES[groupName]
    local options = {}
    if not mode then return options end
    for _, theme in ipairs(DG_THEMES) do
        local name = "RAND_" .. theme[1] .. "_" .. mode .. "_FASTEST_TIME"
        options[#options + 1] = {
            label = theme[2] .. " (" .. theme[3] .. ")", kind = "timer", varName = name, key = name, rank = #options + 1,
            description = "Your fastest " .. (mode == "SOLO" and "solo" or "group") .. " time. Set a time to beat: it completes once your best is at or under it.",
        }
    end
    return options
end

-- Your best time for a Daemonheim variable in seconds (from its minutes and seconds variables), 0 when none yet, nil if unreadable.
-- read(name) returns a variable's number or nil.
function Timers.readDG(name, read)
    local minutes, seconds = read(name .. "_MINUTES"), read(name .. "_SECONDS")
    if minutes ~= nil and seconds ~= nil then return minutes * 60 + seconds end
    return read(name)
end

-- 6.6s, 1:05.4, 1:02:03.0
function Timers.format(ticks, variable)
    if type(ticks) ~= "number" or ticks <= 0 then return "--" end
    if variable and dgVars[variable] then
        local total = math.floor(ticks + 0.5)
        local hours, minutes, rest = math.floor(total / 3600), math.floor(total % 3600 / 60), total % 60
        if hours > 0 then return string.format("%d:%02d:%02d", hours, minutes, rest) end
        if minutes > 0 then return string.format("%d:%02d", minutes, rest) end
        return rest .. "s"
    end
    local seconds = ticks * TICK
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds - hours * 3600) / 60)
    local rest = seconds - hours * 3600 - minutes * 60
    if hours > 0 then return string.format("%d:%02d:%04.1f", hours, minutes, rest) end
    if minutes > 0 then return string.format("%d:%04.1f", minutes, rest) end
    return string.format("%.1fs", rest)
end

-- "6.6", "6.6s", "1:05.4", "1:02:03" to ticks (rounded up to a whole tick), or nil.
function Timers.parse(text, variable)
    text = Vars.trim(text):lower():gsub("s$", "")
    if text == "" then return nil end
    local seconds = 0
    local parts = {}
    for piece in (text .. ":"):gmatch("([^:]*):") do parts[#parts + 1] = piece end
    if #parts > 3 then return nil end
    for _, piece in ipairs(parts) do
        local value = tonumber(piece)
        if not value or value < 0 then return nil end
        seconds = seconds * 60 + value
    end
    if seconds <= 0 then return nil end
    return math.max(1, math.ceil(seconds / unit(variable) - 1e-6))
end

-- "Boss timer", "Boss timer (hard mode)", "Boss timer: Boss 1 (hard mode)"...
local function optionLabel(row)
    local group, label = row[1], row[2]
    if label == group then return "Boss timer" end
    if label:sub(1, #group) == group then return "Boss timer" .. label:sub(#group + 1) end
    return "Boss timer: " .. label
end

-- Bosses the game has added since the list above. A boss's timer variable is usually named like its kill count variable
-- (BSLAY_KILLS_<X> and BOSS_INSTANCE_SCORES_<X>), with _HARD, _DUO or _SOLO on the end for the other modes, so each kill
-- count's name is tried that way. Only variables the game really has are offered, and the listed ones are never repeated.
local VARIANTS = { { "", "" }, { "_HARD", " (hard mode)" }, { "_DUO", " (duo)" }, { "_SOLO", " (solo)" } }

local function liveRows(kills)
    local rows, seen = {}, {}
    for _, kill in ipairs(kills or {}) do
        local base = type(kill) == "table" and type(kill[2]) == "string" and kill[2]:upper() or nil
        if base then
            base = base:gsub("_HARD$", ""):gsub("_DUO$", ""):gsub("_SOLO$", "")
            for _, variant in ipairs(VARIANTS) do
                local suffix = base .. variant[1]
                if not seen[suffix] and not byVar[Timers.PREFIX .. suffix] and Vars.resolveVar(Timers.PREFIX .. suffix) then
                    seen[suffix] = true
                    rows[#rows + 1] = { suffix = suffix, mode = variant[2] }
                end
            end
        end
    end
    return rows
end

local function timerOption(name, label)
    return {
        label = label, kind = "timer", varName = name, key = name,
        description = "Your fastest kill time. Set a time to beat: it completes once your best is at or under it.",
    }
end

-- The timer options of one boss (by its Bossing group name), for the "track" list next to its kill counts. kills is the
-- boss's kill count list from the Bossing feature, used to find the timers of bosses the list above does not know yet.
function Timers.optionsFor(groupName, kills)
    local options = {}
    for _, row in ipairs(BOSSES) do
        local name = Timers.PREFIX .. row[3]
        if row[1] == groupName and Vars.resolveVar(name) then options[#options + 1] = timerOption(name, optionLabel(row)) end
    end
    for _, row in ipairs(liveRows(kills)) do
        options[#options + 1] = timerOption(Timers.PREFIX .. row.suffix, "Boss timer" .. row.mode)
    end
    return options
end

return Timers
