# tank character — defensive frontliner with placeable aura damage.
# the tank's signature mechanic: a passive AoE damage aura (firering) that
# drains mana while active. press attack to toggle on/off. when mana runs
# out the aura auto-deactivates.
#
# class identity:
# - highest HP by far (the durability king), slowest mover, heavy frontline
# - mana powers the AOE aura instead of casts
# - aura is the ONLY attack — no direct strike, just radiating damage
# - defense climbs faster than other classes via skill_proficiency (see
#   SKILL PROFICIENCY below), through actually taking damage — not a flat
#   per-level bonus. CORRECTED: this comment used to claim a flat +2
#   defense on every character level-up, but no _apply_level_up_skill_bonus()
#   override for that was ever actually in this file — the comment
#   described intended design that was never coded. removed the claim
#   rather than add the bonus now, matching the same "proficiency
#   multiplier does this job, not a flat stack" decision made for
#   warrior/mage/healer.
#
# stat curve (recompute-from-level, set in _set_stat_curve):
#   HP   260 base / +22 per level   (steepest HP — earns it by standing in fire)
#   Mana 200 base / +10 per level   (aura uptime)
#   Stam 100 base / +5  per level
#
# physics_process override:
# tank fully overrides _physics_process for its lerp-based movement (smooth
# heavy-class feel). this means regen logic AND sprint logic from player.gd
# don't run automatically — both are duplicated here. _set_active() is called
# in every "doing something" branch to keep the idle timer accurate.
#
# aura mechanics:
# - toggle on/off via attack button (spacebar)
# - drains mana_drain_cost mana every mana_drain_tick seconds
# - damages enemies in $aura collision area every aura_tick seconds
# - auto-deactivates when mana hits 0 OR tank dies
#
# XP ON HIT:
# grants Attack XP (universal — see player.gd's gain_attack_xp()) per enemy
# per aura tick, same place damage already applies in _deal_aura_damage().
# WORTH WATCHING: unlike warrior's discrete swings, mage's discrete casts,
# or healer's discrete shots, the aura is a CONTINUOUS tick (every
# aura_tick seconds, for as long as it's active) — a tank parked in a
# crowd accumulates attack XP considerably faster than the other classes'
# discrete-hit pattern. The per-hit default (5) is the same as everywhere
# else rather than a guessed-at "corrected" lower value — tune
# attack_xp_on_aura_tick down if playtesting shows it's too fast. That is a
# balance dial and nothing else: the rate here has never been changed to
# make the code cheaper, only the number of times it is written down.
extends "res://src/characters/player.gd"

# This class's stat curve. See ClassData — hp_base and friends used to be
# literals in _set_stat_curve() below, which meant the server knew your level
# and your class and still could not work out your maximum health.
const CLASS_DATA := preload("res://data/classes/tank.tres")


# =============================================================================
# AURA SETTINGS
# =============================================================================

# FOUR, NOT NINE. See mage.gd's note on damage_per_magic. 9 across a 0.25s
# tick was 36/s per enemy against the warrior's 24/s — and this number lands
# on EVERYTHING in range, so a tank in a pack of six was already dealing six
# times it. 4 gives 16/s per enemy, the 0.70x this class is aimed at, and the
# pack multiplier is what the tank is actually paid in.
@export var aura_damage: int = 4
@export var aura_tick: float = 0.25
@export var mana_drain_tick: float = 0.5
@export var mana_drain_cost: int = 2

# Attack XP per enemy per aura tick. See the class comment's XP ON HIT
# section for the tick-rate caveat.
#
# LOWERED FROM 5 TO MATCH THE OTHER CLASSES, and the old comment above it
# predicted exactly this. Warrior pays 5 attack XP per enemy per swing and
# swings about every 0.6s — 8.3 XP/sec against one target. The aura ticks four
# times a second, so 5 per tick was 20 XP/sec against one target and four times
# that in a pack of four. 2 brings a single target to 8 XP/sec, level with
# warrior, and leaves the pack bonus as the tank's genuine advantage rather
# than a multiplier on top of an already-higher rate.
@export var attack_xp_on_aura_tick: int = 2


