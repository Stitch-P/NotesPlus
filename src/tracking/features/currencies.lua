-- The Currencies type: names and ordering.

local currencies_m = require("src/tracking/data/currencies")
local CURRENCIES = currencies_m.CURRENCIES
local Vars = require("src/tracking/core/vars")
local Pouch = require("src/tracking/core/pouch")

local function currencyName(currency)
    if currency.obj and not currency.ownName then
        local ok, name = pcall(function() return config.Obj.FromID(currency.obj).name end)
        if ok and type(name) == "string" and name ~= "" and name ~= "null" then return name end
    end
    return currency.name
end

-- A currency whose variable name isn't certain: the first candidate the game knows (then kept), or nil.
local function resolved(currency)
    if not currency.candidates then return true end
    if currency.found then return true end
    for _, name in ipairs(currency.candidates) do
        if Vars.resolveVar(name) then
            currency.var, currency.found = name, true
            return true
        end
    end
    return false
end

local function plain(text) return (tostring(text or ""):lower():gsub("[^%a]", "")) end

-- Currencies the game's currency pouch holds that the list above does not have, so one the game adds turns up without a
-- plugin update. A pouch stack the list already covers (same object, variable or name) is not repeated.
local function pouchExtras()
    local objects, variables, names = {}, {}, {}
    for _, currency in ipairs(CURRENCIES) do
        if currency.obj then objects[currency.obj] = true end
        variables[tostring(currency.var):upper()] = true
        names[plain(currency.name)] = true
        names[plain(currencyName(currency))] = true
    end
    local extras = {}
    for _, stack in ipairs(Pouch.stacks()) do
        if not objects[stack.obj] and not variables[stack.var:upper()] and not names[plain(stack.name)] and Vars.resolveVar(stack.var) then
            extras[#extras + 1] = { var = stack.var, obj = stack.obj, name = stack.name, fromPouch = true }
        end
    end
    return extras
end

local function sortedCurrencies()
    local list = {}
    for _, currency in ipairs(CURRENCIES) do
        if resolved(currency) then list[#list + 1] = { currency = currency, label = currencyName(currency) } end
    end
    for _, currency in ipairs(pouchExtras()) do list[#list + 1] = { currency = currency, label = currency.name } end
    table.sort(list, function(a, b)
        local x, y = a.label:lower(), b.label:lower()
        if x ~= y then return x < y end
        return a.currency.var < b.currency.var
    end)
    return list
end

local function isCurrency(name)
    for _, currency in ipairs(CURRENCIES) do
        if currency.var == name then return true end
        for _, candidate in ipairs(currency.candidates or {}) do
            if candidate == name then return true end
        end
    end
    return Pouch.isStack(name)
end

local function skillIconFor(name)
    for _, currency in ipairs(CURRENCIES) do
        if currency.var == name then return currency.skillIcon end
    end
end

return {
    skillIconFor = skillIconFor,
    -- The skill whose icon the note's header wears (its tile keeps the currency's own picture), or nil.
    headerSkillFor = function(name)
        for _, currency in ipairs(CURRENCIES) do
            if currency.var == name then return currency.headerSkill end
        end
    end,
    currencyName = currencyName,
    sortedCurrencies = sortedCurrencies,
    isCurrency = isCurrency,
}