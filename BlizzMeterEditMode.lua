local _, BlizzMeterPrivate = ...;

-- BlizzMeter's stand-in for EditModeDamageMeterSystemMixin.
--
-- Addons can't register their own Edit Mode systems, so instead of being one, BlizzMeter follows the
-- Blizzard Damage Meter's. It anchors itself to the Blizzard meter's Edit Mode frame, which gives it that
-- frame's position and size (live, including while it's being dragged or resized in Edit Mode), copies the
-- frame's scale, and mirrors the system's editing state. The system's style settings only give BlizzMeter's
-- own options (BlizzMeterOptions.lua) their starting values.
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

	-- Whenever the Blizzard meter re-checks whether it should be shown (including when the damage meter becomes
	-- available after login), check again here too.
	if editModeSystem.UpdateShownState then
		hooksecurefunc(editModeSystem, "UpdateShownState", function()
			self:UpdateShownState();
		end);
	end

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

-- Runs after the Blizzard system has applied a setting. Style settings only seed BlizzMeter's options the first
-- time they're seen (see BlizzMeterOptions.lua). Frame width and height need nothing here: they're applied to the
-- Blizzard meter's frame, which this one is anchored to.
function BlizzMeterEditModeSystemMixin:UpdateSystemSetting(setting, _entireSystemUpdate)
	local editModeSystem = self:GetEditModeSystem();
	if not editModeSystem:IsInitialized() or not editModeSystem:HasSetting(setting) then
		return;
	end

	BlizzMeterPrivate.Options.AdoptEditModeSetting(self, setting);
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
