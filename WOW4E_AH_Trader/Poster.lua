local AHT = WOW4E_AHT

AHT.Poster = { pending = nil }

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
    local recommended = market or current or result.expectedSalePrice or result.salePrice
    if recommended and recommended > 1 and current and current < recommended then
        -- Undercut only when the current market is already below the robust
        -- value; otherwise keep the market value as the economic target.
        recommended = math.max(current, math.floor(recommended - 1))
    end
    return {
        currentPrice = current,
        marketValue = market,
        recommendedPrice = recommended,
        p25 = snapshot and snapshot.p25,
        p75 = snapshot and snapshot.p75,
        samples = snapshot and snapshot.marketSamples or 0,
    }
end

function AHT.Poster:BuildPlan(result, quantity, duration, unitPrice)
    if not result or not result.output or not result.output.itemID then return nil, "output_missing" end
    local location, available = self:FindItem(result.output.itemID)
    if not location then return nil, "item_not_in_bags" end
    quantity = math.min(quantity or 1, available or 1)
    if quantity <= 0 then return nil, "quantity_missing" end
    duration = AHT:NormalizeAuctionDuration(duration or (AHT.DB.settings and AHT.DB.settings.defaultDuration) or 2)
    unitPrice = unitPrice or result.expectedSalePrice or result.salePrice
    if not unitPrice or unitPrice <= 0 then return nil, "price_missing" end

    local isCommodity = false
    if C_AuctionHouse.GetItemCommodityStatus and Enum and Enum.ItemCommodityStatus then
        local ok, status = pcall(C_AuctionHouse.GetItemCommodityStatus, location)
        isCommodity = ok and status == Enum.ItemCommodityStatus.Commodity
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
    }
end

function AHT.Poster:Show(result)
    if AHT.UI then AHT.UI:ShowPostDialog(result) end
end

function AHT.Poster:Post(plan)
    if not plan or not plan.location then return false end
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
        ok, acceptedOrError = pcall(C_AuctionHouse.PostItem, plan.location, plan.duration, plan.quantity, nil, plan.unitPrice)
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
        AHT:Print("Auktion erstellt.")
        self.pending = nil
    end
end

function AHT.Poster:Cancel(reason)
    if self.pending then AHT:Print("Posten abgebrochen: " .. tostring(reason or "cancelled")) end
    self.pending = nil
end
