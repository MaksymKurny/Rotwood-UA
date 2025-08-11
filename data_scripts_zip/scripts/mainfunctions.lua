local ConfirmDialog = require "screens.dialogs.confirmdialog"
local Stats = require "stats"
local URLS = require "urls"
local DebugNodes = require "dbui.debug_nodes"
local monsterutil = require "util.monsterutil"
local ExitCode = require "exit_code"
local AssetLoader = require "assetloader"
require "knownerrors"
require "scheduler"
--require "skinsutils"


SimTearingDown = false
SimShuttingDown = false
PerformingRestart = false

function SecondsToTimeString(total_seconds)
	local minutes = math.floor(total_seconds / 60)
	local seconds = math.floor(total_seconds - minutes * 60)

	if minutes > 0 then
		return string.format("%d:%02d", minutes, seconds)
	elseif seconds > 9 then
		return string.format("%02d", seconds)
	else
		return string.format("%d", seconds)
	end
end

---PREFABS AND ENTITY INSTANTIATION

function ShouldIgnoreResolve(filename, assettype)
	if assettype == "INV_IMAGE" then
		return true
	end
	if assettype == "MINIMAP_IMAGE" then
		return true
	end
	if assettype == "PKGREF" then
		-- Not sure there are any package references we care about, but for now
		-- just ignore knowns.
		if filename:find(".dyn")
			or filename:find(".lua")
		then
			return true
		end
	end

	return false
end


local modprefabinitfns = {}

function RegisterPrefabsImpl(prefab, resolve_fn)
	--print ("Register " .. tostring(prefab))
	-- allow mod-relative asset paths

	RegisterEmbellishmentDependencies(prefab)

	for i, asset in ipairs(prefab.assets) do
		if not ShouldIgnoreResolve(asset.file, asset.type) then
			resolve_fn(prefab, asset)
		end
	end

	modprefabinitfns[prefab.name] = ModManager:GetPostInitFns("PrefabPostInit", prefab.name)
	Prefabs[prefab.name] = prefab

	TheSim:RegisterPrefab(prefab.name, prefab.assets, prefab.deps)
end

function RegisterPrefabsResolveAssets(prefab, asset)
	--print(" - - RegisterPrefabsResolveAssets: " .. asset.file, debugstack())
	local resolvedpath = resolvefilepath(asset.file, prefab.force_path_search)
	assert(resolvedpath, "Could not find " .. asset.file .. " required by " .. prefab.name)
	--TheSim:OnAssetPathResolve(asset.file, resolvedpath)
	asset.file = resolvedpath
end

local function VerifyPrefabAssetExistsAsync(prefab, asset)
	-- this is being done to prime the HDD's file cache and ensure all the assets exist before going into game
	TheSim:AddBatchVerifyFileExists(asset.file)
end

function RegisterPrefabs(...)
	for i, prefab in ipairs({ ... }) do
		RegisterPrefabsImpl(prefab, RegisterPrefabsResolveAssets)
	end
end

PREFABDEFINITIONS = {}

function LoadPrefabFile(filename, async_batch_validation)
	--print("Loading prefab file "..filename)
	local fn, r = loadfile(filename)
	assert(fn, "Could not load file " .. filename)
	if type(fn) == "string" then
		local error_msg = "Error loading file " .. filename .. "\n" .. fn
		if DEV_MODE then
			-- Common error in development when working in a branch (we don't
			-- submit updateprefab changes in branches).
			print(error_msg)
			known_assert(false, "DEV_FAILED_TO_LOAD_PREFAB", filename)
		end
		error(error_msg)
	end
	assert(type(fn) == "function", "Prefab file doesn't return a callable chunk: " .. filename)
	local ret = { fn() }
	for i = 1, #ret do
		local v = ret[i]
		if Prefab.is_instance(v) then
			if async_batch_validation then
				RegisterPrefabsImpl(v, VerifyPrefabAssetExistsAsync)
			else
				RegisterPrefabs(v)
			end
			PREFABDEFINITIONS[v.name] = v
		end
	end
	return ret
end


-- forcelocal allows you to override the network_type of a prefab to NetworkType_None, which makes the prefab completely local.
function SpawnPrefabFromSim(name, instantiatedByHost, forcelocal)	
	local prefab = Prefabs[name]

	if prefab == nil then
		local error_msg = "Failed to spawn. Can't find prefab: " .. name
		if DEV_MODE then
			-- Common error in development when you forget to hook up a dependency.
			print(error_msg)
			known_assert(false, "DEV_FAILED_TO_SPAWN_PREFAB", name)
		end
		error(error_msg)
	end

	local canBeSpawned = forcelocal or instantiatedByHost or prefab:CanBeSpawned()
	if not canBeSpawned then
		-- If it can't be spawned, it is ALWAYS on a client. The host can spawn all network types.
		TheLog.ch.Networking:printf("Warning: Prefab '%s' with %s cannot be spawned by a client",
			name, prefab:GetNetworkTypeString())
		return
	end

	local inst = prefab.fn(name)
	if inst == nil then
		print("Failed to spawn " .. name)
		return
	end


	if not forcelocal and prefab.network_type ~= NetworkType_None and not inst.Network then
