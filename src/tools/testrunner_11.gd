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

class RunStub extends Node:
	# The Endless's run, as an arena asks it: its arena floor, and whether a
	# point is on it rather than in the corridor.
	var arena_rect: Rect2 = Rect2(0, 0, 1000, 1000)
	var corridor_rect: Rect2 = Rect2(450, 800, 100, 200)

	func in_arena(at: Vector2) -> bool:
		return arena_rect.has_point(at) and not corridor_rect.has_point(at)


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
	check("  the six elemental bosses' kits each have their arena (Light 0.139.0 ... Fire 0.143.0), the Crowned's none",
		BossEnemy.KITS[Element.Type.LIGHT].get("arena") == &"light" and BossEnemy.KITS[Element.Type.WIND].get("arena") == &"wind"
		and BossEnemy.KITS[Element.Type.WATER].get("arena") == &"water" and BossEnemy.KITS[Element.Type.ICE].get("arena") == &"ice"
		and BossEnemy.KITS[Element.Type.EARTH].get("arena") == &"earth" and BossEnemy.KITS[Element.Type.FIRE].get("arena") == &"fire"
		and BossEnemy.KITS.keys().filter(func(e): return BossEnemy.KITS[e].has("arena")).size() == 6)
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


func _test_the_wind_arena() -> void:
	section("THE WIND BOSS'S ARENA - CROSSWIND, WINDBREAKS, GUSTS, THE TORNADO (0.140.0)")
	# The owner: "great lets build the next", and of the windbreaks, "Wind
	# only": they stop the wind and walking, never an orb.
	const Arena := preload("res://src/enemies/windarena.gd")
	const Light := preload("res://src/enemies/lightarena.gd")
	const FX := preload("res://src/characters/statuseffects.gd")
	const Lag := preload("res://src/systems/lagtests.gd")
	const Hits := preload("res://src/shared/hitsource.gd")
	const Aim := preload("res://src/shared/targets.gd")

	# THE BULLETS FEEL IT: a flying orb bends, a mine lies still, a swirl turns.
	var field := BulletField.new()
	add_child(field)
	field.bounds = Rect2(-500, -500, 1000, 1000)
	field.wind = Vector2(0, 100)
	field.spawn(Vector2.ZERO, 0.0, 100.0, Color.WHITE)
	field.spawn_settling(Vector2(200, 0), 0.0, 50.0, Color.WHITE, 10.0, 3.0, 1, 0)
	for n in 40:
		field.step(0.05, Vector2(1.0e6, 1.0e6), 1.0, 0.0, true)
	var bent: Vector2 = field.velocity_of(0)
	var mine: Vector2 = field.velocity_of(1)
	check("the wind bends an orb in flight and leaves a mine lying still",
		bent.y > 150.0 and is_equal_approx(bent.x, 100.0) and mine == Vector2.ZERO, [bent, mine])
	field.clear()
	field.wind = Vector2.ZERO
	field.swirl_at = Vector2(0, 0)
	field.swirl_radius = 50.0
	field.swirl_rate = 2.0
	field.spawn(Vector2(10, 0), 0.0, 1.0, Color.WHITE)
	field.spawn(Vector2(300, 0), 0.0, 1.0, Color.WHITE)
	field.step(0.5, Vector2(1.0e6, 1.0e6), 1.0, 0.0, true)
	check("  and a swirl turns what is inside it, nothing outside",
		absf(field.velocity_of(0).angle() - 1.0) < 0.01 and absf(field.velocity_of(1).angle()) < 0.001,
		[field.velocity_of(0).angle(), field.velocity_of(1).angle()])
	field.queue_free()

	# THE ARENA.
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
	me.global_position = origin + Vector2(0, 150)
	var fx: Node = FX.attach(me)
	var boss: Node2D = (load("res://scene/enemy/windboss.tscn") as PackedScene).instantiate()
	boss.position = origin + Vector2(-115, -105)
	world.add_child(boss)
	await get_tree().process_frame
	boss.process_mode = Node.PROCESS_MODE_DISABLED
	Light.everywhere = true
	boss.call("_keep_arena", 1.0)
	var arena: Node2D = boss.call("arena")
	if arena == null or arena.get_script() != Arena:
		check("the loose Wind boss makes its arena", false, arena)
		Light.everywhere = false
		world.queue_free()
		return
	arena.set_process(false)
	var middle: Vector2 = zone.field.bounds.get_center()
	var breaks: Array = arena.get("breaks")
	var solid: bool = true
	for pair in breaks:
		for pillar in pair:
			var body: CollisionObject2D = (pillar as Node).get_node("body") as CollisionObject2D
			solid = solid and body.collision_layer == Arena.BODY_LAYER and body.collision_mask == 0
	# The pillars reach the physics world on its next frame.
	await get_tree().physics_frame
	await get_tree().physics_frame
	zone._rows_built = 0
	zone.build_all_walls()
	var orbs_pass: bool = true
	for k in breaks.size():
		orbs_pass = orbs_pass and not zone.field.is_wall(middle + Arena.BREAK_SPOTS[k] + Vector2(Arena.BREAK_GAP, -6))
	check("the loose Wind boss makes its arena, with two windbreaks of two crypt pillars each",
		str(arena.name) == "windarena0" and arena.get_parent() == ground and int(arena.call("standing")) == 2
		and breaks.all(func(p): return (p as Array).size() == 2), arena.name)
	check("  solid to walking (the walls layer), never to orbs (no bullet wall under them)", solid and orbs_pass)

	# THE CROSSWIND, turned by the leader and carrying you.
	arena.call("_process", 0.05)
	var to: float = float(arena.get("angle_to"))
	var eighth: float = fposmod(to, TAU / 8.0)
	for n in 30:
		arena.call("_process", 0.05)
	var way: Vector2 = Vector2.from_angle(float(arena.get("angle")))
	check("the leader turns the wind one of eight ways; it comes round, and bends the orbs that way",
		minf(eighth, TAU / 8.0 - eighth) < 0.001 and absf(angle_difference(float(arena.get("angle")), to)) < 0.001
		and zone.field.wind.is_equal_approx(way * Arena.ORB_BEND), [to, arena.get("angle")])
	var drifting: Vector2 = fx.get("drift_velocity")
	check("  out in it, you are carried along at its strength (a drift, renewed every frame)",
		float(fx.get("drift_left")) > 0.0 and drifting.is_equal_approx(way * float(Arena.WIND_DRIFT[0])), drifting)
	arena.call("hear", {"h": "wind", "a": 0.0})
	for n in 30:
		arena.call("_process", 0.05)
	var lee: Vector2 = middle + Arena.BREAK_SPOTS[0] + Vector2(30, 0)
	var calm: bool = bool(arena.call("sheltered", lee)) and not bool(arena.call("sheltered", lee - Vector2(60, 0))) \
		and not bool(arena.call("sheltered", lee + Vector2(Arena.LEE_LONG, 0)))
	me.global_position = lee
	fx.set("drift_left", 0.0)
	arena.call("_process", 0.05)
	check("  a follower turns it when told; behind a windbreak, down the wind, the air is calm and nothing carries you",
		calm and float(fx.get("drift_left")) == 0.0)

	# PHASE TWO: a gust lane through you.
	me.global_position = origin + Vector2(0, 150)
	boss.set("hp", int(float(boss.get("max_hp")) * 0.5))
	arena.call("_process", 0.9)
	var gusts: Array = arena.get("gusts")
	var through: bool = gusts.size() == 1 and bool(arena.call("in_gust", gusts[0], Aim.body_point(me)))
	arena.set("_gust_clock", 99.0)
	arena.call("_process", Arena.GUST_WARN)
	Hits.take()
	check("phase two: the leader lays a gust lane through you; it blows - a share of your health as wind, and a slide",
		through and me.taken == [[roundi(1000.0 * Arena.GUST_SHARE), Element.Type.WIND]] and float(fx.get("shove_left")) > 0.0,
		[through, me.taken])
	arena.call("hear", {"h": "gust", "x": me.global_position.x, "y": me.global_position.y, "a": 0.0})
	arena.call("hear", {"h": "twister", "x": origin.x + 5000.0, "y": origin.y})
	check("  a follower lays the leader's lane; nothing from far off", (arena.get("gusts") as Array).size() >= 1
		and arena.get("twister_to") == Vector2.INF)

	# PHASE THREE: the tornado.
	(arena.get("gusts") as Array).clear()
	me.taken.clear()
	fx.call("clear_all")
	boss.set("hp", int(float(boss.get("max_hp")) * 0.2))
	arena.call("_process", 0.05)
	var twister: Vector2 = arena.get("twister")
	check("phase three: the tornado forms in the room's middle and carries the orbs round it",
		twister.distance_to(middle) < 5.0 and is_equal_approx(zone.field.swirl_radius, Arena.TWISTER_REACH)
		and zone.field.swirl_at.distance_to(twister) < 5.0, twister)
	me.global_position = twister + Vector2(60, 0)
	arena.call("_process", 0.05)
	var pulled: bool = float(fx.get("pull_left")) > 0.0
	me.global_position = arena.get("twister")
	arena.set("_twister_clock", 99.0)
	arena.call("_process", 0.05)
	Hits.take()
	check("  within its reach it pulls you; in its core it flings you out, a share of your health as wind",
		pulled and me.taken == [[roundi(1000.0 * Arena.TWISTER_SHARE), Element.Type.WIND]] and float(fx.get("shove_left")) > 0.0,
		[pulled, me.taken])
	Lag.set_test("arena", true, get_tree())
	var hidden: bool = not (arena.get_node("wind") as CanvasItem).visible
	Lag.set_test("arena", false, get_tree())
	check("  the GM panel's Arena lag test hides its drawing", hidden and (arena.get_node("wind") as CanvasItem).visible)

	# GONE WITH ITS BOSS.
	var pillar: Node = (breaks[0] as Array)[0]
	boss.set("_dying", true)
	arena.call("_process", 0.05)
	var dropped: bool = zone.field.wind == Vector2.ZERO and zone.field.swirl_radius == 0.0 \
		and pillar.is_queued_for_deletion() and int(arena.call("standing")) == 0
	arena.call("_process", Arena.END_SECONDS + 0.1)
	check("its boss falling, the wind drops, the windbreaks crumble, and it goes",
		dropped and arena.is_queued_for_deletion())
	check("  and the readout letters its marks",
		PerfOverlay.MARK_LETTERS.get(&"wind turns") == "W" and PerfOverlay.MARK_LETTERS.get(&"gusts blow") == "L"
		and PerfOverlay.MARK_LETTERS.get(&"tornado forms") == "T")
	Light.everywhere = false
	world.queue_free()
	await get_tree().process_frame
	print("  (the Wind boss's arena: done)")


func _test_the_water_arena() -> void:
	section("THE WATER BOSS'S ARENA - THE TIDE, BUBBLES, THE WHIRLPOOL (0.141.0)")
	# The owner: "next boss", and of the water, "Drawn band".
	const Arena := preload("res://src/enemies/waterarena.gd")
	const Light := preload("res://src/enemies/lightarena.gd")
	const FX := preload("res://src/characters/statuseffects.gd")
	const Lag := preload("res://src/systems/lagtests.gd")
	const Hits := preload("res://src/shared/hitsource.gd")
	const Fx := preload("res://src/projectiles/spikefx.gd")
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
	var room: Rect2 = zone.field.bounds.grow(-16.0)
	var me := ArenaDummy.new()
	world.add_child(me)
	me.global_position = origin + Vector2(-300, 0)
	var fx: Node = FX.attach(me)
	var boss: Node2D = (load("res://scene/enemy/waterboss.tscn") as PackedScene).instantiate()
	boss.position = origin + Vector2(115, -105)
	world.add_child(boss)
	await get_tree().process_frame
	boss.process_mode = Node.PROCESS_MODE_DISABLED
	Light.everywhere = true
	boss.call("_keep_arena", 1.0)
	var arena: Node2D = boss.call("arena")
	if arena == null or arena.get_script() != Arena:
		check("the loose Water boss makes its arena", false, arena)
		Light.everywhere = false
		world.queue_free()
		return
	arena.set_process(false)
	var water: Node2D = arena.get_node("water")
	check("the loose Water boss makes its arena, the water drawn on the floor (sorted before the spikes' rings)",
		str(arena.name) == "waterarena0" and arena.get_parent() == ground and water.position.y < Fx.SORT_Y)

	# THE TIDE: the leader's, from a side; it shines, comes in a third, stands, goes.
	arena.call("_process", Arena.FIRST_TIDE + 0.05)
	var from: int = int(arena.get("side"))
	var shone: Rect2 = arena.call("shine")
	var dry: bool = (arena.call("flood") as Rect2).size.x <= 0.0
	arena.set("side", 0)
	arena.call("_process", Arena.TIDE_WARN + Arena.TIDE_IN)
	var wet: Rect2 = arena.call("flood")
	check("the leader sends a tide from a side: it shines wet first, then comes in a third of the room",
		from >= 0 and shone.has_area() and dry and is_equal_approx(wet.size.x, room.size.x * 0.34)
		and is_equal_approx(wet.position.x, room.position.x) and bool(arena.call("standing")), [from, wet])
	check("  in it you are soaked and wade (slower), out of it neither",
		(fx.get("started") as Array).has(FX.SOAKED) and float(fx.get("wade_left")) > 0.0
		and float(fx.call("speed_scale")) < 1.0)
	fx.call("clear_all")
	me.global_position = origin + Vector2(300, 0)
	arena.call("_process", 0.05)
	check("  (out of it)", float(fx.get("wade_left")) == 0.0 and is_equal_approx(float(fx.call("speed_scale")), 1.0))
	arena.call("_process", Arena.TIDE_HOLD + Arena.TIDE_OUT)
	var sides: Array = []
	for n in 6:
		arena.call("_process", Arena.TIDE_REST + 0.05)
		sides.append(int(arena.get("side")))
		arena.call("_process", Arena.TIDE_WARN + Arena.TIDE_IN + Arena.TIDE_HOLD + Arena.TIDE_OUT)
	var repeats: int = 0
	for n in range(1, sides.size()):
		if sides[n] == sides[n - 1]:
			repeats += 1
	check("  it goes out, and the next comes from another side, never the same twice", repeats == 0, sides)

	# PHASE TWO: the same bubbles on every screen, from the tide's seed.
	boss.set("hp", int(float(boss.get("max_hp")) * 0.5))
	arena.call("_process", 0.01)
	arena.call("start_tide", 0, 4242)
	arena.call("_process", Arena.TIDE_WARN + Arena.TIDE_IN + 1.0)
	var mine: Array = (arena.get("bubbles") as Array).map(func(b): return b[0])
	arena.call("start_tide", 0, 4242)
	arena.call("_process", Arena.TIDE_WARN + Arena.TIDE_IN + 1.0)
	var again: Array = (arena.get("bubbles") as Array).map(func(b): return b[0])
	var inside: bool = mine.all(func(p): return (arena.call("flood") as Rect2).has_point(p))
	check("phase two: bubbles rise in the water - the same from the same tide, wherever it is played",
		mine.size() >= 3 and mine == again and inside, mine.size())
	var bubble: Array = (arena.get("bubbles") as Array)[0]
	me.global_position = (bubble[0] as Vector2) - Vector2(0, -4)
	me.taken.clear()
	arena.call("_process", 0.01)
	Hits.take()
	check("  one that touches you pops: a share of your health as water, and soaked",
		me.taken.size() == 1 and me.taken[0] == [roundi(1000.0 * Arena.BUBBLE_SHARE), Element.Type.WATER] and bool(bubble[2]),
		me.taken)
	arena.call("hear", {"h": "tide", "s": 3, "n": 7})
	check("  a follower plays the leader's tide; nothing it does not know",
		int(arena.get("side")) == 3 and int(arena.get("tide_seed")) == 7)
	arena.call("hear", {"h": "gust", "s": 1, "n": 9})
	check("  (a stranger's event changes nothing)", int(arena.get("side")) == 3)

	# PHASE THREE: half the room, and the whirlpool.
	boss.set("hp", int(float(boss.get("max_hp")) * 0.2))
	arena.call("_process", 0.01)
	arena.call("start_tide", 1, 11)
	arena.call("_process", Arena.TIDE_WARN + Arena.TIDE_IN + 0.1)
	var half: Rect2 = arena.call("flood")
	var pool: Vector2 = arena.call("whirlpool")
	fx.call("clear_all")
	me.global_position = pool + Vector2(-60, 0)
	(arena.get("bubbles") as Array).clear()
	arena.call("_process", 0.01)
	var pulled: bool = float(fx.get("pull_left")) > 0.0
	me.global_position = pool
	me.taken.clear()
	(arena.get("bubbles") as Array).clear()
	arena.call("_process", 0.01)
	Hits.take()
	check("phase three: the water comes in half the room; the whirlpool in its middle pulls you, its core drags you under",
		is_equal_approx(half.size.x, room.size.x * 0.5) and pool.distance_to(half.get_center()) < 1.0 and pulled
		and me.taken.size() == 1 and me.taken[0] == [roundi(1000.0 * Arena.WHIRL_SHARE), Element.Type.WATER], [pulled, me.taken])
	Lag.set_test("arena", true, get_tree())
	var hidden: bool = not water.visible
	Lag.set_test("arena", false, get_tree())
	check("  the GM panel's Arena lag test hides the water (it still soaks)", hidden and water.visible)

	# GONE WITH ITS BOSS.
	boss.set("_dying", true)
	arena.call("_process", 0.05)
	arena.call("_process", Arena.END_SECONDS + 0.1)
	check("its boss falling, the water drains away and it goes", arena.is_queued_for_deletion())
	check("  and the readout letters its marks",
		PerfOverlay.MARK_LETTERS.get(&"tide comes") == "Q" and PerfOverlay.MARK_LETTERS.get(&"bubbles pop") == "O")
	var run := RunStub.new()
	run.add_to_group(&"endless_run")
	add_child(run)
	check("in the Endless an arena fills the run's floor, never its corridor (the fallen wait there)",
		Light.room_of(self) == run.arena_rect and Light.in_room(self, Vector2(100, 100))
		and not Light.in_room(self, Vector2(500, 900)))
	run.free()
	Light.everywhere = false
	world.queue_free()
	await get_tree().process_frame
	print("  (the Water boss's arena: done)")


