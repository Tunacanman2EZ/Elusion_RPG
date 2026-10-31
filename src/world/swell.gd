# swell.gd - THE SWELL (0.97.1): while a land stirs, its monsters in the Big
# Field come in numbers.
#
# The owner: "lets make the tests into a real feature that changes with the
# land we can customize it more in hud" - the stress test (stresscrowd.gd)
# made real. While a land stirs (Lands, the server's word), every monster of
# it the Big Field was authored with has (Lands.swell_size() - 1) more of its
# kind beside it. The size is the owner's (GM panel > World > Swell, 2x to
# 4x; the server's world settings, "swell").
#
# REAL, NOT COPIES. A stress copy is this game's alone and worth nothing. A
# swell monster carries no mark that stops it paying (BaseEnemy
# get_enemy_id()), so its kill is reported and paid like any monster's; it
# has no net_origin of its authored monster's, so monstersync.gd numbers it
# and every game in the area draws and fights it; and its net_origin is the
# authored spot's plus MARK and its number ("ysortworld/enemies/
# water_001_watersprite#swell1"), which the server's books take as on the map
# while that land stirs (the API's combatbook.py, _judge_swell()) - so its
# death is AGREED and pays even with kill receipts on - and the kill ceiling
# counts (kill/routes.py).
#
# ONLY THE GAME RUNNING THE AREA builds them, as the respawner only respawns
# there (_has_authority()). A game that takes the area over finds the ones
# standing by their origins (_adopt()) and carries on with them.
#
# WHERE: beside its monster, as the stress test places a copy (_spot_near(),
# _in_sight(): on the floor, in sight of it, clear of where players arrive),
# a few a frame (BUILD_MS), asleep when nobody is near.
#
# KILLED: back after its monster's own respawn wait, at a new spot beside it,
# never within PLAYER_CLEAR of anybody - while its land still stirs.
#
# THE STIR ENDS (or moves on, or the size comes down): each one too many goes
# once it is out of a fight (not `engaged`), so nobody's target vanishes
# mid-swing. Checked every CHECK_SECONDS.
extends Node

const NODE_NAME := "swell"
const GROUP := &"swell"
const META := &"swell_copy"
# The server's books read this (combatbook.py SWELL_MARK): keep the two alike.
const MARK := "#swell"
const AREA := "res://scene/bigfield.tscn"
# Where beside its monster, as the stress test (stresscrowd.gd).
const SPREAD_MIN := 20.0
const SPREAD_MAX := 56.0
const ARRIVAL_CLEAR := 400.0
const WALL_MASK := 1
const BUILD_MS := 3.0
const RESPAWN_FALLBACK := 30.0
# Nothing comes back within this of anybody (the respawner's own distance).
const PLAYER_CLEAR := 250.0
const CHECK_SECONDS := 1.0

const EnemyRespawnerScript := preload("res://src/world/enemyrespawner.gd")
const EnemySleeperScript := preload("res://src/world/enemysleeper.gd")
const Targets := preload("res://src/shared/targets.gd")

# SEAMS FOR THE SUITE: the land and size in place of the Lands autoload's,
# whether this game runs the area, and a respawn wait in place of each
# monster's own, when set.
var land_now: Callable = Callable()
var size_now: Callable = Callable()
var authority_now: Callable = Callable()
var wait_override: float = -1.0

var _area: Node = null
var _sources: Array = []         # the authored monsters: what to swell, and where
var _census_taken: bool = false
var _copies: Dictionary = {}     # "origin#swellN" -> {"id", "source", "n"}
var _back_at: Dictionary = {}    # "origin#swellN" -> when (ms) it may come back
var _busy: bool = false
var _timer: Timer = null


static func add_to(scene: Node) -> Node:
	var swell: Node = (load("res://src/world/swell.gd") as GDScript).new() as Node
	swell.name = NODE_NAME
	scene.add_child(swell)
	return swell


static func is_swell(node: Node) -> bool:
	"""A swell monster: built here, or a mirror of one (its origin says so)."""
	return node != null and (node.has_meta(META) or str(node.get_meta(&"net_origin", "")).contains(MARK))


func _ready() -> void:
	add_to_group(GROUP)
	_area = get_parent()
	if not applies():
		return
	_timer = Timer.new()
	_timer.wait_time = CHECK_SECONDS
	_timer.autostart = true
	_timer.timeout.connect(check)
	add_child(_timer)
	if not Lands.changed.is_connected(check):
		Lands.changed.connect(check)


func _exit_tree() -> void:
	if Lands.changed.is_connected(check):
		Lands.changed.disconnect(check)


func applies() -> bool:
	return _area != null and _area.scene_file_path == AREA


func land() -> int:
	return int(land_now.call()) if land_now.is_valid() else Lands.stirring()


