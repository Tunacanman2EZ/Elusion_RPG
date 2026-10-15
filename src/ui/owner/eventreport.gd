# eventreport.gd - the owner's Event report: what each event did (0.49.0).
#
# The owner's: "dashboards that show, for each event: XP/hour and gold/hour
# before/during/after; player count online vs time; which events actually move
# the needle on 'empty world'". GET /api/world/events/report (the API's
# events/ package) answers it; this window shows it:
#
#   - a chart of who was online this week, the events on it as bands
#     (onlinechart.gd), with a hover that says the time, the counts and the
#     events on then
#   - WHAT MOVES THE NEEDLE: for each kind - more XP, more loot, a land stirs -
#     how many more players were online during its finished events than
#     before them, on average
#   - EACH EVENT of the last 30 days: did it bring players, and in the window
#     before it, its own and the one after (each as long as it ran) - who was
#     online, XP and gold an hour, who played, who signed up
#
# Opened from the GM panel's Events tab ("Report"), read on opening and by
# Refresh. OWNER ONLY three times over, like the Player stats: the HUD builds
# it only for the owner, refresh() asks Api.is_owner first, and the server is
# the gate - require_owner, a bare 404 to anybody else. Players are counted,
# never named.
class_name EventReportWindow
extends Control


const PATH := "/api/world/events/report"
const HEAD := Color(0.93, 0.73, 0.3)
const PLAIN := Color(0.84, 0.88, 0.93)
const DIM := Color(0.55, 0.6, 0.67)
const GOOD := Color(0.55, 0.86, 0.6)
const BAD := Color(0.95, 0.55, 0.5)
const KIND_WORDS := {"xp": "More XP", "loot": "More loot", "stir": "A land stirs"}

var _window: PanelWindow = null
var _busy: bool = false
# The last report read, as the server sent it.
var report: Dictionary = {}

# WHERE A REQUEST GOES, a Callable so the suite can answer without a server.
var get_request: Callable

@onready var report_box: RichTextLabel = %eventreportbox
@onready var chart: OnlineChart = %eventchart
@onready var refresh_button: Button = %eventreportrefresh
@onready var status: Label = %eventreportstatus
@onready var close_button: Button = %eventreportclose


func _init() -> void:
	get_request = Callable(Api, "get_json")


func _ready() -> void:
	_window = PanelWindow.attach(self, "eventreport")
	close_button.pressed.connect(close)
	refresh_button.pressed.connect(refresh)


func open() -> void:
	"""Show the window, and read the report."""
	visible = true
	await refresh()


func close() -> void:
	visible = false


func refresh() -> void:
	if not Api.is_owner:
		_say("The event report is the owner's.", true)
		return
	if _busy:
		return
	_busy = true
	_say("Reading the report...")
	var res: Dictionary = await get_request.call(PATH)
	_busy = false
	if not is_instance_valid(self) or not is_inside_tree():
		return
	if not res.get("ok", false) or not (res.get("data") is Dictionary):
		_say(refusal(res), true)
		return
	report = res.get("data")
	show_report(report)
	_say("Read at %s." % LocalTime.clock(int(report.get("now", Time.get_unix_time_from_system()))))


func show_report(data: Dictionary) -> void:
	"""The chart, and the report into the box - add_text, never BBCode: an
	event's name is words the owner typed."""
	chart.show_online(data)
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
		return "This server has no event report yet (404). Update the server, then Refresh."
	return "The server refused (%d): %s" % [code, str(res.get("error", ""))]


# =============================================================================
# THE REPORT IN WORDS - static, what the suite reads
# =============================================================================

static func number(value: Variant) -> String:
	"""A count or a rate: '-' for not known, else short ('12K')."""
	if value == null:
		return "-"
	return GameConstants.short_number(int(value))


static func average(value: Variant) -> String:
	"""Players online on average: '0', '1.5', '2.25' - '-' for not counted."""
	if value == null:
		return "-"
	var text: String = "%.2f" % float(value)
	while text.ends_with("0"):
		text = text.substr(0, text.length() - 1)
	return text.trim_suffix(".")


