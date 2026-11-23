local Sprites = require("src/data/sprite_catalog")
local Directory = {}
Directory.__index = Directory

local shared
local LOOKUPS_PER_TICK = 512
local ITEMS_PER_TICK = 256
local FILTERS_PER_TICK = 8000
local EMPTY_RANGE = 4096
local SCAN_LIMIT = 262144
local CACHE_LIMIT = 8

local function words(text)
    local result = {}
    for word in text:lower():gmatch("[%w]+") do result[#result + 1] = word end
    return result
end

local function spriteName(number)
    local name = id.Sprite.FromID(number)
    if type(name) ~= "string" or #name > Sprites.MAX_NAME_LENGTH then return nil end
    name = name:upper()
    if not name:match("^[A-Z0-9_]+$") or Sprites.IsBlocked(name) then return nil end
    if id.Sprite[name] ~= number then return nil end
    return name
end

local function itemRecord(number)
    local name = id.Obj.FromID(number)
    if type(name) ~= "string" or not name:match("^[A-Z0-9_]+$") or id.Obj[name] ~= number then return nil end
    return Sprites.Item(number, name)
end

local function copyResults(results)
    local copy = {}
    for index, record in ipairs(results) do copy[index] = record end
    return copy
end

local function exactItem(text)
    local name = text:match("^%s*([%w_]+)%s*$")
    if not name then return nil end
    local ok, record = pcall(Sprites.Get, "item/" .. name:upper())
    if ok and record then
        record.search = record.label:lower() .. " " .. Sprites.ConfigName(record):gsub("_", " "):lower()
        return record
    end
end

local function includeExact(query)
    if not query.exactItem then return end
    for _, record in ipairs(query.results) do
        if record.name == query.exactItem.name then return end
    end
    table.insert(query.results, 1, query.exactItem)
end

local function queryKey(terms, itemsOnly)
    local sorted, seen = {}, {}
    for _, term in ipairs(terms) do
        if not seen[term] then sorted[#sorted + 1], seen[term] = term, true end
    end
    table.sort(sorted)
    return (itemsOnly and "items:" or "all:") .. table.concat(sorted, "\0")
end

local function querySource(self, itemsOnly)
    if itemsOnly and self.records == self.indexedRecords and #self.records == self.indexedCount then
        return self.itemRecords
    end
    return self.records
end

local function addRecord(self, record, item)
    if self.recordNames[record.name] then return false end
    self.recordNames[record.name] = true
    self.records[#self.records + 1] = record
    self.indexedCount = #self.records
    if item then self.itemRecords[#self.itemRecords + 1] = record end
    return true
end

local function refines(terms, previous)
    for _, oldTerm in ipairs(previous) do
        local implied = false
        for _, term in ipairs(terms) do
            if term:find(oldTerm, 1, true) then implied = true break end
        end
        if not implied then return false end
    end
    return true
end

local function cacheQuery(self, query)
    if not self:IsComplete(query.itemsOnly) then return end
    local source = querySource(self, query.itemsOnly)
    for index = #self.cache, 1, -1 do
        if self.cache[index].key == query.key then table.remove(self.cache, index) end
    end
    self.cache[#self.cache + 1] = {key = query.key, words = query.words, itemsOnly = query.itemsOnly,
        source = source, count = #source, results = copyResults(query.results)}
    if #self.cache > CACHE_LIMIT then table.remove(self.cache, 1) end
end

function Directory.Open()
    if shared then return shared end
    local records = {}
    shared = setmetatable({records = records, indexedRecords = records, indexedCount = 0,
        itemRecords = {}, recordNames = {}, cache = {}, finished = false, nextID = 0, empty = 0,
        revision = 0, items = {nextID = 0, empty = 0, count = 0}}, Directory)
    return shared
end

function Directory:DiscoverSprites()
    if self.spritesFinished then return end
    local previousCount = #self.records
    for _ = 1, LOOKUPS_PER_TICK do
        local ok, name = pcall(spriteName, self.nextID)
        self.nextID = self.nextID + 1
        if ok and name then
            self.empty = 0
            local label = name:gsub("_", " "):lower()
            addRecord(self, {name = name, label = label, spriteID = self.nextID - 1})
        else
            self.empty = self.empty + 1
        end
        if self.empty >= EMPTY_RANGE or self.nextID >= SCAN_LIMIT then
            self.spritesFinished = true
            break
        end
    end
    if self.spritesFinished then self.spriteSearchPending = false end
    if #self.records ~= previousCount or self.spritesFinished then self.revision = self.revision + 1 end
end

function Directory:FindSprite(text, predicate)
    if not self.spritesFinished then self.spriteSearchPending = true end
    local terms = words(text)
    if #terms == 0 then return nil end
    local best
    for _, record in ipairs(self.records) do
        if not record.objectID then
            local matches = true
            for _, term in ipairs(terms) do
                if not record.label:find(term, 1, true) then matches = false break end
            end
            if matches and (not predicate or predicate(record))
                and (not best or #record.name < #best.name or (#record.name == #best.name and record.name < best.name)) then
                best = record
            end
        end
    end
    if best then return Sprites.SpriteID(best.name), best.name end
end

function Directory:IsComplete(itemsOnly)
    return self.finished == true or (itemsOnly == true and self.items.finished == true)
end

function Directory:Discover(options)
    if self.finished then return end
    if not (options and options.itemsOnly) then self:DiscoverSprites() end
    local items = self.items
    if id.Obj == nil then items.finished = true end
    for _ = 1, items.finished and 0 or ITEMS_PER_TICK do
        local ok, record = pcall(itemRecord, items.nextID)
        items.nextID = items.nextID + 1
        if ok and record then
            items.empty = 0
            record.search = record.label:lower() .. " " .. Sprites.ConfigName(record):gsub("_", " "):lower()
            if addRecord(self, record, true) then items.count = items.count + 1 end
        else
            items.empty = items.empty + 1
        end
        if items.empty >= EMPTY_RANGE or items.nextID >= SCAN_LIMIT then items.finished = true; break end
    end
    self.finished = self.spritesFinished == true and items.finished == true
    self.unavailable = self.finished and #self.records == 0
end

function Directory:Query(text, options)
    local terms = words(text)
    local query = {text = text, words = terms, cursor = 1, results = {}, complete = #terms == 0,
        itemsOnly = options and options.itemsOnly == true or false}
    if not query.complete then query.exactItem = exactItem(text) end
    if query.exactItem then
        if addRecord(self, query.exactItem, true) then self.items.count = self.items.count + 1 end
        self.unavailable = false
    end
    includeExact(query)
    query.key = queryKey(terms, query.itemsOnly)
    if query.complete or not self:IsComplete(query.itemsOnly) then return query end
    local source, best = querySource(self, query.itemsOnly), nil
    for index = #self.cache, 1, -1 do
        local cached = self.cache[index]
        if cached.itemsOnly == query.itemsOnly and cached.source == source and cached.count == #source then
            if cached.key == query.key then
                query.results, query.complete, query.cursor = copyResults(cached.results), true, #source + 1
                includeExact(query)
                cached.results = copyResults(query.results)
                table.remove(self.cache, index)
                self.cache[#self.cache + 1] = cached
                return query
            end
            if refines(terms, cached.words) and (not best or #cached.results < #best.results) then best = cached end
        end
    end
    if best then
        query.candidates, query.candidateSource, query.candidateCount = best.results, source, #source
    end
    return query
end

function Directory:Continue(query, skipDiscovery)
    if query.complete then return false end
    if not skipDiscovery then self:Discover({itemsOnly = query.itemsOnly}) end
    local indexed = querySource(self, query.itemsOnly)
    if query.candidates and (query.candidateSource ~= indexed or query.candidateCount ~= #indexed) then
        query.candidates, query.cursor, query.results = nil, 1, {}
        includeExact(query)
    end
    local source = query.candidates or indexed
    local previous = #query.results
    local last = math.min(#source, query.cursor + FILTERS_PER_TICK - 1)
    for index = query.cursor, last do
        local record = source[index]
        local matches = (not query.itemsOnly or record.objectID ~= nil)
            and (not query.exactItem or record.name ~= query.exactItem.name)
        if matches then
            for _, word in ipairs(query.words) do
                if not (record.search or record.label):find(word, 1, true) then matches = false; break end
            end
        end
        if matches then query.results[#query.results + 1] = record end
    end
    query.cursor = last + 1
    local complete = self:IsComplete(query.itemsOnly) and query.cursor > #source
    local changed = previous ~= #query.results or complete ~= query.complete
    query.complete = complete
    if complete then cacheQuery(self, query) end
    return changed
end

function Directory.Reset()
    shared = nil
    Sprites.Reset()
end

return Directory
