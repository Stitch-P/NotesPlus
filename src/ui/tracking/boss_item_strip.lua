local Components = require("src/ui/shared/components")
local Tracking = require("src/tracking/model")
local Vars = require("src/tracking/core/vars")
local WindowStyle = require("src/ui/window/window_style")
local Detached = require("src/ui/shared/detached_ui")
local ComponentTooltip = require("src/ui/tracking/component_perk_tooltip")
local QuestTooltip = require("src/ui/tracking/quest_tooltip")

local Strip = {}
Strip.__index = Strip

local SLOT_SIZE, GAP, HEIGHT = 40, 4, 44
local TARGET_LABEL_HEIGHT = 36
local MAX_VISIBLE = 32
-- Lists that drop finished entries (Reaper crew) show a short page at a time and scroll for the rest.
local PAGE_SIZE = 7

local function place(component, x, y, width, height)
    if component.x ~= x or component.y ~= y then component:SetPos(x, y) end
    if component.width ~= width or component.height ~= height then component:SetSize(width, height) end
end

-- Shortened amounts keep one decimal (1,499 reads 1.4K, 1,500 reads 1.5K), rounded down so an amount never looks like it
-- has reached a target it has not.
local function shorten(value, size, suffix)
    local tenths = math.floor(value / (size / 10))
    if tenths % 10 == 0 then return tostring(math.floor(tenths / 10)) .. suffix end
    return tostring(math.floor(tenths / 10)) .. "." .. tostring(tenths % 10) .. suffix
end

local function quantityText(value)
    if type(value) ~= "number" then return "?" end
    if value >= 1000000000000000 then return shorten(value, 1000000000000000, "Q") end
    if value >= 1000000000000 then return shorten(value, 1000000000000, "T") end
    if value >= 1000000000 then return shorten(value, 1000000000, "B") end
    if value >= 1000000 then return shorten(value, 1000000, "M") end
    if value >= 1000 then return shorten(value, 1000, "K") end
    return tostring(math.floor(value))
end

