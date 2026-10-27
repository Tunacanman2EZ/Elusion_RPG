# buildendless.gd - writes scene/endless.tscn, the endless run's map (0.93.0).
#
# Run once from a scene (build()); the scene it writes is then an ordinary
# area the owner can open and decorate in the editor. Running it again
# writes the map afresh and loses anything changed there by hand.
#
# ALL OF IT IS THE GAME'S OWN ART, put together: the floor is the Big Field's
# underground plateau (art/tiles/underground.png, its tileset saved beside
# the scene as underground.tres, once), the walls, door, candelabras and bones are
# the crypt pieces in scene/crypt/ the Big Field is built from, and the way
# out is the ladder.
#
#   +--------------------------------------------------+
#   |  candelabras along the back wall                 |
#   |                                                  |
#   |                 THE ARENA                        |
#   |            (the swarm's floor)                   |
#   |                     [door]                       |
#   |                    |      |                      |
#   |                    | corr-|                      |
#   |                    | idor |                      |
#   |                    | ladder                      |
#   +--------------------------------------------------+
#
# The corridor is walled into the arena's south side: its door opens on the
# arena, and the ladder at its foot goes up to town.
extends Node

const OUT := "res://scene/endless.tscn"
const TILESET_OUT := "res://scene/world/underground.tres"
const TILE := 16
# The plateau, in tiles: 96 x 88 (1,536 x 1,408 px).
const COLS := 96
const ROWS := 88
const CORRIDOR_LEFT := 698.0
const CORRIDOR_RIGHT := 838.0
const DOOR_Y := 1012.0
const BACK := 1376.0
const AMBIENCE := Color(0.5, 0.5, 0.62)
const ARRIVAL := Vector2(768, 1290)

var _root: Node2D = null


func build() -> int:
	# THE BIG FIELD'S OWN TILESET, saved once beside the scene (it is embedded
	# in bigfield.tscn, and no script loads an area by path behind the
	# registry's back - see AreaRegistry). Same atlas, same collision.
	var tiles: TileSet = load(TILESET_OUT) as TileSet
	if tiles == null:
		return ERR_FILE_NOT_FOUND

	_root = Node2D.new()
	_root.name = "endless"
	_root.set_script(load("res://src/world/field.gd"))
	_root.set("bullet_zone", true)
	_root.set("tells_story", false)

	var ground := TileMapLayer.new()
	ground.name = "ground"
	ground.z_index = -10
	ground.tile_set = tiles
	_own(ground, _root)
	_paint(ground)
	var nav := NavigationRegion2D.new()
	nav.name = "navigationregion2d"
	nav.navigation_polygon = _nav_polygon()
	_own(nav, ground)
	# The crypt's own dark, a little lighter: three thousand slimes have to be
	# seen in it.
	var dark: Node = _place("res://scene/crypt/cryptambience.tscn", ground, Vector2.ZERO, "cryptambience")
	dark.set("color", AMBIENCE)

	var world := TileMapLayer.new()
	world.name = "ysortworld"
	world.y_sort_enabled = true
	_own(world, _root)
	var props := _container("props", world)
	var interactables := _container("interactables", world)
	_container("enemies", world)
	_container("groundeffects", world, "groundeffects")
	_container("projectiles", world, "projectiles")
	_container("lootbags", world, "lootbags")
	_container("pets", world, "pets_container")
	# Where a player stands when no marker is named - the Big Field's rule,
	# and where the suite starts its walk of the map.
	var standing: Node2D = _container("player", world)
	standing.position = ARRIVAL
	var above := Node2D.new()
	above.name = "aboveworld"
	_own(above, world)

	_walls(props)
	_decorate(props)
	var door: Node = _place("res://scene/crypt/door.tscn", props, Vector2(768, DOOR_Y), "rundoor")
	door.set("starts_open", false)
	# The ladder up is a picture; the boss room gives it ladder.gd the same way.
	var ladder: Node = _place("res://scene/ladderup.tscn", interactables, Vector2(768, 1348), "ladderup")
	ladder.set_script(load("res://src/world/ladder.gd"))
	ladder.set("collision_layer", 16)
	ladder.set("collision_mask", 4)
	ladder.set("destination_scene_path", "res://scene/elusion.tscn")
	ladder.set("target_spawn_id", "")
	# Wired in the scene, as every door is (the suite's "every door in every
	# area hears a player step in and out").
	ladder.connect("body_entered", Callable(ladder, "_on_body_entered"), CONNECT_PERSIST)
	ladder.connect("body_exited", Callable(ladder, "_on_body_exited"), CONNECT_PERSIST)
	var arrival := Node2D.new()
	arrival.name = "endlessarrival"
	arrival.set_script(load("res://src/world/fieldportal.gd"))
	arrival.set("portal_id", "endless_entrance")
	arrival.position = ARRIVAL
	_own(arrival, interactables)

	_place("res://scene/ui/characterhud.tscn", _root, Vector2.ZERO, "hudcontrol")
	var labels := Node2D.new()
	labels.name = "floatinglabels"
	labels.z_index = 90
	_own(labels, _root)
	labels.add_to_group(&"floatinglabels", true)

	var run := Node.new()
	run.name = "endlessrun"
	run.set_script(load("res://src/world/endless/endlessrun.gd"))
	run.set("arena_rect", Rect2(24, 24, COLS * TILE - 48, BACK - 24))
	# The corridor as the swarm keeps out of it: from the wall's top (the
	# crypt walls stand 28 px over their foot) to the arena's foot.
	run.set("corridor_rect", Rect2(CORRIDOR_LEFT - 8, DOOR_Y - 32, CORRIDOR_RIGHT - CORRIDOR_LEFT + 16, BACK - DOOR_Y + 32))
	# Through the door and out of the corridor: the run starts.
	run.set("start_rect", Rect2(729, DOOR_Y - 104, 78, 68))
	run.set("wake_spot", Vector2(768, 1250))
	_own(run, _root)

	var packed := PackedScene.new()
	var packing: int = packed.pack(_root)
	if packing != OK:
		return packing
	var result: int = ResourceSaver.save(packed, OUT)
	_root.free()
	return result


