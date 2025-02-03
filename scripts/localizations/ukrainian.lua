local Localization = require "questral.localization"
return Localization {
	id = "uk",
	incomplete = true,
	name = "Ukrainian",
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
}

