local Detached = require("src/ui/shared/detached_ui")
local Components = require("src/ui/shared/components")
local Base = require("src/ui/views/view")
local Pages = require("src/ui/notes/journal_pages")
local Sprites = require("src/data/sprite_catalog")
local Tracking = require("src/tracking/model")
local QuestTooltip = require("src/ui/tracking/quest_tooltip")
local GearTooltip = require("src/ui/attachments/gear_tooltip")
local ActionBarTooltip = require("src/ui/attachments/action_bar_tooltip")
local WindowStyle = require("src/ui/window/window_style")

local Journal = {}
Journal.__index = Journal
setmetatable(Journal, {__index = Base})

local MAX_ROWS = 32
local INK, GREEN = 0x000000FF, 0x285C20FF

local function place(component, x, y, width, height)
    if component.x ~= x or component.y ~= y then component:SetPos(x, y) end
    if component.width ~= width or component.height ~= height then component:SetSize(width, height) end
end

local function ink(color)
    local number = tonumber(color or "FFFFFF", 16) or 0xFFFFFF
    if number == 0xFFFFFF then return INK end
    local red = math.floor(math.floor(number / 65536) * 0.4)
    local green = math.floor(math.floor(number / 256) % 256 * 0.4)
    local blue = math.floor(number % 256 * 0.4)
    return (red * 65536 + green * 256 + blue) * 256 + 255
end

local function label(parent, value, font, color)
    local component = prettyui.Text.new(parent, Components.Options({text = value, font = font,
        colour = color or INK, shadowed = false, maxLines = 1, width = 1, height = 20}))
    component.clickthrough = true
    return component
end

function Journal:HideTooltips()
    self.activeTooltip, self.tooltipSlot = nil, nil
    if self.tooltip then self.tooltip:Hide() end
    if self.gearTooltip then self.gearTooltip:Hide() end
    if self.actionBarTooltip then self.actionBarTooltip:Hide() end
end

function Journal:UpdateTooltipBounds()
    local left, right = self.backgrounds[1], self.backgrounds[2]
    local point, origin = left.xyGlobal, self.parent.xyGlobal
    local width = left.width + right.width
    place(self.tooltipOwner, point.x - origin.x, point.y - origin.y, width, left.height)
    self.tooltip.options.maxWidth = math.max(21, math.min(360, width - 12))
end

function Journal:PositionTooltip(slot, x, y)
    local tooltip = self.activeTooltip
    if not tooltip or self.tooltipSlot ~= slot or tooltip.root.hidden then return end
    self:UpdateTooltipBounds()
    tooltip.target:SetPos(slot.root.x + (x or slot.root.width / 2), slot.root.y + (y or slot.root.height / 2))
    tooltip.target:SetSize(1, 1)
    tooltip:Show()
end

function Journal:ShowTooltip(slot, x, y)
    self:HideTooltips()
    local row = slot.row
    if not row or not row.note then return end
    self:UpdateTooltipBounds()
    if row.attachment == "gear" then
        self.gearTooltip:Show(slot.root, row.note.gear)
        self.activeTooltip = self.gearTooltip.tooltip
    elseif row.attachment == "actionBar" then
        self.actionBarTooltip:Show(slot.root, row.note.actionBar)
        self.activeTooltip = self.actionBarTooltip.tooltip
    else
        local tracking = row.tracking
        local card = tracking and (Tracking.BossCard(tracking) or Tracking.QuestTooltip(tracking))
        if not (card and QuestTooltip.Prepare(self.tooltip)
            and QuestTooltip.Set(self.tooltip, card, self.tooltip.options.maxWidth)) then
            QuestTooltip.Clear(self.tooltip)
            local description = tracking and Tracking.Description(tracking)
            local text = row.kind == "item" and row.text or row.note.text or ""
            if description and description ~= "" then text = text ~= "" and text .. "\n\n" .. description or description end
            if text == "" then return end
            self.tooltip:SetText(text:gsub("\r\n", "<br>"):gsub("[\r\n]", "<br>"))
        end
        self.tooltip:Show()
        self.activeTooltip = self.tooltip
    end
    self.tooltipSlot = slot
    self:PositionTooltip(slot, x, y)
end

