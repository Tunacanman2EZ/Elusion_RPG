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
const LABEL_WIDTH := 10

# The frame budget the `frame` row compares against, in milliseconds.
#
# 16.67ms IS 60fps, AND IT IS THE NUMBER TO BUDGET AGAINST rather than any peak.
# Change it to 6.94 if you decide the game targets 144.
const TARGET_FRAME_MS := 1000.0 / 60.0

# A HITCH is a frame half as long again as the budget - 25 ms at 60 fps - the
# stutter a player sees. Not "over budget": on a 60 Hz screen every frame
# lands a hair either side of 16.67 ms, and counting those counts nothing.
const HITCH_MS := TARGET_FRAME_MS * 1.5

# LOADS ARE NOT HITCHES, AND A HITCH SAYS WHERE IT WAS (0.134.3). The owner's
# screenshot after a fight: process worst 241 ms, physics worst 22.5 ms, frame
# worst 31.25 - and no way to tell whether that was the fight or walking into
# the area. Since then:
#   - a frame is held back LOAD_BEFORE frames before it counts, so when the
#     scene changes (a new area) the frames just before it, and LOAD_AFTER
#     after, are the LOAD's - the "loads" row - and in no worst and no hitch;
#   - every hitch is kept, the newest SPIKES_SHOWN on the "spikes" rows: how
#     long, when, where, which part of the frame took it, and the nodes made
#     or freed that frame (a big number there is something spawning);
#   - the frame row's worst is the longest real frame, not the worst fps
#     turned back into ms (fps is averaged over a second, so a 241 ms frame
#     read as 31.25).
const LOAD_BEFORE := 4
const LOAD_AFTER := 4
const SPIKES_SHOWN := 5
# The fps monitor averages a second, so it reads low for one after a load.
const FPS_SETTLE_MSEC := 1100


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

# Frames not yet counted (LOAD_BEFORE of them), and the loads and spikes.
var _pending: Array[Dictionary] = []
var _load_after_left: int = 0
var _scene_id: int = 0
var _in_load: bool = false
var _loads: int = 0
var _last_load_ms: float = 0.0
var _last_load_area: String = ""
var _last_load_msec: int = -100000
var _worst_frame_ms: float = 0.0
var _spikes: Array[Dictionary] = []
# The frame a _process() call measures is the one before it: its length is
# this call's delta and its process time the monitor's, but its physics ticks
# were counted - and its last tick's time read - in the call before.
var _prev_ticks: int = 0
var _prev_physics_ms: float = 0.0
var _prev_nodes: int = 0


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
		_pending.clear()
		_load_after_left = 0
		_scene_id = _current_scene_id()
		_in_load = false
		_loads = 0
		_last_load_ms = 0.0
		_last_load_area = ""
		_last_load_msec = -100000
		_worst_frame_ms = 0.0
		_spikes.clear()
		_prev_ticks = 0
		_prev_physics_ms = 0.0
		_prev_nodes = 0
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
	var ticks: int = Engine.get_physics_frames() - _last_physics_frames
	_last_physics_frames = Engine.get_physics_frames()
	_busy_ms_sum += _process_ms() + _physics_ms() * float(maxi(ticks, 0))
	_busy_frames += 1
	var nodes: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	if _current_scene_id() != _scene_id:
		_scene_id = _current_scene_id()
		mark_load()
	push_sample({
		"ms": delta * 1000.0, "held": held, "fps": fps,
		"process": _process_ms(), "physics": _prev_physics_ms, "ticks": _prev_ticks,
		"nodes": (nodes - _prev_nodes) if _prev_nodes > 0 else 0,
		"area": AreaRegistry.current_area_id(), "at": Time.get_ticks_msec(),
	})
	_prev_ticks = maxi(ticks, 0)
	_prev_physics_ms = _physics_ms()
	_prev_nodes = nodes

	_accum += delta
	if _accum < SAMPLE_INTERVAL:
		return
	_accum = 0.0
	_busy_ms = _busy_ms_sum / float(maxi(_busy_frames, 1))
	_busy_ms_sum = 0.0
	_busy_frames = 0

	var rows: PackedStringArray = [
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
			_worst_frame_ms,
			TARGET_FRAME_MS,
		]),
		_row("hitches", "%s of %s frames over %.0f ms   (%.1f%%)" % [
			_thousands(_hitches), _thousands(_frames), HITCH_MS,
			100.0 * float(_hitches) / float(maxi(_frames, 1))]),
		_row("loads", loads_text()),

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
		# HOW MANY ARE AFTER YOU, AND HOW MANY OF THEM HOLD A SEAT (0.76.0): at
		# most BaseEnemy.FIGHT_SEATS fight a player at once; the rest wait.
		_row("after you", _fight_text()),
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
		_row("memory", memory_text()),
		# THE ONLY ROW HERE THAT IS NOT ABOUT THIS MACHINE. Every other number
		# answers "is this smooth for me"; this one answers "what does one of
		# me cost the server", and it is multiplied by every player online.
		# See Api.REQUEST_WINDOW_SECONDS for the arithmetic that makes it the
		# number worth watching as the game grows.
		_row("net", "%.2f req/s   (%s total)" % [
			Api.requests_per_second(), _thousands(Api.requests_total())]),
	]
	# The spikes last, under everything, newest first.
	var now_msec: int = Time.get_ticks_msec()
	if _spikes.is_empty():
		rows.append(_row("spikes", "none since switched on"))
	for i in _spikes.size():
		rows.append(_row("spikes" if i == 0 else "", spike_text(_spikes[i], now_msec)))
	_label.text = "\n".join(rows)


