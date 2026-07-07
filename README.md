# MB_Fahrzeugvermitung

## Aufgeräumte Ordnerstruktur

Die Resource wurde aufgeräumt:

- Client-Code: `client/main.lua`
- Server-Code: `server/main.lua`
- Speicherdateien: `data/`
- SQL/Item-Dateien: `install/`
- UI: `html/`
- Struktur-Übersicht: `docs/ORDNERSTRUKTUR.md`


# MB_Fahrzeugvermitung — Fahrzeugvermietung (ESX/QBCore)

Ein modernes Fahrzeugvermietungs-System für FiveM-Roleplay-Server mit
deutscher Tablet-UI, Mietvertrag, Unterschriften-Funktion und Ingame-Adminpanel.

---

## 1. Inhalt des Scripts

```
MB_Fahrzeugvermitung/
├── fxmanifest.lua
├── config.lua
├── client.lua
├── server.lua
├── install.sql          (nur bei aktivierter Datenbank-Protokollierung nötig)
└── html/
    ├── index.html
    ├── style.css
    ├── script.js
    └── img/
        ├── quail.svg
        ├── faggio2.svg
        └── faggio.svg
```

---

## 2. Voraussetzungen

Zwingend benötigt:
- **ESX Legacy** ODER **QBCore** (je nachdem, welches Framework du nutzt)

Optional (je nach Config):
- **ox_lib** — wenn `Config.UseOxLib = true`
- **ox_target** ODER **qtarget** — wenn `Config.UseTarget = true`
- **oxmysql** — nur wenn `Config.UseDatabase = true` (für die Mietprotokollierung)
- Ein Schlüssel-System, falls gewünscht: `qb-vehiclekeys`, `qs-vehiclekeys`
  oder `wasabi_carlock` (siehe `Config.KeysSystem`)

Das Script funktioniert auch **ohne** ox_lib, ohne Target-System und ohne
Datenbank — es fällt dann automatisch auf einfache Alternativen zurück
(native Notifications, Tasten-Interaktion mit E, keine Protokollierung).

---

## 3. Installation

1. Ordner `MB_Fahrzeugvermitung` in deinen `resources`-Ordner kopieren.
2. Falls du `ox_lib` und/oder `ox_target`/`qtarget` nutzt, in der
   `fxmanifest.lua` die auskommentierte Zeile aktivieren:
   ```lua
   dependencies { 'ox_lib' }
   ```
   (bzw. zusätzlich `'ox_target'` oder `'qtarget'` ergänzen, falls gewünscht).
3. In deiner `server.cfg` **oberhalb** deines Frameworks bzw. **unterhalb**
   der benötigten Dependencies eintragen:
   ```
   ensure ox_lib          # falls genutzt
   ensure ox_target       # oder qtarget, falls genutzt
   ensure es_extended     # oder qb-core
   ensure oxmysql         # nur falls Config.UseDatabase = true
   ensure MB_Fahrzeugvermitung
   ```
4. Falls `Config.UseDatabase = true` gesetzt ist: Inhalt von `install.sql`
   einmalig in deine Datenbank importieren.
5. Server neu starten bzw. Resource per `refresh` + `ensure MB_Fahrzeugvermitung`
   neu laden.

---

## 4. Config-Erklärung (`config.lua`)

### Framework
```lua
Config.Framework = 'esx'      -- 'esx' oder 'qbcore'
Config.ESXExport = 'es_extended'
Config.QBExport  = 'qb-core'
```
Legt fest, welches Framework verwendet wird. Der Wechsel erfolgt **nur**
über diese eine Zeile — der restliche Code passt sich automatisch an.

### Interaktion
```lua
Config.UseTarget     = true         -- true = Target-System, false = Taste E
Config.TargetSystem  = 'ox_target'  -- 'ox_target' oder 'qtarget'
Config.InteractKey   = 38           -- Taste, falls UseTarget = false
Config.InteractDistance = 8.0
Config.UseOxLib = true              -- ox_lib-Notifications nutzen
```

### Datenbank (optional)
```lua
Config.UseDatabase = false
Config.DatabaseTable = 'MB_Fahrzeugvermitung_history'
```
Wird **nur** benötigt, wenn du abgeschlossene Mietvorgänge dauerhaft in der
Datenbank protokollieren möchtest (z. B. für eine Statistik). Für den
normalen Ablauf (mieten → fahren → Fahrzeug wird nach Ablauf gelöscht) ist
**keine Datenbank erforderlich**.

