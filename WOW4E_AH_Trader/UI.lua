local AHT = WOW4E_AHT

AHT.UI = {
    rows = {},
    dialogs = {},
    viewMode = "recipes",
    lastMessage = "",
    searchQuery = "",
    profitOnly = false,
}

local function MakeBackdrop(frame)
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
    end
    if frame.SetBackdropColor then frame:SetBackdropColor(0.025, 0.018, 0.012, 0.94) end
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

local RECIPE_COLUMNS = {
    { key = "name", label = "Rezept / Ergebnis", width = 215 },
    { key = "ingredientCost", label = "Kosten", width = 80 },
    { key = "salePrice", label = "Aktuell", width = 80 },
    { key = "marketSalePrice", label = "Marktwert", width = 90 },
    { key = "profit", label = "Gewinn", width = 80 },
    { key = "margin", label = "Marge", width = 70 },
    { key = "suggestedCrafts", label = "Empf.", width = 85 },
}

local MATERIAL_COLUMNS = {
    { key = "name", label = "Material", width = 200 },
    { key = "itemID", label = "Item-ID", width = 70 },
    { key = "currentPrice", label = "Aktuell", width = 90 },
    { key = "marketValue", label = "Marktwert", width = 95 },
    { key = "averagePrice", label = "Ø AH-Preis", width = 100 },
    { key = "priceChangePercent", label = "Scan-Trend", width = 80 },
    { key = "updatedAt", label = "Letzter Scan", width = 75 },
}

