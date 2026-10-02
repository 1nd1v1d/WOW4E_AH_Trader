local AHT = WOW4E_AHT

AHT.Production = {
    runtimePlans = {},
    active = nil,
    callback = nil,
}

local MAX_UNIT_PRICE = 1000000000000000

local function IsActive(order)
    return order and order.status ~= "completed" and order.status ~= "cancelled"
end

local function CopyItem(item)
    if type(item) ~= "table" then return item end
    local copy = {}
    for key, value in pairs(item) do copy[key] = value end
    return copy
end

local function Remaining(requirement)
    return math.max(0, (tonumber(requirement.toBuy) or 0) - (tonumber(requirement.bought) or 0))
end

local function PlannedQuantity(plan)
    local quantity = 0
    for _, line in ipairs(plan and plan.lines or {}) do quantity = quantity + (tonumber(line.quantity) or 0) end
    return quantity
end

local function VendorInfo(itemID, name)
    if not AHT.Commerce or not AHT.Commerce.GetVendorInfo then return nil end
    return AHT.Commerce:GetVendorInfo(itemID, name)
end

function AHT.Production:Initialize()
    if not AHT.DB then return end
    AHT.DB.production = AHT.DB.production or { serial = 0, orders = {}, purchases = {} }
    AHT.DB.production.orders = AHT.DB.production.orders or {}
    AHT.DB.production.purchases = AHT.DB.production.purchases or {}
    for _, order in pairs(AHT.DB.production.orders) do
        if order.status == "previewing" or order.status == "buying" or order.status == "checking" or
                order.status == "awaiting_purchase" or order.status == "awaiting_confirmation" or order.status == "submitted" then
            order.status = "paused"
        end
    end
end

function AHT.Production:GetOrder(orderOrID)
    if type(orderOrID) == "table" then return orderOrID end
    return AHT.DB and AHT.DB.production and AHT.DB.production.orders[tostring(orderOrID)] or nil
end

function AHT.Production:GetActiveOrders()
    local orders = {}
    local characterKey = AHT.Inventory and AHT.Inventory:GetCharacterKey() or nil
    for _, order in pairs(AHT.DB and AHT.DB.production and AHT.DB.production.orders or {}) do
        if IsActive(order) and (not order.characterKey or not characterKey or order.characterKey == characterKey) then
            table.insert(orders, order)
        end
    end
    table.sort(orders, function(a, b) return (tonumber(a.createdAt) or 0) > (tonumber(b.createdAt) or 0) end)
    return orders
end

function AHT.Production:GetReserved(itemID, excludeOrderID)
    local reserved = 0
    for _, order in ipairs(self:GetActiveOrders()) do
        if tostring(order.id) ~= tostring(excludeOrderID or "") then
            for _, requirement in ipairs(order.requirements or {}) do
                if tonumber(requirement.itemID) == tonumber(itemID) then
                    reserved = reserved + (tonumber(requirement.required) or 0)
                end
            end
        end
    end
    return reserved
end

