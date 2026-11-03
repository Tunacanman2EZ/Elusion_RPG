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
# WITH THE PARTY (0.105.0; the owner: "make it to where you can join with your
# party"). In a party (Party.members), with a server that seats the run a room
# per party (Presence.healer_rooms()), the run gets a party node (healerparty.gd) and
# this player's presence says where her healer runs (Presence.state_override)
# while the party's healers are drawn in the run (Presence.world_override,
# run.others). It opens on the start panel every time: the room's leader
# presses Start for everyone, the others wait for it; alone, Start is yours.
# Each player's own run of the day, each paid at Leave.
#
# READY, A COUNTDOWN, AND THE PARTY'S BOARD (0.105.0; the owner: "we need a
# ready for all players then a countdown and still have the option to leave
# incase some one goes afk", "i want the screen to show players and total
# accumulation for the party and who is dead"). With the party in the room
# the start panel lists who is here and who is ready, and Start is Ready
# (Space too); everyone ready, every screen counts three seconds and begins
# together (healerparty.gd). Opened from the card with the party
# (`enter_at_start`), the screen has no run of the day yet: it asks for it
# when the count starts (or at Start alone), so Leave before that costs
# nothing - and Again goes back to the start panel. During and after the run
# the board (`board`) lists each player - lives, out or through, kills, their
# gold - and the party's gold added up.
#
# TUNING (the owner's): "Tuning" under the god switch opens sliders for the
# run's numbers (healerrun.gd TUNE_*), kept on this computer; mouse only, as
# every key is the run's. A tuned run pays nothing.
#
# No class_name; open() is how it is made.
extends CanvasLayer

const RunScript := preload("res://src/world/healerrun/healerrun.gd")
const Pad := preload("res://src/ui/touchpad.gd")
const PartyScript := preload("res://src/world/healerrun/healerparty.gd")
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
var party_line: Label = null
var start_button: Button = null
var board: RichTextLabel = null
# THE METEORS ON HAND, bottom right (0.106.0): one picture a meteor held, and
# the next one filling as it recharges (RunScript.METEORS_BASE, METEOR_RECHARGE).
var meteor_box: VBoxContainer = null
# The meteor art at twice its size, made once for every screen (_build_meteors()).
static var _big_rock: Texture2D = null
# On a phone: the move stick (touchpad.gd, a minigame's own), and the meteors
# are tapped (0.110.1).
var stick: Control = null
# The tutorial's lines, worded for keys or for a phone (_word_for_touch()).
var _tutorial_lines: Array = []
var _worded: int = -1
var meteor_slots: Array = []
var tune_button: Button = null
var tune_panel: PanelContainer = null
var _tune_rows: Dictionary = {}
# Opened with the party and no run of the day: it is asked for at the count.
var enter_at_start: bool = false
var _entering: bool = false
# What the start panel says about asking for the run, when it went wrong.
var _lobby_said: String = ""
# The run began without a run of the day (the server said no): why.
var _no_run: String = ""
# The suite's door: whether the server seats the run a room per party.
var party_rooms: Callable = Callable(self, "_party_rooms")
var party_link: Node = null
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
	"Grab an essence: more shots - 2, 4, 6, 8. Past eight, a laser - its red middle hits critical.",
	"Grab a meteor shield: it takes the next hit for you.",
	"Grab a potion: one more life (up to 5).",
	"Space calls a meteor down on the boss - three to start, each back in 30 s; grab more.",
	"Three tiers, a boss at the end of each - every land's boss fights its own way.",
	"A fire rises behind you - keep moving.",
	"Gold counts up as you go. Leave to take it.",
]
# The same on a phone (0.110.2): the stick, a gentle push, the meteors tapped.
const TOUCH_LINES := {
	0: "Move with the stick - she shoots by herself.",
	1: "Push it a little to go slowly through tight gaps.",
	5: "Tap the screen to drop a meteor on the boss - three to start, each back in 30 s.",
}
# The stick stands in the dark left of the run, under the words there (0.110.2).
const STICK_TOP := 200.0


static func open(tree: SceneTree, run_seed: int = 0, run_on_server: int = 0, what_it_pays: Dictionary = {},
		on_hud: Node = null, with_party: bool = false) -> CanvasLayer:
	var screen: CanvasLayer = (load("res://src/world/healerrun/healerrunscreen.gd") as GDScript).new()
	screen.name = "healerrunscreen"
	screen.set("seed_value", run_seed)
	screen.set("run_id", run_on_server)
	screen.set("pays", what_it_pays)
	screen.set("hud", on_hud)
	screen.set("enter_at_start", with_party and run_on_server == 0)
	tree.root.add_child(screen)
	return screen


