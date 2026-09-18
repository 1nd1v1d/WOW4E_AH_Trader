WOW4E_AHT = WOW4E_AHT or {}
local AHT = WOW4E_AHT

AHT.ADDON_NAME = "WOW4E_AH_Trader"
AHT.VERSION = "0.2.0-beta"
AHT.AHOpen = false
AHT.Initialized = false
AHT.State = {
    status = "starting",
    lastError = nil,
    lastOperation = nil,
}

AHT.EventFrame = CreateFrame("Frame")

local function SafeRegister(frame, eventName)
    pcall(frame.RegisterEvent, frame, eventName)
end

local EVENTS = {
    "ADDON_LOADED",
    "PLAYER_LOGIN",
    "PLAYER_ENTERING_WORLD",
    "PLAYER_LOGOUT",
    "AUCTION_HOUSE_SHOW",
    "AUCTION_HOUSE_CLOSED",
    "TRADE_SKILL_SHOW",
    "TRADE_SKILL_LIST_UPDATE",
    "TRADE_SKILL_CLOSE",
    "UPDATE_FACTION",
    "ITEM_SEARCH_RESULTS_UPDATED",
    "COMMODITY_SEARCH_RESULTS_UPDATED",
    "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED",
    "AUCTION_HOUSE_THROTTLED_MESSAGE_QUEUED",
    "AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED",
    "AUCTION_HOUSE_THROTTLED_MESSAGE_SENT",
    "AUCTION_HOUSE_THROTTLED_SYSTEM_READY",
    "COMMODITY_PRICE_UPDATED",
    "COMMODITY_PRICE_UNAVAILABLE",
    "COMMODITY_PURCHASE_FAILED",
    "COMMODITY_PURCHASE_SUCCEEDED",
    "AUCTION_HOUSE_PURCHASE_COMPLETED",
    "AUCTION_HOUSE_PURCHASE_FAILED",
    "AUCTION_HOUSE_AUCTION_CREATED",
    "AUCTION_HOUSE_NEW_BID_RECEIVED",
}

for _, eventName in ipairs(EVENTS) do
    SafeRegister(AHT.EventFrame, eventName)
end

function AHT:Print(message)
    local prefix = "|cff00ccff[WoW4E AH Trader]|r "
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(prefix .. tostring(message))
    elseif print then
        print("[WoW4E AH Trader] " .. tostring(message))
    end
end

function AHT:Now()
    if GetServerTime then
        return GetServerTime()
    end
    return time()
end

function AHT:FormatMoneyPlain(copper)
    if copper == nil then return "?" end
    copper = math.floor(copper)
    local negative = copper < 0
    if negative then copper = -copper end
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local bronze = copper % 100
    local value = ""
    if gold > 0 then value = value .. gold .. "g " end
    if silver > 0 or gold > 0 then value = value .. silver .. "s " end
    value = value .. bronze .. "c"
    if negative then value = "-" .. value end
    return value
end

function AHT:FormatMoney(copper)
    if copper == nil then return "|cffaaaaaa?|r" end
    copper = math.floor(copper)
    local negative = copper < 0
    if negative then copper = -copper end
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local bronze = copper % 100
    local value = ""
    if gold > 0 then value = value .. "|cffffd700" .. gold .. "g|r " end
    if silver > 0 or gold > 0 then value = value .. "|cffc7c7cf" .. silver .. "s|r " end
    value = value .. "|cffeda55f" .. bronze .. "c|r"
    if negative then value = "-" .. value end
    return value
end

function AHT:TableCount(value)
    local count = 0
    if type(value) ~= "table" then return count end
    for _ in pairs(value) do count = count + 1 end
    return count
end

function AHT:CallSafely(label, fn, ...)
    local ok, a, b, c, d = pcall(fn, ...)
    if not ok then
        self.State.lastError = label .. ": " .. tostring(a)
        self:Print("Fehler: " .. self.State.lastError)
        return false, a
    end
    return true, a, b, c, d
end

function AHT:Initialize()
    if self.Initialized then return end
    self.Initialized = true

    if self.Store then self.Store:Load() end
    if self.Capabilities then self.Capabilities:Probe() end
    if self.UI then self.UI:Create() end
    if self.Reputation then self.Reputation:Initialize() end

    self.State.status = "ready"
    self:Print(string.format(self.L and self.L.loaded or "%s geladen", self.VERSION))
    if self.Capabilities then
        self:Print(self.Capabilities:Summary())
    end
