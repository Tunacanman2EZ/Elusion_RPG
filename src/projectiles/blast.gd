# blast.gd - what a meteor or a stick of dynamite looks like when it goes off.
#
# A one-shot effect, built in code and freed when its last particle is gone. It
# deals no damage and knows nothing about who threw what: meteor.gd and
# dynamite.gd decide who is hit, and then ask for this.
#
# WHY ONE EFFECT FOR TWO WEAPONS. Ahvassa drew the falling meteor and the lit
# stick, and nothing for the moment either lands. Both need the same parts in a
# different mix - a flash, a ring of air, fire, smoke, things thrown up, and a
# mark left on the ground - so the parts are written once and the two kinds
# differ only in the numbers below:
#
#   meteor     mostly earth: little fire, a lot of dust and thrown rock, and a
#              crater with a raised rim. It hit the ground; it did not burn.
#   dynamite   mostly fire: a bright core, a bigger fireball, black smoke, and a
#              scorch mark rather than a hole.
#
# PIXELS, NOT SMOOTH SHAPES. The world is pixel art drawn at three times its
# size. Every particle is an untextured square of whole world pixels, and the
# flash, the shadow and the ground marks are small images drawn pixel by pixel
# and shown nearest-neighbour - so the effect is made of the same size of dot
# as Ahvassa's art beside it. A smooth gradient or an antialiased circle would
# look pasted on.
#
# LAYERS. The effect is added beside whatever spawned it and pins its own z
# absolutely, the way spelltargetcircle.gd does: the ground mark sits on the
# floor under every enemy (z -2), and the fire and smoke draw over everything
# (z 5), because an explosion covers what is standing in it.
class_name Blast
extends Node2D


# How long the ground mark stays before it has faded out, in seconds. Long
# enough to read where the hit landed, short enough that a mage's afternoon
# does not leave the field pockmarked.
const MARK_SECONDS := 4.0

# The camera shake each kind asks for: strength in world pixels, length in
# seconds. See Player.shake_camera() for why these are small.
const SHAKE := {
	&"meteor": Vector2(2.0, 0.22),
	&"dynamite": Vector2(1.5, 0.18),
}

var kind: StringName = &"dynamite"
var radius: float = 24.0
# Whether it shakes the local player's camera: not for a picture of somebody
# else's meteor or stick (0.19.0) - their blast shakes their screen.
var shakes: bool = true

# The longest-lived part, so the node knows when it has nothing left to show.
var _life: float = 1.4

# Built textures, shared by every blast. Generating a 32x32 image is cheap, but
# not free, and a meteor shower would make the same ones a dozen times a second.
static var _texture_cache: Dictionary = {}


# =============================================================================
# SPAWNING
# =============================================================================

static func spawn(parent: Node, at: Vector2, blast_kind: StringName, blast_radius: float,
		shake: bool = true) -> Blast:
	# The one way in. Returns the node so a test can look at what was built.
	var blast := Blast.new()
	blast.kind = blast_kind
	blast.radius = blast_radius
	blast.shakes = shake
	parent.add_child(blast)
	blast.global_position = at
	blast.reset_physics_interpolation()
	# BUILT HERE, NOT IN _ready(). _ready() runs inside add_child(), before the
	# line above has moved the node - and the ground mark is placed by global
	# position, so a mark made in _ready() landed at the world's origin. The
	# first one did, under the player's spawn point.
	blast._build()
	return blast


func _build() -> void:
	z_as_relative = false
	z_index = 5
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_leave_mark()
	_flash()
	_ring()
	# Puffs are round (Blast.puff_texture), the rest are single squares: a
	# fireball and a dust cloud are soft shapes, a spark and a thrown stone are
	# points.
	#
	# SMOKE FIRST, AND LATE. Added before the fire so it draws behind it, and
	# started a beat after the flash: drawn on top from the first frame, it
	# put a dark hole in the middle of every fireball.
	var puff: Texture2D = Blast.puff_texture()
	if kind == &"meteor":
		_burst(_smoke(), 6, 1.3, Vector2(6, 16), 1.0, 1.8, -16.0, puff, 0.12)
		_burst(_fire(), 8, 0.3, Vector2(10, 30), 0.8, 1.4, 0.0, puff)
		_burst(_dust(), 16, 0.9, Vector2(25, 70), 0.7, 1.5, 0.0, puff)
		_burst(_rocks(), 14, 0.7, Vector2(60, 130), 2.0, 3.0, 260.0)
	else:
		_burst(_smoke(), 10, 1.4, Vector2(8, 24), 1.2, 2.2, -22.0, puff, 0.15)
		_burst(_fire(), 18, 0.45, Vector2(12, 40), 1.0, 2.0, 0.0, puff)
		_burst(_sparks(), 16, 0.5, Vector2(80, 150), 1.0, 1.0, 120.0)
	_shake_the_thrower()
	# Freed by a timer on this node rather than by the particles finishing, so
	# a scene change takes the whole effect with it in one go.
	get_tree().create_timer(_life).timeout.connect(queue_free)


