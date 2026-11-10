# testrunner_11.gd - part 11 of the suite (testrunner.gd says how it is
# split; part 10 passed 250 KB): _test_the_floor_comes_in_chunks.
extends "res://src/tools/testrunner_10.gd"


# =============================================================================
# THE BIG FIELD'S FLOOR IN CHUNKS (0.135.5)
# =============================================================================
# The owner's profiler entering the Big Field, then "build it": the ground's
# 135,926 cells were about 205 ms of the load frame in the container, built
# at once. groundchunks.gd draws the same cells in chunks - the view's at
# once, the rest a few a frame - from the ground's own data. These hold that
# nothing is seen to change: the same cells, the view's chunks there before a
# frame is drawn, a jump looked at at once, edge tiles still solid.
func _test_the_floor_comes_in_chunks() -> void:
	section("THE BIG FIELD'S FLOOR IN CHUNKS - the view's at once, the rest a few a frame, the same cells (0.135.5)")
	const Ground := preload("res://src/world/groundchunks.gd")

	# ---- the builder's half, on a small layer --------------------------------------
	var small := TileMapLayer.new()
	small.tile_set = load("res://scene/world/underground.tres")
	for k in 400:
		small.set_cell(Vector2i(posmod(k * 37, 301) - 100, posmod(k * 53, 211) - 60), 1, Vector2i(1 + k % 4, 1 + k % 3))
	var before: Dictionary = {}
	for cell in small.get_used_cells():
		before[cell] = small.get_cell_atlas_coords(cell)
	Ground.order_by_chunks(small, 16)
	var same: bool = small.get_used_cells().size() == before.size()
	for cell in small.get_used_cells():
		same = same and before.get(cell) == small.get_cell_atlas_coords(cell)
	var small_ranges: PackedInt32Array = small.get_meta(Ground.RANGES_META, PackedInt32Array())
	check("the builder sets a layer's cells again chunk by chunk: the same cells, ranges that fit, each cell in its own",
		same and Ground.ranges_fit(small_ranges, small.tile_map_data.size())
		and _strays(small.tile_map_data, small_ranges, 16) == 0 and int(small.get_meta(Ground.SIZE_META)) == 16,
		[same, _strays(small.tile_map_data, small_ranges, 16)])
	small.free()
	check("  and buildbigfield.gd does it to the ground once it is painted",
		_func_body(_code_src("res://src/tools/buildbigfield.gd"), "func build(").find("GroundChunks.order_by_chunks(ground)")
		> _func_body(_code_src("res://src/tools/buildbigfield.gd"), "func build(").find("_paint(ground, plan)"))

	# ---- the saved Big Field ---------------------------------------------------------
	var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BIG_FIELD_BUILD))
	var area: Node = (load(BIG_FIELD) as PackedScene).instantiate()
	var ground: TileMapLayer = area.get_node("ground")
	var ranges: PackedInt32Array = ground.get_meta(Ground.RANGES_META, PackedInt32Array())
	var size: int = int(ground.get_meta(Ground.SIZE_META, 0))
	var data: PackedByteArray = ground.tile_map_data
	var cells_total: int = ground.get_used_cells().size()
	check("the Big Field's ground keeps its chunks' ranges (%d chunks of %d cells), and they fit its %d cells"
		% [ranges.size() / 4, size, cells_total], size == Ground.CHUNK_CELLS and Ground.ranges_fit(ranges, data.size()))
	check("  every cell in its own chunk's range", _strays(data, ranges, size) == 0, _strays(data, ranges, size))

	# ---- live, as AreaRegistry adds it -----------------------------------------------
	var world := Node2D.new()
	area.remove_child(ground)
	ground.owner = null
	world.add_child(ground)
	area.free()
	var kept_canvas: Transform2D = get_viewport().canvas_transform
	var zoom_was: Variant = Settings.get_value("camera_zoom")
	Settings.set_value("camera_zoom", 3.0)
	var camera := Camera2D.new()
	world.add_child(camera)
	add_child(world)
	camera.make_current()
	var arrival := Vector2(float(plan["arrival"][0]), float(plan["arrival"][1]))
	_aim(camera, arrival)
	var others_first: Node = ground.get_child(0)
	var helper: Node = Ground.add_to(world)
	if helper == null:
		check("a scene whose ground has chunks gets the helper", false)
		world.free()
		get_viewport().canvas_transform = kept_canvas
		Settings.set_value("camera_zoom", zoom_was)
		return
	var at_arrival: Vector2i = Ground.chunk_of(ground.local_to_map(arrival), size)
	var made_first: int = int(helper.call("made_count"))
	var layers: Array = helper.call("chunk_layers")
	var first_layer: TileMapLayer = layers[0] if not layers.is_empty() else null
	check("as the area arrives the ground is switched off and the arrival's chunk is made at once - %d of %d, not all"
		% [made_first, helper.call("chunk_count")],
		not ground.enabled and made_first >= 1 and made_first < int(helper.call("chunk_count"))
		and _chunk_made(helper, at_arrival), [ground.enabled, made_first])
	check("  a chunk is the ground's tile set and drawing, ahead of the ground's other children (under its scorch marks)",
		first_layer != null and first_layer.tile_set == ground.tile_set and first_layer.get_parent() == ground
		and first_layer.get_index() == 0 and others_first.get_index() == made_first
		and first_layer.z_index == 0 and first_layer.texture_filter == ground.texture_filter
		and first_layer.light_mask == ground.light_mask and first_layer.collision_enabled == ground.collision_enabled)
	check("  and it looks again just before every frame is drawn",
		RenderingServer.frame_pre_draw.is_connected(Callable(helper, "_on_pre_draw")))
	# A jump: the view on the chunk furthest from the arrival, before its turn.
	var far: Vector2i = at_arrival
	for i in range(0, ranges.size(), 4):
		var key := Vector2i(ranges[i], ranges[i + 1])
		if Vector2(key - at_arrival).length() > Vector2(far - at_arrival).length():
			far = key
	var far_middle: Vector2 = ground.to_global(ground.map_to_local(far * size + Vector2i(size / 2, size / 2)))
	var far_waiting: bool = not _chunk_made(helper, far)
	_aim(camera, far_middle)
	helper.call("_on_pre_draw")
	check("  a jump to the far end is looked at before the frame is drawn: its chunk made then, not in its turn",
		far_waiting and _chunk_made(helper, far), [far_waiting, _chunk_made(helper, far)])
	_aim(camera, arrival)
	var frames: int = 0
	while int(helper.call("made_count")) < int(helper.call("chunk_count")) and frames < 400:
		await get_tree().process_frame
		frames += 1
	await get_tree().process_frame
	check("the rest come a few a frame - all %d over %d frames - and then it rests"
		% [helper.call("chunk_count"), frames],
		int(helper.call("made_count")) == int(helper.call("chunk_count")) and frames >= 3
		and not helper.is_processing() and (helper.get("_data") as PackedByteArray).is_empty(), frames)
	var counted: int = 0
	var differ: int = 0
	for layer: TileMapLayer in helper.call("chunk_layers"):
		for cell in layer.get_used_cells():
			counted += 1
			if layer.get_cell_atlas_coords(cell) != ground.get_cell_atlas_coords(cell) \
					or layer.get_cell_source_id(cell) != ground.get_cell_source_id(cell):
				differ += 1
	check("  the chunks hold the ground's cells exactly - %d of %d, each the same tile - and the ground keeps all of its own"
		% [counted, cells_total], counted == cells_total and differ == 0
		and ground.get_used_cells().size() == cells_total, [counted, differ])
	# An edge tile still stops feet, from its chunk.
	var edge: Vector2i = Vector2i(-1, -1)
	for cell in ground.get_used_cells_by_id(1, Vector2i(1, 0)):
		edge = cell
		break
	var solid: bool = false
	if edge != Vector2i(-1, -1):
		await get_tree().physics_frame
		await get_tree().physics_frame
		var query := PhysicsPointQueryParameters2D.new()
		query.position = ground.to_global(ground.map_to_local(edge) + Vector2(0, -7))
		query.collision_mask = 1
		for hit in get_viewport().world_2d.direct_space_state.intersect_point(query, 8):
			var by: Object = hit.get("collider")
			solid = solid or (by is TileMapLayer and by != ground and (by as Node).get_parent() == ground)
	check("  an edge tile still stops feet - its chunk's, the ground's switched off", edge != Vector2i(-1, -1) and solid,
		[edge, solid])
	camera.free()
	world.free()
	get_viewport().canvas_transform = kept_canvas
	Settings.set_value("camera_zoom", zoom_was)

	# ---- what is left alone -----------------------------------------------------------
	var stale := TileMapLayer.new()
	stale.tile_set = load("res://scene/world/underground.tres")
	stale.set_cell(Vector2i(3, 3), 1, Vector2i(1, 1))
	stale.set_meta(Ground.RANGES_META, PackedInt32Array([0, 0, 2, 26]))
	stale.name = "ground"
	var bare := Node2D.new()
	bare.add_child(stale)
	add_child(bare)
	check("a ground whose ranges no longer fit its cells (edited since it was built) is left as it is",
		Ground.add_to(bare) == null and stale.enabled)
	stale.remove_meta(Ground.RANGES_META)
	check("  and an area whose ground has no chunks gets no helper", Ground.add_to(bare) == null)
	bare.free()
	check("AreaRegistry gives every area one as it arrives, and the backdrop does not count a chunk twice",
		_func_body(_code_src("res://src/systems/arearegistry.gd"), "func _on_scene_changed(").contains("GroundChunks.add_to(scene)")
		and _code_src("res://src/world/mapbackdrop.gd").contains("layer.has_meta(&\"ground_chunk\")"))
	await get_tree().process_frame
	print("  (the Big Field's floor in chunks: done)")


func _strays(data: PackedByteArray, ranges: PackedInt32Array, size: int) -> int:
	"""Cells in a range that are not in that range's chunk."""
	const Ground := preload("res://src/world/groundchunks.gd")
	var strays: int = 0
	for i in range(0, ranges.size(), 4):
		var key := Vector2i(ranges[i], ranges[i + 1])
		for at in range(ranges[i + 2], ranges[i + 3], 12):
			if Ground.chunk_of(Vector2i(data.decode_s16(at), data.decode_s16(at + 2)), size) != key:
				strays += 1
	return strays


func _chunk_made(helper: Node, key: Vector2i) -> bool:
	return (helper.get("_made") as Dictionary).has(key)
