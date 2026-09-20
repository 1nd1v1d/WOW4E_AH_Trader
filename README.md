# WOW4E AH Trader

<p align="center">
  <img src="WOW4E_AH_Trader/Assets/WOW4E_AH_Trader-logo.png" alt="WOW4E AH Trader Logo" width="240">
</p>

Ein eigenständiger Auction-House-, Rezept- und Margenanalysator für **World of Warcraft: Forever**. Das Addon ist aus dem ursprünglichen `TWOW_AH_Trader`-Projekt abgeleitet, verwendet aber eine getrennte moderne API-Schicht für die Forever-Beta.

> Status: Beta-Port für Interface `16001` / Version `0.3.5-beta`. Rezept-, Commodity-Kauf- und Post-Events müssen weiterhin im echten Forever-Client verifiziert werden.

## Funktionen

- modernes `C_AuctionHouse`-Scanning mit Queue, Throttle-Handling, Timeout und Retry
- Rezeptauswertung und Gewinn-/Margenberechnung
- Materialüberwachung und begrenzte Marktpreis-Historie
- robuste Marktwerte aus Preisverteilung, altersgewichteten Tagessnapshots, Preisband und Trend
- Chancenansicht für unterbewertete AH-Angebote mit AH-Gebühr, Liquidität, ROI und NPC-Vergleich
- Kaufpläne für Items und Commodities mit Preisprüfung und sichtbarer Bestätigung
- berufsübergreifende Herstellungsaufträge mit Mengenempfehlung und Live-Marge
- automatische gemeinsame Einkaufsliste für alle Rezeptzutaten
- Taschen- und Bankbestand mit Reservierungen zwischen mehreren Herstellungsaufträgen
- dauerhaftes Kaufprotokoll mit gekaufter Menge und Goldkosten pro Auftrag
- Postpläne mit Bestands-, Deposit- und Preisprüfung
- Runenstoff-/Ruf-Funktion für Hauptstadtfraktionen bis Ehrfürchtig
- Transmutationsanalyse
- Runtime-Diagnose über `/aht debug`
- UI-Release mit fokussierter Hauptnavigation, globaler Suche, Profitfilter und gespeicherter Fenster-/Sortierposition
- dynamische Tabellenzeilen ohne künstliche 24-Zeilen-Grenze
- persistenter SavedVariables-Schutz gegen temporär leere Berufsdaten beim Clientstart
- verschiebbare Dialoge ohne Überlagerung von Rezeptaktions- und Postplanfenster

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
| `/aht orders` | aktive Herstellungsaufträge und reservierte Materialien anzeigen |
| `/aht chancen` | belastbare AH-Chancen und Netto-ROI anzeigen |
| `/aht stop` | laufende Operationen abbrechen |
| `/aht debug` | Client- und API-Diagnose ausgeben |
| `/aht reset` | gespeicherte Marktdaten löschen |

Beim Öffnen des Auktionshauses erscheint ein `AH Trader`-Button direkt unterhalb der AH-Titelleiste. Die Hauptnavigation fokussiert `Herstellen`, `Markt`, `Aufträge` und `Chancen`; `Ruf` und `Diagnose` liegen unter `Mehr`, damit der Arbeitsbereich nicht mit seltenen Funktionen überladen wird. Die Suche filtert die sichtbare Liste nach Name, Item-ID und Beruf; `Nur profitabel` grenzt zusätzlich auf positive Chancen ein. Jede sichtbare Tabellenüberschrift ist anklickbar und sortiert ihre Spalte. Fensterposition, Größe, Ansicht und Sortierung werden gespeichert. Die Tabellenzeilen wachsen dynamisch mit der Ergebnisliste.

Beim Überfahren eines Rezepts zeigt ein Kontextfenster die Zutaten, aktuellen Scanpreise, robusten Marktwert, Bestand, Reservierungen und den altersgewichteten Durchschnittspreis. In der Rezepttabelle ist `Aktuell` immer der letzte AH-Scan; `Marktwert` dient als robuste Orientierung, ob dieser aktuelle Preis über oder unter dem historischen Niveau liegt. Gewinn und Marge verwenden den aktuellen Scan, sofern vorhanden, und fallen nur bei fehlendem aktuellem Scan auf den robusten Marktwert zurück. Der robuste Marktwert basiert auf Preisverteilung und Tagessnapshots; ältere Tage verlieren standardmäßig mit einer Halbwertszeit von sieben Tagen an Einfluss. Materialien zeigen zusätzlich Preisband und Trend und bieten per Klick einen erneuten Scan oder das Entfernen aus der Überwachung.

