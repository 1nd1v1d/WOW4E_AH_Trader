local AHT = WOW4E_AHT

AHT.Buyer = { pending = nil }

local function SortedOffers(results)
    local offers = {}
    for _, result in ipairs(results or {}) do
        if result.unitPrice and result.unitPrice > 0 then table.insert(offers, result) end
    end
    table.sort(offers, function(a, b) return a.unitPrice < b.unitPrice end)
    return offers
end

function AHT.Buyer:BuildPlan(results, quantity, maxUnitPrice)
    local plan = { lines = {}, quantity = quantity, total = 0, missing = quantity }
    for _, offer in ipairs(SortedOffers(results)) do
        if offer.unitPrice <= maxUnitPrice and plan.missing > 0 then
            local take = math.min(plan.missing, offer.quantity)
            if offer.kind == "item" and take < offer.quantity then
                -- Item auctions cannot be split at purchase time; buy the whole stack only.
                take = offer.quantity
            end
            table.insert(plan.lines, { offer = offer, quantity = take, total = take * offer.unitPrice })
            plan.total = plan.total + take * offer.unitPrice
            plan.missing = math.max(0, plan.missing - take)
        end
    end
    return plan
end

function AHT.Buyer:Preview(target, quantity, callback)
    if not AHT.AHOpen then
        if callback then callback(nil, "auction_house_closed") end
        return
    end
    AHT.AH:Search(target, function(results, meta)
        if meta.error then
            if callback then callback(nil, meta.error) end
            return
        end
        local cheapest = results[1] and results[1].unitPrice or 0
        local maxUnitPrice = cheapest
        local plan = self:BuildPlan(results, quantity, maxUnitPrice)
        plan.target = target
        plan.results = results
        if callback then callback(plan, nil) end
    end)
end

function AHT.Buyer:Notify(state, data)
    if self.pending and self.pending.callback then
        local ok, err = pcall(self.pending.callback, state, data)
        if not ok then AHT:Print("Kauf-Callback-Fehler: " .. tostring(err)) end
    end
end

function AHT.Buyer:Confirm(plan, callback)
    if not plan or not plan.target or not plan.quantity then return false end
    if self.pending then
        AHT:Print("Es läuft bereits eine Kaufprüfung.")
        return false
    end
    if not AHT.AHOpen then
        AHT:Print(AHT.L.noAH)
        return false
    end
    self.pending = {
        plan = plan,
        state = "refreshing",
        startedAt = GetTime and GetTime() or 0,
        callback = callback,
    }
    AHT.AH:Search(plan.target, function(results, meta)
        if not self.pending then return end
        if meta.error then
            AHT:Print("Kauf abgebrochen: " .. meta.error)
            self:Notify("error", meta.error)
            self.pending = nil
            return
        end

        local refreshed = self:BuildPlan(results, plan.quantity, plan.lines[1] and plan.lines[1].offer.unitPrice or 0)
        if refreshed.missing > 0 or #refreshed.lines == 0 then
            AHT:Print("Kauf abgebrochen: Preis oder Menge hat sich geändert.")
            self:Notify("error", "price_or_quantity_changed")
            self.pending = nil
            return
        end
        refreshed.target = plan.target
        refreshed.results = results
        self.pending.plan = refreshed
        self:Execute(refreshed)
    end)
    return true
end

function AHT.Buyer:Execute(plan)
    local first = plan.lines[1] and plan.lines[1].offer
    if not first then
        self:Notify("error", "offer_missing")
        self.pending = nil
        return
    end

    if first.kind == "commodity" then
        local quantity = plan.quantity
        self.pending.state = "awaiting_price"
        self.pending.itemID = first.itemID
        self.pending.maxTotal = plan.total
        self.pending.quantity = quantity
        if not C_AuctionHouse.StartCommoditiesPurchase then
            AHT:Print("Commodity-Kauf-API fehlt.")
            self:Notify("error", "commodity_purchase_api_missing")
            self.pending = nil
            return
        end
        local ok, err = pcall(C_AuctionHouse.StartCommoditiesPurchase, first.itemID, quantity)
        if not ok then
            AHT:Print("Commodity-Kauf fehlgeschlagen: " .. tostring(err))
            self:Notify("error", tostring(err or "commodity_purchase_failed"))
            self.pending = nil
        end
    else
        local totalPrice = first.buyoutAmount
        if not first.auctionID or not totalPrice or not C_AuctionHouse.PlaceBid then
            AHT:Print("Item-Kaufdaten unvollständig.")
            self:Notify("error", "item_purchase_data_missing")
            self.pending = nil
            return
        end
        self.pending.state = "placing"
        local ok, err = pcall(C_AuctionHouse.PlaceBid, first.auctionID, totalPrice)
        if not ok then
            AHT:Print("Item-Kauf fehlgeschlagen: " .. tostring(err))
            self:Notify("error", tostring(err or "item_purchase_failed"))
            self.pending = nil
        else
            AHT:Print("Kauf ausgelöst: " .. AHT:FormatMoney(totalPrice))
            self:Notify("submitted", plan)
            self.pending = nil
        end
    end
