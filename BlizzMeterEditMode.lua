-- BlizzMeter's stand-in for EditModeDamageMeterSystemMixin.
--
-- Addons can't register their own Edit Mode systems, so instead of being one, BlizzMeter follows the
-- Blizzard Damage Meter's. It anchors itself to the Blizzard meter's Edit Mode frame, which gives it that
-- frame's position and size (live, including while it's being dragged or resized in Edit Mode), copies the
-- frame's scale, and mirrors the system's settings and editing state.
--
-- The Blizzard meter keeps running underneath so its Edit Mode selection can still be moved, resized and
-- configured as usual, but its windows are moved into a hidden parent so only BlizzMeter is visible.
--
-- Everything here only reads from the Blizzard meter or post-hooks it with hooksecurefunc. Writing into its
-- tables from addon code would taint it, and tainted Blizzard code errors on the secret values the meter
-- handles in combat.

-- Parented to UIParent so the hidden windows keep the same effective scale (and so the same screen position and
-- size) they'd have under the Blizzard meter, which GetBlizzardSessionWindowScreenRect relies on.
local HiddenBlizzardWindowParent = CreateFrame("Frame", nil, UIParent);
HiddenBlizzardWindowParent:Hide();

local function GetBlizzardDamageMeterSystem()
	local damageMeter = DamageMeter;
	if type(damageMeter) == "table" and damageMeter.system == Enum.EditModeSystem.DamageMeter then
		return damageMeter;
	end

	return nil;
end

local function HideBlizzardSessionWindow(sessionWindow)
	if sessionWindow and sessionWindow:GetParent() ~= HiddenBlizzardWindowParent then
		sessionWindow:SetParent(HiddenBlizzardWindowParent);
	end
end

BlizzMeterEditModeSystemMixin = {};

function BlizzMeterEditModeSystemMixin:OnSystemLoad()
	local editModeSystem = GetBlizzardDamageMeterSystem();
	if not editModeSystem then
		-- Nothing to follow; the meter keeps its default position and settings.
		return;
	end

	self.editModeSystem = editModeSystem;

	self:ClearAllPoints();
	self:SetPoint("TOPLEFT", editModeSystem, "TOPLEFT");
	self:SetPoint("BOTTOMRIGHT", editModeSystem, "BOTTOMRIGHT");
	self:UpdateSystemScale();

	editModeSystem:ForEachSessionWindow(HideBlizzardSessionWindow);

	hooksecurefunc(editModeSystem, "SetupSessionWindow", function(_editModeSystem, _windowDataIndex, windowData)
		HideBlizzardSessionWindow(windowData.sessionWindow);
	end);

	hooksecurefunc(editModeSystem, "UpdateSystemSetting", function(_editModeSystem, setting, entireSystemUpdate)
		self:UpdateSystemSetting(setting, entireSystemUpdate);
	end);

	hooksecurefunc(editModeSystem, "OnUpdateSystem", function(_editModeSystem, anySettingsDirty)
		self:OnUpdateSystem(anySettingsDirty);
	end);

	hooksecurefunc(editModeSystem, "SetIsEditing", function(_editModeSystem, isEditing)
		self:SetIsEditing(isEditing);
	end);

	hooksecurefunc(editModeSystem, "SetScale", function()
		self:UpdateSystemScale();
	end);

	-- Edit Mode normally applies its layout after login, which the hooks above pick up. If it already has,
	-- catch up once this frame has finished loading.
	if editModeSystem:IsInitialized() then
		RunNextFrame(function()
			self:UpdateSystem();
		end);
	end
end

function BlizzMeterEditModeSystemMixin:GetEditModeSystem()
	return self.editModeSystem;
end

-- Returns the screen rect (left, top, width, height) of a Blizzard secondary window the player has moved or
-- resized, so the matching window here can start out in the same place. Returns nil otherwise.
function BlizzMeterEditModeSystemMixin:GetBlizzardSessionWindowScreenRect(windowDataIndex)
	local editModeSystem = self:GetEditModeSystem();
	local sessionWindow = editModeSystem and editModeSystem:GetSessionWindow(windowDataIndex);
	if not sessionWindow or not sessionWindow:IsUserPlaced() then
		return nil;
	end

	local left, top = sessionWindow:GetLeft(), sessionWindow:GetTop();
	if not left or not top then
		return nil;
	end

	local width, height = sessionWindow:GetSize();
	local scale = sessionWindow:GetEffectiveScale();
	return left * scale, top * scale, width * scale, height * scale;
end

-- The meter is parented to UIParent rather than to the Blizzard frame, so it copies that frame's effective scale.
function BlizzMeterEditModeSystemMixin:UpdateSystemScale()
	self:SetScale(self:GetEditModeSystem():GetEffectiveScale() / self:GetParent():GetEffectiveScale());
end

function BlizzMeterEditModeSystemMixin:GetSettingValue(setting)
	return self:GetEditModeSystem():GetSettingValue(setting);
end

function BlizzMeterEditModeSystemMixin:GetSettingValueBool(setting)
	return self:GetEditModeSystem():GetSettingValueBool(setting);
end

function BlizzMeterEditModeSystemMixin:UpdateSystemSettingVisibility()
	self.visibility = self:GetSettingValue(Enum.EditModeDamageMeterSetting.Visibility);
	self:UpdateShownState();
end

