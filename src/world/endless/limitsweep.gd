extends Node
# limitsweep.gd - Find the limit (0.152.0): the Testing Ground's sweep. One
# monster at a time, more and more of it, until the game's work reaches the
# limit - what one costs, and how many fit.
#
# The owner: "i will spawn until in red then we will see if we need to speed
# up anything or fix anything the goal is to make a spread sheet with all
# enemies", and of the plan's second step (a sweep per monster): "lets build
# it".
#
# HOW A SWEEP GOES (a child of testingground.gd, under its panel's FIND THE
# LIMIT):
# - The field cleared, you put in the middle of the arena (centre()) in God
#   mode (put back after), CLEAR_SECONDS for the clearing to settle.
# - Then over and over: SETTLE_SECONDS for what came to reach you and fight,
#   the readout's work over MEASURE_FRAMES (PerfOverlay.work_stats(): the
#   median, the slow ones - the 95th percentile - and each part's median), a
#   row; then +step more round the middle (gmspawner.gd; the horde through
#   the ground's own fill).
# - Until the median reaches LIMIT_AT (80%) of the budget ("limit"), the slow
#   frames pass the budget ("slow"), it reaches its most ("most"), or nothing
#   more fits on the floor ("no room") - or at once, when the empty field is
#   already past the limit ("base": nothing to measure against).
# - The first row is the field empty: the base. "ms each" is the straight line
#   through every row (least squares), "fits" how many reach LIMIT_AT, and each
#   at CHECKS (10, 50, 100, 200; the horde's HORDE_CHECKS) is (work - base) /
#   count there, so a cost that grows with the crowd shows (grows_with()).
# Every kind and Every monster sweep each in turn, the horde last. Results are
# kept (save_path) and Copy puts them on the clipboard as tab-separated rows
# for a spreadsheet - with every place the readout's Measure kept
# (placemeasure.gd, places_path), so one paste carries every result. Effects
# on you stay on: they are part of a fight's cost.
# Measured alone: what a party adds (the others' pictures, their attacks, the
# server) is the next step's.
# EVERY SHOT AND EVERY EFFECT (0.154.0): the same sweep over what is not a
# monster - more shots in the air, or more of an effect a second - from
# stresskinds.gd, which says how each is made. A result says what it counted
# ("per": out, in the air, a second).
# EVERY BOSS ATTACK AND THE CROWNED'S PHASES (0.176.0): the Crowned's attacks
# one by one, and its fight part by part, from bossbench.gd, which says how.

const GmSpawner := preload("res://src/world/gmspawner.gd")
const PlaceMeasure := preload("res://src/systems/placemeasure.gd")
const StressKinds := preload("res://src/world/endless/stresskinds.gd")
const BossBench := preload("res://src/world/endless/bossbench.gd")
const WorkBar := preload("res://src/world/endless/workbar.gd")
const HORDE := "Horde slimes"
const EVERY_KIND := "every kind"
const EVERY_MONSTER := "every monster"
const EVERY_SHOT := "every shot"
const EVERY_EFFECT := "every effect"
const EVERY_BOSS := "every boss attack"
const BOSS_PHASES := "the crowned's phases"
const STEP := 10
const BOSS_STEP := 1
const HORDE_STEP := 250
const MOST := 600
const BOSS_MOST := 30
# As far as the Testing Ground's biggest horde (0.175.0, swarm.gd MOST).
const HORDE_MOST := 10000
const CLEAR_SECONDS := 1.0
const SETTLE_SECONDS := 3.0
# The horde fills at the ground's rate; past this it is measured as it is.
const FILL_MOST_SECONDS := 10.0
const MEASURE_FRAMES := 120
const LIMIT_AT := 0.8
const CHECKS := [10, 50, 100, 200]
const HORDE_CHECKS := [250, 1000, 2500, 5000]
const SHOT_CHECKS := [100, 500, 1000, 2000]
const BOSS_CHECKS := [1, 5, 10, 20]
# A cost that grows with the crowd: each at the last row this many times each
# at the first row that stands NOISE_MS clear of the base.
const GROWS_AT := 1.5
const NOISE_MS := 0.5
# THE RESULTS TABLE (0.175.1): every result, newest first, ROWS_SHOWN rows
# seen at once and the rest a scroll away (it was the newest five and "...
# and 17 more"); its columns' widths; few fit under FEW (red), some under
# SOME (amber).
const ROWS_SHOWN := 8
const ROW_HEIGHT := 18.0
const COLUMN_EACH := 54.0
const COLUMN_FITS := 112.0
const COLUMN_FITS_NUMBER := 42.0
const COLUMN_WHY := 50.0
const FEW := 100
const SOME := 300
const COLOUR := Color(1.0, 0.86, 0.5)
const COLOUR_TEXT := Color(0.92, 0.88, 0.8)
const FAINT := Color(0.92, 0.88, 0.8, 0.55)
const WHY_SHORT := {
	"limit": "80%", "slow": "slow", "most": "most", "no room": "no room", "stopped": "stopped", "base": "too busy",
}
const WHY_WORDS := {
	"limit": "work at 80%", "slow": "slow frames past the budget", "most": "the sweep's most",
	"no room": "no room on the floor", "stopped": "stopped", "base": "the empty field past the limit",
}

