local Storage = {}
local snapshots = {}
local MAX_NOTES = 1000
local MAX_CATEGORIES = 50
local MAX_ID = 9007199254740991
local READ_ERROR = "Notes could not read the saved notes. The saved data has been kept."
local SAVE_ERROR = "The character notes could not be saved. Your previous saved notes have been kept."

local function positiveInteger(value)
    return type(value) == "number" and value >= 1 and value <= MAX_ID and value % 1 == 0
end

local function array(value, maximum)
    if type(value) ~= "table" or #value > maximum then return false end
    local count = 0
    for key in pairs(value) do
        if not positiveInteger(key) or key > #value then return false end
        count = count + 1
    end
    return count == #value
end

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

local function equal(left, right)
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return left == right end
    for key, value in pairs(left) do
        if not equal(value, right[key]) then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
end

local function noteKey(rootKey, recordID)
    return rootKey .. ":note:" .. string.format("%.0f", recordID)
end

local function read(key)
    local ok, value = pcall(function() return PersistentDB:GetStructuredData(key) end)
    if not ok then return nil, READ_ERROR end
    return value
end

local function write(key, value)
    local ok, saved = pcall(function() return PersistentDB:SetStructuredData(key, value) end)
    return ok and saved == true
end

local function discard(keys)
    for _, key in ipairs(keys) do pcall(function() PersistentDB:Delete(key) end) end
end

local function validData(data)
    if type(data) ~= "table" or data.version ~= 1 or not positiveInteger(data.nextCategoryID)
        or not array(data.categories, MAX_CATEGORIES) or not array(data.notes, MAX_NOTES) then return false end
    for _, category in ipairs(data.categories) do
        if type(category) ~= "table" then return false end
    end
    for _, note in ipairs(data.notes) do
        if type(note) ~= "table" then return false end
    end
    return true
end

local function validManifest(manifest)
    if type(manifest) ~= "table" or manifest.version ~= 2
        or not positiveInteger(manifest.nextCategoryID) or not positiveInteger(manifest.nextNoteID)
        or not array(manifest.categories, MAX_CATEGORIES) or not array(manifest.noteIDs, MAX_NOTES) then return false end
    for _, category in ipairs(manifest.categories) do
        if type(category) ~= "table" then return false end
    end
    local seen = {}
    for _, recordID in ipairs(manifest.noteIDs) do
        if not positiveInteger(recordID) or recordID >= manifest.nextNoteID or seen[recordID] then return false end
        seen[recordID] = true
    end
    return true
end

function Storage.Load(rootKey)
    if type(rootKey) ~= "string" or rootKey == "" then return nil, READ_ERROR end
    snapshots[rootKey] = nil
    local stored, message = read(rootKey)
    if message then return nil, message end
    if stored == nil then
        local ok, exists = pcall(function() return PersistentDB:CheckExists(rootKey) end)
        if not ok or exists ~= false then return nil, READ_ERROR end
        return nil
    end
    if type(stored) == "table" and stored.version == 1 then
        if not validData(stored) then return nil, READ_ERROR end
        snapshots[rootKey] = {data = copy(stored)}
        return stored
    end
    if not validManifest(stored) then return nil, READ_ERROR end
    local data = {version = 1, categories = copy(stored.categories), nextCategoryID = stored.nextCategoryID,
        trackingCategoriesReviewed = stored.trackingCategoriesReviewed,
        scheduledDefaultsAdded = stored.scheduledDefaultsAdded,
        scheduledCategoryOrdered = stored.scheduledCategoryOrdered,
        scheduledEventsAdded = stored.scheduledEventsAdded,
        scheduledRewardsAdded = stored.scheduledRewardsAdded,
        scheduledPenguinsAdded = stored.scheduledPenguinsAdded,
        scheduledTasksAdded = stored.scheduledTasksAdded, notes = {}}
    for _, recordID in ipairs(stored.noteIDs) do
        local note, failure = read(noteKey(rootKey, recordID))
        if failure or type(note) ~= "table" then return nil, READ_ERROR end
        data.notes[#data.notes + 1] = note
    end
    snapshots[rootKey] = {data = copy(data), manifest = copy(stored)}
    return data
end

function Storage.Save(rootKey, data)
    if type(rootKey) ~= "string" or rootKey == "" or not validData(data) then return nil, SAVE_ERROR end
    local previous = snapshots[rootKey]
    if previous == nil then
        local _, message = Storage.Load(rootKey)
        if message then return nil, message end
        previous = snapshots[rootKey] or {}
    end
    local oldManifest = previous.manifest
    if oldManifest and equal(previous.data, data) then return true end
    local manifest = {version = 2, categories = copy(data.categories), nextCategoryID = data.nextCategoryID,
        trackingCategoriesReviewed = data.trackingCategoriesReviewed,
        scheduledDefaultsAdded = data.scheduledDefaultsAdded,
        scheduledCategoryOrdered = data.scheduledCategoryOrdered,
        scheduledEventsAdded = data.scheduledEventsAdded,
        scheduledRewardsAdded = data.scheduledRewardsAdded,
        scheduledPenguinsAdded = data.scheduledPenguinsAdded,
        scheduledTasksAdded = data.scheduledTasksAdded, noteIDs = {},
        nextNoteID = oldManifest and oldManifest.nextNoteID or 1}
    local oldNotes = oldManifest and previous.data.notes or {}
    local oldCount, newCount = #oldNotes, #data.notes
    local prefix, suffix = 0, 0
    while prefix < math.min(oldCount, newCount) and equal(oldNotes[prefix + 1], data.notes[prefix + 1]) do
        prefix = prefix + 1
    end
    while suffix < math.min(oldCount - prefix, newCount - prefix)
        and equal(oldNotes[oldCount - suffix], data.notes[newCount - suffix]) do
        suffix = suffix + 1
    end
    local staged = {}
    for index, note in ipairs(data.notes) do
        local previousIndex
        if index <= prefix then previousIndex = index
        elseif index > newCount - suffix then previousIndex = oldCount - newCount + index
        elseif index <= oldCount - suffix and equal(oldNotes[index], note) then previousIndex = index end
        local recordID = previousIndex and oldManifest.noteIDs[previousIndex]
        if recordID == nil then
            if manifest.nextNoteID >= MAX_ID then discard(staged); return nil, SAVE_ERROR end
            recordID = manifest.nextNoteID
            manifest.nextNoteID = recordID + 1
            local key = noteKey(rootKey, recordID)
            staged[#staged + 1] = key
            if not write(key, copy(note)) then discard(staged); return nil, SAVE_ERROR end
        end
        manifest.noteIDs[#manifest.noteIDs + 1] = recordID
    end
    -- Readers keep using the previous records until the complete manifest is saved.
    if not write(rootKey, manifest) then discard(staged); return nil, SAVE_ERROR end
    snapshots[rootKey] = {data = copy(data), manifest = copy(manifest)}
    if oldManifest then
        local retained, obsolete = {}, {}
        for _, recordID in ipairs(manifest.noteIDs) do retained[recordID] = true end
        for _, recordID in ipairs(oldManifest.noteIDs) do
            if not retained[recordID] then obsolete[#obsolete + 1] = noteKey(rootKey, recordID) end
        end
        discard(obsolete)
    end
    return true
end

return Storage
