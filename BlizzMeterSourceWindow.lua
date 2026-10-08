local _, BlizzMeterPrivate = ...;
local IsSecret = BlizzMeterPrivate.IsSecret;
local AccessibleTableOrNil = BlizzMeterPrivate.AccessibleTableOrNil;

BlizzMeterSourceWindowMixin = {};

local BlizzMeterSourceWindowMixinEvents = {
	"GLOBAL_MOUSE_DOWN",
};

-- BlizzMeter: C_DamageMeter only accepts secret GUIDs and creature IDs from untainted code. A source clicked
-- in combat has a secret identity, so only the local player can still be looked up (by their own GUID).
-- Returns whether the source can be queried, followed by the GUID and creature ID to query it with.
local function GetQueryableSourceIdentity(sourceGUID, sourceCreatureID, isLocalPlayer)
	if not IsSecret(sourceGUID) and not IsSecret(sourceCreatureID) then
		return true, sourceGUID, sourceCreatureID;
	end

	if isLocalPlayer then
		local playerGUID = UnitGUID("player");
		if playerGUID and not IsSecret(playerGUID) then
			return true, playerGUID, nil;
		end
	end

	return false;
end

function BlizzMeterSourceWindowMixin.CanShowSource(source)
	return (GetQueryableSourceIdentity(source.sourceGUID, source.sourceCreatureID, source.isLocalPlayer));
end

function BlizzMeterSourceWindowMixin:GetScrollBox()
	return self.ScrollBox;
end

function BlizzMeterSourceWindowMixin:GetScrollBar()
	return self.ScrollBar;
end

function BlizzMeterSourceWindowMixin:GetResizeButton()
	return self.ResizeButton;
end

function BlizzMeterSourceWindowMixin:GetBackground()
	return self.Background;
end

function BlizzMeterSourceWindowMixin:GetCloseButton()
	return self.CloseButton;
end

function BlizzMeterSourceWindowMixin:OnLoad()
	self:InitializeScrollBox();
	self:InitializeResizeButton();
	self:InitializeCloseButton();
end

function BlizzMeterSourceWindowMixin:OnShow()
	FrameUtil.RegisterFrameForEvents(self, BlizzMeterSourceWindowMixinEvents);

	self:Refresh(ScrollBoxConstants.DiscardScrollPosition);
end

function BlizzMeterSourceWindowMixin:OnHide()
	FrameUtil.UnregisterFrameForEvents(self, BlizzMeterSourceWindowMixinEvents);

	self:ClearSource();
end

function BlizzMeterSourceWindowMixin:OnEvent(event, ...)
	if event == "GLOBAL_MOUSE_DOWN" then
		if not self:IsSticky() and not DoesAncestryIncludeAny(self, GetMouseFoci()) then
			self:Hide();
		end
	end
end

function BlizzMeterSourceWindowMixin:OnEnter()
	-- Handle showing the ResizeButton under the correct conditions.
	self:SetScript("OnUpdate", function()
		local resizeButton = self:GetResizeButton();
		local shouldResizeButtonBeShown = (self:IsMouseOver() or resizeButton:IsMouseOver() or self:IsResizing());

		if shouldResizeButtonBeShown and resizeButton:GetAlpha() == 0 then
			self.ShowResizeButton:Play();
			self.EmphasizeScrollBar:Play();
		elseif not shouldResizeButtonBeShown and resizeButton:GetAlpha() > 0 then
			self:SetScript("OnUpdate", nil);

			local reverse = true;
			self.ShowResizeButton:Play(reverse);
			self.EmphasizeScrollBar:Play(reverse);
		end
	end);
end

function BlizzMeterSourceWindowMixin:InitializeScrollBoxPadding(view)
	local topPadding, bottomPadding, leftPadding, rightPadding = 0, 0, 0, 0;
	local elementSpacing = self:GetBarSpacing();

	view:SetPadding(topPadding, bottomPadding, leftPadding, rightPadding, elementSpacing);
end

