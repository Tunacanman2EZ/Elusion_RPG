extends Area2D

signal cook_requested

var player_in_range: Node = null
var is_lit: bool = true
var spawn_timer = 0.0

func _ready():
	$animatedsprite2d.play("lit")
	spawn_timer = 1.0

func _process(delta):
	if spawn_timer > 0:
		spawn_timer -= delta
		return
	if player_in_range and Input.is_action_just_pressed("interact"):
		if is_lit:
			extinguish_fire()
		else:
			light_fire()

func _on_body_entered(body):
	if body.is_in_group("player"):
		player_in_range = body

func _on_body_exited(body):
	if body == player_in_range:
		player_in_range = null

func light_fire():
	is_lit = true
	$animatedsprite2d.play("lit")

func extinguish_fire():
	is_lit = false
	$animatedsprite2d.play("unlit")

func cook(player: Node):
	if is_lit:
		emit_signal("cook_requested", player)
