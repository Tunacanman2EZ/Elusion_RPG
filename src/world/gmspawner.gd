extends RefCounted
# gmspawner.gd - the GM panel's Spawn (0.151.0): any monster, as many as
# asked, round the owner, in any area - the Endless too, where the stress
# test does nothing.
#
# The owner: "stress test douse not work on minigame ... i could test certain
# mobs like archers only or slimes or bosses or elites and i can measure out
# better".
#
# TEST COPIES, WORTH NOTHING. Each carries the stress test's mark
# (stresscrowd.gd META), so it is this game's alone: BaseEnemy.get_enemy_id()
# is "" for it (no kill report - no XP, no bag, nothing for the kill ceilings
# or the Endless's chest), monstersync.gd never shares it and the respawner
# never counts it. Gone at Clear, or with the area. The panel is the owner's
# alone, and so is this.
#
# ON THE FLOOR IN TOWN TOO (0.173.1, the owner: "if i spawn monsters in town
# they go outside the map"). The town has no navigation, so a spot was any
# point of the ring round you - near its edge, 32 of 40 off the ground and
# some on the water. Where an area has no navigation but has a "ground"
# TileMapLayer, a spot must be on a ground tile, not on a "water" one, and
# not inside a wall (on_floor()).

const StressCrowd := preload("res://src/world/stresscrowd.gd")
const GroundChunks := preload("res://src/world/groundchunks.gd")
const FOLDER := "res://scene/enemy/"
const GROUP := &"gm_spawned"
# At most this many a press.
const MOST := 200
# Places tried for each, before that one is given up.
const TRIES := 16
# What a spot must not be inside: the world's walls (layer 1).
const WALLS := 1
static var _held: Dictionary = {}
# Where round the owner, in px: not on top of them, on their screen.
const NEAR := 120.0
const FAR := 320.0
# After the owner from where they stand, not left to wander home.
const NOTICE := 900.0
# A scene's name is an element and a kind: the kinds, in the picker's order.
const KINDS := [
	["slimelarge", "large slime"], ["slime", "slime"], ["bushsniper", "archer"],
	["bushmage", "bush mage"], ["firesprite", "fire sprite"], ["sprite", "sprite"],
	["skeletonelite", "skeleton elite"], ["skeletonsoldier", "skeleton soldier"],
	["skeleton", "skeleton"], ["boss", "boss"],
]
const ELEMENTS := ["dark", "earth", "electric", "fire", "ice", "light", "poison", "water", "wind"]

static var _catalogue: Array = []


static func catalogue() -> Array:
	"""Every monster scene in FOLDER as {"label", "path", "kind"}, by kind
	(KINDS' order) and then label. ResourceLoader.list_directory(), so an
	exported build lists them too."""
	if not _catalogue.is_empty():
		return _catalogue
	var out: Array = []
	for entry in ResourceLoader.list_directory(FOLDER):
		var file: String = String(entry)
		if not file.ends_with(".tscn"):
			continue
		var stem: String = file.get_basename()
		var named: Array = label_of(stem)
		out.append({"label": named[0], "path": FOLDER + file, "kind": int(named[1])})
	out.sort_custom(func(a, b): return [int(a["kind"]), str(a["label"])] < [int(b["kind"]), str(b["label"])])
	_catalogue = out
	return _catalogue


static func label_of(stem: String) -> Array:
	"""[a name a person reads, its kind's place in KINDS] for a scene's file
	name: "windbushsniper" is ["Wind archer", 2]. The first boss's scene is
	"bossenemy", the dark land's."""
	if stem == "bossenemy":
		return ["Dark boss", KINDS.size() - 1]
	var element: String = ""
	var rest: String = stem
	for word in ELEMENTS:
		if stem.begins_with(word) and stem.length() > word.length():
			element = word
			rest = stem.substr(word.length())
			break
	for k in KINDS.size():
		if rest == str(KINDS[k][0]):
			var kind: String = str(KINDS[k][1])
			return [(element.capitalize() + " " + kind) if element != "" else kind.left(1).to_upper() + kind.substr(1), k]
	return [stem.capitalize(), KINDS.size()]


static func spawn(tree: SceneTree, path: String, count: int, around: Vector2) -> int:
	"""`count` (at most MOST) of the monster at `path`, round `around` on the
	area's floor, each a test copy; how many came."""
	if tree == null or tree.current_scene == null:
		return 0
	var packed: PackedScene = scene_for(path)
	if packed == null:
		return 0
	var scene: Node = tree.current_scene
	var container: Node = scene.get_node_or_null(^"ysortworld/enemies")
	if container == null:
		container = scene.get_node_or_null(^"ysortworld")
	if container == null:
		container = scene
	var run: Node = scene.get_node_or_null(^"endlessrun")
	var map: RID = tree.root.world_2d.navigation_map
	var on_map: bool = map.is_valid() and not NavigationServer2D.map_get_regions(map).is_empty()
	var tiles: Array = [] if on_map else floor_layers(scene)
	var space: PhysicsDirectSpaceState2D = tree.root.world_2d.direct_space_state
	var made: int = 0
	for n in clampi(count, 0, MOST):
		var spot: Variant = _spot(around, map, on_map, run, tiles, space)
		if spot == null:
			continue
		var monster := packed.instantiate() as Node2D
		if monster == null:
			continue
		monster.set_meta(StressCrowd.META, true)
		if "notice_range" in monster:
			monster.set("notice_range", NOTICE)
		if "leash_range" in monster:
			monster.set("leash_range", NOTICE)
		monster.name = "gm_%s_%d" % [path.get_file().get_basename(), made]
		monster.add_to_group(GROUP)
		# Before add_child(): BaseEnemy._ready() reads its spot as home.
		monster.position = spot
		container.add_child(monster)
		monster.global_position = spot
		monster.reset_physics_interpolation()
		if "spawn_position" in monster:
			monster.set("spawn_position", spot)
		made += 1
	return made


