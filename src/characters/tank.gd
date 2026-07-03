# tank character — defensive frontliner with placeable aura damage.
# the tank's signature mechanic: a passive AoE damage aura (firering) that
# drains mana while active. press attack to toggle on/off. when mana runs
# out the aura auto-deactivates.
#
# class identity:
# - highest HP by far (the durability king), slowest mover, heavy frontline
# - mana powers the AOE aura instead of casts
# - aura is the ONLY attack — no direct strike, just radiating damage
# - level-up grants +2 defense skill bonus on top of XP-based growth
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
extends "res://src/characters/player.gd"


# =============================================================================
# AURA SETTINGS
# =============================================================================

@export var aura_damage: int = 4
@export var aura_tick: float = 0.25
@export var mana_drain_tick: float = 0.5
@export var mana_drain_cost: int = 2


# =============================================================================
# AURA STATE
# =============================================================================

var aura_timer:       float = 0.0
var mana_drain_timer: float = 0.0
var aura_active: bool = false


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

	# attack button toggles the aura
	if Input.is_action_just_pressed("attack"):
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

	for body in $aura.get_overlapping_bodies():
		if not body.is_in_group("enemies"):
			continue
		if not body.has_method("take_damage"):
			continue
		body.take_damage(aura_damage)
		GameState.aura_damage_dealt.emit(
			get_instance_id(),
			body.get_instance_id(),
			aura_damage,
		)


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
