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

const StressCrowd := preload("res://src/world/stresscrowd.gd")
const FOLDER := "res://scene/enemy/"
const GROUP := &"gm_spawned"
# At most this many a press.
const MOST := 200
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
	var packed: PackedScene = load(path) as PackedScene
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
	var made: int = 0
	for n in clampi(count, 0, MOST):
		var spot: Variant = _spot(around, map, on_map, run)
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


static func _spot(around: Vector2, map: RID, on_map: bool, run: Node) -> Variant:
	"""A spot NEAR to FAR from `around`, on the navigation where the area has
	one and on the Endless's floor in the Endless; null after eight tries."""
	for attempt in 8:
		var spot: Vector2 = around + Vector2.from_angle(randf() * TAU) * randf_range(NEAR, FAR)
		if on_map:
			var floor_at: Vector2 = NavigationServer2D.map_get_closest_point(map, spot)
			if floor_at.distance_to(spot) > 1.5:
				continue
		if run != null and run.has_method(&"on_floor") and not bool(run.call(&"on_floor", spot)):
			continue
		return spot
	return null


static func alive(tree: SceneTree) -> int:
	return tree.get_nodes_in_group(GROUP).size() if tree != null else 0


static func clear(tree: SceneTree) -> int:
	"""Every spawned test copy gone; how many."""
	if tree == null:
		return 0
	var gone: int = 0
	for monster in tree.get_nodes_in_group(GROUP):
		if not monster.is_queued_for_deletion():
			monster.queue_free()
			gone += 1
	return gone
