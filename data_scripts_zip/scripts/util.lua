local iterator = require "util.iterator"
require "class"
require "mathutil"
require "util.tableutil"
local lume = require "util.lume"


function DumpTableXML(t, name)
	name = name or ""
	function dumpinternal(t, outstr, indent)
		for key, value in pairs(t) do
			if type(value) == "table" then
				table.insert(outstr,indent.."<table name='"..tostring(key).."'>\n")
				dumpinternal(value, outstr, indent.."\t")
				table.insert(outstr, indent.."</table>\n")
			else
				table.insert(outstr, indent.."<"..type(value).." name='"..tostring(key).."' val='"..tostring(value).."'/>\n")
			end
		end
	end
	outstr = {"<table name='"..name.."'>\n"}
	dumpinternal(t, outstr, "\t")
	table.insert(outstr, "</table>")
	return table.concat(outstr)
end

function DebugSpawn(prefab, options)
	options = options or {}
	if TheSim ~= nil and TheInput ~= nil then
		TheSim:LoadPrefabs({ prefab })
		if PrefabExists(prefab) then
			local inst = SpawnPrefab(prefab, TheDebugSource)
			if inst ~= nil then
				if not options.skipmove then
					local worldPos = ConsoleWorldPosition()
					local x, z
					if worldPos then
						x, z = worldPos:GetXZ()
					else
						x = 0
						z = 0
					end

					if inst.components.snaptogrid ~= nil then
						inst.components.snaptogrid:SetNearestGridPos(x, 0, z, false)
					else
						inst.Transform:SetPosition(x, 0, z)
					end
				end
				inst:AddTag("created_by_debugspawn")
				inst:PushEvent("created_by_debugspawn")
				return inst
			end
		end
	end
end

function GetClosest(target, entities)
	local max_dist = nil
	local min_dist = nil

	local closest = nil

	local tpos = target:GetPosition()

	for k,v in pairs(entities) do
		local epos = v:GetPosition()
		local dist = tpos:DistSq(epos)

		if not max_dist or dist > max_dist then
			max_dist = dist
		end

		if not min_dist or dist < min_dist then
			min_dist = dist
			closest = v
		end
	end

	return closest
end

function GetClosestEntityToXZByTag(x, z, range, tags, isalive)
	--returns player, distsq
	local ents = TheSim:FindEntitiesXZ(x, z, range, nil, {"INLIMBO"}, tags)
	local closest
	local closest_sqdist
	for i, ent in ipairs(ents) do
		if (isalive == nil or isalive == ent:IsAlive()) then
			local distsq = ent:GetDistanceSqToXZ(x, z)
			if closest_sqdist == nil or distsq < closest_sqdist then
				closest_sqdist = distsq
				closest = ent
			end
		end
	end

	return closest, closest ~= nil and closest_sqdist or nil
end

--[[
-- Unused and doens't pass originator to SpawnPrefab. Seems overcomplicated.
function SpawnAt(prefab, loc, scale, offset)
	offset = ToVector3(offset) or Vector3(0,0,0)

	if not loc or not prefab then return end

	prefab = (prefab.GUID and prefab.prefab) or prefab

	local spawn = SpawnPrefab(prefab)
	local pos = nil

	if loc.prefab then
		pos = loc:GetPosition()
	else
		pos = loc
	end

	if spawn and pos then
		pos = pos + offset
		spawn.Transform:SetPosition(pos:Get())
		if scale then
			scale = ToVector3(scale)
			spawn.Transform:SetScale(scale:Get())
		end
		return spawn
	end
end
--]]

local memoizedFilePaths = {}

-- look in package loaders to find the file from the root directories
-- this will look first in the mods and then in the data directory
function resolvefilepath( filepath, force_path_search )
	if memoizedFilePaths[filepath] then
		return memoizedFilePaths[filepath]
	end
	local resolved = softresolvefilepath(filepath, force_path_search)
	assert(resolved ~= nil, "Could not find an asset matching "..filepath.." in any of the search paths.")
	memoizedFilePaths[filepath] = resolved
	return resolved
end

function softresolvefilepath(filepath, force_path_search)
	force_path_search = force_path_search or false

	if Platform.IsConsole() and not force_path_search then
		return filepath -- it's already absolute, so just send it back
	end

	-- on PC platforms, search all the possible paths

	-- mod folders don't have "data" in them, so we strip that off if necessary. It will
	-- be added back on as one of the search paths.
	local filepath = string.gsub(filepath, "^/", "")

	local searchpaths = package.path
	-- mods may use package.path to insert themselves into the search path
	for path in string.gmatch(searchpaths, "([^;]+)") do
		local filename = string.gsub(path, "scripts\\%?%.lua", filepath) -- why is this not string.gsub(path, "%?", modulepath) like in worldgen_main.lua?!?
		filename = string.gsub(filename, "\\", "/")
		--print("looking for: "..filename.." ("..filepath..")")
		if not kleifileexists or kleifileexists(filename) then
			--print("found it! "..filename)
			return filename
		end
	end
	-- as a last resort see if the file is an already correct path (incase this asset has already been processed)
	if not kleifileexists or kleifileexists(filepath) then
		--print("found it in it's actual path! "..filepath)
		return filepath
	end

	return nil
