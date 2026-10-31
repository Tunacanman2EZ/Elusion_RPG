# healerrunscreen.gd - the Healer's Run on screen (0.98.0): the run's own
# world in a SubViewport, drawn over everything at a whole multiple, and the
# words round it - the clock, the stretch, lives, shots, the boss's health, a
# banner, and at the end what you did with Again and Leave.
#
# Opened from the Minigames card, in town only (minigamescard.gd): the
# character stays standing where they were, still (open() stops it, close()
# lets it go), so nothing in the world can reach it while you play. The run
# itself touches nothing outside its world (healerrun.gd).
#
# Leave: the button, or Escape - twice while a run is on, once after it.
# Keys are kept from the rest of the game while it is up, so the bag, the map
# and chat do not open behind it.
#
# No class_name; open() is how it is made.
extends CanvasLayer

const RunScript := preload("res://src/world/healerrun/healerrun.gd")
const LAYER := 90
const COLOUR := Color(1.0, 0.86, 0.45)
const COLOUR_HINT := Color(0.82, 0.78, 0.7)
const COLOUR_BAD := Color(1.0, 0.55, 0.45)
const LEAVE_ARMED_SECONDS := 3.0

var run: Node2D = null
var viewport: SubViewport = null
var picture: TextureRect = null
var top_line: Label = null
var stage_line: Label = null
var lives_line: Label = null
var shots_line: Label = null
var slain_line: Label = null
var rank_line: Label = null
var banner_line: Label = null
var boss_bar: ProgressBar = null
var leave_button: Button = null
var results: PanelContainer = null
var result_line: Label = null
var again_button: Button = null
# The character standing in the world while this is up, and how it ran before.
var _held: Node = null
var _held_mode: int = Node.PROCESS_MODE_INHERIT
var _leave_armed: float = 0.0
# A hit is seen: the screen flashes red (HIT_FLASH), from the lives counted last.
var _lives_seen: int = -1
var flash: ColorRect = null
const HIT_FLASH := 0.35
var seed_value: int = 0


static func open(tree: SceneTree, run_seed: int = 0) -> CanvasLayer:
	var screen: CanvasLayer = (load("res://src/world/healerrun/healerrunscreen.gd") as GDScript).new()
	screen.name = "healerrunscreen"
	screen.set("seed_value", run_seed)
	tree.root.add_child(screen)
	return screen


func _ready() -> void:
	layer = LAYER
	var back := ColorRect.new()
	back.name = "back"
	back.color = Color(0.0, 0.0, 0.0)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(back)
	viewport = SubViewport.new()
	viewport.name = "world"
	viewport.size = Vector2i(RunScript.VIEW)
	# A world of its own: its walls, lights and darkness reach nothing outside.
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
	flash.color = Color(1.0, 0.15, 0.1, 0.0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash)
	_build_words()
	_hold_the_character()
	start()


func _build_words() -> void:
	top_line = _label("top", 26, COLOUR, Control.PRESET_CENTER_TOP, Vector2(0, 10))
	stage_line = _label("stage", 18, COLOUR_HINT, Control.PRESET_CENTER_TOP, Vector2(0, 44))
	lives_line = _label("lives", 20, COLOUR, Control.PRESET_TOP_LEFT, Vector2(18, 90))
	shots_line = _label("shots", 18, COLOUR_HINT, Control.PRESET_TOP_LEFT, Vector2(18, 120))
	rank_line = _label("rank", 14, COLOUR_HINT, Control.PRESET_TOP_LEFT, Vector2(18, 148))
	slain_line = _label("slain", 18, COLOUR_HINT, Control.PRESET_TOP_RIGHT, Vector2(-18, 90))
	banner_line = _label("banner", 30, COLOUR, Control.PRESET_CENTER, Vector2(0, -60))
	boss_bar = ProgressBar.new()
	boss_bar.name = "boss"
	boss_bar.show_percentage = false
	boss_bar.min_value = 0.0
	boss_bar.max_value = 1.0
	_place(boss_bar, Control.PRESET_CENTER_TOP, Rect2(-180, 76, 360, 14))
	boss_bar.modulate = Color(1.0, 0.45, 0.4)
	boss_bar.visible = false
	add_child(boss_bar)
	leave_button = Button.new()
	leave_button.name = "leave"
	leave_button.text = "Leave"
	leave_button.focus_mode = Control.FOCUS_NONE
	_place(leave_button, Control.PRESET_TOP_RIGHT, Rect2(-100, 14, 84, 32))
	leave_button.pressed.connect(ask_to_leave)
	add_child(leave_button)
	results = PanelContainer.new()
	results.name = "results"
	results.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.08, 0.07, 0.95)
	style.border_color = Color(0.85, 0.65, 0.25)
	style.set_border_width_all(3)
	style.set_content_margin_all(18)
	results.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	results.add_child(column)
	result_line = Label.new()
	result_line.name = "result"
	result_line.add_theme_font_size_override("font_size", 20)
	result_line.add_theme_color_override("font_color", COLOUR)
	result_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(result_line)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	column.add_child(row)
	again_button = Button.new()
	again_button.name = "again"
	again_button.text = "Again"
	again_button.focus_mode = Control.FOCUS_NONE
	again_button.custom_minimum_size = Vector2(110, 34)
	again_button.pressed.connect(start)
	row.add_child(again_button)
	var out := Button.new()
	out.name = "out"
	out.text = "Leave"
	out.focus_mode = Control.FOCUS_NONE
	out.custom_minimum_size = Vector2(110, 34)
	out.pressed.connect(close)
	row.add_child(out)
	add_child(results)


