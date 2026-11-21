# healthtab.gd - the GM panel's Health tab (0.78.0).
#
# The owner, of four next steps after the 128-player swarm (send each game
# only the players near it, watch the live server, test on the real machine,
# let the server referee every kill): "work on this or if you have a even
# better idea lets hear it". Two of those were numbers only SSH could read,
# and the first needed one nobody had - what the server really sends, against
# the 1,000 GiB a month the droplet comes with. GET /api/server/health has
# them all (the API's serverhealth/), on four pages:
#
#   PLAYERS   players and the biggest crowd, the most today and this week;
#             the tick
#   DATA      data going out, and the month it adds up to at this week's
#             rate; THE DATA GUARD (0.79.0) - the server holding the month
#             under the plan itself, and how hard it is holding; whether one
#             area needs sending only what is near yet - "on" since 0.89.0
#   MACHINE   the machine's load, memory and disk; the slowest routes
#   RECEIPTS  "Kills need the server's count": the week's kills put to the
#             server's own count (killwatch.py's), a verdict - ready or what
#             it is waiting for - and the switch itself, beside it
#   ERRORS    (0.88.0) what broke in players' games in the last day: every
#             SCRIPT ERROR the games reported (errorreporter.gd, the API's
#             clienterrors/), worst first - how many players, how many times,
#             the script and line, the versions. Never who.
#
# Built like the Economy tab (economytab.gd): made in code, read when the
# panel opens, on Refresh and every REFRESH_SECONDS while it is on screen;
# (0.168.13, the owner: "need to fix this screen") each page reads as rows,
# a name and its number, coloured only where it matters, with the month's
# data as a bar - the sentences they replaced are each grid's tooltip and
# what Results is told;
# what Refresh read and what the switch did go in the panel's Results box
# too (`report`). NARROW AND SHORT: four pages that take turns, nothing
# scrolls. The switch is here alone since 0.112.1 (it was the Testing tab's
# too); the GM panel throws it through its own handler, password asked again
# (OwnerPanel._on_receipts_toggled(), _refresh_receipts()).
extends VBoxContainer
class_name HealthTab


const PATH := "/api/server/health"
const SAY_GOOD := Color(0.55, 0.86, 0.6)
const SAY_BAD := Color(0.95, 0.55, 0.5)
const SAY_WARN := Color(0.95, 0.82, 0.5)
const SAY_NOTE := Color(0.84, 0.8, 0.72)
const HEAD := Color(0.93, 0.73, 0.3)
# A row's name, and a value that says nothing is wrong or right (0.168.13).
const ROW_NAME := Color(0.7, 0.66, 0.6)
const ROW_VALUE := Color(0.93, 0.9, 0.82)
# The GM panel's inside width, near enough (the World tab's).
const WIDTH := 250.0
const PAGES := [["players", "Players"], ["data", "Data"], ["machine", "Machine"], ["receipts", "Receipts"],
	["errors", "Errors"]]
## What broke in players' games (0.88.0): the API's clienterrors/.
const ERRORS_PATH := "/api/server/client-errors"
## How many errors the page lists; the rest are counted.
const ERRORS_SHOWN := 5
# How often it reads again while it is on screen. The server's minutes are a
# minute long; half that means a new one shows within half a minute of it.
const REFRESH_SECONDS := 30.0
# How many of the slowest routes a line names.
const ROUTES_NAMED := 3

# Where requests go; seams for the suite.
var fetch: Callable = Callable(Api, "get_json")
# Where results also go: the panel's Results box (OwnerPanel._say).
var report: Callable = Callable()
# The switch, thrown: the panel's own handler (OwnerPanel._on_receipts_toggled),
# which asks the password again and says what it did. Unset, the switch does
# nothing.
var toggle_receipts: Callable = Callable()

var answer: Dictionary = {}
var page: String = "players"
var page_buttons: Dictionary = {}
var pages: Dictionary = {}
var refresh_button: Button
# Refresh's row; the GM panel adds Player stats to it (0.112.1).
var read_row: HBoxContainer
var as_of_label: Label
# Players.
# THE ROWS (0.168.13): a name and its value, two columns a page part.
var players_note: Label
var players_grid: GridContainer
var tick_grid: GridContainer
var data_grid: GridContainer
var month_bar: Control
var month_fill: ColorRect
var guard_grid: GridContainer
var machine_grid: GridContainer
var routes_grid: GridContainer
var receipt_grid: GridContainer
# Machine.
# Receipts.
var verdict_label: Label
var receipts_switch: CheckButton
var build_label: Label
var say_label: Label
var errors_label: Label
var errors_answer: Dictionary = {}
var timer: Timer
var _busy: bool = false


func _init() -> void:
	name = "health"
	add_theme_constant_override("separation", 6)
	_build()


