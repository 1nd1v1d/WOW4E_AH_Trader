# WoW4E AH Trader

Forever-Port des Turtle-WoW-Addons `TWOW_AH_Trader`.

## Installation

Den Ordner `WOW4E_AH_Trader` nach folgendem Pfad kopieren:

`World of Warcraft\_classic_beta_\Interface\AddOns\WOW4E_AH_Trader\`

Die aktuelle Beta verwendet Interface `16001` für Version 1.60.1. Bei einem neuen Beta-Build muss der Wert mit `/dump select(4, GetBuildInfo())` geprüft werden.

## Befehle

- `/aht` – Hauptfenster öffnen
- `/aht scan` – Rezept- und Materialpreise aktualisieren
- `/aht recipes` – gelernte Rezepte ausgeben
- `/aht mats add <Item-Link>` – Material hinzufügen
- `/aht mats remove <Item-Link>` – Material entfernen
- `/aht transmute` – Transmutationsmargen ausgeben
- `/aht orders` – aktive Herstellungsaufträge und Materialreservierungen anzeigen
- `/aht chancen` – unterbewertete AH-Angebote mit Netto-Gewinn, ROI und Liquidität anzeigen
- `/aht ruf` – Runenstoffspenden bis Ehrfürchtig für die beobachtete Hauptstadtfraktion ausgeben
- `/aht stop` – laufende Operationen abbrechen
- `/aht debug` – Runtime- und API-Diagnose
- `/aht reset` – gespeicherte Marktdaten löschen

## Bedienoberfläche

Die Hauptnavigation ist auf die vier täglichen Arbeitsbereiche `Herstellen`, `Markt`, `Aufträge` und `Chancen` reduziert. `Ruf` und `Diagnose` werden über `Mehr` geöffnet. Die Suche filtert sichtbare Rezepte, Materialien, Chancen und Aufträge; der Profitfilter blendet nicht profitable Ergebnisse aus. Tabellenüberschriften sind anklickbar und wechseln zwischen auf- und absteigender Sortierung. Fensterposition, Größe, Ansicht und Sortierspalte werden in den SavedVariables gespeichert.

Die Listen verwenden einen dynamischen Zeilenpool. Dadurch bleiben auch mehr als 24 Rezepte, Materialien oder Chancen vollständig sichtbar und scrollbar. Ein Klick auf ein Material öffnet Aktionen für einen Live-Scan oder das Entfernen aus der Überwachung. Dialoge kennzeichnen Mengen und Preise explizit; Preise im Postplan werden weiterhin als Kupfer pro Stück eingegeben. Alle Rezept-, Kauf-, Auftrags- und Postdialoge lassen sich an ihrer Titelleiste verschieben; beim Wechsel vom Rezeptaktionsfenster zum Postplan wird das Vorgängerfenster ausgeblendet.

`Strg+Linksklick` auf ein herstellbares Ergebnis öffnet im geöffneten Auktionshaus den Reiter `AHT Rezept`. Dort werden Ergebnis- und Material-Listings parallel geladen. Die Materialzeilen zeigen die Menge pro Herstellung, die Gesamtanforderung, Taschen-/Bankbestand, den Restbedarf und eine kaufbare Planung auf Basis der günstigsten aktuellen Listings. Die Schaltfläche `Kaufen` prüft die Listings unmittelbar vor dem Kauf erneut; die finale Commodity-Preisbestätigung bleibt sichtbar und benutzerbestätigt. Der Reiter kann über `AHT Rezept` neben dem `AH Trader`-Button erneut geöffnet werden.

SavedVariables werden beim Addonstart defensiv validiert. Der gespeicherte Berufskatalog, Rezeptindex und die Rezeptdaten werden sofort geladen. Ein vorübergehend leerer `TRADE_SKILL_LIST_UPDATE`-Event darf den gespeicherten Rezeptkatalog nicht überschreiben; Berufsevents führen ausschließlich einen Delta-Upsert für neue oder geänderte Rezept-IDs aus. Die alten Rezepte bleiben erhalten, bis ein gültiger Datensatz ergänzt oder aktualisiert wurde; Berufe müssen nach einem Neustart nicht erneut geöffnet werden.

## Lokale Prüfung

Vor dem Kopieren in den Client kann der statische Audit aus dem Repository ausgeführt werden:

`.\WOW4E_AH_Trader\Tests\SourceAudit.ps1`

Er prüft TOC-Dateien, moderne `C_AuctionHouse`-Verträge und den Ausschluss der alten Legacy-AH-Symbole.

Die Lua-Dateien können zusätzlich ohne externe Pakete auf ausgeglichene Blöcke und Klammern geprüft werden:

`node .\WOW4E_AH_Trader\Tests\lua-balance.mjs`

## Ruf- und Runenstofffunktion

Beim Hovern über die Rufleiste ergänzt das Addon den vorhandenen Tooltip für Stormwind, Ironforge, Darnassus, Gnomeregan Exiles, Orgrimmar, Thunder Bluff, Undercity und Darkspear Trolls. Angezeigt werden fehlender Ruf, benötigte 20er-Spenden, Runenstoffmenge und — nach einem Scan — die geschätzten AH-Kosten.

Die Funktion nutzt bevorzugt `C_Reputation.GetWatchedFactionData()` und fällt auf `GetWatchedFactionInfo()` zurück. Runenstoff wird über Item-ID `14047` identifiziert und beim normalen `/aht scan` automatisch als Scan-Ziel ergänzt.

## Sicherheitsmodell

Alle AH-Anfragen laufen über `AuctionHouse.lua`. Käufe und Posts benötigen eine sichtbare Bestätigung. Commodity-Käufe haben zusätzlich eine zweite Bestätigung nach `COMMODITY_PRICE_UPDATED`, weil der Client den aktuellen Gesamtpreis erst nach dem Start der Preisabfrage liefert. Preis, Menge, Bestand und Gold werden vor der Aktion erneut geprüft. Bei AH-Schließen, Timeout oder Throttle wird die Operation abgebrochen oder kontrolliert wiederholt.

Die Laufzeitdauer wird intern als Modern-AH-Enum `1/2/3` geführt (12/24/48 Stunden). Dadurch werden Deposit-Berechnung und Posting nicht mit den sichtbaren Stundenwerten verwechselt.

## Marktwert und Chancen

Ein Scan speichert neben dem niedrigsten Stückpreis auch die Preisverteilung der sichtbaren Angebote. Aus Median, getrimmtem Mittelwert, P25/P75-Preis und Markttiefe wird ein robuster Marktwert gebildet. Mehrere Scans desselben Tages werden zu einem Tagessnapshot zusammengefasst; ältere Tage werden mit einer konfigurierbaren Halbwertszeit abgewertet. In der Rezeptansicht ist der letzte Scan der aktuelle Verkaufswert und damit die primäre Grundlage für Gewinn und Marge. Der robuste Marktwert bleibt als Orientierung sichtbar und zeigt, ob der aktuelle Preis über oder unter dem historischen Niveau liegt; in der Chancenanalyse dient er weiterhin als Vergleichswert.

Die Ansicht `Chancen` filtert Angebote erst nach einer Mindesthistorie, berücksichtigt AH-Gebühr und zeigt Rabatt, Netto-Gewinn, ROI, Menge, Listings und Vertrauensniveau. Ein NPC-Vergleich wird nur angezeigt, wenn der Forever-Client den Händlerverkaufspreis bereits kennt. Das Addon kauft aus dieser Ansicht nicht automatisch; jede Kaufaktion bleibt an den sichtbaren Produktionsauftrag beziehungsweise die Benutzerbestätigung gebunden.

## Herstellungsplanung und AutoBuy

Die Funktion gilt für alle über `C_TradeSkillUI` erkannten Herstellungsrezepte, nicht nur für Alchemie. Beim Öffnen eines Berufsfensters werden dessen gelernte Rezepte in den berufsübergreifenden Katalog übernommen.

Ein Herstellungsauftrag speichert die gewünschte Anzahl, den vollständigen Materialbedarf, den zugeteilten Taschen-/Bankbestand und jeden tatsächlich abgeschlossenen AH-Kauf. Der vollständige Bedarf bleibt bis `Hergestellt` oder `Stornieren` für diesen Auftrag reserviert. Dadurch kann ein zweiter Auftrag bereits gekaufte oder anderweitig eingeplante Zutaten nicht versehentlich erneut verwenden.

Die Preisvorschau scannt jede fehlende Zutat über die zentrale Forever-AH-Queue. Die angezeigte Marge bewertet vorhandene Materialien weiterhin zu ihrem Marktwert; `Neuer Goldbedarf` zeigt dagegen nur die noch zu kaufenden Mengen. Vor jedem Kauf werden Preis und Verfügbarkeit live revalidiert. Commodity-Preise benötigen die vom Forever-Client vorgesehene finale Benutzerbestätigung.

Bankbestände werden charakterbezogen gespeichert und beim Öffnen der persönlichen Bank aktualisiert. Die Reagenzienbank wird über den Forever-ItemCount-Vertrag einbezogen. Ein unbekannter Banksnapshot wird sichtbar als `?` dargestellt und nicht als bestätigter Nullbestand ausgegeben.

## Status

Beta-Implementierung. Vor dem ersten Goldtest müssen im Forever-Client insbesondere Rezeptdaten, Commodity-Kaufbestätigung und Post-Events geprüft werden. Die erste Verifikation sollte mit einem kleinen, unkritischen Item und niedriger Menge erfolgen.
