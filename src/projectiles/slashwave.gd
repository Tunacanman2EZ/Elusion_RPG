# slashwave projectile — fired by the warrior on every attack swing.
# uses 4 separate directional animations so no rotation is needed.
# the animation is played in shoot() (not _ready) because the direction
# isn't known until the warrior calls shoot(dir) AFTER add_child.
extends Area2D
class_name SlashWave

@export var speed: float = 350.0
@export var damage: int = 15
@export var damage_type: StringName = &"physical"

var direction: Vector2 = Vector2.ZERO
var direction_name: String = "down"

func _ready() -> void:
	# only connect signals here — animation play moved to shoot() because
	# direction_name isn't set until the spawner (warrior) calls shoot()
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)

func shoot(dir: String) -> void:
	direction_name = dir
	match dir:
		"left":  direction = Vector2.LEFT
		"right": direction = Vector2.RIGHT
		"up":    direction = Vector2.UP
		"down":  direction = Vector2.DOWN
	_play_directional_animation()

func shoot_vector(dir: Vector2) -> void:
	direction = dir.normalized()
	if abs(direction.x) > abs(direction.y):
		direction_name = "right" if direction.x > 0 else "left"
	else:
		direction_name = "down" if direction.y > 0 else "up"
	_play_directional_animation()

func _play_directional_animation() -> void:
	# play the slash animation matching the current direction_name.
	# called by shoot() / shoot_vector() after direction is set.
	if not has_node("animatedsprite2d"):
		return
	var sprite: AnimatedSprite2D = $animatedsprite2d
	var anim_name: String = "slash" + direction_name
	print("SLASHWAVE PLAYING: %s (direction_name=%s)" % [anim_name, direction_name])
	if sprite.sprite_frames.has_animation(anim_name):
		sprite.play(anim_name)
	elif sprite.sprite_frames.has_animation("slash"):
		sprite.play("slash")
	else:
		push_warning("SlashWave: no slash animation found for '%s'" % anim_name)

func _physics_process(delta: float) -> void:
	position += direction * speed * delta

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group(&"enemies") and body.has_method(&"take_damage"):
		body.take_damage(damage, damage_type)
		destroy_wave()
		return
	if not body.is_in_group(&"player"):
		destroy_wave()

func _on_area_entered(area: Area2D) -> void:
	var target: Node = area.get_parent()
	if target.is_in_group(&"enemies") and target.has_method(&"take_damage"):
		target.take_damage(damage, damage_type)
		destroy_wave()

func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
	destroy_wave()

func destroy_wave() -> void:
	queue_free()
