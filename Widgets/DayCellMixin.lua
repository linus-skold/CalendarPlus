local ADDON_NAME, ns = ...

CalendarPlus = CalendarPlus or {}

DayCellMixin = {}

function DayCellMixin:OnPoolAcquire()
	self.bg = self.bg or self:CreateTexture(nil, "BACKGROUND")
	self.bg:SetAllPoints()
	local panel2 = CalendarPlus.Colors.surface.panel2
	self.bg:SetColorTexture(panel2.r, panel2.g, panel2.b, 1)

	self.highlight = self.highlight or self:CreateTexture(nil, "ARTWORK")
	self.highlight:SetAllPoints()
	self.highlight:SetColorTexture(1, 1, 1, 0.06)
	self.highlight:Hide()

	-- Whole-cell tint for "today", on top of the gold circle badge on the
	-- number itself -- makes today's column noticeably stand out at a
	-- glance, not just on close inspection of the date text.
	self.todayHighlight = self.todayHighlight or self:CreateTexture(nil, "ARTWORK", nil, -1)
	self.todayHighlight:SetAllPoints()
	self.todayHighlight:SetColorTexture(0.93, 0.68, 0.15, 0.12)
	self.todayHighlight:Hide()

	-- Thin divider on the cell's right edge (mockup's --line-soft column
	-- rules), separating each day from the next within a row.
	self.divider = self.divider or self:CreateTexture(nil, "ARTWORK")
	self.divider:SetPoint("TOPRIGHT")
	self.divider:SetPoint("BOTTOMRIGHT")
	self.divider:SetWidth(1)
	local line = CalendarPlus.Colors.surface.line
	self.divider:SetColorTexture(line.r, line.g, line.b, 0.7)

	self.dayNumber = self.dayNumber or self:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	self.dayNumber:SetPoint("TOPLEFT", 4, -4)

	-- Reused circular texture for the "today" badge, repositioned per day
	-- cell rather than created/destroyed on every redraw. Blizzard's own
	-- portrait alpha mask is a plain white-with-alpha circle sprite, so it
	-- can be tinted directly instead of drawing a plain colored square.
	self.todayBadge = self.todayBadge or self:CreateTexture(nil, "OVERLAY")
	self.todayBadge:SetSize(18, 18)
	self.todayBadge:SetPoint("TOPLEFT", 2, -2)
	self.todayBadge:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
	self.todayBadge:SetVertexColor(0.93, 0.68, 0.15, 1)
	self.todayBadge:Hide()

	self:SetScript("OnEnter", function(owner) owner.highlight:Show() end)
	self:SetScript("OnLeave", function(owner) owner.highlight:Hide() end)
end

function DayCellMixin:SetData(monthDay, isToday, isOtherMonth)
	self.dayNumber:SetText(monthDay)
	self.todayBadge:SetShown(isToday)
	self.todayHighlight:SetShown(isToday)

	self.dayNumber:ClearAllPoints()
	if isToday then
		-- Center on the badge instead of the cell's fixed TOPLEFT text spot,
		-- and darken the text since it's sitting on solid gold now.
		self.dayNumber:SetPoint("CENTER", self.todayBadge, "CENTER")
		self.dayNumber:SetJustifyH("CENTER")
		self.dayNumber:SetTextColor(0.16, 0.13, 0.03)
	else
		self.dayNumber:SetPoint("TOPLEFT", 4, -4)
		self.dayNumber:SetJustifyH("LEFT")
		local shade = isOtherMonth and 0.45 or 1
		self.dayNumber:SetTextColor(shade, shade, shade)
	end

	self:Show()
end

function DayCellMixin:Reset()
	self.highlight:Hide()
	self.todayBadge:Hide()
	self.todayHighlight:Hide()
	self:ClearAllPoints()
	self:Hide()
end