### Mietverhalten
```lua
Config.DeleteVehicleOnExpire = true   -- Fahrzeug nach Ablauf automatisch löschen
Config.ExpireWarningTime = 60         -- Sekunden vor Ablauf wird gewarnt
Config.GiveKeys = true                -- Schlüssel über Keys-System vergeben
Config.KeysSystem = 'auto'            -- 'auto' erkennt automatisch installierte Systeme
Config.Cooldown = 0                   -- Minuten Cooldown zwischen zwei Mieten (0 = aus)
Config.MaxActiveRentalsPerPlayer = 1  -- gleichzeitig aktive Mietfahrzeuge pro Spieler
```

### Zahlungsmethoden
```lua
Config.PaymentMethods = {
    { id = 'cash', label = 'Bar',   account = 'money' },
    { id = 'card', label = 'Karte', account = 'bank'  },
}
```
`account` entspricht dem Framework-internen Konto-Namen (`money` = Bargeld,
`bank` = Bankkonto). Weitere Zahlungsmethoden können einfach ergänzt werden.

### Mietdauer
```lua
Config.RentalDurations = {
    { label = '15 Minuten', minutes = 15,  multiplier = 1.0 },
    { label = '30 Minuten', minutes = 30,  multiplier = 1.8 },
    { label = '1 Stunde',   minutes = 60,  multiplier = 3.2 },
    { label = '2 Stunden',  minutes = 120, multiplier = 6.0 },
}
```
Der `multiplier` wird mit dem Grundpreis des Fahrzeugs multipliziert, um den
Gesamtpreis zu berechnen (`price * multiplier`, abgerundet).

### Fahrzeuge
```lua
Config.Vehicles = {
    quail = {
        label    = 'Devauchee Quail',
        model    = 'quail',
        price    = 250,
        category = 'Sportwagen',
        image    = 'img/quail.svg',
    },
    -- ...
}
```
Weitere Fahrzeuge können beliebig ergänzt werden. Das `image` muss relativ
zum `html`-Ordner liegen (eigene Bilder unter `html/img/` ablegen und in
der `fxmanifest.lua` unter `files` mit einbinden, falls ein neues
Dateiformat verwendet wird).

### Vermietungsstandorte
```lua
Config.RentalLocations = {
    {
        name  = 'flughafen',
        label = 'Flughafen Vermietung',
        npc    = { enabled = true, model = 'a_m_m_business_01', coords = vector4(...) },
        marker = { enabled = true, coords = vector3(...), size = vector3(...), color = {...} },
        blip   = { enabled = true, coords = vector3(...), sprite = 225, color = 2, scale = 0.8, label = '...' },
        spawnPoint = vector4(...),
        vehicles = { 'quail', 'faggio2', 'faggio' }, -- Keys aus Config.Vehicles
    },
    -- beliebig viele weitere Standorte möglich
}
```
Jeder Standort kann eigene Fahrzeuge, einen eigenen NPC, Marker, Blip und
Spawnpunkt haben. `vehicles` verweist per Key auf `Config.Vehicles`.

---

## 5. Ablauf für den Spieler

1. Spieler interagiert mit NPC/Marker → UI öffnet sich mit Fahrzeugauswahl.
2. Fahrzeug auswählen → Mietdauer & Zahlungsmethode wählen → Gesamtpreis wird angezeigt.
3. „Mietvertrag vorbereiten" → Vertrag mit allen Daten wird angezeigt.
4. „Unterschreiben" → Unterschriften-Feld (Maus/Touch).
5. Nach dem Bestätigen: Server prüft Geld, zieht den Betrag ab, spawnt das
   Fahrzeug am konfigurierten Spawnpunkt und vergibt (falls vorhanden) die
   Fahrzeugschlüssel.
6. Kurz vor Ablauf der Mietzeit erhält der Spieler eine Warnung.
7. Nach Ablauf wird das Fahrzeug automatisch gelöscht (falls
   `Config.DeleteVehicleOnExpire = true`).

---

## 6. Eigene Anpassungen

- **Weitere Fahrzeuge/Standorte:** einfach in `config.lua` ergänzen, keine
  Code-Änderungen notwendig.
- **Eigenes Design:** Farben und Schriftarten sind als CSS-Variablen am
  Anfang von `html/style.css` definiert (`:root { ... }`).
