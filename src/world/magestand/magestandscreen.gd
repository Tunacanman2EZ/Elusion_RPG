# magestandscreen.gd - the Mage's Stand on screen (0.107.0, step 2 of the
# commit folder's MAGES_STAND_PLAN.txt): the stand's world in a SubViewport
# half as far again each way as the Healer's Run's (magestand.gd VIEW), drawn
# over everything, and the words round it - the clock, the wave, the gate's
# and the portal's bars, the slain - a start panel, and at the end what you
# did with Again and Leave.
#
# Opened from the Minigames card, in town, for the owner while it is built
# (minigamescard.gd shows_mage_stand). It pays nothing: no request is made.
# The character stays where it was, still, as the Healer's Run holds it.
#
# THE MOUSE AIMS (the owner: "there will be no limit on meteors the goal will
# be to spam them"): each frame the mouse is turned into the stand's own
# space (world_from_screen(), through how the picture is fitted to the
# window) and handed over as `aim`; the left button held is `casting`. The
# move keys walk her along the wall.
#
# Leave: the button, or Escape - twice while a run is on, once before or
# after it. Keys are kept from the rest of the game while it is up.
#
# No class_name; open() is how it is made.
extends CanvasLayer

const StandScript := preload("res://src/world/magestand/magestand.gd")
const LAYER := 90
const COLOUR := Color(1.0, 0.86, 0.45)
const COLOUR_HINT := Color(0.82, 0.78, 0.7)
const COLOUR_BAD := Color(1.0, 0.55, 0.45)
const DOOR_COLOUR := Color(0.9, 0.6, 0.3)
const PORTAL_COLOUR := Color(0.7, 0.55, 1.0)
const LEAVE_ARMED_SECONDS := 3.0
const HOW_TO := [
	"Walk the wall with your move keys.",
	"Hold the mouse button to rain meteors where you aim - there is no limit.",
	"One in five lands critical; each leaves the ground burning.",
	"The horde breaks the gate, then runs for the portal.",
	"Each wave is bigger, faster and tougher. Hold as many as you can.",
]

var run: Node2D = null
var viewport: SubViewport = null
var picture: TextureRect = null
var top_line: Label = null
var wave_line: Label = null
var slain_line: Label = null
var best_line: Label = null
var banner_line: Label = null
var door_bar: ProgressBar = null
var door_line: Label = null
var portal_bar: ProgressBar = null
var portal_line: Label = null
var leave_button: Button = null
var results: PanelContainer = null
var result_line: Label = null
var start_panel: PanelContainer = null
var god_switch: CheckButton = null
var hud: Node = null
var seed_value: int = 0
# The suite's doors: may this player see the god switch; the mouse, and
# whether its button is held.
var may_be_god: Callable = Callable(self, "_may_be_god")
var mouse_at: Callable = Callable(self, "_mouse_at")
var mouse_held: Callable = Callable(self, "_mouse_held")
# The best this session (step 4 keeps it on the server).
static var best: int = 0
var _held: Node = null
var _held_mode: int = Node.PROCESS_MODE_INHERIT
var _leave_armed: float = 0.0


static func open(tree: SceneTree, on_hud: Node = null) -> CanvasLayer:
	var screen: CanvasLayer = (load("res://src/world/magestand/magestandscreen.gd") as GDScript).new()
	screen.name = "magestandscreen"
	screen.set("hud", on_hud)
	tree.root.add_child(screen)
	return screen


func _ready() -> void:
	layer = LAYER
	var back := ColorRect.new()
	back.name = "back"
	back.color = Color.BLACK
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(back)
	viewport = SubViewport.new()
	viewport.name = "world"
	viewport.size = Vector2i(StandScript.VIEW)
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
	_build_words()
	_hold_the_character()
	start()


func _build_words() -> void:
	top_line = _label("top", 26, COLOUR, Control.PRESET_CENTER_TOP, Vector2(0, 10))
	wave_line = _label("wave", 18, COLOUR_HINT, Control.PRESET_CENTER_TOP, Vector2(0, 44))
	door_bar = _bar("door", -250, DOOR_COLOUR)
	door_line = _label("doorline", 14, DOOR_COLOUR.lightened(0.2), Control.PRESET_CENTER_TOP, Vector2(-135, 90))
	portal_bar = _bar("portalbar", 20, PORTAL_COLOUR)
	portal_line = _label("portalline", 14, PORTAL_COLOUR.lightened(0.2), Control.PRESET_CENTER_TOP, Vector2(135, 90))
	slain_line = _label("slain", 22, COLOUR, Control.PRESET_TOP_RIGHT, Vector2(-18, 90))
	best_line = _label("best", 16, COLOUR_HINT, Control.PRESET_TOP_RIGHT, Vector2(-18, 122))
	banner_line = _label("banner", 30, COLOUR, Control.PRESET_CENTER, Vector2(0, -80))
	leave_button = Button.new()
	leave_button.name = "leave"
	leave_button.text = "Leave"
	leave_button.focus_mode = Control.FOCUS_NONE
	_place(leave_button, Control.PRESET_TOP_RIGHT, Rect2(-100, 14, 84, 32))
	leave_button.pressed.connect(ask_to_leave)
	add_child(leave_button)
	god_switch = CheckButton.new()
	god_switch.name = "god"
	god_switch.text = "God mode"
	god_switch.focus_mode = Control.FOCUS_NONE
	god_switch.add_theme_color_override("font_color", COLOUR_HINT)
	god_switch.add_theme_color_override("font_pressed_color", COLOUR_BAD)
	_place(god_switch, Control.PRESET_TOP_RIGHT, Rect2(-170, 150, 154, 30))
	god_switch.toggled.connect(_on_god_toggled)
	god_switch.visible = false
	add_child(god_switch)
	results = _panel("results")
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
	for pair in [["again", "Again", again], ["out", "Leave", leave]]:
		var b := Button.new()
		b.name = str(pair[0])
		b.text = str(pair[1])
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(110, 34)
		b.pressed.connect(pair[2] as Callable)
		row.add_child(b)
	start_panel = _panel("start")
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 8)
	start_panel.add_child(lines)
	var title := Label.new()
	title.text = "The Mage's Stand"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", COLOUR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lines.add_child(title)
	for words in HOW_TO:
		var line := Label.new()
		line.text = str(words)
		line.add_theme_font_size_override("font_size", 17)
		line.add_theme_color_override("font_color", COLOUR_HINT)
		lines.add_child(line)
	var go := Button.new()
	go.name = "go"
	go.text = "Start  (Space)"
	go.focus_mode = Control.FOCUS_NONE
	go.custom_minimum_size = Vector2(160, 36)
	go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	go.pressed.connect(begin)
	lines.add_child(go)


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