function BlizzMeterSourceWindowMixin:InitializeScrollBox()
	local view = CreateScrollBoxListLinearView();
	view:SetElementInitializer("BlizzMeterSpellEntryTemplate", function(frame, elementData)
		frame:Init(elementData);
		frame:SetUseClassColor(self:ShouldUseClassColor());
		frame:SetBarHeight(self:GetBarHeight());
		frame:SetTextScale(self:GetTextScale());
		frame:SetShowBarIcons(self:ShouldShowBarIcons());
		frame:SetStyle(self:GetStyle());
		frame:SetBackgroundAlpha(self:GetBackgroundAlpha());
	end);

	self:InitializeScrollBoxPadding(view);
	ScrollUtil.InitScrollBoxListWithScrollBar(self:GetScrollBox(), self:GetScrollBar(), view);

	local topLeftX, topLeftY = 20, -15;
	local bottomRightX, bottomRightY = -22, 17;
	local withBarXOffset = 20;
	local scrollBoxAnchorsWithBar = {
		CreateAnchor("TOPLEFT", self:GetBackground(), "TOPLEFT", topLeftX, topLeftY),
		CreateAnchor("BOTTOMRIGHT", bottomRightX - withBarXOffset, bottomRightY);
	};
	local scrollBoxAnchorsWithoutBar = {
		CreateAnchor("TOPLEFT", self:GetBackground(), "TOPLEFT", topLeftX, topLeftY),
		CreateAnchor("BOTTOMRIGHT", bottomRightX, bottomRightY);
	};
	ScrollUtil.AddManagedScrollBarVisibilityBehavior(self:GetScrollBox(), self:GetScrollBar(), scrollBoxAnchorsWithBar, scrollBoxAnchorsWithoutBar);
end

function BlizzMeterSourceWindowMixin:IsSticky()
	return self.isSticky;
end

function BlizzMeterSourceWindowMixin:SetSticky(sticky)
	self.isSticky = sticky;
	self:GetCloseButton():SetShown(sticky);
end

function BlizzMeterSourceWindowMixin:InitializeCloseButton()
	self:GetCloseButton():SetScript("OnClick", function()
		self:Hide();
	end);
end

function BlizzMeterSourceWindowMixin:InitializeResizeButton()
	local resizeButton = self:GetResizeButton();

	resizeButton:SetScript("OnMouseDown", function(button, mouseButtonName, _down)
		if mouseButtonName == "LeftButton" then
			button:SetButtonState("PUSHED", true);
			button:GetHighlightTexture():Hide();

			if self:IsRightSide() then
				self:StartSizing("BOTTOMRIGHT");
			else
				self:StartSizing("BOTTOMLEFT");
			end

			self.isResizing = true;
		end
	end);

	resizeButton:SetScript("OnMouseUp", function(button, mouseButtonName, _down)
		if mouseButtonName == "LeftButton" then
			button:SetButtonState("NORMAL", false);
			button:GetHighlightTexture():Show();
			self:StopMovingOrSizing();
			self:SetUserPlaced(false);
			self.isResizing = false;
		end
	end);

	resizeButton:SetScript("OnEnter", function()
		self:OnEnter();
	end);
end

function BlizzMeterSourceWindowMixin:GetCombatSessionSource()
	local damageMeterType = self:GetDamageMeterType();

	-- BlizzMeter: query with an identity addon code is allowed to pass (see GetQueryableSourceIdentity), and
	-- treat a result table that addon code isn't allowed to read as no result.
	local canQuery, sourceGUID, sourceCreatureID = GetQueryableSourceIdentity(self.sourceGUID, self.sourceCreatureID, self.isLocalPlayer);
	if not canQuery then
		return nil;
	end

	local sessionType = self:GetSessionType();
	if sessionType then
		return AccessibleTableOrNil(C_DamageMeter.GetCombatSessionSourceFromType(sessionType, damageMeterType, sourceGUID, sourceCreatureID));
	end

	local sessionID = self:GetSessionID();
	if sessionID then
		return AccessibleTableOrNil(C_DamageMeter.GetCombatSessionSourceFromID(sessionID, damageMeterType, sourceGUID, sourceCreatureID));
	end

	return nil;
end

function BlizzMeterSourceWindowMixin:ShowsValuePerSecondAsPrimary()
	return self.showsValuePerSecondAsPrimary == true;
end

function BlizzMeterSourceWindowMixin:BuildDataProvider()
	local combatSessionSource = self:GetCombatSessionSource();
	local combatSpells = combatSessionSource and combatSessionSource.combatSpells or {};
	local maxAmount = combatSessionSource and combatSessionSource.maxAmount or 0;
	local sessionTotalAmount = combatSessionSource and combatSessionSource.totalAmount or 0;
	local showsValuePerSecondAsPrimary = self:ShowsValuePerSecondAsPrimary();

	local dataProvider = CreateDataProvider();
	for i, combatSpell in ipairs(combatSpells) do
		combatSpell.classFilename = self.classFilename;
		combatSpell.maxAmount = maxAmount;
		combatSpell.sessionTotalAmount = sessionTotalAmount;
		combatSpell.index = i;
		combatSpell.showsValuePerSecondAsPrimary = showsValuePerSecondAsPrimary;

		dataProvider:Insert(combatSpell);
	end

	return dataProvider;
end

function BlizzMeterSourceWindowMixin:Refresh(retainScrollPosition)
	self:GetScrollBox():SetDataProvider(self:BuildDataProvider(), retainScrollPosition);
end

