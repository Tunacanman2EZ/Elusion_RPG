# mage character — glass-cannon caster that drops AOE damage at the cursor.
#
# THIS COMMENT USED TO START MID-SENTENCE. The opening lines were lost at some
# point and the file began "# - high stamina growth", a bullet belonging to a
# list whose heading no longer existed. Nothing breaks when a header goes
# missing, which is why it stayed missing.
#
# class identity:
# - lowest HP in the game (squishy floor) and the deepest mana pool
# - high stamina growth — kiting survival fuel, not flee
# - 1 ability: stalagmite drop, drops at cursor for AOE damage
# - magic skill climbs 50% faster than for any other class (see
#   _set_skill_proficiency)
#
# THE STAT CURVE IS NOT WRITTEN DOWN HERE ON PURPOSE. It lives in
# data/classes/mage.tres and nowhere else. It used to be listed here too, which
# is a second copy nobody can check against the first — the moment the .tres is
# retuned the comment is a lie that reads like documentation. CLASS_DATA below
# is the one source.
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
# - spacebar OR right-click → player.gd's _poll_attack_pressed() → this class's
#   attack_action() → the cast. mage used to poll right-click privately; that
#   copy is gone, because attack_action() IS the cast and the shared path lands
#   on exactly the spell the private poll was reaching for.
extends "res://src/characters/player.gd"

# This class's stat curve. See ClassData — hp_base and friends used to be
# literals in _set_stat_curve() below, which meant the server knew your level
# and your class and still could not work out your maximum health.
const CLASS_DATA := preload("res://data/classes/mage.tres")


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

# right-click edge detection moved to Player — see its ATTACK INPUT section.
# mage doesn't need a private copy: attack_action() below already IS the
# stalagmite cast, so the shared right-click path lands on exactly the spell
# this class used to poll for itself.


# =============================================================================
# STAT CURVE
# =============================================================================

func _set_stat_curve() -> void:
	# mage: lowest HP (squishy), deepest mana pool (spell spam is its whole
	# kit), high stamina for kiting. called before recompute in player.gd.
	_apply_class_data(CLASS_DATA)


# =============================================================================
# SKILL PROFICIENCY
# =============================================================================

func _set_skill_proficiency() -> void:
	# mage's specialty: magic climbs 50% faster than any other class
	# landing the same spell hits. attack XP is still gained from stalagmite
	# hits too (universal now — see player.gd's gain_attack_xp()), just at
	# the base 1.0 rate, unlike warrior's boosted melee. starting value,
	# tune to taste.
	#
	# This replaced a flat +1 magic / +1 agility granted on every character
	# level-up, which paid out however the level was earned — a mage who
	# levelled on fishing XP got spell power for it. This only pays for casting.
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
	# parent handles movement (WASD), attack dispatch from BOTH spacebar and
	# right-click, animation switching, universal regen, and universal sprint.
	# both inputs land on attack_action(), which is the stalagmite cast, so
	# mage adds nothing to the input path any more.
	#
	# the is_casting cooldown that used to be checked here is still enforced —
	# _cast_stalagmite_drop() guards on it itself, which is what made this
	# second check redundant.
	super._physics_process(delta)


# =============================================================================
# ATTACK ACTION OVERRIDE
# =============================================================================

func base_attack_damage() -> int:
	# See player.gd's base_attack_damage().
	return damage_per_magic


func attack_period() -> float:
	# One stalagmite per cooldown. See player.gd's attack_period() for what
	# reads this and why it is asked of the live character rather than looked
	# up in a table. The dps it gives is single-target; the stalagmite is an
	# explosion, so a crowded cast is worth more than the number shown.
	return spell_cooldown


func attack_action() -> void:
	# OVERRIDE: mage's spacebar attack IS the stalagmite drop spell.
	# parent's _physics_process calls this when player presses attack action.
	# we delegate to the cast function so the spell fires from either input.
	_cast_stalagmite_drop()


# =============================================================================
# STALAGMITE CAST
# =============================================================================

func _cast_stalagmite_drop() -> void:
	# The cast. Reached from attack_action(), which both spacebar and
	# right-click dispatch to. Validates state, deducts mana, plays the
	# animation, spawns the spell at the cursor, then holds the cooldown.

	# guards: already casting, not enough mana, missing scene reference
	if is_casting:
		return
	if mana < spell_mana_cost:
		# THE ONE THAT MOST NEEDED THE COOLDOWN IN show_notice(). Attack is
		# held down, not tapped, so an out-of-mana mage runs this branch on
		# every input poll — without de-duplication it would bury the screen
		# in labels for as long as the button was down.
		Audio.play("refused")
		show_notice("Not enough mana")
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

	# Below every guard, so a cast refused for mana or a missing scene stays
	# silent. show_notice() already tells the player why.
	Audio.play("spell_cast")
	if OS.is_debug_build():
		print("[MAGE] casting stalagmite (mana now %d)" % mana)

	_play_cast_animation()
	_spawn_stalagmite()

	# Cooldown unlocks casting after spell_cooldown seconds. This is the ONLY
	# way is_casting clears — there is no animation_finished hook, because the
	# cast deliberately doesn't gate on is_attacking.
	#
	# WHICH MAKES THE GUARD BELOW LOAD-BEARING, not defensive decoration. The
	# line after the await writes a member of `self`, and a mage who dies or
	# leaves the scene inside those 0.45 seconds is freed while this timer keeps
	# running. Same await hazard, same guard, as warrior's attack lock and
	# tank's activate_expand.
	await get_tree().create_timer(spell_cooldown).timeout
	if not is_instance_valid(self) or not is_inside_tree():
		return
	is_casting = false


