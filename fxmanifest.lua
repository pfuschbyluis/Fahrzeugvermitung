fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'MB_Fahrzeugvermitung'
author 'MB'
description 'Fahrzeugvermietung'
version '1.2.8'

shared_script 'config.lua'

client_scripts {
    'client/main.lua'
}

exports {
    'GetUIColorScheme',
    'IsUIDarkMode'
}

server_scripts {
    'server/errors.lua',
    'server/main.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'html/img/*.png',
    'html/img/*.jpg',
    'html/img/*.jpeg',
    'html/img/*.webp',
    'html/img/*.svg',
    'html/fonts/*.ttf',

    'data/admin_vehicles.json',
    'data/rental_contracts.json',
    'data/error_log.json',
    'admin_vehicles.json',
    'rental_contracts.json'
}

dependencies {
    'ox_target',
    'ox_inventory'
}
