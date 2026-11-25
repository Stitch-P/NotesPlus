local Components = require("src/ui/shared/components")
local WindowStyle = require("src/ui/window/window_style")
local Detached = require("src/ui/shared/detached_ui")
local Appearance = require("src/ui/categories/category_appearance")
local Tracking = require("src/tracking/model")
local Sprites = require("src/data/sprite_catalog")
local CategoryDrag = require("src/ui/categories/category_drag")

local Sidebar = {}
Sidebar.__index = Sidebar

local ROW_HEIGHT = 32
local GROUP_GAP = 6
local TEXT = 0xD8D1C4FF
local MUTED = 0xA69D8CFF
local GOLD = 0xF2C66DFF
local FONT = id.Font.MUSEO_SANS_13PT_REGULAR
local SELECTED = 0x4B3C1BFF
local HOVER = 0xFFFFFF08

local function plain(value)
    return tostring(value or ""):gsub("<[Bb][Rr]%s*/?>", " "):gsub("<", "["):gsub(">", "]"):gsub("[\r\n]", " ")
end

local function origin(component, parent)
    local point, base = component.xyGlobal, parent.xyGlobal
    local x, y = point.x - base.x, point.y - base.y
    local ancestor = component.parent
    while ancestor and ancestor ~= parent do
        x, y = x - (ancestor.scrollX or 0), y - (ancestor.scrollY or 0)
        ancestor = ancestor.parent
    end
    return x, y
end

local function text(parent, value, colour)
    local component = prettyui.Text.new(parent, Components.Options({
        text = value, width = 1, height = ROW_HEIGHT, font = FONT,
        colour = colour or TEXT, maxLines = 1, shadowed = true
    }))
    component.clickthrough = true
    return component
end

local function rectangle(parent, colour)
    local component = Components.New(ui.Rectangle, parent)
    component.fill = true
    component.rgba = colour
    component.clickthrough = true
    return component
end

local function measure(value)
    local success, width = pcall(function()
        return config.Font.MUSEO_SANS_13PT_REGULAR:GetStringWidth(value, false)
    end)
    return success and width or #value * 7
end

