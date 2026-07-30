local ADDON_NAME, ns = ...

CalendarPlus = CalendarPlus or {}

-- Built once DB_READY fires so CalendarPlus.db already has its defaults
-- copied in. Reads/writes CalendarPlus.db.weekStartDay via
-- Settings.RegisterAddOnSetting, same field /calendarplus weekstart uses.
local WEEKDAY_LABELS = {
	"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
}

local BuildEventListSubcategory -- forward-declared, defined below

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

	BuildEventListSubcategory(category)

	Settings.RegisterAddOnCategory(category)

	-- Lets the main window's settings-gear button jump straight here.
	CalendarPlus.settingsCategory = category
end

-- Settings.OpenToCategory has a well-known Blizzard quirk where the very
-- first call in a session (before the Settings frame has ever been shown)
-- opens the frame but doesn't actually select the requested category --
-- calling it twice is the standard workaround.
function CalendarPlus.OpenSettings()
	if not CalendarPlus.settingsCategory then return end
	local id = CalendarPlus.settingsCategory:GetID()
	Settings.OpenToCategory(id)
	Settings.OpenToCategory(id)
end

-- Listed/Unlisted shuttle picker for individual named events (see
-- CalendarProvider:GetKnownEventKeys): finer-grained than the main window's
-- category chips, which toggle a whole category at once. Player-made
-- raid/dungeon/guild invites have arbitrary titles and aren't part of this
-- list. Uses a canvas layout since the vertical layout can't represent a
-- two-list shuttle control.
local ROW_HEIGHT = 20
local LIST_WIDTH = 220
local LIST_HEIGHT = 340
local SCROLLBAR_PAD = 28