enum Phase { IDLE, CLEARING, FILLING, SETTLING, MEASURING }

var ground: Node = null
var save_path: String = "user://limitsweep.json"
var places_path: String = "user://limitplaces.json"
var copy_to: Callable = DisplayServer.clipboard_set
var phase: int = Phase.IDLE
var target: Dictionary = {}
var queue: Array = []
var queue_size: int = 0
var rows: Array = []
var results: Dictionary = {}
var order: Array = []
var status: String = ""
var _left: float = 0.0
var _wanted: int = 0
var _was_god: bool = false
var _picker: OptionButton = null
var _step_box: SpinBox = null
var _go: Button = null
var _status_label: Label = null
# The card while a sweep runs (0.175.1).
var _card: PanelContainer = null
var _card_name: Label = null
var _card_of: Label = null
var _card_count: Label = null
var _card_work: Label = null
var _card_doing: Label = null
var _list_bar: Control = null
var _card_bar: Control = null
var _doing: String = ""
# The results table: its rows' box, in a scroll of ROWS_SHOWN rows.
var _table: VBoxContainer = null
var _scroll: ScrollContainer = null
var _results_box: VBoxContainer = null
var _hint: Label = null
var _table_key: String = "-"
var _stress: Node = null
var _bench: Node = null
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	load_results()


func _exit_tree() -> void:
	if phase != Phase.IDLE:
		GameState.god_mode = _was_god


func running() -> bool:
	return phase != Phase.IDLE


# ---- what is swept ----------------------------------------------------------------

static func horde_target() -> Dictionary:
	return {"label": HORDE, "path": "", "kind": -1, "horde": true}


static func counted_as(swept: Dictionary) -> String:
	"""What a sweep's count is: monsters "out", shots "in the air", an effect
	"a second", a party tank's aura "lit" - a boss attack says its own."""
	if BossBench.is_boss(swept):
		return str(swept.get("per", "out"))
	if StressKinds.is_rate(swept):
		return "a second"
	if StressKinds.is_aura(swept) or StressKinds.is_beam(swept):
		return "lit"
	return "in the air" if StressKinds.is_shot(swept) else "out"


static func is_boss(swept: Dictionary) -> bool:
	return int(swept.get("kind", 0)) == GmSpawner.KINDS.size() - 1


static func step_for(swept: Dictionary, chosen: int) -> int:
	"""How many more each time when sweeping a list: the horde HORDE_STEP, a
	boss BOSS_STEP, anything else `chosen`."""
	if bool(swept.get("horde", false)):
		return HORDE_STEP
	return BOSS_STEP if is_boss(swept) else chosen


static func most_for(swept: Dictionary) -> int:
	if swept.has("most"):
		return int(swept["most"])
	if bool(swept.get("horde", false)):
		return HORDE_MOST
	return BOSS_MOST if is_boss(swept) else MOST


static func targets_for(choice: String, chosen: int) -> Array:
	"""What `choice` (the picker's: EVERY_KIND, EVERY_MONSTER, HORDE or a
	monster's scene) sweeps, in order, each with its "step". Every shot and
	Every effect carry their own steps."""
	var out: Array = []
	if choice == EVERY_SHOT:
		return StressKinds.shots()
	if choice == EVERY_EFFECT:
		return StressKinds.effects()
	if choice == EVERY_BOSS:
		return BossBench.attacks()
	if choice == BOSS_PHASES:
		return BossBench.phases()
	if choice == EVERY_KIND or choice == EVERY_MONSTER:
		var kinds_seen: Dictionary = {}
		for entry in GmSpawner.catalogue():
			if choice == EVERY_KIND and kinds_seen.has(int(entry["kind"])):
				continue
			kinds_seen[int(entry["kind"])] = true
			var swept: Dictionary = (entry as Dictionary).duplicate()
			swept["step"] = step_for(swept, chosen)
			out.append(swept)
		var horde: Dictionary = horde_target()
		horde["step"] = HORDE_STEP
		out.append(horde)
		return out
	if choice == HORDE:
		var alone: Dictionary = horde_target()
		alone["step"] = maxi(1, chosen)
		return [alone]
	for entry in GmSpawner.catalogue():
		if str(entry["path"]) == choice:
			var swept: Dictionary = (entry as Dictionary).duplicate()
			swept["step"] = maxi(1, chosen)
			out.append(swept)
	return out


# ---- the sweep ----------------------------------------------------------------------

func begin(choice: String, chosen: int) -> void:
	if running():
		return
	queue = targets_for(choice, chosen)
	queue_size = queue.size()
	if queue.is_empty():
		return
	_was_god = GameState.god_mode
	GameState.god_mode = true
	PerfOverlay.set_shown(true)
	_next()


func stop() -> void:
	"""Stop now; what this monster has so far is kept (two rows or more)."""
	if not running():
		return
	if rows.size() >= 2:
		_keep(summarise(rows, str(target["label"]), "stopped", PerfOverlay.budget_ms(), _checks()))
	queue.clear()
	_end("Stopped.")


func _end(said: String) -> void:
	phase = Phase.IDLE
	if _stress != null:
		_stress.call("end")
	if _bench != null:
		_bench.call("end")
	target = {}
	rows = []
	GameState.god_mode = _was_god
	if ground != null:
		ground.call("clear_all")
	status = said
	paint()