func _test_the_ice_arena() -> void:
	section("THE ICE BOSS'S ARENA - FROST, WALLS OF ICE, HAIL, THE BLIZZARD (0.142.0)")
	# The owner: "next boss", and of the blizzard's fog, "As pictured".
	const Arena := preload("res://src/enemies/icearena.gd")
	const Light := preload("res://src/enemies/lightarena.gd")
	const FX := preload("res://src/characters/statuseffects.gd")
	const Lag := preload("res://src/systems/lagtests.gd")
	const Hits := preload("res://src/shared/hitsource.gd")
	const Fx := preload("res://src/projectiles/spikefx.gd")

	# THE BULLETS: a painted wall ends an orb, and goes leaving the real walls.
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
	var probe: Vector2 = origin + Vector2(0, 200)
	var wall_cell: int = zone._walls.size() - 1
	zone._walls[wall_cell] = 1
	var painted: int = zone.paint_solid("t", probe - Vector2(40, 0), probe + Vector2(40, 0), 10.0, true)
	zone.field.spawn(probe + Vector2(0, -40), PI * 0.5, 100.0, Color.WHITE)
	for n in 10:
		zone.field.step(0.05, Vector2(1.0e6, 1.0e6), 1.0, 0.0, true)
	var ended: bool = zone.field.count == 0 and zone.field.is_wall(probe)
	var opened: int = zone.paint_solid("t", Vector2.ZERO, Vector2.ZERO, 0.0, false)
	check("a painted wall ends an orb and opens again exactly - the real walls kept",
		painted > 10 and ended and opened == painted and not zone.field.is_wall(probe) and zone._walls[wall_cell] == 1,
		[painted, ended, opened])
	zone._walls[wall_cell] = 0

	var me := ArenaDummy.new()
	world.add_child(me)
	me.global_position = origin + Vector2(0, 100)
	var fx: Node = FX.attach(me)
	var boss: Node2D = (load("res://scene/enemy/iceboss.tscn") as PackedScene).instantiate()
	boss.position = origin + Vector2(0, -150)
	world.add_child(boss)
	await get_tree().process_frame
	boss.process_mode = Node.PROCESS_MODE_DISABLED
	Light.everywhere = true
	boss.call("_keep_arena", 1.0)
	var arena: Node2D = boss.call("arena")
	if arena == null or arena.get_script() != Arena:
		check("the loose Ice boss makes its arena", false, arena)
		Light.everywhere = false
		world.queue_free()
		return
	arena.set_process(false)
	var fog_node: Node2D = arena.get_node("fog")
	var fog_rect: Rect2 = Rect2((fog_node.get_child(0) as ColorRect).position, (fog_node.get_child(0) as ColorRect).size)
	check("the loose Ice boss makes its arena: frost on the floor, the fog in the world over it all and under the HUD, not yet showing",
		str(arena.name) == "icearena0" and (arena.get_node("frost") as Node2D).position.y < Fx.SORT_Y
		and fog_node.z_index == Arena.FOG_Z and not fog_node.z_as_relative and not fog_node.visible
		and fog_rect.encloses(Light.room_of(boss).grow(Arena.FOG_REACH - 1.0)), fog_rect)

	# FROST: the leader's, near you; on it you skid and are chilled.
	arena.set("_wall_clock", 99.0)
	arena.call("_process", 1.6)
	var patches: Array = arena.get("frost")
	var near: bool = patches.size() == 1 and (patches[0][0] as Vector2).distance_to(_arena_point(me)) <= Arena.FROST_NEAR.y + 2.0
	patches[0][0] = _arena_point(me)
	patches[0][2] = Arena.FROST_FORM
	arena.set("_frost_clock", 99.0)
	me.velocity = Vector2(100, 0)
	arena.call("_process", 0.05)
	me.velocity = Vector2(-100, 0)
	arena.call("_process", 0.05)
	var skid: Vector2 = fx.get("drift_velocity")
	check("the leader lays frost near you; on it your walk comes round slowly (a skid) and you are chilled",
		near and float(fx.get("drift_left")) > 0.0 and skid.x > 50.0 and (fx.get("started") as Array).has(FX.CHILL), [near, skid])

	# A WALL OF ICE behind you, away from the boss.
	fx.call("clear_all")
	(arena.get("frost") as Array).clear()
	arena.set("_wall_clock", 0.0)
	arena.call("_process", 0.01)
	var walls: Array = arena.get("walls")
	var wall: Node2D = walls[0] if not walls.is_empty() else null
	var behind: bool = wall != null and wall.global_position.y > me.global_position.y \
		and absf(wall.global_position.x - me.global_position.x) < 4.0
	var warned: bool = wall != null and not bool(wall.call("stands"))
	arena.set("_wall_clock", 99.0)
	arena.call("_process", Arena.WALL_WARN)
	await get_tree().physics_frame
	var solid: int = 0
	for v in zone._walls:
		if v == BulletField.SOLID_FIRST:
			solid += 1
	var body: CollisionShape2D = wall.get_node("ice").get_child(0) as CollisionShape2D
	check("the leader raises a wall of ice behind you, across from the boss: it warns, then stops walking and orbs",
		behind and warned and bool(wall.call("stands")) and solid > 10 and not body.disabled
		and wall.is_in_group(&"levers") and wall.has_meta(&"stress_copy") and not bool(wall.call("can_be_aimed_at")),
		[behind, warned, solid])
	for n in Arena.WALL_HITS:
		wall.call("take_damage", 5.0)
	solid = 0
	for v in zone._walls:
		if v == BulletField.SOLID_FIRST:
			solid += 1
	check("  %d blows of yours break it - a door, the orbs through it again" % Arena.WALL_HITS,
		bool(wall.get("broken")) and solid == 0)
	arena.call("hear", {"h": "wall", "x": origin.x + 100.0, "y": origin.y, "a": 0.0, "n": 12})
	var heard: Node2D = (arena.get("walls") as Array).back()
	arena.call("_process", Arena.WALL_WARN)
	heard.call("follow_pull", true)
	check("  a follower raises the leader's wall (named for the levers, \"wall<n mod 10>\"); another game's break breaks it here",
		str(heard.name) == "wall2" and bool(heard.get("broken")))
	arena.call("_process", Arena.WALL_RISE + Arena.WALL_LIFE)
	check("  and a wall goes when its time is up", (arena.get("walls") as Array).is_empty(), (arena.get("walls") as Array).size())

	# PHASE TWO: hail.
	boss.set("hp", int(float(boss.get("max_hp")) * 0.5))
	arena.set("_frost_clock", 99.0)
	arena.set("_wall_clock", 99.0)
	arena.call("_process", 0.01)
	var stones: Array = arena.get("hail")
	var dropped: bool = stones.size() == 1 and (stones[0][0] as Vector2).distance_to(_arena_point(me)) <= Arena.HAIL_NEAR + 1.0
	stones.clear()
	arena.set("_hail_clock", 99.0)
	arena.call("add_hail", _arena_point(me))
	arena.call("add_hail", _arena_point(me) + Vector2(60, 0))
	me.taken.clear()
	arena.call("_process", Arena.HAIL_WARN)
	Hits.take()
	check("phase two: hail near each player; a stone lands after its shadow - near it, a share of your health as ice",
		dropped and me.taken == [[roundi(1000.0 * Arena.HAIL_SHARE), Element.Type.ICE]], me.taken)
	arena.call("hear", {"h": "hail", "x": origin.x + 5000.0, "y": origin.y})
	arena.call("hear", {"h": "frost", "x": me.global_position.x, "y": me.global_position.y, "r": 40.0})
	check("  a follower makes the leader's frost and hail; nothing from far off",
		(arena.get("hail") as Array).is_empty() and (arena.get("frost") as Array).size() == 1)

	# PHASE THREE: the blizzard.
	boss.set("hp", int(float(boss.get("max_hp")) * 0.2))
	for n in 5:
		arena.call("_process", 0.5)
	var fog: Node2D = arena.get_node("fog")
	check("phase three: the blizzard closes in - snow over the room, the fog at the screen's edges",
		is_equal_approx(float(arena.get("blizzard")), 1.0) and fog.visible
		and is_equal_approx(float((arena.get("_fog_material") as ShaderMaterial).get_shader_parameter(&"amount")), Arena.FOG_THICK))
	Lag.set_test("arena", true, get_tree())
	var hidden: bool = not fog.visible and not (arena.get_node("snow") as CanvasItem).visible \
		and not (arena.get_node("frost") as CanvasItem).visible
	Lag.set_test("arena", false, get_tree())
	check("  the GM panel's Arena lag test hides frost, snow and fog", hidden and fog.visible)

	# GONE WITH ITS BOSS.
	arena.set("_wall_clock", 0.0)
	arena.call("_process", 0.01)
	arena.call("_process", Arena.WALL_WARN)
	boss.set("_dying", true)
	arena.call("_process", 0.05)
	solid = 0
	for v in zone._walls:
		if v == BulletField.SOLID_FIRST:
			solid += 1
	arena.call("_process", Arena.END_SECONDS + 0.1)
	check("its boss falling, the walls shatter (the bullets' grid as it was), the fog lifts, and it goes",
		solid == 0 and (arena.get("walls") as Array).is_empty() and arena.is_queued_for_deletion() and not fog.visible)
	check("  and the readout letters its marks",
		PerfOverlay.MARK_LETTERS.get(&"frost forms") == "S" and PerfOverlay.MARK_LETTERS.get(&"ice walls rise") == "I"
		and PerfOverlay.MARK_LETTERS.get(&"hail lands") == "U")
	Light.everywhere = false
	world.queue_free()
	await get_tree().process_frame
	print("  (the Ice boss's arena: done)")


func _arena_point(body: Node2D) -> Vector2:
	return preload("res://src/shared/targets.gd").body_point(body)


