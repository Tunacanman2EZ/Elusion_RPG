# castsparkle.gd - motes thrown off the mage's staff as a spell is cast (0.35.0).
#
# The owner: "time to give the mages attack some effects", and of the four
# offered, all four - this is the first: "frost motes burst from the mage's
# staff as the spell is cast". The rest are the stalagmite's own
# (spelltargetcircle.gd: the frost ring and the shadow) and Blast's
# "stalagmite" kind (the shatter, and the frost left on the ground).
#
# TWO HANDFULS, one emitter each: a small burst round the gem, and a short
# streak of them thrown the way the spell went - so the eye goes from the staff
# to where it lands. Frost for the stalagmite, embers for the Meteorite's
# meteor; whole-pixel squares, unshaded, so they glow in a dark area, as
# Blast's sparks and the burning crater's are.
#
# AT THE GEM. Where the staff's gem is drawn in each facing's cast, measured off
# the first frame of the four attack animations in mage.png (the cyan pixels of
# the gem), from the middle of the mage's picture. It moves a few pixels as the
# staff is raised; the burst is gone before that matters.
#
# ON THE MAGE AND ON ITS PICTURE. mage.gd throws one on every cast; a picture of
# somebody else's mage (remoteattacks.gd) throws one when their stalagmite or
# meteor is drawn, facing the way their picture faces.
class_name CastSparkle
extends CPUParticles2D


# Where the gem is, from the middle of the mage's picture, for each facing.
const GEM := {
	"down": Vector2(-15.0, -11.0),
	"up": Vector2(15.5, -12.5),
	"left": Vector2(-14.5, -12.5),
	"right": Vector2(13.5, -12.5),
}
const FROST := &"frost"
const EMBER := &"ember"
const BURST := 14
const STREAK := 7
const LIFETIME := 0.5


static func gem_offset(body: Node2D, facing: String) -> Vector2:
	"""Where the gem is drawn on `body`, facing `facing`, from its origin."""
	var picture: Node2D = body.get_node_or_null(^"animatedsprite2d") as Node2D
	var middle: Vector2 = picture.position if picture != null else Vector2(0.0, -19.0)
	return middle + GEM.get(facing, GEM["down"])


static func burst(body: Node2D, facing: String, toward: Vector2, palette: StringName = FROST) -> CastSparkle:
	"""Motes off `body`'s staff, facing `facing`, with a streak of them toward
	`toward` (a point in the world). Frees itself when the last one is gone."""
	var spark := CastSparkle.new()
	spark.name = "castsparkle"
	spark._set_up(BURST, 180.0, Vector2(12.0, 34.0), -12.0, palette)
	var streak := CastSparkle.new()
	streak.name = "streak"
	streak._set_up(STREAK, 10.0, Vector2(60.0, 110.0), 0.0, palette)
	spark.add_child(streak)
	body.add_child(spark)
	spark.position = gem_offset(body, facing)
	var along: Vector2 = toward - spark.global_position
	streak.direction = along.normalized() if along.length() > 1.0 else Vector2.UP
	spark.emitting = true
	streak.emitting = true
	spark.finished.connect(spark.queue_free)
	return spark


static func colours(palette: StringName) -> Gradient:
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	if palette == EMBER:
		ramp.colors = PackedColorArray([Color(1.0, 0.97, 0.75), Color(1.0, 0.62, 0.2), Color(0.8, 0.2, 0.05, 0.0)])
	else:
		ramp.colors = PackedColorArray([Color(1.0, 1.0, 1.0), Color(0.62, 0.92, 1.0), Color(0.25, 0.5, 0.95, 0.0)])
	return ramp


func _set_up(count: int, fan: float, speed: Vector2, rise: float, palette: StringName) -> void:
	one_shot = true
	explosiveness = 0.9
	emitting = false
	amount = count
	lifetime = LIFETIME
	lifetime_randomness = 0.4
	local_coords = false
	direction = Vector2.UP
	spread = fan
	initial_velocity_min = speed.x
	initial_velocity_max = speed.y
	damping_min = speed.x
	damping_max = speed.y
	gravity = Vector2(0.0, rise)
	scale_amount_min = 1.0
	scale_amount_max = 1.0
	color_ramp = colours(palette)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Over the mage's picture - the gem is part of it.
	z_index = 1
	var unshaded := CanvasItemMaterial.new()
	unshaded.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = unshaded
