local DAMAGE_METER_ENABLED_CVAR = "damageMeterEnabled";
-- BlizzMeter: Blizzard_DamageMeter already makes this CVar cachable. Doing it again from addon code would
-- write into CVarCallbackRegistry's shared table and taint the Blizzard meter's reads of it.
-- CVarCallbackRegistry:SetCVarCachable(DAMAGE_METER_ENABLED_CVAR);

local MAX_DAMAGE_METER_SESSION_WINDOWS = 3;
local PRIMARY_SESSION_WINDOW_INDEX = 1;

-- Saved Variable. Stores which windows were previously shown and what damage meter type they were tracking.
local DefaultBlizzMeterPerCharacterSettings = {
	windowDataList = {};
};

BlizzMeterPerCharacterSettings = BlizzMeterPerCharacterSettings or nil;

local function BlizzMeterSetSavedVarsToDefault()
	local shallow = false;

	-- BlizzMeter: the first time, start from the Blizzard meter's saved windows so the same windows and
	-- tracked types carry over.
	local blizzardSettings = DamageMeterPerCharacterSettings;
	if type(blizzardSettings) == "table" and type(blizzardSettings.windowDataList) == "table" then
		BlizzMeterPerCharacterSettings = { windowDataList = CopyTable(blizzardSettings.windowDataList, shallow); };
		return;
	end

	BlizzMeterPerCharacterSettings = CopyTable(DefaultBlizzMeterPerCharacterSettings, shallow);
end

local function GetSavedWindowDataList()
	if not BlizzMeterPerCharacterSettings then
		BlizzMeterSetSavedVarsToDefault();
	end

	return BlizzMeterPerCharacterSettings.windowDataList;
end

local function SetSavedWindowData(windowIndex, windowData)
	assertsafe(windowIndex <= MAX_DAMAGE_METER_SESSION_WINDOWS);

	local savedWindowDataList = GetSavedWindowDataList();
	local savedWindowData = savedWindowDataList[windowIndex];

	if not savedWindowData then
		savedWindowData = {};
		savedWindowDataList[windowIndex] = savedWindowData;
	end

	-- Saved window data and actual window data aren't identical structures.
	savedWindowData.damageMeterType = windowData.damageMeterType;
	savedWindowData.sessionType = windowData.sessionType;
	savedWindowData.shown = windowData.sessionWindow and windowData.sessionWindow:IsShown() or false;
	savedWindowData.locked = windowData.locked;
	savedWindowData.nonInteractive = windowData.nonInteractive;
	savedWindowData.minimized = windowData.minimized;
	savedWindowData.position = windowData.position and CopyTable(windowData.position) or nil; -- BlizzMeter: see SaveSessionWindowPosition.
	-- sessionID is intentionally not preserved in saved data as it's specific to the player's recent encounters.
end

-- BlizzMeter: a saved secondary window position, in the window's own coordinates.
local function IsSavedPositionValid(position)
	return type(position) == "table"
		and type(position.left) == "number" and type(position.top) == "number"
		and type(position.width) == "number" and type(position.height) == "number";
end

local function IsSavedWindowDataValid(savedWindowData)
	if savedWindowData == nil then
		return false;
	end

	if savedWindowData.damageMeterType == nil then
		return false;
	end

	if type(savedWindowData.damageMeterType) ~= "number" then
		return false;
	end

	if savedWindowData.sessionType and type(savedWindowData.sessionType) ~= "number" then
		return false;
	end

	return true;
end

BlizzMeterMixin = {};

function BlizzMeterMixin:OnLoad()
	BlizzMeterEditModeSystemMixin.OnSystemLoad(self);

	EventRegistry:RegisterFrameEventAndCallback("VARIABLES_LOADED", self.OnVariablesLoaded, self);
	CVarCallbackRegistry:RegisterCallback(DAMAGE_METER_ENABLED_CVAR, self.OnEnabledCVarChanged, self);

	self:RegisterEvent("PLAYER_IN_COMBAT_CHANGED");
	self:RegisterEvent("PLAYER_LEVEL_CHANGED");
	self:RegisterEvent("GROUP_JOINED");
	self:RegisterEvent("GROUP_LEFT");
	self:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED"); -- BlizzMeter: see OnEvent.
	self:RegisterEvent("PLAYER_ENTERING_WORLD"); -- BlizzMeter: see OnEvent.

	self.windowDataList = {};
	self.sessionType = Enum.DamageMeterSessionType.Overall;
	self.sessionID = nil;

	self:InitializeWindowDataList();
