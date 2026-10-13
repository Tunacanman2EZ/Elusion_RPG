# strikefx.gd - where the warrior's blows land: a flash and sparks (0.38.0).
#
# The owner: "the final character warrioe how can we make him better also",
# and of the four offered, all four. 0.38.0 cut a white arc round every swing
# here too; the owner: "its horrible ... the trails are bad", so 0.39.0 took it
# out and put the crypt's orbs in its place (bladeorb.gd). What is left is:
#
#   sparks()  where a blow lands: a white flash and a handful of steel sparks
#             thrown out fast and short - gold for a finisher - drawn over
#             whoever was hit (z 5, as Blast is). The sword's, the wave's on
#             each monster it cuts, and the wave's where it breaks on a wall.
#
# WHOLE PIXELS AND UNSHADED, like every effect since 0.34.0: the sparks single
# squares, the flash a disc of hard bands.
#
# PRELOADED, AND NOTHING BUT THE ENGINE. warrior.gd and slashwave.gd take it
# as `const Strike := preload(...)`, the way threatring.gd takes targets.gd -
# no class_name. The flash's disc is drawn here rather than borrowed from
# Blast, so this file reaches for nothing.
extends RefCounted


const STEEL := &"steel"
const GOLD := &"gold"
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
