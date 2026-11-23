local Components = require("src/ui/shared/components")
local Base = require("src/ui/views/view")
local Notes = require("src/notes/notes")
local Selection = require("src/notes/share_selection")
local TextLayout = require("src/ui/shared/text_layout")

local ShareSelection = {}
ShareSelection.__index = ShareSelection
setmetatable(ShareSelection, {__index = Base})

local ROW_HEIGHT = 44
-- Notes are laid out in columns at least this wide, as many as fit.
local MIN_COLUMN = 260
local MUTED = 0xB7B1A7FF
local WARNING = 0xFFAA77FF
local READY = 0x55FF55FF

local function plain(value)
    return tostring(value or ""):gsub("<[Bb][Rr]%s*/?>", " "):gsub("<", "["):gsub(">", "]"):gsub("[%c]", " ")
end

local function number(value)
    return tostring(value):reverse():gsub("(%d%d%d)", "%1,"):gsub(",$", ""):reverse()
end

function ShareSelection.new(parent, options, callbacks)
    local self = Base.Init(setmetatable({}, ShareSelection), parent, options, callbacks)
    self.session, self.rows = options.selection or {}, {}
    self.selection = Selection.New(self.data, self.session.selected)
    self:Heading("Share notes")
    self.instruction = Base.Label(self.surface, "Choose notes to share.", 8, 6, self.width - 8, 20, MUTED)
    self.selectAllButton = self:Button("Select all", 8, 32, 100, function() self:SetAll(true) end)
    self.clearButton = self:Button("Clear", 116, 32, 100, function() self:SetAll(false) end)
    self.count = Base.Label(self.surface, "", 8, 66, self.width - 8, 18)
    self.budget = Base.Label(self.surface, "", 8, 86, self.width - 8, 18)
    self.message = Base.Label(self.surface, "", 8, 106, self.width - 8, 18, MUTED)
    self.listScroll = self:Track(prettyui.SimpleView.new(self.surface, Components.Options({
        x = 8, y = 130, width = self.width, height = math.max(1, self.height - 176), scrollStep = ROW_HEIGHT
    })))
    self.listScroll.onLayout = function() self:DrawRows() end
    self.listScroll:SetContentHeight(#self.data.notes * ROW_HEIGHT)
    self.empty = Base.Label(self.listScroll.content, "No notes to share.", 8, 6,
        self.listScroll.contentWidth - 16, 36, MUTED)
    self.shareButton = self:Button("Share selected", 8, self.height - 34, 160, function() self:ShareSelected() end)
    self.backButton = self:Button("Back", self.width - 88, self.height - 34, 88, function() self:ShowList() end)
    self.layout = function() self:Layout() end
    self:RefreshSelection()
    self.listScroll:SetScrollPosition(self.session.scroll or 0)
    return self
end

-- How many columns fit the list at its current width.
function ShareSelection:Columns()
    local width = self.listScroll and self.listScroll.contentWidth or self.width
    return math.max(1, math.floor(math.max(1, width - 8) / MIN_COLUMN))
end

-- The characters this note takes up in a share code on its own.
function ShareSelection:NoteSize(note)
    self.sizes = self.sizes or {}
    local size = self.sizes[note]
    if size == nil then
        local categories = {}
        for _, category in ipairs(self.data.categories or {}) do
            if category.id == note.categoryID then categories[#categories + 1] = category end
        end
        local ok, code = pcall(Notes.Export, {notes = {note}, categories = categories})
        size = ok and type(code) == "string" and #code or false
        self.sizes[note] = size
    end
    return size or nil
end

function ShareSelection:NewRow()
    local row = {}
    row.control = self:Track(prettyui.CheckboxButton.new(self.listScroll.content,
        {{value = "selected", label = ""}}, Components.Options({
            width = math.max(1, self.listScroll.contentWidth - 8),
            _onScrollWheel = self.listScroll._onScrollWheel,
            onChange = function(control)
                if self.destroyed or self.clearing or not row.note or control.root.hidden then return end
                self.selection:SetSelected(row.note, control:IsSelected("selected"))
                self:RefreshSelection()
            end
        })))
    local item = row.control.items[1]
    item.row:SetSize(0, ROW_HEIGHT, 1)
    item.box:SetPos(0, 15)
    item.label:SetPos(22, 1)
    item.label:SetSize(-22, 22, 1)
    item.label.font = id.Font.MUSEO_SANS_13PT_REGULAR
    row.category = Base.Label(row.control.root, "", 22, 23, 1, 18, MUTED)
    row.category.maxLines = 1
    self.rows[#self.rows + 1] = row
    return row
end

function ShareSelection:DrawRows()
    if self.destroyed or self.clearing or not self.listScroll then return end
    local columns = self:Columns()
    local rowsNeeded = math.ceil(#self.data.notes / columns)
    if self.columns ~= columns then
        self.columns = columns
        self.listScroll:SetContentHeight(rowsNeeded * ROW_HEIGHT)
    end
    local firstRow = math.max(0, math.floor(self.listScroll.scrollY / ROW_HEIGHT))
    local visibleRows = math.ceil(self.listScroll.root.height / ROW_HEIGHT) + 1
    local count = visibleRows * columns
    local total = math.max(1, self.listScroll.contentWidth - 8)
    local width = math.max(1, math.floor(total / columns))
    for index = 1, count do
        local noteIndex = firstRow * columns + index
        local note = self.data.notes[noteIndex]
        local row = self.rows[index]
        if note then
            row = row or self:NewRow()
            row.note, row.index = note, noteIndex
            local column, line = (noteIndex - 1) % columns, math.floor((noteIndex - 1) / columns)
            row.control.root:SetPos(4 + column * width, line * ROW_HEIGHT)
            row.control.root:SetSize(width - 4, ROW_HEIGHT)
            row.control.root.hidden = false
            row.control:SetDisabled(false)
            local title = note.title ~= "" and note.title or (note.text or ""):match("[^\r\n]+")
            if not title or not title:match("%S") then title = "Untitled note" end
            local size = self:NoteSize(note)
            local shown = plain(title) .. (size and " (" .. number(size) .. ")" or "")
            local item = row.control.items[1]
            item.text, item.label.content = shown, shown
            row.control.textColour = (tonumber(note.color or "FFFFFF", 16) or 0xFFFFFF) * 256 + 255
            row.control:SetSelected("selected", self.selection:IsSelected(note), false)
            item.label.rgba = row.control.textColour
            row.category.content = plain(Notes.CategoryName(self.data, note.categoryID))
            row.category:SetSize(math.max(1, width - 26), 18)
        elseif row then
            row.note, row.index = nil, nil
            row.control.root.hidden = true
            row.control:SetDisabled(true)
        end
    end
    for index = count + 1, #self.rows do
        local row = self.rows[index]
        row.note, row.index = nil, nil
        row.control.root.hidden = true
        row.control:SetDisabled(true)
    end
    if self.empty then self.empty.hidden = #self.data.notes > 0 end
end

function ShareSelection:RefreshSelection()
    if self.destroyed or self.clearing then return end
    self.code, self.selectedCount, self.totalCount, self.selectedData = self.selection:Export()
    self.canShare = self.selectedCount > 0 and #self.code <= Selection.LIMIT
    self.shareButton:SetDisabled(not self.canShare)
    self.selectAllButton:SetDisabled(self.selectedCount == self.totalCount)
    self.clearButton:SetDisabled(self.selectedCount == 0)
    self.budget.rgba = #self.code > Selection.LIMIT and WARNING or self.canShare and READY or MUTED
    self.message.rgba = #self.code > Selection.LIMIT and WARNING or MUTED
    self.messageText = self.selectedCount == 0 and "Select at least one note."
        or #self.code > Selection.LIMIT and "Over limit. Deselect notes." or "Ready to share."
    self:Layout()
end

function ShareSelection:SetAll(selected)
    if self.destroyed or self.clearing then return end
    self.selection:SetAll(selected)
    self:RefreshSelection()
end

function ShareSelection:ShareSelected()
    if self.destroyed or self.clearing then return end
    self:RefreshSelection()
    if not self.canShare then return end
    self:Navigate("share", {data = self.selectedData, selection = self:Snapshot()})
end

function ShareSelection:Snapshot()
    if not self.destroyed then
        self.session.selected = self.selection:Snapshot()
        self.session.scroll = self.listScroll.scrollY
    end
    return self.session
end

function ShareSelection:Layout()
    local width, height = self.width, self.height
    local compact = height < 300
    local available = math.max(1, width - 8)
    local font = config.Font.MUSEO_SANS_13PT_REGULAR
    local function place(control, value, y)
        local lines = TextLayout.Lines(value, font, available)
        control.content = table.concat(lines, "<br>")
        control:SetPos(8, y)
        control:SetSize(available, math.max(18, #lines * 18))
        return y + control.height + 2
    end
    self.instruction.hidden = compact
    self.instruction:SetSize(available, 20)
    local y = compact and 6 or 32
    local actionWidth = math.min(110, math.floor((width - 16) / 2))
    self.selectAllButton.root:SetPos(8, y)
    self.selectAllButton.root:SetSize(actionWidth, 28)
    self.clearButton.root:SetPos(16 + actionWidth, y)
    self.clearButton.root:SetSize(actionWidth, 28)
    y = place(self.count, self.selectedCount .. " / " .. self.totalCount .. (compact and " selected" or " notes selected"), y + 36)
    y = place(self.budget, number(#self.code) .. " / 9,999 characters", y)
    local messageY = y
    y = place(self.message, self.messageText, y)
    self.message.hidden = height - 46 - y < ROW_HEIGHT
    if self.message.hidden then y = messageY end
    local listY = y + 4
    self.listScroll.root:SetPos(8, listY)
    self.listScroll:SetSize(width, math.max(1, height - 46 - listY))
    self.columns = nil
    self.empty:SetSize(math.max(1, self.listScroll.contentWidth - 16), 36)
    local footerWidth = math.min(160, math.floor((width - 16) / 2))
    self.shareButton.content.content = width < 340 and "Share" or "Share selected"
    self.shareButton.root:SetPos(8, height - 34)
    self.shareButton.root:SetSize(footerWidth, 28)
    self.backButton.root:SetPos(width - footerWidth, height - 34)
    self.backButton.root:SetSize(footerWidth, 28)
    self:DrawRows()
end

function ShareSelection:Destroy(detached)
    if self.destroyed then return end
    if self.listScroll then self.listScroll.onLayout = nil end
    Base.Destroy(self, detached)
    self.listScroll, self.rows = nil, {}
end

return ShareSelection
