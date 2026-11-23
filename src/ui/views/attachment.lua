local Components = require("src/ui/shared/components")
local Base = require("src/ui/views/view")
local GearPreview = require("src/ui/attachments/gear_preview")
local ActionBarPreview = require("src/ui/attachments/action_bar_preview")
local Detached = require("src/ui/shared/detached_ui")
local WindowStyle = require("src/ui/window/window_style")

local Attachment = {}
Attachment.__index = Attachment
setmetatable(Attachment, {__index = Base})
local label = Base.Label

function Attachment.new(parent, options, callbacks)
    local self = Base.Init(setmetatable({}, Attachment), parent, options, callbacks)
    self.note = options.note
    if options.name == "gearPreview" then
        self.gearPreviewNote = self.note
        self:RenderGearAttachment()
    else
        self.actionBarPreviewNote = self.note
        self:RenderActionBarAttachment()
    end
    return self
end

function Attachment:UseEquippedGear()
    return self.callbacks.captureGear(self.note)
end

function Attachment:Destroy(detached)
    if self.destroyed then return end
    for _, key in ipairs({"gearScroll", "actionBarScroll"}) do
        if self[key] then self[key].onLayout = nil end
    end
    for _, key in ipairs({"gearPreviewReadOnly", "actionBarPreviewReadOnly"}) do
        if self[key] then self[key]:Destroy(detached); self[key] = nil end
    end
    Base.DestroyControls(self, detached)
    for _, key in ipairs({"gearScroll", "actionBarScroll"}) do
        if self[key] then
            if detached then Detached.Control(self[key]) else self[key]:Destroy() end
            self[key] = nil
        end
    end
    Base.Destroy(self, detached)
end

function Attachment:RenderGearAttachment()
    local note = self.gearPreviewNote
    self:Heading(note.title ~= "" and note.title or "Gear setup")
    self.gearScroll = prettyui.SimpleView.new(self.surface, Components.Options({
        x = 8, y = 6, width = self.width, height = math.max(1, self.height - 128), scrollStep = 40
    }))
    self.gearPreviewReadOnly = GearPreview.new(self.gearScroll.content, note.gear, {},
        {x = 0, y = 0, width = self.gearScroll.contentWidth, editable = false})
    self.gearScroll.onLayout = function()
        if self.gearPreviewReadOnly then
            if self.gearPreviewReadOnly.width ~= self.gearScroll.contentWidth then
                self.gearPreviewReadOnly:SetBounds(0, 0, self.gearScroll.contentWidth)
            end
            self.gearPreviewReadOnly:Clip(self.gearScroll.scrollY, self.gearScroll.root.height)
        end
    end
    self.gearScroll:SetContentHeight(self.gearPreviewReadOnly.height)
    self.status = label(self.surface, "", 8, self.height - 118, self.width, 36, 0xFFAA77FF)
    local capture = self:Button("Use equipped gear", 8, self.height - 74, self.width, function() self:UseEquippedGear() end)
    capture:SetTooltip("Copy your currently equipped items into an editable setup, then save the note.")
    WindowStyle.ApplyTooltip(capture.tooltip)
    local buttonWidth = math.min(90, math.floor((self.width - 8) / 2))
    local edit = self:Button("Edit gear", 8, self.height - 34, buttonWidth, function()
        for index, current in ipairs(self.data.notes) do
            if current == note then self:Edit(index); return end
        end
    end)
    local back = self:Button("Back", self.width + 8 - buttonWidth, self.height - 34, buttonWidth, function() self:ShowList() end)
    self.layout = function()
        self.gearScroll:SetSize(self.width, math.max(1, self.height - 128))
        self.gearPreviewReadOnly:SetBounds(0, 0, self.gearScroll.contentWidth)
        self.gearScroll:SetContentHeight(self.gearPreviewReadOnly.height)
        self.status:SetPos(8, self.height - 118)
        self.status:SetSize(self.width, 36)
        capture.root:SetPos(8, self.height - 74)
        capture.root:SetSize(self.width, 28)
        buttonWidth = math.min(90, math.floor((self.width - 8) / 2))
        edit.root:SetPos(8, self.height - 34)
        edit.root:SetSize(buttonWidth, 28)
        back.root:SetPos(self.width + 8 - buttonWidth, self.height - 34)
        back.root:SetSize(buttonWidth, 28)
    end
end

function Attachment:RenderActionBarAttachment()
    local note = self.actionBarPreviewNote
    self:Heading(note.title ~= "" and note.title or "Action bar")
    self.actionBarScroll = prettyui.SimpleView.new(self.surface, Components.Options({
        x = 8, y = 6, width = self.width, height = math.max(1, self.height - 50), scrollStep = 40
    }))
    self.actionBarPreviewReadOnly = ActionBarPreview.new(self.actionBarScroll.content, note.actionBar, {},
        {x = 0, y = 0, width = self.actionBarScroll.contentWidth, editable = false})
    self.actionBarScroll.onLayout = function()
        local preview = self.actionBarPreviewReadOnly
        if not preview then return end
        if preview.width ~= self.actionBarScroll.contentWidth then
            preview:SetBounds(0, 0, self.actionBarScroll.contentWidth)
        end
        preview:Clip(self.actionBarScroll.scrollY, self.actionBarScroll.root.height)
    end
    self.actionBarScroll:SetContentHeight(self.actionBarPreviewReadOnly.height)
    local buttonWidth = math.min(110, math.floor((self.width - 8) / 2))
    local edit = self:Button("Edit action bar", 8, self.height - 34, buttonWidth, function()
        for index, current in ipairs(self.data.notes) do
            if current == note then self:Edit(index); return end
        end
    end)
    local back = self:Button("Back", self.width + 8 - buttonWidth, self.height - 34, buttonWidth, function() self:ShowList() end)
    self.layout = function()
        self.actionBarScroll:SetSize(self.width, math.max(1, self.height - 50))
        self.actionBarPreviewReadOnly:SetBounds(0, 0, self.actionBarScroll.contentWidth)
        self.actionBarScroll:SetContentHeight(self.actionBarPreviewReadOnly.height)
        buttonWidth = math.min(110, math.floor((self.width - 8) / 2))
        edit.root:SetPos(8, self.height - 34)
        edit.root:SetSize(buttonWidth, 28)
        back.root:SetPos(self.width + 8 - buttonWidth, self.height - 34)
        back.root:SetSize(buttonWidth, 28)
    end
end

return Attachment
