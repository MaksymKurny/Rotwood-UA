NETFLIX_DEMO_BUILD = false		-- RM - Must be FALSE in TRUNK and TRUE in FromTheForge_mobile

--Override the package.path in luaconf.h because it is impossible to find
package.path = "scripts\\?.lua"

--Override package.loaded metatable so we don't double load packages
--when using different syntax for the path.
setmetatable(package.loaded,
{
	__index = function(t, k)
		k = string.gsub(k, "[\\/]+", ".")
		return rawget(t, k)
	end,
	__newindex = function(t, k, v)
		k = string.gsub(k, "[\\/]+", ".")
		rawset(t, k, v)
	end,
})

-- Improve seeding on platforms where similar seeds produce similar sequences
-- (OSX) by throwing away the high part of time and then reversing the digits
-- so the least significant part makes the biggest change. See
-- http://lua-users.org/wiki/MathLibraryTutorial
math.randomseed(tonumber(tostring(os.time()):reverse():sub(1,6)))
math.random()

Platform = require "util.platform"

--defines
GAMEPLAY_MODS_ENABLED = true
MAIN = 1
IS_QA_BUILD = not not TheSim:GetCurrentBetaBranch():find("huwiz")
DEV_MODE = RELEASE_CHANNEL == "dev" or IS_QA_BUILD -- For now, QA gets debug tools everywhere.
IS_BUILD_STRIPPED = not kleifileexists("scripts/prefabs/__readme.txt")
ENCODE_SAVES = RELEASE_CHANNEL ~= "dev"
CHEATS_ENABLED = DEV_MODE or (Platform.IsConsole() and CONFIGURATION ~= "PRODUCTION")
IS_BETA_TEST = RELEASE_CHANNEL == "preview"
SOUNDDEBUG_ENABLED = false
SOUNDDEBUGUI_ENABLED = false
HITSTUN_VISUALIZER_ENABLED = false
--DEBUG_MENU_ENABLED = true
DEBUG_MENU_ENABLED = DEV_MODE or (Platform.IsConsole() and CONFIGURATION ~= "PRODUCTION") or (Platform.IsMobile() and not NETFLIX_DEMO_BUILD)
METRICS_ENABLED = true
TESTING_NETWORK = 1
AUTOSPAWN_MASTER_SECONDARY = false
DEBUGRENDER_ENABLED = true
SHOWLOG_ENABLED = true
POT_GENERATION = false -- not generating strings.pot for translators
IS_EXPORT_PREFABS = false

-- Networking related configuration
DEFAULT_JOIN_IP				= "127.0.0.1"
DISABLE_MOD_WARNING			= false
DEFAULT_SERVER_SAVE_FILE    = "/server_save"

RELOADING = false
SHOW_OBSOLETE = false

-- In DEV_MODE, we do not update versions but instead require devs to simply
-- erase their save data. This keeps the version updating process simple.
-- Always do version update for mounted saves so we can load player saves
-- in dev builds.
-- Enabling will assert version updating succeeds rather than silently failing.

SAVE_DATA_VERSION_UPDATE_ENABLED = not DEV_MODE or IS_USING_MOUNTED_SAVE
-- You can temporarily set to true to test your version update code.
-- SAVE_DATA_VERSION_UPDATE_ENABLED = true

ExecutingLongUpdate = false

local DEBUGGER_ENABLED = TheSim:ShouldInitDebugger() and Platform.IsNotConsole() and CONFIGURATION ~= "PRODUCTION"
if DEBUGGER_ENABLED then
	Debuggee = require 'debuggee'
end

function export_timer_names_grab_attacks(attacks)
	-- empty
end

TheAudio:SetReverbPreset("default")

RequiredFilesForReload = {}

--install our crazy loader!
local loadfn = function(modulename)
	--print (modulename, package.path)
    local errmsg = ""
    local modulepath = string.gsub(modulename, "%.", "/")
    for path in string.gmatch(package.path, "([^;]+)") do
        local filename = string.gsub(path, "%?", modulepath)
        filename = string.gsub(filename, "\\", "/")
        local result = kleiloadlua(filename)
        if result then
			local filetime = TheSim:GetFileModificationTime(filename)
			RequiredFilesForReload[filename] = filetime
            return result
        end
        errmsg = errmsg.."\n\tno file '"..filename.."' (checked with custom loader)"
    end
  return errmsg
