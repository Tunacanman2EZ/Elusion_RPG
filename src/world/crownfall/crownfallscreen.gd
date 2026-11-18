# crownfallscreen.gd - CROWNFALL on screen (0.162.0): the run's own world
# (crownfallrun.gd) in a SubViewport, drawn over everything, with Leave, the
# kingdom map's Start, and at the end how far you got with Again and Leave.
# The run draws everything else itself - its bar, its panels, the kingdom map.
#
# Opened from the Minigames card, in town only (minigamescard.gd): the
# character stays standing where it was, still (open() stops it, close() lets
# it go).
#
# THE STORY (crownfallmaps.gd STORY) is told the first time a character opens
# it (field.gd story_seen(), key STORY_KEY), and only from the card (a HUD) -
# never in a suite. Any key, click or tap skips it.
#
# GOLD, THREE RUNS A DAY, AND HOW FAR YOU GOT: the card's Go asks the server
# first (POST /api/minigames/enter, game "crownfall") and hands this its run's
# id, what each map pays (`pays`) and how far the account has got (`progress`,
# the maps cleared in order). The kingdom map opens on the next map to clear;
# any map up to it may be started from. The gold counts up on screen
# (run.gold_now()), and Leave - or Again - finishes the run on the server
# (POST /api/minigames/finish with the map it started on and the maps it
# cleared), which pays it into the character's purse, held to the time the
# run took, and moves `progress` on. Again asks for the day's next run. A run
# with no id (the owner's own test, or the suite) is practice: it pays
# nothing, and says so.
#
# THE CONTROLS:
#   - a mouse: the paddle follows it; a click launches the waiting ball. On
#     the kingdom map a click picks a map, a click on the picked one starts.
#   - keys: the move keys steer the paddle (a move key takes over from the
#     mouse until the mouse moves again); Space or Enter launches. On the
#     kingdom map up and down pick, Space or Enter starts.
#   - a phone (0.166.0, the owner: "using a slider to control the movement
#     maybe just tap on the screen to fire bullets or magnet"; 0.166.3: "it
#     is working but it is easy for it to stop working"): in a run
#     - a thumb that lands left of the field is the slider's (drawn at the
#       left panel's foot) and moves the paddle SLIDER_GAIN times as far as
#       it moves, wherever it goes after. The newest thumb there always
#       takes it, so a thumb whose lift never arrived (off the screen's
#       edge, a notification, a system swipe) cannot hold it for ever;
#     - a finger that lands on the field and slides moves the paddle the
#       same way, wherever it landed (DRAG ANYWHERE);
#     - a finger on the field is also a tap (run.tap()): while a ball waits
#       on the paddle (aiming, or held by the Magnet) the tap is its lift,
#       and only if it moved less than TAP_SLACK - so sliding to place the
#       paddle never launches; while a ball is flying the tap is the press,
#       at once (the Laser's volley, which on a phone never fires by
#       itself), and that finger may slide the paddle too.
#     One thumb slides while another taps. Every finger is forgotten when a
#     run starts or ends, when the game loses focus or is paused, and when
#     the screen hides (_forget_fingers()). On the kingdom map a tap picks,
#     and Start starts.
# The ball waits on the paddle with its aim swaying (crownfallrun.gd): launch
# when it points where you want.
#
# Leave: the button, or Escape - twice while a run is on, once before or
# after it. Keys are kept from the rest of the game while it is up.
#
# THE TOWN UNDER IT (0.166.2, the owner: "my computer is running a little
# hard playing this i can tell because my fan kicks up"): the screen covers
# the whole window, so while it is up the town is not drawn (cover()); it
# goes on running, and is shown again the moment the screen goes.
#
# No class_name; the card loads it by path.
extends CanvasLayer