local function quantityRatioText(current, target, width, xp)
    local count, goal = quantityText(current), quantityText(target)
    if xp then return count:lower() .. "/" .. goal:lower() end
    local ratio = count .. "/" .. goal
    local success, measured = pcall(function()
        return config.Font.MUSEO_SANS_13PT_REGULAR:GetStringWidth(ratio, false)
    end)
    if (success and measured or #ratio * 7) <= width then return ratio end
    return count .. "<br>/" .. goal
end

local Timers = require("src/tracking/features/boss_timers")

local function hasQuantityTarget(tracking)
    if not tracking then return false end
    -- Reward shop unlocks always show their price under the tile ("0/7.5K").
    local okPiece, piece = pcall(Tracking.ShopPiece, tracking)
    if okPiece and piece then return true end
    return Tracking.CollectionTargetEditable(tracking.category, tracking.group, tracking)
end

local function plain(value)
    return tostring(value or ""):gsub("<[Bb][Rr]%s*/?>", " "):gsub("<", "["):gsub(">", "]"):gsub("[%c]", " ")
end

local function multiline(value)
    local lines = {}
    for line in (tostring(value or ""):gsub("\r\n", "\n"):gsub("\r", "\n") .. "\n"):gmatch("(.-)\n") do
        lines[#lines + 1] = plain(line)
    end
    return table.concat(lines, "<br>")
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

local function iconRef(tracking)
    local ok, value = pcall(Tracking.Icon, tracking, true)
    if (not ok or not value) and tracking.category == "Currencies" then
        ok, value = pcall(Tracking.CategoryIcon, tracking.category)
    end
    return ok and value or nil
end

function Strip.Measure(items)
    local first = items and items[1]
    local research = first and Tracking.CollectionFixedTarget(first.category, first.group) ~= nil
    local targets = first and (first.category == "Invention" and not research or first.category == "Currencies"
        or first.category == "Ports" and not (type(first.key) == "string" and first.key:match("^cheevo:"))
        or first.category == "Skills" and first.skill ~= nil)
    for _, item in ipairs(items or {}) do targets = targets or hasQuantityTarget(item) end
    return targets and SLOT_SIZE + TARGET_LABEL_HEIGHT + 6 or HEIGHT
end

function Strip.new(parent, items, ownerContext)
    local first = items and items[1]
    local research = first and Tracking.CollectionFixedTarget(first.category, first.group) ~= nil
    local slayer = first and first.category == "Slayer"
    local components = first and first.category == "Invention" and not research
    local currencies = first and first.category == "Currencies"
    -- Ports lists count quantities (trade goods, resources); its goal lists (the scrolls) have no amount to show.
    local ports = first and first.category == "Ports" and not (type(first.key) == "string" and first.key:match("^cheevo:"))
    local skills = first and first.category == "Skills" and first.skill ~= nil
    local quantities = components or currencies or ports or skills
    local targets = quantities
    for _, item in ipairs(items or {}) do targets = targets or hasQuantityTarget(item) end
    local hideDone = first and first.hideComplete == true
    -- Unlocks that come one after another (Livid Farm spells) are shown in that order.
    if first and Tracking.OrderedTier(first) then
        local sorted = {}
        for index, item in ipairs(items) do sorted[index] = item end
        table.sort(sorted, function(a, b) return (Tracking.OrderedTier(a) or 0) < (Tracking.OrderedTier(b) or 0) end)
        items = sorted
    end
    local self = setmetatable({items = items or {}, list = items or {}, hideDone = hideDone,
        maxVisible = hideDone and PAGE_SIZE or MAX_VISIBLE, slots = {}, first = 1, active = false,
        height = Strip.Measure(items), components = components,
        skills = skills, xp = first and Tracking.IsSkillXP(first.category, first.group), research = research,
        words = slayer and first and type(first.key) == "string" and first.key:match("^cheevo:codex_")
                and {unavailable = "Codex status is not available yet.", done = "Captured", notDone = "Not captured yet"}
            or slayer and {unavailable = "Drop status is not available yet.", done = "Obtained", notDone = "Not obtained yet"}
            or first and type(first.key) == "string" and first.key:match("^cheevo:") and {unavailable = "Achievement status is not available yet.", done = "Completed", notDone = "Not completed yet"}
            or first and first.category == "Training" and {unavailable = "Floor status is not available yet.", done = "Completed", notDone = "Not completed yet"}
            or {unavailable = "Unlock status is not available yet.", done = "Unlocked", notDone = "Not unlocked yet"},
        quantities = quantities, targets = targets}, Strip)
    self.root = Components.Host(parent)
    self.root.hidden = true
    self.root.clickthrough = true
    self.root:SetSize(1, self.height)
    local context = ownerContext or tooltipContext(parent)
    local tooltipParent = context and context.parent or parent
    self.tooltipContext = prettyui.Tooltip.registerContext(self.root, tooltipParent, function(target)
        return position(target, tooltipParent)
    end, context)
    self.tooltipTarget = Components.New(ui.Layer, self.root)
    self.tooltipTarget.hidden, self.tooltipTarget.clickthrough = true, true
    self.sharedTooltip = prettyui.Tooltip.attach(self.tooltipTarget, self.root,
        Components.Options({text = research and (slayer and "Slayer drop" or "Research unlock") or skills and "Skill" or ports and "Port stock"
            or components and "Component" or currencies and "Currency" or "Boss item", placement = "above", maxWidth = 300}))
    WindowStyle.ApplyTooltip(self.sharedTooltip, function() self:HideTooltip() end)
    self.previousButton = prettyui.SpriteButton.new(self.root, "ARROW_LEFT", function()
        if not self.destroyed then self.pendingDirection = -1 end
    end, Components.Options({width = 16, height = 24}))
    self.nextButton = prettyui.SpriteButton.new(self.root, "ARROW_RIGHT", function()
        if not self.destroyed then self.pendingDirection = 1 end
    end, Components.Options({width = 16, height = 24}))
    self.previousButton.root.hidden, self.nextButton.root.hidden = true, true
    self:SetBounds(0, 0, 1)
    return self
end

function Strip:HideTooltip()
    self.hoveredSlot = nil
    if self.sharedTooltip then self.sharedTooltip:Hide() end
end

function Strip:ShowSlotTooltip(cell)
    if self.destroyed or self.root.hidden or cell.control.root.hidden or not cell.tracking then return end
    self:HideTooltip()
    self.hoveredSlot = cell
    self.tooltipTarget:SetPos(cell.control.root.x, cell.control.root.y)
    self.tooltipTarget:SetSize(cell.control.root.width, cell.control.root.height)
    local progress = cell.progress or {}
    local count = progress.current
    local key = cell.tracking.key
    if cell.tracking.bossId or type(key) == "string" and (key:match("^camp%-") or key:match("^fort:") or key:match("^arch%-relic:") or key:match("^arch%-art:") or key:match("^necro:") or key:match("^cheevo:")) then
        local okCard, card = pcall(Tracking.BossCard, cell.tracking)
        if okCard and card and QuestTooltip.Prepare(self.sharedTooltip) and QuestTooltip.Set(self.sharedTooltip, card, 360) then
            self.sharedTooltip:Show()
            return
        end
    end
    QuestTooltip.Clear(self.sharedTooltip)
    if self.components or self.research then
        local ok, perks = pcall(Tracking.ComponentPerks, cell.tracking)
        if ok and perks then
            local heading = cell.tracking.label or cell.tracking.variable
            local details = {}
            if self.research then
                details[1] = count == nil and self.words.unavailable
                    or progress.complete and self.words.done or self.words.notDone
            else
                heading = heading .. ": " .. (type(count) == "number" and Vars.withCommas(count) or "?")
                details[1] = "Target: " .. Vars.withCommas(cell.tracking.target)
                details[2] = progress.complete and "Target reached" or "Target not reached"
            end
            if ComponentTooltip.Prepare(self.sharedTooltip) and ComponentTooltip.Set(self.sharedTooltip, heading, perks,
                {details = details, sources = Tracking.ComponentSources(cell.tracking), maxWidth = 300}) then
                self.sharedTooltip:Show()
                return
            end
        end
    end
    ComponentTooltip.Clear(self.sharedTooltip)
    local description = ""
    if self.components or self.research then
        local ok, value = pcall(Tracking.Description, cell.tracking)
        if ok and value then description = "<br>" .. multiline(value) end
    end
    if self.research then
        local state = count == nil and self.words.unavailable
            or progress.complete and ("<col=55FF55>" .. self.words.done .. "</col>") or self.words.notDone
        self.sharedTooltip:SetText(plain(cell.tracking.label or cell.tracking.variable) .. "<br>" .. state .. description)
        self.sharedTooltip:Show()
        return
    end
    local clueReward = (cell.tracking.category == "Clues" or cell.tracking.category == "Unlocks" and cell.tracking.group == "Clues")
        and cell.tracking.ownedVar ~= nil
    if clueReward and progress.owned then
        self.sharedTooltip:SetText(plain(cell.tracking.label or cell.tracking.variable) .. "<br><col=55FF55>Unlocked</col>")
        self.sharedTooltip:Show()
        return
    end
    -- A reward shop unlock: its price, what you have of the currency and whether it can be bought yet.
    local okPiece, piece = pcall(Tracking.ShopPiece, cell.tracking)
    if okPiece and piece then
        local unit = piece.currencyName and (" " .. piece.currencyName) or ""
        local lines = { plain(cell.tracking.label or cell.tracking.variable), "Price: " .. Vars.withCommas(piece.cost) .. unit }
        if progress.owned then
            lines[#lines + 1] = "<col=55FF55>Unlocked</col>"
        else
            lines[#lines + 1] = type(count) == "number" and ("You have: " .. Vars.withCommas(count) .. unit) or "Your balance is not available yet."
            if type(count) == "number" then
                lines[#lines + 1] = count >= piece.cost and (piece.owned and "<col=55FF55>Ready to unlock</col>" or "<col=55FF55>Enough to buy</col>")
                    or ("Need " .. Vars.withCommas(piece.cost - count) .. unit .. " more")
            end
        end
        if piece.description then lines[#lines + 1] = multiline(piece.description) end
        self.sharedTooltip:SetText(table.concat(lines, "<br>"))
        self.sharedTooltip:Show()
        return
    end
    if Timers.isVar(cell.tracking.variable) then
        local best = type(count) == "number" and (count > 0 and Timers.format(count, cell.tracking.variable) or "no time yet") or "not available yet"
        self.sharedTooltip:SetText(plain(cell.tracking.label or cell.tracking.variable) .. "<br>Best time: " .. best
            .. "<br>Time to beat: " .. Timers.format(cell.tracking.target, cell.tracking.variable) .. "<br>"
            .. (progress.complete and "<col=55FF55>Target reached</col>" or "Target not reached"))
        self.sharedTooltip:Show()
        return
    end
    local xp = Tracking.IsSkillXP(cell.tracking.category, cell.tracking.group)
    local countLabel = clueReward and "Points: " or xp and "Current XP: " or self.skills and "Current level: " or cell.tracking.base ~= nil and "New drops: "
        or self.quantities and "You have: " or "In your item log: "
    local detail = type(count) == "number" and (countLabel .. Vars.withCommas(count))
        or "Item count is not available yet."
    local targeted = hasQuantityTarget(cell.tracking) or cell.tracking.target > 1 or cell.tracking.base ~= nil
    if targeted then detail = detail .. (xp and "<br>Target XP: " or self.skills and "<br>Target level: " or "<br>Target: ") .. Vars.withCommas(cell.tracking.target) end
    local state = progress.complete and (targeted and "<col=55FF55>Target reached</col>" or "<col=55FF55>Collected</col>")
        or (targeted and "Target not reached" or "Not collected")
    self.sharedTooltip:SetText(plain(cell.tracking.label or cell.tracking.variable) .. "<br>" .. detail .. "<br>" .. state .. description)
    self.sharedTooltip:Show()
end

local function createCell(self, container)
    local control = prettyui.ItemSlot.new(container, nil, Components.Options({clickthrough = false,
        quantityMode = (self.targets or self.research) and ui.ObjectQuantityDisplayMode.NEVER or ui.ObjectQuantityDisplayMode.MULTIPLE}))
    local cell = {control = control}
    cell.fallback = Components.New(ui.Sprite, control.root)
    cell.fallback.clickthrough = true
    cell.fallback.rgba = 0xFFFFFFFF
    cell.fallback.hidden = true
    cell.tile = prettyui.Text.new(control.root, Components.Options({text = "", width = 40, height = 20,
        font = id.Font.MUSEO_SANS_13PT_REGULAR, colour = 0xFFFFFFFF, shadowed = true, alignHorizontal = ui.AlignMode.CENTRE}))
    cell.tile.clickthrough, cell.tile.hidden = true, true
    cell.status = Components.New(ui.Rectangle, container)
    cell.status.fill, cell.status.clickthrough = true, true
    -- Partial progress (e.g. 34/50) fills the underline from the left.
    cell.fill = Components.New(ui.Rectangle, container)
    cell.fill.fill, cell.fill.clickthrough = true, true
    cell.fill.rgba = 0x55FF55FF
    if self.targets then
        cell.quantityLabel = prettyui.Text.new(container, Components.Options({text = "", font = id.Font.MUSEO_SANS_13PT_REGULAR,
            colour = 0xFFFFFFFF, shadowed = true, maxLines = self.xp and 1 or 2}))
        cell.quantityLabel.clickthrough = true
        cell.quantityLabel.alignHorizontal = ui.AlignMode.CENTRE
    end
    control.root:Subscribe(ui.Hook.ONMOUSEOVER, function()
        self:ShowSlotTooltip(cell)
        return true
    end)
    control.root:Subscribe(ui.Hook.ONMOUSELEAVE, function()
        if self.hoveredSlot == cell then self:HideTooltip() end
        return true
    end)
    -- The wheel goes on to whatever list this strip sits in.
    control.root:Subscribe(ui.Hook.ONSCROLLWHEEL, function(_, rotation)
        if self.onScroll then self:HideTooltip(); self.onScroll(rotation) end
        return false
    end)
    return cell
end

function Strip:ClearCells()
    self:HideTooltip()
    for _, cell in ipairs(self.slots) do cell.control:Destroy() end
    if self.cellsRoot then self.cellsRoot:Destroy() end
    self.cellsRoot, self.slots = nil, {}
end

function Strip:_newCell()
    if not self.cellsRoot then
        self.cellsRoot = Components.Host(self.root)
        self.cellsRoot.clickthrough = true
        self.cellsRoot:SetSize(0, 0, 1, 1)
    end
    local ok, result = pcall(createCell, self, self.cellsRoot)
    if not ok then
        self:ClearCells()
        error(result, 0)
    end
    self.slots[#self.slots + 1] = result
    return result
end

function Strip:_layoutCell(cell, index)
    local size = self.slotSize
    local cellX = self.slotLeft + (index - 1) * (self.cellWidth + self.gap)
    local x = cellX + math.floor((self.cellWidth - size) / 2)
    local y = self.targets and 0 or math.floor((HEIGHT - size - 4) / 2)
    local inset = math.min(math.max(1, math.floor(size / 10)), math.floor(size / 2))
    local inner = math.max(1, size - inset * 2)
    local control = cell.control
    place(control.root, x, y, size, size)
    if control.background.width ~= size or control.background.height ~= size then control.background:SetSize(size, size) end
    for _, component in ipairs({control.item or false, control.dragItem or false,
        control.disabledOverlay or false, cell.fallback}) do
        if component then
            place(component, inset, inset, inner, inner)
        end
    end
    if cell.tile then place(cell.tile, 0, math.floor((size - 20) / 2), size, 20) end
    if cell.quantityLabel then
        place(cell.quantityLabel, cellX, y + size + 2, self.cellWidth, TARGET_LABEL_HEIGHT)
        if cell.progress then
            local text = (cell.tracking.category == "Clues" or cell.tracking.category == "Unlocks" and cell.tracking.group == "Clues")
                and cell.tracking.ownedVar ~= nil and cell.progress.owned and "Owned"
                or cell.tracking.ownedVar ~= nil and cell.progress.ready and "Ready to<br>unlock"
                or Timers.isVar(cell.tracking.variable) and (Timers.format(cell.progress.current, cell.tracking.variable) .. "<br>/" .. Timers.format(cell.tracking.target, cell.tracking.variable))
                or cell.progress.locked and quantityText(cell.tracking.target)
                or quantityRatioText(cell.progress.current, cell.tracking.target, self.cellWidth, self.xp)
            if cell.quantityLabel.content ~= text then cell.quantityLabel.content = text end
        end
    end
    local statusY = y + size + (self.targets and TARGET_LABEL_HEIGHT + 4 or 2)
    place(cell.status, x, statusY, size, 2)
    local fraction = cell.progress and not cell.progress.complete and cell.progress.fraction or 0
    local width = math.floor(size * math.min(1, math.max(0, fraction)))
    cell.fill.hidden = width <= 0 or cell.tracking == nil
    place(cell.fill, x, statusY, math.max(1, width), 2)
end

function Strip:_refreshCell(cell, index)
    local itemIndex = self.first + index - 1
    local tracking = self.list[itemIndex]
    cell.tracking, cell.itemIndex = tracking, itemIndex
    cell.control.root.hidden, cell.status.hidden = tracking == nil, tracking == nil
    if not tracking then cell.fill.hidden = true end
    if cell.quantityLabel then cell.quantityLabel.hidden = not hasQuantityTarget(tracking) end
    if not tracking then return end
    local ref = iconRef(tracking)
    -- Daemonheim floors: the number is written on the tile.
    local tileText = Tracking.TileText(tracking)
    if tileText then
        cell.tile.content = tileText
        cell.tile.hidden = false
    elseif cell.tile then
        cell.tile.hidden = true
    end
    local signature = type(ref) == "table" and ("sprite:" .. tostring(ref.sprite)) or ("item:" .. tostring(ref))
    if cell.iconSignature ~= signature then
        cell.iconSignature = signature
        cell.fallback.hidden = true
        if type(ref) == "number" then
            cell.control:SetObject({id = ref}, 1)
        else
            cell.control:SetObject(nil)
            if type(ref) == "table" and ref.sprite ~= nil then
                cell.fallback.sprite = ref.sprite
                cell.fallback.hidden = false
            end
        end
    end
    local progress = read(tracking)
    cell.progress = progress
    local complete = progress.complete == true
    -- Bright when done (or on lists that drop finished entries), faded otherwise and always faded while locked.
    local bright = (complete or self.hideDone) and not progress.locked
    if cell.control.item then
        local quantity = math.max(1, math.floor(progress.current or 0))
        cell.control:SetQuantity(quantity)
        cell.control.item.alpha = bright and 1 or 0.35
    end
    cell.fallback.alpha = bright and 1 or 0.35
    cell.control.background.alpha = bright and 1 or 0.6
    cell.status.rgba = complete and 0x55FF55FF or 0xFFFFFF33
    self:_layoutCell(cell, index)
end

-- Lists that hide finished entries: rebuild what is shown, and re-fit the strip when its length changed.
function Strip:_filter()
    local shown = {}
    for _, item in ipairs(self.items) do
        if not (read(item).complete == true) then shown[#shown + 1] = item end
    end
    local changed = #shown ~= #self.list
    self.list = shown
    return changed
end

function Strip:Refresh(layoutOnly)
    if self.destroyed or self.active == false or not self.capacity then return end
    if not layoutOnly and self.hideDone and self:_filter() then
        local width = self.width
        self.width = nil
        self:SetBounds(self.root.x, self.root.y, width, true)
        return
    end
    for index = 1, math.min(#self.list, self.capacity) do
        local cell = self.slots[index] or self:_newCell()
        if layoutOnly and cell.tracking == self.list[self.first + index - 1] and cell.progress
            and not cell.control.root.hidden then self:_layoutCell(cell, index)
        else self:_refreshCell(cell, index) end
    end
    for index = math.min(#self.list, self.capacity) + 1, #self.slots do
        self.slots[index].control.root.hidden = true
        self.slots[index].status.hidden = true
        self.slots[index].fill.hidden = true
        if self.slots[index].quantityLabel then self.slots[index].quantityLabel.hidden = true end
    end
    self.previousButton:SetDisabled(self.first <= 1)
    self.nextButton:SetDisabled(self.first + self.capacity > #self.list)
    if self.hoveredSlot then self:ShowSlotTooltip(self.hoveredSlot) end
end

function Strip:SetVisible(visible)
    if self.destroyed then return end
    visible = visible == true
    self.root.hidden = not visible
    if self.active == visible then return end
    self.active = visible
    self:HideTooltip()
    if visible then self:Refresh(); return end
    ComponentTooltip.Destroy(self.sharedTooltip)
    self:ClearCells()
end

function Strip:SetBounds(x, y, width, refresh)
    if self.destroyed then return end
    width = math.max(1, math.floor(width))
    if self.root.x ~= x or self.root.y ~= y then self.root:SetPos(x, y) end
    if self.width == width then return end
    self:HideTooltip()
    self.width = width
    if self.root.width ~= width or self.root.height ~= self.height then self.root:SetSize(width, self.height) end
    if self.hideDone and not self.filtered then self.filtered = true; self:_filter() end
    local count = #self.list
    local cellWidth = self.xp and 96 or SLOT_SIZE
    local natural = count * cellWidth + math.max(0, count - 1) * GAP
    self.overflow = count > self.maxVisible or natural > width
    local navigation = self.overflow and width >= 24
    local buttonWidth = math.min(16, math.max(6, math.floor(width / 5)))
    local gap = math.min(GAP, math.max(1, math.floor(width / 20)))
    local side = navigation and buttonWidth + gap or 0
    local available = math.max(1, width - side * 2)
    self.cellWidth = math.min(cellWidth, available)
    self.slotSize = math.min(SLOT_SIZE, self.cellWidth)
    self.gap = gap
    self.capacity = math.max(1, math.min(self.maxVisible, count,
        math.floor((available + gap) / (self.cellWidth + gap))))
    local used = self.capacity * self.cellWidth + (self.capacity - 1) * gap
    self.slotLeft = side + math.max(0, math.floor((available - used) / 2))
    self.first = math.max(1, math.min(self.first, math.max(1, count - self.capacity + 1)))
    self.previousButton.root:SetPos(0, 10)
    self.previousButton.root:SetSize(buttonWidth, 24)
    self.nextButton.root:SetPos(width - buttonWidth, 10)
    self.nextButton.root:SetSize(buttonWidth, 24)
    self.previousButton.root.hidden, self.nextButton.root.hidden = not navigation, not navigation
    self:Refresh(not refresh)
end

function Strip:Tick()
    if self.destroyed then return end
    if self.root.hidden then self:HideTooltip() end
    local direction = self.pendingDirection
    self.pendingDirection = nil
    if not direction then return end
    self:HideTooltip()
    self.first = math.max(1, math.min(self.first + direction * self.capacity,
        math.max(1, #self.list - self.capacity + 1)))
    self:Refresh()
end

function Strip:Destroy(detached)
    if self.destroyed then return end
    self.destroyed = true
    self.hoveredSlot, self.pendingDirection = nil, nil
    if self.sharedTooltip then
        ComponentTooltip.Destroy(self.sharedTooltip, detached)
        if detached then Detached.Tooltip(self.sharedTooltip) end
        self.sharedTooltip:Destroy()
        self.sharedTooltip = nil
    end
    if detached then Detached.Tooltips(self.root) end
    for _, cell in ipairs(self.slots) do
        if detached then Detached.Control(cell.control) else cell.control:Destroy() end
    end
    for _, control in ipairs({self.previousButton, self.nextButton}) do
        if detached then Detached.Control(control) else control:Destroy() end
    end
    local context = self.tooltipContext
    local children = context and context.parentContext and context.parentContext.children
    for index = #(children or {}), 1, -1 do
        if children[index] == context then table.remove(children, index); break end
    end
    prettyui.Tooltip.unregisterContext(self.root)
    if not detached then self.root:Destroy() end
    self.cellsRoot = nil
    self.root, self.tooltipTarget, self.tooltipContext = nil, nil, nil
    self.previousButton, self.nextButton, self.slots, self.items, self.list = nil, nil, {}, {}, {}
end

return Strip
