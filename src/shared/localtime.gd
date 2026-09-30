class_name LocalTime
extends RefCounted

# =============================================================================
# UNIX SECONDS -> THE CLOCK ON THE PLAYER'S WALL
# =============================================================================
#
# WHY THIS EXISTS. The same six lines were written four times in this project -
# chatpanel.gd, loginmenu.gd, staffpanel.gd and ownerpanel.gd - and the fourth
# copy had quietly dropped the timezone entirely, so the owner panel printed
# UTC and labelled it nothing. Seven hours wrong in Denver, and nothing on
# screen said so. That is the usual fate of a conversion that lives in four
# places: three get fixed and the fourth is discovered by someone confused.
#
# THE SERVER SPEAKS ONE LANGUAGE AND SCREENS SPEAK ANOTHER. Every timestamp
# crossing the wire is unix seconds - no zone, no offset, the same integer for
# everybody. That is exactly right for storage and exactly useless on screen.
# The conversion belongs at the edge, once, and this is the edge.
#
# THE ONE THING IT CANNOT DO, said plainly rather than hidden:
# get_time_zone_from_system() reports the offset in force RIGHT NOW, including
# whether daylight saving is on TODAY. Applied to a timestamp from the other
# side of a DST change it is an hour out. For chat, which is minutes old, that
# never happens; for a broadcast up to a week old it can, twice a year. Fixing
# it properly needs a timezone database, which is not worth shipping to make a
# week-old server notice an hour righter. If that changes, this is the one
# place it changes.


# READ ONCE, LAZILY. get_time_zone_from_system() is a system call, this is
# asked per rendered line, and the offset does not move while somebody plays.
static var _bias_minutes: int = 0
static var _bias_known: bool = false

const WEEKDAYS := ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
const MONTHS := ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun",
	"Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

# What a stamp reads when there is no time to show. NOT an empty string: a
# blank where a clock should be looks like a rendering fault, and this looks
# like what it is - a line whose time nobody recorded.
const UNKNOWN := "--:--"


static func ago(at: int, now: int) -> String:
	"""How long ago, in words: "just now", "5 min ago", "2 h ago", "1 day ago".

	FOUR COPIES OF THIS, AND ONE WAS RIGHT. The guild panel's history had it;
	its roster, the friends list and the staff desk each wrote their own, and
	said "1 days ago" and "0 min ago". Both clocks are unix seconds, and `now`
	should be the server's (every list that shows this carries one), so a
	machine with the wrong time does not age everybody by hours."""
	if at <= 0 or now <= 0:
		return ""
	var gap: int = maxi(0, now - at)
	if gap < 60:
		return "just now"
	if gap < 3600:
		return "%d min ago" % int(gap / 60.0)
	if gap < 86400:
		return "%d h ago" % int(gap / 3600.0)
	var days: int = int(gap / 86400.0)
	return "1 day ago" if days == 1 else "%d days ago" % days


static func bias_minutes() -> int:
	if not _bias_known:
		_bias_minutes = int(Time.get_time_zone_from_system().get("bias", 0))
		_bias_known = true
	return _bias_minutes


static func parts(unix_time: int) -> Dictionary:
	"""The local calendar dictionary for a unix timestamp.

	SHIFT THEN READ. Godot's get_datetime_dict_from_unix_time() is UTC with no
	way to ask it for anything else, so the offset goes on the integer BEFORE
	it is decomposed. Every field that comes back - hour, day, weekday - is
	then local, because they are all pure functions of the shifted number."""
	return Time.get_datetime_dict_from_unix_time(unix_time + bias_minutes() * 60)


static func clock(unix_time: int) -> String:
	"""Just the time: 14:32. For a line that is obviously from today."""
	if unix_time <= 0:
		return UNKNOWN
	var local: Dictionary = parts(unix_time)
	return "%02d:%02d" % [int(local.get("hour", 0)), int(local.get("minute", 0))]


