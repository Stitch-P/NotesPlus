local Components = require("src/ui/shared/components")
local Base = require("src/ui/views/view")
local Notes = require("src/notes/notes")
local Gear = require("src/notes/gear")
local ActionBar = require("src/notes/action_bar")
local TextLayout = require("src/ui/shared/text_layout")
local Detached = require("src/ui/shared/detached_ui")
local ImportPreview = require("src/notes/import_preview")

local Preview = {}
Preview.__index = Preview

local PAGE_SIZE = 8
local MUTED, GOLD = 0xB7B1A7FF, 0xE7D7B0FF

local function count(value, singular, plural)
    return value .. " " .. (value == 1 and singular or plural or singular .. "s")
end

local function plain(value, maximum)
    value = tostring(value or ""):gsub("<[Bb][Rr]%s*/?>", "\n"):gsub("<", "["):gsub(">", "]")
    if maximum and #value > maximum then
        local ending = maximum
        while ending > 0 and (value:byte(ending + 1) or 0) >= 128 and (value:byte(ending + 1) or 0) < 192 do
            ending = ending - 1
        end
        value = value:sub(1, ending) .. "..."
    end
    return value
end

function Preview.new(parent, onSelectionChanged)
    local self = setmetatable({page = 1, pages = 1, rows = {}, entries = {}}, Preview)
    self.onSelectionChanged = onSelectionChanged
    self.root = Components.Host(parent)
    self.root.hidden, self.root.clickthrough = true, false
    self.scroll = prettyui.SimpleView.new(self.root, Components.Options({width = 1, height = 1, scrollStep = 36}))
    self.summary = Base.Label(self.scroll.content, "", 6, 6, 1, 20, GOLD)
    self.notice = Base.Label(self.scroll.content, "Existing notes are kept. Importing the same notes again adds copies.",
        6, 6, 1, 20, MUTED)
    self.selectAllButton = prettyui.SimpleButton.new(self.scroll.content, "Select all", function() self:SetAll(true) end,
        Components.Options({width = 120, height = 28, _onScrollWheel = self.scroll._onScrollWheel}))
    self.deselectAllButton = prettyui.SimpleButton.new(self.scroll.content, "Deselect all", function() self:SetAll(false) end,
        Components.Options({width = 120, height = 28, _onScrollWheel = self.scroll._onScrollWheel}))
    for index = 1, PAGE_SIZE do
        local row = {
            title = Base.Label(self.scroll.content, "", 6, 6, 1, 20),
            metadata = Base.Label(self.scroll.content, "", 6, 6, 1, 20, MUTED),
            subject = Base.Label(self.scroll.content, "", 6, 6, 1, 20, MUTED)
        }
        row.selection = prettyui.CheckboxButton.new(self.scroll.content, {{text = "", value = "selected"}}, Components.Options({
            width = 24, _onScrollWheel = self.scroll._onScrollWheel,
            onChange = function(control)
                if self.destroyed or not row.entry or row.entry.kind ~= "note" or control.root.hidden then return end
                self:SetSelected(row.entry.index, control:IsSelected("selected"))
            end
        }))
        row.selection.items[1].label.hidden = true
        self.rows[index] = row
    end
    self.previousButton = prettyui.SpriteButton.new(self.root, "ARROW_LEFT", function() self:NextPage(-1) end,
        Components.Options({width = 24, height = 24}))
    self.nextButton = prettyui.SpriteButton.new(self.root, "ARROW_RIGHT", function() self:NextPage(1) end,
        Components.Options({width = 24, height = 24}))
    self.pageLabel = Base.Label(self.root, "", 32, 0, 1, 24, MUTED)
    self.pageLabel.alignHorizontal = ui.AlignMode.CENTRE
    return self
end

function Preview:SetSource(source, destination, selected)
    self.source, self.destination, self.selected, self.page = source, destination, {}, 1
    for index in ipairs(source.notes) do
        if selected == nil or selected[index] == true then self.selected[index] = true end
    end
    self:RefreshSelection()
    self.scroll:SetScrollPosition(0)
end

function Preview:SelectionSnapshot()
    local selected = {}
    for index, value in pairs(self.selected or {}) do selected[index] = value end
    return selected
