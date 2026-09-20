local AHT = WOW4E_AHT

AHT.Calculator = { results = {} }

local function PriceFor(itemID)
    if not itemID or not AHT.Store then return nil end
    return AHT.Store:GetPrice(itemID)
end

local function MarketPriceFor(itemID)
    if not itemID or not AHT.Store then return nil, nil end
    local snapshot = AHT.Store:GetMarketSnapshot(itemID)
    return snapshot and snapshot.marketValue, snapshot
end

function AHT.Calculator:CalculateRecipe(recipe)
    local salePrice = PriceFor(recipe.output.itemID)
    local marketSalePrice, marketSnapshot = MarketPriceFor(recipe.output.itemID)
    local result = {
        recipeID = recipe.recipeID,
        name = recipe.name,
        output = recipe.output,
        reagents = recipe.reagents,
        missing = {},
        costDetails = {},
        ingredientCost = 0,
        salePrice = salePrice,
        marketSalePrice = marketSalePrice,
        marketSnapshot = marketSnapshot,
        listingCount = 0,
    }
    result.currentSalePrice = result.salePrice
    -- The latest AH scan is the primary sale reference because it reflects
    -- the current market. The robust value is a comparison/orientation and
    -- remains available separately for the UI and opportunity analysis.
    result.expectedSalePrice = result.currentSalePrice or result.marketSalePrice
    local complete = true

    for _, reagent in ipairs(recipe.reagents or {}) do
        local price = PriceFor(reagent.itemID)
        local quantity = reagent.quantity or 1
        if not price then
            complete = false
            table.insert(result.missing, reagent.name or tostring(reagent.itemID))
        else
            local total = price * quantity
            result.ingredientCost = result.ingredientCost + total
            table.insert(result.costDetails, { itemID = reagent.itemID, name = reagent.name, quantity = quantity, unitPrice = price, total = total })
        end
    end

    local outputQuantity = recipe.output.quantity or 1
    result.costPerOutput = result.ingredientCost / outputQuantity
    result.complete = complete and result.expectedSalePrice ~= nil and result.ingredientCost > 0
    if result.salePrice then
        local record = AHT.Store:GetByItemID(recipe.output.itemID)
        result.listingCount = record and record.listingCount or 0
    end

    if result.complete then
        local gross = result.expectedSalePrice * outputQuantity
        local cutPercent = tonumber(AHT.DB and AHT.DB.settings.auctionCutPercent) or 5
        local cut = math.floor(gross * cutPercent / 100)
        local deposit = 0
        if C_AuctionHouse and C_AuctionHouse.CalculateCommodityDeposit then
            -- The exact deposit needs an ItemLocation for non-commodities and is
            -- therefore shown as zero until the post preview has a location.
            deposit = 0
        end
        result.gross = gross
        result.auctionCut = cut
        result.deposit = deposit
        result.profit = gross - cut - deposit - result.ingredientCost
        result.margin = result.profit / result.ingredientCost * 100
        result.isDeal = AHT.Store:IsDeal(AHT.Store:MarketKey(recipe.output.itemID), result.currentSalePrice)
    else
        result.profit = nil
        result.margin = nil
        result.isDeal = false
    end
    local suggestion = AHT.Production and AHT.Production:Suggest(result) or nil
    result.craftableFromStock = suggestion and suggestion.craftableFromStock or 0
    result.suggestedCrafts = suggestion and suggestion.suggestedCrafts or 0
    return result
end

function AHT.Calculator:Refresh()
    self.results = {}
    for _, recipe in ipairs(AHT.Recipes:GetList()) do
        table.insert(self.results, self:CalculateRecipe(recipe))
    end
    table.sort(self.results, function(a, b)
        return (a.profit or -math.huge) > (b.profit or -math.huge)
    end)
    AHT.results = self.results
    return self.results
end

function AHT.Calculator:CalculateTransmutes()
    local results = {}
    for _, recipe in ipairs(AHT.Recipes:GetList()) do
        if recipe.isTransmute then table.insert(results, self:CalculateRecipe(recipe)) end
    end
    table.sort(results, function(a, b) return (a.profit or -math.huge) > (b.profit or -math.huge) end)
    return results
end

function AHT:Refresh()
    if self.Calculator then self.Calculator:Refresh() end
    if self.UI then self.UI:Refresh(true) end
end
