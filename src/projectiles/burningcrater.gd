# burningcrater.gd - the fire a meteor leaves where it lands (0.12.0).
#
# The owner: "i want the meteor to be bigger yes leave burning crator with fire
# damage", and "fire effects on the ground where meteor hits". meteor.gd spawns
# one on impact, the size of the hit. For BURN_SECONDS the crater burns: flames
# lick up out of it and the ground under it glows, and every BURN_EVERY seconds
# every enemy standing in it takes BURN_SHARE of the meteor's hit as FIRE
# damage. Then the flames die down and it is gone.
#
# NOBODY IS PUSHED. The owner, of knockback: "a bad idea". An enemy that walks
# out of the fire stops burning; one that stays keeps burning.
#
# ONE FIRE AT A TIME PER ENEMY. A mage casts every 0.45 s, mostly at the same
# spot, so craters overlap. If each burned on its own, a pack standing in five
# of them would burn five times over, and the Meteorite's damage would depend
# on how many casts happened to land in one place. An enemy burns from the
# crater that burned it last until that crater goes out (its meta
# &"burning_by", the crater's instance id), so the most fire any one enemy
# takes is BURN_SHARE of a hit every BURN_EVERY seconds. That is the figure the
# server's books allow for: the exporter writes BURN_SHARE and BURN_EVERY into
# gamedata.json as the mage's meteor_burn_share and meteor_burn_every, and
# gamedata.combat_bounds() adds them to a mage holding the Meteorite.
#
# BUILT IN CODE, like Blast: an Area2D with a circle the size of the hit, a
# glow on the floor and a fire emitter, all of whole-pixel squares so it is the
# same size of dot as the art. advance() is the timeline; _physics_process
# calls it, and a test calls it directly.
class_name BurningCrater
extends Area2D


# How long it burns, how often it bites, and how much of the meteor's hit a
# bite is. Five bites of a fifth: a meteor's hit again, spread over the burn,
# for whatever stays in the fire.
const BURN_SECONDS := 2.5
const BURN_EVERY := 0.5
const BURN_SHARE := 0.2
# Bites in a whole burn: one every BURN_EVERY, the last as it goes out.
const BITES := int(BURN_SECONDS / BURN_EVERY)

# The flames die down over the end of the burn rather than stopping at once.
const FADE_SECONDS := 0.6

# How strongly the ground glows under the fire, before it fades.
const GLOW_ALPHA := 0.55

# The meteor's own layers: a player's attack that looks for enemies.
const LAYER := 32
const ENEMY_MASK := 8

var radius: float = 44.0
# The meteor's hit; a bite is BURN_SHARE of it.
var hit_damage: int = 0
var caster: Node = null
var burns_dealt: int = 0

var _age: float = 0.0
var _bites: int = 0
var _out: bool = false
var _flames: CPUParticles2D = null
var _embers: CPUParticles2D = null
var _glow: Sprite2D = null


# =============================================================================
# SPAWNING
# =============================================================================

static func spawn(parent: Node, at: Vector2, from_hit: int, reach: float, by: Node) -> BurningCrater:
	# The one way in. Built after the move, for the reason Blast.spawn() gives.
	var crater := BurningCrater.new()
	crater.radius = reach
	crater.hit_damage = from_hit
	crater.caster = by
	parent.add_child(crater)
	crater.global_position = at
	crater.reset_physics_interpolation()
	crater._build()
	return crater


func _build() -> void:
	name = "burningcrater"
	collision_layer = LAYER
	collision_mask = ENEMY_MASK
	monitorable = false
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	add_child(shape)

	# On the floor, over the crater mark (z -2) and under everybody.
	z_as_relative = false
	z_index = -1
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	_glow = Sprite2D.new()
	_glow.name = "glow"
	_glow.texture = Blast.disc_texture(int(radius * 0.8), Color(1.0, 0.62, 0.2), Color(0.75, 0.2, 0.05))
	_glow.modulate = Color(1, 1, 1, GLOW_ALPHA)
	# Squashed to the floor: the world is seen from above and at a slant.
	_glow.scale = Vector2(1.0, 0.7)
	# Added, so the crater under it lights up rather than being painted over.
	var light := CanvasItemMaterial.new()
	light.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = light
	add_child(_glow)

	# Tongues of fire: the round puff Blast's fireballs are made of, smaller,
	# rising and shrinking as they go.
	_flames = _emitter(maxi(16, int(radius * 1.1)), 0.7, Vector2(10, 24), 0.45, 1.05, -45.0, 4)
	_flames.name = "flames"
	_flames.texture = Blast.puff_texture()
	_flames.scale_amount_curve = _shrink()
	# And sparks: single squares, slower, drifting up out of it.
	_embers = _emitter(maxi(8, int(radius * 0.4)), 1.2, Vector2(4, 12), 1.0, 2.0, -14.0, 4)
	_embers.name = "embers"
	_embers.color_ramp = _ramp([[0.0, Color(1.0, 0.85, 0.4)], [0.5, Color(1.0, 0.45, 0.1)],
		[1.0, Color(0.6, 0.15, 0.05, 0.0)]])


