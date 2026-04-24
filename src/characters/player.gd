extends CharacterBody2D

# --- identity ---
var character_name := "player"

# --- level & xp ---
var level := 1
var xp := 0
var xp_next := 100

# --- health ---
var max_hp := 20
var hp := 20

# --- stamina ---
var max_stamina := 100
var stamina := 100

# --- mana ---
var mana := 0
var max_mana := 0

# --- currency ---
var gold := 0
var lusions := 0

# --- skills ---
var attack := 1;   var attack_xp := 0;   var attack_xp_next := 100
var defense := 1;  var defense_xp := 0;  var defense_xp_next := 100
var agility := 1;  var agility_xp := 0;  var agility_xp_next := 100
var magic := 1;    var magic_xp := 0;    var magic_xp_next := 100
var fishing := 1;  var fishing_xp := 0;  var fishing_xp_next := 100
var cooking := 1;  var cooking_xp := 0;  var cooking_xp_next := 100

# --- movement ---
@export var speed := 75
var last_direction := Vector2.DOWN
var is_attacking := false

# --- inventory ---
var inventory = []

# --- ui ---
var gold_label: Label = null
var lusions_label: Label = null

# --- signals ---
signal took_damage(amount: int, type: String)
signal died()
signal xp_gained_signal(amount: int)
signal gold_changed_signal(amount: int)
signal moved(position: Vector2, direction: String)

func _ready():
	add_to_group("player")
	if has_node("animatedsprite2d"):
		$animatedsprite2d.play("idledown")

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

# --- animation ---
func get_walk_animation(dir: Vector2) -> String:
	if dir.x > 0: return "walkright"
	elif dir.x < 0: return "walkleft"
	elif dir.y > 0: return "walkdown"
	elif dir.y < 0: return "walkup"
	return "idledown"

func get_idle_animation() -> String:
	if last_direction.x > 0: return "idleright"
	elif last_direction.x < 0: return "idleleft"
	elif last_direction.y > 0: return "idledown"
	elif last_direction.y < 0: return "idleup"
	return "idledown"

func get_attack_animation(dir: Vector2) -> String:
	if dir.x > 0: return "attackright"
	elif dir.x < 0: return "attackleft"
	elif dir.y > 0: return "attackdown"
	elif dir.y < 0: return "attackup"
	return "attackdown"

# --- attack ---
func attack_action():
	if is_attacking: return
	is_attacking = true
	if has_node("animatedsprite2d"):
		$animatedsprite2d.play(get_attack_animation(last_direction))

func _on_animatedsprite2d_animation_finished():
	if has_node("animatedsprite2d"):
		if $animatedsprite2d.animation.begins_with("attack"):
			is_attacking = false
			$animatedsprite2d.play(get_idle_animation())

func take_step():
	pass

# --- combat ---
func take_damage(amount: int, _type: StringName = &"physical") -> void:
	hp = clamp(hp - amount, 0, max_hp)
	took_damage.emit(amount, str(_type))
	if hp <= 0:
		died.emit()
		die()

func die():
	call_deferred("_deferred_die")

func _deferred_die():
	get_tree().change_scene_to_file("res://scene/ui/menus/characterselect.tscn")

func heal(amount: int):
	hp = clamp(hp + amount, 0, max_hp)

# --- leveling ---
func level_up() -> void:
	level += 1
	max_hp += 10
	hp = clamp(hp + 10, 0, max_hp)

func gain_xp(amount: int):
	xp += amount
	xp_gained_signal.emit(amount)
	while xp >= xp_next:
		level_up()
		xp -= xp_next
		xp_next *= 2

func xp_needed_for_skill(skill_level: int, base := 100, factor := 1.18) -> int:
	return int(base * pow(factor, skill_level - 1))

# --- skill xp ---
func gain_attack_xp(amount: int):
	attack_xp += amount
	while attack_xp >= attack_xp_next:
		attack += 1
		attack_xp -= attack_xp_next
		attack_xp_next = xp_needed_for_skill(attack, 100, 1.25)

func gain_defense_xp(amount: int):
	defense_xp += amount
	while defense_xp >= defense_xp_next:
		defense += 1
		defense_xp -= defense_xp_next
		defense_xp_next = xp_needed_for_skill(defense, 100, 1.20)

func gain_agility_xp(amount: int):
	agility_xp += amount
	while agility_xp >= agility_xp_next:
		agility += 1
		agility_xp -= agility_xp_next
		agility_xp_next = xp_needed_for_skill(agility, 100, 1.15)

func gain_magic_xp(amount: int):
	magic_xp += amount
	while magic_xp >= magic_xp_next:
		magic += 1
		magic_xp -= magic_xp_next
		magic_xp_next = xp_needed_for_skill(magic, 100, 1.25)

func gain_fishing_xp(amount: int):
	fishing_xp += amount
	while fishing_xp >= fishing_xp_next:
		fishing += 1
		fishing_xp -= fishing_xp_next
		fishing_xp_next = xp_needed_for_skill(fishing, 100, 1.12)

func gain_cooking_xp(amount: int):
	cooking_xp += amount
	while cooking_xp >= cooking_xp_next:
		cooking += 1
		cooking_xp -= cooking_xp_next
		cooking_xp_next = xp_needed_for_skill(cooking, 100, 1.10)

# --- currency ---
func add_gold(amount: int) -> void:
	gold += amount
	gold_changed_signal.emit(gold)
	update_gold_label()

func update_gold_label() -> void:
	if gold_label:
		gold_label.text = "gold: " + str(gold)

func add_lusions(amount: int) -> void:
	lusions += amount
	update_lusions_label()

func update_lusions_label() -> void:
	if lusions_label:
		lusions_label.text = "lusions: " + str(lusions)

# --- ui ---
func update_stats_labels(statspanel):
	statspanel.get_node("levellabel").text   = "level: " + str(level)
	statspanel.get_node("hplabel").text      = "hp: " + str(hp) + "/" + str(max_hp)
	statspanel.get_node("staminalabel").text = "stamina: " + str(stamina) + "/" + str(max_stamina)
	statspanel.get_node("manalabel").text    = "mana: " + str(mana) + "/" + str(max_mana)
	statspanel.get_node("attacklabel").text  = "attack: " + str(attack)
	statspanel.get_node("defenselabel").text = "defense: " + str(defense)
	statspanel.get_node("agilitylabel").text = "agility: " + str(agility)
	statspanel.get_node("magiclabel").text   = "magic: " + str(magic)
	statspanel.get_node("fishinglabel").text = "fishing: " + str(fishing)
	statspanel.get_node("cookinglabel").text = "cooking: " + str(cooking)
	statspanel.get_node("xplabel").text      = "total xp: " + str(xp)
