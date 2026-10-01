local AHT = WOW4E_AHT

AHT.Poster = { pending = nil }

function AHT.Poster:GetStock(itemID)
    local stacks, total = {}, 0
    if not C_Container or not C_Container.GetContainerNumSlots then return stacks, total end
    for bag = 0, tonumber(NUM_BAG_SLOTS) or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID == itemID and not info.isLocked and (info.stackCount or 0) > 0 then
                table.insert(stacks, { location = AHT:GetItemLocation(bag, slot), quantity = info.stackCount })
                total = total + info.stackCount
            end
        end
    end
    return stacks, total
end

function AHT.Poster:RefreshPrice(result, callback)
    return AHT.AH:Search(result.output, function(_, meta)
        if meta.error then callback(nil, meta.error) return end
        self.priceChecked = self.priceChecked or {}
        self.priceChecked[tostring(result.output.itemID)] = AHT:Now()
        callback(self:RecommendPrice(result))
    end)
end

function AHT.Poster:FindItem(itemID)
    if not C_Container or not C_Container.GetContainerNumSlots then return nil end
    for bag = 0, 5 do
        local slots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID == itemID and (info.stackCount or 0) > 0 then
                return AHT:GetItemLocation(bag, slot), info.stackCount, bag, slot
            end
        end
    end
    return nil
end

function AHT.Poster:RecommendPrice(result)
    local itemID = result and result.output and result.output.itemID
    if not itemID then return nil end
    local snapshot = AHT.Store and AHT.Store:GetMarketSnapshot(itemID) or nil
    local market = snapshot and snapshot.marketValue
    local current = snapshot and snapshot.currentPrice
    local settings = AHT.DB.settings
    local recommended = current or market or result.expectedSalePrice or result.salePrice
    local floor = math.max(tonumber(settings.sellFloorCopper) or 0,
        result.costPerOutput and math.ceil(result.costPerOutput / (1 - (settings.auctionCutPercent or 5) / 100)) or 0)
    local outlier = current and snapshot and snapshot.p25 and current < snapshot.p25 * 0.5
    if recommended and current and settings.sellStrategy == "undercut" and not outlier then
        recommended = math.max(1, current - (settings.undercutCopper or 1))
    end
    if recommended then recommended = math.max(floor, recommended) end
    return {
        currentPrice = current,
        marketValue = market,
        recommendedPrice = recommended,
        p25 = snapshot and snapshot.p25,
        p75 = snapshot and snapshot.p75,
        samples = snapshot and snapshot.marketSamples or 0,
        floor = floor,
        estimateOnly = current == nil,
        outlier = outlier,
    }
end

