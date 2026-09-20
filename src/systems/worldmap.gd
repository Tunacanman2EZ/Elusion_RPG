# worldmap.gd — draws the map, and remembers where you have been.
# Autoloaded as `WorldMap`.
#
# =============================================================================
# THE MAP NEEDS NO ART, BECAUSE THE WORLD ALREADY IS ONE
# =============================================================================
# Every area in this game is built from TileMapLayer nodes, and a TileMapLayer
# knows exactly which cells it has and where. So the map is that, drawn one
# pixel per tile: water blue, ground green, ysortworld dark for the trees and
# buildings, nothing at all where there is no tile.
#
# The areas are small enough that this is almost free. The largest is the field
# at 126 x 108 tiles, which is a 126 x 108 image — a thumbnail. It is generated
# once when an area is first entered and cached for the session.
#
# COLOURED BY LAYER NAME, not by tileset or by physics. Every world scene in
# this project names its layers the same way (water, ground, grounddecals,
# ysortworld, aboveworld, Black), so a town and a field both come out legible
# with no per-scene configuration and a new area needs nothing here at all. A
# layer whose name is not in the table is drawn in grey rather than skipped:
# an unnamed layer showing up as a grey smear is a thing you can see and fix,
# and a layer silently missing from the map is not.
#
# =============================================================================
# FOG OF WAR, AND WHY IT IS THE POINT RATHER THAN A FEATURE
# =============================================================================
# A map that shows everything is a convenience — it saves you walking. A map
# you uncover is a reward, and it turns exploring from something you do once
# into something that pays out for the whole game.
#
# It also answers a balance question rather than raising one. The obvious
# alternative was to mark live enemies on the map, and that would have made the
# field substantially easier, because most of what makes it tense is being
# surprised. With fog there is no need: the tension moves to the dark edge of
# what you have seen, which is a better place for it.
#
# WHAT IS STORED IS ONE BIT PER TILE. Not pixels, not a texture, not a list of
# coordinates — a bitmask the width of the area. Every area in the game
# together is under 3 KB before compression, and explored ground arrives in
# large contiguous blobs, which is the best case deflate has.
#
# IT BELONGS TO THE CHARACTER, NOT THE MACHINE. Unlike the options in
# settings.gd — where a volume slider belongs to the speakers it comes out of —
# a discovered map that resets when you log in from a different computer is the
# feature failing at exactly the moment it matters. So it rides in the
# character save, next to equipment and the hotbar, and goes wherever they go.
#
# THE SERVER WILL NOT VALIDATE IT, and does not need to: knowing where you have
# been confers nothing on anybody else, so there is nothing to cheat. It does
# get a size ceiling, because an opaque blob in a database column with no
# ceiling is somewhere to put ten megabytes.
extends Node


# =============================================================================
# SIGNALS
# =============================================================================

# Emitted when a tile is revealed that was not revealed before — never on a
# step that uncovers nothing, which is most steps. The map panel listens so it
# can redraw while open; nothing else has to.
signal explored(area_id: String)


# =============================================================================
# TUNING
# =============================================================================

# How far around the character the fog lifts, in tiles. Seven is a little over
# half a screen at this tile size: enough that the map fills in at walking pace
# and still leaves the far side of an area genuinely unknown.
const SEEN_RADIUS := 7

# CIRCLES, NOT SQUARES. A square reveal leaves the map looking like it was
# built out of Lego, and the corners give away more than the character could
# see. Compared squared to avoid a sqrt per tile per step.
const SEEN_RADIUS_SQUARED := SEEN_RADIUS * SEEN_RADIUS

# A ceiling on what will be generated or stored for one area — 512 x 512 tiles,
# which is sixteen times the size of the biggest area in the game. It is not a
# performance guard; it is there so that a malformed scene, or a stray tile
# placed at coordinate 30000 by a mis-click, cannot ask for a 900 MB image.
const MAX_AREA_TILES := 262144

# The colours the map is drawn in, by lowercased layer name.
const COLOURS := {
	"black":        Color(0.05, 0.05, 0.07),
	"water":        Color(0.18, 0.34, 0.58),
	"ground":       Color(0.33, 0.45, 0.26),
	"grounddecals": Color(0.36, 0.48, 0.28),
	"ysortworld":   Color(0.20, 0.27, 0.17),
	"aboveworld":   Color(0.16, 0.20, 0.14),
}

