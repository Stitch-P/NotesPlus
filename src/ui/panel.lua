local Notes = require("src/notes/notes")
local Settings = require("src/core/settings")
local Overlay = require("src/ui/window/overlay")
local Tracking = require("src/tracking/model")
local Gear = require("src/notes/gear")
local ActionBar = require("src/notes/action_bar")
local NoteList = require("src/ui/views/note_list")
local NoteEditor = require("src/ui/views/note_editor")
local CategoryEditor = require("src/ui/views/category_editor")
local Transfer = require("src/ui/views/transfer")
local ShareSelection = require("src/ui/views/share_selection")
local Attachment = require("src/ui/views/attachment")
local SpriteBrowser = require("src/ui/views/sprite_browser")
local Journal = require("src/ui/views/journal")

local Panel = {}
Panel.__index = Panel

local views = {
    list = NoteList, journal = Journal, edit = NoteEditor, category = CategoryEditor,
    share = Transfer, shareSelect = ShareSelection, copy = Transfer, import = Transfer,
    gearPreview = Attachment, actionBarPreview = Attachment,
    sprites = SpriteBrowser, categorySprites = SpriteBrowser, gearItems = SpriteBrowser
}

function Panel.new(parent, settings, data, callbacks)
    local self = setmetatable({parent = parent, settings = settings, data = data,
        callbacks = callbacks, view = "list", listState = {query = "", scroll = 0}}, Panel)
    self:MountWindow()
    self:Render()
    self.window:SetPosition(settings.notesX, settings.notesY)
    return self
end

function Panel:MountWindow()
    self.parentWidth, self.parentHeight = self.parent.width, self.parent.height
    self.window = Overlay.Mount(self.parent, self.settings, self.callbacks.close, function(width, height, x, y)
        self:Resize(width, height, x, y)
    end, function(x, y)
        if self.editorGeometry then
            self.editorGeometry.currentX, self.editorGeometry.currentY = x, y
            self:RestoreEditorSettings()
        elseif self.callbacks.move then self.callbacks.move(x, y) end
    end)
end

function Panel:RestoreEditorSettings()
    local geometry = self.editorGeometry
    if not geometry then return end
    self.settings.notesWidth, self.settings.notesHeight = geometry.notesWidth, geometry.notesHeight
    self.settings.notesResized = geometry.notesResized
    self.settings.notesX, self.settings.notesY = geometry.notesX, geometry.notesY
end

function Panel:BeginEditing()
    if self.editorGeometry then return end
    self.window:SyncResize()
    local x, y = self.window:GetPosition(true)
    self.editorGeometry = {
        width = self.window.root.width, height = self.window.root.height, x = x, y = y,
        notesWidth = self.settings.notesWidth, notesHeight = self.settings.notesHeight,
        notesResized = self.settings.notesResized, notesX = self.settings.notesX, notesY = self.settings.notesY,
        currentWidth = math.min(math.max(self.window.root.width, 1000), 1400),
        currentHeight = 680, currentX = x, currentY = y,
    }
end

function Panel:EndEditing()
    if not self.editorGeometry then return end
    self:RestoreEditorSettings()
    self.restoringGeometry = self.editorGeometry
    self.editorGeometry = nil
end

function Panel:Resize(width, height, x, y, anchor)
    if self.destroyed then return end
    if anchor and self.activeView then
        self.activeView:Resize(self.window.width - 16, self.window.height)
        local point = anchor.target.xyGlobal
        self.window:SetPosition(self.window.root.x + anchor.x - point.x - anchor.target.width / 2,
            self.window.root.y + anchor.y - point.y - anchor.target.height / 2)
        x, y = self.window.root.x, self.window.root.y
    end
    if self.editorGeometry then
        self.editorGeometry.manuallyResized = true
        self.editorGeometry.currentWidth, self.editorGeometry.currentHeight = width, height
        self.editorGeometry.currentX, self.editorGeometry.currentY = x, y
        self:RestoreEditorSettings()
    else
        self.settings.notesWidth = Settings.ClampInt(width, 200, 1400, self.settings.notesWidth)
        self.settings.notesHeight = Settings.ClampInt(height, 200, 1000, self.settings.notesHeight)
        self.settings.notesResized = true
        if self.callbacks.resize then
            self.callbacks.resize(self.settings.notesWidth, self.settings.notesHeight, x, y)
        end
    end
    if self.activeView and not anchor then self.activeView:Resize(self.window.width - 16, self.window.height) end
end

function Panel:FitEditor(height)
    local geometry = self.editorGeometry
    if not geometry or geometry.manuallyResized then return end
    geometry.currentHeight = math.min(math.max(680, math.ceil(height)), 1000)
    self.window:SetHeight(geometry.currentHeight)
