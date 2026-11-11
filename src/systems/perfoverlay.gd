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

const PerfPanel := preload("res://src/systems/perfpanel.gd")
const StressCrowdScript := preload("res://src/world/stresscrowd.gd")
const LagTests := preload("res://src/systems/lagtests.gd")


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
#
# TIMED BY THE CLOCK, NOT BY GODOT'S MONITORS (0.134.4). The owner's next
# screenshot: four spikes in the Boss Arena, 98 and 100 ms among them, every
# one "outside the scripts", and process worst 267.6 ms with no frame that
# long. Two things were wrong with the numbers, not the game:
#   - a frame's delta stops at 100 ms: Godot runs at most 8 physics ticks a
#     frame (80 a second) and advances the clock only as far as they go, so
#     a 267 ms freeze arrives as a 100 ms delta;
#   - TIME_PROCESS and TIME_PHYSICS_PROCESS are the WORST of the last second,
#     set once a second, so a spike's own cost is not in them yet.
# So each frame is timed here (Time.get_ticks_usec()): from its first physics
# tick (this node's _physics_process - an autoload, so early in the tick) to
# this node's _process is PHYSICS, from there to RenderingServer's
# frame_pre_draw is SCRIPTS (every _process, and anything loaded in one),
# from there to frame_post_draw is DRAWING (where a new effect's shader is
# built the first time it is drawn), and the rest until the next frame starts
# is WAITING (the screen's refresh).


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
# BACK FROM ANOTHER WINDOW (0.137.2). The owner's readout: "158 ms 1 s ago -
# waiting 149.9 ms" and fps "worst 15", with nothing happening in the game.
# The frame measured here is the one that just ENDED, and it was judged by
# whether the game is held NOW: coming back from another window, the last
# frame of the background (held at BACKGROUND_FPS, plus the switch itself)
# counted as a spike, and the fps monitor, an average over a second, read
# the background's 15 as the worst. Now a frame is held if it began held,
# and the worst fps waits HOLD_SETTLE_MSEC after a hold ends: the monitor
# is redone once a second over the second before, so it can read held frames
# twice after the game comes back.
const HOLD_SETTLE_MSEC := 2100
var _held_before: bool = false
# A KEY OR CLICK IN THE FRAME (0.137.4). What a key or a click does - a window
# opening - runs before the frame's own clocked parts, so it was filed under
# waiting, "not the game's code": the owner's 44 ms spike was the GM panel
# being built. Each press is noted here, and a spike with one in it says so.
var _press_usec: int = 0

# LAG POINTS (0.138.0). The owner, of the Boss Arena's hitches in his
# browser: "can we upgrade the test to analyze the lag points". Which part of
# a frame was slow does not say what happened in it, and a browser cannot
# time the graphics card. So the game marks what it does - mark(&"spikes
# rise") at each place that does a lot in one frame - and every kind is
# counted: the frames with it, and how many of those hitched. The kind far
# above the frames with nothing marked is what makes the lag. A mark is
# nothing while the readout is off.
#
# A MARK BELONGS TO THE FRAME IT WAS MADE IN: the frame starts at its first
# physics tick (_physics_process()) and its marks so far are set aside there,
# so a mark made in the next frame's ticks is not counted against this one.
const MARK_LETTERS := {
	&"boss casts": "C",
	&"spikes appear": "A",
	&"spikes rise": "R",
	&"spikes go": "G",
	&"pools land": "P",
	&"boss volleys": "V",
	&"monsters appear": "M",
	&"monsters die": "D",
	&"loot bags": "B",
	&"key or click": "K",
	&"shaders warm": "H",
	# A boss's arena (0.139.0, lightarena.gd).
	&"flares flash": "F",
	&"mirrors break": "X",
	&"eclipse falls": "E",
	&"wind turns": "W",
	&"gusts blow": "L",
	&"tornado forms": "T",
	&"tide comes": "Q",
	&"bubbles pop": "O",
	&"frost forms": "S",
	&"ice walls rise": "I",
	&"hail lands": "U",
}
const NOTHING_MARKED := "nothing marked"
# A kind is the cause when this share of its frames hitched and this many
# times the frames with nothing marked; worth watching at the second pair.
const FIX_RATE := 0.2
const FIX_TIMES := 5.0
const WATCH_RATE := 0.05
const WATCH_TIMES := 2.0
var _marks_now: Dictionary = {}
var _marks_ended: Dictionary = {}
# kind -> [frames, hitched, {part: hitches}]; the same for nothing marked.
var _lag: Dictionary = {}
var _lag_base: Array = [0, 0, {}]
var _on_time: int = 0
# Beside the graph's frames: a hitch's [letter, part], or null.
var _graph_marks: Array = []
# The last frame's draw calls, triangles and graphics memory, for what a
# frame changed.
var _last_draws: int = -1
var _last_prims: int = -1
var _last_vram: int = -1
var _unheld_msec: int = -100000
var _worst_frame_ms: float = 0.0
var _spikes: Array[Dictionary] = []
# THE WORST STAYS (0.134.4): the owner's "frame worst 6080.90" had scrolled
# off the five newest before he looked. The longest hitch since switched on
# keeps its own row.
var _worst_spike: Dictionary = {}
# Nodes at the last frame, for the nodes made (or freed) in a frame.
var _prev_nodes: int = 0
# The clock's stamps for the frame running now (usec; 0 not yet).
var _frame_start_usec: int = 0     # its first physics tick, or its _process
var _tick_usec: int = 0            # the physics tick running now
var _tick_worst_usec: int = 0      # this frame's longest tick so far
var _ticks_now: int = 0
var _idle_usec: int = 0            # this node's _process
var _pre_draw_usec: int = 0
var _post_draw_usec: int = 0
# The next frame's start, stamped by its first tick before its _process.
var _frame_start_usec_next: int = 0
# The ticks of the frame running now, kept for its sample when it ends.
var _last_parts: Dictionary = {}
# THE PANEL (0.136.0, perfpanel.gd): the frames for its graph, oldest
# overwritten, and the frames' parts added up since its last look.
var _panel: Control = null
var _graph := PackedFloat32Array()
var _graph_at: int = 0
var _graph_count: int = 0
var _split_sums := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])   # ms, physics, scripts, drawing, ticks, frames
var _split: Dictionary = {}


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
	# WRITTEN, NOT SHOWN (0.136.0): readout() and Copy read it; the panel is
	# what is drawn.
	_label.visible = false
	add_child(_label)
	_graph.resize(PerfPanel.GRAPH_FRAMES)
	_panel = PerfPanel.new()
	_panel.name = "panel"
	_panel.text_source = readout
	add_child(_panel)

	visible = false
	RenderingServer.frame_pre_draw.connect(_on_pre_draw)
	RenderingServer.frame_post_draw.connect(_on_post_draw)


