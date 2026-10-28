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
#   +==================================================+
#   |  candelabras along the back wall                 |
#   |                                                  |
#   |                 THE ARENA                        |
#   |            (the swarm's floor)                   |
#   |                     [door]                       |
#   |                    |      |                      |
#   |                    | corr-|                      |
#   |                    | idor |                      |
#   |                    | ladder                      |
#   +==================================================+
#
# The corridor is walled into the arena's south side: its door opens on the
# arena, and the ladder at its foot goes up to town.
#
# WALLED ALL ROUND (0.93.1; the owner: "we need walls around the whole map
# now"): the crypt's back wall along the top, its side walls down both sides
# and its front wall along the foot, with its four corner pieces, laid the
# way the Big Field's crypt chambers lay them (_outer_walls()). The arena's
# floor for the swarm (arena_rect) stops at their faces.
extends Node

const OUT := "res://scene/endless.tscn"
const TILESET_OUT := "res://scene/world/underground.tres"
const TILE := 16
# The plateau, in tiles: 96 x 88 (1,536 x 1,408 px).
const COLS := 96
const ROWS := 88
# The corridor's side walls' centre lines, under its two pillars, and the
# door's foot: six tall side pieces (58) down to the front wall's top.
const CORRIDOR_LEFT := 694.5
const CORRIDOR_RIGHT := 841.5
const DOOR_Y := 1030.0
const AMBIENCE := Color(0.5, 0.5, 0.62)
const ARRIVAL := Vector2(768, 1290)
# The outer walls (0.93.2), by their feet: the back wall's along the top (its
# top at the map's edge), the front wall's along the foot, and the side walls'
# centre lines (each 9 wide, flush with the map's sides). Chosen so every run
# is laid end to end with nothing over anything: the sides are 22 tall pieces
# and one short (58 x 22 + 36 = 1,312), the corridor's six tall.
const WALL_BACK := 28.0
const WALL_FRONT := 1406.0
const SIDE_LEFT := 4.5
const SIDE_RIGHT := 1531.5
# The arena's foot: the front wall's face.
const BACK := WALL_FRONT - 28.0
# THE WALLS ALONG, AS WIDTHS, MIRRORED (the owner: "please make symmetrical no
# overlapping"): 101 the four-piece run, 51 the two, 26 the one, 17 a pillar.
# Each half is three runs, a pillar, three runs, a pillar and a short run;
# the back wall's middle is one-two-one (1,485 between its corners - the
# back right corner is a pixel narrower than the left, as drawn), the
# front's two-two (1,484).
const WALL_HALF := [101, 101, 101, 17, 101, 101, 101, 17, 51]
const BACK_MIDDLE := [26, 51, 26]
const FRONT_MIDDLE := [51, 51]
const WALL_PIECES := {101: "res://scene/crypt/wallrun4.tscn", 51: "res://scene/crypt/wallrun2.tscn",
	26: "res://scene/crypt/wallrun1.tscn", 17: "res://scene/crypt/pillar.tscn"}
# How far down the swarm keeps from the back wall's foot: it draws under
# everything standing, so one pressed to the wall would be half hidden by it.
# Still within touching reach of a player standing against the wall.
const SWARM_BACK_GAP := 6.0

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
	_outer_walls(props)
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
	var swarm_top: float = WALL_BACK + SWARM_BACK_GAP
	run.set("arena_rect", Rect2(SIDE_LEFT + 4.5, swarm_top, (SIDE_RIGHT - 4.5) - (SIDE_LEFT + 4.5), BACK - swarm_top))
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
	"""The plain floor in its twelve variants, edge to edge: the walls are
	the room's edges now (0.93.2), not the plateau's rim. The last row is left
	bare - the front wall stands over it, and below the wall is the dark."""
	var rng := RandomNumberGenerator.new()
	rng.seed = 94
	for y in ROWS - 1:
		for x in COLS:
			ground.set_cell(Vector2i(x, y), 1, Vector2i(rng.randi_range(1, 4), rng.randi_range(1, 3)))