func _next() -> void:
	if queue.is_empty():
		var last: String = str(order.back()) if not order.is_empty() else ""
		_end(summary_line(results[last]) if queue_size == 1 and results.has(last)
			else "Done - %d swept. Copy results for the spreadsheet." % queue_size)
		return
	target = queue.pop_front()
	rows = []
	_wanted = 0
	if ground != null:
		ground.call("clear_all")
	_place_player()
	if _stress != null:
		_stress.call("end")
	if _bench != null:
		_bench.call("end")
	if BossBench.is_boss(target):
		if _bench == null:
			_bench = BossBench.new()
			_bench.name = "bossbench"
			add_child(_bench)
		var host_run: Node = _run()
		_bench.call("begin", target, host_run.call("_player") if host_run != null and host_run.has_method("_player") else null,
			host_run.get_parent() if host_run != null else null, centre())
	elif StressKinds.is_rate(target):
		if _stress == null:
			_stress = StressKinds.new()
			_stress.name = "stress"
			add_child(_stress)
		var run: Node = _run()
		_stress.call("begin", target, run.call("_player") if run != null and run.has_method("_player") else null)
	phase = Phase.CLEARING
	_left = CLEAR_SECONDS
	_say("clearing the field")


func _process(delta: float) -> void:
	match phase:
		Phase.CLEARING:
			_left -= delta
			if _left <= 0.0:
				_settle()
		Phase.FILLING:
			_left -= delta
			if count_now() >= _wanted or _left <= 0.0:
				_settle()
		Phase.SETTLING:
			_left -= delta
			if _left <= 0.0:
				if not PerfOverlay.is_shown():
					PerfOverlay.set_shown(true)
				PerfOverlay.forget_work()
				phase = Phase.MEASURING
				_say("measuring %d frames%s" % [MEASURE_FRAMES, " of the empty field" if rows.is_empty() else ""])
		Phase.MEASURING:
			# Counted, not summed, each frame: the sums once, when they are in.
			if PerfOverlay.work_frames() >= MEASURE_FRAMES:
				_measured(PerfOverlay.work_stats(MEASURE_FRAMES))


func _settle() -> void:
	phase = Phase.SETTLING
	_left = SETTLE_SECONDS
	_say("the empty field first" if rows.is_empty() else "letting them reach you")


func _measured(stats: Dictionary) -> void:
	var row: Array = [count_now(), float(stats["median"]), float(stats["p95"]),
		roundi(Engine.get_frames_per_second()), float(stats.get("physics", 0.0)),
		float(stats.get("scripts", 0.0)), float(stats.get("drawing", 0.0))]
	rows.append(row)
	var why: String = judge(row, PerfOverlay.budget_ms(), _wanted, most_for(target))
	if why != "":
		_keep(summarise(rows, str(target["label"]), why, PerfOverlay.budget_ms(), _checks()))
		_next()
		return
	_more()


func _more() -> void:
	var most: int = most_for(target)
	var more: int = mini(int(target.get("step", STEP)), most - _wanted)
	if BossBench.is_boss(target):
		if BossBench.is_rate(target):
			_wanted += more
			_bench.call("set_rate", float(_wanted))
		else:
			var made_out: int = int(_bench.call("make", more))
			if made_out <= 0:
				_keep(summarise(rows, str(target["label"]), "no room", PerfOverlay.budget_ms(), _checks()))
				_next()
				return
			_wanted += made_out
		_settle()
		return
	if StressKinds.is_rate(target):
		_wanted += more
		if _stress != null:
			_stress.call("set_rate", float(_wanted))
		_settle()
		return
	if StressKinds.is_shot(target):
		var me: Node2D = _run().call("_player") as Node2D if _run() != null and _run().has_method("_player") else null
		var made_shots: int = StressKinds.make_shots(get_tree(), target, more,
			me.global_position if me != null else centre(), _rng)
		if made_shots <= 0:
			_keep(summarise(rows, str(target["label"]), "no room", PerfOverlay.budget_ms(), _checks()))
			_next()
			return
		_wanted += made_shots
		_settle()
		return
	if bool(target.get("horde", false)):
		_wanted += more
		if ground != null:
			ground.call("set_horde", _wanted)
		phase = Phase.FILLING
		_left = FILL_MOST_SECONDS
		_say("filling to %s" % GameConstants.commas(_wanted))
		return
	var made: int = GmSpawner.spawn(get_tree(), str(target["path"]), more, centre())
	if made <= 0:
		_keep(summarise(rows, str(target["label"]), "no room", PerfOverlay.budget_ms(), _checks()))
		_next()
		return
	_wanted += made
	_settle()


static func judge(row: Array, budget: float, wanted: int, most: int) -> String:
	"""Why a sweep stops after `row` ([count, median, p95, ...]), or "" to go
	on: the median at LIMIT_AT of `budget` (with nothing out, "base"), the
	slow ones past it, or `most` brought."""
	if int(row[0]) <= 0 and float(row[1]) >= budget * LIMIT_AT:
		return "base"
	if int(row[0]) > 0 and float(row[1]) >= budget * LIMIT_AT:
		return "limit"
	if int(row[0]) > 0 and float(row[2]) > budget:
		return "slow"
	if wanted >= most:
		return "most"
	return ""


