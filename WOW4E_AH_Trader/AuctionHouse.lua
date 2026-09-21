local AHT = WOW4E_AHT

AHT.AH = {
    queue = {},
    active = nil,
    serial = 0,
    pumpScheduled = false,
    retryLimit = 2,
    timeout = 15,
}

local THROTTLE_EVENTS = {
    AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED = true,
    AUCTION_HOUSE_THROTTLED_MESSAGE_QUEUED = true,
    AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED = true,
    AUCTION_HOUSE_THROTTLED_MESSAGE_SENT = true,
    AUCTION_HOUSE_THROTTLED_SYSTEM_READY = true,
}

local function SafeCall(fn, ...)
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end

function AHT.AH:IsReady()
    if C_AuctionHouse and C_AuctionHouse.IsThrottledMessageSystemReady then
        local ok, ready = pcall(C_AuctionHouse.IsThrottledMessageSystemReady)
        return ok and ready == true
    end
    return true
end

function AHT.AH:SchedulePump()
    if self.pumpScheduled then return end
    self.pumpScheduled = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0.1, function()
            self.pumpScheduled = false
            self:Pump()
        end)
    else
        self.pumpScheduled = false
        self:Pump()
    end
end

function AHT.AH:Search(target, callback)
    if not target or not target.itemID then
        if callback then callback({}, { error = "item_id_missing" }) end
        return false
    end
    self.serial = self.serial + 1
    table.insert(self.queue, {
        id = self.serial,
        target = target,
        callback = callback,
        retries = 0,
    })
    self:SchedulePump()
    return true
end

local function FindChildObject(parent, objectType, depth, predicate)
    if not parent or depth > 4 or type(parent.GetChildren) ~= "function" then return nil end
    local children = { parent:GetChildren() }
    for _, child in ipairs(children) do
        if child and type(child.IsObjectType) == "function" then
            local ok, matches = pcall(child.IsObjectType, child, objectType)
            if ok and matches and (not predicate or predicate(child)) then return child end
        end
        local nested = FindChildObject(child, objectType, depth + 1, predicate)
        if nested then return nested end
    end
end

local function FindSearchControl(parent, names, objectType)
    for _, name in ipairs(names) do
        local control = parent and parent[name]
        if control then return control end
    end
    return FindChildObject(parent, objectType, 0)
end

local function FindSearchButton(parent)
    for _, name in ipairs({ "SearchButton", "searchButton", "Search", "searchButtonFrame" }) do
        local named = parent and parent[name]
        if named then return named end
    end
    local byText = FindChildObject(parent, "Button", 0, function(button)
        if type(button.GetText) ~= "function" then return false end
        local ok, text = pcall(button.GetText, button)
        text = string.lower(tostring(ok and text or ""))
        return text == "suchen" or text == "search"
    end)
    return byText or FindChildObject(parent, "Button", 0)
end

