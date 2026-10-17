# eventcalendar.gd - the Events tab's calendar: a real one, any month of any
# year, to pick an event's day from, with the days that have events marked
# (0.51.0; the whole calendar, 0.52.0).
#
# The owner: "i want to set a calendar in schedule that i can use to set
# events for specific days", and then, of the first one, which went from
# this month to the one holding the sixtieth day: "can we make it a real
# calendar that updates with the years etc?". So:
#
#   - one month at a time, Sunday first; < and > a month, << and >> a year,
#     any month from 1970 to 2199, and Today back to this one. The month
#     and year are worked out from the date, so a year turns over like any
#     calendar's - December 2026, then January 2027
#   - a day from today to the furthest the server takes an event
#     (limits.days_ahead: a year, since 0.52.0) can be pressed: it is picked
#     in the day picker, and the hour and minute stay the owner's. Days
#     before today, or past the furthest, are there to read but not to press
#   - a day an event is on, is coming, or ran in the last 30 days (what the
#     schedule answer holds) is drawn in a HOTBAR BOX - the hotbar's own
#     socket, art/images/hotbarslot.png, as the theme's ButtonSocket has it:
#     the owner's "use hotbar boxs for the outline on those days" - with
#     green letters, dimmed once it is past, and its tooltip says each one
#     with its hours that day: "Double XP 14:00-17:00", "(over)" after one
#     that ran. One called off is not marked
#   - today's number in gold, on a warm fill when nothing is on; the picked
#     day pressed in
#
# Opened from the calendar button beside the hour and minute, as a
# PopupPanel under it, so the GM panel keeps its size.
#
# ON THIS COMPUTER'S CALENDAR (LocalTime), like the day picker: a day is
# counted from today's DATE, never in 86400s from now, so a clock change in
# between moves no day.
class_name EventCalendar
extends VBoxContainer


signal picked(days_on: int)

const TITLE := Color(0.56, 0.93, 0.62)
const PLAIN := Color(0.84, 0.88, 0.93)
const DIM := Color(0.55, 0.6, 0.67)
const TODAY := Color(0.93, 0.78, 0.4)
const TODAY_FILL := Color(0.3, 0.24, 0.12)
# The HUD's events green (characterhud.gd, EVENT_COLOUR); a past one dimmer.
const EVENT := Color(0.56, 0.93, 0.62)
const EVENT_PAST := Color(0.36, 0.6, 0.4)
const MONTH_NAMES := ["", "January", "February", "March", "April", "May", "June", "July",
	"August", "September", "October", "November", "December"]
const WEEKDAY_LETTERS := ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
const CELL := Vector2(32, 30)
# The hotbar box an event's day is drawn in: the UI theme's ButtonSocket - the
# hotbar's socket art, nine-sliced at 7 px, lit on hover and darkened when
# pressed - with room inside it for a day's number.
const SOCKET_THEME := preload("res://assets/themes/rpg_ui_theme.tres")
const SOCKET_STATES := ["normal", "hover", "pressed", "hover_pressed", "disabled"]
const DAY := 86400
# How far it can be paged, either way: far past anything the game will need,
# and inside what Godot's Time turns into dates.
const FIRST_YEAR := 1970
const LAST_YEAR := 2199

# THE CALENDAR BUTTON'S PICTURE (0.54.2). It was a calendar drawn in code;
# the owner: "we need to use my art only", and of the pack's pictures, the book
# with the red bookmark (the Magic stat icon) - nothing in his art or the pack
# is a calendar, and the book reads as a planner. Loaded, never preloaded: a
# clone has no pack, and a preload of a missing file stops the script compiling.
const ICON_PATH := "res://art/pack/icons/magiciconcharacterstats.png"
const ICON_WORD := "Cal"
static var _icon: Texture2D = null
static var _sockets: Dictionary = {}

# What it was last shown: the time it was opened, how many days may be picked
# (0 is today), the day picked (-1 for Now) and the marked days.
var _now_unix: int = 0
var _days: int = 366
var _picked: int = -1
var marked: Dictionary = {}
# The month on the screen.
var shown_year: int = 1970
var shown_month: int = 1

var month_label: Label
var year_back_button: Button
var earlier_button: Button
var later_button: Button
var year_on_button: Button
var grid: GridContainer
var key_label: Label
var today_button: Button


