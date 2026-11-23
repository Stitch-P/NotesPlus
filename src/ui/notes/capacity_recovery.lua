local Components = require("src/ui/shared/components")
local Base = require("src/ui/views/view")
local Notes = require("src/notes/notes")

local Recovery = {}
local ROW_HEIGHT = 32
local MUTED = 0xB7B1A7FF

local function matching(view)
    local visible = {}
    for index, note in ipairs(view.data.notes) do
        if (view.categoryID == nil or (note.categoryID or 0) == view.categoryID)
            and (view.query == "" or ((note.title or "") .. " " .. note.text .. " "
                .. (note.tracking and note.tracking.label or "")):lower():find(view.query:lower(), 1, true)) then
            visible[#visible + 1] = index
        end
    end
    local category = Notes.FindCategory(view.data, view.categoryID)
    view.alphabetical = category ~= nil and category.name:lower() == "scheduled"
    if view.alphabetical then
        local function title(index)
            local note = view.data.notes[index]
            return (note.title ~= "" and note.title or note.tracking and note.tracking.label or note.text):lower()
        end
        table.sort(visible, function(left, right)
            local a, b = title(left), title(right)
            return a == b and left < right or a < b
        end)
    end
    return visible
end

function Recovery.Layout(view, scroll)
    if view.destroyed or not view.listScroll then return end
    view.layingOutRows = true
    local viewport = view.listScroll
    scroll = scroll or viewport.scrollY
    local height = math.max(1, view.height - view.listY - (view.countFooter or 70))
    if viewport.width ~= view.listWidth or viewport.height ~= height then viewport:SetSize(view.listWidth, height) end
    local width = math.max(1, viewport.contentWidth - 16)
    view.recoveryNotice:SetSize(width, view.recoveryNoticeHeight)
    for _, row in ipairs(view.noteRows) do
        row.width, row.bodyWidth = width, width
        row.component:SetSize(width, ROW_HEIGHT)
    end
    local contentHeight = view.recoveryNoticeHeight + 20 + #view.noteRows * ROW_HEIGHT
    if viewport.requestedContentHeight ~= contentHeight then viewport:SetContentHeight(contentHeight) end
    if viewport.scrollY ~= scroll then viewport:SetScrollPosition(scroll) end
    view.scroll = viewport.scrollY
    view:LayoutCount()
    view.layingOutRows, view.rowsReady = false, true
    view:LayoutNoteHits()
end

function Recovery.Render(view)
    view.compactRecovery, view.rowsReady = true, false
    view.visibleNotes = matching(view)
    view:UpdateCount(view.capacityCost)
    view.listScroll = prettyui.SimpleView.new(view.surface, Components.Options({
        x = view.listX, y = view.listY, width = view.listWidth,
        height = math.max(1, view.height - view.listY - (view.countFooter or 70)), scrollStep = 48,
    }))
    local width = math.max(1, view.listScroll.contentWidth - 16)
    view.recoveryNoticeHeight = 80
    view.recoveryNotice = Base.Label(view.listScroll.content,
        "Display capacity exceeded. Edit or delete notes to reduce it. Notes are shown as a compact list.",
        8, 8, width, view.recoveryNoticeHeight, MUTED)
    view.noteRows = {}
    for position, index in ipairs(view.visibleNotes) do
        local note = view.data.notes[index]
        local title = note.title ~= "" and note.title or note.tracking and note.tracking.label or note.text
        local y = view.recoveryNoticeHeight + 16 + (position - 1) * ROW_HEIGHT
        local component = Base.Label(view.listScroll.content, title, 8, y, width, ROW_HEIGHT,
            tonumber(note.color, 16) * 256 + 255)
        component.maxLines, component.clickthrough = 1, false
        component:Subscribe(ui.Hook.ONCLICK, function()
            if not view.destroyed and view.data.notes[index] == note then view:Edit(index) end
            return false
        end)
        component:Subscribe(ui.Hook.ONSCROLLWHEEL, function(_, rotation)
            view.listScroll:ScrollBy(rotation * 48)
            return false
        end)
        view.noteRows[position] = {component = component, hit = component, note = note, position = position,
            x = 8, y = y, width = width, height = ROW_HEIGHT, bodyWidth = width, bodyHeight = ROW_HEIGHT}
    end
    view.noteHit = Components.New(ui.Layer, view.listScroll.root)
    view.noteHit.clickthrough = true
    view.listScroll.onLayout = function() view:LayoutNoteHits() end
    Recovery.Layout(view, view.scroll)
end

return Recovery
