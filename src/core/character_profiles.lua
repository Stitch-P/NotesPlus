local Profiles = {}
local activeID, activeToken

function Profiles.NormalizeID(value)
    if type(value) == "number" then
        if math.type(value) ~= "integer" then return nil end
        value = tostring(value)
    end
    if type(value) ~= "string" or not value:match("^-?%d+$") then return nil end
    local negative = value:sub(1, 1) == "-"
    local digits = negative and value:sub(2) or value
    digits = digits:gsub("^0+", "")
    if digits == "" then return "0" end
    local maximum = negative and "9223372036854775808" or "9223372036854775807"
    if #digits > #maximum or #digits == #maximum and digits > maximum then return nil end
    return (negative and "-" or "") .. digits
end

function Profiles.CurrentID()
    local available, loggedIn = pcall(function() return Player.IsAvailable() end)
    if not available or not loggedIn then return nil, "Log in to load this character's notes." end
    local checked, permitted = pcall(function() return Plugin.HasPermission(PluginPermissions.trackingAccess) end)
    if not checked or not permitted then return nil, "Allow character tracking access to load this character's notes." end
    local ok, value = pcall(function() return Player.GetTrackingID() end)
    if not ok or value == nil then return nil, "Waiting for this character's tracking ID." end
    local characterID = Profiles.NormalizeID(value)
    if not characterID then return nil, "The character tracking ID is unavailable." end
    return characterID
end

function Profiles.Activate(characterID)
    activeID = assert(Profiles.NormalizeID(characterID), "Invalid character profile.")
    activeToken = {}
end

function Profiles.Deactivate()
    activeID, activeToken = nil, nil
end

function Profiles.ID()
    return activeID
end

function Profiles.Token()
    return activeToken
end

function Profiles.IsActive(characterID)
    return activeID ~= nil and (characterID == nil or Profiles.NormalizeID(characterID) == activeID)
end

function Profiles.Key(base, characterID)
    assert(type(base) == "string" and base ~= "", "Invalid character storage key.")
    return base .. ":character:" .. assert(Profiles.NormalizeID(characterID), "Invalid character profile.")
end

return Profiles