func _on_pre_draw() -> void:
	if visible:
		_pre_draw_usec = Time.get_ticks_usec()


func _on_post_draw() -> void:
	if visible:
		_post_draw_usec = Time.get_ticks_usec()


func _physics_process(_delta: float) -> void:
	if not visible:
		return
	var now: int = Time.get_ticks_usec()
	if _tick_usec > 0:
		_tick_worst_usec = maxi(_tick_worst_usec, now - _tick_usec)
	_tick_usec = now
	_ticks_now += 1
	if _ticks_now == 1:
		_frame_start_usec_next = now
		# The frame that just ended has its marks; this one starts afresh.
		_marks_ended = _marks_now
		_marks_now = {}


func clocked_frame(now_usec: int) -> Dictionary:
	"""Closes the frame that just ended and opens the one starting now (its
	ticks have run; its _process is this call). Returns the ended frame's
	parts in ms - length, physics, worst_tick, ticks, scripts, drawing - or {}
	for the first frame."""
	var start: int = _frame_start_usec_next if _ticks_now > 0 else now_usec
	if _ticks_now == 0:
		# No tick to set the ended frame's marks aside: they end here.
		_marks_ended = _marks_now
		_marks_now = {}
	var parts: Dictionary = {}
	if _frame_start_usec > 0 and _idle_usec > 0:
		var drew: bool = _pre_draw_usec >= _idle_usec and _post_draw_usec >= _pre_draw_usec
		var scripts_end: int = _pre_draw_usec if drew else start
		parts = {
			"ms": float(start - _frame_start_usec) / 1000.0,
			"physics": float(_idle_usec - _frame_start_usec) / 1000.0,
			"worst_tick": _last_parts.get("next_worst_tick", 0.0),
			"ticks": int(_last_parts.get("next_ticks", 0)),
			"scripts": float(maxi(0, scripts_end - _idle_usec)) / 1000.0,
			"drawing": float(_post_draw_usec - _pre_draw_usec) / 1000.0 if drew else 0.0,
			"marks": _marks_ended,
		}
	_marks_ended = {}
	# This frame: its ticks ran before this call; the last one ends now.
	if _tick_usec > 0 and _ticks_now > 0:
		_tick_worst_usec = maxi(_tick_worst_usec, now_usec - _tick_usec)
	_last_parts = {
		"next_worst_tick": float(_tick_worst_usec) / 1000.0,
		"next_ticks": _ticks_now,
	}
	_frame_start_usec = start
	_idle_usec = now_usec
	_tick_usec = 0
	_tick_worst_usec = 0
	_ticks_now = 0
	return parts


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
		_count_round = []
		_count_at = 0
		_counted = []
		_pending.clear()
		_load_after_left = 0
		_scene_id = _current_scene_id()
		_in_load = false
		_loads = 0
		_last_load_ms = 0.0
		_last_load_area = ""
		_last_load_msec = -100000
		_held_before = false
		_unheld_msec = -100000
		_worst_frame_ms = 0.0
		_spikes.clear()
		_worst_spike = {}
		_prev_nodes = 0
		_frame_start_usec = 0
		_frame_start_usec_next = 0
		_last_parts = {}
		_tick_usec = 0
		_tick_worst_usec = 0
		_ticks_now = 0
		_idle_usec = 0
		_pre_draw_usec = 0
		_post_draw_usec = 0
		_accum = SAMPLE_INTERVAL   # redraw on the very next frame, not in 0.2s
		_graph.fill(0.0)
		_graph_at = 0
		_graph_count = 0
		_split_sums.fill(0.0)
		_split = {}
		_marks_now = {}
		_marks_ended = {}
		_lag = {}
		_lag_base = [0, 0, {}]
		_on_time = 0
		_graph_marks.clear()
		_last_draws = -1
		_last_prims = -1
		_last_vram = -1
	visible = on
	_measure_render_time(on)
	# NEVER LEFT UNCAPPED once the readout is gone (Settings.set_uncapped()).
	if not on:
		Settings.set_uncapped(false)


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
	_count_some(delta)

	# Sampled every frame even though it is DRAWN five times a second — a
	# minimum that only looks every 200ms will miss the frame that stuttered,
	# which is the only frame anyone cares about.
	var fps: float = Performance.get_monitor(Performance.TIME_FPS)
	# A HELD FRAME IS NOT A RESULT (0.69.2): neither its rate nor its length
	# says anything about the game, so it goes into no worst and no count.
	var held: bool = held_for_frame(Settings.held_reason() != "", Time.get_ticks_msec())
	var ticks: int = Engine.get_physics_frames() - _last_physics_frames
	_last_physics_frames = Engine.get_physics_frames()
	_busy_ms_sum += _process_ms() + _physics_ms() * float(maxi(ticks, 0))
	_busy_frames += 1
	var nodes: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	if _current_scene_id() != _scene_id:
		_scene_id = _current_scene_id()
		mark_load()
	var ended_from: int = _frame_start_usec
	var parts: Dictionary = clocked_frame(Time.get_ticks_usec())
	if not parts.is_empty():
		parts["held"] = held
		parts["pressed"] = _press_usec > 0 and _press_usec >= ended_from
		parts["fps"] = fps
		parts["nodes"] = (nodes - _prev_nodes) if _prev_nodes > 0 else 0
		parts["area"] = AreaRegistry.current_area_id()
		parts["at"] = Time.get_ticks_msec()
		_note_drawn(parts)
		push_sample(parts)
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
		rows.append(_row("spikes" if i == 0 else "", _with_marks(spike_text(_spikes[i], now_msec), _spikes[i])))
	if not _worst_spike.is_empty():
		rows.append(_row("worst", _with_marks(spike_text(_worst_spike, now_msec), _worst_spike)))
	# Every kind marked, the likeliest cause first, and the verdicts.
	var lag: Array = lag_rows()
	for i in lag.size():
		var row: Array = lag[i]
		rows.append(_row("lag" if i == 0 else "", "%s   %d of %s hitched (%.0f%%)%s" % [row[0], row[2],
			_thousands(int(row[1])), 100.0 * float(row[2]) / maxf(1.0, float(row[1])),
			(", mostly %s" % row[3]) if str(row[3]) != "" else ""]))
	if not lag.is_empty():
		var base: Array = lag_base()
		rows.append(_row("", "%s   %d of %s hitched (%.1f%%)" % [NOTHING_MARKED, base[1], _thousands(int(base[0])),
			100.0 * float(base[1]) / maxf(1.0, float(base[0]))]))
	for verdict in verdicts():
		rows.append(_row(str(verdict[0]), str(verdict[1])))
	_label.text = "\n".join(rows)
	_panel.show_data(panel_data(now_msec))


