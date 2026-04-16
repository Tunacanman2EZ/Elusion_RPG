extends Area2D

signal cook_requested    # Emitted when player tries to cook at the firepit

var player_in_range: Node = null

func _ready():
	$AnimatedSprite2D.play("burn")

func _on_body_entered(body):
	if body.is_in_group("player"):
		player_in_range = body

func _on_body_exited(body):
	if body == player_in_range:
		player_in_range = null

func _process(_delta):
	# Allow the player to interact (customize your key/method here)
	if player_in_range and Input.is_action_just_pressed("interact"):
		emit_signal("cook_requested", player_in_range)
		# Optionally call a function directly, or open a cooking panel!
