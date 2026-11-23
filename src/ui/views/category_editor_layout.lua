local Components = require("src/ui/shared/components")
local Base = require("src/ui/views/view")
local Notes = require("src/notes/notes")
local Settings = require("src/core/settings")
local TextLayout = require("src/ui/shared/text_layout")
local Overlay = require("src/ui/window/overlay")
local WindowStyle = require("src/ui/window/window_style")

local Layout = {}
local GOLD = 0xE7D7B0FF

local function place(component, x, y, width, height)
    width, height = math.max(1, width), math.max(1, height)
    if component.x ~= x or component.y ~= y then component:SetPos(x, y) end
    if component.width ~= width or component.height ~= height then component:SetSize(width, height) end
end

local function contentHeight(scroll, height)
    height = math.max(0, math.floor(height))
    if scroll.requestedContentHeight ~= height or scroll.width ~= scroll.root.width
        or scroll.height ~= scroll.root.height then scroll:SetContentHeight(height) end
end

function Layout.Build(self)
    local draft = self.categoryDraft
    self:Heading(draft.id and "Edit category" or "New category")
    local chrome = self.window.chrome
    self.previousMinHeight = chrome.minHeight
    self.previousResizeMinHeight = chrome.resize and chrome.resize.minHeight
    local minimumHeight = math.min(self.parent.height, math.max(chrome.minHeight, 320))
    chrome.minHeight = minimumHeight
    if chrome.resize then chrome.resize.minHeight = minimumHeight end
    if self.window.root.height < minimumHeight then self.window:SetHeight(minimumHeight) end
    self.height = self.window.height
    self.categoryScroll = self:Track(prettyui.SimpleView.new(self.surface, Components.Options({
        x = 8, y = 6, width = self.width, height = math.max(1, self.height - 102), scrollStep = 40
    })))
    local body, surface = self.categoryScroll.content, self.surface
    self.categoryNameLabel = Base.Label(body, "Category name", 8, 0, self.width, 20, GOLD)
    self.categoryNameFrame = Base.EditorFrame(body, self.width)
    self.categoryNameField = self:TrackField(prettyui.TextField.new(body, Components.Options({
        text = draft.name, placeholder = "Category name", maxLength = Notes.MAX_CATEGORY_NAME,
        stylesheetID = id.StyleSheet.INPUT_INVISIBLE, contentMargin = ui.Margin.new(12, 8, 12, 8),
        width = self.width, height = 38,
        onChange = function(_, _, value)
            if self.destroyed or self.clearing then return end
            draft.name, draft.confirmDelete = value, false
            self:Status("")
            self:RefreshCategoryAppearance()
        end
    })))
    self.categoryNameField.root.text.alignHorizontal = ui.AlignMode.TOPLEFT
    self.categoryNameField.root.text.alignVertical = ui.AlignMode.CENTRE
    self.categoryNameField.root.text.maxLines = 1
    self.categoryNameField.root.scrollbar.visible, self.categoryNameField.root.scrollbar.size = false, 0
    self.categoryIconLabel = Base.Label(body, "Icon", 8, 0, 80, 20, GOLD)
    self.categoryIconSlot = self:Track(prettyui.ItemSlot.new(body, nil, Components.Options({
        backgroundSpriteID = id.Sprite.RS3_ICON_SLOT_STANDARD,
        quantityMode = ui.ObjectQuantityDisplayMode.NEVER, clickthrough = false
    })))
    self.categorySprite = Components.New(ui.Sprite, self.categoryIconSlot.root)
    self.categorySprite:SetPos(4, 4); self.categorySprite:SetSize(32, 32)
    self.categorySprite.clickthrough = true
    local function chooseIcon()
        if self.destroyed or self.clearing then return end
        self:Snapshot()
        self:Navigate("categorySprites", {draft = draft})
    end
    self.categoryIconSlot.root:Subscribe(ui.Hook.ONCLICK, function() chooseIcon(); return false end)
    self.surface = body
    self.categorySpriteButton = self:Button("Choose icon", 0, 0, 120, chooseIcon)
    self.categorySpriteButton:SetTooltip("Search game sprites and items")
    WindowStyle.ApplyTooltip(self.categorySpriteButton.tooltip)
    self.categoryColorLabel = Base.Label(body, "Color", 8, 0, 80, 20, GOLD)
    self.categoryColorField = self:Field(draft.color or "", 0, 0, 100, 28, 7, function(_, value)
        draft.color = value ~= "" and value:gsub("^#", ""):upper() or nil
        if draft.color == nil or draft.color:match("^%x%x%x%x%x%x$") then
            self.categoryColorPicker:SetValue(tonumber(draft.color or "D8D1C4", 16) * 256 + 255, false)
        end
        self:RefreshCategoryAppearance()
        self:Status("")
    end)
    self.categoryColorField.root.emptyText = "Default"
    self.categoryColorPicker = self:Track(prettyui.ColourPicker.new(body, Components.Options({
        width = 28, height = 28,
        value = tonumber(Settings.NormalizeHex(draft.color, "D8D1C4"), 16) * 256 + 255,
        windowParent = self.parent, windowTitle = "Category color", alphaSlider = false,
        onChange = function(_, value)
            if self.destroyed or self.clearing then return end
            draft.color = string.format("%06X", math.floor(value / 256) % 0x1000000)
            self.categoryColorField:SetText(draft.color, false)
            self:RefreshCategoryAppearance()
            self:Status("")
        end
    })))
    local open = self.categoryColorPicker.Open
    function self.categoryColorPicker.Open(picker)
        picker.options.windowX, picker.options.windowY = Overlay.Clamp(self.parent,
            self.window.root.x + 20, self.window.root.y + 30, 220, 300)
        return open(picker)
    end
    self.categoryDefaultColorButton = self:Button(id.Sprite.RS3_ICON_LOBBY_REFRESH_0, 0, 0, 28, function()
        draft.color = nil
        self.categoryColorField:SetText("", false)
        self.categoryColorPicker:SetValue(0xD8D1C4FF, false)
        self:RefreshCategoryAppearance()
        self:Status("")
    end)
    self.categoryDefaultColorButton:SetTooltip("Use default category color")
    WindowStyle.ApplyTooltip(self.categoryDefaultColorButton.tooltip)
    self.categoryDeleteHint = Base.Label(body, "Deleting a category moves its notes to Uncategorized.",
        8, 0, self.width, 40, 0xB7B1A7FF)
    self.categoryDeleteHint.hidden = draft.id == nil
    self.surface = surface
    self.footerDivider = self:Track(prettyui.Divider.new(surface, Components.Options({width = self.width})))
    self.status = Base.Label(surface, "", 8, 0, self.width, 40, 0xFFAA77FF)
    self.saveButton = self:Track(prettyui.FancyButton.new(surface, "Save category", function()
        if not self.destroyed and not self.clearing then self:SaveDraft() end
    end, Components.Options({variant = "positive"})))
    self.saveButtonWidth, self.saveButtonHeight = self.saveButton.root.width, self.saveButton.root.height
    self.cancelButton = self:Button("Cancel", 0, 0, 80, function() self:ShowList() end)
    if draft.id then self.deleteButton = self:Button("Delete", 0, 0, 80, function() self:DeleteCategory() end) end
    self.categoryClipComponents = {self.categoryNameField.root, self.categoryNameFrame,
        self.categoryIconSlot.root, self.categorySpriteButton.root, self.categoryColorField.root,
        self.categoryColorPicker.root, self.categoryDefaultColorButton.root}
    self.categoryScroll.onLayout = function()
        if not self.layingOutCategory then self:ClipCategoryFields() end
    end
    self.layout = function() Layout.Update(self) end
    self:RefreshCategoryAppearance()
    self.layout()
    if self.categoryScroll.scrollY ~= (draft.scroll or 0) then self.categoryScroll:SetScrollPosition(draft.scroll or 0) end
    self:ClipCategoryFields()