end


if kleifileexists == nil then
	-- No kleifileexists inside updateprefabs.
	function kleifileexists(filepath)
		local f = io.open("data/".. filepath, "r")
		if f == nil then
			return false
		end
		io.close(f)
		return true
	end
end

-- like kleifileexists but using a require() path. Useful for editor code.
function kleimoduleexists(require_path)
	return kleifileexists("scripts/".. require_path:gsub("%.", "/") ..".lua")
end

-------------------------MEMREPORT

local global_type_table = nil

local function type_name(o)
	if global_type_table == nil then
		global_type_table = {}
		for k,v in pairs(_G) do
			global_type_table[v] = k
		end
		global_type_table[0] = "table"
	end
	local mt = getmetatable(o)
	if mt then
		return global_type_table[mt] or "table"
	else
		return type(o) --"Unknown"
	end
end


local function count_all(f)
	local seen = {}
	local count_table
	count_table = function(t)
		if seen[t] then return end
		f(t)
		seen[t] = true
		for k,v in pairs(t) do
			if type(v) == "table" then
				count_table(v)
			else
				f(v)
			end
		end
	end
	count_table(_G)
end

local function type_count()
	local counts = {}
	local enumerate = function (o)
		local t = type_name(o)
		counts[t] = (counts[t] or 0) + 1
	end
	count_all(enumerate)
	return counts
end

function mem_report()
	local tmp = {}

	for k,v in pairs(type_count()) do
		table.insert(tmp, {num=v, name=k})
	end
	table.sort(tmp, function(a,b) return a.num > b.num end)
	local tmp2 = {"MEM REPORT:\n"}
	for k,v in ipairs(tmp) do
		table.insert(tmp2, tostring(v.num).."\t"..tostring(v.name))
	end

	print (table.concat(tmp2,"\n"))
end

-------------------------MEMREPORT





local function dict_from_keys(t, keys)
	local dict = {}
	for _,k in ipairs(keys) do
		dict[k] = t[k]
	end
	return dict
end

local limited_env = {
	-- Add *very safe* functions here that cannot access disk to support basic logic.
	-- Do not include dofile, load, io, os, or other "dangerous" tables/functions.

	coroutine = shallowcopy(coroutine),
	deepcopy = deepcopy,
	ipairs = ipairs,
	math = shallowcopy(math),
	next = next,
	pairs = pairs,
	pcall = pcall,
	print = print,
	shallowcopy = shallowcopy,
	string = shallowcopy(string),
	tonumber = tonumber,
	tostring = tostring,
	type = type,

	table = dict_from_keys(table, {
			"appendarrays",
			"clear",
			"contains",
			"find",
			"getkeys",
			"insert",
			"invert",
			"numkeys",
			"remove",
			"sort",
		}),
}


--- @param fn function An untrusted function.
--- @param fnenv table An execution environment for the function. The function
---   cannot access any globals unless defined in this table (replaces _G).
function RunInEnvironment(fn, fnenv)
	setfenv(fn, fnenv)
	return xpcall(fn, debug.traceback)
end

--- @param fn function An untrusted function.
function RunInEnvironment_Limited(fn)
	return RunInEnvironment(fn, limited_env)
end

