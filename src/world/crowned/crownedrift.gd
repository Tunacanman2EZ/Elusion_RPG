# crownedrift.gd - THE RIFT past the Crowned's walls (0.134.1, step 2 of the
# commit folder's CROWNED_PLAN.txt: "past the walls, a slow code-drawn rift
# with glimpses of each hero's world (the volcano, the forge, the crypt)
# instead of black").
#
# Made by crownedfight.gd in a CanvasLayer behind the world (layer -1,
# following the camera), so it shows wherever nothing of the room is drawn:
# past the walls, between them - and through the floor where the Tear cuts it
# away (crownedphases.gd), which is the point of it. The room's darkness
# (its CanvasModulate) does not reach it.
#
#   - THE VOID: deep indigo, slow clouds in the seven lands' colours, stars
#     that glimmer, and violet tears that pulse. Redrawn REDRAW_FPS times a
#     second - it moves slowly.
#   - GLIMPSES (GLIMPSES): windows into the heroes' worlds, each fading in
#     and out on its own slow clock (GLIMPSE_SECONDS), ringed in violet: the
#     volcano (the town's bubbling lava and the Forge's lava falls), the forge
#     (the underground floor lit orange, lava at its foot) and the crypt (the
#     underground floor in violet). The owner's tiles, clipped to an ellipse
#     (clip_children); nothing new drawn but the void.
#   - THE VOLCANO COMES WITH THE LAVA (0.134.2). The owner: "the lava only
#     appears there when the map is flooding" - the volcano's windows show
#     only while the Sealing's lava is in (`flood`, 0 to 1, set by
#     crownedphases.gd from how many rings it holds, eased over FLOOD_EASE),
#     and float in from where they rest to just past the walls as it rises.
#     The forge and the crypt come and go on their own clocks as before.
#   - THE REALM BREAKING (0.134.2). The owner, of a tear: "we need it to zip
#     accross the screen ... looks like the realm is breaking". Every
#     ZIP_GAP_LEAST to ZIP_GAP_MOST seconds (shorter by `intensity`, which
#     the fight raises phase by phase) a crack races across the void at
#     ZIP_SPEED - jagged, forking, white-hot at its head - over the glimpses
#     too, then fades over ZIP_FADE.
#
# No class_name: preload it by path.
extends Node2D

const UNDERGROUND := "res://scene/world/underground.tres"
const LAVA_SHEET := "res://art/tiles/propsandterrain.png"
const FALL_SHEET := "res://art/tiles/lavafall.png"
const LAVA_TILE := 32
const LAVA_CELL := Vector2i(0, 5)
const LAVA_FRAMES := 9
const LAVA_FPS := 3.0
const FLOOR_TILE := 16
const REDRAW_FPS := 20.0
const STARS := 260
const CLOUDS := 14
const TEARS := 6
const REACH := 1400.0
const GLIMPSE_SECONDS := 14.0
const GLIMPSE_SIZE := Vector2(300, 180)
# Where each glimpse floats, from the room's floor (left, right, above, below).
const GLIMPSES := ["volcano", "crypt", "forge", "volcano"]
const FLOOD_EASE := 1.5
const NEAR_WALL := 30.0
const ZIP_GAP_LEAST := 1.2
const ZIP_GAP_MOST := 3.2
const ZIP_SPEED := 1700.0
const ZIP_FADE := 0.9
const ZIP_STEP := 22.0
const ZIP_LEAST := 700.0
const ZIP_MOST := 1400.0

