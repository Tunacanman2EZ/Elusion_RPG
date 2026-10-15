# eventstab.gd - the GM panel's Events tab: the world's events (0.48.0).
#
# The owner: "Treat events (double XP, double loot, forced stir, etc.) as their
# own feature area with a clean public contract" - and the GM UI can set them
# without a new build. The server holds them (the API's events/ package); this
# tab is its owner's side:
#
#   - schedule one: what (more XP, more loot, a land stirs), how much (1.25x
#     to 3x), whose monsters (every monster, the stirring land's, or one
#     land's), when (now, or a day and a time on THIS computer's clock), for
#     how many hours (1-72), and a name if it wants one
#   - what is on and what is coming, and the last few that ended
#   - call one off
#
# Read from GET /api/world/events/schedule when the panel opens or Refresh is
# pressed. Schedule sends POST /api/world/events, Call off POST
# /api/world/events/cancel; both are owner-only and ask for the password
# again on a hardened login (STEP-UP, the HUD's prompt). The server checks
# every value and says why it refused; the controls only offer what it allows.
# What each button did is said on the tab and in the panel's Results box
# (`report`, OwnerPanel._say), like the World tab's.
#
# AND BEFORE IT IS SET, AND AFTER (0.49.0). The owner's: "a dry-run page that
# shows: if 20 players join during this event, expected XP/gold output range
# is X-Y", and "dashboards that show, for each event: XP/hour and gold/hour
# before/during/after; player count online vs time". Dry run sends what the
# controls hold to POST /api/world/events/preview and says in Results whether
# the server would allow it (its guardrails: never too much at once), the most
# any land's monsters would pay, and what 20 players might earn, from the last
# two weeks' play. Report opens the Event report window (eventreport.gd)
# through the HUD.
extends VBoxContainer
class_name EventsTab


const PATH := "/api/world/events/schedule"
const SCHEDULE_PATH := "/api/world/events"
const CANCEL_PATH := "/api/world/events/cancel"
const PREVIEW_PATH := "/api/world/events/preview"
# Who the dry run forecasts for: the owner's "if 20 players join".
const DRY_RUN_PLAYERS := 20
const SAY_GOOD := Color(0.55, 0.86, 0.6)
const SAY_BAD := Color(0.95, 0.55, 0.5)
const SAY_NOTE := Color(0.78, 0.82, 0.87)
const HEAD := Color(0.56, 0.93, 0.62)
# The GM panel's inside width, near enough: it is 370 wide.
const WIDTH := 250.0
# [kind, words in the picker, hint]
const KINDS := [
	["xp", "More XP", "Every kill it covers gives this many times the XP."],
	["loot", "More loot", "Every kill it covers drops a loot bag this many times as often."],
	["stir", "A land stirs", "The land picked stirs for the whole event - the stirring lands must be switched on."],
]
const LAND_ANY := 0
const LAND_STIRRING := -1
const LANDS := [Element.Type.DARK, Element.Type.LIGHT, Element.Type.ICE, Element.Type.WIND,
	Element.Type.EARTH, Element.Type.FIRE, Element.Type.WATER]
# The day picker: Now, then today and the next DAYS_SHOWN - 1 days.
const DAY_NOW := -1
const DAYS_SHOWN := 21
const DAY_WIDTH := 132.0
# How many events the list shows before "and N more".
const LISTED := 4

# Where requests go; seams for the suite.
var fetch: Callable = Callable(Api, "get_json")
var send: Callable = Callable(Api, "post")
# Where results also go: the GM panel's Results box, set by the panel.
var report: Callable = Callable()
# Opens the Event report window, set by the panel (through the HUD); answers
# false out of the game.
var open_report: Callable = Callable()
# The last answer from the server.
var answer: Dictionary = {}

var status_label: Label
var kind_pick: OptionButton
var amount_box: SpinBox
var land_pick: OptionButton
var day_pick: OptionButton
var hour_box: SpinBox
var minute_box: SpinBox
var hours_box: SpinBox
var name_edit: LineEdit
var schedule_button: Button
var dry_run_button: Button
var report_button: Button
var refresh_button: Button
var list_label: Label
var cancel_pick: OptionButton
var cancel_button: Button
var say_label: Label
var _busy: bool = false