# =============================================================================
# NODE REFERENCES
# =============================================================================
# Resolved once at _ready() instead of looked up by name every time they are
# touched. has_node("x") followed by $x walked the tree twice to answer one
# question, and tank did that on nine sites — two of them in _handle_moving()
# and _handle_idle(), which run EVERY FRAME, and one in _deal_aura_damage(),
# which runs four times a second for as long as the aura is up.
#
# get_node_or_null() rather than $x so a scene without the optional firering
# still loads; every use site checks for null exactly as the old has_node()
# guards did.
@onready var _sprite: AnimatedSprite2D = get_node_or_null("animatedsprite2d")
@onready var _aura: Area2D = get_node_or_null("aura")
@onready var _firering: AnimatedSprite2D = get_node_or_null("firering")


# =============================================================================
# AURA STATE
# =============================================================================

var aura_timer:       float = 0.0
var mana_drain_timer: float = 0.0
var aura_active: bool = false

# right-click edge detection moved to Player — see its ATTACK INPUT section.
# tank still needs its own _physics_process (it replaces the base loop rather
# than extending it), so it calls the inherited _poll_attack_pressed() below
# instead of keeping a private tracker.


# =============================================================================
# STAT CURVE
# =============================================================================

func _set_stat_curve() -> void:
	# tank: steepest HP curve in the game (frontline durability is the whole
	# kit), solid mana for aura uptime. called before recompute in player.gd.
	_apply_class_data(CLASS_DATA)


# =============================================================================
# SKILL PROFICIENCY  (NEW)
# =============================================================================

func _set_skill_proficiency() -> void:
	# tank's specialty: defense climbs 50% faster than any other class
	# taking the same damage. every class already gains SOME defense XP
	# from taking damage at all (see player.gd's take_damage(), which was
	# already universal before this system existed) — this is what keeps
	# tank true to its "durability king" identity on top of that. starting
	# value, tune to taste.
	skill_proficiency["defense"] = 1.5


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# class identity — always set, regardless of save state.
	character_name = "tank"
	speed = 160

	# super._ready() calls _set_stat_curve(), loads save, recomputes maxes
	# from level, and fills resources to full. no manual stat block needed.
	super._ready()

	# preload the aura sprite but keep it hidden until aura activates
	if _firering != null:
		_firering.play("firering")
		_firering.visible = false


func _physics_process(delta: float) -> void:
	# Sampled FIRST, before every early return below, because the edge
	# detector has to see each frame — a click held through death or an attack
	# lockout must not read as a fresh press the instant that block lifts.
	# Tank replaces the base loop rather than extending it, so it calls the
	# inherited poll explicitly; every other class gets this from super().
	var attack_pressed: bool = _poll_attack_pressed()

	# block all input/movement during death sequence so the death animation
	# can play through without being overwritten by walk/idle animations.
	if is_dying:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	_tick_aura(delta)

	# attack lockout — frozen in place while attack animation plays
	if is_attacking:
		velocity = Vector2.ZERO
		move_and_slide()
		_set_active()
		return

	# spacebar OR right-click toggles the aura — both land on attack_action(),
	# same as every other class.
	if attack_pressed:
		attack_action()
		return

	_handle_movement(delta)
	_tick_regen(delta)   # player.gd's, not a local copy


# =============================================================================
# AURA TICKING
# =============================================================================

func _tick_aura(delta: float) -> void:
	# runs every frame while the aura is active. handles both mana drain
	# and damage ticks, plus the auto-deactivate when mana hits 0.
	if not aura_active:
		return

	# active aura counts as "doing something" — reset idle timer so regen
	# doesn't kick in while the tank is actively damaging enemies
	_set_active()

	# mana drain tick
	mana_drain_timer += delta
	if mana_drain_timer >= mana_drain_tick:
		mana_drain_timer = 0.0
		mana = clamp(mana - mana_drain_cost, 0, max_mana)
		if mana <= 0:
			_deactivate_aura()
			return

	# damage tick. hasten() applies agility — read per tick rather than cached,
	# because agility can go up mid-fight on a skill-up and the aura is the one
	# attack in the game that is already running when that happens.
	aura_timer += delta
	if aura_timer >= hasten(aura_tick):
		aura_timer = 0.0
		_deal_aura_damage()


# =============================================================================
# MOVEMENT (LERP + SPRINT, DUPLICATED FROM PLAYER.GD)
# =============================================================================

