# player.gd base player class — inherited by warrior, mage, healer, and tank.
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

const FLOATING_LABEL_SCENE := preload("res://scene/ui/floatinglabel.tscn")

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

# NEW: setter added so max_hp/mana/stamina recompute whenever level changes
# by ANY means — not just the natural level_up() flow below, but also
# typing a new value directly into the Remote Inspector while the game is
# running (e.g. testing "what does level 50 feel like against this boss")
# or an admin tool setting it directly. previously max stats only
# recomputed at _ready() and inside level_up() — manually editing level
# any other way left max_hp/mana/stamina stale at whatever they were
# before, not matching the new level at all. runs _recompute_max_stats()
# during the class's own initial declaration too, before _set_stat_curve()
# has set this class's real hp_base/hp_per_lvl/etc — harmless, since
# _ready() calls both again right after in the correct order regardless.
var level: int = 1:
	set(value):
		level = value
		_recompute_max_stats()
		_fill_all_resources()
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

# NEW: whether entering is_attacking freezes movement. defaults to true so
# mage/tank/healer keep their existing behavior untouched. warrior sets this
# to false in its own _ready() so it can keep walking during its swing —
# melee classes with cursor-aim attacks don't need the WASD-lock that made
# sense for the old fixed-4-direction swing.
@export var attack_locks_movement: bool = true

# NEW: how hard the player shoves an enemy it walks into, in pixels/sec.
# Enemies are solid to us but we are not solid to them (no enemy masks the
# player layer), so without this an enemy that presses into you pins you with
# no way out. Keep this BELOW `speed` — an enemy should yield to a shove more
# slowly than you walk, so it reads as resistance rather than a bulldozer.
# 0.0 disables shoving entirely and restores the old pinning behaviour.
@export var enemy_push_strength: float = 50.0


# =============================================================================
# SPRINT
# =============================================================================

@export var sprint_speed_multiplier: float = 2.0
@export var sprint_stamina_drain_per_sec: float = 15.0
# NEW: agility XP granted per second of actual sprinting. universal here
# (not warrior-specific) since sprinting itself is shared base-class
# movement, not tied to any one class's kit.
@export var sprint_agility_xp_per_sec: float = 1.0

var _sprint_drain_accumulator: float = 0.0
var _sprint_agility_xp_accumulator: float = 0.0
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

# NEW: which pet (an item_id, e.g. "petsniper") is currently active, if
# any. "" means no active pet. a String, not a node reference — nodes
# don't survive scene changes, this does, since it's handled specially in
# CharacterData.gd's save/load (parallel to hotbar_assignments above,
# outside the int-only SAVEABLE_STATS loop).
var active_pet_id: String = ""


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
	_set_skill_proficiency()
	CharacterData.load_character_state(self)
	_recompute_max_stats()
	_fill_all_resources()

	# NEW: re-spawn the active pet (if any) on every scene load — this is
	# what actually makes a pet survive a scene transition, since the old
	# pet node itself gets freed along with the rest of the old scene.
	# active_pet_id is just a string (an item_id), not a node reference,
	# which is exactly why it CAN survive — see CharacterData.gd's
	# save_character_state()/load_character_state() for where it persists.
	_restore_active_pet()

	if has_node("animatedsprite2d"):
		$animatedsprite2d.play("idledown")
		if not $animatedsprite2d.animation_finished.is_connected(_on_animatedsprite2d_animation_finished):
			$animatedsprite2d.animation_finished.connect(_on_animatedsprite2d_animation_finished)


