local ADDON_NAME, ns = ...

CalendarPlus = CalendarPlus or {}

-- Ports the CSS custom-property palette from the mockup into plain Lua tables.
CalendarPlus.Colors = {
	-- Blizzard's rotating systemwide feed (Timewalking, PvP Brawls, bonus
	-- events, real holidays, one-off promos). See GetForEvent for classification.
	weekly    = { r = 0.35, g = 0.62, b = 0.93 },
	monthly   = { r = 0.62, g = 0.44, b = 0.86 },
	seasonal  = { r = 0.93, g = 0.68, b = 0.28 },
	special   = { r = 0.86, g = 0.40, b = 0.30 },

	-- Player-made events (created or invited to) are flattened into one
	-- shared bucket regardless of eventType.
	custom    = { r = 0.80, g = 0.35, b = 0.65 },
	default   = { r = 0.5,  g = 0.5,  b = 0.5 },

	-- Events that only run a single day, regardless of category -- overridden
	-- by expansion/faction colors in EventBarMixin's color priority.
	singleDay = { r = 0.95, g = 0.55, b = 0.45 },
}

-- Colors PvP-flavored systemwide events (PvP Brawl, Battleground/Arena
-- Skirmish Bonus Events) by the player's faction. Neutral/unknown falls
-- back to plain pink.
CalendarPlus.Colors.faction = { r = 0.85, g = 0.45, b = 0.62 }
local factionGroup = UnitFactionGroup("player")
if factionGroup == "Horde" then
	CalendarPlus.Colors.faction = { r = 0.78, g = 0.13, b = 0.13 }
elseif factionGroup == "Alliance" then
	CalendarPlus.Colors.faction = { r = 0.16, g = 0.44, b = 0.80 }
end

-- Blizzard's systemwide feed all comes back as calendarType == "HOLIDAY" with
-- eventType usually just "Other", so title matching is the only way to sort
-- weekly rotations from bonus events, monthly contests, holidays, and promos.
-- Only used for the 5-bucket color classification -- the Listed/Unlisted
-- picker keys off each event's actual title instead, so every distinct event
-- still gets its own row.
-- Lane priority for overlapping bars: Specials, Holiday/Seasonal, Monthly,
-- then Weekly by subtype. Lower sorts first (see Layout.PackLanes), keeping
-- a given category in the same lane across adjacent weeks instead of it
-- flipping depending on which event happened to start first that week.
local RANK_SPECIAL = 10
local RANK_SEASONAL = 20
local RANK_MONTHLY = 30
local RANK_WEEKLY_DUNGEON = 40
local RANK_WEEKLY_TIMEWALKING = 50
local RANK_WEEKLY_PVP = 60
local RANK_WEEKLY_DELVE = 70
local RANK_WEEKLY_PETBATTLE = 80
local RANK_CUSTOM = 90

local SYSTEM_FEED_PATTERNS = {
	{ pattern = "Timewalking", category = "weekly", sortRank = RANK_WEEKLY_TIMEWALKING },
	{ pattern = "PvP Brawl", category = "weekly", sortRank = RANK_WEEKLY_PVP },
	-- These four run on a weekly cadence, unlike other "...Bonus Event"
	-- titles, which fall through to the "special" catch-all instead.
	{ pattern = "Pet Battle Bonus Event", category = "weekly", sortRank = RANK_WEEKLY_PETBATTLE },
	{ pattern = "Delves Bonus Event", category = "weekly", sortRank = RANK_WEEKLY_DELVE },
	{ pattern = "Arena Skirmish Bonus Event", category = "weekly", sortRank = RANK_WEEKLY_PVP },
	{ pattern = "Midnight Dungeon Event", category = "weekly", sortRank = RANK_WEEKLY_DUNGEON },
	{ pattern = "Darkmoon Faire", category = "monthly", sortRank = RANK_MONTHLY },
	{ pattern = "Trial of Style", category = "monthly", sortRank = RANK_MONTHLY },
	{ pattern = "Fire Festival", category = "seasonal", sortRank = RANK_SEASONAL },
	{ pattern = "Fireworks Spectacular", category = "seasonal", sortRank = RANK_SEASONAL },
	{ pattern = "Love is in the Air", category = "seasonal", sortRank = RANK_SEASONAL },
	{ pattern = "Lunar Festival", category = "seasonal", sortRank = RANK_SEASONAL },
	{ pattern = "Brewfest", category = "seasonal", sortRank = RANK_SEASONAL },
	{ pattern = "Hallow's End", category = "seasonal", sortRank = RANK_SEASONAL },
	{ pattern = "Winter Veil", category = "seasonal", sortRank = RANK_SEASONAL },
	{ pattern = "Children's Week", category = "seasonal", sortRank = RANK_SEASONAL },
	{ pattern = "Pilgrim's Bounty", category = "seasonal", sortRank = RANK_SEASONAL },
	{ pattern = "Noblegarden", category = "seasonal", sortRank = RANK_SEASONAL },
	{ pattern = "Anniversary", category = "seasonal", sortRank = RANK_SEASONAL },
}

function CalendarPlus.Colors:GetForEvent(eventInfo)
	-- Player-made events (calendarType PLAYER/GUILD/ARENA) are one flat
	-- "custom" bucket regardless of eventType.
	if eventInfo.calendarType ~= "HOLIDAY" then
		return self.custom, "custom", RANK_CUSTOM
	end

	local title = eventInfo.title or ""
	for _, entry in ipairs(SYSTEM_FEED_PATTERNS) do
		if title:find(entry.pattern, 1, true) then
			return self[entry.category], entry.category, entry.sortRank
		end
	end

	-- Unrecognized systemwide feed entries (one-off/limited-time promos) fall
	-- back to this color; the Listed/Unlisted picker still lists each one
	-- individually by its own title.
	return self.special, "special", RANK_SPECIAL
end

-- Approximate expansion brand colors, keyed by CalendarProvider's
-- EXPANSION_PATTERNS labels, so Timewalking bars are colored by expansion
-- instead of the generic "weekly" category.
CalendarPlus.Colors.expansions = {
	Classic          = { r = 0.75, g = 0.62, b = 0.20 },
	TBC              = { r = 0.35, g = 0.68, b = 0.22 },
	Wrath            = { r = 0.38, g = 0.66, b = 0.87 },
	Cata             = { r = 0.82, g = 0.32, b = 0.14 },
	MoP              = { r = 0.30, g = 0.70, b = 0.55 },
	WoD              = { r = 0.72, g = 0.44, b = 0.20 },
	Legion           = { r = 0.53, g = 0.85, b = 0.28 },
	BfA              = { r = 0.20, g = 0.62, b = 0.62 },
	Shadowlands      = { r = 0.55, g = 0.35, b = 0.75 },
	Dragonflight     = { r = 0.22, g = 0.55, b = 0.78 },
	["War Within"]   = { r = 0.78, g = 0.55, b = 0.22 },
	Midnight         = { r = 0.30, g = 0.25, b = 0.58 },
}

-- Warm gold/parchment scale matching Blizzard's UI-DialogBox-Border edge art
-- (see ApplyDialogBackdrop).
CalendarPlus.Colors.surface = {
	appBg  = { r = 0.075, g = 0.052, b = 0.036 },
	panel  = { r = 0.130, g = 0.095, b = 0.068 },
	panel2 = { r = 0.163, g = 0.122, b = 0.088 },
	card   = { r = 0.203, g = 0.155, b = 0.113 },
	line   = { r = 0.55,  g = 0.42,  b = 0.24 },
	accent = { r = 0.80,  g = 0.64,  b = 0.32 },
}