func _checks() -> Array:
	if BossBench.is_boss(target):
		return BOSS_CHECKS
	if StressKinds.is_shot(target):
		return SHOT_CHECKS
	return HORDE_CHECKS if bool(target.get("horde", false)) else CHECKS


func count_now() -> int:
	"""How many of what is being swept are on the field (an effect: how many
	a second)."""
	if BossBench.is_boss(target):
		return _wanted if BossBench.is_rate(target) else (int(_bench.call("count")) if _bench != null else 0)
	if StressKinds.is_rate(target):
		return _wanted
	if StressKinds.is_shot(target):
		return StressKinds.count_shots(get_tree(), target)
	if bool(target.get("horde", false)):
		var swarm: Node = _run().get("swarm") if _run() != null else null
		return int(swarm.get("alive")) if swarm != null else 0
	var path: String = str(target.get("path", ""))
	var count: int = 0
	for monster in get_tree().get_nodes_in_group(GmSpawner.GROUP):
		if not monster.is_queued_for_deletion() and str(monster.scene_file_path) == path:
			count += 1
	return count


func _run() -> Node:
	return ground.get("run") if ground != null else null


func centre() -> Vector2:
	"""The middle of the arena: where you stand and where they come."""
	var run: Node = _run()
	return (run.get("arena_rect") as Rect2).get_center() if run != null else Vector2.ZERO


func _place_player() -> void:
	var run: Node = _run()
	var me: Node2D = run.call("_player") as Node2D if run != null and run.has_method("_player") else null
	if me == null:
		return
	me.global_position = centre()
	me.reset_physics_interpolation()
	if "velocity" in me:
		me.set("velocity", Vector2.ZERO)


# ---- the sums -----------------------------------------------------------------------

static func line_through(through: Array, column: int) -> Array:
	"""[where it starts, how much it climbs a monster] of the straight line
	nearest every row's `column` against its count (least squares)."""
	var n: int = through.size()
	if n == 0:
		return [0.0, 0.0]
	var mean_x: float = 0.0
	var mean_y: float = 0.0
	for row in through:
		mean_x += float(row[0])
		mean_y += float(row[column])
	mean_x /= float(n)
	mean_y /= float(n)
	var spread: float = 0.0
	var together: float = 0.0
	for row in through:
		var dx: float = float(row[0]) - mean_x
		spread += dx * dx
		together += dx * (float(row[column]) - mean_y)
	if spread <= 0.0:
		return [mean_y, 0.0]
	var climb: float = together / spread
	return [mean_y - climb * mean_x, climb]


static func each_at(through: Array, count: int, base: float) -> float:
	"""(work - base) / count at the row nearest `count` - within half to twice
	it - or -1 when no row is that near."""
	var best: Array = []
	for row in through:
		if int(row[0]) <= 0:
			continue
		if best.is_empty() or absi(int(row[0]) - count) < absi(int(best[0]) - count):
			best = row
	if best.is_empty() or int(best[0]) * 2 < count or int(best[0]) > count * 2:
		return -1.0
	return (float(best[1]) - base) / float(best[0])


static func grows_with(through: Array, base: float) -> bool:
	"""True when a monster costs GROWS_AT times more each at the last row than
	at the first that stands NOISE_MS clear of the base."""
	var first: Array = []
	for row in through:
		if int(row[0]) > 0 and float(row[1]) - base > NOISE_MS:
			first = row
			break
	var last: Array = through.back() if not through.is_empty() else []
	if first.is_empty() or last == first or int(last[0]) <= 0:
		return false
	var each_first: float = (float(first[1]) - base) / float(first[0])
	var each_last: float = (float(last[1]) - base) / float(last[0])
	return each_last > each_first * GROWS_AT


static func summarise(through: Array, label: String, why: String, budget: float, checks: Array) -> Dictionary:
	var base: float = float(through[0][1]) if not through.is_empty() else 0.0
	var each: float = float(line_through(through, 1)[1])
	var at: Array = []
	for count in checks:
		at.append(each_at(through, int(count), base))
	var room: float = budget * LIMIT_AT - base
	var last: Array = through.back() if not through.is_empty() else [0, 0.0, 0.0]
	return {
		"label": label, "why": why, "budget": budget, "base": base, "each": each,
		"physics": _part_each(through, 4), "scripts": _part_each(through, 5), "drawing": _part_each(through, 6),
		"fits": maxi(0, int(floor(room / each + 0.000001))) if each > 0.0 else -1,
		"stopped": int(last[0]), "slow": float(last[2]),
		"checks": checks.duplicate(), "at": at, "grows": grows_with(through, base),
		"rows": through.duplicate(true), "device": device_name(), "version": Api.DISPLAY_VERSION,
		"when": Time.get_datetime_string_from_system(false, true),
	}


static func _part_each(through: Array, column: int) -> float:
	"""ms each of one part of the frame (a row's physics, scripts or drawing)."""
	for row in through:
		if (row as Array).size() <= column:
			return 0.0
	return float(line_through(through, column)[1])


static func ms_text(ms: float) -> String:
	if absf(ms) < 0.01:
		return "%.4f" % ms
	return "%.3f" % ms if absf(ms) < 0.1 else "%.2f" % ms


