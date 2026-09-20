local AHT = WOW4E_AHT

AHT.Tooltips = {
    initialized = false,
    processing = false,
}

local function AddMarketLines(tooltip)
    if not tooltip or (tooltip.IsForbidden and tooltip:IsForbidden()) then return end
    if AHT.Tooltips.processing then return end
    if not AHT.GetItemID or not AHT.Store or not AHT.Store.GetMarketSnapshot then return end

    local getItem = tooltip.GetItem
    if type(getItem) ~= "function" then return end
    local ok, name, link = pcall(getItem, tooltip)
    if not ok then return end
    local itemID = AHT:GetItemID(link) or AHT:GetItemID(name)
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
    if not tooltip or type(tooltip.HookScript) ~= "function" then return end
    tooltip:HookScript("OnTooltipSetItem", AddMarketLines)
end

function AHT.Tooltips:Initialize()
    if self.initialized then return end
    self.initialized = true
    HookTooltip(_G.GameTooltip)
    HookTooltip(_G.ItemRefTooltip)
    HookTooltip(_G.ShoppingTooltip1)
    HookTooltip(_G.ShoppingTooltip2)
end
