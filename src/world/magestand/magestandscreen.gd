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
# THE WORDS SIT ON THE PICTURE (0.109.0; the owner: "we need to clean up
# ui"): one strip across its top - the wave and its land on the left, the
# gate's and the portal's bars in the middle with their words inside, the
# clock and the slain on the right - and Leave under it, all in `frame`,
# which follows the picture as it is fitted to the window (_fit_frame()).
# They were placed on the window, so a wide one left the slain and Leave
# out in the black beside the field.
#
# THE PICK: while the run waits on a pick (magestand.gd State.PICK), a panel
# of up to three cards, each with how many times it has been taken (the
# owner: "get rid of number 1 2 3 we only want to see how many times been
# upgraded") - click one (1, 2 and 3 still pick, unshown).
#
# The pick has a Reroll button (magestand.gd `rerolls`); an evolution's
# card is named in EVOLVE_COLOUR. While a wave's last are still about, a
# button calls the next one early (call_early()). Under GATE_LOW the gate's
# bar pulses red.
#
# ON A PHONE (0.110.1; the owner: "no joystick on mobil believe we only need
# left joystick"): a stick of its own (touchpad.gd minigame_stick()) in the
# dark left of the field, below the strip, walks her; any other finger on the
# field aims, and casts while it is down (_aim_finger) - the mouse is not
# read while touch is on (one finger is a mouse to Godot, so the stick's own
# thumb would cast).
#
# No god mode here (the owner: "we also do not need godmode on this mode").
#
# No class_name; open() is how it is made.
extends CanvasLayer

const StandScript := preload("res://src/world/magestand/magestand.gd")
const Pad := preload("res://src/ui/touchpad.gd")
const LAYER := 90
const COLOUR := Color(1.0, 0.86, 0.45)
const COLOUR_HINT := Color(0.82, 0.78, 0.7)
const COLOUR_BAD := Color(1.0, 0.55, 0.45)
const DOOR_COLOUR := Color(0.9, 0.6, 0.3)
const PORTAL_COLOUR := Color(0.7, 0.55, 1.0)
const EVOLVE_COLOUR := Color(1.0, 0.55, 0.85)
const DANGER_COLOUR := Color(1.0, 0.2, 0.15)
const LEAVE_ARMED_SECONDS := 3.0
const STRIP_HIGH := 58.0
const BAR_SIZE := Vector2(220.0, 22.0)
const CARD_SIZE := Vector2(210.0, 150.0)
const PICK_KEYS := [KEY_1, KEY_2, KEY_3]
const PICK_PAD_KEYS := [KEY_KP_1, KEY_KP_2, KEY_KP_3]
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
var frame: Control = null
var strip: Panel = null
var top_line: Label = null
var wave_line: Label = null
var land_line: Label = null
var slain_line: Label = null
var banner_line: Label = null
var door_bar: ProgressBar = null
var door_line: Label = null
var portal_bar: ProgressBar = null
var portal_line: Label = null
var leave_button: Button = null
var results: PanelContainer = null
var result_line: Label = null
var start_panel: PanelContainer = null
var pick_panel: PanelContainer = null
var pick_title: Label = null
var cards: Array = []
var reroll_button: Button = null
var early_button: Button = null
var stick: Control = null
# The finger aiming on a touch screen, and where it is.
var _aim_finger: int = -1
var _aim_screen: Vector2 = Vector2.ZERO
var hud: Node = null
var seed_value: int = 0
# The suite's doors: the mouse, and whether its button is held.
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
	frame = Control.new()
	frame.name = "frame"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	stick = Pad.minigame_stick()
	add_child(stick)
	strip = Panel.new()
	strip.name = "strip"
	var strip_style := StyleBoxFlat.new()
	strip_style.bg_color = Color(0.04, 0.03, 0.05, 0.72)
	strip_style.border_color = Color(COLOUR, 0.35)
	strip_style.border_width_bottom = 2
	strip.add_theme_stylebox_override("panel", strip_style)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(strip, Control.PRESET_TOP_WIDE, Rect2(0, 0, 0, STRIP_HIGH))
	frame.add_child(strip)
	wave_line = _label("wave", 20, COLOUR, Control.PRESET_TOP_LEFT, Vector2(16, 5))
	land_line = _label("land", 14, COLOUR_HINT, Control.PRESET_TOP_LEFT, Vector2(16, 32))
	top_line = _label("top", 20, COLOUR, Control.PRESET_TOP_RIGHT, Vector2(-16, 5))
	slain_line = _label("slain", 14, COLOUR_HINT, Control.PRESET_TOP_RIGHT, Vector2(-16, 32))
	door_bar = _bar("door", -BAR_SIZE.x - 10.0, DOOR_COLOUR)
	door_line = door_bar.get_node("words") as Label
	portal_bar = _bar("portalbar", 10.0, PORTAL_COLOUR)
	portal_line = portal_bar.get_node("words") as Label
	banner_line = _label("banner", 30, COLOUR, Control.PRESET_CENTER, Vector2(0, -80))
	leave_button = Button.new()
	leave_button.name = "leave"
	leave_button.text = "Leave"
	leave_button.focus_mode = Control.FOCUS_NONE
	_place(leave_button, Control.PRESET_TOP_RIGHT, Rect2(-96, STRIP_HIGH + 8.0, 80, 30))
	leave_button.pressed.connect(ask_to_leave)
	frame.add_child(leave_button)
	early_button = Button.new()
	early_button.name = "early"
	early_button.focus_mode = Control.FOCUS_NONE
	early_button.add_theme_color_override("font_color", COLOUR)
	_place(early_button, Control.PRESET_CENTER_TOP, Rect2(-120, STRIP_HIGH + 8.0, 240, 30))
	early_button.pressed.connect(call_early)
	early_button.visible = false
	frame.add_child(early_button)
	_build_pick()
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


