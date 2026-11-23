local field = require("src/core/safe_values").Field
local ActionBar = {}

ActionBar.SLOT_COUNT = 14
ActionBar.MAX_NAME = 120
ActionBar.MAX_LABEL = 300
ActionBar.MAX_TOKEN_LENGTH = 256

local MAX_INTEGER = 2147483647
local prefixes = {
    "TOPLEVEL_V2_COMBAT_BAR", "TOPLEVEL_V2_COMBAT_BAR2", "TOPLEVEL_V2_COMBAT_BAR3",
    "TOPLEVEL_V2_COMBAT_BAR4", "TOPLEVEL_V2_COMBAT_BAR5"
}
local barKeys = {preset = true, name = true, slots = true}
local slotKeys = {type = true, action = true, object = true, sprite = true, label = true}

local function integer(value, minimum, maximum)
    return type(value) == "number" and value == value and value % 1 == 0
        and value >= minimum and value <= maximum
end

local function token(value)
    return type(value) == "string" and #value > 0 and #value <= ActionBar.MAX_TOKEN_LENGTH
        and value:match("^[A-Z0-9_]+$") ~= nil
end

local function text(value, maximum)
    return type(value) == "string" and #value <= maximum and not value:find("[%c]")
end

local function optional(value)
    if value == "" then return nil end
    return value
end

local function plain(value, maximum)
    if type(value) ~= "string" then return nil end
    value = value:gsub("<[^>]*>", ""):gsub("[%c]", " "):match("^%s*(.-)%s*$")
    if value == "" or #value > maximum then return nil end
    return value
end

local function namedID(namespace, name)
    local value = field(field(id, namespace), name)
    return integer(value, 0, MAX_INTEGER) and value or nil
end

local function nativeName(namespace, value)
    if not integer(value, 0, MAX_INTEGER) then return nil end
    local lookup = field(field(id, namespace), "FromID")
    if lookup == nil then return nil end
    local ok, name = pcall(function() return lookup(value) end)
    return ok and token(name) and namedID(namespace, name) == value and name or nil
end

local function object(value)
    local lookup = field(field(config, "Obj"), "FromID")
    if lookup == nil then return nil end
    local ok, result = pcall(function() return lookup(value) end)
    return ok and field(result, "id") == value and result or nil
end

function ActionBar.Normalize(saved)
    if saved == nil then return nil end
    local message = "Choose a valid action bar setup."
    if type(saved) ~= "table" then return nil, message end
    for key in pairs(saved) do if not barKeys[key] then return nil, message end end
    if not integer(saved.preset, 1, 18) or not text(saved.name, ActionBar.MAX_NAME)
        or type(saved.slots) ~= "table" then return nil, message end
    for key in pairs(saved.slots) do
        if not integer(key, 1, ActionBar.SLOT_COUNT) then return nil, message end
    end
    local copy = {preset = saved.preset, name = saved.name, slots = {}}
    for index = 1, ActionBar.SLOT_COUNT do
        local slot = saved.slots[index]
        if type(slot) ~= "table" then return nil, "An action bar must contain all 14 slots." end
        for key in pairs(slot) do if not slotKeys[key] then return nil, message end end
        if next(slot) == nil then
            copy.slots[index] = {}
        else
            local objectName = optional(slot.object)
            local spriteName = optional(slot.sprite)
            local label = optional(slot.label)
            if not integer(slot.type, 0, MAX_INTEGER) or not integer(slot.action, 0, MAX_INTEGER)
                or (objectName ~= nil and not token(objectName))
                or (spriteName ~= nil and not token(spriteName))
                or (objectName == nil) == (spriteName == nil)
                or (label ~= nil and not text(label, ActionBar.MAX_LABEL)) then return nil, message end
            copy.slots[index] = {type = slot.type, action = slot.action,
                object = objectName, sprite = spriteName, label = label}
        end
    end
    return copy
end

function ActionBar.Count(bar)
    if type(bar) ~= "table" or type(bar.slots) ~= "table" then return 0 end
    local count = 0
    for index = 1, ActionBar.SLOT_COUNT do
        local slot = bar.slots[index]
        if type(slot) == "table" and (token(slot.object) or token(slot.sprite)) then count = count + 1 end
    end
    return count
end

function ActionBar.Icon(slot)
    if type(slot) ~= "table" then return nil end
    if token(slot.object) then return namedID("Obj", slot.object) end
    local sprite = token(slot.sprite) and namedID("Sprite", slot.sprite) or nil
    return sprite and {sprite = sprite} or nil
end

function ActionBar.Label(slot)
    if type(slot) ~= "table" then return "Empty slot" end
    local label = plain(slot.label, ActionBar.MAX_LABEL)
    if label then return label end
    if token(slot.object) then
        local value = namedID("Obj", slot.object)
        label = value and plain(field(object(value), "name"), ActionBar.MAX_LABEL) or nil
        if label then return label end
    end
    local name = token(slot.object) and slot.object or token(slot.sprite) and slot.sprite or nil
    return name and name:gsub("_", " "):lower():gsub("^%l", string.upper) or "Empty slot"
end