func _physics_process(_delta):
	if is_dying:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	# CHANGED: only freeze movement during an attack if this class opts into
	# it (attack_locks_movement). warrior sets this false so it can walk
	# while swinging; mage/tank/healer keep the old frozen behavior.
	if is_attacking and attack_locks_movement:
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

			# NEW: agility XP for actual sprinting, not just holding the
			# sprint key — wants_sprint above already requires stamina > 0
			# and the player to be moving, so standing still holding sprint
			# grants nothing. same fractional-accumulator pattern as the
			# stamina drain right above, since gain_agility_xp() takes an
			# int and per-frame amounts are fractional at this rate.
			_sprint_agility_xp_accumulator += sprint_agility_xp_per_sec * _delta
			if _sprint_agility_xp_accumulator >= 1.0:
				var xp_amount: int = int(_sprint_agility_xp_accumulator)
				_sprint_agility_xp_accumulator -= xp_amount
				gain_agility_xp(xp_amount)

		# CHANGED: guard against stomping an in-progress attack animation,
		# same as the idle guard below. previously this fired every physics
		# frame while a movement key was held, which would immediately
		# overwrite the warrior's swing animation with the walk animation
		# since warrior no longer freezes movement during attacks. because
		# looping animations never fire animation_finished, that left
		# is_attacking permanently stuck true — locking out all future
		# attacks and leaving the sprite stuck on a looping walk/idle frame.
		# now: movement (velocity/position) still happens every frame, but
		# the ANIMATION stays on the attack swing until it finishes, then
		# reverts to reflecting walk/idle normally.
		if has_node("animatedsprite2d") and not is_attacking:
			$animatedsprite2d.play(get_walk_animation(direction))
			$animatedsprite2d.speed_scale = sprint_speed_multiplier if _is_sprinting else 1.0
		last_direction = direction
		take_step()
		moved.emit(global_position, str(last_direction))
	else:
		velocity = Vector2.ZERO
		_is_sprinting = false
		_sprint_drain_accumulator = 0.0
		_sprint_agility_xp_accumulator = 0.0
		if has_node("animatedsprite2d") and not is_attacking:
			$animatedsprite2d.play(get_idle_animation())
			$animatedsprite2d.speed_scale = 1.0

	move_and_slide()
	_shove_blocking_enemies(_delta)

	_idle_timer += _delta
	if _idle_timer >= idle_threshold:
		_regen_accumulator += regen_rate * _delta
		if _regen_accumulator >= 1.0:
			var points: int = int(_regen_accumulator)
			_regen_accumulator -= points
			_regen_stats(points)


# =============================================================================
# ENEMY SHOVING
# =============================================================================
#
# The collision relationship between the player and enemies is deliberately
# one-way: the player's collision_mask includes the enemies layer, but no
# enemy's mask includes the player layer. That makes enemies solid to you
# while you are not solid to them.
#
# On its own that is a trap. An enemy walks into you, you are blocked by it,
# it is not blocked by you, and its AI keeps pressing forward — so you are
# pinned with nothing to push against. This was very visible with the poison
# slime, which splits into eight bodies that all converge on the same spot.
#
# The fix is not to make collision mutual. Mutual collision means a pack of
# slimes jams against itself as well as against you, and pathfinding fights
# the physics. Instead the player explicitly shoves whatever it walks into:
# enemies stay solid and still block you, but leaning into one slides it out
# of the way.
#
# move_and_collide() is used on the enemy rather than assigning
# global_position directly, so the shove still respects walls — an enemy
# cannot be pushed through geometry, it just stops moving once it's pinned
# against something solid.
#
# Anything that should be immovable (the boss, a scripted encounter) can be
# added to the "unpushable" group and this will skip it.
func _shove_blocking_enemies(delta: float) -> void:
	if enemy_push_strength <= 0.0:
		return

	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)

		# cast rather than `is` + call: `other` stays statically typed as
		# CharacterBody2D, so is_in_group()/move_and_collide() resolve without
		# the parser complaining about calling Node methods on Object.
		var other := collision.get_collider() as CharacterBody2D
		if other == null or not is_instance_valid(other):
			continue
		if not other.is_in_group("enemies"):
			continue
		if other.is_in_group("unpushable"):
			continue

		# get_normal() points OUT of the surface we collided with, i.e. back
		# toward us. Negating it gives the direction that moves the enemy
		# away from the player.
		var push: Vector2 = -collision.get_normal() * enemy_push_strength * delta
		other.move_and_collide(push)


# =============================================================================
# STAT CURVE — RECOMPUTE FROM LEVEL
# =============================================================================

func _set_stat_curve() -> void:
	pass


