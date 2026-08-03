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

# NEW: tracks right-click press state for edge detection, same pattern
# as warrior's/mage's _right_click_was_held. right-click is polled
# privately here rather than added to the shared "attack" Input Map
# action — see _physics_process below for why.
var _right_click_was_held: bool = false


# =============================================================================
# STAT CURVE
# =============================================================================

func _set_stat_curve() -> void:
	# tank: steepest HP curve in the game (frontline durability is the whole
	# kit), solid mana for aura uptime. called before recompute in player.gd.
	hp_base    = 260; hp_per_lvl   = 22
	mana_base  = 200; mana_per_lvl = 10
	stam_base  = 100; stam_per_lvl = 5


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
	# always sample right-click, even in branches that return early below —
	# same reasoning as warrior/mage's _right_click_was_held: without this,
	# a click held through death or an attack lockout could false-trigger
	# the toggle the instant the block lifts, since the edge-detection
	# would see "wasn't held a moment ago" even though it's been held the
	# whole time.
	var right_held_now: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)

	# block all input/movement during death sequence so the death animation
	# can play through without being overwritten by walk/idle animations.
	if is_dying:
		velocity = Vector2.ZERO
		move_and_slide()
		_right_click_was_held = right_held_now
		return

	_tick_aura(delta)

	# attack lockout — frozen in place while attack animation plays
	if is_attacking:
		velocity = Vector2.ZERO
		move_and_slide()
		_set_active()
		_right_click_was_held = right_held_now
		return

	# NEW: attack button (spacebar) OR right-click toggles the aura — both
	# call the same attack_action(), matching warrior/mage's dual-input
	# pattern. right-click stays a private poll here rather than joining
	# the shared "attack" Input Map action, since that action is inherited
	# by every class — binding a mouse button onto it directly would give
	# mage (which already uses right-click for its own cast) a second,
	# colliding path to the same trigger.
	var right_click_pressed_now: bool = right_held_now and not _right_click_was_held
	_right_click_was_held = right_held_now

	if Input.is_action_just_pressed("attack") or right_click_pressed_now:
		attack_action()
		return

	_handle_movement(delta)
	_tick_regen(delta)


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

func _tick_regen(delta: float) -> void:
	# tank fully overrides _physics_process so the regen code from player.gd
	# doesn't run automatically. duplicate the accumulator + trigger here.
	# the _set_active() calls in movement/aura/attack reset the idle timer
	# so regen only fires during TRUE idle.
	_idle_timer += delta
	if _idle_timer >= idle_threshold:
		_regen_accumulator += regen_rate * delta
		if _regen_accumulator >= 1.0:
			var points: int = int(_regen_accumulator)
			_regen_accumulator -= points
			_regen_stats(points)


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
		print("CANNOT ACTIVATE AURA: no mana")
		return

	# toggling aura on counts as activity
	_set_active()

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
	# emits GameState.aura_damage_dealt for analytics / multiplayer sync.
	if not has_node("aura"):
		return

	# CHANGED: was a flat aura_damage constant with no scaling at all —
	# tank gained attack XP from every tick but it never affected the
	# tank's own damage output. now scaled by get_damage_multiplier(),
	# same shared function every class's damage uses (see player.gd).
	# computed once here so the analytics emit below reflects the same
	# actual scaled damage dealt, not the flat unscaled base.
	var scaled_aura_damage: int = int(aura_damage * get_damage_multiplier())

	for body in $aura.get_overlapping_bodies():
		if not body.is_in_group("enemies"):
			continue
		if not body.has_method("take_damage"):
			continue
		body.take_damage(scaled_aura_damage)
		GameState.aura_damage_dealt.emit(
			get_instance_id(),
			body.get_instance_id(),
			scaled_aura_damage,
		)
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
