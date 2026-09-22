local AHT = WOW4E_AHT

AHT.Scanner = {
    running = false,
    queue = {},
    completed = 0,
    total = 0,
    mode = "known",
    marketDiscovery = nil,
    scanRun = nil,
}

local function Notify(message)
    if AHT.UI and AHT.UI.AddMessage then AHT.UI:AddMessage(message)
    else AHT:Print(message) end
end

function AHT.Scanner:BeginScanRun(mode, total)
    if not AHT.DB or not AHT.Store:EnsureLoaded() then return false end
    local run = {
        mode = mode or "known",
        status = "running",
        startedAt = AHT:Now(),
        itemCount = 0,
        rejectedCount = 0,
        pageCount = 0,
        total = tonumber(total),
    }
    AHT.DB.scan = run
    self.scanRun = run
    AHT.Store:Save()
    return true
end

function AHT.Scanner:CountScanResult(recorded)
    local run = self.scanRun
    if not run then return end
    if recorded then run.itemCount = run.itemCount + 1
    else run.rejectedCount = run.rejectedCount + 1 end
    if AHT.DB then AHT.DB.scan = run end
end

function AHT.Scanner:FinishScanRun(status, reason)
    local run = self.scanRun
    if not run then return end
    run.status = status or "completed"
    run.finishedAt = AHT:Now()
    run.duration = math.max(0, (tonumber(run.finishedAt) or 0) - (tonumber(run.startedAt) or 0))
    run.reason = reason and tostring(reason) or nil
    if AHT.DB then AHT.DB.scan = run end
    self.scanRun = nil
    if AHT.Store then AHT.Store:Save() end
end

function AHT.Scanner:GetResultStatus()
    local run = self.scanRun
    if not run then return "completed" end
    if (run.itemCount or 0) == 0 then return "failed" end
    if (run.rejectedCount or 0) > 0 then return "partial" end
    return "completed"
end

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
    return self:Start(self:BuildTargets(), "all")
end

function AHT.Scanner:StartMarketDiscovery()
    if self.running or self.marketDiscovery then
        Notify("Ein AH-Scan läuft bereits.")
        return false
    end
    if not AHT.AHOpen then
        Notify(AHT.L.noAH)
        return false
    end
    if AHT.Store and AHT.Store.EnsureLoaded and not AHT.Store:EnsureLoaded() then
        Notify("AH-Markt-Scan konnte nicht gestartet werden: Datenbank nicht geladen.")
        return false
    end
    if not C_AuctionHouse or type(C_AuctionHouse.SendBrowseQuery) ~= "function" or
            type(C_AuctionHouse.GetBrowseResults) ~= "function" then
        Notify("Der Forever-Client unterstützt keinen vollständigen AH-Markt-Scan.")
        return false
    end

    local discovery = {
        seen = {},
        itemCount = 0,
        rejectedCount = 0,
        pageCount = 0,
        maxPages = 100,
        requesting = false,
    }
    if not self:BeginScanRun("market", nil) then
        Notify("AH-Markt-Scan konnte nicht gestartet werden: Datenbank nicht geladen.")
        return false
    end
    self.marketDiscovery = discovery
    self.mode = "market"
    AHT.State.status = "market_discovery"
    local ok, result = pcall(C_AuctionHouse.SendBrowseQuery, BuildBrowseQuery())
    if not ok or result == false then
        self.marketDiscovery = nil
        self:FinishScanRun("failed", "browse_query_failed")
        AHT.State.status = AHT.AHOpen and "ah_open" or "ready"
        Notify("AH-Markt-Scan konnte nicht gestartet werden.")
        if AHT.UI then AHT.UI:RefreshStatus() end
        return false
    end
    Notify("AH-Markt-Scan gestartet: alle sichtbaren AH-Items werden erfasst.")
    if AHT.UI then AHT.UI:RefreshStatus() end
    return true
end

