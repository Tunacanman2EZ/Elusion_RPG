# bank chest interactable — player presses interact to open it
extends Area2D

# reference to the animated sprite for playing open/close animations
@onready var anim: AnimatedSprite2D = $animatedsprite2d

# tracks whether the chest is currently open
var is_open = false

# reference to the player node when they are nearby
var player_nearby: Node = null

# prevents false interact triggers on scene load
var spawn_timer = 0.0

func _ready():
	# play idle animation on start — single frame closed state
	anim.play("idle")
	# set spawn timer to 1 second to prevent instant interaction on load
	spawn_timer = 1.0

func _process(delta):
	# count down spawn timer before allowing interactions
	if spawn_timer > 0:
		spawn_timer -= delta
		# skip rest of process until timer expires
		return
	# if player is nearby, chest is closed, and player presses interact
	if player_nearby and not is_open and Input.is_action_just_pressed("interact"):
		# play the open animation
		anim.play("open")
		# mark chest as open
		is_open = true

func _on_body_entered(body):
	# when a body enters the chest detection area
	if body.is_in_group("player"):
		# store reference to player so we know they are nearby
		player_nearby = body

func _on_body_exited(body):
	# when a body leaves the chest detection area
	if body == player_nearby:
		# clear the player reference
		player_nearby = null
		# if chest was open close it immediately
		if is_open:
			is_open = false
			# play open animation backwards to close the chest
			anim.play_backwards("open")

func _on_animatedsprite2d_animation_finished():
	# called when any animation finishes playing
	if anim.animation == "open":
		# hold on last frame so chest stays visually fully open
		var frame_count = anim.sprite_frames.get_frame_count("open")
		anim.frame = frame_count - 1
