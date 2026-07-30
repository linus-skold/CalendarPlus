local ADDON_NAME, ns = ...

CalendarPlus = CalendarPlus or {}

local provider = {}
CalendarPlus.CalendarProvider = provider

provider.MONTH_NAMES_ABBR = {
	"Jan", "Feb", "Mar", "Apr", "May", "Jun",
	"Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
}

-- Cached per month, built lazily on first access. No fixed range.
local MONTH_CACHE_MAX_AGE_DAYS = 1

local anchored = false

-- SetAbsMonth fires CALENDAR_UPDATE_EVENT_LIST synchronously; the watcher
-- reacts by rebuilding, which would call SetAbsMonth again and recurse.
-- Held true for the entire build, not just around each SetAbsMonth call,
-- since the event isn't guaranteed to fire only between them.
local resolvingSelection = false

-- Requests fresh server data once per session; guarded against refiring on
-- every rebuild.
local function EnsureOpened()
	if anchored then return end
	anchored = true
	C_Calendar.OpenCalendar()
end

-- Derived fresh each call, staying entirely within C_DateAndTime's
-- server-time API -- mixing in time()/date() (local system clock) would land
-- on the wrong weekday whenever the player's timezone differs from the
-- server's. Returned in the same 1=Sunday..7=Saturday convention as
-- CalendarTime.weekday / DateMath.WeekdayOfSerial.
function provider:GetResetWeekday()
	local today = C_DateAndTime.GetCurrentCalendarTime()
	local secondsSinceMidnight = today.hour * 3600 + today.minute * 60
	local daysForward = math.floor((secondsSinceMidnight + C_DateAndTime.GetSecondsUntilWeeklyReset()) / 86400)
	return ((today.weekday - 1 + daysForward) % 7) + 1
end

-- Forces C_Calendar's shared "currently selected month" to today. Blizzard's
-- day-context-menu code resolves a dayButton's monthOffset relative to that
-- same shared selection, so it must be anchored right before invoking it.
-- Guarded with the same flag RebuildMonthCache uses to avoid a redundant
-- rebuild via the watcher.
function provider:AnchorToCurrentMonth()
	EnsureOpened()
	local today = C_DateAndTime.GetCurrentCalendarTime()
	resolvingSelection = true
	C_Calendar.SetAbsMonth(today.month, today.year)
	resolvingSelection = false
end

-- GetNumDayEvents/GetDayEvent only return data for the currently selected
-- month, so it must be selected before querying an arbitrary month's events.
function provider:AnchorToMonth(year, month)
	EnsureOpened()
	resolvingSelection = true
	C_Calendar.SetAbsMonth(month, year)
	resolvingSelection = false
end

-- Expansion-name enrichment for events like "Timewalking Dungeon Event" whose
-- title alone doesn't say which expansion. GetDayEvent's description field is
-- empty for these; the expansion name comes from C_Calendar.GetHolidayInfo
-- instead, which needs the month being scanned to be the currently selected
-- one (true while BuildEvents iterates that month below).
local EXPANSION_PATTERNS = {
	{ pattern = "Burning Crusade", label = "TBC" },
	{ pattern = "Wrath of the Lich King", label = "Wrath" },
	{ pattern = "Cataclysm", label = "Cata" },
	{ pattern = "Mists of Pandaria", label = "MoP" },
	{ pattern = "Warlords of Draenor", label = "WoD" },
	{ pattern = "Legion", label = "Legion" },
	{ pattern = "Battle for Azeroth", label = "BfA" },
	{ pattern = "Shadowlands", label = "Shadowlands" },
	{ pattern = "Dragonflight", label = "Dragonflight" },
	{ pattern = "The War Within", label = "War Within" },
	{ pattern = "Midnight", label = "Midnight" },
	{ pattern = "Classic", label = "Classic" },
}

local function ExtractExpansionLabel(description)
	if not description then return nil end
	for _, entry in ipairs(EXPANSION_PATTERNS) do
		if description:find(entry.pattern, 1, true) then
			return entry.label
		end
	end
	return nil
end

-- PvP Brawls/Battlegrounds/Arena Skirmishes are cleaner colored by the
-- player's own faction than by a generic category color.
local PVP_TITLE_PATTERNS = { "PvP Brawl", "Battleground", "Arena Skirmish" }

