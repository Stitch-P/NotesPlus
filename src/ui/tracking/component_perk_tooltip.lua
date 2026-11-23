local Components = require("src/ui/shared/components")
local PerkSprites = require("src/tracking/data/perk_sprites")

local ComponentTooltip = {}
local MAX_PERKS = 12
local TYPES = {"weapon", "armour", "tool"}
local SHELLS = {
    weapon = {label = "Weapon gizmo", regular = "INVENT_INCOMPLETE_WEAPON_GIZMO", ancient = "INVENT_INCOMPLETE_ANCIENT_WEAPON_GIZMO"},
    armour = {label = "Armour gizmo", regular = "INVENT_INCOMPLETE_ARMOUR_GIZMO", ancient = "INVENT_INCOMPLETE_ANCIENT_ARMOUR_GIZMO"},
    tool = {label = "Tool gizmo", regular = "INVENT_INCOMPLETE_TOOL_GIZMO", ancient = "INVENT_INCOMPLETE_ANCIENT_TOOL_GIZMO"},
}

local function plain(value)
    return tostring(value or ""):gsub("<[Bb][Rr]%s*/?>", " "):gsub("<", "["):gsub(">", "]"):gsub("[%c]", " ")
end

local function text(parent, colour)
    local label = prettyui.Text.new(parent, Components.Options({text = "", width = 1, height = 20,
        colour = colour or 0xFFFFFFFF, font = id.Font.MUSEO_SANS_13PT_REGULAR,
        shadowed = false, maxLines = 0}))
    label.clickthrough = true
    return label
end

local function sprite(parent)
    local icon = Components.New(ui.Sprite, parent)
    icon:SetSize(18, 18)
    icon.clickthrough = true
    return icon
end

