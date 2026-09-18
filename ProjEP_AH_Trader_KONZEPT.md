# ProjEP_AH_Trader – Umsetzungskonzept

**Zielplattform:** Project Epoch (WoW 3.3.5a / Wrath of the Lich King)  
**Basis:** Analyse von TWOW_AH_Trader v1.7.1 (Turtle WoW 1.12.1)  
**Stand:** 2026-04-25

---

## 1. Ausgangslage & Ziel

Das bestehende `TWOW_AH_Trader`-Addon ist vollständig auf Vanilla WoW 1.12.1 (Lua 5.0, Turtle WoW) ausgelegt. Turtle WoW und Project Epoch unterscheiden sich **fundamental** in API-Version, Lua-Version, Spielinhalt und AH-Mechanik. Ein direkter Port ohne Anpassung würde in Project Epoch nicht funktionieren.

Das neue Addon `ProjEP_AH_Trader` soll alle bewährten Kernfunktionen übernehmen, die WotLK-API vollständig nutzen, und um WotLK-spezifische Handwerksbereiche (Inschriftenkunde/Inscription, Schmuckkunst/Jewelcrafting, WotLK-Alchemie) erweitert werden.

---

## 2. Plattform-Vergleich: Turtle WoW vs. Project Epoch

### 2.1 Client-Version

| Eigenschaft | Turtle WoW | Project Epoch |
|---|---|---|
| WoW-Build | 1.12.1 (Vanilla) | 3.3.5a (WotLK) |
| Interface-Nummer | 11200 | 30300 |
| Lua-Version | **5.0** | **5.1** |
| Addon-API | Vanilla API | WotLK API |
| Erweiterungen | Custom Vanilla-Content | Vanilla + TBC + WotLK |

### 2.2 Lua-Unterschiede (Kritisch)

| Feature | Vanilla/Lua 5.0 | WotLK/Lua 5.1 |
|---|---|---|
| `#table` Länge | **NICHT verfügbar** → `getn(t)` | ✓ Verfügbar |
| `%` Modulo | **NICHT verfügbar** → `mod(a,b)` | ✓ Verfügbar |
| `string.match` | **NICHT verfügbar** → `strfind()` | ✓ Verfügbar |
| `string.gmatch` | **NICHT verfügbar** → `string.gfind()` | ✓ Verfügbar |
| Event-Handler | Global `event`, `arg1`–`arg9` | Parameter in Callback ODER globale (beide möglich) |
| Frame-Referenz | `this` (in SetScript) | `self` (modern) – `this` funktioniert noch |
| `print()` | **NICHT verfügbar** | ✓ Verfügbar (aber `DEFAULT_CHAT_FRAME` idiomatischer) |
| Mehrzeilige Strings | `[[...]]` nicht sicher | `[[...]]` sicher |

> **Im neuen Addon:** Moderneres Lua 5.1 nutzen. `self` statt `this` bevorzugen. `#table`, `%`, `string.match` überall verwenden.

### 2.3 Auktionshaus-API-Unterschiede (Kritisch)

| API-Funktion | Vanilla 1.12.1 | WotLK 3.3.5 | Bedeutung |
|---|---|---|---|
| `GetAuctionDeposit()` | **EXISTIERT NICHT** | ✓ `GetAuctionDeposit(duration, maxStack, numStacks)` | Korrekter Deposit ohne Schätzformel |
| `QueryAuctionItems(..., getAll)` | **NICHT verfügbar** | ✓ `getAll`-Parameter | Vollständiger AH-Scan auf einmal (15-min Cooldown) |
| `GetAuctionItemInfo` Rückgaben | 12 Felder | **18 Felder** (+ `bidderFullName`, `ownerFullName`, `saleStatus`, `itemId`, `hasAllInfo`) | Mehr Datenpunkte |
| `GetItemInfo` vendorPrice | **NICHT zurückgegeben** (nur 10 Felder) | ✓ `itemSellPrice` als 11. Feld | Echte Vendor-Preise statt Schätzung |
| Max Items/Seite (`list`) | 50 | 50 | Gleich |
| Max Items/Seite (`getAll`) | — | **~40.000** (alle AH-Einträge) | Game-changer für Scan-Strategie |
| AH-Provision | 5% | 5% | Gleich |

### 2.4 Spielinhalt-Unterschiede (Feature-relevanz)

**Vanilla (Turtle WoW):**
- Alchemie: Vanilla-Tränke, Elixiere, Arkanit-Transmute
- Kein Inschriftenkunde
- Grundlegendes Schmuckhandwerk ohne Gem-System
- Keine Northrend-Inhalte

**Project Epoch (WotLK):**
- Alchemie: WotLK-Tränke, Elixiere, Fläschchen, Titanbarren-Transmute, **Edelstein-Transmutes** (6 epische Edelsteintypen)
- **Inschriftenkunde (Inscription):** Glyphen sind ein Hauptverdienstfeld in WotLK
- **Schmuckkunst (Jewelcrafting):** Edelstein-Schliffe, Prospektieren von Erzen
- Death Knights, Nordend-Content
- Neue Materialien: Icethorn, Lichbloom, Saronit, Titanerz, etc.

