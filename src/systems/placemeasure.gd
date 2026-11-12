extends Node
# placemeasure.gd - MEASURE HERE (0.152.0): the readout's Measure button.
#
# The owner, of the limit tests: "you can do most of this for me i only need
# to share the real results". An area's own cost (the master result's "area
# base") and a party's (its "party extra") were to be readout copies pasted
# one by one. Now: stand where the test says, press Measure on the readout,
# and the game measures its own work - SETTLE_SECONDS to settle, then FRAMES
# frames (PerfOverlay.work_stats(): the median, the slow 95th percentile and
# each part's median) - and keeps it under a label that says where and what
# (place_label(): the area, in the Endless the stage, the slimes and other
# monsters out, a party and whether this game leads it; and any
# minigame's own measure_label() - floor and room, wave, tier, round). Kept
# in save_path, the newest KEPT_MOST, one per label (measured again,
# replaced). The Testing
# Ground's Copy results (limitsweep.gd) puts them with the sweeps, so one
# paste carries every result.
#
# A child of PerfOverlay (the autoload), so it lives across areas. It counts
# only while the readout is up, as the readout does; closing the readout
# stops a measure (cancel()).

const SETTLE_SECONDS := 3.0
const FRAMES := 120
const KEPT_MOST := 60
const SAVED_SHOWN := 2.0

enum Phase { IDLE, SETTLING, MEASURING }

var overlay: Node = null
var save_path: String = "user://limitplaces.json"
# Where it is now, in words (a seam for the suite).
var label_now: Callable = Callable()
var phase: int = Phase.IDLE
var places: Dictionary = {}
var order: Array = []
var last_line: String = ""
var _left: float = 0.0
var _label: String = ""
var _saved_left: float = 0.0


func _ready() -> void:
	load_places()
	set_process(false)


func start() -> void:
	"""Measure here: settle, then FRAMES frames of the game's own work."""
	if phase != Phase.IDLE:
		return
	_label = str(label_now.call()) if label_now.is_valid() else place_label(get_tree())
	phase = Phase.SETTLING
	_left = SETTLE_SECONDS
	_saved_left = 0.0
	set_process(true)


func cancel() -> void:
	phase = Phase.IDLE
	_saved_left = 0.0
	set_process(false)


func word() -> String:
	"""What the readout's button says now."""
	match phase:
		Phase.SETTLING:
			return "Wait %d" % ceili(maxf(_left, 0.0))
		Phase.MEASURING:
			return "Measuring"
	return "Saved" if _saved_left > 0.0 else "Measure"


func _process(delta: float) -> void:
	match phase:
		Phase.SETTLING:
			_left -= delta
			if _left <= 0.0 and overlay != null:
				overlay.call("forget_work")
				phase = Phase.MEASURING
		Phase.MEASURING:
			if overlay != null and int(overlay.call("work_frames")) >= FRAMES:
				keep(_label, overlay.call("work_stats", FRAMES))
				phase = Phase.IDLE
				_saved_left = SAVED_SHOWN
		_:
			_saved_left -= delta
			if _saved_left <= 0.0:
				set_process(false)


func keep(label: String, stats: Dictionary) -> void:
	var entry: Dictionary = {
		"label": label, "median": float(stats.get("median", 0.0)), "p95": float(stats.get("p95", 0.0)),
		"physics": float(stats.get("physics", 0.0)), "scripts": float(stats.get("scripts", 0.0)),
		"drawing": float(stats.get("drawing", 0.0)), "fps": roundi(Engine.get_frames_per_second()),
		"budget": float(overlay.call("budget_ms")) if overlay != null else 0.0,
		"device": device_name(), "version": Api.DISPLAY_VERSION,
		"when": Time.get_datetime_string_from_system(false, true),
	}
	places[label] = entry
	order.erase(label)
	order.append(label)
	while order.size() > KEPT_MOST:
		places.erase(order.pop_front())
	last_line = "%s: work %.1f ms, slow %.1f ms" % [label, entry["median"], entry["p95"]]
	save_places()


static func place_label(tree: SceneTree) -> String:
	"""Where this game is and what is out, in words: "The Endless - stage 10 -
	1,240 slimes - 18 other monsters - party of 4, leading"."""
	var area: String = AreaRegistry.current_area_id()
	var bits: Array = [AreaRegistry.display_name(area) if area != "" else "Somewhere"]
	var scene: Node = tree.current_scene if tree != null else null
	var run: Node = scene.get_node_or_null(^"endlessrun") if scene != null else null
	if run != null:
		if bool(run.get("testing")):
			bits[0] = str(bits[0]) + " (Testing Ground)"
		elif int(run.get("state")) == 1:
			bits.append("stage %d" % int(run.get("stage")))
		var swarm: Node = run.get("swarm")
		if swarm != null:
			bits.append("%s slimes" % GameConstants.commas(int(swarm.get("alive"))))
	# A MINIGAME NAMES ITSELF (0.152.0): every run in "minigame_run" says
	# where it stands (measure_label()) - the Healer's Run over the town too.
	if tree != null:
		for minigame in tree.get_nodes_in_group(&"minigame_run"):
			if minigame.has_method(&"measure_label") and not minigame.is_queued_for_deletion():
				bits.append(str(minigame.call(&"measure_label")))
	var others: int = 0
	if tree != null:
		for monster in tree.get_nodes_in_group(&"enemies"):
			# The swarm's stand-ins (swarmproxy.gd) are slimes, counted above.
			if not monster.is_queued_for_deletion() and not monster.has_method(&"pass_key"):
				others += 1
	bits.append("%s other monsters" % GameConstants.commas(others))
	if Party.in_one():
		var leading: bool = false
		var party: Node = run.get("party") if run != null else null
		if party != null and party.has_method(&"leads"):
			leading = bool(party.call("active")) and bool(party.call("leads"))
		bits.append("party of %d%s" % [Party.members.size(), ", leading" if leading else ""])
	return " - ".join(bits)


static func device_name() -> String:
	if OS.has_feature("web"):
		for pair in [["web_android", "Android"], ["web_ios", "iOS"], ["web_windows", "Windows"],
				["web_macos", "macOS"], ["web_linuxbsd", "Linux"]]:
			if OS.has_feature(str(pair[0])):
				return "Browser on %s" % str(pair[1])
		return "Browser"
	return OS.get_name()


func save_places() -> void:
	if save_path == "":
		return
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({"places": places, "order": order}))


func load_places() -> void:
	var kept: Dictionary = read_file(save_path)
	places = kept["places"]
	order = kept["order"]


static func read_file(path: String) -> Dictionary:
	"""{"places", "order"} from a file of them, empty when there is none."""
	var out: Dictionary = {"places": {}, "order": []}
	if path == "" or not FileAccess.file_exists(path):
		return out
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return out
	var kept: Variant = (parsed as Dictionary).get("places", {})
	var in_order: Variant = (parsed as Dictionary).get("order", [])
	if kept is Dictionary and in_order is Array:
		out["places"] = kept
		for label in in_order:
			if (kept as Dictionary).has(str(label)):
				(out["order"] as Array).append(str(label))
	return out