func _handle_movement(delta: float) -> void:
	# WASD direction sample — same as player.gd but with lerp-based velocity
	# for the heavy-class smooth movement feel.
	var direction: Vector2 = Vector2.ZERO
	if Input.is_action_pressed("move_right"): direction.x += 1
	if Input.is_action_pressed("move_left"):  direction.x -= 1
	if Input.is_action_pressed("move_down"):  direction.y += 1
	if Input.is_action_pressed("move_up"):    direction.y -= 1

	if direction != Vector2.ZERO:
		_handle_moving(direction, delta)
	else:
		_handle_idle()

	# THE SAME WADE AS EVERY OTHER CLASS, WIRED BY HAND.
	#
	# Tank replaces player.gd's _physics_process instead of extending it, so it
	# inherits these functions but not the call to them - anything added to the
	# base loop has to be repeated here or tank silently does without it. The
	# shove this replaced was never wired here at all, and tank's mask has
	# excluded the enemies layer since well before that, so tank has been
	# walking through enemies with no weight and no latch this entire time.
	var wading: Array[CharacterBody2D] = _enemies_overlapping()
	if not wading.is_empty():
		velocity *= _wade_drag_factor(wading.size())

	move_and_slide()
	_displace_wading_enemies(wading, delta)


func _handle_moving(direction: Vector2, delta: float) -> void:
	# moving counts as activity — reset regen timer
	_set_active()

	# sprint check — duplicated from player.gd because tank overrides
	# _physics_process entirely with its lerp-based movement
	var wants_sprint: bool = Input.is_action_pressed("sprint") and stamina > 0
	_is_sprinting = wants_sprint

	# compute target velocity, then lerp toward it for smooth heavy-class feel
	var base_speed:   float = speed + (agility - 1) * 10
	var actual_speed: float = base_speed * sprint_speed_multiplier if _is_sprinting else base_speed
	velocity = velocity.lerp(direction.normalized() * actual_speed, 0.3)

	# drain stamina while sprinting (fractional accumulation, deduct whole points)
	if _is_sprinting:
		_sprint_drain_accumulator += sprint_stamina_drain_per_sec * delta
		if _sprint_drain_accumulator >= 1.0:
			var drain_amount: int = int(_sprint_drain_accumulator)
			_sprint_drain_accumulator -= drain_amount
			stamina = max(0, stamina - drain_amount)

	# animation + speed scale for sprint visual polish
	if _sprite != null:
		_sprite.play(get_walk_animation(direction))
		_sprite.speed_scale = sprint_speed_multiplier if _is_sprinting else 1.0

	last_direction = direction
	take_step()


func _handle_idle() -> void:
	# lerp velocity to zero for smooth stop (no sudden halt)
	velocity = velocity.lerp(Vector2.ZERO, 0.3)
	_is_sprinting = false
	_sprint_drain_accumulator = 0.0
	if _sprite != null:
		_sprite.play(get_idle_animation())
		_sprite.speed_scale = 1.0


# =============================================================================
# REGEN (DUPLICATED FROM PLAYER.GD)
# =============================================================================

# REGEN (REMOVED — INHERITED FROM PLAYER.GD)
# =============================================================================
# tank used to carry its own copy of _tick_regen(), from when it fully overrode
# _physics_process() and player.gd's regen therefore never ran. It called
# regen_rate and _regen_stats(), neither of which exists any more: player.gd's
# regen was rewritten to scale with each stat's maximum, because a flat rate of
# 1.0/second against a mana pool that grows by 16 a level meant a high-level
# mage waited minutes for a bar the game expected to refill in about one.
#
# Two copies of a rule is how that drift happens. There is one.


# =============================================================================
# ATTACK OVERRIDE — AURA TOGGLE
# =============================================================================

func attack_action() -> void:
	# OVERRIDE: tank's spacebar attack TOGGLES the aura on or off.
	# the tank has no direct strike — the aura IS the attack.
	if aura_active:
		_deactivate_aura()
	else:
		_activate_aura()


func _activate_aura() -> void:
	if mana <= 0:
		# show_notice() comes from player.gd, which this class extends —
		# no reference to look up, and the de-duplication there means
		# mashing the aura key with an empty bar shows one label, not forty.
		Audio.play("refused")
		show_notice("Not enough mana")
		return

	# toggling aura on counts as activity
	_set_active()

	# Below the mana guard — an aura that refused to start should not announce
	# itself. There is no matching id for switching it off; if that turns out
	# to want one, it is a new entry in audio.gd rather than a change here.
	Audio.play("aura_on")

	aura_active      = true
	aura_timer       = 0.0
	mana_drain_timer = 0.0

	if _firering != null:
		_firering.visible = true
		_firering.play("firering")


func _deactivate_aura() -> void:
	aura_active = false
	if _firering != null:
		_firering.visible = false