---

## 3. Dateistruktur

```
ProjEP_AH_Trader/
├── ProjEP_AH_Trader.toc      – Addon-Metadaten (Interface: 30300)
├── Core.lua                   – Hauptobjekt, Events, Slash-Befehle, Persistenz
├── Locales.lua                – Lokalisierung (Deutsch + Englisch)
├── Scanner.lua                – AH-Scan (Standard-Scan + GetAll-Scan)
├── Calculator.lua             – Margenberechnung für alle Module
├── Buyer.lua                  – Automatischer AH-Einkauf mit Margenschutz
├── Poster.lua                 – Automatisches AH-Posten
├── UI.lua                     – Hauptfenster + Kaufdialog + Post-Dialog
├── Mats.lua                   – Material-Analyse (unveränderte Logik, API-aktualisiert)
├── Alchemy.lua                – WotLK-Alchemie: Tränke, Elixiere, Fläschchen, Transmutes
├── Transmute.lua              – WotLK-Transmuten (Titanbarren + 6x Epische Edelsteine)
├── Inscription.lua            – Inschriftenkunde-Modul (Glyphen-Analyse)
├── Jewelcrafting.lua          – Schmuckkunst-Modul (Edelstein-Schliffe)
└── DOKUMENTATION.md           – Vollständige Dokumentation
```

### Gegenüber TWOW_AH_Trader neu/geändert:
- `Alchemy.lua` ersetzt die direkte Rezept-Logik in `Recipes.lua` (das entfällt)
- `Transmute.lua` wird für WotLK-Transmutes komplett neu geschrieben
- `Inscription.lua` ist komplett neu
- `Jewelcrafting.lua` ist komplett neu
- `Core.lua`, `Scanner.lua`, `Calculator.lua`, `Buyer.lua`, `Poster.lua`, `UI.lua`, `Mats.lua` werden API-migriert

---

## 4. TOC-Datei

```lua
## Interface: 30300
## Title: ProjEP AH Trader
## Notes: AH-Analyse fuer Alchemie, Inschriftenkunde und Schmuckkunst
## Author: ProjEP_AHT
## Version: 1.0.0
## SavedVariables: ProjEP_AHT_DB

Core.lua
Locales.lua
Scanner.lua
Calculator.lua
Buyer.lua
Poster.lua
UI.lua
Mats.lua
Alchemy.lua
Transmute.lua
Inscription.lua
Jewelcrafting.lua
```

---

## 5. Technische Migrations-Anleitung (Vanilla → WotLK API)

### 5.1 Lua-Code-Migrationen

Jede der folgenden Änderungen ist im gesamten Code systematisch durchzuführen:

```lua
-- ALT (Vanilla/Lua 5.0)        → NEU (WotLK/Lua 5.1)
getn(table)                      → #table
mod(a, b)                        → a % b
strfind(s, p, i, plain)          → string.find(s, p, i, plain)
string.gfind(s, p)               → string.gmatch(s, p)
tinsert(t, v)                    → table.insert(t, v)
tremove(t, i)                    → table.remove(t, i)
strlower(s)                      → string.lower(s)  -- oder strlower, beide OK
this                             → self (in SetScript-Callbacks)
global event / arg1-arg9         → Callback-Parameter direkt nutzen
```

### 5.2 Event-Handler (Modernes Muster)

```lua
-- ALT: Vanilla globale Events
evtFrame:SetScript("OnEvent", function()
    if event == "AUCTION_HOUSE_SHOW" then
        -- arg1, arg2 global verfügbar
    end
end)

-- NEU: WotLK mit Parametern
evtFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "AUCTION_HOUSE_SHOW" then
        local arg1, arg2 = ...
    end
end)
```

### 5.3 SetScript-Callbacks

```lua
-- ALT: Vanilla
btn:SetScript("OnClick", function()
    -- 'this' ist der Button
    this:SetText("Clicked")
end)

-- NEU: WotLK
btn:SetScript("OnClick", function(self)
    self:SetText("Clicked")
end)
```

### 5.4 GetAuctionItemInfo (18 Felder in WotLK)

```lua
-- WotLK GetAuctionItemInfo gibt 18 Werte zurück
local name, texture, count, quality, canUse, level,
      levelColHeader, minBid, minIncrement, buyoutPrice,
      bidAmount, highBidder, bidderFullName, owner,
      ownerFullName, saleStatus, itemId, hasAllInfo
    = GetAuctionItemInfo("list", i)

-- Zusätzlich verfügbar: itemId (gut für zuverlässige Item-Identifikation!)
```

### 5.5 Deposit-Berechnung (WotLK: echte API)

```lua
-- ALT: Vanilla-Schätzformel (ungenau)
local vendorSell = math.floor(sellPrice * 0.02)
local deposit = math.max(1, math.floor(vendorSell * 0.36))

-- NEU: WotLK API (exakt)
-- GetAuctionDeposit(duration, maxStack, numStacks)
-- duration: 1=12h, 2=24h, 3=48h
local deposit = GetAuctionDeposit(2, stackSize, numStacks)
-- Gibt den genauen Deposit in Kupfer zurück
```

