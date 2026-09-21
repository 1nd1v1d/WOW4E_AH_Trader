local AHT = WOW4E_AHT

AHT.Scanner = {
    running = false,
    queue = {},
    completed = 0,
    total = 0,
    mode = "all",
    marketDiscovery = nil,
}

local function EnumValue(container, name, fallback)
    if type(container) == "table" and container[name] ~= nil then return container[name] end
    return fallback
end

local function BuildBrowseQuery()
    local auctionFilters = Enum and Enum.AuctionHouseFilter
    local sortOrders = Enum and Enum.AuctionHouseSortOrder
    local filters = {}
    -- An empty browse query needs at least one filter on the modern AH API.
    -- Include every quality bucket so the discovery scan is not limited to a
    -- profession, category, or the currently selected AH tab.
    for index, name in ipairs({
        "PoorQuality", "CommonQuality", "UncommonQuality", "RareQuality",
        "EpicQuality", "LegendaryQuality", "ArtifactQuality",
    }) do
        table.insert(filters, EnumValue(auctionFilters, name, index + 5))
    end
    return {
        searchString = "",
        filters = filters,
        sorts = {
            { sortOrder = EnumValue(sortOrders, "Price", 0), reverseSort = false },
            { sortOrder = EnumValue(sortOrders, "Name", 1), reverseSort = false },
        },
    }
end

local function AddTarget(targets, seen, item)
    if not item or not item.itemID then return end
    local key = tostring(item.itemID)
    if not seen[key] then
        seen[key] = true
        table.insert(targets, {
            itemID = item.itemID,
            itemKey = item.itemKey,
            name = item.name,
            kind = item.kind,
        })
    end
end

function AHT.Scanner:BuildTargets()
    local targets, seen = {}, {}
    for _, target in ipairs(AHT.Recipes:Targets()) do AddTarget(targets, seen, target) end
    if AHT.Reputation then
        for _, target in ipairs(AHT.Reputation:Targets()) do AddTarget(targets, seen, target) end
    end
    for _, material in pairs(AHT.DB and AHT.DB.materials or {}) do
        if material.enabled ~= false then AddTarget(targets, seen, material) end
    end
    -- A full scan is still serialized through the same AH queue. It covers
    -- bag/bank contents, profession inputs/outputs and all previously stored
    -- market records, so every item uses the same snapshot/history schema.
    if AHT.Inventory and AHT.Inventory.GetScanTargets then
        for _, target in ipairs(AHT.Inventory:GetScanTargets()) do
            AddTarget(targets, seen, target)
        end
    end
    return targets
end

function AHT.Scanner:StartAll()
    self.mode = "all"
    return self:Start(self:BuildTargets())
end

function AHT.Scanner:StartMarketDiscovery()
    if self.running or self.marketDiscovery then
        AHT:Print("Ein AH-Scan läuft bereits.")
        return false
    end
    if not AHT.AHOpen then
        AHT:Print(AHT.L.noAH)
        return false
    end
    if not C_AuctionHouse or type(C_AuctionHouse.SendBrowseQuery) ~= "function" or
            type(C_AuctionHouse.GetBrowseResults) ~= "function" then
        AHT:Print("Der Forever-Client unterstützt keinen vollständigen AH-Markt-Scan.")
        return false
    end

    local discovery = {
        seen = {},
        itemCount = 0,
        pageCount = 0,
        maxPages = 100,
        requesting = false,
    }
    self.marketDiscovery = discovery
    self.mode = "market"
    AHT.State.status = "market_discovery"
    local ok, result = pcall(C_AuctionHouse.SendBrowseQuery, BuildBrowseQuery())
    if not ok or result == false then
        self.marketDiscovery = nil
        AHT.State.status = AHT.AHOpen and "ah_open" or "ready"
        AHT:Print("AH-Markt-Scan konnte nicht gestartet werden.")
        return false
    end
    AHT:Print("AH-Markt-Scan gestartet: alle sichtbaren AH-Items werden erfasst.")
    if AHT.UI then AHT.UI:RefreshStatus() end
    return true
end

function AHT.Scanner:FinishMarketDiscovery()
    local discovery = self.marketDiscovery
    if not discovery then return end
    self.marketDiscovery = nil
    AHT.State.status = AHT.AHOpen and "ah_open" or "ready"
    AHT:Print(string.format("AH-Markt-Scan abgeschlossen: %d Items inventarisiert.", discovery.itemCount or 0))
    if AHT.UI then
        AHT.UI:RefreshStatus()
        AHT.UI:Refresh()
    end
end