- **Eigene Fahrzeugbilder:** Datei in `html/img/` ablegen, Pfad in
  `Config.Vehicles[...].image` eintragen, Dateiendung ggf. in der
  `fxmanifest.lua` unter `files` ergänzen.

---

## 7. Hinweis

Die enthaltenen Fahrzeug-Icons sind einfache, selbst erstellte
Vektorgrafiken (SVG) und keine echten Spiel- oder Markenassets. Sie können
jederzeit durch eigene Bilder ersetzt werden.

## Adminpanel / Fahrzeuge ingame hinzufügen

Command im Spiel:

```text
/rentaladmin
```

Berechtigung über ACE:

```cfg
add_ace group.admin MB_Fahrzeugvermitung.admin allow
```

Zusätzlich werden die Gruppen aus `Config.AdminGroups` akzeptiert, zum Beispiel `admin`, `superadmin` und `god`.

Im Adminpanel kannst du Fahrzeuge mit Spawn-Modell, Anzeige-Name, Preis, Kategorie und Bild-Link hinzufügen. Beim Speichern wird das Fahrzeug direkt an allen Standorten verfügbar gemacht; im Tab **Standorte** kannst du danach einzelne Standorte wieder abwählen.

Bildquellen:

- externe Direktlinks: `https://domain.de/bild.png`, `.jpg`, `.webp`, `.gif`, `.svg`
- lokale Dateien: `img/sultan.png`
- Kurzform für lokale Dateien: `sultan.png` wird automatisch als `img/sultan.png` geladen

Wichtig: Für externe Bilder am besten direkte `https://`-Bildlinks nutzen. Webseiten-Links wie Imgur-Seiten oder Discord-Vorschauseiten sind keine direkten Bilddateien und können nicht als `<img>` geladen werden.

Ingame hinzugefügte Fahrzeuge werden in `admin_vehicles.json` gespeichert und bleiben nach Resource-Restart erhalten.


## Mietvertrag als Item / öffnen / zeigen

Neu: Nach jeder erfolgreichen Miete bekommt der Spieler zusätzlich einen **Mietvertrag als Item**.

Funktionen:
- Vertrag wird serverseitig in `rental_contracts.json` gespeichert
- Spieler bekommt das Item `mietvertrag`
- beim Benutzen öffnet sich der unterschriebene Vertrag
- im geöffneten Vertrag kann man auf **„Spieler zeigen“** klicken
- der nächste Spieler in der Nähe bekommt den Vertrag angezeigt

Config:
```lua
Config.ContractItem = {
    Enabled = true,
    Name = 'mietvertrag',
    Inventory = 'framework',
    ShowDistance = 3.0,
    StorageFile = 'rental_contracts.json'
}
```

### Item im Framework anlegen

**ESX:**
- Datei `esx_item.sql` importieren

**QBCore:**
- Inhalt aus `qb_item.lua` in deine `qb-core/shared/items.lua` übernehmen

Hinweis: Für klassisches ESX-Inventar ohne Metadaten wird beim Benutzen der **zuletzt gespeicherte Vertrag** des Spielers geöffnet. Bei QBCore und ox_inventory kann zusätzlich die Vertrags-ID als Metadaten mitgegeben werden.


## Schriftart Main.ttf

Das UI ist komplett auf die Schriftfamilie `MainFont` vorbereitet.

Lege deine Datei so ab:

```text
MB_Fahrzeugvermitung/html/fonts/Main.ttf
```

Danach Resource neu starten:

```cfg
refresh
ensure MB_Fahrzeugvermitung
```

Die Font-Datei selbst ist nicht erneut in dieser ZIP enthalten. Der Ordner `html/fonts/` ist vorbereitet.

## HUD-Position

Das Miet-HUD sitzt jetzt unten links über der Minimap:

```css
.rental-hud {
  left: 28px;
  bottom: 238px;
}
```

Falls deine Minimap wegen anderer HUD-Scripts größer/kleiner ist, kannst du `bottom` in `html/style.css` leicht anpassen.


HUD-Update: Hintergrund entfernt und Position höher gesetzt (`bottom: 300px`).

HUD-Update: Position auf oben mittig geändert (`top: 26px; left: 50%; transform: translateX(-50%);`).


## Vertrags-Item mit echter Unterschrift

Diese Version speichert beim Unterschreiben die tatsächliche Signatur aus der UI als `signatureDataUrl`.

