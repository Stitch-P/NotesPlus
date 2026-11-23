local SafeValues = require("src/core/safe_values")
local Hotkeys = require("src/core/hotkeys")
local SettingsHotkey = require("src/core/settings_hotkey")
local Settings = require("src/core/settings")
local Profiles = require("src/core/character_profiles")
local Notes = require("src/notes/notes")
local Menu = require("src/ui/settings/menu")
local Panel = require("src/ui/panel")
local SettingsLauncher = require("src/ui/settings/settings_launcher")
local NativeMenu = require("src/ui/native/native_menu")
local NativeRibbonIcon = require("src/ui/native/native_ribbon_icon")
local SpriteDirectory = require("src/data/sprite_directory")
local Tracking = require("src/tracking/model")
local BossModelPresets = require("src/tracking/data/boss_model_presets")
local PetModelPresets = require("src/tracking/data/pet_model_presets")
local CompletionNotifications = require("src/notes/completion_notifications")
local PorterChat = require("src/tracking/features/porter_chat")
local AchievementGoals = require("src/tracking/features/achievement_goals").AchievementGoals
local GatheringTracker = require("src/tracking/features/gathering_tracker").GatheringTracker
local UrnSource = require("src/tracking/features/urn_source").UrnSource
local Fort = require("src/tracking/features/fort").Fort

local nativeRibbonIcon = NativeRibbonIcon.New("N", id.Sprite.CHILD_TAB_ICON_NOTES)


if NotesPlugin then NotesPlugin.Stop() end
if NotesPlusPlugin and NotesPlusPlugin ~= NotesPlugin then NotesPlusPlugin.Stop() end

local api = {}
local state = {
    settings = Settings.Normalize({}),
    data = Notes.New(),
    parent = nil,
    menu = nil,
    nativeMenu = nil,
    hubContentPanel = nil,
    hubSettingsPanel = nil,
    panel = nil,
    stopped = false,
    hotkeyArmed = false,
    elapsed = 0,
    saveAt = nil,
    eventSubscriptions = {},
    eventsReady = false,
    ribbonVisible = false
}

local applySettings
local syncProfile
local syncSubscriptions
local onDraw
local onContextMenu

local function profileAvailable()
    return state.profileID ~= nil and Profiles.CurrentID() == state.profileID
end

local function profileMessage()
    if state.profileError then return state.profileError end
    local _, message = Profiles.CurrentID()
    return message or "Waiting for this character's notes to load."
end

local function queueSave()
    state.saveAt = state.elapsed + 0.5
end

local function flush()
    if state.saveAt then
        if state.profileID then Settings.Save(state.settings, state.profileID) end
        state.saveAt = nil
    end
end

local function saveNotesData()
    local ok, saved, reason = pcall(Notes.Save, state.data)
    if ok and saved == true then state.notesSaveError = nil; return true end
    if not ok then reason = saved end
    reason = tostring(reason)
    if state.notesSaveError ~= reason then log("Notes-Plus notes save failed:", reason) end
    state.notesSaveError = reason
    return nil, reason
end

state.completionNotifications = CompletionNotifications.new({
    getData = function() return state.data end,
    getSettings = function() return state.settings end,
    getParent = function()
        return ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__GAME_AREA)
            or ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
    end,
    available = function()
        return not state.stopped and not state.suspended and state.parent ~= nil
            and profileAvailable() and state.settings.enabled
    end,
    onCompletionStateChanged = function() return Notes.Save(state.data) end,
    onPosition = function(x, y)
        state.settings.achievementPopupX, state.settings.achievementPopupY = x, y
        Menu.SyncSettings(NativeMenu.Get(state, true), state.settings, {"achievementPopupX", "achievementPopupY"})
        Settings.Save(state.settings, state.profileID)
    end
})

local function positionPopup()
    return state.completionNotifications:StartPositioning()
end

local function notificationsDetached()
    return state.parent ~= nil and ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP) ~= state.parent
end

local function panelMoved(x, y)
    state.settings.notesX, state.settings.notesY = x, y
    Menu.SyncSettings(NativeMenu.Get(state, true), state.settings, {"notesX", "notesY"})
    queueSave()
end

local function panelResized(width, height, x, y)
    state.settings.notesWidth, state.settings.notesHeight = width, height
    state.settings.notesResized = true
    state.settings.notesX, state.settings.notesY = x, y
    Menu.SyncSettings(NativeMenu.Get(state, true), state.settings, {
        "notesWidth", "notesHeight", "notesResized", "notesX", "notesY"
    })
    queueSave()
