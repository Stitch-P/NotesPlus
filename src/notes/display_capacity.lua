local Tracking = require("src/tracking/model")
local Capacity = {
    LIMIT = 4096, SAFE_PERCENT = 95, MANAGED_LIMIT = 234 * 235,
    MAX_VIEWPORT_HEIGHT = 1000 - 40 - 44 - 70, OVERSCAN_BANDS = 1,
    CARD_BASE_COMPONENTS = 11, CARD_HOSTS = 8, MAX_SUBTASKS = 5,
    DRAG_CARDS = 1, DRAG_COMPONENTS = 3
}
Capacity.BUDGET = math.floor(Capacity.LIMIT * Capacity.SAFE_PERCENT / 100)
Capacity.MANAGED_BUDGET = math.floor(Capacity.MANAGED_LIMIT * Capacity.SAFE_PERCENT / 100)

local SHELL = 347
local CATEGORY_ROW = 18
local TOOLTIP = 11
local RICH_TOOLTIP = 63
local PERK_TOOLTIP = 40
local MAX_VIEWPORT_HEIGHT = Capacity.MAX_VIEWPORT_HEIGHT
local MIN_CONTENT_WIDTH, MAX_CONTENT_WIDTH = 200 - 32 - 18, 1400 - 32 - 192 - 18
local summaries = setmetatable({}, {__mode = "k"})
local geometry = {}
local packingKey, packingCost

for size = 10, 24 do
    local minimum = 240 * size / 14
    local columns = math.max(1, math.min(4, math.floor((MAX_CONTENT_WIDTH + 12) / (minimum + 12))))
    local largestWidth = 0
    for count = 1, columns do
        local lastWidth = count == 4 and MAX_CONTENT_WIDTH
            or math.min(MAX_CONTENT_WIDTH, math.ceil((count + 1) * (minimum + 12) - 12) - 1)
        largestWidth = math.max(largestWidth, math.floor((lastWidth - (count - 1) * 12) / count))
    end
    geometry[size] = {columns = columns, width = largestWidth}
end

local function positive(value, fallback)
    return type(value) == "number" and value == value and value > 0 and value < math.huge and value or fallback
end

function Capacity.PoolLimit(viewportHeight, columns, showProgressBars, fontBaseline)
    columns = math.max(1, math.min(4, math.floor(positive(columns, 1))))
    local height = math.max(0, positive(viewportHeight, 0))
    local minimum = columns == 1 and 32 or showProgressBars == false and 60 or 100
    minimum = math.max(minimum, positive(fontBaseline, 1) + 14)
    -- Partly visible end bands and the overscan bands still own card controls.
    return columns * (math.ceil(height / minimum) + 1 + Capacity.OVERSCAN_BANDS * 2)
end

function Capacity.TextLineLimit(viewportHeight, fontBaseline)
    return math.ceil(math.max(0, positive(viewportHeight, 0)) / positive(fontBaseline, 1)) + 2
end

local function fontAt(size)
    local ok, font = pcall(function() return config.Font["NOTOSANS_" .. size] end)
    return ok and font or nil
end

local function fontBaseline(font)
    local ok, baseline = pcall(function() return font.baseline end)
    return ok and type(baseline) == "number" and baseline > 0 and baseline or nil
end

