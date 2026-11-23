local Hotkeys = {options = {}}

local definitions = {
    {"None"},
    {"Ctrl", GameKey.CONTROL},
    {"Alt", GameKey.ALT},
    {"Shift", GameKey.SHIFT},
    {"A", GameKey.A},
    {"B", GameKey.B},
    {"C", GameKey.C},
    {"D", GameKey.D},
    {"E", GameKey.E},
    {"F", GameKey.F},
    {"G", GameKey.G},
    {"H", GameKey.H},
    {"I", GameKey.I},
    {"J", GameKey.J},
    {"K", GameKey.K},
    {"L", GameKey.L},
    {"M", GameKey.M},
    {"N", GameKey.N},
    {"O", GameKey.O},
    {"P", GameKey.P},
    {"Q", GameKey.Q},
    {"R", GameKey.R},
    {"S", GameKey.S},
    {"T", GameKey.T},
    {"U", GameKey.U},
    {"V", GameKey.V},
    {"W", GameKey.W},
    {"X", GameKey.X},
    {"Y", GameKey.Y},
    {"Z", GameKey.Z},
    {"0", GameKey._0},
    {"1", GameKey._1},
    {"2", GameKey._2},
    {"3", GameKey._3},
    {"4", GameKey._4},
    {"5", GameKey._5},
    {"6", GameKey._6},
    {"7", GameKey._7},
    {"8", GameKey._8},
    {"9", GameKey._9},
    {"F1", GameKey.F1},
    {"F2", GameKey.F2},
    {"F3", GameKey.F3},
    {"F4", GameKey.F4},
    {"F5", GameKey.F5},
    {"F6", GameKey.F6},
    {"F7", GameKey.F7},
    {"F8", GameKey.F8},
    {"F9", GameKey.F9},
    {"F10", GameKey.F10},
    {"F11", GameKey.F11},
    {"F12", GameKey.F12},
    {"Space", GameKey.SPACE},
    {"Tab", GameKey.TAB},
    {"Enter", GameKey.ENTER},
    {"Escape", GameKey.ESCAPE},
    {"Backspace", GameKey.BACKSPACE},
    {"Insert", GameKey.INSERT},
    {"Delete", GameKey.DELETE},
    {"Home", GameKey.HOME},
    {"End", GameKey.END},
    {"Page Up", GameKey.PAGE_UP},
    {"Page Down", GameKey.PAGE_DOWN},
    {"Left arrow", GameKey.LEFT},
    {"Right arrow", GameKey.RIGHT},
    {"Up arrow", GameKey.UP},
    {"Down arrow", GameKey.DOWN},
    {"Minus (-)", GameKey.MINUS},
    {"Equals (=)", GameKey.EQUALS},
    {"Left bracket ([)", GameKey.LEFT_BRACKET},
    {"Right bracket (])", GameKey.RIGHT_BRACKET},
    {"Semicolon (;)", GameKey.SEMICOLON},
    {"Apostrophe (')", GameKey.APOSTROPHE},
    {"Hash (#)", GameKey.HASH},
    {"Comma (,)", GameKey.COMMA},
    {"Full stop (.)", GameKey.FULLSTOP},
    {"Slash (/)", GameKey.SLASH},
    {"Backslash (\\)", GameKey.BACKSLASH},
    {"Numpad +", GameKey.NUMPAD_ADD},
    {"Numpad -", GameKey.NUMPAD_SUBTRACT},
    {"Numpad *", GameKey.NUMPAD_MULTIPLY},
    {"Numpad /", GameKey.NUMPAD_DIVIDE},
}

local labelsByKey = {}
local bindings = {None = {}}

for index, entry in ipairs(definitions) do
    local label = entry[1]
    Hotkeys.options[index] = label
    if entry[2] ~= nil then
        labelsByKey[entry[2]] = label
        bindings[label] = {entry[2]}
    end
end

local function readBinding(value)
    if type(value) ~= "string" then return nil end
    if bindings[value] ~= nil then return bindings[value] end
    local keys, names = {}, {}
    for name in value:gmatch("[^+]+") do
        if not name:match("^[A-Z_][A-Z_0-9]*$") then return nil end
        local ok, key = pcall(function() return GameKey[name] end)
        if not ok or type(key) ~= "number" or GameKey.FromID(key) ~= name
            or #keys == 2 or key == keys[1] then return nil end
        keys[#keys + 1], names[#names + 1] = key, name
    end
    if #keys == 0 or table.concat(names, "+") ~= value then return nil end
    bindings[value] = keys
    return keys
end

function Hotkeys.GetKeys(value)
    return readBinding(value) or bindings.None
end

function Hotkeys.FromKeys(keys)
    if type(keys) ~= "table" or #keys > 2 then return nil end
    if #keys == 0 then return "None" end
    local names = {}
    for index, key in ipairs(keys) do
        if type(key) ~= "number" or (index == 2 and key == keys[1]) then return nil end
        names[index] = GameKey.FromID(key)
        if names[index] == nil then return nil end
    end
    if #keys == 1 and labelsByKey[keys[1]] ~= nil then return labelsByKey[keys[1]] end
    return table.concat(names, "+")
end

function Hotkeys.Normalize(value, fallback)
    local keys = readBinding(value) or readBinding(fallback) or bindings.None
    return Hotkeys.FromKeys(keys)
end

return Hotkeys
