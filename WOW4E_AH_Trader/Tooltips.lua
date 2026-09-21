local AHT = WOW4E_AHT

AHT.Tooltips = {
    initialized = false,
    processing = false,
}

local function AddMarketLines(tooltip, itemIDOverride)
    if not tooltip or (tooltip.IsForbidden and tooltip:IsForbidden()) then return end
    if AHT.Tooltips.processing then return end
    if not AHT.GetItemID or not AHT.Store or not AHT.Store.GetMarketSnapshot then return end

    local itemID = tonumber(itemIDOverride)
    if not itemID and TooltipUtil and type(TooltipUtil.GetDisplayedItem) == "function" then
        local ok, _, link, displayedID = pcall(TooltipUtil.GetDisplayedItem, tooltip)
        if ok then itemID = tonumber(displayedID) or AHT:GetItemID(link) end
    end
    -- Legacy Forever builds may not expose TooltipUtil. Keep the old path as
    -- a guarded fallback, but never assume that GetItem exists.
    if not itemID and type(tooltip.GetItem) == "function" then
        local ok, name, link = pcall(tooltip.GetItem, tooltip)
        if ok then itemID = AHT:GetItemID(link) or AHT:GetItemID(name) end
    end
    if not itemID then return end

    local snapshot = AHT.Store:GetMarketSnapshot(itemID)
    AHT.Tooltips.processing = true
    if tooltip.AddLine then tooltip:AddLine(" ") end
    if not snapshot then
        if tooltip.AddLine then
            tooltip:AddLine("WoW4E AH Trader: noch nicht gescannt", 0.65, 0.75, 0.95)
            tooltip:AddLine("Im AH mit 'Scan' aktualisieren.", 0.55, 0.55, 0.55)
        end
        AHT.Tooltips.processing = false
        if tooltip.Show then tooltip:Show() end
        return
    end

    if tooltip.AddLine then tooltip:AddLine("WoW4E AH Trader", 1, 0.84, 0.35) end
    if tooltip.AddDoubleLine then
        local changeR, changeG = 0.75, 0.75
        if snapshot.priceChangePercent then
            if snapshot.priceChangePercent >= 0 then changeR, changeG = 0.45, 1 else changeR, changeG = 1, 0.45 end
        end
        tooltip:AddDoubleLine(
            "AH aktuell",
            snapshot.currentPrice and AHT:FormatMoneyPlain(snapshot.currentPrice) or "kein Angebot",
            0.78, 0.78, 0.78, 1, 0.85, 0.35
        )
        tooltip:AddDoubleLine(
            "Robuster Marktwert",
            snapshot.marketValue and AHT:FormatMoneyPlain(snapshot.marketValue) or "?",
            0.78, 0.78, 0.78, 0.45, 0.85, 1
        )
        tooltip:AddDoubleLine(
            "Altersgewichteter Ø",
            snapshot.averagePrice and AHT:FormatMoneyPlain(snapshot.averagePrice) or "?",
            0.78, 0.78, 0.78, 0.45, 1, 0.45
        )
        tooltip:AddDoubleLine(
            "Seit letztem Scan",
            snapshot.priceChangePercent and string.format("%+.1f%%", snapshot.priceChangePercent) or "noch kein Vergleich",
            0.78, 0.78, 0.78, changeR, changeG, 0.45
        )
        tooltip:AddDoubleLine(
            "Aktuell vs. Marktwert",
            snapshot.trendPercent and string.format("%+.1f%%", snapshot.trendPercent) or "?",
            0.78, 0.78, 0.78, 0.45, 0.85, 1
        )
    end
    if tooltip.AddLine then
        local updated = snapshot.updatedAt and date("%d.%m.%y %H:%M", snapshot.updatedAt) or "?"
        tooltip:AddLine(string.format(
            "Angebot: %d Stück / %d Listings | Scan: %s",
            snapshot.totalQuantity or 0, snapshot.listingCount or 0, updated
        ), 0.62, 0.72, 0.95)
    end
    AHT.Tooltips.processing = false
    if tooltip.Show then tooltip:Show() end
end

local function HookTooltip(tooltip)
    if not tooltip or type(tooltip.HookScript) ~= "function" then return false end
    -- Forever's current tooltip objects no longer expose the legacy
    -- OnTooltipSetItem script. Protect this fallback because HookScript throws
    -- when a script type is unavailable on the client build.
    local ok = pcall(tooltip.HookScript, tooltip, "OnTooltipSetItem", function(frame)
        AddMarketLines(frame)
    end)
    return ok
end

function AHT.Tooltips:Initialize()
    if self.initialized then return end
    self.initialized = true

    -- Modern Forever clients use TooltipDataProcessor for item tooltips.
    -- Register once for the item data type; this covers inventory, bank,
    -- profession and item-reference tooltips without touching their scripts.
    local itemType = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item
    if TooltipDataProcessor and type(TooltipDataProcessor.AddTooltipPostCall) == "function" and itemType ~= nil then
        local ok = pcall(TooltipDataProcessor.AddTooltipPostCall, itemType, function(tooltip, data)
            AddMarketLines(tooltip, data and data.id)
        end)
        if ok then
            self.mode = "data_processor"
            return
        end
    end

    -- Compatibility fallback for older clients that still support the script.
    self.mode = "legacy"
    HookTooltip(_G.GameTooltip)
    HookTooltip(_G.ItemRefTooltip)
    HookTooltip(_G.ShoppingTooltip1)
    HookTooltip(_G.ShoppingTooltip2)
end
