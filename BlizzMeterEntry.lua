local _, BlizzMeterPrivate = ...;
local IsSecret = BlizzMeterPrivate.IsSecret;
local StatusBarInterpolation = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut;

BlizzMeterEntryMixin = {};

function BlizzMeterEntryMixin:GetIcon()
	return self.Icon.Icon;
end

function BlizzMeterEntryMixin:GetStatusBar()
	return self.StatusBar;
end

function BlizzMeterEntryMixin:GetStatusBarTexture()
	return self:GetStatusBar():GetStatusBarTexture();
end

function BlizzMeterEntryMixin:GetName()
	return self:GetStatusBar().Name;
end

function BlizzMeterEntryMixin:GetValue()
	return self:GetStatusBar().Value;
end

function BlizzMeterEntryMixin:GetBackground()
	return self:GetStatusBar().Background;
end

function BlizzMeterEntryMixin:GetBackgroundEdge()
	return self:GetStatusBar().BackgroundEdge;
end

function BlizzMeterEntryMixin:GetBackgroundRegions()
	return self:GetStatusBar().BackgroundRegions;
end

function BlizzMeterEntryMixin:GetIconAtlasElement()
	-- Override as necessary.
end

function BlizzMeterEntryMixin:GetIconTexture()
	-- Override as necessary.
end

-- BlizzMeter: iconShape is one of the BLIZZMETER_ICON_SHAPE_* constants.
function BlizzMeterEntryMixin:SetIconShape(iconShape)
	if iconShape == self.iconShape then
		return;
	end

	self.iconShape = iconShape;

	local icon = self:GetIcon();
	local mask = self.Icon.Mask;
	local masked = iconShape ~= BLIZZMETER_ICON_SHAPE_SQUARE;
	local showRing = iconShape == BLIZZMETER_ICON_SHAPE_RING;

	if masked then
		local inset = showRing and BLIZZMETER_ICON_RING_INSET or 0;
		mask:ClearAllPoints();
		mask:SetPoint("TOPLEFT", inset, -inset);
		mask:SetPoint("BOTTOMRIGHT", -inset, inset);
	end

	if masked ~= (self.iconMasked == true) then
		self.iconMasked = masked;
		if masked then
			icon:AddMaskTexture(mask);
		else
			icon:RemoveMaskTexture(mask);
		end
	end

	self.Icon.Ring:SetShown(showRing);
end

function BlizzMeterEntryMixin:UpdateIcon()
	-- BlizzMeter: class atlases and spec icons take the shape chosen in the options; spell icons stay square.
	local atlasElement = self:GetIconAtlasElement();
	local isClassIcon = atlasElement ~= nil or (self.specIconID ~= nil and self.specIconID ~= 0);
	self:SetIconShape(isClassIcon and BlizzMeterPrivate.Options.Get("iconShape") or BLIZZMETER_ICON_SHAPE_SQUARE);

	if atlasElement then
		if atlasElement ~= self.iconAtlasElement then
			self.iconAtlasElement = atlasElement;
			self.iconTexture = nil;
			self:GetIcon():SetAtlas(atlasElement);
		end
	else
		local texture = self:GetIconTexture();
		if texture then
			-- BlizzMeter: spell textures looked up from secret spell IDs are secret and can't be compared.
			if IsSecret(texture) or IsSecret(self.iconTexture) or texture ~= self.iconTexture then
				self.iconTexture = texture;
				self.iconAtlasElement = nil;
				self:GetIcon():SetTexture(texture);
			end
		else
			self.iconAtlasElement = nil;
			self.iconTexture = nil;
			self:GetIcon():SetTexture(nil);
		end
	end
end

function BlizzMeterEntryMixin:GetClassificationAtlasElement()
	-- Using same logic as NamePlateClassificationFrameMixin
	if self.classification == "elite" or self.classification == "worldboss" then
		return "nameplates-icon-elite-gold";
	elseif self.classification == "rare" then
		return "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Star";
	elseif self.classification == "rareelite" then
		return "nameplates-icon-elite-silver";
	end

	return nil;
end

