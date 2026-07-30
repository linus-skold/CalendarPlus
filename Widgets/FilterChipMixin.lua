local ADDON_NAME, ns = ...

CalendarPlus = CalendarPlus or {}

FilterChipMixin = {}

-- Same fixed-cap-plus-stretchable-fill technique as EventBarMixin: fixed end
-- caps plus a rectangle filling the rest, so it looks right at any chip width.
local CAP_WIDTH = 12

-- Matches EventBarMixin's FILL_TILE_WIDTH (CleanFullBarFill.tga's native width).
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

	-- Grain accent layered over the fill, sized/tiled to the fill's bounds in SetData.
	self.grain = self.grain or self:CreateTexture(nil, "ARTWORK")
	self.grain:SetTexture("Interface\\AddOns\\CalendarPlus\\Media\\BarTextureFill", "REPEAT", "CLAMP")
	self.grain:SetPoint("TOPLEFT", self.capLeft, "TOPRIGHT")
	self.grain:SetPoint("BOTTOMRIGHT", self.capRight, "BOTTOMLEFT")

	self.dot = self.dot or self:CreateTexture(nil, "ARTWORK")
	self.dot:SetSize(8, 8)
	self.dot:SetPoint("LEFT", CAP_WIDTH, 0)
	self.dot:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")

	-- Chip is sized (see BuildFilterChips) to fit the full label, so no truncation needed.
	self.label = self.label or self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	self.label:SetPoint("LEFT", self.dot, "RIGHT", 4, 0)

	-- Button HIGHLIGHT-layer textures show/hide automatically on mouseover.
	self.highlight = self.highlight or self:CreateTexture(nil, "HIGHLIGHT")
	self.highlight:SetAllPoints()
	self.highlight:SetTexture("Interface\\AddOns\\CalendarPlus\\Media\\StatusBarHighlight")
	self.highlight:SetBlendMode("ADD")
	self.highlight:SetAlpha(0.35)

	self:SetScript("OnClick", function(owner)
		if IsControlKeyDown() and owner.onIsolate then
			owner.onIsolate(owner.categoryKey)
			return
		end
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
	self.dotColor = CalendarPlus.Colors[categoryKey] or CalendarPlus.Colors.default

	-- Chip width is already set (BuildFilterChips: SetSize then SetData), so
	-- the grain can be tiled to the fill's actual width right away.
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
		self.dot:SetVertexColor(self.dotColor.r, self.dotColor.g, self.dotColor.b, 1)
		self.label:SetTextColor(1, 1, 1, 1)
	else
		local panel2 = CalendarPlus.Colors.surface.panel2
		r, g, b, a = panel2.r, panel2.g, panel2.b, 0.5
		self.dot:SetVertexColor(self.dotColor.r, self.dotColor.g, self.dotColor.b, 0.35)
		self.label:SetTextColor(0.5, 0.5, 0.5, 1)
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
