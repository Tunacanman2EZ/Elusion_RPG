# meteor.gd - the mage's attack while a Meteorite is equipped.
#
# Spawned by mage.gd where the mage aims, in place of the stalagmite. The art is
# Ahvassa's: one cratered stone. Everything around it is here, because the owner
# asked for it to "look a little realistic in terms of the meteor crashing into
# the ground":
#
#   1. It comes in from high up and off to one side, not straight down, and it
#      speeds up as it falls. Its shadow on the ground grows and darkens under
#      it, so the landing spot is readable before anything lands.
#   2. It trails fire and smoke on the way down and turns as it comes.
#   3. On impact (Blast): a flash, a ring of air, earth and rock thrown up,
#      dust, a short camera shake, and a crater left behind.
#   4. The stone itself stays in its crater, glowing, cools to grey, and fades.
#   5. The crater burns (0.12.0, BurningCrater): flames and a glow on the
#      ground, and fire damage to whatever stands in it for a few seconds.
#   6. THE FIRE VORTEX (0.14.0). The owner: "can you add a fire vortex around
#      the meteo when it falls to really draw out that final fantasy effect".
#      Three ribbons of fire corkscrew round its path behind it and sparks
#      whirl round the stone itself (_sky, drawn in the sky with the stone);
#      and on the ground a ring of fire swirls in toward the landing spot over
#      a growing glow, flames twisting up off it, tighter and brighter as the
#      stone comes down. All of it goes out on impact, where the blast takes over.
#      Picture only: what it hits and for how much is unchanged.
#
# Damage happens once, on impact, to every enemy inside HIT_RADIUS, and pays the
# caster magic XP per enemy the way the stalagmite does. Then the fire.
#
# TWICE AS WIDE SINCE 0.12.0. The owner: "dynamite douse not feel that special
# or meteor", then "i want the meteor to be bigger yes". Its hit was 22 across
# the stalagmite's 18 - a spell with a better picture. At 44 it lands on a
# group. Nothing is knocked back: the owner, "knock back is a bad idea".
#
# THE TIMELINE IS ADVANCED BY advance(), which _physics_process calls with the
# frame's delta. A test calls it directly with whatever time it wants to pass,
# so the fall and the impact can be checked without waiting for them.
#
# LAYERS, the same split spelltargetcircle.gd makes: the root (which draws the
# aim ring) and the shadow lie on the floor under every enemy, and the falling
# stone draws above everything, because it is in the sky.
class_name Meteor
extends Area2D


# How long the fall takes, from entering the screen to hitting the ground.
const FALL_SECONDS := 0.55

# Where the stone starts, relative to where it lands: up and to the left, so it
# comes in at an angle. Not straight above, which reads as a dropped rock rather
# than a meteor.
const START_OFFSET := Vector2(-60.0, -150.0)

# The hit. MATCHED to the CollisionShape2D in meteor.tscn and to the crater: a
# ring that under- or over-sold the area would be the stalagmite's old mistake
# (see circle_radius there). The stalagmite's is 18; the meteor's is the size
# of its own crater, and of the fire it leaves.
const HIT_RADIUS := 44.0

# After impact: how long the stone glows in its crater, then how long it takes
# to fade.
const COOL_SECONDS := 1.2
const FADE_SECONDS := 0.8

# Magic XP per enemy hit - the stalagmite's number, so changing weapon does not
# change how magic trains.
const MAGIC_XP_ON_HIT := 5

# THE FIRE VORTEX: how far the ribbons swing out from the stone's path, how
# far back up the path they reach, how many there are and how many points each
# is drawn through, and how fast the whole thing turns.
const VORTEX_RADIUS := 14.0
const VORTEX_LENGTH := 64.0
const VORTEX_STRANDS := 3
const VORTEX_POINTS := 24
const VORTEX_TURNS_PER_SECOND := 3.0
# The ground's ring of fire starts this far out (times HIT_RADIUS) and has
# swirled in to the inner figure by the time the stone lands.
const SWIRL_FROM := 1.25
const SWIRL_TO := 0.55

# Set by mage.gd before the meteor enters the tree.
var explosion_damage: int = 0
var caster: Node = null

