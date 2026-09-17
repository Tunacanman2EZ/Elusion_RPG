# arrow projectile fired by the bushsniper enemy.
# moves in a straight line, damages the player on contact, auto-despawns
# after `lifetime` seconds if it never hits anything.
#
# usage:
# - bushsniper calls shoot_vector(direction) with a normalized vector
#   pointing from the sniper toward the player at fire time
# - shoot(direction_string) is kept for legacy enemies using cardinal-only aim
#
# collision:
# - body_entered fires on physics bodies (the player CharacterBody2D)
# - area_entered fires on Area2D hitboxes — we use the parent as the target
# - _check_initial_overlaps catches the case where the arrow spawns ALREADY
#   overlapping a body (point-blank shots). waits one physics frame so the
#   overlap query reflects the arrow's real world position.
extends Area2D


# =============================================================================
# EXPORTED SETTINGS
# =============================================================================

@export var speed: float = 400.0
@export var damage: int = 12
@export var lifetime: float = 10.0


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

	get_tree().create_timer(lifetime).timeout.connect(queue_free)

	_check_initial_overlaps()


func _physics_process(delta: float) -> void:
	position += velocity * delta


# =============================================================================
# AIM / FIRING
# =============================================================================

func shoot_vector(direction: Vector2) -> void:
	# aim the arrow at any angle. used by bushsniper for player-tracking shots.
	# the sprite is rotated to match the velocity so the arrowhead always
	# points in the direction of travel.
	velocity = direction.normalized() * speed
	rotation = velocity.angle()


func shoot(direction: String) -> void:
	# legacy cardinal-direction interface — kept for compatibility with
	# any enemy still using string directions instead of vectors.
	match direction:
		"left":  shoot_vector(Vector2.LEFT)
		"right": shoot_vector(Vector2.RIGHT)
		"up":    shoot_vector(Vector2.UP)
		"down":  shoot_vector(Vector2.DOWN)


# =============================================================================
# INITIAL OVERLAP CHECK
# =============================================================================

func _check_initial_overlaps() -> void:
	# wait one physics frame so Godot's overlap query reflects the arrow's
	# actual world position, then catch any body it already overlaps
	# (point-blank shots that body_entered wouldn't fire for).
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
	_spent = true
	_try_damage(body)
	queue_free()


func _on_area_entered(area: Area2D) -> void:
	if _spent:
		return
	_spent = true
	_try_damage(area.get_parent())
	queue_free()


# =============================================================================
# DAMAGE APPLICATION
# =============================================================================

func _try_damage(target: Node) -> void:
	if target == null:
		return
	if target.is_in_group("player") and target.has_method("take_damage"):
		target.take_damage(damage)