function BlizzMeterSourceWindowMixin:EnumerateEntryFrames()
	return self:GetScrollBox():EnumerateFrames();
end

function BlizzMeterSourceWindowMixin:ForEachEntryFrame(func, ...)
	for _index, frame in self:EnumerateEntryFrames() do
		func(frame, ...);
	end
end

function BlizzMeterSourceWindowMixin:GetEntryFrameCount()
	return self:GetScrollBox():GetFrameCount();
end

function BlizzMeterSourceWindowMixin:SetSource(source)
	self.sourceGUID = source.sourceGUID;
	self.sourceCreatureID = source.sourceCreatureID;
	self.totalAmount = source.totalAmount;
	self.sourceName = source.name;
	self.classFilename = source.classFilename;
	self.showsValuePerSecondAsPrimary = source.showsValuePerSecondAsPrimary;
	self.isLocalPlayer = source.isLocalPlayer; -- BlizzMeter: see GetQueryableSourceIdentity.
end

function BlizzMeterSourceWindowMixin:ClearSource()
	self.sourceGUID = nil;
	self.sourceCreatureID = nil;
	self.totalAmount = nil;
	self.sourceName = nil;
	self.classFilename = nil;
	self.showsValuePerSecondAsPrimary = nil;
	self.isLocalPlayer = nil;
end

-- BlizzMeter: returns nil (unknown) instead of false when a GUID or creature ID is secret and can't be compared.
function BlizzMeterSourceWindowMixin:IsShowingSource(source)
	if IsSecret(self.sourceGUID) or IsSecret(source.sourceGUID) or IsSecret(self.sourceCreatureID) or IsSecret(source.sourceCreatureID) then
		return nil;
	end

	if self.sourceGUID and self.sourceGUID == source.sourceGUID then
		return true;
	end

	if self.sourceCreatureID and self.sourceCreatureID == source.sourceCreatureID then
		return true;
	end

	return false;
end

function BlizzMeterSourceWindowMixin:GetTotalAmount()
	return self.totalAmount;
end

function BlizzMeterSourceWindowMixin:SetDamageMeterType(damageMeterType)
	self.damageMeterType = damageMeterType;
end

function BlizzMeterSourceWindowMixin:GetDamageMeterType()
	return self.damageMeterType;
end

function BlizzMeterSourceWindowMixin:SetSession(sessionType, sessionID)
	self.sessionType = sessionType;
	self.sessionID = sessionID;

	self:Refresh(ScrollBoxConstants.RetainScrollPosition);
end

function BlizzMeterSourceWindowMixin:GetSessionType()
	return self.sessionType;
end

function BlizzMeterSourceWindowMixin:GetSessionID()
	return self.sessionID;
end

function BlizzMeterSourceWindowMixin:IsResizing()
	return self.isResizing == true;
end

function BlizzMeterSourceWindowMixin:IsRightSide()
	return self.isRightSide == true;
end

function BlizzMeterSourceWindowMixin:AnchorToSessionWindow(sessionWindow)
	self:ClearAllPoints();

	local resizeButton = self:GetResizeButton();
	resizeButton:ClearAllPoints();

	local sessionWindowCenterX, sessionWindowCenterY = sessionWindow:GetCenter();
	local screenCenterX, _screenCenterY = UIParent:GetCenter();

	local needsBottomAnchor = false;

	-- Avoid resetting the height if the session window hasn't moved so if the player resizes the source window the height is preserved.
	if sessionWindowCenterX ~= self.previousSessionWindowCenterX or sessionWindowCenterY ~= self.previousSessionWindowCenterY then
		self.previousSessionWindowCenterX = sessionWindowCenterX;
		self.previousSessionWindowCenterY = sessionWindowCenterY;
		needsBottomAnchor = true;
	end

	-- Anchor in whatever direction has more room.
	if sessionWindowCenterX < screenCenterX then
		self.isRightSide = true;

		self:SetPoint("TOPLEFT", sessionWindow, "TOPRIGHT");

		if needsBottomAnchor then
			self:SetPoint("BOTTOMLEFT", sessionWindow, "BOTTOMRIGHT");
		end

		resizeButton:SetPoint("BOTTOMRIGHT", 1, 1);
		resizeButton:GetNormalTexture():SetTexCoord(0, 1, 0, 1);
		resizeButton:GetHighlightTexture():SetTexCoord(0, 1, 0, 1);
		resizeButton:GetPushedTexture():SetTexCoord(0, 1, 0, 1);
	else
		self.isRightSide = false;

		self:SetPoint("TOPRIGHT", sessionWindow, "TOPLEFT");

		if needsBottomAnchor then
			self:SetPoint("BOTTOMRIGHT", sessionWindow, "BOTTOMLEFT");
		end

		resizeButton:SetPoint("BOTTOMLEFT", -1, 1);
		resizeButton:GetNormalTexture():SetTexCoord(1, 0, 0, 1);
		resizeButton:GetHighlightTexture():SetTexCoord(1, 0, 0, 1);
		resizeButton:GetPushedTexture():SetTexCoord(1, 0, 0, 1);
	end

	self:Refresh(ScrollBoxConstants.DiscardScrollPosition);