function AHT.Production:Suggest(result)
    local suggestion = {
        craftableFromStock = 0,
        suggestedCrafts = 0,
        margin = result and result.margin or nil,
    }
    if not result or not result.output or not result.output.itemID then return suggestion end

    local craftable, perItem = nil, {}
    for _, reagent in ipairs(result.reagents or {}) do
        local key = tostring(reagent.itemID)
        perItem[key] = perItem[key] or { itemID = reagent.itemID, quantity = 0 }
        perItem[key].quantity = perItem[key].quantity + math.max(1, tonumber(reagent.quantity) or 1)
    end
    for _, reagent in pairs(perItem) do
        local perCraft = reagent.quantity
        local counts = AHT.Inventory and AHT.Inventory:GetCount(reagent.itemID) or { total = 0 }
        local available = math.max(0, (counts.total or 0) - self:GetReserved(reagent.itemID))
        local value = math.floor(available / perCraft)
        craftable = craftable and math.min(craftable, value) or value
    end
    suggestion.craftableFromStock = craftable or 0

    local minimumMargin = tonumber(AHT.DB and AHT.DB.settings.minMarginPercent) or 10
    if not result.margin or result.margin < minimumMargin then return suggestion end

    local cap = math.max(1, tonumber(AHT.DB.settings.productionSuggestionCap) or 20)
    local budget = tonumber(AHT.DB.settings.budgetCopper) or 0
    if budget <= 0 then budget = GetMoney and GetMoney() or math.huge end
    for crafts = 1, cap do
        local cost, cash, complete = 0, 0, true
        for _, reagent in pairs(perItem) do
            local needed = reagent.quantity * crafts
            local counts = AHT.Inventory:GetCount(reagent.itemID)
            local available = math.max(0, counts.total - self:GetReserved(reagent.itemID))
            local allocated = math.min(needed, available)
            local vendor = VendorInfo(reagent.itemID, reagent.name)
            if vendor then
                local unit = tonumber(vendor.unitPrice)
                if unit == nil then
                    complete = false
                else
                    cost = cost + needed * unit
                    cash = cash + math.max(0, needed - allocated) * unit
                end
            else
                local record = AHT.Store:GetByItemID(reagent.itemID)
                local unit = AHT.Store:GetPrice(reagent.itemID)
                cost = cost + allocated * (unit or 0)
                if not unit then complete = false end
                if needed > allocated then
                    if not record or not record.priceDepth or not record.distributionAt or AHT:Now() - record.distributionAt > (AHT.DB.settings.maxPriceAgeSeconds or 86400) then
                        complete = false
                    else
                        local plan = AHT.Buyer:BuildPlan(record.priceDepth, needed - allocated, unit * (1 + (AHT.DB.settings.productionPriceSlippagePercent or 25) / 100))
                        cost, cash = cost + plan.total, cash + plan.total
                        if plan.missing > 0 then complete = false end
                    end
                end
            end
        end
        local net = (result.salePrice or 0) * math.max(1, result.output.quantity or 1) * crafts * (1 - (AHT.DB.settings.auctionCutPercent or 5) / 100)
        if not complete or cost <= 0 or (net - cost) / cost * 100 < minimumMargin or cash > budget then break end
        suggestion.suggestedCrafts = crafts
    end
    return suggestion
end

function AHT.Production:CreateOrderForOutputs(result, outputs)
    local perCraft = math.max(1, tonumber(result.output.quantity) or 1)
    local order, reason = self:CreateOrder(result, math.ceil(math.max(1, tonumber(outputs) or 1) / perCraft))
    if order then order.targetOutputs = math.max(1, math.floor(tonumber(outputs) or 1)) end
    return order, reason
end

function AHT.Production:RefreshSuggestion(result, callback)
    local targets = { result.output }
    for _, reagent in ipairs(result.reagents or {}) do table.insert(targets, reagent) end
    local index = 0
    local function Next()
        index = index + 1
        if not targets[index] then
            local fresh = AHT.Calculator:CalculateRecipe(result)
            callback(self:Suggest(fresh), nil)
            return
        end
        if VendorInfo(targets[index].itemID, targets[index].name) then
            Next()
            return
        end
        AHT.AH:Search(targets[index], function(_, meta)
            if meta.error then callback(nil, meta.error) else Next() end
        end)
    end
    Next()
end

