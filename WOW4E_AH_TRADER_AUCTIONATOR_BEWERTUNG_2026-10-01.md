# AH Trader: Funktions- und UI-Bewertung anhand von Auctionator

Stand: 1. Oktober 2026. Bewertet wurden WOW4E AH Trader 0.8.1-beta, Commit `3629a97`, und die installierte Auctionator-Version 339. Zielclient: WoW Forever, Interface 16001.

Die 19 Lua-Dateien und die TOC-Datei von AHT stimmen per SHA-256 zwischen Repository und installiertem Addon überein. Die vorhandenen Lua-Balance- und Source-Audits bestehen. Diese Bewertung beruht auf aktuellem Quellcode und Layoutdefinitionen. Rendering, Klickabläufe, tatsächliche Käufe und Datenhaltbarkeit nach einem vollständigen Clientneustart wurden für diese Bewertung nicht neu im Spiel getestet.

## Gesamtbewertung

AHT besitzt bereits eine gute Grundlage für berufsübergreifende Herstellungsplanung: aktueller Scanpreis, historischer Marktwert, altersgewichteter Durchschnitt, Zutatenpreise, Taschen-/Bankbestand, Auftragsreservierungen und protokollierte Käufe. Die vier Hauptansichten **Herstellen, Markt, Chancen und Aufträge**, sortierbare Spalten und eine eigene schwarze Hintergrundtextur sind vorhanden. Diese Punkte müssen nicht erneut eingeführt werden.

Auctionator ist im untersuchten Code stärker auf das unmittelbare Kaufen und Verkaufen ausgerichtet. Es verbindet konkrete Angebote mit Mengenwahl, Stück- und Gesamtpreis, nachvollziehbaren Bestätigungen, Taschenübersicht, Preis-/Postinghistorie und wiederverwendbaren Einkaufslisten. Seine Tabellen verwenden wiederverwendete sichtbare ScrollBox-Zeilen und getrennte Datenanbieter.

Für AHT ist der größte nächste Nutzen: zuerst wirtschaftliche Aussagen und Datengüte korrigieren, anschließend die vorhandenen Funktionen über einen klaren Einkaufs- und Verkaufsablauf zugänglich machen. Zusätzliche Statistikspalten in jeder Hauptliste würden die Bedienung weiter erschweren.

## P0: Wirtschaftliche Aussagen und Datenvertrauen

### 1. Schnäppchen-Grenze verwendet unterschiedliche Einheiten

**Bestätigter Codefehler:** `Opportunities:Build()` berechnet die Einstellung als Anteil (`20 / 100 = 0,2`), aber den Rabatt als Prozentzahl (`(1 - aktuell / markt) * 100`). Danach wird `discount >= threshold` verglichen. Damit erfüllt bereits 0,2 % Rabatt die voreingestellte 20-%-Grenze. Die Aufnahme einer Kaufchance verlangt außerdem keinen positiven Nettoertrag.

Beispiel: Marktwert 1 Gold, Angebot 99 Silber. Der Rabatt beträgt 1 %, erfüllt die fehlerhafte Grenze und ergibt bei den eingestellten 5 % AH-Gebühr einen theoretischen Nettoverlust von 4 Silber. Ohne den optionalen Filter „Nur profitabel“ kann dieses Angebot als Kaufchance erscheinen.

**Maßnahme:** Eine einheitliche Prozentdarstellung verwenden. Kaufchancen erst bei erreichtem Rabatt, positivem Nettoertrag und gültiger Preisgrundlage aufnehmen. Mindestgewinn zusätzlich zur Prozentgrenze anbieten. NPC-Verwertung mit eigener Kosten-/Ertragsrechnung behandeln.

**Abnahme:** Bei 20-%-Grenze werden 19,9 % abgelehnt und 20 % akzeptiert; ein Angebot mit negativem Nettoertrag erscheint nicht als gewinnbringende Kaufchance. Grenzwerte und AH-Gebühr durch echte Berechnungstests absichern.

