# pinballscreen.gd - THE BEHOLDER'S TABLE on screen (0.167.0): the table's
# own 3D world (pinballrun.gd) in a SubViewport drawn over everything, with
# Leave, and at the end the score with Again and Leave.
#
# Opened from the Minigames card (minigamescard.gd), in town, the owner's
# alone while it is built (TESTING). THREE GAMES A DAY PAY (0.168.0): the
# card's Go asks the server for a run (game "pinball") and opens on it with
# the gold's table (`pays`: a gold every points_per_gold points, at most
# `most` a game) and the account's best; the gold counts up on the table's
# panel as the score does (`gold_now()`), and Game Over - or Leave, or
# Again - finishes the run on the server with the score (POST
# /api/minigames/finish), once (`_pay()`). With no games left the table is
# practice (run_id 0): PRACTICE on the panel, nothing sent. The character
# stays standing where it was, still (open() holds it, close() lets it go),
# and the town is not drawn under it (cover()).
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
# ON A PHONE (0.168.0): Leave is bigger (TOUCH_LEAVE_BOX), each new game
# says for HINT_SECONDS which half holds which flippers, and while a ball
# waits on the plunger the screen says how to launch it - in words big
# enough to read on a phone (the panel's own line is 11 px). The table
# draws itself lighter there (pinballrun.gd PHONES).
#
# Leave: the button, or Escape twice while a game is on (once after it).
# Keys are kept from the rest of the game while it is up.
extends CanvasLayer

# THE LOADING COVER (0.168.3): the owner, on his phone, "it still takes to
# long to start the game up if needed we can improvise with a loading screen
# or a countdown". The table's script is loaded by the cover, not preloaded
# here, so the screen itself is light and up at once: the Beholder's eye, the
# name and a bar, each step a frame of its own (the script, the table, the 3D
# board, then two draws behind the cover - a phone's first draw is the slow
# part), then 3, 2, 1, GO over the table and the ball is yours. Again does
# the same on a new table. The suite's tables (headless_run) open at once.
const RUN_PATH := "res://src/world/pinball/pinballrun.gd"
const PayAnswer := preload("res://src/ui/minigames/payanswer.gd")
const EYE_PATH := "res://art/pack/materials/crownedbeholdereye.png"
# each of 3, 2, 1 and GO, by the clock on the wall: a slow phone's frames
# are cut to 0.1 s each by the engine, which would drag the count out
const COUNT_STEP := 0.5
const GO_SECONDS := 0.4
const COVER_FADE := 0.3
const OPEN_STEPS := ["Opening the table", "Setting the table", "Building the board", "Lighting it"]
const AGAIN_STEPS := ["A new table", "Setting the table", "Building the board", "Lighting it"]
static var RunScript: GDScript = null
# OPENS FASTER (0.168.2): the owner, "it takes almost 6 seconds to launch the
# minigame". This screen preloaded the Healer's Run's screen for one line of
# words, and that pulled in the Healer's Run itself, its party and the field
# script - 561 of the 792 ms this script took to load in the sandbox. The
# line is `paid_line()` below now, the same words (the suite holds them
# equal), and the card says "Opening the table..." before the table loads.
const GAME := "pinball"
const GAME_NAME := "The Beholder's Table"
const LAYER := 90
const VIEW := Vector2i(1280, 720)
const GOLD := Color(1.0, 0.82, 0.38)
const CREAM := Color(1.0, 0.95, 0.85)
const HINT := Color(0.82, 0.78, 0.7)
const PILL := Color(0.06, 0.05, 0.08, 0.86)
const LEAVE_BOX := Rect2(1176, 22, 82, 38)
const TOUCH_LEAVE_BOX := Rect2(1146, 14, 120, 54)
const HINT_SECONDS := 5.0
const LEFT_HINT_BOX := Rect2(40, 590, 420, 60)
const RIGHT_HINT_BOX := Rect2(860, 590, 400, 60)
const PLUNGER_HINT_BOX := Rect2(290, 320, 700, 64)
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
# THE SERVER'S RUN (0.168.0): 0 is practice. Its gold's table and the
# account's best, as Go answered; the requests are the suite's to swap.
var run_id: int = 0
var pays: Dictionary = {}
var server_best: int = 0
var enter_request: Callable = Callable(Api, "post")
var finish_request: Callable = Callable(Api, "post")
var slot_now: Callable = func() -> int: return int(CharacterData.active_character_index)
var gold_line: Label = null
var pay_line: Label = null
var again_button: Button = null
var left_hint: Label = null
var right_hint: Label = null
var plunger_hint: Label = null
var _hints_left: float = 0.0

