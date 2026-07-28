local ADDON_NAME, ns = ...

CalendarPlus = CalendarPlus or {}
local addon = CalendarPlus

local defaultAccountDB = {
	weekStartDay = 2, -- 1=Sunday..7=Saturday (C_DateAndTime convention); 2=Monday
	trimWeeklyEventsAtReset = true,
}

local defaultCharDB = {}

local function CopyDefaults(dst, src)
	for k, v in pairs(src) do
		if dst[k] == nil then
			if type(v) == "table" then
				dst[k] = {}
				CopyDefaults(dst[k], v)
			else
				dst[k] = v
			end
		end
	end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")

eventFrame:SetScript("OnEvent", function(_, event, loadedAddon)
	if event == "ADDON_LOADED" and loadedAddon == ADDON_NAME then
		CalendarPlusDB = CalendarPlusDB or {}
		CalendarPlusCharDB = CalendarPlusCharDB or {}
		CopyDefaults(CalendarPlusDB, defaultAccountDB)
		CopyDefaults(CalendarPlusCharDB, defaultCharDB)

		addon.db = CalendarPlusDB
		addon.charDB = CalendarPlusCharDB

		addon.EventBus:Fire("DB_READY")
	end
end)

-- This client's XML schema no longer parses a <Backdrop> node (it logs
-- "Unrecognized XML: Backdrop" and silently drops it), so both top-level
-- windows apply their backdrop here in Lua instead of declaratively in XML.
-- Requires the frame to have inherits="BackdropTemplate" in its XML.
--
-- bgFile is a plain white texture instead of Blizzard's brown stone dialog
-- background, tinted via SetBackdropColor to the reference mockup's
-- --bg-app -- that stone texture never matched the day cells' own color at
-- all, which read as "just black" rather than an intentional palette.
function addon:ApplyDialogBackdrop(frame)
	frame:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = false,
		edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	local appBg = CalendarPlus.Colors.surface.appBg
	frame:SetBackdropColor(appBg.r, appBg.g, appBg.b, 0.97)
end

-- Full names + common abbreviations, all lowercase.
local WEEKDAY_NAME_TO_NUM = {
	sunday = 1, sun = 1,
	monday = 2, mon = 2,
	tuesday = 3, tue = 3, tues = 3,
	wednesday = 4, wed = 4,
	thursday = 5, thu = 5, thur = 5, thurs = 5,
	friday = 6, fri = 6,
	saturday = 7, sat = 7,
}
local WEEKDAY_NUM_TO_NAME = {
	"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
}

local function SplitFirstWord(msg)
	local word, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
	return (word or ""):lower(), rest or ""
end

SLASH_CALENDARPLUS1 = "/calendarplus"
SLASH_CALENDARPLUS2 = "/calplus"
SlashCmdList["CALENDARPLUS"] = function(msg)
	local cmd, rest = SplitFirstWord(msg)

	if cmd == "weekstart" then
		local dayNum = WEEKDAY_NAME_TO_NUM[rest:lower()]
		if not dayNum then
			print("|cff33ff99CalendarPlus|r: usage: /calendarplus weekstart <Sunday..Saturday>")
			return
		end
		addon.db.weekStartDay = dayNum
		addon.EventBus:Fire("CALENDAR_DATA_INVALIDATED")
		print("|cff33ff99CalendarPlus|r: week now starts on " .. WEEKDAY_NUM_TO_NAME[dayNum] .. ".")
		return
	end

	if addon.ToggleMainFrame then
		addon.ToggleMainFrame()
	else
		print("|cff33ff99CalendarPlus|r: main frame not loaded yet.")
	end
end
