# groundchunks.gd - the Big Field's floor drawn in chunks, the ones in view
# at once and the rest a few a frame (0.135.5). Added to every area by
# AreaRegistry, the way propchunks.gd is; an area whose "ground" carries no
# chunk ranges gets none.
#
# WHY. Walking into the Big Field was one long frame, and most of it was the
# floor: the "ground" TileMapLayer's 135,926 cells, built all at once at the
# end of the frame it arrived in. Measured in the container (zz/benchload.gd):
# the rest of that frame 281 ms with the ground, 75 with it switched off; the
# whole load frame ~500-530 ms, ~295-320 with the floor in chunks, and no
# frame after it worse than before. Each cell is one of twelve floor tiles
# at random, so no repeating picture can stand in.
#
# HOW. buildbigfield.gd writes the ground's cells chunk by chunk (CHUNK_CELLS
# square, propchunks.gd's 1,024 px) and keeps each chunk's bytes of
# tile_map_data on the ground (RANGES_META: chunk x, chunk y, start, end - a
# 2-byte header then 12 bytes a cell). Godot keeps a layer's cells in the
# order they were set, through saving and loading, so each range is a working
# layer of its own. As the area arrives (AreaRegistry, on scene_changed -
# before the ground's own deferred build) the ground is switched off and a
# layer is made for each chunk the view can see; the rest follow nearest
# first, until BUDGET_MS is spent each frame (never fewer than one), about
# half a second for the lot. Any chunk the view reaches before its turn is
# made at once, in _process or just before the frame is drawn.
#
# THE SAME FLOOR. The chunks are the ground's own cells with its tile set and
# drawing settings, children of the ground ahead of its other children, so
# they draw where it drew, under what it had on top (scorch marks). Edge
# tiles collide from their chunk. The ground keeps every cell for what reads
# it - the world map, BulletZone, the scorch marks, the tests - and the
# editor still shows it whole.
extends Node

const NODE_NAME := "groundchunks"
# A chunk's side, in cells.
const CHUNK_CELLS := 64
# On the ground, from the builder: the side used, and the ranges.
const SIZE_META := &"chunk_size"
const RANGES_META := &"chunk_ranges"
# On each chunk layer: its chunk.
const CHUNK_META := &"ground_chunk"
const BUDGET_MS := 2.0
# Made while within this of the view.
const VIEW_MARGIN := 128.0
# What the ground draws and collides with, given to each chunk.
const COPIED := ["texture_filter", "texture_repeat", "material", "use_parent_material",
	"light_mask", "visibility_layer", "modulate", "self_modulate", "collision_enabled",
	"use_kinematic_bodies", "collision_visibility_mode", "navigation_enabled",
	"navigation_visibility_mode", "rendering_quadrant_size", "physics_quadrant_size",
	"occlusion_enabled", "x_draw_order_reversed", "y_sort_enabled", "y_sort_origin"]

var ground: TileMapLayer = null
var _data: PackedByteArray = PackedByteArray()
var _size: int = CHUNK_CELLS
# chunk -> [start, end] in _data
var _ranges: Dictionary = {}
# chunk -> its layer, once made
var _made: Dictionary = {}
# chunks still to make, nearest the arrival first
var _queue: Array[Vector2i] = []
var _seen: Rect2i = Rect2i()


static func add_to(scene: Node) -> Node:
	"""The floor's helper for `scene`, or null when its ground has no chunks."""
	if scene == null or not scene.is_inside_tree():
		return null
	var layer: TileMapLayer = scene.get_node_or_null(^"ground") as TileMapLayer
	if layer == null or not layer.has_meta(RANGES_META) or not layer.enabled:
		return null
	var helper := (load("res://src/world/groundchunks.gd") as GDScript).new() as Node
	helper.name = NODE_NAME
	if not bool(helper.call("take", layer)):
		helper.free()
		return null
	scene.add_child(helper)
	return helper


static func chunk_of(cell: Vector2i, size: int = CHUNK_CELLS) -> Vector2i:
	return Vector2i(floori(cell.x / float(size)), floori(cell.y / float(size)))


