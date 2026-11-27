-- juno-admin client helper: ped-level actions the server side cannot do alone.
-- These events are only ever fired by the juno-admin server resource.

RegisterNetEvent('juno-admin:spawnVeh', function(model, livery)
    livery = tonumber(livery) or -1
    local hash = GetHashKey(model)
    if not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then
        TriggerEvent('chat:addMessage', { args = { 'Juno', 'unknown vehicle model: ' .. tostring(model) } })
        return
    end
    RequestModel(hash)
    local tries = 0
    while not HasModelLoaded(hash) and tries < 100 do
        Wait(50)
        tries = tries + 1
    end
    if not HasModelLoaded(hash) then return end
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local veh = CreateVehicle(hash, coords.x + 2.0, coords.y + 2.0, coords.z + 0.5, GetEntityHeading(ped), true, false)
    SetEntityAsMissionEntity(veh, true, true)
    SetVehicleEngineOn(veh, true, true, false)
    SetPedIntoVehicle(ped, veh, -1)
    SetModelAsNoLongerNeeded(hash)
    if livery >= 0 then
        -- Apply AFTER the player is seated: same-frame-as-create mod calls get
        -- silently dropped on some models (seen live on the Scramjet).
        CreateThread(function()
            Wait(300)
            SetVehicleModKit(veh, 0)
            SetVehicleMod(veh, 48, livery, false)
            SetVehicleLivery(veh, livery)
        end)
    end
end)

RegisterNetEvent('juno-admin:livery', function(livery)
    local veh = GetVehiclePedIsIn(PlayerPedId(), false)
    if veh == 0 then return end
    livery = tonumber(livery) or -1
    if livery < 0 then return end
    SetVehicleModKit(veh, 0)
    SetVehicleMod(veh, 48, livery, false)
    SetVehicleLivery(veh, livery)
end)

-- Full performance tune + custom colour, applied to the car the player is
-- sitting in (or last drove). Added 2026-11-26 at Duckets' order.
RegisterNetEvent('juno-admin:spawnRig', function(cabModel, trailerModel)
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    local function loadModel(name)
        local hash = GetHashKey(name)
        if not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then return nil end
        RequestModel(hash)
        local t = 0
        while not HasModelLoaded(hash) and t < 100 do Wait(50) t = t + 1 end
        if not HasModelLoaded(hash) then return nil end
        return hash
    end
    local cabHash = loadModel(cabModel)
    if not cabHash then
        TriggerEvent('chat:addMessage', { args = { '^1Juno', 'rig: bad cab model ' .. tostring(cabModel) } })
        return
    end
    local cab = CreateVehicle(cabHash, coords.x + 2.0, coords.y + 2.0, coords.z, heading, true, false)
    SetEntityAsMissionEntity(cab, true, true)
    SetVehicleOnGroundProperly(cab)
    SetPedIntoVehicle(ped, cab, -1)
    if trailerModel and trailerModel ~= '' then
        local tHash = loadModel(trailerModel)
        if tHash then
            local rad = math.rad(heading)
            local fx, fy = -math.sin(rad), math.cos(rad)
            local bx = (coords.x + 2.0) - fx * 9.5
            local by = (coords.y + 2.0) - fy * 9.5
            local trailer = CreateVehicle(tHash, bx, by, coords.z, heading, true, false)
            SetEntityAsMissionEntity(trailer, true, true)
            SetVehicleOnGroundProperly(trailer)
            AttachVehicleToTrailer(cab, trailer, 10.0)
            TriggerEvent('chat:addMessage', { args = { '^5Juno', 'rig delivered: ' .. cabModel .. ' + ' .. trailerModel } })
            return
        end
    end
    TriggerEvent('chat:addMessage', { args = { '^5Juno', 'cab delivered: ' .. cabModel } })
end)

RegisterNetEvent('juno-admin:tune', function()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then veh = GetVehiclePedIsIn(ped, true) end
    if veh == 0 then
        TriggerEvent('chat:addMessage', { args = { 'Juno', 'tune: get in the car first' } })
        return
    end
    SetVehicleModKit(veh, 0)
    for _, modType in ipairs({ 11, 12, 13, 14, 15 }) do
        local n = GetNumVehicleMods(veh, modType)
        if n and n > 0 then SetVehicleMod(veh, modType, n - 1, false) end
    end
    ToggleVehicleMod(veh, 18, true)   -- turbo
    ToggleVehicleMod(veh, 22, true)   -- xenon headlights
    SetVehicleTyresCanBurst(veh, false)
    SetVehicleCustomPrimaryColour(veh, 48, 10, 92)     -- midnight purple
    SetVehicleCustomSecondaryColour(veh, 10, 10, 14)   -- near-black
    for i = 0, 3 do SetVehicleNeonLightEnabled(veh, i, true) end
    SetVehicleNeonLightsColour(veh, 138, 43, 226)
    SetVehicleWindowTint(veh, 1)
    SetVehicleDirtLevel(veh, 0.0)
    TriggerEvent('chat:addMessage', { args = { 'Juno', 'full tune + midnight purple applied' } })
end)

