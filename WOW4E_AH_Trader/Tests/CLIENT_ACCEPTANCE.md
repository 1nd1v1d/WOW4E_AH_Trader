# 0.9.0-beta: Umsetzung und Client-Abnahme

Alle P0/P1-Implementierungspunkte und die P2-Komfortfunktionen aus der Auctionator-Bewertung sind enthalten. Eigene Auktionen/Unterbietungsverwaltung waren dort ausdrücklich als späterer Ausbau vorgesehen; sie sind nicht Bestandteil dieses Releases. Kaufbestätigungen werden nicht umgangen.

## Automatisch geprüft

21 produktive Lua-Dateien werden mit Lua 5.1 kompiliert. Verhaltenstests prüfen Prozent-/Gewinngrenzen, Datenherkunft, unabhängige Tage, aktuellen Verkaufsbezug, Mengenrundung, Reservierungen, ganze Stapel, Gesamtmarge/Budget, API-Ablehnung, vollständige Commodity-Ereigniskette, Fensterwiederverwendung, sechs Zutaten, 10.000 Ergebnisse, Filterzustände, Listen, Marktpooltrennung, optionalen Cache und Replikat-Fallback. Ein frischer Interpreter lädt neu serialisierte SavedVariables; Preis, Rezepte, Listen, Postinghistorie und Aufträge bleiben erhalten.

Das ist keine Behauptung, dass Schutzregeln, Rendermethoden oder Datei-Schreibverhalten im laufenden Forever-Client bereits abgenommen wurden. Die Mocks prüfen Geschäftslogik und Zustandsübergänge, nicht das tatsächliche Spiel.

## Manuelle Abnahme im Forever-Client

1. Spiel regulär beenden. Erst danach bei Bedarf SavedVariables und `.bak` zusätzlich sichern. Mit 0.9.0 vollständig neu starten, nicht nur `/reload`. Version und Ladephase unter Mehr → Diagnose prüfen.
2. Notiere zwei konkrete Scanpreise, Rezeptanzahl und einen Auftrag. `/reload`, danach reguläres Beenden und vollständiger Neustart: identische Daten prüfen. Vorhandene Daten nicht mit „Neue Datenbank“ ersetzen. Die Migration startet beim Laden; sie liest keine beliebigen Dateien nach.
3. UI bei zwei Skalen testen: lange Namen, Münzbeträge, alle schwarzen Hintergründe, Drag/Clamping, native Reiter, Escape nur für oberstes Fenster. Rezeptfenster bleibt unabhängig; Schließen bringt AHT zurück.
4. Rezept mit sechs Zutaten und mehrfacher Ausgabe: Zielmenge fünf bei Ausgabe drei → zwei Vorgänge, sechs Ergebnisitems. Alle Zutaten und Stück-/Auftragswerte müssen zugänglich sein.
5. AH-Übersicht: Quelle Übersicht, Listingzahl unbekannt, vorhandenes P25/P75 mit eigenem Datum unverändert. Nachfolgende Details müssen Preisstaffeln und Listingzahlen aktualisieren. Stop/Seitenlimit darf den Zeitpunkt der letzten bestätigten vollständigen Übersicht nicht verfälschen.
6. Kaufen: kleines Budget, Mindestmarge und geringe Mengen verwenden. Erst prüfen, dann vorbereiten, dann per Spieleraktion auslösen/bestätigen. Vor Serverbestätigung keine gekauften Mengen buchen. Preissteigerung, Kaufablehnung, AH-Schließen, Dialog-Schließen und Timeout testen.
7. Zwei Aufträge mit gleicher Zutat: vorhandener Bestand wird nicht doppelt zugeordnet; gekaufte Mengen und echte Kosten bleiben gespeichert. Bankwerte sind gespeicherte Beobachtungen; bei verändertem Bankbestand Bank erneut öffnen. AH-Post abholen, falls gekauftes Material noch nicht in den Taschen liegt.
8. Verkaufen: 7 Items in Stapeln 3+5, aktuelle Konkurrenz prüfen. Anzeige: Ziel 7, zwei Posts, erster Post 3, danach noch 4. Jeder Einzelpost braucht eine eigene Spieleraktion. Item-Auktionen verwenden Gesamtbuyout, Commodities Stückpreis. 2/8/24 Stunden und Kaution im echten Client gegenprüfen.
9. Ansichtswechsel/Neustart: Suche, Spaltenfilter, Sortierung, optionale Spalten und Auswahl soweit noch vorhanden behalten. Rechtsklick auf Überschrift öffnet den Filter; numerische Bedingungen löschen ist reversibel.
10. Auctionator optional: Preisalter in Tagen, kein eigener Verlaufseintrag durch Cache, Export nur in `AHT: <Name>`. Nicht parallel handeln/scannen. Ereigniszuordnung bei gleichzeitig geöffneten Addons separat testen; gemeinsame globale Commodity-Ereignisse erlauben keine sichere Transaktionssperre fremder Addons.
11. Replikat nur nach bewusstem Klick testen. API-Präsenz ist kein Nachweis der Forever-Kompatibilität. Ablehnung/Timeout → Browse-Fallback; Varianten, Cache-Ladezustand und Vollständigkeit müssen vor produktiver Nutzung geprüft werden.
12. Getrennte Forever-Märkte mit verschiedenen Charakteren prüfen. Es wird nach Region und dem vom Client gemeldeten verbundenen Realm-Set getrennt; historische Daten unbekannter Herkunft bleiben entsprechend gekennzeichnet. Fraktions-/Realm-Sonderregeln sind nicht aus Retail abgeleitet.

## Nicht versprochen

Historische Marktwerte und Angebotsmengen sind keine sichere Nachfrage oder Verkaufsgarantie. Postinghistorie protokolliert erstellte Auktionen, nicht tatsächlich verkaufte Items. Datenabdeckung ist keine Gewinnwahrscheinlichkeit. Ein erfolgreiches Deployment ist kein realer Reload-/Neustartnachweis.
