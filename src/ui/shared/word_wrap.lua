local WordWrap = {}

local function format(value, font, width, measure)
    local characters, breaks = {}, {}
    local lineStart, spaceIndex, spacePosition = 1, nil, nil
    width = math.max(1, width)
    for position, character in value:gmatch("()([%z\1-\127\194-\244][\128-\191]*)") do
        characters[#characters + 1] = character
        if character == "\n" or character == "\r" then
            lineStart, spaceIndex, spacePosition = position + 1, nil, nil
        else
            if character == " " or character == "\t" then
                spaceIndex, spacePosition = #characters, position
            end
            local finish = position + #character - 1
            local measured = measure and measure(lineStart, finish)
                or font:GetStringWidth(value:sub(lineStart, finish), true)
            if measured > width then
                if spaceIndex then

                    breaks[spacePosition] = characters[spaceIndex]
                    characters[spaceIndex] = "\n"
                    lineStart, spaceIndex, spacePosition = spacePosition + 1, nil, nil
                else

                    lineStart = position
                end
            end
        end
    end
    return table.concat(characters), breaks
end

function WordWrap.Format(value, font, width)
    return format(value, font, width)
end

function WordWrap.Read(previous, breaks, value)
    local prefix, suffix = 0, 0
    local common = math.min(#previous, #value)
    while prefix < common and previous:byte(prefix + 1) == value:byte(prefix + 1) do
        prefix = prefix + 1
    end
    while suffix < common - prefix and previous:byte(#previous - suffix) == value:byte(#value - suffix) do
        suffix = suffix + 1
    end
    local restore = {}
    for position, character in pairs(breaks) do
        if position <= prefix then restore[position] = character
        elseif position > #previous - suffix then restore[position + #value - #previous] = character end
    end
    return (value:gsub("()\n", function(position) return restore[position] or "\n" end)), restore
end

function WordWrap.Bind(field, initialValue)
    local getText, setText, onChange = field.GetText, field.SetText, field.onChange
    local previous, breaks = getText(field), {}
    local font, width
    local pending = initialValue
    local editing = false
    local logicalText = initialValue or previous
    local source, cachedFont, current, prior
    field.displayRevision = 0

    local function formatted(value, nextFont, nextWidth)
        nextWidth = math.max(1, nextWidth)
        if source ~= value or cachedFont ~= nextFont then
            source, cachedFont, current, prior = value, nextFont, nil, nil
        end
        if current and current.width == nextWidth then return current.text, current.breaks end
        if prior and prior.width == nextWidth then
            current, prior = prior, current
            return current.text, current.breaks
        end
        local measurements = {}
        local function measure(start, finish)
            local row = current and current.measurements[start]
            local measured = row and row[finish]
            if measured == nil then
                row = prior and prior.measurements[start]
                measured = row and row[finish]
            end
            if measured == nil then measured = nextFont:GetStringWidth(value:sub(start, finish), true) end
            row = measurements[start]
            if not row then row = {}; measurements[start] = row end
            row[finish] = measured
            return measured
        end
        local text, softBreaks = format(value, nextFont, nextWidth, measure)
        -- Two widths retain reusable text measurements without growing throughout a resize drag.
        prior, current = current, {width = nextWidth, text = text, breaks = softBreaks, measurements = measurements}
        return text, softBreaks
    end

    function field:GetText()
        if pending ~= nil then return pending end
        return (WordWrap.Read(previous, breaks, getText(self)))
    end

    function field:DisplayText(nextFont, nextWidth)
        if editing then return getText(self) end
        return (formatted(self:GetText(), nextFont, nextWidth))
    end

    function field:Wrap(nextFont, nextWidth)
        font, width = nextFont, nextWidth

        if editing then return end
        local value = self:GetText()
        pending = nil
        previous, breaks = formatted(value, font, width)
        if previous ~= getText(self) then setText(self, previous, false) end
    end

    function field:SetText(value, triggerCallback)
        local content = tostring(value or "")
        pending, editing = nil, false
        logicalText = content
        self.displayRevision = self.displayRevision + 1
        previous, breaks = content, {}
        if font then previous, breaks = formatted(content, font, width) end
        setText(self, previous, false)
        if triggerCallback and onChange then
            onChange(self, ui.InputFieldActionResult.CONTENT_CHANGE, content)
        end
    end

    function field.onChange(self, reason, value)
        local content, shiftedBreaks = WordWrap.Read(previous, breaks, value)
        previous, breaks = value, shiftedBreaks
        local wasEditing = editing
        if reason == ui.InputFieldActionResult.CONTENT_CHANGE then
            editing = true
        elseif reason == ui.InputFieldActionResult.SUBMIT_ON_FOCUS_LOSS
            or reason == ui.InputFieldActionResult.SUBMIT_ON_ESCAPE then
            editing = false
        end
        if content ~= logicalText or editing ~= wasEditing then self.displayRevision = self.displayRevision + 1 end
        logicalText = content
        if onChange then onChange(self, reason, content) end
    end
    return field
end

return WordWrap