-- Returns (displayTitle, colorOverride). expansionCache is scoped to a
-- single BuildEvents call (eventID -> label or false), so a multi-day
-- Timewalking event only pays for GetHolidayInfo once instead of once per
-- day of its run.
local function ComputeDisplay(ev, day, index, expansionCache)
	local title = ev.title
	if not title then return nil, nil end

	if title:find("Timewalking", 1, true) then
		local label
		if ev.eventID and expansionCache[ev.eventID] ~= nil then
			label = expansionCache[ev.eventID] or nil
		else
			local ok, holidayInfo = pcall(C_Calendar.GetHolidayInfo, 0, day, index)
			if ok and holidayInfo then
				label = ExtractExpansionLabel(holidayInfo.description)
			end
			if ev.eventID then
				expansionCache[ev.eventID] = label or false
			end
		end
		if label then
			return "Timewalking: " .. label, CalendarPlus.Colors.expansions[label]
		end
		return title, nil
	end

	for _, pattern in ipairs(PVP_TITLE_PATTERNS) do
		if title:find(pattern, 1, true) then
			return title, CalendarPlus.Colors.faction
		end
	end

	return title, nil
end

-- Merges one month's per-day event entries (CalendarEventInfo.sequenceType:
-- START/ONGOING/END, keyed by eventID) into { startSerial, endSerial,
-- isStart, isEnd, title, category, colorOverride, numSequenceDays } spans.
local function BuildMonthEvents(year, month)
	local events = {}
	local openByEventID = {}
	local expansionCache = {}

	C_Calendar.SetAbsMonth(month, year)

	local numDays = CalendarPlus.DateMath.DaysInMonth(year, month)
	local monthFirstSerial = CalendarPlus.DateMath.ToSerial(year, month, 1)

	for day = 1, numDays do
		local n = C_Calendar.GetNumDayEvents(0, day)
		for i = 1, n do
			local ev = C_Calendar.GetDayEvent(0, day, i)
			local _, category = CalendarPlus.Colors:GetForEvent(ev)
			local serial = monthFirstSerial + day - 1
			local seq = ev.sequenceType
			local displayTitle, colorOverride = ComputeDisplay(ev, day, i, expansionCache)
			local open = ev.eventID and openByEventID[ev.eventID]

			-- Listed/Unlisted keys off the fully-resolved display title,
			-- so every distinct event gets its own row. Two exceptions
			-- grouped under a shared key: the yearly Anniversary
			-- celebration's title changes every year, and player-made
			-- events have arbitrary unique titles -- both collapse into
			-- one shared bucket instead of one row each.
			local eventKey
			if ev.calendarType ~= "HOLIDAY" then
				eventKey = "Player Events"
			elseif displayTitle and displayTitle:find("Anniversary", 1, true) then
				eventKey = "Anniversary"
			else
				eventKey = displayTitle
			end

			if seq == "START" then
				local entry = {
					startSerial = serial, endSerial = serial,
					isStart = true, isEnd = false,
					title = displayTitle, category = category, colorOverride = colorOverride,
					numSequenceDays = ev.numSequenceDays, eventKey = eventKey, namedCategory = category,
					eventID = ev.eventID,
				}
				events[#events + 1] = entry
				if ev.eventID then openByEventID[ev.eventID] = entry end
			elseif (seq == "ONGOING" or seq == "END") and open then
				open.endSerial = serial
				open.title = displayTitle
				open.colorOverride = colorOverride
				if seq == "END" then
					open.isEnd = true
					openByEventID[ev.eventID] = nil
				end
			else
				-- No open sequence: single-day event, or START was in a
				-- different month's build.
				local entry = {
					startSerial = serial, endSerial = serial,
					isStart = seq ~= "ONGOING" and seq ~= "END",
					isEnd = seq ~= "START" and seq ~= "ONGOING",
					title = displayTitle, category = category, colorOverride = colorOverride,
					numSequenceDays = ev.numSequenceDays, eventKey = eventKey, namedCategory = category,
					eventID = ev.eventID,
				}
				events[#events + 1] = entry
				if ev.eventID and seq == "ONGOING" then
					openByEventID[ev.eventID] = entry
				end
			end
		end
	end

	for _, entry in ipairs(events) do
		entry.isSingleDay = entry.startSerial == entry.endSerial and entry.isStart and entry.isEnd
		-- Single-day events get their own filter bucket (matching the flat
		-- color EventBarMixin gives them), except player-made events, which
		-- keep their own distinct category instead of folding into this one.
		-- This is the build-time single-day check, not MainFrame's
		-- render-time weekly-reset trim.
		if entry.isSingleDay and entry.category ~= "custom" then
			entry.category = "singleDay"
		end
	end

	return events
end

local function MonthKey(year, month)
	return year * 12 + (month - 1)
end

local function OffsetToYearMonth(offset)
	local today = C_DateAndTime.GetCurrentCalendarTime()
	local totalIndex = today.year * 12 + (today.month - 1) + offset
	local year = math.floor(totalIndex / 12)
	local month = (totalIndex % 12) + 1
	return year, month
end

function provider:RebuildMonthCache(year, month)
	EnsureOpened()

	resolvingSelection = true
	local ok, events = pcall(BuildMonthEvents, year, month)
	resolvingSelection = false

	if not ok then
		return
	end

	CalendarPlus.db.eventCache = CalendarPlus.db.eventCache or {}
	CalendarPlus.db.eventCache[MonthKey(year, month)] = {
		builtAtSerial = CalendarPlus.DateMath.TodaySerial(),
		events = events,
	}

	CalendarPlus.EventBus:Fire("CALENDAR_DATA_INVALIDATED")
end

-- offset is relative to today (0 = current month, -1 = last month, etc).
function provider:GetMonthEvents(offset)
	if not CalendarPlus.db then return {} end

	local year, month = OffsetToYearMonth(offset)
	local key = MonthKey(year, month)
	local cache = CalendarPlus.db.eventCache and CalendarPlus.db.eventCache[key]
	local todaySerial = CalendarPlus.DateMath.TodaySerial()
	if not cache or not cache.builtAtSerial or (todaySerial - cache.builtAtSerial) > MONTH_CACHE_MAX_AGE_DAYS then
		self:RebuildMonthCache(year, month)
		cache = CalendarPlus.db.eventCache[key]
	end

	return cache and cache.events or {}
end

function provider:GetEventsForRange(minOffset, maxOffset)
	local merged = {}
	for offset = minOffset, maxOffset do
		for _, entry in ipairs(self:GetMonthEvents(offset)) do
			merged[#merged + 1] = entry
		end
	end
	return merged
end

-- Live per-day index lookup -- Blizzard's ordering can shift, so this must
-- be called right before use, never cached.
function provider:ResolveEventIndex(monthOffset, day, eventID)
	local n = C_Calendar.GetNumDayEvents(monthOffset, day)
	for i = 1, n do
		local ev = C_Calendar.GetDayEvent(monthOffset, day, i)
		if ev and ev.eventID == eventID then
			return i
		end
	end
	return nil
end

-- Every distinct named event across currently-cached months. Backs the
-- Settings panel's Listed/Unlisted picker and MainFrame's category chips.
function provider:GetKnownEventKeys()
	local seen = {}
	local list = {}
	local cache = CalendarPlus.db and CalendarPlus.db.eventCache or {}
	for _, monthCache in pairs(cache) do
		for _, entry in ipairs(monthCache.events) do
			if entry.eventKey and not seen[entry.eventKey] then
				seen[entry.eventKey] = true
				list[#list + 1] = { key = entry.eventKey, category = entry.namedCategory }
			end
		end
	end
	table.sort(list, function(a, b) return a.key < b.key end)
	return list
end

function provider:InvalidateAll()
	CalendarPlus.db.eventCache = {}
	CalendarPlus.EventBus:Fire("CALENDAR_DATA_INVALIDATED")
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("CALENDAR_UPDATE_EVENT_LIST")
watcher:RegisterEvent("CALENDAR_UPDATE_EVENT")
watcher:SetScript("OnEvent", function()
	if resolvingSelection then return end
	provider:InvalidateAll()
end)

-- Discards the old single-table eventCache shape from prior versions, then
-- pre-warms today's month (+/- 1).
CalendarPlus.EventBus:On("DB_READY", function()
	local cache = CalendarPlus.db.eventCache
	if cache and (cache.builtAtSerial or cache.events) then
		CalendarPlus.db.eventCache = {}
	end
	provider:GetEventsForRange(-1, 1)
end)