function BlizzMeterEditModeSystemMixin:UpdateSystemSettingStyle()
	local style = self:GetSettingValue(Enum.EditModeDamageMeterSetting.Style);
	self:SetStyle(style);
end

function BlizzMeterEditModeSystemMixin:UpdateSystemSettingNumberDisplayType()
	local numberDisplayType = self:GetSettingValue(Enum.EditModeDamageMeterSetting.Numbers);
	self:SetNumberDisplayType(numberDisplayType);
end

function BlizzMeterEditModeSystemMixin:UpdateSystemSettingFrameWidth()
	-- Applied to the Blizzard meter's frame, which this one is anchored to.
end

function BlizzMeterEditModeSystemMixin:UpdateSystemSettingFrameHeight()
	-- Applied to the Blizzard meter's frame, which this one is anchored to.
end

function BlizzMeterEditModeSystemMixin:UpdateSystemSettingBarHeight()
	local barHeight = self:GetSettingValue(Enum.EditModeDamageMeterSetting.BarHeight);
	self:SetBarHeight(barHeight);
end

function BlizzMeterEditModeSystemMixin:UpdateSystemSettingPadding()
	local barSpacing = self:GetSettingValue(Enum.EditModeDamageMeterSetting.Padding);
	self:SetBarSpacing(barSpacing);
end

function BlizzMeterEditModeSystemMixin:UpdateSystemSettingTransparency()
	local transparency = self:GetSettingValue(Enum.EditModeDamageMeterSetting.Transparency);
	self:SetWindowTransparency(transparency);
end

function BlizzMeterEditModeSystemMixin:UpdateSystemSettingShowSpecIcon()
	local showBarIcons = self:GetSettingValueBool(Enum.EditModeDamageMeterSetting.ShowSpecIcon);
	self:SetShowBarIcons(showBarIcons);
end

function BlizzMeterEditModeSystemMixin:UpdateSystemSettingShowClassColor()
	local useClassColor = self:GetSettingValueBool(Enum.EditModeDamageMeterSetting.ShowClassColor);
	self:SetUseClassColor(useClassColor);
end

function BlizzMeterEditModeSystemMixin:UpdateSystemSettingTextSize()
	local textSize = self:GetSettingValue(Enum.EditModeDamageMeterSetting.TextSize);
	self:SetTextSize(textSize);
end

function BlizzMeterEditModeSystemMixin:UpdateSystemSettingBackgroundTransparency()
	local backgroundTransparency = self:GetSettingValue(Enum.EditModeDamageMeterSetting.BackgroundTransparency);
	self:SetBackgroundTransparency(backgroundTransparency);
end

-- Runs after the Blizzard system has applied a setting. Unlike Blizzard's version this doesn't check the
-- system's dirty flags (they're cleared by then); the setters ignore values that haven't changed instead.
function BlizzMeterEditModeSystemMixin:UpdateSystemSetting(setting, entireSystemUpdate)
	local editModeSystem = self:GetEditModeSystem();
	if not editModeSystem:IsInitialized() or not editModeSystem:HasSetting(setting) then
		return;
	end

	if setting == Enum.EditModeDamageMeterSetting.Visibility then
		self:UpdateSystemSettingVisibility();
	elseif setting == Enum.EditModeDamageMeterSetting.Style then
		self:UpdateSystemSettingStyle();
	elseif setting == Enum.EditModeDamageMeterSetting.Numbers then
		self:UpdateSystemSettingNumberDisplayType();
	elseif setting == Enum.EditModeDamageMeterSetting.FrameWidth then
		self:UpdateSystemSettingFrameWidth();
	elseif setting == Enum.EditModeDamageMeterSetting.FrameHeight then
		self:UpdateSystemSettingFrameHeight();
	elseif setting == Enum.EditModeDamageMeterSetting.BarHeight then
		self:UpdateSystemSettingBarHeight();
	elseif setting == Enum.EditModeDamageMeterSetting.Padding then
		self:UpdateSystemSettingPadding();
	elseif setting == Enum.EditModeDamageMeterSetting.Transparency then
		self:UpdateSystemSettingTransparency();
	elseif setting == Enum.EditModeDamageMeterSetting.ShowSpecIcon then
		self:UpdateSystemSettingShowSpecIcon();
	elseif setting == Enum.EditModeDamageMeterSetting.ShowClassColor then
		self:UpdateSystemSettingShowClassColor();
	elseif setting == Enum.EditModeDamageMeterSetting.TextSize then
		self:UpdateSystemSettingTextSize();
	elseif setting == Enum.EditModeDamageMeterSetting.BackgroundTransparency then
		self:UpdateSystemSettingBackgroundTransparency();
	end

	if not entireSystemUpdate then
		self:RefreshLayout();
	end
end

function BlizzMeterEditModeSystemMixin:OnUpdateSystem(anySettingsDirty)
	self:UpdateSystemScale();

	if anySettingsDirty then
		self:RefreshLayout();
	end
end

-- Applies every setting at once, the way EditModeSystemMixin:UpdateSystem does when a layout is applied.
function BlizzMeterEditModeSystemMixin:UpdateSystem()
	local entireSystemUpdate = true;
	for _settingName, setting in pairs(Enum.EditModeDamageMeterSetting) do
		self:UpdateSystemSetting(setting, entireSystemUpdate);
	end

	local anySettingsDirty = true;
	self:OnUpdateSystem(anySettingsDirty);
end