func _build() -> void:
	var strip := HBoxContainer.new()
	strip.name = "pages"
	strip.add_theme_constant_override("separation", 2)
	add_child(strip)
	var group := ButtonGroup.new()
	for spec in PAGES:
		var button := _button(str(spec[1]), "")
		button.name = str(spec[0])
		button.toggle_mode = true
		button.button_group = group
		# 13, from 14 (0.88.0): five pages' buttons in the panel's 370 where
		# four were.
		button.add_theme_font_size_override("font_size", 13)
		button.pressed.connect(show_page.bind(str(spec[0])))
		strip.add_child(button)
		page_buttons[spec[0]] = button
	# Refresh beside when it was read, under the pages: four page buttons are
	# the strip's width.
	read_row = HBoxContainer.new()
	read_row.name = "read"
	read_row.add_theme_constant_override("separation", 6)
	add_child(read_row)
	refresh_button = _button("Refresh", "Read the server's health again - the kill receipts too, fresh.")
	refresh_button.name = "refresh"
	refresh_button.add_theme_font_size_override("font_size", 13)
	refresh_button.pressed.connect(refresh.bind(true))
	read_row.add_child(refresh_button)
	as_of_label = _label("Not read yet.", SAY_NOTE, false)
	as_of_label.name = "asof"
	as_of_label.add_theme_font_size_override("font_size", 12)
	# Gives way, with "...", now Player stats shares the row (0.112.1).
	as_of_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	as_of_label.clip_text = true
	as_of_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	read_row.add_child(as_of_label)

	# ---- PLAYERS ---------------------------------------------------------------
	var players_page := _page("players")
	players_page.add_child(_head("Players"))
	players_note = _line("playersnote")
	players_note.visible = false
	players_page.add_child(players_note)
	players_grid = _grid(players_page, "players")
	players_page.add_child(_gap())
	players_page.add_child(_head("The tick"))
	tick_grid = _grid(players_page, "tick")

	# ---- DATA ------------------------------------------------------------------
	var data_page := _page("data")
	data_page.add_child(_head("Data going out"))
	data_grid = _grid(data_page, "data")
	month_bar = Control.new()
	month_bar.name = "monthbar"
	month_bar.custom_minimum_size = Vector2(0, 6)
	month_bar.visible = false
	var track := ColorRect.new()
	track.name = "track"
	track.color = Color(1, 1, 1, 0.08)
	track.set_anchors_preset(Control.PRESET_FULL_RECT)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	month_bar.add_child(track)
	month_fill = ColorRect.new()
	month_fill.name = "fill"
	month_fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	month_fill.anchor_right = 0.0
	month_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	month_bar.add_child(month_fill)
	data_page.add_child(month_bar)
	data_page.add_child(_gap())
	data_page.add_child(_head("The data guard"))
	guard_grid = _grid(data_page, "guard")

	# ---- MACHINE ---------------------------------------------------------------
	var machine_page := _page("machine")
	machine_page.add_child(_head("The machine"))
	machine_grid = _grid(machine_page, "machine")
	machine_page.add_child(_gap())
	machine_page.add_child(_head("Slowest routes (p99)"))
	routes_grid = _grid(machine_page, "routes")

	# ---- RECEIPTS --------------------------------------------------------------
	var receipts_page := _page("receipts")
	receipts_page.add_child(_head("The kill receipts, this week"))
	verdict_label = _label("Not read yet.", SAY_NOTE)
	verdict_label.name = "verdict"
	receipts_page.add_child(verdict_label)
	receipt_grid = _grid(receipts_page, "detail")
	receipts_switch = CheckButton.new()
	receipts_switch.name = "receiptsswitch"
	receipts_switch.text = "Kills need the server's count"
	receipts_switch.focus_mode = Control.FOCUS_NONE
	receipts_switch.tooltip_text = "On: a kill is paid only when the server's own count of the fight agrees. Off again is one click, and safe at any time."
	receipts_switch.disabled = true
	receipts_switch.toggled.connect(_on_switch_toggled)
	receipts_page.add_child(receipts_switch)
	build_label = _line("build")
	receipts_page.add_child(build_label)

	# ---- ERRORS (0.88.0) ---------------------------------------------------------
	var errors_page := _page("errors")
	errors_page.add_child(_head("What broke in players' games"))
	errors_label = _line("errors")
	errors_label.text = "Not read yet."
	errors_page.add_child(errors_label)

	say_label = _label("", SAY_NOTE)
	say_label.name = "say"
	say_label.add_theme_font_size_override("font_size", 12)
	add_child(say_label)

	timer = Timer.new()
	timer.name = "timer"
	timer.wait_time = REFRESH_SECONDS
	timer.timeout.connect(_on_timer)
	add_child(timer)
	show_page("players")


func _ready() -> void:
	timer.start()


func _page(page_name: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = page_name
	box.add_theme_constant_override("separation", 2)
	add_child(box)
	pages[page_name] = box
	return box


func _head(text: String) -> Label:
	"""A page's heading, in the GM panel's one heading style (0.112.1)."""
	return EventsTab.heading(text.to_upper())


func _line(line_name: String) -> Label:
	var label := _label("", SAY_NOTE)
	label.name = line_name
	label.add_theme_font_size_override("font_size", 12)
	return label


func _gap() -> Control:
	"""Room above a page's second heading, after rows."""
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return gap


func _grid(page_box: VBoxContainer, grid_name: String) -> GridContainer:
	"""A page part's rows: a name, and its value at the right (0.168.13)."""
	var grid := GridContainer.new()
	grid.name = grid_name
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 3)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_box.add_child(grid)
	return grid


