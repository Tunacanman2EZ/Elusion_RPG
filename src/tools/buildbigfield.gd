# buildbigfield.gd - writes scene/bigfield.tscn, the Big Field, from the
# build file tools/maps/bigfield.py makes (0.94.0).
#
# Run once from a scene (build()); running it again writes the map afresh and
# loses anything changed in the scene by hand - change the build file instead
# (tools/maps/: python3 bigfield.py SEED OUT_DIR, then copy
# OUT_DIR/bigfield_build.json over tools/maps/bigfield_build.json).
#
# THE OWNER, 28 Oct: "we need to mix the maps from earlier with these ones to
# make it more complex" - a hub where you arrive (THE CROSSROADS) and a wing a
# tier off it, each wing built its own way - and "we have to add the walls all
# around the map nice and perfectly the doors all of it".
#
# ALL OF IT IS THE GAME'S OWN ART, put together: the floor is the underground
# plateau (scene/world/underground.tres - the rift's cliffs and rims are its
# own edge tiles), the walls, doors, pillars, candelabras and bones are the
# crypt pieces in scene/crypt/, the gates are the spike doors and the levers
# the Field's.
#
# THE WALLS ARE THE BUILD FILE'S, piece by piece: every edge of the floor is
# walled with whole crypt pieces laid end to end, nothing over anything (the
# Endless's rule, 0.93.2). bigfield.py works out where each goes - see its
# walls.py - and this places them; it adds nothing of its own.
#
#   THE CROSSROADS (arrive) - the hub, in the middle of the west
#     N   the chasm (door), its rift and bridges        tier 2
#     N   the caverns' shortcut (gate)
#     E   the caverns (door at their end), the arena    tier 3
#     E   the descent: two rings, the ladder at heart    tier 5
#     S   the fortress's gatehouse (door) and its grid   tier 4
#     S   the crypt (door), the optional skeleton wing
#     W   the courts                                     tier 1
extends Node

const OUT := "res://scene/bigfield.tscn"
const BUILD := "res://tools/maps/bigfield_build.json"
const TILESET := "res://scene/world/underground.tres"
const TILE := 16
const SOURCE := 1
const CRYPT := "res://scene/crypt/%s.tscn"
const ENEMY := "res://scene/enemy/%s.tscn"
# A monster's reach from home before it turns back, as the Big Field's always was.
const LEASH := 250.0

var _root: Node2D = null
var _cache: Dictionary = {}


func build(build_path: String = BUILD, out_path: String = OUT) -> int:
	var text: String = FileAccess.get_file_as_string(build_path)
	if text == "":
		push_error("buildbigfield: no build file at %s" % build_path)
		return ERR_FILE_NOT_FOUND
	var data: Variant = JSON.parse_string(text)
	if not (data is Dictionary):
		return ERR_PARSE_ERROR
	var plan: Dictionary = data
	var tiles: TileSet = load(TILESET) as TileSet
	if tiles == null:
		return ERR_FILE_NOT_FOUND

	_root = Node2D.new()
	_root.name = "bigfield"
	_root.set_script(load("res://src/world/field.gd"))
	_root.set("bullet_zone", true)

	var ground := TileMapLayer.new()
	ground.name = "ground"
	ground.z_index = -10
	ground.tile_set = tiles
	_own(ground, _root)
	_paint(ground, plan)
	var nav := NavigationRegion2D.new()
	nav.name = "navigationregion2d"
	nav.navigation_polygon = _nav_polygon(plan)
	_own(nav, ground)
	_place(CRYPT % "cryptambience", ground, Vector2.ZERO, "cryptambience")

	var world := TileMapLayer.new()
	world.name = "ysortworld"
	world.y_sort_enabled = true
	_own(world, _root)
	var props := _container("props", world)
	var arrival := _vec(plan["arrival"])
	var teleport := AnimatedSprite2D.new()
	teleport.name = "teleport"
	teleport.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	teleport.position = arrival
	teleport.scale = Vector2(1.5, 1.5)
	teleport.sprite_frames = load("res://art/teleport/teleportframes.tres")
	teleport.autoplay = "default"
	_own(teleport, props)
	var crypt := _container("crypt", props)
	var walls := _container("walls", crypt)
	var plugs: Array[Vector2] = []
	for piece in plan["walls"]:
		var at := Vector2(float(piece[1]), float(piece[2]))
		_place(CRYPT % str(piece[0]), walls, at)
		if str(piece[0]) == "pillar":
			plugs.append(at)
	_plug_pillars(props, plugs)
	var doors := _container("doors", crypt)
	for door in plan["doors"]:
		var d: Node = _place(CRYPT % "door", doors, Vector2(float(door["x"]), float(door["y"])), str(door["name"]))
		d.set("starts_open", false)
	var decor := _container("decor", crypt)
	for prop in plan["props"]:
		_place(CRYPT % str(prop[0]), decor, Vector2(float(prop[1]), float(prop[2])))

	var interactables := _container("interactables", world)
	_arrival(interactables, arrival)
	_ladder(interactables, _vec(plan["ladder"]))
	_gates(interactables, plan["gates"])
	var enemies := _container("enemies", world)
	_monsters(enemies, plan["monsters"])
	_container("groundeffects", world, "groundeffects")
	_container("projectiles", world, "projectiles")
	_container("lootbags", world, "lootbags")
	_container("pets", world, "pets_container")
	# Where a player stands when no marker is named - and where the suite
	# starts its walk of the map.
	var standing: Node2D = _container("player", world)
	standing.position = arrival + Vector2(0, 12)
	var above := Node2D.new()
	above.name = "aboveworld"
	_own(above, world)

	_place("res://scene/ui/floatinglabel.tscn", _root, Vector2.ZERO, "floatinglabel")
	_place("res://scene/ui/characterhud.tscn", _root, Vector2.ZERO, "hudcontrol")
	var labels := Node2D.new()
	labels.name = "floatinglabels"
	labels.z_index = 90
	_own(labels, _root)
	labels.add_to_group(&"floatinglabels", true)
	_place("res://scene/world/enemyrespawner.tscn", _root, Vector2.ZERO, "enemyrespawner")

	var packed := PackedScene.new()
	var packing: int = packed.pack(_root)
	if packing != OK:
		return packing
	var result: int = ResourceSaver.save(packed, out_path)
	_root.free()
	return result


