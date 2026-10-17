# landreport.gd - the owner's Lands window: what the data says about each
# land (0.50.0).
#
# The owner, from a "Behavior Insights" idea: for each land, recent players
# and kills, time since its last event, and whether it is overfarmed, ignored
# or healthy; the next stir with a reason; when players are on. GET
# /api/server/insights (the API's insights/ package) answers it; this window
# shows it:
#
#   - NEXT TO STIR: the land the world would pick when the stir on now ends,
#     and why - it passes over a land where a new player is learning. To take
#     it now, or pick another, use "Stir it now" on the World tab.
#   - EVERY LAND: kills today and this week, players this week, new players
#     there now, when it last stirred and had an event, its busiest hour (this
#     computer's), and its status - busy (overfarmed), healthy, quiet, ignored
#   - WHEN PLAYERS ARE ON: players online by hour of the day, this computer's
#     hours, as bars (hourschart.gd), and the busiest three
#
# Opened from the World tab ("Lands"), read on opening and by Refresh. OWNER
# ONLY three times over, like the Player stats: the HUD builds it only for the
# owner, refresh() asks Api.is_owner first, and the server is the gate.
class_name LandReportWindow
extends Control


const PATH := "/api/server/insights"
const HEAD := Color(0.93, 0.73, 0.3)
const PLAIN := Color(0.84, 0.88, 0.93)
const DIM := Color(0.55, 0.6, 0.67)
const GOOD := Color(0.55, 0.86, 0.6)
const BAD := Color(0.95, 0.55, 0.5)
const STATUS_COLOURS := {"busy": Color(0.96, 0.62, 0.42), "healthy": Color(0.55, 0.86, 0.6),
	"quiet": Color(0.73, 0.78, 0.84), "ignored": Color(0.55, 0.6, 0.67)}
const STATUS_WORDS := {"busy": "busy", "healthy": "healthy", "quiet": "quiet", "ignored": "ignored"}
const COLUMNS := ["Land", "Today", "Week", "Players", "New now", "Stirred", "Event", "Busiest", "Status"]

var _window: PanelWindow = null
var _busy: bool = false
# The last answer read, as the server sent it.
var report: Dictionary = {}

# WHERE A REQUEST GOES, a Callable so the suite can answer without a server.
var get_request: Callable

@onready var report_box: RichTextLabel = %landreportbox
@onready var hours_chart: HoursChart = %landhours
@onready var hours_label: Label = %landhourslabel
@onready var refresh_button: Button = %landreportrefresh
@onready var status: Label = %landreportstatus
@onready var close_button: Button = %landreportclose


func _init() -> void:
	get_request = Callable(Api, "get_json")


func _ready() -> void:
	_window = PanelWindow.attach(self, "landreport")
	close_button.pressed.connect(close)
	refresh_button.pressed.connect(refresh)


func open() -> void:
	visible = true
	await refresh()


func close() -> void:
	visible = false


func refresh() -> void:
	if not Api.is_owner:
		_say("The land report is the owner's.", true)
		return
	if _busy:
		return
	_busy = true
	_say("Reading the lands...")
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
	"""The words and the table into the box - add_text only - and the hours
	into the chart."""
	var now: int = int(data.get("now", Time.get_unix_time_from_system()))
	var bias: int = LocalTime.bias_minutes_at(now)
	report_box.clear()
	for line in next_lines(data, now):
		_line(line[0], line[1], line.size() > 2 and bool(line[2]))
	report_box.newline()
	_line("EVERY LAND, THIS WEEK", HEAD, true)
	report_box.push_table(COLUMNS.size())
	for title in COLUMNS:
		report_box.push_cell()
		report_box.push_color(DIM)
		report_box.add_text(str(title) + "  ")
		report_box.pop()
		report_box.pop()
	var lands: Variant = data.get("lands", [])
	if lands is Array:
		for row in lands:
			if not (row is Dictionary):
				continue
			var cells: Array[String] = row_cells(row, now, bias)
			for i in cells.size():
				report_box.push_cell()
				var colour: Color = PLAIN
				if i == 0:
					colour = Element.colour_for(int(row.get("element", 0))).lightened(0.35)
				elif i == cells.size() - 1:
					colour = STATUS_COLOURS.get(str(row.get("status", "")), PLAIN)
				report_box.push_color(colour)
				report_box.add_text(cells[i] + "  ")
				report_box.pop()
				report_box.pop()
	report_box.pop()
	report_box.newline()
	for line in note_lines(data):
		_line(line[0], line[1])
	var hours: Dictionary = data.get("hours", {}) if data.get("hours") is Dictionary else {}
	hours_chart.show_hours(hours.get("players", []), bias)
	hours_label.text = hours_text(hours_chart.busiest(), hours_chart.players, float(hours.get("days", 0.0)))


