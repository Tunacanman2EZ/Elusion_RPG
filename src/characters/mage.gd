# - high stamina growth — kiting survival fuel, not flee
# - 1 ability: stalagmite drop, drops at cursor for AOE damage
#
# stat curve (recompute-from-level, set in _set_stat_curve):
#   HP   110 base / +5  per level   (squishy floor)
#   Mana 250 base / +16 per level   (deepest pool — mana IS the power budget)
#   Stam  40 base / +7  per level   (kite survival)
#
# animation flow:
# - mage plays directional cast animation (attackdown/up/left/right) with
#   6 frames each. frame 3 is the visual peak (staff orb glowing).
# - spell scene plays its own 8-frame "fall" animation independently in the
#   world at cursor position. damages on frame 4 (impact).
# - both animations run in parallel and complete independently.
#
# kite-while-casting:
# mage does NOT set is_attacking = true when casting. this lets the player
# move while spell drops at cursor — essential for ranged class survival.
# the spell spawns immediately on call, so even if walk animation overrides
# the cast animation visually, the stalagmite still drops correctly.
#
# input model:
# - spacebar (attack action) → parent calls attack_action() → delegates to cast
# - right-click polled in _physics_process (UI can absorb InputEvent otherwise)
extends "res://src/characters/player.gd"


# =============================================================================
# EXPORTED SETTINGS
# =============================================================================

# the stalagmite spell scene — assigned in the inspector on mage.tscn
@export var target_circle_scene: PackedScene

# mana drained per stalagmite cast
@export var spell_mana_cost: int = 15

# cooldown between casts (seconds). prevents spell spam beyond animation duration.
@export var spell_cooldown: float = 0.45

# damage scales with magic skill: total = magic × damage_per_magic
@export var damage_per_magic: int = 25


# =============================================================================
# STATE
# =============================================================================

# true while a spell cast is in flight (within cooldown window).
# independent from parent's is_attacking — blocks new casts until cooldown ends.
var is_casting: bool = false

# tracks right-click press state for edge detection so each click casts once
# instead of every frame held.
var _right_click_was_held: bool = false


# =============================================================================
# STAT CURVE
# =============================================================================

func _set_stat_curve() -> void:
	# mage: lowest HP (squishy), deepest mana pool (spell spam is its whole
	# kit), high stamina for kiting. called before recompute in player.gd.
	hp_base    = 110; hp_per_lvl   = 5
	mana_base  = 250; mana_per_lvl = 16
	stam_base  = 40;  stam_per_lvl = 7


# =============================================================================
# SKILL PROFICIENCY  (NEW)
# =============================================================================

func _set_skill_proficiency() -> void:
	# mage's specialty: magic climbs 50% faster than any other class
	# landing the same spell hits. attack XP is still gained from stalagmite
	# hits too (universal now — see player.gd's gain_attack_xp()), just at
	# the base 1.0 rate, unlike warrior's boosted melee. starting value,
	# tune to taste.
	skill_proficiency["magic"] = 1.5


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# class identity — always set, regardless of save state.
	character_name = "mage"
	speed = 165

	# super._ready() calls _set_stat_curve(), loads save, recomputes maxes
	# from level, and fills resources to full. no manual stat block needed.
	super._ready()


func _physics_process(delta: float) -> void:
	# parent handles movement (WASD), spacebar attack dispatch, animation
	# switching, universal regen, and universal sprint. we layer right-click
	# casting on top.
	super._physics_process(delta)

	# always update the held tracker even while blocked, so we don't false-
	# trigger when the block lifts mid-hold (e.g. right-click held through
	# a cast cooldown then released — should NOT trigger another cast)
	var right_held_now: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)

	# block right-click cast during death OR during active cooldown.
	# we DO allow casting while moving — that's the kite-while-casting design.
	if is_casting or is_dying:
		_right_click_was_held = right_held_now
		return

	# press-edge detection: fires once on press, not every frame held
	if right_held_now and not _right_click_was_held:
		_cast_stalagmite_drop()

	_right_click_was_held = right_held_now


# =============================================================================
# ATTACK ACTION OVERRIDE
# =============================================================================

