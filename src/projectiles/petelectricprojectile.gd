# petelectricprojectile.gd — pet version of electricsprite's magic projectile.
# damages ENEMIES instead of the player, uses a lifetime timer instead of
# VisibleOnScreenNotifier2D.
#
# min-visible window:
# the orb can't hit anything for its first `min_visible_time` seconds. this
# guarantees it renders for a few frames even at point-blank range — without
# it, a close-range orb spawns on top of the enemy, hits + despawns in ~1
# frame, and reads as invisible "melee" damage instead of a visible zap.
extends Area2D


# =============================================================================
# EXPORTED SETTINGS
# =============================================================================

@export var speed: float = 300.0
@export var damage: int = 5
# The element this projectile deals. Element.Type is an int, not the
# StringName this used to be: an enum is checked when the file is parsed,
# and &"posion" was only ever going to be found by someone wondering why a
# resistance did nothing.
#
# Overwritten at spawn for anything an enemy fires — see
# BaseEnemy.spawn_projectile_node(), which stamps the caster's element on
# it so a water slime's shot IS water without a second scene existing.
# LIGHTNING, NOT WIND — the same correction magicprojectile.gd needed, on the
# player's side of the same creature.
#
# The enum had no LIGHTNING when this was written, so the electric sprite was
# filed under WIND and its orb followed. The enemy version was fixed; this one
# is the pet the player summons from the same sheet, and it kept the old label.
# petelectricsprite is a LIGHTNING creature, so its orb deals lightning.
@export var element: int = Element.Type.LIGHTNING
@export var lifetime: float = 4.0

# which group this projectile damages. pets fire at "enemies".
@export var target_group: String = "enemies"

# minimum time (seconds) the orb must exist before it can hit anything.
# guarantees the orb renders for at least a few frames even at point-blank
# range, so close shots don't look like instant melee. tune down (0.05) if
# the orb overshoots close enemies, up (0.1) if it still isn't visible.
@export var min_visible_time: float = 0.08
# Degrees per second this shot may turn to follow what it was fired at.
# 0 is a straight shot, which is what anything that never calls home_on() gets —
# so this stays off for every existing user and only the pet turns it on.
@export var homing_turn_rate: float = 0.0



# =============================================================================
# STATE
# =============================================================================

var direction: Vector2 = Vector2.ZERO
# What this shot is following, or null for a straight shot. Dropped for good the
# moment it is past — see Homing.is_past().
var _homing_target: Node2D = null


# gates collision — false for the first min_visible_time seconds so the orb
# renders before it's allowed to hit + despawn.
var _can_hit: bool = false


# =============================================================================
# LIFECYCLE
# =============================================================================

# NEW: has this projectile already dealt its damage?
#
# Godot's Area2D emits body_entered and area_entered as SEPARATE signals, and
# every character in this game carries both a physics body and a hurtbox Area2D
# on the same collision layer. So one hit fires two signals in the same physics
# frame, and queue_free() is deferred to the end of the frame - it does not
# stop the second handler from running.
#
# Without this latch the warrior and the tank took exactly DOUBLE damage from
# every shot. The mage and healer were safe only by accident: their hurtbox
# collision_layer was never set, so the area signal never fired for them.
#
# slashwave.gd solved the same problem with a list of instance IDs because it
# pierces several enemies. This projectile only ever hits one thing, so a
# single boolean is enough.
var _spent: bool = false


func _ready() -> void:
	if has_node("animatedsprite2d"):
		$animatedsprite2d.play("projectile")

	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)

	# failsafe despawn — replaces VisibleOnScreenNotifier2D, which caused
	# premature despawn issues on other pet projectiles.
	get_tree().create_timer(lifetime).timeout.connect(queue_free)

	# brief delay before the orb can hit — guarantees it renders first so
	# close-range shots don't vanish in the spawn frame.
	_enable_hitting_after(min_visible_time)


func _enable_hitting_after(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	_can_hit = true


func _physics_process(delta: float) -> void:
	# STEER FIRST, THEN MOVE. Turning after the move would advance the orb a
	# frame along last frame's heading and then point it somewhere else, so the
	# sprite would lag its own travel by one frame at every turn.
	direction = _home(delta, direction)
	if direction != Vector2.ZERO:
		rotation = direction.angle()
	position += direction * speed * delta


func _home(delta: float, heading: Vector2) -> Vector2:
	# NOT LAUNCHED YET. The pet calls shoot_vector() deferred (see the spawn
	# note in pet.gd), so a physics frame can land here before there is any
	# heading at all. Falling through would hand Homing.is_past() a zero vector,
	# whose dot product is 0 against anything — it would read as "already past"
	# and drop the target before the shot had moved a single pixel.
	if heading == Vector2.ZERO:
		return heading

	if homing_turn_rate <= 0.0 or not is_instance_valid(_homing_target):
		_homing_target = null
		return heading

	var to: Vector2 = _homing_target.global_position
	if Homing.is_past(heading, global_position, to):
		# LATCHED, not re-checked. A shot that re-acquires after overshooting
		# turns around and comes back, which is not what anyone fired.
		_homing_target = null
		return heading

	return Homing.steer(heading, global_position, to, homing_turn_rate, delta)


# =============================================================================
# AIM / FIRING
# =============================================================================

func shoot(dir: String) -> void:
	match dir:
		"left":  shoot_vector(Vector2.LEFT)
		"right": shoot_vector(Vector2.RIGHT)
		"up":    shoot_vector(Vector2.UP)
		"down":  shoot_vector(Vector2.DOWN)


func shoot_vector(dir: Vector2) -> void:
	direction = dir.normalized()
	rotation = direction.angle()


func home_on(target: Node2D, turn_rate_deg: float) -> void:
	# Called by the pet right after shoot_vector(), so the shot already has a
	# heading to steer FROM. Passing null or a rate of 0 leaves it a straight
	# shot, which is what every caller that does not know about homing gets.
	_homing_target = target
	homing_turn_rate = turn_rate_deg


# =============================================================================
# COLLISION HANDLERS
# =============================================================================

func _on_body_entered(body: Node2D) -> void:
	# ignore hits during the min-visible window so the orb renders first.
	if not _can_hit:
		return
	if _spent:
		return
	if body.is_in_group(target_group):
		_spent = true
		_try_damage(body)
		destroy_projectile()


func _on_area_entered(area: Area2D) -> void:
	if not _can_hit:
		return
	var parent: Node = area.get_parent()
	if _spent:
		return
	if parent != null and parent.is_in_group(target_group):
		_spent = true
		_try_damage(parent)
		destroy_projectile()


# =============================================================================
# DAMAGE APPLICATION
# =============================================================================

func _try_damage(target: Node) -> void:
	if target == null:
		return
	if target.is_in_group(target_group) and target.has_method(&"take_damage"):
		target.take_damage(damage, element)


# =============================================================================
# CLEANUP
# =============================================================================

func destroy_projectile() -> void:
	queue_free()