# =============================================================================
# THE PARTS
# =============================================================================

func _flash() -> void:
	# The first frame: a disc of white-hot light the size of the hit, gone in
	# a tenth of a second. It is what makes the impact read as an impact.
	var flash := Sprite2D.new()
	flash.name = "flash"
	flash.texture = Blast.disc_texture(int(radius * 0.6), Color(1.0, 1.0, 0.9), Color(1.0, 0.8, 0.45))
	add_child(flash)
	var t := flash.create_tween()
	t.tween_interval(0.05)
	t.tween_property(flash, "modulate:a", 0.0, 0.07)


func _ring() -> void:
	# The air pushed out: one ring that runs out past the edge of the hit and
	# fades as it goes. Drawn by a child so its _draw is its own.
	var ring := BlastRing.new()
	ring.name = "ring"
	ring.reach = radius * 1.35
	ring.colour = Color(1.0, 0.9, 0.7, 0.9) if kind == &"dynamite" else Color(0.85, 0.8, 0.7, 0.9)
	add_child(ring)


func _leave_mark() -> void:
	# The crater or the scorch, on the floor, added to the PARENT so it can
	# outlive the fire above it by a few seconds and fade on its own.
	var mark := Sprite2D.new()
	mark.name = "blastmark"
	mark.texture = Blast.crater_texture(int(radius)) if kind == &"meteor" else Blast.scorch_texture(int(radius))
	mark.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mark.z_as_relative = false
	mark.z_index = -2
	mark.add_to_group("blastmarks")
	get_parent().add_child(mark)
	mark.global_position = global_position
	var t := mark.create_tween()
	t.tween_interval(MARK_SECONDS * 0.6)
	t.tween_property(mark, "modulate:a", 0.0, MARK_SECONDS * 0.4)
	t.tween_callback(mark.queue_free)


func _burst(colours: Gradient, amount: int, lifetime: float, velocity: Vector2,
		size_min: float, size_max: float, gravity_y: float = 0.0, texture: Texture2D = null,
		start_after: float = 0.0) -> void:
	# One handful of squares thrown out from the middle at once. gravity_y
	# above zero arcs them back down (rocks and sparks), below zero lifts them
	# (smoke). The ground is a plane seen from above, so "down" is down the
	# screen - the same cheat every top-down game makes.
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = amount
	p.lifetime = lifetime
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius * 0.35
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.initial_velocity_min = velocity.x
	p.initial_velocity_max = velocity.y
	p.damping_min = velocity.x * 0.6
	p.damping_max = velocity.y * 0.6
	p.gravity = Vector2(0, gravity_y)
	p.scale_amount_min = size_min
	p.scale_amount_max = size_max
	p.color_ramp = colours
	# Each particle a little different in shade and in how long it lasts, so
	# a burst of them reads as a mottled cloud and not one flat blob.
	p.color_initial_ramp = _ramp([[0.0, Color(1, 1, 1)], [1.0, Color(0.82, 0.74, 0.7)]])
	p.lifetime_randomness = 0.35
	p.texture = texture
	add_child(p)
	if start_after > 0.0:
		p.emitting = false
		get_tree().create_timer(start_after).timeout.connect(p.set_emitting.bind(true))
	else:
		p.emitting = true
	_life = maxf(_life, start_after + lifetime + 0.2)


func _shake_the_thrower() -> void:
	# The local player's camera, if there is one - for the local player's own
	# blasts. Since 0.19.0 other players' attacks are drawn here too, as
	# pictures, and those are spawned with shakes off.
	if not shakes:
		return
	var player: Node = get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("shake_camera"):
		var shake: Vector2 = SHAKE.get(kind, Vector2.ZERO)
		player.shake_camera(shake.x, shake.y)