function ActionBar.Presets()
    local result = {}
    for index = 1, 18 do result[index] = {id = index, label = "Action bar " .. index} end
    return result
end

local function component(name)
    local componentID = namedID("Component", name)
    local interfaces = field(ui, "Interfaces")
    local lookup = field(interfaces, "GetComponent")
    if not componentID or lookup == nil then return nil end
    local ok, result = pcall(function() return lookup(interfaces, componentID) end)
    return ok and result or nil
end

local function shownPreset(prefix)
    local value = component(prefix .. "__FULLSCREEN_ARROW_TEXT")
    if value == nil or field(value, "visibleGlobal", "visible") == false then return nil end
    local content = plain(field(value, "content"), ActionBar.MAX_NAME)
    return content and tonumber(content:match("^%d+$")) or nil
end

local function readVariables(preset)
    local result = {}
    local variables = field(var, "VarPlayer")
    for index = 1, ActionBar.SLOT_COUNT do
        local prefix = "ACTIONBAR" .. preset .. "_"
        local kind = field(field(variables, prefix .. "INT" .. index .. "_TYPE"), "value")
        local action = field(field(variables, prefix .. "INT" .. index .. "_ID"), "value")
        local item = field(field(variables, prefix .. "OBJ" .. index), "value")
        if type(item) == "table" or type(item) == "userdata" then item = field(item, "id") end
        if not integer(kind, -1, MAX_INTEGER) or not integer(action, -1, MAX_INTEGER)
            or not integer(item, -1, MAX_INTEGER) then return nil end
        result[index] = {type = kind, action = action, object = item}
    end
    return result
end

local function sameVariables(first, second)
    if not first or not second then return false end
    for index = 1, ActionBar.SLOT_COUNT do
        local a, b = first[index], second[index]
        if a.type ~= b.type or a.action ~= b.action or a.object ~= b.object then return false end
    end
    return true
end

local function componentLabel(graphic, prefix, index)
    local candidates = {graphic, component(prefix .. "__BUTTON_" .. index), field(graphic, "parent")}
    for position = 1, 3 do
        local candidate = candidates[position]
        local label = plain(field(field(candidate, "opConfig"), "opBaseName"), ActionBar.MAX_LABEL)
        if label then return label end
    end
end

local function readSlot(raw, prefix, index)
    local graphic = component(prefix .. "__GRAPHIC_" .. index)
    if graphic == nil then return nil end
    local associated = field(graphic, "associatedObjectID")
    local sprite = field(graphic, "spriteID")
    if not integer(associated, -1, MAX_INTEGER) or not integer(sprite, -1, MAX_INTEGER) then return nil end
    if associated ~= raw.object then return nil end
    local runtimeSprite = field(graphic, "runtimeSprite")
    if associated < 0 and runtimeSprite ~= nil and runtimeSprite ~= false then return nil end
    local blank = namedID("Sprite", "COMBATV2_BLANK_ABILITY")
    if associated < 0 and (sprite < 0 or sprite == blank) then
        return raw.type <= 0 and raw.action <= 0 and {} or nil
    end
    if raw.type < 0 or raw.action < 0 or field(graphic, "visibleGlobal", "visible") == false then return nil end
    local slot = {type = raw.type, action = raw.action}
    if associated >= 0 then
        slot.object = nativeName("Obj", associated)
        if not slot.object then return nil end
        slot.label = plain(field(object(associated), "name"), ActionBar.MAX_LABEL)
    else
        slot.sprite = nativeName("Sprite", sprite)
        if not slot.sprite then return nil end
    end
    slot.label = componentLabel(graphic, prefix, index) or slot.label
    return slot
end

function ActionBar.Capture(preset)
    if not integer(preset, 1, 18) then return nil, "Choose an action bar from 1 to 18." end
    local ok, result, message = pcall(function()
        local selected
        for _, prefix in ipairs(prefixes) do
            if shownPreset(prefix) == preset then selected = prefix; break end
        end
        if not selected then return nil, "Display action bar " .. preset .. " in the game before copying it." end
        local before = readVariables(preset)
        if not before then return nil, "Could not read action bar " .. preset .. ". Try again after it has loaded." end
        local bar = {preset = preset, name = "Action bar " .. preset, slots = {}}
        for index = 1, ActionBar.SLOT_COUNT do
            local slot = readSlot(before[index], selected, index)
            if not slot then return nil, "Could not read action bar slot " .. index .. ". Try copying the bar again." end
            bar.slots[index] = slot
        end
        if shownPreset(selected) ~= preset or not sameVariables(before, readVariables(preset)) then
            return nil, "The action bar changed while copying it. Try again."
        end
        for index = 1, ActionBar.SLOT_COUNT do
            local first, second = bar.slots[index], readSlot(before[index], selected, index)
            if not second then return nil, "The action bar changed while copying it. Try again." end
            for key in pairs(slotKeys) do
                if first[key] ~= second[key] then
                    return nil, "The action bar changed while copying it. Try again."
                end
            end
        end
        return ActionBar.Normalize(bar)
    end)
    if not ok then return nil, "Could not read the action bar. Try copying it again." end
    return result, message
end

return ActionBar