const RunScript := preload("res://src/world/crownfall/crownfallrun.gd")
const Maps := preload("res://src/world/crownfall/crownfallmaps.gd")
# A Leave in words, the day's allowance with it - the Healer's Run's, one rule.
const HealerScreen := preload("res://src/world/healerrun/healerrunscreen.gd")
const Field := preload("res://src/world/field.gd")
const LAYER := 90
const GAME := "crownfall"
const STORY_KEY := "#crownfall"
const LEAVE_ARMED_SECONDS := 3.0
const GOLD := Color(1.0, 0.82, 0.38)
const CREAM := Color(1.0, 0.95, 0.85)
const HINT := Color(0.82, 0.78, 0.7)
const RED := Color(0.92, 0.25, 0.28)
const PILL := Color(0.06, 0.05, 0.08, 0.86)
# The buttons are laid out on the run's picture (1280 x 720): Leave at the
# right end of its top bar, past the lives; Start at the kingdom map's foot,
# right of the picked map's line.
const HUD_BASE := Vector2(1280, 720)
const LEAVE_BOX := Rect2(1176, 22, 82, 38)
const START_BOX := Rect2(1000, 640, 240, 50)
const MOUSE_MOVED := 2.0
# How far ahead of the paddle a held move key puts where it is going.
const KEY_LEAD := 220.0
# A tap is a finger that moved less than this (px on the picture).
const TAP_SLACK := 14.0
# The slider moves the paddle this many times as far as the thumb moves.
const SLIDER_GAIN := 3.0

var run: Node2D = null
var viewport: SubViewport = null
var _covered: CanvasItem = null
var picture: TextureRect = null
var frame: Control = null
var flash: ColorRect = null
var leave_button: Button = null
var start_button: Button = null
var results: PanelContainer = null
var result_line: Label = null
var best_line: Label = null
var gold_line: Label = null
var again_button: Button = null
var story: CanvasLayer = null
var hud: Node = null
# The run on the server (0: practice), what each map pays, and how far the
# account has got (maps cleared in order).
var run_id: int = 0
var pays: Dictionary = {}
var progress: int = 0
# The suite's doors: the mouse, the keys, the server, the character's slot,
# and whether this is a phone.
var mouse_at: Callable = Callable(self, "_mouse_at")
var keys_way: Callable = Callable(self, "_keys_way")
var finish_request: Callable = Callable(Api, "post")
var enter_request: Callable = Callable(Api, "post")
var slot_now: Callable = Callable(self, "_slot")
var on_touch: Callable = Callable(self, "_on_touch")

var _by_mouse: bool = true
var _finger: int = -1
var _finger_moved: float = 0.0
var _slider_finger: int = -1
# Fingers on the field in a run: index -> {"moved": px on the picture,
# "tapped": its tap already made}.
var _field_fingers: Dictionary = {}
var _was_playing: bool = false
var _flash_left: float = 0.0
var _held: Node = null
var _held_mode: Node.ProcessMode = Node.PROCESS_MODE_INHERIT
var _leave_armed: float = 0.0
var _paid: bool = false
var _busy: bool = false
# What the server paid at Leave and held back (A DAY'S MINIGAME GOLD); -1
# before it says.
var _gold_paid: int = -1
var _held_back: int = 0


static func open(tree: SceneTree, on_hud: Node = null, run_on_server: int = 0, what_it_pays: Dictionary = {},
		how_far: int = 0) -> CanvasLayer:
	var screen: CanvasLayer = (load("res://src/world/crownfall/crownfallscreen.gd") as GDScript).new()
	screen.name = "crownfallscreen"
	screen.set("hud", on_hud)
	screen.set("run_id", run_on_server)
	screen.set("pays", what_it_pays)
	screen.set("progress", maxi(0, how_far))
	tree.root.add_child(screen)
	return screen


func _ready() -> void:
	layer = LAYER
	var back := ColorRect.new()
	back.name = "back"
	back.color = Color(0.02, 0.02, 0.04)
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
	cover(get_tree().current_scene)
	visibility_changed.connect(_on_shown_or_hidden)
	start()
	tell_story()


func _build_words() -> void:
	frame = Control.new()
	frame.name = "frame"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	leave_button = Button.new()
	leave_button.name = "leave"
	leave_button.text = "Leave"
	leave_button.focus_mode = Control.FOCUS_NONE
	_place(leave_button, LEAVE_BOX)
	for look in [["normal", 0.0], ["hover", 0.06], ["pressed", 0.1]]:
		var style := _pill_style(Color(PILL.lightened(float(look[1])), 0.92))
		style.border_color = Color(GOLD, 0.35)
		leave_button.add_theme_stylebox_override(str(look[0]), style)
	leave_button.add_theme_color_override("font_color", CREAM)
	leave_button.add_theme_font_size_override("font_size", 15)
	leave_button.pressed.connect(ask_to_leave)
	frame.add_child(leave_button)
	start_button = _button("start", "Start  (Space)", begin)
	start_button.add_theme_font_size_override("font_size", 18)
	_place(start_button, START_BOX)
	frame.add_child(start_button)
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