end

function BlizzMeterMixin:OnEvent(event, ...)
	if event == "PLAYER_IN_COMBAT_CHANGED" or event == "PLAYER_LEVEL_CHANGED" or event == "GROUP_JOINED" or event == "GROUP_LEFT" then
		self:UpdateShownState();
	elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
		-- BlizzMeter: while combat restrictions are active, some values are secret and are shown in reduced form
		-- (no percentages or death times). Redraw with the readable values once a restriction lifts.
		local _restrictionType, state = ...;
		if state == Enum.AddOnRestrictionState.Inactive then
			self:ForEachSessionWindow(function(sessionWindow)
				if sessionWindow:IsShown() then
					sessionWindow:Refresh(ScrollBoxConstants.RetainScrollPosition);
				end
			end);
		end
	elseif event == "PLAYER_ENTERING_WORLD" then
		-- BlizzMeter: by now the client has restored saved frame positions, including the Blizzard meter's
		-- secondary windows that new windows here take their positions from.
		self:UnregisterEvent("PLAYER_ENTERING_WORLD");
		self:RestoreSessionWindowPositions();
	end
end

-- BlizzMeter: Blizzard's secondary windows keep their position in the client's frame layout cache, which goes
-- by frame name. BlizzMeter keeps position and size in its own saved variables instead, so a window can start
-- out where the matching Blizzard window was, and nothing depends on when the layout cache is applied.
function BlizzMeterMixin:SaveSessionWindowPosition(sessionWindow)
	local left, top = sessionWindow:GetLeft(), sessionWindow:GetTop();
	if not left or not top then
		return;
	end

	local width, height = sessionWindow:GetSize();
	local sessionWindowIndex, windowData = self:GetSessionWindowData(sessionWindow);
	windowData.position = { left = left, top = top, width = width, height = height };

	SetSavedWindowData(sessionWindowIndex, windowData);

	-- Keep the window out of the layout cache, which would otherwise restore an older copy of the position.
	sessionWindow:SetUserPlaced(false);
end

function BlizzMeterMixin:ApplySessionWindowPosition(sessionWindow, windowData)
	local position = windowData.position;
	if not IsSavedPositionValid(position) then
		return;
	end

	sessionWindow:ClearAllPoints();
	sessionWindow:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", position.left, position.top);
	sessionWindow:SetSize(position.width, position.height);
end

function BlizzMeterMixin:RestoreSessionWindowPositions()
	for windowDataIndex, windowData in pairs(self.windowDataList) do
		local sessionWindow = windowData.sessionWindow;
		if sessionWindow and windowDataIndex ~= PRIMARY_SESSION_WINDOW_INDEX then
			if not IsSavedPositionValid(windowData.position) then
				local left, top, width, height = self:GetBlizzardSessionWindowScreenRect(windowDataIndex);
				if left then
					local scale = sessionWindow:GetEffectiveScale();
					windowData.position = { left = left / scale, top = top / scale, width = width / scale, height = height / scale };
					SetSavedWindowData(windowDataIndex, windowData);
				end
			end

			self:ApplySessionWindowPosition(sessionWindow, windowData);
		end
	end
end

function BlizzMeterMixin:GetDefaultWindowData()
	return {
		damageMeterType = Enum.DamageMeterType.DamageDone,
		sessionType = self:GetSessionType(),
		sessionID = self:GetSessionID()
	};
end

function BlizzMeterMixin:CreateWindowData(windowDataIndex)
	assertsafe(windowDataIndex);
	assertsafe(not self.windowDataList[windowDataIndex]);
	assertsafe(windowDataIndex <= MAX_DAMAGE_METER_SESSION_WINDOWS);

	local windowData = self:GetDefaultWindowData();

	self.windowDataList[windowDataIndex] = windowData;

	self:SetupSessionWindow(windowDataIndex, windowData);

	SetSavedWindowData(windowDataIndex, windowData);