func _current_scene_id() -> int:
	var scene: Node = get_tree().current_scene if is_inside_tree() else null
	return scene.get_instance_id() if scene != null else 0


func push_sample(sample: Dictionary) -> void:
	"""One frame measured: held back LOAD_BEFORE frames, then counted
	(_count_sample()). `sample`: ms, held, fps, process, physics (its last
	tick), ticks, nodes (made less freed), area, at (ticks msec)."""
	if _load_after_left > 0:
		sample["load"] = true
		_load_after_left -= 1
	_pending.append(sample)
	while _pending.size() > LOAD_BEFORE:
		_count_sample(_pending.pop_front())


func mark_load() -> void:
	"""The scene changed: the frames held back, and the next LOAD_AFTER, were
	the load's."""
	for sample in _pending:
		sample["load"] = true
	_load_after_left = LOAD_AFTER


func flush_samples() -> void:
	"""Counts every frame held back now (the suite)."""
	while not _pending.is_empty():
		_count_sample(_pending.pop_front())


func _count_sample(sample: Dictionary) -> void:
	var at: int = int(sample.get("at", 0))
	if bool(sample.get("load", false)):
		if not _in_load:
			_loads += 1
			_last_load_ms = 0.0
		_in_load = true
		_last_load_ms = maxf(_last_load_ms, float(sample.get("ms", 0.0)))
		_last_load_area = str(sample.get("area", ""))
		_last_load_msec = at
		return
	_in_load = false
	var held: bool = bool(sample.get("held", false))
	var fps: float = float(sample.get("fps", 0.0))
	if not held and fps > 0.0 and at - _last_load_msec > FPS_SETTLE_MSEC \
			and (_worst_fps <= 0.0 or fps < _worst_fps):
		_worst_fps = fps
	_note_frame(float(sample.get("ms", 0.0)) / 1000.0, held, sample)


