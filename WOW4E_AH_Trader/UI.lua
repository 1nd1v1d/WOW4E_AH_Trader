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

local requestedItemNames = {}

local function UsableItemName(value)
    if value == nil then return nil end
    local name = tostring(value):match("^%s*(.-)%s*$")
    if name == "" or tonumber(name) then return nil end
    return name
end

function AHT.UI:RequestItemName(itemID)
    itemID = tonumber(itemID)
    if not itemID or requestedItemNames[itemID] then return end
    local request = C_Item and C_Item.RequestLoadItemDataByID
    if type(request) ~= "function" then return end
    requestedItemNames[itemID] = true
    local ok = pcall(request, itemID)
    if not ok then requestedItemNames[itemID] = nil end
end

function AHT.UI:OnItemInfoLoaded(itemID, success)
    itemID = tonumber(itemID)
    if not itemID or not requestedItemNames[itemID] then return end
    requestedItemNames[itemID] = nil
    if success == false then return end
    if self.frame and self.frame:IsShown() and (self.viewMode == "materials" or self.viewMode == "watched") then
        self:RequestRefresh()
    end
end

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

local GameTooltip = CreateFrame("GameTooltip", "WOW4E_AHT_ContextTooltip", UIParent, "GameTooltipTemplate")
MakeBackdrop(GameTooltip)

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
        if dialog.ahtWindowKey and AHT.DB then
            local x, y = dialog:GetCenter()
            local cx, cy = UIParent:GetCenter()
            if x and cx then AHT.DB.ui.windows[dialog.ahtWindowKey] = { x = x - cx, y = y - cy }; AHT.Store:Save() end
        end
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
        return "order:" .. tostring(result.order.id)
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

function AHT.UI:GetRecipeMaterialScanSummary(result)
    local oldestScan, scanned, required, seen = nil, 0, 0, {}
    for _, reagent in ipairs(result and result.reagents or {}) do
        local itemID = tonumber(reagent.itemID)
        local key = itemID and tostring(itemID) or string.lower(tostring(reagent.name or ""))
        if key ~= "" and not seen[key] then
            seen[key] = true
            local isVendorItem = itemID and AHT.Commerce and AHT.Commerce.IsVendorItem
                and AHT.Commerce:IsVendorItem(itemID, reagent.name)
            if not isVendorItem then
                required = required + 1
                local record = itemID and AHT.Store and AHT.Store:GetByItemID(itemID)
                local timestamp = record and tonumber(record.updatedAt)
                if timestamp then
                    scanned = scanned + 1
                    oldestScan = oldestScan and math.min(oldestScan, timestamp) or timestamp
                end
            end
        end
    end

    if required == 0 then return nil, "Händler" end
    if scanned == 0 then return nil, "noch nie" end
    if scanned < required then
        return oldestScan, string.format("%s (%d/%d)", ScanAgeText(oldestScan), scanned, required)
    end
    return oldestScan, ScanAgeText(oldestScan)
end

local RECIPE_COLUMNS = {
    { key = "name", label = "Rezept / Ergebnis", width = 230 },
    { key = "costPerOutput", label = "Kosten/Stk", width = 105 },
    { key = "salePrice", label = "Aktuell/Stk", width = 105 },
    { key = "profitPerOutput", label = "Gewinn/Stk", width = 145 },
    { key = "margin", label = "Marge", width = 115 },
    { key = "materialScanAt", label = "Zutaten-Scan", width = 120 },
}

