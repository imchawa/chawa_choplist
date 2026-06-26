local isUiOpen = false
local npcPed = nil
local isScrapping = false
local currentScrapIndex = 1
local globalNetId = nil
local globalMatchedSlot = nil
local strippedParts = {}
local activeDelivery = false
local deliveryVehicle = nil
local deliveryBlip = nil
local isTracking = false

local scrapParts = {
    {"wheel_lf", "wheel", 0}, {"wheel_rf", "wheel", 1},
    {"wheel_lr", "wheel", 4}, {"wheel_rr", "wheel", 5},
    {"door_dside_f", "door", 0}, {"door_pside_f", "door", 1},
    {"door_dside_r", "door", 2}, {"door_pside_r", "door", 3},
    {"bonnet", "hood", 4}, {"boot", "trunk", 5}
}

CreateThread(function()
    while true do
        local sleep = 500
        if isScrapping then
            sleep = 0
            if IsControlJustPressed(0, 73) then -- 73 is X
                isScrapping = false
                ClearPedTasks(PlayerPedId())
                exports.qbx_core:Notify("Scrapping paused! Target vehicle to resume.", "error", 10000)
            end
        end
        Wait(sleep)
    end
end)

local classMapping = {
    [0] = "Compacts", [1] = "Sedans", [2] = "SUVs", [3] = "Coupes", [4] = "Muscle",
    [5] = "Sports Classics", [6] = "Sports", [7] = "Super", [8] = "Motorcycles", [9] = "Off-Road",
    [10] = "Industrial", [11] = "Utility", [12] = "Vans", [13] = "Cycles", [14] = "Boats",
    [15] = "Helicopters", [16] = "Planes", [17] = "Service", [18] = "Emergency", [19] = "Military",
    [20] = "Commercial", [21] = "Trains", [22] = "Open Wheel"
}

RegisterNetEvent('chawachopin:client:madnpc', function()
    PlayPedAmbientSpeechNative(npcPed, "GENERIC_INSULT_HIGH", "SPEECH_PARAMS_FORCE")
end)

RegisterNetEvent('chawachopin:client:madnpc2', function()
    PlayPedAmbientSpeechNative(npcPed, "PROVOKE_BUMPED_INTO", "SPEECH_PARAMS_FORCE")
end)

RegisterNetEvent('chawachopin:client:checklist', function()
    TriggerServerEvent("chawachopin:server:checkList")
    ToggleUI(true)
end)

function ToggleUI(status)
    isUiOpen = status
    SetNuiFocus(status, status)
    SendNUIMessage({ type = "ui", status = status })
end

RegisterNetEvent("chawachopin:client:updateList", function(progressData, serverList, playSound)
    SendNUIMessage({ 
        type = "updateList",
        progress = progressData,
        list = serverList,
        playSound = playSound
    })
end)

RegisterNUICallback("closeUI", function(data, cb)
    ToggleUI(false)
    cb('ok')
end)

CreateThread(function()
    Wait(2000)
    TriggerServerEvent("chawachopin:server:requestNpcLocation")
end)

