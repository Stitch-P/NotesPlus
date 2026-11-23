local Base = require("src/ui/views/view")
local Notes = require("src/notes/notes")
local Settings = require("src/core/settings")
local EditorLayout = require("src/ui/views/note_editor_layout")
local Overlay = require("src/ui/window/overlay")
local Detached = require("src/ui/shared/detached_ui")
local DropdownLayout = require("src/ui/shared/dropdown_layout")
local Tracking = require("src/tracking/model")
local TrackingEditor = require("src/ui/tracking/tracking_editor")
local Gear = require("src/notes/gear")
local GearPreview = require("src/ui/attachments/gear_preview")
local ActionBar = require("src/notes/action_bar")
local ActionBarPreview = require("src/ui/attachments/action_bar_preview")

local Editor = {}
Editor.__index = Editor
setmetatable(Editor, {__index = Base})

local TAB_INDEX = {tracking = 1, note = 2, gear = 3, actionBar = 4}
local defaultTrackingTypes = {}
for _, category in ipairs(Notes.DefaultCategories()) do defaultTrackingTypes[category.name:lower()] = category.name end

local function categoryTrackingType(data, categoryID)
    local category = Notes.FindCategory(data, categoryID)
    return category and defaultTrackingTypes[category.name:lower()] or nil
end

local function generatedText(value)
    if #value <= Notes.MAX_TITLE then return value, "" end
    local ending = Notes.MAX_TITLE
    while ending > 0 do
        local nextByte = value:byte(ending + 1)
        if nextByte < 128 or nextByte >= 192 then break end
        ending = ending - 1
    end
    return value:sub(1, ending), value
end

function Editor.new(parent, options, callbacks)
    options = options or {}
    local self = Base.Init(setmetatable({}, Editor), parent, options, callbacks)
    self.draft = assert(options.draft, "A note draft is required")
    self.pendingEditorScrolls = {}
    for name, scroll in pairs(self.draft.editorScrolls or {}) do self.pendingEditorScrolls[name] = scroll end
    self:Build()
    return self
end

function Editor:SyncDraftFields()
    if self.view == "edit" and self.draft and self.titleField and self.editor then
        self.draft.title, self.draft.text = self.titleField:GetText(), self.editor:GetText()
    end
end

function Editor:ChooseCategory(categoryID)
    local draft = self.draft
    draft.categoryID, draft.categoryChosen = categoryID, true
    local category = categoryTrackingType(self.data, categoryID)
    if not category then return end
    if not self.trackingEditor then
        draft.trackingType = category
        return
    end
    for index, name in ipairs(self.trackingEditor.categories) do
        if name == category then
            if self.trackingEditor.categoryCombo:GetSelectedID() ~= index then
                self.trackingEditor.categoryCombo:Select(index, true)
            end
            return
        end
    end
end

function Editor:RestoreScrolls()
    local pending = self.pendingEditorScrolls
    if pending.header ~= nil then
        self.header:SetScrollPosition(pending.header)
        pending.header = nil
    end
    local name = self.activeTab or "note"
    -- Hidden pages restore only after their content has been measured.
    if pending[name] ~= nil then
        self.pages[name]:SetScrollPosition(pending[name])
        pending[name] = nil
    end
end

function Editor:CloseTabOverlays(name, hideContext)
    local page = self.pages[name]
    if not page then return end
    if hideContext then prettyui.Tooltip.hideContextTooltips(page.content) end
    if name == "tracking" and self.trackingEditor then
        for _, control in ipairs(self.trackingEditor.controls) do
            if control._Close then control:_Close() end
        end
        if self.trackingEditor.componentPicker then self.trackingEditor.componentPicker:HideTooltip() end
    elseif name == "gear" and self.gearEditor then self.gearEditor:HideTooltip()
    elseif name == "actionBar" and self.actionBarEditor then
        self.actionBarEditor:HideTooltip()
        if self.actionBarEditor.preset then self.actionBarEditor.preset:_Close() end
    end
end

function Editor:ActivateTab(name)
    if self.destroyed or self.clearing or not TAB_INDEX[name] then return end
    self:SyncDraftFields()
    if self.trackingEditor then self.trackingEditor:FlushPending() end
    if self.activeTab then self:CloseTabOverlays(self.activeTab, self.activeTab == name) end
    self.categoryField:_Close()
    self.sectionCombo:_Close()
    self.activeInput = nil
    self.activeTab, self.draft.editorTab = name, name
    self.sectionCombo:Select(TAB_INDEX[name], false)
    if name == "tracking" and not self.trackingEditor then self:MountTrackingEditor()
    elseif name == "gear" and not self.gearEditor then self:MountGearEditor()
    elseif name == "actionBar" and not self.actionBarEditor then self:MountActionBarEditor() end
    self:LayoutEditor(true)
