extends CharacterBody2D

# === BASIC MOVEMENT ===
@export var speed := 150  # Base move speed (improves with agility)

# === INVENTORY AND CURRENCY ===
var gold := 0             # Gold count
var lusions := 0          # Lusions (special currency)
var inventory := []       # List of item identifiers/objects

# === CORE RPG STATS ===
var character_name := "Warrior"
var max_hp := 20
var hp := 20
var level := 1
var attack := 1
var defense := 1
var agility := 1
var magic := 1
var fishing := 1
var cooking := 1
var xp := 0                  # General XP for character level
var xp_next := 100           # XP needed for next level

# === SKILL XP TRACKING ===
var attack_xp := 0
var defense_xp := 0
var agility_xp := 0
var magic_xp := 0
var fishing_xp := 0
var cooking_xp := 0

func _ready():
	$Camera2D.make_current()
	add_to_group("player")
	print("Player added to group: player")  # Debug line!

func _physics_process(_delta):
	# Handle player movement and movement-based animation.
	var direction := Vector2.ZERO

	# Simple WASD/arrow movement
	if Input.is_action_pressed("ui_right"):
		direction.x += 1
	if Input.is_action_pressed("ui_left"):
		direction.x -= 1
	if Input.is_action_pressed("ui_down"):
		direction.y += 1
	if Input.is_action_pressed("ui_up"):
		direction.y -= 1

	if direction != Vector2.ZERO:
		direction = direction.normalized()
		velocity = direction * (speed + (agility - 1) * 10)
		$AnimatedSprite2D.play(get_walk_animation(direction))
		take_step()
	else:
		velocity = Vector2.ZERO
		$AnimatedSprite2D.stop()
	
	move_and_slide()

# === HP DAMAGE AND LEVEL SYSTEM ===

func take_damage(amount: int) -> void:
	# Deal HP damage, clamp HP to [0, max_hp]
	hp = clamp(hp - amount, 0, max_hp)
	assert(hp >= 0, "HP went below 0!")

func level_up() -> void:
	# Level up: increase max/current HP, up to new max.
	level += 1
	max_hp += 10
	hp = clamp(hp + 10, 0, max_hp)
	assert(hp <= max_hp, "HP went above max after level up!")

# === ANIMATION HANDLING ===

func get_walk_animation(dir: Vector2) -> String:
	# Returns walk animation name based on movement direction.
	var angle = dir.angle()
	if angle < 0:
		angle += PI * 2

	if angle >= 7*PI/4 or angle < PI/8:
		return "Walk_Right"
	elif angle < 3*PI/8:
		return "Walk_Bottom_Right"
	elif angle < 5*PI/8:
		return "Walk_Down"
	elif angle < 7*PI/8:
		return "Walk_Bottom_Left"
	elif angle < 9*PI/8:
		return "Walk_Left"
	elif angle < 11*PI/8:
		return "Walk_Top_Left"
	elif angle < 13*PI/8:
		return "Walk_Up"
	elif angle < 15*PI/8:
		return "Walk_Top_Right"
	return "Walk_Right"

# === XP AND LEVELING LOGIC ===

func get_threshold(stat_level: int, multiplier: float) -> int:
	# XP required for next level for a skill. Hardcoded base of 100.
	return int(100 * pow(multiplier, stat_level - 1))

func gain_xp(amount: int):
	# Add general XP, level up when enough is acquired (XP curve doubles each level)
	xp += amount
	while xp >= xp_next:
		level_up()
		xp -= xp_next
		xp_next *= 2

func calculate_xp_award(player_stat: int, monster_level: int, base_xp: int) -> int:
	# XP reward adjustment for monsters/stat curve
	if monster_level > player_stat + 10:
		return int(base_xp * 0.25)
	elif monster_level < player_stat - 10:
		return int(base_xp * 0.5)
	return base_xp

# === STAT XP & LEVELING EXAMPLES ===

func swing_attack(monster_level: int, base_xp: int = 1):
	# Earn attack XP for hitting a monster.
	var xp_gain = calculate_xp_award(attack, monster_level, base_xp)
	attack_xp += xp_gain
	var threshold = get_threshold(attack, 1.25)
	while attack_xp >= threshold:
		attack += 1
		attack_xp -= threshold
		threshold = get_threshold(attack, 1.25)

func take_step():
	# Every frame you move, gain agility XP
	agility_xp += 1
	var threshold = get_threshold(agility, 1.25)
	while agility_xp >= threshold:
		agility += 1
		agility_xp -= threshold
		threshold = get_threshold(agility, 1.25)

func cast_spell(monster_level: int, base_xp: int = 1):
	# Earn magic XP for casting spells.
	var xp_gain = calculate_xp_award(magic, monster_level, base_xp)
	magic_xp += xp_gain
	var threshold = get_threshold(magic, 1.23)
	while magic_xp >= threshold:
		magic += 1
		magic_xp -= threshold
		threshold = get_threshold(magic, 1.23)

func fish_catch(_area_level: int, base_xp: int = 1):
	# Earn fishing XP for catching fish.
	fishing_xp += base_xp
	var threshold = get_threshold(fishing, 1.27)
	while fishing_xp >= threshold:
		fishing += 1
		fishing_xp -= threshold
		threshold = get_threshold(fishing, 1.27)

func cook_dish(_difficulty: int, base_xp: int = 1):
	# Earn cooking XP for cooking dishes.
	cooking_xp += base_xp
	var threshold = get_threshold(cooking, 1.21)
	while cooking_xp >= threshold:
		cooking += 1
		cooking_xp -= threshold
		threshold = get_threshold(cooking, 1.21)