func _nav_polygon() -> NavigationPolygon:
	"""The arena's floor, the corridor cut out: three convex pieces sharing
	their edges."""
	var left: float = SIDE_LEFT + 4.5
	var right: float = SIDE_RIGHT - 4.5
	var top: float = WALL_BACK + 2.0
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
	# A pillar caps each side, end to end with the short run beside it.
	_place("res://scene/crypt/pillar.tscn", props, Vector2(CORRIDOR_LEFT, DOOR_Y))
	_place("res://scene/crypt/pillar.tscn", props, Vector2(CORRIDOR_RIGHT, DOOR_Y))
	# Down to the front wall's top, closed: they stopped 18 px short of the
	# floor's foot, a gap a player could walk out of the corridor through,
	# round the door (0.93.1).
	for side in [CORRIDOR_LEFT, CORRIDOR_RIGHT]:
		_wall_side(props, side, DOOR_Y, WALL_FRONT - 28.0)


func _outer_walls(props: Node) -> void:
	"""The whole map walled in, as a crypt chamber is (bigfield.tscn's
	walls_chambers): a back corner each side 8 px below the back wall's foot,
	the back wall between them, the side walls down from the corners, the
	front corners whose legs meet the side walls, and the front wall between
	them - every piece end to end, the left half the right's mirror."""
	var back_corner_y: float = WALL_BACK + 8.0
	# Each corner's outer edge on the side wall's (13 and 12.5 from its middle).
	_place("res://scene/crypt/wallcornerbackleft.tscn", props, Vector2(SIDE_LEFT + 8.5, back_corner_y))
	_place("res://scene/crypt/wallcornerbackright.tscn", props, Vector2(SIDE_RIGHT - 8.0, back_corner_y))
	_place("res://scene/crypt/wallcornerfrontleft.tscn", props, Vector2(SIDE_LEFT + 8.5, WALL_FRONT))
	_place("res://scene/crypt/wallcornerfrontright.tscn", props, Vector2(SIDE_RIGHT - 8.5, WALL_FRONT))
	_wall_run(props, SIDE_LEFT + 21.5, SIDE_RIGHT - 20.5, WALL_BACK, wall_widths(BACK_MIDDLE))
	_wall_run(props, SIDE_LEFT + 21.5, SIDE_RIGHT - 21.5, WALL_FRONT, wall_widths(FRONT_MIDDLE))
	# A front corner's leg stands 30 px, from 28 over its foot to 58.
	for side in [SIDE_LEFT, SIDE_RIGHT]:
		_wall_side(props, side, back_corner_y, WALL_FRONT - 58.0)


static func wall_widths(middle: Array) -> Array:
	"""A wall's pieces left to right: the half, the middle, the half again
	backwards - the same either way you read it."""
	var widths: Array = WALL_HALF.duplicate()
	widths.append_array(middle)
	var back_half: Array = WALL_HALF.duplicate()
	back_half.reverse()
	widths.append_array(back_half)
	return widths


func _wall_run(props: Node, from_x: float, to_x: float, foot_y: float, widths: Array) -> void:
	"""The pieces in `widths`, end to end from from_x. They must come out at
	to_x exactly - a piece laid over its neighbour is what this replaced."""
	var x: float = from_x
	for width in widths:
		_place(WALL_PIECES[int(width)], props, Vector2(x + float(width) / 2.0, foot_y))
		x += float(width)
	if absf(x - to_x) > 0.01:
		push_error("buildendless: the wall at y %s ends at %s, not %s" % [foot_y, x, to_x])


func _wall_side(props: Node, x: float, from_y: float, to_y: float) -> void:
	"""A side wall down from_y to to_y (the feet of what it joins): the tall
	piece (58) while it fits, then one short one (36 or 35) to end flush - or
	an error, rather than one laid over another."""
	var y: float = from_y
	while to_y - y >= 58.0 - 0.01:
		y += 58.0
		_place("res://scene/crypt/wallsidetall.tscn", props, Vector2(x, y))
	var left: float = to_y - y
	if absf(left - 36.0) < 0.01:
		_place("res://scene/crypt/wallsidea.tscn", props, Vector2(x, to_y))
	elif absf(left - 35.0) < 0.01:
		_place("res://scene/crypt/wallsideb.tscn", props, Vector2(x, to_y))
	elif left > 0.01:
		push_error("buildendless: the side wall at x %s is %s short of %s" % [x, left, to_y])


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