-- Re-evaluate the WHOLE order after each live price change, including paid
-- stacks, owned stock at replacement cost and every remaining requirement.
function AHT.Production:ValidateOrder(order, replacement, replacementTotal)
    local plans = self.runtimePlans[tostring(order.id)] or {}
    local economic, spent, remaining, complete = 0, 0, 0, true
    local vendorPriceMissing = false
    for _, requirement in ipairs(order.requirements or {}) do
        local vendor = VendorInfo(requirement.itemID, requirement.name)
        if not vendor and requirement.source == "vendor" then
            vendor = { unitPrice = requirement.vendorUnitPrice }
        end
        if vendor then
            requirement.source = "vendor"
            local unit = tonumber(vendor.unitPrice) or tonumber(requirement.vendorUnitPrice)
            local baseOwned = tonumber(requirement.vendorBaseOwned) or tonumber(requirement.ownedAllocated) or 0
            local vendorPaid = tonumber(requirement.vendorSpent) or 0
            local paid = (tonumber(requirement.spent) or 0) + vendorPaid
            economic = economic + paid + baseOwned * (unit or 0)
            spent = spent + paid
            if unit == nil then
                complete = false
                vendorPriceMissing = true
            else
                local vendorRemaining = Remaining(requirement) * unit
                economic, remaining = economic + vendorRemaining, remaining + vendorRemaining
            end
        else
            local unit = AHT.Store:GetPrice(requirement.itemID)
            local paid = tonumber(requirement.spent) or 0
            economic, spent = economic + paid + (requirement.ownedAllocated or 0) * (unit or 0), spent + paid
            if (requirement.ownedAllocated or 0) > 0 and not unit then complete = false end
            if Remaining(requirement) > 0 then
                local plan = replacement and tonumber(replacement.requirementItemID) == tonumber(requirement.itemID) and replacement or plans[tostring(requirement.itemID)]
                if not plan or plan.missing > 0 then complete = false else
                    local cost = plan == replacement and replacementTotal or plan.total
                    cost = tonumber(cost) or plan.total
                    economic, remaining = economic + cost, remaining + cost
                end
            end
        end
    end
    local snapshot = AHT.Store:GetMarketSnapshot(order.output.itemID)
    local sale = snapshot and snapshot.currentPrice
    local fresh = snapshot and snapshot.updatedAt and AHT:Now() - snapshot.updatedAt <= (AHT.DB.settings.maxPriceAgeSeconds or 86400)
    local gross = sale and sale * math.max(1, order.output.quantity or 1) * order.crafts
    local net = gross and gross - math.floor(gross * (AHT.DB.settings.auctionCutPercent or 5) / 100)
    local profit = net and net - economic
    local margin = profit and economic > 0 and profit / economic * 100 or nil
    local budget = tonumber(AHT.DB.settings.budgetCopper) or 0
    local minimum = tonumber(AHT.DB.settings.minMarginPercent) or 10
    order.preview = { complete = complete and fresh and sale ~= nil and economic > 0,
        cashCost = spent + remaining, spent = spent, remainingCost = remaining,
        economicCost = economic, salePrice = sale, gross = gross, net = net, profit = profit,
        margin = margin, minimumMargin = minimum, meetsMargin = margin ~= nil and margin >= minimum,
        meetsBudget = (budget <= 0 or spent + remaining <= budget) and (not GetMoney or remaining <= GetMoney()) }
    if not order.preview.complete then
        return false, vendorPriceMissing and "vendor_price_unavailable" or "preview_required"
    end
    if not order.preview.meetsMargin or (profit or 0) < (AHT.DB.settings.minimumProfitCopper or 1) then return false, "margin_below_minimum" end
    if not order.preview.meetsBudget then return false, "budget_exceeded" end
    return true
end

function AHT.Production:CreateOrder(result, crafts)
    crafts = math.max(1, math.floor(tonumber(crafts) or 1))
    if not result or not result.output or not result.output.itemID or #(result.reagents or {}) == 0 then
        return nil, "recipe_data_missing"
    end

    local production = AHT.DB.production
    production.serial = (tonumber(production.serial) or 0) + 1
    local id = tostring(production.serial)
    local order = {
        id = id,
        recipeID = result.recipeID,
        name = result.name,
        crafts = crafts,
        output = CopyItem(result.output),
        reagents = {},
        requirements = {},
        status = "planned",
        createdAt = AHT:Now(),
        updatedAt = AHT:Now(),
        build = AHT.Capabilities and AHT.Capabilities.build,
        characterKey = AHT.Inventory and AHT.Inventory:GetCharacterKey() or nil,
    }

    local aggregated, aggregatedList = {}, {}
    for _, reagent in ipairs(result.reagents or {}) do
        table.insert(order.reagents, CopyItem(reagent))
        local key = tostring(reagent.itemID)
        local entry = aggregated[key]
        if not entry then
            entry = {
                itemID = reagent.itemID,
                name = reagent.name,
                perCraft = 0,
            }
            aggregated[key] = entry
            table.insert(aggregatedList, entry)
        end
        entry.perCraft = entry.perCraft + math.max(1, tonumber(reagent.quantity) or 1)
    end

    for _, reagent in ipairs(aggregatedList) do
        local required = reagent.perCraft * crafts
        local counts = AHT.Inventory and AHT.Inventory:GetCount(reagent.itemID) or { bags = 0, bank = 0, total = 0, bankKnown = false }
        local reservedOther = self:GetReserved(reagent.itemID)
        local available = math.max(0, (counts.total or 0) - reservedOther)
        local ownedAllocated = math.min(required, available)
        local vendor = VendorInfo(reagent.itemID, reagent.name)
        local unitPrice
        if vendor then unitPrice = vendor.unitPrice
        else unitPrice = AHT.Store and AHT.Store:GetPrice(reagent.itemID) or nil end
        table.insert(order.requirements, {
            itemID = reagent.itemID,
            name = reagent.name or AHT:GetItemInfo(reagent.itemID) or tostring(reagent.itemID),
            perCraft = reagent.perCraft,
            required = required,
            bags = counts.bags or 0,
            bank = counts.bank or 0,
            bankKnown = counts.bankKnown == true,
            reservedOther = reservedOther,
            ownedAllocated = ownedAllocated,
            toBuy = math.max(0, required - ownedAllocated),
            bought = 0,
            spent = 0,
            source = vendor and "vendor" or "auction_house",
            vendorUnitPrice = vendor and vendor.unitPrice or nil,
            vendorBaseOwned = vendor and ownedAllocated or nil,
            vendorAcquired = 0,
            vendorSpent = 0,
            unitPrice = unitPrice,
        })
    end

    production.orders[id] = order
    AHT.Store:Save()
    return order