### 5.6 Vendor-Preise aus GetItemInfo (WotLK)

```lua
-- ALT: Vanilla – GetItemInfo gibt kein vendorPrice zurück (10 Felder)
-- → Feste Tabelle mit hardcodierten Vendor-Preisen nötig

-- NEU: WotLK – 11. Feld ist itemSellPrice (Vendor-Verkaufspreis)
local itemName, itemLink, itemRarity, itemLevel, itemMinLevel,
      itemType, itemSubType, itemStackCount, itemEquipLoc,
      itemTexture, itemSellPrice = GetItemInfo(itemNameOrLink)

-- itemSellPrice = was der Vendor für das Item bezahlt
-- AHT.vendorPrices kann jetzt dynamisch befüllt werden statt hardcoded
```

### 5.7 GetAll-Scan (WotLK-Killer-Feature)

```lua
-- WotLK: QueryAuctionItems mit getAll=true scannt ALLE Auktionen auf einmal
-- Cooldown: 15 Minuten (clientseitig erzwungen)
-- Liefert AUCTION_ITEM_LIST_UPDATE mit numBatchAuctions = Gesamtzahl

-- Aufruf:
QueryAuctionItems("", nil, nil, nil, nil, nil, 0, nil, nil, true)
--                ↑ leerer Name = alle Items
--                                                          ↑ getAll = true

-- Nach AUCTION_ITEM_LIST_UPDATE:
local numBatchAuctions, totalAuctions = GetNumAuctionItems("list")
-- numBatchAuctions = alle Auktionen in einer Antwort!

-- Vorteil: Ein einziger Scan erfasst das gesamte AH
-- Nachteil: 15-min-Cooldown, Client kann kurz einfrieren bei großem AH
```

### 5.8 Item-Link-Parsing (WotLK komplexer)

```lua
-- Vanilla Item-Link: |Hitem:itemId|h[Name]|h|r
-- WotLK Item-Link:   |Hitem:itemId:enchantId:gem1:gem2:gem3:gem4:suffixId:uniqueId:level:specId|h[Name]|h|r

-- Robuste Extraktion für WotLK:
local function GetItemIdFromLink(link)
    if not link then return nil end
    local itemId = link:match("|Hitem:(%d+):")
    return itemId and tonumber(itemId)
end

local function GetItemNameFromLink(link)
    if not link then return nil end
    return link:match("%[(.-)%]")
end

-- In WotLK besser: itemId als primären Schlüssel nutzen (stabiler als Name)
-- Preistabelle: [itemId] = price  (statt [itemName] = price)
```

---

## 6. Scanner-Modul: Zwei-Modus-Strategie

### 6.1 Standard-Scan (Kompatibilitätsmodus)
Identisch zur TWOW-Logik: Item-für-Item, Seite-für-Seite. Wird verwendet wenn:
- GetAll noch auf Cooldown ist
- Nur wenige bestimmte Items gescannt werden sollen
- Der schnelle gezielte Scan eines einzelnen Items nötig ist

### 6.2 GetAll-Scan (Primärmodus für WotLK)
```
Ablauf:
1. QueryAuctionItems("", ..., getAll=true)
2. Warten auf AUCTION_ITEM_LIST_UPDATE
3. Alle Einträge in einem Durchlauf verarbeiten
4. Preise für ALLE bekannten Items gleichzeitig aktualisieren
5. Cooldown von 15 Minuten anzeigen (Timer in der UI)
```

**Scanner-Zustandsautomat (erweitert):**
```
idle → getall_waiting → getall_sent → processing → idle (fertig)
  ↓                                                    ↑
  └─→ item_waiting → item_sent → (nächste Seite/Item) ─┘
        ↑               ↓ (Timeout → Retry, max 2×)
        └───────────────┘
```

### 6.3 GetAll-Cooldown-Tracking
```lua
AHT.getAllLastTime = 0       -- GetTime() des letzten GetAll-Scans
AHT.GET_ALL_COOLDOWN = 900  -- 15 Minuten in Sekunden

function AHT:CanGetAllScan()
    return (GetTime() - AHT.getAllLastTime) >= AHT.GET_ALL_COOLDOWN
end

function AHT:GetAllRemainingCooldown()
    local remaining = AHT.GET_ALL_COOLDOWN - (GetTime() - AHT.getAllLastTime)
    return math.max(0, math.floor(remaining))
end
```

---

## 7. Modul: Alchemie (WotLK)

### 7.1 WotLK-spezifische Inhalte

#### Northrend-Kräuter (Zutaten)
| Item | Verwendung |
|---|---|
| Icethorn (Eisdorn) | Tränke, Elixiere, Fläschchen |
| Lichbloom | Tränke, Elixiere, Fläschchen |
| Goldclover (Goldklee) | Anfänger-Northrend-Tränke |
| Deadnettle (Taubnessel) | Tränke |
| Fire Leaf / Tiger Lily | Verschiedene Tränke |
| Talandra's Rose | Mana-Tränke |
| Adder's Tongue | Elixiere, Fläschchen |
| Frost Lotus | Fläschchen (seltene Zutat) |