# =============================================================================
# SKILL PROFICIENCY  (NEW)
# =============================================================================
# every class can train every skill from the same universal triggers
# (attack XP from any hit — melee or spell; defense XP from taking damage,
# already true above in take_damage(); magic XP from any spell) — but each
# class climbs its OWN specialty faster. base class = 1.0 (no bias) for all
# six skills. subclasses override _set_skill_proficiency() to boost their
# specialty: warrior -> attack, tank -> defense, mage/healer -> magic.
# applied inside gain_attack_xp()/gain_defense_xp()/gain_magic_xp() below,
# so every caller (existing or new) gets the right scaling automatically —
# no call site needs to know or care which class it's running on.
var skill_proficiency: Dictionary = {
	"attack":  1.0,
	"defense": 1.0,
	"agility": 1.0,
	"magic":   1.0,
	"fishing": 1.0,
	"cooking": 1.0,
}

func _set_skill_proficiency() -> void:
	# base implementation: no class bias. subclasses override to boost
	# their specialty — see warrior/tank/mage/healer for actual values.
	pass


# =============================================================================
# DEFENSE TIERS  (NEW)
# =============================================================================
# tiered damage reduction based on the defense skill level. crossing into a
# new tier is a real milestone (see _spawn_defense_tier_popup near
# gain_defense_xp), not just a number ticking up invisibly — five tiers,
# Novice through Unbreakable, capped at 50% reduction so a hit always still
# matters no matter how defended you are.
#
# NOTE: "poise" (resistance to knockback/interrupt at higher tiers) was
# discussed alongside this but deliberately isn't included — there's no
# knockback or hit-interrupt system in the game for poise to resist yet,
# so attaching a perk to a mechanic that doesn't exist isn't worth doing.
# worth revisiting as its own real feature if a hit-reaction system ever
# gets built.
const DEFENSE_TIERS := [
	{"min_level": 80, "name": "Unbreakable", "reduction": 0.50},
	{"min_level": 60, "name": "Hardened",    "reduction": 0.40},
	{"min_level": 40, "name": "Veteran",     "reduction": 0.30},
	{"min_level": 20, "name": "Trained",     "reduction": 0.20},
	{"min_level": 1,  "name": "Novice",      "reduction": 0.10},
]


func _get_defense_tier() -> Dictionary:
	# returns the highest tier this character's current defense level
	# qualifies for. DEFENSE_TIERS is ordered highest min_level first, so
	# the first match walking top-down is always the correct (highest
	# qualifying) tier.
	for tier in DEFENSE_TIERS:
		if defense >= tier["min_level"]:
			return tier
	return DEFENSE_TIERS[-1]  # fallback — unreachable since defense starts at 1


# =============================================================================
# COMBAT DAMAGE BONUSES  (NEW)
# =============================================================================
# +0.5% damage per point above 1 in the given stat, universal across every
# class. every class keeps its OWN primary damage formula unchanged
# (warrior stays attack-driven melee, mage/healer stay magic-driven
# spells) — these are meant to be layered ON TOP of that, specifically for
# whichever stat ISN'T already a class's primary driver, so attack and
# magic both matter for everyone without double-counting a stat a class
# already fully scales off of. e.g. warrior multiplies its existing
# attack-based melee damage by get_magic_damage_bonus(); mage/healer
# multiply their existing magic-based spell damage by
# get_attack_damage_bonus(); tank (no clear primary stat) applies both to
# its flat aura_damage.
const DAMAGE_BONUS_PER_POINT := 0.005

func get_attack_damage_bonus() -> float:
	return 1.0 + (attack - 1) * DAMAGE_BONUS_PER_POINT

func get_magic_damage_bonus() -> float:
	return 1.0 + (magic - 1) * DAMAGE_BONUS_PER_POINT


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

# Where damage/heal/level-up popups get parented.
#
# BaseEnemy._spawn_floating_label() already looked for a node in the
# "floatinglabels" group — a dedicated, high-z_index, non-y-sorted layer so
# numbers always draw over the world instead of being sorted behind a tree or
# an enemy. The player's popups never used it and went straight to the scene
# root, so the two halves of the same feedback system behaved differently.
# This makes both take the same path.
func _label_container() -> Node:
	var container: Node = get_tree().get_first_node_in_group("floatinglabels")
	if container != null:
		return container
	return get_tree().current_scene


func _spawn_floating_label(amount: int, type: int) -> void:
	if FLOATING_LABEL_SCENE == null:
		push_warning("Player: FLOATING_LABEL_SCENE not loaded")
		return

	var lbl = FLOATING_LABEL_SCENE.instantiate()
	if lbl == null:
		return

	_label_container().add_child(lbl)
	lbl.global_position = global_position + Vector2(0, -30)
	if lbl.has_method("show_number"):
		lbl.show_number(amount, type)


