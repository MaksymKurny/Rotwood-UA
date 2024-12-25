local Localization = require "questral.localization"
return Localization {
	id = "uk",
	incomplete = true,
	name = "Ukrainian",
	fonts =
	{
		title = { font = "fonts/fallback_full_packed_sdf_uk.zip", sdfthreshold = 0.36, sdfboldthreshold = 0.30 },
		body = { font = "fonts/fallback_full_packed_sdf_uk.zip", sdfthreshold = 0.4, sdfboldthreshold = 0.33 },
		button = { font = "fonts/fallback_full_packed_sdf_uk.zip", sdfthreshold = 0.4, sdfboldthreshold = 0.33 },
		tooltip = { font = "fonts/fallback_full_packed_sdf_uk.zip", sdfthreshold = 0.4, sdfboldthreshold = 0.33 },
		speech = { font = "fonts/fallback_full_packed_sdf_uk.zip", sdfthreshold = 0.4, sdfboldthreshold = 0.33 },
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

