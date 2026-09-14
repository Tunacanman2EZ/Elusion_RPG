# bushmage enemy — ranged caster that summons a stationary vine attack
# in front of itself, stretching toward the player. holds at roughly 1 tile
# away and casts when the player is in range.
#
# attack flow:
# 1. bushmage plays directional attack animation (attackleft/right/up/down)
# 2. on contact_frame, spawns vine.tscn AT THE PLAYER's position, parented
#    into the Y-sorted "groundeffects" group so it renders under the player
# 3. vine plays its own stretch animation in the same direction
# 4. vine damages player on its own impact frame
# 5. vine despawns when its animation finishes
#
# spawn guard:
# _vine_spawned_this_attack flag ensures only ONE vine per attack cycle,
# even if the attack animation loops or frame_changed fires extra times.
# the flag resets at the start of each new _trigger_attack call.
#
# this differs from BaseEnemy._physics_process because bushmage uses
# chase-and-hold positioning (target distance ~1 tile) rather than the
# default flee/attack/idle state machine. IMPORTANT: because of this,
# BaseEnemy._physics_process (and its navigation-agent chase logic) never
# runs for this class at all — this class's own _move_toward_player()
# below is the only thing that handles closing distance to the player,
# which is why it needs its own explicit call into
# _get_direction_to_player_via_navigation() (inherited from BaseEnemy)
# rather than picking that up automatically.
extends BaseEnemy
class_name BushMage

# This enemy's reward profile. See BaseEnemy.enemy_data — the hp, xp, loot tier
# and pet that used to be assigned in _ready() below all live in this file now.
const ENEMY_DATA := preload("res://data/enemies/bushmage.tres")


# =============================================================================
# EXPORTED SETTINGS
# =============================================================================

# damage dealt by the vine effect (passed to the spawned vine instance)
@export var attack_power: int = 8

# preferred distance from player — bushmage chases/backs off to hold this.
#
# RETUNED TO MATCH THE SLOT GRID, WHICH IS WHY THIS NEVER CAST.
#
# These were set for the old free-angle ring, where an enemy ended up roughly
# `desired_distance` from the player. The grid that replaced it parks enemies
# on ring-1 tiles instead: TILE_SIZE (20) * FORMATION_SLOT_STRIDE (2) = 40px
# on the axes, and 40 * sqrt(2) = ~56.6px on the diagonals.
#
# The old band was 32 +/- 4, i.e. 28..36px. Ring 1 is 40..56.6px. The two
# never overlapped, so _physics_process below always took the "too far"
# branch, _move_toward_player() found it was already standing on its slot,
# and it idled there forever. The bush mage wasn't failing to cast — it was
# never reaching the code that casts.
#
# 48 +/- 12 spans 36..60, which covers an axis slot and a diagonal one with
# margin either side.
@export var desired_distance:   float = 48.0  # ring-1 axis..diagonal midpoint
@export var distance_tolerance: float = 12.0  # wide enough to cover both

# frame of the bushmage attack animation where the vine spawns
@export var contact_frame: int = 3

# vine projectile scene — assign in inspector or rely on the default preload
@export var vine_scene: PackedScene = preload("res://scene/projectiles/vine.tscn")


# =============================================================================
# STATE
# =============================================================================

# guards against multiple vine spawns within a single attack cycle.
# set false on each _trigger_attack, set true after the first spawn.
var _vine_spawned_this_attack: bool = false


# =============================================================================
# NODE REFERENCES
# =============================================================================

@onready var sprite: AnimatedSprite2D = $animatedsprite2d


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# class-specific stat overrides BEFORE super._ready() so BaseEnemy
	# wires the healthbar and attack timer with the right values
	# Guarded so a per-placement override set in the Inspector still wins.
	if enemy_data == null:
		enemy_data = ENEMY_DATA

	# COMBAT TUNING STAYS HERE. Only the reward profile moved to the .tres.
	# attack_range in particular could not move: it is derived from this
	# enemy's hold distance, so it is not a number you can put in a file.
	attack_cooldown = 1.2
	attack_range    = desired_distance + 8.0  # reach slightly past hold zone

	super._ready()

	# wire frame_changed so we can spawn the vine on contact_frame
	sprite.frame_changed.connect(_on_frame_changed)


func _physics_process(_delta: float) -> void:
	# override BaseEnemy's _physics_process entirely — bushmage uses
	# chase-and-hold instead of the default flee/attack/idle pattern.
	if player == null:
		_resolve_player()
		return

	attack_direction = _get_direction_to_player()

	# while attacking, freeze in place and let the animation play out
	if is_attacking:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var dist: float = global_position.distance_to(player.global_position)

	# LEASH.
	#
	# BaseEnemy._physics_process does this check, but this class replaces that
	# method wholesale rather than extending it — so bush mages had no leash
	# at all. They followed the player across the entire map and never went
	# home, which is also why they ended up far from the bushes they spawn in.
	# Every other enemy respects leash_range; this one silently opted out by
	# overriding the only place it was enforced.
	if dist > leash_range:
		_handle_return_home()
		return
	is_returning_home = false

	if dist > desired_distance + distance_tolerance:
		_move_toward_player()
	elif dist < desired_distance - distance_tolerance:
		_back_off_from_player()
	else:
		_hold_and_attack()


