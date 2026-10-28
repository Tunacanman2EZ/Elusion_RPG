# minigamescard.gd - the Minigames button's card: each minigame, your wait,
# and Go (0.93.3).
#
# The owner: "we need to get rid of ladder and make this a button in hud that
# says minigames this dungeon will have a 1 day wait timer for players", and
# the day starts when you press Go. So the town square's ladder down to the
# Endless is gone, and the bar's Minigames button opens this card above it:
#
#   The Endless
#   A horde that never stops. Once a day.
#   Ready  /  Back in 13h 20m  /  You are in it
#                                        [ Go ]  /  [ Leave ]
#
# THE WAIT IS THE SERVER'S (the API's minigames/): opening the card asks how
# long is left (GET /api/minigames), and Go asks first (POST
# /api/minigames/enter) - let in, it takes you to the Endless's corridor; a 409
# says how long is left, in the server's own words. Per account; the owner
# skips it. A party's members each press Go and land in the party's arena.
#
# AND THE WAY OUT. The Endless's door lets you in and not back (cryptdoor.gd
# one_way(), the owner: "the door needs to be 1 way entry also"), so inside the
# Endless the card's button is Leave, to town - from the arena as from the
# corridor, whose ladder still goes up. With loot in the chest (0.93.4) Leave
# asks twice: the chest waits on the server, and the next Go empties it.
#
# Built by the HUD (attach()), no class_name, so a fresh checkout needs no
# editor rescan.
extends PanelContainer

const COLOUR := Color(1.0, 0.86, 0.5)
const COLOUR_HINT := Color(0.82, 0.78, 0.7)
const COLOUR_READY := Color(0.6, 0.9, 0.55)
const COLOUR_WAIT := Color(1.0, 0.72, 0.4)
const FONT_SIZE := 14
const WIDTH := 300.0
const GAP := 6.0
const STATUS_WIDTH := 190.0
const GAME := "endless"
const ENTRANCE := "endless_entrance"
const TOWN := "elusion"
const BLURB := "A horde that never stops. Once a day."
const UNREACHABLE := "Could not reach the server - try again."

# The suite's doors: the two requests, where Go and Leave travel to, and which
# area this game is in.
var list_request: Callable = Callable(Api, "get_json")
var enter_request: Callable = Callable(Api, "post")
var travel: Callable = Callable(self, "_travel")
var area_now: Callable = Callable(AreaRegistry, "current_area_id")
# How many cells of the Endless's chest hold something (0.93.4): the chest in
# the corridor's own count (endlesschest.gd `used`). A seam for the suite.
var chest_count: Callable = Callable(self, "_chest_count")

var hud: Node = null
var title: Label = null
var game_name: Label = null
var blurb: Label = null
var status: Label = null
var go_button: Button = null
var close_button: Button = null
# Seconds of the wait left when the server last said, and when that was.
var ready_in: int = 0
var _said_at_msec: int = 0
var _known: bool = false
var _busy: bool = false
# The server did not answer (the listing or Go): said until it does, and Go
# may be pressed - the server decides at Go anyway.
var _failed: bool = false
# LEAVE WITH LOOT IN THE CHEST ASKS TWICE (0.93.4): the chest waits on the
# server until the next Go - which empties it - so leaving it is losing it.
# The first press says so; the second leaves. Opening the card again forgets.
var _leave_armed: bool = false


