local AHT = WOW4E_AHT

AHT.Store = {}

local DEFAULT_DB = {
    schemaVersion = 1,
    market = {},
    byItemID = {},
    history = {},
    recipes = {},
    materials = {},
    settings = {
        minMarginPercent = 10,
        dealThresholdPercent = 20,
        historyLimit = 20,
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
    WOW4E_AHT_DB = WOW4E_AHT_DB or {}
    CopyDefaults(WOW4E_AHT_DB, DEFAULT_DB)
    if tonumber(WOW4E_AHT_DB.schemaVersion) ~= 1 then
        WOW4E_AHT_DB.schemaVersion = 1
    end
    AHT.DB = WOW4E_AHT_DB
    return AHT.DB
end

function AHT.Store:Save()
    if AHT.DB then WOW4E_AHT_DB = AHT.DB end
end

function AHT.Store:ResetMarket()
    AHT.DB.market = {}
    AHT.DB.byItemID = {}
    AHT.DB.history = {}
    self:Save()
end

function AHT.Store:MarketKey(itemID, itemKey)
    return AHT:ItemKeyString(itemKey or AHT:MakeItemKey(itemID))
end

function AHT.Store:Get(itemID, itemKey)
    local key = self:MarketKey(itemID, itemKey)
    return key and AHT.DB.market[key], key
end

function AHT.Store:GetByItemID(itemID)
    local key = AHT.DB.byItemID[tostring(itemID)]
    return key and AHT.DB.market[key], key
end

function AHT.Store:GetPrice(itemID, itemKey)
    local record = self:Get(itemID, itemKey)
    if record and record.minPrice then return record.minPrice end
    local fallback = self:GetByItemID(itemID)
    return fallback and fallback.minPrice or nil
end

function AHT.Store:RecordMarket(target, result)
    local key = self:MarketKey(target.itemID, target.itemKey)
    if not key then return nil end
    local now = AHT:Now()
    local record = AHT.DB.market[key] or {}
    record.key = key
    record.itemID = target.itemID
    record.name = target.name or record.name or (AHT:GetItemInfo(target.itemID))
    record.kind = result.kind or target.kind or record.kind or "unknown"
    record.minPrice = result.minPrice
    record.totalQuantity = result.totalQuantity or 0
    record.listingCount = result.listingCount or 0
    record.updatedAt = now
    record.build = AHT.Capabilities and AHT.Capabilities.build
    AHT.DB.market[key] = record
    AHT.DB.byItemID[tostring(target.itemID)] = key

    if result.minPrice and result.minPrice > 0 then
        local history = AHT.DB.history[key] or {}
        table.insert(history, { t = now, p = result.minPrice, q = result.totalQuantity or 0 })
        local limit = tonumber(AHT.DB.settings.historyLimit) or 20
        while #history > limit do table.remove(history, 1) end
        AHT.DB.history[key] = history
    end
    self:Save()
    return record
end

function AHT.Store:Average(key)
    local history = AHT.DB.history[key]
    if not history or #history == 0 then return nil end
    local total = 0
    for _, entry in ipairs(history) do total = total + (entry.p or 0) end
    return math.floor(total / #history)
end

function AHT.Store:WeightedAverage(key)
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

function AHT.Store:IsDeal(key, currentPrice)
    local average = self:Average(key)
    local threshold = (tonumber(AHT.DB.settings.dealThresholdPercent) or 20) / 100
    return average and currentPrice and currentPrice < average * (1 - threshold)
end

function AHT.Store:AddMaterial(itemID, name)
    AHT.DB.materials[tostring(itemID)] = {
        itemID = itemID,
        name = name or tostring(itemID),
        enabled = true,
    }
    self:Save()
end

function AHT.Store:RemoveMaterial(itemID)
    AHT.DB.materials[tostring(itemID)] = nil
    self:Save()
end