func _spawn_levelup_popup() -> void:
	if FLOATING_LABEL_SCENE == null:
		return
	var lbl = FLOATING_LABEL_SCENE.instantiate()
	if lbl == null:
		return
	_label_container().add_child(lbl)
	lbl.global_position = global_position + Vector2(0, -40)
	if lbl.has_method("show_text"):
		lbl.show_text("LEVEL UP!\n%d" % level, 3, 2.0, 1.5)


func _spawn_defense_tier_popup(tier_name: String) -> void:
	# NEW: crossing a defense tier gets the same visual weight as a
	# character level-up (same color type, size, duration) — it's a bigger
	# moment than a routine skill-up, worth treating that way.
	if FLOATING_LABEL_SCENE == null:
		return
	var lbl = FLOATING_LABEL_SCENE.instantiate()
	if lbl == null:
		return
	_label_container().add_child(lbl)
	lbl.global_position = global_position + Vector2(0, -45)
	if lbl.has_method("show_text"):
		lbl.show_text("DEFENSE TIER\n%s" % tier_name, 3, 2.0, 1.5)


func _spawn_skillup_popup(skill_code: String, new_level: int) -> void:
	if FLOATING_LABEL_SCENE == null:
		return
	var display: String = SKILL_DISPLAY_NAMES.get(skill_code, skill_code.capitalize())
	var lbl = FLOATING_LABEL_SCENE.instantiate()
	if lbl == null:
		return
	_label_container().add_child(lbl)
	lbl.global_position = global_position + Vector2(0, -35)
	if lbl.has_method("show_text"):
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

	# NEW: tiered defense reduction — see DEFENSE_TIERS below. XP gain
	# further down still uses the RAW incoming amount, not the reduced
	# one, so higher defense doesn't also slow down future defense XP —
	# that would create a self-limiting feedback loop nobody asked for.
	# maxi(1, ...) guarantees chip damage always gets through — even at
	# the 50% cap, a hit can never be reduced to zero.
	var reduction: float = _get_defense_tier()["reduction"]
	var reduced_amount: int = maxi(1, int(amount * (1.0 - reduction)))

	hp = clamp(hp - reduced_amount, 0, max_hp)
	took_damage.emit(reduced_amount, str(_type))

	_spawn_floating_label(reduced_amount, 0)

	_play_hit_flash()

	if hp <= 0:
		died.emit()
		_start_death_sequence()
		return

	gain_defense_xp(maxi(1, amount / 2))


func _play_hit_flash() -> void:
	if not has_node("animatedsprite2d"):
		return
	var sprite: AnimatedSprite2D = $animatedsprite2d
	# NEW: flash duration scales down with the same reduction percentage
	# already driving damage tiers (see DEFENSE_TIERS) — a Novice takes
	# the full flash, an Unbreakable character's is noticeably brighter,
	# briefer. this is what "poise" actually became once real knockback
	# turned out to need new art this project doesn't have: not a
	# gameplay-affecting resistance, just defense having a real, felt
	# difference in how a hit LOOKS, using assets that already exist.
	# maxf floor keeps it from ever going imperceptibly short.
	var reduction: float = _get_defense_tier()["reduction"]
	var scaled_duration: float = maxf(0.05, hit_flash_duration * (1.0 - reduction))
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", Color(2.0, 2.0, 2.0, 1.0), 0.0)
	tween.tween_property(sprite, "modulate", _default_modulate, scaled_duration)


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
	level += 1
	_recompute_max_stats()
	_fill_all_resources()
	_apply_level_up_skill_bonus()
	_spawn_levelup_popup()
	print("%s leveled up to %d" % [character_name, level])


func _apply_level_up_skill_bonus() -> void:
	pass