var _covered: CanvasItem = null
var _hidden_layers: Array = []
var _held: Node = null
var _held_mode: Node.ProcessMode = Node.PROCESS_MODE_INHERIT
# the table's own 16:9 rect on a wider screen (_framed())
var frame: Control = null
var _leave_armed: float = 0.0
var _fingers: Dictionary = {}
var _touch_ms: int = -100000
var _mouse_sides: Dictionary = {}
var _paid: bool = false
# A RUN THE SERVER WOULD NOT PAY (0.168.8, payanswer.gd): how many tries
# failed, whether Leave now goes without the gold, and why
var _pay_fails: int = 0
var _go_without: bool = false
var _not_paid_why: String = ""
var _busy: bool = false
var _gold_paid: int = -1
var _held_back: int = 0
var _new_best: bool = false
var _purse_shown: String = "-"
var loading: Control = null
var load_bar: ColorRect = null
var load_words: Label = null
var count_label: Label = null
# while the cover builds the table; the countdown's clock (-1 when not counting)
var _loading: bool = false
var _counting: float = -1.0
var _count_ms: int = 0
var _loads: int = 0


static func open(tree: SceneTree, on_hud: Node = null, run_on_server: int = 0, what_it_pays: Dictionary = {},
		best_known: int = 0) -> CanvasLayer:
	var screen: CanvasLayer = (load("res://src/world/pinball/pinballscreen.gd") as GDScript).new()
	screen.name = "pinballscreen"
	screen.set("hud", on_hud)
	screen.set("run_id", run_on_server)
	screen.set("pays", what_it_pays)
	screen.set("server_best", best_known)
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
	_build_cover()
	_hold_the_character()
	cover(get_tree().current_scene)
	start()


func _framed(parent: Node) -> Control:
	"""A WIDE SCREEN (0.168.12, the owner's 3440 x 1440): the table's
	picture keeps its 16:9, centred, and the screen around it is wider. What
	is placed against the 1280 x 720 table (`_place()`) goes in this frame,
	the picture's own rect, so Leave and the hints stay on the table instead
	of drifting to the screen's far edges."""
	var fit := AspectRatioContainer.new()
	fit.name = "fit"
	fit.ratio = float(VIEW.x) / float(VIEW.y)
	fit.stretch_mode = AspectRatioContainer.STRETCH_FIT
	fit.alignment_horizontal = AspectRatioContainer.ALIGNMENT_CENTER
	fit.alignment_vertical = AspectRatioContainer.ALIGNMENT_CENTER
	fit.set_anchors_preset(Control.PRESET_FULL_RECT)
	fit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(fit)
	var inner := Control.new()
	inner.name = "frame"
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fit.add_child(inner)
	return inner


func _build_words() -> void:
	frame = _framed(self)
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
	frame.add_child(leave_button)
	left_hint = _hint("lefthint", "‹  HOLD: LEFT FLIPPERS", LEFT_HINT_BOX)
	right_hint = _hint("righthint", "RIGHT FLIPPERS: HOLD  ›", RIGHT_HINT_BOX)
	plunger_hint = _hint("plungerhint", "HOLD ANYWHERE TO PULL  ·  LET GO TO LAUNCH", PLUNGER_HINT_BOX)
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
	gold_line = _words("", 17, GOLD)
	gold_line.name = "goldline"
	column.add_child(gold_line)
	best_line = _words("", 15, HINT)
	best_line.name = "bestline"
	column.add_child(best_line)
	pay_line = _words("", 13, HINT)
	pay_line.name = "payline"
	column.add_child(pay_line)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	column.add_child(row)
	again_button = _button("again", "Again", again)
	row.add_child(again_button)
	row.add_child(_button("out", "Leave", leave))


