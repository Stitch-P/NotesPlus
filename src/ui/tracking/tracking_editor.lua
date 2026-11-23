local Components = require("src/ui/shared/components")
local Tracking = require("src/tracking/model")
local Randomizer = require("src/tracking/randomizer")
local WindowStyle = require("src/ui/window/window_style")
local Detached = require("src/ui/shared/detached_ui")
local DropdownLayout = require("src/ui/shared/dropdown_layout")
local DropdownFilter = require("src/ui/shared/dropdown_filter")
local CollectionPicker = require("src/ui/tracking/tracking_item_picker")
local ModelScene = require("src/ui/tracking/model_scene")

local Editor = {}
Editor.__index = Editor

local TEXT = 0xE7D7B0FF
local MUTED = 0xB7B1A7FF
local GOLD = 0xF2C66DFF
local FORM_HEIGHT = 502
local RANDOM_PENDING = "Wait for the random goal to finish, or change a tracking selection to cancel it."

local function safeText(value)
    return tostring(value or ""):gsub("<[Bb][Rr]%s*/?>", " "):gsub("<", "["):gsub(">", "]")
end

-- The option description under the dropdowns is a single line of text: line breaks become spaces.
local function oneLine(value)
    return (tostring(value or ""):gsub("[\r\n]+", " "))
end

-- What the empty target box says a blank target means for this goal.
local function targetPlaceholder(category, option)
    if not option then return "Target" end
    if option.kind == "kills" then return "Next kill" end
    if option.kind == "record" then return option.max and ("Up to " .. option.max) or "Next best" end
    if option.kind == "timer" then return "1 tick faster" end
    if option.kind == "item" and (category == "Bossing" or category == "Clues") then return "1 lifetime drop" end
    return "Target"
end

local function entries(values, label)
    local result = {}
    for index, value in ipairs(values) do
        -- A title's label keeps the game's colours: its markup was made safe where it was read.
        result[index] = {id = index, label = type(value) == "table" and value.markup or safeText(label(value)), order = index}
    end
    return result
end

local function matchingIndex(values, selected)
    for index, value in ipairs(values) do
        if value == selected or (type(value) == "table" and type(selected) == "table"
            and (value.key ~= nil and value.key == selected.key
                or value.key == nil and selected.key == nil and value.name ~= nil and value.name == selected.name)) then return index end
    end
    return 1
end

