$ErrorActionPreference = "Stop"

$addonRoot = Split-Path -Parent $PSScriptRoot
$tocPath = Join-Path $addonRoot "WOW4E_AH_Trader.toc"
$luaFiles = @(Get-ChildItem $addonRoot -Filter "*.lua" -File)
$tocEntries = @(Get-Content $tocPath | Where-Object { $_ -and -not $_.StartsWith("#") })
$errors = [System.Collections.Generic.List[string]]::new()

foreach ($entry in $tocEntries) {
    if (-not (Test-Path (Join-Path $addonRoot $entry))) {
        $errors.Add("TOC-Datei fehlt: $entry")
    }
}

$source = ($luaFiles | ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n"
$tocVersion = (Get-Content $tocPath | Where-Object { $_ -like "## Version:*" } | Select-Object -First 1) -replace '^## Version:\s*', ''
$coreSource = Get-Content (Join-Path $addonRoot "Core.lua") -Raw
$coreVersion = [regex]::Match($coreSource, 'AHT\.VERSION\s*=\s*"([^"]+)"').Groups[1].Value
if (-not $tocVersion -or $tocVersion -ne $coreVersion) {
    $errors.Add("Versionsabweichung: TOC=$tocVersion Core=$coreVersion")
}
$legacySymbols = @(
    "QueryAuctionItems",
    "GetNumAuctionItems",
    "GetAuctionItemInfo",
    "AuctionFrame",
    "AuctionSellItemButton"
)
foreach ($symbol in $legacySymbols) {
    if ($source.Contains($symbol)) {
        $errors.Add("Legacy-AH-Symbol gefunden: $symbol")
    }
}

$requiredSnippets = @(
    "C_AuctionHouse.SendSearchQuery",
    "C_AuctionHouse.GetItemSearchResultInfo",
    "C_AuctionHouse.GetCommoditySearchResultInfo",
    "C_AuctionHouse.StartCommoditiesPurchase",
    "C_AuctionHouse.ConfirmCommoditiesPurchase",
    'pending.state = "awaiting_completion"',
    "AHT.Inventory:GetCount",
    "BANKFRAME_OPENED",
    "AHT.Production:CreateOrder",
    "AHT.Production:GetReserved",
    "AHT.Production:PreviewOrder",
    "AHT.Production:ConfirmCurrentCommodity",
    "ready_to_craft",
    "production.purchases",
    "GetBaseProfessionInfo",
    "CalculatePriceStats",
    "dailyHistory",
    "AHT.Opportunities:Build",
    "marketValue",
    "function AHT.UI:EnsureRows",
    "function AHT.UI:MatchesFilter",
    "self.moreMenu",
    "AHT.DB.ui.viewMode",
    'if type(WOW4E_AHT_DB) ~= "table"',
    "if #newList == 0 then",
    "self:Save()",
    "result.currentSalePrice = result.salePrice",
    "result.expectedSalePrice = result.currentSalePrice or result.marketSalePrice",
    'label = "Marktwert"',
    "local function MakeDialogMovable(dialog)",
    "if self.actionDialog then self.actionDialog:Hide() end"
)
foreach ($snippet in $requiredSnippets) {
    if (-not $source.Contains($snippet)) {
        $errors.Add("Erforderlicher Vertrag fehlt: $snippet")
    }
}

if ($source.Contains("AHT.Capabilities = c")) {
    $errors.Add("Capabilities-Modul wird durch Probe-Ergebnis ersetzt")
}

$inventoryIndex = [Array]::IndexOf($tocEntries, "Inventory.lua")
$calculatorIndex = [Array]::IndexOf($tocEntries, "Calculator.lua")
$buyerIndex = [Array]::IndexOf($tocEntries, "Buyer.lua")
$productionIndex = [Array]::IndexOf($tocEntries, "Production.lua")
$uiIndex = [Array]::IndexOf($tocEntries, "UI.lua")
if ($inventoryIndex -lt 0 -or $inventoryIndex -gt $calculatorIndex) {
    $errors.Add("Inventory.lua muss vor Calculator.lua geladen werden")
}
if ($productionIndex -lt $buyerIndex -or $productionIndex -gt $uiIndex) {
    $errors.Add("Production.lua muss nach Buyer.lua und vor UI.lua geladen werden")
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Output ("Source audit passed: {0} Lua-Dateien, {1} TOC-Einträge, Forever-AH- und Produktionsverträge vorhanden." -f $luaFiles.Count, $tocEntries.Count)