end

function Panel:Save()
    local ok, message = Notes.Save(self.data)
    if not ok then return nil, message end
    self.listState.saveError = nil
    if self.callbacks.notesSaved then self.callbacks.notesSaved() end
    return true
end

function Panel:SnapshotActive()
    local view = self.activeView
    if not view or view.destroyed then return end
    local snapshot = view:Snapshot()
    if view.view == "edit" then self.draft = snapshot
    elseif view.view == "category" then self.categoryDraft = snapshot
    elseif view.view == "shareSelect" then self.shareSelection = snapshot
    elseif view.view == "share" or view.view == "copy" or view.view == "import" then
        self.transferText = snapshot.text
        if view.view == "import" then self.importSession = snapshot.importSession end
    end
end

function Panel:Clear(detached)
    self.viewToken = nil
    local view = self.activeView
    self.activeView = nil
    if view then view:Destroy(detached) end
end

function Panel:NewDraft(index)
    local note = index and self.data.notes[index]
    return {index = index, title = note and note.title or "", text = note and note.text or "",
        skill = note and note.skill or "", color = note and note.color or "FFFFFF",
        categoryID = note and note.categoryID or self.listState.categoryID or 0,
        tracking = note and Tracking.Normalize(note.tracking), gear = note and Gear.Normalize(note.gear),
        actionBar = note and ActionBar.Normalize(note.actionBar),
        notifyChat = note and note.notifyChat == true or false,
        notifyPopup = note and note.notifyPopup == true or false}
end

function Panel:Navigate(name, payload)
    if self.destroyed or not views[name] then return end
    payload = payload or {}
    local category
    if name == "category" and not payload.draft then
        category = Notes.FindCategory(self.data, payload.id)
        if payload.id ~= nil and category == nil then return end
    end
    self:SnapshotActive()
    if name == "edit" then self:BeginEditing()
    elseif self.editorGeometry and name ~= "sprites" and name ~= "gearItems"
        and not ((name == "share" or name == "copy") and payload.draft) then self:EndEditing() end
    if name == "list" then
        self.draft, self.transferData, self.attachmentNote = nil, nil, nil
        self.shareSelection = nil
        self.importSession = nil
    elseif name == "edit" then
        self.transferData = nil
        self.shareSelection = nil
        self.draft = payload.draft or self:NewDraft(payload.index)
    elseif name == "category" then
        local skill = category and category.skill
        if not category then skill = "" end
        self.categoryDraft = payload.draft or {id = payload.id, name = category and category.name or "",
            skill = skill, color = category and category.color}
    elseif name == "shareSelect" then
        self.transferData, self.shareSelection = nil, payload.selection
    elseif name == "share" or name == "copy" or name == "import" then
        self.transferData, self.transferText = payload.data, ""
        self.importSession = nil
        self.shareSelection = name == "share" and payload.selection or nil
        if payload.draft then self.draft = payload.draft end
    elseif name == "gearPreview" or name == "actionBarPreview" then
        self.attachmentNote = payload.note
    elseif name == "categorySprites" then
        self.categoryDraft = payload.draft or self.categoryDraft
    else
        self.draft, self.gearSlot = payload.draft or self.draft, payload.slot
    end
    self.view = name
    self:Render(true)
    if name == "edit" and self.activeView then
        if payload.action == "color" then self.activeView.picker:Open()
        elseif payload.action == "delete" then
            self.draft.confirmDelete = true
            self.activeView:Status("Press Delete to remove this note.")
        end
    end
end

function Panel:ShowList() self:Navigate("list") end
function Panel:Edit(index) self:Navigate("edit", {index = index}) end
function Panel:EditCategory(categoryID) self:Navigate("category", {id = categoryID}) end

