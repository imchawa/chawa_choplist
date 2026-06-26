local vehicleProgress = {}
local scrapSessionRewards = {}
local lockedVehicles = {}
local activeEliteMissions = {}
local jsonFileName = "list_data.json"
local activeNpcLocation = nil
local STREAK_TIMEOUT = Config.StreakTimeout * 3600

function GetPlayerCitizenId(src)
    local player = exports.qbx_core:GetPlayer(src)
    return player and player.PlayerData.citizenid or nil
end

local function SendDiscordScrapLog(src, netId)
    if not Config.DiscordWebhook or Config.DiscordWebhook == "" or Config.DiscordWebhook == "YOUR_DISCORD_WEBHOOK_URL_HERE" then
        return
    end

    local player = exports.qbx_core:GetPlayer(src)
    if not player or not player.PlayerData then return end

    local charInfo = player.PlayerData.charinfo or {}
    local firstName = charInfo.firstname or "Unknown"
    local lastName = charInfo.lastname or "Unknown"
    local cid = player.PlayerData.citizenid or "Unknown"

    local rewardLines = ""
    local sessionData = scrapSessionRewards[netId]

    if sessionData and next(sessionData) then
        for itemName, counts in pairs(sessionData) do
            local secured = counts.secured or 0
            local dropped = counts.dropped or 0

            local line = string.format("• **%s**: x%d", itemName, secured)
            if dropped > 0 then
                line = line .. string.format(" *(x%d dropped - Overweight)*", dropped)
            end
            rewardLines = rewardLines .. line .. "\n"
        end
    else
        rewardLines = "*No rewards were earned from rolls.*"
    end

    local lockData = lockedVehicles[netId] or {}
    local multiplierStr = lockData.multiplier and string.format("x%.1f", lockData.multiplier) or "x1.0"
    local modeStr = lockData.isAuto and "🤖 Auto Teardown" or "🖐️ Manual Teardown"

    local discordEmbed = {
        {
            ["title"] = "🚗 Vehicle Teardown Complete",
            ["color"] = 5763719, 
            ["fields"] = {
                {
                    ["name"] = "👤 Player Information",
                    ["value"] = string.format("**Character:** %s %s\n**CID:** %s\n**Server ID:** %d", firstName, lastName, cid, src),
                    ["inline"] = true
                },
                {
                    ["name"] = "📊 Session Details",
                    ["value"] = string.format("**Mode:** %s\n**Tier Multiplier:** %s", modeStr, multiplierStr),
                    ["inline"] = true
                },
                {
                    ["name"] = "📦 Total Rewards",
                    ["value"] = rewardLines,
                    ["inline"] = false
                }
            },
            ["footer"] = {
                ["text"] = "Chawa Logs • " .. os.date("%Y-%m-%d %H:%M:%S")
            }
        }
    }

    PerformHttpRequest(Config.DiscordWebhook, function() end, 'POST', 
        json.encode({ username = "Chawa Spyin", embeds = discordEmbed }), { ['Content-Type'] = 'application/json' }
    )
end

local function SendDiscordEliteLog(src, amount, item)
    if not Config.DiscordWebhook or Config.DiscordWebhook == "" or Config.DiscordWebhook == "YOUR_DISCORD_WEBHOOK_URL_HERE" then 
        return
    end

    local player = exports.qbx_core:GetPlayer(src)
    if not player or not player.PlayerData then return end

    local charInfo = player.PlayerData.charinfo or {}
    local firstName = charInfo.firstname or "Unknown"
    local lastName = charInfo.lastname or "Unknown"
    local cid = player.PlayerData.citizenid or "Unknown"

    local discordEmbed = {
        {
            ["title"] = "💎 Elite VIP Mission Completed",
            ["color"] = 15105570, 
            ["fields"] = {
                {
                    ["name"] = "👤 Player Information",
                    ["value"] = string.format("**Character:** %s %s\n**CID:** %s\n**Server ID:** %d", firstName, lastName, cid, src),
                    ["inline"] = false
                },
                {
                    ["name"] = "💰 Payout",
                    ["value"] = string.format("• **%s**: x%d", item, amount),
                    ["inline"] = false
                }
            },
            ["footer"] = {
                ["text"] = "Chawa Logs • " .. os.date("%Y-%m-%d %H:%M:%S")
            }
        }
    }

    PerformHttpRequest(Config.DiscordWebhook, function() end, 'POST', 
        json.encode({ username = "Chawa spyin", embeds = discordEmbed }), { ['Content-Type'] = 'application/json' }
    )
