local translation_mod = {}

local function LoadTranslation(modinfo)
	local mod_id = modinfo.mod_id
	TheLog.ch.Mods:printf("Activating '%s' with LoadTranslation.", mod_id)
	if not modinfo.translation then
		TheLog.ch.Mods:printf("modinfo for '%s' was missing the translation configuration table.", mod_id)
		return false
	end
	local Localization = require "questral.localization"
	local loc = Localization(modinfo.translation)
	if not loc:SetAsLocalMod(mod_id, modinfo) then
		TheLog.ch.Mods:printf("'%s' was not a valid local mod.", mod_id)
		return false
	end
	TheGameContent:GetContentDB():AddContentItem(loc)
	TheLog.ch.Mods:printf("Successfully added localization '%s' to ContentDB.", loc.id)
	return true
end

function translation_mod.ActivateAllTranslationMods()
	local to_load = KnownModIndex:_GetModAutoEnableCandidates()
	for _, modname in ipairs(to_load) do
		-- TODO(mod): We don't have a mod screen, so enable all subscribed mods
		-- that aren't broken.
		KnownModIndex:EnableMod(modname)
	end
	KnownModIndex:ActivateModsOfType(KnownModIndex.ModType.s.translation, LoadTranslation)
end

return translation_mod