end

function BlizzMeterSourceWindowMixin:OnUseClassColorChanged(useClassColor)
	self:GetScrollBox():ForEachFrame(function(frame) frame:SetUseClassColor(useClassColor); end);
end

function BlizzMeterSourceWindowMixin:ShouldUseClassColor()
	return self.useClassColor == true;
end

function BlizzMeterSourceWindowMixin:SetUseClassColor(useClassColor)
	useClassColor = (useClassColor == true);

	if self.useClassColor ~= useClassColor then
		self.useClassColor = useClassColor;
		self:OnUseClassColorChanged(useClassColor);
	end
end

function BlizzMeterSourceWindowMixin:OnBarHeightChanged(barHeight)
	self:GetScrollBox():GetView():SetElementExtent(barHeight);
	self:Refresh(ScrollBoxConstants.RetainScrollPosition);
end

function BlizzMeterSourceWindowMixin:GetBarHeight()
	return self.barHeight or BLIZZMETER_DEFAULT_BAR_HEIGHT;
end

function BlizzMeterSourceWindowMixin:SetBarHeight(barHeight)
	if not ApproximatelyEqual(self:GetBarHeight(), barHeight) then
		self.barHeight = barHeight;
		self:OnBarHeightChanged(barHeight);
	end
end

function BlizzMeterSourceWindowMixin:OnTextScaleChanged(textScale)
	self:GetScrollBox():ForEachFrame(function(frame) frame:SetTextScale(textScale); end);
end

function BlizzMeterSourceWindowMixin:GetTextScale()
	return self.textScale or 1;
end

function BlizzMeterSourceWindowMixin:SetTextScale(textScale)
	if not ApproximatelyEqual(self:GetTextScale(), textScale) then
		self.textScale = textScale;
		self:OnTextScaleChanged(textScale);
	end
end

function BlizzMeterSourceWindowMixin:OnShowBarIconsChanged(showBarIcons)
	self:ForEachEntryFrame(function(frame) frame:SetShowBarIcons(showBarIcons); end);
end

function BlizzMeterSourceWindowMixin:ShouldShowBarIcons()
	return self.showBarIcons == true;
end

function BlizzMeterSourceWindowMixin:SetShowBarIcons(showBarIcons)
	showBarIcons = (showBarIcons == true);

	if self.showBarIcons ~= showBarIcons then
		self.showBarIcons = showBarIcons;
		self:OnShowBarIconsChanged(showBarIcons);
	end
end

function BlizzMeterSourceWindowMixin:OnBarSpacingChanged(_spacing)
	self:InitializeScrollBoxPadding(self:GetScrollBox():GetView());
	self:Refresh(ScrollBoxConstants.RetainScrollPosition);
end

function BlizzMeterSourceWindowMixin:GetBarSpacing()
	return self.barSpacing or BLIZZMETER_DEFAULT_BAR_SPACING;
end

function BlizzMeterSourceWindowMixin:SetBarSpacing(spacing)
	if self.barSpacing ~= spacing then
		self.barSpacing = spacing;
		self:OnBarSpacingChanged(spacing);
	end
end

function BlizzMeterSourceWindowMixin:OnStyleChanged(style)
	self:ForEachEntryFrame(function(frame) frame:SetStyle(style); end);
end

function BlizzMeterSourceWindowMixin:GetStyle()
	return self.style or Enum.DamageMeterStyle.Default;
end

function BlizzMeterSourceWindowMixin:SetStyle(style)
	if self.style ~= style then
		self.style = style;
		self:OnStyleChanged(style);
	end
end

function BlizzMeterSourceWindowMixin:OnBackgroundAlphaChanged(alpha)
	self:ForEachEntryFrame(function(frame) frame:SetBackgroundAlpha(alpha); end);
end

function BlizzMeterSourceWindowMixin:GetBackgroundAlpha()
	return self.backgroundAlpha or 1;
end

function BlizzMeterSourceWindowMixin:SetBackgroundAlpha(alpha)
	if not ApproximatelyEqual(self:GetBackgroundAlpha(), alpha) then
		self.backgroundAlpha = alpha;
		self:OnBackgroundAlphaChanged(alpha);
	end
end

function BlizzMeterSourceWindowMixin:DoesCurrentStyleUseBackground()
	return self:GetStyle() == Enum.DamageMeterStyle.FullBackground;
end