BuildEventListSubcategory = function(parentCategory)
	local canvas = CreateFrame("Frame")

	local title = canvas:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("Event Filters")

	local desc = canvas:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	desc:SetPoint("RIGHT", canvas, "RIGHT", -16, 0)
	desc:SetJustifyH("LEFT")
	desc:SetText(
		"Move named events between Listed and Unlisted to control which ones can "
			.. "appear on the calendar. Everything is Listed by default. A category's "
			.. "filter chip on the main window hides itself once every event in it is Unlisted."
	)

	-- Returns (panel, content): panel is the bordered outer frame (fixed
	-- size), content is the scrollable child rows should be parented to and
	-- resized to fit however many rows currently exist.
	local function CreateListPanel(anchorPoint, relativePoint, xOffset, headerText)
		local header = canvas:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		header:SetPoint("BOTTOMLEFT", canvas, "TOPLEFT", 0, 0) -- repositioned below
		header:SetText(headerText)

		local panel = CreateFrame("Frame", nil, canvas, "BackdropTemplate")
		panel:SetSize(LIST_WIDTH, LIST_HEIGHT)
		CalendarPlus:ApplyDialogBackdrop(panel)

		header:ClearAllPoints()
		header:SetPoint("BOTTOMLEFT", panel, "TOPLEFT", 4, 4)

		panel:SetPoint(anchorPoint, desc, relativePoint, xOffset, -20)

		local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
		scroll:SetPoint("TOPLEFT", 4, -4)
		scroll:SetPoint("BOTTOMRIGHT", -SCROLLBAR_PAD, 4)

		local content = CreateFrame("Frame", nil, scroll)
		content:SetSize(LIST_WIDTH - SCROLLBAR_PAD - 4, 1)
		scroll:SetScrollChild(content)

		return panel, content
	end

	local listedPanel, listedContent = CreateListPanel("TOPLEFT", "BOTTOMLEFT", 0, "Listed")
	local unlistedPanel, unlistedContent = CreateListPanel("TOPLEFT", "BOTTOMLEFT", LIST_WIDTH + 60, "Unlisted")

	local rightArrow = CreateFrame("Button", nil, canvas, "UIPanelButtonTemplate")
	rightArrow:SetSize(36, 24)
	rightArrow:SetText(">")
	rightArrow:SetPoint("LEFT", listedPanel, "RIGHT", 12, 0)

	local leftArrow = CreateFrame("Button", nil, canvas, "UIPanelButtonTemplate")
	leftArrow:SetSize(36, 24)
	leftArrow:SetText("<")
	leftArrow:SetPoint("TOP", rightArrow, "BOTTOM", 0, -8)

	local selectedListedKey, selectedUnlistedKey
	local listedRows, unlistedRows = {}, {}

	local function CreateRow(content)
		local row = CreateFrame("Button", nil, content)
		row:SetSize(LIST_WIDTH - SCROLLBAR_PAD - 4, ROW_HEIGHT)

		local hl = row:CreateTexture(nil, "BACKGROUND")
		hl:SetAllPoints()
		local card = CalendarPlus.Colors.surface.card
		hl:SetColorTexture(card.r, card.g, card.b, 1)
		hl:Hide()
		row.highlightTex = hl

		local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		label:SetPoint("LEFT", 6, 0)
		label:SetPoint("RIGHT", -6, 0)
		label:SetJustifyH("LEFT")
		row.label = label

		return row
	end

	local function RenderList(content, rows, keys, selectedKey, onSelect)
		for i, key in ipairs(keys) do
			local row = rows[i]
			if not row then
				row = CreateRow(content)
				rows[i] = row
			end
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
			row.key = key
			row.label:SetText(key)
			row.highlightTex:SetShown(key == selectedKey)
			row:SetScript("OnClick", function() onSelect(key) end)
			row:Show()
		end
		for i = #keys + 1, #rows do
			rows[i]:Hide()
		end
		content:SetHeight(math.max(#keys * ROW_HEIGHT, 1))
	end

	-- Sourced from whatever events have actually occurred within
	-- CalendarProvider's cached build window, keyed by their exact resolved
	-- title, so every distinct event gets its own row.
	local function GetListedAndUnlistedKeys()
		local unlisted = CalendarPlus.db.unlistedEvents
		local listedKeys, unlistedKeys = {}, {}
		for _, entry in ipairs(CalendarPlus.CalendarProvider:GetKnownEventKeys()) do
			if unlisted[entry.key] then
				table.insert(unlistedKeys, entry.key)
			else
				table.insert(listedKeys, entry.key)
			end
		end
		return listedKeys, unlistedKeys
	end

	local function RefreshLists()
		local listedKeys, unlistedKeys = GetListedAndUnlistedKeys()

		RenderList(listedContent, listedRows, listedKeys, selectedListedKey, function(key)
			selectedListedKey = key
			selectedUnlistedKey = nil
			RefreshLists()
		end)
		RenderList(unlistedContent, unlistedRows, unlistedKeys, selectedUnlistedKey, function(key)
			selectedUnlistedKey = key
			selectedListedKey = nil
			RefreshLists()
		end)
	end

	rightArrow:SetScript("OnClick", function()
		if not selectedListedKey then return end
		CalendarPlus.db.unlistedEvents[selectedListedKey] = true
		selectedListedKey = nil
		RefreshLists()
		CalendarPlus.EventBus:Fire("CALENDAR_DATA_INVALIDATED")
	end)

	leftArrow:SetScript("OnClick", function()
		if not selectedUnlistedKey then return end
		CalendarPlus.db.unlistedEvents[selectedUnlistedKey] = nil
		selectedUnlistedKey = nil
		RefreshLists()
		CalendarPlus.EventBus:Fire("CALENDAR_DATA_INVALIDATED")
	end)

	canvas:SetScript("OnShow", RefreshLists)
	RefreshLists()

	Settings.RegisterCanvasLayoutSubcategory(parentCategory, canvas, "Event Filters")
end

CalendarPlus.EventBus:On("DB_READY", BuildSettingsPanel)