# The second meteor of a double cast waits this long before it starts to fall,
# so the two land one after the other instead of as one bigger bang.
var delay: float = 0.0

var landed: bool = false
var _age: float = 0.0
var _hits: int = 0
# How far down the fall is (0 at the top, 1 landed), for the vortex.
var _fallen: float = 0.0

# THE FIRE VORTEX's pieces, built in code like BurningCrater's: the ribbons in
# the sky with the stone, the sparks whirling round it, and the flames
# twisting up off the ring on the ground.
var _sky: Node2D = null
var _whirl: CPUParticles2D = null
var _swirl: CPUParticles2D = null
var _floor_glow: Sprite2D = null

@onready var rock: Sprite2D = $rock
@onready var shadow: Sprite2D = $shadow
@onready var glow: Sprite2D = $glow
# The trails are the rock's siblings, not its children: the rock turns as it
# falls, and an emitter riding on it would spray in a spiral.
@onready var trail: CPUParticles2D = $trail
@onready var smoke_trail: CPUParticles2D = $smoketrail


func _ready() -> void:
	z_as_relative = false
	z_index = -1
	rock.z_as_relative = false
	rock.z_index = 6
	rock.position = START_OFFSET
	for emitter in [trail, smoke_trail]:
		emitter.z_as_relative = false
		emitter.z_index = 5
		emitter.position = START_OFFSET
	rock.visible = false
	shadow.visible = false
	glow.visible = false
	glow.z_as_relative = false
	glow.z_index = 5
	glow.position = START_OFFSET
	glow.texture = Blast.disc_texture(14, Color(1.0, 0.85, 0.45), Color(1.0, 0.4, 0.1))
	trail.emitting = false
	smoke_trail.emitting = false
	_build_vortex()
	queue_redraw()


func _build_vortex() -> void:
	# The ribbons: a bare Node2D in the sky layer that draws through _draw_sky().
	_sky = Node2D.new()
	_sky.name = "vortex"
	_sky.z_as_relative = false
	_sky.z_index = 6
	_sky.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sky.visible = false
	_sky.draw.connect(_draw_sky)
	add_child(_sky)
	# Sparks whirling round the stone, carried down with it.
	_whirl = _fire_emitter("whirl", 36, 0.35, VORTEX_RADIUS, 2.5, 3.5, Vector2.ZERO, 6)
	_whirl.local_coords = true
	_whirl.position = START_OFFSET
	_whirl.scale_amount_min = 2.0
	_whirl.scale_amount_max = 3.0
	# The ground lighting up where it will land, under the ring of fire.
	_floor_glow = Sprite2D.new()
	_floor_glow.name = "floorglow"
	_floor_glow.texture = Blast.disc_texture(int(HIT_RADIUS * 0.9), Color(1.0, 0.6, 0.2), Color(0.7, 0.15, 0.04))
	_floor_glow.scale = Vector2(1.0, 0.7)
	_floor_glow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var light := CanvasItemMaterial.new()
	light.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_floor_glow.material = light
	_floor_glow.modulate.a = 0.0
	_floor_glow.visible = false
	add_child(_floor_glow)
	# Flames twisting up off the ring of fire on the ground.
	_swirl = _fire_emitter("swirl", 48, 0.5, HIT_RADIUS * SWIRL_FROM, 1.2, 1.8, Vector2(0, -60), 4)
	_swirl.local_coords = true
	_swirl.scale = Vector2(1.0, 0.7)
	_swirl.scale_amount_min = 1.5
	_swirl.scale_amount_max = 2.5


func _fire_emitter(id: String, amount: int, lifetime: float, radius: float, orbit_min: float, orbit_max: float,
		pull: Vector2, z: int) -> CPUParticles2D:
	# Squares of fire on a circle, turning round its middle: the crater's fire
	# colours (burningcrater.gd), whole pixels.
	var p := CPUParticles2D.new()
	p.name = id
	p.amount = amount
	p.lifetime = lifetime
	p.emitting = false
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE_SURFACE
	p.emission_sphere_radius = radius
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.gravity = pull
	p.initial_velocity_min = 0.0
	p.initial_velocity_max = 6.0
	p.orbit_velocity_min = orbit_min
	p.orbit_velocity_max = orbit_max
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.0
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.3, 0.7, 1.0])
	ramp.colors = PackedColorArray([Color(1.0, 0.95, 0.6), Color(1.0, 0.65, 0.18),
		Color(0.85, 0.25, 0.06, 0.8), Color(0.3, 0.1, 0.05, 0.0)])
	p.color_ramp = ramp
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	p.z_as_relative = false
	p.z_index = z
	add_child(p)
	return p


