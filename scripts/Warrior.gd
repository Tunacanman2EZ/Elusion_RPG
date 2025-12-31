extends CharacterBody2D

# === BASIC MOVEMENT ===
@export var speed := 150

# === INVENTORY AND CURRENCY ===
var gold := 0
var lusions := 0
var inventory: Inventory = null

# --- UI label node paths (set these from your inventory UI code if needed) ---
var gold_label: Label = null
var lusions_label: Label = null

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
var xp := 0
var xp_next := 100

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

func _physics_process(_delta):
	var direction := Vector2.ZERO
	if Input.is_action_pressed("ui_right"):
		direction.x += 1
	if Input.is_action_pressed("ui_left"):
		direction.x -= 1
	if Input.is_action_pressed("ui_down"):
		direction.y += 1
	if Input.is_action_pressed("ui_up"):
		direction.y -= 1
	if abs(direction.x) > 0:
		direction.y = 0
	elif abs(direction.y) > 0:
		direction.x = 0
	if direction != Vector2.ZERO:
		velocity = direction.normalized() * (speed + (agility - 1) * 10)
		$AnimatedSprite2D.play(get_walk_animation(direction))
		take_step()
	else:
		velocity = Vector2.ZERO
		$AnimatedSprite2D.stop()
	move_and_slide()

# === ANIMATION HANDLING ===
func get_walk_animation(dir: Vector2) -> String:
	if dir.x > 0:
		return "Walk_Right"
	elif dir.x < 0:
		return "Walk_Left"
	elif dir.y > 0:
		return "Walk_Down"
	elif dir.y < 0:
		return "Walk_Up"
	return "Idle"

# === MOVEMENT HOOK ===
func take_step():
	pass

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

# === HP DAMAGE AND LEVEL SYSTEM ===
func take_damage(amount: int) -> void:
	hp = clamp(hp - amount, 0, max_hp)
	assert(hp >= 0, "HP went below 0!")

func level_up() -> void:
	level += 1
	max_hp += 10
	hp = clamp(hp + 10, 0, max_hp)
	assert(hp <= max_hp, "HP went above max after level up!")

# === XP AND LEVELING LOGIC ===
func get_threshold(stat_level: int, multiplier: float) -> int:
	return int(100 * pow(multiplier, stat_level - 1))

func gain_xp(amount: int):
	xp += amount
	while xp >= xp_next:
		level_up()
		xp -= xp_next
		xp_next *= 2

func calculate_xp_award(player_stat: int, monster_level: int, base_xp: int) -> int:
	if monster_level > player_stat + 10:
		return int(base_xp * 0.25)
	elif monster_level < player_stat - 10:
		return int(base_xp * 0.5)
	return base_xp

# === STAT XP & LEVELING ===
func swing_attack(monster_level: int, base_xp: int = 1):
	var xp_gain = calculate_xp_award(attack, monster_level, base_xp)
	attack_xp += xp_gain
	var threshold = get_threshold(attack, 1.25)
	while attack_xp >= threshold:
		attack += 1
		attack_xp -= threshold
		threshold = get_threshold(attack, 1.25)

func block(monster_level: int, base_xp: int = 1):
	var xp_gain = calculate_xp_award(defense, monster_level, base_xp)
	defense_xp += xp_gain
	var threshold = get_threshold(defense, 1.20)
	while defense_xp >= threshold:
		defense += 1
		defense_xp -= threshold
		threshold = get_threshold(defense, 1.20)

func dodge(monster_level: int, base_xp: int = 1):
	var xp_gain = calculate_xp_award(agility, monster_level, base_xp)
	agility_xp += xp_gain
	var threshold = get_threshold(agility, 1.15)
	while agility_xp >= threshold:
		agility += 1
		agility_xp -= threshold
		threshold = get_threshold(agility, 1.15)

func cast_spell(monster_level: int, base_xp: int = 1):
	var xp_gain = calculate_xp_award(magic, monster_level, base_xp)
	magic_xp += xp_gain
	var threshold = get_threshold(magic, 1.25)
	while magic_xp >= threshold:
		magic += 1
		magic_xp -= threshold
		threshold = get_threshold(magic, 1.25)

func fish(base_xp: int = 1):
	var xp_gain = calculate_xp_award(fishing, 1, base_xp)
	fishing_xp += xp_gain
	var threshold = get_threshold(fishing, 1.12)
	while fishing_xp >= threshold:
		fishing += 1
		fishing_xp -= threshold
		threshold = get_threshold(fishing, 1.12)

func cook(base_xp: int = 1):
	var xp_gain = calculate_xp_award(cooking, 1, base_xp)
	cooking_xp += xp_gain
	var threshold = get_threshold(cooking, 1.10)
	while cooking_xp >= threshold:
		cooking += 1
		cooking_xp -= threshold
		threshold = get_threshold(cooking, 1.10)
