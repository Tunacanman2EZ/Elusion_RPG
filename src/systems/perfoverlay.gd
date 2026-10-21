# perfoverlay.gd — an on-screen readout of what the game is actually costing,
# so "can we handle more bosses" has a number instead of an opinion.
#
# THE OWNER PANEL SHOWS IT: the "Performance" switch on the Testing tab, through
# set_shown(). It was the backslash key, in debug builds only, until 0.7.1 (the
# owner, 6 Oct: "add to menu instead and remove backslash"), when every debug
# key went in favour of the panel. This reads no keys now.
#
# IN ANY BUILD, BECAUSE THE PANEL IS THE GATE. The key needed a debug build so
# it could not ship to players; the panel opens for the owner only, so the
# readout can be shown on the real exported game - which is the one whose
# numbers matter. It grants nothing. It reads a few numbers and draws them.
#
# FOR STRESS TESTS TOO (0.63.0). The owner, filling the Big Field with 366
# monsters: "i need to upgrade the performance read out". So it also says how
# many frames hitched, what the physics tick and the rest of the frame
# (scripts and drawing) cost against their own budgets, and how many monsters
# are in the area - awake, and asleep (enemysleeper.gd) - which is what a
# crowd of monsters actually spends.
#
# BUILT IN CODE, NO .tscn. A scene for this would be one more file the editor
# rewrites from its in-memory copy whenever it happens to be open, for a Label
# and a CanvasLayer that are four lines to construct.
extends CanvasLayer


# How often the readout refreshes, in seconds.
#
# NOT EVERY FRAME, AND THIS IS THE WHOLE REASON THE NUMBER IS TRUSTWORTHY.
# Setting Label.text re-shapes and re-lays out the string, which at 180fps is a
# measurable cost of its own - a per-frame overlay measures a game that is
# running an overlay, and reports the slowdown it caused as if the game caused
# it. Five samples a second is faster than an eye reads and cheap enough to
# disappear into the noise.
const SAMPLE_INTERVAL := 0.2

# Lines are padded to this width so the numbers sit in a column and a change is
# visible as movement rather than as re-reading.
const LABEL_WIDTH := 9

# The frame budget the `frame` row compares against, in milliseconds.
#
# 16.67ms IS 60fps, AND IT IS THE NUMBER TO BUDGET AGAINST rather than any peak.
# Change it to 6.94 if you decide the game targets 144.
const TARGET_FRAME_MS := 1000.0 / 60.0

# A HITCH is a frame half as long again as the budget - 25 ms at 60 fps - the
# stutter a player sees. Not "over budget": on a 60 Hz screen every frame
# lands a hair either side of 16.67 ms, and counting those counts nothing.
const HITCH_MS := TARGET_FRAME_MS * 1.5


var _label: Label
var _accum: float = 0.0

# THE WORST FRAME SINCE YOU TURNED IT ON, which is the number a stress test is
# actually about. Current FPS during a 65-pillar carpet tells you what this
# instant costs; the minimum tells you whether the fight ever became unplayable,
# and that is the one the player felt. Reset by toggling off and on.
var _worst_fps: float = 0.0

# Since you turned it on, like the worst frame: every frame counted, the ones
# that hitched, and the worst physics tick and script time.
var _frames: int = 0
var _hitches: int = 0
var _worst_physics_ms: float = 0.0
var _worst_process_ms: float = 0.0

# HOW BUSY A FRAME IS, AGAINST HOW LONG IT TAKES (0.69.2). The owner's
# screenshot of the 8x Big Field: fps 15, frame 66.67 ms, 64% of frames
# hitching - and physics 0.75 ms a tick, process 9.5 ms. The game was held at
# Settings.BACKGROUND_FPS (its window in the background, or the screen
# resting) and the rest of each 66 ms was waiting. A held frame is not a slow
# one, so the frame row cannot say what the game costs while held; this does:
# the process step plus every physics tick the frame ran, averaged over the
# sample.
var _busy_ms_sum: float = 0.0
var _busy_frames: int = 0
var _busy_ms: float = 0.0
var _last_physics_frames: int = 0

# THE GRAPHICS CARD'S SHARE (0.69.2): the viewport's measured render time,
# which Godot only measures when asked. 0 where the renderer cannot say (the
# browser's).
var _measuring: bool = false


func _ready() -> void:
	# ALWAYS, so the readout keeps updating while the game is paused. Reading
	# node counts on a paused frame is how you inspect a spike that already
	# happened instead of chasing it live.
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Above the HUD. The HUD is what this is drawn over, not around.
	layer = 128

	_label = Label.new()
	_label.position = Vector2(12, 12)
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", Color(0.75, 1.0, 0.8))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("outline_size", 4)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

	visible = false


func set_shown(on: bool) -> void:
	"""Show or hide the readout. Showing starts a fresh "worst", so it measures
	from the moment you asked rather than from whenever it was last open."""
	if on and not visible:
		_worst_fps = 0.0
		_frames = 0
		_hitches = 0
		_worst_physics_ms = 0.0
		_worst_process_ms = 0.0
		_busy_ms_sum = 0.0
		_busy_frames = 0
		_busy_ms = 0.0
		_last_physics_frames = Engine.get_physics_frames()
		_accum = SAMPLE_INTERVAL   # redraw on the very next frame, not in 0.2s
	visible = on
	_measure_render_time(on)


