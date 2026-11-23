local Progress = {}

local MAX_SLOTS, MAX_KEY_LENGTH = 10000, 400

local function validKey(key)
    return type(key) == "string" and #key > 0 and #key <= MAX_KEY_LENGTH and not key:find("[%c]")
end

function Progress.Copy(saved, signature)
    if type(saved) ~= "table" or saved.signature ~= signature or type(saved.completed) ~= "table" then return nil end
    local completed, count = {}, 0
    for key, value in pairs(saved.completed) do
        count = count + 1
        if count > MAX_SLOTS or not validKey(key) or value ~= true then return nil end
        completed[key] = true
    end
    return {signature = signature, completed = completed}
end

function Progress.Observe(note, baseline, signature, slots)
    local history = note.progressNotifications
    local changed = false
    if history and history.signature ~= signature then
        note.progressNotifications, history, changed = nil, nil, true
    end
    if type(slots) ~= "table" then
        baseline.slots = nil
        return {}, true, changed
    end
    local observed = baseline.slots or {}
    baseline.slots = observed
    local completed = history and history.completed or {}
    local newlyDone, ready = {}, #slots > 0
    for index, slot in ipairs(slots) do
        if index > MAX_SLOTS then break end
        local key, state = slot.key, slot.complete
        if validKey(key) and type(state) == "boolean" then
            if state and not completed[key] then
                completed[key], changed = true, true
                if observed[key] == false then newlyDone[#newlyDone + 1] = slot end
            end
            observed[key] = state
        else
            ready = false
        end
    end
    if changed and next(completed) then
        note.progressNotifications = {signature = signature, completed = completed}
    end
    return newlyDone, ready, changed
end

return Progress
