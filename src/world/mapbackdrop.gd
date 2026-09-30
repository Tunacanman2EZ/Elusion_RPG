extends Node2D
## What is drawn under an area's tiles: grey under every painted cell, and the
## black of the screen everywhere else.
##
## WHY THIS EXISTS. Many floor tiles have gaps in them - the town's cobblestones
## are a third transparent pixels - and a gap shows whatever is behind the
## tiles. That used to be the engine's grey, which is the colour the art was
## painted against: the gaps read as mortar. The browser round made the
## background black (so a frame with nothing in it is black, not grey), and
## every gap turned black with it - "my graphics trip out", on every scene.
##
## So the two are separate now. project.godot keeps the engine's grey, which
## is also what the editor draws behind the tiles, so a scene looks there the
## way it looks in the game. At runtime AreaRegistry makes the screen black
## (OUTSIDE), and adds one of these to each area: grey (GAPS) under every cell
## that any layer paints, and nothing past the edge of the map. A player sees
## the map, and black beyond it.
##
## No layer to paint and nothing to keep in step: it is read off the area's own
## TileMapLayers when the area opens, so a new area or a repainted one is
## covered the moment it is saved.

# The engine's default clear colour, which is what the tiles were painted over.
const GAPS := Color(0.3, 0.3, 0.3, 1.0)
# Past the edge of the map.
const OUTSIDE := Color(0.0, 0.0, 0.0, 1.0)

# One rectangle per run of painted cells in a row, in the area's own space.
var rects: Array[Rect2] = []


# Scene path -> its cover. An area's tiles do not change while it is played, and
# the field's cover takes tens of milliseconds to work out, so each area pays
# that once a session, on its first visit.
static var _covers: Dictionary = {}


static func add_to(area: Node) -> Node2D:
	"""Puts a backdrop under `area`'s tiles and returns it. An area with no
	tiles gets none."""
	if area == null:
		return null
	var path: String = area.scene_file_path
	var found: Array[Rect2] = []
	if path != "" and _covers.has(path):
		found = _covers[path]
	else:
		found = cover(area)
		if path != "":
			_covers[path] = found
	if found.is_empty():
		return null
	var backdrop := Node2D.new()
	backdrop.set_script(load("res://src/world/mapbackdrop.gd"))
	backdrop.name = "mapbackdrop"
	backdrop.rects = found
	# UNDER EVERYTHING, whatever z the layers use. The town's water is -20.
	backdrop.z_as_relative = false
	backdrop.z_index = RenderingServer.CANVAS_ITEM_Z_MIN
	area.add_child(backdrop)
	area.move_child(backdrop, 0)
	return backdrop


static func cover(area: Node) -> Array[Rect2]:
	"""Where every visible TileMapLayer under `area` draws a tile, merged into
	runs along each row, in `area`'s space.

	THE TILE AS DRAWN, NOT THE CELL IT SITS IN. The town's water is 32x32
	tiles on a 16x16 grid, one every other cell, and drawn centred - so its
	edge falls half a cell off the grid. Marking cells left three quarters of
	every water tile uncovered; rounding to whole cells put a band of grey
	past the edge of the map. The rectangles here are the tiles themselves.

	RUNS, NOT TILES. The field is thousands of tiles; a rectangle each would
	be thousands of draw commands every frame for a colour nobody looks at.
	Tiles in the same band that touch or overlap become one rectangle."""
	# band Vector2(y, height) -> Array of [x, width], in the area's space
	var bands: Dictionary = {}
	for found in area.find_children("*", "TileMapLayer", true, false):
		var layer: TileMapLayer = found
		if not layer.visible or layer.tile_set == null:
			continue
		var to_area: Transform2D = _transform_to(layer, area)
		var drawn: Dictionary = {}
		for cell in layer.get_used_cells():
			var shape: Rect2 = to_area * _drawn_rect(layer, cell, drawn)
			var band := Vector2(shape.position.y, shape.size.y)
			if not bands.has(band):
				bands[band] = []
			bands[band].append([shape.position.x, shape.size.x])

	var out: Array[Rect2] = []
	for band: Vector2 in bands:
		var y: float = band.x
		var height: float = band.y
		var spans: Array = bands[band]
		spans.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		var left: float = spans[0][0]
		var right: float = left + spans[0][1]
		for i in range(1, spans.size() + 1):
			if i < spans.size() and spans[i][0] <= right + 0.01:
				right = maxf(right, spans[i][0] + spans[i][1])
				continue
			out.append(Rect2(left, y, right - left, height))
			if i < spans.size():
				left = spans[i][0]
				right = left + spans[i][1]
	return out


static func _drawn_rect(layer: TileMapLayer, cell: Vector2i, known: Dictionary) -> Rect2:
	"""Where `cell`'s tile is drawn, in the layer's space: its texture region,
	centred on the cell, moved by its texture origin - which is how the layer
	draws it. A tile from a scene collection is its cell."""
	var size: Vector2 = Vector2(layer.tile_set.tile_size)
	var centre: Vector2 = layer.map_to_local(cell)
	var source_id: int = layer.get_cell_source_id(cell)
	var coords: Vector2i = layer.get_cell_atlas_coords(cell)
	var alternative: int = layer.get_cell_alternative_tile(cell)
	var key: Vector4i = Vector4i(source_id, coords.x, coords.y, alternative)
	if not known.has(key):
		var found: Array = [size, Vector2.ZERO]
		var source: TileSetSource = layer.tile_set.get_source(source_id) \
			if layer.tile_set.has_source(source_id) else null
		if source is TileSetAtlasSource and (source as TileSetAtlasSource).has_tile(coords):
			var atlas := source as TileSetAtlasSource
			var data: TileData = atlas.get_tile_data(coords, alternative)
			found = [Vector2(atlas.get_tile_texture_region(coords).size),
				Vector2(data.texture_origin) if data != null else Vector2.ZERO]
		known[key] = found
	var drawn: Array = known[key]
	return Rect2(centre - drawn[0] / 2.0 - drawn[1], drawn[0])


static func _transform_to(node: Node, area: Node) -> Transform2D:
	# By hand rather than get_global_transform(): the suite measures real area
	# scenes without putting them in the tree.
	var xf := Transform2D()
	var at: Node = node
	while at != null and at != area:
		if at is Node2D:
			xf = (at as Node2D).transform * xf
		at = at.get_parent()
	return xf


func _draw() -> void:
	for rect in rects:
		draw_rect(rect, GAPS)