func _input(event: InputEvent) -> void:
	if is_press(event):
		_press_usec = Time.get_ticks_usec()
		mark(&"key or click")


func mark(kind: StringName, count: int = 1) -> void:
	"""The game did `count` of `kind` this frame (MARK_LETTERS has the kinds;
	any other is counted the same, lettered by its first letter). Nothing
	while the readout is off."""
	if not visible:
		return
	_marks_now[kind] = int(_marks_now.get(kind, 0)) + count


func _note_drawn(parts: Dictionary) -> void:
	"""What the ended frame changed in what is drawn: draw calls, triangles,
	graphics memory (new buffers and textures). The renderer's numbers now
	are the last drawn frame's - the one ending."""
	var draws: int = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var prims: int = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var vram: int = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)
	parts["draws"] = draws - _last_draws if _last_draws >= 0 else 0
	parts["prims"] = prims - _last_prims if _last_prims >= 0 else 0
	parts["vram"] = vram - _last_vram if _last_vram >= 0 else 0
	_last_draws = draws
	_last_prims = prims
	_last_vram = vram


static func is_press(event: InputEvent) -> bool:
	"""A key, a button or a finger going down - what can make the game do
	something at once."""
	if event is InputEventKey:
		return (event as InputEventKey).pressed and not (event as InputEventKey).echo
	if event is InputEventMouseButton or event is InputEventScreenTouch or event is InputEventJoypadButton:
		return event.is_pressed()
	return false


