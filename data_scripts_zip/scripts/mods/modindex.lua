-- The KnownModIndex tracks mods that have been installed and whether they've
-- caused issues in the past. It helps prevent automatically enabling mods that
-- caused crashes.

local DataDumper = require "util.datadumper"
local Enum = require "util.enum"
local LIST_FILES = require "util.listfilesenum"
local iterator = require "util.iterator"
local lume = require "util.lume"
require "mods"
require "modutil"

local MOD_CONFIG_ROOT = "mod_config_data/"

local ModIndex = Class(function(self)
	self.startingup = false
	self.cached_data = {}
	self.savedata = {
		known_mods = {},
		known_api_version = 0,
	}
	self.mod_dependencies = {
		server_dependency_list = {},
		dependency_list = {},
	}
	self.modsettings = {
		disablemods = {},
		forceenable = {},
		initdebugprint = {},
		localmodwarning = {},
		moderror = {},
	}
end)

--[[
known_mods = {
	[modname] = {
		enabled = true,
		disabled_bad = true,
		modinfo = {
			mod_version = "1.2",
			api_version = 2,
			failed = false,
		},
	}
}
--]]

local ModType = Enum{
	"translation",
	"gameplay",
}

function ModIndex:_GetModIndexFileName(suffix)
	return "modindex_" .. suffix
end

function ModIndex:GetModConfigurationPath(modname, client_config)
	local name = "modconfig_" .. modname
	return MOD_CONFIG_ROOT .. name
end

local LoadState = Enum{
	"InStartupSequence",
	"Done",
}

function ModIndex:_GetModDirs()
	return TheSim:ListFiles("MODS:", "*", LIST_FILES.DIRS)
end

-- Write a canary file so if we hard crash during mod loading, we can disable
-- all mods on next startup.
function ModIndex:BeginStartupSequence(cb)
	self.startingup = true

	local filename = self:_GetModIndexFileName("boot_canary")
	TheSim:GetPersistentString(filename, function(load_success, str)
		local was_failed_load = load_success and str == LoadState.s.InStartupSequence
		if was_failed_load then
			-- Last startup we never made it to Done.
			local enabled_count = self:GetModsToLoad()
			if #enabled_count > 0 then
				-- We have mods, so attribute last failure to mods.
				self.badload = true
				TheLog.ch.Mods:print("ModIndex: Detected bad load, disabling all mods.")
				self:DisableAllMods()
				self:Save(cb) -- write disable to disk
			else
				-- No mods, so continue as usual.
				cb()
			end
		else
			-- Either never done BeginStartupSequence or it finished last time. We're good.
			TheLog.ch.Mods:print("ModIndex: Beginning normal load sequence.")
			local data = self.modsettings.disablemods and LoadState.s.InStartupSequence or LoadState.s.Done
			TheSim:SetPersistentString(filename, data, false, cb)
		end
	end)
end

function ModIndex:EndStartupSequence(cb)
	self.startingup = false
	local filename = self:_GetModIndexFileName("boot_canary")
	TheSim:SetPersistentString(filename, LoadState.s.Done, false, cb)
	TheLog.ch.Mods:print("ModIndex: Load sequence finished successfully.")
end

function ModIndex:WasLoadBad()
	return self.badload == true
end

function ModIndex:GetEnabledModNames()
	-- I think all ones set to load are enabled?
	return self:GetModsToLoad(true)
end

function ModIndex:GetModNames()
	local names = {}
	for name, _ in pairs(self.savedata.known_mods) do
		table.insert(names, name)
	end
	return names
end

function ModIndex:GetServerModNames()
	local names = {}
	for modname, _ in pairs(self.savedata.known_mods) do
		if not self:GetModInfo(modname).client_only_mod then
			table.insert(names, modname)
		end
	end
	return names
end

function ModIndex:GetClientModNamesTable()
	local names = {}
	for known_modname, _ in pairs(self.savedata.known_mods) do
		if self:GetModInfo(known_modname).client_only_mod then
			table.insert(names, { modname = known_modname })
		end
	end
	return names
end

function ModIndex:GetServerModNamesTable()
	local names = {}
	for known_modname, _ in pairs(self.savedata.known_mods) do
		if not self:GetModInfo(known_modname).client_only_mod then
			table.insert(names, { modname = known_modname })
		end
	end
	return names
end

