# WOW4E AH Trader

<p align="center">
  <img src="WOW4E_AH_Trader/Assets/WOW4E_AH_Trader-logo.png" alt="WOW4E AH Trader Logo" width="240">
</p>

Ein eigenständiger Auction-House-, Rezept- und Margenanalysator für **World of Warcraft: Forever**. Das Addon ist aus dem ursprünglichen `TWOW_AH_Trader`-Projekt abgeleitet, verwendet aber eine getrennte moderne API-Schicht für die Forever-Beta.

> Status: Beta-Port für Interface `16001` / Version `0.2.1-beta`. Rezept-, Commodity-Kauf- und Post-Events müssen weiterhin im echten Forever-Client verifiziert werden.

## Funktionen

- modernes `C_AuctionHouse`-Scanning mit Queue, Throttle-Handling, Timeout und Retry
- Rezeptauswertung und Gewinn-/Margenberechnung
- Materialüberwachung und begrenzte Marktpreis-Historie
- Kaufpläne für Items und Commodities mit Preisprüfung und sichtbarer Bestätigung
- Postpläne mit Bestands-, Deposit- und Preisprüfung
- Runenstoff-/Ruf-Funktion für Hauptstadtfraktionen bis Ehrfürchtig
- Transmutationsanalyse
- Runtime-Diagnose über `/aht debug`

## Installation

Den Ordner `WOW4E_AH_Trader` nach folgendem Pfad kopieren:

```text
World of Warcraft\_classic_beta_\Interface\AddOns\WOW4E_AH_Trader\
```

Danach im Client `/reload` ausführen oder den Client neu starten.

## Befehle

| Befehl | Funktion |
|---|---|
| `/aht` | Hauptfenster öffnen |
| `/aht scan` | Rezept-, Material- und Runenstoffpreise aktualisieren |
| `/aht recipes` | gelernte Rezepte ausgeben |
| `/aht mats add <Item-Link>` | Material zur Überwachung hinzufügen |
| `/aht mats remove <Item-Link>` | Material entfernen |
| `/aht ruf` | aktuellen Ruf-/Runenstoffbedarf ausgeben |
| `/aht transmute` | Transmutationsmargen ausgeben |
| `/aht stop` | laufende Operationen abbrechen |
| `/aht debug` | Client- und API-Diagnose ausgeben |
| `/aht reset` | gespeicherte Marktdaten löschen |

## Ruf- und Runenstoffanalyse

Beim Hovern über die Rufleiste ergänzt das Addon den Tooltip für die acht Hauptstadtfraktionen. Es zeigt fehlenden Ruf, benötigte 20er-Spenden, Runenstoffmenge und — nach einem Markt-Scan — die geschätzten AH-Kosten.

Runenstoff wird über Item-ID `14047` erkannt. Der Preis wird bevorzugt als gewichteter Durchschnitt der gespeicherten Markt-Snapshots verwendet; fehlt eine Historie, wird der zuletzt gescannte Mindestpreis genutzt.

## Sicherheitsmodell

Alle AH-Anfragen laufen über eine zentrale Queue. Käufe und Posts werden niemals automatisch ohne sichtbare Benutzeraktion ausgeführt. Commodity-Käufe erhalten nach der Preisabfrage eine zusätzliche finale Bestätigung. Beim Posten werden Bestand, Preis, Laufzeit und Deposit unmittelbar vor dem API-Aufruf erneut geprüft.

## Projektstruktur

```text
WOW4E_AH_Trader/
├── AuctionHouse.lua       moderne AH-Abstraktion und Queue
├── Buyer.lua              Kaufplan und Bestätigung
├── Calculator.lua         Kosten-, Gewinn- und Margenberechnung
├── Poster.lua              kontrolliertes Posten
├── Recipes.lua             Rezeptdaten aus C_TradeSkillUI
├── Reputation.lua          Ruf-/Runenstoffanalyse
├── Scanner.lua             Markt-Scanner
├── Store.lua               SavedVariables und Preis-Historie
├── UI.lua                  Hauptfenster und Dialoge
└── Assets/
    └── WOW4E_AH_Trader-logo.png
```

## Prüfung

Der statische Quell-Audit prüft TOC-Dateien, moderne AH-Verträge, Ruf-Funktion und den Ausschluss der alten Legacy-AH-Symbole:

```powershell
.\WOW4E_AH_Trader\Tests\SourceAudit.ps1
```

Ein erfolgreicher Audit ersetzt keinen echten Test im Forever-Client. Für die erste Ingame-Prüfung empfiehlt sich ein kleiner Scan sowie ein unkritischer Kauf-/Postversuch mit niedriger Menge.

## Abgrenzung

Der ursprüngliche Turtle-WoW-Code bleibt erhalten. Der Forever-Port liegt ausschließlich im Ordner `WOW4E_AH_Trader`.