Quelle: [Opportunities.lua](/C:/Users/daosm/GitHub/all-repos/TWOW_AH_Trader/WOW4E_AH_Trader/Opportunities.lua:29), insbesondere Zeile 53.

### 2. Verkaufsplan bevorzugt die historische Orientierung

**Bestätigtes Verhalten:** `Poster:RecommendPrice()` beginnt mit `market or current`. Bei aktuellem Preis unter dem Marktwert wird fast der gesamte historische Preis beibehalten, statt sich am aktuellen Konkurrenzangebot zu orientieren.

Beispiele: Aktuell 20 Silber, Marktwert 1 Gold führt zu einer Empfehlung von 99 Silber 99 Kupfer. Aktuell 2 Gold, Marktwert 1 Gold führt zur Empfehlung 1 Gold. Beides widerspricht dem gewünschten Vorrang der aktuellen Marktlage.

**Maßnahme:** Letzten verfügbaren AH-Preis und dessen Alter als Ausgangspunkt zeigen; vor dem Einstellen aktuelle Angebote neu laden. Marktwert und Durchschnitt als Orientierung daneben zeigen. Preisstrategie, eigener Mindestpreis und Schutz vor auffälligen Einzelangeboten separat behandeln. Wenn ein Nutzer bewusst oberhalb der Konkurrenz anbieten möchte, muss das als gewählte Strategie erkennbar sein.

**Abnahme:** Preisvorschlag, Berechnungsquelle und Preisalter sind nachvollziehbar. Konkurrenzangebote können eingesehen werden. Fehlende aktuelle Angebote führen zu einer ausdrücklich historischen Schätzung statt zu einem scheinbar aktuellen Angebotspreis.

Quelle: [Poster.lua](/C:/Users/daosm/GitHub/all-repos/TWOW_AH_Trader/WOW4E_AH_Trader/Poster.lua:19).

### 3. Mindestmarge auch nach Live-Preisänderungen prüfen

**Befund:** `Production:Start()` prüft die Mindestmarge der Vorschau. Spätere Such- und Kaufprüfungen verwenden Material-Einzelpreisgrenzen, die standardmäßig bis zu 25 % über dem Referenzpreis liegen können. In den geprüften Pfaden wird daraus vor dem nächsten Kauf keine neue verbindliche Gesamtkalkulation des Auftrags abgeleitet.

Beispiel: Nettoverkauf 110 Silber, Materialkosten 100 Silber ergeben zunächst 10 % Gewinn auf die Kosten. Steigen die Materialien anschließend auf 125 Silber, liegt der Auftrag bei -12 %, obwohl eine Einzelpreisgrenze mit 25 % Spielraum den Kauf noch zulassen kann.

**Maßnahme:** Nach jeder Live-Prüfung und jedem abgeschlossenen Kauf Kosten, verbleibenden Goldbedarf und erwartete Auftragsmarge neu berechnen. Weitere Käufe pausieren, sobald Mindestmarge oder Gesamtbudget verletzt werden. Bereits gekaufte Materialien und deren tatsächliche Kosten bleiben im Auftrag sichtbar.

**Abnahme:** Ein ursprünglich profitabler Plan kauft nach einer ungünstigen Preisänderung nicht weiter, wenn die aktualisierte Gesamtmarge die Grenze unterschreitet. Die Oberfläche nennt den Grund und bietet eine erneute Preisprüfung.

Quellen: [Production.lua](/C:/Users/daosm/GitHub/all-repos/TWOW_AH_Trader/WOW4E_AH_Trader/Production.lua:239), [Buyer.lua](/C:/Users/daosm/GitHub/all-repos/TWOW_AH_Trader/WOW4E_AH_Trader/Buyer.lua:68).

### 4. Scanquelle, Genauigkeit und Alter getrennt führen

