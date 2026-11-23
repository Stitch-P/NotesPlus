local SafeValues = require("src/core/safe_values")
local Hotkeys = require("src/core/hotkeys")
local SettingsHotkey = require("src/core/settings_hotkey")
local Profiles = require("src/core/character_profiles")
local Settings = {}
Settings.DeepCopy = SafeValues.DeepCopy

local DB_KEY = "notes_settings_v1"
local defaults = {
    enabled = true,
    menuX = 16,
    menuY = 88,
    menuLayout = "Side by side",
    settingsHotkey = "None",
    activePage = "General",
    showOnLogin = false,
    notesHotkey = "None",
    notesX = 60,
    notesY = 120,
    notesWidth = 400,
    notesHeight = 1000,
    notesResized = false,
    notesOpacity = 100,
    fontSize = 14,
    showSubject = true,
    showProgressBars = true,
    compactNotes = false,
    achievementPopupX = -180,
    achievementPopupY = 125
}

Settings.OPTIONS = {
    notesHotkey = Hotkeys.options,
    menuLayout = {"Side by side", "Top to bottom"},
    activePage = {"General", "Display"}
}

function Settings.ClampInt(value, minimum, maximum, fallback)
    local number = tonumber(value)
    if number == nil or number ~= number or math.abs(number) == math.huge then
        number = fallback or minimum
    end
    local bounded = clamp(math.floor(number), minimum, math.max(minimum, maximum))
    return bounded % 1 == 0 and math.floor(bounded) or bounded
end

function Settings.NormalizeChoice(value, options, fallback)
    for _, option in ipairs(options) do
        if value == option then return option end
    end
    return fallback
end

function Settings.NormalizeHex(value, fallback)
    local hex = tostring(value or ""):gsub("^#", ""):upper()
    return hex:match("^%x%x%x%x%x%x$") and hex or (fallback or "FFFFFF")
end

function Settings.RGBA(hex, alpha)
    hex = Settings.NormalizeHex(hex)
    return Vector4.new(tonumber(hex:sub(1, 2), 16) / 255,
        tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, alpha or 1)
end

function Settings.Normalize(source)
    source = type(source) == "table" and source or {}
    local settings = {}
    for key, value in pairs(defaults) do
        if type(value) == "boolean" then
            settings[key] = source[key] == nil and value or source[key] == true
        else
            settings[key] = SafeValues.DeepCopy(source[key] ~= nil and source[key] or value)
        end
    end
    for key, options in pairs(Settings.OPTIONS) do
        if key == "notesHotkey" then
            settings[key] = Hotkeys.Normalize(settings[key], defaults[key])
        else
            settings[key] = Settings.NormalizeChoice(settings[key], options, defaults[key])
        end
    end
    settings.settingsHotkey = SettingsHotkey.Normalize(settings.settingsHotkey)
    for _, key in ipairs({"menuX", "menuY", "notesX", "notesY"}) do
        settings[key] = Settings.ClampInt(settings[key], 0, 16000, defaults[key])
    end
    settings.notesOpacity = Settings.ClampInt(settings.notesOpacity, 10, 100, defaults.notesOpacity)
    settings.notesWidth = Settings.ClampInt(settings.notesWidth, 200, 1400, defaults.notesWidth)
    settings.notesHeight = Settings.ClampInt(settings.notesHeight, 200, 1000, defaults.notesHeight)
    local previousSizes = {Small = 11, Medium = 13, Large = 17}
    settings.fontSize = Settings.ClampInt(source.fontSize or previousSizes[source.textSize], 10, 24, defaults.fontSize)
    settings.achievementPopupX = Settings.ClampInt(settings.achievementPopupX, -16000, 16000, defaults.achievementPopupX)
    settings.achievementPopupY = Settings.ClampInt(settings.achievementPopupY, 0, 16000, defaults.achievementPopupY)
    return settings
end

function Settings.Load(characterID)
    characterID = assert(Profiles.NormalizeID(characterID), "Invalid character profile.")
    assert(Profiles.IsActive(characterID), "No active character profile.")
    local stored = PersistentDB:GetStructuredData(Profiles.Key(DB_KEY, characterID))
    return Settings.Normalize(stored)
end

function Settings.Save(settings, characterID)
    characterID = Profiles.NormalizeID(characterID)
    if characterID == nil or not Profiles.IsActive(characterID) then
        return nil, "These settings do not belong to the active character."
    end
    assert(PersistentDB:SetStructuredData(Profiles.Key(DB_KEY, characterID), Settings.Normalize(settings)) == true,
        "The character settings could not be saved.")
    return true
end

return Settings