local MATERIAL_COLUMNS = {
    { key = "name", label = "Item", width = 220 },
    { key = "currentPrice", label = "Aktuell", width = 105 },
    { key = "marketValue", label = "Marktwert", width = 115 },
    { key = "marketTrendPercent", label = "Abweichung", width = 90 },
    { key = "updatedAt", label = "Alter", width = 110 },
    { key = "averagePrice", label = "Ø gewichtet", width = 105, optional = true },
    { key = "priceChangePercent", label = "Änderung", width = 90, optional = true },
    { key = "totalQuantity", label = "Angebotsmenge", width = 100, optional = true },
    { key = "opportunityType", label = "Chance", width = 120, optional = true },
    { key = "discount", label = "Vorteil", width = 90, optional = true },
    { key = "profit", label = "Netto", width = 100, optional = true },
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
local MAX_COLUMNS = 12
local DETAIL_ROW_HEIGHT = 18
local DETAIL_PAIR_WIDTHS = { 0.25, 0.25, 0.25, 0.25 }
local DETAIL_INGREDIENT_WIDTHS = { 0.42, 0.14, 0.19, 0.25 }
local DETAIL_ORDER_WIDTHS = { 0.40, 0.18, 0.20, 0.22 }

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
    watched = {
        title = "Beobachten",
        help = "Eigene Itemliste. Markiere Items und starte einen gezielten AH-Scan.",
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
    self:SaveViewState()
    if AHT.Store then AHT.Store:Save() end
end

function AHT.UI:UpdateNavigation()
    local primary = {
        recipes = self.recipeButton,
        materials = self.matsButton,
        watched = self.watchButton,
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
    local watched = self.viewMode == "watched"
    local recipes = self.viewMode == "recipes" or self.viewMode == "transmute"
    local searchable = self.viewMode == "recipes"
        or self.viewMode == "transmute"
        or self.viewMode == "materials"
        or watched
    if self.searchLabel then
        if searchable then self.searchLabel:Show() else self.searchLabel:Hide() end
    end
    if self.searchInput then
        if searchable then self.searchInput:Show() else self.searchInput:Hide() end
    end
    if self.filterButton then
        if materials then self.filterButton:Show() else self.filterButton:Hide() end
        if materials then
            local labels = {
                all = "Alle Items", watched = "Beobachtet", inventory = "Bestand aller Figuren",
                opportunities = "Chancen",
            }
            self.filterButton:SetText(labels[self.marketFilter] or labels.all)
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
        if materials and self.marketFilter == "opportunities" then self.opportunityDirectionButton:Show() else self.opportunityDirectionButton:Hide() end
        local labels = { all = "Alle Chancen", buy = "Nur Kauf", sell = "Nur Verkauf" }
        self.opportunityDirectionButton:SetText(labels[self.opportunityDirection] or labels.all)
    end
    if self.opportunityMinimumButton then
        if materials and self.marketFilter == "opportunities" then self.opportunityMinimumButton:Show() else self.opportunityMinimumButton:Hide() end
        self.opportunityMinimumButton:SetText(string.format("Vorteil >= %d%%", self.minimumOpportunityPercent or 0))
    end
    local canAddItems = watched or (materials and self.marketFilter ~= "opportunities")
    if self.materialLabel then
        self.materialLabel:SetText(watched and "Item:" or "Material:")
        if canAddItems then self.materialLabel:Show() else self.materialLabel:Hide() end
    end
    if self.materialInput then
        if canAddItems then self.materialInput:Show() else self.materialInput:Hide() end
    end
    if self.materialAdd then
        if canAddItems then self.materialAdd:Show() else self.materialAdd:Hide() end
    end
    if self.scanButton then
        local scanView = recipes or materials or watched
        if scanView then
            self.scanButton:Show()
            self.scanButton:SetText(recipes and "Rezepte scannen" or materials and "AH scannen" or "Items scannen")
        else
            self.scanButton:Hide()
        end
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

function AHT.UI:ShowDatabaseRecovery(retryAttempted)
    if not self.databaseRecovery then
        local template = BackdropTemplateMixin and "BackdropTemplate" or nil
        local dialog = CreateFrame("Frame", nil, UIParent, template)
        dialog:SetSize(520, 260)
        dialog:SetPoint("CENTER")
        dialog:SetFrameStrata("DIALOG")
        dialog:SetFrameLevel(240)
        dialog:EnableMouse(true)
        if dialog.SetClampedToScreen then dialog:SetClampedToScreen(true) end
        MakeBackdrop(dialog)
        MakeDialogMovable(dialog)

        dialog.title = Label(dialog, "WoW4E AH Trader - Daten nicht geladen", 420)
        dialog.title:SetPoint("TOPLEFT", 16, -16)
        dialog.title:SetFontObject("GameFontHighlightLarge")
        dialog.title:SetTextColor(1, 0.84, 0.35)
        dialog.message = Label(dialog, "", 420)
        dialog.message:SetPoint("TOPLEFT", 16, -56)
        dialog.message:SetHeight(130)
        dialog.message:SetJustifyV("TOP")
        if dialog.message.SetWordWrap then dialog.message:SetWordWrap(true) end
        dialog.message:SetTextColor(0.9, 0.86, 0.75)

        dialog.retry = Button(dialog, nil, "Erneut prüfen", 118, 26)
        dialog.retry:SetPoint("BOTTOMLEFT", 16, 14)
        dialog.retry:SetScript("OnClick", function()
            if AHT:Initialize() then
                self:HideDatabaseRecovery()
                self:Show()
            else
                self:ShowDatabaseRecovery(true)
            end
        end)
        dialog.newDatabase = Button(dialog, nil, "Neue Datenbank", 132, 26)
        dialog.newDatabase:SetPoint("LEFT", dialog.retry, "RIGHT", 8, 0)
        dialog.newDatabase:SetScript("OnClick", function() AHT:InitializeNewDatabase() end)
        self.databaseRecovery = dialog
    end

    local missing = type(WOW4E_AHT_DB) ~= "table"
    local canCreate = missing and not (AHT.Store and AHT.Store.canonicalDB) and type(AHT.DB) ~= "table"
    local title = "WoW4E AH Trader - Daten nicht geladen"
    local message
    if retryAttempted and missing then
        title = "SavedVariables weiterhin nicht geladen"
        message = "Erneut geprüft: WoW hat die SavedVariables-Tabelle weiterhin nicht geladen. Ein Addon kann die Datei nicht während des laufenden Spiels nachladen. Beende WoW vollständig und prüfe danach die Addon-Datei sowie ihre .bak-Sicherung."
    elseif retryAttempted then
        title = "Datenbank weiterhin nicht verfügbar"
        message = "Die Datenbankprüfung ist erneut fehlgeschlagen. Es wurde nichts überschrieben. Beende WoW vollständig und prüfe die SavedVariables-Datei und ihre .bak-Sicherung, bevor du eine neue Datenbank anlegst."
    elseif canCreate then
        title = "AH Trader - Erstinstallation oder fehlende Daten"
        message = "Erstinstallation: Neue Datenbank legt deine Sammlung an. Falls du zuvor Daten hattest, nicht neu anlegen! Die SavedVariables-Datenbank ist nicht verfügbar. Erneut prüfen prüft nur den aktuellen Spielspeicher; WoW lädt die Datei nur beim Start. Wenn du bereits Daten hattest, lege keine neue Datenbank an. Prüfe nach beendetem Spiel die Datei und ihre .bak-Sicherung."
    elseif missing then
        message = "Die globale SavedVariables-Referenz fehlt, aber AHT hält die zuvor geladene Tabelle noch im Speicher. Erneut prüfen versucht, diese Referenz wiederherzustellen."
    else
        message = "Die gespeicherten Daten konnten nicht geladen werden. Bitte erneut prüfen. Eine neue Datenbank wird nur angeboten, wenn keine SavedVariables-Tabelle vorhanden ist."
    end
    self.databaseRecovery.title:SetText(title)
    self.databaseRecovery.message:SetText(message)
    if canCreate then self.databaseRecovery.newDatabase:Show() else self.databaseRecovery.newDatabase:Hide() end
    self.databaseRecovery:Show()
    if self.databaseRecovery.Raise then self.databaseRecovery:Raise() end
end

function AHT.UI:HideDatabaseRecovery()
    if self.databaseRecovery then self.databaseRecovery:Hide() end
end

function AHT.UI:SetView(viewMode)
    local requestedView = viewMode
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
    if requestedView == "opportunities" then
        self.viewMode = "materials"
        self.marketFilter = "opportunities"
    elseif requestedView == "orders" then
        self.viewMode = "materials"
    end
    self.lastMessage = ""
    self.selectedResult = nil
    if not self.frame then self:Create() end
    if self.moreMenu then self.moreMenu:Hide() end
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
    if ui.viewMode == "opportunities" or ui.viewMode == "orders" then
        self.viewMode = "materials"
        self.marketFilter = "opportunities"
    end
    self.sortColumn = ui.sortColumn
    self.sortAscending = ui.sortAscending ~= false
    self.marketFilter = self.marketFilter or ui.marketFilter or "all"
    local viewState = type(ui.views) == "table" and ui.views[self.viewMode] or {}
    self.hiddenColumns = type(viewState.hiddenColumns) == "table" and viewState.hiddenColumns or {}
    for _, columnKey in ipairs({ "priceChangePercent", "totalQuantity", "opportunityType", "discount", "profit" }) do
        if self.hiddenColumns[columnKey] == nil then self.hiddenColumns[columnKey] = true end
    end
    self.professionFilter = ui.professionFilter and ui.professionFilter ~= "all" and ui.professionFilter or nil
    self.opportunityDirection = ui.opportunityDirection or "all"
    self.minimumOpportunityPercent = tonumber(ui.minimumOpportunityPercent) or 0
    self.frame:SetSize(tonumber(ui.width) or 780, tonumber(ui.height) or 600)
    self.frame:SetPoint("CENTER", UIParent, "CENTER", tonumber(ui.x) or 0, tonumber(ui.y) or 0)
    self.frame:SetFrameStrata("DIALOG")
    self.frame:SetClampedToScreen(true)
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

    self.watchButton = Button(self.frame, nil, "Beobachten", 112, 24)
    self.watchButton:SetPoint("LEFT", self.matsButton, "RIGHT", 8, 0)
    self.watchButton:SetScript("OnClick", function() self:SetView("watched") end)

    self.moreButton = Button(self.frame, nil, "Mehr", 70, 24)
    self.moreButton:SetPoint("LEFT", self.watchButton, "RIGHT", 8, 0)

    self.scanButton = Button(self.frame, nil, "Scannen", 120, 24)
    self.scanButton:SetPoint("TOPRIGHT", -18, -70)
    self.scanButton:SetScript("OnClick", function()
        if AHT.Scanner.running or AHT.Scanner.marketDiscovery or AHT.Scanner.replication then
            AHT.Scanner:Stop("user")
        elseif self.viewMode == "recipes" or self.viewMode == "transmute" then
            local targets = AHT.Scanner:BuildSelectedRecipeTargets()
            if #targets == 0 then
                self:AddMessage("Keine Rezepte markiert. Markiere zuerst Rezepte in der Tabelle.")
            else
                AHT.Scanner:Start(targets, "selected_recipes")
            end
        elseif self.viewMode == "materials" then
            AHT.Scanner:StartMarketDiscovery()
        elseif self.viewMode == "watched" then
            local targets = AHT.Scanner:BuildSelectedWatchTargets()
            if #targets == 0 then
                self:AddMessage("Keine Items markiert. Markiere zuerst Items in Beobachten.")
            else
                AHT.Scanner:Start(targets, "watched")
            end
        end
        self:RefreshStatus()
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
    self.opportunityMinimumButton = Button(self.frame, nil, "Vorteil >= 0%", 124, 24)
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
        if self.frame and self.frame:IsShown() then self:RequestRefresh() end
    end)
    self.searchInput:SetScript("OnEscapePressed", function(box)
        box:SetText("")
        box:ClearFocus()
    end)
    self.searchInput:SetScript("OnEnterPressed", function(box)
        AHT.Commerce:RememberSearch(box:GetText())
        box:ClearFocus()
    end)
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
    self.scroll:SetPoint("BOTTOMRIGHT", -34, 174)
    self.content = CreateFrame("Frame", nil, self.scroll)
    self.content:SetSize(TABLE_WIDTH, 420)
    self.scroll:SetScrollChild(self.content)

    self.detailPanel = CreateFrame("Frame", nil, self.frame, template)
    self.detailPanel:SetPoint("BOTTOMLEFT", 18, 10)
    self.detailPanel:SetPoint("BOTTOMRIGHT", -34, 10)
    self.detailPanel:SetHeight(152)
    self.detailPanel:SetFrameLevel(self.frame:GetFrameLevel() + 2)
    MakeBackdrop(self.detailPanel)
    self.detailTitle = Label(self.detailPanel, "Auswahl")
    self.detailTitle:SetPoint("TOPLEFT", 10, -7)
    self.detailTitle:SetPoint("TOPRIGHT", self.detailPanel, "TOPRIGHT", -282, -7)
    self.detailTitle:SetFontObject("GameFontHighlight")
    self.detailTitle:SetTextColor(1, 0.84, 0.35)
    self.detailScroll = CreateFrame("ScrollFrame", nil, self.detailPanel, "UIPanelScrollFrameTemplate")
    self.detailScroll:SetPoint("TOPLEFT", 10, -28)
    self.detailScroll:SetPoint("BOTTOMRIGHT", -282, 10)
    self.detailContent = CreateFrame("Frame", nil, self.detailScroll)
    self.detailContent:SetSize(math.max(360, self.frame:GetWidth() - 364), 82)
    self.detailScroll:SetScrollChild(self.detailContent)
    self.detailRows = {}
    self.detailAction = Button(self.detailPanel, nil, "Kaufplan", 118, 25)
    self.detailAction:SetPoint("RIGHT", -130, 0)
    self.detailAction:SetScript("OnClick", function()
        local result = self.selectedResult
        if not result then return end
        if result.kind == "order" then self:ShowOrderActions(result.order)
        elseif result.kind == "opportunity" then self:ShowOpportunityActions(result)
        elseif result.kind == "material" then self:ShowMaterialActions(result)
        elseif result.output then self:ShowBuyDialog(result) end
    end)
    self.detailSearch = Button(self.detailPanel, nil, "Im AH suchen", 112, 25)
    self.detailSearch:SetPoint("RIGHT", -10, 0)
    self.detailSearch:SetScript("OnClick", function()
        if self.selectedResult then self:OpenResultInAuctionHouse(self.selectedResult) end
    end)

    self.scroll:HookScript("OnVerticalScroll", function() self:RenderVisibleRows() end)
    self.frame:SetScript("OnSizeChanged", function()
        if self.content then self:RequestRefresh() end
        if self.detailRows then self:RefreshDetail() end
    end)
    self:CreateRows()
    self:RestoreViewState(self.viewMode)
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
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", 5, 0)
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
        if row.scanCheckbox and row.scanCheckbox:IsMouseOver() then return end
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
    return row
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
    if entry.vendor then
        local price = tonumber(entry.vendor.unitPrice)
        return price ~= nil and ("Händlerware: " .. AHT:FormatMoneyPlain(price) .. "/Stk; nicht im AH gesucht.")
            or "Händlerware; Preis am Händler prüfen. Nicht im AH gesucht."
    end
    if entry.loading then return "Listings werden geladen..." end
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
    if #entry.results > 8 then table.insert(parts, "...") end
    return "Listings: " .. table.concat(parts, " | ")
end

function AHT.UI:RecalculateAHRecipeEntries()
    local crafts = math.max(1, tonumber(self.ahCraftCrafts) or 1)
    for _, entry in ipairs(self.ahCraftMaterials or {}) do
        local counts = AHT.Inventory and AHT.Inventory:GetCount(entry.itemID) or { bags = 0, bank = 0, total = 0, bankKnown = false }
        entry.required = (tonumber(entry.quantityPerCraft) or 1) * crafts
        entry.bags = counts.accountBags or counts.bags or 0
        entry.bank = counts.accountBank or counts.bank or 0
        entry.bankKnown = counts.accountBankKnown
        entry.characterCount = counts.characterCount or 1
        entry.owned = counts.total or 0
        entry.toBuy = math.max(0, entry.required - entry.owned - (entry.purchasedQuantity or 0))
        entry.plan = nil
        entry.estimated = nil
        if entry.vendor then
            entry.cheapest = tonumber(entry.vendor.unitPrice)
            if entry.cheapest ~= nil then entry.estimated = entry.toBuy * entry.cheapest end
        elseif entry.loaded and entry.results and entry.toBuy > 0 and AHT.Buyer then
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
        "Suche aktuelle Listings...")
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
            "%s%s | benötigt: %d | Bestand: %d | zu kaufen: %d",
            tostring(entry.name or entry.itemID),
            entry.vendor and " (Händler)" or "",
            entry.required or 0,
            entry.owned or 0,
            entry.toBuy or 0
        ))
        local bankText = entry.bankKnown and tostring(entry.bank or 0) or "?"
        local estimate = entry.estimated and AHT:FormatMoneyPlain(entry.estimated) or "?"
        row.details:SetText(string.format(
            "pro Herstellung: %d | Taschen aller Figuren: %d | Banken: %s | geschätzt: %s",
            entry.quantityPerCraft or 1, entry.bags or 0, bankText, estimate
        ))
        row.listings:SetText(AHRecipeListingText(entry))
        if entry.error then
            row.details:SetText(row.details:GetText() .. "\nFehler: " .. tostring(entry.error))
        end
        if entry.vendor then
            row.buy:SetText("Beim Händler")
            row.buy:Disable()
        elseif not AHT.AHOpen then
            row.buy:SetText("AH geschlossen")
            row.buy:Disable()
        elseif entry.buyState == "confirm" then
            row.buy:SetText("Preis bestätigen")
            row.buy:Enable()
        elseif entry.buyState == "ready" then
            row.buy:SetText("Kauf auslösen")
            row.buy:Enable()
        elseif entry.buyState == "checking" then
            row.buy:SetText("Preisprüfung...")
            row.buy:Disable()
        elseif entry.buyState == "error" then
            row.buy:SetText("Erneut prüfen")
            row.buy:Enable()
        elseif entry.buyState == "buying" or entry.buyState == "submitted" then
            row.buy:SetText("Kauf läuft...")
            row.buy:Disable()
        elseif entry.buyState == "done" or (entry.toBuy or 0) <= 0 then
            row.buy:SetText("Bestand reicht")
            row.buy:Disable()
        elseif not entry.loaded then
            row.buy:SetText("Lade...")
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
    self.ahRecipeStatus = "Suche aktuelle Listings für Ergebnis und Materialien..."
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
        if entry.kind == "material" then
            local vendor = AHT.Commerce and AHT.Commerce:GetVendorInfo(entry.itemID, entry.name)
            if vendor then
                entry.vendor = vendor
                entry.loading, entry.loaded, entry.results = false, true, {}
                entry.meta, entry.error = { totalQuantity = 0 }, nil
                index = index + 1
                self:RecalculateAHRecipeEntries()
                self:RenderAHRecipePanel()
                Next()
                return
            end
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
    local vendor = AHT.Commerce and AHT.Commerce:GetVendorInfo(entry.itemID, entry.name)
    if vendor then
        entry.vendor = vendor
        entry.buyState = nil
        entry.error = "Händlerware wird nicht im Auktionshaus gekauft."
        self.ahRecipeStatus = "Dieses Material bitte beim Händler besorgen; es wird im AH übersprungen."
        self:RenderAHRecipePanel()
        return false
    end
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
    local visible = math.min(64, math.max(8, math.ceil((self.scroll:GetHeight() or 300) / ROW_HEIGHT) + 2))
    for index = #self.rows + 1, visible do self:CreateRow(index) end