func _bar(id: String, left: float, colour: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.name = id
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(bar, Control.PRESET_CENTER_TOP, Rect2(left, 74, 230, 14))
	bar.modulate = colour
	add_child(bar)
	return bar


func _panel(id: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = id
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.08, 0.07, 0.95)
	style.border_color = Color(0.85, 0.65, 0.25)
	style.set_border_width_all(3)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	panel.visible = false
	add_child(panel)
	return panel


static func _place(control: Control, preset: int, box: Rect2) -> void:
	control.set_anchors_preset(preset)
	control.offset_left = box.position.x
	control.offset_top = box.position.y
	control.offset_right = box.position.x + box.size.x
	control.offset_bottom = box.position.y + box.size.y


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


func start() -> void:
	"""A stand from the start - the first, or Again: on the start panel."""
	if run != null and is_instance_valid(run):
		run.queue_free()
	run = StandScript.new()
	run.name = "stand"
	run.set("seed_value", seed_value)
	run.position = StandScript.HALF
	viewport.add_child(run)
	run.set_process(false)
	var may: bool = bool(may_be_god.call())
	god_switch.visible = may
	run.set("god", may and GameState.god_mode)
	god_switch.set_pressed_no_signal(may and GameState.god_mode)
	results.visible = false
	_leave_armed = 0.0
	start_panel.visible = true
	_centre(start_panel)


func begin() -> void:
	if not start_panel.visible:
		return
	start_panel.visible = false
	run.set_process(true)


func _may_be_god() -> bool:
	return Api.role_at_least(Api.GOD_MODE_MIN_ROLE)


func _on_god_toggled(on: bool) -> void:
	if not bool(may_be_god.call()):
		god_switch.set_pressed_no_signal(false)
		god_switch.visible = false
		return
	GameState.god_mode = on
	if run != null and is_instance_valid(run):
		run.set("god", on)


func world_from_screen(at: Vector2) -> Vector2:
	"""A point on the window, in the stand's own space: the picture keeps its
	shape, centred, so it is scaled by the smaller fit and has bars either
	side or above and below."""
	var box: Rect2 = picture.get_global_rect()
	var fit: float = minf(box.size.x / StandScript.VIEW.x, box.size.y / StandScript.VIEW.y)
	if fit <= 0.0:
		return Vector2.ZERO
	var drawn: Vector2 = StandScript.VIEW * fit
	var corner: Vector2 = box.position + (box.size - drawn) / 2.0
	return (at - corner) / fit - StandScript.HALF


func _mouse_at() -> Vector2:
	return get_viewport().get_mouse_position()


func _mouse_held() -> bool:
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


func _process(delta: float) -> void:
	_leave_armed = maxf(0.0, _leave_armed - delta)
	if run != null and is_instance_valid(run):
		run.set("aim", world_from_screen(mouse_at.call()))
		run.set("casting", bool(mouse_held.call()) and not start_panel.visible and not results.visible)
	paint()


func paint() -> void:
	if run == null or not is_instance_valid(run):
		return
	var state: int = int(run.get("state"))
	top_line.text = "Mage's Stand   %s" % str(run.call("time_text"))
	var wave: int = int(run.get("wave"))
	wave_line.text = ("Wave %d - the %s lands" % [wave, str(run.call("land_name"))]) if wave > 0 else "Get ready"
	var door: float = float(run.get("door"))
	door_bar.value = door / maxf(1.0, float(run.get("door_most")))
	door_line.text = "Gate broken!" if door <= 0.0 else "Gate %d%%" % roundi(door_bar.value * 100.0)
	portal_bar.value = float(run.get("portal")) / float(StandScript.PORTAL_MOST)
	portal_line.text = "Portal %d%%" % roundi(portal_bar.value * 100.0)
	slain_line.text = "Slain %d" % int(run.get("slain"))
	var held: int = int(run.get("waves_held"))
	best = maxi(best, held) if not bool(run.get("god_used")) else best
	best_line.text = "Best: %s held" % StandScript.waves_words(best)
	banner_line.text = "" if start_panel.visible else str(run.get("banner"))
	leave_button.text = "Sure?" if _leave_armed > 0.0 else "Leave"
	if state == StandScript.State.LOST and not results.visible:
		result_line.text = str(run.call("result_text")) + ("\nGod mode was on" if bool(run.get("god_used")) else "")
		results.visible = true
		_centre(results)


func ask_to_leave() -> void:
	"""Leave - twice while a stand is on; before it starts, or after, at once."""
	var on: bool = run != null and is_instance_valid(run) and not start_panel.visible \
		and int(run.get("state")) != StandScript.State.LOST
	if not on or _leave_armed > 0.0:
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