func _place(control: Control, box: Rect2) -> void:
	"""A button where `box` is on the run's picture, scaled with it."""
	control.anchor_left = box.position.x / HUD_BASE.x
	control.anchor_top = box.position.y / HUD_BASE.y
	control.anchor_right = box.end.x / HUD_BASE.x
	control.anchor_bottom = box.end.y / HUD_BASE.y


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
	for look in [["normal", Color(GOLD, 0.18)], ["hover", Color(GOLD, 0.3)], ["pressed", Color(GOLD, 0.42)],
			["disabled", Color(0.3, 0.3, 0.3, 0.2)]]:
		var style := _pill_style(look[1] as Color)
		style.border_color = Color(GOLD, 0.6)
		b.add_theme_stylebox_override(str(look[0]), style)
	b.add_theme_color_override("font_color", CREAM)
	b.add_theme_font_size_override("font_size", 16)
	b.pressed.connect(does)
	return b


func _panel(id: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = id
	var style := _pill_style(Color(0.06, 0.05, 0.08, 0.95))
	style.set_corner_radius_all(16)
	style.border_color = Color(GOLD, 0.4)
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
# THE STORY
# =============================================================================

func tells_story() -> bool:
	"""The kingdoms' story: once a character, opened from the card (a HUD)."""
	return hud != null and not Field.story_seen(Field.story_key() + STORY_KEY)


func tell_story() -> void:
	if not tells_story() or story_playing():
		return
	Field.mark_story_seen(Field.story_key() + STORY_KEY)
	story = StoryScreen.new()
	add_child(story)
	story.play(Maps.STORY)


func story_playing() -> bool:
	return story != null and is_instance_valid(story) and not story.is_queued_for_deletion()


func _skip_story() -> void:
	if story_playing():
		story.call("_finish")


# =============================================================================
# A RUN
# =============================================================================

func start() -> void:
	"""The kingdom map, the next map to clear picked - the first, or Again."""
	if run != null and is_instance_valid(run):
		run.queue_free()
	run = RunScript.new()
	run.name = "crownfall"
	run.set("pays", pays)
	run.connect("life_lost", _on_life_lost)
	viewport.add_child(run)
	run.call("show_kingdoms", progress)
	_forget_fingers()
	results.visible = false
	again_button.disabled = false
	_paid = false
	_gold_paid = -1
	_held_back = 0
	_leave_armed = 0.0
	paint()


func begin() -> void:
	"""Start (or Space): a run from the map picked, when it is open."""
	if run == null or not is_instance_valid(run) or story_playing():
		return
	if int(run.get("state")) != RunScript.State.KINGDOMS:
		return
	var picked: int = int(run.get("selected"))
	if not bool(run.call("can_start_at", picked)):
		return
	_skip_story()
	run.call("begin", picked)
	_forget_fingers()
	paint()


func pick(index: int) -> void:
	"""A map picked on the kingdom map: an open one only."""
	if run == null or not is_instance_valid(run) or index < 0:
		return
	if bool(run.call("can_start_at", index)):
		run.set("selected", index)
	paint()


func step_kingdom(way: int) -> void:
	"""Left or right along the crests: the next made kingdom with a map open."""
	if run == null or not is_instance_valid(run):
		return
	var at: int = int(run.call("kingdom_index", int(run.get("selected")))) + way
	while at >= 0 and at < Maps.KINGDOMS.size():
		var index: int = int(run.call("open_map_in", at))
		if index >= 0:
			pick(index)
			return
		at += way


func step_pick(way: int) -> void:
	"""Up or down the kingdom's open maps."""
	var picked: int = int(run.get("selected")) + way
	if bool(run.call("can_start_at", picked)):
		run.set("selected", picked)
	paint()


func playing() -> bool:
	"""A run on, not over: a ball waiting or flying, or a map just cleared."""
	return run != null and is_instance_valid(run) and bool(run.call("playing"))


func _on_life_lost() -> void:
	_flash_left = 0.35


# =============================================================================
# THE CONTROLS
# =============================================================================

func world_from_screen(at: Vector2) -> Vector2:
	"""A point on the window, on the run's picture: the picture keeps its
	shape, centred, scaled by the smaller fit."""
	var fit: float = _fit()
	if fit <= 0.0:
		return Vector2.ZERO
	var box: Rect2 = picture.get_global_rect()
	var corner: Vector2 = box.position + (box.size - RunScript.VIEW * fit) / 2.0
	return (at - corner) / fit


func _fit() -> float:
	var box: Rect2 = picture.get_global_rect()
	return minf(box.size.x / RunScript.VIEW.x, box.size.y / RunScript.VIEW.y)


func drawn_rect() -> Rect2:
	var fit: float = _fit()
	var box: Rect2 = picture.get_global_rect()
	var size: Vector2 = RunScript.VIEW * fit
	return Rect2(box.position + (box.size - size) / 2.0, size)


func _mouse_at() -> Vector2:
	return get_viewport().get_mouse_position()


func _keys_way() -> Vector2:
	return Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")


func _slot() -> int:
	return int(CharacterData.active_character_index)


func _on_touch() -> bool:
	return TouchControls.active


func _process(delta: float) -> void:
	# a run started or ended under a finger: it is forgotten
	var on: bool = playing()
	if on != _was_playing:
		_was_playing = on
		_forget_fingers()
	_leave_armed = maxf(0.0, _leave_armed - delta)
	_flash_left = maxf(0.0, _flash_left - delta)
	flash.color = Color(RED, 0.28 * _flash_left / 0.35)
	if run != null and is_instance_valid(run) and playing() and not results.visible:
		var way: float = (keys_way.call() as Vector2).x
		if absf(way) > 0.0:
			_by_mouse = false
			run.set("target_x", float(run.get("paddle_x")) + way * KEY_LEAD)
		elif not _by_mouse and _finger < 0 and not bool(on_touch.call()):
			run.set("target_x", float(run.get("paddle_x")))
		elif _by_mouse and not bool(on_touch.call()):
			run.set("target_x", world_from_screen(mouse_at.call()).x)
	_fit_frame()
	paint()


func _fit_frame() -> void:
	var at: Rect2 = drawn_rect()
	frame.position = at.position
	frame.size = at.size


func paint() -> void:
	if run == null or not is_instance_valid(run):
		return
	leave_button.text = "Sure?" if _leave_armed > 0.0 else "Leave"
	var touch: bool = bool(on_touch.call())
	run.set("launch_hint", "Tap the field to launch" if touch else "Click or Space to launch")
	run.set("touch_slider", touch)
	run.set("map_hint", "Tap Start to enter %s" if touch else "Enter / Space: enter %s   ·   Esc: leave")
	var on_map: bool = int(run.get("state")) == RunScript.State.KINGDOMS
	start_button.visible = on_map and not story_playing()
	start_button.disabled = not bool(run.call("can_start_at", int(run.get("selected"))))
	if int(run.get("state")) == RunScript.State.OVER and not results.visible:
		_show_results()


func _show_results() -> void:
	"""How far the run got - the crown taken, or where the walls held - the
	maps it cleared and their gold."""
	var cleared: int = int(run.get("cleared"))
	var last: int = int(run.get("map_index"))
	var boss_info: Variant = Maps.MAPS[last].get("boss")
	if int(run.get("lives")) <= 0:
		result_line.text = "The walls of %s held" % str(Maps.MAPS[last]["name"])
	elif boss_info is Dictionary and bool(boss_info.get("crown", false)) and bool(run.call("final_map")):
		# THE SEVENTH CROWN: Crownfall's end
		result_line.text = "The seventh crown is yours - every land is healed"
	elif boss_info is Dictionary and bool(boss_info.get("crown", false)):
		result_line.text = "%s's crown is yours" % str(boss_info.get("name", "The ruler"))
	elif boss_info is Dictionary:
		result_line.text = "%s is defeated - the next maps are coming" % str(boss_info.get("name", "The guardian"))
	else:
		result_line.text = "Every map cleared - more are coming"
	best_line.text = "%d %s cleared   ·   score %s" % [cleared, "map" if cleared == 1 else "maps",
		RunScript.thousands(int(run.get("score")))]
	_say_gold()
	results.visible = true
	_centre(results)


func _say_gold() -> void:
	if run_id == 0:
		gold_line.text = "Practice - no gold"
		return
	var gold: int = _gold_paid if _gold_paid >= 0 else int(run.call("gold_now"))
	gold_line.text = "+%s gold" % RunScript.thousands(gold)
	if _held_back > 0:
		gold_line.text += "   (%s held back: the day's minigame gold is full)" % RunScript.thousands(_held_back)


func _input(event: InputEvent) -> void:
	# WHILE THE STORY PLAYS any key, click or tap skips it.
	if story_playing():
		var pressed: bool = (event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo) \
			or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed) \
			or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
		if pressed:
			_skip_story()
			paint()
		if event is InputEventKey or event is InputEventMouseButton:
			get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_finger_input(event)
		return
	var motion := event as InputEventMouseMotion
	if motion != null and motion.device != InputEvent.DEVICE_ID_EMULATION and motion.relative.length() > MOUSE_MOVED:
		_by_mouse = true
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT \
			and click.device != InputEvent.DEVICE_ID_EMULATION and not _on_a_button(click.position):
		_by_mouse = true
		_press_at(world_from_screen(click.position), click.double_click)
	# THE GAME BEHIND IT HEARS NO KEYS while this is up. Escape is Leave.
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			_key(key)
		get_viewport().set_input_as_handled()


