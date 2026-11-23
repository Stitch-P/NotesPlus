local Components = require("src/ui/shared/components")
-- The quest hover text with item icons: the quest's text, then what it needs and what it gives, one row per item
-- (the item's icon and its name). Lives inside the note list's own tooltip, like the Invention perk tooltip.

local QuestTooltip = {}
local MAX_ROWS = 12
local MODEL_HEIGHT = 120
local MODEL_GAP = 12
local MIN_BODY_WIDTH = 160
local DEFAULT_ZOOM = 1000
-- The game's zoom values frame the model for its own (larger) component; this pulls the camera back so a full figure fits,
-- and shifts it down a little because the models sit high in the box.
local ZOOM_OUT = 1.4     -- monsters with no zoom of their own (Slayer tasks): a small, whole figure
local ZOOM_OUT_OWN = 1.6 -- the game's own zoom (Reaper bosses), pulled back to a small, whole figure
local FONT = id.Font.MUSEO_SANS_13PT_REGULAR

local function text(parent, colour)
    local label = prettyui.Text.new(parent, Components.Options({text = "", width = 1, height = 20,
        colour = colour or 0xFFFFFFFF, font = FONT, shadowed = false, maxLines = 0}))
    label.clickthrough = true
    label.hidden = true
    return label
end

local function sprite(parent)
    local icon = Components.New(ui.Sprite, parent)
    icon:SetSize(18, 18)
    icon.clickthrough = true
    icon.hidden = true
    return icon
end

local function measure(value, width)
    local ok, font = pcall(function() return config.Font.FromID(FONT) end)
    if ok and font then
        local measured, height = pcall(function()
            return font:GetStringHeightAndLineCount(value, math.max(1, width), font.baseline, false, false, false)
        end)
        if measured and type(height) == "number" then return math.max(20, math.ceil(height)) end
    end
    return math.max(20, math.ceil(#value * 7 / math.max(1, width)) * 18)
end

local function plain(value)
    return tostring(value or ""):gsub("<[Bb][Rr]%s*/?>", " "):gsub("<", "["):gsub(">", "]"):gsub("[%c]", " ")
end

local function construct(tooltip, state, build)
    local ok, result = pcall(build)
    if not ok then
        if state.root then state.root:Destroy() end
        tooltip.questParts, tooltip.questKey, tooltip.questWidth = nil, nil, nil
        if tooltip.label then tooltip.label.hidden = false end
        error(result, 0)
    end
    return result
end

function QuestTooltip.Prepare(tooltip)
    if not tooltip or not tooltip.root then return false end
    if tooltip.questParts then return true end
    local state = {extras = {}, sections = {}}
    return construct(tooltip, state, function()
        state.root = Components.Host(tooltip.root)
        state.root.clickthrough, state.root.hidden = true, true
        state.body = text(state.root)
        tooltip.questParts = state
        return true
    end)
end

local function prepareParts(tooltip, state, parts)
    construct(tooltip, state, function()
        if parts.model and not state.modelAttempted then
            state.modelAttempted = true
            local ok, model = pcall(function() return Components.New(ui.Model, state.root) end)
            if ok and model then
                state.model = model
                model.clickthrough, model.hidden = true, true
            end
        end
        for index = 1, math.min(3, #(parts.extraRows or {})) do
            if not state.extras[index] then
                state.extras[index] = {icon = sprite(state.root), label = text(state.root)}
            end
        end
        for _, name in ipairs({"needs", "rewards", "codex"}) do
            local rows, body
            if name == "needs" then rows, body = parts.needRows, parts.needText
            elseif name == "codex" then rows = parts.codexRows
            else rows, body = parts.rewardRows, parts.rewardText end
            rows = rows or {}
            if body or #rows > 0 then
                local section = state.sections[name]
                if not section then
                    section = {divider = prettyui.Divider.new(state.root, Components.Options({width = 1})),
                        heading = text(state.root, 0xE7D7B0FF), rows = {}}
                    section.divider.root:SetSize(1, 4)
                    section.divider.root.hidden = true
                    state.sections[name] = section
                end
                if body and not section.text then section.text = text(state.root) end
                for index = 1, math.min(MAX_ROWS, #rows) do
                    if not section.rows[index] then
                        section.rows[index] = {icon = sprite(state.root), label = text(state.root)}
                    end
                end
            end
        end
    end)
end

function QuestTooltip.Clear(tooltip)
    local state = tooltip and tooltip.questParts
    if state and state.root and not state.root.hidden then state.root.hidden = true end
    if tooltip then tooltip.questKey, tooltip.questWidth = nil, nil end
    if tooltip and tooltip.label then tooltip.label.hidden = false end
end

-- parts: Tracking.QuestTooltip(...). Returns true when the tooltip is showing it.
function QuestTooltip.Set(tooltip, parts, maxWidth)
    if not tooltip or not tooltip.root or type(parts) ~= "table" then return false end
    local state = tooltip.questParts
    if not state then return false end
    local width = math.max(200, math.min(maxWidth or 360, 360))
    local parentWidth = tooltip.parent and tooltip.parent.width or 0
    if parentWidth > 0 then width = math.min(width, math.max(1, parentWidth - 12)) end
    if tooltip.questKey == parts.key and tooltip.questWidth == width and not state.root.hidden then return true end
    prepareParts(tooltip, state, parts)
    local contentWidth, y = math.max(1, width - 20), 8
    local semantic = {}
    local function place(label, value, x, available)
        local height = measure(value, available)
        label.content = value
        label:SetPos(x, y)
        label:SetSize(available, height)
        label.hidden = false
        y = y + height
    end
    local modelShown, modelSize = false, math.min(MODEL_HEIGHT, contentWidth)
    if state.model then state.model.hidden = true end
    if parts.model and state.model then
        local shown = pcall(function()
            local model = state.model
            model:SetSize(modelSize, modelSize)
            model:SetModel(ui.ModelType.NPC_MODEL, parts.model.npc)
            local zoom = parts.model.zoom
            model.viewDistance = math.floor(type(zoom) == "number" and zoom > 0 and zoom < math.huge
                and zoom * ZOOM_OUT_OWN or DEFAULT_ZOOM * ZOOM_OUT)
            model.worldOffset = Vector3.new(0, 0, 0)
            model.screenOffset = Vector3.new(0, 0, 0)
            model.hidden = false
        end)
        modelShown, state.model.hidden = shown, not shown
    end
    if modelShown and contentWidth >= modelSize + MODEL_GAP + MIN_BODY_WIDTH then
        local bodyWidth = contentWidth - modelSize - MODEL_GAP
        local bodyHeight = measure(parts.body, bodyWidth)
        local top, height = y, math.max(modelSize, bodyHeight)
        state.model:SetPos(10, top + height / 2)
        place(state.body, parts.body, 10 + modelSize + MODEL_GAP, bodyWidth)
        state.body:SetPos(10 + modelSize + MODEL_GAP, top + (height - bodyHeight) / 2)
        y = top + height + 4
    else
        if modelShown then
            state.model:SetPos(10 + (contentWidth - modelSize) / 2, y + modelSize / 2)
            y = y + modelSize + 6
        end
        place(state.body, parts.body, 10, contentWidth)
    end
    semantic[#semantic + 1] = parts.body
    for _, extra in ipairs(state.extras) do extra.icon.hidden, extra.label.hidden = true, true end
    for index, row in ipairs(parts.extraRows or {}) do
        local extra = state.extras[index]
        if not extra then break end
        extra.icon:SetPos(10, y + 1)
        if type(row.spriteId) == "number" then extra.icon.spriteID = row.spriteId; extra.icon.hidden = false end
        place(extra.label, plain(row.label), 34, math.max(1, contentWidth - 24))
        semantic[#semantic + 1] = plain(row.label)
    end
    local function fill(section, heading, textValue, rows)
        if not section then return end
        section.divider.root.hidden, section.heading.hidden = true, true
        if section.text then section.text.hidden = true end
        for _, row in ipairs(section.rows) do row.icon.hidden, row.label.hidden = true, true end
        if not textValue and #rows == 0 then return end
        y = y + 3
        section.divider.root:SetPos(10, y)
        section.divider.root:SetSize(contentWidth, 4)
        section.divider.root.hidden = false
        y = y + 7
        place(section.heading, "<col=FFD27F>" .. heading .. "</col>", 10, contentWidth)
        semantic[#semantic + 1] = heading
        if textValue then place(section.text, textValue, 10, contentWidth); semantic[#semantic + 1] = textValue end
        for index, item in ipairs(rows) do
            local row = section.rows[index]
            if not row then break end
            -- A row's picture is an item (obj) or a sprite (spriteId); some sprites sit small in their box, so they can be scaled up.
            local size = math.floor(18 * (item.scale or 1))
            local shift = math.floor((size - 18) / 2)
            row.icon.associatedObjectID, row.icon.spriteID = -1, -1
            row.icon:SetSize(size, size)
            row.icon:SetPos(10 - shift, y + 1 - shift)
            if item.spriteId then
                row.icon.spriteID = item.spriteId
            else
                row.icon:SetAssociatedObject(item.obj)
                row.icon.associatedObjectQuantityMode = ui.ObjectQuantityDisplayMode.NEVER
            end
            row.icon.hidden = false
            place(row.label, plain(item.label), 34, math.max(1, contentWidth - 24))
            semantic[#semantic + 1] = plain(item.label)
        end
    end
    fill(state.sections.needs, "Items", parts.needText, parts.needRows or {})
    fill(state.sections.rewards, "Rewards", parts.rewardText, parts.rewardRows or {})
    -- Slayer task cards: whether the task's monsters are in your Slayer Codex.
    fill(state.sections.codex, "Slayer Codex", nil, parts.codexRows or {})
    tooltip.options.text = table.concat(semantic, "<br>")
    tooltip.label.content, tooltip.label.hidden = tooltip.options.text, true
    tooltip.width, tooltip.height = width, y + 8
    tooltip.root:SetSize(tooltip.width, tooltip.height)
    state.root:SetSize(tooltip.width, tooltip.height)
    state.root.hidden = false
    tooltip.questKey, tooltip.questWidth = parts.key, width
    return true
end

return QuestTooltip