function AHT.AH:OpenItemInAuctionHouse(target)
    if not target or not target.itemID then return false, "item_id_missing" end
    if not AHT.AHOpen then return false, "auction_house_closed" end

    local frame = _G.AuctionHouseFrame
    if not frame then return false, "auction_house_frame_missing" end
    if frame.Show then frame:Show() end

    local searchBar = frame.SearchBar or frame.searchBar or frame.SearchPanel or frame.searchPanel or frame
    local searchBox = FindSearchControl(searchBar, {
        "SearchBox", "searchBox", "SearchTextBox", "searchTextBox", "EditBox", "editBox",
    }, "EditBox")
    local searchButton = FindSearchButton(searchBar)
    local itemName = AHT:GetItemInfo(target.itemID)
    -- The Blizzard AH browse search expects the resolved item name. Passing a
    -- raw item hyperlink falls back to an empty/broad browse query on Forever.
    local query = itemName or target.name or tostring(target.itemID)

    if type(frame.SetDisplayMode) == "function" and type(AuctionHouseFrameDisplayMode) == "table" and AuctionHouseFrameDisplayMode.Buy then
        pcall(frame.SetDisplayMode, frame, AuctionHouseFrameDisplayMode.Buy)
    end

    local searchTextSet = false
    if type(frame.SetSearchText) == "function" then
        local ok, accepted = pcall(frame.SetSearchText, frame, query)
        searchTextSet = ok and accepted ~= false
    elseif searchBar and type(searchBar.SetSearchText) == "function" then
        local ok = pcall(searchBar.SetSearchText, searchBar, query)
        searchTextSet = ok
    end

    local itemKey = target.itemKey or AHT:MakeItemKey(target.itemID)
    local itemContext
    if type(AuctionHouseSearchContext) == "table" then
        local keyInfo
        if C_AuctionHouse and type(C_AuctionHouse.GetItemKeyInfo) == "function" then
            local ok, value = pcall(C_AuctionHouse.GetItemKeyInfo, itemKey)
            if ok then keyInfo = value end
        end
        itemContext = keyInfo and keyInfo.isCommodity and AuctionHouseSearchContext.BuyCommodities or AuctionHouseSearchContext.BuyItems
    end

    -- QueryItem is the client's item-specific path. It updates the AH result
    -- frame and avoids the broad browse query caused by submitting a blank
    -- search box.
    if type(frame.QueryItem) == "function" and itemContext then
        local ok, result = pcall(frame.QueryItem, frame, itemContext, itemKey, false)
        -- QueryItem returns nil on a successful query in Blizzard's client.
        -- Only an explicit false means that this path declined the request.
        if ok and result ~= false then return true end
    end

    if searchBar and type(searchBar.StartSearch) == "function" and searchTextSet then
        local ok = pcall(searchBar.StartSearch, searchBar)
        if ok then return true end
    end

    if searchBox and searchBox.SetText then
        pcall(searchBox.SetText, searchBox, query)
        if searchBox.ClearFocus then pcall(searchBox.ClearFocus, searchBox) end
    end

    -- Prefer the client's own submit control so its result panel, filters and
    -- selected item state stay synchronized with the query field.
    if searchButton and searchButton.Click then
        local ok = pcall(searchButton.Click, searchButton)
        if ok then return true end
    end
    if searchBox and searchBox.GetScript then
        local handler = searchBox:GetScript("OnEnterPressed")
        if type(handler) == "function" then
            local ok = pcall(handler, searchBox)
            if ok then return true end
        end
    end

    local directSearch = searchBar.SearchForItem or searchBar.searchForItem or frame.SearchForItem or frame.searchForItem
    if type(directSearch) == "function" then
        local owner = frame
        if searchBar.SearchForItem == directSearch or searchBar.searchForItem == directSearch then
            owner = searchBar
        end
        local ok = pcall(directSearch, owner, query)
        if ok then return true end
    end

    -- Last-resort fallback for client builds without an exposed SearchBar.
    -- The official result event will still update the AH frame when it listens
    -- to C_AuctionHouse search responses.
    if C_AuctionHouse and C_AuctionHouse.SendSearchQuery then
        local ok = pcall(C_AuctionHouse.SendSearchQuery, itemKey, { sortOrder = 0, reverseSort = false }, false)
        if ok then return true end
    end
    return false, "auction_house_search_control_missing"
end

function AHT.AH:Pump()
    if self.active then return end
    if not AHT.AHOpen then
        while #self.queue > 0 do
            local operation = table.remove(self.queue, 1)
            if operation.callback then operation.callback({}, { error = "auction_house_closed" }) end
        end
        return
    end
    if not self:IsReady() then
        self:SchedulePump()
        return
    end

    local operation = table.remove(self.queue, 1)
    if not operation then return end
    local target = operation.target
    operation.itemKey = target.itemKey or AHT:MakeItemKey(target.itemID)
    operation.startedAt = GetTime and GetTime() or 0
    operation.state = "sent"
    self.active = operation
    AHT.State.lastOperation = operation
    AHT.State.status = "ah_query"

    if not C_AuctionHouse or not C_AuctionHouse.SendSearchQuery then
        self:Finish({}, { error = "send_search_query_missing" })
        return
    end

    -- A valid modern sort descriptor is required by the client. We sort the
    -- returned rows ourselves, so the commodity price order is sufficient for
    -- both commodity and item searches.
    local sorts = { sortOrder = 0, reverseSort = false }
    local ok, err = SafeCall(C_AuctionHouse.SendSearchQuery, operation.itemKey, sorts, false)
    if not ok then
        self:Finish({}, { error = tostring(err or "send_search_query_failed") })
    end
end

function AHT.AH:OnUpdate()
    if not self.active or not self.active.startedAt then return end
    local now = GetTime and GetTime() or 0
    if now - self.active.startedAt < self.timeout then return end

    local operation = self.active
    self.active = nil
    if operation.retries < self.retryLimit and AHT.AHOpen then
        operation.retries = operation.retries + 1
        table.insert(self.queue, 1, operation)
        AHT.State.status = "ah_retry"
        self:SchedulePump()
    else
        self:CallCallback(operation, {}, { error = "timeout", operationID = operation.id })
        AHT.State.status = "ah_error"
        self:SchedulePump()
    end
end

local function IsOwned(info)
    return info and (info.containsOwnerItem or info.containsAccountItem) == true
end

