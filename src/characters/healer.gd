# healer character — ranged spell spammer using mana as the cost resource.
# holds spacebar OR right-click to continuously fire projectiles toward cursor.
# each shot drains mana. stamina is reserved for the universal sprint system
# (shared across all classes via player.gd).
#
# class identity:
# - moderate HP (medium fragility), highest mana growth per level
# - mana = spell ammo (one shot per mana point at base cost)
# - cursor-aim projectile spam (10 shots/sec at base cooldown)
# - support archetype — fragile but sustained DPS through volume
#
# THE STAT CURVE IS NOT WRITTEN DOWN HERE ON PURPOSE. It lives in
# data/classes/healer.tres and nowhere else. It used to be listed here too,
# which is a second copy nobody can check against the first — the moment the
# .tres is retuned the comment is a lie that reads like documentation.
# CLASS_DATA below is the one source.
#
# combat model:
# - hold spacebar OR right-click to fire continuously
# - each shot fires toward CURRENT cursor position
# - moving the mouse during a burst creates a spray pattern (player skill)
# - projectile sprite is tinted via modulate (green by default) — set to
#   Color.WHITE in inspector once final attack art is delivered
#
# input model:
# - spacebar held: triggers fire on cooldown
# - right-click held: same as spacebar (alternative for mouse-focused play)
# - both polled in _physics_process so UI events can't absorb them
# - attack_action() is overridden to NO-OP so spacebar press doesn't trigger
#   the parent's single-shot attack animation interrupting held-fire
extends "res://src/characters/player.gd"

# This class's stat curve. See ClassData — hp_base and friends used to be
# literals in _set_stat_curve() below, which meant the server knew your level
# and your class and still could not work out your maximum health.
const CLASS_DATA := preload("res://data/classes/healer.tres")


# =============================================================================
# EXPORTED SETTINGS
# =============================================================================

@export var projectile_scene: PackedScene
@export var mana_cost_per_shot: int = 1
@export var shot_cooldown: float = 0.1
# TWO, NOT THREE. See mage.gd's note on damage_per_magic for the arithmetic:
# base over attack period is the dps floor, and 3 across a 0.1s cooldown was
# 30/s against the warrior's 24/s — a ranged class beating a melee one before
# either picked up a weapon. 2 gives 20/s, which is the 0.80x this class is
# aimed at. One point of base damage is a big proportional step at ten shots
# a second, which is why this line is 2 and not 2.4.
@export var damage_per_magic: int = 2
@export var projectile_speed: float = 200.0
@export var projectile_tint: Color = Color(0.3, 1.0, 0.4, 1.0)


# A cursor delta shorter than this counts as "no direction at all" — see
# _get_direction_to_cursor(). Compared against length_squared() so the check
# costs no sqrt on a path that runs ten times a second: this is 0.001 squared,
# the same threshold warrior uses for the same question.
const AIM_EPSILON_SQUARED: float = 0.000001


# =============================================================================
# STATE
# =============================================================================

var _shot_timer: float = 0.0

# _is_firing USED TO LIVE HERE. It was assigned true on every shot and false on
# every frame between shots, and read by absolutely nothing — not by this file,
# not by player.gd, not by the HUD. Deleted rather than left as a hook for a
# future feature: a variable that is maintained but never consulted looks
# exactly like one that is load-bearing, right up until someone deletes the
# wrong one.


# =============================================================================
# STAT CURVE
# =============================================================================

func _set_stat_curve() -> void:
	# healer: fragile but above the mage's floor, deep mana for sustained
	# projectile spam. called before recompute in player.gd.
	_apply_class_data(CLASS_DATA)


# =============================================================================
# SKILL PROFICIENCY
# =============================================================================

func _set_skill_proficiency() -> void:
	# healer's specialty: magic climbs 50% faster than any other class
	# landing the same shots. attack XP is still gained from projectile
	# hits too (universal now — see player.gd's gain_attack_xp()), just at
	# the base 1.0 rate. starting value, tune to taste.
	#
	# This replaced a flat +1 magic granted on every character level-up, which
	# paid out however the level was earned. This only pays for landed shots.
	skill_proficiency["magic"] = 1.5


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# class identity — always set, regardless of save state.
	character_name = "healer"
	speed = 140

	# super._ready() calls _set_stat_curve(), loads save, recomputes maxes
	# from level, and fills resources to full. no manual stat block needed.
	super._ready()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)

	if is_dying:
		return

	if _shot_timer > 0.0:
		_shot_timer -= delta

	if _can_fire():
		_fire_projectile()
		# hasten() applies agility. At ten shots a second the base cooldown is
		# already 0.1, so this is the class where the multiplier does the most
		# in absolute terms — and the one where forgetting it would be least
		# visible, because a shot every 0.05s and one every 0.1s both read as
		# "a stream".
		_shot_timer = hasten(shot_cooldown)


# =============================================================================
# FIRE GATING
# =============================================================================

func _can_fire() -> bool:
	if not _is_attack_input_held():
		return false
	if _shot_timer > 0.0:
		return false
	if mana < mana_cost_per_shot:
		return false
	return true


func _is_attack_input_held() -> bool:
	# healer fires continuously while the input is HELD, so this stays a hold
	# check rather than the edge-detected _poll_attack_pressed() every other
	# class uses. right_click_attack_held() is the shared version of the mouse
	# half, and it is what stops a right-click the inventory already consumed
	# from reading as "player is holding attack" and draining their mana.
	return Input.is_action_pressed("attack") or right_click_attack_held()


# =============================================================================
# ATTACK ACTION OVERRIDE
# =============================================================================