# The room's floor (crownedfight.gd room_rect).
var room: Rect2 = Rect2(0, 0, 1024, 768)
var clock: float = 0.0
var glimpses: Array = []
var _redraw_left: float = 0.0
var _stars := PackedVector2Array()
var _tears: Array = []
# How often the realm cracks: 1 the first phase, more as the fight goes on.
var intensity: float = 1.0
# How far the Sealing's lava is in (0 none, 1 the most), and as shown.
var flood: float = 0.0
var flood_shown: float = 0.0
# Cracks racing across: {"pts", "along" (distance to each point), "t", "forks"}.
var zips: Array = []
var zips_made: int = 0
var _zip_left: float = 0.6
var _zip_rng := RandomNumberGenerator.new()
var _cracks: Node2D = null


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4021
	var span: Rect2 = room.grow(REACH)
	for k in STARS:
		_stars.append(Vector2(rng.randf_range(span.position.x, span.end.x), rng.randf_range(span.position.y, span.end.y)))
	for k in TEARS:
		var start: Vector2 = _outside(rng)
		var heading: float = rng.randf() * TAU
		var tear := PackedVector2Array([start])
		for q in 9:
			heading += rng.randf_range(-0.7, 0.7)
			tear.append(tear[q] + Vector2.from_angle(heading) * rng.randf_range(18.0, 34.0))
		_tears.append(tear)
	var spots: Array = [Vector2(room.position.x - 300.0, room.get_center().y),
		Vector2(room.end.x + 300.0, room.get_center().y),
		Vector2(room.get_center().x, room.position.y - 260.0),
		Vector2(room.get_center().x - 120.0, room.end.y + 240.0)]
	var half: Vector2 = GLIMPSE_SIZE / 2.0
	var nearer: Array = [Vector2(room.position.x - half.x - NEAR_WALL, room.get_center().y),
		Vector2(room.end.x + half.x + NEAR_WALL, room.get_center().y),
		Vector2(room.get_center().x, room.position.y - half.y - NEAR_WALL),
		Vector2(room.get_center().x - 120.0, room.end.y + half.y + NEAR_WALL)]
	for k in GLIMPSES.size():
		var glimpse: Array = _make_glimpse(str(GLIMPSES[k]), spots[k], float(k) / float(GLIMPSES.size()))
		glimpse.append_array([str(GLIMPSES[k]), spots[k], nearer[k]])
		glimpses.append(glimpse)
	_zip_rng.randomize()
	_cracks = Node2D.new()
	_cracks.name = "cracks"
	_cracks.draw.connect(_draw_cracks)
	add_child(_cracks)


func _outside(rng: RandomNumberGenerator) -> Vector2:
	"""A point past the walls."""
	for tries in 20:
		var at := Vector2(rng.randf_range(room.position.x - 500.0, room.end.x + 500.0),
			rng.randf_range(room.position.y - 400.0, room.end.y + 400.0))
		if not room.grow(60.0).has_point(at):
			return at
	return room.position - Vector2(200, 200)


func _process(delta: float) -> void:
	clock += delta
	flood_shown = move_toward(flood_shown, clampf(flood, 0.0, 1.0), delta / FLOOD_EASE)
	for k in glimpses.size():
		var holder: Node2D = glimpses[k][0]
		var ring: Line2D = glimpses[k][1]
		if str(glimpses[k][3]) == "volcano":
			holder.modulate.a = flood_shown
			holder.position = (glimpses[k][4] as Vector2).lerp(glimpses[k][5], flood_shown)
			ring.position = holder.position
		else:
			var sway: float = 0.5 - 0.5 * cos(TAU * (clock / GLIMPSE_SECONDS + float(glimpses[k][2])))
			holder.modulate.a = clampf(sway * 1.4 - 0.2, 0.0, 1.0)
		ring.modulate.a = holder.modulate.a
	_redraw_left -= delta
	if _redraw_left <= 0.0:
		_redraw_left = 1.0 / REDRAW_FPS
		queue_redraw()
	_step_zips(delta)


func _step_zips(delta: float) -> void:
	_zip_left -= delta
	if _zip_left <= 0.0:
		_zip_left = _zip_rng.randf_range(ZIP_GAP_LEAST, ZIP_GAP_MOST) / maxf(0.25, intensity)
		zips.append(make_zip())
	var still: Array = []
	for zip in zips:
		zip["t"] = float(zip["t"]) + delta
		var along: PackedFloat32Array = zip["along"]
		if float(zip["t"]) < along[along.size() - 1] / ZIP_SPEED + ZIP_FADE:
			still.append(zip)
	zips = still
	if _cracks != null:
		_cracks.queue_redraw()


func make_zip() -> Dictionary:
	"""A crack starting somewhere past the walls and racing across."""
	var start: Vector2 = _outside(_zip_rng)
	var aim: Vector2 = room.get_center() + Vector2(_zip_rng.randf_range(-300.0, 300.0), _zip_rng.randf_range(-250.0, 250.0))
	var heading: float = (aim - start).angle() + _zip_rng.randf_range(-0.5, 0.5)
	var length: float = _zip_rng.randf_range(ZIP_LEAST, ZIP_MOST)
	var pts := PackedVector2Array([start])
	var along := PackedFloat32Array([0.0])
	var gone: float = 0.0
	while gone < length:
		heading += _zip_rng.randf_range(-0.45, 0.45)
		var step: float = ZIP_STEP * _zip_rng.randf_range(0.6, 1.4)
		pts.append(pts[pts.size() - 1] + Vector2.from_angle(heading) * step)
		gone += step
		along.append(gone)
	var forks: Array = []
	for f in _zip_rng.randi_range(2, 4):
		var from: int = _zip_rng.randi_range(2, pts.size() - 3)
		var turn: float = (pts[from + 1] - pts[from]).angle() + _zip_rng.randf_range(0.5, 1.1) * (1.0 if f % 2 == 0 else -1.0)
		var fork := PackedVector2Array([pts[from]])
		for q in _zip_rng.randi_range(3, 7):
			turn += _zip_rng.randf_range(-0.5, 0.5)
			fork.append(fork[q] + Vector2.from_angle(turn) * ZIP_STEP * _zip_rng.randf_range(0.5, 1.1))
		forks.append([along[from], fork])
	zips_made += 1
	return {"pts": pts, "along": along, "t": 0.0, "forks": forks}


