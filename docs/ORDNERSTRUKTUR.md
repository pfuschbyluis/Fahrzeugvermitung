# Ordnerstruktur

```text
MB_Fahrzeugvermitung/
├─ fxmanifest.lua
├─ config.lua
├─ README.md
├─ client/
│  └─ main.lua
├─ server/
│  └─ main.lua
├─ data/
│  ├─ admin_vehicles.json
│  └─ rental_contracts.json
├─ html/
│  ├─ index.html
│  ├─ style.css
│  ├─ script.js
│  ├─ img/
│  └─ fonts/
│     └─ Main.ttf hier reinlegen
└─ install/
   ├─ install.sql
   ├─ esx_item.sql
   ├─ qb_item.lua
   └─ ox_inventory_item.lua
```

## Wichtig

- `client/main.lua` und `server/main.lua` sind im `fxmanifest.lua` eingetragen.
- JSON-Speicherdateien liegen jetzt in `data/`.
- Item-Definitionen und SQL-Dateien liegen jetzt in `install/`.
- Deine Schriftdatei muss weiterhin hier rein:

```text
html/fonts/Main.ttf
```