func _key(key: InputEventKey) -> void:
	if key.keycode == KEY_ESCAPE:
		ask_to_leave()
		return
	var go: bool = key.keycode == KEY_SPACE or key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER
	var state: int = int(run.get("state")) if run != null and is_instance_valid(run) else -1
	if state == RunScript.State.KINGDOMS:
		if go:
			begin()
		elif key.is_action(&"move_up") or key.keycode == KEY_UP:
			step_pick(-1)
		elif key.is_action(&"move_down") or key.keycode == KEY_DOWN:
			step_pick(1)
		elif key.is_action(&"move_left") or key.keycode == KEY_LEFT:
			step_kingdom(-1)
		elif key.is_action(&"move_right") or key.keycode == KEY_RIGHT:
			step_kingdom(1)
	elif go and (state == RunScript.State.AIM or state == RunScript.State.PLAY):
		# a launch, or a ball the Magnet holds let go
		run.call("launch")


func _press_at(at: Vector2, twice: bool) -> void:
	"""A click or a tap on the picture, at `at` on it."""
	if run == null or not is_instance_valid(run) or results.visible:
		return
	var state: int = int(run.get("state"))
	if state == RunScript.State.KINGDOMS:
		var index: int = int(run.call("pick_at", at))
		if index < 0:
			# a kingdom's crest: its next map to clear
			index = int(run.call("open_map_in", int(run.call("kingdom_at", at))))
		if index >= 0 and index == int(run.get("selected")) and (twice or not bool(on_touch.call())):
			begin()
		else:
			pick(index)
	elif state == RunScript.State.AIM or state == RunScript.State.PLAY:
		run.call("launch")


