Config = {}

--[[
  WO WIRD WAS GESPEICHERT?
  ─────────────────────────────────────────────────────────────
  MySQL (oxmysql)     → nur Miet-Historie / Statistik (optional)
  data/admin_vehicles.json → Fahrzeuge, Orte, Mietdauern, Einstellungen (Admin-Panel)
  data/rental_contracts.json → unterschriebene Mietverträge
  config.lua          → Server-Grundeinstellungen + Startwerte (beim ersten Start)
  ─────────────────────────────────────────────────────────────
  Alles was du im Admin-Panel änderst, landet in der JSON-Datei — NICHT in MySQL.
  Die Einträge unten (Fahrzeuge, Orte, Mietdauern) sind nur Standardwerte für den
  ersten Start. Danach kannst du sie ingame verwalten.
]]

-- ============================================================
-- FRAMEWORK
-- ============================================================
Config.Framework = 'esx'          -- 'esx' oder 'qbcore'
Config.ESXExport = 'es_extended'
Config.QBExport  = 'qb-core'

-- ============================================================
-- INTERAKTION
-- ============================================================
Config.UseTarget   = true         -- true = ox_target/qtarget, false = Taste E
Config.TargetSystem = 'ox_target' -- 'ox_target' oder 'qtarget'
Config.InteractKey  = 38
Config.InteractDistance = 8.0

Config.UseOxLib = true

-- Target für Admin-NPCs (Miet-Orte nutzen Config.UseTarget / Config.TargetSystem)
Config.UseOxTarget = true
Config.TargetResource = 'ox_target'

-- ============================================================
-- DATENBANK (optional — nur Miet-Historie, nicht Admin-Daten!)
-- ============================================================
Config.UseDatabase = false
Config.DatabaseTable = 'MB_Fahrzeugvermitung_history'
Config.AutoDatabaseSetup = true   -- Tabelle + ESX-Item beim Start automatisch anlegen
Config.AutoEnableDatabase = true  -- Protokollierung aktivieren wenn oxmysql läuft

-- ============================================================
-- MIETVERHALTEN (Startwerte — Einstellungen-Tab überschreibt in JSON)
-- ============================================================
Config.DeleteVehicleOnExpire = true
Config.ExpireWarningTime = 60
Config.GiveKeys = true
Config.KeysSystem = 'auto'       -- 'auto', 'qb-vehiclekeys', 'qs-vehiclekeys', 'wasabi_carlock', 'none'
Config.Cooldown = 0
Config.MaxActiveRentalsPerPlayer = 1

-- ============================================================
-- ADMINPANEL
-- ============================================================
Config.AdminCommand = 'rentaladmin'
Config.AdminAce = 'MB_Fahrzeugvermitung.admin'
Config.AdminGroups = { 'admin', 'superadmin', 'god' }
Config.AdminStorageFile = 'data/admin_vehicles.json'  -- Admin-Daten (JSON, nicht MySQL)

Config.AdminLocationPed = {
    Enabled = true,
    DefaultModel = 's_m_m_autoshop_01',
    Scenario = 'WORLD_HUMAN_CLIPBOARD',
    InteractDistance = 2.2,
    SpawnDistance = 80.0
}

-- ============================================================
-- MIETVERTRAG ALS ITEM
-- ============================================================
Config.ContractItem = {
    Enabled = true,
    Name = 'mietvertrag',
    Inventory = 'ox_inventory',  -- 'framework', 'ox_inventory' oder 'auto'
    ShowDistance = 3.0,
    StorageFile = 'data/rental_contracts.json'
}

-- ============================================================
-- ZAHLUNGSMETHODEN (fest in Config — nicht im Admin-Panel)
-- ============================================================
Config.PaymentMethods = {
    { id = 'cash', label = 'Bar',   account = 'money' },
    { id = 'card', label = 'Karte', account = 'bank'  },
}

-- ============================================================
-- STARTWERTE (optional — werden nach Admin-Änderung aus JSON geladen)
-- ============================================================

-- Mietdauern: nur Standard beim ersten Start, danach data/admin_vehicles.json
Config.RentalDurations = {
    { minutes = 15,  multiplier = 1.0 },
    { minutes = 30,  multiplier = 1.8 },
    { minutes = 60,  multiplier = 3.2 },
    { minutes = 120, multiplier = 6.0 },
}

-- Fahrzeuge: Config = Basis-Katalog, Admin-Fahrzeuge kommen in JSON dazu
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

-- Standorte: Config = feste Orte mit NPC/Blip/Spawn, Admin-Orte kommen in JSON dazu
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
