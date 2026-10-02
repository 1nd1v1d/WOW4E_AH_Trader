local AHT = WOW4E_AHT

AHT.Inventory = {
    bankOpen = false,
}

local function CharacterIdentity()
    local name = UnitName and UnitName("player") or nil
    local realmName = GetNormalizedRealmName and GetNormalizedRealmName() or nil
    if not realmName or realmName == "" then realmName = GetRealmName and GetRealmName() or nil end

    local factionName, factionToken
    if UnitFactionGroup then factionName, factionToken = UnitFactionGroup("player") end

    local mode
    if type(IsPVPRealm) == "function" then
        local ok, isPVP = pcall(IsPVPRealm)
        if ok and type(isPVP) == "boolean" then mode = isPVP and "pvp" or "pve" end
    end

    local realm = string.lower(tostring(realmName or "unknown"))
    local faction = factionToken or factionName
    if faction ~= nil then faction = string.lower(tostring(faction)) end
    return {
        name = tostring(name or "unknown"),
        realmName = tostring(realmName or "unknown"),
        realm = realm,
        faction = faction,
        mode = mode,
    }
end

local function CharacterKey(identity)
    identity = identity or CharacterIdentity()
    return table.concat({
        tostring(identity.realm or "unknown"),
        tostring(identity.faction or "unknown"),
        tostring(identity.mode or "unknown"),
        tostring(identity.name or "unknown"),
    }, ":")
end

local function SameInventoryPool(store, identity)
    return store and identity and identity.realm ~= "unknown" and identity.faction and identity.mode
        and store.realm == identity.realm
        and store.faction == identity.faction
        and store.mode == identity.mode
end

local function AddContainerCount(counts, itemID, count)
    itemID = tonumber(itemID)
    if not itemID then return end
    local key = tostring(itemID)
    counts[key] = (tonumber(counts[key]) or 0) + math.max(0, tonumber(count) or 1)
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
        if not ok then return nil, nil, false end
        if not info then return nil, nil, true end
        return tonumber(info.itemID) or AHT:GetItemID(info.hyperlink), tonumber(info.stackCount or info.count) or 1, true
    end
    if type(GetContainerItemLink) == "function" then
        local ok, link = pcall(GetContainerItemLink, bag, slot)
        if not ok then return nil, nil, false end
        if ok then
            local _, count
            if type(GetContainerItemInfo) == "function" then
                local infoOK
                infoOK, _, count = pcall(GetContainerItemInfo, bag, slot)
                if not infoOK then return nil, nil, false end
            end
            return AHT:GetItemID(link), tonumber(count) or 1, true
        end
    end
    return nil, nil, false
end

local function ScanContainer(bag, callback)
    local getSlots = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
    if type(getSlots) ~= "function" then return false end
    local ok, slots = pcall(getSlots, bag)
    if not ok or type(slots) ~= "number" or slots < 0 then return false end
    for slot = 1, slots do
        local itemID, count, readOK = ContainerItemID(bag, slot)
        if not readOK then return false end
        if itemID then callback(itemID, count) end
    end
    return true
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
    self:RefreshBags()
    if self.bankOpen then self:RefreshKnownItems() end
end

function AHT.Inventory:GetCharacterKey()
    return CharacterKey(CharacterIdentity())
end

