extends BaseEnemy

const ELECTRIC_ORB_SCENE = preload("res://scene/enemy/magicprojectile.tscn")

func _ready():
	max_hp = 35
	attack_cooldown = 2.5
	attack_range = 280.0
	flee_range = 150.0
	super._ready()
	if has_node("animatedsprite2d"):
		$animatedsprite2d.play("idledown")

func get_move_speed() -> float:
	return 90.0

func fire_projectile():
	print("fire_projectile called, direction: ", attack_direction)
	var spawn_node = _get_spawn_node()
	print("spawn node: ", spawn_node)
	if spawn_node == null:
		print("spawn node is null!")
		return
	var orb = ELECTRIC_ORB_SCENE.instantiate()
	orb.global_position = spawn_node.global_position
	get_tree().current_scene.add_child(orb)
	orb.shoot(attack_direction)
	print("orb fired!")

func _get_spawn_node() -> Marker2D:
	match attack_direction:
		"left":  return $orbspawnleft
		"right": return $orbspawnright
		"up":    return $orbspawntop
		"down":  return $orbspawnbottom
	return null

func play_walk_animation(dir: String) -> void:
	if dir != "" and has_node("animatedsprite2d"):
		$animatedsprite2d.play("walk" + dir)

func play_attack_animation(dir: String) -> void:
	if has_node("animatedsprite2d"):
		var anim = "attack" + dir
		if $animatedsprite2d.sprite_frames.has_animation(anim):
			$animatedsprite2d.play(anim)
		else:
			$animatedsprite2d.play("attackup")

func play_idle_animation(dir: String) -> void:
	if has_node("animatedsprite2d"):
		$animatedsprite2d.play("idle" + dir)