func _ready() -> void:
	layer = LAYER
	RunScript.load_tune()
	var back := ColorRect.new()
	back.name = "back"
	back.color = Color(0.0, 0.0, 0.0)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_STOP
	# A TAP ON THE FIELD drops a meteor, as Space does (_on_field_touched()).
	back.gui_input.connect(_on_field_touched)
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
	# THE STICK ON A PHONE (0.110.1): under the words and buttons, so they
	# take a touch first.
	stick = Pad.minigame_stick()
	add_child(stick)
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
	_build_meteors()
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
	tune_button = Button.new()
	tune_button.name = "tunebutton"
	tune_button.text = "Tuning"
	tune_button.toggle_mode = true
	tune_button.focus_mode = Control.FOCUS_NONE
	_place(tune_button, Control.PRESET_TOP_RIGHT, Rect2(-110, 194, 94, 28))
	tune_button.toggled.connect(_on_tune_toggled)
	tune_button.visible = false
	add_child(tune_button)
	_build_tuning()
	board = RichTextLabel.new()
	board.name = "board"
	board.bbcode_enabled = true
	board.fit_content = true
	board.scroll_active = false
	board.autowrap_mode = TextServer.AUTOWRAP_OFF
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_theme_font_size_override("normal_font_size", 15)
	board.add_theme_color_override("default_color", COLOUR_HINT)
	board.add_theme_color_override("font_outline_color", Color.BLACK)
	board.add_theme_constant_override("outline_size", 5)
	_place(board, Control.PRESET_TOP_LEFT, Rect2(18, 206, 300, 140))
	board.visible = false
	add_child(board)
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
		_tutorial_lines.append(line)
	party_line = Label.new()
	party_line.name = "partyline"
	party_line.add_theme_font_size_override("font_size", 17)
	party_line.add_theme_color_override("font_color", COLOUR)
	party_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	party_line.visible = false
	lines.add_child(party_line)
	start_button = Button.new()
	start_button.name = "start"
	start_button.text = "Start  (Space)"
	start_button.focus_mode = Control.FOCUS_NONE
	start_button.custom_minimum_size = Vector2(160, 36)
	start_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	start_button.pressed.connect(begin)
	lines.add_child(start_button)
	tutorial.visible = false
	add_child(tutorial)


func _build_meteors() -> void:
	"""The bottom right: METEORS_MOST meteor pictures (twice their size, each
	a clock that fills as it recharges) over "Space"."""
	meteor_box = VBoxContainer.new()
	meteor_box.name = "meteorbox"
	meteor_box.alignment = BoxContainer.ALIGNMENT_END
	# A TAP ON THE METEORS CALLS ONE (0.110.1): a phone has no Space.
	meteor_box.mouse_filter = Control.MOUSE_FILTER_STOP
	meteor_box.gui_input.connect(_on_meteors_touched)
	var row := HBoxContainer.new()
	row.name = "meteorrow"
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meteor_box.add_child(row)
	var rock: Texture2D = load(RunScript.METEOR_TEXTURE) as Texture2D
	var big: Texture2D = rock
	if rock != null:
		if _big_rock == null:
			# A COPY OF THE ART, MADE ONCE (2 Nov; the owner's run: "Too many
			# pixels for image"). get_image() can hand back the texture's own
			# image - a headless run does - so resizing it doubled the meteor's
			# picture every time a screen was made, until it was too big to be.
			var image: Image = rock.get_image().duplicate() as Image
			if image.is_compressed():
				image.decompress()
			image.resize(image.get_width() * 2, image.get_height() * 2, Image.INTERPOLATE_NEAREST)
			_big_rock = ImageTexture.create_from_image(image)
		big = _big_rock
	for i in RunScript.METEORS_MOST:
		var slot := TextureProgressBar.new()
		slot.name = "meteor%d" % i
		slot.texture_under = big
		slot.texture_progress = big
		slot.tint_under = Color(0.25, 0.22, 0.2, 0.7)
		slot.fill_mode = TextureProgressBar.FILL_CLOCKWISE
		slot.min_value = 0.0
		slot.max_value = 1.0
		slot.step = 0.0
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(slot)
		meteor_slots.append(slot)
	var key := Label.new()
	key.name = "meteorkey"
	key.text = "Meteors - Space"
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	key.add_theme_font_size_override("font_size", 14)
	key.add_theme_color_override("font_color", COLOUR_HINT)
	key.add_theme_color_override("font_outline_color", Color.BLACK)
	key.add_theme_constant_override("outline_size", 5)
	meteor_box.add_child(key)
	_place(meteor_box, Control.PRESET_BOTTOM_RIGHT, Rect2(-260, -84, 244, 70))
	add_child(meteor_box)


