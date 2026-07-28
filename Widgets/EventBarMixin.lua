local ADDON_NAME, ns = ...

CalendarPlus = CalendarPlus or {}

EventBarMixin = {}

-- Fixed on-screen width for the diamond/chevron end caps, regardless of the
-- bar's total width -- same fixed-cap-plus-stretchable-fill technique used
-- throughout this addon, so a pointed end stays a crisp point no matter how
-- wide the bar gets, instead of distorting when stretched. 12 matches the
-- source art's own proportions (an 8px-wide taper against its 12px-tall
-- source cap) scaled up to this bar's LANE_HEIGHT.
local CAP_WIDTH = 12

-- CleanFullBarFill.tga/BarTextureFill.tga's own native width in pixels --
-- needed to convert an on-screen fill width into how many texture repeats
-- to tile. Settled on after browsing every file in Media/ live via a
-- (since-removed) Settings dropdown that let each be compared in place.
local FILL_TILE_WIDTH = 245

function EventBarMixin:OnPoolAcquire()
	self:SetHeight(CalendarPlus.Layout.LANE_HEIGHT)
	self:EnableMouse(true)
	-- Day cells and event bars are sibling frames under the same week row,
	-- and a day cell's own height spans the whole row (not just its header),
	-- so it fully overlaps every bar drawn beneath it. Both default to the
	-- same frame level as plain same-parent siblings, which left mouse
	-- hit-testing to an unspecified tie-break that was landing on the day
	-- cell -- explicitly raising bars above their row guarantees they win
	-- clicks in their own area regardless of creation order.
	self:SetFrameLevel(self:GetParent():GetFrameLevel() + 2)
	self:SetScript("OnMouseUp", function(owner, button)
		if button == "LeftButton" then
			CalendarPlus.ShowEventInfo(owner.startSerial, owner.eventIndex)
		elseif button == "RightButton" then
			CalendarPlus.ShowEventContextMenu(owner, owner.startSerial, owner.eventIndex)
		end
	end)

	-- CleanFullBarCapLeft/Right.tga -- cropped from the user-supplied
	-- CleanFullBar.tga (a plain, textureless chevron-pointed bar shape with
	-- a subtle bevel; see Media/crop_cleanbar.py) -- white-with-alpha
	-- sprites, so they can be tinted and shown directly like any other
	-- texture, no masking needed. Unlike the earlier StatusBarCapLeft/Right,
	-- these carry no baked-in grain themselves -- that's layered separately
	-- via self.grain below, from a texture file meant specifically to sit
	-- on top of a clean bar rather than being part of it.
	self.capLeft = self.capLeft or self:CreateTexture(nil, "ARTWORK")
	self.capLeft:SetTexture("Interface\\AddOns\\CalendarPlus\\Media\\CleanFullBarCapLeft")

	self.capRight = self.capRight or self:CreateTexture(nil, "ARTWORK")
	self.capRight:SetTexture("Interface\\AddOns\\CalendarPlus\\Media\\CleanFullBarCapRight")

	-- CleanFullBarFill.tga -- used as the fill's own base texture (tinted
	-- per-category via vertex color same as a flat color would be) instead
	-- of a plain flat rectangle, so the fill itself already carries some
	-- texture before the BarTextureFill.tga grain (below) layers on top of it.
	self.fill = self.fill or self:CreateTexture(nil, "ARTWORK")
	self.fill:SetTexture("Interface\\AddOns\\CalendarPlus\\Media\\CleanFullBarFill", "REPEAT", "CLAMP")

	-- BarTextureFill.tga (cropped from the user-supplied BarTexture.tga, see
	-- Media/crop_cleanbar.py) layered over the flat fill as a grain accent,
	-- rather than being the bar's own shape -- scoped to exactly the fill
	-- rectangle's own bounds (set alongside it in SetData) so it never
	-- overhangs past the pointed caps on either end. Plain alpha blend (the
	-- default) is correct here -- unlike the earlier StatusBarFill.tga
	-- (which was light/near-white and needed MOD/multiply blend instead),
	-- this one is black with sparse, low alpha, so normal blending just
	-- darkens the cracks/speckle it actually covers and leaves the rest of
	-- the fill untouched.
	self.grain = self.grain or self:CreateTexture(nil, "ARTWORK", nil, 1)
	self.grain:SetTexture("Interface\\AddOns\\CalendarPlus\\Media\\BarTextureFill", "REPEAT", "CLAMP")

	-- Plain Frames (unlike FilterChipMixin's Buttons) don't get the
	-- automatic "HIGHLIGHT layer shows on hover" behavior, so this needs
	-- explicit OnEnter/OnLeave scripts instead -- same technique as
	-- DayCellMixin's own hover highlight. Sits above the fill/caps/edge
	-- accent but below the label so the title stays readable while hovering.
	-- StatusBarHighlight.tga is a solid warm-gold bar; ADD blend gives a
	-- glow effect (brightens without darkening/tinting) instead of a flat
	-- overlay tint.
	self.hoverHighlight = self.hoverHighlight or self:CreateTexture(nil, "ARTWORK", nil, 3)
	self.hoverHighlight:SetTexture("Interface\\AddOns\\CalendarPlus\\Media\\StatusBarHighlight")
	self.hoverHighlight:SetBlendMode("ADD")
	self.hoverHighlight:SetAllPoints()
	self.hoverHighlight:SetAlpha(0.35)
	self.hoverHighlight:Hide()
	self:SetScript("OnEnter", function(owner) owner.hoverHighlight:Show() end)
	self:SetScript("OnLeave", function(owner) owner.hoverHighlight:Hide() end)

	-- Thin gold top/bottom edge accent (same treatment as FilterChipMixin's
	-- chips), giving the bar a framed, ornate-parchment feel instead of a
	-- flat solid-color block. Drawn on a higher ARTWORK sublevel so it sits
	-- above the fill/caps/grain.
	self.edgeTop = self.edgeTop or self:CreateTexture(nil, "ARTWORK", nil, 2)
	self.edgeTop:SetHeight(1)
	self.edgeTop:SetPoint("TOPLEFT")
	self.edgeTop:SetPoint("TOPRIGHT")
	self.edgeBottom = self.edgeBottom or self:CreateTexture(nil, "ARTWORK", nil, 2)
	self.edgeBottom:SetHeight(1)
	self.edgeBottom:SetPoint("BOTTOMLEFT")
	self.edgeBottom:SetPoint("BOTTOMRIGHT")
	local accent = CalendarPlus.Colors.surface.accent
	self.edgeTop:SetColorTexture(accent.r, accent.g, accent.b, 1)
	self.edgeBottom:SetColorTexture(accent.r, accent.g, accent.b, 1)

	-- Both anchors are set per-segment in SetData instead of fixed here (see
	-- leftInset there) -- the sharper diamond point (unlike the old rounded
	-- cap) reads as visually "pointing into" text that starts too close to
	-- it, so the label needs to clear the whole cap width plus a small gap
	-- on sides that actually show one, not just a flat 4px.
	self.label = self.label or self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
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
	-- Stashed for the click handler above -- see CalendarPlus.ShowEventInfo
	-- (Data/DayContextMenu.lua), which needs to know exactly which
	-- C_Calendar day+index this bar represents to reopen it.
	self.startSerial = segment.startSerial
	self.eventIndex = segment.eventIndex
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
	self.grain:SetAlpha(alpha)

	self.capLeft:ClearAllPoints()
	self.capRight:ClearAllPoints()
	self.fill:ClearAllPoints()
	self.grain:ClearAllPoints()

	-- A pointed cap draws only on the side that's a real start/end; a side
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

	self.label:ClearAllPoints()
	self.label:SetPoint("LEFT", leftInset + 4, 0)
	self.label:SetPoint("RIGHT", -4, 0)

	self.fill:SetPoint("TOPLEFT", leftInset, 0)
	self.fill:SetPoint("BOTTOMRIGHT", -rightInset, 0)

	-- Grain matches the fill's own bounds exactly (never the caps), so it
	-- never overhangs past the pointed ends. Both the fill texture and
	-- BarTextureFill.tga (the grain layered on top) are standalone tileable
	-- strips (see crop_cleanbar.py); repeating them across the fill's
	-- actual on-screen width (rather than stretching one copy) keeps the
	-- texture reading as a consistent surface instead of a smeared blur on
	-- wide, multi-day bars.
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