static func order_by_chunks(layer: TileMapLayer, size: int = CHUNK_CELLS) -> void:
	"""For the builders: `layer`'s cells set again chunk by chunk (chunks in
	order, cells within a chunk row by row), and each chunk's bytes of
	tile_map_data kept on it. The same cells; only their order changes."""
	var by_chunk: Dictionary = {}
	for cell in layer.get_used_cells():
		var key: Vector2i = chunk_of(cell, size)
		if not by_chunk.has(key):
			by_chunk[key] = []
		by_chunk[key].append([cell, layer.get_cell_source_id(cell), layer.get_cell_atlas_coords(cell),
			layer.get_cell_alternative_tile(cell)])
	var keys: Array = by_chunk.keys()
	keys.sort()
	# CLEARED FOR GOOD FIRST: clear() only marks the cells empty until the
	# layer's next update, and a cell set again keeps its old place.
	layer.clear()
	layer.update_internals()
	var ranges := PackedInt32Array()
	var at: int = 0
	for key: Vector2i in keys:
		var cells: Array = by_chunk[key]
		cells.sort_custom(_row_order)
		for entry in cells:
			layer.set_cell(entry[0], entry[1], entry[2], entry[3])
		ranges.append_array([key.x, key.y, 2 + 12 * at, 2 + 12 * (at + cells.size())])
		at += cells.size()
	layer.set_meta(SIZE_META, size)
	layer.set_meta(RANGES_META, ranges)


static func _row_order(a: Array, b: Array) -> bool:
	var ca: Vector2i = a[0]
	var cb: Vector2i = b[0]
	return ca.y < cb.y or (ca.y == cb.y and ca.x < cb.x)


static func ranges_fit(ranges: PackedInt32Array, data_size: int) -> bool:
	"""The ranges cover the data from its header to its end, each straight
	after the last, whole cells each. A ground edited in the editor since it
	was built may not: then the floor is left as it is."""
	if ranges.is_empty() or ranges.size() % 4 != 0:
		return false
	var at: int = 2
	for i in range(0, ranges.size(), 4):
		if ranges[i + 2] != at or ranges[i + 3] <= at or (ranges[i + 3] - at) % 12 != 0:
			return false
		at = ranges[i + 3]
	return at == data_size


func take(layer: TileMapLayer) -> bool:
	"""Switch `layer` off and make the chunks the arrival can see. False, and
	nothing changed, when its ranges do not fit its data."""
	var ranges: PackedInt32Array = layer.get_meta(RANGES_META)
	var data: PackedByteArray = layer.tile_map_data
	if not ranges_fit(ranges, data.size()):
		push_warning("GroundChunks: %s's chunk ranges do not fit its cells - rebuild the map." % layer.get_path())
		return false
	ground = layer
	_data = data
	_size = int(layer.get_meta(SIZE_META, CHUNK_CELLS))
	for i in range(0, ranges.size(), 4):
		_ranges[Vector2i(ranges[i], ranges[i + 1])] = [ranges[i + 2], ranges[i + 3]]
	ground.enabled = false
	var arrival: Vector2 = _arrival()
	var keys: Array = _ranges.keys()
	var middle := Vector2(_world_to_chunks(Rect2(arrival, Vector2.ZERO)).position)
	keys.sort_custom(_nearer.bind(middle))
	_queue.assign(keys)
	var at_arrival := Rect2(arrival - _view_size() * 0.5, _view_size())
	make_in(at_arrival.grow(VIEW_MARGIN))
	return true


func _nearer(a: Vector2i, b: Vector2i, middle: Vector2) -> bool:
	return Vector2(a).distance_squared_to(middle) < Vector2(b).distance_squared_to(middle)


func _ready() -> void:
	# Paused or not: a menu can be open while the floor comes in.
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not RenderingServer.frame_pre_draw.is_connected(_on_pre_draw):
		RenderingServer.frame_pre_draw.connect(_on_pre_draw)


func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_on_pre_draw):
		RenderingServer.frame_pre_draw.disconnect(_on_pre_draw)


func _process(_delta: float) -> void:
	_make_seen()
	var started: int = Time.get_ticks_usec()
	var made: int = 0
	while not _queue.is_empty() and (made == 0 or Time.get_ticks_usec() - started < int(BUDGET_MS * 1000.0)):
		var key: Vector2i = _queue.pop_front()
		if not _made.has(key):
			_make(key)
			made += 1
	if _queue.is_empty() or _made.size() == _ranges.size():
		_done()


func _on_pre_draw() -> void:
	_make_seen()