function AHT.Inventory:GetCharacterStore()
    if not AHT.DB then return nil end
    AHT.DB.inventory = AHT.DB.inventory or { characters = {} }
    AHT.DB.inventory.characters = AHT.DB.inventory.characters or {}
    local identity = CharacterIdentity()
    local key = CharacterKey(identity)
    local characters = AHT.DB.inventory.characters
    local store = characters[key]

    if not store then
        local candidates = {
            identity.realmName .. ":" .. identity.name,
            table.concat({ identity.realm, identity.faction or "unknown", "unknown", identity.name }, ":"),
            table.concat({ identity.realm, "unknown", identity.mode or "unknown", identity.name }, ":"),
            table.concat({ identity.realm, "unknown", "unknown", identity.name }, ":"),
        }
        for _, candidateKey in ipairs(candidates) do
            local candidate = characters[candidateKey]
            local modeCanMigrate = not candidate or not candidate.mode or candidate.mode == "unknown" or candidate.mode == identity.mode
            local factionCanMigrate = not candidate or not candidate.faction or candidate.faction == "unknown" or candidate.faction == identity.faction
            if candidate and modeCanMigrate and factionCanMigrate then
                store = candidate
                characters[candidateKey] = nil
                characters[key] = store
                break
            end
        end
    end

    if not store then
        store = { bags = {}, bank = {}, bankUpdatedAt = 0 }
        characters[key] = store
    end
    store.bags = store.bags or {}
    store.bank = store.bank or {}
    store.characterName = identity.name
    store.realmName = identity.realmName
    store.realm = identity.realm
    store.faction = identity.faction or "unknown"
    store.mode = identity.mode or "unknown"
    return store
end

function AHT.Inventory:GetPoolStores()
    local currentStore = self:GetCharacterStore()
    if not currentStore then return {}, nil end

    local identity = CharacterIdentity()
    local currentKey = CharacterKey(identity)
    local stores = { { key = currentKey, store = currentStore, current = true } }
    if identity.realm == "unknown" or not identity.faction or not identity.mode then return stores, identity end

    for key, store in pairs(AHT.DB.inventory.characters or {}) do
        if key ~= currentKey and SameInventoryPool(store, identity) then
            table.insert(stores, { key = key, store = store, current = false })
        end
    end
    return stores, identity
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
    local characterStore = self:GetCharacterStore()
    for itemID in pairs(characterStore and characterStore.bank or {}) do Add(itemID) end
    -- Include visible contents so bank snapshots cover items that are not on
    -- the material watchlist yet.
    ScanVisibleContainers(self.bankOpen, Add)
    return ids
end

function AHT.Inventory:GetAvailableItemSet()
    local available = {}
    local function Add(itemID)
        itemID = tonumber(itemID)
        if itemID then available[tostring(itemID)] = true end
    end
    ScanVisibleContainers(self.bankOpen, Add)
    local stores = self:GetPoolStores()
    for _, entry in ipairs(stores) do
        local store = entry.store
        if not entry.current then
            for itemID, count in pairs(store.bags or {}) do
                if (tonumber(count) or 0) > 0 then Add(itemID) end
            end
        end
        if (entry.current and not self.bankOpen) or not entry.current then
            for itemID, count in pairs(store.bank or {}) do
                if (tonumber(count) or 0) > 0 then Add(itemID) end
            end
        end
    end
    return available
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
    local stores = self:GetPoolStores()
    for _, entry in ipairs(stores) do
        if not entry.current then
            for itemID, count in pairs(entry.store.bags or {}) do
                if (tonumber(count) or 0) > 0 then Add(itemID, nil, nil, "inventory") end
            end
            for itemID, count in pairs(entry.store.bank or {}) do
                if (tonumber(count) or 0) > 0 then Add(itemID, nil, nil, "inventory") end
            end
        end
    end
    for _, record in pairs(AHT.DB and AHT.DB.market or {}) do
        Add(record.itemID, record.name, record.itemKey, record.kind or "market")
    end
    table.sort(targets, function(a, b)
        return string.lower(tostring(a.name or a.itemID)) < string.lower(tostring(b.name or b.itemID))
    end)
    return targets
end

