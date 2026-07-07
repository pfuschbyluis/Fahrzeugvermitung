Config = {}

--[[
  WO WIRD WAS GESPEICHERT?
  ─────────────────────────────────────────────────────────────
  MySQL (oxmysql)     → nur Miet-Historie / Statistik (optional)
  data/admin_vehicles.json → Fahrzeuge, Orte, Mietdauern, Einstellungen (Admin-Panel)
  data/rental_contracts.json → unterschriebene Mietverträge
  config.lua          → Server-Grundeinstellungen (Framework, Interaktion, DB, Admin)
  ─────────────────────────────────────────────────────────────
  Fahrzeuge, Orte und Mietdauern werden im Admin-Panel verwaltet
  und in data/admin_vehicles.json gespeichert — NICHT in MySQL.
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
-- STARTWERTE (optional — danach aus data/admin_vehicles.json)
-- ============================================================

-- Mietdauern: nur Standard beim ersten Start, danach data/admin_vehicles.json
Config.RentalDurations = {
    { minutes = 15,  multiplier = 1.0 },
    { minutes = 30,  multiplier = 1.8 },
    { minutes = 60,  multiplier = 3.2 },
    { minutes = 120, multiplier = 6.0 },
}

-- Fahrzeuge & Orte: leer lassen — alles über das Admin-Panel / JSON
Config.Vehicles = {}
Config.RentalLocations = {}
