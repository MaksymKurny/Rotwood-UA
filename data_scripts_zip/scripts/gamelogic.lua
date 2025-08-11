local AssetLoader = require "assetloader"
local CancelTip = require "widgets.canceltipwidget"
local ConfirmDialog = require "screens.dialogs.confirmdialog"
local Enum = require "util.enum"
local ExitCode = require "exit_code"
local Lume = require "util.lume"
local MainScreen = require "screens.mainscreen"
local ProfanityFilter = require "util.profanityfilter"
local SceneGen = require "components.scenegen"
local URLS = require "urls"
local WaitingForPlayersScreen = require "screens.waitingforplayersscreen"
local kassert = require "util.kassert"
local Placer = require "components.placer"
local Environment = require "environment"
local LightingLayer = require "defs.lightinglayer"
local FrenzyTypesFilter = require "proc_gen.frenzy_types_filter"
local playerutil = require "util.playerutil"
require "constants"
require "knownerrors"
require "perfutil"

local Neighborhoods = Enum { "town", "dungeon" }

if Platform.IsRail() then
	TheSim:SetMemInfoTrackingInterval(5*60)
end

function SetGlobalErrorWidget(...)
    if TheFrontEnd.error_widget == nil then -- only first error!
		TheFrontEnd:SetGlobalErrorWidget(...)
    end
end

local cancel_tip = CancelTip()
	:SetAnchors("center","top")

TheLog.ch.SaveLoad:print("[Loading frontend assets]")

function ForceAuthenticationDialog()
	if not InGamePlay() then
		local active_screen = TheFrontEnd:GetActiveScreen()
		if active_screen ~= nil and active_screen._widgetname == "MainScreen" then
			active_screen:OnLoginButton(false)
		elseif MainScreen then
			local skip_start = not RUN_GLOBAL_INIT
			local main_screen = MainScreen(Profile, skip_start)
			TheFrontEnd:ShowScreen( main_screen )
			main_screen:OnLoginButton(false)
		end
	end
end

local function KeepAlive()
	local global_loading_widget = TheFrontEnd.loading_widget
	if global_loading_widget then
		global_loading_widget:ShowNextFrame()
		if cancel_tip then
			cancel_tip:ShowNextFrame()
		end
		-- TODO(roomtravel): Can't RenderOneFrame during room travel because it
		-- triggers native sim update assert.
		if not InGamePlay() then
			TheSim:RenderOneFrame()
		end
		global_loading_widget:ShowNextFrame()
		if cancel_tip then
			cancel_tip:ShowNextFrame()
		end
	end
end

function ShowLoading()
	local global_loading_widget = TheFrontEnd.loading_widget
	if global_loading_widget then
		global_loading_widget:SetEnabled(true)
	end
end

function HideLoading(force)
	local global_loading_widget = TheFrontEnd.loading_widget
	if global_loading_widget then
		global_loading_widget:SetEnabled(false)
		if force then
			global_loading_widget:Hide()
		end
	end
end

function ShowCancelTip()
	if cancel_tip then
		cancel_tip:SetEnabled(true)
	end
end

function HideCancelTip()
	if cancel_tip then
		cancel_tip:SetEnabled(false)
	end
end

local function RegisterAllPrefabs(init_dlc, async_batch_validation)
	RegisterAllDLC()
	for i = 1, #PREFABFILES do -- required from prefablist.lua
		LoadPrefabFile("prefabs/" .. PREFABFILES[i], async_batch_validation or false)
	end
	if init_dlc then
		InitAllDLC()
	end
	ModManager:RegisterPrefabs()
end

local function LoadPlayerPrefabs()
	TheLog.ch.Load:print("\tLOAD PLAYER_PREFABS")
	TheSystemService:SetStalling(true)
	TheSim:LoadPrefabs(PLAYER_PREFABS)
	TheSystemService:SetStalling(false)
	KeepAlive()
	TheLog.ch.Load:print("\tLOAD PLAYER_PREFABS done")
end

