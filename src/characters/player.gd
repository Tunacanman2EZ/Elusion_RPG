# base player class — inherited by warrior, mage, healer, and tank.
# handles movement, animation, combat, leveling, currency, the death/revive
# sequence including hit flash and game over transition, universal regen,
# AND universal sprint.
#
# stat recompute architecture:
# - max HP / mana / stamina are PURE FUNCTIONS of level via _recompute_max_stats()
# - each subclass sets its six stat constants in _set_stat_curve() before super._ready()
# - on load AND level-up: recompute maxes, then refill current to max
# - skill stats accumulate from skill XP + level-up bonuses (not recomputed)
#
# level-up feedback (NEW):
# - character level-up spawns a big gold "LEVEL UP!\n{level}" floating popup
# - each skill level-up spawns a smaller cyan "{Skill} {level}" popup
# - defense displays as "Defence" (c) per design; code stays "defense" (s)
#
# currency / regen / sprint / feedback architecture: see inline sections.
extends CharacterBody2D


# =============================================================================
# CONSTANTS
# =============================================================================

# preloaded floating label scene — spawned on damage, healing, and level-ups
const FLOATING_LABEL_SCENE := preload("res://scene/ui/floatinglabel.tscn")

# code skill name -> display name for level-up popups. only "defense" differs
# (shown as "Defence"); the rest just capitalize.
const SKILL_DISPLAY_NAMES := {
	"attack":  "Attack",
	"defense": "Defence",
	"agility": "Agility",
	"magic":   "Magic",
	"fishing": "Fishing",
	"cooking": "Cooking",
}


# =============================================================================
# IDENTITY
# =============================================================================

var character_name := "player"


# =============================================================================
# LEVEL AND XP
# =============================================================================

var level: int = 1
var xp: int = 0
var xp_next: int = 100


# =============================================================================
# STAT CURVE CONSTANTS
# =============================================================================

var hp_base:    int = 20
var hp_per_lvl: int = 0

var mana_base:    int = 0
var mana_per_lvl: int = 0

var stam_base:    int = 100
var stam_per_lvl: int = 0


# =============================================================================
# CORE STATS
# =============================================================================

var max_hp: int = 20
var hp: int = 20

var max_mana: int = 0
var mana: int = 0

var max_stamina: int = 100
var stamina: int = 100


# =============================================================================
# CURRENCY
# =============================================================================

var gold: int = 0

var lusions: int:
	get:
		return CharacterData.get_account_lusions()
	set(value):
		CharacterData.set_account_lusions(value)


# =============================================================================
# SKILLS
# =============================================================================

var attack: int = 1;   var attack_xp: int = 0;   var attack_xp_next: int = 100
var defense: int = 1;  var defense_xp: int = 0;  var defense_xp_next: int = 100
var agility: int = 1;  var agility_xp: int = 0;  var agility_xp_next: int = 100
var magic: int = 1;    var magic_xp: int = 0;    var magic_xp_next: int = 100
var fishing: int = 1;  var fishing_xp: int = 0;  var fishing_xp_next: int = 100
var cooking: int = 1;  var cooking_xp: int = 0;  var cooking_xp_next: int = 100


# =============================================================================
# MOVEMENT
# =============================================================================

@export var speed := 75
var last_direction := Vector2.DOWN
var is_attacking := false


# =============================================================================
# SPRINT
# =============================================================================

@export var sprint_speed_multiplier: float = 2.0
@export var sprint_stamina_drain_per_sec: float = 15.0

var _sprint_drain_accumulator: float = 0.0
var _is_sprinting: bool = false


# =============================================================================
# REGEN
# =============================================================================

@export var regen_rate: float = 1.0
@export var idle_threshold: float = 1.0

var _idle_timer: float = 0.0
var _regen_accumulator: float = 0.0


# =============================================================================
# DEATH AND REVIVE
# =============================================================================

var has_active_revive: bool = false
var is_dying: bool = false

@export var hit_flash_duration: float = 0.15
var _default_modulate: Color = Color.WHITE


# =============================================================================
# INVENTORY
# =============================================================================

var inventory_data: Array = []
var hotbar_assignments: Array = ["", "", "", "", "", "", "", "", ""]


# =============================================================================
# UI REFERENCES
# =============================================================================

var gold_label: Label = null
var lusions_label: Label = null


# =============================================================================
# SIGNALS
# =============================================================================

