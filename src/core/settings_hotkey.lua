local SettingsHotkey = {}
local Controller = {}
Controller.__index = Controller

local function keyName(key)
    if type(key) ~= "number" then return nil end
    local ok, name = pcall(GameKey.FromID, key)
    if not ok or type(name) ~= "string" or not name:match("^[A-Z_][A-Z_0-9]*$") then return nil end
    local found, value = pcall(function() return GameKey[name] end)
    if found and value == key then return name end
    return nil
end

function SettingsHotkey.FromKeys(keys)
    if type(keys) ~= "table" then return nil end
    local names = {}
    for index, key in pairs(keys) do
        if type(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > 2 then return nil end
        names[index] = keyName(key)
        if names[index] == nil then return nil end
    end
    if next(names) == nil then return "None" end
    if names[1] == nil or (names[2] ~= nil and keys[1] == keys[2]) then return nil end
    return table.concat(names, "+")
end

function SettingsHotkey.GetKeys(value)
    if type(value) ~= "string" or value == "None" then return {} end
    local keys, names = {}, {}
    for name in value:gmatch("[^+]+") do
        if #keys == 2 or not name:match("^[A-Z_][A-Z_0-9]*$") then return {} end
        local ok, key = pcall(function() return GameKey[name] end)
        if not ok or keyName(key) ~= name or key == keys[1] then return {} end
        keys[#keys + 1], names[#names + 1] = key, name
    end
    if #keys == 0 or table.concat(names, "+") ~= value then return {} end
    return keys
end

function SettingsHotkey.Normalize(value)
    return SettingsHotkey.FromKeys(SettingsHotkey.GetKeys(value))
end

function Controller:GetBinding()
    local raw = self.callbacks.getBinding()
    if not self.cached or raw ~= self.rawBinding then
        self.cached, self.rawBinding = true, raw
        self.binding = SettingsHotkey.Normalize(raw)
        self.keys = SettingsHotkey.GetKeys(self.binding)
        self.armed = false
        if self.onKeyDown ~= nil then self:SyncSubscriptions() end
    end
    return self.binding
end

function Controller:SyncSubscriptions()
    local enabled = not self.stopped and #self.keys > 0
    if self.subscribed == enabled then return end
    if enabled then
        Event.KeyDown.Subscribe(self.eventID, self.onKeyDown)
        Event.KeyUp.Subscribe(self.eventID, self.onKeyUp)
        if Event.WindowFocusChanged ~= nil then Event.WindowFocusChanged.Subscribe(self.eventID, self.onFocusChanged) end
    elseif self.subscribed then
        Event.KeyDown.Unsubscribe(self.eventID)
        Event.KeyUp.Unsubscribe(self.eventID)
        if Event.WindowFocusChanged ~= nil then Event.WindowFocusChanged.Unsubscribe(self.eventID) end
    end
    self.subscribed = enabled
end

function Controller:SetBinding(value)
    if self.stopped then return end
    local binding = SettingsHotkey.Normalize(value)
    local changed = self:GetBinding() ~= binding
    self.armed = false
    if changed then self.callbacks.setBinding(binding) end
    return self:GetBinding()
end

function SettingsHotkey.IsBlocked()
    return prettyui.KeybindField.IsCapturing() or not Keyboard.IsAvailable() or Keyboard.IsBlocked()
end

local function containsKey(keys, key)
    for _, bound in ipairs(keys) do
        if bound == key then return true end
    end
    return false
end

local function onlyBoundKeysDown(keys)
    if Keyboard.IsMetaDown() then return false end
    for _, key in ipairs(Keyboard.GetGameKeysDown()) do
        if not containsKey(keys, key) then return false end
    end
    return true
end

function SettingsHotkey.IsExactDown(keys, pressedKey)
    if #keys == 0 or SettingsHotkey.IsBlocked() then return false end
    if pressedKey ~= nil and not containsKey(keys, pressedKey) then return false end
    for _, key in ipairs(keys) do
        if key ~= pressedKey and not Keyboard.IsGameKeyDown(key) then return false end
    end
    return onlyBoundKeysDown(keys)
end

function SettingsHotkey.IsValidRelease(keys, releasedKey)
    return containsKey(keys, releasedKey) and not SettingsHotkey.IsBlocked() and onlyBoundKeysDown(keys)
end

function SettingsHotkey.New(eventID, callbacks)
    assert(type(eventID) == "string" and eventID ~= "", "A settings hotkey needs an event ID")
    for _, name in ipairs({"getBinding", "setBinding", "toggle", "available"}) do
        assert(type(callbacks[name]) == "function", "Missing settings hotkey callback: " .. name)
    end
    local self = setmetatable({eventID = eventID, callbacks = callbacks, armed = false}, Controller)
    self.onKeyDown = function(event)
        if self.stopped or event == nil or event.isRepeat then return end
        self:GetBinding()
        self.armed = event.gameKey ~= nil and #self.keys > 0 and callbacks.available()
            and SettingsHotkey.IsExactDown(self.keys, event.gameKey)
    end
    self.onKeyUp = function(event)
        if self.stopped or event == nil then return end
        self:GetBinding()
        local armed = self.armed
        self.armed = false
        if armed and callbacks.available() and SettingsHotkey.IsValidRelease(self.keys, event.gameKey) then
            callbacks.toggle()
        end
    end
    self.onFocusChanged = function() self.armed = false end
    self:GetBinding()
    return self
end

function Controller:Stop()
    if self.stopped then return end
    self.stopped, self.armed = true, false
    self:SyncSubscriptions()
end

return SettingsHotkey