function AHT.Scanner:ContinueMarketDiscovery()
    local discovery = self.marketDiscovery
    if not discovery or discovery.requesting then return end
    local hasFull = true
    if type(C_AuctionHouse.HasFullBrowseResults) == "function" then
        local ok, value = pcall(C_AuctionHouse.HasFullBrowseResults)
        if ok then hasFull = value == true end
    end
    if hasFull or type(C_AuctionHouse.RequestMoreBrowseResults) ~= "function" then
        self:FinishMarketDiscovery()
        return
    end

    discovery.requesting = true
    local function Request()
        if self.marketDiscovery ~= discovery then return end
        discovery.requesting = false
        local ok, err = pcall(C_AuctionHouse.RequestMoreBrowseResults)
        if not ok then
            AHT:Print("Weitere AH-Ergebnisse konnten nicht geladen werden: " .. tostring(err))
            self:FinishMarketDiscovery()
        end
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.15, Request) else Request() end
end

function AHT.Scanner:ProcessMarketBrowseResults(results)
    local discovery = self.marketDiscovery
    if not discovery then return end
    discovery.pageCount = discovery.pageCount + 1
    for _, browse in ipairs(results or {}) do
        local itemKey = browse and browse.itemKey
        local itemID = itemKey and tonumber(itemKey.itemID)
        local keyString = itemKey and AHT:ItemKeyString(itemKey)
        local minPrice = tonumber(browse and browse.minPrice)
        if itemID and keyString and not discovery.seen[keyString] and minPrice and minPrice > 0 then
            discovery.seen[keyString] = true
            local info
            if type(C_AuctionHouse.GetItemKeyInfo) == "function" then
                local ok, value = pcall(C_AuctionHouse.GetItemKeyInfo, itemKey)
                if ok then info = value end
            end
            local name = info and info.itemName or AHT:GetItemInfo(itemID)
            AHT.Store:RecordMarket({
                itemID = itemID,
                itemKey = itemKey,
                name = name,
                kind = info and info.isCommodity and "commodity" or "item",
            }, {
                kind = info and info.isCommodity and "commodity" or "item",
                minPrice = minPrice,
                totalQuantity = tonumber(browse.totalQuantity) or 0,
                -- Browse summaries do not expose the number of listings. The
                -- row is still a valid current-price sample; exact searches
                -- continue to provide detailed listing counts for known items.
                listingCount = 1,
                prices = { minPrice },
            })
            discovery.itemCount = discovery.itemCount + 1
        end
    end
    if AHT.UI then AHT.UI:RefreshStatus() end
    if discovery.pageCount >= discovery.maxPages then
        AHT:Print("AH-Markt-Scan nach 100 Browse-Seiten beendet.")
        self:FinishMarketDiscovery()
        return
    end
    self:ContinueMarketDiscovery()
end

function AHT.Scanner:OnEvent(eventName, payload)
    if not self.marketDiscovery then return end
    if eventName == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
        local ok, results = pcall(C_AuctionHouse.GetBrowseResults)
        if ok then self:ProcessMarketBrowseResults(results) else self:FinishMarketDiscovery() end
    elseif eventName == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
        self:ProcessMarketBrowseResults(payload or {})
    end
end

function AHT.Scanner:Start(targets)
    if self.running or self.marketDiscovery then
        AHT:Print("Ein Scan läuft bereits.")
        return
    end
    if not AHT.AHOpen then
        AHT:Print(AHT.L.noAH)
        return
    end
    targets = targets or self:BuildTargets()
    self.mode = self.mode or "all"
    self.queue = targets
    self.completed = 0
    self.total = #targets
    self.running = self.total > 0
    if not self.running then
        AHT:Print("Keine scanbaren Items gefunden.")
        return
    end
    AHT.State.status = "scanning"
    AHT:Print(string.format(AHT.L.scanStart, self.total))
    self:Next()
end

function AHT.Scanner:Next()
    if not self.running then return end
    local target = table.remove(self.queue, 1)
    if not target then
        self.running = false
        AHT.State.status = AHT.AHOpen and "ah_open" or "ready"
        AHT:Print(string.format(AHT.L.scanDone, self.completed))
        AHT:Refresh()
        return
    end

    AHT.AH:Search(target, function(results, meta)
        if meta.error then
            AHT:Print((target.name or tostring(target.itemID)) .. ": " .. meta.error)
        else
            local minPrice = results[1] and results[1].unitPrice or nil
            local totalQuantity = meta.totalQuantity or 0
            AHT.Store:RecordMarket(target, {
                kind = meta.kind,
                minPrice = minPrice,
                totalQuantity = totalQuantity,
                listingCount = meta.listingCount or #results,
                prices = meta.prices,
            })
        end
        self.completed = self.completed + 1
        if AHT.UI then AHT.UI:RefreshStatus() end
        self:Next()
    end)
end

function AHT.Scanner:Stop(reason)
    if self.marketDiscovery then
        self.marketDiscovery = nil
        AHT.State.status = AHT.AHOpen and "ah_open" or "ready"
        AHT:Print(reason == "user" and AHT.L.scanStopped or "Scan abgebrochen: " .. tostring(reason))
        if AHT.UI then AHT.UI:RefreshStatus() end
    end
    if not self.running then return end
    self.running = false
    self.queue = {}
    AHT:Print(reason == "user" and AHT.L.scanStopped or "Scan abgebrochen: " .. tostring(reason))
end
