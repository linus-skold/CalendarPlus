local ADDON_NAME, ns = ...

CalendarPlus = CalendarPlus or {}

local COLUMNS = 7
local ROWS = 6
local ROW_GAP = 6
-- Index matches C_DateAndTime's weekday convention: 1=Sunday..7=Saturday.
local FULL_WEEKDAY_NAMES = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }

local currentOffset = 0
local weekRows = {}
local filterChips = {}
local dowLabels = {}
local activeCategoryFilters = {} -- categoryKey -> true (visible)

-- 1=Sunday..7=Saturday, user-configurable via /calendarplus weekstart <day>.
local function GetWeekStartDay()
	return (CalendarPlus.db and CalendarPlus.db.weekStartDay) or 2
end

-- Weekday abbreviations reordered to start on the configured day, for the header.
local function GetWeekdayNames()
	local startDay = GetWeekStartDay()
	local names = {}
	for i = 1, COLUMNS do
		local idx = ((startDay - 1 + i - 1) % 7) + 1
		names[i] = FULL_WEEKDAY_NAMES[idx]
	end
	return names
end

local function GetOrCreateWeekRows(grid)
	if #weekRows > 0 then return weekRows end

	local width = grid:GetWidth()
	for i = 1, ROWS do
		local row = CreateFrame("Frame", nil, grid)
		Mixin(row, WeekRowMixin)
		row:SetWidth(width)
		row:SetHeight(1) -- placeholder; SetWeek sets the real height every repaint
		row:OnPoolAcquire()
		weekRows[i] = row
	end
	return weekRows
end

local function CreateDowHeader(header)
	local width = header:GetWidth() / COLUMNS
	for i = 1, COLUMNS do
		if not dowLabels[i] then
			local label = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			label:SetPoint("TOPLEFT", (i - 1) * width + 4, 0)
			dowLabels[i] = label
		end
	end
end

-- Re-labels the (already-created) header to match the current start-day
-- setting; called every repaint so /calendarplus weekstart takes effect
-- immediately even while the frame is open.
local function UpdateDowHeader()
	local names = GetWeekdayNames()
	for i, label in ipairs(dowLabels) do
		label:SetText(names[i])
	end
end

-- GetDayEvent's title alone doesn't say which expansion a Timewalking event
-- covers ("Timewalking Dungeon Event" for all of them) -- that only shows up
-- in the holiday description text (see CalendarProvider:GetExpansionLabel),
-- read synchronously so this resolves immediately, no repaint-later needed.
-- Returns the display title plus a color override (so Timewalking bars are
-- colored by expansion instead of the generic "dungeon" category) once the
-- expansion is known.
local PVP_TITLE_PATTERNS = { "PvP Brawl", "Battleground", "Arena Skirmish" }

local function GetDisplayTitle(ev, day, index)
	local title = ev.title
	if not title then return nil, nil end

	if title:find("Timewalking", 1, true) then
		local label = CalendarPlus.CalendarProvider:GetExpansionLabel(day, index, ev.eventID)
		if label then
			return "Timewalking: " .. label, CalendarPlus.Colors.expansions[label]
		end
		return title, nil
	end

	-- PvP Brawls/Battlegrounds/Arena Skirmishes are cleaner colored by the
	-- player's own faction than by a generic category color.
	for _, pattern in ipairs(PVP_TITLE_PATTERNS) do
		if title:find(pattern, 1, true) then
			return title, CalendarPlus.Colors.faction
		end
	end

	return title, nil
end

