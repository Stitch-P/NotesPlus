local Tracking = require("src/tracking/model")
local TextLayout = require("src/ui/shared/text_layout")
local Vars = require("src/tracking/core/vars")
local Timers = require("src/tracking/features/boss_timers")
local Gear = require("src/notes/gear")
local ActionBar = require("src/notes/action_bar")

local Pages = {}
Pages.__index = Pages

local function plain(value)
    return tostring(value or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
        :gsub("<br%s*/?>", "\n"):gsub("<[^>]*>", "")
end

local function quantity(value)
    if type(value) ~= "number" then return "?" end
    if value >= 1000000000 then return math.floor(value / 1000000000) .. "b" end
    if value >= 1000000 then return math.floor(value / 1000000) .. "m" end
    if value >= 1000 then return math.floor(value / 1000) .. "k" end
    return tostring(math.floor(value))
end

local function itemIcon(item)
    local sprite = Tracking.ItemSprite(item)
    if sprite then return {sprite = sprite} end
    return Tracking.ItemObject(item) or Tracking.Icon(item, true)
end

local function sameIcon(left, right)
    return left == right or type(left) == "table" and type(right) == "table"
        and left.sprite == right.sprite and left.size == right.size
end

function Pages.New(notes, options)
    return setmetatable({notes = notes, font = options.font, width = math.max(1, options.width),
        rows = math.max(1, math.floor(options.rows)), index = 1, blocks = {}, pages = {{rows = {}}},
        done = false}, Pages)
end

function Pages:_lines(rows, text, attributes)
    local icon = attributes.icon
    local width = math.max(1, self.width - (icon and 22 or 0))
    local source = tostring(text or ""):gsub("\r\n", "\n"):gsub("\r", "\n"):gsub("<br%s*/?>", "\n")
    local lineIndex = 0
    for paragraph in (source .. "\n"):gmatch("(.-)\n") do
        local color = paragraph:lower():match("<col=(%x+)>")
        for _, line in ipairs(TextLayout.Lines(plain(paragraph), self.font, width)) do
            lineIndex = lineIndex + 1
            local row = {}
            for key, value in pairs(attributes) do row[key] = value end
            row.text, row.line = line, lineIndex
            row.available = row.available == true or color == "00ff00" or color == "55ff55"
            if lineIndex > 1 then row.icon, row.fraction = nil, nil end
            rows[#rows + 1] = row
        end
    end
end

function Pages:_block(index)
    local note, rows = self.notes[index], {}
    local tracking = note.tracking
    local title = note.title ~= "" and note.title or "Untitled"
    local icon = note.skill ~= "" and note.skill or tracking and Tracking.Icon(tracking) or nil
    local function add(text, kind, extra)
        local attributes = {note = note, noteIndex = index, kind = kind, tracking = tracking}
        for key, value in pairs(extra or {}) do attributes[key] = value end
        self:_lines(rows, text, attributes)
    end
    add(title, "title", {icon = icon, color = note.color})
    if note.text ~= "" then add(note.text, "subject") end
    if tracking then
        local progress = Tracking.Read(tracking)
        add(progress.text, "progress", {fraction = progress.fraction, complete = progress.complete})
        for _, need in ipairs(Tracking.Requirements(tracking)) do
            local value = need.text or need.level
            add("Requires: " .. need.name .. (value and (" " .. tostring(value)) or ""), "requirement",
                {icon = need.icon or need.sprite and {sprite = need.sprite}, complete = need.met})
        end
        for _, sub in ipairs(Tracking.SubTasks(tracking) or {}) do
            add(sub.text .. (sub.done and " (Complete)" or ""), "item", {complete = sub.done})
        end
        local derived = not tracking.items and Tracking.DerivedItems(tracking)
        if not progress.unavailable then
            for _, item in ipairs(tracking.items or derived or {}) do
                local status = Tracking.Read(item)
                if not derived or not status.complete then
                    local text, available = Tracking.ItemLabel(item)
                    text = text or item.label or item.skill or item.variable
                    if not derived then
                        local ratio
                        if Timers.isVar(item.variable) then ratio = Timers.format(status.current, item.variable) .. "/" .. Timers.format(item.target, item.variable)
                        elseif status.owned then ratio = "Owned"
                        elseif Tracking.IsSkillXP(item.category, item.group) then ratio = quantity(status.current) .. "/" .. quantity(item.target)
                        else ratio = (status.current ~= nil and Vars.withCommas(status.current) or "?") .. "/" .. Vars.withCommas(item.target) end
                        text = text .. ": " .. ratio
                    end
                    add(text, "item", {tracking = item, icon = itemIcon(item), complete = status.complete,
                        available = type(available) == "string" and available ~= ""})
                end
            end
        end
    end
    if note.gear then
        add("Gear setup", "attachment", {attachment = "gear"})
        for _, slot in ipairs(Gear.Slots) do
            local token = note.gear[slot.key]
            if token then
                local item = Gear.GetItem(token)
                add(slot.label .. (item and (": " .. item.label) or ""), "item", {icon = token, attachment = "gear"})
            end
        end
    end
    if note.actionBar then
        local bar = note.actionBar
        add(bar.name and bar.name ~= "" and bar.name or "Action bar", "attachment", {attachment = "actionBar"})
        for index = 1, ActionBar.SLOT_COUNT do
            local slot = bar.slots[index]
            if slot then
                add(index .. ": " .. ActionBar.Label(slot), "item", {icon = ActionBar.Icon(slot), attachment = "actionBar"})
            end
        end
    end
    return rows
end

function Pages:_append(index, block)
    local page = self.pages[#self.pages]
    if #page.rows > 0 and self.rows - #page.rows < math.min(3, #block) then
        page = {rows = {}}
        self.pages[#self.pages + 1] = page
    end
    for _, row in ipairs(block) do
        if #page.rows >= self.rows then
            page = {rows = {}}
            self.pages[#self.pages + 1] = page
            if row.kind ~= "title" and self.rows >= 3 then
                local title = self.notes[index].title
                local continuation = TextLayout.Lines("Continued: " .. plain(title ~= "" and title or "Untitled"), self.font, self.width)
                page.rows[1] = {text = continuation[1], kind = "title", note = self.notes[index], noteIndex = index,
                    continuation = true}
            end
        end
        page.rows[#page.rows + 1] = row
    end
    if #page.rows < self.rows then page.rows[#page.rows + 1] = {text = "", kind = "gap", noteIndex = index} end
end

function Pages:Step(limit)
    if self.done then return true end
    for _ = 1, limit or 4 do
        if self.index > #self.notes then self.done = true; return true end
        local block = self:_block(self.index)
        self.blocks[self.index] = block
        self:_append(self.index, block)
        self.index = self.index + 1
    end
    self.done = self.index > #self.notes
    return self.done
end

function Pages:PageForNote(index)
    for pageIndex, page in ipairs(self.pages) do
        for _, row in ipairs(page.rows) do if row.noteIndex == index then return pageIndex end end
    end
    return 1
end

function Pages:Refresh(first, last)
    local selected, changed, repack = {}, false, false
    for pageIndex = first, math.min(last or first, #self.pages) do
        for _, row in ipairs(self.pages[pageIndex].rows) do
            if row.noteIndex and row.kind ~= "gap" and self.blocks[row.noteIndex] then selected[row.noteIndex] = true end
        end
    end
    for index in pairs(selected) do
        local before, after = self.blocks[index], self:_block(index)
        if #before ~= #after then self.blocks[index], changed, repack = after, true, true
        else
            for rowIndex, row in ipairs(before) do
                local nextRow = after[rowIndex]
                if row.text ~= nextRow.text or row.fraction ~= nextRow.fraction or row.complete ~= nextRow.complete
                    or row.available ~= nextRow.available or row.color ~= nextRow.color or not sameIcon(row.icon, nextRow.icon) then changed = true end
                for key in pairs(row) do row[key] = nil end
                for key, value in pairs(nextRow) do row[key] = value end
            end
        end
    end
    if repack then
        self.pages = {{rows = {}}}
        for index, block in ipairs(self.blocks) do self:_append(index, block) end
    end
    return changed, repack
end

return Pages
