# healthtab.gd - the GM panel's Health tab (0.78.0).
#
# The owner, of four next steps after the 128-player swarm (send each game
# only the players near it, watch the live server, test on the real machine,
# let the server referee every kill): "work on this or if you have a even
# better idea lets hear it". Two of those were numbers only SSH could read,
# and the first needed one nobody had - what the server really sends, against
# the 1,000 GiB a month the droplet comes with. GET /api/server/health has
# them all (the API's serverhealth/), on three pages:
#
#   PLAYERS   players and the biggest crowd; data going out, and the month it
#             adds up to at this week's rate; whether one area needs sending
#             only what is near yet
#   MACHINE   the tick; the machine's load, memory and disk; the slowest
#             routes
#   RECEIPTS  "Kills need the server's count": the week's kills put to the
#             server's own count (killwatch.py's), a verdict - ready or what
#             it is waiting for - and the switch itself, beside it
#
# Built like the Economy tab (economytab.gd): made in code, read when the
# panel opens, on Refresh and every REFRESH_SECONDS while it is on screen;
# what Refresh read and what the switch did go in the panel's Results box
# too (`report`). NARROW AND SHORT: three pages that take turns, nothing
# scrolls. The switch is the Testing tab's too - one switch, two places, both
# showing what the server holds (OwnerPanel._refresh_receipts()).
extends VBoxContainer
class_name HealthTab


const PATH := "/api/server/health"
const SAY_GOOD := Color(0.55, 0.86, 0.6)
const SAY_BAD := Color(0.95, 0.55, 0.5)
const SAY_WARN := Color(0.95, 0.82, 0.5)
const SAY_NOTE := Color(0.78, 0.82, 0.87)
const HEAD := Color(0.93, 0.73, 0.3)
# The GM panel's inside width, near enough (the World tab's).
const WIDTH := 250.0
const PAGES := [["players", "Players"], ["machine", "Machine"], ["receipts", "Receipts"]]
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
var as_of_label: Label
# Players.
var players_label: Label
var data_label: Label
var month_label: Label
var nearby_label: Label
# Machine.
var tick_label: Label
var machine_label: Label
var routes_label: Label
# Receipts.
var verdict_label: Label
var detail_label: Label
var receipts_switch: CheckButton
var build_label: Label
var say_label: Label
var timer: Timer
var _busy: bool = false


func _init() -> void:
	name = "health"
	add_theme_constant_override("separation", 6)
	_build()


func _build() -> void:
	var strip := HBoxContainer.new()
	strip.name = "pages"
	strip.add_theme_constant_override("separation", 4)
	add_child(strip)
	var group := ButtonGroup.new()
	for spec in PAGES:
		var button := _button(str(spec[1]), "")
		button.name = str(spec[0])
		button.toggle_mode = true
		button.button_group = group
		button.add_theme_font_size_override("font_size", 14)
		button.pressed.connect(show_page.bind(str(spec[0])))
		strip.add_child(button)
		page_buttons[spec[0]] = button
	refresh_button = _button("Refresh", "Read the server's health again - the kill receipts too, fresh.")
	refresh_button.name = "refresh"
	refresh_button.add_theme_font_size_override("font_size", 14)
	refresh_button.pressed.connect(refresh.bind(true))
	strip.add_child(refresh_button)
	as_of_label = _label("Not read yet.", SAY_NOTE, false)
	as_of_label.name = "asof"
	as_of_label.add_theme_font_size_override("font_size", 12)
	add_child(as_of_label)

	# ---- PLAYERS ---------------------------------------------------------------
	var players_page := _page("players")
	players_page.add_child(_head("Players"))
	players_label = _line("players")
	players_page.add_child(players_label)
	players_page.add_child(_head("Data going out"))
	data_label = _line("data")
	players_page.add_child(data_label)
	month_label = _line("month")
	players_page.add_child(month_label)
	nearby_label = _line("nearby")
	players_page.add_child(nearby_label)

	# ---- MACHINE ---------------------------------------------------------------
	var machine_page := _page("machine")
	machine_page.add_child(_head("The tick"))
	tick_label = _line("tick")
	machine_page.add_child(tick_label)
	machine_page.add_child(_head("The machine"))
	machine_label = _line("machine")
	machine_page.add_child(machine_label)
	machine_page.add_child(_head("Slowest routes"))
	routes_label = _line("routes")
	machine_page.add_child(routes_label)

	# ---- RECEIPTS --------------------------------------------------------------
	var receipts_page := _page("receipts")
	receipts_page.add_child(_head("The kill receipts, this week"))
	verdict_label = _label("Not read yet.", SAY_NOTE)
	verdict_label.name = "verdict"
	receipts_page.add_child(verdict_label)
	detail_label = _line("detail")
	receipts_page.add_child(detail_label)
	receipts_switch = CheckButton.new()
	receipts_switch.name = "receiptsswitch"
	receipts_switch.text = "Kills need the server's count"
	receipts_switch.focus_mode = Control.FOCUS_NONE
	receipts_switch.tooltip_text = "On: a kill is paid only when the server's own count of the fight agrees. The same switch as on the Testing tab. Off again is one click, and safe at any time."
	receipts_switch.disabled = true
	receipts_switch.toggled.connect(_on_switch_toggled)
	receipts_page.add_child(receipts_switch)
	build_label = _line("build")
	receipts_page.add_child(build_label)

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
	var label := _label(text, HEAD, false)
	label.add_theme_font_size_override("font_size", 13)
	return label


