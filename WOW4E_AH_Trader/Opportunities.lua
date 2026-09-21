local AHT = WOW4E_AHT

-- Conservative opportunity finder. It never buys automatically: a row is a
-- decision aid based on the current lowest listing, an age-weighted market
-- value, AH cut, liquidity and (when available) vendor value.
AHT.Opportunities = { results = {} }

local function VendorSellPrice(itemID)
    if not itemID or not AHT.GetItemInfo then return nil end
    local ok, _, _, _, _, _, _, _, _, _, _, sellPrice = pcall(AHT.GetItemInfo, AHT, itemID)
    if ok and tonumber(sellPrice) and tonumber(sellPrice) > 0 then return tonumber(sellPrice) end
    return nil
end

local function Confidence(snapshot)
    local days = math.max(tonumber(snapshot.marketSamples) or 0, tonumber(snapshot.scanSamples) or 0)
    local listings = tonumber(snapshot.priceSampleCount) or 0
    return math.min(100, days * 20 + math.min(listings, 20) * 2)
end

function AHT.Opportunities:Build()
    local rows = {}
    local db = AHT.DB
    local store = AHT.Store
    if not db or not store then return rows end

    local settings = db.settings or {}
    local cut = (tonumber(settings.auctionCutPercent) or 5) / 100
    local threshold = (tonumber(settings.dealThresholdPercent) or 20) / 100
    local minimumSamples = tonumber(settings.minMarketSamples) or 2

    local craftCosts = {}
    for _, result in ipairs(AHT.Calculator and AHT.Calculator.results or {}) do
        if result.output and result.output.itemID and result.ingredientCost and result.ingredientCost > 0 then
            craftCosts[tonumber(result.output.itemID)] = {
                cost = tonumber(result.costPerOutput) or tonumber(result.ingredientCost),
                result = result,
            }
        end
    end

    for _, record in pairs(db.market or {}) do
        local itemID = tonumber(record.itemID)
        local snapshot = itemID and store:GetMarketSnapshot(itemID, record.itemKey)
        local current = snapshot and snapshot.currentPrice
        local market = snapshot and snapshot.marketValue
        local confidenceSamples = snapshot and math.max(snapshot.marketSamples or 0, snapshot.scanSamples or 0) or 0

        -- Buy chance: the latest AH listing is below the robust, history-based
        -- reference value. This remains conservative and requires confidence.
        if current and market and market > 0 and confidenceSamples >= minimumSamples then
            local discount = (1 - current / market) * 100
            if discount >= threshold then
                local ahNet = math.floor(market * (1 - cut))
                local vendor = VendorSellPrice(itemID)
                local vendorProfit = vendor and vendor - current or nil
                local ahProfit = ahNet - current
                local bestValue, bestMethod = ahNet, "AH"
                if vendor and vendor > bestValue then
                    bestValue, bestMethod = vendor, "NPC"
                end
                local profit = bestValue - current
                table.insert(rows, {
                    kind = "opportunity",
                    side = "buy",
                    opportunityType = "Kaufchance",
                    name = record.name or AHT:GetItemInfo(itemID) or tostring(itemID),
                    itemID = itemID,
                    itemKey = record.itemKey,
                    currentPrice = current,
                    marketValue = market,
                    averagePrice = snapshot.averagePrice,
                    priceChangePercent = snapshot.priceChangePercent,
                    trendPercent = snapshot.trendPercent,
                    discount = discount,
                    profit = profit,
                    ahProfit = ahProfit,
                    vendorProfit = vendorProfit,
                    roi = current > 0 and (profit / current * 100) or 0,
                    quantity = snapshot.totalQuantity,
                    listingCount = snapshot.listingCount,
                    confidence = Confidence(snapshot),
                    bestMethod = bestMethod,
                    p25 = snapshot.p25,
                    p75 = snapshot.p75,
                    updatedAt = snapshot.updatedAt,
                })
            end
        end

        -- Sell chance: only items actually owned by the character are shown.
        -- A sale is attractive when the current price is above the robust
        -- market value, above the craft cost, or clearly above vendor value.
        local stock = AHT.Inventory and AHT.Inventory:GetCount(itemID) or { total = 0 }
        local owned = tonumber(stock and stock.total) or 0
        if current and current > 0 and owned > 0 then
            local vendor = VendorSellPrice(itemID)
            local craft = craftCosts[itemID]
            local costBasis = craft and craft.cost or vendor
            local sellNet = math.floor(current * (1 - cut))
            local sellProfit = costBasis and (sellNet - costBasis) or nil
            local premium = market and market > 0 and (current / market - 1) * 100 or nil
            local aboveMarket = premium and confidenceSamples >= minimumSamples and premium >= threshold * 100
            local craftProfitable = sellProfit and craft and sellProfit >= craft.cost * threshold
            local vendorProfitable = sellProfit and vendor and sellProfit >= vendor * threshold
            if aboveMarket or craftProfitable or vendorProfitable then
                table.insert(rows, {
                    kind = "opportunity",
                    side = "sell",
                    opportunityType = "Verkaufschance",
                    name = record.name or AHT:GetItemInfo(itemID) or tostring(itemID),
                    itemID = itemID,
                    itemKey = record.itemKey,
                    currentPrice = current,
                    marketValue = market,
                    averagePrice = snapshot and snapshot.averagePrice,
                    priceChangePercent = snapshot and snapshot.priceChangePercent,
                    trendPercent = snapshot and snapshot.trendPercent,
                    discount = premium or 0,
                    profit = sellProfit,
                    ahProfit = sellProfit,
                    vendorProfit = vendor and (vendor - (costBasis or 0)) or nil,
                    roi = costBasis and costBasis > 0 and ((sellNet - costBasis) / costBasis * 100) or 0,
                    quantity = owned,
                    stockBags = stock.bags or 0,
                    stockBank = stock.bank or 0,
                    bankKnown = stock.bankKnown,
                    listingCount = snapshot and snapshot.listingCount or 0,
                    confidence = Confidence(snapshot or {}),
                    bestMethod = "AH",
                    p25 = snapshot and snapshot.p25,
                    p75 = snapshot and snapshot.p75,
                    updatedAt = snapshot and snapshot.updatedAt,
                    costBasis = costBasis,
                    craftCost = craft and craft.cost,
                    recipe = craft and craft.result,
                })
            end
        end
    end

    table.sort(rows, function(a, b)
        if (a.profit or 0) == (b.profit or 0) then
            if a.side ~= b.side then return a.side == "sell" end
            return (a.confidence or 0) > (b.confidence or 0)
        end
        return (a.profit or 0) > (b.profit or 0)
    end)
    self.results = rows
    return rows
end

function AHT.Opportunities:Find(itemID)
    for _, row in ipairs(self.results or {}) do
        if tonumber(row.itemID) == tonumber(itemID) then return row end
    end
end
