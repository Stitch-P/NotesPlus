local Components = require("src/ui/shared/components")
local SafeValues = require("src/core/safe_values")
local SettingsHotkey = require("src/core/settings_hotkey")
local Hotkeys = require("src/core/hotkeys")

local Launcher = {}
local generation = 0

local function ownedRoot(panel)
    if panel == nil or not panel.active then return nil end
    local ok, root = pcall(function()
        local component = ui.Interfaces:GetComponent(panel.interfaceID, panel.staticID, panel.categoryID, panel.dynamicID)
        if component == nil then return nil end
        local marker = component:GetChild(panel.markerCategory, panel.markerDynamic)
        if marker ~= nil and marker.content == panel.token then return component end
        return nil
    end)
    return ok and root or nil
end

local function textHeight(panel, text, width)
    if text == "" then return 0 end
    return math.max(22, panel.font:GetStringLineCount(text, width, false, false, false) * panel.font.baseline + 4)
end

local function createHotkeys(panel)
    panel.binding = panel.controller:GetBinding()
    panel.hotkey = prettyui.KeybindField.new(panel.view.content, Components.Options({
        value = SettingsHotkey.GetKeys(panel.binding), defaultValue = {},
        width = 1, height = 28, font = panel.fontID,
        onChange = function(_, keys)
            if ownedRoot(panel) == nil then return end
            panel.controller:SetBinding(SettingsHotkey.FromKeys(keys))
            Launcher.Sync(panel)
        end,
    }))
    panel.notesBinding = panel.callbacks.getNotesHotkey()
    panel.notesHotkey = prettyui.KeybindField.new(panel.view.content, Components.Options({
        value = Hotkeys.GetKeys(panel.notesBinding), defaultValue = {},
        width = 1, height = 28, font = panel.fontID,
        onChange = function(_, keys)
            if ownedRoot(panel) == nil then return end
            local binding = Hotkeys.FromKeys(keys)
            if binding then panel.callbacks.setNotesHotkey(binding) end
            Launcher.Sync(panel)
        end,
    }))
    panel.width, panel.height = nil, nil
end

function Launcher.SyncLifecycle(panel)
    local root = ownedRoot(panel)
    if root == nil then
        Launcher.Destroy(panel)
        return nil
    end
    if not root.visibleGlobal then
        for _, key in ipairs({"hotkey", "notesHotkey"}) do
            if panel[key] ~= nil then panel[key]:Destroy(); panel[key] = nil end
        end
        return nil
    end
    if panel.hotkey == nil then createHotkeys(panel) end
    return root
end

function Launcher.Sync(panel)
    local root = Launcher.SyncLifecycle(panel)
    if root == nil then return end
    local binding = panel.controller:GetBinding()
    if binding ~= panel.binding then
        panel.binding = binding
        panel.hotkey:SetValue(SettingsHotkey.GetKeys(binding), false)
    end
    local notesBinding = panel.callbacks.getNotesHotkey()
    if notesBinding ~= panel.notesBinding then
        panel.notesBinding = notesBinding
        panel.notesHotkey:SetValue(Hotkeys.GetKeys(notesBinding), false)
    end
    local parent = root.parent
    local width = math.max(1, math.floor(parent.width))
    local height = math.max(1, math.floor(parent.height))
    local message = panel.status.content
    if width == panel.width and height == panel.height and message == panel.message then return end
    panel.width, panel.height, panel.message = width, height, message
    root:SetSize(width, height)
    panel.view:SetSize(width, height)
    for _ = 1, 2 do
        local contentWidth = panel.view.contentWidth
        local padding = math.min(12, math.floor((contentWidth - 1) / 2))
        local textWidth = math.max(1, math.min(360, contentWidth - padding * 2))
        local descriptionHeight = textHeight(panel, panel.description.content, textWidth)
        panel.description:SetPos(padding, 12)
        panel.description:SetSize(textWidth, descriptionHeight)
        panel.button.root:SetPos(padding, 24 + descriptionHeight)
        panel.button.root:SetSize(textWidth, 28)
        local labelY = 64 + descriptionHeight
        local labelHeight = textHeight(panel, panel.hotkeyLabel.content, textWidth)
        panel.hotkeyLabel:SetPos(padding, labelY)
        panel.hotkeyLabel:SetSize(textWidth, labelHeight)
        local fieldY = labelY + labelHeight + 4
        local stacked = textWidth < 220
        local clearWidth = math.min(76, textWidth)
        local fieldWidth = stacked and textWidth or textWidth - clearWidth - 8
        panel.hotkey.root:SetPos(padding, fieldY)
        panel.hotkey.root:SetSize(fieldWidth, 28)
        panel.clearButton.root:SetPos(stacked and padding or padding + fieldWidth + 8,
            stacked and fieldY + 36 or fieldY)
        panel.clearButton.root:SetSize(clearWidth, 28)
        local notesY = fieldY + (stacked and 76 or 40)
        panel.notesButton.root:SetPos(padding, notesY)
        panel.notesButton.root:SetSize(textWidth, 28)
        local notesLabelY = notesY + 40
        local notesLabelHeight = textHeight(panel, panel.notesHotkeyLabel.content, textWidth)
        panel.notesHotkeyLabel:SetPos(padding, notesLabelY)
        panel.notesHotkeyLabel:SetSize(textWidth, notesLabelHeight)
        local notesFieldY = notesLabelY + notesLabelHeight + 4
        panel.notesHotkey.root:SetPos(padding, notesFieldY)
        panel.notesHotkey.root:SetSize(fieldWidth, 28)
        panel.notesClearButton.root:SetPos(stacked and padding or padding + fieldWidth + 8,
            stacked and notesFieldY + 36 or notesFieldY)
        panel.notesClearButton.root:SetSize(clearWidth, 28)
        local statusY = notesFieldY + (stacked and 76 or 40)
        local statusHeight = textHeight(panel, message, textWidth)
        panel.status:SetPos(padding, statusY)
        panel.status:SetSize(textWidth, statusHeight)
        panel.view:SetContentHeight(statusY + statusHeight + 12)
        if panel.view.contentWidth == contentWidth then break end
    end