func _test_the_earth_arena() -> void:
	section("THE EARTH BOSS'S ARENA - FAULT LINES, FALLING ROCK, THE QUAKE (0.143.0)")
	# The owner: "ok next boss", and of the fault walls, "Walking only".
	const Arena := preload("res://src/enemies/eartharena.gd")
	const Light := preload("res://src/enemies/lightarena.gd")
	const FX := preload("res://src/characters/statuseffects.gd")
	const Lag := preload("res://src/systems/lagtests.gd")
	const Hits := preload("res://src/shared/hitsource.gd")
	const Fx := preload("res://src/projectiles/spikefx.gd")
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
	me.global_position = origin + Vector2(0, 120)
	var fx: Node = FX.attach(me)
	var boss: Node2D = (load("res://scene/enemy/earthboss.tscn") as PackedScene).instantiate()
	boss.position = origin + Vector2(0, -150)
	world.add_child(boss)
	await get_tree().process_frame
	boss.process_mode = Node.PROCESS_MODE_DISABLED
	Light.everywhere = true
	boss.call("_keep_arena", 1.0)
	var arena: Node2D = boss.call("arena")
	if arena == null or arena.get_script() != Arena:
		check("the loose Earth boss makes its arena", false, arena)
		Light.everywhere = false
		world.queue_free()
		return
	arena.set_process(false)
	check("the loose Earth boss makes its arena, its cracks drawn on the floor",
		str(arena.name) == "eartharena0" and (arena.get_node("ground") as Node2D).position.y < Fx.SORT_Y)

	# THE BOX (0.144.0; the owner: "spike wall need to be more like a box
	# that traps players in"): dust round you, then stalagmites on four sides.
	var trapped_at: Vector2 = _arena_point(me)
	arena.set("_fault_clock", 0.0)
	arena.call("_process", 0.01)
	var faults: Array = arena.get("faults")
	var warned: bool = faults.size() == 1 and not bool(faults[0][3])
	var round_you: bool = faults.size() == 1 and (arena.call("box_rect", faults[0]) as Rect2).has_point(trapped_at)
	var ridges: Array = faults[0][2] if faults.size() == 1 else []
	me.taken.clear()
	arena.set("_fault_clock", 99.0)
	arena.call("_process", Arena.FAULT_WARN)
	Hits.take()
	await get_tree().physics_frame
	var solid: bool = not ridges.is_empty() and ridges.all(func(r): return not ((r as Node).get_node("rock").get_child(0) as CollisionShape2D).disabled)
	var side_mid: Vector2 = ((faults[0][4][0][0] as Vector2) + (faults[0][4][0][1] as Vector2)) * 0.5
	check("the leader cracks a square round you; it warns, then stalagmites rise on all four sides and you are trapped",
		warned and round_you and bool(faults[0][3]) and solid and (faults[0][4] as Array).size() == 4
		and bool(arena.call("boxed", trapped_at)) and me.taken.is_empty(), [warned, round_you, ridges.size(), me.taken])
	check("  solid to walking, never to an orb", not zone.field.is_wall(side_mid))
	arena.call("_process", Arena.FAULT_LIFE)
	check("  and it sinks when its time is up", (arena.get("faults") as Array).is_empty()
		and ridges.all(func(r): return not is_instance_valid(r) or (r as Node).is_queued_for_deletion()))
	# Stood on its edge as it rises: hit, and thrown to the side most of you is on.
	arena.call("add_box", _arena_point(me) + Vector2(Arena.BOX_HALF - 4.0, 0.0))
	me.taken.clear()
	fx.call("clear_all")
	arena.call("_process", Arena.FAULT_WARN)
	Hits.take()
	check("  risen under you, it hits and throws you off", me.taken == [[roundi(1000.0 * Arena.FAULT_SHARE), Element.Type.EARTH]]
		and float(fx.get("shove_left")) > 0.0, me.taken)
	arena.call("_process", Arena.FAULT_LIFE)

	# PHASE TWO: falling rock.
	fx.call("clear_all")
	me.taken.clear()
	boss.set("hp", int(float(boss.get("max_hp")) * 0.5))
	arena.call("_process", 0.01)
	var rocks: Array = arena.get("rocks")
	var near: bool = rocks.size() == 1 and (rocks[0][0] as Vector2).distance_to(_arena_point(me)) <= Arena.ROCK_NEAR + 1.0
	rocks.clear()
	arena.set("_rock_clock", 99.0)
	arena.call("add_rock", _arena_point(me))
	arena.call("add_rock", _arena_point(me) + Vector2(70, 0))
	arena.call("_process", Arena.ROCK_WARN)
	Hits.take()
	check("phase two: rock falls near each player after its shadow - near it, a share of your health as earth, and rooted",
		near and me.taken == [[roundi(1000.0 * Arena.ROCK_SHARE), Element.Type.EARTH]] and (fx.get("started") as Array).has(FX.ROOT),
		me.taken)
	arena.call("add_box", _arena_point(me))
	arena.call("_process", Arena.FAULT_WARN)
	(arena.get("rocks") as Array).clear()
	arena.set("_rock_clock", 0.0)
	arena.set("_look_left", 0.0)
	arena.call("_process", 0.01)
	var on_you: Array = arena.get("rocks")
	check("  trapped in a box, the rock comes down on you", on_you.size() == 1
		and (on_you[0][0] as Vector2).distance_to(_arena_point(me)) < 0.5, on_you)
	arena.call("_process", Arena.FAULT_LIFE)
	(arena.get("rocks") as Array).clear()
	arena.set("_rock_clock", 99.0)

	# PHASE THREE: the quake.
	fx.call("clear_all")
	me.taken.clear()
	boss.set("hp", int(float(boss.get("max_hp")) * 0.2))
	arena.call("_process", 0.01)
	var pits: Array = arena.get("pits")
	var cracked: bool = pits.size() == 1 and (pits[0][0] as Vector2).distance_to(_arena_point(me)) <= Arena.PIT_NEAR + 1.0
	pits.clear()
	arena.set("_pit_clock", 99.0)
	arena.call("add_pit", _arena_point(me) + Vector2(6, 0))
	arena.call("_process", Arena.PIT_WARN * 0.5)
	var before: int = me.taken.size()
	arena.call("_process", Arena.PIT_WARN * 0.5)
	arena.call("_process", 0.1)
	Hits.take()
	check("phase three: the floor cracks near you, then drops away - in it you fall (a share of your health), thrown out; once a second at most",
		cracked and before == 0 and me.taken == [[roundi(1000.0 * Arena.PIT_SHARE), Element.Type.EARTH]]
		and float(fx.get("shove_left")) > 0.0, [cracked, me.taken])
	arena.call("hear", {"h": "pit", "x": origin.x + 5000.0, "y": origin.y})
	arena.call("hear", {"h": "rock", "x": me.global_position.x, "y": me.global_position.y})
	arena.call("hear", {"h": "box", "x": me.global_position.x, "y": me.global_position.y})
	check("  a follower makes the leader's boxes, rocks and pits; nothing from far off",
		(arena.get("pits") as Array).size() == 1 and (arena.get("rocks") as Array).size() == 1 and (arena.get("faults") as Array).size() == 1)
	Lag.set_test("arena", true, get_tree())
	var hidden: bool = not (arena.get_node("ground") as CanvasItem).visible
	Lag.set_test("arena", false, get_tree())
	check("  the GM panel's Arena lag test hides its cracks and pits", hidden and (arena.get_node("ground") as CanvasItem).visible)

	# GONE WITH ITS BOSS.
	var last: Array = ((arena.get("faults") as Array)[0] as Array)[2]
	boss.set("_dying", true)
	arena.call("_process", 0.05)
	arena.call("_process", Arena.END_SECONDS + 0.1)
	check("its boss falling, the stalagmites sink, the floor knits, and it goes",
		arena.is_queued_for_deletion() and last.all(func(r): return not is_instance_valid(r) or (r as Node).is_queued_for_deletion()))
	check("  and the readout letters its marks",
		PerfOverlay.MARK_LETTERS.get(&"faults crack") == "J" and PerfOverlay.MARK_LETTERS.get(&"rocks fall") == "Y"
		and PerfOverlay.MARK_LETTERS.get(&"floor drops") == "Z")
	Light.everywhere = false
	world.queue_free()
	await get_tree().process_frame
	print("  (the Earth boss's arena: done)")


func _test_the_fire_arena() -> void:
	section("THE FIRE BOSS'S ARENA - LAVA VENTS, EMBERS, THE RISING LAVA (0.143.0)")
	# The owner: "next boss", and of the lava, "Deeper".
	const Arena := preload("res://src/enemies/firearena.gd")
	const Light := preload("res://src/enemies/lightarena.gd")
	const FX := preload("res://src/characters/statuseffects.gd")
	const Lag := preload("res://src/systems/lagtests.gd")
	const Hits := preload("res://src/shared/hitsource.gd")
	const Fx := preload("res://src/projectiles/spikefx.gd")
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
	var room: Rect2 = zone.field.bounds.grow(-16.0)
	var me := ArenaDummy.new()
	world.add_child(me)
	me.global_position = origin + Vector2(0, 60)
	var fx: Node = FX.attach(me)
	var boss: Node2D = (load("res://scene/enemy/fireboss.tscn") as PackedScene).instantiate()
	boss.position = origin + Vector2(175, -172)
	world.add_child(boss)
	await get_tree().process_frame
	boss.process_mode = Node.PROCESS_MODE_DISABLED
	Light.everywhere = true
	boss.call("_keep_arena", 1.0)
	var arena: Node2D = boss.call("arena")
	if arena == null or arena.get_script() != Arena:
		check("the loose Fire boss makes its arena", false, arena)
		Light.everywhere = false
		world.queue_free()
		return
	arena.set_process(false)
	var vents: PackedVector2Array = arena.get("vents")
	check("the loose Fire boss makes its arena: its vents on a ring round the room's middle, drawn on the floor",
		str(arena.name) == "firearena0" and vents.size() == Arena.VENTS and (arena.get_node("lava") as Node2D).position.y < Fx.SORT_Y
		and Array(vents).all(func(v): return room.has_point(v)))

	# A SWEEP: the leader's, round the ring one way, a vent at a time.
	arena.set("_sweep_clock", 0.0)
	arena.call("_process", 0.01)
	var turns: Array = arena.get("turns")
	var order: Array = turns.map(func(t): return int(t[0]))
	var one_way: bool = order.size() == int(Arena.SWEEP_LENGTH[0])
	for k in range(1, order.size()):
		var step: int = posmod(int(order[k]) - int(order[k - 1]), Arena.VENTS)
		one_way = one_way and step == posmod(int(order[1]) - int(order[0]), Arena.VENTS) and (step == 1 or step == Arena.VENTS - 1)
	check("the leader starts a sweep round the vents, one way, never doubling back, each its turn after the last",
		one_way, order)
	turns.clear()
	(arena.get("pools") as Array).clear()
	arena.set("_sweep_clock", 99.0)
	var vent: Vector2 = vents[2]
	me.global_position += vent - _arena_point(me) + Vector2(4, 0)
	me.taken.clear()
	arena.call("start_sweep", 2, 1, 1)
	arena.call("_process", Arena.VENT_WARN * 0.5)
	var before: int = me.taken.size()
	arena.call("_process", Arena.VENT_WARN * 0.5 + 0.01)
	Hits.take()
	check("  a vent glows, then erupts: on it, a share of your health as fire and burning; it leaves a pool",
		before == 0 and me.taken.size() >= 1 and me.taken[0] == [roundi(1000.0 * Arena.VENT_SHARE), Element.Type.FIRE]
		and (fx.get("started") as Array).has(FX.BURN) and (arena.get("pools") as Array).size() == 1, me.taken)
	me.taken.clear()
	arena.call("_process", Arena.POOL_GAP + 0.01)
	Hits.take()
	check("  and the pool burns you while you stand in it", me.taken.size() == 1
		and me.taken[0] == [roundi(1000.0 * Arena.POOL_SHARE), Element.Type.FIRE], me.taken)

	# PHASE TWO: embers.
	fx.call("clear_all")
	(arena.get("pools") as Array).clear()
	me.global_position = origin + Vector2(0, 60)
	me.taken.clear()
	boss.set("hp", int(float(boss.get("max_hp")) * 0.5))
	arena.call("_process", 0.01)
	var embers: Array = arena.get("embers")
	var over: bool = embers.size() == 1 and (embers[0][0] as Vector2).y < _arena_point(me).y - 100.0
	embers.clear()
	arena.set("_ember_clock", 99.0)
	arena.call("add_ember", _arena_point(me) - Vector2(0, Arena.EMBER_FALL * 1.0))
	# Its sway at nothing a second in, when it reaches you.
	((arena.get("embers") as Array)[0] as Array)[2] = TAU - 2.2
	for n in 30:
		arena.call("_process", 0.05)
	Hits.take()
	check("phase two: an ember falls over each player; drifting down onto you, it burns",
		over and me.taken.size() == 1 and me.taken[0] == [roundi(1000.0 * Arena.EMBER_SHARE), Element.Type.FIRE]
		and (arena.get("embers") as Array).is_empty(), [over, me.taken])
	arena.call("hear", {"h": "sweep", "s": 3, "d": -1, "n": 4})
	arena.call("hear", {"h": "ember", "x": origin.x + 5000.0, "y": origin.y})
	var heard: Array = (arena.get("turns") as Array).map(func(t): return int(t[0]))
	check("  a follower plays the leader's sweep; nothing from far off",
		heard == [3, 2, 1, 0] and (arena.get("embers") as Array).is_empty(), [heard, (arena.get("embers") as Array).size()])
	(arena.get("turns") as Array).clear()

	# PHASE THREE: the lava rises, leaving the middle.
	me.taken.clear()
	boss.set("hp", int(float(boss.get("max_hp")) * 0.2))
	for n in 8:
		arena.call("_process", 0.5)
	var dry: Rect2 = arena.call("dry")
	var kept: bool = is_equal_approx(dry.size.x, room.size.x * Arena.LAVA_KEEP.x) and is_equal_approx(dry.size.y, room.size.y * Arena.LAVA_KEEP.y)
	var middle_dry: bool = not bool(arena.call("in_lava", room.get_center())) and bool(arena.call("in_lava", room.position + Vector2(10, 10)))
	me.global_position = room.position + Vector2(30, 40)
	arena.call("_process", 0.05)
	Hits.take()
	check("phase three: the lava rises from the walls, leaving the middle; in it you burn",
		float(arena.get("lava")) == 1.0 and kept and middle_dry and me.taken.size() >= 1
		and me.taken[0] == [roundi(1000.0 * Arena.LAVA_SHARE), Element.Type.FIRE], [kept, middle_dry, me.taken])
	Lag.set_test("arena", true, get_tree())
	var hidden: bool = not (arena.get_node("lava") as CanvasItem).visible and not (arena.get_node("fire") as CanvasItem).visible
	Lag.set_test("arena", false, get_tree())
	check("  the GM panel's Arena lag test hides the vents, lava and fire", hidden)
	boss.set("hp", int(boss.get("max_hp")))
	for n in 8:
		arena.call("_process", 0.5)
	check("  back to full health, it ebbs", float(arena.get("lava")) == 0.0 and not bool(arena.call("in_lava", room.position + Vector2(10, 10))))

	# GONE WITH ITS BOSS.
	boss.set("_dying", true)
	arena.call("_process", 0.05)
	arena.call("_process", Arena.END_SECONDS + 0.1)
	check("its boss falling, the vents go cold and it goes", arena.is_queued_for_deletion())
	check("  and the readout letters its marks",
		PerfOverlay.MARK_LETTERS.get(&"vents erupt") == "N" and PerfOverlay.MARK_LETTERS.get(&"lava burns") == "~")
	Light.everywhere = false
	world.queue_free()
	await get_tree().process_frame
	print("  (the Fire boss's arena: done)")


class GateStub extends Node2D:
	# A gauntlet gate, as bossgauntlet.gd asks one: its wave, its boss, its
	# land, and open() / warn() written down.
	var wave: int = 1
	var boss_path: NodePath = NodePath("boss")
	var element: int = Element.Type.ICE
	var opened: bool = false
	var warned: float = 0.0

	func open() -> void:
		opened = true
		var boss: Node = get_node_or_null(boss_path)
		if boss != null:
			boss.set(&"gated", false)
		# As the real gate frees itself once it has shattered, an opened one
		# holds nothing any more: the gauntlet must not ask it.
		boss_path = NodePath()

	func warn(seconds: float) -> void:
		warned = seconds


class GateBoss extends Node2D:
	# A boss behind a gate, as the gauntlet watches it.
	signal died
	var gated: bool = true
	var _dying: bool = false
	@warning_ignore("unused_private_class_variable")
	var _death_resolved: bool = false
	var net_mirror: bool = false
	var land: int = Element.Type.ICE
	var phase_now: int = 0
	var fighting: bool = true

	func current_element() -> int:
		return land

	func _current_phase() -> int:
		return phase_now

	func in_fight() -> bool:
		return fighting and not gated


