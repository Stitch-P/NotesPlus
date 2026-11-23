local Components = require("src/ui/shared/components")
local Preview = {}
Preview.__index = Preview

local BORDER = 4
local TITLE_HEIGHT = 24

local function sprite(parent, spriteID, x, y, width, height, xAnchor, yAnchor, widthAnchor, heightAnchor)
    local component = Components.New(ui.Sprite, parent)
    component.spriteID = spriteID
    component:SetPos(x, y, xAnchor or 0, yAnchor or 0)
    component:SetSize(width, height, widthAnchor or 0, heightAnchor or 0)
    component.clickthrough = true
    return component
end

local function text(parent, value, font, colour, x, y, width, height, widthAnchor, heightAnchor, maxLines)
    local component = Components.New(ui.Text, parent)
    component:SetPos(x, y)
    component:SetSize(width, height, widthAnchor or 0, heightAnchor or 0)
    component.content = value
    component.font = font
    component.rgba = colour
    component.alignHorizontal = ui.AlignMode.CENTRE
    component.alignVertical = ui.AlignMode.CENTRE
    component.maxLines = maxLines
    component.isShadowed = true
    component.clickthrough = true
    return component
end

function Preview.new(options)
    local self = setmetatable({interfaceID = options.parent.interfaceID}, Preview)
    self.root = Components.New(ui.Layer, options.parent)
    local ok, reason = pcall(function()
        self.root:SetPos(options.x, options.y, options.xAnchor, 0)
        self.root:SetSize(options.width, options.height)
        self.root.alpha = 1
        self.root.clickthrough = true
        local frame = prettyui.Sprites.HUD_WINDOW
        self.backgroundTexture = sprite(self.root, frame.content, BORDER, BORDER,
            -BORDER * 2, -BORDER * 2, 0, 0, 1, 1)
        self.backgroundTexture.isTiling = true
        self.top = sprite(self.root, frame.top, BORDER, 0, -BORDER * 2, BORDER, 0, 0, 1)
        self.bottom = sprite(self.root, frame.bottom, BORDER, -BORDER, -BORDER * 2, BORDER, 0, 1, 1)
        self.left = sprite(self.root, frame.side, 0, BORDER, BORDER, -BORDER * 2, 0, 0, 0, 1)
        self.right = sprite(self.root, frame.side, -BORDER, BORDER, BORDER, -BORDER * 2, 1, 0, 0, 1)
        for _, edge in ipairs({self.top, self.bottom, self.left, self.right}) do edge.isTiling = true end
        self.right.isFlippedHorizontally = true
        self.topLeft = sprite(self.root, frame.cornerTop, 0, 0, BORDER, BORDER)
        self.topRight = sprite(self.root, frame.cornerTop, -BORDER, 0, BORDER, BORDER, 1)
        self.bottomLeft = sprite(self.root, frame.cornerBottom, 0, -BORDER, BORDER, BORDER, 0, 1)
        self.bottomRight = sprite(self.root, frame.cornerBottom, -BORDER, -BORDER, BORDER, BORDER, 1, 1)
        self.topRight.isFlippedHorizontally = true
        self.bottomRight.isFlippedHorizontally = true
        self.title = text(self.root, options.title, id.Font.CINZEL_13PT_BOLD, 0xF1C384FF,
            BORDER + 4, 6, -(BORDER * 2 + 8), TITLE_HEIGHT, 1, 0, 1)
        self.text = text(self.root, options.text, id.Font.MUSEO_SANS_11PT_REGULAR, 0xFFFFFFFF,
            BORDER + 6, TITLE_HEIGHT, -(BORDER * 2 + 12), -(TITLE_HEIGHT + BORDER), 1, 1, 0)
        self.root:MoveToFront()
    end)
    if not ok then self:Destroy(); error(reason) end
    return self
end

function Preview:Destroy()
    local root = self.root
    self.root = nil
    if root and ui.Interfaces:GetInterface(self.interfaceID) ~= nil then root:Destroy() end
end

return Preview