--		print("Adding network to "..name.." because it has network type ".. prefab.network_type)
		inst.entity:AddNetwork()

		if prefab.network_type == NetworkType_Minimal then
			inst.Network:SetTypeHostAuth() -- Spawn and control entirely on the host
			inst.Network:SetMinimalNetworking()	-- Only sync the bare minimum
		elseif prefab.network_type == NetworkType_HostAuth then
			inst.Network:SetTypeHostAuth() -- Spawn and control entirely on the host
		elseif prefab.network_type == NetworkType_SharedHostSpawn then
			inst.Network:SetTypeSharedHostSpawn() -- Spawn on the host, and auth is transferable to clients
		elseif prefab.network_type == NetworkType_SharedAnySpawn then
			inst.Network:SetTypeSharedAnySpawn() -- Spawnable on any client, and transferable
		elseif prefab.network_type == NetworkType_ClientAuth then
			inst.Network:SetTypeClientAuth() -- Spawn and control entirely on the client
		elseif prefab.network_type == NetworkType_ClientMinimal then
			inst.Network:SetTypeClientAuth() -- Spawn and control entirely on the client
			inst.Network:SetMinimalNetworking()
		end

		if inst.serializeHistory then
			inst.Network:SetSerializeHistory(true)	-- Tell it to precisely sync animations
		end
	end
	inst.serializeHistory = nil -- remove the temp variable


	if inst.alreadyInitialized then
		print("WARNING: The entity "..name.." was already intialized.")
	else
		inst.alreadyInitialized = true

		local def = STATEGRAPH_EMBELLISHMENTS_FINAL[name]
		if def and not inst.prefab then
			-- You might hit this on a correctly-setup prefab if it's not yet loaded.
			assert(false, "Prefab (" .. name .. ") has an embellishment but doesn't have it's prefabname initialized. Embellishable things must SetPrefabName.")
		end

		if inst.prefab == nil then
			inst:SetPrefabName(name)
		end

		inst:Embellish()

		local modfns = modprefabinitfns[inst.prefab or name]
		if modfns ~= nil then
			for k,mod in pairs(modfns) do
				mod(inst)
			end
		end
		if inst.prefab ~= name then
			modfns = modprefabinitfns[name]
			if modfns ~= nil then
				for k,mod in pairs(modfns) do
					mod(inst)
				end
			end
		end

		for k,prefabpostinitany in pairs(ModManager:GetPostInitFns("PrefabPostInitAny")) do
			prefabpostinitany(inst)
		end
		TheGlobalInstance:PushEvent("entity_spawned", inst)
	end

	inst:PostSpawn()
	return inst.entity
end

function PrefabExists(name)
	return Prefabs[name] ~= nil
end