end

function api.CloseNotes(detached)
    if state.panel then
        detached = detached == true or (state.parent ~= nil and ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP) ~= state.parent)
        local panel = state.panel
        state.panel = nil
        if not detached and not panel.editorGeometry then panelMoved(panel.window:GetPosition()) end
        panel:Destroy(detached)
    end
    if syncSubscriptions then syncSubscriptions() end
end

function api.OpenNotes()
    if state.stopped or state.suspended or not state.parent or not state.settings.enabled then return end
    if not profileAvailable() then return profileMessage() end
    if state.panel then state.panel.window.chrome:Show(); return end
    local profileToken = state.profileToken
    state.panel = Panel.new(state.parent, state.settings, state.data, {
        close = function() if state.profileToken == profileToken then api.CloseNotes() end end,
        resize = function(...) if state.profileToken == profileToken then panelResized(...) end end,
        move = function(...) if state.profileToken == profileToken then panelMoved(...) end end,
        notesSaved = function()
            if state.profileToken == profileToken then state.completionNotifications:Refresh(state.elapsed) end
        end
    })
    if syncSubscriptions then syncSubscriptions() end
end

local function notesHotkeyAvailable()
    return not state.stopping and not state.stopped and not state.suspended and state.settings.enabled
        and state.parent ~= nil and profileAvailable() and (state.panel == nil or not state.panel:BlocksHotkey())
end

local function onKeyDown(keyEvent)
    if keyEvent == nil or keyEvent.isRepeat then return end
    state.hotkeyArmed = keyEvent.gameKey ~= nil and notesHotkeyAvailable()
        and SettingsHotkey.IsExactDown(Hotkeys.GetKeys(state.settings.notesHotkey), keyEvent.gameKey)
end

local function onKeyUp(keyEvent)
    if keyEvent == nil or not state.hotkeyArmed then return end
    state.hotkeyArmed = false
    if notesHotkeyAvailable()
        and SettingsHotkey.IsValidRelease(Hotkeys.GetKeys(state.settings.notesHotkey), keyEvent.gameKey) then
        if state.panel then api.CloseNotes() else api.OpenNotes() end
    end
end

local function onWindowFocusChanged()
    state.hotkeyArmed = false
end

local function cleanupStep(label, callback)
    local ok, err = pcall(callback)
    if not ok then
        state.stopSucceeded = false
        log("Notes: cleanup failed", label, tostring(err))
    end
end

local function clearHubPanel(key)
    local panel = state[key]
    state[key] = nil
    cleanupStep("hub panel", function() SettingsLauncher.Destroy(panel) end)
end

function api.CloseMenu(detached)
    if state.menu then
        local menu = state.menu
        state.menu = nil
        if detached == true then Menu.Abandon(menu)
        else
            cleanupStep("menu settings", function() state.settings = Menu.Read(menu) end)
            cleanupStep("menu destruction", function() Menu.Destroy(menu) end)
        end
        queueSave()
    end
    if syncSubscriptions then syncSubscriptions() end
end

function api.OpenMenu(parent, embedded)
    local menuParent = parent or state.parent
    if state.stopped or state.suspended or not menuParent then return end
    if not profileAvailable() then return profileMessage() end
    if state.menu then Menu.MoveToFront(state.menu); return end
    if not embedded then
        local native = NativeMenu.Get(state, true)
        if native ~= nil then state.settings = Menu.Read(native) end
        NativeMenu.Clear(state)
    end
    local profileToken = state.profileToken
    state.menu = Menu.Mount(menuParent, state.settings, {
        onApply = function(settings) if state.profileToken == profileToken then applySettings(settings) end end,
        onClose = function() if state.profileToken == profileToken then api.CloseMenu() end end,
        onOpenNotes = function() if state.profileToken == profileToken then return api.OpenNotes() end end,
        onPositionPopup = function() if state.profileToken == profileToken then return positionPopup() end end
    }, embedded)
    if syncSubscriptions then syncSubscriptions() end
end