static func attach(on_hud: Node) -> Control:
	var card: Control = (load("res://src/ui/minigames/minigamescard.gd") as GDScript).new()
	card.name = "minigamescard"
	card.set("hud", on_hud)
	on_hud.add_child(card)
	return card


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(WIDTH, 0)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	add_child(column)
	var head := HBoxContainer.new()
	column.add_child(head)
	title = _label("title", "Minigames", 16, COLOUR)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	close_button = Button.new()
	close_button.name = "close"
	close_button.text = "×"
	close_button.flat = true
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(close)
	head.add_child(close_button)
	game_name = _label("game", "The Endless", FONT_SIZE, COLOUR)
	column.add_child(game_name)
	blurb = _label("blurb", BLURB, 12, COLOUR_HINT)
	column.add_child(blurb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	column.add_child(row)
	status = _label("status", "", FONT_SIZE, COLOUR_HINT)
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# A wrapping Label measures its height at its narrowest: without a width
	# of its own, the card's first opening stood 500 px tall.
	status.custom_minimum_size = Vector2(STATUS_WIDTH, 0)
	row.add_child(status)
	go_button = Button.new()
	go_button.name = "go"
	go_button.text = "Go"
	go_button.focus_mode = Control.FOCUS_NONE
	go_button.custom_minimum_size = Vector2(72, 28)
	go_button.pressed.connect(_on_go)
	row.add_child(go_button)


func _label(id: String, text: String, size: int, colour: Color) -> Label:
	var label := Label.new()
	label.name = id
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	return label


func _ready() -> void:
	# THE BAR'S LOOK: its theme and panel, as the trade card takes them.
	var nav: Control = hud.get_node_or_null("%navframe") as Control if hud != null else null
	if nav != null:
		theme = nav.theme
		var style: StyleBox = nav.get_theme_stylebox("panel")
		if style != null:
			add_theme_stylebox_override("panel", style)


# =============================================================================
# OPEN, CLOSE, AND WHAT IT SAYS
# =============================================================================

func toggle() -> void:
	if visible:
		close()
	else:
		open()


func close() -> bool:
	var was: bool = visible
	visible = false
	set_process(false)
	return was


func open() -> void:
	_leave_armed = false
	visible = true
	move_to_front()
	_known = false
	_failed = false
	paint()
	_place()
	set_process(true)
	if inside_endless():
		return
	var res: Dictionary = await list_request.call("/api/minigames", 6.0)
	if not is_instance_valid(self) or not visible:
		return
	take_listing(res)


func take_listing(res: Dictionary) -> void:
	"""The server's answer to GET /api/minigames: this card's minigame's wait."""
	_known = false
	if res.get("ok", false) and res.get("data") is Dictionary:
		for game in (res["data"] as Dictionary).get("games", []):
			if game is Dictionary and str(game.get("id", "")) == GAME:
				ready_in = maxi(0, int(game.get("ready_in", 0)))
				_said_at_msec = Time.get_ticks_msec()
				_known = true
	_failed = not _known
	paint()


func inside_endless() -> bool:
	return str(area_now.call()) == GAME


func left_now() -> int:
	"""Seconds of the wait still left, counted down from the server's word."""
	if not _known:
		return 0
	return maxi(0, ready_in - int((Time.get_ticks_msec() - _said_at_msec) / 1000))


static func wait_text(seconds: int) -> String:
	"""'Back in 13h 20m' - how the card says a wait (the server's words)."""
	if seconds < 60:
		return "Back in under a minute"
	var hours: int = seconds / 3600
	var minutes: int = (seconds % 3600) / 60
	if hours > 0 and minutes > 0:
		return "Back in %dh %dm" % [hours, minutes]
	if hours > 0:
		return "Back in %dh" % hours
	return "Back in %dm" % minutes


func paint() -> void:
	"""The status line and the button, from what is known now."""
	if inside_endless():
		var held: int = chest_held()
		if held > 0:
			status.text = "Your chest holds %d. Leave it and your next Go empties it." % held
			status.add_theme_color_override("font_color", COLOUR_WAIT)
		else:
			status.text = "You are in the Endless."
			status.add_theme_color_override("font_color", COLOUR_HINT)
		go_button.text = "Leave anyway" if _leave_armed and held > 0 else "Leave"
		go_button.tooltip_text = "Back up to town"
		go_button.disabled = _busy
		return
	go_button.text = "Go"
	go_button.tooltip_text = "Down to the Endless's corridor - your day starts now"
	var left: int = left_now()
	if left > 0:
		status.text = wait_text(left)
		status.add_theme_color_override("font_color", COLOUR_WAIT)
		go_button.disabled = true
	elif _failed:
		status.text = UNREACHABLE
		status.add_theme_color_override("font_color", COLOUR_WAIT)
		go_button.disabled = _busy
	elif _busy or not _known:
		status.text = "Asking the server..."
		status.add_theme_color_override("font_color", COLOUR_HINT)
		go_button.disabled = true
	else:
		status.text = "Ready"
		status.add_theme_color_override("font_color", COLOUR_READY)
		go_button.disabled = false


func _process(_delta: float) -> void:
	# The wait counts down while the card is open, once a frame is plenty.
	if _known and not inside_endless():
		var was: String = status.text
		paint()
		if status.text != was:
			_place()


func _place() -> void:
	"""Above the Minigames button, its right edge on the button's - as the
	bar's dropdowns stand (characterhud.gd nav_menu_position())."""
	if not is_inside_tree():
		return
	reset_size()
	var screen: Vector2 = get_viewport_rect().size
	var button: Control = hud.get_node_or_null("%minigamesbutton") as Control if hud != null else null
	var nav: Control = hud.get_node_or_null("%navframe") as Control if hud != null else null
	var anchor := Rect2(Vector2(screen.x / 2.0, screen.y - 48.0), Vector2.ZERO)
	if button != null and button.is_visible_in_tree():
		anchor = button.get_global_rect()
	elif nav != null:
		anchor = Rect2(nav.get_global_rect().position + Vector2(size.x, 0), Vector2.ZERO)
	var x: float = clampf(anchor.end.x - size.x, 0.0, maxf(0.0, screen.x - size.x))
	var y: float = maxf(0.0, anchor.position.y - size.y - GAP)
	position = Vector2(x, y).floor()


# =============================================================================
# GO AND LEAVE
# =============================================================================

func _on_go() -> void:
	if _busy:
		return
	if inside_endless():
		if chest_held() > 0 and not _leave_armed:
			_leave_armed = true
			paint()
			_place()
			return
		_leave_armed = false
		close()
		travel.call(TOWN, "")
		return
	_busy = true
	_failed = false
	paint()
	var res: Dictionary = await enter_request.call("/api/minigames/enter", {"game": GAME}, 6.0)
	if not is_instance_valid(self):
		return
	_busy = false
	if res.get("ok", false):
		close()
		travel.call(GAME, ENTRANCE)
		return
	var data: Dictionary = res.get("data", {}) if res.get("data") is Dictionary else {}
	if int(res.get("status", 0)) == 409:
		# THE SERVER'S DAY: how long it says, counted down from here.
		ready_in = maxi(0, int(data.get("ready_in", 0)))
		_said_at_msec = Time.get_ticks_msec()
		_known = true
		paint()
		return
	_failed = true
	paint()


func chest_held() -> int:
	return maxi(0, int(chest_count.call())) if chest_count.is_valid() else 0


func _chest_count() -> int:
	var chest: Node = get_tree().get_first_node_in_group(&"endless_chest") if is_inside_tree() else null
	return int(chest.get("used")) if chest != null and "used" in chest else 0


func _travel(area_id: String, spawn_id: String) -> void:
	GameState.next_spawn_id = spawn_id
	AreaRegistry.go_to(area_id)
