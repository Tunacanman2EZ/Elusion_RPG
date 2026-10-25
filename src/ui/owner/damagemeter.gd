# damagemeter.gd - THE DAMAGE METER (game 0.81.0): how hard everyone in your
# area is really hitting, as the server counts it.
#
# THE OWNER, 25 Oct: "i need a way to measure all players dps maybe make a
# filter just for player damage testing that i can use in game".
#
# THE SERVER'S COUNT, NOT THIS GAME'S. A game sees its own hits, and the area's
# leader sees everybody's, but a follower never sees another follower's - so a
# meter made here would be right for some players and blank for the rest. The
# books on the presence server see every hit from every player (combatbook.py),
# and once a second presence.py sends an owner or co-owner who has the meter
# open the hits its room's books counted since the last report: who, what the
# books booked, what the game claimed, and whether a boss took it, with each
# dealer's name and the bounds the books hold that character to. Nobody else
# is sent anything, so it costs the data bill nothing while it is shut.
#
# WHAT IT SHOWS, a row a player, biggest total first: damage a second over the
# last five seconds and over the whole fight since Reset, the total, the
# biggest single hit, and what the server allows that character a second. A
# hit the books held down to its character's bounds is counted as booked and
# marked "held" in red - the number that says a build, or a client, is hitting
# past what the game's own arithmetic allows.
#
# THE FILTERS: everyone or just you; every monster or bosses only. Reset
# starts a fresh fight. A hit's time is when its report arrived, so the
# five-second window moves a second at a time.
#
# THE OWNER PANEL OPENS IT (Testing, "Damage meter"); the panel is the gate,
# and the server checks the role again. BUILT IN CODE, NO .tscn, like
# perfoverlay.gd; preloaded rather than a class_name, like webpage.gd, so a
# fresh checkout compiles it without an editor rescan.
extends CanvasLayer

# THE FIGHT LOG (0.82.0): every fight this meter hears, kept and compared.
const FightLog := preload("res://src/ui/owner/fightlog.gd")

const NODE_NAME := "DamageMeter"
# The short window, in seconds.
const RECENT_SECONDS := 5.0
# Hits kept for the short window; a report past it drops the oldest.
const RECENT_MOST := 6000
# Rows drawn; the rest are summed into the last line.
const ROWS_MOST := 12

const HEAD := Color(0.93, 0.73, 0.3)
const PLAIN := Color(0.84, 0.88, 0.93)
const DIM := Color(0.55, 0.6, 0.67)
const GOOD := Color(0.55, 0.86, 0.6)
const BAD := Color(0.95, 0.55, 0.5)

const COLUMNS := ["Player", "DPS now", "DPS fight", "Total", "Share", "Top hit", "Limit"]
const COLUMN_TIPS := [
	"Name, class and level. You are in green.",
	"Damage a second over the last 5 seconds.",
	"Damage a second since Reset.",
	"All damage since Reset.",
	"This player's part of everyone's damage.",
	"The biggest single hit.",
	"How much of the damage a second the server allows this character is being used.\nRed: hits the server held down to what the character can really do.",
]
# A row's bar, by class; anything else is grey.
const CLASS_COLOURS := {
	"warrior": Color(0.9, 0.45, 0.32),
	"mage": Color(0.42, 0.62, 1.0),
	"tank": Color(0.62, 0.74, 0.46),
	"healer": Color(0.95, 0.82, 0.4),
}
const OTHER_CLASS := Color(0.6, 0.62, 0.68)
const WARN := Color(0.96, 0.8, 0.4)
# Where the window was last dragged to, kept while the game runs.
static var last_position: Vector2 = Vector2(16, 120)

var state: Dictionary = fresh_state()
# user id -> [name, class, level, allowed a second, biggest allowed hit]
var who: Dictionary = {}
var just_me: bool = false
var boss_only: bool = false
var area: String = ""
var _heard_at: float = -1.0

var _panel: PanelContainer
var _status: Label
var _grid: GridContainer
var _who_pick: OptionButton
var _target_pick: OptionButton
var _dragging: bool = false
var _summary: Label
var _bars: Array = []
# THE FIGHT LOG: the fight being heard ({} between fights), the last
# FightLog.KEEP finished, newest first, and the ids picked to compare.
var fight: Dictionary = {}
var fights: Array = []
var picked: Array = []
# Where they are kept - the test runner points these elsewhere, so a test
# fight never lands in the owner's own log.
var log_path: String = FightLog.SAVE_PATH
var csv_folder: String = FightLog.FOLDER
var _now_page: VBoxContainer
var _fights_page: VBoxContainer
var _fights_scroll: ScrollContainer
var _now_tab: Button
var _fights_tab: Button
var _fight_list: VBoxContainer
var _compare: GridContainer
var _recording: Label
var _folder_button: Button
var _dot: ColorRect
# The Fights page's views (0.82.0): which is showing, and every number or
# only KEY_ROWS in the table.
var fights_view: String = "list"
var all_rows: bool = false
var _views: Dictionary = {}
var _view_buttons: Dictionary = {}
var _group_chart: Control
var _chart_legend: HFlowContainer
var _more_button: Button
var _empty_note: Label
# THE CHART'S EVENTS (0.82.0), and THE PLAYERS VIEW: which picked fight it
# shows (an index into picked_records(), -1 the newest).
var show_events: bool = false
# DAMAGE TAKEN on the Chart (0.83.0).
var show_taken: bool = false
var _taken_button: Button
var players_slot: int = -1
# ONE PLAYER ON THE CHART (0.82.0): the user id whose damage curve the Chart
# shows instead of the group's, across every picked fight; -1 for the group.
# Clicked from the Players view; the title says whose, and Group clears it.
var focus_player: int = -1
var focus_name: String = ""
var _title: Label
var _group_button: Button
var _events_button: Button
var _event_list: VBoxContainer
var _player_slots: HBoxContainer
var _player_grid: GridContainer
var _taken_grid: GridContainer
var _tick: float = 0.0


# ---- the arithmetic (static, for the test runner) ---------------------------

static func fresh_state() -> Dictionary:
	# "all" and "boss": user id -> [damage, biggest, held, first, last], since
	# Reset. "recent": [at, user id, booked, boss] for the short window.
	return {"all": {}, "boss": {}, "recent": []}