func _note_frame(delta: float, held: bool = false, sample: Dictionary = {}) -> void:
	"""One frame into the since-switched-on counts: the frame, whether it
	hitched (and if so, the spike), and the worst frame, physics tick and
	script time. A frame drawn while the game is HELD at the background rate
	(Settings.held_reason()) is not counted: every one of those is 66 ms on
	purpose, and the owner's 8x readout called 64% of its frames hitches for
	it (0.69.2). `sample` is push_sample()'s; without one, the monitors now."""
	if held:
		return
	_frames += 1
	var ms: float = delta * 1000.0
	var physics: float = float(sample.get("physics", _physics_ms()))
	var process: float = float(sample.get("process", _process_ms()))
	_worst_frame_ms = maxf(_worst_frame_ms, ms)
	if ms > HITCH_MS:
		_hitches += 1
		_spikes.push_front({
			"ms": ms, "physics": physics, "ticks": int(sample.get("ticks", 1)),
			"process": process, "nodes": int(sample.get("nodes", 0)),
			"area": str(sample.get("area", AreaRegistry.current_area_id())),
			"at": int(sample.get("at", Time.get_ticks_msec())),
		})
		if _spikes.size() > SPIKES_SHOWN:
			_spikes.resize(SPIKES_SHOWN)
	_worst_physics_ms = maxf(_worst_physics_ms, physics)
	_worst_process_ms = maxf(_worst_process_ms, process)


func spike_text(spike: Dictionary, now_msec: int) -> String:
	"""One hitch: how long, how long ago, where, which part of the frame took
	most of it, and the nodes made (or freed) that frame."""
	var ms: float = float(spike["ms"])
	var ticks: int = int(spike["ticks"])
	var physics: float = float(spike["physics"])
	var physics_all: float = physics * float(ticks)
	var process: float = float(spike["process"])
	var rest: float = maxf(0.0, ms - physics_all - process)
	var what: String
	if physics_all >= process and physics_all >= rest:
		what = "physics, %d tick%s, the last %.1f ms" % [ticks, "" if ticks == 1 else "s", physics]
	elif process >= rest:
		what = "scripts + drawing %.1f ms" % process
	else:
		what = "outside the scripts %.1f ms (the graphics card, or a file loading)" % rest
	var seconds: int = maxi(0, (now_msec - int(spike["at"])) / 1000)
	var ago: String = ("%d s ago" % seconds) if seconds < 120 else ("%d min ago" % (seconds / 60))
	var area: String = str(spike["area"])
	var where: String = (" in " + AreaRegistry.display_name(area)) if area != "" else ""
	var nodes: int = int(spike["nodes"])
	var made: String = ""
	if nodes != 0:
		made = "   %s%s nodes" % ["+" if nodes > 0 else "", _thousands(nodes)]
	return "%.0f ms   %s%s - %s%s" % [ms, ago, where, what, made]


func loads_text() -> String:
	if _loads == 0:
		return "none since switched on   (an area's first frames count here, not as hitches)"
	var area: String = AreaRegistry.display_name(_last_load_area) if _last_load_area != "" else "an area"
	return "%s since switched on   the last %.0f ms, into %s" % [_thousands(_loads), _last_load_ms, area]


func memory_text() -> String:
	"""Godot counts the game's own memory in a debug build only: an exported
	game read 0.0 MB (the owner's screenshot). The graphics memory where the
	renderer says."""
	var parts: PackedStringArray = []
	var game: float = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var video: float = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	if game > 0.0:
		parts.append("%.1f MB" % game)
	if video > 0.0:
		parts.append("graphics %.1f MB" % video)
	if parts.is_empty():
		return "not measured in this build"
	return "   ".join(parts)


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


func fight_counts() -> Vector2i:
	"""(fighting, waiting their turn) among the monsters after somebody - see
	BaseEnemy's SEATS."""
	var fighting: int = 0
	var waiting: int = 0
	for node in get_tree().get_nodes_in_group("enemies"):
		var monster := node as BaseEnemy
		if monster == null or not monster.engaged or monster.has_meta(&"asleep"):
			continue
		if monster.waiting_turn:
			waiting += 1
		else:
			fighting += 1
	return Vector2i(fighting, waiting)


func _fight_text() -> String:
	var counts: Vector2i = fight_counts()
	if counts.x + counts.y == 0:
		return "nobody"
	return "%s fighting   %s waiting their turn   (%d seats a player)" % [
		_thousands(counts.x), _thousands(counts.y), BaseEnemy.FIGHT_SEATS]


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