func _init() -> void:
	name = "events"
	add_theme_constant_override("separation", 6)
	_build()


func _build() -> void:
	# NARROW AND SHORT, like the World tab: the GM panel is 370 wide and holds
	# its tallest tab at its drawn size (the suite measures both).
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	add_child(top)
	status_label = _label("Events: not read yet.", HEAD, false)
	status_label.name = "status"
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(status_label)
	report_button = _button("Report", "Each event's before, during and after - XP and gold an hour, who played, who was online - and a chart of who was online this week.")
	report_button.name = "report"
	report_button.pressed.connect(_on_report_pressed)
	top.add_child(report_button)

	var what := HBoxContainer.new()
	what.add_theme_constant_override("separation", 6)
	add_child(what)
	kind_pick = OptionButton.new()
	kind_pick.name = "kind"
	kind_pick.focus_mode = Control.FOCUS_NONE
	for i in KINDS.size():
		kind_pick.add_item(str(KINDS[i][1]), i)
		kind_pick.set_item_tooltip(i, str(KINDS[i][2]))
	kind_pick.item_selected.connect(_on_kind_selected)
	what.add_child(kind_pick)
	amount_box = _spin(1.25, 3.0, 0.25, "x")
	amount_box.name = "amount"
	amount_box.value = 2.0
	amount_box.tooltip_text = "How many times: 1.25x to 3x. Two events of one kind at once give the bigger, never both."
	what.add_child(amount_box)

	land_pick = OptionButton.new()
	land_pick.name = "land"
	land_pick.focus_mode = Control.FOCUS_NONE
	land_pick.tooltip_text = "Whose monsters it covers - or, for a stir, which land stirs."
	# THE VALUES ARE METADATA, NOT ITEM IDS: an OptionButton takes an id of -1
	# to mean "use the index", so the stirring land's -1 would come back as 1,
	# the dark lands - and the day picker's Now as 0, today.
	var land_words: Array = [["Every monster", LAND_ANY], ["The stirring land's", LAND_STIRRING]]
	for element in LANDS:
		land_words.append(["The %s lands" % Element.name_for(element), element])
	for entry in land_words:
		land_pick.add_item(str(entry[0]))
		land_pick.set_item_metadata(land_pick.item_count - 1, int(entry[1]))
	add_child(land_pick)

	var when := HBoxContainer.new()
	when.add_theme_constant_override("separation", 2)
	add_child(when)
	day_pick = OptionButton.new()
	day_pick.name = "day"
	day_pick.focus_mode = Control.FOCUS_NONE
	day_pick.tooltip_text = "When it starts, on this computer's clock."
	# ONE WIDTH WHATEVER THE MONTH: sized to its longest name, "Wed Sep 30"
	# would make the tab wider in September than in May. DAY_WIDTH holds the
	# widest a name can be (the suite measures every weekday in every month).
	day_pick.fit_to_longest_item = false
	day_pick.clip_text = true
	day_pick.custom_minimum_size = Vector2(DAY_WIDTH, 0)
	day_pick.item_selected.connect(_on_day_selected)
	when.add_child(day_pick)
	hour_box = _spin(0.0, 23.0, 1.0, "")
	hour_box.name = "hour"
	_two_digits(hour_box)
	hour_box.tooltip_text = "The hour it starts (0-23), this computer's clock."
	when.add_child(hour_box)
	when.add_child(_label(":", SAY_NOTE, false))
	minute_box = _spin(0.0, 55.0, 5.0, "")
	minute_box.name = "minute"
	_two_digits(minute_box)
	minute_box.tooltip_text = "The minute it starts."
	when.add_child(minute_box)
	fill_days(int(Time.get_unix_time_from_system()))

	var length := HBoxContainer.new()
	length.add_theme_constant_override("separation", 6)
	add_child(length)
	length.add_child(_label("For", SAY_NOTE, false))
	hours_box = _spin(1.0, 72.0, 1.0, "h")
	hours_box.name = "hours"
	hours_box.value = 3.0
	hours_box.tooltip_text = "How many hours it lasts: 1 to 72."
	length.add_child(hours_box)
	name_edit = LineEdit.new()
	name_edit.name = "eventname"
	name_edit.placeholder_text = "Name (optional)"
	name_edit.max_length = 40
	name_edit.tooltip_text = "Left empty, it is named for what it does: Double XP, 1.5x Loot, The Fire Lands Stir."
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	length.add_child(name_edit)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	add_child(buttons)
	schedule_button = _button("Schedule", "Set it - everyone online is told it is coming, and told again when it begins.")
	schedule_button.name = "schedule"
	schedule_button.pressed.connect(schedule)
	# NOT UNTIL THE SERVER HAS BEEN READ: a server without events would only
	# answer 404, and the list would say nothing of what is already set.
	schedule_button.disabled = true
	buttons.add_child(schedule_button)
	dry_run_button = _button("Dry run", "What it would do, without setting it: allowed or not, the most it pays, what %d players might earn." % DRY_RUN_PLAYERS)
	dry_run_button.name = "dryrun"
	dry_run_button.pressed.connect(dry_run)
	dry_run_button.disabled = true
	buttons.add_child(dry_run_button)
	refresh_button = _button("Refresh", "Read the events again from the server.")
	refresh_button.name = "refresh"
	refresh_button.pressed.connect(refresh.bind(true))
	buttons.add_child(refresh_button)

	list_label = _label("", SAY_NOTE)
	list_label.name = "list"
	add_child(list_label)

	var off_row := HBoxContainer.new()
	off_row.add_theme_constant_override("separation", 8)
	add_child(off_row)
	cancel_pick = OptionButton.new()
	cancel_pick.name = "cancelpick"
	cancel_pick.focus_mode = Control.FOCUS_NONE
	cancel_pick.custom_minimum_size = Vector2(150, 0)
	cancel_pick.clip_text = true
	off_row.add_child(cancel_pick)
	cancel_button = _button("Call off", "End it now, or stop it before it starts - announced to everyone.")
	cancel_button.name = "cancel"
	cancel_button.pressed.connect(cancel)
	cancel_button.disabled = true
	off_row.add_child(cancel_button)

	say_label = _label("", SAY_NOTE)
	say_label.name = "say"
	add_child(say_label)
	_on_kind_selected(0)
	_on_day_selected(0)