local function measure(value, width)
    local ok, font = pcall(function() return config.Font.FromID(id.Font.MUSEO_SANS_13PT_REGULAR) end)
    if ok and font then
        local measured, height = pcall(function()
            return font:GetStringHeightAndLineCount(value, math.max(1, width), font.baseline, false, false, false)
        end)
        if measured and type(height) == "number" then return math.max(20, math.ceil(height)) end
    end
    return math.max(20, math.ceil(#value * 7 / math.max(1, width)) * 18)
end

local function textWidth(value)
    local ok, width = pcall(function()
        return config.Font.FromID(id.Font.MUSEO_SANS_13PT_REGULAR):GetStringWidth(value, false)
    end)
    return ok and type(width) == "number" and width or #value * 7
end

local function native(namespace, name)
    local ok, value = pcall(function() return namespace[name] end)
    return ok and type(value) == "number" and value > 0 and value or nil
end

function ComponentTooltip.Prepare(tooltip)
    if not tooltip or not tooltip.root then return false end
    if tooltip.componentPerks then return true end
    local state = {sections = {}, rows = {}}
    local ok, message = pcall(function()
        state.root = Components.Host(tooltip.root)
        state.root.clickthrough, state.root.hidden = true, true
        state.heading = text(state.root)
        state.details = text(state.root, 0xD8D8D8FF)
        state.sources = {divider = prettyui.Divider.new(state.root, Components.Options({width = 1})),
            icon = sprite(state.root), label = text(state.root, 0xE7D7B0FF), body = text(state.root)}
        state.sources.divider.root:SetSize(1, 4)
        state.sources.divider.root.hidden, state.sources.icon.hidden = true, true
        state.sources.label.hidden, state.sources.body.hidden = true, true
        for _, kind in ipairs(TYPES) do
            local section = {divider = prettyui.Divider.new(state.root, Components.Options({width = 1})),
                icon = sprite(state.root), label = text(state.root, 0xE7D7B0FF)}
            section.divider.root:SetSize(1, 4)
            section.divider.root.hidden, section.icon.hidden, section.label.hidden = true, true, true
            state.sections[kind] = section
        end
        for index = 1, MAX_PERKS do
            state.rows[index] = {icon = sprite(state.root), label = text(state.root)}
            state.rows[index].icon.hidden, state.rows[index].label.hidden = true, true
        end
    end)
    if not ok then
        if state.root then pcall(function() state.root:Destroy() end) end
        error(message, 0)
    end
    tooltip.componentPerks = state
    return true
end

function ComponentTooltip.Clear(tooltip)
    local state = tooltip and tooltip.componentPerks
    if state and state.root then state.root.hidden = true end
    if tooltip and tooltip.label then tooltip.label.hidden = false end
end

function ComponentTooltip.Set(tooltip, title, perks, options)
    if not tooltip or not tooltip.root or type(perks) ~= "table" then return false end
    local state = tooltip.componentPerks
    if not state then return false end
    options = options or {}
    title = plain(title)
    local details, semantic = {}, {title}
    local width = math.max(180, textWidth(title) + 20)
    for _, value in ipairs(options.details or {}) do
        value = plain(value)
        if value ~= "" then
            details[#details + 1] = value
            semantic[#semantic + 1] = value
            width = math.max(width, textWidth(value) + 20)
        end
    end
    local sources = type(options.sources) == "string" and plain(options.sources) or ""
    if sources ~= "" then width = math.max(width, textWidth("Disassembly sources") + 44) end
    for _, kind in ipairs(TYPES) do
        for _, name in ipairs(perks[kind] or {}) do width = math.max(width, textWidth(plain(name)) + 48) end
    end
    width = math.min(options.maxWidth or 300, math.ceil(width))
    local parentWidth = tooltip.parent and tooltip.parent.width or 0
    if parentWidth > 0 then width = math.min(width, math.max(1, parentWidth - 12)) end
    local contentWidth, y = math.max(1, width - 20), 8
    local function place(label, value, x, available)
        local height = measure(value, available)
        label.content = value
        label:SetPos(x, y)
        label:SetSize(available, height)
        label.hidden = false
        y = y + height
    end
    place(state.heading, title, 10, contentWidth)
    if #details > 0 then place(state.details, table.concat(details, "<br>"), 10, contentWidth)
    else state.details.hidden = true end
    for _, section in pairs(state.sections) do
        section.divider.root.hidden, section.icon.hidden, section.label.hidden = true, true, true
    end
    for _, row in ipairs(state.rows) do row.icon.hidden, row.label.hidden = true, true end
    local rowIndex = 0
    for _, kind in ipairs(TYPES) do
        local names, section = perks[kind], state.sections[kind]
        if type(names) == "table" and #names > 0 then
            y = y + 3
            section.divider.root:SetPos(10, y)
            section.divider.root:SetSize(contentWidth, 4)
            section.divider.root.hidden = false
            y = y + 7
            local shell = SHELLS[kind]
            local object = native(id.Obj, perks.ancient and shell.ancient or shell.regular)
            section.icon:SetPos(10, y + 1)
            section.icon.hidden = object == nil
            if object and section.object ~= object then section.icon:SetAssociatedObject(object); section.object = object end
            local name = perks.ancient and "Ancient " .. shell.label:lower() or shell.label
            place(section.label, name, 34, math.max(1, contentWidth - 24))
            semantic[#semantic + 1] = name .. ": " .. table.concat(names, ", "):gsub("<", "["):gsub(">", "]")
            for _, name in ipairs(names) do
                rowIndex = rowIndex + 1
                local row = state.rows[rowIndex]
                if row then
                    local symbol = PerkSprites[name] or "INVENTION_ICON_PERK_RANK_0"
                    local icon = native(id.Sprite, symbol) or native(id.Sprite, "INVENTION_ICON_PERK_RANK_0")
                    row.icon:SetPos(20, y + 1)
                    row.icon.hidden = icon == nil
                    if icon then row.icon.spriteID = icon end
                    place(row.label, plain(name), 44, math.max(1, contentWidth - 34))
                end
            end
        end
    end
    if rowIndex == 0 then
        local row = state.rows[1]
        y = y + 3
        place(row.label, "No perks", 10, contentWidth)
        semantic[#semantic + 1] = "No perks"
    end
    local source = state.sources
    source.divider.root.hidden, source.icon.hidden = true, true
    source.label.hidden, source.body.hidden = true, true
    if sources ~= "" then
        y = y + 3
        source.divider.root:SetPos(10, y)
        source.divider.root:SetSize(contentWidth, 4)
        source.divider.root.hidden = false
        y = y + 7
        local icon = native(id.Sprite, "SPELL_SKILLING_ICON_DISASSEMBLE")
        source.icon:SetPos(10, y + 1)
        source.icon.hidden = icon == nil
        if icon then source.icon.spriteID = icon end
        place(source.label, "Disassembly sources", 34, math.max(1, contentWidth - 24))
        place(source.body, sources, 10, contentWidth)
        semantic[#semantic + 1] = "Disassembly sources: " .. sources
    end
    tooltip.options.text = table.concat(semantic, "<br>")
    tooltip.label.content, tooltip.label.hidden = tooltip.options.text, true
    tooltip.width, tooltip.height = width, y + 8
    tooltip.root:SetSize(tooltip.width, tooltip.height)
    state.root:SetSize(tooltip.width, tooltip.height)
    state.root.hidden = false
    if tooltip.root.hidden ~= true then tooltip:Show() end
    return true
end

function ComponentTooltip.Destroy(tooltip, detached)
    local state = tooltip and tooltip.componentPerks
    if not state then return end
    for _, section in pairs(state.sections) do
        if detached then section.divider.root = nil end
        section.divider:Destroy()
    end
    if detached then state.sources.divider.root = nil end
    state.sources.divider:Destroy()
    if state.root and not detached then state.root:Destroy() end
    tooltip.componentPerks = nil
    if not detached and tooltip.label then tooltip.label.hidden = false end
end

return ComponentTooltip
