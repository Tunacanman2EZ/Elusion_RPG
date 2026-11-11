# testrunner_11.gd - part 11 of the suite (testrunner.gd says how it is
# split; part 10 passed 250 KB): _test_the_floor_comes_in_chunks,
# _test_the_map_draws_monsters_when_they_move, _test_the_readout_panel,
# _test_the_readout_uncaps.
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
	@warning_ignore("integer_division")
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
	@warning_ignore("integer_division")
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


# =============================================================================
# THE MAP'S MONSTERS, GATHERED OVER FRAMES (0.135.8)
# =============================================================================
# The owner's readout with the map open over the Big Field at 16x: 17 fps,
# scripts 52-57 ms a frame - every monster looked up and drawn every frame.
func _test_the_map_draws_monsters_when_they_move() -> void:
	section("THE MAP'S MONSTERS - gathered a slice a frame, drawn again only where they moved (0.135.8)")
	const MapScript := preload("res://src/ui/menus/mapscreen.gd")
	const AREA := "zz_suite_monster_map"
	WorldMap._terrain[AREA] = {"image": Image.create_empty(40, 20, false, Image.FORMAT_RGBA8),
		"origin": Vector2i.ZERO, "size": Vector2i(40, 20), "tile": Vector2i(16, 16)}
	var seen := PackedByteArray()
	seen.resize(100)
	seen.fill(255)
	# The first tile is not explored.
	seen[0] = 254
	WorldMap._seen[AREA] = seen
	var map: Control = (load("res://scene/ui/menus/mapscreen.tscn") as PackedScene).instantiate()
	add_child(map)
	await get_tree().process_frame
	map.set("_area", AREA)
	(map.get_node("%mapview") as Control).size = Vector2(400, 300)
	map.call("_layout")
	map.set("_pass_wait", 0.0)
	map.call("_gather_monsters", MapScript.GATHER_ALL_MS)
	var before: int = int(map.call("dots_drawn"))
	var box := Node2D.new()
	add_child(box)
	var packed: PackedScene = load("res://scene/enemy/firesprite.tscn")
	var monsters: Array = []
	for k in 40:
		var one: Node2D = packed.instantiate()
		one.process_mode = Node.PROCESS_MODE_DISABLED
		one.position = Vector2(40 + (k % 10) * 60, 40 + floori(k / 10.0) * 60)
		box.add_child(one)
		monsters.append(one)
	var fogged: Node2D = packed.instantiate()
	fogged.process_mode = Node.PROCESS_MODE_DISABLED
	fogged.position = Vector2(8, 8)
	box.add_child(fogged)
	var layer: Control = map.get("monster_layer")
	var markers: Control = map.get_node("%mapmarkers")
	map.set("_pass_wait", 0.0)
	map.call("_gather_monsters", MapScript.GATHER_ALL_MS)
	check("every monster on explored ground is a dot - 40 more - and none through the fog",
		int(map.call("dots_drawn")) == before + 40, [before, map.call("dots_drawn")])
	var map_src: String = _code_src("res://src/ui/menus/mapscreen.gd")
	check("  on a layer of their own under the pins, in %d regions; the pins' layer, drawn every frame, draws none"
		% (MapScript.MONSTER_REGIONS * MapScript.MONSTER_REGIONS),
		layer != null and layer.get_parent() == markers.get_parent() and layer.get_index() < markers.get_index()
		and layer.get_child_count() == MapScript.MONSTER_REGIONS * MapScript.MONSTER_REGIONS
		and not _func_body(map_src, "func _draw_markers(").contains("_draw_monsters"))
	# A slice a frame: with no time left a pass stops at each 32 and goes on next frame.
	var total: int = get_tree().get_nodes_in_group(&"enemies").size()
	map.set("_pass_wait", 0.0)
	var calls: int = 1
	var first_stop: bool = not bool(map.call("_gather_monsters", 0.0))
	var stopped_at: int = int(map.get("_pass_at"))
	while not bool(map.call("_gather_monsters", 0.0)) and calls < 100:
		calls += 1
	calls += 1
	check("  gathered a slice at a time: with no time to spare, %d monsters over %d frames, 32 a frame"
		% [total, calls], first_stop and stopped_at == 32 and calls == ceili(total / 32.0), [stopped_at, calls])
	check("  nothing moved: not one region drawn again", int(map.get("regions_redrawn")) == 0,
		map.get("regions_redrawn"))
	(monsters[0] as Node2D).position += Vector2(12, 0)
	map.set("_pass_wait", 0.0)
	map.call("_gather_monsters", MapScript.GATHER_ALL_MS)
	check("  one moved: only its region drawn again", int(map.get("regions_redrawn")) == 1, map.get("regions_redrawn"))
	# One freed between two slices is passed over.
	map.set("_pass_wait", 0.0)
	map.call("_gather_monsters", 0.0)
	(monsters[39] as Node).free()
	while not bool(map.call("_gather_monsters", 0.0)):
		pass
	check("  one freed in the middle of a pass is passed over, not drawn", int(map.call("dots_drawn")) == before + 39,
		map.call("dots_drawn"))
	var key: Control = map.get("key_panel")
	key.visible = true
	map.set("_pass_wait", 0.0)
	map.call("_gather_monsters", MapScript.GATHER_ALL_MS)
	check("  and the key counts what the pass found", (map.get("key_total") as Label).text == str(before + 39),
		(map.get("key_total") as Label).text)
	box.free()
	map.free()
	WorldMap._terrain.erase(AREA)
	WorldMap._seen.erase(AREA)
	await get_tree().process_frame
	print("  (the map's monsters gathered over frames: done)")