func _label(text: String, colour: Color, wraps: bool = true) -> Label:
	var label := Label.new()
	label.text = text
	if wraps:
		# A WRAPPING LABEL WITH NO WIDTH OF ITS OWN is measured at one word a
		# line (the World tab learnt it); given the tab's width, it is not.
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(WIDTH, 0)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_font_size_override("font_size", 13)
	return label


func _spin(low: float, high: float, step: float, suffix: String) -> SpinBox:
	var box := SpinBox.new()
	box.min_value = low
	box.max_value = high
	box.step = step
	box.suffix = suffix
	box.custom_minimum_size = Vector2(84, 0)
	return box


func _two_digits(box: SpinBox) -> void:
	"""Room for two digits and no more: the hour and the minute share a row
	with the day, in a tab 370 wide."""
	box.custom_minimum_size = Vector2.ZERO
	box.get_line_edit().add_theme_constant_override("minimum_character_width", 2)


func _button(text: String, hint: String) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = hint
	button.focus_mode = Control.FOCUS_NONE
	return button


func _say(line: String, colour: Color = SAY_NOTE, results: String = "") -> void:
	"""On the tab, and in the Results box (`results` there when given)."""
	_say_here(line, colour)
	if report.is_valid():
		report.call("[EVENTS] " + (results if results != "" else line), colour)


func _say_here(line: String, colour: Color = SAY_NOTE) -> void:
	say_label.text = line
	say_label.add_theme_color_override("font_color", colour)


# =============================================================================
# THE CONTROLS
# =============================================================================

func kind() -> String:
	return str(KINDS[clampi(kind_pick.get_item_id(kind_pick.selected), 0, KINDS.size() - 1)][0])


