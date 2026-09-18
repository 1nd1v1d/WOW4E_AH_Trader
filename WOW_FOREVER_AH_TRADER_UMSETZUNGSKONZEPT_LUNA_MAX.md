# WoW Forever AH Trader – Umsetzungskonzept für LUNA MAX

**Ziel:** `TWOW_AH_Trader` als eigenständiges Addon für World of Warcraft: Forever neu implementieren  
**Zielname:** `WOW4E_AH_Trader`  
**Technische Basis:** WoW Forever Beta 1.60.1, lokal zuletzt geprüft mit Build `1.60.1.69893`  
**Stand:** 2026-09-18  
**Adressat:** LUNA MAX als autonom arbeitender Implementierungsagent

---

## 1. Verbindlicher Auftrag

Implementiere einen Forever-Port des bestehenden `TWOW_AH_Trader`, ohne den Turtle-WoW-Stand umzuschreiben oder durch Kompatibilitäts-Shims zu verkomplizieren.

Das erste Release soll die vorhandenen Kernfunktionen funktional abbilden:

- Alchemie-Rezepte des Spielers erfassen
- Produkte und Zutaten im Auktionshaus suchen
- Herstellkosten, Verkaufserlös, Gebühren, Gewinn und Marge berechnen
- Preise und begrenzte Preisverläufe speichern
- frei definierbare Materialien beobachten
- kontrollierte Käufe mit Preis- und Margenschutz ausführen
- kontrolliertes Posten vorhandener Produkte ermöglichen
- Transmutationsmargen anzeigen
- deutsche und englische Oberfläche anbieten
- alle Vorgänge bei geschlossenem Auktionshaus oder API-Fehler sicher abbrechen

Die Portierung ist eine **API-Neuentwicklung**, kein `.toc`-Versionsbump. Forever verwendet laut Entwickler-Q&A den modernen Addon-API-Ansatz. Der vorhandene Code basiert dagegen auf Vanilla 1.12.1 und unter anderem auf `QueryAuctionItems`, `GetAuctionItemInfo`, `PlaceAuctionBid`, `StartAuction`, `AuctionFrame`, `GetTradeSkill*` und den alten Containerfunktionen.

---

## 2. Arbeits- und Sicherheitsgrenzen

Diese Vorgaben sind verbindlich:

1. Der bestehende Ordner `TWOW_AH_Trader` bleibt als Legacy-Referenz erhalten.
2. Die Forever-Version entsteht in einem separaten Ziel `WOW4E_AH_Trader`.
3. Keine bestehenden uncommitted oder untracked Dateien überschreiben. Insbesondere `ProjEP_AH_Trader_KONZEPT.md` gehört zu einem anderen Zielsystem.
4. Keine Dateien unter `C:\Program Files (x86)\World of Warcraft\_classic_beta_` verändern, bevor der Nutzer eine Installation oder Synchronisierung ausdrücklich freigibt.
5. Kein Commit, Push, Release oder Upload ohne ausdrückliche Freigabe.
6. Keine Third-Party-Addonquellen kopieren. Auctionator darf wegen seiner Lizenz und seines Umfangs nur als Verhaltens- und API-Referenz dienen.
7. Keine Combat-Automatisierung implementieren. Kauf-, Post- und Abbruchaktionen benötigen eine sichtbare Benutzerinteraktion.
8. Keine neue Profession, Marktprognose, Webanbindung oder Desktop-App in Release 1 aufnehmen.
9. Keine API-Signatur aus Erinnerung übernehmen. Jede verwendete Forever-API muss im aktuellen Beta-Build, in extrahierten Blizzard-UI-Quellen oder durch einen Runtime-Probe bestätigt werden.

---

## 3. Aktuell bestätigte technische Grundlage

### Bestätigt