func held_for_frame(held_now: bool, now_msec: int) -> bool:
	"""Whether the frame that just ended was held: held now, or held when it
	began (BACK FROM ANOTHER WINDOW above). Called once a frame."""
	var held: bool = held_now or _held_before
	if _held_before and not held_now:
		_unheld_msec = now_msec
	_held_before = held_now
	return held


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
			and at - _unheld_msec > HOLD_SETTLE_MSEC \
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
	var ticks: int = int(sample.get("ticks", 1))
	var physics: float = float(sample.get("physics", _physics_ms() * float(ticks)))
	var worst_tick: float = float(sample.get("worst_tick", _physics_ms()))
	var scripts: float = float(sample.get("scripts", _process_ms()))
	var drawing: float = float(sample.get("drawing", 0.0))
	var hitched: bool = ms > HITCH_MS
	if ms <= TARGET_FRAME_MS * 1.05:
		_on_time += 1
	var marks: Dictionary = sample.get("marks", {})
	var part: String = str(spike_cause({"ms": ms, "physics": physics, "scripts": scripts, "drawing": drawing})["kind"]) \
		if hitched else ""
	_count_lag(marks, hitched, part)
	var hitch_mark: Variant = null
	if hitched:
		hitch_mark = [_letter_for(marks), part]
	_note_for_panel(ms, physics, scripts, drawing, ticks, hitch_mark)
	_worst_frame_ms = maxf(_worst_frame_ms, ms)
	if hitched:
		_hitches += 1
		_spikes.push_front({
			"ms": ms, "physics": physics, "worst_tick": worst_tick, "ticks": ticks,
			"scripts": scripts, "drawing": drawing, "nodes": int(sample.get("nodes", 0)),
			"pressed": bool(sample.get("pressed", false)),
			"area": str(sample.get("area", AreaRegistry.current_area_id())),
			"at": int(sample.get("at", Time.get_ticks_msec())),
			"marks": marks.duplicate(),
			"draws": int(sample.get("draws", 0)), "prims": int(sample.get("prims", 0)),
			"vram": int(sample.get("vram", 0)),
		})
		if _worst_spike.is_empty() or ms > float(_worst_spike["ms"]):
			_worst_spike = _spikes[0]
		if _spikes.size() > SPIKES_SHOWN:
			_spikes.resize(SPIKES_SHOWN)
	_worst_physics_ms = maxf(_worst_physics_ms, worst_tick)
	_worst_process_ms = maxf(_worst_process_ms, scripts + drawing)


static func spike_cause(spike: Dictionary) -> Dictionary:
	"""Which part of a hitch took most of it: "kind" (physics, scripts,
	drawing or waiting - perfpanel.gd's colours) and its ms."""
	var ms: float = float(spike["ms"])
	var physics: float = float(spike["physics"])
	var scripts: float = float(spike["scripts"])
	var drawing: float = float(spike["drawing"])
	var waiting: float = maxf(0.0, ms - physics - scripts - drawing)
	var most: float = maxf(maxf(physics, scripts), maxf(drawing, waiting))
	if most == physics:
		return {"kind": "physics", "ms": physics}
	if most == scripts:
		return {"kind": "scripts", "ms": scripts}
	if most == drawing:
		return {"kind": "drawing", "ms": drawing}
	return {"kind": "waiting", "ms": waiting}


func spike_ago(spike: Dictionary, now_msec: int) -> String:
	@warning_ignore("integer_division")
	var seconds: int = maxi(0, (now_msec - int(spike["at"])) / 1000)
	@warning_ignore("integer_division")
	return ("%d s ago" % seconds) if seconds < 120 else ("%d min ago" % (seconds / 60))