end

function AHT.Production:CancelOrder(orderOrID)
    local order = self:GetOrder(orderOrID)
    if not order or not IsActive(order) then return false end
    if self.active and tostring(self.active.orderID) == tostring(order.id) and AHT.Buyer then
        AHT.Buyer:Cancel("production_order_cancelled")
    end
    order.status = "cancelled"
    order.updatedAt = AHT:Now()
    self.runtimePlans[tostring(order.id)] = nil
    if self.active and tostring(self.active.orderID) == tostring(order.id) then self.active = nil end
    AHT.Store:Save()
    return true
end

function AHT.Production:CompleteOrder(orderOrID)
    local order = self:GetOrder(orderOrID)
    if not order or not IsActive(order) then return false end
    if self.active and tostring(self.active.orderID) == tostring(order.id) and AHT.Buyer then
        AHT.Buyer:Cancel("production_order_completed")
    end
    order.status = "completed"
    order.completedAt = AHT:Now()
    order.updatedAt = order.completedAt
    self.runtimePlans[tostring(order.id)] = nil
    if self.active and tostring(self.active.orderID) == tostring(order.id) then self.active = nil end
    AHT.Store:Save()
    return true
end

function AHT.Production:Notify(state, data)
    if not self.callback then return end
    local ok, err = pcall(self.callback, state, data)
    if not ok then AHT:Print("Produktions-Callback-Fehler: " .. tostring(err)) end
end

