-- uk_boot.lua
-- Порт modmain.lua з Rotwood-UA для запуску через DLC (без завантажувача модів).
-- Підключається одним рядком з fonts.lua. Зміни поведінки діють ТІЛЬКИ коли активна
-- мова "uk"; для інших мов все працює як у ванілі. Помилки не валять гру (pcall).

local function log(...)
	print("[UK_BOOT]", ...)
end

local function IsUkActive()
	local content = rawget(_G, "TheGameContent")
	local localization = content and content.localization
	return localization ~= nil and localization.id == "uk"
end

local function Install()
	require "util.kstring"
	local lume = require "util.lume"
	local strict = require "util.strict"
	local kassert = require "util.kassert"
	local loc = require "questral.util.loc"
	local contentloader = require "content.contentloader"
	local LANGUAGE = require "languages.langs"

	LANGUAGE.UKRAINIAN = "uk"

	----------------------------------------------------------------------
	-- ReplaceNames (з modmain.lua). Для не-uk мов викликається ванільна версія.
	----------------------------------------------------------------------
	local vanilla_ReplaceNames = loc.ReplaceNames

	local function ReplaceNameInString(str, fns, clear_names)
		if str:find("{", nil, true) and clear_names == false then
			-- Prefabs names are limited to lowercase letters, numbers, and underscore.
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

			-- Як у ванільній версії: {nbsp} -> нерозривний пробіл.
			str = str:gsub('{nbsp}', "\u{00a0}")
		elseif clear_names == true then
			local tokens = str:split_pattern("|")
			str = #tokens > 0 and tokens[1] or str
		end
		return str
	end

	local function ReplaceNameInTable(string_table, fns, clear_names)
		for k, v in pairs(string_table) do
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
		if not IsUkActive() then
			return vanilla_ReplaceNames(string_table, name_table_singular, name_table_plural, name_table_plurality)
		end

		local fns = {}
		clear_names = clear_names or false

		fns.singular = function(operand, _key)
			local key = _key or operand
			local name = name_table_singular[key]
			kassert.assert_fmt(name, "Unknown name. Did you forget to add '%s' to STRINGS.NAMES?", key)
			if _key == nil then
				local tokens = name:split_pattern("|")
				return #tokens > 0 and tokens[1] or name_table_singular[key] or key
			else
				return operand .. name_table_singular[key] or key
			end
		end
		fns.plural = function(operand, _key)
			local key = _key or operand
			local name = name_table_plural[key]
			kassert.assert_fmt(name, "Unknown name. Did you forget to add '%s' to STRING_METADATA.NAMES_PLURAL?", key)
			if _key == nil then
				local tokens = name:split_pattern("|")
				return #tokens > 0 and tokens[1] or name_table_plural[key] or key
			else
				return operand .. name_table_plural[key] or key
			end
		end
		fns.plural_alt = function(key)
			local name = name_table_plural[key]
			kassert.assert_fmt(name, "Unknown name. Did you forget to add '%s' to STRING_METADATA.NAMES_PLURAL?", key)
			local split_i = name:find('||')
			return split_i and name:sub(split_i + 2) or name_table_plural[key] or key
		end
		fns.plurality = function(key)
			local name = name_table_plurality[key]
			kassert.assert_fmt(name, "Unknown name. Did you forget to add '%s' to STRING_METADATA.NAMES_PLURAL?", key)
			return name_table_plurality[key] or key
		end

		for _, k in ipairs(lume.keys(fns)) do
			fns["lower_" .. k] = function(operand, _key)
				local name = fns[k](operand, _key)
				name = name:lower()
				name = name:gsub("<#(.-)>", function(color)
					return "<#" .. color:upper() .. ">"
				end)
				return name
			end
		end

		for _, k in ipairs(lume.keys(fns)) do
			fns["upper_" .. k] = function(operand, _key)
				local name = fns[k](operand, _key)
				return name:upper()
			end
		end

		strict.strictify(fns)
		ReplaceNameInTable(string_table, fns, clear_names)
	end

	----------------------------------------------------------------------
	-- PostLoadStrings: назва мови в списку + зачистка "|" у STRINGS.NAMES
	----------------------------------------------------------------------
	local _PostLoadStrings = contentloader.PostLoadStrings
	function contentloader.PostLoadStrings(...)
		pcall(function()
			local names = STRINGS.PRETRANSLATED.LANGUAGE_NAMES
			if names[LANGUAGE.UKRAINIAN] == nil then
				names[LANGUAGE.UKRAINIAN] = "Українська"
			end
		end)
		_PostLoadStrings(...)
		if IsUkActive() then
			local ok, err = pcall(loc.ReplaceNames, STRINGS.NAMES, {}, {}, {}, true)
			if not ok then
				log("clear_names failed:", err)
			end
		end
	end

	----------------------------------------------------------------------
	-- Переклад MOTD (новини на головному екрані)
	----------------------------------------------------------------------
	local ok_motd, MotdManager = pcall(require, "motdmanager")
	if ok_motd and type(MotdManager) == "table" and MotdManager.SetMotdInfo then
		local translateExact = {
			["A Delicious Update!"] = "Смачне оновлення!",
			["<#686971>A new power family, farming, cooking, Frenzied Swarm and The Molded Grave!</>"] =
			"<#686971>Нова категорія сил, сільське господарство, кулінарія, Божевільне болото та Запліснявіла могила!</>",
			["<#1C214E>Looking for people to play with?</>"] = "<#1C214E>Шукаєте людей для гри?</>",
			["<#505E42>Check out the Latest Hotfix</>"] = "<#505E42>Перегляньте останній хотфікс</>",
		}
		local translatePattern = {
			["members"] = "підписників",
			["Hotfix"] = "Хотфікс",
			["days\nago"] = "днів\nназад",
		}

		local function translateField(field)
			if type(field) ~= "string" then
				return field
			end
			if translateExact[field] then
				return translateExact[field]
			end
			for pattern, replacement in pairs(translatePattern) do
				field = field:gsub(pattern, replacement)
			end
			return field
		end

		local _SetMotdInfo = MotdManager.SetMotdInfo
		function MotdManager:SetMotdInfo(info, ...)
			if IsUkActive() and type(info) == "table" then
				pcall(function()
					for _, cell in pairs(info) do
						if type(cell) == "table" and type(cell.data) == "table" then
							cell.data.title = translateField(cell.data.title)
							cell.data.text = translateField(cell.data.text)
							cell.data.corner_text = translateField(cell.data.corner_text)
						end
					end
				end)
			end
			return _SetMotdInfo(self, info, ...)
		end
	end

	----------------------------------------------------------------------
	-- Підпис «ПЕРЕКЛАД ВІД: ДД.ММ» на головному екрані.
	-- Дату записує update_ukua.ps1 у scripts/uk_version.lua (return "РРРР-ММ-ДД").
	-- MainScreen завантажується пізніше за fonts.lua, тому чіпляємось через require.
	----------------------------------------------------------------------
	local function GetTranslationLabel()
		local ok, date = pcall(require, "uk_version")
		if not ok or type(date) ~= "string" then
			return nil
		end
		local year, month, day = date:match("(%d+)%-(%d+)%-(%d+)")
		if not day then
			return nil
		end
		return string.format("ПЕРЕКЛАД ВІД: %02d.%02d", tonumber(day), tonumber(month))
	end

	local function PatchMainScreen(MainScreen)
		if type(MainScreen) ~= "table" or MainScreen._uk_patched or type(MainScreen._ctor) ~= "function" then
			return
		end
		MainScreen._uk_patched = true
		local _ctor = MainScreen._ctor
		MainScreen._ctor = function(self, ...)
			_ctor(self, ...)
			if not IsUkActive() then
				return
			end
			local ok, err = pcall(function()
				local label = GetTranslationLabel()
				if not label then
					return
				end
				local Text = require "widgets.text"
				local bottom_pad = 60
				self.translatename = self:AddChild(Text(FONTFACE.DEFAULT, 42))
					:SetGlyphColor(UICOLORS.WHITE)
					:SetHAlign(ANCHOR_RIGHT)
					:SetText(label)
					:LayoutBounds("right", "top", self)
					:Offset(-bottom_pad, -bottom_pad)
				if self.updatename then
					self.updatename
						:LayoutBounds("right", "top", self)
						:Offset(-bottom_pad, -bottom_pad * 1.7)
				end
			end)
			if not ok then
				log("translation label failed:", err)
			end
		end
	end

	local _require = require
	function require(name, ...)
		local result = _require(name, ...)
		if name == "screens.mainscreen" then
			pcall(PatchMainScreen, result)
		end
		return result
	end
	-- Якщо MainScreen вже завантажено до нас.
	if package.loaded["screens.mainscreen"] then
		pcall(PatchMainScreen, package.loaded["screens.mainscreen"])
	end

	log("installed")
end

local ok, err = pcall(Install)
if not ok then
	log("install failed, game continues with vanilla behaviour:", err)
end