function BlizzMeterEntryMixin:GetSourceTypeAtlasElement()
	-- When class color is off, the bars are colored by source type and don't need an icon to indicate teams.
	if not self.isClassColorDesired then
		return nil;
	end

	-- BlizzMeter: source display type and faction are secret in combat, so the team icon is left off until then.
	if IsSecret(self.sourceDisplayType) or IsSecret(self.factionGroup) then
		return nil;
	end

	-- Only show icons for members of the enemy team.
	if self.sourceDisplayType == Enum.DamageMeterSourceDisplayType.Enemy then
		if self.factionGroup == PLAYER_FACTION_GROUP[0] then
			return "HordeSymbol";
		elseif self.factionGroup == PLAYER_FACTION_GROUP[1] then
			return "AllianceSymbol";
		end
	end

	return nil;
end

function BlizzMeterEntryMixin:GetNameText()
	-- Override as necessary.
end

function BlizzMeterEntryMixin:UpdateName()
	local text = self:GetNameText();
	-- BlizzMeter: names can be secret and can't be compared, so secret text is always reapplied.
	if IsSecret(text) or IsSecret(self.nameText) or text ~= self.nameText then
		self.nameText = text;
		self:GetName():SetText(text);
	end
end

function BlizzMeterEntryMixin:ShowsValuePerSecondAsPrimary()
	return self.showsValuePerSecondAsPrimary == true;
end

local function GetEntryValueText(value, parentheticalValue, percentageValue)
	if parentheticalValue and percentageValue then
		return DAMAGE_METER_ENTRY_FORMAT_COMPLETE:format(AbbreviateLargeNumbers(value), AbbreviateLargeNumbers(parentheticalValue), Round(percentageValue * 100));
	elseif percentageValue then
		return DAMAGE_METER_ENTRY_FORMAT_COMPLETE_NO_PARENTHESIS:format(AbbreviateLargeNumbers(value), Round(percentageValue * 100));
	elseif parentheticalValue then
		return DAMAGE_METER_ENTRY_FORMAT_COMPACT:format(AbbreviateLargeNumbers(value), AbbreviateLargeNumbers(parentheticalValue));
	else
		return DAMAGE_METER_ENTRY_FORMAT_MINIMAL:format(AbbreviateLargeNumbers(value));
	end
end

local function GetMainValue(entry)
	if entry.valuePerSecond and entry:ShowsValuePerSecondAsPrimary() then
		return entry.valuePerSecond;
	end

	if entry.value then
		return entry.value;
	end

	return 0;
end

local function GetParentheticalValue(entry)
	if entry.value and entry:ShowsValuePerSecondAsPrimary() then
		return entry.value;
	end

	if entry.suppressValuePerSecond then
		return nil;
	end

	if entry.valuePerSecond then
		return entry.valuePerSecond;
	end

	return 0;
end

local function GetPercentageValue(entry)
	-- BlizzMeter: a percentage needs arithmetic, which addon code can't do on secret values. Returning nil
	-- drops it from the text (Complete shows like Compact) until combat ends and the values are readable.
	if IsSecret(entry.value) or IsSecret(entry.sessionTotalValue) then
		return nil;
	end

	if entry.value and entry.sessionTotalValue and entry.sessionTotalValue > 0 then
		return entry.value / entry.sessionTotalValue;
	end

	return 0;
end

local numberDisplayTypeFormatters =
{
	[Enum.DamageMeterNumbers.Minimal] = function(entry) return GetEntryValueText(GetMainValue(entry)); end,
	[Enum.DamageMeterNumbers.Compact] = function(entry) return GetEntryValueText(GetMainValue(entry), GetParentheticalValue(entry)); end,
	[Enum.DamageMeterNumbers.Complete] = function(entry) return GetEntryValueText(GetMainValue(entry), GetParentheticalValue(entry), GetPercentageValue(entry)); end,
}

function BlizzMeterEntryMixin:GetValueText()
	return numberDisplayTypeFormatters[self:GetNumberDisplayType()](self);
end

function BlizzMeterEntryMixin:UpdateValue()
	local text = self:GetValueText();
	self:GetValue():SetText(text);