func spike_text(spike: Dictionary, now_msec: int) -> String:
	"""One hitch: how long, how long ago, where, which part of the frame took
	most of it, and the nodes made (or freed) that frame.

	WAITING IS THE FRAME LESS THE GAME'S OWN WORK (0.136.0, the owner: "im
	not sure why it says outside of game"): physics, scripts and handing the
	picture over are clocked; the rest of a frame is waiting - for the
	screen's next refresh (vsync), the graphics driver or another program.
	It said "the computer busy elsewhere", which was only the last of those."""
	var ms: float = float(spike["ms"])
	var ticks: int = int(spike["ticks"])
	var cause: Dictionary = spike_cause(spike)
	var what: String
	match str(cause["kind"]):
		"physics":
			what = "physics %.1f ms, %d tick%s, the worst %.1f ms" % [float(cause["ms"]), ticks, "" if ticks == 1 else "s",
				float(spike["worst_tick"])]
		"scripts":
			what = "scripts %.1f ms (the game's code, or a file loading)" % float(cause["ms"])
		"drawing":
			what = "drawing %.1f ms (the graphics card - a new effect's first draw)" % float(cause["ms"])
		_:
			if bool(spike.get("pressed", false)):
				what = "waiting %.1f ms, with a key or click in it (what that did - a window opening, say - counts here)" \
					% float(cause["ms"])
			else:
				what = "waiting %.1f ms (the screen's refresh, the graphics driver or another program - not the game's code)" \
					% float(cause["ms"])
	var area: String = str(spike["area"])
	var where: String = (" in " + AreaRegistry.display_name(area)) if area != "" else ""
	var nodes: int = int(spike["nodes"])
	var made: String = ""
	if nodes != 0:
		made = "   %s%s nodes" % ["+" if nodes > 0 else "", _thousands(nodes)]
	return "%.0f ms   %s%s - %s%s" % [ms, spike_ago(spike, now_msec), where, what, made]


# =============================================================================
# THE PANEL'S NUMBERS (0.136.0)
# =============================================================================

func _note_for_panel(ms: float, physics: float, scripts: float, drawing: float, ticks: int,
		hitch_mark: Variant = null) -> void:
	if _graph.size() != PerfPanel.GRAPH_FRAMES:
		_graph.resize(PerfPanel.GRAPH_FRAMES)
	if _graph_marks.size() != _graph.size():
		_graph_marks.resize(_graph.size())
	_graph[_graph_at] = ms
	_graph_marks[_graph_at] = hitch_mark
	_graph_at = (_graph_at + 1) % _graph.size()
	_graph_count = mini(_graph_count + 1, _graph.size())
	_split_sums[0] += ms
	_split_sums[1] += physics
	_split_sums[2] += scripts
	_split_sums[3] += drawing
	_split_sums[4] += float(ticks)
	_split_sums[5] += 1.0


func graph_frames() -> PackedFloat32Array:
	"""The frames the graph shows, oldest first."""
	var out := PackedFloat32Array()
	var start: int = _graph_at - _graph_count
	for i in _graph_count:
		out.append(_graph[posmod(start + i, _graph.size())])
	return out


func graph_marks() -> Array:
	"""The graph's hitches, oldest first: [frame in graph_frames(), letter,
	part]."""
	var out: Array = []
	if _graph_marks.size() != _graph.size():
		return out
	var start: int = _graph_at - _graph_count
	for i in _graph_count:
		var hitch_mark: Variant = _graph_marks[posmod(start + i, _graph_marks.size())]
		if hitch_mark != null:
			out.append([i, hitch_mark[0], hitch_mark[1]])
	return out


func graph_key(marks: Array, most: int = 3) -> Array:
	"""What the graph's letters stand for: [letter, name, how many, part of
	the latest], the commonest first, at most `most`."""
	var counts: Dictionary = {}
	var parts: Dictionary = {}
	for hitch_mark in marks:
		var letter: String = str(hitch_mark[1])
		counts[letter] = int(counts.get(letter, 0)) + 1
		parts[letter] = str(hitch_mark[2])
	var letters: Array = counts.keys()
	letters.sort_custom(func(a, b): return int(counts[a]) > int(counts[b]))
	var out: Array = []
	for letter in letters.slice(0, most):
		out.append([letter, _name_of_letter(str(letter)), int(counts[letter]), parts[letter]])
	return out


static func letter_of(kind: StringName) -> String:
	if MARK_LETTERS.has(kind):
		return str(MARK_LETTERS[kind])
	var word := str(kind)
	return word.left(1).to_upper() if word != "" else "?"


static func _name_of_letter(letter: String) -> String:
	if letter == "?":
		return NOTHING_MARKED
	for kind in MARK_LETTERS:
		if str(MARK_LETTERS[kind]) == letter:
			return str(kind)
	return letter


func _letter_for(marks: Dictionary) -> String:
	"""A hitch's letter: of its marks, the one most often in hitches so far
	("?" with none)."""
	if marks.is_empty():
		return "?"
	var best: StringName = &""
	var best_rate: float = -1.0
	for kind in marks:
		var row: Array = _lag.get(kind, [0, 0, {}])
		var rate: float = float(row[1]) / maxf(1.0, float(row[0]))
		if rate > best_rate:
			best_rate = rate
			best = kind
	return letter_of(best)


