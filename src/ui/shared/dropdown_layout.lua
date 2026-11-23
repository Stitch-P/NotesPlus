local DropdownLayout = {}

function DropdownLayout.FitToWindow(combo)
    local layoutDropdown = combo._LayoutDropdown
    -- Recalculate when the floating list opens, filters, or follows a window move.
    combo._LayoutDropdown = function(control)
        local _, y = control.root.x, control.root.y
        if control.context and control.context.active then _, y = control.context.position(control.root) end
        local top, bottom = 0, control.overlayParent.height
        if control.ownerWindow then
            local _, windowTop = control.ownerWindow._scroll:_AbsolutePosition()
            top = math.max(top, windowTop)
            bottom = math.min(bottom, windowTop + control.ownerWindow.viewport.height)
        end
        local above = math.max(0, math.min(y, bottom) - top)
        local below = math.max(0, bottom - math.max(y + control.root.height, top))
        control.maxVisibleEntries = math.max(1, math.floor((math.max(above, below) - 2) / control.entryHeight))
        layoutDropdown(control)
        local dropdown = control.dropdown.root
        local dropdownY = y + control.root.height
        if dropdownY + dropdown.height > bottom then dropdownY = y - dropdown.height end
        dropdown:SetPos(dropdown.x, math.max(top, math.min(dropdownY, bottom - dropdown.height)))
    end
    return combo
end

return DropdownLayout
