--Sprites are nice and cool, so we should show them where we can

local Catalog = require("src/data/sprite_catalog")
local Directory = require("src/data/sprite_directory")
local objects_m = require("src/tracking/core/objects")
local findObjectID = objects_m.findObjectID

local CATEGORY_SPRITE_NAMES = {
    Bossing = "AIF_BOSS_SLAYER_POINTS_ICON_SML",
    Clues = "CLUE_SCROLL_ICON",
    Combat = "ACHIEVEMENT_ICON_COMBAT_SCORE",
    Currencies = "RS3_ICON_CURRENCY_GOLD_COINS_64PX",
    Invention = "INVENTION_ICON_THIRD_AGE_COMPONENTS",
    Ports = "AIF_POP_ANCHOR_ICON_0",
    Skills = "RS3_ICON_TAB_SKILLS",
    Quests = "ACHIEVEMENT_ICON_LORE_28PX_0",
    Tasks = "ACHIEVEMENT_ICON_ROSE_AREA_TASK",
    Training = "RS3_ICON_TAB_SKILLS",
    Unlocks = "RS3_ICON_TAB_UNLOCK",
}
-- Search words per category (all words must appear in a sprite's name/aliases).
local CATEGORY_SPRITE_QUERIES = {
    Bossing = { "reaper skull", "reaper", "skull" },
    Combat = { "combat mastery", "mastery" },
    Unlocks = { "tab unlock", "unlock" },
    Currencies = { "currency gold coins", "gold coins" },
    Invention = { "invention icon third age components", "invention" },
    Ports = { "captains log", "captain log", "captain", "ports" },
    Skills = { "skill total", "total skill", "total level", "total" },
    Quests = { "quest list", "quest point", "quests" },
    Tasks = { "area task set", "task set", "area task", "tasks" },
    Training = { "training dummy", "combat training", "training" },
}
-- Categories shown with an object icon instead (first object that exists).
local CATEGORY_OBJECTS = {
    Clues = { "TRAIL_MASTER_SCROLLBOX", "TRAIL_ELITE_SCROLLBOX", "TRAIL_CLUE_MASTER_EMOTE_SCROLLBOX" },
}
local categoryIconCache = {}
local pendingSearch = false

local function spriteByName(name)
    return Catalog.SpriteID(name)
end

local function revision()
    return Directory.Open().revision or 0
end

local function findSprite(query, predicate)
    local directory = Directory.Open()
    local sprite, name = directory:FindSprite(query, predicate)
    if not directory.spritesFinished then pendingSearch = true end
    return sprite, name
end

local function findCategorySprite(category)
    local manual = CATEGORY_SPRITE_NAMES[category]
    if manual then
        local value = spriteByName(manual)
        if value then return value, manual end
    end
    local queries = CATEGORY_SPRITE_QUERIES[category] or {}
    -- No rsprite: look through the client's own sprite names.
    for _, query in ipairs(queries) do
        local sprite, name = findSprite(query)
        if sprite then return sprite, name end
    end
    return nil
end

-- What to draw for a category: { sprite = id }, an object ID, or nil.
local function categoryIconRef(category)
    if not category then return nil end
    local cached = categoryIconCache[category]
    local currentRevision = revision()
    if cached == nil or (not cached.stable and cached.revision ~= currentRevision) then
        local icon = false
        local stable = false
        local manualSprite = CATEGORY_SPRITE_NAMES[category] and spriteByName(CATEGORY_SPRITE_NAMES[category])
        if manualSprite then
            icon, stable = { sprite = manualSprite }, true
        elseif CATEGORY_OBJECTS[category] then
            for _, name in ipairs(CATEGORY_OBJECTS[category]) do
                local objectId = findObjectID(name)
                if objectId then icon, stable = objectId, true break end
            end
        else
            local sprite = findCategorySprite(category)
            if sprite then icon = { sprite = sprite } end
        end
        cached = {icon = icon, revision = currentRevision, stable = stable or Directory.Open().spritesFinished == true}
        categoryIconCache[category] = cached
    end
    return cached.icon or nil
end

return {
    CATEGORY_SPRITE_NAMES = CATEGORY_SPRITE_NAMES,
    CATEGORY_SPRITE_QUERIES = CATEGORY_SPRITE_QUERIES,
    CATEGORY_OBJECTS = CATEGORY_OBJECTS,
    findSprite = findSprite,
    spriteByName = spriteByName,
    revision = revision,
    categoryIconRef = categoryIconRef,
    poll = function()
        if not pendingSearch then return end
        local directory = Directory.Open()
        directory:DiscoverSprites()
        pendingSearch = not directory.spritesFinished
    end,
    reset = function()
        categoryIconCache, pendingSearch = {}, false
    end,
}
