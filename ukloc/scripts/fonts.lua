
local defaultfont = "blockhead"

FONTFACE = {
	DEFAULT = defaultfont,
	TITLE = defaultfont,
	BUTTON = defaultfont,
	NUMBERS = defaultfont,
	CHAT = defaultfont, -- users talking to each other
	HEADER = defaultfont,
	BODYTEXT = defaultfont,
	CODE = "inconsolata",
}
-- See constants.lua for FONTSIZE table.


-- TODO(L10n): We should use Localization to load fonts instead of
-- this since it allows easier custom fonts per language.
local font_posfix = ""

-- These extra glyph fonts are only used as fallbacks.
local fallback_font = "fallback_font"
local DEFAULT_FALLBACK_TABLE = {
	fallback_font,
}


FONTS = {
	{ filename = "fonts/inconsolata_sdf"..font_posfix..".zip", alias = FONTFACE.CODE },
	{ filename = "fonts/blockhead_sdf"..font_posfix..".zip", alias = FONTFACE.DEFAULT, fallback = DEFAULT_FALLBACK_TABLE, sdfthreshold = 0.44, sdfboldthreshold = 0.2 },
	{ filename = "fonts/fallback_full_packed_sdf"..font_posfix..".zip", alias = fallback_font},
}

-- Rotwood-UA (DLC ukua): підключення українського перекладу; помилки не критичні.
local uk_ok, uk_err = pcall(require, "uk_boot")
if not uk_ok then print("[UK_BOOT] require failed:", uk_err) end