func _gauntlet_of(lands: Array, mirrors: bool) -> Node2D:
	"""A gauntlet over stub gates: `lands` is [[wave, land], ...] in scene
	order."""
	var gauntlet: Node2D = (preload("res://src/world/bossgauntlet.gd") as GDScript).new()
	gauntlet.set(&"wave_gap_seconds", 0.05)
	for pair in lands:
		var gate := GateStub.new()
		gate.wave = int(pair[0])
		gate.element = int(pair[1])
		var boss := GateBoss.new()
		boss.name = "boss"
		boss.land = int(pair[1])
		boss.net_mirror = mirrors
		gate.add_child(boss)
		gauntlet.add_child(gate)
	add_child(gauntlet)
	return gauntlet


func _gate_of(gauntlet: Node, land: int) -> GateStub:
	for gate in gauntlet.get_children():
		if gate is GateStub and (gate as GateStub).element == land:
			return gate
	return null


func _test_bosses_share_the_arena() -> void:
	section("WHEN BOSSES FIGHT TOGETHER - TURNS, THE FLOOR, ONE HIT, ONE GATE AT A TIME (0.143.0)")
	# The owner: "we need to make sure that 3 bosses do not break the game
	# also", "should we release them 1 gate at a time then?", and of the
	# advice, "sounds good".
	const Light := preload("res://src/enemies/lightarena.gd")
	const Fire := preload("res://src/enemies/firearena.gd")
	const Ice := preload("res://src/enemies/icearena.gd")
	const FX := preload("res://src/characters/statuseffects.gd")
	const BossScript := preload("res://src/enemies/bossenemy.gd")
	const Gauntlet := preload("res://src/world/bossgauntlet.gd")
	const Hits := preload("res://src/shared/hitsource.gd")
	const Sync := preload("res://src/world/monstersync.gd")

	# TWO PULLS AT ONCE: the tornado and the whirlpool both draw you.
	var host := ArenaDummy.new()
	add_child(host)
	host.global_position = Vector2(-30000, -30000)
	var pulls: Node = FX.attach(host)
	await get_tree().process_frame
	for n in 3:
		pulls.call("pull", host.global_position + Vector2(200, 0), 0.15, 40.0, 11)
		pulls.call("pull", host.global_position + Vector2(0, 200), 0.15, 40.0, 22)
	var push: Vector2 = pulls.call("push_velocity")
	check("two pulls renewed together both draw you (the tornado and the whirlpool), together under PULL_SPEED_MAX",
		push.x > 15.0 and push.y > 15.0 and push.length() <= FX.PULL_SPEED_MAX + 0.01, push)
	pulls.call("clear_all")
	for n in 3:
		pulls.call("pull", host.global_position + Vector2(200, 0), 0.15, 40.0, 11)
		pulls.call("pull", host.global_position + Vector2(200, 0), 0.15, 40.0, 11)
	push = pulls.call("push_velocity")
	check("  one pull alone, however often renewed, draws you at its own speed, as before", absf(push.length() - 40.0) < 0.5
		and float(pulls.get("pull_left_b")) == 0.0, push)
	host.queue_free()

	# A ROOM WITH TWO BOSSES: Fire and Ice, each with its arena.
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
	var me := ArenaDummy.new()
	world.add_child(me)
	me.global_position = origin + Vector2(0, 40)
	FX.attach(me)
	var fire_boss: Node2D = (load("res://scene/enemy/fireboss.tscn") as PackedScene).instantiate()
	fire_boss.position = origin + Vector2(175, -172)
	world.add_child(fire_boss)
	var ice_boss: Node2D = (load("res://scene/enemy/iceboss.tscn") as PackedScene).instantiate()
	ice_boss.position = origin + Vector2(-175, -172)
	world.add_child(ice_boss)
	await get_tree().process_frame
	fire_boss.process_mode = Node.PROCESS_MODE_DISABLED
	ice_boss.process_mode = Node.PROCESS_MODE_DISABLED
	Light.everywhere = true
	fire_boss.call("_keep_arena", 1.0)
	ice_boss.call("_keep_arena", 1.0)
	var fire: Node2D = fire_boss.call("arena")
	var ice: Node2D = ice_boss.call("arena")
	if fire == null or ice == null:
		check("two loose bosses make two arenas in one room", false, [fire, ice])
		Light.everywhere = false
		world.queue_free()
		return
	fire.set_process(false)
	ice.set_process(false)
	check("two loose bosses make two arenas, both in the floor book, and each counts the other as a partner",
		get_tree().get_nodes_in_group(Light.FLOOR_GROUP).has(fire) and get_tree().get_nodes_in_group(Light.FLOOR_GROUP).has(ice)
		and Light.partners(fire_boss) == 1 and Light.partners(ice_boss) == 1)

	# THE LAVA LEAVES MORE WITH A PARTNER: half the room, not the dirt square.
	fire_boss.set("hp", 1)
	for k in 8:
		fire.call("_process", 0.5)
	var dry: Rect2 = fire.call("dry")
	var room: Rect2 = fire.get("_room")
	var share: float = dry.get_area() / room.get_area()
	check("with a partner, Fire's lava rises to leave about half the room dry (%.0f%%), not the dirt square alone" % (share * 100.0),
		float(fire.get("lava")) >= 1.0 and absf(share - Fire.LAVA_KEEP_SHARED.x * Fire.LAVA_KEEP_SHARED.y) < 0.01, share)

	# THE FLOOR BOOK.
	var in_lava: Vector2 = room.position + Vector2(20, 20)
	var middle: Vector2 = room.get_center()
	check("the floor book: Ice may not put frost on Fire's lava", not Light.may_take(ice, in_lava, 40.0)
		and Light.floor_taken_by_others(ice, in_lava))
	check("  but may in the dry middle while the room keeps %d%% free" % roundi(Light.SAFE_FLOOR * 100.0),
		Light.may_take(ice, middle, 40.0) and Light.floor_left(ice) >= Light.SAFE_FLOOR, Light.floor_left(ice))
	check("  and not a hazard so big it would leave less than that free",
		not Light.may_take(ice, middle, 200.0) and Light.floor_left(ice, middle, 200.0) < Light.SAFE_FLOOR,
		Light.floor_left(ice, middle, 200.0))
	me.global_position += in_lava - _arena_point(me)
	ice.set("_frost_clock", 0.0)
	ice.set("_wall_clock", 99.0)
	ice.set("_hail_clock", 99.0)
	var asked: Array = ice_boss.call("fight_targets")
	ice.call("_lead", 0.01)
	check("  the leader's frost round a player standing in the lava waits rather than land on it",
		not asked.is_empty() and (ice.get("frost") as Array).is_empty(), [asked.size(), (ice.get("frost") as Array).size()])
	Light.everywhere = true

	# THE WAVE'S PACE: a partner in the fight stretches the arena's clocks.
	var stub := GDScript.new()
	stub.source_code = "extends Node2D\nfunc in_fight() -> bool:\n\treturn true\n"
	stub.reload()
	me.global_position += middle - _arena_point(me)
	var pace_was: float = float(ice_boss.call("wave_pace"))
	var partner: Node2D = stub.new()
	partner.add_to_group(BossScript.BOSS_GROUP)
	world.add_child(partner)
	partner.global_position = middle
	ice.set("_frost_clock", 0.0)
	ice.call("_lead", 0.01)
	var clock: float = float(ice.get("_frost_clock"))
	var want: float = float(Ice.FROST_GAP[0]) * (pace_was + BossScript.WAVE_PACE)
	check("one more partner in the fight stretches the arena's clocks by the wave's pace (frost every %.2f s, was %.2f)" % [want, float(Ice.FROST_GAP[0]) * pace_was],
		absf(clock - want) < 0.05, clock)
	partner.queue_free()
	await get_tree().process_frame
	ice.set("_frost_clock", 0.0)
	ice.call("_lead", 0.01)
	check("  and it goes back when that partner goes", absf(float(ice.get("_frost_clock")) - float(Ice.FROST_GAP[0]) * pace_was) < 0.05,
		ice.get("_frost_clock"))

	# ONE HIT: two arenas never both hit you in the same moment.
	me.remove_meta(&"arena_hit")
	me.taken.clear()
	fire.call("_hit", me, Fire.VENT_SHARE, "vent", _arena_point(me))
	ice.call("_land", _arena_point(me))
	Hits.take()
	check("a hit from one arena, then another's at once: only the first lands", me.taken.size() == 1
		and int(me.taken[0][1]) == Element.Type.FIRE, me.taken)
	fire.call("_hit", me, Fire.POOL_SHARE, "lava pool", _arena_point(me))
	Hits.take()
	check("  one arena's own hits keep their own clocks", me.taken.size() == 2, me.taken)
	me.set_meta(&"arena_hit", [Time.get_ticks_msec() - int(Light.HIT_GAP * 1000.0) - 10, fire.get_instance_id()])
	ice.call("_land", _arena_point(me))
	Hits.take()
	check("  and %.2f s later the other's lands" % Light.HIT_GAP, me.taken.size() == 3
		and int(me.taken[2][1]) == Element.Type.ICE, me.taken)

	# THE PARTNER LEAVES: Fire alone again, the lava back to the dirt square.
	ice_boss.set("_dying", true)
	for k in 8:
		fire.call("_process", 0.5)
	dry = fire.call("dry")
	check("Fire's partner falls: the lava creeps back to the dirt square",
		Light.partners(fire_boss) == 0 and absf(dry.get_area() / room.get_area() - Fire.LAVA_KEEP.x * Fire.LAVA_KEEP.y) < 0.01,
		dry.get_area() / room.get_area())
	check("  and alone, the floor book asks nothing of an arena", Light.may_take(fire, in_lava, 40.0))

	# WALKING OUT: a boss let out of its gate attacks after WALK_OUT_SECONDS.
	fire_boss.set("gated", true)
	fire_boss.call("_physics_process", 0.016)
	fire_boss.set("gated", false)
	fire_boss.call("_physics_process", 0.016)
	fire_boss.set("_erupted_this_cast", true)
	fire_boss.call("_trigger_attack")
	check("a boss let out of its gate makes no attack for %.0f s while it steps out" % BossScript.WALK_OUT_SECONDS,
		bool(fire_boss.call("walking_out")) and bool(fire_boss.get("_erupted_this_cast")))
	fire_boss.call("_physics_process", BossScript.WALK_OUT_SECONDS)
	check("  and then it may", not bool(fire_boss.call("walking_out")))
	Light.everywhere = false
	world.queue_free()
	await get_tree().process_frame

	# ONE GATE AT A TIME.
	var W := Element.Type
	var gauntlet: Node2D = _gauntlet_of([[1, W.LIGHT], [2, W.WIND], [2, W.WATER], [3, W.FIRE], [3, W.ICE], [3, W.EARTH]], false)
	check("the gauntlet orders a wave's gates: Water then Wind; Ice, Earth, then Fire",
		Gauntlet.ordered([_gate_of(gauntlet, W.FIRE), _gate_of(gauntlet, W.EARTH), _gate_of(gauntlet, W.ICE)]).map(func(g): return int(g.element))
			== [W.ICE, W.EARTH, W.FIRE]
		and Gauntlet.ordered([_gate_of(gauntlet, W.WIND), _gate_of(gauntlet, W.WATER)]).map(func(g): return int(g.element)) == [W.WATER, W.WIND])
	check("  wave one's gate is open from the start, with no banner", _gate_of(gauntlet, W.LIGHT).opened
		and str(gauntlet.call("banner_text")) == "")
	(_gate_of(gauntlet, W.LIGHT).get_node("boss") as GateBoss).died.emit()
	await get_tree().create_timer(0.15).timeout
	var water: GateStub = _gate_of(gauntlet, W.WATER)
	var wind: GateStub = _gate_of(gauntlet, W.WIND)
	check("wave two opens on Water alone, and says so", water.opened and not wind.opened and wind.warned == 0.0
		and str(gauntlet.call("banner_text")) == "Wave 2: Water", [water.opened, wind.opened, gauntlet.call("banner_text")])
	for k in 20:
		gauntlet.call("_process", 1.0)
	check("  Wind waits while Water is in its phase one (20 s of fighting)", not wind.opened and wind.warned == 0.0)
	(water.get_node("boss") as GateBoss).phase_now = 1
	gauntlet.call("_process", 0.01)
	check("Water reaches its phase two: Wind's gate warns for %.0f s and the banner says it joins" % Gauntlet.WARN_SECONDS,
		wind.warned == Gauntlet.WARN_SECONDS and not wind.opened and str(gauntlet.call("banner_text")) == "Wind joins the fight",
		[wind.warned, gauntlet.call("banner_text")])
	gauntlet.call("_process", Gauntlet.WARN_SECONDS - 0.1)
	var early: bool = wind.opened
	gauntlet.call("_process", 0.2)
	check("  and opens when the warning is over", not early and wind.opened)
	(water.get_node("boss") as GateBoss).died.emit()
	(wind.get_node("boss") as GateBoss).died.emit()
	await get_tree().create_timer(0.15).timeout
	var ice_gate: GateStub = _gate_of(gauntlet, W.ICE)
	var earth_gate: GateStub = _gate_of(gauntlet, W.EARTH)
	var fire_gate: GateStub = _gate_of(gauntlet, W.FIRE)
	check("wave three opens on Ice alone", ice_gate.opened and not earth_gate.opened and not fire_gate.opened)
	for k in 29:
		gauntlet.call("_process", 1.0)
	var waited: bool = earth_gate.warned == 0.0
	gauntlet.call("_process", 1.1)
	check("  after %.0f s of Ice fighting in its phase one, Earth is let out anyway" % Gauntlet.RELEASE_SECONDS,
		waited and earth_gate.warned == Gauntlet.WARN_SECONDS)
	gauntlet.call("_process", Gauntlet.WARN_SECONDS + 0.1)
	(earth_gate.get_node("boss") as GateBoss).fighting = false
	for k in 40:
		gauntlet.call("_process", 1.0)
	check("  the clock counts only fighting: nobody near Earth for 40 s and Fire waits", earth_gate.opened and fire_gate.warned == 0.0)
	(earth_gate.get_node("boss") as GateBoss)._dying = true
	gauntlet.call("_process", 0.01)
	check("Earth falls before its phase two: Fire is let out at once (warned %.1f s)" % Gauntlet.WARN_ON_FALL,
		fire_gate.warned == Gauntlet.WARN_ON_FALL and int(gauntlet.call("waiting")) == 0)
	check("  the leader says how many are out, for its party", gauntlet.call("net_released") == [3, 3])
	gauntlet.queue_free()

	# A PARTY: the follower opens what the leader says, never on its own.
	var follower: Node2D = _gauntlet_of([[1, W.LIGHT], [2, W.WIND], [2, W.WATER], [3, W.FIRE], [3, W.ICE], [3, W.EARTH]], true)
	follower.call("net_jump_to", 2, 1)
	water = _gate_of(follower, W.WATER)
	wind = _gate_of(follower, W.WIND)
	(water.get_node("boss") as GateBoss).phase_now = 2
	for k in 40:
		follower.call("_process", 1.0)
	check("a follower catching up opens the leader's first gate of the wave, and never lets the next out itself",
		_gate_of(follower, W.LIGHT).opened and water.opened and not wind.opened and wind.warned == 0.0)
	follower.call("net_release_to", 2, 2)
	check("  told the leader let Wind out, it warns as the leader's did", wind.warned == Gauntlet.WARN_SECONDS
		and str(follower.call("banner_text")) == "Wind joins the fight")
	follower.call("net_jump_to", 3, 2)
	check("  and caught up to wave three with two out: Ice and Earth open at once, Fire still shut",
		_gate_of(follower, W.ICE).opened and _gate_of(follower, W.EARTH).opened and not _gate_of(follower, W.FIRE).opened
		and wind.opened)
	check("the wire: \"rel\" is [wave, let out]; another wave's or none reads unsaid",
		Sync.rel_for({"rel": [3, 2]}, 3) == 2 and Sync.rel_for({"rel": [2, 2]}, 3) == -1 and Sync.rel_for({}, 3) == -1)
	follower.queue_free()
	await get_tree().process_frame
	print("  (when bosses fight together: done)")