static func fill_rows(grid: GridContainer, rows: Array, sentence: String = "") -> void:
	"""The rows anew: each [name, value, colour]. The sentence they say is the
	grid's tooltip."""
	for old: Node in grid.get_children():
		grid.remove_child(old)
		old.queue_free()
	for row: Variant in rows:
		if not (row is Array) or (row as Array).size() < 2:
			continue
		var key := Label.new()
		key.text = str(row[0])
		key.add_theme_color_override("font_color", ROW_NAME)
		key.add_theme_font_size_override("font_size", 13)
		key.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		grid.add_child(key)
		var value := Label.new()
		value.text = str(row[1])
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		value.custom_minimum_size = Vector2(150, 0)
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value.add_theme_color_override("font_color", row[2] if (row as Array).size() > 2 and row[2] is Color else ROW_VALUE)
		value.add_theme_font_size_override("font_size", 14)
		grid.add_child(value)
	grid.tooltip_text = sentence


static func row_value(grid: GridContainer, row_name: String) -> String:
	"""The value beside `row_name` (the suite reads them)."""
	var cells: Array[Node] = grid.get_children()
	for i in range(0, cells.size() - 1, 2):
		if (cells[i] as Label).text == row_name:
			return (cells[i + 1] as Label).text
	return ""


static func row_colour(grid: GridContainer, row_name: String) -> Color:
	var cells: Array[Node] = grid.get_children()
	for i in range(0, cells.size() - 1, 2):
		if (cells[i] as Label).text == row_name:
			return (cells[i + 1] as Label).get_theme_color("font_color")
	return Color.TRANSPARENT


func _label(text: String, colour: Color, wraps: bool = true) -> Label:
	var label := Label.new()
	label.text = text
	if wraps:
		# Given the tab's width, so it is measured as it will be drawn (the
		# World tab's lesson: a wrapping label with no width is one word a line).
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(WIDTH, 0)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_font_size_override("font_size", 13)
	return label


func _button(text: String, hint: String) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = hint
	button.focus_mode = Control.FOCUS_NONE
	return button


func show_page(which: String) -> void:
	page = which if pages.has(which) else "players"
	for key in pages:
		(pages[key] as Control).visible = key == page
	for key in page_buttons:
		(page_buttons[key] as Button).set_pressed_no_signal(key == page)


func _say(line: String, colour: Color = SAY_NOTE, results: String = "") -> void:
	"""On the tab, and in the Results box: `results` there when given."""
	_say_here(line, colour)
	if report.is_valid():
		report.call("[HEALTH] " + (results if results != "" else line), colour)


func _say_here(line: String, colour: Color = SAY_NOTE) -> void:
	say_label.text = line
	say_label.add_theme_color_override("font_color", colour)


static func refusal(res: Dictionary) -> String:
	var status: int = int(res.get("status", 0))
	if status == 0:
		return "Could not reach the server."
	if status == 404:
		# Only the owner and a co-owner see this tab, so a 404 is a server from
		# before 0.78.0 - its update not pushed, or update_server.sh not run.
		return "This server does not have the Health tab yet (404). Update the server, then Refresh."
	var data: Variant = res.get("data", {})
	var message: String = str((data as Dictionary).get("message", "")) if data is Dictionary else ""
	return "The server refused (%d): %s" % [status, message if message != "" else str(res.get("error", ""))]


# =============================================================================
# THE SERVER
# =============================================================================

func refresh(by_hand: bool = false) -> void:
	"""Read the server's health. By hand (Refresh) the kill receipts are read
	fresh and what was read goes in the Results box; opening the panel and
	the half-minute timer read quietly."""
	if _busy:
		return
	_busy = true
	var res: Dictionary = await fetch.call(PATH + ("?fresh=1" if by_hand else ""))
	_busy = false
	if not is_instance_valid(self):
		return
	if not res.get("ok", false) or not (res.get("data") is Dictionary):
		_say(refusal(res), SAY_BAD)
		return
	show_answer(res.get("data"))
	await read_errors()
	if not is_instance_valid(self):
		return
	if by_hand:
		_say("Read from the server.", SAY_GOOD, "Read from the server. %s %s %s" % [
			players_text(answer), month_text(answer.get("month")), verdict_text(answer.get("receipts", {}))])
	elif say_label.text.begins_with("Could not reach") or say_label.text.begins_with("This server"):
		_say_here("")


func read_errors() -> void:
	"""What broke in players' games - asked with the health, its own route,
	so a server from before 0.88.0 says so on its page and nowhere else."""
	var res: Dictionary = await fetch.call(ERRORS_PATH)
	if not is_instance_valid(self):
		return
	if res.get("ok", false) and res.get("data") is Dictionary:
		show_errors(res.get("data"))
	elif int(res.get("status", 0)) == 404:
		errors_label.text = "This server does not take the games' error reports yet (404). Update the server."
		errors_label.add_theme_color_override("font_color", SAY_WARN)
	else:
		errors_label.text = refusal(res)
		errors_label.add_theme_color_override("font_color", SAY_BAD)


func show_errors(data: Dictionary) -> void:
	errors_answer = data
	errors_label.text = errors_text(data)
	errors_label.add_theme_color_override("font_color",
		SAY_GOOD if (data.get("errors", []) as Array).is_empty() else SAY_WARN)
	# THE BUTTON SAYS THERE ARE SOME, in amber, rather than how many: five
	# pages' buttons fill the panel's width, and a number on one did not fit.
	var button: Button = page_buttons.get("errors")
	if button != null:
		var count: int = (data.get("errors", []) as Array).size() + int(data.get("more", 0))
		button.tooltip_text = "%d errors players hit in the last %d hours" % [count, int(data.get("hours", 24))] \
			if count > 0 else "No player's game reported an error"
		if count > 0:
			button.add_theme_color_override("font_color", SAY_WARN)
		else:
			button.remove_theme_color_override("font_color")