# =============================================================================
# THE FLOOR AND THE WAY ROUND IT
# =============================================================================

func _paint(ground: TileMapLayer, plan: Dictionary) -> void:
	"""The plain floor in its twelve variants wherever the build file has
	floor, then the rift's own tiles: the north bank's cliff, the south
	bank's rim, the bridges' edges. (-1, -1) is the dark: no tile at all."""
	var rows: Array = plan["floor"]
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			if row[x] == "1":
				var h: int = absi((x * 7919 + y * 104729) % 12)
				ground.set_cell(Vector2i(x, y), SOURCE, Vector2i(1 + h % 4, 1 + floori(h / 4.0)))
	for t in plan["tiles"]:
		var cell := Vector2i(int(t[0]), int(t[1]))
		if int(t[2]) < 0:
			ground.erase_cell(cell)
		else:
			ground.set_cell(cell, SOURCE, Vector2i(int(t[2]), int(t[3])))


func _nav_polygon(plan: Dictionary) -> NavigationPolygon:
	"""The walkable floor: every loop of it at its walls' faces, holes and
	all, the closed doors and the halls' pillars cut out, baked."""
	var poly := NavigationPolygon.new()
	poly.agent_radius = 0.0
	var source := NavigationMeshSourceGeometryData2D.new()
	for outline in plan["nav"]["outlines"]:
		var pts := PackedVector2Array()
		for p in outline["points"]:
			pts.append(_vec(p))
		if bool(outline["hole"]):
			source.add_obstruction_outline(pts)
		else:
			source.add_traversable_outline(pts)
	for block in plan["nav"]["obstructions"]:
		var pts := PackedVector2Array()
		for p in block:
			pts.append(_vec(p))
		source.add_obstruction_outline(pts)
	NavigationServer2D.bake_from_source_geometry_data(poly, source)
	return poly


func _plug_pillars(walls: Node, at: Array[Vector2]) -> void:
	"""A pillar's body is the bottom 12 px of it, a run's the whole 28: in a
	wall, the 18 px above a pillar's body is filled, or a player squeezes in
	over it - beside a door, or where a wall's end meets a corridor - and out
	into the dark behind the wall. One body, a box a pillar, on the walls'
	layer."""
	if at.is_empty():
		return
	var body := StaticBody2D.new()
	body.name = "pillarplugs"
	_own(body, walls)
	var box := RectangleShape2D.new()
	box.size = Vector2(17, 18)
	for i in at.size():
		var shape := CollisionShape2D.new()
		shape.name = "plug%d" % i
		shape.shape = box
		shape.position = at[i] + Vector2(0, -21)
		_own(shape, body)


