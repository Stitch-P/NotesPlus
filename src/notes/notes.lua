local Sprites = require("src/data/sprite_catalog")
local Tracking = require("src/tracking/model")
local Vars = require("src/tracking/core/vars")
local Registry = require("src/tracking/core/registry").Registry
local Gear = require("src/notes/gear")
local ActionBar = require("src/notes/action_bar")
local Profiles = require("src/core/character_profiles")
local CollectionProgress = require("src/notes/collection_progress")
local Storage = require("src/notes/storage")
local Defaults = require("src/notes/defaults")
local DisplayCapacity = require("src/notes/display_capacity")
local Notes = {}
local owners = setmetatable({}, {__mode = "k"})

local DB_KEY = "notes_plus_data_v1"
local PREFIX = "NOTES20"
local MAX_TRACKING_EXPORT = Tracking.MAX_TRACKING_EXPORT or 30000
local MAX_GEAR_EXPORT = #Gear.Slots * (Sprites.MAX_NAME_LENGTH * 3 + 20) + 1
local MAX_ACTION_BAR_EXPORT = ActionBar.MAX_NAME * 3 + 20
    + ActionBar.SLOT_COUNT * (ActionBar.MAX_TOKEN_LENGTH * 3 + ActionBar.MAX_LABEL * 3 + 30)
local MAX_CATEGORY_ID = 2147483646
Notes.MAX_NOTES = 1000
Notes.MAX_TEXT = 4000
Notes.MAX_TITLE = 120
Notes.MAX_CATEGORIES = 50
Notes.MAX_CATEGORY_NAME = 40
local DEFAULT_CATEGORIES = {"Bossing", "Clues", "Combat", "Currencies", "Gathering", "Invention", "Ports", "Production", "Quests", Defaults.SCHEDULED, "Skills", "Slayer", "Tasks", "Training", "Unlocks"}

local maxEncodedNote = (Notes.MAX_TITLE + Notes.MAX_TEXT) * 3 + Sprites.MAX_NAME_LENGTH
    + MAX_TRACKING_EXPORT + MAX_GEAR_EXPORT + MAX_ACTION_BAR_EXPORT + 30
local maxHeader = #PREFIX + 6
Notes.MAX_EXPORT = maxHeader + Notes.MAX_NOTES * maxEncodedNote
    + Notes.MAX_CATEGORIES * ((Notes.MAX_CATEGORY_NAME + Sprites.MAX_NAME_LENGTH) * 3 + 24)

local function validText(text, maximum)
    return type(text) == "string" and #text <= maximum and text:match("%S") ~= nil
        and text:find("[%z\1-\8\11\12\14-\31\127]") == nil
end

local function validColor(color)
    return type(color) == "string" and color:match("^%x%x%x%x%x%x$") ~= nil
end

local function validCategoryID(value)
    return type(value) == "number" and value >= 0 and value <= MAX_CATEGORY_ID and value % 1 == 0
end

local function categoryName(name)
    if type(name) ~= "string" or name:find("[%c]") then return nil, "Category names cannot contain control characters." end
    name = name:match("^%s*(.-)%s*$")
    if name == "" or #name > Notes.MAX_CATEGORY_NAME then return nil, "Enter a category up to 40 characters." end
    if name:find("[<>]") then return nil, "Category names cannot contain < or >." end
    local key = name:lower()
    if key == "all notes" or key == "uncategorized" then return nil, "All notes and Uncategorized are reserved category names." end
    return name
end

function Notes.FindCategory(data, categoryID)
    if not validCategoryID(categoryID) or categoryID == 0 then return nil end
    for _, category in ipairs(data.categories) do
        if category.id == categoryID then return category end
    end
    return nil
end

function Notes.CategoryName(data, categoryID)
    local category = Notes.FindCategory(data, categoryID)
    return category and category.name or "Uncategorized"
end

local function categoryConflict(data, name, exceptID)
    for _, category in ipairs(data.categories) do
        if category.id ~= exceptID and category.name:lower() == name:lower() then return true end
    end
    return false
end

local function categoryAppearance(appearance)
    if type(appearance) ~= "table" then return nil, "Choose valid category appearance settings." end
    if appearance.skill ~= nil and not Sprites.Valid(appearance.skill) then
        return nil, "Choose an icon from the sprite picker."
    end
    if appearance.color ~= nil and not validColor(appearance.color) then return nil, "Enter a six-digit hex color." end
    return {skill = appearance.skill, color = appearance.color and appearance.color:upper()}
end

local function stageData(data, cloneNotes)
    local staged, originals = {}, {}
    for key, value in pairs(data) do staged[key] = value end
    staged.categories, staged.notes = {}, {}
    for index, category in ipairs(data.categories) do staged.categories[index] = category end
    for index, note in ipairs(data.notes) do
        if cloneNotes then
            local copy = {}
            for key, value in pairs(note) do copy[key] = value end
            staged.notes[index] = copy
            originals[copy] = note
        else staged.notes[index] = note end
    end
    return staged, originals
end

