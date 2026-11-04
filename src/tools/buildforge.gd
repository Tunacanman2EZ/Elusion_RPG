# buildforge.gd - writes scene/forge.tscn, the Forge's island (step 1).
#
# Run once from a scene (build()), as builddescent.gd is; running it again
# writes the island afresh and loses anything changed there by hand.
#
# THE TANK'S WORLD, AS THE OWNER DREW IT. "the animated fire stays at the
# edges of the lava", "we need to make the map like a disc make it bigger",
# then "animated lava should only be here the rest stale reduce the amount of
# lava on the left and right of the map also we still want to see the lava
# falls" and "the lava is graphics heavy so i need to use it wisely".
#
#   - THE ISLAND: the underground floor (scene/world/underground.tres) in a
#     disc of RADIUS round CENTRE - 1,920 px across, wider than the Endless.
#   - THE LAKE: a ring BAND wide all the way round, the town's own lava tile
#     (art/tiles/propsandterrain.png, cell (0,5), nine frames at three a
#     second, each cell starting at a random moment - elusion.tscn's set-up)
#     WHERE IT MEETS THE SHORE, and that tile's first frame, still, everywhere
#     else (source 1). It lies under the whole island too, still, so a slice
#     that floods (forgerun.gd) only has to take the floor away.
#   - THE FALLS: lavafall.png's four frames, at FALLS_AT along the north,
#     pouring out of the dark past the lake into its outermost cells.
#   - The anvil in the middle, its glow (forgerun.gd sizes it to the light
#     the lava never enters), the arrival just south of it, and a wall round
#     the lake's far edge (OUTER_WALL), so nobody walks off the map.
extends Node

const Run := preload("res://src/world/forge/forgerun.gd")
const OUT := "res://scene/forge.tscn"
const TILESET := "res://scene/world/underground.tres"
const LAVA_SHEET := "res://art/tiles/propsandterrain.png"
const FALL_SHEET := "res://art/tiles/lavafall.png"
# The island's numbers are the run's (forgerun.gd, THE MAP), so the map and
# the rules that flood it can never disagree.
const LAVA_FRAMES := 9
const LAVA_FPS := 3.0
const FALLS_AT := [-480.0, -240.0, 0.0, 240.0, 480.0]
const FALL_FPS := 8.0
# The wall's inner face, a little inside the lake's last painted cells.
const OUTER_WALL := Vector2(Run.RADIUS + Run.BAND - 24.0, Run.RADIUS + Run.BAND + 64.0)
const WALL_PIECES := 96
const AMBIENCE := Color(0.66, 0.54, 0.5)
const ENTRY := Run.CENTRE + Vector2(0, 110)
const GLOW_COLOUR := Color(1.0, 0.7, 0.45)

var _root: Node2D = null


