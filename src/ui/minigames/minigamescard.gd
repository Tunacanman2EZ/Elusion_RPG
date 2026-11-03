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
# THE HEALER'S RUN (0.98.0, healerrun.gd) is the card's second minigame: a
# shooter with the healer as the ship, played over the screen from town (Go
# elsewhere says "Play it from town."). Since 0.99.0 everyone's, three runs a
# day: Go asks the server (POST /api/minigames/enter, with the character's
# slot) and opens the run with its id and what it pays; the listing says how
# many runs are left today, or when the next one is.
#
# THE MAGE'S STAND (0.107.0, magestand.gd) is the third, the owner's alone
# while it is built (`shows_mage_stand`): Go, in town, opens it - it pays
# nothing, so nothing is asked of the server.
#
# THE DESCENT (0.112.0, descentrun.gd) is the fourth, the owner's alone while
# it is built (`shows_descent`): THE WARRIOR'S (the owner: "this will be the
# warriors decent", as the Healer's Run is the healer's and the Stand the
# mage's), a roguelike run down a crypt as your own warrior. Go, playing a
# warrior (`class_now`), travels there (its own area, as the Endless is) and
# asks the server nothing - step 1 pays nothing; inside it, the row's button
# is Leave, to town.
#
# WITH THE PARTY (0.105.0): in a party, with a server that seats the run a
# room per party (`healer_party`), Go opens the run's start panel without
# asking (`open_lobby`): the run of the day is asked for when everyone is
# ready and the count starts, so leaving while somebody is away costs nothing.
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
const HEALER_BLURB := "The healer, up a crypt path, shooting. Up to 20,000 gold a run, three runs a day."
const HEALER_GAME := "healerrun"
const FROM_TOWN := "Play it from town."
const STAND_BLURB := "The mage on the wall, raining meteors on the horde at the gate. Yours only while it is built."
const DESCENT_BLURB := "The warrior's: down a crypt room by room - pick a door, pick an upgrade, beat the keepers. Yours only while it is built."
const DESCENT_CLASS := "warrior"
const FOR_WARRIORS := "For warriors - play your warrior"
const DESCENT := "descent"
const DESCENT_ENTRANCE := "descent_entrance"

# The suite's doors: the two requests, where Go and Leave travel to, and which
# area this game is in.
var list_request: Callable = Callable(Api, "get_json")
var enter_request: Callable = Callable(Api, "post")
var travel: Callable = Callable(self, "_travel")
var area_now: Callable = Callable(AreaRegistry, "current_area_id")
# How many cells of the Endless's chest hold something (0.93.4): the chest in
# the corridor's own count (endlesschest.gd `used`). A seam for the suite.
var chest_count: Callable = Callable(self, "_chest_count")
# The Healer's Run's doors: who sees it (the owner, in step 1) and what Go does.
var shows_healer_run: Callable = Callable(self, "_shows_healer_run")
var open_run: Callable = Callable(self, "_open_run")
var healer_party: Callable = Callable(self, "_healer_party")
var open_lobby: Callable = Callable(self, "_open_lobby")
# The Mage's Stand's doors: who sees it (the owner, while it is built) and Go.
var shows_mage_stand: Callable = Callable(self, "_shows_mage_stand")
var open_stand: Callable = Callable(self, "_open_stand")
# The Descent's: who sees it (the owner, while it is built), and the class
# being played - it is the warrior's.
var shows_descent: Callable = Callable(self, "_shows_descent")
var class_now: Callable = Callable(CharacterData, "active_class_id")