function Journal:NewSlot()
    local slot = {root = Components.New(ui.Layer, self.surface)}
    slot.root.hidden, slot.root.clickthrough = true, false
    slot.text = label(slot.root, "", id.Font.MUSEO_SANS_13PT_REGULAR)
    slot.icon = Components.New(ui.Sprite, slot.root)
    slot.icon.hidden, slot.icon.clickthrough = true, true
    slot.track, slot.fill = Components.New(ui.Rectangle, slot.root), Components.New(ui.Rectangle, slot.root)
    for _, bar in ipairs({slot.track, slot.fill}) do bar.fill, bar.clickthrough, bar.hidden = true, true, true end
    slot.track.rgba, slot.fill.rgba = 0x38281833, GREEN
    slot.root:Subscribe(ui.Hook.ONMOUSEOVER, function(_, x, y)
        if not self.destroyed then self:ShowTooltip(slot, x, y) end
        return true
    end)
    slot.root:Subscribe(ui.Hook.ONMOUSEREPEAT, function(_, x, y)
        if not self.destroyed then self:PositionTooltip(slot, x, y) end
        return true
    end)
    slot.root:Subscribe(ui.Hook.ONMOUSELEAVE, function()
        if not self.destroyed then self:HideTooltips() end
        return true
    end)
    return slot
end

function Journal:SetIcon(slot, icon)
    if slot.iconRef == icon then return end
    slot.iconRef = icon
    Sprites.Clear(slot.icon)
    if type(icon) == "string" then slot.icon.hidden = not Sprites.Apply(slot.icon, icon)
    elseif type(icon) == "number" then
        slot.icon:SetAssociatedObject(icon)
        slot.icon.associatedObjectQuantityMode = ui.ObjectQuantityDisplayMode.NEVER
        slot.icon.hidden = false
    elseif type(icon) == "table" and icon.sprite then
        slot.icon.sprite, slot.icon.hidden = icon.sprite, false
    end
end

function Journal:Draw()
    self:HideTooltips()
    local count = self.builder and #self.builder.pages or 1
    if self.ready then
        self.pageIndex = math.max(1, math.min(self.pageIndex, math.max(1, count - (count + 1) % 2)))
        self.state.journalPage = self.pageIndex
    end
    for side = 1, 2 do
        local page = self.ready and self.builder.pages[self.pageIndex + side - 1]
        local x = self.pageX[side]
        for index, slot in ipairs(self.lines[side]) do
            local row = page and page.rows[index]
            slot.row = row
            slot.root.hidden = not row or row.kind == "gap" or index > self.rowsPerPage
            if not slot.root.hidden then
                place(slot.root, x, self.contentY + (index - 1) * self.lineHeight, self.textWidth, self.lineHeight)
                slot.text.font = id.Font[self.fontName]
                slot.text.content = row.text
                slot.text.rgba = row.kind == "title" and ink(row.color) or (row.complete or row.available) and GREEN or INK
                local inset = row.icon and 22 or 0
                place(slot.text, inset, 0, math.max(1, self.textWidth - inset), self.lineHeight - 3)
                self:SetIcon(slot, row.icon)
                place(slot.icon, 0, 0, 18, 18)
                local fraction = row.kind == "progress" and row.fraction
                slot.track.hidden = not fraction
                slot.fill.hidden = slot.track.hidden or fraction <= 0
                place(slot.track, 0, self.lineHeight - 3, self.textWidth, 2)
                place(slot.fill, 0, self.lineHeight - 3,
                    math.max(1, math.floor(self.textWidth * math.max(0, math.min(1, fraction or 0)))), 2)
            end
        end
        self.pageNumbers[side].content = page and tostring(self.pageIndex + side - 1) or ""
    end
    self.status.content = not self.ready and "Loading notes..." or #self.data.notes == 0 and "No notes yet." or ""
    self.previousButton:SetDisabled(not self.ready or self.pageIndex <= 1)
    self.nextButton:SetDisabled(not self.ready or self.pageIndex + 1 >= count)
end