end

function BlizzMeterMixin:InitializeWindowDataList()
	-- Recreate all previously open windows and their respective damageMeterTypes.
	-- Any windows that were previously moved or resized will be positioned when the
	-- SavedFramePositionCache is loaded.
	self:LoadSavedWindowDataList();

	-- If it doesn't exist, create the primary session window, which much always exist and can't be hidden.
	-- This can happen if the saved window data doesn't exist or has been corrupted.
	if self:GetPrimarySessionWindow() == nil then
		self:CreateWindowData(PRIMARY_SESSION_WINDOW_INDEX);
	end
end

function BlizzMeterMixin:OnVariablesLoaded()
	self:UpdateShownState();
end

function BlizzMeterMixin:OnEnabledCVarChanged()
	self:UpdateShownState();
end

function BlizzMeterMixin:GetWindowDataList()
	return self.windowDataList;
end

function BlizzMeterMixin:SetIsEditing(isEditing)
	if self.isEditing == isEditing then
		return;
	end

	self.isEditing = isEditing;

	self:UpdateShownState();

	self:GetPrimarySessionWindow():SetIsEditing(isEditing);
end

function BlizzMeterMixin:IsEditing()
	return self.isEditing;
end

function BlizzMeterMixin:IsPlayerInCombat()
	local isInCombat = UnitAffectingCombat("player");
	return isInCombat;
end

function BlizzMeterMixin:IsPlayerInGroup()
	return IsInGroup();
end

function BlizzMeterMixin:ShouldBeShown()
	if self:IsEditing() then
		return true;
	end

	if CVarCallbackRegistry:GetCVarValueBool(DAMAGE_METER_ENABLED_CVAR) ~= true then
		return false;
	end

	local isAvailable, _failureReason = C_DamageMeter.IsDamageMeterAvailable();
	if not isAvailable then
		return false;
	end

	if self.visibility then
		if self.visibility == Enum.DamageMeterVisibility.Always then
			return true;
		elseif self.visibility == Enum.DamageMeterVisibility.InCombat then
			return self:IsPlayerInCombat();
		elseif self.visibility == Enum.DamageMeterVisibility.Hidden then
			return false;
		elseif self.visibility == Enum.DamageMeterVisibility.InGroup then
			return self:IsPlayerInGroup();
		else
			-- BlizzMeter: Blizzard's message concatenates self.visibleSetting, which doesn't exist and would error.
			assertsafe(false, "Unknown value for visible setting: %s", tostring(self.visibility));
		end
	end

	return true;
end

function BlizzMeterMixin:UpdateShownState()
	local shouldBeShown = self:ShouldBeShown();
	self:SetShown(shouldBeShown);
	self:UpdateSessionTimerState();
end

function BlizzMeterMixin:UpdateSessionTimerState()
	self:ForEachSessionWindow(function(sessionWindow) sessionWindow:UpdateSessionTimerState(); end);
end

function BlizzMeterMixin:RefreshLayout()
	self:ForEachSessionWindow(function(sessionWindow) sessionWindow:RefreshLayout(); end);
end

function BlizzMeterMixin:GetSessionWindow(index)
	return self.windowDataList and self.windowDataList[index] and self.windowDataList[index].sessionWindow or nil;
end

function BlizzMeterMixin:ForEachSessionWindow(func, ...)
	for _, windowData in pairs(self.windowDataList) do
		local sessionWindow = windowData.sessionWindow;
		if sessionWindow then
			func(sessionWindow, ...);
		end
	end
end

function BlizzMeterMixin:GetPrimarySessionWindow()
	return self:GetSessionWindow(PRIMARY_SESSION_WINDOW_INDEX);
end

function BlizzMeterMixin:GetMaxSessionWindowCount()
	return MAX_DAMAGE_METER_SESSION_WINDOWS;
end