static func summary_line(summary: Dictionary) -> String:
	var label: String = str(summary.get("label", ""))
	var stopped: int = int(summary.get("stopped", 0))
	var why: String = str(WHY_WORDS.get(str(summary.get("why", "")), summary.get("why", "")))
	if str(summary.get("why", "")) == "base":
		return "%s: not measured - with nothing out the work is already %.1f ms, past the %.1f ms limit" % [label,
			float(summary.get("base", 0.0)), float(summary.get("budget", 0.0)) * LIMIT_AT]
	var per: String = str(summary.get("per", "out"))
	var unit: String = " a second" if per == "a second" else ""
	if int(summary.get("fits", -1)) < 0:
		return "%s: no cost seen up to %s%s (%s)" % [label, GameConstants.commas(stopped), unit, why]
	var line: String = "%s: %s ms each%s - about %s%s fit (stopped at %s: %s)" % [label,
		ms_text(float(summary.get("each", 0.0))), " " + per if per != "out" else "",
		GameConstants.commas(int(summary["fits"])), unit, GameConstants.commas(stopped), why]
	if bool(summary.get("grows", false)):
		line += " - costs more each as the crowd grows"
	return line


static func device_name() -> String:
	if OS.has_feature("web"):
		for pair in [["web_android", "Android"], ["web_ios", "iOS"], ["web_windows", "Windows"],
				["web_macos", "macOS"], ["web_linuxbsd", "Linux"]]:
			if OS.has_feature(str(pair[0])):
				return "Browser on %s" % str(pair[1])
		return "Browser"
	return OS.get_name()


static func copy_text(kept: Dictionary, in_order: Array, places: Dictionary = {}, place_order: Array = []) -> String:
	"""Every result as tab-separated rows for a spreadsheet: one line a
	monster, then every sweep's own rows, then every place measured."""
	var lines: PackedStringArray = ["Elusion limit sweep - one player - tab-separated"]
	lines.append("\t".join(PackedStringArray(["Monster", "Device", "Version", "Budget ms", "Base ms",
		"ms each", "Physics ms each", "Scripts ms each", "Drawing ms each", "Fits at 80%", "Stopped at",
		"Why", "Each at 10 (horde 250, shots 100)", "Each at 50 (horde 1000, shots 500)",
		"Each at 100 (horde 2500, shots 1000)", "Each at 200 (horde 5000, shots 2000)", "Grows with the crowd", "When", "Counted"])))
	for label in in_order:
		if not kept.has(label):
			continue
		var s: Dictionary = kept[label]
		var cells: PackedStringArray = [str(label), str(s.get("device", "")), str(s.get("version", "")),
			"%.2f" % float(s.get("budget", 0.0)), "%.2f" % float(s.get("base", 0.0)),
			"%.4f" % float(s.get("each", 0.0)), "%.4f" % float(s.get("physics", 0.0)),
			"%.4f" % float(s.get("scripts", 0.0)), "%.4f" % float(s.get("drawing", 0.0)),
			str(int(s.get("fits", -1))), str(int(s.get("stopped", 0))), str(s.get("why", ""))]
		var at: Array = s.get("at", [])
		for k in 4:
			var value: float = float(at[k]) if k < at.size() else -1.0
			cells.append("%.4f" % value if value >= 0.0 else "")
		cells.append("yes" if bool(s.get("grows", false)) else "no")
		cells.append(str(s.get("when", "")))
		cells.append(str(s.get("per", "out")))
		lines.append("\t".join(cells))
	lines.append("")
	lines.append("\t".join(PackedStringArray(["Monster", "Count", "Work median ms", "Slow (95th) ms", "fps",
		"Physics ms", "Scripts ms", "Drawing ms"])))
	for label in in_order:
		if not kept.has(label):
			continue
		for row in (kept[label] as Dictionary).get("rows", []):
			var cells: PackedStringArray = [str(label), str(int(row[0]))]
			for k in range(1, (row as Array).size()):
				cells.append(str(int(row[k])) if k == 3 else "%.2f" % float(row[k]))
			lines.append("\t".join(cells))
	if not place_order.is_empty():
		lines.append("")
		lines.append("\t".join(PackedStringArray(["Place", "Device", "Version", "Budget ms", "Work median ms",
			"Slow (95th) ms", "Physics ms", "Scripts ms", "Drawing ms", "fps", "When"])))
		for label in place_order:
			if not places.has(label):
				continue
			var p: Dictionary = places[label]
			lines.append("\t".join(PackedStringArray([str(label), str(p.get("device", "")), str(p.get("version", "")),
				"%.2f" % float(p.get("budget", 0.0)), "%.2f" % float(p.get("median", 0.0)),
				"%.2f" % float(p.get("p95", 0.0)), "%.2f" % float(p.get("physics", 0.0)),
				"%.2f" % float(p.get("scripts", 0.0)), "%.2f" % float(p.get("drawing", 0.0)),
				str(int(p.get("fps", 0))), str(p.get("when", ""))])))
	return "\n".join(lines)


# ---- kept ---------------------------------------------------------------------------

func _keep(summary: Dictionary) -> void:
	var label: String = str(summary["label"])
	if not summary.has("per"):
		summary["per"] = counted_as(target)
	results[label] = summary
	order.erase(label)
	order.append(label)
	save_results()


