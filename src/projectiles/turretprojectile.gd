# turretprojectile.gd — the healer's magic orb: a light-green spell that weaves
# toward the nearest enemy and pops on the first one it reaches.
#
# usage:
# - healer.gd._fire_projectile() spawns this scene and sets direction, speed,
#   damage, owner_group, and caster
# - on spawn the orb latches onto the nearest enemy, curves toward that enemy's
#   BODY (not its origin) while weaving side to side (~), and deals its damage
#   the instant it gets within reach of the enemy — then despawns.
#
# =============================================================================
# THE HIT SYSTEM — PER-FRAME DISTANCE, NOT PHYSICS SIGNALS  (this is the fix)
# =============================================================================
# Every enemy's real hurtbox is TINY and OFF-CENTRE. On the slimes it's an 8px
# circle offset to (-1, -5) from the enemy's ROOT — and the root sits at the
# creature's FEET, with the sprite drawn ~18px above it. So the visible slime is
# a ~48px blob whose actual hittable area is a little circle floating near its
# middle.
#
# The old orb homed at `enemy.global_position` (the FEET) and left hits to the
# physics engine's body_entered/area_entered signals. Between aiming below the
# body and the weave rocking the orb off-line, it kept threading past that little
# circle without ever overlapping it — so no signal, no damage, and the shot
# just weaved off and expired. That is the bug that read as "the orb reaches the
# enemy and does nothing / vanishes."
#
# The fix is the system RotMG and Darza's Dominion use: forget the physics
# engine. Every physics frame we measure the orb's distance to each live enemy's
# HURTBOX centre and, the moment it's within `hurtbox radius + hit_pad`, we deal
# the damage and despawn. No collision layers, no monitoring flags, no signal
# timing — just geometry we control. `collision_mask` is zeroed and monitoring is
# turned off so the physics engine can NEVER despawn this orb early; the only
# things that end it are a hit or its lifetime.
#
# We read the enemy's hurtbox node LIVE each frame (its global position and shape
# radius), so this stays correct no matter how a variant is offset or scaled —
# e.g. the small-slime form — without hard-coding any numbers per enemy.
#
# =============================================================================
# MOVEMENT — WEAVE + HOMING
# =============================================================================
#   HOMING: `direction` is steered toward the latched enemy's BODY every frame
#           with the shared Homing helper — a turn RATE, not a snap, so it curves
#           the way the pet orbs do (see homing.gd). latched on spawn, dropped
#           once past so it never boomerangs.
#   WEAVE:  the orb travels along `direction` rocked side to side by a sine, so
#           it snakes (~) toward the target. the amplitude is an ANGLE, so the
#           weave looks the same at any speed. the forgiving hit radius above is
#           what lets the weave stay lively without ever costing a hit.
#
# =============================================================================
# ALWAYS GLOWS — UNSHADED
# =============================================================================
# the sprite is given an UNSHADED material in _ready so a dark scene's
# CanvasModulate and lights cannot dim it — it always shows its own light-green
# art at full brightness. one static material is shared by every orb.
#
# sprite orientation: the sprite NEVER rotates — a floating orb, not a thrown
# arrow. the weave moves the orb's PATH, not its facing.
#
# friendly fire: owner_group identifies who fired ("player" for healer shots).
# the orb never damages anything in its owner's group.
#
# XP ON HIT: grants XP back to whoever fired this — see _grant_caster_xp(),
# same pattern as slashwave.gd (warrior) and spelltargetcircle.gd (mage).
extends Area2D


# =============================================================================
# EXPORTED SETTINGS
# =============================================================================

# how long (seconds) before the projectile auto-despawns if it never reaches an
# enemy.
@export var max_lifetime: float = 3.5

# XP granted to the caster on a successful hit.
@export var attack_xp_on_hit: int = 5
@export var magic_xp_on_hit: int = 5

# HOMING — degrees per second the orb may turn to follow the enemy it latched
# onto on spawn. a rate, not a snap (see homing.gd). 0 makes it a straight shot.
@export var homing_turn_rate: float = 200.0

# WEAVE — the ~ motion. amplitude is how far (in degrees) the travel direction
# rocks off the homing heading; frequency is how fast it oscillates. set the
# amplitude to 0 for a clean homing arc with no snake.
@export var weave_amplitude_deg: float = 22.0
@export var weave_frequency: float = 12.0