static func add_hits(into: Dictionary, hits: Array, now: float) -> void:
	"""A report's hits, [[user id, booked, claimed, boss], ...], counted at `now`."""
	var recent: Array = into["recent"]
	for hit in hits:
		if not (hit is Array) or (hit as Array).size() < 4:
			continue
		var id: int = int(hit[0])
		var booked: int = maxi(int(hit[1]), 0)
		var held: int = maxi(int(hit[2]) - booked, 0)
		var boss: bool = int(hit[3]) != 0
		_count(into["all"], id, booked, held, now)
		if boss:
			_count(into["boss"], id, booked, held, now)
		recent.append([now, id, booked, boss])
	while recent.size() > RECENT_MOST:
		recent.pop_front()
	while not recent.is_empty() and float(recent[0][0]) <= now - RECENT_SECONDS:
		recent.pop_front()


static func _count(totals: Dictionary, id: int, booked: int, held: int, now: float) -> void:
	var row: Array = totals.get(id, [0, 0, 0, now, now])
	row[0] = int(row[0]) + booked
	row[1] = maxi(int(row[1]), booked)
	row[2] = int(row[2]) + held
	row[4] = now
	totals[id] = row


static func rows(counted: Dictionary, names: Dictionary, now: float, me: int, only_me: bool,
		only_bosses: bool) -> Array:
	"""A row a player, biggest total first: {id, name, cls, lvl, dps5, dps,
	total, biggest, held, allowed}. A fight's length runs from its first
	report to its last, plus the second the first one covered."""
	var totals: Dictionary = counted["boss"] if only_bosses else counted["all"]
	var recent: Dictionary = {}
	for hit in counted["recent"]:
		if float(hit[0]) <= now - RECENT_SECONDS or (only_bosses and not bool(hit[3])):
			continue
		recent[int(hit[1])] = int(recent.get(int(hit[1]), 0)) + int(hit[2])
	var out: Array = []
	for id in totals:
		if only_me and int(id) != me:
			continue
		var t: Array = totals[id]
		var known: Array = names.get(int(id), [])
		var seconds: float = maxf(1.0, float(t[4]) - float(t[3]) + 1.0)
		out.append({
			"id": int(id),
			"name": str(known[0]) if known.size() > 0 and str(known[0]) != "" else "player %d" % int(id),
			"cls": str(known[1]) if known.size() > 1 else "",
			"lvl": int(known[2]) if known.size() > 2 else 0,
			"dps5": float(recent.get(int(id), 0)) / RECENT_SECONDS,
			"dps": float(t[0]) / seconds,
			"total": int(t[0]),
			"biggest": int(t[1]),
			"held": int(t[2]),
			"allowed": int(known[3]) if known.size() > 3 else 0,
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["total"]) > int(b["total"]) or (int(a["total"]) == int(b["total"]) and int(a["id"]) < int(b["id"])))
	return out


static func summary(counted: Dictionary, only_bosses: bool) -> Dictionary:
	"""The whole fight since Reset: {seconds, total, dps} - from the first
	report anyone hit in to the last, plus the second the first covered."""
	var totals: Dictionary = counted["boss"] if only_bosses else counted["all"]
	var total: int = 0
	var first: float = INF
	var last: float = -INF
	for id in totals:
		var t: Array = totals[id]
		total += int(t[0])
		first = minf(first, float(t[3]))
		last = maxf(last, float(t[4]))
	if totals.is_empty():
		return {"seconds": 0.0, "total": 0, "dps": 0.0}
	var seconds: float = maxf(1.0, last - first + 1.0)
	return {"seconds": seconds, "total": total, "dps": float(total) / seconds}


static func limit_share(row: Dictionary) -> float:
	"""The fight's DPS as a share of what the server allows, 0..; -1 unknown."""
	if int(row.get("allowed", 0)) <= 0:
		return -1.0
	return float(row["dps"]) / float(row["allowed"])


static func clock(seconds: float) -> String:
	var whole: int = int(seconds)
	return "%d:%02d" % [int(whole / 60.0), whole % 60]


static func as_text(all: Array, fight: Dictionary, where: String) -> String:
	"""The table as plain text, for Copy - one line a player, tab between."""
	var lines: Array = ["Damage meter - %s - fight %s, %s total, %s DPS" % [where if where != "" else "here",
		clock(float(fight["seconds"])), number(float(fight["total"])), number(float(fight["dps"]))]]
	lines.append("\t".join(PackedStringArray(COLUMNS)))
	for row in all:
		var total: float = maxf(1.0, float(fight["total"]))
		var limit: float = limit_share(row)
		lines.append("\t".join(PackedStringArray([
			"%s (%s %d)" % [row["name"], row["cls"], int(row["lvl"])],
			str(int(round(float(row["dps5"])))), str(int(round(float(row["dps"])))), str(int(row["total"])),
			"%d%%" % int(round(100.0 * float(row["total"]) / total)), str(int(row["biggest"])),
			("%d%%" % int(round(100.0 * limit))) if limit >= 0.0 else "-",
		])) + ("\theld %d" % int(row["held"]) if int(row["held"]) > 0 else ""))
	return "\n".join(PackedStringArray(lines))


static func number(value: float) -> String:
	"""12, 1.2k, 12.3k, 1.2M - short enough for a column."""
	var v: float = absf(value)
	if v >= 1000000.0:
		return "%.1fM" % (value / 1000000.0)
	if v >= 10000.0:
		return "%.1fk" % (value / 1000.0)
	if v >= 1000.0:
		return "%.2fk" % (value / 1000.0)
	return str(int(round(value)))


# ---- finding it ------------------------------------------------------------

static func shared(tree: SceneTree) -> CanvasLayer:
	"""The one meter, made the first time it is asked for. It sits on the root,
	so it stays open across areas."""
	var found: Node = tree.root.get_node_or_null(NODE_NAME)
	if found is CanvasLayer:
		return found as CanvasLayer
	var made: CanvasLayer = (load("res://src/ui/owner/damagemeter.gd") as GDScript).new() as CanvasLayer
	made.name = NODE_NAME
	tree.root.add_child(made)
	return made


# ---- the window --------------------------------------------------------------

func _init() -> void:
	layer = 90
	visible = false
	fights = FightLog.load_log()
	for record in fights.slice(0, FightLog.COMPARE_MOST):
		picked.append(int(record["id"]))
	_build()


func _ready() -> void:
	if not Presence.damage_meter.is_connected(_on_report):
		Presence.damage_meter.connect(_on_report)


func is_shown() -> bool:
	return visible


func set_shown(on: bool) -> void:
	if not on:
		# The server stops reporting to a shut meter: whatever was being heard
		# is as finished as it will get.
		close_fight()
	visible = on
	Presence.watch_damage(on)
	if on:
		_heard_at = -1.0
		_redraw()


func reset() -> void:
	close_fight()
	state = fresh_state()
	_redraw()


