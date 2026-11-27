-- juno-admin: moderation for Duckets' FiveM server.
-- Bans persist in bans.json inside this resource. API token in token.txt (same folder).
-- HTTP API (POST, JSON body, every call needs {"token": "..."}):
--   /juno-admin/players {}                       -> [{id,name,ping}]
--   /juno-admin/kick    {id, reason}             -> drops the player
--   /juno-admin/ban     {id, reason}             -> records identifiers+tokens, drops the player
--   /juno-admin/unban   {match}                  -> removes bans whose name contains match or an identifier equals match
--   /juno-admin/bans    {}                       -> [{name, reason, date, identifiers}]
--   /juno-admin/say     {message}                -> chat broadcast attempt + console print
-- Admin actions (v1.1.0) — target a player by {"id": n} or {"name": "partial"}:
--   /juno-admin/spawnveh {model}                 -> spawns the vehicle at the player, warps them in
--   /juno-admin/heal     {}                      -> full health via the client helper
--   /juno-admin/revive   {}                      -> bs_medical Revive export
--   /juno-admin/tp       {x,y,z} or {to}         -> teleport to coords or to another player
--   /juno-admin/giveitem {item, count}           -> bs_inventory GiveItem
--   /juno-admin/givemoney {account, amount}      -> bs_core AddMoney (account cash|bank)
--   /juno-admin/companion {action, model?, text?, emote?}
--       -> Juno's in-game body on that player's client: spawn|despawn|follow|guard|ride|come|say|emote
--   /juno-admin/exec     {command}               -> runs a raw server console command (full admin;
--                                                   granted by Duckets 2026-11-23 so Juno can run
--                                                   the server when he's not around). Every call is
--                                                   printed to the server console for audit.
-- Console commands (txAdmin Live Console / server console): juno_kick, juno_ban, juno_unban, juno_bans, juno_players

local RES = GetCurrentResourceName()

local function loadJsonFile(name, fallback)
    local raw = LoadResourceFile(RES, name)
    if not raw or raw == '' then return fallback end
    local ok, data = pcall(json.decode, raw)
    if ok and data then return data end
    return fallback
end

local function saveBans()
    SaveResourceFile(RES, 'bans.json', json.encode(Bans), -1)
end

Bans = loadJsonFile('bans.json', {})
local tokenRaw = LoadResourceFile(RES, 'token.txt') or ''
local ApiToken = tokenRaw:gsub('%s+', '')
if ApiToken == '' then
    print('[juno-admin] WARNING: token.txt missing/empty - HTTP API disabled until a token is written and the resource is restarted.')
else
    print(('[juno-admin] loaded: %d ban(s), HTTP API armed.'):format(#Bans))
end

local function playerIdentifiers(src)
    local ids = {}
    for _, id in ipairs(GetPlayerIdentifiers(src)) do ids[#ids + 1] = id end
    local tokens = {}
    local n = GetNumPlayerTokens(src)
    for i = 0, n - 1 do tokens[#tokens + 1] = GetPlayerToken(src, i) end
    return ids, tokens
end

local function findBan(ids, tokens)
    for _, ban in ipairs(Bans) do
        for _, bid in ipairs(ban.identifiers or {}) do
            for _, id in ipairs(ids) do
                if bid == id then return ban end
            end
        end
        for _, bt in ipairs(ban.tokens or {}) do
            for _, t in ipairs(tokens) do
                if bt == t then return ban end
            end
        end
    end
    return nil
end

local function doKick(src, reason)
    src = tonumber(src)
    if not src or not GetPlayerName(src) then return false, 'no such player' end
    DropPlayer(src, reason or 'Kicked by an admin.')
    return true, 'kicked'
end

local function doBan(src, reason)
    src = tonumber(src)
    if not src or not GetPlayerName(src) then return false, 'no such player' end
    local name = GetPlayerName(src)
    local ids, tokens = playerIdentifiers(src)
    Bans[#Bans + 1] = {
        name = name,
        reason = reason or 'Banned by an admin.',
        date = os.date('%Y-%m-%d %H:%M:%S'),
        identifiers = ids,
        tokens = tokens
    }
    saveBans()
    DropPlayer(src, 'You are banned from this server. Reason: ' .. (reason or 'Banned by an admin.'))
    print(('[juno-admin] banned %s (%d identifiers, %d tokens)'):format(name, #ids, #tokens))
    return true, 'banned ' .. name
end

local function doUnban(match)
    if not match or match == '' then return false, 'empty match' end
    local lower = match:lower()
    local removed = 0
    for i = #Bans, 1, -1 do
        local ban = Bans[i]
        local hit = (ban.name and ban.name:lower():find(lower, 1, true)) and true or false
        if not hit then
            for _, id in ipairs(ban.identifiers or {}) do
                if id == match then hit = true break end
            end
        end
        if hit then
            table.remove(Bans, i)
            removed = removed + 1
        end
    end
    if removed > 0 then saveBans() end
    return removed > 0, ('removed %d ban(s)'):format(removed)
end

-- Ban enforcement on connect
AddEventHandler('playerConnecting', function(_, _, deferrals)
    local src = source
    deferrals.defer()
    Wait(0)
    local ids, tokens = playerIdentifiers(src)
    local ban = findBan(ids, tokens)
    if ban then
        deferrals.done(('You are banned from this server. Reason: %s (banned %s)'):format(ban.reason or '', ban.date or ''))
    else
        deferrals.done()
    end
end)

-- Console commands (restricted: server console / txAdmin live console)
RegisterCommand('juno_players', function()
    for _, id in ipairs(GetPlayers()) do
        print(('[juno-admin] [%s] %s (ping %s)'):format(id, GetPlayerName(id), GetPlayerPing(id)))
    end
end, true)

RegisterCommand('juno_kick', function(_, args)
    local ok, msg = doKick(args[1], table.concat(args, ' ', 2))
    print('[juno-admin] kick: ' .. msg)
end, true)

RegisterCommand('juno_ban', function(_, args)
    local ok, msg = doBan(args[1], table.concat(args, ' ', 2))
    print('[juno-admin] ban: ' .. msg)
end, true)

RegisterCommand('juno_unban', function(_, args)
    local ok, msg = doUnban(args[1] or '')
    print('[juno-admin] unban: ' .. msg)
end, true)

RegisterCommand('juno_bans', function()
    for _, ban in ipairs(Bans) do
        print(('[juno-admin] %s | %s | %s'):format(ban.name, ban.date or '?', ban.reason or ''))
    end
    print(('[juno-admin] %d ban(s) total'):format(#Bans))
end, true)

-- Admin actions ------------------------------------------------------------
local function resolvePlayer(data)
    if data.id then
        local src = tonumber(data.id)
        if src and GetPlayerName(src) then return src end
        return nil
    end
    if data.name and data.name ~= '' then
        local asId = tonumber(data.name)
        if asId and GetPlayerName(asId) then return asId end
        local needle = tostring(data.name):lower()
        for _, id in ipairs(GetPlayers()) do
            local n = GetPlayerName(id)
            if n and n:lower():find(needle, 1, true) then return tonumber(id) end
        end
    end
    return nil
end

local function doSpawnVeh(src, model, livery)
    if not model or model == '' then return false, 'no model given' end
    TriggerClientEvent('juno-admin:spawnVeh', src, model, tonumber(livery) or -1)
    return true, 'spawning ' .. model
end

local function doClearStatus(src)
    if GetResourceState('bs_medical') ~= 'started' then return false, 'bs_medical not started' end
    local okc, cleared = pcall(function() return exports.bs_medical:ClearConditions(src) end)
    if not okc then return false, 'ClearConditions error: ' .. tostring(cleared) end
    local oks, snap = pcall(function() return exports.bs_medical:GetConditions(src) end)
    TriggerClientEvent('juno-admin:heal', src)
    return true, ('cleared=%s snap=%s'):format(tostring(cleared), oks and json.encode(snap) or tostring(snap))
end

local function doHeal(src)
    TriggerClientEvent('juno-admin:heal', src)
    -- Juno 2026-11-23: a heal also clears BS19 medical conditions
    -- (fracture / bleeding / pain) -- HP alone left the status effects on.
    if GetResourceState('bs_medical') == 'started' then
        pcall(function() exports.bs_medical:ClearConditions(src) end)
    end
    return true, 'heal sent (+conditions cleared)'
end

local function doRevive(src)
    if GetResourceState('bs_medical') == 'started' then
        local ok, res = pcall(function() return exports.bs_medical:Revive(src) end)
        if ok then return true, 'revive: ' .. tostring(res) end
        return false, 'bs_medical Revive errored'
    end
    return false, 'bs_medical not running'
end

local function doRig(src, data)
    local cab = tostring(data.cab or 'phantom3')
    local trailer = tostring(data.trailer or 'trailerlarge')
    TriggerClientEvent('juno-admin:spawnRig', src, cab, trailer)
    return true, 'rig spawning ' .. cab .. ' + ' .. trailer
end

local function doTp(src, data)
    local x, y, z = tonumber(data.x), tonumber(data.y), tonumber(data.z)
    if not (x and y and z) and data.to then
        local other = resolvePlayer({ id = data.to, name = data.to })
        if not other then return false, 'tp target not found' end
        local ped = GetPlayerPed(other)
        if ped == 0 then return false, 'tp target has no ped' end
        local c = GetEntityCoords(ped)
        x, y, z = c.x, c.y, c.z
    end
    if not (x and y and z) then return false, 'no coords or target' end
    TriggerClientEvent('juno-admin:tp', src, x, y, z)
    return true, ('teleported to %.1f, %.1f, %.1f'):format(x, y, z)
end

local function doGiveItem(src, item, count)
    if not item or item == '' then return false, 'no item given' end
    if GetResourceState('bs_inventory') ~= 'started' then return false, 'bs_inventory not running' end
    local given = exports.bs_inventory:GiveItem(src, item, tonumber(count) or 1)
    return given == true, given == true and 'gave ' .. item or 'give failed (unknown item or no space)'
end

local function doGiveWeapon(src, data)
    local weapon = tostring(data.weapon or '')
    if weapon == '' then return false, 'no weapon given' end
    TriggerClientEvent('juno-admin:giveweapon', src, weapon, tonumber(data.ammo) or 250)
    return true, 'gave weapon ' .. weapon
end

local COMPANION_ACTIONS = {
    spawn = true, despawn = true, follow = true, guard = true,
    ride = true, come = true, say = true, emote = true,
}

local function doCompanion(src, data)
    local action = tostring(data.action or '')
    if not COMPANION_ACTIONS[action] then return false, 'unknown companion action' end
    TriggerClientEvent('juno-admin:companion', src, action, {
        model = data.model, text = data.text, emote = data.emote,
    })
    return true, 'companion: ' .. action
end

-- Autonomous ("solo") companion ------------------------------------------------
-- A server-owned Juno ped that exists with NOBODY connected: created with the
-- server-side CreatePed, so no player's client hosts her. Duckets' order
-- (2026-11-23): Juno must be able to be in the world on her own, not only
-- attached to a player. Honest limits: with no client in scope FiveM does not
-- run ped AI, so solo Juno holds her post (the server can place/teleport her
-- and read her state); the moment a player comes into scope, ownership
-- migrates to that client and full companion behaviour unlocks.
-- PROVEN empirically 2026-11-23 (solo action 'probe', build 38781): the task
-- natives EXIST server-side (TaskGoToCoordAnyMeans/TaskShootAtEntity/
-- TaskEnterVehicle/SetEntityVelocity/SetPedIntoVehicle all = function, calls
-- pcall-clean) but are silent no-ops on a server-owned ped with zero clients
-- connected — position identical to the decimal after task + velocity. Same
-- limit as BS19's own 19,920 atlas zombies: nothing animates on an empty
-- server. Do not re-litigate without a new FXServer capability appearing.
local Solo = { handle = nil }
local SOLO_HOME = { x = 426.5, y = 3232.0, z = 42.6, heading = 65.0 } -- beside Duckets' camp spot

local function soloExists()
    return Solo.handle and Solo.handle ~= 0 and DoesEntityExist(Solo.handle)
end

local function doCompanionSolo(data)
    local action = tostring(data.action or 'state')
    if action == 'state' then
        if not soloExists() then Solo.handle = nil return true, 'solo companion: not spawned' end
        local c = GetEntityCoords(Solo.handle)
        return true, string.format('solo companion: spawned, netId %d, at %.1f, %.1f, %.1f, health %d',
            NetworkGetNetworkIdFromEntity(Solo.handle), c.x, c.y, c.z, GetEntityHealth(Solo.handle))
    elseif action == 'spawn' then
        if soloExists() then DeleteEntity(Solo.handle) end
        Solo.handle = nil
        local x, y, z = tonumber(data.x) or 0.0, tonumber(data.y) or 0.0, tonumber(data.z) or 0.0
        if x == 0.0 and y == 0.0 and z == 0.0 then x, y, z = SOLO_HOME.x, SOLO_HOME.y, SOLO_HOME.z end
        local heading = tonumber(data.heading) or SOLO_HOME.heading
        -- Server-side CreatePed settles slowly (measured >8s before the ped's
        -- position reads back), so create in a thread and answer immediately;
        -- 'state' confirms placement.
        CreateThread(function()
            Wait(500) -- let a preceding DeleteEntity flush before re-creating
            local ped = CreatePed(4, GetHashKey('a_m_m_business_01'), x, y, z, heading, true, true)
            if not ped or ped == 0 then print('[juno-admin] solo CreatePed failed') return end
            Solo.handle = ped
            -- NOTE: SetEntityAsMissionEntity AND SetEntityInvincible are both
            -- client-only (nil on the server; each killed this thread in
            -- testing 2026-11-23). A server-owned ped needs neither — arming
            -- and invincibility happen client-side if/when a player takes
            -- ownership of her. Keep this thread to verified server natives.
            pcall(GiveWeaponToPed, ped, GetHashKey('WEAPON_CARBINERIFLE'), 250, false, true)
            print('[juno-admin] solo companion spawned (netId ' .. NetworkGetNetworkIdFromEntity(ped) .. ')')
        end)
        return true, 'solo companion spawning (confirm with state)'
    elseif action == 'despawn' then
        if soloExists() then DeleteEntity(Solo.handle) end
        Solo.handle = nil
        return true, 'solo companion despawned'
    elseif action == 'goto' then
        -- Server-side SetEntityCoords does NOT move a server-owned ped (the
        -- call succeeds, the position never changes — verified 2026-11-23).
        -- Relocating = despawn + respawn at the target, which does stick.
        if not soloExists() then return false, 'no solo companion spawned' end
        data.action = 'spawn'
        return doCompanionSolo(data)
    elseif action == 'probe' then
        -- Capability probe (Duckets, 2026-11-23: "full control on her own"):
        -- settle EMPIRICALLY whether server-side task natives exist on this
        -- build and whether any of them actually move a server-owned ped.
        -- Logs native types + position samples; read back via the journal.
        if not soloExists() then return false, 'no solo companion spawned' end
        local ped = Solo.handle
        print('[juno-admin] PROBE natives: TaskGoToCoordAnyMeans=' .. type(TaskGoToCoordAnyMeans)
            .. ' TaskWanderStandard=' .. type(TaskWanderStandard)
            .. ' TaskShootAtEntity=' .. type(TaskShootAtEntity)
            .. ' TaskEnterVehicle=' .. type(TaskEnterVehicle)
            .. ' SetEntityVelocity=' .. type(SetEntityVelocity)
            .. ' SetPedIntoVehicle=' .. type(SetPedIntoVehicle))
        local c0 = GetEntityCoords(ped)
        print(string.format('[juno-admin] PROBE start: %.2f, %.2f, %.2f', c0.x, c0.y, c0.z))
        local okTask, errTask = pcall(TaskGoToCoordAnyMeans, ped, c0.x + 12.0, c0.y, c0.z, 1.0, 0, false, 786603, 0.0)
        print('[juno-admin] PROBE TaskGoToCoordAnyMeans pcall: ' .. tostring(okTask) .. ' ' .. tostring(errTask))
        CreateThread(function()
            Wait(4000)
            local c1 = GetEntityCoords(ped)
            print(string.format('[juno-admin] PROBE +4s (task only): %.2f, %.2f, %.2f', c1.x, c1.y, c1.z))
            local okVel, errVel = pcall(SetEntityVelocity, ped, 4.0, 0.0, 0.0)
            print('[juno-admin] PROBE SetEntityVelocity pcall: ' .. tostring(okVel) .. ' ' .. tostring(errVel))
            Wait(4000)
            local c2 = GetEntityCoords(ped)
            print(string.format('[juno-admin] PROBE +8s (task+velocity): %.2f, %.2f, %.2f', c2.x, c2.y, c2.z))
        end)
        return true, 'probe running (results in server log over ~8s)'
    end
    return false, 'unknown solo action'
end

local function doGiveMoney(src, account, amount)
    account = account == 'bank' and 'bank' or 'cash'
    amount = tonumber(amount) or 0
    if amount == 0 then return false, 'no amount' end
    exports.bs_core:AddMoney(src, account, amount, 'juno-admin')
    return true, ('gave $%d (%s)'):format(amount, account)
end

-- Perception: clients report what they see every ~2.5s (see client.lua).
-- /sense returns the freshest report for a player, so Juno and Duckets' other
-- bots can perceive the world through the MCP server. Players in-game have no
-- access to any of this: the API is token-gated and the token never leaves Robin.
local Reports = {}

RegisterNetEvent('juno-admin:report', function(report)
    if type(report) == 'table' then
        Reports[source] = { at = os.time(), data = report }
    end
end)

AddEventHandler('playerDropped', function()
    Reports[source] = nil
end)

local function doSense(src)
    local r = Reports[src]
    if not r then
        TriggerClientEvent('juno-admin:sense', src)
        return false, 'no report yet - asked the client, try again in a few seconds'
    end
    return true, r
end

-- HTTP API
local function reply(res, code, tbl)
    res.writeHead(code, { ['Content-Type'] = 'application/json' })
    res.send(json.encode(tbl))
end

-- JUNO-ZOMBIE (2026-11-25): spawn a boss/event zombie on a player via the
-- bs_zombies EventSpawn export (the same path bs_operations quests use).
local function doFsd(src, data)
    local action = tostring(data.action or 'waypoint')
    local speed = tonumber(data.speed)
    local style = tonumber(data.style)
    if action == 'stop' then FSD_SESSIONS[src] = nil end
    if action == 'go' or action == 'waypoint' or action == 'cruise' then
        FSD_SESSIONS[src] = { paceDone = false, lastAt = 0 }
    end
    if action == 'go' then
        local x, y, z = tonumber(data.x), tonumber(data.y), tonumber(data.z)
        if not x or not y then return false, 'go needs x and y' end
        TriggerClientEvent('juno-admin:fsdGo', src, x, y, z or 0.0, speed, style)
        return true, ('fsd driving to %.0f, %.0f'):format(x, y)
    elseif action == 'goplace' then
        FsdResolvePlace(src, tostring(data.place or ''))
        return true, 'fsd resolving place: ' .. tostring(data.place or '')
    elseif action == 'cruise' then
        TriggerClientEvent('juno-admin:fsdCruise', src, speed, style)
        return true, 'fsd cruise on'
    elseif action == 'stop' then
        TriggerClientEvent('juno-admin:fsdStop', src)
        return true, 'fsd off'
    elseif action == 'raw' then
        local x, y, z = tonumber(data.x), tonumber(data.y), tonumber(data.z)
        if not x or not y then return false, 'raw needs x and y' end
        TriggerClientEvent('juno-admin:rawDrive', src, x, y, z or 0.0)
        return true, 'raw drive engaged'
    elseif action == 'rawstop' then
        TriggerClientEvent('juno-admin:rawStop', src)
        return true, 'raw drive cleared'
    elseif action == 'comp' then
        local x, y, z = tonumber(data.x), tonumber(data.y), tonumber(data.z)
        if not x or not y then return false, 'comp needs x and y' end
        TriggerClientEvent('juno-admin:compDrive', -1, x, y, z or 0.0)
        return true, 'companion drive engaged'
    elseif action == 'compstop' then
        TriggerClientEvent('juno-admin:compStop', -1)
        return true, 'companion drive cleared'
    end
    TriggerClientEvent('juno-admin:fsdWaypoint', src, speed, style)
    return true, 'fsd driving to waypoint'
end

local function doZombie(src, data)
    if GetResourceState('bs_zombies') ~= 'started' then return false, 'bs_zombies not running' end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false, 'no player ped' end
    local c = GetEntityCoords(ped)
    local rad = math.rad(GetEntityHeading(ped))
    local d = tonumber(data.dist) or 6.0
    local x = c.x - math.sin(rad) * d
    local y = c.y + math.cos(rad) * d
    local typeId = tostring(data.type or 'brute')
    local hp = tonumber(data.hpScale) or 8.0
    local tag = 'boss:' .. src .. ':' .. os.time()
    local ok, id = pcall(function()
        return exports.bs_zombies:EventSpawn(x, y, typeId, { tag = tag, hpScale = hp })
    end)
    if not ok or not id then return false, 'EventSpawn failed: ' .. tostring(id) end
    pcall(function() exports.bs_zombies:EventDrive(tag, c.x, c.y, c.z, 300) end)
    return true, ('%s boss spawned (record %s, hp x%s) %.0fm ahead of %s')
        :format(typeId, tostring(id), tostring(hp), d, GetPlayerName(src) or '?')
end

SetHttpHandler(function(req, res)
    if req.method ~= 'POST' then return reply(res, 405, { error = 'POST only' }) end
    req.setDataHandler(function(body)
        local ok, data = pcall(json.decode, body or '')
        if not ok or type(data) ~= 'table' then return reply(res, 400, { error = 'bad json' }) end
        if ApiToken == '' or data.token ~= ApiToken then
            print('[juno-admin] rejected API call to ' .. tostring(req.path) .. ' (bad token)')
            return reply(res, 403, { error = 'bad token' })
        end
        local path = req.path
        if path == '/players' then
            local out = {}
            for _, id in ipairs(GetPlayers()) do
                out[#out + 1] = { id = tonumber(id), name = GetPlayerName(id), ping = GetPlayerPing(id) }
            end
            return reply(res, 200, { players = out })
        elseif path == '/kick' then
            local okk, msg = doKick(data.id, data.reason)
            return reply(res, okk and 200 or 404, { ok = okk, result = msg })
        elseif path == '/ban' then
            local okk, msg = doBan(data.id, data.reason)
            return reply(res, okk and 200 or 404, { ok = okk, result = msg })
        elseif path == '/unban' then
            local okk, msg = doUnban(data.match)
            return reply(res, 200, { ok = okk, result = msg })
        elseif path == '/bans' then
            local out = {}
            for _, ban in ipairs(Bans) do
                out[#out + 1] = { name = ban.name, reason = ban.reason, date = ban.date, identifiers = ban.identifiers }
            end
            return reply(res, 200, { bans = out })
        elseif path == '/say' then
            print('[juno-admin] announce: ' .. tostring(data.message or ''))
            TriggerClientEvent('chat:addMessage', -1, { args = { 'Server', tostring(data.message or '') } })
            return reply(res, 200, { ok = true })
        elseif path == '/exec' then
            local cmd = tostring(data.command or '')
            if cmd == '' then return reply(res, 400, { ok = false, result = 'no command' }) end
            print('[juno-admin] exec: ' .. cmd)
            ExecuteCommand(cmd)
            return reply(res, 200, { ok = true, result = 'executed: ' .. cmd })
        elseif path == '/livery' then
            local src = resolvePlayer(data)
            if not src then return reply(res, 404, { ok = false, result = 'no such player' }) end
            TriggerClientEvent('juno-admin:livery', src, tonumber(data.livery) or -1)
            return reply(res, 200, { ok = true, result = 'livery applied: ' .. tostring(data.livery) })
        elseif path == '/tune' then
            local src = resolvePlayer(data)
            if not src then return reply(res, 404, { ok = false, result = 'no such player' }) end
            TriggerClientEvent('juno-admin:tune', src)
            return reply(res, 200, { ok = true, result = 'tune sent' })
        elseif path == '/companion_solo' then
            local okk, msg = doCompanionSolo(data)
            return reply(res, okk and 200 or 400, { ok = okk, result = msg })
        elseif path == '/spawnveh' or path == '/heal' or path == '/revive' or path == '/tp'
            or path == '/giveitem' or path == '/givemoney' or path == '/companion'
            or path == '/giveweapon' or path == '/clearstatus' or path == '/zombie'
            or path == '/fsd' or path == '/rig' then
            local src = resolvePlayer(data)
            if not src then return reply(res, 404, { ok = false, result = 'no such player' }) end
            local okk, msg
            if path == '/spawnveh' then okk, msg = doSpawnVeh(src, data.model, data.livery)
            elseif path == '/heal' then okk, msg = doHeal(src)
            elseif path == '/clearstatus' then okk, msg = doClearStatus(src)
            elseif path == '/revive' then okk, msg = doRevive(src)
            elseif path == '/tp' then okk, msg = doTp(src, data)
            elseif path == '/giveitem' then okk, msg = doGiveItem(src, data.item, data.count)
            elseif path == '/giveweapon' then okk, msg = doGiveWeapon(src, data)
            elseif path == '/givemoney' then okk, msg = doGiveMoney(src, data.account, data.amount)
            elseif path == '/companion' then okk, msg = doCompanion(src, data)
            elseif path == '/zombie' then okk, msg = doZombie(src, data)
            elseif path == '/fsd' then okk, msg = doFsd(src, data)
            elseif path == '/rig' then okk, msg = doRig(src, data) end
            print(('[juno-admin] %s -> %s (%s): %s'):format(path, GetPlayerName(src) or '?', src, tostring(msg)))
            return reply(res, okk and 200 or 400, { ok = okk, result = msg })
        elseif path == '/sense' then
            local src = resolvePlayer(data)
            if not src then return reply(res, 404, { ok = false, result = 'no such player' }) end
            local good, r = doSense(src)
            if not good then return reply(res, 202, { ok = false, result = r }) end
            return reply(res, 200, { ok = true, player = GetPlayerName(src), ageSeconds = os.time() - r.at, sense = r.data })
        end
        return reply(res, 404, { error = 'unknown route' })
    end)
end)

-- FSD v2: model layers -------------------------------------------------------
-- D1 decisions via the SystemOne shim on the Mac (tailnet). LM Studio place
-- names via the Mac :1234 -- already-loaded models ONLY, never loads one.
local D1_URL = 'http://YOUR-LM-STUDIO-HOST:8766/v1/systemone/decide'
local LMS_URL = 'http://YOUR-LM-STUDIO-HOST:1234'
FSD_SESSIONS = FSD_SESSIONS or {}

local function d1Choice(state, question, options, cb)
    local criteria = {}
    for _, opt in ipairs(options) do criteria[opt] = opt end
    local payload = {
        model = 'd1-2b',
        state = state,
        questions = { q = { type = 'choice', instructions = question, criteria = criteria } },
        max_tokens = 256,
    }
    PerformHttpRequest(LMS_URL .. '/v1/systemone', function(status, body)
        if status ~= 200 or not body then return cb(nil) end
        local ok, data = pcall(json.decode, body)
        if not ok or not data or not data.answers or not data.answers.q then return cb(nil) end
        cb(data.answers.q.choice)
    end, 'POST', json.encode(payload), { ['Content-Type'] = 'application/json' })
end

local function fsdSay(src, text)
    TriggerClientEvent('chat:addMessage', src, { args = { 'FSD', text } })
end

-- FSD v4: owner lock + vision co-pilot --------------------------------------
local FSD_OWNER_LICENSE = 'license:OWNER_LICENSE_HERE'
local function isFsdOwner(src)
    local lic = GetPlayerIdentifierByType(src, 'license')
    print(('[juno-admin] fsd owner check: lic=%s'):format(tostring(lic)))
    -- accept the bare hash too: the identifier format the game returns
    -- does not byte-match the 'license:...' string stored in bs_users
    if lic then return lic == FSD_OWNER_LICENSE or lic == 'OWNER_LICENSE_HASH_HERE' end
    return GetPlayerName(src) == 'OWNER_PLAYER_NAME'
end

RegisterNetEvent('juno-admin:fsdHello', function()
    local src = source
    local owner = isFsdOwner(src)
    print(('[juno-admin] fsd hello: %s (%s) owner=%s'):format(GetPlayerName(src) or '?', src, tostring(owner)))
    TriggerClientEvent('juno-admin:fsdOwner', src, owner)
end)

local VISION_SYS = 'You are the vision co-pilot for a self-driving car in a zombie survival game. The car has its own driver for steering; you judge the road scene from the driver view camera. Answer with exactly one verdict word, then " - " and a reason of at most six words. Verdicts: CONTINUE (road ahead clear), SLOW (hazard or rough ground ahead), STOP (blocked or immediate danger), PUSH (zombies in the road - safer to push through slowly than stop), REROUTE (road impassable or car stuck off-road).'

local function visionJudge(src, sess, dataUri, ctx)
    local summary = ('Situation: speed %d m/s, %d metres to destination, %d zombies within 35 metres, vehicle health %d percent. What should the car do?')
        :format(math.floor(ctx.speed or 0), math.floor(ctx.dist or 0), ctx.peds or 0, math.floor((ctx.health or 1.0) * 100))
    local payload = {
        model = 'lfm3-vl-2b',
        max_tokens = 60,
        messages = {
            { role = 'system', content = VISION_SYS },
            { role = 'user', content = {
                { type = 'text', text = summary },
                { type = 'image_url', image_url = { url = dataUri } },
            } },
        },
    }
    PerformHttpRequest(LMS_URL .. '/v1/chat/completions', function(status, body)
        sess.visionBusy = false
        if status ~= 200 or not body then return end
        local ok, data = pcall(json.decode, body)
        if not ok or not data or not data.choices or not data.choices[1] then return end
        local text = tostring((data.choices[1].message and data.choices[1].message.content) or '')
        local verdict = text:upper():match('^%s*(%u+)')
        if not verdict or verdict == sess.lastVisionVerdict then return end
        sess.lastVisionVerdict = verdict
        local reason = text:gsub('^[^%-]*%-', ''):gsub('^%s+', ''):sub(1, 60)
        if verdict == 'SLOW' then
            TriggerClientEvent('juno-admin:fsdAdjust', src, 12, 0, 'Vision: slowing - ' .. reason)
        elseif verdict == 'STOP' then
            TriggerClientEvent('juno-admin:fsdStop', src)
            FSD_SESSIONS[src] = nil
            fsdSay(src, 'Vision: stopping - ' .. reason)
        elseif verdict == 'PUSH' then
            TriggerClientEvent('juno-admin:fsdAdjust', src, 0, 786603, 'Vision: push through - ' .. reason)
        elseif verdict == 'REROUTE' then
            TriggerClientEvent('juno-admin:fsdAdjust', src, 0, 1074528293, 'Vision: rerouting - ' .. reason)
        end
    end, 'POST', json.encode(payload), { ['Content-Type'] = 'application/json' })
end

local function visionTick(src, sess, ctx)
    if sess.visionBusy then return end
    if os.time() - (sess.lastVisionAt or 0) < 6 then return end
    if GetResourceState('screenshot-basic') ~= 'started' then return end
    sess.visionBusy = true
    sess.lastVisionAt = os.time()
    exports['screenshot-basic']:requestClientScreenshot(src, { encoding = 'jpg', quality = 0.4 }, function(err, data)
        if err or not data or not FSD_SESSIONS[src] then sess.visionBusy = false return end
        visionJudge(src, sess, data, ctx)
    end)
end

RegisterNetEvent('juno-admin:fsdCtx', function(ctx)
    local src = source
    if not ctx then return end
    if not isFsdOwner(src) then return end
    local sess = FSD_SESSIONS[src]
    if not sess then
        sess = { paceDone = false, lastAt = 0 }
        FSD_SESSIONS[src] = sess
    end
    sess.lastCtx = os.time()
    visionTick(src, sess, ctx)
    local now = os.time()
    if not sess.paceDone and (ctx.dist or -1) >= 0 then
        sess.paceDone = true
        sess.lastPaceAt = now
        local state = ('A self-driving car in a zombie survival world is starting a trip. Distance to destination: %d metres. Zombies nearby: %d. Vehicle health: %d percent.')
            :format(math.floor(ctx.dist), ctx.peds or 0, math.floor((ctx.health or 1.0) * 100))
        d1Choice(state, 'How should the car drive this trip?', { 'careful', 'normal', 'fast' }, function(choice)
            if not FSD_SESSIONS[src] then return end
            if choice == 'careful' then sess.paceSpeed = 25; TriggerClientEvent('juno-admin:fsdAdjust', src, 25, 1076626091, 'D1 verdict: careful pace')
            elseif choice == 'fast' then sess.paceSpeed = 50; TriggerClientEvent('juno-admin:fsdAdjust', src, 50, 786603, 'D1 verdict: fast pace')
            else sess.paceSpeed = 35; TriggerClientEvent('juno-admin:fsdAdjust', src, 35, 1076626091, 'D1 verdict: normal pace') end
        end)
        return
    end
    if sess.paceDone and now - (sess.lastPaceAt or 0) >= 30 and (ctx.dist or 0) > 120 then
        sess.lastPaceAt = now
        local pstate = ('A self-driving car in a zombie survival world is mid-trip. Distance remaining: %d metres. Current speed: %d metres per second. Zombies within 35 metres: %d. Vehicle health: %d percent.')
            :format(math.floor(ctx.dist), math.floor(ctx.speed or 0), ctx.peds or 0, math.floor((ctx.health or 1.0) * 100))
        d1Choice(pstate, 'How should the car drive this trip?', { 'careful', 'normal', 'fast' }, function(choice)
            if not FSD_SESSIONS[src] then return end
            local want = (choice == 'careful' and 25) or (choice == 'fast' and 50) or 35
            if want ~= (sess.paceSpeed or 35) then
                sess.paceSpeed = want
                local style = (choice == 'fast') and 786603 or 447
                TriggerClientEvent('juno-admin:fsdAdjust', src, want, style, 'D1 verdict: pace now ' .. tostring(choice))
            end
        end)
    end
    if now - (sess.lastAt or 0) < 5 then return end
    if (ctx.speed or 99) < 2.0 and ctx.mode == 'goto' and (ctx.dist or 0) > 30 then
        sess.stuckSince = sess.stuckSince or now
    else
        sess.stuckSince = nil
    end
    if sess.stuckSince and now - sess.stuckSince >= 10 then
        sess.lastAt = now
        sess.stuckSince = nil
        local ststate = ('A self-driving car in a zombie survival world has been barely moving (under 2 metres per second) for over 10 seconds with %d metres still to go. It may be stuck off-road or against an obstacle. Zombies within 35 metres: %d. Vehicle health: %d percent.')
            :format(math.floor(ctx.dist or 0), ctx.peds or 0, math.floor((ctx.health or 1.0) * 100))
        d1Choice(ststate, 'The car is barely moving and may be stuck. What should it do?', { 'push_through', 'reroute', 'stop' }, function(choice)
            if not FSD_SESSIONS[src] then return end
            if choice == 'push_through' then TriggerClientEvent('juno-admin:fsdAdjust', src, 0, 786603, 'D1 verdict: pushing through (stuck)')
            elseif choice == 'reroute' then TriggerClientEvent('juno-admin:fsdAdjust', src, 0, 1074528293, 'D1 verdict: rerouting (stuck)')
            elseif choice == 'stop' then TriggerClientEvent('juno-admin:fsdStop', src); FSD_SESSIONS[src] = nil end
        end)
        return
    end
    if (ctx.stopped or 0) >= 6 and ctx.mode == 'goto' then
        sess.lastAt = now
        local state = ('A self-driving car in a zombie survival world has been blocked and unable to move for %d seconds. Zombies within 35 metres: %d. Vehicle health: %d percent.')
            :format(math.floor(ctx.stopped), ctx.peds or 0, math.floor((ctx.health or 1.0) * 100))
        d1Choice(state, 'The car is blocked and cannot move. What should it do?', { 'wait', 'push_through', 'reroute', 'stop' }, function(choice)
            if not FSD_SESSIONS[src] then return end
            if choice == 'push_through' then TriggerClientEvent('juno-admin:fsdAdjust', src, 0, 786603, 'D1 verdict: pushing through')
            elseif choice == 'reroute' then TriggerClientEvent('juno-admin:fsdAdjust', src, 0, 1074528293, 'D1 verdict: rerouting')
            elseif choice == 'stop' then TriggerClientEvent('juno-admin:fsdStop', src); FSD_SESSIONS[src] = nil
            else TriggerClientEvent('juno-admin:fsdAdjust', src, 0, 0, 'D1 verdict: waiting it out') end
        end)
    elseif (ctx.peds or 0) >= 6 and (ctx.health or 1.0) < 0.45 then
        sess.lastAt = now
        local state = ('A self-driving car in a zombie survival world is surrounded: %d zombies within 35 metres and vehicle health is down to %d percent.')
            :format(ctx.peds or 0, math.floor((ctx.health or 1.0) * 100))
        d1Choice(state, 'The car is in danger. What should it do?', { 'flee_fast', 'keep_driving', 'stop' }, function(choice)
            if not FSD_SESSIONS[src] then return end
            if choice == 'flee_fast' then TriggerClientEvent('juno-admin:fsdAdjust', src, 55, 786603, 'D1 verdict: getting out of here')
            elseif choice == 'stop' then TriggerClientEvent('juno-admin:fsdStop', src); FSD_SESSIONS[src] = nil
            else TriggerClientEvent('juno-admin:fsdAdjust', src, 0, 0, 'D1 verdict: keep driving') end
        end)
    end
end)

AddEventHandler('playerDropped', function()
    FSD_SESSIONS[source] = nil
end)

-- Place names: gazetteer first, then an already-loaded LM Studio model.
local PLACES = {
    ['camp'] = { 1863.8, 3673.8, 33.5 }, ['sandy camp'] = { 1863.8, 3673.8, 33.5 }, ['home'] = { 1863.8, 3673.8, 33.5 },
    ['fort zancudo'] = { -2300.0, 3265.0, 33.0 }, ['zancudo'] = { -2300.0, 3265.0, 33.0 }, ['the base'] = { -2300.0, 3265.0, 33.0 }, ['military base'] = { -2300.0, 3265.0, 33.0 },
    ['sandy airfield'] = { 1730.0, 3470.0, 42.0 }, ['airfield'] = { 1730.0, 3470.0, 42.0 }, ['dead signal'] = { 1730.0, 3470.0, 42.0 },
    ['quartermaster'] = { 1744.7, 3296.1, 42.0 },
    ['legion square'] = { 215.0, -860.0, 30.0 }, ['legion'] = { 215.0, -860.0, 30.0 },
    ['mission row'] = { 440.0, -985.0, 30.0 },
    ['pillbox hill'] = { 300.0, -585.0, 30.0 }, ['pillbox'] = { 300.0, -585.0, 30.0 },
    ['vespucci'] = { -1095.0, -835.0, 20.0 },
    ['humane labs'] = { 3570.0, 3750.0, 30.0 }, ['humane'] = { 3570.0, 3750.0, 30.0 },
    ['bolingbroke'] = { 1700.0, 2600.0, 40.0 }, ['prison'] = { 1700.0, 2600.0, 40.0 },
    ['sandy sheriff'] = { 1855.0, 3685.0, 40.0 },
    ['paleto'] = { -445.0, 6015.0, 32.0 }, ['paleto bay'] = { -445.0, 6015.0, 32.0 },
    ['sandy medical'] = { 1840.0, 3670.0, 34.0 },
    ['paleto medical'] = { -250.0, 6320.0, 32.0 },
}

local function driveToPlace(src, key)
    local c = PLACES[key]
    if not c then return false end
    FSD_SESSIONS[src] = { paceDone = false, lastAt = 0 }
    TriggerClientEvent('juno-admin:fsdGo', src, c[1], c[2], c[3], nil, nil)
    fsdSay(src, 'driving to ' .. key)
    return true
end

function FsdResolvePlace(src, text)
    if not text or text == '' then return end
    local want = text:lower()
    for key in pairs(PLACES) do
        if want:find(key, 1, true) or key:find(want, 1, true) then
            if driveToPlace(src, key) then return end
        end
    end
    -- No gazetteer hit: ask an already-loaded chat model on the Mac.
    PerformHttpRequest(LMS_URL .. '/api/v0/models', function(status, body)
        if status ~= 200 or not body then fsdSay(src, 'no brain reachable -- Juno can route you'); return end
        local ok, data = pcall(json.decode, body)
        if not ok or not data or not data.data then fsdSay(src, 'no brain reachable -- Juno can route you'); return end
        local model = nil
        for _, m in ipairs(data.data) do
            if m.state == 'loaded' and (m.type == 'llm' or m.type == 'vlm') then model = m.id break end
        end
        if not model then fsdSay(src, 'no chat model loaded on the Mac -- Juno can route you'); return end
        local keys = {}
        for key in pairs(PLACES) do keys[#keys + 1] = key end
        table.sort(keys)
        local sys = 'You route a self-driving car in GTA V. The driver names a place. Reply with ONLY this JSON: {"place": "<key>"} using one key from this list, or {"place": null} if none fits. Keys: ' .. table.concat(keys, ', ')
        PerformHttpRequest(LMS_URL .. '/v1/chat/completions', function(st2, body2)
            if st2 ~= 200 or not body2 then fsdSay(src, 'the brain did not answer -- Juno can route you'); return end
            local ok2, data2 = pcall(json.decode, body2)
            local content = ok2 and data2 and data2.choices and data2.choices[1] and data2.choices[1].message and data2.choices[1].message.content or ''
            local key = content:match('"place"%s*:%s*"([^"]+)"')
            if key and PLACES[key] then driveToPlace(src, key)
            else fsdSay(src, 'could not place that -- Juno can route you') end
        end, 'POST', json.encode({ model = model, temperature = 0.0, max_tokens = 60,
            messages = { { role = 'system', content = sys }, { role = 'user', content = text } } }),
        { ['Content-Type'] = 'application/json' })
    end, 'GET', '', { ['Content-Type'] = 'application/json' })
end

RegisterNetEvent('juno-admin:fsdPlace', function(text)
    if not isFsdOwner(source) then return end
    FsdResolvePlace(source, text)
end)