# A layer this file has never heard of. Loud on purpose — see the header.
const COLOUR_UNKNOWN := Color(0.45, 0.30, 0.45)

# Where you have not been. Not transparent: an unexplored area should read as
# dark rather than as a hole in the panel.
const COLOUR_FOG := Color(0.04, 0.04, 0.05)


# =============================================================================
# STATE
# =============================================================================

# area_id -> {"image": Image, "origin": Vector2i, "size": Vector2i,
#             "tile": Vector2i}
#
# Cached for the session and rebuilt on demand. Not persisted: the terrain is
# derivable from the scene in a few milliseconds, and a saved copy is a second
# source of truth that goes stale the first time the world is edited.
var _terrain: Dictionary = {}

# area_id -> PackedByteArray, one bit per tile, row-major from origin.
# THIS is what persists.
var _seen: Dictionary = {}

# THE SERIALISED FORM, CACHED, because save_character_state() is called from
# twenty-seven places and eleven of them are in player.gd — every XP gain,
# every coin picked up. Deflating every area's bitmask on each of those is the
# same mistake warrior.gd's own comment describes about gain_attack_xp():
#
#     "...which looks up the HUD by group and serialises the entire inventory
#      into fresh dictionaries before handing off to the debounced save.
#      Calling it once per enemy meant a five-target cleave did all of that
#      five times inside a single frame, to record one number."
#
# The map changes a few times a second while walking and not at all while
# standing in a shop. So it is built when it is asked for and kept until
# something actually uncovers a tile.
var _save_cache: Dictionary = {}
var _save_dirty: bool = true

# =============================================================================
# HOW OFTEN THE MAP IS WORTH A ROUND TRIP
# =============================================================================
# The map changes every few steps. ServerStorage pushes /api/save whenever the
# save body differs from what it last sent — so putting the map in that body
# turned walking in a straight line into a PUT every three or four seconds,
# which is exactly what it looked like in the server log:
#
#     16:51:21 "PUT /api/save HTTP/1.1" 200
#     16:51:26 "PUT /api/save HTTP/1.1" 200
#     16:51:30 "PUT /api/save HTTP/1.1" 200
#
# A REVISION NUMBER SOLVES IT WITHOUT DROPPING THE MAP. It counts up at most
# once every SAVE_REVISION_SECONDS, and only when something has actually been
# uncovered since the last count. ServerStorage fingerprints on the revision
# instead of on the map itself, so:
#
#   walking for a minute            -> one push, carrying the whole map
#   standing in a shop for an hour  -> no pushes at all
#   levelling up mid-walk           -> that push carries the current map free
#
# The cost of the bound is that the stored map can be up to that many seconds
# behind. Losing forty-five seconds of fog on a crash is not a loss worth a
# round trip every four seconds to prevent.
const SAVE_REVISION_SECONDS := 45

var _revision: int = 0
var _revision_pending: bool = false
var _revision_at_ms: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


# =============================================================================
# WHICH AREA
# =============================================================================

func area_id() -> String:
	# THE SCENE'S OWN FILENAME, which needs no new plumbing and cannot drift
	# from reality: "elusion", "field", "boss", "bossarena". The save's `area`
	# field would have been the other candidate, but nothing on the client sets
	# it — the server defaults it to "elusion" for every character in the game.
	var scene: Node = get_tree().current_scene if get_tree() != null else null
	if scene == null:
		return ""
	var path: String = scene.scene_file_path
	if path == "":
		return ""
	return path.get_file().get_basename()


func has_map(area: String) -> bool:
	return _terrain.has(area)


# =============================================================================
# BUILDING THE PICTURE
# =============================================================================

func ensure_built(area: String = "") -> bool:
	# Idempotent: the map panel calls this every time it opens and pays for the
	# generation once per area per session.
	if area == "":
		area = area_id()
	if area == "":
		return false

	# has(), NOT truthiness, AND THE IMAGE HAS TO BE THERE.
	#
	# from_save() puts a stub entry in _terrain for every area it restores
	# bits for — it has to, so _ensure_seen() can tell that a world has
	# changed shape without building the terrain for somewhere nobody has
	# been this session. Those stubs carry a null image.
	#
	# Checking only has() therefore returned "already built" for exactly the
	# areas a returning player walks into, and the map would have come up
	# empty for everyone with a save and full for everyone without one.
	var existing = _terrain.get(area, null)
	if existing != null and existing.get("image", null) != null:
		return true
	return _build(area)


