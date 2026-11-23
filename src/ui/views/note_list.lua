local Base = require("src/ui/views/view")
local Notes = require("src/notes/notes")
local NoteDrag = require("src/ui/notes/note_drag")
local NoteLayout = require("src/ui/notes/note_layout")
local NoteContent = require("src/ui/notes/note_content")
local CardPool = require("src/ui/notes/note_card_pool")
local Components = require("src/ui/shared/components")
local Sprites = require("src/data/sprite_catalog")
local Overlay = require("src/ui/window/overlay")
local WindowStyle = require("src/ui/window/window_style")
local Detached = require("src/ui/shared/detached_ui")
local CategorySidebar = require("src/ui/categories/category_sidebar")
local Tracking = require("src/tracking/model")
local GearTooltip = require("src/ui/attachments/gear_tooltip")
local ActionBarTooltip = require("src/ui/attachments/action_bar_tooltip")
local BossItemStrip = require("src/ui/tracking/boss_item_strip")
local BossList = require("src/ui/tracking/boss_list")
local QuestTooltip = require("src/ui/tracking/quest_tooltip")
local Capacity = require("src/notes/display_capacity")
local CapacityRecovery = require("src/ui/notes/capacity_recovery")

local NoteList = {}
NoteList.__index = NoteList
setmetatable(NoteList, {__index = Base})

local TEXT = 0xE7D7B0FF
local MUTED = 0xB7B1A7FF
local CATEGORY_SIDEBAR_WIDTH = 176

local function copyOrder(entries)
    local copy = {}
    for index, entry in ipairs(entries) do copy[index] = entry end
    return copy
end

local function restoreOrder(entries, previous)
    for index = #entries, #previous + 1, -1 do entries[index] = nil end
    for index, entry in ipairs(previous) do entries[index] = entry end
end

local FADED = 0xFFFFFF66   -- sub-task not done yet
local LIT = 0xFFFFFFFF       -- sub-task done
local REQUIREMENT_UNMET = 0xFF5555FF
local REQUIREMENT_MET = 0x55FF55FF

local function updateTrackingIcon(row, ref)
    local sprite = row.trackingSprite
    if not sprite then return end
    local signature = type(ref) == "table" and ("sprite:" .. tostring(ref.sprite) .. ":" .. tostring(ref.size))
        or tostring(ref)
    if row.iconSignature == signature then return end
    row.iconSignature = signature
    Sprites.Clear(sprite)
    if not ref then return end
    local size = type(ref) == "table" and math.min(row.iconSize, ref.size or row.iconSize) or row.iconSize
    sprite:SetPos(8 + (row.iconSize - size) / 2, 6)
    sprite:SetSize(size, size)
    if type(ref) == "table" then sprite.sprite = ref.sprite
    else
        sprite:SetAssociatedObject(ref)
        sprite.associatedObjectQuantityMode = ui.ObjectQuantityDisplayMode.NEVER
    end
    sprite.hidden = false
end

local noteFont, label = Base.NoteFont, Base.Label

-- Long lists of steps show SUB_PAGE at a time, with the same arrows and "1-5 of 9" line as the other paged lists (the
-- Cats of Menaphos), so a note card never grows past five steps. The page shown is remembered per note while the plugin
-- runs; it starts on the first page with a step to do.
local SUB_PAGE = 5
-- Progress bars start at the card's left edge (the same inset as the item strips), whether or not the note has an icon.
local BAR_LEFT = 8
local PAGER_TEXT = 0xBFBFBFFF
local PAGER_ARROW = 16
local subPages = setmetatable({}, {__mode = "k"})