# HIT REACH — extra pixels added to the enemy's own hurtbox radius to decide when
# the orb "reaches" it. Bigger = pops a touch sooner / more forgiving; smaller =
# has to bury deeper into the body first. This plus the enemy's live hurtbox
# radius is the whole hit test — see the header. Tune here if the orb feels like
# it pops too early or grazes past.
@export var hit_pad: float = 14.0


# =============================================================================
# CONFIGURED ON SPAWN
# =============================================================================
# set by the spawner (healer.gd) immediately after instantiate(), BEFORE
# add_child, so _ready sees correct values.

var direction: Vector2 = Vector2.RIGHT
var speed: float = 400.0
var damage: int = 8
var owner_group: String = "player"
var caster: Node = null


# =============================================================================
# STATE
# =============================================================================

# fallback reach (px) when an enemy exposes no readable hurtbox shape — a slime's
# hurtbox is radius 8, so this covers a body of roughly that size on its own.
const DEFAULT_ENEMY_RADIUS: float = 10.0

# accumulated lifetime — triggers queue_free at max_lifetime.
var _lifetime: float = 0.0

# the enemy this orb is curving toward and testing against. latched on spawn,
# dropped once passed (see _home / homing.gd's is_past). null when there was no
# enemy to seek — the orb then just weaves along the direction it was fired.
var _homing_target: Node2D = null

# has this orb already spent its one hit? guards against a second hit in the same
# frame before queue_free() takes effect.
var _spent: bool = false

# advances every physics frame; drives the weave's sine.
var _time: float = 0.0

# shared unshaded material so the orb ignores scene lighting. static: one for
# every orb, built lazily on the first spawn.
static var _glow_material: CanvasItemMaterial = null


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# WE OWN HITS OURSELVES (see header). Kill every physics-engine path so it can
	# neither despawn this orb early nor fight our per-frame check: no mask means
	# nothing is detected, monitoring off means no body/area signals fire at all.
	collision_mask = 0
	collision_layer = 0
	monitoring = false
	monitorable = false

	# ALWAYS GLOW + animate. unshaded material so a dark scene can't dim the orb;
	# play the shimmer so it isn't a frozen frame. shared material via the static.
	var sprite: AnimatedSprite2D = get_node_or_null("animatedsprite2d")
	if sprite != null:
		if _glow_material == null:
			_glow_material = CanvasItemMaterial.new()
			_glow_material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		sprite.material = _glow_material
		if sprite.sprite_frames != null and sprite.sprite_frames.has_animation(&"projectile"):
			sprite.play(&"projectile")

	# LATCH A TARGET ON SPAWN, not every frame. re-acquiring mid-flight makes a
	# shot chase whatever wanders closest and reads as a bug; the pet orbs latch
	# the same way. no enemy → _homing_target stays null and the orb just weaves.
	_homing_target = _find_nearest_enemy()


func _physics_process(delta: float) -> void:
	_time += delta

	# STEER FIRST, THEN MOVE — same order as petfireprojectile.gd. turning after
	# the move advances the orb along last frame's heading and then points it
	# elsewhere, lagging its own path by a frame.
	direction = _home(delta, direction)

	# THE WEAVE (~). rock the travel direction side to side by a sine. rotating the
	# heading (rather than adding a sideways velocity) keeps the weave centred on
	# the path instead of drifting off it.
	var wobble: float = sin(_time * weave_frequency) * deg_to_rad(weave_amplitude_deg)
	var travel: Vector2 = direction.rotated(wobble)
	global_position += travel * speed * delta

	# THE HIT — per-frame distance to each enemy's live hurtbox (see header).
	if not _spent:
		var enemy: Node2D = _enemy_in_reach()
		if enemy != null:
			_spent = true
			_hit(enemy)
			return

	# lifetime expiry — covers a shot that never reaches anything.
	_lifetime += delta
	if _lifetime >= max_lifetime:
		queue_free()


# =============================================================================
# HOMING
# =============================================================================

