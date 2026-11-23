local Base = require("src/ui/views/view")
local Components = require("src/ui/shared/components")
local Detached = require("src/ui/shared/detached_ui")
local WindowStyle = require("src/ui/window/window_style")
local Sprites = require("src/data/sprite_catalog")
local NoteLayout = require("src/ui/notes/note_layout")
local NoteDrag = require("src/ui/notes/note_drag")
local BossList = require("src/ui/tracking/boss_list")
local BossItemStrip = require("src/ui/tracking/boss_item_strip")
local TextLayout = require("src/ui/shared/text_layout")

local Pool = {}
Pool.__index = Pool

local ALIASES = {"component", "background", "glow", "divider", "topDivider", "trackingSprite", "iconSize",
    "progressLabel", "progressTrack", "progressBar", "hit", "deleteButton", "gearButton", "actionBarButton",
    "subjectButton", "badge", "subFaded", "subLit", "subPagerText", "subPagerPrevious", "subPagerNext"}
local OPTIONAL = {"gearButton", "actionBarButton", "subjectButton", "subPagerPrevious", "subPagerNext"}

local function place(component, x, y, width, height)
    if component.x ~= x or component.y ~= y then component:SetPos(x, y) end
    if component.width ~= width or component.height ~= height then component:SetSize(width, height) end
end

local function rectangle(parent, colour)
    local component = Components.New(ui.Rectangle, parent)
    component.fill, component.clickthrough, component.rgba = true, true, colour
    return component
end

local function current(view, slot)
    local row = slot.row
    return not view.destroyed and not view.clearing and row and row.slot == slot
        and view.noteRows[row.position] == row and row or nil
end

function Pool.new(view, helpers)
    return setmetatable({view = view, helpers = helpers, slots = {}, textPool = {}}, Pool)
end

