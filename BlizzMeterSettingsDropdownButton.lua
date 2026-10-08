BlizzMeterSettingsDropdownButton = CreateFromMixins(ButtonStateBehaviorMixin);

function BlizzMeterSettingsDropdownButton:GetIcon()
	return self.Icon;
end

function BlizzMeterSettingsDropdownButton:GetIconAtlas()
	if not self:IsEnabled() then
		return self.disabled;
	elseif self:IsDownOver() then
		return self.hoverPressed;
	elseif self:IsOver() then
		return self.hover;
	elseif self:IsDown() then
		return self.pressed;
	elseif self:IsMenuOpen() then
		return self.open;
	else
		return self.normal;
	end
end

function BlizzMeterSettingsDropdownButton:OnButtonStateChanged()
	local iconAtlas = self:GetIconAtlas();
	self:GetIcon():SetAtlas(iconAtlas, TextureKitConstants.UseAtlasSize);
end

function BlizzMeterSettingsDropdownButton:OnMenuOpened(menu)
	DropdownButtonMixin.OnMenuOpened(self, menu);

	self:OnButtonStateChanged();
end

function BlizzMeterSettingsDropdownButton:OnMenuClosed(menu, closeReason)
	DropdownButtonMixin.OnMenuClosed(self, menu, closeReason);

	self:OnButtonStateChanged();
end
