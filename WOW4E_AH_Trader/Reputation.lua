local AHT = WOW4E_AHT

AHT.Reputation = {
    runeclothItemID = 14047,
    runeclothPerDonation = 20,
    reputationPerDonation = 50,
    targetStanding = 8,
    watchBar = nil,
    hooked = false,
}

-- Standard Classic reputation band widths from Hated through Revered.
AHT.Reputation.standingWidths = {
    [1] = 36000,
    [2] = 3000,
    [3] = 3000,
    [4] = 3000,
    [5] = 6000,
    [6] = 12000,
    [7] = 21000,
}

-- IDs avoid localization problems. Names remain as a fallback for clients
-- that do not expose factionID through their watched-faction API.
AHT.Reputation.capitalFactionIDs = {
    [72] = true,   -- Stormwind
    [47] = true,   -- Ironforge
    [69] = true,   -- Darnassus
    [54] = true,   -- Gnomeregan Exiles
    [76] = true,   -- Orgrimmar
    [81] = true,   -- Thunder Bluff
    [68] = true,   -- Undercity
    [530] = true,  -- Darkspear Trolls
}

AHT.Reputation.capitalFactionNames = {
    ["stormwind"] = true,
    ["sturmwind"] = true,
    ["ironforge"] = true,
    ["eisenschmiede"] = true,
    ["darnassus"] = true,
    ["gnomeregan exiles"] = true,
    ["gnomereganexil"] = true,
    ["orgrimmar"] = true,
    ["thunder bluff"] = true,
    ["donnerfels"] = true,
    ["undercity"] = true,
    ["unterstadt"] = true,
    ["darkspear trolls"] = true,
    ["dunkelspeer-trolle"] = true,
}

local function ReadWatchedFaction()
    if C_Reputation and C_Reputation.GetWatchedFactionData then
        local ok, data = pcall(C_Reputation.GetWatchedFactionData)
        if ok and type(data) == "table" and data.name then
            return {
                name = data.name,
                standingID = data.reaction,
                barMin = data.currentReactionThreshold,
                barMax = data.nextReactionThreshold,
                barValue = data.currentStanding,
                factionID = data.factionID,
            }
        end
    end

    if GetWatchedFactionInfo then
        local ok, name, standingID, barMin, barMax, barValue, factionID = pcall(GetWatchedFactionInfo)
        if ok and name then
            return {
                name = name,
                standingID = standingID,
                barMin = barMin,
                barMax = barMax,
                barValue = barValue,
                factionID = factionID,
            }
        end
    end
end

function AHT.Reputation:IsCapitalFaction(data)
    if not data then return false end
    if data.factionID and self.capitalFactionIDs[tonumber(data.factionID)] then return true end
    local name = data.name and string.lower(data.name) or nil
    return name and self.capitalFactionNames[name] == true or false
end

function AHT.Reputation:CalculateDonations(standingID, barMax, barValue)
    standingID = tonumber(standingID)
    barMax = tonumber(barMax)
    barValue = tonumber(barValue)
    if not standingID or not barMax or not barValue then return nil, nil end
    if standingID >= self.targetStanding then return 0, 0 end

    local remaining = math.max(0, barMax - barValue)
    for standing = standingID + 1, self.targetStanding - 1 do
        remaining = remaining + (self.standingWidths[standing] or 0)
    end
    return math.ceil(remaining / self.reputationPerDonation), remaining
end

function AHT.Reputation:GetStatus()
    local data = ReadWatchedFaction()
    if not data then return nil, "no_watched_faction" end
    data.isCapital = self:IsCapitalFaction(data)
    if not data.isCapital then return data, "not_capital_faction" end

    data.donations, data.missingReputation = self:CalculateDonations(
        data.standingID, data.barMax, data.barValue
    )
    if not data.donations then return data, "reputation_data_incomplete" end
    data.runecloth = data.donations * self.runeclothPerDonation
    return data
end

function AHT.Reputation:GetRuneclothPrice()
    if not AHT.Store or not AHT.DB then return nil, nil end
    local key = AHT.Store:MarketKey(self.runeclothItemID)
    local average = AHT.Store.WeightedAverage and AHT.Store:WeightedAverage(key)
    if average and average > 0 then return average, "gew. Durchschnitt" end

    local current = AHT.Store:GetPrice(self.runeclothItemID)
    if current and current > 0 then return current, "akt. Preis" end
    return nil, nil
end

function AHT.Reputation:GetCost(status)
    if not status or not status.runecloth then return nil, nil end
    local price, source = self:GetRuneclothPrice()
    if not price then return nil, nil end
    return price * status.runecloth, source, price