end
table.insert(package.searchers, 2, loadfn)

-- Use our loader for loadfile too.
if TheSim then
    function loadfile(filename)
        filename = string.gsub(filename, ".lua", "")
        filename = string.gsub(filename, "scripts/", "")
        return loadfn(filename)
    end
	-- else, how can TheSim be nil??
end

local strict = require "util.strict"
strict.forbid_undeclared(_G)

require("debugprint")
-- add our print loggers
AddPrintLogger(function(...) TheSim:LuaPrint(...) end)
TheLog = require("util.logchan")()


require("class")
require("util.pool")
require("util.multicallback")
require("util.helpers")
require "debugtools"

TheConfig = require("config").CreateDefaultConfig()

require("vector3")
require("vector2")
require("mainfunctions")

require("mods")
require("json")
TUNING = require("tuning")()
require "entityscript"
local kstring = require "util.kstring"

--monkey-patch in utf8-aware version of the string library.
local utf8_ex = require "lua-utf8"
for k,v in pairs(string) do
    if utf8_ex[k] then
        string[k] = utf8_ex[k]
    end
end

function utf8.sub(s,i,j)
    return utf8_ex.sub(s,i,j)
end

local gamesettings = require "settings.gamesettings"
TheGameSettings = gamesettings.CreateSettingsInstance()
local function LoadGameSettings()
	gamesettings.LoadSettings(TheGameSettings)

	LOC.DetectLanguage()

	TheGameSettings:Save()
end

Profile = require("playerprofile")() --profile needs to be loaded before language
Profile:Load( nil, true ) --true to indicate minimal load required for language.lua to read the profile.

LOC = require "languages.loc"
require "strings.strings"
local GameContent = require "gamecontent"
global "TheGameContent"
TheGameContent = GameContent():Load()

require "constants"

-- For dev, configure your channels from customcommands.lua.
if CONFIGURATION == "PRODUCTION" then
	-- TODO: Should we disable anything in prod? Maybe default is fine.
	--~ TheLog:disable_all()
	--~ TheLog:enable_channel("WorldMap")
	--~ TheLog:disable_channel("FrontEnd")
end



require "simutil"
require "util.colorutil"
require "util"
require "util.kstring" -- defines some methods in string
require "scheduler"
Attack = require "attack"
require "stategraph"
require "behaviortree"
require "prefabs"
require "bosscoroutine"
require "brain"
require "components.hitbox"
require "components.soundemitter"
require "hitstopmanager"
require "input.inputconstants"
require "input.input"
require("stats")
require("commonassets")

--Now let's setup debugging!!!
global "Debuggee"
if Debuggee then
    local startResult, breakerType = Debuggee.start()
    print('Debuggee start ->', startResult, breakerType )
end

serpent = require "util/serpent"
require("frontend")
require("networking")

require("gen.prefablist")
require("netcomponents")	-- Creates dictionaries of hash values to prefabs and components
FindNetComponents()

require("networkstrings")	-- Collects and adds all static strings that need to be sent over the network to a string table and submits it to C++

require("update")
require("fonts")
require("physics")
require("mathutil")
require("reload")
require("worldtiledefs")
--require("skinsutils")

if TheConfig:IsEnabled("force_netbookmode") then
	TheSim:SetNetbookMode(true)
end


print ("running main.lua\n")
print("Lua version: "..LUA_VERSION)

TheSystemService:SetStalling(true)

Prefabs = {}
Ents = {}  -- Numerical keys (guids), but may have holes! Iterate with pairs or iterator.ipairs_with_holes.
KnownModIndex = require("mods.modindex")()  -- can't use it until it's Loaded

local tracker = require "util.tracker"
TheTrackers = tracker.CreateTrackerSet()

TheGlobalInstance = nil
TheDebugSource = CreateEntity("TheDebugSource")
	:MakeSurviveRoomTravel()
TheDebugSource.entity:AddTransform()

global("TheCamera")
TheCamera = nil
global("PostProcessor")
PostProcessor = nil

