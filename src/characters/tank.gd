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
# XP ON HIT (NEW):
# grants Attack XP (universal — see player.gd's gain_attack_xp()) per enemy
# per aura tick, same place damage already applies in _deal_aura_damage().
# WORTH WATCHING: unlike warrior's discrete swings, mage's discrete casts,
# or healer's discrete shots, the aura is a CONTINUOUS tick (every
# aura_tick seconds, for as long as it's active) — a tank parked in a
# crowd could accumulate attack XP considerably faster than the other
# classes' discrete-hit pattern. kept the same per-hit default (5) as
# everywhere else rather than guess at a "corrected" lower value — tune
# attack_xp_on_aura_tick down if playtesting shows it's too fast.
extends "res://src/characters/player.gd"

# This class's stat curve. See ClassData — hp_base and friends used to be
# literals in _set_stat_curve() below, which meant the server knew your level
# and your class and still could not work out your maximum health.
const CLASS_DATA := preload("res://data/classes/tank.tres")


# =============================================================================
# AURA SETTINGS
# =============================================================================

@export var aura_damage: int = 4
@export var aura_tick: float = 0.25
@export var mana_drain_tick: float = 0.5
@export var mana_drain_cost: int = 2

# NEW: see class comment's XP ON HIT section for the tick-rate caveat.
@export var attack_xp_on_aura_tick: int = 5


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
	if has_node("firering"):
		$firering.play("firering")
		$firering.visible = false


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

	# damage tick
	aura_timer += delta
	if aura_timer >= aura_tick:
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

	move_and_slide()


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
	if has_node("animatedsprite2d"):
		$animatedsprite2d.play(get_walk_animation(direction))
		$animatedsprite2d.speed_scale = sprint_speed_multiplier if _is_sprinting else 1.0

	last_direction = direction
	take_step()


func _handle_idle() -> void:
	# lerp velocity to zero for smooth stop (no sudden halt)
	velocity = velocity.lerp(Vector2.ZERO, 0.3)
	_is_sprinting = false
	_sprint_drain_accumulator = 0.0
	if has_node("animatedsprite2d"):
		$animatedsprite2d.play(get_idle_animation())
		$animatedsprite2d.speed_scale = 1.0


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

	if has_node("firering"):
		$firering.visible = true
		$firering.play("firering")


func _deactivate_aura() -> void:
	aura_active = false
	if has_node("firering"):
		$firering.visible = false


func _deal_aura_damage() -> void:
	# damage all enemies currently inside the $aura collision area.
	#
	# REMOVED: this used to also emit GameState.aura_damage_dealt on every
	# hit, described as being "for analytics / multiplayer sync." Neither
	# exists — nothing in the game connects to that signal, or to any of the
	# others on GameState (see the note at the top of gamestate.gd). It fired
	# once per enemy per aura tick into an empty bus, which is the most
	# expensive place in this file to do nothing. The declaration is still
	# there for when multiplayer is real; put the emit back then.
	if not has_node("aura"):
		return

	# CHANGED: was a flat aura_damage constant with no scaling at all —
	# tank gained attack XP from every tick but it never affected the
	# tank's own damage output. now scaled by get_damage_multiplier(),
	# same shared function every class's damage uses (see player.gd).
	# computed once outside the loop so every enemy in range takes the same
	# scaled number and the multiplier is not recomputed per body.
	var scaled_aura_damage: int = int(aura_damage * get_damage_multiplier())

	for body in $aura.get_overlapping_bodies():
		if not body.is_in_group("enemies"):
			continue
		if not body.has_method("take_damage"):
			continue
		body.take_damage(scaled_aura_damage)
		# NEW: universal attack XP, granted right where damage already
		# applies — see class comment's XP ON HIT section for the
		# tick-rate caveat worth watching in practice.
		gain_attack_xp(attack_xp_on_aura_tick)


# =============================================================================
# ANIMATION OVERRIDES
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


func get_attack_animation(_dir: Vector2) -> String:
	# tank has no direct attack — toggling the aura doesn't play an
	# attack animation. fall back to idle so the player sprite stays
	# in a clean state if attack_action ever calls this externally.
	return get_idle_animation()


func _get_dir_string() -> String:
	# returns the cardinal string matching last_direction.
	# used for hitflash animation lookup (hitflashleft / right / up / down).
	if abs(last_direction.x) > abs(last_direction.y):
		return "right" if last_direction.x > 0 else "left"
	return "down" if last_direction.y > 0 else "up"


# =============================================================================
# DAMAGE HANDLING OVERRIDE
# =============================================================================

func take_damage(amount: int, _type: StringName = &"physical") -> void:
	# wraps player.take_damage with tank-specific behavior:
	# - plays a directional hitflash animation if still alive
	# - deactivates the aura if the hit killed the tank
	var was_alive: bool = hp > 0
	super.take_damage(amount, _type)

	# play tank-specific hitflash ONLY if still alive after the hit.
	# without this guard, hitflash would overwrite the death animation
	# that parent's _start_death_sequence just started playing.
	if has_node("animatedsprite2d") and hp > 0 and not is_dying:
		$animatedsprite2d.play("hitflash" + _get_dir_string())

	# deactivate aura if tank just died so it doesn't keep ticking damage
	# during the death animation
	if was_alive and hp <= 0:
		_deactivate_aura()


# =============================================================================
# PHASE 2 ABILITY STUB
# =============================================================================

func activate_expand() -> void:
	# 4-second sprite scale-up. costs 25 mana.
	if mana >= 25:
		mana = clamp(mana - 25, 0, max_mana)
		scale = Vector2(1.5, 1.5)
		if has_node("firering"):
			$firering.scale = Vector2(1.5, 1.5)
		await get_tree().create_timer(4.0).timeout
		scale = Vector2(1.0, 1.0)
		if has_node("firering"):
			$firering.scale = Vector2(1.0, 1.0)