--- RunInEnvironment_Safe uses an empty environment for loading lua data. (Like
--- json: data but no logic. Can't even use ipairs.) Useful with kleiloadlua,
--- but otherwise use RunInSandbox_Safe.
---
--- @param fn function An untrusted function that only defines data.
function RunInEnvironment_Safe(fn)
	return RunInEnvironment(fn, {})
end

function RunInEnvironment_Verbose(fn, fnenv)
	setfenv(fn, fnenv)
	return xpcall(fn, function(msg)
		print(msg)
		StackTraceToLog()
		print(debugstack())
		return ""
	end)
end

--- Run code with limited access to external code.
---
--- Use to load untrusted files as code.
---
--- @param untrusted_code string Lua code in a string.
function RunInSandbox_Limited(untrusted_code)
	if untrusted_code:byte(1) == 27 then
		return nil, "binary bytecode prohibited"
	end
	local textonly = "t"
	local untrusted_function, message = load(untrusted_code, "RunInSandbox_Limited", textonly, limited_env)
	if not untrusted_function then
		return nil, message
	end
	return RunInEnvironment(untrusted_function, limited_env)
end

--- RunInSandbox_Safe uses an empty environment for loading lua data. (Like
--- json: data but no logic. Can't even use ipairs.)
---
--- By default this function does not assert, but if you wish to run in a safe
--- sandbox, with normal assertions:
---   RunInSandbox_Safe( untrusted_code, debug.traceback )
---
--- @param untrusted_code string Lua code describing some data as a string.
--- @param error_handler function|nil Function to call on error.
function RunInSandbox_Safe(untrusted_code, error_handler)
	if untrusted_code:byte(1) == 27 then
		return nil, "binary bytecode prohibited"
	end
	local env = {}
	local textonly = "t"
	local untrusted_function, message = load(untrusted_code, "RunInSandbox_Safe", textonly, env)
	if not untrusted_function then
		return nil, message
	end
	setfenv(untrusted_function, env)
	return xpcall(untrusted_function, error_handler or function() end)
end


-- A function call wrapper so we can get extra data about any tracked_asserts
-- that fail in the input function.
-- Not entirely sure why it's useful, especially since we have crash tracking.
function TrackedAssert(tracking_data, function_ptr, function_data)
	--print("TrackedAssert", tracking_data, function_ptr, function_data)
	_G['tracked_assert'] = function(pass, reason)
		--print("Tracked:Assert", tracking_data, pass, reason)
		assert(pass, tracking_data.." --> "..reason)
	end

	local result = function_ptr( function_data )

	_G['tracked_assert'] = _G.assert

	return result
end

-- See also inspect.lua, serpent.lua, and lualib/luaserializer.h
function fastdump(value)
	local tostring = tostring
	local string = string
	local table = table
	local items = {"return "}
	local type = type

	local function printtable(in_table)
		table.insert(items, "{")

		for k,v in pairs(in_table) do
			local t = type(v)
			local comma = true
			if type(k) == "number" then
				if t == "number" then
					table.insert(items, string.format("%s", tostring(v)))
				elseif t == "string" then
					table.insert(items, string.format("[%q]", v))
				elseif t == "boolean" then
					table.insert(items, string.format("%s", tostring(v)))
				elseif type(v) == "table" then
					printtable(v)
				end
			elseif type(k) == "string" then
				local key = tostring(k)
				if t == "number" then
					table.insert(items, string.format("%s=%s", key, tostring(v)))
				elseif t == "string" then
					table.insert(items, string.format("%s=%q", key, v))
				elseif t == "boolean" then
					table.insert(items, string.format("%s=%s", key, tostring(v)))
				elseif type(v) == "table" then
					if next(v) then
						table.insert(items, string.format("%s=", key))
						printtable(v)
					else
						comma = false
					end
				end
			else
				assert(false, "trying to save invalid data type")
			end
			if comma and next(in_table, k) then
				table.insert(items, ",")
			end
		end

		table.insert(items, "}")
		collectgarbage("step")
	end
	printtable(value)
	return table.concat(items)
end

--[[ Data Structures --]]

-----------------------------------------------------------------
-- Class RingBuffer (circular array)

RingBuffer = Class(function(self, maxlen)
	if type(maxlen) ~= "number" or maxlen < 1 then
		maxlen = 10
	end
	self.buffer = {}
	self.maxlen = maxlen or 10
	self.entries = 0
	self.writecount = 0
	self.pos = #self.buffer
end)

function RingBuffer:Clear()
	self.buffer = {}
	self.entries = 0
	self.writecount = 0
	self.pos = #self.buffer
end

function RingBuffer:GetWriteCount()
	return self.writecount
end

-- Add an element to the circular buffer
function RingBuffer:Add(entry)
	local indx = self.pos % self.maxlen + 1

	self.entries = self.entries + 1
	if self.entries > self.maxlen then
		self.entries = self.maxlen
	end
	self.buffer[indx] = entry
	self.writecount = self.writecount + 1
	self.pos = indx
end

-- Access from start of circular buffer
function RingBuffer:Get(index)

	if index > self.maxlen or index > self.entries or index < 1 then
		return nil
	end

	local pos = (self.pos-self.entries) + index
	if pos < 1 then
		pos = pos + self.entries
	end

	return self.buffer[pos]
end

-- Get most recent item
function RingBuffer:Head()
	return self:Get(self.entries)
end

-- Get oldest item
function RingBuffer:Tail()
	return self:Get(1)
end

function RingBuffer:GetBuffer()
	local t = {}
	for i=1, self.entries do
		t[#t+1] = self:GetElementAt(i)
	end
	return t
end

function RingBuffer:Resize(newsize)
	if type(newsize) ~= "number" or newsize < 1 then
		newsize = 1
	end

	-- not dealing with making the buffer smaller
	local nb = self:GetBuffer()

	self.buffer = nb
	self.maxlen = newsize
	self.entries = #nb
	self.pos = #nb

end

------------------------------
-- Class DynamicPosition (a position that is relative to a moveable platform)
-- DynamicPosition is for handling a point in the world that should follow a moving walkable_platform.
-- pt is in world space, walkable_platform is optional, if nil, the constructor will search for a platform at pt.
-- GetPosition() will return nil if a platform was being tracked but no longer exists.
DynamicPosition = Class(function(self, pt, walkable_platform)
	if pt ~= nil then
		self.walkable_platform = walkable_platform or TheWorld.Map:GetPlatformAtPoint(pt.x, pt.z)
		if self.walkable_platform ~= nil then
			self.local_pt = pt - self.walkable_platform:GetPosition()
		else
			self.local_pt = pt
		end
	end
end)

function DynamicPosition:__eq( rhs )
	return self.walkable_platform == rhs.walkable_platform and self.local_pt.x == rhs.local_pt.x and self.local_pt.z == rhs.local_pt.z
end

function DynamicPosition:__tostring()
	local pt = self:GetPosition()
	return pt ~= nil
	and string.format("%2.2f, %2.2f on %s", pt.x, pt.z, tostring(self.walkable_platform))
	or "nil"
end

function DynamicPosition:GetPosition()
	if self.walkable_platform ~= nil then
		if self.walkable_platform:IsValid() then
			local x, y, z = self.walkable_platform.Transform:GetWorldPosition()
			return Vector3(x + self.local_pt.x, y + self.local_pt.y, z + self.local_pt.z)
		else
			self.walkable_platform = nil
			self.local_pt = nil
		end
	elseif self.local_pt ~= nil then
		return self.local_pt
	end
	return nil
end

-----------------------------------------------------------------
-- Class LinkedList (singly linked)
-- Get elements using the iterator

LinkedList = Class(function(self)
	self._head = nil
	self._tail = nil
end)

function LinkedList:Append(v)
	local elem = {data=v}
	if self._head == nil and self._tail == nil then
		self._head = elem
		self._tail = elem
	else
		elem._prev = self._tail
		self._tail._next = elem
		self._tail = elem
	end

	return v
end

function LinkedList:Remove(v)
	local current = self._head
	while current ~= nil do
		if current.data == v then
			if current._prev ~= nil then
				current._prev._next = current._next
			else
				self._head = current._next
			end

			if current._next ~= nil then
				current._next._prev = current._prev
			else
				self._tail = current._prev
			end
			return true
		end

		current = current._next
	end

	return false
end

function LinkedList:Head()
	return self._head and self._head.data or nil
end

function LinkedList:Tail()
	return self._tail and self._tail.data or nil
end

function LinkedList:Clear()
	self._head = nil
	self._tail = nil
end

function LinkedList:Count()
	local count = 0
	local it = self:Iterator()
	while it:Next() ~= nil do
		count = count + 1
	end
	return count
end

function LinkedList:Iterator()
	return {
		_list = self,
		_current = nil,
		Current = function(it)
			return it._current and it._current.data or nil
		end,
		RemoveCurrent = function(it)
			-- use to snip out the current element during iteration

			if it._current._prev == nil and it._current._next == nil then
				-- empty the list!
				it._list:Clear()
				return
			end

			local count = it._list:Count()

			if it._current._prev ~= nil then
				it._current._prev._next = it._current._next
			else
				assert(it._list._head == it._current)
				it._list._head = it._current._next
			end

			if it._current._next ~= nil then
				it._current._next._prev = it._current._prev
			else
				assert(it._list._tail == it._current)
				it._list._tail = it._current._prev
			end

			assert(count-1 == it._list:Count())

			-- NOTE! "current" is now not part of the list, but its _next and _prev still work for iterating off of it.
		end,
		Next = function(it)
			if it._current == nil then
				it._current = it._list._head
			else
				it._current = it._current._next
			end
			return it:Current()
		end,
	}
end

function TrackMem()
	collectgarbage()
	collectgarbage("stop")
	TheSim:SetMemoryTracking(true)
end

function DumpMem()
	TheSim:DumpMemoryStats()
	mem_report()
	collectgarbage("restart")
	TheSim:SetMemoryTracking(false)
end

function checkbit(x, b)
	return x % (b + b) >= b
end

--utf8substr(str, start, end)
--start: 1-based start position (can be negative to count from end)
--end: 1-based end position (optional, can be negative to count from end)
--returns a new string
string.utf8char = utf8char
string.utf8sub = utf8substr
string.utf8len = utf8strlen
string.utf8upper = utf8strtoupper
string.utf8lower = utf8strtolower

--Zachary: add a lua 5.2 feature, metatables for pairs ipairs and next
function metanext(t, k, ...)
	local m = debug.getmetatable(t)
	local n = m and m.__next or next
	return n(t, k, ...)
end

function metapairs(t, ...)
	local m = debug.getmetatable(t)
	local p = m and m.__pairs or pairs
	return p(t, ...)
end

function metaipairs(t, ...)
	local m = debug.getmetatable(t)
	local i = m and m.__ipairs or ipairs
	return i(t, ...)
end

function MetaClass(entries, ctor, classtable)
	local classtable = classtable or {}
	classtable._ = entries or {}
	local defaulttableops = {
		_ctor = function(self)
			if ctor then
				ctor(classtable._)
			end
		end,
		--replaces index behavior obj[key] or obj.key
		__index = function(t, k)
			return classtable._[k] or classtable[k]
		end,
		--replaces setting behavior obj[key] = value
		__newindex = function(t, k, v)
			classtable._[k] = v
		end,
		--replaces #obj behavior (length of table)
		__len = function(t)
			return #classtable._
		end,
		--replaces next
		__next = function(t, k)
			return next(classtable._, k)
		end,
		--replaces pairs
		__pairs = function(t)
			return pairs(classtable._)
		end,
		--replaces ipairs
		__ipairs = function(t)
			return ipairs(classtable._)
		end,
	}
	--newproxy is the only way to use the __len and __gc(garbage collection) meta methods
	local mtclass = newproxy(true)
	debug.setmetatable(mtclass, classtable)
	for k, v in pairs(defaulttableops) do
		if not classtable[k] then
			classtable[k] = v
		end
	end
	mtclass:_ctor()
	return mtclass
end

-- setfenv and getfenv for lua 5.2 and up
-- taken from https://leafo.net/guides/setfenv-in-lua52-and-above.html
function setfenv(fn, env)
	local i = 1
	while true do
		local name = debug.getupvalue(fn, i)
		if name == "_ENV" then
			debug.upvaluejoin(fn, i, (function()
				return env
			end), 1)
			break
		elseif not name then
			break
		end

		i = i + 1
	end

	return fn
end

function getfenv(fn)
	local i = 1
	while true do
		local name, val = debug.getupvalue(fn, i)
		if name == "_ENV" then
			return val
		elseif not name then
			break
		end
		i = i + 1
	end
end

------------------------------------------------------------- GL ----------------------------------------------------------------

function SetFormattedText( textnode, str, player )
	str = tostring(str)
	if textnode then
		textnode:ClearMarkup()
	end
	str = ApplyFormatting( textnode, str, player )
	if textnode then
		textnode:SetString( str )
	end

	return str
end

local function ParseFormattingColour( attr )
	local jj, kk, subattr, clrattr = attr:find( "^(.*)#(.+)$" )
	if clrattr then
		if clrattr == "0" then
			-- special case, we don't want this to be expanded to 0fffffff
			return 0
		elseif tonumber( clrattr, 16 ) then
			while #clrattr < 8 do clrattr = clrattr .. "f" end
			return tonumber( clrattr, 16 )
		elseif UICOLORS[ clrattr ] then
			return RGBToHex(UICOLORS[clrattr])
		end
	end
end


-- Convert a pad width into the padding string.
local function EvaluateNbspPad(pad_char_count)
	if pad_char_count then
		pad_char_count = math.floor(pad_char_count)
		local nbsp = "\u{00a0}"
		return nbsp:rep(pad_char_count)
	end
	return ""
end

-- <p img='images/ui_ftf_shop/displayvalue_up.tex' color=BONUS>
-- <p img='images/ui_ftf_shop/displayvalue_up.tex' color=40AB38 scale=1.2 rpad=1 just_device='gamepad'>
local function ParseImageInformation( attr )
	local lowerattr = string.lower(attr)
	local img = string.match(lowerattr, [[img=['’]([^'’]+)]])
	local scale = string.match(lowerattr, [[scale=([%d.]+)]])
	local rotation = string.match(lowerattr, [[rotation=(-?[%d.]+)]])
	local rpad = string.match(lowerattr, [[rpad=([%d.]+)]])
	rpad = EvaluateNbspPad(rpad)
	local just_device = string.match(lowerattr, [[just_device=['’]([^'’]+)]])
	local colortag = string.match(attr, [[color=([(%w_).]+)]])
	local color = nil
	if colortag then
		color = ParseFormattingColour( "#"..colortag )
	end
	return img, scale, color, rotation, rpad, just_device
end

local function ParseFontScale( attr )
	local scale = tonumber(attr)
	return scale
end

function ApplyFormatting( textnode, str, player )
	local loc = LOC.GetActiveLocalization()
	local can_italic = not loc or loc.can_display_italic
	local can_bold   = not loc or loc.can_display_bold
	-- TODO(ui): Pass user instead of player so it works in main menu (text.lua too).
	local playercontroller = player and player.components.playercontroller
	textnode:ClearMarkup()
	local j, k, sel, attr
	local spans = {}
	local findstartpos = 1
	repeat
		-- find colourization.
		j, k, sel, attr = str:find( "<([#!bBcCsSiIuUpPzZ/]?)([^>]*)>", findstartpos )
		if j then
			local validmarkup = false
			if sel == '/' then
				-- Close the last span
				local attr = table.remove( spans )
				local sel = table.remove( spans )
				local start_idx = table.remove( spans )
				local end_idx = j - 1
				if textnode then

					local pre_segment = str:sub(1, start_idx)
					local utf8_start_idx = string.utf8len(pre_segment)
					local segment = str:sub(1, end_idx)
					local utf8_end_idx = string.utf8len(segment)

					if sel == "b" then
						validmarkup = true
						if can_bold then
							textnode:AddMarkup( utf8_start_idx, utf8_end_idx, MARKUP_BOLD )
						end
						-- else: language doesn't support bold, but still consume the markup.
					elseif sel == "i" then
						validmarkup = true
						if can_italic then
							textnode:AddMarkup( utf8_start_idx, utf8_end_idx, MARKUP_ITALIC )
						end
						-- else: language doesn't support italic, but still consume the markup.
					elseif sel == "u" then
						validmarkup = true
						local clr = ParseFormattingColour( attr )
						textnode:AddMarkup( utf8_start_idx, utf8_end_idx, MARKUP_UNDERLINE, clr )
					elseif sel == "s" then
						validmarkup = true
						textnode:AddMarkup( start_idx, end_idx, MARKUP_SHADOW )
					elseif sel == "z" then
						validmarkup = true
						local size = ParseFontScale(attr)
						textnode:AddMarkup( start_idx, end_idx, MARKUP_TEXTSIZE, size)
					elseif sel == '#' then
						validmarkup = true
						local clr = ParseFormattingColour( sel..attr )
						textnode:AddMarkup( utf8_start_idx, utf8_end_idx, MARKUP_COLOR, clr)
					elseif sel == '!' and attr then
						validmarkup = true
						local clr = ParseFormattingColour( attr )
						local hascolor = attr:find("#")
						attr = attr:sub(1,hascolor and hascolor-1)
						textnode:AddMarkup( utf8_start_idx, utf8_end_idx, MARKUP_LINK, attr, clr )
					elseif sel == '' then
						--just suppressing definitions
					elseif sel ~= nil then
						print( "Closing unknown text markup code", tostring(sel), debug.traceback(), str )
					end
				end
			elseif sel == "p" then
				-- p (picture) doesn't need a </> to close the span, it just inserts
				-- example options:
				-- <p img=folder/image.tex scale=1.0 rpad=1>
				-- <p bind='Controls.Digital.MENU_UNCOMMON' scale=1.0 rpad=1 just_device='gamepad'>
				local img, scale, color, rotation, rpad, just_device = ParseImageInformation( attr )
				local bind = string.match(attr, [[bind=['’]([^'’]+)]]) -- case sensitive
				if bind then
					-- GetDeviceType never returns mouse: use keyboard, but mostly this is for gamepad.
					local player_device = playercontroller and playercontroller:GetDeviceType()
					if not just_device or just_device == player_device then
						img = playercontroller and playercontroller:GetTexForControlName(bind, player)
						img = img or TheInput:GetTexForControlName(bind)
					else
						-- Doesn't match required device, so show no button hint.
						img = nil
					end
					-- If we don't have a bound control, show nothing. Thus it's valid.
					validmarkup = true
				end
				if img then
					validmarkup = true
					local start_idx = j - 1

					local pre_segment = str:sub(1, start_idx)
					local utf8_start_idx = string.utf8len(pre_segment)

					if textnode then
						--~ print("img:",img)
						--~ print("scale:",scale)
						--~ print("color:",color)
						textnode:AddMarkup( utf8_start_idx, utf8_start_idx, MARKUP_IMAGE, img, scale, rotation, color )
					end

					-- also insert a '\a' character into the string, so that the bitmap font renderer knows to render an image:
					-- (insert it AFTER the <blah> tag, so that it remains in the string after the tag is removed
					str = str:sub( 1, k ) .. '\a' .. rpad .. str:sub( k + 1 )
				end
			elseif sel == "c" then
				-- prefer <p bind='Controls.Digital.MENU_ACCEPT'> to show buttons.
				-- <c> allows you to force a specific gamepad button.
				-- replace <c img='r' scale=1.0>
				local img, scale, color, rotation, rpad = ParseImageInformation( attr )
				local img_path = playercontroller and playercontroller:GetInputImageAtlas()
				if not img_path then
					local device_id = 1
					img_path = TheInput:GetDeviceImageAtlas("gamepad", device_id)
				end
				if img then
					if img_path then
						validmarkup = true
						img_path = string.format("images/%s/%s.tex",img_path,img)

						local start_idx = j - 1

						local pre_segment = str:sub(1, start_idx)
						local utf8_start_idx = string.utf8len(pre_segment)


						if textnode then
							textnode:AddMarkup( utf8_start_idx, utf8_start_idx, MARKUP_IMAGE, img_path, scale, rotation, color )
						end

						-- also insert a '\a' character into the string, so that the bitmap font renderer knows to render an image:
						-- (insert it AFTER the <blah> tag, so that it remains in the string after the tag is removed
						str = str:sub( 1, k ) .. '\a' .. rpad .. str:sub( k + 1 )
					end
				end
			else
				sel = sel:lower()
				if (sel == "b") and attr=="" then
					validmarkup = true
				elseif (sel == "i") and attr=="" then
					validmarkup = true
				elseif (sel == "u") then
					-- either no colour at all or a valid color
					if attr == "" or ParseFormattingColour( attr ) then
						validmarkup = true
					end
				elseif (sel == "s") and attr=="" then
					validmarkup = true
				elseif (sel == "#") and ParseFormattingColour( sel..attr ) then
					validmarkup = true
				elseif (sel == "!") and attr then
					validmarkup = true
				elseif (sel == "z") and attr then
					validmarkup = true
				end

				if validmarkup then
					table.insert( spans, j - 1 )
					table.insert( spans, sel )
					table.insert( spans, attr )
				end
			end

			-- remove the <blah> tag from the string:
			if validmarkup then
				str = str:sub( 1, j - 1 ) .. str:sub( k + 1 )
			else
				findstartpos = j + 1
			end
		end
	until not j
	return str
end

function OBSOLETE(old,new)
	if SHOW_OBSOLETE then
		print(string.format("*** OBSOLETE *** %s is obsolete - please use %s instead", old, new))
		print(debugstack())
	end
end

-- TODO(dbriscoe): Remove and replace with enum.lua.
-- It has names, ids, ordered iteration, and Contains.
local _ENUM_META =
{
	__index = function( t, k ) error( "BAD ENUM ACCESS: "..tostring(k) ) end,
	__newindex = function( t, k, v ) error( "BAD ENUM ACCESS "..tostring(k) ) end,
}
-- Enum where strings map to themselves
-- x = MakeEnum{ "duck", "frog", }
-- x.duck == "duck"
function MakeEnum(args) ------ Try enum.lua instead!
	local enum = {}
	for k,v in ipairs(args) do
		assert(type(v) == "string", "Enums come from strings")
		enum[v] = v
	end
	setmetatable( enum, _ENUM_META )
	return enum
end


function CheckAnyBits( bitfield, flags )
	return bitfield & flags ~= 0
end

function CheckBits( bitfield, flags )
	return bitfield & flags == flags
end

function SetBits( bitfield, flags )
	return bitfield | flags
end

function ClearBits( bitfield, flags )
	return bitfield & ~flags
end

function ToggleBits( bitfield, flags )
	return bitfield ~ flags
end

-- taken from DST
--START--
function rawstring( t )
	if type(t) == "table" then
		local mt = getmetatable( t )
		if mt then
			-- Seriously, is there any better way to bypass the tostring metamethod?
			setmetatable( t, nil )
			local s = tostring( t )
			setmetatable( t, mt )
			return s
		end
	end

	return tostring(t)
end

function generic_error( err )
	return tostring(err).."\n"..debugstack()
end

function viewdetails()
	local variables = {}
	local a = 1

	while true do
		local name, value = debug.getlocal(2, a)
		if not name then break end
		variables[name] = value
		a = a + 1
	end

	d_view(variables)
end

function dumpdetails()
	local info = debug.getinfo(2)
	print(info.name)
	local a = 1
	while true do
		local name, value = debug.getlocal(2, a)
		if not name then break end
		printf("> [%s]: %s", name, value)
		a = a + 1
	end
end

function printf(s,...)
	local test_var = select('#', ...)
	if not test_var then
		print(s)
	else
		print(s:format(...))
	end
end

function printf_world(inst, s, ...)

	if not TheDungeon.HUD then return end

	s = s or "NO STRING"

	if type(s) ~= "string" then
		s = tostring(s)
	end

	local test_var = select('#', ...)
	if test_var then
		s = s:format(...)
	end

	TheDungeon.HUD:MakePopText({ target = inst, button = s, color = UICOLORS.KONJUR, size = 66, fade_time = 2 })

	print(("[printf_world]: %s"):format(s))
end

function trace(...)
	print(debug.traceback(...))
end

-------
-- For handling loading images from texture atlases
function GetAtlasTex(atlas_tex, tex)
	local istex = atlas_tex:find(".tex",1,true)
	local ispng = atlas_tex:find(".png",1,true)
	if istex then
		local index1 = string.find(atlas_tex, "/", 1, true)
		if not index1 then
			return atlas_tex, "", true
		end
		local index2 = string.find(atlas_tex, "/", index1 + 1, true)
		if not index2 then
			return atlas_tex, "", true
		end
		local atlas = atlas_tex:sub(1,index2-1)..".xml"
		tex = atlas_tex:sub(index2+1)
		return atlas,tex,true
	elseif ispng then
		return atlas_tex, "", true
	else
		return atlas_tex, "", false
	end
end

-- Use a table of x,y pairs to define your function:
--  local data = { -- cooldown progress, bloom
--  	{0.0,  1},
--  	{0.25, 0.5},
--  	{0.50, 0.25},
--  	{0.75, 0.15},
--  	{1.0,  0},
--  }
--  bloom = PiecewiseFn(time, data)
-- Input values for x that are between values are linearly interpolated between
-- them.
-- Use ui:DrawPiecewiseFn to visualize.
function PiecewiseFn(x, data_table)
	local p1 = nil
	local p2 = nil
	if x >= data_table[#data_table][1] then -- Higher than max range, so jump straight to the last segment
		p1 = data_table[#data_table-1]
		p2 = data_table[#data_table]
	elseif x <= data_table[1][1] then -- Lower than min range, so jump straight to first segment
		p1 = data_table[1]
		p2 = data_table[2]
	else -- In range, so find within which segment we land
		for i,v in ipairs(data_table) do
			if x == v[1] then
				return v[2] -- If we find any exact matches, just return that and get out
			elseif p1 == nil or x > v[1] then
				p1 = v
			else
				p2 = v
				break
			end
		end
	end
	if p1 and p2 then
		local segment_len = p2[1] - p1[1]
		return lume.lerp(p1[2], p2[2], (x - p1[1]) / segment_len)
	end
end

-- from and to: valid entities
function FakeBeamFX(from, to, fx_name, smalldata, largedata)
	if EntityScript.is_instance(from) and from:IsValid()
		and EntityScript.is_instance(to) and to:IsValid() then
		FakeBeamFXWithPositions(from:GetPosition(), to:GetPosition(), fx_name, smalldata, largedata, from)
	end
end

-- from and to : worldspace positions
-- from_ent : an optional valid entity if network transmission is wanted
function FakeBeamFXWithPositions(from_position, to_position, fx_name, smalldata, largedata, from_ent)
	local delta = to_position - from_position
	local delta_xz = Vector2(delta.x, delta.z)
	local angle = delta_xz:angle_to(Vector2.unit_x)
	angle = math.deg(angle)

	local distsq = DistSq2D(from_position.x, from_position.z, to_position.x, to_position.z)
	local dist = math.sqrt(distsq)

	local suffixed_name = fx_name.."_sml"
	local dataset = smalldata
	if dist >= 15 then
		suffixed_name = fx_name.."_lrg"
		dataset = largedata
	end

	local scale = PiecewiseFn(dist, dataset)

	local mid_pos = (from_position + to_position) / 2

	if from_ent and from_ent:IsValid() then
		local params =
		{
			fxname = suffixed_name,
			orientation = ANIM_ORIENTATION.OnGround,
			scale_applies_to_transform = true,
			offset_is_absolute = true,
			scalex = scale,
			scaley = 1 + scale*0.1,
			scalez = scale,
			rotation = angle,
			offx = mid_pos.x,
			offy = mid_pos.y,
			offz = mid_pos.z,
		}

		local EffectEvents = require "effectevents"
		EffectEvents.MakeEventSpawnEffect(from_ent, params)
	else
		local fx = SpawnPrefab(suffixed_name)
		fx.AnimState:SetOrientation(ANIM_ORIENTATION.OnGround)
		fx.Transform:SetScale(scale, 1 + scale*0.1, scale) -- don't scale Y as heavily as the others, because it begins to look very wide and stretchy
		fx.Transform:SetRotation(angle)
		fx.Transform:SetPosition(mid_pos.x, mid_pos.y, mid_pos.z)
	end
end

function GetEntitySizeSuffix(inst)
	-- use entity's BB size if possible
	local art_size = inst.sg and inst.sg.mem.idle_bb_width
	if art_size then
		local size = lume.round(art_size * 0.5, 0.1)
		if size < 1.4 then
			return "_sml"
		elseif size >= 1.4 and size < 1.8 then
			return "_med"
		else
			return "_lrg"
		end
	end

	--printf("[GetEntitySizeSuffix() Error] %s does not have inst.sg.mem.idle_bb_width set!", inst.prefab)

	-- as a second resort, use how the entity is tagged.
	if inst:HasTag("small") then
		-- printf("GetEntitySizeSuffix %s", "_sml")
		return "_sml"
	elseif inst:HasTag("medium") then
		-- printf("GetEntitySizeSuffix %s", "_med")
		return "_med"
	elseif inst:HasTag("large") then
		-- printf("GetEntitySizeSuffix %s", "_lrg")
		return "_lrg"
	elseif inst:HasTag("giant") then
		return "_gnt"
	end

	--printf("[GetEntitySizeSuffix() Error] %s does not have any size tags!", inst.prefab)

	-- as a last resort, use the entity's physics size
	local size = inst.Physics:GetSize()
	size = lume.round(size, 0.1)
	if size < 1.4 then
		return "_sml"
	elseif size >= 1.4 and size < 1.8 then
		return "_med"
	else
		return "_lrg"
	end
end

-- Given an integer that is the expected maximum of some unsigned integer field, return the minimum number of bits
-- necessary to represent that number.
-- This function's main intent is to compute the bit count for fields over the net.
function RequiredBitCount(number)
    if number == 0 then
        return 1 -- Edge case: 0 can be represented with 1 bit
    end

    return math.floor(math.log(number, 2)) + 1
end


-- Moved profiling code into profiler.lua to be easier to find.


local function test_RunInSandbox()
	local err_handler = debug.traceback
	local data = [[
		return {
			one = "first",
			two = { three = 3, },
		}
	]]
	assert(RunInSandbox_Safe(data, err_handler))
	assert(RunInSandbox_Limited(data))

	local basic = [[
		local t = {}
		for i=1,10 do
			table.insert(t, tostring(i * 2))
		end
		local total = 0
		for i,val in ipairs(t) do
			total = total .. val
		end
		print("test: Hello")
		return total
	]]
	assert(not RunInSandbox_Safe(basic, err_handler))
	assert(RunInSandbox_Limited(basic))

	local illegal = [[
		local t = ""
		for line in io.lines("c:/Windows/system.ini") do
			t = t .. line
		end
		print("test: Read system files:", t)
		return t
	]]
	assert(not RunInSandbox_Limited(illegal))
	assert(not RunInSandbox_Safe(illegal, err_handler))
end

local function test_RunInEnvironment()
	local function basic()
		print("test: Hello")
		local t = {}
		for i=1,10 do
			table.insert(t, tostring(i * 2))
		end
		local total = 0
		for i,val in ipairs(t) do
			total = total .. val
		end
		return total
	end
	assert(RunInEnvironment_Limited(basic))

	local function illegal()
		local t = ""
		for line in io.lines("c:/Windows/system.ini") do
			t = t .. line
		end
		print("test: Read system files:", t)
		return t
	end
	assert(not RunInEnvironment_Limited(illegal))
end
