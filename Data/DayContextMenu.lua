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

-- CalendarCreateEventFrame (the actual "Create Event" dialog) is
-- parent="CalendarFrame" in Blizzard's own XML, anchored TOPLEFT relative to
-- CalendarFrame's own TOPRIGHT. We never open the real CalendarFrame, so
-- even though Blizzard's code calls :Show() on the create-event dialog
-- successfully, it never actually becomes visible on screen -- WoW only
-- renders a frame if its *entire* ancestor chain is shown, not just the
-- frame itself. Parking CalendarFrame off-screen (rather than leaving it
-- hidden) satisfies that requirement without it visually intruding, and the
-- dialog's own anchor is then overridden to sit against the right edge of
-- CalendarPlus's own window instead of relative to its now-offscreen parent.
-- Left alone if
-- the player already has their real calendar open -- then everything already
-- works exactly as Blizzard intends, and forcibly moving their own open
-- window would be actively rude.
local weParkedCalendarFrame = false

local function EnsureCalendarFrameVisibleAncestor()
	if CalendarFrame:IsShown() then return end

	weParkedCalendarFrame = true
	CalendarFrame:Show()
	CalendarFrame:ClearAllPoints()
	CalendarFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -5000, 5000)

	if CalendarCreateEventFrame then
		CalendarCreateEventFrame:ClearAllPoints()
		CalendarCreateEventFrame:SetPoint("TOPLEFT", CalendarPlusMainFrame, "TOPRIGHT", 8, 0)

		if not CalendarCreateEventFrame.calendarPlusHooked then
			CalendarCreateEventFrame.calendarPlusHooked = true
			CalendarCreateEventFrame:HookScript("OnHide", function()
				if weParkedCalendarFrame then
					weParkedCalendarFrame = false
					CalendarFrame:Hide()
				end
			end)
		end
	end
end

-- serial: the day cell's absolute DateMath serial day number.
function CalendarPlus.ShowDayContextMenu(cellFrame, serial)
	if not serial then return end

	local year, month, day = CalendarPlus.DateMath.FromSerial(serial)
	local today = C_DateAndTime.GetCurrentCalendarTime()
	local baseIndex = today.year * 12 + (today.month - 1)
	local monthOffset = (year * 12 + (month - 1)) - baseIndex

	-- C_AddOns.LoadAddOn is the current API; older clients only had the
	-- bare global LoadAddOn, kept here as a fallback for safety.
	if C_AddOns and C_AddOns.LoadAddOn then
		C_AddOns.LoadAddOn("Blizzard_Calendar")
	elseif LoadAddOn then
		LoadAddOn("Blizzard_Calendar")
	end

	local realDayButton = GetRealDayButton()
	if not (MenuUtil and MenuUtil.CreateContextMenu and GenerateDayContextMenu and realDayButton) then
		print("|cff33ff99CalendarPlus|r: couldn't open the calendar's event menu (Blizzard's own Calendar UI wasn't available).")
		return
	end

	-- GenerateDayContextMenu and, later, CalendarCreateEventFrame_Update both
	-- resolve dayButton.monthOffset via C_Calendar.GetMonthInfo(monthOffset)
	-- *relative to C_Calendar's own shared "currently selected month"* -- our
	-- monthOffset above is computed relative to today, so that selection has
	-- to actually be sitting on today's month right now, or this resolves to
	-- the wrong month entirely.
	CalendarPlus.CalendarProvider:AnchorToCurrentMonth()
	EnsureCalendarFrameVisibleAncestor()

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
