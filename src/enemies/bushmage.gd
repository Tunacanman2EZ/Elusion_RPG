# bushmage enemy — melee attacker that uses directional vine attack boxes
extends BaseEnemy

# how much damage the bushmage deals per hit
var attack_power: int = 8

func _ready():
	# set bushmage specific stats before calling parent ready
	max_hp = 40           # lower hp than default — fragile melee enemy
	attack_cooldown = 1.2 # attacks every 1.2 seconds
	attack_range = 160.0  # gets fairly close before attacking
	flee_range = 5.0      # almost never flees — aggressive melee fighter

	# call parent _ready to finish setup (timers, healthbar, groups)
	super._ready()

func get_move_speed() -> float:
	# bushmage moves slightly slower than default
	return 75.0

func fire_projectile():
	# bushmage has no projectile — instead checks directional attack boxes
	# build the attack box node name based on current attack direction
	# e.g. "attackboxleft", "attackboxright", "attackboxup", "attackboxdown"
	var box_name = "attackbox" + attack_direction

	# if the attack box node doesn't exist stop here
	if not has_node(box_name):
		return

	# get all physics bodies currently overlapping the attack box
	var bodies = get_node(box_name).get_overlapping_bodies()

	# check each overlapping body
	for body in bodies:
		# only damage the player
		if body.is_in_group("player"):
			# make sure the player has a take_damage function
			if body.has_method("take_damage"):
				# deal damage to the player
				body.take_damage(attack_power)

func play_idle_animation(dir: String) -> void:
	# play idle animation in the given direction e.g. "idledown", "idleleft"
	if has_node("animatedsprite2d"):
		$animatedsprite2d.play("idle" + dir)

func play_attack_animation(dir: String) -> void:
	# play attack animation in the given direction e.g. "attackright", "attackup"
	if has_node("animatedsprite2d"):
		$animatedsprite2d.play("attack" + dir)
