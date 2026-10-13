# strikefx.gd - the warrior's blows, seen: the arc a swing cuts and the sparks
# where steel meets a monster (0.38.0).
#
# The owner: "the final character warrioe how can we make him better also",
# and of the four offered, all four - "Swing arc + sparks", "Dressed slash
# wave", "Heavier hits" and "Third-swing finisher". This file is the two pieces
# the sword and the wave share; the wave's own dressing is slashwave.gd's, and
# the finisher and the hit-stop are warrior.gd's.
#
#   arc()     a crescent swept round the warrior through the swing, the way the
#             cursor aims - all 360 degrees of it, where the art has four - its
#             head bright, its tail fading, gone in a quarter of a second. Each
#             swing sweeps the other way from the last, the way a sword is
#             swung back and forth. A finisher's is gold, longer and wider.
#   sparks()  where a blow lands: a white flash and a handful of steel sparks
#             thrown out fast and short - gold for a finisher - drawn over
#             whoever was hit (z 5, as Blast is).
#
# WHOLE PIXELS AND UNSHADED, like every effect since 0.34.0: the arc is a
# Line2D two pixels wide with antialiasing off, the sparks single squares, the
# flash a disc of hard bands.
#
# PRELOADED, AND NOTHING BUT THE ENGINE. warrior.gd and slashwave.gd take it
# as `const Strike := preload(...)`, the way threatring.gd takes targets.gd -
# no class_name, so nothing new for the editor to register. The arc is a plain
# Line2D driven by a tween (its meta "sweep"), and the flash's disc is drawn
# here rather than borrowed from Blast, so this file reaches for nothing.
extends RefCounted


const STEEL := &"steel"
const GOLD := &"gold"
# The arc: how far out it is cut (inside the sword's reach, 25 to 32 px each
# way), how far either side of the aim it sweeps, how long the sweep takes and
# how long it lingers after.
const ARC_RADIUS := 22.0
const ARC_SWEEP_DEGREES := 75.0
const ARC_SECONDS := 0.14
const ARC_FADE_SECONDS := 0.12
const ARC_POINTS := 16
# A finisher's: wider, and further round.
const FINISHER_ARC_RADIUS := 28.0
const FINISHER_ARC_SWEEP_DEGREES := 100.0
const SPARK_SECONDS := 0.28
const FLASH_RADIUS := 4

static var _flash_textures: Dictionary = {}


static func colours(palette: StringName) -> Gradient:
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	if palette == GOLD:
		ramp.colors = PackedColorArray([Color(1.0, 1.0, 0.9), Color(1.0, 0.82, 0.3), Color(0.85, 0.42, 0.1, 0.0)])
	else:
		ramp.colors = PackedColorArray([Color(1.0, 1.0, 1.0), Color(0.88, 0.94, 1.0), Color(0.55, 0.65, 0.8, 0.0)])
	return ramp


static func arc_points(aim_angle: float, sweep: float, radius: float, clockwise: bool, head: float) -> PackedVector2Array:
	"""The arc's line from where the swing began to `head` of the way round
	(0 to 1): from `sweep` before the aim to `sweep` after it, clockwise or
	back."""
	var side: float = 1.0 if clockwise else -1.0
	var start: float = aim_angle - sweep * side
	var points := PackedVector2Array()
	for i in ARC_POINTS:
		var angle: float = start + 2.0 * sweep * side * head * float(i) / float(ARC_POINTS - 1)
		points.append(Vector2.from_angle(angle) * radius)
	return points