end

function Preview:RefreshSelection()
    if self.destroyed or not self.source then return end
    self.selectedCount = 0
    for index in ipairs(self.source.notes) do
        if self.selected[index] then self.selectedCount = self.selectedCount + 1 end
    end
    self.plan, self.error = ImportPreview.BuildSelection(self.destination, self.source, self.selected)
    self.entries = {}
    for index, note in ipairs(self.source.notes) do
        self.entries[#self.entries + 1] = {kind = "note", note = note, index = index}
    end
    for _, change in ipairs(self.plan and self.plan.categoryChanges or {}) do
        self.entries[#self.entries + 1] = {kind = "category", change = change}
    end
    self.pages = math.max(1, math.ceil(#self.entries / PAGE_SIZE))
    self.page = math.min(self.page, self.pages)
    self:Layout()
    if self.onSelectionChanged then self.onSelectionChanged(self) end
end

function Preview:SetSelected(index, selected)
    if self.destroyed or self.root.hidden or not self.source or self.source.notes[index] == nil then return end
    self.selected[index] = selected == true and true or nil
    self:RefreshSelection()
end

function Preview:SetAll(selected)
    if self.destroyed or self.root.hidden or not self.source then return end
    self.selected = {}
    if selected then for index in ipairs(self.source.notes) do self.selected[index] = true end end
    self:RefreshSelection()
end

function Preview:NextPage(direction)
    if self.destroyed or not self.source then return end
    self.page = math.max(1, math.min(self.pages, self.page + direction))
    self.scroll:SetScrollPosition(0)
    self:Layout()
end

function Preview:SetBounds(x, y, width, height)
    self.hasBounds = true
    self.root:SetPos(x, y)
    self.root:SetSize(math.max(1, width), math.max(1, height))
    self:Layout()
end

function Preview:DrawRows()
    local width = math.max(1, self.scroll.contentWidth - 12)
    local font = config.Font.MUSEO_SANS_13PT_REGULAR
    local y = 6
    local function line(label, value, gap, inset)
        inset = inset or 0
        local available = math.max(1, width - inset)
        local lines = TextLayout.Lines(value, font, available)
        label.content = table.concat(lines, "<br>")
        label.font = id.Font.MUSEO_SANS_13PT_REGULAR
        label:SetPos(6 + inset, y)
        label:SetSize(available, math.max(inset > 0 and 28 or 18, #lines * font.baseline + 2))
        label.hidden = value == ""
        if value ~= "" then y = y + label.height + (gap or 4) end
    end
    local plan = self.plan
    local total = #self.source.notes
    local heading = self.error and "Import blocked: " or "Import preview: "
    local summary = heading .. self.selectedCount .. " / " .. count(total, "note") .. " selected"
    if plan then
        summary = summary .. ", " .. count(plan.newCategoryCount, "new category", "new categories")
            .. ", " .. count(plan.changedCategoryCount, "category appearance change")
    end
    line(self.summary, summary .. ".")
    self.notice.rgba = self.error and 0xFF3333FF or MUTED
    line(self.notice, self.error and plain(self.error, 480)
        or total > 0 and self.selectedCount == 0 and "Select at least one note to import."
        or "Only selected notes and their categories will be added. Existing notes are kept; importing again adds copies.", 8)
    local buttonsVisible = total > 0
    self.selectAllButton.root.hidden, self.deselectAllButton.root.hidden = not buttonsVisible, not buttonsVisible
    self.selectAllButton:SetDisabled(self.selectedCount == total)
    self.deselectAllButton:SetDisabled(self.selectedCount == 0)
    if buttonsVisible then
        local inline = width >= 220
        local buttonWidth = math.max(1, math.min(120, inline and (width - 8) / 2 or width))
        self.selectAllButton.root:SetPos(6, y)
        self.selectAllButton.root:SetSize(buttonWidth, 28)
        self.deselectAllButton.root:SetPos(inline and 14 + buttonWidth or 6, y + (inline and 0 or 32))
        self.deselectAllButton.root:SetSize(buttonWidth, 28)
        y = y + (inline and 40 or 72)
    end
    for index, row in ipairs(self.rows) do
        local entry = self.entries[(self.page - 1) * PAGE_SIZE + index]
        row.entry = entry
        row.selection.root.hidden = not entry or entry.kind ~= "note"
        row.selection:SetDisabled(not entry or entry.kind ~= "note")
        if entry then
            if entry.kind == "category" then
                local change = entry.change
                row.title.rgba = GOLD
                line(row.title, "Category: " .. plain(change.name) .. (change.kind == "added" and " (new)" or " (appearance change)"))
                local before, after = change.before, change.after
                local details = {}
                if before and before.skill ~= after.skill then
                    details[#details + 1] = after.skill and "Icon will change" or "Icon will reset to default"
                elseif not before and after.skill then details[#details + 1] = "Custom icon" end
                if not before or before.color ~= after.color then
                    details[#details + 1] = "Color: " .. (before and (before.color and "#" .. before.color or "default") .. " -> " or "")
                        .. (after.color and "#" .. after.color or "default")
                end
                line(row.metadata, table.concat(details, " | "))
                line(row.subject, before and "The existing category's appearance will be updated." or "This category will be added.", 12)
            else
                local note = entry.note
                local title = note.title ~= "" and note.title or "Untitled note"
                row.selection:SetSelected("selected", self.selected[entry.index] == true, false)
                row.selection.root:SetPos(6, y)
                row.title.rgba = self.selected[entry.index] and tonumber(note.color, 16) * 256 + 255 or MUTED
                line(row.title, entry.index .. ". " .. plain(title), nil, 24)
                local details = {"Category: " .. plain(Notes.CategoryName(self.source, note.categoryID))}
                if note.tracking then details[#details + 1] = "Tracking: " .. plain(note.tracking.label or note.tracking.category, 160) end
                if note.gear then details[#details + 1] = "Gear: " .. count(Gear.Count(note.gear), "item") end
                if note.actionBar then details[#details + 1] = "Action bar: " .. count(ActionBar.Count(note.actionBar), "action") end
                if note.notifyChat then details[#details + 1] = "Chat notifications" end
                if note.notifyPopup then details[#details + 1] = "Popup notifications" end
                line(row.metadata, table.concat(details, " | "))
                line(row.subject, note.text ~= "" and (#note.text > 480 and "Subject excerpt: " or "Subject: ")
                    .. plain(note.text, 480) or "No subject.", 12)
            end
        else
            row.title.hidden, row.metadata.hidden, row.subject.hidden = true, true, true
        end
    end
    self.scroll:SetContentHeight(y)
end

function Preview:Layout()
    if self.destroyed or not self.source or not self.hasBounds then return end
    local paging = self.pages > 1
    local height = self.root.height
    self.scroll:SetSize(self.root.width, math.max(1, height - (paging and 32 or 0)))
    for _ = 1, 2 do
        local width = self.scroll.contentWidth
        self:DrawRows()
        if width == self.scroll.contentWidth then break end
    end
    self.previousButton.root.hidden, self.nextButton.root.hidden, self.pageLabel.hidden = not paging, not paging, not paging
    self.previousButton:SetDisabled(self.page <= 1)
    self.nextButton:SetDisabled(self.page >= self.pages)
    self.previousButton.root:SetPos(4, math.max(0, height - 26))
    self.nextButton.root:SetPos(math.max(4, self.root.width - 28), math.max(0, height - 26))
    self.pageLabel:SetPos(32, math.max(0, height - 26))
    self.pageLabel:SetSize(math.max(1, self.root.width - 64), 24)
    self.pageLabel.content = "Page " .. self.page .. " / " .. self.pages
end

function Preview:Destroy(detached)
    if self.destroyed then return end
    self.destroyed = true
    self.onSelectionChanged = nil
    for _, row in ipairs(self.rows) do
        if detached then Detached.Control(row.selection) else row.selection:Destroy() end
    end
    for _, control in ipairs({self.previousButton, self.nextButton, self.selectAllButton, self.deselectAllButton, self.scroll}) do
        if detached then Detached.Control(control) else control:Destroy() end
    end
    if not detached and self.root then self.root:Destroy() end
    self.root, self.plan, self.source, self.destination, self.rows, self.entries, self.selected = nil, nil, nil, nil, {}, {}, {}
end

return Preview