function ModIndex:Save(cb)
	if Platform.IsConsole() then
		return
	end

	local newdata = { known_mods = {} }
	newdata.known_api_version = MOD_API_VERSION

	for name, data in pairs(self.savedata.known_mods) do
		newdata.known_mods[name] = {}
		newdata.known_mods[name].enabled = data.enabled
		newdata.known_mods[name].favorite = data.favorite
		newdata.known_mods[name].temp_enabled = data.temp_enabled
		newdata.known_mods[name].temp_disabled = data.temp_disabled
		newdata.known_mods[name].disabled_bad = data.disabled_bad
		newdata.known_mods[name].disabled_incompatible_with_mode = data.disabled_incompatible_with_mode
		newdata.known_mods[name].seen_api_version = MOD_API_VERSION
		newdata.known_mods[name].temp_config_options = data.temp_config_options
		-- Don't save raw modinfo from mods. We'll pull it out of them on load
		-- otherwise they can bloat our known_mods a ton.
	end

	--TheLog.ch.Mods:print("\n\n---SAVING MOD INDEX---\n\n")
	--dumptable(newdata)
	--TheLog.ch.Mods:print("\n\n---END SAVING MOD INDEX---\n\n")
	local fastmode = true
	local data = DataDumper(newdata, nil, fastmode)
	TheSim:SetPersistentString(self:_GetModIndexFileName("config"), data, ENCODE_SAVES, cb)
end

function ModIndex:GetModsToLoad(use_cached)
	local moddirs
	if use_cached then
		moddirs = lume.keys(self.savedata.known_mods)
	else
		moddirs = self:_GetModDirs()
	end

	local ret = {}
	for i, moddir in ipairs(moddirs) do
		if (self:IsModEnabled(moddir)
				or self:IsModForceEnabled(moddir)
				or self:IsModTempEnabled(moddir))
			and not self:IsModTempDisabled(moddir)
		then
			TheLog.ch.Mods:print("ModIndex:GetModsToLoad inserting moddir, ", moddir)
			table.insert(ret, moddir)
		end
	end

	for i, modname in ipairs(ret) do
		if self:IsModStandalone(modname) then
			TheLog.ch.Mods:print("\n\n" .. self:GetModLogName(modname) .. " Loading a standalone mod! No other mods will be loaded.\n")
			return { modname }
		end
	end
	return ret
end

function ModIndex:_GetModAutoEnableCandidates()
	local ret = {}
	for mod_id, mod in pairs(self.savedata.known_mods) do
		-- Don't bother with already enabled mods.
		if not self:IsModEnabled(mod_id)
			-- Reasons we shouldn't auto enable a mod:
			and not self:IsModKnownBad(mod_id)
		then
			TheLog.ch.Mods:print("_GetModAutoEnableCandidates inserting mod_id, ", mod_id)
			table.insert(ret, mod_id)
		end
	end

	for i, mod_id in ipairs(ret) do
		if self:IsModStandalone(mod_id) then
			TheLog.ch.Mods:print("\n\n" .. self:GetModLogName(mod_id) .. " Loading a standalone mod! No other mods will be loaded.\n")
			return { mod_id }
		end
	end
	return ret
	
end

function ModIndex:GetModInfo(modname)
	if self.savedata.known_mods[modname] then
		return self.savedata.known_mods[modname].modinfo or {}
	else
		modprint("unknown mod " .. tostring(modname))
		return nil
	end
end

-- Call this to refresh our list of mods. Loads their modinfo lua as data.
function ModIndex:UpdateModInfo()
	TheLog.ch.Mods:print("Updating all mod info.")

	local modnames = lume.invert(self:_GetModDirs())

	for modname, moddata in pairs(self.savedata.known_mods) do
		if not modnames[modname] then
			-- Mod was removed, forget about it.
			self.savedata.known_mods[modname] = nil
		end
	end

	for modname in iterator.sorted_pairs(modnames) do
		if not self.savedata.known_mods[modname] then
			self.savedata.known_mods[modname] = {}
		end
		self.savedata.known_mods[modname].modinfo = self:_LoadModInfo(modname)
	end
end

function ModIndex:UpdateSingleModInfo(modname)
	if not self.savedata.known_mods[modname] then
		self.savedata.known_mods[modname] = {}
	end
	self.savedata.known_mods[modname].modinfo = self:_LoadModInfo(modname)
end

local workshop_prefix = "workshop-"
--This function only works if the modindex has been updated
local function ResolveModname(modname)
	--try to convert from Workshop id to modname
	if KnownModIndex:DoesModExistAnyVersion(modname) then
		return modname
	else
		--modname wasn't found, try it as a workshop mod
		local workshop_modname = workshop_prefix .. modname
		if KnownModIndex:DoesModExistAnyVersion(workshop_modname) then
			return workshop_modname
		end
	end
	return nil
end

function ModIndex:IsWorkshopMod(modname)
	if modname == nil then
		return false
	end
	return modname:sub(1, workshop_prefix:len()) == workshop_prefix
end

function ModIndex:GetWorkshopIdNumber(modname)
	return string.sub(modname, workshop_prefix:len() + 1)
end

