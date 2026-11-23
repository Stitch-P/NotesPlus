local Components = require("src/ui/shared/components")
local SafeValues = require("src/core/safe_values")

local AchievementPopupPositioner = {}
AchievementPopupPositioner.__index = AchievementPopupPositioner

local DEFAULT_PARENT_WIDTH = 765
local DEFAULT_PARENT_HEIGHT = 503

local function componentDimension(component, primary, secondary, fallback)
    local current = component
    for _ = 1, 4 do
        if current == nil then
            break
        end
        for _, field in ipairs({ primary, secondary }) do
            local ok, value = pcall(function()
                return current[field]
            end)
            if ok and type(value) == "function" then
                local methodOK, result = pcall(function()
                    return value(current)
                end)
                if not methodOK then
                    methodOK, result = pcall(value)
                end
                value = methodOK and result or nil
            end
            local numeric = ok and SafeValues.Number(value) or nil
            if numeric ~= nil and numeric > 1 then
                return math.floor(numeric)
            end
        end
        local ok, parent = pcall(function()
            return current.parent
        end)
        if not ok or parent == nil or parent == current then
            break
        end
        current = parent
    end
    return fallback
end

local function valueLooksMiddleButton(value)
    if value == nil then
        return false
    end
    local text = tostring(value):lower()
    return text == "middle"
        or text == "mousemiddle"
        or text == "middlemouse"
        or text == "mousebuttonmiddle"
        or text == "buttonmiddle"
        or text == "wheel"
        or text == "mousewheel"
        or text == "2"
end

local function eventIsMiddleMouse(...)
    local names = {
        "button", "Button", "buttonId", "ButtonId", "buttonID", "ButtonID",
        "buttonIndex", "ButtonIndex", "mouseButton", "MouseButton",
        "mouseButtonId", "MouseButtonId", "mouseButtonID", "MouseButtonID"
    }
    for index = 1, select("#", ...) do
        local argument = select(index, ...)
        if type(argument) == "string" and valueLooksMiddleButton(argument) then
            return true
        elseif type(argument) == "table" or type(argument) == "userdata" then
            for _, name in ipairs(names) do
                local ok, value = pcall(function()
                    return argument[name]
                end)
                if ok and valueLooksMiddleButton(value) then
                    return true
                end
            end
        end
    end
    return false
end

local function hookPosition(...)
    local count = select("#", ...)
    if count < 2 then
        return nil
    end
    local rawX = select(count - 1, ...)
    local rawY = select(count, ...)
    local x = SafeValues.Number(rawX)
    local y = SafeValues.Number(rawY)
    if x == nil or y == nil then
        return nil
    end
    return math.floor(x), math.floor(y)
end

local function moveToFront(component)
    if component ~= nil then
        pcall(function()
            component:MoveToFront()
        end)
    end
end

local function rootOf(preview)
    return preview and preview.root
end

local function destroyPreview(preview)
    if preview == nil then return end
    local ok, err = pcall(function() preview:Destroy() end)
    if not ok then log("Popup preview cleanup failed", tostring(err)) end
end

local function passThroughEvent()
    return false
end

local function swallowEvent()
    return true
end

function AchievementPopupPositioner.new(options)
    options = options or {}
    return setmetatable({
        options = options,
        active = false,
        blocker = nil,
        preview = nil,
        pendingX = nil,
        pendingY = nil,
        previewReady = false
    }, AchievementPopupPositioner)
end

function AchievementPopupPositioner:IsActive()
    return self.active == true
end

function AchievementPopupPositioner.ParentDetached(parent, fallback)
    if parent == nil then return fallback == true end
    local ok, gameArea, pluginLayer = pcall(function()
        return ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__GAME_AREA),
            ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
    end)
    if not ok then return fallback == true end
    return parent ~= gameArea and parent ~= pluginLayer
end

