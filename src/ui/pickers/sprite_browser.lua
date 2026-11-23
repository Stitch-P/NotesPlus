local Components = require("src/ui/shared/components")
local Directory = require("src/data/sprite_directory")
local Sprites = require("src/data/sprite_catalog")
local WindowStyle = require("src/ui/window/window_style")
local Detached = require("src/ui/shared/detached_ui")
local Browser = {}
Browser.__index = Browser

local CELL = 52
local MAX_VISIBLE_CELLS = 144
local SEARCH_DELAY = 2

local function text(parent, content, height)
    return prettyui.Text.new(parent, Components.Options({text = content, height = height,
        colour = 0xD8D8D8FF, maxLines = 0, shadowed = false}))
end

local function image(parent, size)
    local sprite = Components.New(ui.Sprite, parent)
    sprite:SetSize(size, size)
    sprite.clickthrough = true
    sprite.rgba = 0xFFFFFFFF
    sprite.hidden = true
    return sprite
end

function Browser.new(parent, width, height, selected, choose, back, ownerContext, options)
    options = options or {}
    local self = setmetatable({directory = Directory.Open(), selected = selected,
        choose = choose, cells = {}, itemsOnly = options.itemsOnly == true}, Browser)
    self.root = Components.Host(parent)
    self.root.clickthrough = false
    local context = prettyui.Tooltip.getContext(parent)
    if context then
        prettyui.Tooltip.registerContext(self.root, context.parent, context.position, ownerContext or context)
    end
    self.search = prettyui.TextField.new(self.root, Components.Options({x = 8, y = 6, height = 28, width = 200,
        placeholder = self.itemsOnly and "Search items" or "Search game sprites and items", text = "", maxLength = 120,
        onChange = function(_, _, value) self:Search(value) end}))
    WindowStyle.ApplyInput(self.search.root)
    self.search.root.text.maxLines = 1
    self.search.root.scrollbar.visible = false
    self.search.root.scrollbar.size = 0
    self.view = prettyui.SimpleView.new(self.root, Components.Options({x = 8, y = 42,
        width = width, height = 100, scrollStep = CELL}))
    self.view.onLayout = function()
        prettyui.Tooltip.hideContextTooltips(self.view.content)
        self:DrawCells()
    end
    self.tooltipTarget = Components.New(ui.Layer, self.view.content)
    self.tooltipTarget.hidden = true
    self.tooltipTarget.clickthrough = true
    self.sharedTooltip = prettyui.Tooltip.attach(self.tooltipTarget, self.view.content,
        Components.Options({text = self.itemsOnly and "Item" or "Sprite", placement = "above", maxWidth = 260}))
    WindowStyle.ApplyTooltip(self.sharedTooltip)
    self.empty = text(self.view.viewport, "", 44)
    self.status = text(self.root, self.itemsOnly and "Loading items..." or "Loading sprites...", 22)
    self.previewSprite = image(self.root, 64)
    self.previewItem = image(self.root, 64)
    self.previewName = text(self.root, "Hover over an icon to preview it.", 66)
    self.none = prettyui.SimpleButton.new(self.root, self.itemsOnly and "Clear slot" or "No sprite", function()
        if not self.destroyed then choose("") end
    end,
        Components.Options({x = 8, y = 0, width = 100, height = 28}))
    self.back = prettyui.SimpleButton.new(self.root, "Back", function()
        if not self.destroyed then back() end
    end,
        Components.Options({x = 0, y = 0, width = 80, height = 28}))
    self.query = self.directory:Query("", {itemsOnly = self.itemsOnly})
    self:Resize(width, height)
    return self
end

function Browser:Search(value)
    if self.destroyed then return end
    if self.query and self.query.text == value then return end
    self.query = self.directory:Query(value, {itemsOnly = self.itemsOnly})
    self.searchDelay = SEARCH_DELAY
    self.previewRecord = nil
    self.previewApplied = false
    Sprites.Clear(self.previewSprite)
    Sprites.Clear(self.previewItem)
    self.previewName.content = "Hover over an icon to preview it."
    self.view:SetScrollPosition(0)
    self:Refresh()
end

