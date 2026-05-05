# base player class — inherited by warrior, mage, healer, and tank
extends CharacterBody2D

# --- identity ---
# the character class name — set by each subclass e.g. "warrior", "mage"
var character_name := "player"

# --- level and xp ---
# current character level — increases on level up
var level := 1

# current total xp earned
var xp := 0

# xp required to reach the next level — doubles each level
var xp_next := 100

# --- health ---
# maximum health points — increases on level up
var max_hp := 20

# current health points — reduced by damage, restored by healing
var hp := 20

# --- stamina ---
# maximum stamina — used by warrior and tank for physical skills
var max_stamina := 100

# current stamina — drains on skill use, regens over time
var stamina := 100

# --- mana ---
# current mana — used by all characters for chat command spells
var mana := 0

# maximum mana — set per character class
var max_mana := 0

# --- currency ---
# gold — earned from enemies, chests, and trading
var gold := 0

# lusions — rare premium currency, cosmetics only
var lusions := 0

# --- skills ---
# each skill has a level, current xp, and xp needed for next level
var attack := 1;   var attack_xp := 0;   var attack_xp_next := 100
var defense := 1;  var defense_xp := 0;  var defense_xp_next := 100
var agility := 1;  var agility_xp := 0;  var agility_xp_next := 100
var magic := 1;    var magic_xp := 0;    var magic_xp_next := 100
var fishing := 1;  var fishing_xp := 0;  var fishing_xp_next := 100
var cooking := 1;  var cooking_xp := 0;  var cooking_xp_next := 100

# --- movement ---
# base movement speed — agility increases effective speed
@export var speed := 75

# last movement direction — used for idle and attack animation facing
var last_direction := Vector2.DOWN

# whether the player is currently in an attack animation
var is_attacking := false

# --- inventory ---
# array of items the player is carrying — synced with inventory UI
var inventory = []

# --- ui references ---
# optional label node for displaying gold amount
var gold_label: Label = null

# optional label node for displaying lusions amount
var lusions_label: Label = null

# --- signals ---
# emitted when player takes damage — amount and damage type
signal took_damage(amount: int, type: String)

# emitted when player hp reaches 0
signal died()

# emitted when player gains xp — forwarded to GameState
signal xp_gained_signal(amount: int)

# emitted when gold amount changes — forwarded to GameState
signal gold_changed_signal(amount: int)

# emitted every frame the player moves — forwarded to GameState for multiplayer
signal moved(position: Vector2, direction: String)

func _ready():
	# add to player group so enemies and systems can find this node
	add_to_group("player")

	# play default idle animation on spawn
	if has_node("animatedsprite2d"):
		$animatedsprite2d.play("idledown")

func _physics_process(_delta):
	# if in attack animation freeze movement until animation finishes
	if is_attacking:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	# check for attack input — takes priority over movement
	if Input.is_action_just_pressed("attack"):
		attack_action()
		return

	# build movement direction from input
	var direction := Vector2.ZERO
	if Input.is_action_pressed("move_right"): direction.x += 1
	if Input.is_action_pressed("move_left"):  direction.x -= 1
	if Input.is_action_pressed("move_down"):  direction.y += 1
	if Input.is_action_pressed("move_up"):    direction.y -= 1

	if direction != Vector2.ZERO:
		# move player — agility increases speed by 10 per level above 1
		velocity = direction.normalized() * (speed + (agility - 1) * 10)

		# play the correct walk animation for this direction
		if has_node("animatedsprite2d"):
			$animatedsprite2d.play(get_walk_animation(direction))

		# store last direction for idle and attack animation facing
		last_direction = direction

		# placeholder for footstep sounds — implemented in phase 1
		take_step()

		# emit moved signal for multiplayer position sync
		moved.emit(global_position, str(last_direction))
	else:
		# no input — stop moving and play idle animation
		velocity = Vector2.ZERO
		if has_node("animatedsprite2d"):
			$animatedsprite2d.play(get_idle_animation())

	# apply movement
	move_and_slide()

# --- animation ---

func get_walk_animation(dir: Vector2) -> String:
	# returns the correct walk animation name based on movement direction
	# diagonal directions checked first since they are more specific
	if dir.x > 0.5 and dir.y < -0.5: return "walkupright"
	elif dir.x < -0.5 and dir.y < -0.5: return "walkupleft"
	elif dir.x > 0.5 and dir.y > 0.5: return "walkdownright"
	elif dir.x < -0.5 and dir.y > 0.5: return "walkdownleft"
	elif dir.x > 0: return "walkright"
	elif dir.x < 0: return "walkleft"
	elif dir.y > 0: return "walkdown"
	elif dir.y < 0: return "walkup"
	return "idledown"

func get_idle_animation() -> String:
	# returns the correct idle animation based on last movement direction
	if last_direction.x > 0.5 and last_direction.y < -0.5: return "idleupright"
	elif last_direction.x < -0.5 and last_direction.y < -0.5: return "idleupleft"
	elif last_direction.x > 0.5 and last_direction.y > 0.5: return "idledownright"
	elif last_direction.x < -0.5 and last_direction.y > 0.5: return "idledownleft"
	elif last_direction.x > 0: return "idleright"
	elif last_direction.x < 0: return "idleleft"
	elif last_direction.y > 0: return "idledown"
	elif last_direction.y < 0: return "idleup"
	return "idledown"

