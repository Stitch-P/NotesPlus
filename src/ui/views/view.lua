local Components = require("src/ui/shared/components")
local Settings = require("src/core/settings")
local WindowStyle = require("src/ui/window/window_style")
local Detached = require("src/ui/shared/detached_ui")

local View = {}

function View.Init(self, parent, options, callbacks)
    self.parent, self.window = options.parent, options.window
    self.data, self.settings = options.data, options.settings
    self.width, self.height, self.view = options.width, options.height, options.name
    self.state, self.callbacks, self.controls = options.state or {}, callbacks or {}, {}
    self.surface = Components.Host(parent)
    self.surface:SetSize(self.window.width, self.height)
    self.surface.clickthrough = false
    self.root = self.surface
    local tooltipParent = self.parent
    if self.view == "list" or self.view == "journal" then
        self.tooltipOwner = Components.Host(self.parent)
        self.tooltipOwnerInterfaceID = self.tooltipOwner.interfaceID
        self.tooltipOwner:SetSize(0, 0, 1, 1)
        self.tooltipOwner.clickthrough = true
        self.window.chrome:_RegisterOverlay(self.tooltipOwner)
        tooltipParent = self.tooltipOwner
    end
    local context = prettyui.Tooltip.registerContext(self.surface, tooltipParent, function(target)
        local point, base = target.xyGlobal, self.parent.xyGlobal
        local x, y = point.x - base.x, point.y - base.y
        local ancestor = target.parent
        while ancestor and ancestor ~= self.parent do
            x, y = x - (ancestor.scrollX or 0), y - (ancestor.scrollY or 0)
            ancestor = ancestor.parent
        end
        return x, y
    end)
    context.ownerWindow = self.window.chrome
    return self
end

function View.Label(parent, text, x, y, width, height, color, font)
    local component = prettyui.Text.new(parent, Components.Options({text = text, x = x, y = y, width = width, height = height,
        font = font or id.Font.MUSEO_SANS_13PT_REGULAR, colour = color or 0xE7D7B0FF,
        maxLines = 0, shadowed = true}))
    component.clickthrough = true
    return component
end

function View.NoteFont(settings)
    local size = Settings.ClampInt(settings.fontSize, 10, 24, 14)
    return "NOTOSANS_" .. size, size
end

function View.EditorFrame(parent, width)
    local root = Components.New(ui.Layer, parent)
    root:SetSize(width, 54)
    root.clickthrough = true
    local parts = prettyui.Sprites.CONTENT_FRAME
    local rows = {{parts.topLeft, parts.top, parts.topRight}, {parts.left, parts.centre, parts.right},
        {parts.bottomLeft, parts.bottom, parts.bottomRight}}
    for row, sprites in ipairs(rows) do
        for column, spriteID in ipairs(sprites) do
            local sprite = Components.New(ui.Sprite, root)
            sprite.spriteID, sprite.clickthrough = spriteID, true
            sprite.isTiling = row == 2 or column == 2
            sprite:SetPos(column == 1 and 0 or (column == 2 and 10 or -10),
                row == 1 and 0 or (row == 2 and 10 or -10), column == 3 and 1 or 0, row == 3 and 1 or 0)
            sprite:SetSize(column == 2 and -20 or 10, row == 2 and -20 or 10,
                column == 2 and 1 or 0, row == 2 and 1 or 0)
        end
    end
    return root
end

