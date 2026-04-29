extends Area2D

@onready var anim: AnimatedSprite2D = $animatedsprite2d
var is_open = false
var player_nearby: Node = null
var spawn_timer = 0.0

func _ready():
	anim.play("idle")
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
	if body == player_nearby:
		player_nearby = null
		if is_open:
			is_open = false
			anim.play_backwards("open")

func _on_animatedsprite2d_animation_finished():
	if anim.animation == "open":
		var frame_count = anim.sprite_frames.get_frame_count("open")
		anim.frame = frame_count - 1