function BlizzMeterMixin:GetCurrentSessionWindowCount()
	local currentCount = 0;

	self:ForEachSessionWindow(function(sessionWindow)
		if sessionWindow:IsShown() then
			currentCount = currentCount + 1;
		end
	end);

	return currentCount;
end

function BlizzMeterMixin:CanShowNewSecondarySessionWindow()
	return self:GetCurrentSessionWindowCount() < self:GetMaxSessionWindowCount();
end

-- Returns an index of an empty slot in the windowData table.
-- Can return nil if the maximum number of windowData entries have already been created.
function BlizzMeterMixin:GetAvailableSecondaryWindowDataIndex()
	local windowDataList = self:GetWindowDataList();
	local maxSessionWindowCount = self:GetMaxSessionWindowCount();
	for i = 1, maxSessionWindowCount do
		if i ~= PRIMARY_SESSION_WINDOW_INDEX then
			local windowData = windowDataList[i];
			if not windowData then
				return i;
			end
		end
	end

	return nil;
end

-- Returns an index of an existing windowData entry that either doesn't have a sessionWindow created, or the sessionWindow is hidden.
-- Can return nil if the maximum number of windows are already shown.
function BlizzMeterMixin:GetAvailableSecondarySessionWindowIndex()
	local windowDataList = self:GetWindowDataList();
	local maxSessionWindowCount = self:GetMaxSessionWindowCount();
	for i = 1, maxSessionWindowCount do
		if i ~= PRIMARY_SESSION_WINDOW_INDEX then
			local windowData = windowDataList[i];
			if windowData then
				if windowData.sessionWindow == nil or windowData.sessionWindow:IsShown() == false then
					return i;
				end
			end
		end
	end

	return nil;
end

function BlizzMeterMixin:SetupSessionWindow(windowDataIndex, windowData)
	local sessionWindow = windowData.sessionWindow or CreateFrame("FRAME", "BlizzMeterSessionWindow" .. windowDataIndex, self, "BlizzMeterSessionWindowTemplate");

	if not windowData.sessionWindow then
		windowData.sessionWindow = sessionWindow;
	end

	sessionWindow:SetDamageMeterOwner(self, windowDataIndex);
	sessionWindow:SetDamageMeterType(windowData.damageMeterType);
	sessionWindow:SetSession(windowData.sessionType, windowData.sessionID);
	sessionWindow:SetUseClassColor(self:ShouldUseClassColor());
	sessionWindow:SetBarHeight(self:GetBarHeight());
	sessionWindow:SetBarSpacing(self:GetBarSpacing());
	sessionWindow:SetTextScale(self:GetTextScale());
	sessionWindow:SetAlpha(self:GetWindowAlpha());
	sessionWindow:SetShowBarIcons(self:ShouldShowBarIcons());
	sessionWindow:SetBackgroundAlpha(self:GetBackgroundAlpha());
	sessionWindow:SetStyle(self:GetStyle());
	sessionWindow:SetNumberDisplayType(self:GetNumberDisplayType());

	-- Each new window should render above the previous ones.
	sessionWindow:SetFrameLevel(windowDataIndex);

	-- Give the window initial positioning that may be overwritten by the saved frame position cache when it's loaded.
	sessionWindow:ClearAllPoints();

	-- Primary window is always anchored to the meter frame so its size and location are controlled through edit mode.
	-- All other windows are given an initial offset so they're not stacked on top of each other when shown.
	if windowDataIndex == PRIMARY_SESSION_WINDOW_INDEX then
		sessionWindow:SetPoint("TOPLEFT");
		sessionWindow:SetPoint("BOTTOMRIGHT");
	else
		local xOffset = (windowDataIndex - PRIMARY_SESSION_WINDOW_INDEX) * 40;
		local yOffset = (windowDataIndex - PRIMARY_SESSION_WINDOW_INDEX) * -40;
		sessionWindow:SetPoint("TOPLEFT", UIParent, "TOPLEFT", xOffset, yOffset);

		self:ApplySessionWindowPosition(sessionWindow, windowData); -- BlizzMeter: see SaveSessionWindowPosition.
	end

	-- Only the secondary windows can be moved and resized outside of edit mode.
	if self:CanMoveOrResizeSessionWindow(sessionWindow) then
		sessionWindow:SetMovable(true);
		sessionWindow:SetResizable(true);

		-- Ensure that the window's position won't be saved out until it's restored from the frame
		-- position cache, or if the player moves it. Important for the case when the player hides a
		-- window and shows a new one that's reusing a name already in the cache.
		sessionWindow:SetUserPlaced(false);
	end

	sessionWindow:Show();

	if windowData.locked then
		sessionWindow:SetLocked(true);
	end

	if windowData.nonInteractive then
		sessionWindow:SetNonInteractive(true);
	end

	if type(windowData.minimized) == "boolean" then
		sessionWindow:SetMinimized(windowData.minimized);
	end
