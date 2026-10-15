# statswindow.gd - the owner's Player stats: who signs up, who comes back,
# where players stop, and what gets played (0.47.0).
#
# The owner: "build this and add it in my gm menu as a button somewhere" -
# after "they log in noone is here it is pretty discouraging". The answer to
# "why do they leave?" is in rows the server already keeps; this window asks
# for them (GET /api/server/stats, the API's playerstats/ package) and says
# them in words.
#
# - OPENED FROM THE GM PANEL'S Server tab ("Player stats"), and read on
#   opening. Refresh reads again; the days picker is how far back a player
#   signed up to count as new.
# - PLAYERS ONLY. The server leaves staff, the owner and co-owners out, and
#   says how many - the owner testing all day is not a player.
# - DAYS ARE YOURS: the game sends its UTC offset, so "today" starts at your
#   midnight.
# - THE BIGGEST DROP is worked out here, from the new players' road: the step
#   where the most of them stopped is the one to look at first.
#
# OWNER ONLY, three times over like the save history: the HUD builds it only
# for the owner, refresh() asks Api.is_owner first, and the server is the gate
# that counts - require_owner, a bare 404 to anybody else.
class_name StatsWindow
extends Control


const PATH := "/api/server/stats"
# How far back a player signed up to count as new, as the picker offers it.
const DAY_CHOICES := [7, 30, 90]
const DEFAULT_DAYS := 30

const HEAD := Color(0.93, 0.73, 0.3)
const PLAIN := Color(0.84, 0.88, 0.93)
const DIM := Color(0.55, 0.6, 0.67)
const GOOD := Color(0.55, 0.86, 0.6)
const BAD := Color(0.95, 0.55, 0.5)
const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

var _window: PanelWindow = null
var _busy: bool = false
# The last report read, as the server sent it.
var report: Dictionary = {}

# WHERE A REQUEST GOES, a Callable so the suite can answer without a server.
var get_request: Callable

@onready var report_box: RichTextLabel = %statsreport
@onready var days_pick: OptionButton = %statsdays
@onready var refresh_button: Button = %statsrefresh
@onready var status: Label = %statsstatus
@onready var close_button: Button = %statsclose


func _init() -> void:
	get_request = Callable(Api, "get_json")


func _ready() -> void:
	_window = PanelWindow.attach(self, "statswindow")
	close_button.pressed.connect(close)
	refresh_button.pressed.connect(refresh)
	days_pick.clear()
	for choice in DAY_CHOICES:
		days_pick.add_item("%d days" % choice, choice)
	days_pick.select(DAY_CHOICES.find(DEFAULT_DAYS))
	days_pick.item_selected.connect(func(_index: int) -> void: refresh())


func open() -> void:
	"""Show the window, and read the numbers."""
	visible = true
	await refresh()


func close() -> void:
	visible = false


func days() -> int:
	return days_pick.get_item_id(days_pick.selected) if days_pick.selected >= 0 else DEFAULT_DAYS


func refresh() -> void:
	"""Ask the server for the report, in this computer's days."""
	if not Api.is_owner:
		_say("The player stats are the owner's.", true)
		return
	if _busy:
		return
	_busy = true
	_say("Reading the numbers...")
	var now: int = int(Time.get_unix_time_from_system())
	var path: String = "%s?days=%d&offset=%d" % [PATH, days(), LocalTime.bias_minutes_at(now)]
	var res: Dictionary = await get_request.call(path)
	_busy = false
	if not is_instance_valid(self) or not is_inside_tree():
		return
	if not res.get("ok", false) or not (res.get("data") is Dictionary):
		_say(refusal(res), true)
		return
	report = res.get("data")
	show_report(report)
	_say("Read at %s." % LocalTime.clock(int(report.get("now", now))))


func show_report(data: Dictionary) -> void:
	"""The report into the box. add_text, never BBCode: an area's name is the
	server's word, and markup in it would be markup."""
	report_box.clear()
	for line in report_lines(data):
		var heading: bool = bool(line[2]) if line.size() > 2 else false
		if heading:
			report_box.push_font_size(14)
		report_box.push_color(line[1])
		report_box.add_text(str(line[0]))
		report_box.pop()
		if heading:
			report_box.pop()
		report_box.newline()