var hud: Node = null
var title: Label = null
var game_name: Label = null
var blurb: Label = null
var status: Label = null
var go_button: Button = null
var close_button: Button = null
var healer_box: VBoxContainer = null
var healer_status: Label = null
var healer_go: Button = null
var stand_box: VBoxContainer = null
var stand_status: Label = null
var stand_go: Button = null
var descent_box: VBoxContainer = null
var descent_status: Label = null
var descent_go: Button = null
# The Healer's Run's runs left today, and the wait when none are, as the
# server said and when.
var healer_left: int = 3
var healer_wait: int = 0
var _healer_known: bool = false
var _healer_said_msec: int = 0
var _healer_busy: bool = false
var _healer_said: String = ""
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
	healer_box = VBoxContainer.new()
	healer_box.name = "healerrun"
	healer_box.add_theme_constant_override("separation", 4)
	column.add_child(healer_box)
	healer_box.add_child(HSeparator.new())
	healer_box.add_child(_label("healergame", "The Healer's Run", FONT_SIZE, COLOUR))
	var healer_blurb: Label = _label("healerblurb", HEALER_BLURB, 12, COLOUR_HINT)
	healer_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	healer_blurb.custom_minimum_size = Vector2(WIDTH - 20.0, 0)
	healer_box.add_child(healer_blurb)
	var healer_row := HBoxContainer.new()
	healer_row.add_theme_constant_override("separation", 10)
	healer_box.add_child(healer_row)
	healer_status = _label("healerstatus", "", FONT_SIZE, COLOUR_HINT)
	healer_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	healer_status.custom_minimum_size = Vector2(STATUS_WIDTH, 0)
	healer_row.add_child(healer_status)
	healer_go = Button.new()
	healer_go.name = "healergo"
	healer_go.text = "Go"
	healer_go.focus_mode = Control.FOCUS_NONE
	healer_go.custom_minimum_size = Vector2(72, 28)
	healer_go.pressed.connect(_on_healer_go)
	healer_row.add_child(healer_go)
	stand_box = VBoxContainer.new()
	stand_box.name = "magestand"
	stand_box.add_theme_constant_override("separation", 4)
	column.add_child(stand_box)
	stand_box.add_child(HSeparator.new())
	stand_box.add_child(_label("standgame", "The Mage's Stand", FONT_SIZE, COLOUR))
	var stand_blurb: Label = _label("standblurb", STAND_BLURB, 12, COLOUR_HINT)
	stand_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stand_blurb.custom_minimum_size = Vector2(WIDTH - 20.0, 0)
	stand_box.add_child(stand_blurb)
	var stand_row := HBoxContainer.new()
	stand_row.add_theme_constant_override("separation", 10)
	stand_box.add_child(stand_row)
	stand_status = _label("standstatus", "", FONT_SIZE, COLOUR_HINT)
	stand_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stand_status.custom_minimum_size = Vector2(STATUS_WIDTH, 0)
	stand_row.add_child(stand_status)
	stand_go = Button.new()
	stand_go.name = "standgo"
	stand_go.text = "Go"
	stand_go.focus_mode = Control.FOCUS_NONE
	stand_go.custom_minimum_size = Vector2(72, 28)
	stand_go.pressed.connect(_on_stand_go)
	stand_row.add_child(stand_go)
	descent_box = VBoxContainer.new()
	descent_box.name = "descent"
	descent_box.add_theme_constant_override("separation", 4)
	column.add_child(descent_box)
	descent_box.add_child(HSeparator.new())
	descent_box.add_child(_label("descentgame", "The Descent", FONT_SIZE, COLOUR))
	var descent_blurb: Label = _label("descentblurb", DESCENT_BLURB, 12, COLOUR_HINT)
	descent_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	descent_blurb.custom_minimum_size = Vector2(WIDTH - 20.0, 0)
	descent_box.add_child(descent_blurb)
	var descent_row := HBoxContainer.new()
	descent_row.add_theme_constant_override("separation", 10)
	descent_box.add_child(descent_row)
	descent_status = _label("descentstatus", "", FONT_SIZE, COLOUR_HINT)
	descent_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	descent_status.custom_minimum_size = Vector2(STATUS_WIDTH, 0)
	descent_row.add_child(descent_status)
	descent_go = Button.new()
	descent_go.name = "descentgo"
	descent_go.text = "Go"
	descent_go.focus_mode = Control.FOCUS_NONE
	descent_go.custom_minimum_size = Vector2(72, 28)
	descent_go.pressed.connect(_on_descent_go)
	descent_row.add_child(descent_go)


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
	_healer_said = ""
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
			if game is Dictionary and str(game.get("id", "")) == HEALER_GAME:
				healer_left = maxi(0, int(game.get("plays_left", 3)))
				healer_wait = maxi(0, int(game.get("ready_in", 0)))
				_healer_said_msec = Time.get_ticks_msec()
				_healer_known = true
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
	_paint_healer()
	_paint_stand()
	_paint_descent()
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


func _paint_healer() -> void:
	healer_box.visible = bool(shows_healer_run.call())
	var in_town: bool = str(area_now.call()) == TOWN
	var wait_left: int = maxi(0, healer_wait - int((Time.get_ticks_msec() - _healer_said_msec) / 1000)) \
		if _healer_known else 0
	var none_left: bool = _healer_known and healer_left <= 0 and wait_left > 0
	if _healer_said != "":
		healer_status.text = _healer_said
	elif not in_town:
		healer_status.text = FROM_TOWN
	elif none_left:
		healer_status.text = wait_text(wait_left)
	elif _healer_known:
		healer_status.text = "Ready - %d of 3 runs left today" % healer_left
	else:
		healer_status.text = "Ready"
	var go_on: bool = in_town and not none_left and not _healer_busy
	healer_status.add_theme_color_override("font_color", COLOUR_READY if go_on else (COLOUR_WAIT if none_left else COLOUR_HINT))
	healer_go.disabled = not go_on
	healer_go.tooltip_text = "Play the Healer's Run - your character waits in town" if in_town \
		else "Go back to town first"