func gain_xp(amount: int) -> void:
	# CHANGED: xp_next used to be `xp_next *= 2` — a raw doubling
	# accumulator that overflows a 64-bit int somewhere around level 58
	# (2^57 alone is already past int64's range). the sanity-check side of
	# this got a safety clamp earlier, but that only stopped CharacterData's
	# anti-tamper pass from producing garbage — it never fixed this, the
	# ACTUAL formula every real level-up runs through. now recomputed fresh
	# from the current level each time, same deterministic pattern already
	# used for skill XP (xp_needed_for_skill below) — 1.15 is the same
	# growth factor already proven safe there. at level 99 this needs
	# ~240M total XP for that single level, well within int64's range with
	# enormous headroom, instead of overflowing entirely.
	xp += amount
	xp_gained_signal.emit(amount)
	while xp >= xp_next:
		level_up()
		xp -= xp_next
		xp_next = int(100 * pow(1.15, level - 1))
	CharacterData.save_character_state(self)


func xp_needed_for_skill(skill_level: int, base := 100, factor := 1.18) -> int:
	return int(base * pow(factor, skill_level - 1))


# =============================================================================
# UNIVERSAL DAMAGE SCALING  (NEW)
# =============================================================================
# attack AND magic both contribute a % damage bonus, for EVERY class's
# every attack — melee or spell — not just whichever skill that class's
# kit happens to use as its own primary scaling. this is what gives
# attack/magic XP real payoff across the whole roster: tank/mage/healer
# all gain attack XP now (see skill_proficiency), and without this, that
# XP had zero effect on their own damage output at all — only warrior's
# melee formula ever read it.
#
# each class still has its OWN base damage value (base_melee_damage,
# damage_per_magic reinterpreted as a flat base rather than a per-point
# multiplier, aura_damage) — this multiplier scales ON TOP of that base,
# it doesn't replace class identity, just makes both stats matter
# everywhere. starting percentages, tune to taste.
const ATTACK_DAMAGE_PERCENT_PER_LEVEL: float = 0.01  # +1% damage per attack level
const MAGIC_DAMAGE_PERCENT_PER_LEVEL:  float = 0.01  # +1% damage per magic level

func get_damage_multiplier() -> float:
	return 1.0 \
		+ (attack - 1) * ATTACK_DAMAGE_PERCENT_PER_LEVEL \
		+ (magic - 1) * MAGIC_DAMAGE_PERCENT_PER_LEVEL


# =============================================================================
# SKILL XP
# =============================================================================

func gain_attack_xp(amount: int) -> void:
	# NEW: scaled by skill_proficiency["attack"] — this is what makes
	# attack XP universal (any class can call this) while still letting
	# warrior climb it faster than everyone else. see SKILL PROFICIENCY
	# section above.
	var scaled_amount: int = maxi(1, int(amount * skill_proficiency.get("attack", 1.0)))
	attack_xp += scaled_amount
	while attack_xp >= attack_xp_next:
		attack += 1
		attack_xp -= attack_xp_next
		attack_xp_next = xp_needed_for_skill(attack, 100, 1.25)
		_spawn_skillup_popup("attack", attack)
	CharacterData.save_character_state(self)


