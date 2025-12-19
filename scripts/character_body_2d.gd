extends CharacterBody2D

var speed = 100
var threshold = 0.1  # smaller so diagonals register better
var last_direction = "down"

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

func _physics_process(_delta):
	var input_vector = Vector2.ZERO
	input_vector.x = Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left")
	input_vector.y = Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up")

	if input_vector != Vector2.ZERO:
		input_vector = input_vector.normalized()

	velocity = input_vector * speed
	move_and_slide()

	if input_vector != Vector2.ZERO:
		# diagonals if both inputs are active
		if input_vector.x < -threshold and input_vector.y > threshold:
			last_direction = "bottom_left"
		elif input_vector.x > threshold and input_vector.y > threshold:
			last_direction = "bottom_right"
		elif input_vector.x < -threshold and input_vector.y < -threshold:
			last_direction = "top_left"
		elif input_vector.x > threshold and input_vector.y < -threshold:
			last_direction = "top_right"
		elif input_vector.x < -threshold:
			last_direction = "left"
		elif input_vector.x > threshold:
			last_direction = "right"
		elif input_vector.y > threshold:
			last_direction = "down"
		elif input_vector.y < -threshold:
			last_direction = "up"

		sprite.play(last_direction)
	else:
		sprite.stop()
