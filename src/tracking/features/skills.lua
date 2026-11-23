-- Skill levels and skill icons.

local sprites_m = require("src/tracking/core/sprites")
local Experience = require("src/tracking/data/skill_experience")
local spriteByName, findSprite = sprites_m.spriteByName, sprites_m.findSprite

-- Alphabetical ordering of the skills (we have the cape objects here if for whatever reason we can't find the sprites)
local SKILLS = {
    { name = "Agility", skill = "AGILITY", cape = id.Obj.SKILLCAPE_AGILITY },
    { name = "Archaeology", skill = "ARCHAEOLOGY", cape = id.Obj.SKILLCAPE_ARCHAEOLOGY },
    { name = "Attack", skill = "ATTACK", cape = id.Obj.SKILLCAPE_ATTACK },
    { name = "Constitution", skill = "HITPOINTS", cape = id.Obj.SKILLCAPE_HITPOINTS },
    { name = "Construction", skill = "CONSTRUCTION", cape = id.Obj.SKILLCAPE_CONSTRUCTION },
    { name = "Cooking", skill = "COOKING", cape = id.Obj.SKILLCAPE_COOKING },
    { name = "Crafting", skill = "CRAFTING", cape = id.Obj.SKILLCAPE_CRAFTING },
    { name = "Defence", skill = "DEFENCE", cape = id.Obj.SKILLCAPE_DEFENCE },
    { name = "Divination", skill = "DIVINATION", cape = id.Obj.SKILLCAPE_DIVINATION },
    { name = "Dungeoneering", skill = "DUNGEONEERING", cape = id.Obj.SKILLCAPE_DUNGEONEERING },
    { name = "Farming", skill = "FARMING", cape = id.Obj.SKILLCAPE_FARMING },
    { name = "Firemaking", skill = "FIREMAKING", cape = id.Obj.SKILLCAPE_FIREMAKING },
    { name = "Fishing", skill = "FISHING", cape = id.Obj.SKILLCAPE_FISHING },
    { name = "Fletching", skill = "FLETCHING", cape = id.Obj.SKILLCAPE_FLETCHING },
    { name = "Herblore", skill = "HERBLORE", cape = id.Obj.SKILLCAPE_HERBLORE },
    { name = "Hunter", skill = "HUNTER", cape = id.Obj.SKILLCAPE_HUNTING },
    { name = "Invention", skill = "INVENTION", cape = id.Obj.SKILLCAPE_INVENTION },
    { name = "Magic", skill = "MAGIC", cape = id.Obj.SKILLCAPE_MAGIC },
    { name = "Mining", skill = "MINING", cape = id.Obj.SKILLCAPE_MINING },
    { name = "Necromancy", skill = "NECROMANCY", cape = id.Obj.SKILLCAPE_NECROMANCY },
    { name = "Prayer", skill = "PRAYER", cape = id.Obj.SKILLCAPE_PRAYER },
    { name = "Ranged", skill = "RANGED", cape = id.Obj.SKILLCAPE_RANGING },
    { name = "Runecrafting", skill = "RUNECRAFTING", cape = id.Obj.SKILLCAPE_RUNECRAFTING },
    { name = "Slayer", skill = "SLAYER", cape = id.Obj.SKILLCAPE_SLAYER },
    { name = "Smithing", skill = "SMITHING", cape = id.Obj.SKILLCAPE_SMITHING },
    { name = "Strength", skill = "STRENGTH", cape = id.Obj.SKILLCAPE_STRENGTH },
    { name = "Summoning", skill = "SUMMONING", cape = id.Obj.SKILLCAPE_SUMMONING },
    { name = "Thieving", skill = "THIEVING", cape = id.Obj.SKILLCAPE_THIEVING },
    { name = "Woodcutting", skill = "WOODCUTTING", cape = id.Obj.SKILLCAPE_WOODCUTTING },
}
local SKILL_BY_TYPE = {}
for _, entry in ipairs(SKILLS) do SKILL_BY_TYPE[entry.skill] = entry end

local SKILL_SPRITE_NAMES = {}
local SKILL_SPRITE_TOKENS = {
    HITPOINTS = { "HITPOINTS", "CONSTITUTION" },
    RANGED = { "RANGED", "RANGING", "RANGE" },
    HUNTER = { "HUNTER", "HUNTING" },
}
local SKILL_SPRITE_BAD = { "CAPE", "HOOD", "BTN", "BUTTON", "OVR", "HOVER", "MINIMAP", "CHAT", "LEVELUP", "LEVEL_UP", "GUIDE", "MENU", "BAR", "PET", "LOOT", "TOOLTIP" }
local skillSpriteCache = {}

local function readSkillXP(entry)
    if not entry then return nil end
    local ok, xp = pcall(function()
        return Player.GetXPUncapped(SkillType[entry.skill])
    end)
    if ok and type(xp) == "number" and xp == xp and xp >= 0 and xp < math.huge then return xp end
    return nil
end

local function readSkillLevel(entry)
    return Experience.Level(entry and entry.skill, readSkillXP(entry))
end

local function findSkillSprite(entry)
    local manual = SKILL_SPRITE_NAMES[entry.skill]
    if manual then
        local value = spriteByName(manual)
        if value then return value, manual, nil, true end
    end
    do
        local tokens = SKILL_SPRITE_TOKENS[entry.skill] or { entry.skill }
        local names = {}
        for _, token in ipairs(tokens) do names[#names + 1] = token end
        names[#names + 1] = entry.name:upper()
        local patterns = { { "HITMARK_ICON_SKILL_%s", nil }, { "SKILL_ICON_%s_24PX", 24 } }
        for _, pattern in ipairs(patterns) do
            for _, token in ipairs(names) do
                local name = pattern[1]:format(token)
                local value = spriteByName(name)
                if value then return value, name, pattern[2], true end
            end
        end
    end
    do
        local tokens = SKILL_SPRITE_TOKENS[entry.skill] or { entry.skill }
        local names = {}
        for _, token in ipairs(tokens) do names[#names + 1] = "SKILL_" .. token end
        names[#names + 1] = "SKILL_" .. entry.name:upper()
        for _, name in ipairs(names) do
            local value = spriteByName(name)
            if value then return value, name, nil, true end
        end
    end
    local tokens = SKILL_SPRITE_TOKENS[entry.skill] or { entry.skill }
    local function suitable(record)
        local name = record.name
        local padded = "_" .. name .. "_"
        local hasToken = false
        for _, token in ipairs(tokens) do
            if padded:find("_" .. token .. "_", 1, true) then hasToken = true break end
        end
        if hasToken and (name:find("STAT", 1, true) or name:find("SKILL", 1, true)) then
            local bad = false
            for _, word in ipairs(SKILL_SPRITE_BAD) do
                if name:find(word, 1, true) then bad = true break end
            end
            return not bad
        end
        return false
    end
    for _, token in ipairs(tokens) do
        local sprite, name = findSprite(token, suitable)
        if sprite then return sprite, name end
    end
    return nil
end

local function skillIconRef(entry)
    if not entry then return nil end
    local cached = skillSpriteCache[entry.skill]
    local currentRevision = sprites_m.revision()
    if cached == nil or (not cached.stable and cached.revision ~= currentRevision) then
        local sprite, _, fixedSize, stable = findSkillSprite(entry)
        local icon
        if sprite then
            icon = { sprite = sprite, size = fixedSize }
        else
            icon = entry.cape or false
        end
        cached = {icon = icon, revision = currentRevision, stable = stable == true}
        skillSpriteCache[entry.skill] = cached
    end
    return cached.icon or nil
end

return {
    SKILLS = SKILLS,
    SKILL_BY_TYPE = SKILL_BY_TYPE,
    MaxLevel = Experience.MaxLevel,
    readSkillLevel = readSkillLevel,
    readSkillXP = readSkillXP,
    skillIconRef = skillIconRef,
    resetIcons = function() skillSpriteCache = {} end,
}
