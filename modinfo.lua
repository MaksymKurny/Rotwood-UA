name = "Ukrainian Language"
description = "Translation of the game into Ukrainian"
author = "Godless"
version = "1.0"
api_version = 10

rotwood_compatible = true

icon_atlas = "modicon.png"
icon = "modicon.png"

client_only_mod = true
all_clients_require_mod = false

configuration_options = {
	{
        name = "auto_update",
		label = "Auto update",
		hover = "Automatically update the translation file as soon as a new version is available",
        options =
        {
            {description = "Yes", data = true},
            {description = "No", data = false},
        },
        default = true,
    },
}