static func scene_for(path: String) -> PackedScene:
	"""The monster's scene, loaded once and held (0.154.0). A monster made from
	a scene does not keep the scene: with nothing else holding it Godot's
	cache lets it go, and the next load() read it from disk again - 3.8 ms
	for an archer in the container, measured, every time one was made (Every
	effect's deaths made one a frame). A minigame's warmer holds its own; the
	Testing Ground's are held here for the session."""
	var packed: PackedScene = _held.get(path) as PackedScene
	if packed == null:
		packed = load(path) as PackedScene
		if packed != null:
			_held[path] = packed
	return packed


static func _spot(around: Vector2, map: RID, on_map: bool, run: Node,
		tiles: Array = [], space: PhysicsDirectSpaceState2D = null) -> Variant:
	"""A spot NEAR to FAR from `around`, on the navigation where the area has
	one, on the Endless's floor in the Endless, and on the ground (not water,
	not a wall) where there is a ground layer and no navigation; null after
	TRIES tries."""
	for attempt in TRIES:
		var spot: Vector2 = around + Vector2.from_angle(randf() * TAU) * randf_range(NEAR, FAR)
		if on_map:
			var floor_at: Vector2 = NavigationServer2D.map_get_closest_point(map, spot)
			if floor_at.distance_to(spot) > 1.5:
				continue
		if run != null and run.has_method(&"on_floor") and not bool(run.call(&"on_floor", spot)):
			continue
		if not tiles.is_empty() and not on_floor(spot, tiles, space):
			continue
		return spot
	return null


static func floor_layers(scene: Node) -> Array:
	"""[ground, water] - an area's "ground" TileMapLayer and its "water" one
	(or null) - or [] when it has no ground layer."""
	var ground: TileMapLayer = scene.get_node_or_null(^"ground") as TileMapLayer
	if ground == null:
		return []
	return [ground, scene.get_node_or_null(^"water") as TileMapLayer]


static func on_floor(spot: Vector2, tiles: Array, space: PhysicsDirectSpaceState2D) -> bool:
	"""On a ground tile, not a water one, and not inside a wall. The tiles
	asked of groundchunks.gd: the Big Field's floor is kept once, off the layer."""
	var ground: TileMapLayer = tiles[0]
	if GroundChunks.source_at(ground, ground.local_to_map(ground.to_local(spot))) == -1:
		return false
	var water: TileMapLayer = tiles[1] if tiles.size() > 1 else null
	if water != null and GroundChunks.source_at(water, water.local_to_map(water.to_local(spot))) != -1:
		return false
	if space != null:
		var probe := PhysicsPointQueryParameters2D.new()
		probe.position = spot
		probe.collision_mask = WALLS
		if not space.intersect_point(probe, 1).is_empty():
			return false
	return true


static func alive(tree: SceneTree) -> int:
	return tree.get_nodes_in_group(GROUP).size() if tree != null else 0


# CLEARED IN PARTS (0.174.1). Freeing 600 skeletons in one frame - 12,664
# nodes - was the owner's worst spike, "scripts 38.1 ms, -12,664 nodes" (84 ms
# in the container). Now Clear takes every copy out of the game at once - out
# of its group and "enemies" (nothing counts, aims at or wakes it), gated (it
# neither moves nor attacks), hidden - and frees CLEAR_EACH_FRAME a frame
# after: 600 are gone in 15 frames, about 2 ms each.
const CLEAR_EACH_FRAME := 40
static var _clearing: Array[int] = []
static var _clearing_waits: bool = false


static func clear(tree: SceneTree) -> int:
	"""Every spawned test copy out of the game now, freed over the next
	frames (CLEARED IN PARTS); how many."""
	if tree == null:
		return 0
	var gone: int = 0
	for monster in tree.get_nodes_in_group(GROUP):
		if monster.is_queued_for_deletion():
			continue
		monster.remove_from_group(GROUP)
		monster.remove_from_group(&"enemies")
		if "gated" in monster:
			monster.set("gated", true)
		if monster is CanvasItem:
			(monster as CanvasItem).visible = false
		_clearing.append(monster.get_instance_id())
		gone += 1
	if not _clearing.is_empty() and not _clearing_waits:
		_clearing_waits = true
		tree.process_frame.connect(_clear_some.bind(tree), CONNECT_ONE_SHOT)
	return gone


static func clearing() -> int:
	"""Copies cleared and not freed yet."""
	return _clearing.size()


static func _clear_some(tree: SceneTree) -> void:
	_clearing_waits = false
	var freed: int = 0
	while freed < CLEAR_EACH_FRAME and not _clearing.is_empty():
		var monster: Node = instance_from_id(_clearing.pop_back()) as Node
		if monster != null and not monster.is_queued_for_deletion():
			monster.queue_free()
			freed += 1
	if not _clearing.is_empty() and is_instance_valid(tree):
		_clearing_waits = true
		tree.process_frame.connect(_clear_some.bind(tree), CONNECT_ONE_SHOT)
