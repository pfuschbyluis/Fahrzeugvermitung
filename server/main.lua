local ESX, QBCore = nil, nil

if Config.Framework == 'esx' then
    ESX = exports[Config.ESXExport]:getSharedObject()
elseif Config.Framework == 'qbcore' then
    QBCore = exports[Config.QBExport]:GetCoreObject()
end

local activeRentals = {}   -- [source] = { rentalId, netId, expireAt, locationName, locationLabel, vehicleKey, vehicleLabel, plate, price, minutes }
local lastRentalTime = {}  -- [identifier] = os.time()
local adminStore = { vehicles = {}, locations = {} }
local rentalHistory = {}
local rentalStats = { total = 0, revenue = 0 }
local contractStore = { contracts = {} }
local databaseBootstrapDone = false

-- ============================================================
-- AUTOMATISCHES DATENBANK-SETUP (beim ersten Start)
-- ============================================================
local function SanitizeTableName(name)
    name = tostring(name or '')
    if name == '' or not name:match('^[%w_]+$') then
        return 'MB_Fahrzeugvermitung_history'
    end
    return name
end

local function WaitForOxMySQL(maxWaitMs)
    maxWaitMs = maxWaitMs or 15000
    local waited = 0
    while GetResourceState('oxmysql') ~= 'started' and waited < maxWaitMs do
        Wait(250)
        waited = waited + 250
    end
    return GetResourceState('oxmysql') == 'started'
end

local function DbExecute(sql, params)
    local finished, result = false, nil
    exports.oxmysql:execute(sql, params or {}, function(res)
        result = res
        finished = true
    end)

    local attempts = 0
    while not finished and attempts < 80 do
        Wait(100)
        attempts = attempts + 1
    end

    if not finished then
        return false, 'timeout'
    end
    return true, result
end

