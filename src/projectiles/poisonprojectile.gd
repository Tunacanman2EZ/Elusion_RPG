# poisonball.gd — acid ball spat by the large poison slime.
# structural twin of magicprojectile.gd / fireprojectile.gd / arrow.gd.
# the rapid-fire cadence lives in poisonslime.gd, not here — this just travels.
extends Area2D


# =============================================================================
# EXPORTED SETTINGS
# =============================================================================

# NEW: the ground hazard this ball leaves where it lands.
const PUDDLE_SCENE := preload("res://scene/projectiles/acidpuddle.tscn")

@export var speed: float = 260.0
@export var damage: int = 8
@export var damage_type: StringName = &"poison"

# NEW: whether a hit leaves an acid puddle behind. Exported so a variant
# ball (a weaker slime, a different enemy reusing this projectile) can fire
# clean shots without needing its own script.
@export var leaves_puddle: bool = true

# auto-despawn failsafe if the ball flies off into empty space.
@export var lifetime: float = 3.0


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

	get_tree().create_timer(lifetime).timeout.connect(destroy_projectile)

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

	await get_tree().physics_frame

	if not is_inside_tree():
		return

	for body in get_overlapping_bodies():
		if _is_player_target(body):
			_on_body_entered(body)
			return

	for area in get_overlapping_areas():
		if _is_player_target(area.get_parent()):
			_on_area_entered(area)
			return


# =============================================================================
# COLLISION HANDLERS
# =============================================================================

func _on_body_entered(body: Node2D) -> void:
	_try_damage(body)
	_leave_puddle()
	destroy_projectile()


func _on_area_entered(area: Area2D) -> void:
	_try_damage(area.get_parent())
	_leave_puddle()
	destroy_projectile()


# =============================================================================
# GROUND EFFECT
# =============================================================================

func _leave_puddle() -> void:
	# NEW: the ball leaves acid where it lands. See acidpuddle.gd for what
	# that's for — briefly, it turns a dodgeable hit into a positioning
	# problem, and overlapping puddles stack.
	#
	# Spawned on CONTACT only, not when the lifetime failsafe fires: a ball
	# that flew off into empty space and timed out should not be quietly
	# poisoning ground nobody is near.
	if not leaves_puddle or PUDDLE_SCENE == null:
		return

	var puddle: Node2D = PUDDLE_SCENE.instantiate()

	# capture the position NOW — this node is about to be freed, so reading
	# global_position from inside the deferred call below would be too late.
	var landing: Vector2 = global_position

	# parented into the Y-sorted "groundeffects" container so it draws under
	# characters, exactly like bushmage's vine. Falling back to the current
	# scene keeps it working (just sorted wrong) if that container is
	# missing from a level.
	var container: Node = get_tree().get_first_node_in_group("groundeffects")
	if container == null:
		container = get_tree().current_scene
	if container == null:
		return

	# deferred: this runs inside a collision callback, and adding a node to
	# the tree mid-physics throws "Can't change this state while flushing
	# queries".
	container.call_deferred("add_child", puddle)
	puddle.call_deferred("set", "global_position", landing)
	puddle.call_deferred("reset_physics_interpolation")


# =============================================================================
# DAMAGE APPLICATION
# =============================================================================

func _is_player_target(target: Node) -> bool:
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