RegisterNetEvent("chawachopin:client:spawnNpcAtLocation", function(coords)
    if DoesEntityExist(npcPed) then DeleteEntity(npcPed) end

    RequestModel(Config.NpcModel)
    while not HasModelLoaded(Config.NpcModel) do Wait(1) end

    npcPed = CreatePed(4, Config.NpcModel, coords.x, coords.y, coords.z, coords.w, false, true)
    SetBlockingOfNonTemporaryEvents(npcPed, true)
    SetEntityInvincible(npcPed, true)
    FreezeEntityPosition(npcPed, true)

    local targetOptions = {
        { name = "get_list", type = "client", event = "chawachopin:client:checklist", icon = "fa-solid fa-clipboard-list", label = "Get Daily List" },
        { name = 'request_elite_delivery', icon = 'fas fa-car-side', label = 'Request VIP Work', onSelect = function() TriggerServerEvent("chawachopin:server:requestEliteMission") end,}
    }

    if Config.AutoWalk == "manual" then
        table.insert(targetOptions, { name = 'turn_in_daily_vehicle_auto', icon = 'fa-solid fa-robot', label = 'Verify Vehicle (Auto Strip)', onSelect = function() VerifyLastVehicle(true) end })
        table.insert(targetOptions, { name = 'turn_in_daily_vehicle_manual', icon = 'fa-solid fa-wrench', label = 'Verify Vehicle (Manual Strip)', onSelect = function() VerifyLastVehicle(false) end })
    else
        table.insert(targetOptions, { name = 'turn_in_daily_vehicle', icon = 'fa-solid fa-magnifying-glass-chart', label = 'Verify Vehicle', onSelect = function() VerifyLastVehicle(Config.AutoWalk) end })
    end

    exports.ox_target:addLocalEntity(npcPed, targetOptions)
end)

function VerifyLastVehicle(isAuto)
    local playerPed = PlayerPedId()
    local lastVehicle = GetVehiclePedIsIn(playerPed, true)

    if not DoesEntityExist(lastVehicle) or lastVehicle == 0 then
        local coords = GetEntityCoords(playerPed)
        lastVehicle = lib.getClosestVehicle(coords, 5.0, true)
    end

    if DoesEntityExist(lastVehicle) and lastVehicle ~= 0 then
        local modelHash = GetEntityModel(lastVehicle)
        local modelName = GetDisplayNameFromVehicleModel(modelHash):lower()
        local classInt = GetVehicleClass(lastVehicle)
        local className = classMapping[classInt] or "Unknown"
        TriggerServerEvent("chawachopin:server:verifyVehicle", NetworkGetNetworkIdFromEntity(lastVehicle), modelName, className, isAuto)
    else
        exports.qbx_core:Notify("No recent or nearby vehicle found to verify!", "error", 5000)
    end
end

local function InterruptibleWait(ms)
    local targetTime = GetGameTimer() + ms
    while GetGameTimer() < targetTime do
        if not isScrapping then return false end
        Wait(0)
    end
    return isScrapping
end

RegisterNetEvent("chawachopin:client:beginScrapSequence", function(netId, matchedSlot, isAuto)
    globalNetId = netId
    globalMatchedSlot = matchedSlot
    local vehicle = NetworkGetEntityFromNetworkId(netId)

    if DoesEntityExist(vehicle) then
        FreezeEntityPosition(vehicle, true)
        exports.qbx_core:Notify("Vehicle secured and ready for teardown.", "primary", 7500)
    end
    TriggerServerEvent("chawachopin:server:getScrapProgress", netId, isAuto)
end)

local CheckAllPartsStripped
local PerformManualScrap
local SetupManualScrapTargets

RegisterNetEvent("chawachopin:client:syncScrapProgress", function(progressTable, isAuto)
    local vehicle = NetworkGetEntityFromNetworkId(globalNetId)
    if not DoesEntityExist(vehicle) then return end

    strippedParts = {}
    local highestIndex = 0

    for key, isStripped in pairs(progressTable) do
        if isStripped then
            local index = tonumber(key) 
            if index then
                local part = scrapParts[index]
                if part then
                    local boneName = part[1]
                    local partType = part[2]
                    local doorIndex = part[3]

                    strippedParts[boneName] = true
                    if index > highestIndex then highestIndex = index end

                    if partType == "wheel" then
                        SetVehicleTyreBurst(vehicle, doorIndex, true, 1000.0)
                        BreakOffVehicleWheel(vehicle, doorIndex, true, false, true, false)
                    elseif partType == "door" or partType == "hood" or partType == "trunk" then
                        SetVehicleDoorBroken(vehicle, doorIndex, true)
                    end
                end
            end
        end
    end

    if isAuto then
        currentScrapIndex = highestIndex + 1
        RunScrapLoop()
    else
        SetupManualScrapTargets(vehicle)
    end
end)