func _build_cover() -> void:
	"""The loading cover over the table, and the countdown's number."""
	loading = ColorRect.new()
	loading.name = "loading"
	(loading as ColorRect).color = Color(0.03, 0.022, 0.05)
	loading.set_anchors_preset(Control.PRESET_FULL_RECT)
	loading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	loading.visible = false
	add_child(loading)
	var on_cover: Control = _framed(loading)
	var eye_tex: Texture2D = load(EYE_PATH) as Texture2D if ResourceLoader.exists(EYE_PATH) else null
	if eye_tex != null:
		var eye := TextureRect.new()
		eye.name = "eye"
		eye.texture = eye_tex
		eye.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		eye.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		eye.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		eye.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_place(eye, Rect2(576, 196, 128, 128))
		on_cover.add_child(eye)
	var title := _words(GAME_NAME.to_upper(), 40, GOLD)
	title.name = "title"
	_place(title, Rect2(240, 338, 800, 56))
	on_cover.add_child(title)
	var track := ColorRect.new()
	track.name = "track"
	track.color = Color(1.0, 1.0, 1.0, 0.08)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(track, Rect2(440, 420, 400, 10))
	on_cover.add_child(track)
	load_bar = ColorRect.new()
	load_bar.name = "bar"
	load_bar.color = GOLD
	load_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	load_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	load_bar.anchor_right = 0.0
	track.add_child(load_bar)
	load_words = _words("", 20, HINT)
	load_words.name = "step"
	_place(load_words, Rect2(340, 444, 600, 36))
	on_cover.add_child(load_words)
	count_label = _words("", 120, CREAM)
	count_label.name = "count"
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count_label.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.08))
	count_label.add_theme_constant_override("outline_size", 18)
	_place(count_label, Rect2(340, 230, 600, 200))
	count_label.visible = false
	frame.add_child(count_label)
	# the words, the number and Leave over the cover (all in the frame)
	move_child(frame.get_parent(), -1)
	move_child(results, -1)


func _hint(id: String, text: String, box: Rect2) -> Label:
	"""A phone's hint: big words on a dark pill over the table."""
	var label := _words(text, 24, CREAM)
	label.name = id
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var pill := _pill_style(Color(PILL, 0.96))
	pill.border_color = Color(GOLD, 0.45)
	label.add_theme_stylebox_override("normal", pill)
	_place(label, box)
	label.visible = false
	frame.add_child(label)
	return label


func _place(item: Control, box: Rect2) -> void:
	"""Anchored to where `box` is on the 1280 x 720 picture."""
	item.anchor_left = box.position.x / VIEW.x
	item.anchor_top = box.position.y / VIEW.y
	item.anchor_right = box.end.x / VIEW.x
	item.anchor_bottom = box.end.y / VIEW.y
	item.offset_left = 0.0
	item.offset_top = 0.0
	item.offset_right = 0.0
	item.offset_bottom = 0.0


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
	again_button.disabled = false
	_paid = false
	_pay_fails = 0
	_go_without = false
	_not_paid_why = ""
	_gold_paid = -1
	_held_back = 0
	_new_best = false
	_purse_shown = "-"
	var touch: bool = bool(on_touch.call())
	_place(leave_button, TOUCH_LEAVE_BOX if touch else LEAVE_BOX)
	leave_button.add_theme_font_size_override("font_size", 20 if touch else 15)
	_hints_left = HINT_SECONDS if touch else 0.0
	run = null
	_counting = -1.0
	count_label.visible = false
	if headless_run:
		_make_run(false)
		return
	_open_steps()


