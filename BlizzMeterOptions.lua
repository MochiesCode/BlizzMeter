local addonName, BlizzMeterPrivate = ...;

-- BlizzMeter's options panel (Options > AddOns > BlizzMeter, or /bm).
--
-- The style options here replace the Damage Meter's Edit Mode settings, which can't be written from addon code
-- without tainting the Blizzard meter. Edit Mode still controls where the meter is and how big it is. On first
-- load each option starts from the Edit Mode layout's value, and the panel can copy them over again later.

-- Saved Variable (account-wide). Option key -> value. Options never set (or seeded from Edit Mode) are left nil.
BlizzMeterSettings = BlizzMeterSettings or nil;

local Options = {};
BlizzMeterPrivate.Options = Options;

local function ApplyRefreshEntries(meter)
	meter:RefreshEntries();
end

-- editModeSetting: the Edit Mode setting this option takes its first value from.
-- apply: pushes the value to the meter.
local OptionInfo = {
	visibility = {
		editModeSetting = Enum.EditModeDamageMeterSetting.Visibility,
		default = Enum.DamageMeterVisibility.Always,
		apply = function(meter, value) meter:SetVisibility(value); end,
	},
	style = {
		editModeSetting = Enum.EditModeDamageMeterSetting.Style,
		default = Enum.DamageMeterStyle.Default,
		apply = function(meter, value) meter:SetStyle(value); end,
	},
	numberDisplayType = {
		editModeSetting = Enum.EditModeDamageMeterSetting.Numbers,
		default = Enum.DamageMeterNumbers.Minimal,
		apply = function(meter, value) meter:SetNumberDisplayType(value); end,
	},
	barHeight = {
		editModeSetting = Enum.EditModeDamageMeterSetting.BarHeight,
		default = BLIZZMETER_DEFAULT_BAR_HEIGHT,
		apply = function(meter, value) meter:SetBarHeight(value); end,
	},
	barSpacing = {
		editModeSetting = Enum.EditModeDamageMeterSetting.Padding,
		default = BLIZZMETER_DEFAULT_BAR_SPACING,
		apply = function(meter, value) meter:SetBarSpacing(value); end,
	},
	transparency = {
		editModeSetting = Enum.EditModeDamageMeterSetting.Transparency,
		default = 100,
		apply = function(meter, value) meter:SetWindowTransparency(value); end,
	},
	backgroundTransparency = {
		editModeSetting = Enum.EditModeDamageMeterSetting.BackgroundTransparency,
		default = 100,
		apply = function(meter, value) meter:SetBackgroundTransparency(value); end,
	},
	textSize = {
		editModeSetting = Enum.EditModeDamageMeterSetting.TextSize,
		default = 100,
		apply = function(meter, value) meter:SetTextSize(value); end,
	},
	showSpecIcon = {
		editModeSetting = Enum.EditModeDamageMeterSetting.ShowSpecIcon,
		isBool = true,
		default = true,
		apply = function(meter, value) meter:SetShowBarIcons(value); end,
	},
	showClassColor = {
		editModeSetting = Enum.EditModeDamageMeterSetting.ShowClassColor,
		isBool = true,
		default = true,
		apply = function(meter, value) meter:SetUseClassColor(value); end,
	},
	iconShape = {
		default = BLIZZMETER_ICON_SHAPE_RING,
		apply = ApplyRefreshEntries,
	},
	showRealmNames = {
		default = false,
		apply = ApplyRefreshEntries,
	},
	textOutline = {
		default = true,
		apply = ApplyRefreshEntries,
	},
	pinLocalPlayer = {
		default = true,
		apply = ApplyRefreshEntries,
	},
	smoothBars = {
		default = true,
		apply = ApplyRefreshEntries,
	},
	textColor = {
		default = "ffffffff",
		apply = ApplyRefreshEntries,
	},
	-- Used for every bar while Show Class Color is off. Starts as Blizzard's default bar color.
	barColor = {
		default = function()
			return DAMAGE_METER_STATUS_BAR_DEFAULT_COLOR and DAMAGE_METER_STATUS_BAR_DEFAULT_COLOR:GenerateHexColor() or "ffffffff";
		end,
		apply = ApplyRefreshEntries,
	},
};

-- Settings panel setting objects, by option key. Changing a value through these keeps the panel's controls in sync.
local settingObjects = {};

local category;

local function GetSavedOptions()
	if type(BlizzMeterSettings) ~= "table" then
		BlizzMeterSettings = {};
	end

	return BlizzMeterSettings;
end

-- A default can be a function, for values that aren't available yet when this file loads.
local function GetDefault(key)
	local default = OptionInfo[key].default;
	if type(default) == "function" then
		return default();
	end

	return default;
end

function Options.Get(key)
	local value = GetSavedOptions()[key];
	if value == nil then
		return GetDefault(key);
	end

	return value;
end

local colorCache = {};