global("MapLayerManager")
MapLayerManager = nil
global("TheDungeon")
global("TheFrontEnd")
TheFrontEnd = nil
global("TheWorld")
--- @type World|nil
TheWorld = nil
global("TheFocalPoint")
TheFocalPoint = nil
global("ThePlayer")
ThePlayer = nil  --- @type Entity: Debug player set from native.
global("AllPlayers")
-- @type Entity[]
AllPlayers = {}
global("TheDebugAudio")
TheDebugAudio = nil
global("TheMetrics")
TheMetrics = require("util.metrics")()
global("SERVER_TERMINATION_TIMER")
SERVER_TERMINATION_TIMER = -1
global("TheSceneGen")
TheSceneGen = nil
global("UseMapGen2") -- TODO(mg2): remove this eventually
UseMapGen2 = not IS_USING_MOUNTED_SAVE or TheSim:GetMapGenVersion() ~= 1


function GetDebugPlayer()
	local playerID = TheNet:GetLocalDebugPlayer()
	if playerID then
		return GetPlayerEntityFromPlayerID(playerID)
	end
	return nil
end

local function ModSafeStartup(was_savedata_successfully_loaded)

	-- If we failed to boot last time, disable all mods
	-- Otherwise, set a flag file to test for boot success.

	--Ensure we have a fresh filesystem
	--TheSim:ClearFileSystemAliases()

	---PREFABS AND ENTITY INSTANTIATION

	--#V2C no mods for now... deal with this later T_T
	ModManager:LoadMods()

	-- Apply translations
	TheGameContent:SetLanguage()

	-- Register every standard prefab with the engine

    -- global must be active from the get-go.
    local async_batch_validation = RUN_GLOBAL_INIT
    LoadPrefabFile("prefabs/global", async_batch_validation)
	-- Also need player for save slot puppets. It's a dep of global, but
	-- LoadPrefabFile isn't recursive on deps.
	LoadPrefabFile("prefabs/player_assets_global", async_batch_validation)

    local FollowCamera = require("cameras/followcamera")
    TheCamera = FollowCamera()

	--- GLOBAL ENTITY ---
    --[[Non-networked entity]]
    TheGlobalInstance = CreateEntity("TheGlobalInstance")
		:MakeSurviveRoomTravel()
    TheGlobalInstance.entity:AddTransform()
    TheGlobalInstance.persists = false
    TheGlobalInstance:AddTag("CLASSIFIED")

	if RUN_GLOBAL_INIT then
		GlobalInit()
	end

	PostProcessor = TheGlobalInstance.entity:AddPostProcessor()
	local Environment = require "environment"
	Environment.Initialize()

	MapLayerManager = TheGlobalInstance.entity:AddMapLayerManager()

    -- I think we've got everything we need by now...
   	if Platform.IsNotConsole() then
		if TheSim:GetNumLaunches() == 1 then
			TheMetrics:Send_StartGame()
		end
	end

	TheSim:SetUIColorCube("images/color_cubes/mapcc_basic.tex")
end

-- json_instance_params is a global set from cSimulation
ProcessInstanceParameters(json_instance_params)

require "stacktrace"
require "debughelpers"

require "consolecommands"

require "debugsettings"

--debug key init
if CHEATS_ENABLED then
    require "debugcommands"
    require "debugkeys"
end

local function screen_resize(w,h)
	TheFrontEnd:OnScreenResize(w,h)
	TheInput:OnScreenResize(w, h)
end

function Render()
	TheFrontEnd:OnRender()
end

local function key_down_callback(keyid, modifiers)
	TheInput:OnKeyDown(keyid, modifiers);
end

local function key_repeat_callback(keyid, modifiers)
	TheInput:OnKeyRepeat(keyid);
end

local function key_up_callback(keyid, modifiers)
	TheInput:OnKeyUp(keyid, modifiers);
end

local function text_input_callback(text)
	TheInput:OnTextInput(text)
end

--local function text_edit_callback(text)
--    TheGame:GetInput():OnTextEdit(text);
--end

-- Mouse:
local function mouse_move_callback(x, y)
	if not Platform.ShouldIgnoreMouse() then
		TheInput:OnMouseMove(x,y)
	end
end

local function mouse_wheel_callback(wheeldelta)
	TheInput:OnMouseWheel(wheeldelta)
end