local isTargetingActive = false
local isBusy = false 

CheckAllPartsStripped = function(vehicle, optionNames)
    local allStripped = true
    for _, p in ipairs(scrapParts) do
        local boneName = p[1]
        if not strippedParts[boneName] then
            if GetEntityBoneIndexByName(vehicle, boneName) == -1 then
                strippedParts[boneName] = true
            else
                allStripped = false
                break
            end
        end
    end

    if allStripped then
        isTargetingActive = false 
        if optionNames then
            exports.ox_target:removeLocalEntity(vehicle, optionNames)
        end
        exports.qbx_core:Notify("Vehicle completely stripped! Crush the chassis.", "success", 8000)

        exports.ox_target:addLocalEntity(vehicle, {
            {
                name = 'crush_daily_vehicle',
                icon = 'fa-solid fa-dumpster-fire',
                label = 'Crush Stripped Chassis',
                onSelect = function() 
                    TriggerServerEvent("chawachopin:server:crushVehicle", globalNetId, globalMatchedSlot)
                end
            }
        })
    end
end

PerformManualScrap = function(vehicle, part, index, optionNames)
    if isBusy then return end
    isBusy = true

    local ped = PlayerPedId()
    local boneName = part[1]
    local partType = part[2]
    local doorIndex = part[3]
    local boneIdx = GetEntityBoneIndexByName(vehicle, boneName)

    if boneIdx == -1 then 
        isBusy = false
        return 
    end

    local bonePos = GetEntityBonePosition_2(vehicle, boneIdx)

    TaskGoToCoordAnyMeans(ped, bonePos.x, bonePos.y, bonePos.z, 1.0, 0, 0, 0, 0)

    local timeout = GetGameTimer() + 3000
    while #(GetEntityCoords(ped) - bonePos) > 0.35 and GetGameTimer() < timeout do
        Wait(100)
    end

    ClearPedTasks(ped)
    TaskTurnPedToFaceCoord(ped, bonePos.x, bonePos.y, bonePos.z, 800)
    Wait(500)
    if partType == "door" or partType == "hood" or partType == "trunk" then
        SetVehicleDoorOpen(vehicle, doorIndex, false, false)
    end

    local animDict = (partType == "wheel") and "anim@amb@clubhouse@tutorial@bkr_tut_ig3@" or "mini@repair"
    local animName = (partType == "wheel") and "machinic_loop_mechandplayer" or "fixing_a_ped"

    lib.requestAnimDict(animDict)

    Wait(550)
    TaskPlayAnim(ped, animDict, animName, 8.0, -8.0, -1, 1, 0, false, false, false)

    exports.qbx_core:Notify("Stripping " .. partType .. "... Press X to pause.", "primary", Config.ScrapDuration)

    local success = true
    local scrapTimer = GetGameTimer() + Config.ScrapDuration
    while GetGameTimer() < scrapTimer do
        Wait(0)
        if IsControlJustPressed(0, 73) then
            success = false
            break
        end
    end

    ClearPedTasks(ped)

    if not success then
        isBusy = false
        exports.qbx_core:Notify("Scrapping cancelled.", "error", 5000)
        return 
    end

    if partType == "wheel" then
        SetVehicleTyreBurst(vehicle, doorIndex, true, 1000.0)
        BreakOffVehicleWheel(vehicle, doorIndex, true, false, true, false)
    elseif partType == "door" or partType == "hood" or partType == "trunk" then
        SetVehicleDoorBroken(vehicle, doorIndex, true)
    end

    strippedParts[boneName] = true
    TriggerServerEvent("chawachopin:server:updateScrapProgress", globalNetId, index, partType, false)
    CheckAllPartsStripped(vehicle, optionNames)

    isBusy = false
end

