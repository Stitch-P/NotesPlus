local CollectionFormat = {}

function CollectionFormat.Shape(tracking)
    if not tracking or not tracking.items then return false, false, false end
    local expanded = tracking.category == "Skills" or tracking.category == "Clues"
        or tracking.category == "Ports" and (tracking.group == "Trade Goods" or tracking.group == "Ports Resources")
        or tracking.category == "Invention" and tracking.group == "Research: Components"
        or tracking.category == "Production" or tracking.category == "Training" or tracking.category == "Gathering"
    local extended, keyed = tracking.category == "Currencies", expanded
    for _, item in ipairs(tracking.items) do
        if item.key ~= item.variable then keyed = true end
        if item.base ~= nil or (tracking.category == "Bossing" or tracking.category == "Slayer") and item.target ~= 1 then extended = true end
    end
    return extended or keyed, keyed, expanded
end

return CollectionFormat
