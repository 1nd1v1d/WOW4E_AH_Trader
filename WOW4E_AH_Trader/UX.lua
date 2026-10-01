local AHT = WOW4E_AHT
local UI = AHT.UI
local ROW_HEIGHT = 23

local function Text(parent, text, width)
    local label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    label:SetText(text or "")
    label:SetJustifyH("LEFT")
    if width then label:SetWidth(width) end
    return label
end

local function Button(parent, text, width, callback)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width or 130, 24)
    button:SetText(text)
    if callback then button:SetScript("OnClick", callback) end
    return button
end

local function Input(parent, width, numeric)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(width or 70, 24)
    box:SetAutoFocus(false)
    if numeric then box:SetNumeric(true) end
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return box
end

local function Money(value)
    if value == nil then return "—" end
    if GetMoneyString then return (value < 0 and "-" or "") .. GetMoneyString(math.floor(math.abs(value)), true) end
    return AHT:FormatMoneyPlain(value)
end

local function Opaque(frame)
    if not frame.ahtOpaqueBackground then frame.ahtOpaqueBackground = frame:CreateTexture(nil, "BACKGROUND", nil, -8) end
    frame.ahtOpaqueBackground:SetAllPoints(frame)
    frame.ahtOpaqueBackground:SetColorTexture(0, 0, 0, 1)
    frame:SetAlpha(1)
    if frame.SetBackdrop then
        frame:SetBackdrop({ edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 16 })
    end
end

function UI:Window(key, title, width, height)
    if self.dialogs[key] then self.dialogs[key].title:SetText(title) return self.dialogs[key] end
    local frame = CreateFrame("Frame", "WOW4E_AHT_Window_" .. key, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    frame:SetSize(width, height)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(260)
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    Opaque(frame)
    local saved = AHT.DB.ui.windows[key] or {}
    frame:SetPoint("CENTER", UIParent, "CENTER", saved.x or 40, saved.y or -30)
    frame.title = Text(frame, title, width - 110)
    frame.title:SetPoint("TOPLEFT", 16, -16)
    frame.title:SetFontObject("GameFontNormalLarge")
    frame:SetMovable(true)
    local drag = CreateFrame("Frame", nil, frame)
    drag:SetPoint("TOPLEFT", 4, -4)
    drag:SetPoint("TOPRIGHT", -100, -4)
    drag:SetHeight(30)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() frame:StartMoving() end)
    drag:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        local x, y = frame:GetCenter()
        local cx, cy = UIParent:GetCenter()
        if x and cx then AHT.DB.ui.windows[key] = { x = x - cx, y = y - cy }; AHT.Store:Save() end
    end)
    frame.close = Button(frame, CLOSE or "Schließen", 82, function() frame:Hide() end)
    frame.close:SetPoint("TOPRIGHT", -12, -12)
    frame.close:SetFrameLevel(frame:GetFrameLevel() + 10)
    frame:HookScript("OnShow", function()
        self.windowStack = self.windowStack or {}
        for i = #self.windowStack, 1, -1 do if self.windowStack[i] == frame then table.remove(self.windowStack, i) end end
        table.insert(self.windowStack, frame)
        if self.escapeFrame then self.escapeFrame:Show() end
    end)
    frame:Hide()
    self.dialogs[key] = frame
    return frame
end

function UI:RequestRefresh()
    if self.refreshScheduled then return end
    self.refreshScheduled = true
    local function Run()
        self.refreshScheduled = false
        self:Refresh(true)
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.15, Run) else Run() end
end

function UI:SaveViewState()
    if self.restoringView or not AHT.DB then return end
    AHT.DB.ui.views[self.viewMode] = {
        query = self.searchQuery, profitOnly = self.profitOnly, marketFilter = self.marketFilter,
        professionFilter = self.professionFilter, opportunityDirection = self.opportunityDirection,
        minimumOpportunityPercent = self.minimumOpportunityPercent, showTransmutes = self.showTransmutes,
        sortColumn = self.sortColumn, sortAscending = self.sortAscending, filters = self.numericFilters or {},
        hiddenColumns = self.hiddenColumns or {}, scroll = self.scroll and self.scroll:GetVerticalScroll() or 0,
        selectedKey = self.selectedKey,
    }
end

function UI:RestoreViewState(view)
    self.restoringView = true
    local state = AHT.DB.ui.views[view] or {}
    self.searchQuery, self.profitOnly = state.query or "", state.profitOnly == true
    self.marketFilter, self.professionFilter = state.marketFilter or "all", state.professionFilter
    self.opportunityDirection, self.minimumOpportunityPercent = state.opportunityDirection or "all", state.minimumOpportunityPercent or 0
    self.showTransmutes = state.showTransmutes == true
    self.sortColumn, self.sortAscending = state.sortColumn, state.sortAscending == true
    self.numericFilters, self.hiddenColumns = state.filters or {}, state.hiddenColumns or { priceChangePercent = true, totalQuantity = true }
    self.selectedKey = state.selectedKey
    if self.searchInput then self.searchInput:SetText(self.searchQuery) end
    if self.scroll then self.scroll:SetVerticalScroll(state.scroll or 0) end
    self.restoringView = false
end

local baseSetView = UI.SetView
function UI:SetView(view)
    if self.frame and AHT.DB then
        self:SaveViewState()
        self:RestoreViewState(view == "transmute" and "recipes" or view)
    end
    baseSetView(self, view)
    if self.frame and self.selectedKey then self:Refresh(true) end
end

local moneyKeys = { costPerOutput = true, salePrice = true, profitPerOutput = true, ingredientCost = true,
    profit = true, currentPrice = true, marketValue = true, averagePrice = true, spent = true }
local percentKeys = { margin = true, discount = true, marketTrendPercent = true, priceChangePercent = true }