func _line(line_name: String) -> Label:
	var label := _label("", SAY_NOTE)
	label.name = line_name
	label.add_theme_font_size_override("font_size", 12)
	return label


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
	if by_hand:
		_say("Read from the server.", SAY_GOOD, "Read from the server. %s %s %s" % [
			players_text(answer), month_text(answer.get("month")), verdict_text(answer.get("receipts", {}))])
	elif say_label.text.begins_with("Could not reach") or say_label.text.begins_with("This server"):
		_say_here("")


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
	as_of_label.text = "Read at %s. Every half minute while it is open." % LocalTime.clock(now) if now > 0 else ""
	var presence: Dictionary = _dict(data.get("presence"))
	players_label.text = players_text(data)
	players_label.add_theme_color_override("font_color",
		SAY_NOTE if bool(presence.get("reporting", false)) else SAY_BAD)
	data_label.text = data_text(data)
	var month: Variant = data.get("month")
	month_label.text = month_text(month)
	month_label.add_theme_color_override("font_color", share_colour(month))
	var crowd: Dictionary = _dict(data.get("crowd"))
	nearby_label.text = nearby_text(crowd)
	nearby_label.add_theme_color_override("font_color",
		{"now": SAY_BAD, "watch": SAY_WARN, "fine": SAY_GOOD}.get(str(crowd.get("verdict", "")), SAY_NOTE))
	var tick: Dictionary = _dict(data.get("tick"))
	tick_label.text = tick_text(tick)
	tick_label.add_theme_color_override("font_color",
		{"steady": SAY_GOOD, "late": SAY_WARN}.get(str(tick.get("verdict", "")), SAY_NOTE))
	machine_label.text = machine_text(_dict(data.get("machine")))
	routes_label.text = routes_text(_dict(data.get("routes")))
	var receipts: Dictionary = _dict(data.get("receipts"))
	verdict_label.text = verdict_text(receipts)
	verdict_label.add_theme_color_override("font_color", verdict_colour(receipts))
	detail_label.text = detail_text(receipts)
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


static func share_colour(month: Variant) -> Color:
	if not (month is Dictionary):
		return SAY_NOTE
	var share: float = float((month as Dictionary).get("share", 0.0))
	return SAY_BAD if share >= 1.0 else (SAY_WARN if share >= 0.5 else SAY_GOOD)


static func nearby_text(crowd: Dictionary) -> String:
	"""Whether one area needs sending only the players near each game yet."""
	match str(crowd.get("verdict", "")):
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


static func build_text(receipts: Dictionary) -> String:
	"""Said only while it matters: ready or on, with the oldest build allowed
	in still below the receipts' own."""
	var verdict: String = str(receipts.get("verdict", ""))
	if not bool(receipts.get("min_build_low", false)) or verdict not in ["ready", "on"]:
		return ""
	return "Set Old versions must update to %d first (the Server tab): an older game cannot wait for the count." % int(
		receipts.get("receipt_build", 7))