end

function BlizzMeterEntryMixin:GetMaxStatusValue()
	return self.maxValue or 0;
end

function BlizzMeterEntryMixin:GetStatusValue()
	return self.value or 0;
end

function BlizzMeterEntryMixin:UpdateStatusBar()
	self:GetStatusBar():SetMinMaxValues(0, self:GetMaxStatusValue());
	-- BlizzMeter: optionally eases the fill toward the new value instead of snapping. The interpolation is done
	-- by the widget itself, so it works on secret values where addon code couldn't animate them by hand.
	if StatusBarInterpolation and BlizzMeterPrivate.Options.Get("smoothBars") then
		self:GetStatusBar():SetValue(self:GetStatusValue(), StatusBarInterpolation);
	else
		self:GetStatusBar():SetValue(self:GetStatusValue());
	end
end

function BlizzMeterEntryMixin:SetupSharedStyleAnchors()
	self:GetStatusBar():ClearAllPoints();
	self:GetName():ClearAllPoints();
	self:GetValue():ClearAllPoints();
end

function BlizzMeterEntryMixin:GetIconAttachmentAnchor()
	local point = "LEFT";
	local relativeTo = self;
	local relativePoint = "LEFT";
	local x = 0;
	local y = 0;

	if self:ShouldShowBarIcons() then
		local style = self:GetStyle();

		relativeTo = self:GetIcon();
		relativePoint = "RIGHT";

		if style == Enum.DamageMeterStyle.Bordered or style == Enum.DamageMeterStyle.Thin then
			x = 5;
		end
	end

	return point, relativeTo, relativePoint, x, y;
end

function BlizzMeterEntryMixin:GetBackgroundAtlasForStyle(style)
	if style == Enum.DamageMeterStyle.Bordered then
		return "UI-HUD-CoolDownManager-Bar-BG";
	else
		return "ui-damagemeters-bar-shadowbg";
	end
end

function BlizzMeterEntryMixin:GetBackgroundInsetsForStyle(style)
	-- Returns are left, top, right, bottom anchor point offsets.

	if style == Enum.DamageMeterStyle.Bordered then
		return -2, 2, 6, -7;
	else
		return -2, 2, 2, -2;
	end
end

function BlizzMeterEntryMixin:GetBackgroundEdgeVisibilityForStyle(style)
	if style == Enum.DamageMeterStyle.Bordered then
		return false;
	else
		return true;
	end
end

function BlizzMeterEntryMixin:SetupSharedStyleIconVisibility()
	-- BlizzMeter: hides the icon's container rather than just the icon texture, so the ring goes with it.
	self.Icon:SetShown(self:ShouldShowBarIcons());
end

function BlizzMeterEntryMixin:SetupSharedStyleBackground()
	local style = self:GetStyle();
	local left, top, right, bottom = self:GetBackgroundInsetsForStyle(style);

	local background = self:GetBackground();
	local backgroundEdge = self:GetBackgroundEdge();

	background:ClearAllPoints();
	background:SetPoint("TOPLEFT", left, top);
	background:SetPoint("BOTTOMRIGHT", right, bottom);
	background:SetAtlas(self:GetBackgroundAtlasForStyle(style));

	backgroundEdge:SetShown(self:GetBackgroundEdgeVisibilityForStyle(style));
end

function BlizzMeterEntryMixin:SetupDefaultStyle()
	self:SetupSharedStyleAnchors();
	self:SetupSharedStyleBackground();
	self:SetupSharedStyleIconVisibility();

	local name = self:GetName();
	local statusBar = self:GetStatusBar();
	local value = self:GetValue();

	statusBar:SetPoint(self:GetIconAttachmentAnchor());
	statusBar:SetPoint("TOP", 0, -1);
	statusBar:SetPoint("BOTTOMRIGHT", -4, 1);

	name:SetPoint("LEFT", 2, 0);
	name:SetPoint("RIGHT", self:GetValue(), "LEFT", -25, 0);

	value:SetPoint("RIGHT", -3, 0);
end

function BlizzMeterEntryMixin:SetupBorderedStyle()
	self:SetupDefaultStyle();