function Browser:Preview(record)
    if self.destroyed or self.previewRecord == record then return end
    if self.itemsOnly and not record.objectID then return end
    self.previewRecord = record
    Sprites.Clear(self.previewSprite)
    Sprites.Clear(self.previewItem)
    self.previewName.content = Sprites.Description(record)
    local target = record.objectID and self.previewItem or self.previewSprite
    self.previewApplied = Sprites.Apply(target, record.name)
    target.hidden = not self.largePreview or not self.previewApplied
end

function Browser:HideCellTooltip()
    self.hoveredCell = nil
    if self.sharedTooltip then self.sharedTooltip:Hide() end
end

function Browser:ShowCellTooltip(cell)
    if self.destroyed or not cell.record or cell.button.root.hidden then return end
    local top = cell.button.root.y - self.view.scrollY
    if top < 0 or top + cell.button.root.height > self.view.root.height then return end
    self:HideCellTooltip()
    self.hoveredCell = cell
    self:Preview(cell.record)
    self.tooltipTarget:SetPos(cell.button.root.x, cell.button.root.y)
    self.tooltipTarget:SetSize(cell.button.root.width, cell.button.root.height)
    self.sharedTooltip:SetText(Sprites.Description(cell.record))
    self.sharedTooltip:Show()
end

