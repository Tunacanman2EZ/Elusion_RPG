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
#   overlapping a body. Godot's body_entered only fires on enter transitions,
#   so a body already inside the area on spawn would never trigger damage.
#   waits one physics frame so the overlap query reflects the projectile's
#   actual world position before polling.
extends Area2D


# =============================================================================
# EXPORTED SETTINGS
# =============================================================================

@export var speed: float = 400.0
@export var damage: int = 10
@export var lifetime: float = 10.0


# =============================================================================
# STATE
# =============================================================================

var velocity: Vector2 = Vector2.ZERO


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# wire collision callbacks for both physics bodies and area hitboxes
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

	# failsafe despawn — if the arrow flies off into empty space, this
	# prevents leaked nodes accumulating in the scene tree
	get_tree().create_timer(lifetime).timeout.connect(queue_free)

	# catch bodies the arrow ALREADY overlaps on spawn. body_entered doesn't
	# fire for those — it only fires on outside-to-inside transitions.
	# this catches the "circle enemy, stop close, get shot at" bug where
	# the arrow spawns at a marker close enough to land inside the player.
	_check_initial_overlaps()


func _physics_process(delta: float) -> void:
	# straight-line motion at constant velocity.
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
	# wait one physics frame so Godot's overlap query reflects the
	# projectile's actual world position and monitoring state. without
	# this wait, the overlap query returns empty even when the arrow
	# spawned inside a body.
	if not is_inside_tree():
		return

	await get_tree().physics_frame

	# verify we still exist after the await — a normal body_entered could
	# have fired during the wait and queued us for deletion
	if not is_inside_tree():
		return

	for body in get_overlapping_bodies():
		_on_body_entered(body)
		return


# =============================================================================
# COLLISION HANDLERS
# =============================================================================

func _on_body_entered(body: Node) -> void:
	# physics body hit (CharacterBody2D) — try to damage and despawn.
	_try_damage(body)
	queue_free()


func _on_area_entered(area: Area2D) -> void:
	# area hit (typically a hurtbox) — the actual target is the area's parent.
	_try_damage(area.get_parent())
	queue_free()


# =============================================================================
# DAMAGE APPLICATION
# =============================================================================

func _try_damage(target: Node) -> void:
	# only damages player-grouped nodes that expose take_damage(amount).
	if target == null:
		return
	if target.is_in_group("player") and target.has_method("take_damage"):
		target.take_damage(damage)