end

function table.clone(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in pairs(orig) do copy[orig_key] = orig_value end
    else copy = orig end
    return copy
end

function LoadDataFile()
    local fileContent = LoadResourceFile(GetCurrentResourceName(), jsonFileName)
    if not fileContent or fileContent == "" then return {} end
    return json.decode(fileContent) or {}
end

function SaveDataFile(data)
    SaveResourceFile(GetCurrentResourceName(), jsonFileName, json.encode(data, {indent = true}), -1)
end

local function GetPlayerTier(streak)
    streak = streak or 0
    if streak >= Config.Tiers["elite"].minStreak then return "elite"
    elseif streak >= Config.Tiers["high"].minStreak then return "high"
    elseif streak >= Config.Tiers["mid"].minStreak then return "mid"
    elseif streak >= Config.Tiers["low"].minStreak then return "low"
    else return "base" end
end

function GenerateListForPlayer(streak)
    streak = streak or 0
    local playerList = {}
    local tier = GetPlayerTier(streak)

    local chosenType = Config.ListType

    if chosenType == "random" then
        chosenType = (math.random(1, 2) == 1) and "model" or "class"
    end

    if tier == "elite" then
        chosenType = "model"
    end

    local tempVehicles = {}
    local tempClasses = table.clone(Config.ClassPool)
    local baseVehicles = table.clone(Config.VehiclePool)

    if tier == "base" then
        tempVehicles = table.clone(Config.VehiclePool)
    elseif tier == "elite" then
        tempVehicles = table.clone(Config.Tiers["high"].pool)
    else
        tempVehicles = table.clone(Config.Tiers[tier].pool)
    end

    for i = 1, Config.MaxList do
        if chosenType == "model" then
            if #tempVehicles == 0 then tempVehicles = table.clone(baseVehicles) end

            if #tempVehicles > 0 then
                local index = math.random(#tempVehicles)
                table.insert(playerList, { type = "model", value = tempVehicles[index] })
                table.remove(tempVehicles, index) 
            end
        elseif chosenType == "class" and #tempClasses > 0 then
            local index = math.random(#tempClasses)
            table.insert(playerList, { type = "class", value = tempClasses[index] })
            table.remove(tempClasses, index)
        end
    end
    return playerList
end

function PerformGlobalRefresh(currentTime)
    local fileData = LoadDataFile()

    local newLocation = Config.NPCLocations[math.random(#Config.NPCLocations)]
    if #Config.NPCLocations > 1 and activeNpcLocation then
        while newLocation == activeNpcLocation do
            newLocation = Config.NPCLocations[math.random(#Config.NPCLocations)]
        end
    end
    activeNpcLocation = newLocation

    local serverState = {
        lastRefreshTime = currentTime,
        npcLocation = activeNpcLocation
    }
    fileData["_SERVER_STATE_"] = serverState

    for cid, data in pairs(fileData) do
        if cid ~= "_SERVER_STATE_" and type(data) == "table" then
            data.list = GenerateListForPlayer(data.streak or 0)
            data.eliteMissionsDone = 0

            for i = 1, Config.MaxList do
                data["slot" .. i] = 0
            end
        end
    end

    SaveDataFile(fileData)
    print("^2Global refresh completed. NPC moved and all player lists regenerated.^7")
    TriggerClientEvent("chawachopin:client:spawnNpcAtLocation", -1, activeNpcLocation)
end

function InitializeServerState()
    local fileData = LoadDataFile()

    if not fileData["_SERVER_STATE_"] then
        fileData["_SERVER_STATE_"] = {
            lastRefreshTime = os.time(),
            npcLocation = Config.NPCLocations[math.random(#Config.NPCLocations)]
        }
        SaveDataFile(fileData)
    end

    local serverState = fileData["_SERVER_STATE_"]
    local currentTime = os.time()
    local needsRefresh = false

    if Config.RefreshMode == "reboot" then
        needsRefresh = true
    elseif Config.RefreshMode == "hours" then
        local lastRefresh = serverState.lastRefreshTime or currentTime
        if (currentTime - lastRefresh) >= (Config.RefreshHours * 3600) then
            needsRefresh = true
        end
    end

    if needsRefresh then
        PerformGlobalRefresh(currentTime)
    else
        activeNpcLocation = serverState.npcLocation or Config.NPCLocations[math.random(#Config.NPCLocations)]
        if Config.RefreshMode == "hours" then
            local nextRefresh = (serverState.lastRefreshTime or currentTime) + (Config.RefreshHours * 3600)
            local remaining = nextRefresh - currentTime
            local remainingHours = math.floor(remaining / 3600)
            local remainingMinutes = math.floor((remaining % 3600) / 60)
            print(("^2Loaded persistent state. Next refresh in %d hours and %d minutes.^7"):format(remainingHours, remainingMinutes))
        end
    end
end

CreateThread(function()
    while true do
        Wait(1000)

        local currentTime = os.time()
        local fileData = LoadDataFile()
        local globalRefreshed = false

        if Config.RefreshMode == "hours" then
            local serverState = fileData["_SERVER_STATE_"] or {}
            local lastRefresh = serverState.lastRefreshTime or currentTime
            local nextRefreshTime = lastRefresh + (Config.RefreshHours * 3600)

            if (nextRefreshTime - currentTime) <= 0 then
                if Config.Debug then print("Refresh hours hit 0. Performing live global refresh.") end
                PerformGlobalRefresh(currentTime)
                globalRefreshed = true

                local updatedData = LoadDataFile()
                local players = GetPlayers()

                for _, src in ipairs(players) do
                    local cid = GetPlayerCitizenId(tonumber(src))
                    if cid and updatedData[cid] then
                        TriggerClientEvent("chawachopin:client:updateList", tonumber(src), updatedData[cid], updatedData[cid].list, false)
                    end
                end
            end
        end

        if not globalRefreshed then
            local dataChanged = false
            for cid, data in pairs(fileData) do
                if cid ~= "_SERVER_STATE_" and type(data) == "table" then
                    if data.listAssignedTime and data.listAssignedTime > 0 then
                        if (currentTime - data.listAssignedTime) > STREAK_TIMEOUT then

                            fileData[cid] = nil -- Wipe from JSON
                            dataChanged = true

                            if Config.Debug then print("^3Streak expired for " .. cid .. ". Data removed.^7") end

                            local players = GetPlayers()
                            for _, src in ipairs(players) do
                                if GetPlayerCitizenId(tonumber(src)) == cid then
                                    local dummyData = {
                                        streak = 0,
                                        lastCompleted = 0,
                                        listAssignedTime = currentTime,
                                        eliteMissionsDone = 0,
                                        list = GenerateListForPlayer(0)
                                    }
                                    for i = 1, Config.MaxList do
                                        dummyData["slot" .. i] = 0
                                    end
                                    TriggerClientEvent("chawachopin:client:updateList", tonumber(src), dummyData, dummyData.list, false)
                                    break
                                end
                            end
                        end
                    end
                end
            end

            if dataChanged then
                SaveDataFile(fileData)
            end
        end
    end
end)

if Config.Debug then
    CreateThread(function()
        while true do
            Wait(1000)

            local currentTime = os.time()
            local fileData = LoadDataFile()

            if Config.RefreshMode == "hours" then
                local serverState = fileData["_SERVER_STATE_"] or {}
                local lastRefresh = serverState.lastRefreshTime or currentTime
                local nextRefreshTime = lastRefresh + (Config.RefreshHours * 3600)
                local timeRemaining = nextRefreshTime - currentTime

                if timeRemaining > 0 then
                    local hours = math.floor(timeRemaining / 3600)
                    local mins = math.floor((timeRemaining % 3600) / 60)
                    local secs = timeRemaining % 60
                    print(("^5List/npc refresh in: %d hours, %d minutes, %d seconds.^7"):format(hours, mins, secs))
                end
            end

            local players = GetPlayers()
            for _, src in ipairs(players) do
                local cid = GetPlayerCitizenId(tonumber(src))
                local Player = exports.qbx_core:GetPlayer(src)

                if cid and fileData[cid] and fileData[cid].listAssignedTime then
                    local assignedTime = fileData[cid].listAssignedTime
                    local timeRemaining = (assignedTime + STREAK_TIMEOUT) - currentTime

                    if timeRemaining > 0 then
                        local hours = math.floor(timeRemaining / 3600)
                        local mins = math.floor((timeRemaining % 3600) / 60)
                        local secs = timeRemaining % 60

                        if hours > 0 then
                            print(("^6Player %s %s (%s) expires in: %d hours, %d mins, %d secs.^7"):format(Player.PlayerData.charinfo.firstname, Player.PlayerData.charinfo.lastname, cid, hours, mins, secs))
                        else
                            print(("^6Player %s %s (%s) expires in: %d mins, %d secs.^7"):format(Player.PlayerData.charinfo.firstname, Player.PlayerData.charinfo.lastname, cid, mins, secs))
                        end
                    end
                end
            end
        end
    end)
end

function CheckStreakExpiration(cid, fileData)
    if fileData[cid] then
        if not fileData[cid].listAssignedTime then
            fileData[cid].listAssignedTime = fileData[cid].lastCompleted or os.time()
        end

        if fileData[cid].listAssignedTime > 0 then
            if (os.time() - fileData[cid].listAssignedTime) > STREAK_TIMEOUT then
                fileData[cid] = nil
                SaveDataFile(fileData)
                print("^3Streak expired for " .. cid .. ". Data removed.^7")
            end
        end
    end
    return fileData
end

function InitializePlayerData(cid, fileData)
    if not fileData[cid] then fileData[cid] = {} end
    if not fileData[cid].streak then fileData[cid].streak = 0 end

    fileData[cid].lastCompleted = fileData[cid].lastCompleted or 0
    fileData[cid].listAssignedTime = os.time()
    fileData[cid].eliteMissionsDone = fileData[cid].eliteMissionsDone or 0

    for i = 1, Config.MaxList do fileData[cid]["slot" .. i] = 0 end

    fileData[cid].list = GenerateListForPlayer(fileData[cid].streak)
    return fileData
end

RegisterNetEvent("chawachopin:server:requestNpcLocation", function()
    TriggerClientEvent("chawachopin:client:spawnNpcAtLocation", source, activeNpcLocation)
end)

RegisterNetEvent("chawachopin:server:checkList", function()
    local src = source
    local cid = GetPlayerCitizenId(src)
    if not cid then return end

    local fileData = LoadDataFile()

    if not fileData[cid] or not fileData[cid]["slot1"] or not fileData[cid].list then
        fileData = InitializePlayerData(cid, fileData)
        SaveDataFile(fileData)
    end

    fileData = CheckStreakExpiration(cid, fileData)

    if not fileData[cid] then
        fileData = InitializePlayerData(cid, fileData)
        SaveDataFile(fileData)
    end

    TriggerClientEvent("chawachopin:client:updateList", src, fileData[cid], fileData[cid].list, false)
end)

RegisterNetEvent("chawachopin:server:verifyVehicle", function(vehicleNetId, clientModelName, clientClassName, isAuto)
    local src = source
    local cid = GetPlayerCitizenId(src)
    if not cid then return end

    local vehicleEntity = NetworkGetEntityFromNetworkId(vehicleNetId)

    if not DoesEntityExist(vehicleEntity) then
        exports.qbx_core:Notify(src, "Cannot verify: Vehicle not found.", "error", 5000)
        return
    end

    if lockedVehicles[vehicleNetId] then
        if lockedVehicles[vehicleNetId].cid == cid then
            local savedData = lockedVehicles[vehicleNetId]
            exports.qbx_core:Notify(src, "Vehicle lock re-established. Resuming teardown...", "success", 5000)
            TriggerClientEvent("chawachopin:client:beginScrapSequence", src, vehicleNetId, savedData.slot, savedData.isAuto)
            return
        else
            exports.qbx_core:Notify(src, "This vehicle is already being processed by another worker!", "error", 5000)
            return
        end
    end

    local playerPed = GetPlayerPed(src)
    local driverPed = GetPedInVehicleSeat(vehicleEntity, -1)

    if driverPed ~= 0 then
        if driverPed ~= playerPed then
            exports.qbx_core:Notify(src, "Only the current driver can verify this vehicle!", "error", 5000)
            return
        end
    else
        local netOwner = NetworkGetEntityOwner(vehicleEntity)
        if netOwner ~= src then
            exports.qbx_core:Notify(src, "You must be the driver or last driver to verify this vehicle!", "error", 5000)
            return
        end
    end

    local fileData = LoadDataFile()
    if not fileData[cid] or not fileData[cid]["slot1"] or not fileData[cid].list then 
        fileData = InitializePlayerData(cid, fileData)
        SaveDataFile(fileData)
    end

    fileData = CheckStreakExpiration(cid, fileData)

    if not fileData[cid] then
        fileData = InitializePlayerData(cid, fileData)
        SaveDataFile(fileData)
    end

    local isMatch = false
    local matchedSlot = nil
    local playerList = fileData[cid].list or {}

    for index, task in ipairs(playerList) do
        local slotName = "slot" .. index

        if fileData[cid][slotName] == 0 then
            if task.type == "model" and clientModelName == string.lower(task.value) then
                isMatch = true
                matchedSlot = slotName
                break
            elseif task.type == "class" and string.lower(clientClassName) == string.lower(task.value) then
                isMatch = true
                matchedSlot = slotName
                break
            end
        end
    end

    if isMatch and matchedSlot then
        local streak = fileData[cid].streak or 0
        local tier = GetPlayerTier(streak)
        local tierMultiplier = 1.0

        if tier ~= "base" and Config.Tiers[tier] and Config.Tiers[tier].multiplier then
            tierMultiplier = Config.Tiers[tier].multiplier
        end

        lockedVehicles[vehicleNetId] = {
            cid = cid,
            slot = matchedSlot,
            isAuto = isAuto,
            multiplier = tierMultiplier
        } 

        TriggerClientEvent("chawachopin:client:beginScrapSequence", src, vehicleNetId, matchedSlot, isAuto)
    else
        local alreadyDone = false
        for index, task in ipairs(playerList) do
            if (task.type == "model" and clientModelName == string.lower(task.value)) or
               (task.type == "class" and string.lower(clientClassName) == string.lower(task.value)) then
                alreadyDone = true
                break
            end
        end

        if alreadyDone then
            exports.qbx_core:Notify(src, "You have already turned this vehicle in!", "error", 5000)
            local npcTarget = vec3(activeNpcLocation.x, activeNpcLocation.y, activeNpcLocation.z)
            local players = GetPlayers()
            for _, playerId in ipairs(players) do
                local pPed = GetPlayerPed(playerId)
                if DoesEntityExist(pPed) then
                    local pCoords = GetEntityCoords(pPed)
                    if #(pCoords - npcTarget) <= 200.0 then
                        TriggerClientEvent("chawachopin:client:madnpc", playerId)
                    end
                end
            end
        else
            exports.qbx_core:Notify(src, "This vehicle does not match any open list!", "error", 5000)
        end
    end
end)

local function IsPlayerNearScrapYard(playerCoords)
    for _, npcLoc in ipairs(Config.NPCLocations) do
        local npcVector3 = vec3(npcLoc.x, npcLoc.y, npcLoc.z)
        if #(playerCoords - npcVector3) <= Config.MaxDistance then
            return true
        end
    end
    return false
end

RegisterNetEvent("chawachopin:server:crushVehicle", function(netId, matchedSlot)
    local src = source
    local cid = GetPlayerCitizenId(src)
    local playerPed = GetPlayerPed(src)
    local playerCoords = GetEntityCoords(playerPed)

    if not IsPlayerNearScrapYard(playerCoords) then
        print(("[EXPLOIT WARNING] Player ID %s attempted to crush far from the Scrap NPC!"):format(src))
        return
    end

    if not scrapSessionRewards[netId] then scrapSessionRewards[netId] = {} end

    local tierMultiplier = 1.0
    if lockedVehicles[netId] and lockedVehicles[netId].multiplier then
        tierMultiplier = lockedVehicles[netId].multiplier
    end

    if Config.ScrapRewards["crush"] then
        for _, reward in ipairs(Config.ScrapRewards["crush"]) do
            local dropChanceRoll = math.random(1, 100)
            if dropChanceRoll <= reward.percentage then
                local baseAmount = math.random(reward.min, reward.max)
                local dropAmount = math.floor((baseAmount * tierMultiplier) + 0.5)

                if dropAmount > 0 then
                    if not scrapSessionRewards[netId][reward.item] then
                        scrapSessionRewards[netId][reward.item] = { secured = 0, dropped = 0 }
                    end

                    if exports.ox_inventory:CanCarryItem(src, reward.item, dropAmount) then
                        exports.ox_inventory:AddItem(src, reward.item, dropAmount)
                        scrapSessionRewards[netId][reward.item].secured = scrapSessionRewards[netId][reward.item].secured + dropAmount
                    else
                        exports.ox_inventory:CustomDrop("Scrap Drop", { { reward.item, dropAmount } }, playerCoords, 1, 0, nil)
                        TriggerClientEvent('ox_lib:notify', src, {
                            type = 'warning',
                            title = 'Inventory Overweight',
                            description = ('Overweight! %dx %s from crushing dropped at your feet.'):format(dropAmount, reward.item),
                            position = 'top'
                        })
                        scrapSessionRewards[netId][reward.item].dropped = scrapSessionRewards[netId][reward.item].dropped + dropAmount
                    end
                end
            end
        end
    end

    if cid and matchedSlot then
        local fileData = LoadDataFile()
        if fileData[cid] then
            fileData[cid][matchedSlot] = 1

            local allDone = true
            for i = 1, Config.MaxList do
                if fileData[cid]["slot" .. i] ~= 1 then
                    allDone = false
                    break
                end
            end

            local triggerSound = false

            if allDone then
                fileData[cid].streak = (fileData[cid].streak or 0) + 1
                fileData[cid].listAssignedTime = os.time()
                fileData[cid].lastCompleted = os.time()
                triggerSound = true
            end

            SaveDataFile(fileData)
            TriggerClientEvent("chawachopin:client:updateList", src, fileData[cid], fileData[cid].list, triggerSound)
        end
    end

    SendDiscordScrapLog(src, netId)

    TriggerClientEvent("chawachopin:client:deleteVerifiedVehicle", src, netId)
    vehicleProgress[netId] = nil
    scrapSessionRewards[netId] = nil
    lockedVehicles[netId] = nil 
end)

RegisterNetEvent("chawachopin:server:cancelScrap", function(netId)
    local src = source
    local cid = GetPlayerCitizenId(src)
    if lockedVehicles[netId] and lockedVehicles[netId].cid == cid then
        vehicleProgress[netId] = nil
        scrapSessionRewards[netId] = nil
        lockedVehicles[netId] = nil
        exports.qbx_core:Notify(src, "Scrap session cancelled.", "primary", 5000)
    end
end)

RegisterNetEvent("chawachopin:server:updateScrapProgress", function(netId, nextIndex, partType, isAuto)
    local src = source

    if not vehicleProgress[netId] then vehicleProgress[netId] = {} end
    if vehicleProgress[netId][nextIndex] then return end

    vehicleProgress[netId][nextIndex] = true
    if not scrapSessionRewards[netId] then scrapSessionRewards[netId] = {} end

    if partType and Config.ScrapRewards[partType] then
        local mode = isAuto and "auto" or "manual"
        local modifiers = Config.RewardModifiers[mode] or { chanceModifier = 0, amountMultiplier = 1.0 }
        local tierMultiplier = 1.0
        if lockedVehicles[netId] and lockedVehicles[netId].multiplier then
            tierMultiplier = lockedVehicles[netId].multiplier
        end

        for _, reward in ipairs(Config.ScrapRewards[partType]) do
            local dropChanceRoll = math.random(1, 100)
            local finalChance = reward.percentage + modifiers.chanceModifier
            if finalChance > 100 then finalChance = 100 elseif finalChance < 0 then finalChance = 0 end

            if dropChanceRoll <= finalChance then
                local baseAmount = math.random(reward.min, reward.max)
                local dropAmount = math.floor((baseAmount * modifiers.amountMultiplier * tierMultiplier) + 0.5)

                if dropAmount > 0 then
                    if not scrapSessionRewards[netId][reward.item] then
                        scrapSessionRewards[netId][reward.item] = { secured = 0, dropped = 0 }
                    end

                    if exports.ox_inventory:CanCarryItem(src, reward.item, dropAmount) then
                        exports.ox_inventory:AddItem(src, reward.item, dropAmount)
                        scrapSessionRewards[netId][reward.item].secured = scrapSessionRewards[netId][reward.item].secured + dropAmount
                    else
                        local playerPed = GetPlayerPed(src)
                        local coords = GetEntityCoords(playerPed)
                        exports.ox_inventory:CustomDrop("Scrap Drop", { { reward.item, dropAmount } }, coords, 1, 0, nil)
                        TriggerClientEvent('ox_lib:notify', src, {
                            type = 'warning',
                            title = 'Inventory Overweight',
                            description = ('You are too heavy! %dx %s was dropped at your feet.'):format(dropAmount, reward.item),
                            position = 'top'
                        })
                        scrapSessionRewards[netId][reward.item].dropped = scrapSessionRewards[netId][reward.item].dropped + dropAmount
                    end
                end
            end
        end
    end
end)

RegisterNetEvent("chawachopin:server:getScrapProgress", function(netId, isAuto)
    local progressTable = vehicleProgress[netId] or {}
    TriggerClientEvent("chawachopin:client:syncScrapProgress", source, progressTable, isAuto)
end)

RegisterNetEvent("chawachopin:server:requestEliteMission", function()
    local src = source
    local cid = GetPlayerCitizenId(src)
    local fileData = LoadDataFile()

    if not fileData[cid] then return end

    local streak = fileData[cid].streak or 0
    if streak < Config.Tiers["elite"].minStreak then
        exports.qbx_core:Notify(src, "You aren't trusted enough for this kind of work yet.", "error", 5000)
        local npcTarget = vec3(activeNpcLocation.x, activeNpcLocation.y, activeNpcLocation.z)
            local players = GetPlayers()
            for _, playerId in ipairs(players) do
                local pPed = GetPlayerPed(playerId)
                if DoesEntityExist(pPed) then
                    local pCoords = GetEntityCoords(pPed)
                    if #(pCoords - npcTarget) <= 200.0 then
                        TriggerClientEvent("chawachopin:client:madnpc2", playerId)
                    end
                end
            end
        return
    end

    local maxMissions = Config.EliteDelivery.MaxMissions
    local currentCompleted = fileData[cid].eliteMissionsDone or 0

    if currentCompleted >= maxMissions then
        exports.qbx_core:Notify(src, "Lay low for a bit. The boss doesn't have any high-end work right now.", "error", 15000)
        return
    end

    local modelName = Config.EliteDelivery.Models[math.random(#Config.EliteDelivery.Models)]
    local pickupCoords = Config.EliteDelivery.Pickups[math.random(#Config.EliteDelivery.Pickups)]
    local dropoffCoords = Config.EliteDelivery.Dropoffs[math.random(#Config.EliteDelivery.Dropoffs)]

    local modelHash = GetHashKey(modelName)
    local veh = CreateVehicle(modelHash, pickupCoords.x, pickupCoords.y, pickupCoords.z, pickupCoords.w, true, true)

    while not DoesEntityExist(veh) do Wait(0) end
    local netId = NetworkGetNetworkIdFromEntity(veh)
    
    TriggerClientEvent("chawachopin:client:startEliteMission", src, netId, modelName, pickupCoords, dropoffCoords)
end)

RegisterNetEvent("chawachopin:server:trackEliteMission", function(netId, dropoffCoords, modelName, startCoords)
    local src = source
    local cid = GetPlayerCitizenId(src)
    activeEliteMissions[cid] = {
        netId = netId,
        coords = dropoffCoords,
        model = modelName,
        lastPos = startCoords
    }
end)

RegisterNetEvent('QBCore:Server:OnPlayerLoaded', function()
    local src = source
    local cid = GetPlayerCitizenId(src)

    if cid and activeEliteMissions[cid] then
        SetTimeout(5000, function()
            local m = activeEliteMissions[cid]
            TriggerClientEvent("chawachopin:client:recoverEliteMission", src, m.netId, m.coords, m.model, m.lastPos)
        end)
    end
end)

RegisterNetEvent("chawachopin:server:completeEliteMission", function()
    local src = source
    local cid = GetPlayerCitizenId(src)
    if not cid then return end

    activeEliteMissions[cid] = nil

    local fileData = LoadDataFile()
    if fileData[cid] then
        fileData[cid].eliteMissionsDone = (fileData[cid].eliteMissionsDone or 0) + 1
        SaveDataFile(fileData)
    end

    local reward = Config.EliteDelivery.Reward
    local amount = math.random(reward.min, reward.max)

    exports.ox_inventory:AddItem(src, reward.item, amount)

    SendDiscordEliteLog(src, amount, reward.item)

    local currentCompleted = fileData[cid] and fileData[cid].eliteMissionsDone or 0
    local maxMissions = Config.EliteDelivery.MaxMissions

    exports.qbx_core:Notify(src, ("Delivery complete! Received $%d. (%d/%d VIP Runs done today)"):format(amount, currentCompleted, maxMissions), "success", 5000)
end)

RegisterNetEvent("chawachopin:server:initialPoliceAlert", function(vehName, plateName)
    local alertMsg = string.format("10-90 Grand Theft Auto | Vehicle : %s, Plate: %s", vehName, plateName)
    local players = exports.qbx_core:GetQBPlayers()
    for _, player in pairs(players) do
        if player.PlayerData.job.type == "leo" and player.PlayerData.job.onduty then
            exports.qbx_core:Notify(player.PlayerData.source, alertMsg, "error", 15000)
        end
    end
end)

RegisterNetEvent("chawachopin:server:updatePoliceLocation", function(coords)
    local src = source
    local cid = GetPlayerCitizenId(src)

    if cid and activeEliteMissions[cid] then
        activeEliteMissions[cid].lastPos = coords
    end

    local players = exports.qbx_core:GetQBPlayers()
    for _, player in pairs(players) do
        if player.PlayerData.job.type == "leo" and player.PlayerData.job.onduty then
            TriggerClientEvent('chawachopin:client:policePingMap', player.PlayerData.source, coords)
        end
    end
end)

RegisterNetEvent("chawachopin:server:deleteVehicle", function(netId)
    local veh = NetworkGetEntityFromNetworkId(netId)
    if DoesEntityExist(veh) then
        DeleteEntity(veh)
    end
end)

AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        InitializeServerState()
    end
end)