SetupManualScrapTargets = function(vehicle)
    local targetOptions = {}
    local optionNames = {}
    local boneCache = {}

    for i, part in ipairs(scrapParts) do
        local boneName = part[1]
        local partType = part[2]
        local targetName = 'scrap_' .. boneName

        local bIdx = GetEntityBoneIndexByName(vehicle, boneName)
        boneCache[boneName] = bIdx

        table.insert(optionNames, targetName)

        table.insert(targetOptions, {
            name = targetName,
            icon = 'fa-solid fa-wrench',
            label = 'Strip ' .. partType:gsub("^%l", string.upper) .. ' (' .. boneName:gsub("_", " ") .. ')',
            bones = boneName,
            canInteract = function(entity, distance, coords, name)
                if strippedParts[boneName] then return false end
                local boneIdx = boneCache[boneName] or -1
                if boneIdx ~= -1 then
                    local boneCoords = GetEntityBonePosition_2(entity, boneIdx)
                    if #(coords - boneCoords) < 0.3 then return true end
                end
                return false
            end,
            onSelect = function()
                PerformManualScrap(vehicle, part, i, optionNames)
            end
        })
    end

    exports.ox_target:addLocalEntity(vehicle, targetOptions)

    local allStripped = true
    for _, p in ipairs(scrapParts) do
        local boneName = p[1]
        if not strippedParts[boneName] then
            if GetEntityBoneIndexByName(vehicle, boneName) == -1 then
                strippedParts[boneName] = true
            else
                allStripped = false
                break
            end
        end
    end

    if allStripped then
        isTargetingActive = false
        exports.ox_target:removeLocalEntity(vehicle, optionNames)
        exports.qbx_core:Notify("Vehicle completely stripped! Crush the chassis.", "success", 7500)

        exports.ox_target:addLocalEntity(vehicle, {
            { 
                name = 'crush_daily_vehicle', 
                icon = 'fa-solid fa-dumpster-fire', 
                label = 'Crush Stripped Chassis', 
                onSelect = function() TriggerServerEvent("chawachopin:server:crushVehicle", globalNetId, globalMatchedSlot) end 
            }
        })
    else
        exports.qbx_core:Notify("Vehicle verified! Use your target eye on the glowing zones.", "success", 15000)
        isTargetingActive = true
        CreateThread(function()
            while isTargetingActive and DoesEntityExist(vehicle) do
                local sleep = 1000
                local playerCoords = GetEntityCoords(PlayerPedId())
                local vehCoords = GetEntityCoords(vehicle)

                if #(playerCoords - vehCoords) < 15.0 then
                    sleep = 0
                    for _, part in ipairs(scrapParts) do
                        local boneName = part[1]

                        if not strippedParts[boneName] then
                            local boneIdx = boneCache[boneName] or -1
                            if boneIdx ~= -1 then
                                local bonePos = GetEntityBonePosition_2(vehicle, boneIdx)

                                DrawMarker(28, 
                                    bonePos.x, bonePos.y, bonePos.z, 
                                    0.0, 0.0, 0.0, 
                                    0.0, 0.0, 0.0, 
                                    0.15, 0.15, 0.15, 
                                    0, 180, 255, 120, 
                                    false, false, 2, false, nil, nil, false
                                )
                            end
                        end
                    end
                end
                Wait(sleep)
            end
        end)
    end
end

