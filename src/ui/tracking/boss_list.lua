local Components = require("src/ui/shared/components")
local Base = require("src/ui/views/view")
-- A note's list of what is still to do as a bulleted list, a page of 7 at a time. Used for the
-- Reaper crew: each boss you have not killed yet is a line; hovering one shows that boss's card; killed bosses drop off.
-- It plugs into the note list the same way the item strip does (same methods), so the list treats both alike.

local Tracking = require("src/tracking/model")
local WindowStyle = require("src/ui/window/window_style")
local Detached = require("src/ui/shared/detached_ui")
local QuestTooltip = require("src/ui/tracking/quest_tooltip")

local BossList = {}
BossList.__index = BossList

local PAGE = 7
local FADED, LIT = 0xBFBFBFFF, 0xFFFFFFFF

local function fontMetrics(settings)
    local name, size = Base.NoteFont(settings or {})
    local font = config.Font[name]
    local textHeight = math.ceil(math.max(font.baseline, (font.maxAscent or 0) + (font.maxDescent or 0))) + 2
    local iconSize = math.max(1, math.floor(16 * size / 14 + 0.5))
    local rowHeight = math.max(textHeight, iconSize + 2)
    return id.Font[name], rowHeight, iconSize, math.max(26, rowHeight + 8)
end

local function plain(value)
    return tostring(value or ""):gsub("<[Bb][Rr]%s*/?>", " "):gsub("<", "["):gsub(">", "]"):gsub("[%c]", " ")
end

