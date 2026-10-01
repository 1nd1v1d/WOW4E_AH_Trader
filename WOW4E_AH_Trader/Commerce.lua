local AHT = WOW4E_AHT

-- Optional public API only. Foreign caches never become AHT scan observations.
AHT.Commerce = {}

function AHT.Commerce:ExternalPrice(itemID)
    if not AHT.DB or not AHT.DB.settings.useAuctionator then return nil end
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if not api or not api.GetAuctionPriceByItemID or not api.GetAuctionAgeByItemID then return nil end
    local ok, price = pcall(api.GetAuctionPriceByItemID, AHT.ADDON_NAME, tonumber(itemID))
    local ageOK, days = pcall(api.GetAuctionAgeByItemID, AHT.ADDON_NAME, tonumber(itemID))
    if not ok or not ageOK or not tonumber(price) or price <= 0 or not tonumber(days) then return nil end
    local age = days * 86400
    if age > (AHT.DB.settings.maxPriceAgeSeconds or 86400) then return nil end
    return { itemID = itemID, currentPrice = price, marketValue = price, updatedAt = AHT:Now() - age,
        source = "auctionator", marketSamples = 0, scanSamples = 0, priceSampleCount = 0 }
end

function AHT.Commerce:AggregateShopping()
    local aggregated = {}
    for _, order in ipairs(AHT.Production:GetActiveOrders()) do
        for _, requirement in ipairs(order.requirements or {}) do
            local missing = math.max(0, (requirement.toBuy or 0) - (requirement.bought or 0))
            if missing > 0 then
                local key = tostring(requirement.itemID)
                local line = aggregated[key] or { itemID = requirement.itemID, name = requirement.name,
                    quantity = 0, reserved = 0, maxUnitPrice = requirement.maxUnitPrice, orders = {} }
                line.quantity = line.quantity + missing
                line.reserved = line.reserved + (requirement.required or 0)
                if requirement.maxUnitPrice then line.maxUnitPrice = math.min(line.maxUnitPrice or math.huge, requirement.maxUnitPrice) end
                table.insert(line.orders, order.id)
                aggregated[key] = line
            end
        end
    end
    local rows = {}
    for _, line in pairs(aggregated) do table.insert(rows, line) end
    table.sort(rows, function(a, b) return tostring(a.name) < tostring(b.name) end)
    return rows
end

function AHT.Commerce:SaveList(name, lines)
    name = tostring(name or ""):match("^%s*(.-)%s*$")
    if name == "" then return false, "list_name_missing" end
    local copy = {}
    for _, line in ipairs(lines or self:AggregateShopping()) do
        table.insert(copy, { itemID = line.itemID, name = line.name, quantity = line.quantity,
            maxUnitPrice = line.maxUnitPrice })
    end
    AHT.DB.shoppingLists[name] = { name = name, lines = copy, updatedAt = AHT:Now() }
    return AHT.Store:Save()
end

function AHT.Commerce:ExportList(list)
    if AHT.Buyer.pending or AHT.AH.active or AHT.Scanner.running or AHT.Scanner.marketDiscovery then return false, "purchase_in_progress" end
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if not api or not api.CreateShoppingList or not api.ConvertToSearchString then return false, "auctionator_missing" end
    local strings = {}
    for _, line in ipairs(list.lines or {}) do
        local ok, value = pcall(api.ConvertToSearchString, AHT.ADDON_NAME, {
            searchString = line.name or AHT:GetItemInfo(line.itemID) or tostring(line.itemID),
            quantity = line.quantity, maxPrice = line.maxUnitPrice, isExact = true })
        if not ok then return false, value end
        table.insert(strings, value)
    end
    local ok, result = pcall(api.CreateShoppingList, AHT.ADDON_NAME, "AHT: " .. list.name, strings)
    return ok and result ~= false, ok and nil or result
end

function AHT.Commerce:RememberSearch(query)
    query = tostring(query or "")
    if query == "" then return end
    local recent = AHT.DB.recentSearches
    for i = #recent, 1, -1 do if recent[i] == query then table.remove(recent, i) end end
    table.insert(recent, 1, query)
    while #recent > 12 do table.remove(recent) end
    AHT.Store:Save()
end

function AHT.Commerce:PriceHistory(itemID, itemKey, days)
    local record, key = AHT.Store:Get(itemID, itemKey)
    if not record then record, key = AHT.Store:GetByItemID(itemID) end
    local points = {}
    local cutoff = AHT:Now() - math.max(1, days or 30) * 86400
    for _, entry in ipairs(key and AHT.DB.dailyHistory[key] or {}) do
        if entry.t and entry.t >= cutoff and entry.p and entry.p > 0 then table.insert(points, { t = entry.t, p = entry.p, scans = entry.n }) end
    end
    return points
end

local errors = {
    budget_exceeded = "Budget oder verfügbares Gold reicht nicht mehr aus.",
    margin_below_minimum = "Die aktuelle Gesamtmarge liegt unter deinem Minimum.",
    preview_required = "Preise oder Materialmengen fehlen. Plan erneut prüfen.",
    auction_house_closed = "Öffne das Auktionshaus erneut.",
    purchase_in_progress = "Ein Einkauf läuft bereits. Zuerst abschließen oder abbrechen.",
    another_purchase_in_progress = "Ein anderer Einkauf läuft bereits.",
    price_or_quantity_changed = "Angebot oder Menge hat sich geändert. Preise erneut prüfen.",
    quantity_or_price_missing = "Nicht genug Material zum zulässigen Preis verfügbar.",
    updated_price_exceeds_plan = "Der Live-Preis überschreitet deinen bestätigten Plan.",
    item_not_in_bags = "Das Item befindet sich nicht in deinen Taschen.",
    quantity_missing = "Die gewünschte Menge ist nicht verfügbar.",
    price_missing = "Ein aktueller Stückpreis fehlt.",
    price_below_floor = "Der Preis liegt unter deinem Verkaufsminimum.",
    sale_refresh_required = "Aktuelle Angebote vor dem Posten erneut prüfen.",
    auctionator_missing = "Auctionator mit öffentlicher API v1 ist nicht geladen.",
    list_name_missing = "Bitte einen Listennamen eingeben.",
    timeout = "Das Auktionshaus antwortet nicht. Erneut versuchen.",
    not_enough_money = "Nicht genug Gold verfügbar.",
    api_rejected = "Der Client hat die Aktion abgelehnt.",
    order_missing = "Der Auftrag ist nicht mehr verfügbar.",
    dialog_closed = "Einkaufsfenster geschlossen.",
}

function AHT:ErrorText(code)
    return errors[tostring(code)] or ("Aktion nicht möglich (" .. tostring(code or "unbekannt") .. "). Preise prüfen und erneut versuchen.")
end

function AHT.Commerce:SourceText(source)
    return ({ browse = "AH-Übersicht", detailed = "Detailabfrage", replicate = "AH-Replikat",
        auctionator = "Auctionator-Cache", legacy = "Altbestand", legacy_origin_unknown = "Altbestand: Herkunft unbekannt" })[source] or tostring(source or "unbekannt")
end
