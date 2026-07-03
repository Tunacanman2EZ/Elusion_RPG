# fireprojectile.gd — fire projectile fired by the firesprite enemy.
# travels in any direction, damages the player on contact, and despawns
# after `lifetime` seconds if it never hits anything.
#
# despawn architecture:
# uses a lifetime timer rather than VisibleOnScreenNotifier2D. the notifier
# fired screen_exited when the orb scrolled off-camera as the player moved,
# killing orbs that should have hit — timer-based despawn is independent of
# camera/screen state.
#
# collision:
# orb is on Layer 7 (enemyprojectile) and masks Layer 3 (player) so it only
# detects the player's hurtbox. enemy hurtboxes live on Layer 4 and are
# correctly ignored, so the orb can't self-destruct on its own shooter.
extends Area2D
class_name FireProjectile


# =============================================================================
# EXPORTED SETTINGS
# =============================================================================

@export var speed: float = 300.0
@export var damage: int = 12
@export var damage_type: StringName = &"fire"

# auto-despawn time in seconds — failsafe if orb flies off into empty space.
@export var lifetime: float = 10.0


# =============================================================================
# STATE
# =============================================================================

var direction: Vector2 = Vector2.ZERO


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	if has_node("animatedsprite2d"):
		$animatedsprite2d.play("projectile")

	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)

	# despawn after lifetime expires — protects against scene-tree leaks
	# when an orb flies past everything and never hits.
	get_tree().create_timer(lifetime).timeout.connect(destroy_projectile)

	# catch a player already overlapping on spawn — the engine won't emit an
	# enter signal for a pre-existing overlap, so a point-blank stationary
	# target depends entirely on this scan. it covers BOTH channels the live
	# handlers do (bodies AND areas) since the player is hit via a hurtbox.
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
	if not is_inside_tree():
		return

	# wait one physics frame so the overlap query reflects the orb's actual
	# world position and monitoring state.
	await get_tree().physics_frame

	if not is_inside_tree():
		return

	# channel 1 — direct body overlap
	for body in get_overlapping_bodies():
		if _is_player_target(body):
			_on_body_entered(body)
			return

	# channel 2 — hurtbox area overlap (player is hit via a child Area2D)
	for area in get_overlapping_areas():
		if _is_player_target(area.get_parent()):
			_on_area_entered(area)
			return


# =============================================================================
# COLLISION HANDLERS
# =============================================================================

func _on_body_entered(body: Node2D) -> void:
	_try_damage(body)
	destroy_projectile()


func _on_area_entered(area: Area2D) -> void:
	_try_damage(area.get_parent())
	destroy_projectile()


func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
	# DISABLED — despawn is handled by the lifetime timer in _ready instead.
	# kept as an empty function so existing editor signal wiring won't error.
	pass


# =============================================================================
# DAMAGE APPLICATION
# =============================================================================

func _is_player_target(target: Node) -> bool:
	# shared player check used by both the live handlers and the spawn scan,
	# so the two paths can never drift apart.
	return target != null and target.is_in_group(&"player")


func _try_damage(target: Node) -> void:
	if not _is_player_target(target):
		return
	if target.has_method(&"take_damage"):
		target.take_damage(damage, damage_type)


# =============================================================================
# CLEANUP
# =============================================================================

func destroy_projectile() -> void:
	queue_free()