func size() -> int:
	"""How many of each stirring monster: 1 (none added) up to 4."""
	var n: int = int(size_now.call()) if size_now.is_valid() else Lands.swell_size()
	return clampi(n, 1, 4)


func copy_count() -> int:
	var alive: int = 0
	for key in _copies:
		if _alive(_copies[key]):
			alive += 1
	return alive


func source_count() -> int:
	return _sources.size()


func check() -> void:
	"""Bring the swell to what the land and size say: adopt any standing
	(a game that has just taken the area over), let go of the ones too many
	once out of a fight, build the missing ones a few a frame."""
	if _busy or not applies() or not is_inside_tree() or not _has_authority():
		return
	_busy = true
	if not _census_taken:
		await _take_census()
		if not is_instance_valid(self) or not is_inside_tree():
			return
	_adopt()
	var stirring: int = land()
	var want: int = size() if stirring != 0 else 1
	# TOO MANY: the stir over, another land's, or the size come down.
	for key in _copies.keys():
		var entry: Dictionary = _copies[key]
		if not _alive(entry):
			_copies.erase(key)
			continue
		var source: Dictionary = _sources[int(entry["source"])] if int(entry["source"]) < _sources.size() else {}
		if int(source.get("element", 0)) == stirring and int(entry["n"]) < want:
			continue
		var node: Node = instance_from_id(int(entry["id"])) as Node
		if node != null and not bool(node.get("engaged")) and not bool(node.get("_dying")):
			node.queue_free()
			_copies.erase(key)
	# TOO FEW: one at each place, unless it was killed and its wait is not up.
	if want > 1:
		var spots: Array[Vector2] = _player_spots()
		var started: int = Time.get_ticks_usec()
		var now_ms: int = Time.get_ticks_msec()
		for i in _sources.size():
			var source: Dictionary = _sources[i]
			if int(source["element"]) != stirring:
				continue
			for n in range(1, want):
				var key: String = "%s%s%d" % [source["origin"], MARK, n]
				if _copies.has(key) or int(_back_at.get(key, 0)) > now_ms:
					continue
				_build(i, n, key, spots)
				if Time.get_ticks_usec() - started >= int(BUILD_MS * 1000.0):
					await get_tree().process_frame
					if not is_instance_valid(self) or not is_inside_tree() or not _has_authority():
						_busy = false
						return
					spots = _player_spots()
					started = Time.get_ticks_usec()
	_busy = false


func _take_census() -> void:
	"""The Big Field's authored monsters, once, as they stand before anything
	has died: what each swells into, and where. Waits for the navigation, which
	says what is floor."""
	await get_tree().process_frame
	await get_tree().process_frame
	var map: RID = (_area as Node2D).get_world_2d().navigation_map if _area is Node2D else RID()
	for i in 60:
		if not map.is_valid() or NavigationServer2D.map_get_iteration_id(map) > 0:
			break
		await get_tree().physics_frame
	if not is_instance_valid(self) or not is_inside_tree():
		return
	var arrivals: Array[Vector2] = []
	for marker in _area.find_children("arrivalmarker", "Marker2D", true, false):
		arrivals.append((marker as Node2D).global_position)
	var respawner: Node = _area.find_child("enemyrespawner", true, false)
	var root: Node = get_tree().current_scene
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Node2D
		if enemy == null or is_swell(enemy) or enemy.has_meta(&"stress_copy") or enemy.has_meta(&"run_extra") \
				or enemy.scene_file_path == "" or not _area.is_ancestor_of(enemy) or not (enemy.get_parent() is Node2D) \
				or not enemy.has_method("current_element"):
			continue
		var origin: String = str(enemy.get_meta(&"net_origin", ""))
		if origin == "" and root != null and root.is_ancestor_of(enemy):
			origin = str(root.get_path_to(enemy))
		var element: int = int(enemy.call("current_element"))
		var packed: PackedScene = load(enemy.scene_file_path) as PackedScene
		if origin == "" or packed == null or element < Element.Type.DARK or element > Element.Type.WATER:
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
			"origin": origin,
			"element": element,
			"map": map,
			"world": (_area as Node2D).get_world_2d() if _area is Node2D else null,
			"arrivals": arrivals,
		})
	_census_taken = true


func _adopt() -> void:
	"""Swell monsters standing that this game did not build - the area was
	taken over from a game that did - are this game's now: counted, and
	brought back when killed, like its own."""
	var by_origin: Dictionary = {}
	for i in _sources.size():
		by_origin[str(_sources[i]["origin"])] = i
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Node
		if enemy == null or not _area.is_ancestor_of(enemy) or enemy.is_queued_for_deletion():
			continue
		var key: String = str(enemy.get_meta(&"net_origin", ""))
		if not key.contains(MARK) or _copies.has(key):
			continue
		var parts: PackedStringArray = key.rsplit(MARK, true, 1)
		if parts.size() != 2 or not by_origin.has(parts[0]) or not parts[1].is_valid_int():
			continue
		enemy.set_meta(META, true)
		_track(enemy, key, int(by_origin[parts[0]]), int(parts[1]))