func _deal_aura_damage() -> void:
	# damage all enemies currently inside the $aura collision area.
	#
	# This used to also emit GameState.aura_damage_dealt on every hit,
	# described as being "for analytics / multiplayer sync." Neither existed —
	# nothing connected to that signal, and it fired once per enemy per aura
	# tick into an empty bus, which is the most expensive place in this file to
	# do nothing. The emit went first; the declaration went with the rest of
	# that bus later (see the note at the top of gamestate.gd). When multiplayer
	# is real, the signal it needs should be designed around what listens.
	if _aura == null:
		return

	# Scaled by get_damage_multiplier(), the same shared function every class's
	# damage uses (see player.gd). It was a flat aura_damage constant with no
	# scaling at all, so the tank gained attack XP from every tick while that
	# skill never affected the tank's own output. Computed once outside the
	# loop: every enemy in range takes the same number, and the multiplier is
	# not recomputed per body.
	# NEW: THE EQUIPPED MAUL, ADDED TO THE AURA RATHER THAN REPLACING IT.
	#
	# A weapon's damage is one number and an aura tick is not one kind of hit —
	# this one lands four times a second on everything in range, which is why
	# aura_damage is 9 where the warrior's swing is 24. The maul ladder is
	# scaled to that: 8 at iron rather than the 24 it was authored with, so a
	# maul adds the same PROPORTION of the tank's damage that a sword adds of
	# the warrior's. Authored flat, an ember maul would have put 120 on a tick
	# that fires four times a second and made the tank do 968 dps to the
	# warrior's 233.
	#
	# ROLLED ONCE PER TICK AND SHARED, not once per enemy. A tick is a single
	# event that happens to touch several things — the whole ring pulses with
	# one value, and rolling per body would make a crowd look like static.
	var scaled_aura_damage: int = roundi(
		(aura_damage + weapon_damage_roll()) * get_damage_multiplier())

	# ONE XP GRANT PER TICK, NOT ONE PER ENEMY.
	#
	# gain_attack_xp() ends in CharacterData.save_character_state(), which
	# looks up the HUD by group and serialises the whole inventory into fresh
	# dictionaries before handing off to the debounced save. This loop ran that
	# once per enemy, four times a second (aura_tick = 0.25), for as long as
	# the aura was up — so standing in a pack of six meant twenty-four full
	# inventory walks every second, to record one number. It is the same
	# mistake warrior.gd's _deal_melee_damage() made, in a far hotter loop:
	# warrior paid it per swing, tank paid it per tick, forever.
	#
	# The XP is identical, not merely close. The proficiency multiplier
	# truncates to an int, which is what made warrior's batched total differ
	# slightly from its per-hit one — but tank boosts "defense", not "attack",
	# so attack sits at 1.0 here and n * int(5 * 1.0) == int(5n * 1.0).
	var hits: int = 0

	for body in _aura.get_overlapping_bodies():
		if not body.is_in_group("enemies"):
			continue
		if not body.has_method("take_damage"):
			continue
		body.take_damage(scaled_aura_damage)
		hits += 1

	if hits > 0:
		gain_attack_xp(attack_xp_on_aura_tick * hits)


# =============================================================================
# ANIMATION OVERRIDES
# =============================================================================

# get_walk_animation() and get_idle_animation() used to be overridden here with
# code CHARACTER FOR CHARACTER IDENTICAL to Player's. They are deleted rather
# than converted: an override that does exactly what it overrides is a place for
# the two to drift apart, and that already happened once in this file with the
# regen loop, whose own comment read "DUPLICATED FROM PLAYER.GD".
#
# get_attack_animation below is a real override - the tank has no attack
# animation and holds its idle pose - so it stays.
func get_attack_animation(_dir: Vector2) -> String:
	# tank has no direct attack — toggling the aura doesn't play an
	# attack animation. fall back to idle so the player sprite stays
	# in a clean state if attack_action ever calls this externally.
	return get_idle_animation()


func base_attack_damage() -> int:
	# See player.gd's base_attack_damage(). The aura's per-tick damage, which
	# lands on everything in range rather than on one target.
	return aura_damage


func attack_period() -> float:
	# The aura's tick, four times a second. See player.gd's attack_period()
	# for what reads this and why it is asked of the live character.
	#
	# The dps it produces is PER ENEMY IN RANGE, not total. A tank standing in
	# a pack of six is dealing six times the number the tooltip shows, which is
	# the tank's entire point and not something one figure can say.
	# hasten() applies agility, so this is the rate actually delivered.
	return hasten(aura_tick)


