-- This file is separate from strings.lua because it's not translated.
-- TODO: We could generate this from our translations, but it's probably not worth the effort.

local LANGUAGE = require "languages.langs"

STRINGS.PRETRANSLATED = {
	LANGUAGE_NAMES = {
		-- Use to display language native names so users can easily recognize
		-- their language in the list regardless of the currently selected
		-- language.
		[LANGUAGE.ENGLISH] = "English",
		[LANGUAGE.FRENCH] = "Français",
		[LANGUAGE.SPANISH] = "Español - España",
		[LANGUAGE.SPANISH_LA] = "Español - Latinoamérica",
		[LANGUAGE.GERMAN] = "Deutsch",
		[LANGUAGE.ITALIAN] = "Italiano",
		[LANGUAGE.JAPANESE] = "日本語",
		[LANGUAGE.PORTUGUESE] = "Português - Portugal",
		[LANGUAGE.PORTUGUESE_BR] = "Português - Brasil",
		[LANGUAGE.POLISH] = "Polski",
		[LANGUAGE.RUSSIAN] = "Русский",
		[LANGUAGE.KOREAN] = "한국어",
		[LANGUAGE.CHINESE_S] = "简体中文",
		[LANGUAGE.CHINESE_T] = "繁體中文",
		["uk"] = "Українська", -- Rotwood-UA (DLC ukua)
	},

	--~ ENGLISH_NAMES = {
	--~ 	-- Use these when creating scripts/localizations/*.lua to match our style.
	--~ 	[LANGUAGE.ENGLISH] = "English",
	--~ 	[LANGUAGE.FRENCH] = "French",
	--~ 	[LANGUAGE.SPANISH] = "Spanish - Spain",
	--~ 	[LANGUAGE.SPANISH_LA] = "Spanish - Latin America",
	--~ 	[LANGUAGE.GERMAN] = "German",
	--~ 	[LANGUAGE.ITALIAN] = "Italian",
	--~ 	[LANGUAGE.JAPANESE] = "Japanese",
	--~ 	[LANGUAGE.PORTUGUESE] = "Portuguese - Portugal",
	--~ 	[LANGUAGE.PORTUGUESE_BR] = "Portuguese - Brazil",
	--~ 	[LANGUAGE.POLISH] = "Polish",
	--~ 	[LANGUAGE.RUSSIAN] = "Russian",
	--~ 	[LANGUAGE.KOREAN] = "Korean",
	--~ 	[LANGUAGE.CHINESE_S] = "Simplified Chinese",
	--~ 	[LANGUAGE.CHINESE_T] = "Traditional Chinese",
	--~ },

}
