# warrior character — fast melee fighter with 4-directional attacks.
# the warrior's signature: free melee swings plus mana-gated slashwave
# projectiles for extended reach, letting the warrior compete with ranged
# classes against electric/fire enemies they can't safely approach.
#
# class identity:
# - balanced HP / mana / stamina, fast move speed
# - free melee swing (always available, no resource cost)
# - mana-gated slashwave projectile during contact frames (extends reach)
# - level-up grants +1 attack and +1 defense skill bonus on top of XP growth
#
# stat curve (recompute-from-level, set in _set_stat_curve):
#   HP   180 base / +12 per level
#   Mana 180 base / +10 per level
#   Stam  80 base / +5  per level
#
# damage architecture:
# 'attack' is the SKILL stat (player progression, 1->99 like other skills).
# it is NOT the damage value. damage = base_melee_damage + scaling bonus
# from the attack skill. when the equipment system is built,
# base_melee_damage should be replaced by the equipped weapon's damage.
# both melee and slashwave damage derive from _calculate_melee_damage()
# so skill progression scales BOTH consistently.
#
# resource model:
# - melee swing: FREE (preserves melee class identity, always available)
# - slashwave: mana-gated per spawn (when mana depleted, sword still swings
#   but the projectile doesn't fire)
# - mana regenerates via the universal regen in player.gd
#
# attack flow:
# 1. attack_action plays directional animation, resets per-swing state
# 2. _on_frame_changed during contact frames (2-5): scan hitbox, damage enemies
# 3. _on_frame_changed on wave_spawn_frame (6): spawn slashwave if mana permits
# 4. each enemy can only be hit ONCE per swing (cleave, no multi-tick)
extends "res://src/characters/player.gd"


# =============================================================================
# CONSTANTS
# =============================================================================

# preloaded slash wave projectile scene
const SLASHWAVE_SCENE := preload("res://scene/projectiles/slashwave.tscn")

# cardinal directions array — used by detection helpers to avoid 4x duplication
const CARDINAL_DIRECTIONS := ["left", "right", "up", "down"]


# =============================================================================
# EXPORTED SETTINGS — DAMAGE WINDOW
# =============================================================================

@export var contact_frame_start: int = 2
@export var contact_frame_end:   int = 5
@export var wave_spawn_frame: int = 6


# =============================================================================
# EXPORTED SETTINGS — DAMAGE VALUES
# =============================================================================

@export var base_melee_damage: int = 20
@export var wave_damage_ratio: float = 0.75
@export var slashwave_mana_cost: int = 10


# =============================================================================
# STATE
# =============================================================================

var _hit_this_swing: Array[Node] = []
var _wave_spawned_this_swing: bool = false


# =============================================================================
# NODE REFERENCES
# =============================================================================

@onready var sprite: AnimatedSprite2D = $animatedsprite2d

var hitboxes: Dictionary = {
	"left":  null,
	"right": null,
	"up":    null,
	"down":  null,
}

var wavespawns: Dictionary = {
	"left":  null,
	"right": null,
	"up":    null,
	"down":  null,
}


# =============================================================================
# STAT CURVE
# =============================================================================

func _set_stat_curve() -> void:
	# warrior: balanced HP, moderate mana for slashwave uptime, solid stamina.
	# called by player.gd._ready BEFORE recompute, so these drive max stats.
	hp_base    = 180; hp_per_lvl   = 12
	mana_base  = 180; mana_per_lvl = 10
	stam_base  = 80;  stam_per_lvl = 5


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# class identity — always set, regardless of save state.
	character_name = "warrior"
	speed = 200

	# super._ready() calls _set_stat_curve(), loads save, recomputes maxes
	# from level, and fills resources to full. no manual stat block needed.
	super._ready()

	_detect_hitboxes()
	_detect_wavespawns()
	_wire_animation_signal()


# =============================================================================
# INITIALIZATION HELPERS
# =============================================================================