func _physics_process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	_age += delta
	var falling: float = _age - delay
	if falling < 0.0:
		return

	if not landed:
		_fall(clampf(falling / FALL_SECONDS, 0.0, 1.0), delta)
		if falling >= FALL_SECONDS:
			_impact()
		return

	_cool(falling - FALL_SECONDS)


func _fall(t: float, delta: float) -> void:
	rock.visible = true
	shadow.visible = true
	trail.emitting = true
	smoke_trail.emitting = true
	# t*t: slow at the top of the screen, fastest as it lands.
	rock.position = START_OFFSET.lerp(Vector2.ZERO, t * t).round()
	trail.position = rock.position
	smoke_trail.position = rock.position
	rock.rotation += delta * 4.0
	rock.scale = Vector2.ONE * lerpf(0.8, 1.0, t)
	# Warm while it falls, with a burning halo behind it; _cool() brings it
	# back to the stone's own grey.
	rock.modulate = Color(1.3, 1.05, 0.9)
	glow.visible = true
	glow.position = rock.position
	glow.modulate.a = 0.55 + 0.25 * sin(_age * 40.0)
	# The shadow grows a whole pixel at a time - see Blast.shadow_texture().
	var rx: int = int(lerpf(3.0, 10.0, t))
	shadow.texture = Blast.shadow_texture(rx, maxi(1, int(rx * 0.55)))
	shadow.modulate.a = lerpf(0.35, 1.0, t)
	# THE FIRE VORTEX: round the stone, and swirling in on the ground.
	_fallen = t
	if _sky != null:
		_sky.visible = true
		_sky.queue_redraw()
	if _whirl != null:
		_whirl.emitting = true
		_whirl.position = rock.position
	if _swirl != null:
		_swirl.emitting = true
		_swirl.emission_sphere_radius = HIT_RADIUS * lerpf(SWIRL_FROM, SWIRL_TO, t)
		_swirl.orbit_velocity_min = lerpf(1.2, 2.4, t)
		_swirl.orbit_velocity_max = lerpf(1.8, 3.2, t)
	if _floor_glow != null:
		_floor_glow.visible = true
		_floor_glow.modulate.a = lerpf(0.08, 0.5, t)
	queue_redraw()


func _impact() -> void:
	landed = true
	rock.position = Vector2.ZERO
	rock.rotation = 0.0
	rock.scale = Vector2.ONE * 0.85
	# Into its crater: on the floor now, under anyone who walks over it.
	rock.z_index = -1
	shadow.visible = false
	glow.visible = false
	trail.emitting = false
	smoke_trail.emitting = false
	_vortex_out()
	queue_redraw()
	Audio.play("meteor_impact")
	_hits = _apply_damage()
	Blast.spawn(get_parent(), global_position, &"meteor", HIT_RADIUS)
	# The fire, beside the meteor rather than under it: the stone fades in two
	# seconds and the crater burns a little longer.
	BurningCrater.spawn(get_parent(), global_position, explosion_damage, HIT_RADIUS, caster)


func _apply_damage() -> int:
	# Every enemy inside the hit, once. Returns how many, for the tests.
	var hit := 0
	for body in get_overlapping_bodies():
		if not body.is_in_group("enemies") or not body.has_method("take_damage"):
			continue
		body.take_damage(explosion_damage)
		hit += 1
		if caster != null and is_instance_valid(caster) and caster.has_method("gain_magic_xp"):
			caster.gain_magic_xp(MAGIC_XP_ON_HIT)
	return hit