func _label(id: String, size: int, colour: Color, preset: int, at: Vector2) -> Label:
	var label := Label.new()
	label.name = id
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_anchors_and_offsets_preset(preset)
	if preset == Control.PRESET_CENTER_TOP or preset == Control.PRESET_CENTER:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	elif preset == Control.PRESET_TOP_RIGHT:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	label.offset_left += at.x
	label.offset_right += at.x
	label.offset_top += at.y
	label.offset_bottom += at.y
	add_child(label)
	return label


static func _place(control: Control, preset: int, box: Rect2) -> void:
	"""`control` anchored by `preset`, its box offset from the anchor."""
	control.set_anchors_preset(preset)
	control.offset_left = box.position.x
	control.offset_top = box.position.y
	control.offset_right = box.position.x + box.size.x
	control.offset_bottom = box.position.y + box.size.y


func _hold_the_character() -> void:
	_held = get_tree().get_first_node_in_group("player") if is_inside_tree() else null
	if _held != null:
		_held_mode = _held.process_mode
		_held.process_mode = Node.PROCESS_MODE_DISABLED


func start() -> void:
	"""A run from the start - the first, or Again."""
	if run != null and is_instance_valid(run):
		run.queue_free()
	run = RunScript.new()
	run.name = "run"
	run.set("seed_value", seed_value)
	run.position = RunScript.HALF
	viewport.add_child(run)
	results.visible = false
	_leave_armed = 0.0
	_lives_seen = -1


func _process(delta: float) -> void:
	_leave_armed = maxf(0.0, _leave_armed - delta)
	flash.color.a = maxf(0.0, flash.color.a - delta / HIT_FLASH * 0.35)
	paint()


func paint() -> void:
	"""The words, from the run as it stands."""
	if run == null or not is_instance_valid(run):
		return
	var state: int = int(run.get("state"))
	top_line.text = "Healer's Run   %s" % str(run.call("time_text"))
	var stretch: int = int(run.get("stretch"))
	if state == RunScript.State.WON:
		stage_line.text = "Through the gate"
	elif state == RunScript.State.BOSS or state == RunScript.State.GOAL:
		stage_line.text = "The gate"
	else:
		stage_line.text = "Stretch %d of %d - wave %d" % [mini(stretch + 1, RunScript.STRETCHES),
			RunScript.STRETCHES, int(run.get("wave_in_stretch")) + 1]
	var lives: int = int(run.get("lives"))
	if _lives_seen >= 0 and lives < _lives_seen:
		flash.color.a = 0.35
	_lives_seen = lives
	lives_line.text = "Lives %d" % lives
	lives_line.add_theme_color_override("font_color", COLOUR_BAD if int(run.get("lives")) <= 1 else COLOUR)
	shots_line.text = "Shots %d" % int(RunScript.SHOT_STEPS[int(run.get("power"))]) \
		+ (" - overcharge" if float(run.get("overcharge")) > 0.0 else "")
	rank_line.text = "Danger %d" % int(run.call("rank"))
	slain_line.text = "Slain %d" % int(run.get("slain"))
	banner_line.text = str(run.get("banner"))
	boss_bar.visible = state == RunScript.State.BOSS
	boss_bar.value = float(run.call("boss_share"))
	if _leave_armed > 0.0:
		leave_button.text = "Sure?"
	else:
		leave_button.text = "Leave"
	if (state == RunScript.State.WON or state == RunScript.State.LOST) and not results.visible:
		result_line.text = str(run.call("result_text"))
		results.visible = true
		results.reset_size()
		results.grow_horizontal = Control.GROW_DIRECTION_BOTH
		results.grow_vertical = Control.GROW_DIRECTION_BOTH
		results.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)


func ask_to_leave() -> void:
	"""Leave - asked twice while a run is on; once it is over, at once."""
	var state: int = int(run.get("state")) if run != null and is_instance_valid(run) else RunScript.State.LOST
	var over: bool = state == RunScript.State.WON or state == RunScript.State.LOST
	if over or _leave_armed > 0.0:
		close()
		return
	_leave_armed = LEAVE_ARMED_SECONDS
	paint()


func close() -> void:
	if _held != null and is_instance_valid(_held):
		_held.process_mode = _held_mode
	_held = null
	queue_free()


func _input(event: InputEvent) -> void:
	# THE GAME BEHIND IT HEARS NO KEYS while this is up: no bag, no map, no
	# chat opening under the run. Escape is Leave. Mouse clicks go on to the
	# buttons (the black behind everything stops them reaching the HUD).
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
			ask_to_leave()
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if _held != null and is_instance_valid(_held):
		_held.process_mode = _held_mode