local function mouse_button_down_callback(x, y, button)
	if not Platform.ShouldIgnoreMouse() then
		TheInput:OnMouseButtonDown(x,y,button)
	end
end

local function mouse_button_up_callback(x, y, button)
	if not Platform.ShouldIgnoreMouse() then
		TheInput:OnMouseButtonUp(x,y,button)
	end
end

local function GetHoveredWidget(touch_x,touch_y)
	-- Based on FrontEnd:FocusHoveredWidget()
	local x = touch_x
	local y = (TheInput.h or RES_Y) - touch_y
	x,y = TheFrontEnd:WindowToUI(x,y)

	local toucher = TheInput:GetTouchDevice()
	local hunter_id = toucher:GetOwnerId_strict()

	local top = TheFrontEnd:GetActiveScreen()
	if hunter_id
		or (top and top:CanDeviceInteract(toucher))
	then
		local hover_widget = TheFrontEnd:FindMouseHover( x, y )
		if hover_widget then
			if hover_widget:CanDeviceInteract(toucher) then
				return hover_widget
			end
		end
	end
end

local function IsButton(widget)
	local Clickable = require "widgets.clickable"
	local Button = require "widgets.button"
	--print("IsButton",widget)
	while widget do
		--print("====",widget, widget.widget)
		if widget:is_a(Clickable) or widget:is_a(Button) then
			return true
		end
		widget = widget.parent
		print("widget now",widget)
	end
end

local function IsTouchOnButton(touch_x, touch_y)
	local hover = GetHoveredWidget(touch_x, touch_y)
	return hover and IsButton(hover)
end

local function VirtualTouchPadWouldConsume(touch_x, touch_y)
	-- otherwise, only it the virtual joystick wouldn't consume it
	local x = touch_x 
	local y = (TheInput.h or RES_Y) - touch_y 
	local x,y = TheFrontEnd:WindowToUI(x,y)
	local wouldConsumeClick = TheDungeon.HUD.player_touch_hud:WouldConsumeClick(x,y)
	return wouldConsumeClick
end

local function GetVirtualJoyPad()
	if TheDungeon
		and TheDungeon.HUD
		and TheDungeon.HUD.player_touch_hud
		and TheDungeon.HUD.player_touch_hud:IsVisible()
	then
		return TheDungeon.HUD.player_touch_hud
	end
end

local activeScrollRegions = {}

function ActivateTouchRegion(region)
	activeScrollRegions[region] = true
end

function DeactivateTouchRegion(region)
	activeScrollRegions[region] = nil
end

local function ScrollRegionWouldConsumeTouchDown(touch_x, touch_y)
	local x = touch_x
	local y = (TheInput.h or RES_Y) - touch_y
	x,y = TheFrontEnd:WindowToUI(x,y)
	for i,_ in pairs(activeScrollRegions) do
		if i:IsInside(x,y) then
			return true
		end
	end
end

local function ScrollRegionWouldConsumeTouchUp(touch_x, touch_y)
	for i,_ in pairs(activeScrollRegions) do
		if i:IsScrolling() then
			return true
		end
	end
end


local function touch_began_callback(id,x, y)
	if NETFLIX_DEMO_BUILD then 
		local virtualJoyPad = GetVirtualJoyPad()
		if not virtualJoyPad then
			-- does an active touch region need this? If not don't send the touch down, cuz future frames mayu have the virtual pad and it'll promptly
			-- see the touch as down as it polls rather than listening to a touch down event
			if ScrollRegionWouldConsumeTouchDown(x,y) then
				TheInput:OnTouchDown(x,y,id)
			end
			TheInput:OnMouseButtonDown(x,y,0)
		else
			-- if we're on a button don't send the touch-down. The virtual joystick would respond to it
			local onButton = IsTouchOnButton(x,y)
			if not onButton then
				-- Send to virtual joystick
				TheInput:OnTouchDown(x,y,id)
				-- and if the virtual joystick would consume this, don't send a mouse click for this touch
				if not VirtualTouchPadWouldConsume(x,y) then
					TheInput:OnMouseButtonDown(x,y,0)
				end
			else
				TheInput:OnMouseButtonDown(x,y,0)
			end
		end
	end
end

