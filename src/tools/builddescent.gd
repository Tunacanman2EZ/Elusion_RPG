# builddescent.gd - writes scene/descent.tscn, the Descent's room (0.112.0).
#
# Run once from a scene (build()), as buildendless.gd is; running it again
# writes the room afresh and loses anything changed there by hand.
#
# ONE ROOM THE SCREEN'S SIZE, all of it the game's own art: the underground
# floor (scene/world/underground.tres), the crypt's walls laid end to end from
# their pieces - nothing over anything, the way buildendless.gd lays them -
# two doors in the back wall and one in the front (descentdoor.gd, from the
# crypt door's art), candelabras along the back. The run (descentrun.gd)
# dresses it anew each room; the walls never change.
#
#   +====[door]=========[door]====+
#   |  candelabras                |
#   |                             |
#   |          THE ROOM           |
#   |                             |
#   +===========[door]============+   <- where you come in (shut)
#
# Its numbers are the mock-up's (zz/rlmock.gd): side walls at SIDE_LEFT and
# SIDE_RIGHT (615 apart), the back wall's foot at WALL_BACK, the front's at
# WALL_FRONT - chosen so every run of pieces comes out exact.
extends Node

const OUT := "res://scene/descent.tscn"
const TILESET := "res://scene/world/underground.tres"
const TILE := 16
const SIDE_LEFT := 12.5
const SIDE_RIGHT := 627.5
const WALL_BACK := 84.0
const WALL_FRONT := 360.0
const AMBIENCE := Color(0.5, 0.5, 0.62)
const ENTRY := Vector2(320, 312)
# The walls as widths, left to right; a minus is a door's gap (78), named.
const BACK := [101, 17, 26, "doorleft", 26, 17, 26, 17, 17, 26, "doorright", 26, 17, 101]
const FRONT := [101, 51, 26, 26, 17, 26, "doorfront", 26, 17, 26, 26, 51, 101]
const GAP := 78.0
const PIECES := {101: "res://scene/crypt/wallrun4.tscn", 51: "res://scene/crypt/wallrun2.tscn",
	26: "res://scene/crypt/wallrun1.tscn", 17: "res://scene/crypt/pillar.tscn"}

var _root: Node2D = null


func build() -> int:
	var tiles: TileSet = load(TILESET) as TileSet
	if tiles == null:
		return ERR_FILE_NOT_FOUND
	_root = Node2D.new()
	_root.name = "descent"
	_root.set_script(load("res://src/world/field.gd"))
	_root.set("bullet_zone", true)
	_root.set("tells_story", false)

	var ground := TileMapLayer.new()
	ground.name = "ground"
	ground.z_index = -10
	ground.tile_set = tiles
	_own(ground, _root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 112
	for y in range(4, int(WALL_FRONT / TILE) + 1):
		for x in range(0, 40):
			ground.set_cell(Vector2i(x, y), 1, Vector2i(rng.randi_range(1, 4), rng.randi_range(1, 3)))
	var nav := NavigationRegion2D.new()
	nav.name = "navigationregion2d"
	nav.navigation_polygon = _nav_polygon()
	_own(nav, ground)
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
	var standing: Node2D = _container("player", world)
	standing.position = ENTRY
	var above := Node2D.new()
	above.name = "aboveworld"
	_own(above, world)

	_walls(props)
	for x in [70.0, 320.0, 570.0]:
		_place("res://scene/crypt/candelabra.tscn", props, Vector2(x, WALL_BACK + 14.0))
	var arrival := Node2D.new()
	arrival.name = "descentarrival"
	arrival.set_script(load("res://src/world/fieldportal.gd"))
	arrival.set("portal_id", "descent_entrance")
	arrival.position = ENTRY
	_own(arrival, interactables)

	_place("res://scene/ui/characterhud.tscn", _root, Vector2.ZERO, "hudcontrol")
	var labels := Node2D.new()
	labels.name = "floatinglabels"
	labels.z_index = 90
	_own(labels, _root)
	labels.add_to_group(&"floatinglabels", true)

	var run := Node.new()
	run.name = "descentrun"
	run.set_script(load("res://src/world/descent/descentrun.gd"))
	run.set("room_rect", room_rect())
	run.set("entry_spot", ENTRY)
	_own(run, _root)

	var packed := PackedScene.new()
	var packing: int = packed.pack(_root)
	if packing != OK:
		return packing
	var saved: int = ResourceSaver.save(packed, OUT)
	_root.free()
	return saved


static func room_rect() -> Rect2:
	"""The floor monsters stand on: inside the side walls' faces, from the
	back wall's foot to the front wall's face."""
	return Rect2(SIDE_LEFT + 9.5, WALL_BACK + 8.0, (SIDE_RIGHT - 9.5) - (SIDE_LEFT + 9.5), (WALL_FRONT - 36.0) - (WALL_BACK + 8.0))


func _nav_polygon() -> NavigationPolygon:
	var r: Rect2 = room_rect()
	var poly := NavigationPolygon.new()
	poly.vertices = PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	poly.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	return poly


func _walls(props: Node) -> void:
	"""The four corners, the back wall with its two doors, the front with its
	one, and the sides between - every piece end to end."""
	var back_corner_y: float = WALL_BACK + 8.0
	_place("res://scene/crypt/wallcornerbackleft.tscn", props, Vector2(SIDE_LEFT + 8.5, back_corner_y))
	_place("res://scene/crypt/wallcornerbackright.tscn", props, Vector2(SIDE_RIGHT - 8.0, back_corner_y))
	_place("res://scene/crypt/wallcornerfrontleft.tscn", props, Vector2(SIDE_LEFT + 8.5, WALL_FRONT))
	_place("res://scene/crypt/wallcornerfrontright.tscn", props, Vector2(SIDE_RIGHT - 8.5, WALL_FRONT))
	_run(props, SIDE_LEFT + 21.5, SIDE_RIGHT - 20.5, WALL_BACK, BACK)
	_run(props, SIDE_LEFT + 21.5, SIDE_RIGHT - 21.5, WALL_FRONT, FRONT)
	for side in [SIDE_LEFT, SIDE_RIGHT]:
		_side(props, side, back_corner_y, WALL_FRONT - 58.0)


func _run(props: Node, from_x: float, to_x: float, foot: float, widths: Array) -> void:
	var x: float = from_x
	for w in widths:
		if w is String:
			var door := Node2D.new()
			door.name = str(w)
			door.set_script(load("res://src/world/descent/descentdoor.gd"))
			door.set("entrance", str(w) == "doorfront")
			door.position = Vector2(x + GAP / 2.0, foot)
			_own(door, props)
			# Its body saved with it, shut: the suite walks the scene as saved.
			var body: StaticBody2D = (load("res://src/world/descent/descentdoor.gd") as GDScript).call("make_body")
			_own(body, door)
			for shape in body.get_children():
				shape.owner = _root
			x += GAP
		else:
			_place(PIECES[int(w)], props, Vector2(x + float(w) / 2.0, foot))
			x += float(w)
	if absf(x - to_x) > 0.01:
		push_error("builddescent: the wall at y %s ends at %s, not %s" % [foot, x, to_x])


func _side(props: Node, x: float, from_y: float, to_y: float) -> void:
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
		push_error("builddescent: the side wall at x %s is %s short of %s" % [x, left, to_y])


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
