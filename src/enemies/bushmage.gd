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


# =============================================================================
# EXPORTED SETTINGS
# =============================================================================

# damage dealt by the vine effect (passed to the spawned vine instance)
@export var attack_power: int = 8

# preferred distance from player — bushmage chases/backs off to hold this
@export var desired_distance:   float = 32.0  # ~1 tile
@export var distance_tolerance: float = 4.0   # dead zone to prevent jitter

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
	max_hp          = 80
	attack_cooldown = 1.2
	attack_range    = desired_distance + 8.0  # reach slightly past hold zone

	# NEW: pet_drop_id defaults to "" on every enemy (never set per-instance
	# in the editor), which meant _roll_pet() always bailed out immediately
	# before even rolling the dice — the entire triple-six pet-drop system
	# was completely non-functional, not just rare. guarded so an explicit
	# Inspector override still wins if one's ever set later.
	if pet_drop_id == "":
		pet_drop_id = "petmage"

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
		velocity = Vector2.ZERO
		move_and_slide()
		play_idle_animation(attack_direction)
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