func _on_meteors_touched(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	var click := event as InputEventMouseButton
	# Not the click Godot makes of a first finger's tap (DEVICE_ID_EMULATION):
	# that tap is here already, and one tap fired two meteors.
	var pressed: bool = (touch != null and touch.pressed) \
		or (click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT
			and click.device != InputEvent.DEVICE_ID_EMULATION)
	if not pressed:
		return
	meteor_box.accept_event()
	if run != null and is_instance_valid(run) and not tutorial.visible:
		run.call("fire_meteor")


# TAP THE SCREEN TO DROP A METEOR (0.110.3; the owner, on a phone: "tap the
# screen to drop meteor"). A finger anywhere on the run - not the stick's
# dark left, a button or a panel, which take their own touches - calls one
# down on the boss, as Space does. A touch only: a mouse click on the field
# does nothing, as before. (The black `back` hears it: it lies under all,
# full size, at the screen's origin, so its touch is in the screen's units.)
func _on_field_touched(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	if touch == null or not touch.pressed:
		return
	if stick != null and stick.visible and stick_zone().has_point(touch.position):
		return
	if run == null or not is_instance_valid(run) or tutorial.visible or results.visible:
		return
	get_viewport().set_input_as_handled()
	run.call("fire_meteor")


func paint_meteors() -> void:
	"""Each slot: held (full), recharging (filling), to come back (dark) or
	not there at all (past METEORS_BASE, unless looted)."""
	var key := meteor_box.get_node_or_null("meteorkey") as Label
	if key != null:
		key.text = "Meteors - tap" if TouchControls.active else "Meteors - Space"
	var held: int = int(run.get("meteors"))
	var charge: float = float(run.get("meteor_charge"))
	for i in meteor_slots.size():
		var slot: TextureProgressBar = meteor_slots[i]
		slot.visible = i < maxi(held, RunScript.METEORS_BASE)
		if i < held:
			slot.value = 1.0
		elif i == held:
			slot.value = charge
		else:
			slot.value = 0.0


func _build_tuning() -> void:
	"""The owner's sliders: one a number of RunScript.TUNE_ORDER, its value
	beside its name, Defaults, and what tuning does."""
	tune_panel = PanelContainer.new()
	tune_panel.name = "tuning"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.06, 0.92)
	style.border_color = Color(0.85, 0.65, 0.25)
	style.set_border_width_all(2)
	style.set_content_margin_all(10)
	tune_panel.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	tune_panel.add_child(column)
	for which in RunScript.TUNE_ORDER:
		var said := Label.new()
		said.name = "%s_said" % which
		said.add_theme_font_size_override("font_size", 13)
		said.add_theme_color_override("font_color", COLOUR_HINT)
		column.add_child(said)
		var span: Array = RunScript.TUNE_RANGES[which]
		var slider := HSlider.new()
		slider.name = str(which)
		slider.min_value = float(span[0])
		slider.max_value = float(span[1])
		slider.step = float(span[2])
		slider.focus_mode = Control.FOCUS_NONE
		slider.custom_minimum_size = Vector2(260, 16)
		slider.value_changed.connect(_on_tune_changed.bind(str(which)))
		column.add_child(slider)
		_tune_rows[str(which)] = [said, slider]
	var defaults := Button.new()
	defaults.name = "defaults"
	defaults.text = "Defaults"
	defaults.focus_mode = Control.FOCUS_NONE
	defaults.pressed.connect(tune_defaults)
	column.add_child(defaults)
	var note := Label.new()
	note.text = "Your runs, and the runs you lead.\nA tuned run pays nothing."
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", COLOUR_BAD)
	column.add_child(note)
	_place(tune_panel, Control.PRESET_TOP_RIGHT, Rect2(-300, 226, 284, 0))
	tune_panel.visible = false
	add_child(tune_panel)


func _on_tune_toggled(on: bool) -> void:
	if not bool(may_be_god.call()):
		tune_button.set_pressed_no_signal(false)
		tune_button.visible = false
		tune_panel.visible = false
		return
	tune_panel.visible = on
	_show_tuning()


func _show_tuning() -> void:
	"""Each slider and its words, from the tuning as it stands."""
	for which in _tune_rows:
		var row: Array = _tune_rows[which]
		var value: float = float(RunScript.tune.get(which, RunScript.TUNE_DEFAULTS[which]))
		(row[1] as HSlider).set_value_no_signal(value)
		(row[0] as Label).text = "%s: %s" % [str(RunScript.TUNE_NAMES[which]), tune_text(which, value)]


static func tune_text(which: String, value: float) -> String:
	"""A tuning number as the owner reads it: a share as a percent, a count
	as a count, a scale as times."""
	match which:
		"party_health", "party_keeper", "events":
			return "%d%%" % roundi(value * 100.0)
		"party_crowd":
			return "%d" % roundi(value)
	return "x%.2f" % value


func _on_tune_changed(value: float, which: String) -> void:
	if not bool(may_be_god.call()):
		return
	RunScript.tune[which] = value
	RunScript.save_tune()
	_show_tuning()


func tune_defaults() -> void:
	if not bool(may_be_god.call()):
		return
	RunScript.tune = RunScript.TUNE_DEFAULTS.duplicate()
	RunScript.save_tune()
	_show_tuning()


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
	var with_party: bool = bool(party_rooms.call())
	if with_party:
		var party: Node = PartyScript.new()
		party.name = "party"
		party.set("run", run)
		if party_link != null:
			party.set("link", party_link)
		run.set("party", party)
		run.add_child(party)
		party.connect("start_now", _on_start_now)
		party.connect("counting_began", _on_counting_began)
	viewport.add_child(run)
	if with_party and party_link == null:
		Presence.state_override = Callable(run, "presence_state")
		Presence.world_override = run.get("others")
	var may: bool = bool(may_be_god.call())
	god_switch.visible = may
	run.set("god", may and GameState.god_mode)
	god_switch.set_pressed_no_signal(may and GameState.god_mode)
	tune_button.visible = may
	if not may:
		tune_button.set_pressed_no_signal(false)
		tune_panel.visible = false
	elif tune_panel.visible:
		_show_tuning()
	results.visible = false
	_lobby_said = ""
	_no_run = ""
	_leave_armed = 0.0
	_lives_seen = -1
	_paid = false
	# THE FIRST RUN OF A SESSION OPENS ON THE TUTORIAL, her standing still
	# on the landing behind it until Start.
	party_line.visible = with_party
	# Opened without a run of the day, it opens there too: Start asks for it.
	if not _tutorial_seen or with_party or enter_at_start:
		run.set_process(false)
		tutorial.visible = true
		tutorial.reset_size()
		tutorial.grow_horizontal = Control.GROW_DIRECTION_BOTH
		tutorial.grow_vertical = Control.GROW_DIRECTION_BOTH
		tutorial.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)


