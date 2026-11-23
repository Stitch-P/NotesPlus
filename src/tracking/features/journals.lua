local providers = {
    require("src/tracking/features/menaphos_journal").MenaphosJournal,
    require("src/tracking/features/arc_journal").ArcJournal,
}

local Journals = {}

local function provider(key)
    for _, journal in ipairs(providers) do
        if journal.isPage(key) then return journal end
    end
end

function Journals.groups()
    local groups = {}
    for index, journal in ipairs(providers) do groups[index] = {name = journal.GROUP} end
    return groups
end

function Journals.isGroup(name)
    for _, journal in ipairs(providers) do if journal.GROUP == name then return true end end
    return false
end

function Journals.options(name)
    for _, journal in ipairs(providers) do if journal.GROUP == name then return journal.options() end end
    return {}
end

function Journals.isPage(key)
    return provider(key) ~= nil
end

function Journals.items(key)
    local journal = provider(key)
    return journal and journal.items(key)
end

function Journals.progress(key, includeSlots)
    local journal = provider(key)
    return journal and journal.progress(key, includeSlots)
end

for _, name in ipairs({"sprite", "object", "label", "card", "readItem"}) do
    Journals[name] = function(item)
        local journal = item and provider(item.journalKey)
        if journal and journal[name] then return journal[name](item) end
    end
end

function Journals.Clear()
    for _, journal in ipairs(providers) do journal.Clear() end
end

return Journals
