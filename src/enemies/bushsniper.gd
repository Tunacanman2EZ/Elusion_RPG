extends BaseEnemy

const ARROW_SCENE = preload("res://scene/enemy/arrow.tscn")

func _ready():
	max_hp = 50
	attack_cooldown = 2.0
	attack_range = 200.0
	flee_range = 100.0
	super._ready()

func get_move_speed() -> float:
	return 80.0

func fire_projectile():
	var spawn_node = _get_spawn_node()
	if spawn_node == null:
		return
	var arrow = ARROW_SCENE.instantiate()
	arrow.position = spawn_node.global_position
	get_tree().current_scene.add_child(arrow)
	arrow.shoot(attack_direction)

func _get_spawn_node() -> Marker2D:
	match attack_direction:
		"left":  return $arrowspawnleft
		"right": return $arrowspawnright
		"up":    return $arrowspawntop
		"down":  return $arrowspawnbottom
	return null

# no run — use walk for all movement
func play_walk_animation(dir: String) -> void:
	if dir != "":
		$animatedsprite2d.play("walk" + dir)

func play_attack_animation(dir: String) -> void:
	$animatedsprite2d.play("attack" + dir)

func play_idle_animation(dir: String) -> void:
	$animatedsprite2d.play("idle" + dir)
