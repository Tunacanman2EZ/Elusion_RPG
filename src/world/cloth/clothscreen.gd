# clothscreen.gd - CUT THE CLOTH on screen (0.130.0; 0.131.0): the run's own world
# (clothrun.gd) in a SubViewport, drawn over everything, and round it the
# words - the round and its land, how much is cut away against the round's
# mark (or the Plague Mother's piece against her seal), the gold, the lives,
# what is helping you now - a banner, and at the end how far you got with
# Again and Leave.
#
# Opened from the Minigames card, in town only (minigamescard.gd): the
# character stays standing where it was, still (open() stops it, close() lets
# it go).
#
# GOLD AND THREE RUNS A DAY (0.131.0, the owner's "rewards and a daily limit
# through the server"): the card's Go asks the server first (POST
# /api/minigames/enter, game "cloth") and hands this its run's id and what it
# pays (`pays`, the rounds' table); the gold counts up on screen
# (run.gold_now()), and Leave - or Again - finishes the run on the server
# (POST /api/minigames/finish with the rounds cleared), which pays it into
# the character's purse, held to the time the run took. Again asks for the
# day's next run. A run with no id (the owner's own test, or the suite) is
# practice: it pays nothing, and says so.
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
# Let go mid-cut and the shot waits on its line (on ice it slides on). A life
# lost, the cut held through it does not cut again until it is let go
# (`_wait_release`).
#
# THE LOOK, the owner's "make it look way more current": the words drawn in
# rounded dark pills over the picture (`_draw_hud()`, laid out for a
# 1280 x 720 window and scaled to the picture), a gold bar with the round's
# mark, drawn hearts, chips for what helps you. All drawn in code.
#
# Leave: the button, or Escape - twice while a run is on, once after it.
# Keys are kept from the rest of the game while it is up.
#
# No class_name; the card loads it by path.
extends CanvasLayer

const RunScript := preload("res://src/world/cloth/clothrun.gd")
# A Leave in words, the day's allowance with it - the Healer's Run's, one rule.
const HealerScreen := preload("res://src/world/healerrun/healerrunscreen.gd")
const Pad := preload("res://src/ui/touchpad.gd")
const LAYER := 90
const GAME := "cloth"
const LEAVE_ARMED_SECONDS := 3.0
const GOLD := Color(1.0, 0.82, 0.38)
const CREAM := Color(1.0, 0.95, 0.85)
const HINT := Color(0.82, 0.78, 0.7)
const RED := Color(0.92, 0.25, 0.28)
const PILL := Color(0.06, 0.05, 0.08, 0.86)
# The words are laid out for the picture at twice its size (1280 x 720).
const HUD_BASE := Vector2(1280, 720)
const LEAVE_BOX := Rect2(1020, 12, 82, 40)
const MOUSE_MOVED := 2.0
const SLICE_SIZE := 132.0
const BANNER_SECONDS := 1.8
const CHIPS := {"swift": ["Swift", Color(0.45, 0.95, 0.5)], "slow": ["Slow", Color(0.45, 0.7, 1.0)],
	"ward": ["Ward", Color(1.0, 0.82, 0.3)]}