function Pool:NewSlot()
    local view = self.view
    local slot = {generation = 0}
    slot.component = Components.Host(view.listScroll.content, {width = 1, height = 1})
    slot.component.clickthrough = false
    slot.background = rectangle(slot.component, 0xFFFFFF00)
    slot.glow = rectangle(slot.component, 0xE7D7B000)
    for _, component in ipairs({slot.background, slot.glow}) do component:SetSize(0, 0, 1, 1) end
    slot.divider = rectangle(slot.component, 0xE7D7B033)
    slot.topDivider = rectangle(slot.component, 0xE7D7B033)
    slot.trackingSprite = Components.New(ui.Sprite, slot.component)
    slot.trackingSprite.clickthrough = true
    slot.progressLabel = Base.Label(slot.component, "", 8, 8, 1, 18)
    slot.progressTrack = rectangle(slot.component, 0xFFFFFF18)
    slot.progressBar = rectangle(slot.component, 0xFFDA35FF)
    slot.deleteButton = prettyui.SpriteButton.new(view.listScroll.content, "TRASH", nil,
        Components.Options({width = 20, height = 20}))
    slot.hit = Components.New(ui.Layer, view.noteHit)
    slot.hit.clickthrough = false
    local cursorID
    for _, name in ipairs({"CURSOR_HAND", "TOPLEVEL_V2_HAND", "CURSOR_POINTER", "CURSOR_READ"}) do
        local ok, value = pcall(function() return id.Cursor[name] end)
        if ok and value ~= nil then cursorID = value; break end
    end
    if cursorID then
        pcall(function() slot.hit.cursorConfig.mouseOverCursor = cursorID end)
        pcall(function() slot.hit.opConfig:SetOpCursor(0, cursorID) end)
    end
    slot.hit:Subscribe(ui.Hook.ONCLICK, function(component, x, y)
        local row = current(view, slot)
        if not row or view.noteDrag or type(x) ~= "number" or type(y) ~= "number" then return false end
        if NoteLayout.Hit(view.noteRows, component.x + x, component.y + y + view.listScroll.scrollY) == row then
            view.noteDrag = NoteDrag.new(view, row, component, x, y)
        end
        return false
    end)
    local function move(component, x, y)
        if current(view, slot) and view.noteDrag then view.noteDrag:Pointer(component, x, y) end
        return false
    end
    slot.hit:Subscribe(ui.Hook.ONHOLD, move)
    slot.hit:Subscribe(ui.Hook.ONDRAG, move)
    local function finish(component, x, y)
        if current(view, slot) and view.noteDrag then view.noteDrag:Finish(component, x, y) end
        return false
    end
    slot.hit:Subscribe(ui.Hook.ONRELEASE, finish)
    slot.hit:Subscribe(ui.Hook.ONDRAGCOMPLETE, function(component, _, x, y) return finish(component, x, y) end)
    local function wheel(_, rotation)
        if not view.destroyed and not view.clearing and view.listScroll then
            if view.rowTooltip then view.rowTooltip:Hide() end
            view.listScroll:ScrollBy(rotation * 48)
        end
        return false
    end
    slot.component:Subscribe(ui.Hook.ONSCROLLWHEEL, wheel)
    slot.hit:Subscribe(ui.Hook.ONSCROLLWHEEL, wheel)
    local function hover(component, x, y)
        if not current(view, slot) then return true end
        if not view.noteDrag then slot.glow.rgba = 0xE7D7B026 end
        if type(x) == "number" and type(y) == "number" then view:ShowDescription(component.x + x, component.y + y) end
        return true
    end
    slot.hit:Subscribe(ui.Hook.ONMOUSEOVER, hover)
    slot.hit:Subscribe(ui.Hook.ONMOUSEREPEAT, hover)
    slot.hit:Subscribe(ui.Hook.ONMOUSELEAVE, function()
        if not current(view, slot) then return true end
        slot.glow.rgba = 0xE7D7B000
        if view.rowTooltip then view.rowTooltip:Hide() end
        return true
    end)
    slot.deleteButton.root:Subscribe(ui.Hook.ONMOUSEOVER, "notes_row_glow", function()
        if current(view, slot) and not view.noteDrag then slot.glow.rgba = 0xE7D7B026 end
        return false
    end)
    slot.deleteButton.root:Subscribe(ui.Hook.ONMOUSELEAVE, "notes_row_glow", function()
        if current(view, slot) then slot.glow.rgba = 0xE7D7B000 end
        return false
    end)
    self.slots[#self.slots + 1] = slot
    return slot
end

function Pool:Bind(row, slot)
    if row.slot then return row.slot end
    if not slot then
        for _, candidate in ipairs(self.slots) do if not candidate.row then slot = candidate; break end end
    end
    slot = slot or self:NewSlot()
    slot.generation = slot.generation + 1
    slot.row, row.slot = row, slot
    for _, name in ipairs(ALIASES) do row[name] = slot[name] end
    row.labels, row.labelEntries = {}, {}
    row.iconSignature, row.appliedPlan, row.nativeShape = nil, nil, row.shape
    row.iconSize = math.floor(24 * select(2, Base.NoteFont(self.view.settings)) / 14 + 0.5)
    local view, generation = self.view, slot.generation
    local function valid()
        return current(view, slot) == row and slot.generation == generation
    end
    row.deleteButton.action = function() if valid() then view:DeleteRow(row) end end
    local function spriteButton(name, sprite, action, options)
        local button = prettyui.SpriteButton.new(view.listScroll.content, sprite,
            function() if valid() then action() end end, Components.Options(options))
        row[name], slot[name] = button, button
        return button
    end
    if row.showSubject then
        local button = spriteButton("subjectButton", row.expanded and "ARROW_DOWN" or "ARROW_RIGHT",
            function() view:ToggleSubject(row) end, {width = 16, height = 16,
                tooltip = (row.expanded and "Hide " or "Show ") .. row.subjectDetails})
        WindowStyle.ApplyTooltip(button.tooltip)
        row.subjectTooltipExpanded = row.expanded
    end
    local function attachment(name, sprite, kind)
        local button = prettyui.SimpleButton.new(view.listScroll.content, Sprites.SpriteID(sprite) or (kind == "gear" and "G" or "A"),
            function() if valid() then view:OpenRowAttachment(row, kind) end end,
            Components.Options({width = 20, height = 20, iconSize = 16}))
        row[name], slot[name] = button, button
        if button.contentType == "number" then button.content:SetPos(2, 2); button.content:SetSize(16, 16) end
        local function show()
            if valid() then view:ShowRowAttachment(row, kind) end
            return true
        end
        button.root:Subscribe(ui.Hook.ONMOUSEOVER, "notes_attachment_popup", show)
        button.root:Subscribe(ui.Hook.ONMOUSEREPEAT, "notes_attachment_popup", show)
        button.root:Subscribe(ui.Hook.ONMOUSELEAVE, "notes_attachment_popup", function()
            local tooltip = kind == "gear" and view.gearTooltip or view.actionBarTooltip
            if valid() and tooltip then tooltip:Hide() end
            return true
        end)
    end
    if row.note.gear then attachment("gearButton", "ICON_MOBILE_WORNEQUIPMENT", "gear") end
    if row.note.actionBar then attachment("actionBarButton", "RS3_ICON_PLUGIN_HUB_SETTINGS_ACTIVE", "actionBar") end
    for _, key in ipairs({"gearButton", "actionBarButton", "subjectButton"}) do
        local button = row[key]
        if button then
            button.root:Subscribe(ui.Hook.ONMOUSEOVER, "notes_row_glow", function()
                if valid() and not view.noteDrag then slot.glow.rgba = 0xE7D7B026 end
                return false
            end)
            button.root:Subscribe(ui.Hook.ONMOUSELEAVE, "notes_row_glow", function()
                if valid() then slot.glow.rgba = 0xE7D7B000 end
                return false
            end)
        end
    end
    local fontName = Base.NoteFont(view.settings)
    local font = config.Font[fontName]
    if row.note.tracking then
        if #row.requirements > 0 then row.reqs = self.helpers.buildRequirements(row.component, row.requirements, font, fontName) end
        if row.hasBadge then
            row.badge = {icon = Components.New(ui.Sprite, row.component), mark = Components.New(ui.Sprite, row.component), size = font.baseline}
            row.badge.icon.clickthrough, row.badge.mark.clickthrough = true, true
        end
        self.helpers.updateSubTasks(row, row.allSubTasks, font, fontName)
        if row.stripPlan then
            local context = prettyui.Tooltip.getContext(view.surface)
            row.itemStrip = row.stripPlan.kind == "list"
                and BossList.new(view.listScroll.root, row.stripPlan.items, row.note.tracking, row.progress, context, view.settings)
                or BossItemStrip.new(view.listScroll.root, row.stripPlan.items, context)
            row.itemStrip.first = row.stripFirst or 1
            row.itemStrip.onScroll = function(rotation)
                if valid() and view.listScroll then view.listScroll:ScrollBy(rotation * 48) end
            end
        end
    end
    if row.contentPlan.subPager then
        row.subPagerText = Base.Label(row.component, "", 0, 0, 1, 24, 0xBFBFBFFF, id.Font[fontName])
        row.subPagerText.alignHorizontal = ui.AlignMode.CENTRE
        for _, entry in ipairs({{"subPagerPrevious", "ARROW_LEFT", -1}, {"subPagerNext", "ARROW_RIGHT", 1}}) do
            local direction = entry[3]
            local button = prettyui.SpriteButton.new(view.listScroll.root, entry[2], function()
                if valid() then view.pendingSubPage = {row = row, direction = direction} end
            end, Components.Options({width = 16, height = 24}))
            row[entry[1]], slot[entry[1]] = button, button
            button.root:Subscribe(ui.Hook.ONSCROLLWHEEL, function(_, rotation)
                if valid() and view.listScroll then view.listScroll:ScrollBy(rotation * 48) end
                return false
            end)
        end
    end
    Sprites.Clear(row.trackingSprite)
    row.trackingSprite.hidden = true
    if row.customIcon then
        -- The sprite was hidden by Clear above: it is shown again once the chosen icon has been applied.
        row.trackingSprite.hidden = not Sprites.Apply(row.trackingSprite, row.note.skill)
        place(row.trackingSprite, 8, 6, row.iconSize, row.iconSize)
    elseif row.note.tracking then self.helpers.updateTrackingIcon(row, row.trackingIcon) end
    row.component.hidden = false
    return slot
end

function Pool:ReleaseText(row, detached)
    for _, entry in ipairs(row.labelEntries or {}) do
        entry.owner = nil
        if not detached then entry.component.hidden = true end
    end
    row.labels, row.labelEntries = {}, {}
end

function Pool:Release(row, detached, preserveHit)
    local slot = row.slot
    if not slot then return end
    self:ReleaseText(row, detached)
    if row.itemStrip and row.itemStrip ~= row.stripPlan then
        row.stripFirst = row.itemStrip.first
        row.itemStrip:Destroy(detached)
    end
    local function destroy(component)
        if component and not detached then component:Destroy() end
    end
    if row.reqs and row.reqs.prefix then
        destroy(row.reqs.prefix)
        for _, item in ipairs(row.reqs.items) do
            for _, key in ipairs({"icon", "faded", "lit", "mark"}) do destroy(item[key]) end
        end
    end
    if row.badge then destroy(row.badge.icon); destroy(row.badge.mark) end
    for _, entries in ipairs({row.subFaded or {}, row.subLit or {}}) do
        for _, component in ipairs(entries) do destroy(component) end
    end
    destroy(row.subPagerText)
    for _, key in ipairs(OPTIONAL) do
        if row[key] then
            if detached then Detached.Control(row[key]) else row[key]:Destroy() end
        end
        slot[key] = nil
    end
    if not detached then
        slot.component.hidden, slot.deleteButton.root.hidden = true, true
        if not preserveHit then slot.hit.hidden = true end
        slot.glow.rgba = 0xE7D7B000
    end
    for _, key in ipairs(ALIASES) do row[key] = nil end
    row.reqs, row.itemStrip, row.slot = row.requirementMetrics, row.stripPlan, nil
    row.appliedPlan, row.nativeShape = nil, nil
    slot.row = nil
end

function Pool:TextRange(row, font, scroll)
    local view, plan = self.view, row.contentPlan
    local first = math.max(1, math.floor((scroll - row.y - 6) / font.baseline))
    local last = math.min(#plan.lines, math.ceil((scroll + view.listScroll.root.height - row.y - 6) / font.baseline) + 1)
    return first, math.max(0, last - first + 1)
end

function Pool:TrimText(row, needed)
    while row.labelEntries and #row.labelEntries > needed do
        local entry = table.remove(row.labelEntries)
        entry.owner, entry.component.hidden = nil, true
        table.remove(row.labels)
    end
end

function Pool:PaintText(row, font, fontName, scroll)
    local view, plan = self.view, row.contentPlan
    local first, needed = self:TextRange(row, font, scroll)
    self:TrimText(row, needed)
    while #row.labelEntries < needed do
        local free
        for _, entry in ipairs(self.textPool) do if not entry.owner then free = entry; break end end
        if not free then
            free = {component = Base.Label(view.listScroll.content, "", 0, 0, 1, 18)}
            self.textPool[#self.textPool + 1] = free
        end
        free.owner = row
        row.labelEntries[#row.labelEntries + 1] = free
        row.labels[#row.labels + 1] = free.component
    end
    -- A title note (still in the default white) wears the title's colour on the lines of its name.
    local titleLines = row.titleColour and tostring(row.note.color):upper() == "FFFFFF"
        and #TextLayout.Lines(row.note.title or "", font, plan.textWidth) or 0
    for index, entry in ipairs(row.labelEntries) do
        local line = first + index - 1
        local component = entry.component
        component.hidden, component.font = false, id.Font[fontName]
        component.rgba, component.content = tonumber(line <= titleLines and row.titleColour or row.note.color, 16) * 256 + 255, plan.lines[line]
        -- A one-line title with several colours is drawn with all of them (the text part left plain is the note's colour).
        if line == 1 and titleLines == 1 and row.titleMarkup then
            component.rgba, component.content = tonumber(row.note.color, 16) * 256 + 255, row.titleMarkup
        end
        place(component, row.x + row.textX, row.y + 6 + (line - 1) * font.baseline, plan.textWidth, font.baseline + 2)
        component:MoveToFront()
    end
    row.firstVisibleLine = needed > 0 and first or nil
end

function Pool:Paint(row)
    local view, plan = self.view, row.contentPlan
    local scroll = view.listScroll.scrollY
    local fontName = Base.NoteFont(view.settings)
    local font = config.Font[fontName]
    place(row.component, row.x, row.y, row.width, row.height)
    row.background.rgba = row.columns > 1 and (row.position % 2 == 0 and 0xFFFFFF0B or 0xFFFFFF07)
        or (row.position % 2 == 0 and 0xFFFFFF0B or 0xFFFFFF00)
    row.divider.hidden = row.columns == 1 and row.position == #view.noteRows
    place(row.divider, 8, row.height - 1, math.max(1, row.width - 16), 1)
    row.topDivider.hidden = row.columns == 1
    place(row.topDivider, 8, 0, math.max(1, row.width - 16), 1)
    row.progressLabel.hidden = not row.progress
    row.progressTrack.hidden = not row.progress or view.settings.showProgressBars == false or row.progress.statusOnly == true
    row.progressBar.hidden = row.progressTrack.hidden or (row.progress.fraction or 0) <= 0
    if row.progress then
        if not row.customIcon then self.helpers.updateTrackingIcon(row, row.trackingIcon) end
        row.progressLabel.font, row.progressLabel.content = id.Font[fontName], plan.progressText
        place(row.progressLabel, row.textX, plan.progressY, plan.textWidth, plan.progressHeight)
        row.progressY, row.textWidth = plan.progressY, plan.textWidth
        row.progressWidth = math.max(1, row.textX + plan.textWidth - 8)
        local barY = row.height - plan.footerHeight - 12
        place(row.progressTrack, 8, barY, row.progressWidth, 6)
        place(row.progressBar, 8, barY, math.floor(row.progressWidth * (row.progress.fraction or 0)), 6)
        if row.reqs and row.reqs.prefix then self.helpers.updateRequirements(row, row.requirements) end
        if row.badge then self.helpers.placeBadge(row, plan, font) end
        self.helpers.updateSubTasks(row, row.allSubTasks, font, fontName)
        row.subHits = {}
        for index, bounds in ipairs(plan.subtasks) do
            for _, component in ipairs({row.subFaded[index], row.subLit[index]}) do
                component.font, component.content = id.Font[fontName], bounds.text
                place(component, bounds.x, bounds.y, bounds.width, bounds.height)
            end
            row.subHits[index] = {x1 = bounds.x, x2 = bounds.x + bounds.width, y1 = bounds.y, y2 = bounds.y + bounds.height}
        end
        if row.itemStrip and row.itemStrip ~= row.stripPlan then
            local bounds = plan.itemStrip
            if bounds then
                local top = row.y + bounds.y - scroll
                row.itemStrip:SetBounds(row.x + bounds.x, top, bounds.width)
                if row.itemStrip.SetClip then
                    row.itemStrip:SetClip(-top, view.listScroll.root.height - top)
                    row.itemStrip:SetVisible(top < view.listScroll.root.height and top + bounds.height > 0)
                else row.itemStrip:SetVisible(top >= 0 and top + bounds.height <= view.listScroll.root.height) end
                row.itemStrip.root:MoveToFront()
            else row.itemStrip:SetVisible(false) end
        end
    end
    for _, name in ipairs({"gearButton", "actionBarButton", "subjectButton", "deleteButton"}) do
        local button, bounds = row[name], row.actions[name]
        if button then
            local top = bounds and row.y + bounds.y - scroll
            button.root.hidden = not bounds or top < 0 or top + bounds.height > view.listScroll.root.height
            if bounds then place(button.root, row.x + bounds.x, row.y + bounds.y, bounds.width, bounds.height) end
        end
    end
    if row.subjectButton then
        row.subjectButton:SetSprite(row.expanded and "ARROW_DOWN" or "ARROW_RIGHT")
        if row.subjectTooltipExpanded ~= row.expanded then
            row.subjectButton:SetTooltip((row.expanded and "Hide " or "Show ") .. row.subjectDetails)
            WindowStyle.ApplyTooltip(row.subjectButton.tooltip)
            row.subjectTooltipExpanded = row.expanded
        end
    end
    local pager = plan.subPager
    if row.subPagerText then
        row.subPagerText.hidden = not pager
        if pager then
            row.subPagerText.content, row.subPagerText.font = pager.text, id.Font[fontName]
            place(row.subPagerText, pager.x + 20, pager.y + 4, math.max(1, pager.width - 40), pager.height - 4)
            row.subPagerPrevious:SetDisabled(not pager.canPrevious)
            row.subPagerNext:SetDisabled(not pager.canNext)
        end
        for _, pair in ipairs({{"subPagerPrevious", "previous"}, {"subPagerNext", "next"}}) do
            local button = row[pair[1]]
            local bounds = row.subPagerBounds and row.subPagerBounds[pair[2]]
            local top = bounds and row.y + bounds.y - scroll
            button.root.hidden = not bounds or top < 0 or top + bounds.height > view.listScroll.root.height
            if not button.root.hidden then
                place(button.root, row.x + bounds.x, top, bounds.width, bounds.height)
                button.root:MoveToFront()
            end
        end
    end
    if not (view.noteDrag and view.noteDrag.captureExpanded and view.noteDrag.capture == row.hit) then
        local top = row.y - scroll
        local first, last = math.max(0, top), math.min(view.listScroll.root.height, top + row.bodyHeight)
        row.hit.hidden = last <= first
        place(row.hit, row.x, first, row.bodyWidth, math.max(1, last - first))
    end
    self:PaintText(row, font, fontName, scroll)
end

function Pool:Update()
    if self.updating or self.view.destroyed or self.view.clearing then return end
    self.updating = true
    local view = self.view
    local first, last = NoteLayout.VisibleRange(view.noteRows, view.listScroll.scrollY, view.listScroll.root.height, 1)
    local desired, active = {}, {}
    for index = first, last do desired[view.noteRows[index]] = true; active[#active + 1] = view.noteRows[index] end
    local dragged = view.noteDrag and view.noteDrag.row
    if dragged and not desired[dragged] then desired[dragged] = true; active[#active + 1] = dragged end
    local captureSlot
    for _, slot in ipairs(self.slots) do
        if slot.row and (not desired[slot.row] or slot.row.nativeShape ~= slot.row.shape) then
            local preserveHit = slot.row == dragged and view.noteDrag.capture == slot.hit
            if preserveHit then captureSlot = slot end
            self:Release(slot.row, false, preserveHit)
        end
    end
    -- A live shape change must keep the native component holding the mouse capture.
    if captureSlot then self:Bind(dragged, captureSlot) end
    local fontName = Base.NoteFont(view.settings)
    local font = config.Font[fontName]
    -- Release leaving lines before entering rows acquire labels, so jumps retain only one viewport's peak.
    for _, row in ipairs(active) do
        local _, needed = self:TextRange(row, font, view.listScroll.scrollY)
        self:TrimText(row, needed)
    end
    for _, row in ipairs(active) do self:Bind(row); self:Paint(row) end
    view.activeRows = active
    self.updating = false
end

function Pool:Clear(detached)
    for _, slot in ipairs(self.slots) do if slot.row then self:Release(slot.row, detached) end end
    self.view.activeRows = {}
end

function Pool:Destroy(detached)
    self:Clear(detached)
    for _, slot in ipairs(self.slots) do
        if detached then Detached.Control(slot.deleteButton) else
            slot.deleteButton:Destroy()
            slot.hit:Destroy()
            slot.component:Destroy()
        end
    end
    if not detached then for _, entry in ipairs(self.textPool) do entry.component:Destroy() end end
    self.slots, self.textPool = {}, {}
end

return Pool