-- Walks one month's cached day->events map over [rangeStart, rangeEnd] (that
-- month's own 1-indexed day numbers), merging each multi-day event's per-day
-- entries (CalendarEventInfo.sequenceType: START/ONGOING/END, keyed by
-- eventID) into a single { startDay, endDay, isStart, isEnd, event, category,
-- displayTitle } span. Segments that start or end outside the range (a
-- sequence's START day was earlier, or it continues later) are left with
-- isStart/isEnd false on that side so the caller draws a flush edge instead
-- of a rounded cap.
--
-- virtualOffset remaps that month's day numbers onto the grid's running day
-- counter (0 for the currently displayed month itself; -previous month's
-- numDays, or +this month's numDays, for the faded preview of adjacent
-- months' leading/trailing padding days -- see RepaintMonth). isPadding
-- flags those preview days so EventBarMixin can dim them. Enrichment
-- (GetDisplayTitle's Timewalking/PvP lookup) runs for every range, not just
-- the real month -- it relies on the target month being the API's
-- "currently selected" one, but RepaintMonth always re-selects whichever
-- month it's about to build right before calling this, so that holds for
-- the padding ranges too, not only the month actually being displayed.
--
-- segments/openByEventID are accumulated *across* calls (RepaintMonth builds
-- leading-padding, then the real month, then trailing-padding, threading the
-- same two tables through all three in that order) so an event spanning a
-- month boundary keeps extending the same visual run instead of each side
-- becoming its own disconnected bar. It should still visibly dim/brighten
-- exactly at that boundary though, so when a day's isPadding differs from
-- the currently open segment's, that segment is closed off right there and
-- a new one starts flush against it (isStart false, so no cap is drawn on
-- the shared edge) -- same event, same color/title (freshly enriched on
-- both sides, so they always agree), touching with no gap, just a different
-- alpha on each side.
local function BuildSegmentsForRange(monthData, rangeStart, rangeEnd, virtualOffset, isPadding, segments, openByEventID)
	segments = segments or {}
	openByEventID = openByEventID or {}

	for day = rangeStart, rangeEnd do
		local events = monthData.days[day]
		if events then
			for index, ev in ipairs(events) do
				local _, category = CalendarPlus.Colors:GetForEvent(ev)
				if activeCategoryFilters[category] ~= false then
					local seq = ev.sequenceType
					local displayTitle, colorOverride = GetDisplayTitle(ev, day, index)
					local vday = day + virtualOffset

					local open = ev.eventID and openByEventID[ev.eventID]
					local paddingChanged = open and open.isPadding ~= isPadding

					if seq == "START" then
						local segment = {
							startDay = vday, endDay = vday,
							isStart = true, isEnd = false,
							event = ev, category = category,
							displayTitle = displayTitle, colorOverride = colorOverride,
							isPadding = isPadding,
						}
						segments[#segments + 1] = segment
						if ev.eventID then openByEventID[ev.eventID] = segment end
					elseif (seq == "ONGOING" or seq == "END") and open and not paddingChanged then
						open.endDay = vday
						open.displayTitle = displayTitle
						open.colorOverride = colorOverride
						if seq == "END" then
							open.isEnd = true
							openByEventID[ev.eventID] = nil
						end
					elseif (seq == "ONGOING" or seq == "END") and open and paddingChanged then
						local segment = {
							startDay = vday, endDay = vday,
							isStart = false, isEnd = (seq == "END"),
							event = ev, category = open.category,
							displayTitle = displayTitle, colorOverride = colorOverride,
							isPadding = isPadding,
							continuesFrom = open, -- see Layout.PackLanes: forces the same lane
						}
						segments[#segments + 1] = segment
						if seq == "END" then
							openByEventID[ev.eventID] = nil
						else
							openByEventID[ev.eventID] = segment
						end
					else
						-- No open sequence to continue (either a plain
						-- single-day event, or the START happened earlier,
						-- outside everything built so far).
						local segment = {
							startDay = vday, endDay = vday,
							isStart = seq ~= "ONGOING" and seq ~= "END",
							isEnd = seq ~= "START" and seq ~= "ONGOING",
							event = ev, category = category,
							displayTitle = displayTitle, colorOverride = colorOverride,
							isPadding = isPadding,
						}
						segments[#segments + 1] = segment
						-- If it's still ONGOING, register it as open too, so
						-- tomorrow's ONGOING/END for the same eventID extends
						-- *this* segment instead of each spawning its own
						-- separate 1-day segment (the previous bug: an event
						-- whose START was earlier never got registered here
						-- at all, so every day of it fragmented apart).
						if ev.eventID and seq == "ONGOING" then
							openByEventID[ev.eventID] = segment
						end
					end
				end
			end
		end
	end

	return segments, openByEventID
end

-- Runs the month-independent finishing passes (isSingleDay, weekly-reset
-- trim) over an already-combined segment list. Split out from segment
-- *building* so RepaintMonth can build the current month's segments (which
-- need GetExpansionLabel/GetDisplayTitle, both relying on the API's
-- "currently selected" month still being this one) before ever calling
-- GetMonth for the adjacent months' padding preview -- fetching those first
-- would move that selection away and silently break Timewalking's
-- expansion-name lookup for the CURRENT month's own events.
local function FinishSegments(segments, monthData)
	-- Whether a segment ends up spanning only one day can't be known until
	-- its ONGOING/END continuations (if any) have all been folded in above,
	-- so it's computed here in a final pass rather than at creation time.
	-- Needs BOTH conditions: startDay==endDay alone would also catch a
	-- fragment cut off at a month boundary (flush on one side, so not
	-- really 1 day -- its other end just isn't visible here); isStart and
	-- isEnd alone would also catch a complete multi-day event that happens
	-- to fit inside one week row with two true (non-flush) ends.
	for _, segment in ipairs(segments) do
		segment.isSingleDay = segment.startDay == segment.endDay
			and segment.isStart and segment.isEnd
	end

	-- Weekly-cadence events (Timewalking, PvP Brawls, etc. -- identified by
	-- numSequenceDays being about a week long) often report their true end as
	-- the reset day itself, e.g. ending Tuesday 6am right as next week's
	-- instance starts Tuesday too -- so for one day both occupy the grid at
	-- once, forcing an extra lane just for that overlap. Trimming the old
	-- one's end back to the day before reset avoids that clutter. Only a
	-- segment's true end (isEnd) gets trimmed, never a week-row's flush cut.
	local trimEnabled = not CalendarPlus.db or CalendarPlus.db.trimWeeklyEventsAtReset ~= false
	if trimEnabled then
		local resetWeekday = CalendarPlus.CalendarProvider:GetResetWeekday()
		for _, segment in ipairs(segments) do
			local numDays = segment.event.numSequenceDays
			if segment.isEnd and numDays and numDays >= 6 and numDays <= 8 and segment.endDay > segment.startDay then
				local endWeekday = ((monthData.info.firstWeekday - 1 + (segment.endDay - 1)) % 7) + 1
				if endWeekday == resetWeekday then
					segment.endDay = segment.endDay - 1
					segment.isSingleDay = segment.startDay == segment.endDay
						and segment.isStart and segment.isEnd
				end
			end
		end
	end

	return segments
end

-- Clips month-level segments to one week row's 7-day window, matching the
-- reference mockup's per-week clipping: isStart/isEnd only stay true when the
-- clip boundary is the event's true start/end, not just the week wrap.
local function ClipSegmentsToWeek(monthSegments, weekFirstDay, weekLastDay)
	local weekSegments = {}
	local copyByOriginal = {} -- month-level segment -> its week-clipped copy
	for _, seg in ipairs(monthSegments) do
		if seg.endDay >= weekFirstDay and seg.startDay <= weekLastDay then
			local copy = {
				colStart = math.max(seg.startDay, weekFirstDay) - weekFirstDay,
				colEnd = math.min(seg.endDay, weekLastDay) - weekFirstDay,
				isStart = seg.isStart and seg.startDay >= weekFirstDay,
				isEnd = seg.isEnd and seg.endDay <= weekLastDay,
				event = seg.event,
				category = seg.category,
				displayTitle = seg.displayTitle,
				colorOverride = seg.colorOverride,
				isSingleDay = seg.isSingleDay,
				isPadding = seg.isPadding,
				-- Resolved from the month-level continuesFrom (a table
				-- reference to another month-level segment) to that
				-- predecessor's OWN week-clipped copy, since Layout.PackLanes
				-- needs to look up a `.lane` that only exists on copies, not
				-- on the original month-level segments.
				linkedLane = seg.continuesFrom and copyByOriginal[seg.continuesFrom] or nil,
			}
			copyByOriginal[seg] = copy
			weekSegments[#weekSegments + 1] = copy
		end
	end
	return weekSegments
end

local function BuildFilterChips(filterBar)
	if #filterChips > 0 then return filterChips end

	local pool = CalendarPlus:CreatePool(filterBar, "Button", nil, FilterChipMixin, function(_, f) f:Reset() end)
	local order = {
		{ key = "weekly",   label = "Weekly rotation",     width = 128 },
		{ key = "bonus",    label = "Bonus event",         width = 104 },
		{ key = "monthly",  label = "Monthly",             width = 84 },
		{ key = "seasonal", label = "Seasonal / holiday",  width = 162 },
		{ key = "special",  label = "Special / limited",   width = 156 },
	}
	local x = 0
	for _, entry in ipairs(order) do
		local chip = pool:Acquire()
		chip:SetParent(filterBar)
		chip:SetSize(entry.width, 20)
		chip:ClearAllPoints()
		chip:SetPoint("LEFT", x, 0)
		chip:SetData(entry.key, entry.label, function(catKey, active)
			activeCategoryFilters[catKey] = active
			CalendarPlus.RepaintMonth()
		end)
		activeCategoryFilters[entry.key] = true
		x = x + entry.width + 6
		filterChips[#filterChips + 1] = chip
	end
	return filterChips
end

-- Splits a month's cached day->events map into 6 week rows of 7 days,
-- merging multi-day events into single spanning bars (see BuildSegmentsForRange
-- / FinishSegments) and growing each row to fit however many lanes that week
-- actually needs.
function CalendarPlus.RepaintMonth()
	local frame = CalendarPlusMainFrame
	if not frame or not frame:IsShown() then return end

	local monthData = CalendarPlus.CalendarProvider:GetMonth(currentOffset)
	local info = monthData.info
	local monthName = CalendarPlus.CalendarProvider.MONTH_NAMES_ABBR[info.month]
	frame.TopBar.MonthLabel:SetText(monthName .. " " .. info.year)

	local today = C_DateAndTime.GetCurrentCalendarTime()
	local isCurrentMonth = info.year == today.year and info.month == today.month

	UpdateDowHeader()

	-- C_Calendar's firstWeekday is 1=Sunday..7=Saturday; convert to a 0-based
	-- column offset relative to the user's configured week-start day.
	local firstWeekday = (info.firstWeekday - GetWeekStartDay()) % 7
	local rows = GetOrCreateWeekRows(frame.Grid)

	-- Not every month needs all 6 fixed row slots (e.g. a month starting
	-- right on the configured week-start day only needs 5 rows to cover up
	-- to 35 days) -- rendering unneeded trailing rows just shows a mostly
	-- blank strip of next month's padding days. Rows are reused/cached
	-- across repaints (see GetOrCreateWeekRows), so leftover ones from a
	-- previous month that needed more rows must be explicitly hidden here.
	local neededRows = math.ceil((firstWeekday + info.numDays) / COLUMNS)
	local leadingPadding = firstWeekday
	local trailingPadding = neededRows * COLUMNS - (firstWeekday + info.numDays)

	-- Built in calendar order -- leading padding, then the real month, then
	-- trailing padding -- threading the same segments/openByEventID tables
	-- through all three so an event spanning a month boundary keeps
	-- extending one segment instead of becoming two disconnected bars (see
	-- BuildSegmentsForRange). Leading/trailing padding days only get fetched
	-- when the grid actually shows that padding.
	local segments, openByEventID
	local prevMonthNumDays -- needed below to compute leading padding cells' real day numbers

	if leadingPadding > 0 then
		local prevMonthData = CalendarPlus.CalendarProvider:GetMonth(currentOffset - 1)
		prevMonthNumDays = prevMonthData.info.numDays
		local rangeStart = prevMonthNumDays - leadingPadding + 1
		segments, openByEventID = BuildSegmentsForRange(
			prevMonthData, rangeStart, prevMonthNumDays, -prevMonthNumDays, true
		)

		-- Fetching prevMonthData above moved the API's "currently selected"
		-- month away from the one about to be built below, which needs it
		-- back for GetDisplayTitle's Timewalking expansion-label lookup.
		CalendarPlus.CalendarProvider:GetMonth(currentOffset)
	end

	segments, openByEventID = BuildSegmentsForRange(
		monthData, 1, info.numDays, 0, false, segments, openByEventID
	)

	if trailingPadding > 0 then
		local nextMonthData = CalendarPlus.CalendarProvider:GetMonth(currentOffset + 1)
		segments, openByEventID = BuildSegmentsForRange(
			nextMonthData, 1, trailingPadding, info.numDays, true, segments, openByEventID
		)
	end

	local monthSegments = FinishSegments(segments, monthData)

	local dayNum = 1 - firstWeekday
	local cumulativeY = 0
	for r = 1, ROWS do
		if r > neededRows then
			rows[r]:Hide()
		else
			rows[r]:Show()
			local weekFirstDay = dayNum
			local weekLastDay = dayNum + COLUMNS - 1

			local dayCells = {}
			for c = 1, COLUMNS do
				local isOtherMonth = dayNum < 1 or dayNum > info.numDays
				local displayDay = dayNum
				if dayNum < 1 then
					displayDay = prevMonthNumDays + dayNum
				elseif dayNum > info.numDays then
					displayDay = dayNum - info.numDays
				end
				dayCells[c] = {
					monthDay = displayDay,
					isToday = (not isOtherMonth) and isCurrentMonth and dayNum == today.monthDay,
					isOtherMonth = isOtherMonth,
				}
				dayNum = dayNum + 1
			end

			local weekSegments = ClipSegmentsToWeek(monthSegments, weekFirstDay, weekLastDay)
			local height = rows[r]:SetWeek(dayCells, weekSegments)

			rows[r]:ClearAllPoints()
			rows[r]:SetPoint("TOPLEFT", 0, -cumulativeY)
			cumulativeY = cumulativeY + height + ROW_GAP
		end
	end

	-- Keep Grid's own bounds matching its actual content height so its panel
	-- background (see MainFrame_OnLoad) covers busy months fully instead of
	-- stopping at a fixed height while rows overflow past it.
	frame.Grid:SetHeight(cumulativeY)

	-- Grow/shrink the whole window to fit the actual content height instead
	-- of leaving a fixed-height backdrop border that busy months' rows spill
	-- silently past. topOverhead (frame top -> Grid top, in screen pixels) is
	-- measured live rather than hard-coded so it stays correct if the layout
	-- above the grid ever changes.
	local topOverhead = frame:GetTop() - frame.Grid:GetTop()
	local bottomMargin = 16
	frame:SetHeight(topOverhead + cumulativeY + bottomMargin)
end

function CalendarPlus.MainFrame_OnLoad(frame)
	CalendarPlus:ApplyDialogBackdrop(frame)
	tinsert(UISpecialFrames, frame:GetName())

	-- Panel behind the whole grid (matching the mockup's .grid-card), so the
	-- gaps between week rows read as an intentional layered surface instead
	-- of empty space showing the window backdrop through.
	local gridBg = frame.Grid:CreateTexture(nil, "BACKGROUND")
	gridBg:SetAllPoints()
	local panel = CalendarPlus.Colors.surface.panel
	gridBg:SetColorTexture(panel.r, panel.g, panel.b, 1)

	frame.TopBar.PrevMonth:SetScript("OnClick", function()
		currentOffset = currentOffset - 1
		CalendarPlus.RepaintMonth()
	end)
	frame.TopBar.NextMonth:SetScript("OnClick", function()
		currentOffset = currentOffset + 1
		CalendarPlus.RepaintMonth()
	end)

	CreateDowHeader(frame.DowHeader)
	BuildFilterChips(frame.TopBar.FilterBar)

	CalendarPlus.EventBus:On("CALENDAR_DATA_INVALIDATED", CalendarPlus.RepaintMonth)
end

function CalendarPlus.MainFrame_OnShow()
	currentOffset = 0
	CalendarPlus.RepaintMonth()
end

function CalendarPlus.ToggleMainFrame()
	local frame = CalendarPlusMainFrame
	if frame:IsShown() then
		frame:Hide()
	else
		frame:Show()
	end
end
