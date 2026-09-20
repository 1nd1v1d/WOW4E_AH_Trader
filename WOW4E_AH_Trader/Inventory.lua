local AHT = WOW4E_AHT

AHT.Inventory = {
    bankOpen = false,
}

local function CharacterKey()
    local name = UnitName and UnitName("player") or nil
    local realm = GetNormalizedRealmName and GetNormalizedRealmName() or nil
    if not realm or realm == "" then realm = GetRealmName and GetRealmName() or "unknown" end
    return tostring(realm or "unknown") .. ":" .. tostring(name or "unknown")
end

local function QueryItemCount(itemID, includeBank)
    itemID = tonumber(itemID)
    if not itemID then return nil end

    if C_Item and type(C_Item.GetItemCount) == "function" then
        -- Forever currently exposes the modern item-count contract. The
        -- trailing flags include reagent-bank stock while deliberately
        -- excluding account-bank stock from this character's production plan.
        local ok, count = pcall(C_Item.GetItemCount, itemID, includeBank == true, false, true, false)
        if ok and type(count) == "number" then return math.max(0, count) end
        ok, count = pcall(C_Item.GetItemCount, itemID, includeBank == true, false, true)
        if ok and type(count) == "number" then return math.max(0, count) end
        ok, count = pcall(C_Item.GetItemCount, itemID, includeBank == true)
        if ok and type(count) == "number" then return math.max(0, count) end
    end
    if type(GetItemCount) == "function" then
        local ok, count = pcall(GetItemCount, itemID, includeBank == true, false, true)
        if ok and type(count) == "number" then return math.max(0, count) end
    end
    return nil
end

local function ContainerItemID(bag, slot)
    if C_Container and type(C_Container.GetContainerItemInfo) == "function" then
        local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
        if ok and info then
            return tonumber(info.itemID) or AHT:GetItemID(info.hyperlink)
        end
    end
    if type(GetContainerItemLink) == "function" then
        local ok, link = pcall(GetContainerItemLink, bag, slot)
        if ok then return AHT:GetItemID(link) end
    end
end

local function ScanContainer(bag, callback)
    if not C_Container or type(C_Container.GetContainerNumSlots) ~= "function" then return end
    local ok, slots = pcall(C_Container.GetContainerNumSlots, bag)
    if not ok or not slots then return end
    for slot = 1, slots do
        local itemID = ContainerItemID(bag, slot)
        if itemID then callback(itemID) end
    end
end

local function ScanVisibleContainers(includeBank, callback)
    local bagSlots = tonumber(NUM_BAG_SLOTS) or 4
    for bag = 0, bagSlots do ScanContainer(bag, callback) end
    if not includeBank then return end

    ScanContainer(-1, callback)
    local bankSlots = tonumber(NUM_BANKBAGSLOTS) or 7
    for bag = -2, -(bankSlots + 1), -1 do ScanContainer(bag, callback) end
    if REAGENTBANK_CONTAINER then ScanContainer(REAGENTBANK_CONTAINER, callback) end
end

function AHT.Inventory:Initialize()
    if not AHT.DB then return end
    AHT.DB.inventory = AHT.DB.inventory or { characters = {} }
    AHT.DB.inventory.characters = AHT.DB.inventory.characters or {}
    self.bankOpen = BankFrame and BankFrame.IsShown and BankFrame:IsShown() == true or false
    if self.bankOpen then self:RefreshKnownItems() end
end

function AHT.Inventory:GetCharacterKey()
    return CharacterKey()
end

function AHT.Inventory:GetCharacterStore()
    if not AHT.DB then return nil end
    AHT.DB.inventory = AHT.DB.inventory or { characters = {} }
    AHT.DB.inventory.characters = AHT.DB.inventory.characters or {}
    local key = CharacterKey()
    local store = AHT.DB.inventory.characters[key]
    if not store then
        store = { bank = {}, bankUpdatedAt = 0 }
        AHT.DB.inventory.characters[key] = store
    end
    store.bank = store.bank or {}
    return store
end