# =============================================================================
# MOVEMENT MODES
# =============================================================================

func _move_toward_player() -> void:
	# CHANGED: routes toward this bushmage's claimed TILE around the
	# player (see baseenemy.gd's SLOT SYSTEM section — now a real
	# discrete grid, not a free-angle ring), instead of straight at the
	# player directly — this is what spreads multiple bushmages out
	# instead of all converging on the same spot.
	#
	# CHANGED AGAIN: the earlier "desired_distance * 3.0" fix was for the
	# old free-angle ring system, where circumference (and therefore
	# per-enemy spacing) shrank as more enemies packed onto the same
	# radius. the grid system replacing it guarantees real tile-sized
	# separation between adjacent slots regardless of enemy count, so
	# just uses the default TILE_SIZE spacing now — no per-class
	# multiplier needed to compensate for a shrinking ring anymore.
	var slot_target: Vector2 = _get_slot_target_position()

	# NEW: essentially arrived at the claimed slot — stop and hold
	# instead of continuing to chase it. see baseenemy.gd's
	# SLOT_ARRIVAL_THRESHOLD comment for why this is what actually stops
	# the animation-flip jitter at close range.
	if global_position.distance_to(slot_target) < SLOT_ARRIVAL_THRESHOLD:
		# ARRIVED — cast from here rather than standing idle.
		#
		# This branch used to idle unconditionally, which made the hold band
		# above the ONLY route to an attack. Any slot geometry that put the
		# enemy outside that band meant it stood at its slot doing nothing
		# forever, which is exactly what happened. Retuning the band fixed
		# today's numbers; this makes the class stop depending on them being
		# right, so a future change to TILE_SIZE or the ring count can't
		# silently disarm the bush mage again.
		velocity = Vector2.ZERO
		move_and_slide()
		_hold_and_attack()
		return

	var pos_before: Vector2 = global_position
	var chase_dir: String = _get_direction_to_point_via_navigation(slot_target)
	velocity = _vec_from_dir(chase_dir) * get_move_speed()
	move_and_slide()
	play_walk_animation(chase_dir)
	_record_nav_movement_result(pos_before)


func _back_off_from_player() -> void:
	# too close — back off toward open space
	var back_dir: String = _get_direction_from_vec(global_position - player.global_position)
	velocity = _vec_from_dir(back_dir) * get_move_speed()
	move_and_slide()
	play_walk_animation(back_dir)


func _hold_and_attack() -> void:
	# in the sweet spot — stop and cast when ready, otherwise idle
	velocity = Vector2.ZERO
	if attack_ready:
		_trigger_attack()
	else:
		play_idle_animation(attack_direction)


# =============================================================================
# ATTACK OVERRIDE
# =============================================================================

func _trigger_attack() -> void:
	# reset the spawn guard so this attack can spawn a vine.
	# then delegate to BaseEnemy._trigger_attack which sets attack_ready,
	# is_attacking, starts the cooldown timer, and plays the attack animation.
	_vine_spawned_this_attack = false
	super._trigger_attack()


# =============================================================================
# SUBCLASS OVERRIDES
# =============================================================================

func get_move_speed() -> float:
	return 75.0


# bushmage doesn't use the BaseEnemy fire_projectile hook because we spawn
# from frame_changed instead. kept empty for documentation.
func fire_projectile() -> void:
	pass


# =============================================================================
# VINE SPAWNING
# =============================================================================

func _on_frame_changed() -> void:
	# spawn the vine ONCE per attack cycle, on contact_frame.
	# the spawn guard prevents multiple vines if the attack animation loops
	# or frame_changed fires repeatedly during the same cast.

	# if we're not in an attack animation, reset the guard so the next
	# attack can spawn fresh (covers the idle->attack transition cleanly)
	if not sprite.animation.begins_with("attack"):
		_vine_spawned_this_attack = false
		return

	# guard: already spawned this attack
	if _vine_spawned_this_attack:
		return

	# guard: not on the contact frame yet
	if sprite.frame != contact_frame:
		return

	_spawn_vine()
	_vine_spawned_this_attack = true


func _spawn_vine() -> void:
	# instantiate vine at bushmage's OWN position (this is the original,
	# intended design — the vine's stretch animation visually reaches
	# toward the player from here; only petvine.gd spawns at the target
	# directly, since pets use a different no-travel eruption style).
	# parented into the Y-sorted "groundeffects" group so it still renders
	# under characters correctly, regardless of where it spawns. falls back
	# to current_scene if no groundeffects group exists yet, same fallback
	# pattern as pet.gd.
	if vine_scene == null:
		push_warning("BushMage: vine_scene not assigned")
		return

	var vine: Node2D = vine_scene.instantiate()
	var container: Node = get_tree().get_first_node_in_group("groundeffects")
	if container == null:
		container = get_tree().current_scene
	container.add_child(vine)
	vine.global_position = global_position
	vine.damage = attack_power
	vine.fire(attack_direction)
	# AFTER fire(), not before: fire() sets the vine's facing, and rotation is
	# part of the transform being interpolated. Resetting first would collapse
	# the position blend and leave the rotation one to spin the vine into place.
	# See BaseEnemy.spawn_projectile_node() for why any of this is needed.
	vine.reset_physics_interpolation()
