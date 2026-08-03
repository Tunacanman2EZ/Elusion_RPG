# turretprojectile.gd — fast small projectile fired by the healer class.
# travels in a fixed direction set on spawn, damages enemies on contact,
# despawns on hit, on hitting a wall, or after a max lifetime.
#
# usage:
# - healer.gd._fire_projectile() spawns this scene
# - sets direction (normalized), speed, damage, owner_group, and caster (NEW)
# - projectile flies until impact OR lifetime expiry
#
# sprite orientation:
# the sprite NEVER rotates — it stays visually upright regardless of travel
# direction. healer's projectile is a magical orb that floats in any
# direction without tilting (think of it like a slow-moving energy ball,
# not a thrown arrow). if you ever want directional rotation back, set
# rotation = direction.angle() + PI/2 in _ready (sprite is drawn pointing UP).
#
# friendly fire prevention:
# the owner_group field identifies who fired the projectile ("player" for
# healer shots, "enemies" for enemy-fired turrets if added later). projectiles
# never damage anything in their owner's group, so a player can't be hit by
# their own shots and enemies can't damage each other.
#
# XP ON HIT (NEW):
# grants XP back to whoever fired this — see caster/_grant_caster_xp()
# below, same pattern as slashwave.gd (warrior) and spelltargetcircle.gd
# (mage). single-target and despawns immediately on its first hit, unlike
# the stalagmite's AoE, so XP is granted exactly once per shot that lands —
# no "per enemy" question here.
extends Area2D


# =============================================================================
# EXPORTED SETTINGS
# =============================================================================

# how long (seconds) before the projectile auto-despawns if it never hits.
# protects against projectiles flying off-map forever and leaking nodes.
@export var max_lifetime: float = 2.0

# NEW: XP granted to caster on a successful hit. attack XP is universal
# (any class — see player.gd's gain_attack_xp()); magic XP is healer's
# boosted specialty via skill_proficiency.
@export var attack_xp_on_hit: int = 5
@export var magic_xp_on_hit: int = 5


# =============================================================================
# CONFIGURED ON SPAWN
# =============================================================================
# these are set by the spawner (healer.gd) immediately after instantiate(),
# so they're vars not @exports — runtime configuration rather than scene
# defaults. healer assigns them BEFORE add_child so _ready sees correct values.

# direction the projectile travels in (normalized vector)
var direction: Vector2 = Vector2.RIGHT

# travel speed in pixels per second
var speed: float = 400.0

# damage dealt to the first enemy hit
var damage: int = 8

# group name of the owner. used to prevent self-damage and same-team friendly
# fire. "player" if shot by player, "enemies" if shot by an enemy turret.
var owner_group: String = "player"

# NEW: identifies who fired this projectile — set by healer.gd on spawn,
# mirrors slashwave.gd's caster reference for warrior. used to grant XP
# back to the caster on impact, see _grant_caster_xp() below. null-guarded
# throughout in case something ever spawns this scene without setting it
# (e.g. a future enemy-fired turret variant, which shouldn't grant player
# skill XP at all).
var caster: Node = null


# =============================================================================
# STATE
# =============================================================================

# accumulated lifetime — incremented each frame in _physics_process,
# triggers queue_free when it reaches max_lifetime
var _lifetime: float = 0.0


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# sprite stays visually upright — no rotation assignment. the projectile
	# moves in any direction but the art remains in its drawn orientation
	# (pointing up). this gives a "floating magic orb" feel rather than a
	# directional arrow feel.

	# wire collision callbacks — guarded against double-connection in case
	# the scene was reused or pooled (or signals also wired in editor).
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	# straight-line motion at constant velocity.
	# direction is pre-normalized by the spawner.
	global_position += direction * speed * delta

	# lifetime expiry — covers off-screen flight without ever hitting anything
	_lifetime += delta
	if _lifetime >= max_lifetime:
		queue_free()


# =============================================================================
# COLLISION HANDLERS
# =============================================================================

func _on_body_entered(body: Node) -> void:
	# hit a CharacterBody2D — typically an enemy or environment wall.
	# skip our owner's group so we don't damage the shooter.
	if body.is_in_group(owner_group):
		return

	# damage the body if it's an enemy with take_damage. always despawn
	# regardless — projectiles shouldn't pass through walls or non-enemy
	# bodies even if they don't deal damage.
	if body.is_in_group("enemies") and body.has_method("take_damage"):
		body.take_damage(damage)
		_grant_caster_xp()
	queue_free()


func _on_area_entered(area: Area2D) -> void:
	# hit an Area2D — typically an enemy's hurtbox child. the actual target
	# is the area's parent since hurtboxes don't carry the take_damage method.
	var parent: Node = area.get_parent()
	if parent == null:
		return

	# skip our own team's hurtboxes (e.g., player's hurtbox if owner is player)
	if parent.is_in_group(owner_group):
		return

	# damage the parent if it's an enemy with take_damage, then despawn.
	# unlike _on_body_entered, we DON'T despawn on non-enemy areas — that
	# lets the projectile pass through non-combat areas (triggers, regions)
	# without dying. only enemy-hurtbox hits despawn from this path.
	if parent.is_in_group("enemies") and parent.has_method("take_damage"):
		parent.take_damage(damage)
		_grant_caster_xp()
		queue_free()


# =============================================================================
# XP ON HIT  (NEW)
# =============================================================================

func _grant_caster_xp() -> void:
	# see class comment for why this fires exactly once per shot. null-
	# guarded since caster isn't guaranteed to be set (e.g. an enemy-fired
	# turret variant shouldn't grant the player skill XP at all).
	if caster == null:
		return
	if caster.has_method("gain_attack_xp"):
		caster.gain_attack_xp(attack_xp_on_hit)
	if caster.has_method("gain_magic_xp"):
		caster.gain_magic_xp(magic_xp_on_hit)