-- name: prefab name. See allprefabs.
-- instigator: Player entity that caused spawn. If none relevant, enemy that
--   caused spawn. If none relevant, TheWorld or nil.
-- player_id: Used when spawning a player?
function SpawnPrefab(name, instigator, player_id, forceLocal)
	local skin = nil
	local skin_id = -1
	local guid = TheSim:SpawnPrefab(name, skin, skin_id, player_id, forceLocal)
	if guid then
		local inst = Ents[guid]
		if inst ~= nil then
			if populating_world_ents ~= nil then
				populating_world_ents[#populating_world_ents + 1] = { inst = inst }
			end
			inst:_SetSpawnInstigator(instigator)
			return inst
		end
	end
end

function SpawnSaveRecord(name, record, player_id)
	local skin = nil
	local skin_id = -1
	local forceLocal = false
	local guid = TheSim:SpawnPrefab(name, skin, skin_id, player_id, forceLocal)
	local inst = Ents[guid]
	if inst ~= nil then
		if inst.Transform ~= nil then
			inst.Transform:SetPosition(record.x or 0, record.y or 0, record.z or 0)
			if record.rot ~= nil then
				inst.Transform:SetRotation(record.rot)
			end
		end
		if populating_world_ents ~= nil then
			populating_world_ents[#populating_world_ents + 1] = { inst = inst, data = record.data }
		end
		inst:SetPersistData(record.data)
		-- Don't call PostLoadWorld here! This might get hit before the world
		-- is done loading. If you're loading save records outside of the world
		-- load flow, use SpawnSaveRecord_InExistingWorld.
		if inst:IsValid() then
			return inst
		end
	end
	print(string.format("SpawnSaveRecord [%s] FAILED", name))
end

function SpawnSaveRecord_InExistingWorld(name, record, player_id)
	local inst = SpawnSaveRecord(name, record, player_id)
	inst:PostLoadWorld(record.data)
	return inst
end

function CreateEntity(name)
	local ent = TheSim:CreateEntity()
	local guid = ent:GetGUID()
	local scr = EntityScript(ent)
	if name ~= nil then
		scr.name = name
	end
	Ents[guid] = scr
	return scr
end

local debug_entity = nil
local debug_table = nil

function RemoveEntity(guid)
	local inst = Ents[guid]
	if inst ~= nil then
		inst:Remove(true) -- force remove when instructed by native code
	end
end

function PushEntityEvent(guid, event, data)
	-- If your stacktrace stopped here, search C++ code for PushLuaEvent to
	-- find what's broadcasting the event.
	local inst = Ents[guid]
	if inst ~= nil then
		inst:PushEvent(event, data)
	end
end

function GetEntityDisplayName(guid)
	local inst = Ents[guid]
	return inst ~= nil and inst:GetDisplayName() or ""
end

------TIME FUNCTIONS

local ticktime = TheSim:GetTickTime()

-- Duration of a tick in seconds. Should be the same value as TICKS.
function GetTickTime()
	return ticktime
end

-- How long sim has run in seconds.
function GetTime()
	return TheSim:GetTick() * ticktime
end

-- How long sim has run in ticks.
function GetTick()
	return TheSim:GetTick()
end

-- Probably don't want this for gameplay code.
function GetTimeReal()
	return TheSim:GetRealTime()
end

function GetTimeRealSeconds()
	return TheSim:GetRealTime() / 1000
end

-- How long has it been since the window gained focus?
-- Useful to avoid "clicked on window" inputs.
local last_focus_gain_tick = 0
function GetTicksSinceFocusGain()
	return GetTick() - last_focus_gain_tick
end


---SCRIPTING
local Scripts = {}

function LoadScript(filename)
	if not Scripts[filename] then
		local scriptfn = loadfile("scripts/" .. filename)
		assert(type(scriptfn) == "function", scriptfn)
		Scripts[filename] = scriptfn()
	end
	return Scripts[filename]
end

function RunScript(filename)
	local fn = LoadScript(filename)
	if fn then
		fn()
	end
end

function GetEntityString(guid)
	local ent = Ents[guid]

	if ent then
		return ent:GetDebugString()
	end

	return ""
end

function GetExtendedDebugString()
	if debug_entity and debug_entity.brain then
		return debug_entity:GetBrainString()
	elseif SOUNDDEBUG_ENABLED then
		return GetSoundDebugString(), 24
	end
	return ""
end

function GetDebugString()
	local str = {}
	table.insert(str, tostring(Scheduler))

	if debug_entity then
		table.insert(str, "\n-------DEBUG-ENTITY-----------------------\n")
		table.insert(str, debug_entity.GetDebugString and debug_entity:GetDebugString() or "<no debug string>")
	end

	return table.concat(str)
end

function GetDebugEntity()
	return debug_entity
end

function SetDebugEntity(inst)
	if debug_entity ~= nil and debug_entity:IsValid() then
		debug_entity.entity:SetSelected(false)
	end
	if inst ~= nil and inst:IsValid() then
		debug_entity = inst
		inst.entity:SetSelected(true)
	else
		debug_entity = nil
	end
end

function GetDebugTable()
	return debug_table
end

function SetDebugTable(tbl)
	debug_table = tbl
end

function OnEntitySleep(guid)
	local inst = Ents[guid]
	if inst ~= nil then
		if inst.OnEntitySleep ~= nil then
			inst:OnEntitySleep()
		end
		if inst.brain ~= nil then
			inst.brain:Pause("entitysleep")
		end
		if inst.sg ~= nil then
			inst.sg:Pause("entitysleep")
		end
		for k, v in pairs(inst.components) do
			if v.OnEntitySleep ~= nil then
				v:OnEntitySleep()
			end
		end
	end
end

function OnEntityWake(guid)
	local inst = Ents[guid]
	if inst ~= nil then
		if inst.OnEntityWake ~= nil then
			inst:OnEntityWake()
		end
		if inst.brain ~= nil then
			inst.brain:Resume("entitysleep")
		end
		if inst.sg ~= nil then
			inst.sg:Resume("entitysleep")
		end
		for k, v in pairs(inst.components) do
			if v.OnEntityWake ~= nil then
				v:OnEntityWake()
			end
		end
	end
end

function HandlePermanentFlagChange(inst, permanentFlags)
	if not SupportPFlags then
		return
	end

	if inst:IsLocal()
		and (permanentFlags & PFLAG_JOURNALED_REMOVAL) == PFLAG_JOURNALED_REMOVAL
		and not IsLocalGame
		and not ((inst:GetIgnorePermanentFlagChanges() & PFLAG_JOURNALED_REMOVAL) == PFLAG_JOURNALED_REMOVAL) then
		TheLog.ch.Networking:printf("Entity GUID %d EntityID %d (%s) flagged for journaled removal. Removing...",
			inst.GUID, inst.Network:GetEntityID(), inst.prefab)
		inst:Remove()
		return true
	end

	if (permanentFlags & PFLAG_CHARMED) == PFLAG_CHARMED then
		monsterutil.CharmMonster(inst)
		-- Do NOT return true here. The return value of this function is seemingly only used inside OnEntityBecameLocal, and assumes returning true means the entity was removed.
	end
end

function OnEntityBecameLocal(guid, permanentFlags)
	local inst = Ents[guid]
	if inst ~= nil then
		-- For minimal entities, we want to ignore all of this. We want to keep them running 'as if they are local'
		if not inst:IsMinimal() then
			if HandlePermanentFlagChange(inst, permanentFlags) then
				return
			end

			inst:ResolveInLimboTag()

			if inst.OnEntityBecameLocal ~= nil then
				inst:OnEntityBecameLocal()
			end
			if inst.brain ~= nil then
				inst.brain:Resume("remote")
			end
			if inst.sg ~= nil then
				inst.sg:Resume("remote")
			end
			-- Resume it if paused by something like HitStopManager on the previous client when control was taken
			-- May need to sync HitStopManager instead
			if inst.Physics then
				inst.Physics:Resume()
			end

			for k, v in pairs(inst.components) do
				if v.OnEntityBecameLocal ~= nil then
					v:OnEntityBecameLocal()
				end
			end
		end
	end
end

function OnEntityBecameRemote(guid, permanentFlags)
	local inst = Ents[guid]
	if inst ~= nil then
		-- For minimal entities, we want to ignore all of this. We want to keep them running 'as if they are local'
		if not inst:IsMinimal() then
			HandlePermanentFlagChange(inst, permanentFlags);

			inst:ResolveInLimboTag()

			if inst.OnEntityBecameRemote ~= nil then
				inst:OnEntityBecameRemote()
			end
			if inst:IsInDelayedRemove() then
				inst:CancelDelayedRemove()
			end
			if inst.brain ~= nil then
				inst.brain:Pause("remote")
			end
			if inst.sg ~= nil then
				inst.sg:Pause("remote")
			end
			if inst.Physics and inst.Physics:HasMotorVel() and (not inst:HasTag("projectile") or inst.components.complexprojectile) then
				-- prevent entities from resuming previous vel if ownership changes back to this client
				-- do not reset for "simple" projectiles because those are only set once on spawn
				inst.Physics:SetMotorVel(0)
			end
			for k, v in pairs(inst.components) do
				if v.OnEntityBecameRemote ~= nil then
					v:OnEntityBecameRemote()
				end
			end
		end
	end
end


function OnEntityPermanentFlagsChanged(guid, newflags, oldflags)
	local inst = Ents[guid]
	if inst ~= nil then
		local changedflags = newflags ~ oldflags
		HandlePermanentFlagChange(inst, changedflags)
	end
end


------------------------------

local paused = false
local is_gameplay_paused = false
local pause_reason = "initial state"

-- Did player open the pause screen.
function IsPaused()
	return paused, pause_reason
end

-- Did player halt the sim to pause. See TheSim:IsDebugPaused() for debug pause.
function IsGameplayPaused()
	return is_gameplay_paused, pause_reason
end

---------------------------------------------------------------------
--V2C: DST sim pauses via network checks, and will notify LUA here
function OnSimPaused()
	--Probably shouldn't do anything here, since sim is now paused
	--and most likely anything triggered here won't actually work.
end

function OnSimUnpaused()
	if TheWorld ~= nil then
		TheWorld:PushEvent("ms_simunpaused")
	end
end
---------------------------------------------------------------------

-- TODO(dbriscoe): Rename since it doesn't stop time.
function SetPause(val, reason)
	if val ~= paused then
		pause_reason = reason or "none given"
		--~ TheLog.ch.Sim:printf("SetPause: %s -> %s (%s)", paused, val, pause_reason)
		if val then
			paused = true
		else
			paused = false
		end
		return true
	end
end

-- Usually we push a screen with SetWantsPause instead of calling
-- SetGameplayPause directly.
function SetGameplayPause(should_pause, reason)
	if not SetPause(should_pause, reason) then
		-- Do nothing for no change.
		return
	end
	-- TODO: Allow host to pause in net games and show STRINGS.UI.PAUSEMENU.HOST_PAUSE_FMT to clients
	local is_net_bootstrap = (reason == "InitGame") and TheNet:IsHost()

	if not is_net_bootstrap and not TheNet:IsGameTypeLocal() then
		-- Cannot pause in a non-local network game
		return
	end
	is_gameplay_paused = should_pause
	TheSim:SetGameplayPause(should_pause)
end

--- EXTERNALLY SET GAME SETTINGS ---
InstanceParams = nil
function ProcessInstanceParameters(instance_params)
	-- decode and cache params saved during SimReset shutdown
	if instance_params ~= "" then
		InstanceParams = json.decode(instance_params)
		InstanceParams.settings = InstanceParams.settings or {}
	else
		InstanceParams = { settings = {} }
	end
end

Purchases = {}
function SetPurchases(purchases)
	if purchases ~= "" then
		Purchases = json.decode(purchases)
	end
end

function ProcessJsonMessage(message)
	--print("ProcessJsonMessage", message)

	local player = GetDebugPlayer()

	local command = TrackedAssert("ProcessJsonMessage", json.decode, message)

	-- Sim commands
	if command.sim ~= nil then
		--print( "command.sim: ", command.sim )
		--print("Sim command", message)
		if command.sim == "toggle_pause" then
			--TheSim:TogglePause()
			SetPause(not IsPaused())
		elseif command.sim == "quit" then
			if player then
				player:PushEvent("quit", {})
			end
		elseif type(command.sim) == "table" and command.sim.playerid then
			TheFrontEnd:SendScreenEvent("onsetplayerid", command.sim.playerid)
		end
	end
end

function LoadFonts()
	for k, v in pairs(FONTS) do
		TheSim:LoadFont(
			v.filename,
			v.alias,
			v.sdfthreshold,
			v.sdfboldthreshold,
			v.sdfshadowthreshold,
			v.supportsItalics
		)
	end

	for k, v in pairs(FONTS) do
		if v.fallback and v.fallback ~= "" then
			TheSim:SetupFontFallbacks(v.alias, v.fallback)
		end
		if v.adjustadvance ~= nil then
			TheSim:AdjustFontAdvance(v.alias, v.adjustadvance)
		end
	end
end

function UnloadFonts()
	for k, v in pairs(FONTS) do
		TheSim:UnloadFont(v.alias)
	end
end

local function Check_Mods()
	if MODS_ENABLED then
		if GAMEPLAY_MODS_ENABLED then
			--after starting everything up, give the mods additional environment variables
			ModManager:SetPostEnv(GetDebugPlayer())
		end

		--By this point the game should have either a) disabled bad mods, or b) be interactive
		KnownModIndex:EndStartupSequence(nil) -- no callback, this doesn't need to block and we don't need the results
	end