function AchievementPopupPositioner:_parent()
    if self.options.getParent == nil then
        return nil
    end
    local ok, parent = pcall(self.options.getParent)
    return ok and parent or nil
end

function AchievementPopupPositioner:_destroyBlocker()
    local blocker = self.blocker
    self.blocker = nil
    if blocker ~= nil then
        pcall(function()
            blocker:Destroy()
        end)
    end
end

function AchievementPopupPositioner:_destroyPreview()
    local preview = self.preview
    self.preview = nil
    destroyPreview(preview)
end


function AchievementPopupPositioner:_setPreviewPosition(x, y)
    local root = rootOf(self.preview)
    if root == nil then
        return false
    end
    local ok = pcall(function()
        root:SetPos(x, y, 0.5, 0)
        root.hidden = false
    end)
    if ok then
        self.pendingX = x
        self.pendingY = y
        self.previewReady = true
    end
    return ok
end

function AchievementPopupPositioner:_positionForMouse(mouseX, mouseY)
    local parent = self.nativeParent or self:_parent()
    local width = math.max(1, math.floor(SafeValues.Number(self.options.width) or 300))
    local height = math.max(1, math.floor(SafeValues.Number(self.options.height) or 92))
    local parentWidth = componentDimension(parent, "width", "Width", DEFAULT_PARENT_WIDTH)
    local parentHeight = componentDimension(parent, "height", "Height", DEFAULT_PARENT_HEIGHT)
    local left = math.floor(mouseX - width / 2)
    local top = math.floor(mouseY - height / 2)
    left = clamp(left, 0, math.max(0, parentWidth - width))
    top = clamp(top, 0, math.max(0, parentHeight - height))
    return left - math.floor(parentWidth / 2), top
end

function AchievementPopupPositioner:_follow(mouseX, mouseY)
    if not self.active or mouseX == nil or mouseY == nil then
        return false
    end
    local x, y = self:_positionForMouse(mouseX, mouseY)
    return self:_setPreviewPosition(x, y)
end

function AchievementPopupPositioner:_finish(mouseX, mouseY)
    if not self.active then
        return true
    end
    if mouseX == nil or mouseY == nil then
        return true
    end
    self:_follow(mouseX, mouseY)
    local x = self.pendingX
    local y = self.pendingY
    self.active = false
    self.previewReady = false
    self:_destroyBlocker()
    self:_destroyPreview()
    self.nativeParent = nil
    if x ~= nil and y ~= nil and self.options.commitPosition ~= nil then
        pcall(self.options.commitPosition, x, y)
    end
    if self.options.afterFinish ~= nil then
        pcall(self.options.afterFinish)
    end
    return true
end

function AchievementPopupPositioner:_createBlocker()
    local parent = self.nativeParent or self:_parent()
    if parent == nil or ui == nil then
        return nil
    end
    local blocker = nil
    if ui.Button ~= nil then
        blocker = Components.New(ui.Button, parent)
    elseif ui.GroupBox ~= nil then
        blocker = Components.New(ui.GroupBox, parent)
    elseif ui.Panel ~= nil then
        blocker = Components.New(ui.Panel, parent)
    end
    if blocker == nil then
        return nil
    end
    blocker:SetPos(0, 0)
    blocker:SetSize(0, 0, 1.0, 1.0)
    blocker.clickthrough = false
    pcall(function()
        blocker.text.content = " "
    end)
    pcall(function()
        blocker.alpha = 0.01
    end)
    if self.options.transparentColor ~= nil then
        local ok, color = pcall(self.options.transparentColor)
        if ok and color ~= nil then
            pcall(function()
                blocker.rgba = color
            end)
            pcall(function()
                blocker.colour = color
            end)
        end
    end
    local function followAtHookPosition(...)
        local mouseX, mouseY = hookPosition(...)
        if mouseX ~= nil and mouseY ~= nil then
            self:_follow(mouseX, mouseY)
        end
        return true
    end
    blocker:Subscribe(ui.Hook.ONMOUSEOVER, followAtHookPosition)
    blocker:Subscribe(ui.Hook.ONMOUSEREPEAT, followAtHookPosition)
    blocker:Subscribe(ui.Hook.ONCLICK, function(...)
        if eventIsMiddleMouse(...) then
            return false
        end
        local mouseX, mouseY = hookPosition(...)
        return self:_finish(mouseX, mouseY)
    end)
    blocker:Subscribe(ui.Hook.ONCLICKREPEAT, swallowEvent)
    blocker:Subscribe(ui.Hook.ONBUTTONPRESSED, swallowEvent)
    blocker:Subscribe(ui.Hook.ONHOLD, swallowEvent)
    blocker:Subscribe(ui.Hook.ONRELEASE, passThroughEvent)
    blocker:Subscribe(ui.Hook.ONDRAG, swallowEvent)
    blocker:Subscribe(ui.Hook.ONDRAGCOMPLETE, passThroughEvent)
    blocker:Subscribe(ui.Hook.ONSCROLLWHEEL, passThroughEvent)
    self.blocker = blocker
    return blocker