end

function Editor:SelectTab(name)
    if self.destroyed or self.clearing or not TAB_INDEX[name] then return end
    self.tabs:SetActive(TAB_INDEX[name], false)
    self:ActivateTab(name)
end

function Editor:OpenGearEditor() self:SelectTab("gear") end

function Editor:OpenGearSlot(key)
    if self.destroyed or self.view ~= "edit" or not self.draft then return end
    for _, slot in ipairs(Gear.Slots) do
        if slot.key == key then
            self:SyncDraftFields()
            self.draft.gear = self.draft.gear or {}
            self:Navigate("gearItems", {draft = self.draft, slot = slot})
            return
        end
    end
end

function Editor:OpenActionBarEditor() self:SelectTab("actionBar") end

function Editor:MountActionBarEditor()
    local draft = self.draft
    self.actionBarEditor = ActionBarPreview.new(self.pages.actionBar.content, draft.actionBar, {
        capture = function(preset)
            self.pendingActionBar = {draft = draft, preset = preset}
        end,
        remove = function()
            self.pendingActionBar = {draft = draft, remove = true}
        end
    }, {x = 8, y = 8, width = self.pages.actionBar.contentWidth - 16, editable = true,
        selectedPreset = draft.actionBarPreset})
    DropdownLayout.FitToWindow(self.actionBarEditor.preset)
end

function Editor:FlushActionBar()
    if not self.pendingActionBar then return true end
    local pending = self.pendingActionBar
    self.pendingActionBar = nil
    return self:CaptureActionBar(pending)
end

function Editor:CaptureActionBar(pending)
    if self.destroyed or self.view ~= "edit" or self.draft ~= pending.draft then return nil, "That note is no longer open." end
    self:SyncDraftFields()
    if pending.remove then
        self.draft.actionBar = nil
        self.actionBarEditor:SetBar(nil)
        self:LayoutEditor()
        return true
    end
    local bar, message = ActionBar.Capture(pending.preset)
    if not bar then self:Status(message); return nil, message end
    self.draft.actionBar = bar
    self.draft.actionBarPreset = bar.preset
    self.actionBarEditor:SetBar(bar)
    self:LayoutEditor()
    self:Status("Copied action bar " .. bar.preset .. ". Press Save to keep it.")
    return true
end

function Editor:MountGearEditor()
    local draft = self.draft
    self.gearEditor = GearPreview.new(self.pages.gear.content, draft.gear, {
        choose = function(key) self:OpenGearSlot(key) end,
        capture = function() self:UseEquippedGear() end,
        remove = function()
            self:SyncDraftFields()
            draft.gear = nil
            self.gearEditor:SetGear(nil)
            self:LayoutEditor()
        end
    }, {x = 8, y = 8, width = self.pages.gear.contentWidth - 16, editable = true})
end

function Editor:UseEquippedGear()
    if self.destroyed or self.view ~= "edit" or not self.draft then return end
    local gear, message = Gear.CaptureEquipped()
    if gear == nil then self:Status(message); return end
    self:SyncDraftFields()
    self.draft.gear = gear
    if self.gearEditor then
        self.gearEditor:SetGear(gear)
        self:LayoutEditor()
    else
        self:SelectTab("gear")
    end
    self:Status("Copied " .. Gear.Count(gear) .. " items. Press Save to keep them.")
end

function Editor:UpdateTrackingTitle(defaultTitle, previousTitle)
    if not defaultTitle then return false end
    local draft = self.draft
    local title, text = self.titleField:GetText(), self.editor:GetText()
    local previous, previousText
    if previousTitle then previous, previousText = generatedText(previousTitle) end
    local empty = title == "" and text == ""
    if not empty and title ~= previous then return false end
    local generatedTitle, generatedSubject = generatedText(defaultTitle)
    if empty or text == previousText then text = generatedSubject end
    local changed = title ~= generatedTitle or self.editor:GetText() ~= text
    draft.title, draft.text = generatedTitle, text
    self.titleField:SetText(draft.title, false)
    self.editor:SetText(draft.text, false)
    return changed
end