end

function BlizzMeterMixin:LoadSavedWindowDataList()
	local savedWindowDataList = GetSavedWindowDataList();
	if #savedWindowDataList == 0 then
		return;
	end

	local maxSessionWindowCount = self:GetMaxSessionWindowCount();
	for i = 1, maxSessionWindowCount do
		local savedWindowData = savedWindowDataList[i];

		if IsSavedWindowDataValid(savedWindowData) == true then
			local windowData = self.windowDataList[i];

			if not windowData then
				windowData = {};
				self.windowDataList[i] = windowData;
			end

			windowData.damageMeterType = savedWindowData.damageMeterType;
			windowData.sessionType = savedWindowData.sessionType or self:GetSessionType();
			windowData.locked = savedWindowData.locked;
			windowData.nonInteractive = savedWindowData.nonInteractive;
			windowData.minimized = savedWindowData.minimized;
			windowData.position = savedWindowData.position; -- BlizzMeter: see SaveSessionWindowPosition.

			if savedWindowData.shown or i == PRIMARY_SESSION_WINDOW_INDEX then
				self:SetupSessionWindow(i, windowData);
			end
		end
	end
end

function BlizzMeterMixin:GetSessionWindowData(sessionWindow)
	local sessionWindowIndex = sessionWindow:GetSessionWindowIndex();
	local windowData = self.windowDataList[sessionWindowIndex];

	return sessionWindowIndex, windowData;
end

function BlizzMeterMixin:ShowNewSecondarySessionWindow()
	if self:CanShowNewSecondarySessionWindow() ~= true then
		return;
	end

	local sessionWindowIndex = self:GetAvailableSecondarySessionWindowIndex();
	if sessionWindowIndex then
		local windowData = self.windowDataList[sessionWindowIndex];

		self:SetupSessionWindow(sessionWindowIndex, windowData);

		SetSavedWindowData(sessionWindowIndex, windowData);
	else
		sessionWindowIndex = self:GetAvailableSecondaryWindowDataIndex();

		self:CreateWindowData(sessionWindowIndex);
	end
end

function BlizzMeterMixin:CanHideSessionWindow(sessionWindow)
	if sessionWindow == nil then
		return false;
	end

	return self:GetPrimarySessionWindow() ~= sessionWindow;
end

function BlizzMeterMixin:CanMoveOrResizeSessionWindow(sessionWindow)
	if sessionWindow == nil then
		return false;
	end

	-- The size and location of the primary session window is controlled through edit mode.
	return self:GetPrimarySessionWindow() ~= sessionWindow;
end

function BlizzMeterMixin:HideSessionWindow(sessionWindow)
	if self:CanHideSessionWindow(sessionWindow) ~= true then
		return;
	end

	local sessionWindowIndex, windowData = self:GetSessionWindowData(sessionWindow);

	-- BlizzMeter: like Blizzard's, a window shown again later starts at its default position.
	windowData.position = nil;

	windowData.sessionWindow:Hide();

	SetSavedWindowData(sessionWindowIndex, windowData);
end

function BlizzMeterMixin:HideAllSessionWindows()
	-- Hides all session windows except for the primary one, which can't be hidden.
	self:ForEachSessionWindow(function(sessionWindow) self:HideSessionWindow(sessionWindow); end);
end

