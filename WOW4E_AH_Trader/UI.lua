local AHT = WOW4E_AHT

AHT.UI = {
    rows = {},
    dialogs = {},
    viewMode = "recipes",
    lastMessage = "",
    searchQuery = "",
    profitOnly = false,
    marketFilter = "all",
    professionFilter = nil,
    opportunityDirection = "all",
    minimumOpportunityPercent = 0,
    showTransmutes = false,
    selectedResult = nil,
}

local function MakeBackdrop(frame)
    if frame.SetBackdrop then
        frame:SetBackdrop({
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
    end
    -- Use our own solid layer; Blizzard dialog background textures can carry
    -- alpha and BackdropTemplate is not available on every Forever frame.
    if not frame.ahtOpaqueBackground then
        frame.ahtOpaqueBackground = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    end
    frame.ahtOpaqueBackground:ClearAllPoints()
    frame.ahtOpaqueBackground:SetAllPoints(frame)
    frame.ahtOpaqueBackground:SetColorTexture(0, 0, 0, 1)
    if frame.SetAlpha then frame:SetAlpha(1) end
    if frame.SetBackdropBorderColor then frame:SetBackdropBorderColor(0.75, 0.48, 0.12, 0.95) end
end

local function MakeDialogMovable(dialog)
    dialog:SetMovable(true)
    dialog:EnableMouse(true)
    if dialog.SetClampedToScreen then dialog:SetClampedToScreen(true) end

    local dragHandle = CreateFrame("Frame", nil, dialog)
    dragHandle:SetPoint("TOPLEFT", 4, -4)
    dragHandle:SetPoint("TOPRIGHT", -4, -4)
    dragHandle:SetHeight(34)
    dragHandle:EnableMouse(true)
    dragHandle:RegisterForDrag("LeftButton")
    dragHandle:SetScript("OnDragStart", function()
        dialog:StartMoving()
    end)
    dragHandle:SetScript("OnDragStop", function()
        dialog:StopMovingOrSizing()
    end)
    dialog.dragHandle = dragHandle
end

local function Button(parent, name, text, width, height)
    local button = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    button:SetSize(width or 110, height or 24)
    button:SetText(text)
    return button
end

local function Label(parent, text, size)
    local font = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    font:SetText(text or "")
    if size then font:SetWidth(size) end
    font:SetJustifyH("LEFT")
    return font
end

local function DisableInput(box)
    if box.SetEnabled then box:SetEnabled(false)
    elseif box.Disable then box:Disable() end
end

local function ResultKey(result)
    if not result or result.kind == "info" then return nil end
    if result.recipeID then return "recipe:" .. tostring(result.recipeID) end
    if result.order then
        return "order:" .. tostring(result.order.createdAt or result.order.name or result.name)
    end
    local item = result.output or result
    if not item.itemID then return nil end
    local itemKey = item.itemKey and AHT:ItemKeyString(item.itemKey) or ""
    return table.concat({ tostring(result.kind or "item"), tostring(item.itemID), tostring(result.side or ""), itemKey }, ":")
end

local function PriceText(value)
    return value and AHT:FormatMoneyPlain(value) or AHT.L.noData
end

local function PercentText(value)
    return value ~= nil and string.format("%+.1f%%", value) or "-"
end

local function ScanAgeText(timestamp)
    local age = timestamp and math.max(0, (AHT:Now() or time()) - timestamp)
    if not age then return "noch nie" end
    if age < 60 then return "gerade eben" end
    if age < 3600 then return string.format("vor %d Min.", math.floor(age / 60)) end
    if age < 86400 then return string.format("vor %d Std.", math.floor(age / 3600)) end
    return string.format("vor %d Tg.", math.floor(age / 86400))
end

local RECIPE_COLUMNS = {
    { key = "name", label = "Rezept / Ergebnis", width = 230 },
    { key = "ingredientCost", label = "Kosten", width = 105 },
    { key = "salePrice", label = "Aktuell", width = 105 },
    { key = "profit", label = "Gewinn", width = 145 },
    { key = "margin", label = "Marge", width = 115 },
}

local MATERIAL_COLUMNS = {
    { key = "name", label = "Item", width = 220 },
    { key = "currentPrice", label = "Aktuell", width = 105 },
    { key = "marketValue", label = "Marktwert", width = 115 },
    { key = "marketTrendPercent", label = "Trend", width = 90 },
    { key = "updatedAt", label = "Gescannt", width = 170 },
}

local OPPORTUNITY_COLUMNS = {
    { key = "name", label = "Chance / Item", width = 220 },
    { key = "currentPrice", label = "Aktuell", width = 105 },
    { key = "marketValue", label = "Marktwert", width = 105 },
    { key = "discount", label = "Vorteil", width = 110 },
    { key = "profit", label = "Netto", width = 160 },
}

local ORDER_COLUMNS = {
    { key = "name", label = "Herstellungsauftrag", width = 260 },
    { key = "crafts", label = "Anzahl", width = 80 },
    { key = "statusText", label = "Status", width = 150 },
    { key = "remainingCount", label = "Offene Mats", width = 90 },
    { key = "spent", label = "Gekauft für", width = 120 },
}

local TABLE_WIDTH = 700
local ROW_HEIGHT = 23
local MAX_COLUMNS = 7

local function HeaderButton(parent, text, width)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, 24)
    button.bg = button:CreateTexture(nil, "BACKGROUND")
    button.bg:SetAllPoints()
    button.bg:SetColorTexture(0.18, 0.11, 0.035, 0.95)
    button.line = button:CreateTexture(nil, "BORDER")
    button.line:SetPoint("BOTTOMLEFT")
    button.line:SetPoint("BOTTOMRIGHT")
    button.line:SetHeight(1)
    button.line:SetColorTexture(0.85, 0.58, 0.18, 0.9)
    button.label = button:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    button.label:SetPoint("LEFT", 7, 0)
    button.label:SetPoint("RIGHT", -7, 0)
    button.label:SetJustifyH("LEFT")
    button.label:SetTextColor(1, 0.84, 0.35)
    button.label:SetText(text)
    button:SetScript("OnEnter", function()
        button.bg:SetColorTexture(0.3, 0.18, 0.05, 1)
    end)
    button:SetScript("OnLeave", function()
        button.bg:SetColorTexture(0.18, 0.11, 0.035, 0.95)
    end)
    return button
end

local VIEW_INFO = {
    recipes = {
        title = "Herstellen",
        help = "Aktuell = letzter AH-Scan; Marktwert = robuste Orientierung über mehrere Scans.",
    },
    transmute = {
        title = "Transmute",
        help = "Nur Rezepte, deren Berufsname als Transmutation erkannt wurde.",
    },
    materials = {
        title = "Markt",
        help = "Alle erfassten AH-Items. Aktuell = letzter Scan; Marktwert = robuste historische Orientierung.",
    },
    orders = {
        title = "Aufträge",
        help = "Reservierte Materialien und bereits gekaufte Zutaten je Herstellungsauftrag.",
    },
    opportunities = {
        title = "Chancen",
        help = "AH-Markt-Scan erfasst alle Browse-Items; Chancen entstehen aus aktuellem Preis und robuster Historie.",
    },
    reputation = {
        title = "Ruf",
        help = "Runenstoff-Spenden für die beobachtete Hauptstadtfraktion.",
    },
    diagnostics = {
        title = "Diagnose",
        help = "Laufzeit- und API-Informationen des Forever-Beta-Clients.",
    },
}

function AHT.UI:AddMessage(message)
    self.lastMessage = tostring(message or "")
    if self.status then self:RefreshStatus() end
end

function AHT.UI:SaveLayout()
    if not self.frame or not AHT.DB then return end
    AHT.DB.ui = AHT.DB.ui or {}
    local x, y = self.frame:GetCenter()
    local centerX, centerY = UIParent:GetCenter()
    if x and y and centerX and centerY then
        AHT.DB.ui.x = math.floor(x - centerX + 0.5)
        AHT.DB.ui.y = math.floor(y - centerY + 0.5)
    end
    AHT.DB.ui.width = math.floor(self.frame:GetWidth() or 780)
    AHT.DB.ui.height = math.floor(self.frame:GetHeight() or 600)
    AHT.DB.ui.viewMode = self.viewMode
    AHT.DB.ui.sortColumn = self.sortColumn
    AHT.DB.ui.sortAscending = self.sortAscending == true
    AHT.DB.ui.marketFilter = self.marketFilter or "all"
    AHT.DB.ui.professionFilter = self.professionFilter or "all"
    AHT.DB.ui.opportunityDirection = self.opportunityDirection or "all"
    AHT.DB.ui.minimumOpportunityPercent = self.minimumOpportunityPercent or 0
    if AHT.Store then AHT.Store:Save() end
end

function AHT.UI:UpdateNavigation()
    local primary = {
        recipes = self.recipeButton,
        materials = self.matsButton,
        opportunities = self.opportunityButton,
        orders = self.ordersButton,
    }
    for viewMode, button in pairs(primary) do
        if button and button.GetFontString then
            local font = button:GetFontString()
            if font then
                if self.viewMode == viewMode then
                    font:SetTextColor(1, 1, 0.35)
                else
                    font:SetTextColor(1, 0.82, 0.1)
                end
            end
        end
    end
    if self.moreButton and self.moreButton.GetFontString then
        local font = self.moreButton:GetFontString()
        if font then
            local active = self.viewMode == "reputation" or self.viewMode == "diagnostics"
            if active then font:SetTextColor(1, 1, 0.35) else font:SetTextColor(1, 0.82, 0.1) end
        end
    end
end

function AHT.UI:RefreshControls()
    local materials = self.viewMode == "materials"
    local recipes = self.viewMode == "recipes" or self.viewMode == "transmute"
    local opportunities = self.viewMode == "opportunities"
    local searchable = self.viewMode == "recipes"
        or self.viewMode == "transmute"
        or self.viewMode == "materials"
        or self.viewMode == "opportunities"
        or self.viewMode == "orders"
    if self.searchLabel then
        if searchable then self.searchLabel:Show() else self.searchLabel:Hide() end
    end
    if self.searchInput then
        if searchable then self.searchInput:Show() else self.searchInput:Hide() end
    end
    if self.filterButton then
        if searchable and self.viewMode ~= "orders" then self.filterButton:Show() else self.filterButton:Hide() end
        if materials then
            local labels = { all = "Alle Items", watched = "Beobachtet", inventory = "Tasche/Bank" }
            self.filterButton:SetText(labels[self.marketFilter] or labels.all)
        else
            self.filterButton:SetText(self.profitOnly and "Alle" or "Nur profitabel")
        end
    end
    if self.transmuteButton then
        if recipes then self.transmuteButton:Show() else self.transmuteButton:Hide() end
        self.transmuteButton:SetText(self.showTransmutes and "Alle Berufe" or "Transmute")
    end
    if self.professionButton then
        if recipes then self.professionButton:Show() else self.professionButton:Hide() end
        self.professionButton:SetText(self.professionFilter or "Alle Berufe")
    end
    if self.opportunityDirectionButton then
        if opportunities then self.opportunityDirectionButton:Show() else self.opportunityDirectionButton:Hide() end
        local labels = { all = "Alle Chancen", buy = "Nur Kauf", sell = "Nur Verkauf" }
        self.opportunityDirectionButton:SetText(labels[self.opportunityDirection] or labels.all)
    end
    if self.opportunityMinimumButton then
        if opportunities then self.opportunityMinimumButton:Show() else self.opportunityMinimumButton:Hide() end
        self.opportunityMinimumButton:SetText(string.format("Vorteil ≥ %d%%", self.minimumOpportunityPercent or 0))
    end
    if self.materialLabel then
        if materials then self.materialLabel:Show() else self.materialLabel:Hide() end
    end
    if self.materialInput then
        if materials then self.materialInput:Show() else self.materialInput:Hide() end
    end
    if self.materialAdd then
        if materials then self.materialAdd:Show() else self.materialAdd:Hide() end
    end
end

function AHT.UI:CycleProfessionFilter()
    local names, seen = {}, {}
    for _, recipe in ipairs(AHT.Recipes and AHT.Recipes:GetList() or {}) do
        local name = recipe.professionName
        if name and name ~= "" and not seen[name] then
            seen[name] = true
            table.insert(names, name)
        end
    end
    table.sort(names)
    local current = self.professionFilter
    local currentIndex = 0
    for index, name in ipairs(names) do
        if name == current then currentIndex = index break end
    end
    if #names == 0 or currentIndex >= #names then
        self.professionFilter = nil
    else
        self.professionFilter = names[currentIndex + 1]
    end
    if AHT.DB and AHT.DB.ui then AHT.DB.ui.professionFilter = self.professionFilter or "all" end
    self:RefreshControls()
    self:Refresh(true)
end

function AHT.UI:CycleOpportunityDirection()
    local nextDirection = { all = "buy", buy = "sell", sell = "all" }
    self.opportunityDirection = nextDirection[self.opportunityDirection] or "all"
    if AHT.DB and AHT.DB.ui then AHT.DB.ui.opportunityDirection = self.opportunityDirection end
    self:RefreshControls()
    self:Refresh(true)
end

function AHT.UI:CycleOpportunityMinimum()
    local steps = { 0, 10, 20, 30 }
    local nextValue = steps[1]
    for index, value in ipairs(steps) do
        if value == self.minimumOpportunityPercent then nextValue = steps[index + 1] or steps[1] break end
    end
    self.minimumOpportunityPercent = nextValue
    if AHT.DB and AHT.DB.ui then AHT.DB.ui.minimumOpportunityPercent = nextValue end
    self:RefreshControls()
    self:Refresh(true)
end

function AHT.UI:ShowDatabaseRecovery()
    if not self.databaseRecovery then
        local template = BackdropTemplateMixin and "BackdropTemplate" or nil
        local dialog = CreateFrame("Frame", nil, UIParent, template)
        dialog:SetSize(460, 220)
        dialog:SetPoint("CENTER")
        dialog:SetFrameStrata("DIALOG")
        dialog:SetFrameLevel(240)
        dialog:EnableMouse(true)
        if dialog.SetClampedToScreen then dialog:SetClampedToScreen(true) end
        MakeBackdrop(dialog)
        MakeDialogMovable(dialog)

        dialog.title = Label(dialog, "WoW4E AH Trader – Daten nicht geladen", 420)
        dialog.title:SetPoint("TOPLEFT", 16, -16)
        dialog.title:SetFontObject("GameFontHighlightLarge")
        dialog.title:SetTextColor(1, 0.84, 0.35)
        dialog.message = Label(dialog, "", 420)
        dialog.message:SetPoint("TOPLEFT", 16, -56)
        dialog.message:SetHeight(92)
        dialog.message:SetJustifyV("TOP")
        if dialog.message.SetWordWrap then dialog.message:SetWordWrap(true) end
        dialog.message:SetTextColor(0.9, 0.86, 0.75)

        dialog.retry = Button(dialog, nil, "Erneut laden", 118, 26)
        dialog.retry:SetPoint("BOTTOMLEFT", 16, 14)
        dialog.retry:SetScript("OnClick", function()
            if AHT:Initialize() then
                self:HideDatabaseRecovery()
                self:Show()
            else
                self:ShowDatabaseRecovery()
            end
        end)
        dialog.newDatabase = Button(dialog, nil, "Neue Datenbank", 132, 26)
        dialog.newDatabase:SetPoint("LEFT", dialog.retry, "RIGHT", 8, 0)
        dialog.newDatabase:SetScript("OnClick", function() AHT:InitializeNewDatabase() end)
        self.databaseRecovery = dialog
    end

    local missing = type(WOW4E_AHT_DB) ~= "table"
    local canCreate = missing and not (AHT.Store and AHT.Store.canonicalDB) and type(AHT.DB) ~= "table"
    local message
    if canCreate then
        message = "Die SavedVariables-Datenbank ist nicht verfügbar. Wenn du bereits Daten hattest: Lege keine neue Datenbank an. Prüfe nach beendetem Spiel die Sicherung; beim nächsten Login kannst du erneut laden."
    elseif missing then
        message = "Die globale SavedVariables-Referenz fehlt, aber AHT hält die zuvor geladene Tabelle noch im Speicher. Lade erneut, damit diese Referenz wiederhergestellt wird."
    else
        message = "Die gespeicherten Daten konnten nicht geladen werden. Bitte zuerst erneut laden. Eine neue Datenbank wird nur angeboten, wenn keine SavedVariables-Tabelle vorhanden ist."
    end
    self.databaseRecovery.message:SetText(message)
    if canCreate then self.databaseRecovery.newDatabase:Show() else self.databaseRecovery.newDatabase:Hide() end
    self.databaseRecovery:Show()
    if self.databaseRecovery.Raise then self.databaseRecovery:Raise() end
end

function AHT.UI:HideDatabaseRecovery()
    if self.databaseRecovery then self.databaseRecovery:Hide() end
end

function AHT.UI:SetView(viewMode)
    if viewMode == "transmute" then
        self.showTransmutes = true
        viewMode = "recipes"
    elseif viewMode == "recipes" then
        self.showTransmutes = false
    end
    if not AHT.Initialized and AHT.Initialize then AHT:Initialize() end
    if not AHT.Initialized then
        self:ShowDatabaseRecovery()
        return false
    end
    self.viewMode = VIEW_INFO[viewMode] and viewMode or "recipes"
    self.lastMessage = ""
    self.selectedResult = nil
    if not self.frame then self:Create() end
    if self.moreMenu then self.moreMenu:Hide() end
    if self.scanMenu then self.scanMenu:Hide() end
    self:RefreshControls()
    self:UpdateNavigation()
    self:RefreshDetail()
    if AHT.DB and AHT.DB.ui then AHT.DB.ui.viewMode = self.viewMode end
    self:Refresh()
    self:SaveLayout()
    self.frame:Show()
end

function AHT.UI:Create()
    if self.frame then return end
    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    self.frame = CreateFrame("Frame", "WOW4E_AH_Trader_MainFrame", UIParent, template)
    local ui = AHT.DB and AHT.DB.ui or {}
    self.viewMode = VIEW_INFO[ui.viewMode] and ui.viewMode or self.viewMode
    self.sortColumn = ui.sortColumn
    self.sortAscending = ui.sortAscending ~= false
    self.marketFilter = ui.marketFilter or self.marketFilter or "all"
    self.professionFilter = ui.professionFilter and ui.professionFilter ~= "all" and ui.professionFilter or nil
    self.opportunityDirection = ui.opportunityDirection or "all"
    self.minimumOpportunityPercent = tonumber(ui.minimumOpportunityPercent) or 0
    self.frame:SetSize(tonumber(ui.width) or 780, tonumber(ui.height) or 600)
    self.frame:SetPoint("CENTER", UIParent, "CENTER", tonumber(ui.x) or 0, tonumber(ui.y) or 0)
    self.frame:SetFrameStrata("DIALOG")
    self.frame:SetMovable(true)
    self.frame:EnableMouse(true)
    self.frame:RegisterForDrag("LeftButton")
    self.frame:SetScript("OnDragStart", self.frame.StartMoving)
    self.frame:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        self:SaveLayout()
    end)
    if self.frame.SetResizable and self.frame.StartSizing then
        self.frame:SetResizable(true)
        if self.frame.SetResizeBounds then
            self.frame:SetResizeBounds(780, 500, 1100, 850)
        end
        self.resizeGrip = CreateFrame("Button", nil, self.frame)
        self.resizeGrip:SetSize(16, 16)
        self.resizeGrip:SetPoint("BOTTOMRIGHT", -4, 4)
        local gripTexture = self.resizeGrip:CreateTexture(nil, "ARTWORK")
        gripTexture:SetAllPoints()
        gripTexture:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
        self.resizeGrip:SetScript("OnMouseDown", function()
            self.frame:StartSizing("BOTTOMRIGHT")
        end)
        self.resizeGrip:SetScript("OnMouseUp", function()
            self.frame:StopMovingOrSizing()
            self:SaveLayout()
        end)
    end
    MakeBackdrop(self.frame)
    self.frame:Hide()

    if ui.viewMode == "transmute" then
        self.viewMode = "recipes"
        self.showTransmutes = true
    end

    self.title = Label(self.frame, "WoW4E AH Trader  |  Marktübersicht", 560)
    self.title:SetPoint("TOPLEFT", 18, -16)
    self.title:SetFontObject("GameFontHighlightLarge")
    self.title:SetTextColor(1, 0.84, 0.35)

    self.close = Button(self.frame, nil, CLOSE or "Close", 70, 22)
    self.close:SetPoint("TOPRIGHT", -14, -12)
    self.close:SetScript("OnClick", function()
        self:HideRecipeContext()
        if self.moreMenu then self.moreMenu:Hide() end
        if self.actionDialog then self.actionDialog:Hide() end
        if self.buyDialog then self.buyDialog:Hide() end
        if self.postDialog then self.postDialog:Hide() end
        self.frame:Hide()
    end)

    self.status = Label(self.frame, "", 720)
    self.status:SetPoint("TOPLEFT", 18, -46)
    self.status:SetTextColor(0.95, 0.82, 0.35)

    self.viewTitle = Label(self.frame, "", 720)
    self.viewTitle:SetPoint("TOPLEFT", 18, -134)
    self.viewTitle:SetFontObject("GameFontHighlight")
    self.viewTitle:SetTextColor(0.95, 0.78, 0.28)

    self.viewHelp = Label(self.frame, "", 720)
    self.viewHelp:SetPoint("TOPLEFT", 18, -151)
    self.viewHelp:SetTextColor(0.72, 0.68, 0.58)

    self.recipeButton = Button(self.frame, nil, "Herstellen", 112, 24)
    self.recipeButton:SetPoint("TOPLEFT", 18, -70)
    self.recipeButton:SetScript("OnClick", function() self:SetView("recipes") end)

    self.matsButton = Button(self.frame, nil, "Markt", 88, 24)
    self.matsButton:SetPoint("LEFT", self.recipeButton, "RIGHT", 8, 0)
    self.matsButton:SetScript("OnClick", function() self:SetView("materials") end)

    self.opportunityButton = Button(self.frame, nil, "Chancen", 88, 24)
    self.opportunityButton:SetPoint("LEFT", self.matsButton, "RIGHT", 8, 0)
    self.opportunityButton:SetScript("OnClick", function() self:SetView("opportunities") end)

    self.ordersButton = Button(self.frame, nil, "Aufträge", 92, 24)
    self.ordersButton:SetPoint("LEFT", self.opportunityButton, "RIGHT", 8, 0)
    self.ordersButton:SetScript("OnClick", function() self:SetView("orders") end)

    self.moreButton = Button(self.frame, nil, "Mehr", 70, 24)
    self.moreButton:SetPoint("LEFT", self.ordersButton, "RIGHT", 8, 0)

    self.scanButton = Button(self.frame, nil, "Scannen ▾", 120, 24)
    self.scanButton:SetPoint("TOPRIGHT", -18, -70)
    self.scanButton:SetScript("OnClick", function()
        if AHT.Scanner.running or AHT.Scanner.marketDiscovery then
            AHT.Scanner:Stop("user")
            if self.scanMenu then self.scanMenu:Hide() end
        else
            if self.scanMenu:IsShown() then self.scanMenu:Hide() else self.scanMenu:Show() end
        end
        self:RefreshStatus()
    end)

    self.scanMenu = CreateFrame("Frame", nil, self.frame, template)
    self.scanMenu:SetSize(190, 112)
    self.scanMenu:SetPoint("TOPRIGHT", self.scanButton, "BOTTOMRIGHT", 0, -4)
    self.scanMenu:SetFrameStrata("TOOLTIP")
    MakeBackdrop(self.scanMenu)
    local function AddScanOption(label, y, callback)
        local option = Button(self.scanMenu, nil, label, 164, 26)
        option:SetPoint("TOPLEFT", 12, y)
        option:SetScript("OnClick", function()
            self.scanMenu:Hide()
            callback()
            self:RefreshStatus()
        end)
    end
    AddScanOption("Bekannte Items", -9, function() AHT.Scanner:Start(nil, "known") end)
    AddScanOption("Ganzer AH-Markt", -41, function() AHT.Scanner:StartMarketDiscovery() end)
    AddScanOption("Ausgewähltes Item", -73, function()
        local result = self.selectedResult
        local item = result and (result.output or result)
        if item and item.itemID then
            AHT.Scanner:Start({ { itemID = item.itemID, itemKey = item.itemKey, name = item.name, kind = item.kind } }, "selected")
        else
            AHT:Print("Wähle zuerst ein Item in der Liste aus.")
        end
    end)

    self.transmuteButton = Button(self.frame, nil, "Transmute", 105, 24)
    self.transmuteButton:SetPoint("TOPLEFT", 360, -99)
    self.transmuteButton:SetScript("OnClick", function()
        self.showTransmutes = not self.showTransmutes
        self:RefreshControls()
        self:Refresh()
    end)

    self.professionButton = Button(self.frame, nil, "Alle Berufe", 132, 24)
    self.professionButton:SetPoint("TOPLEFT", 474, -99)
    self.professionButton:SetScript("OnClick", function() self:CycleProfessionFilter() end)

    self.opportunityDirectionButton = Button(self.frame, nil, "Alle Chancen", 122, 24)
    self.opportunityDirectionButton:SetPoint("TOPLEFT", 360, -99)
    self.opportunityDirectionButton:SetScript("OnClick", function() self:CycleOpportunityDirection() end)
    self.opportunityMinimumButton = Button(self.frame, nil, "Vorteil ≥ 0%", 124, 24)
    self.opportunityMinimumButton:SetPoint("TOPLEFT", 490, -99)
    self.opportunityMinimumButton:SetScript("OnClick", function() self:CycleOpportunityMinimum() end)

    self.moreMenu = CreateFrame("Frame", nil, self.frame, template)
    self.moreMenu:SetSize(156, 74)
    self.moreMenu:SetPoint("TOPLEFT", self.moreButton, "BOTTOMLEFT", 0, -4)
    self.moreMenu:SetFrameStrata("TOOLTIP")
    MakeBackdrop(self.moreMenu)
    self.moreMenu:Hide()
    local moreReputation = Button(self.moreMenu, nil, "Ruf", 130, 24)
    moreReputation:SetPoint("TOPLEFT", 12, -10)
    moreReputation:SetScript("OnClick", function()
        self.moreMenu:Hide()
        self:SetView("reputation")
    end)
    local moreDiagnostics = Button(self.moreMenu, nil, "Diagnose", 130, 24)
    moreDiagnostics:SetPoint("TOPLEFT", 12, -40)
    moreDiagnostics:SetScript("OnClick", function()
        self.moreMenu:Hide()
        self:SetView("diagnostics")
    end)
    self.moreButton:SetScript("OnClick", function()
        if self.moreMenu:IsShown() then self.moreMenu:Hide() else self.moreMenu:Show() end
    end)

    self.searchInput = CreateFrame("EditBox", nil, self.frame, "InputBoxTemplate")
    self.searchInput:SetSize(168, 24)
    self.searchInput:SetPoint("TOPLEFT", 70, -101)
    self.searchInput:SetAutoFocus(false)
    self.searchInput:SetTextInsets(6, 6, 0, 0)
    self.searchInput:SetScript("OnTextChanged", function(box)
        self.searchQuery = string.lower(box:GetText() or "")
        if self.frame and self.frame:IsShown() then self:Refresh(true) end
    end)
    self.searchInput:SetScript("OnEscapePressed", function(box)
        box:SetText("")
        box:ClearFocus()
    end)
    self.searchInput:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
    self.searchInput:SetText("")

    self.searchLabel = Label(self.frame, "Suchen:", 48)
    self.searchLabel:SetPoint("TOPLEFT", 18, -106)
    self.searchLabel:SetTextColor(0.82, 0.75, 0.58)

    self.filterButton = Button(self.frame, nil, "Nur profitabel", 105, 24)
    self.filterButton:SetPoint("LEFT", self.searchInput, "RIGHT", 8, 0)
    self.filterButton:SetScript("OnClick", function()
        if self.viewMode == "materials" then
            local nextFilter = { all = "watched", watched = "inventory", inventory = "all" }
            self.marketFilter = nextFilter[self.marketFilter] or "all"
            if AHT.DB and AHT.DB.ui then AHT.DB.ui.marketFilter = self.marketFilter end
        else
            self.profitOnly = not self.profitOnly
        end
        self:RefreshControls()
        self:Refresh(true)
    end)

    self.materialInput = CreateFrame("EditBox", nil, self.frame, "InputBoxTemplate")
    self.materialInput:SetSize(190, 24)
    self.materialInput:SetPoint("TOPLEFT", 430, -101)
    self.materialInput:SetAutoFocus(false)
    self.materialInput:SetTextInsets(6, 6, 0, 0)
    local function AddMaterialFromInput(box)
        local value = box:GetText()
        if value ~= "" and AHT.Mats:Add(value) then box:SetText("") end
    end
    self.materialInput:SetScript("OnEnterPressed", function(box)
        AddMaterialFromInput(box)
    end)
    self.materialInput:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)

    self.materialAdd = Button(self.frame, nil, "+ Mat", 75, 24)
    self.materialAdd:SetPoint("LEFT", self.materialInput, "RIGHT", 8, 0)
    self.materialAdd:SetScript("OnClick", function()
        AddMaterialFromInput(self.materialInput)
    end)

    self.materialLabel = Label(self.frame, "Material:", 62)
    self.materialLabel:SetPoint("TOPLEFT", 360, -106)
    self.materialLabel:SetTextColor(0.82, 0.75, 0.58)

    self.tableHeader = CreateFrame("Frame", nil, self.frame)
    self.tableHeader:SetSize(TABLE_WIDTH, 24)
    self.tableHeader:SetPoint("TOPLEFT", 18, -174)
    self.headers = {}
    local offset = 0
    for index = 1, MAX_COLUMNS do
        local headerIndex = index
        local header = HeaderButton(self.tableHeader, "", 100)
        header:SetPoint("LEFT", offset, 0)
        header:SetScript("OnClick", function()
            local columns = self:GetActiveColumns()
            if columns[headerIndex] then self:SetSort(columns[headerIndex].key) end
        end)
        self.headers[index] = header
        offset = offset + 100
    end

    local scrollTemplate = "UIPanelScrollFrameTemplate"
    self.scroll = CreateFrame("ScrollFrame", nil, self.frame, scrollTemplate)
    self.scroll:SetPoint("TOPLEFT", 18, -202)
    self.scroll:SetPoint("BOTTOMRIGHT", -34, 140)
    self.content = CreateFrame("Frame", nil, self.scroll)
    self.content:SetSize(TABLE_WIDTH, 420)
    self.scroll:SetScrollChild(self.content)

    self.detailPanel = CreateFrame("Frame", nil, self.frame, template)
    self.detailPanel:SetPoint("BOTTOMLEFT", 18, 10)
    self.detailPanel:SetPoint("BOTTOMRIGHT", -34, 10)
    self.detailPanel:SetHeight(118)
    self.detailPanel:SetFrameLevel(self.frame:GetFrameLevel() + 2)
    MakeBackdrop(self.detailPanel)
    self.detailTitle = Label(self.detailPanel, "Auswahl", 450)
    self.detailTitle:SetPoint("TOPLEFT", 10, -7)
    self.detailTitle:SetFontObject("GameFontHighlight")
    self.detailTitle:SetTextColor(1, 0.84, 0.35)
    self.detailSummary = Label(self.detailPanel, "Klicke ein Item für Preis, Verlauf, Zutaten und Bestand.", 450)
    self.detailSummary:SetPoint("TOPLEFT", 10, -28)
    self.detailSummary:SetHeight(82)
    self.detailSummary:SetJustifyV("TOP")
    if self.detailSummary.SetWordWrap then self.detailSummary:SetWordWrap(true) end
    self.detailSummary:SetTextColor(0.85, 0.82, 0.74)
    self.detailAction = Button(self.detailPanel, nil, "Kaufplan", 118, 25)
    self.detailAction:SetPoint("RIGHT", -130, 0)
    self.detailAction:SetScript("OnClick", function()
        local result = self.selectedResult
        if not result then return end
        if result.kind == "order" then self:ShowOrderActions(result.order)
        elseif result.kind == "opportunity" then self:ShowOpportunityActions(result)
        elseif result.kind == "material" then self:ShowMaterialActions(result)
        elseif result.output then self:ShowRecipeActions(result) end
    end)
    self.detailSearch = Button(self.detailPanel, nil, "Im AH suchen", 112, 25)
    self.detailSearch:SetPoint("RIGHT", -10, 0)
    self.detailSearch:SetScript("OnClick", function()
        if self.selectedResult then self:OpenResultInAuctionHouse(self.selectedResult) end
    end)

    self:CreateRows()
    self:RefreshControls()
    self:UpdateNavigation()
    self:Refresh()