static func errors_text(data: Dictionary) -> String:
	"""'2 players hit 3 errors, 41 times.' then each, worst first:
	'5 players, 30 times - partypanel.gd:312, 0.88.0 / Invalid get index ...'"""
	var errors: Array = data.get("errors", []) if data.get("errors") is Array else []
	if errors.is_empty():
		return "No player's game reported an error in the last %d hours." % int(data.get("hours", 24))
	var total: int = errors.size() + int(data.get("more", 0))
	var lines: PackedStringArray = []
	lines.append("%s hit %s, %s in the last %d hours." % [
		_count(int(data.get("players", 0)), "player"), _count(total, "error"),
		_count(int(data.get("times", 0)), "time"), int(data.get("hours", 24))])
	for i in mini(ERRORS_SHOWN, errors.size()):
		var e: Dictionary = errors[i] if errors[i] is Dictionary else {}
		var versions: Array = e.get("versions", []) if e.get("versions") is Array else []
		lines.append("%s, %s - %s%s" % [_count(int(e.get("players", 0)), "player"),
			_count(int(e.get("times", 0)), "time"), short_where(str(e.get("where", ""))),
			(", " + ", ".join(PackedStringArray(versions.slice(0, 2)))) if not versions.is_empty() else ""])
		lines.append("    " + str(e.get("what", "")).left(140))
	if errors.size() > ERRORS_SHOWN:
		lines.append("and %d more." % (total - ERRORS_SHOWN))
	return "\n".join(lines)


static func short_where(where: String) -> String:
	"""'res://src/ui/party/partypanel.gd:312' as 'party/partypanel.gd:312'."""
	if not where.begins_with("res://"):
		return where
	var parts: PackedStringArray = where.trim_prefix("res://").split("/")
	return "/".join(parts.slice(maxi(0, parts.size() - 2)))


static func _count(n: int, word: String) -> String:
	return "%s %s%s" % [GameConstants.commas(n), word, "" if n == 1 else "s"]


func _on_timer() -> void:
	if is_visible_in_tree() and Api.is_owner:
		await refresh()


func _on_switch_toggled(pressed: bool) -> void:
	if not toggle_receipts.is_valid():
		show_switch(not pressed)
		return
	await toggle_receipts.call(pressed)
	if is_instance_valid(self):
		await refresh()


func show_switch(on: bool) -> void:
	"""What the server holds, without throwing it (the panel calls this too)."""
	receipts_switch.set_pressed_no_signal(on)
	receipts_switch.disabled = not Api.is_owner


# =============================================================================
# WHAT IT SHOWS
# =============================================================================

func show_answer(data: Dictionary) -> void:
	answer = data
	var now: int = int(data.get("now", 0))
	as_of_label.text = "Read %s · every %d s" % [LocalTime.clock(now), int(REFRESH_SECONDS)] if now > 0 else ""
	var presence: Dictionary = _dict(data.get("presence"))
	players_note.text = players_quiet_text(data)
	players_note.visible = players_note.text != ""
	players_note.add_theme_color_override("font_color",
		SAY_NOTE if _dict(presence.get("last")).is_empty() else SAY_BAD)
	fill_rows(players_grid, players_rows(data), players_text(data))
	var tick: Dictionary = _dict(data.get("tick"))
	fill_rows(tick_grid, tick_rows(tick), tick_text(tick))
	var month: Variant = data.get("month")
	fill_rows(data_grid, data_rows(data), data_text(data) + " " + month_text(month))
	month_bar.visible = month is Dictionary
	if month is Dictionary:
		month_fill.anchor_right = clampf(float((month as Dictionary).get("share", 0.0)), 0.0, 1.0)
		month_fill.offset_right = 0.0
		month_fill.color = share_colour(month)
	var budget: Dictionary = _dict(data.get("budget"))
	var crowd: Dictionary = _dict(data.get("crowd"))
	fill_rows(guard_grid, guard_rows(budget, crowd), guard_text(budget) + " " + nearby_text(crowd))
	fill_rows(machine_grid, machine_rows(_dict(data.get("machine"))), machine_text(_dict(data.get("machine"))))
	fill_rows(routes_grid, routes_rows(_dict(data.get("routes"))), routes_text(_dict(data.get("routes"))))
	var receipts: Dictionary = _dict(data.get("receipts"))
	verdict_label.text = verdict_text(receipts)
	verdict_label.add_theme_color_override("font_color", verdict_colour(receipts))
	fill_rows(receipt_grid, receipt_rows(receipts), detail_text(receipts))
	build_label.text = build_text(receipts)
	build_label.add_theme_color_override("font_color", SAY_WARN)
	show_switch(bool(receipts.get("on", false)))


static func _dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


static func rate_text(bytes_per_second: float) -> String:
	"""'0.2 KB/s', '850 KB/s', '13.4 MB/s' - decimal, as the swarm says them."""
	if bytes_per_second >= 1000000.0:
		return "%.1f MB/s" % (bytes_per_second / 1000000.0)
	if bytes_per_second >= 10000.0:
		return "%d KB/s" % roundi(bytes_per_second / 1000.0)
	return "%.1f KB/s" % (bytes_per_second / 1000.0)