local function openStandaloneSettings()
    if state.stopping or state.stopped then return "The plugin is stopped." end
    if state.suspended then return "Open settings after the game interface is available." end
    if not profileAvailable() then return profileMessage() end
    local parent = state.parent or ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
    if parent == nil then return "Open settings after the game interface is available." end
    api.OpenMenu(parent, false)
    if state.menu == nil then return "Unable to open settings." end
end

local function toggleStandaloneSettings()
    if state.menu ~= nil then
        api.CloseMenu()
    else
        return openStandaloneSettings()
    end
end

state.settingsHotkeyController = SettingsHotkey.New("notes_settings_hotkey", {
    getBinding = function() return state.settings.settingsHotkey end,
    setBinding = function(value)
        if not profileAvailable() then return end
        local menu = NativeMenu.Get(state, true)
        if menu ~= nil then applySettings(Menu.Read(menu)) end
        state.settings.settingsHotkey = value
        Menu.SyncSettings(menu, state.settings, {"settingsHotkey"})
        Settings.Save(state.settings, state.profileID)
        state.saveAt = nil
    end,
    toggle = toggleStandaloneSettings,
    available = function()
        SettingsLauncher.Sync(state.hubContentPanel)
        SettingsLauncher.Sync(state.hubSettingsPanel)
        return not state.stopping and not state.stopped and not state.suspended and profileAvailable()
    end
})

local function mountHubPanel(event, key)
    if state.stopping or state.stopped or state.suspended or event == nil or event.component == nil then return end
    clearHubPanel(key)
    state[key] = SettingsLauncher.Mount(event, "Notes-Plus", toggleStandaloneSettings, state.settingsHotkeyController, {
        onOpenNotes = function() return api.OpenNotes() end,
        getNotesHotkey = function() return state.settings.notesHotkey end,
        setNotesHotkey = function(value)
            if not profileAvailable() then return end
            local menu = NativeMenu.Get(state, true)
            if menu ~= nil then applySettings(Menu.Read(menu)) end
            state.settings.notesHotkey = value
            state.hotkeyArmed = false
            Menu.SyncSettings(menu, state.settings, {"notesHotkey"})
            Settings.Save(state.settings, state.profileID)
            state.saveAt = nil
            if syncSubscriptions then syncSubscriptions() end
        end
    })
    if syncSubscriptions then syncSubscriptions() end
end

local function onMenuLayerReady(event)
    mountHubPanel(event, "hubContentPanel")
end

local function onSettingsLayerReady(event)
    mountHubPanel(event, "hubSettingsPanel")
end

function applySettings(settings)
    if not profileAvailable() then return end
    local previousHotkey = state.settings.notesHotkey
    local previousShowSubject = state.settings.showSubject
    state.settings = Settings.Normalize(settings)
    if not state.settings.enabled then state.completionNotifications:Reset(notificationsDetached()) end
    if previousHotkey ~= state.settings.notesHotkey then state.hotkeyArmed = false end
    if previousShowSubject ~= state.settings.showSubject then
        for _, note in ipairs(state.data.notes) do note.subjectExpanded = state.settings.showSubject end
        state.gatherSaveAt = state.gatherSaveAt or state.elapsed + 5
    end
    queueSave()
    if state.panel then
        if not state.settings.enabled then api.CloseNotes()
        else state.panel:Update(state.settings) end
        if state.menu then Menu.MoveToFront(state.menu) end
    end
    if syncSubscriptions then syncSubscriptions() end
end

function api.Mount(parent)
    if state.stopped or state.suspended or state.parent or not parent or parent.width <= 0 or parent.height <= 0 then return end
    if not syncProfile() then return end
    state.parent = parent
    state.parentWidth, state.parentHeight = parent.width, parent.height
    if state.settings.showOnLogin or state.reopenNotes then api.OpenNotes() end
    state.reopenNotes = false
end


local function unmount(saveNotes)
    local detached = state.parent ~= nil and ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP) ~= state.parent
    cleanupStep("completion notifications", function() state.completionNotifications:Reset(detached) end)
    cleanupStep("menu", function() api.CloseMenu(detached) end)
    NativeMenu.Clear(state)
    clearHubPanel("hubContentPanel")
    clearHubPanel("hubSettingsPanel")
    cleanupStep("notes panel", function() api.CloseNotes(detached) end)
    state.parent = nil
    state.hotkeyArmed = false
    if state.profileID ~= nil and state.profileToken == Profiles.Token() and (saveNotes or state.gatherSaveAt) then
        if saveNotesData() then state.gatherSaveAt = nil
        else
            state.gatherSaveAt = state.elapsed + 5
            state.stopSucceeded = false
        end
    end
    SpriteDirectory.Reset()
    Tracking.Reset()
    cleanupStep("settings", function() flush() end)
