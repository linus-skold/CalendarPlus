local ADDON_NAME, ns = ...

CalendarPlus = CalendarPlus or {}

-- Uses Blizzard's own GenerateDayContextMenu (the function CalendarDayButton_OnClick
-- calls for right-click) instead of a custom menu. Lives in Blizzard_Calendar,
-- which is lazy-loaded, so it isn't guaranteed to exist yet -- loaded on demand below.
--
-- GenerateDayContextMenu's flag bits: SHOWDAY shows day create/paste options,
-- SHOWEVENT shows event copy/delete/paste options (needs a real eventButton).
local CALENDAR_CONTEXTMENU_FLAG_SHOWDAY = 0x01
local CALENDAR_CONTEXTMENU_FLAG_SHOWEVENT = 0x02

-- GenerateDayContextMenu's "Create Event" path calls dayButton:GetHighlightTexture()
-- and :GetID(), real Button-widget methods a plain proxy table can't fake. So this
-- borrows one of Blizzard's real day-button widgets (CalendarDayButton1) and
-- repoints its day/monthOffset fields at whichever day was clicked.
--
-- Cosmetic side effect: the create-event dialog's date label derives its weekday
-- text from dayButton:GetID(), not from the overridden day/monthOffset, so the
-- weekday shown can be wrong even though the saved date (via C_Calendar.EventSetDate,
-- which uses the overridden fields) is correct.
local function GetRealDayButton()
	return _G["CalendarDayButton1"]
end

-- C_AddOns.LoadAddOn is the current API; LoadAddOn is a fallback for older clients.
-- Returns true if the Blizzard Calendar UI globals this file needs are available.
local function EnsureBlizzardCalendarLoaded()
	if C_AddOns and C_AddOns.LoadAddOn then
		C_AddOns.LoadAddOn("Blizzard_Calendar")
	elseif LoadAddOn then
		LoadAddOn("Blizzard_Calendar")
	end
	return MenuUtil and MenuUtil.CreateContextMenu and GenerateDayContextMenu and CalendarFrame
end

-- The create-event dialog and the "view event" frames are all parent="CalendarFrame"
-- in Blizzard's XML, and WoW only renders a frame if its whole ancestor chain is
-- shown. We never open the real CalendarFrame, so it's parked off-screen (rather
-- than hidden) to satisfy that without it visually intruding.
--
-- All of those frames are shown via the shared CalendarFrame_ShowEventFrame(frame),
-- so hooking that once covers all of them. Left alone if the player already has
-- their real calendar open.
local weParkedCalendarFrame = false
local hookedShowEventFrame = false
local hookedCalendarMutations = false

-- Tracks the event-info frame most recently shown via CalendarFrame_ShowEventFrame,
-- and which event (startSerial:eventID) ShowEventInfo last opened -- lets a
-- second click on the same event's bar toggle it closed instead of reopening it.
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

	-- CALENDAR_UPDATE_EVENT_LIST normally triggers the cache rebuild, but there
	-- can be a delay before it fires. Force a rebuild directly on delete/paste
	-- instead of waiting for it.
	if not hookedCalendarMutations then
		hookedCalendarMutations = true
		hooksecurefunc(C_Calendar, "ContextMenuEventRemove", function()
			CalendarPlus.CalendarProvider:InvalidateAll()
		end)
		hooksecurefunc(C_Calendar, "ContextMenuEventPaste", function()
			CalendarPlus.CalendarProvider:InvalidateAll()
		end)
	end
end

-- Restores CalendarFrame to hidden, only if we were the one who parked it.
-- Called from CalendarPlusMainFrame's OnHide, not from any individual dialog
-- closing -- CalendarFrame stays parked for as long as our window is open.
function CalendarPlus.RestoreCalendarFrameIfParked()
	if weParkedCalendarFrame then
		weParkedCalendarFrame = false
		CalendarFrame:Hide()
	end
end

-- monthOffset is relative to C_Calendar's shared "currently selected month",
-- so it must be anchored to "today" first, or the offset resolves against
-- whatever month was last selected by anything else.
local function ResolveMonthOffset(serial)
	local year, month = CalendarPlus.DateMath.FromSerial(serial)
	local today = C_DateAndTime.GetCurrentCalendarTime()
	local baseIndex = today.year * 12 + (today.month - 1)
	return (year * 12 + (month - 1)) - baseIndex
end

-- Called when CalendarPlus's window opens so CalendarFrame is already parked
-- off-screen ahead of time, instead of loading reactively on first click.
-- Silent on failure since this just warms things up in the background.
function CalendarPlus.EnsureCalendarUIReady()
	if not EnsureBlizzardCalendarLoaded() then return end
	EnsureCalendarFrameParked()
end