func land() -> int:
	"""The land picked: 0 every monster, -1 the stirring land's, 1-7 a land."""
	return int(land_pick.get_item_metadata(land_pick.selected)) if land_pick.selected >= 0 else LAND_ANY


func land_index(value: int) -> int:
	for i in land_pick.item_count:
		if int(land_pick.get_item_metadata(i)) == value:
			return i
	return -1


func day() -> int:
	"""The day picked: DAY_NOW, or how many days after today."""
	return int(day_pick.get_item_metadata(day_pick.selected)) if day_pick.selected >= 0 else DAY_NOW


func day_index(value: int) -> int:
	for i in day_pick.item_count:
		if int(day_pick.get_item_metadata(i)) == value:
			return i
	return -1


func _on_kind_selected(_index: int) -> void:
	"""A stir names a land and has no amount; XP and loot may cover every
	monster or the stirring land's as well."""
	var stir: bool = kind() == "stir"
	amount_box.editable = not stir
	for value in [LAND_ANY, LAND_STIRRING]:
		land_pick.set_item_disabled(land_index(value), stir)
	if stir and land() <= LAND_ANY:
		land_pick.select(land_index(Element.Type.FIRE))


func _on_day_selected(_index: int) -> void:
	"""Now has no hour and minute of its own."""
	var now_picked: bool = day() == DAY_NOW
	hour_box.editable = not now_picked
	minute_box.editable = not now_picked


func fill_days(now_unix: int) -> void:
	"""Now, Today, Tomorrow, then 'Sat Oct 17' - on this computer's calendar."""
	var kept: int = day()
	day_pick.clear()
	day_pick.add_item("Now")
	day_pick.set_item_metadata(0, DAY_NOW)
	for ahead in DAYS_SHOWN:
		var at: Dictionary = LocalTime.parts(now_unix + ahead * 86400)
		var words: String = "Today" if ahead == 0 else ("Tomorrow" if ahead == 1 else "%s %s %d" % [
			LocalTime.WEEKDAYS[int(at.get("weekday", 0)) % 7], LocalTime.MONTHS[clampi(int(at.get("month", 1)), 1, 12)],
			int(at.get("day", 1))])
		day_pick.add_item(words)
		day_pick.set_item_metadata(day_pick.item_count - 1, ahead)
	var index: int = day_index(kept)
	day_pick.select(index if index >= 0 else 0)


static func start_time(days_on: int, hour: int, minute: int, now_unix: int) -> int:
	"""The unix time of `hour`:`minute` on this computer's clock, `days_on` days
	after today (0 is today). SHIFT, BUILD, SHIFT BACK: today's date is read
	in local time (LocalTime.parts()), the wall-clock time is built on it as
	if it were UTC, and the offset in force then is taken off."""
	var today: Dictionary = LocalTime.parts(now_unix)
	var wall: int = int(Time.get_unix_time_from_datetime_dict({
		"year": int(today.get("year", 1970)), "month": int(today.get("month", 1)), "day": int(today.get("day", 1)),
		"hour": 0, "minute": 0, "second": 0})) + days_on * 86400 + hour * 3600 + minute * 60
	var guess: int = wall - LocalTime.bias_minutes() * 60
	return wall - LocalTime.bias_minutes_at(guess) * 60


func event_from_controls(at_now: int) -> Dictionary:
	"""What Schedule sends. `at_now` (the server's clock) is the start for Now."""
	var picked_day: int = day()
	var starts_at: int = at_now if picked_day == DAY_NOW \
		else start_time(picked_day, int(hour_box.value), int(minute_box.value), int(Time.get_unix_time_from_system()))
	var out := {"kind": kind(), "starts_at": starts_at, "hours": int(hours_box.value), "land": land()}
	if kind() != "stir":
		out["amount"] = snappedf(amount_box.value, 0.01)
	var typed: String = name_edit.text.strip_edges()
	if typed != "":
		out["name"] = typed
	return out