function AHT.Scanner:FinishMarketDiscovery(status, reason)
    local discovery = self.marketDiscovery
    if not discovery then return end
    self.marketDiscovery = nil
    local run = self.scanRun
    if run then
        run.pageCount = discovery.pageCount or 0
        run.itemCount = discovery.itemCount or 0
        run.rejectedCount = discovery.rejectedCount or 0
    end
    local finalStatus = status or self:GetResultStatus()
    self:FinishScanRun(finalStatus, reason)
    if AHT.Store then AHT.Store:Save() end
    AHT.State.status = AHT.AHOpen and "ah_open" or "ready"
    local stateText = finalStatus == "partial" and "teilweise" or finalStatus == "aborted" and "abgebrochen" or finalStatus == "failed" and "fehlgeschlagen" or "abgeschlossen"
    Notify(string.format("AH-Markt-Scan %s: %d Items, %d verworfen, %d Seiten.", stateText, discovery.itemCount or 0, discovery.rejectedCount or 0, discovery.pageCount or 0))
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
    if hasFull then
        self:FinishMarketDiscovery()
        return
    end
    if type(C_AuctionHouse.RequestMoreBrowseResults) ~= "function" then
        self:FinishMarketDiscovery(discovery.itemCount > 0 and "partial" or "failed", "browse_pagination_unavailable")
        return
    end

    discovery.requesting = true
    local function Request()
        if self.marketDiscovery ~= discovery then return end
        discovery.requesting = false
        local ok, err = pcall(C_AuctionHouse.RequestMoreBrowseResults)
        if not ok then
            Notify("Weitere AH-Ergebnisse konnten nicht geladen werden: " .. tostring(err))
            self:FinishMarketDiscovery(discovery.itemCount > 0 and "partial" or "failed", tostring(err))
        end
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.15, Request) else Request() end
end