func build() -> int:
	var tiles: TileSet = load(TILESET) as TileSet
	if tiles == null:
		return ERR_FILE_NOT_FOUND
	_root = Node2D.new()
	_root.name = "forge"
	_root.set_script(load("res://src/world/field.gd"))
	_root.set("bullet_zone", true)
	_root.set("tells_story", false)

	var lava := TileMapLayer.new()
	lava.name = "lava"
	lava.z_index = -11
	lava.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	lava.tile_set = lava_tiles()
	_own(lava, _root)
	_paint_lake(lava)

	var ground := TileMapLayer.new()
	ground.name = "ground"
	ground.z_index = -10
	ground.tile_set = tiles
	_own(ground, _root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 119
	var reach: int = int(ceil(Run.RADIUS / Run.TILE))
	var middle := Vector2i(int(Run.CENTRE.x / Run.TILE), int(Run.CENTRE.y / Run.TILE))
	for y in range(-reach, reach + 1):
		for x in range(-reach, reach + 1):
			var cell := middle + Vector2i(x, y)
			if Run.floor_cell_mid(cell).distance_to(Run.CENTRE) <= Run.RADIUS:
				ground.set_cell(cell, 1, Vector2i(rng.randi_range(1, 4), rng.randi_range(1, 3)))
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

	_place("res://scene/interactables/anvil.tscn", props, Run.CENTRE, "anvil")
	_falls(props)
	_wall(props)
	var glow := PointLight2D.new()
	glow.name = "forgeglow"
	glow.texture = load("res://scene/crypt/lightgradient.tres") as Texture2D
	glow.color = GLOW_COLOUR
	glow.energy = 0.9
	glow.texture_scale = 2.3
	glow.position = Run.CENTRE
	_own(glow, _root)
	var arrival := Node2D.new()
	arrival.name = "forgearrival"
	arrival.set_script(load("res://src/world/fieldportal.gd"))
	arrival.set("portal_id", "forge_entrance")
	arrival.position = ENTRY
	_own(arrival, interactables)

	_place("res://scene/ui/characterhud.tscn", _root, Vector2.ZERO, "hudcontrol")
	var labels := Node2D.new()
	labels.name = "floatinglabels"
	labels.z_index = 90
	_own(labels, _root)
	labels.add_to_group(&"floatinglabels", true)

	var run := Node.new()
	run.name = "forgerun"
	run.set_script(load("res://src/world/forge/forgerun.gd"))
	run.set("entry_spot", ENTRY)
	_own(run, _root)

	var packed := PackedScene.new()
	var packing: int = packed.pack(_root)
	if packing != OK:
		return packing
	var saved: int = ResourceSaver.save(packed, OUT)
	_root.free()
	return saved


# =============================================================================
# THE LAKE
# =============================================================================

static func lava_tiles() -> TileSet:
	"""Two sources from one sheet: the town's bubbling lava, and its first
	frame still."""
	var tiles := TileSet.new()
	tiles.tile_size = Vector2i(Run.LAVA_TILE, Run.LAVA_TILE)
	var moving := TileSetAtlasSource.new()
	moving.texture = load(LAVA_SHEET) as Texture2D
	moving.texture_region_size = Vector2i(Run.LAVA_TILE, Run.LAVA_TILE)
	moving.create_tile(Run.LAVA_CELL)
	moving.set_tile_animation_columns(Run.LAVA_CELL, LAVA_FRAMES)
	moving.set_tile_animation_frames_count(Run.LAVA_CELL, LAVA_FRAMES)
	moving.set_tile_animation_speed(Run.LAVA_CELL, LAVA_FPS)
	moving.set_tile_animation_mode(Run.LAVA_CELL, TileSetAtlasSource.TILE_ANIMATION_MODE_RANDOM_START_TIMES)
	tiles.add_source(moving, Run.BUBBLING)
	var still := TileSetAtlasSource.new()
	still.texture = load(LAVA_SHEET) as Texture2D
	still.texture_region_size = Vector2i(Run.LAVA_TILE, Run.LAVA_TILE)
	still.create_tile(Run.LAVA_CELL)
	tiles.add_source(still, Run.STILL)
	return tiles


func _paint_lake(lava: TileMapLayer) -> void:
	"""Bubbling where it meets the shore, still everywhere else - the same
	rule the run repaints by (Run.bubbles())."""
	for cell in Run.lake_cells():
		lava.set_cell(cell, Run.BUBBLING if Run.bubbles(cell, {}, Run.SAFE_OTHER) else Run.STILL, Run.LAVA_CELL)


func _falls(props: Node) -> void:
	"""Pouring out of the dark past the lake: the drop over the black, the
	splash (the frame's last 32 px) on the lake's outermost cell."""
	var frames := SpriteFrames.new()
	frames.set_animation_speed(&"default", FALL_FPS)
	var sheet: Texture2D = load(FALL_SHEET) as Texture2D
	for i in 4:
		var piece := AtlasTexture.new()
		piece.atlas = sheet
		piece.region = Rect2(i * 32, 0, 32, 96)
		frames.add_frame(&"default", piece)
	var outer: float = Run.RADIUS + Run.BAND
	var n: int = 0
	for dx in FALLS_AT:
		var col: int = floori((Run.CENTRE.x + dx) / Run.LAVA_TILE)
		var row: int = floori((Run.CENTRE.y - outer) / Run.LAVA_TILE) - 1
		while Run.lava_cell_mid(Vector2i(col, row)).distance_to(Run.CENTRE) > outer:
			row += 1
		n += 1
		var fall := AnimatedSprite2D.new()
		fall.name = "lavafall%d" % n
		fall.sprite_frames = frames
		fall.autoplay = "default"
		fall.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		fall.position = Vector2(col * Run.LAVA_TILE + Run.LAVA_TILE / 2.0, row * Run.LAVA_TILE - 16.0)
		_own(fall, props)
		fall.add_to_group(&"forge_falls", true)


func _wall(props: Node) -> void:
	"""A ring of solid quads past the lake's far edge."""
	var body := StaticBody2D.new()
	body.name = "lakewall"
	body.collision_layer = 1
	body.collision_mask = 0
	_own(body, props)
	for i in WALL_PIECES:
		var a0: float = TAU * i / WALL_PIECES
		var a1: float = TAU * (i + 1) / WALL_PIECES
		var quad := ConvexPolygonShape2D.new()
		quad.points = PackedVector2Array([
			Run.at_angle(a0, OUTER_WALL.x), Run.at_angle(a0, OUTER_WALL.y),
			Run.at_angle(a1, OUTER_WALL.y), Run.at_angle(a1, OUTER_WALL.x)])
		var shape := CollisionShape2D.new()
		shape.name = "piece%d" % i
		shape.shape = quad
		_own(shape, body)


func _nav_polygon() -> NavigationPolygon:
	"""The island and the lake, a little inside the wall: fire walks lava."""
	var poly := NavigationPolygon.new()
	var points := PackedVector2Array()
	var indices := PackedInt32Array()
	var sides: int = 48
	for i in sides:
		var a: float = TAU * i / sides
		points.append(Run.at_angle(a, OUTER_WALL.x - 16.0))
		indices.append(i)
	poly.vertices = points
	poly.add_polygon(indices)
	return poly


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
