local Localization = require "questral.localization"
return Localization {
	id = "uk",
	incomplete = true,
	name = "Ukrainian",
	fonts =
	{
		title = { font = "fonts/blockhead_sdf.zip", sdfthreshold = 0.36, sdfboldthreshold = 0.30 },
		body = { font = "fonts/blockhead_sdf.zip", sdfthreshold = 0.4, sdfboldthreshold = 0.33 },
		button = { font = "fonts/blockhead_sdf.zip", sdfthreshold = 0.4, sdfboldthreshold = 0.33 },
		tooltip = { font = "fonts/blockhead_sdf.zip", sdfthreshold = 0.4, sdfboldthreshold = 0.33 },
		speech = { font = "fonts/blockhead_sdf.zip", sdfthreshold = 0.4, sdfboldthreshold = 0.33 },
	},
	
	can_display_italic = true,
	can_display_bold = false,

	po_filenames = {
		"localizations/uk.po",
	},

	default_languages =
	{
		"uk",
	},
}

