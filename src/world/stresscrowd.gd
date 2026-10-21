# stresscrowd.gd - the owner's stress test (0.65.0): more of the Big Field's
# monsters, in this game only. Added to every area by AreaRegistry, the way
# EnemySleeper is; it does nothing outside the areas in AREAS.
#
# The owner, 21 Oct: "first we need to stress test the game with 2x the
# enemies in big field" - and he chose a switch on the owner panel's Testing
# tab over putting them in the scene for everybody.
#
# COPIES, NOT NEW KINDS. Each monster the area was authored with gets
# (multiplier - 1) more of its own scene beside it, with its settings (the
# respawner's kept_settings(): its leash), on the floor a few steps away and
# never near where players arrive. They chase, fight, sleep and wake like any
# monster - the cost on the machine is real, which is the point.
#
# THIS GAME'S ALONE, AND WORTH NOTHING:
#   - no kill report: BaseEnemy.get_enemy_id() is "" for a copy, so no XP, no
#     bag, and the server's kill ceilings and fraud watch (killwatch.py) never
#     see a kill they could not have expected;
#   - never numbered by monstersync.gd, so no other game hears of them, and
#     neither do the server's books;
#   - not in the respawner's census. A copy that dies is brought back here,
#     after the wait the monster it copies would take.
#
# BUILT BY THE CLOCK, A FEW MILLISECONDS A FRAME (0.65.1). Four times the Big
# Field is a thousand new monsters, and building them in one frame is a
# second-long freeze - exactly what a stress test must not cause itself. It
# was 24 a frame; the owner's 4x run opened with 111 hitches and a 66 ms
# frame from the building alone, because 24 skeletons is 40 ms on his
# machine. Now each frame builds until BUILD_MS is spent, and taking them
# away is spread the same way.
#
# BORN ASLEEP WHEN NOBODY IS NEAR: a copy built further than the sleeper's
# SLEEP_DISTANCE from every player starts the way enemysleeper.gd would put
# it within a quarter second - not thinking - so a thousand new monsters are
# not all awake for that quarter second.
#
# Survives walking between areas (a static); always off after a restart.
extends Node

const NODE_NAME := "stresscrowd"
const GROUP := &"stresscrowd"
const META := &"stress_copy"
const AREAS := ["res://scene/bigfield.tscn"]
# What the owner panel offers. 1 is off.
const MULTIPLIERS := [1, 2, 3, 4, 6, 8]
# How far from the monster it copies a copy stands, in px.
const SPREAD_MIN := 20.0
const SPREAD_MAX := 56.0
# Nothing new within this of where players arrive - the Big Field's own rule.
const ARRIVAL_CLEAR := 400.0
# How long a frame may spend building or taking away copies, in ms.
const BUILD_MS := 3.0
const RESPAWN_FALLBACK := 30.0

const EnemyRespawnerScript := preload("res://src/world/enemyrespawner.gd")
const EnemySleeperScript := preload("res://src/world/enemysleeper.gd")
const Targets := preload("res://src/shared/targets.gd")

static var multiplier: int = 1

# The suite's: a refill wait in place of the copied monster's own, when >= 0.
var refill_seconds_override: float = -1.0

var _area: Node = null
var _sources: Array = []      # one per authored monster: what to copy, and where
var _copies: Array = []       # [{source index, node id}] - what this has put in
var _generation: int = 0


static func add_to(scene: Node) -> Node:
	var crowd: Node = (load("res://src/world/stresscrowd.gd") as GDScript).new() as Node
	crowd.name = NODE_NAME
	scene.add_child(crowd)
	return crowd


static func set_multiplier(n: int, tree: SceneTree) -> void:
	"""The owner panel's switch: how many of each monster there are, now and in
	every area entered from here on."""
	multiplier = n if n in MULTIPLIERS else 1
	if tree == null:
		return
	for crowd in tree.get_nodes_in_group(GROUP):
		crowd.call("apply")


static func is_copy(node: Node) -> bool:
	return node != null and node.has_meta(META)