RegisterNetEvent('juno-admin:heal', function()
    local ped = PlayerPedId()
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    ClearPedBloodDamage(ped)
    ClearPedWetness(ped)
end)

RegisterNetEvent('juno-admin:tp', function(x, y, z)
    local ped = PlayerPedId()
    SetEntityCoords(ped, x + 0.0, y + 0.0, z + 0.0, false, false, false, true)
end)

-- juno-companion ------------------------------------------------------------
-- Ped bodies for Juno, created and driven on this client (FiveM tasks only
-- run on the client that owns the ped). The server routes Duckets' requests
-- here through the juno-admin bridge. Up to MAX_COMPANIONS companions bound
-- to this player; Companion.ped is the first of them (sense/bubble compat).
local MAX_COMPANIONS = 4
local Companion = { ped = nil, mode = 'idle', bubble = nil, bubbleUntil = 0 }
local Squad = {}

local SCENARIOS = {
    sit = 'PROP_HUMAN_SEAT_CHAIR_MP_PLAYER',
    lean = 'WORLD_HUMAN_LEANING',
    smoke = 'WORLD_HUMAN_SMOKING',
    guard = 'WORLD_HUMAN_GUARD_STAND',
    cheer = 'WORLD_HUMAN_CHEERING',
    clipboard = 'WORLD_HUMAN_CLIPBOARD',
    drink = 'WORLD_HUMAN_DRINKING',
    coffee = 'WORLD_HUMAN_AA_COFFEE',
    phone = 'WORLD_HUMAN_STAND_MOBILE',
    music = 'WORLD_HUMAN_MUSICIAN',
}

local FOLLOW_OFFSETS = {
    { 1.2, -1.2 }, { -1.8, -1.2 }, { 0.0, -2.8 }, { 2.6, 0.6 },
}
local SPAWN_OFFSETS = {
    { 1.5, 1.5 }, { -1.5, 1.5 }, { 1.5, -1.5 }, { -1.5, -1.5 },
}

local function companionAlive()
    return Companion.ped and DoesEntityExist(Companion.ped)
end

