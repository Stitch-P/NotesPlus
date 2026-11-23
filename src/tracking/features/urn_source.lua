-- Urns, found by name in the game's own object list: "<Tier> <skill> urn (<stage>)". Nothing is hand-listed, so new urn
-- skills or tiers show up by themselves. The object list is walked a few hundred ids per frame (Pump) so no frame stalls.

local UrnSource = {}

UrnSource.TIERS = { "Cracked", "Fragile", "Plain", "Strong", "Decorated", "Exquisite" }
local TIER_BY_WORD = {}
for _, tier in ipairs(UrnSource.TIERS) do TIER_BY_WORD[tier:lower()] = tier end

local MAX_ID, PER_FRAME = 120000, 300
local cursor, done = 0, false
local found = {}          -- { { id, tier, skill, stage, name } ... } in id order
local byId = {}
local seen = {}

-- unfired: made, still to be fired. empty: fired and ready to start gathering "(empty)". Urns with no rune, no gem or that
-- are being filled are other stages and are left out; so is anything whose name doesn't say which stage it is.
local function stageOf(rest)
    rest = rest:lower()
    if rest:find("(full)", 1, true) then return "full", true end
    if rest:find("(unfired)", 1, true) or rest:find("(unf)", 1, true) then return "unfired", true end
    if rest:find("(empty)", 1, true) then return "empty", true end
    return "other", false
end

-- Noted ("cert") copies carry the same name as the real item but point at a template object.
local NOTE_FIELDS = { "certTemplate", "certtemplate", "noteTemplate", "notedTemplate", "certlink", "certLink" }
local function isNoted(cfg)
    for _, field in ipairs(NOTE_FIELDS) do
        local ok, value = pcall(function() return cfg[field] end)
        if ok and type(value) == "number" and value > 0 then return true end
    end
    return false
end

local function look(objId)
    local okCfg, cfg = pcall(function() return config.Obj.FromID(objId) end)
    if not okCfg or not cfg then return end
    local ok, name = pcall(function() return cfg.name end)
    if not ok or type(name) ~= "string" then return end
    local lower = name:lower()
    if not lower:find(" urn", 1, true) then return end
    local word, skill, rest = lower:match("^(%a+) (.-) urn%s*(.*)$")
    if not word then word, rest = lower:match("^(%a+) urn%s*(.*)$"); skill = "" end
    local tier = word and TIER_BY_WORD[word]
    if not tier then return end
    if skill == "" then skill = "Any" end
    if lower:find("noted", 1, true) or lower:find("cert", 1, true) or isNoted(cfg) then return end
    local stage, explicit = stageOf(rest)
    -- Placeholders and noted copies reuse the real item's name; the real one has the lowest id, so keep that one only.
    local sameName = lower
    if seen[sameName] then return end
    seen[sameName] = true
    local entry = { id = objId, tier = tier, skill = skill:gsub("^%l", string.upper), stage = stage, explicit = explicit, name = name }
    found[#found + 1], byId[objId] = entry, entry
end

-- Call once per frame; does nothing once the whole list has been walked.
function UrnSource.Pump()
    if done then return end
    local last = math.min(MAX_ID, cursor + PER_FRAME - 1)
    for objId = cursor, last do look(objId) end
    cursor = last + 1
    if cursor > MAX_ID then done = true end
end

function UrnSource.Done() return done end
function UrnSource.All() return found end
function UrnSource.Entry(objId) return byId[objId] end

-- One tier's urns at one stage ("empty" or "full"), ordered by skill.
function UrnSource.Urns(tier, stage)
    local list = {}
    for _, entry in ipairs(found) do
        if entry.tier == tier and entry.stage == stage then list[#list + 1] = entry end
    end
    -- Drop a bare-name guess when the same skill has an urn that says "(r)" / "empty" outright.
    local explicitSkill = {}
    for _, entry in ipairs(list) do if entry.explicit then explicitSkill[entry.skill] = true end end
    for index = #list, 1, -1 do
        if not list[index].explicit and explicitSkill[list[index].skill] then table.remove(list, index) end
    end
    table.sort(list, function(a, b)
        if a.skill ~= b.skill then return a.skill < b.skill end
        return a.id < b.id
    end)
    return list
end

return { UrnSource = UrnSource }