func _init() -> void:
	name = "calendar"
	add_theme_constant_override("separation", 6)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 4)
	add_child(top)
	year_back_button = _arrow("<<", "The year before.")
	year_back_button.name = "yearback"
	year_back_button.pressed.connect(turn.bind(-12))
	top.add_child(year_back_button)
	earlier_button = _arrow("<", "The month before.")
	earlier_button.name = "earlier"
	earlier_button.pressed.connect(turn.bind(-1))
	top.add_child(earlier_button)
	month_label = Label.new()
	month_label.name = "month"
	month_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	month_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	month_label.custom_minimum_size = Vector2(118, 0)
	month_label.add_theme_color_override("font_color", TITLE)
	month_label.add_theme_font_size_override("font_size", 14)
	top.add_child(month_label)
	later_button = _arrow(">", "The month after.")
	later_button.name = "later"
	later_button.pressed.connect(turn.bind(1))
	top.add_child(later_button)
	year_on_button = _arrow(">>", "The year after.")
	year_on_button.name = "yearon"
	year_on_button.pressed.connect(turn.bind(12))
	top.add_child(year_on_button)
	grid = GridContainer.new()
	grid.name = "days"
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	add_child(grid)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 6)
	add_child(foot)
	key_label = Label.new()
	key_label.name = "key"
	key_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key_label.add_theme_color_override("font_color", DIM)
	key_label.add_theme_font_size_override("font_size", 12)
	foot.add_child(key_label)
	today_button = _arrow("Today", "Back to this month.")
	today_button.name = "todaybutton"
	today_button.pressed.connect(show_today)
	foot.add_child(today_button)


func _arrow(text: String, hint: String) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = hint
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(28, 0)
	return button


# =============================================================================
# THE CALENDAR - static, what the suite reads
# =============================================================================

static func days_in_month(year: int, month: int) -> int:
	if month == 2:
		return 29 if (year % 4 == 0 and year % 100 != 0) or year % 400 == 0 else 28
	return 30 if month in [4, 6, 9, 11] else 31


static func _wall(year: int, month: int, day_of_month: int) -> int:
	"""A date's midnight counted as if it were UTC: whole days apart, always."""
	return int(Time.get_unix_time_from_datetime_dict({"year": year, "month": month, "day": day_of_month,
		"hour": 0, "minute": 0, "second": 0}))


static func first_weekday(year: int, month: int) -> int:
	"""The weekday of the month's first day: 0 Sunday to 6 Saturday."""
	return int(Time.get_datetime_dict_from_unix_time(_wall(year, month, 1)).get("weekday", 0))


static func month_cells(year: int, month: int) -> Array[int]:
	"""The month as the grid lays it out, Sunday first: a 0 for each blank
	before the 1st, then 1 to the last day."""
	var out: Array[int] = []
	for _blank in first_weekday(year, month):
		out.append(0)
	for number in days_in_month(year, month):
		out.append(number + 1)
	return out


static func month_after(year: int, month: int, months: int) -> Array[int]:
	"""[year, month], `months` on from the given one (back, if negative) -
	the year turning over at December and January - held to FIRST_YEAR's
	January and LAST_YEAR's December."""
	var number: int = clampi(year * 12 + month - 1 + months, FIRST_YEAR * 12, LAST_YEAR * 12 + 11)
	@warning_ignore("integer_division")
	return [number / 12, number % 12 + 1]


static func date_of(days_on: int, now_unix: int) -> Dictionary:
	"""Today on this computer's calendar, plus `days_on` days: year, month,
	day and weekday."""
	var today: Dictionary = LocalTime.parts(now_unix)
	return Time.get_datetime_dict_from_unix_time(_wall(int(today.get("year", 1970)), int(today.get("month", 1)),
		int(today.get("day", 1))) + days_on * DAY)


static func days_from_today(year: int, month: int, day_of_month: int, now_unix: int) -> int:
	var today: Dictionary = LocalTime.parts(now_unix)
	@warning_ignore("integer_division")
	return (_wall(year, month, day_of_month) - _wall(int(today.get("year", 1970)), int(today.get("month", 1)),
		int(today.get("day", 1)))) / DAY


static func days_on_of(unix_time: int, now_unix: int) -> int:
	"""How many days after today, on this computer's calendar, `unix_time` is."""
	var at: Dictionary = LocalTime.parts(unix_time)
	return days_from_today(int(at.get("year", 1970)), int(at.get("month", 1)), int(at.get("day", 1)), now_unix)


