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
# stat curve (recompute-from-level, set in _set_stat_curve):
#   HP   140 base / +7  per level   (above mage, below frontliners)
#   Mana 220 base / +14 per level   (deep pool for sustained spam)
#   Stam  60 base / +6  per level
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


# =============================================================================
# EXPORTED SETTINGS
# =============================================================================

@export var projectile_scene: PackedScene
@export var mana_cost_per_shot: int = 1
@export var shot_cooldown: float = 0.1
@export var damage_per_magic: int = 8
@export var projectile_speed: float = 200.0
@export var projectile_tint: Color = Color(0.3, 1.0, 0.4, 1.0)


# =============================================================================
# STATE
# =============================================================================

var _shot_timer: float = 0.0
var _is_firing: bool = false


# =============================================================================
# STAT CURVE
# =============================================================================

func _set_stat_curve() -> void:
	# healer: fragile but above the mage's floor, deep mana for sustained
	# projectile spam. called before recompute in player.gd.
	hp_base    = 140; hp_per_lvl   = 7
	mana_base  = 220; mana_per_lvl = 14
	stam_base  = 60;  stam_per_lvl = 6


# =============================================================================
# SKILL PROFICIENCY  (NEW)
# =============================================================================

func _set_skill_proficiency() -> void:
	# healer's specialty: magic climbs 50% faster than any other class
	# landing the same shots. attack XP is still gained from projectile
	# hits too (universal now — see player.gd's gain_attack_xp()), just at
	# the base 1.0 rate. starting value, tune to taste.
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
		_shot_timer = shot_cooldown
		_is_firing = true
	else:
		_is_firing = false


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
	return Input.is_action_pressed("attack") \
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)


# =============================================================================
# ATTACK ACTION OVERRIDE
# =============================================================================

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
	mana -= mana_cost_per_shot

	var direction: Vector2 = _get_direction_to_cursor()
	last_direction = direction

	_play_cast_animation(direction)
	_spawn_projectile(direction)


func _get_direction_to_cursor() -> Vector2:
	var mouse_pos: Vector2 = get_global_mouse_position()
	return (mouse_pos - global_position).normalized()


func _play_cast_animation(direction: Vector2) -> void:
	if not has_node("animatedsprite2d"):
		return

	var sprite: AnimatedSprite2D = $animatedsprite2d
	var anim_name: String = "attack" + _direction_to_string(direction)
	if sprite.sprite_frames.has_animation(anim_name):
		sprite.play(anim_name)


func _spawn_projectile(direction: Vector2) -> void:
	var projectile: Node = projectile_scene.instantiate()
	get_tree().current_scene.add_child(projectile)

	projectile.global_position = global_position
	projectile.modulate = projectile_tint

	if "direction" in projectile:
		projectile.direction = direction
	if "speed" in projectile:
		projectile.speed = projectile_speed
	if "damage" in projectile:
		# CHANGED: was magic * damage_per_magic — same reinterpretation as
		# mage's stalagmite: damage_per_magic is now a flat base, scaled by
		# get_damage_multiplier() (folds in both magic and attack, shared
		# across every class — see player.gd).
		projectile.damage = int(damage_per_magic * get_damage_multiplier())
	if "owner_group" in projectile:
		projectile.owner_group = "player"
	# NEW: identifies the healer for the projectile's XP-on-hit — same
	# pattern as slashwave.gd's caster reference for warrior, and mage's
	# equivalent addition to _spawn_stalagmite(). lets the projectile grant
	# attack XP (universal) AND magic XP (healer's boosted specialty) back
	# to whoever fired it, on impact. the projectile script itself still
	# needs its own matching XP-grant call added — that part isn't done
	# here, since it lives in projectile_scene's own script, not this one.
	if "caster" in projectile:
		projectile.caster = self


# =============================================================================
# LEVEL-UP SKILL BONUS  (REMOVED)
# =============================================================================
# CHANGED: used to grant a flat +1 magic on every character level-up. now
# that skill_proficiency exists (see _set_skill_proficiency() above),
# magic climbs faster for healer through actual landed shots, not just
# from leveling up via ANY combat. no override needed anymore; falls back
# to player.gd's no-op base.


# =============================================================================
# HELPERS
# =============================================================================

func _direction_to_string(dir: Vector2) -> String:
	if abs(dir.x) > abs(dir.y):
		return "right" if dir.x > 0 else "left"
	else:
		return "down" if dir.y > 0 else "up"