end

function BlizzMeterEntryMixin:SetupFullBackgroundStyle()
	self:SetupDefaultStyle();
end

function BlizzMeterEntryMixin:SetupThinStyle()
	self:SetupSharedStyleAnchors();
	self:SetupSharedStyleBackground();
	self:SetupSharedStyleIconVisibility();

	local name = self:GetName();
	local statusBar = self:GetStatusBar();
	local value = self:GetValue();

	statusBar:SetPoint(self:GetIconAttachmentAnchor());
	statusBar:SetPoint("TOP", name, "BOTTOM", 0, 0);
	statusBar:SetPoint("BOTTOMRIGHT", 0, 1);

	name:SetPoint("TOP", self, "TOP", 0, 0);
	name:SetPoint(self:GetIconAttachmentAnchor());
	name:SetPoint("RIGHT", value, "LEFT", -25, 0);

	value:SetPoint("TOP", self, "TOP", 0, 0);
	value:SetPoint("RIGHT", self, "RIGHT", -3, 0);
end

function BlizzMeterEntryMixin:UpdateStyle()
	local style = self:GetStyle();

	if style == Enum.DamageMeterStyle.Default then
		self:SetupDefaultStyle();
	elseif style == Enum.DamageMeterStyle.Bordered then
		self:SetupBorderedStyle();
	elseif style == Enum.DamageMeterStyle.FullBackground then
		self:SetupFullBackgroundStyle();
	elseif style == Enum.DamageMeterStyle.Thin then
		self:SetupThinStyle();
	else
		assertsafe(false, "unhandled damage meter style: %s", style);
	end
end

function BlizzMeterEntryMixin:GetDefaultStatusBarColor()
	return DAMAGE_METER_STATUS_BAR_DEFAULT_COLOR;
end

function BlizzMeterEntryMixin:GetCreatureStatusBarColor()
	return DAMAGE_METER_STATUS_BAR_CREATURE_COLOR;
end

function BlizzMeterEntryMixin:GetAllyStatusBarColor()
	return DAMAGE_METER_STATUS_BAR_ALLY_COLOR;
end

function BlizzMeterEntryMixin:GetEnemyStatusBarColor()
	return DAMAGE_METER_STATUS_BAR_ENEMY_COLOR;
end

function BlizzMeterEntryMixin:GetStatusBarColor()
	local r, g, b = self:GetStatusBarTexture():GetVertexColor();
	return CreateColor(r, g, b);
end

function BlizzMeterEntryMixin:SetStatusBarColor(color)
	if color ~= self.statusBarColor then
		self.statusBarColor = color;
		self:GetStatusBarTexture():SetVertexColor(color:GetRGB());
	end
end

function BlizzMeterEntryMixin:GetDesiredBarColor()
	if self.isClassColorDesired then
		if self:IsCreature() then
			return self:GetCreatureStatusBarColor();
		end

		local classFilename = self.classFilename or self.unitClassFilename;
		if classFilename then
			return RAID_CLASS_COLORS[classFilename] or self:GetDefaultStatusBarColor();
		end
	else
		-- BlizzMeter: with class colors off, every bar uses the Bar Color option instead of Blizzard's default,
		-- ally and enemy colors.
		return BlizzMeterPrivate.Options.GetColor("barColor");
	end

	return self:GetDefaultStatusBarColor();
end

function BlizzMeterEntryMixin:SetUseClassColor(useClassColor)
	self.isClassColorDesired = useClassColor;
	self:UpdateStatusBarColor();
end

function BlizzMeterEntryMixin:UpdateStatusBarColor()
	self:SetStatusBarColor(self:GetDesiredBarColor());
end

function BlizzMeterEntryMixin:GetBarHeight()
	return self:GetHeight();
end

function BlizzMeterEntryMixin:SetBarHeight(barHeight)
	self:SetHeight(barHeight);
end

function BlizzMeterEntryMixin:GetTextScale()
	-- We assume that all fontstrings are re-scaled equally. If this one day
	-- changes, SetTextScale should instead store the size as a field that can
	-- be returned here.

	return self:GetName():GetTextScale();