func _make_run(later: bool) -> void:
	"""The table's run: with `later`, paused and its 3D board not yet built."""
	if RunScript == null:
		RunScript = load(RUN_PATH)
	run = RunScript.new()
	run.name = "run"
	run.set("headless", headless_run)
	run.set("seed_now", next_seed)
	run.set("controls_hint", TOUCH_HINT if bool(on_touch.call()) else KEYS_HINT)
	run.set("build_later", later)
	run.set("paused", later)
	viewport.add_child(run)
	run.connect("game_over", _on_game_over)


func _open_steps() -> void:
	"""The cover up, the table built a step a frame behind it, then the count."""
	_loads += 1
	var mine: int = _loads
	var words: Array = OPEN_STEPS if _loads == 1 else AGAIN_STEPS
	_loading = true
	loading.visible = true
	loading.modulate.a = 1.0
	for part in loading.get_children():
		(part as CanvasItem).visible = true
	leave_button.visible = false
	_cover_step(0, words)
	if not await _shown(mine):
		return
	if RunScript == null:
		RunScript = load(RUN_PATH)
	_cover_step(1, words)
	if not await _shown(mine):
		return
	_make_run(true)
	_cover_step(2, words)
	if not await _shown(mine):
		return
	run.call("build_world_now")
	_cover_step(3, words)
	# two draws of the table behind the cover: a phone readies its shaders
	if not await _shown(mine) or not await _shown(mine):
		return
	load_bar.anchor_right = 1.0
	_loading = false
	leave_button.visible = true
	for part in loading.get_children():
		(part as CanvasItem).visible = false
	_counting = 0.0
	_count_ms = Time.get_ticks_msec()
	_show_count()


func _cover_step(i: int, words: Array) -> void:
	load_words.text = str(words[i]) + "..."
	load_bar.anchor_right = float(i + 1) / float(words.size() + 1)


func _shown(mine: int) -> bool:
	"""After the cover has been drawn as it is now: false if the screen went
	or a newer table began meanwhile."""
	await get_tree().process_frame
	await get_tree().process_frame
	return is_inside_tree() and mine == _loads


func loading_now() -> bool:
	return _loading


func counting() -> bool:
	return _counting >= 0.0


func _show_count() -> void:
	"""3, 2, 1 over the table as the cover fades, then GO - the ball's."""
	var fade: float = clampf(1.0 - _counting / COVER_FADE, 0.0, 1.0)
	loading.modulate.a = fade
	loading.visible = fade > 0.0
	var numbers: float = COUNT_STEP * 3.0
	if _counting < numbers:
		var step: int = int(_counting / COUNT_STEP)
		count_label.text = str(3 - step)
		count_label.modulate.a = 1.0 - 0.5 * fmod(_counting, COUNT_STEP) / COUNT_STEP
		count_label.visible = true
		return
	if run != null and is_instance_valid(run) and bool(run.get("paused")) and not _paid:
		run.set("paused", false)
	if _counting < numbers + GO_SECONDS:
		count_label.text = "GO!"
		count_label.modulate.a = 1.0 - (_counting - numbers) / GO_SECONDS
		count_label.visible = true
		return
	count_label.visible = false
	_counting = -1.0


func again() -> void:
	"""Again: this game's gold paid, then the day's next game when there is
	one - practice when there is not."""
	if _busy:
		return
	if not await _pay():
		return
	if run_id == 0:
		start()
		return
	_busy = true
	result_line.text = "Asking for another game..."
	var res: Dictionary = await enter_request.call("/api/minigames/enter", {"game": GAME, "slot": int(slot_now.call())}, 6.0)
	_busy = false
	if not is_instance_valid(self):
		return
	var data: Dictionary = res.get("data", {}) if res.get("data") is Dictionary else {}
	if res.get("ok", false) and data.has("run"):
		run_id = int(data["run"])
		if data.get("pays") is Dictionary:
			pays = data["pays"]
		server_best = maxi(server_best, int(data.get("best_score", 0)))
		start()
		return
	if int(res.get("status", 0)) == 409:
		# the day's three are played: the next is practice
		run_id = 0
		start()
		return
	result_line.text = "Could not reach the server - try again."


