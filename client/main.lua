local QBCore = nil
local ESX = nil

-- ============================================================
-- FRAMEWORK BOOTSTRAP
-- ============================================================
CreateThread(function()
    if Config.Framework == 'esx' then
        ESX = exports[Config.ESXExport]:getSharedObject()
    elseif Config.Framework == 'qbcore' then
        QBCore = exports[Config.QBExport]:GetCoreObject()
    end
end)

local function Notify(msg, type)
    type = type or 'inform'
    if Config.UseOxLib and lib then
        lib.notify({ description = msg, type = type })
    elseif Config.Framework == 'esx' and ESX then
        ESX.ShowNotification(msg)
    elseif Config.Framework == 'qbcore' and QBCore then
        QBCore.Functions.Notify(msg, type)
    else
        SetNotificationTextEntry('STRING')
        AddTextComponentString(msg)
        DrawNotification(false, false)
    end
end

-- ============================================================
-- STATE
-- ============================================================
local uiOpen = false
local currentLocation = nil
local spawnedPeds = {}
local activeRentalVehicle = nil -- { entity, netId, deadlineTick, totalSeconds, vehicleLabel }
local hudVisible = false

-- ============================================================
-- HILFSFUNKTIONEN: TARGET WRAPPER
-- ============================================================
local function AddTargetToPed(ped, locationData)
    if not Config.UseTarget then return end

    if Config.TargetSystem == 'ox_target' then
        exports.ox_target:addLocalEntity(ped, {
            {
                name = 'MB_Fahrzeugvermitung_' .. locationData.name,
                icon = 'fa-solid fa-car-side',
                label = 'Fahrzeug mieten',
                onSelect = function()
                    OpenRentalUI(locationData)
                end,
            }
        })
    elseif Config.TargetSystem == 'qtarget' then
        exports.qtarget:AddTargetEntity(ped, {
            options = {
                {
                    icon = 'fa-solid fa-car-side',
                    label = 'Fahrzeug mieten',
                    action = function()
                        OpenRentalUI(locationData)
                    end,
                }
            },
            distance = Config.InteractDistance,
        })
    end
end

-- ============================================================
-- NPCs, MARKER, BLIPS ERSTELLEN
-- ============================================================
local function CreateLocationBlip(locationData)
    if not locationData.blip or not locationData.blip.enabled then return end
    local b = locationData.blip
    local blip = AddBlipForCoord(b.coords.x, b.coords.y, b.coords.z)
    SetBlipSprite(blip, b.sprite)
    SetBlipColour(blip, b.color)
    SetBlipScale(blip, b.scale)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(b.label)
    EndTextCommandSetBlipName(blip)
end