end

function AHT.UI:CreateRow(index)
    local row = CreateFrame("Button", nil, self.content)
    local rowIndex = index
    row.rowIndex = rowIndex
    row:SetSize(TABLE_WIDTH, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -((rowIndex - 1) * ROW_HEIGHT))
    row:EnableMouse(true)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(rowIndex % 2 == 0 and 0.045 or 0.065, 0.032, 0.018, 0.82)
    row.info = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.info:SetPoint("LEFT", 8, 0)
    row.info:SetWidth(TABLE_WIDTH - 16)
    row.info:SetJustifyH("LEFT")
    row.cells = {}
    for cellIndex = 1, MAX_COLUMNS do
        local text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.cells[cellIndex] = text
    end
    row:SetScript("OnClick", function(_, button)
        if button == "LeftButton" and type(IsControlKeyDown) == "function" and IsControlKeyDown() then
            if row.result and row.result.output and #(row.result.reagents or {}) > 0 then
                self:OpenRecipeInAuctionHouse(row.result)
            end
            return
        end
        if button == "LeftButton" and type(IsShiftKeyDown) == "function" and IsShiftKeyDown() then
            if row.result and row.result.kind ~= "info" and row.result.kind ~= "order" then
                self:OpenResultInAuctionHouse(row.result)
            end
            return
        end
        self:SelectResult(row.result)
    end)
    row:SetScript("OnEnter", function()
        if row.result then
            row.bg:SetColorTexture(0.2, 0.2, 0.05, 0.75)
            if row.result.kind == "material" then
                self:ShowMaterialContext(row.result, row)
            elseif row.result.kind == "opportunity" then
                self:ShowOpportunityContext(row.result, row)
            elseif row.result.kind ~= "info" and row.result.kind ~= "order" then
                self:ShowRecipeContext(row.result, row)
            end
        end
    end)
    row:SetScript("OnLeave", function()
        local selected = self.selectedKey and ResultKey(row.result) == self.selectedKey
        row.bg:SetColorTexture(selected and 0.22 or (rowIndex % 2 == 0 and 0.045 or 0.065), selected and 0.13 or 0.032, selected and 0.035 or 0.018, 1)
        if self.recipeTooltipOwner == row then self:HideRecipeContext() end
    end)
    self.rows[index] = row
