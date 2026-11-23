local Layout = {}

function Layout.Measure(contentWidth, fontSize)
    contentWidth = math.max(1, math.floor(contentWidth))
    local gap = 12
    local minimumWidth = 240 * fontSize / 14
    local columns = math.max(1, math.min(4, math.floor((contentWidth + gap) / (minimumWidth + gap))))
    if columns == 1 then gap = 0 end
    return {columns = columns, gap = gap, contentWidth = contentWidth,
        cardWidth = math.max(1, math.floor((contentWidth - gap * (columns - 1)) / columns))}
end

function Layout.Arrange(rows, metrics)
    local y = 0
    for first = 1, #rows, metrics.columns do
        local last = math.min(#rows, first + metrics.columns - 1)
        local height = 1
        for index = first, last do height = math.max(height, rows[index].naturalHeight) end
        for index = first, last do
            local row = rows[index]
            row.column, row.band, row.columns = index - first + 1, math.floor((first - 1) / metrics.columns) + 1, metrics.columns
            row.x = (row.column - 1) * (metrics.cardWidth + metrics.gap)
            row.y, row.width, row.height = y, metrics.cardWidth, height
        end
        y = y + height + metrics.gap
    end
    return #rows == 0 and 0 or y - metrics.gap
end

function Layout.VisibleRange(rows, scroll, height, overscan)
    if #rows == 0 then return 1, 0 end
    local first, last = 1, #rows
    while first < last do
        local middle = math.floor((first + last) / 2)
        if rows[middle].y + rows[middle].height <= scroll then first = middle + 1 else last = middle end
    end
    local start, bottom = first, scroll + math.max(1, height)
    first, last = start, #rows
    while first < last do
        local middle = math.ceil((first + last) / 2)
        if rows[middle].y < bottom then first = middle else last = middle - 1 end
    end
    local columns = rows[start].columns or 1
    local margin = math.max(0, overscan or 1)
    return math.max(1, ((rows[start].band or 1) - margin - 1) * columns + 1),
        math.min(#rows, ((rows[first].band or 1) + margin) * columns)
end

function Layout.Hit(rows, x, y, includeActions)
    if type(x) ~= "number" or type(y) ~= "number" then return nil end
    for _, row in ipairs(rows) do
        local localX, localY = x - (row.x or 0), y - row.y
        if localX >= 0 and localX < row.width and localY >= 0 and localY < row.height then
            if not includeActions then
                if row.bodyWidth and localX >= row.bodyWidth then return nil end
                if row.bodyHeight and localY >= row.bodyHeight then return nil end
                for _, bounds in ipairs(row.actionBounds or {}) do
                    if localX >= bounds.x and localX < bounds.x + bounds.width
                        and localY >= bounds.y and localY < bounds.y + bounds.height then return nil end
                end
            end
            return row
        end
    end
    return nil
end

function Layout.Drop(rows, source, x, y)
    if #rows == 0 then return nil end
    local target, index, after
    local columns = source.columns or 1
    local lastRow = rows[#rows]
    if y >= lastRow.y + lastRow.height then
        target, index, after = lastRow, #rows, true
    elseif y < rows[1].y then
        target, index, after = rows[1], 1, false
    elseif columns == 1 then
        for candidateIndex, candidate in ipairs(rows) do
            target, index = candidate, candidateIndex
            if y < candidate.y + candidate.height / 2 then after = false; break end
            after = true
        end
    else
        local first = 1
        while first <= #rows do
            local last = first
            while last < #rows and rows[last + 1].y == rows[first].y do last = last + 1 end
            local nextRow = rows[last + 1]
            local bottom = rows[first].y + rows[first].height
            local boundary = nextRow and (bottom + nextRow.y) / 2 or math.huge
            if y < boundary then
                for candidateIndex = first, last do
                    local candidate = rows[candidateIndex]
                    local nextCandidate = candidateIndex < last and rows[candidateIndex + 1]
                    local right = (candidate.x or 0) + candidate.width
                    if not nextCandidate or x < (right + nextCandidate.x) / 2 then
                        target, index = candidate, candidateIndex
                        after = x >= (candidate.x or 0) + candidate.width / 2
                        break
                    end
                end
                break
            end
            first = last + 1
        end
    end
    local slot = index + (after and 1 or 0)
    local sourceIndex = source.position
    if sourceIndex < slot then slot = slot - 1 end
    local marker
    if columns == 1 then
        marker = {x = target.x or 0, y = target.y + (after and target.height or 0),
            width = target.bodyWidth or target.width, height = 2, vertical = false}
    else
        marker = {x = (target.x or 0) + (after and target.width or 0), y = target.y,
            width = 2, height = target.height, vertical = true}
    end
    return math.max(1, math.min(#rows, slot)), marker
end

return Layout
