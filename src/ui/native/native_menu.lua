local Components = require("src/ui/shared/components")
local Menu = require("src/ui/settings/menu")
local NativeMenu = {}
local generation = 0

local function resolve(binding)
    if binding.categoryID < 0 or binding.dynamicID < 0 then
        return ui.Interfaces:GetComponent(binding.interfaceID, binding.staticID)
    end
    return ui.Interfaces:GetComponent(binding.interfaceID, binding.staticID, binding.categoryID, binding.dynamicID)
end

local function ownsMarker(parent, binding)
    local marker = parent:GetChild(binding.markerCategory, binding.markerDynamic)
    return marker ~= nil and marker.type == ui.ComponentType.LABEL and marker.content == binding.token
end

local function deleteMarker(binding)
    if binding == nil then return end
    local parent = resolve(binding)
    if parent ~= nil and ownsMarker(parent, binding) then
        parent:Delete(binding.markerCategory, binding.markerDynamic)
    end
end

function NativeMenu.Bind(menu, parent, name)
    if menu == nil then return end
    generation = generation + 1
    local marker = Components.New(ui.Text, parent)
    marker:SetSize(0, 0)
    marker.hidden = true
    marker.clickthrough = true
    local token = name .. ":" .. generation .. ":" .. tostring(menu)
    marker.content = token
    menu.nativeBinding = {
        interfaceID = parent.interfaceID,
        staticID = parent.staticID,
        categoryID = parent.categoryID,
        dynamicID = parent.dynamicID,
        markerCategory = marker.categoryID,
        markerDynamic = marker.dynamicID,
        token = token
    }
end

function NativeMenu.Get(state, includeHidden)
    if state.menu ~= nil then return state.menu end
    local menu = state.nativeMenu
    if menu == nil then return nil end
    local binding = menu.nativeBinding
    if binding == nil then return nil end
    local parent = resolve(binding)
    if parent == nil or not ownsMarker(parent, binding) then return nil end
    if not includeHidden and not parent.visibleGlobal then return nil end
    return menu
end

function NativeMenu.Clear(state)
    local menu = state.nativeMenu
    state.nativeMenu = nil
    if menu == nil then return end
    local ownedOK, owned = pcall(function()
        local binding = menu.nativeBinding
        local parent = binding ~= nil and resolve(binding) or nil
        return parent ~= nil and ownsMarker(parent, binding)
    end)
    if not ownedOK or not owned then Menu.Abandon(menu); return end
    local markerOK, markerError = pcall(deleteMarker, menu.nativeBinding)
    if not markerOK then log("Notes: native menu marker cleanup failed", tostring(markerError)) end
    local ok, err = pcall(Menu.Destroy, menu)
    if not ok then log("Notes: native menu cleanup failed", tostring(err)) end
end

return NativeMenu
