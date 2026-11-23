local Components = require("src/ui/shared/components")
local Controls = {}

function Controls.Button(parent, text, x, y, width, height, action, colour)
    local button = prettyui.SimpleButton.new(parent, text, action, Components.Options({
        x = x, y = y, width = width, height = height,
        colour = (colour or 0xD8D8D8) * 256 + 255
    }))
    button.content.font = id.Font.NOTOSANS_13 or id.Font.MUSEO_SANS_13PT_REGULAR
    button.content:SetPos(2, 0)
    button.content:SetSize(-4, 0, 1.0, 1.0)
    return button
end

function Controls.SetTextColour(button, colour)
    button.textColour = colour * 256 + 255
    button.content.rgba = button.textColour
end

function Controls.Text(parent, text, x, y, width, height, colour, font)
    local label = prettyui.Text.new(parent, Components.Options({
        text = text, x = x, y = y, width = width, height = height,
        colour = (colour or 0xD8D8D8) * 256 + 255,
        font = font or id.Font.MUSEO_SANS_13PT_REGULAR,
        shadowed = false, maxLines = 1
    }))
    label.clickthrough = true
    return label
end

return Controls
