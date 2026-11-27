local Tracking = require("src/tracking/model")
local Menaphos = require("src/tracking/features/menaphos_journal").MenaphosJournal
local Arc = require("src/tracking/features/arc_journal").ArcJournal
local Raven = require("src/tracking/features/prif_raven").PrifRaven
local Scheduled = require("src/tracking/features/scheduled")
local DisplayCapacity = require("src/notes/display_capacity")

local Defaults = {SCHEDULED = "Scheduled"}
local definitions = {
    {provider = Menaphos, key = "menaphos-cats"},
    {provider = Arc, key = "arc-birds"},
    {provider = Arc, key = "arc-castaways"},
    {provider = Raven, key = Raven.KEY},
}
local templates

local function scheduledTemplates()
    if templates then return templates end
    local built = {}
    for _, definition in ipairs(definitions) do
        local selected
        for _, option in ipairs(definition.provider.options()) do
            if option.key == definition.key then selected = option; break end
        end
        assert(selected, "Unknown scheduled default tracking.")
        local tracking, message = Tracking.Normalize({category = "Unlocks", group = definition.provider.GROUP,
            key = selected.key, label = selected.label, variable = selected.varName,
            target = selected.defaultTarget, iconSprite = selected.spriteName, iconObj = selected.objId})
        assert(tracking, message)
        built[#built + 1] = tracking
    end
    for _, option in ipairs(Scheduled.options()) do
        local tracking, message = Tracking.Normalize({category = "Scheduled", group = option.group,
            key = option.key, label = option.label, variable = option.varName,
            target = option.defaultTarget, iconSprite = option.spriteName, iconObj = option.objId})
        assert(tracking, message)
        built[#built + 1] = tracking
    end
    templates = built
    return templates
end

local function orderScheduled(data)
    local scheduled
    for index, category in ipairs(data.categories) do
        if category.name:lower() == Defaults.SCHEDULED:lower() then
            scheduled = table.remove(data.categories, index)
            break
        end
    end
    if not scheduled then return end
    local position = #data.categories + 1
    for index, category in ipairs(data.categories) do
        if category.name:lower() > Defaults.SCHEDULED:lower() then position = index; break end
    end
    table.insert(data.categories, position, scheduled)
end

function Defaults.Apply(data, notes, restore)
    if not restore and data.scheduledDefaultsAdded == true and data.scheduledEventsAdded == true
        and data.scheduledRewardsAdded == true and data.scheduledPenguinsAdded == true
        and data.scheduledTasksAdded == true then
        if data.scheduledCategoryOrdered ~= true then
            orderScheduled(data)
            data.scheduledCategoryOrdered = true
        end
        return true
    end
    local defaults, wanted, existing, missing = {}, {}, {}, 0
    for _, tracking in ipairs(scheduledTemplates()) do
        local installed
        if tracking.key == "scheduled-nemi-forest"
            or tracking.key == "scheduled-meg" or tracking.key == "scheduled-tears-of-guthix"
            or tracking.key == "scheduled-agoroth" or tracking.key == "scheduled-troll-invasion"
            or tracking.key == "scheduled-soul-obelisks" or tracking.key == "scheduled-citadel" then
            installed = data.scheduledTasksAdded
        elseif tracking.key == "scheduled-penguins" then
            installed = data.scheduledPenguinsAdded
        elseif tracking.key == "scheduled-giant-oyster" or tracking.key == "scheduled-crystal-blossoms" then
            installed = data.scheduledRewardsAdded
        elseif tracking.category == "Scheduled" then installed = data.scheduledEventsAdded
        else installed = data.scheduledDefaultsAdded end
        if restore or installed ~= true then
            defaults[#defaults + 1] = tracking
            wanted[tracking.category .. ":" .. tracking.key] = true
        end
    end
    for _, note in ipairs(data.notes) do
        local tracking = note.tracking
        if tracking and wanted[tracking.category .. ":" .. tostring(tracking.key)] then existing[tracking.key] = true end
    end
    for _, tracking in ipairs(defaults) do
        if not existing[tracking.key] then missing = missing + 1 end
    end
    if #data.notes + missing > notes.MAX_NOTES then
        return nil, "Not enough space within the 1,000-note limit for scheduled defaults."
    end
    local categoryID
    for _, category in ipairs(data.categories) do
        if category.name:lower() == Defaults.SCHEDULED:lower() then categoryID = category.id; break end
    end
    local staged = {categories = {}, nextCategoryID = data.nextCategoryID, notes = {}}
    for index, category in ipairs(data.categories) do staged.categories[index] = category end
    for index, note in ipairs(data.notes) do
        local copy = {}
        for key, value in pairs(note) do copy[key] = value end
        staged.notes[index] = copy
    end
    if not categoryID then
        local message
        categoryID, message = notes.AddCategory(staged, Defaults.SCHEDULED)
        if not categoryID then return nil, message end
    end
    for _, tracking in ipairs(defaults) do
        if not existing[tracking.key] then
            local ok, message = notes.Put(staged, nil, "", "FFFFFF", tracking.label, "", categoryID, tracking,
                false, {notifyChat = false, notifyPopup = false}, false)
            if not ok then return nil, message end
        end
    end
    for _, note in ipairs(staged.notes) do
        local tracking = note.tracking
        if tracking and wanted[tracking.category .. ":" .. tostring(tracking.key)] then note.categoryID = categoryID end
    end
    local ok, message = DisplayCapacity.Check(data, staged)
    if not ok then return nil, message end
    if #staged.categories > #data.categories then
        data.categories[#data.categories + 1] = staged.categories[#staged.categories]
        data.nextCategoryID = staged.nextCategoryID
    end
    for _, note in ipairs(data.notes) do
        local tracking = note.tracking
        if tracking and wanted[tracking.category .. ":" .. tostring(tracking.key)] then note.categoryID = categoryID end
    end
    for index = #data.notes + 1, #staged.notes do data.notes[index] = staged.notes[index] end
    if data.scheduledCategoryOrdered ~= true then orderScheduled(data) end
    data.scheduledDefaultsAdded, data.scheduledCategoryOrdered, data.scheduledEventsAdded = true, true, true
    data.scheduledRewardsAdded = true
    data.scheduledPenguinsAdded = true
    data.scheduledTasksAdded = true
    return true
end

return Defaults