end

function AHT.UI:CreateRows()
    self:EnsureRows(24)
end

function AHT.UI:GetActiveColumns()
    local source = (self.viewMode == "materials" or self.viewMode == "watched") and MATERIAL_COLUMNS
        or self.viewMode == "opportunities" and OPPORTUNITY_COLUMNS
        or self.viewMode == "orders" and ORDER_COLUMNS or RECIPE_COLUMNS
    local columns = {}
    for _, column in ipairs(source) do
        local chanceColumn = column.key == "opportunityType" or column.key == "discount" or column.key == "profit"
        local showChanceColumns = self.viewMode == "materials" and self.marketFilter == "opportunities"
        if not column.optional or not (self.hiddenColumns or {})[column.key] or (chanceColumn and showChanceColumns) then
            table.insert(columns, column)
        end
    end
    return columns
end

function AHT.UI:EnsureSortColumn()
    local columns = self:GetActiveColumns()
    for _, column in ipairs(columns) do
        if column.key == self.sortColumn then return end
    end
    if self.viewMode == "materials" then
        self.sortColumn = self.marketFilter == "opportunities" and "discount" or "currentPrice"
        self.sortAscending = false
    elseif self.viewMode == "opportunities" then
        self.sortColumn = "profit"
        self.sortAscending = false
    elseif self.viewMode == "orders" then
        self.sortColumn = "createdAt"
        self.sortAscending = false
    else
        self.sortColumn = "profitPerOutput"
        self.sortAscending = false
    end