signal took_damage(amount: int, type: String)
signal died()
signal xp_gained_signal(amount: int)
signal gold_changed_signal(amount: int)
signal lusions_changed_signal(amount: int)
signal moved(position: Vector2, direction: String)


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	add_to_group("player")

	_set_stat_curve()
	CharacterData.load_character_state(self)
	_recompute_max_stats()
	_fill_all_resources()

	if has_node("animatedsprite2d"):
		$animatedsprite2d.play("idledown")
		if not $animatedsprite2d.animation_finished.is_connected(_on_animatedsprite2d_animation_finished):
			$animatedsprite2d.animation_finished.connect(_on_animatedsprite2d_animation_finished)


func _physics_process(_delta):
	if is_dying:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if is_attacking:
		velocity = Vector2.ZERO
		move_and_slide()
		_set_active()
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
		_set_active()

		var wants_sprint: bool = Input.is_action_pressed("sprint") and stamina > 0
		_is_sprinting = wants_sprint

		var base_speed: float = speed + (agility - 1) * 10
		var actual_speed: float = base_speed * sprint_speed_multiplier if _is_sprinting else base_speed
		velocity = direction.normalized() * actual_speed

		if _is_sprinting:
			_sprint_drain_accumulator += sprint_stamina_drain_per_sec * _delta
			if _sprint_drain_accumulator >= 1.0:
				var drain_amount: int = int(_sprint_drain_accumulator)
				_sprint_drain_accumulator -= drain_amount
				stamina = max(0, stamina - drain_amount)

		if has_node("animatedsprite2d"):
			$animatedsprite2d.play(get_walk_animation(direction))
			$animatedsprite2d.speed_scale = sprint_speed_multiplier if _is_sprinting else 1.0
		last_direction = direction
		take_step()
		moved.emit(global_position, str(last_direction))
	else:
		velocity = Vector2.ZERO
		_is_sprinting = false
		_sprint_drain_accumulator = 0.0
		if has_node("animatedsprite2d"):
			$animatedsprite2d.play(get_idle_animation())
			$animatedsprite2d.speed_scale = 1.0

	move_and_slide()

	_idle_timer += _delta
	if _idle_timer >= idle_threshold:
		_regen_accumulator += regen_rate * _delta
		if _regen_accumulator >= 1.0:
			var points: int = int(_regen_accumulator)
			_regen_accumulator -= points
			_regen_stats(points)


# =============================================================================
# STAT CURVE — RECOMPUTE FROM LEVEL
# =============================================================================

func _set_stat_curve() -> void:
	pass


func _recompute_max_stats() -> void:
	max_hp      = hp_base   + (level - 1) * hp_per_lvl
	max_mana    = mana_base + (level - 1) * mana_per_lvl
	max_stamina = stam_base + (level - 1) * stam_per_lvl


func _fill_all_resources() -> void:
	hp      = max_hp
	mana    = max_mana
	stamina = max_stamina


# =============================================================================
# REGEN HELPERS
# =============================================================================

func _set_active() -> void:
	_idle_timer = 0.0
	_regen_accumulator = 0.0


func _regen_stats(amount: int) -> void:
	if hp < max_hp:
		hp = min(max_hp, hp + amount)
	if mana < max_mana:
		mana = min(max_mana, mana + amount)
	if stamina < max_stamina:
		stamina = min(max_stamina, stamina + amount)


# =============================================================================
# FLOATING LABEL FEEDBACK
# =============================================================================

func _spawn_floating_label(amount: int, type: int) -> void:
	if FLOATING_LABEL_SCENE == null:
		push_warning("Player: FLOATING_LABEL_SCENE not loaded")
		return

	var lbl = FLOATING_LABEL_SCENE.instantiate()
	if lbl == null:
		return

	get_tree().current_scene.add_child(lbl)
	lbl.global_position = global_position + Vector2(0, -30)
	if lbl.has_method("show_number"):
		lbl.show_number(amount, type)


func _spawn_levelup_popup() -> void:
	# big gold "LEVEL UP!\n{level}" popup above the player. character level-ups
	# are rare, so this lingers longer and is scaled up to feel celebratory.
	# Type.LEVELUP = 3 in floatinglabel's enum (DAMAGE,HEAL,MANA,LEVELUP,SKILLUP)
	if FLOATING_LABEL_SCENE == null:
		return
	var lbl = FLOATING_LABEL_SCENE.instantiate()
	if lbl == null:
		return
	get_tree().current_scene.add_child(lbl)
	lbl.global_position = global_position + Vector2(0, -40)
	if lbl.has_method("show_text"):
		# message, type, lifetime override (~2s), scale (big)
		lbl.show_text("LEVEL UP!\n%d" % level, 3, 2.0, 1.5)