function ModIndex:ApplyEnabledOverrides(mod_overrides) --Note(Peter): This function is now coupled with the format written by SaveIndex:SetServerEnabledMods
	if mod_overrides == nil then
		TheLog.ch.Mods:print("Warning: modoverrides.lua is empty, or is failing to return a table.")
	else
		--Enable mods that are being forced on in the modoverrides.lua file
		--TheLog.ch.Mods:print("ModIndex:ApplyEnabledOverrides for mods" )
		for modname, env in pairs(mod_overrides) do
			if modname == "client_mods_disabled" then
				self:DisableClientMods(env) --env is a bool in this case
			else
				if env.enabled ~= nil then
					local actual_modname = ResolveModname(modname)
					if actual_modname ~= nil then
						if env.enabled then
							TheLog.ch.Mods:print("modoverrides.lua enabling " .. actual_modname)
							self:EnableMod(actual_modname)
						else
							self:DisableMod(actual_modname)
						end
					end
				end
			end
		end
	end
end

function ModIndex:ApplyConfigOptionOverrides(mod_overrides)
	--TheLog.ch.Mods:print("ModIndex:ApplyConfigOptionOverrides for mods" )
	for modname, env in pairs(mod_overrides) do
		if modname == "client_mods_disabled" then
			--Do nothing here for this entry
		else
			if env.configuration_options ~= nil then
				local actual_modname = ResolveModname(modname)
				if actual_modname ~= nil then
					TheLog.ch.Mods:print("applying configuration_options from modoverrides.lua to mod " .. actual_modname)

					local force_local_options = true
					local config_options = self:GetModConfigurationOptions_Internal(actual_modname, force_local_options)

					if config_options and type(config_options) == "table" then
						for option, override in pairs(env.configuration_options) do
							for _, config_option in pairs(config_options) do
								if config_option.name == option then
									TheLog.ch.Mods:print(
										"Overriding mod "
											.. actual_modname
											.. "'s option "
											.. option
											.. " with value "
											.. tostring(override)
									)
									config_option.saved = override
								end
							end
						end
					end
				end
			end
		end
	end
end

local function FindEnabledMod(self, v)
	if self:IsModEnabledAny(v.workshop) then
		return v.workshop
	end
	for modname, isfancy in ipairs(v) do
		if modname ~= "workshop" then
			modname = not isfancy and modname or self:GetModActualName(modname)
			if self:IsModEnabledAny(modname) then
				return modname
			end
		end
	end
end