const HOW_TO := [
	"Move the mouse - the shot rides the cut edge to it.",
	"Hold the left button (or Space) to cut into the cloth.",
	"Close the cut on an edge: every piece no slime is on is cut away.",
	"A slime on your open cut costs a life - and saws ride the edge.",
	"Each map has its own trick. Cut pickups free. Every 5th round, a boss.",
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
var gold_line: Label = null
var again_button: Button = null
var start_panel: PanelContainer = null
var start_button: Button = null
var stick: Control = null
var slice_pad: Control = null
var hud: Node = null
var seed_value: int = 0
# The run on the server (0: practice) and what it pays.
var run_id: int = 0
var pays: Dictionary = {}
# The suite's doors: the mouse, whether its button is held, the keys, the
# server, and the character's slot.
var mouse_at: Callable = Callable(self, "_mouse_at")
var mouse_held: Callable = Callable(self, "_mouse_held")
var keys_way: Callable = Callable(self, "_keys_way")
var space_held: Callable = Callable(self, "_space_held")
var finish_request: Callable = Callable(Api, "post")
var enter_request: Callable = Callable(Api, "post")
var slot_now: Callable = Callable(self, "_slot")

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
var _held_mode: Node.ProcessMode = Node.PROCESS_MODE_INHERIT
var _leave_armed: float = 0.0
var _paid: bool = false
var _busy: bool = false
# What the server paid at Leave and held back (0.157.0, A DAY'S MINIGAME
# GOLD); -1 before it says.
var _gold_paid: int = -1
var _held_back: int = 0


static func open(tree: SceneTree, on_hud: Node = null, run_on_server: int = 0, what_it_pays: Dictionary = {}) -> CanvasLayer:
	var screen: CanvasLayer = (load("res://src/world/cloth/clothscreen.gd") as GDScript).new()
	screen.name = "clothscreen"
	screen.set("hud", on_hud)
	screen.set("run_id", run_on_server)
	screen.set("pays", what_it_pays)
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
	gold_line = _words("", 18, GOLD)
	gold_line.name = "goldline"
	column.add_child(gold_line)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	column.add_child(row)
	again_button = _button("again", "Again", again)
	row.add_child(again_button)
	row.add_child(_button("out", "Leave", leave))
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
	for look in [["normal", Color(GOLD, 0.16)], ["hover", Color(GOLD, 0.28)], ["pressed", Color(GOLD, 0.4)],
			["disabled", Color(0.3, 0.3, 0.3, 0.2)]]:
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
	run.set("pays", pays)
	run.connect("hurt", _on_hurt)
	run.connect("round_cleared", _on_cleared)
	run.connect("said", _say)
	viewport.add_child(run)
	run.set_physics_process(false)
	results.visible = false
	again_button.disabled = false
	_paid = false
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
	var gold: int = RunScript.gold_for_round(which, pays)
	_say(("Round %d cleared!  +%s gold" % [which, thousands(gold)]) if run_id != 0 else ("Round %d cleared!" % which))


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


func _slot() -> int:
	return int(CharacterData.active_character_index)


# WHO SPENT IT (0.152.0): this minigame's own frame, timed, so a slow
# frame on the readout names it (PerfOverlay.spend()).
func _process(delta: float) -> void:
	var spent_from: int = Time.get_ticks_usec()
	_timed_process(delta)
	PerfOverlay.spend(&"cloth screen", Time.get_ticks_usec() - spent_from)


func _timed_process(delta: float) -> void:
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
			var aim: Variant = null
			if on and _by_mouse:
				aim = world_from_screen(mouse_at.call())
			run.set("aim", aim)
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

static func thousands(n: int) -> String:
	"""A whole number with commas: 20000 reads 20,000."""
	var digits: String = str(absi(n))
	var out: String = ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-" if n < 0 else "") + digits + out


func paint() -> void:
	if run == null or not is_instance_valid(run):
		return
	leave_button.text = "Sure?" if _leave_armed > 0.0 else "Leave"
	if playing() and int(run.get("state")) == RunScript.State.PLAYING and int(run.get("round_now")) != _round_said:
		_round_said = int(run.get("round_now"))
		_say("%s - %s" % [str(run.call("round_title")), str(run.call("land_name"))])
	if int(run.get("state")) == RunScript.State.OVER and not results.visible:
		var reached: int = int(run.get("round_now"))
		result_line.text = "The slimes broke through on %s" % str(run.call("round_title")).to_lower()
		var cleared: int = int(run.get("best"))
		best_line.text = "%d %s cleared   ·   best %d" % [cleared, "round" if cleared == 1 else "rounds",
			int(RunScript.best_ever)]
		gold_line.text = ("%s gold - yours when you leave" % thousands(int(run.call("gold_now")))) if run_id != 0 \
			else "Practice - this run pays nothing"
		if reached <= 0:
			result_line.text = "The slimes broke through"
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
	var which: int = int(run.get("round_now"))
	# left: the round and its land, and the land's one rule
	hud_draw.draw_style_box(pill, Rect2(16, 10, 394, 44))
	hud_draw.draw_string(font, Vector2(32, 29), "%s  ·  %s" % [str(run.call("round_title")), str(run.call("land_name"))],
		HORIZONTAL_ALIGNMENT_LEFT, 362, 15, CREAM)
	hud_draw.draw_string(font, Vector2(32, 46), str(run.call("rule_line")), HORIZONTAL_ALIGNMENT_LEFT, 362, 12,
		Color(1.0, 1.0, 1.0, 0.55))
	# middle: how much is cut away against the round's mark - or her piece
	var boss: bool = RunScript.is_boss_round(which)
	var taken: float = float(run.get("taken"))
	var target: float = RunScript.target_for(which)
	var done: float = taken
	var left_words: String = "%d%% cut away" % floori(taken * 100.0)
	var right_words: String = "clear at %d%%" % roundi(target * 100.0)
	if boss:
		var share: float = float(run.get("boss_share"))
		done = 1.0 - share
		target = 1.0 - RunScript.SEAL_SHARE
		left_words = "Her piece: %d%% of the cloth" % roundi(share * 100.0)
		right_words = "sealed at %d%%" % roundi(RunScript.SEAL_SHARE * 100.0)
	hud_draw.draw_style_box(pill, Rect2(424, 10, 440, 44))
	var bar := Rect2(442, 34, 404, 10)
	hud_draw.draw_string(font, Vector2(442, 28), left_words, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, CREAM)
	hud_draw.draw_string(font, Vector2(442, 28), right_words, HORIZONTAL_ALIGNMENT_RIGHT, bar.size.x, 13, Color(1.0, 1.0, 1.0, 0.5))
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1.0, 1.0, 1.0, 0.10)
	track.set_corner_radius_all(5)
	hud_draw.draw_style_box(track, bar)
	if done > 0.0:
		var fill := StyleBoxFlat.new()
		fill.bg_color = (Color(0.86, 0.45, 0.95) if boss else GOLD) if done < target else Color(0.6, 0.95, 0.5)
		fill.set_corner_radius_all(5)
		hud_draw.draw_style_box(fill, Rect2(bar.position, Vector2(maxf(10.0, bar.size.x * clampf(done, 0.0, 1.0)), bar.size.y)))
	var mark_x: float = bar.position.x + bar.size.x * target
	hud_draw.draw_line(Vector2(mark_x, bar.position.y - 3), Vector2(mark_x, bar.end.y + 3), Color(1.0, 1.0, 1.0, 0.85), 2.0)
	# the gold, and the lives
	hud_draw.draw_style_box(pill, Rect2(878, 10, 132, 44))
	if run_id != 0:
		_draw_coin(Vector2(900, 32))
		hud_draw.draw_string(font, Vector2(914, 38), thousands(int(run.call("gold_now"))), HORIZONTAL_ALIGNMENT_LEFT, 90, 16, GOLD)
	else:
		hud_draw.draw_string(font, Vector2(878, 38), "Practice", HORIZONTAL_ALIGNMENT_CENTER, 132, 14, Color(1.0, 1.0, 1.0, 0.5))
	hud_draw.draw_style_box(pill, Rect2(1110, 10, 154, 44))
	var lives: int = int(run.get("lives"))
	var shown: int = maxi(RunScript.LIVES, lives)
	var spacing: float = 140.0 / float(shown)
	for n in shown:
		_heart(Vector2(1110 + spacing * (float(n) + 0.5) + 7.0, 32), n < lives, 0.62 if shown > RunScript.LIVES else 0.75)
	# what helps you now
	var chips: Array = []
	if float(run.get("swift_left")) > 0.0:
		chips.append(["swift", float(run.get("swift_left"))])
	if float(run.get("slow_left")) > 0.0:
		chips.append(["slow", float(run.get("slow_left"))])
	if bool(run.get("ward")):
		chips.append(["ward", -1.0])
	var x: float = (HUD_BASE.x - float(chips.size()) * 118.0) / 2.0
	for chip in chips:
		var info: Array = CHIPS[chip[0]]
		var box := Rect2(Vector2(x, 666), Vector2(110, 32))
		hud_draw.draw_style_box(_pill_style(Color(PILL, 0.9)), box)
		hud_draw.draw_circle(box.position + Vector2(18, 16), 5.0, info[1] as Color)
		var words: String = str(info[0]) if float(chip[1]) < 0.0 else "%s %ds" % [str(info[0]), ceili(float(chip[1]))]
		hud_draw.draw_string(font, box.position + Vector2(30, 22), words, HORIZONTAL_ALIGNMENT_LEFT, 76, 14, CREAM)
		x += 118.0
	# the banner
	if _banner_left > 0.0 and _banner != "":
		var a: float = clampf(_banner_left / 0.4, 0.0, 1.0)
		var wide: float = font.get_string_size(_banner, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x + 64.0
		var at := Rect2(Vector2((HUD_BASE.x - wide) / 2.0, 300), Vector2(wide, 60))
		hud_draw.draw_style_box(_pill_style(Color(PILL, 0.8 * a)), at)
		hud_draw.draw_string(font, Vector2(at.position.x, at.position.y + 40), _banner, HORIZONTAL_ALIGNMENT_CENTER,
			at.size.x, 28, Color(CREAM, a))
	hud_draw.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_coin(at: Vector2) -> void:
	hud_draw.draw_circle(at, 8.0, Color(0.75, 0.55, 0.15))
	hud_draw.draw_circle(at, 6.0, GOLD)
	hud_draw.draw_circle(at + Vector2(-2, -2), 1.5, Color(1.0, 1.0, 0.85, 0.8))


func _heart(at: Vector2, full: bool, size_k: float) -> void:
	var points := PackedVector2Array()
	for n in 40:
		var t: float = float(n) / 40.0 * TAU
		points.append(at + Vector2(16.0 * pow(sin(t), 3), -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))) * size_k)
	if full:
		hud_draw.draw_colored_polygon(points, RED)
		hud_draw.draw_circle(at + Vector2(-4, -4) * size_k / 0.75, 2.0, Color(1.0, 1.0, 1.0, 0.45))
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
# LEAVING, AND AGAIN
# =============================================================================

