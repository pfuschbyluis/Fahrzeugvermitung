Config = {}

-- ============================================================
-- FRAMEWORK
-- ============================================================
Config.Framework = 'esx'          -- 'esx' oder 'qbcore'
Config.ESXExport = 'es_extended'  -- Resource-Name von ESX
Config.QBExport  = 'qb-core'      -- Resource-Name von QBCore

-- ============================================================
-- INTERAKTION
-- ============================================================
Config.UseTarget   = true         -- true = ox_target/qtarget, false = Taste drücken (E)
Config.TargetSystem = 'ox_target' -- 'ox_target' oder 'qtarget'
Config.InteractKey  = 38          -- E-Taste, nur relevant wenn UseTarget = false
Config.InteractDistance = 8.0     -- Entfernung, ab der die NPCs/Marker geladen werden

Config.UseOxLib = true            -- true = ox_lib Notifications/Progressbar, false = eigenes NUI-Notify

-- ============================================================
-- DATENBANK (optional)
-- ============================================================
-- Wird NUR benötigt, wenn du abgeschlossene/aktive Vermietungen dauerhaft
-- speichern willst (z.B. für Statistiken oder einen Admin-Überblick).
-- Für den normalen Betrieb (Miete -> Fahrzeug -> Ablauf -> löschen) wird
-- KEINE Datenbank benötigt.
Config.UseDatabase = false
Config.DatabaseTable = 'MB_Fahrzeugvermitung_history'

-- ============================================================
-- MIETVERHALTEN
-- ============================================================
Config.DeleteVehicleOnExpire = true   -- Fahrzeug nach Mietablauf automatisch löschen
Config.ExpireWarningTime = 60         -- Sekunden vor Ablauf, in denen gewarnt wird
Config.GiveKeys = true                -- Fahrzeugschlüssel über Keys-System vergeben
Config.KeysSystem = 'auto'            -- 'auto', 'qb-vehiclekeys', 'qs-vehiclekeys', 'wasabi_carlock', 'none'
Config.Cooldown = 0                   -- Cooldown in Minuten zwischen zwei Anmietungen, 0 = deaktiviert
Config.MaxActiveRentalsPerPlayer = 1  -- Wie viele gemietete Fahrzeuge gleichzeitig aktiv sein dürfen


-- ============================================================
-- ADMINPANEL
-- ============================================================
Config.AdminCommand = 'rentaladmin'                 -- Ingame-Command: /rentaladmin
Config.AdminAce = 'MB_Fahrzeugvermitung.admin'          -- add_ace group.admin MB_Fahrzeugvermitung.admin allow
Config.AdminGroups = { 'admin', 'superadmin', 'god' } -- ESX/QBCore Gruppen mit Zugriff
Config.AdminStorageFile = 'data/admin_vehicles.json'     -- Datei für ingame hinzugefügte Fahrzeuge


-- ============================================================
-- MIETVERTRAG ALS ITEM
-- ============================================================
Config.ContractItem = {
    Enabled = true,
    Name = 'mietvertrag',        -- Item-Name im Inventar
    Inventory = 'ox_inventory',  -- 'framework', 'ox_inventory' oder 'auto'
    ShowDistance = 3.0,          -- Distanz, um anderen Spielern den Vertrag zu zeigen
    StorageFile = 'data/rental_contracts.json'
}

-- ============================================================
-- ZAHLUNGSMETHODEN
-- ============================================================
Config.PaymentMethods = {
    { id = 'cash', label = 'Bar',   account = 'money' },
    { id = 'card', label = 'Karte', account = 'bank'  },
}

-- ============================================================
-- MIETDAUER (Preis-Multiplikator wird auf den Fahrzeug-Grundpreis angewendet)
-- ============================================================
Config.RentalDurations = {
    { label = '15 Minuten', minutes = 15,  multiplier = 1.0 },
    { label = '30 Minuten', minutes = 30,  multiplier = 1.8 },
    { label = '1 Stunde',   minutes = 60,  multiplier = 3.2 },
    { label = '2 Stunden',  minutes = 120, multiplier = 6.0 },
}

-- ============================================================
-- FAHRZEUGE
-- Bild-Dateien liegen in html/img/ und werden per Dateiname referenziert.
-- ============================================================
Config.Vehicles = {
    quail = {
        label    = 'Devauchee Quail',
        model    = 'quail',
        price    = 250,
        category = 'Sportwagen',
        image    = 'img/quail.svg',
    },
    faggio2 = {
        label    = 'Pegassi Faggio Sport',
        model    = 'faggio2',
        price    = 60,
        category = 'Roller',
        image    = 'img/faggio2.svg',
    },
    faggio = {
        label    = 'Faggio',
        model    = 'faggio',
        price    = 40,
        category = 'Roller',
        image    = 'img/faggio.svg',
    },
}

-- ============================================================
-- VERMIETUNGSSTANDORTE
-- Jeder Standort verweist per Key auf Config.Vehicles.
-- Mehrere Standorte mit unterschiedlichem Fahrzeugangebot möglich.
-- ============================================================
Config.RentalLocations = {
    {
        name  = 'flughafen',
        label = 'Flughafen Vermietung',

        npc = {
            enabled = true,
            model   = 'a_m_m_business_01',
            coords  = vector4(-1035.0, -2733.5, 20.17, 240.0),
        },

        marker = {
            enabled = true,
            coords  = vector3(-1035.0, -2733.5, 19.17),
            size    = vector3(1.5, 1.5, 0.5),
            color   = { r = 0, g = 160, b = 90 },
        },

        blip = {
            enabled = true,
            coords  = vector3(-1035.0, -2733.5, 20.17),
            sprite  = 225,
            color   = 2,
            scale   = 0.8,
            label   = 'Fahrzeugvermietung',
        },

        spawnPoint = vector4(-1041.0, -2727.0, 20.17, 240.0),

        -- Welche Fahrzeuge (Keys aus Config.Vehicles) an diesem Standort verfügbar sind
        vehicles = { 'quail', 'faggio2', 'faggio' },
    },

    {
        name  = 'strand',
        label = 'Strand Vermietung',

        npc = {
            enabled = true,
            model   = 'a_f_y_beach_01',
            coords  = vector4(-1339.0, -1108.0, 5.9, 20.0),
        },

        marker = {
            enabled = true,
            coords  = vector3(-1339.0, -1108.0, 4.9),
            size    = vector3(1.5, 1.5, 0.5),
            color   = { r = 0, g = 160, b = 90 },
        },

        blip = {
            enabled = true,
            coords  = vector3(-1339.0, -1108.0, 5.9),
            sprite  = 225,
            color   = 2,
            scale   = 0.8,
            label   = 'Fahrzeugvermietung',
        },

        spawnPoint = vector4(-1345.0, -1102.0, 4.9, 20.0),

        vehicles = { 'faggio2', 'faggio' },
    },
}


-- Adminpanel-Orte / NPCs
Config.AdminLocationPed = {
    Enabled = true,
    DefaultModel = 's_m_m_autoshop_01',
    Scenario = 'WORLD_HUMAN_CLIPBOARD',
    InteractDistance = 2.2,
    SpawnDistance = 80.0
}


-- ox_target für Miet-Orte
Config.UseOxTarget = true
Config.TargetResource = 'ox_target'
