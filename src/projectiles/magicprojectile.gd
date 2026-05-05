# magic projectile — fired by the electricspirit enemy
extends Area2D

# how fast the projectile travels in pixels per second — exported for easy tuning
@export var speed: float = 300.0

# how much damage the projectile deals on hit — exported for easy tuning
@export var damage: int = 10

# the damage type — used by the elemental system later
# &"magic" is a StringName literal which is faster than a regular String
@export var damage_type: StringName = &"magic"

# the direction the projectile is travelling as a Vector2
var direction: Vector2 = Vector2.ZERO

func _ready():
	# play the projectile animation if the sprite node exists
	if has_node("animatedsprite2d"):
		$animatedsprite2d.play("projectile")
		if has_node("firering"):
			$firering.play("firering")  # animation name is "firering" not "ring"
			$firering.visible = true

	# connect body entered signal — check first to avoid double connection
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

func shoot(dir: String) -> void:
	# convert the direction string into a Vector2 for movement
	match dir:
		"left":  direction = Vector2.LEFT   # move left
		"right": direction = Vector2.RIGHT  # move right
		"up":    direction = Vector2.UP     # move up
		"down":  direction = Vector2.DOWN   # move down

func _physics_process(delta: float) -> void:
	# move the projectile in its direction every frame
	# normalized() ensures consistent speed regardless of direction
	position += direction.normalized() * speed * delta

func _on_body_entered(body: Node2D) -> void:
	# check if the body that was hit is the player
	if body.is_in_group(&"player"):
		# check if the player has a take_damage function
		if body.has_method(&"take_damage"):
			# deal magic damage to the player
			body.take_damage(damage, damage_type)

		# destroy the projectile after hitting the player
		destroy_projectile()

func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
	# destroy the projectile when it leaves the visible screen area
	# prevents projectiles from travelling forever off screen
	destroy_projectile()

func destroy_projectile() -> void:
	# remove the projectile from the scene
	queue_free()