func _count_lag(marks: Dictionary, hitched: bool, part: String) -> void:
	if marks.is_empty():
		_bump(_lag_base, hitched, part)
		return
	for kind in marks:
		if not _lag.has(kind):
			_lag[kind] = [0, 0, {}]
		_bump(_lag[kind], hitched, part)


static func _bump(row: Array, hitched: bool, part: String) -> void:
	row[0] = int(row[0]) + 1
	if hitched:
		row[1] = int(row[1]) + 1
		var parts: Dictionary = row[2]
		parts[part] = int(parts.get(part, 0)) + 1


static func _mostly(parts: Dictionary) -> String:
	var best: String = ""
	for part in parts:
		if best == "" or int(parts[part]) > int(parts[best]):
			best = str(part)
	return best


func lag_rows() -> Array:
	"""Every kind marked since switched on: [kind, frames, hitched, mostly
	in], the likeliest cause first (the share that hitched, then how many)."""
	var rows: Array = []
	for kind in _lag:
		var row: Array = _lag[kind]
		rows.append([str(kind), int(row[0]), int(row[1]), _mostly(row[2])])
	rows.sort_custom(func(a, b):
		var ra: float = float(a[2]) / maxf(1.0, float(a[1]))
		var rb: float = float(b[2]) / maxf(1.0, float(b[1]))
		return ra > rb if not is_equal_approx(ra, rb) else int(a[2]) > int(b[2]))
	return rows


func lag_base() -> Array:
	"""The frames with nothing marked: [frames, hitched, mostly in]."""
	return [int(_lag_base[0]), int(_lag_base[1]), _mostly(_lag_base[2])]


func verdicts() -> Array:
	"""[["great" | "fix" | "watch", why], ...]: what is well inside its
	budget, the kind of event that makes the hitches, and the next one."""
	var out: Array = []
	var great: PackedStringArray = []
	if _frames >= 60:
		var on_time: float = float(_on_time) / float(_frames)
		if on_time >= 0.95:
			great.append("%d%% of frames on time" % floori(on_time * 100.0))
	var inside: PackedStringArray = []
	if float(_split.get("scripts", TARGET_FRAME_MS)) < TARGET_FRAME_MS * 0.25:
		inside.append("scripts")
	if _physics_ms() < 0.4 * 1000.0 / float(Engine.physics_ticks_per_second):
		inside.append("physics")
	if not inside.is_empty():
		great.append("%s well inside" % " and ".join(inside))
	if not great.is_empty():
		out.append(["great", " · ".join(great)])
	var base: Array = lag_base()
	var base_rate: float = float(base[1]) / maxf(1.0, float(base[0]))
	var fix: Array = []
	var watch: Array = []
	for row in lag_rows():
		if int(row[1]) < 3 or int(row[2]) < 2:
			continue
		var rate: float = float(row[2]) / float(row[1])
		if fix.is_empty() and watch.is_empty() and rate >= maxf(FIX_RATE, base_rate * FIX_TIMES):
			fix = row
		elif watch.is_empty() and rate >= maxf(WATCH_RATE, base_rate * WATCH_TIMES):
			watch = row
	if not fix.is_empty():
		out.append(["fix", "%s: %d of %d hitched, mostly %s" % [fix[0], fix[2], fix[1], fix[3]]])
	elif _frames >= 60 and float(_hitches) / float(_frames) > 0.02 and int(base[1]) >= 3:
		out.append(["fix", "%s: %d of %s hitched, mostly %s" % [NOTHING_MARKED,
			base[1], _thousands(int(base[0])), base[2]]])
	if not watch.is_empty():
		out.append(["watch", "%s: %d of %d hitched" % [watch[0], watch[2], watch[1]]])
	return out


func marks_text(spike: Dictionary, most: int = 3) -> String:
	"""What happened in a hitch's frame, in a few words: its marks, the
	commonest first, then what it changed in what is drawn."""
	var bits: PackedStringArray = []
	var marks: Dictionary = spike.get("marks", {})
	var kinds: Array = marks.keys()
	kinds.sort_custom(func(a, b): return int(marks[a]) > int(marks[b]))
	for kind in kinds.slice(0, most):
		bits.append("%s ×%d" % [kind, int(marks[kind])])
	var draws: int = int(spike.get("draws", 0))
	if absi(draws) >= 3:
		bits.append("draws %s%d" % ["+" if draws > 0 else "", draws])
	var prims: int = int(spike.get("prims", 0))
	if absi(prims) >= 1000:
		bits.append("%s%.1fk triangles" % ["+" if prims > 0 else "-", absf(prims) / 1000.0])
	var vram: int = int(spike.get("vram", 0))
	if absi(vram) >= 262144:
		bits.append("%s%.1f MB graphics" % ["+" if vram > 0 else "-", absf(vram) / 1048576.0])
	return " · ".join(bits)