func _make_seen() -> void:
	if ground == null or not is_inside_tree() or not ground.is_inside_tree():
		return
	var view: Rect2 = _view_rect()
	if view.size == Vector2.ZERO:
		return
	make_in(view.grow(VIEW_MARGIN))


func make_in(world: Rect2) -> int:
	"""Every chunk touching `world` (the world's space) made now. How many."""
	if ground == null:
		return 0
	var span: Rect2i = _world_to_chunks(world)
	if span == _seen:
		return 0
	_seen = span
	var made: int = 0
	for y in range(span.position.y, span.end.y):
		for x in range(span.position.x, span.end.x):
			var key := Vector2i(x, y)
			if _ranges.has(key) and not _made.has(key):
				_make(key)
				made += 1
	return made


func _world_to_chunks(world: Rect2) -> Rect2i:
	var to_cells: Transform2D = ground.get_global_transform().affine_inverse() \
		if ground.is_inside_tree() else ground.transform.affine_inverse()
	var local: Rect2 = to_cells * world
	var tile := Vector2(ground.tile_set.tile_size) if ground.tile_set != null else Vector2(16, 16)
	var side: Vector2 = tile * float(_size)
	var from := Vector2i((local.position / side).floor())
	var to := Vector2i((local.end / side).floor())
	return Rect2i(from, to - from + Vector2i.ONE)


func _make(key: Vector2i) -> void:
	var range_of: Array = _ranges[key]
	var layer := TileMapLayer.new()
	layer.name = "groundchunk_%d_%d" % [key.x, key.y]
	layer.set_meta(CHUNK_META, key)
	for property in COPIED:
		if property in ground:
			layer.set(property, ground.get(property))
	layer.tile_set = ground.tile_set
	layer.tile_map_data = _data.slice(0, 2) + _data.slice(int(range_of[0]), int(range_of[1]))
	ground.add_child(layer)
	# Ahead of the ground's own children, as its own tiles were.
	ground.move_child(layer, _made.size())
	_made[key] = layer
	# Built now, not at the end of the frame: a chunk made for the view is
	# drawn in the frame that asked for it, and the budget counts its cost.
	layer.update_internals()


func _done() -> void:
	_data = PackedByteArray()
	set_process(false)
	if RenderingServer.frame_pre_draw.is_connected(_on_pre_draw):
		RenderingServer.frame_pre_draw.disconnect(_on_pre_draw)


func made_count() -> int:
	return _made.size()


func chunk_count() -> int:
	return _ranges.size()


func chunk_layers() -> Array:
	return _made.values()


func _arrival() -> Vector2:
	"""Where the view will be: the player's spot, else the camera's, else the
	floor's middle."""
	var player: Node2D = ground.get_tree().get_first_node_in_group(&"player") as Node2D \
		if ground.is_inside_tree() else null
	if player != null and player.is_inside_tree():
		return player.global_position
	var camera: Camera2D = ground.get_viewport().get_camera_2d() if ground.is_inside_tree() else null
	if camera != null:
		return camera.global_position
	var used: Rect2i = ground.get_used_rect()
	var tile := Vector2(ground.tile_set.tile_size)
	return ground.to_global((Vector2(used.position) + Vector2(used.size) * 0.5) * tile)


func _view_size() -> Vector2:
	"""The view's size in the world: the screen over the zoom, 1x (the widest)
	when there is no camera to ask."""
	var viewport: Viewport = ground.get_viewport()
	if viewport == null:
		return Vector2(1280, 720)
	var zoom: float = 1.0
	var camera: Camera2D = viewport.get_camera_2d()
	if camera != null:
		zoom = maxf(minf(absf(camera.zoom.x), absf(camera.zoom.y)), 0.01)
	return viewport.get_visible_rect().size / zoom


func _view_rect() -> Rect2:
	"""What the screen shows of the world (propchunks.gd's view_rect())."""
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return Rect2()
	var to_world: Transform2D = viewport.get_canvas_transform().affine_inverse()
	var size: Vector2 = viewport.get_visible_rect().size
	var view := Rect2(to_world * Vector2.ZERO, Vector2.ZERO)
	view = view.expand(to_world * size)
	view = view.expand(to_world * Vector2(size.x, 0.0))
	return view.expand(to_world * Vector2(0.0, size.y))