function UI:RenderVisibleRows()
    if not self.content or self.renderingRows then return end
    self.renderingRows = true
    local results = self.visibleResults or {}
    local maxScroll = math.max(0, #results * ROW_HEIGHT - (self.scroll:GetHeight() or 300))
    local scroll = math.min(self.scroll:GetVerticalScroll() or 0, maxScroll)
    if scroll ~= self.scroll:GetVerticalScroll() then self.scroll:SetVerticalScroll(scroll) end
    local offset = math.floor(scroll / ROW_HEIGHT)
    local columns = self:GetActiveColumns()
    for i, row in ipairs(self.rows) do
        local index = offset + i
        local result = results[index]
        row.result, row.rowIndex = result, index
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
        row.icon:Hide()
        for _, cell in ipairs(row.cells) do cell:Hide(); cell:SetTextColor(1, 1, 1) end
        row.info:Hide()
        if result then
            local selected = result == self.selectedResult
            row.bg:SetColorTexture(selected and 0.20 or 0.035, selected and 0.14 or 0.035, selected and 0.05 or 0.035, 1)
            if result.kind == "info" then row.info:SetText(result.text); row.info:Show() else
                local item = result.output or result
                if item.itemID then
                    local _, _, quality, _, _, _, _, _, _, icon = AHT:GetItemInfo(item.itemID)
                    if icon then row.icon:SetTexture(icon); row.icon:Show() end
                    if quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
                        local color = ITEM_QUALITY_COLORS[quality]
                        row.cells[1]:SetTextColor(color.r, color.g, color.b)
                    end
                end
                for cellIndex, column in ipairs(columns) do
                    local value = result[column.key]
                    if column.key == "name" then
                        value = (result.isWatched and "★ " or "") .. (result.side == "buy" and "Kauf: " or result.side == "sell" and "Verkauf: " or "") .. tostring(result.name or "?")
                    elseif moneyKeys[column.key] then value = Money(value)
                    elseif percentKeys[column.key] then value = value and string.format("%+.1f%%", value) or "—"
                    elseif column.key == "updatedAt" then
                        local age = value and math.max(0, AHT:Now() - value)
                        value = age and (age < 3600 and string.format("%d Min.", math.floor(age / 60)) or string.format("%.1f Std.", age / 3600)) or "—"
                    end
                    row.cells[cellIndex]:SetText(tostring(value == nil and "—" or value))
                    row.cells[cellIndex]:Show()
                    if column.key == "profitPerOutput" or column.key == "profit" then
                        row.cells[cellIndex]:SetTextColor((result[column.key] or 0) > 0 and 0.35 or 1, (result[column.key] or 0) > 0 and 1 or 0.45, 0.35)
                    end
                end
            end
            row:Show()
        else row:Hide() end
    end
    self.renderingRows = false
    self:SaveViewState()
end

local baseMatches = UI.MatchesFilter
function UI:MatchesFilter(result)
    if not baseMatches(self, result) then return false end
    if result.kind == "info" then return true end
    local filter = self.numericFilters or {}
    local price = result.currentPrice or result.salePrice
    local margin, profit = result.margin or result.roi, result.profitPerOutput or result.profit
    local item = result.output or result
    local stock = item.itemID and AHT.Inventory:GetCount(item.itemID) or { total = 0 }
    if filter.priceMin and (not price or price < filter.priceMin) then return false end
    if filter.priceMax and (not price or price > filter.priceMax) then return false end
    if filter.marginMin and (not margin or margin < filter.marginMin) then return false end
    if filter.profitMin and (not profit or profit < filter.profitMin) then return false end
    local timestamp = result.updatedAt or (result.marketSnapshot and result.marketSnapshot.updatedAt)
    if filter.ageHours and (not timestamp or AHT:Now() - timestamp > filter.ageHours * 3600) then return false end
    if filter.stockMin and stock.total < filter.stockMin then return false end
    for key, condition in pairs(filter.columns or {}) do
        local value = result[key]
        if key == "updatedAt" and value then value = (AHT:Now() - value) / 3600 end
        if condition.text and not tostring(value or ""):lower():find(condition.text:lower(), 1, true) then return false end
        if condition.min and (not tonumber(value) or value < condition.min) then return false end
        if condition.max and (not tonumber(value) or value > condition.max) then return false end
    end
    return true
end

function UI:Dropdown(anchor, options)
    local frame = self:Window("dropdown", "Auswählen", 270, 80 + #options * 27)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
    frame.buttons = frame.buttons or {}
    for _, button in ipairs(frame.buttons) do button:Hide() end
    for i, option in ipairs(options) do
        local button = frame.buttons[i] or Button(frame, "", 235)
        frame.buttons[i] = button
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", 16, -50 - (i - 1) * 27)
        button:SetText(option.label)
        button:SetScript("OnClick", function() frame:Hide(); option.action(); self:RefreshControls(); self:Refresh(true) end)
        button:Show()
    end
    frame:SetHeight(65 + #options * 27)
    frame:Show()
end

function UI:ShowFilters(column)
    local frame = self:Window("filters", "Filter – " .. (column and column.label or "diese Ansicht"), 450, 360)
    frame.inputs = frame.inputs or {}
    for _, entry in ipairs(frame.inputs) do entry.label:Hide(); entry.box:Hide() end
    local fields = column and {{ "min", "Minimum" }, { "max", "Maximum" }, { "text", "Enthält" }} or {
        { "priceMin", "Preis min. (Kupfer/Stk)" }, { "priceMax", "Preis max. (Kupfer/Stk)" },
        { "marginMin", "Marge / ROI min. (%)" }, { "profitMin", "Gewinn min. (Kupfer/Stk)" },
        { "ageHours", "Datenalter max. (Stunden)" }, { "stockMin", "Bestand min. (Stück)" },
    }
    self.numericFilters = self.numericFilters or {}
    self.numericFilters.columns = self.numericFilters.columns or {}
    local target = column and (self.numericFilters.columns[column.key] or {}) or self.numericFilters
    for i, field in ipairs(fields) do
        local entry = frame.inputs[i]
        if not entry then
            entry = { label = Text(frame, "", 250), box = Input(frame, 135, false) }
            entry.label:SetPoint("TOPLEFT", 16, -50 - (i - 1) * 36)
            entry.box:SetPoint("LEFT", entry.label, "RIGHT", 12, 0)
            frame.inputs[i] = entry
        end
        entry.label:SetText(column and column.key == "updatedAt" and field[1] ~= "text" and field[2] .. " (Alter/Std.)" or field[2])
        entry.box:SetText(tostring(target[field[1]] or ""))
        entry.label:Show(); entry.box:Show()
    end
    frame.apply = frame.apply or Button(frame, "Anwenden", 120)
    frame.apply:SetPoint("BOTTOMLEFT", 16, 16)
    frame.apply:SetScript("OnClick", function()
        for i, field in ipairs(fields) do
            local value = frame.inputs[i].box:GetText()
            target[field[1]] = field[1] == "text" and value ~= "" and value or tonumber(value)
        end
        if column then self.numericFilters.columns[column.key] = target end
        frame:Hide(); self:Refresh(true)
    end)
    frame.reset = frame.reset or Button(frame, "Zurücksetzen", 120)
    frame.reset:SetPoint("LEFT", frame.apply, "RIGHT", 10, 0)
    frame.reset:SetScript("OnClick", function() self.numericFilters = {}; frame:Hide(); self:Refresh(true) end)
    frame:Show()
end

function UI:ShowSettings()
    local frame = self:Window("settings", "AH Trader – Einstellungen", 490, 475)
    local fields = {
        { "minMarginPercent", "Mindestmarge (%)", 0, 10000 }, { "budgetCopper", "Auftragsbudget (Kupfer; 0 = Goldbestand)", 0, 1000000000000 },
        { "productionPriceSlippagePercent", "Preistoleranz (%)", 0, 100 }, { "maxPriceAgeSeconds", "Max. Preisalter (Sekunden)", 60, 2592000 },
        { "sellFloorCopper", "Verkaufsminimum pro Stück (Kupfer)", 0, 1000000000000 },
        { "minimumProfitCopper", "Mindestgewinn (Kupfer)", 1, 1000000000000 },
        { "productionSuggestionCap", "Mengenprüfung bis Herstellvorgänge", 1, 1000 },
        { "averageHalfLifeSeconds", "Historie: Halbwertszeit (Sekunden)", 3600, 2592000 },
        { "marketTrimPercent", "Historie: Ausreißer-Trim (%)", 0, 40 },
    }
    frame.fields = frame.fields or {}
    for i, field in ipairs(fields) do
        local entry = frame.fields[i]
        if not entry then
            entry = { label = Text(frame, field[2], 330), box = Input(frame, 90, true) }
            entry.label:SetPoint("TOPLEFT", 16, -50 - (i - 1) * 32)
            entry.box:SetPoint("LEFT", entry.label, "RIGHT", 12, 0)
            frame.fields[i] = entry
        end
        entry.box:SetText(tostring(AHT.DB.settings[field[1]]))
    end
    frame.strategy = frame.strategy or Button(frame, "", 160)
    frame.strategy:SetPoint("BOTTOMLEFT", 16, 83)
    frame.strategy:SetText(AHT.DB.settings.sellStrategy == "match" and "Preis angleichen ▾" or "Unterbieten (1c) ▾")
    frame.strategy:SetScript("OnClick", function() self:Dropdown(frame.strategy, {
        { label = "Aktuellen Preis angleichen", action = function() AHT.DB.settings.sellStrategy = "match"; self:ShowSettings() end },
        { label = "Um 1 Kupfer unterbieten", action = function() AHT.DB.settings.sellStrategy = "undercut"; self:ShowSettings() end },
    }) end)
    frame.adapter = frame.adapter or Button(frame, "", 265)
    frame.adapter:SetPoint("LEFT", frame.strategy, "RIGHT", 10, 0)
    frame.adapter:SetText("Auctionator-Fallback: " .. (AHT.DB.settings.useAuctionator and "an" or "aus"))
    frame.adapter:SetScript("OnClick", function() AHT.DB.settings.useAuctionator = not AHT.DB.settings.useAuctionator; self:ShowSettings() end)
    frame.note = frame.note or Text(frame, "Marge = Gewinn / Materialwert. Kaution bleibt als gebundenes Gold separat. Ohne Nachfrageprognose.", 450)
    frame.note:SetPoint("BOTTOMLEFT", 16, 48)
    frame.save = frame.save or Button(frame, "Speichern", 140)
    frame.save:SetPoint("BOTTOMLEFT", 16, 14)
    frame.save:SetScript("OnClick", function()
        for i, field in ipairs(fields) do
            local value = tonumber(frame.fields[i].box:GetText())
            if value then AHT.DB.settings[field[1]] = math.max(field[3], math.min(field[4], value)) end
        end
        AHT.Store:Save(); frame:Hide(); AHT:Refresh()
    end)
    frame:Show()
end

function UI:ShowHistory(result, days)
    local item = result.output or result
    days = days or 30
    local frame = self:Window("history", "Preisverlauf – " .. tostring(result.name or item.name or item.itemID), 700, 420)
    local points = AHT.Commerce:PriceHistory(item.itemID, item.itemKey, days)
    local snapshot = AHT.Store:GetMarketSnapshot(item.itemID, item.itemKey)
    frame.summary = frame.summary or Text(frame, "", 650)
    frame.summary:SetPoint("TOPLEFT", 16, -53)
    frame.summary:SetText(string.format("Aktuell %s | Ø %s | %d Beobachtungstage | Quelle: %s\nÄnderung zum letzten Scan: %s | Verteilung: %s",
        Money(snapshot and snapshot.currentPrice), Money(snapshot and snapshot.averagePrice), #points,
        AHT.Commerce:SourceText(snapshot and snapshot.source), snapshot and snapshot.priceChangePercent and string.format("%+.1f%%", snapshot.priceChangePercent) or "—",
        snapshot and snapshot.distributionAt and date("%d.%m. %H:%M", snapshot.distributionAt) or "nicht bekannt"))
    frame.graph = frame.graph or CreateFrame("Frame", nil, frame)
    frame.graph:SetPoint("TOPLEFT", 60, -117)
    frame.graph:SetSize(580, 220)
    frame.bars = frame.bars or {}
    for _, bar in ipairs(frame.bars) do bar:Hide() end
    local minimum, maximum = math.huge, 0
    for _, point in ipairs(points) do minimum = math.min(minimum, point.p); maximum = math.max(maximum, point.p) end
    frame.axis = frame.axis or Text(frame, "", 650)
    frame.axis:SetPoint("TOPLEFT", 16, -91)
    frame.axis:SetText(#points > 0 and ("Min " .. Money(minimum) .. "  /  Max " .. Money(maximum) .. "  |  Tagespreise, zeitlich gewichtet im Ø") or "Noch keine eigenen Tagesdaten. Cachepreise erzeugen keinen Verlauf.")
    local cutoff = AHT:Now() - days * 86400
    for i, point in ipairs(points) do
        local bar = frame.bars[i] or frame.graph:CreateTexture(nil, "ARTWORK")
        frame.bars[i] = bar
        bar:ClearAllPoints()
        bar:SetPoint("BOTTOMLEFT", math.max(0, (point.t - cutoff) / (days * 86400)) * 570, 0)
        bar:SetSize(math.max(3, 500 / days), 4 + (point.p - minimum) / math.max(1, maximum - minimum) * 200)
        bar:SetColorTexture(0.85, 0.65, 0.20, 1)
        bar:Show()
    end
    frame.from = frame.from or Text(frame, "", 150)
    frame.from:SetPoint("BOTTOMLEFT", 60, 62); frame.from:SetText(date("%d.%m.", cutoff))
    frame.to = frame.to or Text(frame, "heute", 70); frame.to:SetPoint("BOTTOMRIGHT", -40, 62)
    frame.week = frame.week or Button(frame, "7 Tage", 110)
    frame.week:SetPoint("BOTTOMLEFT", 16, 16); frame.week:SetScript("OnClick", function() self:ShowHistory(result, 7) end)
    frame.month = frame.month or Button(frame, "30 Tage", 110)
    frame.month:SetPoint("LEFT", frame.week, "RIGHT", 10, 0); frame.month:SetScript("OnClick", function() self:ShowHistory(result, 30) end)
    frame:Show()
end

local baseCreate = UI.Create
function UI:Create()
    baseCreate(self)
    if not self.frame or self.uxCreated then return end
    self.uxCreated = true
    self.escapeFrame = CreateFrame("Frame", nil, UIParent)
    self.escapeFrame:EnableKeyboard(true)
    self.escapeFrame:SetPropagateKeyboardInput(true)
    self.escapeFrame:SetScript("OnKeyDown", function(frame, key)
        if InCombatLockdown and InCombatLockdown() then return end
        frame:SetPropagateKeyboardInput(true)
        if key ~= "ESCAPE" then return end
        for i = #(self.windowStack or {}), 1, -1 do
            local window = self.windowStack[i]
            if window:IsShown() then window:Hide(); frame:SetPropagateKeyboardInput(false); return end
        end
        if self.ahRecipePanel and self.ahRecipePanel:IsShown() then
            self:HideAHRecipePanel(); self:Show(); frame:SetPropagateKeyboardInput(false)
        elseif self.frame:IsShown() then self.frame:Hide(); frame:SetPropagateKeyboardInput(false)
        else frame:Hide() end
    end)
    self.escapeFrame:Hide()
    self.frame:HookScript("OnShow", function() self.escapeFrame:Show() end)
    self.filterOptions = Button(self.frame, "Filter ▾", 95, function() self:ShowFilters() end)
    self.filterOptions:SetPoint("TOPRIGHT", -18, -132)
    self.clearFilters = Button(self.frame, "Filter löschen", 105, function()
        self.numericFilters, self.searchQuery, self.profitOnly, self.marketFilter, self.professionFilter = {}, "", false, "all", nil
        self.opportunityDirection, self.minimumOpportunityPercent = "all", 0
        self.searchInput:SetText(""); self:RefreshControls(); self:Refresh(true)
    end)
    self.clearFilters:SetPoint("RIGHT", self.filterOptions, "LEFT", -7, 0)
    self.viewTitle:SetWidth(410)
    self.viewHelp:SetWidth(700)
    self.recent = Button(self.frame, "▾", 25, function()
        local options = {}
        for _, query in ipairs(AHT.DB.recentSearches) do
            table.insert(options, { label = query, action = function() self.searchInput:SetText(query) end })
        end
        self:Dropdown(self.recent, options)
    end)
    self.recent:SetPoint("RIGHT", self.searchInput, "RIGHT", 0, 0)
    self.searchInput:SetTextInsets(6, 26, 0, 0)
    self.filterButton:SetScript("OnClick", function()
        local options = self.viewMode == "materials" and {
            { label = "Alle Items", action = function() self.marketFilter = "all" end },
            { label = "Beobachtete Items", action = function() self.marketFilter = "watched" end },
            { label = "Taschen und Bank", action = function() self.marketFilter = "inventory" end },
        } or {
            { label = "Alle Ergebnisse", action = function() self.profitOnly = false end },
            { label = "Nur profitabel", action = function() self.profitOnly = true end },
        }
        self:Dropdown(self.filterButton, options)
    end)
    self.professionButton:SetScript("OnClick", function()
        local options, seen = {{ label = "Alle Berufe", action = function() self.professionFilter = nil end }}, {}
        for _, recipe in ipairs(AHT.Recipes:GetList()) do
            local name = recipe.professionName
            if name and not seen[name] then seen[name] = true; table.insert(options, { label = name, action = function() self.professionFilter = name end }) end
        end
        self:Dropdown(self.professionButton, options)
    end)
    self.opportunityDirectionButton:SetScript("OnClick", function() self:Dropdown(self.opportunityDirectionButton, {
        { label = "Alle Chancen", action = function() self.opportunityDirection = "all" end },
        { label = "Kaufchancen", action = function() self.opportunityDirection = "buy" end },
        { label = "Verkaufschancen", action = function() self.opportunityDirection = "sell" end },
    }) end)
    self.opportunityMinimumButton:SetScript("OnClick", function() self:ShowFilters({ key = "discount", label = "Vorteil (%)" }) end)
    for i, header in ipairs(self.headers) do
        header:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        header:SetScript("OnClick", function(_, button)
            local column = self:GetActiveColumns()[i]
            if column then if button == "RightButton" then self:ShowFilters(column) else self:SetSort(column.key) end end
        end)
    end
    self.moreButton:SetScript("OnClick", function() self:Dropdown(self.moreButton, {
        { label = "Einkaufslisten", action = function() self:ShowLists() end },
        { label = "Verkauf vorbereiten", action = function() self:ShowSellingWorkspace() end },
        { label = "Einstellungen", action = function() self:ShowSettings() end },
        { label = "Spalten auswählen", action = function() self:ShowColumnOptions() end },
        { label = "Ruf", action = function() self:SetView("reputation") end },
        { label = "Diagnose", action = function() self:SetView("diagnostics") end },
    }) end)
    self.scanButton:SetScript("OnClick", function()
        if AHT.Scanner.running or AHT.Scanner.marketDiscovery or AHT.Scanner.replication then AHT.Scanner:Stop("user"); self:RefreshStatus(); return end
        self:Dropdown(self.scanButton, {
            { label = "Bekannte Items (Details)", action = function() AHT.Scanner:Start() end },
            { label = "AH-Übersicht (max. 100 Seiten)", action = function() AHT.Scanner:StartMarketDiscovery() end },
            { label = "Auswahl detailliert prüfen", action = function()
                local result = self.selectedResult
                if result then AHT.Scanner:Start({ result.output or result }, "selected") end
            end },
            { label = "Replikat prüfen (experimentell)", action = function() AHT.Scanner:StartReplication() end },
        })
    end)
    self.detailAction:SetWidth(130)
    self.detailAction:ClearAllPoints(); self.detailAction:SetPoint("TOPRIGHT", -135, -28)
    self.detailSearch:ClearAllPoints(); self.detailSearch:SetPoint("BOTTOMRIGHT", -12, 12)
    self.detailSell = Button(self.detailPanel, "Verkauf planen", 120, function()
        local result = self.selectedResult
        if result then self:ShowPostDialog(result.output and result or { name = result.name, output = { itemID = result.itemID, quantity = 1 } }) end
    end)
    self.detailSell:SetPoint("TOPRIGHT", -12, -28)
    self.detailHistory = Button(self.detailPanel, "Preisverlauf", 130, function() if self.selectedResult then self:ShowHistory(self.selectedResult) end end)
    self.detailHistory:SetPoint("BOTTOMRIGHT", -135, 12)
    self:UpgradeTabs()
    self:RefreshControls()
end

function UI:ShowColumnOptions()
    local options = {}
    for _, field in ipairs({ { "averagePrice", "Gewichteter Durchschnitt" }, { "priceChangePercent", "Änderung letzter Scan" }, { "totalQuantity", "Angebotsmenge" } }) do
        table.insert(options, { label = ((self.hiddenColumns or {})[field[1]] and "[ ] " or "[x] ") .. field[2], action = function()
            self.hiddenColumns = self.hiddenColumns or {}; self.hiddenColumns[field[1]] = not self.hiddenColumns[field[1]]
        end })
    end
    self:Dropdown(self.moreButton, options)
end

function UI:UpgradeTabs()
    local definitions = { { "recipeButton", "recipes", "Herstellen", 112 }, { "matsButton", "materials", "Markt", 88 },
        { "opportunityButton", "opportunities", "Chancen", 88 }, { "ordersButton", "orders", "Aufträge", 92 } }
    for _, definition in ipairs(definitions) do
        local old = self[definition[1]]
        local tab = CreateFrame("Button", nil, self.frame, "CharacterFrameTabButtonTemplate")
        tab:SetText(definition[3]); tab:SetSize(definition[4], 28); tab:SetAllPoints(old)
        tab:SetScript("OnClick", function() self:SetView(definition[2]) end)
        old:Hide()
        self[definition[1]] = tab
        tab.ahtView = definition[2]
    end
    self:UpdateNavigation()
end

local baseNavigation = UI.UpdateNavigation
function UI:UpdateNavigation()
    baseNavigation(self)
    for _, button in ipairs({ self.recipeButton, self.matsButton, self.opportunityButton, self.ordersButton }) do
        if button.ahtView then
            if self.viewMode == button.ahtView and PanelTemplates_SelectTab then PanelTemplates_SelectTab(button)
            elseif PanelTemplates_DeselectTab then PanelTemplates_DeselectTab(button) end
        end
    end
end

local baseControls = UI.RefreshControls
function UI:RefreshControls()
    baseControls(self)
    if self.opportunityMinimumButton then
        local conditions = (self.numericFilters or {}).columns or {}
        local minimum = conditions.discount and conditions.discount.min or self.minimumOpportunityPercent or 0
        self.opportunityMinimumButton:SetText(string.format("Vorteil ≥ %.0f%% ▾", minimum))
    end
    if self.filterButton then self.filterButton:SetText(self.viewMode == "materials" and (({ all = "Alle ▾", watched = "Beobachtet ▾", inventory = "Bestand ▾" })[self.marketFilter] or "Alle ▾") or (self.profitOnly and "Profitabel ▾" or "Alle ▾")) end
    if self.clearFilters then
        local count = 0
        for key, value in pairs(self.numericFilters or {}) do
            if key == "columns" then for _ in pairs(value) do count = count + 1 end elseif value then count = count + 1 end
        end
        self.clearFilters:SetText(count > 0 and ("Filter (" .. count .. ") ×") or "Zurücksetzen")
    end
end

local baseHeaders = UI.UpdateHeaders
function UI:UpdateHeaders()
    baseHeaders(self)
    for i, column in ipairs(self:GetActiveColumns()) do
        if self.numericFilters and self.numericFilters.columns and self.numericFilters.columns[column.key] then
            self.headers[i].label:SetText(self.headers[i].label:GetText() .. " *")
        end
    end
end

local baseCreateRecipePanel = UI.CreateAHRecipePanel
function UI:CreateAHRecipePanel()
    baseCreateRecipePanel(self)
    local panel = self.ahRecipePanel
    if not panel or panel.ahtEscapeHooked then return end
    panel.ahtEscapeHooked = true
    panel.ahtWindowKey = "recipe"
    local position = AHT.DB.ui.windows.recipe
    if position then panel:ClearAllPoints(); panel:SetPoint("CENTER", UIParent, "CENTER", position.x or 0, position.y or 0) end
    panel:HookScript("OnShow", function()
        self.windowStack = self.windowStack or {}
        table.insert(self.windowStack, panel)
        if self.escapeFrame then self.escapeFrame:Show() end
    end)
    panel:HookScript("OnHide", function()
        self:CancelAHRecipeScan()
        self:Show()
    end)
end

function UI:RenderBuyDialog()
    local frame = self.buyDialog
    if not frame then return end
    local order, result = frame.order, frame.result
    local outputs = math.max(1, math.floor(tonumber(frame.quantity:GetText()) or 1))
    local crafts = order and order.crafts or math.ceil(outputs / math.max(1, result.output.quantity or 1))
    frame.quantity:SetEnabled(order == nil)
    frame.quantityInfo:SetText(string.format("%d Herstellvorgänge → %d fertige Items%s", crafts, crafts * math.max(1, result.output.quantity or 1),
        crafts * math.max(1, result.output.quantity or 1) ~= outputs and " (aufgerundet)" or ""))
    local requirements = order and order.requirements or {}
    if not order then
        for _, reagent in ipairs(result.reagents or {}) do
            local count = AHT.Inventory:GetCount(reagent.itemID)
            local reserved = AHT.Production:GetReserved(reagent.itemID)
            local required = (reagent.quantity or 1) * crafts
            table.insert(requirements, { itemID = reagent.itemID, name = reagent.name, required = required,
                bags = count.bags, bank = count.bank, bankKnown = count.bankKnown, reservedOther = reserved,
                toBuy = math.max(0, required - math.max(0, count.total - reserved)), bought = 0,
                unitPrice = AHT.Store:GetPrice(reagent.itemID) })
        end
    end
    for _, row in ipairs(frame.rows) do row:Hide() end
    for i, requirement in ipairs(requirements) do
        local row = frame.rows[i]
        if not row then
            row = CreateFrame("Frame", nil, frame.materialContent)
            row:SetSize(795, 30); row.cells = {}
            local positions = { 0, 240, 295, 350, 410, 485, 560, 665 }
            local widths = { 230, 50, 50, 55, 70, 70, 95, 115 }
            for n, x in ipairs(positions) do
                local cell = Text(row, "", widths[n]); cell:SetPoint("LEFT", x, 0)
                if n > 1 then cell:SetJustifyH("RIGHT") end
                row.cells[n] = cell
            end
            frame.rows[i] = row
        end
        row:SetPoint("TOPLEFT", 0, -(i - 1) * 30)
        local missing = math.max(0, (requirement.toBuy or 0) - (requirement.bought or 0))
        local plan = order and (AHT.Production.runtimePlans[tostring(order.id)] or {})[tostring(requirement.itemID)]
        local total = plan and plan.total or requirement.unitPrice and missing * requirement.unitPrice
        local unit = plan and plan.plannedQuantity > 0 and plan.total / plan.plannedQuantity or requirement.unitPrice
        local values = { requirement.name or AHT:GetItemInfo(requirement.itemID) or tostring(requirement.itemID),
            requirement.required, requirement.bags or 0, requirement.bankKnown and requirement.bank or "?",
            requirement.reservedOther or 0, missing, Money(unit), Money(total) }
        for n, value in ipairs(values) do row.cells[n]:SetText(tostring(value)) end
        row:Show()
    end
    frame.materialContent:SetHeight(math.max(270, #requirements * 30))
    local preview = order and order.preview
    local status = order and order.status or "new"
    local statusText = ({ new = "Zielmenge eingeben und Preise prüfen.", previewing = "Aktuelle Angebote werden geprüft…",
        checking = "Preise und Gesamtmarge werden erneut geprüft…", ready = "Plan geprüft. Einkauf vorbereiten.",
        buying = "Live-Angebote werden geprüft…", awaiting_purchase = "Kauf ist vorbereitet. Bitte auslösen.",
        awaiting_confirmation = "Live-Gesamtsumme bestätigen.", submitted = "Warte auf Kaufbestätigung des Servers…",
        next_ready = "Nächste Zutat vorbereiten.", ready_to_craft = "Alle Zutaten eingeplant/gekauft. Bank oder Post ggf. abholen.",
        paused = "Einkauf pausiert. Preise erneut prüfen.", incomplete = "Materialmenge oder Preis fehlt.", cancelled = "Auftrag storniert." })[status] or status
    frame.summary:SetText(preview and string.format("Ausgegeben %s  |  Noch zu kaufen %s  |  Gesamt %s\nMaterialwert inkl. Bestand %s  |  Erlös nach AH-Gebühr %s\nAuftragsgewinn %s  |  Marge %s  |  Minimum %.1f%%  |  Budget: %s",
        Money(preview.spent or 0), Money(preview.remainingCost), Money(preview.cashCost), Money(preview.economicCost),
        Money(preview.net), Money(preview.profit), preview.margin and string.format("%.1f%%", preview.margin) or "—",
        preview.minimumMargin or 0, preview.meetsBudget and "OK" or "überschritten")
        or "Keine Nachfrageprognose. Die Mengenprüfung berücksichtigt aktuelle Material-Preisstaffeln, Bestand, Reservierungen, Marge und Budget.")
    frame.status:SetText(frame.message or (order and order.lastError and AHT:ErrorText(order.lastError)) or statusText)
    frame.action:Disable()
    frame.action:SetText("Einkauf vorbereiten")
    local pending = AHT.Buyer.pending
    local ownPending = pending and AHT.Production.active and order and tostring(AHT.Production.active.orderID) == tostring(order.id)
    if ownPending and pending.state == "ready_to_buy" then
        frame.action:SetText("Kauf auslösen"); frame.action:Enable()
    elseif ownPending and pending.state == "awaiting_user_confirmation" then
        frame.action:SetText("Kauf bestätigen"); frame.action:Enable()
        frame.status:SetText(string.format("%dx %s: %s pro Stück – GESAMT %s. Nur dieser Klick kauft.",
            pending.quantity or 0, pending.plan.target.name or "Material", Money(pending.unitPrice), Money(pending.totalPrice)))
    elseif order and not pending and preview and preview.complete and preview.meetsMargin and preview.meetsBudget
            and status ~= "ready_to_craft" and status ~= "cancelled" and status ~= "previewing" and status ~= "checking" then
        frame.action:Enable()
    end
    if pending or status == "previewing" or status == "checking" then frame.preview:Disable(); frame.suggest:Disable() else frame.preview:Enable(); frame.suggest:Enable() end
end

function UI:ShowBuyDialog(result, existingOrder)
    if self.actionDialog then self.actionDialog:Hide() end
    if not result or not result.output or #(result.reagents or {}) == 0 then AHT:Print("Keine Zutaten für dieses Rezept bekannt.") return end
    if AHT.Buyer.pending then AHT:Print(AHT:ErrorText("purchase_in_progress")); return end
    local frame = self:Window("buy", "Einkauf planen – " .. (result.name or "?"), 850, 580)
    self.buyDialog = frame
    frame.result, frame.order, frame.message = result, existingOrder, nil
    if frame.complete then frame.complete:Hide() end
    if not frame.quantity then
        frame.quantityLabel = Text(frame, "Zielmenge fertige Items:", 185); frame.quantityLabel:SetPoint("TOPLEFT", 16, -58)
        frame.quantity = Input(frame, 75, true); frame.quantity:SetPoint("LEFT", frame.quantityLabel, "RIGHT", 8, 0)
        frame.quantity:SetScript("OnTextChanged", function() if frame.result then self:RenderBuyDialog() end end)
        frame.quantityInfo = Text(frame, "", 360); frame.quantityInfo:SetPoint("LEFT", frame.quantity, "RIGHT", 15, 0)
        frame.suggest = Button(frame, "Menge berechnen", 145, function()
            frame.suggest:Disable(); frame.message = "Preisstaffeln und profitable Menge werden geprüft…"; self:RenderBuyDialog()
            AHT.Production:RefreshSuggestion(frame.result, function(suggestion, reason)
                if reason then frame.message = AHT:ErrorText(reason) else
                    local count = suggestion.suggestedCrafts * math.max(1, frame.result.output.quantity or 1)
                    frame.message = count > 0 and "Maximale geprüfte Menge innerhalb deines Limits. Absatz ist nicht garantiert." or "Keine profitable Menge innerhalb von Preisstaffeln und Budget gefunden."
                    if not frame.order and count > 0 then frame.quantity:SetText(tostring(count)) end
                end
                frame.suggest:Enable(); self:RenderBuyDialog()
            end)
        end)
        frame.suggest:SetPoint("TOPLEFT", 16, -94)
        local headers, positions = { "Material", "Bedarf", "Tasche", "Bank", "Reserviert", "Fehlen", "Preis/Stk", "Noch kaufen" }, { 0, 240, 295, 350, 410, 485, 560, 665 }
        for i, text in ipairs(headers) do local h = Text(frame, text, i == 1 and 230 or 100); h:SetPoint("TOPLEFT", 16 + positions[i], -135); h:SetTextColor(1, 0.82, 0) end
        frame.materialScroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
        frame.materialScroll:SetPoint("TOPLEFT", 16, -158); frame.materialScroll:SetPoint("BOTTOMRIGHT", -40, 170)
        frame.materialContent = CreateFrame("Frame", nil, frame.materialScroll); frame.materialContent:SetSize(790, 270)
        frame.materialScroll:SetScrollChild(frame.materialContent); frame.rows = {}
        frame.summary = Text(frame, "", 790); frame.summary:SetPoint("BOTTOMLEFT", 16, 78); frame.summary:SetHeight(78); frame.summary:SetJustifyV("TOP")
        frame.status = Text(frame, "", 790); frame.status:SetPoint("BOTTOMLEFT", 16, 50); frame.status:SetHeight(28)
        frame.action = Button(frame, "Einkauf vorbereiten", 180, function()
            local order = frame.order
            if not order then return end
            frame.message = nil
            local function Callback(state, data)
                frame.message = state == "error" and AHT:ErrorText(data) or nil
                self:RenderBuyDialog(); self:RequestRefresh()
            end
            local ok, reason
            if AHT.Buyer.pending and AHT.Buyer.pending.state == "ready_to_buy" then ok = AHT.Production:StartCurrentPurchase()
            elseif AHT.Buyer.pending and AHT.Buyer.pending.state == "awaiting_user_confirmation" then ok = AHT.Production:ConfirmCurrentCommodity()
            elseif order.status == "ready" then ok, reason = AHT.Production:Start(order, Callback)
            else ok, reason = AHT.Production:Continue(order, Callback) end
            if not ok then frame.message = AHT:ErrorText(reason or order.lastError or "api_rejected") end
            self:RenderBuyDialog()
        end)
        frame.action:SetPoint("BOTTOMLEFT", 16, 14)
        frame.preview = Button(frame, "Preise prüfen", 150, function()
            frame.message = nil
            if not frame.order then
                local order, reason = AHT.Production:CreateOrderForOutputs(frame.result, frame.quantity:GetText())
                if not order then frame.message = AHT:ErrorText(reason); self:RenderBuyDialog(); return end
                frame.order = order
            end
            frame.order.lastError = nil
            AHT.Production:PreviewOrder(frame.order, function(_, reason)
                frame.message = reason and AHT:ErrorText(reason) or nil; self:RenderBuyDialog(); self:RequestRefresh()
            end)
            self:RenderBuyDialog()
        end)
        frame.preview:SetPoint("LEFT", frame.action, "RIGHT", 10, 0)
        frame.cancel = Button(frame, "Auftrag stornieren", 160, function()
            if frame.order then AHT.Production:CancelOrder(frame.order) end
            frame:Hide(); self:RequestRefresh()
        end)
        frame.cancel:SetPoint("LEFT", frame.preview, "RIGHT", 10, 0)
        frame:HookScript("OnHide", function()
            local active = AHT.Production.active
            if active and frame.order and tostring(active.orderID) == tostring(frame.order.id) then AHT.Buyer:Cancel("dialog_closed") end
        end)
    end
    local suggestion = AHT.Production:Suggest(result)
    frame.quantity:SetText(tostring(existingOrder and (existingOrder.targetOutputs or existingOrder.crafts * math.max(1, result.output.quantity or 1)) or math.max(1, suggestion.suggestedCrafts) * math.max(1, result.output.quantity or 1)))
    self:RenderBuyDialog(); frame:Show()
end

function UI:ShowLists()
    local frame = self:Window("lists", "Einkaufslisten und gemeinsame Zutaten", 680, 480)
    if not frame.listName then
        frame.listName = Input(frame, 240, false); frame.listName:SetPoint("TOPLEFT", 24, -53)
        frame.listName:SetText("Produktion")
        frame.status = Text(frame, "", 620); frame.status:SetPoint("BOTTOMLEFT", 20, 52)
        frame.scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
        frame.scroll:SetPoint("TOPLEFT", 20, -110); frame.scroll:SetPoint("BOTTOMRIGHT", -40, 90)
        frame.content = CreateFrame("Frame", nil, frame.scroll); frame.content:SetSize(600, 300)
        frame.scroll:SetScrollChild(frame.content)
        frame.text = Text(frame.content, "", 590); frame.text:SetPoint("TOPLEFT"); frame.text:SetJustifyV("TOP")
        frame.live = Button(frame, "Offene Aufträge", 140, function() frame.list = { name = frame.listName:GetText(), lines = AHT.Commerce:AggregateShopping() }; self:RenderList(frame) end)
        frame.live:SetPoint("TOPLEFT", 24, -81)
        frame.load = Button(frame, "Liste laden ▾", 130, function()
            local options = {}
            for name, list in pairs(AHT.DB.shoppingLists) do table.insert(options, { label = name, action = function() frame.list = list; frame.listName:SetText(name); self:RenderList(frame) end }) end
            table.sort(options, function(a, b) return a.label < b.label end)
            self:Dropdown(frame.load, options)
        end)
        frame.load:SetPoint("LEFT", frame.live, "RIGHT", 10, 0)
        frame.save = Button(frame, "Liste speichern", 140, function()
            local ok, reason = AHT.Commerce:SaveList(frame.listName:GetText(), frame.list.lines)
            frame.status:SetText(ok and "Liste gespeichert. Erneutes Speichern ersetzt nur diese benannte Liste." or AHT:ErrorText(reason))
        end)
        frame.save:SetPoint("BOTTOMLEFT", 20, 16)
        frame.export = Button(frame, "An Auctionator", 150, function()
            local ok, reason = AHT.Commerce:ExportList({ name = frame.listName:GetText(), lines = frame.list.lines })
            frame.status:SetText(ok and "Als AHT-Liste an Auctionator übergeben. Käufe dort separat bestätigen." or AHT:ErrorText(reason))
        end)
        frame.export:SetPoint("LEFT", frame.save, "RIGHT", 10, 0)
        frame.scan = Button(frame, "Liste scannen", 130, function() AHT.Scanner:Start(frame.list.lines, "shopping") end)
        frame.scan:SetPoint("LEFT", frame.export, "RIGHT", 10, 0)
        frame.watch = Button(frame, "Liste beobachten", 140, function()
            for _, line in ipairs(frame.list.lines) do AHT.Store:AddMaterial(line.itemID, line.name) end
            frame.status:SetText("Alle Items dieser Liste werden nun beobachtet.")
        end)
        frame.watch:SetPoint("LEFT", frame.load, "RIGHT", 10, 0)
        frame.fromWatch = Button(frame, "Beobachtete übernehmen", 205, function()
            local lines = {}
            for _, material in pairs(AHT.DB.materials) do table.insert(lines, { itemID = material.itemID, name = material.name, quantity = 1 }) end
            frame.list = { name = frame.listName:GetText(), lines = lines }; self:RenderList(frame)
        end)
        frame.fromWatch:SetPoint("LEFT", frame.listName, "RIGHT", 15, 0)
    end
    frame.list = { name = frame.listName:GetText(), lines = AHT.Commerce:AggregateShopping() }
    self:RenderList(frame); frame:Show()
end

function UI:ShowRecipeActions(result)
    self:SelectResult(result)
    self:Dropdown(self.detailAction, {
        { label = "Einkauf planen", action = function() self:ShowBuyDialog(result) end },
        { label = "Verkauf vorbereiten", action = function() self:ShowPostDialog(result) end },
        { label = "Rezept und aktuelle Listings", action = function() self:OpenRecipeInAuctionHouse(result) end },
        { label = "Preisverlauf", action = function() self:ShowHistory(result) end },
    })
end

function UI:ShowOrderActions(order)
    self:ShowBuyDialog(AHT.Production:ResultFromOrder(order), order)
    local frame = self.buyDialog
    frame.complete = frame.complete or Button(frame, "Als erledigt markieren", 180, function()
        if frame.order then AHT.Production:CompleteOrder(frame.order) end
        frame:Hide(); self:RequestRefresh()
    end)
    frame.complete:SetPoint("LEFT", frame.cancel, "RIGHT", 10, 0)
    frame.complete:Show()
end

function UI:ShowMaterialActions(result)
    self:Dropdown(self.detailAction, {
        { label = "Aktuelle Listings und Kauf", action = function() self:ShowItemPurchase(result) end },
        { label = "Verkauf vorbereiten", action = function() self:ShowPostDialog({ name = result.name, output = { itemID = result.itemID, quantity = 1 } }) end },
        { label = "Preisverlauf", action = function() self:ShowHistory(result) end },
        { label = result.isWatched and "Nicht mehr beobachten" or "Item beobachten", action = function()
            if result.isWatched then AHT.Store:RemoveMaterial(result.itemID) else AHT.Store:AddMaterial(result.itemID, result.name) end
        end },
    })
end

function UI:ShowOpportunityActions(result)
    if result.side == "sell" then self:ShowPostDialog(result.recipe or { name = result.name, output = { itemID = result.itemID, quantity = 1 } })
    else self:ShowItemPurchase(result) end
end

function UI:ShowItemPurchase(result)
    if AHT.Buyer.pending then AHT:Print(AHT:ErrorText("purchase_in_progress")); return end
    local frame = self:Window("itembuy", "Listings und Einkauf – " .. tostring(result.name), 650, 480)
    frame.result, frame.plan = result, nil
    if not frame.quantity then
        local label = Text(frame, "Gewünschte Stückzahl:", 180); label:SetPoint("TOPLEFT", 16, -55)
        frame.quantity = Input(frame, 80, true); frame.quantity:SetPoint("LEFT", label, "RIGHT", 10, 0)
        frame.summary = Text(frame, "", 600); frame.summary:SetPoint("TOPLEFT", 16, -93); frame.summary:SetHeight(60)
        frame.scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
        frame.scroll:SetPoint("TOPLEFT", 16, -163); frame.scroll:SetPoint("BOTTOMRIGHT", -40, 90)
        frame.content = CreateFrame("Frame", nil, frame.scroll); frame.content:SetSize(585, 300); frame.scroll:SetScrollChild(frame.content)
        frame.listings = Text(frame.content, "", 570); frame.listings:SetPoint("TOPLEFT"); frame.listings:SetJustifyV("TOP")
        frame.status = Text(frame, "", 600); frame.status:SetPoint("BOTTOMLEFT", 16, 52); frame.status:SetHeight(35)
        frame.preview = Button(frame, "Preise prüfen", 150, function()
            frame.preview:Disable(); frame.action:Disable(); frame.status:SetText("Aktuelle Angebote prüfen…")
            AHT.AH:Search(frame.result, function(offers, meta)
                frame.preview:Enable()
                if meta.error then frame.status:SetText(AHT:ErrorText(meta.error)); return end
                local cheapest = offers[1] and offers[1].unitPrice or 0
                local maxPrice = cheapest
                local snapshot = AHT.Store:GetMarketSnapshot(frame.result.itemID, frame.result.itemKey)
                if frame.result.side == "buy" and snapshot and snapshot.marketValue then
                    local cut = (AHT.DB.settings.auctionCutPercent or 5) / 100
                    local reference = snapshot.marketValue * (1 - cut)
                    if frame.result.bestMethod == "NPC" then reference = frame.result.currentPrice + frame.result.vendorProfit end
                    maxPrice = math.min(cheapest, math.floor(reference / (1 + (AHT.DB.settings.minMarginPercent or 10) / 100)))
                end
                local plan = AHT.Buyer:BuildPlan(offers, math.max(1, math.floor(tonumber(frame.quantity:GetText()) or 1)), maxPrice)
                plan.target, plan.ownerTag = frame.result, "itembuy"
                plan.validate = function(live, total)
                    local money = total or live.total
                    local budget = tonumber(AHT.DB.settings.budgetCopper) or 0
                    if money > GetMoney() or budget > 0 and money > budget then return false, "budget_exceeded" end
                    if frame.result.side == "buy" then
                        local reference = AHT.Store:GetMarketSnapshot(frame.result.itemID, frame.result.itemKey)
                        local resale = reference and reference.marketValue
                        if not resale then return false, "preview_required" end
                        local net = resale * live.plannedQuantity * (1 - (AHT.DB.settings.auctionCutPercent or 5) / 100)
                        if frame.result.bestMethod == "NPC" then net = (frame.result.currentPrice + frame.result.vendorProfit) * live.plannedQuantity end
                        if net - money < (AHT.DB.settings.minimumProfitCopper or 1) or (net - money) / math.max(1, money) * 100 < (AHT.DB.settings.minMarginPercent or 10) then return false, "margin_below_minimum" end
                    end
                    return true
                end
                frame.plan = plan
                local rows = { "Preis/Stk | Stückzahl | Stapelpreis" }
                for _, offer in ipairs(offers) do table.insert(rows, Money(offer.unitPrice) .. " | " .. offer.quantity .. " | " .. Money(offer.buyoutAmount or offer.unitPrice * offer.quantity)) end
                frame.listings:SetText(table.concat(rows, "\n\n")); frame.listings:SetHeight(math.max(300, frame.listings:GetStringHeight() + 10)); frame.content:SetHeight(frame.listings:GetHeight())
                frame.summary:SetText(string.format("Angefragt %d | Ganze Stapel: %d Stück | Gesamtkosten %s\nQuelle: Detailabfrage. Preise vor Kauf erneut prüfen.", plan.quantity, plan.plannedQuantity, Money(plan.total)))
                local allowed, reason = plan.validate(plan)
                if plan.missing > 0 or not allowed then frame.status:SetText(AHT:ErrorText(reason or "quantity_or_price_missing")); return end
                frame.action:SetText("Kauf vorbereiten"); frame.action:Enable(); frame.status:SetText("Kaufbereiter Plan. Keine Kaufaktion ohne nächsten Klick.")
            end)
        end)
        frame.preview:SetPoint("BOTTOMLEFT", 16, 16)
        frame.action = Button(frame, "Kauf vorbereiten", 180, function()
            local pending = AHT.Buyer.pending
            if pending and pending.plan.ownerTag ~= "itembuy" then return end
            if pending and pending.state == "ready_to_buy" then AHT.Buyer:StartPendingPurchase(); frame.action:Disable()
            elseif pending and pending.state == "awaiting_user_confirmation" then AHT.Buyer:ConfirmCommodity(); frame.action:Disable()
            elseif frame.plan then
                frame.action:Disable()
                AHT.Buyer:Confirm(frame.plan, function(state, data)
                    if state == "ready" then frame.action:SetText("Kauf auslösen"); frame.action:Enable()
                    elseif state == "price" then
                        frame.action:SetText("Kauf bestätigen"); frame.action:Enable()
                        frame.status:SetText(string.format("%d Stück zu %s – gesamt %s", data.quantity, Money(data.unitPrice), Money(data.totalPrice)))
                    elseif state == "completed" then
                        frame.plan = nil; frame.action:Disable(); frame.preview:Enable()
                        frame.status:SetText("Server bestätigt: " .. (data.purchasedQuantity or 0) .. " Stück für " .. Money(data.actualTotal))
                    elseif state == "error" then frame.status:SetText(AHT:ErrorText(data)); frame.action:Disable(); frame.preview:Enable() end
                end)
            end
        end)
        frame.action:SetPoint("LEFT", frame.preview, "RIGHT", 10, 0)
        frame.quantity:SetScript("OnTextChanged", function() frame.plan = nil; frame.action:Disable() end)
        frame:HookScript("OnHide", function() if AHT.Buyer.pending and AHT.Buyer.pending.plan.ownerTag == "itembuy" then AHT.Buyer:Cancel("dialog_closed") end end)
    end
    frame.quantity:SetText("1"); frame.status:SetText("Gewünschte Menge eingeben und aktuelle Angebote prüfen."); frame:Show()
end

local baseDiagnostics = UI.BuildDiagnosticsRows
function UI:BuildDiagnosticsRows()
    local rows = baseDiagnostics(self)
    table.insert(rows, 1, { kind = "info", text = string.format("Ladephase: %s | Schema: %s | Marktpool: %s", tostring(AHT.State.loadPhase), tostring(AHT.DB.schemaVersion), tostring(AHT.DB.marketPoolKey)) })
    table.insert(rows, 2, { kind = "info", text = "Letzte bestätigte Marktübersicht: " .. (AHT.DB.lastCompletedMarketScanAt and date("%d.%m.%y %H:%M", AHT.DB.lastCompletedMarketScanAt) or "noch nicht bekannt") })
    table.insert(rows, 3, { kind = "info", text = "Migration: " .. AHT.Commerce:SourceText(AHT.DB.marketPools[AHT.DB.marketPoolKey].origin) .. " | WoW speichert bei Reload/Logout; ein Addon kann keine Datei nachladen." })
    return rows
end

function UI:RenderList(frame)
    local lines = { "Material | fehlende Menge | Preislimit/Stk | Gesamtlimit" }
    local maximum, known = 0, true
    for _, line in ipairs(frame.list.lines) do
        if line.maxUnitPrice then maximum = maximum + line.maxUnitPrice * (line.quantity or 0) else known = false end
    end
    table.insert(lines, "Gemeinsames Einkaufsmaximum: " .. (known and Money(maximum) or "noch nicht vollständig geprüft") .. " | Verfügbares Gold: " .. Money(GetMoney()))
    for _, line in ipairs(frame.list.lines) do table.insert(lines, string.format("%s | %d | %s | %s", line.name or line.itemID, line.quantity or 0,
        Money(line.maxUnitPrice), Money(line.maxUnitPrice and line.maxUnitPrice * (line.quantity or 0)))) end
    if #lines == 1 then table.insert(lines, "Keine offenen Einkaufsbedarfe. Zuerst einen Herstellungsplan anlegen.") end
    frame.text:SetText(table.concat(lines, "\n\n")); frame.text:SetHeight(math.max(300, frame.text:GetStringHeight() + 10)); frame.content:SetHeight(frame.text:GetHeight())
    frame.status:SetText("Bestand und Reservierungen sind bereits in den Aufträgen berücksichtigt. Keine automatischen Käufe durch Listen.")
end

function UI:ShowSellingWorkspace(result)
    local frame = self:Window("sell", "Verkauf vorbereiten", 940, 610)
    self.postDialog = frame
    if not frame.gold then
        frame.bagScroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
        frame.bagScroll:SetPoint("TOPLEFT", 16, -70); frame.bagScroll:SetPoint("BOTTOMLEFT", 16, 55); frame.bagScroll:SetWidth(250)
        frame.bagContent = CreateFrame("Frame", nil, frame.bagScroll); frame.bagContent:SetSize(235, 480); frame.bagScroll:SetScrollChild(frame.bagContent)
        frame.bagRows = {}
        frame.bagTitle = Text(frame, "Taschenbestand", 240); frame.bagTitle:SetPoint("TOPLEFT", 16, -50); frame.bagTitle:SetTextColor(1, 0.82, 0)
        frame.itemTitle = Text(frame, "Item auswählen", 600); frame.itemTitle:SetPoint("TOPLEFT", 300, -53)
        frame.summary = Text(frame, "", 600); frame.summary:SetPoint("TOPLEFT", 300, -80); frame.summary:SetHeight(70); frame.summary:SetJustifyV("TOP")
        frame.quantityLabel = Text(frame, "Zielmenge", 75); frame.quantityLabel:SetPoint("TOPLEFT", 300, -165)
        frame.quantity = Input(frame, 70, true); frame.quantity:SetPoint("LEFT", frame.quantityLabel, "RIGHT", 10, 0); frame.quantity:SetText("1")
        frame.gold, frame.silver, frame.copper = Input(frame, 85, true), Input(frame, 55, true), Input(frame, 55, true)
        frame.gold:SetPoint("TOPLEFT", 475, -160); frame.silver:SetPoint("LEFT", frame.gold, "RIGHT", 25, 0); frame.copper:SetPoint("LEFT", frame.silver, "RIGHT", 25, 0)
        local g, s, c = Text(frame, "g"), Text(frame, "s"), Text(frame, "c")
        g:SetPoint("LEFT", frame.gold, "RIGHT", 3, 0); s:SetPoint("LEFT", frame.silver, "RIGHT", 3, 0); c:SetPoint("LEFT", frame.copper, "RIGHT", 3, 0)
        frame.duration = 2
        frame.durationButton = Button(frame, "8 Stunden ▾", 125, function() self:Dropdown(frame.durationButton, {
            { label = "2 Stunden", action = function() frame.duration = 1; frame.durationButton:SetText("2 Stunden ▾"); frame.confirm:Disable() end },
            { label = "8 Stunden", action = function() frame.duration = 2; frame.durationButton:SetText("8 Stunden ▾"); frame.confirm:Disable() end },
            { label = "24 Stunden", action = function() frame.duration = 3; frame.durationButton:SetText("24 Stunden ▾"); frame.confirm:Disable() end },
        }) end)
        frame.durationButton:SetPoint("TOPLEFT", 300, -200)
        frame.refresh = Button(frame, "Angebote prüfen", 150, function() self:RefreshSellPreview() end)
        frame.refresh:SetPoint("LEFT", frame.durationButton, "RIGHT", 10, 0)
        frame.history = Button(frame, "Preisverlauf", 120, function() if frame.result then self:ShowHistory(frame.result) end end)
        frame.history:SetPoint("LEFT", frame.refresh, "RIGHT", 10, 0)
        frame.confirm = Button(frame, "Auktion erstellen", 170, function()
            if not frame.result or not frame.plan then return end
            local plan, reason = AHT.Poster:BuildPlan(frame.result, frame.quantity:GetText(), frame.duration, self:SellInputPrice())
            if not plan then frame.status:SetText(AHT:ErrorText(reason)); frame.confirm:Disable(); return end
            plan.onPosted = function(posted)
                frame.quantity:SetText(tostring(math.max(1, posted.remainingQuantity)))
                frame.status:SetText(posted.remainingQuantity > 0 and ("Auktion bestätigt. Noch " .. posted.remainingQuantity .. " Stück: nächste Auktion separat prüfen und erstellen.") or "Auktion bestätigt. Dies ist eine Postinghistorie, kein Verkaufsnachweis.")
                frame.confirm:Disable(); self:RenderSellingWorkspace()
            end
            local ok, errorMessage = AHT.Poster:Post(plan)
            frame.confirm:Disable()
            frame.status:SetText(ok and "Warte auf Bestätigung des Servers…" or AHT:ErrorText(errorMessage or "api_rejected"))
        end)
        frame.confirm:SetPoint("BOTTOMLEFT", 300, 16)
        frame.confirm:Disable()
        frame.status = Text(frame, "", 600); frame.status:SetPoint("BOTTOMLEFT", 300, 52); frame.status:SetHeight(44)
        frame.detailsScroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
        frame.detailsScroll:SetPoint("TOPLEFT", 300, -275); frame.detailsScroll:SetPoint("BOTTOMRIGHT", -40, 110)
        frame.detailsContent = CreateFrame("Frame", nil, frame.detailsScroll); frame.detailsContent:SetSize(590, 300); frame.detailsScroll:SetScrollChild(frame.detailsContent)
        frame.details = Text(frame.detailsContent, "", 580); frame.details:SetPoint("TOPLEFT"); frame.details:SetJustifyV("TOP")
        frame.current = Button(frame, "Aktuelle Angebote", 150, function() frame.detailMode = "current"; self:RenderSellDetails() end)
        frame.current:SetPoint("TOPLEFT", 300, -240)
        frame.posted = Button(frame, "Postinghistorie", 140, function() frame.detailMode = "posted"; self:RenderSellDetails() end)
        frame.posted:SetPoint("LEFT", frame.current, "RIGHT", 10, 0)
        frame.detailMode = "current"
        for _, input in ipairs({ frame.quantity, frame.gold, frame.silver, frame.copper }) do
            input:SetScript("OnTextChanged", function() frame.confirm:Disable(); frame.plan = nil end)
        end
        frame.bagScroll:HookScript("OnVerticalScroll", function() self:RenderSellBags() end)
    end
    frame.duration = AHT.DB.settings.defaultDuration or 2
    frame.durationButton:SetText(({ "2 Stunden ▾", "8 Stunden ▾", "24 Stunden ▾" })[frame.duration] or "8 Stunden ▾")
    if result then self:SelectSellItem(result) end
    self:RenderSellingWorkspace(); frame:Show()
end

function UI:ShowPostDialog(result)
    if self.actionDialog then self.actionDialog:Hide() end
    self:ShowSellingWorkspace(result)
end

function UI:SellInputPrice()
    local frame = self.postDialog
    return math.floor(math.max(0, tonumber(frame.gold:GetText()) or 0)) * 10000
        + math.floor(math.max(0, tonumber(frame.silver:GetText()) or 0)) * 100
        + math.floor(math.max(0, tonumber(frame.copper:GetText()) or 0))
end

function UI:SelectSellItem(result)
    local frame = self.postDialog
    frame.result, frame.offers, frame.plan = result, nil, nil
    frame.itemTitle:SetText(result.name or AHT:GetItemInfo(result.output.itemID) or tostring(result.output.itemID))
    local recommendation = AHT.Poster:RecommendPrice(result)
    local price = recommendation and recommendation.recommendedPrice or 0
    frame.gold:SetText(tostring(math.floor(price / 10000))); frame.silver:SetText(tostring(math.floor(price % 10000 / 100))); frame.copper:SetText(tostring(price % 100))
    local _, total = AHT.Poster:GetStock(result.output.itemID)
    frame.quantity:SetText(tostring(math.max(1, total)))
    frame.confirm:Disable(); frame.status:SetText("Aktuelle Konkurrenz mit „Angebote prüfen“ abrufen. Keine automatische Auktion.")
    self:RenderSellingWorkspace()
end

function UI:RefreshSellPreview()
    local frame = self.postDialog
    if not frame.result then return end
    if AHT.Buyer.pending or AHT.Scanner.running or AHT.Scanner.marketDiscovery then frame.status:SetText(AHT:ErrorText("purchase_in_progress")); return end
    frame.confirm:Disable(); frame.refresh:Disable(); frame.status:SetText("Aktuelle Konkurrenz wird geprüft…")
    AHT.Poster:RefreshPrice(frame.result, function(recommendation, reason)
        frame.refresh:Enable()
        if reason then frame.status:SetText(AHT:ErrorText(reason)); return end
        frame.offers = AHT.AH.lastResults and AHT.AH.lastResults[tostring(frame.result.output.itemID)] or {}
        local plan, errorMessage = AHT.Poster:BuildPlan(frame.result, frame.quantity:GetText(), frame.duration, self:SellInputPrice())
        frame.plan = plan
        if not plan then frame.status:SetText(AHT:ErrorText(errorMessage)); return end
        frame.status:SetText(string.format("Ziel %d Stück | %d Einzelpost(s) | Dieser Klick: %d Stück\nNettoerlös %s | Kaution %s | Danach noch %d Stück", plan.requestedQuantity, plan.posts, plan.quantity, Money(plan.netIncome), Money(plan.deposit), plan.remainingQuantity))
        frame.confirm:Enable(); self:RenderSellingWorkspace()
    end)
end

function UI:RenderSellingWorkspace()
    local frame = self.postDialog
    if not frame or not frame.gold then return end
    local items = {}
    for _, target in ipairs(AHT.Inventory:GetScanTargets()) do
        local count = AHT.Inventory:GetCount(target.itemID)
        if count.bags > 0 then table.insert(items, { itemID = target.itemID, name = target.name or AHT:GetItemInfo(target.itemID) or tostring(target.itemID), quantity = count.bags }) end
    end
    table.sort(items, function(a, b) return a.name < b.name end)
    frame.bagItems = items; frame.bagContent:SetHeight(math.max(480, #items * 28))
    self:RenderSellBags()
    if frame.result then
        local recommendation = AHT.Poster:RecommendPrice(frame.result)
        local _, stock = AHT.Poster:GetStock(frame.result.output.itemID)
        frame.summary:SetText(string.format("Aktuell %s | Marktwert %s | Empfehlung %s%s\nTaschenbestand %d | Eigenes Minimum %s%s",
            Money(recommendation.currentPrice), Money(recommendation.marketValue), Money(recommendation.recommendedPrice), recommendation.estimateOnly and " (nur historische Orientierung)" or "",
            stock, Money(recommendation.floor), recommendation.outlier and " | Achtung: auffällig niedriger Mindestpreis" or ""))
    end
    self:RenderSellDetails()
end

function UI:RenderSellBags()
    local frame = self.postDialog
    if not frame or not frame.bagItems then return end
    local offset = math.floor(frame.bagScroll:GetVerticalScroll() / 28)
    for i = 1, 21 do
        local row = frame.bagRows[i] or Button(frame.bagContent, "", 235)
        frame.bagRows[i] = row
        local item = frame.bagItems[offset + i]
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -(offset + i - 1) * 28)
        if item then
            row:SetText(tostring(item.quantity) .. "× " .. item.name)
            row:SetScript("OnClick", function() self:SelectSellItem({ name = item.name, output = { itemID = item.itemID, quantity = 1 } }) end)
            row:Show()
        else row:Hide() end
    end
end

function UI:RenderSellDetails()
    local frame = self.postDialog
    if not frame or not frame.details then return end
    local lines = {}
    if frame.detailMode == "posted" then
        table.insert(lines, "Eigene erstellte Auktionen – keine bestätigten Verkäufe")
        for i = #AHT.DB.postingHistory, 1, -1 do
            local entry = AHT.DB.postingHistory[i]
            if frame.result and entry.itemID == frame.result.output.itemID and entry.marketPoolKey == AHT.DB.marketPoolKey then
                table.insert(lines, date("%d.%m. %H:%M", entry.t) .. " | " .. entry.quantity .. "× " .. Money(entry.unitPrice) .. "/Stk")
            end
        end
    else
        table.insert(lines, "Konkurrenz: Stückpreis | Stückzahl | Stapelpreis")
        for _, offer in ipairs(frame.offers or {}) do table.insert(lines, Money(offer.unitPrice) .. " | " .. tostring(offer.quantity) .. " | " .. Money(offer.buyoutAmount or offer.unitPrice * offer.quantity)) end
        if #(frame.offers or {}) == 0 then table.insert(lines, "Noch keine aktuellen Listings geprüft oder keine Konkurrenz vorhanden.") end
    end
    frame.details:SetText(table.concat(lines, "\n\n")); frame.details:SetHeight(math.max(300, frame.details:GetStringHeight() + 10)); frame.detailsContent:SetHeight(frame.details:GetHeight())
end