func split_now() -> Dictionary:
	"""The frames since the last look, on average: physics, scripts, drawing,
	waiting (the rest of the frame) and ticks - or the last look's, when no
	frame has come since."""
	var frames: float = _split_sums[5]
	if frames > 0.0:
		var ms: float = _split_sums[0] / frames
		var physics: float = _split_sums[1] / frames
		var scripts: float = _split_sums[2] / frames
		var drawing: float = _split_sums[3] / frames
		_split = {"physics": physics, "scripts": scripts, "drawing": drawing,
			"waiting": maxf(0.0, ms - physics - scripts - drawing), "ticks": _split_sums[4] / frames, "ms": ms}
		_split_sums.fill(0.0)
	return _split


func panel_data(now_msec: int) -> Dictionary:
	var fps: float = Performance.get_monitor(Performance.TIME_FPS)
	var counts: Vector2i = monster_counts() if _counted.is_empty() or not visible else Vector2i(_counted[0], _counted[1])
	var fight: Vector2i = fight_counts() if _counted.is_empty() or not visible else Vector2i(_counted[2], _counted[3])
	var game_mb: float = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var video_mb: float = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	var gpu: float = gpu_ms()
	var spikes: Array = []
	for i in mini(_spikes.size(), PerfPanel.SPIKES_SHOWN):
		spikes.append(_panel_spike(_spikes[i], now_msec))
	var title_bits: PackedStringArray = []
	var area: String = AreaRegistry.current_area_id()
	if area != "":
		title_bits.append(AreaRegistry.display_name(area))
	if StressCrowdScript.multiplier > 1:
		title_bits.append("%dx" % StressCrowdScript.multiplier)
	var split: Dictionary = split_now()
	var cap: String = _cap_short()
	if cap != "":
		title_bits.append(cap)
	# A LAG TEST ON SAYS SO, so a quiet readout is read as the test's.
	if LagTests.any_on():
		title_bits.append("test: " + ", ".join(LagTests.names_on()))
	var marks: Array = graph_marks()
	var lag: Array = []
	for row in lag_rows():
		lag.append([row[0], row[1], row[2]])
	var base: Array = lag_base()
	return {
		"title": "  ·  ".join(title_bits),
		"title_colour": PerfPanel.WARN if Settings.held_reason() != "" else PerfPanel.SOFT,
		# The frames since the last look, as measured: the fps monitor is
		# counted once a second, and just switched on it says 1.
		"fps": fps if split.is_empty() or fps > 1.5 else 1000.0 / maxf(float(split.get("ms", 1000.0)), 0.001),
		"frame_ms": float(split.get("ms", 1000.0 / maxf(fps, 0.001))),
		"worst_ms": _worst_frame_ms,
		"budget": TARGET_FRAME_MS,
		"hitch_ms": HITCH_MS,
		"graph": graph_frames(),
		"hitches": "hitches   %s of %s frames over %.0f ms   (%.1f%%)" % [_thousands(_hitches), _thousands(_frames),
			HITCH_MS, 100.0 * float(_hitches) / float(maxi(_frames, 1))],
		"loads": "loads: " + ("none since switched on"
			if _loads == 0 else "%s, the last %.0f ms into %s" % [_thousands(_loads), _last_load_ms,
				AreaRegistry.display_name(_last_load_area) if _last_load_area != "" else "an area"]),
		"split": split,
		"ticks_line": "physics tick %.2f ms (worst %.2f) of %.2f  ·  graphics card %s" % [_physics_ms(),
			_worst_physics_ms, 1000.0 / float(Engine.physics_ticks_per_second),
			("%.2f ms" % gpu) if gpu > 0.0 else "not measured"],
		"world": [
			["monsters", _thousands(counts.x)], ["awake", _thousands(counts.x - counts.y)],
			["asleep", _thousands(counts.y)],
			["after you", "nobody" if fight.x + fight.y == 0 else "%s + %s waiting" % [_thousands(fight.x), _thousands(fight.y)]],
			["nodes", _thousands(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))],
			["bodies", _thousands(int(Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS)))],
			["pairs", _thousands(int(Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS)))],
			["draws", _thousands(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))],
			["memory", ("%.0f MB" % game_mb) if game_mb > 0.0 else "-"],
			["graphics", ("%.0f MB" % video_mb) if video_mb > 0.0 else "-"],
			["net", "%.2f req/s" % Api.requests_per_second()],
		],
		"spikes": spikes,
		"worst_spike": _panel_spike(_worst_spike, now_msec, true) if not _worst_spike.is_empty() else {},
		"graph_marks": marks,
		"graph_key": graph_key(marks),
		"verdict": verdicts(),
		"lag": lag,
		"lag_base": [base[0], base[1]] if not lag.is_empty() else [],
	}