func _measure_render_time(on: bool) -> void:
	if on == _measuring or not is_inside_tree():
		return
	_measuring = on
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), on)


func gpu_ms() -> float:
	"""What the graphics card spent on the last frame, in ms, or 0 when this
	renderer does not measure it."""
	if not _measuring or not is_inside_tree():
		return 0.0
	return RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())


func busy_ms() -> float:
	"""The frame's own work, averaged over the last sample: process plus the
	physics ticks it ran. Next to `frame`, the difference is waiting - for a
	cap, V-Sync or the graphics card."""
	return _busy_ms


func is_shown() -> bool:
	return visible


func _process(delta: float) -> void:
	if not visible:
		return

	# Sampled every frame even though it is DRAWN five times a second — a
	# minimum that only looks every 200ms will miss the frame that stuttered,
	# which is the only frame anyone cares about.
	var fps: float = Performance.get_monitor(Performance.TIME_FPS)
	# A HELD FRAME IS NOT A RESULT (0.69.2): neither its rate nor its length
	# says anything about the game, so it goes into no worst and no count.
	var held: bool = Settings.held_reason() != ""
	if not held and fps > 0.0 and (_worst_fps <= 0.0 or fps < _worst_fps):
		_worst_fps = fps
	_note_frame(delta, held)
	var ticks: int = Engine.get_physics_frames() - _last_physics_frames
	_last_physics_frames = Engine.get_physics_frames()
	_busy_ms_sum += _process_ms() + _physics_ms() * float(maxi(ticks, 0))
	_busy_frames += 1

	_accum += delta
	if _accum < SAMPLE_INTERVAL:
		return
	_accum = 0.0
	_busy_ms = _busy_ms_sum / float(maxi(_busy_frames, 1))
	_busy_ms_sum = 0.0
	_busy_frames = 0

	_label.text = "\n".join([
		_row("fps", "%d   (worst %d)%s" % [int(fps), int(_worst_fps), _cap_note()]),

		# MILLISECONDS, BECAUSE FRAME RATE IS THE WRONG UNIT FOR THIS QUESTION.
		#
		# fps is a reciprocal, so its deltas lie about cost. Dropping 2500 -> 1250
		# looks like losing half the game and costs 0.4ms. Dropping 70 -> 60 looks
		# like nothing and costs 2.4ms — six times more. You cannot add frame
		# rates, and "how many more bosses fit" is an addition.
		#
		# Milliseconds add. One boss costing 1.2ms means fourteen of them fit in a
		# 60fps frame, and that arithmetic is only available in this unit.
		_row("frame", "%.2f ms   (worst %.2f)   budget %.2f" % [
			1000.0 / maxf(fps, 0.001),
			1000.0 / maxf(_worst_fps, 0.001),
			TARGET_FRAME_MS,
		]),
		_row("hitches", "%s of %s frames over %.0f ms   (%.1f%%)" % [
			_thousands(_hitches), _thousands(_frames), HITCH_MS,
			100.0 * float(_hitches) / float(maxi(_frames, 1))]),

		# THE TWO HALVES OF A FRAME THAT A CROWD OF MONSTERS FILLS. Physics is
		# every monster's brain - navigation, the formation ring, move_and_slide -
		# at 80 ticks a second, so its budget is 12.5 ms, not the frame's.
		#
		# PROCESS IS THE REST OF THE FRAME, DRAWING INCLUDED - NOT THE SCRIPTS
		# ALONE (0.63.1; 0.63.0 called it the scripts). Godot measures
		# TIME_PROCESS round the whole idle step: every _process (animation, the
		# HUD, names over heads) and handing the picture to the graphics card.
		# The same Big Field read 2 ms with nothing drawn and 51 ms drawn on a
		# machine with no graphics card. Its budget is the frame's, less physics.
		_row("physics", "%.2f ms a tick   (worst %.2f)   budget %.2f" % [
			_physics_ms(), _worst_physics_ms, 1000.0 / float(Engine.physics_ticks_per_second)]),
		_row("process", "%.2f ms   (worst %.2f)   scripts + drawing" % [_process_ms(), _worst_process_ms]),
		# THE TWO ROWS THAT STAY TRUE WHILE THE FRAME RATE IS HELD (0.69.2).
		_row("busy", "%.2f ms of each frame   (process + its physics ticks)" % busy_ms()),
		_row("gpu", ("%.2f ms a frame   (the graphics card)" % gpu_ms()) if gpu_ms() > 0.0
			else "not measured by this renderer"),
		_row("monsters", _monsters_text()),
		_row("nodes", _thousands(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))),
		_row("bodies", "%s active" % _thousands(
			int(Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS)))),
		# THE NUMBER TO WATCH IN THIS PROJECT. Collision pairs is the broad
		# phase's output - how many candidate overlaps it could not discard and
		# had to hand to the narrow phase. It is what a bullet-hell actually
		# spends its physics budget on, and it is the number that a scaled
		# collision shape makes worse: see the note in CLAUDE.md about why the
		# elemental scenes size their shape resource instead of scaling a node.
		_row("pairs", _thousands(
			int(Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS)))),
		_row("draws", _thousands(
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))),
		_row("memory", "%.1f MB" % (
			Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0)),
		# THE ONLY ROW HERE THAT IS NOT ABOUT THIS MACHINE. Every other number
		# answers "is this smooth for me"; this one answers "what does one of
		# me cost the server", and it is multiplied by every player online.
		# See Api.REQUEST_WINDOW_SECONDS for the arithmetic that makes it the
		# number worth watching as the game grows.
		_row("net", "%.2f req/s   (%s total)" % [
			Api.requests_per_second(), _thousands(Api.requests_total())]),
	])