-- touch move and end will be sent even if over a button, so that the joypad can't get stuck
local function touch_move_callback(id, x, y)
	if NETFLIX_DEMO_BUILD then 
		TheInput:OnTouchMove(x,y,id)
	end
	TheInput:OnMouseMove(x,y)
end

local function touch_ended_callback(id,x, y)
	if NETFLIX_DEMO_BUILD then 
		TheInput:OnTouchUp(x,y,id)
		if ScrollRegionWouldConsumeTouchUp(x,y) then
			TheInput:OnMouseButtonUp(10000,10000,0)
		else
			TheInput:OnMouseButtonUp(x,y,0)
		end
	else
		TheInput:OnMouseButtonUp(x,y,0)
	end
end

-- Gamepad:
local function gamepad_connected_callback(gamepad_id, gamepad_name)
	TheInput:OnGamepadConnected(gamepad_id, gamepad_name);
end

local function gamepad_disconnected_callback(gamepad_id)
	TheInput:OnGamepadDisconnected(gamepad_id);
end

local function gamepad_button_down_callback(gamepad_id, button)
	TheInput:OnGamePadButtonDown(gamepad_id, button);
end

local function gamepad_button_repeat_callback(gamepad_id, button)
	TheInput:OnGamePadButtonRepeat(gamepad_id, button);
end

local function gamepad_button_up_callback(gamepad_id, button)
	TheInput:OnGamePadButtonUp(gamepad_id, button);
end

local function gamepad_analog_input_callback(gamepad_id, ls_x, ls_y, rs_x, rs_y, lt, rt)
	TheInput:OnGamepadAnalogInput(gamepad_id, ls_x, ls_y, rs_x, rs_y, lt, rt);
end

local function filedrop(dropped_file)
	if not DEV_MODE then
		print("You must be in dev mode to drop files onto the game. Received:", dropped_file)
		return
	end

	if dropped_file:find("savedata[()_ 0-9]*%.zip$") -- "savedata.zip", "savedata (1).zip", "friendly_tidy_rhino_savedata(1).zip"
	then
		print("Dropped a save zip", dropped_file)
		TheSaveSystem:Debug_MountSave(dropped_file, function()
			d_loadsaveddungeon(true)
		end)

	elseif dropped_file:find("\\replay",1,true) then
		print("Dropped a replay", dropped_file)
		local savestr = TheSim:DevLoadDataFile(dropped_file)
		if savestr then
			local savepath = "SAVEGAME:replay"
			if TheSim:DevSaveDataFile(savepath, savestr) then
				local metadata
				local loadsuccess
				TheSim:GetPersistentString("replay", function(success, data)
					if success and string.len(data) > 0 then
						success, data = RunInSandbox_Safe(data)
						if success and data ~= nil then
							loadsuccess = true
							metadata = data.metadata
							TheLog.ch.SaveLoad:print("Successfully loaded: /"..savepath)
							return
						end
					end
					TheLog.ch.SaveLoad:print("Failed to load: /"..savepath)
				end)

				if loadsuccess then
					local RoomLoader = require "roomloader"
					InstanceParams.dbg = InstanceParams.dbg or {}
					-- InstanceParams.dbg.open_nodes = {'DebugHistory'} -- This doesn't work unfortunately, the history debugger has some assumptions
					InstanceParams.dbg.load_replay = true
					if metadata then
						if metadata.world_is_town then
							RoomLoader.LoadTownLevel(metadata.world_prefab or TOWN_LEVEL)
						else
							RoomLoader.LoadDungeonLevel(metadata.world_prefab, metadata.scenegen_prefab, metadata.room_id, metadata.prev_room_cardinal)
						end
					else
						RoomLoader.LoadTownLevel(TOWN_LEVEL)
					end
				end
			else
				print("Failed to save replay to "..savepath)
			end
		else
			print("Failed to load", dropped_file)
		end
	else
		print("Dropped unrecognized file type", dropped_file)
	end
end

TheFeedbackScreen = nil

function SubmitFeedbackResult(response_code, response)
	print("Feedback result:",response_code)
	print("response:",response)
	if TheFeedbackScreen then
		TheFeedbackScreen:SubmitFeedbackResult(response_code, response)
	end
end