# =============================================================================
# THE FLOOR
# =============================================================================

func _paint(ground: TileMapLayer) -> void:
	"""The plateau: its rim along the top and sides, the brick face along the
	foot, and the plain floor between in its twelve variants."""
	var rng := RandomNumberGenerator.new()
	rng.seed = 94
	for y in ROWS:
		for x in COLS:
			var col: int = 0 if x == 0 else (5 if x == COLS - 1 else rng.randi_range(1, 4))
			var row: int
			if y == 0:
				row = 0
			elif y == ROWS - 2:
				row = 4
			elif y == ROWS - 1:
				row = 5
			else:
				row = rng.randi_range(1, 3)
			ground.set_cell(Vector2i(x, y), 1, Vector2i(col, row))


func _nav_polygon() -> NavigationPolygon:
	"""The arena's floor, the corridor cut out: three convex pieces sharing
	their edges."""
	var left: float = 24.0
	var right: float = COLS * TILE - 24.0
	var top: float = 24.0
	var cut: float = DOOR_Y - 30.0
	var bottom: float = BACK - 8.0
	var a: float = CORRIDOR_LEFT - 10.0
	var b: float = CORRIDOR_RIGHT + 10.0
	var poly := NavigationPolygon.new()
	poly.vertices = PackedVector2Array([
		Vector2(left, top), Vector2(right, top), Vector2(right, cut), Vector2(b, cut),
		Vector2(a, cut), Vector2(left, cut), Vector2(left, bottom), Vector2(a, bottom),
		Vector2(b, bottom), Vector2(right, bottom)])
	poly.add_polygon(PackedInt32Array([0, 1, 2, 3, 4, 5]))
	poly.add_polygon(PackedInt32Array([5, 4, 7, 6]))
	poly.add_polygon(PackedInt32Array([3, 2, 9, 8]))
	return poly


