local ADDON_NAME, ns = ...

CalendarPlus = CalendarPlus or {}

-- Blizzard's Settings API (patch 10.0+): a vertical-layout category gets you
-- a Blizzard-styled panel (checkboxes/dropdowns auto-positioned) without
-- having to hand-build a dropdown widget ourselves. Built once DB_READY
-- fires so CalendarPlus.db already has its defaults copied in -- the panel
-- reads/writes CalendarPlus.db.weekStartDay directly via
-- Settings.RegisterAddOnSetting, same field /calendarplus weekstart uses.
local WEEKDAY_LABELS = {
	"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
}

local function BuildSettingsPanel()
	local category = Settings.RegisterVerticalLayoutCategory("CalendarPlus")

	local weekStartSetting = Settings.RegisterAddOnSetting(
		category, "CalendarPlus_WeekStartDay", "weekStartDay",
		CalendarPlus.db, "number", "Week starts on", 2
	)
	weekStartSetting:SetValueChangedCallback(function()
		CalendarPlus.EventBus:Fire("CALENDAR_DATA_INVALIDATED")
	end)

	local function GetWeekdayOptions()
		local container = Settings.CreateControlTextContainer()
		for i, label in ipairs(WEEKDAY_LABELS) do
			container:Add(i, label)
		end
		return container:GetData()
	end

	Settings.CreateDropdown(
		category, weekStartSetting, GetWeekdayOptions,
		"Which day the calendar grid and agenda week start on."
	)

	local trimSetting = Settings.RegisterAddOnSetting(
		category, "CalendarPlus_TrimWeeklyEventsAtReset", "trimWeeklyEventsAtReset",
		CalendarPlus.db, "boolean", "Trim weekly events at reset", true
	)
	trimSetting:SetValueChangedCallback(function()
		CalendarPlus.EventBus:Fire("CALENDAR_DATA_INVALIDATED")
	end)
	Settings.CreateCheckbox(
		category, trimSetting,
		"Ends weekly-cadence events (Timewalking, PvP Brawls, etc.) the day before "
			.. "weekly reset instead of on it, so the outgoing and incoming week's "
			.. "events don't overlap on the reset day itself."
	)

	Settings.RegisterAddOnCategory(category)
end

CalendarPlus.EventBus:On("DB_READY", BuildSettingsPanel)
