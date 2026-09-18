local AHT = WOW4E_AHT

AHT.UI = { rows = {}, dialogs = {} }

local function MakeBackdrop(frame)
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
    end
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

function AHT.UI:Create()
    if self.frame then return end
    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    self.frame = CreateFrame("Frame", "WOW4E_AH_Trader_MainFrame", UIParent, template)
    self.frame:SetSize(760, 560)
    self.frame:SetPoint("CENTER")
    self.frame:SetFrameStrata("DIALOG")
    self.frame:SetMovable(true)
    self.frame:EnableMouse(true)
    self.frame:RegisterForDrag("LeftButton")
    self.frame:SetScript("OnDragStart", self.frame.StartMoving)
    self.frame:SetScript("OnDragStop", self.frame.StopMovingOrSizing)
    MakeBackdrop(self.frame)
    self.frame:Hide()

    self.title = Label(self.frame, "WoW4E AH Trader", 500)
    self.title:SetPoint("TOPLEFT", 18, -16)
    self.title:SetFontObject("GameFontHighlightLarge")

    self.close = Button(self.frame, nil, CLOSE or "Close", 70, 22)
    self.close:SetPoint("TOPRIGHT", -14, -12)
    self.close:SetScript("OnClick", function() self.frame:Hide() end)

    self.status = Label(self.frame, "", 720)
    self.status:SetPoint("TOPLEFT", 18, -46)

    self.scanButton = Button(self.frame, nil, "Scan", 100, 24)
    self.scanButton:SetPoint("TOPLEFT", 18, -70)
    self.scanButton:SetScript("OnClick", function()
        if AHT.Scanner.running then AHT.Scanner:Stop("user") else AHT.Scanner:Start() end
        self:RefreshStatus()
    end)

    self.recipeButton = Button(self.frame, nil, "Rezepte", 100, 24)
    self.recipeButton:SetPoint("LEFT", self.scanButton, "RIGHT", 8, 0)
    self.recipeButton:SetScript("OnClick", function()
        if AHT.Recipes then AHT.Recipes:Refresh() end
        AHT:Refresh()
    end)

    self.matsButton = Button(self.frame, nil, "Materialien", 100, 24)
    self.matsButton:SetPoint("LEFT", self.recipeButton, "RIGHT", 8, 0)
    self.matsButton:SetScript("OnClick", function() self:ShowMaterials() end)

    self.transmuteButton = Button(self.frame, nil, "Transmute", 100, 24)
    self.transmuteButton:SetPoint("LEFT", self.matsButton, "RIGHT", 8, 0)
    self.transmuteButton:SetScript("OnClick", function()
        if AHT.Transmute then AHT.Transmute:Print() end
    end)

    self.reputationButton = Button(self.frame, nil, "Ruf", 70, 24)
    self.reputationButton:SetPoint("LEFT", self.transmuteButton, "RIGHT", 8, 0)
    self.reputationButton:SetScript("OnClick", function()
        if AHT.Reputation then AHT.Reputation:Print() end
    end)

    self.debugButton = Button(self.frame, nil, "Debug", 80, 24)
    self.debugButton:SetPoint("LEFT", self.reputationButton, "RIGHT", 8, 0)
    self.debugButton:SetScript("OnClick", function()
        if AHT.Diagnostics then AHT.Diagnostics:Print() end
    end)

    self.materialInput = CreateFrame("EditBox", nil, self.frame, "InputBoxTemplate")
    self.materialInput:SetSize(190, 24)
    self.materialInput:SetPoint("TOPRIGHT", -115, -70)
    self.materialInput:SetAutoFocus(false)
    self.materialInput:SetTextInsets(6, 6, 0, 0)
    self.materialInput:SetScript("OnEnterPressed", function(box)
        if box:GetText() ~= "" then AHT.Mats:Add(box:GetText()); box:SetText("") end
    end)
    self.materialInput:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)

    self.materialAdd = Button(self.frame, nil, "+ Mat", 75, 24)
    self.materialAdd:SetPoint("LEFT", self.materialInput, "RIGHT", 8, 0)
    self.materialAdd:SetScript("OnClick", function()
        local value = self.materialInput:GetText()
        if value ~= "" then AHT.Mats:Add(value); self.materialInput:SetText("") end
    end)

    local scrollTemplate = "UIPanelScrollFrameTemplate"
    self.scroll = CreateFrame("ScrollFrame", nil, self.frame, scrollTemplate)
    self.scroll:SetPoint("TOPLEFT", 18, -108)
    self.scroll:SetPoint("BOTTOMRIGHT", -34, 18)
    self.content = CreateFrame("Frame", nil, self.scroll)
    self.content:SetSize(690, 420)
    self.scroll:SetScrollChild(self.content)

    self:CreateRows()
    self:Refresh()