local function fontContext()
    local context = {fonts = {}, baselines = {}}
    local signature = {}
    for size = 10, 24 do
        local font = fontAt(size)
        context.fonts[size] = font
        context.baselines[size] = font and (fontBaseline(font) or true) or false
        signature[#signature + 1] = tostring(context.baselines[size])
    end
    context.signature = table.concat(signature, ":")
    return context
end

local function lineBound(note)
    local title, text = note.title or "", note.text or ""
    local expanded = title ~= "" and (title .. (text ~= "" and "\n" .. text or "")) or text
    if expanded == "" and note.gear then expanded = "Gear setup" end
    if expanded == "" and note.actionBar then expanded = "Action bar" end
    local collapsed = title ~= "" and title or "Untitled"
    return math.max(#expanded, #collapsed) + 1
end

local function detail(method, tracking)
    local ok, value = pcall(method, tracking)
    if not ok then return nil, Capacity.LIMIT end
    return value
end

local function stripTargets(items)
    local first = items[1]
    if not first then return false end
    local research = Tracking.CollectionFixedTarget(first.category, first.group) ~= nil
    local targets = first.category == "Invention" and not research or first.category == "Currencies"
        or first.category == "Ports" or first.category == "Skills"
    if not targets then
        for _, item in ipairs(items) do
            if Tracking.CollectionTargetEditable(item.category, item.group, item) then return true end
        end
    end
    return targets
end

local function stripRich(items)
    for _, item in ipairs(items) do
        local key = item.key
        if item.bossId or type(key) == "string" and (key:match("^camp%-") or key:match("^fort:")
            or key:match("^arch%-relic:") or key:match("^arch%-art:")) then return RICH_TOOLTIP end
    end
    return 0
end

local function rowCost(note, strips)
    local tracking = note.tracking
    local total = 0
    if note.gear then total = total + 11 end
    if note.actionBar then total = total + 11 end
    local subTasks, subError
    if tracking then subTasks, subError = detail(Tracking.SubTasks, tracking) end
    local subCount = type(subTasks) == "table" and #subTasks or 0
    if note.text ~= nil and note.text ~= "" or subCount > 0 then total = total + 12 end
    if not tracking then return total end
    total = total + 2 + math.min(Capacity.MAX_SUBTASKS, subCount) * 2 + (subError or 0)
    if subCount > Capacity.MAX_SUBTASKS then total = total + 3 end
    local requirements, reqError
    requirements, reqError = detail(Tracking.Requirements, tracking)
    total = total + (reqError or 0)
    if type(requirements) == "table" and #requirements > 0 then
        total = total + 1
        for _, need in ipairs(requirements) do
            total = total + ((need.kind == "skill" or need.kind == "item") and 3 or 2)
        end
    end
    local derived, derivedError
    if not tracking.items and (tracking.category == "Scheduled" or tracking.category == "Unlocks"
        or tracking.category == "Gathering") then
        derived, derivedError = detail(Tracking.DerivedItems, tracking)
    end
    total = total + (derivedError or 0)
    if derived or tracking.category == "Unlocks" and tracking.key == "reaper-crew" then
        local count = type(derived) == "table" and #derived or 8
        return total + 13 + 3 * math.max(1, math.min(7, count)) + (count > 7 and 3 or 0) + RICH_TOOLTIP
    end
    if type(tracking.items) == "table" then
        local ok, targets = pcall(stripTargets, tracking.items)
        if not ok then return total + Capacity.LIMIT end
        local first = tracking.items[1]
        local count = #tracking.items
        strips[#strips + 1] = {count = count, maximum = first and first.hideComplete and 7 or 32,
            height = targets and 82 or 44, cellCost = targets and 9 or 8,
            hoverCost = first and first.category == "Invention" and PERK_TOOLTIP or 0}
        total = total + 15 + stripRich(tracking.items)
    end
    return total
end

local function cellCount(strip, width)
    width = math.max(1, math.floor(width))
    local natural = strip.count * 40 + math.max(0, strip.count - 1) * 4
    local overflow = strip.count > strip.maximum or natural > width
    local navigation = overflow and width >= 24
    local gap = math.min(4, math.max(1, math.floor(width / 20)))
    local buttonWidth = math.min(16, math.max(6, math.floor(width / 5)))
    local available = math.max(1, width - (navigation and (buttonWidth + gap) * 2 or 0))
    local size = math.min(40, available)
    return math.max(1, math.min(strip.maximum, strip.count, math.floor((available + gap) / (size + gap))))
end

local function packedCost(entries, columns)
    table.sort(entries, function(left, right) return left.cost > right.cost end)
    local total, all = 0, 0
    for _, entry in ipairs(entries) do all = all + entry.cost * entry.copies end
    local boundary = columns * 2
    for _, entry in ipairs(entries) do
        local count = math.min(boundary, entry.copies)
        total, boundary = total + count * entry.cost, boundary - count
        if boundary == 0 then break end
    end
    local interior = {}
    for _, entry in ipairs(entries) do interior[#interior + 1] = entry end
    table.sort(interior, function(left, right) return left.cost / left.height > right.cost / right.height end)
    local room = columns * MAX_VIEWPORT_HEIGHT
    for _, entry in ipairs(interior) do
        if room <= 0 then break end
        local height = math.min(room, entry.height * entry.copies)
        total, room = total + entry.cost * height / entry.height, room - height
    end
    return math.min(all, math.ceil(total))
end

local function activeStripCost(strips, context)
    if #strips == 0 then return 0 end
    local grouped, keys = {}, {}
    for _, strip in ipairs(strips) do
        local key = table.concat({math.min(strip.count, strip.maximum + 1), strip.maximum,
            strip.height, strip.cellCost, strip.hoverCost}, ":")
        local group = grouped[key]
        if group then group.copies = group.copies + 1
        else grouped[key] = {strip = strip, copies = 1}; keys[#keys + 1] = key end
    end
    table.sort(keys)
    local signature = {context.signature}
    for _, key in ipairs(keys) do signature[#signature + 1] = key .. ":" .. grouped[key].copies end
    local key = table.concat(signature, "|")
    if packingKey == key then return packingCost end
    local greatest = 0
    for size = 10, 24 do
        local metrics = geometry[size]
        local baseline = type(context.baselines[size]) == "number" and context.baselines[size] or 1
        if metrics.baseline ~= baseline then
            metrics.baseline, metrics.heights = baseline, {}
            for columns = 1, metrics.columns do
                metrics.heights[columns] = 2 * baseline + 22 + (columns > 1 and 28 or 0)
            end
        end
        for columns = 1, metrics.columns do
            local entries = {}
            for _, name in ipairs(keys) do
                local group = grouped[name]
                local strip = group.strip
                local cells = cellCount(strip, metrics.width - 16)
                entries[#entries + 1] = {cost = 1 + cells * strip.cellCost + strip.hoverCost,
                    height = strip.height + metrics.heights[columns], copies = group.copies}
            end
            greatest = math.max(greatest, packedCost(entries, columns))
        end
    end
    packingKey, packingCost = key, greatest
    return greatest
end

function Capacity.Profile(data, settings)
    local notes, categories = data.notes or {}, data.categories or {}
    local context = fontContext()
    local extras, strips, totalText, largestText, largestExtra, largestStrip = {}, {}, 0, 0, 0, 0
    local gear, actionBar, rich = false, false, false
    for _, note in ipairs(notes) do
        gear, actionBar = gear or note.gear ~= nil, actionBar or note.actionBar ~= nil
        local tracking = note.tracking
        rich = rich or tracking ~= nil and (tracking.category == "Quests" or tracking.category == "Slayer")
        local firstStrip = #strips + 1
        local extra = rowCost(note, strips)
        local text = lineBound(note)
        extras[#extras + 1] = extra
        largestExtra, largestText = math.max(largestExtra, extra), math.max(largestText, text)
        totalText = totalText + text
        for index = firstStrip, #strips do
            local strip = strips[index]
            largestStrip = math.max(largestStrip, 1 + math.min(strip.maximum, strip.count) * strip.cellCost + strip.hoverCost)
        end
    end
    table.sort(extras, function(left, right) return left > right end)
    local prefix = {[0] = 0}
    for index, extra in ipairs(extras) do prefix[index] = prefix[index - 1] + extra end

    local categoryShell = SHELL + (#categories + 2) * CATEGORY_ROW
    local previews = (gear and 1 + TOOLTIP + 83 or 0) + (actionBar and 1 + TOOLTIP + 100 or 0)
        + (rich and RICH_TOOLTIP or 0)
    local shared = categoryShell + previews + (#notes == 0 and 1 or 0)
    local stripCost = activeStripCost(strips, context)
    local managed = type(prettyui) == "table" and type(prettyui.NewComponent) == "function"
    local height = MAX_VIEWPORT_HEIGHT
    if settings and positive(settings.notesHeight) then
        height = math.max(1, math.min(height, settings.notesHeight - 40 - 44 - 70))
    end
    local firstSize, lastSize = 10, 24
    if settings then
        firstSize = math.max(10, math.min(24, math.floor(positive(settings.fontSize, 14))))
        lastSize = firstSize
    end
    local best, bestRatio
    local peak = {category0 = 0, managed = 0, singleCard = 0, activeCards = 0, textLabels = 0}
    for size = firstSize, lastSize do
        local metrics = geometry[size]
        local maxColumns = metrics.columns
        if settings and positive(settings.notesWidth) then
            local width = math.min(1400, settings.notesWidth)
            local content = math.max(MIN_CONTENT_WIDTH, width - 32 - 18 - (width - 32 >= 480 and 192 or 0))
            maxColumns = math.max(1, math.min(4, math.floor((content + 12) / (240 * size / 14 + 12))))
        end
        local baseline = type(context.baselines[size]) == "number" and context.baselines[size] or 1
        for columns = 1, maxColumns do
            local cards = math.min(#notes, Capacity.PoolLimit(height, columns,
                settings and settings.showProgressBars ~= false or false, baseline) + Capacity.DRAG_CARDS)
            local text = math.min(totalText, Capacity.TextLineLimit(height, baseline) * columns + cards * 2)
            local optional = prefix[cards] or 0
            local drag = #notes > 0 and Capacity.DRAG_COMPONENTS or 0
            local category0 = (managed and categoryShell + cards * Capacity.CARD_HOSTS
                or shared + cards * Capacity.CARD_BASE_COMPONENTS + optional + text + stripCost) + drag
            local managedCount = managed and shared + cards * (Capacity.CARD_BASE_COMPONENTS - 1)
                + optional + text + stripCost + drag or 0
            -- A single card must remain bounded even with a larger allocation namespace.
            local single = #notes == 0 and 0 or Capacity.CARD_BASE_COMPONENTS + largestExtra + largestStrip
                + math.min(largestText, Capacity.TextLineLimit(height, baseline) + 2) + previews
            local ratio = math.max(category0 / Capacity.BUDGET,
                managedCount / Capacity.MANAGED_BUDGET, single / Capacity.BUDGET)
            peak.category0, peak.managed = math.max(peak.category0, category0), math.max(peak.managed, managedCount)
            peak.singleCard = math.max(peak.singleCard, single)
            if cards > peak.activeCards then
                peak.activeCards, peak.poolColumns, peak.poolFontSize = cards, columns, size
            end
            if text > peak.textLabels then
                peak.textLabels, peak.textColumns, peak.textFontSize, peak.textBaseline = text, columns, size, baseline
            end
            if not best or ratio > bestRatio then
                bestRatio = ratio
                best = {mode = managed and "managed" or "legacy", category0 = category0, managed = managedCount,
                    singleCard = single, category0Limit = Capacity.LIMIT, managedLimit = Capacity.MANAGED_LIMIT,
                    category0Budget = Capacity.BUDGET, managedBudget = Capacity.MANAGED_BUDGET,
                    singleCardBudget = Capacity.BUDGET, activeCards = cards, textLabels = text,
                    columns = columns, fontSize = size, viewportHeight = height}
            end
        end
    end
    for key, value in pairs(peak) do best[key] = value end
    best.estimate = math.ceil(bestRatio * Capacity.BUDGET)
    best.pressure = best.estimate / Capacity.LIMIT * 100
    summaries[data] = best
    return best
end

function Capacity.Estimate(data, settings)
    return Capacity.Profile(data, settings).estimate
end

function Capacity.Percentage(data, settings)
    return Capacity.Profile(data, settings).pressure
end

local function equal(left, right)
    if left == right then return true end
    if type(left) ~= "table" or type(right) ~= "table" then return false end
    for key, value in pairs(left) do if not equal(value, right[key]) then return false end end
    for key in pairs(right) do if left[key] == nil then return false end end
    return true
end

local function sameFootprint(left, right)
    return left.title == right.title and left.text == right.text
        and (left.skill ~= nil and left.skill ~= "") == (right.skill ~= nil and right.skill ~= "")
        and not not left.gear == not not right.gear and not not left.actionBar == not not right.actionBar
        and equal(left.tracking, right.tracking)
end

local function nonIncreasing(data, candidate)
    local previous, proposed = data.notes or {}, candidate.notes or {}
    if #proposed > #previous or #(candidate.categories or {}) > #(data.categories or {}) then return false end
    local old, new = summaries[data], summaries[candidate]
    for _, entry in ipairs({{"category0", "category0Budget"}, {"managed", "managedBudget"}, {"singleCard", "singleCardBudget"}}) do
        if new[entry[1]] > new[entry[2]] and new[entry[1]] > old[entry[1]] then return false end
    end
    if new.estimate <= old.estimate then return true end
    if #proposed == #previous then return false end
    local index = 1
    for _, note in ipairs(proposed) do
        while index <= #previous and not sameFootprint(previous[index], note) do index = index + 1 end
        if index > #previous then return false end
        index = index + 1
    end
    return true
end

function Capacity.Check(data, candidate, settings)
    local proposed = Capacity.Estimate(candidate, settings)
    if proposed <= Capacity.BUDGET then return true end
    Capacity.Estimate(data, settings)
    if nonIncreasing(data, candidate) then return true end
    return nil, "Display capacity would exceed 95%. Simplify complex notes or reduce the controls shown at once."
end

return Capacity
