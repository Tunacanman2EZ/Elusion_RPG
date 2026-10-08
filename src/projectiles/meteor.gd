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

# Set by mage.gd before the meteor enters the tree.
var explosion_damage: int = 0
var caster: Node = null

# The second meteor of a double cast waits this long before it starts to fall,
# so the two land one after the other instead of as one bigger bang.
var delay: float = 0.0

var landed: bool = false
var _age: float = 0.0
var _hits: int = 0

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
	queue_redraw()


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


func _draw() -> void:
	# The aim ring, the stalagmite's colour but fainter: the shadow already
	# says where it will land, and this says how far the hit reaches. Gone on
	# impact, when the crater says it instead.
	if landed:
		return
	draw_arc(Vector2.ZERO, HIT_RADIUS, 0.0, TAU, 40, Color(1.0, 0.35, 0.15, 0.45), 1.0, false)
