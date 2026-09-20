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
@export var damage: int = 13
# The element this projectile deals. Element.Type is an int, not the
# StringName this used to be: an enum is checked when the file is parsed,
# and &"posion" was only ever going to be found by someone wondering why a
# resistance did nothing.
#
# Overwritten at spawn for anything an enemy fires — see
# BaseEnemy.spawn_projectile_node(), which stamps the caster's element on
# it so a water slime's shot IS water without a second scene existing.
@export var element: int = Element.Type.FIRE

# auto-despawn time in seconds — failsafe if orb flies off into empty space.
@export var lifetime: float = 10.0


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
		target.take_damage(damage, element)


# =============================================================================
# CLEANUP
# =============================================================================

func destroy_projectile() -> void:
	queue_free()