- Forever Beta verwendet Version `1.60.1`.
- Der lokale Client meldete Build `1.60.1.69893` und Flavor `wow_classic_beta`.
- Blizzard hat im Entwickler-Q&A den „modern API approach“ für Forever bestätigt.
- Der lokale Beta-Client enthält die modernen Namespaces `C_AuctionHouse`, `C_Container`, `C_Item` und `C_TradeSkillUI`.
- Der Client enthält `Blizzard_AuctionHouseUI`.
- Auctionator 337 besitzt einen expliziten Forever-Build für 1.60.1. Der Changelog nennt ein Forever-TOC-Update und die Beseitigung erster Login-Fehler.
- Der lokale Addonpfad ist vorhanden: `C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns`.

### Vor der Implementierung erneut zu prüfen

- aktuelle Build- und Interface-Nummer
- `WOW_PROJECT_ID` und vorhandene Projektkonstanten
- gültiger TOC-Name beziehungsweise Forever-spezifischer TOC-Suffix
- exakte Signaturen aller verwendeten `C_AuctionHouse`-Funktionen
- verfügbare Events und deren Argumente
- Verhalten von Item- und Commodity-Auktionen
- Verfügbarkeit und Einschränkungen von `C_AuctionHouse.ReplicateItems`
- Throttle-Verhalten des aktuellen Builds
- geschützte beziehungsweise nur durch Hardware-Event erlaubte Aktionen
- tatsächliche Profession-/Rezeptdaten für Forever

Die `.toc`-Interface-Nummer darf nicht aus `1.60.1` geraten werden. Sie ist im laufenden Client mit `select(4, GetBuildInfo())` oder aus einem nachweislich ladenden Forever-Addon zu ermitteln.

---

## 4. Produktumfang für Release 1

### Muss-Funktionen

| Bereich | Abnahmepunkt |
|---|---|
| Laden | Addon erscheint in Forever und lädt ohne Lua-Fehler |
| Diagnose | Build, Interface, Projekt-ID und relevante Capabilitys sind abrufbar |
| Rezepte | Gelernte Alchemie-Rezepte werden per Recipe-ID erfasst |
| Scan | Produkt- und Zutatenpreise können gezielt aktualisiert werden |
| Preisnormalisierung | Preise werden als Kupfer pro Stück gespeichert |
| Berechnung | Kosten, Erlös, AH-Gebühr, Deposit, Gewinn und Marge sind nachvollziehbar |
| Historie | Preisverlauf ist begrenzt, versioniert und reload-fest |
| Materialien | Benutzer kann Materialbeobachtung hinzufügen, entfernen und scannen |
| Kauf | Kaufplan zeigt Menge, Preisstufen und Maximalpreis vor Ausführung |
| Posten | Postplan zeigt Menge, Laufzeit, Stückpreis und Deposit vor Ausführung |
| Sicherheit | AH-Schließen, Timeout, Throttle und Preisänderung führen zu sauberem Abbruch |
| Lokalisierung | Deutsch und Englisch funktionieren ohne Logikduplikation |

### Bewusst nicht in Release 1

- Inscription- oder Jewelcrafting-Komplettmodule
- automatische Dauer- oder Hintergrundscans
- unbeaufsichtigtes Sniping
- automatisches Kaufen oder Posten ohne expliziten Klick
- TSM-Importformat
- externe Preisquellen oder Netzwerkzugriff
- Cross-Character-Synchronisierung
- Prognosen auf Basis komplexer Statistik
- gemeinsame Codebasis mit dem Vanilla-Addon

Nach stabiler Feature-Parität können weitere Professionen als getrennte Anforderungen geplant werden.

---

## 5. Zielstruktur

Die Struktur soll klein bleiben und die bestehenden fachlichen Grenzen wiederverwenden:

```text
WOW4E_AH_Trader/
├── WOW4E_AH_Trader.toc
├── Core.lua                 Start, Events, Slash-Befehle, Lifecycle
├── Capabilities.lua         Build-/API-Erkennung und Diagnose
├── Store.lua                Schema, Migrationen, Preis- und Verlaufsdaten
├── AuctionHouse.lua         Einziger Zugriffspunkt auf C_AuctionHouse
├── Scanner.lua              Scan-Pläne und Ergebnisnormalisierung
├── Calculator.lua           Reine Preis-, Gebühren- und Margenlogik
├── Recipes.lua              C_TradeSkillUI und Recipe-/Schematic-Auswertung
├── Buyer.lua                Kaufplan und kontrollierte Kaufzustände
├── Poster.lua               Postplan und kontrollierte Postzustände
├── Mats.lua                 Materialbeobachtung und Kaufplan
├── Transmute.lua            Forever-Transmutationsauswertung
├── UI.lua                   Fenster, Tabellen, Dialoge und Status
├── Locales.lua              deDE/enUS
├── Diagnostics.lua          /aht debug und Runtime-Probe
├── Tests/
│   ├── CalculatorTests.lua
│   ├── StoreMigrationTests.lua
│   └── NormalizationTests.lua
└── DOKUMENTATION.md
```

`AuctionHouse.lua` ist die wichtigste neue Grenze. Kein anderes Modul darf `C_AuctionHouse` direkt aufrufen. Dadurch bleiben Throttling, Events, Fehlerbehandlung und Beta-Änderungen an einer Stelle.

---

## 6. Verantwortlichkeiten und Verträge

### `Capabilities.lua`

- liest Build, Interface, Locale und Projekt-ID
- erkennt verfügbare Funktionen und Events defensiv
- stellt Capability-Flags bereit, beispielsweise:
  - `hasAuctionHouse`
  - `hasReplicateItems`
  - `hasCommodityPurchase`
  - `hasTradeSkillUI`
- darf keine dauerhaften Annahmen aus Versionsnummern ableiten
- liefert eine kompakte Diagnose für Bugreports

### `AuctionHouse.lua`

- verwaltet genau eine aktive AH-Operation
- kapselt Such-, Kauf-, Post-, Cancel- und Full-Snapshot-Aufrufe
- registriert alle AH-Events zentral
- behandelt die `AUCTION_HOUSE_THROTTLED_*`-Events
- normalisiert Item- und Commodity-Ergebnisse auf ein gemeinsames internes Format
- prüft vor jeder mutierenden Aktion, ob das Auktionshaus offen und die Anfrage noch aktuell ist
- verwirft verspätete Events über eine Operation-ID

### `Scanner.lua`

- erstellt einen Scanplan aus aktiven Rezepten und Materialien
- dedupliziert identische Item-Keys
- entscheidet zwischen gezielter Suche und optionalem Full Snapshot
- verarbeitet Ergebnisse in kleinen Batches, damit die UI nicht einfriert
- meldet Fortschritt, Fehler und Teilresultate
- besitzt keine Kauf- oder Postlogik

### `Calculator.lua`

- enthält ausschließlich deterministische Funktionen
- erhält normalisierte Daten als Parameter
- greift weder auf UI noch auf WoW-APIs direkt zu
- berechnet Stückkosten, erwarteten Nettoerlös, Gewinn, Marge und Preisgrenzen
- erklärt fehlende Daten mit strukturierten Reason-Codes

### `Recipes.lua`

- arbeitet primär mit `recipeID` und Item-IDs/Item-Keys
- liest nur gelernte, herstellbare Rezepte
- verarbeitet asynchron fehlende Itemdaten
- speichert keine flüchtigen ItemLocations
- trennt Recipe-Daten von lokalisierten Anzeigenamen

### `Buyer.lua`

- erzeugt zunächst einen unveränderlichen Kaufplan
- aktualisiert unmittelbar vor dem Kauf den betroffenen Marktpreis
- erfordert für jeden tatsächlich ausgeführten Kauf eine Benutzeraktion
- behandelt Items und Commodities getrennt
- kauft nie eigene Auktionen
- bricht ab, sobald Maximalpreis, verfügbare Menge oder Marge nicht mehr passt