-- Shared setup for both context-menu entry points: loads Blizzard_Calendar,
-- anchors C_Calendar's selection to today, parks CalendarFrame, and points
-- the borrowed real day button at the given day. Returns nil (after printing
-- a message) if Blizzard's Calendar UI isn't available.
local function PrepareDayButton(serial)
	if not EnsureBlizzardCalendarLoaded() then
		print("|cff33ff99CalendarPlus|r: couldn't open the calendar's event menu (Blizzard's own Calendar UI wasn't available).")
		return nil
	end

	local realDayButton = GetRealDayButton()
	if not realDayButton then
		print("|cff33ff99CalendarPlus|r: couldn't open the calendar's event menu (Blizzard's own Calendar UI wasn't available).")
		return nil
	end

	local _, _, day = CalendarPlus.DateMath.FromSerial(serial)
	local monthOffset = ResolveMonthOffset(serial)

	CalendarPlus.CalendarProvider:AnchorToCurrentMonth()
	EnsureCalendarFrameParked()

	realDayButton.day = day
	realDayButton.monthOffset = monthOffset
	return realDayButton
end

-- serial: the day cell's absolute DateMath serial day number.
function CalendarPlus.ShowDayContextMenu(cellFrame, serial)
	if not serial then return end

	local realDayButton = PrepareDayButton(serial)
	if not realDayButton then return end

	local ok, err = pcall(function()
		MenuUtil.CreateContextMenu(cellFrame, function(owner, rootDescription)
			GenerateDayContextMenu(owner, rootDescription, CALENDAR_CONTEXTMENU_FLAG_SHOWDAY, realDayButton, nil)
		end)
	end)
	if not ok then
		print("|cff33ff99CalendarPlus|r: couldn't open the calendar's event menu (" .. tostring(err) .. ").")
	end
end

-- barFrame: the clicked EventBarMixin bar, used as the menu's screen anchor.
-- eventButton is only ever read as plain data (.eventIndex) by Blizzard's
-- code, no widget methods, so a bare table is enough here (unlike dayButton).
function CalendarPlus.ShowEventContextMenu(barFrame, startSerial, eventID)
	if not startSerial or not eventID then return end

	local year, month, day = CalendarPlus.DateMath.FromSerial(startSerial)
	CalendarPlus.CalendarProvider:AnchorToMonth(year, month)
	local eventIndex = CalendarPlus.CalendarProvider:ResolveEventIndex(0, day, eventID)
	if not eventIndex then
		print("|cff33ff99CalendarPlus|r: this event no longer exists.")
		return
	end

	local realDayButton = PrepareDayButton(startSerial)
	if not realDayButton then return end

	local eventButton = { eventIndex = eventIndex }
	local flags = CALENDAR_CONTEXTMENU_FLAG_SHOWDAY + CALENDAR_CONTEXTMENU_FLAG_SHOWEVENT

	local ok, err = pcall(function()
		MenuUtil.CreateContextMenu(barFrame, function(owner, rootDescription)
			GenerateDayContextMenu(owner, rootDescription, flags, realDayButton, eventButton)
		end)
	end)
	if not ok then
		print("|cff33ff99CalendarPlus|r: couldn't open this event's menu (" .. tostring(err) .. ").")
	end
end

-- C_Calendar.OpenEvent kicks off an async fetch; CalendarFrame reacts once it
-- completes, picking which view frame to show (or CalendarCreateEventFrame in
-- edit mode). Nothing further to do here beyond making sure it renders.
function CalendarPlus.ShowEventInfo(startSerial, eventID)
	if not startSerial or not eventID then return end

	local eventKey = startSerial .. ":" .. eventID
	if eventKey == lastOpenedEventKey and lastShownFrame and lastShownFrame:IsShown() then
		lastShownFrame:Hide()
		lastOpenedEventKey = nil
		return
	end

	if not EnsureBlizzardCalendarLoaded() then
		print("|cff33ff99CalendarPlus|r: couldn't open this event's info (Blizzard's own Calendar UI wasn't available).")
		return
	end

	if not (C_Calendar and C_Calendar.OpenEvent) then
		print("|cff33ff99CalendarPlus|r: couldn't open this event's info (C_Calendar.OpenEvent wasn't available).")
		return
	end

	local year, month, day = CalendarPlus.DateMath.FromSerial(startSerial)
	CalendarPlus.CalendarProvider:AnchorToMonth(year, month)
	EnsureCalendarFrameParked()

	local eventIndex = CalendarPlus.CalendarProvider:ResolveEventIndex(0, day, eventID)
	if not eventIndex then
		print("|cff33ff99CalendarPlus|r: this event no longer exists.")
		return
	end

	lastOpenedEventKey = eventKey
	C_Calendar.OpenEvent(0, day, eventIndex)
end