func _detect_hitboxes() -> void:
	for dir in CARDINAL_DIRECTIONS:
		var node_name: String = "hitbox" + dir
		if has_node(node_name):
			hitboxes[dir] = get_node(node_name)


func _detect_wavespawns() -> void:
	for dir in CARDINAL_DIRECTIONS:
		var node_name: String = "wavespawn" + dir
		if has_node(node_name):
			wavespawns[dir] = get_node(node_name)


func _wire_animation_signal() -> void:
	if sprite == null:
		return
	if not sprite.frame_changed.is_connected(_on_frame_changed):
		sprite.frame_changed.connect(_on_frame_changed)


# =============================================================================
# DAMAGE CALCULATION
# =============================================================================

func _calculate_melee_damage() -> int:
	return base_melee_damage + int((attack - 1) / 2)


# =============================================================================
# ATTACK ACTION
# =============================================================================

func attack_action() -> void:
	if is_attacking:
		return

	_set_active()
	is_attacking = true

	_hit_this_swing.clear()
	_wave_spawned_this_swing = false

	var anim: String = get_attack_animation(last_direction)
	if sprite != null and sprite.sprite_frames.has_animation(anim):
		sprite.play(anim)
		sprite.frame = 0


func _on_frame_changed() -> void:
	if not is_attacking:
		return
	if sprite == null:
		return
	if not sprite.animation.begins_with("attack"):
		return

	if sprite.frame >= contact_frame_start and sprite.frame <= contact_frame_end:
		_deal_melee_damage()

	if sprite.frame == wave_spawn_frame and not _wave_spawned_this_swing:
		_spawn_slashwave()
		_wave_spawned_this_swing = true


# =============================================================================
# MELEE DAMAGE
# =============================================================================

func _deal_melee_damage() -> void:
	var box: Area2D = _get_active_hitbox()
	if box == null:
		return

	for area in box.get_overlapping_areas():
		_try_damage(area.get_parent())

	for body in box.get_overlapping_bodies():
		_try_damage(body)


func _try_damage(target: Node) -> void:
	if target == null:
		return
	if target in _hit_this_swing:
		return
	if not target.is_in_group("enemies"):
		return
	if not target.has_method("take_damage"):
		return

	target.take_damage(_calculate_melee_damage())
	gain_attack_xp(5)
	_hit_this_swing.append(target)


# =============================================================================
# SLASHWAVE PROJECTILE
# =============================================================================

func _spawn_slashwave() -> void:
	if mana < slashwave_mana_cost:
		return

	var dir: String = _last_direction_to_cardinal()
	var spawn_node: Marker2D = wavespawns.get(dir)
	if spawn_node == null:
		return

	mana -= slashwave_mana_cost

	var wave: SlashWave = SLASHWAVE_SCENE.instantiate()
	_parent_to_projectiles_container(wave)

	wave.global_position = spawn_node.global_position
	wave.damage = int(_calculate_melee_damage() * wave_damage_ratio)
	wave.shoot(dir)


func _parent_to_projectiles_container(wave: Node) -> void:
	var container: Node = get_tree().get_first_node_in_group("projectiles")
	if container == null:
		container = get_tree().current_scene
	container.add_child(wave)


# =============================================================================
# DIRECTION HELPERS
# =============================================================================

func _get_active_hitbox() -> Area2D:
	var dir: String = _last_direction_to_cardinal()
	return hitboxes.get(dir)


func _last_direction_to_cardinal() -> String:
	if abs(last_direction.x) > abs(last_direction.y):
		return "right" if last_direction.x > 0 else "left"
	else:
		return "down" if last_direction.y > 0 else "up"


# =============================================================================
# LEVEL-UP SKILL BONUS
# =============================================================================

func _apply_level_up_skill_bonus() -> void:
	# warrior skill bonus: +1 attack, +1 defense per level. these stack with
	# XP-based skill growth and are NOT part of the recomputed stat pools.
	attack  += 1
	defense += 1
