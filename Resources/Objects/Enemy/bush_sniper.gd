extends CharacterBody2D
class_name Archer

@export var arrow_scene: PackedScene = preload("res://Resources/Objects/Enemy/BushSniperArrow.tscn")
@onready var arrow_spawn: Marker2D = $ArrowSpawn
@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var attack_box: Area2D = $AttackBox
@onready var attack_timer: Timer = $AttackTimer

var attack_target: Node2D = null
var is_attacking: bool = false
var attack_direction: Vector2 = Vector2.RIGHT
var facing_anim_name: String = "Right"

func _ready():
	anim_sprite.play("Idle_Right")
	attack_box.body_entered.connect(_on_attack_box_body_entered)
	attack_box.body_exited.connect(_on_attack_box_body_exited)
	attack_timer.timeout.connect(_on_attack_timer_timeout)
	anim_player.animation_finished.connect(_on_animation_player_animation_finished)

func _on_attack_box_body_entered(body):
	if body.is_in_group("player"):
		attack_target = body
		if attack_timer.is_stopped():
			attack_timer.start()
		print("Player entered archer range!")

func _on_attack_box_body_exited(body):
	if body == attack_target:
		attack_target = null
		attack_timer.stop()
		print("Player left archer range.")
		anim_sprite.play("Idle_" + facing_anim_name)

func _on_attack_timer_timeout():
	if attack_target and not is_attacking:
		var direction = (attack_target.global_position - global_position).normalized()
		attack_action(direction)

func attack_action(direction: Vector2):
	if is_attacking:
		return
	is_attacking = true
	attack_direction = direction

	var anim_name = "Attack_Right"
	facing_anim_name = "Right"
	if direction.dot(Vector2.LEFT) > 0.7:
		anim_name = "Attack_Left"
		facing_anim_name = "Left"
	elif direction.dot(Vector2.UP) > 0.7:
		anim_name = "Attack_Up"
		facing_anim_name = "Up"
	elif direction.dot(Vector2.DOWN) > 0.7:
		anim_name = "Attack_Down"
		facing_anim_name = "Down"
	anim_player.play(anim_name)

# This is called at the correct animation frame via Call Method track
func shoot_arrow():
	print(">>> shoot_arrow called!")
	var arrow = arrow_scene.instantiate()
	get_tree().current_scene.add_child(arrow)
	arrow.global_position = arrow_spawn.global_position
	arrow.shoot(attack_direction)

func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if anim_name.begins_with("Attack"):
		is_attacking = false
		# Don't call idle here—ensure idle only plays when player leaves range
