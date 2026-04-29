extends Area2D

var speed: float = 400.0
var velocity: Vector2 = Vector2.ZERO
var lifetime: float = 10.0
var grace_time: float = 0.2

func shoot(direction: String) -> void:
	match direction:
		"left":
			velocity = Vector2.LEFT * speed
			rotation = PI
		"right":
			velocity = Vector2.RIGHT * speed
			rotation = 0
		"up":
			velocity = Vector2.UP * speed
			rotation = -PI / 2
		"down":
			velocity = Vector2.DOWN * speed
			rotation = PI / 2

func _ready():
	await get_tree().process_frame
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	position += velocity * delta
	lifetime -= delta
	if lifetime <= 0:
		queue_free()

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		if body.has_method("take_damage"):
			body.take_damage(10)
		queue_free()