end

function AHT.UI:LayoutTable()
    local columns = self:GetActiveColumns()
    local recipeRows = self.viewMode == "recipes" or self.viewMode == "transmute" or self.viewMode == "watched"
    local width = math.max(700, (self.frame:GetWidth() or 780) - 80)
    local total = 0
    for _, column in ipairs(columns) do total = total + column.width end
    self.content:SetWidth(width)
    self.tableHeader:SetWidth(width)
    local offset = 0
    for index, column in ipairs(columns) do
        local cellWidth = width * column.width / total
        local header = self.headers[index]
        header:ClearAllPoints()
        header:SetWidth(cellWidth)
        header:SetPoint("LEFT", offset, 0)
        if index == 1 then
            header.label:ClearAllPoints()
            header.label:SetPoint("LEFT", recipeRows and 47 or 7, 0)
            header.label:SetPoint("RIGHT", -7, 0)
        end
        for _, row in ipairs(self.rows) do
            row:SetWidth(width)
            row.info:SetWidth(width - 36)
            local cell = row.cells[index]
            cell:ClearAllPoints()
            cell:SetPoint("LEFT", offset + (index == 1 and (recipeRows and 47 or 28) or 6), 0)
            cell:SetWidth(cellWidth - (index == 1 and (recipeRows and 55 or 34) or 12))
            cell:SetJustifyH(index == 1 and "LEFT" or "RIGHT")
        end
        offset = offset + cellWidth
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
    local tableMode = self.viewMode == "recipes" or self.viewMode == "transmute" or self.viewMode == "materials" or self.viewMode == "watched" or self.viewMode == "orders" or self.viewMode == "opportunities"
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
            marker = self.sortAscending and "  |cff66ff66[A]|r" or "  |cffffaa44[D]|r"
        end
        local label = column.label
        header.label:SetText(label .. marker)
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
    if self.viewMode == "materials" or self.viewMode == "watched" then
        if self.marketFilter == "watched" and not result.isWatched then return false end
        if self.marketFilter == "inventory" and not result.inInventory then return false end
        if self.marketFilter == "opportunities" then
            if not result.opportunityType then return false end
            if self.opportunityDirection and self.opportunityDirection ~= "all"
                    and result.side ~= self.opportunityDirection then return false end
            local minimum = tonumber(self.minimumOpportunityPercent) or 0
            if minimum > 0 and (tonumber(result.discount) or 0) < minimum then return false end
        end
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

