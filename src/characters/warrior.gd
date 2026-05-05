extends "res://src/characters/player.gd"

func _ready():
	super._ready()
	character_name = "warrior"
	speed = 200
	max_hp = 100
	hp = 100
	max_stamina = 100
	stamina = 100
	max_mana = 100
	mana = 100
	attack = 20
	defense = 1
	if not $animatedsprite2d.animation_finished.is_connected(_on_animatedsprite2d_animation_finished):
		$animatedsprite2d.animation_finished.connect(_on_animatedsprite2d_animation_finished)

# connected via hitbox body_entered signal in warrior.tscn
# detects enemy CharacterBody2D nodes directly
func _on_hitbox_area_entered(area: Area2D) -> void:
	var parent = area.get_parent()
	if parent and parent.is_in_group("enemies"):
		if parent.has_method("take_damage"):
			parent.take_damage(attack)
			gain_attack_xp(5)

func _on_interaction_zone_body_entered(body: Node2D) -> void:
	if body.is_in_group("interactors"):
		print("press e to interact with: ", body.name)

func _on_interaction_zone_body_exited(body: Node2D) -> void:
	if body.is_in_group("interactors"):
		print("left range of: ", body.name)

func take_damage(amount: int, _type: StringName = &"physical") -> void:
	hp = clamp(hp - amount, 0, max_hp)
	took_damage.emit(amount, str(_type))
	if hp <= 0:
		died.emit()
		die()

func gain_xp(amount: int):
	xp += amount
	xp_gained_signal.emit(amount)
	while xp >= xp_next:
		level_up()
		xp -= xp_next
		xp_next *= 2

func add_gold(amount: int) -> void:
	gold += amount
	gold_changed_signal.emit(gold)
	update_gold_label()

func _physics_process(_delta):
	if is_attacking:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	if Input.is_action_just_pressed("attack"):
		attack_action()
		return
	var direction := Vector2.ZERO
	if Input.is_action_pressed("move_right"): direction.x += 1
	if Input.is_action_pressed("move_left"):  direction.x -= 1
	if Input.is_action_pressed("move_down"):  direction.y += 1
	if Input.is_action_pressed("move_up"):    direction.y -= 1
	if abs(direction.x) > 0:
		direction.y = 0
	elif abs(direction.y) > 0:
		direction.x = 0
	if direction != Vector2.ZERO:
		velocity = direction.normalized() * (speed + (agility - 1) * 10)
		if has_node("animatedsprite2d"):
			$animatedsprite2d.play(get_walk_animation(direction))
		last_direction = direction
		take_step()
		moved.emit(global_position, str(last_direction))
	else:
		velocity = Vector2.ZERO
		if has_node("animatedsprite2d"):
			$animatedsprite2d.play(get_idle_animation())
	move_and_slide()
