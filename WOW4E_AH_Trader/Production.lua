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

function AHT.Production:Initialize()
    if not AHT.DB then return end
    AHT.DB.production = AHT.DB.production or { serial = 0, orders = {}, purchases = {} }
    AHT.DB.production.orders = AHT.DB.production.orders or {}
    AHT.DB.production.purchases = AHT.DB.production.purchases or {}
    for _, order in pairs(AHT.DB.production.orders) do
        if order.status == "buying" or order.status == "checking" or
                order.status == "awaiting_confirmation" or order.status == "submitted" then
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

    local record = AHT.Store and AHT.Store:GetByItemID(result.output.itemID)
    local currentSupply = record and tonumber(record.totalQuantity) or 0
    local outputQuantity = math.max(1, tonumber(result.output.quantity) or 1)
    local share = tonumber(AHT.DB.settings.productionSuggestionShare) or 0.10
    local cap = math.max(1, tonumber(AHT.DB.settings.productionSuggestionCap) or 20)
    local suggestedOutputs = currentSupply > 0 and math.max(outputQuantity, math.ceil(currentSupply * share)) or outputQuantity
    suggestion.suggestedCrafts = math.max(1, math.min(cap, math.ceil(suggestedOutputs / outputQuantity)))
    return suggestion
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
            unitPrice = AHT.Store and AHT.Store:GetPrice(reagent.itemID) or nil,
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
        order.status = "paused"
        order.lastError = "auction_house_closed"
        order.updatedAt = AHT:Now()
        AHT.Store:Save()
        if callback then callback(nil, "auction_house_closed") end
        return false
    end

    order.status = "previewing"
    order.updatedAt = AHT:Now()
    local plans = {}
    self.runtimePlans[tostring(order.id)] = plans
    local index = 0
    local complete = true
    local cashCost = 0
    local economicCost = 0
    local slippage = (tonumber(AHT.DB.settings.productionPriceSlippagePercent) or 25) / 100

    local function Finish()
        if not IsActive(order) then return end
        local outputQuantity = math.max(1, tonumber(order.output and order.output.quantity) or 1)
        local salePrice = AHT.Store and AHT.Store:GetPrice(order.output.itemID) or nil
        local gross = salePrice and salePrice * outputQuantity * order.crafts or nil
        local cutPercent = tonumber(AHT.DB.settings.auctionCutPercent) or 5
        local net = gross and gross - math.floor(gross * cutPercent / 100) or nil
        local profit = net and economicCost > 0 and net - economicCost or nil
        local margin = profit and economicCost > 0 and profit / economicCost * 100 or nil
        local minimumMargin = tonumber(AHT.DB.settings.minMarginPercent) or 10
        order.preview = {
            complete = complete and salePrice ~= nil and economicCost > 0,
            cashCost = cashCost,
            economicCost = economicCost,
            salePrice = salePrice,
            gross = gross,
            net = net,
            profit = profit,
            margin = margin,
            minimumMargin = minimumMargin,
            meetsMargin = margin ~= nil and margin >= minimumMargin,
        }
        order.status = order.preview.complete and "ready" or "incomplete"
        order.updatedAt = AHT:Now()
        AHT.Store:Save()
        if callback then callback(order, nil) end
    end

    local function Next()
        if not IsActive(order) then return end
        index = index + 1
        local requirement = order.requirements[index]
        if not requirement then Finish() return end

        requirement.unitPrice = AHT.Store and AHT.Store:GetPrice(requirement.itemID) or requirement.unitPrice
        local remaining = Remaining(requirement)
        local ownedValue = (tonumber(requirement.ownedAllocated) or 0) * (tonumber(requirement.unitPrice) or 0)
        economicCost = economicCost + ownedValue + (tonumber(requirement.spent) or 0)
        cashCost = cashCost + (tonumber(requirement.spent) or 0)
        if (requirement.ownedAllocated or 0) > 0 and not requirement.unitPrice then complete = false end
        if remaining <= 0 then Next() return end

        local marketPrice = tonumber(requirement.unitPrice)
        local maxUnitPrice = marketPrice and math.max(1, math.floor(marketPrice * (1 + slippage))) or MAX_UNIT_PRICE
        local target = { itemID = requirement.itemID, name = requirement.name, kind = "unknown" }
        AHT.AH:Search(target, function(results, meta)
            if not IsActive(order) then return end
            if meta.error then
                requirement.error = meta.error
                complete = false
                Next()
                return
            end
            local plan = AHT.Buyer:BuildPlan(results, remaining, maxUnitPrice)
            plan.target = target
            plan.results = results
            plan.maxUnitPrice = maxUnitPrice
            plan.requirementItemID = requirement.itemID
            plan.plannedQuantity = PlannedQuantity(plan)
            plans[tostring(requirement.itemID)] = plan
            requirement.previewQuantity = plan.plannedQuantity
            requirement.previewCost = plan.total
            requirement.maxUnitPrice = plan.maxUnitPrice
            requirement.error = plan.missing > 0 and "quantity_or_price_missing" or nil
            if plan.missing > 0 or plan.plannedQuantity <= 0 then complete = false end
            cashCost = cashCost + plan.total
            economicCost = economicCost + plan.total
            Next()
        end)
    end

    Next()
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
        callback(plan, nil)
    end)
end

function AHT.Production:Start(orderOrID, callback)
    local order = self:GetOrder(orderOrID)
    if not order or not IsActive(order) then return false, "order_missing" end
    if not order.preview or not order.preview.complete then return false, "preview_required" end
    if not order.preview.meetsMargin then return false, "margin_below_minimum" end
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
    if state == "price" then
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