**Bestätigtes Verhalten:** Der breite Marktscan verarbeitet Browse-Zusammenfassungen und speichert `listingCount = 1` sowie `prices = { minPrice }`. `Store:RecordMarket()` berechnet daraus Median und Perzentile. Ein früherer detaillierter Datensatz kann dadurch eine Verteilung aus nur einer Mindestpreisprobe erhalten. Eine echte Listingzahl ist aus dieser Browse-Zusammenfassung nicht bekannt.

**Maßnahme:** Preisquelle und Erfassungsart speichern: Marktübersicht, detaillierte Listings, historischer Wert, gegebenenfalls Auctionator-Cache. Unbekannte Listingzahl als unbekannt anzeigen. Verteilungswerte mit eigenem Erfassungszeitpunkt erhalten und nur mit geeigneten Detaildaten aktualisieren. Kandidaten, beobachtete Items und Rezeptzutaten gezielt detailliert nachprüfen.

**Abnahme:** Ein Übersichts-Scan behauptet keine exakte Listingzahl und ersetzt keine detaillierte Preisverteilung durch eine einzelne Probe. Chancen zeigen Datenalter und Datenqualität. Ein abgebrochener Scan verändert nicht die Aussage, wann ein vollständiger Scan abgeschlossen wurde.

Quelle: [Scanner.lua](/C:/Users/daosm/GitHub/all-repos/TWOW_AH_Trader/WOW4E_AH_Trader/Scanner.lua:264).

### 5. Datenhaltbarkeit und Erstinstallation nachvollziehbar abschließen

Die kanonische Datenbankreferenz und die Sperre bei fehlenden SavedVariables verbessern die Absicherung. Die Änderung in 0.8.1 macht die erfolglose Prüfung verständlicher. Sie weist jedoch weder eine Wiederherstellung noch die Datenhaltbarkeit nach einem Neustart nach. Eine Erstinstallation landet ebenfalls im allgemeinen Dialog „Daten nicht geladen“.

**Maßnahme:** Klarer Erstinstallations-/Fehlerzustand mit verständlichen nächsten Schritten. Diagnose um Ladephase, Schema, Markt-/Rezeptanzahl und bestätigte Scanzeit ergänzen. Den bekannten Fehler durch einen echten Scan, `/reload`, reguläres Beenden und vollständigen Neustart abnehmen. Migrationen und Tabellenidentität mit synthetischen Daten prüfen.

**Abnahme:** Zwei konkrete Preise, Rezeptanzahl und aktive Aufträge bleiben über Reload und Neustart identisch. Eine fehlende oder beschädigte Datenbank erhält verständliche Rückmeldung. Die vorhandenen Source-Audits allein gelten dafür nicht als Nachweis.

Quellen: [Core.lua](/C:/Users/daosm/GitHub/all-repos/TWOW_AH_Trader/WOW4E_AH_Trader/Core.lua:134), [Store.lua](/C:/Users/daosm/GitHub/all-repos/TWOW_AH_Trader/WOW4E_AH_Trader/Store.lua:77).

## P1: Bedienung, Layout und große Datenmengen