#### WotLK-Tränke (Beispiele mit höchster AH-Relevanz)
| Trank | Hauptzutaten | Zielgruppe |
|---|---|---|
| Potion of Speed (Trank der Schnelligkeit) | Icethorn, Lichbloom | DPS-Klassen (Raider) |
| Potion of Wild Magic | Icethorn, Lichbloom | Caster (Raider) |
| Endless Rage Potion | Goldclover, Tiger Lily | Krieger/DPS |
| Crazy Alchemist's Potion | Mix | Solisten |
| Indestructible Potion | Icethorn, Lichbloom | Tanks |

#### WotLK-Elixiere (Battle + Guardian → zusammen Flask-äquivalent)
Elixiere sind in WotLK in zwei Kategorien: Battle (Offensiv) und Guardian (Defensiv). Ein Spieler kann einen von jeder Sorte benutzen.

#### WotLK-Fläschchen (Flasks) – Hochprofitabel
| Flask | Zutaten | Effekt |
|---|---|---|
| Flask of Endless Rage | Icethorn ×7, Lichbloom ×7, Frost Lotus ×1 | Angriffskraft |
| Flask of Pure Mojo | Icethorn ×7, Lichbloom ×7, Frost Lotus ×1 | MP5 |
| Flask of Stoneblood | Icethorn ×7, Lichbloom ×7, Frost Lotus ×1 | HP |
| Flask of the Frost Wyrm | Icethorn ×7, Lichbloom ×7, Frost Lotus ×1 | Zaubermacht |

> **Fläschchen sind in WotLK das profitabelste Alchemie-Produkt.** Frost Lotus als Engpass-Zutat bestimmt maßgeblich die Rentabilität.

#### Transmutation: WotLK-Spezifika
Vollständige Liste der neuen WotLK-Transmuten (Details in Abschnitt 8).

### 7.2 Alchemie-Spezialisierung (Transmutation Master)
In WotLK hat der Transmutation Master eine **Proc-Chance** (~20%), bei einer Transmutation ein zusätzliches Ergebnis zu erhalten. Das muss in der Margenberechnung berücksichtigt werden:

```lua
-- Erwarteter Gewinn mit Transmutation Master:
-- effectiveOutput = 1 + (procChance × procMultiplier)
-- Bei Transmutation Master: effectiveOutput = 1 + (0.20 × 1.0) = 1.20

local TRANSMUTE_MASTER_PROC_CHANCE = 0.20  -- 20% Chance
local TRANSMUTE_MASTER_PROC_MULT   = 1.0   -- 1 zusätzliches Item bei Proc

function AHT:CalcEffectiveTransmuteOutput(baseOutput, isMaster)
    if isMaster then
        return baseOutput * (1 + TRANSMUTE_MASTER_PROC_CHANCE * TRANSMUTE_MASTER_PROC_MULT)
    end
    return baseOutput
end
```

Die UI soll eine Checkbox "Transmutation Master?" anbieten und die Marge entsprechend anpassen.

---

## 8. Modul: Transmutationen (WotLK)

### 8.1 WotLK-Transmutes vs. Vanilla-Transmutes

**Vanilla (TWOW):** Nur Arkanit-Transmute (Thorniumbarren + Arkankristall → Arkanitbarren) + elementare Transmutes.

**WotLK:** Titanbarren-Transmute + 6 epische Edelstein-Transmutes + Erde/Wasser etc. bleiben erhalten.

### 8.2 Transmute-Liste (WotLK)

| Transmutation | Input | Output | Cooldown |
|---|---|---|---|
| Transmute: Titanium | 8× Saronit-Barren | 1× Titan-Barren | 20h |
| Transmute: Ametrine | 1× Eternal Shadow + 1× Eternal Fire | 1× Ametrine | 20h |
| Transmute: Cardinal Ruby | 1× Eternal Fire + 1× Eternal Life | 1× Cardinal Ruby | 20h |
| Transmute: Dreadstone | 1× Eternal Shadow + 1× Eternal Life | 1× Dreadstone | 20h |
| Transmute: Eye of Zul | 1× Eternal Life + 1× Eternal Water | 1× Eye of Zul | 20h |
| Transmute: King's Amber | 1× Eternal Life + 1× Eternal Air | 1× King's Amber | 20h |
| Transmute: Majestic Zircon | 1× Eternal Air + 1× Eternal Water | 1× Majestic Zircon | 20h |

### 8.3 Transmute-UI (WotLK)

Das Transmute-Fenster zeigt eine Tabelle aller Transmutes mit:
- Materialkosten (aktuell)
- Verkaufspreis des Outputs
- Erwarteter Gewinn (ohne/mit Master-Proc)
- 20h-Cooldown-Hinweis
- Empfehlung: Welcher Transmute ist heute am profitabelsten?

---

## 9. Modul: Inschriftenkunde (Inscription) — NEU