function BlizzMeterMixin:SetSessionWindowDamageMeterType(sessionWindow, damageMeterType)
	local sessionWindowIndex, windowData = self:GetSessionWindowData(sessionWindow);

	windowData.damageMeterType = damageMeterType;

	SetSavedWindowData(sessionWindowIndex, windowData);

	sessionWindow:SetDamageMeterType(damageMeterType);
end

function BlizzMeterMixin:GetSessionWindowDamageMeterType(sessionWindow)
	local _, windowData = self:GetSessionWindowData(sessionWindow);
	return windowData.damageMeterType;
end

function BlizzMeterMixin:SetSessionWindowSessionID(sessionWindow, sessionType, sessionID)
	local sessionWindowIndex, windowData = self:GetSessionWindowData(sessionWindow);

	windowData.sessionType = sessionType;
	windowData.sessionID = sessionID;

	SetSavedWindowData(sessionWindowIndex, windowData);

	sessionWindow:SetSession(sessionType, sessionID);
end

function BlizzMeterMixin:GetSessionType()
	return self.sessionType;
end

function BlizzMeterMixin:GetSessionID()
	return self.sessionID;
end

function BlizzMeterMixin:SetSessionWindowLocked(sessionWindow, locked)
	local sessionWindowIndex, windowData = self:GetSessionWindowData(sessionWindow);

	windowData.locked = locked;

	SetSavedWindowData(sessionWindowIndex, windowData);

	sessionWindow:SetLocked(locked);
end

function BlizzMeterMixin:SetSessionWindowNonInteractive(sessionWindow, nonInteractive)
	local sessionWindowIndex, windowData = self:GetSessionWindowData(sessionWindow);

	windowData.nonInteractive = nonInteractive;

	SetSavedWindowData(sessionWindowIndex, windowData);

	sessionWindow:SetNonInteractive(nonInteractive);
end

function BlizzMeterMixin:SetSessionWindowMinimized(sessionWindow, minimized)
	local sessionWindowIndex, windowData = self:GetSessionWindowData(sessionWindow);

	windowData.minimized = minimized;

	SetSavedWindowData(sessionWindowIndex, windowData);

	sessionWindow:SetMinimized(minimized);
end

function BlizzMeterMixin:OnUseClassColorChanged(useClassColor)
	self:ForEachSessionWindow(function(sessionWindow) sessionWindow:SetUseClassColor(useClassColor); end);
end

function BlizzMeterMixin:ShouldUseClassColor()
	return self.useClassColor;
end

function BlizzMeterMixin:SetUseClassColor(useClassColor)
	if self.useClassColor ~= useClassColor then
		self.useClassColor = useClassColor;
		self:OnUseClassColorChanged(useClassColor);
	end
end

function BlizzMeterMixin:OnBarHeightChanged(barHeight)
	self:ForEachSessionWindow(function(sessionWindow) sessionWindow:SetBarHeight(barHeight); end);
end

function BlizzMeterMixin:GetBarHeight()
	return self.barHeight or BLIZZMETER_DEFAULT_BAR_HEIGHT;
end

function BlizzMeterMixin:SetBarHeight(barHeight)
	if not ApproximatelyEqual(self:GetBarHeight(), barHeight) then
		self.barHeight = barHeight;
		self:OnBarHeightChanged(barHeight);
	end
end

function BlizzMeterMixin:OnTextScaleChanged(textScale)
	self:ForEachSessionWindow(function(sessionWindow) sessionWindow:SetTextScale(textScale); end);
end

function BlizzMeterMixin:GetTextScale()
	return self.textScale or 1;
end

function BlizzMeterMixin:SetTextScale(textScale)
	if not ApproximatelyEqual(self:GetTextScale(), textScale) then
		self.textScale = textScale;
		self:OnTextScaleChanged(textScale);
	end
end

function BlizzMeterMixin:GetTextSize()
	return self:GetTextScale() / BLIZZMETER_TEXT_SIZE_TO_SCALE_MULTIPLIER;
end

function BlizzMeterMixin:SetTextSize(textSize)
	self:SetTextScale(textSize * BLIZZMETER_TEXT_SIZE_TO_SCALE_MULTIPLIER);
end

