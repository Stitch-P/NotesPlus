local TextLayout = require("src/ui/shared/text_layout")

local Content = {}

local function measuredText(text, font, width)
    local lines = TextLayout.Lines(text or "", font, width)
    return table.concat(lines, "<br>"), #lines * font.baseline + 2, lines
end

local function requirementPlan(built, font, textX, textWidth, progress, progressY, progressHeight)
    if not built or #built.items == 0 then return nil, progressY + progressHeight end
    local size = built.size
    local limit = textX + textWidth
    local left = math.min(textX, math.max(8, limit - size))
    local width = math.max(1, limit - left)
    local prefixText, prefixHeight, prefixLines = measuredText("Requires:", font, width)
    local prefixWidth = math.min(width, font:GetStringWidth("Requires:", true) + 6)
    local total = prefixWidth
    for _, item in ipairs(built.items) do
        total = total + size + 2 + (item.textWidth and item.textWidth + 4 or size) + 10
    end
    local progressLines = TextLayout.Lines(progress or "", font, textWidth)
    local inlineX = textX + font:GetStringWidth(progress or "", true) + 8
    local inline = #progressLines == 1 and inlineX + total <= limit
    local x, y = inline and inlineX or left, inline and progressY or progressY + progressHeight + 4
    local result = {prefix = {x = x, y = y, width = prefixWidth, height = prefixHeight,
        text = prefixText, hidden = false}, items = {}}
    local rowHeight = prefixHeight
    x = x + prefixWidth
    if #prefixLines > 1 then x, y, rowHeight = left, y + prefixHeight + 4, 0 end
    for index, item in ipairs(built.items) do
        local valueWidth = item.textWidth and item.textWidth + 4 or size
        local itemWidth = size + 2 + valueWidth
        local stacked = itemWidth > width
        local text, textHeight
        if item.textWidth then
            text, textHeight = measuredText(item.text or "", font, stacked and width or valueWidth)
        else textHeight = size + 2 end
        local itemHeight = stacked and size + 2 + textHeight or math.max(size + 2, textHeight)
        itemWidth = stacked and math.max(size, math.min(width, valueWidth)) or itemWidth
        if x > left and x + itemWidth > limit then
            x, y, rowHeight = left, y + rowHeight + 4, 0
        end
        local valueX, valueY = stacked and x or x + size + 2, stacked and y + size + 2 or y
        result.items[index] = {x = x, y = y, width = itemWidth, height = itemHeight,
            textX = valueX, textY = valueY, textWidth = stacked and width or valueWidth,
            textHeight = textHeight, text = text, markX = valueX, markY = valueY}
        x = x + itemWidth + 10
        rowHeight = math.max(rowHeight, itemHeight)
    end
    return result, math.max(progressY + progressHeight, y + rowHeight)
end

-- How the sub-tasks of a multi-part task are laid out at this width: two per
-- line when every one fits in half the row, otherwise one per line.
local function subTaskPlan(list, font, textWidth)
    local columnWidth = math.max(1, math.floor((textWidth - 6) / 2) - 6)
    local twoColumns = true
    for _, sub in ipairs(list) do
        if #TextLayout.Lines("- " .. sub.text, font, columnWidth) > 1 then twoColumns = false break end
    end
    return twoColumns and 2 or 1
end

-- Position and text of sub-task number `index` under the progress text.
local function subTaskSlots(list, font, textX, textWidth, startY)
    local columns = subTaskPlan(list, font, textWidth)
    local half = math.floor((textWidth - 6) / 2)
    local inset = math.min(6, math.max(0, textWidth - 1))
    local slots, bottom = {}, startY
    for index, sub in ipairs(list) do
        local column = columns == 2 and (index - 1) % 2 or 0
        local width = columns == 2 and math.max(1, half - 6) or math.max(1, textWidth - inset)
        local text, height = measuredText("- " .. sub.text, font, width)
        local y = columns == 2 and startY + math.floor((index - 1) / 2) * (font.baseline + 2) or bottom
        slots[index] = {x = textX + inset + column * half, y = y, width = width, height = height, text = text}
        bottom = math.max(bottom, y + height)
    end
    return slots, bottom
end

function Content.Plan(row, font, textWidth, iconSize, footerActions, cardWidth, showProgressBars)
    textWidth = math.max(1, textWidth)
    local lines = TextLayout.Lines(row.text or "", font, textWidth)
    local baseHeight = math.max(32, #lines * font.baseline + 14,
        row.hasIcon and iconSize and iconSize + 12 or 0)
    local plan = {lines = lines, textWidth = textWidth, progressY = #lines * font.baseline + 8,
        progressHeight = 0, progressText = "", subtasks = {}, footerHeight = footerActions and 28 or 0}
    local bodyHeight = baseHeight
    if row.progress then
        -- A compact note shows a one-line summary in place of the full progress text.
        local shown = row.compactText or row.progress.text
        plan.progressText, plan.progressHeight = measuredText(shown or "", font, textWidth)
        local bottom = plan.progressY + plan.progressHeight
        plan.requirements, bottom = requirementPlan(row.reqs, font, row.textX, textWidth,
            shown, plan.progressY, plan.progressHeight)
        if row.subTasks and #row.subTasks > 0 then
            plan.subtasks, bottom = subTaskSlots(row.subTasks, font, row.textX, textWidth, bottom + 2)
            -- More steps than fit: a "< 6-9 of 9 >" line pages through them.
            if row.subPageCount and row.subPageCount > 1 then
                local text = row.subFirst .. "-" .. row.subLast .. " of " .. row.subTotal
                local height = 26
                plan.subPager = {x = row.textX, y = bottom + 2, width = textWidth, height = height, text = text,
                    canPrevious = row.subPageIndex > 1, canNext = row.subPageIndex < row.subPageCount}
                bottom = plan.subPager.y + height
            end
        end
        if row.itemStrip then
            local stripWidth = math.max(1, (cardWidth or row.textX + textWidth + 8) - 16)
            local stripHeight = row.itemStrip.HeightFor and row.itemStrip:HeightFor(stripWidth) or row.itemStrip.height
            if stripHeight > 0 then
                plan.itemStrip = {x = 8, y = bottom + 6, width = stripWidth, height = stripHeight}
                bottom = plan.itemStrip.y + stripHeight
            end
        end
        if showProgressBars == false then bodyHeight = math.max(baseHeight, bottom + 6)
        else bodyHeight = math.max(baseHeight + font.baseline + 13, bottom + 17) end
    end
    plan.height = math.max(footerActions and showProgressBars ~= false and 100 or 32, bodyHeight + plan.footerHeight)
    plan.naturalHeight = plan.height
    plan.bodyHeight = plan.height - plan.footerHeight
    plan.contentHeight = plan.bodyHeight
    plan.progressBarY = plan.bodyHeight - 12
    return plan
end

return Content
