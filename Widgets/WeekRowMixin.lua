local ADDON_NAME, ns = ...

CalendarPlus = CalendarPlus or {}

WeekRowMixin = {}

local COLUMNS = 7

function WeekRowMixin:OnPoolAcquire()
	self.colWidth = self:GetWidth() / COLUMNS

	self.dayCellPool = self.dayCellPool
		or CalendarPlus:CreatePool(self, "Frame", nil, DayCellMixin, function(_, frame) frame:Reset() end)
	self.eventBarPool = self.eventBarPool
		or CalendarPlus:CreatePool(self, "Frame", nil, EventBarMixin, function(_, frame) frame:Reset() end)
end

-- dayCells: array[1..7] of { monthDay, isToday, isOtherMonth }
-- segments: list of { colStart, colEnd, isStart, isEnd, title, category,
-- colorOverride, isSingleDay, realColStart, realColEnd }, 0-based columns
-- already clipped to this week's 7-day window (see MainFrame's per-week
-- clipper), lanes not yet assigned. realColStart/realColEnd mark the
-- sub-range of [colStart, colEnd] that falls in the real (non-padding)
-- month; nil,nil means the whole segment is padding.
-- Returns the row's new height so the caller can stack rows cumulatively --
-- rows grow taller on busy weeks instead of letting bars bleed into the row
-- below.

-- Renders one packed segment as a single bar, unless its real sub-range is a
-- strict subset of its full range (it crosses the month boundary within this
-- week), in which case it renders as two adjacent, same-lane, touching bar
-- pieces -- a dimmed padding piece and a bright real piece -- so it reads as
-- one continuous bar that just changes brightness at the boundary. Packing
-- lanes on the whole unsplit segment first and splitting only at render time
-- means the two pieces always land in the same lane by construction, with no
-- need to link them back together after the fact.
local function RenderSegmentPiece(self, segment, colStart, colEnd, isStart, isEnd, isPadding)
	local bar = self.eventBarPool:Acquire()
	bar:SetParent(self)
	bar:SetData({
		colStart = colStart, colEnd = colEnd,
		isStart = isStart, isEnd = isEnd,
		lane = segment.lane, category = segment.category,
		displayTitle = segment.title, colorOverride = segment.colorOverride,
		isSingleDay = segment.isSingleDay, isPadding = isPadding,
	}, self.colWidth, CalendarPlus.Layout.DAY_HEADER_HEIGHT)
end

local function RenderSegment(self, segment)
	if not segment.realColStart then
		RenderSegmentPiece(self, segment, segment.colStart, segment.colEnd, segment.isStart, segment.isEnd, true)
	elseif segment.realColStart == segment.colStart and segment.realColEnd == segment.colEnd then
		RenderSegmentPiece(self, segment, segment.colStart, segment.colEnd, segment.isStart, segment.isEnd, false)
	elseif segment.realColStart > segment.colStart then
		-- Padding on the left, real on the right.
		RenderSegmentPiece(self, segment, segment.colStart, segment.realColStart - 1, segment.isStart, false, true)
		RenderSegmentPiece(self, segment, segment.realColStart, segment.colEnd, false, segment.isEnd, false)
	else
		-- Real on the left, padding on the right.
		RenderSegmentPiece(self, segment, segment.colStart, segment.realColEnd, segment.isStart, false, false)
		RenderSegmentPiece(self, segment, segment.realColEnd + 1, segment.colEnd, false, segment.isEnd, true)
	end
end

function WeekRowMixin:SetWeek(dayCells, segments)
	self.dayCellPool:ReleaseAll()
	self.eventBarPool:ReleaseAll()

	local packed, laneCount = CalendarPlus.Layout.PackLanes(segments)
	local height = CalendarPlus.Layout.RowHeightForLanes(laneCount)
	self:SetHeight(height)

	for col, day in ipairs(dayCells) do
		local cell = self.dayCellPool:Acquire()
		cell:SetParent(self)
		cell:ClearAllPoints()
		cell:SetPoint("TOPLEFT", (col - 1) * self.colWidth, 0)
		cell:SetSize(self.colWidth, height)
		cell:SetData(day.monthDay, day.isToday, day.isOtherMonth, day.serial)
	end

	for _, segment in ipairs(packed) do
		RenderSegment(self, segment)
	end

	return height
end
