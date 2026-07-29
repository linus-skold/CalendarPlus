local ADDON_NAME, ns = ...

CalendarPlus = CalendarPlus or {}

FilterChipMixin = {}

-- Same fixed-cap-plus-stretchable-fill technique as EventBarMixin's rounded
-- bars: a small end region at each side (native size, no stretching) and a
-- plain rectangle filling the rest, so it looks right at any chip width
-- instead of one mask stretched across the whole button. Now uses the same
-- CleanFullBar* art as the event bars (chevron caps + grain-textured fill)
-- instead of the old plain rounded-pill mask, so chips and bars read as the
-- same material.
local CAP_WIDTH = 12

-- Matches EventBarMixin's own FILL_TILE_WIDTH -- CleanFullBarFill.tga's
-- native width in pixels, needed to convert an on-screen fill width into how
-- many texture repeats to tile.
local FILL_TILE_WIDTH = 245

function FilterChipMixin:OnPoolAcquire()
	self.capLeft = self.capLeft or self:CreateTexture(nil, "BACKGROUND")
	self.capLeft:SetTexture("Interface\\AddOns\\CalendarPlus\\Media\\CleanFullBarCapLeft")
	self.capLeft:SetPoint("TOPLEFT")
	self.capLeft:SetPoint("BOTTOMLEFT")
	self.capLeft:SetWidth(CAP_WIDTH)

	self.capRight = self.capRight or self:CreateTexture(nil, "BACKGROUND")
	self.capRight:SetTexture("Interface\\AddOns\\CalendarPlus\\Media\\CleanFullBarCapRight")
	self.capRight:SetPoint("TOPRIGHT")
	self.capRight:SetPoint("BOTTOMRIGHT")
	self.capRight:SetWidth(CAP_WIDTH)

	self.fill = self.fill or self:CreateTexture(nil, "BACKGROUND")
	self.fill:SetTexture("Interface\\AddOns\\CalendarPlus\\Media\\CleanFullBarFill", "REPEAT", "CLAMP")
	self.fill:SetPoint("TOPLEFT", self.capLeft, "TOPRIGHT")
	self.fill:SetPoint("BOTTOMRIGHT", self.capRight, "BOTTOMLEFT")

	-- BarTextureFill.tga grain accent layered over the fill, same as
	-- EventBarMixin's bars -- sized/tiled to the fill's own bounds in
	-- SetData/Refresh below (see width plumbing there).
	self.grain = self.grain or self:CreateTexture(nil, "ARTWORK")
	self.grain:SetTexture("Interface\\AddOns\\CalendarPlus\\Media\\BarTextureFill", "REPEAT", "CLAMP")
	self.grain:SetPoint("TOPLEFT", self.capLeft, "TOPRIGHT")
	self.grain:SetPoint("BOTTOMRIGHT", self.capRight, "BOTTOMLEFT")

	-- A circular alpha sprite (same one used for the "today" badge) tinted
	-- per-category, instead of a plain colored square.
	self.dot = self.dot or self:CreateTexture(nil, "ARTWORK")
	self.dot:SetSize(8, 8)
	self.dot:SetPoint("LEFT", CAP_WIDTH, 0)
	self.dot:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")

	-- No truncation here -- the chip is sized (see BuildFilterChips) to fit
	-- the full label text, so this only needs a LEFT anchor.
	self.label = self.label or self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	self.label:SetPoint("LEFT", self.dot, "RIGHT", 4, 0)

	-- Any texture on the Button's HIGHLIGHT layer is shown/hidden
	-- automatically on mouseover -- no OnEnter/OnLeave scripting needed.
	-- Same StatusBarHighlight.tga + ADD blend as EventBarMixin's bars, for a
	-- consistent hover glow instead of a flat white overlay.
	self.highlight = self.highlight or self:CreateTexture(nil, "HIGHLIGHT")
	self.highlight:SetAllPoints()
	self.highlight:SetTexture("Interface\\AddOns\\CalendarPlus\\Media\\StatusBarHighlight")
	self.highlight:SetBlendMode("ADD")
	self.highlight:SetAlpha(0.35)

	self:SetScript("OnClick", function(owner)
		owner.active = not owner.active
		owner:Refresh()
		if owner.onToggle then
			owner.onToggle(owner.categoryKey, owner.active)
		end
	end)
end

function FilterChipMixin:SetData(categoryKey, label, onToggle)
	self.categoryKey = categoryKey
	self.active = true
	self.onToggle = onToggle
	self.label:SetText(label)
	local color = CalendarPlus.Colors[categoryKey] or CalendarPlus.Colors.default
	self.dot:SetVertexColor(color.r, color.g, color.b, 1)

	-- Chip width is already set (see BuildFilterChips: SetSize then SetData)
	-- by the time this runs, so the grain can be tiled to the fill's actual
	-- on-screen width right away rather than needing a separate layout pass.
	local fillWidth = self:GetWidth() - CAP_WIDTH * 2
	self.grain:SetTexCoord(0, fillWidth / FILL_TILE_WIDTH, 0, 1)

	self:Refresh()
	self:Show()
end

function FilterChipMixin:Refresh()
	local r, g, b, a
	if self.active then
		local card = CalendarPlus.Colors.surface.card
		r, g, b, a = card.r, card.g, card.b, 1
	else
		local panel2 = CalendarPlus.Colors.surface.panel2
		r, g, b, a = panel2.r, panel2.g, panel2.b, 0.5
	end
	self.capLeft:SetVertexColor(r, g, b, a)
	self.capRight:SetVertexColor(r, g, b, a)
	self.fill:SetVertexColor(r, g, b, a)
	self.grain:SetAlpha(a)
end

function FilterChipMixin:Reset()
	self:ClearAllPoints()
	self:Hide()
end
