-- Prifddinas recipe shop: one goal per combo potion recipe, done once the recipe is unlocked. The recipes (objects) are the
-- game's ELFCITY_RECIPE_SHOP enum; each has an ELFCITY_RECIPE_UNLOCK_* variable that says it is yours.
local Vars = require("src/tracking/core/vars")
local objects_m = require("src/tracking/core/objects")
local RECIPES = require("src/tracking/data/recipe_shop").RECIPES

local Recipes = {}
Recipes.GROUP = "Prifddinas"
Recipes.SECTION = "Recipe Shop"
Recipes.RAVENS = "Ravens"

local byVar
local function index()
    if byVar then return byVar end
    byVar = {}
    for _, recipe in ipairs(RECIPES) do byVar[recipe.var] = recipe end
    return byVar
end

function Recipes.isKey(key) return type(key) == "string" and index()[key] ~= nil end

-- "ELFCITY_RECIPE_UNLOCK_2COMBOSUPREMEOVERLOAD" -> "Supreme overload" (the game's own object name is preferred).
local function fallbackName(var)
    local text = var:gsub("^ELFCITY_RECIPE_UNLOCK_", ""):gsub("^2COMBO", "Combo "):gsub("^COMBO", ""):lower()
    return (text:gsub("^%l", string.upper))
end

function Recipes.options()
    local options = {}
    for _, recipe in ipairs(RECIPES) do
        local label = objects_m.objectDisplayName(recipe.obj) or fallbackName(recipe.var)
        options[#options + 1] = {
            kind = "recipe", key = recipe.var, label = label, varName = recipe.var, defaultTarget = 1, objId = recipe.obj,
            description = "Unlock this recipe in the Prifddinas recipe shop.",
        }
    end
    table.sort(options, function(a, b) return a.label:lower() < b.label:lower() end)
    return options
end

return { Recipes = Recipes }