# =============================================================================
# THE READOUT, REMADE AS A PANEL (0.136.0)
# =============================================================================
# The owner: "can we remake the entire screen for read out improve it", then
# "build it" from readout_mock.png.
func _test_the_readout_panel() -> void:
	section("THE READOUT AS A PANEL - big numbers, a graph, where the frame goes, the world, spikes, Copy (0.136.0)")
	const PanelScript := preload("res://src/systems/perfpanel.gd")
	var shown_before: bool = PerfOverlay.is_shown()
	PerfOverlay.set_shown(false)
	PerfOverlay.set_shown(true)
	var panel: Control = PerfOverlay.get_node_or_null("panel")
	check("switched on, the panel is drawn and the old text is kept but not shown",
		panel != null and panel.is_visible_in_tree() and not PerfOverlay._label.visible)
	var now: int = Time.get_ticks_msec()
	var plain := {"ms": 16.0, "held": false, "fps": 60.0, "scripts": 6.0, "drawing": 1.0,
		"physics": 2.0, "worst_tick": 1.0, "ticks": 2, "nodes": 0, "area": "bigfield", "at": now}
	for i in 10:
		PerfOverlay.push_sample(plain.duplicate())
	var waits := plain.duplicate()
	waits["ms"] = 40.0
	waits["at"] = now - 3000
	PerfOverlay.push_sample(waits)
	var busy := plain.duplicate()
	busy["ms"] = 30.0
	busy["scripts"] = 25.0
	busy["nodes"] = 39
	PerfOverlay.push_sample(busy)
	PerfOverlay.flush_samples()
	var frames: PackedFloat32Array = PerfOverlay.graph_frames()
	check("every counted frame goes on the graph, oldest first - the last two the hitches",
		frames.size() >= 12 and is_equal_approx(frames[frames.size() - 1], 30.0)
		and is_equal_approx(frames[frames.size() - 2], 40.0), frames.slice(frames.size() - 3))
	var split: Dictionary = PerfOverlay.split_now()
	var parts: float = 0.0
	for part in PanelScript.PARTS:
		parts += float(split.get(part, 0.0))
	check("  where the frame goes: physics, scripts, drawing and waiting add up to the frame, on average",
		is_equal_approx(snappedf(parts, 0.001), snappedf(float(split.get("ms", -1.0)), 0.001))
		and float(split.get("waiting", -1.0)) >= 0.0, split)
	var data: Dictionary = PerfOverlay.panel_data(now)
	var spikes: Array = data["spikes"]
	check("  a spike says its cause by its part's colour - scripts for the busy one, waiting for the other",
		spikes.size() == 2 and str(spikes[0]["kind"]) == "scripts" and str(spikes[0]["nodes"]) == "+39 nodes"
		and str(spikes[1]["kind"]) == "waiting" and str((data["worst_spike"] as Dictionary)["ago"]).begins_with("worst"),
		spikes)
	check("  and the text says what waiting is: the screen's refresh, the driver or another program",
		PerfOverlay.spike_text(PerfOverlay._spikes[1], now).contains("the screen's refresh, the graphics driver or another program"))
	check("green within the budget, amber over it, red past a hitch",
		PanelScript.tone(16.0) == PanelScript.GOOD and PanelScript.tone(20.0) == PanelScript.WARN and PanelScript.tone(30.0) == PanelScript.BAD)
	check("  the world in a grid of eleven, the title says the area you are in and the cap",
		(data["world"] as Array).size() == 11 and str(data["title"]).contains(PerfOverlay._cap_short())
		and str(data["title"]).begins_with(AreaRegistry.display_name(AreaRegistry.current_area_id())), data["title"])
	PerfOverlay._accum = PerfOverlay.SAMPLE_INTERVAL
	PerfOverlay._process(0.016)
	var view: Vector2 = Vector2(1280, 720)
	check("  it stays on the screen's left half, top to bottom inside it: %s" % [panel.size],
		panel.position.x + panel.size.x <= view.x * 0.5 and panel.position.y + panel.size.y <= view.y, panel.size)
	var copied: Array = []
	panel.set("copy_to", copied.append)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	panel.call("_on_copy_input", click)
	check("Copy puts the whole readout's text on the clipboard, and says Copied",
		copied.size() == 1 and str(copied[0]) == PerfOverlay.readout() and str(copied[0]).contains("hitches")
		and str(panel.get("_copy_word")) == "Copied", copied.size())
	panel.set("copy_to", DisplayServer.clipboard_set)
	PerfOverlay.set_shown(false)
	if shown_before:
		PerfOverlay.set_shown(true)
	print("  (the readout as a panel: done)")


func _test_the_readout_uncaps() -> void:
	section("UNCAP - V-Sync and the frame cap off while the readout is open, nothing saved (0.137.0)")
	# The owner, after "explain": "if you think its a good idea lets go for it".
	var cap_was: int = Engine.max_fps
	var frame_cap_was: Variant = Settings.get_value("frame_cap")
	var vsync_was: Variant = Settings.get_value("vsync")
	Settings.set_uncapped(true)
	check("uncapped, nothing caps the frame rate - and the player's own settings are left as saved",
		Settings.uncapped and Engine.max_fps == 0 and Settings.get_value("frame_cap") == frame_cap_was
		and Settings.get_value("vsync") == vsync_was, Engine.max_fps)
	var focused_was: bool = Settings._focused
	Settings._focused = false
	Settings._apply_fps_cap()
	var held: int = Engine.max_fps
	Settings._focused = focused_was
	Settings._apply_fps_cap()
	check("  but a game behind another window is still held, as ever",
		held == (Settings.BACKGROUND_FPS if bool(Settings.get_value("background_fps_limit")) else 0), held)
	var settings_src: String = _code_src("res://src/systems/settings.gd")
	check("  V-Sync off while it lasts - and choosing V-Sync in Options meanwhile does not turn it back on",
		_func_body(settings_src, "func set_uncapped(").contains("DisplayServer.VSYNC_DISABLED if on else")
		and settings_src.contains("DisplayServer.VSYNC_DISABLED if uncapped else vsync_mode_for(str(value))"))
	Settings.set_uncapped(false)
	check("switched back, the frame rate is capped as it was", not Settings.uncapped and Engine.max_fps == cap_was,
		[Engine.max_fps, cap_was])
	var shown_before: bool = PerfOverlay.is_shown()
	PerfOverlay.set_shown(false)
	PerfOverlay.set_shown(true)
	var panel: Control = PerfOverlay.get_node("panel")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	panel.call("_on_uncap_input", click)
	check("the readout's Uncap switches it on, and its title says so",
		Settings.uncapped and PerfOverlay._cap_short() == "uncapped to test", PerfOverlay._cap_short())
	PerfOverlay.set_shown(false)
	check("  closing the readout always puts it back", not Settings.uncapped and Engine.max_fps == cap_was)
	if shown_before:
		PerfOverlay.set_shown(true)
	print("  (uncap: done)")