func close_fight() -> Dictionary:
	"""Finish the fight being heard, keep it and save it; the record, or {}."""
	var record: Dictionary = FightLog.finish(fight)
	fight = {}
	if record.is_empty():
		return record
	while fights.any(func(other: Dictionary) -> bool: return int(other["id"]) == int(record["id"])):
		record["id"] = int(record["id"]) + 1
	fights.push_front(record)
	fights = fights.slice(0, FightLog.KEEP)
	picked.push_front(int(record["id"]))
	picked = picked.slice(0, FightLog.COMPARE_MOST)
	FightLog.save_log(fights, log_path)
	var saved: String = "" if OS.has_feature("web") else FightLog.save_csv(record, csv_folder)
	if _status != null:
		_status.text = "Fight saved: %s, %s DPS%s." % [FightLog.clock(float(record["seconds"])),
			number(float(record["dps"])), "" if saved == "" else " - and as a spreadsheet in the fights folder"]
		_tick = -3.0
	_draw_fights()
	return record


func take_report(report: Dictionary, now: float) -> void:
	"""One report from the server ({"t": "dm"}), counted at `now` seconds."""
	area = str(report.get("a", ""))
	var dealers: Variant = report.get("who", {})
	if dealers is Dictionary:
		for key in dealers:
			if dealers[key] is Array:
				who[int(key)] = dealers[key]
	var hits: Variant = report.get("h", [])
	if hits is Array:
		add_hits(state, hits, now)
		var deaths: Variant = report.get("k", [])
		# DAMAGE TAKEN (0.83.0): being hit starts a fight and keeps it going,
		# like hitting; a heal or regen alone does neither.
		var hurt: bool = took_any(report)
		if not (hits as Array).is_empty() or (deaths is Array and not (deaths as Array).is_empty()) or hurt:
			if FightLog.quiet(fight, now):
				close_fight()
			if fight.is_empty() and (not (hits as Array).is_empty() or hurt):
				fight = FightLog.begin(now, Time.get_unix_time_from_system(), area)
			if not fight.is_empty():
				FightLog.add(fight, report, now)
	_heard_at = now
	_redraw()


static func took_any(report: Dictionary) -> bool:
	"""Whether anyone in the report's "tk" took damage."""
	var taken: Variant = report.get("tk", {})
	if taken is Dictionary:
		for key in taken:
			if taken[key] is Array and (taken[key] as Array).size() >= 1 and int(taken[key][0]) > 0:
				return true
	return false


func _on_report(report: Dictionary) -> void:
	take_report(report, Time.get_ticks_msec() / 1000.0)


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.name = "panel"
	_panel.position = last_position
	_panel.custom_minimum_size = Vector2(460, 0)
	# SOLID. At 0.88 whatever stood behind it - another window, the HUD - showed
	# through in patches and the numbers sat on two colours.
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.055, 0.065, 0.09, 0.97)
	box.border_color = Color(0.93, 0.73, 0.3, 0.7)
	box.set_border_width_all(1)
	box.set_corner_radius_all(4)
	box.set_content_margin_all(10)
	box.shadow_color = Color(0, 0, 0, 0.45)
	box.shadow_size = 6
	_panel.add_theme_stylebox_override("panel", box)
	add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_panel.add_child(column)

	var head := HBoxContainer.new()
	head.name = "head"
	head.mouse_filter = Control.MOUSE_FILTER_STOP
	head.mouse_default_cursor_shape = Control.CURSOR_MOVE
	head.tooltip_text = "Drag to move"
	head.gui_input.connect(_on_head_input)
	column.add_child(head)
	_title = Label.new()
	_title.name = "title"
	_title.text = TITLE
	_title.add_theme_color_override("font_color", HEAD)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.mouse_filter = Control.MOUSE_FILTER_PASS
	_title.clip_text = true
	head.add_child(_title)
	var pages := ButtonGroup.new()
	_now_tab = _tab("Now", pages, true)
	head.add_child(_now_tab)
	_fights_tab = _tab("Fights", pages, false)
	head.add_child(_fights_tab)
	var shut := Button.new()
	shut.name = "close"
	shut.text = "x"
	shut.flat = true
	shut.tooltip_text = "Close the meter"
	shut.pressed.connect(func() -> void: set_shown(false))
	head.add_child(shut)

	_now_page = VBoxContainer.new()
	_now_page.name = "now"
	_now_page.add_theme_constant_override("separation", 6)
	column.add_child(_now_page)
	# The Fights page scrolls once it is taller than most of the screen: ten
	# fights, a table and three charts are, in a big font.
	_fights_scroll = ScrollContainer.new()
	_fights_scroll.name = "fightsscroll"
	_fights_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_fights_scroll.visible = false
	column.add_child(_fights_scroll)
	_fights_page = VBoxContainer.new()
	_fights_page.name = "fights"
	_fights_page.add_theme_constant_override("separation", 6)
	_fights_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fights_scroll.add_child(_fights_page)

	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 6)
	_now_page.add_child(filters)
	_who_pick = OptionButton.new()
	_who_pick.name = "whopick"
	_who_pick.add_item("Everyone")
	_who_pick.add_item("Just me")
	_who_pick.item_selected.connect(_on_who_picked)
	filters.add_child(_who_pick)
	_target_pick = OptionButton.new()
	_target_pick.name = "targetpick"
	_target_pick.add_item("All monsters")
	_target_pick.add_item("Bosses only")
	_target_pick.item_selected.connect(_on_target_picked)
	filters.add_child(_target_pick)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filters.add_child(gap)
	var again := Button.new()
	again.name = "reset"
	again.text = "Reset"
	again.tooltip_text = "Start a fresh fight"
	again.pressed.connect(reset)
	filters.add_child(again)
	var copy := Button.new()
	copy.name = "copy"
	copy.text = "Copy"
	copy.tooltip_text = "Copy the table, to paste into notes or chat"
	copy.pressed.connect(_on_copy)
	filters.add_child(copy)

	_summary = Label.new()
	_summary.name = "summary"
	_summary.add_theme_color_override("font_color", PLAIN)
	_now_page.add_child(_summary)

	_grid = GridContainer.new()
	_grid.name = "rows"
	_grid.columns = COLUMNS.size()
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 3)
	# THE BARS are drawn on the grid itself, under its cells: one a row, as long
	# as that player's share of the top total, in its class's colour.
	# Redrawn once the grid has laid its cells out, so a bar sits on its row.
	_grid.draw.connect(_draw_bars)
	_grid.sort_children.connect(_grid.queue_redraw)
	_now_page.add_child(_grid)

	_status = Label.new()
	_status.name = "status"
	_status.add_theme_color_override("font_color", DIM)
	_now_page.add_child(_status)
	_build_fights()


