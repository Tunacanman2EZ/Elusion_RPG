# clothscreen.gd - CUT THE CLOTH on screen (0.130.0, step 1): the run's own
# world (clothrun.gd) in a SubViewport, drawn over everything, and round it
# the words - the round, how much is cut away against the round's mark, the
# lives - a banner, and at the end how far you got with Again and Leave.
#
# Opened from the Minigames card, in town only (minigamescard.gd), the
# owner's alone while it is built: the character stays standing where it
# was, still (open() stops it, close() lets it go). It pays nothing, so it
# asks nothing of the server.
#
# THE CONTROLS (the owner: "on pc it should react like the ring around
# characters it just drags the belluet to the spot you mouse is", "on mobile
# ... a joystick to do the same thing", and "no fruit ninja stuff"):
#   - a mouse: the shot follows it (`aim`); the left button held cuts.
#   - keys: the move keys steer it (`steer`); Space held cuts. A move key
#     takes over from the mouse until the mouse moves again.
#   - a phone: the stick steers (TouchControls.analog_move()); a finger held
#     on SLICE cuts (`_slice_finger`, read here, so the stick's thumb and the
#     cutting finger are two touches).
# Let go mid-cut and the shot waits on its line. A life lost, the cut held
# through it does not cut again until it is let go (`_wait_release`).
#
# THE LOOK, the owner's "make it look way more current": the words drawn in
# rounded dark pills over the picture (`_draw_hud()`, laid out for a
# 1280 x 720 window and scaled to the picture), a gold bar with the round's
# mark, drawn hearts. All drawn in code.
#
# Leave: the button, or Escape - twice while a run is on, once after it.
# Keys are kept from the rest of the game while it is up.
#
# No class_name; the card loads it by path.
extends CanvasLayer

const RunScript := preload("res://src/world/cloth/clothrun.gd")
const Pad := preload("res://src/ui/touchpad.gd")
const LAYER := 90
const LEAVE_ARMED_SECONDS := 3.0
const GOLD := Color(1.0, 0.82, 0.38)
const CREAM := Color(1.0, 0.95, 0.85)
const HINT := Color(0.82, 0.78, 0.7)
const RED := Color(0.92, 0.25, 0.28)
const PILL := Color(0.06, 0.05, 0.08, 0.86)
# The words are laid out for the picture at twice its size (1280 x 720).
const HUD_BASE := Vector2(1280, 720)
const LEAVE_BOX := Rect2(940, 12, 130, 40)
const MOUSE_MOVED := 2.0
const SLICE_SIZE := 132.0
const BANNER_SECONDS := 1.6
const HOW_TO := [
	"Move the mouse - the shot rides the cut edge to it.",
	"Hold the left button (or Space) to cut into the cloth.",
	"Close the cut on an edge: every piece no slime is on is cut away.",
	"A slime that touches your open cut costs a life.",
	"Cut away enough of the cloth to clear the round.",
]
const HOW_TO_TOUCH := {
	0: "Move with the stick - the shot rides the cut edge.",
	1: "Hold SLICE to cut into the cloth.",
}
const STORY := [
	"The town's first map maker drew the world on enchanted parchment.",
	"The slime plague was stopped by cutting the land out from under it.",
	"The seal is failing. Someone has to cut the cloth.",
]

var run: Node2D = null
var viewport: SubViewport = null
var picture: TextureRect = null
var frame: Control = null
var hud_draw: Control = null
var flash: ColorRect = null
var leave_button: Button = null
var results: PanelContainer = null
var result_line: Label = null
var best_line: Label = null
var start_panel: PanelContainer = null
var start_button: Button = null
var stick: Control = null
var slice_pad: Control = null
var hud: Node = null
var seed_value: int = 0
# The suite's doors: the mouse, whether its button is held, and the keys.
var mouse_at: Callable = Callable(self, "_mouse_at")
var mouse_held: Callable = Callable(self, "_mouse_held")
var keys_way: Callable = Callable(self, "_keys_way")
var space_held: Callable = Callable(self, "_space_held")

var _how_to_lines: Array = []
var _worded: int = -1
var _by_mouse: bool = true
var _wait_release: bool = false
var _round_said: int = 0
var _slice_finger: int = -1
var _banner: String = ""
var _banner_left: float = 0.0
var _flash_left: float = 0.0
var _held: Node = null
var _held_mode: int = Node.PROCESS_MODE_INHERIT
var _leave_armed: float = 0.0