function Editor:Track(control)
    self.controls[#self.controls + 1] = control
    return control
end

function Editor:Label(value, x, y, width, height, colour)
    local label = prettyui.Text.new(self.content, Components.Options({text = safeText(value), x = x, y = y,
        width = width, height = height, colour = colour or TEXT,
        font = id.Font.MUSEO_SANS_13PT_REGULAR, shadowed = true, maxLines = 0}))
    label.clickthrough = true
    return label
end

function Editor:Queue(action, selection, unchanged)
    if self.destroyed then return end
    self:CancelRandomGoal()
    if self.built and not unchanged then self.dirty = true end
    if not selection then self:FlushSelection() end
    self.pending, self.pendingSelection = action, selection == true
    self.randomQueued = unchanged == true
    self.pendingTargetText = selection and self.target and self.target:GetText() or nil
end

function Editor:UpdateRandomButton()
    if not self.randomButton then return end
    local supported = Randomizer.Supports(self.category)
    self.randomButton:SetDisabled(not supported or self.randomJob ~= nil)
    self.randomButton:SetTooltip(supported and (self.randomJob and "Finding a random goal..."
        or "Prepare a random goal for this type.") or nil)
    WindowStyle.ApplyTooltip(self.randomButton.tooltip)
end

function Editor:CancelRandomGoal()
    if not self.randomJob and not self.randomQueued then return end
    if self.randomQueued then self.pending, self.randomQueued = nil, nil end
    self.randomJob = nil
    if self.message and (self.message.content == "Finding a random goal..." or self.message.content == RANDOM_PENDING) then
        self.message.content = ""
        self.message.hidden = true
    end
    self:UpdateRandomButton()
end

function Editor:StartRandomGoal()
    if self.destroyed or not self.randomButton or not Randomizer.Supports(self.category) then return end
    local existing = self.callbacks.existingTrackings and self.callbacks.existingTrackings() or {}
    self.randomJob = Randomizer.New(self.category, existing, self.randomHistory, self.group and self.group.name)
    self:UpdateRandomButton()
    self:ShowMessage("Finding a random goal...")
end

function Editor:PrepareRandomGoal(result)
    if self.destroyed or result.category ~= self.category then return end
    local groupName = result.group and result.group.name
    local sub = result.group and result.group.sub
    local groupChanged = groupName ~= (self.group and self.group.name) or sub ~= (self.group and self.group.sub)
    if groupChanged then
        local groupIndex
        for index, group in ipairs(self.groups) do
            if group.name == groupName then groupIndex = index break end
        end
        if not groupIndex then self:ShowMessage("Choose this type again to refresh its goals."); return end
        self.group = self.groups[groupIndex]
        if self.group.subs then
            local subIndex
            for index, entry in ipairs(self.group.subs) do
                if entry.name == sub then subIndex = index break end
            end
            if not subIndex then self:ShowMessage("Choose this type again to refresh its goals."); return end
            self.group = self:WithSub(self.group, subIndex)
        end
        self.groupCombo:Select(groupIndex, false)
        self:LoadOptions(result.option, result.targetText)
    elseif not self.componentMode then
        self.optionCombo:Select(matchingIndex(self.options, result.option), false)
        self:UpdateOption(false, true)
        self.target:SetText(result.targetText, false)
    end
    if self.componentPicker then
        local key = result.option.key or result.option.skill
        self.componentPicker:SetSelected({[key] = true})
        self.componentPicker:SetTargets({[key] = result.targetText})
        self.target:SetText("", false)
        self:UpdateComponents()
    else self:UpdateCurrent() end
    self.dirty = true
    self.lastTargetText = self.target:GetText()
    self.randomHistory = self.randomHistory or {}
    self.randomHistory[#self.randomHistory + 1] = result.identity
    if #self.randomHistory > 4 then table.remove(self.randomHistory, 1) end
    self:NotifyTitle()
    self:ShowMessage("")
end

function Editor:TickRandomGoal()
    local job = self.randomJob
    if not job then return end
    local result, done, message = job:Step()
    if self.destroyed or self.randomJob ~= job then return end
    if not done then return end
    self.randomJob = nil
    self:UpdateRandomButton()
    if result then self:PrepareRandomGoal(result)
    else self:ShowMessage(message or "No suitable random goal is available for this type.") end
end

function Editor:FlushSelection()
    if self.componentPicker then self.componentPicker:FlushSelection() end
    if not self.pendingSelection then return end
    local pending = self.pending
    local text = self.target and self.target:GetText()
    local editedTarget = text ~= self.pendingTargetText
    self.pending, self.pendingSelection, self.pendingTargetText = nil, false, nil
    if pending then pending() end
    if editedTarget and not self.destroyed then self.target:SetText(text or "", false) end
    if not self.destroyed then
        self:NotifyTitle()
    end
end

function Editor:FlushPending()
    if self.destroyed then return end
    self:FlushSelection()
    if self.destroyed then return end
    local pending = self.pending
    self.pending, self.randomQueued = nil, nil
    if pending then pending() end
end

function Editor:CollectionTargets()
    local targets, filled = self.componentPicker:GetTargets(), false
    local text = self.target:GetText()
    if Tracking.IsSkillLevels(self.category, self.group) and text:match("%S") then
        for _, option in ipairs(self.componentPicker:GetSelected()) do
            local key = option.key or option.skill
            if not tostring(targets[key] or ""):match("%S") then
                targets[key], filled = text, true
            end
        end
    end
    return targets, filled
end

function Editor:CurrentTitle()
    if self.componentMode then
        return Tracking.CollectionTitle(self.category, self.group, self.componentPicker:GetSelected(), self:CollectionTargets())
    end
    return Tracking.Title(self.category, self.group, self:SelectedOption(), self.target:GetText())
end

function Editor:NotifyTitle()
    local title = self:CurrentTitle()
    if not title then return end
    local previous = self.selectionTitle
    self.selectionTitle = title
    if self.callbacks.selectionChanged then self.callbacks.selectionChanged(title, previous) end
end

function Editor:UpdateComponents(selected, notify)
    selected = selected or self.componentPicker:GetSelected()
    self.componentKeys = {}
    for _, option in ipairs(selected) do
        self.componentKeys[option.key or option.varName or option.currency and option.currency.var or option.variable] = true
    end
    local singular, plural = self:CollectionNames()
    self.current.content = self.tabbed and (tostring(#selected) .. " selected")
        or tostring(#selected) .. " " .. (#selected == 1 and singular or plural) .. " selected"
    if self.setAllButton then self.setAllButton:SetDisabled(#selected == 0) end
    if notify then self:NotifyTitle() end
end

function Editor:CollectionNames()
    return Tracking.CollectionNames(self.category, self.group)
end

-- Bossing and Slayer both list ordinary options plus a "Collection items" picker for the drops.
local function mixedCollection(category)
    return category == "Bossing" or category == "Slayer"
end

local function collectionScope(category, group)
    return tostring(category) .. ":" .. tostring(group and group.name or "") .. (group and group.sub and ("/" .. group.sub) or "")
end

function Editor:RememberCollection()
    if not self.componentPicker then return end
    self:UpdateComponents(self.componentPicker:GetSelected())
    self.collectionDrafts[self.collectionScope] = {keys = self.componentKeys, targetText = self.target:GetText(),
        targets = self.componentPicker:GetTargets()}
end

function Editor:ReleaseCollection()
    if not self.componentPicker then return end
    self:RememberCollection()
    self.componentPicker:Destroy()
    self.componentPicker, self.petPreviewOption = nil, nil
end

function Editor:InitializeCollections(category, group, snapshot)
    self.collectionDrafts = snapshot and snapshot.collectionDrafts or {}
    local scope = collectionScope(category, group)
    if self.collectionDrafts[scope] == nil then
        local keys, targetText, targets = Tracking.CollectionSelection(self.previous)
        if Tracking.IsSkillLevels(category, group) then targetText = "" end
        if next(keys) then self.collectionDrafts[scope] = {keys = keys, targetText = targetText, targets = targets} end
    end
end

function Editor:UpdateCollectionMode()
    local option = self.options[self.optionCombo:GetSelectedID()]
    local enabled = Tracking.IsCollection(self.category, self.group)
        and (not mixedCollection(self.category) or option and option.kind == "collection")
    if not enabled then self:ReleaseCollection() end
    self.componentMode = enabled == true
    self.description.hidden = self.componentMode
    self.singleOption = Tracking.IsSingleOption(self.category, self.group)
    local hideOptions = Tracking.IsCollection(self.category, self.group) and not mixedCollection(self.category) or self.singleOption
    self:SetControlHidden(self.optionCombo, hideOptions)
    local singular, plural = self:CollectionNames()
    self.trackLabel.content = hideOptions and not self.singleOption and ("Select " .. plural) or "Track"
    if self.componentMode and not self.componentPicker then
        self.collectionScope = collectionScope(self.category, self.group)
        local draft = self.collectionDrafts[self.collectionScope] or {}
        self.componentKeys = draft.keys or {}
        self.componentTargetText = draft.targetText or Tracking.CollectionDefaultTarget(self.category, self.group)
        local options = Tracking.CollectionOptions(self.category, self.group, true)
        local petGroup = Tracking.IsPetGroup(self.category, self.group)
        self.componentPicker = CollectionPicker.new(self.content, options, self.componentKeys, {
            changed = function(selected, touchedKey)
                if self.destroyed or not self.componentMode then return end
                self:CancelRandomGoal()
                if self.built then self.dirty = true end
                if petGroup then
                    for _, option in ipairs(options) do
                        if option.key == touchedKey then self.petPreviewOption = option; break end
                    end
                    self:UpdatePreview()
                end
                self:UpdateComponents(selected, true)
                self:ShowMessage("")
            end,
            targetChanged = function()
                if self.destroyed or not self.componentMode then return end
                self:CancelRandomGoal()
                if self.built then self.dirty = true end
                self:NotifyTitle()
                if self.message.content ~= "" then self:ShowMessage("") end
            end,
            focus = function(control) self:Focus(control) end,
            limit = function(maximum) self:ShowMessage("Select up to " .. maximum .. " " .. plural .. " per note.") end
        }, {width = math.max(1, self.width - 16), maxSelected = Tracking.MAX_COLLECTION_ITEMS,
            category = self.category, group = self.group, noun = plural, nounSingular = singular,
            targets = draft.targets, defaultTarget = Tracking.IsSkillLevels(self.category, self.group) and "" or self.componentTargetText,
            showStatus = not self.tabbed})
        if petGroup then self.petPreviewOption = self.componentPicker:GetSelected()[1] end
    end
    self.canBulk = (self.tabbed or mixedCollection(self.category)) and self.componentMode and #Tracking.CollectionOptions(self.category, self.group) > 0
        or self.category == "Combat" and self.group ~= nil
    self:SetControlHidden(self.bulkButton, not self.canBulk)
    if self.clearButton then self:SetControlHidden(self.clearButton, not self.componentMode) end
    if self.canBulk then
        self.bulkButton.content.content = self.componentMode and (self.tabbed and "Select all" or "Select all items") or "Add all achievements"
        self.bulkButton:SetTooltip(nil)
    end
end

function Editor:Focus(control)
    if self.callbacks.focus then self.callbacks.focus(control) end
end

function Editor:Combo(y, values, label, selected, changed)
    local choices = entries(values, label)
    if #choices == 0 then choices = {{id = 1, label = "(none)", order = 1}} end
    local combo = self:Track(prettyui.ComboBox.new(self.content, Components.Options({
        x = 12, y = y, width = self.width - 24, height = 30,
        entries = choices, selectedID = selected,
        maxVisibleEntries = #choices,
        onChange = function(_, index)
            self:Queue(function() changed(index) end, true)
        end
    })))
    DropdownFilter.Batch(combo)
    DropdownLayout.FitToWindow(combo)
    combo.root:Subscribe(ui.Hook.ONCLICK, function()
        self:Focus(combo)
        return true
    end)
    return combo
end

function Editor:Button(value, x, y, width, action)
    return self:Track(prettyui.SimpleButton.new(self.content, value, function()
        self:Queue(action)
    end, Components.Options({x = x, y = y, width = width, height = 28})))
end

function Editor:ShowMessage(value)
    self.message.content = safeText(value)
    self:Layout()
end

function Editor:SelectedOption()
    if self.componentMode then return nil end
    return self.options[self.optionCombo:GetSelectedID()]
end

function Editor:UpdateCurrent()
    local option = self:SelectedOption()
    self.current.content = option and safeText(Tracking.Preview(self.category, self.group, option, self.target:GetText()).text) or ""
    self.previewTargetText = option and option.userTarget and self.target:GetText() or nil
end

function Editor:UpdateOption(prefill, deferLayout)
    self:UpdateCollectionMode()
    self.hideTarget = false
    if self.componentMode then
        self.fixedCollectionTarget = Tracking.CollectionFixedTarget(self.category, self.group)
        if prefill then self.target:SetText(self.fixedCollectionTarget and tostring(self.fixedCollectionTarget)
            or self.componentTargetText or Tracking.CollectionDefaultTarget(self.category, self.group), false) end
        local available = #Tracking.CollectionOptions(self.category, self.group) > 0
        self.target:SetDisabled(not available or self.fixedCollectionTarget ~= nil)
        self.target:SetPlaceholder("Target")
        self:SetControlHidden(self.target, self.fixedCollectionTarget ~= nil)
        self:SetControlHidden(self.setAllButton, self.fixedCollectionTarget ~= nil)
        self.targetLabel.hidden = self.fixedCollectionTarget ~= nil
        local singular = self:CollectionNames()
        local xp = Tracking.IsSkillXP(self.category, self.group)
        self.targetLabel.content = xp and (self.tabbed and "Set selected XP" or "Set all selected XP to")
            or Tracking.IsSkillLevels(self.category, self.group) and (self.tabbed and "Set selected levels" or "Set all selected levels to")
            or self.tabbed and "Set selected targets" or "Set all selected targets to"
        self.hint.content = not available and "Completion tracking is not available for these items yet."
            or self.fixedCollectionTarget and (singular == "building" and "Each selected building is tracked to its next tier."
                or singular == "breed" and "Each selected breed is complete once it is in your log."
                or singular == "artefact" and "Each selected artefact is complete once it is in its collection."
                or singular == "research unlock" and "Each selected research entry is complete when unlocked."
                or singular == "achievement" and "Each selected achievement is complete once the game marks it done."
                or singular == "pet" and "Each selected pet is complete once you have it."
                or singular == "engram" and "Each selected engram is complete once it is handed in."
                or singular == "passive effect" and "Each selected passive effect counts while it is active; active ones are lit on the note."
                or singular == "floor" and "Each selected floor is complete once you have completed it."
                or ("Each selected " .. singular .. " is complete once it is unlocked."))
            or xp and "Enter total XP for each skill, or use Set all. XP you already have counts toward the target."
            or Tracking.IsSkillLevels(self.category, self.group) and "Enter individual levels, or use the level above for blank targets: 1-120, or 1-150 for Invention."
            or (self.category == "Clues" or self.category == "Unlocks" and self.group.name == "Clues") and (self.group.name == "Reward shop" or self.group.name == "Clues"
                and "Leave targets blank to use each reward's shop cost. Owning a reward completes its goal."
                or "Leave targets blank to count one lifetime drop. Enter a number to count new drops from now")
            or Tracking.CollectionHint(self.category, self.group)
            or ("Edit the target below each selected " .. singular .. ", or use Set all.")
        self.description.content = ""
        self:UpdateComponents()
        self.message.content = ""
        self:UpdatePreview()
        if not deferLayout then self:Layout() end
        return
    end
    self.fixedCollectionTarget = nil
    self:SetControlHidden(self.setAllButton, true)
    local option = self:SelectedOption()
    local fixed, fixedValue = Tracking.TargetPolicy(self.category, option)
    local single = fixed and not (option.savedTracking and option.savedTracking.items) and (fixedValue == nil or fixedValue == 1)
    self.hideTarget = option ~= nil and (option.statusOnly == true or option.dynamicTarget == true or single == true)
    self:SetControlHidden(self.target, self.hideTarget)
    self.targetLabel.hidden = self.hideTarget
    local category, group = self.category, self.group
    if prefill then
        self.target:SetText(option and Tracking.DefaultTarget(category, group, option) or "", false)
    end
    local collection = option and option.savedTracking and option.savedTracking.items
    local fixedTarget = Tracking.TargetPolicy(category, option)
    self.target:SetDisabled(fixedTarget or option == nil)
    self.target:SetPlaceholder(targetPlaceholder(category, option))
    self.targetLabel.content = collection and "Items to collect" or Tracking.IsSkillLevels(category, group) and "Target level" or "Target value"
    self.hint.content = option and safeText(Tracking.Hint(category, group, option)) or "All tracking entries in this selection are complete."
    self:UpdateCurrent()
    self.description.content = option and safeText(oneLine(option.description)) or ""
    self.optionCombo:SetTooltip(option and option.description or nil)
    WindowStyle.ApplyTooltip(self.optionCombo.tooltip)
    self.message.content = ""
    self:UpdatePreview()
    if not deferLayout then self:Layout() end
end

function Editor:UpdatePreview()
    self.iconRevision = Tracking.IconRevision and Tracking.IconRevision() or 0
    if self.preview then self.preview:Destroy(); self.preview = nil end
    local petPreview = self.componentMode and Tracking.IsPetGroup(self.category, self.group)
    local option = petPreview and self.petPreviewOption or self:SelectedOption()
    local bossPreview = not self.componentMode and (self.category == "Bossing" or self.category == "Combat")
    if bossPreview or petPreview then
        local reference = Tracking.PreviewModel(self.category, self.group, option)
        if petPreview and not option then
            for _, candidate in ipairs(self.componentPicker.options) do
                reference = Tracking.PreviewModel(self.category, self.group, candidate)
                if reference then option = candidate; break end
            end
        end
        self.modelShown = false
        self.description.content = option and safeText(oneLine(petPreview and option.label or option.description)) or ""
        if reference then
            if not self.modelPreview then self.modelPreview = ModelScene.new(self.content) end
            self.modelShown = self.modelPreview:Apply(reference) == true
        end
        if self.modelPreview then self.modelPreview:SetHidden(not self.modelShown) end
        if petPreview then self.description.hidden = not self.modelShown
        elseif not self.modelShown and self.description.content == "" then
            self.description.content = "Boss model is not available."
        end
        if self.clipScrollY ~= nil then self:Clip(self.clipScrollY, self.clipViewportHeight) end
        return
    end
    self.modelShown = false
    if self.modelPreview then self.modelPreview:Hide() end
    if self.tabbed and self.componentMode then return end
    local ref
    if option then ref = Tracking.Icon(option)
    elseif self.componentMode then
        -- A Production / Gathering group (nothing picked yet) previews with its skill's icon.
        local okGroup, groupRef = pcall(Tracking.GroupIcon, self.category, self.group)
        if okGroup then ref = groupRef end
    end
    if not ref then return end
    local size = type(ref) == "table" and math.min(32, ref.size or 32) or 32
    local sprite = Components.New(ui.Sprite, self.content)
    sprite:SetPos((self.inline and 8 or 12) + (32 - size) / 2, (self.previewY or 218) + (32 - size) / 2)
    sprite:SetSize(size, size)
    sprite.clickthrough = true
    sprite.rgba = 0xFFFFFFFF
    if type(ref) == "table" then
        sprite.sprite = ref.sprite
    else
        sprite:SetAssociatedObject(ref)
        sprite.associatedObjectQuantityMode = ui.ObjectQuantityDisplayMode.NEVER
    end
    self.preview = sprite
end

function Editor:LoadOptions(selected, targetText)
    self:CancelRandomGoal()
    self:LoadSubs()
    self:ReleaseCollection()
    self.componentMode = false
    self.options = Tracking.Options(self.category, self.group)
    if mixedCollection(self.category) then
        -- Some lists are only offered as the collection (the Slayer Codex's souls), not one by one as well.
        local pickerLabel, collectionOnly = Tracking.CollectionPickerLabel(self.category, self.group)
        local ordinary = {}
        for _, option in ipairs(self.options) do
            if option.kind ~= "item" and not (option.savedTracking and option.savedTracking.items)
                and not (collectionOnly and option.kind == "cheevo") then
                ordinary[#ordinary + 1] = option
            end
        end
        if self.group and #Tracking.CollectionOptions(self.category, self.group, true) > 0 then
            local collection = {kind = "collection", key = "boss-items:" .. self.group.name, label = pickerLabel}
            ordinary[#ordinary + 1] = collection
            if selected and (selected.kind == "item" or selected.savedTracking and selected.savedTracking.items
                or collectionOnly and selected.kind == "cheevo") then selected = collection end
        end
        self.options = ordinary
    end
    local hideOptions = Tracking.IsCollection(self.category, self.group) and not mixedCollection(self.category)
    self.optionCombo:SetEntries(hideOptions and {} or entries(self.options, function(option) return option.label end),
        matchingIndex(self.options, selected))
    self.optionCombo:SetDisabled(hideOptions or #self.options == 0)
    self:UpdateOption(true, true)
    if targetText ~= nil and not self.componentMode then self.target:SetText(targetText, false) end
    if not self.componentMode and self:SelectedOption() and self:SelectedOption().userTarget then self:UpdateCurrent() end
    self:UpdateRandomButton()
    self:Layout()
end

function Editor:LoadCategory(category, selectedGroup, selectedOption, targetText)
    self:CancelRandomGoal()
    self.category = category
    self:UpdateRandomButton()
    self.groups = Tracking.Groups(category)
    local groupIndex = matchingIndex(self.groups, selectedGroup)
    self.group = self.groups[groupIndex]
    if self.group and self.group.subs then
        local sub = type(selectedGroup) == "table" and selectedGroup.sub
        local subIndex = 1
        for index, entry in ipairs(self.group.subs) do if entry.name == sub then subIndex = index end end
        self.group = self:WithSub(self.group, subIndex)
    end
    self.groupCombo:SetEntries(entries(self.groups, function(group) return group.label or group.name end), groupIndex)
    local hasGroups = #self.groups > 0
    self.hasGroups = hasGroups
    self:SetControlHidden(self.groupCombo, not hasGroups)
    self.groupLabel.hidden = not hasGroups
    self.groupLabel.content = category == "Skills" and "Track" or (category == "Clues" or category == "Ports") and "Section" or category == "Tasks" and "Area" or category == "Quests" and "Series" or (category == "Invention" or category == "Gathering") and "Sub-type" or category == "Production" and "Skill" or category == "Training" and "Type" or category == "Unlocks" and "Category" or category == "Scheduled" and "Frequency" or category == "Slayer" and "Area" or "Boss"
    self:LoadOptions(selectedOption, targetText)
end

-- A group with its third-level choice picked (the farm's animals): a copy that carries the choice as `sub`.
function Editor:WithSub(group, index)
    local entry = group.subs and group.subs[index]
    return {name = group.name, key = group.key, label = group.label, subs = group.subs, subLabel = group.subLabel, sub = entry and entry.name}
end

-- Fills the third dropdown for a group that has choices, hides it otherwise.
function Editor:LoadSubs()
    local subs = self.group and self.group.subs
    self.hasSubs = subs ~= nil and #subs > 0
    self:SetControlHidden(self.subCombo, not self.hasSubs)
    self.subLabel.hidden = not self.hasSubs
    if not self.hasSubs then return end
    self.subLabel.content = self.group.subLabel or "Section"
    local current = 1
    for index, entry in ipairs(subs) do if entry.name == self.group.sub then current = index end end
    self.subCombo:SetEntries(entries(subs, function(entry) return entry.name end), current)
end

function Editor:Commit()
    self:FlushSelection()
    if self.destroyed then return nil, "Tracking is no longer open." end
    if self.randomJob or self.randomQueued then
        self:ShowMessage(RANDOM_PENDING)
        return nil, RANDOM_PENDING
    end
    local tracking, title, targets, filledTargets
    if self.componentMode then
        targets, filledTargets = self:CollectionTargets()
        tracking, title = Tracking.BuildCollection(self.category, self.group, self.componentPicker:GetSelected(), targets, self.previous)
    else
        local option = self:SelectedOption()
        if not option then self:ShowMessage("Choose what to track."); return nil, "Choose what to track." end
        tracking, title = Tracking.Build(self.category, self.group, option, self.target:GetText(), self.previous)
    end
    if not tracking then self:ShowMessage(title); return nil, title end
    if self.callbacks.apply then
        local ok, message = self.callbacks.apply(tracking, title, self.selectionTitle)
        if ok == false or message ~= nil then
            message = message or "Unable to apply tracking."
            self:ShowMessage(message)
            return nil, message
        end
    end
    if filledTargets then self.componentPicker:SetTargets(targets) end
    self.selectionTitle = title
    self.committedTitle = title
    self.previous = Tracking.Normalize(tracking)
    self.dirty = false
    return true
end

function Editor:SetAllTargets()
    if not self.componentMode or not self.componentPicker then return end
    local selected = self.componentPicker:GetSelected()
    if #selected == 0 then return end
    local text, targets = self.target:GetText(), self.componentPicker:GetTargets()
    for _, option in ipairs(selected) do
        if Tracking.CollectionTargetEditable(self.category, self.group, option) then
            targets[option.key or option.varName or option.skill] = text
        end
    end
    local tracking, message = Tracking.BuildCollection(self.category, self.group, selected, targets, self.previous)
    if not tracking then self:ShowMessage(message); return end
    self.componentPicker:SetAllTargets(text)
    self:UpdateComponents(selected, true)
    self:ShowMessage("")
end

function Editor:BatchTargetChanged()
    if self.built and not self.componentMode then
        local option = self:SelectedOption()
        if option and option.userTarget and self.target:GetText() ~= self.previewTargetText then
            self:UpdateCurrent()
            self:Layout()
        end
    end
    if self.built and self.componentMode and self.componentPicker then
        self.componentPicker:SetDefaultTarget(Tracking.IsSkillLevels(self.category, self.group) and "" or self.target:GetText())
        if Tracking.IsSkillLevels(self.category, self.group) then
            self:NotifyTitle()
            if self.message.content ~= "" then self:ShowMessage("") end
        end
    end
end

function Editor:Apply()
    if not self:Commit() then return end
    if not self.tabbed then self:Destroy() end
end

function Editor:Cancel()
    if self.destroyed then return end
    if self.selectionTitle and self.callbacks.selectionChanged then
        self.callbacks.selectionChanged(self.committedTitle or "", self.selectionTitle)
    end
    self:Destroy()
end

function Editor:AddAll()
    if self.componentMode and (self.tabbed or mixedCollection(self.category)) then
        self.componentPicker:SetSelected(Tracking.CollectionOptions(self.category, self.group))
        self:UpdateComponents(self.componentPicker:GetSelected(), true)
        self:ShowMessage("")
        return
    end
    if not self.callbacks.addAll then return end
    local existing = self.callbacks.existingTrackings and self.callbacks.existingTrackings() or {}
    local records, skipped = Tracking.Bulk(self.category, self.group, existing)
    if #records == 0 then
        self:ShowMessage(skipped and skipped > 0 and ("Already added (" .. skipped .. " skipped).")
            or "There are no items to add for this selection.")
        return
    end
    local ok, message = self.callbacks.addAll(records, self.category)
    if ok == false or message ~= nil then self:ShowMessage(message or "Unable to add notes."); return end
    self:ShowMessage("Added " .. #records .. (#records == 1 and " note" or " notes")
        .. (skipped and skipped > 0 and (" (" .. skipped .. " skipped).") or "."))
end

function Editor:SetControlHidden(control, hidden)
    if self.inline then
        self.logicalHidden = self.logicalHidden or {}
        self.logicalHidden[control] = hidden == true
    end
    control.root.hidden = hidden == true
end

local function measuredHeight(value, width, minimum)
    if value == "" then return minimum or 0 end
    local ok, height = pcall(function()
        local font = config.Font.FromID(id.Font.MUSEO_SANS_13PT_REGULAR)
        return font:GetStringHeightAndLineCount(value, math.max(1, width), font.baseline, false, false, false)
    end)
    if not ok or type(height) ~= "number" then
        height = math.max(1, math.ceil(#value * 7 / math.max(1, width))) * 18
    end
    return math.max(minimum or 0, math.ceil(height))
end

function Editor:LayoutSelectorRow(width, y, place)
    local fields = {{label = self.typeLabel, control = self.categoryCombo}}
    if self.hasGroups then fields[#fields + 1] = {label = self.groupLabel, control = self.groupCombo} end
    if self.hasSubs then fields[#fields + 1] = {label = self.subLabel, control = self.subCombo} end
    local showOptions = (not self.componentMode or mixedCollection(self.category)) and not self.singleOption
    self.trackLabel.hidden = not showOptions
    if showOptions then fields[#fields + 1] = {label = self.trackLabel, control = self.optionCombo} end
    local columns = math.min(#fields, math.max(1, math.floor((width + 12) / 192)))
    if #fields == 4 and columns == 3 then columns = 2 end
    local fieldWidth = math.max(1, math.floor((width - (columns - 1) * 12) / columns))
    for index, field in ipairs(fields) do
        local column, row = (index - 1) % columns, math.floor((index - 1) / columns)
        local span = #fields % columns == 1 and index == #fields and width or fieldWidth
        local x, top = 8 + column * (fieldWidth + 12), y + row * 56
        place(field.label, x, top, span, 18)
        local randomWidth = field.control == self.categoryCombo and self.randomButton and 36 or 0
        place(field.control.root, x, top + 20, span - randomWidth, 28)
        if randomWidth > 0 then place(self.randomButton.root, x + span - 28, top + 20, 28, 28) end
    end
    y = y + math.ceil(#fields / columns) * 56
    place(self.selectorDivider.root, 8, y, width, self.selectorDivider.root.height)
    return y + self.selectorDivider.root.height
end

function Editor:LayoutCollectionToolbar(width, y, place)
    local _, plural = self:CollectionNames()
    self.collectionLabel.content = "Select " .. plural
    local countWidth, selectWidth, clearWidth = 100, 92, 64
    if width >= selectWidth + clearWidth + countWidth + 24 then
        local labelHeight = measuredHeight(self.collectionLabel.content, width, 18)
        place(self.collectionLabel, 8, y, width, labelHeight)
        local buttonY = y + labelHeight + 6
        place(self.bulkButton.root, 8, buttonY, selectWidth, 28)
        place(self.clearButton.root, 16 + selectWidth, buttonY, clearWidth, 28)
        place(self.current, 24 + selectWidth + clearWidth, buttonY + 5, countWidth, 18)
        return buttonY + 36
    end
    countWidth = math.min(countWidth, math.floor(width / 2))
    local labelHeight = measuredHeight(self.collectionLabel.content, width - countWidth - 8, 18)
    place(self.collectionLabel, 8, y, width - countWidth - 8, labelHeight)
    place(self.current, 8 + width - countWidth, y, countWidth, 18)
    selectWidth = math.max(1, math.min(selectWidth, math.floor((width - 8) / 2)))
    clearWidth = math.max(1, math.min(clearWidth, width - selectWidth - 8))
    local buttonY = y + math.max(18, labelHeight) + 6
    place(self.bulkButton.root, 8, buttonY, selectWidth, 28)
    place(self.clearButton.root, 16 + selectWidth, buttonY, clearWidth, 28)
    return buttonY + 36
end

function Editor:ActionHeight() return 0 end

function Editor:LayoutActions() end

function Editor:Layout()
    if not self.built or self.destroyed then return end
    if self.layingOut then self.layoutPending = true; return end
    self.layingOut = true
    local width = math.max(1, self.width - 16)
    local function place(component, x, y, w, h)
        component:SetPos(x, y)
        component:SetSize(math.max(1, w), h)
    end
    local y = self.inline and 0 or 48
    if self.introLabel then place(self.introLabel, 8, 8, width, 36) end
    if self.tabbed then
        y = self:LayoutSelectorRow(width, y, place)
        self.collectionLabel.hidden = not self.componentMode
    else
        place(self.typeLabel, 8, y, width, 18)
        local randomWidth = self.randomButton and 36 or 0
        place(self.categoryCombo.root, 8, y + 20, width - randomWidth, 28)
        if self.randomButton then place(self.randomButton.root, width - 20, y + 20, 28, 28) end
        y = y + 56
        if self.hasGroups then
            place(self.groupLabel, 8, y, width, 18)
            place(self.groupCombo.root, 8, y + 20, width, 28)
            y = y + 56
        end
        if self.hasSubs then
            place(self.subLabel, 8, y, width, 18)
            place(self.subCombo.root, 8, y + 20, width, 28)
            y = y + 56
        end
        self.trackLabel.hidden = false
        place(self.trackLabel, 8, y, width, 18)
    end
    if self.componentMode then
        if self.tabbed then
            y = self:LayoutCollectionToolbar(width, y, place)
        elseif mixedCollection(self.category) then
            place(self.optionCombo.root, 8, y + 20, width, 28)
            y = y + 56
        else y = y + 20 end
        if self.modelShown then
            local labelHeight = measuredHeight(self.description.content, width, 18)
            place(self.description, 8, y, width, labelHeight)
            y = y + labelHeight + 4
            self.previewAvailableWidth = width
            local _, modelHeight = self.modelPreview:Measure(width)
            self.previewY = y
            self.modelPreview:SetBounds(8, y, width)
            y = y + modelHeight + 32
        end
        self.componentPicker:SetBounds(8, y, width)
        y = y + self.componentPicker.height + 8
    else
        if not self.tabbed then
            place(self.optionCombo.root, 8, y + 20, width, 28)
            y = y + 56
        end
        self.previewY = y
        local modelArea, modelHeight = 0, 0
        local hasDescription = self.description.content ~= ""
        local descriptionBelow = false
        if self.modelShown then
            self.previewAvailableWidth = hasDescription and math.max(160, width - 240) or width
            modelArea, modelHeight = self.modelPreview:Measure(self.previewAvailableWidth)
            descriptionBelow = hasDescription and modelArea + 176 > width
            if descriptionBelow then
                self.previewAvailableWidth = width
                modelArea, modelHeight = self.modelPreview:Measure(width)
            end
            self.modelPreview:SetBounds(8, y, self.previewAvailableWidth)
        end
        local descriptionX = modelArea > 0 and modelArea + 16 or 48
        local descriptionY = y
        if descriptionBelow then descriptionX, descriptionY = 8, y + modelHeight + 8 end
        local descriptionWidth = math.max(1, width - descriptionX + 8)
        local descriptionHeight = measuredHeight(self.description.content, descriptionWidth)
        local previewHeight = descriptionBelow and modelHeight + 8 + descriptionHeight
            or math.max(32, modelHeight, descriptionHeight)
        place(self.description, descriptionX, descriptionY, descriptionWidth, descriptionBelow and descriptionHeight or previewHeight)
        if self.preview then
            local size = self.preview.width
            self.preview:SetPos(8 + (32 - size) / 2, y + (32 - size) / 2)
        end
        y = y + previewHeight + 8
    end
    if not self.fixedCollectionTarget and not self.hideTarget then
        local labelHeight = measuredHeight(self.targetLabel.content, width, 18)
        if self.tabbed and self.componentMode and width >= 480 then
            place(self.targetLabel, 8, y + 5, 180, labelHeight)
            place(self.target.root, 196, y, 160, 28)
            place(self.setAllButton.root, 364, y, 80, 28)
            y = y + math.max(28, labelHeight + 5) + 4
        else
            place(self.targetLabel, 8, y, width, labelHeight)
            local inputY = y + labelHeight + 2
            if self.componentMode and width >= 176 then
                local inputWidth = math.min(160, width - 88)
                place(self.target.root, 8, inputY, inputWidth, 28)
                place(self.setAllButton.root, 8 + inputWidth + 8, inputY, 80, 28)
                y = inputY + 32
            elseif self.componentMode then
                place(self.target.root, 8, inputY, width, 28)
                place(self.setAllButton.root, 8, inputY + 34, width, 28)
                y = inputY + 68
            else
                place(self.target.root, 8, inputY, math.min(160, width), 28)
                y = inputY + 32
            end
        end
    end
    if not (self.tabbed and self.componentMode) then
        local currentHeight = measuredHeight(self.current.content, width, 18)
        place(self.current, 8, y, width, currentHeight)
        y = y + currentHeight + 4
    end
    local hintHeight = measuredHeight(self.hint.content, width)
    place(self.hint, 8, y, width, hintHeight)
    y = y + hintHeight
    if self.message.content ~= "" then
        y = y + 6
        local messageHeight = measuredHeight(self.message.content, width, 18)
        place(self.message, 8, y, width, messageHeight)
        y = y + messageHeight
        self.message.hidden = false
    else self.message.hidden = true end
    if self.canBulk and not (self.tabbed and self.componentMode) then
        y = y + 8
        place(self.bulkButton.root, 8, y, math.min(200, width), 28)
        y = y + 28
    end
    y = y + 8
    self.footerY = y
    if self.tabbed then y = y + self.footerHeight end
    if not self.actionsParent then
        self:LayoutActions(8, y, width)
        y = y + self:ActionHeight(width)
    end
    local oldHeight = self.height
    self.height = y + 8
    if self.inline then self.root:SetSize(self.width, self.height)
    else self.window:SetContentHeight(self.height) end
    if self.clipScrollY ~= nil then self:Clip(self.clipScrollY, self.clipViewportHeight) end
    if oldHeight ~= self.height and self.callbacks.layout then self.callbacks.layout(self, self.height) end
    self.layingOut = false
    if self.layoutPending then self.layoutPending = nil; self:Layout() end
end

function Editor:SetBounds(x, y, width)
    if not self.inline or self.destroyed then return end
    self.x, self.y = x, y
    self.width = math.max(1, width)
    self.root:SetPos(x, y)
    self:Layout()
end

function Editor:Clip(scrollY, viewportHeight)
    if not self.inline or self.destroyed then return end
    self.clipScrollY, self.clipViewportHeight = scrollY or 0, viewportHeight or 0
    for _, control in ipairs(self.controls) do
        local root = control.root
        if root then
            local top = self.root.y + root.y - self.clipScrollY
            local hidden = self.logicalHidden[control] or top < 0 or top + root.height > self.clipViewportHeight
            root.hidden = hidden == true
            if hidden and control._Close then control:_Close() end
        end
    end
    if self.componentPicker then self.componentPicker:Clip(self.clipScrollY - self.root.y, self.clipViewportHeight) end
    if self.modelPreview then
        self.modelPreview:SetHidden(not self.modelShown)
        self.modelPreview:Clip(self.root.y - self.clipScrollY, self.clipViewportHeight)
    end
end

function Editor:Snapshot()
    self:FlushPending()
    if self.destroyed then return nil end
    self:CancelRandomGoal()
    self:RememberCollection()
    return {category = self.category, group = self.group, option = self.options[self.optionCombo:GetSelectedID()],
        targetText = self.target:GetText(), previous = Tracking.Normalize(self.previous),
        selectionTitle = self.selectionTitle, committedTitle = self.committedTitle, collectionDrafts = self.collectionDrafts,
        dirty = self.dirty == true, randomHistory = self.randomHistory}
end

local function buildControls(self, category)
    local width = math.max(1, self.width - (self.inline and 16 or 24))
    self.typeLabel = self:Label("Type", 8, 0, width, 18, GOLD)
    self.categoryCombo = self:Combo(0, self.categories, function(value) return Tracking.CategoryLabel(value) end,
        matchingIndex(self.categories, category), function(index)
            if self.categories[index] then self:LoadCategory(self.categories[index]) end
        end)
    if self.randomize then
        self.randomButton = self:Track(prettyui.SimpleButton.new(self.content, id.Sprite.RS3_ICON_RANDOMISE_0, function()
            self:Queue(function() self:StartRandomGoal() end, false, true)
        end, Components.Options({x = 8, y = 0, width = 28, height = 28, iconSize = 18})))
    end
    self.groupLabel = self:Label("Boss", 8, 0, width, 18, GOLD)
    self.groupCombo = self:Combo(0, {}, function(value) return value.label or value.name end, 1, function(index)
        self.group = self.groups[index]
        if self.group and self.group.subs then self.group = self:WithSub(self.group, 1) end
        self:LoadOptions()
    end)
    self.subLabel = self:Label("Animal", 8, 0, width, 18, GOLD)
    self.subCombo = self:Combo(0, {}, function(value) return value.name end, 1, function(index)
        if self.group and self.group.subs then
            self.group = self:WithSub(self.group, index)
            self:LoadOptions()
        end
    end)
    self.trackLabel = self:Label("Track", 8, 0, width, 18, GOLD)
    self.optionCombo = self:Combo(0, {}, function(value) return value.label end, 1, function()
        self:UpdateOption(true)
    end)
    self.description = self:Label("", 48, 0, math.max(1, width - 40), 32, MUTED)
    self.targetLabel = self:Label("Target value", 8, 0, width, 18, GOLD)
    self.target = self:Track(prettyui.TextField.new(self.content, Components.Options({x = 8, y = 0,
        width = math.min(160, width), height = 28, maxLength = 16, text = "", placeholder = "Target",
        onChange = function(control, _, value)
            self:CancelRandomGoal()
            local text = tostring(value or control:GetText())
            if self.built and text ~= self.lastTargetText then self.dirty = true end
            self.lastTargetText = text
            self:BatchTargetChanged()
        end})))
    WindowStyle.ApplyInput(self.target.root)
    self.target.root.text.maxLines = 1
    self.target.root.scrollbar.visible = false
    self.target.root.scrollbar.size = 0
    self.target.root:Subscribe(ui.Hook.ONCLICK, function() self:Focus(self.target); return true end)
    self.setAllButton = self:Button("Set all", 176, 0, 80, function() self:SetAllTargets() end)
    self.current = self:Label("", 8, 0, width, 18, TEXT)
    self.hint = self:Label("", 8, 0, width, 18, MUTED)
    self.message = self:Label("", 8, 0, width, 18, GOLD)
    self.bulkButton = self:Button("Add all items", 8, 0, math.min(200, width), function() self:AddAll() end)
    self:SetControlHidden(self.bulkButton, true)
    if self.tabbed then
        self.selectorDivider = self:Track(prettyui.Divider.new(self.content, Components.Options({x = 8, width = width})))
        self.collectionLabel = self:Label("Collection items", 8, 0, width, 18, GOLD)
        self.clearButton = self:Button("Clear", 8, 0, 64, function()
            if not self.componentPicker then return end
            self.componentPicker:SetSelected({})
            self:UpdateComponents(nil, true)
            self:ShowMessage("")
        end)
        self:SetControlHidden(self.clearButton, true)
    end
end

function Editor.Mount(parent, tracking, callbacks, options)
    options = options or {}
    local snapshot = options.snapshot
    local self = setmetatable({parent = parent, callbacks = callbacks or {}, inline = true, tabbed = options.tabbed == true,
        randomize = options.randomize == true, randomHistory = snapshot and snapshot.randomHistory or {},
        controls = {}, logicalHidden = {}, previous = Tracking.Normalize(snapshot and snapshot.previous or tracking),
        width = math.max(1, options.width or parent.width), footerHeight = options.footerHeight or 0,
        x = options.x or 0, y = options.y or 0, actionsParent = options.actionsParent}, Editor)
    self.root = Components.Host(parent)
    self.root:SetPos(self.x, self.y)
    self.root:SetSize(self.width, 1)
    self.root.clickthrough = true
    self.content = self.root
    local context = prettyui.Tooltip.getContext(parent)
    if context then
        prettyui.Tooltip.registerContext(self.root, context.parent, function(target)
            local x, y = target.x or 0, target.y or 0
            local ancestor = target.parent
            while ancestor and ancestor ~= parent do
                x, y = x + (ancestor.x or 0) - (ancestor.scrollX or 0), y + (ancestor.y or 0) - (ancestor.scrollY or 0)
                ancestor = ancestor.parent
            end
            return context.position({x = x, y = y})
        end, context)
    end
    self.categories = Tracking.Categories()
    local category, group, option, targetText = Tracking.Selection(self.previous)
    self:InitializeCollections(category, group, snapshot)
    self.committedTitle = snapshot and snapshot.committedTitle or Tracking.Title(category, group, option, targetText) or ""
    if snapshot then
        category, group, option, targetText = snapshot.category, snapshot.group, snapshot.option, snapshot.targetText
    end
    local changedCategory = options.category ~= nil and options.category ~= category
    if changedCategory then category, group, option, targetText = options.category, nil, nil, nil end
    category = category or self.categories[1]
    buildControls(self, category)
    self:LoadCategory(category, group, option, targetText)
    self.selectionTitle = snapshot and snapshot.selectionTitle or changedCategory and self.committedTitle or self:CurrentTitle()
    if not snapshot then self.committedTitle = self.selectionTitle or "" end
    self.built = true
    self.dirty = snapshot and snapshot.dirty == true or changedCategory and self.previous ~= nil or false
    self.lastTargetText = self.target:GetText()
    self:Layout()
    return self
end

function Editor.Open(parent, tracking, callbacks)
    local self = setmetatable({parent = parent, callbacks = callbacks or {},
        controls = {}, previous = Tracking.Normalize(tracking)}, Editor)
    local windowWidth = math.min(560, parent.width)
    local windowHeight = math.min(FORM_HEIGHT + 40, parent.height)
    self.window = WindowStyle.New(parent, {
        title = "Notes-Plus - Tracking", width = windowWidth, height = windowHeight,
        minWidth = math.min(320, windowWidth), minHeight = math.min(200, windowHeight),
        x = math.max(0, math.floor((parent.width - windowWidth) / 2)),
        y = math.max(0, math.floor((parent.height - windowHeight) / 2)),
        scrollable = true, contentHeight = FORM_HEIGHT,
        onClose = function() self:Queue(function() self:Cancel() end) end
    })
    self.content = self.window.content
    self.width = self.window.contentWidth - 16
    local width = self.width - 24
    self.introLabel = self:Label("Tracking is optional. Your title, subject, icon and colour stay editable.", 12, 8, width, 36, MUTED)
    self.categories = Tracking.Categories()
    local category, group, option, targetText = Tracking.Selection(self.previous)
    self:InitializeCollections(category, group)
    category = category or self.categories[1]
    buildControls(self, category)
    self:LoadCategory(category, group, option, targetText)
    self.selectionTitle = self:CurrentTitle()
    self.committedTitle = self.selectionTitle or ""
    self.built = true
    self:Layout()
    self.window:Show()
    return self
end

function Editor:Tick()
    if self.destroyed then return end
    if self.componentPicker then self.componentPicker:Tick() end
    self:FlushPending()
    if not self.destroyed and self.randomJob then self:TickRandomGoal() end
    if not self.destroyed and Tracking.IconRevision and self.iconRevision ~= Tracking.IconRevision() then
        local wasShown = self.modelShown
        self:UpdatePreview()
        if self.modelShown ~= wasShown then self:Layout() end
    end
end

function Editor:Destroy(detached)
    if self.destroyed then return end
    self.destroyed = true
    self.randomJob, self.randomHistory = nil, nil
    self.pending, self.pendingSelection, self.pendingTargetText, self.randomQueued = nil, false, nil, nil
    if self.componentPicker then self.componentPicker:Destroy(detached); self.componentPicker = nil end
    if self.modelPreview then self.modelPreview:Destroy(detached) end
    self.modelPreview, self.petPreviewOption = nil, nil
    if detached then Detached.Tooltips(self.content) end
    for _, control in ipairs(self.controls) do
        if detached then
            if control.dropdown then
                control.ownerWindow = nil
                Detached.Control(control.dropdown)
                control.dropdown = nil
            end
            Detached.Control(control)
        else
            control:Destroy()
        end
    end
    self.controls = {}
    if self.window then
        if detached then Detached.Window(self.window) else self.window:Destroy() end
    elseif self.root then
        if not detached then
            prettyui.Tooltip.unregisterContext(self.root)
            self.root:Destroy()
        end
    end
    self.window, self.root, self.content, self.preview = nil, nil, nil, nil
    if self.callbacks.closed then self.callbacks.closed() end
end

function Editor:Abandon()
    self:Destroy(true)
end

return Editor
