# warrior character — fast melee fighter with cursor-aimed attacks.
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
# CURSOR-AIM ATTACK (NEW):
# - triggered by EITHER the shared "attack" input action (spacebar) OR a
#   right-click, polled privately inside warrior's own _physics_process
#   (see _right_click_was_held). right-click is intentionally NOT added to
#   the shared "attack" Input Map action, because that action is inherited
#   by every class — including mage, whose attack_action() override IS its
#   right-click stalagmite cast via a separate direct poll. Adding a mouse
#   button to the shared action would give mage two independent paths to
#   the same cast. Keeping warrior's right-click private avoids that.
# - on trigger, we read get_global_mouse_position() and compute a direction
#   vector from the warrior to the cursor. that direction drives:
#     1. which attack animation plays (snapped to nearest cardinal, via the
#        same get_attack_animation() helper player.gd already uses)
#     2. which hitboxXXXX / wavespawnXXXX node is treated as "active" for
#        this swing (also cardinal-snapped — see note below)
# - the SLASHWAVE now travels at a true 360 angle toward the cursor, via
#   slashwave.gd's shoot_vector() (its animation still snaps to nearest
#   cardinal internally — that part is unchanged, just the travel line).
# - MELEE HIT DETECTION is still cardinal-snapped: hitboxleft/right/up/down
#   are 4 fixed pre-placed Area2D nodes (not a single node we can freely
#   rotate/reposition), so contact damage still picks whichever of the 4
#   is closest to the cursor angle, same as the animation. what changed vs.
#   before is that the snap now comes from cursor direction instead of last
#   WASD direction. true continuous 360 melee hit detection would need a
#   restructured single hitbox rotated at runtime — flagged as a possible
#   follow-up, not done here.
# - warrior no longer freezes movement during the swing (player.gd's
#   attack_locks_movement is set false below), so you keep walking while
#   attacking.
#
# attack flow:
# 1. attack_action reads cursor direction, plays matching directional
#    animation, resets per-swing state
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

# NEW: how fast the attack animation itself plays, independent of walk/sprint
# speed. Doesn't change WHICH frames trigger damage/wave (contact_frame_start/
# end and wave_spawn_frame are still frame-index based, not time-based) — it
# just compresses the whole swing into less real time. Tune to taste; this is
# a practical mitigation for the cardinal-snap mismatch (the pose can be up
# to 45° off from your actual cursor aim while moving) — a faster swing means
# that mismatched pose is visible for less time, even though it doesn't fix
# the underlying snap.
@export var attack_animation_speed: float = 2.0


# =============================================================================
# STATE
# =============================================================================

var _hit_this_swing: Array[Node] = []
var _wave_spawned_this_swing: bool = false

# NEW: the cursor-aim direction captured at the moment this swing started.
# used instead of last_direction to pick the animation AND the active
# hitbox/wavespawn for the whole swing, so a moving cursor mid-swing
# doesn't change which hitbox is "live" partway through.
var _swing_aim_direction: Vector2 = Vector2.DOWN

# NEW: tracks right-click press state for edge detection, same pattern as
# mage's _right_click_was_held. kept PRIVATE to warrior — right-click is
# polled directly here rather than being added to the shared "attack"
# Input Map action, because that action is inherited by every class
# including mage, whose own attack_action() override IS its right-click
# stalagmite cast. binding a mouse button onto the shared action would
# give mage two independent paths to the same cast (the action AND its own
# direct poll), racing each other. polling right-click privately here
# avoids that entirely — mage's right-click stays untouched by any of this.
var _right_click_was_held: bool = false


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

	# NEW: don't freeze movement while is_attacking — warrior keeps walking
	# through its swing. mage/tank/healer are unaffected since this defaults
	# to true on the base class.
	attack_locks_movement = false

	# super._ready() calls _set_stat_curve(), loads save, recomputes maxes
	# from level, and fills resources to full. no manual stat block needed.
	super._ready()

	_detect_hitboxes()
	_detect_wavespawns()
	_wire_animation_signal()


func _physics_process(delta: float) -> void:
	# parent handles movement (WASD), spacebar attack dispatch via the
	# shared "attack" action, animation switching, universal regen, and
	# universal sprint. we layer right-click attack on top, polled directly
	# (NOT via the "attack" action) so it stays private to warrior — see
	# note on _right_click_was_held above for why.
	super._physics_process(delta)

	var right_held_now: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)

	# block right-click attack during death, same as mage blocks its cast.
	# we do NOT block on is_attacking here — attack_action() already guards
	# against re-triggering mid-swing, so this just needs to not double-fire
	# on the same held click.
	if is_dying:
		_right_click_was_held = right_held_now
		return

	# press-edge detection: fires once on press, not every frame held
	if right_held_now and not _right_click_was_held:
		attack_action()

	_right_click_was_held = right_held_now


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

	# NEW: aim toward the cursor instead of last WASD direction. fall back
	# to last_direction if the cursor is sitting exactly on the player
	# (zero-length vector, e.g. controller/edge case) so we never animate
	# toward a garbage direction.
	var to_cursor: Vector2 = get_global_mouse_position() - global_position
	_swing_aim_direction = to_cursor.normalized() if to_cursor.length() > 0.001 else last_direction

	var anim: String = get_attack_animation(_swing_aim_direction)
	if sprite != null and sprite.sprite_frames.has_animation(anim):
		sprite.play(anim)
		sprite.frame = 0
		sprite.speed_scale = attack_animation_speed


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

	var dir: String = _cardinal_from_direction(_swing_aim_direction)
	var spawn_node: Marker2D = wavespawns.get(dir)
	if spawn_node == null:
		return

	mana -= slashwave_mana_cost

	var wave: SlashWave = SLASHWAVE_SCENE.instantiate()
	_parent_to_projectiles_container(wave)

	wave.global_position = spawn_node.global_position
	wave.damage = int(_calculate_melee_damage() * wave_damage_ratio)

	# NEW: fire at the true cursor angle (not cardinal-snapped) via
	# shoot_vector(). the wave still snaps its OWN animation to the nearest
	# cardinal internally (slashwave.gd handles that), but the travel
	# direction is now full 360 — this is the "real" 360 aim piece the
	# fixed 4-node melee hitboxes can't give us. spawn origin (spawn_node)
	# stays cardinal-snapped since it's just a launch point on the warrior's
	# body, not the direction of travel.
	wave.shoot_vector(_swing_aim_direction)


func _parent_to_projectiles_container(wave: Node) -> void:
	var container: Node = get_tree().get_first_node_in_group("projectiles")
	if container == null:
		container = get_tree().current_scene
	container.add_child(wave)


# =============================================================================
# DIRECTION HELPERS
# =============================================================================

func _get_active_hitbox() -> Area2D:
	var dir: String = _cardinal_from_direction(_swing_aim_direction)
	return hitboxes.get(dir)


# CHANGED: generalized from _last_direction_to_cardinal() (which only ever
# read last_direction) into a function that snaps ANY direction vector to
# its nearest cardinal. warrior now calls this with _swing_aim_direction
# (cursor-based) instead of last_direction (WASD-based).
func _cardinal_from_direction(dir: Vector2) -> String:
	if abs(dir.x) > abs(dir.y):
		return "right" if dir.x > 0 else "left"
	else:
		return "down" if dir.y > 0 else "up"


# =============================================================================
# LEVEL-UP SKILL BONUS
# =============================================================================

func _apply_level_up_skill_bonus() -> void:
	# warrior skill bonus: +1 attack, +1 defense per level. these stack with
	# XP-based skill growth and are NOT part of the recomputed stat pools.
	attack  += 1
	defense += 1