function AHT.Poster:BuildPlan(result, quantity, duration, unitPrice)
    if not result or not result.output or not result.output.itemID then return nil, "output_missing" end
    local location, available = self:FindItem(result.output.itemID)
    if not location then return nil, "item_not_in_bags" end
    local stacks, totalStock = self:GetStock(result.output.itemID)
    quantity = math.floor(tonumber(quantity) or 1)
    if quantity <= 0 or quantity > totalStock then return nil, "quantity_missing" end
    duration = AHT:NormalizeAuctionDuration(duration or (AHT.DB.settings and AHT.DB.settings.defaultDuration) or 2)
    unitPrice = unitPrice or result.expectedSalePrice or result.salePrice
    if not unitPrice or unitPrice <= 0 then return nil, "price_missing" end
    unitPrice = math.floor(unitPrice)
    if unitPrice < (self:RecommendPrice(result).floor or 0) then return nil, "price_below_floor" end

    local isCommodity = false
    if C_AuctionHouse.GetItemCommodityStatus and Enum and Enum.ItemCommodityStatus then
        local ok, status = pcall(C_AuctionHouse.GetItemCommodityStatus, location)
        isCommodity = ok and status == Enum.ItemCommodityStatus.Commodity
    end
    local requestedQuantity = quantity
    local posts = 1
    if not isCommodity then
        quantity = math.min(quantity, available)
        local left = requestedQuantity
        posts = 0
        for _, stack in ipairs(stacks) do
            if left > 0 then posts = posts + 1; left = left - stack.quantity end
        end
    end
    local deposit = 0
    if isCommodity and C_AuctionHouse.CalculateCommodityDeposit then
        local ok, value = pcall(C_AuctionHouse.CalculateCommodityDeposit, result.output.itemID, duration, quantity)
        if ok then deposit = tonumber(value) or 0 end
    elseif C_AuctionHouse.CalculateItemDeposit then
        local ok, value = pcall(C_AuctionHouse.CalculateItemDeposit, location, duration, quantity)
        if ok then deposit = tonumber(value) or 0 end
    end
    return {
        result = result,
        location = location,
        itemID = result.output.itemID,
        quantity = quantity,
        duration = duration,
        unitPrice = unitPrice,
        deposit = deposit,
        isCommodity = isCommodity,
        requestedQuantity = requestedQuantity,
        remainingQuantity = requestedQuantity - quantity,
        posts = posts,
        totalStock = totalStock,
        netIncome = math.floor(unitPrice * quantity * (1 - (AHT.DB.settings.auctionCutPercent or 5) / 100)),
    }
end

function AHT.Poster:Show(result)
    if AHT.UI then AHT.UI:ShowPostDialog(result) end
end

function AHT.Poster:Post(plan)
    if not plan or not plan.location then return false end
    if self.pending then return false, "purchase_in_progress" end
    local checked = self.priceChecked and self.priceChecked[tostring(plan.itemID)]
    if not checked or AHT:Now() - checked > 60 then return false, "sale_refresh_required" end
    if not AHT.AHOpen then
        AHT:Print(AHT.L.noAH)
        return false
    end
    if GetMoney and plan.deposit > GetMoney() then
        AHT:Print("Posten abgebrochen: nicht genug Gold für das Deposit.")
        return false
    end
    local ok, acceptedOrError
    if plan.isCommodity and C_AuctionHouse.PostCommodity then
        ok, acceptedOrError = pcall(C_AuctionHouse.PostCommodity, plan.location, plan.duration, plan.quantity, plan.unitPrice)
    elseif C_AuctionHouse.PostItem then
        ok, acceptedOrError = pcall(C_AuctionHouse.PostItem, plan.location, plan.duration, plan.quantity, nil, plan.unitPrice * plan.quantity)
    else
        ok, acceptedOrError = false, "post_api_missing"
    end
    if not ok or acceptedOrError == false then
        AHT:Print("Posten fehlgeschlagen: " .. tostring(acceptedOrError or "api_rejected"))
        return false
    end
    self.pending = plan
    AHT:Print(string.format("Posten ausgelöst: %dx für %s, Deposit %s", plan.quantity, AHT:FormatMoney(plan.unitPrice), AHT:FormatMoney(plan.deposit)))
    return true
end

function AHT.Poster:OnEvent(eventName)
    if eventName == "AUCTION_HOUSE_AUCTION_CREATED" and self.pending then
        local plan = self.pending
        table.insert(AHT.DB.postingHistory, { itemID = plan.itemID, name = plan.result.name,
            quantity = plan.quantity, unitPrice = plan.unitPrice, t = AHT:Now(), marketPoolKey = AHT.DB.marketPoolKey })
        while #AHT.DB.postingHistory > 500 do table.remove(AHT.DB.postingHistory, 1) end
        AHT.Store:Save()
        AHT:Print("Auktion erstellt.")
        self.pending = nil
        if plan.onPosted then plan.onPosted(plan) end
    end
end

function AHT.Poster:Cancel(reason)
    if self.pending then AHT:Print("Posten abgebrochen: " .. tostring(reason or "cancelled")) end
    self.pending = nil
end
