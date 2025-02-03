_G = GLOBAL
require "util.kstring"
local select = _G.select
local assert = _G.assert
local next = _G.next
local TheGameContent = _G.TheGameContent
local TheSim = _G.TheSim
local Sim = _G.Sim
local ModManager = _G.ModManager
local STRINGS = _G.STRINGS
local FONTFACE = _G.FONTFACE
local UICOLORS = _G.UICOLORS
local FONTSIZE = _G.FONTSIZE
local lume = require "util.lume"
local strict = require "util.strict"
local kassert = require "util.kassert"
local tostring = _G.tostring
local Text = require "widgets.text"
local LANGUAGE = require "languages.langs"
local loc = require "questral.util.loc"
local contentloader = require "content.contentloader"

LANGUAGE.UKRAINIAN = "uk"

Assets = {
  Asset("FONT", "fonts/blockhead_sdf_uk.zip"),
}

local fallback_font = "fallback_font"
local DEFAULT_FALLBACK_TABLE = {
	fallback_font,
}
local font_posfix = "_uk"
local uk_font = { filename = "fonts/blockhead_sdf"..font_posfix..".zip", alias = "blockhead", fallback = DEFAULT_FALLBACK_TABLE, sdfthreshold = 0.44, sdfboldthreshold = 0.2 }

local function ApplyLocalizedFonts()
	TheSim:UnloadFont(uk_font.alias)
	TheSim:UnloadPrefabs({"uk_fonts"})

	local FontsPrefab = _G.Prefab("uk_fonts", function() return _G.CreateEntity() end, Assets)
	_G.RegisterPrefabs(FontsPrefab)
	TheSim:LoadPrefabs({"uk_fonts"})

	TheSim:LoadFont(
		_G.resolvefilepath(uk_font.filename),
		uk_font.alias,
		uk_font.sdfthreshold,
		uk_font.sdfboldthreshold,
		uk_font.sdfshadowthreshold,
		uk_font.supportsItalics
	)
	TheSim:SetupFontFallbacks(uk_font.alias, uk_font.fallback)
end

local _UnregisterAllPrefabs = Sim.UnregisterAllPrefabs
Sim.UnregisterAllPrefabs = function(self, ...)
	_UnregisterAllPrefabs(self, ...)
	ApplyLocalizedFonts()
end

local _RegisterPrefabs = ModManager.RegisterPrefabs
ModManager.RegisterPrefabs = function(self, ...)
	_RegisterPrefabs(self, ...)
	ApplyLocalizedFonts()
end

local _Start = Start
function Start(...) 
	ApplyLocalizedFonts()
	return _Start(...)
end

