# base player class — inherited by warrior, mage, healer, and tank.
# handles movement, animation, combat, leveling, currency, and the
# death/revive sequence including hit flash and game over transition.
extends CharacterBody2D

# --- identity ---
var character_name := "player"

# --- level and xp ---
var level: int = 1
var xp: int = 0
var xp_next: int = 100

# --- health ---
var max_hp: int = 20
var hp: int = 20

# --- stamina ---
var max_stamina: int = 100
var stamina: int = 100

# --- mana ---
var mana: int = 0
var max_mana: int = 0

# --- currency ---
var gold: int = 0
var lusions: int = 0

# --- skills ---
var attack: int = 1;   var attack_xp: int = 0;   var attack_xp_next: int = 100
var defense: int = 1;  var defense_xp: int = 0;  var defense_xp_next: int = 100
var agility: int = 1;  var agility_xp: int = 0;  var agility_xp_next: int = 100
var magic: int = 1;    var magic_xp: int = 0;    var magic_xp_next: int = 100
var fishing: int = 1;  var fishing_xp: int = 0;  var fishing_xp_next: int = 100
var cooking: int = 1;  var cooking_xp: int = 0;  var cooking_xp_next: int = 100

# --- movement ---
@export var speed := 75
var last_direction := Vector2.DOWN
var is_attacking := false

# --- inventory ---
var inventory_data: Array = []

# --- ui references ---
var gold_label: Label = null
var lusions_label: Label = null

# --- death/revive state ---
# tracks if the player has armed a revive token — set by right-clicking
# a token in inventory. consumed automatically on death for instant revive.
var has_active_revive: bool = false

# tracks dying state — prevents input, movement, attacks during the death sequence
var is_dying: bool = false

# hit flash modulate duration in seconds — brief white flash on damage
@export var hit_flash_duration: float = 0.15

# cached default modulate color so we restore correctly after the flash
var _default_modulate: Color = Color.WHITE

# --- signals ---
signal took_damage(amount: int, type: String)
signal died()
signal xp_gained_signal(amount: int)
signal gold_changed_signal(amount: int)
signal lusions_changed_signal(amount: int)
signal moved(position: Vector2, direction: String)

func _ready() -> void:
	add_to_group("player")
	CharacterData.load_character_state(self)

	if has_node("animatedsprite2d"):
		$animatedsprite2d.play("idledown")

		# connect animation_finished signal — guard against double connection.
		if not $animatedsprite2d.animation_finished.is_connected(_on_animatedsprite2d_animation_finished):
			$animatedsprite2d.animation_finished.connect(_on_animatedsprite2d_animation_finished)

func _physics_process(_delta):
	# block all movement and input during death sequence —
	# death animation plays, game over scene loads, no other input accepted
	if is_dying:
		velocity = Vector2.ZERO
		move_and_slide()
		return

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

# --- DEBUG: development-only item-giving keys --------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_F1:
			_debug_give_item("healthpotion", 5)
		elif event.keycode == KEY_F2:
			_debug_give_item("ironsword", 1)
		elif event.keycode == KEY_F3:
			_debug_give_item("starteramulet", 1)
		elif event.keycode == KEY_F4:
			_debug_give_item("smallamountofgold", 1)
		elif event.keycode == KEY_F5:
			_debug_give_lusions(20)
		elif event.keycode == KEY_F6:
			_debug_give_item("smalllusions", 5)
		elif event.keycode == KEY_F7:
			_debug_give_item("manapotion", 5)
		elif event.keycode == KEY_F8:
			# drain mana for testing mana potions
			mana = max(mana - 30, 0)
			print("DEBUG: drained 30 mana (now %d)" % mana)

func _debug_give_item(item_id: String, quantity: int) -> void:
	var data := ItemRegistry.get_item(item_id)
	if data == null:
		print("DEBUG: item '%s' not found in registry" % item_id)
		return

	var stack := ItemStack.new(data, quantity)
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud == null:
		print("DEBUG: HUD not found in 'hud' group")
		return

	if hud.inventory_screen == null:
		print("DEBUG: open the inventory at least once before using debug keys")
		return

	var container: Node = hud.inventory_screen.get_node_or_null("%inventorycontainer")
	if container == null:
		print("DEBUG: inventorycontainer not found in inventory_screen")
		return

	if container.add_stack(stack):
		print("DEBUG: gave %d x %s" % [quantity, data.display_name])
	else:
		print("DEBUG: inventory full or partial fit — couldn't add full quantity")