func _cool(since: float) -> void:
	# Glowing, then grey, then gone.
	var heat: float = clampf(1.0 - since / COOL_SECONDS, 0.0, 1.0)
	rock.modulate = Color(1.0 + 0.75 * heat, 1.0 - 0.05 * heat, 1.0 - 0.4 * heat,
		1.0 - clampf((since - COOL_SECONDS) / FADE_SECONDS, 0.0, 1.0))
	if since >= COOL_SECONDS + FADE_SECONDS:
		queue_free()


func hit_count() -> int:
	return _hits


func vortex_burning() -> bool:
	"""TRUE while the fire vortex is up: from the start of the fall to the
	impact. For the tests."""
	return _sky != null and _sky.visible and _whirl != null and _whirl.emitting and _swirl != null and _swirl.emitting \
		and _floor_glow != null and _floor_glow.visible


func _vortex_out() -> void:
	if _sky != null:
		_sky.visible = false
	if _whirl != null:
		_whirl.emitting = false
	if _swirl != null:
		_swirl.emitting = false
	if _floor_glow != null:
		_floor_glow.visible = false


func _draw() -> void:
	# The aim ring, the stalagmite's colour but fainter: the shadow already
	# says where it will land, and this says how far the hit reaches. Gone on
	# impact, when the crater says it instead.
	if landed:
		return
	draw_arc(Vector2.ZERO, HIT_RADIUS, 0.0, TAU, 40, Color(1.0, 0.35, 0.15, 0.45), 1.0, false)
	if _age - delay < 0.0:
		return
	# THE RING OF FIRE on the ground: three arcs turning round the landing
	# spot and swirling in toward it, longer and brighter as the stone comes.
	# Squashed to the floor, as the crater's glow is.
	var t: float = _fallen
	var r: float = HIT_RADIUS * lerpf(SWIRL_FROM, SWIRL_TO, t)
	var turn: float = _age * TAU * VORTEX_TURNS_PER_SECOND * lerpf(0.6, 1.4, t)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.7))
	for i in 3:
		var from: float = turn + TAU * i / 3.0
		var span: float = lerpf(0.6, 1.5, t)
		draw_arc(Vector2.ZERO, r, from, from + span, 14, Color(1.0, 0.55, 0.15, lerpf(0.3, 0.85, t)), 3.0, false)
		draw_arc(Vector2.ZERO, r * 0.7, from + 0.9, from + 0.9 + span * 0.8, 12,
			Color(1.0, 0.85, 0.4, lerpf(0.2, 0.7, t)), 1.0, false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_sky() -> void:
	# THE RIBBONS: VORTEX_STRANDS strands of fire corkscrewing round the
	# stone's path, from the stone back up the way it came - white-hot at the
	# stone, red and thinning behind it - each a broad orange band with a
	# bright core. Drawn on _sky, which is in the sky layer with the stone, so
	# it is over everything the way the stone is.
	if landed or rock == null:
		return
	var at: Vector2 = rock.position
	var back: Vector2 = (START_OFFSET - Vector2.ZERO).normalized()
	var side: Vector2 = back.orthogonal()
	var spin: float = _age * TAU * VORTEX_TURNS_PER_SECOND
	for strand in VORTEX_STRANDS:
		var points := PackedVector2Array()
		var band := PackedColorArray()
		var core := PackedColorArray()
		for k in VORTEX_POINTS:
			var f: float = float(k) / float(VORTEX_POINTS - 1)
			var phase: float = spin + f * TAU * 1.5 + TAU * strand / VORTEX_STRANDS
			# Wide at the stone, closing behind it, like a funnel.
			var swing: float = VORTEX_RADIUS * lerpf(1.0, 0.3, f)
			var p: Vector2 = at + back * (f * VORTEX_LENGTH) + side * sin(phase) * swing
			points.append(p.round())
			band.append(Color(1.0, lerpf(0.6, 0.2, f), lerpf(0.15, 0.03, f), lerpf(0.85, 0.0, f)))
			core.append(Color(1.0, lerpf(0.98, 0.6, f), lerpf(0.75, 0.2, f), lerpf(1.0, 0.0, f)))
		_sky.draw_polyline_colors(points, band, 3.0, false)
		_sky.draw_polyline_colors(points, core, 1.0, false)