func _party_rooms() -> bool:
	"""In a party, with a server that seats the run a room per party. Alone,
	the run is as it always was."""
	return Presence.healer_rooms() and Party.members.size() > 1


func _party() -> Node:
	return run.get("party") if run != null and is_instance_valid(run) else null


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
	"""Start (or Space). With the party here it is Ready - and Not ready -
	and the count starts everyone together; alone, the tutorial away and
	the run's "Get ready" (with the run of the day asked for first, when the
	screen was opened without one)."""
	var party: Node = _party()
	if party != null and bool(party.call("active")):
		if float(party.get("counting")) < 0.0:
			party.call("set_ready", not bool(party.get("said_ready")))
		paint()
		return
	if not await _have_a_run():
		paint()
		return
	if is_instance_valid(self) and tutorial.visible:
		_go()


func _on_start_now() -> void:
	"""The count reached nought (or the leader's run began): go."""
	if tutorial.visible:
		_go()


func _on_counting_began() -> void:
	"""The count began: the run of the day, asked for now - when the server
	says no, this player is not ready, and the count stops."""
	if await _have_a_run():
		return
	if not is_instance_valid(self):
		return
	var party: Node = _party()
	if run != null and is_instance_valid(run) and bool(run.get("begun")):
		_no_run = _lobby_said
	elif party != null:
		party.call("set_ready", false)