static func refusal(res: Dictionary) -> String:
	var status: int = int(res.get("status", 0))
	if status == 0:
		return "Could not reach the server."
	if status == 404:
		# Only the owner sees this tab, so a 404 on reading is a server from
		# before 0.48.0.
		return "This server does not have events yet (404). Update the server, then Refresh."
	return "The server refused (%d): %s" % [status, str(res.get("error", ""))]


# =============================================================================
# THE SERVER
# =============================================================================

func server_now() -> int:
	"""The server's clock as the last answer gave it, moved on since."""
	return WorldEvents.now() if not answer.has("now") \
		else int(answer.get("now")) + int(Time.get_unix_time_from_system()) - int(answer.get("_read_at", 0))


func refresh(by_hand: bool = false) -> void:
	"""Read the events again. By hand (Refresh), what was read goes in the
	Results box; opening the panel reads quietly."""
	if _busy:
		return
	_busy = true
	var res: Dictionary = await fetch.call(PATH)
	_busy = false
	if not is_instance_valid(self):
		return
	if not res.get("ok", false) or not (res.get("data") is Dictionary):
		answer = {}
		schedule_button.disabled = true
		dry_run_button.disabled = true
		cancel_button.disabled = true
		status_label.text = "Events: not read."
		_say(refusal(res), SAY_BAD)
		return
	show_answer(res.get("data"))
	if by_hand:
		_say("Read from the server.", SAY_GOOD, "Read from the server. " + status_text(answer))


func schedule() -> void:
	if _busy or answer.is_empty():
		return
	var event: Dictionary = event_from_controls(server_now())
	_busy = true
	_say_here("Scheduling...")
	var res: Dictionary = await send.call(SCHEDULE_PATH, event)
	_busy = false
	if not is_instance_valid(self):
		return
	if not res.get("ok", false):
		_say(refusal(res) if int(res.get("status", 0)) != 409 else str(res.get("error", "Too many waiting.")), SAY_BAD)
		return
	var data: Dictionary = res.get("data", {}) if res.get("data") is Dictionary else {}
	var made: Dictionary = data.get("event", {}) if data.get("event") is Dictionary else {}
	var at: int = int(made.get("starts_at", 0))
	var begins: String = "now" if at <= int(data.get("now", at)) else LocalTime.stamp(at)
	_say("Scheduled: %s, %s." % [str(made.get("name", "the event")), begins], SAY_GOOD,
		"Scheduled: %s, %s, for %d h - %s Everyone online is told." % [str(made.get("name", "the event")), begins,
			int(event.get("hours", 0)), str(made.get("description", ""))])
	var warned: Variant = data.get("warnings", [])
	if warned is Array and report.is_valid():
		for line in warned:
			report.call("[EVENTS]   " + str(line), SAY_BAD)
	name_edit.text = ""
	await refresh()


func dry_run() -> void:
	"""What the controls hold, asked of the server without setting it - into
	Results, line by line."""
	if _busy or answer.is_empty():
		return
	var event: Dictionary = event_from_controls(server_now())
	event["players"] = DRY_RUN_PLAYERS
	_busy = true
	_say_here("Asking...")
	var res: Dictionary = await send.call(PREVIEW_PATH, event)
	_busy = false
	if not is_instance_valid(self):
		return
	if not res.get("ok", false) or not (res.get("data") is Dictionary):
		_say("This server has no dry run yet (404). Update the server." if int(res.get("status", 0)) == 404
			else refusal(res), SAY_BAD)
		return
	var data: Dictionary = res.get("data")
	var allowed: bool = bool(data.get("allowed", false))
	_say_here("Dry run: %s - see Results." % ("allowed" if allowed else "not allowed"), SAY_GOOD if allowed else SAY_BAD)
	if report.is_valid():
		var lines: Array[String] = dry_run_lines(data)
		for i in lines.size():
			report.call("[EVENTS] " + ("" if i == 0 else "  ") + lines[i], (SAY_GOOD if allowed else SAY_BAD) if i == 0 else SAY_NOTE)


static func _times_text(value: float) -> String:
	var text: String = "%.2f" % value
	while text.ends_with("0"):
		text = text.substr(0, text.length() - 1)
	return text.trim_suffix(".")