func _debug_give_lusions(amount: int) -> void:
	# grants the player lusions directly — for testing the revive system.
	# uses add_lusions so the signal fires and any listeners (inventory
	# screen, HUD, etc.) refresh their displayed counts automatically.
	add_lusions(amount)
	print("DEBUG: gave %d lusions (now %d total)" % [amount, lusions])

# --- END DEBUG --------------------------------------------------------------

# --- animation ---

func get_walk_animation(dir: Vector2) -> String:
	if abs(dir.x) > abs(dir.y):
		return "walkright" if dir.x > 0 else "walkleft"
	else:
		return "walkdown" if dir.y > 0 else "walkup"

func get_idle_animation() -> String:
	if abs(last_direction.x) > abs(last_direction.y):
		return "idleright" if last_direction.x > 0 else "idleleft"
	else:
		return "idledown" if last_direction.y > 0 else "idleup"

func get_attack_animation(dir: Vector2) -> String:
	if abs(dir.x) > abs(dir.y):
		return "attackright" if dir.x > 0 else "attackleft"
	else:
		return "attackdown" if dir.y > 0 else "attackup"

# --- attack ---

func attack_action() -> void:
	if is_attacking:
		return
	is_attacking = true
	var anim := get_attack_animation(last_direction)
	if has_node("animatedsprite2d"):
		var sprite: AnimatedSprite2D = $animatedsprite2d
		if sprite.sprite_frames.has_animation(anim):
			sprite.play(anim)
		else:
			push_warning("Player: missing animation '%s' — attack canceled" % anim)
			is_attacking = false

func _on_animatedsprite2d_animation_finished() -> void:
	# fires when any non-looping animation finishes.
	# idle/walk animations loop, so this only fires for attack/death/hitflash etc.
	if not has_node("animatedsprite2d"):
		return
	var anim_name: String = $animatedsprite2d.animation

	# attack animation finished — return to idle
	if anim_name.begins_with("attack"):
		is_attacking = false
		$animatedsprite2d.play(get_idle_animation())
		return

	# death animation finished — transition to game over scene
	if anim_name.begins_with("death"):
		call_deferred("_change_to_game_over")
		return

func take_step():
	pass

# --- combat ---

func take_damage(amount: int, _type: StringName = &"physical") -> void:
	if is_dying:
		return

	hp = clamp(hp - amount, 0, max_hp)
	took_damage.emit(amount, str(_type))

	_play_hit_flash()

	if hp <= 0:
		died.emit()
		_start_death_sequence()

func _play_hit_flash() -> void:
	# brief modulate flash — sprite tints brighter, then snaps back.
	# uses a tween so multiple hits cleanly stack (each hit refreshes the flash).
	if not has_node("animatedsprite2d"):
		return
	var sprite: AnimatedSprite2D = $animatedsprite2d
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", Color(2.0, 2.0, 2.0, 1.0), 0.0)
	tween.tween_property(sprite, "modulate", _default_modulate, hit_flash_duration)

func _start_death_sequence() -> void:
	# locks input, plays death animation, transitions to game over scene.
	# if the player has an armed revive token, the token is consumed instead
	# and the death is fully bypassed — no scene change, full HP restored.
	is_dying = true
	velocity = Vector2.ZERO

	if has_active_revive:
		has_active_revive = false
		hp = max_hp
		is_dying = false
		print("Revive token consumed — instant revive at %d HP" % hp)
		return

	var death_anim: String = _get_death_animation()
	if has_node("animatedsprite2d"):
		var sprite: AnimatedSprite2D = $animatedsprite2d
		if sprite.sprite_frames.has_animation(death_anim):
			sprite.play(death_anim)
			return

	# fallback: no death animation, go to game over immediately
	call_deferred("_change_to_game_over")

func _get_death_animation() -> String:
	if abs(last_direction.x) > abs(last_direction.y):
		return "deathright" if last_direction.x > 0 else "deathleft"
	else:
		return "deathdown" if last_direction.y > 0 else "deathup"

func _change_to_game_over() -> void:
	GameState.death_state = {
		"character_name": character_name,
		"death_position": global_position,
		"max_hp": max_hp,
		"lusions": lusions,
	}
	get_tree().change_scene_to_file("res://scene/ui/menus/gameover.tscn")

func restore_mana(amount: int) -> void:
	# restore mana up to max_mana — mirror of heal() for the mana stat.
	# clamps to max so overheal is auto-trimmed.
	mana = clamp(mana + amount, 0, max_mana)

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
	# emits lusions_changed_signal so the inventory screen, HUD, and any
	# other listeners refresh their displayed count without needing to
	# manually poll the player. matches the gold_changed_signal pattern.
	lusions += amount
	lusions_changed_signal.emit(lusions)
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