end

function AHT.Buyer:ConfirmCommodity()
    local pending = self.pending
    if not pending or pending.state ~= "awaiting_user_confirmation" then return false end
    if not C_AuctionHouse or not C_AuctionHouse.ConfirmCommoditiesPurchase then
        self:Notify("error", "commodity_confirm_api_missing")
        self.pending = nil
        return false
    end
    local ok, err = pcall(C_AuctionHouse.ConfirmCommoditiesPurchase, pending.itemID, pending.quantity)
    if not ok then
        AHT:Print("Commodity-Bestätigung fehlgeschlagen: " .. tostring(err))
        self:Notify("error", tostring(err or "commodity_confirm_failed"))
        self.pending = nil
        return false
    end
    AHT:Print("Commodity-Kauf ausgelöst: " .. AHT:FormatMoney(pending.totalPrice))
    self:Notify("submitted", pending.plan)
    self.pending = nil
    return true
end

function AHT.Buyer:OnEvent(eventName, ...)
    if not self.pending then return end
    if eventName == "COMMODITY_PRICE_UPDATED" and self.pending.state == "awaiting_price" then
        -- Blizzard sends (newUnitPrice, newTotalPrice) here. The item ID is
        -- not part of this event; the pending transaction identifies it.
        local unitPrice, totalPrice = ...
        totalPrice = tonumber(totalPrice) or ((tonumber(unitPrice) or 0) * (self.pending.quantity or 0))
        if totalPrice <= 0 or totalPrice > self.pending.maxTotal then
            AHT:Print("Kauf abgebrochen: aktualisierter Commodity-Preis überschreitet den Plan.")
            if C_AuctionHouse.CancelCommoditiesPurchase then
                pcall(C_AuctionHouse.CancelCommoditiesPurchase)
            end
            self:Notify("error", "updated_price_exceeds_plan")
            self.pending = nil
            return
        end
        self.pending.state = "awaiting_user_confirmation"
        self.pending.unitPrice = tonumber(unitPrice) or 0
        self.pending.totalPrice = totalPrice
        self:Notify("price", self.pending)
    elseif eventName == "COMMODITY_PRICE_UNAVAILABLE" and self.pending.state == "awaiting_price" then
        if C_AuctionHouse.CancelCommoditiesPurchase then
            pcall(C_AuctionHouse.CancelCommoditiesPurchase)
        end
        AHT:Print("Kauf abgebrochen: kein aktueller Commodity-Preis verfügbar.")
        self:Notify("error", "commodity_price_unavailable")
        self.pending = nil
    elseif eventName == "COMMODITY_PURCHASE_FAILED" or eventName == "AUCTION_HOUSE_PURCHASE_FAILED" then
        AHT:Print("Kauf vom Client abgelehnt.")
        self:Notify("error", "purchase_failed")
        self.pending = nil
    elseif eventName == "COMMODITY_PURCHASE_SUCCEEDED" or eventName == "AUCTION_HOUSE_PURCHASE_COMPLETED" then
        AHT:Print("Kauf abgeschlossen.")
        self:Notify("completed", self.pending.plan)
        self.pending = nil
    end
end

function AHT.Buyer:Cancel(reason)
    if self.pending then
        if self.pending.state == "awaiting_price" or self.pending.state == "awaiting_user_confirmation" then
            if C_AuctionHouse and C_AuctionHouse.CancelCommoditiesPurchase then
                pcall(C_AuctionHouse.CancelCommoditiesPurchase)
            end
        end
        AHT:Print("Kauf abgebrochen: " .. tostring(reason or "cancelled"))
        self:Notify("error", reason or "cancelled")
    end
    self.pending = nil
end