func _build(area: String) -> bool:
	var scene: Node = get_tree().current_scene if get_tree() != null else null
	if scene == null:
		return false

	var layers: Array = _root_layers(scene)
	if layers.is_empty():
		return false

	# =========================================================================
	# A TILE IS NOT ALWAYS ONE CELL, AND ASSUMING IT IS DRAWS A DOTTED MAP
	# =========================================================================
	# elusion's water layer has 926 cells and 925 of them sit on an even x and
	# an even y. That is not a pattern in the art — its atlas source has a
	# texture_region_size of 32x32 on a tileset whose tile_size is 16x16, so
	# each water tile covers a 2x2 block of cells and is placed on every other
	# one.
	#
	# Painting one pixel per used cell therefore left three quarters of the sea
	# unpainted, and the town came out as a blue checkerboard. It looked like a
	# deliberate dither, which is the only reason it is worth this comment:
	# the first render was WRONG and looked STYLISED, and those are hard to
	# tell apart from across the room.
	#
	# The span is the tile's region divided by the grid, per source, and the
	# tileset hands both numbers over.
	var cells: Array = []          # [layer_index, Vector2i cell, Vector2i span]
	var bounds := Rect2i()
	var first := true

	for index in layers.size():
		var layer = layers[index]
		var grid: Vector2i = Vector2i(16, 16)
		if layer.tile_set != null and layer.tile_set.tile_size.x > 0:
			grid = layer.tile_set.tile_size

		for cell in layer.get_used_cells():
			var span: Vector2i = Vector2i.ONE
			if layer.tile_set != null:
				var source = layer.tile_set.get_source(layer.get_cell_source_id(cell))
				if source is TileSetAtlasSource:
					var region: Vector2i = (source as TileSetAtlasSource).texture_region_size
					# HOW MANY GRID CELLS THIS TILE COVERS — a count, so the
					# discarded remainder is the point rather than a rounding
					# loss. A 32x32 region on a 16x16 grid spans 2x2; a region
					# that is not a whole multiple of the grid still occupies
					# whole cells, and the floor is the honest answer.
					@warning_ignore("integer_division")
					span = Vector2i(maxi(1, region.x / maxi(1, grid.x)),
									maxi(1, region.y / maxi(1, grid.y)))
			cells.append([index, cell, span])

			# THE BOUNDS COVER WHAT IS PAINTED, not what is placed. A 2x2 tile
			# on the last cell of a row reaches one further than get_used_rect()
			# reports, and cropping to that rect would shave the far edge off
			# every coastline in the game.
			var covered := Rect2i(cell, span)
			if first:
				bounds = covered
				first = false
			else:
				bounds = bounds.merge(covered)
	if first:
		return false

	if bounds.size.x * bounds.size.y > MAX_AREA_TILES:
		push_error("WorldMap: '%s' covers %d x %d tiles, past the %d ceiling — "
			% [area, bounds.size.x, bounds.size.y, MAX_AREA_TILES]
			+ "a stray tile at an extreme coordinate will do this. Not mapped.")
		return false

	var image: Image = Image.create_empty(
		bounds.size.x, bounds.size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))

	# IN SCENE ORDER, so later layers paint over earlier ones — which is the
	# same order they are drawn in the world. Trees end up on top of the ground
	# they stand on, for the same reason they do on screen. `cells` was
	# collected in that order above, so walking it in order is enough.
	var palette: Array = []
	for layer in layers:
		palette.append(COLOURS.get(String(layer.name).to_lower(), COLOUR_UNKNOWN))

	for entry in cells:
		var colour: Color = palette[entry[0]]
		var cell: Vector2i = entry[1]
		var span: Vector2i = entry[2]
		for dy in span.y:
			for dx in span.x:
				var px: int = cell.x + dx - bounds.position.x
				var py: int = cell.y + dy - bounds.position.y
				if px < 0 or py < 0 or px >= bounds.size.x or py >= bounds.size.y:
					continue
				image.set_pixel(px, py, colour)

	# THE GRID, for turning a world position into a map pixel. The first layer
	# that has a tileset decides it: every root layer in a given scene shares
	# one grid, which is what makes them line up in the world in the first
	# place.
	var tile: Vector2i = Vector2i(16, 16)
	for layer in layers:
		if layer.tile_set != null and layer.tile_set.tile_size.x > 0:
			tile = layer.tile_set.tile_size
			break

	# THE STUB'S SIZE IS READ BEFORE IT IS OVERWRITTEN. from_save() recorded
	# what shape the world was when the bits were written; _ensure_seen() below
	# compares that against the shape it is now, and it cannot do that after
	# this assignment has replaced it.
	var previous = _terrain.get(area, null)
	var previous_size: Vector2i = Vector2i.ZERO
	if previous != null:
		previous_size = previous.get("size", Vector2i.ZERO)

	_terrain[area] = {
		"image": image,
		"origin": bounds.position,
		"size": bounds.size,
		"tile": tile,
	}

	if previous_size != Vector2i.ZERO and previous_size != bounds.size:
		push_warning("WorldMap: '%s' is %dx%d now and was %dx%d when its map was "
			% [area, bounds.size.x, bounds.size.y, previous_size.x, previous_size.y]
			+ "saved. Its exploration starts again.")
		_seen.erase(area)
		_save_dirty = true

	# The bitmask has to match the bounds it indexes into. An area whose scene
	# gained tiles since the save was written arrives here a different size,
	# and _resize_seen() is what stops the old bits being read as the new
	# coordinates.
	_ensure_seen(area, bounds.size)
	return true