func _tab(text: String, group: ButtonGroup, on: bool) -> Button:
	var tab := Button.new()
	tab.name = text.to_lower() + "tab"
	tab.text = text
	tab.toggle_mode = true
	tab.button_group = group
	tab.button_pressed = on
	tab.toggled.connect(_on_tab_toggled.bind(text.to_lower()))
	return tab


func _on_tab_toggled(pressed: bool, page: String) -> void:
	if pressed:
		show_page(page)


func show_page(page: String) -> void:
	_now_page.visible = page == "now"
	_fights_scroll.visible = page == "fights"
	if _now_tab != null:
		_now_tab.set_pressed_no_signal(page == "now")
		_fights_tab.set_pressed_no_signal(page == "fights")
	if page == "fights":
		_draw_fights()
	# Shrink back to fit the page now showing.
	_panel.reset_size()


func _fit_fights() -> void:
	"""The Fights page as tall as it needs, up to most of the screen."""
	if _fights_scroll == null or not is_inside_tree():
		return
	var want: float = _fights_page.get_combined_minimum_size().y
	var room: float = _panel.get_viewport_rect().size.y * 0.7
	_fights_scroll.custom_minimum_size.y = minf(want, room)
	_panel.reset_size()


func recording_text(now: float) -> String:
	if fight.is_empty():
		return "Idle - the next hit starts a fight"
	return "Recording %s - %s" % [FightLog.clock(float(fight["last"]) - float(fight["t0"]) + 1.0),
		str(fight["area"])]


# ---- the Fights page ----------------------------------------------------------
# Picked fights are shown OLDEST FIRST, as A, B and C, each in its own colour -
# its row in the list, its chart and its column in the table - so a change
# reads left to right, and every number after A says how far it moved from A.

const SLOT_COLOURS := [Color(0.95, 0.74, 0.32), Color(0.36, 0.8, 0.86), Color(0.76, 0.56, 0.96)]
const SLOT_NAMES := ["A", "B", "C"]
const CARD := Color(1, 1, 1, 0.04)
const CARD_HOVER := Color(1, 1, 1, 0.07)


