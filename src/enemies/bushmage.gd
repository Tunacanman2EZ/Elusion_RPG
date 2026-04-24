extends BaseEnemy

var attack_power: int = 8

func _ready():
	max_hp = 40
	attack_cooldown = 1.2
	attack_range = 160.0
	flee_range = 80.0
	super._ready()

func get_move_speed() -> float:
	return 75.0

func fire_projectile():
	if not has_node("attackarea"):
		return
	var bodies = $attackarea.get_overlapping_bodies()
	for body in bodies:
		if body.is_in_group("player"):
			if body.has_method("take_damage"):
				body.take_damage(attack_power)

func play_idle_animation(dir: String) -> void:
	if has_node("animatedsprite2d"):
		$animatedsprite2d.play("idle" + dir)

func play_attack_animation(dir: String) -> void:
	if has_node("animatedsprite2d"):
		$animatedsprite2d.play("attack" + dir)
