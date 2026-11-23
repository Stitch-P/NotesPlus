local Base = require("src/ui/views/view")
local Notes = require("src/notes/notes")
local CategoryLayout = require("src/ui/views/category_editor_layout")
local CategoryAppearance = require("src/ui/categories/category_appearance")
local Overlay = require("src/ui/window/overlay")
local Tracking = require("src/tracking/model")

local CategoryEditor = {}
CategoryEditor.__index = CategoryEditor
setmetatable(CategoryEditor, {__index = Base})

function CategoryEditor.new(parent, options, callbacks)
    local self = Base.Init(setmetatable({}, CategoryEditor), parent, options, callbacks)
    self.categoryDraft = options.draft
    self:Build()
    return self
end

function CategoryEditor:RefreshCategoryAppearance()
    if not self.categorySprite or not self.categoryDraft then return end
    self.categorySprite.hidden = not CategoryAppearance.Apply(self.categorySprite, self.categoryDraft)
    self.categoryNameField.root.text.rgba = CategoryAppearance.Color(self.categoryDraft, 0xD8D1C4FF)
end

CategoryEditor.Build = CategoryLayout.Build
CategoryEditor.ClipCategoryFields = CategoryLayout.Clip

function CategoryEditor:Resize(width, height)
    if self.destroyed or self.width == width and self.height == height then return end
    self.width, self.height = width, height
    self.layout()
end

function CategoryEditor:SaveDraft()
    self:Snapshot()
    local draft = self.categoryDraft
    local previous = draft.id and Notes.FindCategory(self.data, draft.id)
    local fields, nextID = {}, self.data.nextCategoryID
    for key, value in pairs(previous or {}) do fields[key] = value end
    local appearance = {skill = draft.skill, color = draft.color}
    local result, message
    if draft.id then result, message = Notes.UpdateCategory(self.data, draft.id, draft.name, appearance)
    else result, message = Notes.AddCategory(self.data, draft.name, appearance) end
    if not result then self:Status(message); return end
    local saved
    saved, message = self:Save()
    if not saved then
        if previous then
            for key in pairs(previous) do previous[key] = nil end
            for key, value in pairs(fields) do previous[key] = value end
        else
            table.remove(self.data.categories)
            self.data.nextCategoryID = nextID
        end
        self:Status(message)
        return
    end
    self.state.categoryID, self.state.scroll = draft.id or result, 0
    self:ShowList()
end

function CategoryEditor:DeleteCategory()
    local draft = self.categoryDraft
    if not draft.confirmDelete then
        draft.confirmDelete = true
        self:Status("Press Delete again. Notes will move to Uncategorized.")
        return
    end
    local category, position, notes = Notes.FindCategory(self.data, draft.id), nil, {}
    for index, existing in ipairs(self.data.categories) do
        if existing == category then position = index; break end
    end
    for _, note in ipairs(self.data.notes) do
        if note.categoryID == draft.id then notes[#notes + 1] = note end
    end
    local ok, message = Notes.DeleteCategory(self.data, draft.id)
    if not ok then self:Status(message); return end
    local saved
    saved, message = self:Save()
    if not saved then
        table.insert(self.data.categories, position, category)
        for _, note in ipairs(notes) do note.categoryID = draft.id end
        self:Status(message)
        return
    end
    if self.state.categoryID == draft.id then self.state.categoryID = 0 end
    self.state.scroll = 0
    self:ShowList()
end

function CategoryEditor:Snapshot()
    local draft = self.categoryDraft
    if not self.destroyed then
        if self.categoryNameField then draft.name = self.categoryNameField:GetText() end
        if self.categoryColorField then
            local color = self.categoryColorField:GetText():gsub("^#", ""):upper()
            draft.color = color ~= "" and color or nil
        end
        if self.categoryScroll then draft.scroll = self.categoryScroll.scrollY end
    end
    return draft
end

function CategoryEditor:Tick()
    if self.destroyed then return end
    if self.categorySprite and self.categoryIconRevision ~= Tracking.IconRevision() then
        self.categoryIconRevision = Tracking.IconRevision()
        self:RefreshCategoryAppearance()
    end
    local picker = self.categoryColorPicker and self.categoryColorPicker.pickerWindow
    if picker then
        local x, y = Overlay.Clamp(self.parent, picker.root.x, picker.root.y, picker.root.width, picker.root.height)
        picker.root:SetPos(x, y)
    end
end

function CategoryEditor:Destroy(detached)
    if self.destroyed then return end
    if self.categoryScroll then self.categoryScroll.onLayout = nil end
    self.window.chrome.minHeight = self.previousMinHeight
    if self.window.chrome.resize then self.window.chrome.resize.minHeight = self.previousResizeMinHeight end
    Base.Destroy(self, detached)
    self.categoryScroll, self.categoryClipComponents = nil, nil
    self.categoryNameField, self.categoryColorField, self.categoryColorPicker = nil, nil, nil
    self.categorySpriteButton, self.categorySprite, self.categoryDefaultColorButton = nil, nil, nil
end

return CategoryEditor