func _test_the_elements_mix() -> void:
	section("THE ELEMENTS MIX - ONE PHASE THREE, THAW, STEAM, POCKET, SHATTER (0.144.0)")
	# The owner: "the main thing we need is elements to mix also", "there is
	# a lot going on with 3 bosses", and "lets build them all".
	const Light := preload("res://src/enemies/lightarena.gd")
	const Ice := preload("res://src/enemies/icearena.gd")
	const Earth := preload("res://src/enemies/eartharena.gd")
	const FX := preload("res://src/characters/statuseffects.gd")
	const Hits := preload("res://src/shared/hitsource.gd")

	var origin := Vector2(-44000, -44000)
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
	var me := ArenaDummy.new()
	world.add_child(me)
	me.global_position = origin + Vector2(0, 40)
	var fx: Node = FX.attach(me)
	var bosses: Array = []
	for pair in [["fireboss", Vector2(175, -172)], ["iceboss", Vector2(-175, -172)], ["earthboss", Vector2(0, -190)]]:
		var b: Node2D = (load("res://scene/enemy/%s.tscn" % pair[0]) as PackedScene).instantiate()
		b.position = origin + (pair[1] as Vector2)
		world.add_child(b)
		bosses.append(b)
	await get_tree().process_frame
	Light.everywhere = true
	var arenas: Array = []
	for b in bosses:
		(b as Node).process_mode = Node.PROCESS_MODE_DISABLED
		b.call("_keep_arena", 1.0)
		arenas.append(b.call("arena"))
	Light.everywhere = false
	if arenas.has(null):
		check("three loose bosses make three arenas", false, arenas)
		world.queue_free()
		return
	for a in arenas:
		(a as Node).set_process(false)
	var fire: Node2D = arenas[0]
	var ice: Node2D = arenas[1]
	var earth: Node2D = arenas[2]
	(Light._said as Array).clear()

	# ONE BOSS IN PHASE THREE.
	for b in bosses:
		b.set("hp", int(float(b.get("max_hp")) * 0.2))
	var phases: Array = []
	for a in arenas:
		phases.append(Light.arena_phase(a))
	check("all three bosses in phase three: only the first arena plays it, the others hold at phase two",
		phases == [2, 1, 1], phases)
	bosses[0].set("_dying", true)
	fire.call("_process", 0.01)
	var next: Array = [Light.arena_phase(ice), Light.arena_phase(earth)]
	check("  it falls, and the next takes phase three", next == [2, 1], next)
	bosses[0].set("_dying", false)
	bosses[0].set("gated", true)
	bosses[1].set("gated", true)
	var alone: int = Light.arena_phase(earth)
	bosses[0].set("gated", false)
	bosses[1].set("gated", false)
	check("  alone, a boss plays its own phase three as ever", alone == 2, alone)

	# THAW: frost by a burning pool melts into a puddle that soaks.
	var pool_at: Vector2 = origin + Vector2(-120, 60)
	(fire.get("pools") as Array).append([pool_at, 0.0])
	fire.set("_ending", -1.0)
	ice.call("add_frost", pool_at + Vector2(10, 0), 40.0)
	ice.call("_age", Ice.FROST_FORM)
	var patch: Array = (ice.get("frost") as Array)[0]
	check("THAW: frost by a burning pool melts into a puddle, and says so", bool(patch[3])
		and (Light._said as Array).size() == 1, [patch, (Light._said as Array).size()])
	me.global_position += (pool_at + Vector2(10, 0)) - _arena_point(me)
	fx.call("clear_all")
	ice.set("_chill_left", 0.0)
	ice.call("_on_you", 0.01)
	var started: Array = fx.get("started")
	check("  in it you are soaked, not skidding or chilled", started.has(FX.SOAKED) and not started.has(FX.CHILL)
		and not bool(ice.call("on_frost", _arena_point(me))), started)

	# STEAM: hail on a pool bursts into a cloud and hurts nobody.
	me.taken.clear()
	me.remove_meta(&"arena_hit")
	ice.call("_land", _arena_point(me))
	Hits.take()
	check("STEAM: hail landing on a pool is a cloud of steam, not a hit", me.taken.is_empty()
		and (ice.get("steam") as Array).size() == 1 and bool(ice.call("in_steam", _arena_point(me))), me.taken)
	ice.call("_land", _arena_point(me) + Vector2(10, 0))
	check("  more hail there swells the same cloud", (ice.get("steam") as Array).size() == 1)
	ice.call("_age", Ice.STEAM_LIFE)
	check("  and it clears", (ice.get("steam") as Array).is_empty())

	# POCKET: a box risen in the lava holds it back.
	fire.set("lava", 1.0)
	var room: Rect2 = fire.get("_room")
	var in_the_lava: Vector2 = room.position + Vector2(70, room.size.y * 0.5)
	var covered: bool = bool(fire.call("lava_covers", in_the_lava)) and bool(fire.call("in_lava", in_the_lava))
	var said: int = (Light._said as Array).size()
	earth.call("add_box", in_the_lava)
	earth.call("_age", Earth.FAULT_WARN)
	var pocket: Vector2 = ((earth.get("faults") as Array)[0] as Array)[0]
	check("POCKET: a spike box risen in the lava holds it back - inside it is dry - and says so",
		covered and bool(fire.call("lava_covers", pocket)) and not bool(fire.call("in_lava", pocket))
		and not bool(fire.call("takes_floor", pocket)) and (Light._said as Array).size() == said + 1
		and (fire.call("pockets") as Array).size() == 1, [covered, (Light._said as Array).size() - said])
	earth.call("_age", Earth.FAULT_LIFE)
	check("  and when the box sinks the lava comes back", bool(fire.call("in_lava", pocket)))

	# SHATTER: a rock on an ice wall breaks it.
	var wall_at: Vector2 = origin + Vector2(150, 80)
	ice.call("add_wall", wall_at, 0.0, 1)
	ice.call("_age", Ice.WALL_WARN + 0.01)
	var wall: Node = (ice.get("walls") as Array)[0]
	var stood: bool = bool(wall.call("stands"))
	said = (Light._said as Array).size()
	earth.call("_land", wall_at + Vector2(0, 6))
	check("SHATTER: the Earth boss's rock on an ice wall breaks it, a door early, and says so",
		stood and bool(wall.get("broken")) and (Light._said as Array).size() == said + 1, [stood, wall.get("broken")])

	# ONE MIX IN ONE PLACE.
	said = (Light._said as Array).size()
	var again: bool = Light.react(ice, wall_at + Vector2(20, 0), "Steam", Element.Type.WATER)
	check("one mix said in one place at a time: another word right there waits", not again
		and (Light._said as Array).size() == said)
	check("  and the readout marks a mix (+)", PerfOverlay.MARK_LETTERS.get(&"elements mix") == "+")
	(Light._said as Array).clear()
	world.queue_free()
	await get_tree().process_frame
	print("  (the elements mix: done)")


func _test_the_tide_and_the_wind() -> void:
	section("A TIDE YOU FEEL, AND WIND MEETS WATER - CREST, CURRENT, UPWIND, RAIN, SPRAY (0.144.0)")
	# The owner: "when water floods the land feels like nothing happens", and
	# of the mixes, "lets build them all".
	const Light := preload("res://src/enemies/lightarena.gd")
	const Water := preload("res://src/enemies/waterarena.gd")
	const Wind := preload("res://src/enemies/windarena.gd")
	const FX := preload("res://src/characters/statuseffects.gd")
	const Hits := preload("res://src/shared/hitsource.gd")

	var origin := Vector2(-48000, -48000)
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
	var me := ArenaDummy.new()
	world.add_child(me)
	me.global_position = origin + Vector2(0, 40)
	var fx: Node = FX.attach(me)
	var water_boss: Node2D = (load("res://scene/enemy/waterboss.tscn") as PackedScene).instantiate()
	water_boss.position = origin + Vector2(-175, -172)
	world.add_child(water_boss)
	await get_tree().process_frame
	water_boss.process_mode = Node.PROCESS_MODE_DISABLED
	Light.everywhere = true
	water_boss.call("_keep_arena", 1.0)
	var water: Node2D = water_boss.call("arena")
	if water == null:
		check("the Water boss makes its arena", false)
		Light.everywhere = false
		world.queue_free()
		return
	water.set_process(false)
	(Light._said as Array).clear()

	# THE CREST: alone, a tide from the left; standing where its front passes.
	var room: Rect2 = water.get("_room")
	water.call("start_tide", 0, 2, 1.0)
	water.call("_process", Water.TIDE_WARN + Water.TIDE_IN * 0.5)
	var front: float = (water.call("flood") as Rect2).end.x
	me.global_position += Vector2(front - 6.0, room.get_center().y) - _arena_point(me)
	me.taken.clear()
	fx.call("clear_all")
	me.remove_meta(&"arena_hit")
	water.set("_soak_left", 0.0)
	water.call("_wet", 0.01)
	Hits.take()
	var started: Array = fx.get("started")
	check("THE CREST: caught by the water's front coming in, you are hit, soaked and thrown inland",
		me.taken == [[roundi(1000.0 * Water.CREST_SHARE), Element.Type.WATER]] and started.has(FX.SOAKED)
		and float(fx.get("shove_left")) > 0.0, [me.taken, started])
	me.taken.clear()
	me.remove_meta(&"arena_hit")
	water.call("_wet", 0.01)
	Hits.take()
	check("  once a tide", me.taken.is_empty(), me.taken)
	water.call("_process", Water.TIDE_IN)
	fx.call("clear_all")
	water.call("_wet", 0.01)
	var along: Vector2 = fx.get("drift_velocity")
	check("THE CURRENT: in the water alone you are carried along it", float(fx.get("drift_left")) > 0.0
		and absf(along.length() - Water.CURRENT) < 0.5 and absf(along.x) < 0.5, along)
	check("  and wading is slower (x%.2f)" % FX.WADE_SCALE, FX.WADE_SCALE == 0.55 and float(fx.get("wade_left")) > 0.0)

	# WIND MEETS WATER.
	var wind_boss: Node2D = (load("res://scene/enemy/windboss.tscn") as PackedScene).instantiate()
	wind_boss.position = origin + Vector2(175, -172)
	world.add_child(wind_boss)
	await get_tree().process_frame
	wind_boss.process_mode = Node.PROCESS_MODE_DISABLED
	wind_boss.call("_keep_arena", 1.0)
	var wind: Node2D = wind_boss.call("arena")
	if wind == null:
		check("the Wind boss makes its arena beside it", false)
		Light.everywhere = false
		world.queue_free()
		return
	wind.set_process(false)
	# UPWIND: the wind blows to the left, so the tide comes from the right.
	wind.set("angle_to", PI)
	wind.set("angle", PI)
	water.call("_process", 30.0)
	water.set("_next_tide", 0.0)
	water.set("_look_left", 0.0)
	water.call("_lead", 0.01)
	check("UPWIND: with the Wind boss here, the tide comes from where the wind blows from, and further",
		int(water.get("side")) == 1 and absf(float(water.get("tide_depth")) - minf(float(Water.TIDE_DEPTH[0]) * Water.UPWIND_DEPTH, Water.TIDE_DEEPEST)) < 0.001,
		[water.get("side"), water.get("tide_depth")])
	check("  (the side the wind comes from, each way)", Water.upwind_side(Vector2.RIGHT) == 0 and Water.upwind_side(Vector2.LEFT) == 1
		and Water.upwind_side(Vector2.DOWN) == 2 and Water.upwind_side(Vector2.UP) == 3)
	# DRAGGED: in the water the wind carries you harder, and the current stands aside.
	water.call("_process", Water.TIDE_WARN + Water.TIDE_IN)
	var wet: Rect2 = water.call("flood")
	me.global_position += wet.get_center() - _arena_point(me)
	fx.call("clear_all")
	wind.set("phase", 0)
	wind.call("_carry", Vector2.LEFT)
	var dragged: Vector2 = fx.get("drift_velocity")
	check("DRAGGED: in the water the wind carries you %.1f times as hard" % Wind.WET_DRIFT,
		absf(dragged.length() - float(Wind.WIND_DRIFT[0]) * Wind.WET_DRIFT) < 0.5, dragged)
	# SPRAY: a gust through the water.
	var said: int = (Light._said as Array).size()
	wind.call("add_gust", _arena_point(me), PI)
	var gust: Array = (wind.get("gusts") as Array).back()
	gust[2] = Wind.GUST_WARN
	fx.call("clear_all")
	me.taken.clear()
	me.remove_meta(&"arena_hit")
	wind.call("_blow", gust)
	gust[3] = true
	Hits.take()
	check("SPRAY: a gust across the water throws spray down its lane, soaks you as it hits, and says so",
		bool(gust[4]) and me.taken.size() == 1 and (fx.get("started") as Array).has(FX.SOAKED)
		and (Light._said as Array).size() >= said + 1, [gust, me.taken])
	# RAIN: the tornado over the standing water.
	(Light._said as Array).clear()
	wind.set("twister", wet.get_center())
	var was_age: float = float(water.get("tide_age"))
	water.call("_lead_rain")
	check("RAIN: the tornado over the water lifts it - it rains, the water goes out, and it says so",
		float(water.get("rain_left")) == Water.RAIN_SECONDS and float(water.get("tide_age")) >= Water.TIDE_WARN + Water.TIDE_IN + Water.TIDE_HOLD
		and was_age < Water.TIDE_WARN + Water.TIDE_IN + Water.TIDE_HOLD and (Light._said as Array).size() == 1)
	me.global_position += Vector2(room.get_center().x, room.position.y + 30.0) - _arena_point(me)
	fx.call("clear_all")
	water.set("_soak_left", 0.0)
	water.call("_wet", 0.01)
	check("  in the rain you are soaked out of the water too", (fx.get("started") as Array).has(FX.SOAKED))
	water.set("rain_left", Water.RAIN_SECONDS - 0.5)
	water.call("_show_rain")
	check("  and it falls on the card over the room", (water.get_node("rain") as CanvasItem).visible)
	water.call("hear", {"h": "rain", "x": wet.get_center().x, "y": wet.get_center().y})
	check("  a follower rains when the leader says", float(water.get("rain_left")) == Water.RAIN_SECONDS)
	(Light._said as Array).clear()
	Light.everywhere = false
	world.queue_free()
	await get_tree().process_frame
	print("  (the tide and the wind: done)")


