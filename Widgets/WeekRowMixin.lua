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
-- segments: list of { colStart, colEnd, isStart, isEnd, event, category }, 0-based
-- columns already clipped to this week's 7-day window (see MainFrame's month-
-- level segment builder), lanes not yet assigned.
-- Returns the row's new height so the caller can stack rows cumulatively --
-- rows grow taller on busy weeks instead of letting bars bleed into the row
-- below.
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
		cell:SetData(day.monthDay, day.isToday, day.isOtherMonth)
	end

	for _, segment in ipairs(packed) do
		local bar = self.eventBarPool:Acquire()
		bar:SetParent(self)
		bar:SetData(segment, self.colWidth, CalendarPlus.Layout.DAY_HEADER_HEIGHT)
	end

	return height
end