func _root_layers(scene: Node) -> Array:
	# DIRECT CHILDREN OF THE SCENE ROOT ONLY.
	#
	# There are TileMapLayer nodes inside instanced props too — bush.tscn,
	# shop.tscn, largetree.tscn — and those hold their cells in their OWN
	# coordinate space, positioned by the instance's transform. Painting them
	# by cell coordinate would stack every shop in the game on top of each
	# other at the world origin.
	#
	# They are not lost. The world layers already include `ysortworld`, which
	# is where the placed props live on the map.
	var out: Array = []
	for child in scene.get_children():
		if child is TileMapLayer:
			out.append(child)
	return out


# =============================================================================
# WHAT YOU HAVE SEEN
# =============================================================================

func _ensure_seen(area: String, size: Vector2i) -> void:
	# Bytes to hold one bit per tile, rounded up. Written as a shift rather
	# than / 8 to match the `index >> 3` the reveal loop uses on the same
	# array, and because an integer divide here reads as if a remainder were
	# being thrown away when the +7 above is what handles it.
	var needed: int = (size.x * size.y + 7) >> 3
	var existing = _seen.get(area, null)
	if existing is PackedByteArray and existing.size() == needed:
		return
	if existing is PackedByteArray and existing.size() > 0:
		# A SAVE FROM A DIFFERENT SHAPE OF WORLD. The bits are indexed by
		# position within the bounds, so a world that grew by one tile to the
		# left shifts every one of them. Rather than guess at a remap, the
		# fog comes back — the cost is re-walking an area you had explored,
		# which is a smaller wrong than a map that is subtly displaced.
		push_warning("WorldMap: '%s' is a different size than the saved map "
			% area + "expected. Starting its exploration again.")
	var fresh := PackedByteArray()
	fresh.resize(needed)
	fresh.fill(0)
	_seen[area] = fresh


func tile_at(area: String, world_position: Vector2) -> Vector2i:
	var info = _terrain.get(area, null)
	if info == null:
		return Vector2i.ZERO
	var tile: Vector2i = info["tile"]
	# floori, not int(): int() truncates toward zero, so everything in the
	# column left of the origin and the row above it would round the wrong way
	# and reveal the neighbouring tile instead.
	return Vector2i(floori(world_position.x / float(tile.x)),
					floori(world_position.y / float(tile.y)))


func is_seen(area: String, tile: Vector2i) -> bool:
	var info = _terrain.get(area, null)
	var bits = _seen.get(area, null)
	if info == null or not (bits is PackedByteArray):
		return false
	var index: int = _bit_index(info, tile)
	if index < 0:
		return false
	return (bits[index >> 3] & (1 << (index & 7))) != 0


func _bit_index(info: Dictionary, tile: Vector2i) -> int:
	var origin: Vector2i = info["origin"]
	var size: Vector2i = info["size"]
	var x: int = tile.x - origin.x
	var y: int = tile.y - origin.y
	if x < 0 or y < 0 or x >= size.x or y >= size.y:
		return -1
	return y * size.x + x