static func marks(events: Array, now_unix: int) -> Dictionary:
	"""{days_on: ["Double XP 14:00-17:00", ...]} - each day an event touches,
	before today too, with its hours that day (00:00 when it began the day
	before, 24:00 when it runs past midnight, "all day"), and "(over)" after
	one that has run. One called off is left out."""
	var out: Dictionary = {}
	for event in events:
		if not (event is Dictionary):
			continue
		var state: String = str(event.get("state", ""))
		if state == "cancelled" or bool(event.get("cancelled", false)):
			continue
		var starts: int = int(event.get("starts_at", 0))
		var ends: int = int(event.get("ends_at", 0))
		if ends <= starts:
			continue
		var first: int = days_on_of(starts, now_unix)
		var last: int = days_on_of(ends - 1, now_unix)
		for days_on in range(first, last + 1):
			var from_text: String = LocalTime.clock(starts) if days_on == first else "00:00"
			var to_text: String = LocalTime.clock(ends) if days_on == last else "24:00"
			if to_text == "00:00":
				to_text = "24:00"
			var line: String = str(event.get("name", "?"))
			line += " all day" if from_text == "00:00" and to_text == "24:00" else " %s-%s" % [from_text, to_text]
			if state == "over":
				line += " (over)"
			if not out.has(days_on):
				out[days_on] = []
			(out[days_on] as Array).append(line)
	return out


static func socket_style(state: String) -> StyleBox:
	"""The hotbar box for a day, in one of a button's states: the theme's
	ButtonSocket, its content margins brought in to fit a number in a cell."""
	if not _sockets.has(state):
		var from_theme: StyleBox = SOCKET_THEME.get_stylebox(state, &"ButtonSocket")
		var box: StyleBox = from_theme.duplicate() as StyleBox if from_theme != null else null
		if box != null:
			for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
				box.set_content_margin(side, 2.0)
			# THE ART HAS A CLEAR RIM - 4 px at the sides, 2 at the top and
			# bottom - which the hotbar hides by overlapping its slots
			# (separation -4). Drawn that much past the cell instead, the
			# box is the cell's size, like the days beside it.
			if box is StyleBoxTexture:
				(box as StyleBoxTexture).set_expand_margin(SIDE_LEFT, 4.0)
				(box as StyleBoxTexture).set_expand_margin(SIDE_RIGHT, 4.0)
				(box as StyleBoxTexture).set_expand_margin(SIDE_TOP, 2.0)
				(box as StyleBoxTexture).set_expand_margin(SIDE_BOTTOM, 2.0)
		_sockets[state] = box
	return _sockets[state]


static func reach_words(days: int) -> String:
	"""How far ahead an event may be set, in words: 'a year', '60 days'."""
	return "a year" if days >= 365 and days <= 366 else "%d days" % days


static func icon() -> Texture2D:
	"""The calendar button's picture: the Clockwork pack's book with the red
	bookmark (ICON_PATH) - or null where a clone has no pack, and the button
	says ICON_WORD instead."""
	if _icon == null and ResourceLoader.exists(ICON_PATH):
		_icon = load(ICON_PATH) as Texture2D
	return _icon


# =============================================================================
# ON THE SCREEN
# =============================================================================

func show_days(now_unix: int, days: int, picked_day: int, events: Array) -> void:
	"""Fill it: from `now_unix`, `days` days may be picked, `picked_day` is
	the day picker's (-1 for Now), `events` are the schedule's - on, coming
	and lately over. It opens on the picked day's month - this month for
	Now."""
	_now_unix = now_unix
	_days = maxi(1, days)
	_picked = picked_day
	marked = marks(events, now_unix)
	key_label.text = "Boxed: events. Up to %s ahead." % reach_words(_days)
	var at: Dictionary = date_of(maxi(picked_day, 0), now_unix)
	show_month(int(at.get("year", 1970)), int(at.get("month", 1)))


func show_today() -> void:
	var at: Dictionary = date_of(0, _now_unix)
	show_month(int(at.get("year", 1970)), int(at.get("month", 1)))


func turn(months: int) -> void:
	"""The month `months` on, or back - 12 is a year."""
	var to: Array[int] = month_after(shown_year, shown_month, months)
	show_month(to[0], to[1])


