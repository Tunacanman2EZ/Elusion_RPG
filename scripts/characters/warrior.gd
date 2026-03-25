extends "res://scripts/characters/player.gd"

var is_attacking = false

# --- WARRIOR INITIALIZATION ---
func _ready():
	super._ready()
	character_name = "Warrior"
	speed = 200
	add_to_group("player")

func _physics_process(_delta):
	if is_attacking:
		velocity = Vector2.ZERO   # Locks the player in place during attack
		move_and_slide()
		return

	# Regular movement code
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
		$AnimatedSprite2D.play(get_walk_animation(direction))
		last_direction = direction
		take_step()
	else:
		velocity = Vector2.ZERO
		$AnimatedSprite2D.play(get_idle_animation())
	move_and_slide()

func get_walk_animation(dir: Vector2) -> String:
	if dir.x > 0: return "Walk_Right"
	elif dir.x < 0: return "Walk_Left"
	elif dir.y > 0: return "Walk_Down"
	elif dir.y < 0: return "Walk_Up"
	return "Idle"

func get_idle_animation() -> String:
	if last_direction.x > 0: return "Idle_Right"
	elif last_direction.x < 0: return "Idle_Left"
	elif last_direction.y > 0: return "Idle_Down"
	elif last_direction.y < 0: return "Idle_Up"
	return "Idle"

# --- COMBAT/ATTACK LOGIC ---
func attack_action():
	if is_attacking:
		print("Attack ignored: already attacking!")
		return
	is_attacking = true
	print("Warrior is attacking!")
	var dir = last_direction
	var anim = get_attack_animation(dir)
	print("Trying to play animation: ", anim)
	$AnimatedSprite2D.play(anim)

func get_attack_animation(dir: Vector2) -> String:
	if dir.x > 0: return "Attack_Right"
	elif dir.x < 0: return "Attack_Left"
	elif dir.y > 0: return "Attack_Down"
	elif dir.y < 0: return "Attack_Up"
	return "Attack"
# --- UI LABEL UPDATER FOR STATS PANEL ---

func update_stats_labels(stats_panel):
	stats_panel.get_node("LevelLabel").text    = "Level: " + str(level)
	stats_panel.get_node("HPLabel").text       = "HP: 1"  # TODO: Show real HP/max_hp
	stats_panel.get_node("StaminaLabel").text  = "Stamina: 1"  # TODO: Show real stamina/max
	stats_panel.get_node("AttackLabel").text   = "Attack: " + str(attack)
	stats_panel.get_node("DefenseLabel").text  = "Defense: " + str(defense)
	stats_panel.get_node("AgilityLabel").text  = "Agility: " + str(agility)
	stats_panel.get_node("MagicLabel").text    = "Magic: " + str(magic)
	stats_panel.get_node("FishingLabel").text  = "Fishing: " + str(fishing)
	stats_panel.get_node("CookingLabel").text  = "Cooking: " + str(cooking)
	stats_panel.get_node("XPLabel").text       = "Total XP: " + str(xp)

# --- CURRENCY/INVENTORY HELPERS ---

func add_lusions(amount: int) -> void:
	lusions += amount
	update_lusions_label()

func update_lusions_label() -> void:
	if lusions_label:
		lusions_label.text = "Lusions: " + str(lusions)

func add_gold(amount: int) -> void:
	gold += amount
	update_gold_label()

func update_gold_label() -> void:
	if gold_label:
		gold_label.text = "Gold: " + str(gold)

func heal(amount: int):
	hp = clamp(hp + amount, 0, max_hp)

# --- HP DAMAGE & LEVEL LOGIC ---

func take_damage(amount: int) -> void:
	hp = clamp(hp - amount, 0, max_hp)
	assert(hp >= 0, "HP went below 0!")  # Useful for catching bugs in combat events.

func level_up() -> void:
	level += 1
	max_hp += 10
	hp = clamp(hp + 10, 0, max_hp)
	assert(hp <= max_hp, "HP went above max after level up!")

# --- XP/LEVELING CURVES ---
func xp_needed_for_skill(skill_level: int, base := 100, factor := 1.18) -> int:
	return int(base * pow(factor, skill_level - 1))

func gain_xp(amount: int):
	xp += amount
	while xp >= xp_next:
		level_up()
		xp -= xp_next
		xp_next *= 2

# --- PER-SKILL XP/LEVELING ---
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

func _on_animated_sprite_2d_animation_finished() -> void:
	var current = $AnimatedSprite2D.animation
	print("Animation finished! Current was: ", current)
	if current.begins_with("Attack"):
		is_attacking = false
		$AnimatedSprite2D.play(get_idle_animation())
