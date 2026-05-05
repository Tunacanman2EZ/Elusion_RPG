# bushsniper enemy — ranged archer that fires arrows at the player
extends BaseEnemy

# preload the arrow scene so it can be instantiated when firing
const ARROW_SCENE = preload("res://scene/arrow.tscn")

func _ready():
	# set bushsniper specific stats before calling parent ready
	max_hp = 50            # medium health — tougher than bushmage
	attack_cooldown = 2.0  # slower attack speed — takes time to aim and fire
	attack_range = 200.0   # long attack range — fires from a distance
	flee_range = 50.0      # flees if player gets too close

	# call parent _ready to finish setup (timers, healthbar, groups)
	super._ready()

func get_move_speed() -> float:
	# bushsniper moves at default speed
	return 80.0

func fire_projectile():
	# get the correct spawn marker based on attack direction
	var spawn_node = _get_spawn_node()

	# if no spawn node found stop here
	if spawn_node == null:
		return

	# create a new arrow instance from the preloaded scene
	var arrow = ARROW_SCENE.instantiate()

	# position the arrow at the spawn marker world position
	arrow.position = spawn_node.global_position

	# add the arrow to the current scene so it exists in the world
	get_tree().current_scene.add_child(arrow)

	# tell the arrow which direction to travel
	arrow.shoot(attack_direction)

func _get_spawn_node() -> Marker2D:
	# return the correct spawn marker based on which direction we are attacking
	match attack_direction:
		"left":  return $arrowspawnleft    # spawn arrow on the left side
		"right": return $arrowspawnright   # spawn arrow on the right side
		"up":    return $arrowspawntop     # spawn arrow on the top
		"down":  return $arrowspawnbottom  # spawn arrow on the bottom
	# return null if direction didn't match — prevents crash
	return null

func play_walk_animation(dir: String) -> void:
	# play walk animation in the given direction e.g. "walkright", "walkdown"
	# only plays if direction string is not empty
	if dir != "":
		$animatedsprite2d.play("walk" + dir)

func play_attack_animation(dir: String) -> void:
	# play attack animation in the given direction e.g. "attackleft", "attackup"
	$animatedsprite2d.play("attack" + dir)

func play_idle_animation(dir: String) -> void:
	# play idle animation in the given direction e.g. "idledown", "idleright"
	$animatedsprite2d.play("idle" + dir)