-- A note beside a taller one has spare height, and its steps use it: row.subPageSize is how many steps a page shows.
local function sliceSubTasks(row, all)
    local size = row.subPageSize or SUB_PAGE
    if not all or #all <= size then
        row.subPageIndex, row.subPageCount, row.subTotal, row.subFirst, row.subLast = nil, nil, nil, nil, nil
        return all
    end
    local pages = math.ceil(#all / size)
    local page = subPages[row.note]
    if page == nil then
        page = 1
        for index, sub in ipairs(all) do
            if sub.done ~= true then page = math.ceil(index / size) break end
        end
    end
    page = math.max(1, math.min(pages, page))
    subPages[row.note] = page
    local first, last = (page - 1) * size + 1, math.min(#all, page * size)
    row.subPageIndex, row.subPageCount, row.subTotal, row.subFirst, row.subLast = page, pages, #all, first, last
    local slice = {}
    for index = first, last do slice[#slice + 1] = all[index] end
    return slice
end

-- Requirements shown after the progress text: "Requires: <icon> 90  <icon> 95  <quest> <tick>".
-- Skill levels are faded until reached; quests get a tick or a cross.
local function reqSprite(parent, size)
    local sprite = Components.New(ui.Sprite, parent)
    sprite.clickthrough = true
    sprite:SetSize(size, size)
    sprite.rgba = 0xFFFFFFFF
    return sprite
end

local function buildRequirements(row, reqs, font, fontName)
    local size = font.baseline
    local built = {size = size, items = {}}
    built.prefix = label(row, "Requires:", 0, 0, 200, size + 2, 0xFFFFFFFF, id.Font[fontName])
    for index, need in ipairs(reqs) do
        local item = {icon = reqSprite(row, size)}
        if need.kind == "skill" or need.kind == "item" then
            local ref = need.icon
            if type(ref) == "table" then item.icon.sprite = ref.sprite
            elseif ref then
                item.icon:SetAssociatedObject(ref)
                item.icon.associatedObjectQuantityMode = ui.ObjectQuantityDisplayMode.NEVER
            end
            local text = need.text or need.kind == "item" and ("x" .. tostring(need.level)) or tostring(need.level)
            item.text = text
            item.textWidth = font:GetStringWidth(text, true)
            item.faded = label(row, text, 0, 0, item.textWidth + 4, size + 2, REQUIREMENT_UNMET, id.Font[fontName])
            item.lit = label(row, text, 0, 0, item.textWidth + 4, size + 2, REQUIREMENT_MET, id.Font[fontName])
        else
            if need.sprite then item.icon.sprite = need.sprite end
            item.mark = reqSprite(row, size)
        end
        built.items[index] = item
    end
    return built
end

local TICK, CROSS
local function updateRequirements(row, reqs)
    local built = row.reqs
    local plan = row.contentPlan and row.contentPlan.requirements
    if not built or not plan then return end
    TICK = TICK or Sprites.SpriteID("AIF_TICK_CROSS_ICON_0")
    CROSS = CROSS or Sprites.SpriteID("AIF_TICK_CROSS_ICON_1")
    local prefix = plan.prefix
    built.prefix.hidden = prefix.hidden
    built.prefix.content = prefix.text
    built.prefix:SetPos(prefix.x, prefix.y)
    built.prefix:SetSize(prefix.width, prefix.height)
    row.reqHits = {}
    for index, need in ipairs(reqs) do
        local item = built.items[index]
        local slot = plan.items[index]
        if item and slot then
            item.icon:SetPos(slot.x, slot.y + 1)
            local tip
            if need.kind == "skill" or need.kind == "item" then
                for _, component in ipairs({item.faded, item.lit}) do
                    component:SetPos(slot.textX, slot.textY)
                    component:SetSize(slot.textWidth, slot.textHeight)
                    component.content = slot.text
                end
                item.faded.hidden, item.lit.hidden = need.met, not need.met
                if need.kind == "item" then
                    tip = (need.level > 1 and (need.level .. " x ") or "") .. need.name
                else
                    tip = need.name .. " " .. need.level .. (need.met and " (met)"
                        or need.have and (" (you have " .. need.have .. ")") or "")
                end
            else
                item.mark:SetPos(slot.markX, slot.markY + 1)
                local mark = need.met and TICK or CROSS
                if mark then item.mark.sprite = mark end
                item.mark.rgba = need.met and REQUIREMENT_MET or REQUIREMENT_UNMET
                tip = need.name .. (need.met and (need.metText or " (quest complete)") or (need.unmetText or " (quest not complete)"))
            end
            if need.tip then tip = need.tip end
            row.reqHits[#row.reqHits + 1] = {x1 = slot.x, x2 = slot.x + slot.width,
                y1 = slot.y, y2 = slot.y + slot.height + 2, text = tip}
        end
    end
end

-- The badge at the end of a Slayer task note's title: an ushabti with a tick or a cross for whether the task's monster
-- is in the Slayer Codex (hidden while there is no task, or it isn't one codex monster).
local function updateBadge(row)
    local badge = row.badge
    if not badge then return end
    local ok, state = pcall(Tracking.TitleBadge, row.note.tracking)
    state = ok and state or nil
    TICK = TICK or Sprites.SpriteID("AIF_TICK_CROSS_ICON_0")
    CROSS = CROSS or Sprites.SpriteID("AIF_TICK_CROSS_ICON_1")
    local shown = state ~= nil and badge.x ~= nil
    badge.icon.hidden, badge.mark.hidden = not shown, not shown
    row.badgeHit = nil
    if not shown then return end
    if badge.obj ~= state.obj then
        badge.obj = state.obj
        badge.icon:SetAssociatedObject(state.obj)
        badge.icon.associatedObjectQuantityMode = ui.ObjectQuantityDisplayMode.NEVER
    end
    local mark = state.met and TICK or CROSS
    if mark then badge.mark.sprite = mark end
    badge.mark.rgba = state.met and REQUIREMENT_MET or REQUIREMENT_UNMET
    badge.icon:SetPos(badge.x, badge.y)
    badge.mark:SetPos(badge.x + badge.size + 2, badge.y)
    row.badgeHit = {x1 = badge.x, x2 = badge.x + badge.size * 2 + 2, y1 = badge.y, y2 = badge.y + badge.size, text = state.tip}
end

-- Places the badge just after the first line of the title (kept inside the text column).
local function placeBadge(row, plan, font)
    local badge = row.badge
    if not badge then return end
    local first = plan.lines and plan.lines[1] or ""
    local width = badge.size * 2 + 2
    local x = row.textX + font:GetStringWidth(first, true) + 6
    badge.x = math.max(row.textX, math.min(x, row.textX + plan.textWidth - width))
    badge.y = 6 + math.floor((font.baseline + 2 - badge.size) / 2)
    updateBadge(row)
end

local function subjectText(note, expanded)
    local text = note.title ~= "" and note.title or "Untitled"
    if expanded then
        text = note.title ~= "" and (note.title .. (note.text ~= "" and "\n" .. note.text or "")) or note.text
    end
    if text == "" and note.gear then text = "Gear setup" end
    if text == "" and note.actionBar then text = "Action bar" end
    return text
end

local function hoverText(note, description)
    local text = note.text or ""
    if description and description ~= "" then
        text = text ~= "" and (text .. "\n\n" .. description) or description
    end
    return (text:gsub("\r\n", "<br>"):gsub("[\r\n]", "<br>"))
end

local function hoverPreview(note, preview)
    if not preview or note.text == "" then return preview end
    local combined = {}
    for key, value in pairs(preview) do combined[key] = value end
    combined.body = hoverText(note, preview.body)
    combined.key = tostring(preview.key or "") .. ":" .. note.text
    return combined
end

-- Compact notes: a title and one line of progress. The one line is the first line of the full progress text, with how many
-- steps are done when that line doesn't already count them, the next reset, and (!) when a requirement isn't met. The
-- tooltip carries everything else. Returns whether the one-line text changed.
local MAX_TIP_STEPS = 24
local function refreshCompact(row)
    if not row.compact or not row.progress then return false end
    local full = tostring(row.progress.text or ""):gsub("<br>", "\n")
    local lines = {}
    for line in (full .. "\n"):gmatch("(.-)\n") do if line ~= "" then lines[#lines + 1] = line end end
    local summary = lines[1] or ""
    local steps = row.allSubTasks or {}
    local done = 0
    for _, sub in ipairs(steps) do if sub.done == true then done = done + 1 end end
    if #steps > 0 and not summary:find("%%") then summary = summary .. " - " .. done .. " of " .. #steps .. " done" end
    for _, line in ipairs(lines) do
        local reset = line:match("[Nn]ext reset:%s*(.-)%s+at%s")
        if reset then summary = summary .. " - resets " .. reset break end
    end
    local unmet = false
    local tipLines = {}
    local reqStart
    if row.note.text and row.note.text ~= "" then tipLines[#tipLines + 1] = (row.note.text:gsub("\r\n", "<br>"):gsub("[\r\n]", "<br>")) end
    for _, line in ipairs(lines) do tipLines[#tipLines + 1] = line end
    for _, need in ipairs(row.fullRequirements or {}) do
        if need.met ~= true then unmet = true end
    end
    if #(row.fullRequirements or {}) > 0 then
        tipLines[#tipLines + 1] = "Requires:"
        reqStart = #tipLines
        for _, need in ipairs(row.fullRequirements) do
            local text = need.tip
            if not text then
                if need.kind == "skill" or need.kind == "item" then
                    text = need.kind == "item" and ((need.level > 1 and (need.level .. " x ") or "") .. (need.name or ""))
                        or ((need.name or "") .. " " .. tostring(need.level) .. (need.met and " (met)" or need.have and (" (you have " .. need.have .. ")") or ""))
                else
                    text = (need.name or "") .. (need.met and (need.metText or " (quest complete)") or (need.unmetText or " (quest not complete)"))
                end
            end
            tipLines[#tipLines + 1] = (need.met and "<col=55FF55>" or "<col=FF6666>") .. "- " .. text .. "</col>"
        end
    end
    row.compactReq = nil
    if reqStart then
        row.compactReq = "<col=FFD27F>Requires</col><br>" .. table.concat(tipLines, "<br>", reqStart + 1, #tipLines)
    end
    if #steps > 0 then
        tipLines[#tipLines + 1] = "Steps (" .. done .. " of " .. #steps .. " done):"
        for index, sub in ipairs(steps) do
            if index > MAX_TIP_STEPS then tipLines[#tipLines + 1] = "... and " .. (#steps - MAX_TIP_STEPS) .. " more" break end
            local text = tostring(sub.text or "")
            tipLines[#tipLines + 1] = sub.done == true and ("<col=55FF55>- " .. text .. "</col>") or ("- " .. text)
        end
    end
    -- The entries the note would list or show as tiles (the cats, the chests, the boss items), read at most every two seconds.
    local now = type(os) == "table" and os.clock and os.clock() or 0
    if row.compactEntries == nil or now - (row.compactEntriesAt or 0) >= 2 then
        local entries = {}
        local tracking = row.note.tracking
        local okItems, derived = pcall(Tracking.DerivedItems, tracking)
        if okItems and derived then
            local okEntries, listed = pcall(BossList.Entries, derived)
            if okEntries then entries = listed end
        elseif tracking and tracking.items and #steps == 0 then
            local okEntries, listed = pcall(BossList.Entries, tracking.items)
            if okEntries then entries = listed end
        end
        row.compactEntries, row.compactEntriesAt = entries, now
    end
    local entries = row.compactEntries
    if #entries > 0 then
        local doneEntries = 0
        for _, entry in ipairs(entries) do if entry.done then doneEntries = doneEntries + 1 end end
        tipLines[#tipLines + 1] = "Entries (" .. doneEntries .. " of " .. #entries .. " done):"
        for index, entry in ipairs(entries) do
            if index > MAX_TIP_STEPS then tipLines[#tipLines + 1] = "... and " .. (#entries - MAX_TIP_STEPS) .. " more" break end
            local text = tostring(entry.text or ""):gsub("<[^>]*>", "")
            tipLines[#tipLines + 1] = entry.done and ("<col=55FF55>- " .. text .. "</col>") or ("- " .. text)
        end
    end
    local description = row.note.tracking and Tracking.Description(row.note.tracking)
    if description and description ~= "" then tipLines[#tipLines + 1] = (tostring(description):gsub("\r\n", "<br>"):gsub("[\r\n]", "<br>")) end
    row.compactTip = table.concat(tipLines, "<br>")
    if unmet then summary = summary .. " (!)" end
    local changed = row.compactText ~= summary
    row.compactText = summary
    return changed
end

local function updateSubTasks(row, subTasks, font, fontName)
    row.subTasks = row.expanded and sliceSubTasks(row, subTasks) or nil
    if not row.expanded then row.subPageCount = nil end
    if row.subTasks then
        row.subFaded, row.subLit = row.subFaded or {}, row.subLit or {}
        for index, sub in ipairs(row.subTasks) do
            if not row.subFaded[index] then
                row.subFaded[index] = label(row.component, sub.text, 0, 0,
                    row.textWidth, font.baseline + 2, FADED, id.Font[fontName])
                row.subLit[index] = label(row.component, sub.text, 0, 0,
                    row.textWidth, font.baseline + 2, LIT, id.Font[fontName])
            end
        end
    end
    for index, faded in ipairs(row.subFaded or {}) do
        local sub = row.subTasks and row.subTasks[index]
        local done = sub and sub.done == true
        faded.hidden = not sub or done
        row.subLit[index].hidden = not sub or not done
    end
end

function NoteList.new(parent, options, callbacks)
    local self = setmetatable({}, NoteList)
    local window, overlays = options.window.chrome, {}
    for component in pairs(window.overlays) do overlays[component] = true end
    local ok, message = pcall(function()
        Base.Init(self, parent, options, callbacks)
        self.query, self.scroll = self.state.query or "", self.state.scroll or 0
        self.categoryID, self.categorySidebarScroll = self.state.categoryID, self.state.categorySidebarScroll
        self:RenderList()
    end)
    if not ok then
        for component in pairs(window.overlays) do
            if not overlays[component] then window:_UnregisterOverlay(component) end
        end
        local cleaned = pcall(self.Destroy, self)
        if not cleaned then
            if self.listScroll then self.listScroll.onLayout = nil end
            if self.surface then pcall(function() prettyui.Tooltip.unregisterContext(self.surface); self.surface:Destroy() end) end
            if self.tooltipOwner then pcall(function() self.tooltipOwner:Destroy() end) end
        end
        error(message, 0)
    end
    return self
end

function NoteList:Snapshot()
    local state = self.state
    state.query, state.categoryID = self.query, self.categoryID
    state.scroll = self.listScroll and self.listScroll.scrollY or self.scroll
    state.categorySidebarScroll = self.categorySidebar and self.categorySidebar.scroll.scrollY
        or self.categorySidebarScroll
    return state
end

function NoteList:UpdateCount(capacityCost)
    if not self.count then return end
    self.count.content = self.state.saveError and "Save failed. Try again."
        or #self.visibleNotes .. " / " .. #self.data.notes .. " notes"
    self.count.rgba = self.state.saveError and 0xFFAA77FF or MUTED
    self.capacityCost = capacityCost or Capacity.Estimate(self.data)
    if self.capacity then
        local percent = self.capacityCost / Capacity.LIMIT * 100
        self.capacity.content = string.format("Display capacity: %.1f%%", percent)
        self.capacity.rgba = self.capacityCost >= Capacity.BUDGET and 0xFF5555FF
            or percent >= 85 and 0xFFAA55FF or percent >= 70 and 0xFFE14AFF or 0x55FF55FF
        local previousFooter = self.countFooter
        self:LayoutCount()
        if self.rowsReady and previousFooter ~= self.countFooter then self:LayoutRows(nil, true) end
    end
    if self.addNoteButton then self.addNoteButton:SetDisabled(self.capacityCost >= Capacity.BUDGET) end
end

function NoteList:LayoutCount()
    if not self.count or not self.capacity then return end
    local font = config.Font.MUSEO_SANS_13PT_REGULAR
    local countWidth = font:GetStringWidth(self.count.content, true) + 2
    local capacityWidth = font:GetStringWidth(self.capacity.content, true) + 2
    self.countStacked = countWidth + capacityWidth + 16 > self.listWidth
    self.countFooter = self.countStacked and 92 or 70
    self.count:SetPos(self.listX, self.height - (self.countStacked and 85 or 63))
    self.count:SetSize(math.min(self.listWidth, countWidth), 22)
    self.capacity:SetPos(self.listX + (self.countStacked and 0 or countWidth + 16), self.height - 63)
    self.capacity:SetSize(math.min(self.listWidth, capacityWidth), 22)
end

function NoteList:Save(rebuilding)
    local saved, message = Base.Save(self)
    if saved then self.state.saveError = nil
    else self.state.saveError = message or "The notes could not be saved." end
    if not saved or not rebuilding then self:UpdateCount() end
    return saved, message
end

function NoteList:RenderList()
    local width, height = self.width, self.height
    local wide = width >= 480
    self.listX, self.listY = wide and (CATEGORY_SIDEBAR_WIDTH + 24) or 8, wide and 44 or 82
    self.listWidth = width - self.listX + 8
    local add = self:Button("+", width - 20, 6, 28, function() self:Edit(nil) end)
    self.addNoteButton = add
    self.journalButton = self:Button(-1, width - 54, 6, 28,
        function() self:Navigate("journal") end)
    self.journalButton.content:SetAssociatedObject(id.Obj.MENAPHOS_COLLECTIONS_JOURNAL)
    self.journalButton.content.associatedObjectQuantityMode = ui.ObjectQuantityDisplayMode.NEVER
    self.journalButton.content:SetSize(24, 24)
    self.journalButton.content:SetPos(2, 2)
    self.journalButton:SetTooltip("Journal view")
    WindowStyle.ApplyTooltip(self.journalButton.tooltip)
    local search = self:Field(self.query, self.listX, 6, self.listWidth - 72, 28, 120, function(_, value)
        self.query = value
        self.scroll = 0
        self:RenderRows()
    end)
    search.root.emptyText = "Search notes"
    if wide then
        self.categorySidebar = CategorySidebar.new(self.surface, self.data, self.categoryID, {
            select = function(categoryID) self:SelectCategory(categoryID) end,
            edit = function(categoryID) self:EditCategory(categoryID) end,
            delete = function(categoryID) self:DeleteCategory(categoryID) end,
            new = function() self:EditCategory(nil) end,
            reset = function() self:ResetCategories() end,
            reorder = function(categoryID, destination) return self:MoveCategory(categoryID, destination) end
        }, {x = 8, y = 6, width = CATEGORY_SIDEBAR_WIDTH, height = math.max(1, height - 12),
            scrollY = self.categorySidebarScroll, inputOwner = self.window.chrome})
    else
        local entries = self:CategoryEntries(true)
        self.categoryFilter = self:Track(prettyui.ComboBox.new(self.surface, Components.Options({
            x = 8, y = 44, width = width - 96, height = 28, entries = entries,
            selectedID = self.categoryID == nil and -1 or self.categoryID,
            font = id.Font.MUSEO_SANS_13PT_REGULAR,
            onChange = function(field, categoryID)
                if self.destroyed or self.clearing or self.view ~= "list" or self.categoryFilter ~= field then return end
                if categoryID == -1 then self:SelectCategory(nil) else self:SelectCategory(categoryID) end
            end
        })))
        self.newCategoryButton = self:Button("+", width - 84, 44, 28, function() self:EditCategory(nil) end)
        self.newCategoryButton:SetTooltip("New category")
        WindowStyle.ApplyTooltip(self.newCategoryButton.tooltip)
        self.resetCategoriesButton = self:Button(Sprites.SpriteID("RS3_ICON_LOBBY_REFRESH_0") or "R",
            width - 52, 44, 28, function() self:ResetCategories() end)
        self.resetCategoriesButton:SetTooltip("Restore missing default categories and Scheduled notes. Keeps existing notes and settings.")
        WindowStyle.ApplyTooltip(self.resetCategoriesButton.tooltip)
        self.editCategoryButton = self:Button(Sprites.SpriteID("RS3_MENU_ICON_NOTES_NORMAL") or "...", width - 20, 44, 28,
            function() self:EditCategory(self.categoryID) end)
        self.editCategoryButton:SetTooltip("Edit or delete category")
        WindowStyle.ApplyTooltip(self.editCategoryButton.tooltip)
        local noEdit = self.categoryID == nil or self.categoryID == 0
        self.editCategoryButton:SetDisabled(noEdit)
        pcall(function() self.editCategoryButton.root.alpha = noEdit and 0.35 or 1 end)
    end
    local buttonWidth = math.floor((self.listWidth - 8) / 3)
    self.footerButtons = {}
    self.footerButtons[1] = self:Button("Share", self.listX, height - 34, buttonWidth, function()
        self:Navigate("shareSelect")
    end)
    self.footerButtons[2] = self:Button("Copy", self.listX + 4 + buttonWidth, height - 34, buttonWidth, function()
        self:Navigate("copy")
    end)
    self.footerButtons[3] = self:Button("Import", self.listX + 8 + buttonWidth * 2, height - 34, buttonWidth, function()
        self:Navigate("import")
    end)
    self.count = label(self.surface, "", self.listX, height - 63, self.listWidth, 22, MUTED)
    self.capacity = label(self.surface, "", self.listX, height - 63, self.listWidth, 22, MUTED)
    self.capacityTooltip = prettyui.Tooltip.attach(self.capacity, self.surface,
        Components.Options({text = "The game has a fixed UI limit. Collections and attachments use more of it than plain notes. "
            .. "We stop at 95% to leave some room and avoid potential errors."}))
    WindowStyle.ApplyTooltip(self.capacityTooltip)
    self:RenderRows()
    self.layout = function()
        if wide ~= (self.width >= 480) then
            self.scroll = self.listScroll.scrollY
            self:Render()
            return
        end
        self.listWidth = self.width - self.listX + 8
        add.root:SetPos(self.width - 20, 6)
        self.journalButton.root:SetPos(self.width - 54, 6)
        search.root:SetSize(self.listWidth - 72, 28)
        if self.categorySidebar then
            self.categorySidebar:Resize(CATEGORY_SIDEBAR_WIDTH, math.max(1, self.height - 12))
        else
            self.categoryFilter.root:SetSize(self.width - 96, 28)
            self.newCategoryButton.root:SetPos(self.width - 84, 44)
            self.resetCategoriesButton.root:SetPos(self.width - 52, 44)
            self.editCategoryButton.root:SetPos(self.width - 20, 44)
        end
        local buttonWidth = math.floor((self.listWidth - 8) / 3)
        for index, button in ipairs(self.footerButtons) do
            button.root:SetPos(self.listX + (index - 1) * (buttonWidth + 4), self.height - 34)
            button.root:SetSize(buttonWidth, 28)
        end
        self:LayoutCount()
        self:LayoutRows(nil, true)
    end
end

function NoteList:SelectCategory(categoryID)
    if categoryID ~= nil and categoryID ~= 0 and not Notes.FindCategory(self.data, categoryID) then return end
    self.categoryID = categoryID
    self.scroll = 0
    if self.listScroll then self.listScroll:SetScrollPosition(0) end
    if self.view == "list" and self.categoryFilter then
        self.categoryFilter:Select(categoryID == nil and -1 or categoryID, false)
        local noEdit = categoryID == nil or categoryID == 0
        self.editCategoryButton:SetDisabled(noEdit)
        pcall(function() self.editCategoryButton.root.alpha = noEdit and 0.35 or 1 end)
        self:RenderRows()
    else
        self:Render()
    end
end

-- "Delete category" from the right-click menu: removes it straight away; its notes move to Uncategorized (nothing else is
-- lost). Put back as it was if the notes can't be saved.
function NoteList:DeleteCategory(categoryID)
    if self.destroyed or self.clearing or self.view ~= "list" then return false end
    local category = Notes.FindCategory(self.data, categoryID)
    if not category then return false end
    local position, moved = nil, {}
    for index, existing in ipairs(self.data.categories) do
        if existing == category then position = index break end
    end
    for _, note in ipairs(self.data.notes) do
        if note.categoryID == categoryID then moved[#moved + 1] = note end
    end
    if not Notes.DeleteCategory(self.data, categoryID) then return false end
    if self.listScroll then self.scroll = self.listScroll.scrollY end
    if not self:Save(true) then
        table.insert(self.data.categories, position, category)
        for _, note in ipairs(moved) do note.categoryID = categoryID end
        self:UpdateCount()
        return false
    end
    -- Viewing the deleted category: show Uncategorized, where its notes went.
    if self.categoryID == categoryID then
        self.categoryID, self.scroll = 0, 0
        if self.state then self.state.categoryID, self.state.scroll = 0, 0 end
    end
    self:Render()
    return true
end

function NoteList:MoveCategory(categoryID, destination)
    local previous = copyOrder(self.data.categories)
    if self.destroyed or self.view ~= "list" or not Notes.ReorderCategory(self.data, categoryID, destination) then
        return false
    end
    if self.listScroll then self.scroll = self.listScroll.scrollY end
    if not self:Save(true) then restoreOrder(self.data.categories, previous); return false end
    self:Render()
    return true
end

function NoteList:ResetCategories()
    if self.destroyed or self.view ~= "list" then return end
    local previous, nextID = copyOrder(self.data.categories), self.data.nextCategoryID
    local notes, categoryIDs = copyOrder(self.data.notes), {}
    for index, note in ipairs(notes) do categoryIDs[index] = note.categoryID end
    local defaultsAdded, eventsAdded, rewardsAdded, penguinsAdded, tasksAdded, ordered = self.data.scheduledDefaultsAdded,
        self.data.scheduledEventsAdded, self.data.scheduledRewardsAdded, self.data.scheduledPenguinsAdded,
        self.data.scheduledTasksAdded, self.data.scheduledCategoryOrdered
    local ok, message = Notes.ResetCategories(self.data, true)
    if not ok then
        if self.count then self.count.content = message end
        return
    end
    if self.listScroll then self.scroll = self.listScroll.scrollY end
    if not self:Save(true) then
        restoreOrder(self.data.categories, previous)
        restoreOrder(self.data.notes, notes)
        for index, note in ipairs(notes) do note.categoryID = categoryIDs[index] end
        self.data.nextCategoryID = nextID
        self.data.scheduledDefaultsAdded, self.data.scheduledEventsAdded, self.data.scheduledRewardsAdded,
            self.data.scheduledPenguinsAdded, self.data.scheduledTasksAdded, self.data.scheduledCategoryOrdered =
            defaultsAdded, eventsAdded, rewardsAdded, penguinsAdded, tasksAdded, ordered
        return
    end
    self:Render()
end

function NoteList:DestroyItemStrips(detached)
    if self.cardPool then self.cardPool:Clear(detached) end
end

function NoteList:SetSubjectExpanded(row, expanded)
    if row.compact or row.expanded == expanded then return end
    row.expanded, row.text = expanded, subjectText(row.note, expanded)
    row.subTasks = expanded and sliceSubTasks(row, row.allSubTasks) or nil
    if not expanded then row.subPageCount = nil end
    row.layoutWidth = nil
    return true
end

function NoteList:UpdateSubjects()
    local changed = false
    for _, row in ipairs(self.noteRows or {}) do
        local expanded = row.note.subjectExpanded
        if expanded == nil then
            expanded = row.hasSubTasks and Tracking.TasksOnly(row.note.tracking) or not row.hasSubTasks and self.settings.showSubject
        end
        if self:SetSubjectExpanded(row, expanded) then changed = true end
    end
    return changed
end

function NoteList:ToggleSubject(row)
    if self.destroyed or self.clearing or self.noteRows[row.position] ~= row then return end
    local scroll = self.listScroll.scrollY
    local previous = row.note.subjectExpanded
    row.note.subjectExpanded = not row.expanded
    if not self:Save() then row.note.subjectExpanded = previous; return end
    if self.capacityCost > Capacity.BUDGET then
        self.scroll = scroll
        self:RenderRows()
        return
    end
    self:SetSubjectExpanded(row, not row.expanded)
    self.pendingDeleteNote = nil
    self:LayoutRows(scroll, true)
end

function NoteList:MoveNote(source, destination)
    if self.destroyed or self.clearing or self.alphabetical then return false end
    local previous = copyOrder(self.data.notes)
    if not Notes.Reorder(self.data, self.visibleNotes, source, destination) then return false end
    if not self:Save(true) then restoreOrder(self.data.notes, previous); return false end
    self:RenderRows()
    return true
end

function NoteList:LayoutNoteHits()
    if not self.rowsReady or not self.noteHit or not self.listScroll or self.layingOutRows then return end
    self.noteHit:SetSize(self.listScroll.contentWidth, self.listScroll.root.height)
    if not self.compactRecovery and self.cardPool then self.cardPool:Update() end
end

local function requirementMetrics(requirements, font)
    local result = {size = font.baseline, items = {}}
    for index, need in ipairs(requirements or {}) do
        local item = {}
        if need.kind == "skill" or need.kind == "item" then
            item.text = need.text or need.kind == "item" and ("x" .. tostring(need.level)) or tostring(need.level)
            item.textWidth = font:GetStringWidth(item.text, true)
        end
        result.items[index] = item
    end
    return result
end

local function requirementsSignature(requirements)
    local parts = {}
    for _, need in ipairs(requirements or {}) do
        local icon = type(need.icon) == "table" and (tostring(need.icon.sprite) .. ":" .. tostring(need.icon.size))
            or tostring(need.icon or need.sprite)
        parts[#parts + 1] = tostring(need.kind) .. ":" .. tostring(need.name) .. ":" .. tostring(need.level)
            .. ":" .. tostring(need.text) .. ":" .. icon
    end
    return table.concat(parts, "|")
end

local function stripDescriptor(note, progress, settings)
    if not note.tracking then return nil end
    local items = Tracking.DerivedItems(note.tracking)
    local kind = items and "list" or note.tracking.items and not Tracking.TasksOnly(note.tracking) and "strip" or nil
    if not kind then return nil end
    items = items or note.tracking.items
    local descriptor = {kind = kind, items = items, tracking = note.tracking, progress = progress, settings = settings}
    local keys = {kind}
    for _, item in ipairs(items) do keys[#keys + 1] = tostring(item.key or item.variable or item.skill) end
    descriptor.signature = table.concat(keys, "|")
    function descriptor:HeightFor(width)
        self.height = self.kind == "list" and BossList.Measure(self.items, self.tracking, self.progress, width, self.settings)
            or BossItemStrip.Measure(self.items)
        return self.height
    end
    descriptor.height = descriptor:HeightFor(1)
    return descriptor
end

local function actionPlan(self, row, footer)
    local plan = row.contentPlan
    row.actions, row.actionBounds, row.subPagerBounds = {}, {}, nil
    row.actionY = footer and row.height - 26 or 6
    if plan.itemStrip then row.actionBounds[#row.actionBounds + 1] = plan.itemStrip end
    if plan.subPager then
        local pager = plan.subPager
        row.subPagerBounds = {previous = {x = pager.x, y = pager.y, width = PAGER_ARROW, height = 24},
            next = {x = pager.x + pager.width - PAGER_ARROW, y = pager.y, width = PAGER_ARROW, height = 24}}
        row.actionBounds[#row.actionBounds + 1] = row.subPagerBounds.previous
        row.actionBounds[#row.actionBounds + 1] = row.subPagerBounds.next
    end
    local names = {}
    if row.note.gear then names[#names + 1] = "gearButton" end
    if row.note.actionBar then names[#names + 1] = "actionBarButton" end
    if row.showSubject then names[#names + 1] = "subjectButton" end
    names[#names + 1] = "deleteButton"
    local function bounds(name, x, y)
        local size = name == "subjectButton" and 16 or 20
        local result = {x = x, y = y, width = size, height = size}
        row.actions[name] = result
        row.actionBounds[#row.actionBounds + 1] = result
    end
    if footer then
        local x = row.width - 8 - #names * 24
        for index, name in ipairs(names) do bounds(name, x + (index - 1) * 24, row.actionY + (name == "subjectButton" and 2 or 0)) end
        row.bodyWidth, row.bodyHeight = row.width, row.actionY
    else
        local width = row.width - self.rowActionsWidth
        if row.note.gear then bounds("gearButton", width + 16, 6) end
        if row.note.actionBar then bounds("actionBarButton", width + 16 + self.rowGearOffset, 6) end
        if row.showSubject then bounds("subjectButton", width + 16 + self.rowActionOffset, 8) end
        bounds("deleteButton", width + 38 + self.rowActionOffset, 6)
        row.bodyWidth, row.bodyHeight = width + 12, row.height
    end
end

-- Change how many steps a note shows per page, keeping the first step on screen.
function NoteList:SetSubPageSize(row, size)
    local old = row.subPageSize or SUB_PAGE
    if (size or SUB_PAGE) == old then return false end
    local page = subPages[row.note]
    if page then subPages[row.note] = math.ceil(((page - 1) * old + 1) / (size or SUB_PAGE)) end
    row.subPageSize = size
    row.allSubTasks = row.allSubTasks or Tracking.SubTasks(row.note.tracking)
    row.subTasks = row.expanded and sliceSubTasks(row, row.allSubTasks) or nil
    return true
end

local function replanRow(row, metrics, font, spriteSize, footer, showProgressBars)
    local planning = setmetatable({reqs = row.requirementMetrics, itemStrip = row.stripPlan or false}, {__index = row})
    row.contentPlan = NoteContent.Plan(planning, font, row.layoutWidth, spriteSize, footer, metrics.cardWidth, showProgressBars)
end

-- Spare height in a card (the note beside it is taller) goes to more steps per page instead of empty space. Returns whether
-- the page size changed.
function NoteList:FillSubTasks(row, metrics, font, spriteSize, footer)
    if row.slot or not row.expanded or not row.baseHeight or not row.contentPlan then return false end
    local total = row.allSubTasks and #row.allSubTasks or 0
    if total <= SUB_PAGE then return false end
    local slots = row.contentPlan.subtasks or {}
    local columns = (#slots > 1 and slots[2].y == slots[1].y) and 2 or 1
    local lines = math.floor(math.max(0, row.height - row.baseHeight) / (font.baseline + 2))
    local size = lines > 0 and math.min(total, SUB_PAGE + lines * columns) or nil
    if not self:SetSubPageSize(row, size) then return false end
    replanRow(row, metrics, font, spriteSize, footer, self.settings.showProgressBars)
    if row.contentPlan.height > row.height then
        self:SetSubPageSize(row, nil)
        replanRow(row, metrics, font, spriteSize, footer, self.settings.showProgressBars)
        return false
    end
    return true
end

function NoteList:LayoutRows(scroll, keepTracking)
    if self.layingOutRows then return end
    if self.compactRecovery then return CapacityRecovery.Layout(self, scroll) end
    self.layingOutRows = true
    if self.gearTooltip then self.gearTooltip:Hide() end
    if self.actionBarTooltip then self.actionBarTooltip:Hide() end
    if self.rowTooltip then self.rowTooltip:Hide() end
    scroll = scroll or self.listScroll.scrollY
    local viewportHeight = math.max(1, self.height - self.listY - (self.countFooter or 70))
    if self.listScroll.width ~= self.listWidth or self.listScroll.height ~= viewportHeight then self.listScroll:SetSize(self.listWidth, viewportHeight) end
    local fontName, fontSize = noteFont(self.settings)
    local font = config.Font[fontName]
    local spriteSize = math.floor(24 * fontSize / 14 + 0.5)
    if not keepTracking then self:RefreshTracking(true) end
    for pass = 1, 3 do
        local contentWidth = self.listScroll.contentWidth
        local metrics = NoteLayout.Measure(contentWidth, fontSize)
        if self.noteDrag and (self.noteColumns ~= metrics.columns or self.noteCardWidth ~= metrics.cardWidth) then
            local drag = self.noteDrag; self.noteDrag = nil; drag:Destroy()
        end
        self.noteColumns, self.noteCardWidth = metrics.columns, metrics.cardWidth
        local footer = metrics.columns > 1 or metrics.cardWidth < 340 * fontSize / 14
        for _, row in ipairs(self.noteRows) do
            row.textX = row.hasIcon and spriteSize + 14 or 8
            local textWidth = math.max(1, metrics.cardWidth - row.textX - (footer and 8 or self.rowActionsWidth - 8))
            local stripHeight = row.stripPlan and row.stripPlan:HeightFor(math.max(1, metrics.cardWidth - 16))
            if row.layoutWidth ~= textWidth or row.layoutFooter ~= footer or row.layoutFont ~= fontName
                or row.layoutProgress ~= row.progressText or row.layoutStripHeight ~= stripHeight
                or row.layoutProgressBars ~= self.settings.showProgressBars then
                row.requirementMetrics = requirementMetrics(row.requirements, font)
                if row.subPageSize then self:SetSubPageSize(row, nil) end
                local planning = setmetatable({reqs = row.requirementMetrics, itemStrip = row.stripPlan or false}, {__index = row})
                row.contentPlan = NoteContent.Plan(planning, font, textWidth, spriteSize, footer, metrics.cardWidth, self.settings.showProgressBars)
                row.layoutWidth, row.layoutFooter, row.layoutFont = textWidth, footer, fontName
                row.layoutProgress, row.layoutStripHeight = row.progressText, stripHeight
                row.layoutProgressBars = self.settings.showProgressBars
            end
            row.shape = fontName .. ":" .. row.requirementSignature .. ":" .. tostring(row.hasBadge)
                .. ":" .. (row.stripPlan and row.stripPlan.signature or "") .. ":" .. tostring(row.contentPlan.subPager ~= nil)
                .. ":" .. tostring(row.showSubject)
            if not row.subPageSize then row.baseHeight = row.contentPlan.height end
            row.naturalHeight = row.baseHeight or row.contentPlan.height
            if not row.slot then row.reqs, row.itemStrip = row.requirementMetrics, row.stripPlan end
        end
        local contentHeight = NoteLayout.Arrange(self.noteRows, metrics)
        for _, row in ipairs(self.noteRows) do
            self:FillSubTasks(row, metrics, font, spriteSize, footer)
            if row.subPageSize then row.shape = row.shape .. ":" .. tostring(row.subPageSize) end
        end
        for _, row in ipairs(self.noteRows) do actionPlan(self, row, footer) end
        if self.emptyList then self.emptyList:SetSize(math.max(1, contentWidth - 16), 48) end
        local height = #self.noteRows == 0 and 48 or contentHeight
        if self.listScroll.requestedContentHeight ~= height then self.listScroll:SetContentHeight(height) end
        if contentWidth == self.listScroll.contentWidth then break end
    end
    if self.listScroll.scrollY ~= scroll then self.listScroll:SetScrollPosition(scroll) end
    self.scroll = self.listScroll.scrollY
    self:LayoutCount()
    self.layingOutRows, self.rowsReady = false, true
    self:LayoutNoteHits()
end

function NoteList:DeleteRow(row)
    if self.destroyed or self.clearing or self.noteRows[row.position] ~= row then return end
    local note = row.note
    if self.pendingDeleteNote ~= note then self.pendingDeleteNote = note; return end
    for index, current in ipairs(self.data.notes) do
        if current == note then
            self.scroll = self.listScroll.scrollY
            Notes.Delete(self.data, index)
            if not self:Save(true) then table.insert(self.data.notes, index, note); return end
            self.pendingDeleteNote = nil
            self:Render()
            return
        end
    end
end

function NoteList:OpenRowAttachment(row, kind)
    self.scroll = self.listScroll.scrollY
    self:Navigate(kind == "gear" and "gearPreview" or "actionBarPreview", {note = row.note})
end

function NoteList:ShowRowAttachment(row, kind)
    local control = kind == "gear" and row.gearButton or row.actionBarButton
    local tooltip = kind == "gear" and self.gearTooltip or self.actionBarTooltip
    if not control or not tooltip then return end
    local top = control.root.y - self.listScroll.scrollY
    if self.noteDrag or control.root.hidden or top < 0 or top + control.root.height > self.listScroll.root.height then tooltip:Hide(); return end
    prettyui.Tooltip.hideContextTooltips(self.listScroll.content)
    if self.gearTooltip then self.gearTooltip:Hide() end
    if self.actionBarTooltip then self.actionBarTooltip:Hide() end
    if self.rowTooltip then self.rowTooltip:Hide() end
    tooltip:Show(control.root, kind == "gear" and row.note.gear or row.note.actionBar)
end

function NoteList:ShowDescription(x, y)
    local tooltip = self.rowTooltip
    if not tooltip then return end
        tooltip.cursorX, tooltip.cursorY = x, y
        local contentY = (y or 0) + self.listScroll.scrollY
        local description, rich, row_
        if not self.noteDrag then
            local row = NoteLayout.Hit(self.noteRows, x, contentY)
            row_ = row
            if row then
                description = row.compact and row.compactTip or row.description
                rich = row.rich
                local localX, localY = x - row.x, contentY - row.y
                local badgeHit = row.badgeHit
                if badgeHit and localX >= badgeHit.x1 and localX <= badgeHit.x2 and localY >= badgeHit.y1 and localY <= badgeHit.y2 then
                    description, rich = badgeHit.text, nil
                end
                for _, hit in ipairs(row.reqHits or {}) do
                    if localX >= hit.x1 and localX <= hit.x2 and localY >= hit.y1 and localY <= hit.y2 then
                        description, rich = hit.text, nil
                        break
                    end
                end
                for index, hit in ipairs(row.subHits or {}) do
                    local sub = row.subTasks and row.subTasks[index]
                    if sub and sub.tip and localX >= hit.x1 and localX <= hit.x2 and localY >= hit.y1 and localY <= hit.y2 then
                        description, rich = sub.tip, nil
                        break
                    end
                end
            end
        end
        if rich and row_ and row_.compact and row_.compactReq then
            -- Compact notes hide their requirements, so the quest card carries them below its description.
            local cached = row_.compactRich
            if not cached or cached.source ~= rich or cached.req ~= row_.compactReq then
                local copy = {}
                for key, value in pairs(rich) do copy[key] = value end
                copy.body = tostring(rich.body or "") .. "<br><br>" .. row_.compactReq
                copy.key = tostring(rich.key) .. ":req:" .. row_.compactReq
                cached = {source = rich, req = row_.compactReq, parts = copy}
                row_.compactRich = cached
            end
            rich = cached.parts
        end
        if rich and QuestTooltip.Prepare(tooltip) and QuestTooltip.Set(tooltip, rich, 360) then
            tooltip:Show()
            return
        end
        QuestTooltip.Clear(tooltip)
        if description and description ~= "" then
            if tooltip.options.text ~= description then tooltip:SetText(description) end
            tooltip:Show()
        else tooltip:Hide() end
    end

function NoteList:RenderRows()
    local wasRecovery = self.compactRecovery
    self.rowsReady, self.compactRecovery = false, false
    if self.noteDrag then self.noteDrag:Destroy(); self.noteDrag = nil end
    if self.cardPool then self.cardPool:Clear() end
    self.pendingDeleteNote, self.pendingSubPage = nil, nil
    self.capacityCost = Capacity.Estimate(self.data)
    if wasRecovery or self.capacityCost > Capacity.BUDGET then
        if self.cardPool then self.cardPool:Destroy(); self.cardPool = nil end
        if self.rowTooltip then self.rowTooltip:Destroy(); self.rowTooltip = nil end
        if self.listScroll then self.listScroll.onLayout = nil; self.listScroll:Destroy(); self.listScroll = nil end
        self.noteHit, self.emptyList = nil, nil
        if self.capacityCost > Capacity.BUDGET then return CapacityRecovery.Render(self) end
    end
    self.noteRows = {}
    local notes = self.data.notes
    local visible, hasGear, hasActionBar = {}, false, false
    for index, note in ipairs(notes) do
        if (self.categoryID == nil or (note.categoryID or 0) == self.categoryID)
            and (self.query == "" or ((note.title or "") .. " " .. note.text .. " "
                .. (note.tracking and note.tracking.label or "")):lower():find(self.query:lower(), 1, true)) then
            visible[#visible + 1] = index
            hasGear, hasActionBar = hasGear or note.gear ~= nil, hasActionBar or note.actionBar ~= nil
        end
    end
    local category = Notes.FindCategory(self.data, self.categoryID)
    self.alphabetical = category ~= nil and category.name:lower() == "scheduled"
    if self.alphabetical then
        table.sort(visible, function(left, right)
            local a, b = notes[left], notes[right]
            local first = (a.title ~= "" and a.title or a.tracking and a.tracking.label or a.text):lower()
            local second = (b.title ~= "" and b.title or b.tracking and b.tracking.label or b.text):lower()
            return first == second and left < right or first < second
        end)
    end
    self.visibleNotes = visible
    self.rowGearOffset = hasGear and 24 or 0
    self.rowActionOffset = self.rowGearOffset + (hasActionBar and 24 or 0)
    self.rowActionsWidth = 64 + self.rowActionOffset
    if not self.listScroll then
        self.listScroll = prettyui.SimpleView.new(self.surface, Components.Options({x = self.listX, y = self.listY,
            width = self.listWidth, height = math.max(1, self.height - self.listY - (self.countFooter or 70)), scrollStep = 48}))
        self.noteHit = Components.New(ui.Layer, self.listScroll.root)
        self.noteHit.clickthrough = true
        self.rowTooltip = prettyui.Tooltip.attach(self.noteHit, self.surface,
            Components.Options({text = "", placement = "right", maxWidth = 360}), {followCursor = true,
                onMouseOver = function(tooltip) self:ShowDescription(tooltip.cursorX, tooltip.cursorY) end})
        WindowStyle.ApplyTooltip(self.rowTooltip)
        self.noteHit.clickthrough = true
        self.cardPool = CardPool.new(self, {buildRequirements = buildRequirements, updateRequirements = updateRequirements,
            updateTrackingIcon = updateTrackingIcon, updateSubTasks = updateSubTasks, placeBadge = placeBadge})
        self.emptyList = label(self.listScroll.content, "", 8, 12, 1, 48, MUTED)
        self.listScroll.onLayout = function()
            if self.layingOutRows or not self.rowsReady then return end
            if self.gearTooltip then self.gearTooltip:Hide() end
            if self.actionBarTooltip then self.actionBarTooltip:Hide() end
            if self.rowTooltip then self.rowTooltip:Hide() end
            self:LayoutNoteHits()
        end
    end
    if hasGear and not self.gearTooltip then self.gearTooltip = GearTooltip.new(self.listScroll.content) end
    if hasActionBar and not self.actionBarTooltip then self.actionBarTooltip = ActionBarTooltip.new(self.listScroll.content) end
    local fontName = noteFont(self.settings)
    local font = config.Font[fontName]
    for position, index in ipairs(visible) do
        local note = notes[index]
        local row = {note = note, position = position, requirements = {}, requirementSignature = ""}
        row.customIcon = Sprites.Get(note.skill) ~= nil
        row.trackingIcon = note.tracking and Tracking.Icon(note.tracking)
        row.allSubTasks = note.tracking and Tracking.SubTasks(note.tracking)
        row.hasSubTasks = row.allSubTasks ~= nil and #row.allSubTasks > 0
        row.hasIcon = row.customIcon or row.trackingIcon ~= nil or note.tracking ~= nil and note.tracking.noIcon ~= true
        row.compact = self.settings.compactNotes == true and note.tracking ~= nil
        row.expanded = note.subjectExpanded
        if row.expanded == nil then row.expanded = row.hasSubTasks and Tracking.TasksOnly(note.tracking) or not row.hasSubTasks and self.settings.showSubject end
        if row.compact then row.expanded = false end
        row.text = subjectText(note, row.expanded)
        row.subTasks = row.expanded and sliceSubTasks(row, row.allSubTasks) or nil
        row.showSubject = (note.text ~= "" or row.hasSubTasks) and not row.compact
        row.subjectDetails = row.hasSubTasks and (note.text ~= "" and "subject and task steps" or "task steps") or "subject"
        row.description = hoverText(note, note.tracking and Tracking.Description(note.tracking))
        if note.tracking then
            row.progress = Tracking.Read(note.tracking)
            row.progressText = row.progress.text
            row.requirements = Tracking.Requirements(note.tracking)
            row.fullRequirements = row.requirements
            if row.compact then row.requirements = {} end
            row.requirementSignature = requirementsSignature(row.requirements)
            row.requirementMetrics = requirementMetrics(row.requirements, font)
            row.reqs = row.requirementMetrics
            row.hasBadge = Tracking.HasTitleBadge(note.tracking)
            row.titleColour = Tracking.TitleColour(note.tracking)
            -- The multi-coloured name, only while the note still carries the title's own name.
            local markup = row.titleColour and Tracking.TitleMarkup(note.tracking)
            row.titleMarkup = markup and (markup:gsub("<[^>]*>", "")) == note.title and markup or nil
            row.stripPlan = not row.compact and stripDescriptor(note, row.progress, self.settings) or nil
            row.itemStrip = row.stripPlan
            refreshCompact(row)
            if note.tracking.category == "Quests" or note.tracking.category == "Slayer" then
                local ok, rich = pcall(Tracking.QuestTooltip, note.tracking)
                row.rich = ok and hoverPreview(note, rich) or nil
            end
        end
        self.noteRows[#self.noteRows + 1] = row
    end
    self.emptyList.hidden = #visible ~= 0
    self.emptyList.content = #notes == 0 and "Press + to write your first note." or "No matching notes."
    self:UpdateCount(self.capacityCost)
    self:LayoutRows(self.scroll, true)
end

function NoteList:AddContextMenu(miniMenu)
    if not self.noteDrag and self.view == "list" and self.categorySidebar and self.categorySidebar:AddContextMenu(miniMenu) then return end
    if self.noteDrag or self.view ~= "list" or not self.listScroll or not self.noteHit then return end
    local x, y = Overlay.Mouse(self.listScroll.root)
    if x < self.noteHit.x or x >= self.noteHit.x + self.noteHit.width
        or y < 0 or y >= self.listScroll.root.height then return end
    y = y + self.listScroll.scrollY
    local notes = self.data.notes
    for _, row in ipairs(self.noteRows) do
        if row.hit and row.hit.isMouseOver and NoteLayout.Hit(self.noteRows, x, y) == row then
            local note = row.note
            local function select(action)
                if self.destroyed or self.view ~= "list" or self.data.notes ~= notes then return end
                for index, current in ipairs(notes) do
                    if current == note then
                        self.scroll = self.listScroll.scrollY
                        self:Edit(index, action)
                        return
                    end
                end
            end
            miniMenu:Add("Edit", function() select("edit") end)
            miniMenu:Add("Color", function() select("color") end)
            miniMenu:Add("Delete", function() select("delete") end)
            return
        end
    end
end

function NoteList:UpdateProgressBars()
    for _, row in ipairs(self.noteRows or {}) do
        if row.progressTrack then
            local hidden = row.progress == nil or self.settings.showProgressBars == false or row.progress.statusOnly == true
            row.progressTrack.hidden = hidden
            row.progressBar.hidden = hidden or (row.progress.fraction or 0) <= 0
        end
    end
end

function NoteList:RefreshTracking(skipLayout)
    if self.compactRecovery then return end
    local needsLayout = false
    for _, row in ipairs(self.noteRows or {}) do
        if row.note.tracking then
            row.trackingIcon = Tracking.Icon(row.note.tracking)
            local progress = Tracking.Read(row.note.tracking)
            if row.progressText ~= progress.text then row.layoutWidth, needsLayout = nil, true end
            row.progress, row.progressText = progress, progress.text
            local requirements = Tracking.Requirements(row.note.tracking)
            row.fullRequirements = requirements
            if row.compact then requirements = {} end
            local signature = requirementsSignature(requirements)
            if row.requirementSignature ~= signature then row.layoutWidth, needsLayout = nil, true end
            row.requirements, row.requirementSignature = requirements, signature
            local strip = not row.compact and stripDescriptor(row.note, progress, self.settings) or nil
            if row.stripPlan and (not strip or row.stripPlan.height ~= strip.height or row.stripPlan.signature ~= strip.signature)
                or strip and not row.stripPlan then row.layoutWidth, needsLayout = nil, true end
            row.stripPlan = strip
            if not row.slot then row.itemStrip = strip end
            if row.slot and row.itemStrip and row.itemStrip ~= strip then row.itemStrip:Refresh(nil, progress) end
            if row.note.tracking.category == "Slayer" then
                local ok, rich = pcall(Tracking.QuestTooltip, row.note.tracking)
                row.rich = ok and hoverPreview(row.note, rich) or nil
            end
            local beforePage, beforeTotal = row.subPageCount, row.subTotal
            local previousSubject = row.showSubject
            local previousSubTasks = row.subTasks or {}
            row.allSubTasks = Tracking.SubTasks(row.note.tracking) or {}
            row.hasSubTasks = #row.allSubTasks > 0
            row.showSubject = (row.note.text ~= "" or row.hasSubTasks) and not row.compact
            row.subjectDetails = row.hasSubTasks and (row.note.text ~= "" and "subject and task steps" or "task steps") or "subject"
            if refreshCompact(row) then row.layoutWidth, needsLayout = nil, true end
            if row.showSubject ~= previousSubject then row.layoutWidth, needsLayout = nil, true end
            row.subTasks = row.expanded and sliceSubTasks(row, row.allSubTasks) or nil
            if not row.expanded then row.subPageCount = nil end
            if row.subPageCount ~= beforePage or row.subTotal ~= beforeTotal then row.layoutWidth, needsLayout = nil, true end
            if #previousSubTasks ~= #(row.subTasks or {}) then row.layoutWidth, needsLayout = nil, true end
            for index, sub in ipairs(row.subTasks or {}) do
                if not previousSubTasks[index] or previousSubTasks[index].text ~= sub.text then row.layoutWidth, needsLayout = nil, true; break end
            end
        end
    end
    if needsLayout and not skipLayout then self:LayoutRows(nil, true)
    elseif not skipLayout then self:LayoutNoteHits() end
end

function NoteList:ChangeSubPage(row, direction)
    if self.destroyed or self.clearing or not row or not row.subPageCount or self.noteRows[row.position] ~= row then return end
    local page = math.max(1, math.min(row.subPageCount, (row.subPageIndex or 1) + direction))
    if page == row.subPageIndex then return end
    subPages[row.note] = page
    row.allSubTasks = Tracking.SubTasks(row.note.tracking)
    row.subTasks = row.expanded and sliceSubTasks(row, row.allSubTasks) or nil
    row.layoutWidth = nil
    if self.rowTooltip then self.rowTooltip:Hide() end
    self:LayoutRows(self.listScroll.scrollY, true)
end

function NoteList:Tick()
    if self.destroyed then return end
    local pendingPage = self.pendingSubPage
    if pendingPage then
        self.pendingSubPage = nil
        self:ChangeSubPage(pendingPage.row, pendingPage.direction)
    end
    if self.rowTooltip and (self.noteDrag or self.window:IsDragging()) then self.rowTooltip:Hide() end
    if self.actionBarTooltip then
        if self.noteDrag or self.window:IsDragging() then self.actionBarTooltip:Hide()
        else self.actionBarTooltip:Tick() end
    end
    if self.noteDrag then self.noteDrag:Tick(true) end
    for _, row in ipairs(self.activeRows or {}) do
        if row.itemStrip then
            if self.noteDrag then row.itemStrip:HideTooltip() end
            row.itemStrip:Tick()
        end
    end
    if self.noteDrag and self.noteHit then self.noteHit:MoveToFront() end
    if self.categorySidebar then
        self.categorySidebar:Tick()
        self.categorySidebar:RefreshIcons()
    end
end

function NoteList:Destroy(detached)
    if self.destroyed then return end
    if not detached then self:Snapshot() end
    self.clearing = true
    if self.listScroll then self.listScroll.onLayout = nil end
    if self.cardPool then self.cardPool:Destroy(detached); self.cardPool = nil end
    if self.gearTooltip then self.gearTooltip:Destroy(detached); self.gearTooltip = nil end
    if self.actionBarTooltip then self.actionBarTooltip:Destroy(detached); self.actionBarTooltip = nil end
    if self.noteDrag then
        if detached then self.noteDrag.destroyed = true else self.noteDrag:Destroy() end
        self.noteDrag = nil
    end
    if self.rowTooltip then
        if detached then Detached.Tooltip(self.rowTooltip) end
        self.rowTooltip:Destroy()
        self.rowTooltip = nil
    end
    if self.categorySidebar then self.categorySidebar:Destroy(detached); self.categorySidebar = nil end
    if self.listScroll then
        if detached then Detached.Control(self.listScroll) else self.listScroll:Destroy() end
        self.listScroll = nil
    end
    self.noteRows, self.visibleNotes, self.noteHit = {}, nil, nil
    self.pendingDeleteNote = nil
    Base.Destroy(self, detached)
end

return NoteList
