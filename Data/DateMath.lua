local ADDON_NAME, ns = ...

CalendarPlus = CalendarPlus or {}

-- Pure calendar math, no C_Calendar dependency -- avoids C_Calendar's shared,
-- mutable "currently selected month" state entirely.
--
-- "Serial day" = a plain integer day count (days since 1970-01-01), using
-- Howard Hinnant's days_from_civil / civil_from_days algorithm
-- (http://howardhinnant.github.io/date_algorithms.html), correct across the
-- whole proleptic Gregorian calendar. Turns date arithmetic into plain
-- integer add/subtract.
local DateMath = {}
CalendarPlus.DateMath = DateMath

function DateMath.ToSerial(year, month, day)
	local y = month <= 2 and year - 1 or year
	local era = math.floor((y >= 0 and y or y - 399) / 400)
	local yoe = y - era * 400 -- [0, 399]
	local mp = (month + 9) % 12 -- Mar=0 .. Feb=11
	local doy = math.floor((153 * mp + 2) / 5) + day - 1 -- [0, 365]
	local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy -- [0, 146096]
	return era * 146097 + doe - 719468
end

function DateMath.FromSerial(serial)
	local z = serial + 719468
	local era = math.floor((z >= 0 and z or z - 146096) / 146097)
	local doe = z - era * 146097 -- [0, 146096]
	local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365) -- [0, 399]
	local y = yoe + era * 400
	local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100)) -- [0, 365]
	local mp = math.floor((5 * doy + 2) / 153) -- [0, 11]
	local day = doy - math.floor((153 * mp + 2) / 5) + 1 -- [1, 31]
	local month = mp < 10 and mp + 3 or mp - 9 -- [1, 12]
	if month <= 2 then y = y + 1 end
	return y, month, day
end

function DateMath.DaysInMonth(year, month)
	local nextYear, nextMonth = year, month + 1
	if nextMonth > 12 then
		nextYear, nextMonth = year + 1, 1
	end
	return DateMath.ToSerial(nextYear, nextMonth, 1) - DateMath.ToSerial(year, month, 1)
end

-- 1=Sunday..7=Saturday, matching C_Calendar's own weekday/firstWeekday
-- convention. 1970-01-01 (serial 0) was a Thursday (=5 in this convention).
function DateMath.WeekdayOfSerial(serial)
	return ((serial + 4) % 7) + 1
end

-- today's serial day, derived from the WoW server's calendar time
-- (C_DateAndTime.GetCurrentCalendarTime), not the player's local system clock.
function DateMath.TodaySerial()
	local t = C_DateAndTime.GetCurrentCalendarTime()
	return DateMath.ToSerial(t.year, t.month, t.monthDay), t
end