func _get_dir_string() -> String:
	# The cardinal matching last_direction, for hitflash animation lookup
	# (hitflashleft / right / up / down).
	return Facing.from_vec_total(last_direction)


# =============================================================================
# DAMAGE HANDLING OVERRIDE
# =============================================================================

func take_damage(amount: int, element: int = Element.Type.NONE) -> void:
	# wraps player.take_damage with tank-specific behavior:
	# - plays a directional hitflash animation if still alive
	# - deactivates the aura if the hit killed the tank
	var was_alive: bool = hp > 0
	super.take_damage(amount, element)

	# play tank-specific hitflash ONLY if still alive after the hit.
	# without this guard, hitflash would overwrite the death animation
	# that parent's _start_death_sequence just started playing.
	if _sprite != null and hp > 0 and not is_dying:
		_sprite.play("hitflash" + _get_dir_string())

	# deactivate aura if tank just died so it doesn't keep ticking damage
	# during the death animation
	if was_alive and hp <= 0:
		_deactivate_aura()


# =============================================================================
# PHASE 2 ABILITY STUB
# =============================================================================

# TRUE while an expand is running. See the note in activate_expand().
var _expanding: bool = false


func activate_expand() -> void:
	# 4-second sprite scale-up. costs 25 mana.
	#
	# NOTHING CALLS THIS YET - it is the Phase 2 stub. The two guards below are
	# here anyway, because the bug they prevent is invisible while the function
	# is unreachable and lands on whoever wires it up.
	#
	# FOUR SECONDS IS A LONG AWAIT ON A TANK. This is the class built to stand
	# in damage, so dying during the hold is the expected case, not the edge
	# one - and a death takes the scene with it. There is nothing in the log
	# when that happens: a coroutine whose node is gone is dropped silently, not
	# with an error. combat.gd has the measured table.
	#
	# Death is the harmless version, because the node and its 1.5 scale go
	# together. The case to actually think about when wiring this up is the one
	# the guard catches - alive, out of the tree - because the guard returns
	# BEFORE `_expanding = false`. Come back into the tree and the flag is still
	# true, so the `if _expanding: return` at the top rejects every future press
	# and the sprite stays at 1.5 forever. Whoever calls this first should decide
	# whether the restore belongs in a deferred/`tree_exiting` path instead; it
	# is left as-is rather than guessed at, since nothing calls it yet.
	#
	# AND IT MUST NOT OVERLAP ITSELF. Two presses inside four seconds used to
	# start two timers; the first to fire shrank the sprite while the second
	# hold was still paid for and supposedly running. The player loses the
	# ability they just spent 25 mana on.
	if _expanding:
		return
	if mana >= 25:
		_expanding = true
		mana = clamp(mana - 25, 0, max_mana)
		# RESTORE WHAT WAS THERE, NOT WHAT SOMEBODY ASSUMED WAS THERE.
		#
		# The shrink below used to write Vector2(1.0, 1.0) to both. The scene had
		# the root at 0.9 and the fire ring at 1.625 x 1.597, so the first expand
		# would have left the tank permanently resized and the ring a third
		# smaller - invisible only because nothing calls this yet.
		#
		# The root is 1.0 in the scene now (the 0.9 made the sprite ripple while
		# walking - see the commit that changed tank.tscn), which happens to make
		# the old root line right. The ring's would still have been wrong, and the
		# next person to tune either value in the editor would break it again.
		# Captured here, so neither number is written down twice.
		var root_scale_before: Vector2 = scale
		var ring_scale_before: Vector2 = _firering.scale if _firering != null else Vector2.ONE
		scale = Vector2(1.5, 1.5)
		if _firering != null:
			_firering.scale = Vector2(1.5, 1.5)
		await get_tree().create_timer(4.0).timeout
		# PAST AN AWAIT - same guard and same reason as fishingspot.gd and
		# characterhud.gd. Nothing below is safe on a node that has been freed.
		if not is_instance_valid(self) or not is_inside_tree():
			return
		_expanding = false
		scale = root_scale_before
		# is_instance_valid rather than a null check, uniquely here: this is the
		# far side of a four-second await, and a cached reference to a freed
		# node is non-null while has_node() would have returned false.
		if is_instance_valid(_firering):
			_firering.scale = ring_scale_before