end

function BlizzMeterEntryMixin:SetTextScale(textScale)
	self:GetName():SetTextScale(textScale);
	self:GetValue():SetTextScale(textScale);
end

function BlizzMeterEntryMixin:ShouldShowBarIcons()
	return self.showBarIcons;
end

function BlizzMeterEntryMixin:SetShowBarIcons(showBarIcons)
	self.showBarIcons = (showBarIcons == true);
	self:UpdateStyle();
end

function BlizzMeterEntryMixin:GetStyle()
	return self.style or Enum.DamageMeterStyle.Default;
end

function BlizzMeterEntryMixin:SetStyle(style)
	self.style = style;
	self:UpdateBackground();
	self:UpdateStyle();
end

function BlizzMeterEntryMixin:GetNumberDisplayType()
	return self.numberDisplayType or Enum.DamageMeterNumbers.Minimal;
end

function BlizzMeterEntryMixin:SetNumberDisplayType(numberDisplayType)
	self.numberDisplayType = numberDisplayType;
	self:UpdateValue();
end

function BlizzMeterEntryMixin:GetBackgroundAlpha()
	return self.backgroundAlpha or 1;
end

function BlizzMeterEntryMixin:SetBackgroundAlpha(alpha)
	self.backgroundAlpha = alpha;
	self:UpdateBackground();
end

function BlizzMeterEntryMixin:GetBackgroundRegionAlpha()
	--[[
	-- Previous behavior
	local style = self:GetStyle();

	if style == Enum.DamageMeterStyle.FullBackground then
		-- The full background style uses a background asset on the parent
		-- frame instead.
		return 0;
	elseif style == Enum.DamageMeterStyle.Bordered then
		-- Art for the bordered style reuses an asset that doesn't permit
		-- customization of background transparency.
		return 1;
	else
		return self:GetBackgroundAlpha();
	end
	--]]

	return 1; -- Only controlled by container frame opacity now.
end

function BlizzMeterEntryMixin:UpdateBackground()
	local alpha = self:GetBackgroundRegionAlpha();

	for _, region in ipairs(self:GetBackgroundRegions()) do
		region:SetAlpha(alpha);
	end
end

-- BlizzMeter: turns the font's outline and drop shadow on or off for the name and value text. The font's own
-- flags and shadow offset are remembered the first time so they can be restored.
function BlizzMeterEntryMixin:UpdateTextOutline()
	local textOutline = BlizzMeterPrivate.Options.Get("textOutline");
	if textOutline == self.textOutline then
		return;
	end

	self.textOutline = textOutline;

	for _, fontString in ipairs({ self:GetName(), self:GetValue() }) do
		if not fontString.originalFontFlags then
			local _fontFile, _fontHeight, fontFlags = fontString:GetFont();
			fontString.originalFontFlags = fontFlags or "";
			fontString.originalShadowX, fontString.originalShadowY = fontString:GetShadowOffset();
		end

		local fontFile, fontHeight = fontString:GetFont();
		if textOutline then
			fontString:SetFont(fontFile, fontHeight, fontString.originalFontFlags);
			fontString:SetShadowOffset(fontString.originalShadowX, fontString.originalShadowY);
		else
			fontString:SetFont(fontFile, fontHeight, "");
			fontString:SetShadowOffset(0, 0);
		end
	end
end

-- BlizzMeter: colors the name and value text. Color codes inside the text (eg. class-colored unit names in the
-- spell breakdown) still take precedence.
function BlizzMeterEntryMixin:UpdateTextColor()
	local textColor = BlizzMeterPrivate.Options.Get("textColor");
	if textColor == self.textColor then
		return;
	end

	self.textColor = textColor;

	local r, g, b = CreateColorFromHexString(textColor):GetRGB();
	self:GetName():SetTextColor(r, g, b);
	self:GetValue():SetTextColor(r, g, b);
end