func _say(line: String, bad: bool = false) -> void:
	status.text = line
	status.add_theme_color_override("font_color", BAD if bad else DIM)


static func refusal(res: Dictionary) -> String:
	var code: int = int(res.get("status", 0))
	if code == 0:
		return "Could not reach the server."
	if code == 404:
		# Only the owner opens this, so a 404 is a server from before 0.47.0.
		return "This server does not have the player stats yet (404). Update the server, then Refresh."
	return "The server refused (%d): %s" % [code, str(res.get("error", ""))]


# =============================================================================
# THE WORDS
# =============================================================================

static func share(part: int, whole: int) -> String:
	"""'(60%)', or '' when there is nothing to be a share of."""
	return "" if whole <= 0 else " (%d%%)" % roundi(100.0 * float(part) / float(whole))


static func day_text(day: String) -> String:
	"""'2026-10-15' -> 'Oct 15'."""
	var bits: PackedStringArray = day.split("-")
	if bits.size() != 3 or not bits[1].is_valid_int() or not bits[2].is_valid_int():
		return day
	var month: int = clampi(int(bits[1]), 1, 12)
	return "%s %d" % [MONTHS[month - 1], int(bits[2])]


static func biggest_drop(road: Dictionary) -> String:
	"""The step of the new players' road where the most of them stopped, in
	words - or '' when nobody new has come."""
	var steps: Array = [
		["signed up", int(road.get("signed_up", 0))],
		["made a character", int(road.get("made_character", 0))],
		["killed a monster", int(road.get("first_kill", 0))],
		["reached level 5", int(road.get("level_5", 0))],
	]
	var worst: int = 0
	var at: int = -1
	for i in range(1, steps.size()):
		var lost: int = int(steps[i - 1][1]) - int(steps[i][1])
		if lost > worst:
			worst = lost
			at = i
	if at < 0:
		return ""
	return "The biggest drop: %d of %d who %s never %s." % [worst, int(steps[at - 1][1]),
		str(steps[at - 1][0]), str(steps[at][0])]


static func _counts(rows: Array, key: String, label_key: String) -> String:
	var parts: Array[String] = []
	for row in rows:
		if row is Dictionary and int((row as Dictionary).get(key, 0)) > 0:
			parts.append("%s %d" % [str((row as Dictionary).get(label_key, "")), int((row as Dictionary).get(key, 0))])
	return ", ".join(parts) if not parts.is_empty() else "none"