func playing() -> bool:
	return run != null and is_instance_valid(run) and not bool(run.get("over"))


func gold_now() -> int:
	"""What this game's score is worth by the server's table - 0 in practice."""
	if run_id == 0 or run == null or not is_instance_valid(run):
		return 0
	var per: int = maxi(1, int(pays.get("points_per_gold", 2000)))
	@warning_ignore("integer_division")
	var worth: int = int(run.get("score")) / per
	return mini(int(pays.get("most", 3000)), worth)


func purse_words() -> String:
	"""The table's panel's gold line: so far, MOST once it can pay no more, or
	PRACTICE."""
	if run_id == 0:
		return "PRACTICE"
	var gold: int = gold_now()
	return "%s GOLD%s" % [_thousands(gold), "  ·  MOST" if gold >= int(pays.get("most", 3000)) else ""]


func _on_game_over() -> void:
	var score: int = int(run.get("score"))
	var first: bool = score > best
	best = maxi(best, score)
	result_line.text = "Score  %s" % _thousands(score)
	if run_id == 0:
		gold_line.text = ""
		best_line.text = "A new best!" if first and score > 0 else "Best this sitting  %s" % _thousands(best)
		pay_line.text = "Practice: it pays nothing."
		_show_results()
		return
	gold_line.text = "Paying %s gold..." % _thousands(gold_now())
	best_line.text = ""
	pay_line.text = ""
	_show_results()
	if await _pay():
		_paid_words()


static func _thousands(n: int) -> String:
	"""1234567 as "1,234,567" (pinballrun.gd's own, not loaded for it)."""
	var digits: String = str(absi(n))
	var out: String = ""
	while digits.length() > 3:
		out = "," + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return digits + out


static func paid_line(game_name: String, paid: int, held: int) -> String:
	"""The gold into the purse and, past the day's allowance, what the server
	held back - the Healer's Run's words (healerrunscreen.gd paid_line())."""
	if held > 0 and paid > 0:
		return "%s: %s gold into your purse - %s held back, today's minigame gold is full." % [
			game_name, _thousands(paid), _thousands(held)]
	if held > 0:
		return "%s: today's minigame gold is full - %s held back." % [game_name, _thousands(held)]
	if paid > 0:
		return "%s: %s gold, into your purse." % [game_name, _thousands(paid)]
	return ""


func _show_results() -> void:
	results.visible = true
	results.reset_size()
	results.grow_horizontal = Control.GROW_DIRECTION_BOTH
	results.grow_vertical = Control.GROW_DIRECTION_BOTH
	results.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)


func _paid_words() -> void:
	"""The results' lines once the server has paid."""
	var paid: int = maxi(0, _gold_paid)
	gold_line.text = "%s gold into your purse" % _thousands(paid)
	if _held_back > 0:
		gold_line.text += "  (%s held back: the day's minigame gold is full)" % _thousands(_held_back)
	best_line.text = ("A new best!  %s" if _new_best else "Your best  %s") % _thousands(server_best)
	pay_line.text = ""
	_show_results()