static func open(tree: SceneTree, on_hud: Node = null) -> CanvasLayer:
	var screen: CanvasLayer = (load("res://src/world/cloth/clothscreen.gd") as GDScript).new()
	screen.name = "clothscreen"
	screen.set("hud", on_hud)
	tree.root.add_child(screen)
	return screen


func _ready() -> void:
	layer = LAYER
	var back := ColorRect.new()
	back.name = "back"
	back.color = Color(0.03, 0.028, 0.05)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(back)
	viewport = SubViewport.new()
	viewport.name = "world"
	viewport.size = Vector2i(RunScript.VIEW)
	viewport.world_2d = World2D.new()
	viewport.disable_3d = true
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	picture = TextureRect.new()
	picture.name = "picture"
	picture.texture = viewport.get_texture()
	picture.set_anchors_preset(Control.PRESET_FULL_RECT)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(picture)
	flash = ColorRect.new()
	flash.name = "flash"
	flash.color = Color(RED, 0.0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash)
	_build_words()
	_hold_the_character()
	start()


func _build_words() -> void:
	frame = Control.new()
	frame.name = "frame"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	hud_draw = Control.new()
	hud_draw.name = "hud"
	hud_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_draw.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_draw.draw.connect(_draw_hud)
	frame.add_child(hud_draw)
	leave_button = Button.new()
	leave_button.name = "leave"
	leave_button.text = "Leave"
	leave_button.focus_mode = Control.FOCUS_NONE
	leave_button.anchor_left = LEAVE_BOX.position.x / HUD_BASE.x
	leave_button.anchor_top = LEAVE_BOX.position.y / HUD_BASE.y
	leave_button.anchor_right = LEAVE_BOX.end.x / HUD_BASE.x
	leave_button.anchor_bottom = LEAVE_BOX.end.y / HUD_BASE.y
	for look in [["normal", 0.0], ["hover", 0.06], ["pressed", 0.1]]:
		var style := _pill_style(Color(PILL.lightened(float(look[1])), 0.9))
		leave_button.add_theme_stylebox_override(str(look[0]), style)
	leave_button.add_theme_color_override("font_color", CREAM)
	leave_button.add_theme_font_size_override("font_size", 15)
	leave_button.pressed.connect(ask_to_leave)
	frame.add_child(leave_button)
	stick = Pad.minigame_stick()
	add_child(stick)
	slice_pad = Control.new()
	slice_pad.name = "slice"
	slice_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slice_pad.visible = false
	slice_pad.draw.connect(_draw_slice_pad)
	add_child(slice_pad)
	results = _panel("results")
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	results.add_child(column)
	result_line = _words("", 24, CREAM)
	result_line.name = "result"
	column.add_child(result_line)
	best_line = _words("", 15, HINT)
	best_line.name = "bestline"
	column.add_child(best_line)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	column.add_child(row)
	for pair in [["again", "Again", again], ["out", "Leave", leave]]:
		row.add_child(_button(str(pair[0]), str(pair[1]), pair[2] as Callable))
	start_panel = _panel("start")
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 7)
	start_panel.add_child(lines)
	lines.add_child(_words("CUT THE CLOTH", 28, GOLD))
	for words in STORY:
		var told := _words(str(words), 15, Color(CREAM, 0.8))
		lines.add_child(told)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	lines.add_child(gap)
	for words in HOW_TO:
		var line := _words(str(words), 16, HINT)
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		lines.add_child(line)
		_how_to_lines.append(line)
	start_button = _button("go", "Start  (Space)", begin)
	start_button.custom_minimum_size = Vector2(170, 38)
	start_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	lines.add_child(start_button)