### 9.1 Warum Inscription?
Inschriftenkunde-Glyphen sind in WotLK das **profitabelste Handwerk** im Auktionshaus:
- Jeder Spieler jeder Klasse benötigt 6 Glyphen (2 Major, 2 Minor = mehr in späteren Patches)
- Hunderte verschiedene Glyphen für alle Klassen
- Materialien (Tinte) sind günstig herzustellen
- Hoher Umsatz durch konstante Nachfrage

### 9.2 Materialfluss
```
Northrend-Kräuter (Icethorn, Lichbloom, etc.)
    ↓ Mahlen (Mill) [5 Kräuter → 2-4 Pigmente]
Pigmente (Midnight Pigment, Azure Pigment, etc.)
    ↓ Tinte herstellen
Tinte (Ink of the Sea, Snowfall Ink)
    ↓ Glyph herstellen
Glyph der [Klasse/Fähigkeit]
```

### 9.3 Tinte/Pigment-Tabelle (WotLK Northrend)

| Kräuter | Pigment | Tinte |
|---|---|---|
| Icethorn, Lichbloom, Adder's Tongue, Goldclover, Deadnettle, Tiger Lily, Talandra's Rose | Azure Pigment (häufig) | Ink of the Sea |
| Icethorn, Lichbloom, Adder's Tongue | Icy Pigment (selten) | Snowfall Ink |

**Ink of the Sea** = Standard-Tinte für ~95% aller WotLK-Glyphen  
**Snowfall Ink** = Selten, Nebenerzeugnis, für shoulder inscriptions und Darkmoon Cards

### 9.4 Herstellungskosten-Berechnung

```
Kosten pro Ink of the Sea:
= (Preis für 5× Kräuter) × (1 / erwartete_Azure_Pigmente_pro_5_Kräuter)

Erwartete Pigmente pro 5 Kräuter (empirisch):
- Icethorn: ~2.5 Azure + 0.15 Icy
- Lichbloom: ~2.5 Azure + 0.15 Icy
- Adder's Tongue: ~2.2 Azure + 0.12 Icy
- Goldclover: ~2.2 Azure + 0.05 Icy
- Tiger Lily: ~2.0 Azure + 0.05 Icy
- Talandra's Rose: ~2.0 Azure + 0.08 Icy
- Deadnettle: ~2.0 Azure + 0.05 Icy

Kosten pro Glyph = (benötigte Tinten × Tintenkosten) + (Parchment-Kosten)
```

Die Mahl-Raten sind konfigurierbar (empirische Werte variieren zwischen Servern).

### 9.5 Inscription-Modul-Struktur

```lua
-- Inscription.lua
ProjEP_AHT.glyphs = {}          -- [glyphName] = { class, tintas = {}, parchment }
ProjEP_AHT.inkPrices = {}       -- [inkName] = berechneter Preis pro Tinte
ProjEP_AHT.millRates = {}       -- [herbName] = { azure = X, icy = Y } (Pigmente pro 5 Kräuter)
ProjEP_AHT.glyphResults = {}    -- Berechnete Margen für alle Glyphen
```

**Wichtige UI-Features:**
- Filter nach Klasse (Krieger, Paladin, Jäger, etc.)
- Sortierung nach Marge / Gewinn
- Markierung der profitabelsten Glyph je Klasse
- Mahl-Raten konfigurierbar (für Server-spezifische Werte)

---

## 10. Modul: Schmuckkunst (Jewelcrafting) — NEU

### 10.1 Edelstein-System WotLK

**Prospektion (Prospecting):** 5× Erz → zufällige rohe Edelsteine
**Schliff (Cut):** Roher Edelstein + Rezept → Geschliffener Edelstein (AH-fähig)

### 10.2 Northrend-Erze und Edelstein-Drops

| Erz | Häufige Gems | Seltene Gems |
|---|---|---|
| Cobalt Ore | Bloodstone, Shadow Crystal, Chalcedony, Dark Jade, Huge Citrine, Sun Crystal | Rare (Northrend) |
| Saronite Ore | Wie Cobalt + höhere Wahrscheinlichkeit | Bloodstone, Shadow Crystal, etc. |
| Titanium Ore | Selten: Gem-Drops + **Rare Gems** direkt | Cardinal Ruby, King's Amber, etc. |

### 10.3 Epische Edelsteine (WotLK Phase 3+)

| Gem | Farbe | Primärer Einsatz |
|---|---|---|
| Cardinal Ruby | Rot | Stärke, Angriffskraft, Zaubermacht |
| Ametrine | Orange | Hybrid-Stats |
| King's Amber | Gelb | Haste, Hit, Crit |
| Dreadstone | Violett | Hybrid-Stats |
| Eye of Zul | Grün | Ausdauer-Hybrid |
| Majestic Zircon | Blau | Ausdauer, Spirit |

### 10.4 Jewelcrafting-Modul-Strategie

Das JC-Modul analysiert zwei separate Profitmöglichkeiten:

**A) Rohe Gems schneiden:**
- Preis roher Gem → Preis geschliffener Gem × mehrere Schliff-Varianten
- Empfehlung: Welcher Schliff ist aktuell am profitabelsten?

