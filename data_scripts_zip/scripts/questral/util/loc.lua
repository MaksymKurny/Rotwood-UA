----------------------------------------------------------------
-- Localization functions.

local loc = {}

local kassert = require "util.kassert"
local lume = require "util.lume"
local macros = require "questral.util.locmacros"
local strict = require "util.strict"
require "util.kstring"


for k,v in pairs(macros) do
    loc[k] = v
end

--local utf8_ex = require "lua-utf8"

local LOCALE_ENV =
{
	max_plurality = 2,
}

function loc.getEnv()
	return LOCALE_ENV
end

function loc.setMaxPlurality( n )
	assert( type(n) == "number" )
	LOCALE_ENV.max_plurality = n
end

-- Converts a plurality (integer) to an index.
-- TODO: this can be re-assigned by the locale, through the .pot file.
function loc.convertPlurality( n )
    if type(n) ~= "number" then
        LOGWARN("invalid non-number plurality argument: %s", tostring(n))
        return 1
    end
    if loc.convertPluralityOverride then
        local ok, plurality = pcall( loc.convertPluralityOverride, n )
        if ok and type(plurality) == "number" then
            return plurality
        elseif ok and type(plurality) == "boolean" then
            return plurality == true and 2 or 1
        else
            print( "loc.convertPlurality failed: ", ok, plurality )
        end
    end
    return (n ~= 1 and n ~= -1) and 2 or 1
end



loc.name_replacement_pattern = "^[_a-z0-9]-$"
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

function loc.IsValidStringKey(key)
    return (type(key) == "string"
        or type(key) == "number") -- allow indexed strings for easy lookups
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

-- Replace {name.blah} and {name_plurality.bleh} with values from the input
-- tables. Makes life easier for writers because they don't need to update all
-- references when renaming characters, powers, keywords, etc.
--
-- We call this function on English and translated strings! Localized strings
-- contain {name.blah} to reduce translation overhead, but translators can
-- replace it with the actual name to retain full control over matching gender
-- and plurality.
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
        fns["upper_".. k] = function(key)
            local name = fns[k](key)
            -- TODO: no longer safe to upper because transforms translated strings.
            return name:upper()
        end
    end

    strict.strictify(fns)
    ReplaceNameInTable(string_table, fns, clear_names)
end

-- For use with loc.ReplaceNames.
function loc.BuildPlurality(names, plural)
    -- English only has singular and plural, so we can derive plurality from the two.
	local plurality = {}
	for k,pl in pairs(plural) do
		local singular = names[k]
		assert(singular, "Plural string exists for name but singular does not.")
		plurality[k] = ("%s|%s"):format(singular, pl)
	end
	
    return plurality
end

local function test_ReplaceNameInString()
    local s = {
        bandi_gloves = "Made from {name.bandicoot} fur.",
        yammo_lore = "{name_multiple.yammo} are nearly extinct because {name.yammo} rind is delicious.",
        yammo_quest = "Kill {count} {count*{name_plurality.yammo}}.",

        NAMES = {
            bandicoot = "Greyl",
            yammo = "Yammo",
        },
        NAMES_PL = {
            bandicoot = "Greyls",
            yammo = "Yammi",
        },
    }
    local pl = loc.BuildPlurality(s.NAMES, s.NAMES_PL)
    loc.ReplaceNames(s, s.NAMES, s.NAMES_PL, pl)
    kassert.equal(s.bandi_gloves, "Made from Greyl fur.")
    kassert.equal(s.yammo_lore, "Yammi are nearly extinct because Yammo rind is delicious.")
    kassert.equal(s.yammo_quest, "Kill {count} {count*Yammo|Yammi}.")
end


local function parse_operator( str )
	if str and #str > 0 then
		return str:match("^([:*.%%#?])(.*)")
	end
end

-- Localization formatter which should be used exclusively to compose all localized strings.  Each
-- format specifier (a parameter index enclosed in curly braces) can take multiple forms.
-- Note that the location of the specifiers within the format string is immaterial, since they
-- directly refer to the relevant parameter's index.
-- In the examples below, replace 'n' with the 'nth' parameter (not including the format string).
--
-- {n} : replaced with tostring(n)
-- loc.format( "I am a formatted {1}", "string" ) --> "I am a formatted string"