local function CreateLocationPed(locationData)
    if not locationData.npc or not locationData.npc.enabled then return end
    local n = locationData.npc

    RequestModel(n.model)
    local tries = 0
    while not HasModelLoaded(n.model) and tries < 100 do
        Wait(10)
        tries = tries + 1
    end
    if not HasModelLoaded(n.model) then return end

    local ped = CreatePed(4, n.model, n.coords.x, n.coords.y, n.coords.z - 1.0, n.coords.w, false, true)
    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedDiesWhenInjured(ped, false)
    SetPedCanPlayAmbientAnims(ped, true)
    SetPedCanRagdollFromPlayerImpact(ped, false)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_STAND_IMPATIENT', 0, true)

    spawnedPeds[#spawnedPeds + 1] = ped

    AddTargetToPed(ped, locationData)

    SetModelAsNoLongerNeeded(n.model)
end

CreateThread(function()
    for _, locationData in pairs(Config.RentalLocations) do
        CreateLocationBlip(locationData)
        CreateLocationPed(locationData)
    end
end)

-- ============================================================
-- MARKER + KEY-INTERAKTION (Fallback, wenn UseTarget = false)
-- ============================================================
if not Config.UseTarget then
    CreateThread(function()
        while true do
            local sleep = 1000
            local playerCoords = GetEntityCoords(PlayerPedId())

            for _, locationData in pairs(Config.RentalLocations) do
                if locationData.marker and locationData.marker.enabled then
                    local dist = #(playerCoords - locationData.marker.coords)
                    if dist < 15.0 then
                        sleep = 0
                        local m = locationData.marker
                        DrawMarker(1, m.coords.x, m.coords.y, m.coords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                            m.size.x, m.size.y, m.size.z, m.color.r, m.color.g, m.color.b, 120, false, true, 2, false, nil, nil, false)

                        if dist < 1.5 then
                            DrawText3D(m.coords.x, m.coords.y, m.coords.z + 1.0, '[E] Fahrzeug mieten')
                            if IsControlJustReleased(0, Config.InteractKey) then
                                OpenRentalUI(locationData)
                            end
                        end
                    end
                end
            end

            Wait(sleep)
        end
    end)

    function DrawText3D(x, y, z, text)
        local onScreen, sx, sy = World3dToScreen2d(x, y, z)
        if onScreen then
            SetTextScale(0.35, 0.35)
            SetTextFont(4)
            SetTextProportional(1)
            SetTextColour(255, 255, 255, 215)
            SetTextEntry('STRING')
            SetTextCentre(true)
            AddTextComponentString(text)
            DrawText(sx, sy)
        end
    end
end

-- ============================================================
-- NUI ÖFFNEN / SCHLIESSEN
-- ============================================================
function OpenRentalUI(locationData)
    if uiOpen then return end
    if activeRentalVehicle then
        Notify('Du hast bereits ein gemietetes Fahrzeug.', 'error')
        return
    end

    currentLocation = locationData
    uiOpen = true
    SetNuiFocus(true, true)

    TriggerServerEvent('MB_Fahrzeugvermitung:getCharacterName')
    TriggerServerEvent('MB_Fahrzeugvermitung:requestOpenData', locationData.name)
end

local function CloseRentalUI()
    uiOpen = false
    currentLocation = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeUI' })
end

local function OpenStoredContract(contractData, allowShow)
    uiOpen = true
    currentLocation = nil
    SetNuiFocus(true, true)

    SendNUIMessage({
        action = 'openStoredContract',
        contract = contractData or {},
        allowShow = allowShow == true
    })
end

local function GetClosestPlayerServerId(maxDistance)
    local myPed = PlayerPedId()
    local myCoords = GetEntityCoords(myPed)
    local closestServerId, closestDistance = nil, nil

    for _, player in ipairs(GetActivePlayers()) do
        if player ~= PlayerId() then
            local targetPed = GetPlayerPed(player)
            if DoesEntityExist(targetPed) then
                local targetCoords = GetEntityCoords(targetPed)
                local dist = #(myCoords - targetCoords)
                if (not closestDistance or dist < closestDistance) and dist <= maxDistance then
                    closestDistance = dist
                    closestServerId = GetPlayerServerId(player)
                end
            end
        end
    end

    return closestServerId, closestDistance
end

RegisterNUICallback('closeUI', function(_, cb)
    CloseRentalUI()
    cb('ok')
end)

-- Daten für die Miet-UI vom Server empfangen. Dadurch funktionieren auch
-- ingame hinzugefügte Fahrzeuge ohne Config-Neustart im Client.
RegisterNetEvent('MB_Fahrzeugvermitung:openRentalUI', function(payload)
    if not uiOpen then return end
    payload = payload or {}
    SendNUIMessage({
        action = 'openUI',
        locationLabel = payload.locationLabel or (currentLocation and currentLocation.label) or 'Standort',
        vehicles = payload.vehicles or {},
        durations = payload.durations or Config.RentalDurations,
        payments = payload.payments or Config.PaymentMethods,
    })
end)

-- Adminpanel öffnen: /rentaladmin
RegisterCommand(Config.AdminCommand or 'rentaladmin', function()
    if uiOpen then return end
    uiOpen = true
    SetNuiFocus(true, true)
    TriggerServerEvent('MB_Fahrzeugvermitung:requestAdminPanel')
end, false)

RegisterNetEvent('MB_Fahrzeugvermitung:openAdminPanel', function(payload)
    if not uiOpen then
        uiOpen = true
        SetNuiFocus(true, true)
    end
    SendNUIMessage({ action = 'openAdmin', data = payload or {}, payload = payload or {} })
end)

RegisterNetEvent('MB_Fahrzeugvermitung:adminNotify', function(message, typ)
    SendNUIMessage({ action = 'adminNotify', message = message, type = typ or 'success' })
    Notify(message, typ == 'error' and 'error' or 'success')
end)

RegisterNetEvent('MB_Fahrzeugvermitung:forceCloseUI', function()
    CloseRentalUI()
end)

RegisterNUICallback('adminSaveVehicle', function(data, cb)
    TriggerServerEvent('MB_Fahrzeugvermitung:adminSaveVehicle', data or {})
    cb({ success = true, stayOpen = true })
end)




RegisterNUICallback('adminDeleteVehicle', function(data, cb)
    TriggerServerEvent('MB_Fahrzeugvermitung:adminDeleteVehicle', data and data.key or '')
    cb({ success = true })
end)

RegisterNUICallback('adminAction', function(data, cb)
    data = data or {}
    TriggerServerEvent('MB_Fahrzeugvermitung:adminAction', data.action or '', data.data or {})
    cb({ success = true })
end)
RegisterNUICallback('showContractToNearest', function(data, cb)
    data = data or {}
    local maxDistance = (Config.ContractItem and Config.ContractItem.ShowDistance) or 3.0
    local targetSrc = GetClosestPlayerServerId(maxDistance)

    if not targetSrc then
        Notify('Kein Spieler in deiner Nähe.', 'error')
        cb({ success = false, reason = 'Kein Spieler in deiner Nähe.' })
        return
    end

    TriggerServerEvent('MB_Fahrzeugvermitung:showContractToPlayer', data.contractId, targetSrc)
    cb({ success = true })
end)


-- Charakternamen vom Server empfangen und an die UI weitergeben
RegisterNetEvent('MB_Fahrzeugvermitung:receiveCharacterName', function(name)
    SendNUIMessage({ action = 'setPlayerName', name = name })
end)
RegisterNetEvent('MB_Fahrzeugvermitung:openStoredContract', function(contractData, allowShow)
    OpenStoredContract(contractData, allowShow)
end)

RegisterNetEvent('MB_Fahrzeugvermitung:notify', function(message, typ)
    Notify(message, typ or 'inform')
end)


local function ExtractContractIdFromItem(itemData, slot)
    local meta = {}

    -- ox_inventory client.event bekommt normalerweise (data, slot).
    -- Die Metadaten liegen je nach Version in slot.metadata oder data.metadata.
    if type(slot) == 'table' and type(slot.metadata) == 'table' then
        meta = slot.metadata
    elseif type(itemData) == 'table' and type(itemData.metadata) == 'table' then
        meta = itemData.metadata
    elseif type(itemData) == 'table' and type(itemData.info) == 'table' then
        meta = itemData.info
    elseif type(itemData) == 'table' then
        meta = itemData
    end

    return meta.contractId or meta.contract_id or meta.id
end

RegisterNetEvent('MB_Fahrzeugvermitung:client:useContractItem', function(itemData, slot)
    TriggerServerEvent('MB_Fahrzeugvermitung:openContractItem', ExtractContractIdFromItem(itemData, slot))
end)

RegisterNetEvent('MB_Fahrzeugvermitung:useContractItem', function(itemData, slot)
    TriggerServerEvent('MB_Fahrzeugvermitung:openContractItem', ExtractContractIdFromItem(itemData, slot))
end)

exports('openContractItem', function(itemData, slot)
    TriggerServerEvent('MB_Fahrzeugvermitung:openContractItem', ExtractContractIdFromItem(itemData, slot))
end)

exports('openMietvertrag', function(itemData, slot)
    TriggerServerEvent('MB_Fahrzeugvermitung:openContractItem', ExtractContractIdFromItem(itemData, slot))
end)

exports('OpenMietvertrag', function(itemData, slot)
    TriggerServerEvent('MB_Fahrzeugvermitung:openContractItem', ExtractContractIdFromItem(itemData, slot))
end)




-- ============================================================
-- VERTRAG UNTERSCHREIBEN -> SERVER ANFRAGEN
-- ============================================================
RegisterNUICallback('signContract', function(data, cb)
    if not currentLocation then
        cb({ success = false, reason = 'Kein Standort ausgewählt.' })
        return
    end

    TriggerServerEvent('MB_Fahrzeugvermitung:requestRental', {
        location         = currentLocation.name,
        vehicleKey       = data.vehicleKey,
        durationIdx      = data.durationIdx,
        paymentId        = data.paymentId,
        signatureDataUrl = data.signatureDataUrl or '',
    })

    cb({ success = true })
end)

-- ============================================================
-- SERVER-ANTWORTEN
-- ============================================================
RegisterNetEvent('MB_Fahrzeugvermitung:denied', function(reason)
    SendNUIMessage({ action = 'rentalDenied', reason = reason })
    Notify(reason, 'error')
end)

RegisterNetEvent('MB_Fahrzeugvermitung:approved', function(rentalData)
    -- rentalData: { model, spawnPoint, durationMinutes, expireAt, plate, rentalId }
    CloseRentalUI()
    SpawnRentalVehicle(rentalData)
end)

-- ============================================================
-- FAHRZEUG SPAWNEN
-- ============================================================
local function GiveVehicleKeys(vehicle, plate)
    if not Config.GiveKeys then return end

    local system = Config.KeysSystem

    if system == 'auto' then
        if GetResourceState('qb-vehiclekeys') == 'started' then
            system = 'qb-vehiclekeys'
        elseif GetResourceState('qs-vehiclekeys') == 'started' then
            system = 'qs-vehiclekeys'
        elseif GetResourceState('wasabi_carlock') == 'started' then
            system = 'wasabi_carlock'
        else
            system = 'none'
        end
    end

    if system == 'qb-vehiclekeys' then
        TriggerEvent('qb-vehiclekeys:client:SetOwner', plate)
    elseif system == 'qs-vehiclekeys' then
        exports['qs-vehiclekeys']:GiveKeys(plate)
    elseif system == 'wasabi_carlock' then
        TriggerEvent('wasabi_carlock:client:GiveKey', plate)
    end
end

function SpawnRentalVehicle(rentalData)
    RequestModel(rentalData.model)
    local tries = 0
    while not HasModelLoaded(rentalData.model) and tries < 200 do
        Wait(10)
        tries = tries + 1
    end
    if not HasModelLoaded(rentalData.model) then
        Notify('Fahrzeugmodell konnte nicht geladen werden.', 'error')
        return
    end

    local sp = rentalData.spawnPoint
    local vehicle = CreateVehicle(rentalData.model, sp.x, sp.y, sp.z, sp.w, true, false)
    SetVehicleOnGroundProperly(vehicle)
    SetVehicleNumberPlateText(vehicle, rentalData.plate)
    SetEntityAsNoLongerNeeded(vehicle)
    SetModelAsNoLongerNeeded(rentalData.model)

    local netId = NetworkGetNetworkIdFromEntity(vehicle)

    GiveVehicleKeys(vehicle, rentalData.plate)

    activeRentalVehicle = {
        entity       = vehicle,
        netId        = netId,
        deadlineTick = GetGameTimer() + (rentalData.durationMinutes * 60000),
        totalSeconds = rentalData.durationMinutes * 60,
        vehicleLabel = rentalData.vehicleLabel,
    }

    TriggerServerEvent('MB_Fahrzeugvermitung:registerVehicle', rentalData.rentalId, netId)

    Notify(('Miete gestartet: %s für %d Minuten.'):format(rentalData.vehicleLabel, rentalData.durationMinutes), 'success')

    -- Spieler in Fahrzeug setzen
    TaskWarpPedIntoVehicle(PlayerPedId(), vehicle, -1)
end

-- ============================================================
-- MIET-DASHBOARD (Tablet-HUD mit Restzeit, nur beim Fahren sichtbar)
-- ============================================================
local function SetHudVisible(visible)
    if hudVisible == visible then return end
    hudVisible = visible
    if not visible then
        SendNUIMessage({ action = 'updateRentalHud', visible = false })
    end
end

CreateThread(function()
    while true do
        local sleep = 1000

        if activeRentalVehicle and DoesEntityExist(activeRentalVehicle.entity) then
            local ped = PlayerPedId()
            local veh = activeRentalVehicle.entity
            local isDriver = GetVehiclePedIsIn(ped, false) == veh and GetPedInVehicleSeat(veh, -1) == ped

            if isDriver then
                sleep = 500
                local remainingMs = activeRentalVehicle.deadlineTick - GetGameTimer()
                local remainingSeconds = math.max(0, math.ceil(remainingMs / 1000))

                hudVisible = true
                SendNUIMessage({
                    action           = 'updateRentalHud',
                    visible          = true,
                    remainingSeconds = remainingSeconds,
                    totalSeconds     = activeRentalVehicle.totalSeconds,
                    vehicleLabel     = activeRentalVehicle.vehicleLabel,
                })
            else
                SetHudVisible(false)
            end
        else
            SetHudVisible(false)
        end

        Wait(sleep)
    end
end)

-- ============================================================
-- ABLAUF-WARNUNG / RÜCKSETZEN
-- ============================================================
RegisterNetEvent('MB_Fahrzeugvermitung:warnExpire', function(secondsLeft)
    Notify(('Deine Miete läuft in %d Sekunden ab!'):format(secondsLeft), 'warning')
end)

RegisterNetEvent('MB_Fahrzeugvermitung:expired', function()
    Notify('Deine Mietzeit ist abgelaufen. Das Fahrzeug wurde entfernt.', 'error')
    activeRentalVehicle = nil
    SetHudVisible(false)
end)

RegisterNetEvent('MB_Fahrzeugvermitung:returned', function()
    activeRentalVehicle = nil
    SetHudVisible(false)
end)

-- ============================================================
-- CLEANUP
-- ============================================================
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    for _, ped in ipairs(spawnedPeds) do
        if DoesEntityExist(ped) then
            DeleteEntity(ped)
        end
    end
end)