end

local function CheckControllers()
	if TheInput:HasAnyConnectedGamepads() then
		TheFrontEnd:StopTrackingMouse(true)
	end
	Check_Mods()
end

function Start()
	if SOUNDDEBUG_ENABLED then
		require "debugsounds"
	end

	---The screen manager
	-- It's too early during init to require it at the top, so do it here.
	local FrontEnd = require "frontend"
	TheFrontEnd = FrontEnd()
	require "gamelogic"

	known_assert(TheSim:CanWriteConfigurationDirectory(), "CONFIG_DIR_WRITE_PERMISSION")
	known_assert(TheSim:CanReadConfigurationDirectory(), "CONFIG_DIR_READ_PERMISSION")
	--jcheng:handling this with a popup now
	--known_assert(TheSim:HasEnoughFreeDiskSpace(), "CONFIG_DIR_DISK_SPACE")

	if InGamePlay() and IS_QA_BUILD then
		print("Running c_qa_build()")
		c_qa_build()
	end
	
	if NETFLIX_DEMO_BUILD then
		RefreshGodMode()
	end

	--load the user's custom commands into the game
	if CUSTOMCOMMANDS_ENABLED then
		TheSim:GetPersistentString("../customcommands.lua",
			function(load_success, str)
				if load_success then
					local fn = load(str)
					known_assert(fn ~= nil, "CUSTOM_COMMANDS_ERROR")
					xpcall(fn, debug.traceback)
				end
			end)
	end

	if TheSim:FileExists("scripts/localexec_no_package/localexec.lua") then
		print("Loading Localexec...")
		local result, val = pcall(function()
			return require("localexec_no_package.localexec")
		end)
		if result == false then
			print(val)
		end
		print("...done loading localexec")
	end

	if AUTOMATION_SCRIPT then
		print("Loading automation script: "..AUTOMATION_SCRIPT)
		require("automation_no_package/"..AUTOMATION_SCRIPT)
		print("...done loading automation script: "..AUTOMATION_SCRIPT)
	end

	CheckControllers()

	if InstanceParams.dbg ~= nil then
		-- Cache so below can reinit it if necessary.
		local dbg = InstanceParams.dbg
		InstanceParams.dbg = nil

		local open_nodes = dbg.open_nodes
		if open_nodes then
			for node_class_name in pairs(open_nodes) do
				local PanelClass = DebugNodes[node_class_name]
				if PanelClass.CanBeOpened() then
					TheFrontEnd:CreateDebugPanel(PanelClass())
				end
			end
			dbg.open_nodes = nil
		end

		if dbg.load_replay then
			if TheWorld then
				TheWorld:DoTaskInTime(0.1, function()
					local panel = TheFrontEnd:CreateDebugPanel(DebugNodes.DebugHistory())
					local editor = panel:GetNode()
					editor:Load()
				end)
			end
			dbg.load_replay = nil
		end
		dbassert(next(dbg) == nil, "Failed to handle all InstanceParams.dbg features.")
	end
