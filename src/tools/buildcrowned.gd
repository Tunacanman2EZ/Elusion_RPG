# buildcrowned.gd - writes scene/boss.tscn, the Crowned's room (0.134.0, step 1
# of the commit folder's CROWNED_PLAN.txt: "Bigger, walled all round,
# symmetrical; seven lit points round the edge, one per land").
#
# Run once from a scene (build()); the scene it writes is then an ordinary
# area the owner can open and decorate in the editor. Running it again
# writes the room afresh and loses anything changed there by hand.
#
# ALL OF IT IS THE GAME'S OWN ART, as the Endless is (buildendless.gd): the
# Big Field's underground floor (scene/world/underground.tres), the crypt's
# walls, candelabras, lanterns and bones (scene/crypt/), the ladder and the
# teleporter. The seven crown lights are drawn in code (crownedfight.gd).
#
#   +==================================================+
#   |  [crown]          [crown]          [crown]       |
#   |                 (victory teleporter)             |
#   | [crown]                                  [crown] |
#   |                   THE CROWNED                    |
#   | [crown]                                  [crown] |
#   |                     arrival                      |
#   |                     ladder                       |
#   +==================================================+
#
# WHAT IS KEPT FROM THE ROOM IT REPLACES: the root "bossroom" and its script
# (src/enemies/boss.gd: the bullet zone, the player), the Crowned at
# ysortworld/enemies/bossenemy standing at (-400, 100) - where the server's
# gamedata.json has it, so nothing on the server changes - the ladder up to
# the Field (target "boss_ladder"), the arrival marker "boss_entrance", the
# victory teleporter waiting on the Crowned, the HUD and the respawner (two
# minutes, as before). The room is built round the Crowned: ORIGIN puts its
# middle there.
#
# THE WALLS ARE LAID AS THE ENDLESS'S ARE (one piece end to end with the next,
# the left half the right's mirror; an error rather than a piece over
# another): 846 wide - the two-run half (202) each side, and middles of 391
# at the back and 390 at the front, because the back right corner is drawn a
# pixel narrower than the left - and 768 tall, eleven tall side pieces and
# one short down each side.
#
# SMALLER (0.134.7). The owner: "lets reduce the size of the map a bit i
# think that would help a tiny bit"; then, of the plan, the room about a
# fifth smaller. It was 1,048 x 826 (a three-run half, twelve tall side
# pieces): one run off each half and one tall piece off each side make the
# floor 818 x 704 where it was 1,020 x 762 - a quarter less floor, the same
# shape near enough. The Crowned still stands at (-400, 100), so the server's
# gamedata.json is unchanged; the room is rebuilt round it (ORIGIN), the
# ladder, the arrival and the lights kept as far from their walls as they
# were.
extends Node

const OUT := "res://scene/boss.tscn"
const TILESET := "res://scene/world/underground.tres"
const TILE := 16
const WIDE := 846
const TALL := 774
const COLS := 53
const ROWS := 49
# The room's top-left in the world: the Crowned's (-400, 100) is (423, 384) in.
const ORIGIN := Vector2(-823, -284)
const BOSS_AT := Vector2(423, 384)
const WALL_BACK := 28.0
const WALL_FRONT := 768.0
const SIDE_LEFT := 4.5
const SIDE_RIGHT := 841.5
const WALL_HALF := [101, 101]
const BACK_MIDDLE := [17, 26, 51, 51, 101, 51, 51, 26, 17]
const FRONT_MIDDLE := [17, 26, 51, 101, 101, 51, 26, 17]
const WALL_PIECES := {101: "res://scene/crypt/wallrun4.tscn", 51: "res://scene/crypt/wallrun2.tscn",
	26: "res://scene/crypt/wallrun1.tscn", 17: "res://scene/crypt/pillar.tscn"}
const AMBIENCE := Color(0.46, 0.44, 0.56)
const ARRIVAL := Vector2(423, 650)
const LADDER := Vector2(423, 710)
const VICTORY := Vector2(423, 170)
# The floor inside the walls, in the room's own pixels.
const FLOOR := Rect2(14, 34, 818, 704)
# The seven crown lights, in crownedfight.gd's CROWN_ORDER (light, wind,
# water, ice, earth, fire, dark): up the left side, along the back, down the
# right.
const LIGHT_SPOTS := [Vector2(56, 542), Vector2(56, 301), Vector2(149, 66), Vector2(423, 66),
	Vector2(697, 66), Vector2(790, 301), Vector2(790, 542)]

var _root: Node2D = null