func _draw_cracks() -> void:
	for zip in zips:
		var pts: PackedVector2Array = zip["pts"]
		var along: PackedFloat32Array = zip["along"]
		var head: float = float(zip["t"]) * ZIP_SPEED
		var total: float = along[along.size() - 1]
		var fade: float = 1.0 - clampf((float(zip["t"]) - total / ZIP_SPEED) / ZIP_FADE, 0.0, 1.0)
		var shown := PackedVector2Array()
		for k in pts.size():
			if along[k] > head:
				break
			shown.append(pts[k])
		if shown.size() < 2:
			continue
		_cracks.draw_polyline(shown, Color(0.55, 0.25, 1.0, 0.28 * fade), 12.0)
		_cracks.draw_polyline(shown, Color(0.85, 0.65, 1.0, 0.85 * fade), 3.0)
		_cracks.draw_polyline(shown, Color(1.0, 1.0, 1.0, fade), 1.2)
		for fork in zip["forks"]:
			if float(fork[0]) <= head:
				var branch: PackedVector2Array = fork[1]
				_cracks.draw_polyline(branch, Color(0.75, 0.5, 1.0, 0.6 * fade), 2.0)
				_cracks.draw_polyline(branch, Color(1.0, 0.95, 1.0, 0.7 * fade), 1.0)
		if head < total:
			_cracks.draw_circle(shown[shown.size() - 1], 6.0, Color(1.0, 0.95, 1.0, 0.9))
			_cracks.draw_circle(shown[shown.size() - 1], 14.0, Color(0.7, 0.45, 1.0, 0.35))


func _draw() -> void:
	var span: Rect2 = room.grow(REACH)
	draw_rect(span, Color(0.06, 0.035, 0.11))
	var lands: Array = [Element.Type.LIGHT, Element.Type.WIND, Element.Type.WATER, Element.Type.ICE,
		Element.Type.EARTH, Element.Type.FIRE, Element.Type.DARK]
	for k in CLOUDS:
		var colour: Color = Element.colour_for(int(lands[k % lands.size()]))
		var base := Vector2(room.position.x + fmod(float(k) * 431.0, room.size.x + 800.0) - 400.0,
			room.position.y + fmod(float(k) * 277.0, room.size.y + 700.0) - 350.0)
		var at: Vector2 = base + Vector2(sin(clock * 0.07 + float(k)), cos(clock * 0.05 + float(k) * 1.7)) * 40.0
		var size: float = 160.0 + float(k % 4) * 50.0
		for ring in 4:
			draw_circle(at, size * (1.0 - 0.2 * float(ring)), Color(colour, 0.035))
	for k in _stars.size():
		var glimmer: float = 0.35 + 0.35 * sin(clock * (1.3 + float(k % 5) * 0.4) + float(k))
		draw_circle(_stars[k], 1.0 + float(k % 3) * 0.4, Color(0.9, 0.85, 1.0, glimmer))
	for k in _tears.size():
		var pulse: float = 0.5 + 0.5 * sin(clock * 1.1 + float(k) * 1.9)
		var tear: PackedVector2Array = _tears[k]
		draw_polyline(tear, Color(0.6, 0.3, 1.0, 0.12 + 0.12 * pulse), 12.0)
		draw_polyline(tear, Color(0.8, 0.6, 1.0, 0.4 + 0.4 * pulse), 3.0)
		draw_polyline(tear, Color(1.0, 0.95, 1.0, 0.5 + 0.5 * pulse), 1.0)


# =============================================================================
# GLIMPSES
# =============================================================================

