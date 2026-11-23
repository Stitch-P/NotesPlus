local Notes = require("src/notes/notes")
local Tracking = require("src/tracking/model")
local Sprites = require("src/data/sprite_catalog")
local PopupPositioner = require("src/ui/notifications/achievement_popup_positioner")
local PopupPreview = require("src/ui/notifications/completion_popup_preview")
local Components = require("src/ui/shared/components")
local CollectionProgress = require("src/notes/collection_progress")

local Notifications = {}
Notifications.__index = Notifications

local POLL_INTERVAL = 0.6
local POPUP_WIDTH, POPUP_HEIGHT = 360, 92
local ICON_SIZE, ICON_GAP = 40, 8

local function plainText(value)
    return tostring(value or ""):gsub("<[^>]*>", ""):gsub("[<>%c]", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
end

local function noteTitle(note)
    local title = plainText(note and note.title)
    if title == "" and note and note.tracking then
        title = plainText(note.tracking.label or note.tracking.variable or note.tracking.skill)
    end
    return title ~= "" and title or "Tracked note"
end

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

function Notifications.new(options)
    return setmetatable({options = options or {}, baselines = {}, queue = {}, failures = {}}, Notifications)
end

function Notifications:_available()
    if self.stopped then return false end
    local settings = self.options.getSettings()
    return settings and settings.enabled ~= false and self.options.available() == true
end

function Notifications:_failure(kind, reason)
    reason = tostring(reason)
    if self.failures[kind] == reason then return end
    self.failures[kind] = reason
    if type(log) == "function" then log("Notes-Plus " .. kind .. " failed:", reason) end
end

function Notifications:_postChat(message)
    local ok, posted, reason = pcall(function()
        if not Plugin.HasPermission(PluginPermissions.chatAccess) then
            return false, "chatAccess permission is not enabled for Notes-Plus."
        end
        Chat.AddMessage(message)
        return true
    end)
    if ok and posted then self.failures.chat = nil; return true end
    self:_failure("chat", ok and reason or posted)
    return false
end

function Notifications:_chat(note)
    return self:_postChat("<col=00FF00>[Notes-Plus] Complete: " .. noteTitle(note) .. "</col>")
end

-- "<quest> is now ready to start!" for a tracked quest whose requirements have just been met.
function Notifications:_chatReady(info)
    local message = "<img=15> <col=83beff>" .. plainText(info.name) .. "</col> is now ready to start!"
    if info.start and info.start ~= "" then message = message .. " " .. plainText(info.start) end
    return self:_postChat(message)
end

function Notifications:_enqueue(note, signature, text, title)
    if #self.queue >= Notes.MAX_NOTES then table.remove(self.queue, 1) end
    self.queue[#self.queue + 1] = {note = note, signature = signature, text = text, title = title,
        period = note.notificationPeriod}
end

function Notifications:_progress(note, signature, progress, slots)
    local names = {}
    for index = 1, math.min(3, #slots) do
        local slot = slots[index]
        local label = plainText(slot.label)
        names[index] = label ~= "" and label or plainText(slot.key)
    end
    if #slots > #names then names[#names + 1] = "and " .. tostring(#slots - #names) .. " more" end
    local summary = table.concat(names, ", ") .. " complete!"
    local count
    if finite(progress.current) and finite(progress.target) and progress.target > 0 then
        local fraction = finite(progress.fraction) and progress.fraction or progress.current / progress.target
        count = tostring(math.floor(progress.current)) .. "/" .. tostring(math.floor(progress.target))
            .. " (" .. tostring(math.floor(math.max(0, math.min(1, fraction)) * 100)) .. "%)"
    end
    if note.notifyChat == true then
        self:_postChat("<col=00FF00>[Notes-Plus] " .. summary .. " " .. noteTitle(note)
            .. (count and ": " .. count or "") .. "</col>")
    end
    if note.notifyPopup == true then
        local popupSummary = #slots == 1 and summary or tostring(#slots) .. " entries complete!"
        self:_enqueue(note, signature, noteTitle(note) .. "<br>" .. popupSummary .. (count and "<br>" .. count or ""),
            "COLLECTION PROGRESS")
    end
end

function Notifications:_observeProgress(note, entry, signature, progress)
    local slots, ready, changed = CollectionProgress.Observe(note, entry, signature, progress.slots)
    if changed then self.completionSavePending = true end
    if #slots > 0 then entry.observed = true end
    if not entry.fired and progress.complete ~= true and #slots > 0 then self:_progress(note, signature, progress, slots) end
    return ready
end

function Notifications:_prepareRecurring(note, entry, signature, progress)
    if progress.statusOnly == true then return false end
    if progress.recurring ~= true then return true end
    local period = progress.period
    if type(period) ~= "string" or period == "" or #period > 120 or period:find("[%c]")
        or not finite(progress.current) or type(progress.complete) ~= "boolean" then return false end
    local changed = false
    if note.notificationPeriod ~= period or note.completedTracking == signature and not progress.complete then
        note.notificationPeriod, note.completedTracking, note.progressNotifications = period, nil, nil
        entry.fired, entry.observed, entry.slots = nil, nil, nil
        changed = true
    end
    local history = note.progressNotifications
    if history and history.signature == signature and type(progress.slots) == "table" then
        -- Reset flags can arrive separately, so each cleared entry must be eligible again.
        for _, slot in ipairs(progress.slots) do
            if slot.complete == false and history.completed[slot.key] then
                history.completed[slot.key], changed = nil, true
            end
        end
        if not next(history.completed) then note.progressNotifications = nil end
    end
    if changed then self.completionSavePending = true end
    return true
end

function Notifications:_valid(pending, alive)
    local note = pending.note
    if not note or note.notifyPopup ~= true or not note.tracking then return false end
    if alive then
        if not alive[note] then return false end
    else
        local found = false
        for _, candidate in ipairs(self.options.getData().notes) do
            if candidate == note then found = true; break end
        end
        if not found then return false end
    end
    return Notes.TrackingGoalSignature(note.tracking) == pending.signature
        and (pending.period == nil or pending.period == note.notificationPeriod)
end

function Notifications:_pruneQueue(alive)
    for index = #self.queue, 1, -1 do
        if not self:_valid(self.queue[index], alive) then table.remove(self.queue, index) end
    end
end

function Notifications:_dismissPopup(detached)
    local popup = self.popup
    local parent = self.popupParent
    self.popup, self.popupParent, self.activePending = nil, nil, nil
    if popup then
        if PopupPositioner.ParentDetached(parent, detached) then popup.root = nil end
        local ok, reason = pcall(function() popup:Destroy() end)
        if not ok then self:_failure("popup cleanup", reason) end
    end
end

function Notifications:_attachIcon(popup, note)
    if not note then return end
    local icon, attached
    local ok, reason = pcall(function()
        local choice = Sprites.Get(note.skill)
        local ref = not choice and note.tracking and Tracking.Icon(note.tracking)
        if not choice and not ref then return end
        icon = Components.New(ui.Sprite, popup.root)
        icon.clickthrough = true
        icon.rgba = 0xFFFFFFFF
        local size = type(ref) == "table" and math.min(ICON_SIZE, ref.size or ICON_SIZE) or ICON_SIZE
        if choice then
            if not Sprites.Apply(icon, note.skill) then return end
        elseif type(ref) == "table" then
            icon.sprite = ref.sprite
        else
            icon:SetAssociatedObject(ref)
            icon.associatedObjectQuantity = 1
            icon.associatedObjectQuantityMode = ui.ObjectQuantityDisplayMode.NEVER
        end
        local textY = popup.text.y
        icon:SetPos(10 + (ICON_SIZE - size) / 2, textY + (POPUP_HEIGHT - textY - 4 - size) / 2)
        icon:SetSize(size, size)
        local textLeft = 10 + ICON_SIZE + ICON_GAP
        popup.text:SetPos(textLeft, textY)
        popup.text:SetSize(-(textLeft + 10), -(textY + 4), 1.0, 1.0)
        if popup.flash then popup.flash:MoveToFront() end
        if popup.fadeVisuals then table.insert(popup.fadeVisuals, {component = icon, alpha = 1}) end
        popup.noteIcon, attached = icon, true
    end)
    if icon and not attached then pcall(function() icon:Destroy() end) end
    if not ok then self:_failure("popup icon", reason) end
end

function Notifications:_popupOptions(text, parent, x, y, onComplete, title)
    local settings = self.options.getSettings()
    return Components.Options({
        parent = parent,
        title = title or "NOTE COMPLETE",
        text = text,
        width = POPUP_WIDTH, height = POPUP_HEIGHT,
        x = x == nil and settings.achievementPopupX or x,
        y = y == nil and settings.achievementPopupY or y,
        xAnchor = 0.5,
        sound = false,
        onComplete = onComplete
    })
end

function Notifications:_createPopup(text, parent, x, y, onComplete, note, title)
    local popup = prettyui.AchievementPopup.show(self:_popupOptions(text, parent, x, y, onComplete, title))
    if popup then self:_attachIcon(popup, note) end
    return popup
end

function Notifications:_createPreview(text, parent, x, y, note)
    local preview = PopupPreview.new(self:_popupOptions(text, parent, x, y))
    self:_attachIcon(preview, note)
    return preview
end

function Notifications:_showNext()
    if not self:_available() or self.popup or self:IsPositioning() then return end
    local parent = self.options.getParent()
    if not parent then return end
    while not self.popup and #self.queue > 0 do
        local pending = table.remove(self.queue, 1)
        if self:_valid(pending) then
            local ok, popup = pcall(function()
                return self:_createPopup(pending.text or noteTitle(pending.note), parent, nil, nil, function(completed)
                    if self.popup == completed then
                        self.popup, self.popupParent, self.activePending = nil, nil, nil
                        self:_showNext()
                    end
                end, pending.note, pending.title)
            end)
            if ok and popup then
                self.popup, self.popupParent, self.activePending = popup, parent, pending
                self.failures.popup = nil
            elseif not ok then self:_failure("popup", popup) end
        end
    end
end

-- Tells the player when a tracked quest goes from "requirements not met" to "ready to start".
function Notifications:_pollReady(note, entry, signature)
    local ok, info = pcall(function() return require("src/tracking/features/quests").Quests.readiness(note.tracking.key) end)
    if not ok then self:_failure("quest readiness", info); return end
    if not info then return end
    local was = entry.ready
    entry.ready = info.ready
    if was == false and info.ready == true then
        if note.notifyChat == true then self:_chatReady(info) end
        if note.notifyPopup == true then
            self:_enqueue(note, signature, plainText(info.name) .. (info.start and ("<br>" .. plainText(info.start)) or ""),
                "READY TO START")
        end
    end
end

function Notifications:_poll()
    local notes = self.options.getData().notes
    local alive, baselines = {}, {}
    for _, note in ipairs(notes) do alive[note] = true end
    self:_pruneQueue(alive)
    for _, note in ipairs(notes) do
        if note.tracking and (note.notifyChat == true or note.notifyPopup == true or self.baselines[note]) then
            local signature = Notes.TrackingGoalSignature(note.tracking)
            local entry = self.baselines[note]
            if not entry or entry.signature ~= signature then entry = {signature = signature} end
            if note.completedTracking == signature then
                entry.fired = true
            elseif note.completedTracking ~= nil then
                note.completedTracking, self.completionSavePending = nil, true
            end
            baselines[note] = entry
            if (note.notifyChat == true or note.notifyPopup == true) and note.tracking.category == "Quests" and note.tracking.key
                and not note.tracking.items then
                self:_pollReady(note, entry, signature)
            end
            if note.notifyChat ~= true and note.notifyPopup ~= true then
                if not entry.fired then entry.observed = nil end
                entry.slots = nil
            else
                local ok, progress = pcall(Tracking.Read, note.tracking,
                    not entry.fired or note.tracking.category == "Scheduled")
                local prepared = ok and progress and self:_prepareRecurring(note, entry, signature, progress)
                local ready = prepared and self:_observeProgress(note, entry, signature, progress)
                if prepared and finite(progress.current) then
                    local complete = progress.complete == true
                    if complete and note.completedTracking ~= signature then
                        note.completedTracking, self.completionSavePending = signature, true
                    end
                    if not entry.observed then
                        if ready then entry.observed, entry.fired = true, entry.fired or complete end
                    elseif not entry.fired and complete then
                        entry.fired = true
                        if note.notifyChat == true then self:_chat(note) end
                        if note.notifyPopup == true then
                            self:_enqueue(note, signature)
                        end
                    end
                elseif not ok then self:_failure("tracking notification read", progress) end
            end
        end
    end
    self.baselines = baselines
    if self.completionSavePending and self.options.onCompletionStateChanged then
        local ok, saved, reason = pcall(self.options.onCompletionStateChanged)
        if ok and saved == true then
            self.completionSavePending = nil
            self.failures["completion state save"] = nil
        else self:_failure("completion state save", ok and reason or saved) end
    end
end

function Notifications:IsPositioning()
    return self.positioner ~= nil and self.positioner:IsActive()
end

function Notifications:StartPositioning(draft)
    if not self:_available() or self:IsPositioning() or not self.options.getParent() then return false end
    self.previewTitle = draft and noteTitle(draft) or "Your completed note will appear here."
    self.previewNote = draft
    if not self.positioner then
        self.positioner = PopupPositioner.new({
            width = POPUP_WIDTH, height = POPUP_HEIGHT,
            getParent = self.options.getParent,
            getPosition = function()
                local settings = self.options.getSettings()
                return settings.achievementPopupX, settings.achievementPopupY
            end,
            canStart = function() return self:_available() end,
            beforeStart = function()
                local pending = self.activePending
                self:_dismissPopup()
                if pending and self:_valid(pending) then table.insert(self.queue, 1, pending) end
            end,
            createPreview = function(x, y, parent)
                return self:_createPreview(self.previewTitle, parent, x, y, self.previewNote)
            end,
            commitPosition = function(x, y) self.options.onPosition(x, y) end,
            afterFinish = function() self:_showNext() end,
            afterCancel = function() self:_showNext() end
        })
    end
    local ok, started = pcall(function() return self.positioner:Start() end)
    if not ok then self:_failure("popup positioning", started); return false end
    return started
end

function Notifications:Refresh(elapsed)
    self.nextPoll = nil
    self:Tick(elapsed)
end

function Notifications:Tick(elapsed)
    if self.stopped then return end
    if not self:_available() then self:Reset(); return end
    if self.popup and PopupPositioner.ParentDetached(self.popupParent) then
        local pending = self.activePending
        self:_dismissPopup(true)
        if pending and self:_valid(pending) then table.insert(self.queue, 1, pending) end
    end
    if self.positioner and self.positioner:Sync() == false then self.positioner = nil end
    if not self.nextPoll or elapsed >= self.nextPoll then
        self.nextPoll = elapsed + POLL_INTERVAL
        self:_poll()
    end
    if self.activePending and not self:_valid(self.activePending) then self:_dismissPopup() end
    self:_showNext()
end

function Notifications:Reset(detached)
    self.baselines, self.queue, self.nextPoll = {}, {}, nil
    self:_dismissPopup(detached)
    if self.positioner then self.positioner:Destroy(detached); self.positioner = nil end
    self.previewTitle, self.previewNote = nil, nil
end

function Notifications:Stop(detached)
    if self.stopped then return end
    self.stopped = true
    self:Reset(detached)
end

return Notifications
