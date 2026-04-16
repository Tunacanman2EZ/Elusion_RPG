extends Area2D

@export var speed: float = 300.0
@export var damage: int = 10
@export var damage_type: StringName = &"magic"

var direction: Vector2 = Vector2.ZERO 

func _physics_process(delta: float) -> void:
	position += direction.normalized() * speed * delta  # Use .normalized() for safety

func _on_body_entered(body: Node2D) -> void:
	# Only process hits for objects in the 'player' group
	if body.is_in_group(&"player"):
		if body.has_method(&"take_damage"):
			body.take_damage(damage, damage_type)
		destroy_projectile()

# Destroy projectile if it leaves the screen (using a VisibleOnScreenNotifier2D node)
func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
	destroy_projectile()

func destroy_projectile() -> void:
	queue_free()