-- Decision logic here needs to match AssetLoader.PrepareAssetPrefetch
-- TODO: reconcile both functions
local function LoadAssets(asset_set, savedata)
	ShowLoading()

	local settings = InstanceParams.settings

	if AssetLoader.UsePrefetch(settings) then
		KeepAlive()
		AssetLoader.WaitForPrefetch()
	end

	assert(asset_set)

	local back_end_prefabs = shallowcopy(BACKEND_PREFABS)
	if savedata and savedata.map then
		if savedata.map.prefab then
			table.insert(back_end_prefabs, savedata.map.prefab)
		end
		if savedata.map.scenegenprefab then
			table.insert(back_end_prefabs, savedata.map.scenegenprefab)
		end
	end

	KeepAlive()

	if asset_set == "FRONTEND" then
		if settings.last_asset_set == asset_set then
			TheLog.ch.Load:print("\tFE assets already loaded")
			RegisterAllPrefabs() -- sanity check??
		else
			if settings.last_asset_set == "BACKEND" then
				TheLog.ch.Load:print("\tUnload BE")
				if not USE_SAVESLOT_DATA_FLOW then
					TheSim:UnloadPrefabs(PLAYER_PREFABS)
				end
				if settings.last_back_end_prefabs ~= nil then
					TheSim:UnloadPrefabs(settings.last_back_end_prefabs)
				end
				KeepAlive()
				TheLog.ch.Load:print("\tUnload BE done")
			end

			TheSystemService:SetStalling(true)
			TheSim:UnregisterAllPrefabs()
			local async_batch_validation = settings.last_asset_set == nil
			RegisterAllPrefabs(false, async_batch_validation)
			TheSystemService:SetStalling(false)
			KeepAlive()

			TheLog.ch.Load:print("\tLoad FE")
			TheSystemService:SetStalling(true)
			TheSim:LoadPrefabs(FRONTEND_PREFABS)
			TheSystemService:SetStalling(false)
			if async_batch_validation then
				TheSim:StartFileExistsAsync()
				TheGlobalInstance.async_validate_task = TheGlobalInstance:DoPeriodicTask(1, function()
					local complete, err = TheSim:ProbeFileExistsAsync()
					TheLog.ch.Load:print("[FilesExist] async_validate_task complete:", complete, "error:", err)
					if err then
						local popup = ConfirmDialog(nil, nil, true)
							:SetTitle(STRINGS.UI.MAINSCREEN.ERROR_MISSING_FILE.TITLE)
							:SetSubtitle(STRINGS.UI.MAINSCREEN.ERROR_MISSING_FILE.DESC)
							:SetText(STRINGS.UI.MAINSCREEN.ERROR_MISSING_FILE.BODY:subfmt({
									file_list = err,
							}))
							:HideArrow()
							:SetYesButton(STRINGS.UI.MAINSCREEN.ERROR_MISSING_FILE.INSTRUCTIONS, function()
								VisitURL(URLS.troubleshooting)
							end, true)
							:SetNoButton(STRINGS.UI.MAINSCREEN.QUIT, function()
								TheSim:Quit(ExitCode.MissingAssets)
							end, false)
							:CenterText()
						TheFrontEnd:PushFatalErrorScreen(popup)
						complete = true
					end
					if complete then
						TheGlobalInstance.async_validate_task:Cancel()
						TheGlobalInstance.async_validate_task = nil
					end
				end)
			end
			TheLog.ch.Load:print("\tLoad FE done")
		end
	else
		kassert.equal(asset_set, "BACKEND")
		if settings.last_asset_set == asset_set then
			TheLog.ch.Load:print("\tBack end state has changed. Unloading unused prefabs, loading required prefabs.")

			local unloadables = Lume(settings.last_back_end_prefabs)
				:filter(function(prefab)
					return not Lume(back_end_prefabs)
						:find(prefab)
						:result()
				end)
				:result()
			local loadables = Lume(back_end_prefabs)
				:filter(function(prefab)
					return not Lume(settings.last_back_end_prefabs)
						:find(prefab)
						:result()
				end)
				:result()

			if next(unloadables) then
				TheLog.ch.Load:print("\tUnload BE")
				TheSim:UnloadPrefabs(unloadables)
				KeepAlive()
				TheLog.ch.Load:print("\tUnload BE done")
			end

			TheSystemService:SetStalling(true)
			RegisterAllPrefabs()
			TheSystemService:SetStalling(false)
			KeepAlive()

			if next(loadables) then
				TheLog.ch.Load:print("\tLOAD BE")
				TheSystemService:SetStalling(true)
				TheSim:LoadPrefabs(loadables)
				TheSystemService:SetStalling(false)
				KeepAlive()
				TheLog.ch.Load:print("\tLOAD BE done")
			end
		else
			if settings.last_asset_set == "FRONTEND" then
				TheLog.ch.Load:print("\tUnload FE")
				TheSim:UnloadPrefabs(FRONTEND_PREFABS)
				KeepAlive()
				TheLog.ch.Load:print("\tUnload FE done")
			end

			TheSystemService:SetStalling(true)
			TheSim:UnregisterAllPrefabs()
			RegisterAllPrefabs(true)
			TheSystemService:SetStalling(false)
			KeepAlive()

			LoadPlayerPrefabs()

			TheLog.ch.Load:print("\tLOAD BE")
			if back_end_prefabs ~= nil then
				TheSystemService:SetStalling(true)
				TheSim:LoadPrefabs(back_end_prefabs)
				TheSystemService:SetStalling(false)
				KeepAlive()
			end
			TheLog.ch.Load:print("\tLOAD BE done")
		end
	end

	AssetLoader.ClearPrefetch()
	settings.last_asset_set = asset_set
	settings.last_back_end_prefabs = back_end_prefabs
