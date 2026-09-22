local AHT = WOW4E_AHT

AHT.Buyer = { pending = nil, timeout = 30 }

local function SortedOffers(results)
    local offers = {}
    for _, result in ipairs(results or {}) do
        if result.unitPrice and result.unitPrice > 0 then table.insert(offers, result) end
    end
    table.sort(offers, function(a, b) return a.unitPrice < b.unitPrice end)
    return offers
end

function AHT.Buyer:BuildPlan(results, quantity, maxUnitPrice)
    local plan = { lines = {}, quantity = quantity, total = 0, missing = quantity, maxUnitPrice = maxUnitPrice, plannedQuantity = 0 }
    for _, offer in ipairs(SortedOffers(results)) do
        if offer.unitPrice <= maxUnitPrice and plan.missing > 0 then
            local take = math.min(plan.missing, offer.quantity)
            if offer.kind == "item" and take < offer.quantity then
                -- Item auctions cannot be split at purchase time; buy the whole stack only.
                take = offer.quantity
            end
            table.insert(plan.lines, { offer = offer, quantity = take, total = take * offer.unitPrice })
            plan.total = plan.total + take * offer.unitPrice
            plan.plannedQuantity = plan.plannedQuantity + take
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
    local operation = self.pending
    if operation and operation.callback then
        local ok, err = pcall(operation.callback, state, data)
        if not ok then AHT:Print("Kauf-Callback-Fehler: " .. tostring(err)) end
    end
end

function AHT.Buyer:Finish(state, data)
    local operation = self.pending
    self.pending = nil
    if operation and operation.callback then
        local ok, err = pcall(operation.callback, state, data)
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
    local queued = AHT.AH:Search(plan.target, function(results, meta)
        if not self.pending then return end
        meta = meta or {}
        if meta.error then
            AHT:Print("Kauf abgebrochen: " .. tostring(meta.error))
            self:Finish("error", tostring(meta.error))
            return
        end

        local maxUnitPrice = tonumber(plan.maxUnitPrice) or (plan.lines[1] and plan.lines[1].offer.unitPrice) or 0
        local refreshed = self:BuildPlan(results, plan.quantity, maxUnitPrice)
        if refreshed.missing > 0 or #refreshed.lines == 0 then
            AHT:Print("Kauf abgebrochen: Preis oder Menge hat sich geändert.")
            self:Finish("error", "price_or_quantity_changed")
            return
        end
        refreshed.target = plan.target
        refreshed.results = results
        refreshed.maxUnitPrice = maxUnitPrice
        refreshed.requirementItemID = plan.requirementItemID
        self.pending.plan = refreshed
        -- The live search finishes asynchronously. Protected auction-house
        -- purchase APIs must be called by a later direct button click.
        self.pending.state = "ready_to_buy"
        self.pending.startedAt = GetTime and GetTime() or self.pending.startedAt
        self:Notify("ready", refreshed)
    end)
    if not queued then
        self:Finish("error", "auction_house_search_start_failed")
        return false
    end
    return true
end

function AHT.Buyer:StartPendingPurchase()
    local pending = self.pending
    if not pending or pending.state ~= "ready_to_buy" or not pending.plan then
        return false
    end
    -- Call this only from a visible user action. Execute contains the
    -- protected Blizzard API calls.
    self:Execute(pending.plan)
    return self.pending ~= nil and self.pending.state ~= "ready_to_buy"
end

