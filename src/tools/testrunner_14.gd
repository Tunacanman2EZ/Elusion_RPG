# testrunner_14.gd - part 14 of the suite (testrunner.gd says how it is
# split; part 13 passed 255 KB): _test_the_big_field_floor_kept_once,
# _test_zooming_walks_no_tree.
extends "res://src/tools/testrunner_13.gd"


# =============================================================================
# THE BIG FIELD'S FLOOR KEPT ONCE (0.176.2)
# =============================================================================
# The owner: "fix floor". The ground's 135,926 cells were kept twice - by the
# chunks that draw them, and by the ground, never drawn, for what reads it:
# 27-33 ms to build as the area loaded, 40-50 to take apart as it was left,
# and its world map picture 21-24 ms more. buildbigfield.gd keeps them once,
# in the ground's meta (groundchunks.gd keep_once()). These hold that it is
# the same floor, read the same way.
func _test_the_big_field_floor_kept_once() -> void:
	section("THE BIG FIELD'S FLOOR KEPT ONCE - in its meta, drawn by its chunks, read through groundchunks.gd (0.176.2)")
	const Ground := preload("res://src/world/groundchunks.gd")
	const Map := preload("res://src/systems/worldmap.gd")
	const Preview := preload("res://src/world/floorpreview.gd")
	const Spawner := preload("res://src/world/gmspawner.gd")

	# ---- the saved Big Field ---------------------------------------------------------
	var area: Node = (load(BIG_FIELD) as PackedScene).instantiate()
	var ground: TileMapLayer = area.get_node("ground")
	var data: PackedByteArray = Ground.cells_of(ground)
	var whole := TileMapLayer.new()
	whole.tile_set = ground.tile_set
	whole.tile_map_data = data
	var cells: int = whole.get_used_cells().size()
	check("the ground holds no cells; its %d are in its meta, with their rectangle %s and chunk ranges that fit"
		% [cells, Ground.used_rect(ground)],
		Ground.kept_once(ground) and ground.get_used_cells().is_empty() and cells > 100000
		and Ground.used_rect(ground) == whole.get_used_rect()
		and Ground.ranges_fit(ground.get_meta(Ground.RANGES_META, PackedInt32Array()), data.size()),
		[ground.get_used_cells().size(), cells])
	var probes: int = 0
	var on_floor: int = 0
	var differ: Array = []
	var span: Rect2i = whole.get_used_rect().grow(2)
	for y in range(span.position.y, span.end.y, 37):
		for x in range(span.position.x, span.end.x, 41):
			var cell := Vector2i(x, y)
			probes += 1
			if whole.get_cell_source_id(cell) != -1:
				on_floor += 1
			if Ground.source_at(ground, cell) != whole.get_cell_source_id(cell):
				differ.append(cell)
	check("  read with no helper yet (source_at()), %d cells across it - %d on the floor - answer as the whole floor does"
		% [probes, on_floor], differ.is_empty() and on_floor > 20 and probes - on_floor > 5, differ.slice(0, 4))
	check("  the ground wears floorpreview.gd, which draws the meta in the editor alone (the same meta name)",
		ground.get_script() == Preview and Preview.CELLS_META == Ground.CELLS_META)

	# ---- its map, baked with it ------------------------------------------------------
	var baked: Dictionary = Map.baked_picture(area)
	# Painted where nothing was baked: the meta read whole.
	var from_meta: Dictionary = Map.picture_of(area, "bigfield")
	Ground.restore(ground)
	check("  restore() gives the layer its cells back, whole, as before it was kept once",
		not Ground.kept_once(ground) and ground.get_used_cells().size() == cells and ground.get_used_rect() == whole.get_used_rect())
	var painted: Dictionary = Map.picture_of(area, "bigfield")
	var same_picture: bool = not baked.is_empty() and not painted.is_empty()
	if same_picture:
		same_picture = baked["origin"] == painted["origin"] and baked["size"] == painted["size"] \
			and baked["tile"] == painted["tile"] and (baked["image"] as Image).get_format() == (painted["image"] as Image).get_format() \
			and (baked["image"] as Image).get_data() == (painted["image"] as Image).get_data()
	var meta_same: bool = not from_meta.is_empty() and not painted.is_empty() and from_meta["origin"] == painted["origin"] \
		and (from_meta["image"] as Image).get_data() == (painted["image"] as Image).get_data()
	check("the world map's picture was baked with the map (%s), and is the one painted from its cells, to the pixel"
		% [baked.get("size", "none")], same_picture, [baked.get("size"), painted.get("size")])
	check("  painted with nothing baked, it reads the floor kept once whole: the same picture", meta_same)
	var build_body: String = _func_body(_code_src("res://src/systems/worldmap.gd"), "func _build(")
	check("  and the map takes it as it is: _build() asks for the baked one before painting",
		build_body.find("baked_picture(scene)") != -1 and build_body.find("baked_picture(scene)") < build_body.find("picture_of(scene, area)"))
	area.free()

	# ---- live, on a small floor kept once -------------------------------------------
	var small := TileMapLayer.new()
	small.name = "ground"
	small.tile_set = load("res://scene/world/underground.tres")
	for k in 400:
		small.set_cell(Vector2i(posmod(k * 37, 301) - 100, posmod(k * 53, 211) - 60), 1, Vector2i(1 + k % 4, 1 + k % 3))
	var truth := TileMapLayer.new()
	truth.tile_set = small.tile_set
	truth.tile_map_data = small.tile_map_data
	Ground.order_by_chunks(small, 16)
	Ground.keep_once(small)
	# A cell painted on it by hand since (the editor): drawn with the rest.
	var by_hand := Vector2i(400, 300)
	small.set_cell(by_hand, 1, Vector2i(2, 2))
	var world := Node2D.new()
	world.add_child(small)
	add_child(world)
	var helper: Node = Ground.add_to(world)
	check("a floor kept once gets its helper, which takes its cells from the meta",
		helper != null and not small.enabled and int(helper.call("chunk_count")) > 1)
	if helper == null:
		truth.free()
		world.free()
		return
	var asked: int = 0
	var wrong: Array = []
	var rect: Rect2i = truth.get_used_rect()
	for y in range(rect.position.y - 1, rect.end.y + 1, 7):
		for x in range(rect.position.x - 1, rect.end.x + 1, 5):
			asked += 1
			if Ground.source_at(small, Vector2i(x, y)) != truth.get_cell_source_id(Vector2i(x, y)):
				wrong.append(Vector2i(x, y))
	check("  through it, %d cells answer as before - each chunk asked is made then" % asked,
		wrong.is_empty() and asked > 1000, wrong.slice(0, 4))
	check("  the cell painted by hand is drawn by a chunk too, and counts",
		Ground.source_at(small, by_hand) == 1 and _chunk_has(helper, by_hand)
		and Ground.used_rect(small) == rect.merge(Rect2i(by_hand, Vector2i.ONE)))
	var put_at := Vector2i(-300, -200)
	Ground.put(small, put_at, 1, Vector2i(3, 1))
	check("  a cell the game puts off its old edge is drawn, read, and widens its rectangle",
		Ground.source_at(small, put_at) == 1 and _chunk_has(helper, put_at)
		and Ground.used_rect(small).has_point(put_at) and Ground.used_rect(small).encloses(rect))
	# What reads the floor asks groundchunks.gd: scorch marks, the GM's spawns.
	var on_cell: Vector2i = truth.get_used_cells()[0]
	var off_cell := Vector2i(rect.end.x + 40, rect.end.y + 40)
	var marks := ScorchMarks.new()
	small.add_child(marks)
	var scorch_right: bool = marks.has_floor(small.to_global(small.map_to_local(on_cell))) \
		and not marks.has_floor(small.to_global(small.map_to_local(off_cell)))
	var spawn_right: bool = Spawner.on_floor(small.to_global(small.map_to_local(on_cell)), [small, null], null) \
		and not Spawner.on_floor(small.to_global(small.map_to_local(off_cell)), [small, null], null)
	check("  a scorch mark burns on it and not off it; the GM's spawns stand on it and not off it",
		scorch_right and spawn_right, [scorch_right, spawn_right])
	check("  and the bullets' edge of the world is its rectangle (BulletZone._floor_rect())",
		_func_body(_code_src("res://src/world/bulletzone.gd"), "func _floor_rect(").contains("GroundChunks.used_rect(ground)"))
	world.free()
	truth.free()

	# ---- ranges that do not fit -------------------------------------------------------
	var stale := TileMapLayer.new()
	stale.name = "ground"
	stale.tile_set = load("res://scene/world/underground.tres")
	stale.set_cell(Vector2i(3, 3), 1, Vector2i(1, 1))
	stale.set_cell(Vector2i(4, 3), 1, Vector2i(2, 1))
	Ground.keep_once(stale)
	stale.set_meta(Ground.RANGES_META, PackedInt32Array([0, 0, 2, 14]))
	var bare := Node2D.new()
	bare.add_child(stale)
	add_child(bare)
	check("a floor kept once whose ranges do not fit gets no helper, and its cells back to draw itself",
		Ground.add_to(bare) == null and stale.enabled and stale.get_used_cells().size() == 2 and not Ground.kept_once(stale))
	bare.free()

	# ---- the builder, the Field's, and the art audit ---------------------------------
	var build: String = _func_body(_code_src("res://src/tools/buildbigfield.gd"), "func build(")
	var cover_at: int = build.find("MapBackdrop.cover(_root)")
	var bake_at: int = build.find("WorldMap.bake(_root, root_name)")
	var keep_at: int = build.find("GroundChunks.keep_once(ground)")
	check("the builder works the backdrop and the map out from the cells, then keeps them once, then dresses the ground for the editor",
		cover_at != -1 and cover_at < bake_at and bake_at < keep_at and keep_at < build.find("ground.set_script(FloorPreview)"))
	check("  the Field's builder keeps its floor as it was",
		_code_src("res://src/tools/buildfield.gd").contains("keep_floor_once = false"))
	const Audit := preload("res://src/tools/atlasaudit.gd")
	var header := PackedByteArray([0, 0])
	var one := PackedByteArray([0, 0, 1, 0, 2, 0, 1, 0, 1, 0, 1, 0, 0, 0])
	check("  the art audit counts a floor kept once: its meta's cells, with the layer's own",
		_code_src("res://src/tools/atlasaudit.gd").contains("\"metadata/chunk_cells\":")
		and Audit._cells_after_header(PackedByteArray(), one) == one
		and Audit._cells_after_header(header, one).size() == 12)
	print("  (the big field's floor kept once: done)")