static func area_name(area: String) -> String:
	return area.replace("_", " ")


static func players_text(data: Dictionary) -> String:
	"""'12 online, 9 in an area; the biggest crowd: town, 7. Most today: 19
	(field 11). This week: 40 (field 34).' - or why there is nothing."""
	var presence: Dictionary = _dict(data.get("presence"))
	var last: Dictionary = _dict(presence.get("last"))
	if last.is_empty():
		return "presence.py has not written a minute yet. It writes one a minute once it runs this update."
	var text: String = ""
	if not bool(presence.get("reporting", false)):
		text = "presence.py has not written for %s - is it running? Last seen: " % Lands.time_text(
			int(last.get("age_seconds", 0)))
	text += "%d online, %d in an area" % [int(last.get("connections", 0)), int(last.get("players", 0))]
	var crowd: Variant = last.get("crowd", [])
	if crowd is Array and not (crowd as Array).is_empty() and (crowd as Array)[0] is Array:
		text += "; the biggest crowd: %s, %d" % [area_name(str(crowd[0][0])), int(crowd[0][1])]
	text += "."
	var day: Dictionary = _dict(presence.get("day"))
	var week: Dictionary = _dict(presence.get("week"))
	if int(day.get("samples", 0)) > 0:
		text += " Most today: %d%s." % [int(day.get("peak_players", 0)), _peak_area(day)]
	if int(week.get("samples", 0)) > int(day.get("samples", 0)):
		text += " This week: %d%s." % [int(week.get("peak_players", 0)), _peak_area(week)]
	return text


static func _peak_area(window: Dictionary) -> String:
	if int(window.get("peak_area_players", 0)) <= 0:
		return ""
	return " (%s %d)" % [area_name(str(window.get("peak_area", ""))), int(window.get("peak_area_players", 0))]


static func data_text(data: Dictionary) -> String:
	"""'Now 1.2 MB/s from the machine, 0.9 MB/s of it the game's sockets.'"""
	var last: Dictionary = _dict(_dict(data.get("presence")).get("last"))
	if last.is_empty():
		return "Nothing measured yet."
	var sockets: String = rate_text(float(last.get("bytes_per_second", 0.0)))
	if last.get("net_per_second") == null:
		return "Now %s from the game's sockets (the machine's own network cannot be read here)." % sockets
	return "Now %s from the machine, %s of it the game's sockets (before a browser's compression)." % [
		rate_text(float(last.get("net_per_second", 0.0))), sockets]


static func month_text(month: Variant) -> String:
	"""'A month at this week's rate: 520 GiB of the 1,000 included.' - and
	what the rest would cost when it is over."""
	if not (month is Dictionary):
		return "A month's data: not enough measured yet."
	var held: Dictionary = month
	var gib: float = float(held.get("gib", 0.0))
	var allowance: int = int(held.get("allowance_gib", 1000))
	var shown: String = ("%.1f" % gib) if gib < 10.0 else GameConstants.commas(roundi(gib))
	var text: String = "A month at this week's rate: %s GiB of the %s included" % [shown, GameConstants.commas(allowance)]
	if float(held.get("over_cost", 0.0)) > 0.0:
		text += " - about $%s over" % GameConstants.commas(roundi(float(held.get("over_cost", 0.0))))
	if str(held.get("source", "")) == "presence":
		text += " (the sockets alone)"
	return text + "."


static func guard_text(budget: Dictionary) -> String:
	"""THE DATA GUARD (0.79.0) in a line or two: how hard the server is
	holding the month under the plan, and the month counted so far."""
	if budget.is_empty():
		return "Data guard: not on this server yet."
	if not bool(budget.get("on", false)):
		return "Data guard: switched off (ELUSION_TRANSFER_GIB) - nothing holds the month under the plan."
	var text: String
	match str(budget.get("level", "full")):
		"half":
			text = "Data guard: holding - other players' steps at half rate, to stay under the plan."
		"crowd":
			text = "Data guard: holding hard - half rate, and at most %d players see each other in one area." % int(
				budget.get("crowd_cap", 16) if budget.get("crowd_cap") != null else 16)
		"alone":
			text = "Data guard: the month's data is nearly spent - players do not see each other until it allows."
		_:
			text = "Data guard: full speed."
	if budget.get("used_gib") != null and budget.get("since") != null:
		var used: float = float(budget.get("used_gib"))
		text += " Counted this month: %s GiB since %s" % [("%.2f" % used) if used < 10.0 else GameConstants.commas(roundi(used)),
			LocalTime.date(int(budget.get("since")))]
		if budget.get("affordable_per_second") != null and float(budget.get("affordable_per_second")) > 0.0:
			text += "; it can send %s to the month's end" % rate_text(float(budget.get("affordable_per_second")))
		text += "."
	return text


static func guard_colour(budget: Dictionary) -> Color:
	if budget.is_empty():
		return SAY_NOTE
	if not bool(budget.get("on", false)):
		return SAY_WARN
	match str(budget.get("level", "full")):
		"half":
			return SAY_WARN
		"crowd", "alone":
			return SAY_BAD
	return SAY_GOOD