function AHT.Buyer:Execute(plan)
    local first = plan.lines[1] and plan.lines[1].offer
    if not first then
        self:Finish("error", "offer_missing")
        return
    end
    if GetMoney and tonumber(plan.total) and GetMoney() < plan.total then
        AHT:Print("Kauf abgebrochen: nicht genug Gold.")
        self:Finish("error", "not_enough_money")
        return
    end

    if first.kind == "commodity" then
        local quantity = plan.quantity
        self.pending.state = "awaiting_price"
        self.pending.itemID = first.itemID
        self.pending.maxTotal = plan.total
        self.pending.quantity = quantity
        if not C_AuctionHouse or not C_AuctionHouse.StartCommoditiesPurchase then
            AHT:Print("Commodity-Kauf-API fehlt.")
            self:Finish("error", "commodity_purchase_api_missing")
            return false
        end
        local ok, err = pcall(C_AuctionHouse.StartCommoditiesPurchase, first.itemID, quantity)
        if not ok then
            AHT:Print("Commodity-Kauf fehlgeschlagen: " .. tostring(err))
            self:Finish("error", tostring(err or "commodity_purchase_failed"))
            return false
        end
        return true
    else
        local totalPrice = first.buyoutAmount
        if not first.auctionID or not totalPrice or not C_AuctionHouse or not C_AuctionHouse.PlaceBid then
            AHT:Print("Item-Kaufdaten unvollständig.")
            self:Finish("error", "item_purchase_data_missing")
            return
        end
        self.pending.state = "placing"
        self.pending.purchaseQuantity = tonumber(first.quantity) or 0
        self.pending.totalPrice = totalPrice
        self.pending.auctionID = first.auctionID
        local ok, err = pcall(C_AuctionHouse.PlaceBid, first.auctionID, totalPrice)
        if not ok then
            AHT:Print("Item-Kauf fehlgeschlagen: " .. tostring(err))
            self:Finish("error", tostring(err or "item_purchase_failed"))
            return false
        else
            AHT:Print("Kauf ausgelöst: " .. AHT:FormatMoney(totalPrice))
            self.pending.state = "awaiting_completion"
            self:Notify("submitted", plan)
            return true
        end
    end
end

function AHT.Buyer:ConfirmCommodity()
    local pending = self.pending
    if not pending or pending.state ~= "awaiting_user_confirmation" then return false end
    if not C_AuctionHouse or not C_AuctionHouse.ConfirmCommoditiesPurchase then
        self:Finish("error", "commodity_confirm_api_missing")
        return false
    end
    local ok, err = pcall(C_AuctionHouse.ConfirmCommoditiesPurchase, pending.itemID, pending.quantity)
    if not ok then
        AHT:Print("Commodity-Bestätigung fehlgeschlagen: " .. tostring(err))
        self:Finish("error", tostring(err or "commodity_confirm_failed"))
        return false
    end
    AHT:Print("Commodity-Kauf ausgelöst: " .. AHT:FormatMoney(pending.totalPrice))
    pending.state = "awaiting_completion"
    pending.purchaseQuantity = pending.quantity
    pending.startedAt = GetTime and GetTime() or pending.startedAt
    self:Notify("submitted", pending.plan)
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
            self:Finish("error", "updated_price_exceeds_plan")
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
        self:Finish("error", "commodity_price_unavailable")
    elseif eventName == "COMMODITY_PURCHASE_FAILED" or eventName == "AUCTION_HOUSE_PURCHASE_FAILED" then
        AHT:Print("Kauf vom Client abgelehnt.")
        self:Finish("error", "purchase_failed")
    elseif eventName == "COMMODITY_PURCHASE_SUCCEEDED" or eventName == "AUCTION_HOUSE_PURCHASE_COMPLETED" then
        AHT:Print("Kauf abgeschlossen.")
        local pending = self.pending
        local completed = pending.plan
        completed.purchasedQuantity = tonumber(pending.purchaseQuantity) or tonumber(pending.quantity) or tonumber(completed.plannedQuantity) or 0
        completed.actualTotal = tonumber(pending.totalPrice) or tonumber(completed.total) or 0
        self:Finish("completed", completed)
    end
end

function AHT.Buyer:OnUpdate()
    if not self.pending or not self.pending.startedAt then return end
    local now = GetTime and GetTime() or 0
    if now - self.pending.startedAt < self.timeout then return end
    if self.pending.state == "awaiting_price" or self.pending.state == "awaiting_user_confirmation" then
        if C_AuctionHouse and C_AuctionHouse.CancelCommoditiesPurchase then
            pcall(C_AuctionHouse.CancelCommoditiesPurchase)
        end
    end
    AHT:Print("Kauf abgebrochen: Zeitüberschreitung.")
    self:Finish("error", "purchase_timeout")
end

function AHT.Buyer:Cancel(reason)
    if self.pending then
        if self.pending.state == "awaiting_price" or self.pending.state == "awaiting_user_confirmation" then
            if C_AuctionHouse and C_AuctionHouse.CancelCommoditiesPurchase then
                pcall(C_AuctionHouse.CancelCommoditiesPurchase)
            end
        end
        AHT:Print("Kauf abgebrochen: " .. tostring(reason or "cancelled"))
        self:Finish("error", reason or "cancelled")
        return
    end
    self.pending = nil
end
