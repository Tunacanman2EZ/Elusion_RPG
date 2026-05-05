# firesprite enemy — ranged magic caster that fires fire orbs at the player
extends BaseEnemy

# preload the fire projectile scene so it can be instantiated when firing
const FIRE_ORB_SCENE = preload("res://scene/enemy/fireprojectile.tscn")

func _ready():
	# set firesprite specific stats before calling parent ready
	max_hp = 40            # medium health — slightly tougher than electricspirit
	attack_cooldown = 2.0  # fires every 2 seconds
	attack_range = 240.0   # long range — keeps distance from player
	flee_range = 50.0      # flees if player gets very close

	# call parent _ready to finish setup (timers, healthbar, groups)
	super._ready()

	# start with idle animation facing down
	if has_node("animatedsprite2d"):
		$animatedsprite2d.play("idledown")

func get_move_speed() -> float:
	# firesprite moves slightly faster than electricspirit
	return 85.0

func fire_projectile():
	# get the correct spawn marker based on attack direction
	var spawn_node = _get_spawn_node()

	# if no spawn node found stop here
	if spawn_node == null:
		return

	# create a new fire orb instance from the preloaded scene
	var orb = FIRE_ORB_SCENE.instantiate()

	# position the orb at the spawn marker world position
	orb.global_position = spawn_node.global_position

	# add the orb to the current scene so it exists in the world
	get_tree().current_scene.add_child(orb)

	# tell the orb which direction to travel
	orb.shoot(attack_direction)

func _get_spawn_node() -> Marker2D:
	# return the correct spawn marker based on which direction we are attacking
	match attack_direction:
		"left":  return $orbspawnleft   # spawn orb on the left side
		"right": return $orbspawnright  # spawn orb on the right side
		"up":    return $orbspawntop    # spawn orb on the top
		"down":  return $orbspawnbottom # spawn orb on the bottom

	# return null if direction didn't match — prevents crash
	return null

func play_walk_animation(dir: String) -> void:
	# play walk animation in the given direction e.g. "walkright", "walkdown"
	# only plays if direction is valid and sprite node exists
	if dir != "" and has_node("animatedsprite2d"):
		$animatedsprite2d.play("walk" + dir)

func play_attack_animation(dir: String) -> void:
	if has_node("animatedsprite2d"):
		# build the attack animation name e.g. "attackleft", "attackup"
		var anim = "attack" + dir

		# check if this directional animation exists in the sprite frames
		if $animatedsprite2d.sprite_frames.has_animation(anim):
			# play the correct directional attack animation
			$animatedsprite2d.play(anim)
		else:
			# fallback to attackup if the directional animation doesn't exist
			$animatedsprite2d.play("attackup")

func play_idle_animation(dir: String) -> void:
	# play idle animation in the given direction e.g. "idledown", "idleright"
	if has_node("animatedsprite2d"):
		$animatedsprite2d.play("idle" + dir)
