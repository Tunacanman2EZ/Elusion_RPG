# healerrunscreen.gd - the Healer's Run on screen (0.98.0): the run's own
# world in a SubViewport, drawn over everything at a whole multiple, and the
# words round it - the clock, the tier and wave, lives, shots, the boss's health, a
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
# GOLD AT LEAVE, THREE RUNS A DAY, A TUTORIAL (0.99.0). The owner: "gold
# should be rewarded on the screen then moved to char when hitting leave",
# "this minigame can be played 3 times a day", "a tutorial screen also before
# char walks", "just press space to fire meteor". The card's Go asks the
# server first (POST /api/minigames/enter) and hands this its run's id and
# what it pays; the gold counts up on screen (run.gold_now()), and Leave - or
# Again - finishes the run on the server (POST /api/minigames/finish), which
# pays it into the character's purse and answers with the purse. Again asks
# for the next run of the day. The first run of a session opens on the
# tutorial, the healer standing on her landing until Start (or Space).
# Space calls a meteor (run.fire_meteor()).
#
# THREE TIERS (0.100.0): the stage line says the tier and its wave ("Tier 2 of
# 3 - wave 5 of 8") or its keeper; Leave sends how many bosses fell
# (`bosses`, 0-3), and the run counts by the server's "tiers" table
# (RunScript.pays_from()).
#
# GOD MODE (0.100.0), the owner's: "i need a godmode switch that only i can
# see on the screen for this mini game so i can test". A switch under the gold,
# shown only to those the world's god mode is for (Api.GOD_MODE_MIN_ROLE, the
# same gate as the GM panel's Testing tab) and re-checked when pressed. It IS
# that switch - GameState.god_mode - so turning it on here turns it on in the
# world too, and the other way round. A run with it on at any moment
# (run.god_used) says so on the gold line and pays nothing: Leave finishes it
# on the server with nothing reached.
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
# The run on the server (its Go), what it pays, and the HUD to say the gold in.
var run_id: int = 0
var pays: Dictionary = {}
var hud: Node = null
var gold_line: Label = null
var meteor_line: Label = null
var tutorial: PanelContainer = null
# The suite's doors: the two requests and the character's slot.
var finish_request: Callable = Callable(Api, "post")
var enter_request: Callable = Callable(Api, "post")
var slot_now: Callable = Callable(self, "_slot")
var _paid: bool = false
var _busy: bool = false
var god_switch: CheckButton = null
# The suite's door: may this player see the god mode switch.
var may_be_god: Callable = Callable(self, "_may_be_god")
static var _tutorial_seen: bool = false
const TUTORIAL_LINES := [
	"Move with your move keys - she shoots by herself.",
	"Hold sprint to slow down through tight gaps.",
	"Grab an essence: more shots - 2, 4, 6, 8. Past eight, a laser - stronger each time.",
	"Grab a potion: one more life (up to 5).",
	"Grab a meteor, then press Space: it finds the boss.",
	"Three tiers, a boss at the end of each - every land's boss fights its own way.",
	"A fire rises behind you - keep moving.",
	"Gold counts up as you go. Leave to take it.",
]


