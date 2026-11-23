local Notes = require("src/notes/notes")
local SafeValues = require("src/core/safe_values")

local ImportPreview = {}

local function newPlan(notes, categories, nextCategoryID, addedCount, totalCount)
    return {
        notes = notes,
        data = {notes = notes, categories = categories, nextCategoryID = nextCategoryID},
        addedCount = addedCount, totalCount = totalCount,
        categoryChanges = {}, newCategoryCount = 0, changedCategoryCount = 0,
        trackingCount = 0, gearCount = 0, actionBarCount = 0, notificationCount = 0
    }
end

function ImportPreview.Parse(text)
    local called, source, message = pcall(Notes.Parse, text)
    if not called then
        return nil, "These notes could not be read (" .. tostring(source):sub(1, 160) .. ")."
    end
    if not source then return nil, message or "These notes could not be read." end
    return source
end

function ImportPreview.SelectedText(source, selectedIndices)
    local notes, categories, usedCategories = {}, {}, {}
    for index, note in ipairs(source.notes) do
        if selectedIndices == nil or selectedIndices[index] == true then
            notes[#notes + 1] = note
            usedCategories[note.categoryID or 0] = true
        end
    end
    for _, category in ipairs(source.categories) do
        if #source.notes == 0 then
            local copy = SafeValues.DeepCopy(category)
            -- Keep metadata-only categories even when they have no custom appearance.
            if copy.skill == nil and copy.color == nil then copy.skill = "" end
            categories[#categories + 1] = copy
        elseif usedCategories[category.id] then
            categories[#categories + 1] = category
        end
    end
    return Notes.Export({notes = notes, categories = categories}), #notes
end

function ImportPreview.Build(data, text)
    local called, staged, message = pcall(function()
        local candidate = SafeValues.DeepCopy(data)
        local imported, failure = Notes.Import(candidate, text)
        if not imported then return nil, failure end
        return candidate
    end)
    if not called then
        return nil, "These notes could not be previewed (" .. tostring(staged):sub(1, 160) .. ")."
    end
    if not staged then return nil, message or "These notes could not be previewed." end

    local incoming = {}
    local plan = newPlan(incoming, staged.categories, staged.nextCategoryID, #staged.notes - #data.notes, #staged.notes)
    for index = #data.notes + 1, #staged.notes do
        local note = staged.notes[index]
        incoming[#incoming + 1] = note
        if note.tracking then plan.trackingCount = plan.trackingCount + 1 end
        if note.gear then plan.gearCount = plan.gearCount + 1 end
        if note.actionBar then plan.actionBarCount = plan.actionBarCount + 1 end
        if note.notifyChat or note.notifyPopup then plan.notificationCount = plan.notificationCount + 1 end
    end

    local previous = {}
    for _, category in ipairs(data.categories) do previous[category.id] = category end
    for _, category in ipairs(staged.categories) do
        local before = previous[category.id]
        local kind = before == nil and "added"
            or (before.skill ~= category.skill or before.color ~= category.color) and "appearance" or nil
        if kind then
            plan.categoryChanges[#plan.categoryChanges + 1] = {
                name = category.name, kind = kind,
                before = before and SafeValues.DeepCopy(before) or nil, after = category
            }
            if kind == "added" then plan.newCategoryCount = plan.newCategoryCount + 1
            else plan.changedCategoryCount = plan.changedCategoryCount + 1 end
        end
    end
    return plan
end

function ImportPreview.BuildSelection(data, source, selectedIndices)
    local called, plan, message = pcall(function()
        local text, count = ImportPreview.SelectedText(source, selectedIndices)
        if count == 0 and (#source.notes > 0 or #source.categories == 0) then
            return newPlan({}, SafeValues.DeepCopy(data.categories), data.nextCategoryID, 0, #data.notes)
        end
        return ImportPreview.Build(data, text)
    end)
    if not called then
        return nil, "These notes could not be previewed (" .. tostring(plan):sub(1, 160) .. ")."
    end
    return plan, message
end

return ImportPreview