func _ellipse(size: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	for k in 40:
		points.append(Vector2.from_angle(TAU * float(k) / 40.0) * size / 2.0)
	return points


func _make_glimpse(world: String, at: Vector2, offset: float) -> Array:
	"""A window into a hero's world at `at`: [the clipped holder, its ring,
	its clock's offset]."""
	var holder := Polygon2D.new()
	holder.name = "glimpse_%s" % world
	holder.polygon = _ellipse(GLIMPSE_SIZE)
	holder.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	holder.position = at
	holder.modulate.a = 0.0
	var reach := Rect2(-GLIMPSE_SIZE / 2.0, GLIMPSE_SIZE)
	match world:
		"volcano":
			holder.add_child(_lava_layer(reach))
			holder.add_child(_falls(reach))
		"forge":
			var floor_layer: TileMapLayer = _floor_layer(reach, 31)
			floor_layer.modulate = Color(1.0, 0.72, 0.5)
			holder.add_child(floor_layer)
			holder.add_child(_lava_layer(Rect2(reach.position.x, reach.end.y - 56.0, reach.size.x, 56.0)))
		_:
			var floor_layer: TileMapLayer = _floor_layer(reach, 77)
			floor_layer.modulate = Color(0.7, 0.55, 1.0)
			holder.add_child(floor_layer)
	add_child(holder)
	var ring := Line2D.new()
	ring.name = "glimpse_ring_%s" % world
	var loop: PackedVector2Array = _ellipse(GLIMPSE_SIZE)
	loop.append(loop[0])
	ring.points = loop
	ring.width = 3.0
	ring.default_color = Color(0.8, 0.6, 1.0, 0.85)
	ring.position = at
	ring.modulate.a = 0.0
	add_child(ring)
	return [holder, ring, offset]


static func lava_tiles() -> TileSet:
	"""The town's bubbling lava (buildforge.gd's own set-up)."""
	var tiles := TileSet.new()
	tiles.tile_size = Vector2i(LAVA_TILE, LAVA_TILE)
	var moving := TileSetAtlasSource.new()
	moving.texture = load(LAVA_SHEET) as Texture2D
	moving.texture_region_size = Vector2i(LAVA_TILE, LAVA_TILE)
	moving.create_tile(LAVA_CELL)
	moving.set_tile_animation_columns(LAVA_CELL, LAVA_FRAMES)
	moving.set_tile_animation_frames_count(LAVA_CELL, LAVA_FRAMES)
	moving.set_tile_animation_speed(LAVA_CELL, LAVA_FPS)
	moving.set_tile_animation_mode(LAVA_CELL, TileSetAtlasSource.TILE_ANIMATION_MODE_RANDOM_START_TIMES)
	tiles.add_source(moving, 0)
	return tiles


func _lava_layer(area: Rect2) -> TileMapLayer:
	var lava := TileMapLayer.new()
	lava.tile_set = lava_tiles()
	lava.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for y in range(floori(area.position.y / LAVA_TILE), ceili(area.end.y / LAVA_TILE)):
		for x in range(floori(area.position.x / LAVA_TILE), ceili(area.end.x / LAVA_TILE)):
			lava.set_cell(Vector2i(x, y), 0, LAVA_CELL)
	return lava


func _floor_layer(area: Rect2, seed_value: int) -> TileMapLayer:
	var ground := TileMapLayer.new()
	ground.tile_set = load(UNDERGROUND) as TileSet
	ground.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for y in range(floori(area.position.y / FLOOR_TILE), ceili(area.end.y / FLOOR_TILE)):
		for x in range(floori(area.position.x / FLOOR_TILE), ceili(area.end.x / FLOOR_TILE)):
			ground.set_cell(Vector2i(x, y), 1, Vector2i(rng.randi_range(1, 4), rng.randi_range(1, 3)))
	return ground


func _falls(area: Rect2) -> Node2D:
	"""The Forge's lava falls, pouring down the volcano's window."""
	var frames := SpriteFrames.new()
	frames.set_animation_speed(&"default", 6.0)
	var sheet: Texture2D = load(FALL_SHEET) as Texture2D
	for i in 4:
		var piece := AtlasTexture.new()
		piece.atlas = sheet
		piece.region = Rect2(i * 32, 0, 32, 96)
		frames.add_frame(&"default", piece)
	var falls := Node2D.new()
	for k in 3:
		var fall := AnimatedSprite2D.new()
		fall.sprite_frames = frames
		fall.autoplay = "default"
		fall.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		fall.position = Vector2(area.position.x + area.size.x * (0.25 + 0.25 * float(k)), area.position.y + 40.0)
		falls.add_child(fall)
	return falls
