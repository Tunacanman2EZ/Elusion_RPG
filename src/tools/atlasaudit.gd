# atlasaudit.gd — answers "is this tile art actually used?" with a number.
#
# RUN IT:
#
#     .\atlasaudit.ps1
#
# It reads scenes and prints; it writes nothing and changes nothing, so it is
# always safe to run.
#
# The wrapper exists because the obvious instruction - "run godot --headless
# --script res://..." - was the documented command for about ten minutes and
# failed instantly with "The term 'godot' is not recognized". The engine here is
# a downloaded .exe on the Desktop that was never added to PATH. atlasaudit.ps1
# finds it the same way run_tests.ps1 does. Underneath it runs:
#
#     <godot> --headless --path . --script res://src/tools/atlasaudit.gd
#
#
# WHY THIS EXISTS, WHICH IS A STORY ABOUT GETTING IT WRONG THREE TIMES
# --------------------------------------------------------------------
# `c92.png` looked unused. It was deleted. Godot did not complain, because Godot
# does not complain: it quietly degraded the TileSet's `ext_resource` into an
# embedded CompressedTexture2D pointing at the baked copy in .godot/imported/,
# which kept drawing until the cache was cleaned and then stopped.
#
# Three separate answers were given about that file before the right one:
#
#   1. "13 tiles are painted from it."  WRONG. The `N:M/0 = 0` lines in an atlas
#      block are tile DEFINITIONS - which rectangles of the sheet are carved into
#      tiles. They say nothing about whether any of them was ever placed.
#
#   2. "Nothing is painted from it, deleting was correct."  ALSO WRONG. That came
#      from finding its atlas in the water TileSet, counting zero cells there and
#      stopping. One texture can back SEVERAL atlas sources, in DIFFERENT
#      TileSets, at DIFFERENT source ids.
#
#   3. "112 cells in the ground layer."  Correct, and only visible after finding
#      the SECOND atlas source and decoding the packed cell data.
#
# A filename grep cannot settle this. Searching a scene for "c92.png" finds the
# ext_resource and reports the file as used - which is true, and says nothing
# about whether a single tile is placed. "Referenced" and "painted" are different
# questions and only one of them decides whether deleting is safe.
#
#
# WHY IT USES THE TILESET API AND NOT TEXT PARSING
# -------------------------------------------------
# Every wrong answer above came from reading .tscn text with regexes. So this
# asks Godot instead: PackedScene.get_state() exposes each node's type and
# properties WITHOUT instantiating the scene - which matters, because
# instantiating elusion.tscn to count tiles would run the whole world.
#
# From there `TileSet.get_source(id)` hands back the real TileSetAtlasSource and
# its real Texture2D, so the source-id-to-texture mapping is Godot's own and
# cannot drift from what the engine actually does.
#
# The one thing with no API is the cell list. `tile_map_data` is a PackedByteArray
# of fixed records, documented below, and decoding it is unavoidable.
extends SceneTree


# THE PACKED CELL FORMAT, which is the only hand-decoded thing here.
#
#   bytes 0-1      format version (uint16)
#   then, per cell, 12 bytes of int16:
#       0-1   cell x
#       2-3   cell y
#       4-5   SOURCE ID      <- the only field this tool needs
#       6-7   atlas coord x
#       8-9   atlas coord y
#      10-11  alternative tile
#
# Source ids are PER TILESET. Two layers can both paint "source 2" and mean
# completely different atlases - that is mistake 2 in the header. Always resolve
# a layer's own TileSet before mapping its ids.
const HEADER_BYTES := 2
const CELL_BYTES := 12
const FIELD_SOURCE_ID := 4