local function clippedText(value, width)
    if measure(value) <= width then return value, false end
    local characters = {}
    for character in value:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        characters[#characters + 1] = character
    end
    while #characters > 0 do
        characters[#characters] = nil
        local shortened = table.concat(characters) .. "..."
        if measure(shortened) <= width then return shortened, true end
    end
    return "", true
end

local function rowButton(parent, action)
    local button = {root = Components.New(ui.Layer, parent), action = action}
    button.interfaceID = button.root.interfaceID
    button.root.clickthrough = false
    function button:Destroy()
        prettyui.Tooltip.unbind(self)
        if self.root then
            if ui.Interfaces:GetInterface(self.interfaceID) ~= nil then self.root:Destroy() end
            self.root = nil
        end
        self.action = nil
    end
    return button
end

local function applyRowIcon(row)
    if row.category then return Appearance.Apply(row.icon, row.category) end
    Sprites.Clear(row.icon)
    local name = row.categoryID == nil and "RS3_MENU_ICON_NOTES_NORMAL" or "RS3_MENU_ICON_BACKPACK_NORMAL"
    local spriteID = Sprites.SpriteID(name)
    if not spriteID then return false end
    row.icon.spriteID = spriteID
    row.icon.rgba = GOLD
    row.icon.hidden = false
    return true
end

function Sidebar.new(parent, data, selectedID, callbacks, options)
    options = options or {}
    local self = setmetatable({rows = {}, selectedID = selectedID,
        callbacks = callbacks or {}, inputOwner = options.inputOwner}, Sidebar)
    self.root = Components.Host(parent)
    self.root:SetPos(options.x or 8, options.y or 6)
    self.root.clickthrough = false
    local context = prettyui.Tooltip.getContext(parent)
    self.overlayParent = context and context.parent or parent
    if context then
        prettyui.Tooltip.registerContext(self.root, context.parent, context.position, context)
    end
    self.heading = text(self.root, "Categories", GOLD)
    self.divider = rectangle(self.root, 0xC9AF6A55)
    self.headerLine = rectangle(self.root, 0xC9AF6A33)
    self.headerLine.hidden = true
    self.editButton = prettyui.SimpleButton.new(self.root, Sprites.SpriteID("RS3_MENU_ICON_NOTES_NORMAL") or "...", function()
        if not self.destroyed and type(self.selectedID) == "number" and self.selectedID > 0
            and self.callbacks.edit then self.callbacks.edit(self.selectedID) end
    end, Components.Options({width = 26, height = 24, tooltip = "Edit or delete category"}))
    if self.editButton.contentType ~= "number" then pcall(function() self.editButton.content.font = FONT end) end
    WindowStyle.ApplyTooltip(self.editButton.tooltip)
    self.scroll = prettyui.SimpleView.new(self.root, Components.Options({x = 0, y = 36,
        width = options.width or 160, height = 1, scrollStep = ROW_HEIGHT}))
    self.scroll.onLayout = function()
        if self.destroyed then return end
        prettyui.Tooltip.hideContextTooltips(self.scroll.content)
        self:LayoutRows()
    end
    self.newButton = prettyui.SimpleButton.new(self.root, "+ New category", function()
        if not self.destroyed and self.callbacks.new then self.callbacks.new() end
    end, Components.Options({width = options.width or 160, height = 28}))
    self.newButton.content.font = FONT
    self.newButton:SetTooltip("New category")
    WindowStyle.ApplyTooltip(self.newButton.tooltip)
    self.resetButton = prettyui.SimpleButton.new(self.root,
        Sprites.SpriteID("RS3_ICON_LOBBY_REFRESH_0") or "R", function()
            if not self.destroyed and self.callbacks.reset then self.callbacks.reset() end
        end, Components.Options({width = 28, height = 28,
            tooltip = "Restore missing default categories and Scheduled notes. Keeps existing notes and settings."}))
    WindowStyle.ApplyTooltip(self.resetButton.tooltip)
    local counts = {}
    for _, note in ipairs(data.notes or {}) do
        local categoryID = note.categoryID or 0
        counts[categoryID] = (counts[categoryID] or 0) + 1
    end
    self:AddRow(nil, "All notes", #(data.notes or {}))
    for _, category in ipairs(data.categories or {}) do
        self:AddRow(category.id, category.name, counts[category.id] or 0, category)
    end
    self:AddRow(0, "Uncategorized", counts[0] or 0)
    self:MountInput()
    self.iconRevision = Tracking.IconRevision()
    self.scroll:SetContentHeight(#self.rows * ROW_HEIGHT + (#self.rows > 2 and 2 or 1) * GROUP_GAP)
    self:UpdateSelection()
    self:Resize(options.width or 160, options.height or 240)
    if options.scrollY then self.scroll:SetScrollPosition(options.scrollY) end
    return self
end

function Sidebar:AddRow(categoryID, name, count, category)
    local row = {categoryID = categoryID, name = plain(name), count = tostring(count), category = category}
    row.button = rowButton(self.scroll.content, function()
        if self.destroyed then return end
        self.selectedID = categoryID
        self:UpdateSelection()
        if self.callbacks.select then self.callbacks.select(categoryID) end
    end)
    row.root = row.button.root
    row.root:SetPos(0, #self.rows * ROW_HEIGHT)
    row.background = rectangle(row.root, 0xFFFFFF00)
    row.background:SetSize(0, 0, 1, 1)
    row.selectedBar = rectangle(row.root, GOLD)
    row.selectedBar:SetSize(2, -8, 0, 1)
    row.selectedBar:SetPos(0, 4)
    row.separator = rectangle(row.root, categoryID == 0 and 0x8E79494A or 0x8E794929)
    row.separator:SetPos(6, categoryID == 0 and 0 or ROW_HEIGHT - 1)
    row.separator.hidden = categoryID == nil
    row.icon = Components.New(ui.Sprite, row.root)
    row.icon:SetPos(8, 6)
    row.icon:SetSize(20, 20)
    row.icon.clickthrough = true
    row.hasIcon = applyRowIcon(row)
    row.nameLabel = text(row.root, row.name)
    row.countLabel = text(row.root, row.count, MUTED)
    row.countLabel.alignHorizontal = ui.AlignMode.BOTTOMRIGHT
    local function updateHover(hovered)
        if self.destroyed then return end
        row.hovered = hovered
        row.background.rgba = row.selected and SELECTED or (hovered and HOVER or 0xFFFFFF00)
    end
    row.root:Subscribe(ui.Hook.ONMOUSEOVER, "notes_category_hover", function()
        updateHover(true)
        return true
    end)
    row.root:Subscribe(ui.Hook.ONMOUSELEAVE, "notes_category_hover", function()
        updateHover(false)
        return true
    end)
    row.root:Subscribe(ui.Hook.ONSCROLLWHEEL, function(_, rotation)
        if not self.destroyed then self.scroll:ScrollBy(rotation * ROW_HEIGHT) end
        return false
    end)
    prettyui.Tooltip.bind(row.button, row.root, self.scroll.content,
        Components.Options({text = row.name, placement = "right", maxWidth = 280}))
    WindowStyle.ApplyTooltip(row.button.tooltip)
    local show = row.button.tooltip.Show
    function row.button.tooltip.Show(tooltip)
        if self.destroyed or self.drag or not row.clipped then return end
        local top = row.root.y - self.scroll.scrollY
        if top < 0 or top + ROW_HEIGHT > self.scroll.root.height then return end
        show(tooltip)
    end
    self.rows[#self.rows + 1] = row
end

function Sidebar:InputRow(component, x, y)
    if type(x) ~= "number" or type(y) ~= "number" then return end
    local left, top = origin(component, self.overlayParent)
    local viewportX, viewportY = origin(self.scroll.root, self.overlayParent)
    x, y = left + x - viewportX, top + y - viewportY
    if x < 0 or x >= self.scroll.contentWidth or y < 0 or y >= self.scroll.root.height then return end
    local contentY = y + self.scroll.scrollY
    for _, row in ipairs(self.rows) do
        if contentY >= row.root.y and contentY < row.root.y + row.root.height then return row end
    end
end

function Sidebar:HoverRow(row)
    if self.destroyed then return end
    if self.drag then row = nil end
    for _, candidate in ipairs(self.rows) do
        local hovered = candidate == row
        candidate.hovered = hovered
        candidate.background.rgba = candidate.selected and SELECTED or (hovered and HOVER or 0xFFFFFF00)
        if not hovered then candidate.button.tooltip:Hide() end
    end
    if row then row.button.tooltip:Show() end
end

function Sidebar:LayoutInput()
    if self.destroyed or not self.hit then return end
    if self.drag and self.drag.moved then
        self.hit:SetPos(0, 0)
        self.hit:SetSize(self.overlayParent.width, self.overlayParent.height)
    else
        local x, y = origin(self.scroll.root, self.overlayParent)
        self.hit:SetPos(x, y)
        self.hit:SetSize(self.scroll.contentWidth, self.scroll.root.height)
    end
end

function Sidebar:MountInput()
    self.hit = Components.New(ui.Layer, self.overlayParent)
    self.hit.clickthrough = false
    self.inputOwner = self.inputOwner or self.scroll.ownerWindow
    if self.inputOwner then
        self.inputOwner:_RegisterOverlay(self.hit, function() return not self.destroyed end,
            function() self:LayoutInput() end)
    end
    self.hit:MoveToFront()
    self.hit:Subscribe(ui.Hook.ONCLICK, function(component, x, y)
        if self.destroyed or self.drag then return false end
        local row = self:InputRow(component, x, y)
        if row then
            if row.category then self.drag = CategoryDrag.new(self, row, component, x, y)
            else row.button.action() end
        end
        return false
    end)
    local function move(component, x, y)
        if self.drag then self.drag:Pointer(component, x, y) end
        return false
    end
    self.hit:Subscribe(ui.Hook.ONHOLD, move)
    self.hit:Subscribe(ui.Hook.ONDRAG, move)
    self.hit:Subscribe(ui.Hook.ONRELEASE, function(component, x, y)
        if self.drag then self.drag:Finish(component, x, y) end
        return false
    end)
    self.hit:Subscribe(ui.Hook.ONDRAGCOMPLETE, function(component, _, x, y)
        if self.drag then self.drag:Finish(component, x, y) end
        return false
    end)
    local function hover(component, x, y)
        self:HoverRow(self:InputRow(component, x, y))
        return true
    end
    self.hit:Subscribe(ui.Hook.ONMOUSEOVER, hover)
    self.hit:Subscribe(ui.Hook.ONMOUSEREPEAT, hover)
    self.hit:Subscribe(ui.Hook.ONMOUSELEAVE, function() self:HoverRow(nil); return true end)
    self.hit:Subscribe(ui.Hook.ONSCROLLWHEEL, function(_, rotation)
        if not self.destroyed then self.scroll:ScrollBy(rotation * ROW_HEIGHT) end
        return false
    end)
    self:LayoutInput()
end

function Sidebar:UpdateSelection()
    if self.destroyed then return end
    for _, row in ipairs(self.rows) do
        row.selected = row.categoryID == self.selectedID
        row.nameLabel.rgba = Appearance.Color(row.category,
            row.selected and GOLD or (row.categoryID == 0 and 0xBDB4A4FF or TEXT))
        row.countLabel.rgba = row.selected and GOLD or MUTED
        row.selectedBar.hidden = not row.selected
        row.background.rgba = row.selected and SELECTED or (row.hovered and HOVER or 0xFFFFFF00)
    end
    self.editButton.root.hidden = false
    local disabled = type(self.selectedID) ~= "number" or self.selectedID <= 0
    self.editButton:SetDisabled(disabled)
    -- Faded out while All notes / Uncategorized is selected, as there is nothing to edit.
    pcall(function() self.editButton.root.alpha = disabled and 0.35 or 1 end)
end

-- Right-clicking one of your own categories offers to edit or delete it (All notes and Uncategorized have neither).
-- Returns true when the menu was filled, so the note list doesn't add its own entries as well.
function Sidebar:AddContextMenu(miniMenu)
    if self.destroyed or self.drag or not self.callbacks.edit then return false end
    -- The row under the mouse, worked out from where the mouse is: the hover state is already cleared by the time the
    -- right-click menu opens (the menu appearing counts as the mouse leaving the sidebar).
    local row
    if self.hit then
        local ok, found = pcall(function()
            local mouse, origin = Mouse.GetPosition(), self.hit.xyGlobal
            return self:InputRow(self.hit, mouse.x - origin.x, mouse.y - origin.y)
        end)
        if ok then row = found end
    end
    if not row then
        for _, candidate in ipairs(self.rows) do if candidate.hovered then row = candidate break end end
    end
    if row and type(row.categoryID) == "number" and row.categoryID > 0 then
        local categoryID = row.categoryID
        miniMenu:Add("Edit category", function()
            if not self.destroyed and self.callbacks.edit then self.callbacks.edit(categoryID) end
        end)
        if self.callbacks.delete then
            miniMenu:Add("Delete category", function()
                if not self.destroyed and self.callbacks.delete then self.callbacks.delete(categoryID, row.root) end
            end)
        end
        return true
    end
    return false
end

function Sidebar:RefreshIcons()
    if self.destroyed then return end
    local revision = Tracking.IconRevision()
    if self.iconRevision == revision then return end
    self.iconRevision = revision
    for _, row in ipairs(self.rows) do
        row.hasIcon = applyRowIcon(row)
    end
    self:LayoutRows()
end

function Sidebar:LayoutRows()
    if self.destroyed then return end
    local width = self.scroll.contentWidth
    local y = 0
    for index, row in ipairs(self.rows) do
        if index > 1 and (index == 2 or row.categoryID == 0) then y = y + GROUP_GAP end
        row.root:SetPos(0, y)
        row.root:SetSize(width, ROW_HEIGHT)
        y = y + ROW_HEIGHT
        local countWidth = math.max(20, measure(row.count) + 2)
        local nameX = 36
        local nameWidth = math.max(1, width - countWidth - nameX - 10)
        row.nameLabel:SetPos(nameX, 0)
        row.nameLabel:SetSize(nameWidth, ROW_HEIGHT)
        row.nameLabel.content, row.clipped = clippedText(row.name, nameWidth)
        row.countLabel:SetPos(width - countWidth - 4, 0)
        row.countLabel:SetSize(countWidth, ROW_HEIGHT)
        row.separator:SetSize(math.max(1, width - 12), 1)
    end
    self:LayoutInput()
end

function Sidebar:Tick()
    if self.destroyed then return end
    if self.drag then self.drag:Tick(true) end
    self:LayoutInput()
end

function Sidebar:Resize(width, height)
    if self.destroyed then return end
    width, height = math.max(1, width), math.max(1, height)
    if self.root.width == width and self.root.height == height then return end
    if self.drag then self.drag:Destroy(); self.drag = nil end
    self.root:SetSize(width, height)
    self.heading:SetPos(4, 0)
    self.heading:SetSize(math.max(1, width - 38), 28)
    self.editButton.root:SetPos(math.max(0, width - 36), 2)
    self.divider:SetPos(width - 1, 0)
    self.divider:SetSize(1, height)
    self.headerLine:SetPos(0, 32)
    self.headerLine:SetSize(math.max(1, width - 10), 1)
    self.newButton.root:SetPos(0, math.max(0, height - 28))
    local resetWidth = math.min(28, math.max(1, math.floor((width - 14) / 2)))
    local newWidth = math.max(1, width - 14 - resetWidth)
    self.newButton.root:SetSize(newWidth, 28)
    self.newButton.content.content = newWidth >= measure("+ New category") + 16 and "+ New category" or "+ New"
    self.resetButton.root:SetPos(newWidth + 4, math.max(0, height - 28))
    self.resetButton.root:SetSize(resetWidth, 28)
    local scroll = self.scroll.scrollY
    self.scroll:SetSize(math.max(1, width - 10), math.max(1, height - 72))
    if self.scroll.scrollY ~= scroll then self.scroll:SetScrollPosition(scroll) end
end

function Sidebar:Destroy(detached)
    if self.destroyed then return end
    self.destroyed = true
    if self.drag then self.drag:Destroy(detached); self.drag = nil end
    if self.hit then
        if self.inputOwner then self.inputOwner:_UnregisterOverlay(self.hit) end
        if not detached then self.hit:Destroy() end
        self.hit = nil
    end
    self.inputOwner = nil
    self.scroll.onLayout = nil
    if detached then Detached.Tooltips(self.root) end
    for _, row in ipairs(self.rows) do
        if detached then Detached.Control(row.button) else row.button:Destroy() end
    end
    self.rows = {}
    for _, control in ipairs({self.editButton, self.newButton, self.resetButton, self.scroll}) do
        if detached then Detached.Control(control) else control:Destroy() end
    end
    prettyui.Tooltip.unregisterContext(self.root)
    if not detached then self.root:Destroy() end
    self.root, self.callbacks = nil, nil
end

return Sidebar