end

--Only valid during PopulateWorld
populating_world_ents = nil

--- @param savedata table Serialized world state that was created with RoomSave.
local function PopulateWorld(savedata, profile, savetype)
	assert(savedata ~= nil)
	TheSystemService:SetStalling(true)

	Environment.InitializeState()

	dbassert(populating_world_ents == nil)
	populating_world_ents = {}

	TheSceneGen = savedata.map.scenegenprefab and SpawnPrefab(savedata.map.scenegenprefab)

	local world = SpawnPrefab(savedata.map.prefab)
	dbassert(world ~= nil)
	assert(TheWorld == world)

	world:SetPersistData(savedata.map.data)
	world.ent_highwater_on_load = savedata.ent_highwater

	if savetype == Neighborhoods.s.town
		and not world.components.propmanager  -- Skip if called in SetPersistData.
	then
		InitializeWorldViaSceneList(world)  -- Creates propmanager.
	end

	local dungeon_progress = world:GetDungeonProgress()
	local suppress_environment = false

	--If propmanager exist, load static layout one time
	--See world_autogen.lua (OnPreLoad)
	if world.components.propmanager ~= nil then
		--Instantiate all the layout entities

		-- Should roll this logic into MapLayout.
		local layout = world.map_layout.layout
		if layout ~= nil then
			-- Skip the ground layer
			for i = 2, #layout.layers do
				local objects = layout.layers[i].objects
				if objects ~= nil then
					for j = 1, #objects do
						local object = objects[j]
						local record = world.map_layout:ConvertLayoutObjectToSaveRecord(object)
						SpawnSaveRecord(object.type, record)
					end
				end
			end
		end

		-- Instantiate static, authored props from the world's scenes.
		world.components.propmanager:SpawnStaticProps(layout)

		if savetype == Neighborhoods.s.town then
			local num_decor_removed = 0

			-- We likely spawned some decor in SpawnStaticProps, remove them.
			-- TODO(boot): Could we skip spawning them in the first place?
			local has_town_save = savedata.map.data
				-- Check ent_highwater to handle rare case that we don't save
				-- ents (possibly caused of the initial jump to dungeon?).
				and (savedata.ent_highwater or 0) > 0
			if has_town_save then
				-- Has previously loaded a town. Remove all decor from the town
				-- because placeable decor is persisted in the town save.
				for i,newent in ipairs(populating_world_ents) do
					if newent.inst:HasTag(Placer.DECOR_TAG) then
						newent.inst:Remove(true)
						num_decor_removed = num_decor_removed + 1
					end
				end

			else
				-- New town. Stash decor until after we load player's town save
				-- to give it priority. DecorManager will resolve later.
				world.decor_spawn_records = {}
				for i,newent in ipairs(populating_world_ents) do
					if newent.inst:HasTag(Placer.DECOR_TAG) then
						local record = newent.data or newent.inst:GetSaveRecord()

						-- Rebuild the scene's placements, but limited to decor.
						local t = world.decor_spawn_records[newent.inst.prefab] or {}
						world.decor_spawn_records[newent.inst.prefab] = t
						table.insert(t, record)

						newent.inst:Remove(true)
						num_decor_removed = num_decor_removed + 1
					end
				end
			end

			TheLog.ch.Boot:printf("Loading town: %s. Removed %i decor owned by DecorManager. highwater: %s", has_town_save and "savedata exists" or "created new town", num_decor_removed, savedata.ent_highwater)
		end

		if TheSceneGen then
			local suppress_decor_props = Profile:GetValue("suppress_decor_props", false)
			if not suppress_decor_props
				and world:ProcGenEnabled()
			then
				local authored_prop_placements = world.components.propmanager
					and CollectPropPlacements(world.components.propmanager.filenames)
					or {}
				TheSceneGen.components.scenegen:BuildScene(world, dungeon_progress, authored_prop_placements, FrenzyTypesFilter.GetCurrentFrenzyType())
				suppress_environment = true
			else
				if suppress_decor_props then
					TheLog.ch.Cheat:print("Skipping scenegen:BuildScene() because of suppress_decor_props.")
				end
				TheSceneGen.components.scenegen:InstallZoneGrid(world)
			end
		end
	end

	if not suppress_environment then
		-- Initialize the state to the data supplied by TheWorld and TheSceneGen.
		local dungeon_progress = TheWorld:GetDungeonProgress()

		if TheSceneGen then
			-- Prefer Environment settings from TheSceneGen.
			SceneGen.SetEnvironment(TheWorld, TheSceneGen.components.scenegen, dungeon_progress)
		else
			-- Otherwise, use defaults where TheWorld data has not provided settings.
			if not TheWorld.scene_gen_overrides.lighting then
				Environment.InitializeLighting(LightingLayer.s.Dungeon)
			end
			if not TheWorld.scene_gen_overrides.sky then
				Environment.InitializeSky(LightingLayer.s.Dungeon)
			end
			if not TheWorld.scene_gen_overrides.water then
				ApplyDefaultWater()
			end
		end
	end
	TheDungeon:ApplyLighting()

	-- Instantiate all saved entities from player's save file.
	if savedata.ents ~= nil then
		for prefab, ents in pairs(savedata.ents) do
			for i = 1, #ents do
				local inst = SpawnSaveRecord(prefab, ents[i])

				-- Mark all entities from the player's town save data as decor.
				if inst and savetype == Neighborhoods.s.town then
					world.components.decormanager:OnDecorSpawned(inst)
				end
			end
		end
	end

	--Post pass
	for i = 1, #populating_world_ents do
		local newent = populating_world_ents[i]
		if newent.inst ~= world and newent.inst:IsValid() then
			newent.inst:PostLoadWorld(newent.data)
		end
	end
	world:PostLoadWorld(savedata.map.data)

	populating_world_ents = nil

	--Done
	TheSystemService:SetStalling(false)