### `Poster.lua`

- erzeugt zunächst einen unveränderlichen Postplan
- trennt Item-Auktionen und Commodities
- verwendet moderne `ItemLocation`-/Containerdaten
- berechnet Deposit über die aktuelle API
- postet nur nach sichtbarer Bestätigung
- prüft unmittelbar vor dem Posten Bestand, Preis und Deposit erneut

### `Store.lua`

- besitzt eine explizite `schemaVersion`
- führt kleine, nachvollziehbare Migrationen aus
- begrenzt Historien pro Marktobjekt
- validiert geladene SavedVariables defensiv
- speichert keine Frames, Callbacks oder flüchtigen API-Objekte

---

## 7. Internes Datenmodell

Ein bloßer `itemID`-Schlüssel reicht bei nicht stapelbaren Items nicht aus. Forever kann Varianten desselben Items über Item-Level, Suffixe oder weitere ItemKey-Felder unterscheiden.

```lua
WOW4E_AHT_DB = {
    schemaVersion = 1,
    addonVersion = "0.1.0-beta",
    lastBuild = nil,

    settings = {
        locale = nil,
        minMarginPercent = 10,
        dealThresholdPercent = 20,
        historyLimit = 20,
        defaultDuration = nil,
    },

    recipes = {
        -- [recipeID] = normalized recipe record
    },

    watchlist = {
        -- [marketKey] = { enabled=true, category=nil }
    },

    market = {
        -- [marketKey] = {
        --   kind="item"|"commodity",
        --   itemID=...,
        --   itemKey=...,
        --   minBuyout=...,
        --   quantity=...,
        --   updatedAt=...,
        -- }
    },

    history = {
        -- [marketKey] = { {t=serverTime, p=unitPrice, q=quantity}, ... }
    },
}
```

### Identitätsregeln

- Commodities: mindestens `itemID` als stabiler Marktschlüssel.
- Einzelausrüstung: serialisierter vollständiger `itemKey`.
- Rezepte: `recipeID`.
- Anzeigenamen: nur Darstellung und Suche, nie Primärschlüssel.
- Preise: immer Integer-Kupfer pro Einheit.
- Zeiten: `GetServerTime()` bevorzugen; keine `GetTime()`-Werte persistent speichern.

---

## 8. API-Migration

| Legacy-Verwendung | Forever-Ziel |
|---|---|
| `QueryAuctionItems` | `C_AuctionHouse.SendSearchQuery` oder `SendBrowseQuery` |
| `GetAuctionItemInfo` | Item-/Commodity-Resultfunktionen von `C_AuctionHouse` |
| `AUCTION_ITEM_LIST_UPDATE` | `ITEM_SEARCH_RESULTS_UPDATED` / `COMMODITY_SEARCH_RESULTS_UPDATED` |
| `CanSendAuctionQuery` | moderne Throttle-Bereitschaft und Throttle-Events |
| `PlaceAuctionBid("list", ...)` | `C_AuctionHouse.PlaceBid` für Item-Auktionen |
| keine Commodity-Trennung | `StartCommoditiesPurchase` plus Bestätigung |
| `StartAuction` | `C_AuctionHouse.PostItem` / `PostCommodity` |
| geschätzter Deposit | `CalculateItemDeposit` / `CalculateCommodityDeposit` |
| `AuctionFrame` | `AuctionHouseFrame` beziehungsweise AH-Lifecycle-Events |
| `GetContainer*` | `C_Container.*` und `ItemLocation` |
| `GetTradeSkill*` | `C_TradeSkillUI.*` mit Recipe-IDs und Schematics |
| Name als Schlüssel | Item-Key/Item-ID als Schlüssel |
| globale `event`, `arg1`, `this` | Callback-Parameter und `self` |