func _test_a_crowd_goes_in_turns() -> void:
	section("A CROWD GOES IN TURNS - deaths' bursts and frees on a budget a tick, the rest a tick or two on (0.137.1)")
	# The owner's 16x readout: a 22.9 ms worst physics tick. A blow killing
	# forty made forty bursts and freed forty in one tick.
	var world := Node2D.new()
	world.y_sort_enabled = true
	add_child(world)
	var packed := load("res://scene/enemy/firesprite.tscn") as PackedScene
	var crowd: Array = []
	for i in 40:
		var e: BaseEnemy = packed.instantiate()
		e.position = Vector2(-61000 + (i % 8) * 40, -61000 + floorf(i / 8.0) * 40)
		world.add_child(e)
		crowd.append(e)
	var deaths: Array = [0]
	for e in crowd:
		(e as BaseEnemy).died.connect(func() -> void: deaths[0] += 1)
	await get_tree().physics_frame
	await get_tree().physics_frame
	for e in crowd:
		(e as BaseEnemy).take_damage(100000, 0)
	var gone_now: int = crowd.filter(func(e: Node) -> bool: return e.is_queued_for_deletion()).size()
	var waiting: Array = crowd.filter(func(e: Node) -> bool: return not e.is_queued_for_deletion())
	check("forty killed in one tick: every death counted at once (died, the kill report, the slot)",
		deaths[0] == 40, deaths[0])
	check("  but only some go that tick - the rest wait their turn",
		gone_now >= 1 and gone_now < 40 and BaseEnemy.leaving_count() == waiting.size(),
		[gone_now, BaseEnemy.leaving_count()])
	var still: bool = not waiting.is_empty()
	for e in waiting:
		var m := e as BaseEnemy
		var bar: CanvasItem = m.get_node_or_null("healthbar") as CanvasItem
		still = still and m.visible and not m.is_in_group(&"enemies") and m._dying \
			and not m.is_physics_processing() and (bar == null or not bar.visible)
	check("  one waiting stands where it fell - out of \"enemies\", its bar hidden, nothing of it running",
		still)
	var last: BaseEnemy = waiting[waiting.size() - 1] if not waiting.is_empty() else null
	var sprite: AnimatedSprite2D = last.get_node_or_null("animatedsprite2d") as AnimatedSprite2D if last != null else null
	var timer: Timer = last.get_node_or_null("attacktimer") as Timer if last != null else null
	check("  nothing aims at it, its frame holds for the burst, and it attacks no more",
		last != null and not last.can_be_aimed_at() and sprite != null and not sprite.is_playing()
		and (timer == null or timer.is_stopped()) and not last.is_attacking)
	var ticks: int = 0
	while BaseEnemy.leaving_count() > 0 and ticks < 40:
		await get_tree().physics_frame
		ticks += 1
	await get_tree().process_frame
	var bursts: int = world.get_children().filter(func(c: Node) -> bool: return c is DeathBurst).size()
	var left: int = crowd.filter(func(e: Variant) -> bool: return is_instance_valid(e)).size()
	check("  every one gone a few ticks on, each with its burst",
		left == 0 and bursts == 40 and ticks <= 8, [left, bursts, ticks])
	var lone: BaseEnemy = packed.instantiate()
	lone.position = Vector2(-60000, -60000)
	world.add_child(lone)
	await get_tree().physics_frame
	lone.take_damage(100000, 0)
	check("one death alone goes at once, as before", lone.is_queued_for_deletion() and BaseEnemy.leaving_count() == 0)
	var src: String = _code_src("res://src/enemies/baseenemy.gd")
	check("both deaths - this game's and a mirror's - leave through the budget",
		_func_body(src, "func _die(").contains("_leave_world(burst)")
		and _func_body(src, "func net_vanish(").contains("_leave_world(burst)")
		and not _func_body(src, "func _die(").contains("queue_free()"))
	world.free()
	print("  (a crowd goes in turns: done)")


func _test_the_readout_back_from_another_window() -> void:
	section("THE READOUT BACK FROM ANOTHER WINDOW - the background's last frame and its fps are not counted (0.137.2)")
	# The owner's readout: "158 ms 1 s ago - waiting 149.9 ms", fps "worst
	# 15" - the background rate - with nothing happening in the game.
	var shown_before: bool = PerfOverlay.is_shown()
	PerfOverlay.set_shown(false)
	PerfOverlay.set_shown(true)
	var clock: Array = [100000]
	var frame := func(ms: float, held_now: bool, fps: float) -> void:
		clock[0] += int(ms)
		var at: int = int(clock[0])
		PerfOverlay.push_sample({"ms": ms, "held": PerfOverlay.held_for_frame(held_now, at), "fps": fps,
			"physics": 1.0, "worst_tick": 1.0, "ticks": 1, "scripts": 2.0, "drawing": 1.0,
			"nodes": 0, "area": "bigfield", "at": at})
	for k in 120:
		frame.call(16.0, false, 60.0)
	for k in 30:
		frame.call(66.7, true, 15.0)
	# Back: the frame that ends now began in the background - and the window
	# switch made it long - and the monitor still says 15 for a while.
	frame.call(158.0, false, 15.0)
	for k in 150:
		frame.call(16.0, false, 15.0 if k < 100 else 60.0)
	PerfOverlay.flush_samples()
	check("the frame the game comes back in is the background's - no spike, no worst frame",
		PerfOverlay._hitches == 0 and PerfOverlay._worst_frame_ms < 25.0,
		[PerfOverlay._hitches, PerfOverlay._worst_frame_ms])
	check("  and the fps monitor's second of the background is no worst fps", is_equal_approx(PerfOverlay._worst_fps, 60.0),
		PerfOverlay._worst_fps)
	for k in 60:
		frame.call(16.0, false, 60.0)
	frame.call(40.0, false, 50.0)
	for k in 6:
		frame.call(16.0, false, 60.0)
	PerfOverlay.flush_samples()
	check("  but a real slow frame afterwards still counts, and its fps", PerfOverlay._hitches == 1
		and is_equal_approx(PerfOverlay._worst_fps, 50.0), [PerfOverlay._hitches, PerfOverlay._worst_fps])
	check("  each frame judged by whether it began held, in the readout's own frame",
		_func_body(_code_src("res://src/systems/perfoverlay.gd"), "func _process(").contains("held_for_frame(Settings.held_reason()"))
	PerfOverlay.set_shown(false)
	if shown_before:
		PerfOverlay.set_shown(true)
	print("  (back from another window: done)")


