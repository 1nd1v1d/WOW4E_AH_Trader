local AHT = WOW4E_AHT

AHT.Store = {}

local DEFAULT_DB = {
    schemaVersion = 3,
    market = {},
    byItemID = {},
    history = {},
    dailyHistory = {},
    recipes = {},
    recipeIndex = {},
    professions = {},
    materials = {},
    inventory = {
        characters = {},
    },
    production = {
        serial = 0,
        orders = {},
        purchases = {},
    },
    ui = {
        x = 0,
        y = 0,
        width = 780,
        height = 600,
        viewMode = "recipes",
        sortColumn = "profit",
        sortAscending = false,
    },
    settings = {
        minMarginPercent = 10,
        dealThresholdPercent = 20,
        historyLimit = 100,
        auctionCutPercent = 5,
        productionSuggestionShare = 0.10,
        productionSuggestionCap = 20,
        productionPriceSlippagePercent = 25,
        marketDayLimit = 30,
        marketTrimPercent = 10,
        minMarketSamples = 2,
        -- Older market snapshots still matter, but their influence decays
        -- exponentially. Seven days is the default half-life.
        averageHalfLifeSeconds = 604800,
        -- Modern C_AuctionHouse APIs expect 1/2/3, not hours.
        defaultDuration = 2,
    },
}

local function CopyDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if target[key] == nil then
            if type(value) == "table" then
                target[key] = {}
                CopyDefaults(target[key], value)
            else
                target[key] = value
            end
        elseif type(value) == "table" and type(target[key]) == "table" then
            CopyDefaults(target[key], value)
        end
    end
end

function AHT.Store:Load()
    if type(WOW4E_AHT_DB) ~= "table" then WOW4E_AHT_DB = {} end
    local tableKeys = {
        "market", "byItemID", "history", "dailyHistory", "recipes", "recipeIndex", "professions", "materials",
        "inventory", "production", "ui", "settings",
    }
    for _, key in ipairs(tableKeys) do
        if type(WOW4E_AHT_DB[key]) ~= "table" then WOW4E_AHT_DB[key] = {} end
    end
    CopyDefaults(WOW4E_AHT_DB, DEFAULT_DB)
    -- Older beta builds kept only 20 snapshots. Move that implicit default
    -- to the larger history window so the weighted average can use more scans.
    if tonumber(WOW4E_AHT_DB.settings.historyLimit) == 20 then
        WOW4E_AHT_DB.settings.historyLimit = 100
    end
    WOW4E_AHT_DB.schemaVersion = 3
    AHT.DB = WOW4E_AHT_DB
    self:RebuildIndexes()
    return AHT.DB
end

function AHT.Store:Save()
    if AHT.DB then
        self:RebuildIndexes()
        WOW4E_AHT_DB = AHT.DB
    end
end

function AHT.Store:EnsureLoaded()
    if type(AHT.DB) ~= "table" or type(AHT.DB.market) ~= "table" or
            type(AHT.DB.byItemID) ~= "table" or type(AHT.DB.history) ~= "table" then
        if type(WOW4E_AHT_DB) ~= "table" then return false end
        self:Load()
    end
    return type(AHT.DB) == "table"
end

function AHT.Store:RebuildIndexes()
    if not AHT.DB then return end
    AHT.DB.market = AHT.DB.market or {}
    AHT.DB.byItemID = AHT.DB.byItemID or {}
    -- Older beta snapshots could contain valid market records while the
    -- byItemID lookup was empty or pointed to a removed key. Rebuild the
    -- lookup on every load/save so prices remain visible after a restart.
    for key, record in pairs(AHT.DB.market) do
        if type(record) == "table" and record.itemID then
            local itemID = tostring(record.itemID)
            local indexedKey = AHT.DB.byItemID[itemID]
            local indexedRecord = indexedKey and AHT.DB.market[indexedKey]
            if not indexedRecord or tonumber(indexedRecord.itemID) ~= tonumber(record.itemID) then
                AHT.DB.byItemID[itemID] = key
            end
        end
    end
end

function AHT.Store:ResetMarket()
    AHT.DB.market = {}
    AHT.DB.byItemID = {}
    AHT.DB.history = {}
    AHT.DB.dailyHistory = {}
    self:Save()
end

function AHT.Store:MarketKey(itemID, itemKey)
    return AHT:ItemKeyString(itemKey or AHT:MakeItemKey(itemID))