func _play_cast_animation() -> void:
	# play directional cast animation matching last_direction.
	# walk animation will override visually if the player moves during the
	# cast — acceptable tradeoff for kite-while-casting gameplay.
	# get_node_or_null() rather than has_node() then $node, which walked the
	# same path twice to answer one question. sprite_frames is checked too:
	# has_animation() on a null SpriteFrames is a crash, not a false.
	var sprite: AnimatedSprite2D = get_node_or_null("animatedsprite2d")
	if sprite == null or sprite.sprite_frames == null:
		return

	var cast_anim: String = "attack" + _direction_to_string(last_direction)
	if sprite.sprite_frames.has_animation(cast_anim):
		sprite.play(cast_anim)
	else:
		# a missing animation is a scene defect, not a runtime condition —
		# the cast still fires, it just plays nothing, which looks like the
		# spell failed. push_warning so it is not lost in the boot chatter.
		push_warning("Mage: animatedsprite2d has no animation named '%s'" % cast_anim)


func _spawn_stalagmite() -> void:
	# spawn the spell scene at cursor position. parented to the scene ROOT
	# (not to mage) so the spell stays at cursor location if mage moves
	# during the fall animation. spell.tscn plays its own 8-frame fall
	# animation and damages on impact frame (frame 4).
	var spell: Node = target_circle_scene.instantiate()
	get_tree().current_scene.add_child(spell)
	spell.global_position = get_global_mouse_position()

	# The target circle used to SLIDE into place instead of appearing at the
	# cursor.
	#
	# This project runs physics_interpolation, so the renderer draws every node
	# blended between its previous and current physics transforms. A node that
	# has just entered the tree has no meaningful previous transform, so its
	# first rendered frame is a blend from wherever it was born toward where we
	# just put it — visible as a short slide across the screen.
	#
	# reset_physics_interpolation() collapses previous and current to the same
	# value, leaving nothing to blend. It MUST come AFTER global_position is
	# set, never before.
	#
	# WHY IT ONLY SHOWED UP WHEN IT DID: the slide lasts exactly one physics
	# tick. At 180 ticks/second that was 5.6ms and invisible. At 80 it is
	# 12.5ms, and 12.5ms of movement is something an eye catches.
	spell.reset_physics_interpolation()
	# damage_per_magic is a flat base damage value scaled by
	# get_damage_multiplier(), the shared function every class's damage uses
	# (see player.gd), which folds in magic AND attack. It was magic *
	# damage_per_magic — magic-only, with damage_per_magic acting as a "per
	# point" multiplier. Same export, same default (25), reinterpreted role.
	# Guarded the same way `caster` is, two lines down. Assigning a property a
	# scene may not have is a hard error, and the two assignments had no reason
	# to disagree about how careful to be.
	#
	# NEW: THE EQUIPPED STAFF, ADDED RATHER THAN SUBSTITUTED — the same rule
	# all four classes now share; see player.gd's weapon_damage_roll(). Rolled
	# once per cast, so a stalagmite that lands well hits harder than one that
	# does not, and every enemy caught in the same explosion takes the same
	# number. roundi rather than int, because truncating toward zero cost a
	# fraction of a point on every single cast.
	if "explosion_damage" in spell:
		spell.explosion_damage = roundi(
			(damage_per_magic + weapon_damage_roll()) * get_damage_multiplier())
	# Identifies the mage for spelltargetcircle.gd's XP-on-hit — same
	# pattern as slashwave.gd's caster reference for warrior. this is what
	# lets the spell grant attack XP (universal) AND magic XP (mage's
	# boosted specialty) back to whoever cast it, on impact. the spell
	# script itself still needs its own matching XP-grant call added —
	# that part isn't done here, since it lives in target_circle_scene's
	# script, not this one.
	if "caster" in spell:
		spell.caster = self


# =============================================================================
# HELPERS
# =============================================================================

func _direction_to_string(dir: Vector2) -> String:
	# Snap a Vector2 to one of four cardinals for animation name lookup. The same
	# rule every other class uses - see Facing.
	return Facing.from_vec_total(dir)