func _have_a_run() -> bool:
	"""The day's run on the server: true when there is one (or the screen
	needs none). Opened with the party, it is asked for here, once."""
	if not enter_at_start or run_id != 0:
		return true
	if _entering:
		return false
	_entering = true
	_lobby_said = "Asking the server for your run..."
	var res: Dictionary = await enter_request.call("/api/minigames/enter",
		{"game": "healerrun", "slot": int(slot_now.call())}, 6.0)
	_entering = false
	if not is_instance_valid(self):
		return false
	var data: Dictionary = res.get("data", {}) if res.get("data") is Dictionary else {}
	if res.get("ok", false) and data.has("run"):
		run_id = int(data["run"])
		if data.get("pays") is Dictionary:
			pays = data["pays"]
			if run != null and is_instance_valid(run):
				run.set("pays", RunScript.pays_from(pays))
		_lobby_said = ""
		return true
	_lobby_said = str(data.get("message", "No runs left today.")) if int(res.get("status", 0)) == 409 \
		else "Could not reach the server - try again."
	return false


func _go() -> void:
	tutorial.visible = false
	_tutorial_seen = true
	if run != null and is_instance_valid(run):
		run.call("begin_run")
		run.set_process(true)


func _process(delta: float) -> void:
	_leave_armed = maxf(0.0, _leave_armed - delta)
	flash.color.a = maxf(0.0, flash.color.a - delta / HIT_FLASH * 0.35)
	_lay_stick()
	paint()


func _lay_stick() -> void:
	"""The stick, mounted in stick_zone()."""
	Pad.lay_minigame_stick(stick, TouchControls.active, stick_zone(), get_window() if is_inside_tree() else null,
		get_viewport().get_visible_rect().size if is_inside_tree() else Vector2.ZERO)


func stick_zone() -> Rect2:
	"""Where the stick stands (0.110.2): the dark left of the run, from the
	window's edge to the path's wall, under the words there - off the field,
	so a thumb hides none of it. It sat on the field's left (0.110.1)."""
	var drawn: Rect2 = Pad.drawn_rect(picture, RunScript.VIEW)
	var fit: float = drawn.size.x / RunScript.VIEW.x
	var wall: float = drawn.position.x + (RunScript.HALF.x - RunScript.PATH_HALF - 8.0) * fit
	var top: float = maxf(drawn.position.y, 0.0) + STICK_TOP
	return Rect2(Vector2(0.0, top), Vector2(maxf(0.0, wall), maxf(0.0, drawn.end.y - top)))


func _word_for_touch() -> void:
	"""The tutorial in the words of the keys, or of a phone's stick and taps
	(0.110.2) - whichever is in hand now."""
	var touch: int = 1 if TouchControls.active else 0
	if touch == _worded:
		return
	_worded = touch
	for k in _tutorial_lines.size():
		(_tutorial_lines[k] as Label).text = str(TOUCH_LINES[k]) if touch == 1 and TOUCH_LINES.has(k) else str(TUTORIAL_LINES[k])


static func key_hint(words: String, touch: bool) -> String:
	"""A button's words, with its key beside them unless on a phone."""
	return words if touch else words + "  (Space)"


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
	gold_line.text = "Gold %d" % int(run.call("gold_now"))
	if bool(run.get("god_used")):
		gold_line.text += " - god mode, pays nothing"
	elif bool(run.get("tune_used")):
		gold_line.text += " - tuned, pays nothing"
	elif _no_run != "":
		gold_line.text += " - not paid: " + _no_run
	# The meteors are the bottom right's now (paint_meteors()).
	meteor_line.text = ""
	_word_for_touch()
	paint_meteors()
	banner_line.text = "" if tutorial.visible else str(run.get("banner"))
	var party: Node = _party()
	if party != null and party_line != null:
		var here: bool = bool(party.call("active"))
		if here:
			party_line.text = lobby_text(party)
			var counting: float = float(party.get("counting"))
			start_button.text = key_hint("Not ready" if bool(party.get("said_ready")) else "Ready", TouchControls.active)
			start_button.disabled = counting >= 0.0 or _entering
			if int(run.get("players")) > 1:
				top_line.text += "   party of %d" % int(run.get("players"))
		else:
			party_line.text = "Your party joins when they press Go too - wait for them here, or Start alone." \
				+ ("\n" + _lobby_said if _lobby_said != "" else "")
			start_button.text = key_hint("Start alone", TouchControls.active)
			start_button.disabled = _entering
		board.visible = not tutorial.visible and (here or int(run.get("players")) > 1)
		if board.visible:
			board.text = board_text(party)
	elif party_line != null:
		# Alone: the panel says only what went wrong asking for the run.
		party_line.visible = _lobby_said != ""
		party_line.text = _lobby_said
		board.visible = false
		start_button.text = key_hint("Start", TouchControls.active)
	boss_bar.visible = state == RunScript.State.BOSS
	boss_bar.value = float(run.call("boss_share"))
	if _leave_armed > 0.0:
		leave_button.text = "Sure?"
	else:
		leave_button.text = "Leave"
	if (state == RunScript.State.WON or state == RunScript.State.LOST) and not results.visible:
		result_line.text = "%s\n%d gold - yours when you Leave" % [str(run.call("result_text")), int(run.call("gold_now"))]
		if bool(run.get("god_used")):
			result_line.text = "%s\nGod mode - this run pays nothing" % str(run.call("result_text"))
		elif bool(run.get("tune_used")):
			result_line.text = "%s\nTuned - this run pays nothing" % str(run.call("result_text"))
		elif _no_run != "":
			result_line.text = "%s\nNot paid: %s" % [str(run.call("result_text")), _no_run]
		results.visible = true
		results.reset_size()
		results.grow_horizontal = Control.GROW_DIRECTION_BOTH
		results.grow_vertical = Control.GROW_DIRECTION_BOTH
		results.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)