**B) Prospecting-Analyse:**
- Saroniterzpreis → erwarteter Rohgem-Ertrag → bester Schliff → Gesamtgewinn
- Vergleich: Erz prospektieren vs. direkt rohe Gems kaufen

---

## 11. Datenbank-Schema (SavedVariables)

```lua
ProjEP_AHT_DB = {
    -- ── Kern (aus TWOW portiert, Schlüssel: itemName ODER itemId) ──
    prices          = {},   -- [itemId] = günstigster Buyout pro Stück (Kupfer)
    priceUpdated    = {},   -- [itemId] = Unix-Timestamp
    priceHistory    = {},   -- [itemId] = { {t=, p=}, ... } (letzte 20 Einträge)
    listingCounts   = {},   -- [itemId] = Anzahl Listings

    -- ── Alchemie ────────────────────────────────────────────────
    recipes         = {},   -- [{name, id, reagents=[{id, count}]}]
    selected        = {},   -- [recipeName] = true/false
    isMasterAlch    = false, -- Spezialisierung: Transmutation Master?

    -- ── Mats (portiert) ─────────────────────────────────────────
    materials       = {},   -- [itemId] = true
    matsSelected    = {},   -- [itemId] = true/false
    matsCategories  = {},   -- [itemId] = categoryId
    matsHistory     = {},   -- [itemId] = { {t=, p=, weighted_avg=}, ... }

    -- ── Inscription ─────────────────────────────────────────────
    millRates       = {},   -- [herbId] = { azure=X, icy=Y }
    glyphSelected   = {},   -- [glyphName] = true/false
    glyphClassFilter = nil, -- aktive Klassen-Filter oder nil = alle

    -- ── Schmuckkunst ─────────────────────────────────────────────
    prospectRates   = {},   -- [oreId] = { [gemId] = rate, ... }
    gemCutSelected  = {},   -- [gemName] = true/false

    -- ── Scanner ─────────────────────────────────────────────────
    getAllLastTime   = 0,    -- GetTime() des letzten GetAll-Scans (für Cooldown)
    scanPreference  = "getall",  -- "getall" oder "item" (User-Präferenz)
}
```

**Wichtige Änderung gegenüber TWOW:** Primärschlüssel ist **itemId** (Zahl) statt itemName (String). Grund: WotLK-Itemlinks enthalten die itemId zuverlässig. Item-Namen können durch Serverkonfiguration variieren; IDs sind stabil.

Zusätzlich: `idToName` und `nameToId` Lookup-Tabellen zur Laufzeit aus `GetItemInfo`.

---

## 12. Berechnungslogik

### 12.1 AH-Provision (WotLK)

| AH-Typ | Provision |
|---|---|
| Allianz / Horde | 5% des Buyout-Preises |
| Neutral (Goblin) | 15% des Buyout-Preises |

Project Epoch hat wahrscheinlich das Standard-WotLK-System. **Prüfen: Gibt es auf Project Epoch ggf. modifizierte AH-Gebühren?** (Serverconfig-abhängig)

```lua
local AH_CUT_FACTION = 0.05
local AH_CUT_NEUTRAL = 0.15
AHT.ahCutRate = AH_CUT_FACTION  -- konfigurierbar
```

### 12.2 Deposit (WotLK: echte API)

```lua
-- GetAuctionDeposit(duration, maxStack, numStacks)
-- duration: 1=12h, 2=24h, 3=48h
-- Für Standard-24h-Posting mit Stack=1:
local deposit = GetAuctionDeposit(2, 1, 1)

-- Wichtig: Muss aufgerufen werden wenn AH offen ist und das Item im Sell-Slot liegt
-- Für Pre-Berechnung ohne Sell-Slot: vendorSellPrice aus GetItemInfo nutzen
```

### 12.3 Gewinn-Formel (identisch zu TWOW, Deposit-Berechnung verbessert)

```
Brutto-Einnahme  = Verkaufspreis
AH-Provision     = floor(Verkaufspreis × ahCutRate)
Deposit          = GetAuctionDeposit(2, 1, 1)  -- exakt statt Schätzung
Netto-Einnahme   = Brutto - Provision - Deposit
Gewinn           = Netto-Einnahme - Zutatenkosten
Marge            = (Gewinn / Zutatenkosten) × 100%
```

### 12.4 Inscription-Kostenberechnung

```
Tinte-Kosten (Ink of the Sea) pro Tinte:
= min(Herb1Preis/millRate_azure_1, Herb2Preis/millRate_azure_2, ...) × 5
  (günstigster Kräuter-Typ als Basis)

Alternativ: direkter Kauf von Ink of the Sea vom AH

Glyph-Kosten = (Anzahl_Tinten × Tintenpreis) + Parchment-Preis

Parchment-Preise (Vendor):
- Light Parchment: 10c (Vendor)
- Common Parchment: 50c (Vendor)
- Heavy Parchment: 1s (Vendor)
```

### 12.5 Prospecting-Erwartungswert