function AHT.AH:CollectItemResults(operation)
    local results = {}
    local prices = {}
    local totalQuantity = 0
    local count = 0
    if not C_AuctionHouse.GetNumItemSearchResults or not C_AuctionHouse.GetItemSearchResultInfo then
        return results, { error = "item_result_api_missing" }
    end

    local total = C_AuctionHouse.GetNumItemSearchResults(operation.itemKey) or 0
    for index = 1, total do
        local info = C_AuctionHouse.GetItemSearchResultInfo(operation.itemKey, index)
        if info then
            local quantity = tonumber(info.quantity) or 0
            local buyout = tonumber(info.buyoutAmount) or 0
            if quantity > 0 and buyout > 0 and not IsOwned(info) then
                count = count + 1
                totalQuantity = totalQuantity + quantity
                table.insert(prices, math.floor(buyout / quantity))
                table.insert(results, {
                    kind = "item",
                    itemID = operation.target.itemID,
                    itemKey = info.itemKey or operation.itemKey,
                    itemLink = info.itemLink,
                    auctionID = info.auctionID,
                    quantity = quantity,
                    buyoutAmount = buyout,
                    unitPrice = math.floor(buyout / quantity),
                    owners = info.owners,
                    timeLeft = info.timeLeft,
                    containsOwnerItem = info.containsOwnerItem,
                })
            end
        end
    end
    table.sort(results, function(a, b) return a.unitPrice < b.unitPrice end)
    return results, { kind = "item", listingCount = count, totalQuantity = totalQuantity, prices = prices }
end

function AHT.AH:CollectCommodityResults(operation)
    local results = {}
    local prices = {}
    local totalQuantity = 0
    local count = 0
    if not C_AuctionHouse.GetNumCommoditySearchResults or not C_AuctionHouse.GetCommoditySearchResultInfo then
        return results, { error = "commodity_result_api_missing" }
    end

    local total = C_AuctionHouse.GetNumCommoditySearchResults(operation.target.itemID) or 0
    for index = 1, total do
        local info = C_AuctionHouse.GetCommoditySearchResultInfo(operation.target.itemID, index)
        if info and (tonumber(info.quantity) or 0) > 0 and (tonumber(info.unitPrice) or 0) > 0 then
            count = count + 1
            totalQuantity = totalQuantity + info.quantity
            table.insert(prices, info.unitPrice)
            table.insert(results, {
                kind = "commodity",
                itemID = operation.target.itemID,
                auctionID = info.auctionID,
                quantity = info.quantity,
                unitPrice = info.unitPrice,
                owners = info.owners,
                timeLeftSeconds = info.timeLeftSeconds,
                containsOwnerItem = info.containsOwnerItem,
            })
        end
    end
    table.sort(results, function(a, b) return a.unitPrice < b.unitPrice end)
    return results, { kind = "commodity", listingCount = count, totalQuantity = totalQuantity, prices = prices }
end

function AHT.AH:CallCallback(operation, results, meta)
    if operation and operation.callback then
        local ok, err = pcall(operation.callback, results, meta or {})
        if not ok then AHT:Print("Callback-Fehler: " .. tostring(err)) end
    end
end

function AHT.AH:Finish(results, meta)
    local operation = self.active
    self.active = nil
    if operation then
        meta = meta or {}
        meta.operationID = operation.id
        self:CallCallback(operation, results, meta)
    end
    AHT.State.status = AHT.AHOpen and "ah_open" or "ready"
    self:SchedulePump()
end

function AHT.AH:OnEvent(eventName, itemRef)
    if THROTTLE_EVENTS[eventName] then
        if eventName == "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED" and self.active then
            local operation = self.active
            self.active = nil
            if operation.retries < self.retryLimit then
                operation.retries = operation.retries + 1
                table.insert(self.queue, 1, operation)
                self:SchedulePump()
            else
                self:CallCallback(operation, {}, { error = "throttled", operationID = operation.id })
            end
        elseif eventName == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
            self:SchedulePump()
        end
        return
    end

    if not self.active then return end
    if eventName == "ITEM_SEARCH_RESULTS_UPDATED" then
        local operation = self.active
        -- Other AH addons can receive the same global event. Only consume the
        -- event when Blizzard supplied a matching item key; older clients may
        -- omit the argument, in which case the timeout remains the fallback.
        if itemRef and type(itemRef) == "table" and operation.itemKey and
                AHT:ItemKeyString(itemRef) ~= AHT:ItemKeyString(operation.itemKey) then
            return
        end
        local results, meta = self:CollectItemResults(operation)
        self:Finish(results, meta)
    elseif eventName == "COMMODITY_SEARCH_RESULTS_UPDATED" then
        local operation = self.active
        if itemRef and tonumber(itemRef) and tonumber(itemRef) ~= tonumber(operation.target.itemID) then
            return
        end
        local results, meta = self:CollectCommodityResults(operation)
        self:Finish(results, meta)
    end
end

function AHT.AH:Cancel(reason)
    self.queue = {}
    local operation = self.active
    self.active = nil
    if operation then self:CallCallback(operation, {}, { error = reason or "cancelled" }) end
    AHT.State.status = AHT.AHOpen and "ah_open" or "ready"
end