| Bereich | Aktueller Befund | Empfohlene Verbesserung |
|---|---|---|
| Einkaufsplan | Materialbedarf und Status stehen überwiegend in einem langen Textblock; der Knopf wechselt zwischen Autokauf, Auslösen und Bestätigen. | Zutaten als Tabelle: Bedarf, Tasche, Bank, reserviert, fehlen, aktueller Stückpreis, Gesamtpreis. Darunter verbleibender Goldbedarf, erwarteter Gewinn und genau eine aktuelle nächste Aktion. |
| Mengenwahl | Vorschlag entspricht standardmäßig 10 % der aktuellen Angebotsmenge, begrenzt auf 20 Herstellvorgänge. Das misst keine Nachfrage und keine profitable Materialtiefe. | Zielmenge in fertigen Items eingeben. Anzahl Herstellvorgänge und resultierende Stückzahl separat anzeigen. Maximal sinnvolle Menge anhand verfügbarer Preisstufen, Mindestmarge und Budget berechnen; Nachfrage nur als unsichere Zusatzinformation verwenden. |
| Preis-/Gewinneinheiten | Rezeptkosten und Gewinn gelten für einen Herstellvorgang; aktueller Verkaufspreis gilt pro Ergebnisitem. | Tabellenwerte auf eine eindeutige Einheit normalisieren. „pro Stück“ und „für den gesamten Auftrag“ explizit unterscheiden. Gewinn/Kosten-Prozent als solche erklären. |
| Verkaufsdialog | Rohzahl „Preis/Stk (Kupfer)“, feste Dauer 2, kleine Vorschau; der Vorschauknopf liegt außerhalb des Fensters. | Gold-/Silber-/Kupfer-Eingabe, Forever-Laufzeitauswahl, sichtbarer Gesamterlös und Kaution. Aktuelle Angebote, historische Orientierung und eigenes Preisminimum im selben Arbeitsbereich. |
| Verkaufsbestand | `FindItem()` findet den ersten passenden Taschenstack; `BuildPlan()` begrenzt auf dessen Menge. | Gesamten Taschenbestand berücksichtigen und benötigte Einzelposts offen anzeigen. Keine stillschweigende Änderung der eingegebenen Zielmenge. |
| Aktionszugriff | Der beschriftete Detailknopf „Kaufplan“ öffnet zunächst einen weiteren Rezept-Aktionsdialog. | „Einkauf planen“ direkt zum Plan führen. „Verkauf vorbereiten“ als zweite direkte Aktion. Weitere Funktionen unter einem eindeutigen Aktionsmenü. |
| Detailbereich | Feste Höhe 118 Pixel, Textbreite 450; nur drei Zutaten werden zusammengefasst. | Rezeptdetails als scrollbare Materialtabelle oder vergrößerbare Detailfläche. Alle Zutaten ohne verpflichtenden Hover zugänglich machen. Das unabhängige Rezeptfenster erhalten. |
| Haupttabelle | Für jedes Ergebnis wird ein Frame mit mehreren Textfeldern erzeugt. Suche aktualisiert die Liste bei jeder Eingabe. | Sichtbare Zeilen wiederverwenden, etwa mit den vorhandenen WoW-ScrollBox-Funktionen. Suchupdates zusammenfassen und teure Berechnungen außerhalb der Darstellung halten. Scrollposition und Auswahl erhalten. |
| Filter | Sortierung vorhanden; Filter sind überwiegend zyklische Buttons und wenige feste Werte. | Dropdowns und numerische Bedingungen für Preis, Marge, Mindestgewinn, Alter und Verfügbarkeit. Aktive Bedingungen sichtbar anzeigen und mit einem Klick zurücksetzen. |
| Ansichtsmerker | Sortierung wird global geführt; Suche und Profitfilter werden im geprüften Layout-Speicherpfad nicht je Ansicht gespeichert. | Suche, Sortierung, Filter und optionale Spalten pro Ansicht speichern. Ein Berufwechsel soll keine vertraute Marktsortierung verändern. |
| WoW-Stil | Standardbuttons vorhanden; aktiver Reiter wird hauptsächlich über Schriftfarbe signalisiert. Itemzeilen haben keine eigene Item-Icon-Zelle. | Echte WoW-Reiter mit klarer aktiver Kontur, Item-Icons, Seltenheitsfarben und einheitlichen Geldanzeigen. Schwarze deckende Flächen beibehalten. |
| Fenstersystem | Viele Dialoge werden neu erzeugt und zentriert; kein erkennbarer zentraler Escape-Schließpfad. | Bestehende Dialoge wiederverwenden, Fensterpositionen sinnvoll merken und Escape zum obersten Fenster führen. Die Hauptfläche und das eigenständige Rezeptfenster bleiben verschiebbar. |
| Einstellungen | „Mehr“ enthält Ruf und Diagnose; wichtige Wirtschaftsparameter liegen als Datenbankwerte vor. | Kleines Einstellungsfenster für Mindestmarge, Budget/Preisgrenzen, Datenalter und Verkaufsstrategie. Historienparameter unter „Erweitert“. Fehlermeldungen in verständliche Sprache übersetzen. |