local function BuildHistoryTableSql(tableName)
    return ([[
CREATE TABLE IF NOT EXISTS `%s` (
    `id`         INT NOT NULL AUTO_INCREMENT,
    `identifier` VARCHAR(64)  NOT NULL,
    `location`   VARCHAR(64)  NOT NULL,
    `vehicle`    VARCHAR(64)  NOT NULL,
    `plate`      VARCHAR(16)  NOT NULL,
    `price`      INT NOT NULL,
    `minutes`    INT NOT NULL,
    `payment`    VARCHAR(16)  NOT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]]):format(tableName)
end

local function EnsureEsxContractItem()
    if Config.Framework ~= 'esx' then return true end
    if not (Config.ContractItem and Config.ContractItem.Enabled) then return true end

    local itemName = Config.ContractItem.Name or 'mietvertrag'
    if not itemName:match('^[%w_]+$') then return false, 'invalid item name' end

    local ok, err = DbExecute(
        'INSERT IGNORE INTO `items` (`name`, `label`, `weight`) VALUES (?, ?, ?)',
        { itemName, 'Mietvertrag', 1 }
    )
    if not ok then
        return false, err
    end
    return true
end

local function RunAutoDatabaseSetup()
    if databaseBootstrapDone then return end
    if Config.AutoDatabaseSetup == false then return end

    if not WaitForOxMySQL() then
        print('[MB_Fahrzeugvermitung] Auto-Datenbank-Setup übersprungen: oxmysql nicht verfügbar.')
        ReportError({
            description = 'Automatisches Datenbank-Setup übersprungen: oxmysql nicht verfügbar.',
            system = 'oxmysql / Datenbank',
            hint = 'oxmysql installieren und in der server.cfg vor dieser Resource starten.',
            code = 'oxmysql_missing',
            notifyPlayer = false,
        })
        return
    end

    local tableName = SanitizeTableName(Config.DatabaseTable)
    Config.DatabaseTable = tableName

    local ok, err = DbExecute(BuildHistoryTableSql(tableName))
    if not ok then
        print(('[MB_Fahrzeugvermitung] Auto-Datenbank-Setup fehlgeschlagen (Tabelle %s): %s'):format(tableName, tostring(err)))
        ReportError({
            description = ('Miet-Historie-Tabelle konnte nicht erstellt werden (%s).'):format(tableName),
            system = 'oxmysql / Datenbank',
            hint = 'MySQL-Verbindung und Berechtigungen prüfen. Fehler: ' .. tostring(err),
            code = 'db_table_create',
            notifyPlayer = false,
        })
        return
    end

    local itemOk, itemErr = EnsureEsxContractItem()
    if itemOk then
        if Config.Framework == 'esx' and Config.ContractItem and Config.ContractItem.Enabled then
            print(('[MB_Fahrzeugvermitung] ESX-Item "%s" automatisch in der Datenbank registriert.'):format(Config.ContractItem.Name or 'mietvertrag'))
        end
    else
        print(('[MB_Fahrzeugvermitung] ESX-Item konnte nicht automatisch registriert werden: %s'):format(tostring(itemErr)))
        ReportError({
            description = ('ESX-Mietvertrag-Item "%s" konnte nicht registriert werden.'):format(Config.ContractItem.Name or 'mietvertrag'),
            system = 'ESX / Datenbank-Items',
            hint = 'Item manuell in der ESX-items-Tabelle anlegen oder SQL-Rechte prüfen.',
            code = 'esx_item_register',
            notifyPlayer = false,
        })
    end

    if Config.AutoEnableDatabase then
        Config.UseDatabase = true
    end

    databaseBootstrapDone = true
    print(('[MB_Fahrzeugvermitung] Datenbank-Setup abgeschlossen (Tabelle: %s, Protokollierung: %s).'):format(
        tableName,
        Config.UseDatabase and 'aktiv' or 'inaktiv'
    ))
end

-- Globaler Forward-Fix: alte Admin-Funktionen rufen BuildAdminLocations global auf.
_G.BuildAdminLocations = _G.BuildAdminLocations

-- ============================================================
-- FRAMEWORK-ABSTRAKTION
-- ============================================================
local function GetPlayerObj(src)
    if Config.Framework == 'esx' then
        return ESX.GetPlayerFromId(src)
    elseif Config.Framework == 'qbcore' then
        return QBCore.Functions.GetPlayer(src)
    end
    return nil
end

local function GetIdentifier(src)
    if Config.Framework == 'esx' then
        local xPlayer = GetPlayerObj(src)
        return xPlayer and xPlayer.identifier or tostring(src)
    elseif Config.Framework == 'qbcore' then
        local Player = GetPlayerObj(src)
        return Player and Player.PlayerData.citizenid or tostring(src)
    end
    return tostring(src)
end

local function GetMoney(src, account)
    local playerObj = GetPlayerObj(src)
    if not playerObj then return 0 end

    if Config.Framework == 'esx' then
        if account == 'money' then
            return playerObj.getMoney()
        else
            local acc = playerObj.getAccount(account)
            return acc and acc.money or 0
        end
    elseif Config.Framework == 'qbcore' then
        return playerObj.PlayerData.money[account] or 0
    end
    return 0
end

local function RemoveMoney(src, account, amount)
    local playerObj = GetPlayerObj(src)
    if not playerObj then return false end

    if Config.Framework == 'esx' then
        if account == 'money' then
            playerObj.removeMoney(amount)
        else
            playerObj.removeAccountMoney(account, amount)
        end
        return true
    elseif Config.Framework == 'qbcore' then
        return playerObj.Functions.RemoveMoney(account, amount, 'vehicle-rental')
    end
    return false
end

-- ============================================================
-- UTILS (Trim muss vor GetCharacterName stehen — Lua-Scoping)
-- ============================================================
local function Trim(value)
    return tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

-- ============================================================
-- CHARAKTERNAME
-- ============================================================
local function GetCharacterName(src)
    local function fullName(first, last)
        first = Trim(first)
        last = Trim(last)
        if first == '' then return nil end
        if last == '' then return first end
        return ('%s %s'):format(first, last)
    end

    local playerObj = GetPlayerObj(src)

    if Config.Framework == 'esx' and playerObj then
        if playerObj.getName then
            local name = Trim(playerObj.getName())
            if name ~= '' then return name end
        end
        if playerObj.get then
            local name = fullName(
                playerObj.get('firstName') or playerObj.get('firstname'),
                playerObj.get('lastName') or playerObj.get('lastname')
            )
            if name then return name end
        end
        if type(playerObj.variables) == 'table' then
            local v = playerObj.variables
            local name = fullName(v.firstName or v.firstname, v.lastName or v.lastname)
            if name then return name end
        end
    elseif Config.Framework == 'qbcore' and playerObj then
        local ci = playerObj.PlayerData and playerObj.PlayerData.charinfo
        if ci then
            local name = fullName(ci.firstname, ci.lastname)
            if name then return name end
        end
    end

    return GetPlayerName(src) or 'Unbekannt'
end

RegisterNetEvent('MB_Fahrzeugvermitung:getCharacterName', function()
    local src = source
    TriggerClientEvent('MB_Fahrzeugvermitung:receiveCharacterName', src, GetCharacterName(src))
end)

-- ============================================================
-- UTILS / STORAGE
-- ============================================================
local function Keyify(value)
    local key = Trim(value):lower():gsub('[^%w_%-]+', '_'):gsub('^_+', ''):gsub('_+$', '')
    if #key > 40 then key = key:sub(1, 40) end
    return key
end

local function TableContains(t, value)
    if not t then return false end
    for _, v in ipairs(t) do
        if v == value then return true end
    end
    return false
end


local function ResolveSpawnPoint(loc, x, y, z, heading)
    heading = tonumber(heading) or 0.0
    local sp = loc and loc.spawnPoint
    if type(sp) == 'vector4' then
        return sp
    end
    if type(sp) == 'table' then
        local sx = tonumber(sp.x) or tonumber(sp[1])
        local sy = tonumber(sp.y) or tonumber(sp[2])
        local sz = tonumber(sp.z) or tonumber(sp[3])
        local sh = tonumber(sp.heading) or tonumber(sp.w) or tonumber(sp[4]) or heading
        if sx and sy and sz then
            return vector4(sx, sy, sz, sh)
        end
    end
    return vector4(x + 3.0, y, z, heading)
end

local function FindLocation(name)
    name = tostring(name or '')

    for _, loc in ipairs(Config.RentalLocations or {}) do
        if loc.name == name or loc.key == name then
            return loc
        end
    end

    if type(adminStore) == 'table' and type(adminStore.locations) == 'table' then
        for _, loc in ipairs(adminStore.locations) do
            if type(loc) == 'table' and (loc.key == name or loc.name == name) then
                local c = loc.coords or {}
                local x = tonumber(c.x) or tonumber(c[1]) or 0.0
                local y = tonumber(c.y) or tonumber(c[2]) or 0.0
                local z = tonumber(c.z) or tonumber(c[3]) or 0.0
                local h = tonumber(loc.heading) or 0.0

                return {
                    name = loc.key or loc.name,
                    key = loc.key or loc.name,
                    label = loc.label or loc.name or 'Mietstation',
                    vehicles = loc.vehicles or {},
                    spawnPoint = ResolveSpawnPoint(loc, x, y, z, h),
                    npc = {
                        enabled = true,
                        model = loc.pedModel or (Config.AdminLocationPed and Config.AdminLocationPed.DefaultModel) or 's_m_m_autoshop_01',
                        coords = vector4(x, y, z, h)
                    }
                }
            end
        end
    end

    return nil
end


local function FormatDurationLabel(minutes)
    minutes = math.floor(tonumber(minutes) or 0)
    if minutes <= 0 then return '0 Minuten' end
    if minutes == 1 then return '1 Minute' end
    if minutes < 60 then return ('%d Minuten'):format(minutes) end
    if minutes % 60 == 0 then
        local hours = minutes / 60
        if hours == 1 then return '1 Stunde' end
        return ('%d Stunden'):format(hours)
    end
    return ('%d Minuten'):format(minutes)
end

local function NormalizeDurationEntry(du)
    if type(du) ~= 'table' then return nil end
    local minutes = math.max(1, math.floor(tonumber(du.minutes) or 0))
    local multiplier = math.max(0.1, tonumber(du.multiplier) or 1.0)
    if minutes <= 0 then return nil end
    return {
        minutes = minutes,
        multiplier = multiplier,
        label = FormatDurationLabel(minutes),
    }
end

local function NormalizeDurations(list)
    local clean = {}
    for _, du in ipairs(list or {}) do
        local entry = NormalizeDurationEntry(du)
        if entry then clean[#clean + 1] = entry end
    end
    table.sort(clean, function(a, b) return a.minutes < b.minutes end)
    return clean
end

local function GetRentalDurations()
    if type(adminStore.durations) == 'table' and #adminStore.durations > 0 then
        return NormalizeDurations(adminStore.durations)
    end
    return NormalizeDurations(Config.RentalDurations)
end

local function FindDuration(idx)
    return Config.RentalDurations[idx + 1] -- JS ist 0-indexiert
end

local function FindPayment(id)
    id = Trim(id)
    if id == '' then return nil end

    for _, p in ipairs(Config.PaymentMethods or {}) do
        if p.id == id then return p end
    end

    -- Kompatibilität: bank/card und Konto-Namen
    if id == 'bank' or id == 'card' then
        for _, p in ipairs(Config.PaymentMethods or {}) do
            if p.id == 'bank' or p.id == 'card' or p.account == 'bank' then
                return p
            end
        end
    end

    return nil
end

local function NormalizeStore(data)
    if type(data) ~= 'table' then data = {} end
    if type(data.vehicles) ~= 'table' then data.vehicles = {} end
    if type(data.locations) ~= 'table' then data.locations = {} end
    if type(data.deletedConfigVehicles) ~= 'table' then data.deletedConfigVehicles = {} end
    return data
end

local function ApplyAdminStoreToConfig()
    if type(adminStore.durations) == 'table' and #adminStore.durations > 0 then
        Config.RentalDurations = NormalizeDurations(adminStore.durations)
    end
    if type(adminStore.settings) == 'table' then
        local s = adminStore.settings
        if s.cooldown ~= nil then Config.Cooldown = s.cooldown end
        if s.maxActive ~= nil then Config.MaxActiveRentalsPerPlayer = s.maxActive end
        if s.warningTime ~= nil then Config.ExpireWarningTime = s.warningTime end
    end
end

local function NormalizeContractStore(data)
    if type(data) ~= 'table' then data = {} end
    if type(data.contracts) ~= 'table' then data.contracts = {} end
    return data
end

local function LoadContractStore()
    local file = (Config.ContractItem and Config.ContractItem.StorageFile) or 'data/rental_contracts.json'
    local raw = LoadResourceFile(GetCurrentResourceName(), file)
    if raw and raw ~= '' then
        local ok, decoded = pcall(json.decode, raw)
        if ok and type(decoded) == 'table' then
            contractStore = NormalizeContractStore(decoded)
        else
            ReportError({
                description = ('Mietverträge konnten nicht gelesen werden (%s).'):format(file),
                system = 'data/rental_contracts.json',
                hint = 'JSON-Syntax der Vertragsdatei prüfen.',
                code = 'contract_store_decode',
                notifyPlayer = false,
            })
            contractStore = { contracts = {} }
        end
    else
        contractStore = { contracts = {} }
        SaveResourceFile(GetCurrentResourceName(), file, json.encode(contractStore), -1)
    end
end

local function SaveContractStore()
    local file = (Config.ContractItem and Config.ContractItem.StorageFile) or 'data/rental_contracts.json'
    SaveResourceFile(GetCurrentResourceName(), file, json.encode(contractStore), -1)
end

local function AddContractRecord(contract)
    if type(contract) ~= 'table' or not contract.id then return end
    contractStore.contracts[contract.id] = contract
    SaveContractStore()
end

local function GetContractById(contractId)
    return contractStore.contracts and contractStore.contracts[contractId] or nil
end

local function GetPlayerContracts(identifier)
    local out = {}
    for _, contract in pairs(contractStore.contracts or {}) do
        if contract.identifier == identifier then
            out[#out + 1] = contract
        end
    end
    table.sort(out, function(a, b)
        return (tonumber(a.signedAt) or 0) > (tonumber(b.signedAt) or 0)
    end)
    return out
end

local function GetLatestPlayerContract(identifier)
    local list = GetPlayerContracts(identifier)
    return list[1]
end

local function NormalizeSignatureDataUrl(value)
    value = Trim(value)
    if value == '' then return '' end
    if #value > 250000 then return '' end
    if value:match('^data:image/png;base64,[A-Za-z0-9%+%/%=]+$') then
        return value
    end
    return ''
end

local function BuildContractPayload(src, rentalId, locationLabel, vehicle, duration, payment, totalPrice, plate, signatureDataUrl)
    local playerName = GetCharacterName(src)
    return {
        id = ('CTR-%s'):format(rentalId),
        rentalId = rentalId,
        identifier = GetIdentifier(src),
        tenant = playerName,
        playerName = playerName,
        date = os.date('%d.%m.%Y'),
        signedAt = os.time(),
        status = 'Unterschrieben',
        statusKey = 'signed',
        location = locationLabel or '—',
        vehicleLabel = vehicle.label or vehicle.model or 'Fahrzeug',
        vehicleModel = vehicle.model or 'unknown',
        durationLabel = duration.label or (tostring(duration.minutes) .. ' Minuten'),
        durationMinutes = duration.minutes or 0,
        paymentLabel = payment.label or '—',
        price = tonumber(totalPrice) or 0,
        plate = plate or '—',
        signatureDataUrl = signatureDataUrl or '',
    }
end

local function ResolveContractInventory()
    local mode = Config.ContractItem and Config.ContractItem.Inventory or 'framework'
    if mode == 'auto' then
        if GetResourceState('ox_inventory') == 'started' then
            return 'ox_inventory'
        end
        return 'framework'
    end
    return mode
end

local function GiveContractItem(src, contract)
    if not (Config.ContractItem and Config.ContractItem.Enabled) then return true end

    local playerObj = GetPlayerObj(src)
    if not playerObj then return false end

    local itemName = Config.ContractItem.Name or 'mietvertrag'
    local meta = {
        contractId = contract.id,
        label = ('Mietvertrag %s'):format(contract.plate or ''),
        description = ('%s | %s | %s'):format(contract.vehicleLabel or 'Fahrzeug', contract.date or os.date('%d.%m.%Y'), tostring(contract.price or 0) .. '€'),
        vehicle = contract.vehicleLabel,
        plate = contract.plate,
        tenant = contract.tenant,
        date = contract.date
    }

    local mode = ResolveContractInventory()
    if mode == 'ox_inventory' then
        if GetResourceState('ox_inventory') ~= 'started' then
            print('[MB_Fahrzeugvermitung] ox_inventory ist nicht gestartet, Mietvertrag-Item konnte nicht vergeben werden.')
            ReportError({
                src = src,
                description = 'Mietvertrag konnte nicht ins Inventar gelegt werden: ox_inventory nicht gestartet.',
                system = 'ox_inventory',
                hint = 'ox_inventory in der server.cfg vor MB_Fahrzeugvermitung starten.',
                code = 'ox_inventory_stopped',
            })
            return false
        end

        local ok = exports.ox_inventory:AddItem(src, itemName, 1, meta)
        if ok == false then
            print(('[MB_Fahrzeugvermitung] ox_inventory:AddItem fehlgeschlagen für Item %s'):format(itemName))
            ReportError({
                src = src,
                description = ('Mietvertrag-Item "%s" konnte nicht vergeben werden.'):format(itemName),
                system = 'ox_inventory / Item-Setup',
                hint = ('Item "%s" in ox_inventory/data/items.lua anlegen und Resource neu starten.'):format(itemName),
                code = 'missing_contract_item',
            })
        end
        return ok ~= false
    end

    if Config.Framework == 'qbcore' then
        return playerObj.Functions.AddItem(itemName, 1, false, meta)
    elseif Config.Framework == 'esx' then
        if playerObj.addInventoryItem then
            -- Standard ESX hat keine Item-Metadaten. Der Vertrag wird trotzdem serverseitig gespeichert;
            -- beim Benutzen wird der neueste Vertrag des Spielers geöffnet.
            playerObj.addInventoryItem(itemName, 1)
            return true
        end
    end

    return false
end

local function NotifyPlayer(src, message, typ)
    TriggerClientEvent('MB_Fahrzeugvermitung:notify', src, message, typ or 'inform')
end

local function OpenContractFromItem(src, itemData)
    local identifier = GetIdentifier(src)
    local contractId = nil

    if type(itemData) == 'table' then
        local meta = itemData.metadata or itemData.info or itemData
        contractId = meta and meta.contractId or nil
    end

    local contract = contractId and GetContractById(contractId) or nil
    if not contract or contract.identifier ~= identifier then
        contract = GetLatestPlayerContract(identifier)
    end

    if not contract then
        NotifyPlayer(src, 'Für diesen Spieler wurde kein Mietvertrag gefunden.', 'error')
        return
    end

    TriggerClientEvent('MB_Fahrzeugvermitung:openStoredContract', src, contract, true)
end

local function RegisterContractUsableItem()
    if not (Config.ContractItem and Config.ContractItem.Enabled) then return end

    local itemName = Config.ContractItem.Name or 'mietvertrag'

    if Config.Framework == 'qbcore' and QBCore and QBCore.Functions then
        local register = QBCore.Functions.CreateUseableItem or QBCore.Functions.CreateUsableItem
        if register then
            register(itemName, function(src, item)
                OpenContractFromItem(src, item)
            end)
            print(('[MB_Fahrzeugvermitung] Useable Item registriert: %s (QBCore)'):format(itemName))
            return
        end
    end

    if Config.Framework == 'esx' and ESX and ESX.RegisterUsableItem then
        ESX.RegisterUsableItem(itemName, function(src)
            OpenContractFromItem(src)
        end)
        print(('[MB_Fahrzeugvermitung] Useable Item registriert: %s (ESX)'):format(itemName))
        return
    end

    -- ox_inventory öffnet das Item über den client.event-Eintrag in ox_inventory_item.lua.
    print(('[MB_Fahrzeugvermitung] Item-Öffnung läuft über Inventar-Definition oder konnte nicht automatisch registriert werden: %s'):format(itemName))
end

local function LoadAdminStore()
    local file = Config.AdminStorageFile or 'data/admin_vehicles.json'
    local raw = LoadResourceFile(GetCurrentResourceName(), file)
    if raw and raw ~= '' then
        local ok, decoded = pcall(json.decode, raw)
        if ok and type(decoded) == 'table' then
            adminStore = NormalizeStore(decoded)
        else
            print(('[MB_Fahrzeugvermitung] %s konnte nicht gelesen werden. Starte mit leerem Admin-Speicher.'):format(file))
            ReportError({
                description = ('Admin-Daten konnten nicht gelesen werden (%s).'):format(file),
                system = 'data/admin_vehicles.json',
                hint = 'JSON-Syntax prüfen oder die Datei mit einem leeren Objekt ersetzen.',
                code = 'admin_store_decode',
                notifyPlayer = false,
            })
            adminStore = { vehicles = {}, locations = {}, deletedConfigVehicles = {} }
        end
    else
        adminStore = { vehicles = {}, locations = {}, deletedConfigVehicles = {} }
        SaveResourceFile(GetCurrentResourceName(), file, json.encode(adminStore), -1)
    end
    ApplyAdminStoreToConfig()
end


local function EnsureAdminDeletedStore()
    adminStore.deletedConfigVehicles = adminStore.deletedConfigVehicles or {}
end

local function IsConfigVehicleDeleted(locationName, vehicleKey)
    EnsureAdminDeletedStore()
    if adminStore.deletedConfigVehicles['*'] and adminStore.deletedConfigVehicles['*'][vehicleKey] then
        return true
    end
    return adminStore.deletedConfigVehicles[locationName] and adminStore.deletedConfigVehicles[locationName][vehicleKey] == true
end

local function MarkConfigVehicleDeleted(locationName, vehicleKey)
    EnsureAdminDeletedStore()
    locationName = Trim(locationName)
    if locationName == '' then locationName = '*' end
    adminStore.deletedConfigVehicles[locationName] = adminStore.deletedConfigVehicles[locationName] or {}
    adminStore.deletedConfigVehicles[locationName][vehicleKey] = true
end

local function UnmarkConfigVehicleDeleted(locationName, vehicleKey)
    EnsureAdminDeletedStore()
    locationName = Trim(locationName)
    if locationName ~= '' and adminStore.deletedConfigVehicles[locationName] then
        adminStore.deletedConfigVehicles[locationName][vehicleKey] = nil
    end
    if adminStore.deletedConfigVehicles['*'] then
        adminStore.deletedConfigVehicles['*'][vehicleKey] = nil
    end
end


local function SaveAdminStore()
    local file = Config.AdminStorageFile or 'data/admin_vehicles.json'
    SaveResourceFile(GetCurrentResourceName(), file, json.encode(adminStore), -1)
end

local function IsVehicleKeyList(value)
    if type(value) ~= 'table' then return false end
    if value.key or value.coords or value.label or value.pedModel or value.source then return false end
    return true
end

local function FindStoredLocation(locKey)
    locKey = Trim(locKey)
    if locKey == '' then return nil, nil end
    adminStore.locations = adminStore.locations or {}
    for i, loc in ipairs(adminStore.locations) do
        if type(loc) == 'table' and (loc.key == locKey or loc.name == locKey) then
            return loc, i
        end
    end
    return nil, nil
end

local function AddVehicleToLocation(locKey, vehicleKey)
    local loc, index = FindStoredLocation(locKey)
    if loc then
        loc.vehicles = loc.vehicles or {}
        if not TableContains(loc.vehicles, vehicleKey) then
            loc.vehicles[#loc.vehicles + 1] = vehicleKey
            adminStore.locations[index] = loc
        end
        return true
    end

    local list = adminStore.locations[locKey]
    if not IsVehicleKeyList(list) then list = {} end
    if not TableContains(list, vehicleKey) then
        list[#list + 1] = vehicleKey
    end
    adminStore.locations[locKey] = list
    return true
end

local function RemoveVehicleFromStoredLocations(vehicleKey)
    adminStore.locations = adminStore.locations or {}
    for i, loc in ipairs(adminStore.locations) do
        if type(loc) == 'table' and type(loc.vehicles) == 'table' then
            local cleanList = {}
            for _, existingKey in ipairs(loc.vehicles) do
                if existingKey ~= vehicleKey then cleanList[#cleanList + 1] = existingKey end
            end
            loc.vehicles = cleanList
            adminStore.locations[i] = loc
        end
    end
    for locName, list in pairs(adminStore.locations) do
        if type(locName) == 'string' and IsVehicleKeyList(list) then
            local cleanList = {}
            for _, existingKey in ipairs(list) do
                if existingKey ~= vehicleKey then cleanList[#cleanList + 1] = existingKey end
            end
            adminStore.locations[locName] = cleanList
        end
    end
end

local function GetVehicle(key)
    if adminStore.vehicles and adminStore.vehicles[key] then
        return adminStore.vehicles[key], true
    end
    return Config.Vehicles[key], false
end


local function GetLocationVehicleKeys(location)
    local out, seen = {}, {}

    local function addKey(key)
        if key and not seen[key] then
            seen[key] = true
            out[#out + 1] = key
        end
    end

    for _, key in ipairs(location.vehicles or {}) do
        addKey(key)
    end

    local extra = adminStore.locations and adminStore.locations[location.name]
    if type(extra) == 'table' then
        for _, key in ipairs(extra) do
            if GetVehicle(key) then
                addKey(key)
            end
        end
    end

    return out
end


local function GetLocationsForVehicle(key)
    local out, seen = {}, {}
    for _, loc in ipairs(Config.RentalLocations or {}) do
        if TableContains(loc.vehicles or {}, key) then
            out[#out + 1] = loc.name
            seen[loc.name] = true
        end
        local extra = adminStore.locations and adminStore.locations[loc.name]
        if type(extra) == 'table' and TableContains(extra, key) and not seen[loc.name] then
            out[#out + 1] = loc.name
            seen[loc.name] = true
        end
    end

    if type(adminStore) == 'table' and type(adminStore.locations) == 'table' then
        for _, loc in ipairs(adminStore.locations) do
            if type(loc) == 'table' and loc.key then
                local locKey = loc.key
                local vehicles = loc.vehicles or {}
                if TableContains(vehicles, key) and not seen[locKey] then
                    out[#out + 1] = locKey
                    seen[locKey] = true
                end
            end
        end
    end

    return out
end

local function VehiclePayload(key, vehicle, custom)
    return {
        key = key,
        label = vehicle.label or key,
        model = vehicle.model or key,
        price = tonumber(vehicle.price) or 0,
        category = vehicle.category or 'Fahrzeug',
        image = vehicle.image or '',
        custom = custom == true,
        locations = GetLocationsForVehicle(key),
    }
end

local function BuildLocationPayload(locationName, src)
    local loc = FindLocation(locationName)
    if not loc then return nil end

    local vehicles = {}
    for _, key in ipairs(GetLocationVehicleKeys(loc)) do
        local vehicle, custom = GetVehicle(key)
        if vehicle then
            vehicles[#vehicles + 1] = VehiclePayload(key, vehicle, custom)
        end
    end

    return {
        locationLabel = loc.label,
        locationName = loc.name or loc.key,
        playerName = src and GetCharacterName(src) or nil,
        vehicles = vehicles,
        locations = BuildAdminLocations(),
        durations = GetRentalDurations(),
        payments = Config.PaymentMethods,
    }
end

local function BuildAdminPayload()
    local vehicles, seen = {}, {}

    for key, vehicle in pairs(Config.Vehicles) do
        vehicles[#vehicles + 1] = VehiclePayload(key, adminStore.vehicles[key] or vehicle, adminStore.vehicles[key] ~= nil)
        seen[key] = true
    end

    for key, vehicle in pairs(adminStore.vehicles or {}) do
        if not seen[key] then
            vehicles[#vehicles + 1] = VehiclePayload(key, vehicle, true)
            seen[key] = true
        end
    end

    table.sort(vehicles, function(a, b)
        return tostring(a.label):lower() < tostring(b.label):lower()
    end)

    local locations = BuildAdminLocations()
    local rentals = {}
    for src, rental in pairs(activeRentals) do
        rentals[#rentals + 1] = {
            src = src,
            player = GetCharacterName(src),
            vehicle = rental.vehicleLabel or rental.vehicleKey or 'Fahrzeug',
            plate = rental.plate or '—',
            location = rental.locationLabel or rental.locationName or '—',
            remaining = math.max(0, (rental.expireAt or os.time()) - os.time()),
        }
    end

    table.sort(rentals, function(a, b) return (a.remaining or 0) < (b.remaining or 0) end)

    return {
        vehicles = vehicles,
        locations = locations,
        durations = GetRentalDurations(),
        payments = Config.PaymentMethods or {},
        rentals = rentals,
        settings = {
            cooldown = Config.Cooldown or 0,
            maxActive = Config.MaxActiveRentalsPerPlayer or 1,
            warningTime = Config.ExpireWarningTime or 60,
        },
        stats = {
            total = rentalStats.total or 0,
            revenue = rentalStats.revenue or 0,
            history = rentalHistory,
        },
        errors = MBErrors and MBErrors.GetLog and MBErrors.GetLog() or {},
        errorUnread = MBErrors and MBErrors.GetUnreadCount and MBErrors.GetUnreadCount() or 0,
    }
end

local function IsValidLocationName(name)
    return FindLocation(name) ~= nil
end

local function IsAllowedImagePath(image)
    image = Trim(image)
    if image == '' then return true end
    if image:find('<', 1, true) or image:find('>', 1, true) or image:find('\"', 1, true) or image:find("'", 1, true) then return false end
    if image:match('^//') then return true end
    if image:match('^https?://') then return true end
    if image:match('^nui://') then return true end
    if image:match('^data:image/[A-Za-z0-9%+%-%._]+;base64,') then return true end
    if image:match('^img/[A-Za-z0-9_%-%.%/%?%&%=%:]+$') then return true end
    local lower = image:lower()
    if lower:match('^[a-z0-9_%-%.]+%.png$') or lower:match('^[a-z0-9_%-%.]+%.jpg$') or lower:match('^[a-z0-9_%-%.]+%.jpeg$') or lower:match('^[a-z0-9_%-%.]+%.webp$') or lower:match('^[a-z0-9_%-%.]+%.gif$') or lower:match('^[a-z0-9_%-%.]+%.svg$') then return true end
    return false
end

local function IsAdmin(src)
    if src == 0 then return true end

    if Config.AdminAce and Config.AdminAce ~= '' and IsPlayerAceAllowed(src, Config.AdminAce) then
        return true
    end

    local playerObj = GetPlayerObj(src)
    if not playerObj then return false end

    if Config.Framework == 'esx' and playerObj.getGroup then
        local group = playerObj.getGroup()
        for _, allowed in ipairs(Config.AdminGroups or {}) do
            if group == allowed then return true end
        end
    elseif Config.Framework == 'qbcore' and QBCore and QBCore.Functions and QBCore.Functions.HasPermission then
        for _, allowed in ipairs(Config.AdminGroups or {}) do
            if QBCore.Functions.HasPermission(src, allowed) then return true end
        end
    end

    return false
end

local function ReportError(opts)
    if MBErrors and MBErrors.Report then
        return MBErrors.Report(opts)
    end
end

MBErrors.SetCallbacks({
    isAdmin = IsAdmin,
    getPlayerName = GetCharacterName,
})
MBErrors.Load()

local function DenyRental(src, message, reportOpts)
    if reportOpts then
        reportOpts.src = reportOpts.src or src
        ReportError(reportOpts)
    end
    TriggerClientEvent('MB_Fahrzeugvermitung:denied', src, message)
end

local function NotifyAdmin(src, message, typ)
    TriggerClientEvent('MB_Fahrzeugvermitung:adminNotify', src, message, typ or 'success')
end

local function GeneratePlate()
    local chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    local plate = 'MV'
    for _ = 1, 6 do
        local i = math.random(1, #chars)
        plate = plate .. chars:sub(i, i)
    end
    return plate
end

local function AddRentalHistory(data)
    rentalStats.total = (rentalStats.total or 0) + 1
    rentalStats.revenue = (rentalStats.revenue or 0) + (tonumber(data.price) or 0)

    table.insert(rentalHistory, 1, {
        time = os.date('%d.%m. %H:%M'),
        player = data.player or 'Unbekannt',
        vehicle = data.vehicleLabel or 'Fahrzeug',
        location = data.location or '—',
        minutes = data.minutes or 0,
        price = data.price or 0,
    })

    while #rentalHistory > 20 do
        table.remove(rentalHistory)
    end
end

local function LogRental(data)
    if not Config.UseDatabase then return end
    local ok, err = pcall(function()
        exports.oxmysql:insert(
            ('INSERT INTO %s (identifier, location, vehicle, plate, price, minutes, payment) VALUES (?, ?, ?, ?, ?, ?, ?)'):format(Config.DatabaseTable),
            { data.identifier, data.location, data.vehicleLabel, data.plate, data.price, data.minutes, data.payment }
        )
    end)
    if not ok then
        print('[MB_Fahrzeugvermitung] Datenbank-Logging fehlgeschlagen: ' .. tostring(err))
        ReportError({
            description = 'Miet-Historie konnte nicht in die Datenbank geschrieben werden.',
            system = 'oxmysql / Miet-Historie',
            hint = 'MySQL-Verbindung prüfen. Fehler: ' .. tostring(err),
            code = 'db_rental_log',
            notifyPlayer = false,
        })
    end
end

LoadAdminStore()
LoadContractStore()

Config.RentalDurations = NormalizeDurations(Config.RentalDurations or {})

CreateThread(function()
    RunAutoDatabaseSetup()
end)

RegisterContractUsableItem()

-- Delayed item registration: falls ESX/QBCore beim Laden noch nicht komplett bereit ist.
CreateThread(function()
    Wait(2500)
    RegisterContractUsableItem()
end)

RegisterNetEvent('MB_Fahrzeugvermitung:showContractToPlayer', function(contractId, targetSrc)
    local src = source
    targetSrc = tonumber(targetSrc)

    if not contractId or not targetSrc then
        NotifyPlayer(src, 'Ungültiger Zielspieler.', 'error')
        return
    end

    local contract = GetContractById(tostring(contractId))
    if not contract or contract.identifier ~= GetIdentifier(src) then
        NotifyPlayer(src, 'Du besitzt diesen Mietvertrag nicht.', 'error')
        return
    end

    if not GetPlayerName(targetSrc) then
        NotifyPlayer(src, 'Der Zielspieler ist nicht verfügbar.', 'error')
        return
    end

    TriggerClientEvent('MB_Fahrzeugvermitung:openStoredContract', targetSrc, contract, false)
    NotifyPlayer(src, 'Mietvertrag gezeigt.', 'success')
    NotifyPlayer(targetSrc, ('%s hat dir einen Mietvertrag gezeigt.'):format(GetCharacterName(src)), 'inform')
end)


RegisterNetEvent('MB_Fahrzeugvermitung:openContractItem', function(contractId)
    local src = source
    local identifier = GetIdentifier(src)
    contractId = Trim(contractId)

    local contract = nil

    -- QBCore / ox_inventory: Vertrags-ID kommt über Item-Metadaten
    if contractId ~= '' then
        contract = GetContractById(contractId)
    end

    -- Standard ESX hat oft keine Item-Metadaten:
    -- Dann wird der neueste Vertrag des Spielers geöffnet.
    if not contract or contract.identifier ~= identifier then
        contract = GetLatestPlayerContract(identifier)
    end

    if not contract then
        NotifyPlayer(src, 'Kein Mietvertrag gefunden. Du bekommst einen Vertrag erst nach erfolgreicher Miete.', 'error')
        return
    end

    TriggerClientEvent('MB_Fahrzeugvermitung:openStoredContract', src, contract, true)
end)



-- ============================================================
-- ADMIN-ORTE / NPC-STANDORTE
-- Muss VOR requestAdminData/adminAction definiert sein.
-- ============================================================

function BuildAdminLocations()
    local list = {}

    -- Config-Standorte anzeigen
    for _, loc in ipairs(Config.RentalLocations or {}) do
        local coords = nil
        local heading = 0.0

        if loc.npc and loc.npc.coords then
            coords = loc.npc.coords
            heading = coords.w or loc.heading or 0.0
        elseif loc.marker and loc.marker.coords then
            coords = loc.marker.coords
            heading = loc.heading or 0.0
        elseif loc.coords then
            coords = loc.coords
            heading = loc.heading or 0.0
        end

        list[#list + 1] = {
            key = loc.name or loc.key or ('config_' .. tostring(#list + 1)),
            name = loc.name or loc.key or ('config_' .. tostring(#list + 1)),
            label = loc.label or loc.name or 'Mietstation',
            coords = {
                x = coords and (coords.x or coords[1]) or 0.0,
                y = coords and (coords.y or coords[2]) or 0.0,
                z = coords and (coords.z or coords[3]) or 0.0
            },
            heading = heading,
            pedModel = (loc.npc and loc.npc.model) or (Config.AdminLocationPed and Config.AdminLocationPed.DefaultModel) or 's_m_m_autoshop_01',
            vehicles = loc.vehicles or {},
            source = 'config',
            spawnPoint = loc.spawnPoint and {
                x = loc.spawnPoint.x or loc.spawnPoint[1],
                y = loc.spawnPoint.y or loc.spawnPoint[2],
                z = loc.spawnPoint.z or loc.spawnPoint[3],
                heading = loc.spawnPoint.w or loc.spawnPoint.heading or loc.spawnPoint[4] or heading,
            } or nil,
        }
    end

    -- Ingame erstellte Standorte anzeigen
    if type(adminStore) == 'table' and type(adminStore.locations) == 'table' then
        for _, loc in ipairs(adminStore.locations) do
            if type(loc) == 'table' and loc.key then
                list[#list + 1] = loc
            end
        end
    end

    return list
end


local function NormalizeAdminLocation(data)
    data = data or {}

    local key = Trim(data.key)
    if key == '' then
        key = ('loc_%s_%s'):format(os.time(), math.random(1000, 9999))
    end

    local name = Trim(data.name or data.label)
    if name == '' then
        name = 'Mietstation'
    end

    local x = tonumber(data.x) or tonumber(data.coords and data.coords.x) or 0.0
    local y = tonumber(data.y) or tonumber(data.coords and data.coords.y) or 0.0
    local z = tonumber(data.z) or tonumber(data.coords and data.coords.z) or 0.0
    local heading = tonumber(data.heading) or 0.0

    local pedModel = Trim(data.pedModel)
    if pedModel == '' then
        pedModel = (Config.AdminLocationPed and Config.AdminLocationPed.DefaultModel) or 's_m_m_autoshop_01'
    end

    local spawnX = tonumber(data.spawnX) or tonumber(data.spawnPoint and data.spawnPoint.x)
    local spawnY = tonumber(data.spawnY) or tonumber(data.spawnPoint and data.spawnPoint.y)
    local spawnZ = tonumber(data.spawnZ) or tonumber(data.spawnPoint and data.spawnPoint.z)
    local spawnHeading = tonumber(data.spawnHeading) or tonumber(data.spawnPoint and (data.spawnPoint.heading or data.spawnPoint.w))

    local loc = {
        key = key,
        name = name,
        label = name,
        coords = { x = x, y = y, z = z },
        heading = heading,
        pedModel = pedModel,
        source = 'admin'
    }

    if spawnX and spawnY and spawnZ then
        loc.spawnPoint = {
            x = spawnX,
            y = spawnY,
            z = spawnZ,
            heading = spawnHeading or heading,
        }
    end

    return loc
end

local function SaveAdminLocation(data)
    adminStore.locations = adminStore.locations or {}
    local loc = NormalizeAdminLocation(data)

    for i, existing in ipairs(adminStore.locations) do
        if existing.key == loc.key then
            loc.vehicles = existing.vehicles
            adminStore.locations[i] = loc
            return loc
        end
    end

    adminStore.locations[#adminStore.locations + 1] = loc
    return loc
end

local function DeleteAdminLocation(key)
    key = Trim(key)
    adminStore.locations = adminStore.locations or {}

    for i = #adminStore.locations, 1, -1 do
        if adminStore.locations[i].key == key then
            table.remove(adminStore.locations, i)
            return true
        end
    end

    return false
end

RegisterNetEvent('MB_Fahrzeugvermitung:adminSaveLocation', function(data)
    local src = source
    if not IsAdmin(src) then
        NotifyPlayer(src, 'Keine Berechtigung.', 'error')
        return
    end

    SaveAdminLocation(data or {})
    SaveAdminStore()
    NotifyPlayer(src, 'Ort gespeichert.', 'success')
    TriggerClientEvent('MB_Fahrzeugvermitung:adminDataUpdated', -1)
    TriggerClientEvent('MB_Fahrzeugvermitung:locationsUpdated', -1, BuildAdminLocations())
end)

RegisterNetEvent('MB_Fahrzeugvermitung:adminDeleteLocation', function(key)
    local src = source
    if not IsAdmin(src) then
        NotifyPlayer(src, 'Keine Berechtigung.', 'error')
        return
    end

    if not DeleteAdminLocation(key) then
        NotifyPlayer(src, 'Ort wurde nicht gefunden oder kommt aus der Config.', 'error')
        return
    end

    SaveAdminStore()
    NotifyPlayer(src, 'Ort gelöscht.', 'success')
    TriggerClientEvent('MB_Fahrzeugvermitung:adminDataUpdated', -1)
    TriggerClientEvent('MB_Fahrzeugvermitung:locationsUpdated', -1, BuildAdminLocations())
end)

RegisterNetEvent('MB_Fahrzeugvermitung:requestLocations', function()
    local src = source
    TriggerClientEvent('MB_Fahrzeugvermitung:locationsUpdated', src, BuildAdminLocations())
end)


-- ============================================================
-- UI-DATEN FÜR MIETSTATION
-- ============================================================
RegisterNetEvent('MB_Fahrzeugvermitung:requestOpenData', function(locationName)
    local src = source
    local payload = BuildLocationPayload(locationName, src)
    if not payload then
        DenyRental(src, 'Ungültiger Vermietungsstandort.', {
            description = ('Ungültiger Vermietungsstandort: %s'):format(tostring(locationName)),
            system = 'Miet-UI / Standorte',
            hint = 'Standort im Admin-Panel prüfen oder NPC/Interaktion neu laden.',
            code = 'invalid_rental_location',
            playerMessage = 'An diesem Standort ist die Vermietung derzeit nicht verfügbar. Das Team wurde informiert.',
        })
        return
    end
    TriggerClientEvent('MB_Fahrzeugvermitung:openRentalUI', src, payload)
end)

-- ============================================================
-- ADMINPANEL
-- ============================================================
RegisterNetEvent('MB_Fahrzeugvermitung:requestAdminPanel', function()
    local src = source
    if not IsAdmin(src) then
        NotifyAdmin(src, 'Du hast keine Berechtigung für das Rental-Adminpanel.', 'error')
        TriggerClientEvent('MB_Fahrzeugvermitung:forceCloseUI', src)
        return
    end
    TriggerClientEvent('MB_Fahrzeugvermitung:openAdminPanel', src, BuildAdminPayload())
end)

local function BroadcastAdminPayload(src)
    TriggerClientEvent('MB_Fahrzeugvermitung:openAdminPanel', src, BuildAdminPayload())
end

local function SaveVehicleFromPayload(src, payload, requireLocations)
    payload = type(payload) == 'table' and payload or {}
    local rawKey = Trim(payload.key)
    if rawKey == '' then rawKey = payload.model or payload.label end
    local key = Keyify(rawKey)
    local model = Trim(payload.model)
    local label = Trim(payload.label)
    local price = tonumber(payload.price) or 0
    local category = Trim(payload.category)
    local image = Trim(payload.image)
    local locations = type(payload.locations) == 'table' and payload.locations or nil

    if key == '' or model == '' or label == '' then
        NotifyAdmin(src, 'Key, Spawn-Modell und Name müssen ausgefüllt sein.', 'error')
        return false
    end
    if price < 0 then
        NotifyAdmin(src, 'Der Preis darf nicht negativ sein.', 'error')
        return false
    end
    if category == '' then category = 'Fahrzeug' end
    if image == '' then image = 'img/placeholder.svg' end
    if not IsAllowedImagePath(image) then
        NotifyAdmin(src, 'Bild muss ein direkter http(s)-Bildlink, nui://, data:image oder ein Pfad wie img/datei.png sein.', 'error')
        return false
    end

    local validLocations = nil

    if locations then
        validLocations = {}
        local seenLocations = {}
        for _, locName in ipairs(locations) do
            locName = Trim(locName)
            if IsValidLocationName(locName) and not seenLocations[locName] then
                validLocations[#validLocations + 1] = locName
                seenLocations[locName] = true
            end
        end

        if requireLocations and #validLocations == 0 then
            NotifyAdmin(src, 'Bitte mindestens einen gültigen Standort auswählen.', 'error')
            return false
        end
    end

    adminStore.vehicles[key] = {
        label = label,
        model = model,
        price = math.floor(price),
        category = category,
        image = image,
    }

    if validLocations then
        RemoveVehicleFromStoredLocations(key)
        for _, locName in ipairs(validLocations) do
            AddVehicleToLocation(locName, key)
        end
    end

    SaveAdminStore()
    NotifyAdmin(src, ('Fahrzeug "%s" gespeichert.'):format(label), 'success')
    BroadcastAdminPayload(src)
    return true
end

local function DeleteVehicleByKey(src, key)
    key = Keyify(key)
    if key == '' then
        NotifyAdmin(src, 'Ungültiger Fahrzeug-Key.', 'error')
        return false
    end
    if not adminStore.vehicles[key] then
        NotifyAdmin(src, 'Dieses Fahrzeug kommt aus der Config und kann ingame nicht gelöscht werden. Du kannst es aber überschreiben.', 'error')
        return false
    end

    adminStore.vehicles[key] = nil
    RemoveVehicleFromStoredLocations(key)

    SaveAdminStore()
    NotifyAdmin(src, 'Fahrzeug gelöscht.', 'success')
    BroadcastAdminPayload(src)
    return true
end

local function SetLocationVehicles(src, name, keys)
    name = Trim(name)
    if not IsValidLocationName(name) then
        NotifyAdmin(src, 'Ungültiger Standort.', 'error')
        return false
    end

    local cleanList, seen = {}, {}
    keys = type(keys) == 'table' and keys or {}
    for _, key in ipairs(keys) do
        key = Keyify(key)
        if key ~= '' and GetVehicle(key) and not seen[key] then
            cleanList[#cleanList + 1] = key
            seen[key] = true
        end
    end

    local loc, index = FindStoredLocation(name)
    if loc then
        loc.vehicles = cleanList
        adminStore.locations[index] = loc
    else
        adminStore.locations[name] = cleanList
    end

    SaveAdminStore()
    NotifyAdmin(src, 'Standort-Fahrzeuge gespeichert.', 'success')
    BroadcastAdminPayload(src)
    return true
end

RegisterNetEvent('MB_Fahrzeugvermitung:adminSaveVehicle', function(payload)
    local src = source
    if not IsAdmin(src) then
        NotifyAdmin(src, 'Keine Berechtigung.', 'error')
        TriggerClientEvent('MB_Fahrzeugvermitung:forceCloseUI', src)
        return
    end

    SaveVehicleFromPayload(src, payload, true)
end)


RegisterNetEvent('MB_Fahrzeugvermitung:adminDeleteVehicle', function(vehicleKey, locationName, sourceType)
    local src = source
    if not IsAdmin(src) then
        NotifyPlayer(src, 'Keine Berechtigung.', 'error')
        return
    end

    vehicleKey = Trim(vehicleKey)
    locationName = Trim(locationName)

    if vehicleKey == '' then
        NotifyPlayer(src, 'Ungültiges Fahrzeug.', 'error')
        return
    end

    local removed = false

    -- Admin-Fahrzeuge wirklich aus data/admin_vehicles.json entfernen
    for locName, vehicles in pairs(adminStore.vehicles or {}) do
        if type(vehicles) == 'table' then
            for i = #vehicles, 1, -1 do
                local veh = vehicles[i]
                if veh and (veh.key == vehicleKey or veh.model == vehicleKey) then
                    table.remove(vehicles, i)
                    removed = true
                end
            end
        end
    end

    -- Config-Fahrzeuge können ingame nicht aus config.lua gelöscht werden.
    -- Deshalb werden sie dauerhaft in data/admin_vehicles.json ausgeblendet.
    if not removed or sourceType == 'config' then
        MarkConfigVehicleDeleted(locationName ~= '' and locationName or '*', vehicleKey)
        removed = true
    end

    if not removed then
        NotifyPlayer(src, 'Fahrzeug wurde nicht gefunden.', 'error')
        return
    end

    SaveAdminStore()
    NotifyPlayer(src, 'Fahrzeug gelöscht.', 'success')
    TriggerClientEvent('MB_Fahrzeugvermitung:adminDataUpdated', -1)
end)

RegisterNetEvent('MB_Fahrzeugvermitung:adminAction', function(action, data)
    local src = source
    if not IsAdmin(src) then
        NotifyAdmin(src, 'Keine Berechtigung.', 'error')
        TriggerClientEvent('MB_Fahrzeugvermitung:forceCloseUI', src)
        return
    end

    action = Trim(action)
    data = type(data) == 'table' and data or {}

    if action == 'saveVehicle' then
        SaveVehicleFromPayload(src, data, false)
        return
    end

    if action == 'deleteVehicle' then
        DeleteVehicleByKey(src, data.key)
        return
    end

    if action == 'setLocationVehicles' then
        SetLocationVehicles(src, data.name, data.keys)
        return
    end

    if action == 'saveDurations' then
        local list = type(data.list) == 'table' and data.list or {}
        local clean = NormalizeDurations(list)
        if #clean == 0 then
            NotifyAdmin(src, 'Mindestens eine gültige Mietdauer wird benötigt.', 'error')
            return
        end
        Config.RentalDurations = clean
        adminStore.durations = clean
        SaveAdminStore()
        NotifyAdmin(src, 'Mietdauern gespeichert.', 'success')
        BroadcastAdminPayload(src)
        return
    end

    if action == 'saveSettings' then
        Config.Cooldown = math.max(0, math.floor(tonumber(data.cooldown) or 0))
        Config.MaxActiveRentalsPerPlayer = math.max(1, math.floor(tonumber(data.maxActive) or 1))
        Config.ExpireWarningTime = math.max(10, math.floor(tonumber(data.warningTime) or 60))
        adminStore.settings = {
            cooldown = Config.Cooldown,
            maxActive = Config.MaxActiveRentalsPerPlayer,
            warningTime = Config.ExpireWarningTime,
        }
        SaveAdminStore()
        NotifyAdmin(src, 'Einstellungen gespeichert.', 'success')
        BroadcastAdminPayload(src)
        return
    end

    if action == 'saveLocation' then
        SaveAdminLocation(data or {})
        SaveAdminStore()
        NotifyPlayer(src, 'Ort gespeichert.', 'success')
        TriggerClientEvent('MB_Fahrzeugvermitung:adminDataUpdated', -1)
        TriggerClientEvent('MB_Fahrzeugvermitung:locationsUpdated', -1, BuildAdminLocations())
        return
    end

    if action == 'deleteLocation' then
        if DeleteAdminLocation(data and data.key) then
            SaveAdminStore()
            NotifyPlayer(src, 'Ort gelöscht.', 'success')
            TriggerClientEvent('MB_Fahrzeugvermitung:adminDataUpdated', -1)
            TriggerClientEvent('MB_Fahrzeugvermitung:locationsUpdated', -1, BuildAdminLocations())
        else
            NotifyPlayer(src, 'Ort wurde nicht gefunden oder kommt aus der Config.', 'error')
        end
        return
    end

    if action == 'endRental' then
        local target = tonumber(data.src)
        local rental = target and activeRentals[target]
        if not rental then
            NotifyAdmin(src, 'Diese Miete ist nicht mehr aktiv.', 'error')
            BroadcastAdminPayload(src)
            return
        end
        if rental.netId then
            local entity = NetworkGetEntityFromNetworkId(rental.netId)
            if entity and entity ~= 0 and DoesEntityExist(entity) then
                DeleteEntity(entity)
            end
        end
        activeRentals[target] = nil
        pcall(TriggerClientEvent, 'MB_Fahrzeugvermitung:returned', target)
        NotifyAdmin(src, 'Miete beendet, Fahrzeug entfernt.', 'success')
        BroadcastAdminPayload(src)
        return
    end

    if action == 'extendRental' then
        local target = tonumber(data.src)
        local minutes = math.max(1, math.floor(tonumber(data.minutes) or 15))
        local rental = target and activeRentals[target]
        if not rental then
            NotifyAdmin(src, 'Diese Miete ist nicht mehr aktiv.', 'error')
            BroadcastAdminPayload(src)
            return
        end
        rental.expireAt = (rental.expireAt or os.time()) + (minutes * 60)
        NotifyAdmin(src, ('Miete um %d Minuten verlängert.'):format(minutes), 'success')
        BroadcastAdminPayload(src)
        return
    end

    if action == 'markErrorsSeen' then
        if MBErrors and MBErrors.MarkAllSeen then MBErrors.MarkAllSeen() end
        BroadcastAdminPayload(src)
        return
    end

    if action == 'clearErrors' then
        if MBErrors and MBErrors.Clear then MBErrors.Clear() end
        NotifyAdmin(src, 'Fehlerhistorie geleert.', 'success')
        BroadcastAdminPayload(src)
        return
    end

    NotifyAdmin(src, 'Unbekannte Admin-Aktion.', 'error')
end)

-- ============================================================
-- MIETANFRAGE
-- ============================================================
RegisterNetEvent('MB_Fahrzeugvermitung:requestRental', function(payload)
    local src = source
    local identifier = GetIdentifier(src)
    payload = type(payload) == 'table' and payload or {}

    if Config.Cooldown and Config.Cooldown > 0 then
        local last = lastRentalTime[identifier]
        if last and (os.time() - last) < (Config.Cooldown * 60) then
            local remaining = math.ceil((Config.Cooldown * 60 - (os.time() - last)) / 60)
            TriggerClientEvent('MB_Fahrzeugvermitung:denied', src, ('Du musst noch %d Minute(n) warten, bevor du erneut mieten kannst.'):format(remaining))
            return
        end
    end

    local activeCount = 0
    for s, _ in pairs(activeRentals) do
        if GetIdentifier(s) == identifier then activeCount = activeCount + 1 end
    end
    if activeCount >= Config.MaxActiveRentalsPerPlayer then
        TriggerClientEvent('MB_Fahrzeugvermitung:denied', src, 'Du hast bereits ein aktives Mietfahrzeug.')
        return
    end

    local location = FindLocation(payload.location)
    if not location then
        TriggerClientEvent('MB_Fahrzeugvermitung:denied', src, 'Ungültiger Vermietungsstandort.')
        return
    end

    local vehicleAllowed = TableContains(GetLocationVehicleKeys(location), payload.vehicleKey)
    local vehicle = GetVehicle(payload.vehicleKey)
    if not vehicleAllowed or not vehicle then
        TriggerClientEvent('MB_Fahrzeugvermitung:denied', src, 'Dieses Fahrzeug ist an diesem Standort nicht verfügbar.')
        return
    end

    local duration = FindDuration(tonumber(payload.durationIdx) or -1)
    if not duration then
        TriggerClientEvent('MB_Fahrzeugvermitung:denied', src, 'Ungültige Mietdauer.')
        return
    end

    local payment = FindPayment(payload.paymentId)
    if not payment then
        TriggerClientEvent('MB_Fahrzeugvermitung:denied', src, 'Ungültige Zahlungsmethode.')
        return
    end

    local totalPrice = math.floor((tonumber(vehicle.price) or 0) * duration.multiplier)
    local balance = GetMoney(src, payment.account)
    if balance < totalPrice then
        TriggerClientEvent('MB_Fahrzeugvermitung:denied', src, ('Nicht genug Geld (%s benötigt: %d€).'):format(payment.label, totalPrice))
        return
    end

    RemoveMoney(src, payment.account, totalPrice)

    local plate = GeneratePlate()
    local rentalId = ('%s-%d'):format(identifier, os.time())
    local expireAt = os.time() + (duration.minutes * 60)

    activeRentals[src] = {
        rentalId     = rentalId,
        netId        = nil,
        expireAt     = expireAt,
        locationName = location.name,
        locationLabel = location.label,
        vehicleKey   = payload.vehicleKey,
        vehicleLabel = vehicle.label,
        plate        = plate,
        price        = totalPrice,
        minutes      = duration.minutes,
    }

    lastRentalTime[identifier] = os.time()

    local historyData = {
        identifier   = identifier,
        player       = GetCharacterName(src),
        location     = location.label,
        vehicleLabel = vehicle.label,
        plate        = plate,
        price        = totalPrice,
        minutes      = duration.minutes,
        payment      = payment.label,
    }

    local signatureDataUrl = NormalizeSignatureDataUrl(payload.signatureDataUrl)
    local contractData = BuildContractPayload(src, rentalId, location.label, vehicle, duration, payment, totalPrice, plate, signatureDataUrl)
    AddContractRecord(contractData)

    AddRentalHistory(historyData)
    LogRental(historyData)

    if Config.ContractItem and Config.ContractItem.Enabled then
        local gaveItem = GiveContractItem(src, contractData)
        if gaveItem then
            NotifyPlayer(src, 'Du hast den unterschriebenen Mietvertrag als Item erhalten.', 'success')
        else
            ReportError({
                src = src,
                description = 'Mietvertrag gespeichert, aber die Item-Vergabe ist fehlgeschlagen.',
                system = 'Inventar / Mietvertrag-Item',
                hint = 'Prüfe ox_inventory-Item-Definition und Inventarplatz des Spielers.',
                code = 'contract_item_grant_failed',
                severity = 'warning',
            })
            NotifyPlayer(src, 'Mietvertrag wurde gespeichert, aber das Item konnte nicht ins Inventar gelegt werden.', 'warning')
        end
    end

    TriggerClientEvent('MB_Fahrzeugvermitung:approved', src, {
        rentalId        = rentalId,
        model           = vehicle.model,
        vehicleLabel    = vehicle.label,
        spawnPoint      = location.spawnPoint,
        durationMinutes = duration.minutes,
        expireAt        = expireAt,
        plate           = plate,
    })

    CreateThread(function()
        local warnAt = math.max(0, (expireAt - Config.ExpireWarningTime) - os.time())
        Wait(warnAt * 1000)

        if activeRentals[src] and activeRentals[src].rentalId == rentalId then
            pcall(TriggerClientEvent, 'MB_Fahrzeugvermitung:warnExpire', src, Config.ExpireWarningTime)
        end

        local remaining = math.max(0, expireAt - os.time())
        Wait(remaining * 1000)

        local rental = activeRentals[src]
        if rental and rental.rentalId == rentalId then
            if Config.DeleteVehicleOnExpire and rental.netId then
                local entity = NetworkGetEntityFromNetworkId(rental.netId)
                if entity and entity ~= 0 and DoesEntityExist(entity) then
                    DeleteEntity(entity)
                end
            end
            pcall(TriggerClientEvent, 'MB_Fahrzeugvermitung:expired', src)
            activeRentals[src] = nil
        end
    end)
end)

-- ============================================================
-- FAHRZEUG-NETID REGISTRIEREN
-- ============================================================
RegisterNetEvent('MB_Fahrzeugvermitung:registerVehicle', function(rentalId, netId)
    local src = source
    local rental = activeRentals[src]
    if rental and rental.rentalId == rentalId then
        rental.netId = netId
    end
end)

AddEventHandler('playerDropped', function()
    -- activeRentals[source] bewusst NICHT gelöscht, damit der Timer weiterläuft
end)


-- === MB_SAFE_UI_OPEN ===
local function MB_SAFE_NormalizeVehicle(v, source)
    if not v then return nil end

    local key = v.key or v.model or v.name
    if not key then return nil end

    return {
        key = key,
        label = v.label or v.name or v.model or key,
        model = v.model or key,
        category = v.category or 'Fahrzeug',
        price = tonumber(v.price or v.basePrice or v.minutePrice) or 100,
        image = v.image or v.img or 'img/placeholder.svg',
        source = source or v.source or 'config'
    }
end

local function MB_SAFE_GetVehicles()
    local list = {}

    for _, v in pairs(Config.Vehicles or {}) do
        local veh = MB_SAFE_NormalizeVehicle(v, 'config')
        if veh then
            list[#list + 1] = veh
        end
    end

    if type(adminStore) == 'table' and type(adminStore.vehicles) == 'table' then
        if #adminStore.vehicles > 0 then
            for _, v in ipairs(adminStore.vehicles) do
                local veh = MB_SAFE_NormalizeVehicle(v, 'admin')
                if veh then
                    list[#list + 1] = veh
                end
            end
        else
            for _, group in pairs(adminStore.vehicles) do
                if type(group) == 'table' then
                    for _, v in ipairs(group) do
                        local veh = MB_SAFE_NormalizeVehicle(v, 'admin')
                        if veh then
                            list[#list + 1] = veh
                        end
                    end
                end
            end
        end
    end

    if #list == 0 then
        list[#list + 1] = {
            key = 'faggio',
            label = 'Faggio',
            model = 'faggio',
            category = 'Roller',
            price = 100,
            image = 'img/placeholder.svg',
            source = 'fallback'
        }
    end

    return list
end

local function MB_SAFE_GetDurations()
    if Config.Durations and #Config.Durations > 0 then
        return NormalizeDurations(Config.Durations)
    end

    if Config.RentalDurations and #Config.RentalDurations > 0 then
        return GetRentalDurations()
    end

    return NormalizeDurations({
        { minutes = 15, multiplier = 1.0 },
        { minutes = 30, multiplier = 1.8 },
        { minutes = 60, multiplier = 3.2 },
    })
end

local function MB_SAFE_GetPayments()
    if type(Config.PaymentMethods) == 'table' and #Config.PaymentMethods > 0 then
        return Config.PaymentMethods
    end

    if Config.Payments and #Config.Payments > 0 then
        return Config.Payments
    end

    return {
        { id = 'cash', label = 'Bargeld', account = 'money' },
        { id = 'bank', label = 'Bank', account = 'bank' },
    }
end

local function MB_SAFE_GetLocations()
    local list = {}

    if BuildAdminLocations then
        return BuildAdminLocations()
    end

    for _, loc in ipairs(Config.Locations or {}) do
        local c = loc.coords or loc.position or { x = 0.0, y = 0.0, z = 0.0 }

        list[#list + 1] = {
            key = loc.key or loc.name or ('config_' .. tostring(#list + 1)),
            label = loc.label or loc.name or 'Mietstation',
            name = loc.label or loc.name or 'Mietstation',
            coords = {
                x = c.x or c[1] or 0.0,
                y = c.y or c[2] or 0.0,
                z = c.z or c[3] or 0.0
            },
            heading = loc.heading or 0.0,
            pedModel = loc.pedModel or 's_m_m_autoshop_01',
            source = 'config'
        }
    end

    if type(adminStore) == 'table' and type(adminStore.locations) == 'table' then
        for _, loc in ipairs(adminStore.locations) do
            list[#list + 1] = loc
        end
    end

    return list
end

local function MB_SAFE_AdminPayload()
    return {
        vehicles = MB_SAFE_GetVehicles(),
        durations = MB_SAFE_GetDurations(),
        payments = MB_SAFE_GetPayments(),
        locations = MB_SAFE_GetLocations(),
        rentals = {},
        stats = {
            active = 0,
            total = 0,
            revenue = 0,
            history = {}
        },
        settings = { cooldown = 0, deposit = 0 },
        errors = MBErrors and MBErrors.GetLog and MBErrors.GetLog() or {},
        errorUnread = MBErrors and MBErrors.GetUnreadCount and MBErrors.GetUnreadCount() or 0,
    }
end

local function MB_SAFE_OpenAdmin(src)
    if src <= 0 then return end
    TriggerClientEvent('MB_Fahrzeugvermitung:client:forceOpenAdmin', src, MB_SAFE_AdminPayload())
end

RegisterNetEvent('MB_Fahrzeugvermitung:server:forceOpenAdmin', function()
    MB_SAFE_OpenAdmin(source)
end)

RegisterCommand('rentaladmin', function(src)
    MB_SAFE_OpenAdmin(src)
end, false)

RegisterCommand('adminrental', function(src)
    MB_SAFE_OpenAdmin(src)
end, false)

RegisterNetEvent('MB_Fahrzeugvermitung:server:openRentalAtLocation', function(locationKey)
    local src = source
    local payload = BuildLocationPayload(locationKey, src)
    if not payload then
        TriggerClientEvent('MB_Fahrzeugvermitung:denied', src, 'Ungültiger Vermietungsstandort.')
        return
    end

    TriggerClientEvent('MB_Fahrzeugvermitung:client:openRental', src, payload)
end)
-- === /MB_SAFE_UI_OPEN ===


-- ============================================================
-- FIX-ALIASE: Admin öffnen / Daten neu laden
-- ============================================================
RegisterNetEvent('MB_Fahrzeugvermitung:server:openAdmin', function()
    local src = source
    if MB_SAFE_OpenAdmin then
        MB_SAFE_OpenAdmin(src)
    elseif MB_LR_OpenAdmin then
        MB_LR_OpenAdmin(src)
    end
end)

RegisterNetEvent('MB_Fahrzeugvermitung:requestAdminData', function()
    local src = source
    if MB_SAFE_OpenAdmin then
        MB_SAFE_OpenAdmin(src)
    elseif MB_LR_OpenAdmin then
        MB_LR_OpenAdmin(src)
    end
end)

RegisterNetEvent('MB_Fahrzeugvermitung:requestRentalData', function(locationKey)
    local src = source
    TriggerEvent('MB_Fahrzeugvermitung:server:openRentalAtLocation', locationKey)
end)

RegisterNetEvent('MB_Fahrzeugvermitung:reportClientError', function(payload)
    payload = type(payload) == 'table' and payload or {}
    ReportError({
        src = source,
        description = payload.description or 'Client-seitiger Fehler',
        system = payload.system or 'client/main.lua',
        hint = payload.hint or '',
        code = payload.code or 'client_error',
        severity = payload.severity or 'error',
        playerMessage = payload.playerMessage,
        notifyPlayer = payload.notifyPlayer ~= false,
        alertAdmins = payload.alertAdmins ~= false,
    })
end)