func build() -> int:
	var tiles: TileSet = load(TILESET) as TileSet
	if tiles == null:
		return ERR_FILE_NOT_FOUND
	_root = Node2D.new()
	_root.name = "bossroom"
	_root.set_script(load("res://src/enemies/boss.gd"))

	var ground := TileMapLayer.new()
	ground.name = "ground"
	ground.z_index = -10
	ground.tile_set = tiles
	ground.position = ORIGIN
	_own(ground, _root)
	_paint(ground)
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
	var interactables := _container("inteactables", world)
	var enemies := _container("enemies", world)
	_container("groundeffects", world, "groundeffects")
	_container("projectiles", world, "projectiles")
	_container("lootbags", world, "lootbags")
	_container("pets", world, "pets_container")
	var standing: Node2D = _container("player", world)
	standing.position = ORIGIN + ARRIVAL
	var above := Node2D.new()
	above.name = "aboveworld"
	_own(above, world)

	_outer_walls(props)
	_decorate(props)

	var ladder: Node = _place("res://scene/ladderup.tscn", interactables, ORIGIN + LADDER, "ladderup")
	ladder.set_script(load("res://src/world/ladder.gd"))
	ladder.set("collision_layer", 16)
	ladder.set("collision_mask", 4)
	ladder.set("destination_scene_path", "res://scene/field.tscn")
	ladder.set("target_spawn_id", "boss_ladder")
	ladder.connect("body_entered", Callable(ladder, "_on_body_entered"), CONNECT_PERSIST)
	ladder.connect("body_exited", Callable(ladder, "_on_body_exited"), CONNECT_PERSIST)
	var arrival := Node2D.new()
	arrival.name = "arrivalmarker"
	arrival.set_script(load("res://src/world/fieldportal.gd"))
	arrival.set("portal_id", "boss_entrance")
	arrival.position = ORIGIN + ARRIVAL
	_own(arrival, interactables)
	_victory(interactables)

	var boss: Node2D = _place("res://scene/enemy/bossenemy.tscn", enemies, ORIGIN + BOSS_AT, "bossenemy") as Node2D

	_place("res://scene/ui/characterhud.tscn", _root, Vector2.ZERO, "hudcontrol")
	var respawner: Node = _place("res://scene/world/enemyrespawner.tscn", _root, Vector2.ZERO, "enemyrespawner")
	respawner.set("respawn_seconds", 120.0)
	respawner.set("respawn_jitter", 0.0)
	respawner.set("min_player_distance", 400.0)

	var fight := Node2D.new()
	fight.name = "crownedfight"
	fight.set_script(load("res://src/world/crowned/crownedfight.gd"))
	fight.set("room_rect", Rect2(ORIGIN + FLOOR.position, FLOOR.size))
	var spots := PackedVector2Array()
	for spot in LIGHT_SPOTS:
		spots.append(ORIGIN + (spot as Vector2))
	fight.set("light_spots", spots)
	_own(fight, _root)

	if boss == null:
		_root.free()
		return ERR_CANT_CREATE
	var packed := PackedScene.new()
	var packing: int = packed.pack(_root)
	if packing != OK:
		_root.free()
		return packing
	var result: int = ResourceSaver.save(packed, OUT)
	_root.free()
	return result


func _victory(interactables: Node) -> void:
	"""The way home once the Crowned falls (victoryteleporter.gd), hidden and
	unsteppable until then, as the room it replaces had it."""
	var door := Area2D.new()
	door.name = "victoryteleporter"
	door.visible = false
	door.position = ORIGIN + VICTORY
	door.collision_layer = 16
	door.collision_mask = 4
	door.monitoring = false
	door.set_script(load("res://src/world/victoryteleporter.gd"))
	door.set("boss_path", NodePath("../../enemies/bossenemy"))
	_own(door, interactables)
	var picture := AnimatedSprite2D.new()
	picture.name = "teleporter"
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	picture.scale = Vector2(2.5, 2.25)
	picture.sprite_frames = load("res://art/teleport/teleportframes.tres") as SpriteFrames
	_own(picture, door)
	var shape := CollisionShape2D.new()
	shape.name = "collisionshape2d"
	var box := RectangleShape2D.new()
	box.size = Vector2(44, 44)
	shape.shape = box
	shape.disabled = true
	_own(shape, door)
	door.connect("body_entered", Callable(door, "_on_body_entered"), CONNECT_PERSIST)


# =============================================================================
# THE FLOOR
# =============================================================================

func _paint(ground: TileMapLayer) -> void:
	"""The plain floor in its twelve variants, edge to edge, the last row
	bare under the front wall (the Endless's floor)."""
	var rng := RandomNumberGenerator.new()
	rng.seed = 134
	for y in ROWS - 1:
		for x in COLS:
			ground.set_cell(Vector2i(x, y), 1, Vector2i(rng.randi_range(1, 4), rng.randi_range(1, 3)))