end

local pop_mastery_queue_data

local OnAllPlayersReady = function(savedata, profile)
	TheLog.ch.Boot:print("Fade to black")
	TheFrontEnd:FadeToBlack(0)
	--OK, we have our savedata and a profile. Instantiate everything and start the game!
	if not TheNet:IsInGame() then
		TheLog.ch.Boot:printf("OnAllPlayersReady Error: No longer in an active network game");
		return
	end

	TheLog.ch.Boot:printf("OnAllPlayersReady: IsHost[%s] GetNrPlayersOnRoomChange[%s]",
		TheNet:IsHost(), TheNet:GetNrPlayersOnRoomChange())

	TheFrontEnd:GetSound():KillSound("FEMusic")
	TheFrontEnd:GetSound():KillSound("FEPortalSFX")

	if TheFrontEnd.error_widget == nil then
		if TheDungeon.HUD and pop_mastery_queue_data then
			-- Maybe want this to only show AFTER a cinematic ... PlayerSpawner:_QueueGameplayEvent
			TheLog.ch.FrontEnd:printf("PopMastery: Queue data exists from previous HUD: %d items", #pop_mastery_queue_data)

			TheDungeon:DoTaskInTime(2, function()
				if TheDungeon.HUD then
					TheDungeon.HUD:SetPopMasteryProgressQueueData(pop_mastery_queue_data)
				end
				pop_mastery_queue_data = nil
			end)
		end
	else
		TheFrontEnd:SetFadeLevel(1)
	end

	TheDungeon:DoTaskInTicks(1, function()
		local in_cine = false
		local local_players = playerutil.GetLocalPlayers()
		for i,spawned_player in ipairs(local_players) do
			-- Let the cine control the fade if possible.
			in_cine = in_cine or (spawned_player and spawned_player.components.cineactor and spawned_player.components.cineactor:IsInCine())
		end
		if not in_cine then
			TheLog.ch.Boot:print("Fade in from black now")
			TheFrontEnd:FadeInFromBlack()
		else
			TheLog.ch.Boot:print("Fade deferred to cine control")
		end
		ForceInGamePlay() -- the normal transition to gameplay
		TheCamera:Snap()
	end)
end

local function OnFinishedSpawnLocalPlayers()
	TheLog.ch.Boot:printf("OnFinishedSpawnLocalPlayers()")
	TheNet:ConfirmRoomLoadReady()	-- Tell the host we're ready to go.
	TheNet:StartingRoom() -- Signal the networking systems that the room is starting
	HideLoading()
end

local WaitForLocalPlayersTask = nil
local WaitForLocalPlayersTaskTimeoutTicks <const> = 120
local WaitForLocalPlayersTaskTimeout = WaitForLocalPlayersTaskTimeoutTicks

local function ResetWaitForLocalPlayersTask()
	if WaitForLocalPlayersTask then
		WaitForLocalPlayersTask:Cancel()
		WaitForLocalPlayersTask = nil
	end
end

local function BeginRoom(savedata, profile, savetype)
	TheLog.ch.Boot:print("BeginRoom called")
	LoadAssets("BACKEND", savedata)

	local should_post_load_dungeon = false
	if not TheDungeon then
		-- Simpler to let dungeon be a prefab which means putting it after LoadAssets.
		TheDungeon = SpawnPrefab("dungeon")
		-- Don't create hud yet because room information doesn't exist to
		-- populate it.

		TheDungeon:SetPersistData({})

		Environment.AlignLightingLayerWeightsWithTheDungeon()

		should_post_load_dungeon = true
	end

	if savetype == Neighborhoods.s.dungeon then
		TheDungeon:GetDungeonMap():OnCompletedTravel()
	end

	if TheDungeon.HUD then
		pop_mastery_queue_data = TheDungeon.HUD:GetPopMasteryProgressQueueData()
		TheFrontEnd:PopScreen(TheDungeon.HUD)
		TheDungeon.HUD = nil
	end

	-- Each room is a world.
	PopulateWorld(savedata, profile, savetype)

	if should_post_load_dungeon then
		-- Only call this if TheDungeon was newly created.
		TheDungeon:PostLoadWorld()
	end

	TheLog.ch.Boot:printf("World loaded.  Setting up room.")
	TheFrontEnd:ClearScreens()

	assert(savedata.map ~= nil, "Map missing from savedata on load")
	assert(savedata.map.prefab ~= nil, "Map prefab missing from savedata on load")

	local BeginRoomComplete = function()
		-- We are done loading, but the other players in the network game might not
		-- be ready to go yet. So we have to wait until the host tells us we can
		-- continue.
		if not TheNet:IsReadyToStartRoom() then
			TheLog.ch.Boot:print("Waiting for other players...")
			TheFrontEnd:PushScreen(WaitingForPlayersScreen( OnAllPlayersReady, savedata, profile) )
		else
			TheLog.ch.Boot:print("Skipping waiting for other players, as everybody is ready")
			OnAllPlayersReady(savedata, profile)
		end
	end

	if TheFrontEnd.error_widget == nil then
		ModManager:SimPostInit()
		-- This will start the encounter coroutine on the net host.
		assert(TheWorld)
		TheDungeon:StartRoom()
		TheDungeon:CreateHud()

		-- Confirm that underlying network system host has registered at least one local player
		-- Wait here for up to WaitForLocalPlayersTaskTimeoutTicks timeout ticks
		local raw_local_player_count = TheNet:GetNrLocalPlayers(true) -- nil: no network
		if not raw_local_player_count then
			TheLog.ch.Boot:printf("Error: SpawnLocalPlayers - Network session abruptly ended.")
		elseif raw_local_player_count == 0 then
			if not WaitForLocalPlayersTask then
				TheLog.ch.Boot:printf("SpawnLocalPlayers - Waiting for host registration.")

				WaitForLocalPlayersTaskTimeout = WaitForLocalPlayersTaskTimeoutTicks
				WaitForLocalPlayersTask = TheGlobalInstance:DoPeriodicTask(0, function()
					WaitForLocalPlayersTaskTimeout = WaitForLocalPlayersTaskTimeout - 1
					raw_local_player_count = TheNet:GetNrLocalPlayers(true)
					if raw_local_player_count > 0 then
						ResetWaitForLocalPlayersTask()

						TheLog.ch.Boot:printf("SpawnLocalPlayers - Ready, task ticks waited: %d",
							WaitForLocalPlayersTaskTimeoutTicks - WaitForLocalPlayersTaskTimeout)
						TheNet:SpawnLocalPlayers()
						OnFinishedSpawnLocalPlayers()
						BeginRoomComplete()
						return
					end

					if WaitForLocalPlayersTaskTimeout <= 0 then
						TheLog.ch.Boot:printf("Error: SpawnLocalPlayers - Task timed out. Ticks waited: %d",
							WaitForLocalPlayersTaskTimeout)
						ResetWaitForLocalPlayersTask()
						BeginRoomComplete()
					end
				end)
			else
				TheLog.ch.Boot:printf("SpawnLocalPlayers - Continuing to wait for host registration after new room change request.")
				-- do nothing
			end
		else
			TheLog.ch.Boot:printf("SpawnLocalPlayers - Ready")

			TheNet:SpawnLocalPlayers()
			OnFinishedSpawnLocalPlayers()
			BeginRoomComplete()
		end
	else
		BeginRoomComplete()
	end
end

------------------------THESE FUNCTIONS HANDLE STARTUP FLOW

-- We call this if we don't have savedata for the world we're loading.
local function DoGenerateWorld(worldprefab, scenegenprefab, savetype)
	local savedata = {
		map = {
			prefab = worldprefab,
			scenegenprefab = scenegenprefab,
		},
	}
	BeginRoom(savedata, Profile, savetype)
end

local function LoadRoomFromSave(savetype, worldprefab, scenegenprefab, roomid)
	dbassert(Neighborhoods:Contains(savetype))
	dbassert(worldprefab)
	dbassert(roomid)

	local save = TheSaveSystem[savetype]

	if savetype == Neighborhoods.s.town then
		save = TheSaveSystem:GetActiveTownSave()
	end

	save:LoadRoom(roomid, function(savedata, load_error)
		if savedata ~= nil then
			local prefab = savedata.map ~= nil and savedata.map.prefab or nil
			if prefab == worldprefab then -- and not InstanceParams.settings.need_reset then
				BeginRoom(savedata, Profile, savetype)
			else
				-- SAVE-MIGRATION: We want to migrate to a new town prefab because TOWN_LEVEL changed! Here's where we do it!
				-- However, it doesn't make much sense for a dungeon room to mismatch.
				local msg = ("WARNING: Saved %s room [%d:%s] prefab mismatch: %s. Can't load savedata."):format(savetype, roomid, tostring(prefab), worldprefab)
				TheLog.ch.WorldGen:print(msg)
				dbassert(savetype == Neighborhoods.s.town and worldprefab == TOWN_LEVEL, msg)

				-- Load the new town prefab. The player's saved placeables are in savedata.ents.
				savedata.map.prefab = worldprefab
				savedata.map.data = nil
				BeginRoom(savedata, Profile, savetype)
			end
		else
			TheLog.ch.WorldGen:printf("Generating new %s room [%d:%s].", savetype, roomid, worldprefab)
			DoGenerateWorld(worldprefab, scenegenprefab, savetype)
		end
		TheSaveSystem.last_loaded_room_error = load_error
		if AUTOMATION_SCRIPT then
			require("automation_no_package/"..AUTOMATION_SCRIPT).Automate()
		end
	end)
end
local function DoLoadTownRoom(worldprefab, roomid)
	return LoadRoomFromSave(Neighborhoods.s.town, worldprefab, nil, roomid)
end

local function DoLoadDungeonRoom(worldprefab, scenegenprefab, roomid)
	return LoadRoomFromSave(Neighborhoods.s.dungeon, worldprefab, scenegenprefab, roomid)
end

----------------LOAD THE PROFILE AND THE SAVE INDEX, AND START THE FRONTEND

function LoadWorld(settings)
	if DEV_MODE and settings.is_debug_room then
		-- Dev worlds won't have their placements in the list, so load
		-- everything to get their contents.
		d_allprefabs()
	end
	if settings.reset_action == RESET_ACTION.LOAD_TOWN_ROOM then
		DoLoadTownRoom(settings.world_prefab, settings.room_id)
	elseif settings.reset_action == RESET_ACTION.LOAD_DUNGEON_ROOM then
		DoLoadDungeonRoom(settings.world_prefab, settings.scenegen_prefab, settings.room_id)
	elseif settings.reset_action == RESET_ACTION.DEV_LOAD_ROOM then
		DoGenerateWorld(settings.world_prefab, settings.scenegen_prefab, nil)
	else
		error("Unknown reset action ".. tostring(settings.reset_action))
	end
end

local function DoResetAction()
	-- Start loading from a fresh lua sim.
	local ssn = TheNet:GetSimSequenceNumber()
	TheLog.ch.Networking:printf("Simulation Sequence Number: " .. ssn)
	TheNet:DoResetAction();

	local settings = InstanceParams.settings
	if settings.reset_action == nil or settings.reset_action == RESET_ACTION.LOAD_FRONTEND then
		if AUTOMATION_SCRIPT then
			local automation = require("automation_no_package/"..AUTOMATION_SCRIPT)
			if automation.Reset then
				automation.Reset()
				return
			end
		end

		LoadAssets("FRONTEND")
		if MainScreen then
			local skip_start = not RUN_GLOBAL_INIT
			TheFrontEnd:ShowScreen(MainScreen(Profile, skip_start))
		end
		TheNet:EndGame()
		TheNet:ResetCachedHostState()
	elseif settings.reset_action == RESET_ACTION.JOIN_GAME and not TheNet:IsInGame() then
		TheLog.ch.Networking:print("Reconnecting to the game")
		LoadAssets("FRONTEND")	-- Need to load these assets before reconnecting, otherwise the reconnect will fail.

		if settings.reconnect_settings.joincode then
			TheNet:StartGame(settings.reconnect_settings.playerInputIDs, "invitejoincode", settings.reconnect_settings.joincode)
		elseif settings.reconnect_settings.lobbyID then
			TheNet:StartGame(settings.reconnect_settings.playerInputIDs, "invite", settings.reconnect_settings.lobbyID)
		else
			TheLog.ch.Networking:print("No reconnection data! Moving to main menu instead.")
			if MainScreen then
				local skip_start = not RUN_GLOBAL_INIT
				TheFrontEnd:ShowScreen(MainScreen(Profile, skip_start))
			end
		end
	else
		LoadWorld(settings)
	end
end

local function OnFilesLoaded()
	TheLog.ch.Boot:print("OnFilesLoaded()")

	if TheInput:HasAnyConnectedGamepads() then
		TheFrontEnd:StopTrackingMouse()
	end

	DoResetAction()
end

-- Needed to defer graphics loading until that system was init.
TheGameContent:LoadLanguageDisplayElements()

-- Not sure where to put these, so I'm dumping them into a new global.
TheNetUtils = {}
TheNetUtils.ProfanityFilter = ProfanityFilter()

TheNetUtils.ProfanityFilter:AddDictionary("default", require("wordfilter"))

TheLog.ch.SaveLoad:print("[Loading profile and save index]")
Profile:Load(OnFilesLoaded) -- this causes a chain of continuations in sequence that eventually result in DoResetAction being called

require "platformpostload"