Die Tabelle beschreibt die Richtung, nicht die endgültigen Funktionssignaturen. LUNA MAX muss die Signaturen im aktuellen Client verifizieren.

---

## 9. AH-Abfrage- und Throttle-Modell

Alle AH-Abfragen laufen über eine gemeinsame Queue. Parallel laufende Scanner-, Mats-, Buyer- und Poster-Abfragen sind verboten.

```text
idle
  -> queued
  -> waiting_for_ready
  -> sent
  -> receiving_results
  -> normalizing
  -> complete

Fehlerpfade:
sent/receiving -> throttled -> waiting_for_ready
any active     -> timeout   -> failed
any active     -> AH closed -> cancelled
```

Jede Operation besitzt:

- eindeutige Operation-ID
- Typ und Ziel
- Startzeit und Deadline
- Retry-Zähler
- erwartete Ergebnis-Events
- Callback für Erfolg oder strukturierten Fehler

Vorgaben:

- exponentielles Retry ist unnötig; auf das Ready-Event warten
- maximal zwei echte Wiederholungen pro logischer Anfrage
- keine enge `OnUpdate`-Polling-Schleife
- alte oder fremde Events ignorieren
- Teilresultate nicht als vollständigen Scan kennzeichnen
- UI bleibt während großer Normalisierungen bedienbar

### Full Snapshot

`C_AuctionHouse.ReplicateItems()` darf nur als optionale Capability verwendet werden:

- vor Aufruf Verfügbarkeit prüfen
- Cooldown und Serverantwort respektieren
- Resultate als Snapshot mit Buildnummer markieren
- bei Fehler auf gezielte Suchen zurückfallen
- niemals Voraussetzung für normale Rezeptanalyse

---

## 10. Kauf- und Post-Sicherheit

### Kaufablauf

```text
plan -> preview -> refresh price -> validate -> await user click
     -> item bid OR commodity start/confirm -> success/failure -> summary
```

Vor der Ausführung erneut prüfen:

- AH geöffnet
- Angebot noch vorhanden
- Preis nicht über Nutzerlimit
- resultierende Marge nicht unter Mindestmarge
- ausreichendes Gold
- keine eigene Auktion
- Menge entspricht dem bestätigten Plan
- keine andere Operation aktiv

Bei Commodities muss jede vom Client vorgesehene Start-/Confirm-Sequenz eingehalten werden. Preisänderungen zwischen Start und Confirm führen zu einer neuen Vorschau, nicht zu stiller Akzeptanz.

### Postablauf

```text
select inventory item -> query competition -> build plan -> preview
-> validate inventory/deposit -> await user click -> post -> event confirmation
```

Vorgaben:

- kein pauschales „Post everything“ in Release 1
- standardmäßig Marktpreis matchen; Undercut nur als ausdrückliche Einstellung
- Mindestpreis aus Herstellkosten, AH-Gebühr, Deposit und Mindestmarge
- bei fehlenden Kostendaten kein automatischer Preisvorschlag
- ItemLocation unmittelbar vor dem API-Aufruf neu bestimmen
- bei Bag-Änderung Plan verwerfen und neu aufbauen

---

## 11. Berechnungsregeln

Alle Berechnungen erfolgen mit Integer-Kupfer. Rundung muss explizit und getestet sein.

```text
materialCost = Sum(reagentUnitPrice * reagentQuantity)
grossRevenue = saleUnitPrice * outputQuantity
auctionCut   = API-Wert oder bestätigter Clientwert
depositRisk  = Deposit nach gewählter Laufzeit und Menge
netRevenue   = grossRevenue - auctionCut - depositRisk
profit       = netRevenue - materialCost
margin       = profit / materialCost * 100
```

Regeln:

- Mehrfachoutput eines Rezepts berücksichtigen.
- Fehlende Preise ergeben `incomplete`, nicht Preis `0`.
- Vendorpreise nur verwenden, wenn die Quelle durch API oder bestätigte Konfiguration bekannt ist.
- Deposit getrennt ausweisen; bei erfolgreichem Verkauf ist seine wirtschaftliche Behandlung konfigurierbar zu dokumentieren.
- Historische Durchschnitte dürfen aktuelle Kaufgrenzen nicht ohne sichtbaren Hinweis ersetzen.
- Deal-Erkennung verwendet nur ausreichend frische und genügend viele Historieneinträge.

---

## 12. UI-Konzept

Release 1 behält das bekannte Arbeitsmodell bei, nutzt aber die Forever-UI-Konventionen:

### Hauptfenster

- Tabs: `Rezepte`, `Materialien`, `Transmutationen`
- Statuszeile für AH-Verbindung, Queue, Throttle und Datenalter
- filter- und sortierbare Tabelle
- Spalten: Produkt, Kosten, Marktpreis, Netto, Gewinn, Marge, Menge, Aktualisiert
- fehlende oder partielle Daten klar markieren
- kein farblicher Status als einzige Informationsquelle

### Rezeptdetail

- Zutaten mit benötigter Menge, Stückpreis, Datenalter und Quelle
- Outputmenge und Verkaufspreis
- AH-Gebühr und Deposit separat
- vollständige Rechenformel
- Aktionen: `Preise aktualisieren`, `Kaufplan`, `Postplan`

### Diagnose

`/aht debug` zeigt kopierbar:

- Addonversion
- Clientbuild und Interface
- Projekt-ID/Flavor
- erkannte Capabilitys
- letzte Operation samt Fehlercode
- Queue- und Throttle-Zustand
- Anzahl gespeicherter Rezepte/Marktdaten

Keine Account-, Charakter- oder sonstigen personenbezogenen Daten ausgeben.

---

## 13. Implementierungsphasen

### Phase 0 – Runtime-Vertrag beweisen

1. Aktuellen Beta-Build und Interface-Wert lesen.
2. Minimalen Diagnose-Prototyp im neuen Ziel anlegen.
3. Vorhandensein und Typ aller benötigten API-Funktionen prüfen.
4. Events beim Öffnen/Schließen des AH und bei einer manuellen Suche protokollieren.
5. Item- und Commodity-Suche separat testen.
6. Ergebnisse als `FOREVER_API_PROBE.md` dokumentieren.

**Gate:** Keine produktive AH-Logik, bevor der Vertrag dokumentiert ist.

### Phase 1 – Lauffähiges Fundament

1. TOC, Bootstrap, Locale und SavedVariables anlegen.
2. `Capabilities.lua`, `Store.lua` und `Diagnostics.lua` implementieren.
3. `/aht`, `/aht debug` und `/aht reset` bereitstellen.
4. Fehlerfreie Anmeldung, `/reload` und Logout-Speicherung prüfen.

**Gate:** Null Lua-Fehler bei Login, `/reload` und Logout.

### Phase 2 – AH-Leseweg

1. `AuctionHouse.lua` mit Queue, Operation-ID und Throttle-Handling bauen.
2. gezielte Item- und Commodity-Suche implementieren
3. Ergebnisse normalisieren
4. `Scanner.lua` mit Deduplizierung und Fortschritt ergänzen
5. optionalen Replicate-Pfad capability-gated hinzufügen

**Gate:** Wiederholbare Suche nach mindestens einem Item und einer Commodity; korrekter Stückpreis und korrekte Menge.

### Phase 3 – Rezepte und Kalkulation

1. gelernte Alchemie-Rezepte über `C_TradeSkillUI` einlesen
2. Schematics und Outputmengen normalisieren
3. Item-Cache asynchron behandeln
4. reine Calculator-Funktionen und Tests implementieren
5. Haupttabelle und Rezeptdetail anzeigen

**Gate:** Mindestens drei echte Rezepte stimmen manuell mit den angezeigten API-Daten überein.

### Phase 4 – Materialien und Historie

