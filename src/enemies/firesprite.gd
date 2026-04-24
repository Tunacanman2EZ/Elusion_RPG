extends BaseEnemy

const FIRE_ORB_SCENE = preload("res://scene/enemy/fireprojectile.tscn")

func _ready():
	max_hp = 40
	attack_cooldown = 2.0
	attack_range = 240.0
	flee_range = 130.0
	super._ready()
	if has_node("animatedsprite2d"):
		$animatedsprite2d.play("idledown")

func get_move_speed() -> float:
	return 85.0

func fire_projectile():
	var spawn_node = _get_spawn_node()
	if spawn_node == null:
		return
	var orb = FIRE_ORB_SCENE.instantiate()
	orb.global_position = spawn_node.global_position
	get_tree().current_scene.add_child(orb)
	orb.shoot(attack_direction)

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
