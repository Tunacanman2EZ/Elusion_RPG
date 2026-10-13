# scorchmarks.gd - burnt patches on the ground, cooling and fading (0.34.0).
#
# The ground the tank's lit aura passes over is left scorched (auraburn.gd, the
# owner's "born on the ground"). Each patch is a dark, ragged blot of pixels
# with two to four embers in it; the embers cool from yellow to a dull red and
# go out, and the blot holds for a moment and then fades. Nothing about it is
# saved or sent - it is a picture, and a few seconds long.
#
# ONE PER AREA, ON THE FLOOR. It is a child of the area's "ground" layer, so it
# draws with the floor - after its tiles, before the grass and stones on
# "grounddecals" and long before anything that stands on the ground. Every
# world scene has a "ground" (field, bigfield, elusion, boss, bossarena); one
# without has no scorch, and nothing else changes.
#
# NOT ON WATER. Where the "ground" layer has no tile there is no floor - the
# water layer shows through it, z -20 under the ground's -10 - and a burn
# there sat on the water in the first recording, in town. A patch is laid
# only where the ground has a tile (has_floor()).
#
# ONE DRAW FOR ALL OF THEM, rather than a node per patch: a walk can leave a
# hundred, and they all change every frame as they fade. The embers are drawn
# by a child, unshaded, so they glow in a dark area where the blots do not.
#
# PIXELS, NOT SHAPES: the blots are small textures built once (VARIANTS of
# them, from a fixed seed) and drawn on whole pixels, so they sit in the floor
# the way the tiles do.
class_name ScorchMarks
extends Node2D


# How long a patch lasts: dark for HOLD seconds, then fading to nothing by LIFE.
const HOLD := 1.4
const LIFE := 4.5
# How long its embers burn, at the most - each gets a share of it.
const EMBER_SECONDS := 2.6
# The most patches at once; the oldest go first.
const MOST := 140
const VARIANTS := 8
# The blots' colours, from the middle out.
const CHAR := Color(0.05, 0.04, 0.035, 0.8)
const BURNT := Color(0.11, 0.075, 0.05, 0.62)
const SINGED := Color(0.22, 0.13, 0.07, 0.4)
const EMBER_HOT := Color(1.0, 0.78, 0.32)
const EMBER_COOL := Color(0.5, 0.09, 0.03)

static var _blots: Array[ImageTexture] = []

# Each: {"at": Vector2 (this node's space, whole pixels), "blot": int,
# "age": float, "embers": Array of [Vector2 offset, float share, float phase]}.
var marks: Array[Dictionary] = []
var _embers: Node2D = null


static func of(tree: SceneTree) -> ScorchMarks:
	"""The area's scorch layer, made the first time it is asked for - or null in
	an area with no "ground"."""
	var scene: Node = tree.current_scene if tree != null else null
	if scene == null:
		return null
	var ground: Node = scene.get_node_or_null(^"ground")
	if ground == null or not (ground is CanvasItem):
		return null
	var layer: ScorchMarks = ground.get_node_or_null(^"scorchmarks") as ScorchMarks
	if layer == null:
		layer = ScorchMarks.new()
		layer.name = "scorchmarks"
		ground.add_child(layer)
	return layer


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_embers = Node2D.new()
	_embers.name = "embers"
	var unshaded := CanvasItemMaterial.new()
	unshaded.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_embers.material = unshaded
	_embers.draw.connect(_draw_embers)
	add_child(_embers)
	set_process(false)


func has_floor(at_global: Vector2) -> bool:
	"""Whether there is ground to burn at `at_global`: a tile in the ground
	layer there. A ground that is not a tile layer is all floor."""
	var layer: TileMapLayer = get_parent() as TileMapLayer
	if layer == null:
		return true
	return layer.get_cell_source_id(layer.local_to_map(layer.to_local(at_global))) != -1


func burn(at_global: Vector2) -> bool:
	"""A patch, centred on `at_global` - if there is floor there to burn."""
	if not has_floor(at_global):
		return false
	var embers: Array = []
	for i in randi_range(2, 4):
		embers.append([Vector2(randi_range(-4, 4), randi_range(-2, 2)), randf_range(0.45, 1.0), randf() * TAU])
	marks.append({"at": to_local(at_global).round(), "blot": randi() % VARIANTS, "age": 0.0, "embers": embers})
	while marks.size() > MOST:
		marks.pop_front()
	set_process(true)
	return true


static func fade(age: float) -> float:
	"""How much of a patch is left at `age` seconds: all of it until HOLD, then
	less and less, none at LIFE."""
	if age <= HOLD:
		return 1.0
	return clampf(1.0 - (age - HOLD) / (LIFE - HOLD), 0.0, 1.0)


static func ember_heat(age: float, share: float) -> float:
	"""How hot an ember is at `age`, one that burns for `share` of
	EMBER_SECONDS: 1 when the patch is laid, 0 when it is out."""
	return clampf(1.0 - age / (EMBER_SECONDS * share), 0.0, 1.0)


func _process(delta: float) -> void:
	var i: int = marks.size() - 1
	while i >= 0:
		marks[i]["age"] = float(marks[i]["age"]) + delta
		if float(marks[i]["age"]) >= LIFE:
			marks.remove_at(i)
		i -= 1
	queue_redraw()
	_embers.queue_redraw()
	if marks.is_empty():
		set_process(false)


func _draw() -> void:
	if marks.is_empty():
		return
	var blots: Array[ImageTexture] = blot_textures()
	for mark in marks:
		var blot: ImageTexture = blots[int(mark["blot"])]
		var size: Vector2 = blot.get_size()
		draw_texture(blot, (mark["at"] as Vector2) - (size / 2.0).floor(), Color(1, 1, 1, fade(float(mark["age"]))))


func _draw_embers() -> void:
	for mark in marks:
		var age: float = float(mark["age"])
		for ember in mark["embers"]:
			var heat: float = ember_heat(age, float(ember[1]))
			if heat <= 0.0:
				continue
			var glow: Color = EMBER_COOL.lerp(EMBER_HOT, heat)
			glow.a = heat * (0.75 + 0.25 * sin(float(ember[2]) + age * 11.0))
			_embers.draw_rect(Rect2((mark["at"] as Vector2) + (ember[0] as Vector2), Vector2.ONE), glow)


static func blot_textures() -> Array[ImageTexture]:
	"""VARIANTS blots, 16 to 30 px across and a little over half as tall, each a
	few overlapping lobes with a ragged edge. Built once, from a fixed seed."""
	if not _blots.is_empty():
		return _blots
	for v in VARIANTS:
		var rng := RandomNumberGenerator.new()
		rng.seed = 4111 + v * 97
		var w: int = 16 + v * 2
		var h: int = maxi(8, roundi(w * 0.55))
		var lobes: Array = []
		for i in 4:
			lobes.append([Vector2(rng.randf_range(-0.35, 0.35), rng.randf_range(-0.3, 0.3)), rng.randf_range(0.45, 0.7)])
		var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
		for y in h:
			for x in w:
				var at := Vector2((x + 0.5) / w * 2.0 - 1.0, (y + 0.5) / h * 2.0 - 1.0)
				var d: float = INF
				for lobe in lobes:
					d = minf(d, (at - (lobe[0] as Vector2)).length() / float(lobe[1]))
				if d >= 1.0:
					continue
				# A ragged edge: the outer pixels go missing now and then.
				if d > 0.65 and rng.randf() < 0.3:
					continue
				image.set_pixel(x, y, CHAR if d < 0.45 else (BURNT if d < 0.75 else SINGED))
		_blots.append(ImageTexture.create_from_image(image))
	return _blots
