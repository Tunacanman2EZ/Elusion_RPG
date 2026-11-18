# pinballscreen.gd - THE BEHOLDER'S TABLE on screen (0.167.0): the table's
# own 3D world (pinballrun.gd) in a SubViewport drawn over everything, with
# Leave, and at the end the score with Again and Leave.
#
# Opened from the Minigames card (minigamescard.gd), in town, the owner's
# alone while it is built (TESTING): practice - it pays nothing yet and the
# server is not asked. The character stays standing where it was, still
# (open() holds it, close() lets it go), and the town is not drawn under it
# (cover()).
#
# THE CONTROLS:
#   - keys: Z, A, Left Shift or the left arrow - the left flippers (every
#     left flipper, on every floor); M, L, Right Shift or the right arrow -
#     the right ones. Space, Enter, S or the down arrow held - the plunger
#     pulls; let go and the ball goes as hard as it was pulled.
#   - a mouse: the left button the left flippers, the right button the
#     right; while a ball waits on the plunger, either button pulls it.
#   - a phone: a finger on the left half of the picture holds the left
#     flippers, on the right half the right ones, for as long as it stays
#     down; while a ball waits on the plunger, a finger anywhere pulls and
#     lifting it launches. Two thumbs, one a side. A browser's own mouse
#     events after a touch are ignored for TOUCH_QUIET_MS (as Crownfall).
#
# Leave: the button, or Escape twice while a game is on (once after it).
# Keys are kept from the rest of the game while it is up.
extends CanvasLayer

const RunScript := preload("res://src/world/pinball/pinballrun.gd")
const LAYER := 90
const VIEW := Vector2i(1280, 720)
const GOLD := Color(1.0, 0.82, 0.38)
const CREAM := Color(1.0, 0.95, 0.85)
const HINT := Color(0.82, 0.78, 0.7)
const PILL := Color(0.06, 0.05, 0.08, 0.86)
const LEAVE_BOX := Rect2(1176, 22, 82, 38)
const TOUCH_QUIET_MS := 800
const LEFT_KEYS := [KEY_Z, KEY_A, KEY_LEFT]
const RIGHT_KEYS := [KEY_M, KEY_L, KEY_RIGHT]
const PLUNGER_KEYS := [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_S, KEY_DOWN]
const KEYS_HINT := "Z / LEFT  ·  M / RIGHT  ·  HOLD SPACE TO LAUNCH"
const TOUCH_HINT := "LEFT HALF  ·  RIGHT HALF  ·  HOLD TO LAUNCH"

# the best score of this sitting (practice keeps nothing yet)
static var best: int = 0

var run: Node = null
var viewport: SubViewport = null
var picture: TextureRect = null
var leave_button: Button = null
var results: PanelContainer = null
var result_line: Label = null
var best_line: Label = null
var hud: Node = null
var on_touch: Callable = Callable(self, "_on_touch")
var headless_run: bool = false
# the next game's table (0 for a new one each time; the sandbox's films fix it)
var next_seed: int = 0

var _covered: CanvasItem = null
var _held: Node = null
var _held_mode: Node.ProcessMode = Node.PROCESS_MODE_INHERIT
var _leave_armed: float = 0.0
var _fingers: Dictionary = {}
var _touch_ms: int = -100000
var _mouse_sides: Dictionary = {}


static func open(tree: SceneTree, on_hud: Node = null) -> CanvasLayer:
	var screen: CanvasLayer = (load("res://src/world/pinball/pinballscreen.gd") as GDScript).new()
	screen.name = "pinballscreen"
	screen.set("hud", on_hud)
	tree.root.add_child(screen)
	return screen


func _ready() -> void:
	layer = LAYER
	var back := ColorRect.new()
	back.name = "back"
	back.color = Color(0.015, 0.012, 0.03)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(back)
	viewport = SubViewport.new()
	viewport.name = "table"
	viewport.size = VIEW
	viewport.own_world_3d = true
	viewport.world_2d = World2D.new()
	viewport.physics_object_picking = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	picture = TextureRect.new()
	picture.name = "picture"
	picture.texture = viewport.get_texture()
	picture.set_anchors_preset(Control.PRESET_FULL_RECT)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(picture)
	_build_words()
	_hold_the_character()
	cover(get_tree().current_scene)
	start()