# =============================================================================
# WAYS IN AND OUT, GATES, MONSTERS
# =============================================================================

func _arrival(interactables: Node, at: Vector2) -> void:
	"""Where the town's way out lands: the Big Field's own arrival portal,
	which closes behind you, and its marker."""
	var gate := Area2D.new()
	gate.name = "fieldteleport"
	gate.position = at
	gate.scale = Vector2(1.5, 1.5)
	gate.collision_layer = 16
	gate.collision_mask = 4
	gate.set_script(load("res://src/world/leavetown.gd"))
	gate.set("vanish_after_first_use", true)
	gate.set("arrival_only", true)
	_own(gate, interactables)
	gate.set("visual", NodePath("../../props/teleport"))
	var shape := CollisionShape2D.new()
	shape.name = "collisionshape2d"
	var rect := RectangleShape2D.new()
	rect.size = Vector2(16.666668, 16.666668)
	shape.shape = rect
	_own(shape, gate)
	var marker := Marker2D.new()
	marker.name = "arrivalmarker"
	marker.position = Vector2(0, 8)
	marker.set_script(load("res://src/world/fieldportal.gd"))
	marker.set("portal_id", "field_entrance")
	_own(marker, gate)
	gate.connect("body_entered", Callable(gate, "_on_body_entered"), CONNECT_PERSIST)
	gate.connect("body_exited", Callable(gate, "_on_body_exited"), CONNECT_PERSIST)


func _ladder(interactables: Node, at: Vector2) -> void:
	"""The way down to the Field, at the descent's heart, and where a player
	climbing back up arrives."""
	var ladder: Node = _place("res://scene/ladderdown.tscn", interactables, at, "ladderdown")
	ladder.set("collision_layer", 16)
	ladder.set("collision_mask", 4)
	ladder.set("destination_scene_path", "res://scene/field.tscn")
	ladder.set("target_spawn_id", "field_entrance")
	ladder.connect("body_entered", Callable(ladder, "_on_body_entered"), CONNECT_PERSIST)
	ladder.connect("body_exited", Callable(ladder, "_on_body_exited"), CONNECT_PERSIST)
	var back := Node2D.new()
	back.name = "ladderarrival"
	back.position = at + Vector2(0, 27)
	back.set_script(load("res://src/world/fieldportal.gd"))
	back.set("portal_id", "boss_ladder")
	_own(back, interactables)


func _gates(interactables: Node, gates: Array) -> void:
	"""Each shortcut's spikes, raised, and the lever in its wing's far room
	that lowers them - the Field's spike doors and levers, as its boss gates
	are (on the root, the lever's targets three levels up)."""
	for gate in gates:
		var targets: Array[NodePath] = []
		var k: int = 0
		for spot in gate["spikes"]:
			var spike_name: String = "%s_spikes%d" % [gate["name"], k]
			_place("res://scene/interactables/spikedoor.tscn", _root, _vec(spot), spike_name)
			targets.append(NodePath("../../../" + spike_name))
			k += 1
		var lever: Node = _place("res://scene/interactables/lever.tscn", interactables, _vec(gate["lever"]),
			"%s_lever" % gate["name"])
		lever.set("targets", targets)


func _monsters(enemies: Node, monsters: Array) -> void:
	var count: Dictionary = {}
	for m in monsters:
		var kind: String = str(m["scene"])
		var land: String = str(m["land"])
		count[land] = int(count.get(land, 0)) + 1
		var label: String = "%s_%03d_%s" % [land, int(count[land]), kind]
		var monster: Node = _place(ENEMY % kind, enemies, Vector2(float(m["x"]), float(m["y"])), label)
		monster.set("leash_range", float(m.get("leash", LEASH)))


# =============================================================================
# PUTTING A NODE IN THE SCENE
# =============================================================================

func _vec(p: Variant) -> Vector2:
	return Vector2(float(p[0]), float(p[1]))


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
	if not _cache.has(path):
		_cache[path] = load(path)
	# As the editor does: the packed scene then keeps only what differs from
	# the piece's own scene - not, say, a lever's own signal wiring twice.
	var piece: Node = (_cache[path] as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	if node_name != "":
		piece.name = node_name
	if piece is Node2D:
		(piece as Node2D).position = at
	parent.add_child(piece, node_name == "")
	piece.owner = _root
	return piece
