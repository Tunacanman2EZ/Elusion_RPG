# arrow projectile fired by the bushsniper enemy
extends Area2D

# how fast the arrow travels in pixels per second
var speed: float = 400.0

# current movement vector — starts at zero until shoot() is called
var velocity: Vector2 = Vector2.ZERO

# how many seconds before the arrow despawns automatically
var lifetime: float = 10.0

# grace period before despawn check activates — prevents instant despawn on spawn
var grace_time: float = 0.2

# called by bushsniper to set the arrow's direction and rotation
func shoot(direction: String) -> void:
	match direction:
		"left":
			# move left and rotate to face left
			velocity = Vector2.LEFT * speed
			rotation = PI  # 180 degrees

		"right":
			# move right and rotate to face right
			velocity = Vector2.RIGHT * speed
			rotation = 0  # 0 degrees

		"up":
			# move up and rotate to face up
			velocity = Vector2.UP * speed
			rotation = -PI / 2  # -90 degrees

		"down":
			# move down and rotate to face down
			velocity = Vector2.DOWN * speed
			rotation = PI / 2  # 90 degrees

func _ready():
	# wait one frame before connecting body_entered
	# prevents the arrow from immediately detecting the enemy that fired it
	await get_tree().process_frame

	# connect the body_entered signal to our damage handler
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	# move the arrow in its direction every frame
	position += velocity * delta

	# count down the lifetime timer
	lifetime -= delta

	# despawn the arrow when its lifetime runs out
	if lifetime <= 0:
		queue_free()

func _on_body_entered(body: Node) -> void:
	# check if the body that was hit is the player
	if body.is_in_group("player"):

		# check if the player has a take_damage function
		if body.has_method("take_damage"):

			# deal 10 damage to the player
			body.take_damage(10)

		# remove the arrow from the scene after hitting the player
		queue_free()
