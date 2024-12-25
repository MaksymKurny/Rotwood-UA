local REPO = "MaksymKurny/Rotwood-UA/"
local BRANCH = IS_BETA_TEST and "main_beta" or "main"
local LINK = "data_scripts_zip/localizations/uk.po"

local Image = require "widgets.image"
local Text = require "widgets.text"
local Widget = require "widgets.widget"
local Panel = require "widgets.panel"
local ImageButton = require "widgets.imagebutton"
local ActionButton = require("widgets/actionbutton")
local MainScreen = require "screens.mainscreen"
local Screen = require "widgets.screen"

local LocUpdate = {
	URL = "https://raw.githubusercontent.com/"..REPO..BRANCH.."/"..LINK,
	V_URL = "https://api.github.com/repos/"..REPO.."commits?path="..LINK.."&page=1&per_page=1&sha="..BRANCH,
	PATH = "",
	lastModified = "",
}


function LocUpdate:ShowNote()
if TheFrontEnd then
	print("SHOW NOTE", MainScreen)
	local bottom_pad = 60
	
	self.reload_popup = Widget("UpdPOpup")
	self.reload_popup:AddChild(Image("images/bg_popup_small/popup_small.tex"))
		:SetName("Popup background")
		:SetSize(1200, 500)

	self.reload_popup:AddChild(Text(FONTFACE.DEFAULT, FONTSIZE.SCREEN_TITLE))
		:SetGlyphColor(UICOLORS.LIGHT_TEXT_DARKER)
		:SetName("Title text")
		:LayoutBounds("center", "top", self.reload_popup)
		:SetGlyphColor(UICOLORS.LIGHT_TEXT_DARKER)
		:Offset(0, -bottom_pad)
		:SetText("Файл перекладу оновлено")
		
	self.reload_popup:AddChild(Text(FONTFACE.DEFAULT, FONTSIZE.DIALOG_TITLE))
		:SetName("Dialog title")
		:SetGlyphColor(UICOLORS.DARK_TEXT)
		:SetAutoSize(700)
		:Offset(0, bottom_pad)
		:SetText("Перезавантажте гру для застосування змін")
	
	self.reload_popup:AddChild(ImageButton("images/ui_ftf/HeaderClose.tex"))
		:SetName("Close button")
		:SetSize(BUTTON_SQUARE_SIZE, BUTTON_SQUARE_SIZE)
		:LayoutBounds("right", "top", self.reload_popup)
		:Offset(bottom_pad / 2, bottom_pad / 2)
		:SetOnClick(function() self.reload_popup:Hide() end)
	
	self.reload_popup:AddChild(ActionButton())
		:SetName("Button")
		:SetSize(_G.BUTTON_W, _G.BUTTON_H)
		:SetPrimary()
		:SetTextAndResizeToFit("Перезавантажити", 50, 30)
		:LayoutBounds("center", "bottom", self.reload_popup)
		:Offset(0, bottom_pad)
		:SetOnClick(function() _G.c_reset() end)
	end
end

function LocUpdate:StartUpdate()
	print("[Loc Update] Start update")
	TheSim:QueryServer(self.URL, function (result, isSuccessful, resultCode)
		if resultCode ~= 200 or not isSuccessful or #result < 1 then
			print("[Loc Update] Update: fail")
			return
		end
		
		local f = io.open(self.PATH.."uk.po", "w")
		if f then
			f:write(result)
			f:close()
			--self:ShowNote()
			c_reset()
		else
			print("[Loc Update] Update: fail")
		end
		
		local ver_f = io.open(self.PATH.."version.txt", "w")
		if ver_f then
			ver_f:write(self.lastModified)
			ver_f:close()
		else
			print("[Loc Update] Save version: fail")
		end
	end, "GET")
end

function LocUpdate:GetLastCommitDate(fn)
	TheSim:QueryServer(self.V_URL, function (result, isSuccessful, resultCode)
		if resultCode ~= 200 or not isSuccessful or #result < 1 then
			print("[Loc Update] Get version: fail")
			return
		end
		
		local commit_data = json.decode(result)
		if commit_data and commit_data[1] and commit_data[1].commit and commit_data[1].commit.author and commit_data[1].commit.author.date then
			local lastModified = commit_data[1].commit.author.date
			fn(lastModified)
		end
	end, "HEAD")
end

function LocUpdate:CheckUpdate()
	self:GetLastCommitDate(function(date)
		local file = io.open(self.PATH.."version.txt", "r")
		if file then
			local curr_date = file:read("*all")
			file:close()
			if date and curr_date and date ~= curr_date then
				self.lastModified = date
				self:StartUpdate()
			end
		else
			print("[Loc Update] Read version: fail")
		end
	end)
end

return LocUpdate