static func arc(body: Node2D, aim: Vector2, clockwise: bool, gold: bool = false) -> Line2D:
	"""A swing's arc round `body`'s origin - the middle of the warrior's
	picture - centred on `aim`, sweeping `clockwise` or back. Frees itself;
	its tween is its meta "sweep", for the tests."""
	var aim_angle: float = aim.angle() if aim != Vector2.ZERO else PI / 2.0
	var radius: float = FINISHER_ARC_RADIUS if gold else ARC_RADIUS
	var sweep: float = deg_to_rad(FINISHER_ARC_SWEEP_DEGREES if gold else ARC_SWEEP_DEGREES)
	var colour: Color = Color(1.0, 0.86, 0.4) if gold else Color(1.0, 1.0, 1.0)
	var line := Line2D.new()
	line.name = "swingarc"
	line.width = 2.0
	line.antialiased = false
	line.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	line.z_index = 1
	# Tail clear, head bright: where the blade was, and where it is.
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 1.0])
	fade.colors = PackedColorArray([Color(colour.r, colour.g, colour.b, 0.0), colour])
	line.gradient = fade
	var unshaded := CanvasItemMaterial.new()
	unshaded.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	line.material = unshaded
	line.points = arc_points(aim_angle, sweep, radius, clockwise, 0.0)
	body.add_child(line)
	var cut := func(head: float) -> void:
		line.points = arc_points(aim_angle, sweep, radius, clockwise, head)
	var t := line.create_tween()
	t.tween_method(cut, 0.0, 1.0, ARC_SECONDS)
	t.tween_property(line, "modulate:a", 0.0, ARC_FADE_SECONDS)
	t.tween_callback(line.queue_free)
	line.set_meta(&"sweep", t)
	return line


static func sparks(parent: Node, at: Vector2, palette: StringName = STEEL) -> Node2D:
	"""Where a blow lands: a flash and sparks thrown out. Frees itself."""
	if parent == null:
		return null
	var root := Node2D.new()
	root.name = "strikesparks"
	root.z_as_relative = false
	root.z_index = 5
	root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var unshaded := CanvasItemMaterial.new()
	unshaded.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	var flash := Sprite2D.new()
	flash.name = "flash"
	flash.texture = flash_texture(palette)
	flash.material = unshaded
	root.add_child(flash)
	var p := CPUParticles2D.new()
	p.name = "sparks"
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 14 if palette == GOLD else 8
	p.lifetime = SPARK_SECONDS
	p.lifetime_randomness = 0.4
	p.direction = Vector2.UP
	p.spread = 180.0
	p.initial_velocity_min = 50.0
	p.initial_velocity_max = 110.0
	p.damping_min = 120.0
	p.damping_max = 220.0
	p.color_ramp = colours(palette)
	p.material = unshaded
	p.emitting = true
	root.add_child(p)
	parent.add_child(root)
	root.global_position = at
	var t := flash.create_tween()
	t.tween_interval(0.04)
	t.tween_property(flash, "modulate:a", 0.0, 0.06)
	root.get_tree().create_timer(SPARK_SECONDS + 0.1).timeout.connect(root.queue_free)
	return root


static func flash_texture(palette: StringName) -> ImageTexture:
	"""A disc of white with a steel (or gold) rim, in hard bands, FLASH_RADIUS
	across - Blast's flash, small."""
	if _flash_textures.has(palette):
		return _flash_textures[palette]
	var rim: Color = Color(1.0, 0.8, 0.35) if palette == GOLD else Color(0.8, 0.9, 1.0)
	var size: int = FLASH_RADIUS * 2
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var d: float = Vector2(x + 0.5 - FLASH_RADIUS, y + 0.5 - FLASH_RADIUS).length() / float(FLASH_RADIUS)
			if d <= 0.5:
				image.set_pixel(x, y, Color(1.0, 1.0, 0.95))
			elif d <= 1.0:
				image.set_pixel(x, y, Color(rim.r, rim.g, rim.b, 0.75))
	var texture := ImageTexture.create_from_image(image)
	_flash_textures[palette] = texture
	return texture


static func hit_point(target: Node2D) -> Vector2:
	"""Where on a monster a blow lands: the middle of its hurtbox, or a little
	above its feet if it has none."""
	var shape_node: Node2D = target.get_node_or_null(^"hurtbox/collisionshape2d") as Node2D
	if shape_node != null:
		return shape_node.global_position
	return target.global_position + Vector2(0.0, -12.0)