local function commitData(data, staged, originals)
    for index, note in ipairs(staged.notes) do
        local previous = originals[note] or note
        if previous ~= note then
            for key in pairs(previous) do previous[key] = nil end
            for key, value in pairs(note) do previous[key] = value end
            staged.notes[index] = previous
        end
    end
    for index = #data.categories, 1, -1 do data.categories[index] = nil end
    for index, category in ipairs(staged.categories) do data.categories[index] = category end
    for index, note in ipairs(staged.notes) do data.notes[index] = note end
    for key, value in pairs(staged) do
        if key ~= "categories" and key ~= "notes" then data[key] = value end
    end
end

local function createCategory(data, name, appearance)
    local message
    name, message = categoryName(name)
    if name == nil then return nil, message end
    if appearance == nil then appearance = {} end
    appearance, message = categoryAppearance(appearance)
    if appearance == nil then return nil, message end
    if categoryConflict(data, name) then return nil, "A category with that name already exists." end
    if #data.categories >= Notes.MAX_CATEGORIES then return nil, "You have reached the 50-category limit." end
    local categoryID = data.nextCategoryID
    if not validCategoryID(categoryID) or categoryID == 0 then return nil, "No more category IDs are available." end
    return {id = categoryID, name = name, skill = appearance.skill, color = appearance.color}, categoryID + 1
end

