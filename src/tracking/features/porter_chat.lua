-- Reads the game's chat for the message a Porter sends when it moves gathered items to your bank
-- ("You transport to your bank: 1 x Raw trout."), so they can be counted for Gathering notes: they never pass through the
-- backpack, ore box or metal bank, which are the places the counting watches.
-- Needs the chatAccess permission (without it the client sends no chat events).

local PorterChat = {}
local EVENT = "notes_plus_chat"
local MAX_PENDING = 200

local pending = {}
local banked = {}   -- "... was sent straight to your bank" messages: { text = lower-case, count = n }

-- "You transport to your bank: 1 x Raw trout." -> { { name = "raw trout", count = 1 } }
function PorterChat.Parse(text)
    local list = {}
    if type(text) ~= "string" then return list end
    text = text:gsub("<[^>]*>", "")
    local body = text:match("[Tt]ransport to your bank:%s*(.+)$")
    if not body then return list end
    for count, name in body:gmatch("(%d[%d,]*)%s*x%s*([^,]+)") do
        name = name:gsub("%.%s*$", ""):gsub("^%s+", ""):gsub("%s+$", "")
        local amount = tonumber((count:gsub(",", "")))
        if amount and amount > 0 and name ~= "" then list[#list + 1] = { name = name:lower(), count = amount } end
    end
    return list
end

-- Any message saying something was sent to the bank ("Your artificer's measure has manufactured an extra item: Decorated
-- smithing urn (unfired). It was sent straight to your bank."). Kept whole; each note then looks for its own item's name.
function PorterChat.ParseBanked(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub("<[^>]*>", ""):lower()
    if not (text:find("sent straight to your bank", 1, true) or text:find("sent to your bank", 1, true)
        or text:find("to your material storage", 1, true)) then return nil end
    local digits = (text:match("(%d[%d,]*)%s*x%s") or ""):gsub(",", "")
    local count = tonumber(digits) or 1
    return { text = text, count = count > 0 and count or 1 }
end

-- How many of an item (by its in-game name) the bank messages since the last Take say were sent, in total.
function PorterChat.BankedCount(list, name)
    if not list or type(name) ~= "string" or name == "" then return 0 end
    local needle, total = name:lower(), 0
    for _, entry in ipairs(list) do
        local start, finish = entry.text:find(needle, 1, true)
        if start then
            local before, after = entry.text:sub(start - 1, start - 1), entry.text:sub(finish + 1, finish + 1)
            if not before:match("[%w]") and not after:match("[%w]") then total = total + entry.count end
        end
    end
    return total
end

-- The bank messages since the last call.
function PorterChat.TakeBanked()
    if #banked == 0 then return nil end
    local list = banked
    banked = {}
    return list
end

-- The same chat line can reach us twice (one event per chat channel it is shown in), and Porter lines come seconds
-- apart, so an identical line arriving again within a fraction of a second is the same message.
local DUPLICATE_SECONDS = 0.35
local lastText, lastAt
local function isDuplicate(text)
    -- The plugin sandbox doesn't always offer os; without a clock lines are simply not de-duplicated.
    local now = type(os) == "table" and (os.clock and os.clock() or os.time and os.time()) or nil
    if not now then lastText, lastAt = text, nil; return false end
    local duplicate = text == lastText and lastAt ~= nil and now - lastAt < DUPLICATE_SECONDS
    lastText, lastAt = text, now
    return duplicate
end

local function record(text)
    if isDuplicate(text) then return end
    local bank = PorterChat.ParseBanked(text)
    if bank then
        if #banked >= MAX_PENDING then table.remove(banked, 1) end
        banked[#banked + 1] = bank
    end
    for _, delivery in ipairs(PorterChat.Parse(text)) do
        if #pending >= MAX_PENDING then table.remove(pending, 1) end
        pending[#pending + 1] = delivery
    end
end

-- What has been transported since the last call: { [lower-case item name] = total }.
function PorterChat.Take()
    if #pending == 0 then return nil end
    local totals = {}
    for _, delivery in ipairs(pending) do totals[delivery.name] = (totals[delivery.name] or 0) + delivery.count end
    pending = {}
    return totals
end

-- Only the game's own messages count: the GENERAL channel (value 0, where "You catch a trout."), SPAM (109, where the Porter's bank lines
-- arrive) and ENGINE (4), and only when no player is named as the sender. Anything a player can type (public, private,
-- friends, clan, group, quick chat...) is ignored, so nobody can pass a fake "You transport to your bank: 20 x Raw trout."
-- line to someone else's goals.
local GAME_CHANNELS = { GENERAL = 0, ENGINE = 4, SPAM = 109 }
local SENDER_FIELDS = { "senderNameUnfiltered", "senderNameFiltered", "senderNameSimple" }

function PorterChat.IsGameMessage(event)
    if event == nil or event.chatType == nil then return false end
    for _, field in ipairs(SENDER_FIELDS) do
        local okField, value = pcall(function() return event[field] end)
        if okField and type(value) == "string" and value ~= "" then return false end
    end
    local kind = event.chatType
    for name, number in pairs(GAME_CHANNELS) do
        local okType, value = pcall(function() return ChatType[name] end)
        if kind == number or okType and value ~= nil and kind == value then return true end
        local okNumber, asNumber = pcall(tonumber, kind)
        if okNumber and asNumber == number then return true end
    end
    return false
end

function PorterChat.Start()
    local ok, allowed = pcall(function() return Plugin.HasPermission(PluginPermissions.chatAccess) end)
    if not ok or not allowed then return false end
    return pcall(function()
        Event.ChatMessage.Subscribe(EVENT, function(event)
            if PorterChat.IsGameMessage(event) and type(event.chatMessage) == "string" then record(event.chatMessage) end
        end)
    end)
end

function PorterChat.Stop()
    pcall(function() Event.ChatMessage.Unsubscribe(EVENT) end)
    pending, banked = {}, {}
end

return PorterChat