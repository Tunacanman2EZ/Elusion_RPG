# base class for all enemies — inherited by bushmage, bushsniper, electricsprite, firesprite
extends CharacterBody2D

# gives this script a global class name so other scripts can reference it
class_name BaseEnemy

# exported vars show in the Godot Inspector and can be tweaked per enemy scene
@export var max_hp: int = 50              # maximum health points
@export var attack_cooldown: float = 2.0  # seconds between attacks
@export var attack_range: float = 200.0   # distance at which enemy starts attacking
@export var flee_range: float = 10.0      # distance at which enemy flees from player

# current health — set to max_hp on ready
var hp: int

# current AI state — idle, run, or attack
var state: String = "idle"

# reference to the player node — found at runtime
var player: CharacterBody2D = null

# which direction the enemy is facing toward the player
var attack_direction: String = "left"

# whether the enemy can attack right now — false during cooldown
var attack_ready: bool = true

# signal emitted when enemy takes damage — passes the amount
signal damaged(amount)

# signal emitted when enemy dies
signal died

func _ready():
	# set current hp to max hp at start
	hp = max_hp

	# add to enemies group so player and other systems can find this enemy
	add_to_group("enemies")

	# find the player node in the scene
	var players = get_tree().get_nodes_in_group("player")

	# if a player exists assign the first one as our target
	if players.size() > 0:
		player = players[0]

	# if this enemy has an attack timer node set it up
	if has_node("attacktimer"):
		# set how long the cooldown lasts
		$attacktimer.wait_time = attack_cooldown
		# one_shot means timer fires once then stops — not looping
		$attacktimer.one_shot = true
		# connect timer timeout to our handler function
		$attacktimer.timeout.connect(_on_attack_timer_timeout)

	# if this enemy has a health bar set its starting values
	if has_node("healthbar"):
		$healthbar.max_value = max_hp  # set the bar maximum
		$healthbar.value = hp          # set the bar current value

	# start with idle animation facing down
	play_idle_animation("down")

func _physics_process(_delta):
	# if we lost the player reference try to find them again
	if player == null:
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			player = players[0]
		# stop processing this frame if still no player found
		return

	# calculate distance between this enemy and the player
	var dist = position.distance_to(player.position)

	# update which direction we are facing toward the player
	attack_direction = _get_direction_to_player()

	if dist < flee_range:
		# player is too close — flee away in a straight 4-directional line
		state = "run"

		# get the flee direction as a string based on which axis is dominant
		var flee_dir = _get_direction_from_vec(position - player.position)

		# convert flee direction string back to a clean Vector2
		# this ensures movement is strictly 4-directional — no diagonals
		var move_vec = Vector2.ZERO
		match flee_dir:
			"left":  move_vec = Vector2.LEFT
			"right": move_vec = Vector2.RIGHT
			"up":    move_vec = Vector2.UP
			"down":  move_vec = Vector2.DOWN

		# set velocity in the flee direction at move speed
		velocity = move_vec * get_move_speed()

		# actually move the character
		move_and_slide()

		# play walk animation in the flee direction
		play_walk_animation(flee_dir)

		# still attack while fleeing if cooldown is ready
		if attack_ready:
			_trigger_attack()

	elif dist < attack_range:
		# player is in attack range — stop and attack
		state = "attack"

		# stop moving while attacking
		velocity = Vector2.ZERO

		# play attack animation facing player
		play_attack_animation(attack_direction)

		# trigger attack if cooldown is ready
		if attack_ready:
			_trigger_attack()

	else:
		# player is out of range — idle
		state = "idle"

		# play idle animation facing player direction
		play_idle_animation(attack_direction)

		# stop moving
		velocity = Vector2.ZERO

	# update health bar every frame if it exists
	if has_node("healthbar"):
		$healthbar.value = hp

	# every 3 physics frames check for enemy stacking
	# modulo 3 reduces how often this runs to save performance
	if Engine.get_physics_frames() % 3 == 0:
		_avoid_stacking_with_others()

# --- override these in subclasses ---

# returns move speed — subclasses override this for different speeds
func get_move_speed() -> float:
	return 80.0

# fires a projectile or deals melee damage — overridden in each enemy
func fire_projectile():
	pass

# plays the walk animation in the given direction
func play_walk_animation(dir: String) -> void:
	# only play if direction is valid and sprite node exists
	if dir != "" and has_node("animatedsprite2d"):
		$animatedsprite2d.play("walk" + dir)  # e.g. "walkright", "walkdown"

# plays the attack animation in the given direction
func play_attack_animation(dir: String) -> void:
	if has_node("animatedsprite2d"):
		$animatedsprite2d.play("attack" + dir)  # e.g. "attackleft", "attackup"

# plays the idle animation in the given direction
func play_idle_animation(dir: String) -> void:
	if has_node("animatedsprite2d"):
		$animatedsprite2d.play("idle" + dir)  # e.g. "idledown", "idleright"

# --- shared logic ---

func _trigger_attack():
	# mark attack as not ready — starts cooldown
	attack_ready = false

	# start the attack cooldown timer if it exists
	if has_node("attacktimer"):
		$attacktimer.start()

	# call fire_projectile — overridden in each enemy subclass
	fire_projectile()

func _on_attack_timer_timeout():
	# cooldown finished — enemy can attack again
	attack_ready = true

func _get_direction_to_player() -> String:
	# get the vector from this enemy to the player
	var diff = player.position - position

	# return the dominant axis direction as a string
	# this ensures facing direction is always one of 4 directions
	if abs(diff.x) > abs(diff.y):
		# horizontal movement is dominant
		return "right" if diff.x > 0 else "left"
	else:
		# vertical movement is dominant
		return "down" if diff.y > 0 else "up"

func _get_direction_from_vec(vec: Vector2) -> String:
	# convert a Vector2 into a 4-directional string
	if abs(vec.x) > abs(vec.y):
		# horizontal is dominant
		return "right" if vec.x > 0 else "left"
	elif abs(vec.y) > 0:
		# vertical is dominant
		return "down" if vec.y > 0 else "up"
	# no movement — return empty string
	return ""

func _avoid_stacking_with_others():
	# get all enemies in the scene
	var others = get_tree().get_nodes_in_group("enemies")
	for other in others:
		# skip self — only check other enemies
		if other != self and position.distance_to(other.position) < 24:
			# push this enemy slightly away from the overlapping enemy
			position += (position - other.position).normalized() * 1

func take_damage(amount: int):
	# reduce hp by damage amount — clamp between 0 and max_hp
	hp = clamp(hp - amount, 0, max_hp)

	# emit damaged signal so other systems can react
	emit_signal("damaged", amount)

	# check if enemy has died
	if hp <= 0:
		# award xp to player if player exists and has the method
		if player and player.has_method("gain_xp"):
			player.gain_xp(20)        # award general xp
			player.gain_attack_xp(5) # award attack skill xp

		# emit died signal so other systems can react
		emit_signal("died")

		# remove this enemy from the scene
		queue_free()
