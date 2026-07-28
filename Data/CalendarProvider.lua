local ADDON_NAME, ns = ...

CalendarPlus = CalendarPlus or {}

local provider = {}
CalendarPlus.CalendarProvider = provider

provider.MONTH_NAMES_ABBR = {
	"Jan", "Feb", "Mar", "Apr", "May", "Jun",
	"Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
}

-- How far back/forward (in months from today) to precompute and cache in one
-- pass, and how many days old that cache can get before it's rebuilt from
-- scratch. Navigating further out than this window than falls back to
-- nothing rather than a live fetch -- a deliberate tradeoff for dropping all
-- the per-repaint C_Calendar juggling below.
local BUILD_MONTHS_BACK = 2
local BUILD_MONTHS_FORWARD = 6
local CACHE_MAX_AGE_DAYS = 7

local anchored = false

-- SetAbsMonth (called once per month during a cache build) fires
-- CALENDAR_UPDATE_EVENT_LIST synchronously, not just after a server
-- round-trip -- our own watcher reacts to that by rebuilding, which would
-- call SetAbsMonth again, recursing forever (a real C-stack overflow this
-- addon hit earlier). Held true for the ENTIRE build, not just bracketing
-- each individual SetAbsMonth call, since there's no guarantee the event
-- doesn't fire on some deferred tick between them.
local resolvingSelection = false

-- Only ever requests fresh server data once per session -- guarded so it
-- doesn't refire on every rebuild.
local function EnsureOpened()
	if anchored then return end
	anchored = true
	C_Calendar.OpenCalendar()
end

-- The weekly reset always lands on the same weekday for a given realm/region
-- (Tuesday NA, Wednesday EU, etc.), so this is derived fresh each call
-- rather than cached -- cheap enough not to need it, and avoids ever holding
-- a stale value. Deliberately stays entirely within C_DateAndTime's own
-- server-time API rather than mixing in time()/date(), which read the
-- PLAYER'S LOCAL system clock -- adding a server-relative "seconds until
-- reset" duration to a local timestamp lands on the wrong weekday whenever
-- the player's timezone differs from the server's (i.e. almost always),
-- which is exactly the kind of bug that silently breaks this only right
-- around the reset day itself. Returned in the same 1=Sunday..7=Saturday
-- convention as CalendarTime.weekday / DateMath.WeekdayOfSerial.
function provider:GetResetWeekday()
	local today = C_DateAndTime.GetCurrentCalendarTime()
	local secondsSinceMidnight = today.hour * 3600 + today.minute * 60
	local daysForward = math.floor((secondsSinceMidnight + C_DateAndTime.GetSecondsUntilWeeklyReset()) / 86400)
	return ((today.weekday - 1 + daysForward) % 7) + 1
end

-- Forces C_Calendar's shared "currently selected month" to the real current
-- month. Nothing else in this addon touches that selection anymore (the
-- whole point of the cache rewrite), so it could be sitting on whatever
-- ANY other code last left it at. That's fine for our own rendering (pure
-- DateMath, doesn't care), but Blizzard's own day-context-menu code (see
-- DayContextMenu.lua) resolves a dayButton's monthOffset via
-- C_Calendar.GetMonthInfo(monthOffset) *relative to that same shared
-- selection* -- so it must be anchored to "today" immediately before
-- invoking any of that code, or an offset meant to be relative to today
-- would resolve to the wrong month entirely. Guarded with the same flag
-- RebuildEventCache uses so this doesn't also trigger a redundant rebuild
-- via the watcher.
function provider:AnchorToCurrentMonth()
	EnsureOpened()
	local today = C_DateAndTime.GetCurrentCalendarTime()
	resolvingSelection = true
	C_Calendar.SetAbsMonth(today.month, today.year)
	resolvingSelection = false
end

-- Expansion-name enrichment for events like "Timewalking Dungeon Event" whose
-- title alone doesn't say which expansion -- that only appears in the full
-- description text. GetDayEvent's own description field turned out empty for
-- these (it's meant for player-created events); the richer text ("...revisit
-- past dungeons from the Shadowlands expansion") comes from the dedicated
-- holiday API instead, which is synchronous -- no OpenEvent/async wait
-- needed, but it does need the month currently being scanned to actually be
-- C_Calendar's "currently selected" one, which only holds true while
-- BuildEvents is actively iterating that specific month below.
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
-- colorOverride, numSequenceDays } span, in DateMath serial-day terms. Since
-- it's one continuous scan across the whole window instead of separate
-- per-month fetches, an event spanning a month boundary just naturally
-- keeps extending the same entry -- no leading/trailing-padding split-and-
-- link machinery needed at render time anymore.
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

				-- Listed/Unlisted keys off the fully-resolved display title
				-- itself (e.g. "Timewalking: Classic", or a PvP Brawl's own
				-- specific name) rather than a fixed pattern list, so every
				-- distinct event gets its own row with nothing lumped into a
				-- shared catch-all.
				--
				-- Two deliberate exceptions, both grouped under one shared
				-- key regardless of the specific title, since each is really
				-- "the same thing" from the player's point of view:
				-- - the yearly Anniversary celebration's title changes every
				--   year ("15th Anniversary", "16th Anniversary", ...), which
				--   would otherwise make each year's occurrence its own
				--   permanent, never-reused row in the picker.
				-- - player-made events (calendarType ~= HOLIDAY) have
				--   arbitrary titles unique to each one, whether you created
				--   them yourself or were just invited -- there's no sense
				--   listing them individually, so they all collapse into one
				--   "Player Events" bucket instead.
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
					-- No open sequence to continue (either a plain
					-- single-day event, or the START happened before our
					-- build window).
					local entry = {
						startSerial = serial, endSerial = serial,
						isStart = seq ~= "ONGOING" and seq ~= "END",
						isEnd = seq ~= "START" and seq ~= "ONGOING",
						title = displayTitle, category = category, colorOverride = colorOverride,
						numSequenceDays = ev.numSequenceDays, eventKey = eventKey, namedCategory = category,
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
		-- Single-day events get their own filter bucket instead of whichever
		-- category GetForEvent originally classified them under, matching
		-- the flat coral color EventBarMixin already gives them regardless
		-- of category. This is a build-time (genuine single-day) call, not
		-- the render-time isSingleDay recompute in MainFrame's weekly-reset
		-- trim -- an event that only *becomes* one visible day because it
		-- got trimmed this week stays filed under its real category.
		--
		-- Player-made events are exempt: they're almost always one day
		-- long, so folding them into "singleDay" here would defeat the
		-- whole point of giving player events their own distinct category
		-- and color -- nearly every one of them would silently end up
		-- coral instead of pink.
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

-- Builds (or rebuilds, if missing/stale) on demand. The build itself is
-- synchronous and cheap (a few hundred local C_Calendar calls, no network
-- wait), so callers can just use the return value immediately.
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

-- Every distinct named (systemwide-feed, i.e. eventKey ~= nil) event
-- currently present in the cache, alphabetically, each tagged with its true
-- classification category (entry.namedCategory, never overwritten by the
-- singleDay filter-bucket override -- see BuildEvents). Backs both the
-- Settings panel's Listed/Unlisted picker and MainFrame's category-chip
-- visibility check. Since this only reflects whatever actually occurred
-- within the cache's build window, an event that hasn't happened yet (or
-- already scrolled out of it) simply won't appear here until it does.
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

-- Pre-warm the cache at login (in the background of DB_READY, not the first
-- time the user opens the calendar) so opening it doesn't have to wait on a
-- build.
CalendarPlus.EventBus:On("DB_READY", function()
	provider:GetEventCache()
end)
