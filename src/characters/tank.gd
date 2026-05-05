# tank character — defensive frontliner with placeable aura damage
extends "res://src/characters/player.gd"

# --- aura settings ---
# damage dealt to enemies per aura tick
var aura_damage: int = 4

# seconds between each aura damage tick
var aura_tick: float = 1.0

# internal countdown timer for aura damage ticks
var aura_timer: float = 0.0

# seconds between each mana drain
var mana_drain_tick: float = 0.5

# internal countdown timer for mana drain
var mana_drain_timer: float = 0.0

# how much mana is drained per drain tick
var mana_drain_cost: int = 2

# whether the aura ring is currently active and dealing damage
var aura_active: bool = false

# --- tank skills ---
# whether taunt is currently active
var taunt_active: bool = false

# taunt duration countdown in seconds
var taunt_duration: float = 0.0

func _ready():
	super._ready()
	character_name = "tank"
	speed = 140
	max_hp = 150
	hp = 150
	max_stamina = 120
	stamina = 120
	max_mana = 100
	mana = 100
	defense = 3

	# hide fire ring on start — only shows when aura is active
	if has_node("firering"):
		$firering.play("firering")
		$firering.visible = false

func _physics_process(delta):
	# run base player movement and input
	super._physics_process(delta)

	# handle taunt countdown
	if taunt_active:
		taunt_duration -= delta
		if taunt_duration <= 0:
			taunt_active = false

	if aura_active:
		# keep fire ring positioned under the tank
		if has_node("firering"):
			$firering.global_position = global_position

		# drain mana every 0.5 seconds
		mana_drain_timer += delta
		if mana_drain_timer >= mana_drain_tick:
			mana_drain_timer = 0.0
			mana = clamp(mana - mana_drain_cost, 0, max_mana)

			# deactivate aura if mana runs out
			if mana <= 0:
				_deactivate_aura()
				return

		# deal aura damage every second
		aura_timer += delta
		if aura_timer >= aura_tick:
			aura_timer = 0.0
			_deal_aura_damage()

# --- override attack action for tank ---
func attack_action():
	if aura_active:
		_deactivate_aura()
	else:
		_activate_aura()


func _activate_aura():
	if mana <= 0:
		return
	aura_active = true
	aura_timer = 0.0
	mana_drain_timer = 0.0
	if has_node("firering"):
		$firering.visible = true
		$firering.play("firering")
		
func _deactivate_aura():
	# deactivate aura
	aura_active = false

	# hide fire ring
	if has_node("firering"):
		$firering.visible = false

func _deal_aura_damage():
	# deal damage to all enemies overlapping the aura area
	if has_node("aura"):
		for body in $aura.get_overlapping_bodies():
			if body.is_in_group("enemies"):
				if body.has_method("take_damage"):
					body.take_damage(aura_damage)
					# emit signal for multiplayer tracking
					GameState.aura_damage_dealt.emit(
						get_instance_id(),
						body.get_instance_id(),
						aura_damage
					)

# --- helper to get direction string from last_direction ---
func _get_dir_string() -> String:
	if last_direction.x > 0: return "right"
	elif last_direction.x < 0: return "left"
	elif last_direction.y > 0: return "down"
	elif last_direction.y < 0: return "up"
	return "down"

# --- animation overrides ---

func get_walk_animation(dir: Vector2) -> String:
	if dir.x > 0: return "walkright"
	elif dir.x < 0: return "walkleft"
	elif dir.y > 0: return "walkdown"
	elif dir.y < 0: return "walkup"
	return "idledown"

func get_idle_animation() -> String:
	if last_direction.x > 0: return "idleright"
	elif last_direction.x < 0: return "idleleft"
	elif last_direction.y > 0: return "idledown"
	elif last_direction.y < 0: return "idleup"
	return "idledown"

func get_attack_animation(dir: Vector2) -> String:
	# tank has no direct attack animation
	return get_idle_animation()

# --- override take_damage to show hitflash ---
func take_damage(amount: int, _type: StringName = &"physical") -> void:
	# call parent take_damage first
	super.take_damage(amount, _type)

	# play hit flash animation if still alive
	if has_node("animatedsprite2d") and hp > 0:
		$animatedsprite2d.play("hitflash" + _get_dir_string())

# --- override die to show death animation ---
func die():
	# play death animation
	if has_node("animatedsprite2d"):
		$animatedsprite2d.play("death" + _get_dir_string())

	# hide fire ring on death
	_deactivate_aura()

	# change scene after animation
	call_deferred("_deferred_die")

# --- tank skills ---

func activate_taunt(duration: float) -> void:
	# forces nearby enemies to target the tank
	taunt_active = true
	taunt_duration = duration
	mana = clamp(mana - 20, 0, max_mana)
	GameState.taunt_activated.emit(get_instance_id(), duration)
	# TODO — enemy AI taunt targeting in phase 1

func activate_aura_burst() -> void:
	# temporarily doubles aura damage
	if mana >= 30:
		mana = clamp(mana - 30, 0, max_mana)
		aura_damage *= 2
		await get_tree().create_timer(3.0).timeout
		aura_damage /= 2

func activate_expand() -> void:
	# temporarily increases aura and character size
	if mana >= 25:
		mana = clamp(mana - 25, 0, max_mana)
		scale = Vector2(1.5, 1.5)
		if has_node("firering"):
			$firering.scale = Vector2(1.5, 1.5)
		await get_tree().create_timer(4.0).timeout
		scale = Vector2(1.0, 1.0)
		if has_node("firering"):
			$firering.scale = Vector2(1.0, 1.0)

# --- future skill placeholder ---
func drop_aura_on_enemy(target: Node) -> void:
	# TODO phase 1 — drop aura on enemy position
	# decreases enemy magic % and deals damage over time
	pass
