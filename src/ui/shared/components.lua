local Components = {}

function Components.Options(options)
    local copy = {}
    for key, value in pairs(options or {}) do copy[key] = value end
    copy.categoryID = "auto"
    return copy
end

local function inheritedPreflight(parent, host)
    local static = parent.parentStatic or parent
    local category = parent == static and 0 or parent.categoryID
    local first = parent == static and 0 or type(parent.dynamicID) == "number" and parent.dynamicID + 1 or nil
    if category == -1 then category, first = 0, 0 end
    if host and category ~= nil and category ~= 0 then
        error("Notes-Plus: content must be mounted inside a category-zero host.", 3)
    end
    if type(category) ~= "number" or first == nil then return end
    local maximum = category == 0 and 4095 or 234
    if category % 1 ~= 0 or category < 0 or category > 234 or first % 1 ~= 0 or first < 0 then
        error("Notes-Plus: this UI container has invalid component IDs.", 3)
    end
    if first > maximum then error("Notes-Plus: this UI container is full. Close unused views and try again.", 3) end
    local interfaces = ui and ui.Interfaces
    if parent ~= static and interfaces and type(interfaces.GetComponent) == "function"
        and type(static.interfaceID) == "number" and type(static.staticID) == "number"
        and interfaces:GetComponent(static.interfaceID, static.staticID, parent.categoryID, parent.dynamicID) == parent
        and interfaces:GetComponent(static.interfaceID, static.staticID, category, maximum) == nil then
        return
    end
    if type(static.IterateDynamicComponents) ~= "function" then return end
    local occupied, visited = {}, {}
    local function visit(collection)
        if visited[collection] or type(collection.IterateDynamicComponents) ~= "function" then return end
        visited[collection] = true
        collection:IterateDynamicComponents(function(child)
            if child.parentStatic == static then
                if child.categoryID == category then occupied[child.dynamicID] = true end
                visit(child)
            end
            return false
        end)
    end
    visit(static)
    for dynamicID = first, maximum do if not occupied[dynamicID] then return end end
    error("Notes-Plus: this UI container is full. Close unused views and try again.", 3)
end

local function layout(component, options)
    if not options then return component end
    if options.x ~= nil or options.y ~= nil or options.xAnchor ~= nil or options.yAnchor ~= nil then
        component:SetPos(options.x or 0, options.y or 0, options.xAnchor or 0, options.yAnchor or 0)
    end
    if options.width ~= nil or options.height ~= nil or options.widthAnchor ~= nil or options.heightAnchor ~= nil then
        component:SetSize(options.width or 0, options.height or 0, options.widthAnchor or 0, options.heightAnchor or 0)
    end
    return component
end

function Components.New(nativeType, parent, options)
    local component = prettyui.NewComponent(nativeType, parent, Components.Options(options))
    return layout(component, options)
end

function Components.Host(parent, options, nativeType)
    -- Content hosts retain category zero; their decorations use managed IDs.
    inheritedPreflight(parent, true)
    return layout((nativeType or ui.Layer).new(parent), options)
end

function Components.Group(parent, count, builder)
    return prettyui.BuildCategoryGroup(parent, count, builder)
end

return Components
