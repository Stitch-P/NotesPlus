local Sprites = require("src/data/sprite_catalog")
local Tracking = require("src/tracking/model")

local Appearance = {}
local categories = {"Bossing", "Clues", "Combat", "Currencies", "Gathering", "Invention", "Ports", "Production", "Quests", "Skills", "Slayer", "Tasks", "Training", "Unlocks"}

function Appearance.Icon(category)
    if not category then return nil end
    -- An empty sprite means "no custom sprite", so a built-in name can still supply its own icon.
    if category.skill ~= nil and category.skill ~= "" then
        local choice = Sprites.Get(category.skill)
        if not choice then return nil end
        return choice.objectID or {sprite = Sprites.SpriteID(choice.name)}
    end
    local name = tostring(category.name or ""):lower()
    if name == "scheduled" then return {sprite = id.Sprite.SEPT16_ICON_CALENDAR_1} end
    for _, builtin in ipairs(categories) do
        if name == builtin:lower() then return Tracking.CategoryIcon(builtin) end
    end
end

function Appearance.Apply(sprite, category)
    Sprites.Clear(sprite)
    local icon = Appearance.Icon(category)
    if not icon then return false end
    if type(icon) == "table" then
        sprite.spriteID = icon.sprite
    else
        sprite:SetAssociatedObject(icon)
        sprite.associatedObjectQuantity = 1
        sprite.associatedObjectQuantityMode = ui.ObjectQuantityDisplayMode.NEVER
    end
    sprite.hidden = false
    return true
end

function Appearance.Color(category, fallback)
    local color = category and category.color
    if type(color) == "string" and color:match("^%x%x%x%x%x%x$") then
        return tonumber(color, 16) * 256 + 255
    end
    return fallback
end

return Appearance