static func share_colour(month: Variant) -> Color:
	if not (month is Dictionary):
		return SAY_NOTE
	var share: float = float((month as Dictionary).get("share", 0.0))
	return SAY_BAD if share >= 1.0 else (SAY_WARN if share >= 0.5 else SAY_GOOD)


static func nearby_text(crowd: Dictionary) -> String:
	"""Whether one area needs sending only the players near each game yet."""
	match str(crowd.get("verdict", "")):
		"on":
			# ONLY WHAT IS NEAR (0.89.0): presence.py does it now.
			return "Sending each game only nearby players: on - a crowd costs what is near each player."
		"fine":
			return "Sending each game only nearby players: not needed yet (watch from %d in one area)." % int(
				crowd.get("watch_at", 32))
		"watch":
			return "Sending each game only nearby players: worth planning - %s." % (
				"an area held %d or more this week" % int(crowd.get("watch_at", 32)) if str(crowd.get("by", "")) == "crowd"
				else "the month is past half the data included")
		"now":
			return "Sending each game only nearby players: needed now - %s." % (
				"an area held %d or more this week" % int(crowd.get("now_at", 96)) if str(crowd.get("by", "")) == "crowd"
				else "the month is past the data included")
	return "Sending each game only nearby players: not enough measured yet."


static func tick_text(tick: Dictionary) -> String:
	"""'Tick: 10.0 a second, steady. Late today: 0.'"""
	if tick.get("per_second") == null:
		return "Tick: not measured yet."
	return "Tick: %.1f a second, %s. Late beats today: %d." % [float(tick.get("per_second", 0.0)),
		"steady" if str(tick.get("verdict", "")) == "steady" else "falling behind",
		int(tick.get("late_today", 0))]


static func machine_text(machine: Dictionary) -> String:
	"""'Load 0.31 on 1 core, 412 MB free, disk 18.2 of 24.9 GB free, the
	database 120 MB.' - whatever of it could be read."""
	var bits: Array[String] = []
	if machine.get("load1") != null:
		var cores: int = int(machine.get("cores", 1)) if machine.get("cores") != null else 1
		bits.append("load %.2f on %d core%s" % [float(machine.get("load1")), cores, "" if cores == 1 else "s"])
	if machine.get("mem_free_mb") != null:
		bits.append("%s MB memory free" % GameConstants.commas(int(machine.get("mem_free_mb"))))
	if machine.get("disk_free_gb") != null:
		bits.append("disk %.1f of %.1f GB free" % [float(machine.get("disk_free_gb")),
			float(machine.get("disk_total_gb", 0.0))])
	if machine.get("db_mb") != null:
		bits.append("the database %s MB" % GameConstants.commas(roundi(float(machine.get("db_mb")))))
	if bits.is_empty():
		return "The machine: nothing read yet."
	var text: String = ", ".join(bits)
	return text.substr(0, 1).to_upper() + text.substr(1) + "."


static func route_name(route: String) -> String:
	"""'POST combat_kill' -> 'combat kill': the endpoint, as words."""
	var parts: PackedStringArray = route.split(" ", false, 1)
	return (parts[1] if parts.size() == 2 else route).replace("_", " ")


static func routes_text(routes: Dictionary) -> String:
	"""'p99: login 98 ms, combat kill 12 ms, save 9 ms. 3 errors in 2 h -
	one worker's.'"""
	var slowest: Variant = routes.get("slowest", [])
	var bits: Array[String] = []
	if slowest is Array:
		for row in slowest:
			if row is Dictionary and bits.size() < ROUTES_NAMED:
				bits.append("%s %s ms" % [route_name(str(row.get("route", ""))), _ms(float(row.get("p99_ms", 0.0)))])
	var text: String = ("p99: %s." % ", ".join(bits)) if not bits.is_empty() else "No route asked often enough yet."
	var errors: int = int(routes.get("errors", 0))
	text += " %s in %s, one worker's." % ["No server errors" if errors == 0 else "%d server error%s" % [
		errors, "" if errors == 1 else "s"], Lands.time_text(maxi(60, int(routes.get("uptime_seconds", 0))))]
	return text


static func _ms(value: float) -> String:
	return ("%.1f" % value) if value < 10.0 else str(roundi(value))


static func verdict_text(receipts: Dictionary) -> String:
	"""The receipts' verdict in a sentence."""
	var paid: int = int(receipts.get("paid", 0))
	match str(receipts.get("verdict", "")):
		"on":
			return "On: kills are paid only when the server's count agrees."
		"ready":
			return "Ready to switch on: a week of honest play is backed by the server's count."
		"no_books":
			return "Not yet: the server has not counted a fight yet."
		"young":
			return "Not yet: the server has counted fights for %.1f days; a week is wanted." % float(
				receipts.get("books_days", 0.0))
		"few":
			return "Not yet: %d kill%s paid this week; %d are wanted to judge by." % [paid, "" if paid == 1 else "s",
				int(receipts.get("min_kills", 200))]
		"short":
			return "Not yet: %s of kills had the server's count; %d%% is wanted." % [
				_percent(receipts.get("share")), roundi(float(receipts.get("ready_share", 0.98)) * 100.0)]
		"monster":
			var never: Variant = receipts.get("never_by_enemy", [])
			var first: String = str(never[0][0]) if never is Array and not (never as Array).is_empty() else "a monster"
			return "Not yet: the server never saw %s die %d times - its land may not be mapped." % [
				EnemyPortraits.display_name(first), int(never[0][1]) if never is Array and not (never as Array).is_empty() else 0]
	return "Not read yet."