end

local function releaseProfile()
    unmount(state.profileID ~= nil)
    PorterChat.Stop()
    state.chatStarted = false
    Profiles.Deactivate()
    state.profileID, state.profileToken = nil, nil
    state.settings, state.data = Settings.Normalize({}), Notes.New()
    state.saveAt, state.gatherSaveAt, state.notesSaveError = nil, nil, nil
    state.nextGoalExpire, state.nextGatherPoll, state.nextTrackingRefresh = nil, nil, nil
    state.hotkeyArmed, state.trackingDirty = false, true
end

syncProfile = function()
    local profileID = Profiles.CurrentID()
    if profileID ~= nil and profileID == state.profileID then return true end
    if state.profileID ~= nil then
        if state.panel ~= nil then state.reopenNotes = true end
        state.reopenProfileID = state.profileID
        releaseProfile()
    end
    if profileID == nil then
        state.profileError, state.failedProfileID = nil, nil
        return false
    end
    if state.failedProfileID == profileID then return false end
    local ok, settings, data = pcall(function()
        Profiles.Activate(profileID)
        local loadedSettings = Settings.Load(profileID)
        local loadedData = Notes.Load(profileID)
        return loadedSettings, loadedData
    end)
    if not ok then
        Profiles.Deactivate()
        state.failedProfileID = profileID
        state.profileError = "Unable to load this character's notes. Saved data has been kept. Reload Notes-Plus to retry."
        log("Notes: character profile could not be loaded", tostring(settings))
        return false
    end
    state.profileID, state.settings, state.data = profileID, settings, data
    state.profileToken = Profiles.Token()
    state.profileError, state.failedProfileID = nil, nil
    if state.reopenProfileID ~= nil and state.reopenProfileID ~= profileID then state.reopenNotes = false end
    state.reopenProfileID = nil
    state.trackingDirty = true
    if syncSubscriptions then syncSubscriptions() end
    return true
end

local function onGameStateChanged(event)
    if state.stopped or event == nil or event.newState == nil then return end
    state.suspended = event.newState ~= GameState.GAME
    if state.suspended then state.completionNotifications:Reset(notificationsDetached()) end
    if event.newState == GameState.LOBBY or event.newState == GameState.LOGINSCREEN
        or event.newState == GameState.BOOT or event.newState == GameState.INIT or event.newState == GameState.ACCOUNT_CREATE then
        state.reopenNotes = false
        state.reopenProfileID = nil
        releaseProfile()
        state.profileError, state.failedProfileID = nil, nil
    end
    if syncSubscriptions then syncSubscriptions() end
end

