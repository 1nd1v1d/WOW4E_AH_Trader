local AHT = WOW4E_AHT

AHT.UI = { rows = {}, dialogs = {}, viewMode = "recipes", lastMessage = "" }

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

local RECIPE_COLUMNS = {
    { key = "name", label = "Rezept / Ergebnis", width = 300 },
    { key = "ingredientCost", label = "Kosten", width = 100 },
    { key = "salePrice", label = "Verkauf", width = 100 },
    { key = "profit", label = "Gewinn", width = 105 },
    { key = "margin", label = "Marge", width = 95 },
}

local MATERIAL_COLUMNS = {
    { key = "name", label = "Material", width = 270 },
    { key = "itemID", label = "Item-ID", width = 100 },
    { key = "currentPrice", label = "Aktuell", width = 110 },
    { key = "averagePrice", label = "Ø AH-Preis", width = 130 },
    { key = "updatedAt", label = "Letzter Scan", width = 90 },
}

local TABLE_WIDTH = 700
local ROW_HEIGHT = 23

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
        title = "Rezepte",
        help = "Alle erkannten Herstellungsrezepte mit Kosten, Verkauf und Gewinn.",
    },
    transmute = {
        title = "Transmute",
        help = "Nur Rezepte, deren Berufsname als Transmutation erkannt wurde.",
    },
    materials = {
        title = "Materialien",
        help = "Überwachte Auktionshaus-Materialien. Eingabe akzeptiert Item-Link oder Item-ID.",
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

function AHT.UI:SetView(viewMode)
    self.viewMode = VIEW_INFO[viewMode] and viewMode or "recipes"
    if not self.frame then self:Create() end
    self:Refresh()
    self.frame:Show()
end

function AHT.UI:Create()
    if self.frame then return end
    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    self.frame = CreateFrame("Frame", "WOW4E_AH_Trader_MainFrame", UIParent, template)
    self.frame:SetSize(780, 600)
    self.frame:SetPoint("CENTER")
    self.frame:SetFrameStrata("DIALOG")
    self.frame:SetMovable(true)
    self.frame:EnableMouse(true)
    self.frame:RegisterForDrag("LeftButton")
    self.frame:SetScript("OnDragStart", self.frame.StartMoving)
    self.frame:SetScript("OnDragStop", self.frame.StopMovingOrSizing)
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

    self.scanButton = Button(self.frame, nil, "Scan", 100, 24)
    self.scanButton:SetPoint("TOPLEFT", 18, -70)
    self.scanButton:SetScript("OnClick", function()
        if AHT.Scanner.running then AHT.Scanner:Stop("user") else AHT.Scanner:Start() end
        self:RefreshStatus()
    end)

    self.recipeButton = Button(self.frame, nil, "Rezepte", 100, 24)
    self.recipeButton:SetPoint("LEFT", self.scanButton, "RIGHT", 8, 0)
    self.recipeButton:SetScript("OnClick", function()
        self:SetView("recipes")
        if AHT.Recipes then AHT.Recipes:Refresh() end
    end)

    self.matsButton = Button(self.frame, nil, "Materialien", 100, 24)
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

    self.materialInput = CreateFrame("EditBox", nil, self.frame, "InputBoxTemplate")
    self.materialInput:SetSize(190, 24)
    self.materialInput:SetPoint("TOPLEFT", 150, -101)
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

    self.materialLabel = Label(self.frame, "Material hinzufügen:", 125)
    self.materialLabel:SetPoint("TOPLEFT", 18, -106)
    self.materialLabel:SetTextColor(0.82, 0.75, 0.58)

    self.tableHeader = CreateFrame("Frame", nil, self.frame)
    self.tableHeader:SetSize(TABLE_WIDTH, 24)
    self.tableHeader:SetPoint("TOPLEFT", 18, -174)
    self.headers = {}
    local offset = 0
    for index = 1, 5 do
        local header = HeaderButton(self.tableHeader, "", 100)
        header:SetPoint("LEFT", offset, 0)
        header:SetScript("OnClick", function()
            local columns = self:GetActiveColumns()
            if columns[index] then self:SetSort(columns[index].key) end
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
    self:Refresh()
end

function AHT.UI:CreateRows()
    for index = 1, 24 do
        local row = CreateFrame("Button", nil, self.content)
        row:SetSize(TABLE_WIDTH, ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 0, -((index - 1) * ROW_HEIGHT))
        row:EnableMouse(true)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bg:SetColorTexture(index % 2 == 0 and 0.045 or 0.065, 0.032, 0.018, 0.82)
        row.info = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.info:SetPoint("LEFT", 8, 0)
        row.info:SetWidth(TABLE_WIDTH - 16)
        row.info:SetJustifyH("LEFT")
        row.cells = {}
        for index = 1, 5 do
            local text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            row.cells[index] = text
        end
        row:SetScript("OnClick", function()
            if row.result and row.result.kind ~= "info" and row.result.kind ~= "material" then
                self:ShowRecipeActions(row.result)
            end
        end)
        row:SetScript("OnEnter", function()
            if row.result then
                row.bg:SetColorTexture(0.2, 0.2, 0.05, 0.75)
                if row.result.kind ~= "info" and row.result.kind ~= "material" then
                    self:ShowRecipeContext(row.result, row)
                end
            end
        end)
        row:SetScript("OnLeave", function()
            row.bg:SetColorTexture(index % 2 == 0 and 0.045 or 0.065, 0.032, 0.018, 0.82)
            if self.recipeTooltipOwner == row then self:HideRecipeContext() end
        end)
        self.rows[index] = row
    end
end

function AHT.UI:GetActiveColumns()
    if self.viewMode == "materials" then return MATERIAL_COLUMNS end
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
    self:Refresh()
end

function AHT.UI:UpdateHeaders()
    local tableMode = self.viewMode == "recipes" or self.viewMode == "transmute" or self.viewMode == "materials"
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
    for _, result in ipairs(results or {}) do table.insert(sorted, result) end
    self:EnsureSortColumn()
    local key = self.sortColumn
    local ascending = self.sortAscending == true
    table.sort(sorted, function(a, b)
        local av, bv
        if key == "name" then
            av, bv = string.lower(tostring(a.name or "")), string.lower(tostring(b.name or ""))
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
    GameTooltip:AddLine(" ")

    for _, reagent in ipairs(result.reagents or {}) do
        local quantity = tonumber(reagent.quantity) or 1
        local name = reagent.name or AHT:GetItemInfo(reagent.itemID) or tostring(reagent.itemID)
        local current = AHT.Store and AHT.Store:GetPrice(reagent.itemID)
        local average = AHT.Store and AHT.Store:RecencyAverage(reagent.itemID)
        local currentText = current and AHT:FormatMoneyPlain(current) or "?"
        local averageText = average and AHT:FormatMoneyPlain(average) or "?"
        local currentTotal = current and AHT:FormatMoneyPlain(current * quantity) or "?"
        local averageTotal = average and AHT:FormatMoneyPlain(average * quantity) or "?"
        GameTooltip:AddLine(string.format("%dx %s", quantity, name), 1, 1, 1)
        GameTooltip:AddDoubleLine(
            "  aktuell/Stk " .. currentText .. " | Gesamt " .. currentTotal,
            "Ø/Stk " .. averageText .. " | Gesamt " .. averageTotal,
            0.78, 0.78, 0.78, 0.45, 1, 0.45
        )
    end

    local output = result.output
    if output and output.itemID then
        local current = AHT.Store and AHT.Store:GetPrice(output.itemID)
        local average = AHT.Store and AHT.Store:RecencyAverage(output.itemID)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Verkaufspreis des Ergebnisses", 0.8, 0.75, 0.55)
        GameTooltip:AddDoubleLine("Aktueller Scan", current and AHT:FormatMoneyPlain(current) or "?", 0.78, 0.78, 0.78, 1, 1, 0.45)
        GameTooltip:AddDoubleLine("Altersgewichteter Durchschnitt", average and AHT:FormatMoneyPlain(average) or "?", 0.78, 0.78, 0.78, 0.45, 1, 0.45)
    end

    local halfLife = AHT.DB and AHT.DB.settings and tonumber(AHT.DB.settings.averageHalfLifeSeconds) or 604800
    local halfLifeDays = math.max(1, math.floor(halfLife / 86400 + 0.5))
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(string.format("Ø = altersgewichtete Scans, Halbwertszeit %d Tage.", halfLifeDays), 0.62, 0.62, 0.62)
    GameTooltip:Show()
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
    self.scanButton:SetText(AHT.Scanner and AHT.Scanner.running and "Abbrechen" or "Scan")
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
        local currentPrice = record and tonumber(record.minPrice) or nil
        local averagePrice = AHT.Store and AHT.Store:RecencyAverage(material.itemID) or nil
        local updatedAt = record and tonumber(record.updatedAt) or nil
        local updatedText = updatedAt and date("%d.%m.%y", updatedAt) or "-"
        table.insert(rows, {
            kind = "material",
            name = material.name or "?",
            itemID = tonumber(material.itemID) or material.itemID,
            currentPrice = currentPrice,
            averagePrice = averagePrice,
            updatedAt = updatedAt,
            updatedText = updatedText,
        })
    end
    if #rows == 0 then
        table.insert(rows, { kind = "info", text = "Keine Materialien. Item-Link oder Item-ID oben eingeben und + Mat drücken." })
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
    table.insert(rows, { kind = "info", text = string.format("Rezepte=%d | Markt=%d | Materialien=%d", #((AHT.Recipes and AHT.Recipes:GetList()) or {}), AHT:TableCount(AHT.DB and AHT.DB.market), AHT:TableCount(AHT.DB and AHT.DB.materials)) })
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
    self:UpdateHeaders()
    self.content:SetHeight(math.max(420, #results * ROW_HEIGHT))
    for index, row in ipairs(self.rows) do
        local result = results[index]
        row.result = result
        if result then
            if result.kind == "info" then
                row.info:SetText(result.text or "")
                row.info:Show()
                for index = 1, 5 do row.cells[index]:Hide() end
                row:EnableMouse(false)
            elseif result.kind == "material" then
                row.info:Hide()
                row.cells[1]:SetText(result.name or "?")
                row.cells[2]:SetText(tostring(result.itemID or "?"))
                row.cells[3]:SetText(result.currentPrice and AHT:FormatMoneyPlain(result.currentPrice) or AHT.L.noData)
                row.cells[4]:SetText(result.averagePrice and AHT:FormatMoneyPlain(result.averagePrice) or AHT.L.noData)
                row.cells[5]:SetText(result.updatedText or "-")
                for index = 1, 5 do row.cells[index]:Show() end
                row.cells[3]:SetTextColor(1, 0.85, 0.4)
                row.cells[4]:SetTextColor(0.45, 1, 0.55)
                row:EnableMouse(false)
            else
                local profit = result.profit and AHT:FormatMoneyPlain(result.profit) or AHT.L.incomplete
                local margin = result.margin and string.format("%.1f%%", result.margin) or "-"
                local cost = result.ingredientCost and AHT:FormatMoneyPlain(result.ingredientCost) or "?"
                local sale = result.salePrice and AHT:FormatMoneyPlain(result.salePrice) or "?"
                local prefix = result.isDeal and "★ " or ""
                row.info:Hide()
                row.cells[1]:SetText(prefix .. (result.name or "?"))
                row.cells[2]:SetText(cost)
                row.cells[3]:SetText(sale)
                row.cells[4]:SetText(profit)
                row.cells[5]:SetText(margin)
                for index = 1, 5 do row.cells[index]:Show() end
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
            for index = 1, 5 do row.cells[index]:Hide() end
            row:Hide()
        end
    end
    self:RefreshStatus()
end

function AHT.UI:Show()
    if not self.frame then self:Create() end
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
    self.actionDialog = dialog

    local title = Label(dialog, result.name or "Rezept", 380)
    title:SetPoint("TOPLEFT", 14, -14)
    title:SetFontObject("GameFontHighlightLarge")
    local detail = Label(dialog, "Kostendetails werden aus den aktuellen Marktdaten berechnet.", 380)
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

function AHT.UI:ShowBuyDialog(result)
    if self.actionDialog then self.actionDialog:Hide() end
    local target = result.reagents and result.reagents[1]
    if not target then
        AHT:Print("Dieses Rezept hat keine kaufbare Zutat.")
        return
    end
    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    local dialog = CreateFrame("Frame", nil, UIParent, template)
    dialog:SetSize(430, 210)
    dialog:SetPoint("CENTER")
    dialog:SetFrameStrata("TOOLTIP")
    MakeBackdrop(dialog)
    self.buyDialog = dialog

    local title = Label(dialog, "Kaufplan: " .. (target.name or tostring(target.itemID)), 400)
    title:SetPoint("TOPLEFT", 14, -14)
    title:SetFontObject("GameFontHighlightLarge")
    local info = Label(dialog, "Preis wird vor der Ausführung erneut geprüft.", 400)
    info:SetPoint("TOPLEFT", 14, -48)
    info:SetHeight(55)

    local quantity = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
    quantity:SetSize(70, 24)
    quantity:SetPoint("TOPLEFT", 14, -105)
    quantity:SetAutoFocus(false)
    quantity:SetText("1")
    quantity:SetNumeric(true)

    local confirm = Button(dialog, nil, "Kaufen", 100, 24)
    confirm:SetPoint("BOTTOMLEFT", 14, 12)
    confirm:Disable()
    confirm:SetScript("OnClick", function()
        if not dialog.plan then return end
        if AHT.Buyer.pending and AHT.Buyer.pending.state == "awaiting_user_confirmation" then
            if AHT.Buyer:ConfirmCommodity() then dialog:Hide() end
            return
        end

        confirm:Disable()
        confirm:SetText("Prüfe Preis…")
        local started = AHT.Buyer:Confirm(dialog.plan, function(state, data)
            if state == "price" then
                info:SetText(string.format("Aktuell: %s pro Stück | Gesamt: %s\nBitte jetzt endgültig bestätigen.",
                    AHT:FormatMoneyPlain(data.unitPrice), AHT:FormatMoneyPlain(data.totalPrice)))
                confirm:SetText("Endgültig kaufen")
                confirm:Enable()
            elseif state == "submitted" or state == "completed" then
                dialog:Hide()
            elseif state == "error" then
                info:SetText("Fehler: " .. tostring(data))
                confirm:SetText("Kaufen")
                confirm:Disable()
            end
        end)
        if not started then
            confirm:SetText("Kaufen")
            confirm:Disable()
        end
    end)

    local preview = Button(dialog, nil, "Preis prüfen", 110, 24)
    preview:SetPoint("LEFT", quantity, "RIGHT", 8, 0)
    preview:SetScript("OnClick", function()
        local count = math.max(1, tonumber(quantity:GetText()) or 1)
        AHT.Buyer:Preview(target, count, function(plan, errorMessage)
            if errorMessage then info:SetText("Fehler: " .. errorMessage) return end
            dialog.plan = plan
            info:SetText(string.format("Menge: %d | Gesamt: %s | Fehlend: %d", plan.quantity, AHT:FormatMoneyPlain(plan.total), plan.missing))
            confirm:Enable()
        end)
    end)

    local close = Button(dialog, nil, CLOSE or "Close", 80, 24)
    close:SetPoint("BOTTOMRIGHT", -12, 12)
    close:SetScript("OnClick", function()
        if AHT.Buyer and AHT.Buyer.pending then AHT.Buyer:Cancel("dialog_closed") end
        dialog:Hide()
    end)
    dialog:Show()
end

function AHT.UI:ShowPostDialog(result)
    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    local dialog = CreateFrame("Frame", nil, UIParent, template)
    dialog:SetSize(430, 230)
    dialog:SetPoint("CENTER")
    dialog:SetFrameStrata("TOOLTIP")
    MakeBackdrop(dialog)
    self.postDialog = dialog

    local title = Label(dialog, "Postplan: " .. (result.name or "?"), 400)
    title:SetPoint("TOPLEFT", 14, -14)
    title:SetFontObject("GameFontHighlightLarge")
    local info = Label(dialog, "Bestand, Deposit und Preis werden vor dem Posten geprüft.", 400)
    info:SetPoint("TOPLEFT", 14, -48)
    info:SetHeight(45)

    local quantity = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
    quantity:SetSize(70, 24)
    quantity:SetPoint("TOPLEFT", 14, -100)
    quantity:SetAutoFocus(false)
    quantity:SetNumeric(true)
    quantity:SetText("1")

    local price = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
    price:SetSize(100, 24)
    price:SetPoint("LEFT", quantity, "RIGHT", 8, 0)
    price:SetAutoFocus(false)
    price:SetNumeric(true)
    price:SetText(tostring(result.salePrice or 0))

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