function Browser:NewCell()
    local cell = {}
    cell.button = prettyui.SimpleButton.new(self.view.content, -1, function()
        if not self.destroyed and cell.record and (not self.itemsOnly or cell.record.objectID) then
            self.choose(cell.record.name)
        end
    end, Components.Options({x = 0, y = 0, width = 44, height = 44, iconSize = 32}))
    cell.item = image(cell.button.root, 32)
    cell.item:SetPos(6, 6)
    cell.button.root:Subscribe(ui.Hook.ONSCROLLWHEEL, function(_, rotation)
        self.view:ScrollBy(rotation * CELL)
        return false
    end)
    cell.button.root:Subscribe(ui.Hook.ONMOUSEOVER, "notes_sprite_preview", function()
        self:ShowCellTooltip(cell)
        return true
    end)
    cell.button.root:Subscribe(ui.Hook.ONMOUSELEAVE, "notes_sprite_preview", function()
        if self.hoveredCell == cell then self:HideCellTooltip() end
        return true
    end)
    self.cells[#self.cells + 1] = cell
    return cell
end

function Browser:DrawCells()
    if self.destroyed or not self.columns or not self.query then return end
    self:HideCellTooltip()
    local records = self.query.results
    local firstRow = math.floor(self.view.scrollY / CELL)
    local count = math.min(#records, self.columns * (math.ceil(self.view.root.height / CELL) + 1))
    local left = math.max(0, math.floor((self.view.contentWidth - self.columns * CELL) / 2))
    for slot = 1, count do
        local cell = self.cells[slot] or self:NewCell()
        local index = firstRow * self.columns + slot
        local record = records[index]
        cell.button.root.hidden = record == nil
        if record then
            cell.button.root:SetPos(left + ((index - 1) % self.columns) * CELL + 4,
                math.floor((index - 1) / self.columns) * CELL + 4)
            if cell.record ~= record then
                Sprites.Clear(cell.button.content)
                Sprites.Clear(cell.item)
                local target = record.objectID and cell.item or cell.button.content
                target.hidden = not Sprites.Apply(target, record.name)
                cell.button:SetActive(record.name == self.selected)
                cell.record = record
            end
        else
            if cell.record then Sprites.Clear(cell.button.content); Sprites.Clear(cell.item) end
            cell.record = nil
        end
    end
    for index = count + 1, #self.cells do
        local cell = self.cells[index]
        cell.button.root.hidden = true
        if cell.record then Sprites.Clear(cell.button.content); Sprites.Clear(cell.item) end
        cell.record = nil
    end
end

function Browser:Refresh()
    local total = #self.query.results
    local progress = self.directory:IsComplete(self.itemsOnly) and "Searching... "
        or (self.itemsOnly and "Indexing items... " or "Indexing sprites and items... ")
    self.status.content = (self.query.complete and "" or progress) .. total .. (total == 1 and " result" or " results")
    self.empty.content = total == 0 and (self.query.complete
        and (self.itemsOnly and "No matching items." or "No matching sprites or items.")
        or (self.itemsOnly and "Searching items..." or "Searching sprites and items...")) or ""
    if #self.query.words == 0 then
        self.status.content = ""
        self.empty.content = self.itemsOnly and "Type an item name to search." or "Type a sprite or item name to search."
    elseif self.directory.unavailable and total == 0 then
        self.status.content = self.itemsOnly and "Game item names could not be read." or "Game sprite and item names could not be read."
        self.empty.content = self.itemsOnly and "The game returned no usable item names." or "The game returned no usable icon names."
    end
    self.view:SetContentHeight(math.ceil(total / self.columns) * CELL)
end

function Browser:Resize(width, height)
    self.root:SetSize(width + 16, height)
    self.largePreview = height >= 320
    local previewHeight = self.largePreview and 76 or 0
    self.search.root:SetSize(width, 28)
    local viewHeight = math.max(1, height - 112 - previewHeight)
    local visibleRows = math.ceil(viewHeight / CELL) + 1
    local maxColumns = math.max(1, math.floor(MAX_VISIBLE_CELLS / visibleRows))
    self.columns = math.max(1, math.min(maxColumns, math.floor((width - 18) / CELL)))
    self.view:SetSize(width, viewHeight)
    self.empty:SetPos(6, 6)
    self.empty:SetSize(math.max(1, self.view.contentWidth - 12), 44)
    self.status:SetPos(8, height - 64)
    self.status:SetSize(width - 8, 22)
    local previewY = height - 64 - previewHeight
    self.previewSprite:SetPos(8, previewY + 4)
    self.previewItem:SetPos(8, previewY + 4)
    local showPreview = self.largePreview and self.previewApplied and self.previewRecord
    self.previewSprite.hidden = not showPreview or self.previewRecord.objectID ~= nil
    self.previewItem.hidden = not showPreview or self.previewRecord.objectID == nil
    self.previewName:SetPos(82, previewY + 2)
    self.previewName:SetSize(math.max(1, width - 88), 70)
    self.previewName.hidden = not self.largePreview
    local buttonWidth = math.min(100, math.floor((width - 16) / 2))
    self.none.root:SetPos(8, height - 34)
    self.none.root:SetSize(buttonWidth, 28)
    self.back.root:SetPos(width - buttonWidth, height - 34)
    self.back.root:SetSize(buttonWidth, 28)
    self:Refresh()
end

function Browser:Tick()
    if self.destroyed then return end
    if self.query.complete and self.directory:IsComplete(self.itemsOnly) then return end
    self.directory:Discover({itemsOnly = self.itemsOnly})
    if self.query.complete then return end
    if self.searchDelay and self.searchDelay > 0 then self.searchDelay = self.searchDelay - 1; return end
    if self.directory:Continue(self.query, true) then self:Refresh() end
end

function Browser:Destroy(detached)
    if self.destroyed then return end
    self.destroyed = true
    self.view.onLayout = nil
    self.hoveredCell = nil
    if self.sharedTooltip then
        if detached then Detached.Tooltip(self.sharedTooltip) end
        self.sharedTooltip:Destroy()
        self.sharedTooltip = nil
    end
    if detached then Detached.Tooltips(self.root)
    else Sprites.Clear(self.previewSprite); Sprites.Clear(self.previewItem) end
    for _, cell in ipairs(self.cells) do
        if not detached then Sprites.Clear(cell.button.content); Sprites.Clear(cell.item) end
        cell.record = nil
        if detached then Detached.Control(cell.button) else cell.button:Destroy() end
    end
    self.cells = {}
    for _, control in ipairs({self.search, self.none, self.back, self.view}) do
        if detached then Detached.Control(control) else control:Destroy() end
    end
    prettyui.Tooltip.unregisterContext(self.root)
    if not detached then self.root:Destroy() end
    self.query, self.directory, self.previewRecord = nil, nil, nil
    self.tooltipTarget = nil
    self.choose = nil
end

return Browser
