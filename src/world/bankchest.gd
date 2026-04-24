extends Area2D

@onready var anim: AnimatedSprite2D = $animatedsprite2d
var is_open = false
var player_nearby: Node = null
var spawn_timer = 0.0

func _ready():
	anim.play("closed")
	spawn_timer = 1.0

func _process(delta):
	if spawn_timer > 0:
		spawn_timer -= delta
		return
	if player_nearby and not is_open and Input.is_action_just_pressed("interact"):
		anim.play("open")
		is_open = true

func _on_body_entered(body):
	if body.is_in_group("player"):
		player_nearby = body

func _on_body_exited(body):
	if spawn_timer > 0:
		return
	if body == player_nearby:
		player_nearby = null
		if is_open:
			await get_tree().create_timer(0.1).timeout
			is_open = false
			anim.play("closed")