func _test_the_mirrors_shield() -> void:
	section("THE MIRRORS SHIELD THE BOSS - BREAK THEM TO HURT IT (0.144.0)")
	# The owner: "mirrors feel like they have no objective other then
	# reflecting particles"; of the two ways, the shield.
	const Light := preload("res://src/enemies/lightarena.gd")
	var origin := Vector2(-52000, -52000)
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
	var boss: Node2D = (load("res://scene/enemy/lightboss.tscn") as PackedScene).instantiate()
	boss.position = origin + Vector2(0, -120)
	world.add_child(boss)
	await get_tree().process_frame
	boss.process_mode = Node.PROCESS_MODE_DISABLED
	Light.everywhere = true
	boss.call("_keep_arena", 1.0)
	var arena: Node2D = boss.call("arena")
	Light.everywhere = false
	if arena == null:
		check("the Light Keeper makes its arena", false)
		world.queue_free()
		return
	arena.set_process(false)
	var standing: int = int(arena.call("standing"))
	var before: int = int(boss.get("hp"))
	boss.call("take_damage", 100, Element.Type.FIRE)
	var took: int = before - int(boss.get("hp"))
	check("four mirrors standing shield the Light Keeper: a hit of 100 takes %d" % roundi(100.0 * (1.0 - Light.MIRROR_SHIELD * 4)),
		standing == 4 and took == roundi(100.0 * (1.0 - Light.MIRROR_SHIELD * 4)), [standing, took])
	arena.call("break_pane", 0, true)
	arena.call("break_pane", 1, true)
	before = int(boss.get("hp"))
	boss.call("take_damage", 100, Element.Type.FIRE)
	took = before - int(boss.get("hp"))
	check("  break two and it takes %d" % roundi(100.0 * (1.0 - Light.MIRROR_SHIELD * 2)),
		int(arena.call("standing")) == 2 and took == roundi(100.0 * (1.0 - Light.MIRROR_SHIELD * 2)), took)
	boss.set("_net_applying_remote", true)
	before = int(boss.get("hp"))
	boss.call("take_damage", 100, Element.Type.FIRE)
	took = before - int(boss.get("hp"))
	boss.set("_net_applying_remote", false)
	check("  a party member's hit arrives already cut by their game, and is not cut twice", took == 100, took)
	var beams: Node2D = arena.get_node("beams")
	check("  each standing mirror's beam is drawn to the boss, above everyone and under the orbs",
		beams.z_index == Light.BEAM_Z and not beams.z_as_relative and Light.BEAM_Z < 20)
	arena.call("break_pane", 2, true)
	arena.call("break_pane", 3, true)
	before = int(boss.get("hp"))
	boss.call("take_damage", 100, Element.Type.FIRE)
	check("  all broken, every hit lands whole", before - int(boss.get("hp")) == 100)
	world.queue_free()
	await get_tree().process_frame
	print("  (the mirrors shield: done)")


# =============================================================================
# A QUICK TAP ON THE STICK'S SIDE STRIKES THERE (0.145.0)
# =============================================================================
# The owner, on a phone: "i have to tap left of character to attack and it
# hits joystick instead". A thumb on the left that lifts quickly and walked
# nobody is a tap on the world; a second finger there while a thumb holds the
# stick is a finger on the world.
func _test_a_tap_on_the_left_strikes() -> void:
	section("A TAP ON THE LEFT STRIKES THERE - the stick's side, a quick tap that walked nobody, a second finger (0.145.0)")
	const PadScript := preload("res://src/ui/touchpad.gd")
	const TouchScript := preload("res://src/systems/touchcontrols.gd")
	var was_active: bool = TouchControls.active
	TouchControls.set_active(true)
	TouchControls.clear()
	var body := Node2D.new()
	body.add_to_group(&"player")
	add_child(body)
	var holder := Control.new()
	holder.position = Vector2(0, 100)
	add_child(holder)
	var stick = PadScript.Stick.new()
	holder.add_child(stick)
	stick.place(Rect2(0, 0, 500, 400), Vector2(80, 300), 50.0, 21.0)
	var at_screen := func(local: Vector2) -> Vector2:
		return stick.get_global_transform_with_canvas() * local

	var touch := func(index: int, local: Vector2, down: bool) -> void:
		var event := InputEventScreenTouch.new()
		event.index = index
		event.position = local
		event.pressed = down
		stick._gui_input(event)
	var slide := func(index: int, local: Vector2) -> void:
		var event := InputEventScreenDrag.new()
		event.index = index
		event.position = local
		stick._gui_input(event)

	# A quick tap that went nowhere: one attack, aimed where it landed.
	touch.call(0, Vector2(300, 120), true)
	touch.call(0, Vector2(302, 121), false)
	var tapped: bool = bool(TouchControls.get("_attack_tap"))
	var aimed: Vector2 = TouchControls.get("_world_screen")
	TouchControls._latch_attack(null)
	var struck: bool = Input.is_action_pressed("attack")
	var aim_ticks: int = int(TouchControls.get("_world_aim_ticks"))
	TouchControls._latch_attack(null)
	check("a quick tap on the stick's side that walked nobody is an attack, aimed where it landed",
		tapped and struck and aimed.is_equal_approx(at_screen.call(Vector2(302, 121))) and aim_ticks > 0,
		[tapped, struck, aimed, aim_ticks])
	check("  once: the next frame lets go", not Input.is_action_pressed("attack"))
	check("  and the stick went back to rest, walking nobody", int(stick.finger) == -1 and TouchControls.stick == Vector2.ZERO
		and not TouchControls.stick_held)

	# Slid past the dead middle: the stick, no attack.
	TouchControls.clear()
	touch.call(0, Vector2(300, 120), true)
	slide.call(0, Vector2(300 + 50.0 * TouchScript.STICK_DEAD + 6.0, 120))
	var walked: bool = TouchControls.stick.length() >= TouchScript.STICK_DEAD
	touch.call(0, Vector2(300, 120), false)
	check("  a thumb that slid past the stick's dead middle walked, and is no attack - even slid back before it lifted",
		walked and not bool(TouchControls.get("_attack_tap")), walked)

	# Held too long: no attack.
	touch.call(0, Vector2(300, 120), true)
	stick.set("_landed_msec", Time.get_ticks_msec() - TouchScript.STRIKE_TAP_MSEC - 50)
	touch.call(0, Vector2(300, 120), false)
	check("  nor one held past STRIKE_TAP_MSEC (%d ms) - a thumb resting on the stick" % TouchScript.STRIKE_TAP_MSEC,
		not bool(TouchControls.get("_attack_tap")))

	# A second finger while a thumb holds the stick: on the world.
	touch.call(0, Vector2(100, 300), true)
	slide.call(0, Vector2(140, 300))
	touch.call(1, Vector2(420, 60), true)
	var second_on_world: bool = TouchControls.world_finger() == 1 \
		and (TouchControls.get("_world_screen") as Vector2).is_equal_approx(at_screen.call(Vector2(420, 60)))
	TouchControls._latch_attack(null)
	var second_attacks: bool = Input.is_action_pressed("attack")
	slide.call(1, Vector2(380, 80))
	var followed: bool = (TouchControls.get("_world_screen") as Vector2).is_equal_approx(at_screen.call(Vector2(380, 80)))
	var still_walking: bool = TouchControls.stick_held and TouchControls.stick.x > 0.5
	check("a second finger on the stick's side while a thumb holds it is a finger on the world: an attack aimed there",
		second_on_world and second_attacks, [TouchControls.world_finger(), TouchControls.get("_world_screen")])
	check("  aimed where it slides, and the stick walks on under the first thumb", followed and still_walking,
		[followed, still_walking, TouchControls.stick])
	touch.call(1, Vector2(380, 80), false)
	check("  lifted, it lets go of the world", TouchControls.world_finger() == -1)
	touch.call(1, Vector2(420, 60), true)
	stick.let_go()
	check("  and the stick let go lets go of both", TouchControls.world_finger() == -1 and int(stick.finger) == -1
		and int(stick.second) == -1)

	# A minigame's stick is over the world: a tap there is the knob, never a strike.
	TouchControls.clear()
	stick.mounted = true
	touch.call(0, Vector2(90, 300), true)
	touch.call(0, Vector2(90, 300), false)
	check("a minigame's mounted stick never strikes", not bool(TouchControls.get("_attack_tap")))
	stick.mounted = false

	# With nobody to attack with, nothing.
	body.remove_from_group(&"player")
	touch.call(0, Vector2(300, 120), true)
	touch.call(0, Vector2(300, 120), false)
	check("  nor does a tap with nobody to attack with", not bool(TouchControls.get("_attack_tap")))

	TouchControls.clear()
	holder.queue_free()
	body.queue_free()
	TouchControls.set_active(was_active)
	await get_tree().process_frame
	print("  (a tap on the left: done)")


# =============================================================================
# A PINCH ZOOMS THE MAP (0.145.0)
# =============================================================================
# The owner: "we also need zoom in and out of map with a pinch".
func _test_a_pinch_zooms_the_map() -> void:
	section("A PINCH ZOOMS THE MAP - two fingers zoom about the point between them, one drags (0.145.0)")
	WorldMap._terrain[_MAP_BIG] = {"image": Image.create_empty(40, 20, false, Image.FORMAT_RGBA8),
		"origin": Vector2i.ZERO, "size": Vector2i(40, 20), "tile": Vector2i(16, 16)}
	var map: Control = _MapScene.instantiate() as Control
	add_child(map)
	var picture: TextureRect = map.get_node("%mapview") as TextureRect
	map.set("_area", _MAP_BIG)
	picture.size = Vector2(400, 300)
	map.call("show_whole")
	var touch := func(index: int, at: Vector2, down: bool) -> void:
		var event := InputEventScreenTouch.new()
		event.index = index
		event.position = at
		event.pressed = down
		map.call("_on_view_input", event)
	var slide := func(index: int, at: Vector2, by: Vector2) -> void:
		var event := InputEventScreenDrag.new()
		event.index = index
		event.position = at
		event.relative = by
		map.call("_on_view_input", event)
	var map_at := func(view_point: Vector2) -> Vector2:
		return (view_point - (map.get("_offset") as Vector2)) / float(map.get("_fit"))

	# Spread from 100 apart to 200 apart about (200, 150): twice as close.
	touch.call(0, Vector2(150, 150), true)
	touch.call(1, Vector2(250, 150), true)
	var under_before: Vector2 = map_at.call(Vector2(200, 150))
	slide.call(0, Vector2(100, 150), Vector2(-50, 0))
	slide.call(1, Vector2(300, 150), Vector2(50, 0))
	var fit_in: float = float(map.get("_fit"))
	var under_after: Vector2 = map_at.call(Vector2(200, 150))
	check("two fingers spread on the map zoom it in by as much as they spread (10 -> 20 a tile)",
		is_equal_approx(fit_in, 20.0), fit_in)
	check("  about the point between them: the map under it stays under it",
		under_after.distance_to(under_before) < 0.05, [under_before, under_after])
	# Both move right together: the map moves with them, no zoom.
	var centre_before: Vector2 = map.get("_centre")
	slide.call(0, Vector2(120, 150), Vector2(20, 0))
	slide.call(1, Vector2(320, 150), Vector2(20, 0))
	var moved: Vector2 = (map.get("_centre") as Vector2) - centre_before
	check("  moved together, they move the map with them and zoom nothing",
		is_equal_approx(float(map.get("_fit")), 20.0) and is_equal_approx(moved.x, -1.0) and is_zero_approx(moved.y),
		[map.get("_fit"), moved])
	# Closed together: back out, never past the whole area.
	slide.call(0, Vector2(219, 150), Vector2(99, 0))
	slide.call(1, Vector2(221, 150), Vector2(-99, 0))
	check("  closed together, out again - no further than the whole area", is_equal_approx(float(map.get("_fit")), 10.0),
		map.get("_fit"))
	# A pinch is never a click on a pin.
	var travel: float = float(map.get("_press_travel"))
	touch.call(1, Vector2(221, 150), false)
	touch.call(0, Vector2(219, 150), false)
	check("  a pinch is never a click on a pin, and lifted, no finger is kept",
		travel > float(_MapCode.CLICK_SLACK) and (map.get("_fingers") as Dictionary).is_empty(), [travel, map.get("_fingers")])

	# One finger drags; its copied mouse motion moves nothing more.
	map.call("zoom_by", 2.0)
	touch.call(0, Vector2(200, 150), true)
	var held_centre: Vector2 = map.get("_centre")
	slide.call(0, Vector2(240, 150), Vector2(40, 0))
	var copy := InputEventMouseMotion.new()
	copy.device = InputEvent.DEVICE_ID_EMULATION
	copy.button_mask = MOUSE_BUTTON_MASK_LEFT
	copy.relative = Vector2(40, 0)
	map.set("_dragging", true)
	map.call("_on_view_input", copy)
	var one_moved: Vector2 = (map.get("_centre") as Vector2) - held_centre
	touch.call(0, Vector2(240, 150), false)
	check("one finger drags the map once - its copied mouse motion does not drag it again",
		is_equal_approx(one_moved.x, -2.0), one_moved)
	map.set("_dragging", false)
	touch.call(3, Vector2(10, 10), true)
	map.call("close")
	check("  and the map shut keeps no finger for the next time it opens",
		(map.get("_fingers") as Dictionary).is_empty())

	map.queue_free()
	WorldMap._terrain.erase(_MAP_BIG)
	await get_tree().process_frame
	print("  (a pinch zooms the map: done)")