func _panel_spike(spike: Dictionary, now_msec: int, worst: bool = false) -> Dictionary:
	var cause: Dictionary = spike_cause(spike)
	var kind: String = str(cause["kind"])
	var what: String = "%s %.1f ms" % [kind, float(cause["ms"])]
	if kind == "physics":
		what += ", %d tick%s" % [int(spike["ticks"]), "" if int(spike["ticks"]) == 1 else "s"]
	elif kind == "waiting" and bool(spike.get("pressed", false)):
		what += " after a key or click"
	var nodes: int = int(spike["nodes"])
	return {
		"ms": float(spike["ms"]),
		"ago": ("worst, " if worst else "") + spike_ago(spike, now_msec).trim_suffix(" ago"),
		"kind": kind,
		"cause": what,
		"nodes": ("%s%s nodes" % ["+" if nodes > 0 else "", _thousands(nodes)]) if nodes != 0 else "",
		"marks": marks_text(spike),
	}


func _cap_short() -> String:
	"""_cap_note(), in a few words for the panel's title."""
	match Settings.held_reason():
		"resting":
			return "held at %d - the screen is resting" % Settings.BACKGROUND_FPS
		"background":
			return "held at %d - in the background" % Settings.BACKGROUND_FPS
	if Settings.uncapped:
		return "uncapped to test"
	var r: Dictionary = Settings.pacing_report()
	if bool(r["overridden"]):
		return "vsync ignored by the driver"
	var caps: PackedStringArray = []
	if str(r["vsync"]) != "off":
		caps.append("vsync")
	if int(r["cap"]) > 0:
		caps.append("cap %d" % int(r["cap"]))
	return "no cap" if caps.is_empty() else ", ".join(caps)


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


# COUNTED A SLICE A FRAME (0.135.3). The rows below counted every monster in
# the area, twice, each time the readout wrote itself - five times a second.
# At 16x, 8,700 monsters: 8 ms of one frame in the container (monster_counts
# 3.6, fight_counts 4.5), the readout making the very hitches it reports. Now
# one pass over a round of them, a share a frame - that frame's part of
# SAMPLE_INTERVAL, as the sleeper spreads its pass - and the rows show the
# last whole round's totals. Before the first round (just switched on), or
# asked with the readout hidden, they count at once, as before. monster_counts() and fight_counts() still count
# everything at once for whoever asks.
var _count_round: Array = []
var _count_at: int = 0
var _count_part: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])   # here, asleep, fighting, waiting
var _counted: PackedInt32Array = PackedInt32Array()                  # the last whole round's


func _count_some(delta: float) -> void:
	if _count_at >= _count_round.size():
		if not _count_round.is_empty():
			_counted = _count_part.duplicate()
		_count_round = get_tree().get_nodes_in_group("enemies")
		_count_at = 0
		_count_part = PackedInt32Array([0, 0, 0, 0])
		if _count_round.is_empty():
			_counted = PackedInt32Array([0, 0, 0, 0])
			return
	var share: int = clampi(ceili(float(_count_round.size()) * delta / SAMPLE_INTERVAL), 1, _count_round.size())
	var upto: int = mini(_count_at + share, _count_round.size())
	for i in range(_count_at, upto):
		var node: Variant = _count_round[i]
		if not is_instance_valid(node) or not (node as Node).is_inside_tree():
			continue
		_count_part[0] += 1
		if (node as Node).has_meta(&"asleep"):
			_count_part[1] += 1
			continue
		var monster := node as BaseEnemy
		if monster == null or not monster.engaged:
			continue
		if monster.waiting_turn:
			_count_part[3] += 1
		else:
			_count_part[2] += 1
	_count_at = upto


func _fight_text() -> String:
	var counts: Vector2i = fight_counts() if _counted.is_empty() or not visible else Vector2i(_counted[2], _counted[3])
	if counts.x + counts.y == 0:
		return "nobody"
	return "%s fighting   %s waiting their turn   (%d seats a player)" % [
		_thousands(counts.x), _thousands(counts.y), BaseEnemy.FIGHT_SEATS]


func _monsters_text() -> String:
	var counts: Vector2i = monster_counts() if _counted.is_empty() or not visible else Vector2i(_counted[0], _counted[1])
	if counts.x == 0:
		return "none here"
	return "%s here   %s awake   %s asleep" % [
		_thousands(counts.x), _thousands(counts.x - counts.y), _thousands(counts.y)]


func _with_marks(text: String, spike: Dictionary) -> String:
	var marks: String = marks_text(spike, 6)
	return text + ("   [%s]" % marks if marks != "" else "")


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