func _emitter(amount: int, lifetime: float, velocity: Vector2, size_min: float, size_max: float,
		gravity_y: float, z: int) -> CPUParticles2D:
	# A burning patch, not a burst: always emitting, from anywhere in the
	# crater, rising. Squares, as Blast's sparks are.
	var p := CPUParticles2D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius * 0.75
	p.scale = Vector2(1.0, 0.7)
	p.direction = Vector2(0, -1)
	p.spread = 20.0
	p.gravity = Vector2(0, gravity_y)
	p.initial_velocity_min = velocity.x
	p.initial_velocity_max = velocity.y
	p.scale_amount_min = size_min
	p.scale_amount_max = size_max
	p.color_ramp = _ramp([[0.0, Color(1.0, 0.95, 0.6)], [0.3, Color(1.0, 0.65, 0.18)],
		[0.7, Color(0.85, 0.25, 0.06, 0.8)], [1.0, Color(0.3, 0.1, 0.05, 0.0)]])
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Fire stands up out of the ground, over whoever is standing in it.
	p.z_as_relative = false
	p.z_index = z
	add_child(p)
	return p


static func _shrink() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 1.0))
	c.add_point(Vector2(1.0, 0.25))
	return c


static func _ramp(stops: Array) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(stops.map(func(s: Array) -> float: return float(s[0])))
	g.colors = PackedColorArray(stops.map(func(s: Array) -> Color: return s[1] as Color))
	return g


# =============================================================================
# THE BURN
# =============================================================================

func _physics_process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	if _out:
		return
	_age += delta
	# BY THE BITE'S OWN TIME, not by what is left of a step: a long step (a
	# hitch, or a test) still bites every time it should have, and never past
	# the end of the burn.
	while _bites < BITES and float(_bites + 1) * BURN_EVERY <= _age + 0.0001:
		_bites += 1
		_burn()
	var left: float = BURN_SECONDS - _age
	if left < FADE_SECONDS:
		var f: float = clampf(left / FADE_SECONDS, 0.0, 1.0)
		if _glow != null:
			_glow.modulate.a = GLOW_ALPHA * f
		if _flames != null and f < 0.5:
			_flames.emitting = false
	if _age >= BURN_SECONDS:
		_go_out()


func burning() -> bool:
	return not _out


func burn_damage() -> int:
	return maxi(1, roundi(float(hit_damage) * BURN_SHARE))


func _burn() -> void:
	var bite: int = burn_damage()
	for body in get_overlapping_bodies():
		if not body.is_in_group("enemies") or not body.has_method("take_damage"):
			continue
		# ONE FIRE AT A TIME: see the top of the file.
		var by: int = int(body.get_meta(&"burning_by", 0))
		if by != 0 and by != get_instance_id():
			var other: Object = instance_from_id(by)
			if other != null and is_instance_valid(other) and other is BurningCrater \
					and (other as BurningCrater).burning():
				continue
		body.set_meta(&"burning_by", get_instance_id())
		body.take_damage(bite, Element.Type.FIRE)
		burns_dealt += 1


func _go_out() -> void:
	_out = true
	set_deferred("monitoring", false)
	if _flames != null:
		_flames.emitting = false
	if _embers != null:
		_embers.emitting = false
	if _glow != null:
		_glow.visible = false
	# The last flames finish rising before the node goes. Connected to this
	# node's own method, as Blast does: a scene change frees the node, and a
	# freed node's connections go with it.
	if is_inside_tree():
		get_tree().create_timer(1.2).timeout.connect(queue_free)
	else:
		queue_free()