func base_attack_damage() -> int:
	# See player.gd's base_attack_damage(). Three, which is small because this
	# fires ten times a second — the number only means anything next to
	# attack_period() below.
	return damage_per_magic


func attack_period() -> float:
	# Ten shots a second. See player.gd's attack_period() for what reads this.
	#
	# This is the class the whole dps row exists for: a scepter's damage number
	# is tiny — 3 at iron, 13 at ember — precisely BECAUSE of this 0.1, and a
	# player comparing it to a 100-damage sword without the division would
	# reasonably conclude the healer had been abandoned.
	# hasten() applies agility, so this is the rate actually delivered.
	return hasten(shot_cooldown)


func attack_action() -> void:
	return


# =============================================================================
# PROJECTILE FIRING
# =============================================================================

func _fire_projectile() -> void:
	if projectile_scene == null:
		push_warning("Healer: projectile_scene not assigned in inspector")
		return

	_set_active()

	# The healer's attack IS the projectile, so this is the cast rather than a
	# swing. Below the projectile_scene guard above, which returns on a
	# misconfigured inspector.
	Audio.play("spell_cast")

	mana -= mana_cost_per_shot

	var direction: Vector2 = _get_direction_to_cursor()
	last_direction = direction

	_play_cast_animation(direction)
	_spawn_projectile(direction)


func _get_direction_to_cursor() -> Vector2:
	# ALWAYS A REAL DIRECTION. Vector2.normalized() on a zero-length vector
	# returns Vector2.ZERO, not an error — and the cursor sitting exactly on the
	# character makes it zero-length.
	#
	# That fed two things at once. last_direction went to ZERO, which is what
	# every idle and walk animation lookup reads, and the projectile was handed
	# direction = ZERO, so it spawned and then sat perfectly still until its
	# lifetime ran out. At ten shots a second that is a growing pile of
	# motionless orbs on top of the player. Falling back to the last real facing
	# fires the shot the way the player is already looking, which is the only
	# answer that isn't a guess.
	var to_cursor: Vector2 = get_global_mouse_position() - global_position
	if to_cursor.length_squared() <= AIM_EPSILON_SQUARED:
		return last_direction
	return to_cursor.normalized()


func _play_cast_animation(direction: Vector2) -> void:
	# get_node_or_null() rather than has_node() then $node, which walked the
	# same path twice to answer one question. sprite_frames is checked too:
	# has_animation() on a null SpriteFrames is a crash, not a false.
	var sprite: AnimatedSprite2D = get_node_or_null("animatedsprite2d")
	if sprite == null or sprite.sprite_frames == null:
		return

	var anim_name: String = "attack" + _direction_to_string(direction)
	if sprite.sprite_frames.has_animation(anim_name):
		sprite.play(anim_name)


func _spawn_projectile(direction: Vector2) -> void:
	var projectile: Node = projectile_scene.instantiate()
	get_tree().current_scene.add_child(projectile)

	projectile.global_position = global_position

	# THE ONLY SPAWNER IN THE PROJECT THAT WAS MISSING THIS. mage.gd, warrior.gd,
	# pet.gd, petcontroller.gd, baseenemy.gd, bossenemy.gd, bushmage.gd,
	# poisonslime.gd, poisonprojectile.gd, combat.gd and teleporter.gd all call
	# it; healer.gd did not.
	#
	# The project runs common/physics_interpolation, so the renderer draws every
	# node blended between its previous and current physics transforms. A node
	# that has just entered the tree has no meaningful previous transform, so its
	# first rendered frame is a blend from the scene origin toward wherever it
	# was just placed — the shot visibly smears in from off-screen instead of
	# leaving the staff. mage.gd's _spawn_stalagmite() has the long-form version
	# of this explanation.
	#
	# It MUST come after global_position is set, never before.
	projectile.reset_physics_interpolation()

	projectile.modulate = projectile_tint

	if "direction" in projectile:
		projectile.direction = direction
	if "speed" in projectile:
		projectile.speed = projectile_speed
	if "damage" in projectile:
		# damage_per_magic is a flat base scaled by get_damage_multiplier(),
		# which folds in both magic and attack and is shared across every class
		# (see player.gd). It was magic * damage_per_magic — the same
		# reinterpretation mage's stalagmite went through.
		#
		# NEW: THE EQUIPPED SCEPTER, ADDED RATHER THAN SUBSTITUTED. The scepter
		# ladder is small on purpose — 3 at iron, 13 at ember — because this
		# fires ten times a second. A scepter carrying the sword's 20 would
		# have given the healer 170 dps at tier 1 and 1,370 at ember, against a
		# warrior's 233. It adds the same PROPORTION of the healer's own damage
		# that a sword adds of the warrior's; the dps it buys is identical.
		#
		# roundi rather than int matters most here. A base of 3 truncated at a
		# 1.16 multiplier is still 3 — the healer was the class paying most for
		# a rounding mode nobody chose.
		projectile.damage = roundi(
			(damage_per_magic + weapon_damage_roll()) * get_damage_multiplier())
	if "owner_group" in projectile:
		projectile.owner_group = "player"
	# Identifies the healer for the projectile's XP-on-hit — same
	# pattern as slashwave.gd's caster reference for warrior, and mage's
	# equivalent addition to _spawn_stalagmite(). lets the projectile grant
	# attack XP (universal) AND magic XP (healer's boosted specialty) back
	# to whoever fired it, on impact. the projectile script itself still
	# needs its own matching XP-grant call added — that part isn't done
	# here, since it lives in projectile_scene's own script, not this one.
	if "caster" in projectile:
		projectile.caster = self


# =============================================================================
# HELPERS
# =============================================================================

func _direction_to_string(dir: Vector2) -> String:
	return Facing.from_vec_total(dir)