local function onLogic(event)
    if state.stopped then return end
    local tick = SafeValues.Number(SafeValues.Field(event, "logicTick"))
    if tick ~= nil and (tick ~= tick or tick == math.huge or tick == -math.huge) then tick = nil end
    local delta = tick ~= nil and state.lastLogicTick ~= nil and tick - state.lastLogicTick or 1
    if delta < 0 then delta = 1 end
    state.elapsed = state.elapsed + delta / 50
    state.lastLogicTick = tick
    if state.elapsed >= (state.nextUILifecycle or 0) then
        state.nextUILifecycle = state.elapsed + 0.1
        state.ribbonVisible = nativeRibbonIcon:IsVisible()
        syncSubscriptions()
    end
    local parent = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
    if state.parent and parent ~= state.parent then
        state.reopenNotes = state.panel ~= nil
        unmount()
    end
    if state.suspended then return end
    if not syncProfile() then return end
    local browser = state.panel and state.panel:GetSpriteBrowser()
    if Tracking.Poll(browser and not browser.destroyed and not browser.itemsOnly, state.elapsed) then state.trackingDirty = true end
    if not state.parent and parent then api.Mount(parent) end
    if not state.parent then return end
    local menu = NativeMenu.Get(state)
    if menu ~= nil then Menu.Tick(menu) end
    if parent.width ~= state.parentWidth or parent.height ~= state.parentHeight then
        state.parentWidth, state.parentHeight = parent.width, parent.height
        state.menuBoundsPending = true
        if state.panel then state.panel:Update(state.settings) end
    end
    if state.menuBoundsPending and state.menu ~= nil and not Menu.IsDragging(state.menu) then
        state.menu.refreshBounds()
        state.menuBoundsPending = false
    end
    if state.elapsed >= (state.nextGoalExpire or 0) then
        -- The achievement lists behind the Reaper / cape notes are read once and kept; this makes them read afresh.
        state.nextGoalExpire = state.elapsed + 4
        AchievementGoals.Expire()
    end
    AchievementGoals.Pump()
    -- Looks for skilling pets' items by name, a few hundred items a tick, only while a pet is still being looked for.
    require("src/tracking/core/pet_objects").Pump()
    UrnSource.Pump()
    Fort.Pump()
    if state.panel then
        state.panel:Tick()
        if state.trackingDirty or state.elapsed >= (state.nextTrackingRefresh or 0) then
            state.panel:RefreshTracking()
            state.trackingDirty = false
            state.nextTrackingRefresh = state.elapsed + 0.6
        end
    end
    state.completionNotifications:Tick(state.elapsed)
    if not state.chatStarted and state.elapsed >= 2 then
        state.chatStarted = true
        PorterChat.Start()
    end
    if state.elapsed >= (state.nextGatherPoll or 0) then
        state.nextGatherPoll = state.elapsed + 0.5
        local ok, changed = pcall(GatheringTracker.Poll, state.data.notes, state.elapsed)
        if ok and changed then
            state.trackingDirty, state.gatherSaveAt = true, state.gatherSaveAt or state.elapsed + 5
        end
    end
    if state.gatherSaveAt and state.elapsed >= state.gatherSaveAt then
        if saveNotesData() then state.gatherSaveAt = nil
        else state.gatherSaveAt = state.elapsed + 5 end
    end
    if state.saveAt and state.elapsed >= state.saveAt then flush() end
end

function api.GetState()
    return state
end

function api.GetModelPresets()
    if state.stopped then return nil, "Notes-Plus is stopped." end
    local presets = SafeValues.DeepCopy(BossModelPresets)
    for skill, preset in pairs(PetModelPresets) do
        presets["Pet: " .. (preset.label or skill)] = SafeValues.DeepCopy(preset)
    end
    return presets
end

function api.GetModelPreviewLayout()
    local view = state.panel and state.panel.activeView
    local editor = view and view.view == "edit" and view.activeTab == "tracking" and view.trackingEditor
    local page = view and view.pages and view.pages.tracking
    local scene = editor and editor.modelPreview
    if state.stopped or state.suspended or not state.parent or not editor or editor.destroyed
        or not editor.modelShown or not scene or not scene.ready or not scene.x or not scene.y
        or not editor.previewAvailableWidth or not page or not page._scroll then
        return nil
    end
    return {
        width = editor.previewAvailableWidth,
        viewportWidth = page.contentWidth,
        viewportHeight = page._scroll.height,
        sceneX = editor.x + scene.x,
        sceneY = editor.y + scene.y - page.scrollY,
    }
end

function api.Stop()
    if state.stopped then return end
    state.stopped = true
    state.stopSucceeded = true
    cleanupStep("settings hotkey", function() state.settingsHotkeyController:Stop() end)
    cleanupStep("ribbon icon", function() nativeRibbonIcon:Stop() end)
    cleanupStep("event subscription", function() Event.KeyDown.Unsubscribe("notes_hotkey") end)
    cleanupStep("event subscription", function() Event.KeyUp.Unsubscribe("notes_hotkey") end)
    if Event.WindowFocusChanged ~= nil then
        cleanupStep("event subscription", function() Event.WindowFocusChanged.Unsubscribe("notes_hotkey_focus") end)
    end
    cleanupStep("event subscription", function() Event.Logic.Unsubscribe("notes_logic") end)
    cleanupStep("event subscription", function() Event.Draw.Unsubscribe("notes_draw") end)
    cleanupStep("event subscription", function() Event.MiniMenuReady.Unsubscribe("notes_context") end)
    cleanupStep("event subscription", function() Event.ContentLayerReady.Unsubscribe("notes_content") end)
    cleanupStep("event subscription", function() Event.SettingsLayerReady.Unsubscribe("notes_settings") end)
    cleanupStep("event subscription", function() Event.GameStateChanged.Unsubscribe("notes_game_state") end)
    cleanupStep("event subscription", function() Event.VarTransmit.Unsubscribe("notes_plus_vars") end)
    cleanupStep("event subscription", function() require("src/tracking/core/pouch").Detach() end)
    cleanupStep("event subscription", function() Event.ServerLogic.Unsubscribe("notes_plus_server") end)
    cleanupStep("event subscription", function() PorterChat.Stop() end)
    cleanupStep("completion notifications", function() state.completionNotifications:Stop(notificationsDetached()) end)
    unmount(true)
    Profiles.Deactivate()
    state.profileID, state.profileToken = nil, nil