func _ready() -> void:
	add_to_group(GROUP)
	_area = get_parent()
	# Walking into the Big Field with the switch already on.
	if multiplier > 1:
		apply()


func applies() -> bool:
	return _area != null and _area.scene_file_path in AREAS


func copy_count() -> int:
	var alive: int = 0
	for entry in _copies:
		var node: Object = instance_from_id(int(entry["id"]))
		if node != null and is_instance_valid(node) and not (node as Node).is_queued_for_deletion():
			alive += 1
	return alive


func source_count() -> int:
	return _sources.size()


func apply() -> void:
	"""Bring the copies to what the switch says: build the missing ones a few a
	frame, or take them all away."""
	if not applies() or not is_inside_tree():
		return
	_generation += 1
	var generation: int = _generation
	if multiplier <= 1:
		await _remove_all(generation)
		return
	if _sources.is_empty():
		await _take_census()
		if generation != _generation or not is_inside_tree():
			return
	_prune()
	var want: int = multiplier - 1
	var have: Dictionary = {}
	for entry in _copies:
		have[int(entry["source"])] = int(have.get(int(entry["source"]), 0)) + 1
	# Too many (4x down to 2x): the extra ones go.
	var kept: Array = []
	var going: Array = []
	for entry in _copies:
		var source: int = int(entry["source"])
		if int(have.get(source, 0)) > want:
			have[source] = int(have[source]) - 1
			going.append(entry)
		else:
			kept.append(entry)
	_copies = kept
	if not await _free_by_the_clock(going, generation):
		return
	var spots: Array[Vector2] = _player_spots()
	var started: int = Time.get_ticks_usec()
	for source in _sources.size():
		for k in maxi(want - int(have.get(source, 0)), 0):
			_build_copy(source, spots)
			if Time.get_ticks_usec() - started >= int(BUILD_MS * 1000.0):
				await get_tree().process_frame
				if generation != _generation or not is_inside_tree():
					return
				spots = _player_spots()
				started = Time.get_ticks_usec()


func _take_census() -> void:
	"""What the area was authored with, once: its monsters as they stand before
	anything has died. Waits for the navigation, which says what is floor."""
	await get_tree().process_frame
	await get_tree().process_frame
	var map: RID = (_area as Node2D).get_world_2d().navigation_map if _area is Node2D else RID()
	for i in 60:
		if not map.is_valid() or NavigationServer2D.map_get_iteration_id(map) > 0:
			break
		await get_tree().physics_frame
	var arrivals: Array[Vector2] = []
	for marker in _area.find_children("arrivalmarker", "Marker2D", true, false):
		arrivals.append((marker as Node2D).global_position)
	var respawner: Node = _area.find_child("enemyrespawner", true, false)
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Node2D
		if enemy == null or is_copy(enemy) or enemy.scene_file_path == "" or not _area.is_ancestor_of(enemy) \
				or not (enemy.get_parent() is Node2D):
			continue
		var packed: PackedScene = load(enemy.scene_file_path) as PackedScene
		if packed == null:
			continue
		var wait: float = RESPAWN_FALLBACK
		if respawner != null and respawner.has_method("respawn_time_for"):
			wait = float(respawner.call("respawn_time_for", enemy))
		_sources.append({
			"packed": packed,
			"home": enemy.global_position,
			"parent": enemy.get_parent(),
			"kept": EnemyRespawnerScript.kept_settings(enemy),
			"respawn": wait,
			"name": str(enemy.name),
			"map": map,
			"arrivals": arrivals,
		})


func _player_spots() -> Array[Vector2]:
	"""Where everybody the monsters may chase stands - the sleeper's own list."""
	var spots: Array[Vector2] = []
	if not is_inside_tree():
		return spots
	for body in Targets.all(get_tree()):
		spots.append((body as Node2D).global_position)
	return spots


