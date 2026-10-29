# buildfield.gd - writes scene/field.tscn, the Field, from the build file
# tools/maps/field.py makes (0.94.2).
#
# The Big Field's builder (buildbigfield.gd) does it all - the floor, the
# walls piece by piece, the doors, the props, the arrival portal, the
# navigation - and this changes only what the Field has of its own: the
# ladder down to the boss, the boss gate with a lever either side (the names
# the suite and the server know: spikedoor, spikedoor2, spikedoor3,
# levergatesout, levergatesin), and monsters that keep their own leash.
#
# Run once from a scene (build_field()); running it again writes the map
# afresh and loses anything changed in the scene by hand - change the plan
# instead (tools/maps/: python3 field.py SEED OUT_DIR, then copy
# OUT_DIR/field_build.json over tools/maps/field_build.json).
#
# THE OWNER, 28 Oct: "work on the next map field". The plan (MAPS_PLAN.txt,
# PART 2 and THE FIELD CANDIDATES; seed 38, candidate B): you arrive top
# left from the Big Field's ladder; a fire route goes over the top and down
# the right (tier 4), a dark route down the left and along the bottom
# (tier 5), round a solid middle; both end in the exit hall, a skeleton guard
# by the outer lever, the spike gate, and the ladder's room below.
extends "res://src/tools/buildbigfield.gd"

const FIELD_SCENE := "res://scene/field.tscn"
const FIELD_PLAN := "res://tools/maps/field_build.json"
const BOSS_ARENA := "res://scene/bossarena.tscn"
const GATE_NAMES := ["spikedoor", "spikedoor2", "spikedoor3"]


func _init() -> void:
	root_name = "field"


func build_field(build_path: String = FIELD_PLAN, out_path: String = FIELD_SCENE) -> int:
	return build(build_path, out_path)


func _ladder(interactables: Node, at: Vector2) -> void:
	"""The way down to the boss, and where a player climbing back up lands."""
	var ladder: Node = _place("res://scene/ladderdown.tscn", interactables, at, "ladderdown")
	ladder.set("collision_layer", 16)
	ladder.set("collision_mask", 4)
	ladder.set("destination_scene_path", BOSS_ARENA)
	ladder.set("target_spawn_id", "boss_entrance")
	ladder.connect("body_entered", Callable(ladder, "_on_body_entered"), CONNECT_PERSIST)
	ladder.connect("body_exited", Callable(ladder, "_on_body_exited"), CONNECT_PERSIST)
	var back := Node2D.new()
	back.name = "ladderarrival"
	back.position = at + Vector2(0, 27)
	back.set_script(load("res://src/world/fieldportal.gd"))
	back.set("portal_id", "boss_ladder")
	_own(back, interactables)


func _gates(interactables: Node, gates: Array) -> void:
	"""The boss gate: three spike doors across the passage down (on the root,
	so a lever's targets are three levels up), the outer lever in the exit
	hall and the inner one by the ladder."""
	if gates.is_empty():
		return
	var gate: Dictionary = gates[0]
	var targets: Array[NodePath] = []
	for k in mini(GATE_NAMES.size(), (gate["spikes"] as Array).size()):
		_place("res://scene/interactables/spikedoor.tscn", _root, _vec(gate["spikes"][k]), GATE_NAMES[k])
		targets.append(NodePath("../../../" + GATE_NAMES[k]))
	var outside: Node = _place("res://scene/interactables/lever.tscn", interactables, _vec(gate["lever_out"]),
		"levergatesout")
	outside.set("targets", targets)
	var inside: Node = _place("res://scene/interactables/lever.tscn", interactables, _vec(gate["lever_in"]),
		"levergatesin")
	inside.set("targets", targets.duplicate())


func _monsters(enemies: Node, monsters: Array) -> void:
	"""Each named by land and kind, as the Big Field's; a leash only when the
	plan gives one - the Field's keep their own."""
	var count: Dictionary = {}
	for m in monsters:
		var kind: String = str(m["scene"])
		var land: String = str(m["land"])
		count[land] = int(count.get(land, 0)) + 1
		var label: String = "%s_%03d_%s" % [land, int(count[land]), kind]
		var monster: Node = _place(ENEMY % kind, enemies, Vector2(float(m["x"]), float(m["y"])), label)
		if m.has("leash"):
			monster.set("leash_range", float(m["leash"]))