end

function AHT.UI:CreateRows()
    for index = 1, 24 do
        local row = CreateFrame("Button", nil, self.content)
        row:SetSize(690, 20)
        row:SetPoint("TOPLEFT", 0, -((index - 1) * 21))
        row:EnableMouse(true)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bg:SetColorTexture(index % 2 == 0 and 0.08 or 0.12, 0.08, 0.04, 0.45)
        row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", 6, 0)
        row.text:SetWidth(680)
        row.text:SetJustifyH("LEFT")
        row:SetScript("OnClick", function()
            if row.result then self:ShowRecipeActions(row.result) end
        end)
        row:SetScript("OnEnter", function()
            if row.result then row.bg:SetColorTexture(0.2, 0.2, 0.05, 0.75) end
        end)
        row:SetScript("OnLeave", function()
            row.bg:SetColorTexture(index % 2 == 0 and 0.08 or 0.12, 0.08, 0.04, 0.45)
        end)
        self.rows[index] = row
    end
end

function AHT.UI:RefreshStatus()
    if not self.status then return end
    local state = AHT.State.status or "?"
    local progress = ""
    if AHT.Scanner and AHT.Scanner.running then
        progress = string.format(" | %d/%d", AHT.Scanner.completed, AHT.Scanner.total)
    end
    self.status:SetText("Status: " .. state .. progress)
    self.scanButton:SetText(AHT.Scanner and AHT.Scanner.running and "Abbrechen" or "Scan")
end

function AHT.UI:Refresh()
    if not self.frame then return end
    if AHT.Calculator then AHT.Calculator:Refresh() end
    local results = AHT.Calculator and AHT.Calculator.results or {}
    self.content:SetHeight(math.max(420, #results * 21))
    for index, row in ipairs(self.rows) do
        local result = results[index]
        row.result = result
        if result then
            local profit = result.profit and AHT:FormatMoneyPlain(result.profit) or AHT.L.incomplete
            local margin = result.margin and string.format("%.1f%%", result.margin) or "-"
            local cost = result.ingredientCost and AHT:FormatMoneyPlain(result.ingredientCost) or "?"
            local sale = result.salePrice and AHT:FormatMoneyPlain(result.salePrice) or "?"
            local prefix = result.isDeal and "★ " or ""
            row.text:SetText(string.format("%s%-34s Kosten %8s | Verkauf %8s | Gewinn %8s | %s", prefix, result.name or "?", cost, sale, profit, margin))
            row:Show()
        else
            row.text:SetText("")
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
    if not self.ahButton then
        self.ahButton = Button(UIParent, "WOW4E_AH_Trader_AHButton", "AH Trader", 100, 24)
        self.ahButton:SetPoint("TOP", 0, -90)
        self.ahButton:SetFrameStrata("HIGH")
        self.ahButton:SetScript("OnClick", function() self:Show() end)
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
    self:Show()
    local text = "Materialien:\n"
    for _, material in pairs(AHT.DB.materials or {}) do
        local record = AHT.Store:GetByItemID(material.itemID)
        text = text .. string.format("%s: %s\n", material.name or tostring(material.itemID), record and AHT:FormatMoneyPlain(record.minPrice) or AHT.L.noData)
    end
    AHT:Print(text:gsub("\n", " | "))
end