static func verdict_colour(receipts: Dictionary) -> Color:
	match str(receipts.get("verdict", "")):
		"on", "ready":
			return SAY_GOOD
		"short", "monster":
			return SAY_BAD
		"young", "few":
			return SAY_WARN
	return SAY_NOTE


static func _percent(share: Variant) -> String:
	if share == null:
		return "none"
	return "%.1f%%" % (float(share) * 100.0)


static func detail_text(receipts: Dictionary) -> String:
	"""'Of 412 kills paid in the last 7 days, 405 (98.3%) had the server's
	count; 2 short, 0 not due, 5 never seen (Slime 3, Bat 2).'"""
	var paid: int = int(receipts.get("paid", 0))
	if paid == 0:
		return "No kills paid in the last %d days to measure by." % int(receipts.get("days", 7))
	var text: String = "Of %s kill%s paid in the last %d days, %s (%s) had the server's count; %d short, %d not due, %d never seen" % [
		GameConstants.commas(paid), "" if paid == 1 else "s", int(receipts.get("days", 7)),
		GameConstants.commas(int(receipts.get("backed", 0))), _percent(receipts.get("share")),
		int(receipts.get("short", 0)), int(receipts.get("not_due", 0)), int(receipts.get("never", 0))]
	var named: Array[String] = []
	var never: Variant = receipts.get("never_by_enemy", [])
	if never is Array:
		for pair in never:
			if pair is Array and (pair as Array).size() == 2:
				named.append("%s %d" % [EnemyPortraits.display_name(str(pair[0])), int(pair[1])])
	if not named.is_empty():
		text += " (%s)" % ", ".join(named)
	return text + "."


# =============================================================================
# THE ROWS (0.168.13): each page's numbers, a name and a value; the sentences
# above stay for the tooltips and for Results.
# =============================================================================

static func players_quiet_text(data: Dictionary) -> String:
	"""Said above the rows only when presence.py is not writing."""
	var presence: Dictionary = _dict(data.get("presence"))
	var last: Dictionary = _dict(presence.get("last"))
	if last.is_empty():
		return "presence.py has not written a minute yet. It writes one a minute once it runs this update."
	if not bool(presence.get("reporting", false)):
		return "presence.py has not written for %s - is it running? The rows are the last it wrote." % Lands.time_text(
			int(last.get("age_seconds", 0)))
	return ""


static func players_rows(data: Dictionary) -> Array:
	var presence: Dictionary = _dict(data.get("presence"))
	var last: Dictionary = _dict(presence.get("last"))
	if last.is_empty():
		return []
	var rows: Array = [["Online", str(int(last.get("connections", 0)))],
		["In an area", str(int(last.get("players", 0)))]]
	var crowd: Variant = last.get("crowd", [])
	if crowd is Array and not (crowd as Array).is_empty() and (crowd as Array)[0] is Array:
		rows.append(["Biggest crowd", "%s, %d" % [area_name(str(crowd[0][0])), int(crowd[0][1])]])
	var day: Dictionary = _dict(presence.get("day"))
	var week: Dictionary = _dict(presence.get("week"))
	if int(day.get("samples", 0)) > 0:
		rows.append(["Most today", "%d%s" % [int(day.get("peak_players", 0)), _peak_area(day)]])
	if int(week.get("samples", 0)) > int(day.get("samples", 0)):
		rows.append(["Most this week", "%d%s" % [int(week.get("peak_players", 0)), _peak_area(week)]])
	return rows


static func tick_rows(tick: Dictionary) -> Array:
	if tick.get("per_second") == null:
		return [["Tick", "not measured yet", SAY_NOTE]]
	var steady: bool = str(tick.get("verdict", "")) == "steady"
	return [["Tick", "%.1f a second, %s" % [float(tick.get("per_second", 0.0)), "steady" if steady else "falling behind"],
			SAY_GOOD if steady else SAY_WARN],
		["Late beats today", str(int(tick.get("late_today", 0)))]]


static func data_rows(data: Dictionary) -> Array:
	var rows: Array = []
	var last: Dictionary = _dict(_dict(data.get("presence")).get("last"))
	if last.is_empty():
		rows.append(["Going out", "nothing measured yet", SAY_NOTE])
	elif last.get("net_per_second") == null:
		rows.append(["Game sockets", rate_text(float(last.get("bytes_per_second", 0.0)))])
	else:
		rows.append(["Going out now", rate_text(float(last.get("net_per_second", 0.0)))])
		rows.append(["Game sockets", rate_text(float(last.get("bytes_per_second", 0.0)))])
	var month: Variant = data.get("month")
	if not (month is Dictionary):
		rows.append(["This month", "not enough measured yet", SAY_NOTE])
		return rows
	var held: Dictionary = month
	var gib: float = float(held.get("gib", 0.0))
	var shown: String = ("%.1f" % gib) if gib < 10.0 else GameConstants.commas(roundi(gib))
	rows.append(["Month at this rate", "%s / %s GiB%s" % [shown, GameConstants.commas(int(held.get("allowance_gib", 1000))),
		" (sockets)" if str(held.get("source", "")) == "presence" else ""], share_colour(month)])
	if float(held.get("over_cost", 0.0)) > 0.0:
		rows.append(["Over the plan", "about $%s" % GameConstants.commas(roundi(float(held.get("over_cost", 0.0)))), SAY_BAD])
	return rows