function Editor:MountTrackingEditor()
    local draft = self.draft
    local initialCategory = draft.trackingType
        or not draft.tracking and not draft.trackingState and categoryTrackingType(self.data, draft.categoryID) or nil
    draft.trackingExpanded = true
    self.trackingEditor = TrackingEditor.Mount(self.pages.tracking.content, draft.tracking, {
        selectionChanged = function(defaultTitle, previousTitle)
            if self.destroyed or self.draft ~= draft or not self.trackingEditor or not self.titleField or not self.editor then return end
            if not draft.tracking and not self.trackingEditor.dirty then return end
            local changed = self:UpdateTrackingTitle(defaultTitle, previousTitle)
            if changed and not self.clearing then self:LayoutEditor() end
        end,
        apply = function(tracking, defaultTitle, previousTitle)
            if self.destroyed or self.draft ~= draft then return nil, "That note is no longer open." end
            draft.title, draft.text = self.titleField:GetText(), self.editor:GetText()
            local categoryID = draft.categoryID
            if tracking and not draft.categoryChosen and (draft.index == nil or categoryID == 0) then
                categoryID = nil
                for _, category in ipairs(self.data.categories) do
                    if category.name:lower() == tracking.category:lower() then categoryID = category.id break end
                end
                if categoryID == nil then
                    local message
                    categoryID, message = Notes.AddCategory(self.data, tracking.category)
                    if categoryID == nil then return nil, message end
                end
            end
            draft.tracking = tracking and Tracking.Normalize(tracking) or nil
            draft.categoryID = categoryID
            if tracking then self:UpdateTrackingTitle(defaultTitle or tracking.label, previousTitle) end
            self.categoryField:SetEntries(self:CategoryEntries(false), draft.categoryID)
            self.titleField:SetText(draft.title, false)
            self.editor:SetText(draft.text, false)
            self:LayoutEditor()
            return true
        end,
        existingTrackings = function()
            local result = {}
            for _, note in ipairs(self.data.notes) do
                if note.tracking then result[#result + 1] = note.tracking end
            end
            return result
        end,
        addAll = function(records, category)
            local batch = Notes.New()
            local categoryID, message = Notes.AddCategory(batch, category)
            if categoryID == nil then return nil, message end
            for _, record in ipairs(records) do
                local ok
                local title, text = generatedText(record.label)
                ok, message = Notes.Put(batch, nil, text, "FFFFFF", title, "", categoryID, record.tracking)
                if not ok then return nil, message end
            end
            local categories, nextCategoryID, notes = self.data.categories, self.data.nextCategoryID, self.data.notes
            local ok
            ok, message = Notes.Import(self.data, Notes.Export(batch), true)
            if not ok then return nil, message end
            ok, message = self:Save()
            if not ok then
                self.data.categories, self.data.nextCategoryID, self.data.notes = categories, nextCategoryID, notes
                return nil, message
            end
            return true
        end,
        closed = function()
            self.trackingEditor = nil
            self.activeInput = nil
            if not self.clearing and self.draft == draft then
                draft.trackingExpanded = false
                draft.trackingState = nil
                self.pendingTrackingLayout = true
            end
        end,
        focus = function(control) self.activeInput = control end,
        layout = function(editor)
            if self.trackingEditor == editor then self:LayoutEditor(true) end
        end
    }, {x = 0, y = 0, width = self.pages.tracking.contentWidth - 16, snapshot = draft.trackingState,
        tabbed = true, randomize = draft.index == nil, category = initialCategory, actionsParent = self.surface})
    draft.trackingType = nil
    self.trackingEditor:NotifyTitle()
    self:TrackField(self.trackingEditor.target, true)
end

function Editor:CommitTracking()
    if self.trackingEditor then self.trackingEditor:FlushPending() end
    if not self.trackingEditor then return true end
    if self.trackingEditor.randomJob then
        self:Status("Wait for the random goal to finish, or change a tracking selection to cancel it.")
        self:SelectTab("tracking")
        return nil
    end
    if not self.trackingEditor.dirty then return true end
    local ok, message = self.trackingEditor:Commit()
    if not ok then
        self:Status(message)
        self:SelectTab("tracking")
        self.pages.tracking:SetScrollPosition(self.trackingEditor.root.y + self.trackingEditor.message.y)
        return nil
    end
    return true
end

Editor.Build = EditorLayout.Build
Editor.LayoutEditor = EditorLayout.Update
Editor.ClipEditorFields = EditorLayout.Clip

function Editor:Resize(width, height)
    if self.destroyed or self.width == width and self.height == height then return end
    self.width, self.height = width, height
    self:LayoutEditor(true)
end

function Editor:SaveDraft()
    if self.destroyed or self.view ~= "edit" or not self.draft or not self.editorButtons
        or not self.editor or not self.editor.root or not self.titleField or not self.titleField.root then return end
    if not self:FlushActionBar() then return end
    if not self:CommitTracking() then return end
    local draft = self.draft
    local previous = draft.index and self.data.notes[draft.index]
    local fields = {}
    for key, value in pairs(previous or {}) do fields[key] = value end
    local ok, error = Notes.Put(self.data, draft.index, self.editor:GetText(), draft.color,
        self.titleField:GetText(), draft.skill, draft.categoryID, draft.tracking or false, draft.gear or false,
        {notifyChat = draft.notifyChat == true, notifyPopup = draft.notifyPopup == true}, draft.actionBar or false)
    if not ok then self:Status(error); return end
    local saved, message = self:Save()
    if not saved then
        if previous then
            for key in pairs(previous) do previous[key] = nil end
            for key, value in pairs(fields) do previous[key] = value end
        else
            table.remove(self.data.notes)
        end
        self:Status(message)
        return
    end
    self:ShowList()
end

function Editor:TransferDraft(view)
    if not self:FlushActionBar() then return end
    if not self:CommitTracking() then return end
    local draft = self.draft
    local data = Notes.New()
    local category = Notes.FindCategory(self.data, draft.categoryID)
    if category then
        data.categories = {{id = category.id, name = category.name, skill = category.skill, color = category.color}}
        data.nextCategoryID = category.id + 1
    end
    local ok, error = Notes.Put(data, nil, self.editor:GetText(), draft.color,
        self.titleField:GetText(), draft.skill, draft.categoryID, draft.tracking or false, draft.gear or false,
        {notifyChat = draft.notifyChat == true, notifyPopup = draft.notifyPopup == true}, draft.actionBar or false)
    if not ok then self:Status(error); return end
    self:SyncDraftFields()
    self:Navigate(view, {data = data, draft = draft})
end

function Editor:Snapshot()
    local draft = self.draft
    if self.destroyed then return draft end
    local copied, message = self:FlushActionBar()
    if not copied then draft.editorStatus = message end
    self:SyncDraftFields()
    if self.actionBarEditor then draft.actionBarPreset = self.actionBarEditor.selectedPreset end
    if self.trackingEditor then draft.trackingState = self.trackingEditor:Snapshot() end
    draft.editorTab = self.activeTab
    draft.editorScrolls = {header = self.pendingEditorScrolls.header or self.header.scrollY}
    for name, page in pairs(self.pages) do
        draft.editorScrolls[name] = self.pendingEditorScrolls[name] or page.scrollY
    end
    return draft
end

function Editor:BlocksHotkey()
    return self.activeInput ~= nil or self.activeTab == "tracking" and self.trackingEditor ~= nil
        or self.activeTab == "actionBar" and self.actionBarEditor ~= nil
end

function Editor:Tick()
    if self.destroyed then return end
    if self.pendingTrackingLayout then
        self.pendingTrackingLayout = nil
        if self.activeTab == "tracking" and not self.trackingEditor then self:MountTrackingEditor() end
        self:LayoutEditor()
    end
    if self.pendingActionBar then
        self:FlushActionBar()
        if self.destroyed then return end
    end
    if self.trackingEditor and self.activeTab == "tracking" then self.trackingEditor:Tick() end
    if self.destroyed then return end
    if self.editorText and self.draft then
        local color = self.picker and self.picker.pickerWindow and self.picker.pendingColour
            or tonumber(Settings.NormalizeHex(self.draft.color), 16) * 256 + 255
        if color ~= self.editorColor then
            self.editorColor = color
            for _, text in ipairs(self.editorText) do text.rgba = color end
        end
    end
    if self.picker and self.picker.pickerWindow then
        local picker = self.picker.pickerWindow
        local x, y = Overlay.Clamp(self.parent, picker.root.x, picker.root.y, picker.root.width, picker.root.height)
        picker.root:SetPos(x, y)
    end
end

function Editor:Destroy(detached)
    if self.destroyed then return end
    self.clearing = true
    self.pendingActionBar, self.pendingTrackingLayout = nil, nil
    if self.header then self.header.onLayout = nil end
    for _, page in pairs(self.pages or {}) do page._scroll.onLayout = nil end
    if self.gearEditor then self.gearEditor:Destroy(detached); self.gearEditor = nil end
    if self.actionBarEditor then self.actionBarEditor:Destroy(detached); self.actionBarEditor = nil end
    if self.trackingEditor then
        local editor = self.trackingEditor
        self.trackingEditor = nil
        editor:Destroy(detached)
    end
    Base.DestroyControls(self, detached)
    if self.tabs then
        if detached then Detached.Control(self.tabs) else self.tabs:Destroy() end
        self.tabs, self.pages = nil, nil
    end
    if self.header then
        if detached then Detached.Control(self.header) else self.header:Destroy() end
        self.header = nil
    end
    self.window.chrome.minHeight = self.previousMinHeight
    if self.window.chrome.resize then self.window.chrome.resize.minHeight = self.previousResizeMinHeight end
    Base.Destroy(self, detached)
end

return Editor
