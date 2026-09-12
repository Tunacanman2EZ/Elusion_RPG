# petfireprojectile.gd — pet version of firesprite's fire orb projectile.
# damages ENEMIES instead of the player, uses a lifetime timer instead of
# VisibleOnScreenNotifier2D.
#
# min-visible window:
# the orb can't hit anything for its first `min_visible_time` seconds, so it
# renders for a few frames even at point-blank range instead of vanishing in
# the spawn frame and reading as invisible "melee" damage.
#
# structural twin of petelectricprojectile.gd — same logic, fire damage type.
extends Area2D


# =============================================================================
# EXPORTED SETTINGS
# =============================================================================

@export var speed: float = 300.0
@export var damage: int = 6
@export var damage_type: StringName = &"fire"
@export var lifetime: float = 4.0

# which group this projectile damages. pets fire at "enemies".
@export var target_group: String = "enemies"

# minimum time (seconds) the orb must exist before it can hit anything.
# guarantees the orb renders even at point-blank. tune down (0.05) if it
# overshoots close enemies, up (0.1) if it still isn't visible.
@export var min_visible_time: float = 0.08


# =============================================================================
# STATE
# =============================================================================

var direction: Vector2 = Vector2.ZERO

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
	position += direction * speed * delta


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
		target.take_damage(damage, damage_type)


# =============================================================================
# CLEANUP
# =============================================================================

func destroy_projectile() -> void:
	queue_free()
