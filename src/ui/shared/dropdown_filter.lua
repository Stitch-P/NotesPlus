local DropdownFilter = {}

local function visibleEntries(control)
    local result = {}
    for _, entry in ipairs(control.entries) do
        if entry.visible then
            result[#result + 1] = {id = entry.id, label = entry.label}
        end
    end
    return result
end

local function sameEntries(left, right)
    if #left ~= #right then return false end
    for index, entry in ipairs(left) do
        if entry.id ~= right[index].id or entry.label ~= right[index].label then return false end
    end
    return true
end

function DropdownFilter.Batch(combo)
    local displayed = visibleEntries(combo)
    local setEntries, clear = combo.SetEntries, combo.Clear

    -- The box shows its choice in an input field, which prints colour tags as they are. An entry carrying the game's colours
    -- (titles) shows its plain text there, made invisible, with a text label on top that draws every colour. When the list
    -- opens (the field is emptied) the label goes away. If the label can't be made, the plain text takes the first colour.
    local setInput = combo._SetInput
    local baseColour = combo.input and combo.input.text and combo.input.text.rgba
    if setInput and baseColour then
        local overlay
        local function overlayLabel(control)
            if overlay == nil then
                local ok, label = pcall(function()
                    local text = ui.Text.new(control.root)
                    text:SetPos(8, 0)
                    text:SetSize(-32, 0, 1.0, 1.0)
                    text.font = control.input.text.font
                    text.rgba = baseColour
                    text.isShadowed = true
                    text.alignHorizontal = ui.AlignMode.TOPLEFT
                    text.alignVertical = ui.AlignMode.CENTRE
                    text.maxLines = 1
                    text.clickthrough = true
                    return text
                end)
                overlay = ok and label or false
            end
            return overlay or nil
        end
        combo._SetInput = function(control, value)
            local text = tostring(value or "")
            local tagged = text:find("<", 1, true) ~= nil
            setInput(control, (text:gsub("<[^>]*>", "")))
            local label = tagged and overlayLabel(control) or overlay or nil
            if label then
                label.hidden = not tagged
                if tagged then label.content = text end
            end
            if tagged and label then
                control.input.text.rgba = 0x00000000
            else
                local hex = text:match("<col=0?x?(%x%x%x%x%x%x)>")
                control.input.text.rgba = hex and (tonumber(hex, 16) * 256 + 255) or baseColour
            end
        end
    end

    combo.SetEntries = function(control, values, selectedID)
        setEntries(control, values, selectedID)
        displayed = visibleEntries(control)
    end

    combo.Clear = function(control)
        clear(control)
        displayed = {}
    end

    combo._Filter = function(control, value)
        local query = string.lower(tostring(value or ""))
        for _, entry in ipairs(control.entries) do
            -- Colour tags in a label are not part of the text that is searched.
            entry.visible = query == ""
                or string.find(string.lower((entry.label:gsub("<[^>]*>", ""))), query, 1, true) ~= nil
        end
        local filtered = visibleEntries(control)
        -- Per-entry visibility updates recreate the list's rows, so update once per result set.
        if not sameEntries(displayed, filtered) then
            control.dropdown:SetEntries(filtered)
            displayed = filtered
        end
        local selected = control.entriesByID[control.selectedID]
        if selected and selected.visible then
            control.dropdown:SetSelected(selected.id, true, false)
        end
        control:_LayoutDropdown()
    end
    return combo
end

return DropdownFilter