func _build_pick() -> void:
	pick_panel = _panel("pick")
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	pick_panel.add_child(column)
	pick_title = _words("Wave 1 held!", 28, COLOUR)
	column.add_child(pick_title)
	column.add_child(_words("Pick one - it lasts the whole run", 16, COLOUR_HINT))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	column.add_child(row)
	for i in 3:
		var card := Button.new()
		card.name = "card%d" % (i + 1)
		card.focus_mode = Control.FOCUS_NONE
		card.custom_minimum_size = CARD_SIZE
		for look in [["normal", 0.0, 0.45], ["hover", 0.05, 1.0], ["pressed", 0.1, 1.0]]:
			var style := StyleBoxFlat.new()
			style.bg_color = Color(0.13, 0.1, 0.09).lightened(float(look[1]))
			style.border_color = Color(COLOUR, float(look[2]))
			style.set_border_width_all(2)
			style.set_corner_radius_all(4)
			card.add_theme_stylebox_override(str(look[0]), style)
		var words := VBoxContainer.new()
		words.name = "words"
		words.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		words.alignment = BoxContainer.ALIGNMENT_CENTER
		words.add_theme_constant_override("separation", 8)
		words.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(words)
		for line in [["name", "", 22, COLOUR], ["does", "", 15, Color(0.95, 0.9, 0.8)], ["level", "", 14, COLOUR_HINT]]:
			var label := _words(str(line[1]), int(line[2]), line[3] as Color)
			label.name = str(line[0])
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.custom_minimum_size = Vector2(CARD_SIZE.x - 20.0, 0.0)
			words.add_child(label)
		card.pressed.connect(choose.bind(i))
		row.add_child(card)
		cards.append(card)
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	foot.add_theme_constant_override("separation", 18)
	column.add_child(foot)
	foot.add_child(_words("Click one", 13, COLOUR_HINT))
	reroll_button = Button.new()
	reroll_button.name = "reroll"
	reroll_button.focus_mode = Control.FOCUS_NONE
	reroll_button.custom_minimum_size = Vector2(150, 30)
	reroll_button.pressed.connect(reroll)
	foot.add_child(reroll_button)