end

function AchievementPopupPositioner:Start()
    if self.active then
        return false
    end
    if self.options.canStart ~= nil then
        local ok, allowed = pcall(self.options.canStart)
        if not ok or allowed ~= true then
            return false
        end
    end
    local parent = self:_parent()
    if parent == nil then
        return false
    end
    if self.options.beforeStart ~= nil then
        local ok, allowed = pcall(self.options.beforeStart)
        if not ok or allowed == false then
            return false
        end
    end
    local x, y = 0, 0
    if self.options.getPosition ~= nil then
        local ok, savedX, savedY = pcall(self.options.getPosition)
        if ok then
            x = SafeValues.Number(savedX) or 0
            y = SafeValues.Number(savedY) or 0
        end
    end
    self.active = true
    self.nativeParent = parent
    self.pendingX = math.floor(x)
    self.pendingY = math.floor(y)
    self.previewReady = false
    local ok, preview = pcall(
        self.options.createPreview,
        self.pendingX,
        self.pendingY,
        parent
    )
    if not ok or preview == nil then
        self:Cancel(true)
        if not ok then error(preview) end
        return false
    end
    self.preview = preview
    local root = rootOf(preview)
    if root ~= nil then
        pcall(function()
            root.hidden = true
        end)
    end
    if self:_createBlocker() == nil then
        self:Cancel(true)
        return false
    end
    self:MoveToFront()
    return true
end

function AchievementPopupPositioner:Cancel(reopenMenu)
    local wasActive = self.active
    self.active = false
    self.pendingX = nil
    self.pendingY = nil
    self.previewReady = false
    self:_destroyBlocker()
    self:_destroyPreview()
    self.nativeParent = nil
    if wasActive and reopenMenu == true and self.options.afterCancel ~= nil then
        pcall(self.options.afterCancel)
    end
end

function AchievementPopupPositioner:Sync()
    if self.active and AchievementPopupPositioner.ParentDetached(self.nativeParent) then
        self:Destroy(true)
        return false
    end
    if not self.active then
        self:_destroyBlocker()
        return
    end
    if self.blocker == nil and self:_createBlocker() == nil then
        self:Cancel(true)
        return
    end
    self:MoveToFront()
end

function AchievementPopupPositioner:MoveToFront()
    if not self.active then
        return
    end
    moveToFront(rootOf(self.preview))
    moveToFront(self.blocker)
end

function AchievementPopupPositioner:Destroy(detached)
    if AchievementPopupPositioner.ParentDetached(self.nativeParent, detached) then
        self.blocker = nil
        if self.preview then self.preview.root = nil end
    end
    self:Cancel(false)
    self.nativeParent = nil
    self.options = {}
end

return AchievementPopupPositioner
