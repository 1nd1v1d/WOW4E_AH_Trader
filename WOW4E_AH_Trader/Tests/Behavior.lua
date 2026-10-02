local AHT = WOW4E_AHT
local passed = 0
local function test(name, fn) fn(); passed = passed + 1; print("PASS " .. name) end
local function equal(a, b) assert(a == b, tostring(a) .. " ~= " .. tostring(b)) end
local function record(id, price, source, prices)
    return AHT.Store:RecordMarket({ itemID = id, name = "Item " .. id }, { minPrice = price, prices = prices or { price }, totalQuantity = 100, listingCount = 3, source = source })
end
WOW4E_AHT_DB = { schemaVersion = 4, recipes = { { recipeID = 1, name = "Testrezept", professionName = "Alchemie", output = { itemID = 100, quantity = 2 }, reagents = { { itemID = 200, quantity = 1, name = "Zutat" } } } } }
AHT:Initialize()
AHT.AHOpen = true
TEST.Flush()

test("schema migration and canonical identity", function()
    equal(AHT.DB.schemaVersion, 5); equal(#AHT.Recipes:GetList(), 1)
    local canonical = AHT.DB; WOW4E_AHT_DB = nil; AHT.DB = nil
    assert(AHT.Store:Save()); equal(AHT.DB, canonical); equal(WOW4E_AHT_DB, canonical)
end)
test("browse preserves detailed distribution and unknown listing count", function()
    record(100, 100, "detailed", { 100, 200, 300 }); local r = AHT.Store:GetByItemID(100)
    local median, timestamp = r.medianPrice, r.distributionAt
    TEST.now = TEST.now + 1; record(100, 90, "browse")
    equal(r.medianPrice, median); equal(r.distributionAt, timestamp); equal(r.listingCount, nil); equal(r.minPrice, 90)
end)
test("independent observation days, not repeated scans", function()
    local _, days = AHT.Store:RobustMarketValue(100); equal(days, 1)
    TEST.now = TEST.now + 86400; record(100, 100, "detailed"); local _, days2 = AHT.Store:RobustMarketValue(100); equal(days2, 2)
end)
test("20 percent threshold excludes 1 percent and negative net", function()
    AHT.DB.market = {}; AHT.DB.history = {}; AHT.DB.dailyHistory = {}; AHT.DB.byItemID = {}; AHT.Store:Save()
    record(300, 100); TEST.now = TEST.now + 86400; record(300, 100); record(300, 99, "browse")
    equal(#AHT.Opportunities:Build(), 0)
    record(300, 50, "browse"); assert(#AHT.Opportunities:Build() >= 1)
    AHT.DB.settings.minimumProfitCopper = 1000; equal(#AHT.Opportunities:Build(), 0); AHT.DB.settings.minimumProfitCopper = 1
end)
test("current sell recommendation and floor", function()
    record(100, 200); TEST.now = TEST.now + 86400; record(100, 200); record(100, 100, "browse")
    local result = { name = "Test", output = { itemID = 100 } }
    equal(AHT.Poster:RecommendPrice(result).recommendedPrice, 100)
    AHT.DB.settings.sellFloorCopper = 150; equal(AHT.Poster:RecommendPrice(result).recommendedPrice, 150); AHT.DB.settings.sellFloorCopper = 0
end)
test("target outputs round crafts up and respect reservations", function()
    TEST.stock[200] = { bags = 4, bank = 2 }
    local order = AHT.Production:CreateOrderForOutputs(AHT.Recipes:GetList()[1], 5)
    equal(order.crafts, 3); equal(order.targetOutputs, 5); equal(order.requirements[1].ownedAllocated, 3)
    local second = AHT.Production:CreateOrderForOutputs(AHT.Recipes:GetList()[1], 8)
    equal(second.requirements[1].ownedAllocated, 3); equal(second.requirements[1].toBuy, 1)
    AHT.Production:CancelOrder(order); AHT.Production:CancelOrder(second)
end)
test("whole stack cost uses exact buyout, no rounding loss", function()
    local plan = AHT.Buyer:BuildPlan({ { kind = "item", quantity = 3, unitPrice = 33, buyoutAmount = 100 } }, 1, 40)
    equal(plan.total, 100); equal(plan.plannedQuantity, 3)
end)
test("live margin and budget include already paid and remaining", function()
    record(100, 100); record(200, 20)
    local order = { id = "guard", crafts = 1, output = { itemID = 100, quantity = 2 }, requirements = { { itemID = 200, ownedAllocated = 1, spent = 40, toBuy = 2, bought = 1 } } }
    AHT.Production.runtimePlans.guard = { ["200"] = { total = 30, missing = 0 } }
    assert(AHT.Production:ValidateOrder(order)); equal(order.preview.economicCost, 90); equal(order.preview.remainingCost, 30)
    AHT.DB.settings.budgetCopper = 60; local ok, reason = AHT.Production:ValidateOrder(order); equal(ok, false); equal(reason, "budget_exceeded")
    AHT.DB.settings.budgetCopper = 0
    local changed = { requirementItemID = 200, total = 130, missing = 0 }; local allowed, reason2 = AHT.Production:ValidateOrder(order, changed)
    equal(allowed, false); equal(reason2, "margin_below_minimum")
end)
test("buy guard blocks protected action", function()
    local plan = { target = { itemID = 200 }, quantity = 1, total = 10, lines = { { offer = { kind = "item", auctionID = 1, buyoutAmount = 10 }, quantity = 1 } }, validate = function() return false, "budget_exceeded" end }
    AHT.Buyer.pending = { state = "ready_to_buy", plan = plan }
    TEST.calls.bid = nil; AHT.Buyer:StartPendingPurchase(); equal(TEST.calls.bid, nil); equal(AHT.Buyer.pending, nil)
end)
test("multi-stack post explicit quantities and fresh quote requirement", function()
    local result = { output = { itemID = 100 }, name = "Test" }
    local plan = assert(AHT.Poster:BuildPlan(result, 7, 3, 100))
    equal(plan.totalStock, 8); equal(plan.quantity, 3); equal(plan.requestedQuantity, 7); equal(plan.posts, 2); equal(plan.remainingQuantity, 4)
    local ok, reason = AHT.Poster:Post(plan); equal(ok, false); equal(reason, "sale_refresh_required")
    AHT.Poster.priceChecked = { ["100"] = TEST.now }; assert(AHT.Poster:Post(plan)); AHT.Poster:OnEvent("AUCTION_HOUSE_AUCTION_CREATED")
    equal(TEST.calls.post[5], 300)
    equal(#AHT.DB.postingHistory, 1)
end)
test("Forever durations and copper precision", function()
    equal(AHT:NormalizeAuctionDuration(1), 1); equal(AHT:NormalizeAuctionDuration(2), 2); equal(AHT:NormalizeAuctionDuration(3), 3)
    equal(AHT:NormalizeAuctionDuration(8), 2); equal(AHT:NormalizeAuctionDuration(24), 3)
end)
test("market pools preserve old realm without cross mixing", function()
    AHT.Store:Save(); local pool = AHT.DB.marketPoolKey
    TEST.realm = "OtherRealm"; AHT.Store:SelectMarketPool(); equal(AHT:TableCount(AHT.DB.market), 0); record(400, 9); AHT.Store:Save()
    TEST.realm = "Forever"; AHT.Store:SelectMarketPool(); equal(AHT.DB.marketPoolKey, pool); assert(AHT.Store:GetPrice(100)); equal(AHT.Store:GetPrice(400), nil)
end)
test("optional Auctionator price is aged and never added to history", function()
    Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function() return 123 end, GetAuctionAgeByItemID = function() return 1 end } } }
    AHT.DB.settings.useAuctionator = true; equal(AHT.Store:GetMarketSnapshot(999).source, "auctionator"); equal(AHT.Store:GetPrice(999), 123)
    equal(AHT.Store:GetByItemID(999), nil); AHT.DB.settings.useAuctionator = false; equal(AHT.Store:GetMarketSnapshot(999), nil)
end)
test("virtualized 10000-result list and column filters", function()
    AHT.UI:SetView("materials")
    local results = {}
    for i = 1, 10000 do results[i] = { kind = "material", name = "Item " .. i, itemID = i, currentPrice = i } end
    AHT.UI.visibleResults = results; AHT.UI:EnsureRows(#results); AHT.UI:RenderVisibleRows(); assert(#AHT.UI.rows <= 64)
    AHT.UI.scroll:SetVerticalScroll(2300); equal(AHT.UI.rows[1].result.itemID, 101)
    AHT.UI.numericFilters = { columns = { currentPrice = { min = 500, max = 1000 } } }
    assert(not AHT.UI:MatchesFilter(results[499])); assert(AHT.UI:MatchesFilter(results[500])); assert(not AHT.UI:MatchesFilter(results[1001]))
    AHT.UI.numericFilters = {}
end)
test("view-specific search sort and filters", function()
    AHT.UI:SetView("materials"); AHT.UI.searchQuery = "iron"; AHT.UI.sortColumn = "averagePrice"; AHT.UI.numericFilters = { priceMin = 5 }; AHT.UI:SaveViewState()
    AHT.UI:SetView("recipes"); equal(AHT.UI.searchQuery, ""); AHT.UI:SetView("materials")
    equal(AHT.UI.searchQuery, "iron"); equal(AHT.UI.sortColumn, "averagePrice"); equal(AHT.UI.numericFilters.priceMin, 5)
end)
test("reusable buy/sell windows and all materials", function()
    local recipe = AHT.Recipes:GetList()[1]
    AHT.UI:ShowBuyDialog(recipe); local buy = AHT.UI.buyDialog; AHT.UI:ShowBuyDialog(recipe); equal(AHT.UI.buyDialog, buy)
    equal(buy.ahtOpaqueBackground.color[4], 1); equal(buy.ahtOpaqueBackground.color[1], 0)
    AHT.UI:ShowPostDialog({ name = "Test", output = { itemID = 100 } }); local sell = AHT.UI.postDialog
    AHT.UI:ShowPostDialog({ name = "Test", output = { itemID = 100 } }); equal(AHT.UI.postDialog, sell)
    sell.gold:SetText("1"); sell.silver:SetText("2"); sell.copper:SetText("3"); equal(AHT.UI:SellInputPrice(), 10203)
end)
test("shopping aggregation and named list persistence", function()
    local order = AHT.Production:CreateOrderForOutputs(AHT.Recipes:GetList()[1], 20)
    local rows = AHT.Commerce:AggregateShopping(); assert(#rows > 0); assert(AHT.Commerce:SaveList("Test", rows)); assert(AHT.DB.shoppingLists.Test)
    AHT.Production:CancelOrder(order)
end)
test("simulated reload restores market recipes orders and history", function()
    local database = AHT.DB; local price = AHT.Store:GetPrice(100); local recipes = #AHT.Recipes:GetList()
    AHT.Store.canonicalDB = nil; AHT.DB = nil; WOW4E_AHT_DB = database
    assert(AHT.Store:Load()); AHT.Recipes:Load(); equal(AHT.Store:GetPrice(100), price); equal(#AHT.Recipes:GetList(), recipes)
    assert(AHT.DB.shoppingLists.Test); equal(#AHT.DB.postingHistory, 1)
end)
test("all dialogs and recipe detail work with >3 reagents", function()
    local recipe = { recipeID = 999, name = "Lang benanntes Testrezept", output = { itemID = 100, quantity = 3 }, reagents = {} }
    for i = 1, 6 do table.insert(recipe.reagents, { itemID = 600 + i, quantity = 2, name = "Zutat " .. i }) end
    AHT.UI:ShowBuyDialog(recipe); equal(#AHT.UI.buyDialog.rows, 6)
    AHT.UI:ShowSettings(); AHT.UI:ShowFilters(); AHT.UI:ShowHistory({ itemID = 100, name = "Test" }); AHT.UI:ShowLists()
    AHT.UI:ShowItemPurchase({ itemID = 100, name = "Test" })
    AHT.UI:CreateAHRecipePanel(); AHT.UI.ahRecipePanel:Show(); TEST.Click(AHT.UI.ahRecipePanel.close); assert(AHT.UI.frame:IsShown())
    for _, window in pairs(AHT.UI.dialogs) do equal(window.ahtOpaqueBackground.color[1], 0); equal(window.ahtOpaqueBackground.color[4], 1) end
end)
test("search changes coalesce into one refresh", function()
    TEST.Flush(); local count = 0; local original = AHT.UI.Refresh
    AHT.UI.Refresh = function(self, ...) count = count + 1; return original(self, ...) end
    AHT.UI.searchInput:SetText("a"); AHT.UI.searchInput:SetText("ab"); AHT.UI.searchInput:SetText("abc"); TEST.Flush()
    equal(count, 1); AHT.UI.Refresh = original; AHT.UI.searchInput:SetText(""); TEST.Flush()
end)
test("recipe detail data is rendered in aligned metric and ingredient columns", function()
    local ui = AHT.UI
    local oldFrame, oldPanel, oldContent, oldScroll = ui.frame, ui.detailPanel, ui.detailContent, ui.detailScroll
    local oldTitle, oldAction, oldSearch, oldRows, oldSelection = ui.detailTitle, ui.detailAction, ui.detailSearch, ui.detailRows, ui.selectedResult
    ui.frame = CreateFrame("Frame", nil, UIParent); ui.frame:SetWidth(780)
    ui.detailPanel = CreateFrame("Frame", nil, ui.frame)
    ui.detailScroll = CreateFrame("ScrollFrame", nil, ui.detailPanel)
    ui.detailContent = CreateFrame("Frame", nil, ui.detailScroll)
    ui.detailTitle = CreateFrame("FontString", nil, ui.detailPanel)
    ui.detailAction = CreateFrame("Button", nil, ui.detailPanel)
    ui.detailSearch = CreateFrame("Button", nil, ui.detailPanel)
    ui.detailRows = {}
    ui.selectedResult = {
        name = "Testtrank", output = { itemID = 100 }, ingredientCost = 40, currentSalePrice = 90,
        marketSalePrice = 85, profit = 30, margin = 75, suggestedCrafts = 2,
        reagents = { { itemID = 200, quantity = 3, name = "Testkraut" } },
    }
    ui:RefreshDetail()
    equal(ui.detailRows[1].cells[1]:GetText(), "Kennzahl")
    equal(ui.detailRows[2].cells[1]:GetText(), "Kosten/Stk")
    equal(ui.detailRows[8].cells[1]:GetText(), "Zutat")
    equal(ui.detailRows[9].cells[1]:GetText(), "Testkraut")
    equal(ui.detailRows[9].cells[2]:GetText(), "6")
    ui.frame, ui.detailPanel, ui.detailContent, ui.detailScroll = oldFrame, oldPanel, oldContent, oldScroll
    ui.detailTitle, ui.detailAction, ui.detailSearch, ui.detailRows, ui.selectedResult = oldTitle, oldAction, oldSearch, oldRows, oldSelection
end)
test("recipe AH search submits the visible search instead of stopping at QueryItem", function()
    local previousFrame, previousContext = _G.AuctionHouseFrame, _G.AuctionHouseSearchContext
    local calls = { start = 0, queryItem = 0 }
    local frame
    local searchBar = { StartSearch = function(self) calls.start = calls.start + 1; self.submittedText = frame.searchText end }
    frame = { SearchBar = searchBar }
    frame.SetSearchText = function(self, text) self.searchText = text end
    frame.QueryItem = function() calls.queryItem = calls.queryItem + 1 end
    frame.Show = function() end
    _G.AuctionHouseFrame = frame
    _G.AuctionHouseSearchContext = { BuyItems = 1, BuyCommodities = 2 }
    local ok = AHT.AH:OpenItemInAuctionHouse({ itemID = 100, name = "Item 100" })
    equal(ok, true); equal(frame.searchText, "Item 100"); equal(searchBar.submittedText, "Item 100")
    equal(calls.start, 1); equal(calls.queryItem, 0)
    _G.AuctionHouseFrame, _G.AuctionHouseSearchContext = previousFrame, previousContext
end)
test("recipe AH search falls back to the search box Enter handler", function()
    local previousFrame = _G.AuctionHouseFrame
    local calls = { enter = 0, queryItem = 0 }
    local searchBox = {
        SetText = function(self, text) self.text = text end,
        ClearFocus = function() end,
        GetScript = function(_, name)
            if name == "OnEnterPressed" then return function() calls.enter = calls.enter + 1 end end
        end,
    }
    local frame = { SearchBar = { SearchBox = searchBox }, SetSearchText = function() end, Show = function() end }
    frame.QueryItem = function() calls.queryItem = calls.queryItem + 1 end
    _G.AuctionHouseFrame = frame
    local ok = AHT.AH:OpenItemInAuctionHouse({ itemID = 100, name = "Item 100" })
    equal(ok, true); equal(searchBox.text, "Item 100"); equal(calls.enter, 1); equal(calls.queryItem, 0)
    _G.AuctionHouseFrame = previousFrame
end)
test("actual queued commodity purchase completes on server event only", function()
    TEST.stock[200] = { bags = 0, bank = 0 }; AHT.DB.production.orders = {}; AHT.Production.active = nil
    AHT.Inventory.bankOpen = true; AHT.Inventory:RefreshBankItem(200); AHT.Inventory.bankOpen = false
    TEST.offers = { [100] = { { unitPrice = 100, quantity = 100 } }, [200] = { { unitPrice = 20, quantity = 100 } } }
    C_AuctionHouse.SendSearchQuery = function(key, sorts)
        assert(type(sorts[1]) == "table", "Search sort descriptors must be an array")
        C_Timer.After(0, function() AHT.AH:OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED", key.itemID) end)
    end
    C_AuctionHouse.GetNumCommoditySearchResults = function(id) return #(TEST.offers[id] or {}) end
    C_AuctionHouse.GetCommoditySearchResultInfo = function(id, i) return TEST.offers[id] and TEST.offers[id][i] end
    local recipe = AHT.Recipes:GetList()[1]
    local order = assert(AHT.Production:CreateOrderForOutputs(recipe, 4))
    assert(AHT.Production:PreviewOrder(order)); TEST.Flush(); equal(order.preview.cashCost, 40)
    assert(AHT.Production:Start(order)); TEST.Flush(); equal(order.status, "awaiting_purchase"); equal(TEST.calls.start, nil)
    assert(AHT.Production:StartCurrentPurchase()); equal(order.requirements[1].bought, 0)
    AHT.Buyer:OnEvent("COMMODITY_PRICE_UPDATED", 20, 40); equal(order.status, "awaiting_confirmation")
    assert(AHT.Production:ConfirmCurrentCommodity()); equal(order.status, "submitted"); equal(order.requirements[1].bought, 0)
    AHT.Buyer:OnEvent("COMMODITY_PURCHASE_SUCCEEDED"); equal(order.status, "ready_to_craft"); equal(order.requirements[1].bought, 2); equal(order.requirements[1].spent, 40)
    TEST.Flush()
end)
test("price jump pauses order without spending gold", function()
    AHT.DB.production.orders = {}; local order = AHT.Production:CreateOrderForOutputs(AHT.Recipes:GetList()[1], 4)
    assert(AHT.Production:PreviewOrder(order)); TEST.Flush(); TEST.offers[200][1].unitPrice = 95
    assert(AHT.Production:Start(order)); TEST.Flush(); equal(order.status, "paused"); equal(AHT.Buyer.pending, nil)
    equal(order.requirements[1].bought, 0); TEST.offers[200][1].unitPrice = 20
end)
test("API rejection reports error immediately", function()
    local plan = { target = { itemID = 100 }, quantity = 1, total = 10, lines = { { offer = { kind = "item", quantity = 1, auctionID = 1, buyoutAmount = 10 } } } }
    local original = C_AuctionHouse.PlaceBid; C_AuctionHouse.PlaceBid = function() return false end
    AHT.Buyer.pending = { plan = plan, state = "ready_to_buy" }; AHT.Buyer:StartPendingPurchase(); equal(AHT.Buyer.pending, nil)
    C_AuctionHouse.PlaceBid = original
end)
test("replica rejection safely falls back to browse", function()
    local original = AHT.Scanner.StartMarketDiscovery; local used = false
    AHT.Scanner.StartMarketDiscovery = function() used = true; return true end
    C_AuctionHouse.ReplicateItems = function() return false end
    C_AuctionHouse.GetNumReplicateItems = function() return 0 end
    C_AuctionHouse.GetReplicateItemInfo = function() return nil end
    AHT.AH.active = nil; AHT.Buyer.pending = nil; AHT.Scanner:StartReplication(); assert(used); equal(AHT.Scanner.replication, nil)
    AHT.Scanner.StartMarketDiscovery = original
end)
test("NPC buy opportunity needs no market history", function()
    AHT.DB.market = {}; AHT.DB.history = {}; AHT.DB.dailyHistory = {}; AHT.DB.byItemID = {}; AHT.Store:Save()
    local original = AHT.GetItemInfo
    AHT.GetItemInfo = function(_, id) return "NPC Item", "item:" .. id, 1, 1, 1, nil, nil, 1, nil, nil, 100 end
    record(800, 50, "browse"); local rows = AHT.Opportunities:Build(); equal(#rows, 1); equal(rows[1].bestMethod, "NPC"); equal(rows[1].profit, 50)
    AHT.GetItemInfo = original
end)
print(string.format("Behavior tests passed: %d (Lua 5.1, mocked WoW APIs; real client acceptance pending)", passed))