end

--------------------------


-- Gets called ONCE when the sim first gets created. Does not get called on subsequent sim recreations!
function GlobalInit()
	print("Steam Deck:",Platform.IsSteamDeck())
	print("Big Picture Mode:",Platform.IsBigPictureMode())
	local global_prefabs = { "global", }
	TheSim:LoadPrefabs(global_prefabs)
	LoadFonts()
	if Platform.IsPS4() then
		PreloadSounds()
	end
	TheSim:SendHardwareStats()
end

function DoLoadingPortal(cb)
	local values = {}
	local screen = TheFrontEnd:GetActiveScreen()
	values.join_screen = screen ~= nil and screen._widgetname or "other"
	Stats.PushMetricsEvent("joinfromscreen", TheNet:GetUserID(), values)

	--No portal anymore, just fade to "white". Maybe we want to swipe fade to the loading screen?
	TheFrontEnd:Fade(FADE_OUT, SCREEN_FADE_TIME, cb, nil, nil, "white")
	return
end

-- This is for joining a game: once we're done downloading the map, we load it and simreset
function LoadMapFile(map_name)
	local function do_load_file()
		DisableAllDLC()
		StartNextInstance({
			reset_action = RESET_ACTION.LOAD_FILE,
			save_name = map_name,
		})
	end

	if InGamePlay() then
		-- Must be a synchronous load if we're in any game play state (including lobby screen)
		do_load_file()
	else
		DoLoadingPortal(do_load_file)
	end
end

function JapaneseOnPS4()
	if Platform.IsPS4() and APP_REGION == "SCEJ" then
		return true
	end
	return false
end


local function WantsLoadFrontEnd(settings)
	return settings.reset_action == nil or settings.reset_action == RESET_ACTION.LOAD_FRONTEND
end

local __startedNextInstance

function StartNextInstance(settings)
	if not __startedNextInstance then
		__startedNextInstance = true
		ShowLoading()
		AssetLoader.PrefetchPrefabAssets(settings)
		Updaters.TriggerSimReset(settings)
	end
end

function ForceAssetReset()
	-- TODO(mods): Test this successfully unloads all mod assets.
	local settings = InstanceParams.settings
	if settings.last_back_end_prefabs then
		TheSim:UnloadPrefabs(settings.last_back_end_prefabs)
		settings.last_back_end_prefabs = nil
	end
end

function HostLoadRoom(settings)
	if TheNet:IsHost()
		and not WantsLoadFrontEnd(settings)
		-- HACK(network): Not sure how network should handle debug loading
		-- rooms. They don't set a room id, but there's probably a better way
		-- to detect?
		and settings.room_id
	then
		TheNet:HostLoadRoom(settings.reset_action, settings.world_prefab, settings.scenegen_prefab or "", settings.room_id, settings.force_reset, settings.prev_room_cardinal)
	end
end

function SimReset(settings)
	SimTearingDown = true

	local lastsettings = InstanceParams.settings
	settings = settings or {}
	dbassert(settings.last_asset_set == nil,        "Don't set. We'll auto copy from current settings.")
	dbassert(settings.last_back_end_prefabs == nil, "Don't set. We'll auto copy from current settings.")
	settings.last_asset_set = lastsettings.last_asset_set
	settings.last_back_end_prefabs = lastsettings.last_back_end_prefabs

	local dbg = InstanceParams.dbg

	local params = {
		settings = settings,
		dbg = dbg,
	}
	params = json.encode(params)

	HostLoadRoom(settings)

	TheSim:SetInstanceParameters(params)
	TheSim:Reset()
end

function RequestShutdown(requested_exit_code)
	-- This guard is important as this function will get invoked multiple times if shutdown is initiated from Lua.
	if SimShuttingDown then
		return
	end
	SimShuttingDown = true

	local exit_code = requested_exit_code or ExitCode.Success
	TheLog.ch.Sim:printf("Ending the sim now, exit code [%d]", exit_code)

	-- Don't bother trying to show UI since we shutdown too fast to see it.
	--~ if not TheNet:GetServerIsDedicated() then
	--~     -- Must delay or it crashes imgui for some reason.
	--~     TheFrontEnd.gameinterface:DoTaskInTime(0, function(inst_)
	--~         TheFrontEnd:PushScreen(
	--~             WaitingDialog()
	--~ 				:SetTitle(STRINGS.UI.QUITTINGTITLE)
	--~ 				:SetWaitingText(STRINGS.UI.QUITTING))
	--~     end)
	--~ end

	--V2C: Assets will be unloaded when the C++ subsystems are deconstructed
	--UnloadFonts()

	-- warning, we don't want to run much code here. We're in a strange mix of loaded assets and mapped paths
	-- as a bonus, the fonts are unloaded, so no asserting...
	--TheSim:UnloadAllPrefabs()
	--ModManager:UnloadPrefabs()
	
	-- When shutdown is initiated from C++ (i.e. execution is being aborted due to a critical error) it will still
	-- depend on this call to shut the app down *IF* the Lua sim is still running and valid.
	TheSim:Quit(exit_code)