static func guard_rows(budget: Dictionary, crowd: Dictionary) -> Array:
	var rows: Array = []
	if budget.is_empty():
		rows.append(["Guard", "not on this server yet", SAY_NOTE])
	elif not bool(budget.get("on", false)):
		rows.append(["Guard", "switched off", SAY_WARN])
	else:
		var level: String = {"half": "holding - half rate",
			"crowd": "holding hard - %d a room" % int(budget.get("crowd_cap", 16) if budget.get("crowd_cap") != null else 16),
			"alone": "month nearly spent - players alone"}.get(str(budget.get("level", "full")), "full speed")
		rows.append(["Guard", level, guard_colour(budget)])
		if budget.get("used_gib") != null and budget.get("since") != null:
			var used: float = float(budget.get("used_gib"))
			rows.append(["Counted this month", "%s GiB since %s" % [("%.2f" % used) if used < 10.0 else GameConstants.commas(roundi(used)),
				LocalTime.date(int(budget.get("since")))]])
		if budget.get("affordable_per_second") != null and float(budget.get("affordable_per_second")) > 0.0:
			rows.append(["Can still send", rate_text(float(budget.get("affordable_per_second")))])
	var verdict: String = str(crowd.get("verdict", ""))
	var nearby: String = {"on": "on", "fine": "not needed yet", "watch": "worth planning", "now": "needed now"}.get(
		verdict, "not measured yet")
	rows.append(["Nearby players only", nearby,
		{"now": SAY_BAD, "watch": SAY_WARN, "fine": SAY_GOOD, "on": SAY_GOOD}.get(verdict, SAY_NOTE)])
	return rows


static func machine_rows(machine: Dictionary) -> Array:
	var rows: Array = []
	if machine.get("load1") != null:
		var cores: int = int(machine.get("cores", 1)) if machine.get("cores") != null else 1
		var load: float = float(machine.get("load1"))
		rows.append(["Load", "%.2f on %d core%s" % [load, cores, "" if cores == 1 else "s"],
			SAY_BAD if load >= cores else (SAY_WARN if load >= 0.7 * cores else ROW_VALUE)])
	if machine.get("mem_free_mb") != null:
		rows.append(["Memory free", "%s MB" % GameConstants.commas(int(machine.get("mem_free_mb")))])
	if machine.get("disk_free_gb") != null:
		rows.append(["Disk free", "%.1f of %.1f GB" % [float(machine.get("disk_free_gb")), float(machine.get("disk_total_gb", 0.0))]])
	if machine.get("db_mb") != null:
		rows.append(["Database", "%s MB" % GameConstants.commas(roundi(float(machine.get("db_mb"))))])
	if rows.is_empty():
		rows.append(["The machine", "nothing read yet", SAY_NOTE])
	return rows


static func routes_rows(routes: Dictionary) -> Array:
	var rows: Array = []
	var slowest: Variant = routes.get("slowest", [])
	if slowest is Array:
		for row in slowest:
			if row is Dictionary and rows.size() < ROUTES_NAMED:
				var named: String = route_name(str(row.get("route", "")))
				rows.append([named.left(1).to_upper() + named.substr(1), "%s ms" % _ms(float(row.get("p99_ms", 0.0)))])
	if rows.is_empty():
		rows.append(["Routes", "none asked often enough yet", SAY_NOTE])
	var errors: int = int(routes.get("errors", 0))
	rows.append(["Server errors", "%s in %s" % ["none" if errors == 0 else str(errors),
		Lands.time_text(maxi(60, int(routes.get("uptime_seconds", 0))))], SAY_GOOD if errors == 0 else SAY_BAD])
	return rows


static func receipt_rows(receipts: Dictionary) -> Array:
	var paid: int = int(receipts.get("paid", 0))
	var days: int = int(receipts.get("days", 7))
	if paid == 0:
		return [["Kills paid, %d days" % days, "none to measure by", SAY_NOTE]]
	var rows: Array = [["Kills paid, %d days" % days, GameConstants.commas(paid)],
		["Backed by the server", "%s (%s)" % [GameConstants.commas(int(receipts.get("backed", 0))), _percent(receipts.get("share"))]],
		["Short / not due / never", "%d / %d / %d" % [int(receipts.get("short", 0)), int(receipts.get("not_due", 0)),
			int(receipts.get("never", 0))]]]
	var named: Array[String] = []
	var never: Variant = receipts.get("never_by_enemy", [])
	if never is Array:
		for pair in never:
			if pair is Array and (pair as Array).size() == 2:
				named.append("%s %d" % [EnemyPortraits.display_name(str(pair[0])), int(pair[1])])
	if not named.is_empty():
		rows.append(["Never seen", ", ".join(named)])
	return rows


static func build_text(receipts: Dictionary) -> String:
	"""Said only while it matters: ready or on, with the oldest build allowed
	in still below the receipts' own."""
	var verdict: String = str(receipts.get("verdict", ""))
	if not bool(receipts.get("min_build_low", false)) or verdict not in ["ready", "on"]:
		return ""
	return "Set Old versions must update to %d first (the Server tab): an older game cannot wait for the count." % int(
		receipts.get("receipt_build", 7))