-- ============================================================
-- ADMIN-ORTE / NPC-MIETSTATIONEN MIT ox_target
-- ============================================================
local rentalLocations = {}
local rentalPeds = {}

local function VecFromLocation(loc)
    local c = loc and loc.coords or {}
    return vector3(tonumber(c.x) or 0.0, tonumber(c.y) or 0.0, tonumber(c.z) or 0.0)
end

local function LoadPedModel(model)
    local hash = type(model) == 'number' and model or joaat(model or 's_m_m_autoshop_01')
    if not IsModelInCdimage(hash) then
        hash = joaat('s_m_m_autoshop_01')
    end

    RequestModel(hash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do
        Wait(0)
    end

    return hash
end

local function RemoveTargetFromPed(ped)
    if Config.UseOxTarget and GetResourceState(Config.TargetResource or 'ox_target') == 'started' and DoesEntityExist(ped) then
        pcall(function()
            exports.ox_target:removeLocalEntity(ped)
        end)
    end
end

local function DeleteRentalPeds()
    for _, ped in pairs(rentalPeds) do
        if DoesEntityExist(ped) then
            RemoveTargetFromPed(ped)
            DeleteEntity(ped)
        end
    end
    rentalPeds = {}
end

local function OpenRentalFromLocation(loc)
    if not loc then return end

    currentLocation = {
        name = loc.key,
        label = loc.label or loc.name or 'Mietstation'
    }

    TriggerServerEvent('MB_Fahrzeugvermitung:server:openRentalAtLocation', loc.key)
end

local function AddTargetToPed(ped, loc)
    if not DoesEntityExist(ped) then return end

    if not Config.UseOxTarget then
        print('[MB_Fahrzeugvermitung] Config.UseOxTarget ist false. Miet-NPC nutzt kein Target.')
        return
    end

    if GetResourceState(Config.TargetResource or 'ox_target') ~= 'started' then
        print('[MB_Fahrzeugvermitung] ox_target ist nicht gestartet. Bitte ensure ox_target vor MB_Fahrzeugvermitung.')
        return
    end

    exports.ox_target:addLocalEntity(ped, {
        {
            name = ('MB_Fahrzeugvermitung_rent_%s'):format(loc.key),
            icon = 'fa-solid fa-car',
            label = ('Fahrzeuge mieten%s'):format(loc.label and (' - ' .. loc.label) or ''),
            distance = tonumber(Config.AdminLocationPed and Config.AdminLocationPed.InteractDistance) or 2.2,
            onSelect = function()
                OpenRentalFromLocation(loc)
            end
        }
    })
end

local function SpawnRentalPed(loc)
    if not (Config.AdminLocationPed and Config.AdminLocationPed.Enabled) then return end
    if not loc or not loc.key then return end
    if rentalPeds[loc.key] and DoesEntityExist(rentalPeds[loc.key]) then return end

    local coords = VecFromLocation(loc)
    if coords.x == 0.0 and coords.y == 0.0 and coords.z == 0.0 then return end

    local playerCoords = GetEntityCoords(PlayerPedId())
    local spawnDistance = tonumber(Config.AdminLocationPed.SpawnDistance) or 80.0
    if #(playerCoords - coords) > spawnDistance then return end

    local hash = LoadPedModel(loc.pedModel or (Config.AdminLocationPed and Config.AdminLocationPed.DefaultModel) or 's_m_m_autoshop_01')
    local ped = CreatePed(4, hash, coords.x, coords.y, coords.z - 1.0, tonumber(loc.heading) or 0.0, false, true)

    if DoesEntityExist(ped) then
        SetEntityAsMissionEntity(ped, true, true)
        SetBlockingOfNonTemporaryEvents(ped, true)
        SetEntityInvincible(ped, true)
        FreezeEntityPosition(ped, true)

        if Config.AdminLocationPed.Scenario and Config.AdminLocationPed.Scenario ~= '' then
            TaskStartScenarioInPlace(ped, Config.AdminLocationPed.Scenario, 0, true)
        end

        rentalPeds[loc.key] = ped
        AddTargetToPed(ped, loc)
    end

    SetModelAsNoLongerNeeded(hash)
end

local function RefreshRentalLocationPeds()
    for _, loc in ipairs(rentalLocations or {}) do
        SpawnRentalPed(loc)
    end
end

RegisterNetEvent('MB_Fahrzeugvermitung:locationsUpdated', function(locations)
    rentalLocations = locations or {}
    DeleteRentalPeds()
    RefreshRentalLocationPeds()
    print(('[MB_Fahrzeugvermitung] %s Miet-Orte geladen.'):format(#rentalLocations))
end)

RegisterNUICallback('adminSaveLocation', function(data, cb)
    TriggerServerEvent('MB_Fahrzeugvermitung:adminSaveLocation', data)
    cb({ success = true, stayOpen = true })
end)

RegisterNUICallback('adminDeleteLocation', function(data, cb)
    TriggerServerEvent('MB_Fahrzeugvermitung:adminDeleteLocation', data.key)
    cb({ success = true, stayOpen = true })
end)

RegisterNUICallback('getCurrentCoords', function(_, cb)
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    cb({
        success = true,
        x = tonumber(string.format('%.3f', coords.x)),
        y = tonumber(string.format('%.3f', coords.y)),
        z = tonumber(string.format('%.3f', coords.z)),
        heading = tonumber(string.format('%.2f', GetEntityHeading(ped)))
    })
end)

CreateThread(function()
    Wait(1500)
    TriggerServerEvent('MB_Fahrzeugvermitung:requestLocations')
end)

CreateThread(function()
    while true do
        Wait(2500)
        RefreshRentalLocationPeds()
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    DeleteRentalPeds()
end)




-- ============================================================
local function MB_OpenRentalUI(payload)
    payload = payload or {}
    uiOpen = true
    SetNuiFocus(true, true)

    SendNUIMessage({
        action = 'openRental',
        location = payload.location or payload.locationLabel or 'Mietstation',
        locationLabel = payload.locationLabel or payload.location or 'Mietstation',
        playerName = payload.playerName or GetPlayerName(PlayerId()),
        vehicles = payload.vehicles or {},
        durations = payload.durations or {},
        payments = payload.payments or {}
    })
end

local function MB_OpenAdminUI(payload)
    payload = payload or {}
    uiOpen = true
    SetNuiFocus(true, true)

    SendNUIMessage({
        action = 'openAdmin',
        data = payload
    })
end

RegisterNetEvent('MB_Fahrzeugvermitung:openRentalUI', function(payload)
    MB_OpenRentalUI(payload)
end)

RegisterNetEvent('MB_Fahrzeugvermitung:openAdminUI', function(payload)
    MB_OpenAdminUI(payload)
end)

-- Fallback, damit /rentaladmin garantiert am Client ankommt.

-- Falls irgendwo noch /adminrental genutzt wird.


-- ============================================================
-- HARD FIX: UI Öffnung
-- ============================================================
local function MB_SendOpenAdmin(payload)
    payload = payload or {}
    uiOpen = true
    SetNuiFocus(true, true)

    -- Neues Format
    SendNUIMessage({
        action = 'openAdmin',
        data = payload,
        admin = payload
    })

    -- Altes Format, falls script.js dieses erwartet
    SendNUIMessage({
        type = 'openAdmin',
        action = 'adminOpen',
        data = payload,
        admin = payload
    })
end

local function MB_SendOpenRental(payload)
    payload = payload or {}
    uiOpen = true
    SetNuiFocus(true, true)

    SendNUIMessage({
        action = 'openRental',
        type = 'openRental',
        data = payload,
        location = payload.location or payload.locationLabel or 'Mietstation',
        locationLabel = payload.locationLabel or payload.location or 'Mietstation',
        playerName = payload.playerName or GetPlayerName(PlayerId()),
        vehicles = payload.vehicles or {},
        durations = payload.durations or {},
        payments = payload.payments or {}
    })
end

RegisterNetEvent('MB_Fahrzeugvermitung:client:openAdmin', function(payload)
    MB_SendOpenAdmin(payload)
end)

RegisterNetEvent('MB_Fahrzeugvermitung:client:openRental', function(payload)
    MB_SendOpenRental(payload)
end)

-- Kompatibilität mit älteren Versionen
RegisterNetEvent('MB_Fahrzeugvermitung:openAdminUI', function(payload)
    MB_SendOpenAdmin(payload)
end)

RegisterNetEvent('MB_Fahrzeugvermitung:openRentalUI', function(payload)
    MB_SendOpenRental(payload)
end)

RegisterCommand('rentaladmin', function()
    TriggerServerEvent('MB_Fahrzeugvermitung:server:forceOpenAdmin')
end, false)

RegisterCommand('adminrental', function()
    TriggerServerEvent('MB_Fahrzeugvermitung:server:forceOpenAdmin')
end, false)

RegisterNUICallback('requestAdminData', function(_, cb)
    TriggerServerEvent('MB_Fahrzeugvermitung:server:forceOpenAdmin')
    cb({ success = true })
end)

RegisterNUICallback('closeUI', function(_, cb)
    uiOpen = false
    SetNuiFocus(false, false)
    cb({ success = true })
end)


-- === MB_UI_OPEN_LAST_RESORT_CLIENT ===
RegisterNetEvent('MB_Fahrzeugvermitung:client:forceOpenAdmin', function(payload)
    uiOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'forceOpenAdmin',
        data = payload or {}
    })
end)

RegisterCommand('rentaladmin', function()
    TriggerServerEvent('MB_Fahrzeugvermitung:server:forceOpenAdmin')
end, false)

RegisterCommand('adminrental', function()
    TriggerServerEvent('MB_Fahrzeugvermitung:server:forceOpenAdmin')
end, false)
-- === /MB_UI_OPEN_LAST_RESORT_CLIENT ===