func _spawn_skillup_popup(skill_code: String, new_level: int) -> void:
	# smaller cyan "{Display} {level}" popup. skill level-ups are frequent, so
	# this is compact and short-lived. defense shows as "Defence".
	# Type.SKILLUP = 4 in floatinglabel's enum.
	if FLOATING_LABEL_SCENE == null:
		return
	var display: String = SKILL_DISPLAY_NAMES.get(skill_code, skill_code.capitalize())
	var lbl = FLOATING_LABEL_SCENE.instantiate()
	if lbl == null:
		return
	get_tree().current_scene.add_child(lbl)
	lbl.global_position = global_position + Vector2(0, -35)
	if lbl.has_method("show_text"):
		# message, type, lifetime override (~1.2s), scale (smaller)
		lbl.show_text("%s %d" % [display, new_level], 4, 1.2, 0.9)


# =============================================================================
# ANIMATION HELPERS
# =============================================================================

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


func _on_animatedsprite2d_animation_finished() -> void:
	if not has_node("animatedsprite2d"):
		return
	var anim_name: String = $animatedsprite2d.animation

	if anim_name.begins_with("attack"):
		is_attacking = false
		$animatedsprite2d.play(get_idle_animation())
		return

	if anim_name.begins_with("death"):
		call_deferred("_change_to_game_over")
		return


# =============================================================================
# COMBAT
# =============================================================================

func attack_action() -> void:
	if is_attacking:
		return
	_set_active()
	is_attacking = true
	var anim := get_attack_animation(last_direction)
	if has_node("animatedsprite2d"):
		var sprite: AnimatedSprite2D = $animatedsprite2d
		if sprite.sprite_frames.has_animation(anim):
			sprite.play(anim)
		else:
			push_warning("Player: missing animation '%s' — attack canceled" % anim)
			is_attacking = false


func take_step() -> void:
	pass


func take_damage(amount: int, _type: StringName = &"physical") -> void:
	if is_dying:
		return

	_set_active()

	hp = clamp(hp - amount, 0, max_hp)
	took_damage.emit(amount, str(_type))

	_spawn_floating_label(amount, 0)

	_play_hit_flash()

	if hp <= 0:
		# killing blow — no defense XP granted. dying to farm defense is a
		# degenerate strategy; surviving the hit is what trains the skill.
		died.emit()
		_start_death_sequence()
		return

	# survived the hit — train defense, scaled to damage taken so bigger
	# hits train faster (and weak chip hits can't be farmed efficiently).
	gain_defense_xp(maxi(1, amount / 2))


func _play_hit_flash() -> void:
	if not has_node("animatedsprite2d"):
		return
	var sprite: AnimatedSprite2D = $animatedsprite2d
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", Color(2.0, 2.0, 2.0, 1.0), 0.0)
	tween.tween_property(sprite, "modulate", _default_modulate, hit_flash_duration)


func heal(amount: int) -> void:
	var actual_heal: int = min(amount, max_hp - hp)
	if actual_heal <= 0:
		return
	hp = min(max_hp, hp + amount)
	_spawn_floating_label(actual_heal, 1)


func restore_mana(amount: int) -> void:
	var actual_restore: int = min(amount, max_mana - mana)
	if actual_restore <= 0:
		return
	mana = clamp(mana + amount, 0, max_mana)
	_spawn_floating_label(actual_restore, 2)


# =============================================================================
# DEATH SEQUENCE
# =============================================================================

func _start_death_sequence() -> void:
	is_dying = true
	velocity = Vector2.ZERO

	if has_active_revive:
		has_active_revive = false
		_fill_all_resources()
		is_dying = false
		print("Revive token consumed — instant revive at full resources")
		return

	var death_anim: String = _get_death_animation()
	if has_node("animatedsprite2d"):
		var sprite: AnimatedSprite2D = $animatedsprite2d
		if sprite.sprite_frames.has_animation(death_anim):
			sprite.play(death_anim)
			return

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
	}
	get_tree().change_scene_to_file("res://scene/ui/menus/gameover.tscn")


# =============================================================================
# LEVELING
# =============================================================================

func level_up() -> void:
	# universal level-up: increment level, recompute maxes, refill to full,
	# apply class skill bonuses, then spawn the celebratory level-up popup.
	level += 1
	_recompute_max_stats()
	_fill_all_resources()
	_apply_level_up_skill_bonus()
	_spawn_levelup_popup()
	print("%s leveled up to %d" % [character_name, level])