func get_attack_animation(dir: Vector2) -> String:
	# returns the correct attack animation based on facing direction
	if dir.x > 0.5 and dir.y < -0.5: return "attackupright"
	elif dir.x < -0.5 and dir.y < -0.5: return "attackupleft"
	elif dir.x > 0.5 and dir.y > 0.5: return "attackdownright"
	elif dir.x < -0.5 and dir.y > 0.5: return "attackdownleft"
	elif dir.x > 0: return "attackright"
	elif dir.x < 0: return "attackleft"
	elif dir.y > 0: return "attackdown"
	elif dir.y < 0: return "attackup"
	return "attackdown"

# --- attack ---

func attack_action():
	# do nothing if already attacking
	if is_attacking: return

	# lock movement and start attack animation
	is_attacking = true
	if has_node("animatedsprite2d"):
		$animatedsprite2d.play(get_attack_animation(last_direction))

func _on_animatedsprite2d_animation_finished():
	# called when any animation completes
	if has_node("animatedsprite2d"):
		# only handle attack animation completion
		if $animatedsprite2d.animation.begins_with("attack"):
			# unlock movement
			is_attacking = false
			# return to idle animation
			$animatedsprite2d.play(get_idle_animation())

func take_step():
	# placeholder for footstep sound effects
	# will be connected to SFX system in phase 1
	pass

# --- combat ---

func take_damage(amount: int, _type: StringName = &"physical") -> void:
	# reduce hp by damage amount — clamped to prevent going below 0 or above max
	hp = clamp(hp - amount, 0, max_hp)

	# emit signal for GameState multiplayer tracking
	took_damage.emit(amount, str(_type))

	# check if player has died
	if hp <= 0:
		# emit died signal for GameState
		died.emit()
		die()

func die():
	# use call_deferred to avoid crash from freeing during physics process
	call_deferred("_deferred_die")

func _deferred_die():
	# send player back to character select screen on death
	get_tree().change_scene_to_file("res://scene/ui/menus/characterselect.tscn")

func heal(amount: int):
	# restore hp — clamped to prevent exceeding max hp
	hp = clamp(hp + amount, 0, max_hp)

# --- leveling ---

func level_up() -> void:
	# increase level
	level += 1

	# increase max hp on level up
	max_hp += 10

	# restore some hp on level up — clamped to new max
	hp = clamp(hp + 10, 0, max_hp)

func gain_xp(amount: int):
	# add xp to total
	xp += amount

	# emit signal for GameState tracking
	xp_gained_signal.emit(amount)

	# check for level up — loop in case of multiple level ups at once
	while xp >= xp_next:
		level_up()
		xp -= xp_next
		# double xp required for each subsequent level
		xp_next *= 2

func xp_needed_for_skill(skill_level: int, base := 100, factor := 1.18) -> int:
	# calculates xp needed for next skill level using exponential curve
	# higher factor = steeper curve = harder to level up at high levels
	return int(base * pow(factor, skill_level - 1))

# --- skill xp ---

func gain_attack_xp(amount: int):
	# add xp to attack skill and level up if threshold reached
	attack_xp += amount
	while attack_xp >= attack_xp_next:
		attack += 1
		attack_xp -= attack_xp_next
		attack_xp_next = xp_needed_for_skill(attack, 100, 1.25)

func gain_defense_xp(amount: int):
	# add xp to defense skill and level up if threshold reached
	defense_xp += amount
	while defense_xp >= defense_xp_next:
		defense += 1
		defense_xp -= defense_xp_next
		defense_xp_next = xp_needed_for_skill(defense, 100, 1.20)

func gain_agility_xp(amount: int):
	# add xp to agility skill and level up if threshold reached
	agility_xp += amount
	while agility_xp >= agility_xp_next:
		agility += 1
		agility_xp -= agility_xp_next
		agility_xp_next = xp_needed_for_skill(agility, 100, 1.15)

func gain_magic_xp(amount: int):
	# add xp to magic skill and level up if threshold reached
	magic_xp += amount
	while magic_xp >= magic_xp_next:
		magic += 1
		magic_xp -= magic_xp_next
		magic_xp_next = xp_needed_for_skill(magic, 100, 1.25)

func gain_fishing_xp(amount: int):
	# add xp to fishing skill and level up if threshold reached
	fishing_xp += amount
	while fishing_xp >= fishing_xp_next:
		fishing += 1
		fishing_xp -= fishing_xp_next
		fishing_xp_next = xp_needed_for_skill(fishing, 100, 1.12)

func gain_cooking_xp(amount: int):
	# add xp to cooking skill and level up if threshold reached
	cooking_xp += amount
	while cooking_xp >= cooking_xp_next:
		cooking += 1
		cooking_xp -= cooking_xp_next
		cooking_xp_next = xp_needed_for_skill(cooking, 100, 1.10)

# --- currency ---

func add_gold(amount: int) -> void:
	# add gold and emit signal for GameState tracking
	gold += amount
	gold_changed_signal.emit(gold)
	update_gold_label()

func update_gold_label() -> void:
	# update the gold display label if it exists
	if gold_label:
		gold_label.text = "gold: " + str(gold)

func add_lusions(amount: int) -> void:
	# add lusions premium currency
	lusions += amount
	update_lusions_label()

func update_lusions_label() -> void:
	# update the lusions display label if it exists
	if lusions_label:
		lusions_label.text = "lusions: " + str(lusions)

# --- ui ---

func update_stats_labels(statspanel):
	# updates all stat labels in the stats panel UI
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