function RunScrapLoop()
    local vehicle = NetworkGetEntityFromNetworkId(globalNetId)
    if not DoesEntityExist(vehicle) then return end
    local ped = PlayerPedId()
    isScrapping = true

    RequestNamedPtfxAsset("core")
    RequestAnimDict("mini@repair")
    RequestAnimDict("anim@amb@clubhouse@tutorial@bkr_tut_ig3@")

    exports.qbx_core:Notify("Stripping started. Press X to pause.", "primary", 30000)

    while currentScrapIndex <= #scrapParts and isScrapping do
        if not DoesEntityExist(vehicle) then 
            exports.qbx_core:Notify("Vehicle lost!", "error", 4000)
            isScrapping = false
            break
        end

        local part = scrapParts[currentScrapIndex]
        local boneIdx = GetEntityBoneIndexByName(vehicle, part[1])
        local partTypeToReward = nil 

        if boneIdx ~= -1 then
            local bonePos = GetEntityBonePosition_2(vehicle, boneIdx)

            TaskGoToCoordAnyMeans(ped, bonePos.x, bonePos.y, bonePos.z, 1.0, 0, 0, 0, 0)

            local timeout = GetGameTimer() + 8000
            while #(GetEntityCoords(ped) - bonePos) > 1.2 and GetGameTimer() < timeout and isScrapping do 
                Wait(0) 
            end

            if not isScrapping then break end

            ClearPedTasks(ped)
            TaskTurnPedToFaceCoord(ped, bonePos.x, bonePos.y, bonePos.z, 800)

            if not InterruptibleWait(800) then break end 

            if part[2] == "door" or part[2] == "hood" or part[2] == "trunk" then
                SetVehicleDoorOpen(vehicle, part[3], false, false)
            end

            local animDict = (part[2] == "wheel") and "anim@amb@clubhouse@tutorial@bkr_tut_ig3@" or "mini@repair"
            local animName = (part[2] == "wheel") and "machinic_loop_mechandplayer" or "fixing_a_ped"

            if not InterruptibleWait(150) then break end
            TaskPlayAnim(ped, animDict, animName, 8.0, -8.0, -1, 1, 0, false, false, false)

            if not InterruptibleWait(Config.ScrapDuration) then break end

            if part[2] == "wheel" then
                SetVehicleTyreBurst(vehicle, part[3], true, 1000.0)
                BreakOffVehicleWheel(vehicle, part[3], true, false, true, false)
            elseif part[2] == "door" or part[2] == "hood" or part[2] == "trunk" then
                SetVehicleDoorBroken(vehicle, part[3], true)
            end

            partTypeToReward = part[2]
        end

        if isScrapping then
            currentScrapIndex = currentScrapIndex + 1
            TriggerServerEvent("chawachopin:server:updateScrapProgress", globalNetId, currentScrapIndex, partTypeToReward, true)
        end

        if not InterruptibleWait(10) then break end
    end

    ClearPedTasks(ped)

    local wasInterrupted = not isScrapping 
    isScrapping = false 

    if wasInterrupted and currentScrapIndex <= #scrapParts then
        exports.ox_target:addLocalEntity(vehicle, {
            {
                name = 'resume_scrap_vehicle',
                icon = 'fa-solid fa-play',
                label = 'Resume Stripping Parts',
                onSelect = function()
                    exports.ox_target:removeLocalEntity(vehicle, 'resume_scrap_vehicle')
                    RunScrapLoop()
                end
            }
        })
    elseif currentScrapIndex > #scrapParts then
        exports.qbx_core:Notify("Vehicle completely stripped! Crushing chassis...", "success", 6000)
        Wait(1500) 
        TriggerServerEvent("chawachopin:server:crushVehicle", globalNetId, globalMatchedSlot)
    end
end

RegisterNetEvent("chawachopin:client:deleteVerifiedVehicle", function(netId)
    if NetworkDoesNetworkIdExist(netId) then
        local vehicle = NetworkGetEntityFromNetworkId(netId)
        if DoesEntityExist(vehicle) then
            SetEntityAsMissionEntity(vehicle, true, true)
            FreezeEntityPosition(vehicle, true)

            for alpha = 255, 0, -5 do
                SetEntityAlpha(vehicle, alpha, false)
                Wait(30)
            end

            TriggerServerEvent('chawachopin:server:deleteVehicle', NetworkGetNetworkIdFromEntity(vehicle))
            exports.qbx_core:Notify("Chassis crushed! List updated.", "success", 7500)
        end
    end
end)

