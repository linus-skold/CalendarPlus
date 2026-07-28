local ADDON_NAME, ns = ...

CalendarPlus = CalendarPlus or {}

FilterChipMixin = {}

-- Same fixed-cap-plus-stretchable-fill technique as EventBarMixin's rounded
-- bars: a small rounded region at each end (native size, no stretching) and
-- a plain rectangle filling the rest, so it looks properly rounded at any
-- chip width instead of one 32px mask stretched across the whole button.
local CAP_WIDTH = 12

function FilterChipMixin:OnPoolAcquire()
	self.capLeft = self.capLeft or self:CreateTexture(nil, "BACKGROUND")
	self.capLeft:SetTexture("Interface\\AddOns\\CalendarPlus\\Media\\RoundMaskLeft")
	-- Only the left half of the source image is actually the curve (the
	-- right half is flat padding, meant for the old whole-bar stretch) --
	-- cropping to just that half means the whole CAP_WIDTH is spent on the
	-- curve instead of half being wasted on more flatness right next to the
	-- fill rectangle.
	self.capLeft:SetTexCoord(0, 0.5, 0, 1)
	self.capLeft:SetPoint("TOPLEFT")
	self.capLeft:SetPoint("BOTTOMLEFT")
	self.capLeft:SetWidth(CAP_WIDTH)

	self.capRight = self.capRight or self:CreateTexture(nil, "BACKGROUND")
	self.capRight:SetTexture("Interface\\AddOns\\CalendarPlus\\Media\\RoundMaskRight")
	self.capRight:SetTexCoord(0.5, 1, 0, 1)
	self.capRight:SetPoint("TOPRIGHT")
	self.capRight:SetPoint("BOTTOMRIGHT")
	self.capRight:SetWidth(CAP_WIDTH)

	self.fill = self.fill or self:CreateTexture(nil, "BACKGROUND")
	self.fill:SetColorTexture(1, 1, 1, 1)
	self.fill:SetPoint("TOPLEFT", self.capLeft, "TOPRIGHT")
	self.fill:SetPoint("BOTTOMRIGHT", self.capRight, "BOTTOMLEFT")

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
	self.highlight = self.highlight or self:CreateTexture(nil, "HIGHLIGHT")
	self.highlight:SetAllPoints()
	self.highlight:SetColorTexture(1, 1, 1, 0.15)
	self.highlight:SetBlendMode("ADD")

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
	self:Refresh()
	self:Show()
end

function FilterChipMixin:Refresh()
	local r, g, b, a
	if self.active then
		r, g, b, a = 0.2, 0.2, 0.22, 1
	else
		r, g, b, a = 0.1, 0.1, 0.11, 0.5
	end
	self.capLeft:SetVertexColor(r, g, b, a)
	self.capRight:SetVertexColor(r, g, b, a)
	self.fill:SetVertexColor(r, g, b, a)
end

function FilterChipMixin:Reset()
	self:ClearAllPoints()
	self:Hide()
end
