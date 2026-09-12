# petarrow.gd — projectile fired by a PET. identical to the enemy arrow, but
# retargeted: it damages ENEMIES (the "enemies" group) instead of the player.
# used by pet.gd so companions can reuse the archer attack against mobs.
#
# collision: this scene's Area2D mask must detect the ENEMY collision layer
# (layer 4 in this project), so body/area_entered fires on enemies. the group
# check below is the second gate — collision finds them, the group confirms
# they're a valid pet target.
extends Area2D


# =============================================================================
# EXPORTED SETTINGS
# =============================================================================

@export var speed: float = 400.0
@export var damage: int = 5
@export var lifetime: float = 10.0

# which group this projectile damages. pets fire at "enemies".
@export var target_group: String = "enemies"


# =============================================================================
# STATE
# =============================================================================

var velocity: Vector2 = Vector2.ZERO


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
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

	# failsafe despawn if it flies into empty space
	get_tree().create_timer(lifetime).timeout.connect(queue_free)

	# catch enemies the arrow already overlaps on spawn (body_entered only
	# fires on enter transitions, not for bodies already inside on spawn)
	_check_initial_overlaps()


func _physics_process(delta: float) -> void:
	position += velocity * delta


# =============================================================================
# AIM / FIRING
# =============================================================================

func shoot_vector(direction: Vector2) -> void:
	# aim at any angle. the pet computes the direction to the nearest enemy
	# and passes it here. sprite rotates to face travel direction.
	velocity = direction.normalized() * speed
	rotation = velocity.angle()


func shoot(direction: String) -> void:
	# legacy cardinal interface, kept for parity with the enemy arrow.
	match direction:
		"left":  shoot_vector(Vector2.LEFT)
		"right": shoot_vector(Vector2.RIGHT)
		"up":    shoot_vector(Vector2.UP)
		"down":  shoot_vector(Vector2.DOWN)


# =============================================================================
# INITIAL OVERLAP CHECK
# =============================================================================

func _check_initial_overlaps() -> void:
	if not is_inside_tree():
		return

	await get_tree().physics_frame

	if not is_inside_tree():
		return

	for body in get_overlapping_bodies():
		_on_body_entered(body)
		return


# =============================================================================
# COLLISION HANDLERS
# =============================================================================

func _on_body_entered(body: Node) -> void:
	if _spent:
		return
	if body.is_in_group(target_group):
		_spent = true
		_try_damage(body)
		queue_free()


func _on_area_entered(area: Area2D) -> void:
	if _spent:
		return
	var parent = area.get_parent()
	if parent != null and parent.is_in_group(target_group):
		_spent = true
		_try_damage(parent)
		queue_free()


# =============================================================================
# DAMAGE APPLICATION
# =============================================================================

func _try_damage(target: Node) -> void:
	# only damages nodes in the target group (enemies) that expose take_damage.
	if target == null:
		return
	if target.is_in_group(target_group) and target.has_method("take_damage"):
		target.take_damage(damage)
