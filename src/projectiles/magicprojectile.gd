# magicprojectile.gd — magic projectile fired by the electricspirit enemy.
# travels in any direction (cardinal or arbitrary angle), damages the player
# on contact, and despawns on any collision or when it leaves the screen.
#
# this script is the structural twin of fireprojectile.gd and arrow.gd —
# same pattern, different scene/damage/visual. if you change one, you
# probably want to mirror the change to the others for consistency.
extends Area2D


# =============================================================================
# EXPORTED SETTINGS
# =============================================================================

@export var speed: float = 300.0
@export var damage: int = 11
@export var damage_type: StringName = &"magic"


# =============================================================================
# STATE
# =============================================================================

var direction: Vector2 = Vector2.ZERO


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

	# catch bodies already overlapping on spawn — see notes in arrow.gd
	# for the "circle enemy, stop close, get shot at" bug. waits one
	# physics frame so the overlap query reflects the orb's actual
	# world position before polling.
	_check_initial_overlaps()


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
# INITIAL OVERLAP CHECK
# =============================================================================

func _check_initial_overlaps() -> void:
	# wait one physics frame so Godot's overlap query reflects the orb's
	# actual world position. without this wait the query returns empty
	# even when the orb spawned inside a body.
	if not is_inside_tree():
		return

	await get_tree().physics_frame

	# verify we still exist after the await
	if not is_inside_tree():
		return

	for body in get_overlapping_bodies():
		_on_body_entered(body)
		return


# =============================================================================
# COLLISION HANDLERS
# =============================================================================

func _on_body_entered(body: Node2D) -> void:
	if _spent:
		return
	_spent = true
	_try_damage(body)
	destroy_projectile()


func _on_area_entered(area: Area2D) -> void:
	if _spent:
		return
	_spent = true
	_try_damage(area.get_parent())
	destroy_projectile()


func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
	destroy_projectile()


# =============================================================================
# DAMAGE APPLICATION
# =============================================================================

func _try_damage(target: Node) -> void:
	if target == null:
		return
	if target.is_in_group(&"player") and target.has_method(&"take_damage"):
		target.take_damage(damage, damage_type)


# =============================================================================
# CLEANUP
# =============================================================================

func destroy_projectile() -> void:
	queue_free()
