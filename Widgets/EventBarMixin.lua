local ADDON_NAME, ns = ...

CalendarPlus = CalendarPlus or {}

EventBarMixin = {}

-- Fixed on-screen width for the rounded end caps, regardless of the bar's
-- total width. The earlier version stretched one 32px-wide rounded-corner
-- mask across the whole bar (sometimes 700+px for a month-long span), which
-- blew the corner up into a huge diagonal streak instead of a tight round.
-- Capping the rounded art to a small fixed region and filling everything
-- between with a plain rectangle keeps the corner looking like a corner no
-- matter how wide the bar gets.
local CAP_WIDTH = 18

function EventBarMixin:OnPoolAcquire()
	self:SetHeight(CalendarPlus.Layout.LANE_HEIGHT)

	-- RoundMaskLeft/Right.tga are white-with-alpha sprites (opaque inside the
	-- rounded shape, transparent outside), so they can be tinted and shown
	-- directly like any other texture -- no masking needed for these caps.
	self.capLeft = self.capLeft or self:CreateTexture(nil, "ARTWORK")
	self.capLeft:SetTexture("Interface\\AddOns\\CalendarPlus\\Media\\RoundMaskLeft")

	self.capRight = self.capRight or self:CreateTexture(nil, "ARTWORK")
	self.capRight:SetTexture("Interface\\AddOns\\CalendarPlus\\Media\\RoundMaskRight")

	self.fill = self.fill or self:CreateTexture(nil, "ARTWORK")
	self.fill:SetColorTexture(1, 1, 1, 1)

	-- Thin gold top/bottom edge accent (same treatment as FilterChipMixin's
	-- chips), giving the bar a framed, ornate-parchment feel instead of a
	-- flat solid-color block. Drawn on a higher ARTWORK sublevel so it sits
	-- above the fill/caps.
	self.edgeTop = self.edgeTop or self:CreateTexture(nil, "ARTWORK", nil, 1)
	self.edgeTop:SetHeight(1)
	self.edgeTop:SetPoint("TOPLEFT")
	self.edgeTop:SetPoint("TOPRIGHT")
	self.edgeBottom = self.edgeBottom or self:CreateTexture(nil, "ARTWORK", nil, 1)
	self.edgeBottom:SetHeight(1)
	self.edgeBottom:SetPoint("BOTTOMLEFT")
	self.edgeBottom:SetPoint("BOTTOMRIGHT")
	local accent = CalendarPlus.Colors.surface.accent
	self.edgeTop:SetColorTexture(accent.r, accent.g, accent.b, 1)
	self.edgeBottom:SetColorTexture(accent.r, accent.g, accent.b, 1)

	self.label = self.label or self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	self.label:SetPoint("LEFT", 4, 0)
	self.label:SetPoint("RIGHT", -4, 0)
	self.label:SetJustifyH("LEFT")
	-- Default WordWrap left the label free to grow past the bar's fixed
	-- 18px height on long single-day titles ("Auction House Dance Party"),
	-- spilling text into the lanes above/below it. MaxLines(1) with
	-- WordWrap on keeps it to one line and truncates with "..." instead.
	self.label:SetWordWrap(true)
	self.label:SetMaxLines(1)
end

-- segment: { colStart, colEnd, lane, isStart, isEnd, category, displayTitle,
-- colorOverride, isSingleDay, isPadding } -- displayTitle is always the
-- final, already-resolved title (Timewalking/PvP enrichment happens once at
-- cache-build time, see CalendarProvider). Color priority: an explicit
-- colorOverride (expansion/faction-specific) wins first, then single-day
-- events get a flat coral regardless of category (except "custom" --
-- player-made events are nearly always one day long, so lumping them in
-- here too would defeat the point of them having their own distinct
-- color), then the plain category color. isPadding (a faded preview of an
-- adjacent month's events on the grid's leading/trailing padding days) dims
-- whatever color was chosen.
function EventBarMixin:SetData(segment, colWidth, headerHeight)
	self.categoryKey = segment.category
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
	self.edgeTop:SetAlpha(0.35 * alpha)
	self.edgeBottom:SetAlpha(0.35 * alpha)

	self.capLeft:ClearAllPoints()
	self.capRight:ClearAllPoints()
	self.fill:ClearAllPoints()

	-- A rounded cap draws only on the side that's a real start/end; a side
	-- cut off by the week row (isStart/isEnd false) stays flush and square,
	-- so the fill just runs all the way to that edge instead.
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

	self.fill:SetPoint("TOPLEFT", leftInset, 0)
	self.fill:SetPoint("BOTTOMRIGHT", -rightInset, 0)

	self:Show()
end

function EventBarMixin:Reset()
	self:ClearAllPoints()
	self.capLeft:Hide()
	self.capRight:Hide()
	self:Hide()
end
