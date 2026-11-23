local Detached = {}

function Detached.Tooltip(tooltip)
    if not tooltip then return end
    tooltip.target, tooltip.root, tooltip._parts = nil, nil, nil
    tooltip.questParts, tooltip.questKey, tooltip.questWidth = nil, nil, nil
    tooltip.componentPerks = nil
end

local function detachManaged(control)
    control._destroyingManagedFlow = true
    for _, entry in ipairs(control._managedFlowEntries or {}) do
        if not entry.native then Detached.Control(entry.component) end
    end
    control._managedFlowEntries = {}
end

function Detached.Tooltips(root)
    local context = root and prettyui.Tooltip.getContext(root)
    if not context then return end
    local function detach(collection)
        for _, child in ipairs(collection.children or {}) do detach(child) end
        for _, tooltip in ipairs(collection.tooltips or {}) do Detached.Tooltip(tooltip) end
    end
    detach(context)
    prettyui.Tooltip.unregisterContext(root)
end

function Detached.Control(control)
    if not control then return end
    Detached.Tooltips(control.root)
    Detached.Tooltips(control.content)
    for field in pairs(control._tooltipBindings or {}) do
        local tooltip = control[field]
        Detached.Tooltip(tooltip)
    end
    detachManaged(control)
    for _, page in ipairs(control.pages or {}) do
        Detached.Tooltips(page.content)
        detachManaged(page)
        page.rowBackgrounds = {}
        if page._scroll then Detached.Control(page._scroll); page._scroll = nil end
        page.root, page.viewport, page.content = nil, nil, nil
    end
    if control.pickerWindow then
        Detached.Window(control.pickerWindow)
        control:_ClearPickerReferences()
    end
    if control.dropdown then
        control.ownerWindow = nil
        Detached.Control(control.dropdown)
        control.dropdown = nil
    end
    if control.button then
        if type(control.button) == "table" and rawget(control.button, "root") ~= nil then
            Detached.Control(control.button)
        end
        control.button = nil
    end
    if control._scroll then Detached.Control(control._scroll); control._scroll = nil end
    if control.thumbDrag and ui.Interfaces:GetInterface(control.overlayInterfaceID) ~= nil then
        control.thumbDrag:Destroy()
    end
    control.root, control.thumbDrag = nil, nil
    control:Destroy()
end

function Detached.Window(window)
    if not window then return end
    if window.resize then
        window.resize.dragState, window.resize.feedback = nil, nil
        window.resize.interfaceID = -1
        window.resize:Destroy()
        window.resize = nil
    end
    if window.dragBounds then
        window.dragBounds.parent = nil
        window.dragBounds:Destroy()
        window.dragBounds = nil
    end
    if window.titleDrag and ui.Interfaces:GetInterface(window.interfaceID) ~= nil then
        window.titleDrag:Destroy()
    end
    window.titleDrag, window.dragFeedback, window._stopDrag = nil, nil, nil
    window.overlays, window.rowBackgrounds = {}, {}
    Detached.Control(window)
end

return Detached
