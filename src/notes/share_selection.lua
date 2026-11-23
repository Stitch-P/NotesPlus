local Notes = require("src/notes/notes")
local Selection = {}
Selection.__index = Selection
Selection.LIMIT = 9999

function Selection.New(data, snapshot)
    local self = setmetatable({data = data, selected = {}}, Selection)
    for _, note in ipairs(data.notes) do
        if snapshot == nil or snapshot[note] == true then self.selected[note] = true end
    end
    return self
end

function Selection:IsSelected(note)
    return self.selected[note] == true
end

function Selection:SetSelected(note, selected)
    for _, existing in ipairs(self.data.notes) do
        if existing == note then
            self.selected[note] = selected == true and true or nil
            return
        end
    end
end

function Selection:SetAll(selected)
    self.selected = {}
    if selected == true then
        for _, note in ipairs(self.data.notes) do self.selected[note] = true end
    end
end

function Selection:Snapshot()
    local snapshot = {}
    for _, note in ipairs(self.data.notes) do
        if self.selected[note] then snapshot[note] = true end
    end
    return snapshot
end

function Selection:Export()
    local notes, categories, usedCategories = {}, {}, {}
    for _, note in ipairs(self.data.notes) do
        if self.selected[note] then
            notes[#notes + 1] = note
            usedCategories[note.categoryID or 0] = true
        end
    end
    local count, total = #notes, #self.data.notes
    if count == total then return Notes.Export(self.data), count, total, self.data end
    for _, category in ipairs(self.data.categories or {}) do
        if usedCategories[category.id] then categories[#categories + 1] = category end
    end
    local data = {notes = notes, categories = categories}
    return Notes.Export(data), count, total, data
end

function Selection:CanShare()
    local code, count = self:Export()
    return count > 0 and #code <= Selection.LIMIT
end

return Selection