func _finger_input(event: InputEvent) -> void:
	"""A PHONE (the header's THE CONTROLS): in a run a finger landing left of
	the field takes the slider (the newest always); one landing on the field
	slides the paddle too, and taps - at once while a ball flies, on its lift
	(if it hardly moved) while a ball waits on the paddle. Before and after a
	run the first finger down, lifted without moving far, is a tap. Not
	consumed: Godot's own click from it still presses the buttons."""
	if run == null or not is_instance_valid(run):
		return
	var touch := event as InputEventScreenTouch
	if touch != null:
		if touch.pressed:
			if _on_a_button(touch.position):
				return
			_by_mouse = false
			if playing():
				_field_fingers.erase(touch.index)
				if world_from_screen(touch.position).x < RunScript.ARENA.position.x:
					# the newest thumb takes the slider, whatever held it
					_slider_finger = touch.index
					run.set("target_x", float(run.get("paddle_x")))
				else:
					if touch.index == _slider_finger:
						_slider_finger = -1
					var tapped: bool = not _ball_waits()
					_field_fingers[touch.index] = {"moved": 0.0, "tapped": tapped}
					if _slider_finger < 0 and _field_fingers.size() == 1:
						run.set("target_x", float(run.get("paddle_x")))
					if tapped:
						run.call("tap")
			elif _finger < 0:
				_finger = touch.index
				_finger_moved = 0.0
		else:
			if touch.index == _slider_finger:
				_slider_finger = -1
			if _field_fingers.has(touch.index):
				var f: Dictionary = _field_fingers[touch.index]
				_field_fingers.erase(touch.index)
				if playing() and not bool(f["tapped"]) and float(f["moved"]) < TAP_SLACK:
					run.call("tap")
			if touch.index == _finger:
				_finger = -1
				if _finger_moved < TAP_SLACK:
					_press_at(world_from_screen(touch.position), false)
		return
	var drag := event as InputEventScreenDrag
	if drag == null:
		return
	var moved: float = drag.relative.x / maxf(_fit(), 0.001)
	if (drag.index == _slider_finger or _field_fingers.has(drag.index)) and playing():
		if _field_fingers.has(drag.index):
			var f: Dictionary = _field_fingers[drag.index]
			f["moved"] = float(f["moved"]) + absf(moved)
		run.set("target_x", clampf(float(run.get("target_x")) + moved * SLIDER_GAIN, RunScript.ARENA.position.x,
			RunScript.ARENA.end.x))
	elif drag.index == _finger:
		_finger_moved += absf(moved)


