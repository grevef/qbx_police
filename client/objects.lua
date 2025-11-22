local sharedConfig = require 'config.shared'

Config = {}

Config.ModelList = {
    [`prop_roadcone02a`] = "Kjegle",
    [`prop_barrier_work06a`] = "Barriere",
    [`prop_snow_sign_road_06g`] = "Fartsgrenseskilt",
    [`prop_gazebo_03`] = "Telt",
    [`prop_worklight_03b`] = "Lyskaster",
    [`prop_chair_08`] = "Stol",
    [`prop_chair_pile_01`] = "Stolstabel",
    [`prop_table_03`] = "Bord",
    [`des_tvsmash_root`] = "TV"
}

---Spawn police object
RegisterNetEvent('police:client:spawnPObj', function(item)
    if QBX.PlayerData.job.type ~= 'leo' or not QBX.PlayerData.job.onduty then return end
    if cache.vehicle then return exports.core:Notify(locale('error.in_vehicle'), 'error') end

    if lib.progressBar({
        duration = 2500,
        label = locale('progressbar.place_object'),
        useWhileDead = false,
        canCancel = true,
        disable = { car = true, move = true, combat = true, mouse = false },
        anim = { dict = 'anim@narcotics@trash', clip = 'drop_front' }
    }) then
        local objectConfig = sharedConfig.objects[item]
        local forward = GetEntityForwardVector(cache.ped)
        local spawnCoords = GetEntityCoords(cache.ped) + forward * 0.5

        local netid, error = lib.callback.await('police:server:spawnObject', false,
                                                objectConfig.model, spawnCoords, GetEntityHeading(cache.ped))

        if not netid then return exports.core:Notify(locale(error), 'error') end

        local object = NetworkGetEntityFromNetworkId(netid)
        PlaceObjectOnGroundProperly(object)
        FreezeEntityPosition(object, objectConfig.freeze)
    else
        exports.core:Notify(locale('error.canceled'), 'error')
    end
end)

CreateThread(function()
    for modelHash, _ in pairs(Config.ModelList) do
        exports.targeting:addModel(modelHash, {
            {
                name = 'delete_police_object',
                label = 'Fjern Politiobjekt',
                icon = 'fa-solid fa-trash',
                distance = 5.0, -- increased distance

                onSelect = function(data)
                    local entity = data.entity
                    if not entity or not DoesEntityExist(entity) then
                        print("[Core FW 2.0 - DEBUG] Entity does not exist.")
                        return
                    end

                    local modelLabel = Config.ModelList[GetEntityModel(entity)] or "Objekt"
                    print("[Core FW 2.0 - DEBUG] Removing object:", modelLabel, "ModelHash:", GetEntityModel(entity))

                    local success = lib.progressBar({
                        duration = 2500,
                        label = string.format(locale('progressbar.remove_object'), modelLabel),
                        useWhileDead = false,
                        canCancel = true,
                        disable = {
                            car = true,
                            move = true,
                            combat = true,
                            mouse = false
                        },
                        anim = {
                            dict = 'weapons@first_person@aim_rng@generic@projectile@thermal_charge@',
                            clip = 'plant_floor'
                        }
                    })

                    if not success then
                        exports.core:Notify(locale('error.canceled'), 'error')
                        print("[Core FW 2.0 - DEBUG] Progressbar canceled.")
                        return
                    end

                    -- Ensure entity is networked
                    if not NetworkGetEntityIsNetworked(entity) then
                        print("[Core FW 2.0 - DEBUG] Entity not networked, registering...")
                        NetworkRegisterEntityAsNetworked(entity)
                        Wait(50)
                    end

                    -- Request network control
                    local timeout = 1000
                    local startTime = GetGameTimer()
                    while not NetworkHasControlOfEntity(entity) and GetGameTimer() - startTime < timeout do
                        NetworkRequestControlOfEntity(entity)
                        Wait(5)
                    end

                    if NetworkHasControlOfEntity(entity) then
                        print("[Core FW 2.0 - DEBUG] Got control of entity, deleting locally.")
                        DeleteEntity(entity)
                        if DoesEntityExist(entity) then
                            print("[Core FW 2.0 - DEBUG] WARNING: entity still exists! Falling back to server event.")
                            local netId = NetworkGetNetworkIdFromEntity(entity)
                            if netId and netId ~= 0 then
                                TriggerServerEvent('police:server:despawnObject', netId)
                            end
                        else
                            print("[Core FW 2.0 - DEBUG] Entity deleted successfully.")
                        end
                    else
                        print("[Core FW 2.0 - DEBUG] Could not get control, triggering server fallback.")
                        local netId = NetworkGetNetworkIdFromEntity(entity)
                        if netId and netId ~= 0 then
                            TriggerServerEvent('police:server:despawnObject', netId)
                        else
                            print("[Core FW 2.0 - DEBUG] WARNING: Unable to delete entity, no network ID.")
                        end
                    end
                end
            }
        })
    end
end)

---Cleanup on resource stop/start/restart
local function cleanupPoliceProps()
    local isOpen, text = lib.isTextUIOpen()
    if isOpen and text == locale('info.delete_prop') then
        lib.hideTextUI()
    end

    if GlobalState.policeObjects then
        for i = #GlobalState.policeObjects, 1, -1 do
            local netid = GlobalState.policeObjects[i]
            local entity = NetworkGetEntityFromNetworkId(netid)
            if entity and DoesEntityExist(entity) then
                DeleteEntity(entity)
            end
            table.remove(GlobalState.policeObjects, i)
        end
    end

    -- Delete any untracked objects matching Config.ModelList
    local handle, entity = FindFirstObject()
    local finished = false
    repeat
        if DoesEntityExist(entity) and Config.ModelList[GetEntityModel(entity)] then
            SetEntityAsMissionEntity(entity, true, true)
            DeleteObject(entity)
        end
        finished, entity = FindNextObject(handle)
    until not finished
    EndFindObject(handle)
end

for _, eventName in ipairs({'onResourceStop', 'onResourceStart', 'onResourceRestart'}) do
    AddEventHandler(eventName, function(resource)
        if resource == GetCurrentResourceName() then
            cleanupPoliceProps()
        end
    end)
end
