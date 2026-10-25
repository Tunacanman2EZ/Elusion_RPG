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

const COLUMNS := ["Player", "DPS 5s", "DPS fight", "Total", "Biggest", "Allowed"]

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
	_build()


func _ready() -> void:
	if not Presence.damage_meter.is_connected(_on_report):
		Presence.damage_meter.connect(_on_report)


func is_shown() -> bool:
	return visible


func set_shown(on: bool) -> void:
	visible = on
	Presence.watch_damage(on)
	if on:
		_heard_at = -1.0
		_redraw()


func reset() -> void:
	state = fresh_state()
	_redraw()


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
	_heard_at = now
	_redraw()


func _on_report(report: Dictionary) -> void:
	take_report(report, Time.get_ticks_msec() / 1000.0)


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.name = "panel"
	_panel.position = Vector2(16, 120)
	_panel.custom_minimum_size = Vector2(430, 0)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.06, 0.07, 0.1, 0.88)
	box.border_color = Color(0.93, 0.73, 0.3, 0.55)
	box.set_border_width_all(1)
	box.set_content_margin_all(8)
	_panel.add_theme_stylebox_override("panel", box)
	add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_panel.add_child(column)

	var head := HBoxContainer.new()
	head.name = "head"
	head.mouse_filter = Control.MOUSE_FILTER_STOP
	head.mouse_default_cursor_shape = Control.CURSOR_MOVE
	head.gui_input.connect(_on_head_input)
	column.add_child(head)
	var title := Label.new()
	title.text = "Damage meter"
	title.add_theme_color_override("font_color", HEAD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_PASS
	head.add_child(title)
	var shut := Button.new()
	shut.name = "close"
	shut.text = "x"
	shut.tooltip_text = "Close the meter"
	shut.pressed.connect(func() -> void: set_shown(false))
	head.add_child(shut)

	var filters := HBoxContainer.new()
	column.add_child(filters)
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
	var again := Button.new()
	again.name = "reset"
	again.text = "Reset"
	again.tooltip_text = "Start a fresh fight"
	again.pressed.connect(reset)
	filters.add_child(again)

	_status = Label.new()
	_status.name = "status"
	_status.add_theme_color_override("font_color", DIM)
	column.add_child(_status)

	_grid = GridContainer.new()
	_grid.name = "rows"
	_grid.columns = COLUMNS.size()
	_grid.add_theme_constant_override("h_separation", 12)
	column.add_child(_grid)


func _on_who_picked(index: int) -> void:
	just_me = index == 1
	_redraw()


func _on_target_picked(index: int) -> void:
	boss_only = index == 1
	_redraw()


func _process(delta: float) -> void:
	# The status line ages between reports ("No word from the server..."); the
	# rows only change when one arrives.
	_tick += delta
	if _tick >= 1.0 and _status != null:
		_tick = 0.0
		_status.text = status_text(Time.get_ticks_msec() / 1000.0)


func _on_head_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_dragging = (event as InputEventMouseButton).pressed
	elif event is InputEventMouseMotion and _dragging:
		var view: Vector2 = _panel.get_viewport_rect().size
		_panel.position = (_panel.position + (event as InputEventMouseMotion).relative).clamp(
			Vector2.ZERO, (view - _panel.size).max(Vector2.ZERO))


func status_text(now: float) -> String:
	if not Presence.books():
		return "The server is not counting hits right now."
	if _heard_at < 0.0:
		return "Waiting for the server..."
	if now - _heard_at > 3.0:
		return "No word from the server for %d s." % int(now - _heard_at)
	return "Live - %s, counted by the server." % (area if area != "" else "this area")


func _redraw() -> void:
	if _grid == null:
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	_status.text = status_text(now)
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	for heading in COLUMNS:
		_cell(heading, HEAD)
	var all: Array = rows(state, who, now, Presence.my_id(), just_me, boss_only)
	if all.is_empty():
		_cell("No hits yet.", DIM)
		for _i in COLUMNS.size() - 1:
			_cell("", DIM)
		return
	var rest: Array = all.slice(ROWS_MOST)
	for row in all.slice(0, ROWS_MOST):
		var named: String = str(row["name"])
		if str(row["cls"]) != "":
			named += " (%s %d)" % [str(row["cls"]), int(row["lvl"])]
		_cell(named, GOOD if int(row["id"]) == Presence.my_id() else PLAIN)
		_cell(number(float(row["dps5"])), PLAIN)
		_cell(number(float(row["dps"])), PLAIN)
		_cell(number(float(row["total"])), PLAIN)
		_cell(number(float(row["biggest"])), PLAIN)
		if int(row["held"]) > 0:
			_cell("%s  held %s" % [number(float(row["allowed"])), number(float(row["held"]))], BAD)
		else:
			_cell(number(float(row["allowed"])) if int(row["allowed"]) > 0 else "-", DIM)
	if not rest.is_empty():
		var total: int = 0
		for row in rest:
			total += int(row["total"])
		_cell("%d more" % rest.size(), DIM)
		for _i in 2:
			_cell("", DIM)
		_cell(number(float(total)), DIM)
		for _i in 2:
			_cell("", DIM)


func _cell(text: String, colour: Color) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", colour)
	_grid.add_child(label)