func save_results() -> void:
	if save_path == "":
		return
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({"results": results, "order": order}))


func load_results() -> void:
	if save_path == "" or not FileAccess.file_exists(save_path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not parsed is Dictionary:
		return
	var kept: Variant = (parsed as Dictionary).get("results", {})
	var in_order: Variant = (parsed as Dictionary).get("order", [])
	if kept is Dictionary and in_order is Array:
		results = kept
		order = []
		for label in in_order:
			if results.has(str(label)):
				order.append(str(label))


func copy_results() -> void:
	var kept_places: Dictionary = PlaceMeasure.read_file(places_path)
	var place_order: Array = kept_places["order"]
	if order.is_empty() and place_order.is_empty():
		status = "Nothing measured yet."
	else:
		copy_to.call(copy_text(results, order, kept_places["places"], place_order))
		status = "Copied %d sweeps and %d places - paste them into the chat." % [order.size(), place_order.size()]
	paint()


# ---- the panel's part ------------------------------------------------------------------

func build(into: VBoxContainer, width: float) -> void:
	"""THE PANEL'S PART, AT A GLANCE (0.175.1). The owner: "upgrade this ui".
	The picker, +N and Find the limit (green; Stop, red, while it runs); a
	card while it sweeps - what, how far through the list, its work climbing
	to the 80% line, what it is doing; then every result in a table, newest
	first, the whole sentence on a hover; Copy results."""
	into.add_child(HSeparator.new())
	var head := Label.new()
	head.name = "sweephead"
	head.text = "FIND THE LIMIT"
	head.add_theme_color_override("font_color", COLOUR)
	head.add_theme_font_size_override("font_size", 12)
	head.mouse_filter = Control.MOUSE_FILTER_PASS
	head.tooltip_text = "Brings more and more of one monster round you (in God mode, in the middle) until the work reaches %d%% of the budget:\nwhat one costs, and how many fit. Stand still - or fight, to count your attacks too.\nEvery shot and Every effect do the same with shots in the air and effects a second;\nEvery boss attack the Crowned's attacks one by one, and The Crowned's phases its fight part by part." \
		% roundi(LIMIT_AT * 100.0)
	into.add_child(head)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	into.add_child(row)
	_picker = OptionButton.new()
	_picker.name = "sweeppick"
	_picker.fit_to_longest_item = false
	_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker.focus_mode = Control.FOCUS_NONE
	_picker.add_theme_font_size_override("font_size", 12)
	var listed: Array = GmSpawner.catalogue()
	var kinds: Dictionary = {}
	for entry in listed:
		kinds[int(entry["kind"])] = true
	_add_pick("Every kind (%d)" % (kinds.size() + 1), EVERY_KIND)
	_add_pick("Every monster (%d)" % (listed.size() + 1), EVERY_MONSTER)
	_add_pick(HORDE, HORDE)
	_add_pick("Every shot (%d)" % StressKinds.shots().size(), EVERY_SHOT)
	_add_pick("Every effect (%d)" % StressKinds.effects().size(), EVERY_EFFECT)
	_add_pick("Every boss attack (%d)" % BossBench.attacks().size(), EVERY_BOSS)
	_add_pick("The Crowned's phases (%d)" % BossBench.phases().size(), BOSS_PHASES)
	for entry in listed:
		_add_pick(str(entry["label"]), str(entry["path"]))
	_picker.item_selected.connect(_on_picked)
	row.add_child(_picker)
	_step_box = SpinBox.new()
	_step_box.name = "sweepstep"
	_step_box.min_value = 1
	_step_box.max_value = HORDE_STEP
	_step_box.value = STEP
	_step_box.prefix = "+"
	_step_box.tooltip_text = "How many more each time (a list's bosses +%d, the horde +%d)." % [BOSS_STEP, HORDE_STEP]
	_step_box.get_line_edit().add_theme_font_size_override("font_size", 12)
	row.add_child(_step_box)
	_go = Button.new()
	_go.name = "sweepgo"
	_go.focus_mode = Control.FOCUS_NONE
	_go.add_theme_font_size_override("font_size", 12)
	_go.pressed.connect(_on_go)
	row.add_child(_go)

	# The card while it sweeps.
	_card = PanelContainer.new()
	_card.name = "sweepcard"
	var card_look := StyleBoxFlat.new()
	card_look.bg_color = Color(1.0, 1.0, 1.0, 0.05)
	card_look.border_color = Color(COLOUR, 0.3)
	card_look.set_border_width_all(1)
	card_look.set_corner_radius_all(3)
	card_look.set_content_margin_all(6.0)
	_card.add_theme_stylebox_override("panel", card_look)
	into.add_child(_card)
	var card_rows := VBoxContainer.new()
	card_rows.add_theme_constant_override("separation", 3)
	_card.add_child(card_rows)
	var name_row := HBoxContainer.new()
	card_rows.add_child(name_row)
	_card_name = _label("sweepname", 15, COLOUR)
	_card_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_card_name.clip_text = true
	name_row.add_child(_card_name)
	_card_of = _label("sweepof", 12, COLOUR_TEXT)
	name_row.add_child(_card_of)
	_list_bar = WorkBar.make(4.0)
	_list_bar.name = "sweeplistbar"
	card_rows.add_child(_list_bar)
	var work_row := HBoxContainer.new()
	work_row.add_theme_constant_override("separation", 6)
	card_rows.add_child(work_row)
	_card_count = _label("sweepcount", 12, COLOUR_TEXT)
	_card_count.custom_minimum_size = Vector2(112.0, 0.0)
	work_row.add_child(_card_count)
	_card_bar = WorkBar.make(8.0)
	_card_bar.name = "sweepworkbar"
	work_row.add_child(_card_bar)
	_card_work = _label("sweepwork", 12, COLOUR_TEXT)
	_card_work.custom_minimum_size = Vector2(76.0, 0.0)
	_card_work.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	work_row.add_child(_card_work)
	_card_doing = _label("sweepdoing", 11, FAINT)
	card_rows.add_child(_card_doing)

	# A line said once (done, stopped, copied), under the controls.
	_status_label = _label("sweepstatus", 12, COLOUR)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size = Vector2(width - 16.0, 0.0)
	into.add_child(_status_label)

	# Every result, a row each.
	_table = VBoxContainer.new()
	_table.name = "sweeptable"
	_table.add_theme_constant_override("separation", 0)
	into.add_child(_table)
	var header := _result_row(["Swept", "ms each", "Fits", "Stopped"], -1)
	header.name = "sweepheader"
	_table.add_child(header)
	_scroll = ScrollContainer.new()
	_scroll.name = "sweepscroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_table.add_child(_scroll)
	_results_box = VBoxContainer.new()
	_results_box.name = "sweepresults"
	_results_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_results_box.add_theme_constant_override("separation", 0)
	_scroll.add_child(_results_box)
	_hint = _label("sweephint", 11, COLOUR_TEXT)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(width - 16.0, 0.0)
	_hint.text = "Pick a monster: it comes +%d at a time round you until the work reaches %d%% of the budget." \
		% [STEP, roundi(LIMIT_AT * 100.0)]
	into.add_child(_hint)
	var bottom := HBoxContainer.new()
	into.add_child(bottom)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(gap)
	var copy := Button.new()
	copy.name = "sweepcopy"
	copy.text = "Copy results"
	copy.tooltip_text = "Every result, as rows to paste into a spreadsheet."
	copy.focus_mode = Control.FOCUS_NONE
	copy.add_theme_font_size_override("font_size", 12)
	copy.pressed.connect(copy_results)
	bottom.add_child(copy)
	paint()


static func _label(label_name: String, font_size: int, colour: Color) -> Label:
	var label := Label.new()
	label.name = label_name
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	return label


func _result_row(cells: Array, index: int) -> Control:
	"""A row of the table: the header (`index` -1) or result `index` (0 the
	newest), [name, ms each, fits, stopped] - fits a number, or with a
	result's summary a bar and the number."""
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", WorkBar.row_look(index >= 0 and index % 2 == 1))
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)
	var font: int = 11
	var colour: Color = FAINT if index < 0 else COLOUR_TEXT
	var named := _label("name", font, colour)
	named.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	named.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	named.clip_text = true
	named.text = str(cells[0])
	line.add_child(named)
	var rise: Control = WorkBar.make(7.0, 7.0)
	rise.name = "grows"
	rise.set("shape", WorkBar.Shape.RISE)
	rise.set("colour", WorkBar.AMBER)
	rise.visible = index >= 0 and bool(cells[4]) if cells.size() > 4 else false
	line.add_child(rise)
	var each := _label("each", font, colour)
	each.custom_minimum_size = Vector2(COLUMN_EACH, 0.0)
	each.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	each.text = str(cells[1])
	line.add_child(each)
	var fits_cell := HBoxContainer.new()
	fits_cell.custom_minimum_size = Vector2(COLUMN_FITS, 0.0)
	fits_cell.add_theme_constant_override("separation", 4)
	fits_cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(fits_cell)
	var bar: Control = WorkBar.make(6.0)
	bar.name = "fitsbar"
	bar.visible = index >= 0
	fits_cell.add_child(bar)
	var fits := _label("fits", font, colour)
	fits.custom_minimum_size = Vector2(COLUMN_FITS_NUMBER, 0.0)
	fits.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fits.size_flags_horizontal = Control.SIZE_EXPAND_FILL if index < 0 else Control.SIZE_FILL
	fits.text = str(cells[2])
	fits_cell.add_child(fits)
	var why := _label("why", font, colour)
	why.custom_minimum_size = Vector2(COLUMN_WHY, 0.0)
	why.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	why.text = str(cells[3])
	line.add_child(why)
	return row