# =============================================================================
# COLOURS
# =============================================================================

static func _ramp(stops: Array) -> Gradient:
	# [[offset, Color], ...] -> Gradient, so each palette below reads as a list.
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(stops.map(func(s): return float(s[0])))
	g.colors = PackedColorArray(stops.map(func(s): return s[1]))
	return g


func _fire() -> Gradient:
	return _ramp([[0.0, Color(1.0, 0.97, 0.7)], [0.25, Color(1.0, 0.72, 0.2)],
		[0.6, Color(0.9, 0.3, 0.08)], [1.0, Color(0.3, 0.12, 0.08, 0.0)]])


func _sparks() -> Gradient:
	return _ramp([[0.0, Color(1.0, 1.0, 0.75)], [0.5, Color(1.0, 0.8, 0.3)],
		[1.0, Color(1.0, 0.4, 0.1, 0.0)]])


func _dust() -> Gradient:
	return _ramp([[0.0, Color(0.62, 0.52, 0.4)], [0.5, Color(0.5, 0.44, 0.36, 0.85)],
		[1.0, Color(0.45, 0.41, 0.36, 0.0)]])


func _rocks() -> Gradient:
	# The meteor's own greys, so what flies out is the same stone.
	return _ramp([[0.0, Color(0.47, 0.53, 0.59)], [0.7, Color(0.3, 0.33, 0.36)],
		[1.0, Color(0.16, 0.17, 0.19, 0.0)]])


func _smoke() -> Gradient:
	var dark: float = 0.18 if kind == &"dynamite" else 0.42
	return _ramp([[0.0, Color(dark, dark, dark, 0.0)], [0.15, Color(dark, dark, dark, 0.75)],
		[1.0, Color(dark + 0.15, dark + 0.15, dark + 0.15, 0.0)]])


# =============================================================================
# PIXEL TEXTURES
# =============================================================================

static func _cached(key: String, build: Callable) -> Texture2D:
	if not _texture_cache.has(key):
		_texture_cache[key] = ImageTexture.create_from_image(build.call())
	return _texture_cache[key]


static func disc_texture(r: int, core: Color, edge: Color) -> Texture2D:
	# A filled disc, white-hot in the middle and the edge colour at the rim, in
	# three hard bands rather than a smooth fade: pixel art does not blend.
	r = maxi(r, 2)
	return _cached("disc%d" % r, func() -> Image:
		var img := Image.create_empty(r * 2, r * 2, false, Image.FORMAT_RGBA8)
		for y in r * 2:
			for x in r * 2:
				var d: float = Vector2(x + 0.5 - r, y + 0.5 - r).length() / float(r)
				if d > 1.0:
					continue
				var c: Color = core if d < 0.45 else (core.lerp(edge, 0.5) if d < 0.75 else edge)
				c.a = 1.0 if d < 0.75 else 0.7
				img.set_pixel(x, y, c)
		return img)


static func puff_texture() -> Texture2D:
	# One round puff of white, 8 pixels across, for the particles that should
	# read as soft - fire and smoke and dust. The colour ramp tints it.
	return _cached("puff", func() -> Image:
		var img := Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)
		for y in 8:
			for x in 8:
				if Vector2(x + 0.5 - 4.0, y + 0.5 - 4.0).length() <= 4.0:
					img.set_pixel(x, y, Color.WHITE)
		return img)


static func shadow_texture(rx: int, ry: int) -> Texture2D:
	# A soft-edged dark ellipse: solid in the middle, one ring of half-dark
	# pixels at the edge. The meteor grows its shadow by swapping between
	# these a pixel at a time, which stays crisp where scaling one would not.
	rx = maxi(rx, 1)
	ry = maxi(ry, 1)
	return _cached("shadow%dx%d" % [rx, ry], func() -> Image:
		var img := Image.create_empty(rx * 2 + 2, ry * 2 + 2, false, Image.FORMAT_RGBA8)
		for y in ry * 2 + 2:
			for x in rx * 2 + 2:
				var v := Vector2((x + 0.5 - (rx + 1)) / float(rx), (y + 0.5 - (ry + 1)) / float(ry))
				var d: float = v.length()
				if d <= 0.8:
					img.set_pixel(x, y, Color(0, 0, 0, 0.45))
				elif d <= 1.0:
					img.set_pixel(x, y, Color(0, 0, 0, 0.25))
		return img)