func gain_defense_xp(amount: int) -> void:
	# NEW: scaled by skill_proficiency["defense"] — take_damage() above
	# already grants this universally to every class; this is what lets
	# tank climb it faster without touching take_damage() at all.
	var scaled_amount: int = maxi(1, int(amount * skill_proficiency.get("defense", 1.0)))
	var tier_before: String = _get_defense_tier()["name"]
	defense_xp += scaled_amount
	while defense_xp >= defense_xp_next:
		defense += 1
		defense_xp -= defense_xp_next
		defense_xp_next = xp_needed_for_skill(defense, 100, 1.20)
		_spawn_skillup_popup("defense", defense)
	# NEW: a tier crossing (Novice -> Trained -> ... -> Unbreakable) is a
	# bigger moment than an ordinary skill level-up, so it gets its own,
	# more prominent popup on top of the normal one above.
	var tier_after: String = _get_defense_tier()["name"]
	if tier_after != tier_before:
		_spawn_defense_tier_popup(tier_after)
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
	# NEW: scaled by skill_proficiency["magic"] — this is what lets
	# mage/healer climb magic faster than a class that only occasionally
	# lands a spell hit.
	var scaled_amount: int = maxi(1, int(amount * skill_proficiency.get("magic", 1.0)))
	magic_xp += scaled_amount
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
	# NEW: gated behind OS.is_debug_build() — true in the editor and in a
	# "Debug" export, false only in a real "Release" export. without this,
	# EVERY key below (free items, free skill XP, instant pet spawns)
	# would work exactly the same in a build handed to classmates as it
	# does in the editor — anyone pressing F9 a few times becomes
	# instantly overpowered, no decompiling required at all.
	#
	# IMPORTANT: this alone isn't enough — when you actually export for
	# classmates, you must select the "Release" export template in the
	# Export dialog, not "Debug". a debug-template export still reports
	# is_debug_build() == true, and every key below would still work.
	if not OS.is_debug_build():
		return

	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F1: _debug_give_item("tinyhealthpotion", 5)
			KEY_F2: _debug_give_item("ironsword", 1)
			KEY_F3: _debug_give_item("bushamulet", 1)
			KEY_F4: _debug_give_item("smallamountofgold", 1)
			KEY_F5: _debug_give_lusions(20)
			KEY_F6: _debug_give_item("lusions", 5)
			KEY_F7: _debug_give_item("tinymanapotion", 5)
			# NEW: grants the pet ITEM rather than spawning the pet directly,
			# so this exercises the real path — inventory -> use -> summon_pet()
			# -> active_pet_id -> survives a scene change. KEY_P below skips
			# all of that and drops a bare node in the scene, which is why it
			# never caught that the pet items didn't exist.
			#
			# NOT F8: that's the editor's "Stop running project" shortcut and
			# it kills the game even when the game window has focus. Y sits
			# next to the U/I/O/P pet cluster instead, and is unbound in both
			# the input map and every other script.
			KEY_Y: _debug_give_item("petsniper", 1)
			KEY_P: _debug_spawn_pet()
			KEY_O: _debug_spawn_pet_mage()
			KEY_I: _debug_spawn_pet_electric()
			KEY_U: _debug_spawn_pet_fire()
			KEY_M:
				mana = max(mana - 30, 0)
				print("DEBUG: drained 30 mana (now %d)" % mana)
			KEY_F9:  gain_attack_xp(30)
			KEY_F10: gain_defense_xp(30)
			KEY_F11: gain_agility_xp(30)
			KEY_F12: gain_magic_xp(30)

func _debug_spawn_pet_fire() -> void:
	# spawn a test fire pet next to the player to tune follow/attack behavior.
	_despawn_current_pet()
	var pet_scene: PackedScene = load("res://scene/pets/petfiresprite.tscn")
	if pet_scene == null:
		print("DEBUG: petfiresprite.tscn not found — check the path")
		return
	var pet: Node = pet_scene.instantiate()
	_attach_pet(pet, Vector2(0, -40))
	print("DEBUG: spawned fire pet")
	active_pet_id = "petfiresprite"
	CharacterData.save_character_state(self)

func _debug_spawn_pet_electric() -> void:
	_despawn_current_pet()
	var pet_scene: PackedScene = load("res://scene/pets/petelectricsprite.tscn")
	if pet_scene == null:
		print("DEBUG: petelectricsprite.tscn not found — check the path")
		return
	var pet: Node = pet_scene.instantiate()
	_attach_pet(pet, Vector2(0, 40))
	print("DEBUG: spawned electric pet")
	active_pet_id = "petelectricsprite"
	CharacterData.save_character_state(self)

func _debug_spawn_pet() -> void:
	# spawn a test archer pet next to the player to tune follow/attack behavior.
	_despawn_current_pet()
	var pet_scene: PackedScene = load("res://scene/pets/petsniper.tscn")
	if pet_scene == null:
		print("DEBUG: petsniper.tscn not found — check the path")
		return
	var pet: Node = pet_scene.instantiate()
	_attach_pet(pet, Vector2(40, 0))
	print("DEBUG: spawned pet")
	active_pet_id = "petsniper"
	CharacterData.save_character_state(self)


func _debug_spawn_pet_mage() -> void:
	# spawn a test mage pet next to the player to tune the vine attack.
	_despawn_current_pet()
	var pet_scene: PackedScene = load("res://scene/pets/petmage.tscn")
	if pet_scene == null:
		print("DEBUG: petmage.tscn not found — check the path")
		return
	var pet: Node = pet_scene.instantiate()
	_attach_pet(pet, Vector2(-40, 0))
	print("DEBUG: spawned mage pet")
	active_pet_id = "petmage"
	CharacterData.save_character_state(self)


# =============================================================================
# PET PERSISTENCE  (NEW)
# =============================================================================

