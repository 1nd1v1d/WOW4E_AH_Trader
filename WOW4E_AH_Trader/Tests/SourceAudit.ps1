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
    "C_AuctionHouse.PostItem",
    "C_AuctionHouse.PostCommodity",
    "NormalizeAuctionDuration",
    "awaiting_user_confirmation",
    "ConfirmCommodity",
    "GetWatchedFactionData",
    "CalculateDonations",
    "runeclothItemID = 14047"
)
foreach ($snippet in $requiredSnippets) {
    if (-not $source.Contains($snippet)) {
        $errors.Add("Erforderlicher Vertrag fehlt: $snippet")
    }
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Output ("Source audit passed: {0} Lua-Dateien, {1} TOC-Einträge, Legacy-AH-Symbolscan sauber." -f $luaFiles.Count, $tocEntries.Count)