static func open(tree: SceneTree, run_seed: int = 0, run_on_server: int = 0, what_it_pays: Dictionary = {},
		on_hud: Node = null) -> CanvasLayer:
	var screen: CanvasLayer = (load("res://src/world/healerrun/healerrunscreen.gd") as GDScript).new()
	screen.name = "healerrunscreen"
	screen.set("seed_value", run_seed)
	screen.set("run_id", run_on_server)
	screen.set("pays", what_it_pays)
	screen.set("hud", on_hud)
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
	gold_line = _label("gold", 22, COLOUR, Control.PRESET_TOP_RIGHT, Vector2(-18, 120))
	meteor_line = _label("meteors", 16, COLOUR_HINT, Control.PRESET_TOP_LEFT, Vector2(18, 176))
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
	god_switch = CheckButton.new()
	god_switch.name = "god"
	god_switch.text = "God mode"
	god_switch.focus_mode = Control.FOCUS_NONE
	god_switch.add_theme_color_override("font_color", COLOUR_HINT)
	# On, it reads in the warning colour: there is no mistaking a run that pays nothing.
	god_switch.add_theme_color_override("font_pressed_color", COLOUR_BAD)
	god_switch.add_theme_color_override("font_hover_pressed_color", COLOUR_BAD)
	_place(god_switch, Control.PRESET_TOP_RIGHT, Rect2(-170, 160, 154, 30))
	god_switch.toggled.connect(_on_god_toggled)
	god_switch.visible = false
	add_child(god_switch)
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
	again_button.pressed.connect(again)
	row.add_child(again_button)
	var out := Button.new()
	out.name = "out"
	out.text = "Leave"
	out.focus_mode = Control.FOCUS_NONE
	out.custom_minimum_size = Vector2(110, 34)
	out.pressed.connect(leave)
	row.add_child(out)
	add_child(results)
	tutorial = PanelContainer.new()
	tutorial.name = "tutorial"
	var how := StyleBoxFlat.new()
	how.bg_color = Color(0.1, 0.08, 0.07, 0.94)
	how.border_color = Color(0.85, 0.65, 0.25)
	how.set_border_width_all(3)
	how.set_content_margin_all(20)
	tutorial.add_theme_stylebox_override("panel", how)
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 8)
	tutorial.add_child(lines)
	var title := Label.new()
	title.text = "The Healer's Run"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", COLOUR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lines.add_child(title)
	for words in TUTORIAL_LINES:
		var line := Label.new()
		line.text = str(words)
		line.add_theme_font_size_override("font_size", 17)
		line.add_theme_color_override("font_color", COLOUR_HINT)
		lines.add_child(line)
	var start_button := Button.new()
	start_button.name = "start"
	start_button.text = "Start  (Space)"
	start_button.focus_mode = Control.FOCUS_NONE
	start_button.custom_minimum_size = Vector2(160, 36)
	start_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	start_button.pressed.connect(begin)
	lines.add_child(start_button)
	tutorial.visible = false
	add_child(tutorial)


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
	if not pays.is_empty():
		run.set("pays", RunScript.pays_from(pays))
	run.position = RunScript.HALF
	viewport.add_child(run)
	var may: bool = bool(may_be_god.call())
	god_switch.visible = may
	run.set("god", may and GameState.god_mode)
	god_switch.set_pressed_no_signal(may and GameState.god_mode)
	results.visible = false
	_leave_armed = 0.0
	_lives_seen = -1
	_paid = false
	# THE FIRST RUN OF A SESSION OPENS ON THE TUTORIAL, her standing still
	# on the landing behind it until Start.
	if not _tutorial_seen:
		run.set_process(false)
		tutorial.visible = true
		tutorial.reset_size()
		tutorial.grow_horizontal = Control.GROW_DIRECTION_BOTH
		tutorial.grow_vertical = Control.GROW_DIRECTION_BOTH
		tutorial.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)


func _may_be_god() -> bool:
	return Api.role_at_least(Api.GOD_MODE_MIN_ROLE)


func _on_god_toggled(on: bool) -> void:
	"""The world's god mode, from here: for the owner only, asked again."""
	if not bool(may_be_god.call()):
		god_switch.set_pressed_no_signal(false)
		god_switch.visible = false
		return
	GameState.god_mode = on
	if run != null and is_instance_valid(run):
		run.set("god", on)


