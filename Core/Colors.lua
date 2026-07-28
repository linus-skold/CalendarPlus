local ADDON_NAME, ns = ...

CalendarPlus = CalendarPlus or {}

-- Ports the CSS custom-property palette from the mockup into plain Lua tables.
CalendarPlus.Colors = {
	-- Blizzard's rotating systemwide feed (Timewalking, PvP Brawls, bonus
	-- events, real holidays, one-off promos), matching the reference
	-- mockup's 5-category legend: Weekly rotation / Bonus event / Monthly /
	-- Seasonal-holiday / Special-limited. See GetForEvent for how a given
	-- event lands in one of these.
	weekly    = { r = 0.35, g = 0.62, b = 0.93 },
	bonus     = { r = 0.42, g = 0.53, b = 0.90 },
	monthly   = { r = 0.62, g = 0.44, b = 0.86 },
	seasonal  = { r = 0.93, g = 0.68, b = 0.28 },
	special   = { r = 0.86, g = 0.40, b = 0.30 },

	-- Player-made invites (raid/dungeon/meeting signups) are a different axis
	-- entirely from the systemwide feed above -- kept on the plain eventType
	-- classification instead.
	raid      = { r = 0.86, g = 0.34, b = 0.34 },
	dungeon   = { r = 0.36, g = 0.74, b = 0.55 },
	guild     = { r = 0.45, g = 0.75, b = 0.83 },
	personal  = { r = 0.55, g = 0.55, b = 0.58 },
	default   = { r = 0.5,  g = 0.5,  b = 0.5 },

	-- Pastel coral for events that only run a single day, regardless of
	-- category -- overridden by anything more specific (expansion colors,
	-- faction colors) in EventBarMixin's color priority.
	singleDay = { r = 0.95, g = 0.55, b = 0.45 },
}

-- The player's own faction color, used as a colorOverride for PvP-flavored
-- systemwide events (PvP Brawl, Battleground/Arena Skirmish Bonus Events) --
-- a cleaner, more meaningful signal than a fixed pink for everything PvP.
-- Neutral/unknown (faction not yet chosen) falls back to a plain pink.
CalendarPlus.Colors.faction = { r = 0.85, g = 0.45, b = 0.62 }
local factionGroup = UnitFactionGroup("player")
if factionGroup == "Horde" then
	CalendarPlus.Colors.faction = { r = 0.78, g = 0.13, b = 0.13 }
elseif factionGroup == "Alliance" then
	CalendarPlus.Colors.faction = { r = 0.16, g = 0.44, b = 0.80 }
end

-- Player-made invites (calendarType PLAYER/GUILD/ARENA) map cleanly via
-- eventType. There is no Enum.CalendarEventType.Holiday -- Blizzard's own
-- systemwide feed is identified separately via calendarType == "HOLIDAY".
CalendarPlus.EventTypeToCategory = {
	[Enum.CalendarEventType.Raid]    = "raid",
	[Enum.CalendarEventType.Dungeon] = "dungeon",
	[Enum.CalendarEventType.Meeting] = "guild",
}

-- Blizzard's systemwide feed all comes back as calendarType == "HOLIDAY"
-- regardless of what it actually is, and eventType is almost always just
-- "Other" for it -- so eventType/calendarType can't tell weekly rotations
-- apart from bonus events, monthly contests, real holidays, and one-off
-- promos. The only signal left is the title, patterned after the reference
-- mockup's own category assignments for these exact event names.
-- Only used for the 5-bucket color/category classification below -- the
-- Listed/Unlisted event picker (see CalendarProvider:GetKnownEventKeys) keys
-- off each event's actual resolved title instead of this pattern list, so
-- every distinct event (each individual PvP Brawl variant, each specific
-- one-off promo) gets its own row rather than being lumped into a shared
-- "Timewalking"/"Other" bucket.
local SYSTEM_FEED_PATTERNS = {
	{ pattern = "Timewalking", category = "weekly" },
	{ pattern = "PvP Brawl", category = "weekly" },
	{ pattern = "Bonus Event", category = "bonus" },
	{ pattern = "Darkmoon Faire", category = "monthly" },
	{ pattern = "Trial of Style", category = "monthly" },
	{ pattern = "Fire Festival", category = "seasonal" },
	{ pattern = "Fireworks Spectacular", category = "seasonal" },
	{ pattern = "Love is in the Air", category = "seasonal" },
	{ pattern = "Lunar Festival", category = "seasonal" },
	{ pattern = "Brewfest", category = "seasonal" },
	{ pattern = "Hallow's End", category = "seasonal" },
	{ pattern = "Winter Veil", category = "seasonal" },
	{ pattern = "Children's Week", category = "seasonal" },
	{ pattern = "Pilgrim's Bounty", category = "seasonal" },
	{ pattern = "Noblegarden", category = "seasonal" },
	{ pattern = "Anniversary", category = "seasonal" },
}

function CalendarPlus.Colors:GetForEvent(eventInfo)
	if eventInfo.calendarType ~= "HOLIDAY" then
		local category = CalendarPlus.EventTypeToCategory[eventInfo.eventType] or "personal"
		return self[category], category
	end

	local title = eventInfo.title or ""
	for _, entry in ipairs(SYSTEM_FEED_PATTERNS) do
		if title:find(entry.pattern, 1, true) then
			return self[entry.category], entry.category
		end
	end

	-- Unrecognized systemwide feed entry -- one-off/limited-time promos
	-- (Turbulent Timeways, Auction House Dance Party, etc.) are the natural
	-- catch-all here for COLOR purposes only; the Listed/Unlisted picker
	-- still lists each one individually by its own title.
	return self.special, "special"
end

-- Approximate expansion brand colors, keyed by the same labels
-- CalendarProvider's EXPANSION_PATTERNS produces, for Timewalking event bars
-- to be colored by expansion instead of the generic "weekly" category.
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

-- A warm gold/parchment scale (replacing the earlier cool dark blue-gray
-- one) so the window's own tint actually agrees with Blizzard's stock
-- UI-DialogBox-Border edge art (see ApplyDialogBackdrop) -- that border has
-- always been a warm tan/gold parchment design, which read as mismatched
-- sitting behind a cool blue-gray backdrop. Values are original, chosen to
-- evoke the same warm ornate-parchment feel as other polished modern
-- WoW addon UIs, not sampled or copied from any of them.
CalendarPlus.Colors.surface = {
	appBg  = { r = 0.075, g = 0.052, b = 0.036 }, -- window backdrop
	panel  = { r = 0.130, g = 0.095, b = 0.068 }, -- grid area
	panel2 = { r = 0.163, g = 0.122, b = 0.088 }, -- day cells
	card   = { r = 0.203, g = 0.155, b = 0.113 }, -- raised/hover surfaces
	line   = { r = 0.55,  g = 0.42,  b = 0.24 },  -- cell dividers (gold-brown, was blue-gray)
	accent = { r = 0.80,  g = 0.64,  b = 0.32 },  -- brighter gold, for section-divider-style accents
}