# =============================================================================
# ATTACK GOES WHERE THE THUMB IS (0.145.1)
# =============================================================================
# The owner, once a tap on the left struck where it landed: "now attack is not
# moving to right side of screen ... attacking left works fine". The Attack
# thumb on the right aimed at the nearest monster or the character's facing.
func _test_attack_goes_where_the_thumb_is() -> void:
	section("ATTACK GOES WHERE THE THUMB IS - the right side's Attack aims where it lands and slides (0.145.1)")
	const PadScript := preload("res://src/ui/touchpad.gd")
	var was_active: bool = TouchControls.active
	TouchControls.set_active(true)
	TouchControls.clear()
	var body_script := GDScript.new()
	body_script.source_code = "extends Node2D\nfunc world_point_at(screen: Vector2) -> Vector2:\n\treturn screen * 2.0\n"
	body_script.reload()
	var body: Node2D = body_script.new()
	body.add_to_group(&"player")
	add_child(body)
	var holder := Control.new()
	holder.position = Vector2(640, 100)
	add_child(holder)
	var button = PadScript.PadButton.new()
	holder.add_child(button)
	button.place_floating(Rect2(0, 0, 600, 400), Rect2(0, 0, 52, 52), 34, 2.0)
	var heard: Array = []
	button.touched_at.connect(func(at: Vector2) -> void: heard.append(at))
	button.went_down.connect(TouchControls.press_attack)
	button.went_up.connect(TouchControls.release_attack)
	button.touched_at.connect(TouchControls.aim_attack_at)
	var press := InputEventScreenTouch.new()
	press.index = 1
	press.position = Vector2(400, 50)
	press.pressed = true
	button._gui_input(press)
	var landed: Vector2 = Vector2(1040, 150)
	check("the Attack thumb says where it landed on the screen", heard.size() == 1 and heard[0].is_equal_approx(landed), heard)
	TouchControls._latch_attack(body)
	check("  its press is an attack, aimed where it landed - not the nearest monster, not the facing",
		Input.is_action_pressed("attack") and (TouchControls.aim_for(body) as Vector2).is_equal_approx(landed * 2.0),
		TouchControls.aim_for(body))
	var slide := InputEventScreenDrag.new()
	slide.index = 1
	slide.position = Vector2(100, 300)
	button._gui_input(slide)
	TouchControls._physics_process(0.0)
	TouchControls._physics_process(0.0)
	TouchControls._physics_process(0.0)
	check("  held and slid, it aims where the thumb is now", (TouchControls.aim_for(body) as Vector2).is_equal_approx(Vector2(740, 400) * 2.0),
		TouchControls.aim_for(body))
	press.pressed = false
	button._gui_input(press)
	TouchControls._physics_process(0.0)
	TouchControls._physics_process(0.0)
	TouchControls._physics_process(0.0)
	TouchControls._aim_frame = -1
	# Not "null": in the whole suite an earlier section's monster may still be
	# near, and the nearest is aimed at then - which is right.
	var lifted_aim: Variant = TouchControls.aim_for(body)
	check("  lifted, it aims nowhere of its own - not where the thumb was",
		not bool(TouchControls.attack_aimed)
		and not (lifted_aim is Vector2 and (lifted_aim as Vector2).is_equal_approx(Vector2(740, 400) * 2.0)), lifted_aim)
	var pad: Control = PadScript.new()
	check("the pad's Attack is wired to it", pad.attack.touched_at.is_connected(TouchControls.aim_attack_at))
	pad.free()
	TouchControls.clear()
	holder.queue_free()
	body.queue_free()
	TouchControls.set_active(was_active)
	await get_tree().process_frame
	print("  (attack goes where the thumb is: done)")


# =============================================================================
# THIRTY ON A PHONE, AND THE READOUT JUDGES THE CAP (0.146.0)
# =============================================================================
# The owner, of a 16x stress test on his phone: "puts everything in red we are
# optimizing for 30fps now", then "lets fix phone because within 30 seconds
# my phone is hot".
func _test_thirty_on_a_phone() -> void:
	section("THIRTY ON A PHONE - no cap is 30 there, and the readout judges a frame against the cap in force (0.146.0)")
	const SettingsScript := preload("res://src/systems/settings.gd")
	const OverlayScript := preload("res://src/systems/perfoverlay.gd")
	check("a phone with no cap of its own draws 30 a second (it was 60), saver or not",
		SettingsScript.PHONE_FPS == 30 and SettingsScript.fps_cap_for(0, true, true, 0.0, false, true) == 30
		and SettingsScript.fps_cap_for(0, true, true, 0.0, true, true) == 30)
	check("  a cap the player picks is still theirs, and a computer is as it was",
		SettingsScript.fps_cap_for(60, true, true, 0.0, false, true) == 60
		and SettingsScript.fps_cap_for(0, true, true, 0.0, false, false) == 0)
	check("the readout judges against the cap when it is under 60, else 60",
		is_equal_approx(OverlayScript.target_fps(30), 30.0) and is_equal_approx(OverlayScript.target_fps(0), 60.0)
		and is_equal_approx(OverlayScript.target_fps(60), 60.0) and is_equal_approx(OverlayScript.target_fps(144), 60.0)
		and is_equal_approx(OverlayScript.target_fps(20), 20.0))
	var kept: Dictionary = Settings._values.duplicate()
	Settings._values["frame_cap"] = 0
	Settings._values["battery_saver"] = false
	var open_budget: float = PerfOverlay.budget_ms()
	Settings._values["battery_saver"] = true
	var saver_budget: float = PerfOverlay.budget_ms()
	var saver_hitch: float = PerfOverlay.hitch_ms()
	var frames: int = PerfOverlay._frames
	var hitches: int = PerfOverlay._hitches
	var on_time: int = PerfOverlay._on_time
	PerfOverlay._note_frame(1.0 / 30.0)
	PerfOverlay._note_frame(0.045)
	PerfOverlay._note_frame(0.055)
	var counted: Array = [PerfOverlay._frames - frames, PerfOverlay._hitches - hitches, PerfOverlay._on_time - on_time]
	var data: Dictionary = PerfOverlay.panel_data(Time.get_ticks_msec())
	Settings._values = kept
	check("  at 30 a frame's budget is 33.3 ms and a hitch is past 50; uncapped, 16.7 as ever",
		is_equal_approx(saver_budget, 1000.0 / 30.0) and is_equal_approx(saver_hitch, 50.0)
		and is_equal_approx(open_budget, 1000.0 / 60.0), [open_budget, saver_budget, saver_hitch])
	check("  a 33 ms frame at 30 is on time, not a hitch; 45 ms is late but no hitch; 55 ms is one",
		counted == [3, 1, 1], counted)
	check("  and the panel draws its colours and lines against that budget",
		is_equal_approx(float(data.get("budget", 0.0)), 1000.0 / 30.0) and is_equal_approx(float(data.get("hitch_ms", 0.0)), 50.0),
		[data.get("budget"), data.get("hitch_ms")])
	await get_tree().process_frame
	print("  (thirty on a phone: done)")


# =============================================================================
# A PHONE LEFT ALONE DRAWS LESS; PHYSICS CATCHES UP 2 TICKS (0.147.0)
# =============================================================================
# The owner, of his phone at the 16x stress test running hot: "lets built
# them", and "darza can manage no overheating in mobil play".
func _test_a_phone_left_alone() -> void:
	section("A PHONE LEFT ALONE DRAWS LESS - 8 s untouched is 15 a second; physics catches up 2 ticks on Light (0.147.0)")
	const SettingsScript := preload("res://src/systems/settings.gd")
	check("Light catches up at most 2 ticks a frame: a phone that falls behind slips, not spirals",
		SettingsScript.PHYSICS_CATCH_UP["light"] == 2 and SettingsScript.PHYSICS_CATCH_UP["smooth"] == 8)
	check("idle after IDLE_AFTER (8 s) untouched on a phone; never with a finger down, never on a computer",
		SettingsScript.idle_due(8.0, true, false) and not SettingsScript.idle_due(7.9, true, false)
		and not SettingsScript.idle_due(600.0, true, true) and not SettingsScript.idle_due(600.0, false, false))
	var was_shown: bool = PerfOverlay.is_shown()
	PerfOverlay.set_shown(false)
	var cap_before: int = Engine.max_fps
	Settings.pretend_idle_phone = true
	var now: int = Time.get_ticks_msec()
	Settings._last_rest_check_msec = now
	Settings._last_input_msec = now - 9000
	Settings.check_rest()
	var idle_cap: int = Engine.max_fps
	var idle_reason: String = Settings.held_reason()
	var idled: bool = Settings.is_idle()
	var rested: bool = Settings.is_resting()
	Settings.note_input()
	check("  9 s untouched: held at BACKGROUND_FPS (15), and the readout says why - no veil, no rest",
		idled and idle_cap == SettingsScript.BACKGROUND_FPS and idle_reason == "idle" and not rested,
		[idled, idle_cap, idle_reason, rested])
	check("  the next touch brings it back at once", not Settings.is_idle() and Engine.max_fps == cap_before
		and Settings.held_reason() != "idle", [Settings.is_idle(), Engine.max_fps, cap_before])
	TouchControls.stick_held = true
	now = Time.get_ticks_msec()
	Settings._last_rest_check_msec = now
	Settings._last_input_msec = now - 9000
	Settings.check_rest()
	var held_idle: bool = Settings.is_idle()
	var clock_reset: bool = Time.get_ticks_msec() - Settings._last_input_msec < 1000
	TouchControls.stick_held = false
	check("  a thumb resting on the stick is playing: no hold, and the idle clock starts again",
		not held_idle and clock_reset, [held_idle, clock_reset])
	Settings.pretend_idle_phone = false
	now = Time.get_ticks_msec()
	Settings._last_rest_check_msec = now
	Settings._last_input_msec = now - 9000
	Settings.check_rest()
	check("  and a computer left alone 9 s is not held", not Settings.is_idle())
	Settings.note_input()
	PerfOverlay.set_shown(was_shown)
	await get_tree().process_frame
	print("  (a phone left alone: done)")


# =============================================================================
# 5,000 SMALLER SLIMES, THE STEP IN PARTS (0.148.0)
# =============================================================================
# The owner: "4 players attacking with 5000 slimes i think that would be a
# massive showcase", "it would be more realistic if we made the slimes a bit
# smaller", and of two-thirds, "it will look absolutely insane".
func _test_five_thousand_smaller_slimes() -> void:
	section("5,000 SMALLER SLIMES - two-thirds the size, 5,000 for computers, the step moved in parts (0.148.0)")
	const SwarmScript := preload("res://src/world/endless/swarm.gd")
	const RunScript := preload("res://src/world/endless/endlessrun.gd")
	check("the crowd reaches 5,000 on a computer; a phone, and a party with one, still holds 1,000",
		SwarmScript.MOST == 5000 and RunScript.crowd_for(40, 4) == 5000 and RunScript.PHONE_CROWD == 1000)
	check("  two-thirds the size: at the game's 3x zoom an art pixel is two screen pixels, whole",
		is_equal_approx(SwarmScript.DRAW_SCALE * 3.0, 2.0) and is_equal_approx(SwarmScript.CELL, 16.0)
		and is_equal_approx(SwarmScript.ROOM, 10.0) and is_equal_approx(SwarmScript.PICTURE_TOP, 28.0))
	var o := Vector2(-64000, -64000)
	var arena := Rect2(o + Vector2(24, 34), Vector2(1488, 1334))
	var me := Node2D.new()
	me.add_to_group(&"player")
	add_child(me)
	var start := o + Vector2(760, 600)
	me.global_position = start
	# On a stopped clock (testrunner_10's _SWARM_CLOCK): the crowd's sway reads
	# the time, and the two would be read a moment apart.
	var stopped := GDScript.new()
	stopped.source_code = _SWARM_CLOCK
	stopped.reload()
	var pair: Array = []
	for k in 2:
		var swarm: Node2D = stopped.new()
		swarm.set("arena", arena)
		add_child(swarm)
		swarm.set_process(false)
		swarm.set_physics_process(false)
		pair.append(swarm)
	await get_tree().process_frame
	for swarm in pair:
		var slots: PackedInt32Array = swarm.call("take_slots", 2400)
		swarm.call("spawn_batch", 1, 4242, slots, PackedVector2Array([start]), 30.0, 1)
		swarm.set("_others_now", PackedVector2Array([start + Vector2(300, 0), start + Vector2(-260, 200)]))
	var whole: Node2D = pair[0]
	var parts: Node2D = pair[1]
	var same: bool = true
	for step in 40:
		whole.call("_step", start, true)
		parts.call("_begin_step", start, true)
		var third: int = ceili(float(int(parts.get("_chunk_end"))) / 3.0)
		parts.call("_move_some", third)
		parts.call("_move_some", third)
		parts.call("_move_some", third)
		parts.call("_end_step")
		if whole.get("px") != parts.get("px") or whole.get("py") != parts.get("py") \
				or whole.get("facing") != parts.get("facing") or int(whole.get("_touching")) != int(parts.get("_touching")):
			same = false
	check("a step moved in three parts lands every slime where the whole step does, to the bit (40 steps of 2,400)",
		same and int(whole.get("alive")) == 2400)
	# The game's frames: three parts at 60 a second, the whole at 30.
	parts.set("_step_left", 0.0)
	parts.set("_chunk_at", -1)
	parts.call("_process", 1.0 / 60.0)
	var under_way_60: bool = int(parts.get("_chunk_at")) > 0 and int(parts.get("_chunk_at")) < int(parts.get("_chunk_end"))
	var blend_before: float = float(parts.get("_since_write"))
	parts.call("_process", 1.0 / 60.0)
	parts.call("_process", 1.0 / 60.0)
	var done_60: bool = int(parts.get("_chunk_at")) == -1 and is_zero_approx(float(parts.get("_since_write")))
	parts.set("_step_left", 0.0)
	parts.call("_process", 1.0 / 30.0)
	var done_30: bool = int(parts.get("_chunk_at")) == -1
	check("  at 60 a second the step is spread over three frames and the picture written after the last; at 30, one frame (never slower)",
		under_way_60 and done_60 and done_30 and blend_before > 0.0, [under_way_60, done_60, done_30, blend_before])
	parts.set("_step_left", 0.0)
	parts.set("_chunk_at", -1)
	parts.call("_process", 1.0 / 60.0)
	parts.set("_step_left", -0.01)
	parts.call("_process", 1.0 / 60.0)
	check("  a frame that falls behind finishes the step under way at once", int(parts.get("_chunk_at")) == -1
		or int(parts.get("_chunk_at")) < int(parts.get("_chunk_end")))
	# ROOM IN PARTS TOO (0.150.1): the near ones' room is worked out with
	# their part, not all in the frame that starts the step.
	var amid := Vector2(float(parts.get("px")[0]), float(parts.get("py")[0]))
	parts.set("_chunk_at", -1)
	parts.call("_begin_step", amid, true)
	var near_n: int = int(parts.get("_near_n"))
	var third: int = ceili(float(int(parts.get("_high"))) / 3.0)
	parts.call("_move_some", third)
	var room_first: int = int(parts.get("_room_done"))
	parts.call("_move_some", third)
	parts.call("_move_some", third)
	parts.call("_end_step")
	check("  the near ones' room is worked out a part at a time (%d of %d after the first frame), all of it by the last"
		% [room_first, near_n], near_n > 100 and room_first > 0 and room_first < near_n
		and int(parts.get("_room_done")) == near_n, [room_first, near_n, int(parts.get("_room_done"))])
	for swarm in pair:
		swarm.queue_free()
	me.queue_free()
	await get_tree().process_frame
	print("  (5,000 smaller slimes: done)")


# =============================================================================
# UNDER BUDGET, AND STILL THE HORDE (0.149.0)
# =============================================================================
# The owner, of a boss's spikes standing round his warrior at stage 17:
# "character is behind wall", then "lets do what we can to keep my game under
# budget and still have this devastating power".