end

function AHT.Store:Get(itemID, itemKey)
    local key = self:MarketKey(itemID, itemKey)
    if not key or not self:EnsureLoaded() or type(AHT.DB.market) ~= "table" then return nil, key end
    return key and AHT.DB.market[key], key
end

function AHT.Store:GetByItemID(itemID)
    if not self:EnsureLoaded() or type(AHT.DB.market) ~= "table" or type(AHT.DB.byItemID) ~= "table" then return nil end
    local key = AHT.DB.byItemID[tostring(itemID)]
    return key and AHT.DB.market[key], key
end

function AHT.Store:GetPrice(itemID, itemKey)
    local record = self:Get(itemID, itemKey)
    if record and record.minPrice then return record.minPrice end
    local fallback = self:GetByItemID(itemID)
    return fallback and fallback.minPrice or nil
end

local function Percentile(values, fraction)
    if #values == 0 then return nil end
    local position = (#values - 1) * fraction + 1
    local lower = math.floor(position)
    local upper = math.ceil(position)
    if lower == upper then return values[lower] end
    return values[lower] + (values[upper] - values[lower]) * (position - lower)
end

function AHT.Store:CalculatePriceStats(prices)
    local values = {}
    for _, price in ipairs(prices or {}) do
        price = tonumber(price)
        if price and price > 0 then table.insert(values, price) end
    end
    if #values == 0 then return nil end
    table.sort(values)

    local trimPercent = tonumber(AHT.DB and AHT.DB.settings.marketTrimPercent) or 10
    local trim = math.floor(#values * math.max(0, math.min(40, trimPercent)) / 100)
    if trim * 2 >= #values then trim = 0 end
    local first, last = trim + 1, #values - trim
    local total = 0
    for index = first, last do total = total + values[index] end
    local count = math.max(1, last - first + 1)
    return {
        min = math.floor(values[1]),
        p25 = math.floor(Percentile(values, 0.25) + 0.5),
        median = math.floor(Percentile(values, 0.50) + 0.5),
        p75 = math.floor(Percentile(values, 0.75) + 0.5),
        trimmedMean = math.floor(total / count + 0.5),
        sampleCount = #values,
    }
end

function AHT.Store:RecordMarket(target, result)
    if not self:EnsureLoaded() then return nil end
    local key = self:MarketKey(target.itemID, target.itemKey)
    if not key then return nil end
    local now = AHT:Now()
    local record = AHT.DB.market[key] or {}
    record.key = key
    record.itemID = target.itemID
    record.itemKey = target.itemKey or record.itemKey
    record.name = target.name or record.name or (AHT:GetItemInfo(target.itemID))
    record.kind = result.kind or target.kind or record.kind or "unknown"
    record.minPrice = result.minPrice
    record.totalQuantity = result.totalQuantity or 0
    record.listingCount = result.listingCount or 0
    local stats = result.stats or self:CalculatePriceStats(result.prices)
    if stats then
        record.p25 = stats.p25
        record.medianPrice = stats.median
        record.p75 = stats.p75
        record.marketValue = stats.trimmedMean or stats.median
        record.priceSampleCount = stats.sampleCount
    elseif result.minPrice and result.minPrice > 0 then
        record.marketValue = record.marketValue or result.minPrice
    end
    record.updatedAt = now
    record.build = AHT.Capabilities and AHT.Capabilities.build
    AHT.DB.market[key] = record
    AHT.DB.byItemID[tostring(target.itemID)] = key

    if result.minPrice and result.minPrice > 0 then
        local history = AHT.DB.history[key] or {}
        table.insert(history, {
            t = now,
            p = result.minPrice,
            q = result.totalQuantity or 0,
            m = record.marketValue,
            s = record.priceSampleCount or result.listingCount or 0,
        })
        local limit = tonumber(AHT.DB.settings.historyLimit) or 20
        while #history > limit do table.remove(history, 1) end
        AHT.DB.history[key] = history

        local daily = AHT.DB.dailyHistory[key] or {}
        local day = math.floor(now / 86400)
        local dayRecord
        for _, entry in ipairs(daily) do
            if tonumber(entry.d) == day then dayRecord = entry break end
        end
        local dayPrice = tonumber(record.medianPrice or record.marketValue or result.minPrice)
        if dayPrice and dayPrice > 0 then
            if dayRecord then
                local scans = tonumber(dayRecord.n) or 0
                dayRecord.p = math.floor(((tonumber(dayRecord.p) or dayPrice) * scans + dayPrice) / (scans + 1) + 0.5)
                dayRecord.q = math.max(tonumber(dayRecord.q) or 0, tonumber(result.totalQuantity) or 0)
                dayRecord.s = math.max(tonumber(dayRecord.s) or 0, tonumber(record.priceSampleCount) or 0)
                dayRecord.n = scans + 1
                dayRecord.t = now
            else
                table.insert(daily, {
                    d = day,
                    t = now,
                    p = dayPrice,
                    q = result.totalQuantity or 0,
                    s = record.priceSampleCount or result.listingCount or 0,
                    n = 1,
                })
            end
            table.sort(daily, function(a, b) return (tonumber(a.d) or 0) < (tonumber(b.d) or 0) end)
            local dayLimit = tonumber(AHT.DB.settings.marketDayLimit) or 30
            while #daily > dayLimit do table.remove(daily, 1) end
            AHT.DB.dailyHistory[key] = daily
        end
    end
    self:Save()
    return record
end

function AHT.Store:Average(key)
    if not self:EnsureLoaded() then return nil end
    local history = AHT.DB.history[key]
    if not history or #history == 0 then return nil end
    local total = 0
    for _, entry in ipairs(history) do total = total + (entry.p or 0) end
    return math.floor(total / #history)
end

function AHT.Store:WeightedAverage(key)
    if not self:EnsureLoaded() then return nil end
    local history = AHT.DB.history[key]
    if not history or #history == 0 then return nil end
    local weightedTotal, weight = 0, 0
    local simpleTotal, samples = 0, 0
    for _, entry in ipairs(history) do
        local price = tonumber(entry.p)
        local quantity = tonumber(entry.q) or 0
        if price and price > 0 then
            simpleTotal = simpleTotal + price
            samples = samples + 1
            if quantity > 0 then
                weightedTotal = weightedTotal + price * quantity
                weight = weight + quantity
            end
        end
    end
    if weight > 0 then return math.floor(weightedTotal / weight) end
    if samples > 0 then return math.floor(simpleTotal / samples) end
    return nil
end

function AHT.Store:RecencyAverage(itemID, itemKey)
    if not self:EnsureLoaded() then return nil, 0 end
    local key = self:MarketKey(itemID, itemKey)
    local history = key and AHT.DB.history[key]
    if (not history or #history == 0) and itemID and AHT.DB.byItemID then
        local fallbackKey = AHT.DB.byItemID[tostring(itemID)]
        history = fallbackKey and AHT.DB.history[fallbackKey]
    end
    if not history or #history == 0 then return nil, 0 end

    local now = AHT:Now() or time()
    local halfLife = tonumber(AHT.DB.settings.averageHalfLifeSeconds) or 604800
    halfLife = math.max(1, halfLife)
    local weightedTotal, weight, samples = 0, 0, 0
    for _, entry in ipairs(history) do
        local price = tonumber(entry.p)
        if price and price > 0 then
            local timestamp = tonumber(entry.t) or now
            local age = math.max(0, now - timestamp)
            local influence = 2 ^ (-age / halfLife)
            weightedTotal = weightedTotal + price * influence
            weight = weight + influence
            samples = samples + 1
        end
    end
    if weight == 0 then return nil, 0 end
    return math.floor(weightedTotal / weight + 0.5), samples
end

function AHT.Store:GetPriceChange(itemID, itemKey)
    if not self:EnsureLoaded() then return nil, nil end
    local key = self:MarketKey(itemID, itemKey)
    local history = key and AHT.DB.history[key]
    if (not history or #history == 0) and itemID and AHT.DB.byItemID then
        local fallbackKey = AHT.DB.byItemID[tostring(itemID)]
        key = fallbackKey or key
        history = fallbackKey and AHT.DB.history[fallbackKey]
    end
    if not history or #history < 2 then return nil, nil end
    local latest = tonumber(history[#history].p)
    local previous = tonumber(history[#history - 1].p)
    if not latest or not previous or previous <= 0 then return nil, previous end
    return (latest / previous - 1) * 100, previous
end

function AHT.Store:RobustMarketValue(itemID, itemKey)
    if not self:EnsureLoaded() then return nil, 0 end
    local key = self:MarketKey(itemID, itemKey)
    local daily = key and AHT.DB.dailyHistory[key]
    if (not daily or #daily == 0) and itemID and AHT.DB.byItemID then
        local fallbackKey = AHT.DB.byItemID[tostring(itemID)]
        key = fallbackKey or key
        daily = fallbackKey and AHT.DB.dailyHistory[fallbackKey]
    end

    local now = AHT:Now() or time()
    local halfLife = tonumber(AHT.DB.settings.averageHalfLifeSeconds) or 604800
    halfLife = math.max(1, halfLife)
    local weightedTotal, totalWeight, days = 0, 0, 0
    for _, entry in ipairs(daily or {}) do
        local price = tonumber(entry.p)
        if price and price > 0 then
            local age = math.max(0, now - (tonumber(entry.t) or now))
            local freshness = 2 ^ (-age / halfLife)
            local sampleWeight = math.min(tonumber(entry.s) or 1, 10)
            local weight = freshness * (0.75 + sampleWeight * 0.25)
            weightedTotal = weightedTotal + price * weight
            totalWeight = totalWeight + weight
            days = days + 1
        end
    end
    if totalWeight > 0 then return math.floor(weightedTotal / totalWeight + 0.5), days end

    local record = key and AHT.DB.market[key]
    if record and record.marketValue then return record.marketValue, 1 end
    local fallback, samples = self:RecencyAverage(itemID, itemKey)
    return fallback, samples or 0
end

function AHT.Store:GetMarketSnapshot(itemID, itemKey)
    local record, key = self:Get(itemID, itemKey)
    if not record and itemID then record, key = self:GetByItemID(itemID) end
    if not record then return nil end
    local marketValue, marketSamples = self:RobustMarketValue(itemID, itemKey)
    local averagePrice, scanSamples = self:RecencyAverage(itemID, itemKey)
    local currentPrice = tonumber(record.minPrice)
    local priceChangePercent, previousPrice = self:GetPriceChange(itemID, itemKey)
    local trendPercent
    if currentPrice and marketValue and marketValue > 0 then
        trendPercent = (currentPrice / marketValue - 1) * 100
    end
    return {
        key = key,
        itemID = record.itemID or itemID,
        itemKey = record.itemKey or itemKey,
        name = record.name,
        kind = record.kind,
        currentPrice = currentPrice,
        marketValue = marketValue,
        averagePrice = averagePrice,
        medianPrice = tonumber(record.medianPrice),
        p25 = tonumber(record.p25),
        p75 = tonumber(record.p75),
        trendPercent = trendPercent,
        priceChangePercent = priceChangePercent,
        previousPrice = previousPrice,
        totalQuantity = tonumber(record.totalQuantity) or 0,
        listingCount = tonumber(record.listingCount) or 0,
        marketSamples = marketSamples or 0,
        scanSamples = scanSamples or 0,
        priceSampleCount = tonumber(record.priceSampleCount) or 0,
        updatedAt = tonumber(record.updatedAt),
    }
end

function AHT.Store:IsDeal(key, currentPrice)
    if not self:EnsureLoaded() then return false end
    local record = key and AHT.DB.market[key]
    local marketValue, samples = record and self:RobustMarketValue(record.itemID, record.itemKey)
    local _, scanSamples = record and self:RecencyAverage(record.itemID, record.itemKey)
    samples = math.max(samples or 0, scanSamples or 0)
    local threshold = (tonumber(AHT.DB.settings.dealThresholdPercent) or 20) / 100
    local minimum = tonumber(AHT.DB.settings.minMarketSamples) or 2
    return marketValue and currentPrice and samples >= minimum and currentPrice < marketValue * (1 - threshold)
end

function AHT.Store:AddMaterial(itemID, name)
    if not self:EnsureLoaded() then return false end
    AHT.DB.materials = AHT.DB.materials or {}
    AHT.DB.materials[tostring(itemID)] = {
        itemID = itemID,
        name = name or tostring(itemID),
        enabled = true,
    }
    self:Save()
    return true
end

function AHT.Store:RemoveMaterial(itemID)
    if not self:EnsureLoaded() then return false end
    AHT.DB.materials = AHT.DB.materials or {}
    AHT.DB.materials[tostring(itemID)] = nil
    self:Save()
    return true
end