RegisterNetEvent('chawachopin:client:policePingMap', function(coords)
    local pingBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
    local street1, street2 = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local street1name = GetStreetNameFromHashKey(street1)
    local street2name = GetStreetNameFromHashKey(street2)
    exports.qbx_core:Notify(text,'inform', 7500, street1name.. ' ' ..street2name)
    SetBlipSprite(pingBlip, 161)
    SetBlipColour(pingBlip, 1)
    SetBlipScale(pingBlip, 1.5)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("Tracker: Stolen Elite Vehicle")
    EndTextCommandSetBlipName(pingBlip)
    PlaySound(-1, 'Lose_1st', 'GTAO_FM_Events_Soundset', false, 0, true)
    local alpha = 250
    CreateThread(function()
        while alpha > 0 do
            Wait(1200)
            alpha = alpha - 10
            SetBlipAlpha(pingBlip, alpha)
        end
        RemoveBlip(pingBlip)
    end)
end)

local function HandleEliteDropoff(dropoffCoords)
    CreateThread(function()
        local delivered = false
        while not delivered and activeDelivery do
            Wait(0)
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            local dropoffVec3 = vec3(dropoffCoords.x, dropoffCoords.y, dropoffCoords.z)
            local dist = #(coords - dropoffVec3)

            if not isTracking and dist < 50.0 then
                DrawMarker(1, dropoffVec3.x, dropoffVec3.y, dropoffVec3.z + 2.0, 0.0, 0.0, 0.0, 0.0, 180.0, 0.0, 4.0, 4.0, 4.0, 255, 128, 0, 50, false, true, 2, nil, nil, false)
                if dist < 6.0 and IsControlJustReleased(0, 38) then
                    if GetVehiclePedIsIn(ped, false) == deliveryVehicle then
                        delivered = true
                    else
                        exports.qbx_core:Notify("You need to be in the requested vehicle!", "error")
                    end
                end
            end
        end

        if delivered then
            TaskLeaveVehicle(PlayerPedId(), deliveryVehicle, 0)
            Wait(2000)

            for alpha = 255, 0, -5 do
                SetEntityAlpha(deliveryVehicle, alpha, false)
                Wait(30)
            end

            TriggerServerEvent('chawachopin:server:deleteVehicle', NetworkGetNetworkIdFromEntity(deliveryVehicle))
            if deliveryBlip then RemoveBlip(deliveryBlip) end
            TriggerServerEvent("chawachopin:server:completeEliteMission")

            activeDelivery = false
            deliveryVehicle = nil
            deliveryBlip = nil
        end
    end)
end

local function StartEliteVehicleTracking(vehicle, dropoffCoords, durationRemaining)
    if isTracking then return end
    isTracking = true

    local vehName = GetDisplayNameFromVehicleModel(GetEntityModel(vehicle))
    local plateName = GetVehicleNumberPlateText(vehicle)

    if not durationRemaining then
        TriggerServerEvent("chawachopin:server:initialPoliceAlert", vehName, plateName)
        exports.qbx_core:Notify("Tracker active! The police have been alerted. Lay low until the heat dies down.", "error", 20000)

        local minTimeMs = Config.PoliceAlert.MinTime * 60000
        local maxTimeMs = Config.PoliceAlert.MaxTime * 60000
        durationRemaining = math.random(minTimeMs, maxTimeMs)
    end

    local endTime = GetGameTimer() + durationRemaining

    CreateThread(function()
        while isTracking and GetGameTimer() < endTime do
            if DoesEntityExist(vehicle) then
                local currentCoords = GetEntityCoords(vehicle)
                TriggerServerEvent("chawachopin:server:updatePoliceLocation", currentCoords)
                SetVehicleAlarm(vehicle, true)
                StartVehicleAlarm(vehicle)
                SetTimeout(15000, function()
                    SetVehicleAlarm(vehicle, false)
                end)
            else
                isTracking = false
                break
            end
            Wait(Config.PoliceAlert.UpdateInterval)
        end

        if isTracking then 
            isTracking = false
            exports.qbx_core:Notify("The tracker died. The heat is off! Proceed to the drop-off.", "success", 15000)
            deliveryBlip = AddBlipForCoord(dropoffCoords.x, dropoffCoords.y, dropoffCoords.z)
            SetBlipSprite(deliveryBlip, 227)
            SetBlipColour(deliveryBlip, 30)
            SetBlipRoute(deliveryBlip, true)
            BeginTextCommandSetBlipName("STRING")
            AddTextComponentString("Elite Drop-off")
            EndTextCommandSetBlipName(deliveryBlip)
            activeDelivery = true 
        end
    end)