func reveal_around(world_position: Vector2, area: String = "") -> bool:
	# Returns true only when something was actually uncovered, which is what
	# lets the caller be a signal emitted on every frame of movement and still
	# cost nothing on the frames that reveal nothing — which is most of them.
	if area == "":
		area = area_id()
	if area == "" or not _terrain.has(area):
		return false

	var info: Dictionary = _terrain[area]

	# TWO DICTIONARIES, ONE GUARD — which was the bug.
	#
	# The check above asks _terrain, and this line then read _seen, on the
	# assumption that an area present in one is present in the other. It is
	# not always: forget_everything() clears _seen and only refills the areas
	# whose terrain has a real image, so a save-restored stub leaves _terrain
	# holding a key that _seen does not. from_save() can land the same way.
	#
	# The result was "Invalid access to property or key 'field' on a base
	# object of type 'Dictionary'" on every step that crossed a tile — which
	# is several a second while walking, each one a synchronous flush to
	# stdout because the project runs flush_stdout_on_print.
	#
	# Rebuilt rather than refused: the area's terrain is known, so its fog
	# can be created here and exploring carries on. Returning false instead
	# would have hidden this behind a map that quietly stopped revealing.
	if not _seen.has(area):
		_ensure_seen(area, info.get("size", Vector2i.ZERO))
		if not _seen.has(area):
			return false

	var bits: PackedByteArray = _seen[area]
	var centre: Vector2i = tile_at(area, world_position)

	var changed := false
	for dy in range(-SEEN_RADIUS, SEEN_RADIUS + 1):
		for dx in range(-SEEN_RADIUS, SEEN_RADIUS + 1):
			if dx * dx + dy * dy > SEEN_RADIUS_SQUARED:
				continue
			var index: int = _bit_index(info, centre + Vector2i(dx, dy))
			if index < 0:
				continue
			var byte: int = index >> 3
			var mask: int = 1 << (index & 7)
			if bits[byte] & mask:
				continue
			bits[byte] = bits[byte] | mask
			changed = true

	if changed:
		_seen[area] = bits
		_save_dirty = true
		_revision_pending = true
		explored.emit(area)
	return changed


func save_revision() -> int:
	# A number that changes when the map is worth writing again, and not
	# before. Asked once per save by CharacterData; see the note beside
	# SAVE_REVISION_SECONDS for what it is protecting against.
	#
	# The clock only starts mattering once something is pending, so a player
	# who walks for two seconds and then stops still gets that walk saved on
	# the next push rather than waiting for a bucket boundary that never comes.
	if _revision_pending:
		var now: int = Time.get_ticks_msec()
		if now - _revision_at_ms >= SAVE_REVISION_SECONDS * 1000:
			_revision += 1
			_revision_pending = false
			_revision_at_ms = now
	return _revision


func explored_fraction(area: String) -> float:
	# For a "37% explored" line on the panel. Counts bits rather than tracking
	# a running total: a counter is a second copy of the truth that a resize,
	# a reset or a save reload can put out of step with the bitmask.
	var info = _terrain.get(area, null)
	var bits = _seen.get(area, null)
	if info == null or not (bits is PackedByteArray):
		return 0.0
	var size: Vector2i = info["size"]
	var total: int = size.x * size.y
	if total <= 0:
		return 0.0
	var count := 0
	for byte in bits:
		# Kernighan: clears the lowest set bit each pass, so it loops once per
		# SET bit rather than eight times per byte. Most bytes are 0 or 255.
		var b: int = byte
		while b:
			b &= b - 1
			count += 1
	return float(count) / float(total)


# =============================================================================
# WHAT THE PANEL DRAWS
# =============================================================================

func display_image(area: String = "") -> Image:
	# The terrain with the fog laid over it, as a fresh Image the caller owns.
	#
	# BAKED RATHER THAN SHADED. At 126 x 108 this is thirteen thousand pixel
	# writes, once, when the panel opens or something new is uncovered — which
	# is cheaper to write, cheaper to read, and needs no second texture than
	# doing it with a mask and a shader would be.
	if area == "":
		area = area_id()
	var info = _terrain.get(area, null)
	if info == null or info.get("image", null) == null:
		return null

	var source: Image = info["image"]
	var size: Vector2i = info["size"]
	var out: Image = Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)

	var bits = _seen.get(area, null)
	var have_bits: bool = bits is PackedByteArray

	for y in size.y:
		for x in size.x:
			var index: int = y * size.x + x
			var lit: bool = have_bits and (bits[index >> 3] & (1 << (index & 7))) != 0
			out.set_pixel(x, y, source.get_pixel(x, y) if lit else COLOUR_FOG)
	return out