Die Ansicht `Chancen` meldet nur Angebote mit ausreichender Historie. Sie zieht die konfigurierbare AH-Gebühr ab, zeigt den erwarteten Netto-Gewinn, ROI, verfügbare Menge, Listing-Anzahl und ein Vertrauensniveau. Wenn der Forever-Client einen Händlerverkaufspreis liefert, wird auch der NPC-Verkauf als Alternative angezeigt. Ein Klick kann das Item in die Materialüberwachung übernehmen oder einen Live-Scan anstoßen.

## Herstellungsaufträge und AutoBuy

`Trank` steht im Addon für jedes herstellbare Ergebnis eines erkannten Berufsrezepts. Der Forever-Port speichert Rezepte berufsübergreifend: Jeder Beruf muss mindestens einmal geöffnet werden, damit seine gelernten Rezepte eingelesen werden.

Die Rezeptliste zeigt eine konservative Mengenempfehlung sowie die erwartete Marge. Ein Klick auf ein Rezept öffnet den Herstellungs- und Einkaufsplan. Dort wird die gewünschte Anzahl an Herstellvorgängen eingegeben. Das Addon:

- multipliziert sämtliche Zutaten mit der gewählten Anzahl,
- zieht verfügbare Gegenstände aus Taschen und persönlicher beziehungsweise Reagenzienbank ab,
- berücksichtigt Materialreservierungen anderer aktiver Aufträge,
- prüft die fehlenden Mengen und Preisstufen live im Forever-Auktionshaus,
- kauft die Zutaten in einer geführten Warteschlange,
- speichert gekaufte Menge und Kosten beim zugehörigen Auftrag.

Aktive Aufträge bleiben in der Ansicht `Aufträge` erhalten. `Hergestellt` gibt ihre Materialreservierungen frei; `Stornieren` verwirft den Auftrag ebenfalls. Bankbestände werden beim Öffnen der Bank aktualisiert. Ist noch kein Banksnapshot verfügbar, zeigt das Addon den Bankwert als unbekannt an.

## Ruf- und Runenstoffanalyse

Beim Hovern über die Rufleiste ergänzt das Addon den Tooltip für die acht Hauptstadtfraktionen. Es zeigt fehlenden Ruf, benötigte 20er-Spenden, Runenstoffmenge und — nach einem Markt-Scan — die geschätzten AH-Kosten.

Runenstoff wird über Item-ID `14047` erkannt. Der Preis wird bevorzugt als gewichteter Durchschnitt der gespeicherten Markt-Snapshots verwendet; fehlt eine Historie, wird der zuletzt gescannte Mindestpreis genutzt.

## Sicherheitsmodell

Alle AH-Anfragen laufen über eine zentrale Queue. Der AutoBuy übernimmt Suche, Mengenplanung, Reservierungen und den Wechsel zur nächsten Zutat. Forever verlangt für den finalen Commodity-Preis weiterhin eine sichtbare Bestätigung; Itemauktionen werden ebenfalls nicht ohne Benutzeraktion ausgelöst. Preis und Menge werden unmittelbar vor jedem Kauf erneut geprüft. Beim Posten werden Bestand, Preis, Laufzeit und Deposit unmittelbar vor dem API-Aufruf erneut geprüft.

## Projektstruktur

```text
WOW4E_AH_Trader/
├── AuctionHouse.lua       moderne AH-Abstraktion und Queue
├── Buyer.lua              Kaufplan und Bestätigung
├── Calculator.lua         Kosten-, Gewinn- und Margenberechnung
├── Opportunities.lua      Deal-Finder mit Risiko-, Liquiditäts- und ROI-Bewertung
├── Inventory.lua          Taschen-, Bank- und Reagenzienbankbestand
├── Production.lua         Herstellungsaufträge, Reservierungen und AutoBuy-Queue
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

Der statische Quell-Audit prüft TOC-Dateien, moderne AH-Verträge, Marktstatistik, Chancenansicht, Ruf-Funktion und den Ausschluss der alten Legacy-AH-Symbole:

```powershell
.\WOW4E_AH_Trader\Tests\SourceAudit.ps1
node .\WOW4E_AH_Trader\Tests\lua-balance.mjs
```

Ein erfolgreicher Audit ersetzt keinen echten Test im Forever-Client. Für die erste Ingame-Prüfung empfiehlt sich ein kleiner Scan sowie ein unkritischer Kauf-/Postversuch mit niedriger Menge.

## Abgrenzung

Der ursprüngliche Turtle-WoW-Code bleibt erhalten. Der Forever-Port liegt ausschließlich im Ordner `WOW4E_AH_Trader`.