func _nav_polygon() -> NavigationPolygon:
	"""The floor inside the walls, in the ground layer's own pixels."""
	var poly := NavigationPolygon.new()
	var left: float = SIDE_LEFT + 4.5
	var right: float = SIDE_RIGHT - 4.5
	var top: float = WALL_BACK + 2.0
	var bottom: float = WALL_FRONT - 36.0
	poly.vertices = PackedVector2Array([Vector2(left, top), Vector2(right, top), Vector2(right, bottom),
		Vector2(left, bottom)])
	poly.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	return poly


# =============================================================================
# THE WALLS AND WHAT STANDS IN THE ROOM
# =============================================================================

func _outer_walls(props: Node) -> void:
	"""Walled all round as a crypt chamber is (buildendless.gd _outer_walls())."""
	var back_corner_y: float = WALL_BACK + 8.0
	_place("res://scene/crypt/wallcornerbackleft.tscn", props, ORIGIN + Vector2(SIDE_LEFT + 8.5, back_corner_y))
	_place("res://scene/crypt/wallcornerbackright.tscn", props, ORIGIN + Vector2(SIDE_RIGHT - 8.0, back_corner_y))
	_place("res://scene/crypt/wallcornerfrontleft.tscn", props, ORIGIN + Vector2(SIDE_LEFT + 8.5, WALL_FRONT))
	_place("res://scene/crypt/wallcornerfrontright.tscn", props, ORIGIN + Vector2(SIDE_RIGHT - 8.5, WALL_FRONT))
	_wall_run(props, SIDE_LEFT + 21.5, SIDE_RIGHT - 20.5, WALL_BACK, wall_widths(BACK_MIDDLE))
	_wall_run(props, SIDE_LEFT + 21.5, SIDE_RIGHT - 21.5, WALL_FRONT, wall_widths(FRONT_MIDDLE))
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
	var x: float = from_x
	for width in widths:
		_place(WALL_PIECES[int(width)], props, ORIGIN + Vector2(x + float(width) / 2.0, foot_y))
		x += float(width)
	if absf(x - to_x) > 0.01:
		push_error("buildcrowned: the wall at y %s ends at %s, not %s" % [foot_y, x, to_x])


func _wall_side(props: Node, x: float, from_y: float, to_y: float) -> void:
	var y: float = from_y
	while to_y - y >= 58.0 - 0.01:
		y += 58.0
		_place("res://scene/crypt/wallsidetall.tscn", props, ORIGIN + Vector2(x, y))
	var left: float = to_y - y
	if absf(left - 36.0) < 0.01:
		_place("res://scene/crypt/wallsidea.tscn", props, ORIGIN + Vector2(x, to_y))
	elif absf(left - 35.0) < 0.01:
		_place("res://scene/crypt/wallsideb.tscn", props, ORIGIN + Vector2(x, to_y))
	elif left > 0.01:
		push_error("buildcrowned: the side wall at x %s is %s short of %s" % [x, left, to_y])


func _decorate(props: Node) -> void:
	"""Candelabras by the ladder and either side of the crown at the back,
	lanterns down the sides between the crowns, the crypt's bones in the
	corners - all at the edges, out of the fight."""
	var middle: float = WIDE / 2.0
	for x in [130.0, middle - 138.0, middle + 138.0, WIDE - 130.0]:
		_place("res://scene/crypt/candelabra.tscn", props, ORIGIN + Vector2(x, 46))
	_place("res://scene/crypt/candelabra.tscn", props, ORIGIN + Vector2(middle - 54.0, WALL_FRONT - 66.0))
	_place("res://scene/crypt/candelabra.tscn", props, ORIGIN + Vector2(middle + 54.0, WALL_FRONT - 66.0))
	for y in [180.0, 437.0, WALL_FRONT - 86.0]:
		_place("res://scene/crypt/lantern.tscn", props, ORIGIN + Vector2(36, y))
		_place("res://scene/crypt/lantern.tscn", props, ORIGIN + Vector2(WIDE - 36, y))
	_place("res://scene/crypt/skullpile.tscn", props, ORIGIN + Vector2(80, 86))
	_place("res://scene/crypt/skullpile.tscn", props, ORIGIN + Vector2(WIDE - 80, 86))
	_place("res://scene/crypt/bones.tscn", props, ORIGIN + Vector2(120, WALL_FRONT - 56.0))
	_place("res://scene/crypt/ribcage.tscn", props, ORIGIN + Vector2(WIDE - 130, WALL_FRONT - 56.0))
	_place("res://scene/crypt/skullcandles.tscn", props, ORIGIN + Vector2(200, WALL_FRONT - 56.0))
	_place("res://scene/crypt/skullcandles.tscn", props, ORIGIN + Vector2(WIDE - 200, WALL_FRONT - 56.0))


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
