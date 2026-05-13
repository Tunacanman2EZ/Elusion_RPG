# arrow projectile fired by the bushsniper enemy
extends Area2D

@export var speed: float = 400.0
@export var damage: int = 10
@export var lifetime: float = 10.0

var velocity: Vector2 = Vector2.ZERO

# aim arrow at any angle — used for player-tracking shots
func shoot_vector(direction: Vector2) -> void:
	velocity = direction.normalized() * speed
	rotation = velocity.angle()

# kept for compatibility with any enemy still using cardinal directions
func shoot(direction: String) -> void:
	match direction:
		"left":  shoot_vector(Vector2.LEFT)
		"right": shoot_vector(Vector2.RIGHT)
		"up":    shoot_vector(Vector2.UP)
		"down":  shoot_vector(Vector2.DOWN)

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	get_tree().create_timer(lifetime).timeout.connect(queue_free)

func _physics_process(delta: float) -> void:
	position += velocity * delta

func _on_body_entered(body: Node) -> void:
	_try_damage(body)
	queue_free()

func _on_area_entered(area: Area2D) -> void:
	_try_damage(area.get_parent())
	queue_free()

func _try_damage(target: Node) -> void:
	if target.is_in_group("player") and target.has_method("take_damage"):
		target.take_damage(damage)