local function itemLabel(item)
    local ok, value, status = pcall(Tracking.ItemLabel, item)
    if ok and value ~= nil then
        value = tostring(value)
        if type(status) == "string" and status ~= "" then
            return plain(value:sub(1, #value - #status)) .. "<col=00ff00>" .. plain(status) .. "</col>"
        end
        return plain(value)
    end
    return plain(item and item.label)
end

local function itemIcon(item)
    if not item then return nil end
    local ok, value = pcall(Tracking.ItemSprite, item)
    if ok and type(value) == "number" and value >= 0 then return "sprite", value end
    ok, value = pcall(Tracking.ItemObject, item)
    if ok and type(value) == "number" and value >= 0 then return "object", value end
end

local function setIcon(row, kind, value)
    if row.iconKind ~= kind or row.iconID ~= value then
        if row.iconKind ~= kind then
            if row.iconKind == "object" then row.icon.associatedObjectID = -1 end
            if row.iconKind == "sprite" then row.icon.spriteID = -1 end
            row.icon.hidden = kind == nil
        end
        if kind == "object" then
            row.icon:SetAssociatedObject(value)
            row.icon.associatedObjectQuantity = 1
            row.icon.associatedObjectQuantityMode = ui.ObjectQuantityDisplayMode.NEVER
        elseif kind == "sprite" then
            row.icon.spriteID = value
        end
        row.iconKind, row.iconID = kind, value
    end
end

local function tooltipContext(parent)
    while parent do
        local context = prettyui.Tooltip.getContext(parent)
        if context then return context end
        parent = parent.parent
    end
end

local function position(target, parent)
    local point, base = target.xyGlobal, parent.xyGlobal
    local x, y = point.x - base.x, point.y - base.y
    local ancestor = target.parent
    while ancestor and ancestor ~= parent do
        x = x - (ancestor.scrollX or 0)
        y = y - (ancestor.scrollY or 0)
        ancestor = ancestor.parent
    end
    return x, y
end

local function read(tracking)
    local ok, value = pcall(Tracking.Read, tracking)
    return ok and value or {}
end

local function label(parent, font, colour)
    local text = prettyui.Text.new(parent, Components.Options({text = "", font = font, colour = colour or LIT, shadowed = true, maxLines = 1}))
    text.clickthrough = true
    text.hidden = true
    text.alignVertical = ui.AlignMode.CENTRE
    return text
end

function BossList.new(parent, items, tracking, progress, ownerContext, settings)
    local self = setmetatable({items = items or {}, list = items or {}, rows = {}, first = 1, active = false,
        tracking = tracking, unavailable = false}, BossList)
    self.font, self.rowHeight, self.iconSize, self.pagerHeight = fontMetrics(settings)
    self.rowCount = math.max(1, math.min(PAGE, #self.items))
    self.paged = #self.items > PAGE
    self:_filter(progress)
    self.root = Components.Host(parent)
    self.root.hidden = true
    self.root.clickthrough = true
    self.height = self:HeightFor(1)
    self.root:SetSize(1, self.height)
    local context = ownerContext or tooltipContext(parent)
    local tooltipParent = context and context.parent or parent
    self.tooltipContext = prettyui.Tooltip.registerContext(self.root, tooltipParent, function(target)
        return position(target, tooltipParent)
    end, context)
    self.tooltipTarget = Components.New(ui.Layer, self.root)
    self.tooltipTarget.hidden, self.tooltipTarget.clickthrough = true, true
    self.sharedTooltip = prettyui.Tooltip.attach(self.tooltipTarget, self.root,
        Components.Options({text = "Reaper boss", placement = "right", maxWidth = 360}))
    WindowStyle.ApplyTooltip(self.sharedTooltip, function() self:HideTooltip() end)
    for index = 1, self.rowCount do
        local row = {hit = Components.New(ui.Layer, self.root), label = label(self.root, self.font, FADED), icon = Components.New(ui.Sprite, self.root)}
        row.icon:SetSize(self.iconSize, self.iconSize)
        row.icon.clickthrough = true
        row.icon.hidden = true
        row.hit.clickthrough = false
        row.hit.hidden = true
        local function hover(_, x, y)
            self:ShowTooltip(row, x, y)
            return true
        end
        row.hit:Subscribe(ui.Hook.ONMOUSEOVER, hover)
        row.hit:Subscribe(ui.Hook.ONMOUSEREPEAT, hover)
        row.hit:Subscribe(ui.Hook.ONMOUSELEAVE, function()
            if self.hoveredRow == row then self:HideTooltip() end
            return true
        end)
        -- The wheel goes on to whatever list this one sits in.
        row.hit:Subscribe(ui.Hook.ONSCROLLWHEEL, function(_, rotation)
            if self.onScroll then self:HideTooltip(); self.onScroll(rotation) end
            return false
        end)
        self.rows[index] = row
    end
    if self.paged then
        self.previousButton = prettyui.SpriteButton.new(self.root, "ARROW_LEFT", function()
            if not self.destroyed then self.pendingDirection = -1 end
        end, Components.Options({width = 16, height = 24}))
        self.nextButton = prettyui.SpriteButton.new(self.root, "ARROW_RIGHT", function()
            if not self.destroyed then self.pendingDirection = 1 end
        end, Components.Options({width = 16, height = 24}))
        self.pageLabel = label(self.root, self.font, FADED)
        self.pageLabel.alignHorizontal = ui.AlignMode.CENTRE
    end
    return self
end

-- How tall the list is at this width .
function BossList:HeightFor(width)
    if self.unavailable or self.empty then return 0 end
    local count = #self.list
    local height = math.max(1, math.min(PAGE, count)) * self.rowHeight + (count > PAGE and self.pagerHeight or 0)
    return height + 2
end

-- Every entry of a list as { text, done }, for the tooltip of a compact note (finished entries included).
function BossList.Entries(items)
    local entries = {}
    for _, item in ipairs(items or {}) do
        local progress = read(item)
        local text = itemLabel(item)
        -- Quantity targets (96/99 levels, 10/50 kills) are listed after the name, like the figures under the tiles.
        if type(progress.current) == "number" and type(progress.target) == "number" and progress.target > 1 and not progress.owned
            and item.kind ~= "timer" and not item.ownedVar
            and not text:find("%d%s*/%s*%d") then
            text = text .. " - " .. math.floor(progress.current) .. " / " .. math.floor(progress.target)
        end
        entries[#entries + 1] = {text = text, done = progress.complete == true}
    end
    return entries
end

function BossList.Measure(items, tracking, progress, width, settings)
    local descriptor = setmetatable({items = items or {}, list = items or {}, first = 1,
        tracking = tracking, unavailable = false}, BossList)
    descriptor.font, descriptor.rowHeight, descriptor.iconSize, descriptor.pagerHeight = fontMetrics(settings)
    descriptor:_filter(progress)
    return descriptor:HeightFor(width)
end

function BossList:HideTooltip()
    self.hoveredRow, self.hoverX, self.hoverY = nil, nil, nil
    if self.sharedTooltip then self.sharedTooltip:Hide() end
end

function BossList:ShowTooltip(row, x, y)
    if self.destroyed or self.root.hidden or not row.item then return end
    local sameRow = self.hoveredRow == row
    x = type(x) == "number" and x or sameRow and self.hoverX or row.hit.width / 2
    y = type(y) == "number" and y or sameRow and self.hoverY or row.hit.height / 2
    x, y = math.max(0, math.min(row.hit.width, x)), math.max(0, math.min(row.hit.height, y))
    self:HideTooltip()
    self.hoveredRow, self.hoverX, self.hoverY = row, x, y
    self.tooltipTarget:SetPos(row.hit.x + x, row.hit.y + y)
    self.tooltipTarget:SetSize(1, 1)
    local okCard, card = pcall(Tracking.BossCard, row.item)
    if okCard and card and QuestTooltip.Prepare(self.sharedTooltip) and QuestTooltip.Set(self.sharedTooltip, card, 360) then
        self.sharedTooltip:Show()
        return
    end
    QuestTooltip.Clear(self.sharedTooltip)
    self.sharedTooltip:SetText(itemLabel(row.item))
    self.sharedTooltip:Show()
end

function BossList:_filter(progress)
    local shown = {}
    if progress then
        self.unavailable = progress.unavailable == true
        self.complete = progress.complete == true
    end
    if not self.unavailable then
        for _, item in ipairs(self.items) do
            if item.keepComplete or read(item).complete ~= true then shown[#shown + 1] = item end
        end
    end
    self.list = shown
    self.empty = #shown == 0 and self.complete == false
    self.first = math.max(1, math.min(self.first, math.max(1, #shown - PAGE + 1)))
end

-- keepList: just redraw the rows (a resize), without re-reading every entry's progress from the game.
function BossList:Refresh(keepList, progress)
    if self.destroyed then return end
    if not (keepList == true and self.list) then self:_filter(progress) end
    self:_layout()
    self.root.hidden = self.active == false or self.unavailable or self.empty
    if self.unavailable or self.empty then
        self.pendingDirection = nil
        self:HideTooltip()
        for _, row in ipairs(self.rows) do
            row.item = nil
            row.label.hidden, row.hit.hidden = true, true
            setIcon(row, nil, nil)
        end
        if self.pageLabel then
            self.pageLabel.hidden = true
            self.previousButton.root.hidden, self.nextButton.root.hidden = true, true
        end
        return
    end
    if self.active == false then return end
    local count = #self.list
    for index, row in ipairs(self.rows) do
        local item = self.list[self.first + index - 1]
        row.item = item
        local text = item and ("- " .. itemLabel(item)) or index == 1 and count == 0 and "Completed" or ""
        if row.labelText ~= text then row.label.content = text; row.labelText = text end
        row.label.hidden = not item and not (index == 1 and count == 0)
        row.hit.hidden = item == nil
        local kind, value = itemIcon(item)
        setIcon(row, kind, value)
        if row.y and row.width then
            local left = kind and self.iconSize + 8 or 4
            row.label:SetPos(left, row.y)
            row.label:SetSize(math.max(1, row.width - left - 4), self.rowHeight)
        end
    end
    if self.pageLabel then
        local paged = count > PAGE
        local last = math.min(count, self.first + PAGE - 1)
        self.pageLabel.content = paged and (self.first .. "-" .. last .. " of " .. count) or ""
        self.pageLabel.hidden = not paged
        self.previousButton.root.hidden, self.nextButton.root.hidden = not paged, not paged
        self.previousButton:SetDisabled(not paged or self.first <= 1)
        self.nextButton:SetDisabled(not paged or self.first + PAGE > count)
    end
    self:_applyClip()
    if self.hoveredRow then
        if self.hoveredRow.item and not self.hoveredRow.hit.hidden then self:ShowTooltip(self.hoveredRow) else self:HideTooltip() end
    end
end

-- Only the lines (and pager) that sit fully inside the part of the list that is on screen are drawn; top and bottom are in
-- this list's own coordinates (nil for no limit). A list scrolled half out of the viewport shows what is still in view.
function BossList:_applyClip()
    local clip = self.clip
    local count = #(self.list or {})
    for index, row in ipairs(self.rows) do
        local out = clip ~= nil and row.y ~= nil and (row.y < clip[1] or row.y + self.rowHeight > clip[2])
        row.hit.hidden = row.item == nil or out
        row.label.hidden = (row.item == nil and not (index == 1 and count == 0)) or out
        row.icon.hidden = row.iconKind == nil or out
    end
    if self.pageLabel then
        local paged = count > PAGE
        local top = math.min(PAGE, count) * self.rowHeight
        local out = clip ~= nil and (top < clip[1] or top + self.pagerHeight > clip[2])
        self.pageLabel.hidden = not paged or out
        self.previousButton.root.hidden, self.nextButton.root.hidden = not paged or out, not paged or out
    end
end

function BossList:SetClip(top, bottom)
    if self.destroyed then return end
    local clip = top ~= nil and {top, bottom} or nil
    local same = (clip == nil and self.clip == nil) or (clip ~= nil and self.clip ~= nil and clip[1] == self.clip[1] and clip[2] == self.clip[2])
    if same then return end
    self.clip = clip
    if self.active ~= false and not self.root.hidden then self:_applyClip() end
end

function BossList:SetVisible(visible)
    if self.destroyed then return end
    visible = visible == true
    self.root.hidden = not visible or self.unavailable or self.empty
    if self.active == visible then return end
    self.active = visible
    self:HideTooltip()
    if visible then self:Refresh() end
end

function BossList:_layout()
    local width = self.width or 1
    local height = self:HeightFor(width)
    self.height = height
    if self.layoutWidth == width and self.layoutHeight == height then return end
    self.layoutWidth, self.layoutHeight = width, height
    self:HideTooltip()
    self.root:SetSize(width, self.height)
    local top = 0
    for index, row in ipairs(self.rows) do
        local rowY = top + (index - 1) * self.rowHeight
        row.hit:SetPos(0, rowY)
        row.hit:SetSize(width, self.rowHeight)
        row.y, row.width = rowY, width
        row.icon:SetPos(4, rowY + math.floor((self.rowHeight - self.iconSize) / 2))
    end
    top = top + math.max(1, math.min(PAGE, #self.list)) * self.rowHeight
    if self.paged then
        local button = math.min(self.iconSize, math.max(6, math.floor(width / 5)))
        self.previousButton.root:SetPos(0, top + 1)
        self.previousButton.root:SetSize(button, self.pagerHeight - 2)
        self.nextButton.root:SetPos(width - button, top + 1)
        self.nextButton.root:SetSize(button, self.pagerHeight - 2)
        self.pageLabel:SetPos(button + 4, top + math.floor((self.pagerHeight - self.rowHeight) / 2))
        self.pageLabel:SetSize(math.max(1, width - button * 2 - 8), self.rowHeight)
    end
end

function BossList:SetBounds(x, y, width)
    if self.destroyed then return end
    if self.root.x ~= x or self.root.y ~= y then self.root:SetPos(x, y) end
    width = math.max(1, math.floor(width))
    if self.width == width then return end
    self.width = width
    self:_layout()
    self:Refresh(true)
end

function BossList:Tick()
    if self.destroyed then return end
    if self.root.hidden then self:HideTooltip() end
    local direction = self.pendingDirection
    self.pendingDirection = nil
    if not direction then return end
    self:HideTooltip()
    self.first = math.max(1, math.min(self.first + direction * PAGE, math.max(1, #self.list - PAGE + 1)))
    self:Refresh()
end

function BossList:Destroy(detached)
    if self.destroyed then return end
    self.destroyed = true
    self.hoveredRow, self.pendingDirection = nil, nil
    if self.sharedTooltip then
        if detached then Detached.Tooltip(self.sharedTooltip) end
        self.sharedTooltip:Destroy()
        self.sharedTooltip = nil
    end
    if detached then Detached.Tooltips(self.root) end
    for _, control in ipairs({self.previousButton or false, self.nextButton or false}) do
        if control then
            if detached then Detached.Control(control) else control:Destroy() end
        end
    end
    local context = self.tooltipContext
    local children = context and context.parentContext and context.parentContext.children
    for index = #(children or {}), 1, -1 do
        if children[index] == context then table.remove(children, index); break end
    end
    prettyui.Tooltip.unregisterContext(self.root)
    if not detached then self.root:Destroy() end
    self.root, self.tooltipTarget, self.tooltipContext = nil, nil, nil
    self.previousButton, self.nextButton, self.rows, self.items, self.list = nil, nil, {}, {}, {}, {}
end

return BossList
