-- Picking an icon for the note we need!

local constants_m = require("src/tracking/constants")
local ITEMLOG_PREFIX = constants_m.ITEMLOG_PREFIX
local objects_m = require("src/tracking/core/objects")
local findObjectID = objects_m.findObjectID
local vars_m = require("src/tracking/core/vars")
local trim = vars_m.trim

-- Varp name -> object name, for the few where the two don't line up.
local ICON_OVERRIDES = {
    ITEMLOG_ITEM_GWD2_TELOS_PIECE_MELEE = "GWD2_SOLO_MELEE_WEAPON_PIECE",
    ITEMLOG_ITEM_GWD2_TELOS_PIECE_MAGIC = "GWD2_SOLO_MAGIC_WEAPON_PIECE",
    ITEMLOG_ITEM_GWD2_TELOS_PIECE_RANGED = "GWD2_SOLO_RANGED_WEAPON_PIECE",
}

local BOSS_PET_ICONS = {
    BSLAY_KILLS_YAKAMARU = "BPETS_YAKAMARU_DROP",
    SB_PLAYER_PET_MELEE = "SB_PET_SPIDER_MELEE_POH",
    SB_PLAYER_PET_RANGE = "SB_PET_SPIDER_RANGE_POH",
    SB_PLAYER_PET_MAGIC = "SB_PET_SPIDER_MAGIC_POH",
    SB_PLAYER_PET_REFLECT = "SB_PET_SPIDER_REFLECT_POH",
    SB_PLAYER_PET_HEALER = "SB_PET_SPIDER_HEALER_POH",
    SB_PLAYER_PET_ACID = "SB_PET_SPIDER_ACID_POH",
    BPETS_ARAXXOR_UNLOCKED = "BPETS_ARAXXOR_POH",
    BPETS_ARAXXI_UNLOCKED = "BPETS_ARAXXI_POH",
}

local function bossPetIcon(varName)
    local name = type(varName) == "string" and BOSS_PET_ICONS[varName:upper()]
    return name and findObjectID(name) or nil
end

--No MTX, nope.
local EXCLUDED_PREFIXES = { "MTX", "WOF" }

local function isExcluded(rawName)
    for part in tostring(rawName or ""):upper():gmatch("[^_]+") do
        for _, word in ipairs(EXCLUDED_PREFIXES) do
            if part:sub(1, #word) == word then return true end
        end
    end
    return false
end

-- Object for a varp name: override first, then the name without ITEMLOG_ITEM_,
-- then the name as is.
local function iconObjectFor(varName)
    if type(varName) ~= "string" or varName == "" then return nil end

    local petIcon = bossPetIcon(varName)
    if petIcon then return petIcon end

    local override = ICON_OVERRIDES[varName]
    if override then
        local objId = findObjectID(override)
        if objId then return objId end
    end

    if varName:sub(1, #ITEMLOG_PREFIX) == ITEMLOG_PREFIX then
        local objId = findObjectID(varName:sub(#ITEMLOG_PREFIX + 1))
        if objId then return objId end
    end

    return findObjectID(varName)
end

-- The icon for a saved note.
local function iconObjectForNote(note)
    if note.iconObj then return note.iconObj end

    local objId = iconObjectFor(note.variable)
    if objId then return objId end

    local guess = trim(note.text):upper():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
    if guess ~= "" and #guess <= 60 then
        return findObjectID(guess)
    end
    return nil
end

return {
    isExcluded = isExcluded,
    bossPetIcon = bossPetIcon,
    iconObjectForNote = iconObjectForNote,
}