function Journal:Layout()
    self:HideTooltips()
    local width = math.max(1, math.min(self.width, math.max(1, self.height - 44) * 1.5))
    local height = width / 1.5
    local x, y = math.floor((self.width - width) / 2), 40 + math.max(0, math.floor((self.height - 40 - height) / 2))
    local pageWidth = width / 2
    place(self.backgrounds[1], x, y, pageWidth, height)
    place(self.backgrounds[2], x + pageWidth, y, pageWidth, height)
    local fontName, fontSize = Base.NoteFont(self.settings)
    if width < 700 then fontSize = math.min(fontSize, 12); fontName = "NOTOSANS_" .. fontSize end
    local font = config.Font[fontName]
    local textWidth = math.max(1, math.floor(width * 0.4))
    local lineHeight = math.max(22, font.baseline + 6)
    local headerY = y + math.max(28, height * 0.095) + 12
    local top = headerY - y + math.max(28, lineHeight) + 8
    local footerY = y + height - math.max(56, height * 0.12)
    local bottom = math.max(56, height * 0.12) + lineHeight
    local rows = math.max(1, math.min(MAX_ROWS, math.floor((height - top - bottom) / lineHeight)))
    self.pageX = {x + width * 0.06, x + width * 0.54}
    self.contentY, self.textWidth, self.lineHeight = y + top, textWidth, lineHeight
    for side = 1, 2 do
        place(self.pageNumbers[side], self.pageX[side], footerY, textWidth, 20)
    end
    local tabY = math.max(0, y + height * 0.095 - 32)
    self.backButton.root:SetPos(self.pageX[1], headerY)
    local buttonWidth = 28
    for index, button in ipairs(self.sizeButtons) do
        place(button.root, self.pageX[2] + textWidth - (3 - index) * (buttonWidth + 4) + 4,
            headerY, buttonWidth, 28)
    end
    self.closeSprite:SetPos(x + width * 0.94 - 28, tabY)
    self.closeSprite:SetSize(28, 40)
    self.window.journalBounds = {x = 8 + x + width * 0.06 + 68, y = 32 + tabY,
        width = math.max(1, width * 0.88 - 100)}
    self.window:ClampPosition()
    self.previousButton.root:SetPos(x + width * 0.07, footerY)
    self.nextButton.root:SetPos(x + width * 0.89, footerY)
    place(self.status, self.pageX[1], self.contentY, textWidth, lineHeight)
    if not self.builder or self.fontName ~= fontName or self.textWidthBefore ~= textWidth or self.rowsPerPage ~= rows then
        local page = self.ready and self.builder.pages[self.pageIndex]
        self.anchor = page and page.rows[1] and page.rows[1].noteIndex or self.anchor
        self.fontName, self.textWidthBefore, self.rowsPerPage = fontName, textWidth, rows
        self.builder = Pages.New(self.data.notes, {font = font, width = textWidth, rows = rows})
        self.ready = false
    end
    self:Draw()
end

function Journal:RefreshTracking()
    if not self.ready then return end
    local page = self.builder.pages[self.pageIndex]
    local anchor = page and page.rows[1] and page.rows[1].noteIndex
    local changed, repacked = self.builder:Refresh(self.pageIndex, self.pageIndex + 1)
    if repacked and anchor then
        local selected = self.builder:PageForNote(anchor)
        self.pageIndex = selected - (selected - 1) % 2
    end
    if changed then self:Draw() end
end