static func crater_texture(r: int) -> Texture2D:
	# The meteor's mark: a dark bowl, a lighter rim of earth thrown up round it,
	# and a few clods scattered beyond. Seeded, so every crater of one size is
	# the same shape and the cache can hold it.
	r = maxi(r, 4)
	return _cached("crater%d" % r, func() -> Image:
		var size: int = r * 2 + 8
		var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
		var rng := RandomNumberGenerator.new()
		rng.seed = 7700 + r
		var c := Vector2(size / 2.0, size / 2.0)
		var bowl := Color(0.13, 0.1, 0.08, 0.7)
		var floor_ := Color(0.2, 0.16, 0.12, 0.6)
		var rim := Color(0.55, 0.45, 0.33, 0.55)
		var rim_lit := Color(0.66, 0.56, 0.42, 0.55)
		for y in size:
			for x in size:
				# Squashed top to bottom: a round hole seen at the angle the
				# rest of the world is drawn at.
				var v := Vector2(x + 0.5 - c.x, (y + 0.5 - c.y) * 1.35)
				var d: float = v.length() / float(r) + rng.randf_range(-0.06, 0.06)
				if d < 0.45:
					img.set_pixel(x, y, bowl)
				elif d < 0.75:
					img.set_pixel(x, y, floor_)
				elif d < 0.95:
					img.set_pixel(x, y, rim_lit if v.y < 0 else rim)
		for i in 10:
			var a: float = rng.randf() * TAU
			var p := c + Vector2(cos(a), sin(a) / 1.35) * float(r) * rng.randf_range(1.0, 1.25)
			var px := Vector2i(clampi(int(p.x), 0, size - 1), clampi(int(p.y), 0, size - 1))
			img.set_pixelv(px, rim_lit)
		return img)


static func scorch_texture(r: int) -> Texture2D:
	# The dynamite's mark: a black burn, ragged at the edge, with soot streaks
	# running out from it. Seeded for the same reason as the crater.
	r = maxi(r, 4)
	return _cached("scorch%d" % r, func() -> Image:
		var size: int = r * 2 + 6
		var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
		var rng := RandomNumberGenerator.new()
		rng.seed = 4400 + r
		var c := Vector2(size / 2.0, size / 2.0)
		for y in size:
			for x in size:
				var v := Vector2(x + 0.5 - c.x, (y + 0.5 - c.y) * 1.35)
				var d: float = v.length() / float(r * 0.8) + rng.randf_range(-0.12, 0.12)
				if d < 0.5:
					img.set_pixel(x, y, Color(0.05, 0.04, 0.04, 0.7))
				elif d < 0.85:
					img.set_pixel(x, y, Color(0.08, 0.07, 0.06, 0.5))
				elif d < 1.0:
					img.set_pixel(x, y, Color(0.1, 0.09, 0.08, 0.25))
		for i in 8:
			var a: float = rng.randf() * TAU
			var reach: float = float(r) * rng.randf_range(0.8, 1.15)
			for step in int(reach * 0.5):
				var p := c + Vector2(cos(a), sin(a) / 1.35) * (float(r) * 0.5 + step)
				var px := Vector2i(clampi(int(p.x), 0, size - 1), clampi(int(p.y), 0, size - 1))
				img.set_pixelv(px, Color(0.07, 0.06, 0.05, 0.4))
		return img)


# =============================================================================
# THE RING
# =============================================================================

class BlastRing extends Node2D:
	# One expanding ring of pushed air, a pixel thick, gone in a third of a
	# second. draw_arc with antialiasing off and a whole-pixel width, so it
	# stays a hard line at three times zoom.
	var reach: float = 30.0
	var colour: Color = Color.WHITE
	var _age: float = 0.0
	const SECONDS := 0.3

	func _process(delta: float) -> void:
		_age += delta
		if _age >= SECONDS:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var t: float = clampf(_age / SECONDS, 0.0, 1.0)
		var r: float = roundf(lerpf(reach * 0.3, reach, 1.0 - pow(1.0 - t, 2.0)))
		var c := colour
		c.a *= 1.0 - t
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, c, 1.0, false)