static func report_lines(data: Dictionary) -> Array:
	"""The report as [text, colour, heading] lines - what the box shows, and
	what the suite reads."""
	var lines: Array = []
	var p: Dictionary = data.get("players", {}) if data.get("players") is Dictionary else {}
	lines.append(["PLAYERS", HEAD, true])
	lines.append(["%d players%s." % [int(p.get("total", 0)),
		(" (%d staff left out)" % int(p.get("staff_left_out", 0))) if int(p.get("staff_left_out", 0)) > 0 else ""], PLAIN])
	lines.append(["New: %d today, %d this week, %d this month." % [int(p.get("new_today", 0)),
		int(p.get("new_7d", 0)), int(p.get("new_30d", 0))], PLAIN])
	lines.append(["Seen: %d today, %d this week, %d this month." % [int(p.get("seen_today", 0)),
		int(p.get("seen_7d", 0)), int(p.get("seen_30d", 0))], PLAIN])

	var road: Dictionary = data.get("road", {}) if data.get("road") is Dictionary else {}
	var joined: int = int(road.get("signed_up", 0))
	lines.append(["", PLAIN])
	lines.append(["NEW PLAYERS - signed up in the last %d days" % int(road.get("days", DEFAULT_DAYS)), HEAD, true])
	if joined == 0:
		lines.append(["Nobody new in these days.", DIM])
	else:
		lines.append(["Signed up: %d" % joined, PLAIN])
		lines.append(["Made a character: %d%s" % [int(road.get("made_character", 0)), share(int(road.get("made_character", 0)), joined)], PLAIN])
		lines.append(["Killed a monster: %d%s" % [int(road.get("first_kill", 0)), share(int(road.get("first_kill", 0)), joined)], PLAIN])
		lines.append(["Reached level 5: %d%s" % [int(road.get("level_5", 0)), share(int(road.get("level_5", 0)), joined)], PLAIN])
		lines.append(["Reached level 10: %d%s" % [int(road.get("level_10", 0)), share(int(road.get("level_10", 0)), joined)], PLAIN])
		var back_of: int = int(road.get("came_back_of", 0))
		if back_of > 0:
			lines.append(["Came back a day or more later: %d of %d%s" % [int(road.get("came_back", 0)), back_of,
				share(int(road.get("came_back", 0)), back_of)], GOOD if int(road.get("came_back", 0)) > 0 else BAD])
		var week_of: int = int(road.get("stayed_week_of", 0))
		if week_of > 0:
			lines.append(["Still around a week later: %d of %d%s" % [int(road.get("stayed_week", 0)), week_of,
				share(int(road.get("stayed_week", 0)), week_of)], GOOD if int(road.get("stayed_week", 0)) > 0 else BAD])
		if road.get("minutes_to_first_kill") != null:
			lines.append(["First kill: %s minutes after signing up (the middle player)" %
				str(snappedf(float(road.get("minutes_to_first_kill")), 0.1)), PLAIN])
		var drop: String = biggest_drop(road)
		if drop != "":
			lines.append([drop, BAD])

	var stopped: Dictionary = data.get("quit", {}) if data.get("quit") is Dictionary else {}
	lines.append(["", PLAIN])
	lines.append(["WHERE PLAYERS STOPPED - not seen for %d days: %d" % [int(stopped.get("quiet_days", 3)),
		int(stopped.get("players", 0))], HEAD, true])
	if int(stopped.get("players", 0)) > 0:
		lines.append(["How long they played: " + _counts(stopped.get("stayed", []), "players", "label"), PLAIN])
		lines.append(["How far they got: " + _counts(stopped.get("levels", []), "players", "label"), PLAIN])
		var areas: Array = []
		for row in stopped.get("areas", []):
			if row is Dictionary:
				areas.append({"area": str((row as Dictionary).get("area", "")).capitalize(),
					"players": int((row as Dictionary).get("players", 0))})
		lines.append(["Where they were last: " + _counts(areas, "players", "area"), PLAIN])
		lines.append(["Never killed anything: %d" % int(stopped.get("never_killed", 0)), PLAIN])

	lines.append(["", PLAIN])
	lines.append(["DAY BY DAY - your days, newest first", HEAD, true])
	for row in data.get("daily", []):
		if row is Dictionary:
			lines.append(["%s   new %d   played %d" % [day_text(str((row as Dictionary).get("day", ""))),
				int((row as Dictionary).get("new", 0)), int((row as Dictionary).get("played", 0))],
				PLAIN if int((row as Dictionary).get("played", 0)) > 0 else DIM])

	var monsters: Dictionary = data.get("monsters", {}) if data.get("monsters") is Dictionary else {}
	lines.append(["", PLAIN])
	lines.append(["MONSTERS - the last %d days: %d kills" % [int(monsters.get("days", 14)),
		int(monsters.get("kills", 0))], HEAD, true])
	var most: Array[String] = []
	for row in monsters.get("most", []):
		if row is Dictionary:
			most.append("%s %d (%d players)" % [str((row as Dictionary).get("name", "")),
				int((row as Dictionary).get("kills", 0)), int((row as Dictionary).get("players", 0))])
	lines.append(["Most hunted: " + (", ".join(most) if not most.is_empty() else "none"), PLAIN])
	var least: Array[String] = []
	for row in monsters.get("least", []):
		if row is Dictionary:
			least.append("%s %d" % [str((row as Dictionary).get("name", "")), int((row as Dictionary).get("kills", 0))])
	lines.append(["Least hunted: " + (", ".join(least) if not least.is_empty() else "none"), PLAIN])
	lines.append(["Never killed: %d of %d kinds" % [int(monsters.get("never", 0)), int(monsters.get("kinds", 0))], PLAIN])

	lines.append(["", PLAIN])
	lines.append(["CLASSES", HEAD, true])
	var classes: Array[String] = []
	for row in data.get("classes", []):
		if row is Dictionary:
			classes.append("%s %d (top level %d)" % [str((row as Dictionary).get("class", "")).capitalize(),
				int((row as Dictionary).get("characters", 0)), int((row as Dictionary).get("top_level", 0))])
	lines.append([(", ".join(classes) if not classes.is_empty() else "No characters yet."), PLAIN])
	return lines