function AHT.Production:PreviewOrder(orderOrID, callback)
    local order = self:GetOrder(orderOrID)
    if not order or not IsActive(order) then
        if callback then callback(nil, "order_missing") end
        return false
    end
    if not AHT.AHOpen then
        order.status, order.lastError = "paused", "auction_house_closed"
        AHT.Store:Save()
        if callback then callback(nil, "auction_house_closed") end
        return false
    end
    self.previewTokens = self.previewTokens or {}
    local id = tostring(order.id)
    local token = (self.previewTokens[id] or 0) + 1
    self.previewTokens[id] = token
    local function Active() return IsActive(order) and self.previewTokens[id] == token end
    order.status, order.lastError, order.updatedAt = "previewing", nil, AHT:Now()
    local plans, index, complete = {}, 0, true
    self.runtimePlans[id] = plans
    local slippage = (tonumber(AHT.DB.settings.productionPriceSlippagePercent) or 25) / 100
    local function Finish()
        if not Active() then return end
        local allowed, reason = self:ValidateOrder(order)
        if not complete then order.preview.complete = false end
        order.status = order.preview.complete and "ready" or "incomplete"
        order.lastError = not allowed and reason or nil
        order.updatedAt = AHT:Now()
        AHT.Store:Save()
        if callback then callback(order, nil) end
    end
    local function Next()
        if not Active() then return end
        index = index + 1
        local requirement = order.requirements[index]
        if not requirement then Finish() return end
        local remaining = Remaining(requirement)
        local vendor = VendorInfo(requirement.itemID, requirement.name)
        if not vendor and requirement.source == "vendor" then
            vendor = { unitPrice = requirement.vendorUnitPrice }
        end
        if vendor then
            requirement.source = "vendor"
            local unit = tonumber(vendor.unitPrice) or tonumber(requirement.vendorUnitPrice)
            requirement.vendorUnitPrice = unit
            requirement.unitPrice = unit
            requirement.vendorBaseOwned = tonumber(requirement.vendorBaseOwned) or tonumber(requirement.ownedAllocated) or 0
            local counts = AHT.Inventory and AHT.Inventory:GetCount(requirement.itemID) or { total = 0 }
            local reserved = self:GetReserved(requirement.itemID, order.id)
            local available = math.min(tonumber(requirement.required) or 0,
                math.max(0, (tonumber(counts.total) or 0) - reserved))
            local alreadyBought = tonumber(requirement.bought) or 0
            local acquired = math.max(0, available - requirement.vendorBaseOwned - alreadyBought)
            requirement.vendorAcquired = math.max(tonumber(requirement.vendorAcquired) or 0, acquired)
            requirement.vendorSpent = unit and requirement.vendorAcquired * unit or nil
            requirement.vendorOwnedCurrent = available
            requirement.toBuy = math.max(0, (tonumber(requirement.required) or 0) -
                requirement.vendorBaseOwned - requirement.vendorAcquired)
            remaining = Remaining(requirement)
            requirement.previewQuantity = remaining
            requirement.previewCost = unit and remaining * unit or nil
            requirement.maxUnitPrice = nil
            requirement.error = unit == nil and "vendor_price_unavailable" or nil
            if unit == nil then complete = false end
            Next()
            return
        end
        local reference = AHT.Store:GetPrice(requirement.itemID)
        local maximum = reference and math.max(1, math.floor(reference * (1 + slippage))) or MAX_UNIT_PRICE
        local target = { itemID = requirement.itemID, name = requirement.name, kind = "unknown" }
        -- Owned ingredients also need a current replacement-cost reference.
        AHT.AH:Search(target, function(results, meta)
            if not Active() then return end
            if meta.error then requirement.error = meta.error; complete = false; Next(); return end
            requirement.unitPrice = AHT.Store:GetPrice(requirement.itemID)
            if remaining > 0 then
                local plan = AHT.Buyer:BuildPlan(results, remaining, maximum)
                plan.target, plan.results, plan.maxUnitPrice = target, results, maximum
                plan.requirementItemID = requirement.itemID
                plan.plannedQuantity = PlannedQuantity(plan)
                plans[tostring(requirement.itemID)] = plan
                requirement.previewQuantity, requirement.previewCost, requirement.maxUnitPrice = plan.plannedQuantity, plan.total, maximum
                requirement.error = plan.missing > 0 and "quantity_or_price_missing" or nil
                if plan.missing > 0 or plan.plannedQuantity <= 0 then complete = false end
            else requirement.error = nil end
            Next()
        end)
    end
    AHT.AH:Search(order.output, function(_, meta)
        if not Active() then return end
        if meta.error then
            order.status, order.lastError = "paused", meta.error
            AHT.Store:Save()
            if callback then callback(nil, meta.error) end
        else Next() end
    end)
    return true
end

function AHT.Production:FindNextRequirement(order)
    for _, requirement in ipairs(order.requirements or {}) do
        if Remaining(requirement) > 0 then return requirement end
    end
    return nil
end

function AHT.Production:PrepareRequirement(order, requirement, callback)
    local remaining = Remaining(requirement)
    if remaining <= 0 then callback(nil, "nothing_to_buy") return end
    if VendorInfo(requirement.itemID, requirement.name) or requirement.source == "vendor" then
        callback(nil, "vendor_purchase_required")
        return false
    end
    local maxUnitPrice = tonumber(requirement.maxUnitPrice) or MAX_UNIT_PRICE
    local target = { itemID = requirement.itemID, name = requirement.name, kind = "unknown" }
    AHT.AH:Search(target, function(results, meta)
        if meta.error then callback(nil, meta.error) return end
        local plan = AHT.Buyer:BuildPlan(results, remaining, maxUnitPrice)
        plan.target = target
        plan.results = results
        plan.maxUnitPrice = maxUnitPrice
        plan.requirementItemID = requirement.itemID
        plan.plannedQuantity = PlannedQuantity(plan)
        if plan.missing > 0 or plan.plannedQuantity <= 0 then
            callback(nil, "price_or_quantity_changed")
            return
        end
        self.runtimePlans[tostring(order.id)] = self.runtimePlans[tostring(order.id)] or {}
        self.runtimePlans[tostring(order.id)][tostring(requirement.itemID)] = plan
        local valid, reason = self:ValidateOrder(order, plan)
        if not valid then callback(nil, reason) return end
        plan.validate = function(refreshed, total)
            local allowed, errorMessage = self:ValidateOrder(order, refreshed, total)
            if allowed then self.runtimePlans[tostring(order.id)][tostring(requirement.itemID)] = refreshed end
            return allowed, errorMessage
        end
        callback(plan, nil)
    end)