function AHT.UI:RenderDetailRows(rows)
    local frameWidth = self.frame and self.frame:GetWidth() or 780
    local width = math.max(360, frameWidth - 364)
    local height = math.max(DETAIL_ROW_HEIGHT, #rows * DETAIL_ROW_HEIGHT)
    self.detailContent:SetSize(width, height)

    for index, rowData in ipairs(rows) do
        local row = self.detailRows[index]
        if not row then
            row = CreateFrame("Frame", nil, self.detailContent)
            row.bg = row:CreateTexture(nil, "BACKGROUND")
            row.bg:SetAllPoints(row)
            row.rule = row:CreateTexture(nil, "BORDER")
            row.rule:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
            row.rule:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
            row.rule:SetHeight(1)
            row.cells = {}
            for column = 1, 4 do
                row.cells[column] = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
            end
            self.detailRows[index] = row
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.detailContent, "TOPLEFT", 0, -((index - 1) * DETAIL_ROW_HEIGHT))
        row:SetSize(width, DETAIL_ROW_HEIGHT)
        row:Show()

        if rowData.kind == "header" then
            row.bg:SetColorTexture(0.18, 0.11, 0.035, 1)
            row.rule:SetColorTexture(0.85, 0.58, 0.18, 0.9)
        elseif rowData.kind == "section" then
            row.bg:SetColorTexture(0.12, 0.08, 0.025, 1)
            row.rule:SetColorTexture(0.48, 0.32, 0.1, 0.8)
        else
            local shade = index % 2 == 0 and 0.055 or 0.035
            row.bg:SetColorTexture(shade, shade * 0.78, shade * 0.5, 0.95)
            row.rule:SetColorTexture(0.25, 0.19, 0.1, 0.55)
        end

        local values = rowData.values or {}
        local widths = rowData.widths or DETAIL_PAIR_WIDTHS
        local offset = 0
        for column, cell in ipairs(row.cells) do
            cell:ClearAllPoints()
            cell:SetHeight(DETAIL_ROW_HEIGHT)
            if cell.SetWordWrap then cell:SetWordWrap(false) end
            if rowData.kind == "section" or rowData.kind == "message" then
                if column == 1 then
                    cell:SetPoint("LEFT", row, "LEFT", 7, 0)
                    cell:SetWidth(width - 14)
                else
                    cell:SetPoint("LEFT", row, "LEFT", width, 0)
                    cell:SetWidth(1)
                end
            else
                local columnWidth = width * (widths[column] or 0.25)
                cell:SetPoint("LEFT", row, "LEFT", offset + 6, 0)
                cell:SetWidth(math.max(1, columnWidth - 12))
                local leftAligned = rowData.kind == "header" or column == 1 or (rowData.kind == "metric" and column == 3)
                cell:SetJustifyH(leftAligned and "LEFT" or "RIGHT")
                offset = offset + columnWidth
            end

            cell:SetText(values[column] or "")
            if rowData.kind == "header" or rowData.kind == "section" then
                cell:SetFontObject("GameFontHighlightSmall")
                cell:SetTextColor(1, 0.84, 0.35)
            elseif rowData.kind == "message" then
                cell:SetFontObject("GameFontNormalSmall")
                cell:SetTextColor(0.85, 0.82, 0.74)
            elseif column == 2 or column == 4 then
                cell:SetFontObject("GameFontHighlightSmall")
                cell:SetTextColor(0.92, 0.89, 0.8)
            else
                cell:SetFontObject("GameFontNormalSmall")
                cell:SetTextColor(0.78, 0.72, 0.59)
            end
        end
    end

    for index = #rows + 1, #self.detailRows do
        self.detailRows[index]:Hide()
    end
    self.detailScroll:SetVerticalScroll(0)
