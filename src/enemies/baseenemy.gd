# base class for all enemies — inherited by bushmage, bushsniper, electricspirit, firesprite
extends CharacterBody2D
class_name BaseEnemy

@export var max_hp: int = 50
@export var attack_cooldown: float = 2.0
@export var attack_range: float = 200.0
@export var flee_range: float = 40.0
@export var xp_reward: int = 20
@export var attack_xp_reward: int = 5

# how far an enemy will chase from its spawn point before returning home.
# prevents enemies migrating across the map toward distant players.
# tune higher for boss-arena enemies, lower for static patrol mobs.
@export var leash_range: float = 400.0

var hp: int
var player: CharacterBody2D = null
var attack_direction: String = "down"
var attack_ready: bool = true

# true while the attack animation is playing — enemy can't move or attack again
var is_attacking: bool = false

# tracks which animation is currently playing — prevents restart spam
var current_anim: String = ""

# remembered spawn position — enemy returns here if leashed
var spawn_position: Vector2 = Vector2.ZERO

# true while the enemy is heading back to its spawn after disengaging
var is_returning_home: bool = false

signal damaged(amount: int)
signal died

func _ready() -> void:
	hp = max_hp
	add_to_group("enemies")

	# remember where this enemy was placed — used as the leash anchor
	spawn_position = global_position

	# find the player via group lookup
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]

	# attack cooldown timer — guard against double connection in case
	# the timeout signal is also wired through the editor
	if has_node("attacktimer"):
		$attacktimer.wait_time = attack_cooldown
		$attacktimer.one_shot = true
		if not $attacktimer.timeout.is_connected(_on_attack_timer_timeout):
			$attacktimer.timeout.connect(_on_attack_timer_timeout)

	# healthbar setup — explicitly force ALL range properties so scene defaults
	# can't leak through. without min_value=0 and step=1, scene-set values can
	# cause the bar to show 0% even though hp is positive.
	if has_node("healthbar"):
		var bar = $healthbar
		bar.min_value = 0
		bar.max_value = max_hp
		bar.step = 1
		bar.value = hp

	# connect animation_finished so we can transition out of attack animations
	if has_node("animatedsprite2d"):
		var sprite: AnimatedSprite2D = $animatedsprite2d
		if not sprite.animation_finished.is_connected(_on_animation_finished):
			sprite.animation_finished.connect(_on_animation_finished)

	play_idle_animation("down")

func _physics_process(_delta: float) -> void:
	# look up player if we don't have one yet
	if player == null:
		var players := get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			player = players[0]
		return

	# always update the cached facing toward the player, even while attacking.
	# this prevents the "frozen direction" bug when the player circles during
	# a long attack animation. animation isn't switched here during attack —
	# we only refresh the direction value so the post-attack idle plays correctly.
	if not is_returning_home:
		attack_direction = _get_direction_to_player()

	# while attacking, freeze in place — projectile fires on a frame_changed
	# signal in subclasses; movement and new attacks resume on animation_finished
	if is_attacking:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var dist_to_player := global_position.distance_to(player.global_position)

	# if the player is beyond the leash range from spawn, return home.
	# this prevents enemies migrating across the entire map.
	if dist_to_player > leash_range:
		var dist_from_spawn := global_position.distance_to(spawn_position)
		if dist_from_spawn > 4.0:
			# walk back to spawn
			is_returning_home = true
			var return_dir := _get_direction_from_vec(spawn_position - global_position)
			velocity = _vec_from_dir(return_dir) * get_move_speed()
			move_and_slide()
			play_walk_animation(return_dir)
		else:
			# arrived home — idle in place
			is_returning_home = false
			velocity = Vector2.ZERO
			play_idle_animation("down")
		return

	# player is within leash range — normal aggro behavior
	is_returning_home = false

	if dist_to_player < flee_range:
		# player too close — flee in 4-directional line
		var flee_dir := _get_direction_from_vec(global_position - player.global_position)
		velocity = _vec_from_dir(flee_dir) * get_move_speed()
		move_and_slide()
		play_walk_animation(flee_dir)

	elif dist_to_player < attack_range:
		# in attack range — stop and attack when ready, otherwise idle
		velocity = Vector2.ZERO
		if attack_ready:
			_trigger_attack()
		else:
			# waiting for cooldown — idle facing the player
			play_idle_animation(attack_direction)

	else:
		# in leash range but out of attack range — chase the player
		var to_player := _get_direction_from_vec(player.global_position - global_position)
		velocity = _vec_from_dir(to_player) * get_move_speed()
		move_and_slide()
		play_walk_animation(to_player)

	# stagger the stacking check by instance id so enemies don't all spike on the same frame
	if (Engine.get_physics_frames() + get_instance_id()) % 3 == 0:
		_avoid_stacking_with_others()