func _line(text: String, colour: Color, heading: bool = false) -> void:
	if heading:
		report_box.push_font_size(14)
	report_box.push_color(colour)
	report_box.add_text(text)
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
		return "This server has no land report yet (404). Update the server, then Refresh."
	return "The server refused (%d): %s" % [code, str(res.get("error", ""))]


# =============================================================================
# IN WORDS - static, what the suite reads
# =============================================================================

static func ago(at: Variant, now: int) -> String:
	"""'never', 'now', '45m ago', '3h ago', '2d ago'."""
	if at == null or int(at) <= 0:
		return "never"
	var seconds: int = now - int(at)
	if seconds < 60:
		return "now"
	@warning_ignore("integer_division")
	var minutes: int = seconds / 60
	if minutes < 60:
		return "%dm ago" % minutes
	@warning_ignore("integer_division")
	var hours: int = minutes / 60
	if hours < 48:
		return "%dh ago" % hours
	@warning_ignore("integer_division")
	return "%dd ago" % (hours / 24)


static func row_cells(row: Dictionary, now: int, bias: int) -> Array[String]:
	"""One land's row of the table, as words."""
	var busiest: Variant = row.get("busiest_hour")
	var newcomers: int = int(row.get("newcomers_now", 0))
	return [str(row.get("name", "?")).capitalize(), str(int(row.get("kills_day", 0))), str(int(row.get("kills_week", 0))),
		str(int(row.get("players_week", 0))), str(newcomers) if newcomers > 0 else "-",
		ago(row.get("last_stirred_at"), now), ago(row.get("last_event_at"), now),
		HoursChart.local_hour(int(busiest), bias) if busiest != null else "-",
		str(STATUS_WORDS.get(str(row.get("status", "")), str(row.get("status", ""))))]


static func next_lines(data: Dictionary, now: int) -> Array:
	"""[[text, colour, heading]]: the next stir and why."""
	var out: Array = [["NEXT TO STIR", HEAD, true]]
	var upcoming: Variant = data.get("next")
	if not (upcoming is Dictionary):
		out.append(["Nothing - the stirring lands are switched off (World tab).", DIM])
		return out
	out.append(["At %s: %s" % [LocalTime.stamp(int(upcoming.get("at", now)), now), str(upcoming.get("reason", ""))], PLAIN])
	out.append(["To take it now or pick another, use Stir it now on the World tab.", DIM])
	return out


static func note_lines(data: Dictionary) -> Array:
	var out: Array = []
	if bool(data.get("few", false)):
		out.append(["Only %d kills this week - a rough read." % int(data.get("total_week", 0)), BAD])
	out.append(["Status from each land's share of the week's kills: busy is twice an even share or more, quiet under half, ignored none. New now: players under level %d with a kill there in the last 2 hours - the world will not stir a land they are learning in while another will do." % int(data.get("new_player_level", 10)), DIM])
	return out


static func hours_text(top: Array[int], players: Array[float], days: float) -> String:
	"""'Busiest (your time): 20:00 (1.4 on average), 21:00 (1.2), 19:00 (0.8) - over 14 days.'"""
	if days < 3.0:
		return "Players online by hour, your time - counting began %s days ago; a few more days and this will say when players are on." % HoursChart._short(days)
	if top.is_empty():
		return "Nobody was online in the last %s days." % HoursChart._short(days)
	var parts: Array[String] = []
	for i in top.size():
		parts.append("%02d:00 (%s%s)" % [top[i], HoursChart._short(players[top[i]]), " on average" if i == 0 else ""])
	return "Busiest hours, your time: %s - over %s days." % [", ".join(parts), HoursChart._short(days)]