func _words(text: String, size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


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
	frame.add_child(label)
	return label


func _bar(id: String, left: float, colour: Color) -> ProgressBar:
	"""A bar in the strip with its words inside it."""
	var bar := ProgressBar.new()
	bar.name = id
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	back.border_color = Color(colour, 0.6)
	back.set_border_width_all(1)
	back.set_corner_radius_all(3)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(colour, 0.85)
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", back)
	bar.add_theme_stylebox_override("fill", fill)
	_place(bar, Control.PRESET_CENTER_TOP, Rect2(left, (STRIP_HIGH - BAR_SIZE.y) / 2.0, BAR_SIZE.x, BAR_SIZE.y))
	var words := Label.new()
	words.name = "words"
	words.add_theme_font_size_override("font_size", 14)
	words.add_theme_color_override("font_color", Color.WHITE)
	words.add_theme_color_override("font_outline_color", Color.BLACK)
	words.add_theme_constant_override("outline_size", 5)
	words.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	words.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.add_child(words)
	frame.add_child(bar)
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
	results.visible = false
	pick_panel.visible = false
	_leave_armed = 0.0
	start_panel.visible = true
	_centre(start_panel)


func begin() -> void:
	if not start_panel.visible:
		return
	start_panel.visible = false
	run.set_process(true)


func choose(index: int) -> void:
	"""A card picked (a click, or 1, 2 or 3)."""
	if run != null and is_instance_valid(run) and bool(run.call("pick", index)):
		pick_panel.visible = false
		paint()


func reroll() -> void:
	if run != null and is_instance_valid(run) and bool(run.call("reroll")):
		pick_panel.visible = false
		paint()


func call_early() -> void:
	if run != null and is_instance_valid(run):
		run.call("call_early")
		paint()


func drawn_rect() -> Rect2:
	"""Where the picture is drawn in the window: it keeps its shape, centred,
	scaled by the smaller fit."""
	return Pad.drawn_rect(picture, StandScript.VIEW)


func stick_zone() -> Rect2:
	"""Where a thumb lands for the stick: the dark left of the field, from the
	window's edge to the field's, under the strip."""
	var drawn: Rect2 = drawn_rect()
	var fit: float = drawn.size.x / StandScript.VIEW.x
	var field_left: float = drawn.position.x + (StandScript.HALF.x - StandScript.PATH_HALF - 9.0) * fit
	var top: float = drawn.position.y + STRIP_HIGH + 44.0
	return Rect2(Vector2(0.0, top), Vector2(maxf(0.0, field_left), drawn.end.y - top))


func _on_controls(at: Vector2) -> bool:
	"""Is a touch at `at` on the stick's zone or on a button or panel, not the
	field?"""
	if stick.visible and stick_zone().has_point(at):
		return true
	for control in [leave_button, early_button, start_panel, pick_panel, results]:
		if control != null and (control as Control).is_visible_in_tree() and (control as Control).get_global_rect().has_point(at):
			return true
	return false


func _fit_frame() -> void:
	var at: Rect2 = drawn_rect()
	frame.position = at.position
	frame.size = at.size


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
	var touch: bool = TouchControls.active
	if not touch:
		_aim_finger = -1
	if run != null and is_instance_valid(run):
		var held: bool = _aim_finger >= 0 if touch else bool(mouse_held.call())
		if not touch or _aim_finger >= 0:
			run.set("aim", world_from_screen(_aim_screen if touch else mouse_at.call()))
		run.set("casting", held and not start_panel.visible and not results.visible
			and not pick_panel.visible and int(run.get("state")) != StandScript.State.PICK)
	_fit_frame()
	Pad.lay_minigame_stick(stick, touch and not start_panel.visible and not results.visible, stick_zone(),
		get_window() if is_inside_tree() else null, get_viewport().get_visible_rect().size if is_inside_tree() else Vector2.ZERO)
	paint()


func paint() -> void:
	if run == null or not is_instance_valid(run):
		return
	var state: int = int(run.get("state"))
	top_line.text = str(run.call("time_text"))
	var wave: int = int(run.get("wave"))
	wave_line.text = ("Wave %d" % wave) if wave > 0 else "Get ready"
	land_line.text = ("the %s lands" % str(run.call("land_name"))) if wave > 0 else "The Mage's Stand"
	var door: float = float(run.get("door"))
	door_bar.value = door / maxf(1.0, float(run.get("door_most")))
	door_line.text = "Gate broken!" if door <= 0.0 else "Gate %d%%" % roundi(door_bar.value * 100.0)
	var fill := door_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill != null:
		var pulse: float = 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) / 1000.0 * 8.0)
		fill.bg_color = Color(DOOR_COLOUR.lerp(DANGER_COLOUR, pulse), 0.9) if bool(run.call("gate_low")) \
			else Color(DOOR_COLOUR, 0.85)
	early_button.visible = bool(run.call("can_call_early")) and not start_panel.visible
	early_button.text = "Call wave %d early" % (wave + 1)
	portal_bar.value = float(run.get("portal")) / float(StandScript.PORTAL_MOST)
	portal_line.text = "Portal %d%%" % roundi(portal_bar.value * 100.0)
	best = maxi(best, int(run.get("waves_held")))
	slain_line.text = "Slain %d   Best: %s" % [int(run.get("slain")), StandScript.waves_words(best)]
	banner_line.text = "" if start_panel.visible or pick_panel.visible else str(run.get("banner"))
	leave_button.text = "Sure?" if _leave_armed > 0.0 else "Leave"
	if state == StandScript.State.PICK and not pick_panel.visible:
		_show_pick(wave, run.get("offers") as Array)
	elif state != StandScript.State.PICK:
		pick_panel.visible = false
	if state == StandScript.State.LOST and not results.visible:
		result_line.text = str(run.call("result_text"))
		results.visible = true
		_centre(results)


