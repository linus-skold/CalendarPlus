local ADDON_NAME, ns = ...

CalendarPlus = CalendarPlus or {}

-- Matches Blizzard's own Calendar UI's day-cell right-click menu (the same
-- "Create Event" / "Create Guild Event" / paste-event menu you'd get
-- right-clicking a day in the stock Blizzard calendar) instead of building a
-- competing custom menu -- GenerateDayContextMenu is the exact function
-- Blizzard's own CalendarDayButton_OnClick calls for its RightButton case.
-- It lives in the Blizzard_Calendar addon, which is lazy-loaded (only
-- pulled in the first time the player opens the calendar), so it isn't
-- guaranteed to exist yet -- loaded on demand below.
--
-- CALENDAR_CONTEXTMENU_FLAG_SHOWDAY is Blizzard's own flag bit for "show the
-- day's create/paste options" (as opposed to the flag for an existing
-- event's edit/delete options) -- hardcoded here since it's a bit constant,
-- not something that changes, and not guaranteed to be an exported global.
local CALENDAR_CONTEXTMENU_FLAG_SHOWDAY = 0x01

-- A first attempt at this faked a plain proxy table for "dayButton" (just
-- .day/.monthOffset plus no-op LockHighlight/UnlockHighlight), which looked
-- like enough going by GenerateDayContextMenu's own signature -- but
-- clicking "Create Event" actually walks much deeper into Blizzard's UI
-- (CalendarDayContextMenu_ClearEvent -> CalendarDayButton_Click ->
-- CalendarFrame_SetSelectedDay), which calls dayButton:GetHighlightTexture()
-- and dayButton:GetID() -- real Button-widget methods no plain table can
-- fake. Rather than keep guessing at how much of a real CalendarDayButton's
-- interface is actually needed, this borrows one of Blizzard's own 42 real
-- day-button widgets (CalendarDayButton1, a genuine global CreateFrame gives
-- a name to, even though the array holding all of them is file-local to
-- Blizzard_Calendar.lua) and just repoints its day/monthOffset fields at
-- whichever day was actually clicked. Every method Blizzard's code calls on
-- it then works for real, because it really is a CalendarDayButtonTemplate
-- button.
--
-- Known cosmetic side effect: the create-event dialog's date LABEL derives
-- its weekday text from this button's own grid position (dayButton:GetID()),
-- not from the day/monthOffset we overrode -- so the weekday name shown
-- there can be wrong even though the date it actually saves to (via
-- C_Calendar.EventSetDate, which does use the overridden fields directly) is
-- correct. Not worth chasing further; the saved event lands on the right day.
local function GetRealDayButton()
	return _G["CalendarDayButton1"]
end

-- C_AddOns.LoadAddOn is the current API; older clients only had the bare
-- global LoadAddOn, kept here as a fallback for safety. Returns true if the
-- Blizzard Calendar UI globals this file depends on are actually available
-- afterward.
local function EnsureBlizzardCalendarLoaded()
	if C_AddOns and C_AddOns.LoadAddOn then
		C_AddOns.LoadAddOn("Blizzard_Calendar")
	elseif LoadAddOn then
		LoadAddOn("Blizzard_Calendar")
	end
	return MenuUtil and MenuUtil.CreateContextMenu and GenerateDayContextMenu and CalendarFrame
end

-- Both the create-event dialog (CalendarCreateEventFrame) and every "view
-- this event" frame (CalendarViewHolidayFrame / CalendarViewEventFrame /
-- CalendarViewRaidFrame) are parent="CalendarFrame" in Blizzard's own XML.
-- We never open the real CalendarFrame, so even though Blizzard's code
-- calls :Show() on any of these successfully, none of them actually become
-- visible on screen -- WoW only renders a frame if its *entire* ancestor
-- chain is shown, not just the frame itself. Parking CalendarFrame
-- off-screen (rather than leaving it hidden) satisfies that requirement
-- without it visually intruding.
--
-- Every one of those frames is ultimately shown via the single shared
-- CalendarFrame_ShowEventFrame(frame) function, so hooking that once here
-- (rather than repositioning each frame type individually at each call
-- site) covers all of them uniformly, including any Blizzard adds in the
-- future. Left alone entirely if the player already has their real
-- calendar open -- then everything already works exactly as Blizzard
-- intends, and forcibly moving their own open window would be actively
-- rude, and forcibly relocating whatever it shows would be too.
local weParkedCalendarFrame = false
local hookedShowEventFrame = false

-- Tracks whichever event-info frame Blizzard most recently showed via
-- CalendarFrame_ShowEventFrame, and which event (by startSerial:eventIndex)
-- ShowEventInfo last asked to open -- lets a second click on the same
-- already-open event's bar toggle it closed instead of reopening/refreshing
-- it (see ShowEventInfo below).
local lastShownFrame
local lastOpenedEventKey

local function EnsureCalendarFrameParked()
	if not CalendarFrame:IsShown() then
		weParkedCalendarFrame = true
		CalendarFrame:Show()
		CalendarFrame:ClearAllPoints()
		CalendarFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -5000, 5000)
	end

	if not hookedShowEventFrame then
		hookedShowEventFrame = true
		hooksecurefunc("CalendarFrame_ShowEventFrame", function(frame)
			if not frame then return end
			lastShownFrame = frame

			if weParkedCalendarFrame then
				frame:ClearAllPoints()
				frame:SetPoint("TOPLEFT", CalendarPlusMainFrame, "TOPRIGHT", 8, 0)
			end
		end)
	end
end