**Konkreter Layoutfehler im Postdialog:** Fensterbreite 430. Preislabel beginnt bei x=190 und ist 108 breit; die Preiseingabe beginnt nach 8 Pixeln Abstand und ist 100 breit. Der Vorschauknopf beginnt danach bei x=414 und endet bei x=514. Damit liegen 84 Pixel außerhalb der Fensterbreite. Quelle: [UI.lua](/C:/Users/daosm/GitHub/all-repos/TWOW_AH_Trader/WOW4E_AH_Trader/UI.lua:2577).

**Konkreter Skalierungsbefund:** Die Spaltenbreiten ergeben jetzt korrekt 700 Pixel. Beim Vergrößern des Hauptfensters werden sie im geprüften Layoutpfad jedoch nicht an die verfügbare Breite angepasst. Quelle: [UI.lua](/C:/Users/daosm/GitHub/all-repos/TWOW_AH_Trader/WOW4E_AH_Trader/UI.lua:1311).

**Begriffe korrigieren:** „Trend“ ist im Markt aktuell die Abweichung des letzten Preises vom historischen Marktwert. Die Veränderung gegenüber dem vorherigen Scan ist ein anderer Wert. Daher „Abweichung“ und „Preisänderung“ trennen. „Postplan“ durch „Verkauf vorbereiten“, „Deposit“ durch „Kaution“ und „Autokauf starten“ durch den tatsächlich folgenden Arbeitsschritt ersetzen. Eine Verkaufschance gegenüber NPC-Wert ist ein möglicher Mehrerlös gegenüber dem Händler, kein belegter Gewinn gegenüber dem eigenen Einkaufspreis.

## P2: Zusätzliche Funktionen mit nachvollziehbarem Mehrwert

1. **Beobachtungs- und Einkaufslisten:** Mehrere benannte Listen, letzte Suchen und Suchvervollständigung wie bei Auctionator. Ein Rezept oder mehrere Aufträge erzeugen eine zusammengefasste Einkaufsliste mit reservierten Mengen und Einzel-/Gesamtpreislimits.
2. **Verkaufsarbeitsplatz:** Taschenliste, aktuelle Konkurrenz, Preisverlauf und eigene Postinghistorie. Eigene Auktionen und Unterbietungen später ergänzen. Postinghistorie nicht als Nachweis eines tatsächlichen Verkaufs ausgeben.
3. **Echte Verlaufsgrafik im Detail:** 7/30 Tage, Preisänderung, Preisquelle und Zahl unabhängiger Beobachtungstage. Hauptlisten behalten wenige klare Entscheidungsspalten. Angebotsmenge und Listingzahl sind keine gemessene Verkaufsnachfrage.
4. **Preisqualität und Ausreißer:** Alter, unterschiedliche Beobachtungstage und breite Preisverteilung in die Vertrauensanzeige einbeziehen. Die derzeitige Prozentbewertung aus Scan-/Listingzahlen als Datenabdeckung erklären, nicht als statistische Erfolgswahrscheinlichkeit.
5. **Daten nach Marktpool trennen:** Auctionator trennt seine Preisdaten nach Realm. AHT führt Markt und Historie im geprüften Schema accountweit ohne Realm-Unterteilung. Falls der Forever-Client mehrere getrennte AH-Märkte anbietet, müssen deren Werte getrennt bleiben; verbundene Märkte müssen anhand des tatsächlichen Forever-Vertrags zusammengeführt werden.
6. **Optionaler Auctionator-Adapter:** Die installierte API v1 bietet Preisabfrage, Preisalter und Einkaufslisten. Ein kleiner optionaler Adapter kann fehlende Orientierungswerte bereitstellen und Einkaufsmengen als Liste übergeben. Quelle und Alter sichtbar halten; fremde Cachewerte nicht bei jedem Login als neuen eigenen Scan in die Historie schreiben. AHT bleibt ohne Auctionator benutzbar. Such- und Transaktionskonflikte bei gleichzeitig aktiven Addons gezielt im Client prüfen.
7. **Scanstrategie prüfen:** Auctionator enthält einen Replikat-Scanner mit Fortschrittsmeldungen. Ob dieser Pfad im aktuellen Forever-Client tatsächlich verfügbar und geeignet ist, muss zuerst dort geprüft werden. Die vorhandene AHT-Browse-Grenze von 100 Seiten muss sichtbar bleiben. Übersichts-Scan und Detailprüfung ausgewählter Kandidaten sind ein sinnvoller erster Ausbau.