static func short_why(why: String) -> String:
	"""What stopped a sweep, in a word for the table's last column."""
	return str(WHY_SHORT.get(why, why))


static func fits_fraction(fits: int, most: int) -> float:
	"""How long a result's fits bar is: on a log scale against the most that
	fit of any result, so 80 and 5,000 both show."""
	if fits <= 0 or most <= 1:
		return 0.0
	return clampf(log(float(fits) + 1.0) / log(float(most) + 1.0), 0.04, 1.0)


static func fits_colour(fits: int) -> Color:
	"""Few fit, red; a few hundred, amber; many, green."""
	if fits < FEW:
		return WorkBar.RED
	if fits < SOME:
		return WorkBar.AMBER
	return WorkBar.GREEN


func _fill_table() -> void:
	"""Every result as a row, newest first; rebuilt only when they change."""
	if _results_box == null:
		return
	var key: String = "%d|%s" % [order.size(), str(order.back()) + str((results.get(order.back(), {}) as Dictionary).get("when", "")) if not order.is_empty() else ""]
	if key == _table_key:
		return
	_table_key = key
	for child in _results_box.get_children():
		_results_box.remove_child(child)
		child.queue_free()
	var most: int = 1
	for label in order:
		most = maxi(most, int((results[label] as Dictionary).get("fits", 0)))
	var index: int = 0
	for k in range(order.size() - 1, -1, -1):
		var summary: Dictionary = results[order[k]]
		var fits: int = int(summary.get("fits", -1))
		var why: String = str(summary.get("why", ""))
		var row: Control = _result_row([str(summary.get("label", order[k])),
			"-" if why == "base" else ms_text(float(summary.get("each", 0.0))),
			GameConstants.commas(fits) if fits >= 0 else "-", short_why(why), bool(summary.get("grows", false))], index)
		row.name = "result%d" % index
		row.tooltip_text = summary_line(summary) + ("\n(%s)" % str(summary.get("per", "out")) if str(summary.get("per", "out")) != "out" else "")
		var bar: Control = row.find_child("fitsbar", true, false)
		if bar != null:
			bar.call("show_value", fits_fraction(fits, most), fits_colour(fits))
		_results_box.add_child(row)
		index += 1
	_scroll.custom_minimum_size = Vector2(0.0, ROW_HEIGHT * float(mini(order.size(), ROWS_SHOWN)))
	# The header over the columns, not over the scroll bar's room.
	var header: PanelContainer = _table.get_node_or_null(^"sweepheader") as PanelContainer
	if header != null:
		var look: StyleBoxFlat = WorkBar.row_look(false)
		if order.size() > ROWS_SHOWN:
			look.content_margin_right += _scroll.get_v_scroll_bar().get_combined_minimum_size().x
		header.add_theme_stylebox_override("panel", look)
	_table.visible = not order.is_empty()
	_hint.visible = order.is_empty() and not running()


