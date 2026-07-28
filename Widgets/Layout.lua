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
-- A segment.linkedLane (another segment in the same list) forces it into
-- that segment's lane instead of running the normal first-fit search --
-- used for a month-boundary event split into two adjacent, touching, non-
-- overlapping pieces (a bright real-month one and a dimmed padding-preview
-- one) that need to land in the same lane so they read as one continuous
-- bar. Safe by construction: the two pieces never overlap (they touch, with
-- zero gap), so nothing else could have claimed that lane in between them.
-- linkedLane must already have a `.lane` by the time its dependent is
-- processed, which holds here since it always has a lower colStart and the
-- sort below is by colStart ascending. Ties on colStart (e.g. a linked
-- continuation and some unrelated brand-new segment both starting on the
-- exact same day) break in favor of the linked one, since table.sort isn't
-- stable -- without this, an unrelated tied segment could win the race and
-- greedily grab the very lane the linked one is about to be forced into,
-- landing both in the same lane.
function Layout.PackLanes(segments)
	table.sort(segments, function(a, b)
		if a.colStart ~= b.colStart then
			return a.colStart < b.colStart
		end
		return (a.linkedLane ~= nil) and (b.linkedLane == nil)
	end)

	local laneEnds = {} -- laneEnds[lane] = last occupied column in that lane
	local laneCount = 0

	for _, segment in ipairs(segments) do
		local placedLane = segment.linkedLane and segment.linkedLane.lane

		if not placedLane then
			for lane = 1, laneCount do
				if laneEnds[lane] < segment.colStart then
					placedLane = lane
					break
				end
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
