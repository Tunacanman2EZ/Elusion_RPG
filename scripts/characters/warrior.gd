"""
Player Character Script (Godot 4.5, Warrior Example)

WHY: Controls core movement, stats, combat, currencies, experience, and UI for the player character.
HOW: Extends CharacterBody2D for physics/collision, handles input, updates UI panels, and manages RPG progression.
WHAT: Single script to keep early prototypes simple; designed for expansion with more systems (stamina regen, debuffs, etc).
TODO:
 - Modularize into smaller scripts as features grow.
 - Improve XP/level curves tuning.
 - Add mana, status effects, enemies, AI routines.
 - Refactor UI updates—use signals/events instead of direct node lookups.
"""
extends CharacterBody2D

# --- BASIC PLAYER PROPERTIES ---
@export var speed := 75  # Player movement speed (can be rebalanced later).

var gold := 0            # Soft currency ("gold coins")—shop, loot, rewards, etc.
var lusions := 0         # Premium currency for rare items or upgrades (design choice).
var inventory = []       # Item storage. TODO: Replace with Dict<String, int> for stackable items.

# --- UI LABELS (referenced nodes) ---
var gold_label: Label = null     # Label node for displaying gold UI.
var lusions_label: Label = null  # Label node for lusions currency UI.

# --- RPG CHARACTER STATS ---
var character_name := "Warrior"  # For multiplayer, could export or randomize.
var level := 1
var xp := 0
var xp_next := 100
var max_hp := 20
var hp := 20
var max_stamina := 100
var stamina := 100

# --- INDIVIDUAL SKILL TRACKING (could modularize later) ---
var attack := 1;   var attack_xp := 0;   var attack_xp_next := 100
var defense := 1;  var defense_xp := 0;  var defense_xp_next := 100
var agility := 1;  var agility_xp := 0;  var agility_xp_next := 100
var magic := 1;    var magic_xp := 0;    var magic_xp_next := 100
var fishing := 1;  var fishing_xp := 0;  var fishing_xp_next := 100
var cooking := 1;  var cooking_xp := 0;  var cooking_xp_next := 100

var last_direction := Vector2.DOWN  # Used for idle/facing/attack direction replay

# --- PLAYER INITIALIZATION ---
"""
Runs once when the scene is loaded.
WHY: Ensures camera follows player, adds to global group, sets up stat panel if present.
HOW: Checks for Stats UI node to avoid null refs.
TODO: Replace hard-coded node paths for better modularity.
"""
func _ready():
	$Camera2D.make_current()  # Lock camera to player
	add_to_group("player")
	# Try to update stats panel immediately if present
	var stats_panel = null
	var curr_scene = get_tree().current_scene
	if curr_scene and curr_scene.has_node("MenuScreen/InventoryUI/PanelContainer/Stats"):
		stats_panel = curr_scene.get_node("MenuScreen/InventoryUI/PanelContainer/Stats")
	if stats_panel:
		update_stats_labels(stats_panel)

# --- MAIN MOVEMENT AND PHYSICS LOOP ---
"""
Handles all walking, direction, and animation logic.

WHY: Core player feel—smooth, simple, can be extended.
HOW:
 - Reads directional input.
 - Only one axis at a time (classic RPG style; fixes diagonal sprint cheat).
 - Sets velocity and plays walk/idle animations.
 - Updates last_direction for attack/idling.
TODO: Add stamina drain, dashing, obstacles, run toggle, and sound FX!
"""
func _physics_process(_delta):
	var direction := Vector2.ZERO
	# Gather input into direction vector; supports arrow keys and remapped controls.
	if Input.is_action_pressed("ui_right"): direction.x += 1
	if Input.is_action_pressed("ui_left"): direction.x -= 1
	if Input.is_action_pressed("ui_down"): direction.y += 1
	if Input.is_action_pressed("ui_up"): direction.y -= 1
	# Lock to horizontal or vertical axis only (disable diagonals for snappier feel).
	if abs(direction.x) > 0:
		direction.y = 0
	elif abs(direction.y) > 0:
		direction.x = 0

	if direction != Vector2.ZERO:
		# Speed increases slightly with agility stat
		velocity = direction.normalized() * (speed + (agility - 1) * 10)
		$AnimatedSprite2D.play(get_walk_animation(direction))
		last_direction = direction
		take_step()  # Placeholder for step logic (sound, event, footstep FX)
	else:
		velocity = Vector2.ZERO
		$AnimatedSprite2D.play(get_idle_animation())
	move_and_slide()

"""
Chooses the correct walk animation string based on player direction.

WHY: Keeps visuals consistent with movement.
HOW: Checks horizontal/vertical axes.
TODO: Add new sprites for diagonal walking.
"""
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

"""
Chooses the correct idle animation string based on last movement direction.

WHY: Player stays facing the last way they moved; avoids “twist reset” bug.
TODO: Animate idle stance (blinking, fidgeting), add weapons.
"""
func get_idle_animation() -> String:
	if last_direction.x > 0:
		return "Idle_Right"
	elif last_direction.x < 0:
		return "Idle_Left"
	elif last_direction.y > 0:
		return "Idle_Down"
	elif last_direction.y < 0:
		return "Idle_Up"
	return "Idle"