-- {n:word1|word2|...} : replaced with word<n>, so that n indexes into the pipe-delineated list.
-- loc.format( "I choose you, {1:Pikachu|Squirtle}!", 1 ) --> "I choose you, Pikachu!"
--
-- {n*plural1|plural2|...} : replaced with word<i>, where i == convertPlurality(n), so that n is
--      an integral number of something, which is converted into an index into the pipe-delineated list.
--      The plurality function is customizable per locale.
-- loc.format( "I ate {1*an|some} {1*apple|apples}", 1 ) --> "I ate an apple"
--
-- {n.field} : replaced with n[ field ], so that n is a table of strings indexed by the fieldname.
--      In the example below, DECKER = { name = "Decker", hisher = "his" }.
-- loc.format( "{1.name} hurt {1.hisher} hand", DECKER ) --> "Decker hurt his hand"
--
-- {n%format} : replaced with string.format( format, n )
-- loc.format( "Pi to 2 places: {1%.2f}", math.pi ) --> "Pi to 2 places: 3.14"
--
-- {n#macro_fn} : replaced with macro_fn( n )
-- loc.format( "Happy {1#time} to you!", gs:GetDateTime() ) --> "Happy 6:05 am to you!"
--
-- {n?true_phrase|false_phrase} : boolean selector
--


function loc.format(str, ...)
     if type(str) == "table" then
        str = table.concat( str )
    end

    local params = {...}

    local ret = string.gsub(str, "%b{}",
        function(capture)

            local ret
            local param_idx, payload = string.match(capture, "^{%s*([0-9]+)(.*)}$")
            if param_idx then
                param_idx = tonumber(param_idx)
            end

            local operator, operator_payload
            if payload then
                payload = loc.format(payload, table.unpack(params))
                operator, operator_payload = string.match(payload, "([?:#.*%%])(.*)")
            end

            local param = params[param_idx]
            local tokens = {}
            if operator_payload then
                if operator == "." then
                    tokens = operator_payload:split_pattern("[?|]")
                else
                    tokens = operator_payload:split_pattern("|")
                end
            end
            if operator == "?" then
                -- boolean true|false
                ret = param and tokens[1] or tokens[2]
                ret = ret and tostring(ret) or ""
            elseif operator == "*" then
                -- param is a plurality, which converts to an index into tokens
                local pluralForm = loc.convertPlurality( param )
                ret = tostring( tokens[pluralForm] or tokens[#tokens] )
            elseif operator == ":" then
                -- param in an index into tokens
                ret = tostring( tokens[param] or tokens[#tokens] )
            elseif operator == '.' then
                -- param is a table, token is the field-name.
                if type(param) == "table" then
                    if tokens[1] and param.LocMacro then
                        ret = param:LocMacro(table.unpack(tokens))
                    end
                    ret = ret or tostring( tokens[1] and type(param) == "table" and param[ tokens[1] ] )
                end
            elseif operator == '%' then
                if tokens[1] == "d" and type(param) ~= "number" then
                    ret = tostring(param)
                else
                    ret = string.format( "%"..tokens[1], param )
                end
            elseif operator == '#' then
                ret = tostring( (loc[ tokens[1] ] and loc[ tokens[1] ]( param ) or tokens[1]) )
            else
                local str = tostring(param or capture)
                ret = str
                --local inner = string.match(str, "^{(.*{.*)}$")
                --ret = inner and loc.format(inner, table.unpack(params) ) or str
            end
            return ret
        end)
    return ret
end


-- Localization formatter which defers the replacement to the function 'f' which receives
-- 3 parameters: word, fn, field which correspond to the loc formatter fields {word.fn.field}
function loc.custom_format( format, f )
    assert( type(f) == "function" )

    local function repl( formatter )
        local word, rest = formatter:match( "^{([%(%) _%w]+)(.*)}$")
    	if word then
            local operator, rest = parse_operator( rest )
            rest = rest and loc.custom_format(rest, f)
            return f( word, operator, rest)
        end
    end

    local txt = format:gsub( "%b{}", repl )

    return txt
end

function loc.cap( str )
	return loc.toupper( str:sub( 1, 1 ) ) .. str:sub( 2 )
end

function loc.decap( str )
	return loc.tolower( str:sub( 1, 1 ) ) .. str:sub( 2 )
end

function loc.toupper( str )
	-- FIXME: non-unicode garbage
	--return utf8_ex.upper( str )
    return string.upper( str )
end

function loc.tolower( str )
	-- FIXME: non-unicode garbage
	--return utf8_ex.lower( str )
    return string.lower( str )
end

-- Resolves and formats a recursive save-loadable localization table 't', which is a table containing
-- loc IDs and format parameters (possibly nested).  eg:
-- loc.resolve( { "TALK.SAVELOAD.DESC_FORMAT", 235235, 63, { "CLASSES.SectorName.HOME" } } )

function loc.resolve( t )
    t = shallowcopy( t )
    for i, v in ipairs( t ) do
        if type(v) == "string" then
            t[i] = LOC( v )
        elseif type(v) == "table" then
            t[i] = loc.resolve(v)
        end
    end
    return loc.format( table.unpack( t ))
end

return loc