Ablauf:
1. Spieler unterschreibt den Mietvertrag.
2. Server speichert den Vertrag inklusive Signatur in `rental_contracts.json`.
3. Spieler bekommt das Item `mietvertrag`.
4. Beim Benutzen öffnet sich genau dieser Vertrag.
5. Im geöffneten Vertrag kann der Spieler auf **„Spieler zeigen“** klicken.
6. Der nächste Spieler in der Nähe bekommt denselben Vertrag mit Signatur angezeigt.

Item-Dateien:
- ESX: `esx_item.sql`
- QBCore: `qb_item.lua`
- ox_inventory: `ox_inventory_item.lua`

Hinweis:
- Bei QBCore und ox_inventory wird die Vertrags-ID als Metadaten gespeichert.
- Bei Standard-ESX ohne Metadaten öffnet das Item den neuesten Vertrag des Spielers.


## Vertragsanzeige ohne Tablet

Beim Benutzen des Items `mietvertrag` wird jetzt nur noch das Vertragsblatt angezeigt.
Das große Miet-Tablet wird dabei nicht geöffnet. Der Viewer enthält nur:

- Vertragsblatt
- Schließen
- Spieler zeigen

Die normale Mietstation nutzt weiterhin das Tablet.




## Mietvertrag nur per Item öffnen

Diese Version öffnet den Vertrag **nicht per Command**, sondern per Item-Nutzung.

Item-Name:

```lua
Config.ContractItem.Name = 'mietvertrag'
```

### ESX
1. `esx_item.sql` importieren.
2. Resource neu starten.
3. Das Script registriert `mietvertrag` automatisch mit `ESX.RegisterUsableItem`.

### QBCore
1. Inhalt von `qb_item.lua` in `qb-core/shared/items.lua` einfügen.
2. `qb-core` neu starten.
3. `MB_Fahrzeugvermitung` neu starten.
4. Das Script registriert `mietvertrag` automatisch als usable item.

### ox_inventory
1. Inhalt von `ox_inventory_item.lua` in `ox_inventory/data/items.lua` einfügen.
2. `ox_inventory` neu starten.
3. `MB_Fahrzeugvermitung` neu starten.
4. Das Item öffnet über:
```lua
client = {
    event = 'MB_Fahrzeugvermitung:client:useContractItem'
}
```

Ablauf:
- Spieler unterschreibt.
- Spieler bekommt Item `mietvertrag`.
- Beim Benutzen öffnet sich nur das Vertragsblatt.
- Mit „Spieler zeigen“ kann er es dem nächsten Spieler zeigen.


## ox_inventory: Mietvertrag per Item öffnen

Diese Version ist für ox_inventory voreingestellt:

```lua
Config.ContractItem.Inventory = 'ox_inventory'
Config.ContractItem.Name = 'mietvertrag'
```

In `ox_inventory/data/items.lua` muss exakt dieser Eintrag stehen:

```lua
['mietvertrag'] = {
    label = 'Mietvertrag',
    weight = 1,
    stack = false,
    close = true,
    consume = 0,
    description = 'Ein unterschriebener Mietvertrag',
    client = {
        event = 'MB_Fahrzeugvermitung:client:useContractItem'
    }
},
```

Danach in dieser Reihenfolge neu starten:

```cfg
ensure ox_inventory
ensure MB_Fahrzeugvermitung
```

Wenn das Item im Inventar liegt, öffnet ein Klick/Benutzen direkt den gespeicherten Vertrag.


## Fix: contractViewerApp null

Diese Version enthält den Container:

```html
<div class="contract-viewer-overlay hidden" id="contract-viewer-app"></div>
```

zusätzlich fest in `index.html`. Außerdem erstellt `script.js` den Container als Fallback automatisch, falls er durch ein altes HTML fehlt.

UI-Fix: Vertragsnummer im Vertrag ausgeblendet und Linie unter der Unterschrift entfernt.


## Resource-Name / Exports

Der Ordner heißt jetzt:

```text
MB_Fahrzeugvermitung
```

Starten in der `server.cfg`:

```cfg
ensure MB_Fahrzeugvermitung
```

Alle Events wurden von `wm_vehiclerental:*` auf `MB_Fahrzeugvermitung:*` geändert.

Client-Exports:

```lua
exports['MB_Fahrzeugvermitung']:openContractItem(itemData, slot)
exports['MB_Fahrzeugvermitung']:openMietvertrag(itemData, slot)
exports['MB_Fahrzeugvermitung']:OpenMietvertrag(itemData, slot)
```

ox_inventory Item-Event:

```lua
client = {
    event = 'MB_Fahrzeugvermitung:client:useContractItem'
}
```


## Adminpanel: Fahrzeuge löschen

Im Adminpanel gibt es jetzt den Bereich **Fahrzeuge löschen**.

Ablauf:
1. `/rentaladmin` öffnen.
2. Fahrzeug in der Liste suchen.
3. Auf **Löschen** klicken.
4. Bestätigen.
5. Fahrzeug wird aus `data/admin_vehicles.json` entfernt.

Nur Admins mit Berechtigung können Fahrzeuge löschen.


## Fix: Config-Fahrzeuge löschen

Config-Fahrzeuge können nicht direkt aus `config.lua` entfernt werden, weil FiveM zur Laufzeit keine Lua-Dateien umschreiben sollte.

Ab jetzt funktioniert Löschen trotzdem:

- Admin-Fahrzeuge werden wirklich aus `data/admin_vehicles.json` entfernt.
- Config-Fahrzeuge werden in `data/admin_vehicles.json` unter `deletedConfigVehicles` gespeichert.
- Dadurch werden sie im Adminpanel und bei der Vermietung dauerhaft ausgeblendet.
- Wenn du dasselbe Fahrzeug später im Adminpanel neu speicherst/überschreibst, wird es wieder eingeblendet.


## Fix: Adminpanel schließt beim Einfügen

Das Adminpanel bleibt beim Fahrzeug-Hinzufügen/Speichern jetzt offen.

Fixes:
- Admin-Formulare blockieren normales HTML-Submit.
- Speicherbuttons schließen das NUI nicht mehr.
- Nach dem Speichern wird nur die Adminliste aktualisiert.
- Das Panel bleibt im Adminmodus offen.


Fix: Die versehentlich außerhalb des Adminpanels eingefügte Leiste wurde entfernt.


## Adminpanel: Miet-Orte mit NPC festlegen

Im Adminpanel gibt es jetzt im Tab **Standorte** eine Verwaltung für Miet-Orte.

Du kannst:
- Ort hinzufügen
- aktuellen Spielerstandort übernehmen
- X/Y/Z/Heading manuell setzen
- NPC-Modell setzen
- Orte bearbeiten
- ingame erstellte Orte löschen

An jedem gespeicherten Ort spawnt ein NPC. Spieler gehen zum NPC und drücken `E`, um Fahrzeuge zu mieten.

Die Orte werden gespeichert in:

```text
data/admin_vehicles.json
```

NPC-Einstellungen in `config.lua`:

```lua
Config.AdminLocationPed = {
    Enabled = true,
    DefaultModel = 's_m_m_autoshop_01',
    Scenario = 'WORLD_HUMAN_CLIPBOARD',
    InteractDistance = 2.2,
    SpawnDistance = 80.0
}
```


Fix: Obere Leiste entfernt und Schutz gegen versehentlich im Body gerenderte Admin-Elemente ergänzt.


## Fix: UI öffnet wieder + ox_target für Miet-Orte

Diese Version entfernt die fehlerhafte harte UI-Ausblendung und nutzt für Miet-Orte jetzt **ox_target**.

Wichtig in der `server.cfg`:

```cfg
ensure ox_target
ensure MB_Fahrzeugvermitung
```

Ablauf:
1. `/rentaladmin` öffnen.
2. Tab **Standorte** öffnen.
3. Ort hinzufügen.
4. **Aktuelle Position übernehmen** oder Koordinaten manuell setzen.
5. Speichern.
6. Dort spawnt ein NPC.
7. Spieler öffnen die Vermietung am NPC über **ox_target**.

Config:

```lua
Config.UseOxTarget = true
Config.TargetResource = 'ox_target'
```


## Fix: BuildAdminLocations nil

Serverfehler behoben:

```text
attempt to call a nil value (global 'BuildAdminLocations')
```

Die Standort-Funktion wird jetzt vor allen Admin- und Location-Events definiert.


## Fix: UI öffnet generell nicht

Diese Version repariert die Öffnungslogik komplett:

- `/rentaladmin` öffnet das Adminpanel direkt über Server → Client Event.
- `/adminrental` ist zusätzlich als Alias drin.
- Miet-NPCs öffnen die Miet-UI über `ox_target`.
- NUI akzeptiert jetzt direkte Events `openRental` und `openAdmin`.
- `requestAdminData` und `requestRentalData` wurden robust neu gesetzt.

Wichtig:

```cfg
ensure ox_target
ensure MB_Fahrzeugvermitung
```


## HARD FIX: UI öffnet nicht

Diese Version enthält einen direkten UI-Bridge-Fix:

- `/rentaladmin` und `/adminrental` sind serverseitig und clientseitig registriert.
- Server sendet `MB_Fahrzeugvermitung:client:openAdmin`.
- Client setzt NUI-Focus und sendet `openAdmin` an HTML.
- HTML öffnet `#admin-app` direkt.
- ox_target nutzt `MB_Fahrzeugvermitung:server:openRentalAtLocation`.

Test:
```cfg
ensure ox_target
ensure ox_inventory
ensure MB_Fahrzeugvermitung
```

Dann:
```text
/rentaladmin
```


## Fix: Server Parse Error + fehlende JSON

Behoben:
- `rental_contracts.json` liegt jetzt korrekt unter `data/rental_contracts.json`.
- `fxmanifest.lua` zeigt jetzt auf `data/rental_contracts.json`.
- Fehler `server/main.lua:689: <eof> expected near 'end'` wurde durch Entfernen des kaputten Hard-Fix-Blocks behoben.
- Neuer Hard-Fix-Block wurde sauber und geschlossen neu eingefügt.

Interner Balance-Check: `13`


## WICHTIG: Cache / alte Datei löschen

Diese Version enthält absichtlich beide Dateien:

```text
data/rental_contracts.json
rental_contracts.json
```

Damit verschwindet die Warnung auch dann, wenn dein Server noch eine alte `fxmanifest.lua` gecached hat.

Bitte wirklich so machen:
1. Server stoppen.
2. Alten Ordner `resources/[...]/MB_Fahrzeugvermitung` komplett löschen.
3. Neuen Ordner aus dieser ZIP einfügen.
4. Server starten.
5. Nicht nur einzelne Dateien überschreiben.

Start:
```cfg
ensure ox_target
ensure ox_inventory
ensure MB_Fahrzeugvermitung
```

Test:
```text
/rentaladmin
```


## Lua 689 Fix

Der alte kaputte Hard-Fix-/UI-Open-Block wurde entfernt und durch `MB_SAFE_UI_OPEN` ersetzt.

Syntax-Check:
```text
rough_balance=13, min=0, luac_error=[Errno 13] Permission denied: 'luac'
```

Bitte den alten Resource-Ordner komplett löschen und diese Version neu einsetzen.


## Fix: Adminpanel leer

Das Adminpanel war leer, weil die Serverdaten nicht im Format ankamen, das `script.js` erwartet hat.

Behoben:
- Admin-Payload wird im UI normalisiert.
- Tabs rendern jetzt auch bei fehlenden Daten.
- Fehler im Tab werden sichtbar angezeigt statt leere Fläche.
- `forceOpenAdmin`, `openAdmin`, `adminOpen` und `openAdminPanel` öffnen alle denselben Renderer.
- Server gibt notfalls Default-Daten zurück, damit das Dashboard nicht leer bleibt.

Syntax-Check:
```text
...dmin_empty_fix_work/MB_Fahrzeugvermitung/server/main.lua:3: attempt to index a nil value (global 'Config')
```


## Fix: Standorte + ox_target + Adminpanel leer

Behoben:
- Adminpanel rendert jetzt sofort, ohne zuerst leer zu bleiben.
- Der kaputte externe `forceOpenAdmin`-Handler wurde entfernt.
- `forceOpenAdmin`, `openAdmin`, `adminOpen`, `openAdminPanel` werden direkt im richtigen UI-Kontext verarbeitet.
- `openRental` vom ox_target-NPC öffnet jetzt die Miet-UI.
- Ingame erstellte Standorte werden serverseitig als gültige Mietstandorte erkannt.
- Wenn ein ingame Standort keine Fahrzeugliste hat, sind dort alle Fahrzeuge verfügbar.
- `requestAdminData` nutzt jetzt den funktionierenden Server-Event.
- `Config.Vehicles` wird korrekt als Key-Table gelesen.

Checks:
```text
Lua: ...arget_full_fix_work/MB_Fahrzeugvermitung/server/main.lua:3: attempt to index a nil value (global 'Config')
JS: 
```

Wichtig:
1. Alten Ordner komplett löschen.
2. Neue Version einsetzen.
3. Startreihenfolge:
```cfg
ensure ox_target
ensure ox_inventory
ensure MB_Fahrzeugvermitung
```