func _pill_style(colour: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = colour
	style.set_corner_radius_all(12)
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
	for look in [["normal", Color(GOLD, 0.16)], ["hover", Color(GOLD, 0.28)], ["pressed", Color(GOLD, 0.4)]]:
		var style := _pill_style(look[1] as Color)
		style.border_color = Color(GOLD, 0.55)
		b.add_theme_stylebox_override(str(look[0]), style)
	b.add_theme_color_override("font_color", CREAM)
	b.add_theme_font_size_override("font_size", 16)
	b.pressed.connect(does)
	return b


func _panel(id: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = id
	var style := _pill_style(Color(0.06, 0.05, 0.08, 0.94))
	style.set_corner_radius_all(16)
	style.border_color = Color(GOLD, 0.35)
	style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", style)
	panel.visible = false
	add_child(panel)
	return panel


func _centre(panel: Control) -> void:
	panel.reset_size()
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)


func _hold_the_character() -> void:
	_held = get_tree().get_first_node_in_group("player") if is_inside_tree() else null
	if _held != null:
		_held_mode = _held.process_mode
		_held.process_mode = Node.PROCESS_MODE_DISABLED


# =============================================================================
# A RUN
# =============================================================================

func start() -> void:
	"""A run from the start - the first, or Again: on the start panel."""
	if run != null and is_instance_valid(run):
		run.queue_free()
	run = RunScript.new()
	run.name = "cloth"
	run.set("seed_value", seed_value)
	run.connect("hurt", _on_hurt)
	run.connect("round_cleared", _on_cleared)
	viewport.add_child(run)
	run.set_physics_process(false)
	results.visible = false
	_leave_armed = 0.0
	_banner = ""
	start_panel.visible = true
	_centre(start_panel)


func begin() -> void:
	if not start_panel.visible:
		return
	start_panel.visible = false
	_wait_release = true
	run.set_physics_process(true)
	_round_said = 0


func playing() -> bool:
	return run != null and is_instance_valid(run) and not start_panel.visible \
		and int(run.get("state")) != RunScript.State.OVER


func _say(text: String) -> void:
	_banner = text
	_banner_left = BANNER_SECONDS


func _on_hurt() -> void:
	"""A life lost: the flash, the lives left - and the button held through
	it does not cut again until it is let go and pressed (else the shot,
	back on the edge, would burn straight back in)."""
	_flash_left = 0.35
	_wait_release = true
	_slice_finger = -1
	var lives: int = int(run.get("lives"))
	if lives > 0:
		_say("%d %s left" % [lives, "life" if lives == 1 else "lives"])


func _on_cleared(which: int) -> void:
	_say("Round %d cleared!" % which)


# =============================================================================
# THE CONTROLS
# =============================================================================

func world_from_screen(at: Vector2) -> Vector2:
	"""A point on the window, on the run's board: the picture keeps its
	shape, centred, scaled by the smaller fit."""
	var box: Rect2 = picture.get_global_rect()
	var fit: float = minf(box.size.x / RunScript.VIEW.x, box.size.y / RunScript.VIEW.y)
	if fit <= 0.0:
		return Vector2.ZERO
	var corner: Vector2 = box.position + (box.size - RunScript.VIEW * fit) / 2.0
	return (at - corner) / fit


func drawn_rect() -> Rect2:
	return Pad.drawn_rect(picture, RunScript.VIEW)


func stick_zone() -> Rect2:
	"""Where a thumb lands for the stick: the dark left of the picture when
	there is room, else its lower left."""
	var drawn: Rect2 = drawn_rect()
	var view: Vector2 = get_viewport().get_visible_rect().size if is_inside_tree() else HUD_BASE
	if drawn.position.x >= 150.0:
		return Rect2(Vector2(0.0, view.y * 0.35), Vector2(drawn.position.x, view.y * 0.65))
	return Rect2(Vector2(0.0, view.y * 0.45), Vector2(view.x * 0.32, view.y * 0.55))


func slice_rect() -> Rect2:
	"""SLICE: in the dark right of the picture when there is room, else its
	lower right."""
	var drawn: Rect2 = drawn_rect()
	var view: Vector2 = get_viewport().get_visible_rect().size if is_inside_tree() else HUD_BASE
	var right: float = view.x - drawn.end.x
	var at := Vector2(view.x - SLICE_SIZE - 36.0, view.y - SLICE_SIZE - 40.0)
	if right >= SLICE_SIZE + 24.0:
		at.x = drawn.end.x + (right - SLICE_SIZE) / 2.0
	return Rect2(at, Vector2(SLICE_SIZE, SLICE_SIZE))


func _mouse_at() -> Vector2:
	return get_viewport().get_mouse_position()


func _mouse_held() -> bool:
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


func _keys_way() -> Vector2:
	return Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")


func _space_held() -> bool:
	return Input.is_physical_key_pressed(KEY_SPACE)


func _process(delta: float) -> void:
	_leave_armed = maxf(0.0, _leave_armed - delta)
	_banner_left = maxf(0.0, _banner_left - delta)
	_flash_left = maxf(0.0, _flash_left - delta)
	flash.color = Color(RED, 0.28 * _flash_left / 0.35)
	var touch: bool = TouchControls.active
	if not touch:
		_slice_finger = -1
	if run != null and is_instance_valid(run):
		var on: bool = playing() and not results.visible
		if touch:
			run.set("aim", null)
			run.set("steer", TouchControls.analog_move() if on else Vector2.ZERO)
			run.set("cut_held", on and _slice_finger >= 0)
			_wait_release = false
		else:
			var way: Vector2 = keys_way.call()
			if way.length() > 0.0:
				_by_mouse = false
			var mouse: bool = bool(mouse_held.call())
			var space: bool = bool(space_held.call())
			# the click or the Space that started it is not a cut
			if not mouse and not space:
				_wait_release = false
			run.set("steer", way if on else Vector2.ZERO)
			run.set("aim", world_from_screen(mouse_at.call()) if on and _by_mouse else null)
			run.set("cut_held", on and not _wait_release and (space or (mouse and _by_mouse)))
	_fit_frame()
	Pad.lay_minigame_stick(stick, touch and playing(), stick_zone(),
		get_window() if is_inside_tree() else null, get_viewport().get_visible_rect().size if is_inside_tree() else Vector2.ZERO)
	slice_pad.visible = touch and playing()
	if slice_pad.visible:
		var box: Rect2 = slice_rect()
		slice_pad.position = box.position
		slice_pad.size = box.size
		slice_pad.queue_redraw()
	_word_for_touch()
	paint()


func _fit_frame() -> void:
	var at: Rect2 = drawn_rect()
	frame.position = at.position
	frame.size = at.size


func _word_for_touch() -> void:
	var touch: int = 1 if TouchControls.active else 0
	if touch == _worded:
		return
	_worded = touch
	for k in _how_to_lines.size():
		(_how_to_lines[k] as Label).text = str(HOW_TO_TOUCH[k]) if touch == 1 and HOW_TO_TOUCH.has(k) else str(HOW_TO[k])
	start_button.text = "Start" if touch == 1 else "Start  (Space)"


# =============================================================================
# THE WORDS
# =============================================================================

func paint() -> void:
	if run == null or not is_instance_valid(run):
		return
	leave_button.text = "Sure?" if _leave_armed > 0.0 else "Leave"
	if playing() and int(run.get("state")) == RunScript.State.PLAYING and int(run.get("round_now")) != _round_said:
		_round_said = int(run.get("round_now"))
		_say("Round %d" % _round_said)
	if int(run.get("state")) == RunScript.State.OVER and not results.visible:
		var reached: int = int(run.get("round_now"))
		result_line.text = "The slimes broke through on round %d" % reached
		var cleared: int = int(run.get("best"))
		best_line.text = "%d %s cleared   ·   best %d" % [cleared, "round" if cleared == 1 else "rounds",
			int(RunScript.best_ever)]
		results.visible = true
		_centre(results)
	hud_draw.queue_redraw()


func _draw_hud() -> void:
	"""The words, in pills over the picture: laid out for 1280 x 720, scaled."""
	if run == null or not is_instance_valid(run):
		return
	var k: float = hud_draw.size.x / HUD_BASE.x
	hud_draw.draw_set_transform(Vector2.ZERO, 0.0, Vector2(k, k))
	var font: Font = ThemeDB.fallback_font
	var pill := _pill_style(PILL)
	# left: the name, the round, the best
	hud_draw.draw_style_box(pill, Rect2(16, 10, 360, 44))
	hud_draw.draw_string(font, Vector2(32, 38), "CUT THE CLOTH", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, CREAM)
	hud_draw.draw_string(font, Vector2(186, 38), "Round %d" % int(run.get("round_now")),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.0, 1.0, 1.0, 0.7))
	hud_draw.draw_string(font, Vector2(270, 38), "best %d" % maxi(int(RunScript.best_ever), int(run.get("best"))),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 1.0, 1.0, 0.45))
	# middle: how much is cut away, against the round's mark
	var taken: float = float(run.get("taken"))
	var target: float = RunScript.target_for(int(run.get("round_now")))
	hud_draw.draw_style_box(pill, Rect2(420, 10, 480, 44))
	var bar := Rect2(440, 34, 440, 10)
	hud_draw.draw_string(font, Vector2(440, 28), "%d%% cut away" % floori(taken * 100.0),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, CREAM)
	hud_draw.draw_string(font, Vector2(440, 28), "clear at %d%%" % roundi(target * 100.0),
		HORIZONTAL_ALIGNMENT_RIGHT, bar.size.x, 13, Color(1.0, 1.0, 1.0, 0.5))
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1.0, 1.0, 1.0, 0.10)
	track.set_corner_radius_all(5)
	hud_draw.draw_style_box(track, bar)
	if taken > 0.0:
		var fill := StyleBoxFlat.new()
		fill.bg_color = GOLD if taken < target else Color(0.6, 0.95, 0.5)
		fill.set_corner_radius_all(5)
		hud_draw.draw_style_box(fill, Rect2(bar.position, Vector2(maxf(10.0, bar.size.x * clampf(taken, 0.0, 1.0)), bar.size.y)))
	var mark_x: float = bar.position.x + bar.size.x * target
	hud_draw.draw_line(Vector2(mark_x, bar.position.y - 3), Vector2(mark_x, bar.end.y + 3), Color(1.0, 1.0, 1.0, 0.85), 2.0)
	# right: the lives
	hud_draw.draw_style_box(pill, Rect2(1104, 10, 160, 44))
	for n in RunScript.LIVES:
		_heart(Vector2(1138 + n * 44, 32), n < int(run.get("lives")))
	# the banner
	if _banner_left > 0.0 and _banner != "":
		var a: float = clampf(_banner_left / 0.4, 0.0, 1.0)
		var wide: float = font.get_string_size(_banner, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x + 64.0
		var box := Rect2(Vector2((HUD_BASE.x - wide) / 2.0, 300), Vector2(wide, 64))
		hud_draw.draw_style_box(_pill_style(Color(PILL, 0.8 * a)), box)
		hud_draw.draw_string(font, Vector2(box.position.x, box.position.y + 43), _banner, HORIZONTAL_ALIGNMENT_CENTER,
			box.size.x, 30, Color(CREAM, a))
	hud_draw.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _heart(at: Vector2, full: bool) -> void:
	var points := PackedVector2Array()
	for n in 40:
		var t: float = float(n) / 40.0 * TAU
		points.append(at + Vector2(16.0 * pow(sin(t), 3), -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))) * 0.75)
	if full:
		hud_draw.draw_colored_polygon(points, RED)
		hud_draw.draw_circle(at + Vector2(-4, -4), 2.0, Color(1.0, 1.0, 1.0, 0.45))
	else:
		points.append(points[0])
		hud_draw.draw_polyline(points, Color(1.0, 1.0, 1.0, 0.35), 1.5, true)