static func three(windows: Dictionary, read: Callable) -> String:
	"""'0 before, 2 during, 1 after' - 'not yet' for an after still to come."""
	var parts: Array[String] = []
	for which in ["before", "during", "after"]:
		var span: Variant = windows.get(which)
		parts.append(("%s %s" % [read.call(span), which]) if span is Dictionary else "not yet %s" % which)
	return ", ".join(parts)


static func lift_words(lift: Variant) -> String:
	if lift == null:
		return "not counted yet"
	var change: float = float(lift)
	var who: String = "player" if is_equal_approx(absf(change), 1.0) else "players"
	if change > 0.05:
		return "+%s %s online on average" % [average(change), who]
	if change < -0.05:
		return "%s %s online on average" % [average(change), who]
	return "no change in who was online"


static func report_lines(data: Dictionary) -> Array:
	"""[[text, colour, heading]] - the whole report, top to bottom."""
	var out: Array = []
	var now: int = int(data.get("now", 0))
	out.append(["WHAT MOVES THE NEEDLE", HEAD, true])
	out.append(["Players online during an event, less the same time before it - finished events only.", DIM])
	var kinds: Variant = data.get("kinds", [])
	if kinds is Array:
		for row in kinds:
			if not (row is Dictionary):
				continue
			var held: int = int(row.get("events", 0))
			var counted: int = int(row.get("counted", 0))
			var words: String = str(KIND_WORDS.get(str(row.get("kind", "")), str(row.get("kind", ""))))
			if held == 0:
				out.append(["%s: no events yet." % words, DIM])
			elif counted == 0:
				out.append(["%s: not counted yet (%d event%s)." % [words, held, "" if held == 1 else "s"], DIM])
			else:
				var change: float = float(row.get("lift", 0.0))
				out.append(["%s: %s, across %d event%s counted." % [words, lift_words(change), counted,
					"" if counted == 1 else "s"], GOOD if change > 0.05 else PLAIN])
	out.append(["", PLAIN])
	out.append(["EACH EVENT", HEAD, true])
	var events: Variant = data.get("events", [])
	if not (events is Array) or (events as Array).is_empty():
		out.append(["No events in the last 30 days. Set one on the Events tab.", DIM])
	else:
		for event in events:
			if event is Dictionary:
				out.append_array(event_lines(event, now))
	out.append(["", PLAIN])
	var since: int = int(data.get("sampling_since", 0))
	out.append([("Who is online has been counted since %s." % LocalTime.stamp(since, now)) if since > 0
		else "Who is online has not been counted yet - it is counted while anybody plays.", DIM])
	out.append(["XP is known for %d days (the kill log), gold for good. Players are the player rank: the owner, co-owners and staff are left out." % int(data.get("kills_kept_days", 14)), DIM])
	return out


static func event_lines(event: Dictionary, now: int) -> Array:
	var out: Array = []
	var starts: int = int(event.get("starts_at", 0))
	var ran: int = maxi(0, int(event.get("ended_at", event.get("ends_at", starts))) - starts)
	var state: String = str(event.get("state", ""))
	var said: String = {"on": "on now", "cancelled": "called off", "over": "over"}.get(state, state)
	out.append(["%s - %s, %s (%s)" % [str(event.get("name", "?")), LocalTime.stamp(starts, now),
		WorldEvents.span_text(ran), said], PLAIN, false])
	var lift: Variant = event.get("lift")
	out.append(["  " + str(event.get("verdict", "")), GOOD if lift != null and float(lift) > 0.05 else DIM])
	var windows: Dictionary = event.get("windows", {}) if event.get("windows") is Dictionary else {}
	out.append(["  Online: " + three(windows, func(span: Dictionary) -> String:
		var online: Variant = span.get("online")
		return average(online.get("players")) if online is Dictionary else "-"), PLAIN])
	out.append(["  XP an hour: " + three(windows, func(span: Dictionary) -> String: return number(span.get("xp_per_hour"))), PLAIN])
	out.append(["  Gold an hour: " + three(windows, func(span: Dictionary) -> String: return number(span.get("gold_per_hour"))), PLAIN])
	out.append(["  Played: " + three(windows, func(span: Dictionary) -> String: return number(span.get("played")))
		+ "; new players: " + three(windows, func(span: Dictionary) -> String: return number(span.get("new_players"))), DIM])
	return out