end

function AHT.UI:RefreshDetail()
    if not self.detailPanel then return end
    local result = self.selectedResult
    if not result then
        self.detailTitle:SetText("Auswahl")
        self:RenderDetailRows({ { kind = "message", values = { "Wähle einen Eintrag für Preise, Marktverlauf, Zutaten und Bestand." } } })
        self.detailAction:Disable()
        self.detailSearch:Hide()
        return
    end

    local metrics, extraRows = {}, {}
    local searchable = false
    local function AddMetric(label, value)
        table.insert(metrics, { label, tostring(value or "-") })
    end

    if result.kind == "material" then
        local counts = AHT.Inventory and AHT.Inventory:GetCount(result.itemID) or { bags = 0, bank = 0, bankKnown = false }
        AddMetric("Aktuell", PriceText(result.currentPrice))
        AddMetric("Marktwert", PriceText(result.marketValue))
        AddMetric("Ø AH", PriceText(result.averagePrice))
        AddMetric("Abweichung", PercentText(result.marketTrendPercent))
        AddMetric("Änderung", PercentText(result.priceChangePercent))
        AddMetric("Listings", result.listingCount or "?")
        AddMetric("Angebot", result.totalQuantity or "?")
        AddMetric(string.format("Bestand (%d Figuren)", counts.characterCount or 1), string.format("Taschen %d / Banken %s", counts.accountBags or counts.bags or 0, counts.accountBankKnown and tostring(counts.accountBank or 0) or "?"))
        if not counts.poolKnown then AddMetric("Inventarpool", "Nur aktueller Charakter") end
        AddMetric("Scanalter", ScanAgeText(result.updatedAt))
        self.detailAction:SetText("Aktionen")
        searchable = true
    elseif result.kind == "opportunity" then
        local direction = result.side == "sell" and "Verkauf" or "Kauf"
        AddMetric("Richtung", direction)
        AddMetric("Aktuell", PriceText(result.currentPrice))
        AddMetric("Marktwert", PriceText(result.marketValue))
        AddMetric("Vorteil", PercentText(result.discount))
        AddMetric("Netto", PriceText(result.profit or result.netIncome))
        AddMetric("ROI", PercentText(result.roi))
        AddMetric("Angebot", result.quantity or 0)
        AddMetric("Samples", result.sampleCount or result.marketSamples or 0)
        AddMetric("Scanalter", ScanAgeText(result.updatedAt))
        self.detailAction:SetText(result.side == "sell" and "Verkaufsplan" or "Kaufchance")
        searchable = result.itemID ~= nil
    elseif result.kind == "order" then
        local order = result.order or {}
        AddMetric("Vorgänge", result.crafts or 0)
        AddMetric("Status", result.statusText or "?")
        AddMetric("Offen", result.remainingCount or 0)
        AddMetric("Ausgegeben", PriceText(result.spent or 0))
        if #(order.requirements or {}) > 0 then
            table.insert(extraRows, { kind = "section", values = { "EINKAUFSMATERIALIEN" } })
            table.insert(extraRows, { kind = "header", values = { "Material", "Gekauft", "Zu kaufen", "Ausgegeben" }, widths = DETAIL_ORDER_WIDTHS })
            for _, requirement in ipairs(order.requirements) do
                local itemName = requirement.name or AHT:GetItemInfo(requirement.itemID) or tostring(requirement.itemID)
                table.insert(extraRows, {
                    kind = "ingredient",
                    widths = DETAIL_ORDER_WIDTHS,
                    values = { itemName, requirement.bought or 0, requirement.toBuy or requirement.quantity or 0, PriceText(requirement.spent or 0) },
                })
            end
        end
        self.detailAction:SetText("Auftrag öffnen")
    else
        local output = result.output or {}
        local snapshot = result.marketSnapshot or (output.itemID and AHT.Store:GetMarketSnapshot(output.itemID))
        local sale = result.currentSalePrice or result.salePrice
        AddMetric("Kosten/Stk", PriceText(result.ingredientCost))
        AddMetric("Aktuell/Stk", PriceText(sale))
        AddMetric("Marktwert", PriceText(result.marketSalePrice))
        AddMetric("Ø AH", PriceText(snapshot and snapshot.averagePrice))
        AddMetric("Netto/Stk", PriceText(result.profit))
        AddMetric("Marge", result.margin and string.format("%.1f%%", result.margin) or "-")
        AddMetric("Änderung", PercentText(snapshot and snapshot.priceChangePercent))
        AddMetric("Trend", PercentText(snapshot and snapshot.trendPercent))
        AddMetric("Vorschlag", string.format("%d Vorgänge", result.suggestedCrafts or 0))
        AddMetric("Scanalter", ScanAgeText(snapshot and snapshot.updatedAt))

        local crafts = math.max(1, tonumber(result.suggestedCrafts) or 0)
        if #(result.reagents or {}) > 0 then
            table.insert(extraRows, { kind = "section", values = { string.format("ZUTATEN | %d Vorgänge | Bestand aller Figuren: Taschen/Bank | R/F reserviert/fehlt", crafts) } })
            table.insert(extraRows, { kind = "header", values = { "Zutat", "Bedarf", "AH/Stk", "T/B • R/F" }, widths = DETAIL_INGREDIENT_WIDTHS })
            for _, reagent in ipairs(result.reagents) do
                local quantity = (tonumber(reagent.quantity) or 1) * crafts
                local itemName = reagent.name or AHT:GetItemInfo(reagent.itemID) or tostring(reagent.itemID)
                local price = AHT.Store and AHT.Store:GetPrice(reagent.itemID)
                local count = AHT.Inventory and AHT.Inventory:GetCount(reagent.itemID) or { bags = 0, bank = 0, bankKnown = false }
                local reserved = AHT.Production and AHT.Production:GetReserved(reagent.itemID) or 0
                local accountBags = count.accountBags or count.bags or 0
                local accountBank = count.accountBank or count.bank or 0
                local accountBankKnown = count.accountBankKnown
                local knownStock = accountBags + (accountBankKnown and accountBank or 0)
                local available = math.max(0, knownStock - reserved)
                local missing = available >= quantity and 0 or accountBankKnown and (quantity - available) or "?"
                local stockText = string.format("%d/%s • %d/%s", accountBags,
                    accountBankKnown and tostring(accountBank) or "?", reserved, tostring(missing))
                table.insert(extraRows, {
                    kind = "ingredient",
                    widths = DETAIL_INGREDIENT_WIDTHS,
                    values = { itemName, quantity, PriceText(price), stockText },
                })
            end
        else
            table.insert(extraRows, { kind = "message", values = { "Zutaten und Einkaufspreise sind noch nicht vollständig erfasst." } })
        end
        self.detailAction:SetText("Einkauf planen")
        searchable = output.itemID ~= nil
    end

    local rows = { { kind = "header", values = { "Kennzahl", "Wert", "Kennzahl", "Wert" } } }
    for index = 1, #metrics, 2 do
        local left, right = metrics[index], metrics[index + 1] or { "", "" }
        table.insert(rows, { kind = "metric", values = { left[1], left[2], right[1], right[2] } })
    end
    for _, row in ipairs(extraRows) do table.insert(rows, row) end

    self.detailTitle:SetText(result.name or (result.order and result.order.name) or "Itemdetails")
    self:RenderDetailRows(rows)
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
        local vendorItem = AHT.Commerce and AHT.Commerce:IsVendorItem(reagent.itemID, reagent.name)
        local scanRecord = AHT.Store and AHT.Store:GetByItemID(reagent.itemID)
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
        GameTooltip:AddDoubleLine(
            "  AH zuletzt gescannt",
            vendorItem and "Händlerware (kein AH-Scan)" or ScanAgeText(scanRecord and scanRecord.updatedAt),
            0.62, 0.72, 0.95, 0.45, 1, 0.45
        )
        GameTooltip:AddLine(string.format(
            "  Bestand (%d Figuren): Taschen %d | Banken %s | reserviert %d",
            counts.characterCount or 1,
            counts.accountBags or counts.bags or 0,
            counts.accountBankKnown and tostring(counts.accountBank or 0) or "?",
            reserved
        ), 0.55, 0.72, 0.95)
        if not counts.poolKnown then
            GameTooltip:AddLine("  Realm, Fraktion oder PvP/PvE-Modus nicht erkannt: kein Twink-Abgleich.", 1, 0.55, 0.35)
        elseif not counts.accountBagsKnown then
            GameTooltip:AddLine("  Taschenstände noch unvollständig; einzelne Twinks müssen sich einmal einloggen.", 1, 0.72, 0.35)
        elseif counts.inventoryUpdatedAt then
            GameTooltip:AddLine("  Ältester gespeicherter Bestand: " .. ScanAgeText(counts.inventoryUpdatedAt), 0.65, 0.65, 0.65)
        end
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
    GameTooltip:AddLine(string.format("Angebot: %s Stück / %s Listings", tostring(result.totalQuantity or "?"), tostring(result.listingCount or "?")), 0.62, 0.72, 0.95)
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
    GameTooltip:AddDoubleLine(selling and (result.costBasis and "Gewinn pro Stück" or "Nettoerlös pro Stück") or "Potenzial pro Stück", AHT:FormatMoneyPlain(result.profit or result.netIncome or 0), 0.45, 1, 0.45, 0.45, 1, 0.45)
    GameTooltip:AddDoubleLine("ROI", string.format("%.1f%%", result.roi or 0), 0.78, 0.78, 0.78, 0.45, 1, 0.45)
    GameTooltip:AddLine(string.format("%s %.1f%% | Empfehlung: %s", selling and "Aufschlag" or "Rabatt", result.discount or 0, result.bestMethod or "AH"), 0.78, 0.78, 0.78)
    if selling then
        GameTooltip:AddLine(string.format("Bestand (%d Figuren): Taschen %d | Banken %s", result.characterCount or 1, result.stockBags or 0, result.bankKnown and tostring(result.stockBank or 0) or "?"), 0.62, 0.72, 0.95)
    else
        GameTooltip:AddLine(string.format("AH-Angebotsmenge: %s / %s Listings (nicht Kaufmenge)", tostring(result.availableSupply or "?"), tostring(result.listingCount or "?")), 0.62, 0.72, 0.95)
    end
    GameTooltip:AddLine(string.format("Datenabdeckung %d/100, keine Erfolgswahrscheinlichkeit | %s", result.confidence or 0, AHT.Commerce:SourceText(result.source)), 0.62, 0.62, 0.62)
    GameTooltip:Show()
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
    local scanning = AHT.Scanner and (AHT.Scanner.running or AHT.Scanner.marketDiscovery or AHT.Scanner.replication)
    if self.scanButton then
        local label
        if self.viewMode == "recipes" or self.viewMode == "transmute" then
            label = "Rezepte scannen"
        elseif self.viewMode == "materials" then
            label = "AH scannen"
        elseif self.viewMode == "watched" then
            label = "Items scannen"
        else
            label = "Scannen"
        end
        self.scanButton:SetText(scanning and "Abbrechen" or label)
    end
