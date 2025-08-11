return {
	mod_type = "translation",
	api_version = 1,
	mod_version = "1.0",
	version = "1.0",
	author = "Godless",
	name = "Ukrainian Language",
	description = "Translation of the game into Ukrainian",

	icon_atlas = "modicon.png",
	icon = "modicon.png",

	supports_mode = {
		rotwood = true
	},

	translation = {
		id = "uk",
		name = "Ukrainian",
		incomplete = true,
		fonts =
		{
			blockhead = { font = "fonts/blockhead_sdf_uk.zip", sdfthreshold = 0.4, sdfboldthreshold = 0.33 },
			title = { font = "fonts/blockhead_sdf_uk.zip", sdfthreshold = 0.5, sdfboldthreshold = 0.33, scale = 0.6, line_height_scale = 0.85 },
		},

		can_display_italic = true,
		can_display_bold = true,

		po_filenames = {
			"localizations/uk.po",
			"localizations/main.po",
		},

		default_languages =
		{
			"uk",
		},
	},

	client_only_mod = true,
	all_clients_require_mod = false,

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
}
