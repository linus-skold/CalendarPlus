local ADDON_NAME, ns = ...

CalendarPlus = CalendarPlus or {}

EventBarMixin = {}

-- Fixed width for the diamond/chevron end caps so a pointed end stays crisp
-- regardless of the bar's total width, instead of distorting when stretched.
local CAP_WIDTH = 12

-- CleanFullBarFill.tga/BarTextureFill.tga's native width in pixels, needed to
-- convert an on-screen fill width into a texture repeat count.
local FILL_TILE_WIDTH = 245

function EventBarMixin:OnPoolAcquire()
	self:SetHeight(CalendarPlus.Layout.LANE_HEIGHT)
	self:EnableMouse(true)
	-- Day cells span the whole row and overlap bars drawn beneath them, so bars
	-- must be raised above the row's frame level to win mouse hit-testing.
	self:SetFrameLevel(self:GetParent():GetFrameLevel() + 2)
	self:SetScript("OnMouseUp", function(owner, button)
		if button == "LeftButton" then
			CalendarPlus.ShowEventInfo(owner.startSerial, owner.eventID)
		elseif button == "RightButton" then
			CalendarPlus.ShowEventContextMenu(owner, owner.startSerial, owner.eventID)
		end
	end)

	self.capLeft = self.capLeft or self:CreateTexture(nil, "ARTWORK")
	self.capLeft:SetTexture("Interface\\AddOns\\CalendarPlus\\Media\\CleanFullBarCapLeft")

	self.capRight = self.capRight or self:CreateTexture(nil, "ARTWORK")
	self.capRight:SetTexture("Interface\\AddOns\\CalendarPlus\\Media\\CleanFullBarCapRight")

	self.fill = self.fill or self:CreateTexture(nil, "ARTWORK")
	self.fill:SetTexture("Interface\\AddOns\\CalendarPlus\\Media\\CleanFullBarFill", "REPEAT", "CLAMP")

	-- Grain layered over the flat fill, scoped to the fill rectangle's bounds
	-- (set in SetData) so it never overhangs past the pointed caps.
	self.grain = self.grain or self:CreateTexture(nil, "ARTWORK", nil, 1)
	self.grain:SetTexture("Interface\\AddOns\\CalendarPlus\\Media\\BarTextureFill", "REPEAT", "CLAMP")

	-- Plain Frames don't get automatic HIGHLIGHT-layer hover behavior, so this
	-- needs explicit OnEnter/OnLeave scripts. ADD blend gives a glow effect.
	self.hoverHighlight = self.hoverHighlight or self:CreateTexture(nil, "ARTWORK", nil, 3)
	self.hoverHighlight:SetTexture("Interface\\AddOns\\CalendarPlus\\Media\\StatusBarHighlight")
	self.hoverHighlight:SetBlendMode("ADD")
	self.hoverHighlight:SetAllPoints()
	self.hoverHighlight:SetAlpha(0.35)
	self.hoverHighlight:Hide()
	self:SetScript("OnEnter", function(owner) owner.hoverHighlight:Show() end)
	self:SetScript("OnLeave", function(owner) owner.hoverHighlight:Hide() end)

	-- Anchors are set per-segment in SetData (see leftInset there), since the
	-- label needs to clear the cap width on whichever sides show one.
	-- Created before the label so it draws behind it in the OVERLAY layer.
	self.labelShadow = self.labelShadow or self:CreateTexture(nil, "OVERLAY")
	self.labelShadow:SetTexture("Interface\\AddOns\\CalendarPlus\\Media\\TextDropShadow")

	self.label = self.label or self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	self.label:SetJustifyH("LEFT")
	-- WordWrap + MaxLines(1) truncates long titles with "..." instead of
	-- growing past the bar's fixed height and spilling into other lanes.
	self.label:SetWordWrap(true)
	self.label:SetMaxLines(1)
end