function BlizzMeterEntryMixin:Init(source)
	self.value = source.totalAmount;
	self.valuePerSecond = source.amountPerSecond;
	self.maxValue = source.maxAmount;
	self.sessionTotalValue = source.sessionTotalAmount;
	self.index = source.index;
	self.showsValuePerSecondAsPrimary = source.showsValuePerSecondAsPrimary;

	self:UpdateTextOutline();
	self:UpdateTextColor();
	self:UpdateIcon();
	self:UpdateName();
	self:UpdateValue();
	self:UpdateStatusBar();
	self:UpdateStatusBarColor();
end

function BlizzMeterEntryMixin:IsCreature()
	return false;
end

BlizzMeterSourceEntryMixin = {}

-- BlizzMeter: removes the realm from player names ("Name-Realm" -> "Name") unless the options say to show realms.
-- Ambiguate accepts secret names, so this also works in combat. Only used for players, since NPC names can contain
-- hyphens (eg. "Ra-den").
local function StripRealm(name)
	if BlizzMeterPrivate.Options.Get("showRealmNames") then
		return name;
	end

	return Ambiguate(name, "short");
end

function BlizzMeterSourceEntryMixin:Init(combatSource)
	-- BlizzMeter: player sources are the ones without a creature ID (a boolean test is allowed on the secret ID).
	if combatSource.name and not combatSource.sourceCreatureID then
		self.sourceName = StripRealm(combatSource.name);
	else
		self.sourceName = combatSource.name;
	end
	self.isLocalPlayer = combatSource.isLocalPlayer;
	self.classFilename = combatSource.classFilename;
	self.specIconID = combatSource.specIconID;
	self.deathRecapID = combatSource.deathRecapID;
	self.deathTimeSeconds = combatSource.deathTimeSeconds;

	 -- Creatures, but not those treated as players for display (who will have classFilename like players)
	-- BlizzMeter: sourceCreatureID is secret in combat. It can't be compared to nil, but a boolean test is allowed.
	self.isCreature = (combatSource.sourceCreatureID and true or false) and (self.classFilename == '');

	self.classification = combatSource.classification;
	self.suppressValuePerSecond = combatSource.suppressValuePerSecond;
	self.sourceDisplayType = combatSource.sourceDisplayType;
	self.factionGroup = combatSource.factionGroup;
	self:SetSuppressIcon(combatSource.suppressIcon);

	BlizzMeterEntryMixin.Init(self, combatSource);
end

function BlizzMeterSourceEntryMixin:SetSuppressIcon(suppressIcon)
	if self.suppressIcon ~= suppressIcon then
		self.suppressIcon = suppressIcon;
		self:UpdateStyle();
	end
end

function BlizzMeterSourceEntryMixin:IsCreature()
	return self.isCreature;
end

function BlizzMeterSourceEntryMixin:GetIconAtlasElement()
	-- If spec is set it takes precedence over class.
	if self.specIconID and self.specIconID ~= 0 then
		return nil;
	end

	if not self.classFilename or #self.classFilename == 0 then
		return nil;
	end

	return GetClassAtlas(self.classFilename);
end

function BlizzMeterEntryMixin:GetIconTexture()
	if self.specIconID == 0 then
		return nil;
	end

	return self.specIconID;
end

function BlizzMeterEntryMixin:GetFormattedSourceNameText()
	-- Insert the classification image if its provided.
	local classificationAtlasElement = self:GetClassificationAtlasElement();
	if classificationAtlasElement then
		local atlasMarkup = CreateAtlasMarkup(classificationAtlasElement);
		return string.format("%s %s", atlasMarkup, self.sourceName);
	end

	local sourceTypeAtlasElement = self:GetSourceTypeAtlasElement();
	if sourceTypeAtlasElement then
		local atlasMarkup = CreateAtlasMarkup(sourceTypeAtlasElement);
		return string.format("%s %s", atlasMarkup, self.sourceName);
	end

	return self.sourceName;
end

function BlizzMeterSourceEntryMixin:GetNameText()
	if self.deathRecapID and self.deathRecapID ~= 0 then
		return self.sourceName;
	end

	local formattedSourceName = self:GetFormattedSourceNameText();
	return DAMAGE_METER_SOURCE_NAME:format(self.index, formattedSourceName);