static func card_style(fill: Color, edge: Color = Color(0, 0, 0, 0), edge_width: int = 0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.set_corner_radius_all(4)
	box.content_margin_left = 8 + edge_width
	box.content_margin_right = 8
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	if edge_width > 0:
		box.border_color = edge
		box.border_width_left = edge_width
	return box


# The rows the table shows until More: the numbers a tuning pass moves.
const KEY_ROWS := ["Length", "Group DPS", "Best 5 s", "Uptime", "Boss kill", "Held"]
const TITLE := "Damage meter"
const VIEWS := ["list", "chart", "table", "players"]
# Events listed under the chart, at most.
const EVENTS_LISTED := 8


func _build_fights() -> void:
	# ONE VIEW AT A TIME (the owner: "its too big"): List, Chart or Table under
	# three buttons, so the page is never more than one of them tall.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	_fights_page.add_child(top)
	var pill := PanelContainer.new()
	pill.name = "pill"
	pill.add_theme_stylebox_override("panel", card_style(CARD))
	pill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pill.tooltip_text = "A fight starts with its first hit and ends after %d s with none, or on Reset." \
		% int(FightLog.QUIET_SECONDS)
	var pill_row := HBoxContainer.new()
	pill_row.add_theme_constant_override("separation", 8)
	pill.add_child(pill_row)
	_dot = ColorRect.new()
	_dot.name = "dot"
	_dot.custom_minimum_size = Vector2(8, 8)
	_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pill_row.add_child(_dot)
	_recording = Label.new()
	_recording.name = "recording"
	_recording.add_theme_color_override("font_color", PLAIN)
	_recording.clip_text = true
	_recording.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pill_row.add_child(_recording)
	top.add_child(pill)
	var copy := Button.new()
	copy.name = "copyfights"
	copy.text = "Copy"
	copy.tooltip_text = "Copy the fights you picked, every number, to paste into notes"
	copy.pressed.connect(_on_copy_fights)
	top.add_child(copy)
	_folder_button = Button.new()
	_folder_button.name = "folder"
	_folder_button.text = "Folder"
	_folder_button.tooltip_text = "Open the folder each fight is saved in as a spreadsheet (CSV)"
	_folder_button.visible = not OS.has_feature("web")
	_folder_button.pressed.connect(_open_folder)
	top.add_child(_folder_button)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	_fights_page.add_child(bar)
	var group := ButtonGroup.new()
	for view in VIEWS:
		var button := Button.new()
		button.name = "%sview" % view
		button.text = str(view).capitalize()
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size.x = 70
		button.toggled.connect(_on_view_toggled.bind(view))
		bar.add_child(button)
		_view_buttons[view] = button

	_fight_list = VBoxContainer.new()
	_fight_list.name = "list"
	_fight_list.add_theme_constant_override("separation", 3)
	_fights_page.add_child(_fight_list)
	_views["list"] = _fight_list

	var chart_view := VBoxContainer.new()
	chart_view.name = "chartpage"
	chart_view.add_theme_constant_override("separation", 6)
	_fights_page.add_child(chart_view)
	_views["chart"] = chart_view
	_events_button = Button.new()
	_events_button.name = "events"
	_events_button.text = "Events"
	_events_button.toggle_mode = true
	_events_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_events_button.tooltip_text = "Mark what changed each fight: ^ a boss grew, v shrank, + a player joined, - left, x fell"
	_events_button.toggled.connect(_on_events_toggled)
	var chart_bar := HBoxContainer.new()
	chart_bar.name = "chartbar"
	chart_bar.add_theme_constant_override("separation", 6)
	chart_bar.alignment = BoxContainer.ALIGNMENT_END
	chart_view.add_child(chart_bar)
	_group_button = Button.new()
	_group_button.name = "group"
	_group_button.text = "x  Group"
	_group_button.tooltip_text = "Back to the whole group's DPS"
	_group_button.pressed.connect(func() -> void: focus(-1, ""))
	chart_bar.add_child(_group_button)
	_taken_button = Button.new()
	_taken_button.name = "taken"
	_taken_button.text = "Taken"
	_taken_button.toggle_mode = true
	_taken_button.tooltip_text = "Damage taken, dashed. With one player picked: their healing dotted, and their health under the chart (red under %d%%)" \
		% int(round(100.0 * FightLog.DANGER_SHARE))
	_taken_button.toggled.connect(_on_taken_toggled)
	chart_bar.add_child(_taken_button)
	chart_bar.add_child(_events_button)
	_group_chart = FightLog.GroupChart.new()
	_group_chart.name = "groupchart"
	_group_chart.tooltip_text = "The whole group's DPS through each fight, smoothed over 5 s, on one clock.\nA dashed line: that fight's boss fell."
	chart_view.add_child(_group_chart)
	_chart_legend = HFlowContainer.new()
	_chart_legend.name = "legend"
	_chart_legend.add_theme_constant_override("h_separation", 14)
	chart_view.add_child(_chart_legend)
	_event_list = VBoxContainer.new()
	_event_list.name = "eventlist"
	_event_list.add_theme_constant_override("separation", 0)
	chart_view.add_child(_event_list)

	var players_view := VBoxContainer.new()
	players_view.name = "playerspage"
	players_view.add_theme_constant_override("separation", 6)
	_fights_page.add_child(players_view)
	_views["players"] = players_view
	_player_slots = HBoxContainer.new()
	_player_slots.name = "slots"
	_player_slots.add_theme_constant_override("separation", 4)
	players_view.add_child(_player_slots)
	_player_grid = GridContainer.new()
	_player_grid.name = "playergrid"
	_player_grid.columns = PLAYER_COLUMNS.size()
	_player_grid.add_theme_constant_override("h_separation", 14)
	_player_grid.add_theme_constant_override("v_separation", 2)
	players_view.add_child(_player_grid)
	_taken_grid = GridContainer.new()
	_taken_grid.name = "takengrid"
	_taken_grid.columns = TAKEN_COLUMNS.size()
	_taken_grid.add_theme_constant_override("h_separation", 14)
	_taken_grid.add_theme_constant_override("v_separation", 2)
	players_view.add_child(_taken_grid)

	var table_view := VBoxContainer.new()
	table_view.name = "tablepage"
	table_view.add_theme_constant_override("separation", 6)
	_fights_page.add_child(table_view)
	_views["table"] = table_view
	_compare = GridContainer.new()
	_compare.name = "compare"
	_compare.add_theme_constant_override("h_separation", 14)
	_compare.add_theme_constant_override("v_separation", 2)
	table_view.add_child(_compare)
	_more_button = Button.new()
	_more_button.name = "more"
	_more_button.flat = true
	_more_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_more_button.pressed.connect(_on_more)
	table_view.add_child(_more_button)

	_empty_note = Label.new()
	_empty_note.name = "empty"
	_empty_note.add_theme_color_override("font_color", DIM)
	_fights_page.add_child(_empty_note)
	show_view(fights_view)


func show_view(view: String) -> void:
	fights_view = view if VIEWS.has(view) else "list"
	for key in _views:
		(_views[key] as Control).visible = key == fights_view
	(_view_buttons[fights_view] as Button).set_pressed_no_signal(true)
	_draw_fights()


func _on_view_toggled(pressed: bool, view: String) -> void:
	if pressed:
		show_view(view)


func _on_taken_toggled(on: bool) -> void:
	show_taken = on
	_draw_fights()


func _on_events_toggled(on: bool) -> void:
	show_events = on
	_draw_fights()


func focus(id: int, named: String) -> void:
	"""Show one player's damage on the Chart (id -1: the group's again)."""
	focus_player = id
	focus_name = named if id >= 0 else ""
	_title.text = TITLE if id < 0 else "%s: %s" % [TITLE, focus_name]
	if id >= 0:
		show_view("chart")
	else:
		_draw_fights()


func _on_player_name_input(event: InputEvent, id: int, named: String) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		focus(-1 if focus_player == id else id, named)


func _on_player_slot(slot: int) -> void:
	players_slot = slot
	_draw_fights()


const PLAYER_COLUMNS := ["Player", "DPS", "Best 5 s", "Uptime", "Steady", "Elements"]
# DAMAGE TAKEN (0.83.0): a second table under the first - one row of fourteen
# ran off the screen.
const TAKEN_COLUMNS := ["Player", "Taken/s", "Biggest", "Healed", "Regen", "Lowest", "Danger", "Deaths", "Took"]
const PLAYER_TIPS := [
	"Name, class and level",
	"Damage a second over the whole fight",
	"The best five seconds",
	"The share of their own time in the fight - first hit to last - they were dealing damage. Low: dodging, walking, waiting.",
	"How evenly the damage came. 100%: the same every second. Low: a few big seconds - burst, or luck.",
	"Their damage by element, after the target's resistance",
]
const TAKEN_TIPS := [
	"Name, class and level",
	"Damage they took a second over the whole fight, after their armour and resistance",
	"The biggest single hit they took",
	"Health heals gave them back - potions, the healer - only what was missing",
	"Health their slow regeneration gave back",
	"Their lowest health in the fight",
	"Seconds they spent under %d%% health" % int(round(100.0 * FightLog.DANGER_SHARE)),
	"How many times they fell",
	"What they took by element, after their resistance",
]


func _draw_players(chosen: Array) -> void:
	for holder in [_player_slots, _player_grid, _taken_grid]:
		for child in (holder as Node).get_children():
			(holder as Node).remove_child(child)
			child.queue_free()
	if chosen.is_empty():
		return
	var slot: int = chosen.size() - 1 if players_slot < 0 or players_slot >= chosen.size() else players_slot
	var group := ButtonGroup.new()
	for i in chosen.size():
		var button := Button.new()
		button.text = "%s  %s %s" % [SLOT_NAMES[i], str(chosen[i]["area"]), FightLog.clock(float(chosen[i]["seconds"]))]
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = i == slot
		button.add_theme_color_override("font_color", SLOT_COLOURS[i])
		button.add_theme_color_override("font_pressed_color", SLOT_COLOURS[i])
		button.pressed.connect(_on_player_slot.bind(i))
		_player_slots.add_child(button)
	for i in PLAYER_COLUMNS.size():
		_player_grid.add_child(_compare_cell(PLAYER_COLUMNS[i], HEAD))
		(_player_grid.get_child(_player_grid.get_child_count() - 1) as Control).tooltip_text = PLAYER_TIPS[i]
	for i in TAKEN_COLUMNS.size():
		_taken_grid.add_child(_compare_cell(TAKEN_COLUMNS[i], HEAD))
		(_taken_grid.get_child(_taken_grid.get_child_count() - 1) as Control).tooltip_text = TAKEN_TIPS[i]
	var stripe: bool = false
	for p in chosen[slot]["players"]:
		stripe = not stripe
		var tint: Color = Color(1, 1, 1, 0.03) if stripe else Color(0, 0, 0, 0)
		var named: String = str(p["name"]) if str(p["cls"]) == "" else "%s (%s %d)" % [str(p["name"]), str(p["cls"]), int(p["lvl"])]
		var focused: bool = int(p["id"]) == focus_player
		var name_cell: Control = _compare_cell(("> " if focused else "") + named,
			CLASS_COLOURS.get(str(p["cls"]), OTHER_CLASS), "", Color(1, 1, 1, 0.09) if focused else tint)
		name_cell.mouse_filter = Control.MOUSE_FILTER_STOP
		name_cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		name_cell.tooltip_text = "Click to see only %s's damage on the Chart" % str(p["name"])
		name_cell.gui_input.connect(_on_player_name_input.bind(int(p["id"]), str(p["name"])))
		_player_grid.add_child(name_cell)
		_player_grid.add_child(_compare_cell(number(float(p["dps"])), PLAIN, "", tint))
		_player_grid.add_child(_compare_cell(number(float(p["peak"])), PLAIN, "", tint))
		var up: float = float(p.get("uptime", 0.0))
		_player_grid.add_child(_compare_cell("%d%%" % int(round(100.0 * up)), GOOD if up >= 0.85 else (WARN if up >= 0.6 else BAD), "", tint))
		var steady: float = float(p.get("steady", 0.0))
		_player_grid.add_child(_compare_cell("%d%%" % int(round(100.0 * steady)), GOOD if steady >= 0.75 else (WARN if steady >= 0.55 else BAD), "", tint))
		var cell := PanelContainer.new()
		cell.add_theme_stylebox_override("panel", card_style(tint))
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		cell.add_child(line)
		for pair in (p.get("elements", []) as Array).slice(0, 3):
			var part := Label.new()
			part.text = "%s %d%%" % [FightLog.element_name(int(pair[0])),
				int(round(100.0 * float(pair[1]) / maxf(1.0, float(p["total"]))))]
			part.add_theme_color_override("font_color", Element.colour_for(int(pair[0])) if int(pair[0]) >= 0 else DIM)
			line.add_child(part)
		_player_grid.add_child(cell)
		var taken_name: Control = _compare_cell(("> " if focused else "") + named,
			CLASS_COLOURS.get(str(p["cls"]), OTHER_CLASS), "", Color(1, 1, 1, 0.09) if focused else tint)
		taken_name.mouse_filter = Control.MOUSE_FILTER_STOP
		taken_name.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		taken_name.tooltip_text = name_cell.tooltip_text
		taken_name.gui_input.connect(_on_player_name_input.bind(int(p["id"]), str(p["name"])))
		_taken_grid.add_child(taken_name)
		_add_taken_cells(p, tint)


func _add_taken_cells(p: Dictionary, tint: Color) -> void:
	"""DAMAGE TAKEN (0.83.0): the rest of a player's row. "-" for a fight from
	before it was kept."""
	if not p.has("taken"):
		for i in 8:
			_taken_grid.add_child(_compare_cell("-", DIM, "", tint))
		return
	_taken_grid.add_child(_compare_cell(number(float(p["taken_ps"])), PLAIN, "", tint))
	_taken_grid.add_child(_compare_cell(number(float(p["biggest_taken"])), PLAIN, "", tint))
	_taken_grid.add_child(_compare_cell(number(float(p["healed"])), PLAIN, "", tint))
	_taken_grid.add_child(_compare_cell(number(float(p["regen"])), PLAIN, "", tint))
	var lowest: float = float(p["lowest"])
	_taken_grid.add_child(_compare_cell("-" if lowest < 0.0 else "%d%%" % int(round(100.0 * lowest)),
		DIM if lowest < 0.0 else (BAD if lowest < FightLog.DANGER_SHARE else (WARN if lowest < 0.5 else GOOD)), "", tint))
	var danger: int = int(p["danger"])
	_taken_grid.add_child(_compare_cell("%d s" % danger, GOOD if danger == 0 else (WARN if danger <= 3 else BAD), "", tint))
	var deaths: int = int(p["deaths"])
	_taken_grid.add_child(_compare_cell(str(deaths), GOOD if deaths == 0 else BAD, "", tint))
	var cell := PanelContainer.new()
	cell.add_theme_stylebox_override("panel", card_style(tint))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	cell.add_child(line)
	for pair in (p.get("took", []) as Array).slice(0, 3):
		var part := Label.new()
		part.text = "%s %d%%" % [FightLog.element_name(int(pair[0])),
			int(round(100.0 * float(pair[1]) / maxf(1.0, float(p["taken"]))))]
		part.add_theme_color_override("font_color", Element.colour_for(int(pair[0])) if int(pair[0]) >= 0 else DIM)
		line.add_child(part)
	_taken_grid.add_child(cell)


func _on_more() -> void:
	all_rows = not all_rows
	_draw_fights()


func _open_folder() -> void:
	DirAccess.make_dir_recursive_absolute(csv_folder)
	OS.shell_open(ProjectSettings.globalize_path(csv_folder))


func picked_records() -> Array:
	"""The picked fights, OLDEST FIRST - A, B, C."""
	var out: Array = []
	for record in fights:
		if picked.has(int(record["id"])):
			out.append(record)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) < int(b["id"]))
	return out