func _pay() -> bool:
	"""This game finished on the server and its gold paid - once. True when
	it is (or it is practice). Not reached, the screen says so and stays."""
	if run_id == 0 or _paid or _go_without or run == null or not is_instance_valid(run):
		return true
	_busy = true
	# still while it is settled: the score sent is the score
	run.set("paused", true)
	var body := {"run": run_id, "score": int(run.get("score"))}
	var res: Dictionary = await finish_request.call("/api/minigames/finish", body, 8.0)
	_busy = false
	if not is_instance_valid(self):
		return false
	var data: Dictionary = res.get("data", {}) if res.get("data") is Dictionary else {}
	if res.get("ok", false) or int(res.get("status", 0)) == 409:
		_paid = true
		if res.get("ok", false):
			_gold_paid = maxi(0, int(data.get("gold", 0)))
			_held_back = maxi(0, int(data.get("held_back", 0)))
			server_best = maxi(server_best, int(data.get("best", 0)))
			_new_best = bool(data.get("new_best", false))
			var said: String = paid_line(GAME_NAME, _gold_paid, _held_back)
			if said != "" and hud != null and is_instance_valid(hud) and hud.has_method("_push_message"):
				hud.call("_push_message", said, GOLD, 0, true)
		var status: Dictionary = data.get("status", {}) if data.get("status") is Dictionary else {}
		if status.has("gold") and _held != null and is_instance_valid(_held) and _held.has_method("set_gold"):
			_held.call("set_gold", int(status["gold"]))
		return true
	_pay_fails += 1
	_go_without = PayAnswer.refused(res) or _pay_fails >= 2
	_not_paid_why = PayAnswer.why_not(res)
	result_line.text = _not_paid_why
	gold_line.text = PayAnswer.waiting_line(_go_without)
	best_line.text = ""
	pay_line.text = ""
	_show_results()
	return false


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
		if not _loading:
			_key(key)
		get_viewport().set_input_as_handled()
		return
	if _loading:
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
	if _counting >= 0.0:
		var now: int = Time.get_ticks_msec()
		_counting += maxf(delta, (now - _count_ms) / 1000.0)
		_count_ms = now
		_show_count()
	elif not _loading:
		_hints_left = maxf(0.0, _hints_left - delta)
	var touch: bool = bool(on_touch.call())
	var fade: float = clampf(_hints_left, 0.0, 1.0)
	for hint in [left_hint, right_hint]:
		(hint as Label).visible = touch and fade > 0.0 and playing() and not results.visible
		(hint as Label).modulate.a = fade
	plunger_hint.visible = touch and waiting() and not results.visible
	if run != null and is_instance_valid(run):
		var words: String = purse_words()
		if words != _purse_shown:
			_purse_shown = words
			run.set("purse_text", words)
			run.set("purse_colour", HINT if run_id == 0 else GOLD)


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
	"""Leave: this game's gold paid by the server, then out. Not reached, the
	screen says so and stays - Leave again tries again."""
	if _busy:
		return
	if not await _pay():
		if gold_now() <= 0:
			# nothing earned: nothing to lose by going
			close()
		return
	if _go_without and not _paid and hud != null and is_instance_valid(hud) and hud.has_method("_push_message"):
		hud.call("_push_message", PayAnswer.not_paid_line(GAME_NAME, _not_paid_why), GOLD, 0, true)
	close()


func close() -> void:
	if _held != null and is_instance_valid(_held):
		_held.process_mode = _held_mode
	_held = null
	uncover()
	queue_free()


func cover(scene: Node) -> void:
	"""The world under the screen goes undrawn while it is up: only a scene
	that draws, and is drawn now. And every layer under this one (the HUD,
	the touch buttons; 0.168.4, for a phone that ran hot): the screen is
	opaque, and they went on being drawn beneath it every frame."""
	if scene is CanvasItem and scene != self and (scene as CanvasItem).visible:
		_covered = scene
		_covered.visible = false
	if not is_inside_tree():
		return
	for node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		var under := node as CanvasLayer
		if under == self or is_ancestor_of(under) or not under.visible or under.layer >= LAYER:
			continue
		under.visible = false
		_hidden_layers.append(under)


func uncover() -> void:
	if _covered != null and is_instance_valid(_covered):
		_covered.visible = true
	_covered = null
	for under in _hidden_layers:
		if is_instance_valid(under):
			(under as CanvasLayer).visible = true
	_hidden_layers.clear()


func _exit_tree() -> void:
	# however the screen goes, what it hid comes back
	uncover()