-- Returns a color option as a Color object. The same object is returned until the value changes.
function Options.GetColor(key)
	local hexColor = Options.Get(key);
	local cached = colorCache[key];
	if not cached or cached.hexColor ~= hexColor then
		cached = { hexColor = hexColor, color = CreateColorFromHexString(hexColor) };
		colorCache[key] = cached;
	end

	return cached.color;
end

function Options.Set(key, value)
	GetSavedOptions()[key] = value;

	local meter = BlizzMeter;
	if meter then
		OptionInfo[key].apply(meter, value);
		meter:RefreshLayout();
	end
end

-- Sets an option through its panel setting when there is one, so an open panel shows the new value.
local function SetOptionValue(key, value)
	local setting = settingObjects[key];
	if setting then
		setting:SetValue(value);
	else
		Options.Set(key, value);
	end
end

-- Pushes every option to the meter. Called while the meter loads, before its windows are created.
function Options.ApplyAll(meter)
	for key, info in pairs(OptionInfo) do
		info.apply(meter, Options.Get(key));
	end
end

local function GetEditModeValue(meter, info)
	if info.isBool then
		return meter:GetSettingValueBool(info.editModeSetting);
	end

	return meter:GetSettingValue(info.editModeSetting);
end

-- Called whenever the Blizzard meter applies an Edit Mode setting. The first value seen for an option becomes its
-- starting value; after that the option is BlizzMeter's own and Edit Mode changes no longer affect it.
function Options.AdoptEditModeSetting(meter, editModeSetting)
	for key, info in pairs(OptionInfo) do
		if info.editModeSetting == editModeSetting then
			if GetSavedOptions()[key] == nil then
				SetOptionValue(key, GetEditModeValue(meter, info));
			end
			return;
		end
	end
end

local function CanCopyFromEditMode(meter)
	local editModeSystem = meter and meter:GetEditModeSystem();
	return editModeSystem ~= nil and editModeSystem:IsInitialized();
end

-- Overwrites every option that has an Edit Mode counterpart with the current Edit Mode layout's value.
function Options.CopyFromEditMode()
	local meter = BlizzMeter;
	if not CanCopyFromEditMode(meter) then
		return;
	end

	for key, info in pairs(OptionInfo) do
		if info.editModeSetting and meter:GetEditModeSystem():HasSetting(info.editModeSetting) then
			SetOptionValue(key, GetEditModeValue(meter, info));
		end
	end
end

function Options.Open()
	if category then
		Settings.OpenToCategory(category:GetID());
	end
end

-- Settings panel

local function FormatAsPercentage(value)
	local roundToNearestInteger = true;
	return FormatPercentage(value / 100, roundToNearestInteger);
end

local function RegisterSetting(key, variableType, name)
	local variable = addonName .. "_" .. key;
	local setting = Settings.RegisterProxySetting(category, variable, variableType, name, GetDefault(key),
		function() return Options.Get(key); end,
		function(value) Options.Set(key, value); end);
	settingObjects[key] = setting;
	return setting;
end

local function AddDropdown(key, name, choices, tooltip)
	local setting = RegisterSetting(key, Settings.VarType.Number, name);

	local function GetOptions()
		local container = Settings.CreateControlTextContainer();
		for _, choice in ipairs(choices) do
			container:Add(choice.value, choice.text);
		end
		return container:GetData();
	end

	Settings.CreateDropdown(category, setting, GetOptions, tooltip);
end

local function AddSlider(key, name, minValue, maxValue, step, formatter, tooltip)
	local setting = RegisterSetting(key, Settings.VarType.Number, name);

	local options = Settings.CreateSliderOptions(minValue, maxValue, step);
	options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, formatter);

	Settings.CreateSlider(category, setting, options, tooltip);
end

local function AddCheckbox(key, name, tooltip)
	local setting = RegisterSetting(key, Settings.VarType.Boolean, name);
	return Settings.CreateCheckbox(category, setting, tooltip);
end

-- The value is an "AARRGGBB" hex string, which is what the settings panel's color swatch reads and writes.
local function AddColorSwatch(key, name, tooltip)
	local setting = RegisterSetting(key, Settings.VarType.String, name);
	return Settings.CreateColorSwatch(category, setting, tooltip);
end