local OPPORTUNITY_COLUMNS = {
    { key = "name", label = "Chance / Item", width = 200 },
    { key = "currentPrice", label = "Preis", width = 85 },
    { key = "marketValue", label = "Marktwert", width = 95 },
    { key = "discount", label = "Vorteil", width = 80 },
    { key = "profit", label = "Netto", width = 85 },
    { key = "roi", label = "ROI", width = 70 },
    { key = "quantity", label = "Menge", width = 85 },
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
        help = "Überwachte Materialien mit aktuellem Preis, altersgewichteter Historie und robustem Marktwert.",
    },
    orders = {
        title = "Aufträge",
        help = "Reservierte Materialien und bereits gekaufte Zutaten je Herstellungsauftrag.",
    },
    opportunities = {
        title = "Chancen",
        help = "Kauf- und Verkaufschancen aus aktuellem AH-Preis, robustem Marktwert und deinem Bestand.",
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
    if AHT.Store then AHT.Store:Save() end
end

function AHT.UI:UpdateNavigation()
    local primary = {
        recipes = self.recipeButton,
        transmute = self.transmuteButton,
        materials = self.matsButton,
        orders = self.ordersButton,
        opportunities = self.opportunityButton,
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
        if searchable then self.filterButton:Show() else self.filterButton:Hide() end
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
    if self.filterButton then self.filterButton:SetText(self.profitOnly and "Alle" or "Nur profitabel") end
end

function AHT.UI:SetView(viewMode)
    self.viewMode = VIEW_INFO[viewMode] and viewMode or "recipes"
    if not self.frame then self:Create() end
    if self.moreMenu then self.moreMenu:Hide() end
    self:RefreshControls()
    self:UpdateNavigation()
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

    self.scanButton = Button(self.frame, nil, "AH Scan", 100, 24)
    self.scanButton:SetPoint("TOPLEFT", 18, -70)
    self.scanButton:SetScript("OnClick", function()
        if AHT.Scanner.running then AHT.Scanner:Stop("user") else AHT.Scanner:Start() end
        self:RefreshStatus()
    end)

    self.recipeButton = Button(self.frame, nil, "Herstellen", 100, 24)
    self.recipeButton:SetPoint("LEFT", self.scanButton, "RIGHT", 8, 0)
    self.recipeButton:SetScript("OnClick", function()
        self:SetView("recipes")
        if AHT.Recipes then AHT.Recipes:Refresh() end
    end)

    self.matsButton = Button(self.frame, nil, "Markt", 100, 24)
    self.matsButton:SetPoint("LEFT", self.recipeButton, "RIGHT", 8, 0)
    self.matsButton:SetScript("OnClick", function() self:SetView("materials") end)

    self.transmuteButton = Button(self.frame, nil, "Transmute", 100, 24)
    self.transmuteButton:SetPoint("LEFT", self.matsButton, "RIGHT", 8, 0)
    self.transmuteButton:SetScript("OnClick", function()
        self:SetView("transmute")
    end)

    self.reputationButton = Button(self.frame, nil, "Ruf", 70, 24)
    self.reputationButton:SetPoint("LEFT", self.transmuteButton, "RIGHT", 8, 0)
    self.reputationButton:SetScript("OnClick", function()
        self:SetView("reputation")
    end)

    self.debugButton = Button(self.frame, nil, "Debug", 80, 24)
    self.debugButton:SetPoint("LEFT", self.reputationButton, "RIGHT", 8, 0)
    self.debugButton:SetScript("OnClick", function()
        self:SetView("diagnostics")
    end)

    self.ordersButton = Button(self.frame, nil, "Aufträge", 90, 24)
    self.ordersButton:SetPoint("LEFT", self.transmuteButton, "RIGHT", 8, 0)
    self.ordersButton:SetScript("OnClick", function()
        self:SetView("orders")
    end)

    self.reputationButton:Hide()
    self.debugButton:Hide()

    self.opportunityButton = Button(self.frame, nil, "Chancen", 85, 24)
    self.opportunityButton:SetPoint("LEFT", self.ordersButton, "RIGHT", 8, 0)
    self.opportunityButton:SetScript("OnClick", function() self:SetView("opportunities") end)

    self.moreButton = Button(self.frame, nil, "Mehr", 70, 24)
    self.moreButton:SetPoint("LEFT", self.opportunityButton, "RIGHT", 8, 0)

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
        self.profitOnly = not self.profitOnly
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
    self.scroll:SetPoint("BOTTOMRIGHT", -34, 18)
    self.content = CreateFrame("Frame", nil, self.scroll)
    self.content:SetSize(TABLE_WIDTH, 420)
    self.scroll:SetScrollChild(self.content)

    self:CreateRows()
    self:RefreshControls()
    self:UpdateNavigation()
    self:Refresh()
end

function AHT.UI:CreateRow(index)
    local row = CreateFrame("Button", nil, self.content)
    local rowIndex = index
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
        if button == "LeftButton" and type(IsShiftKeyDown) == "function" and IsShiftKeyDown() then
            if row.result and row.result.kind ~= "info" and row.result.kind ~= "order" then
                self:OpenResultInAuctionHouse(row.result)
            end
            return
        end
        if row.result and row.result.kind == "order" then
            self:ShowOrderActions(row.result.order)
        elseif row.result and row.result.kind == "opportunity" then
            self:ShowOpportunityActions(row.result)
        elseif row.result and row.result.kind == "material" then
            self:ShowMaterialActions(row.result)
        elseif row.result and row.result.kind ~= "info" then
            self:ShowRecipeActions(row.result)
        end
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
        row.bg:SetColorTexture(rowIndex % 2 == 0 and 0.045 or 0.065, 0.032, 0.018, 0.82)
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
    self.scroll:SetPoint("BOTTOMRIGHT", -34, 18)
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
    if self.profitOnly and result.kind ~= "order" then
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
    local state = AHT.State.status or "?"
    local progress = ""
    if AHT.Scanner and AHT.Scanner.running then
        progress = string.format(" | %d/%d", AHT.Scanner.completed, AHT.Scanner.total)
    end
    local view = VIEW_INFO[self.viewMode] or VIEW_INFO.recipes
    self.status:SetText("Ansicht: " .. view.title .. " | Status: " .. state .. progress)
    if self.viewTitle then self.viewTitle:SetText(view.title) end
    local help = view.help
    if self.lastMessage ~= "" then help = help .. " | " .. self.lastMessage end
    if self.viewHelp then self.viewHelp:SetText(help) end
    self.scanButton:SetText(AHT.Scanner and AHT.Scanner.running and "Abbrechen" or "AH Scan")
end

function AHT.UI:BuildMaterialRows()
    local rows, materials = {}, AHT.DB and AHT.DB.materials or {}
    local list = {}
    for _, material in pairs(materials) do table.insert(list, material) end
    table.sort(list, function(a, b)
        return tostring(a.name or a.itemID) < tostring(b.name or b.itemID)
    end)
    for _, material in ipairs(list) do
        local record = AHT.Store and AHT.Store:GetByItemID(material.itemID)
        local snapshot = AHT.Store and AHT.Store:GetMarketSnapshot(material.itemID) or nil
        local currentPrice = snapshot and snapshot.currentPrice or record and tonumber(record.minPrice) or nil
        local averagePrice = snapshot and snapshot.averagePrice or AHT.Store and AHT.Store:RecencyAverage(material.itemID) or nil
        local marketValue = snapshot and snapshot.marketValue or nil
        local priceChangePercent = snapshot and snapshot.priceChangePercent or nil
        local marketTrendPercent = snapshot and snapshot.trendPercent or nil
        local updatedAt = snapshot and snapshot.updatedAt or record and tonumber(record.updatedAt) or nil
        local updatedText = updatedAt and date("%d.%m.%y", updatedAt) or "-"
        table.insert(rows, {
            kind = "material",
            name = material.name or "?",
            itemID = tonumber(material.itemID) or material.itemID,
            currentPrice = currentPrice,
            marketValue = marketValue,
            averagePrice = averagePrice,
            priceChangePercent = priceChangePercent,
            marketTrendPercent = marketTrendPercent,
            trendText = priceChangePercent and string.format("%+.1f%%", priceChangePercent) or "-",
            p25 = snapshot and snapshot.p25,
            p75 = snapshot and snapshot.p75,
            totalQuantity = snapshot and snapshot.totalQuantity or 0,
            listingCount = snapshot and snapshot.listingCount or 0,
            marketSamples = snapshot and snapshot.marketSamples or 0,
            updatedAt = updatedAt,
            updatedText = updatedText,
        })
    end
    if #rows == 0 then
        table.insert(rows, { kind = "info", text = "Keine Materialien. Item-Link oder Item-ID oben eingeben und + Mat drücken." })
    end
    return rows
end

function AHT.UI:BuildOpportunityRows()
    -- Opportunity rows use current recipe cost as an optional sell basis.
    if AHT.Calculator then AHT.Calculator:Refresh() end
    local rows = AHT.Opportunities and AHT.Opportunities:Build() or {}
    if #rows == 0 then
        table.insert(rows, { kind = "info", text = "Keine Kauf- oder Verkaufschance gefunden. AH öffnen und 'AH Scan' ausführen; Verkaufschancen benötigen außerdem Bestand in Tasche oder Bank." })
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
        results = mode == "transmute" and AHT.Calculator and AHT.Calculator:CalculateTransmutes() or (AHT.Calculator and AHT.Calculator.results)
        results = results or {}
        results = self:SortResults(results)
        if #results == 0 then
            results = {{ kind = "info", text = mode == "transmute" and "Keine Transmutationsrezepte erkannt. Öffne das Berufsfenster und aktualisiere die Rezepte." or "Keine Rezepte erkannt. Öffne das Berufsfenster und aktualisiere die Rezepte." }}
        end
    end
    if #results == 0 then
        results = {{ kind = "info", text = "Keine Treffer für die aktuelle Suche oder den Filter." }}
    end
    self:EnsureRows(#results)
    self:UpdateHeaders()
    self.content:SetHeight(math.max(420, #results * ROW_HEIGHT))
    for index, row in ipairs(self.rows) do
        local result = results[index]
        row.result = result
        if result then
            for cellIndex = 1, MAX_COLUMNS do row.cells[cellIndex]:SetTextColor(1, 1, 1) end
            if result.kind == "info" then
                row.info:SetText(result.text or "")
                row.info:Show()
                for index = 1, MAX_COLUMNS do row.cells[index]:Hide() end
                row:EnableMouse(true)
            elseif result.kind == "material" then
                row.info:Hide()
                row.cells[1]:SetText(result.name or "?")
                row.cells[2]:SetText(tostring(result.itemID or "?"))
                row.cells[3]:SetText(result.currentPrice and AHT:FormatMoneyPlain(result.currentPrice) or AHT.L.noData)
                row.cells[4]:SetText(result.marketValue and AHT:FormatMoneyPlain(result.marketValue) or AHT.L.noData)
                row.cells[5]:SetText(result.averagePrice and AHT:FormatMoneyPlain(result.averagePrice) or AHT.L.noData)
                row.cells[6]:SetText(result.trendText or "-")
                row.cells[7]:SetText(result.updatedText or "-")
                for index = 1, #MATERIAL_COLUMNS do row.cells[index]:Show() end
                for index = #MATERIAL_COLUMNS + 1, MAX_COLUMNS do row.cells[index]:Hide() end
                row.cells[3]:SetTextColor(1, 0.85, 0.4)
                row.cells[4]:SetTextColor(0.45, 1, 0.55)
                row.cells[5]:SetTextColor(0.45, 1, 0.55)
                row:EnableMouse(true)
            elseif result.kind == "opportunity" then
                row.info:Hide()
                local marker = result.side == "sell" and "▼ Verkaufen: " or "▲ Kaufen: "
                row.cells[1]:SetText(marker .. (result.name or "?"))
                row.cells[2]:SetText(AHT:FormatMoneyPlain(result.currentPrice or 0))
                row.cells[3]:SetText(result.marketValue and AHT:FormatMoneyPlain(result.marketValue) or "-")
                row.cells[4]:SetText(string.format("%.1f%%", result.discount or 0))
                row.cells[5]:SetText(result.profit and AHT:FormatMoneyPlain(result.profit) or "-")
                row.cells[6]:SetText(string.format("%.1f%%", result.roi or 0))
                row.cells[7]:SetText(tostring(result.quantity or 0))
                for index = 1, #OPPORTUNITY_COLUMNS do row.cells[index]:Show() end
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
                local marketText = result.marketSalePrice and AHT:FormatMoneyPlain(result.marketSalePrice) or "?"
                local prefix = result.isDeal and "★ " or ""
                row.info:Hide()
                row.cells[1]:SetText(prefix .. (result.name or "?"))
                row.cells[2]:SetText(cost)
                row.cells[3]:SetText(currentText)
                row.cells[4]:SetText(marketText)
                row.cells[5]:SetText(profit)
                row.cells[6]:SetText(margin)
                row.cells[7]:SetText((result.suggestedCrafts or 0) > 0 and tostring(result.suggestedCrafts) or "-")
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
                row.cells[4]:SetTextColor(0.45, 0.85, 1)
                if result.profit and result.profit >= 0 then
                    row.cells[5]:SetTextColor(0.35, 1, 0.35)
                else
                    row.cells[5]:SetTextColor(1, 0.45, 0.35)
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
    self:RefreshStatus()
end

function AHT.UI:Show()
    if not self.frame then self:Create() end
    self:RestoreFrameStrata()
    AHT:Refresh()
    self.frame:Show()
end

function AHT.UI:ShowAHButton()
    local auctionHouse = _G.AuctionHouseFrame
    local parent = auctionHouse or UIParent
    if not self.ahButton then
        self.ahButton = Button(parent, "WOW4E_AH_Trader_AHButton", "AH Trader", 100, 24)
        self.ahButton:SetScript("OnClick", function() self:Show() end)
    else
        self.ahButton:SetParent(parent)
    end
    self.ahButton:ClearAllPoints()
    if auctionHouse then
        -- Keep the button below the AH title bar. The old top-right anchor
        -- placed it behind the header/search controls in the Forever client.
        self.ahButton:SetPoint("TOPLEFT", auctionHouse, "TOPLEFT", 92, -50)
        self.ahButton:SetFrameStrata(auctionHouse:GetFrameStrata() or "HIGH")
        self.ahButton:SetFrameLevel((auctionHouse:GetFrameLevel() or 1) + 10)
    else
        self.ahButton:SetPoint("TOP", UIParent, "TOP", 0, -90)
        self.ahButton:SetFrameStrata("HIGH")
    end
    self.ahButton:Show()
end

function AHT.UI:HideAHButton()
    if self.ahButton then self.ahButton:Hide() end
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
        if status == "awaiting_confirmation" then
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