func ask_to_leave() -> void:
	"""Leave - twice while a run is on; before it starts, or after, at once."""
	if not playing() or _leave_armed > 0.0:
		leave()
		return
	_leave_armed = LEAVE_ARMED_SECONDS
	paint()


func leave() -> void:
	"""Leave: the run's gold paid into the character's purse by the server,
	then out. Not reached, the screen says so and stays - Leave again tries
	again."""
	if _busy:
		return
	if not await _pay():
		return
	var gold: int = int(run.call("gold_now")) if run != null and is_instance_valid(run) else 0
	if _gold_paid >= 0:
		gold = _gold_paid
	var said: String = HealerScreen.paid_line("Cut the Cloth", gold, _held_back)
	if run_id != 0 and said != "" and hud != null and is_instance_valid(hud) and hud.has_method("_push_message"):
		hud.call("_push_message", said, GOLD, 0, true)
	close()


func again() -> void:
	"""Again: this run's gold paid, then the day's next run - when there is
	one. Practice is practice again."""
	if _busy:
		return
	if not await _pay():
		return
	if run_id == 0:
		start()
		return
	_busy = true
	result_line.text = "Asking for another run..."
	var res: Dictionary = await enter_request.call("/api/minigames/enter", {"game": GAME, "slot": int(slot_now.call())}, 6.0)
	_busy = false
	if not is_instance_valid(self):
		return
	var data: Dictionary = res.get("data", {}) if res.get("data") is Dictionary else {}
	if res.get("ok", false) and data.has("run"):
		run_id = int(data["run"])
		if data.get("pays") is Dictionary:
			pays = data["pays"]
		start()
		return
	if int(res.get("status", 0)) == 409:
		result_line.text = str(data.get("message", "No runs left today."))
		again_button.disabled = true
		return
	result_line.text = "Could not reach the server - try again."


