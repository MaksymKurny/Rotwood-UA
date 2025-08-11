local Screen = require "widgets/screen"
local Menu = require "widgets/menu"
local Text = require "widgets/text"
local Image = require "widgets/image"
local Widget = require "widgets/widget"

local Controls = require "input.controls"

local ModWarningScreen = Class(Screen, function(self, title, text, buttons, texthalign, additionaltext, textsize)
	Screen._ctor(self, "ModWarningScreen")

	--darken everything behind the dialog
	self.background = self:AddChild(Image("images/global/square.tex"))
		:SetName("Background")
    	:SetSize(RES_X, RES_Y)
		:SetMultColor(UICOLORS.DARK_BACKGROUNDS_DARK)
		:SetMultColorAlpha(0.8)

	self.main_stack = self:AddChild(Widget("Main Stack"))
		:SetRegistration("center", "center")

	--title
    self.title = self.main_stack:AddChild(Text(FONTFACE.TITLE, FONTSIZE.OVERLAY_TITLE))
		:SetName("Title")
    	:SetText(title)

	self.textbody_stack = self.main_stack:AddChild(Widget("Text Body Stack"))
		:SetRegistration("center", "center")

	--text
	local defaulttextsize = textsize or FONTSIZE.DIALOG_TEXT
    self.text = self.textbody_stack:AddChild(Text(FONTFACE.BODYTEXT, defaulttextsize))
		:EnableWordWrap(true)
		:SetAutoSize(480*4)
		:SetText(text)
	if texthalign then
		self.text:SetHAlign(texthalign)
	end

    if additionaltext then
	    self.additionaltext = self.textbody_stack:AddChild(Text(FONTFACE.BODYTEXT, 50))
			:SetName("Additional Text")
	    	:SetText(additionaltext)
	    	:EnableWordWrap(true)
	    	:SetAutoSize(480*4)
    end

	if buttons then
	    self.menu = self.main_stack:AddChild(Menu(buttons, 250, true))
			:SetName("Buttons")
	end

	if Platform.IsRail() then
		-- disable the mod forum button if it exists
		if self.menu and self.menu.items then
			for _,v in pairs(self.menu.items) do
				if v:GetText() == STRINGS.UI.MAINSCREEN.MODFORUMS then
					v:Select()
					v:SetToolTip(STRINGS.UI.MAINSCREEN.MODFORUMS_NOT_AVAILABLE_YET)
				end
			end
		end
	end

	self.version = self:AddChild(Text(FONTFACE.BODYTEXT, 50))
		:SetName("Version Number")
		:SetRegistration("left", "bottom")
		:SetVAlign(ANCHOR_BOTTOM)
		:SetHAlign(ANCHOR_LEFT)
		:LayoutBounds("left", "bottom", self)
		:SetText("Rev. "..APP_VERSION.." "..PLATFORM)
		:SetMultColorAlpha(0.6)

	self.textbody_stack
		:CenterChildren()
		:LayoutChildrenInColumn(48)
	self.main_stack
		:CenterChildren()
		:LayoutChildrenInColumn(100)

	self.default_focus = self.menu and self.menu.items[1] or self.text
end)

ModWarningScreen.CONTROL_MAP = {
	{
		control = Controls.Digital.CANCEL,
		fn = function(self)
			TheFrontEnd:PopScreen(self)
		end,
	},
}

return ModWarningScreen
