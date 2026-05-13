# tank character — defensive frontliner with placeable aura damage.
# the tank's signature mechanic: a passive AoE damage aura (firering) that
# drains mana while active. press attack to toggle on/off. when mana runs
# out the aura auto-deactivates. provides constant pressure on melee
# enemies while the rest of the party deals burst damage.
extends "res://src/characters/player.gd"

# --- aura settings ---
# damage dealt to each enemy in the aura every aura_tick seconds
var aura_damage: int = 4
# how often the aura ticks damage on enemies (seconds)
var aura_tick: float = 1.0
# accumulator that fires aura damage when it reaches aura_tick
var aura_timer: float = 0.0
# how often mana drains while the aura is active (seconds)
var mana_drain_tick: float = 0.5
# accumulator that drains mana when it reaches mana_drain_tick
var mana_drain_timer: float = 0.0
# how much mana drains per tick — at 2 mana / 0.5s = 4 mp/sec
var mana_drain_cost: int = 2
# true while the aura is running (consumes mana, damages enemies)
var aura_active: bool = false

func _ready():
	super._ready()
	character_name = "tank"
	speed = 160
	max_hp = 150
	hp = 150
	max_stamina = 25
	stamina = 25
	max_mana = 100
	mana = 100
	defense = 3
	if has_node("firering"):
		$firering.play("firering")
		$firering.visible = false

func _physics_process(delta):
	# block all input/movement during death sequence so the death animation
	# can play through without being overwritten by walk/idle. parent's
	# _physics_process has this guard but tank fully overrides it.
	if is_dying:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	# --- aura logic ---
	if aura_active:
		mana_drain_timer += delta
		if mana_drain_timer >= mana_drain_tick:
			mana_drain_timer = 0.0
			var before := mana
			mana = clamp(mana - mana_drain_cost, 0, max_mana)
			print("AURA DRAIN: mana %d -> %d" % [before, mana])
			if mana <= 0:
				_deactivate_aura()
				return
		aura_timer += delta
		if aura_timer >= aura_tick:
			aura_timer = 0.0
			_deal_aura_damage()

	# --- movement ---
	if is_attacking:
		velocity = Vector2.ZERO
		move_and_slide()
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
		velocity = velocity.lerp(direction.normalized() * (speed + (agility - 1) * 10), 0.3)
		if has_node("animatedsprite2d"):
			$animatedsprite2d.play(get_walk_animation(direction))
		last_direction = direction
		take_step()
	else:
		velocity = velocity.lerp(Vector2.ZERO, 0.3)
		if has_node("animatedsprite2d"):
			$animatedsprite2d.play(get_idle_animation())
	move_and_slide()

# --- attack overridden for tank ---
func attack_action():
	if aura_active:
		_deactivate_aura()
	else:
		_activate_aura()

func _activate_aura():
	if mana <= 0:
		print("CANNOT ACTIVATE AURA: no mana")
		return
	aura_active = true
	aura_timer = 0.0
	mana_drain_timer = 0.0
	print("AURA ACTIVATED, mana=%d" % mana)
	if has_node("firering"):
		$firering.visible = true
		$firering.play("firering")

func _deactivate_aura():
	print("AURA DEACTIVATED")
	aura_active = false
	if has_node("firering"):
		$firering.visible = false

func _deal_aura_damage():
	if has_node("aura"):
		for body in $aura.get_overlapping_bodies():
			if body.is_in_group("enemies"):
				if body.has_method("take_damage"):
					body.take_damage(aura_damage)
					GameState.aura_damage_dealt.emit(
						get_instance_id(),
						body.get_instance_id(),
						aura_damage
					)

# --- direction helpers ---

func _get_dir_string() -> String:
	if abs(last_direction.x) > abs(last_direction.y):
		return "right" if last_direction.x > 0 else "left"
	return "down" if last_direction.y > 0 else "up"

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
	return get_idle_animation()

# --- damage handling overrides ---

func take_damage(amount: int, _type: StringName = &"physical") -> void:
	var was_alive: bool = hp > 0
	super.take_damage(amount, _type)

	# play tank-specific hitflash animation ONLY if still alive after the hit.
	# without this guard, hitflash would overwrite the death animation that
	# parent's _start_death_sequence just started playing, breaking the
	# game-over transition that relies on death animation_finished firing.
	if has_node("animatedsprite2d") and hp > 0 and not is_dying:
		$animatedsprite2d.play("hitflash" + _get_dir_string())

	# deactivate aura if tank just died — so the aura doesn't continue ticking
	# damage during the death animation.
	if was_alive and hp <= 0:
		_deactivate_aura()

func die():
	# UNUSED — parent.gd calls _start_death_sequence() at hp<=0 instead of
	# calling die() directly. kept here as a hook for future class-specific
	# death behavior that doesn't fit in _start_death_sequence.
	pass

# --- placeholder ability stubs (phase 2 content) ---

func activate_taunt(duration: float) -> void:
	# TODO: pull aggro from all enemies within taunt radius for duration seconds.
	pass

func activate_aura_burst() -> void:
	if mana >= 30:
		mana = clamp(mana - 30, 0, max_mana)
		aura_damage *= 2
		await get_tree().create_timer(3.0).timeout
		aura_damage /= 2

func activate_expand() -> void:
	if mana >= 25:
		mana = clamp(mana - 25, 0, max_mana)
		scale = Vector2(1.5, 1.5)
		if has_node("firering"):
			$firering.scale = Vector2(1.5, 1.5)
		await get_tree().create_timer(4.0).timeout
		scale = Vector2(1.0, 1.0)
		if has_node("firering"):
			$firering.scale = Vector2(1.0, 1.0)

func drop_aura_on_enemy(target: Node) -> void:
	pass
