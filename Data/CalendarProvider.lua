local ADDON_NAME, ns = ...

CalendarPlus = CalendarPlus or {}

local provider = {}
CalendarPlus.CalendarProvider = provider

provider.MONTH_NAMES_ABBR = {
	"Jan", "Feb", "Mar", "Apr", "May", "Jun",
	"Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
}

-- How far back/forward (in months from today) to precompute and cache in one
-- pass, and how many days old the cache can get before it's rebuilt.
-- Navigating further out than this window falls back to nothing rather than
-- a live fetch.
local BUILD_MONTHS_BACK = 2
local BUILD_MONTHS_FORWARD = 6
local CACHE_MAX_AGE_DAYS = 7

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
-- Guarded with the same flag RebuildEventCache uses to avoid a redundant
-- rebuild via the watcher.
function provider:AnchorToCurrentMonth()
	EnsureOpened()
	local today = C_DateAndTime.GetCurrentCalendarTime()
	resolvingSelection = true
	C_Calendar.SetAbsMonth(today.month, today.year)
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

-- Walks BUILD_MONTHS_BACK..BUILD_MONTHS_FORWARD around today in one
-- continuous pass, merging each multi-day event's per-day entries
-- (CalendarEventInfo.sequenceType: START/ONGOING/END, keyed by eventID) into
-- a single { startSerial, endSerial, isStart, isEnd, title, category,
-- colorOverride, numSequenceDays } span, in DateMath serial-day terms.
local function BuildEvents()
	local events = {}
	local openByEventID = {}
	local expansionCache = {}

	local today = C_DateAndTime.GetCurrentCalendarTime()
	local baseIndex = today.year * 12 + (today.month - 1)

	for offset = -BUILD_MONTHS_BACK, BUILD_MONTHS_FORWARD do
		local totalIndex = baseIndex + offset
		local year = math.floor(totalIndex / 12)
		local month = (totalIndex % 12) + 1

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
						-- C_Calendar's per-day event index, kept so clicking the
						-- rendered bar can call C_Calendar.OpenEvent to show
						-- Blizzard's info panel for this event.
						eventIndex = i,
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
					-- No open sequence to continue: a plain single-day event,
					-- or the START happened before our build window.
					local entry = {
						startSerial = serial, endSerial = serial,
						isStart = seq ~= "ONGOING" and seq ~= "END",
						isEnd = seq ~= "START" and seq ~= "ONGOING",
						title = displayTitle, category = category, colorOverride = colorOverride,
						numSequenceDays = ev.numSequenceDays, eventKey = eventKey, namedCategory = category,
						eventIndex = i,
					}
					events[#events + 1] = entry
					if ev.eventID and seq == "ONGOING" then
						openByEventID[ev.eventID] = entry
					end
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

function provider:RebuildEventCache()
	EnsureOpened()

	resolvingSelection = true
	local ok, events = pcall(BuildEvents)
	resolvingSelection = false

	if not ok then
		return
	end

	CalendarPlus.db.eventCache = {
		builtAtSerial = CalendarPlus.DateMath.TodaySerial(),
		events = events,
	}

	CalendarPlus.EventBus:Fire("CALENDAR_DATA_INVALIDATED")
end

-- Builds (or rebuilds, if missing/stale) on demand. The build is synchronous
-- and cheap, so callers can use the return value immediately.
function provider:GetEventCache()
	if not CalendarPlus.db then return {} end

	local cache = CalendarPlus.db.eventCache
	local todaySerial = CalendarPlus.DateMath.TodaySerial()
	if not cache or not cache.builtAtSerial or (todaySerial - cache.builtAtSerial) > CACHE_MAX_AGE_DAYS then
		self:RebuildEventCache()
		cache = CalendarPlus.db.eventCache
	end

	return cache and cache.events or {}
end

-- Every distinct named event currently in the cache, alphabetically, tagged
-- with its true classification category (namedCategory, never overwritten by
-- the singleDay override -- see BuildEvents). Backs the Settings panel's
-- Listed/Unlisted picker and MainFrame's category-chip visibility check.
function provider:GetKnownEventKeys()
	local events = self:GetEventCache()
	local seen = {}
	local list = {}
	for _, entry in ipairs(events) do
		if entry.eventKey and not seen[entry.eventKey] then
			seen[entry.eventKey] = true
			list[#list + 1] = { key = entry.eventKey, category = entry.namedCategory }
		end
	end
	table.sort(list, function(a, b) return a.key < b.key end)
	return list
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("CALENDAR_UPDATE_EVENT_LIST")
watcher:RegisterEvent("CALENDAR_UPDATE_EVENT")
watcher:SetScript("OnEvent", function()
	if resolvingSelection then return end
	provider:RebuildEventCache()
end)

-- Pre-warm the cache at login so opening the calendar doesn't wait on a build.
CalendarPlus.EventBus:On("DB_READY", function()
	provider:GetEventCache()
end)