1. Watchlist-Verwaltung implementieren
2. begrenzte Historie und gewichtete Anzeige ergänzen
3. Datenalter und unvollständige Snapshots darstellen
4. SavedVariables-Migration testen

**Gate:** Daten bleiben nach `/reload` erhalten; History-Limit wird eingehalten.

### Phase 5 – Kontrollierter Einkauf

1. Kaufplan und Vorschau implementieren
2. Preisgrenzen und Margenschutz testen
3. Item- und Commodity-Kauf getrennt implementieren
4. Events, Preisänderungen und Teilkäufe behandeln
5. Nutzerbestätigung vor jeder Ausführung erzwingen

**Gate:** Ein günstiger Testkauf funktioniert; absichtlich zu teures Angebot wird sicher abgelehnt.

### Phase 6 – Kontrolliertes Posten

1. moderne Container-/ItemLocation-Ermittlung
2. Postplan und Deposit-Berechnung
3. Item- und Commodity-Posting
4. Bestandsänderung und Fehlerfälle behandeln
5. Nutzerbestätigung erzwingen

**Gate:** Ein niedrigwertiger Testgegenstand kann gepostet und im eigenen Auktionsbestand erkannt werden.

### Phase 7 – Transmute, Polish und Beta-Härtung

1. Transmutationsansicht auf Basis gelernter Rezepte ergänzen
2. Lokalisierung vervollständigen
3. UI-Zustände, Tooltips und Fehlertexte überarbeiten
4. längeren AH-Test mit konkurrierenden Addons durchführen
5. Dokumentation und bekannte Einschränkungen abschließen

**Gate:** vollständiger Abnahmelauf ohne Lua-Fehler, Deadlock oder unbeabsichtigte Aktion.

---

## 14. Verifikation

### Statische Gates

- Lua-Syntaxprüfung mit einer zum Client passenden Lua-Version
- keine Legacy-AH-Aufrufe im Forever-Ziel
- keine direkten `C_AuctionHouse`-Aufrufe außerhalb `AuctionHouse.lua`
- keine unbeschränkten SavedVariables-Historien
- keine geheimen oder personenbezogenen Daten in Logs
- optional Semgrep, sofern eine relevante Lua-Regelbasis vorhanden ist

Beispiel für den Legacy-API-Audit:

```text
QueryAuctionItems
GetAuctionItemInfo
PlaceAuctionBid
StartAuction
ClickAuctionSellItemButton
CanSendAuctionQuery
GetTradeSkillLine
GetTradeSkillInfo
GetContainerItemInfo ohne C_Container
AuctionFrame
```

### Deterministische Tests

- Preisnormalisierung für Einzelauktionen und Commodities
- gemischte Stackgrößen
- Rundung auf Kupfer
- fehlende Preise
- Mehrfachoutput
- Mindestmarge
- Preisänderung zwischen Plan und Ausführung
- History-Limit und Datenmigration
- abgelaufene Daten
- Deduplizierung identischer Item-Keys

### Ingame-Matrix

| Test | Erwartung |
|---|---|
| Login ohne AH | keine Fehler, Diagnose verfügbar |
| AH öffnen/schließen | Status korrekt, aktive Operation wird abgebrochen |
| Item suchen | Ergebnis und Stückpreis korrekt |
| Commodity suchen | aggregierte Menge und Stückpreis korrekt |
| schnelles Wiederholen | Queue wartet auf Throttle-Ready |
| `/reload` während Idle | Daten bleiben erhalten |
| `/reload` während Operation | keine persistierte aktive Operation |
| fremdes AH-Addon aktiv | kein paralleler interner Request, sauberer Fehler/Retry |
| Preis ändert sich | Kauf/Post verlangt neue Bestätigung |
| Bag ändert sich | Postplan wird verworfen |
| Combat beginnt | keine geschützte Automatisierung |

---

## 15. Definition of Done

