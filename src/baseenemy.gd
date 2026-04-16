extends CharacterBody2D
class_name BaseEnemy

@export var max_hp: int = 50
@export var attack_cooldown: float = 2.0
@export var attack_range: float = 200.0
@export var flee_range: float = 100.0

var hp: int
var state: String = "idle"
var player: CharacterBody2D = null
var attack_direction: String = "left"
var attack_ready: bool = true

signal damaged(amount)
signal died

func _ready():
	hp = max_hp
	add_to_group("enemies")
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
	attack_direction = _get_direction_to_player()

	if dist < flee_range:
		state = "run"
		var move_vec = (position - player.position).normalized()
		velocity = move_vec * get_move_speed()
		move_and_slide()
		play_walk_animation(_get_direction_from_vec(move_vec))
		if attack_ready:
			_trigger_attack()

	elif dist < attack_range:
		state = "attack"
		play_attack_animation(attack_direction)
		if attack_ready:
			_trigger_attack()

	else:
		state = "idle"
		play_idle_animation(attack_direction)
		velocity = Vector2.ZERO

	$healthbar.value = hp
	if Engine.get_physics_frames() % 3 == 0:
		_avoid_stacking_with_others()

# --- overridable in subclasses ---
func get_move_speed() -> float:
	return 80.0

func fire_projectile():
	pass  # override in subclass

func play_walk_animation(dir: String) -> void:
	if dir != "":
		$animatedsprite2d.play("walk" + dir)

func play_attack_animation(dir: String) -> void:
	$animatedsprite2d.play("attack" + dir)

func play_idle_animation(dir: String) -> void:
	$animatedsprite2d.play("idle" + dir)

# --- shared logic ---
func _trigger_attack():
	attack_ready = false
	$attacktimer.start()
	fire_projectile()

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
			position += (position - other.position).normalized() * 4

func take_damage(amount: int):
	hp = clamp(hp - amount, 0, max_hp)
	emit_signal("damaged", amount)
	if hp <= 0:
		emit_signal("died")
		queue_free()