end

function onContextMenu(event)
    if not state.stopped and not state.suspended and state.panel then
        state.panel:AddContextMenu(event.miniMenu)
    end
end

function onDraw()
    if state.stopped then return end
    local parent = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
    if state.parent and parent ~= state.parent then
        state.reopenNotes = state.panel ~= nil
        unmount()
        return
    end
    if state.suspended then return end
    SettingsLauncher.Sync(state.hubContentPanel)
    SettingsLauncher.Sync(state.hubSettingsPanel)
    if not profileAvailable() then
        if state.ribbonVisible then nativeRibbonIcon:Draw() end
        return
    end
    if state.panel then state.panel.window:SyncResize() end
    local menu = NativeMenu.Get(state)
    if menu ~= nil then Menu.Tick(menu) end
    if state.ribbonVisible then nativeRibbonIcon:Draw() end
end

local function setSubscription(event, key, enabled, callback)
    if event == nil then return end
    local subscriptions = state.eventSubscriptions[event]
    if subscriptions == nil then subscriptions = {}; state.eventSubscriptions[event] = subscriptions end
    if subscriptions[key] == enabled then return end
    if enabled then event.Subscribe(key, callback)
    elseif subscriptions[key] then event.Unsubscribe(key) end
    subscriptions[key] = enabled
end

local function launcherVisible(key)
    local panel = state[key]
    if panel == nil then return false end
    local root = SettingsLauncher.SyncLifecycle(panel)
    if not panel.active then state[key] = nil end
    return root ~= nil
end

function syncSubscriptions()
    if not state.eventsReady or state.stopped then return end
    state.settingsHotkeyController:GetBinding()
    local contentVisible = launcherVisible("hubContentPanel")
    local settingsVisible = launcherVisible("hubSettingsPanel")
    local notesKeys = not state.suspended and state.settings.enabled and state.parent ~= nil
        and state.profileID ~= nil and #Hotkeys.GetKeys(state.settings.notesHotkey) > 0
    if not notesKeys then state.hotkeyArmed = false end
    setSubscription(Event.KeyDown, "notes_hotkey", notesKeys, onKeyDown)
    setSubscription(Event.KeyUp, "notes_hotkey", notesKeys, onKeyUp)
    setSubscription(Event.WindowFocusChanged, "notes_hotkey_focus", notesKeys, onWindowFocusChanged)
    setSubscription(Event.MiniMenuReady, "notes_context", not state.suspended and state.panel ~= nil, onContextMenu)
    local drawing = not state.suspended and (state.panel ~= nil or NativeMenu.Get(state) ~= nil
        or contentVisible or settingsVisible or state.ribbonVisible)
    setSubscription(Event.Draw, "notes_draw", drawing, onDraw)
end

Event.Logic.Subscribe("notes_logic", onLogic)
Event.ContentLayerReady.Subscribe("notes_content", onMenuLayerReady)
Event.SettingsLayerReady.Subscribe("notes_settings", onSettingsLayerReady)
Event.GameStateChanged.Subscribe("notes_game_state", onGameStateChanged)
Event.VarTransmit.Subscribe("notes_plus_vars", function() state.trackingDirty = true end)
-- Currency pouch (Chronotes, Stardust). Set POUCH_EVENTS to false to stop listening for inventory events while testing
-- reloads: balances are then still read when the tracking refreshes, just not pushed the moment the pouch changes.
local POUCH_EVENTS = true
if POUCH_EVENTS then require("src/tracking/core/pouch").Attach(function() state.trackingDirty = true end) end
Event.ServerLogic.Subscribe("notes_plus_server", function() state.trackingDirty = true end)
state.eventsReady = true
syncSubscriptions()

function PluginShutdown()
    api.Stop()
end

NotesPlugin = api
NotesPlusPlugin = api
return api
