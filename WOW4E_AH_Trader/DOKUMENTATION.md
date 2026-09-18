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
- `/aht ruf` – Runenstoffspenden bis Ehrfürchtig für die beobachtete Hauptstadtfraktion ausgeben
- `/aht stop` – laufende Operationen abbrechen
- `/aht debug` – Runtime- und API-Diagnose
- `/aht reset` – gespeicherte Marktdaten löschen

## Lokale Prüfung

Vor dem Kopieren in den Client kann der statische Audit aus dem Repository ausgeführt werden:

`.\WOW4E_AH_Trader\Tests\SourceAudit.ps1`

Er prüft TOC-Dateien, moderne `C_AuctionHouse`-Verträge und den Ausschluss der alten Legacy-AH-Symbole.

## Ruf- und Runenstofffunktion

Beim Hovern über die Rufleiste ergänzt das Addon den vorhandenen Tooltip für Stormwind, Ironforge, Darnassus, Gnomeregan Exiles, Orgrimmar, Thunder Bluff, Undercity und Darkspear Trolls. Angezeigt werden fehlender Ruf, benötigte 20er-Spenden, Runenstoffmenge und — nach einem Scan — die geschätzten AH-Kosten.

Die Funktion nutzt bevorzugt `C_Reputation.GetWatchedFactionData()` und fällt auf `GetWatchedFactionInfo()` zurück. Runenstoff wird über Item-ID `14047` identifiziert und beim normalen `/aht scan` automatisch als Scan-Ziel ergänzt.

## Sicherheitsmodell

Alle AH-Anfragen laufen über `AuctionHouse.lua`. Käufe und Posts benötigen eine sichtbare Bestätigung. Commodity-Käufe haben zusätzlich eine zweite Bestätigung nach `COMMODITY_PRICE_UPDATED`, weil der Client den aktuellen Gesamtpreis erst nach dem Start der Preisabfrage liefert. Preis, Menge, Bestand und Gold werden vor der Aktion erneut geprüft. Bei AH-Schließen, Timeout oder Throttle wird die Operation abgebrochen oder kontrolliert wiederholt.

Die Laufzeitdauer wird intern als Modern-AH-Enum `1/2/3` geführt (12/24/48 Stunden). Dadurch werden Deposit-Berechnung und Posting nicht mit den sichtbaren Stundenwerten verwechselt.

## Status

Beta-Implementierung. Vor dem ersten Goldtest müssen im Forever-Client insbesondere Rezeptdaten, Commodity-Kaufbestätigung und Post-Events geprüft werden. Die erste Verifikation sollte mit einem kleinen, unkritischen Item und niedriger Menge erfolgen.