func _build_copy(source: int, spots: Array[Vector2] = []) -> void:
	var entry: Dictionary = _sources[source]
	var parent: Node2D = entry["parent"] as Node2D
	if parent == null or not is_instance_valid(parent) or not parent.is_inside_tree():
		return
	var spot: Variant = _spot_near(entry)
	if spot == null:
		return
	var enemy := (entry["packed"] as PackedScene).instantiate() as Node2D
	if enemy == null:
		return
	var kept: Dictionary = entry["kept"]
	for property in kept:
		enemy.set(property, kept[property])
	enemy.set_meta(META, true)
	enemy.name = "stress_%s_%d" % [entry["name"], _copies.size()]
	# Asleep from the start when nobody is near (see BORN ASLEEP above). With
	# nobody in the world at all the sleeper sleeps nobody, so neither does this.
	var far: bool = not spots.is_empty()
	for at in spots:
		if (at as Vector2).distance_to(spot) <= EnemySleeperScript.SLEEP_DISTANCE:
			far = false
			break
	if far:
		enemy.process_mode = Node.PROCESS_MODE_DISABLED
		enemy.set_meta(&"asleep", true)
	# Before add_child(): BaseEnemy._ready() reads its spot as home.
	enemy.position = parent.to_local(spot)
	parent.add_child(enemy)
	enemy.global_position = spot
	enemy.reset_physics_interpolation()
	if "spawn_position" in enemy:
		enemy.set("spawn_position", spot)
	_copies.append({"source": source, "id": enemy.get_instance_id()})
	if enemy.has_signal("died"):
		enemy.died.connect(_on_copy_died.bind(source), CONNECT_ONE_SHOT)


func _spot_near(entry: Dictionary) -> Variant:
	"""A spot on the floor beside the monster being copied, clear of where
	players arrive; null when eight tries find none."""
	var home: Vector2 = entry["home"]
	var map: RID = entry["map"]
	for attempt in 8:
		var angle: float = randf() * TAU
		var spot: Vector2 = home + Vector2.from_angle(angle) * randf_range(SPREAD_MIN, SPREAD_MAX)
		if map.is_valid():
			var floor_at: Vector2 = NavigationServer2D.map_get_closest_point(map, spot)
			if floor_at.distance_to(spot) > 1.5:
				continue
		var near_arrival: bool = false
		for arrival in entry["arrivals"]:
			if (arrival as Vector2).distance_to(spot) < ARRIVAL_CLEAR:
				near_arrival = true
				break
		if near_arrival:
			continue
		return spot
	return null


func _on_copy_died(source: int) -> void:
	# Back after the wait the monster it copies would take - then only if the
	# switch still wants it, in a world still here.
	if not is_inside_tree():
		return
	var wait: float = refill_seconds_override if refill_seconds_override >= 0.0 \
		else float(_sources[source].get("respawn", RESPAWN_FALLBACK))
	var generation: int = _generation
	await get_tree().create_timer(wait).timeout
	if not is_instance_valid(self) or not is_inside_tree() or generation != _generation:
		return
	_prune()
	var have: int = 0
	for entry in _copies:
		if int(entry["source"]) == source:
			have += 1
	if have < multiplier - 1:
		_build_copy(source)


func _prune() -> void:
	var alive: Array = []
	for entry in _copies:
		var node: Object = instance_from_id(int(entry["id"]))
		if node != null and is_instance_valid(node) and not (node as Node).is_queued_for_deletion():
			alive.append(entry)
	_copies = alive


func _remove_all(generation: int) -> void:
	var going: Array = _copies
	_copies = []
	await _free_by_the_clock(going, generation)


func _free_by_the_clock(going: Array, generation: int) -> bool:
	"""Take these copies away, BUILD_MS a frame. False when the switch moved
	or the area went while it was at it."""
	var started: int = Time.get_ticks_usec()
	for entry in going:
		var node: Object = instance_from_id(int(entry["id"]))
		if node != null and is_instance_valid(node):
			(node as Node).queue_free()
		if Time.get_ticks_usec() - started >= int(BUILD_MS * 1000.0):
			await get_tree().process_frame
			if generation != _generation or not is_inside_tree():
				return false
			started = Time.get_ticks_usec()
	return true