func lobby_text(party: Node) -> String:
	"""The start panel with the party here: who is, who is ready, the count."""
	var lines: Array = []
	var counting: float = float(party.get("counting"))
	if counting >= 0.0:
		lines.append("Starting in %d..." % maxi(1, ceili(counting)))
	else:
		lines.append("Your party - everyone presses Ready, then a count of three.")
	for row in party.call("roster"):
		var is_ready: bool = int(row["flags"]) & 1 != 0
		lines.append("%s%s - %s" % [str(row["name"]), " (you)" if bool(row["me"]) else "",
			"ready" if is_ready else ("joining..." if not bool(row["heard"]) else "not ready")])
	if _lobby_said != "":
		lines.append(_lobby_said)
	return "\n".join(lines)


func board_text(party: Node) -> String:
	"""The party's board: each player - lives, out or through, kills, gold -
	and the party's gold added up."""
	var rows: Array = party.call("roster")
	var lines: Array = ["[color=#%s]Party of %d - %s gold[/color]" % [COLOUR.to_html(false), rows.size(),
		thousands(int(party.call("party_gold")))]]
	for row in rows:
		var flags: int = int(row["flags"])
		var status: String = "%d lives" % int(row["lives"])
		var colour: Color = COLOUR_HINT
		if flags & 2 != 0:
			status = "through"
			colour = COLOUR
		elif flags & 4 != 0:
			status = "out"
			colour = COLOUR_BAD
		elif int(row["lives"]) == 1:
			status = "1 life"
		lines.append("[color=#%s]%s - %s - %d slain - %s[/color]" % [colour.to_html(false),
			str(row["name"]).replace("[", "[lb]"), status, int(row["kills"]), thousands(int(row["gold"]))])
	return "\n".join(lines)


static func thousands(n: int) -> String:
	"""A whole number with commas: 20000 reads 20,000."""
	var digits: String = str(absi(n))
	var out: String = ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-" if n < 0 else "") + digits + out


func ask_to_leave() -> void:
	"""Leave - asked twice while a run is on; before it begins, and once it
	is over, at once."""
	var state: int = int(run.get("state")) if run != null and is_instance_valid(run) else RunScript.State.LOST
	var over: bool = state == RunScript.State.WON or state == RunScript.State.LOST
	var waiting: bool = run != null and is_instance_valid(run) and not bool(run.get("begun"))
	if over or waiting or _leave_armed > 0.0:
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
	if enter_at_start:
		# WITH THE PARTY: back to the start panel; the next run of the day is
		# asked for at the count.
		run_id = 0
		start()
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
	if bool(run.get("god_used")) or bool(run.get("tune_used")):
		# GOD MODE, AND A TUNED RUN, PAY NOTHING: the run is closed on the
		# server, nothing reached.
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
	_let_presence_go()
	queue_free()


func _let_presence_go() -> void:
	"""Back in town: this player's presence is the character's again."""
	if party_link == null and Presence.state_override.is_valid():
		Presence.state_override = Callable()
		Presence.world_override = null


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
	_let_presence_go()