end

function AHT:OnEvent(eventName, ...)
    if eventName == "ADDON_LOADED" then
        local addonName = ...
        if addonName == self.ADDON_NAME then self:Initialize() end
        return
    end

    if eventName == "PLAYER_LOGIN" or eventName == "PLAYER_ENTERING_WORLD" then
        if not self.Initialized then self:Initialize() end
        return
    end

    if eventName == "PLAYER_LOGOUT" then
        if self.Store then self.Store:Save() end
        return
    end

    if eventName == "AUCTION_HOUSE_SHOW" then
        self.AHOpen = true
        self.State.status = "ah_open"
        if self.UI then self.UI:ShowAHButton() end
    elseif eventName == "AUCTION_HOUSE_CLOSED" then
        self.AHOpen = false
        self.State.status = "ah_closed"
        if self.AH then self.AH:Cancel("auction_house_closed") end
        if self.Buyer then self.Buyer:Cancel("auction_house_closed") end
        if self.Poster then self.Poster:Cancel("auction_house_closed") end
        if self.UI then self.UI:HideAHButton() end
    end

    if self.AH then self.AH:OnEvent(eventName, ...) end
    if self.Buyer then self.Buyer:OnEvent(eventName, ...) end
    if self.Poster then self.Poster:OnEvent(eventName, ...) end
    if self.Reputation then self.Reputation:OnEvent(eventName, ...) end

    if eventName == "TRADE_SKILL_SHOW" or eventName == "TRADE_SKILL_LIST_UPDATE" then
        if self.Recipes then self.Recipes:Refresh() end
    elseif eventName == "TRADE_SKILL_CLOSE" then
        self.State.status = self.AHOpen and "ah_open" or "ready"
    end
end

AHT.EventFrame:SetScript("OnEvent", function(_, eventName, ...)
    AHT:OnEvent(eventName, ...)
end)

AHT.EventFrame:SetScript("OnUpdate", function(_, elapsed)
    if AHT.AH and AHT.AH.OnUpdate then AHT.AH:OnUpdate(elapsed) end
end)

SLASH_WOW4E_AHT1 = "/aht"
SLASH_WOW4E_AHT2 = "/ahtrader"
SlashCmdList.WOW4E_AHT = function(message)
    local command, rest = (message or ""):match("^(%S*)%s*(.-)%s*$")
    command = string.lower(command or "")
    if command == "" or command == "show" then
        if AHT.UI then AHT.UI:Show() end
    elseif command == "scan" then
        if AHT.Scanner then AHT.Scanner:Start() end
    elseif command == "stop" or command == "cancel" then
        if AHT.Scanner then AHT.Scanner:Stop("user") end
        if AHT.Buyer then AHT.Buyer:Cancel("user") end
        if AHT.Poster then AHT.Poster:Cancel("user") end
        if AHT.AH then AHT.AH:Cancel("user") end
    elseif command == "recipes" then
        if AHT.Recipes then AHT.Recipes:Print() end
    elseif command == "mats" then
        if AHT.Mats then
            local subcommand, value = (rest or ""):match("^(%S*)%s*(.-)%s*$")
            if subcommand == "add" and value ~= "" then
                AHT.Mats:Add(value)
            elseif subcommand == "remove" and value ~= "" then
                AHT.Mats:Remove(value)
            else
                AHT.Mats:Print()
            end
        end
    elseif command == "transmute" then
        if AHT.Transmute then AHT.Transmute:Print() end
    elseif command == "ruf" or command == "rep" or command == "reputation" then
        if AHT.Reputation then AHT.Reputation:Print() end
    elseif command == "reset" then
        if AHT.Store then AHT.Store:ResetMarket() end
        AHT:Print(AHT.L and AHT.L.reset or "Marktdaten gelöscht.")
    elseif command == "debug" then
        if AHT.Diagnostics then AHT.Diagnostics:Print() end
    elseif command == "post" then
        AHT:Print(AHT.L and AHT.L.postHint or "Posten erfolgt über eine sichtbare Vorschau im Addon.")
    else
        AHT:Print("/aht | scan | stop | recipes | mats add <Item-Link> | mats remove <Item-Link> | transmute | ruf | reset | debug")
    end
end