func _add_pick(label: String, key: String) -> void:
	_picker.add_item(label)
	_picker.set_item_metadata(_picker.item_count - 1, key)


func picked() -> String:
	return str(_picker.get_item_metadata(_picker.selected)) if _picker != null and _picker.selected >= 0 else EVERY_KIND


func _on_picked(index: int) -> void:
	var key: String = str(_picker.get_item_metadata(index))
	if key == HORDE:
		_step_box.value = HORDE_STEP
		return
	for entry in GmSpawner.catalogue():
		if str(entry["path"]) == key:
			_step_box.value = BOSS_STEP if is_boss(entry) else STEP
			return
	_step_box.value = STEP


func _on_go() -> void:
	if running():
		stop()
	else:
		begin(picked(), int(_step_box.value) if _step_box != null else STEP)


func _say(doing: String) -> void:
	_doing = doing
	var where: String = " (%d of %d)" % [queue_size - queue.size(), queue_size] if queue_size > 1 else ""
	var said: String = "%s%s: %s %s - %s" % [str(target.get("label", "")), where,
		GameConstants.commas(count_now()), counted_as(target), doing]
	if not rows.is_empty():
		var last: Array = rows.back()
		said += "  ·  at %s: work %.1f · slow %.1f ms" % [GameConstants.commas(int(last[0])),
			float(last[1]), float(last[2])]
	status = said
	paint()


func paint() -> void:
	if ground != null and ground.has_method("hold_controls"):
		ground.call("hold_controls", running())
	if _go == null:
		return
	_go.text = "Stop" if running() else "Find the limit"
	WorkBar.dress_go(_go, running())
	_picker.disabled = running()
	_step_box.editable = not running()
	# The card while it sweeps; the line said once when it does not.
	_card.visible = running()
	_status_label.text = status
	_status_label.visible = status != "" and not running()
	if running():
		var budget: float = PerfOverlay.budget_ms()
		var done: int = queue_size - queue.size()
		_card_name.text = str(target.get("label", ""))
		_card_of.text = "%d of %d" % [done, queue_size] if queue_size > 1 else ""
		_list_bar.visible = queue_size > 1
		_list_bar.call("show_value", float(done - 1) / float(maxi(queue_size, 1)), Color(COLOUR, 0.8))
		_card_count.text = "%s %s" % [GameConstants.commas(count_now()), counted_as(target)]
		if rows.is_empty() or budget <= 0.0:
			_card_bar.call("show_value", 0.0, WorkBar.GREEN, -1.0, LIMIT_AT)
			_card_work.text = "-"
		else:
			var last: Array = rows.back()
			var median: float = float(last[1])
			var slow: float = float(last[2])
			_card_bar.call("show_value", median / budget, WorkBar.work_colour(median, slow, budget), slow / budget, LIMIT_AT)
			_card_work.text = "%.1f / %.1f ms" % [median, budget * LIMIT_AT]
		_card_doing.text = _doing
	_fill_table()
	if _hint != null:
		_hint.visible = order.is_empty() and not running()
