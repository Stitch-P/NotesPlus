local Components = require("src/ui/shared/components")
local NativeRibbonIcon = {}
NativeRibbonIcon.__index = NativeRibbonIcon

local BUTTON_LAYER = id.Component.TOPLEVEL_V2_PLUGIN_CONTENT__PLUGIN_BUTTONS_LAYER

local function labelOf(component)
    local ok, value = pcall(function() return component.text.content end)
    if not ok or value == nil then return "" end
    return tostring(value):gsub("<[^>]->", ""):match("^%s*(.-)%s*$")
end

function NativeRibbonIcon.New(label, spriteID)
    return setmetatable({
        label = label,
        spriteID = spriteID,
        iconCategory = nil,
        iconDynamic = nil,
        buttonCategory = nil,
        buttonDynamic = nil,
        originalAlpha = nil,
        lastError = nil
    }, NativeRibbonIcon)
end

function NativeRibbonIcon:GetIcon(layer)
    if self.iconCategory == nil then return nil end
    local icon = layer:GetChild(self.iconCategory, self.iconDynamic)
    local ok, matches = pcall(function() return icon ~= nil and icon.spriteID == self.spriteID end)
    if ok and matches then return icon end
    self.iconCategory = nil
    self.iconDynamic = nil
    return nil
end

function NativeRibbonIcon:DeleteIcon(layer)
    if self:GetIcon(layer) ~= nil then
        layer:Delete(self.iconCategory, self.iconDynamic)
    end
    self.iconCategory = nil
    self.iconDynamic = nil
end

function NativeRibbonIcon:RestoreLabel(layer)
    if self.buttonCategory ~= nil then
        local button = layer:GetChild(self.buttonCategory, self.buttonDynamic)
        if button ~= nil and labelOf(button) == self.label and button.text.alpha == 0 then
            button.text.alpha = self.originalAlpha or 1
        end
    end
    self.buttonCategory = nil
    self.buttonDynamic = nil
    self.originalAlpha = nil
end

function NativeRibbonIcon:IsVisible()
    local ok, visible = pcall(function()
        local layer = ui.Interfaces:GetComponent(BUTTON_LAYER)
        return layer ~= nil and layer.visibleGlobal == true
    end)
    return ok and visible == true
end

function NativeRibbonIcon:Draw()
    if self.spriteID == nil then return end

    local ok, err = pcall(function()
        local layer = ui.Interfaces:GetComponent(BUTTON_LAYER)
        if layer == nil then
            self.iconCategory = nil
            self.iconDynamic = nil
            self.buttonCategory = nil
            self.buttonDynamic = nil
            self.originalAlpha = nil
            return
        end

        local button = self.buttonCategory ~= nil
            and layer:GetChild(self.buttonCategory, self.buttonDynamic) or nil
        if button == nil or labelOf(button) ~= self.label then
            button = nil
            layer:IterateDynamicComponents(function(component)
                if labelOf(component) == self.label then
                    button = component
                    return true
                end
                return false
            end)
        end

        if button == nil then
            self:RestoreLabel(layer)
            self:DeleteIcon(layer)
            return
        end
        if self.buttonCategory ~= button.categoryID or self.buttonDynamic ~= button.dynamicID then
            self:RestoreLabel(layer)
        end

        local icon = self:GetIcon(layer)
        if icon == nil then
            icon = Components.New(ui.Sprite, layer)
            local configured, configError = pcall(function()
                icon.sprite = self.spriteID
                icon.clickthrough = true
            end)
            if not configured then
                icon:Destroy()
                error(configError)
            end
            self.iconCategory = icon.categoryID
            self.iconDynamic = icon.dynamicID
            icon:MoveToFront()
        end
        local size = math.max(1, math.min(20, button.width - 4, button.height - 4))
        local x = button.x + math.floor((button.width - size) / 2)
        local y = button.y + math.floor((button.height - size) / 2)
        if icon.width ~= size or icon.height ~= size then icon:SetSize(size, size) end
        if icon.x ~= x or icon.y ~= y then icon:SetPos(x, y) end
        local hidden = not button.visibleGlobal
        if icon.hidden ~= hidden then icon.hidden = hidden end

        self.buttonCategory = button.categoryID
        self.buttonDynamic = button.dynamicID
        if self.originalAlpha == nil or button.text.alpha ~= 0 then
            self.originalAlpha = button.text.alpha
        end
        if button.text.alpha ~= 0 then button.text.alpha = 0 end
    end)
    if not ok then
        self:Stop()
        if self.lastError ~= tostring(err) then
            log("Ribbon icon " .. self.label .. ": could not update sprite", tostring(err))
            self.lastError = tostring(err)
        end
    else
        self.lastError = nil
    end
end

function NativeRibbonIcon:Stop()
    pcall(function()
        local layer = ui.Interfaces:GetComponent(BUTTON_LAYER)
        if layer == nil then return end
        self:RestoreLabel(layer)
        self:DeleteIcon(layer)
    end)
    self.iconCategory = nil
    self.iconDynamic = nil
    self.buttonCategory = nil
    self.buttonDynamic = nil
    self.originalAlpha = nil
end

return NativeRibbonIcon
