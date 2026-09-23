extends RefCounted
class_name WarhammerCalendar
## The Empire's own Imperial Calendar, per the request — a 400-day
## year: twelve months of 32 or 33 days each, plus six intercalary
## holidays that fall outside the normal month/weekday sequence
## entirely (they occupy a real calendar day, but don't get a weekday
## name and don't consume a slot in the 8-day weekday rotation, which
## just continues on unbroken across them).
##
## day_of_year is 0-indexed (0-399). Character creation starts new
## characters at day_of_year 100, which decodes to Sigmarzeit 1 —
## Marktag, per the request — verified against this exact calendar
## model before implementing it.

const MONTH_NAMES := ["Nachexen", "Jahrdrung", "Pflugzeit", "Sigmarzeit", "Sommerzeit", "Vorgeheim",
	"Nachgeheim", "Erntezeit", "Brauzeit", "Kaldezeit", "Ulriczeit", "Vorhexen"]
const MONTH_LENGTHS := [32, 33, 33, 33, 33, 33, 32, 33, 33, 33, 33, 33]
const WEEKDAY_NAMES := ["Wellentag", "Aubentag", "Marktag", "Backertag", "Bezahltag", "Konistag", "Angestag", "Festag"]
## Keyed by the 0-indexed MONTH_NAMES position the holiday falls right
## after; -1 means "before the first month" (Hexenstag opens the year).
const INTERCALARY_AFTER := {
	-1: "Hexenstag",
	2: "Mitterfruhl",
	4: "Sonnstill",
	6: "Geheimnistag",
	8: "Mittherbst",
	10: "Monstille",
}
const DAYS_PER_YEAR := 400
const CHARACTER_CREATION_START_DAY := 100   ## Sigmarzeit 1 — Marktag

class DateInfo:
	var is_intercalary: bool = false
	var holiday_name: String = ""
	var month_name: String = ""
	var day_of_month: int = 0
	var weekday_name: String = ""

	func display_string() -> String:
		if is_intercalary:
			return holiday_name
		return "%s, %d %s" % [weekday_name, day_of_month, month_name]

## Decodes a 0-399 day_of_year into a full DateInfo. Walks the year's
## real sequence (Hexenstag, then each month with its own intercalary
## holiday immediately after where one falls) rather than a closed-
## form formula — the intercalary placement isn't evenly spaced, so a
## direct walk is both simpler and less error-prone than deriving one.
static func decode(day_of_year: int) -> DateInfo:
	var info := DateInfo.new()
	var remaining := ((day_of_year % DAYS_PER_YEAR) + DAYS_PER_YEAR) % DAYS_PER_YEAR
	var weekday_counter := 0

	if INTERCALARY_AFTER.has(-1):
		if remaining == 0:
			info.is_intercalary = true
			info.holiday_name = INTERCALARY_AFTER[-1]
			return info
		remaining -= 1

	for m_idx in range(MONTH_NAMES.size()):
		var length: int = MONTH_LENGTHS[m_idx]
		if remaining < length:
			info.month_name = MONTH_NAMES[m_idx]
			info.day_of_month = remaining + 1
			info.weekday_name = WEEKDAY_NAMES[weekday_counter % WEEKDAY_NAMES.size()]
			return info
		remaining -= length
		weekday_counter += length
		if INTERCALARY_AFTER.has(m_idx):
			if remaining == 0:
				info.is_intercalary = true
				info.holiday_name = INTERCALARY_AFTER[m_idx]
				return info
			remaining -= 1

	## Should be unreachable given DAYS_PER_YEAR == the real total of
	## every month length plus every intercalary day, but returning a
	## clearly-invalid DateInfo here (rather than crashing) is the
	## safer failure if that invariant is ever broken by a future edit.
	info.month_name = "?"
	info.day_of_month = 0
	info.weekday_name = "?"
	return info