end

function AHT.Production:Start(orderOrID, callback)
    local order = self:GetOrder(orderOrID)
    if not order or not IsActive(order) then return false, "order_missing" end
    if not order.preview or not order.preview.complete then return false, "preview_required" end
    if not order.preview.meetsMargin then return false, "margin_below_minimum" end
    if not order.preview.meetsBudget then return false, "budget_exceeded" end
    if self.active and tostring(self.active.orderID) ~= tostring(order.id) then
        if AHT.Buyer and AHT.Buyer.pending then return false, "another_purchase_in_progress" end
        local previous = self:GetOrder(self.active.orderID)
        if previous and IsActive(previous) then previous.status = "paused" end
    end
    self.callback = callback
    self.active = { orderID = order.id, currentItemID = nil, plan = nil }
    return self:Continue(order)
end

function AHT.Production:Continue(orderOrID, callback, allowItemPurchase)
    local order = self:GetOrder(orderOrID)
    if not order or not IsActive(order) then return false, "order_missing" end
    if AHT.Buyer.pending or AHT.Scanner.running or AHT.Scanner.marketDiscovery or AHT.Scanner.replication then return false, "purchase_in_progress" end
    if not AHT.AHOpen then return false, "auction_house_closed" end
    if callback then self.callback = callback end
    -- Refresh output AND every unfinished input before the next purchase.
    return self:PreviewOrder(order, function(_, reason)
        local allowed, errorMessage = self:ValidateOrder(order)
        if reason or not allowed then
            order.status, order.lastError = "paused", reason or errorMessage
            self:Notify("error", order.lastError); AHT.Store:Save(); return
        end
        self:ContinuePrepared(order, callback, allowItemPurchase)
    end)
end

function AHT.Production:ContinuePrepared(orderOrID, callback, allowItemPurchase)
    local order = self:GetOrder(orderOrID)
    if not order or not IsActive(order) then return false, "order_missing" end
    if callback then self.callback = callback end
    if AHT.Buyer and AHT.Buyer.pending then return false, "purchase_in_progress" end
    if not AHT.AHOpen then return false, "auction_house_closed" end

    if self.active and tostring(self.active.orderID) ~= tostring(order.id) then
        local previous = self:GetOrder(self.active.orderID)
        if previous and IsActive(previous) then previous.status = "paused" end
        self.active = nil
    end

    self.active = self.active or { orderID = order.id }
    self.active.orderID = order.id
    local requirement = self:FindNextRequirement(order)
    if not requirement then
        order.status = "ready_to_craft"
        order.updatedAt = AHT:Now()
        AHT.Store:Save()
        self.active = nil
        self:Notify("ready_to_craft", order)
        return true
    end

    if VendorInfo(requirement.itemID, requirement.name) or requirement.source == "vendor" then
        order.status = "vendor_required"
        order.lastError = "vendor_purchase_required"
        order.updatedAt = AHT:Now()
        AHT.Store:Save()
        self:Notify("vendor_required", { order = order, requirement = requirement,
            quantity = Remaining(requirement), unitPrice = requirement.vendorUnitPrice })
        return true
    end

    order.status = "checking"
    order.updatedAt = AHT:Now()
    self.active.currentItemID = requirement.itemID
    self:Notify("checking", { order = order, requirement = requirement })
    self:PrepareRequirement(order, requirement, function(plan, errorMessage)
        if not IsActive(order) or not self.active or tostring(self.active.orderID) ~= tostring(order.id) then return end
        if errorMessage then
            order.status = "paused"
            order.lastError = errorMessage
            order.updatedAt = AHT:Now()
            AHT.Store:Save()
            self:Notify("error", errorMessage)
            return
        end
        self.active.plan = plan
        local firstOffer = plan.lines[1] and plan.lines[1].offer
        if allowItemPurchase == false and firstOffer and firstOffer.kind ~= "commodity" then
            order.status = "next_ready"
            order.updatedAt = AHT:Now()
            AHT.Store:Save()
            self:Notify("next", { order = order, requirement = requirement })
            return
        end
        order.status = "buying"
        local started = AHT.Buyer:Confirm(plan, function(state, data)
            self:OnBuyerState(order, requirement, state, data)
        end)
        if not started then
            order.status = "paused"
            self:Notify("error", "purchase_start_failed")
        end
    end)
    return true