func pick(id: int, on: bool) -> void:
	picked.erase(id)
	if on:
		picked.push_front(id)
	picked = picked.slice(0, FightLog.COMPARE_MOST)
	_draw_fights()


func _on_copy_fights() -> void:
	var chosen: Array = picked_records()
	DisplayServer.clipboard_set(FightLog.compare_text(chosen))
	_recording.text = "Copied %d fight%s" % [chosen.size(), "" if chosen.size() == 1 else "s"]


func _slot_of(id: int, chosen: Array) -> int:
	for i in chosen.size():
		if int(chosen[i]["id"]) == id:
			return i
	return -1


func _fight_row(record: Dictionary, slot: int) -> PanelContainer:
	var on: bool = slot >= 0
	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.tooltip_text = "Click to %s" % ("take it out of the comparison" if on else "compare it")
	row.add_theme_stylebox_override("panel", card_style(Color(1, 1, 1, 0.075) if on else CARD,
		SLOT_COLOURS[slot] if on else Color(0, 0, 0, 0), 3 if on else 0))
	row.gui_input.connect(_on_row_input.bind(int(record["id"])))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)
	var boss: Dictionary = FightLog.boss_kill(record)
	var parts: Array = [
		[SLOT_NAMES[slot] if on else " ", SLOT_COLOURS[slot] if on else DIM, 14],
		[str(record["when"]).substr(5, 11), DIM, 0],
		[str(record["area"]), PLAIN, 0],
		[FightLog.clock(float(record["seconds"])), PLAIN, 0],
		["%s DPS" % number(float(record["dps"])), GOOD, 0],
		["" if boss.is_empty() else "%s %s" % [str(boss["name"]), FightLog.clock(float(boss["seconds"]))], HEAD, 0],
	]
	for part in parts:
		var label := Label.new()
		label.text = str(part[0])
		label.add_theme_color_override("font_color", part[1])
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if int(part[2]) > 0:
			label.custom_minimum_size.x = int(part[2])
		line.add_child(label)
	return row


