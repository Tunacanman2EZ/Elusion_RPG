extends "res://src/player.gd"

# --- state ---
var is_attacking := false

# --- initialization ---
func _ready():
	super._ready()
	character_name = "warrior"
	speed = 200
	add_to_group("player") # orb checks this group

	# connect the signal if not done in the editor
	if not $animatedsprite2d.animation_finished.is_connected(_on_animatedsprite2d_animation_finished):
		$animatedsprite2d.animation_finished.connect(_on_animatedsprite2d_animation_finished)

func _physics_process(_delta):
	if is_attacking:
		velocity = Vector2.ZERO   
		move_and_slide()
		return

	var direction := Vector2.ZERO
	if Input.is_action_pressed("ui_right"): direction.x += 1
	if Input.is_action_pressed("ui_left"): direction.x -= 1
	if Input.is_action_pressed("ui_down"): direction.y += 1
	if Input.is_action_pressed("ui_up"): direction.y -= 1
	
	if abs(direction.x) > 0:
		direction.y = 0
	elif abs(direction.y) > 0:
		direction.x = 0

	if direction != Vector2.ZERO:
		velocity = direction.normalized() * (speed + (agility - 1) * 10)
		$animatedsprite2d.play(get_walk_animation(direction))
		last_direction = direction
		take_step()
	else:
		velocity = Vector2.ZERO
		$animatedsprite2d.play(get_idle_animation())
	
	move_and_slide()

# --- animation helpers ---
func get_walk_animation(dir: Vector2) -> String:
	if dir.x > 0: return "walkright"
	elif dir.x < 0: return "walkleft"
	elif dir.y > 0: return "walkdown"
	elif dir.y < 0: return "walkup"
	return "idle"

func get_idle_animation() -> String:
	if last_direction.x > 0: return "idleright"
	elif last_direction.x < 0: return "idleleft"
	elif last_direction.y > 0: return "idledown"
	elif last_direction.y < 0: return "idleup"
	return "idledown"

# --- combat/attack logic ---
func attack_action():
	if is_attacking: return
	is_attacking = true
	var anim = get_attack_animation(last_direction)
	$animatedsprite2d.play(anim)

func get_attack_animation(dir: Vector2) -> String:
	if dir.x > 0: return "attackright"
	elif dir.x < 0: return "attackleft"
	elif dir.y > 0: return "attackdown"
	elif dir.y < 0: return "attackup"
	return "attackdown"

func _on_animatedsprite2d_animation_finished() -> void:
	if $animatedsprite2d.animation.begins_with("attack"):
		is_attacking = false
		$animatedsprite2d.play(get_idle_animation())

# --- ui label updater ---
func update_stats_labels(statspanel):
	statspanel.get_node("levellabel").text    = "level: " + str(level)
	statspanel.get_node("hplabel").text       = "hp: " + str(hp) + "/" + str(max_hp)
	statspanel.get_node("staminalabel").text  = "stamina: " + str(stamina)
	statspanel.get_node("attacklabel").text   = "attack: " + str(attack)
	statspanel.get_node("defenselabel").text  = "defense: " + str(defense)
	statspanel.get_node("agilitylabel").text  = "agility: " + str(agility)
	statspanel.get_node("magiclabel").text    = "magic: " + str(magic)
	statspanel.get_node("fishinglabel").text  = "fishing: " + str(fishing)
	statspanel.get_node("cookinglabel").text  = "cooking: " + str(cooking)
	statspanel.get_node("xplabel").text       = "total xp: " + str(xp)

# --- currency/inventory helpers ---
func add_lusions(amount: int) -> void:
	lusions += amount
	update_lusions_label()

func update_lusions_label() -> void:
	if lusions_label:
		lusions_label.text = "lusions: " + str(lusions)

func add_gold(amount: int) -> void:
	gold += amount
	update_gold_label()

func update_gold_label() -> void:
	if gold_label:
		gold_label.text = "gold: " + str(gold)

func heal(amount: int):
	hp = clamp(hp + amount, 0, max_hp)

# --- hp damage & level logic ---
func take_damage(amount: int) -> void:
	hp = clamp(hp - amount, 0, max_hp)
	if hp <= 0:
		die()

func die():
	get_tree().reload_current_scene()

func level_up() -> void:
	level += 1
	max_hp += 10
	hp = clamp(hp + 10, 0, max_hp)

# --- xp/leveling curves ---
func xp_needed_for_skill(skill_level: int, base := 100, factor := 1.18) -> int:
	return int(base * pow(factor, skill_level - 1))

func gain_xp(amount: int):
	xp += amount
	while xp >= xp_next:
		level_up()
		xp -= xp_next
		xp_next *= 2

# --- per-skill xp/leveling ---
func gain_attack_xp(amount: int):
	attack_xp += amount
	while attack_xp >= attack_xp_next:
		attack += 1
		attack_xp -= attack_xp_next
		attack_xp_next = xp_needed_for_skill(attack)

func gain_defense_xp(amount: int):
	defense_xp += amount
	while defense_xp >= defense_xp_next:
		defense += 1
		defense_xp -= defense_xp_next
		defense_xp_next = xp_needed_for_skill(defense)

func gain_agility_xp(amount: int):
	agility_xp += amount
	while agility_xp >= agility_xp_next:
		agility += 1
		agility_xp -= agility_xp_next
		agility_xp_next = xp_needed_for_skill(agility)

func gain_magic_xp(amount: int):
	magic_xp += amount
	while magic_xp >= magic_xp_next:
		magic += 1
		magic_xp -= magic_xp_next
		magic_xp_next = xp_needed_for_skill(magic)

func gain_fishing_xp(amount: int):
	fishing_xp += amount
	while fishing_xp >= fishing_xp_next:
		fishing += 1
		fishing_xp -= fishing_xp_next
		fishing_xp_next = xp_needed_for_skill(fishing)

func gain_cooking_xp(amount: int):
	cooking_xp += amount
	while cooking_xp >= cooking_xp_next:
		cooking += 1
		cooking_xp -= cooking_xp_next
		cooking_xp_next = xp_needed_for_skill(cooking)

# --- area/interaction ---
func _on_sword_area_area_entered(area: Area2D) -> void:
	# hit detection—enemies must be in "enemies" group (lowercase single word)
	if area.is_in_group("enemies"):
		if area.has_method("take_damage"):
			area.take_damage(attack)
			gain_attack_xp(5)
			
func _on_interaction_zone_body_entered(body: Node2D) -> void:
	if body.is_in_group("interactors"):
		print("press e to interact with: ", body.name)
		# ui prompt here

func _on_interaction_zone_body_exited(body: Node2D) -> void:
	if body.is_in_group("interactors"):
		print("left range of: ", body.name)
		# hide prompt here
