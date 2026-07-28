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

-- Filters+trims CalendarProvider's cached event list down to whatever
-- overlaps [gridFirstSerial, gridLastSerial] (the whole visible grid,
-- including padding days), applying the weekly-reset trim and the active
-- category filters in the same pass. The trim itself stays a render-time
-- step (rather than being baked into the cache) specifically so toggling
-- trimWeeklyEventsAtReset takes effect immediately without a cache rebuild.
local function GetVisibleEvents(gridFirstSerial, gridLastSerial)
	local events = CalendarPlus.CalendarProvider:GetEventCache()
	local trimEnabled = not CalendarPlus.db or CalendarPlus.db.trimWeeklyEventsAtReset ~= false
	local resetWeekday = trimEnabled and CalendarPlus.CalendarProvider:GetResetWeekday() or nil

	local visible = {}
	for _, entry in ipairs(events) do
		if activeCategoryFilters[entry.category] ~= false then
			local endSerial = entry.endSerial

			-- Weekly-cadence events (Timewalking, PvP Brawls, etc.) often
			-- report their true end as the reset day itself, overlapping one
			-- day with next week's instance starting the same day. Trimming
			-- the old one's end back to the day before reset avoids that
			-- clutter. Only a segment's true end (isEnd) gets trimmed.
			if trimEnabled and entry.isEnd and entry.numSequenceDays
				and entry.numSequenceDays >= 6 and entry.numSequenceDays <= 8
				and endSerial > entry.startSerial then
				if CalendarPlus.DateMath.WeekdayOfSerial(endSerial) == resetWeekday then
					endSerial = endSerial - 1
				end
			end

			if endSerial >= gridFirstSerial and entry.startSerial <= gridLastSerial then
				visible[#visible + 1] = {
					startSerial = entry.startSerial, endSerial = endSerial,
					isStart = entry.isStart, isEnd = entry.isEnd,
					title = entry.title, category = entry.category, colorOverride = entry.colorOverride,
					isSingleDay = entry.startSerial == endSerial and entry.isStart and entry.isEnd,
				}
			end
		end
	end
	return visible
end

-- Clips the (already grid-filtered) event list to one week row's 7-day
-- window, in 0-based column terms. realColStart/realColEnd mark the
-- sub-range of [colStart, colEnd] that falls within the real (non-padding)
-- month -- nil,nil if the event doesn't touch the real month at all within
-- this week -- so WeekRowMixin can render the faded/bright split without
-- needing to know about serial days at all.
local function ClipEventsToWeek(events, weekFirstSerial, weekLastSerial, monthFirstSerial, monthLastSerial)
	local weekSegments = {}
	for _, ev in ipairs(events) do
		if ev.endSerial >= weekFirstSerial and ev.startSerial <= weekLastSerial then
			local realStart = math.max(ev.startSerial, weekFirstSerial, monthFirstSerial)
			local realEnd = math.min(ev.endSerial, weekLastSerial, monthLastSerial)
			local realColStart, realColEnd
			if realStart <= realEnd then
				realColStart = realStart - weekFirstSerial
				realColEnd = realEnd - weekFirstSerial
			end

			weekSegments[#weekSegments + 1] = {
				colStart = math.max(ev.startSerial, weekFirstSerial) - weekFirstSerial,
				colEnd = math.min(ev.endSerial, weekLastSerial) - weekFirstSerial,
				isStart = ev.isStart and ev.startSerial >= weekFirstSerial,
				isEnd = ev.isEnd and ev.endSerial <= weekLastSerial,
				title = ev.title, category = ev.category, colorOverride = ev.colorOverride,
				isSingleDay = ev.isSingleDay,
				realColStart = realColStart, realColEnd = realColEnd,
			}
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

-- Lays out the currently-selected month (currentOffset months from today)
-- into up to 6 week rows, reading from CalendarProvider's precomputed event
-- cache instead of live C_Calendar calls -- month metadata (day counts,
-- weekday-of-1st) comes from pure DateMath arithmetic instead of
-- GetMonthInfo, so navigating never touches C_Calendar's shared "currently
-- selected month" state at all.
function CalendarPlus.RepaintMonth()
	local frame = CalendarPlusMainFrame
	if not frame or not frame:IsShown() then return end

	local DateMath = CalendarPlus.DateMath
	local todaySerial, today = DateMath.TodaySerial()

	local baseIndex = today.year * 12 + (today.month - 1)
	local totalIndex = baseIndex + currentOffset
	local year = math.floor(totalIndex / 12)
	local month = (totalIndex % 12) + 1

	local numDays = DateMath.DaysInMonth(year, month)
	local monthFirstSerial = DateMath.ToSerial(year, month, 1)
	local monthLastSerial = monthFirstSerial + numDays - 1

	local monthName = CalendarPlus.CalendarProvider.MONTH_NAMES_ABBR[month]
	frame.TopBar.MonthLabel:SetText(monthName .. " " .. year)

	UpdateDowHeader()

	-- DateMath's weekday is 1=Sunday..7=Saturday; convert to a 0-based
	-- column offset relative to the user's configured week-start day.
	local rawFirstWeekday = DateMath.WeekdayOfSerial(monthFirstSerial)
	local firstWeekday = (rawFirstWeekday - GetWeekStartDay()) % 7
	local rows = GetOrCreateWeekRows(frame.Grid)

	-- Not every month needs all 6 fixed row slots (e.g. a month starting
	-- right on the configured week-start day only needs 5 rows to cover up
	-- to 35 days) -- rendering unneeded trailing rows just shows a mostly
	-- blank strip of next month's padding days. Rows are reused/cached
	-- across repaints (see GetOrCreateWeekRows), so leftover ones from a
	-- previous month that needed more rows must be explicitly hidden here.
	local neededRows = math.ceil((firstWeekday + numDays) / COLUMNS)
	local gridFirstSerial = monthFirstSerial - firstWeekday
	local gridLastSerial = gridFirstSerial + neededRows * COLUMNS - 1

	local visibleEvents = GetVisibleEvents(gridFirstSerial, gridLastSerial)

	local cumulativeY = 0
	for r = 1, ROWS do
		if r > neededRows then
			rows[r]:Hide()
		else
			rows[r]:Show()
			local weekFirstSerial = gridFirstSerial + (r - 1) * COLUMNS
			local weekLastSerial = weekFirstSerial + COLUMNS - 1

			local dayCells = {}
			for c = 1, COLUMNS do
				local serial = weekFirstSerial + c - 1
				local isOtherMonth = serial < monthFirstSerial or serial > monthLastSerial
				local _, _, displayDay = DateMath.FromSerial(serial)
				dayCells[c] = {
					monthDay = displayDay,
					isToday = serial == todaySerial and not isOtherMonth,
					isOtherMonth = isOtherMonth,
				}
			end

			local weekSegments = ClipEventsToWeek(visibleEvents, weekFirstSerial, weekLastSerial, monthFirstSerial, monthLastSerial)
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