## Was konkret aus Auctionator übernommen werden sollte

- Tabellen mit wiederverwendeten sichtbaren Zeilen, sortierbaren und optionalen Spalten: `Source/Components/ResultsListing/Mixins/ResultsListing.lua`.
- Geldanzeige als eigene Zelle: `Source/Components/ResultsListing/Mixins/PriceCell.lua`.
- Einkaufsmenge, gestaffelte Angebotskosten und Warnung bei stark auseinanderliegenden Preisstufen: `Source_ModernAH/Tabs/Buying/Commodity/Mixins/Main.lua`.
- Finale Bestätigung mit Menge, Stückpreis und Gesamtsumme: `Source_ModernAH/Tabs/Buying/Commodity/Mixins/Dialogs.lua`.
- Verkaufsbereich mit Taschenliste und getrennten Ansichten für aktuelle Preise, Preisverlauf und eigene Historie: `Source_ModernAH/Tabs/Selling/Frames/Main.xml`.
- Wiederverwendbare Einkaufslisten und letzte Suchen: `Source/Tabs/Shopping/Mixins/Main.lua` und `SearchOptions.lua`.
- Forever-Anpassung: `Source_Forever/Constants.lua` enthält 2/8/24 Stunden als Laufzeitanzeige; die Forever-Preispfade erlauben Kupferwerte. Daueranzeigen und tatsächliche API-Werte getrennt behandeln und im Forever-Client abnehmen.

Alle genannten Auctionator-Pfade liegen unter `C:/Program Files (x86)/World of Warcraft/_classic_beta_/Interface/AddOns/Auctionator/`.

## Empfohlene Umsetzung in drei Paketen

**Paket 1 – verlässliche Entscheidungen:** Schnäppchen-Grenze, aktueller Verkaufsbezug, laufende Mindestmargenprüfung und Herkunft/Genauigkeit der Scandaten korrigieren. Datenhaltbarkeit nach Reload und Neustart nachweisen. Gezielte Verhaltenstests statt weiterer Prüfungen auf bloß vorhandene Quelltextfragmente.

**Paket 2 – klarer Einkauf und Verkauf:** Materialtabelle, Zielmenge in fertigen Items, direkte Planaktionen, Gold-/Silber-/Kupfer-Eingaben, Forever-Dauer, verständliche Statusmeldungen und funktionierende Fenstergeometrie. Alle Zutaten und aktuellen Listings ohne Tastenkürzel erreichbar.

**Paket 3 – große Märkte und Komfort:** Zeilenwiederverwendung, gespeicherte Filter/Spalten je Ansicht, Einkaufslisten, Verlaufsgrafik und optionaler Auctionator-Adapter. Weitere Auktionsverwaltung erst danach.

Die Abnahme erfolgt zusätzlich zu den bestehenden Audits im Forever-Client: zwei UI-Skalierungen, lange Itemnamen, Rezept mit mehr als drei Zutaten, Rezept mit mehreren Ergebnisitems, viele Marktresultate, geänderte Preise während eines Einkaufs, Kaufablehnung, AH-Schließen, Reload und vollständiger Neustart. Das Rezeptfenster bleibt eigenständig; alle AHT-Flächen bleiben vollständig schwarz und deckend.