--local filter = _G.ProfanityFilter()
--filter:AddDictionary("ua", {
--	-- These only match at word boundaries. (Grouchy doesn't match).
--	exact_match = {
--		[strhash("блядь")] = true,
--		[strhash("сука")] = true,
--		[strhash("кончений")] = true,
--	},
--	-- These match occurrences of these characters inside other words. It's
--	-- a json-encoded string.
--	loose_match = '["пізда", "член", "єба", "блядь", "довбойоб", "підор"]',
--})

if GetModConfigData("auto_update") then
	LocUpdate = require "loc_update"
	LocUpdate.BRANCH = _G.RELEASE_CHANNEL == "dev" and "main_beta" or "main"
	LocUpdate.PATH = MODROOT.."localizations/"
	LocUpdate:CheckUpdate()
end

AddClassPostConstruct("screens/mainscreen", function(self, profile, skip_start)
	local bottom_pad = 60
	local ver_f = _G.io.open(MODROOT.."localizations/version.txt", "r")
	if ver_f then
		local year, month, day = ver_f:read("*all"):match("(%d+)%-(%d+)%-(%d+)")
		local rev = string.format("ПЕРЕКЛАД ВІД: %02d.%02d", day, month)
		ver_f:close()
		
		self.translatename = self:AddChild(Text(FONTFACE.DEFAULT, 42))
			:SetGlyphColor(UICOLORS.WHITE)
			:SetHAlign(_G.ANCHOR_RIGHT)
			:SetText(rev)
			:LayoutBounds("right", "top", self)
			:Offset(-bottom_pad, -bottom_pad)
			
		self.updatename
			:LayoutBounds("right", "top", self)
			:Offset(-bottom_pad, -bottom_pad * 1.7)
	end
end)

local function ReplaceNameInString(str, fns, clear_names)
	if str:find("{", nil, true) and clear_names == false then -- TODO(PERF): Does skipping gsub for plain strings help load perf?
		-- Prefabs names are limited to lowercase letters, numbers, and
		-- underscore.
		
		str = str:gsub('([?:#*%%]){name.([_a-z0-9]-)}', fns.lower_singular)
		str = str:gsub('{name.([_a-z0-9]-)}', fns.lower_singular)
		str = str:gsub('([?:#*%%]){name_multiple.([_a-z0-9]-)}', fns.lower_plural)
		str = str:gsub('{name_multiple.([_a-z0-9]-)}', fns.lower_plural)
		str = str:gsub('{name_plurality.([_a-z0-9]-)}', fns.lower_plurality)
		
		str = str:gsub('([?:#*%%]){Name.([_a-z0-9]-)}', fns.singular)
		str = str:gsub('{Name.([_a-z0-9]-)}', fns.singular)
		str = str:gsub('([?:#*%%]){Name_multiple.([_a-z0-9]-)}', fns.plural)
		str = str:gsub('{Name_multiple.([_a-z0-9]-)}', fns.plural)
		str = str:gsub('{Name_plurality.([_a-z0-9]-)}', fns.plurality)

		str = str:gsub('{([?:#*%%])NAME.([_a-z0-9]-)}', fns.upper_singular)
		str = str:gsub('{NAME.([_a-z0-9]-)}', fns.upper_singular)
		str = str:gsub('{([?:#*%%])NAME_MULTIPLE.([_a-z0-9]-)}', fns.upper_plural)
		str = str:gsub('{NAME_MULTIPLE.([_a-z0-9]-)}', fns.upper_plural)
		str = str:gsub('{NAME_PLURALITY.([_a-z0-9]-)}', fns.upper_plurality)
	elseif clear_names == true then
		local tokens = {}
		tokens = str:split_pattern("|")
		str = #tokens > 0 and tokens[1] or str
	end
	return str
end

local function ReplaceNameInTable(string_table, fns, clear_names)
	for k,v in pairs(string_table) do
		if loc.IsValidStringKey(k) then
			if type(v) == "string" then
				string_table[k] = loc.format(ReplaceNameInString(v, fns, clear_names), 1, 2, 3, 4, 5)
			elseif type(v) == "table" then
				ReplaceNameInTable(v, fns, clear_names)
			end
		end
	end
end

function loc.ReplaceNames(string_table, name_table_singular, name_table_plural, name_table_plurality, clear_names)
    local fns = {}
	local clear_names = clear_names or false

	fns.singular = function(operand, _key)
		local key = _key or operand
		local name = name_table_singular[key]
		kassert.assert_fmt(name, "Unknown name. Did you forget to add '%s' to STRINGS.NAMES?", key)
		if _key == nil then
			local tokens = {}
			tokens = name:split_pattern("|")
			return #tokens > 0 and tokens[1] or name_table_singular[key] or key
		else
			return operand..name_table_singular[key] or key
		end
	end
	fns.plural = function(operand, _key)
		local key = _key or operand
		local name = name_table_plural[key]
		kassert.assert_fmt(name, "Unknown name. Did you forget to add '%s' to STRING_METADATA.NAMES_PLURAL?", key)
		if _key == nil then
			local tokens = {}
			tokens = name:split_pattern("|")
			return #tokens > 0 and tokens[1] or name_table_plural[key] or key
		else
			return operand..name_table_plural[key] or key
		end
	end
	fns.plural_alt = function(key)
		local name = name_table_plural[key]
		kassert.assert_fmt(name, "Unknown name. Did you forget to add '%s' to STRING_METADATA.NAMES_PLURAL?", key)
		local split_i = name:find('||')
		return split_i and name:sub(split_i + 2) or name_table_plural[key] or key
	end
	fns.plurality = function(key)
		-- This table is created with loc.BuildPlurality.
		local name = name_table_plurality[key]
		kassert.assert_fmt(name, "Unknown name. Did you forget to add '%s' to STRING_METADATA.NAMES_PLURAL?", key)
		return name_table_plurality[key] or key
	end

    for _,k in ipairs(lume.keys(fns)) do
        fns["lower_".. k] = function(operand, _key)
            local name = fns[k](operand, _key)
            -- TODO: no longer safe to lower because transforms translated strings.
            return name:lower()
        end
    end

    for _,k in ipairs(lume.keys(fns)) do
        fns["upper_".. k] = function(operand, _key)
            local name = fns[k](operand, _key)
            -- TODO: no longer safe to upper because transforms translated strings.
            return name:upper()
        end
    end

    strict.strictify(fns)
    ReplaceNameInTable(string_table, fns, clear_names)
end

local _PostLoadStrings = contentloader.PostLoadStrings
function contentloader.PostLoadStrings(...)
	_PostLoadStrings(...)
	loc.ReplaceNames(STRINGS.NAMES, {}, {}, {}, true)
end

TheGameContent:GetContentDB():LoadScript("scripts/localizations/ukrainian.lua")
TheGameContent:SetLanguage()
TheGameContent:LoadLanguageDisplayElements()

STRINGS.PRETRANSLATED.LANGUAGES[LANGUAGE.UKRAINIAN] = "Українська (Ukrainian)"
STRINGS.PRETRANSLATED.LANGUAGES_TITLE[LANGUAGE.UKRAINIAN] = "Варіант перекладу"
STRINGS.PRETRANSLATED.LANGUAGES_BODY[LANGUAGE.UKRAINIAN] = "В якості мови інтерфейсу вибрана українська. Вам потрібен переклад на вашу мову?"
STRINGS.PRETRANSLATED.LANGUAGES_YES[LANGUAGE.UKRAINIAN] = "Так"
STRINGS.PRETRANSLATED.LANGUAGES_NO[LANGUAGE.UKRAINIAN] = "Ні"