end

function BlizzMeterSourceEntryMixin:GetMaxStatusValue()
	if self.deathRecapID and self.deathRecapID ~= 0 then
		return 1;
	end

	return BlizzMeterEntryMixin.GetMaxStatusValue(self);
end

function BlizzMeterSourceEntryMixin:GetStatusValue()
	if self.deathRecapID and self.deathRecapID ~= 0 then
		return 1;
	end

	return BlizzMeterEntryMixin.GetStatusValue(self);
end

-- Format death time as "3m 22s"
local deathTimeFormatter = CreateFromMixins(SecondsFormatterMixin);
deathTimeFormatter:Init(0, SecondsFormatter.Abbreviation.OneLetter, false, false);
deathTimeFormatter:SetDesiredUnitCount(2);
deathTimeFormatter:SetMinInterval(SecondsFormatter.Interval.Seconds);

function BlizzMeterSourceEntryMixin:GetValueText()
	if self.deathRecapID and self.deathRecapID ~= 0 then
		-- BlizzMeter: the death time is secret in combat and can't be formatted; it fills in once combat ends.
		if IsSecret(self.deathTimeSeconds) then
			return "";
		end

		-- no timestamps for overall session
		if self.deathTimeSeconds == -1 then
			return "";
		end

		local totalSeconds = self.deathTimeSeconds or 0;
		return deathTimeFormatter:Format(totalSeconds);
	end

	return BlizzMeterEntryMixin.GetValueText(self);
end

function BlizzMeterSourceEntryMixin:ShouldShowBarIcons()
	if self.suppressIcon then
		return false;
	end

	return BlizzMeterEntryMixin.ShouldShowBarIcons(self);
end

BlizzMeterSpellEntryMixin = {};

function BlizzMeterSpellEntryMixin:Init(combatSpell)
	self.spellID = combatSpell.spellID;
	self.creatureName = combatSpell.creatureName;
	self.unitName = combatSpell.combatSpellDetails.unitName;
	self.classification = combatSpell.combatSpellDetails.classification;
	self.unitClassFilename = combatSpell.combatSpellDetails.unitClassFilename;

	-- BlizzMeter: remove the realm from player unit names (eg. damage taken from a player). Units with a class are players.
	if self.unitName and self.unitClassFilename and #self.unitClassFilename > 0 then
		self.unitName = StripRealm(self.unitName);
	end
	self.isPet = combatSpell.combatSpellDetails.isPet;
	self.isMob = combatSpell.combatSpellDetails.isMob;
	self.classFilename = combatSpell.classFilename;
	self.specIconID = combatSpell.combatSpellDetails.specIconID;

	BlizzMeterEntryMixin.Init(self, combatSpell);

	self:GetIcon():SetScript("OnEnter", function()
		if self.spellID then
			local tooltip = GetAppropriateTooltip();
			GameTooltip_SetDefaultAnchor(tooltip, self:GetIcon());

			local isPet = false;
			tooltip:SetSpellByID(self.spellID, isPet);

			tooltip:Show();
		end
	end);

	self:GetIcon():SetScript("OnLeave", function()
		GetAppropriateTooltip():Hide();
	end);
end

function BlizzMeterSpellEntryMixin:IsCreature()
	-- BlizzMeter: isPet and isMob are secret booleans in combat, which addon code can't test.
	if IsSecret(self.isPet) or IsSecret(self.isMob) then
		return false;
	end

	return not self.isPet and self.isMob;
end

function BlizzMeterSpellEntryMixin:GetSpellID()
	return self.spellID;
end

function BlizzMeterSpellEntryMixin:GetIconAtlasElement()
	-- If spec is set it takes precedence over class.
	if self.specIconID and self.specIconID ~= 0 then
		return nil;
	end

	if not self.unitClassFilename or #self.unitClassFilename == 0 then
		return nil;
	end

	return GetClassAtlas(self.unitClassFilename);
end

function BlizzMeterSpellEntryMixin:GetIconTexture()
	if self.specIconID and self.specIconID ~= 0 then
		return self.specIconID;
	end

	if not self.spellID then
		return nil;
	end

	return C_Spell.GetSpellTexture(self.spellID);