func _initialize() -> void:
	var scenes: Array[String] = []
	_collect_scenes("res://scene", scenes)
	scenes.sort()

	# texture path -> painted cell count, across every scene
	var totals: Dictionary = {}
	# texture path -> array of "scene (layer): n" for the detail lines
	var where: Dictionary = {}
	# textures that back an atlas somewhere but are painted nowhere
	var atlas_textures: Dictionary = {}

	for path in scenes:
		_audit_scene(path, totals, where, atlas_textures)

	print("")
	print("=".repeat(72))
	print("  ATLAS AUDIT — painted cells per texture, across %d scenes" % scenes.size())
	print("=".repeat(72))
	print("")

	var painted: Array[String] = []
	var unpainted: Array[String] = []
	for tex in atlas_textures:
		if int(totals.get(tex, 0)) > 0:
			painted.append(tex)
		else:
			unpainted.append(tex)

	painted.sort_custom(func(a, b): return int(totals[a]) > int(totals[b]))
	unpainted.sort()

	print("  PAINTED — these are in use. Deleting one removes tiles from the world.")
	print("")
	for tex in painted:
		print("    %7d  %s" % [int(totals[tex]), tex])
		for line in where[tex]:
			print("             %s" % line)

	print("")
	print("  NOT PAINTED ANYWHERE — every atlas built on these has zero placed cells.")
	print("")
	if unpainted.is_empty():
		print("    (none)")
	for tex in unpainted:
		print("    %7d  %s" % [0, tex])

	print("")
	print("  READ THE SECOND LIST CAREFULLY. It means 'no tile is placed from this")
	print("  texture in any TileSet'. It does NOT mean the file is unused: the same")
	print("  texture can be a Sprite2D, an AnimatedSprite2D frame, a button icon or a")
	print("  shader parameter, and none of that is a tile. This tool answers one")
	print("  question. Deleting on the strength of it alone is how art disappears.")
	print("")

	quit()


func _collect_scenes(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_collect_scenes(full, out)
		elif entry.ends_with(".tscn"):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()


func _audit_scene(path: String, totals: Dictionary, where: Dictionary,
		atlas_textures: Dictionary) -> void:
	var packed := load(path) as PackedScene
	if packed == null:
		push_warning("atlasaudit: %s would not load" % path)
		return

	# get_state() rather than instantiate(): reading elusion.tscn should not
	# build the world, spawn its enemies or run anybody's _ready().
	var state := packed.get_state()

	for n in state.get_node_count():
		if state.get_node_type(n) != "TileMapLayer":
			continue

		var tile_set: TileSet = null
		var data := PackedByteArray()
		for p in state.get_node_property_count(n):
			match state.get_node_property_name(n, p):
				"tile_set":
					tile_set = state.get_node_property_value(n, p) as TileSet
				"tile_map_data":
					data = state.get_node_property_value(n, p) as PackedByteArray
		if tile_set == null:
			continue

		# Godot's own mapping, not a guess: source id -> the texture behind it.
		var id_to_texture: Dictionary = {}
		for s in tile_set.get_source_count():
			var sid: int = tile_set.get_source_id(s)
			var atlas := tile_set.get_source(sid) as TileSetAtlasSource
			if atlas == null or atlas.texture == null:
				continue
			var tex_path: String = atlas.texture.resource_path
			if tex_path == "":
				# An embedded texture with no file behind it - which is exactly
				# what a deleted source leaves. Named so it cannot hide.
				tex_path = "<embedded, no file — %s>" % path.get_file()
			id_to_texture[sid] = tex_path
			atlas_textures[tex_path] = true

		if data.size() < HEADER_BYTES:
			continue
		var cells: int = (data.size() - HEADER_BYTES) / CELL_BYTES
		var counts: Dictionary = {}
		for i in cells:
			var sid: int = data.decode_s16(HEADER_BYTES + i * CELL_BYTES + FIELD_SOURCE_ID)
			counts[sid] = int(counts.get(sid, 0)) + 1

		var layer_name: String = state.get_node_name(n)
		for sid in counts:
			if not id_to_texture.has(sid):
				continue
			var tex: String = id_to_texture[sid]
			totals[tex] = int(totals.get(tex, 0)) + int(counts[sid])
			if not where.has(tex):
				where[tex] = []
			where[tex].append("%s (%s, source %d): %d"
				% [path.trim_prefix("res://"), layer_name, sid, int(counts[sid])])