# =============================================================================
# THE WALLS AND WHAT STANDS IN THE ROOM
# =============================================================================

func _walls(props: Node) -> void:
	"""The corridor: a wall each side of the door, a pillar capping each end,
	and its two long sides down to the brick at the arena's foot."""
	_place("res://scene/crypt/wallrun1.tscn", props, Vector2(716, DOOR_Y))
	_place("res://scene/crypt/wallrun1.tscn", props, Vector2(820, DOOR_Y))
	_place("res://scene/crypt/pillar.tscn", props, Vector2(CORRIDOR_LEFT - 2, DOOR_Y + 2))
	_place("res://scene/crypt/pillar.tscn", props, Vector2(CORRIDOR_RIGHT + 2, DOOR_Y + 2))
	for side in [CORRIDOR_LEFT, CORRIDOR_RIGHT]:
		var y: float = DOOR_Y + 58.0
		while y <= BACK + 10.0:
			_place("res://scene/crypt/wallsidetall.tscn", props, Vector2(side, y))
			y += 58.0


func _decorate(props: Node) -> void:
	"""Candelabras along the back wall and down the corridor, and the crypt's
	bones, cages and graves in the arena's corners - all at its edges, where
	the swarm's crowd does not walk through them."""
	var x: float = 120.0
	while x < COLS * TILE - 100.0:
		_place("res://scene/crypt/candelabra.tscn", props, Vector2(x, 44))
		x += 216.0
	for y in [160.0, 520.0, 880.0, 1240.0]:
		_place("res://scene/crypt/lantern.tscn", props, Vector2(40, y))
		_place("res://scene/crypt/lantern.tscn", props, Vector2(COLS * TILE - 40, y))
	_place("res://scene/crypt/candelabra.tscn", props, Vector2(722, 1080))
	_place("res://scene/crypt/candelabra.tscn", props, Vector2(814, 1080))
	_place("res://scene/crypt/candelabra.tscn", props, Vector2(722, 1220))
	_place("res://scene/crypt/candelabra.tscn", props, Vector2(814, 1220))
	_place("res://scene/crypt/skullpile.tscn", props, Vector2(70, 80))
	_place("res://scene/crypt/cageoccupied.tscn", props, Vector2(COLS * TILE - 70, 86))
	_place("res://scene/crypt/gravestone.tscn", props, Vector2(60, 1330))
	_place("res://scene/crypt/gravestone.tscn", props, Vector2(92, 1336))
	_place("res://scene/crypt/skullpole.tscn", props, Vector2(COLS * TILE - 64, 1330))
	_place("res://scene/crypt/cage.tscn", props, Vector2(COLS * TILE - 110, 1320))
	_place("res://scene/crypt/skullcandles.tscn", props, Vector2(640, 1340))
	_place("res://scene/crypt/skullcandles.tscn", props, Vector2(896, 1340))
	_place("res://scene/crypt/bones.tscn", props, Vector2(300, 1300))
	_place("res://scene/crypt/ribcage.tscn", props, Vector2(1220, 300))
	_place("res://scene/crypt/skullbones.tscn", props, Vector2(400, 200))


# =============================================================================
# PUTTING A NODE IN THE SCENE
# =============================================================================

func _own(node: Node, parent: Node) -> void:
	parent.add_child(node)
	node.owner = _root


func _container(node_name: String, parent: Node, group: String = "") -> Node2D:
	var holder := Node2D.new()
	holder.name = node_name
	holder.y_sort_enabled = true
	_own(holder, parent)
	if group != "":
		holder.add_to_group(StringName(group), true)
	return holder


func _place(path: String, parent: Node, at: Vector2, node_name: String = "") -> Node:
	var piece: Node = (load(path) as PackedScene).instantiate()
	if node_name != "":
		piece.name = node_name
	if piece is Node2D:
		(piece as Node2D).position = at
	parent.add_child(piece, node_name == "")
	piece.owner = _root
	return piece