# --- COMBAT/ATTACK LOGIC ---
"""
Handles all logic for when the player attacks.

WHY: Triggers combat visuals (and, soon, game mechanics).
HOW: Uses `last_direction` to choose correct animation.
WHAT: Only does visuals for now. TODO: Add hitboxes, target detection, and effect triggers.
"""
func attack_action():
	print("Warrior is attacking!")  # Debug print—replace or expand soon.
	var dir = last_direction
	var anim = get_attack_animation(dir)
	$AnimatedSprite2D.play(anim)

"""
Chooses the attack animation string for given direction.

WHY: Ensures attack matches player facing.
TODO: Add diagonal attacks, weapon type checks, and multi-hit support.
"""
func get_attack_animation(dir: Vector2) -> String:
	if dir.x > 0:
		return "Attack_Right"
	elif dir.x < 0:
		return "Attack_Left"
	elif dir.y > 0:
		return "Attack_Down"
	elif dir.y < 0:
		return "Attack_Up"
	return "Attack"  # Neutral/fallback

# --- ANIMATION SIGNAL HANDLERS ---
"""
When attack animation finishes, auto-return to idle.

WHY: Other state resets could happen here (combo timer, hit recovery).
TODO: Only auto-idle if attack not interrupted (add state manager?).
"""
func _on_AnimatedSprite2D_animation_finished():
	var current = $AnimatedSprite2D.animation
	if current.begins_with("Attack"):
		$AnimatedSprite2D.play(get_idle_animation())

func take_step(): 
	pass  # TODO: Add stamina drain, footstep audio, tile/loot triggers

# --- UI LABEL UPDATER FOR STATS PANEL ---
"""
Updates the RPG stats panel UI after stat changes.

WHY: Keeps player informed—core part of game feel!
TODO: Update HP/Stamina to show real values. Rework panel for more skills/bars.
"""
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
"""
Adds lusions to total and updates UI.

WHY: Currency change must be shown instantly.
TODO: Add max/limit logic.
"""
func add_lusions(amount: int) -> void:
	lusions += amount
	update_lusions_label()

func update_lusions_label() -> void:
	if lusions_label:
		lusions_label.text = "Lusions: " + str(lusions)

"""
Adds gold and updates relevant UI.

WHY: Standard currency gain.
TODO: Trigger “gold sparkle” effect on add.
"""
func add_gold(amount: int) -> void:
	gold += amount
	update_gold_label()

func update_gold_label() -> void:
	if gold_label:
		gold_label.text = "Gold: " + str(gold)

"""
Heals the player by a set amount, clamped to max_hp.

WHY: Could be called from items/events that restore health.
TODO: Trigger heal animation/effects, sound.
"""
func heal(amount: int):
	hp = clamp(hp + amount, 0, max_hp)

# --- HP DAMAGE & LEVEL LOGIC ---
"""
Subtracts HP from player and asserts they can’t go negative.

WHY: Centralizes damage—could be hooked to play hurt effects or trigger death soon.
TODO: Add invulnerability frames, knockback, and “game over.”
"""
func take_damage(amount: int) -> void:
	hp = clamp(hp - amount, 0, max_hp)
	assert(hp >= 0, "HP went below 0!")  # Useful for catching bugs in combat events.

"""
Levels up player: increase level & HP.

WHY: Keeps RPG progression clear and reusable.
TODO: Show a level-up popup, play SFX, unlock new skills at milestones!
"""
func level_up() -> void:
	level += 1
	max_hp += 10
	hp = clamp(hp + 10, 0, max_hp)
	assert(hp <= max_hp, "HP went above max after level up!")

# --- XP/LEVELING CURVES ---
"""
Calculates XP needed for next skill level.

WHY: Allows tuning/adjustment of skill curve easily across the project.
TODO: Use per-skill curve adjustments for more granularity.
"""
func xp_needed_for_skill(skill_level: int, base := 100, factor := 1.18) -> int:
	return int(base * pow(factor, skill_level - 1))

"""
Gains general XP, handles player level-up logic.

WHY: Centralizes XP flow for game-wide events/rewards.
TODO: Trigger level-up cutscene/UI, scale xp_next more smoothly.
"""
func gain_xp(amount: int):
	xp += amount
	while xp >= xp_next:
		level_up()
		xp -= xp_next
		xp_next *= 2

# --- PER-SKILL XP/LEVELING ---
"""
Handles individual skill XP gain/level up for all skills.

WHY: Lets players specialize; easy to add new skills or rebalance.
TODO: Extract into SkillManager system. Add callbacks for new unlocks.
"""
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

# --- FUTURE WORK ---
"""
Team future notes:
 - Refactor large methods into smaller helpers (SRP).
 - Add SFX, VFX, and robust error handling across currency/stats.
 - Consider Signals for UI/data sync, not direct node lookups.
 - Thoroughly test all stat/level up overflow/edge cases.
"""