func _test_the_town_floor_in_chunks() -> void:
	section("THE TOWN'S FLOOR AND WATER IN CHUNKS - for low-end phones, the same picture (0.137.3)")
	# The owner: "chunking its important everything is fast so it works on
	# low end phones".
	const Ground := preload("res://src/world/groundchunks.gd")
	var town: Node = (load("res://scene/elusion.tscn") as PackedScene).instantiate()
	var fits: Array = []
	for layer_name in [&"ground", &"water"]:
		var layer: TileMapLayer = town.get_node(NodePath(layer_name))
		var ranges: PackedInt32Array = layer.get_meta(Ground.RANGES_META, PackedInt32Array())
		var size: int = int(layer.get_meta(Ground.SIZE_META, 0))
		if size != Ground.CHUNK_CELLS_SMALL or not Ground.ranges_fit(ranges, layer.tile_map_data.size()) \
				or _strays(layer.tile_map_data, ranges, size) != 0:
			fits.append(layer_name)
	check("the town's ground and water keep their chunks (%d cells a side) and every cell is in its own" % Ground.CHUNK_CELLS_SMALL
		+ " - painted since? open scene/elusion.tscn, File > Run src/tools/chunkfloor.gd, save", fits.is_empty(), fits)
	# THE BOSS ARENA TOO (0.137.3), painted by hand (chunkfloor.gd after). NOT
	# THE CROWNED'S ROOM: its lava phase takes cells out of the ground and puts
	# them back (crownedphases.gd _take(), _give_back()), and an edit to a
	# ground in chunks never reaches the chunks that draw it.
	var arena: Node = (load("res://scene/bossarena.tscn") as PackedScene).instantiate()
	var arena_floor: TileMapLayer = arena.get_node("ground")
	var arena_ranges: PackedInt32Array = arena_floor.get_meta(Ground.RANGES_META, PackedInt32Array())
	var arena_fits: bool = int(arena_floor.get_meta(Ground.SIZE_META, 0)) == Ground.CHUNK_CELLS_SMALL \
		and Ground.ranges_fit(arena_ranges, arena_floor.tile_map_data.size()) \
		and _strays(arena_floor.tile_map_data, arena_ranges, Ground.CHUNK_CELLS_SMALL) == 0
	arena.free()
	var crowned: Node = (load("res://scene/boss.tscn") as PackedScene).instantiate()
	var crowned_whole: bool = not (crowned.get_node("ground") as TileMapLayer).has_meta(Ground.RANGES_META)
	crowned.free()
	check("  and the Boss Arena's floor, every cell in its own chunk - but not the Crowned's room, whose lava edits its floor",
		arena_fits and crowned_whole and _code_src("res://src/world/crowned/crownedphases.gd").contains("ground.erase_cell("),
		[arena_fits, crowned_whole])
	var ground: TileMapLayer = town.get_node("ground")
	var water: TileMapLayer = town.get_node("water")
	var tints: Array = [ground.modulate, water.modulate]
	var cells_of := func(layer: TileMapLayer) -> Array:
		var out: Array = []
		for cell in layer.get_used_cells():
			out.append([cell, layer.get_cell_source_id(cell), layer.get_cell_atlas_coords(cell)])
		return out
	var whole: Array = [cells_of.call(ground), cells_of.call(water)]
	for list in whole:
		(list as Array).sort()
	var hud: Node = town.get_node_or_null("hudcontrol")
	if hud != null:
		town.remove_child(hud)
		hud.free()
	var kept_canvas: Transform2D = get_viewport().canvas_transform
	var camera := Camera2D.new()
	town.add_child(camera)
	add_child(town)
	camera.make_current()
	_aim(camera, (town.get_node("playerspawn") as Node2D).global_position)
	var first: Node = Ground.add_to(town)
	var helpers: Array = [town.get_node_or_null(Ground.NODE_NAME), town.get_node_or_null("%s_water" % Ground.NODE_NAME)]
	check("as the town arrives it gets a helper for each, the ground's first",
		first != null and first == helpers[0] and helpers[1] != null and not ground.enabled and not water.enabled)
	var frames: int = 0
	while frames < 200 and (helpers[0] == null or helpers[1] == null
			or int(helpers[0].call("made_count")) < int(helpers[0].call("chunk_count"))
			or int(helpers[1].call("made_count")) < int(helpers[1].call("chunk_count"))):
		await get_tree().process_frame
		frames += 1
	var same: bool = helpers[0] != null and helpers[1] != null
	var untinted: bool = same
	for i in 2:
		if helpers[i] == null:
			continue
		var cells: Array = []
		for layer: TileMapLayer in helpers[i].call("chunk_layers"):
			cells.append_array(cells_of.call(layer))
			untinted = untinted and layer.modulate == Color.WHITE
		cells.sort()
		same = same and cells == whole[i]
	check("  all made a few frames on (%d), the same cells as before" % frames, same and frames < 200)
	check("  a chunk is tinted by its layer, not twice over (the town's floor is 0.41 grey)",
		untinted and ground.modulate == tints[0] and water.modulate == tints[1]
		and not Ground.COPIED.has("modulate"))
	town.free()
	get_viewport().canvas_transform = kept_canvas
	print("  (the town's floor in chunks: done)")


func _test_the_gm_panel_comes_with_the_area() -> void:
	section("THE GM PANEL BUILT WITH THE AREA, AND A KEY'S WORK NAMED IN THE READOUT (0.137.4)")
	# The owner's readout: one 44 ms spike, "waiting ... not the game's code",
	# +435 nodes - "opened gm panel".
	var was_owner: bool = Api.is_owner
	Api.is_owner = true
	var hud: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	add_child(hud)
	await get_tree().process_frame
	var none_yet: bool = hud.owner_panel == null
	hud.prepare_owner_panel()
	var built: Control = hud.owner_panel
	check("the owner's HUD builds the GM panel when the area asks (none before), hidden",
		none_yet and built != null and built.get_parent() == hud and not built.visible)
	hud._toggle_owner_panel()
	check("  opening it is then only showing it - the same panel", hud.owner_panel == built and built.visible)
	hud._toggle_owner_panel()
	hud.queue_free()
	Api.is_owner = false
	var player_hud: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	add_child(player_hud)
	await get_tree().process_frame
	player_hud.prepare_owner_panel()
	check("  nobody else gets one", player_hud.owner_panel == null)
	player_hud.queue_free()
	Api.is_owner = was_owner
	await get_tree().process_frame
	check("  AreaRegistry asks for it as an area arrives",
		_func_body(_code_src("res://src/systems/arearegistry.gd"), "func _on_scene_changed(").contains("prepare_owner_panel"))

	# ---- the readout names a key or click in a spike -------------------------
	var key := InputEventKey.new()
	key.pressed = true
	var echo := InputEventKey.new()
	echo.pressed = true
	echo.echo = true
	var click := InputEventMouseButton.new()
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT
	check("a key or a click going down is a press; a held key's repeat and a mouse move are not",
		PerfOverlay.is_press(key) and PerfOverlay.is_press(click) and not PerfOverlay.is_press(echo)
		and not PerfOverlay.is_press(InputEventMouseMotion.new()))
	var at: int = Time.get_ticks_msec()
	var keyed := {"ms": 44.0, "physics": 0.4, "worst_tick": 0.3, "ticks": 1, "scripts": 0.2, "drawing": 0.1,
		"nodes": 435, "area": "bigfield", "at": at, "pressed": true}
	var plain: Dictionary = keyed.duplicate()
	plain["pressed"] = false
	check("  a spike with one in it says so, row and panel; one without blames the screen as before",
		PerfOverlay.spike_text(keyed, at).contains("with a key or click in it")
		and str(PerfOverlay._panel_spike(keyed, at)["cause"]).ends_with("after a key or click")
		and PerfOverlay.spike_text(plain, at).contains("not the game's code")
		and not str(PerfOverlay._panel_spike(plain, at)["cause"]).contains("key"))
	check("  and each frame notes whether a press came in it",
		_func_body(_code_src("res://src/systems/perfoverlay.gd"), "func _process(").contains("parts[\"pressed\"] = _press_usec > 0"))
	print("  (the GM panel with the area: done)")