local function BuildModPriorityList(self, v, is_workshop)
	local workshop = v.workshop
	local mods = {}
	for modname, isfancy in pairs(v) do
		if modname ~= "workshop" then
			modname = not isfancy and modname or self:GetModActualName(modname)
			if self:DoesModExistAnyVersion(modname) then
				table.insert(mods, modname)
			end
		end
	end
	if workshop then
		--prioritize workshop mods if the mod is_workshop, otherwise its the last resort
		table.insert(mods, is_workshop and 1 or #mods + 1, workshop)
	end
	return mods
end

-- Loads the modinfo for a mod which should only load very simple data that
-- specifies metadata about the mod. Doesn't activate the mod.
function ModIndex:_LoadModInfo(modname)
	local msg = string.format("Reading modinfo for mod '%s':", self:GetModLogName(modname))
	modprint(msg)

	TheLog.ch.Mods:print(msg)
	TheLog.ch.Mods:indent()
	local info = self:_ReadModInfoFile(modname)
	TheLog.ch.Mods:unindent()
	if info.failed then
		modprint("  But there was an error loading it.")
		self:DisableBecauseBad(modname)
		return
	else
		-- we've already "dealt" with this in the past; if the user
		-- chooses to enable it, then try loading it!
	end

	self.savedata.known_mods[modname].modinfo = info
	--~ TheLog.ch.Mods:dumptable(self.savedata.known_mods[modname].modinfo)

	info.mod_version = info.mod_version or ""
	info.mod_version = info.mod_version:lower():trim()
	info.version_compatible = type(info.version_compatible) == "string" and info.version_compatible:lower():trim() or info.mod_version

	info.mod_type = info.mod_type:lower():trim()
	info.mod_id = modname

	local print_atlas_warning = true
	if info.icon_atlas ~= nil and info.icon ~= nil and info.icon_atlas ~= "" and info.icon ~= "" then
		local atlaspath = MODS_ROOT .. modname .. "/" .. info.icon_atlas
		local iconpath = string.gsub(atlaspath, "/[^/]*$", "") .. "/" .. info.icon
		if softresolvefilepath(atlaspath) and softresolvefilepath(iconpath) then
			info.icon_atlas = atlaspath
			info.iconpath = iconpath
		else
			-- This prevents malformed icon paths from crashing the game.
			if print_atlas_warning then
				TheLog.ch.Mods:print(
					string.format(
						'WARNING: icon paths for mod %s are not valid. Got icon_atlas="%s" and icon="%s".\nPlease ensure that these point to valid files in your mod folder, or else comment out those lines from your modinfo.lua.',
						self:GetModLogName(modname),
						info.icon_atlas,
						info.icon
					)
				)
				print_atlas_warning = false
			end
			info.icon_atlas = nil
			info.iconpath = nil
			info.icon = nil
		end
	else
		info.icon_atlas = nil
		info.iconpath = nil
		info.icon = nil
	end

	if info.mod_dependencies and not info.client_only_mod then
		local dependencies = {}
		self.savedata.known_mods[modname].dependencies = dependencies
		for i, v in ipairs(info.mod_dependencies) do
			--if a mod is already enabled, use that version.
			local enabledmod = FindEnabledMod(self, v)
			if enabledmod then
				table.insert(dependencies, { enabledmod })
			else
				local mods = BuildModPriorityList(self, v, self:IsWorkshopMod(modname))
				if #mods == 0 then
					modprint("no valid dependent mod found for mod " .. modname)
					self:DisableBecauseBad(modname)
				end
				table.insert(dependencies, mods)
			end
		end
	end

	return info
end

local modinfo_path = "MODS:%s/modinfo.lua"

function ModIndex:_ReadModInfoFile(modname)
	local fn = kleiloadlua(modinfo_path:format(modname))
	local ret = {}
	if not fn or type(fn) == "string" then
		TheLog.ch.Mods:printf("Error loading mod: '%s'. Is there a modinfo.lua?%s\n", self:GetModLogName(modname), fn or "")
		return {
			failed = true,
			msg = "Failed to find modinfo.lua",
		}
	end
	-- Load modinfo as a data table. It shouldn't contain any logic because we
	-- just want metadata and aren't trying to load the mod yet.
	local status, env = RunInEnvironment_Safe(fn)

	if status == false or type(env) ~= "table" then
		TheLog.ch.Mods:printf("Error loading mod: '%s'. Does it have modinfo.lua that returns a table? %s Type seen: %s", self:GetModLogName(modname), env or "", type(env))
		return {
			failed = true,
			msg = "Failed to load modinfo.lua",
		}
	end

	env.api_version = env.api_version or -1

	if env.api_version < MOD_API_VERSION then
		env.warning = true
		env.msg = string.format("Old API! (mod: %s game: %s) ", env.api_version, MOD_API_VERSION)

	elseif env.api_version > MOD_API_VERSION then
		env.failed = true
		env.msg = string.format(
			"Error loading mod: '%s'.\napi_version for '%s' is in the future, please set to the current version. (mod api_version is version %s, game is version %s.)\n",
			self:GetModLogName(modname),
			modname,
			env.api_version,
			MOD_API_VERSION)

	elseif not ModType:Contains(env.mod_type) then
		env.failed = true
		env.msg = string.format(
			"Error loading mod: invalid mod_type '%s'. Supported types: %s",
			env.mod_type,
			table.concat(ModType:Ordered(), ", "))

	else
		local checkinfo = { "name", "description", "author", "mod_version", "mod_type", "api_version", }
		local missing = {}
		for i, v in ipairs(checkinfo) do
			if env[v] == nil then
				table.insert(missing, v)
			end
		end

		if #missing > 0 then
			env.failed = true
			env.msg = "Error loading modinfo.lua. These fields are required: " .. table.concat(missing, ", ")
		end
		-- else: everything loaded okay!
	end

	if env.client_only_mod and env.all_clients_require_mod then
		env.warning = true
		local msg = string.format("WARNING loading modinfo.lua: %s specifies client_only_mod and all_clients_require_mod. These flags are mutually exclusive.", modname)
		env.msg = env.msg or msg
	end

	if env.msg then
		TheLog.ch.Mods:print(env.msg)
	else
		TheLog.ch.Mods:print("Successfully loaded mod", modname)
	end

	return env
end

function ModIndex:GetModActualName(fancyname)
	for i, v in pairs(self.savedata.known_mods) do
		if v and v.modinfo and v.modinfo.name then
			if v.modinfo.name == fancyname then
				return i
			end
		end
	end
end

-- Pretty name specified by modder for display to users.
function ModIndex:GetModFancyName(modname)
	local knownmod = self.savedata.known_mods[modname]
	if knownmod and knownmod.modinfo and knownmod.modinfo.name then
		return knownmod.modinfo.name
	else
		return modname
	end
end

-- Show both identifier name and fancy name.
function ModIndex:GetModLogName(modname)
	local prettyname = KnownModIndex:GetModFancyName(modname)
	if prettyname == modname then
		return modname
	else
		return modname .. " (" .. prettyname .. ")"
	end
end

function ModIndex:Load(cb)
	self:UpdateModSettings()

	local filename = self:_GetModIndexFileName("config")
	TheSim:GetPersistentString(filename, function(load_success, str)
		if load_success == true then
			local success, savedata = RunInSandbox_Safe(str)
			if success and string.len(str) > 0 and savedata ~= nil then
				self.savedata = savedata
				TheLog.ch.Mods:print("loaded " .. filename)
				--TheLog.ch.Mods:print("\n\n---LOADING MOD INDEX---\n\n")
				--dumptable(self.savedata)
				--TheLog.ch.Mods:print("\n\n---END LOADING MOD INDEX---\n\n")

				--TheLog.ch.Mods:print("\n\n---LOADING MOD INFOS---\n\n")
				self:UpdateModInfo()
				--dumptable(self.savedata)
				--TheLog.ch.Mods:print("\n\n---END LOADING MOD INFOS---\n\n")
			else
				TheLog.ch.Mods:print("Could not load " .. filename)
				if string.len(str) > 0 then
					TheLog.ch.Mods:print("File str is [" .. str .. "]")
				end
			end
		else
			TheLog.ch.Mods:print("Could not load " .. filename)
		end

		cb()
	end)
end

function ModIndex:IsModCompatibleWithMode(modname, dlcmode)
	local dlcmode = "rotwood"
	local known_mod = self.savedata.known_mods[modname]
	if known_mod and known_mod.modinfo then
		return known_mod.modinfo.supports_mode[dlcmode]
	end
	return false
end

function ModIndex:GetModConfigurationOptions(modname)
	local modinfo = self:GetModInfo(modname)
	return modinfo
		and modinfo.configuration_options
end

function ModIndex:HasModConfigurationOptions(modname)
	local modcfg = self:GetModConfigurationOptions(modname)
	return modcfg
		and type(modcfg) == "table"
		and #modcfg > 0
end

function ModIndex:SetConfigurationOption(modname, option_name, value)
	local modcfg = self:GetModConfigurationOptions(modname)
	if modcfg then
		modcfg[option_name] = value
	end
end

-- Loads the actual file from disk
function ModIndex:LoadModConfigurationOptions(modname, client_config)
	local known_mod = self.savedata.known_mods[modname]
	if known_mod == nil then
		TheLog.ch.Mods:print("Error: mod isn't known", modname)
		return nil
	end

	-- Try to find saved config settings first
	local filename = self:GetModConfigurationPath(modname, client_config)
	TheSim:GetPersistentString(filename, function(load_success, str)
		if load_success and string.len(str) > 0 then
			local success, savedata = RunInSandbox_Safe(str)
			if success then
				if known_mod.modinfo then
					known_mod.modinfo.configuration_options = savedata
				else
					TheLog.ch.Mods:print("Error: modinfo was not available for mod ", modname) --something went wrong, likely due to workshop update during FE loading, load modinfo now to try to recover
					self:UpdateSingleModInfo(modname)
					known_mod.modinfo.configuration_options = savedata
				end
				TheLog.ch.Mods:print("loaded " .. filename)
			else
				TheLog.ch.Mods:print("Could not load " .. filename)
			end
		else
			TheLog.ch.Mods:print("Could not load " .. filename)
		end
	end)

	if known_mod and known_mod.modinfo and known_mod.modinfo.configuration_options then
		return known_mod.modinfo.configuration_options
	end
	return nil
end

function ModIndex:SaveConfigurationOptions(cb, modname, configdata, client_config)
	if Platform.IsConsole() or not configdata then
		return
	end
	-- Save it to disk
	local name = self:GetModConfigurationPath(modname, client_config)
	local data = DataDumper(configdata, nil, false)

	local function on_done()
		cb()
		-- And reload it to make sure there's parity after it's been saved
		self:LoadModConfigurationOptions(modname, client_config)
	end

	TheSim:SetPersistentString(name, data, ENCODE_SAVES, on_done)
end

function ModIndex:IsModEnabled(modname)
	local known_mod = self.savedata.known_mods[modname]
	return known_mod and known_mod.enabled
end

function ModIndex:IsModTempEnabled(modname)
	local known_mod = self.savedata.known_mods[modname]
	return known_mod and known_mod.temp_enabled
end

function ModIndex:IsModTempDisabled(modname)
	local known_mod = self.savedata.known_mods[modname]
	return known_mod and known_mod.temp_disabled
end

function ModIndex:IsModForceEnabled(modname)
	if self.modsettings.forceenable[modname] then
		return self.modsettings.forceenable[modname]
	else
		--try to fall back and find the mod without the workshop prefix (sometimes users force enable a mod by just the workshop id)
		if modname:startswith(workshop_prefix) then
			local alt_name = string.sub(modname, string.len(workshop_prefix) + 1)
			return self.modsettings.forceenable[alt_name]
		end
	end
	return false
end

function ModIndex:IsModEnabledAny(modname)
	return modname
		and ((self:IsModEnabled(modname)
				or self:IsModForceEnabled(modname)
				or self:IsModTempEnabled(modname))
				and not self:IsModTempDisabled(modname))
end

-- Standalone means no other mods can load when this one is loaded.
function ModIndex:IsModStandalone(modname)
	local known_mod = self.savedata.known_mods[modname]
	return known_mod and known_mod.modinfo and known_mod.modinfo.standalone == true
end

function ModIndex:IsModInitPrintEnabled()
	return false -- prevent odd crash in modutil initprint
end

function ModIndex:IsModErrorEnabled()
	return self.modsettings.moderror
end

function ModIndex:IsLocalModWarningEnabled()
	return self.modsettings.localmodwarning
end

function ModIndex:DisableMod(modname)
	if not self.savedata.known_mods[modname] then
		self.savedata.known_mods[modname] = {}
	end
	self.savedata.known_mods[modname].enabled = false
end

function ModIndex:DisableAllMods()
	for k, v in pairs(self.savedata.known_mods) do
		self:DisableMod(k)
	end
end

function ModIndex:DisableAllModsBecauseBad()
	for k, v in pairs(self.savedata.known_mods) do
		self:DisableBecauseBad(k)
	end
end

function ModIndex:ClearTempModFlags(modname)
	if not self.savedata.known_mods[modname] then
		self.savedata.known_mods[modname] = {}
	end
	self.savedata.known_mods[modname].temp_enabled = false
	self.savedata.known_mods[modname].temp_disabled = false
	self.savedata.known_mods[modname].temp_config_options = nil
end

function ModIndex:ClearAllTempModFlags()
	--TheLog.ch.Mods:print( "ModIndex:ClearAllTempModFlags" )

	local function internal_clear_all_temp_mod_flags()
		for k, v in pairs(self.savedata.known_mods) do
			self:ClearTempModFlags(k)
		end
		self:Save(nil)
	end
	if self.savedata == nil then
		self:Load(internal_clear_all_temp_mod_flags)
	else
		internal_clear_all_temp_mod_flags()
	end
end

function ModIndex:SetTempModConfigData(temp_mods_config_data)
	TheLog.ch.Mods:print("ModIndex:SetTempModConfigData")
	for modname, config_data in pairs(temp_mods_config_data) do
		if self.savedata.known_mods[modname] ~= nil then
			TheLog.ch.Mods:print("Setting temp mod config for mod ", modname)
			self.savedata.known_mods[modname].temp_config_options = config_data
		else
			assert(false, "Temp mod is missing from known mods")
		end
	end
end

function ModIndex:DisableBecauseBad(modname)
	if not self.savedata.known_mods[modname] then
		self.savedata.known_mods[modname] = {}
	end
	self.savedata.known_mods[modname].disabled_bad = true
	self.savedata.known_mods[modname].enabled = false
end

function ModIndex:DisableBecauseIncompatibleWithMode(modname)
	if not self.savedata.known_mods[modname] then
		self.savedata.known_mods[modname] = {}
	end
	self.savedata.known_mods[modname].disabled_incompatible_with_mode = true
	self.savedata.known_mods[modname].enabled = false
end

function ModIndex:EnableMod(modname)
	if not self.savedata.known_mods[modname] then
		self.savedata.known_mods[modname] = {}
	end

	self.savedata.known_mods[modname].enabled = true
	self.savedata.known_mods[modname].disabled_bad = false
	self.savedata.known_mods[modname].disabled_incompatible_with_mode = false
end

function ModIndex:TempEnable(modname)
	if not self.savedata.known_mods[modname] then
		self.savedata.known_mods[modname] = {}
	end
	self.savedata.known_mods[modname].temp_enabled = true
	self.savedata.known_mods[modname].disabled_bad = false
	self.savedata.known_mods[modname].disabled_incompatible_with_mode = false
end

function ModIndex:TempDisable(modname)
	if not self.savedata.known_mods[modname] then
		self.savedata.known_mods[modname] = {}
	end
	self.savedata.known_mods[modname].temp_disabled = true
end

function ModIndex:IsModNewlyBad(modname)
	local known_mod = self.savedata.known_mods[modname]
	if known_mod and known_mod.modinfo.failed then
		-- After a mod is disabled it can no longer fail;
		-- in addition, the index is saved when a mod fails.
		-- So we just have to check if the mod failed in the index
		-- and that indicates what happened last time.
		return true
	end
	return false
end

function ModIndex:KnownAPIVersion(modname)
	local known_mod = self.savedata.known_mods[modname]
	if not known_mod or not known_mod.modinfo then
		return -2 -- If we've never seen the mod before, we assume it's REALLY old
	elseif not known_mod.modinfo.api_version then
		return -1 -- If we've seen it but it has no info, it's just "Old"
	else
		return known_mod.modinfo.api_version
	end
end

function ModIndex:IsModNew(modname)
	local known_mod = self.savedata.known_mods[modname]
	return not known_mod or not known_mod.modinfo
end

function ModIndex:IsModKnownBad(modname)
	local known_mod = self.savedata.known_mods[modname]
	return known_mod and known_mod.disabled_bad
end

-- When the user changes settings it messes directly with the index data, so make a backup
function ModIndex:CacheSaveData()
	self.cached_data = {}
	self.cached_data.savedata = deepcopy(self.savedata)
	self.cached_data.modsettings = deepcopy(self.modsettings)
	return self.cached_data
end

-- If the user cancels their mod changes, restore the index to how it was prior the changes.
function ModIndex:RestoreCachedSaveData(ext_data)
	local data = ext_data or self.cached_data
	self.savedata = data.savedata
	self.modsettings = data.modsettings
end

local function IsModAlreadyDepended(deps, new_deps)
	for i, mod in ipairs(new_deps) do
		if deps[mod] then
			return true
		end
	end
	return false
end

function ModIndex:GetModDependencies(modname, recursive, rec_deps)
	if not rec_deps then
		self:UpdateModInfo()
	end
	local known_mod = self.savedata.known_mods[modname]
	local dependencies = known_mod and known_mod.dependencies
	if not dependencies then
		return {}
	end
	local deps = rec_deps or {}
	local new_deps = {}
	--add our modname to the deps to prevent circular dependency loops
	deps[modname] = true
	for i, mods_dep in ipairs(dependencies) do
		if not IsModAlreadyDepended(deps, mods_dep) then
			deps[mods_dep[1]] = true
			new_deps[mods_dep[1]] = true
		end
	end
	if recursive then
		for _modname, _ in pairs(new_deps) do
			self:GetModDependencies(_modname, recursive, deps)
		end
	end
	--rec_deps will be nil when called externally
	if not rec_deps then
		deps[modname] = nil
		return table.getkeys(deps)
	end
end

function ModIndex:GetModDependents(modname, recursive, rec_deps)
	local deps = rec_deps or {}
	local new_deps = {}
	--add our modname to the deps to prevent circular dependency loops
	deps[modname] = true
	for _modname, modslist in pairs(self.mod_dependencies.dependency_list) do
		if not deps[_modname] then
			for _, _modnamedep in ipairs(modslist) do
				if modname == _modnamedep then
					deps[_modname] = true
					new_deps[_modname] = true
				end
			end
		end
	end
	if recursive then
		for _modname, _ in pairs(new_deps) do
			self:GetModDependents(_modname, recursive, deps)
		end
	end

	--rec_deps will be nil when called externally
	if not rec_deps then
		deps[modname] = nil
		return table.getkeys(deps)
	end
end

function ModIndex:IsModDependedOn(modname)
	return (self.mod_dependencies.server_dependency_list[modname] or 0) > 0
end

function ModIndex:SetDependencyList(modname, modslist, nosubscribe)
	self.mod_dependencies.dependency_list[modname] = modslist
	for i, mod in ipairs(modslist) do
		self:AddModDependency(mod, nosubscribe)
	end
end

function ModIndex:AddModDependency(modname, nosubscribe)
	if self:IsWorkshopMod(modname) and not self:DoesModExistAnyVersion(modname) then
		if nosubscribe then
			return
		end
		TheSim:SubscribeToMod(modname)
	end
	self.mod_dependencies.server_dependency_list[modname] = (self.mod_dependencies.server_dependency_list[modname] or 0) + 1
end

function ModIndex:ClearModDependencies(modname)
	if modname == nil then
		self.mod_dependencies.server_dependency_list = {}
		self.mod_dependencies.dependency_list = {}
	else
		for i, v in ipairs(self.mod_dependencies.dependency_list[modname] or {}) do
			self.mod_dependencies.server_dependency_list[v] = (self.mod_dependencies.server_dependency_list[v] or 0) - 1
		end
		self.mod_dependencies.dependency_list[modname] = nil
	end
end

function ModIndex:GetModDependenciesEnabled()
	for k, v in pairs(self.mod_dependencies.server_dependency_list) do
		if (v or 0) > 0 and not self:IsModEnabled(k) then
			return false
		end
	end
	return true
end

-- TODO(mods): What does any version mean?
function ModIndex:DoesModExistAnyVersion(modname)
	local modinfo = self:GetModInfo(modname)
	return modinfo ~= nil
end

function ModIndex:DoModsExistAnyVersion(modlist)
	for i, v in ipairs(modlist) do
		if not self:DoesModExistAnyVersion(v) then
			return false
		end
	end
	return true
end

function ModIndex:DoesModExist(modname, server_version, server_version_compatible)
	if server_version_compatible == nil then
		--no compatible flag, so we want to do an exact version check
		local modinfo = self:GetModInfo(modname)
		if modinfo ~= nil then
			return server_version == modinfo.mod_version
		end
		TheLog.ch.Mods:print("Mod " .. modname .. " v:" .. server_version .. " doesn't exist in mod dir ")
		return false
	else
		local modinfo = self:GetModInfo(modname)
		if modinfo ~= nil then
			if server_version >= modinfo.mod_version then
				--server is ahead or equal version, check if client is compatible with server
				return modinfo.mod_version >= server_version_compatible
			else
				--client is ahead, check if server is compatible with client
				return server_version >= modinfo.version_compatible
			end
		end
		TheLog.ch.Mods:print(
			"Mod "
				.. modname
				.. " v:"
				.. server_version
				.. " vc:"
				.. server_version_compatible
				.. " doesn't exist in mod dir "
		)
		return false
	end
end

function ModIndex:GetEnabledModTags()
	local tags = {}
	for name, data in pairs(self.savedata.known_mods) do
		if data.enabled then
			local modinfo = self:GetModInfo(name)
			if modinfo ~= nil and modinfo.server_filter_tags ~= nil then
				for i, tag in pairs(modinfo.server_filter_tags) do
					table.insert(tags, tag)
				end
			end
		end
	end
	return tags
end

-- To be called from the server/host when loading mod overrides. Note, this is
-- not saved out to the mod index file on the clients, it's applied through the
-- server listing temp disabling individual client mods when connecting
function ModIndex:DisableClientMods(disabled)
	self.client_mods_disabled = disabled
end

function ModIndex:AreClientModsDisabled()
	return self.client_mods_disabled
end



-- Activate all enabled mods of mod_type using loader_fn to load and apply them
-- from their loaded modinfo.
--
-- This is the only mod activation function in ModIndex. We keep everything
-- else out because running mod code is the more dangerous code that needs more
-- care (since running lua code could introduce gameplay exploits).
--
-- @param mod_type ModType The kind of mod.
-- @param loader_fn function A function that can safely run the mod code and
--		  add it to some list of active mods.
function ModIndex:ActivateModsOfType(mod_type, loader_fn)
	for modname, mod in pairs(self.savedata.known_mods) do
		local modinfo = mod.modinfo or table.empty
		TheLog.ch.Mods:print("ActivateModsOfType", modinfo.mod_id, modinfo.mod_type, mod.enabled)
		if modinfo.mod_type == mod_type then
			if mod.enabled then
				TheLog.ch.Mods:print("Attempting to activate mod", modinfo.mod_id)
				TheLog.ch.Mods:indent() do
					-- Only pass modinfo because rest of mod table is just for status tracking.
					local call_success, mod_success = pcall(loader_fn, modinfo)
					if call_success and mod_success then
						TheLog.ch.Mods:printf("activating '%s' succeeded.", modinfo.mod_id)
					else
						TheLog.ch.Mods:printf("activating '%s' failed: %s", modinfo.mod_id, mod_success)
						self:DisableBecauseBad(modname)
					end
				end
				TheLog.ch.Mods:unindent()
			end
		end
	end
end

function ModIndex:UpdateModSettings()

    self.modsettings = {
        forceenable = {},
        disablemods = true,
        localmodwarning = true
    }

    local function ForceEnableMod(modname)
        print("WARNING: Force-enabling mod '"..modname.."' from modsettings.lua! If you are not developing a mod, please use the in-game menu instead.")
        self.modsettings.forceenable[modname] = true
    end
    local function EnableModDebugPrint()
        self.modsettings.initdebugprint = true
    end
    local function EnableModError()
        self.modsettings.moderror = true
    end
    local function DisableModDisabling()
        self.modsettings.disablemods = false
    end
    local function DisableLocalModWarning()
        self.modsettings.localmodwarning = false
    end

    local env = {
        ForceEnableMod = ForceEnableMod,
        EnableModDebugPrint = EnableModDebugPrint,
        EnableModError = EnableModError,
        DisableModDisabling = DisableModDisabling,
        DisableLocalModWarning = DisableLocalModWarning,
        print = print,
    }

    local filename = MODS_ROOT.."modsettings.lua"
    local fn = kleiloadlua( filename )
    if fn == nil then
        print("could not load modsettings: "..filename)
        print("Warning: You may want to try reinstalling the game if you need access to forcing mods on.")
    else
        if type(fn)=="string" then
            error("Error loading modsettings:\n"..fn)
        end
        setfenv(fn, env)
        fn()
    end
end

ModIndex.ModType = ModType
return ModIndex