func _ball_waits() -> bool:
	"""A ball sits on the paddle: aiming before the launch, or held by the
	Magnet. Then a finger on the field taps on its lift, not its press."""
	var state: int = int(run.get("state"))
	if state == RunScript.State.AIM:
		return true
	if state == RunScript.State.PLAY:
		for b in run.get("balls"):
			if (b as Dictionary).has("stuck"):
				return true
	return false


func _forget_fingers() -> void:
	"""No finger is held over a run starting or ending, the game losing focus
	or being paused, or the screen hiding - so a lift that never arrived
	cannot leave the slider dead."""
	_slider_finger = -1
	_finger = -1
	_finger_moved = 0.0
	_field_fingers.clear()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT \
			or what == NOTIFICATION_APPLICATION_PAUSED:
		_forget_fingers()


func _on_shown_or_hidden() -> void:
	if not visible:
		_forget_fingers()


func _on_a_button(at: Vector2) -> bool:
	for b in [leave_button, start_button, again_button]:
		var button: Button = b
		if button != null and button.is_visible_in_tree() and button.get_global_rect().has_point(at):
			return true
	return results.visible and results.get_global_rect().has_point(at)


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
	var said: String = HealerScreen.paid_line("Crownfall", gold, _held_back)
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
		if run != null and is_instance_valid(run):
			progress = maxi(progress, int(run.get("furthest")))
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
		if data.has("progress"):
			progress = maxi(0, int(data["progress"]))
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
	run.set("running_by_clock", false)
	var body := {"run": run_id, "from": int(run.get("start_index")), "cleared": int(run.get("cleared"))}
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
		if data.has("progress"):
			progress = maxi(progress, int(data["progress"]))
		var status: Dictionary = data.get("status", {}) if data.get("status") is Dictionary else {}
		if status.has("gold") and _held != null and is_instance_valid(_held) and _held.has_method("set_gold"):
			_held.call("set_gold", int(status["gold"]))
		return true
	run.set("running_by_clock", true)
	if not results.visible:
		results.visible = true
		_centre(results)
	result_line.text = "Could not reach the server"
	gold_line.text = "Your gold is waiting: Leave again to take it."
	return false


func close() -> void:
	if _held != null and is_instance_valid(_held):
		_held.process_mode = _held_mode
	_held = null
	uncover()
	queue_free()


func cover(scene: Node) -> void:
	"""The world under the screen goes undrawn while it is up (THE TOWN UNDER
	IT): only a scene that draws, and is drawn now."""
	if scene is CanvasItem and scene != self and (scene as CanvasItem).visible:
		_covered = scene
		_covered.visible = false


func uncover() -> void:
	if _covered != null and is_instance_valid(_covered):
		_covered.visible = true
	_covered = null


func _exit_tree() -> void:
	uncover()
	if _held != null and is_instance_valid(_held):
		_held.process_mode = _held_mode