func _on_row_input(event: InputEvent, id: int) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		pick(id, not picked.has(id))


func _compare_cell(text: String, colour: Color, delta: String = "", tint: Color = Color(0, 0, 0, 0),
		trend: int = 0) -> Control:
	var holder := PanelContainer.new()
	holder.add_theme_stylebox_override("panel", card_style(tint))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	holder.add_child(line)
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", colour)
	line.add_child(label)
	if delta != "":
		var change := Label.new()
		change.text = delta
		change.add_theme_color_override("font_color", GOOD if trend > 0 else (BAD if trend < 0 else DIM))
		line.add_child(change)
	return holder


func _legend_item(text: String, colour: Color, swatch_colour: Color) -> HBoxContainer:
	var item := HBoxContainer.new()
	item.add_theme_constant_override("separation", 5)
	var swatch := ColorRect.new()
	swatch.color = swatch_colour
	swatch.custom_minimum_size = Vector2(12, 3)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	item.add_child(swatch)
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", colour)
	item.add_child(label)
	return item


func _draw_fights() -> void:
	if _fight_list == null:
		return
	_recording.text = recording_text(Time.get_ticks_msec() / 1000.0)
	_dot.color = BAD if not fight.is_empty() else DIM
	for holder in [_fight_list, _compare, _chart_legend, _event_list]:
		for child in (holder as Node).get_children():
			(holder as Node).remove_child(child)
			child.queue_free()
	var chosen: Array = picked_records()
	_empty_note.visible = fights.is_empty() or (fights_view != "list" and chosen.is_empty())
	if fights.is_empty():
		_empty_note.text = "No fights yet. Fight with the meter open and each one is kept here."
	elif chosen.is_empty():
		_empty_note.text = "Pick fights in List to see them here."
	for record in fights:
		_fight_list.add_child(_fight_row(record, _slot_of(int(record["id"]), chosen)))
	(_views["chart"] as Control).visible = fights_view == "chart" and not chosen.is_empty()
	(_views["table"] as Control).visible = fights_view == "table" and not chosen.is_empty()
	(_views["players"] as Control).visible = fights_view == "players" and not chosen.is_empty()
	_draw_players(chosen)
	_group_chart.set("show_events", show_events)
	_events_button.set_pressed_no_signal(show_events)
	if show_events:
		var listed: int = 0
		for i in chosen.size():
			for e in chosen[i].get("events", []):
				if listed >= EVENTS_LISTED:
					break
				var line := Label.new()
				line.text = "%s %s  %s %s" % [SLOT_NAMES[i], FightLog.clock(float(e["at"])),
					str(FightLog.GroupChart.MARKS.get(str(e["kind"]), "*")), str(e["text"])]
				line.add_theme_color_override("font_color", SLOT_COLOURS[i])
				_event_list.add_child(line)
				listed += 1
		if listed == 0:
			var none := Label.new()
			none.text = "Nothing changed in these fights: no boss grew, nobody joined, left or fell."
			none.add_theme_color_override("font_color", DIM)
			_event_list.add_child(none)
	var colours: Array = SLOT_COLOURS.slice(0, chosen.size())
	var lines: Array = []
	for record in chosen:
		lines.append(FightLog.group_line(record) if focus_player < 0 else FightLog.player_line(record, focus_player))
	_group_chart.set_records(chosen, colours, lines)
	# DAMAGE TAKEN (0.83.0): the group's taken alone; one player's taken,
	# healing and health.
	var taken: Array = []
	var healed: Array = []
	var health: Array = []
	for record in chosen:
		taken.append(FightLog.taken_line(record, focus_player))
		healed.append(FightLog.heal_line(record, focus_player) if focus_player >= 0 else [])
		health.append(((record.get("health_timeline", {}) as Dictionary).get(str(focus_player), []))
			if focus_player >= 0 else [])
	_group_chart.call("set_taken", show_taken, taken, healed, health)
	_taken_button.set_pressed_no_signal(show_taken)
	_group_button.visible = focus_player >= 0
	_group_chart.tooltip_text = ("The whole group's DPS" if focus_player < 0 else "%s's DPS" % focus_name) \
		+ " through each fight, smoothed over 5 s, on one clock.\nA dashed line: that fight's boss fell."
	for i in chosen.size():
		var record: Dictionary = chosen[i]
		var boss: Dictionary = FightLog.boss_kill(record)
		var text: String = ""
		if focus_player < 0:
			text = "%s  %s %s  %s DPS" % [SLOT_NAMES[i], str(record["area"]),
				FightLog.clock(float(record["seconds"])), number(float(record["dps"]))]
			if not boss.is_empty():
				text += "  boss %s" % FightLog.clock(float(boss["seconds"]))
		else:
			var row: Dictionary = FightLog.player_in(record, focus_player)
			if row.is_empty():
				text = "%s  %s %s  - not in this fight" % [SLOT_NAMES[i], str(record["area"]),
					FightLog.clock(float(record["seconds"]))]
			else:
				text = "%s  %s %s  %s %d  %s DPS  best %s  uptime %d%%" % [SLOT_NAMES[i], str(record["area"]),
					FightLog.clock(float(record["seconds"])), str(row["cls"]), int(row["lvl"]), number(float(row["dps"])),
					number(float(row["peak"])), int(round(100.0 * float(row.get("uptime", 0.0))))]
		_chart_legend.add_child(_legend_item(text, SLOT_COLOURS[i], SLOT_COLOURS[i]))
	if show_taken and not chosen.is_empty():
		var key := Label.new()
		key.text = ("solid dealt, dashed taken" if focus_player < 0
			else "solid dealt, dashed taken, dotted healed; the strip is health, red under %d%%"
				% int(round(100.0 * FightLog.DANGER_SHARE)))
		if chosen.all(func(r: Dictionary) -> bool: return not r.has("taken_timeline")):
			key.text = "These fights are from before damage taken was kept."
		key.add_theme_color_override("font_color", DIM)
		_chart_legend.add_child(key)
	if not chosen.is_empty():
		_compare.columns = 1 + chosen.size()
		_compare.add_child(_compare_cell("", DIM))
		for i in chosen.size():
			_compare.add_child(_compare_cell("%s  %s" % [SLOT_NAMES[i], str(chosen[i]["when"]).substr(5, 11)],
				SLOT_COLOURS[i]))
		var stripe: bool = false
		for row in FightLog.compare_cells(chosen):
			if str(row[0]) == "Fought" or (not all_rows and not KEY_ROWS.has(str(row[0]))):
				continue
			stripe = not stripe
			var tint: Color = Color(1, 1, 1, 0.03) if stripe else Color(0, 0, 0, 0)
			_compare.add_child(_compare_cell(str(row[0]), HEAD, "", tint))
			for cell in row[1]:
				var best: bool = bool(cell["best"])
				_compare.add_child(_compare_cell(str(cell["text"]), GOOD if best else PLAIN, str(cell["delta"]),
					Color(0.55, 0.86, 0.6, 0.12) if best else tint, int(cell["trend"])))
	_more_button.text = "Fewer rows" if all_rows else "More rows"
	_fit_fights.call_deferred()


