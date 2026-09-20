# poisonball.gd — acid ball spat by the large poison slime.
# structural twin of magicprojectile.gd / fireprojectile.gd / arrow.gd.
# the rapid-fire cadence lives in poisonslime.gd, not here — this just travels.
extends Area2D


# =============================================================================
# EXPORTED SETTINGS
# =============================================================================

# The ground hazard this ball leaves where it lands is chosen by element —
# Puddles.scene_for(). There are nine of them, so there is no one scene to
# preload here; an ice slime's ball leaves ice, not green acid with the hue
# turned at runtime.
@export var speed: float = 260.0
@export var damage: int = 7
# The element this projectile deals. Element.Type is an int, not the
# StringName this used to be: an enum is checked when the file is parsed,
# and &"posion" was only ever going to be found by someone wondering why a
# resistance did nothing.
#
# Overwritten at spawn for anything an enemy fires — see
# BaseEnemy.spawn_projectile_node(), which stamps the caster's element on
# it so a water slime's shot IS water without a second scene existing.
# POISON, NOT EARTH — the same correction acidpuddle.gd needed, and this is
# where the brown puddles were coming from.
#
# slime.png's ball is green. EARTH is ochre. They disagreed harmlessly for as
# long as nothing read the element for colour, and then stopped being harmless
# the moment this started passing it to the puddle it drops: every pool a slime
# left was being hue-rotated to 0.0985, which is brown, on top of art that is
# green. POISON is 0.3122 against the art's own 0.311, so the rotation is a
# no-op and the acid comes out as drawn.
@export var element: int = Element.Type.POISON

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
	if _spent:
		return
	_spent = true
	_try_damage(body)
	_leave_puddle()
	destroy_projectile()


func _on_area_entered(area: Area2D) -> void:
	if _spent:
		return
	_spent = true
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
	if not leaves_puddle:
		return

	# THE BALL'S ELEMENT PICKS THE SCENE, which for the poison slime that owns
	# this projectile is poison and looks like nothing changed. It matters for
	# every other slime: BaseEnemy.spawn_projectile_node() stamps the caster's
	# element on the way out, so an ice slime's ball arrives here carrying ICE
	# and leaves an ice pool with ice's own lifetime and tick.
	var puddle: Node2D = Puddles.scene_for(element).instantiate()

	# Carried through for the fallback case — see the same line in
	# bossprojectile.gd. The scene already agrees for every element that has one.
	puddle.element = element

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
	# One deferred call: the pool places itself from spawn_at in _ready().
	puddle.spawn_at = landing
	container.call_deferred("add_child", puddle)


# =============================================================================
# DAMAGE APPLICATION
# =============================================================================

func _is_player_target(target: Node) -> bool:
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
