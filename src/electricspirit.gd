extends "res://scene/enemy/electricsprite.tscn"

const ELECTRIC_ORB_SCENE = preload("res://scene/enemy/electricorb.tscn")

@export var max_hp: int = 35
@export var attack_range: float = 280.0
@export var flee_range: float = 150.0
@export var attack_cooldown: float = 2.5

@onready var marker = $marker2d

func _ready():
	super._ready()
	hp = max_hp

func get_move_speed() -> float:
	return 90.0

func _physics_process(_delta):
	if player == null:
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			player = players[0]
		return

	var dist = position.distance_to(player.position)
	attack_direction = _get_direction_to_player()

	if dist < flee_range:
		# flee and shoot simultaneously
		var move_vec = (position - player.position).normalized()
		velocity = move_vec * get_move_speed()
		move_and_slide()
		var walk_dir = _get_direction_from_vec(move_vec)
		if walk_dir != "":
			$animationplayer.play("walk" + walk_dir)
		if attack_ready:
			_trigger_attack()

	elif dist < attack_range:
		# in range — walk toward player slowly and shoot
		var move_vec = (player.position - position).normalized()
		velocity = move_vec * (get_move_speed() * 0.5)
		move_and_slide()
		var walk_dir = _get_direction_from_vec(move_vec)
		if walk_dir != "":
			$animationplayer.play("walk" + walk_dir)
		if attack_ready:
			_trigger_attack()

	else:
		# out of range — walk toward player
		var move_vec = (player.position - position).normalized()
		velocity = move_vec * get_move_speed()
		move_and_slide()
		var walk_dir = _get_direction_from_vec(move_vec)
		if walk_dir != "":
			$animationplayer.play("walk" + walk_dir)

	$healthbar.value = hp
	if Engine.get_physics_frames() % 3 == 0:
		_avoid_stacking_with_others()

func _trigger_attack():
	attack_ready = false
	$attacktimer.start()
	# play attack animation in facing direction
	$animationplayer.play("attack" + attack_direction)
	fire_projectile()

func fire_projectile():
	if marker == null:
		return
	var orb = ELECTRIC_ORB_SCENE.instantiate()
	orb.global_position = marker.global_position
	get_tree().current_scene.add_child(orb)
	orb.shoot(attack_direction)