static func _span(pair: Variant) -> String:
	"""[24000, 54000] -> '24K-54K'."""
	if not (pair is Array) or (pair as Array).size() < 2:
		return "?"
	var low: String = GameConstants.short_number(int(pair[0]))
	var high: String = GameConstants.short_number(int(pair[1]))
	return low if low == high else "%s-%s" % [low, high]


static func worst_text(worst: Variant) -> String:
	"""'2x XP and 3x loot (6x together) for every monster' - the most any
	land's monsters would be paid, from the dry run's rows."""
	if not (worst is Array) or (worst as Array).is_empty():
		return ""
	var rows: Array = (worst as Array).filter(func(row: Variant) -> bool: return row is Dictionary)
	if rows.is_empty():
		return ""
	var top: Dictionary = rows[0]
	var same: bool = true
	for row in rows:
		if float(row.get("together", 1.0)) > float(top.get("together", 1.0)):
			top = row
	for row in rows:
		if not is_equal_approx(float(row.get("xp", 1.0)), float(top.get("xp", 1.0))) \
				or not is_equal_approx(float(row.get("loot", 1.0)), float(top.get("loot", 1.0))):
			same = false
	var xp: float = float(top.get("xp", 1.0))
	var loot: float = float(top.get("loot", 1.0))
	var parts: Array[String] = []
	if xp > 1.0001:
		parts.append("%sx XP" % _times_text(xp))
	if loot > 1.0001:
		parts.append("%sx loot" % _times_text(loot))
	if parts.is_empty():
		return "nothing more than usual for any monster"
	var paid: String = " and ".join(parts)
	if parts.size() == 2:
		paid += " (%sx together)" % _times_text(float(top.get("together", xp * loot)))
	return "%s for %s" % [paid, "every monster" if same else "the %s lands' monsters" % str(top.get("name", "?"))]


static func dry_run_lines(data: Dictionary) -> Array[String]:
	"""The dry run in sentences: allowed or why not, the most at once, any
	warnings, and the forecast."""
	var out: Array[String] = []
	var event: Dictionary = data.get("event", {}) if data.get("event") is Dictionary else {}
	var now: int = int(data.get("now", 0))
	var starts: int = int(event.get("starts_at", now))
	@warning_ignore("integer_division")
	var hours: int = (int(event.get("ends_at", starts)) - starts) / 3600
	var when: String = "now" if starts <= now + 60 else LocalTime.stamp(starts, now)
	var allowed: bool = bool(data.get("allowed", false))
	out.append("Dry run - %s, %s, for %d h: %s" % [str(event.get("name", "the event")), when, hours,
		"allowed." if allowed else "not allowed."])
	if not allowed and str(data.get("why", "")) != "":
		out.append(str(data.get("why")))
	var most: String = worst_text(data.get("worst"))
	if most != "":
		var limits: Dictionary = data.get("limits", {}) if data.get("limits") is Dictionary else {}
		out.append("The most at once: %s. The ceilings: %sx XP, %sx loot, %sx together." % [most,
			_times_text(float(limits.get("xp", 3.0))), _times_text(float(limits.get("loot", 3.0))),
			_times_text(float(limits.get("together", 6.0)))])
	var warned: Variant = data.get("warnings", [])
	if warned is Array:
		for line in warned:
			out.append(str(line))
	var cast: Dictionary = data.get("forecast", {}) if data.get("forecast") is Dictionary else {}
	if not cast.is_empty():
		var xp: Dictionary = cast.get("xp", {}) if cast.get("xp") is Dictionary else {}
		var gold: Dictionary = cast.get("gold", {}) if cast.get("gold") is Dictionary else {}
		out.append("If %d players play all %d h: %s XP as usual, %s with it; %s gold as usual, %s with it." % [
			int(cast.get("players", 0)), hours, _span(xp.get("usual")), _span(xp.get("with")),
			_span(gold.get("usual")), _span(gold.get("with"))])
		out.append("From %d player-hours of play in the last two weeks%s. The most players online at once then: %d." % [
			int(cast.get("player_hours", 0)), "" if bool(cast.get("enough", false)) else " - too few to be more than a guess",
			int(data.get("peak_online", 0))])
	return out