func _pay() -> bool:
	"""This run finished on the server and its gold paid - once. True when it
	is (or it is practice)."""
	if run_id == 0 or _paid:
		return true
	if run == null or not is_instance_valid(run):
		return true
	_busy = true
	# Still while it is settled: what is sent is what was reached.
	run.set_physics_process(false)
	var body := {"run": run_id, "rounds": int(run.get("best")), "bosses": int(run.call("bosses_beaten"))}
	var res: Dictionary = await finish_request.call("/api/minigames/finish", body, 8.0)
	_busy = false
	if not is_instance_valid(self):
		return false
	var data: Dictionary = res.get("data", {}) if res.get("data") is Dictionary else {}
	if res.get("ok", false) or int(res.get("status", 0)) == 409:
		_paid = true
		if res.get("ok", false) and data.has("gold"):
			_gold_paid = int(data["gold"])
			_held_back = int(data.get("held_back", 0))
		var status: Dictionary = data.get("status", {}) if data.get("status") is Dictionary else {}
		if status.has("gold") and _held != null and is_instance_valid(_held) and _held.has_method("set_gold"):
			_held.call("set_gold", int(status["gold"]))
		return true
	results.visible = true
	_centre(results)
	result_line.text = "Could not reach the server"
	gold_line.text = "Your gold is waiting: Leave again to take it."
	return false


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