func _despawn_current_pet() -> void:
	# ensures only one active pet at a time, matching the single
	# active_pet_id model — without this, pressing multiple debug pet keys
	# in a row (or restoring after a scene change while an old one somehow
	# still exists) would leave orphaned pets wandering around that aren't
	# tracked by active_pet_id at all. pet.gd's own _ready() already calls
	# add_to_group("pets"), so this just leans on that existing tag.
	for pet in get_tree().get_nodes_in_group("pets"):
		if is_instance_valid(pet):
			pet.queue_free()


func _attach_pet(pet: Node, offset: Vector2) -> void:
	# NEW: the single place a pet gets put into the world. every spawn path
	# (summon_pet, _restore_active_pet, and the four debug spawners) goes
	# through here so none of them can forget the ownership line below.
	#
	# ORDER MATTERS: owner_player is claimed BEFORE add_child(), because
	# add_child() runs the pet's _ready(), which is where it resolves who to
	# follow. Set it afterwards and the pet has already fallen back to
	# get_nodes_in_group("player")[0] — right by luck with one player,
	# arbitrary with two — and nothing re-resolves it while that stays valid.
	if pet is Pet:
		pet.owner_player = self

	get_tree().current_scene.add_child(pet)
	pet.global_position = global_position + offset
	# NEW: positioned AFTER entering the tree, so without this the pet gets
	# interpolated from wherever it started toward the player on its first
	# rendered frame. See teleporter.gd for why physics interpolation needs
	# to be told about instant placement.
	pet.reset_physics_interpolation()


func _restore_active_pet() -> void:
	# re-spawns the active pet (if any) on scene load — see active_pet_id's
	# comment for why a String survives scene changes when a node can't.
	# looks up the pet's scene via ItemRegistry/ItemData.pet_scene, which
	# already existed specifically for this purpose (see itemdata.gd) —
	# just never wired up until now.
	if active_pet_id == "":
		return

	var item_data := ItemRegistry.get_item(active_pet_id)
	if item_data == null or item_data.pet_scene == null:
		push_warning("Player: active_pet_id '%s' has no valid pet_scene in ItemRegistry — clearing" % active_pet_id)
		active_pet_id = ""
		return

	var pet: Node = item_data.pet_scene.instantiate()
	_attach_pet(pet, Vector2(0, -40))
	print("Player: restored active pet '%s'" % active_pet_id)


func summon_pet(item_id: String) -> bool:
	# NEW: the real summon path, called when a PET item is used from the
	# inventory. the _debug_spawn_* functions below hardcode a res:// path
	# each; this resolves the scene through ItemRegistry exactly the way
	# _restore_active_pet() does, so there is one definition of "which scene
	# is this pet" rather than one per call site.
	#
	# returns false WITHOUT changing anything if the item can't be summoned,
	# so the caller can leave the item sitting in the inventory instead of
	# consuming it for nothing. this is the whole reason it returns a bool.
	var item_data := ItemRegistry.get_item(item_id)
	if item_data == null:
		push_warning("Player: no item '%s' in the registry — cannot summon" % item_id)
		return false
	if item_data.type != ItemData.Type.PET or item_data.pet_scene == null:
		push_warning("Player: item '%s' is not a summonable pet" % item_id)
		return false

	# one pet at a time, matching the single active_pet_id model — summoning
	# a second pet REPLACES the first rather than stacking companions.
	_despawn_current_pet()

	var pet: Node = item_data.pet_scene.instantiate()
	_attach_pet(pet, Vector2(0, -40))

	# set LAST, and only after everything above succeeded — _restore_active_pet()
	# trusts this string to name a pet that actually resolves, and CharacterData
	# persists it per character slot, so a bad value here would follow the save
	# around and warn on every scene load.
	active_pet_id = item_id
	print("Player: summoned pet '%s'" % active_pet_id)
	return true


func dismiss_pet() -> void:
	# NEW: despawn AND forget. distinct from _despawn_current_pet(), which
	# only removes the node — that one is used when replacing a pet, where
	# active_pet_id is about to be overwritten anyway. this one is for
	# genuinely putting the pet away, so it must clear the id too or the pet
	# reappears on the next scene load.
	_despawn_current_pet()
	active_pet_id = ""


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
