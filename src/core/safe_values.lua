local SafeValues = {}

function SafeValues.Field(source, ...)
    if source == nil then return nil end
    for index = 1, select("#", ...) do
        local key = select(index, ...)
        local ok, value = pcall(function() return source[key] end)
        if ok and value ~= nil then return value end
    end
    return nil
end

function SafeValues.Number(value, fallback)
    if type(value) == "number" then return value end
    if type(value) == "string" then return tonumber(value) or fallback end
    return fallback
end

function SafeValues.DeepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] ~= nil then return seen[value] end
    local copied = {}
    seen[value] = copied
    for key, entry in pairs(value) do
        copied[SafeValues.DeepCopy(key, seen)] = SafeValues.DeepCopy(entry, seen)
    end
    return copied
end

return SafeValues
