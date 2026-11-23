local Components = require("src/ui/shared/components")
local WindowStyle = {}
local activeTooltip = setmetatable({}, {__mode = "v"})

function WindowStyle.New(parent, options)
    local configured = Components.Options(options)
    local showClose = configured.hideCloseButton ~= true
    configured.hideCloseButton = true
    local window = prettyui.Window.new(parent, configured)
    if not showClose or window.closeButton then return window end

    local ok, reason = pcall(function()
        if window.titleRight then
            window.titleCentreRight:SetPos(-128, 0, 1)
            window.titleCentreRight:SetSize(64, 32)
            window.titleCentreRight.isTiling = false
            window.titleRight.spriteID = id.Sprite.RS3_MODAL_WINDOW_1_CLOSE_CORNER
            window.titleRight.isFlippedHorizontally = false
            window.titleRight:SetPos(-64, 0, 1)
            window.titleRight:SetSize(64, 32)
        end
        -- Explicit allocation avoids relying on policy inherited through native parent handles.
        local button = Components.New(ui.Layer, window.root, {x = -28, y = 7, xAnchor = 1, width = 20, height = 20})
        local icon = Components.New(ui.Sprite, button, {x = 1, y = 1, width = 18, height = 18})
        window.closeButton, window.closeSprite = button, icon
        button.clickthrough, icon.clickthrough = false, true
        icon.spriteID = id.Sprite.RS3_BTN_MODAL_WINDOW_1_CLOSE_NML
        button:Subscribe(ui.Hook.ONMOUSEOVER, function()
            icon.spriteID = id.Sprite.RS3_BTN_MODAL_WINDOW_1_CLOSE_OVR
        end)
        button:Subscribe(ui.Hook.ONMOUSELEAVE, function()
            icon.spriteID = id.Sprite.RS3_BTN_MODAL_WINDOW_1_CLOSE_NML
        end)
        button:Subscribe(ui.Hook.ONCLICK, function()
            window:Close()
            return false
        end)
        button:MoveToFront()
        window.hideCloseButton = false
    end)
    if not ok then
        pcall(function() window:Destroy() end)
        error(reason, 0)
    end
    return window
end

function WindowStyle.ApplyInput(input)
    input.stylesheetID = id.StyleSheet.INPUT_DEFAULT_LEGACY
    input.containerSprite.rgba = 0xFFFFFFFF
end

function WindowStyle.ApplyTooltip(tooltip, dismiss)
    if tooltip == nil or tooltip.notesStyleShow then return end
    local show = tooltip.Show
    tooltip.notesStyleShow = show
    tooltip.notesStyleDismiss = dismiss or tooltip.Hide
    function tooltip:Show(...)
        local previous = activeTooltip[1]
        if previous ~= self then
            if self.target == nil or ui.Interfaces:GetInterface(self.interfaceID) == nil
                or ui.Interfaces:GetInterface(self.targetInterfaceID) == nil then return end
            if previous then previous:notesStyleDismiss() end
            activeTooltip[1] = self
        end
        show(self, ...)
        local parts = rawget(self, "_parts")
        if parts and not parts.notesStyleApplied then
            parts.centre.spriteID = id.Sprite.RS3_MODAL_WINDOW_CONTENT_TILE
            parts.centre:MoveToBack()
            parts.notesStyleApplied = true
        end
    end
end

return WindowStyle