function BlizzMeterMixin:OnWindowAlphaChanged(alpha)
	self:ForEachSessionWindow(function(sessionWindow) sessionWindow:SetAlpha(alpha); end);
end

function BlizzMeterMixin:GetWindowAlpha()
	return self.windowAlpha or 1;
end

function BlizzMeterMixin:SetWindowAlpha(alpha)
	if not ApproximatelyEqual(self:GetWindowAlpha(), alpha) then
		self.windowAlpha = alpha;
		self:OnWindowAlphaChanged(alpha);
	end
end

function BlizzMeterMixin:GetWindowTransparency()
	return self:GetWindowAlpha() / BLIZZMETER_TRANSPARENCY_TO_ALPHA_MULTIPLIER;
end

function BlizzMeterMixin:SetWindowTransparency(transparency)
	return self:SetWindowAlpha(transparency * BLIZZMETER_TRANSPARENCY_TO_ALPHA_MULTIPLIER);
end

function BlizzMeterMixin:OnShowBarIconsChanged(showBarIcons)
	self:ForEachSessionWindow(function(sessionWindow) sessionWindow:SetShowBarIcons(showBarIcons); end);
end

function BlizzMeterMixin:ShouldShowBarIcons()
	return self.showBarIcons;
end

function BlizzMeterMixin:SetShowBarIcons(showBarIcons)
	if self.showBarIcons ~= showBarIcons then
		self.showBarIcons = showBarIcons;
		self:OnShowBarIconsChanged(showBarIcons);
	end
end

function BlizzMeterMixin:OnBarSpacingChanged(spacing)
	self:ForEachSessionWindow(function(sessionWindow) sessionWindow:SetBarSpacing(spacing); end);
end

function BlizzMeterMixin:GetBarSpacing()
	return self.barSpacing or BLIZZMETER_DEFAULT_BAR_SPACING;
end

function BlizzMeterMixin:SetBarSpacing(spacing)
	if self.barSpacing ~= spacing then
		self.barSpacing = spacing;
		self:OnBarSpacingChanged(spacing);
	end
end

function BlizzMeterMixin:OnStyleChanged(style)
	self:ForEachSessionWindow(function(sessionWindow) sessionWindow:SetStyle(style); end);
end

function BlizzMeterMixin:GetStyle()
	return self.style or Enum.DamageMeterStyle.Default;
end

function BlizzMeterMixin:SetStyle(style)
	if self.style ~= style then
		self.style = style;
		self:OnStyleChanged(style);
	end
end

function BlizzMeterMixin:OnNumberDisplayTypeChanged(numberDisplayType)
	self:ForEachSessionWindow(function(sessionWindow) sessionWindow:SetNumberDisplayType(numberDisplayType); end);
end

function BlizzMeterMixin:GetNumberDisplayType()
	return self.numberDisplayType or Enum.DamageMeterNumbers.Minimal;
end

function BlizzMeterMixin:SetNumberDisplayType(numberDisplayType)
	if self.numberDisplayType ~= numberDisplayType then
		self.numberDisplayType = numberDisplayType;
		self:OnNumberDisplayTypeChanged(numberDisplayType);
	end
end

function BlizzMeterMixin:OnBackgroundAlphaChanged(alpha)
	self:ForEachSessionWindow(function(sessionWindow) sessionWindow:SetBackgroundAlpha(alpha); end);
end

function BlizzMeterMixin:GetBackgroundAlpha()
	return self.backgroundAlpha or 1;
end

function BlizzMeterMixin:SetBackgroundAlpha(alpha)
	if not ApproximatelyEqual(self:GetBackgroundAlpha(), alpha) then
		self.backgroundAlpha = alpha;
		self:OnBackgroundAlphaChanged(alpha);
	end
end

function BlizzMeterMixin:GetBackgroundTransparency()
	return self:GetBackgroundAlpha() / BLIZZMETER_TRANSPARENCY_TO_ALPHA_MULTIPLIER;
end

function BlizzMeterMixin:SetBackgroundTransparency(transparency)
	return self:SetBackgroundAlpha(transparency * BLIZZMETER_TRANSPARENCY_TO_ALPHA_MULTIPLIER);
end
