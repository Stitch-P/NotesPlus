-- Permanent codes for the names Notes+ uses to identify what a note tracks.
-- Shared notes carry these codes instead of display names, so a name can change later without breaking old shares:
-- keep the code, change the name here. Never reuse or renumber a code.
local Registry = {}

local CATEGORIES = {
    Bossing = 1, Clues = 2, Combat = 3, Currencies = 4, Gathering = 5, Invention = 6, Ports = 7, Production = 8,
    Quests = 9, Scheduled = 10, Skills = 11, Slayer = 12, Tasks = 13, Training = 14, Unlocks = 15,
}

-- Groups that Notes+ itself defines. Groups named by the game (bosses, areas, factions...) travel as "~name".
local GROUPS = {
    ["Current task"] = 1, ["Prifddinas"] = 2, ["Menaphos journal"] = 3, ["Player Owned Farm"] = 4, ["Breeding logs"] = 5,
    ["Arc journal"] = 6, ["Archaeology"] = 7, ["Fort Forinthry"] = 8, ["Anachronia"] = 9, ["Base Camp (Buildings)"] = 10,
    ["Clues"] = 11, ["Reward Shop"] = 12, ["Necromancy"] = 13, ["Daemonheim group times"] = 14, ["Level"] = 15, ["XP"] = 16,
    ["Combat"] = 17, ["Skilling"] = 18, ["Combat Pets"] = 19, ["Skilling Pets"] = 20,
    ["Group Ironman"] = 21, ["Memorial to Guthix"] = 22, ["Hall of Memories"] = 23, ["Slayer Codex"] = 24, ["Varrock"] = 25, ["Scrolls"] = 26,
}

-- Old name -> current name, for anything renamed after notes were saved or shared.
local ALIASES = { category = {}, group = {} }

local function reverse(map)
    local result = {}
    for name, code in pairs(map) do result[code] = name end
    return result
end
local CATEGORY_NAMES, GROUP_NAMES = reverse(CATEGORIES), reverse(GROUPS)

Registry.CATEGORIES, Registry.GROUPS = CATEGORIES, GROUPS

function Registry.categoryCode(name) return CATEGORIES[name] and tostring(CATEGORIES[name]) or nil end

function Registry.categoryName(code)
    local number = type(code) == "string" and code:match("^%d+$") and tonumber(code)
    return number and CATEGORY_NAMES[number] or nil
end

-- A code for Notes+'s own groups, "~name" (percent-encoded by the caller) for the game's.
function Registry.groupCode(name) return GROUPS[name] and tostring(GROUPS[name]) or nil end

function Registry.groupName(code)
    local number = type(code) == "string" and code:match("^%d+$") and tonumber(code)
    return number and GROUP_NAMES[number] or nil
end

-- Brings a saved tracking up to the current names (a copy when something changed).
function Registry.migrate(saved)
    if type(saved) ~= "table" then return saved end
    local category, group = ALIASES.category[saved.category], ALIASES.group[saved.group]
    if not category and not group then return saved end
    local moved = {}
    for key, value in pairs(saved) do moved[key] = value end
    moved.category, moved.group = category or saved.category, group or saved.group
    if type(saved.items) == "table" then
        moved.items = {}
        for index, item in ipairs(saved.items) do
            local child = {}
            for key, value in pairs(item) do child[key] = value end
            child.category, child.group = moved.category, moved.group
            moved.items[index] = child
        end
    end
    return moved
end

return { Registry = Registry }