func begin() -> void:
	"""The tutorial away: the run's "Get ready", then she walks."""
	tutorial.visible = false
	_tutorial_seen = true
	if run != null and is_instance_valid(run):
		run.set_process(true)


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
	var tier: int = int(run.get("tier"))
	if state == RunScript.State.WON:
		stage_line.text = "Through the gate"
	elif state == RunScript.State.GOAL:
		stage_line.text = "The gate"
	elif state == RunScript.State.BOSS:
		stage_line.text = "Tier %d of %d - the %s keeper" % [tier + 1, RunScript.TIERS,
			str(run.call("land_name", int(run.call("land"))))]
	else:
		stage_line.text = "Tier %d of %d - wave %d of %d" % [tier + 1, RunScript.TIERS,
			int(run.get("wave_in_tier")) + 1, RunScript.WAVES_PER_TIER]
	var lives: int = int(run.get("lives"))
	if _lives_seen >= 0 and lives < _lives_seen:
		flash.color.a = 0.35
	_lives_seen = lives
	lives_line.text = "Lives %d" % lives
	lives_line.add_theme_color_override("font_color", COLOUR_BAD if int(run.get("lives")) <= 1 else COLOUR)
	shots_line.text = "Shots %d" % int(RunScript.SHOT_STEPS[int(run.get("power"))]) \
		+ ((" - laser %d" % int(run.get("laser_level"))) if float(run.get("laser")) > 0.0 else "")
	rank_line.text = "Danger %d" % int(run.call("rank"))
	slain_line.text = "Slain %d" % int(run.get("slain"))
	gold_line.text = ("Gold %d - god mode, pays nothing" if bool(run.get("god_used")) else "Gold %d") \
		% int(run.call("gold_now"))
	var held_meteors: int = int(run.get("meteors"))
	meteor_line.text = ("Meteors %d - Space" % held_meteors) if held_meteors > 0 else ""
	banner_line.text = "" if tutorial.visible else str(run.get("banner"))
	boss_bar.visible = state == RunScript.State.BOSS
	boss_bar.value = float(run.call("boss_share"))
	if _leave_armed > 0.0:
		leave_button.text = "Sure?"
	else:
		leave_button.text = "Leave"
	if (state == RunScript.State.WON or state == RunScript.State.LOST) and not results.visible:
		result_line.text = "%s\n%d gold - yours when you Leave" % [str(run.call("result_text")), int(run.call("gold_now"))] \
			if not bool(run.get("god_used")) else "%s\nGod mode - this run pays nothing" % str(run.call("result_text"))
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
	if hud != null and is_instance_valid(hud) and hud.has_method("_push_message") and gold > 0:
		hud.call("_push_message", "The Healer's Run: %d gold, into your purse." % gold, COLOUR, 0, true)
	close()


func again() -> void:
	"""Again: this run's gold paid, then the day's next run - when there is one."""
	if _busy:
		return
	if not await _pay():
		return
	if run_id == 0:
		start()
		return
	_busy = true
	result_line.text = "Asking for another run..."
	var res: Dictionary = await enter_request.call("/api/minigames/enter",
		{"game": "healerrun", "slot": int(slot_now.call())}, 6.0)
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
	is (or there is no run on the server: a test, or the owner's own)."""
	if run_id == 0 or _paid:
		return true
	if run == null or not is_instance_valid(run):
		return true
	_busy = true
	# Still while it is settled: what is sent is what was reached.
	run.set_process(false)
	var state: int = int(run.get("state"))
	var body := {"run": run_id, "waves": mini(int(run.get("waves_done")), RunScript.TIERS * RunScript.WAVES_PER_TIER),
		"bosses": int(run.get("bosses_beaten")), "goal": state == RunScript.State.WON}
	if bool(run.get("god_used")):
		# GOD MODE PAYS NOTHING: the run is closed on the server, nothing reached.
		body = {"run": run_id, "waves": 0, "bosses": 0, "goal": false}
	var res: Dictionary = await finish_request.call("/api/minigames/finish", body, 8.0)
	_busy = false
	if not is_instance_valid(self):
		return false
	var data: Dictionary = res.get("data", {}) if res.get("data") is Dictionary else {}
	if res.get("ok", false) or int(res.get("status", 0)) == 409:
		_paid = true
		var status: Dictionary = data.get("status", {}) if data.get("status") is Dictionary else {}
		if status.has("gold") and _held != null and is_instance_valid(_held) and _held.has_method("set_gold"):
			_held.call("set_gold", int(status["gold"]))
		return true
	banner_line.text = "Could not reach the server - Leave again to try once more."
	results.visible = true
	result_line.text = "Your gold is waiting: Leave again to take it."
	return false


func _slot() -> int:
	return int(CharacterData.active_character_index)


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
		elif key.pressed and not key.echo and key.keycode == KEY_SPACE:
			if tutorial.visible:
				begin()
			elif run != null and is_instance_valid(run):
				run.call("fire_meteor")
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if _held != null and is_instance_valid(_held):
		_held.process_mode = _held_mode