end

function Launcher.Mount(event, title, onOpen, controller, callbacks)
    local parent = SafeValues.Field(event, "component")
    if parent == nil then return nil end
    generation = generation + 1
    local root = Components.Host(parent)
    root:SetPos(0, 0)
    local panel = {root = root, active = true, controller = controller, callbacks = callbacks,
        interfaceID = root.interfaceID, staticID = root.staticID,
        categoryID = root.categoryID, dynamicID = root.dynamicID}
    local marker = Components.New(ui.Text, root)
    marker:SetSize(0, 0)
    marker.hidden, marker.clickthrough = true, true
    panel.token = title .. " settings:" .. generation .. ":" .. tostring(panel)
    marker.content = panel.token
    panel.markerCategory, panel.markerDynamic = marker.categoryID, marker.dynamicID
    panel.view = prettyui.SimpleView.new(root, Components.Options({width = 1, height = 1, contentHeight = 1}))
    local fontID = id.Font.NOTOSANS_13
    panel.fontID = fontID
    panel.font = config.Font.FromID(fontID)
    panel.description = prettyui.Text.new(panel.view.content, Components.Options({
        text = "Open " .. title .. " settings to configure the plugin.",
        font = fontID, colour = 0xD8D8D8FF
    }))
    panel.status = prettyui.Text.new(panel.view.content, Components.Options({text = "", font = fontID, colour = 0xD8D8D8FF}))
    panel.button = prettyui.SimpleButton.new(panel.view.content, "Open settings", function()
        if ownedRoot(panel) == nil then return end
        local message = onOpen()
        if ownedRoot(panel) == nil then return end
        panel.status.content = message or ""
        Launcher.Sync(panel)
    end, Components.Options({width = 1, height = 28}))
    panel.button.content.font = fontID
    panel.hotkeyLabel = prettyui.Text.new(panel.view.content, Components.Options({
        text = "Settings hotkey", font = fontID, colour = 0xD8D8D8FF
    }))
    createHotkeys(panel)
    panel.clearButton = prettyui.SimpleButton.new(panel.view.content, "Clear", function()
        if ownedRoot(panel) == nil then return end
        if panel.hotkey ~= nil then panel.hotkey:SetValue({}, true) end
    end, Components.Options({width = 1, height = 28}))
    panel.clearButton.content.font = fontID
    panel.notesButton = prettyui.SimpleButton.new(panel.view.content, "Open notes", function()
        if ownedRoot(panel) == nil then return end
        local message = callbacks.onOpenNotes()
        if ownedRoot(panel) == nil then return end
        panel.status.content = message or ""
        Launcher.Sync(panel)
    end, Components.Options({width = 1, height = 28}))
    panel.notesButton.content.font = fontID
    panel.notesHotkeyLabel = prettyui.Text.new(panel.view.content, Components.Options({
        text = "Notes window hotkey", font = fontID, colour = 0xD8D8D8FF
    }))
    panel.notesClearButton = prettyui.SimpleButton.new(panel.view.content, "Clear", function()
        if ownedRoot(panel) == nil then return end
        if panel.notesHotkey ~= nil then panel.notesHotkey:SetValue({}, true) end
    end, Components.Options({width = 1, height = 28}))
    panel.notesClearButton.content.font = fontID
    Launcher.Sync(panel)
    return panel
end

function Launcher.Destroy(panel)
    if panel == nil or not panel.active then return end
    local root = ownedRoot(panel)
    panel.active = false
    if root == nil then
        panel.button.root = nil
        panel.clearButton.root = nil
        if panel.hotkey ~= nil then panel.hotkey.root, panel.hotkey.input.root = nil, nil end
        panel.notesButton.root = nil
        panel.notesClearButton.root = nil
        if panel.notesHotkey ~= nil then panel.notesHotkey.root, panel.notesHotkey.input.root = nil, nil end
        panel.view.root, panel.view.thumbDrag = nil, nil
    end
    if panel.hotkey ~= nil then panel.hotkey:Destroy(); panel.hotkey = nil end
    panel.clearButton:Destroy()
    panel.button:Destroy()
    if panel.notesHotkey ~= nil then panel.notesHotkey:Destroy(); panel.notesHotkey = nil end
    panel.notesClearButton:Destroy()
    panel.notesButton:Destroy()
    panel.view:Destroy()
    if root ~= nil then root:Destroy() end
end

return Launcher