func _build_words() -> void:
	leave_button = Button.new()
	leave_button.name = "leave"
	leave_button.text = "Leave"
	leave_button.focus_mode = Control.FOCUS_NONE
	leave_button.anchor_left = LEAVE_BOX.position.x / VIEW.x
	leave_button.anchor_top = LEAVE_BOX.position.y / VIEW.y
	leave_button.anchor_right = LEAVE_BOX.end.x / VIEW.x
	leave_button.anchor_bottom = LEAVE_BOX.end.y / VIEW.y
	for look in [["normal", 0.0], ["hover", 0.06], ["pressed", 0.1]]:
		var style := _pill_style(Color(PILL.lightened(float(look[1])), 0.92))
		style.border_color = Color(GOLD, 0.35)
		leave_button.add_theme_stylebox_override(str(look[0]), style)
	leave_button.add_theme_color_override("font_color", CREAM)
	leave_button.add_theme_font_size_override("font_size", 15)
	leave_button.pressed.connect(ask_to_leave)
	add_child(leave_button)
	results = PanelContainer.new()
	results.name = "results"
	var style := _pill_style(Color(0.06, 0.05, 0.08, 0.95))
	style.set_corner_radius_all(16)
	style.border_color = Color(GOLD, 0.4)
	style.set_content_margin_all(24)
	results.add_theme_stylebox_override("panel", style)
	results.visible = false
	add_child(results)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	results.add_child(column)
	result_line = _words("", 24, CREAM)
	result_line.name = "result"
	column.add_child(result_line)
	best_line = _words("", 15, HINT)
	best_line.name = "bestline"
	column.add_child(best_line)
	column.add_child(_words("Practice: it pays nothing while the table is being built.", 13, HINT))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	column.add_child(row)
	row.add_child(_button("again", "Again", again))
	row.add_child(_button("out", "Leave", leave))


