local AHT = WOW4E_AHT

local deDE = GetLocale and GetLocale() == "deDE"

AHT.L = {
    loaded = deDE and "WoW4E AH Trader %s geladen." or "WoW4E AH Trader %s loaded.",
    reset = deDE and "Marktdaten gelöscht." or "Market data cleared.",
    postHint = deDE and "Posten erfolgt über eine sichtbare Vorschau im Addon." or "Posting is available through the visible addon preview.",
    noAH = deDE and "Bitte zuerst das Auktionshaus öffnen." or "Open the Auction House first.",
    noRecipes = deDE and "Keine Rezepte geladen. Öffne das Alchemiefenster." or "No recipes loaded. Open the Alchemy profession.",
    scanStart = deDE and "Scan gestartet: %d Markteinträge." or "Scan started: %d market entries.",
    scanDone = deDE and "Scan abgeschlossen: %d Markteinträge verarbeitet." or "Scan complete: %d market entries processed.",
    scanStopped = deDE and "Scan abgebrochen." or "Scan cancelled.",
    noItemID = deDE and "Item-ID nicht verfügbar. Verwende einen Item-Link." or "Item ID unavailable. Use an item link.",
    recipesLoaded = deDE and "%d Rezepte geladen." or "%d recipes loaded.",
    noData = deDE and "keine Daten" or "no data",
    incomplete = deDE and "unvollständig" or "incomplete",
}