func _test_spikes_drawn_together() -> void:
	section("A BOSS'S SPIKES DRAWN TOGETHER - RINGS, SPARKS AND POOLS (0.137.5)")
	# The owner: "if i have 3 bosses all doing that at once you see the issue".
	# Three bosses' patterns were 500 to 1,100 draw calls a frame (a ring and
	# a CPUParticles2D a spike); spikefx.gd draws the container's rings in one
	# MultiMesh, its sparks in another, and its pools under them.
	const Fx := preload("res://src/projectiles/spikefx.gd")
	var spike_scene := load("res://scene/projectiles/bossprojectile.tscn") as PackedScene
	var world := Node2D.new()
	world.y_sort_enabled = true
	add_child(world)
	var container := Node2D.new()
	container.y_sort_enabled = true
	world.add_child(container)
	var spikes: Array = []
	var spots: Array = [Vector2(-30000, -30000), Vector2(-29900, -30000), Vector2(-29800, -29950), Vector2(-29700, -30050)]
	var elements: Array = [Element.Type.DARK, Element.Type.DARK, Element.Type.DARK, Element.Type.LIGHTNING]
	for i in spots.size():
		var spike: Node2D = spike_scene.instantiate()
		spike.set("element", elements[i])
		spike.set("telegraph_seconds", 30.0)
		container.add_child(spike)
		spike.global_position = spots[i]
		spike.reset_physics_interpolation()
		spikes.append(spike)
	var fx: Node2D = container.get_node_or_null(NodePath(Fx.NODE_NAME)) as Node2D
	var made: int = 0
	for c in container.get_children():
		if c.get_script() == Fx:
			made += 1
	check("the first spike makes the container's spikefx - one, first among its children, at the top of the y-sort",
		fx != null and made == 1 and fx.get_index() == 0 and is_equal_approx(fx.position.y, Fx.SORT_Y), [made, fx])
	check("  each spike warns there (%d), with no _process or _draw of its own" % [fx.call("warning_count") if fx != null else -1],
		fx != null and int(fx.call("warning_count")) == 4
		and spikes.all(func(k): return not (k as Node).is_processing() and not (k as Node).has_method(&"_draw")))
	var dark_a: Material = (spikes[0] as Node).get_node("animatedsprite2d").material
	var dark_b: Material = (spikes[2] as Node).get_node("animatedsprite2d").material
	var spark_tint: Material = (spikes[3] as Node).get_node("animatedsprite2d").material
	check("  dark spikes (no scene of their own) share one tint; lightning has its own",
		dark_a != null and dark_a == dark_b and spark_tint != null and spark_tint != dark_a)
	await get_tree().process_frame
	var rings: MultiMeshInstance2D = fx.get_node("rings") as MultiMeshInstance2D
	var sparks: MultiMeshInstance2D = fx.get_node("sparks") as MultiMeshInstance2D
	var placed: int = 0
	var buf: PackedFloat32Array = fx.get("_ring_buf")
	for i in rings.multimesh.visible_instance_count:
		var origin: Vector2 = fx.to_global(Vector2(buf[i * Fx.RING_STRIDE + 3], buf[i * Fx.RING_STRIDE + 7]))
		for spot in spots:
			if origin.distance_to(spot) < 0.5:
				placed += 1
	check("  the rings are one MultiMesh, an instance a spike where it stands (placed after it was added)",
		rings.multimesh.visible_instance_count == 4 and placed == 4, [rings.multimesh.visible_instance_count, placed])
	check("  both MultiMeshes drawn as written, never blended between buffers; the sparks over everything",
		rings.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF
		and sparks.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF and sparks.z_index == 1)
	var early: bool = spikes.any(func(k): return bool((k as Node).get("_erupting")))
	var gone: Node2D = spike_scene.instantiate()
	gone.set("element", Element.Type.DARK)
	container.add_child(gone)
	var with_it: int = int(fx.call("warning_count"))
	gone.free()
	check("  a spike that goes before it erupts takes its ring with it",
		with_it == 5 and int(fx.call("warning_count")) == 4, [with_it, fx.call("warning_count")])
	# Thirty seconds on: the clock says so.
	fx.set("now", float(fx.get("now")) + 30.5)
	var waited: int = 0
	while int(fx.call("warning_count")) > 0 and waited < 300:
		await get_tree().process_frame
		waited += 1
	check("  on the container's clock the warnings end and the spikes erupt (none before), a burst each",
		not early and int(fx.call("warning_count")) == 0
		and spikes.all(func(k): return bool((k as Node).get("_erupting")))
		and int(fx.call("bursts_alive")) == 4 and sparks.multimesh.visible_instance_count == 4,
		[early, fx.call("warning_count"), fx.call("bursts_alive")])
	var holder: Node = Fx.pool_holder(container, Element.Type.DARK)
	check("  a spike's pool goes under the rings, beside its element's",
		holder != null and holder.get_parent() == fx and holder.get_index() < rings.get_index()
		and Fx.pool_holder(container, Element.Type.DARK) == holder
		and _func_body(_code_src("res://src/projectiles/bossprojectile.gd"), "func _leave_puddle(").contains("SpikeFx.pool_holder("))
	await get_tree().create_timer(1.5).timeout
	check("  the sparks spent, nothing is drawn and the container's clock stops",
		int(fx.call("bursts_alive")) == 0 and sparks.multimesh.visible_instance_count == 0 and not fx.is_processing(),
		[fx.call("bursts_alive"), fx.is_processing()])

	# ---- warming the shaders --------------------------------------------------
	var was_warmed: bool = Fx._warmed
	Fx._warmed = false
	fx.call("warm")
	var layer: Node = fx.get_node_or_null(^"warming")
	var drawn: int = layer.get_child(0).get_child_count() if layer != null and layer.get_child_count() > 0 else 0
	check("warming draws a pool, a tinted spike, a ring and a burst, faint, in a layer of their own",
		layer is CanvasLayer and drawn >= 2 and int(fx.call("warning_count")) == 1 and int(fx.call("bursts_alive")) == 1
		and Fx._warmed, [layer, drawn])
	for k in Fx.WARM_FRAMES + 2:
		await get_tree().process_frame
	check("  for a few frames, then it is gone",
		fx.get_node_or_null(^"warming") == null and int(fx.call("warning_count")) == 0 and sparks.self_modulate.a == 1.0)
	Fx._warmed = was_warmed
	check("  AreaRegistry gives every area its own as the area arrives",
		_func_body(_code_src("res://src/systems/arearegistry.gd"), "func _on_scene_changed(").contains("SpikeFx.add_to(scene)"))
	world.queue_free()
	await get_tree().process_frame
	print("  (a boss's spikes drawn together: done)")