-- Ranges and choices match the Damage Meter's entries in Blizzard_EditMode's EditModeSettingDisplayInfo.
local function RegisterOptionsPanel()
	local layout;
	local version = C_AddOns.GetAddOnMetadata(addonName, "Version");
	local title = version and (addonName .. " v" .. version) or addonName;
	category, layout = Settings.RegisterVerticalLayoutCategory(title);

	AddDropdown("style", HUD_EDIT_MODE_SETTING_DAMAGE_METER_STYLE, {
		{ value = Enum.DamageMeterStyle.Default, text = HUD_EDIT_MODE_SETTING_DAMAGE_METER_STYLE_DEFAULT },
		{ value = Enum.DamageMeterStyle.Bordered, text = HUD_EDIT_MODE_SETTING_DAMAGE_METER_STYLE_BORDERED },
		{ value = Enum.DamageMeterStyle.Thin, text = HUD_EDIT_MODE_SETTING_DAMAGE_METER_STYLE_THIN },
	});

	AddDropdown("numberDisplayType", HUD_EDIT_MODE_SETTING_DAMAGE_METER_NUMBERS, {
		{ value = Enum.DamageMeterNumbers.Minimal, text = HUD_EDIT_MODE_SETTING_DAMAGE_METER_NUMBERS_MINIMAL },
		{ value = Enum.DamageMeterNumbers.Compact, text = HUD_EDIT_MODE_SETTING_DAMAGE_METER_NUMBERS_COMPACT },
		{ value = Enum.DamageMeterNumbers.Complete, text = HUD_EDIT_MODE_SETTING_DAMAGE_METER_NUMBERS_COMPLETE },
	});

	AddSlider("barHeight", HUD_EDIT_MODE_SETTING_DAMAGE_METER_BAR_HEIGHT, 15, 40, 1, tostring);
	AddSlider("barSpacing", HUD_EDIT_MODE_SETTING_DAMAGE_METER_PADDING, 2, 10, 1, tostring);
	AddSlider("transparency", HUD_EDIT_MODE_SETTING_DAMAGE_METER_TRANSPARENCY, 50, 100, 1, FormatAsPercentage);
	AddSlider("backgroundTransparency", HUD_EDIT_MODE_SETTING_DAMAGE_METER_BACKGROUND, 0, 100, 1, FormatAsPercentage);
	AddSlider("textSize", HUD_EDIT_MODE_SETTING_DAMAGE_METER_TEXT_SIZE, 50, 150, 10, FormatAsPercentage);

	AddDropdown("visibility", HUD_EDIT_MODE_SETTING_DAMAGE_METER_VISIBILITY, {
		{ value = Enum.DamageMeterVisibility.Always, text = HUD_EDIT_MODE_SETTING_DAMAGE_METER_VISIBILITY_ALWAYS },
		{ value = Enum.DamageMeterVisibility.InCombat, text = HUD_EDIT_MODE_SETTING_DAMAGE_METER_VISIBILITY_IN_COMBAT },
		{ value = Enum.DamageMeterVisibility.Hidden, text = HUD_EDIT_MODE_SETTING_DAMAGE_METER_VISIBILITY_HIDDEN },
		{ value = Enum.DamageMeterVisibility.InGroup, text = HUD_EDIT_MODE_SETTING_DAMAGE_METER_VISIBILITY_IN_GROUP },
	});

	AddDropdown("iconShape", "Spec Icon Shape", {
		{ value = BLIZZMETER_ICON_SHAPE_SQUARE, text = "Square" },
		{ value = BLIZZMETER_ICON_SHAPE_CIRCLE, text = "Circle" },
		{ value = BLIZZMETER_ICON_SHAPE_RING, text = "Circle with Ring" },
	}, "Shape of the class and spec icons on the bars. Spell icons are always square.");

	AddCheckbox("showSpecIcon", HUD_EDIT_MODE_SETTING_DAMAGE_METER_SHOW_SPEC_ICON);
	local showClassColorInitializer = AddCheckbox("showClassColor", HUD_EDIT_MODE_SETTING_DAMAGE_METER_SHOW_CLASS_COLOR);

	-- Only shown while Show Class Color is off. Changing any setting makes the panel re-check this.
	local barColorInitializer = AddColorSwatch("barColor", "Bar Color", "Color of every bar while class colors are off.");
	barColorInitializer:SetParentInitializer(showClassColorInitializer);
	barColorInitializer:AddShownPredicate(function() return not Options.Get("showClassColor"); end);

	AddCheckbox("pinLocalPlayer", "Always Show Your Bar",
		"When your bar is scrolled out of view, pin it to the top or bottom edge of the window.");

	AddCheckbox("smoothBars", "Smooth Bar Animation",
		"Ease the bars toward their new values instead of jumping on each update.");

	AddCheckbox("showRealmNames", "Show Realm Names",
		"Show players from other realms as \"Name-Realm\" instead of just \"Name\".");

	AddCheckbox("textOutline", "Text Outline",
		"Draw the black outline and shadow around the names and numbers on the bars.");

	AddColorSwatch("textColor", "Text Color", "Color of the names and numbers on the bars.");

	local copyFromEditModeTooltip = "Replace the options that Edit Mode also has with the Damage Meter's settings from your current Edit Mode layout. Position and size always come from Edit Mode.";
	layout:AddInitializer(CreateSettingsButtonInitializer("Copy Edit Mode Settings", "Copy", Options.CopyFromEditMode, copyFromEditModeTooltip, true));

	Settings.RegisterAddOnCategory(category);
end

EventUtil.ContinueOnAddOnLoaded(addonName, RegisterOptionsPanel);

SLASH_BLIZZMETER1 = "/bm";
SlashCmdList["BLIZZMETER"] = Options.Open;