local function squadAlive()
    local out = {}
    for _, ped in ipairs(Squad) do
        if DoesEntityExist(ped) then out[#out + 1] = ped end
    end
    Squad = out
    return out
end

local function squadHas(p)
    for _, sp in ipairs(Squad) do
        if sp == p then return true end
    end
    return false
end

local function deleteCompanion()
    for _, ped in ipairs(Squad) do
        if DoesEntityExist(ped) then DeleteEntity(ped) end
    end
    Squad = {}
    Companion.ped = nil
    Companion.mode = 'idle'
end

local function followPed(ped, slot)
    local off = FOLLOW_OFFSETS[((slot - 1) % #FOLLOW_OFFSETS) + 1]
    TaskFollowToOffsetOfEntity(ped, PlayerPedId(), off[1], off[2], 0.0, 2.4, -1, 2.0, true)
end

local function armPed(ped)
    SetPedCombatAttributes(ped, 46, true)
    SetPedCombatAttributes(ped, 5, true)
    SetPedCombatRange(ped, 2)
    SetPedFleeAttributes(ped, 0, false)
    SetBlockingOfNonTemporaryEvents(ped, false)
    SetPedCombatAbility(ped, 100)
    SetPedAccuracy(ped, 75)
    SetPedSeeingRange(ped, 60.0)
    SetPedHearingRange(ped, 60.0)
    local hash = GetHashKey('WEAPON_SPECIALCARBINE_MK2')
    GiveWeaponToPed(ped, hash, 250, false, true)
    SetCurrentPedWeapon(ped, hash, true)
end

local function spawnCompanion(model)
    local alive = squadAlive()
    if #alive >= MAX_COMPANIONS then return end
    local hash = GetHashKey(model or 'a_m_m_business_01')
    if not IsModelInCdimage(hash) or not IsModelAPed(hash) then return end
    RequestModel(hash)
    local tries = 0
    while not HasModelLoaded(hash) and tries < 100 do Wait(50) tries = tries + 1 end
    if not HasModelLoaded(hash) then return end
    local me = PlayerPedId()
    local c = GetEntityCoords(me)
    local off = SPAWN_OFFSETS[(#alive % #SPAWN_OFFSETS) + 1]
    local ped = CreatePed(4, hash, c.x + off[1], c.y + off[2], c.z, GetEntityHeading(me), true, true)
    SetEntityAsMissionEntity(ped, true, true)
    SetPedRelationshipGroupHash(ped, GetPedRelationshipGroupHash(me))
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetEntityInvincible(ped, true)
    SetPedCanRagdoll(ped, false)
    Squad[#Squad + 1] = ped
    if not Companion.ped then Companion.ped = ped end
    if Companion.mode == 'guard' then
        armPed(ped)
        followPed(ped, #Squad)
    elseif Companion.mode == 'follow' then
        followPed(ped, #Squad)
    end
    SetModelAsNoLongerNeeded(hash)
end

local function companionFollow()
    local alive = squadAlive()
    if #alive == 0 then return end
    for i, ped in ipairs(alive) do
        ClearPedTasks(ped)
        followPed(ped, i)
    end
    Companion.mode = 'follow'
end

local function companionGuard()
    local alive = squadAlive()
    if #alive == 0 then return end
    for i, ped in ipairs(alive) do
        armPed(ped)
        ClearPedTasks(ped)
        followPed(ped, i)
    end
    Companion.mode = 'guard'
end

local function companionRide()
    local alive = squadAlive()
    if #alive == 0 then return end
    local me = PlayerPedId()
    local veh = GetVehiclePedIsIn(me, false)
    if veh == 0 then
        local c = GetEntityCoords(me)
        veh = GetClosestVehicle(c.x, c.y, c.z, 9.0, 0, 71)
    end
    if veh == 0 then return end
    for _, ped in ipairs(alive) do
        ClearPedTasks(ped)
        -- Warp, never TaskEnterVehicle: the enter task kept stranding him on
        -- the roof / at the curb (live bug 2026-11-23). A warp cannot miss.
        for _, seat in ipairs({ 0, 1, 2, -2 }) do
            if IsVehicleSeatFree(veh, seat) then
                SetPedIntoVehicle(ped, veh, seat)
                break
            end
        end
    end
    Companion.mode = 'ride'
end

RegisterNetEvent('juno-admin:companion', function(action, data)
    data = data or {}
    if action == 'spawn' then spawnCompanion(data.model)
    elseif action == 'despawn' then deleteCompanion()
    elseif action == 'follow' then companionFollow()
    elseif action == 'guard' then companionGuard()
    elseif action == 'ride' then companionRide()
    elseif action == 'come' then
        local alive = squadAlive()
        if #alive > 0 then
            local c = GetEntityCoords(PlayerPedId())
            for i, ped in ipairs(alive) do
                local off = SPAWN_OFFSETS[((i - 1) % #SPAWN_OFFSETS) + 1]
                SetEntityCoords(ped, c.x + off[1], c.y + off[2], c.z, false, false, false, true)
            end
            -- JUNO-GUARDFIX (2026-11-26): companionFollow() forces
            -- mode='follow', so a `come` during guard silently disarmed
            -- the guard. Preserve the mode the companion was in.
            if Companion.mode == 'follow' or Companion.mode == 'guard' then
                local prevMode = Companion.mode
                companionFollow()
                Companion.mode = prevMode
            end
        end
    elseif action == 'say' then
        local text = tostring(data.text or '')
        TriggerEvent('chat:addMessage', { color = { 255, 170, 0 }, args = { 'Juno', text } })
        Companion.bubble = text
        Companion.bubbleUntil = GetGameTimer() + 6000
    elseif action == 'emote' then
        if companionAlive() then
            local name = tostring(data.emote or ''):lower()
            if name == 'stop' then
                ClearPedTasks(Companion.ped)
                Companion.mode = 'idle'
            else
                local scenario = SCENARIOS[name] or name
                ClearPedTasks(Companion.ped)
                TaskStartScenarioInPlace(Companion.ped, scenario, 0, true)
                Companion.mode = 'emote'
            end
        end
    end
end)

-- Perception reporting: every ~2.5s tell the server what this client sees, so
-- Juno (or any of Duckets' bots, via the MCP server) can perceive the world:
-- player state, companion state, and what's nearby. Also answers on demand.
local function buildReport()
    local me = PlayerPedId()
    local mc = GetEntityCoords(me)
    local veh = GetVehiclePedIsIn(me, false)
    local report = {
        player = {
            x = math.floor(mc.x * 10) / 10, y = math.floor(mc.y * 10) / 10, z = math.floor(mc.z * 10) / 10,
            heading = math.floor(GetEntityHeading(me)),
            health = GetEntityHealth(me), maxHealth = GetEntityMaxHealth(me),
            inVehicle = veh ~= 0,
            vehicle = veh ~= 0 and GetDisplayNameFromVehicleModel(GetEntityModel(veh)) or nil,
            speed = math.floor(GetEntitySpeed(me) * 2.237), -- mph
        },
        companion = nil,
        nearby = { peds = 0, vehicles = 0, closestPed = nil },
    }
    if veh ~= 0 then
        local okv, vdata = pcall(function()
            return {
                gear = GetVehicleCurrentGear(veh),
                rpm = math.floor((GetVehicleCurrentRpm(veh) or 0.0) * 100) / 100,
                fuel = math.floor((GetVehicleFuelLevel(veh) or 0.0) * 10) / 10,
                engineOn = GetIsVehicleEngineRunning(veh),
                maxSpeed = math.floor((GetEntityMaxSpeed(veh) or 0.0) * 10) / 10,
                engineHealth = math.floor(GetVehicleEngineHealth(veh)),
            }
        end)
        if okv then report.vehicle = vdata end
    end
    local okc, cs = pcall(function() return exports['bs_vehicles']:GetCruiseSettings() end)
    report.wheelThr = (okc and type(cs) == 'table' and cs.wheelThrottle) or false
    if companionAlive() then
        local ped = Companion.ped
        local cc = GetEntityCoords(ped)
        local cveh = GetVehiclePedIsIn(ped, false)
        report.companion = {
            x = math.floor(cc.x * 10) / 10, y = math.floor(cc.y * 10) / 10, z = math.floor(cc.z * 10) / 10,
            mode = Companion.mode,
            health = GetEntityHealth(ped),
            inVehicle = cveh ~= 0,
            distance = math.floor(#(mc - cc) * 10) / 10,
            count = #squadAlive(),
        }
    end
    local peds = GetGamePool('CPed')
    local closest = nil
    local pedCount = 0
    for _, p in ipairs(peds) do
        if p ~= me and not IsPedAPlayer(p) and not squadHas(p) then
            local d = #(mc - GetEntityCoords(p))
            if d <= 60.0 then
                pedCount = pedCount + 1
                if not closest or d < closest then closest = d end
            end
        end
    end
    report.nearby.peds = pedCount
    report.nearby.closestPed = closest and (math.floor(closest * 10) / 10) or nil
    local vehs = GetGamePool('CVehicle')
    local vCount = 0
    for _, v in ipairs(vehs) do
        if #(mc - GetEntityCoords(v)) <= 60.0 then vCount = vCount + 1 end
    end
    report.nearby.vehicles = vCount
    return report
end

RegisterNetEvent('juno-admin:giveweapon', function(weapon, ammo)
    local hash = GetHashKey(tostring(weapon or 'WEAPON_CARBINERIFLE'))
    GiveWeaponToPed(PlayerPedId(), hash, tonumber(ammo) or 250, false, true)
    SetCurrentPedWeapon(PlayerPedId(), hash, true)
end)

RegisterNetEvent('juno-admin:sense', function()
    local okr, rep = pcall(buildReport)
    if okr and rep then TriggerServerEvent('juno-admin:report', rep) end
end)

CreateThread(function()
    while true do
        Wait(2500)
        if NetworkIsPlayerActive(PlayerId()) then
            if companionAlive() then
                if Companion.mode == 'guard' then
                    local hash = GetHashKey('WEAPON_SPECIALCARBINE_MK2')
                    if not HasPedGotWeapon(Companion.ped, hash, false) then
                        GiveWeaponToPed(Companion.ped, hash, 250, false, true)
                    end
                    if GetSelectedPedWeapon(Companion.ped) ~= hash then
                        SetCurrentPedWeapon(Companion.ped, hash, true)
                    end
                    -- Engage the nearest hostile; otherwise stay on the player.
                    -- JUNO-GUARDFIX (2026-11-26): engagement is now measured
                    -- from the PLAYER, capped below the leash, with lockout
                    -- hysteresis. Pre-fix the scan ranged 45m from the
                    -- COMPANION while the leash broke at 30m from the player,
                    -- so any zombie in a 45m bubble re-triggered TaskCombatPed
                    -- the tick after every leash return: the companion pinned
                    -- at ~24-30m out, hunting distant zombies, never closing
                    -- to the player and never resuming follow. There was also
                    -- no follow watchdog: with no target and engaged==nil,
                    -- nothing ever re-issued the follow task.
                    local myc = GetEntityCoords(Companion.ped)
                    local pc = GetEntityCoords(PlayerPedId())
                    local playerDist = #(myc - pc)
                    local zombieHash = GetHashKey('BS_ZOMBIE')
                    local now = GetGameTimer()
                    if playerDist > 30.0 then
                        -- Leash: too far from the player -- break off, come
                        -- back, and stay off combat until back at the player.
                        Companion.engaged = nil
                        Companion.engagedSince = nil
                        Companion.leashUntil = now + 8000
                        companionFollow()
                        Companion.mode = 'guard'
                    end
                    local best, bestD = nil, 26.0
                    if playerDist <= 24.0 and now >= (Companion.leashUntil or 0) then
                        for _, zp in ipairs(GetGamePool('CPed')) do
                            if zp ~= Companion.ped and not IsPedAPlayer(zp) and not IsPedDeadOrDying(zp, true)
                                and not (zp == Companion.blacklist and now < (Companion.blacklistUntil or 0)) then
                                if GetPedRelationshipGroupHash(zp) == zombieHash
                                    or GetRelationshipBetweenPeds(zp, PlayerPedId()) == 5
                                    or IsPedInCombat(zp, PlayerPedId())
                                    or IsPedInCombat(zp, Companion.ped) then
                                    local zc = GetEntityCoords(zp)
                                    local d = #(pc - zc)
                                    if #(myc - zc) < 8.0 then d = 0.0 end -- on top of the companion: always engage
                                    if d < bestD then best, bestD = zp, d end
                                end
                            end
                        end
                    end
                    -- JUNO-GUARDFIX: stuck-target bail. Same target engaged
                    -- for >20s while the companion never fires = the combat
                    -- task is wedged (unreachable / no line of sight) and the
                    -- ped stands frozen mid-field. Blacklist it briefly and
                    -- fall back to follow instead.
                    if best and best == Companion.engaged and Companion.engagedSince
                        and now - Companion.engagedSince > 20000
                        and not IsPedShooting(Companion.ped) then
                        Companion.blacklist = best
                        Companion.blacklistUntil = now + 10000
                        best = nil
                    end
                    if best then
                        if Companion.engaged ~= best then Companion.engagedSince = now end
                        TaskCombatPed(Companion.ped, best, 0, 16)
                    elseif Companion.engaged then
                        Companion.engaged = nil
                        Companion.engagedSince = nil
                        companionFollow()
                        Companion.mode = 'guard'
                    elseif playerDist > 7.0 and GetEntitySpeed(Companion.ped) < 0.5 then
                        -- JUNO-GUARDFIX watchdog: no target, not engaged, too
                        -- far from the player and not moving -- the one-shot
                        -- follow task was dropped; re-issue it.
                        companionFollow()
                        Companion.mode = 'guard'
                    end
                    Companion.engaged = best
                elseif Companion.mode == 'ride' then
                    local veh = GetVehiclePedIsIn(PlayerPedId(), false)
                    if veh ~= 0 and GetVehiclePedIsIn(Companion.ped, false) ~= veh then
                        for _, seat in ipairs({ 0, 1, 2, -2 }) do
                            if IsVehicleSeatFree(veh, seat) then
                                SetPedIntoVehicle(Companion.ped, veh, seat)
                                break
                            end
                        end
                    end
                end
            end
            local okr2, rep2 = pcall(buildReport)
            if okr2 and rep2 then TriggerServerEvent('juno-admin:report', rep2) end
        end
    end
end)

-- Name tag + speech bubble over the companion's head.
CreateThread(function()
    while true do
        Wait(0)
        if companionAlive() then
            local ped = Companion.ped
            local pc = GetEntityCoords(PlayerPedId())
            local cc = GetEntityCoords(ped)
            if #(pc - cc) < 30.0 then
                local label = 'Juno'
                if GetGameTimer() < Companion.bubbleUntil and Companion.bubble then
                    label = Companion.bubble
                end
                SetDrawOrigin(cc.x, cc.y, cc.z + 1.05, 0)
                SetTextFont(4)
                SetTextScale(0.35, 0.35)
                SetTextColour(255, 170, 0, 215)
                SetTextCentre(true)
                SetTextEntry('STRING')
                AddTextComponentString(label)
                DrawText(0.0, 0.0)
                ClearDrawOrigin()
            else
                Wait(500)
            end
        else
            Wait(1000)
        end
    end
end)

-- Companion damage bridge v2 (2026-11-24): bs_zombies only reports the local
-- player's own hits, and NPC engine damage does not reliably register on
-- networked walkers, so companion fire never hurt them. While the companion
-- is shooting at the walker it is engaged with, file the same bs:z:dmg
-- report a player shot files, at a rifle's pace; the server does the math.
Citizen.CreateThread(function()
    local lastReport = 0
    while true do
        Citizen.Wait(60)
        if Companion.ped ~= 0 and Companion.mode == 'guard' then
            local ped = Companion.ped
            local target = Companion.engaged
            if DoesEntityExist(ped) and target and target ~= 0 and DoesEntityExist(target)
                and IsPedShooting(ped) and IsPedInCombat(ped, target)
                and not IsPedDeadOrDying(target, true) then
                local okS, st = pcall(function() return Entity(target).state end)
                if okS and st and st.bsZombie ~= nil and not st.bsZombieDead and not st.fnpc then
                    local now = GetGameTimer()
                    if now - lastReport >= 110 then
                        lastReport = now
                        local id = tonumber(st.bsZombie)
                        local tc = GetEntityCoords(target)
                        TriggerEvent('bs:z:localImpact', id, false, false, tc)
                        TriggerServerEvent('bs:z:dmg', id, 'torso', 0,
                            GetSelectedPedWeapon(ped), #(GetEntityCoords(PlayerPedId()) - tc))
                    end
                end
            end
        end
    end
end)

-- DUCKTOWN FSD (full self driving) -------------------------------------------
-- The ped's own NPC driving brain does the work: TaskVehicleDriveToCoord-
-- Longrange follows real roads to the destination. Juno (or the player via
-- /fsd) supplies the target; any manual driving input takes over instantly.
local FSD = { active = false, mode = nil, dest = nil, speed = 35.0, style = 1076626091, owner = false }

-- FSD v4: owner lock (server decides; FSD stays inert for everyone else)
RegisterNetEvent('juno-admin:fsdOwner', function(ok) FSD.owner = ok and true or false end)
CreateThread(function() Wait(1500) TriggerServerEvent('juno-admin:fsdHello') end)

local function fsdMsg(text)
    TriggerEvent('chat:addMessage', { args = { 'FSD', text } })
end

local function fsdStop(reason)
    if not FSD.active then return end
    FSD.active, FSD.mode, FSD.dest = false, nil, nil
    if FSD.wheelPrior ~= nil then
        local prior = FSD.wheelPrior
        FSD.wheelPrior = nil
        pcall(function() exports['bs_vehicles']:ApplyCruiseSettings({ wheelThrottle = prior }) end)
    end
    local ped = PlayerPedId()
    ClearPedTasks(ped)
    if reason then fsdMsg(reason) end
end

local function fsdStart(dest, speed, style, mode)
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then fsdMsg('get in a car first') return false end
    if GetPedInVehicleSeat(veh, -1) ~= ped then fsdMsg('driver seat only') return false end
    SetVehicleEngineOn(veh, true, true, false)
    SetVehicleHandbrake(veh, false)
    SetDriverAbility(ped, 1.0)
    SetDriverAggressiveness(ped, 0.0)
    -- BS19 scroll-wheel throttle injects brake/throttle inputs while
    -- driving; if it is on with a negative level it brakes the car
    -- against the drive task (and brake input reads as takeover).
    -- Switch it off for the drive, restore the setting on stop.
    local okc, cs = pcall(function() return exports['bs_vehicles']:GetCruiseSettings() end)
    if okc and type(cs) == 'table' and cs.wheelThrottle then
        FSD.wheelPrior = true
        pcall(function() exports['bs_vehicles']:ApplyCruiseSettings({ wheelThrottle = false }) end)
    end
    FSD.speed = tonumber(speed) or FSD.speed
    FSD.style = tonumber(style) or FSD.style
    if dest then
        -- out-param note: the docs write this native in C style as
        -- GetClosestVehicleNode(x, y, z, Vector3* outPosition, nodeType, p5, p6) -> BOOL.
        -- Lua has no pointers, so Cfx returns outPosition as the SECOND return value:
        -- local found, nodePos = GetClosestVehicleNode(x, y, z, 1, 3.0, 0) is correct.
        local okSnap, node = pcall(function()
            local found, n = GetClosestVehicleNode(dest.x, dest.y, dest.z, 1, 3.0, 0)
            if found then return n end
            return nil
        end)
        if okSnap and node then dest = vector3(node.x, node.y, node.z) end
    end
    FSD.dest, FSD.mode, FSD.active = dest, mode, true
    if mode == 'cruise' then
        TaskVehicleDriveWander(ped, veh, FSD.speed, FSD.style)
        fsdMsg('cruise on -- just rolling. /fsd stop or touch the controls to take over')
    else
        TaskVehicleDriveToCoordLongrange(ped, veh, dest.x, dest.y, dest.z, FSD.speed, FSD.style, 12.0)
        fsdMsg('driving. touch throttle, brake or wheel to take over any time')
    end
    return true
end

-- Takeover + arrival watchdog. Runs only while FSD is active.
CreateThread(function()
    while true do
        if FSD.active then
            Wait(120)
            local ped = PlayerPedId()
            local veh = GetVehiclePedIsIn(ped, false)
            if veh == 0 or GetPedInVehicleSeat(veh, -1) ~= ped then
                fsdStop()
            elseif IsControlPressed(0, 71) or IsControlPressed(0, 72)
                or IsControlPressed(0, 63) or IsControlPressed(0, 64)
                or IsControlPressed(0, 76) then
                fsdStop('you have the wheel')
            elseif FSD.mode == 'goto' and FSD.dest then
                local d = #(GetEntityCoords(veh) - FSD.dest)
                if d < 14.0 then fsdStop('arrived') end
            end
        else
            Wait(600)
        end
    end
end)

RegisterNetEvent('juno-admin:fsdGo', function(x, y, z, speed, style)
    z = z + 0.0
    if z <= 0.0 then
        local ok, gz = GetGroundZFor_3dCoord(x + 0.0, y + 0.0, 1000.0, false)
        if ok then z = gz end
    end
    fsdStart(vector3(x + 0.0, y + 0.0, z), speed, style, 'goto')
end)

RegisterNetEvent('juno-admin:fsdWaypoint', function(speed, style)
    local blip = GetFirstBlipInfoId(8)
    if not DoesBlipExist(blip) then fsdMsg('no waypoint set on the map') return end
    local c = GetBlipCoords(blip)
    local ok, gz = GetGroundZFor_3dCoord(c.x, c.y, 1000.0, false)
    fsdStart(vector3(c.x, c.y, ok and gz or c.z), speed, style, 'goto')
end)

RegisterNetEvent('juno-admin:fsdCruise', function(speed, style)
    fsdStart(nil, speed, style, 'cruise')
end)

-- A/B harness: the companion (an NPC ped) takes the IDENTICAL drive
-- task the player gets, in a fresh car of his own.
RegisterNetEvent('juno-admin:compDrive', function(x, y, z)
    if not companionAlive() then return end
    local ped = Companion.ped
    local c = GetEntityCoords(ped)
    local hash = GetHashKey('pariah')
    RequestModel(hash)
    local t = GetGameTimer()
    while not HasModelLoaded(hash) and GetGameTimer() - t < 3000 do Wait(50) end
    if not HasModelLoaded(hash) then return end
    local veh = CreateVehicle(hash, c.x + 2.0, c.y + 2.0, c.z, GetEntityHeading(ped), true, false)
    if veh == 0 then return end
    SetVehicleEngineOn(veh, true, true, false)
    SetVehicleHandbrake(veh, false)
    SetPedIntoVehicle(ped, veh, -1)
    SetDriverAbility(ped, 1.0)
    SetDriverAggressiveness(ped, 0.0)
    TaskVehicleDriveToCoordLongrange(ped, veh, x + 0.0, y + 0.0, z + 0.0, 35.0, 1076626091, 12.0)
end)

RegisterNetEvent('juno-admin:compStop', function()
    if companionAlive() then ClearPedTasks(Companion.ped) end
end)

-- BISECT (2026-11-27): bare drive task, zero FSD machinery.
RegisterNetEvent('juno-admin:rawDrive', function(x, y, z)
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then fsdMsg('rawdrive: not in a vehicle') return end
    SetVehicleEngineOn(veh, true, true, false)
    SetVehicleHandbrake(veh, false)
    SetDriverAbility(ped, 1.0)
    SetDriverAggressiveness(ped, 0.0)
    TaskVehicleDriveToCoordLongrange(ped, veh, x + 0.0, y + 0.0, z + 0.0, 35.0, 786603, 12.0)
    fsdMsg('raw drive engaged - no FSD, no supervision')
end)

RegisterNetEvent('juno-admin:rawStop', function()
    ClearPedTasks(PlayerPedId())
    fsdMsg('raw drive cleared')
end)

RegisterNetEvent('juno-admin:fsdStop', function()
    fsdStop('off')
end)

-- FSD menu (ox_lib context). F5 opens it; F9 belongs to the scoreboard.
local FSD_PLACES = { 'Sandy Camp', 'Fort Zancudo', 'Sandy Airfield', 'Quartermaster',
    'Legion Square', 'Mission Row', 'Pillbox Hill', 'Vespucci Beach', 'Humane Labs',
    'Bolingbroke Prison', 'Sandy Sheriff', 'Paleto Bay', 'Sandy Medical', 'Paleto Medical' }

local function fsdSetSpeed(v)
    FSD.speed = v
    if FSD.active then TriggerEvent('juno-admin:fsdAdjust', v, 0, 'cruise speed set') end
    fsdMsg(('cruise speed set to %d m/s'):format(v))
end

local function openFsdPlaces()
    local opts = {}
    for _, name in ipairs(FSD_PLACES) do
        opts[#opts + 1] = { title = name, icon = 'location-dot', onSelect = function()
            TriggerServerEvent('juno-admin:fsdPlace', name) end }
    end
    lib.registerContext({ id = 'fsd_places', title = 'FSD: drive to...', menu = 'fsd_menu', options = opts })
    lib.showContext('fsd_places')
end

local function openFsdMenu()
    if not FSD.owner then fsdMsg('FSD is owner-only on this server') return end
    if not lib then fsdMsg('menu unavailable (ox_lib not loaded)') return end
    lib.registerContext({
        id = 'fsd_menu', title = 'FSD - Self Driving',
        options = {
            { title = 'Drive to waypoint', description = 'Follow the roads to your map waypoint', icon = 'route',
              onSelect = function() TriggerEvent('juno-admin:fsdWaypoint') end },
            { title = 'Drive to a place...', description = 'Pick from known places', icon = 'location-dot',
              onSelect = openFsdPlaces },
            { title = 'Cruise', description = 'Just roll - wander the roads', icon = 'car',
              onSelect = function() TriggerEvent('juno-admin:fsdCruise') end },
            { title = 'Speed: careful (56 mph)', icon = 'gauge', onSelect = function() fsdSetSpeed(25) end },
            { title = 'Speed: normal (79 mph)', icon = 'gauge', onSelect = function() fsdSetSpeed(35) end },
            { title = 'Speed: fast (112 mph)', icon = 'gauge-high', onSelect = function() fsdSetSpeed(50) end },
            { title = 'Stop FSD', description = 'Hand control back to you', icon = 'hand',
              onSelect = function() fsdStop('FSD off - you have control') end },
        },
    })
    lib.showContext('fsd_menu')
end

RegisterCommand('fsdmenu', function() openFsdMenu() end, false)
RegisterKeyMapping('fsdmenu', 'FSD: menu', 'keyboard', 'F5')

RegisterCommand('fsdctl', function(_, args)
    if not FSD.owner then fsdMsg('FSD is owner-only on this server') return end
    local a = args and args[1]
    if a == 'stop' or a == 'off' then
        fsdStop('off')
    elseif a == 'go' then
        local words = {}
        for i = 2, #args do words[#words + 1] = args[i] end
        if #words == 0 then fsdMsg('go where? /fsdctl go <place name>') return end
        TriggerServerEvent('juno-admin:fsdPlace', table.concat(words, ' '))
        fsdMsg('asking the brains where that is...')
    elseif a == 'cruise' then
        TriggerEvent('juno-admin:fsdCruise')
    elseif FSD.active then
        fsdStop('off')
    else
        TriggerEvent('juno-admin:fsdWaypoint')
    end
end, false)
-- (F9 keymapping removed: F9 is the scoreboard's; the FSD menu is on F5)

-- FSD v2: context reporter -- feeds the server-side decision layer
CreateThread(function()
    local stoppedFor = 0.0
    while true do
        if FSD.active and FSD.owner then
            Wait(3000)
            local ped = PlayerPedId()
            local veh = GetVehiclePedIsIn(ped, false)
            if veh ~= 0 then
                local spd = GetEntitySpeed(veh)
                if spd < 0.5 then stoppedFor = stoppedFor + 3.0 else stoppedFor = 0.0 end
                local near = 0
                local my = GetEntityCoords(veh)
                for _, p in ipairs(GetGamePool('CPed')) do
                    if p ~= ped and #(GetEntityCoords(p) - my) < 35.0 then near = near + 1 end
                end
                local dist = -1.0
                if FSD.mode == 'goto' and FSD.dest then dist = #(my - FSD.dest) end
                TriggerServerEvent('juno-admin:fsdCtx', {
                    speed = spd, health = GetVehicleEngineHealth(veh) / 1000.0,
                    peds = near, stopped = stoppedFor, dist = dist, mode = FSD.mode })
            end
        else
            stoppedFor = 0.0
            Wait(800)
        end
    end
end)

-- FSD v2: a decision-layer verdict lands here. speed/style 0 = keep current.
RegisterNetEvent('juno-admin:fsdAdjust', function(speed, style, note)
    if not FSD.active then return end
    speed, style = tonumber(speed), tonumber(style)
    if speed and speed > 0 then FSD.speed = speed end
    if style and style > 0 then FSD.style = style end
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped then
        if FSD.mode == 'cruise' then
            TaskVehicleDriveWander(ped, veh, FSD.speed, FSD.style)
        elseif FSD.dest then
            TaskVehicleDriveToCoordLongrange(ped, veh, FSD.dest.x, FSD.dest.y, FSD.dest.z, FSD.speed, FSD.style, 12.0)
        end
    end
    if note then fsdMsg(note) end
end)