func show_month(year: int, month: int) -> void:
	var held: Array[int] = month_after(year, month, 0)
	shown_year = held[0]
	shown_month = held[1]
	month_label.text = "%s %d" % [MONTH_NAMES[shown_month], shown_year]
	var number: int = shown_year * 12 + shown_month - 1
	earlier_button.disabled = number <= FIRST_YEAR * 12
	year_back_button.disabled = earlier_button.disabled
	later_button.disabled = number >= LAST_YEAR * 12 + 11
	year_on_button.disabled = later_button.disabled
	var today: Dictionary = date_of(0, _now_unix)
	today_button.disabled = shown_year == int(today.get("year", 0)) and shown_month == int(today.get("month", 0))
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	for letters in WEEKDAY_LETTERS:
		var heading := Label.new()
		heading.text = letters
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		heading.custom_minimum_size = Vector2(CELL.x, 0)
		heading.add_theme_color_override("font_color", DIM)
		heading.add_theme_font_size_override("font_size", 12)
		grid.add_child(heading)
	for number_of_day in month_cells(shown_year, shown_month):
		if number_of_day == 0:
			var blank := Control.new()
			blank.custom_minimum_size = CELL
			blank.mouse_filter = Control.MOUSE_FILTER_IGNORE
			grid.add_child(blank)
			continue
		var cell: Button = _cell(number_of_day)
		grid.add_child(cell)
		_edge(cell)


func _cell(number_of_day: int) -> Button:
	var days_on: int = days_from_today(shown_year, shown_month, number_of_day, _now_unix)
	var cell := Button.new()
	cell.name = "day%d" % number_of_day
	cell.text = str(number_of_day)
	cell.custom_minimum_size = CELL
	cell.focus_mode = Control.FOCUS_NONE
	cell.toggle_mode = true
	cell.add_theme_font_size_override("font_size", 13)
	cell.set_meta("days_on", days_on)
	cell.disabled = days_on < 0 or days_on >= _days
	cell.button_pressed = days_on == _picked
	var lines: Array = marked.get(days_on, [])
	var colour: Color = PLAIN
	var hint: Array[String] = []
	if days_on == 0:
		hint.append("Today")
	if not lines.is_empty():
		colour = EVENT
		for line in lines:
			hint.append(str(line))
	if days_on == 0:
		colour = TODAY
	if days_on >= _days:
		hint.append("Further ahead than an event can be set (%s)." % reach_words(_days))
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		cell.add_theme_color_override(key, colour)
	if not lines.is_empty():
		cell.add_theme_color_override("font_disabled_color", EVENT_PAST)
	cell.tooltip_text = "\n".join(hint)
	cell.pressed.connect(_on_cell_pressed.bind(days_on))
	return cell


func _edge(cell: Button) -> void:
	"""A DAY WITH AN EVENT in a hotbar box (socket_style()), in every state -
	the box's disabled look on one gone by. TODAY with nothing on, a warm
	fill and a gold edge on the GM panel's own button. Called once the cell
	is in the grid: only then is the GM panel's button style the one it
	would draw with - before, get_theme_stylebox() answers with the engine's
	default, which has no edge."""
	var days_on: int = int(cell.get_meta("days_on", -1))
	if marked.has(days_on):
		for state in SOCKET_STATES:
			var box: StyleBox = socket_style(state)
			if box != null:
				cell.add_theme_stylebox_override(state, box)
		return
	if days_on != 0:
		return
	for state in ["normal", "hover"]:
		var plain_box: StyleBox = cell.get_theme_stylebox(state)
		if not (plain_box is StyleBoxFlat):
			continue
		var warm := (plain_box as StyleBoxFlat).duplicate() as StyleBoxFlat
		if warm.border_width_left == 0:
			warm.set_border_width_all(2)
		warm.bg_color = TODAY_FILL
		warm.border_color = TODAY
		cell.add_theme_stylebox_override(state, warm)


func _on_cell_pressed(days_on: int) -> void:
	if days_on < 0 or days_on >= _days:
		return
	_picked = days_on
	picked.emit(days_on)


func cell_for(number_of_day: int) -> Button:
	"""The shown month's button for a day of it - for the suite."""
	return grid.get_node_or_null("day%d" % number_of_day) as Button
