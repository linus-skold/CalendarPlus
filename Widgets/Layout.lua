local ADDON_NAME, ns = ...

CalendarPlus = CalendarPlus or {}
CalendarPlus.Layout = CalendarPlus.Layout or {}

local Layout = CalendarPlus.Layout

-- Shared sizing constants so MainFrame's row positioning, WeekRowMixin's
-- height calc, and EventBarMixin's bar placement all agree on the same
-- numbers instead of three separate hard-coded copies.
Layout.DAY_HEADER_HEIGHT = 26
Layout.LANE_HEIGHT = 18
Layout.LANE_GAP = 2

function Layout.RowHeightForLanes(laneCount)
	return Layout.DAY_HEADER_HEIGHT + math.max(laneCount, 0) * (Layout.LANE_HEIGHT + Layout.LANE_GAP)
end

-- Greedy interval-scheduling lane packer, ported line-for-line from the CSS
-- mockup's JS. `segments` is a list of { colStart, colEnd, ... }; returns the
-- same list with a `.lane` field added, plus the total lane count used.
-- Pure function, no frame dependency -- keeps it unit testable outside a UI.
--
-- Packing runs on the whole, unsplit per-week event list (one entry per
-- event, even if it crosses the real/padding month boundary within that
-- week) -- the caller splits an already-packed segment into two same-lane
-- render pieces afterward (see WeekRowMixin:RenderSegment) rather than lanes
-- ever needing to be linked back together.
function Layout.PackLanes(segments)
	table.sort(segments, function(a, b)
		return a.colStart < b.colStart
	end)

	local laneEnds = {} -- laneEnds[lane] = last occupied column in that lane
	local laneCount = 0

	for _, segment in ipairs(segments) do
		local placedLane

		for lane = 1, laneCount do
			if laneEnds[lane] < segment.colStart then
				placedLane = lane
				break
			end
		end

		if not placedLane then
			laneCount = laneCount + 1
			placedLane = laneCount
		end

		laneEnds[placedLane] = segment.colEnd
		segment.lane = placedLane
	end

	return segments, laneCount
end