func _note_frame(delta: float, held: bool = false) -> void:
	"""One frame into the since-switched-on counts: the frame, whether it
	hitched, and the worst physics tick and script time. A frame drawn while
	the game is HELD at the background rate (Settings.held_reason()) is not
	counted: every one of those is 66 ms on purpose, and the owner's 8x
	readout called 64% of its frames hitches for it (0.69.2)."""
	if held:
		return
	_frames += 1
	if delta * 1000.0 > HITCH_MS:
		_hitches += 1
	_worst_physics_ms = maxf(_worst_physics_ms, _physics_ms())
	_worst_process_ms = maxf(_worst_process_ms, _process_ms())


func _physics_ms() -> float:
	return Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0


func _process_ms() -> float:
	return Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0


func monster_counts() -> Vector2i:
	"""(in the area, asleep) - every node in the "enemies" group, and those the
	enemy sleeper has put to sleep (it marks them with the "asleep" meta)."""
	var here: int = 0
	var asleep: int = 0
	for node in get_tree().get_nodes_in_group("enemies"):
		here += 1
		if node.has_meta(&"asleep"):
			asleep += 1
	return Vector2i(here, asleep)


func _monsters_text() -> String:
	var counts: Vector2i = monster_counts()
	if counts.x == 0:
		return "none here"
	return "%s here   %s awake   %s asleep" % [
		_thousands(counts.x), _thousands(counts.x - counts.y), _thousands(counts.y)]


func readout() -> String:
	"""What the readout says right now, as drawn."""
	return _label.text


func _cap_note() -> String:
	# SAYS WHETHER THE FPS NUMBER MEANS ANYTHING, because while anything is
	# capping it, it does not. A pinned "60 (worst 60)" reads as a result and is
	# not one: it means the renderer was never asked for more than 60, so two
	# bosses carpeting at once and standing in an empty room produce the
	# identical number. There is no headroom figure in it at all.
	#
	# THERE ARE TWO SEPARATE CAPS AND THEY LIVE IN DIFFERENT SECTIONS of
	# project.godot, which is exactly how you turn one off and stay capped:
	#
	#   display/window/vsync/vsync_mode   Display -> Window -> V-Sync
	#   application/run/max_fps           Application -> Run -> Max FPS
	#
	# Both are checked, and both are read from the RUNNING ENGINE rather than
	# from ProjectSettings. Both settings are applied at startup, so the stored
	# value is stale until a restart, and a graphics driver can force vsync back
	# on over whatever the game asked for. What the engine is doing right now is
	# the only version worth printing.
	#
	# AND THE ENGINE CAN BE WRONG ABOUT VSYNC. window_get_vsync_mode() reports
	# what the swapchain was ASKED for; a driver overriding it from its own
	# control panel does so underneath the engine, which goes on believing it
	# is synced. This line once read "2516 (capped by vsync - not a limit)",
	# which is a number vsync would never permit sitting next to the claim
	# that vsync was producing it. Settings.pacing_report() compares the
	# request with the result, and that comparison is the only honest source.
	# HELD, AND WHY, FIRST (0.69.2). The owner read "[capped by vsync, cap 15 -
	# not a limit]" over a 66 ms frame as the 8x crowd costing it: the cap was
	# the game's own background rate, and the words did not say so.
	match Settings.held_reason():
		"resting":
			return "   [held at %d: the screen is resting - press a key]" % Settings.BACKGROUND_FPS
		"background":
			return "   [held at %d: the game is in the background - click it]" % Settings.BACKGROUND_FPS
	var r: Dictionary = Settings.pacing_report()
	if bool(r["overridden"]):
		return "   [vsync requested, driver ignoring it - this number is real]"
	var caps: PackedStringArray = []
	if str(r["vsync"]) != "off":
		caps.append("vsync")
	if int(r["cap"]) > 0:
		caps.append("cap %d" % int(r["cap"]))
	if caps.is_empty():
		return ""
	return "   [capped by %s - not a limit]" % ", ".join(caps)


func _row(label: String, value: String) -> String:
	return label.rpad(LABEL_WIDTH) + value


func _thousands(n: int) -> String:
	# 650000 is a number you have to count the digits of. 650,000 is not, and in
	# a readout you are glancing at mid-fight that is the whole difference.
	var s: String = str(absi(n))
	var out: String = ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