function View:Track(control)
    self.controls[#self.controls + 1] = control
    return control
end

function View:TrackField(field, managed)
    if not managed then self:Track(field) end
    -- Inputs must draw above their decorative frames across allocation categories.
    field.root:MoveToFront()
    field.root:Subscribe(ui.Hook.ONCLICK, "notes_hotkey_focus", function()
        self.activeInput = field
        return true
    end)
    local onChange = field.onChange
    function field.onChange(control, reason, value)
        if self.destroyed or self.clearing then return end
        if reason == ui.InputFieldActionResult.SUBMIT_ON_FOCUS_LOSS and self.activeInput == field then self.activeInput = nil end
        if onChange then onChange(control, reason, value) end
    end
    return field
end

function View:Button(text, x, y, width, action)
    return self:Track(prettyui.SimpleButton.new(self.surface, text, function(...)
        if not self.destroyed and not self.clearing then return action(...) end
    end, Components.Options({x = x, y = y, width = width, height = 28})))
end

function View:Field(text, x, y, width, height, maxLength, onChange)
    local field = self:TrackField(prettyui.TextField.new(self.surface, Components.Options({x = x, y = y, width = width, height = height,
        text = text, maxLength = maxLength, onChange = function(control, _, value)
            if onChange then onChange(control, value) end
        end})))
    WindowStyle.ApplyInput(field.root)
    field.root.text.maxLines = height > 30 and 0 or 1
    field.root.scrollbar.visible, field.root.scrollbar.size = false, 0
    return field
end

function View:Heading(text) self.window.chrome:SetTitle(text) end
local ALERT_COLOUR = 0xFF3333FF
-- alert: show the message in red so it catches the eye (the next plain status goes back to the label's own colour).
function View:Status(text, alert)
    if not self.status then return end
    self.status.content = text or ""
    local status = self.status
    if self.statusBaseFor ~= status then
        local ok, colour = pcall(function() return status.rgba end)
        self.statusBaseFor, self.statusBaseColour = status, ok and colour or nil
    end
    local colour = alert and ALERT_COLOUR or self.statusBaseColour
    if colour ~= nil then pcall(function() status.rgba = colour end) end
end

function View:Save() return self.callbacks.save() end
function View:Render() return self.callbacks.rebuild() end
function View:Navigate(name, payload) return self.callbacks.navigate(name, payload) end
function View:ShowList() return self:Navigate("list") end
function View:Edit(index, action) return self:Navigate("edit", {index = index, action = action}) end
function View:EditCategory(categoryID) return self:Navigate("category", {id = categoryID}) end

function View:CategoryEntries(includeAll)
    local counts, entries = {}, {}
    for _, note in ipairs(self.data.notes) do
        local categoryID = note.categoryID or 0
        counts[categoryID] = (counts[categoryID] or 0) + 1
    end
    if includeAll then entries[#entries + 1] = {id = -1, label = "All notes (" .. #self.data.notes .. ")"} end
    for _, category in ipairs(self.data.categories) do
        entries[#entries + 1] = {id = category.id,
            label = category.name .. (includeAll and (" (" .. (counts[category.id] or 0) .. ")") or "")}
    end
    entries[#entries + 1] = {id = 0,
        label = "Uncategorized" .. (includeAll and (" (" .. (counts[0] or 0) .. ")") or "")}
    for index, entry in ipairs(entries) do entry.order = index end
    return entries
end

function View:Resize(width, height)
    if self.destroyed then return end
    self.width, self.height = width, height
    self.surface:SetSize(self.window.width, height)
    if self.layout then self.layout() end
end

function View:Snapshot() return self.state end
function View:BlocksHotkey() return self.activeInput ~= nil end
function View:Tick() end

function View:DestroyControls(detached)
    for index = #self.controls, 1, -1 do
        if detached then Detached.Control(self.controls[index]) else self.controls[index]:Destroy() end
    end
    self.controls = {}
end

function View:Destroy(detached)
    if self.destroyed then return end
    self.destroyed, self.clearing, self.activeInput = true, true, nil
    if self.tooltipOwner then self.window.chrome:_UnregisterOverlay(self.tooltipOwner) end
    if detached then Detached.Tooltips(self.surface) end
    self:DestroyControls(detached)
    prettyui.Tooltip.unregisterContext(self.surface)
    if not detached then self.surface:Destroy() end
    if self.tooltipOwner and ui.Interfaces:GetInterface(self.tooltipOwnerInterfaceID) ~= nil then
        self.tooltipOwner:Destroy()
    end
    self.tooltipOwner, self.tooltipOwnerInterfaceID = nil, nil
    self.surface, self.root, self.layout = nil, nil, nil
end

return View