end

function Layout.Update(self)
    if self.layingOutCategory then return end
    self.layingOutCategory = true
    local width, height = math.max(1, self.width), self.height
    if self.surface.width ~= self.window.width or self.surface.height ~= height then
        self.surface:SetSize(self.window.width, height)
    end
    local wide = width >= 520
    local compactFooter = width < self.saveButtonWidth + 96 + (self.deleteButton and 96 or 0)
    local footerHeight = compactFooter and self.deleteButton and 132 or 96
    footerHeight = math.min(footerHeight, math.max(80, height - 52))
    local scrollHeight = math.max(1, height - footerHeight - 12)
    if self.categoryScroll.root.width ~= width or self.categoryScroll.root.height ~= scrollHeight
        or self.categoryScroll.width ~= width or self.categoryScroll.height ~= scrollHeight then
        self.categoryScroll:SetSize(width, scrollHeight)
    end
    local fontName = Base.NoteFont(self.settings)
    local font, fontID = config.Font[fontName], id.Font[fontName]
    for _ = 1, 2 do
        local contentWidth = math.max(1, self.categoryScroll.contentWidth - 16)
        local nameX, nameY = width >= 640 and 140 or 8, width >= 640 and 0 or 22
        place(self.categoryNameLabel, 8, width >= 640 and 8 or 0, 124, 20)
        place(self.categoryNameField.root, nameX, nameY, contentWidth - nameX + 8, 38)
        place(self.categoryNameFrame, nameX, nameY, contentWidth - nameX + 8, 38)
        if self.categoryNameField.root.text.font ~= fontID then self.categoryNameField.root.text.font = fontID end
        local lineHeight = math.max(font.baseline, font.maxAscent + font.maxDescent)
        local margin = math.max(0, math.floor((38 - lineHeight) / 2))
        if self.categoryNameField.verticalMargin ~= margin then
            self.categoryNameField.verticalMargin = margin
            self.categoryNameField.root.contentMargin = ui.Margin.new(12, margin, 12, margin)
        end
        local rowY = nameY + 54
        local iconWidth = wide and math.floor((contentWidth - 12) * 0.55) or contentWidth
        local colorX, colorY = wide and iconWidth + 20 or 8, wide and rowY or rowY + 74
        local colorWidth = wide and contentWidth - iconWidth - 12 or contentWidth
        place(self.categoryIconLabel, 8, rowY, iconWidth, 20)
        place(self.categoryIconSlot.root, 8, rowY + 22, 40, 40)
        place(self.categorySpriteButton.root, 56, rowY + 28, iconWidth - 48, 28)
        place(self.categoryColorLabel, colorX, colorY, colorWidth, 20)
        place(self.categoryColorPicker.root, colorX, colorY + 22, 28, 28)
        place(self.categoryColorField.root, colorX + 36, colorY + 22, math.min(120, colorWidth - 72), 28)
        place(self.categoryDefaultColorButton.root, colorX + math.min(120, colorWidth - 72) + 44, colorY + 22, 28, 28)
        local bottom = math.max(rowY + 62, colorY + 50) + 16
        if self.categoryDraft.id then
            local hintFont = config.Font.MUSEO_SANS_13PT_REGULAR
            local hintHeight = #TextLayout.Lines(self.categoryDeleteHint.content, hintFont, contentWidth) * hintFont.baseline
            place(self.categoryDeleteHint, 8, bottom, contentWidth, hintHeight)
            bottom = bottom + hintHeight + 8
        end
        contentHeight(self.categoryScroll, bottom)
        if self.categoryScroll.contentWidth - 16 == contentWidth then break end
    end
    place(self.footerDivider.root, 8, math.max(0, height - footerHeight - 28), width, 60)
    local buttonsY = height - (compactFooter and self.deleteButton and 70 or 34)
    local statusY = height - footerHeight + 8
    place(self.status, 8, statusY, width, math.min(44, buttonsY - statusY - 6))
    if self.categoryCompactFooter ~= compactFooter then
        self.categoryCompactFooter = compactFooter
        self.saveButton:SetText(compactFooter and "Save" or "Save category")
    end
    local saveWidth = self.saveButtonWidth
    if compactFooter then
        local minimumSaveWidth = self.saveButton.left.width + self.saveButton.right.width
            + config.Font.CINZEL_13PT_BOLD:GetStringWidth("Save", false) + 4
        saveWidth = math.min(math.max(math.floor((width - 8) / 2), minimumSaveWidth), math.max(1, width - 76))
    end
    place(self.saveButton.root, 8, buttonsY, saveWidth, self.saveButtonHeight)
    place(self.cancelButton.root, saveWidth + 16, buttonsY, compactFooter and width - saveWidth - 8 or 80, 28)
    self.cancelButton.content.font = id.Font.MUSEO_SANS_13PT_REGULAR
    if self.deleteButton then
        place(self.deleteButton.root, width - 72, height - 34, 80, 28)
        self.deleteButton.content.font = id.Font.MUSEO_SANS_13PT_REGULAR
    end
    self.layingOutCategory = false
    self:ClipCategoryFields()
end

function Layout.Clip(self)
    if not self.categoryScroll or self.layingOutCategory then return end
    local scroll, height = self.categoryScroll.scrollY, self.categoryScroll.root.height
    for _, component in ipairs(self.categoryClipComponents or {}) do
        local top = component.y - scroll
        local hidden = top < 0 or top + component.height > height
        if component.hidden ~= hidden then component.hidden = hidden end
    end
end

return Layout
