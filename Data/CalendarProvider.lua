local ADDON_NAME, ns = ...

CalendarPlus = CalendarPlus or {}

local provider = {}
CalendarPlus.CalendarProvider = provider

provider.MONTH_NAMES_ABBR = {
	"Jan", "Feb", "Mar", "Apr", "May", "Jun",
	"Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
}

-- key: "year-month" -> { info = MonthInfo, days = { [monthDay] = { CalendarEventInfo... } } }
local monthCache = {}
local anchored = false

-- Only ever requests fresh server data once per session -- guarded so it
-- doesn't refire on every repaint. (Anchoring the selected month itself is
-- handled entirely by GetMonth below.)
local function EnsureAnchored()
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
-- convention as CalendarTime.weekday / CalendarMonthInfo.firstWeekday.
function provider:GetResetWeekday()
	local today = C_DateAndTime.GetCurrentCalendarTime()
	local secondsSinceMidnight = today.hour * 3600 + today.minute * 60
	local daysForward = math.floor((secondsSinceMidnight + C_DateAndTime.GetSecondsUntilWeeklyReset()) / 86400)
	return ((today.weekday - 1 + daysForward) % 7) + 1
end

-- Tracks whichever offsetMonths GetMonth last actually resolved via
-- SetAbsMonth/SetMonth, purely as a fast-path skip for repeat calls with the
-- SAME target (e.g. re-showing the frame without navigating). This alone is
-- NOT enough to prevent recursion once a single repaint needs multiple
-- different months (current + adjacent-month padding preview): each one
-- resolves to a different offset, so this check never blocks any of them,
-- and each SetAbsMonth/SetMonth still fires CALENDAR_UPDATE_EVENT_LIST
-- synchronously -- see resolvingSelection below for what actually stops the
-- resulting cascade.
local lastResolvedOffset = nil

-- SetAbsMonth/SetMonth fire CALENDAR_UPDATE_EVENT_LIST synchronously (not
-- just after a server round-trip like OpenCalendar's own doc implies), and
-- the watcher below reacts to that by invalidating the cache + repainting,
-- which calls GetMonth again, which would call SetAbsMonth/SetMonth again...
-- This flag brackets every such call so the watcher can simply ignore any
-- event fired as a side effect of our OWN navigation, regardless of how many
-- different offsets get resolved within one repaint (that's what actually
-- broke here: three GetMonth calls per repaint -- current/prev/next month --
-- meant the offset-based guard above never matched twice in a row, so it
-- never stopped the cascade; this does, unconditionally).
local resolvingSelection = false

function provider:GetMonth(offsetMonths)
	EnsureAnchored()

	-- GetMonthInfo/GetNumDayEvents/GetDayEvent all read from the "currently
	-- selected" month, which only actually moves via SetAbsMonth/SetMonth --
	-- passing offsetMonths straight through without ever calling SetMonth
	-- left the event *data* stuck on whatever month was anchored at load
	-- time, even though the month *metadata* computed fine on its own.
	-- Resetting to today and stepping by the exact offset in one move (each
	-- time the target actually changes, not accumulating relative steps)
	-- means every resolution lands on the correct target regardless of
	-- navigation history, since SetMonth's own offset is relative to
	-- whatever is CURRENTLY selected, not always today.
	if lastResolvedOffset ~= offsetMonths then
		lastResolvedOffset = offsetMonths
		resolvingSelection = true
		local today = C_DateAndTime.GetCurrentCalendarTime()
		C_Calendar.SetAbsMonth(today.month, today.year)
		if offsetMonths ~= 0 then
			C_Calendar.SetMonth(offsetMonths)
		end
		resolvingSelection = false
	end

	local info = C_Calendar.GetMonthInfo(0)
	local key = info.year .. "-" .. info.month

	local cached = monthCache[key]
	if cached then
		return cached
	end

	local days = {}
	for day = 1, info.numDays do
		local n = C_Calendar.GetNumDayEvents(0, day)
		if n > 0 then
			local list = {}
			for i = 1, n do
				list[i] = C_Calendar.GetDayEvent(0, day, i)
			end
			days[day] = list
		end
	end

	cached = { info = info, days = days }
	monthCache[key] = cached
	return cached
end

function provider:Invalidate(year, month)
	if year and month then
		monthCache[year .. "-" .. month] = nil
	else
		wipe(monthCache)
	end
end

-- Expansion-name enrichment for events like "Timewalking Dungeon Event" whose
-- title alone doesn't say which expansion -- that only appears in the full
-- description text. GetDayEvent's own description field turned out empty for
-- these (it's meant for player-created events); the richer text ("...revisit
-- past dungeons from the Shadowlands expansion") comes from the dedicated
-- holiday API instead, which is synchronous -- no OpenEvent/async wait
-- needed. Callers always pass offset 0 here since GetMonth has already moved
-- the "currently selected" month to the target before this ever runs.
local expansionLabelCache = {} -- eventID -> label string, or false = no match found

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

function provider:GetExpansionLabel(day, index, eventID)
	if eventID then
		local cached = expansionLabelCache[eventID]
		if cached ~= nil then
			return cached ~= false and cached or nil
		end
	end

	local label
	local ok, holidayInfo = pcall(C_Calendar.GetHolidayInfo, 0, day, index)
	if ok and holidayInfo then
		label = ExtractExpansionLabel(holidayInfo.description)
	end

	if eventID then
		expansionLabelCache[eventID] = label or false
	end
	return label
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("CALENDAR_UPDATE_EVENT_LIST")
watcher:RegisterEvent("CALENDAR_UPDATE_EVENT")
watcher:SetScript("OnEvent", function()
	if resolvingSelection then return end
	provider:Invalidate()
	CalendarPlus.EventBus:Fire("CALENDAR_DATA_INVALIDATED")
end)