```
Erwartete Gems aus X Erzen:
= Σ(gemDropRate[gemId] × floor(X/5))

Erwarteter Erlös:
= Σ(bestCutPrice[gemId] × erwartete_Anzahl[gemId]) - AH-Gebühren

Brutto-Profit aus Prospecting:
= Erwarteter Erlös - (X × Erzpreis)
```

---

## 13. UI-Konzept (Änderungen gegenüber TWOW)

### 13.1 Hauptfenster: Tabellen-Tabs

Da jetzt mehrere Berufe unterstützt werden, erhält das Hauptfenster **Tab-Navigation:**

```
[Alchemie] [Transmuten] [Inschrift] [Schmuckkunst] [Materialien]
```

Jeder Tab zeigt seine eigene scrollbare Ergebnisliste mit profession-spezifischen Spalten.

### 13.2 AH-Buttons (am Auktionshaus-Frame)

```
[Trank-Analyse] [Transmuten] [Glyphen] [Gems] [Mats] [GetAll-Scan ⏱15:00]
```

Der GetAll-Button zeigt den Cooldown-Countdown an. Bei aktivem Cooldown ist er deaktiviert und zeigt `mm:ss`.

### 13.3 GetAll-Scan Fortschrittsanzeige

Da der GetAll-Scan alle Daten auf einmal liefert, gibt es keinen Seiten-Fortschritt. Stattdessen:
1. „Sende GetAll-Anfrage..." (Button kurz deaktiviert)
2. „Verarbeite X von Y Auktionen..." (Processing-Phase)
3. „Scan abgeschlossen: X Items aktualisiert"

### 13.4 Transmutation-Master-Checkbox

Im Transmuten-Tab: Checkbox „Transmutation Master (Proc +20%)" → passt alle Gewinnberechnungen für Transmutes an.

### 13.5 Inscription-Tab spezifisch

- Dropdown „Klasse filtern" (alle Klassen + Alle)
- Spalten: Glyph-Name | Klasse | Tinten-Kosten | Verkaufspreis | Gewinn | Marge
- Highlight: Beste Glyph je Klasse mit Icon

### 13.6 Tooltips (erweitert)

WotLK-Tooltips können mittels `GameTooltip:SetHyperlink(itemLink)` den echten Item-Tooltip anzeigen. Das wird für alle Zeilen in den Ergebnislisten verwendet, damit der Spieler ein Item-Tooltip-Preview beim Hovern sieht.

---

## 14. Slash-Befehle

| Befehl | Funktion |
|---|---|
| `/aht` | Hauptfenster öffnen |
| `/aht scan` | Item-für-Item-Scan starten (aktive Rezepte) |
| `/aht getall` | GetAll-Scan starten (alle AH-Daten) |
| `/aht stop` | Scan/Kauf/Post abbrechen |
| `/aht reset` | Preisdaten löschen |
| `/aht mats` | Material-Verwaltung |
| `/aht snipe` | Schnäppchen-Scan aller bekannten Items |
| `/aht debug` | Diagnose |
| `/aht master` | Transmutation-Master togglen |
| `/aht millrate [herb] [azure] [icy]` | Mahl-Rate manuell setzen |

---

## 15. Sicherheitsfeatures (portiert + erweitert)

Alle TWOW-Sicherheitsfeatures bleiben erhalten:
- Eigene Auktionen nicht kaufen (`ownerFullName`-Prüfung statt `owner`)
- Nur 1 Kauf pro AH-Update
- Margenschutz (min. 10% Marge beim Kauf)
- Goldprüfung vor Kauf
- AH-Closed: Alle Operationen abbrechen

**Neu für WotLK:**
- `ownerFullName` (Realm-Name enthaltend) für korrekte Cross-Realm-Prüfung nutzen
- GetAll-Cooldown-Schutz: Kein erneuter GetAll vor Ablauf der 15 Minuten

---

## 16. Lokalisierung

Gleiches System wie TWOW (via `GetLocale()`). Zusätzliche Schlüssel nötig für:
- Inscription-UI
- Jewelcrafting-UI
- WotLK-Transmute-Bezeichnungen
- GetAll-Scan-Texte
- Transmutation-Master-Texte

Neue WotLK-Item-Namen (EN + DE):

| Englisch | Deutsch |
|---|---|
| Ink of the Sea | Tinte des Meeres |
| Snowfall Ink | Schneefallstinte |
| Icethorn | Eisendorn |
| Lichbloom | Lichblüte |
| Frost Lotus | Frostlotus |
| Saronite Ore | Saroniiterz |
| Titanium Ore | Titanerz |
| Cardinal Ruby | Cardinal-Rubin |
| King's Amber | Amber des Königs |

---

## 17. Abkürzungs-Reihenfolge bei der Implementierung

**Phase 1 – Kern migrieren (Basis lauffähig):**
1. `TOC` auf Interface 30300
2. `Core.lua`: Lua 5.1 Migration, neue SavedVariables, itemId-basierte Preise
3. `Scanner.lua`: API-Migration, GetAll-Scan implementieren
4. `Calculator.lua`: Lua 5.1 Migration, echte Deposit-Berechnung
5. `Buyer.lua` + `Poster.lua`: API-Migration
6. `UI.lua`: Lua 5.1 Migration, Tab-System
7. `Locales.lua`: WotLK-Strings ergänzen