func _apply_level_up_skill_bonus() -> void:
	pass


func gain_xp(amount: int) -> void:
	xp += amount
	xp_gained_signal.emit(amount)
	while xp >= xp_next:
		level_up()
		xp -= xp_next
		xp_next *= 2
	CharacterData.save_character_state(self)


func xp_needed_for_skill(skill_level: int, base := 100, factor := 1.18) -> int:
	return int(base * pow(factor, skill_level - 1))


# =============================================================================
# SKILL XP
# =============================================================================

func gain_attack_xp(amount: int) -> void:
	attack_xp += amount
	while attack_xp >= attack_xp_next:
		attack += 1
		attack_xp -= attack_xp_next
		attack_xp_next = xp_needed_for_skill(attack, 100, 1.25)
		_spawn_skillup_popup("attack", attack)
	CharacterData.save_character_state(self)


func gain_defense_xp(amount: int) -> void:
	defense_xp += amount
	while defense_xp >= defense_xp_next:
		defense += 1
		defense_xp -= defense_xp_next
		defense_xp_next = xp_needed_for_skill(defense, 100, 1.20)
		_spawn_skillup_popup("defense", defense)
	CharacterData.save_character_state(self)


func gain_agility_xp(amount: int) -> void:
	agility_xp += amount
	while agility_xp >= agility_xp_next:
		agility += 1
		agility_xp -= agility_xp_next
		agility_xp_next = xp_needed_for_skill(agility, 100, 1.15)
		_spawn_skillup_popup("agility", agility)
	CharacterData.save_character_state(self)


func gain_magic_xp(amount: int) -> void:
	magic_xp += amount
	while magic_xp >= magic_xp_next:
		magic += 1
		magic_xp -= magic_xp_next
		magic_xp_next = xp_needed_for_skill(magic, 100, 1.25)
		_spawn_skillup_popup("magic", magic)
	CharacterData.save_character_state(self)


func gain_fishing_xp(amount: int) -> void:
	fishing_xp += amount
	while fishing_xp >= fishing_xp_next:
		fishing += 1
		fishing_xp -= fishing_xp_next
		fishing_xp_next = xp_needed_for_skill(fishing, 100, 1.12)
		_spawn_skillup_popup("fishing", fishing)
	CharacterData.save_character_state(self)


func gain_cooking_xp(amount: int) -> void:
	cooking_xp += amount
	while cooking_xp >= cooking_xp_next:
		cooking += 1
		cooking_xp -= cooking_xp_next
		cooking_xp_next = xp_needed_for_skill(cooking, 100, 1.10)
		_spawn_skillup_popup("cooking", cooking)
	CharacterData.save_character_state(self)


# =============================================================================
# CURRENCY
# =============================================================================

func add_gold(amount: int) -> void:
	gold += amount
	gold_changed_signal.emit(gold)
	update_gold_label()
	CharacterData.save_character_state(self)


func update_gold_label() -> void:
	if gold_label:
		gold_label.text = "gold: " + str(gold)


func add_lusions(amount: int) -> void:
	CharacterData.add_account_lusions(amount)
	lusions_changed_signal.emit(CharacterData.get_account_lusions())
	update_lusions_label()


func update_lusions_label() -> void:
	if lusions_label:
		lusions_label.text = "lusions: " + str(lusions)


# =============================================================================
# UI HELPERS
# =============================================================================

func update_stats_labels(statspanel) -> void:
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


# =============================================================================
# DEBUG
# =============================================================================

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F1: _debug_give_item("tinyhealthpotion", 5)
			KEY_F2: _debug_give_item("ironsword", 1)
			KEY_F3: _debug_give_item("bushamulet", 1)
			KEY_F4: _debug_give_item("smallamountofgold", 1)
			KEY_F5: _debug_give_lusions(20)
			KEY_F6: _debug_give_item("lusions", 5)
			KEY_F7: _debug_give_item("tinymanapotion", 5)
			KEY_M:
				mana = max(mana - 30, 0)
				print("DEBUG: drained 30 mana (now %d)" % mana)
			KEY_F9:  gain_attack_xp(30)
			KEY_F10: gain_defense_xp(30)
			KEY_F11: gain_agility_xp(30)
			KEY_F12: gain_magic_xp(30)

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
		CharacterData.save_character_state(self)
	else:
		print("DEBUG: inventory full or partial fit — couldn't add full quantity")


func _debug_give_lusions(amount: int) -> void:
	add_lusions(amount)
	print("DEBUG: gave %d lusions (now %d total)" % [amount, lusions])