function ProfilingDone()
	TheFrontEnd:DoneProfiling()
	local feedback = require "feedback"
	feedback.StartFeedback(STRINGS.UI.FEEDBACK_SCREEN.ABOUT_PERF_PROFILE)
end

TheScreenshotter = require("util.screenshotter")()

TheSim:SetScreenSizeChangeFn(screen_resize)

-- These Set*Fn() callbacks are defined in native with the LUACALLBACK_INIT macro.

--  Keyboard
TheSim:SetKeyDownFn(key_down_callback);
TheSim:SetKeyRepeatFn(key_repeat_callback);
TheSim:SetKeyUpFn(key_up_callback);
TheSim:SetTextInputFn(text_input_callback);
--TheSim:SetTextEditFn(text_edit_callback);


-- Mouse:
TheSim:SetMouseMoveFn(mouse_move_callback);
TheSim:SetMouseWheelFn(mouse_wheel_callback);
TheSim:SetMouseButtonDownFn(mouse_button_down_callback);
TheSim:SetMouseButtonUpFn(mouse_button_up_callback);

-- Touch:
TheSim:SetTouchBeganFn(touch_began_callback);
TheSim:SetTouchMoveFn(touch_move_callback);
TheSim:SetTouchEndedFn(touch_ended_callback);

-- Gamepad:
TheSim:SetGamepadConnectedFn(gamepad_connected_callback);
TheSim:SetGamepadDisconnectedFn(gamepad_disconnected_callback);
TheSim:SetGamepadButtonDownFn(gamepad_button_down_callback);
TheSim:SetGamepadButtonRepeatFn(gamepad_button_repeat_callback);
TheSim:SetGamepadButtonUpFn(gamepad_button_up_callback);
TheSim:SetGamepadAnalogInputFn(gamepad_analog_input_callback);

TheSim:SetDropFileFn(filedrop);


TheSaveSystem = require("savedata.savesystem")()
LoadGameSettings()

require "prefabs.stategraph_autogen" -- to get around a circular dependency

global("AUTOMATION_SCRIPT")

if MODS_ENABLED then
	KnownModIndex:Load(function()
		KnownModIndex:BeginStartupSequence(function()
			local translation_mod = require "mods.translation_mod"

			KnownModIndex:UpdateModInfo()
			translation_mod.ActivateAllTranslationMods()

			TheSaveSystem:PerformInitialLoad(ModSafeStartup)
		end)
	end)
else
	TheSaveSystem:PerformInitialLoad(ModSafeStartup)
end

TheSystemService:SetStalling(false)

if Platform.IsMobile() then
	TheSim:ConfigDebugRender({
			main_font_size = 70,
			perf_font_size = 70,
			network_font_size = 70,
		})
end


if NETFLIX_DEMO_BUILD then

	local GODMODE_IMAGE

	function RefreshGodMode(player)
		print("KAJ:RefreshGodMode TheWorld",TheWorld,"TheDungeon",TheDungeon)
		local godmode = TheSaveSystem.cheats:GetValue("godmode")
		if godmode then
			local Image = require "widgets/image"
			local icon_image = "images/icons_boss/bandicoot.tex"

			if GODMODE_IMAGE then
				GODMODE_IMAGE:SetTexture(icon_image)
				GODMODE_IMAGE:Show()
			else
				GODMODE_IMAGE = Image(icon_image)
					:SetAnchors("left", "bottom")
					:SetScale(0.5)
					:SetPosition(50, 50)
			end
		else
			if GODMODE_IMAGE then
				GODMODE_IMAGE:Hide()
			end
		end

		if player then
			player.components.combat.godmode = godmode
			if player.components.combat.godmode then
				local damage_mult = 5
				player.components.combat:SetDamageDealtMult("cheat", damage_mult)
				player.components.combat:SetDamageReceivedMult("cheat", 0)
			else
				player.components.combat:RemoveAllDamageMult("cheat")
			end	
		end
	end

	function ToggleGodMode()
		local godmode = TheSaveSystem.cheats:GetValue("godmode")
		print("godmode was",godmode)
		if not godmode then
			TheSaveSystem.cheats:SetValue("godmode", true)				
		else
			TheSaveSystem.cheats:SetValue("godmode", nil)				
		end
		TheSaveSystem.cheats:Save()
		RefreshGodMode(ThePlayer)
	end

end