end

function AHT.Reputation:Targets()
    return {{
        itemID = self.runeclothItemID,
        name = "Runenstoff / Runecloth",
        kind = "reputation_material",
    }}
end

function AHT.Reputation:AppendTooltip(frame)
    local status = self:GetStatus()
    if not status or not status.isCapital or not status.donations then return false end
    if not GameTooltip or not GameTooltip.AddLine then return false end

    if GameTooltip.IsShown and not GameTooltip:IsShown() and GameTooltip.SetOwner then
        GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|cff00ccff[AH Trader] Runenstoff-Spenden|r")
    if status.standingID < 4 then
        GameTooltip:AddLine("|cffff8080Spenden sind erst ab Neutral möglich.|r")
    end
    if status.donations == 0 then
        GameTooltip:AddLine("|cff00ff00Bereits Ehrfürchtig!|r")
    else
        GameTooltip:AddDoubleLine("Fehlender Ruf:", tostring(status.missingReputation) .. " Punkte", 0.9, 0.9, 0.9, 1, 1, 0.5)
        GameTooltip:AddDoubleLine("Benötigte Spenden:", tostring(status.donations) .. "x", 0.9, 0.9, 0.9, 0.4, 1, 0.4)
        GameTooltip:AddDoubleLine("Runenstoff gesamt:", tostring(status.runecloth) .. "x", 0.9, 0.9, 0.9, 1, 0.65, 0)

        local cost, source, unitPrice = self:GetCost(status)
        if cost then
            GameTooltip:AddDoubleLine("Runenstoff-Preis:", AHT:FormatMoneyPlain(unitPrice) .. " (" .. source .. ")", 0.7, 0.9, 1, 1, 1, 1)
            GameTooltip:AddDoubleLine("Gesamtkosten:", AHT:FormatMoneyPlain(cost), 0.7, 0.9, 1, 1, 0.9, 0.3)
        else
            GameTooltip:AddLine("Noch kein Runenstoff-Marktpreis vorhanden. /aht scan")
        end
    end
    GameTooltip:Show()
    self.tooltipActive = true
    return true
end

function AHT.Reputation:ClearTooltip()
    if self.tooltipActive and GameTooltip and GameTooltip.Hide then
        GameTooltip:Hide()
        self.tooltipActive = false
    end
end

function AHT.Reputation:HookWatchBar()
    if self.hooked then return true end
    local bar = _G.ReputationWatchBar or _G.ReputationWatchBarFrame or _G.ReputationWatchStatusBar
    if not bar then return false end

    if bar.HookScript then
        bar:HookScript("OnEnter", function(frame)
            self:AppendTooltip(frame)
        end)
        bar:HookScript("OnLeave", function()
            self:ClearTooltip()
        end)
    elseif bar.SetScript then
        local originalEnter = bar.GetScript and bar:GetScript("OnEnter")
        local originalLeave = bar.GetScript and bar:GetScript("OnLeave")
        bar:SetScript("OnEnter", function(frame, ...)
            if originalEnter then originalEnter(frame, ...) end
            self:AppendTooltip(frame)
        end)
        bar:SetScript("OnLeave", function(frame, ...)
            if originalLeave then originalLeave(frame, ...) end
            self:ClearTooltip()
        end)
    else
        return false
    end
    self.watchBar = bar
    self.hooked = true
    return true
end

function AHT.Reputation:Initialize()
    if self:HookWatchBar() then return end
    if C_Timer and C_Timer.After then
        C_Timer.After(1, function() self:HookWatchBar() end)
    end
end

function AHT.Reputation:OnEvent(eventName)
    if eventName == "PLAYER_ENTERING_WORLD" or eventName == "PLAYER_LOGIN" or eventName == "UPDATE_FACTION" then
        self:HookWatchBar()
    end
end

function AHT.Reputation:Print()
    if AHT.UI then
        AHT.UI:SetView("reputation")
        return
    end
    local status, reason = self:GetStatus()
    if not status or not status.isCapital then
        AHT:Print("Keine beobachtete Hauptstadtfraktion. Grund: " .. tostring(reason or "unbekannt"))
        return
    end
    if status.donations == 0 then
        AHT:Print(status.name .. ": bereits Ehrfürchtig.")
        return
    end
    local cost, source = self:GetCost(status)
    AHT:Print(string.format(
        "%s: %d Spenden / %d Runenstoff bis Ehrfürchtig%s",
        status.name, status.donations, status.runecloth,
        cost and string.format(" | %s (%s)", AHT:FormatMoneyPlain(cost), source) or ""
    ))
end
