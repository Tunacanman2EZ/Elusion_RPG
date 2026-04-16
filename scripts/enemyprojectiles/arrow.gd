extends Area2D

var speed: float = 400
var velocity: Vector2 = Vector2.ZERO

func shoot(direction: Vector2) -> void:
	velocity = direction.normalized() * speed
	rotation = velocity.angle()

func _physics_process(delta: float) -> void:
	position += velocity * delta
	# Despawn arrow if it leaves the visible window
	if not get_viewport_rect().has_point(global_position):
		queue_free()