func map_size(area: String = "") -> Vector2i:
	if area == "":
		area = area_id()
	var info = _terrain.get(area, null)
	return Vector2i.ZERO if info == null else info["size"]


func pixel_for(world_position: Vector2, area: String = "") -> Vector2:
	# Where something in the world sits on the map image, in pixels, as a
	# float — so a marker moves smoothly across a tile rather than snapping
	# from one pixel to the next.
	if area == "":
		area = area_id()
	var info = _terrain.get(area, null)
	if info == null:
		return Vector2.ZERO
	var tile: Vector2i = info["tile"]
	var origin: Vector2i = info["origin"]
	return Vector2(world_position.x / float(tile.x) - float(origin.x),
				   world_position.y / float(tile.y) - float(origin.y))


# =============================================================================
# PERSISTENCE
# =============================================================================

func to_save() -> Dictionary:
	# {area: {"w":, "h":, "ox":, "oy":, "bits": base64}}
	#
	# THE SIZE AND ORIGIN TRAVEL WITH THE BITS, because the bits mean nothing
	# without them — index 400 is a different tile in a 126-wide area than in a
	# 87-wide one. Storing them is what lets _ensure_seen() notice that a world
	# has changed shape rather than drawing a displaced map.
	if not _save_dirty:
		return _save_cache

	var out: Dictionary = {}
	for area in _seen:
		var bits = _seen[area]
		if not (bits is PackedByteArray) or bits.is_empty():
			continue
		var info = _terrain.get(area, null)
		if info == null:
			continue
		var size: Vector2i = info["size"]
		var origin: Vector2i = info["origin"]
		out[area] = {
			"w": size.x,
			"h": size.y,
			"ox": origin.x,
			"oy": origin.y,
			"bits": Marshalls.raw_to_base64(
				bits.compress(FileAccess.COMPRESSION_DEFLATE)),
		}

	_save_cache = out
	_save_dirty = false
	return out


func from_save(data) -> void:
	_seen.clear()
	_save_cache = {}
	_save_dirty = true
	if typeof(data) != TYPE_DICTIONARY:
		return

	for area in data:
		var entry = data[area]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var w: int = int(entry.get("w", 0))
		var h: int = int(entry.get("h", 0))
		if w <= 0 or h <= 0 or w * h > MAX_AREA_TILES:
			continue

		# Same shift as _ensure_seen(), and for the same reason — these two
		# numbers have to agree or a restored map is rejected as the wrong
		# length. Keeping them written identically is what makes that
		# obvious to anyone changing one of them.
		var expected: int = (w * h + 7) >> 3
		var packed: PackedByteArray = Marshalls.base64_to_raw(str(entry.get("bits", "")))
		if packed.is_empty():
			continue

		# A SAVE IS NOT TRUSTED TO DECOMPRESS. decompress() with a wrong
		# expected size returns an empty array rather than raising, and a
		# hand-edited or truncated blob is exactly the case this has to survive
		# without taking the character's login with it.
		var bits: PackedByteArray = packed.decompress(
			expected, FileAccess.COMPRESSION_DEFLATE)
		if bits.size() != expected:
			push_warning("WorldMap: the stored map for '%s' would not decompress "
				% str(area) + "to the size it claims. Starting it again.")
			continue

		_seen[str(area)] = bits

		# Recorded so _ensure_seen() can compare against the world as it is now
		# WITHOUT having to build the terrain for an area nobody has entered
		# this session.
		if not _terrain.has(str(area)):
			_terrain[str(area)] = {
				"image": null,
				"origin": Vector2i(int(entry.get("ox", 0)), int(entry.get("oy", 0))),
				"size": Vector2i(w, h),
				"tile": Vector2i(16, 16),
			}


func forget_everything() -> void:
	# For a fresh character, and for anyone testing the fog who does not want
	# to walk the field again to see it.
	_seen.clear()
	_save_cache = {}
	_save_dirty = true
	for area in _terrain:
		var info = _terrain[area]
		if info != null and info.get("image", null) != null:
			_ensure_seen(area, info["size"])