function Notes.AddCategory(data, name, appearance)
    local category, nextID = createCategory(data, name, appearance)
    if not category then return nil, nextID end
    local staged = stageData(data)
    staged.categories[#staged.categories + 1], staged.nextCategoryID = category, nextID
    local ok, message = DisplayCapacity.Check(data, staged)
    if not ok then return nil, message end
    data.categories[#data.categories + 1], data.nextCategoryID = category, nextID
    return category.id
end

function Notes.UpdateCategory(data, categoryID, name, appearance)
    local category = Notes.FindCategory(data, categoryID)
    if category == nil then return nil, "That category no longer exists." end
    local message
    name, message = categoryName(name)
    if name == nil then return nil, message end
    if categoryConflict(data, name, categoryID) then return nil, "A category with that name already exists." end
    if appearance ~= nil then
        appearance, message = categoryAppearance(appearance)
        if appearance == nil then return nil, message end
    end
    category.name = name
    if appearance ~= nil then category.skill, category.color = appearance.skill, appearance.color end
    return true
end

function Notes.RenameCategory(data, categoryID, name)
    return Notes.UpdateCategory(data, categoryID, name)
end

function Notes.DeleteCategory(data, categoryID)
    local category = Notes.FindCategory(data, categoryID)
    if category == nil then return nil, "That category no longer exists." end
    for index, existing in ipairs(data.categories) do
        if existing == category then table.remove(data.categories, index) break end
    end
    for _, note in ipairs(data.notes) do
        if note.categoryID == categoryID then note.categoryID = 0 end
    end
    return true
end

function Notes.ReorderCategory(data, categoryID, destination)
    if not validCategoryID(categoryID) or categoryID == 0 or type(destination) ~= "number"
        or destination % 1 ~= 0 or destination < 1 or destination > #data.categories then return false end
    local source
    for index, category in ipairs(data.categories) do
        if category.id == categoryID then source = index break end
    end
    if source == nil or source == destination then return false end
    table.insert(data.categories, destination, table.remove(data.categories, source))
    return true
end

function Notes.DefaultCategories()
    local categories = {}
    for index, name in ipairs(DEFAULT_CATEGORIES) do categories[index] = {id = index, name = name} end
    return categories
end

function Notes.ResetCategories(data, restoreScheduled)
    local missing = {}
    for _, name in ipairs(DEFAULT_CATEGORIES) do
        if not categoryConflict(data, name) then missing[#missing + 1] = name end
    end
    if #data.categories + #missing > Notes.MAX_CATEGORIES then
        return nil, "Not enough space within the 50-category limit."
    end
    if #missing > 0 and (not validCategoryID(data.nextCategoryID) or data.nextCategoryID == 0
        or data.nextCategoryID + #missing - 1 > MAX_CATEGORY_ID) then
        return nil, "No more category IDs are available."
    end
    local staged, originals = stageData(data, restoreScheduled)
    for _, name in ipairs(missing) do
        -- Slot each one in before the first existing category that comes after it in the default order.
        local position = #staged.categories + 1
        local later = {}
        local seen = false
        for _, defaultName in ipairs(DEFAULT_CATEGORIES) do
            if seen then later[defaultName:lower()] = true end
            if defaultName == name then seen = true end
        end
        for index, category in ipairs(staged.categories) do
            if later[category.name:lower()] then position = index break end
        end
        table.insert(staged.categories, position, {id = staged.nextCategoryID, name = name})
        staged.nextCategoryID = staged.nextCategoryID + 1
    end
    if restoreScheduled then
        local ok, message = Defaults.Apply(staged, Notes, true)
        if not ok then return nil, message end
    end
    local ok, message = DisplayCapacity.Check(data, staged)
    if not ok then return nil, message end
    commitData(data, staged, originals)
    return true
end

local function validNote(note)
    return type(note) == "table" and type(note.title) == "string" and type(note.text) == "string"
        and (note.title == "" or validText(note.title, Notes.MAX_TITLE))
        and (note.text == "" or validText(note.text, Notes.MAX_TEXT))
        and (note.title ~= "" or note.text ~= "" or Gear.Count(note.gear) > 0 or ActionBar.Count(note.actionBar) > 0)
        and validColor(note.color) and Sprites.Valid(note.skill)
        and (note.subjectExpanded == nil or type(note.subjectExpanded) == "boolean")
        and type(note.notifyChat) == "boolean" and type(note.notifyPopup) == "boolean"
        and validCategoryID(note.categoryID)
end

local function readNote(saved)
    if type(saved) ~= "table" then return nil end
    local skill = saved.skill
    if type(skill) == "string" and not Sprites.Valid(skill) then skill = "" end
    local note = {title = saved.title, text = saved.text, color = saved.color, skill = skill,
        subjectExpanded = saved.subjectExpanded, categoryID = saved.categoryID == nil and 0 or saved.categoryID,
        notifyChat = saved.notifyChat ~= nil and saved.notifyChat or false,
        notifyPopup = saved.notifyPopup ~= nil and saved.notifyPopup or false}
    if saved.tracking ~= nil then
        note.tracking = Tracking.Normalize(saved.tracking)
        if note.tracking == nil then return nil end
    end
    if saved.gear ~= nil then
        note.gear = Gear.Normalize(saved.gear)
        if note.gear == nil then return nil end
    end
    if saved.actionBar ~= nil then
        note.actionBar = ActionBar.Normalize(saved.actionBar)
        if note.actionBar == nil then return nil end
    end
    local signature
    if saved.completedTracking ~= nil then
        if not validText(saved.completedTracking, MAX_TRACKING_EXPORT) then return nil end
        if note.tracking then
            signature = Notes.TrackingGoalSignature(note.tracking)
            if saved.completedTracking == signature then note.completedTracking = saved.completedTracking end
        end
    end
    if note.tracking and note.tracking.category == "Scheduled" and validText(saved.notificationPeriod, 120)
        and not saved.notificationPeriod:find("[%c]") then
        note.notificationPeriod = saved.notificationPeriod
    end
    if note.tracking and (note.completedTracking or saved.progressNotifications ~= nil) then
        signature = signature or Notes.TrackingGoalSignature(note.tracking)
        if note.completedTracking then note.completedTracking = signature end
        if saved.progressNotifications ~= nil then
            note.progressNotifications = CollectionProgress.Copy(saved.progressNotifications, signature)
        end
    end
    return validNote(note) and note or nil
end

local function copyNotes(notes)
    local copy = {}
    for _, saved in ipairs(notes) do
        local note = readNote(saved)
        assert(note, "Invalid saved note. The saved data has been kept.")
        copy[#copy + 1] = note
    end
    return copy
end

function Notes.New()
    return {version = 1, categories = {}, nextCategoryID = 1, notes = {}, trackingCategoriesReviewed = true}
end

local function copyData(stored)
    assert(type(stored) == "table" and stored.version == 1 and type(stored.notes) == "table"
        and #stored.notes <= Notes.MAX_NOTES and type(stored.categories) == "table"
        and #stored.categories <= Notes.MAX_CATEGORIES,
        "Notes could not read the saved notes. The saved data has been kept.")
    local data = Notes.New()
    data.trackingCategoriesReviewed = stored.trackingCategoriesReviewed == true
    data.scheduledDefaultsAdded = stored.scheduledDefaultsAdded == true or nil
    data.scheduledCategoryOrdered = stored.scheduledCategoryOrdered == true or nil
    data.scheduledEventsAdded = stored.scheduledEventsAdded == true or nil
    data.scheduledRewardsAdded = stored.scheduledRewardsAdded == true or nil
    data.scheduledPenguinsAdded = stored.scheduledPenguinsAdded == true or nil
    data.scheduledTasksAdded = stored.scheduledTasksAdded == true or nil
    local largestID = 0
    for _, saved in ipairs(stored.categories) do
        assert(type(saved) == "table" and validCategoryID(saved.id) and saved.id > 0
            and categoryName(saved.name) == saved.name and Notes.FindCategory(data, saved.id) == nil
            and not categoryConflict(data, saved.name), "Invalid saved category. The saved data has been kept.")
        local skill = saved.skill
        if type(skill) == "string" and not Sprites.Valid(skill) then skill = "" end
        local appearance = categoryAppearance({skill = skill, color = saved.color})
        assert(appearance, "Invalid saved category appearance. The saved data has been kept.")
        data.categories[#data.categories + 1] = {id = saved.id, name = saved.name,
            skill = appearance.skill, color = appearance.color}
        largestID = math.max(largestID, saved.id)
    end
    assert(type(stored.nextCategoryID) == "number" and stored.nextCategoryID % 1 == 0
        and stored.nextCategoryID > largestID and stored.nextCategoryID <= MAX_CATEGORY_ID + 1,
        "Invalid saved categories. The saved data has been kept.")
    data.nextCategoryID = stored.nextCategoryID
    data.notes = copyNotes(stored.notes)
    for _, note in ipairs(data.notes) do
        assert(note.categoryID == 0 or Notes.FindCategory(data, note.categoryID) ~= nil,
            "Invalid saved note category. The saved data has been kept.")
    end
    return data
end

local function loadData(characterID)
    local stored, message = Storage.Load(Profiles.Key(DB_KEY, characterID))
    assert(message == nil, message)
    if stored ~= nil then return copyData(stored) end
    local data = Notes.New()
    Notes.ResetCategories(data)
    return data
end

function Notes.Load(characterID)
    characterID = assert(Profiles.NormalizeID(characterID), "Invalid character profile.")
    assert(Profiles.IsActive(characterID), "No active character profile.")
    local data = loadData(characterID)
    for _, note in ipairs(data.notes) do
        local tracking = note.tracking
        if tracking and tracking.items and #tracking.items == 1 then
            local generic = tracking.category == "Currencies" and tracking.label == "Currencies"
                or tracking.category == "Invention" and tracking.label == "Components"
                or (tracking.category == "Bossing" or tracking.category == "Slayer") and (tracking.label == "Collection items" or tracking.label == "All items")
            if generic then
                local previous = Tracking.Title(tracking.category, tracking.group, {savedTracking = tracking})
                local title = Tracking.CollectionTitle(tracking.category, tracking.group, tracking.items)
                if validText(title, Notes.MAX_TITLE) then
                    if note.title == previous then note.title = title end
                    tracking.label = tracking.items[1].label
                end
            end
        end
    end
    if not data.trackingCategoriesReviewed then
        for _, note in ipairs(data.notes) do
            if note.categoryID == 0 and note.tracking then
                for _, category in ipairs(data.categories) do
                    if category.name:lower() == note.tracking.category:lower() then
                        note.categoryID = category.id
                        break
                    end
                end
            end
        end
        data.trackingCategoriesReviewed = true
    end
    -- Presets wait for space without preventing this character's existing notes from loading.
    Defaults.Apply(data, Notes)
    owners[data] = {id = characterID, token = Profiles.Token()}
    return data
end

function Notes.Save(data)
    local owner = owners[data]
    if owner == nil or not Profiles.IsActive(owner.id) or owner.token ~= Profiles.Token() then
        return nil, "These notes do not belong to the active character."
    end
    return Storage.Save(Profiles.Key(DB_KEY, owner.id), copyData(data))
end

function Notes.Put(data, index, text, color, title, skill, categoryID, tracking, gear, notifications, actionBar)
    title, skill = title or "", skill or ""
    if title ~= "" and not validText(title, Notes.MAX_TITLE) then return nil, "Enter a title up to 120 characters." end
    if text ~= "" and not validText(text, Notes.MAX_TEXT) then return nil, "Enter a subject up to 4,000 characters." end
    if not validColor(color) then return nil, "Enter a six-digit hex color." end
    if not Sprites.Valid(skill) then return nil, "Choose an icon from the sprite picker." end
    if index == nil and #data.notes >= Notes.MAX_NOTES then return nil, "You have reached the 1,000-note limit." end
    if index ~= nil and data.notes[index] == nil then return nil, "That note no longer exists." end
    if categoryID == nil then categoryID = index and data.notes[index].categoryID or 0 end
    if not validCategoryID(categoryID) or (categoryID ~= 0 and Notes.FindCategory(data, categoryID) == nil) then
        return nil, "Choose an existing category."
    end
    if notifications == nil then notifications = index and data.notes[index] or {} end
    if type(notifications) ~= "table"
        or (notifications.notifyChat ~= nil and type(notifications.notifyChat) ~= "boolean")
        or (notifications.notifyPopup ~= nil and type(notifications.notifyPopup) ~= "boolean") then
        return nil, "Choose valid completion notification settings."
    end
    local note = {title = title, text = text, color = color:upper(), skill = skill, categoryID = categoryID,
        notifyChat = notifications.notifyChat == true, notifyPopup = notifications.notifyPopup == true}
    if index then note.subjectExpanded = data.notes[index].subjectExpanded end
    if tracking == nil and index then tracking = data.notes[index].tracking end
    if tracking ~= nil and tracking ~= false then
        local message
        note.tracking, message = Tracking.Normalize(tracking)
        if note.tracking == nil then return nil, message or "Choose valid tracking settings." end
    end
    if gear == nil and index then gear = data.notes[index].gear end
    if gear ~= nil and gear ~= false then
        local message
        note.gear, message = Gear.Normalize(gear)
        if note.gear == nil then return nil, message or "Choose valid gear setup items." end
    end
    if actionBar == nil and index then actionBar = data.notes[index].actionBar end
    if actionBar ~= nil and actionBar ~= false then
        local message
        note.actionBar, message = ActionBar.Normalize(actionBar)
        if note.actionBar == nil then return nil, message or "Choose a valid action bar." end
    end
    if title == "" and text == "" and Gear.Count(note.gear) == 0 and ActionBar.Count(note.actionBar) == 0 then
        return nil, "Enter a title or subject."
    end
    if index then
        local previous = data.notes[index]
        if note.tracking and (previous.completedTracking ~= nil or previous.progressNotifications ~= nil or previous.notificationPeriod ~= nil) then
            local signature = Notes.TrackingGoalSignature(note.tracking)
            if note.tracking.category == "Scheduled" and previous.tracking
                and Notes.TrackingGoalSignature(previous.tracking) == signature then
                note.notificationPeriod = previous.notificationPeriod
            end
            if previous.progressNotifications ~= nil then
                note.progressNotifications = CollectionProgress.Copy(previous.progressNotifications, signature)
            end
            if previous.completedTracking == signature then
                note.completedTracking = previous.completedTracking
            end
        end
    end
    local staged = stageData(data)
    staged.notes[index or #staged.notes + 1] = note
    local ok, message = DisplayCapacity.Check(data, staged)
    if not ok then return nil, message end
    if index then
        local previous = data.notes[index]
        for key in pairs(previous) do previous[key] = nil end
        for key, value in pairs(note) do previous[key] = value end
    else data.notes[#data.notes + 1] = note end
    return true
end

function Notes.Delete(data, index)
    if data.notes[index] == nil then return false end
    table.remove(data.notes, index)
    return true
end

function Notes.Reorder(data, indices, source, destination)
    if source == destination or source % 1 ~= 0 or destination % 1 ~= 0
        or source < 1 or source > #indices or destination < 1 or destination > #indices then return false end
    local selected, previous = {}, 0
    for position, index in ipairs(indices) do
        if index % 1 ~= 0 or index <= previous or data.notes[index] == nil then return false end
        selected[position] = data.notes[index]
        previous = index
    end
    table.insert(selected, destination, table.remove(selected, source))

    for position, index in ipairs(indices) do data.notes[index] = selected[position] end
    return true
end

local function encode(text)
    return (text:gsub("([^A-Za-z0-9 _%.%-])", function(character)
        return string.format("%%%02X", string.byte(character))
    end))
end

local function decode(text)
    if text:gsub("%%%x%x", ""):find("%%") then return nil end
    return (text:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

local trackingStrings = {"category", "group", "key", "label", "variable", "skill", "ownedVar", "iconSprite"}
local trackingNumbers = {"varId", "target", "base", "iconObj"}
local trackingTypes = {vars = "list", noIcon = "boolean", items = "items", ref = "flag"}
for _, key in ipairs(trackingStrings) do trackingTypes[key] = "string" end
for _, key in ipairs(trackingNumbers) do trackingTypes[key] = "number" end

-- Shared notes leave out the variable id and (when it is the variable) the key; the importer works them out.
local function resolvedID(variable)
    if type(variable) ~= "string" or variable == "" then return nil end
    local _, _, variableID = Vars.resolveVar(variable)
    return variableID
end

local function encodeTracking(tracking, plain)
    if tracking == nil then return "" end
    tracking = assert(Tracking.Normalize(tracking), "Invalid note tracking.")
    -- The label and icon are always written: the importer cannot rebuild them until the game lists they come from have loaded.
    local omitAppearance = false
    local parts = {}
    for _, key in ipairs(trackingStrings) do
        local value = tracking[key]
        if value ~= nil then
            if key == "category" and not plain then
                parts[#parts + 1] = "category=" .. assert(Registry.categoryCode(value), "Unknown tracking type.")
            elseif key == "group" and not plain then
                local code = Registry.groupCode(value)
                parts[#parts + 1] = "group=" .. (code or ("~" .. encode(value)))
            elseif key == "key" and not plain and value == (tracking.ownedVar or tracking.variable) then
                -- left out: the importer uses the owned variable, else the variable
                -- omitted
            elseif key == "variable" and value == "" then
                -- nothing to write
            elseif not (omitAppearance and (key == "label" or key == "iconSprite")) then
                parts[#parts + 1] = key .. "=" .. encode(value)
            end
        end
    end
    for _, key in ipairs(trackingNumbers) do
        local value = tracking[key]
        if value ~= nil then
            if key == "varId" and not plain and value == resolvedID(tracking.variable) then
                -- omitted
            elseif not (omitAppearance and key == "iconObj") then
                parts[#parts + 1] = key .. "=" .. tostring(value)
            end
        end
    end
    if tracking.noIcon ~= nil and not omitAppearance then parts[#parts + 1] = "noIcon=" .. tostring(tracking.noIcon) end
    if omitAppearance then parts[#parts + 1] = "ref=1" end
    if tracking.vars ~= nil then
        local names = {}
        for _, name in ipairs(tracking.vars) do names[#names + 1] = encode(name) end
        parts[#parts + 1] = "vars=" .. table.concat(names, ",")
    end
    if tracking.items ~= nil then
        local items = {}
        for index, item in ipairs(tracking.items) do
            local itemID = item.varId ~= nil and not (not plain and item.varId == resolvedID(item.variable)) and tostring(item.varId) or ""
            items[index] = table.concat({encode(item.variable), encode(item.label or ""),
                tostring(item.iconObj or ""), encode(item.iconSprite or ""), itemID,
                item.noIcon == nil and "" or (item.noIcon and "1" or "0"),
                tostring(item.target), tostring(item.base or ""),
                item.key == item.variable and not plain and "" or encode(item.key or item.variable),
                encode(item.skill or "")}, "~")
        end
        parts[#parts + 1] = "items=" .. table.concat(items, ";")
    end
    local encoded = table.concat(parts, "&")
    assert(#encoded <= MAX_TRACKING_EXPORT, "Note tracking is too large to share.")
    return encoded
end

function Notes.TrackingGoalSignature(tracking)
    if tracking == nil then return "" end
    local goal = assert(Tracking.Normalize(tracking), "Invalid note tracking.")
    local function stripAppearance(item)
        item.label, item.iconObj, item.iconSprite, item.noIcon = nil, nil, nil, nil
        if item.varId ~= nil then
            local ok, namedID = pcall(function() return id.VarPlayer[item.variable:upper()] end)
            if ok and type(namedID) == "number" then item.varId = nil end
        end
        if item.vars then table.sort(item.vars) end
        if item.items then
            for _, child in ipairs(item.items) do stripAppearance(child) end
            table.sort(item.items, function(a, b) return a.key < b.key end)
            item.variable = item.items[1].variable
        end
    end
    stripAppearance(goal)
    return encodeTracking(goal, true)
end

local function decodeTracking(text)
    if text == "" then return nil end
    if #text > MAX_TRACKING_EXPORT then return nil, "The shared tracking is too large." end
    local tracking, useReference = {}, false
    for part in (text .. "&"):gmatch("(.-)&") do
        local key, value = part:match("^([A-Za-z]+)=(.*)$")
        local kind = key and trackingTypes[key]
        if kind == nil or tracking[key] ~= nil then return nil, "The shared tracking is invalid." end
        if kind == "flag" then
            if value ~= "1" then return nil, "The shared tracking is invalid." end
            useReference = true
            tracking[key] = false
            value = nil
        elseif kind == "string" then
            if key == "category" then value = Registry.categoryName(value)
            elseif key == "group" then
                if value:sub(1, 1) == "~" then value = decode(value:sub(2)) else value = Registry.groupName(value) end
            else value = decode(value) end
        elseif kind == "number" then
            value = tonumber(value)
        elseif kind == "boolean" then
            if value ~= "true" and value ~= "false" then return nil, "The shared tracking is invalid." end
            value = value == "true"
        elseif kind == "items" then
            local items = {}
            for item in (value .. ";"):gmatch("(.-);") do
                if #items >= Tracking.MAX_COLLECTION_ITEMS then return nil, "The item collection is too large." end
                local fields = {}
                for field in (item .. "~"):gmatch("(.-)~") do fields[#fields + 1] = field end
                if #fields ~= 10 then return nil, "The shared collection item is invalid." end
                local variable, label, iconObj, iconSprite, varId, noIcon, target, base, itemKey, skill = table.unpack(fields, 1, 10)
                local number, baseNumber = tonumber(target), tonumber(base)
                if number == nil or (base ~= "" and baseNumber == nil) or (iconObj ~= "" and tonumber(iconObj) == nil)
                    or (varId ~= "" and tonumber(varId) == nil)
                    or (noIcon ~= "" and noIcon ~= "0" and noIcon ~= "1") then
                    return nil, "The shared collection item is invalid."
                end
                variable, label, iconSprite, skill = decode(variable), decode(label), decode(iconSprite), decode(skill)
                if variable == nil or label == nil or iconSprite == nil or skill == nil then
                    return nil, "The shared collection item is invalid."
                end
                itemKey = itemKey == "" and variable or decode(itemKey)
                if itemKey == nil or itemKey == "" then return nil, "The shared collection item is invalid." end
                items[#items + 1] = {variable = variable, key = itemKey, target = number,
                    label = label ~= "" and label or nil, iconObj = tonumber(iconObj),
                    iconSprite = iconSprite ~= "" and iconSprite or nil,
                    varId = varId == "" and resolvedID(variable) or tonumber(varId),
                    skill = skill ~= "" and skill or nil, base = baseNumber}
                if noIcon ~= "" then items[#items].noIcon = noIcon == "1" end
            end
            value = items
        elseif kind == "list" then
            local names = {}
            for name in (value .. ","):gmatch("(.-),") do
                name = decode(name)
                if name == nil or name == "" or #names >= 20 then return nil, "The shared tracking is invalid." end
                names[#names + 1] = name
            end
            value = names
        end
        if value == nil and kind ~= "flag" then return nil, "The shared tracking is invalid." end
        if kind ~= "flag" then tracking[key] = value end
    end
    tracking.ref = nil
    -- Left out of the shared text: the key is the owned variable, else the variable, and the id is the game's own.
    if tracking.key == nil and tracking.variable ~= nil and (tracking.ownedVar or tracking.variable) ~= "" then
        tracking.key = tracking.ownedVar or tracking.variable
    end
    if tracking.varId == nil then tracking.varId = resolvedID(tracking.variable) end
    if tracking.items then
        for _, item in ipairs(tracking.items) do item.category, item.group = tracking.category, tracking.group end
    elseif useReference and tracking.category then
        -- Label and icon were left out because they are the ones Notes+ itself shows.
        local reference = Tracking.Reference(tracking)
        if reference then
            for _, field in ipairs({"label", "iconObj", "iconSprite", "noIcon"}) do
                if tracking[field] == nil then tracking[field] = reference[field] end
            end
        end
    end
    local normalized, message = Tracking.Normalize(tracking)
    return normalized, normalized == nil and (message or "The shared tracking is invalid.") or nil
end

local function encodeGear(gear)
    if gear == nil then return "" end
    gear = assert(Gear.Normalize(gear), "Invalid gear setup.")
    local parts = {}
    for _, slot in ipairs(Gear.Slots) do
        if gear[slot.key] then parts[#parts + 1] = slot.key .. "=" .. encode(gear[slot.key]) end
    end
    return #parts == 0 and "-" or table.concat(parts, "&")
end

local function decodeGear(text)
    if text == "" then return nil end
    if text == "-" then return {} end
    if type(text) ~= "string" or #text > MAX_GEAR_EXPORT then return nil, "The shared gear setup is too large." end
    local gear = {}
    for part in (text .. "&"):gmatch("(.-)&") do
        local key, value = part:match("^([a-z]+)=(.*)$")
        if key == nil or gear[key] ~= nil then return nil, "The shared gear setup is invalid." end
        value = decode(value)
        if value == nil then return nil, "The shared gear setup is invalid." end
        gear[key] = value
    end
    return Gear.Normalize(gear)
end

local function encodeActionBar(actionBar)
    if actionBar == nil then return "" end
    actionBar = assert(ActionBar.Normalize(actionBar), "Invalid action bar.")
    local parts = {tostring(actionBar.preset), encode(actionBar.name)}
    for index = 1, ActionBar.SLOT_COUNT do
        local slot = actionBar.slots[index]
        parts[#parts + 1] = slot.type == nil and "-" or table.concat({tostring(slot.type), tostring(slot.action),
            encode(slot.object or ""), encode(slot.sprite or ""), encode(slot.label or "")}, ",")
    end
    return table.concat(parts, "~")
end

local function decodeActionBar(text)
    if text == "" then return nil end
    if type(text) ~= "string" or #text > MAX_ACTION_BAR_EXPORT then return nil, "The shared action bar is too large." end
    local parts = {}
    for part in (text .. "~"):gmatch("(.-)~") do
        parts[#parts + 1] = part
        if #parts > ActionBar.SLOT_COUNT + 2 then return nil, "The shared action bar is invalid." end
    end
    if #parts ~= ActionBar.SLOT_COUNT + 2 or not parts[1]:match("^%d+$") then
        return nil, "The shared action bar is incomplete or invalid."
    end
    local actionBar = {preset = tonumber(parts[1]), name = decode(parts[2]), slots = {}}
    if actionBar.name == nil then return nil, "The shared action bar has an invalid name." end
    for index = 1, ActionBar.SLOT_COUNT do
        local part = parts[index + 2]
        local slot = {}
        if part ~= "-" then
            local slotType, action, object, sprite, label = part:match("^(%d+),(%d+),([^,]*),([^,]*),([^,]*)$")
            if slotType == nil then return nil, "The shared action bar contains an invalid slot." end
            object, sprite, label = decode(object), decode(sprite), decode(label)
            if object == nil or sprite == nil or label == nil then
                return nil, "The shared action bar contains an invalid slot."
            end
            slot = {type = tonumber(slotType), action = tonumber(action), label = label ~= "" and label or nil,
                object = object ~= "" and object or nil, sprite = sprite ~= "" and sprite or nil}
        end
        actionBar.slots[index] = slot
    end
    return ActionBar.Normalize(actionBar)
end

-- Share format: NOTES20|C:<name>:<icon>:<colour>|...|<colour>:<icon>:<category>:<title>:<text>:<tracking>:<gear>:<action bar>:<chat/popup>
-- Notes name their category (empty for none); a C: entry only appears for a category with its own icon or colour.
function Notes.Export(data)
    local categories = data.categories or {}
    local parts = {PREFIX}
    local names = {}
    for _, category in ipairs(categories) do names[category.id] = category.name end
    for _, category in ipairs(categories) do
        if category.skill ~= nil or category.color ~= nil then
            parts[#parts + 1] = "C:" .. encode(category.name) .. ":" .. (category.skill == nil and "" or encode(category.skill))
                .. ":" .. (category.color or "")
        end
    end
    for _, note in ipairs(data.notes) do
        parts[#parts + 1] = note.color .. ":" .. encode(note.skill or "") .. ":" .. encode(names[note.categoryID or 0] or "")
            .. ":" .. encode(note.title or "") .. ":" .. encode(note.text)
            .. ":" .. encodeTracking(note.tracking)
            .. ":" .. encodeGear(note.gear)
            .. ":" .. encodeActionBar(note.actionBar)
            .. ":" .. (note.notifyChat and "1" or "0") .. (note.notifyPopup and "1" or "0")
    end
    return table.concat(parts, "|")
end

function Notes.PlainText(data)
    local parts = {}
    for _, note in ipairs(data.notes) do
        local title = note.title or ""
        local text = title ~= "" and (title .. (note.text ~= "" and "\n" .. note.text or "")) or note.text
        if note.gear ~= nil then
            local gear = {"Gear setup"}
            for _, slot in ipairs(Gear.Slots) do
                local token = note.gear[slot.key]
                if token then
                    local item = Gear.GetItem(token)
                    gear[#gear + 1] = slot.label .. ": " .. (item and item.label or token:sub(6):gsub("_", " "))
                end
            end
            text = text .. (text ~= "" and "\n\n" or "") .. table.concat(gear, "\n")
        end
        if note.actionBar ~= nil then
            local actionBar = {note.actionBar.name ~= "" and note.actionBar.name or "Action bar " .. note.actionBar.preset}
            for index = 1, ActionBar.SLOT_COUNT do
                local slot = note.actionBar.slots[index]
                actionBar[#actionBar + 1] = tostring(index) .. ": " .. (slot.type == nil and "Empty" or ActionBar.Label(slot))
            end
            text = text .. (text ~= "" and "\n\n" or "") .. table.concat(actionBar, "\n")
        end
        parts[#parts + 1] = text
    end
    return table.concat(parts, "\n\n")
end


function Notes.Parse(text, trusted)
    if type(text) ~= "string" or #text > Notes.MAX_EXPORT then return nil, "The shared notes are too large." end
    if not text:match("^%s*NOTES%d+|") then
        text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
        local title, subject = text:match("^([^\n]*)\n(.*)$")
        if title == nil then title, subject = text, "" end
        local data = Notes.New()
        local ok, message = Notes.Put(data, nil, subject, "FFFFFF", title, "")
        if not ok then return nil, message end
        return data
    end
    text = text:match("^%s*(.-)%s*$")
    text = text:gsub("\r\n", " "):gsub("[\r\n]", " ")
    local parts = {}
    for part in (text .. "|"):gmatch("(.-)|") do
        parts[#parts + 1] = part
        if #parts > Notes.MAX_NOTES + Notes.MAX_CATEGORIES + 1 then return nil, "There are too many notes or categories." end
    end
    if parts[1] ~= PREFIX then return nil, "Paste the full text from Share notes." end
    local data = Notes.New()
    local function categoryFor(name)
        if name == "" then return 0 end
        for _, category in ipairs(data.categories) do
            if category.name:lower() == name:lower() then return category.id end
        end
        if #data.categories >= Notes.MAX_CATEGORIES then return nil, "There are too many notes or categories." end
        local added, nextID = createCategory(data, name, {})
        if not added then return nil, "The shared notes contain an invalid category." end
        data.categories[#data.categories + 1], data.nextCategoryID = added, nextID
        return added.id
    end
    for index = 2, #parts do
        local part = parts[index]
        if part:sub(1, 2) == "C:" then
            local name, skill, color = part:match("^C:([^:]*):([^:]*):([^:]*)$")
            name = name and categoryName(decode(name))
            skill = skill and decode(skill)
            if name == nil or skill == nil or (color ~= "" and not validColor(color))
                or not categoryAppearance({skill = skill ~= "" and skill or nil, color = color ~= "" and color or nil}) then
                return nil, "The shared notes contain an invalid category."
            end
            local categoryID, message = categoryFor(name)
            if categoryID == nil then return nil, message end
            for _, category in ipairs(data.categories) do
                if category.id == categoryID then
                    category.skill, category.color = skill ~= "" and skill or nil, color ~= "" and color:upper() or nil
                end
            end
        else
            local color, skill, categoryText, title, noteText, trackingText, gearText, barText, notifications =
                part:match("^(%x%x%x%x%x%x):([^:]*):([^:]*):([^:]*):([^:]*):([^:]*):([^:]*):([^:]*):([01][01])$")
            if color == nil then return nil, "The shared notes are incomplete or invalid." end
            if #data.notes >= Notes.MAX_NOTES then return nil, "There are too many notes or categories." end
            local message
            local tracking, gear, actionBar
            tracking, message = decodeTracking(trackingText)
            if message ~= nil then return nil, message end
            gear, message = decodeGear(gearText)
            if message ~= nil then return nil, message end
            actionBar, message = decodeActionBar(barText)
            if message ~= nil then return nil, message end
            skill, categoryText = decode(skill), decode(categoryText)
            local categoryName_ = categoryText == "" and "" or categoryText and categoryName(categoryText)
            if skill == nil or categoryName_ == nil then return nil, "The shared notes contain an invalid category reference." end
            local categoryID
            categoryID, message = categoryFor(categoryName_)
            if categoryID == nil then return nil, message end
            local note = readNote({color = color, skill = skill, title = decode(title), text = decode(noteText),
                categoryID = categoryID, tracking = tracking, gear = gear, actionBar = actionBar,
                notifyChat = notifications:sub(1, 1) == "1", notifyPopup = notifications:sub(2, 2) == "1"})
            if not note then return nil, "The shared notes contain an invalid note." end
            -- Notes from outside may only track what Notes+ itself offers.
            if not trusted then
                local allowed, reason = Tracking.CheckImported(note.tracking)
                if not allowed then return nil, reason end
            end
            note.color = color:upper()
            data.notes[#data.notes + 1] = note
        end
    end
    return data
end

function Notes.Import(data, text, trusted)
    local imported, message = Notes.Parse(text, trusted)
    if imported == nil then return nil, message end
    if #data.notes + #imported.notes > Notes.MAX_NOTES then return nil, "There are too many notes to import." end
    local merged, categoryIDs = copyData(data), {[0] = 0}
    for _, category in ipairs(imported.categories) do
        local categoryID
        for _, existing in ipairs(merged.categories) do
            if existing.name:lower() == category.name:lower() then
                categoryID = existing.id
                if category.skill ~= nil or category.color ~= nil then existing.skill, existing.color = category.skill, category.color end
                break
            end
        end
        if categoryID == nil then
            local added, nextID = createCategory(merged, category.name, category)
            if not added then return nil, nextID end
            categoryID = added.id
            merged.categories[#merged.categories + 1], merged.nextCategoryID = added, nextID
        end
        categoryIDs[category.id] = categoryID
    end
    for _, saved in ipairs(imported.notes) do
        local note = readNote(saved)
        note.categoryID = categoryIDs[note.categoryID]
        merged.notes[#merged.notes + 1] = note
    end
    for index, note in ipairs(data.notes) do merged.notes[index] = note end
    local ok
    ok, message = DisplayCapacity.Check(data, merged)
    if not ok then return nil, message end
    data.categories, data.nextCategoryID, data.notes = merged.categories, merged.nextCategoryID, merged.notes
    return true
end

return Notes