**Phase 2 – WotLK-Alchemie:**
8. `Alchemy.lua`: WotLK-Tränke, Elixiere, Fläschchen
9. `Transmute.lua`: Titanbarren + 6 Epische Edelsteine, Master-Proc

**Phase 3 – Neue Module:**
10. `Inscription.lua`: Glyphen-Analyse, Ink-Kostenberechnung
11. `Jewelcrafting.lua`: Gem-Schliff-Analyse, Prospecting-Analyse

**Phase 4 – Mats & Polish:**
12. `Mats.lua`: API-Migration, Erweiterung um Northrend-Items
13. UI-Feinschliff, GetAll-Cooldown-Anzeige, Tooltips

---

## 18. Kritische Risiken & Offene Punkte

### 18.1 AH-Gebühren auf Project Epoch
**Unbekannt:** Hat Project Epoch Standard-WotLK-AH-Gebühren (5%/15%) oder angepasste Werte?  
→ Im Client prüfen oder im Project Epoch Forum/Wiki nachschlagen.

### 18.2 GetAll-Verfügbarkeit
**Unbekannt:** Erlaubt Project Epoch den `getAll`-Parameter in `QueryAuctionItems`?  
→ Technisch in WotLK verfügbar. Manche private Server deaktivieren es.  
→ Beim ersten Start testen; automatischer Fallback auf Item-Scan.

### 18.3 Mahl-Raten (Milling Rates)
Die Drop-Raten beim Mahlen sind empirisch und können serverspezifisch sein.  
→ Im Addon konfigurierbar machen. Standardwerte aus Wowhead WotLK nutzen.

### 18.4 Inscription-Rezepte
Die vollständige Liste aller Glyphen-Rezepte muss manuell oder über die TradeSkill-API erfasst werden. Das Addon sollte die Glyphen aus dem Berufe-Fenster auslesen (analog zu TWOW `TRADE_SKILL_SHOW`) – nicht hardcoded.

### 18.5 Vendor-Preise für WotLK-Phiolen
WotLK nutzt andere Alchemiephiolen. In WotLK gibt es keine "Crystal Vials" mehr – Tränke können direkt ohne Phiolen hergestellt werden (bis auf einige Spezialfälle). Vendor-Preisliste muss überprüft werden.

### 18.6 AH-Scan bei Konkurrenzaddons
Wenn Spieler auf Project Epoch Auctioneer oder Auctionator nutzen, kann es zu Query-Konflikten kommen. Implementierung muss `CanSendAuctionQuery()` korrekt respektieren.

---

## 19. Referenz: Bekannte WotLK-AH-Addons auf privaten Servern

Diese Addons funktionieren auf WotLK 3.3.5 Servern und können als Referenz-Implementierungen dienen:

| Addon | Fokus | Referenz-Wert |
|---|---|---|
| **Auctionator** (WotLK) | Einfacher AH-Scan, Kauf/Verkauf | GetAll-Scan Implementierung |
| **Auctioneer** (WotLK) | Umfassende Statistiken | Datenmodell, Bewertungslogik |
| **TradeSkillMaster 1.x** (WotLK) | Craft+Post Automatisierung | Rezepte-Erkennung, Posting-Logik |
| **GnomeWorks** | Handwerk-Helper | Rezepte-Datenbank |

Diese Addons nutzen alle den WotLK-API-Stil und können als Code-Referenz für korrekte API-Nutzung herangezogen werden.

---

## 20. Zusammenfassung der wichtigsten Änderungen

| Bereich | TWOW_AH_Trader | ProjEP_AH_Trader |
|---|---|---|
| **Interface** | 11200 (Vanilla) | 30300 (WotLK) |
| **Lua** | 5.0 (Einschränkungen) | 5.1 (modern) |
| **Item-Schlüssel** | Item-Name (String) | Item-ID (Zahl) |
| **Deposit-Berechnung** | Schätzformel (~2% von AH-Preis) | `GetAuctionDeposit()` API |
| **Vendor-Preise** | Hardcodierte Tabelle | `GetItemInfo().itemSellPrice` |
| **Scan-Methode** | Nur Item-für-Item | Item-Scan + GetAll-Scan |
| **Alchemie-Inhalte** | Vanilla-Tränke + Arkanit | WotLK-Tränke/Fläschchen/Transmutes |
| **Transmutation** | Nur Arkanit | Titan + 6× Epische Gems |
| **Master-Proc** | Nicht vorhanden | Transmutation Master Checkbox |
| **Inscription** | Nicht vorhanden | Glyphen-Analyse-Modul |
| **Jewelcrafting** | Nicht vorhanden | Gem-Schliff + Prospecting |
| **UI** | Einzel-Fenster | Tab-Navigation |
| **AH-Buttons** | 3 Buttons | 6 Buttons + GetAll-Timer |