end

function AHT.UI:OpenResultInAuctionHouse(result)
    if not result or not AHT.AH or not AHT.AH.OpenItemInAuctionHouse then return false end
    local item = result.output and result.output.itemID and result.output or result
    local itemID = tonumber(item.itemID)
    if not itemID then
        AHT:Print("Dieses Ergebnis hat keine Item-ID für die AH-Suche.")
        return false
    end

    local name = item.name or AHT:GetItemInfo(itemID) or result.name or tostring(itemID)
    local ok, reason = AHT.AH:OpenItemInAuctionHouse({
        itemID = itemID,
        itemKey = result.itemKey,
        name = name,
    })
    if not ok then
        if reason == "auction_house_closed" then
            AHT:Print("Bitte zuerst das Auktionshaus öffnen.")
        else
            AHT:Print("AH-Suche konnte nicht geöffnet werden: " .. tostring(reason or "unbekannt"))
        end
        return false
    end

    self:HideRecipeContext()
    if self.actionDialog then self.actionDialog:Hide() end
    if self.buyDialog then self.buyDialog:Hide() end
    if self.postDialog then self.postDialog:Hide() end
    -- Keep the trader window open as requested, but place it below the AH so
    -- the Blizzard result list remains visible after navigation.
    self:LowerForAuctionHouse()
    return true
end

function AHT.UI:LowerForAuctionHouse()
    if not self.frame then return end
    self.frame:SetFrameStrata("MEDIUM")
    if self.frame.SetFrameLevel then self.frame:SetFrameLevel(1) end
    self.frame:Show()
end

function AHT.UI:RestoreFrameStrata()
    if not self.frame then return end
    self.frame:SetFrameStrata("DIALOG")
end

function AHT.UI:CreateAHRecipePanel()
    if self.ahRecipePanel then return end
    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    local panel = CreateFrame("Frame", nil, UIParent, template)
    panel:SetSize(900, 620)
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    panel:SetFrameStrata("DIALOG")
    panel:SetFrameLevel(220)
    if panel.SetToplevel then panel:SetToplevel(true) end
    panel:EnableMouse(true)
    if panel.SetClampedToScreen then panel:SetClampedToScreen(true) end
    MakeBackdrop(panel)
    MakeDialogMovable(panel)
    self.ahRecipePanel = panel

    panel.title = Label(panel, "AHT Rezept- und Materialansicht", 620)
    panel.title:SetPoint("TOPLEFT", 16, -14)
    panel.title:SetFontObject("GameFontHighlightLarge")
    panel.title:SetTextColor(1, 0.84, 0.35)

    panel.craftLabel = Label(panel, "Herstellvorgänge:", 120)
    panel.craftLabel:SetPoint("TOPLEFT", 16, -50)
    panel.craftInput = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    panel.craftInput:SetSize(64, 24)
    panel.craftInput:SetPoint("LEFT", panel.craftLabel, "RIGHT", 8, 0)
    panel.craftInput:SetAutoFocus(false)
    panel.craftInput:SetNumeric(true)
    panel.craftInput:SetText("1")
    panel.craftInput:SetScript("OnTextChanged", function(box)
        if self.ahRecipeUpdating then return end
        self.ahCraftCrafts = math.max(1, tonumber(box:GetText()) or 1)
        self:RecalculateAHRecipeEntries()
        self:RenderAHRecipePanel()
    end)

    panel.refresh = Button(panel, nil, "Listings aktualisieren", 140, 24)
    panel.refresh:SetPoint("LEFT", panel.craftInput, "RIGHT", 12, 0)
    panel.refresh:SetScript("OnClick", function()
        if self.ahCraftRecipe then self:StartAHRecipeListingScan(self.ahCraftRecipe) end
    end)

    panel.close = Button(panel, nil, CLOSE or "Close", 80, 24)
    panel.close:SetPoint("TOPRIGHT", -14, -12)
    -- The movable title drag handle is created before this button and covers
    -- the same title-bar area. Keep the close button explicitly above it so
    -- the click reaches the button on Forever's frame-stack implementation.
    panel.close:SetFrameLevel((panel:GetFrameLevel() or 0) + 10)
    panel.close:EnableMouse(true)
    panel.close:SetScript("OnClick", function()
        self:HideAHRecipePanel()
        if self.ahRecipeTab then self.ahRecipeTab:Hide() end
        self:Show()
    end)

    panel.summary = Label(panel, "", 720)
    panel.summary:SetPoint("TOPLEFT", 16, -82)
    panel.summary:SetTextColor(0.82, 0.75, 0.58)

    panel.status = Label(panel, "", 720)
    panel.status:SetPoint("TOPLEFT", 16, -104)
    panel.status:SetTextColor(0.55, 0.82, 0.95)

    panel.scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    panel.scroll:SetPoint("TOPLEFT", 16, -128)
    panel.scroll:SetPoint("BOTTOMRIGHT", -34, 14)
    panel.content = CreateFrame("Frame", nil, panel.scroll)
    panel.content:SetSize(700, 420)
    panel.scroll:SetScrollChild(panel.content)
    panel.rows = {}
    panel:Hide()
end

function AHT.UI:CreateAHRecipeRow(index)
    local panel = self.ahRecipePanel
    local row = CreateFrame("Frame", nil, panel.content)
    row:SetHeight(76)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(index % 2 == 0 and 0.07 or 0.095, 0.045, 0.02, 1)
    row.title = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.title:SetPoint("TOPLEFT", 10, -8)
    row.title:SetPoint("TOPRIGHT", -140, -8)
    row.title:SetJustifyH("LEFT")
    row.details = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.details:SetPoint("TOPLEFT", 10, -28)
    row.details:SetPoint("TOPRIGHT", -140, -28)
    row.details:SetJustifyH("LEFT")
    row.listings = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.listings:SetPoint("TOPLEFT", 10, -48)
    row.listings:SetPoint("TOPRIGHT", -140, -48)
    row.listings:SetJustifyH("LEFT")
    row.buy = Button(row, nil, "Kaufen", 112, 25)
    row.buy:SetPoint("TOPRIGHT", -12, -10)
    row.buy:SetScript("OnClick", function()
        if row.entry then self:BuyAHRecipeMaterial(row.entry) end
    end)
    panel.rows[index] = row
    return row
end