end

function AHT.UI:BuildMaterialRows(watchedOnly)
    local rows = {}
    local materials = AHT.DB and AHT.DB.materials or {}
    local market = AHT.DB and AHT.DB.market or {}
    local inventorySet = AHT.Inventory and AHT.Inventory:GetAvailableItemSet() or {}
    local seen = {}
    local opportunityIndex = {}
    if not watchedOnly and self.marketFilter == "opportunities" and AHT.Opportunities then
        if AHT.Calculator then AHT.Calculator:Refresh() end
        for _, opportunity in ipairs(AHT.Opportunities:Build() or {}) do
            local itemID = tonumber(opportunity.itemID)
            if itemID then
                local bucket = opportunityIndex[itemID] or {}
                local side = opportunity.side or "all"
                local current = bucket[side]
                if not current or (tonumber(opportunity.profit) or 0) > (tonumber(current.profit) or 0) then
                    bucket[side] = opportunity
                end
                opportunityIndex[itemID] = bucket
            end
        end
    end

    local function AddRow(key, record, material)
        local itemID = tonumber((record and record.itemID) or (material and material.itemID))
        if not itemID then return end
        local rowKey = tostring(key or itemID)
        if seen[rowKey] then return end
        seen[rowKey] = true
        local snapshot = AHT.Store and AHT.Store:GetMarketSnapshot(itemID, record and record.itemKey) or nil
        local updatedAt = snapshot and snapshot.updatedAt or record and tonumber(record.updatedAt) or nil
        local name = UsableItemName(material and material.name) or UsableItemName(record and record.name)
        if not name then name = UsableItemName(AHT:GetItemInfo(itemID)) end
        local opportunity
        local opportunityBucket = opportunityIndex[itemID]
        if opportunityBucket then
            local minimum = tonumber(self.minimumOpportunityPercent) or 0
            local candidates = self.opportunityDirection ~= "all"
                and { opportunityBucket[self.opportunityDirection] }
                or { opportunityBucket.buy, opportunityBucket.sell, opportunityBucket.all }
            for _, candidate in ipairs(candidates) do
                if candidate and (tonumber(candidate.discount) or 0) >= minimum
                        and (not opportunity or (tonumber(candidate.profit) or 0) > (tonumber(opportunity.profit) or 0)) then
                    opportunity = candidate
                end
            end
        end
        table.insert(rows, {
            kind = "material",
            name = name or string.format("Item #%d", itemID),
            nameNeedsCache = name == nil,
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
            listingCount = snapshot and snapshot.listingCount,
            source = snapshot and snapshot.source,
            marketSamples = snapshot and snapshot.marketSamples or 0,
            scanSamples = snapshot and snapshot.scanSamples or 0,
            updatedAt = updatedAt,
            updatedText = updatedAt and date("%d.%m.%y", updatedAt) or "-",
            opportunityType = opportunity and ((opportunity.side == "buy" and "Kauf: " or opportunity.side == "sell" and "Verkauf: " or "") .. tostring(opportunity.opportunityType or "Chance")) or nil,
            side = opportunity and opportunity.side or nil,
            discount = opportunity and opportunity.discount or nil,
            profit = opportunity and opportunity.profit or nil,
            roi = opportunity and opportunity.roi or nil,
            confidence = opportunity and opportunity.confidence or nil,
        })
    end

    if not watchedOnly then
        for key, record in pairs(market) do
            if type(record) == "table" then
                local material = materials[tostring(record.itemID or "")]
                AddRow(key, record, material)
            end
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
        local message = watchedOnly and "Keine beobachteten Items. Füge oben ein Item hinzu."
            or self.marketFilter == "watched" and "Keine beobachteten Items. Füge ein Item über Material hinzu."
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
        vendor_required = "Beim Händler besorgen",
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
    elseif mode == "watched" then
        results = self:SortResults(self:BuildMaterialRows(true))
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
            for _, candidate in ipairs(candidates) do
                candidate.materialScanAt, candidate.materialScanText = self:GetRecipeMaterialScanSummary(candidate)
            end
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
    self.visibleResults = results
    self:EnsureRows(#results)
    self:UpdateHeaders()
    self.content:SetHeight(math.max(self.scroll:GetHeight() or 300, #results * ROW_HEIGHT))
    self:RenderVisibleRows()
    self:SaveViewState()
    self:RefreshDetail()
    self:RefreshControls()
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

function AHT.UI:ShowMaterials()
    self:SetView("materials")
end
