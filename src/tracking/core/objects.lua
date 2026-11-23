-- This allows us to look up the objects we want and return the Object name in the dropdowns we use it for!
local function findObjectID(objName)
    if type(objName) ~= "string" or objName == "" then return nil end
    local ok, cfg = pcall(function()
        return config.Obj[objName]
    end)
    if not ok or not cfg then return nil end

    local okId, objId = pcall(function() return cfg.id end)
    if okId and type(objId) == "number" and objId >= 0 then
        return objId
    end
    return nil
end

local objectNameCache = {}
local function objectDisplayName(objId)
    if not objId then return nil end
    local cached = objectNameCache[objId]
    if cached ~= nil then return cached or nil end
    local name = false
    local ok, found = pcall(function() return config.Obj.FromID(objId).name end)
    if ok and type(found) == "string" and found ~= "" and found ~= "null" then name = found end
    objectNameCache[objId] = name
    return name or nil
end

return {
    findObjectID = findObjectID,
    objectNameCache = objectNameCache,
    objectDisplayName = objectDisplayName,
}