local function AHRecipeListingText(entry)
    if entry.loading then return "Listings werden geladen …" end
    if not entry.loaded then return "Listings noch nicht geladen." end
    if entry.error then return "Listing-Suche fehlgeschlagen: " .. tostring(entry.error) end
    if not entry.results or #entry.results == 0 then return "Keine aktuellen Listings." end
    local parts = {}
    for index = 1, math.min(#entry.results, 8) do
        local listing = entry.results[index]
        table.insert(parts, string.format(
            "%dx %s",
            tonumber(listing.quantity) or 0,
            AHT:FormatMoneyPlain(listing.unitPrice or 0)
        ))
    end
    if #entry.results > 8 then table.insert(parts, "…") end
    return "Listings: " .. table.concat(parts, " | ")
end

function AHT.UI:RecalculateAHRecipeEntries()
    local crafts = math.max(1, tonumber(self.ahCraftCrafts) or 1)
    for _, entry in ipairs(self.ahCraftMaterials or {}) do
        local counts = AHT.Inventory and AHT.Inventory:GetCount(entry.itemID) or { bags = 0, bank = 0, total = 0, bankKnown = false }
        entry.required = (tonumber(entry.quantityPerCraft) or 1) * crafts
        entry.bags = counts.bags or 0
        entry.bank = counts.bank or 0
        entry.bankKnown = counts.bankKnown
        entry.owned = counts.total or 0
        entry.toBuy = math.max(0, entry.required - entry.owned - (entry.purchasedQuantity or 0))
        entry.plan = nil
        entry.estimated = nil
        if entry.loaded and entry.results and entry.toBuy > 0 and AHT.Buyer then
            entry.cheapest = entry.results[1] and entry.results[1].unitPrice or nil
            if entry.cheapest and entry.cheapest > 0 then
                entry.plan = AHT.Buyer:BuildPlan(entry.results, entry.toBuy, entry.cheapest)
                entry.estimated = entry.plan.total
            end
        end
    end
end

function AHT.UI:RenderAHRecipePanel()
    local panel = self.ahRecipePanel
    local recipe = self.ahCraftRecipe
    if not panel or not recipe then return end
    local crafts = math.max(1, tonumber(self.ahCraftCrafts) or 1)
    local output = self.ahCraftOutput
    panel.title:SetText("AHT Rezept: " .. tostring(recipe.name or "Herstellung"))
    panel.summary:SetText(string.format(
        "%dx Herstellung | Ergebnis: %dx %s",
        crafts,
        tonumber(output and output.quantity) or 1,
        tostring(output and output.name or "?")
    ))

    local width = math.max(500, (panel:GetWidth() or 760) - 52)
    panel.content:SetWidth(width)
    local offset = 0
    local function AddHeading(slot, text)
        local heading = panel[slot]
        if not heading then
            heading = panel.content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            heading:SetWidth(width - 20)
            heading:SetJustifyH("LEFT")
            heading:SetTextColor(1, 0.84, 0.35)
            panel[slot] = heading
        end
        heading:ClearAllPoints()
        heading:SetPoint("TOPLEFT", 10, -offset - 2)
        heading:SetText(text)
        offset = offset + 24
    end

    AddHeading("outputHeading", "Ergebnis-Listings")
    local outputEntry = self.ahCraftOutput
    local outputRow = self.ahRecipeOutputRow
    if not outputRow then
        outputRow = CreateFrame("Frame", nil, panel.content)
        outputRow.bg = outputRow:CreateTexture(nil, "BACKGROUND")
        outputRow.bg:SetAllPoints()
        outputRow.bg:SetColorTexture(0.055, 0.07, 0.09, 1)
        outputRow.title = outputRow:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        outputRow.title:SetPoint("TOPLEFT", 10, -8)
        outputRow.title:SetWidth(width - 20)
        outputRow.details = outputRow:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        outputRow.details:SetPoint("TOPLEFT", 10, -30)
        outputRow.details:SetWidth(width - 20)
        outputRow.listings = outputRow:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        outputRow.listings:SetPoint("TOPLEFT", 10, -50)
        outputRow.listings:SetWidth(width - 20)
        self.ahRecipeOutputRow = outputRow
    end
    outputRow:SetPoint("TOPLEFT", 0, -offset)
    outputRow:SetSize(width, 72)
    outputRow.title:SetText(tostring(outputEntry and outputEntry.name or "?"))
    outputRow.details:SetText(outputEntry and outputEntry.loaded and
        string.format("Aktuell: %s | Gesamtmenge im AH: %d", outputEntry.results[1] and AHT:FormatMoneyPlain(outputEntry.results[1].unitPrice or 0) or "?", outputEntry.meta and outputEntry.meta.totalQuantity or 0) or
        "Suche aktuelle Listings …")
    outputRow.listings:SetText(AHRecipeListingText(outputEntry or {}))
    outputRow:Show()
    offset = offset + 80

    AddHeading("materialHeading", "Benötigte Materialien und Kaufoptionen")
    for index, entry in ipairs(self.ahCraftMaterials or {}) do
        local row = panel.rows[index] or self:CreateAHRecipeRow(index)
        row.entry = entry
        row:SetPoint("TOPLEFT", 0, -offset)
        row:SetWidth(width)
        row.title:SetText(string.format(
            "%s | benötigt: %d | Bestand: %d | zu kaufen: %d",
            tostring(entry.name or entry.itemID),
            entry.required or 0,
            entry.owned or 0,
            entry.toBuy or 0
        ))
        local bankText = entry.bankKnown and tostring(entry.bank or 0) or "?"
        local estimate = entry.estimated and AHT:FormatMoneyPlain(entry.estimated) or "?"
        row.details:SetText(string.format(
            "pro Herstellung: %d | Tasche: %d | Bank: %s | geschätzt: %s",
            entry.quantityPerCraft or 1, entry.bags or 0, bankText, estimate
        ))
        row.listings:SetText(AHRecipeListingText(entry))
        if entry.error then
            row.details:SetText(row.details:GetText() .. "\nFehler: " .. tostring(entry.error))
        end
        if not AHT.AHOpen then
            row.buy:SetText("AH geschlossen")
            row.buy:Disable()
        elseif entry.buyState == "confirm" then
            row.buy:SetText("Preis bestätigen")
            row.buy:Enable()
        elseif entry.buyState == "ready" then
            row.buy:SetText("Kauf auslösen")
            row.buy:Enable()
        elseif entry.buyState == "checking" then
            row.buy:SetText("Preisprüfung …")
            row.buy:Disable()
        elseif entry.buyState == "error" then
            row.buy:SetText("Erneut prüfen")
            row.buy:Enable()
        elseif entry.buyState == "buying" or entry.buyState == "submitted" then
            row.buy:SetText("Kauf läuft …")
            row.buy:Disable()
        elseif entry.buyState == "done" or (entry.toBuy or 0) <= 0 then
            row.buy:SetText("Bestand reicht")
            row.buy:Disable()
        elseif not entry.loaded then
            row.buy:SetText("Lade …")
            row.buy:Disable()
        elseif not entry.plan or entry.plan.missing > 0 then
            row.buy:SetText("Nicht genug")
            row.buy:Disable()
        else
            row.buy:SetText("Kaufen")
            row.buy:Enable()
        end
        row:Show()
        offset = offset + 82
    end
    for index = #(self.ahCraftMaterials or {}) + 1, #panel.rows do panel.rows[index]:Hide() end
    panel.content:SetHeight(math.max(300, offset + 12))
    panel.status:SetText(self.ahRecipeStatus or "")
end

function AHT.UI:StartAHRecipeListingScan(recipe)
    if not AHT.AHOpen then
        self.ahRecipeStatus = "Das Auktionshaus muss geöffnet sein."
        self:RenderAHRecipePanel()
        return false
    end
    local panel = self.ahRecipePanel
    if not panel then return false end
    self.ahRecipeSearchSerial = (self.ahRecipeSearchSerial or 0) + 1
    local serial = self.ahRecipeSearchSerial
    self.ahCraftCrafts = math.max(1, tonumber(self.ahCraftCrafts) or 1)
    self.ahCraftOutput = {
        kind = "output",
        itemID = recipe.output.itemID,
        itemKey = recipe.output.itemKey,
        name = recipe.output.name or AHT:GetItemInfo(recipe.output.itemID),
        quantity = recipe.output.quantity or 1,
        loaded = false,
    }
    local materials, byItemID = {}, {}
    for _, reagent in ipairs(recipe.reagents or {}) do
        local itemID = tonumber(reagent.itemID)
        if itemID then
            local entry = byItemID[itemID]
            if not entry then
                entry = {
                    kind = "material",
                    itemID = itemID,
                    itemKey = reagent.itemKey,
                    name = reagent.name or AHT:GetItemInfo(itemID) or tostring(itemID),
                    quantityPerCraft = 0,
                    loaded = false,
                }
                byItemID[itemID] = entry
                table.insert(materials, entry)
            end
            entry.quantityPerCraft = entry.quantityPerCraft + (tonumber(reagent.quantity) or 1)
        end
    end
    self.ahCraftMaterials = materials
    self.ahCraftEntries = { self.ahCraftOutput }
    for _, entry in ipairs(materials) do table.insert(self.ahCraftEntries, entry) end
    self.ahRecipeStatus = "Suche aktuelle Listings für Ergebnis und Materialien …"
    self:RecalculateAHRecipeEntries()
    self:RenderAHRecipePanel()

    local index = 1
    local function Next()
        if serial ~= self.ahRecipeSearchSerial then return end
        local entry = self.ahCraftEntries[index]
        if not entry then
            self.ahRecipeStatus = "Listings vollständig geladen."
            self:RecalculateAHRecipeEntries()
            self:RenderAHRecipePanel()
            return
        end
        entry.loading = true
        self:RenderAHRecipePanel()
        AHT.AH:Search({ itemID = entry.itemID, itemKey = entry.itemKey, name = entry.name, kind = entry.kind }, function(results, meta)
            if serial ~= self.ahRecipeSearchSerial then return end
            entry.loading = false
            entry.loaded = true
            entry.results = results or {}
            entry.meta = meta or {}
            if entry.results[1] and entry.results[1].itemKey then entry.itemKey = entry.results[1].itemKey end
            if meta and meta.error then entry.error = meta.error end
            index = index + 1
            self:RecalculateAHRecipeEntries()
            self:RenderAHRecipePanel()
            Next()
        end)
    end
    Next()
    return true
end

function AHT.UI:BuyAHRecipeMaterial(entry)
    if not entry or entry.kind ~= "material" then return false end
    if entry.buyState == "confirm" then
        if AHT.Buyer and AHT.Buyer:ConfirmCommodity() then
            entry.buyState = "submitted"
            self:RenderAHRecipePanel()
            return true
        end
        return false
    end
    if entry.buyState == "ready" then
        entry.buyState = "buying"
        if AHT.Buyer and AHT.Buyer:StartPendingPurchase() then
            self:RenderAHRecipePanel()
            return true
        end
        entry.buyState = nil
        entry.error = "Kauf konnte nicht ausgelöst werden. Bitte erneut prüfen."
        self:RenderAHRecipePanel()
        return false
    end
    if AHT.Buyer and AHT.Buyer.pending then
        self.ahRecipeStatus = "Es läuft bereits ein anderer Kauf."
        self:RenderAHRecipePanel()
        return false
    end
    self:RecalculateAHRecipeEntries()
    local plan = entry.plan
    if not plan or plan.missing > 0 then return false end
    plan.target = { itemID = entry.itemID, itemKey = entry.itemKey, name = entry.name, kind = "unknown" }
    plan.maxUnitPrice = entry.cheapest
    entry.buyState = "checking"
    entry.error = nil
    self:RenderAHRecipePanel()
    local started = AHT.Buyer:Confirm(plan, function(state, data)
        if state == "ready" then
            entry.buyState = "ready"
        elseif state == "price" then
            entry.buyState = "confirm"
        elseif state == "submitted" then
            entry.buyState = "submitted"
        elseif state == "completed" then
            entry.buyState = "done"
            entry.purchasedQuantity = (entry.purchasedQuantity or 0) + (tonumber(data and data.purchasedQuantity) or tonumber(plan.plannedQuantity) or 0)
        elseif state == "error" then
            entry.buyState = "error"
            entry.error = tostring(data or "Kauf fehlgeschlagen")
        end
        self:RecalculateAHRecipeEntries()
        self:RenderAHRecipePanel()
    end)
    if not started then
        entry.buyState = "error"
        entry.error = "Kaufprüfung konnte nicht gestartet werden."
        self:RenderAHRecipePanel()
    end
    return started
end

function AHT.UI:OpenRecipeInAuctionHouse(result)
    if not result or not result.output or #(result.reagents or {}) == 0 then return false end
    if not AHT.AHOpen then
        AHT:Print("Bitte zuerst das Auktionshaus öffnen.")
        return false
    end
    self:HideRecipeContext()
    if self.actionDialog then self.actionDialog:Hide() end
    if self.buyDialog then self.buyDialog:Hide() end
    if self.postDialog then self.postDialog:Hide() end
    if self.frame then self.frame:Hide() end
    self.ahCraftRecipe = result
    self.ahCraftCrafts = 1
    self:ShowAHRecipePanel(result, true)
    return true
end

function AHT.UI:ShowAHRecipePanel(recipe, refresh)
    local auctionHouse = _G.AuctionHouseFrame
    if not self.ahRecipePanel then self:CreateAHRecipePanel() end
    self:ShowAHButton()
    self.ahCraftRecipe = recipe or self.ahCraftRecipe
    if not self.ahCraftRecipe then return false end
    if auctionHouse then self:ShowAHRecipeTab(auctionHouse) end
    self.ahRecipePanel:Show()
    if self.ahRecipePanel.Raise then self.ahRecipePanel:Raise() end
    if self.ahRecipeTab then self.ahRecipeTab:SetText("AHT Rezept") end
    if refresh then self:StartAHRecipeListingScan(self.ahCraftRecipe) else self:RenderAHRecipePanel() end
    return true
end

function AHT.UI:EnsureRows(count)
    local target = math.max(24, tonumber(count) or 0)
    for index = #self.rows + 1, target do
        self:CreateRow(index)
    end
end

function AHT.UI:CreateRows()
    self:EnsureRows(24)
end

function AHT.UI:GetActiveColumns()
    if self.viewMode == "materials" then return MATERIAL_COLUMNS end
    if self.viewMode == "opportunities" then return OPPORTUNITY_COLUMNS end
    if self.viewMode == "orders" then return ORDER_COLUMNS end
    return RECIPE_COLUMNS
end

function AHT.UI:EnsureSortColumn()
    local columns = self:GetActiveColumns()
    for _, column in ipairs(columns) do
        if column.key == self.sortColumn then return end
    end
    if self.viewMode == "materials" then
        self.sortColumn = "currentPrice"
        self.sortAscending = false
    elseif self.viewMode == "opportunities" then
        self.sortColumn = "profit"
        self.sortAscending = false
    elseif self.viewMode == "orders" then
        self.sortColumn = "createdAt"
        self.sortAscending = false
    else
        self.sortColumn = "profit"
        self.sortAscending = false
    end
end

function AHT.UI:LayoutTable()
    local columns = self:GetActiveColumns()
    local offset = 0
    for index, column in ipairs(columns) do
        local header = self.headers[index]
        header:ClearAllPoints()
        header:SetWidth(column.width)
        header:SetPoint("LEFT", offset, 0)
        for _, row in ipairs(self.rows) do
            local cell = row.cells[index]
            cell:ClearAllPoints()
            cell:SetPoint("LEFT", offset + 6, 0)
            cell:SetWidth(column.width - 12)
            cell:SetJustifyH(index == 1 and "LEFT" or "RIGHT")
        end
        offset = offset + column.width
    end
end

function AHT.UI:SetSort(column)
    if self.sortColumn == column then
        self.sortAscending = not self.sortAscending
    else
        self.sortColumn = column
        self.sortAscending = true
    end
    if AHT.DB and AHT.DB.ui then
        AHT.DB.ui.sortColumn = self.sortColumn
        AHT.DB.ui.sortAscending = self.sortAscending
    end
    self:Refresh()
end

function AHT.UI:UpdateHeaders()
    local tableMode = self.viewMode == "recipes" or self.viewMode == "transmute" or self.viewMode == "materials" or self.viewMode == "orders" or self.viewMode == "opportunities"
    if not self.tableHeader then return end
    self:LayoutTable()
    self.scroll:ClearAllPoints()
    self.scroll:SetPoint("TOPLEFT", 18, tableMode and -202 or -174)
    self.scroll:SetPoint("BOTTOMRIGHT", -34, 140)
    if not tableMode then
        self.tableHeader:Hide()
        return
    end
    self.tableHeader:Show()
    local columns = self:GetActiveColumns()
    for index, header in ipairs(self.headers) do
        if columns[index] then header:Show() else header:Hide() end
    end
    for index, column in ipairs(columns) do
        local header = self.headers[index]
        local marker = ""
        if self.sortColumn == column.key then
            marker = self.sortAscending and "  |cff66ff66▲|r" or "  |cffffaa44▼|r"
        end
        header.label:SetText(column.label .. marker)
    end
end

function AHT.UI:SortResults(results)
    local sorted = {}
    for _, result in ipairs(results or {}) do
        if self:MatchesFilter(result) then table.insert(sorted, result) end
    end
    self:EnsureSortColumn()
    local key = self.sortColumn
    local ascending = self.sortAscending == true
    table.sort(sorted, function(a, b)
        local av, bv
        if key == "name" or type(a[key]) == "string" or type(b[key]) == "string" then
            av, bv = string.lower(tostring(a.name or "")), string.lower(tostring(b.name or ""))
            if key ~= "name" then
                av, bv = string.lower(tostring(a[key] or "")), string.lower(tostring(b[key] or ""))
            end
        else
            av, bv = tonumber(a[key]), tonumber(b[key])
        end
        if av == nil or bv == nil then
            if av == nil and bv == nil then return tostring(a.name or "") < tostring(b.name or "") end
            return av ~= nil
        end
        if av == bv then return tostring(a.name or "") < tostring(b.name or "") end
        if ascending then return av < bv end
        return av > bv
    end)
    return sorted
end

function AHT.UI:MatchesFilter(result)
    if not result or result.kind == "info" then return true end
    local query = string.lower(self.searchQuery or "")
    if query ~= "" then
        local haystack = string.lower(table.concat({
            tostring(result.name or ""),
            tostring(result.itemID or ""),
            tostring(result.professionName or ""),
        }, " "))
        if not string.find(haystack, query, 1, true) then return false end
    end
    if self.viewMode == "materials" then
        if self.marketFilter == "watched" and not result.isWatched then return false end
        if self.marketFilter == "inventory" and not result.inInventory then return false end
    end
    if (self.viewMode == "recipes" or self.viewMode == "transmute") and self.professionFilter
            and result.professionName ~= self.professionFilter then return false end
    if self.viewMode == "opportunities" and result.kind == "opportunity" then
        if self.opportunityDirection and self.opportunityDirection ~= "all"
                and result.side ~= self.opportunityDirection then return false end
        local minimum = tonumber(self.minimumOpportunityPercent) or 0
        if minimum > 0 and (tonumber(result.discount) or 0) < minimum then return false end
    end
    if self.profitOnly and (self.viewMode == "recipes" or self.viewMode == "transmute" or self.viewMode == "opportunities") then
        local profit = tonumber(result.profit)
        if profit == nil and result.kind == "material" then
            profit = (tonumber(result.marketValue) or 0) - (tonumber(result.currentPrice) or 0)
        end
        if profit == nil and result.kind == "opportunity" and result.side == "sell" then
            profit = tonumber(result.discount) or 0
        end
        if profit == nil or profit <= 0 then return false end
    end
    return true
end

function AHT.UI:SelectResult(result)
    if not result or result.kind == "info" then
        self.selectedResult = nil
        self.selectedKey = nil
    else
        self.selectedResult = result
        self.selectedKey = ResultKey(result)
    end
    self:RefreshDetail()
    for _, row in ipairs(self.rows or {}) do
        if row.result then
            local selected = self.selectedKey and ResultKey(row.result) == self.selectedKey
            row.bg:SetColorTexture(selected and 0.22 or (row.rowIndex % 2 == 0 and 0.045 or 0.065), selected and 0.13 or 0.032, selected and 0.035 or 0.018, 1)
        end
    end
end

function AHT.UI:RefreshDetail()
    if not self.detailPanel then return end
    local result = self.selectedResult
    if not result then
        self.detailTitle:SetText("Auswahl")
        self.detailSummary:SetText("Klicke ein Item für Preise, Verlauf, Zutaten und Bestand. Aktionen sind rechts beschriftet.")
        self.detailAction:Disable()
        self.detailSearch:Hide()
        return
    end

    local lines = {}
    local searchable = false
    if result.kind == "material" then
        local counts = AHT.Inventory and AHT.Inventory:GetCount(result.itemID) or { bags = 0, bank = 0, bankKnown = false }
        table.insert(lines, string.format("Aktuell %s  |  Marktwert %s  |  Ø %s  |  Markttrend %s",
            PriceText(result.currentPrice), PriceText(result.marketValue), PriceText(result.averagePrice), PercentText(result.marketTrendPercent)))
        table.insert(lines, string.format("Seit letztem Scan %s  |  %d Listings / %d Stück  |  Tasche %d, Bank %s  |  %s",
            PercentText(result.priceChangePercent), result.listingCount or 0, result.totalQuantity or 0,
            counts.bags or 0, counts.bankKnown and tostring(counts.bank or 0) or "?", ScanAgeText(result.updatedAt)))
        self.detailAction:SetText("Aktionen")
        searchable = true
    elseif result.kind == "opportunity" then
        local direction = result.side == "sell" and "Verkauf" or "Kauf"
        table.insert(lines, string.format("%s-Chance  |  Aktuell %s  |  Marktwert %s  |  Vorteil %s  |  Netto %s  |  ROI %s",
            direction, PriceText(result.currentPrice), PriceText(result.marketValue), PercentText(result.discount),
            PriceText(result.profit), PercentText(result.roi)))
        table.insert(lines, string.format("Angebotsmenge %d  |  Historische Samples %d  |  %s",
            result.quantity or 0, result.sampleCount or result.marketSamples or 0, ScanAgeText(result.updatedAt)))
        self.detailAction:SetText(result.side == "sell" and "Verkaufsplan" or "Kaufchance")
        searchable = result.itemID ~= nil
    elseif result.kind == "order" then
        local order = result.order or {}
        local requirements = {}
        for index, requirement in ipairs(order.requirements or {}) do
            if index <= 3 then
                local itemName = requirement.name or AHT:GetItemInfo(requirement.itemID) or tostring(requirement.itemID)
                table.insert(requirements, string.format("%s: %d/%d", itemName,
                    requirement.bought or 0, requirement.toBuy or requirement.quantity or 0))
            end
        end
        table.insert(lines, string.format("%d Herstellvorgänge  |  Status: %s  |  Offen: %d  |  Ausgegeben: %s",
            result.crafts or 0, result.statusText or "?", result.remainingCount or 0, PriceText(result.spent or 0)))
        if #requirements > 0 then table.insert(lines, table.concat(requirements, "  •  ")) end
        self.detailAction:SetText("Auftrag öffnen")
    else
        local output = result.output or {}
        local snapshot = result.marketSnapshot or (output.itemID and AHT.Store:GetMarketSnapshot(output.itemID))
        local sale = result.currentSalePrice or result.salePrice
        table.insert(lines, string.format("Kosten %s  |  Aktueller Verkauf %s  |  Marktwert %s  |  Netto %s  |  Marge %s  |  Vorschlag %d Herstellvorgänge",
            PriceText(result.ingredientCost), PriceText(sale), PriceText(result.marketSalePrice), PriceText(result.profit),
            result.margin and string.format("%.1f%%", result.margin) or "-", result.suggestedCrafts or 0))
        table.insert(lines, string.format("Seit letztem Scan %s  |  Markttrend %s  |  %s",
            PercentText(snapshot and snapshot.priceChangePercent), PercentText(snapshot and snapshot.trendPercent), ScanAgeText(snapshot and snapshot.updatedAt)))
        local ingredients = {}
        local crafts = math.max(1, tonumber(result.suggestedCrafts) or 0)
        for index, reagent in ipairs(result.reagents or {}) do
            if index <= 3 then
                local quantity = (tonumber(reagent.quantity) or 1) * crafts
                local itemName = reagent.name or AHT:GetItemInfo(reagent.itemID) or tostring(reagent.itemID)
                local price = AHT.Store and AHT.Store:GetPrice(reagent.itemID)
                local count = AHT.Inventory and AHT.Inventory:GetCount(reagent.itemID) or { bags = 0, bank = 0, bankKnown = false }
                local reserved = AHT.Production and AHT.Production:GetReserved(reagent.itemID) or 0
                local knownStock = (count.bags or 0) + (count.bankKnown and (count.bank or 0) or 0)
                local available = math.max(0, knownStock - reserved)
                local missing = available >= quantity and 0 or count.bankKnown and (quantity - available) or "?"
                table.insert(ingredients, string.format("%dx %s @ %s [T%d/B%s, reserviert %d, fehlen %s]", quantity, itemName, PriceText(price),
                    count.bags or 0, count.bankKnown and tostring(count.bank or 0) or "?", reserved, tostring(missing)))
            end
        end
        if #ingredients > 0 then
            local extra = math.max(0, #(result.reagents or {}) - #ingredients)
            local craftLabel = crafts == 1 and "1 Herstellvorgang" or string.format("%d Herstellvorgänge", crafts)
            table.insert(lines, string.format("Zutaten für %s: %s%s", craftLabel, table.concat(ingredients, "  •  "),
                extra > 0 and string.format("  +%d weitere", extra) or ""))
        else
            table.insert(lines, "Zutaten und Einkaufspreise sind noch nicht vollständig erfasst.")
        end
        self.detailAction:SetText("Kaufplan")
        searchable = output.itemID ~= nil
    end

    self.detailTitle:SetText(result.name or (result.order and result.order.name) or "Itemdetails")
    self.detailSummary:SetText(table.concat(lines, "\n"))
    self.detailAction:Enable()
    if searchable then self.detailSearch:Show() else self.detailSearch:Hide() end
end

function AHT.UI:HideRecipeContext()
    if self.recipeTooltipOwner and GameTooltip and GameTooltip.Hide then
        GameTooltip:Hide()
        self.recipeTooltipOwner = nil
    end
end

function AHT.UI:ShowRecipeContext(result, owner)
    if not GameTooltip or not GameTooltip.SetOwner or not GameTooltip.AddLine then return end
    self:HideRecipeContext()
    self.recipeTooltipOwner = owner
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(result.name or "Rezept", 1, 0.84, 0.35)
    GameTooltip:AddLine("Zutaten und Marktpreise", 0.8, 0.75, 0.55)
    GameTooltip:AddLine("Shift+Linksklick: Ergebnis direkt im AH anzeigen", 0.62, 0.72, 0.95)
    GameTooltip:AddLine("Strg+Linksklick: Rezept- und Material-Listings im AHT-Reiter", 0.62, 0.72, 0.95)
    GameTooltip:AddLine(" ")

    for _, reagent in ipairs(result.reagents or {}) do
        local quantity = tonumber(reagent.quantity) or 1
        local name = reagent.name or AHT:GetItemInfo(reagent.itemID) or tostring(reagent.itemID)
        local current = AHT.Store and AHT.Store:GetPrice(reagent.itemID)
        local snapshot = AHT.Store and AHT.Store:GetMarketSnapshot(reagent.itemID) or nil
        local average = snapshot and snapshot.averagePrice or AHT.Store and AHT.Store:RecencyAverage(reagent.itemID)
        local market = snapshot and snapshot.marketValue
        local counts = AHT.Inventory and AHT.Inventory:GetCount(reagent.itemID) or { bags = 0, bank = 0, bankKnown = false }
        local reserved = AHT.Production and AHT.Production:GetReserved(reagent.itemID) or 0
        local currentText = current and AHT:FormatMoneyPlain(current) or "?"
        local averageText = average and AHT:FormatMoneyPlain(average) or "?"
        local marketText = market and AHT:FormatMoneyPlain(market) or "?"
        local currentTotal = current and AHT:FormatMoneyPlain(current * quantity) or "?"
        GameTooltip:AddLine(string.format("%dx %s", quantity, name), 1, 1, 1)
        GameTooltip:AddDoubleLine(
            "  aktuell/Stk " .. currentText .. " | Gesamt " .. currentTotal,
            "Markt/Stk " .. marketText .. " | Ø " .. averageText,
            0.78, 0.78, 0.78, 0.45, 1, 0.45
        )
        GameTooltip:AddDoubleLine(
            "  Seit letztem Scan",
            snapshot and snapshot.priceChangePercent and string.format("%+.1f%%", snapshot.priceChangePercent) or "noch kein Vergleich",
            0.62, 0.72, 0.95, 0.45, 1, 0.45
        )
        GameTooltip:AddLine(string.format(
            "  Bestand: Tasche %d | Bank %s | reserviert %d",
            counts.bags or 0,
            counts.bankKnown and tostring(counts.bank or 0) or "?",
            reserved
        ), 0.55, 0.72, 0.95)
    end

    local output = result.output
    if output and output.itemID then
        local current = AHT.Store and AHT.Store:GetPrice(output.itemID)
        local snapshot = AHT.Store and AHT.Store:GetMarketSnapshot(output.itemID) or nil
        local average = snapshot and snapshot.averagePrice or AHT.Store and AHT.Store:RecencyAverage(output.itemID)
        local market = snapshot and snapshot.marketValue
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Verkaufspreis des Ergebnisses", 0.8, 0.75, 0.55)
        GameTooltip:AddDoubleLine("Aktueller Scan", current and AHT:FormatMoneyPlain(current) or "?", 0.78, 0.78, 0.78, 1, 1, 0.45)
        GameTooltip:AddDoubleLine("Robuster Marktwert", market and AHT:FormatMoneyPlain(market) or "?", 0.78, 0.78, 0.78, 0.45, 0.85, 1)
        GameTooltip:AddDoubleLine("Altersgewichteter Durchschnitt", average and AHT:FormatMoneyPlain(average) or "?", 0.78, 0.78, 0.78, 0.45, 1, 0.45)
        GameTooltip:AddDoubleLine("Seit letztem Scan", snapshot and snapshot.priceChangePercent and string.format("%+.1f%%", snapshot.priceChangePercent) or "noch kein Vergleich", 0.78, 0.78, 0.78, 0.45, 1, 0.45)
        GameTooltip:AddDoubleLine("Aktuell vs. Marktwert", snapshot and snapshot.trendPercent and string.format("%+.1f%%", snapshot.trendPercent) or "?", 0.78, 0.78, 0.78, 0.45, 0.85, 1)
    end

    local halfLife = AHT.DB and AHT.DB.settings and tonumber(AHT.DB.settings.averageHalfLifeSeconds) or 604800
    local halfLifeDays = math.max(1, math.floor(halfLife / 86400 + 0.5))
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(string.format("Ø = altersgewichtete Scans, Halbwertszeit %d Tage.", halfLifeDays), 0.62, 0.62, 0.62)
    GameTooltip:AddLine(string.format(
        "Empfehlung: %d Herstellvorgänge | ohne Einkauf: %d",
        tonumber(result.suggestedCrafts) or 0,
        tonumber(result.craftableFromStock) or 0
    ), 0.95, 0.82, 0.35)
    GameTooltip:Show()
end

function AHT.UI:ShowMaterialContext(result, owner)
    if not GameTooltip or not GameTooltip.SetOwner or not GameTooltip.AddLine then return end
    self:HideRecipeContext()
    self.recipeTooltipOwner = owner
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(result.name or "Material", 1, 0.84, 0.35)
    GameTooltip:AddLine("Shift+Linksklick: Item direkt im AH anzeigen", 0.62, 0.72, 0.95)
    GameTooltip:AddDoubleLine("Aktueller Einkauf", result.currentPrice and AHT:FormatMoneyPlain(result.currentPrice) or "?", 0.78, 0.78, 0.78, 1, 0.85, 0.35)
    GameTooltip:AddDoubleLine("Altersgewichteter Ø", result.averagePrice and AHT:FormatMoneyPlain(result.averagePrice) or "?", 0.78, 0.78, 0.78, 0.45, 1, 0.45)
    GameTooltip:AddDoubleLine("Robuster Marktwert", result.marketValue and AHT:FormatMoneyPlain(result.marketValue) or "?", 0.78, 0.78, 0.78, 0.45, 0.85, 1)
    GameTooltip:AddDoubleLine("P25", result.p25 and AHT:FormatMoneyPlain(result.p25) or "?", 0.65, 0.65, 0.65, 0.65, 0.65, 0.65)
    GameTooltip:AddDoubleLine("P75", result.p75 and AHT:FormatMoneyPlain(result.p75) or "?", 0.65, 0.65, 0.65, 0.65, 0.65, 0.65)
    GameTooltip:AddLine(string.format("Angebot: %d Stück / %d Listings", result.totalQuantity or 0, result.listingCount or 0), 0.62, 0.72, 0.95)
    GameTooltip:AddDoubleLine("Seit letztem Scan", result.priceChangePercent and string.format("%+.1f%%", result.priceChangePercent) or "noch kein Vergleich", 0.78, 0.78, 0.78, 0.45, 1, 0.45)
    GameTooltip:AddDoubleLine("Aktuell vs. Marktwert", result.marketTrendPercent and string.format("%+.1f%%", result.marketTrendPercent) or "?", 0.78, 0.78, 0.78, 0.45, 0.85, 1)
    GameTooltip:AddLine(string.format("Markt-Tage: %d | Letzter Scan: %s", result.marketSamples or 0, result.updatedText or "-"), 0.62, 0.72, 0.95)
    GameTooltip:Show()
end

function AHT.UI:ShowOpportunityContext(result, owner)
    if not GameTooltip or not GameTooltip.SetOwner or not GameTooltip.AddLine then return end
    self:HideRecipeContext()
    self.recipeTooltipOwner = owner
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    local selling = result.side == "sell"
    GameTooltip:AddLine((selling and "Verkaufschance: " or "Kaufchance: ") .. (result.name or "Chance"), 1, 0.84, 0.35)
    GameTooltip:AddLine("Shift+Linksklick: Item direkt im AH anzeigen", 0.62, 0.72, 0.95)
    GameTooltip:AddDoubleLine(selling and "Verkauf aktuell" or "Einkauf aktuell", result.currentPrice and AHT:FormatMoneyPlain(result.currentPrice) or "?", 1, 0.85, 0.35, 0.45, 0.85, 1)
    GameTooltip:AddDoubleLine("Marktwert", result.marketValue and AHT:FormatMoneyPlain(result.marketValue) or "?", 0.78, 0.78, 0.78, 0.45, 0.85, 1)
    GameTooltip:AddDoubleLine("Altersgewichteter Ø", result.averagePrice and AHT:FormatMoneyPlain(result.averagePrice) or "?", 0.78, 0.78, 0.78, 0.45, 1, 0.45)
    GameTooltip:AddDoubleLine("Preisänderung seit letztem Scan", result.priceChangePercent and string.format("%+.1f%%", result.priceChangePercent) or "noch kein Vergleich", 0.78, 0.78, 0.78, 0.45, 1, 0.45)
    GameTooltip:AddDoubleLine("Aktuell vs. Marktwert", result.trendPercent and string.format("%+.1f%%", result.trendPercent) or "?", 0.78, 0.78, 0.78, 0.45, 0.85, 1)
    GameTooltip:AddDoubleLine(selling and "Nettoerlös pro Stück" or "Netto pro Stück", AHT:FormatMoneyPlain(result.profit or 0), 0.45, 1, 0.45, 0.45, 1, 0.45)
    GameTooltip:AddDoubleLine("ROI", string.format("%.1f%%", result.roi or 0), 0.78, 0.78, 0.78, 0.45, 1, 0.45)
    GameTooltip:AddLine(string.format("%s %.1f%% | Empfehlung: %s", selling and "Aufschlag" or "Rabatt", result.discount or 0, result.bestMethod or "AH"), 0.78, 0.78, 0.78)
    if selling then
        GameTooltip:AddLine(string.format("Bestand: Tasche %d | Bank %s", result.stockBags or 0, result.bankKnown and tostring(result.stockBank or 0) or "?"), 0.62, 0.72, 0.95)
    else
        GameTooltip:AddLine(string.format("Angebot: %d Stück / %d Listings", result.quantity or 0, result.listingCount or 0), 0.62, 0.72, 0.95)
    end
    GameTooltip:AddLine(string.format("Vertrauen %d%% | Klick für Details.", result.confidence or 0), 0.62, 0.62, 0.62)
    GameTooltip:Show()
end

function AHT.UI:ShowMaterialActions(result)
    if not result then return end
    if self.actionDialog then self.actionDialog:Hide() end
    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    local dialog = CreateFrame("Frame", nil, UIParent, template)
    dialog:SetSize(430, 190)
    dialog:SetPoint("CENTER")
    dialog:SetFrameStrata("TOOLTIP")
    MakeBackdrop(dialog)
    self.actionDialog = dialog

    local title = Label(dialog, result.name or "Material", 400)
    title:SetPoint("TOPLEFT", 14, -14)
    title:SetFontObject("GameFontHighlightLarge")
    local info = Label(dialog, string.format(
        "Aktuell %s | Ø %s | Marktwert %s\nBestand aus Tasche und Bank wird bei Herstellungsaufträgen berücksichtigt.",
        result.currentPrice and AHT:FormatMoneyPlain(result.currentPrice) or "?",
        result.averagePrice and AHT:FormatMoneyPlain(result.averagePrice) or "?",
        result.marketValue and AHT:FormatMoneyPlain(result.marketValue) or "?"
    ), 400)
    info:SetPoint("TOPLEFT", 14, -50)
    info:SetHeight(52)
    info:SetJustifyV("TOP")

    local scan = Button(dialog, nil, "Neu scannen", 105, 24)
    scan:SetPoint("BOTTOMLEFT", 14, 12)
    scan:SetScript("OnClick", function()
        if not AHT.AHOpen or not AHT.AH then
            info:SetText("Das Auktionshaus muss für einen Live-Scan geöffnet sein.")
            return
        end
        scan:Disable()
        AHT.AH:Search({ itemID = result.itemID, name = result.name }, function(results, meta)
            scan:Enable()
            if meta.error then
                info:SetText("Scan fehlgeschlagen: " .. tostring(meta.error))
                return
            end
            AHT.Store:RecordMarket({ itemID = result.itemID, itemKey = result.itemKey, name = result.name }, {
                kind = meta.kind,
                minPrice = results[1] and results[1].unitPrice,
                totalQuantity = meta.totalQuantity,
                listingCount = meta.listingCount or #results,
                prices = meta.prices,
            })
            info:SetText("Live-Scan gespeichert. Marktansicht wurde aktualisiert.")
            self:Refresh(true)
        end)
    end)

    local remove = Button(dialog, nil, "Überwachung entfernen", 160, 24)
    remove:SetPoint("LEFT", scan, "RIGHT", 8, 0)
    remove:SetScript("OnClick", function()
        if AHT.Store then AHT.Store:RemoveMaterial(result.itemID) end
        dialog:Hide()
        self:SetView("materials")
    end)

    local close = Button(dialog, nil, CLOSE or "Close", 80, 24)
    close:SetPoint("BOTTOMRIGHT", -12, 12)
    close:SetScript("OnClick", function() dialog:Hide() end)
end

function AHT.UI:RefreshStatus()
    if not self.status then return end
    local stateLabels = {
        starting = "lädt",
        ready = "bereit",
        ah_open = "AH offen",
        ah_closed = "AH geschlossen",
        scanning = "Scan läuft",
        market_discovery = "Marktscan läuft",
        database_missing = "Daten fehlen",
        database_invalid = "Datenfehler",
    }
    local state = stateLabels[AHT.State.status] or "bereit"
    local progress = ""
    if AHT.Scanner and AHT.Scanner.running then
        local run = AHT.Scanner.scanRun or {}
        progress = string.format(" | Lauf %d/%d, %d ok, %d verworfen",
            AHT.Scanner.completed, AHT.Scanner.total, run.itemCount or 0, run.rejectedCount or 0)
    elseif AHT.Scanner and AHT.Scanner.marketDiscovery then
        local run = AHT.Scanner.scanRun or {}
        progress = string.format(" | Lauf %d Items/%d Seiten, %d verworfen",
            AHT.Scanner.marketDiscovery.itemCount or 0, AHT.Scanner.marketDiscovery.pageCount or 0, run.rejectedCount or 0)
    end
    local view = VIEW_INFO[self.viewMode] or VIEW_INFO.recipes
    local scan = AHT.DB and AHT.DB.scan
    local scanSummary = "kein Scan"
    if scan and scan.finishedAt then
        local scanLabels = { completed = "fertig", partial = "teilweise", aborted = "abgebrochen", failed = "fehlgeschlagen" }
        scanSummary = string.format("%s %d Items/%d Seiten, %s",
            scanLabels[scan.status] or "unbekannt", scan.itemCount or 0, scan.pageCount or 0, ScanAgeText(scan.finishedAt))
    end
    local marketCount = AHT:TableCount(AHT.DB and AHT.DB.market)
    local historyCount = AHT:TableCount(AHT.DB and AHT.DB.history)
    self.status:SetText(string.format("%s | Markt %d / Verlauf %d | Letzter Scan: %s%s", state, marketCount, historyCount, scanSummary, progress))
    if self.viewTitle then self.viewTitle:SetText(view.title) end
    local help = self.lastMessage ~= "" and self.lastMessage or view.help
    if self.viewHelp then self.viewHelp:SetText(help) end
    local scanning = AHT.Scanner and (AHT.Scanner.running or AHT.Scanner.marketDiscovery)
    self.scanButton:SetText(scanning and "Abbrechen" or "Scannen ▾")
end

function AHT.UI:BuildMaterialRows()
    local rows = {}
    local materials = AHT.DB and AHT.DB.materials or {}
    local market = AHT.DB and AHT.DB.market or {}
    local inventorySet = self.marketFilter == "inventory" and AHT.Inventory and AHT.Inventory:GetAvailableItemSet() or {}
    local seen = {}

    local function AddRow(key, record, material)
        local itemID = tonumber((record and record.itemID) or (material and material.itemID))
        if not itemID then return end
        local rowKey = tostring(key or itemID)
        if seen[rowKey] then return end
        seen[rowKey] = true
        local snapshot = AHT.Store and AHT.Store:GetMarketSnapshot(itemID, record and record.itemKey) or nil
        local updatedAt = snapshot and snapshot.updatedAt or record and tonumber(record.updatedAt) or nil
        local name = material and material.name or record and record.name or tostring(itemID)
        table.insert(rows, {
            kind = "material",
            name = name,
            itemID = itemID,
            itemKey = record and record.itemKey,
            marketKey = rowKey,
            isWatched = material ~= nil,
            inInventory = inventorySet[tostring(itemID)] == true,
            currentPrice = snapshot and snapshot.currentPrice or record and tonumber(record.minPrice) or nil,
            marketValue = snapshot and snapshot.marketValue or nil,
            averagePrice = snapshot and snapshot.averagePrice or nil,
            priceChangePercent = snapshot and snapshot.priceChangePercent or nil,
            marketTrendPercent = snapshot and snapshot.trendPercent or nil,
            trendText = PercentText(snapshot and snapshot.trendPercent),
            p25 = snapshot and snapshot.p25,
            p75 = snapshot and snapshot.p75,
            totalQuantity = snapshot and snapshot.totalQuantity or tonumber(record and record.totalQuantity) or 0,
            listingCount = snapshot and snapshot.listingCount or tonumber(record and record.listingCount) or 0,
            marketSamples = snapshot and snapshot.marketSamples or 0,
            scanSamples = snapshot and snapshot.scanSamples or 0,
            updatedAt = updatedAt,
            updatedText = updatedAt and date("%d.%m.%y", updatedAt) or "-",
        })
    end

    for key, record in pairs(market) do
        if type(record) == "table" then
            local material = materials[tostring(record.itemID or "")]
            AddRow(key, record, material)
        end
    end
    for _, material in pairs(materials) do
        local record, key
        if AHT.Store then record, key = AHT.Store:GetByItemID(material.itemID) end
        AddRow(key or ("watch:" .. tostring(material.itemID)), record, material)
    end

    table.sort(rows, function(a, b)
        return string.lower(tostring(a.name)) < string.lower(tostring(b.name))
    end)
    if #rows == 0 then
        local message = self.marketFilter == "watched" and "Keine beobachteten Items. Füge ein Item über Material hinzu."
            or self.marketFilter == "inventory" and "Keine Items in Taschen/Bank gefunden. Öffne die Bank, damit der Bestand aktualisiert wird."
            or "Noch keine Items erfasst. Starte 'Ganzer AH-Markt' oder einen Scan bekannter Items."
        table.insert(rows, { kind = "info", text = message })
    end
    return rows
end

function AHT.UI:BuildOpportunityRows()
    -- Opportunity rows use current recipe cost as an optional sell basis.
    if AHT.Calculator then AHT.Calculator:Refresh() end
    local rows = AHT.Opportunities and AHT.Opportunities:Build() or {}
    if #rows == 0 then
        local scan = AHT.DB and AHT.DB.scan or {}
        local marketCount = AHT:TableCount(AHT.DB and AHT.DB.market)
        local message
        if marketCount == 0 or not scan.finishedAt then
            message = "Noch kein AH-Markt-Scan gespeichert. Wähle 'Ganzer AH-Markt'; dieser erfasst Items unabhängig von Rezepten und Überwachung."
        elseif scan.status == "partial" or scan.status == "aborted" then
            message = "Der letzte AH-Markt-Scan war nur teilweise. Bereits erfasste Preise bleiben erhalten; starte ihn erneut für den Rest."
        elseif scan.status == "failed" then
            message = "Der letzte AH-Markt-Scan ist fehlgeschlagen. Gespeicherte alte Preise bleiben bestehen; prüfe den AH und starte erneut."
        else
            local currentListings, historyReady = 0, 0
            local minimumSamples = tonumber(AHT.DB.settings.minMarketSamples) or 2
            for _, record in pairs(AHT.DB.market or {}) do
                local snapshot = record.itemID and AHT.Store:GetMarketSnapshot(record.itemID, record.itemKey)
                if snapshot and snapshot.currentPrice and snapshot.currentPrice > 0 then
                    currentListings = currentListings + 1
                    if math.max(snapshot.marketSamples or 0, snapshot.scanSamples or 0) >= minimumSamples then
                        historyReady = historyReady + 1
                    end
                end
            end
            if currentListings == 0 then
                message = "Kein aktuelles Listing gefunden. Führe einen neuen AH-Markt-Scan aus, um die Marktlage zu aktualisieren."
            elseif historyReady == 0 then
                message = string.format("Noch zu wenig Historie für Chancen: pro Item werden mindestens %d Scans benötigt. Scanne den AH-Markt später erneut.", minimumSamples)
            else
                message = "Keine Chance erfüllt derzeit die gewählte Richtung und den Mindestvorteil. Filter lockern oder später erneut scannen."
            end
        end
        table.insert(rows, { kind = "info", text = message })
    end
    return rows
end

function AHT.UI:BuildOrderRows()
    local rows = {}
    local statusNames = {
        planned = "Geplant",
        previewing = "Prüfe Preise",
        ready = "Einkauf bereit",
        incomplete = "Unvollständig",
        checking = "Live-Prüfung",
        buying = "Kauf läuft",
        awaiting_purchase = "Kauf auslösen",
        awaiting_confirmation = "Bestätigung nötig",
        submitted = "Kauf gesendet",
        next_ready = "Nächste Zutat",
        paused = "Pausiert",
        ready_to_craft = "Bereit zum Herstellen",
    }
    for _, order in ipairs(AHT.Production and AHT.Production:GetActiveOrders() or {}) do
        local spent, remainingCount = 0, 0
        for _, requirement in ipairs(order.requirements or {}) do
            spent = spent + (tonumber(requirement.spent) or 0)
            remainingCount = remainingCount + math.max(0, (tonumber(requirement.toBuy) or 0) - (tonumber(requirement.bought) or 0))
        end
        table.insert(rows, {
            kind = "order",
            order = order,
            name = order.name or "?",
            crafts = tonumber(order.crafts) or 0,
            statusText = statusNames[order.status] or tostring(order.status or "?"),
            remainingCount = remainingCount,
            spent = spent,
            createdAt = tonumber(order.createdAt) or 0,
        })
    end
    if #rows == 0 then
        table.insert(rows, { kind = "info", text = "Keine aktiven Herstellungsaufträge. Rezept anklicken und Kaufplan öffnen." })
    end
    return rows
end

function AHT.UI:BuildReputationRows()
    local rows = {}
    local status, reason = AHT.Reputation and AHT.Reputation:GetStatus()
    if not status or not status.isCapital then
        table.insert(rows, { kind = "info", text = "Keine beobachtete Hauptstadtfraktion. Grund: " .. tostring(reason or "unbekannt") })
        return rows
    end
    table.insert(rows, { kind = "info", text = "Fraktion: " .. tostring(status.name) })
    if status.donations == 0 then
        table.insert(rows, { kind = "info", text = "Bereits Ehrfürchtig." })
        return rows
    end
    table.insert(rows, { kind = "info", text = string.format("Benötigte Spenden: %d | Runenstoff: %d", status.donations, status.runecloth) })
    local cost, source, unitPrice = AHT.Reputation:GetCost(status)
    if cost then
        table.insert(rows, { kind = "info", text = string.format("Preis: %s pro Stück (%s) | Gesamtkosten: %s", AHT:FormatMoneyPlain(unitPrice), source, AHT:FormatMoneyPlain(cost)) })
    else
        table.insert(rows, { kind = "info", text = "Noch kein Runenstoff-Marktpreis vorhanden. Erst einen Scan durchführen." })
    end
    return rows
end

function AHT.UI:BuildDiagnosticsRows()
    local rows, c = {}, AHT.Capabilities or {}
    table.insert(rows, { kind = "info", text = string.format("Version %s | Client %s | Build %s | Interface %s", AHT.VERSION, tostring(c.version), tostring(c.build), tostring(c.interface)) })
    table.insert(rows, { kind = "info", text = string.format("WOW_PROJECT_ID=%s | Forever-Beta=%s | AH offen=%s", tostring(c.projectID), tostring(c.foreverBeta), tostring(AHT.AHOpen)) })
    table.insert(rows, { kind = "info", text = string.format("Rezepte=%d | Markt=%d | Materialien=%d | Aufträge=%d", #((AHT.Recipes and AHT.Recipes:GetList()) or {}), AHT:TableCount(AHT.DB and AHT.DB.market), AHT:TableCount(AHT.DB and AHT.DB.materials), #((AHT.Production and AHT.Production:GetActiveOrders()) or {})) })
    local scan = AHT.DB and AHT.DB.scan or {}
    table.insert(rows, { kind = "info", text = string.format("Scan=%s | erfasst=%d | verworfen=%d | Seiten=%d | DB-Referenz kanonisch=%s",
        tostring(scan.status or "never"), tonumber(scan.itemCount) or 0, tonumber(scan.rejectedCount) or 0,
        tonumber(scan.pageCount) or 0, AHT.DB == WOW4E_AHT_DB and "ja" or "nein") })
    local names = {}
    for name in pairs(c.functions or {}) do table.insert(names, name) end
    table.sort(names)
    for _, name in ipairs(names) do table.insert(rows, { kind = "info", text = name .. "=" .. tostring(c.functions[name]) }) end
    if AHT.State.lastError then table.insert(rows, { kind = "info", text = "Letzter Fehler: " .. AHT.State.lastError }) end
    return rows
end

function AHT.UI:Refresh(skipCalculator)
    if not self.frame then return end
    local mode = self.viewMode or "recipes"
    local results
    if mode == "materials" then
        results = self:SortResults(self:BuildMaterialRows())
    elseif mode == "opportunities" then
        results = self:SortResults(self:BuildOpportunityRows())
    elseif mode == "orders" then
        results = self:SortResults(self:BuildOrderRows())
    elseif mode == "reputation" then
        results = self:BuildReputationRows()
    elseif mode == "diagnostics" then
        results = self:BuildDiagnosticsRows()
    else
        if not skipCalculator and AHT.Calculator then AHT.Calculator:Refresh() end
        local candidates = self.showTransmutes and AHT.Calculator and AHT.Calculator:CalculateTransmutes() or (AHT.Calculator and AHT.Calculator.results)
        candidates = candidates or {}
        if #candidates == 0 then
            local professionCount = AHT:TableCount(AHT.DB and AHT.DB.professions)
            local text
            if self.showTransmutes then
                text = "Keine Transmutationsrezepte erkannt. Prüfe, ob die passenden Berufsdaten synchronisiert wurden."
            elseif professionCount == 0 then
                text = "Noch kein Beruf synchronisiert. Öffne ein Berufsfenster; AHT übernimmt Rezepte und merkt sie sich dauerhaft."
            else
                text = "Berufsdaten sind gespeichert, aber es wurden keine herstellbaren Rezepte gefunden."
            end
            results = { { kind = "info", text = text } }
        else
            results = self:SortResults(candidates)
        end
    end
    if #results == 0 then
        local text = mode == "opportunities"
            and "Keine Treffer für die gewählte Richtung, Suche oder den Mindestvorteil. Filter lockern."
            or "Keine Treffer für die aktuelle Suche oder den Filter."
        results = {{ kind = "info", text = text }}
    end
    if self.selectedKey then
        local selected
        for _, result in ipairs(results) do
            if ResultKey(result) == self.selectedKey then selected = result break end
        end
        self.selectedResult = selected
        if not selected then self.selectedKey = nil end
    end
    self:EnsureRows(#results)
    self:UpdateHeaders()
    self.content:SetHeight(math.max(420, #results * ROW_HEIGHT))
    for index, row in ipairs(self.rows) do
        local result = results[index]
        row.result = result
        if result then
            local selected = self.selectedKey and ResultKey(result) == self.selectedKey
            row.bg:SetColorTexture(selected and 0.22 or (index % 2 == 0 and 0.045 or 0.065), selected and 0.13 or 0.032, selected and 0.035 or 0.018, 1)
            for cellIndex = 1, MAX_COLUMNS do row.cells[cellIndex]:SetTextColor(1, 1, 1) end
            if result.kind == "info" then
                row.info:SetText(result.text or "")
                row.info:Show()
                for index = 1, MAX_COLUMNS do row.cells[index]:Hide() end
                row:EnableMouse(true)
            elseif result.kind == "material" then
                row.info:Hide()
                row.cells[1]:SetText((result.isWatched and "★ " or "") .. (result.name or "?"))
                row.cells[2]:SetText(PriceText(result.currentPrice))
                row.cells[3]:SetText(PriceText(result.marketValue))
                row.cells[4]:SetText(PercentText(result.marketTrendPercent))
                row.cells[5]:SetText(result.updatedText .. " (" .. ScanAgeText(result.updatedAt) .. ")")
                for index = 1, #MATERIAL_COLUMNS do row.cells[index]:Show() end
                for index = #MATERIAL_COLUMNS + 1, MAX_COLUMNS do row.cells[index]:Hide() end
                row.cells[2]:SetTextColor(1, 0.85, 0.4)
                row.cells[3]:SetTextColor(0.45, 0.85, 1)
                if result.marketTrendPercent and result.marketTrendPercent < -10 then row.cells[4]:SetTextColor(0.45, 1, 0.55) end
                row:EnableMouse(true)
            elseif result.kind == "opportunity" then
                row.info:Hide()
                local marker = result.side == "sell" and "▼ Verkaufen: " or "▲ Kaufen: "
                row.cells[1]:SetText(marker .. (result.name or "?"))
                row.cells[2]:SetText(AHT:FormatMoneyPlain(result.currentPrice or 0))
                row.cells[3]:SetText(result.marketValue and AHT:FormatMoneyPlain(result.marketValue) or "-")
                row.cells[4]:SetText(string.format("%.1f%%", result.discount or 0))
                row.cells[5]:SetText(result.profit and AHT:FormatMoneyPlain(result.profit) or "-")
                for index = 1, #OPPORTUNITY_COLUMNS do row.cells[index]:Show() end
                for index = #OPPORTUNITY_COLUMNS + 1, MAX_COLUMNS do row.cells[index]:Hide() end
                row.cells[2]:SetTextColor(result.side == "sell" and 1 or 1, result.side == "sell" and 0.65 or 0.85, 0.35)
                row.cells[4]:SetTextColor(result.side == "sell" and 0.45 or 0.35, 1, 0.45)
                if result.profit and result.profit > 0 then row.cells[5]:SetTextColor(0.35, 1, 0.35) end
                row:EnableMouse(true)
            elseif result.kind == "order" then
                row.info:Hide()
                row.cells[1]:SetText(result.name or "?")
                row.cells[2]:SetText(tostring(result.crafts or 0))
                row.cells[3]:SetText(result.statusText or "?")
                row.cells[4]:SetText(tostring(result.remainingCount or 0))
                row.cells[5]:SetText(AHT:FormatMoneyPlain(result.spent or 0))
                for index = 1, #ORDER_COLUMNS do row.cells[index]:Show() end
                for index = #ORDER_COLUMNS + 1, MAX_COLUMNS do row.cells[index]:Hide() end
                row.cells[3]:SetTextColor(result.order.status == "ready_to_craft" and 0.35 or 1, result.order.status == "ready_to_craft" and 1 or 0.82, 0.35)
                row:EnableMouse(true)
            else
                local profit = result.profit and AHT:FormatMoneyPlain(result.profit) or AHT.L.incomplete
                local margin = result.margin and string.format("%.1f%%", result.margin) or "-"
                local cost = result.ingredientCost and AHT:FormatMoneyPlain(result.ingredientCost) or "?"
                local currentSale = result.currentSalePrice or result.salePrice
                local currentText = currentSale and AHT:FormatMoneyPlain(currentSale) or "?"
                local prefix = result.isDeal and "★ " or ""
                row.info:Hide()
                row.cells[1]:SetText(prefix .. (result.name or "?"))
                row.cells[2]:SetText(cost)
                row.cells[3]:SetText(currentText)
                row.cells[4]:SetText(profit)
                row.cells[5]:SetText(margin)
                for index = 1, #RECIPE_COLUMNS do row.cells[index]:Show() end
                for index = #RECIPE_COLUMNS + 1, MAX_COLUMNS do row.cells[index]:Hide() end
                if currentSale and result.marketSalePrice then
                    if currentSale < result.marketSalePrice then
                        row.cells[3]:SetTextColor(0.35, 1, 0.45)
                    elseif currentSale > result.marketSalePrice then
                        row.cells[3]:SetTextColor(1, 0.55, 0.35)
                    else
                        row.cells[3]:SetTextColor(1, 0.85, 0.4)
                    end
                else
                    row.cells[3]:SetTextColor(1, 0.85, 0.4)
                end
                if result.profit and result.profit >= 0 then
                    row.cells[4]:SetTextColor(0.35, 1, 0.35)
                else
                    row.cells[4]:SetTextColor(1, 0.45, 0.35)
                end
                row:EnableMouse(true)
            end
            row:Show()
        else
            row.info:SetText("")
            row.info:Hide()
            for index = 1, MAX_COLUMNS do row.cells[index]:Hide() end
            row:Hide()
        end
    end
    self:RefreshDetail()
    self:RefreshStatus()
end

function AHT.UI:Show()
    if not AHT.Initialized and AHT.Initialize then AHT:Initialize() end
    if not AHT.Initialized then
        self:ShowDatabaseRecovery()
        return false
    end
    if not self.frame then self:Create() end
    self:RestoreFrameStrata()
    AHT:Refresh()
    self.frame:Show()
    self:HideDatabaseRecovery()
    return true
end

function AHT.UI:ShowAHButton()
    local auctionHouse = _G.AuctionHouseFrame
    if not self.ahButton then
        -- Parent the control to UIParent. As a child of AuctionHouseFrame it
        -- can be painted below the Blizzard title-bar texture even with a
        -- higher local frame level.
        self.ahButton = Button(UIParent, "WOW4E_AH_Trader_AHButton", "AH Trader", 100, 24)
        self.ahButton:SetScript("OnClick", function() self:Show() end)
    else
        self.ahButton:SetParent(UIParent)
    end
    self.ahButton:ClearAllPoints()
    if auctionHouse then
        -- The Forever AH has an empty slot in its title bar on the left. Keep
        -- the button in that bar so it does not cover the search controls.
        self.ahButton:SetPoint("TOPLEFT", auctionHouse, "TOPLEFT", 18, -4)
        self.ahButton:SetFrameStrata("DIALOG")
        self.ahButton:SetFrameLevel(math.max((auctionHouse:GetFrameLevel() or 1) + 100, 100))
    else
        self.ahButton:SetPoint("TOP", UIParent, "TOP", 0, -90)
        self.ahButton:SetFrameStrata("DIALOG")
        self.ahButton:SetFrameLevel(100)
    end
    self.ahButton:Show()
    if auctionHouse then self:ShowAHRecipeTab(auctionHouse) end
end

function AHT.UI:ShowAHRecipeTab(auctionHouse)
    if not auctionHouse then return end
    if not self.ahCraftRecipe then
        if self.ahRecipeTab then self.ahRecipeTab:Hide() end
        return
    end
    if not self.ahRecipeTab then
        self.ahRecipeTab = Button(UIParent, "WOW4E_AH_Trader_RecipeTab", "AHT Rezept", 106, 24)
        self.ahRecipeTab:SetScript("OnClick", function()
            if self.ahRecipePanel and self.ahRecipePanel:IsShown() then
                self.ahRecipePanel:Hide()
            elseif self.ahCraftRecipe then
                self:ShowAHRecipePanel(self.ahCraftRecipe, false)
            else
                AHT:Print("Strg+Linksklick auf ein herstellbares Ergebnis lädt hier ein Rezept.")
            end
        end)
    else
        self.ahRecipeTab:SetParent(UIParent)
    end
    self.ahRecipeTab:ClearAllPoints()
    self.ahRecipeTab:SetPoint("TOPLEFT", auctionHouse, "TOPLEFT", 194, -4)
    self.ahRecipeTab:SetFrameStrata("DIALOG")
    self.ahRecipeTab:SetFrameLevel(math.max((auctionHouse:GetFrameLevel() or 1) + 101, 101))
    self.ahRecipeTab:Show()
end

function AHT.UI:HideAHRecipePanel()
    self:CancelAHRecipeScan()
    if self.ahRecipePanel then self.ahRecipePanel:Hide() end
end

function AHT.UI:CancelAHRecipeScan()
    self.ahRecipeSearchSerial = (self.ahRecipeSearchSerial or 0) + 1
end

function AHT.UI:HideAHButton()
    if self.ahButton then self.ahButton:Hide() end
    if self.ahRecipeTab then self.ahRecipeTab:Hide() end
    -- The recipe window is independent of the Blizzard AH frame. Keep it
    -- open with its cached listings when the AH closes, but stop live scans
    -- and make its purchase controls reflect that the AH is unavailable.
    self:CancelAHRecipeScan()
    if self.ahRecipePanel and self.ahRecipePanel:IsShown() then
        self.ahRecipeStatus = "Auktionshaus geschlossen. Gecachte Listings bleiben sichtbar."
        self:RenderAHRecipePanel()
    end
end

function AHT.UI:ShowRecipeActions(result)
    if self.actionDialog then self.actionDialog:Hide() end
    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    local dialog = CreateFrame("Frame", nil, UIParent, template)
    dialog:SetSize(420, 190)
    dialog:SetPoint("CENTER")
    dialog:SetFrameStrata("TOOLTIP")
    MakeBackdrop(dialog)
    MakeDialogMovable(dialog)
    self.actionDialog = dialog

    local title = Label(dialog, result.name or "Rezept", 380)
    title:SetPoint("TOPLEFT", 14, -14)
    title:SetFontObject("GameFontHighlightLarge")
    local detail = Label(dialog, string.format(
        "Kosten %s | Aktuell %s | Marktwert %s | Gewinn %s | Marge %s\nHover zeigt Zutaten, Bestand, aktuellen Preis und altersgewichteten Durchschnitt.",
        result.ingredientCost and AHT:FormatMoneyPlain(result.ingredientCost) or "?",
        (result.currentSalePrice or result.salePrice) and AHT:FormatMoneyPlain(result.currentSalePrice or result.salePrice) or "?",
        result.marketSalePrice and AHT:FormatMoneyPlain(result.marketSalePrice) or "?",
        result.profit and AHT:FormatMoneyPlain(result.profit) or "?",
        result.margin and string.format("%.1f%%", result.margin) or "?"
    ), 380)
    detail:SetPoint("TOPLEFT", 14, -46)
    detail:SetHeight(40)

    local close = Button(dialog, nil, CLOSE or "Close", 80, 24)
    close:SetPoint("BOTTOMRIGHT", -12, 12)
    close:SetScript("OnClick", function() dialog:Hide() end)

    local buy = Button(dialog, nil, "Kaufplan", 100, 24)
    buy:SetPoint("BOTTOMLEFT", 14, 12)
    buy:SetScript("OnClick", function() self:ShowBuyDialog(result) end)

    local post = Button(dialog, nil, "Postplan", 100, 24)
    post:SetPoint("LEFT", buy, "RIGHT", 8, 0)
    post:SetScript("OnClick", function() self:ShowPostDialog(result) end)
end

function AHT.UI:ShowOpportunityActions(result)
    if not result then return end
    if self.actionDialog then self.actionDialog:Hide() end
    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    local dialog = CreateFrame("Frame", nil, UIParent, template)
    dialog:SetSize(450, 205)
    dialog:SetPoint("CENTER")
    dialog:SetFrameStrata("TOOLTIP")
    MakeBackdrop(dialog)
    MakeDialogMovable(dialog)
    self.actionDialog = dialog

    local selling = result.side == "sell"
    local title = Label(dialog, (selling and "Verkaufschance: " or "Kaufchance: ") .. (result.name or "Marktchance"), 420)
    title:SetPoint("TOPLEFT", 14, -14)
    title:SetFontObject("GameFontHighlightLarge")
    local info = Label(dialog, string.format(
        "%s %s | Marktwert %s | %s %s pro Stück\n%s %.1f%% | ROI %.1f%% | bevorzugt: %s",
        selling and "Verkauf" or "Einkauf",
        AHT:FormatMoneyPlain(result.currentPrice or 0),
        AHT:FormatMoneyPlain(result.marketValue or 0),
        selling and "Nettoerlös" or "Netto",
        AHT:FormatMoneyPlain(result.profit or 0),
        selling and "Aufschlag" or "Rabatt",
        result.discount or 0,
        result.roi or 0,
        result.bestMethod or "AH"
    ), 420)
    info:SetPoint("TOPLEFT", 14, -50)
    info:SetHeight(60)
    info:SetJustifyV("TOP")

    local primary
    if selling then
        primary = Button(dialog, nil, "Postplan", 105, 24)
        primary:SetPoint("BOTTOMLEFT", 14, 12)
        primary:SetScript("OnClick", function()
            local postResult = result.recipe or {
                name = result.name,
                output = { itemID = result.itemID, name = result.name, quantity = 1 },
                currentSalePrice = result.currentPrice,
                expectedSalePrice = result.currentPrice,
                salePrice = result.currentPrice,
                marketSalePrice = result.marketValue,
            }
            self:ShowPostDialog(postResult)
        end)
    else
        primary = Button(dialog, nil, "Als Material überwachen", 165, 24)
        primary:SetPoint("BOTTOMLEFT", 14, 12)
        primary:SetScript("OnClick", function()
            if AHT.Store then AHT.Store:AddMaterial(result.itemID, result.name) end
            dialog:Hide()
            self:SetView("materials")
        end)
    end

    local scan = Button(dialog, nil, "Neu scannen", 100, 24)
    scan:SetPoint("LEFT", primary, "RIGHT", 8, 0)
    scan:SetScript("OnClick", function()
        if not AHT.AHOpen or not AHT.AH then
            info:SetText("Das Auktionshaus muss für einen Live-Scan geöffnet sein.")
            return
        end
        scan:Disable()
        AHT.AH:Search({ itemID = result.itemID, itemKey = result.itemKey, name = result.name }, function(results, meta)
            scan:Enable()
            if meta.error then
                info:SetText("Scan fehlgeschlagen: " .. tostring(meta.error))
                return
            end
            AHT.Store:RecordMarket({ itemID = result.itemID, itemKey = result.itemKey, name = result.name }, {
                kind = meta.kind,
                minPrice = results[1] and results[1].unitPrice,
                totalQuantity = meta.totalQuantity,
                listingCount = meta.listingCount or #results,
                prices = meta.prices,
            })
            info:SetText("Live-Scan gespeichert. Die Chance wird mit den neuen Daten neu bewertet.")
            self:Refresh(true)
        end)
    end)

    local close = Button(dialog, nil, CLOSE or "Close", 80, 24)
    close:SetPoint("BOTTOMRIGHT", -12, 12)
    close:SetScript("OnClick", function() dialog:Hide() end)
end

local function ProductionOrderText(order, suggestion)
    local lines = {}
    if not order then
        table.insert(lines, string.format(
            "Empfehlung: %d Herstellvorgänge | Ohne Einkauf herstellbar: %d | Marge: %s",
            suggestion and suggestion.suggestedCrafts or 0,
            suggestion and suggestion.craftableFromStock or 0,
            suggestion and suggestion.margin and string.format("%.1f%%", suggestion.margin) or "?"
        ))
        table.insert(lines, "Die Empfehlung ist konservativ und begrenzt die neue Menge auf einen Anteil des aktuell angebotenen Bestands.")
        return table.concat(lines, "\n")
    end

    local preview = order.preview
    if preview then
        table.insert(lines, string.format(
            "Marge: %s | Gewinn: %s | Neuer Goldbedarf: %s | Status: %s",
            preview.margin and string.format("%.1f%%", preview.margin) or "?",
            preview.profit and AHT:FormatMoneyPlain(preview.profit) or "?",
            AHT:FormatMoneyPlain(preview.cashCost or 0),
            tostring(order.status or "?")
        ))
    else
        table.insert(lines, "Status: " .. tostring(order.status or "geplant"))
    end
    table.insert(lines, " ")
    table.insert(lines, "Zutat | Tasche | Bank | reserviert | zugeteilt | noch kaufen")
    for _, requirement in ipairs(order.requirements or {}) do
        local remaining = math.max(0, (tonumber(requirement.toBuy) or 0) - (tonumber(requirement.bought) or 0))
        local bankText = requirement.bankKnown and tostring(requirement.bank or 0) or "?"
        table.insert(lines, string.format(
            "%dx %s | Tasche %d | Bank %s | anderweitig reserviert %d | diesem Auftrag zugeteilt %d | noch kaufen %d",
            requirement.required or 0,
            requirement.name or tostring(requirement.itemID),
            requirement.bags or 0,
            bankText,
            requirement.reservedOther or 0,
            requirement.ownedAllocated or 0,
            remaining
        ))
        if (requirement.bought or 0) > 0 then
            table.insert(lines, string.format("   bereits gekauft: %d für %s", requirement.bought, AHT:FormatMoneyPlain(requirement.spent or 0)))
        end
        if requirement.error then table.insert(lines, "   Problem: " .. tostring(requirement.error)) end
    end
    return table.concat(lines, "\n")
end

function AHT.UI:ShowBuyDialog(result, existingOrder)
    if self.actionDialog then self.actionDialog:Hide() end
    if self.buyDialog then self.buyDialog:Hide() end
    if not AHT.Production or not result or #(result.reagents or {}) == 0 then
        AHT:Print("Dieses Rezept hat keine kaufbaren Zutaten.")
        return
    end

    local suggestion = AHT.Production:Suggest(result)
    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    local dialog = CreateFrame("Frame", nil, UIParent, template)
    dialog:SetSize(700, 500)
    dialog:SetPoint("CENTER")
    dialog:SetFrameStrata("TOOLTIP")
    MakeBackdrop(dialog)
    MakeDialogMovable(dialog)
    self.buyDialog = dialog
    dialog.result = result
    dialog.order = existingOrder

    local title = Label(dialog, "Herstellungs- und Einkaufsplan: " .. (result.name or "?"), 660)
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetFontObject("GameFontHighlightLarge")

    local quantityLabel = Label(dialog, "Herstellvorgänge:", 130)
    quantityLabel:SetPoint("TOPLEFT", 16, -55)
    local quantity = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
    quantity:SetSize(70, 24)
    quantity:SetPoint("LEFT", quantityLabel, "RIGHT", 8, 0)
    quantity:SetAutoFocus(false)
    quantity:SetNumeric(true)
    quantity:SetText(tostring(existingOrder and existingOrder.crafts or math.max(1, suggestion.suggestedCrafts or 1)))
    if existingOrder then DisableInput(quantity) end

    local info = Label(dialog, "", 660)
    info:SetPoint("TOPLEFT", 16, -92)
    info:SetHeight(330)
    info:SetJustifyV("TOP")
    info:SetText(ProductionOrderText(dialog.order, suggestion))

    local action = Button(dialog, nil, "Autokauf starten", 155, 26)
    action:SetPoint("BOTTOMLEFT", 16, 14)
    action:Disable()

    local preview = Button(dialog, nil, existingOrder and "Preise neu prüfen" or "Plan prüfen", 135, 26)
    preview:SetPoint("LEFT", action, "RIGHT", 8, 0)

    local cancelOrder = Button(dialog, nil, "Auftrag stornieren", 140, 26)
    cancelOrder:SetPoint("LEFT", preview, "RIGHT", 8, 0)
    if not existingOrder then cancelOrder:Disable() end

    local close = Button(dialog, nil, CLOSE or "Close", 90, 26)
    close:SetPoint("BOTTOMRIGHT", -14, 14)

    local function Render()
        info:SetText(ProductionOrderText(dialog.order, suggestion))
        if not dialog.order then
            action:Disable()
            return
        end
        cancelOrder:Enable()
        local status = dialog.order.status
        if status == "awaiting_purchase" then
            action:SetText("Kauf auslösen")
            action:Enable()
        elseif status == "awaiting_confirmation" then
            action:SetText("Kauf bestätigen")
            action:Enable()
        elseif status == "ready_to_craft" then
            action:SetText("Einkauf fertig")
            action:Disable()
        elseif status == "previewing" or status == "checking" or status == "buying" or status == "submitted" then
            action:SetText("Bitte warten…")
            action:Disable()
        elseif dialog.order.preview and dialog.order.preview.complete and dialog.order.preview.meetsMargin then
            action:SetText(status == "next_ready" and "Nächste Zutat" or "Autokauf starten")
            action:Enable()
        else
            action:SetText("Autokauf starten")
            action:Disable()
        end
    end

    local function PurchaseCallback(state, data)
        Render()
        if state == "price" then
            local purchase = data.purchase
            info:SetText(ProductionOrderText(dialog.order, suggestion) .. string.format(
                "\n\nLive-Preis für %s: %s pro Stück, gesamt %s. Bitte bestätigen.",
                data.requirement.name or "Zutat",
                AHT:FormatMoneyPlain(purchase.unitPrice or 0),
                AHT:FormatMoneyPlain(purchase.totalPrice or 0)
            ))
        elseif state == "error" then
            info:SetText(ProductionOrderText(dialog.order, suggestion) .. "\n\nFehler: " .. tostring(data))
        end
        if self.viewMode == "orders" then self:Refresh(true) end
    end

    preview:SetScript("OnClick", function()
        if not dialog.order then
            local order, errorMessage = AHT.Production:CreateOrder(result, tonumber(quantity:GetText()) or 1)
            if not order then info:SetText("Fehler: " .. tostring(errorMessage)) return end
            dialog.order = order
            DisableInput(quantity)
            cancelOrder:Enable()
        end
        dialog.order.status = "previewing"
        Render()
        preview:Disable()
        AHT.Production:PreviewOrder(dialog.order, function(order, errorMessage)
            preview:Enable()
            if errorMessage then
                Render()
                info:SetText("Preisprüfung fehlgeschlagen: " .. tostring(errorMessage))
                return
            end
            dialog.order = order
            Render()
        end)
    end)

    action:SetScript("OnClick", function()
        if not dialog.order then return end
        if AHT.Buyer and AHT.Buyer.pending and AHT.Buyer.pending.state == "ready_to_buy" then
            action:Disable()
            action:SetText("Kauf wird ausgelöst…")
            if not AHT.Production:StartCurrentPurchase() then
                Render()
                info:SetText(ProductionOrderText(dialog.order, suggestion) .. "\n\nFehler: Kauf konnte nicht ausgelöst werden. Bitte den Plan erneut prüfen.")
            end
            return
        end
        if AHT.Buyer and AHT.Buyer.pending and AHT.Buyer.pending.state == "awaiting_user_confirmation" then
            action:Disable()
            action:SetText("Kauf läuft…")
            if not AHT.Production:ConfirmCurrentCommodity() then
                Render()
                info:SetText(ProductionOrderText(dialog.order, suggestion) .. "\n\nFehler: Commodity-Kauf konnte nicht bestätigt werden.")
            end
            return
        end
        action:Disable()
        local ok, errorMessage
        if dialog.order.status == "ready" then
            ok, errorMessage = AHT.Production:Start(dialog.order, PurchaseCallback)
        else
            ok, errorMessage = AHT.Production:Continue(dialog.order, PurchaseCallback)
        end
        if not ok then
            Render()
            info:SetText(ProductionOrderText(dialog.order, suggestion) .. "\n\nFehler: " .. tostring(errorMessage))
        end
    end)

    cancelOrder:SetScript("OnClick", function()
        if dialog.order and AHT.Production:CancelOrder(dialog.order) then
            dialog:Hide()
            self:SetView("orders")
        end
    end)

    close:SetScript("OnClick", function()
        if AHT.Buyer and AHT.Buyer.pending then AHT.Buyer:Cancel("dialog_closed") end
        dialog:Hide()
    end)

    Render()
    dialog:Show()
end

function AHT.UI:ShowOrderActions(order)
    if not order then return end
    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    local dialog = CreateFrame("Frame", nil, UIParent, template)
    dialog:SetSize(480, 230)
    dialog:SetPoint("CENTER")
    dialog:SetFrameStrata("TOOLTIP")
    MakeBackdrop(dialog)
    MakeDialogMovable(dialog)

    local title = Label(dialog, order.name or "Herstellungsauftrag", 440)
    title:SetPoint("TOPLEFT", 14, -14)
    title:SetFontObject("GameFontHighlightLarge")
    local info = Label(dialog, ProductionOrderText(order), 440)
    info:SetPoint("TOPLEFT", 14, -48)
    info:SetHeight(110)
    info:SetJustifyV("TOP")

    local open = Button(dialog, nil, "Öffnen", 100, 24)
    open:SetPoint("BOTTOMLEFT", 14, 12)
    open:SetScript("OnClick", function()
        local result = AHT.Production:ResultFromOrder(order)
        dialog:Hide()
        if result then self:ShowBuyDialog(result, order) end
    end)

    local completed = Button(dialog, nil, "Hergestellt", 110, 24)
    completed:SetPoint("LEFT", open, "RIGHT", 8, 0)
    completed:SetScript("OnClick", function()
        AHT.Production:CompleteOrder(order)
        dialog:Hide()
        self:Refresh(true)
    end)

    local cancel = Button(dialog, nil, "Stornieren", 100, 24)
    cancel:SetPoint("LEFT", completed, "RIGHT", 8, 0)
    cancel:SetScript("OnClick", function()
        AHT.Production:CancelOrder(order)
        dialog:Hide()
        self:Refresh(true)
    end)

    local close = Button(dialog, nil, CLOSE or "Close", 80, 24)
    close:SetPoint("BOTTOMRIGHT", -12, 12)
    close:SetScript("OnClick", function() dialog:Hide() end)
end

function AHT.UI:ShowPostDialog(result)
    if self.actionDialog then self.actionDialog:Hide() end
    if self.postDialog then self.postDialog:Hide() end
    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    local dialog = CreateFrame("Frame", nil, UIParent, template)
    dialog:SetSize(430, 230)
    dialog:SetPoint("CENTER")
    dialog:SetFrameStrata("TOOLTIP")
    MakeBackdrop(dialog)
    MakeDialogMovable(dialog)
    self.postDialog = dialog

    local title = Label(dialog, "Postplan: " .. (result.name or "?"), 400)
    title:SetPoint("TOPLEFT", 14, -14)
    title:SetFontObject("GameFontHighlightLarge")
    local recommendation = AHT.Poster and AHT.Poster:RecommendPrice(result) or nil
    local suggestedPrice = recommendation and recommendation.recommendedPrice or result.expectedSalePrice or result.salePrice or 0
    local info = Label(dialog, "Bestand, Deposit und Preis werden vor dem Posten geprüft.", 400)
    info:SetPoint("TOPLEFT", 14, -48)
    info:SetHeight(45)

    local quantityLabel = Label(dialog, "Menge:", 82)
    quantityLabel:SetPoint("TOPLEFT", 14, -101)
    local quantity = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
    quantity:SetSize(70, 24)
    quantity:SetPoint("LEFT", quantityLabel, "RIGHT", 8, 0)
    quantity:SetAutoFocus(false)
    quantity:SetNumeric(true)
    quantity:SetText("1")

    local priceLabel = Label(dialog, "Preis/Stk (Kupfer):", 108)
    priceLabel:SetPoint("TOPLEFT", 190, -101)
    local price = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
    price:SetSize(100, 24)
    price:SetPoint("LEFT", priceLabel, "RIGHT", 8, 0)
    price:SetAutoFocus(false)
    price:SetNumeric(true)
    price:SetText(tostring(suggestedPrice))

    if recommendation then
        info:SetText(string.format(
            "Empfehlung %s | Marktwert %s | P25–P75 %s–%s | %d Tag(e) Historie",
            AHT:FormatMoneyPlain(recommendation.recommendedPrice or 0),
            AHT:FormatMoneyPlain(recommendation.marketValue or 0),
            AHT:FormatMoneyPlain(recommendation.p25 or 0),
            AHT:FormatMoneyPlain(recommendation.p75 or 0),
            recommendation.samples or 0
        ))
    end

    local confirm = Button(dialog, nil, "Posten", 100, 24)
    confirm:SetPoint("BOTTOMLEFT", 14, 12)
    confirm:Disable()

    local preview = Button(dialog, nil, "Vorschau", 100, 24)
    preview:SetPoint("LEFT", price, "RIGHT", 8, 0)
    preview:SetScript("OnClick", function()
        local plan, errorMessage = AHT.Poster:BuildPlan(result, tonumber(quantity:GetText()) or 1, 2, tonumber(price:GetText()) or 0)
        if not plan then info:SetText("Fehler: " .. tostring(errorMessage)) return end
        dialog.plan = plan
        info:SetText(string.format("Menge %d | Stückpreis %s | Deposit %s", plan.quantity, AHT:FormatMoneyPlain(plan.unitPrice), AHT:FormatMoneyPlain(plan.deposit)))
        confirm:Enable()
    end)

    confirm:SetScript("OnClick", function()
        local freshPlan, errorMessage = AHT.Poster:BuildPlan(
            result,
            tonumber(quantity:GetText()) or 1,
            2,
            tonumber(price:GetText()) or 0
        )
        if not freshPlan then
            info:SetText("Fehler: " .. tostring(errorMessage))
            return
        end
        dialog.plan = freshPlan
        if AHT.Poster:Post(freshPlan) then dialog:Hide() end
    end)
    local close = Button(dialog, nil, CLOSE or "Close", 80, 24)
    close:SetPoint("BOTTOMRIGHT", -12, 12)
    close:SetScript("OnClick", function() dialog:Hide() end)
    dialog:Show()
end

function AHT.UI:ShowMaterials()
    self:SetView("materials")
end