func _build(source: int, n: int, key: String, spots: Array[Vector2]) -> void:
	var entry: Dictionary = _sources[source]
	var parent: Node2D = entry["parent"] as Node2D
	if parent == null or not is_instance_valid(parent) or not parent.is_inside_tree():
		return
	var spot: Variant = _spot_near(entry)
	if spot == null:
		return
	# NEVER ON TOP OF ANYBODY: a place with a player close waits for the next
	# check (CHECK_SECONDS).
	for at in spots:
		if (at as Vector2).distance_to(spot) < PLAYER_CLEAR and _back_at.has(key):
			return
	var enemy := (entry["packed"] as PackedScene).instantiate() as Node2D
	if enemy == null:
		return
	var kept: Dictionary = entry["kept"]
	for property in kept:
		enemy.set(property, kept[property])
	enemy.set_meta(META, true)
	enemy.set_meta(&"net_origin", key)
	enemy.name = "swell_%s_%d" % [entry["name"], n]
	var far: bool = not spots.is_empty()
	for at in spots:
		if (at as Vector2).distance_to(spot) <= EnemySleeperScript.SLEEP_DISTANCE:
			far = false
			break
	if far:
		EnemySleeperScript.put_to_sleep(enemy)
	# Before add_child(): BaseEnemy._ready() reads its spot as home.
	enemy.position = parent.to_local(spot)
	parent.add_child(enemy)
	enemy.global_position = spot
	enemy.reset_physics_interpolation()
	if "spawn_position" in enemy:
		enemy.set("spawn_position", spot)
	_back_at.erase(key)
	_track(enemy, key, source, n)


func _track(enemy: Node, key: String, source: int, n: int) -> void:
	_copies[key] = {"id": enemy.get_instance_id(), "source": source, "n": n}
	if enemy.has_signal("died") and not enemy.died.is_connected(_on_died):
		enemy.died.connect(_on_died.bind(key), CONNECT_ONE_SHOT)


func _on_died(key: String) -> void:
	"""Killed: back after its monster's wait (check() builds it then), at a new
	spot beside it - if its land still stirs."""
	var entry: Dictionary = _copies.get(key, {})
	_copies.erase(key)
	var source: int = int(entry.get("source", -1))
	var wait: float = wait_override if wait_override >= 0.0 \
		else (float(_sources[source].get("respawn", RESPAWN_FALLBACK)) if source >= 0 and source < _sources.size()
			else RESPAWN_FALLBACK)
	_back_at[key] = Time.get_ticks_msec() + int(wait * 1000.0)


func _alive(entry: Dictionary) -> bool:
	var node: Object = instance_from_id(int(entry.get("id", 0)))
	return node != null and is_instance_valid(node) and not (node as Node).is_queued_for_deletion() \
		and not bool(node.get("_death_resolved"))


func _has_authority() -> bool:
	"""This game runs the area's monsters: the leader, or alone (no
	MonsterSync - a test, or no link). Asked as the respawner asks."""
	if authority_now.is_valid():
		return bool(authority_now.call())
	if not is_inside_tree():
		return false
	for sync in get_tree().get_nodes_in_group(&"monstersync"):
		var holder: Node = sync.get_parent()
		if holder != null and holder.is_ancestor_of(self) and sync.has_method("has_authority"):
			return sync.call("has_authority")
	return true


func _player_spots() -> Array[Vector2]:
	var spots: Array[Vector2] = []
	if not is_inside_tree():
		return spots
	for body in Targets.all(get_tree()):
		spots.append((body as Node2D).global_position)
	return spots


func _spot_near(entry: Dictionary) -> Variant:
	"""A spot on the floor beside its monster, in sight of it, clear of where
	players arrive; null when eight tries find none (stresscrowd.gd's rule)."""
	var home: Vector2 = entry["home"]
	var map: RID = entry["map"]
	for attempt in 8:
		var spot: Vector2 = home + Vector2.from_angle(randf() * TAU) * randf_range(SPREAD_MIN, SPREAD_MAX)
		if map.is_valid():
			var floor_at: Vector2 = NavigationServer2D.map_get_closest_point(map, spot)
			if floor_at.distance_to(spot) > 1.5:
				continue
		var world: World2D = entry.get("world") as World2D
		if world != null:
			var query := PhysicsRayQueryParameters2D.create(home, spot, WALL_MASK)
			if not world.direct_space_state.intersect_ray(query).is_empty():
				continue
		var near_arrival: bool = false
		for arrival in entry["arrivals"]:
			if (arrival as Vector2).distance_to(spot) < ARRIVAL_CLEAR:
				near_arrival = true
				break
		if not near_arrival:
			return spot
	return null
