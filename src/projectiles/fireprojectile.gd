# fire projectile — fired by the firesprite enemy
# travels in any direction (cardinal or arbitrary angle), damages player on hit
extends Area2D
class_name FireProjectile

@export var speed: float = 300.0
@export var damage: int = 12
# the damage type — used by the elemental system later
# &"fire" is a StringName literal which is faster than a regular String
@export var damage_type: StringName = &"fire"

# the direction the projectile is travelling, normalized
var direction: Vector2 = Vector2.ZERO

func _ready() -> void:
	# play the projectile animation if the sprite node exists
	if has_node("animatedsprite2d"):
		$animatedsprite2d.play("projectile")

	# connect collision signals — guard against double connection
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)

# called for cardinal direction shots — kept for compatibility
func shoot(dir: String) -> void:
	match dir:
		"left":  shoot_vector(Vector2.LEFT)
		"right": shoot_vector(Vector2.RIGHT)
		"up":    shoot_vector(Vector2.UP)
		"down":  shoot_vector(Vector2.DOWN)

# called for arbitrary-angle shots — used for player-tracking projectiles
func shoot_vector(dir: Vector2) -> void:
	direction = dir.normalized()
	rotation = direction.angle()  # rotate sprite to match travel direction

func _physics_process(delta: float) -> void:
	# direction is pre-normalized in shoot_vector, so no renormalize needed
	position += direction * speed * delta

func _on_body_entered(body: Node2D) -> void:
	# damage player if hit, destroy on any body (player, walls, anything solid)
	if body.is_in_group(&"player") and body.has_method(&"take_damage"):
		body.take_damage(damage, damage_type)
	destroy_projectile()

func _on_area_entered(area: Area2D) -> void:
	# in case the player uses an Area2D hurtbox child, check the parent
	var target: Node = area.get_parent()
	if target.is_in_group(&"player") and target.has_method(&"take_damage"):
		target.take_damage(damage, damage_type)
	destroy_projectile()

func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
	# despawn when leaving visible screen — saves processing
	destroy_projectile()

func destroy_projectile() -> void:
	# single cleanup point — add particles, sound, etc. here later
	queue_free()
