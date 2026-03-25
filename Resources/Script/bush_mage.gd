extends CharacterBody2D

"""
BushMage Enemy (final, pushable by player, RPG logic)
"""

var max_hp := 40
var hp := 40
var xp_reward := 30
var attack_damage := 10
var attack_cooldown := 1.2
var speed := 80
var patrol_size := 288
var chase_distance := 160
var attack_range := 160
var standoff_range := 96
var respawn_delay := 5.0
var player = null
var rng := RandomNumberGenerator.new()
var can_attack := true

var patrol_center := Vector2.ZERO
var patrol_area := Rect2()
var patrol_target := Vector2.ZERO
var chasing := false
var last_attack_time := -999.0
var facing_direction := "Down"  # Up, Down, Left, Right
var current_animation := ""
var is_attacking := false

func _ready():
	patrol_center = position
	patrol_area = Rect2(patrol_center - Vector2(patrol_size / 2.0, patrol_size / 2.0), Vector2(patrol_size, patrol_size))
	hp = max_hp
	_choose_new_patrol_target()
	$HurtBox.area_entered.connect(_on_HurtBox_area_entered)
	$AttackBox.area_entered.connect(_on_AttackBox_area_entered)
	$AttackBox.monitoring = false

func _physics_process(_delta):
	# Remove forced velocity = Vector2.ZERO. Let physics push enemy unless AI wants to move.
	if not player or not player.is_inside_tree():
		player = get_tree().get_first_node_in_group("player")

	if is_attacking:
		# Don't forcibly zero; let engine allow pushes during attack freeze
		move_and_slide()
		return

	if player and position.distance_to(player.position) < chase_distance:
		chasing = true
	else:
		chasing = false

	var to_player = Vector2.ZERO
	var dist = 99999.0

	if chasing and player:
		to_player = (player.position - position)
		dist = to_player.length()
		var dir_name = _get_direction_name(to_player)
		if dist > standoff_range:
			velocity = to_player.normalized() * speed
			if velocity.length() > 0.1:
				facing_direction = dir_name
			_play_animation(get_walk_animation(facing_direction))
		else:
			# Don't move by AI, but allow sliding if pushed by player.
			velocity = Vector2.ZERO
			_play_animation(get_idle_animation())
			if dist <= attack_range and can_attack:
				_perform_spellcast()
	else:
		var to_target = patrol_target - position
		var dir_name = _get_direction_name(to_target)
		if to_target.length() > 8:
			velocity = to_target.normalized() * speed
			if velocity.length() > 0.1:
				facing_direction = dir_name
			_play_animation(get_walk_animation(facing_direction))
		else:
			velocity = Vector2.ZERO
			_play_animation(get_idle_animation())
			_choose_new_patrol_target()

	move_and_slide() # Always allow physical collision response

func get_walk_animation(dir: String) -> String:
	return "Walk_" + dir

func get_idle_animation() -> String:
	return "Idle_" + facing_direction

func get_attack_animation(dir: String) -> String:
	return "Attack_" + dir

func _play_animation(anim_name: String):
	if current_animation != anim_name:
		$AnimatedSprite2D.play(anim_name)
		current_animation = anim_name

func _perform_spellcast():
	is_attacking = true
	can_attack = false
	last_attack_time = Time.get_ticks_msec() / 1000.0
	var dir_name = _get_direction_name(player.position - position)
	facing_direction = dir_name
	$AttackBox.monitoring = true
	_play_animation(get_attack_animation(facing_direction))
	await get_tree().create_timer(0.28).timeout
	$AttackBox.monitoring = false
	# No idle animation here—wait for animation finished!
	await get_tree().create_timer(attack_cooldown).timeout
	can_attack = true
	# Only set is_attacking = false after animation finished!

func _choose_new_patrol_target():
	var x = patrol_area.position.x + rng.randf_range(0, patrol_area.size.x)
	var y = patrol_area.position.y + rng.randf_range(0, patrol_area.size.y)
	patrol_target = Vector2(x, y)

func _get_direction_name(vec : Vector2) -> String:
	if vec.length() < 0.4:
		return facing_direction
	if abs(vec.x) > abs(vec.y):
		return "Right" if vec.x > 0 else "Left"
	else:
		return "Down" if vec.y > 0 else "Up"

func _on_HurtBox_area_entered(area):
	if area.is_in_group("player_attacks"):
		hp -= area.damage if area.has("damage") else 5
		print("BushMage HP: %d/%d" % [hp, max_hp])
		if hp <= 0:
			_die()

func _on_AttackBox_area_entered(area):
	if area.is_in_group("player_hurtbox"):
		if area.has_method("take_damage"):
			area.take_damage(attack_damage)
		print("BushMage hits player for %d damage!" % attack_damage)

func _die():
	_spawn_chest_if_lucky()
	_give_xp_to_player()
	queue_free()
	get_tree().create_timer(respawn_delay).timeout.connect(_on_respawn)

func _spawn_chest_if_lucky():
	if rng.randf() < 0.1:
		var chest = preload("res://Resources/Scene/BankChest.tscn").instantiate()
		get_tree().current_scene.add_child(chest)
		chest.position = position
		print("Chest spawned!")

func _give_xp_to_player():
	if player and player.has("gain_xp"):
		player.gain_xp(xp_reward)
		print("+%dxp to player!" % xp_reward)

func _on_respawn():
	var new_bushmage = preload("res://Resources/Objects/Enemy/BushMage.tscn").instantiate()
	get_tree().current_scene.add_child(new_bushmage)
	new_bushmage.position = patrol_center

func _on_animated_sprite_2d_animation_finished() -> void:
	var current = $AnimatedSprite2D.animation
	if current.begins_with("Attack"):
		is_attacking = false
		_play_animation(get_idle_animation())