Release 1 ist nur fertig, wenn:

- der Legacy-Ordner unverändert geblieben ist
- ein getrenntes Forever-Ziel existiert
- der aktuelle Clientvertrag dokumentiert ist
- das Addon im Beta-Client sichtbar ist und ohne Lua-Fehler lädt
- Rezept-, Scan- und Kalkulationspfad mit echten Daten funktionieren
- Item- und Commodity-Ergebnisse korrekt getrennt werden
- Throttle-, Timeout- und AH-Close-Pfade geprüft wurden
- Kauf und Posten nur nach ausdrücklichem Nutzerklick erfolgen
- mindestens ein Testkauf und ein Testposting nachgewiesen sind
- SavedVariables nach `/reload` korrekt bleiben
- Syntaxprüfung und deterministische Tests grün sind
- Dokumentation, bekannte Einschränkungen und Build-Kompatibilität aktuell sind

Passing Unit-Tests allein reichen nicht. Die Abnahme benötigt einen echten Beta-Client-Test.

---

## 16. Bekannte Risiken

| Risiko | Gegenmaßnahme |
|---|---|
| Beta-API ändert sich | Capability-Layer, Build in Diagnose, keine verstreuten API-Aufrufe |
| falsche TOC-/Flavor-Annahme | Runtime prüfen und funktionierendes Forever-Addon als Manifestreferenz verwenden |
| AH-Throttling | zentrale Queue und Ready-Events |
| Commodity-/Item-Verwechslung | getrennte Adapterpfade, gemeinsames normalisiertes Ergebnisformat |
| Itemdaten noch nicht gecacht | asynchron laden, UI als „wartend“ markieren |
| Preis ändert sich beim Kauf | unmittelbar aktualisieren und erneut bestätigen |
| geschützte Aktion | Benutzerklick und sauberer Abbruch statt Umgehung |
| große Scans frieren UI ein | Batch-Verarbeitung und optionaler Full Snapshot |
| SavedVariables wachsen unbegrenzt | feste Limits und Migrationen |
| Third-Party-Lizenzverletzung | keine Codeübernahme; nur API-Verhalten vergleichen |

---

## 17. Quellen für die Implementierung

- Entwickler-Q&A: <https://www.youtube.com/watch?v=Y5zzSMSVhRo>
- Community-Transkript zum modernen API-Ansatz: <https://wowsod.pro/articles/wow-forever-qa-recap-september-17>
- Auctionator Forever 337: <https://www.curseforge.com/wow/addons/auctionator/files/8907278>
- WoW-API-Übersicht: <https://warcraft.wiki.gg/wiki/API>
- Blizzard-Hinweise zum AH-Throttling: <https://worldofwarcraft.blizzard.com/en-us/news/23277654>

Community-Seiten sind Hinweise, nicht die letzte Instanz. Bei Widersprüchen gilt der aktuelle Beta-Clientvertrag.

---

## 18. Direktauftrag zum Einfügen in LUNA MAX

> Implementiere `WOW4E_AH_Trader` gemäß diesem Dokument. Arbeite autonom, aber ändere den vorhandenen Turtle-WoW-Stand nicht. Beginne mit Phase 0 und dokumentiere den realen Forever-API-Vertrag, bevor du AH-Produktionslogik schreibst. Verwende eine zentrale `AuctionHouse.lua`-Abstraktion, moderne Item-/Commodity-Pfade, explizite Nutzerbestätigungen und defensives Throttle-/Event-Handling. Führe nach jeder Phase die zugehörigen Gates aus. Kopiere nichts aus Third-Party-Addons. Installiere nichts in den Beta-Client, committe, pushe oder veröffentliche nichts ohne ausdrückliche Freigabe. Melde Blocker mit konkreter API-Evidenz. Fertig ist die Arbeit erst nach Syntaxprüfung, deterministischen Tests und einem nachgewiesenen Ingame-Abnahmelauf.