func _test_the_lag_points() -> void:
	section("THE READOUT'S LAG POINTS - WHAT HAPPENED WHEN FRAMES HITCHED (0.138.0)")
	# The owner: "can we upgrade the test to analyze the lag points", then
	# "make markers showing what is great and what needs to be fixed".
	const Lag := preload("res://src/systems/lagtests.gd")
	const Fx := preload("res://src/projectiles/spikefx.gd")
	var was_shown: bool = PerfOverlay.is_shown()
	PerfOverlay.set_shown(false)
	PerfOverlay.mark(&"spikes rise")
	check("a mark is nothing while the readout is off", (PerfOverlay._marks_now as Dictionary).is_empty())
	PerfOverlay.set_shown(true)
	var t: int = Time.get_ticks_usec()
	PerfOverlay.clocked_frame(t)
	PerfOverlay.mark(&"spikes rise", 3)
	PerfOverlay._physics_process(0.0)
	PerfOverlay.mark(&"boss casts")
	var parts: Dictionary = PerfOverlay.clocked_frame(t + 20000)
	check("  a mark belongs to the frame it was made in: set aside at the next frame's first tick",
		parts.get("marks", {}) == {&"spikes rise": 3} and PerfOverlay._marks_now == {&"boss casts": 1}, parts.get("marks"))
	PerfOverlay._marks_now = {}
	PerfOverlay.clocked_frame(t + 30000)
	PerfOverlay.mark(&"pools land")
	var untick: Dictionary = PerfOverlay.clocked_frame(t + 40000)
	check("  and a frame with no tick ends its marks where it ends", untick.get("marks", {}) == {&"pools land": 1},
		untick.get("marks"))

	# ---- counted: the frames with each kind, and those that hitched ----------
	PerfOverlay.set_shown(false)
	PerfOverlay.set_shown(true)
	var at: int = Time.get_ticks_msec() - 100000
	var feed := func(ms: float, marks: Dictionary) -> void:
		at += 17
		PerfOverlay.push_sample({"ms": ms, "held": false, "fps": 60.0, "physics": 0.3, "worst_tick": 0.3, "ticks": 1,
			"scripts": 0.5, "drawing": ms - 1.0, "nodes": 0, "area": "", "at": at, "marks": marks,
			"draws": 4 if not marks.is_empty() else 0, "prims": 0, "vram": 0})
	for i in 100:
		feed.call(40.0 if i == 50 else 16.6, {})
	for i in 10:
		feed.call(40.0 if i < 8 else 16.6, {&"spikes rise": 12})
	for i in 10:
		feed.call(16.6, {&"pools land": 2})
	for i in 10:
		feed.call(40.0 if i < 2 else 16.6, {&"boss casts": 1})
	PerfOverlay.flush_samples()
	var rows: Array = PerfOverlay.lag_rows()
	check("each kind: its frames, those that hitched, and in which part - the likeliest first",
		not rows.is_empty() and rows[0] == ["spikes rise", 10, 8, "drawing"], rows)
	check("  and the frames with nothing marked beside them", PerfOverlay.lag_base() == [100, 1, "drawing"],
		PerfOverlay.lag_base())
	var verdicts: Array = PerfOverlay.verdicts()
	var said: Dictionary = {}
	for v in verdicts:
		said[v[0]] = v[1]
	check("  FIX names the kind far above the rest, and where its time went",
		str(said.get("fix", "")) == "spikes rise: 8 of 10 hitched, mostly drawing", verdicts)
	check("  WATCH the next (boss casts, 2 of 10), never one that did not hitch",
		str(said.get("watch", "")) == "boss casts: 2 of 10 hitched" and not str(verdicts).contains("pools land"), verdicts)
	var marks: Array = PerfOverlay.graph_marks()
	var letters: String = ""
	for m in marks:
		letters += str(m[1])
	check("  the graph marks each hitch with its kind's letter - ? where nothing was marked",
		letters == "?RRRRRRRRCC" and str(marks[1][2]) == "drawing", letters)
	var key: Array = PerfOverlay.graph_key(marks)
	check("  and the key under it says what the letters were, the commonest first",
		not key.is_empty() and key[0][0] == "R" and key[0][1] == "spikes rise" and int(key[0][2]) == 8, key)
	var data: Dictionary = PerfOverlay.panel_data(Time.get_ticks_msec())
	var spike: Dictionary = (data.get("spikes", []) as Array)[0] if not (data.get("spikes", []) as Array).is_empty() else {}
	check("  the panel has them all, and a spike says what happened in its frame",
		(data.get("lag", []) as Array).size() == 3 and data.get("lag_base", []) == [100, 1]
		and (data.get("verdict", []) as Array).size() >= 2 and str(spike.get("marks", "")) == "boss casts ×1 · draws +4",
		[spike.get("marks"), data.get("lag_base")])
	check("  and the copied text has the lag points and the verdicts",
		_func_body(_code_src("res://src/systems/perfoverlay.gd"), "func _process(").contains("lag_rows()")
		and _func_body(_code_src("res://src/systems/perfoverlay.gd"), "func _process(").contains("verdicts()"))
	PerfOverlay.set_shown(false)

	# ---- where the game marks -----------------------------------------------------
	var marked: Array = [
		["res://src/enemies/bossenemy.gd", "func _cast_stalagmites_from_cast(", "boss casts"],
		["res://src/enemies/bossenemy.gd", "func fire_volley(", "boss volleys"],
		["res://src/projectiles/bossprojectile.gd", "func _ready(", "spikes appear"],
		["res://src/projectiles/bossprojectile.gd", "func _erupt(", "spikes rise"],
		["res://src/projectiles/bossprojectile.gd", "func _on_animation_finished(", "spikes go"],
		["res://src/projectiles/acidpuddle.gd", "func _ready(", "pools land"],
		["res://src/enemies/baseenemy.gd", "func _ready(", "monsters appear"],
		["res://src/enemies/baseenemy.gd", "func _die(", "monsters die"],
		["res://src/world/lootbag.gd", "func _ready(", "loot bags"],
		["res://src/projectiles/spikefx.gd", "func warm(", "shaders warm"],
		["res://src/systems/perfoverlay.gd", "func _input(", "key or click"],
	]
	var unmarked: Array = []
	for place in marked:
		if not _func_body(_code_src(place[0]), place[1]).contains("mark(&\"%s\")" % place[2]):
			unmarked.append(place[2])
		if not PerfOverlay.MARK_LETTERS.has(StringName(place[2])):
			unmarked.append(place[2] + " (no letter)")
	check("the game marks its big moments, each with a letter", unmarked.is_empty(), unmarked)

	# ---- the lag tests ------------------------------------------------------------
	var area := Node2D.new()
	add_child(area)
	var fx: Node2D = Fx.of(area)
	var pools: Node = fx.call("puddles_for", Element.Type.FIRE)
	var light := PointLight2D.new()
	get_tree().current_scene.add_child(light)
	var dark := PointLight2D.new()
	dark.enabled = false
	get_tree().current_scene.add_child(dark)
	Lag.set_test("rings", true, get_tree())
	Lag.set_test("pools", true, get_tree())
	Lag.set_test("lights", true, get_tree())
	var hidden: bool = not (fx.get_node("rings") as CanvasItem).visible and (fx.get_node("sparks") as CanvasItem).visible \
		and not (pools as CanvasItem).visible and not light.enabled
	var titled: String = str(PerfOverlay.panel_data(Time.get_ticks_msec()).get("title", ""))
	Lag.set_test("rings", false, get_tree())
	Lag.set_test("pools", false, get_tree())
	Lag.set_test("lights", false, get_tree())
	check("a lag test hides what it says - drawing only - and the readout's title says so",
		hidden and titled.contains("test: rings off, pools off, lights off"), [hidden, titled])
	check("  and off, it is all back as it was (a light that was off stays off)",
		(fx.get_node("rings") as CanvasItem).visible and (pools as CanvasItem).visible and light.enabled
		and not dark.enabled and not Lag.any_on())
	light.free()
	dark.free()
	area.queue_free()
	var was_role: String = Api.role
	Api.role = "owner"
	var gm: Control = (load("res://scene/ui/owner/ownerpanel.tscn") as PackedScene).instantiate() as Control
	add_child(gm)
	await get_tree().process_frame
	var grid: Node = gm.find_child("laggrid", true, false)
	var button: Button = gm.find_child("lagsparksbutton", true, false) as Button
	if button != null:
		button.button_pressed = true
	var strip: Array = gm.call("active_now")
	check("the GM panel's Testing tab has the five under LAG TESTS (the arena's since 0.139.0), toggles in a row; one on is on the strip",
		grid != null and grid.find_children("lag*button", "Button", false, false).size() == 5
		and button != null and button.toggle_mode
		and Lag.hide_sparks and strip.has("Sparks Off"), strip)
	if button != null:
		button.button_pressed = false
	gm.queue_free()
	Api.role = was_role
	Lag.hide_rings = false
	Lag.hide_sparks = false
	Lag.hide_pools = false
	Lag.lights_off = false
	Lag.hide_arena = false
	PerfOverlay.set_shown(was_shown)
	await get_tree().process_frame
	print("  (the readout's lag points: done)")


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


