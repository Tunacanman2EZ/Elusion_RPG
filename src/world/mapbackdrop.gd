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

# THE BLACK, FOR BULLETS (0.72.1). The owner: "i still have the white bullet
# projectiles from warrior fling in the black of the map for some reason and
# spraying across the map instead of vanishing". The Big Field is walled all
# round, and a wall stops every bullet; the town, the Field and the boss arena
# are not - their edges stop a player's feet (tile collisions, water) and let a
# bullet fly on over the black until its range ran out, 300 px for a
# finisher's fan, three seconds for a wave. black_at() answers whether a point
# is past the painted map, and every flying bullet asks it each tick: over the
# black, it is gone.
#
# A GRID OF BLACK_CELL SQUARES over the rectangles above, a byte each, worked
# out with them when the area opens (and kept with them, per scene): any
# square a tile touches is map. One lookup a bullet a tick.
const BLACK_CELL := 8
var _grid: PackedByteArray = PackedByteArray()
var _grid_origin: Vector2i = Vector2i.ZERO
var _grid_size: Vector2i = Vector2i.ZERO
# The backdrop of the area being played, while it is in the tree.
static var _current: Node2D = null
# Scene path -> [grid, origin, size], beside _covers.
static var _grids: Dictionary = {}


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
	if path != "" and _grids.has(path):
		var kept: Array = _grids[path]
		backdrop.set("_grid", kept[0])
		backdrop.set("_grid_origin", kept[1])
		backdrop.set("_grid_size", kept[2])
	else:
		backdrop.call("build_grid")
		if path != "":
			_grids[path] = [backdrop.get("_grid"), backdrop.get("_grid_origin"), backdrop.get("_grid_size")]
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
	return _stacked(out)


static func _stacked(runs: Array[Rect2]) -> Array[Rect2]:
	"""Runs one above the other, the same left and right, become one
	rectangle (0.94.0). The Big Field's rooms and corridors are many runs to
	a row and three hundred rows - 2,667 rectangles a frame in rows, a few
	hundred stacked."""
	runs.sort_custom(_by_column)
	var out: Array[Rect2] = []
	for r in runs:
		if not out.is_empty():
			var last: Rect2 = out[out.size() - 1]
			if is_equal_approx(last.position.x, r.position.x) and is_equal_approx(last.size.x, r.size.x) \
					and absf(last.end.y - r.position.y) < 0.01:
				out[out.size() - 1] = Rect2(last.position, Vector2(last.size.x, r.end.y - last.position.y))
				continue
		out.append(r)
	return out


static func _by_column(a: Rect2, b: Rect2) -> bool:
	"""Left edge, then width, then top: runs that can stack end up together."""
	if not is_equal_approx(a.position.x, b.position.x):
		return a.position.x < b.position.x
	if not is_equal_approx(a.size.x, b.size.x):
		return a.size.x < b.size.x
	return a.position.y < b.position.y


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


func _enter_tree() -> void:
	_current = self


func _exit_tree() -> void:
	if _current == self:
		_current = null


func build_grid() -> void:
	"""BLACK_CELL squares over `rects`: 1 where a tile touches, 0 the black."""
	if rects.is_empty():
		return
	var box: Rect2 = rects[0]
	for rect in rects:
		box = box.merge(rect)
	_grid_origin = Vector2i(floori(box.position.x / BLACK_CELL), floori(box.position.y / BLACK_CELL))
	var far := Vector2i(ceili(box.end.x / BLACK_CELL), ceili(box.end.y / BLACK_CELL))
	_grid_size = far - _grid_origin
	_grid = PackedByteArray()
	_grid.resize(_grid_size.x * _grid_size.y)
	for rect in rects:
		var x0: int = floori(rect.position.x / BLACK_CELL) - _grid_origin.x
		var x1: int = ceili(rect.end.x / BLACK_CELL) - _grid_origin.x
		var y0: int = floori(rect.position.y / BLACK_CELL) - _grid_origin.y
		var y1: int = ceili(rect.end.y / BLACK_CELL) - _grid_origin.y
		for y in range(y0, y1):
			var row: int = y * _grid_size.x
			for x in range(x0, x1):
				_grid[row + x] = 1


func painted(local: Vector2) -> bool:
	"""Whether a tile is drawn at `local` (this node's space, the area's)."""
	if _grid.is_empty():
		return true
	var x: int = floori(local.x / BLACK_CELL) - _grid_origin.x
	var y: int = floori(local.y / BLACK_CELL) - _grid_origin.y
	if x < 0 or y < 0 or x >= _grid_size.x or y >= _grid_size.y:
		return false
	return _grid[y * _grid_size.x + x] != 0


static func black_at(any: Node, at: Vector2) -> bool:
	"""Whether `at` (a world position) is past the painted map of the area
	`any` is in - the black. False outside an area with a backdrop (a test's
	arena), so nothing there changes."""
	var backdrop: Node2D = _current
	if backdrop == null or not is_instance_valid(backdrop) or any == null:
		return false
	var area: Node = backdrop.get_parent()
	if area == null or (any != area and not area.is_ancestor_of(any)):
		return false
	return not backdrop.call("painted", backdrop.to_local(at))
