extends CharacterBody2D

# --- CONFIGURABLES ---
@export var max_hp: int = 40
@export var attack_cooldown: float = 1.2
@export var attack_range: float = 160.0
@export var flee_range: float = 80.0

# --- STATE ---
var hp: int = max_hp
var state: String = "idle"
var player: CharacterBody2D = null
var attack_direction: String = "left"
var attack_ready: bool = true

signal damaged(amount)
signal died

func _ready():
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]

	$attacktimer.wait_time = attack_cooldown
	$attacktimer.one_shot = true
	$attacktimer.timeout.connect(_on_attack_timer_timeout)

	$healthbar.max_value = max_hp
	$healthbar.value = hp

func _physics_process(_delta):
	if player == null:
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			player = players[0]
		return

	var dist = position.distance_to(player.position)
	var move_vec = Vector2.ZERO

	if dist < flee_range:
		move_vec = (position - player.position).normalized()
		state = "run"
	elif dist < attack_range and attack_ready:
		state = "attack"
		attack_direction = _get_direction_to_player()
		$animatedsprite2d.play("attack" + attack_direction)
	else:
		state = "idle"

	if state == "run":
		velocity = move_vec * 75
		move_and_slide()
		var walk_dir = _get_direction_from_vec(move_vec)
		if walk_dir != "":
			$animatedsprite2d.play("walk" + walk_dir)
	elif state == "idle":
		$animatedsprite2d.play("idle" + attack_direction)

	$healthbar.value = hp
	_avoid_stacking_with_others()

# Called at frame 5 of attack animation by animation event.
func fire_projectile():
	var spawn_node: Marker2D = null
	match attack_direction:
		"left":
			spawn_node = $projectilespawnleft
		"right":
			spawn_node = $projectilespawnright
		"up":
			spawn_node = $projectilespawntop
		"down":
			spawn_node = $projectilespawnbottom

	if spawn_node != null:
		var projectile = preload("res://scene/enemy/magicprojectile.tscn").instantiate()
		projectile.position = spawn_node.global_position
		get_tree().current_scene.add_child(projectile)
		projectile.shoot(attack_direction)
	attack_ready = false
	$attacktimer.start()

func _on_attack_timer_timeout():
	attack_ready = true

func _get_direction_to_player() -> String:
	var diff = player.position - position
	if abs(diff.x) > abs(diff.y):
		return "right" if diff.x > 0 else "left"
	else:
		return "down" if diff.y > 0 else "up"

func _get_direction_from_vec(vec: Vector2) -> String:
	if abs(vec.x) > abs(vec.y):
		return "right" if vec.x > 0 else "left"
	elif abs(vec.y) > 0:
		return "down" if vec.y > 0 else "up"
	return ""

func _avoid_stacking_with_others():
	var others = get_tree().get_nodes_in_group("enemies")
	for other in others:
		if other != self and position.distance_to(other.position) < 24:
			var push = (position - other.position).normalized() * 4
			position += push

func take_damage(amount: int):
	hp -= amount
	emit_signal("damaged", amount)
	if hp <= 0:
		emit_signal("died")
		queue_free()