function AHT.Scanner:ProcessMarketBrowseResults(results, countPage)
    local discovery = self.marketDiscovery
    if not discovery then return end
    if countPage then
        discovery.pageCount = discovery.pageCount + 1
        local run = self.scanRun
        if run then run.pageCount = discovery.pageCount end
    end
    for _, browse in ipairs(results or {}) do
        local itemKey = browse and browse.itemKey
        local itemID = itemKey and tonumber(itemKey.itemID)
        local keyString = itemKey and AHT:ItemKeyString(itemKey)
        local minPrice = tonumber(browse and browse.minPrice)
        if itemID and keyString and not discovery.seen[keyString] then
            discovery.seen[keyString] = true
            local recorded = false
            if minPrice and minPrice > 0 then
                local info
                if type(C_AuctionHouse.GetItemKeyInfo) == "function" then
                    local ok, value = pcall(C_AuctionHouse.GetItemKeyInfo, itemKey)
                    if ok then info = value end
                end
                local name = info and info.itemName or AHT:GetItemInfo(itemID)
                local record = AHT.Store:RecordMarket({
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
                if record then
                    discovery.itemCount = discovery.itemCount + 1
                    recorded = true
                end
            end
            if not recorded then discovery.rejectedCount = discovery.rejectedCount + 1 end
            self:CountScanResult(recorded)
        end
    end
    if AHT.UI then AHT.UI:RefreshStatus() end
    if discovery.pageCount >= discovery.maxPages then
        Notify("AH-Markt-Scan nach 100 Browse-Seiten beendet.")
        self:FinishMarketDiscovery("partial", "browse_page_limit")
        return
    end
    self:ContinueMarketDiscovery()
end

function AHT.Scanner:OnEvent(eventName, payload)
    if not self.marketDiscovery then return end
    if eventName == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
        local ok, results = pcall(C_AuctionHouse.GetBrowseResults)
        if ok then
            self:ProcessMarketBrowseResults(results, true)
        else
            local state = self.marketDiscovery.itemCount > 0 and "partial" or "failed"
            self:FinishMarketDiscovery(state, "browse_results_unavailable")
        end
    elseif eventName == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
        self:ProcessMarketBrowseResults(payload or {}, false)
    end
end

function AHT.Scanner:Start(targets, mode)
    if self.running or self.marketDiscovery then
        Notify("Ein Scan läuft bereits.")
        return
    end
    if not AHT.AHOpen then
        Notify(AHT.L.noAH)
        return
    end
    if AHT.Store and AHT.Store.EnsureLoaded and not AHT.Store:EnsureLoaded() then
        Notify("AH-Scan konnte nicht gestartet werden: Datenbank nicht geladen.")
        return
    end
    targets = targets or self:BuildTargets()
    self.mode = mode or "known"
    self.queue = targets
    self.completed = 0
    self.total = #targets
    self.running = self.total > 0
    if not self.running then
        Notify("Keine scanbaren Items gefunden.")
        return
    end
    if not self:BeginScanRun(self.mode, self.total) then
        self.running = false
        self.queue = {}
        Notify("AH-Scan konnte nicht gestartet werden: Datenbank nicht geladen.")
        return false
    end
    AHT.State.status = "scanning"
    Notify(string.format(AHT.L.scanStart, self.total))
    if AHT.UI then AHT.UI:RefreshStatus() end
    self:Next()
end

function AHT.Scanner:Next()
    if not self.running then return end
    local target = table.remove(self.queue, 1)
    if not target then
        self.running = false
        local scanStatus = self:GetResultStatus()
        self:FinishScanRun(scanStatus)
        AHT.State.status = AHT.AHOpen and "ah_open" or "ready"
        local scanStatusText = scanStatus == "completed" and "abgeschlossen" or scanStatus == "partial" and "teilweise" or "fehlgeschlagen"
        local scan = AHT.DB and AHT.DB.scan or {}
        Notify(string.format("Scan %s: %d/%d Items erfasst, %d verworfen.", scanStatusText, scan.itemCount or 0, self.total, scan.rejectedCount or 0))
        AHT:Refresh()
        return
    end

    AHT.AH:Search(target, function(results, meta)
        if meta.error then
            Notify((target.name or tostring(target.itemID)) .. ": " .. meta.error)
            self:CountScanResult(false)
        else
            local minPrice = results[1] and results[1].unitPrice or nil
            local totalQuantity = meta.totalQuantity or 0
            local record = AHT.Store:RecordMarket(target, {
                kind = meta.kind,
                minPrice = minPrice,
                totalQuantity = totalQuantity,
                listingCount = meta.listingCount or #results,
                prices = meta.prices,
            })
            self:CountScanResult(record ~= nil)
        end
        self.completed = self.completed + 1
        if AHT.UI then AHT.UI:RefreshStatus() end
        self:Next()
    end)
end

function AHT.Scanner:Stop(reason)
    if self.marketDiscovery then
        local discovery = self.marketDiscovery
        local state = reason == "user" and "aborted" or discovery.itemCount > 0 and "partial" or "failed"
        self.marketDiscovery = nil
        if self.scanRun then
            self.scanRun.itemCount = discovery.itemCount or 0
            self.scanRun.rejectedCount = discovery.rejectedCount or 0
            self.scanRun.pageCount = discovery.pageCount or 0
        end
        self:FinishScanRun(state, reason)
        AHT.State.status = AHT.AHOpen and "ah_open" or "ready"
        local stateText = state == "aborted" and "abgebrochen" or state == "partial" and "teilweise" or "fehlgeschlagen"
        Notify(string.format("Scan %s: %d Items erfasst, %d verworfen, %d Seiten.", stateText, discovery.itemCount or 0, discovery.rejectedCount or 0, discovery.pageCount or 0))
        if AHT.UI then AHT.UI:RefreshStatus() end
    end
    if not self.running then return end
    self.running = false
    self.queue = {}
    AHT.State.status = AHT.AHOpen and "ah_open" or "ready"
    local state = reason == "user" and "aborted" or self.scanRun and self.scanRun.itemCount > 0 and "partial" or "failed"
    self:FinishScanRun(state, reason)
    local stateText = state == "aborted" and "abgebrochen" or state == "partial" and "teilweise" or "fehlgeschlagen"
    Notify("Scan " .. stateText .. ". Bereits erfasste Werte bleiben erhalten.")
    if AHT.UI then AHT.UI:RefreshStatus() end
end
