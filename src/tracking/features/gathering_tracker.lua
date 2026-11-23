-- Counts new ores and bars for Gathering notes, without ever adding up what you already own.
--
-- Each poll looks at the metal bank, ore box and backpack. When one place drops, that amount becomes a short-lived
-- "moved" credit; when another place rises, the credit is used up first and only what's left counts as gained.
-- So depositing ore from your backpack into the ore box (or withdrawing it) is never counted twice, while ore you
-- mine, smelt into bars, or otherwise newly receive is.

local Mining = require("src/tracking/features/mining").Mining
local Production = require("src/tracking/features/production").Production
local SlayerTask = require("src/tracking/features/slayer_task").SlayerTask

local GatheringTracker = {}

local CREDIT_SECONDS = 4
-- A Porter delivery only covers the same item turning up in a place within a poll or two, so it can never swallow a log
-- you cut yourself a few seconds later.
local PORTER_SECONDS = 1.2
local PLACES = 4
local states = setmetatable({}, { __mode = "k" })

-- One step of the counting. state = { last = { n1, n2, n3, n4 }, credit, creditAt }. Returns how much was gained.
-- countsFrom[place] == false means that place only offsets moves (it never counts as a gain itself).
function GatheringTracker.Step(state, now, current, countsFrom)
    local gained = 0
    if state.credit > 0 and now - state.creditAt > CREDIT_SECONDS then state.credit = 0 end
    if (state.porter or 0) > 0 and now - (state.porterAt or now) > PORTER_SECONDS then state.porter = 0 end
    local rises = {}
    for place = 1, PLACES do
        local value, previous = current[place], state.last[place]
        if value ~= nil then
            if previous ~= nil then
                local delta = value - previous
                if delta < 0 then
                    state.credit, state.creditAt = state.credit - delta, now
                elseif delta > 0 then
                    rises[#rises + 1] = { delta, not (countsFrom and countsFrom[place] == false) }
                end
            end
            state.last[place] = value
        end
    end
    -- One new item can show up in more than one place at once (the game updates the wood box total as well as the
    -- backpack when you cut a log), so rises seen in the same poll count once, by the largest of them.
    local largest = 0
    for _, rise in ipairs(rises) do
        local delta = rise[1]
        local fromPorter = math.min(state.porter or 0, delta)
        state.porter = (state.porter or 0) - fromPorter
        delta = delta - fromPorter
        local used = math.min(state.credit, delta)
        state.credit = state.credit - used
        if rise[2] then largest = math.max(largest, delta - used) end
    end
    return gained + largest
end

local function signature(tracking)
    return tostring(tracking.key) .. "|" .. tostring(tracking.target)
end

-- Counts one tracked thing (a whole note, or one item of a Production selection).
local function pollOne(owner, tracking, category, now, delivered, bankMessages, PorterChat)
    local item = category == "Gathering" and Mining.info(tracking.key) or Production.info(tracking.key)
    if not item then return false end
    local slot = states[owner]
    if not slot then slot = {}; states[owner] = slot end
    local state = slot[tracking.key]
    if not state then
        state = { key = tracking.key, last = {}, credit = 0, creditAt = now }
        slot[tracking.key] = state
    end
    -- Items a Porter sent straight to the bank (seen in chat) count once. Their credit is added before the places are read,
    -- so should the same items also show up in the backpack, ore box, wood box or bank in this very poll, that rise is
    -- covered by the credit instead of being counted a second time.
    local transported = category == "Gathering" and delivered and item.name and delivered[item.name:lower()] or 0
    -- "... was sent straight to your bank": any note counts those too, found by the item's in-game name.
    if bankMessages and PorterChat then
        transported = transported + PorterChat.BankedCount(bankMessages, item.gameName or item.name)
    end
    if transported > 0 then
        state.porter, state.porterAt = (state.porter or 0) + transported, now
    end
    local ok, gained = pcall(function()
        if category == "Production" or category == "Training" then
            -- Backpack and metal bank count; the normal bank only offsets moves.
            local pack, bank, metal = Production.places(item)
            return GatheringTracker.Step(state, now, { pack, bank, metal }, { true, false, true })
        end
        -- The normal bank only offsets moves, so taking items out of it never counts as gathering them.
        local bank, box, pack = Mining.places(item)
        return GatheringTracker.Step(state, now, { bank, box, pack, Mining.inventoryCount("BANK", item.objId) },
            { true, true, true, false })
    end)
    if transported > 0 then
        if ok then gained = gained + transported else ok, gained = true, transported end
    end
    if ok and gained > 0 then
        -- The counting above always runs so the readings stay current, but a finished goal stops at its target.
        local before = tracking.gained or 0
        local target = tracking.target
        local after = before + gained
        if type(target) == "number" and target > 0 and after > target then after = math.max(before, target) end
        if after > before then
            tracking.gained = after
            return true
        end
    end
    return false
end

-- Goes through the notes and adds what's been gained. Returns true when any note's count changed.
function GatheringTracker.Poll(notes, now)
    local changed = false
    local okChat, PorterChat = pcall(require, "src/tracking/features/porter_chat")
    local delivered = okChat and PorterChat.Take() or nil
    local bankMessages = okChat and PorterChat.TakeBanked() or nil
    if not okChat then PorterChat = nil end
    for _, note in ipairs(notes) do
        local tracking = note.tracking
        local category = tracking and tracking.category
        if category == "Gathering" or category == "Production" or category == "Training" then
            if tracking.items then
                for _, child in ipairs(tracking.items) do
                    if pollOne(note, child, category, now, delivered, bankMessages, PorterChat) then changed = true end
                end
            elseif pollOne(note, tracking, category, now, delivered, bankMessages, PorterChat) then
                changed = true
            end
        end
    end
    -- Slayer / Reaper task notes ride on the same poll: they remember the size of the current assignment.
    local okTask, taskChanged = pcall(SlayerTask.Poll, notes)
    if okTask and taskChanged then changed = true end
    return changed
end

return { GatheringTracker = GatheringTracker }