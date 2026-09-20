# perfoverlay.gd — an on-screen readout of what the game is actually costing,
# so "can we handle more bosses" has a number instead of an opinion.
#
# BACKSLASH toggles it, and the key space is more crowded than it looks. The
# audit, so nobody repeats it:
#
#   F1-F7, F9-F12, 1-9, M, I O P T U Y   player.gd's staff debug rows
#   `  (backtick)                        characterhud.gd's owner panel
#   M                                    also the minimap_toggle action
#   W A S D, space, arrows, shift        movement, attack, interact, sprint
#   F8                                   THE GODOT EDITOR'S "STOP" SHORTCUT
#
# F8 was the obvious pick and it is the one key that looks free from inside the
# project and is not: the editor grabs it to kill the running game, so binding
# it here means the overlay quits instead of toggling.
#
# A MODIFIER COMBO DOES NOT RESCUE A TAKEN KEY EITHER. Neither existing handler
# checks modifiers - both test `event.keycode == KEY_X` alone - so Ctrl+P still
# grants a pet and Ctrl+` still opens the owner panel. The key has to be one
# nothing looks at, and backslash is one.
#
# DEBUG BUILDS ONLY, BUT NOT RANK-GATED, and the difference is deliberate. The
# pet and gear keys are gated on OS.is_debug_build() AND a role check because
# they hand out loot — see the note in CLAUDE.md about why even that is only an
# honesty gate. This grants nothing. It reads five numbers and draws them. The
# build check is here so it cannot ship in a release export, and that is all it
# needs to be.
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


var _label: Label
var _accum: float = 0.0

# THE WORST FRAME SINCE YOU TURNED IT ON, which is the number a stress test is
# actually about. Current FPS during a 65-pillar carpet tells you what this
# instant costs; the minimum tells you whether the fight ever became unplayable,
# and that is the one the player felt. Reset by toggling off and on.
var _worst_fps: float = 0.0


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


func _input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_BACKSLASH:
		visible = not visible
		_worst_fps = 0.0
		_accum = SAMPLE_INTERVAL   # redraw on the very next frame, not in 0.2s


func _process(delta: float) -> void:
	if not visible:
		return

	# Sampled every frame even though it is DRAWN five times a second — a
	# minimum that only looks every 200ms will miss the frame that stuttered,
	# which is the only frame anyone cares about.
	var fps: float = Performance.get_monitor(Performance.TIME_FPS)
	if fps > 0.0 and (_worst_fps <= 0.0 or fps < _worst_fps):
		_worst_fps = fps

	_accum += delta
	if _accum < SAMPLE_INTERVAL:
		return
	_accum = 0.0

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
	])


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
	var caps: PackedStringArray = []
	if DisplayServer.window_get_vsync_mode(0) != DisplayServer.VSYNC_DISABLED:
		caps.append("vsync")
	if Engine.max_fps > 0:
		caps.append("max_fps %d" % Engine.max_fps)
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