func _on_report_pressed() -> void:
	if not open_report.is_valid() or not bool(open_report.call()):
		_say("The event report opens from inside the game.", SAY_BAD)


func cancel() -> void:
	if _busy or answer.is_empty() or cancel_pick.selected < 0 or cancel_pick.item_count == 0:
		return
	var event_id: int = cancel_pick.get_item_id(cancel_pick.selected)
	var words: String = cancel_pick.get_item_text(cancel_pick.selected)
	_busy = true
	_say_here("Calling it off...")
	var res: Dictionary = await send.call(CANCEL_PATH, {"id": event_id})
	_busy = false
	if not is_instance_valid(self):
		return
	if not res.get("ok", false):
		_say(refusal(res) if int(res.get("status", 0)) != 404 else "It has already ended, or was called off.", SAY_BAD)
		await refresh()
		return
	_say("Called off: %s - everyone online is told." % words, SAY_GOOD)
	await refresh()


# =============================================================================
# WHAT IT SHOWS
# =============================================================================

func show_answer(data: Dictionary) -> void:
	answer = data.duplicate(true)
	answer["_read_at"] = int(Time.get_unix_time_from_system())
	status_label.text = status_text(answer)
	list_label.text = list_text(answer)
	cancel_pick.clear()
	for event in waiting(answer):
		cancel_pick.add_item("%s (%s)" % [str(event.get("name", "?")), when_text(event, int(answer.get("now", 0)))],
			int(event.get("id", 0)))
	cancel_button.disabled = cancel_pick.item_count == 0
	if cancel_pick.item_count == 0:
		cancel_pick.add_item("Nothing to call off", 0)
		cancel_pick.set_item_disabled(0, true)
	schedule_button.disabled = false
	dry_run_button.disabled = false
	fill_days(int(Time.get_unix_time_from_system()))


static func waiting(data: Dictionary) -> Array[Dictionary]:
	"""The events on now and to come, soonest first."""
	var out: Array[Dictionary] = []
	var events: Variant = data.get("events", [])
	if events is Array:
		for event in events:
			if event is Dictionary and str(event.get("state", "")) in ["on", "coming"]:
				out.append(event)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("starts_at", 0)) < int(b.get("starts_at", 0)))
	return out


static func when_text(event: Dictionary, now: int) -> String:
	"""'on, 2h 14m left' or 'Sat 14:00, 3 h'."""
	var starts: int = int(event.get("starts_at", 0))
	var ends: int = int(event.get("ends_at", 0))
	if starts <= now:
		return "on, %s left" % WorldEvents.span_text(maxi(0, ends - now))
	@warning_ignore("integer_division")
	var hours: int = (ends - starts) / 3600
	return "%s, %d h" % [LocalTime.stamp(starts, now), hours]


static func status_text(data: Dictionary) -> String:
	var all: Array[Dictionary] = waiting(data)
	var on: int = all.filter(func(event: Dictionary) -> bool: return str(event.get("state", "")) == "on").size()
	if all.is_empty():
		return "No events on or coming."
	return "%d on now, %d coming." % [on, all.size() - on]


static func list_text(data: Dictionary) -> String:
	"""Each one on or coming, soonest first, then the last few that ended."""
	var now: int = int(data.get("now", 0))
	var rows: Array[String] = []
	var all: Array[Dictionary] = waiting(data)
	for event in all.slice(0, LISTED):
		rows.append("%s - %s" % [str(event.get("name", "?")), when_text(event, now)])
	if all.size() > LISTED:
		rows.append("and %d more" % (all.size() - LISTED))
	var ended: Array[String] = []
	var events: Variant = data.get("events", [])
	if events is Array:
		for event in events:
			if event is Dictionary and str(event.get("state", "")) in ["over", "cancelled"] and ended.size() < 3:
				ended.append("%s (%s)" % [str(event.get("name", "?")),
					"called off" if str(event.get("state", "")) == "cancelled" else "over"])
	if not ended.is_empty():
		rows.append("Last: " + ", ".join(ended))
	return "\n".join(rows)