end

function DisplayError(error_msg)
	SetPause(true, "DisplayError")
	if TheFrontEnd.error_widget ~= nil then
		return nil
	end

	print(error_msg) -- Failsafe since sometimes the error screen fails to display.

	local modnames = KnownModIndex:GetEnabledModNames()

	local have_submenu = not DEV_MODE

	local debug_btn = {
		submenu = have_submenu,
		text = STRINGS.UI.MAINSCREEN.SCRIPTERROR_DEBUG,
		cb = function()
			if not TheFrontEnd:FindOpenDebugPanel(DebugNodes.DebugConsole) then
				DebugNodes.ShowDebugPanel(DebugNodes.DebugConsole, false)
			end
		end,
	}
	-- local save_replay_btn = {
	-- 	submenu = have_submenu,
	-- 	text = STRINGS.UI.MAINSCREEN.SCRIPTERROR_SAVE_REPLAY,
	-- 	cb = function()
	-- 		TheFrontEnd.debugMenu.history:Save()
	-- 		TheSim:OpenGameSaveFolder()
	-- 	end,
	-- }
	local restart_btn = {
		text = STRINGS.UI.MAINSCREEN.SCRIPTERROR_RESTART,
		cb = function()
			c_reset()
		end,
	}
	local clipboard_btn = {
		submenu = have_submenu,
		text = STRINGS.UI.MAINSCREEN.SCRIPTERROR_COPY_CLIPBOARD,
		cb = function()
			local ui = require "dbui.imgui"
			ui:SetClipboardText(error_msg)
		end,
	}
	local back_btn = {
		submenu = have_submenu,
		text = STRINGS.UI.MAINSCREEN.SCRIPTERRORBACK,
		cb = function()
			-- the menu is automatically closed
		end,
	}
	local more_btn = {
		text = STRINGS.UI.MAINSCREEN.SCRIPTERRORMORE,
		cb = function()
			TheFrontEnd.error_widget:ShowMoreMenu()
		end,
	}

	local quit_btn = {
		submenu = have_submenu,
		text = STRINGS.UI.MAINSCREEN.SCRIPTERRORQUIT,
		style = "NEGATIVE_BUTTON_STYLE",
		cb = function()
			TheSim:ForceAbort(ExitCode.ScriptError)
		end,
	}

	local troubleshoot_btn = {
		text = STRINGS.UI.SCRIPTERROR.TROUBLESHOOTING,
		cb = function()
			VisitURL(URLS.troubleshooting)
		end,
	}

	-- Default formatting for showing callstacks.
	local anchor = ANCHOR_LEFT
	local font_size = 20
	local mod_icon = {
		icon_tex = "images/ui_ftf_dialog/quirk_mad_science.tex",
	}
	local icon_forums = "<p img='images/ui_ftf_dialog/quirk_usuday.tex' color=0> "

	-- Check hackmods first since they're least obvious to players and we can
	-- do nothing to make them behave.
	if TheSim:IsGameDataModified() then
		local buttons = {
			{
				text = STRINGS.UI.SCRIPTERROR.HACKMOD.REMOVE_MODS,
				cb = function()
					VisitURL(URLS.about_hackmods)
				end,
			},
			restart_btn,
			quit_btn,
		}
		SetGlobalErrorWidget(
			STRINGS.UI.SCRIPTERROR.HACKMOD.TITLE,
			error_msg,
			buttons,
			anchor,
			STRINGS.UI.SCRIPTERROR.HACKMOD.DESC,
			font_size,
			nil,
			mod_icon
		)

	elseif #modnames > 0 then
		local modnamesstr = ""
		for k, modname in ipairs(modnames) do
			modnamesstr = modnamesstr.."\""..KnownModIndex:GetModFancyName(modname).."\" "
		end

		local buttons = nil
		if Platform.IsNotConsole() then
			buttons = {
				restart_btn,
				troubleshoot_btn,
				{
					text = "<p img='images/ui_ftf_icons/discord_off.tex' scale=1.2 color=0>  ".. STRINGS.UI.MAINSCREEN.SCRIPTERROR_MOD.RESET_WITHOUT_MODS,
					submenu = false,
					cb = function()
						KnownModIndex:DisableAllModsBecauseBad()
						ForceAssetReset()
						KnownModIndex:Save(function()
							SimReset()
						end)
					end,
				},
				{
					text = icon_forums .. STRINGS.UI.MAINSCREEN.SCRIPTERROR_MOD.MODFORUMS,
					submenu = false,
					cb = function()
						VisitURL(URLS.mod_forum)
					end,
				},
				quit_btn,
			}
		end
		SetGlobalErrorWidget(
			STRINGS.UI.MAINSCREEN.TITLE_MODFAIL,
			error_msg,
			buttons,
			anchor,
			STRINGS.UI.MAINSCREEN.SCRIPTERROR_MOD.INSTALLED_MODS .."\n".. modnamesstr,
			font_size,
			nil,
			mod_icon
		)

	else
		local buttons = nil

		-- If we know what happened, display a better message for the user
		local known_error = GetCurrentKnownError()
		if known_error then
			error_msg = known_error.message
			-- Bigger display when not showing callstack.
			anchor = ANCHOR_MIDDLE
			font_size = 30
		elseif DEV_MODE
			and APP_VERSION ~= "-1" -- local build == -1
			and error_msg:find("attempt to call a nil value (method", nil, true)
		then
			error_msg = "Called function that doesn't exist (yet?). Wait a minute, grab new binaries, and try again.\n\n" .. error_msg
		end

		if Platform.IsNotConsole() then
			buttons = {
				clipboard_btn,
				restart_btn,
				troubleshoot_btn,
				-- save_replay_btn,
			}
			if DEV_MODE then
				table.insert(buttons, 1, debug_btn)
				-- table.insert(buttons, save_replay_btn)
			end
			if have_submenu then
				table.insert(buttons, more_btn)
				table.insert(buttons, 1, back_btn)
 			end
			if known_error and known_error.url then
				table.insert(buttons, {
					text = STRINGS.UI.MAINSCREEN.GETHELP,
					nopop = true,
					cb = function()
						VisitURL(known_error.url)
					end,
				})
			else
				-- TODO: Get error status from backend, if we get KNOWN_ISSUE
				-- then rename this to SCRIPTERROR_BUGTRACKER, and display
				-- the right string from STRINGS.UI.CRASH_STATUS.
				--~ table.insert(buttons, {
				--~ 		text = icon_forums .. STRINGS.UI.MAINSCREEN.ISSUE, nopop=true,
				--~ 		cb = function()
				--~ 			VisitURL(URLS.klei_bug_tracker)
				--~ 		end
				--~ 	})
			end

			-- Quit should always be last.
			table.insert(buttons, quit_btn)
		end

		SetGlobalErrorWidget(
			STRINGS.UI.MAINSCREEN.TITLE_GAMEFAIL,
			error_msg,
			buttons,
			anchor,
			nil,
			font_size
			)
	end