# --- override these in subclasses ---

func get_move_speed() -> float:
	return 80.0

func fire_projectile() -> void:
	# subclasses override this — called via frame_changed signal at the right
	# animation frame, NOT directly from _trigger_attack.
	pass

# --- animation helpers ---
# _set_animation only calls play() when the animation actually changes.
# without this guard, play() runs every physics frame and the animation
# restarts from frame 0, so frame_changed signals never reach later frames.
# also defensively checks if the animation exists before playing — missing
# animations cause silent failure that can lock state machines.

func _set_animation(new_anim: String) -> void:
	if new_anim == "" or not has_node("animatedsprite2d"):
		return
	if new_anim == current_anim:
		return  # already playing this — don't restart

	var sprite: AnimatedSprite2D = $animatedsprite2d
	if not sprite.sprite_frames.has_animation(new_anim):
		push_warning("%s: missing animation '%s'" % [name, new_anim])
		return

	current_anim = new_anim
	sprite.play(new_anim)

func play_walk_animation(dir: String) -> void:
	if dir != "":
		_set_animation("walk" + dir)

func play_attack_animation(dir: String) -> void:
	if dir != "":
		_set_animation("attack" + dir)

func play_idle_animation(dir: String) -> void:
	if dir != "":
		_set_animation("idle" + dir)

# --- shared logic ---

func _trigger_attack() -> void:
	attack_ready = false
	is_attacking = true
	if has_node("attacktimer"):
		$attacktimer.start()
	play_attack_animation(attack_direction)
	# fire_projectile() NOT called here — subclasses fire on the correct
	# animation frame via AnimatedSprite2D.frame_changed.

func _on_attack_timer_timeout() -> void:
	attack_ready = true

func _on_animation_finished() -> void:
	# called when any animation finishes playing.
	# transitions out of attack animations so the enemy doesn't get stuck.
	if not has_node("animatedsprite2d"):
		return

	var sprite: AnimatedSprite2D = $animatedsprite2d
	if sprite.animation.begins_with("attack"):
		is_attacking = false
		play_idle_animation(attack_direction)

func _get_direction_to_player() -> String:
	if player == null:
		return attack_direction  # fall back to last known
	return _get_direction_from_vec(player.global_position - global_position)

func _get_direction_from_vec(vec: Vector2) -> String:
	# always returns one of the 4 cardinals (or "" for zero vector).
	# matches the player's animation set — no diagonals.
	if abs(vec.x) > abs(vec.y):
		return "right" if vec.x > 0 else "left"
	elif abs(vec.y) > 0:
		return "down" if vec.y > 0 else "up"
	return ""

func _vec_from_dir(dir: String) -> Vector2:
	match dir:
		"left":  return Vector2.LEFT
		"right": return Vector2.RIGHT
		"up":    return Vector2.UP
		"down":  return Vector2.DOWN
	return Vector2.ZERO

func _avoid_stacking_with_others() -> void:
	# nudge enemies apart slightly when they overlap.
	# uses velocity so move_and_slide handles wall collision properly,
	# preventing the "phase through wall" bug from direct global_position writes.
	var others := get_tree().get_nodes_in_group("enemies")
	for other in others:
		if other == self:
			continue
		var d := global_position.distance_to(other.global_position)
		if d < 24 and d > 0:
			velocity += (global_position - other.global_position).normalized() * 20

# --- damage ---

func take_damage(amount: int, _type: StringName = &"physical") -> void:
	hp = max(hp - amount, 0)
	damaged.emit(amount)

	if has_node("healthbar"):
		var bar = $healthbar
		if bar.max_value != max_hp:
			bar.max_value = max_hp
		bar.value = hp

	if hp <= 0:
		_die()

func _die() -> void:
	# award xp to the player who killed this enemy
	if player and player.has_method("gain_xp"):
		player.gain_xp(xp_reward)
		if player.has_method("gain_attack_xp"):
			player.gain_attack_xp(attack_xp_reward)
	died.emit()
	queue_free()
