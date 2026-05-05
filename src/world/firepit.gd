# firepit interactable — player can light or extinguish it and use it for cooking
extends Area2D

# emitted when a player tries to cook at a lit firepit
# connected to the cooking system when implemented in phase 1
signal cook_requested

# reference to the player when they are in range
var player_in_range: Node = null

# tracks whether the fire is currently lit or extinguished
var is_lit: bool = true

# prevents false interact triggers on scene load
var spawn_timer = 0.0

func _ready():
	# start with the fire lit and playing the lit animation
	$animatedsprite2d.play("lit")

	# set spawn timer to prevent instant interaction on scene load
	spawn_timer = 1.0

func _process(delta):
	# count down spawn timer before allowing interactions
	if spawn_timer > 0:
		spawn_timer -= delta
		# skip the rest of process until timer expires
		return

	# if player is nearby and presses interact toggle the fire
	if player_in_range and Input.is_action_just_pressed("interact"):
		if is_lit:
			# fire is lit — extinguish it
			extinguish_fire()
		else:
			# fire is out — light it
			light_fire()

func _on_body_entered(body):
	# when a body enters the firepit detection area
	if body.is_in_group("player"):
		# store reference to player so we know they are nearby
		player_in_range = body

func _on_body_exited(body):
	# when the player leaves the firepit detection area
	if body == player_in_range:
		# clear player reference — they are no longer nearby
		player_in_range = null

func light_fire():
	# mark fire as lit
	is_lit = true
	# play the lit flame animation
	$animatedsprite2d.play("lit")

func extinguish_fire():
	# mark fire as extinguished
	is_lit = false
	# play the unlit/smoke animation
	$animatedsprite2d.play("unlit")

func cook(player: Node):
	# only allow cooking if the fire is currently lit
	if is_lit:
		# emit signal to trigger the cooking system
		# cooking UI will be implemented in phase 1
		emit_signal("cook_requested", player)