end

function SetPauseFromCode(pause)
	if pause then
		if InGamePlay() and not IsPaused() then
			local PauseScreen = require "screens.pausescreen"
			TheFrontEnd:PushScreen(PauseScreen(nil))	-- pass in a player?
		end
	end
end

-- Whether we're in the main menu (start screen) or loaded into gameplay (town,
-- dungeon, etc).
--
-- Do not use during loading! Will be false while loading into game until load
-- completes. See IsInFrontEnd() instead.
local in_game_play
function InGamePlay()
	return in_game_play
end

-- Only mainfunctions load flow and roomloader fallback flow should call this function!
function ForceInGamePlay()
	in_game_play = true
end

function IsMigrating()
	--Right now the only way to really tell if we are migrating is if we are neither in FE or in gameplay, which results in no screen...
	--      e.g. if there is no active screen, or just a connecting to game popup
	--THIS SHOULD BE IMPROVED YARK YARK YARK
	--V2C: Who dat? ----------^
	local screen = TheFrontEnd:GetActiveScreen()
	return screen == nil or (screen._widgetname == "ConnectingToGamePopup" and TheFrontEnd:GetScreenStackSize() <= 1)
end

-- RestartToMainMenu helpers
local function postsavefn()
	TheNet:EndGame()
	EnableAllMenuDLC()

	StartNextInstance()
	in_game_play = false
--	PerformingRestart = false	-- DON'T set this back to false, or the networking.lua IsReadyForInvite will fail to return the proper value. 
end
local function savefn()
	if TheWorld == nil then
		postsavefn()
	else
		-- TODO(saveload): This doesn't actually save anything. Should use TheSaveSystem:SaveAll(shutdown) instead.
		for i, v in ipairs(AllPlayers) do
			v:OnDespawn()
		end
		TheSystemService:EnableStorage(true)
		postsavefn()
	end
end

function RestartToMainMenu(save)
	print("RestartToMainMenu: should_save=", save)

	if not PerformingRestart then
		PerformingRestart = true
		ShowLoading()
		TheFrontEnd:Fade(FADE_OUT, 1, save and savefn or postsavefn)
	end
end

local screen_fade_time = 0.25

function OnPlayerLeave(player_guid, expected)
	if player_guid ~= nil then
		local player = Ents[player_guid]
		if player ~= nil then
			--Save must happen when the player is actually removed
			--This is currently handled in playerspawner listening to ms_playerdespawn
			TheWorld:PushEvent("ms_playerdisconnected", { player = player, wasExpected = expected })
			TheWorld:PushEvent("ms_playerdespawn", player)
		end
	end
end

function OnDemoTimeout()
	print("Demo timed out")
	RestartToMainMenu()
end


-- Receive a disconnect notification
function OnNetworkDisconnect(message, should_reset, force_immediate_reset, details)
	print("OnNetworkDisconnect called: " .. message)

	-- TODO: save progress here?

	-- The client has requested we immediately close this connection
	if force_immediate_reset == true then
		print("force_immediate_reset!")
		RestartToMainMenu("save")
		return
	end

	local title = STRINGS.UI.NETWORKDISCONNECT.TITLE[message] or STRINGS.UI.NETWORKDISCONNECT.TITLE.DEFAULT
	message = STRINGS.UI.NETWORKDISCONNECT.BODY[message] or STRINGS.UI.NETWORKDISCONNECT.BODY.DEFAULT

	HideConnectingToGamePopup()


	--Don't need to reset if we're in FE already
	should_reset = should_reset and not IsInFrontEnd()

	local yes_msg = STRINGS.UI.NETWORKDISCONNECT.CONFIRM_OK
	if should_reset then
		yes_msg = STRINGS.UI.NETWORKDISCONNECT.CONFIRM_RESET
	end

	local function doquit()
		if should_reset then
			RestartToMainMenu() --don't save again
		else
			TheFrontEnd:PopScreen()
			-- Make sure we try to enable the screen behind this
			local screen = TheFrontEnd:GetActiveScreen()
			if screen then
				screen:Enable()
			end
		end
	end

	TheFrontEnd:SetFadeLevel(0)	-- Disable all fading.
	HideLoading(true)	-- Also hide the loading screen

	local dialog = ConfirmDialog(nil, nil, true,
			title,
			nil,
			message,
			function()
			end
		)
		:FollowTextScaling()
		:SetYesButton(yes_msg, doquit, true)
		:HideNoButton()
		:HideArrow()
		:SetMinWidth(600)
		:CenterText()
		:CenterButtons()

	if IsInFrontEnd() then
		print("OnNetworkDisconnect pushing confirm dialog. Message=" .. message)
		TheFrontEnd:PushScreen(dialog)
	else
		print("OnNetworkDisconnect pushing fatal confirm dialog. Message=" .. message)
		TheFrontEnd:PushFatalErrorScreen(dialog)
	end

	local screen = TheFrontEnd:GetActiveScreen()
	if screen then
		screen:Enable()
			:AnimateIn()
	end
	return true
