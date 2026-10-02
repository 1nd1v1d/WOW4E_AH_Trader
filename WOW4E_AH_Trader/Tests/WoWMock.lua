TEST = { now = 2000000000, timers = {}, frames = {}, realm = "Forever", characterName = "Testmage", factionGroup = "Alliance", realmMode = "pve", stock = {}, money = 1000000, calls = {} }
function TEST.Flush(limit)
    for _ = 1, limit or 200 do
        local timer = table.remove(TEST.timers, 1)
        if not timer then return end
        timer()
    end
    error("Timer loop exceeded")
end
function TEST.Click(frame) local f = frame:GetScript("OnClick"); assert(f, "Missing OnClick"); f(frame, "LeftButton") end
local methods = {}
function methods:SetScript(name, fn) assert(type(fn) == "function"); self.scripts[name] = fn end
function methods:HookScript(name, fn)
    assert(type(fn) == "function", "HookScript requires function")
    local prior = self.scripts[name]
    self.scripts[name] = function(...) if prior then prior(...) end; fn(...) end
end
function methods:GetScript(name) return self.scripts[name] end
function methods:Show() local was = self.shown; self.shown = true; if not was and self.scripts.OnShow then self.scripts.OnShow(self) end end
function methods:Hide() local was = self.shown; self.shown = false; if was and self.scripts.OnHide then self.scripts.OnHide(self) end end
function methods:IsShown() return self.shown end
function methods:SetText(value) self.text = tostring(value); if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self) end end
function methods:GetText() return self.text or "" end
function methods:SetSize(w, h) self.width, self.height = w, h end
function methods:SetWidth(w) self.width = w end
function methods:SetHeight(h) self.height = h end
function methods:GetWidth() return self.width or 700 end
function methods:GetHeight() return self.height or 300 end
function methods:GetStringHeight() return math.max(14, #self:GetText() / math.max(1, self:GetWidth() / 7) * 14) end
function methods:GetCenter() return self.cx or 960, self.cy or 540 end
function methods:GetFrameLevel() return self.level or 1 end
function methods:SetFrameLevel(n) self.level = n end
function methods:SetVerticalScroll(n) self.scroll = n; if self.scripts.OnVerticalScroll then self.scripts.OnVerticalScroll(self, n) end end
function methods:GetVerticalScroll() return self.scroll or 0 end
function methods:SetPoint(...) self.point = {...} end
function methods:GetPoint() return unpack(self.point or {"CENTER", UIParent, "CENTER", 0, 0}) end
function methods:Enable() self.enabled = true end
function methods:Disable() self.enabled = false end
function methods:SetEnabled(v) self.enabled = v end
function methods:IsEnabled() return self.enabled ~= false end
function methods:GetFontString() self.font = self.font or self:CreateFontString(); return self.font end
function methods:GetChildren() return unpack(self.children) end
function methods:GetParent() return self.parent end
function methods:GetName() return self.name end
function methods:IsForbidden() return false end
function methods:SetColorTexture(...) self.color = {...} end
function methods:IsObjectType(t) return self.kind == t end
function methods:CreateTexture() return CreateFrame("Texture", nil, self) end
function methods:CreateFontString() return CreateFrame("FontString", nil, self) end
for _, name in ipairs({ "RegisterEvent", "SetAutoFocus", "SetNumeric", "SetTextInsets", "SetJustifyH", "SetJustifyV", "SetFontObject", "SetTextColor", "SetWordWrap",
    "ClearAllPoints", "SetAllPoints", "SetBackdrop", "SetBackdropBorderColor", "SetAlpha", "SetTexture", "SetFrameStrata", "SetToplevel", "SetClampedToScreen", "SetMovable",
    "EnableMouse", "RegisterForDrag", "RegisterForClicks", "StartMoving", "StopMovingOrSizing", "SetResizable", "SetResizeBounds", "StartSizing", "SetScrollChild",
    "ClearFocus", "Raise", "EnableKeyboard", "SetPropagateKeyboardInput", "SetOwner", "ClearLines", "AddLine", "AddDoubleLine", "SetNormalTexture" }) do
    methods[name] = function() end
end
function CreateFrame(kind, name, parent, template)
    local frame = setmetatable({ kind = kind, name = name, parent = parent, template = template, shown = true, enabled = true, scripts = {}, children = {} }, { __index = methods })
    if name then _G[name] = frame end
    if parent then table.insert(parent.children, frame) end
    table.insert(TEST.frames, frame)
    return frame
end
UIParent = CreateFrame("Frame", "UIParent"); UIParent:SetSize(1920, 1080)
GameTooltip = CreateFrame("GameTooltip", "GameTooltip")
ShoppingTooltip1 = CreateFrame("GameTooltip", "ShoppingTooltip1")
ShoppingTooltip2 = CreateFrame("GameTooltip", "ShoppingTooltip2")
BackdropTemplateMixin = {}; SlashCmdList = {}; UISpecialFrames = {}; NUM_BAG_SLOTS = 4
Enum = { ItemCommodityStatus = { Commodity = 1 } }; WOW_PROJECT_ID = 1; WOW_PROJECT_MAINLINE = 1
function GetServerTime() return TEST.now end
time = GetServerTime
function GetTime() return TEST.now - 1999999000 end
function GetMoney() return TEST.money end
function GetNormalizedRealmName() return TEST.realm end
GetRealmName = GetNormalizedRealmName
function GetAutoCompleteRealms() return { TEST.realm } end
function GetCurrentRegion() return 3 end
function UnitName() return TEST.characterName end
function UnitFactionGroup() return TEST.factionName or TEST.factionGroup, TEST.factionGroup end
function IsPVPRealm() return TEST.realmMode == "pvp" end
function GetBuildInfo() return "1.60.1", "69913", "Sep 17 2026", 16001 end
function GetLocale() return "deDE" end
function date(format, t) return os.date(format, t) end
function GetItemInfo(id) return "Item " .. tostring(id), "item:" .. tostring(id), 1, 5, 1, "Test", "Test", 20, nil, "icon", 1 end
function PanelTemplates_SelectTab(frame) frame.selected = true end
function PanelTemplates_DeselectTab(frame) frame.selected = false end
function InCombatLockdown() return false end
C_Timer = { After = function(_, fn) table.insert(TEST.timers, fn) end }
C_Item = { GetItemInfo = GetItemInfo, GetItemCount = function(id, bank) local c = TEST.stock[id] or {}; return (c.bags or 0) + (bank and (c.bank or 0) or 0) end }
C_Container = { GetContainerNumSlots = function(bag)
    if TEST.containers then return #(TEST.containers[bag] or {}) end
    return bag == 0 and 2 or 0
end,
    GetContainerItemInfo = function(bag, slot)
        if TEST.containers then return TEST.containers[bag] and TEST.containers[bag][slot] end
        if bag == 0 then return { itemID = 100, stackCount = slot == 1 and 3 or 5 } end
    end }
ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot) return { bagID = bag, slotIndex = slot } end }
C_AuctionHouse = { MakeItemKey = function(id) return { itemID = id, itemLevel = 5, itemSuffix = 0, battlePetSpeciesID = 0 } end,
    GetItemCommodityStatus = function() return 0 end, CalculateItemDeposit = function() return 10 end,
    PostItem = function(...) TEST.calls.post = {...}; return true end,
    PlaceBid = function(...) TEST.calls.bid = {...}; return true end,
    StartCommoditiesPurchase = function(...) TEST.calls.start = {...}; return true end,
    ConfirmCommoditiesPurchase = function(...) TEST.calls.confirm = {...}; return true end,
    CancelCommoditiesPurchase = function() TEST.calls.cancel = true end }
