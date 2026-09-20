local AHT = WOW4E_AHT

AHT.Capabilities = {}

-- The modern auction APIs use enum values (1/2/3), while the UI commonly
-- exposes the familiar 12/24/48 hour choices. Keep that conversion in one
-- place so deposit calculations and posting always receive the API value.
AHT.AUCTION_DURATIONS = {
    [12] = 1,
    [24] = 2,
    [48] = 3,
}

function AHT:NormalizeAuctionDuration(value)
    value = tonumber(value)
    if not value then return 2 end
    return self.AUCTION_DURATIONS[value] or math.max(1, math.min(3, math.floor(value)))
end

local function HasFunction(container, name)
    return type(container) == "table" and type(container[name]) == "function"
end

function AHT.Capabilities:Probe()
    local version, build, dateText, interface = GetBuildInfo()
    local c = {
        version = version,
        build = build,
        buildDate = dateText,
        interface = interface,
        projectID = WOW_PROJECT_ID,
        projectMainline = WOW_PROJECT_MAINLINE,
        foreverBeta = tonumber(interface) == 16001,
        auctionHouse = type(C_AuctionHouse) == "table",
        item = type(C_Item) == "table",
        container = type(C_Container) == "table",
        tradeSkill = type(C_TradeSkillUI) == "table",
        itemCount = HasFunction(C_Item, "GetItemCount") or type(GetItemCount) == "function",
        reputation = type(C_Reputation) == "table" or type(GetWatchedFactionInfo) == "function",
        functions = {},
    }

    local ahFunctions = {
        "MakeItemKey", "SendSearchQuery", "SendBrowseQuery", "GetNumItemSearchResults",
        "GetItemSearchResultInfo", "GetNumCommoditySearchResults", "GetCommoditySearchResultInfo",
        "PlaceBid", "StartCommoditiesPurchase", "ConfirmCommoditiesPurchase", "CancelCommoditiesPurchase",
        "GetItemCommodityStatus", "PostItem",
        "PostCommodity", "CalculateItemDeposit", "CalculateCommodityDeposit",
        "IsThrottledMessageSystemReady", "ReplicateItems", "GetItemKeyInfo",
    }
    for _, name in ipairs(ahFunctions) do
        c.functions["C_AuctionHouse." .. name] = HasFunction(C_AuctionHouse, name)
    end
    c.functions["C_Reputation.GetWatchedFactionData"] = HasFunction(C_Reputation, "GetWatchedFactionData")
    c.functions["GetWatchedFactionInfo"] = type(GetWatchedFactionInfo) == "function"
    c.functions["C_Item.GetItemCount"] = HasFunction(C_Item, "GetItemCount")
    c.functions["GetItemCount"] = type(GetItemCount) == "function"

    -- Keep the module table intact. Replacing AHT.Capabilities with the
    -- probe result would discard Probe/Has/Summary and make the next call
    -- such as AHT.Capabilities:Summary() fail during addon startup.
    for key, value in pairs(c) do
        self[key] = value
    end
    return self
end

function AHT.Capabilities:Has(name)
    return self.functions and self.functions[name] == true
end

function AHT.Capabilities:Summary()
    local c = self
    return string.format(
        "Build %s / Interface %s / AH %s / TradeSkill %s / Reputation %s",
        tostring(c.build or "?"), tostring(c.interface or "?"),
        c.auctionHouse and "ok" or "missing", c.tradeSkill and "ok" or "missing",
        c.reputation and "ok" or "missing"
    )
end

function AHT:MakeItemKey(itemID)
    if not itemID then return nil end
    if C_AuctionHouse and C_AuctionHouse.MakeItemKey then
        local ok, key = pcall(C_AuctionHouse.MakeItemKey, itemID)
        if ok and type(key) == "table" then return key end
    end
    return { itemID = itemID, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }
end

function AHT:ItemKeyString(key)
    if not key then return nil end
    if type(key) == "number" then return tostring(key) end
    return table.concat({
        tostring(key.itemID or 0), tostring(key.itemLevel or 0),
        tostring(key.itemSuffix or 0), tostring(key.battlePetSpeciesID or 0),
    }, ":")
end

function AHT:GetItemID(value)
    if type(value) == "number" then return value end
    if type(value) ~= "string" then return nil end

    value = value:match("^%s*(.-)%s*$")
    if value == "" then return nil end

    -- The material input accepts an item ID as well as an item link. This is
    -- important when the client has not cached the item name/link yet.
    local numericID = value:match("^(%d+)$")
    if numericID then return tonumber(numericID) end

    local linkID = value:match("|Hitem:(%d+)")
    if linkID then return tonumber(linkID) end

    if C_Item and C_Item.GetItemInfoInstant then
        local ok, itemID = pcall(C_Item.GetItemInfoInstant, value)
        if ok and type(itemID) == "number" then return itemID end
    end
    if GetItemInfoInstant then
        local ok, itemID = pcall(GetItemInfoInstant, value)
        if ok and type(itemID) == "number" then return itemID end
    end
    return nil
end

function AHT:GetItemInfo(value)
    if C_Item and C_Item.GetItemInfo then
        local ok, name, link, quality, itemLevel, minLevel, itemType, itemSubType,
            stackCount, equipLoc, texture, sellPrice = pcall(C_Item.GetItemInfo, value)
        if ok then
            return name, link, quality, itemLevel, minLevel, itemType, itemSubType,
                stackCount, equipLoc, texture, sellPrice
        end
    end
    if GetItemInfo then return GetItemInfo(value) end
end

function AHT:GetItemLocation(bag, slot)
    if ItemLocation and ItemLocation.CreateFromBagAndSlot then
        local ok, location = pcall(ItemLocation.CreateFromBagAndSlot, ItemLocation, bag, slot)
        if ok then return location end
    end
    if C_Container and C_Container.GetContainerItemInfo then
        return { bagID = bag, slotIndex = slot }
    end
end
