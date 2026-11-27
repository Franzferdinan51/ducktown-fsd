fx_version 'cerulean'
game 'gta5'

author 'Juno (for Duckets)'
description 'Juno server admin: moderation (kick/ban/unban) + in-game admin actions (spawn vehicle, heal, revive, teleport, give item/money) + the juno-companion ped body, via a token-gated HTTP API for the fivem-admin CLI'
version '1.4.1'

server_scripts {
    'server.lua'
}

client_scripts {
    '@ox_lib/init.lua',
    'client.lua'
}

dependencies {
    'ox_lib'
}