end

-- A network invite was received, but we're running in offline mode
function OnNetworkInviteDisabled()
	if OFFLINE_DIALOG then
		-- if we came in through an invite in offline mode there's already a popup showing for that
		-- This one is more appropriate
		TheFrontEnd:PopScreen(OFFLINE_DIALOG)
		OFFLINE_DIALOG = nil
	end

	local body = table.concat({
			STRINGS.UI.DATACOLLECTION.REQUIREMENT,
			STRINGS.UI.DATACOLLECTION.EXPLAIN_POPUP.SEE_PRIVACY,
		},
		"\n\n")
	local dialog = ConfirmDialog(nil, nil, true, STRINGS.UI.NETWORKINVITEDISABLED.TITLE, nil, body)
	dialog
		:FollowTextScaling()
		:SetYesButton(STRINGS.UI.NETWORKINVITEDISABLED.CLOSE, 
			function()
					dialog:Close()
			end)
		:HideArrow() 
		:HideNoButton()
		:SetMinWidth(1000)
		:CenterButtons()
	TheFrontEnd:PushScreen(dialog)
	dialog:AnimateIn()
end

OnAccountEventListeners = {}

-- TODO: Convert to gameevent listeners:
--   inst:ListenForEvent("klei_account_update", self._onsystem_account_update, TheGlobalInstance)
function RegisterOnAccountEventListener(listener)
	table.insert(OnAccountEventListeners, listener)
end

function RemoveOnAccountEventListener(listener_to_remove)
	local index = 1
	for k, listener in pairs(OnAccountEventListeners) do
		if listener == listener_to_remove then
			table.remove(OnAccountEventListeners, index)
			break
		end
		index = index + 1
	end
end

function OnAccountEvent(success, event_code)
	-- For event_code, see AccountActions in metrics.lua
	for k, listener in pairs(OnAccountEventListeners) do
		if listener ~= nil then
			listener:OnAccountEvent(success, event_code)
		end
	end
end

function TintBackground(bg)
	--if IsDLCEnabled(REIGN_OF_GIANTS) then
	--    bg:SetMultColor(table.unpack(BGCOLORS.PURPLE))
	--else
		-- bg:SetMultColor(table.unpack(BGCOLORS.GREY))
		bg:SetMultColor(table.unpack(BGCOLORS.FULL))
	--end
end

function OnFocusLost()
	local fmodtable = require "defs.sound.fmodtable"
	if TheGameSettings:Get("audio.mute_on_lost_focus") then
		TheAudio:StartFMODSnapshot(fmodtable.Snapshot.Mute_Everything_LoseFocus)
	end

	if Platform.IsAndroid() and InGamePlay() then
		-- Common to lose focus on Android, so save game and pause.
		-- TODO: Save()
		SetPause(true)
	end
end

function OnFocusGained()
	local fmodtable = require "defs.sound.fmodtable"
	if TheGameSettings:Get("audio.mute_on_lost_focus") then
		TheAudio:StopFMODSnapshot(fmodtable.Snapshot.Mute_Everything_LoseFocus)
	end

	last_focus_gain_tick = GetTick()

	if Platform.IsAndroid() and InGamePlay() then
		-- See OnFocusLost.
		SetPause(false)
	end
end


local function PrintPcall(status, ...)
	TheSim:ProfilerPush("PrintPcall")
	if status then
		local result = "\n"
		local sep = ""
		for i, v in ipairs({ ... }) do
			local str = tostring(v)
			if type(v) == "table" then
				str = ("'%s': %s"):format(str, table.inspect(v, { depth = 1 }))
			end
			result = result .. sep .. str
			sep = ", "
		end
		nolineprint(result)
	else
		nolineprint(...)
	end
	TheSim:ProfilerPop()
	return status
end

-- Execute arbitrary lua
function ExecuteConsoleCommand(fnstr)
	TheSim:ProfilerPush("ConsoleCommand")

	local fn, err = load("return " .. fnstr)
	if not fn then
		fn, err = load(fnstr)
	end

	local success = false
	nolineprint(">>>", fnstr)
	if fn then
		success = PrintPcall(pcall(fn))
	else
		nolineprint(err)
	end

	TheSim:ProfilerPop()
	return success
end

-- TODO: unused? remove.
function BuildTagsStringCommon(tagsTable)
	-- Vote command tags (controlled by master server only)

	-- Mods tags
	for i, mod_tag in ipairs(KnownModIndex:GetEnabledModTags()) do
		table.insert(tagsTable, mod_tag)
	end

	-- Language tag (forced to front of list, don't put anything else at slot 1, or language detection will fail!)
	table.insert(tagsTable, 1, STRINGS.PRETRANSLATED.LANGUAGES[LOC.GetCurrentLanguageId()] or "")

	-- Concat unique tags
	local tagged = {}
	local tagsString = ""
	for i, v in ipairs(tagsTable) do
		--trim whitespace
		v = v:lower():match("^%s*(.-%S)%s*$") or ""
		if v:len() > 0 and not tagged[v] then
			tagged[v] = true
			tagsString = tagsString:len() > 0 and (tagsString .. "," .. v) or v
		end
	end

	return tagsString
end

function SaveAndShutdown()
	local shutdown = function()
		RequestShutdown(ExitCode.Success)
	end
	if TheWorld then
		TheSaveSystem:SaveAll(shutdown)
	else
		shutdown()
	end
end

-- See also InGamePlay().
function IsInFrontEnd()
	return WantsLoadFrontEnd(InstanceParams.settings)
end

function EnableDebugFacilities()
	CONSOLE_ENABLED = true
	CHEATS_ENABLED = true
	require "debugcommands"
	require "debugkeys"
	TheFrontEnd:EnableDebugFacilities()
end

require "dlcsupport"