func _on_who_picked(index: int) -> void:
	just_me = index == 1
	_redraw()


func _on_target_picked(index: int) -> void:
	boss_only = index == 1
	_redraw()


func _on_copy() -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	var all: Array = rows(state, who, now, Presence.my_id(), just_me, boss_only)
	DisplayServer.clipboard_set(as_text(all, summary(state, boss_only), area))
	_status.text = "Copied %d row%s." % [all.size(), "" if all.size() == 1 else "s"]
	_tick = -2.0


func _process(delta: float) -> void:
	# The status line ages between reports ("No word from the server..."); the
	# rows only change when one arrives.
	_tick += delta
	if _tick >= 1.0 and _status != null:
		_tick = 0.0
		var now: float = Time.get_ticks_msec() / 1000.0
		if FightLog.quiet(fight, now):
			close_fight()
		else:
			_status.text = status_text(now)
		if _recording != null:
			_recording.text = recording_text(now)
			_dot.color = BAD if not fight.is_empty() else DIM


func _on_head_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_dragging = (event as InputEventMouseButton).pressed
	elif event is InputEventMouseMotion and _dragging:
		var view: Vector2 = _panel.get_viewport_rect().size
		_panel.position = (_panel.position + (event as InputEventMouseMotion).relative).clamp(
			Vector2.ZERO, (view - _panel.size).max(Vector2.ZERO))
		last_position = _panel.position


func status_text(now: float) -> String:
	if not Presence.books():
		return "The server is not counting hits right now."
	if _heard_at < 0.0:
		return "Waiting for the server..."
	if now - _heard_at > 3.0:
		return "No word from the server for %d s." % int(now - _heard_at)
	return "Live in %s - counted by the server." % (area if area != "" else "this area")


func _redraw() -> void:
	if _grid == null:
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	_status.text = status_text(now)
	var fight: Dictionary = summary(state, boss_only)
	_summary.text = "Fight %s    %s total    %s DPS%s" % [clock(float(fight["seconds"])),
		number(float(fight["total"])), number(float(fight["dps"])), "    bosses only" if boss_only else ""]
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_bars.clear()
	for i in COLUMNS.size():
		_cell(COLUMNS[i], HEAD, COLUMN_TIPS[i])
	var all: Array = rows(state, who, now, Presence.my_id(), just_me, boss_only)
	if all.is_empty():
		_cell("No hits yet - hit a monster and it shows here.", DIM)
		for _i in COLUMNS.size() - 1:
			_cell("", DIM)
		_grid.queue_redraw()
		return
	var top: float = maxf(1.0, float(all[0]["total"]))
	var everyone: float = maxf(1.0, float(fight["total"]))
	var rest: Array = all.slice(ROWS_MOST)
	var line: int = 1
	for row in all.slice(0, ROWS_MOST):
		var mine: bool = int(row["id"]) == Presence.my_id()
		var named: String = str(row["name"])
		if str(row["cls"]) != "":
			named += " (%s %d)" % [str(row["cls"]), int(row["lvl"])]
		_bars.append([line, float(row["total"]) / top, CLASS_COLOURS.get(str(row["cls"]), OTHER_CLASS)])
		_cell(named, GOOD if mine else PLAIN)
		_cell(number(float(row["dps5"])), PLAIN)
		_cell(number(float(row["dps"])), PLAIN)
		_cell(number(float(row["total"])), PLAIN)
		_cell("%d%%" % int(round(100.0 * float(row["total"]) / everyone)), DIM)
		_cell(number(float(row["biggest"])), PLAIN)
		var limit: float = limit_share(row)
		if int(row["held"]) > 0:
			_cell("held %s" % number(float(row["held"])), BAD,
				"The server held %s of this player's damage down to what the character can really do." \
				% number(float(row["held"])))
		elif limit < 0.0:
			_cell("-", DIM)
		else:
			_cell("%d%%" % int(round(100.0 * limit)), BAD if limit > 1.0 else (WARN if limit >= 0.9 else GOOD),
				"%s of %s a second allowed" % [number(float(row["dps"])), number(float(row["allowed"]))])
		line += 1
	if not rest.is_empty():
		var total: int = 0
		for row in rest:
			total += int(row["total"])
		_cell("%d more" % rest.size(), DIM)
		for _i in 2:
			_cell("", DIM)
		_cell(number(float(total)), DIM)
		for _i in COLUMNS.size() - 4:
			_cell("", DIM)
	_grid.queue_redraw()


func _cell(text: String, colour: Color, tip: String = "") -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", colour)
	if tip != "":
		label.tooltip_text = tip
		label.mouse_filter = Control.MOUSE_FILTER_STOP
	_grid.add_child(label)


func _draw_bars() -> void:
	var columns: int = _grid.columns
	for bar in _bars:
		var first: int = int(bar[0]) * columns
		if first >= _grid.get_child_count():
			continue
		var cell: Control = _grid.get_child(first) as Control
		var colour: Color = bar[2]
		var width: float = _grid.size.x * clampf(float(bar[1]), 0.0, 1.0)
		var rect := Rect2(Vector2(-4, cell.position.y - 1), Vector2(width + 8, cell.size.y + 2))
		_grid.draw_rect(Rect2(rect.position, Vector2(_grid.size.x + 8, rect.size.y)), Color(1, 1, 1, 0.03))
		_grid.draw_rect(rect, Color(colour.r, colour.g, colour.b, 0.28))
		_grid.draw_rect(Rect2(rect.position, Vector2(3, rect.size.y)), colour)