func attack_action() -> void:
	# OVERRIDE: mage's spacebar attack IS the stalagmite drop spell.
	# parent's _physics_process calls this when player presses attack action.
	# we delegate to the cast function so the spell fires from either input.
	_cast_stalagmite_drop()


# =============================================================================
# STALAGMITE CAST
# =============================================================================

func _cast_stalagmite_drop() -> void:
	# core cast function. called from attack_action (spacebar) AND from
	# _physics_process (right-click). validates state, deducts mana, plays
	# animation, spawns spell at cursor, then starts the cooldown.

	# guards: already casting, not enough mana, missing scene reference
	if is_casting:
		return
	if mana < spell_mana_cost:
		print("Mage: not enough mana (%d/%d)" % [mana, spell_mana_cost])
		return
	if target_circle_scene == null:
		push_warning("Mage: target_circle_scene not assigned in inspector")
		return

	# casting counts as activity — reset regen timer
	_set_active()

	# deduct mana and lock casting state.
	# NOTE: we do NOT set is_attacking = true. mage can move while casting.
	# walk animation overrides cast animation visually if the player moves,
	# but the spell still fires correctly because spawn is immediate.
	mana -= spell_mana_cost
	is_casting = true
	print("Mage: casting stalagmite (mana now %d)" % mana)

	_play_cast_animation()
	_spawn_stalagmite()

	# cooldown unlocks casting after spell_cooldown seconds. this is the
	# only way is_casting clears — no animation_finished hook needed since
	# we don't gate on is_attacking.
	await get_tree().create_timer(spell_cooldown).timeout
	is_casting = false


func _play_cast_animation() -> void:
	# play directional cast animation matching last_direction.
	# walk animation will override visually if the player moves during the
	# cast — acceptable tradeoff for kite-while-casting gameplay.
	if not has_node("animatedsprite2d"):
		return

	var sprite: AnimatedSprite2D = $animatedsprite2d
	var cast_anim: String = "attack" + _direction_to_string(last_direction)
	if sprite.sprite_frames.has_animation(cast_anim):
		sprite.play(cast_anim)
	else:
		print("Mage: no animation named '%s'" % cast_anim)


func _spawn_stalagmite() -> void:
	# spawn the spell scene at cursor position. parented to the scene ROOT
	# (not to mage) so the spell stays at cursor location if mage moves
	# during the fall animation. spell.tscn plays its own 8-frame fall
	# animation and damages on impact frame (frame 4).
	var spell = target_circle_scene.instantiate()
	get_tree().current_scene.add_child(spell)
	spell.global_position = get_global_mouse_position()
	# CHANGED: was magic * damage_per_magic — magic-only, and damage_per_magic
	# was acting as a "per point" multiplier rather than a flat base. now
	# damage_per_magic is a flat base damage value, scaled by
	# get_damage_multiplier() — the same shared function every class's
	# damage uses (see player.gd), which already folds magic in, plus
	# attack too. same export, same default (25), reinterpreted role.
	spell.explosion_damage = int(damage_per_magic * get_damage_multiplier())
	# NEW: identifies the mage for spelltargetcircle.gd's XP-on-hit — same
	# pattern as slashwave.gd's caster reference for warrior. this is what
	# lets the spell grant attack XP (universal) AND magic XP (mage's
	# boosted specialty) back to whoever cast it, on impact. the spell
	# script itself still needs its own matching XP-grant call added —
	# that part isn't done here, since it lives in target_circle_scene's
	# script, not this one.
	if "caster" in spell:
		spell.caster = self


# =============================================================================
# LEVEL-UP SKILL BONUS  (REMOVED)
# =============================================================================
# CHANGED: used to grant a flat +1 magic / +1 agility on every character
# level-up. now that skill_proficiency exists (see _set_skill_proficiency()
# above), magic climbs faster for mage through actual spell casts, not
# just from leveling up via ANY combat. no override needed anymore; falls
# back to player.gd's no-op base.


# =============================================================================
# HELPERS
# =============================================================================

func _direction_to_string(dir: Vector2) -> String:
	# snap a Vector2 to one of 4 cardinals for animation name lookup.
	# matches the convention used by warrior/tank in player.gd.
	if abs(dir.x) > abs(dir.y):
		return "right" if dir.x > 0 else "left"
	else:
		return "down" if dir.y > 0 else "up"