# =============================================================================
# ZOOMING WALKS NO TREE (0.176.3)
# =============================================================================
# The owner: "zooming in and out takes a large cost". Each notch walked the
# whole tree for its cameras - 10-17 ms in the Big Field (zz/zoomcost.gd).
# Settings keeps every camera as it arrives instead.
func _test_zooming_walks_no_tree() -> void:
	section("ZOOMING WALKS NO TREE - the cameras kept as they arrive, a notch reaches each (0.176.3)")
	var was: float = float(Settings.get_value("camera_zoom"))
	var sharp_was: bool = bool(Settings.get_value("sharp_pixels"))
	Settings.set_value("sharp_pixels", false)
	Settings.set_value("camera_zoom", 3.0)
	var holder := Node2D.new()
	add_child(holder)
	var camera := Camera2D.new()
	holder.add_child(camera)
	var inner := SubViewport.new()
	holder.add_child(inner)
	var deep := Camera2D.new()
	inner.add_child(deep)
	var kept: Array[Camera2D] = Settings.cameras()
	check("a camera arriving anywhere - in a viewport of its own too - is known, and takes the zoom as it comes",
		kept.has(camera) and kept.has(deep) and is_equal_approx(camera.zoom.x, 3.0) and is_equal_approx(deep.zoom.x, 3.0))
	Settings.set_value("camera_zoom", 2.0)
	var moved: bool = is_equal_approx(camera.zoom.x, 2.0) and is_equal_approx(deep.zoom.x, 2.0)
	var out := Camera2D.new()
	holder.add_child(out)
	holder.remove_child(out)
	Settings.set_value("camera_zoom", 1.5)
	var gone_id: int = deep.get_instance_id()
	inner.free()
	Settings.set_value("camera_zoom", 2.5)
	check("  a notch reaches every camera in the tree; one taken out is left alone; one freed is forgotten",
		moved and is_equal_approx(camera.zoom.x, 2.5) and is_equal_approx(out.zoom.x, 2.0)
		and not Settings.cameras().has(out) and not Settings._cameras.has(gone_id), [camera.zoom.x, out.zoom.x])
	out.free()
	holder.free()
	Settings.set_value("camera_zoom", was)
	Settings.set_value("sharp_pixels", sharp_was)
	check("  and no notch walks the tree for them (find_children cost 10-17 ms in the Big Field)",
		not _func_body(_code_src("res://src/systems/settings.gd"), "func _apply_camera_zoom_everywhere(").contains("find_children")
		and not _func_body(_code_src("res://src/systems/settings.gd"), "func cameras(").contains("find_children"))
	print("  (zooming walks no tree: done)")


func _chunk_has(helper: Node, cell: Vector2i) -> bool:
	"""Whether a chunk the helper has made draws `cell`."""
	for layer: TileMapLayer in helper.call("chunk_layers"):
		if layer.get_cell_source_id(cell) != -1:
			return true
	return false