end

function BlizzMeterSpellEntryMixin:GetUnitNameText()
	-- Color the text by class color if its provided.
	if self.unitClassFilename and #self.unitClassFilename > 0 then
		local classColor = RAID_CLASS_COLORS[self.unitClassFilename];
		if classColor then
			return classColor:WrapTextInColorCode(self.unitName);
		end
	end

	return self.unitName;
end

function BlizzMeterSpellEntryMixin:GetFormattedUnitNameText()
	local unitNameText = self:GetUnitNameText();

	-- Insert the classification image if its provided.
	local classificationAtlasElement = self:GetClassificationAtlasElement();
	if classificationAtlasElement then
		local atlasMarkup = CreateAtlasMarkup(classificationAtlasElement);
		return string.format("%s %s", atlasMarkup, unitNameText);
	end

	return unitNameText;
end

-- BlizzMeter: splits a "%s<infix>%s<suffix>" format string into its infix and suffix. Returns nil for any
-- other shape (eg. a localization that reorders its arguments).
local function SplitTwoStringFormat(formatString)
	local infix, suffix = formatString:match("^%%s(.-)%%s(.*)$");
	if infix and not infix:find("%", 1, true) and not suffix:find("%", 1, true) then
		return infix, suffix;
	end

	return nil;
end

-- BlizzMeter: GetNameText for when the names are secret (in combat). Their length can't be checked, but
-- C_StringUtil.WrapString only adds a prefix/suffix around a non-empty string, which reproduces the
-- pet ("Spell (Pet)") and unit ("Spell - Unit") formats without inspecting the names.
function BlizzMeterSpellEntryMixin:GetSecretNameText(spellName)
	local creatureInfix, creatureSuffix = SplitTwoStringFormat(DAMAGE_METER_SPELL_ENTRY_CREATURE);
	local unitInfix, unitSuffix = SplitTwoStringFormat(DAMAGE_METER_SPELL_ENTRY_UNIT);
	if not creatureInfix or not unitInfix then
		return spellName;
	end

	local unitPrefix = unitInfix;
	local classificationAtlasElement = self:GetClassificationAtlasElement();
	if classificationAtlasElement then
		unitPrefix = unitPrefix .. CreateAtlasMarkup(classificationAtlasElement) .. " ";
	end

	local classColor = self.unitClassFilename and #self.unitClassFilename > 0 and RAID_CLASS_COLORS[self.unitClassFilename];
	if classColor then
		unitPrefix = unitPrefix .. classColor:GenerateHexColorMarkup();
		unitSuffix = "|r" .. unitSuffix;
	end

	local creatureText = C_StringUtil.WrapString(self.creatureName or "", creatureInfix, creatureSuffix);
	local unitText = C_StringUtil.WrapString(self.unitName or "", unitPrefix, unitSuffix);
	return (spellName or "") .. creatureText .. unitText;
end

function BlizzMeterSpellEntryMixin:GetNameText()
	if not self.spellID then
		return nil;
	end

	local spellName = C_Spell.GetSpellName(self.spellID);

	-- BlizzMeter: the length checks below can't be done on secret names.
	if IsSecret(spellName) or IsSecret(self.creatureName) or IsSecret(self.unitName) then
		return self:GetSecretNameText(spellName);
	end

	-- Special formatting for pets.
	if self.creatureName and #self.creatureName > 0 then
		return DAMAGE_METER_SPELL_ENTRY_CREATURE:format(spellName, self.creatureName);
	end

	-- Special formatting for when another unit is the subject and the player is the object (e.g. damage taken)
	if self.unitName and #self.unitName > 0 then
		local formattedUnitName = self:GetFormattedUnitNameText();
		if spellName and #spellName > 0 then
			return DAMAGE_METER_SPELL_ENTRY_UNIT:format(spellName, formattedUnitName);
		end

		return formattedUnitName;
	end

	return spellName;
end

function BlizzMeterSpellEntryMixin:GetNumberDisplayType()
	return Enum.DamageMeterNumbers.Complete;
end