func _home(delta: float, heading: Vector2) -> Vector2:
	# steering off, or nothing to steer toward → fly straight (still weaves).
	if homing_turn_rate <= 0.0 or not is_instance_valid(_homing_target):
		_homing_target = null
		return heading

	# aim at the enemy's BODY, not its root origin — the root sits at the feet,
	# well below the hittable area, and homing at the feet was half the old miss.
	var to: Vector2 = _enemy_hit_point(_homing_target)

	# LATCHED, NOT RE-CHECKED. once the orb is level with or past its target it
	# drops it and flies straight — a shot that re-engages after overshooting
	# turns into a boomerang. same rule as petfireprojectile.gd.
	if Homing.is_past(heading, global_position, to):
		_homing_target = null
		return heading

	return Homing.steer(heading, global_position, to, homing_turn_rate, delta)


# =============================================================================
# HIT DETECTION  (pure geometry — no physics engine)
# =============================================================================

func _enemy_in_reach() -> Node2D:
	# the first live enemy whose hurtbox the orb is now touching. checks EVERY
	# enemy, not just the latched one, so a weaving orb still connects with a slime
	# that drifts into its path. distance is measured to the enemy's real hurtbox
	# centre and compared against that hurtbox's radius plus hit_pad.
	for node in get_tree().get_nodes_in_group("enemies"):
		if not (node is Node2D) or not is_instance_valid(node):
			continue
		var enemy: Node2D = node as Node2D
		# never damage our own team (defensive — enemies aren't in "player").
		if enemy.is_in_group(owner_group):
			continue
		if not enemy.has_method("take_damage"):
			continue
		var reach: float = _enemy_radius(enemy) + hit_pad
		if global_position.distance_squared_to(_enemy_hit_point(enemy)) <= reach * reach:
			return enemy
	return null


func _enemy_hit_point(enemy: Node2D) -> Vector2:
	# the enemy's hurtbox centre in world space. read live so it's right for a
	# moving, offset, or rescaled enemy. falls back to the root origin only if the
	# enemy has no hurtbox shape node at the conventional path.
	var shape_node: Node = enemy.get_node_or_null("hurtbox/collisionshape2d")
	if shape_node is Node2D:
		return (shape_node as Node2D).global_position
	return enemy.global_position


func _enemy_radius(enemy: Node2D) -> float:
	# the enemy's hurtbox radius in world pixels, read live from its shape and
	# scaled by the node's global scale. Circle and Capsule shapes both expose a
	# `radius`. anything without one falls back to DEFAULT_ENEMY_RADIUS.
	var shape_node: Node = enemy.get_node_or_null("hurtbox/collisionshape2d")
	if shape_node is CollisionShape2D:
		var shape: Shape2D = (shape_node as CollisionShape2D).shape
		if shape != null and "radius" in shape:
			var scale_x: float = absf((shape_node as Node2D).global_scale.x)
			return float(shape.radius) * scale_x
	return DEFAULT_ENEMY_RADIUS


func _find_nearest_enemy() -> Node2D:
	# nearest live enemy by squared distance to its hurtbox, chosen once on spawn.
	# no aggro-range gate (unlike the pet's version) — the player already aimed the
	# shot, so the orb just needs something to curve toward.
	var nearest: Node2D = null
	var nearest_d: float = INF
	for node in get_tree().get_nodes_in_group("enemies"):
		if not (node is Node2D) or not is_instance_valid(node):
			continue
		var enemy: Node2D = node as Node2D
		var d: float = global_position.distance_squared_to(_enemy_hit_point(enemy))
		if d < nearest_d:
			nearest_d = d
			nearest = enemy
	return nearest


# =============================================================================
# DAMAGE
# =============================================================================

func _hit(enemy: Node2D) -> void:
	# deal the damage, pay out the caster's XP, and despawn. take_damage's second
	# arg (element) defaults, so one arg is correct here — see baseenemy.take_damage.
	enemy.take_damage(damage)
	_grant_caster_xp()
	queue_free()


func _grant_caster_xp() -> void:
	# null-guarded since caster isn't guaranteed to be set (e.g. an enemy-fired
	# turret variant shouldn't grant the player skill XP at all).
	if caster == null:
		return
	if caster.has_method("gain_attack_xp"):
		caster.gain_attack_xp(attack_xp_on_hit)
	if caster.has_method("gain_magic_xp"):
		caster.gain_magic_xp(magic_xp_on_hit)