func _draw_slice_pad() -> void:
	"""SLICE, a round pad: brighter while a finger holds it."""
	var middle: Vector2 = slice_pad.size / 2.0
	var r: float = minf(middle.x, middle.y)
	var held: bool = _slice_finger >= 0
	slice_pad.draw_circle(middle, r, Color(0.06, 0.05, 0.08, 0.62 if not held else 0.8))
	slice_pad.draw_arc(middle, r - 2.0, 0.0, TAU, 48, Color(0.55, 0.95, 0.42, 0.55 if not held else 1.0), 3.0, true)
	var font: Font = ThemeDB.fallback_font
	slice_pad.draw_string(font, Vector2(0, middle.y + 7), "SLICE", HORIZONTAL_ALIGNMENT_CENTER, slice_pad.size.x, 20,
		Color(CREAM, 0.8 if not held else 1.0))


# =============================================================================
# LEAVING
# =============================================================================

func ask_to_leave() -> void:
	"""Leave - twice while a run is on; before it starts, or after, at once."""
	if not playing() or _leave_armed > 0.0:
		leave()
		return
	_leave_armed = LEAVE_ARMED_SECONDS
	paint()


func leave() -> void:
	close()


func again() -> void:
	start()


func close() -> void:
	if _held != null and is_instance_valid(_held):
		_held.process_mode = _held_mode
	_held = null
	queue_free()


func _input(event: InputEvent) -> void:
	# SLICE ON A PHONE: a finger down on the pad cuts until it lifts. Not
	# consumed: the stick takes its own thumb as ever.
	var touch := event as InputEventScreenTouch
	if touch != null:
		if touch.pressed and _slice_finger < 0 and slice_pad.visible and slice_rect().has_point(touch.position):
			_slice_finger = touch.index
		elif not touch.pressed and touch.index == _slice_finger:
			_slice_finger = -1
		return
	if event is InputEventMouseMotion and (event as InputEventMouseMotion).relative.length() > MOUSE_MOVED:
		_by_mouse = true
	# THE GAME BEHIND IT HEARS NO KEYS while this is up. Escape is Leave;
	# Space starts.
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
			ask_to_leave()
		elif key.pressed and not key.echo and key.keycode == KEY_SPACE and start_panel.visible:
			begin()
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if _held != null and is_instance_valid(_held):
		_held.process_mode = _held_mode