function Journal:Turn(direction)
    if not self.ready then return end
    self.pageIndex = math.max(1, math.min(self.pageIndex + direction * 2,
        math.max(1, #self.builder.pages - (#self.builder.pages + 1) % 2)))
    self:RefreshTracking()
    self:Draw()
end

function Journal:Tick()
    if self.pendingBack then self:ShowList(); return end
    if self.pendingClose then self.window.chrome:Close(); return end
    if self.pendingSize then
        local direction = self.pendingSize
        self.pendingSize = nil
        local button = self.sizeButtons[direction == -1 and 1 or 2].root
        local point = button.xyGlobal
        self.callbacks.resizeWindow(math.max(200, self.window.root.width + direction * 150),
            math.max(200, self.window.root.height + direction * 100),
            {target = button, x = point.x + button.width / 2, y = point.y + button.height / 2})
    end
    if self.pendingPage then local direction = self.pendingPage; self.pendingPage = nil; self:Turn(direction) end
    if not self.ready and self.builder:Step(4) then
        self.ready = true
        if self.anchor then
            local selected = self.builder:PageForNote(self.anchor)
            self.pageIndex, self.anchor = selected - (selected - 1) % 2, nil
        end
        self:Draw()
    end
    if self.window:IsDragging() then self:HideTooltips() end
    self.actionBarTooltip:Tick()
end

function Journal.new(parent, options, callbacks)
    local self = setmetatable({}, Journal)
    local ok, message = pcall(function()
        Base.Init(self, parent, options, callbacks)
        prettyui.Tooltip.getContext(self.surface).position = function(target)
            local point, origin = target.xyGlobal, self.tooltipOwner.xyGlobal
            return point.x - origin.x, point.y - origin.y
        end
        self.pageIndex, self.lines, self.backgrounds, self.pageNumbers = self.state.journalPage or 1, {{}, {}}, {}, {}
        for side = 1, 2 do
            local background = Components.New(ui.Sprite, self.surface)
            background.spriteID, background.clickthrough = id.Sprite.ARCH_JOURNAL_BACKGROUND, false
            background.isFlippedHorizontally = side == 2
            self.backgrounds[side] = background
            self.pageNumbers[side] = label(self.surface, "", id.Font.MUSEO_SANS_13PT_REGULAR)
            self.pageNumbers[side].alignHorizontal = ui.AlignMode.CENTRE
        end
        self.backButton = self:Button(id.Sprite.RS3_ICON_BACK_32PX_1, 0, 0, 32, function() self.pendingBack = true end)
        self.backButton.content:SetSize(28, 28)
        self.backButton.content:SetPos(2, 0)
        self.sizeButtons = {}
        for index, sprite in ipairs({id.Sprite.LOBBY_ICON_MINUS, id.Sprite.LOBBY_BUTTON_PLUS_ICON}) do
            local button = self:Button(sprite, 0, 0, 28, function() self.pendingSize = index == 1 and -1 or 1 end)
            button.content:SetSize(20, 20)
            button.content:SetPos(4, 4)
            self.sizeButtons[index] = button
        end
        for _, button in ipairs({self.backButton, self.sizeButtons[1], self.sizeButtons[2]}) do
            for _, part in pairs(button.parts) do part.hidden = true end
        end
        self.previousButton = self:Track(prettyui.SpriteButton.new(self.surface, "ARROW_LEFT",
            function() self.pendingPage = -1 end, Components.Options({width = 20, height = 24})))
        self.nextButton = self:Track(prettyui.SpriteButton.new(self.surface, "ARROW_RIGHT",
            function() self.pendingPage = 1 end, Components.Options({width = 20, height = 24})))
        self.closeSprite = Components.New(ui.Sprite, self.surface)
        self.closeSprite.spriteID = id.Sprite.ARCH_JOURNAL_TAB_CLOSE_0
        self.closeSprite:Subscribe(ui.Hook.ONMOUSEOVER, function() self.closeSprite.spriteID = id.Sprite.ARCH_JOURNAL_TAB_CLOSE_1; return true end)
        self.closeSprite:Subscribe(ui.Hook.ONMOUSELEAVE, function() self.closeSprite.spriteID = id.Sprite.ARCH_JOURNAL_TAB_CLOSE_0; return true end)
        self.closeSprite:Subscribe(ui.Hook.ONCLICK, function() self.pendingClose = true; return false end)
        self.status = label(self.surface, "Loading notes...", id.Font.MUSEO_SANS_13PT_REGULAR)
        for side = 1, 2 do for _ = 1, MAX_ROWS do self.lines[side][#self.lines[side] + 1] = self:NewSlot() end end
        self.tooltipTarget = Components.New(ui.Layer, self.surface)
        self.tooltipTarget.hidden, self.tooltipTarget.clickthrough = true, true
        self.tooltip = prettyui.Tooltip.attach(self.tooltipTarget, self.surface, Components.Options({text = "", maxWidth = 360}))
        WindowStyle.ApplyTooltip(self.tooltip)
        self.gearTooltip, self.actionBarTooltip = GearTooltip.new(self.surface), ActionBarTooltip.new(self.surface)
        self.layout = function() self:Layout() end
        self:Layout()
    end)
    if not ok then self:Destroy(); error(message, 0) end
    return self
end

function Journal:Destroy(detached)
    if self.destroyed then return end
    self:HideTooltips()
    if self.gearTooltip then self.gearTooltip:Destroy(detached) end
    if self.actionBarTooltip then self.actionBarTooltip:Destroy(detached) end
    if self.tooltip then
        if detached then Detached.Tooltip(self.tooltip) end
        self.tooltip:Destroy()
    end
    self.builder, self.lines = nil, {}
    Base.Destroy(self, detached)
end

return Journal
