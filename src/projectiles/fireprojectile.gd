extends Area2D

@export var speed: float = 300.0
@export var damage: int = 12
@export var damage_type: StringName = &"fire"

var direction: Vector2 = Vector2.ZERO

func _ready():
	if has_node("animatedsprite2d"):
		$animatedsprite2d.play("projectile")
	body_entered.connect(_on_body_entered)

func shoot(dir: String) -> void:
	match dir:
		"left":  direction = Vector2.LEFT
		"right": direction = Vector2.RIGHT
		"up":    direction = Vector2.UP
		"down":  direction = Vector2.DOWN

func _physics_process(delta: float) -> void:
	position += direction.normalized() * speed * delta

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group(&"player"):
		if body.has_method(&"take_damage"):
			body.take_damage(damage, damage_type)
		destroy_projectile()

func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
	destroy_projectile()

func destroy_projectile() -> void:
	queue_free()
