fx_version 'cerulean'
game 'gta5'

author 'Chawa'
description 'Chopshop with different tiers'
version '1.0.0'

dependencies {
    'ox_target'
}

shared_scripts {
    '@ox_lib/init.lua',
    'shared.lua'
}

client_script 'client.lua'
server_script 'server.lua'

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/script.js',
    'ui/paper-bg.png',
    'ui/MissionPassed.mp3',
    'list_data.json'
}