-- segment: { colStart, colEnd, lane, isStart, isEnd, category, displayTitle,
-- colorOverride, isSingleDay, isPadding }. Color priority: colorOverride,
-- then single-day flat color (except "custom"), then the category color.
-- isPadding dims whatever color was chosen (adjacent-month preview days).
function EventBarMixin:SetData(segment, colWidth, headerHeight)
	self.categoryKey = segment.category
	self.startSerial = segment.startSerial
	self.eventID = segment.eventID
	local color = segment.colorOverride
		or (segment.isSingleDay and segment.category ~= "custom" and CalendarPlus.Colors.singleDay)
		or CalendarPlus.Colors[segment.category]
		or CalendarPlus.Colors.default
	self.label:SetText(segment.displayTitle or "")

	local Layout = CalendarPlus.Layout
	local yOffset = (headerHeight or Layout.DAY_HEADER_HEIGHT) + (segment.lane - 1) * (Layout.LANE_HEIGHT + Layout.LANE_GAP)
	local width = (segment.colEnd - segment.colStart + 1) * colWidth

	self:ClearAllPoints()
	self:SetPoint("TOPLEFT", segment.colStart * colWidth, -yOffset)
	self:SetWidth(width)

	local alpha = segment.isPadding and 0.45 or 1
	self.capLeft:SetVertexColor(color.r, color.g, color.b, alpha)
	self.capRight:SetVertexColor(color.r, color.g, color.b, alpha)
	self.fill:SetVertexColor(color.r, color.g, color.b, alpha)
	self.label:SetAlpha(alpha)
	self.grain:SetAlpha(alpha)

	self.capLeft:ClearAllPoints()
	self.capRight:ClearAllPoints()
	self.fill:ClearAllPoints()
	self.grain:ClearAllPoints()

	-- A pointed cap draws only on a real start/end; a side cut off by the week
	-- row stays flush and square, with the fill running to that edge instead.
	local leftInset = 0
	if segment.isStart then
		self.capLeft:Show()
		self.capLeft:SetSize(CAP_WIDTH, Layout.LANE_HEIGHT)
		self.capLeft:SetPoint("TOPLEFT", self, "TOPLEFT")
		leftInset = CAP_WIDTH
	else
		self.capLeft:Hide()
	end

	local rightInset = 0
	if segment.isEnd then
		self.capRight:Show()
		self.capRight:SetSize(CAP_WIDTH, Layout.LANE_HEIGHT)
		self.capRight:SetPoint("TOPRIGHT", self, "TOPRIGHT")
		rightInset = CAP_WIDTH
	else
		self.capRight:Hide()
	end

	self.label:ClearAllPoints()
	self.label:SetPoint("LEFT", leftInset + 4, 0)
	self.label:SetPoint("RIGHT", -4, 0)

	-- Anchored to the label's rect (not the bar's) so it tracks leftInset.
	-- Padded a few px past the label's tight bounds so the shadow's soft
	-- falloff isn't cropped off at the letters' edges.
	self.labelShadow:ClearAllPoints()
	self.labelShadow:SetPoint("TOPLEFT", self.label, "TOPLEFT", -2, 2)
	self.labelShadow:SetPoint("BOTTOMRIGHT", self.label, "BOTTOMRIGHT", 4, -3)
	self.labelShadow:SetAlpha(alpha)

	self.fill:SetPoint("TOPLEFT", leftInset, 0)
	self.fill:SetPoint("BOTTOMRIGHT", -rightInset, 0)

	-- Repeating the tileable fill/grain textures across the fill's actual
	-- width (rather than stretching one copy) avoids a smeared look on wide,
	-- multi-day bars.
	local fillWidth = width - leftInset - rightInset
	self.fill:SetTexCoord(0, fillWidth / FILL_TILE_WIDTH, 0, 1)

	self.grain:SetPoint("TOPLEFT", leftInset, 0)
	self.grain:SetPoint("BOTTOMRIGHT", -rightInset, 0)
	self.grain:SetTexCoord(0, fillWidth / FILL_TILE_WIDTH, 0, 1)

	self:Show()
end

function EventBarMixin:Reset()
	self:ClearAllPoints()
	self.capLeft:Hide()
	self.capRight:Hide()
	self.hoverHighlight:Hide()
	self:Hide()
end