# =============================================================================
# THE LIGHT KEEPER'S ARENA (0.139.0)
# =============================================================================

class ArenaDummy extends CharacterBody2D:
	# A player for the arena's flares: in their group, with the health a
	# flare takes its share of, and a take_damage() that writes it down.
	var taken: Array = []
	var max_hp: int = 1000
	var is_dying: bool = false

	func _init() -> void:
		collision_layer = 4
		collision_mask = 0
		add_to_group(&"player")

	func take_damage(amount: int, element: int = 0) -> void:
		taken.append([amount, element])


func _test_the_light_arena() -> void:
	section("THE LIGHT KEEPER'S ARENA - MIRRORS, FLARES, THE ECLIPSE (0.139.0)")
	# The owner, of the Docs plan "Boss fights: arenas that fight back": "lets
	# build it", and of the mirrors: "Yes, players break them".
	const Arena := preload("res://src/enemies/lightarena.gd")
	const Fx := preload("res://src/projectiles/spikefx.gd")
	const Lag := preload("res://src/systems/lagtests.gd")
	const Hits := preload("res://src/shared/hitsource.gd")

	# THE BULLETS: a mirror cell turns an orb back off its face, a wall ends it.
	var field := BulletField.new()
	add_child(field)
	field.bounds = Rect2(0, 0, 160, 160)
	var grid := PackedByteArray()
	grid.resize(20 * 20)
	for cy in 20:
		grid[cy * 20 + 15] = 1
	for cx in range(2, 12):
		grid[10 * 20 + cx] = BulletField.MIRROR_FIRST + 1
	field.set_walls(grid, Vector2.ZERO, 8.0, Vector2i(20, 20))
	field.set_mirror(1, Vector2(56, 84), Vector2(0, 1))
	field.spawn(Vector2(40, 60), PI * 0.5 + 0.3, 60.0, Color(1, 0.9, 0.5), false, 0.0, 0.0, 6.0, 5, Element.Type.LIGHT)
	var off_it: Array = []
	var curve: float = 0.0
	for n in 30:
		field.step(0.05, Vector2(1.0e6, 1.0e6), 1.0, 0.0, true)
		for k in field.bounces:
			off_it.append(k)
	var turned: Vector2 = field.velocity_of(0) if field.count > 0 else Vector2.ZERO
	curve = field._turn[0] if field.count > 0 else 1.0
	check("an orb reaching a mirror's cell is turned back off its face, once, stays in the air and is drawn white",
		field.count == 1 and off_it == [1] and turned.y < 0.0 and is_equal_approx(turned.length(), 60.0)
		and curve == 0.0 and field._buffer[8] == 1.0 and field._buffer[9] == 1.0 and field._buffer[10] == 1.0,
		[field.count, off_it, turned])
	field.clear()
	field.spawn(Vector2(100, 20), 0.0, 80.0, Color.WHITE)
	field.step(0.05, Vector2(1.0e6, 1.0e6), 1.0, 0.0, true)
	var flying: int = field.count
	for n in 10:
		field.step(0.05, Vector2(1.0e6, 1.0e6), 1.0, 0.0, true)
	check("  a wall still ends one", flying == 1 and field.count == 0, [flying, field.count])
	field.queue_free()

	# THE ARENA, in a world of its own far from everything.
	var origin := Vector2(-40000, -40000)
	var world := Node2D.new()
	world.y_sort_enabled = true
	add_child(world)
	var ground := Node2D.new()
	ground.y_sort_enabled = true
	ground.add_to_group(&"groundeffects")
	world.add_child(ground)
	var zone := BulletZone.new()
	world.add_child(zone)
	zone.set_process(false)
	zone.field.bounds = Rect2(origin - Vector2(352, 224), Vector2(704, 448))
	zone._start_walls()
	zone.build_all_walls()
	var me := ArenaDummy.new()
	world.add_child(me)
	me.global_position = origin + Vector2(60, 120)
	var boss: Node2D = (load("res://scene/enemy/lightboss.tscn") as PackedScene).instantiate()
	boss.position = origin + Vector2(0, -30)
	world.add_child(boss)
	await get_tree().process_frame
	boss.process_mode = Node.PROCESS_MODE_DISABLED
	Arena.everywhere = false
	check("no arena outside the Boss Arena and the Endless", not Arena.wanted(boss))
	Arena.everywhere = true
	boss.set_meta(&"descent_caster", true)
	check("  nor for a Descent's hidden caster", not Arena.wanted(boss))
	boss.remove_meta(&"descent_caster")
	check("  only the Light Keeper's kit has one", bool(BossEnemy.KITS[Element.Type.LIGHT].get("arena", false))
		and BossEnemy.KITS.keys().filter(func(e): return bool(BossEnemy.KITS[e].get("arena", false))).size() == 1)
	boss.call("_keep_arena", 1.0)
	var arena: Node2D = boss.call("arena")
	if arena == null:
		check("the loose Light Keeper makes its arena", false)
		Arena.everywhere = false
		world.queue_free()
		return
	arena.set_process(false)
	var panes: Array = arena.get("panes")
	var named: bool = true
	var marked: bool = true
	for k in panes.size():
		var pane: Node2D = panes[k]
		named = named and pane != null and str(pane.name) == "pane%dp0" % k
		marked = marked and pane != null and pane.is_in_group(&"enemies") and pane.is_in_group(&"levers") \
			and pane.has_meta(&"stress_copy") and not bool(pane.call("can_be_aimed_at"))
	check("the loose Light Keeper makes its arena in the area's effects, named for the levers",
		arena.get_parent() == ground and str(arena.name) == "lightarena0" and arena.is_in_group(Lag.GROUP), arena.name)
	check("  four mirrors, \"pane<k>p<phase>\", in enemies and levers, stress-marked, never aimed at",
		panes.size() == 4 and int(arena.call("standing")) == 4 and named and marked)
	var cells: Array = [0, 0, 0, 0]
	for v in zone._walls:
		if v >= BulletField.MIRROR_FIRST and v < BulletField.MIRROR_FIRST + 4:
			cells[v - BulletField.MIRROR_FIRST] += 1
	check("  each painted into the bullets' walls", cells.all(func(c): return c >= 10), cells)
	var middle: Vector2 = zone.field.bounds.get_center()
	var sends: bool = true
	for k in panes.size():
		var pane: Node2D = panes[k]
		var face: Vector2 = (pane.get("half") as Vector2).orthogonal().normalized()
		var spoke: Vector2 = (pane.global_position - middle).normalized()
		var off: Vector2 = spoke - 2.0 * spoke.dot(face) * face
		sends = sends and off.dot(Arena.PANE_SENDS[k]) > 0.99
	check("  each angled to send a spoke from the middle along the room's side", sends)
	var target: Node2D = panes[0]
	zone.field.spawn(middle, (target.global_position - middle).angle(), 90.0, Color.WHITE)
	var bounced: bool = false
	for n in 60:
		zone.field.step(0.05, Vector2(1.0e6, 1.0e6), 1.0, 0.0, true)
		if zone.field.bounces.has(0):
			bounced = true
			break
	check("  an orb from the middle comes off the first down the room's side",
		bounced and zone.field.velocity_of(zone.field.count - 1).normalized().dot(Vector2(0, 1)) > 0.99)
	zone.field.clear()

	# BREAKING ONE: your blows, or somebody else's game's.
	for n in Arena.PANE_HITS - 1:
		target.call("take_damage", 10.0)
	var held: bool = not bool(target.get("broken")) and int(target.get("hits")) == Arena.PANE_HITS - 1
	target.call("take_damage", 10.0)
	var left: int = 0
	for v in zone._walls:
		if v == BulletField.MIRROR_FIRST:
			left += 1
	check("%d blows break a mirror: its cells open, it is no longer counted standing" % Arena.PANE_HITS,
		held and bool(target.get("broken")) and left == 0 and int(arena.call("standing")) == 3, [held, left])
	(panes[1] as Node).call("follow_pull", false)
	var kept: bool = not bool((panes[1] as Node).get("broken"))
	(panes[1] as Node).call("follow_pull", true)
	check("  another game's break (a lever pull, on) breaks it here too; an off pull does nothing",
		kept and bool((panes[1] as Node).get("broken")))

	# PHASE TWO: every mirror again, and the leader's flares.
	boss.set("hp", int(float(boss.get("max_hp")) * 0.5))
	arena.call("_process", 0.7)
	var regrown: bool = int(arena.call("standing")) == 4 and str(target.name) == "pane0p1" \
		and int(target.get("hits")) == 0
	var flares: Array = arena.get("flares")
	var near: bool = flares.size() == 1 and (flares[0][0] as Vector2).distance_to(me.global_position) <= Arena.FLARE_FURTHEST + 16.0
	check("phase two: every mirror stands again under the phase's name, and the leader throws a flare near each player",
		regrown and near, [regrown, flares])
	flares.clear()
	arena.set("_flare_clock", 99.0)
	arena.call("add_flare", me.global_position)
	arena.call("add_flare", me.global_position + Vector2(200, 0))
	arena.call("_process", Arena.FLARE_SWELL + 0.05)
	Hits.take()
	var share: int = roundi(1000.0 * Arena.FLARE_SHARE)
	check("  a flare flashes after its swell: near it, a share of your health as light; further off, nothing",
		me.taken == [[share, Element.Type.LIGHT]], me.taken)
	flares.clear()
	arena.call("hear", {"h": "flare", "x": me.global_position.x, "y": me.global_position.y})
	arena.call("hear", {"h": "flare", "x": origin.x + Arena.FLARE_REACH + 300.0, "y": origin.y})
	arena.call("hear", {"h": "mirror", "x": me.global_position.x, "y": me.global_position.y})
	check("  a follower makes the leader's flare where it was put - near its boss, and nothing it does not know",
		flares.size() == 1, flares.size())
	flares.clear()

	# PHASE THREE: the eclipse.
	boss.set("hp", int(float(boss.get("max_hp")) * 0.2))
	for n in 4:
		arena.call("_process", 0.5)
	var fx: Node2D = Fx.of(ground)
	var rings: CanvasItem = fx.get("_rings")
	var dark: CanvasItem = arena.get_node("eclipse") as CanvasItem
	var lit: int = int((arena.get("_dark_material") as ShaderMaterial).get_shader_parameter(&"count"))
	check("phase three: the dark falls, lit round the boss, each mirror and each player; the spikes' rings above it",
		is_equal_approx(float(arena.get("eclipse")), 1.0) and dark.visible and lit == 6
		and rings.z_index == Fx.RINGS_LIFTED_Z and not rings.z_as_relative, [arena.get("eclipse"), lit, rings.z_index])
	Lag.set_test("arena", true, get_tree())
	var hidden: bool = not target.visible and not dark.visible and not (arena.get_node("flares") as CanvasItem).visible
	var said: bool = Lag.names_on().has("arena off")
	Lag.set_test("arena", false, get_tree())
	check("  the GM panel's Arena lag test hides it all (and says so), and puts it back",
		hidden and said and target.visible and dark.visible)
	boss.set("hp", int(boss.get("max_hp")))
	for n in 3:
		arena.call("_process", 0.5)
	check("  back to full health, it lifts and the rings go back among the floor",
		float(arena.get("eclipse")) == 0.0 and not dark.visible and rings.z_index == 0 and rings.z_as_relative)

	# GONE WITH ITS BOSS.
	boss.set("_dying", true)
	arena.call("_process", 0.1)
	var painted: int = 0
	for v in zone._walls:
		if v >= BulletField.MIRROR_FIRST:
			painted += 1
	arena.call("_process", Arena.END_SECONDS + 0.1)
	check("its boss falling, every mirror shatters, the bullets' walls are as they were, and it goes",
		int(arena.call("standing")) == 0 and painted == 0 and arena.is_queued_for_deletion(), [painted])

	# AND ON THE WIRE, AND ON THE READOUT.
	var sync_src: String = FileAccess.get_file_as_string("res://src/world/monstersync.gd")
	var apply_body: String = _func_body(sync_src, "func _apply_event(")
	check("the leader's arena hazard (\"la\") reaches a follower's boss (net_arena)",
		apply_body.contains("\"la\":") and apply_body.contains("\"net_arena\""))
	check("  and the readout letters the arena's marks",
		PerfOverlay.MARK_LETTERS.get(&"flares flash") == "F" and PerfOverlay.MARK_LETTERS.get(&"mirrors break") == "X"
		and PerfOverlay.MARK_LETTERS.get(&"eclipse falls") == "E")
	Arena.everywhere = false
	world.queue_free()
	await get_tree().process_frame
	print("  (the Light Keeper's arena: done)")