static func stamp(unix_time: int) -> String:
	"""The time, plus as much date as it takes to be unambiguous.

		today            14:32
		within a week    Sat 14:32
		older            Sep 21 14:32

	A BARE CLOCK IS ONLY TRUE FOR TODAY, and that is the whole reason this
	function is not just clock(). The server hands a player who has just
	logged in the TAIL of the broadcast table - up to a week of notices, all
	at once. Stamped "14:32" apiece they read as a week of things that are
	happening now, which is worse than no stamp at all: it does not merely
	fail to inform, it actively misinforms. The date is what turns that dump
	back into history.

	GROWS ONLY AS MUCH AS IT HAS TO. Putting the full date on every line would
	cost a third of the width of a chat message to repeat the same eight
	characters down the whole log. Today's lines - which is nearly all of
	them, nearly all of the time - stay four characters wide."""
	if unix_time <= 0:
		return UNKNOWN

	var local: Dictionary = parts(unix_time)
	var now: Dictionary = parts(int(Time.get_unix_time_from_system()))
	var time_part: String = "%02d:%02d" % [
		int(local.get("hour", 0)), int(local.get("minute", 0))]

	if (int(local.get("year", 0)) == int(now.get("year", 0))
			and int(local.get("month", 0)) == int(now.get("month", 0))
			and int(local.get("day", 0)) == int(now.get("day", 0))):
		return time_part

	# SIX DAYS, NOT SEVEN. At seven "Sat" is ambiguous between this Saturday
	# and the one before it, which is the exact confusion a date is here to
	# remove. Measured in whole local days so that 23:59 yesterday reads as
	# "yesterday" rather than as "an hour ago".
	var days: int = int(floor((float(_local_midnight(now)) - float(_local_midnight(local))) / 86400.0))
	if days >= 0 and days <= 6:
		return "%s %s" % [WEEKDAYS[int(local.get("weekday", 0)) % 7], time_part]

	var month: int = clampi(int(local.get("month", 1)), 1, 12)
	return "%s %d %s" % [MONTHS[month], int(local.get("day", 1)), time_part]


static func full(unix_time: int) -> String:
	"""2026-09-27 14:32. For panels that list records rather than conversation.

	A ban expiry or a login history wants the whole date every time - those
	are read one row at a time and compared against a calendar, not skimmed."""
	if unix_time <= 0:
		return UNKNOWN
	var local: Dictionary = parts(unix_time)
	return "%04d-%02d-%02d %02d:%02d" % [
		int(local.get("year", 1970)), int(local.get("month", 1)),
		int(local.get("day", 1)), int(local.get("hour", 0)),
		int(local.get("minute", 0))]


static func date(unix_time: int) -> String:
	"""Sep 27, 2026. For something that happened on a DAY rather than at a time.

	A guild's founding is a date. Nobody cares that it was at 14:32, and
	printing the minute invites a reader to treat the figure as more precise
	than the question deserves - full() keeps its clock because a ban expiry is
	genuinely compared against one.

	EMPTY, NOT UNKNOWN, for a missing time. UNKNOWN is "--:--", which is a
	clock face and would read as a broken time rather than an absent date. A
	caller with nothing to show should leave the clause out, which is what ""
	lets it do."""
	if unix_time <= 0:
		return ""
	var local: Dictionary = parts(unix_time)
	var month: int = clampi(int(local.get("month", 1)), 1, 12)
	return "%s %d, %d" % [MONTHS[month], int(local.get("day", 1)),
		int(local.get("year", 1970))]


static func _local_midnight(local: Dictionary) -> int:
	"""Seconds since the epoch at the start of the local day this describes.

	Built from the calendar fields rather than by rounding the timestamp,
	because rounding rounds in UTC and a day does not start at UTC midnight
	anywhere the offset is not zero."""
	return int(Time.get_unix_time_from_datetime_dict({
		"year": int(local.get("year", 1970)),
		"month": int(local.get("month", 1)),
		"day": int(local.get("day", 1)),
		"hour": 0, "minute": 0, "second": 0,
	}))