func _show_pick(wave: int, offers: Array) -> void:
	var owed: int = int(run.get("picks_left"))
	pick_title.text = ("Wave %d held!" % wave) + ("   %d picks" % owed if owed > 1 else "")
	var left: int = int(run.get("rerolls"))
	reroll_button.text = "Reroll (%d left)" % left
	reroll_button.disabled = left <= 0
	for i in cards.size():
		var card: Button = cards[i]
		card.visible = i < offers.size()
		if not card.visible:
			continue
		var id: String = str(offers[i])
		var info: Dictionary = StandScript.UPGRADES[id]
		var words: Node = card.get_node("words")
		(words.get_node("name") as Label).text = str(info["name"])
		(words.get_node("name") as Label).add_theme_color_override("font_color",
			EVOLVE_COLOUR if StandScript.EVOLUTIONS.has(id) else COLOUR)
		(words.get_node("does") as Label).text = str(info["does"])
		(words.get_node("level") as Label).text = str(run.call("offer_level_text", id))
	pick_panel.visible = true
	_centre(pick_panel)


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
	# A FINGER ON THE FIELD AIMS (on a touch screen): the first one down that
	# is not on the stick or a button, followed while it moves. Not consumed:
	# the stick and the buttons take their touches as ever.
	var touch := event as InputEventScreenTouch
	if touch != null:
		if touch.pressed and _aim_finger < 0 and not _on_controls(touch.position):
			_aim_finger = touch.index
			_aim_screen = touch.position
		elif not touch.pressed and touch.index == _aim_finger:
			_aim_finger = -1
		return
	var drag := event as InputEventScreenDrag
	if drag != null:
		if drag.index == _aim_finger:
			_aim_screen = drag.position
		return
	# THE GAME BEHIND IT HEARS NO KEYS while this is up. Escape is Leave;
	# Space starts.
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
			ask_to_leave()
		elif key.pressed and not key.echo and key.keycode == KEY_SPACE and start_panel.visible:
			begin()
		elif key.pressed and not key.echo and pick_panel.visible \
				and (PICK_KEYS.has(key.keycode) or PICK_PAD_KEYS.has(key.keycode)):
			choose(maxi(PICK_KEYS.find(key.keycode), PICK_PAD_KEYS.find(key.keycode)))
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if _held != null and is_instance_valid(_held):
		_held.process_mode = _held_mode
