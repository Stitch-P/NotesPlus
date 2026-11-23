local Sprites = {}
Sprites.MAX_NAME_LENGTH = 256

local entries = {}
local ITEM_PREFIX = "item/"

local function validID(value)
    return type(value) == "number" and value >= 0 and value % 1 == 0
end

local function validName(name)
    return type(name) == "string" and name:match("^[A-Z0-9_]+$") ~= nil
end

function Sprites.IsBlocked(name)
    return name == "FLOORSHADOWS"
end

function Sprites.SpriteID(name)
    if not validName(name) or #name > Sprites.MAX_NAME_LENGTH or Sprites.IsBlocked(name) then return nil end
    local ok, value = pcall(function() return id.Sprite[name] end)
    return ok and validID(value) and value or nil
end

function Sprites.Valid(name)
    return name == "" or Sprites.Get(name) ~= nil
end

local function displayName(item)
    if item == nil or type(item.name) ~= "string" then return nil end
    local label = item.name:gsub("<[^>]*>", ""):gsub("[%c]", " "):match("^%s*(.-)%s*$")
    if label == "" or label:lower() == "null" then return nil end
    return label
end

function Sprites.Item(number, name)
    if not validID(number) or not validName(name) or #name + #ITEM_PREFIX > Sprites.MAX_NAME_LENGTH then return nil end
    local mapped, objectID = pcall(function() return id.Obj[name] end)
    if not mapped or objectID ~= number then return nil end
    local ok, label = pcall(function() return displayName(config.Obj.FromID(number)) end)
    if not ok or not label then label = name end
    return {name = ITEM_PREFIX .. name, label = label, objectID = number}
end

function Sprites.ConfigName(choice)
    return choice.objectID and choice.name:sub(#ITEM_PREFIX + 1) or choice.name
end

-- What the Choose Sprite window shows for a choice: just its name (the game's internal sprite / item name still works
-- in the search box).
function Sprites.Description(choice)
    return choice.label
end

function Sprites.Get(name)
    if type(name) ~= "string" or #name > Sprites.MAX_NAME_LENGTH then return nil end
    local itemName = name:match("^item/([A-Z0-9_]+)$")
    if not itemName and (not validName(name) or Sprites.IsBlocked(name)) then return nil end
    if entries[name] ~= nil then return entries[name] end
    if itemName then
        local ok, choice = pcall(function() return Sprites.Item(id.Obj[itemName], itemName) end)
        if not ok or choice == nil then return nil end
        entries[name] = choice
        return choice
    end
    local value = Sprites.SpriteID(name)
    if value == nil then return nil end
    local choice = {name = name, label = name:gsub("_", " "):lower()}
    entries[name] = choice
    return choice
end

function Sprites.Apply(component, name)
    local choice = Sprites.Get(name)
    if choice == nil then return false end
    local ok = pcall(function()
        if choice.objectID then
            component:SetAssociatedObject(choice.objectID)
            component.associatedObjectQuantity = 1
            component.associatedObjectQuantityMode = ui.ObjectQuantityDisplayMode.NEVER
        else
            component.spriteID = id.Sprite[choice.name]
        end
    end)
    return ok
end

function Sprites.Clear(component)
    component.hidden = true
    component.associatedObjectID = -1
    component.spriteID = -1
end

function Sprites.Reset()
    entries = {}
end

return Sprites