end

RegisterNetEvent("chawachopin:client:startEliteMission", function(netId, modelName, pickupCoords, dropoffCoords)
    if activeDelivery then
        exports.qbx_core:Notify("You already have an active VIP job!", "error")
        return
    end

    activeDelivery = true
    exports.qbx_core:Notify("A high-end vehicle needs moving. Check your GPS.", "success", 15000)

    deliveryBlip = AddBlipForCoord(pickupCoords.x, pickupCoords.y, pickupCoords.z)
    SetBlipSprite(deliveryBlip, 225) 
    SetBlipColour(deliveryBlip, 30) 
    SetBlipRoute(deliveryBlip, true)

    CreateThread(function()
        while not NetworkDoesNetworkIdExist(netId) do Wait(100) end
        exports.qbx_core:Notify("The vehicle is marked on your GPS. Don't scratch it.", "info", 15000)

        local inVehicle = false
        while not inVehicle and activeDelivery do
            Wait(500)
            if not DoesEntityExist(deliveryVehicle) then
                deliveryVehicle = NetworkGetEntityFromNetworkId(netId)
            end

            local ped = PlayerPedId()
            if DoesEntityExist(deliveryVehicle) and GetVehiclePedIsIn(ped, false) == deliveryVehicle then
                inVehicle = true
            end
        end

        if inVehicle then
            TriggerServerEvent("chawachopin:server:trackEliteMission", netId, dropoffCoords, modelName, pickupCoords)
            StartEliteVehicleTracking(deliveryVehicle, dropoffCoords)
            if deliveryBlip then
                RemoveBlip(deliveryBlip)
                deliveryBlip = nil
            end
            HandleEliteDropoff(dropoffCoords)
        end
    end)
end)

RegisterNetEvent("chawachopin:client:recoverEliteMission", function(netId, dropoffCoords, modelName, lastPos)
    exports.qbx_core:Notify("Elite VIP Run paused. Locating vehicle...", "primary", 5000)
    CreateThread(function()
        local veh = nil
        if NetworkDoesNetworkIdExist(netId) then
            veh = NetworkGetEntityFromNetworkId(netId)
        end

        if not DoesEntityExist(veh) then
            local modelHash = GetHashKey(modelName)
            RequestModel(modelHash)
            while not HasModelLoaded(modelHash) do Wait(10) end
            veh = CreateVehicle(modelHash, lastPos.x, lastPos.y, lastPos.z, lastPos.w or 0.0, true, true)
            SetVehicleNumberPlateText(veh, "ELITE")
        end

        local recoveryBlip = AddBlipForEntity(veh)
        SetBlipSprite(recoveryBlip, 225)
        SetBlipColour(recoveryBlip, 30)
        SetBlipRoute(recoveryBlip, true)
        local recovered = false
        while not recovered do
            Wait(1000)
            if IsPedInVehicle(PlayerPedId(), veh, false) then
                recovered = true
                if DoesBlipExist(recoveryBlip) then RemoveBlip(recoveryBlip) end
                deliveryVehicle = veh
                activeDelivery = true
                exports.qbx_core:Notify("Elite VIP Run Resumed. Authorities alerted!", "error")
                StartEliteVehicleTracking(veh, dropoffCoords, (Config.PoliceAlert.MinTime * 60000))
                HandleEliteDropoff(dropoffCoords)
            end
        end
    end)
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    if DoesEntityExist(npcPed) then DeleteEntity(npcPed) end
end)