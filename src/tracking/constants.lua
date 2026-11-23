local categories = {"Bossing", "Clues", "Combat", "Currencies", "Gathering", "Invention", "Ports", "Production", "Quests", "Scheduled", "Skills", "Slayer", "Tasks", "Training", "Unlocks"}

return {
    ITEMLOG_PREFIX = "ITEMLOG_ITEM_",
    KILLS_PREFIX = "BSLAY_KILLS_",
    categoryIndex = function(name)
        for index, category in ipairs(categories) do
            if category == name then return index end
        end
        return 0
    end
}