-- Restores CalendarFrame to hidden, but only if WE were the one who parked
-- it and it's still us using it -- called from CalendarPlusMainFrame's own
-- OnHide (see MainFrame.xml), not whenever some individual Blizzard dialog
-- closes. An earlier version instead hid CalendarFrame from that dialog's
-- own OnHide, on the theory that we should tidy up as soon as its info
-- panel was done with -- but CalendarFrame itself isn't purely invisible
-- infrastructure once shown (Blizzard's own OnShow/OnHide handling for it
-- has side effects beyond this addon's control), so hiding it that eagerly,
-- every single time any one dialog closed, was itself a visible disruption.
-- Simplest fix: leave CalendarFrame parked for as long as CalendarPlus's own
-- window stays open, and only tear it down when that closes too.
function CalendarPlus.RestoreCalendarFrameIfParked()
	if weParkedCalendarFrame then
		weParkedCalendarFrame = false
		CalendarFrame:Hide()
	end
end

-- Both entry points below need a monthOffset relative to C_Calendar's own
-- shared "currently selected month" -- which nothing else in this addon
-- touches anymore (the whole point of the cache rewrite) -- so it has to be
-- anchored to "today" first, or an offset meant to be relative to today
-- resolves against whatever month was last selected by anything else.
local function ResolveMonthOffset(serial)
	local year, month = CalendarPlus.DateMath.FromSerial(serial)
	local today = C_DateAndTime.GetCurrentCalendarTime()
	local baseIndex = today.year * 12 + (today.month - 1)
	return (year * 12 + (month - 1)) - baseIndex
end

-- Called when CalendarPlus's own window opens (see MainFrame.lua), so the
-- real CalendarFrame and its whole family of dialogs already exist and are
-- parked off-screen ahead of time, rather than only getting loaded/parked
-- reactively on the first right-click or event click. Silent on failure
-- (unlike the two functions below) since this is just warming things up in
-- the background, not a direct response to the player asking for a menu.
function CalendarPlus.EnsureCalendarUIReady()
	if not EnsureBlizzardCalendarLoaded() then return end
	EnsureCalendarFrameParked()
end

-- serial: the day cell's absolute DateMath serial day number.
function CalendarPlus.ShowDayContextMenu(cellFrame, serial)
	if not serial then return end

	local _, _, day = CalendarPlus.DateMath.FromSerial(serial)
	local monthOffset = ResolveMonthOffset(serial)

	if not EnsureBlizzardCalendarLoaded() then
		print("|cff33ff99CalendarPlus|r: couldn't open the calendar's event menu (Blizzard's own Calendar UI wasn't available).")
		return
	end

	local realDayButton = GetRealDayButton()
	if not realDayButton then
		print("|cff33ff99CalendarPlus|r: couldn't open the calendar's event menu (Blizzard's own Calendar UI wasn't available).")
		return
	end

	CalendarPlus.CalendarProvider:AnchorToCurrentMonth()
	EnsureCalendarFrameParked()

	realDayButton.day = day
	realDayButton.monthOffset = monthOffset

	local ok, err = pcall(function()
		MenuUtil.CreateContextMenu(cellFrame, function(owner, rootDescription)
			GenerateDayContextMenu(owner, rootDescription, CALENDAR_CONTEXTMENU_FLAG_SHOWDAY, realDayButton, nil)
		end)
	end)
	if not ok then
		print("|cff33ff99CalendarPlus|r: couldn't open the calendar's event menu (" .. tostring(err) .. ").")
	end
end

-- startSerial/eventIndex: identify exactly which C_Calendar day+index this
-- rendered event bar represents (see CalendarProvider's eventIndex field,
-- captured on whichever day the event's own entry was first created --
-- always a valid day for that event, since it's the day it actually
-- occupies in Blizzard's own per-day event list).
--
-- C_Calendar.OpenEvent kicks off an async fetch; Blizzard's own CalendarFrame
-- (already loaded, registered for CALENDAR_OPEN_EVENT since its own OnLoad,
-- regardless of whether it's shown) reacts on its own once that completes,
-- deciding for us whether to show CalendarViewHolidayFrame,
-- CalendarViewEventFrame, CalendarViewRaidFrame, or CalendarCreateEventFrame
-- in edit mode (if you can edit this particular event) -- nothing further
-- to do here beyond making sure whichever one it picks actually renders
-- (see EnsureCalendarFrameParked).
function CalendarPlus.ShowEventInfo(startSerial, eventIndex)
	if not startSerial or not eventIndex then return end

	local eventKey = startSerial .. ":" .. eventIndex
	if eventKey == lastOpenedEventKey and lastShownFrame and lastShownFrame:IsShown() then
		lastShownFrame:Hide()
		lastOpenedEventKey = nil
		return
	end

	local _, _, day = CalendarPlus.DateMath.FromSerial(startSerial)
	local monthOffset = ResolveMonthOffset(startSerial)

	if not EnsureBlizzardCalendarLoaded() then
		print("|cff33ff99CalendarPlus|r: couldn't open this event's info (Blizzard's own Calendar UI wasn't available).")
		return
	end

	if not (C_Calendar and C_Calendar.OpenEvent) then
		print("|cff33ff99CalendarPlus|r: couldn't open this event's info (C_Calendar.OpenEvent wasn't available).")
		return
	end

	CalendarPlus.CalendarProvider:AnchorToCurrentMonth()
	EnsureCalendarFrameParked()

	lastOpenedEventKey = eventKey
	C_Calendar.OpenEvent(monthOffset, day, eventIndex)
end
