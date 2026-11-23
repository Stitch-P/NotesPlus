-- The skilling pets' own items, found by name. The game names each pet's achievement "Skill - Pet" ("Agility - Dojo
-- Mojo"), and the pet's item carries the pet's name, so the item list is read a little at a time (Pump, from the main loop)
-- looking only for the names asked for. What is found is kept on disk, so the search runs once, not every session.

local PetObjects = {}

local STORE_KEY = "notes_plus_pet_objects_v1"
local PUMP_BUDGET = 300     -- items read per call
local END_GAP = 3000        -- this many unused ids in a row ends the list

local BY_SKILL = { PRAYER = "SKILLPETS_PRAYER_PET_DROP", MAGIC = "SKILLPETS_MAGIC_PET_DROP",
    SUMMONING = "SKILLPETS_SUMMONING_PET_DROP", FISHING = "SKILLPETS_FISHING" }

local found, missing, loaded = {}, {}, false   -- lower-case name -> item id / true (searched for, not there)
local wanted = {}                               -- names still to look for
local cursor, gap, scanning = 0, 0, false

local function key(name) return type(name) == "string" and name:lower():gsub("^%s+", ""):gsub("%s+$", "") or nil end

local function load()
    if loaded then return end
    loaded = true
    local ok, saved = pcall(function() return PersistentDB:GetStructuredData(STORE_KEY) end)
    if ok and type(saved) == "table" then
        for name, value in pairs(type(saved.found) == "table" and saved.found or {}) do
            if type(name) == "string" and type(value) == "number" then found[name] = value end
        end
        for name, value in pairs(type(saved.missing) == "table" and saved.missing or {}) do
            if type(name) == "string" and value == true then missing[name] = true end
        end
    end
end

local function save()
    pcall(function() PersistentDB:SetStructuredData(STORE_KEY, { found = found, missing = missing }) end)
end

local function configObject(name)
    local ok, value = pcall(function() return config.Obj[name].id end)
    return ok and type(value) == "number" and value >= 0 and value or nil
end

-- The item of a pet, or nil while it is still being looked for (or the game has none by that name).
-- skill: the skill type ("AGILITY"), name: the pet's name ("Dojo Mojo").
function PetObjects.find(skill, name)
    local byConfig = skill and BY_SKILL[skill] and configObject(BY_SKILL[skill])
    if byConfig then return byConfig end
    local wantedKey = key(name)
    if not wantedKey or wantedKey == "" then return nil end
    load()
    if found[wantedKey] then return found[wantedKey] end
    if missing[wantedKey] then return nil end
    if not wanted[wantedKey] then
        wanted[wantedKey] = true
        if not scanning then scanning, cursor, gap = true, 0, 0 end
    end
    return nil
end

-- Reads up to `budget` items, while any pet is still being looked for.
function PetObjects.Pump(budget)
    if not scanning then return end
    if type(config) ~= "table" and type(config) ~= "userdata" then return end
    budget = budget or PUMP_BUDGET
    local changed = false
    for _ = 1, budget do
        local ok, name = pcall(function()
            local item = config.Obj.FromID(cursor)
            return item and item.name
        end)
        cursor = cursor + 1
        if ok and type(name) == "string" and name ~= "" and name ~= "null" then
            gap = 0
            local nameKey = name:lower()
            if wanted[nameKey] and not found[nameKey] then
                found[nameKey], wanted[nameKey], changed = cursor - 1, nil, true
                if next(wanted) == nil then scanning = false; break end
            end
        else
            gap = gap + 1
            if gap > END_GAP then
                -- End of the list: whatever is still wanted isn't an item name.
                for nameKey in pairs(wanted) do missing[nameKey] = true end
                wanted, scanning, changed = {}, false, true
                break
            end
        end
    end
    if changed then save() end
end

-- Pet names in achievements read "Skill - Pet"; returns pet, skill (or the whole name and nil).
function PetObjects.split(achievementName)
    if type(achievementName) ~= "string" then return nil end
    local skill, pet = achievementName:match("^(.-)%s+%-%s+(.+)$")
    if skill and pet then return pet, skill end
    return achievementName, nil
end

return PetObjects