function Panel:Render(skipSnapshot)
    if self.destroyed then return end
    if not skipSnapshot then self:SnapshotActive() end
    self:Clear()
    self.window.chrome:SetTitle("Notes-Plus")
    local geometry = self.restoringGeometry or self.editorGeometry
    if geometry then
        if self.restoringGeometry then
            self.restoringGeometry = nil
            self.window:SetSize(geometry.width, geometry.height)
            self.window:SetPosition(geometry.x, geometry.y)
        else
            self.window:SetSize(geometry.currentWidth, geometry.currentHeight)
            self.window:SetPosition(geometry.currentX, geometry.currentY)
        end
    else self.window:SetHeight((self.view == "list" or self.view == "journal" or self.settings.notesResized) and self.settings.notesHeight or 360) end
    self.window:SetJournal(self.view == "journal")
    local token = {}
    self.viewToken = token
    local function current() return not self.destroyed and self.viewToken == token end
    local callbacks = {
        save = function()
            if current() then return self:Save() end
            return nil, "That notes window is no longer open."
        end,
        rebuild = function() if current() then self:Render() end end,
        fitEditor = function(height) if current() then self:FitEditor(height) end end,
        resizeWindow = function(width, height, anchor)
            if not current() then return end
            local previousWidth, previousHeight = self.window.root.width, self.window.root.height
            self.window:SetSize(width, height)
            local root = self.window.root
            if root.width == previousWidth and root.height == previousHeight then return end
            self.window:SetPosition(root.x, root.y)
            self:Resize(root.width, root.height, root.x, root.y, anchor)
        end,
        navigate = function(name, payload) if current() then self:Navigate(name, payload) end end,
        captureGear = function(note) if current() then self:CaptureGear(note) end end
    }
    local options = {parent = self.parent, window = self.window, data = self.data, settings = self.settings,
        name = self.view, width = self.window.width - 16, height = self.window.height, state = self.listState,
        draft = (self.view == "category" or self.view == "categorySprites") and self.categoryDraft or self.draft,
        note = self.attachmentNote, text = self.transferText, transferData = self.transferData, slot = self.gearSlot,
        selection = self.shareSelection, importSession = self.importSession}
    self.activeView = assert(views[self.view], "Unknown notes view").new(self.window.body, options, callbacks)
end

function Panel:CaptureGear(note)
    local index
    for currentIndex, current in ipairs(self.data.notes) do
        if current == note then index = currentIndex; break end
    end
    if not index then return end
    local gear, message = Gear.CaptureEquipped()
    if not gear then self.activeView:Status(message); return end
    self:SnapshotActive()
    self.draft = self:NewDraft(index)
    self.draft.gear, self.draft.editorTab = gear, "gear"
    self.draft.editorStatus = "Copied " .. Gear.Count(gear) .. " items. Press Save to keep them."
    self:BeginEditing()
    self.view, self.transferData = "edit", nil
    self:Render(true)
end

function Panel:GetActiveView() return self.activeView end

function Panel:GetSpriteBrowser()
    return self.activeView and self.activeView.spriteBrowser
end

function Panel:BlocksHotkey()
    return self.window:IsDragging() or (self.activeView and self.activeView:BlocksHotkey()) or false
end

function Panel:RefreshTracking(skipLayout)
    local view = self.activeView
    if view and view.RefreshTracking then view:RefreshTracking(skipLayout) end
end

function Panel:AddContextMenu(miniMenu)
    local view = self.activeView
    if view and view.AddContextMenu then view:AddContextMenu(miniMenu) end
end

function Panel:Update(settings)
    if self.destroyed then return end
    local subjectsChanged = settings.showSubject ~= self.settings.showSubject
    local barsChanged = settings.showProgressBars ~= self.settings.showProgressBars
    local displayOnly = true
    for key, value in pairs(self.settings) do
        if key ~= "showProgressBars" and key ~= "showSubject" and settings[key] ~= value then
            displayOnly = false
            break
        end
    end
    if displayOnly then
        self.settings, self.window.settings = settings, settings
        if self.parent.width ~= self.parentWidth or self.parent.height ~= self.parentHeight then
            self.parentWidth, self.parentHeight = self.parent.width, self.parent.height
            local geometry = self.editorGeometry
            self.window:SetSize(geometry and geometry.currentWidth or settings.notesWidth,
                geometry and geometry.currentHeight
                    or ((self.view == "list" or self.view == "journal" or settings.notesResized) and settings.notesHeight or 360))
            if self.activeView then self.activeView:Resize(self.window.width - 16, self.window.height) end
        end
        if self.activeView then
            self.activeView.settings = settings
            if self.activeView.view == "list" then
                local subjectsUpdated = subjectsChanged and self.activeView:UpdateSubjects()
                if barsChanged then self.activeView:UpdateProgressBars() end
                if subjectsUpdated or barsChanged then self.activeView:LayoutRows(nil, true) end
            end
        end
        return
    end
    local x, y = self.window:GetPosition(true)
    self:SnapshotActive()
    self:Clear()
    self.window:Destroy()
    self.settings = settings
    self:RestoreEditorSettings()
    self:MountWindow()
    self:Render(true)
    self.window:SetPosition(x, y)
end

function Panel:Tick()
    if self.destroyed then return end
    self.window:SyncResize()
    if self.activeView then self.activeView:Tick() end
    if self.destroyed then return end
    self.window:ClampPosition()
end

function Panel:Destroy(detached)
    if self.destroyed then return end
    self:RestoreEditorSettings()
    self.editorGeometry, self.restoringGeometry = nil, nil
    self.destroyed = true
    self:Clear(detached)
    self.window:Destroy(detached)
end

return Panel