function AHT.Inventory:GetKnownItemIDs()
    local ids, seen = {}, {}
    local function Add(itemID)
        itemID = tonumber(itemID)
        if itemID and not seen[itemID] then
            seen[itemID] = true
            table.insert(ids, itemID)
        end
    end

    if AHT.Recipes then
        for _, recipe in ipairs(AHT.Recipes:GetList() or {}) do
            if recipe.output then Add(recipe.output.itemID) end
            for _, reagent in ipairs(recipe.reagents or {}) do Add(reagent.itemID) end
        end
    end
    local production = AHT.DB and AHT.DB.production
    for _, order in pairs(production and production.orders or {}) do
        if order.status ~= "completed" and order.status ~= "cancelled" then
            for _, requirement in ipairs(order.requirements or {}) do Add(requirement.itemID) end
        end
    end

    for _, material in pairs(AHT.DB and AHT.DB.materials or {}) do Add(material.itemID) end
    for _, record in pairs(AHT.DB and AHT.DB.market or {}) do Add(record.itemID) end
    -- Include visible contents so bank snapshots cover items that are not on
    -- the material watchlist yet.
    ScanVisibleContainers(self.bankOpen, Add)
    return ids
end

function AHT.Inventory:GetScanTargets()
    local targets, seen = {}, {}
    local function Add(itemID, name, itemKey, kind)
        itemID = tonumber(itemID)
        if not itemID or seen[itemID] then return end
        seen[itemID] = true
        table.insert(targets, {
            itemID = itemID,
            name = name or AHT:GetItemInfo(itemID) or tostring(itemID),
            itemKey = itemKey,
            kind = kind or "inventory",
        })
    end

    for _, itemID in ipairs(self:GetKnownItemIDs()) do Add(itemID) end
    ScanVisibleContainers(self.bankOpen, function(itemID) Add(itemID, nil, nil, "inventory") end)
    for _, record in pairs(AHT.DB and AHT.DB.market or {}) do
        Add(record.itemID, record.name, record.itemKey, record.kind or "market")
    end
    table.sort(targets, function(a, b)
        return string.lower(tostring(a.name or a.itemID)) < string.lower(tostring(b.name or b.itemID))
    end)
    return targets
end

function AHT.Inventory:RefreshBankItem(itemID)
    if not self.bankOpen then return nil end
    local bags = QueryItemCount(itemID, false) or 0
    local total = QueryItemCount(itemID, true)
    if total == nil then return nil end
    local store = self:GetCharacterStore()
    if not store then return nil end
    local bank = math.max(0, total - bags)
    store.bank[tostring(itemID)] = bank
    store.bankUpdatedAt = AHT:Now()
    return bank
end

function AHT.Inventory:RefreshKnownItems()
    if not self.bankOpen then return end
    for _, itemID in ipairs(self:GetKnownItemIDs()) do self:RefreshBankItem(itemID) end
    if AHT.Store then AHT.Store:Save() end
end

function AHT.Inventory:GetCount(itemID)
    itemID = tonumber(itemID)
    if not itemID then return { bags = 0, bank = 0, total = 0, bankKnown = false } end

    local bags = QueryItemCount(itemID, false) or 0
    local store = self:GetCharacterStore()
    local bank = store and tonumber(store.bank[tostring(itemID)]) or nil

    if self.bankOpen then
        bank = self:RefreshBankItem(itemID)
    elseif bank == nil then
        -- Some Forever builds expose bank counts even while the bank is
        -- closed. Accept a positive result, but never overwrite a known
        -- snapshot with an ambiguous zero outside the bank.
        local withBank = QueryItemCount(itemID, true)
        if withBank and withBank > bags then
            bank = withBank - bags
            if store then store.bank[tostring(itemID)] = bank end
        end
    end

    local bankKnown = bank ~= nil
    bank = math.max(0, tonumber(bank) or 0)
    return {
        bags = bags,
        bank = bank,
        total = bags + bank,
        bankKnown = bankKnown,
        bankUpdatedAt = store and store.bankUpdatedAt or 0,
    }
end

function AHT.Inventory:OnEvent(eventName)
    if eventName == "BANKFRAME_OPENED" then
        self.bankOpen = true
        self:RefreshKnownItems()
    elseif eventName == "BANKFRAME_CLOSED" then
        self:RefreshKnownItems()
        self.bankOpen = false
    elseif self.bankOpen and (eventName == "BAG_UPDATE_DELAYED" or
            eventName == "PLAYERBANKSLOTS_CHANGED" or
            eventName == "PLAYERREAGENTBANKSLOTS_CHANGED") then
        self:RefreshKnownItems()
    end
end