function AHT.Inventory:RefreshBags()
    local store = self:GetCharacterStore()
    if not store then return false end

    local bags = {}
    local bagSlots = tonumber(NUM_BAG_SLOTS) or 4
    local scanComplete = true
    for bag = 0, bagSlots do
        if not ScanContainer(bag, function(itemID, count) AddContainerCount(bags, itemID, count) end) then
            scanComplete = false
        end
    end
    if not scanComplete then return false end

    store.bags = bags
    store.bagsUpdatedAt = AHT:Now()
    if AHT.Store then AHT.Store:Save() end
    return true
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
    if not itemID then return { bags = 0, bank = 0, total = 0, bankKnown = false, characterCount = 0 } end

    local liveBags = QueryItemCount(itemID, false)
    local bagsKnown = liveBags ~= nil
    liveBags = liveBags or 0
    local store = self:GetCharacterStore()
    local bank = store and tonumber(store.bank[tostring(itemID)]) or nil

    if self.bankOpen then
        bank = self:RefreshBankItem(itemID)
    elseif bank == nil then
        -- Some Forever builds expose bank counts even while the bank is
        -- closed. Accept a positive result, but never overwrite a known
        -- snapshot with an ambiguous zero outside the bank.
        local withBank = QueryItemCount(itemID, true)
        if withBank and withBank > liveBags then
            bank = withBank - liveBags
            if store then
                store.bank[tostring(itemID)] = bank
                store.bankUpdatedAt = AHT:Now()
            end
        end
    end

    local accountBags, accountBank = liveBags, math.max(0, tonumber(bank) or 0)
    local accountBagsKnown, accountBankKnown = bagsKnown, bank ~= nil
    local oldestSnapshotAt
    local function IncludeTimestamp(timestamp)
        timestamp = tonumber(timestamp) or 0
        if timestamp > 0 and (not oldestSnapshotAt or timestamp < oldestSnapshotAt) then oldestSnapshotAt = timestamp end
    end

    local poolStores, identity = self:GetPoolStores()
    for _, entry in ipairs(poolStores) do
        local characterStore = entry.store
        if not entry.current then
            local savedBags = characterStore.bags
            if type(savedBags) == "table" and tonumber(characterStore.bagsUpdatedAt) then
                accountBags = accountBags + math.max(0, tonumber(savedBags[tostring(itemID)]) or 0)
                IncludeTimestamp(characterStore.bagsUpdatedAt)
            else
                accountBagsKnown = false
            end

            local savedBank = characterStore.bank and tonumber(characterStore.bank[tostring(itemID)])
            if savedBank ~= nil then
                accountBank = accountBank + math.max(0, savedBank)
            else
                accountBankKnown = false
            end
        end

        IncludeTimestamp(characterStore.bagsUpdatedAt)
        IncludeTimestamp(characterStore.bankUpdatedAt)
    end

    accountBank = math.max(0, accountBank)
    return {
        bags = liveBags,
        bank = math.max(0, tonumber(bank) or 0),
        total = accountBags + accountBank,
        bankKnown = bank ~= nil,
        accountBags = accountBags,
        accountBank = accountBank,
        accountBagsKnown = accountBagsKnown,
        accountBankKnown = accountBankKnown,
        characterBags = liveBags,
        characterBank = math.max(0, tonumber(bank) or 0),
        characterCount = #poolStores,
        modeKnown = identity and identity.mode ~= nil or false,
        poolKnown = identity and identity.realm ~= "unknown" and identity.faction ~= nil and identity.mode ~= nil or false,
        bankUpdatedAt = store and store.bankUpdatedAt or 0,
        inventoryUpdatedAt = oldestSnapshotAt,
    }
end

function AHT.Inventory:OnEvent(eventName)
    if eventName == "PLAYER_LOGOUT" then
        self:RefreshBags()
        if self.bankOpen then self:RefreshKnownItems() end
    elseif eventName == "BAG_UPDATE_DELAYED" then
        self:RefreshBags()
        if self.bankOpen then self:RefreshKnownItems() end
    elseif eventName == "BANKFRAME_OPENED" then
        self.bankOpen = true
        self:RefreshKnownItems()
    elseif eventName == "BANKFRAME_CLOSED" then
        self:RefreshKnownItems()
        self.bankOpen = false
    elseif self.bankOpen and (eventName == "PLAYERBANKSLOTS_CHANGED" or
            eventName == "PLAYERREAGENTBANKSLOTS_CHANGED") then
        self:RefreshKnownItems()
    end
end