func _pill_style(colour: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = colour
	style.set_corner_radius_all(10)
	style.border_color = Color(1.0, 1.0, 1.0, 0.08)
	style.set_border_width_all(1)
	return style


func _words(text: String, size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(id: String, text: String, does: Callable) -> Button:
	var b := Button.new()
	b.name = id
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(120, 36)
	for look in [["normal", Color(GOLD, 0.18)], ["hover", Color(GOLD, 0.3)], ["pressed", Color(GOLD, 0.42)]]:
		var style := _pill_style(look[1] as Color)
		style.border_color = Color(GOLD, 0.6)
		b.add_theme_stylebox_override(str(look[0]), style)
	b.add_theme_color_override("font_color", CREAM)
	b.add_theme_font_size_override("font_size", 16)
	b.pressed.connect(does)
	return b


func _hold_the_character() -> void:
	_held = get_tree().get_first_node_in_group("player") if is_inside_tree() else null
	if _held != null:
		_held_mode = _held.process_mode
		_held.process_mode = Node.PROCESS_MODE_DISABLED


# =============================================================================
# A GAME
# =============================================================================

func start() -> void:
	"""A new game on a new table."""
	if run != null and is_instance_valid(run):
		run.queue_free()
	_fingers.clear()
	_mouse_sides.clear()
	results.visible = false
	run = RunScript.new()
	run.name = "run"
	run.set("headless", headless_run)
	run.set("seed_now", next_seed)
	run.set("controls_hint", TOUCH_HINT if bool(on_touch.call()) else KEYS_HINT)
	viewport.add_child(run)
	run.connect("game_over", _on_game_over)


func again() -> void:
	start()


func playing() -> bool:
	return run != null and is_instance_valid(run) and not bool(run.get("over"))


func _on_game_over() -> void:
	var score: int = int(run.get("score"))
	var first: bool = score > best
	best = maxi(best, score)
	result_line.text = "Score  %s" % RunScript._thousands(score)
	best_line.text = "A new best!" if first and score > 0 else "Best this sitting  %s" % RunScript._thousands(best)
	results.visible = true
	results.reset_size()
	results.grow_horizontal = Control.GROW_DIRECTION_BOTH
	results.grow_vertical = Control.GROW_DIRECTION_BOTH
	results.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)


# =============================================================================
# THE CONTROLS
# =============================================================================

func _on_touch() -> bool:
	return TouchControls.active


func waiting() -> bool:
	"""A ball waits on the plunger."""
	if not playing():
		return false
	for ball in run.get("balls"):
		if bool((ball as Dictionary).get("held", false)):
			return true
	return false


func _input(event: InputEvent) -> void:
	if not visible:
		return
	var key := event as InputEventKey
	if key != null:
		_key(key)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenTouch:
		_finger(event as InputEventScreenTouch)
		return
	var click := event as InputEventMouseButton
	if click != null and click.device != InputEvent.DEVICE_ID_EMULATION \
			and Time.get_ticks_msec() - _touch_ms > TOUCH_QUIET_MS:
		if click.pressed and (leave_button.get_global_rect().has_point(click.position) or results.visible):
			return
		if click.button_index == MOUSE_BUTTON_LEFT or click.button_index == MOUSE_BUTTON_RIGHT:
			var side: int = -1 if click.button_index == MOUSE_BUTTON_LEFT else 1
			_hold(side, click.pressed, "mouse%d" % side)


func _key(key: InputEventKey) -> void:
	if key.echo:
		return
	if key.keycode == KEY_ESCAPE and key.pressed:
		ask_to_leave()
		return
	if not playing():
		if key.pressed and (key.keycode == KEY_SPACE or key.keycode == KEY_ENTER):
			again()
		return
	if key.keycode in LEFT_KEYS or key.keycode == KEY_SHIFT and key.location == KEY_LOCATION_LEFT:
		run.call("press", -1, key.pressed)
	elif key.keycode in RIGHT_KEYS or key.keycode == KEY_SHIFT and key.location == KEY_LOCATION_RIGHT:
		run.call("press", 1, key.pressed)
	elif key.keycode in PLUNGER_KEYS:
		run.call("plunge", key.pressed)


func _hold(side: int, down: bool, who: String) -> void:
	"""A mouse button or a finger: on the plunger while a ball waits there,
	else its side's flippers - held while any button or finger holds it."""
	if not playing():
		return
	if down:
		var role: String = "plunger" if waiting() else ("left" if side < 0 else "right")
		_mouse_sides[who] = role
	else:
		_mouse_sides.erase(who)
	var roles: Array = _mouse_sides.values()
	run.call("press", -1, roles.has("left"))
	run.call("press", 1, roles.has("right"))
	run.call("plunge", roles.has("plunger"))


func _finger(touch: InputEventScreenTouch) -> void:
	_touch_ms = Time.get_ticks_msec()
	if touch.pressed and (leave_button.get_global_rect().has_point(touch.position) or results.visible):
		return
	var box: Rect2 = picture.get_global_rect()
	var side: int = -1 if touch.position.x < box.position.x + box.size.x / 2.0 else 1
	_hold(side, touch.pressed, "finger%d" % touch.index)


func _process(delta: float) -> void:
	_leave_armed = maxf(0.0, _leave_armed - delta)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT \
			or what == NOTIFICATION_APPLICATION_PAUSED:
		# a lost touch or key must not hold a flipper up
		_mouse_sides.clear()
		if run != null and is_instance_valid(run):
			run.call("press", -1, false)
			run.call("press", 1, false)
			run.call("plunge", false)


# =============================================================================
# LEAVING
# =============================================================================

func ask_to_leave() -> void:
	"""Leave: at once after a game; during one, the second press (or Escape)
	within two seconds."""
	if not playing() or _leave_armed > 0.0:
		leave()
		return
	_leave_armed = 2.0
	leave_button.text = "Sure?"
	get_tree().create_timer(2.0).timeout.connect(_disarm)


func _disarm() -> void:
	if is_instance_valid(leave_button):
		leave_button.text = "Leave"


func leave() -> void:
	close()


func close() -> void:
	if _held != null and is_instance_valid(_held):
		_held.process_mode = _held_mode
	_held = null
	uncover()
	queue_free()


func cover(scene: Node) -> void:
	"""The world under the screen goes undrawn while it is up: only a scene
	that draws, and is drawn now."""
	if scene is CanvasItem and scene != self and (scene as CanvasItem).visible:
		_covered = scene
		_covered.visible = false


func uncover() -> void:
	if _covered != null and is_instance_valid(_covered):
		_covered.visible = true
	_covered = null
