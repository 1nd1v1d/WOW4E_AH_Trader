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
    local days = tonumber(snapshot.marketSamples) or 0
    local listings = tonumber(snapshot.priceSampleCount) or 0
    local age = math.max(0, AHT:Now() - (tonumber(snapshot.updatedAt) or 0))
    local distributionFresh = (tonumber(snapshot.distributionAge) or math.huge) <= 86400
    local spread = snapshot.p25 and snapshot.p75 and snapshot.p25 > 0 and snapshot.p75 / snapshot.p25 or 1
    return math.floor(math.min(100, days * 15 + (distributionFresh and math.min(listings, 20) * 2 or 0))
        * 2 ^ (-age / 86400) / math.max(1, spread))
end

function AHT.Opportunities:Build()
    local rows = {}
    local db = AHT.DB
    local store = AHT.Store
    if not db or not store then return rows end

    local settings = db.settings or {}
    local cut = (tonumber(settings.auctionCutPercent) or 5) / 100
    local threshold = tonumber(settings.dealThresholdPercent) or 20
    local minimumProfit = math.max(1, tonumber(settings.minimumProfitCopper) or 1)
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
        local confidenceSamples = snapshot and (snapshot.marketSamples or 0) or 0
        local fresh = snapshot and snapshot.updatedAt and AHT:Now() - snapshot.updatedAt <= (tonumber(settings.maxPriceAgeSeconds) or 86400)
        local buyAdded = false

        -- Buy chance: the latest AH listing is below the robust, history-based
        -- reference value. This remains conservative and requires confidence.
        if fresh and current and market and market > 0 and confidenceSamples >= minimumSamples then
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
                if profit >= minimumProfit then buyAdded = true; table.insert(rows, {
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
                    quantity = nil,
                    availableSupply = snapshot.totalQuantity,
                    listingCount = snapshot.listingCount,
                    confidence = Confidence(snapshot),
                    bestMethod = bestMethod,
                    p25 = snapshot.p25,
                    p75 = snapshot.p75,
                    updatedAt = snapshot.updatedAt,
                    source = snapshot.source,
                    marketSamples = confidenceSamples,
                }) end
            end
        end

        -- NPC liquidation is a known payout, not a speculative AH resale.
        local npcValue = fresh and current and VendorSellPrice(itemID)
        if not buyAdded and npcValue and npcValue - current >= minimumProfit
                and (npcValue - current) / current * 100 >= (tonumber(settings.minMarginPercent) or 10) then
            table.insert(rows, { kind = "opportunity", side = "buy", opportunityType = "NPC-Kaufchance",
                name = record.name or tostring(itemID), itemID = itemID, itemKey = record.itemKey,
                currentPrice = current, marketValue = market, profit = npcValue - current,
                vendorProfit = npcValue - current, roi = (npcValue - current) / current * 100,
                discount = (1 - current / npcValue) * 100, bestMethod = "NPC", confidence = Confidence(snapshot),
                availableSupply = snapshot.totalQuantity, listingCount = snapshot.listingCount,
                updatedAt = snapshot.updatedAt, source = snapshot.source, marketSamples = confidenceSamples })
        end

        -- Sell chance: include inventory snapshots from the same tradable character pool.
        -- A sale is attractive when the current price is above the robust
        -- market value, above the craft cost, or clearly above vendor value.
        local stock = AHT.Inventory and AHT.Inventory:GetCount(itemID) or { total = 0 }
        local owned = tonumber(stock and stock.total) or 0
        if fresh and current and current > 0 and owned > 0 then
            local vendor = VendorSellPrice(itemID)
            local craft = craftCosts[itemID]
            local costBasis = craft and craft.cost or nil
            local sellNet = math.floor(current * (1 - cut))
            local sellProfit = costBasis and (sellNet - costBasis) or nil
            local premium = market and market > 0 and (current / market - 1) * 100 or nil
            local aboveMarket = premium and confidenceSamples >= minimumSamples and premium >= threshold
            local craftProfitable = sellProfit and craft and sellProfit >= minimumProfit and sellProfit >= craft.cost * threshold / 100
            if aboveMarket or craftProfitable then
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
                    vendorIncome = vendor,
                    netIncome = sellNet,
                    roi = costBasis and costBasis > 0 and ((sellNet - costBasis) / costBasis * 100) or 0,
                    quantity = owned,
                    stockBags = stock.accountBags or stock.bags or 0,
                    stockBank = stock.accountBank or stock.bank or 0,
                    bankKnown = stock.accountBankKnown,
                    characterCount = stock.characterCount or 1,
                    listingCount = snapshot and snapshot.listingCount or 0,
                    confidence = Confidence(snapshot or {}),
                    bestMethod = "AH",
                    p25 = snapshot and snapshot.p25,
                    p75 = snapshot and snapshot.p75,
                    updatedAt = snapshot and snapshot.updatedAt,
                    source = snapshot.source,
                    marketSamples = confidenceSamples,
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