end

function AHT.Production:OnBuyerState(order, requirement, state, data)
    if not IsActive(order) then return end
    if state == "ready" then
        order.status = "awaiting_purchase"
        order.updatedAt = AHT:Now()
        AHT.Store:Save()
        self:Notify("ready", { order = order, requirement = requirement, purchase = data })
    elseif state == "price" then
        order.status = "awaiting_confirmation"
        order.updatedAt = AHT:Now()
        AHT.Store:Save()
        self:Notify("price", { order = order, requirement = requirement, purchase = data })
    elseif state == "submitted" then
        order.status = "submitted"
        order.updatedAt = AHT:Now()
        self:Notify("submitted", { order = order, requirement = requirement, purchase = data })
    elseif state == "completed" then
        local quantity = tonumber(data and data.purchasedQuantity) or tonumber(self.active and self.active.plan and self.active.plan.plannedQuantity) or 0
        local total = tonumber(data and data.actualTotal) or tonumber(self.active and self.active.plan and self.active.plan.total) or 0
        requirement.bought = (tonumber(requirement.bought) or 0) + quantity
        requirement.spent = (tonumber(requirement.spent) or 0) + total
        requirement.lastPurchaseAt = AHT:Now()
        self:ValidateOrder(order)
        local purchases = AHT.DB.production.purchases
        table.insert(purchases, {
            orderID = order.id,
            recipeID = order.recipeID,
            itemID = requirement.itemID,
            name = requirement.name,
            quantity = quantity,
            total = total,
            t = AHT:Now(),
        })
        while #purchases > 500 do table.remove(purchases, 1) end
        order.updatedAt = AHT:Now()
        self.active.plan = nil

        if self:FindNextRequirement(order) then
            order.status = "next_ready"
            AHT.Store:Save()
            self:Notify("progress", { order = order, requirement = requirement, quantity = quantity, total = total })
            -- Preparing the next commodity does not spend gold. Forever still
            -- requires the player to confirm the live commodity price. Item
            -- auctions wait for another explicit click before PlaceBid.
            self:Continue(order, nil, false)
        else
            order.status = "ready_to_craft"
            AHT.Store:Save()
            self.active = nil
            self:Notify("ready_to_craft", order)
        end
    elseif state == "error" then
        order.status = "paused"
        order.lastError = tostring(data)
        order.updatedAt = AHT:Now()
        AHT.Store:Save()
        self:Notify("error", data)
    end
end

function AHT.Production:ConfirmCurrentCommodity()
    if not self.active or not AHT.Buyer then return false end
    return AHT.Buyer:ConfirmCommodity()
end

function AHT.Production:StartCurrentPurchase()
    if not self.active or not AHT.Buyer then return false end
    return AHT.Buyer:StartPendingPurchase()
end

function AHT.Production:ResultFromOrder(orderOrID)
    local order = self:GetOrder(orderOrID)
    if not order then return nil end
    if AHT.Calculator then
        for _, result in ipairs(AHT.Calculator.results or {}) do
            if tonumber(result.recipeID) == tonumber(order.recipeID) then return result end
        end
    end
    return {
        recipeID = order.recipeID,
        name = order.name,
        output = order.output,
        reagents = order.reagents,
        salePrice = order.preview and order.preview.salePrice,
        margin = order.preview and order.preview.margin,
    }
end

function AHT.Production:OnEvent()
    -- Inventory events are handled by Inventory.lua. Orders deliberately stay
    -- reserved until the player marks them completed or cancels them.
end