func _test_see_through_spikes_and_a_busy_computer() -> void:
	section("UNDER BUDGET, AND STILL THE HORDE (0.149.0): spikes in front of you see-through, a busy computer holds the crowd")
	const SpikeFx := preload("res://src/projectiles/spikefx.gd")
	# ---- the rule --------------------------------------------------------------------
	var at := Vector2(1000, 1000)
	check("a spike just below you, over your picture, covers you; one behind you, or off to the side, does not",
		SpikeFx.covers(at + Vector2(0, 30), 1.0, at) and not SpikeFx.covers(at + Vector2(0, 10), 1.0, at)
		and not SpikeFx.covers(at + Vector2(0, -10), 1.0, at) and not SpikeFx.covers(at + Vector2(90, 30), 1.0, at)
		and not SpikeFx.covers(at + Vector2(0, 70), 1.0, at) and SpikeFx.covers(at + Vector2(0, 70), 2.0, at))
	# ---- real spikes -------------------------------------------------------------------
	var container := Node2D.new()
	container.y_sort_enabled = true
	add_child(container)
	var fx: Node2D = SpikeFx.of(container)
	var me := Node2D.new()
	add_child(me)
	me.global_position = at
	fx.set("see_for", me)
	var scene: PackedScene = load("res://scene/projectiles/icebossprojectile.tscn")
	var spikes: Array = []
	for offset in [Vector2(0, 30), Vector2(0, -10), Vector2(120, 30)]:
		var spike: Node2D = scene.instantiate()
		spike.set("telegraph_seconds", 5.0)
		container.add_child(spike)
		spike.global_position = at + offset
		spike.call("telegraph_over")
		spikes.append(spike)
	for i in 4:
		fx.call("_process", 0.1)
	var alphas: Array = spikes.map(func(s): return snappedf((s.get("anim") as CanvasItem).modulate.a, 0.01))
	check("an erupted spike in front of you fades to SEE_THROUGH; the one behind you and the one beside you stay whole",
		int(fx.call("standing_count")) == 3 and is_equal_approx(alphas[0], SpikeFx.SEE_THROUGH)
		and alphas[1] == 1.0 and alphas[2] == 1.0, alphas)
	me.global_position = at + Vector2(-300, 0)
	for i in 4:
		fx.call("_process", 0.1)
	check("  step out from behind it and it is whole again",
		is_equal_approx((spikes[0].get("anim") as CanvasItem).modulate.a, 1.0))
	var shader: String = FileAccess.get_file_as_string("res://src/shared/hearth_warm.gdshader")
	check("  the spikes' colour shader keeps a fade (it set COLOR from the texture alone, so a fade did nothing)",
		shader.find("float faded = COLOR.a;") != -1 and shader.find("float faded = COLOR.a;") < shader.find("texture(TEXTURE, UV)")
		and shader.find("COLOR.a *= faded;") > shader.find("COLOR.rgb *= brightness;"))
	for spike in spikes:
		spike.queue_free()
	await get_tree().process_frame
	fx.call("_process", 0.1)
	check("  a spike gone is dropped from the standing", int(fx.call("standing_count")) == 0)
	container.queue_free()
	me.queue_free()
	# ---- a busy computer --------------------------------------------------------------
	const RunScript := preload("res://src/world/endless/endlessrun.gd")
	const PartyScript := preload("res://src/world/endless/endlessparty.gd")
	var judge: Node = RunScript.new()
	var budget: float = 1000.0 / 60.0
	for i in 120:
		judge.call("note_frame", 1.0 / 60.0, budget)
	var on_time: bool = not bool(judge.get("busy"))
	for i in 30:
		judge.call("note_frame", 0.05, budget)
	var busy_at_1_5s: bool = bool(judge.get("busy"))
	for i in 30:
		judge.call("note_frame", 0.05, budget)
	var busy_at_3s: bool = bool(judge.get("busy"))
	for i in 120:
		judge.call("note_frame", 1.0 / 60.0, budget)
	var still_at_2s: bool = bool(judge.get("busy"))
	# The average takes about half a second to come back under, then three
	# seconds within it.
	for i in 120:
		judge.call("note_frame", 1.0 / 60.0, budget)
	check("frames on time are not busy; two seconds of 50 ms frames are, and three seconds back on time are not",
		on_time and not busy_at_1_5s and busy_at_3s and still_at_2s and not bool(judge.get("busy")),
		[on_time, busy_at_1_5s, busy_at_3s, still_at_2s])
	judge.free()
	# The fill: held while busy, filling again once not.
	var run: Node = RunScript.new()
	add_child(run)
	await get_tree().process_frame
	run.set("state", 1)
	run.set("stage", 1)
	run.set("elapsed", 1.0)
	run.set("_elite_left", 999.0)
	run.set("busy", true)
	for i in 20:
		run.call("_process", 0.05)
	var held_alive: int = int(run.get("swarm").get("alive"))
	run.set("busy", false)
	for i in 20:
		run.call("_process", 0.05)
	var filled_alive: int = int(run.get("swarm").get("alive"))
	check("  busy, the crowd is not refilled; not busy, it fills (no slime is taken away)",
		held_alive == 0 and filled_alive > 0, [held_alive, filled_alive])
	run.set("busy", false)
	# A party: any game that says so holds everybody's crowd.
	var party: Node = PartyScript.new()
	var link := Node.new()
	var stub := GDScript.new()
	stub.source_code = "extends Node\nfunc runs() -> bool:\n\treturn true\nfunc sharers() -> int:\n\treturn 1\nfunc leader_for(_a) -> int:\n\treturn 1\nfunc my_id() -> int:\n\treturn 1\nfunc remotes() -> Dictionary:\n\treturn {7: true}\n"
	stub.reload()
	link.set_script(stub)
	party.set("link", link)
	run.set("party", party)
	party.set("_members", {7: [1, 0, 0, 0]})
	var calm_party: bool = bool(run.call("held_for_busy"))
	party.set("_members", {7: [1, 0, 0, 1]})
	var busy_party: bool = bool(run.call("held_for_busy"))
	party.set("_members", {7: [1, 0, 0]})
	var old_game: bool = bool(party.call("any_busy"))
	check("  in a party any game that says it is busy (the fourth number of its \"me\") holds the crowd; a game from before says nothing",
		not calm_party and busy_party and not old_game, [calm_party, busy_party, old_game])
	run.set("party", null)
	if is_instance_valid(run.get("swarm")):
		(run.get("swarm") as Node).queue_free()
	run.queue_free()
	party.free()
	link.free()
	await get_tree().process_frame
	print("  (under budget, and still the horde: done)")


# =============================================================================
# THE ENDLESS'S LAG TESTS (0.150.0)
# =============================================================================
# The owner: "test and fix what you need to". His boss fight drew 13 ms a frame
# and the browser cannot time the graphics card, so: hide one thing at a time
# and see which takes the drawing with it.

func _test_the_endless_lag_tests() -> void:
	section("THE ENDLESS'S LAG TESTS (0.150.0): slimes, health bars, damage numbers and boss spikes, hidden one at a time")
	const Lag := preload("res://src/systems/lagtests.gd")
	const SwarmScript := preload("res://src/world/endless/swarm.gd")
	const SpikeFx := preload("res://src/projectiles/spikefx.gd")
	# ---- the slimes ------------------------------------------------------------------
	var swarm: Node2D = SwarmScript.new()
	add_child(swarm)
	swarm.call("draw_in_front_of", 28.0)
	await get_tree().process_frame
	var mesh: CanvasItem = swarm.get("_mesh") as CanvasItem
	var front: CanvasItem = swarm.get("_front") as CanvasItem
	var drawn_before: bool = mesh.visible and front.visible
	Lag.set_test("slimes", true, get_tree())
	var hidden: bool = not mesh.visible and not front.visible
	Lag.set_test("slimes", false, get_tree())
	check("Slimes hides both of the swarm's pictures and puts them back (the slimes still move and bite)",
		drawn_before and hidden and mesh.visible and front.visible)
	swarm.queue_free()
	# ---- the health bars ---------------------------------------------------------------
	var monster: Node2D = (load("res://scene/enemy/poisonslime.tscn") as PackedScene).instantiate() as Node2D
	add_child(monster)
	await get_tree().process_frame
	monster.set("hp", float(monster.get("max_hp")) * 0.5)
	monster.call("_paint_bar_shown")
	var bar: CanvasItem = monster.get_node_or_null("healthbar") as CanvasItem
	var bar_shown: bool = bar != null and bar.visible
	Lag.set_test("health", true, get_tree())
	var bar_hidden: bool = bar != null and not bar.visible
	Lag.set_test("health", false, get_tree())
	check("Health hides a wounded monster's bar (and its numbers with it) and shows it again",
		bar_shown and bar_hidden and bar.visible, [bar_shown, bar_hidden])
	monster.queue_free()
	# ---- the damage numbers ------------------------------------------------------------
	var holder := Node2D.new()
	add_child(holder)
	Lag.set_test("numbers", true, get_tree())
	var number: Node = FloatingLabel.take(holder)
	number.call("show_number", 42, 0)
	var words: Node = FloatingLabel.take(holder)
	words.call("show_text", "LEVEL UP!", 0)
	Lag.set_test("numbers", false, get_tree())
	var shown_after: Node = FloatingLabel.take(holder)
	shown_after.call("show_number", 7, 0)
	check("Numbers hides the damage numbers - not words such as a level-up - and they come back",
		not (number as CanvasItem).visible and (words as CanvasItem).visible and (shown_after as CanvasItem).visible)
	holder.queue_free()
	# ---- the boss spikes ---------------------------------------------------------------
	var container := Node2D.new()
	add_child(container)
	var fx: Node2D = SpikeFx.of(container)
	var spike: Node2D = (load("res://scene/projectiles/icebossprojectile.tscn") as PackedScene).instantiate()
	spike.set("telegraph_seconds", 5.0)
	Lag.set_test("spikes", true, get_tree())
	container.add_child(spike)
	spike.global_position = Vector2(500, 500)
	spike.call("telegraph_over")
	var risen_unseen: bool = not (spike.get("anim") as CanvasItem).visible and bool(spike.get("_erupting"))
	Lag.set_test("spikes", false, get_tree())
	check("Spikes: a spike rises, and hits, unseen; off again, the one standing is seen",
		risen_unseen and (spike.get("anim") as CanvasItem).visible and int(fx.call("standing_count")) == 1)
	container.queue_free()
	# ---- the panel ---------------------------------------------------------------------
	var was_role: String = Api.role
	Api.role = "owner"
	var gm: Control = (load("res://scene/ui/owner/ownerpanel.tscn") as PackedScene).instantiate() as Control
	add_child(gm)
	await get_tree().process_frame
	var row: Node = gm.find_child("laggridtwo", true, false)
	var slimes_button: Button = gm.find_child("lagslimesbutton", true, false) as Button
	if slimes_button != null:
		slimes_button.button_pressed = true
	var strip: Array = gm.call("active_now")
	var on: bool = Lag.hide_slimes
	if slimes_button != null:
		slimes_button.button_pressed = false
	check("the GM panel's LAG TESTS has a second row - Slimes, Health, Numbers, Spikes - each a toggle on the strip, and it still fits 370 (%d)"
		% PanelWindow.content_minimum(gm).x,
		row != null and row.find_children("lag*button", "Button", false, false).size() == 4
		and on and strip.has("Slimes Off") and not Lag.hide_slimes and PanelWindow.content_minimum(gm).x <= 370.0, strip)
	gm.queue_free()
	Api.role = was_role
	Lag.hide_slimes = false
	Lag.hide_health = false
	Lag.hide_numbers = false
	Lag.hide_spikes = false
	await get_tree().process_frame
	print("  (the Endless's lag tests: done)")


# =============================================================================
# SPAWN (0.151.0)
# =============================================================================
# The owner: "i could test certain mobs like archers only or slimes or bosses
# or elites and i can measure out better" - the stress test works only in the
# Big Field.

func _test_the_gm_spawner() -> void:
	section("SPAWN (0.151.0): any monster round the owner, in any area, as test copies worth nothing")
	const Spawner := preload("res://src/world/gmspawner.gd")
	var listed: Array = Spawner.catalogue()
	var scenes: int = 0
	for entry in ResourceLoader.list_directory(Spawner.FOLDER):
		if String(entry).ends_with(".tscn"):
			scenes += 1
	var labels: Dictionary = {}
	for entry in listed:
		labels[str(entry["label"])] = true
	check("the picker lists every monster scene, each by a name of its own (%d)" % listed.size(),
		listed.size() == scenes and scenes > 40 and labels.size() == listed.size(), [listed.size(), scenes, labels.size()])
	check("  named for a person: an element and a kind",
		Spawner.label_of("windbushsniper") == ["Wind archer", 2] and str(Spawner.label_of("skeletonelite")[0]) == "Skeleton elite"
		and str(Spawner.label_of("darkslimelarge")[0]) == "Dark large slime" and str(Spawner.label_of("bossenemy")[0]) == "Dark boss"
		and str(Spawner.label_of("fireboss")[0]) == "Fire boss")
	var at := Vector2(9000, 9000)
	var made: int = Spawner.spawn(get_tree(), "res://scene/enemy/lightslime.tscn", 3, at)
	await get_tree().process_frame
	var spawned: Array = get_tree().get_nodes_in_group(Spawner.GROUP)
	var all_copies: bool = spawned.size() == 3
	for monster in spawned:
		var away: float = (monster as Node2D).global_position.distance_to(at)
		if not monster.has_meta(&"stress_copy") or str(monster.call("get_enemy_id")) != "" \
				or away < Spawner.NEAR - 1.0 or away > Spawner.FAR + 1.0 or float(monster.get("notice_range")) != Spawner.NOTICE:
			all_copies = false
	check("Spawn: that many round you, each a test copy - no kill report (no loot, no XP), after you from where it stands",
		made == 3 and all_copies, [made, spawned.size()])
	var over: int = Spawner.spawn(get_tree(), "res://scene/enemy/lightslime.tscn", Spawner.MOST + 50, at)
	var cleared: int = Spawner.clear(get_tree())
	await get_tree().process_frame
	check("  at most %d a press; Clear takes every one away" % Spawner.MOST,
		over == Spawner.MOST and cleared == 3 + Spawner.MOST and Spawner.alive(get_tree()) == 0, [over, cleared])
	# ---- the panel ---------------------------------------------------------------------
	var was_role: String = Api.role
	var was_owner: bool = Api.is_owner
	Api.role = "owner"
	var gm: Control = (load("res://scene/ui/owner/ownerpanel.tscn") as PackedScene).instantiate() as Control
	add_child(gm)
	await get_tree().process_frame
	var pick: OptionButton = gm.find_child("spawnpick", true, false) as OptionButton
	var items: int = 0
	if pick != null:
		for i in pick.item_count:
			if not pick.is_item_separator(i):
				items += 1
	check("the GM panel's Testing tab has SPAWN - the picker, how many, Spawn and Clear - and still fits 370 (%d)"
		% PanelWindow.content_minimum(gm).x,
		pick != null and items == listed.size() and gm.find_child("spawncount", true, false) is SpinBox
		and gm.find_child("spawnbutton", true, false) is Button and gm.find_child("spawnclearbutton", true, false) is Button
		and PanelWindow.content_minimum(gm).x <= 370.0, items)
	gm.queue_free()
	Api.role = was_role
	Api.is_owner = was_owner
	await get_tree().process_frame
	print("  (spawn: done)")