func _on_healer_go() -> void:
	if str(area_now.call()) != TOWN or _healer_busy:
		paint()
		return
	if bool(healer_party.call()):
		# WITH THE PARTY: the start panel first; the run is asked for at the count.
		close()
		open_lobby.call()
		return
	_healer_busy = true
	_healer_said = "Asking the server..."
	paint()
	var res: Dictionary = await enter_request.call("/api/minigames/enter",
		{"game": HEALER_GAME, "slot": int(CharacterData.active_character_index)}, 6.0)
	_healer_busy = false
	_healer_said = ""
	if not is_instance_valid(self):
		return
	var data: Dictionary = res.get("data", {}) if res.get("data") is Dictionary else {}
	if res.get("ok", false) and data.has("run"):
		healer_left = maxi(0, int(data.get("plays_left", 0)))
		close()
		open_run.call(int(data["run"]), data.get("pays", {}) if data.get("pays") is Dictionary else {})
		return
	if int(res.get("status", 0)) == 409:
		healer_left = 0
		healer_wait = maxi(0, int(data.get("ready_in", 0)))
		_healer_said_msec = Time.get_ticks_msec()
		_healer_known = true
	else:
		_healer_said = UNREACHABLE
	paint()


func _shows_healer_run() -> bool:
	return true


func _paint_stand() -> void:
	stand_box.visible = bool(shows_mage_stand.call())
	var in_town: bool = str(area_now.call()) == TOWN
	stand_status.text = "Ready - no limit on meteors" if in_town else FROM_TOWN
	stand_status.add_theme_color_override("font_color", COLOUR_READY if in_town else COLOUR_HINT)
	stand_go.disabled = not in_town
	stand_go.tooltip_text = "Play the Mage's Stand - your character waits in town" if in_town \
		else "Go back to town first"


func _on_stand_go() -> void:
	if str(area_now.call()) != TOWN or not bool(shows_mage_stand.call()):
		paint()
		return
	close()
	open_stand.call()


func _paint_descent() -> void:
	descent_box.visible = bool(shows_descent.call())
	var inside: bool = str(area_now.call()) == DESCENT
	var warrior: bool = str(class_now.call()) == DESCENT_CLASS
	if inside:
		descent_status.text = "You are in the Descent."
	else:
		descent_status.text = "Ready - your warrior goes down" if warrior else FOR_WARRIORS
	descent_status.add_theme_color_override("font_color", COLOUR_READY if warrior and not inside else COLOUR_HINT)
	descent_go.text = "Leave" if inside else "Go"
	descent_go.disabled = not inside and not warrior
	descent_go.tooltip_text = "Back up to town" if inside else ("Down into the Descent - as you are, gear and all"
		if warrior else "The Descent is the warrior's")


func _on_descent_go() -> void:
	if not bool(shows_descent.call()):
		paint()
		return
	if str(area_now.call()) == DESCENT:
		close()
		travel.call(TOWN, "")
	elif str(class_now.call()) == DESCENT_CLASS:
		close()
		travel.call(DESCENT, DESCENT_ENTRANCE)
	else:
		paint()


func _shows_descent() -> bool:
	return bool(Api.is_owner)


func _shows_mage_stand() -> bool:
	return bool(Api.is_owner)


func _open_stand() -> void:
	(load("res://src/world/magestand/magestandscreen.gd") as GDScript).call("open", get_tree(), hud)


func _open_run(run_id: int = 0, what_it_pays: Dictionary = {}) -> void:
	(load("res://src/world/healerrun/healerrunscreen.gd") as GDScript).call("open", get_tree(), 0, run_id,
		what_it_pays, hud)


func _healer_party() -> bool:
	return Presence.healer_rooms() and Party.members.size() > 1


func _open_lobby() -> void:
	(load("res://src/world/healerrun/healerrunscreen.gd") as GDScript).call("open", get_tree(), 0, 0, {}, hud, true)


func chest_held() -> int:
	return maxi(0, int(chest_count.call())) if chest_count.is_valid() else 0


func _chest_count() -> int:
	var chest: Node = get_tree().get_first_node_in_group(&"endless_chest") if is_inside_tree() else null
	return int(chest.get("used")) if chest != null and "used" in chest else 0


func _travel(area_id: String, spawn_id: String) -> void:
	GameState.next_spawn_id = spawn_id
	AreaRegistry.go_to(area_id)
