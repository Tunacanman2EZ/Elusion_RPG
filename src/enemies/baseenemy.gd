# base class for all enemies — inherited by bushmage, bushsniper,
# electricsprite, firesprite.
#
# behavior model:
# - look up the player on _ready via "player" group lookup
# - every physics frame: update direction to player, decide whether to
#   flee, attack, chase, or return home based on distance + leash
# - attack animations play with is_attacking=true blocking movement until
#   _on_animation_finished clears the flag
# - subclasses override get_move_speed() and fire_projectile()
#
# leash system: enemies remember spawn position and return home if the
# player gets more than leash_range away, preventing map-wide migration.
#
# stacking avoidance: overlapping enemies nudge apart via velocity every
# 3rd frame (staggered per instance id).
#
# NAVIGATION (NEW): the "chase toward player" case now routes through a
# NavigationAgent2D instead of a straight line — see the NAVIGATION
# section below for what this needs in the scene to actually work, and
# why movement still stays strictly 4-directional despite using real
# pathfinding underneath.
#
# loot drops:
# on death, rolls two INDEPENDENT things:
#   1. bag drop (bag_drop_chance) — gold + tier-gated items
#   2. pet drop — three d6, all sixes (1/216) drops this enemy's signature
#      pet (pet_drop_id). a won pet forces a bag to spawn to hold it.
# gold is guaranteed in any bag.
#
# ITEM RARITY (CHANGED): item rolls were previously 8 independent chances
# at 35% each (~2.8 expected items per bag, with real odds of 4-5+ landing
# on the high end of variance) — enough noise that items stopped reading as
# meaningful next to the pet-beam moment. cut to fewer, lower-odds rolls
# (see max_item_slots/slot_fill_chance below), and the tier weighting
# formula changed from linear to exponential so higher-tier items are
# dramatically rarer relative to lower-tier ones instead of barely
# differentiated. gold generation is untouched — already guaranteed on
# every bag with no rarity gate, which is exactly the "currency flows,
# items are scarce" split this was tuned toward.
#
# projectile spawning:
# spawn_projectile_node() parents projectiles into the y-sorted "projectiles"
# container so they depth-sort against characters. deferred to avoid the
# "can't change state while flushing queries" physics error.
extends CharacterBody2D
class_name BaseEnemy


# =============================================================================
# CONSTANTS
# =============================================================================

const FLOATING_LABEL_SCENE := preload("res://scene/ui/floatinglabel.tscn")
const LOOTBAG_SCENE := preload("res://scene/interactables/lootbag.tscn")

const HOME_ARRIVAL_THRESHOLD := 4.0

const LARGE_GOLD_THRESHOLD := 100
const GOLD_SMALL_ID := "smallamountofgold"
const GOLD_LARGE_ID := "largeamountofgold"


# =============================================================================
# EXPORTED SETTINGS
# =============================================================================

@export var max_hp:           int   = 50

@export var attack_cooldown:  float = 2.0
@export var attack_range:     float = 200.0
@export var flee_range:       float = 40.0

@export var leash_range:      float = 400.0

@export var xp_reward:        int = 20
@export var attack_xp_reward: int = 5


# =============================================================================
# EXPORTED SETTINGS — LOOT DROPS
# =============================================================================

@export var bag_drop_chance: float = 0.30
@export var max_loot_tier: int = 1

# CHANGED: was a hardcoded const (BAG_ITEM_SLOTS = 8), now exported so
# tougher enemies can reasonably roll more item chances than a basic mob
# without needing a second global constant. was 8, now 3 — see class
# comment on ITEM RARITY for why.
@export var max_item_slots: int = 3

# CHANGED: was 0.35, now 0.15. combined with max_item_slots dropping from
# 8 to 3, expected items per bag goes from ~2.8 down to ~0.45 — most bags
# that drop will have zero or one item, two+ becomes a real rare moment.
@export var slot_fill_chance: float = 0.15

@export var pet_drop_id: String = ""


# =============================================================================
# SIGNALS
# =============================================================================

signal damaged(amount: int)
signal died


# =============================================================================
# STATE
# =============================================================================

var hp: int
var player: CharacterBody2D = null
var attack_direction: String = "down"
var attack_ready: bool = true
var is_attacking: bool = false
var current_anim: String = ""
var spawn_position: Vector2 = Vector2.ZERO
var is_returning_home: bool = false

# NEW: see NAVIGATION section below.
var nav_agent: NavigationAgent2D = null


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	hp = max_hp
	add_to_group("enemies")
	spawn_position = global_position

	# NEW: enemies are on collision layer 4, but their mask only included
	# 1 and 2 (walls, player) — layer 4 itself was missing, meaning
	# enemies genuinely could not detect or collide with each other at
	# all. adding it here means enemies now physically block one another
	# via normal move_and_slide() collision, producing a real "line up
	# next to the target" formation instead of visually overlapping —
	# replaces the old soft push-apart force below, which is now
	# redundant (and would fight against real collision the same way
	# navigation and that force fought each other earlier).
	set_collision_mask_value(4, true)

	_resolve_player()
	_wire_attack_timer()
	_wire_healthbar()
	_wire_animated_sprite()
	_setup_navigation()

	play_idle_animation("down")


func _physics_process(_delta: float) -> void:
	# CHANGED: was `player == null`. A FREED node is not null — it's a
	# dangling reference — so that check passed a dead player straight
	# through to global_position below and threw "Attempt to call function on
	# a previously freed instance". is_instance_valid() catches both null and
	# freed, and re-resolving means an enemy whose target died or left picks
	# up a new one instead of erroring every frame. This matters more with
	# several players around than it did with one.
	if not is_instance_valid(player):
		_resolve_player()
		return

	if not is_returning_home:
		attack_direction = _get_direction_to_player()

	if is_attacking:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var dist_to_player: float = global_position.distance_to(player.global_position)

	if dist_to_player > leash_range:
		_handle_return_home()
		return

	is_returning_home = false
	_handle_combat(dist_to_player)


# =============================================================================
# NAVIGATION  (NEW)
# =============================================================================
# a NavigationAgent2D computes a path around static obstacles (walls) for
# the "chase toward player" case, instead of the old straight-line
# approach that got enemies stuck pushing against any wall between them
# and the player — harmless in town's open layout, a real problem in a
# scene with actual corridors.
#
# IMPORTANT — this code alone isn't sufficient: it needs a
# NavigationRegion2D with a baked NavigationPolygon covering the walkable
# floor area of whatever scene the enemy is placed in. without that,
# there's no navigable map for the agent to route through, and
# get_next_path_position() effectively degrades toward the same
# straight-line behavior as before. that region/polygon is scene-editor
# setup, not something this script creates.
#
# movement stays strictly 4-directional, matching this game's established
# convention (enemy movement, wall collision, and animation all assume
# cardinal-only motion) — the agent computes a smart PATH, but each step
# still snaps to the nearest cardinal via the same _get_direction_from_vec
# helper already used everywhere else in this file, not free-angle
# diagonal movement.
#
# WALL-SLIDE FALLBACK (NEW): navmesh waypoints are free-angle points on an
# open polygon — a waypoint can sit diagonally from the enemy, needing
# (say) an up-then-left approach to actually reach it. converting that
# into a SINGLE cardinal step picks whichever axis is more dominant, and
# if THAT specific axis happens to run straight into a wall — even though
# the other axis would clear it fine — the enemy pushes against that wall
# forever, never advancing. _prefer_secondary_axis tracks whether the
# enemy has been GENUINELY stuck for several consecutive frames; if so,
# the NEXT frame tries the other axis instead of repeating the same
# blocked direction indefinitely.
#
# CHANGED: originally reacted to a single frame's movement dipping below
# 1.0 units — but normal movement at typical enemy speeds is only ~1.3
# units per physics frame to begin with, so totally normal, unblocked
# movement could dip below the threshold for one frame, falsely trigger
# the fallback, look slow on the OTHER axis too, flip back — a rapid,
# noisy oscillation. now requires several CONSECUTIVE stuck frames before
# actually switching, with a more forgiving distance threshold.
#
# avoidance_enabled is deliberately OFF: enemies now have real
# collision with each other (see the collision_mask change in _ready())
# instead of the old soft push-apart force — turning on the nav agent's
# own avoidance too would mean two separate systems fighting over the
# same job.
const STUCK_DISTANCE_THRESHOLD := 2.0
const STUCK_FRAMES_BEFORE_SWITCH := 5

# NEW: if even the axis-swap fallback hasn't resolved things after this
# much longer, the real problem likely isn't a static wall — it's another
# enemy also trying to reach a nearby/conflicting slot, and both enemies
# swapping axes can just steer them back into each other repeatedly (a
# standoff neither side's local axis-swap can break on its own). at this
# point the enemy gives up on its current slot entirely and claims a
# different one — a bigger, more decisive move than nudging direction,
# which is what actually breaks a two-enemy deadlock.
const STUCK_FRAMES_BEFORE_RECLAIM := 24

var _prefer_secondary_axis: bool = false
var _stuck_frame_count: int = 0

func _setup_navigation() -> void:
	nav_agent = NavigationAgent2D.new()
	nav_agent.avoidance_enabled = false
	nav_agent.path_desired_distance = 8.0
	nav_agent.target_desired_distance = 8.0
	add_child(nav_agent)


# =============================================================================
# SLOT SYSTEM  (NEW)
# =============================================================================
# instead of every enemy pathing directly toward the player's raw
# position — which is what caused enemies to converge and physically
# fight over the same space once real enemy-to-enemy collision was added
# — each enemy claims one of a fixed set of slots arranged in two
# concentric rings around the player, and paths toward THAT slot's
# position instead. slots are shared across ALL enemy instances (a
# static var), so enemies naturally spread out into a surrounding
# formation instead of competing for the same spot. if a slot's owner
# dies or gives up chasing, the slot frees up automatically and the next
# enemy that needs one claims it.
#
# CHANGED AGAIN: was a free-angle ring system (12+16 slots at arbitrary
# angles, radius-scaled). replaced with a true discrete tile grid — the
# player is treated as occupying a 3x3 tile footprint (9 tiles) centered
# on them, and enemies claim individual tiles in the ring immediately
# surrounding that footprint (Chebyshev distance 2 = a 5x5 area minus the
# inner 3x3 = 16 tiles), then further rings out automatically if more
# enemies need space than one ring holds. WHY the switch: the cardinal
# direction picker (abs(x) > abs(y) in _get_direction_from_vec) is
# inherently unstable whenever a target sits near a 45° angle from the
# enemy — small position changes each frame can flip which axis "wins,"
# and free-angle ring slots put a lot of targets close to exactly that
# unstable zone. a real grid mostly avoids this, since most tile offsets
# aren't at 45° — only the true diagonal corner tiles are.
#
# CHANGED: reduced from 32 to 20 for a tighter, closer formation — this
# is a tunable value, adjust further if it still feels too spread out or
# starts feeling cramped once you see it in motion.
const TILE_SIZE := 20.0
const FORMATION_RING_COUNT := 3  # generates 16 + 24 + 32 = 72 slots — comfortably more than any realistic simultaneous encounter

# NEW: once within this many pixels of the claimed slot, stop and hold
# an idle pose instead of continuing to chase it. WHY: right at the
# point of essentially arriving, tiny positional noise (from collision
# resolution against another enemy, or the player themselves shifting
# slightly) can still flip which axis "wins" in the cardinal direction
# picker every frame — even though the enemy isn't meaningfully moving
# anymore. that's what looked like animations "flipping out" despite the
# formation itself being correctly shaped.
const SLOT_ARRIVAL_THRESHOLD := 6.0

# built once, lazily on first use — each entry is {"tile_offset": Vector2i}.
# ring N (1-indexed) = every tile at Chebyshev distance (N+1) from the
# player's own tile, i.e. ring 1 is the 16-tile perimeter just outside
# the 3x3 player footprint, ring 2 the next perimeter out, etc.
static var SLOT_DEFS: Array = []

static func _ensure_slot_defs_built() -> void:
	if not SLOT_DEFS.is_empty():
		return
	for ring in range(1, FORMATION_RING_COUNT + 1):
		var d: int = ring + 1
		for dx in range(-d, d + 1):
			for dy in range(-d, d + 1):
				if max(abs(dx), abs(dy)) == d:
					SLOT_DEFS.append({"tile_offset": Vector2i(dx, dy)})

static var _slot_owners: Dictionary = {}  # slot_index (int) -> enemy instance

var _claimed_slot: int = -1

# NEW: excluded from the very next claim attempt, so releasing a
# genuinely blocked slot (see STUCK-RECLAIM in _record_nav_movement_result
# below) doesn't just immediately re-claim that same slot again if
# nothing else has changed yet.
var _last_released_slot: int = -1


# returns the world-space position this enemy should actually path
# toward — its claimed tile around the player. tile_size defaults to one
# real grid tile (TILE_SIZE); pass a larger value to hold further out
# (e.g. for a ranged class), without changing the grid's actual shape.
func _get_slot_target_position(tile_size: float = TILE_SIZE) -> Vector2:
	if not is_instance_valid(player):
		return global_position

	_ensure_slot_claimed()
	if _claimed_slot == -1:
		return player.global_position

	var offset: Vector2i = SLOT_DEFS[_claimed_slot]["tile_offset"]
	return player.global_position + Vector2(offset.x, offset.y) * tile_size


func _ensure_slot_claimed() -> void:
	_ensure_slot_defs_built()

	# already own a valid slot — keep it. reshuffling every frame would
	# just make enemies constantly swap places instead of settling.
	if _claimed_slot != -1 and _slot_owners.get(_claimed_slot) == self:
		return

	for i in range(SLOT_DEFS.size()):
		if i == _last_released_slot:
			continue  # don't immediately re-claim the slot just given up on
		var slot_owner = _slot_owners.get(i)
		if slot_owner == null or not is_instance_valid(slot_owner):
			_slot_owners[i] = self
			_claimed_slot = i
			_last_released_slot = -1
			return

	# every slot already taken by a still-valid enemy — none available
	# right now (would need more than 28 simultaneous chasers).
	# _get_slot_target_position falls back to the player's raw position
	# in this case; real collision with whoever owns the nearest slot
	# still prevents actual overlap.
	_claimed_slot = -1


# called on death, on giving up a chase (return-home), and on getting
# genuinely stuck trying to reach the current slot (see STUCK-RECLAIM
# below) — so another enemy (or this same one, next attempt) can claim
# the slot instead of it staying reserved forever.
func _release_slot() -> void:
	if _claimed_slot != -1 and _slot_owners.get(_claimed_slot) == self:
		_slot_owners.erase(_claimed_slot)
	_last_released_slot = _claimed_slot
	_claimed_slot = -1



# generalized to any target point (not just the player) so subclasses
# with their own movement override — see BushMage._move_toward_player —
# can share this same navigation + wall-slide-fallback logic rather than
# duplicating it.
func _get_direction_to_point_via_navigation(target_pos: Vector2) -> String:
	# CHANGED: check for a clear, unobstructed line to the target FIRST.
	# if there's nothing in the way, just go straight there — simple,
	# predictable, and each enemy's own line naturally spreads out based
	# on its own position, same as before this whole navigation system
	# existed. only fall back to nav-agent routing when a wall genuinely
	# blocks the direct line. this is what fixes multiple enemies
	# bunching into each other: without this gate, several enemies
	# chasing the same target through the same narrow navmesh converge
	# onto nearly the same path, fighting against the existing
	# stacking-avoidance system (push apart, path back together, repeat).
	if _has_line_of_sight(target_pos):
		_prefer_secondary_axis = false
		_stuck_frame_count = 0
		return _get_direction_from_vec(target_pos - global_position)

	if nav_agent == null:
		return _get_direction_from_vec(target_pos - global_position)

	nav_agent.target_position = target_pos
	var next_point: Vector2 = nav_agent.get_next_path_position()
	var to_waypoint: Vector2 = next_point - global_position

	if _prefer_secondary_axis:
		return _get_secondary_direction_from_vec(to_waypoint)
	return _get_direction_from_vec(to_waypoint)


# raycasts through PHYSICS collision (walls) to check for a clear line to
# the target — deliberately physics, not navigation, since this is the
# "do I even need pathfinding right now" gate, separate from the actual
# routing logic above.
#
# NOTE: collision_mask is set to layer 1 below, the most common default
# for world/ground geometry — but I don't have visibility into this
# project's actual collision layer setup. if walls live on a different
# layer, or if this raycast is incorrectly hitting other enemies/the
# player themselves, adjust the mask value to match whatever layer your
# wall collision actually uses.
func _has_line_of_sight(target_pos: Vector2) -> bool:
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, target_pos)
	query.exclude = [self]
	query.collision_mask = 1
	var result := space_state.intersect_ray(query)
	return result.is_empty()


func _get_direction_to_player_via_navigation() -> String:
	if not is_instance_valid(player):
		return _get_direction_to_player()
	return _get_direction_to_point_via_navigation(player.global_position)


func _get_secondary_direction_from_vec(vec: Vector2) -> String:
	# the OPPOSITE axis choice from _get_direction_from_vec — the
	# wall-slide fallback described above.
	if abs(vec.x) > abs(vec.y):
		if vec.y == 0:
			return ""
		return "down" if vec.y > 0 else "up"
	else:
		if vec.x == 0:
			return ""
		return "right" if vec.x > 0 else "left"


# called after move_and_slide() by any caller using navigation-routed
# movement — tracks CONSECUTIVE frames of minimal movement (see the
# CHANGED note above for why a single-frame check was too noisy) and only
# flips _prefer_secondary_axis on once genuinely, persistently stuck.
# resets immediately the moment real movement resumes, on either axis.
#
# NEW: escalates further if the axis-swap alone still isn't working —
# see STUCK_FRAMES_BEFORE_RECLAIM's comment above for why (most likely
# another enemy contesting a nearby slot, not a static wall). releasing
# the slot here means the very next _get_slot_target_position call
# (next frame) claims a different one automatically.
func _record_nav_movement_result(pos_before: Vector2) -> void:
	var moved_distance: float = global_position.distance_to(pos_before)

	if moved_distance < STUCK_DISTANCE_THRESHOLD:
		_stuck_frame_count += 1
	else:
		_stuck_frame_count = 0
		_prefer_secondary_axis = false

	_prefer_secondary_axis = _stuck_frame_count >= STUCK_FRAMES_BEFORE_SWITCH

	if _stuck_frame_count >= STUCK_FRAMES_BEFORE_RECLAIM:
		_release_slot()
		_stuck_frame_count = 0
		_prefer_secondary_axis = false


# =============================================================================
# INITIALIZATION HELPERS
# =============================================================================

func _resolve_player() -> void:
	# CHANGED: was players[0] — whichever player node happened to sit first
	# in the group. With exactly one player that is always the right answer,
	# so this changes NOTHING in single-player. With two it was an arbitrary
	# pick, and once this is networked it could resolve to a different player
	# on each client, so every machine would disagree about who an enemy is
	# chasing. Nearest is a real rule; first-in-group was an accident.
	#
	# SCOPE: this is target ACQUISITION, not aggro. It doesn't re-evaluate
	# while a target stays valid, so an enemy won't flip mid-fight to whoever
	# steps closer. Real aggro — threat, taunts, switching — is a decision
	# the server has to own, and inventing it here before that server exists
	# would just be something to throw away later.
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		player = null
		return

	if players.size() == 1:
		player = players[0]
		return

	var nearest: Node = null
	var nearest_dist: float = INF
	for candidate in players:
		if not is_instance_valid(candidate):
			continue
		# distance_squared_to: ordering by squared distance is identical to
		# ordering by distance, and skips a sqrt per player per scan.
		var d: float = global_position.distance_squared_to(candidate.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = candidate

	player = nearest


func _wire_attack_timer() -> void:
	if not has_node("attacktimer"):
		return
	$attacktimer.wait_time = attack_cooldown
	$attacktimer.one_shot  = true
	if not $attacktimer.timeout.is_connected(_on_attack_timer_timeout):
		$attacktimer.timeout.connect(_on_attack_timer_timeout)


func _on_attack_timer_timeout() -> void:
	attack_ready = true


func _wire_healthbar() -> void:
	if not has_node("healthbar"):
		return
	var bar: Range = $healthbar
	bar.min_value = 0
	bar.max_value = max_hp
	bar.step      = 1
	bar.value     = hp


func _wire_animated_sprite() -> void:
	if not has_node("animatedsprite2d"):
		return
	var sprite: AnimatedSprite2D = $animatedsprite2d
	if not sprite.animation_finished.is_connected(_on_animation_finished):
		sprite.animation_finished.connect(_on_animation_finished)


func _on_animation_finished() -> void:
	if not has_node("animatedsprite2d"):
		return
	var sprite: AnimatedSprite2D = $animatedsprite2d
	if sprite.animation.begins_with("attack"):
		is_attacking = false
		play_idle_animation(attack_direction)


# =============================================================================
# COMBAT / MOVEMENT
# =============================================================================

func _handle_combat(dist_to_player: float) -> void:
	if dist_to_player < flee_range:
		_release_slot()
		# CHANGED: was a naive straight-line flee direction with zero
		# wall-awareness. if that direction happened to point into a wall
		# (enemy cornered), it kept pushing into it indefinitely while
		# blocked — and since its collision shape stayed pinned there, an
		# approaching player could get caught on it too, feeling exactly
		# like getting stuck on a wall that started pulling them
		# (confirmed directly — that's the reported symptom). now routes
		# through the same navigation-aware helper already proven for
		# chasing: a flee TARGET point further away along the flee
		# direction, with the same line-of-sight-first, wall-slide-
		# fallback-if-blocked behavior, so a cornered enemy tries an
		# alternate route instead of pushing into a wall forever.
		var flee_target: Vector2 = global_position + (global_position - player.global_position).normalized() * 100.0
		var flee_pos_before: Vector2 = global_position
		var flee_dir: String = _get_direction_to_point_via_navigation(flee_target)
		velocity = _vec_from_dir(flee_dir) * get_move_speed()
		move_and_slide()
		play_walk_animation(flee_dir)
		_record_nav_movement_result(flee_pos_before)
		return

	if dist_to_player < attack_range:
		velocity = Vector2.ZERO
		if attack_ready:
			_trigger_attack()
		else:
			play_idle_animation(attack_direction)
		return

	# CHANGED: routes toward this enemy's claimed tile around the player
	# (see SLOT SYSTEM section above) instead of the player's raw
	# position directly — this is what actually spreads multiple enemies
	# out into a real surrounding formation instead of all converging on
	# the same spot. uses the default TILE_SIZE spacing (real grid tiles,
	# not attack_range-scaled) since the grid's spacing is now tied to
	# the actual world tile size, not this enemy's attack range.
	var slot_target: Vector2 = _get_slot_target_position()

	# NEW: essentially arrived at the claimed slot — stop and hold
	# instead of continuing to chase it. see SLOT_ARRIVAL_THRESHOLD's
	# comment above for why this is what actually stops the
	# animation-flip jitter at close range.
	if global_position.distance_to(slot_target) < SLOT_ARRIVAL_THRESHOLD:
		velocity = Vector2.ZERO
		move_and_slide()
		play_idle_animation(attack_direction)
		return

	var pos_before: Vector2 = global_position
	var to_player: String = _get_direction_to_point_via_navigation(slot_target)
	velocity = _vec_from_dir(to_player) * get_move_speed()
	move_and_slide()
	play_walk_animation(to_player)
	_record_nav_movement_result(pos_before)


func _handle_return_home() -> void:
	_release_slot()
	var dist_from_spawn: float = global_position.distance_to(spawn_position)

	if dist_from_spawn > HOME_ARRIVAL_THRESHOLD:
		is_returning_home = true
		var return_dir: String = _get_direction_from_vec(spawn_position - global_position)
		velocity = _vec_from_dir(return_dir) * get_move_speed()
		move_and_slide()
		play_walk_animation(return_dir)
	else:
		is_returning_home = false
		velocity = Vector2.ZERO
		play_idle_animation("down")


func _trigger_attack() -> void:
	attack_ready = false
	is_attacking = true
	if has_node("attacktimer"):
		$attacktimer.start()
	play_attack_animation(attack_direction)


# =============================================================================
# SUBCLASS OVERRIDE POINTS
# =============================================================================

func get_move_speed() -> float:
	return 80.0


func fire_projectile() -> void:
	pass


# =============================================================================
# PROJECTILE SPAWNING
# =============================================================================

func spawn_projectile_node(projectile: Node, spawn_pos: Vector2) -> void:
	# parent a projectile into the y-sorted "projectiles" container so it
	# depth-sorts correctly against characters. falls back to the scene root
	# if the container is missing (wrongly-sorted but still functional).
	#
	# add_child + position are BOTH deferred: deferred add avoids the
	# "can't change state while flushing queries" physics error when a
	# projectile spawns during a collision, and deferred position ensures
	# global_position is applied AFTER the node is actually in the tree.
	var container: Node = get_tree().get_first_node_in_group("projectiles")
	if container == null:
		container = get_tree().current_scene
	container.add_child.call_deferred(projectile)
	projectile.set_deferred("global_position", spawn_pos)


# =============================================================================
# ANIMATION HELPERS
# =============================================================================

func _set_animation(new_anim: String) -> void:
	if new_anim == "" or not has_node("animatedsprite2d"):
		return
	if new_anim == current_anim:
		return

	var sprite: AnimatedSprite2D = $animatedsprite2d
	if not sprite.sprite_frames.has_animation(new_anim):
		push_warning("%s: missing animation '%s'" % [name, new_anim])
		return

	current_anim = new_anim
	sprite.play(new_anim)


func play_walk_animation(dir: String) -> void:
	if dir != "":
		_set_animation("walk" + dir)


func play_attack_animation(dir: String) -> void:
	if dir != "":
		_set_animation("attack" + dir)


func play_idle_animation(dir: String) -> void:
	if dir != "":
		_set_animation("idle" + dir)


# =============================================================================
# DIRECTION HELPERS
# =============================================================================

func _get_direction_to_player() -> String:
	if not is_instance_valid(player):
		return attack_direction
	return _get_direction_from_vec(player.global_position - global_position)


func _get_direction_from_vec(vec: Vector2) -> String:
	if abs(vec.x) > abs(vec.y):
		return "right" if vec.x > 0 else "left"
	elif abs(vec.y) > 0:
		return "down" if vec.y > 0 else "up"
	return ""


func _vec_from_dir(dir: String) -> Vector2:
	match dir:
		"left":  return Vector2.LEFT
		"right": return Vector2.RIGHT
		"up":    return Vector2.UP
		"down":  return Vector2.DOWN
	return Vector2.ZERO


# =============================================================================
# DAMAGE AND DEATH
# =============================================================================

# NEW: has the death path already run for this enemy?
#
# queue_free() is DEFERRED to the end of the frame, so a dead enemy is still a
# live node for the rest of that frame - and two things landing in the same
# frame both reach take_damage(). Enemies carry several shapes on the enemies
# layer at once (bushmage has a hurtbox plus four overlapping attack boxes), so
# one shot genuinely can register twice.
#
# Without this, the second hit re-ran the whole death path: XP granted twice,
# a second loot bag spawned, and a second INDEPENDENT pet roll - on the rarest
# drop in the game.
var _death_resolved: bool = false


func take_damage(amount: int, _type: StringName = &"physical") -> void:
	if _death_resolved:
		return

	hp = max(hp - amount, 0)
	damaged.emit(amount)

	_spawn_floating_label(amount, 0)

	if has_node("healthbar"):
		var bar: Range = $healthbar
		if bar.max_value != max_hp:
			bar.max_value = max_hp
		bar.value = hp

	if hp <= 0:
		_die()


func _die() -> void:
	# Second layer of the same guard. take_damage() is the usual route in, but
	# anything holding a reference can call _die() directly, and the loot roll
	# must not be reachable twice by any path.
	if _death_resolved:
		return
	_death_resolved = true

	_release_slot()

	var killer: Node = player

	if killer and killer.has_method("gain_xp"):
		killer.gain_xp(xp_reward)
		if killer.has_method("gain_attack_xp"):
			killer.gain_attack_xp(attack_xp_reward)

	_roll_and_spawn_loot(killer)

	died.emit()
	queue_free()


# =============================================================================
# DROPS
# =============================================================================

func _roll_and_spawn_loot(killer: Node) -> void:
	var pet_won: bool = _roll_pet()
	var bag_drops: bool = randf() <= bag_drop_chance

	if not bag_drops and not pet_won:
		return

	var contents: Array = _build_bag_contents()

	if pet_won:
		contents.append({ "item_id": pet_drop_id, "quantity": 1 })

	_spawn_loot_bag(contents, killer, pet_won)


func _roll_pet() -> bool:
	if pet_drop_id == "":
		return false
	if not ItemRegistry.has_item(pet_drop_id):
		return false

	var d1: int = randi_range(1, 6)
	var d2: int = randi_range(1, 6)
	var d3: int = randi_range(1, 6)
	return d1 == 6 and d2 == 6 and d3 == 6


func _build_bag_contents() -> Array:
	var contents: Array = []

	# gold: UNTOUCHED — guaranteed on every bag, no rarity gate. this is
	# intentional and already matches the "currency flows freely, items
	# are scarce" design goal — see class comment.
	var gold_amount: int = randi_range(max_loot_tier, max_loot_tier * 25)
	var gold_id: String = GOLD_LARGE_ID if gold_amount >= LARGE_GOLD_THRESHOLD else GOLD_SMALL_ID
	if ItemRegistry.has_item(gold_id):
		contents.append({ "item_id": gold_id, "quantity": gold_amount })

	# items: fewer, lower-odds rolls than before — see class comment.
	for i in range(max_item_slots):
		if randf() <= slot_fill_chance:
			var picked_id: String = _pick_weighted_item_id(max_loot_tier)
			if picked_id != "":
				contents.append({ "item_id": picked_id, "quantity": 1 })

	return contents


func _pick_weighted_item_id(max_tier: int) -> String:
	var candidates: Array = []
	var weights: Array = []
	var total_weight: int = 0

	for item in ItemRegistry.get_all_items():
		if item.tier > max_tier:
			continue
		if item.type == ItemData.Type.PET:
			continue
		if item.type == ItemData.Type.QUEST:
			continue
		if item.type == ItemData.Type.CURRENCY:
			continue

		var tier_gap: int = max_tier - item.tier
		var w: int = int(pow(2, max(tier_gap, 0)))
		if w < 1:
			w = 1

		candidates.append(item.item_id)
		weights.append(w)
		total_weight += w

	if candidates.is_empty() or total_weight <= 0:
		return ""

	var roll: int = randi() % total_weight
	var cumulative: int = 0
	for i in range(candidates.size()):
		cumulative += weights[i]
		if roll < cumulative:
			return candidates[i]

	return candidates[candidates.size() - 1]


func _spawn_loot_bag(contents: Array, killer: Node, has_pet: bool) -> void:
	if LOOTBAG_SCENE == null:
		push_warning("BaseEnemy: LOOTBAG_SCENE not loaded — no bag spawned")
		return

	var bag: Node = LOOTBAG_SCENE.instantiate()
	bag.global_position = global_position

	call_deferred("_finish_spawn_loot_bag", bag, contents, killer, has_pet)


func _finish_spawn_loot_bag(bag: Node, contents: Array, killer: Node, has_pet: bool) -> void:
	# parent loot bags into the y-sorted world so they sort with characters.
	# prefer a "lootbags" container, fall back to "projectiles", then scene root.
	var container: Node = get_tree().get_first_node_in_group("lootbags")
	if container == null:
		container = get_tree().get_first_node_in_group("projectiles")
	if container == null:
		container = get_tree().current_scene
	container.add_child(bag)

	if bag.has_method("set_contents"):
		bag.set_contents(contents)
	if bag.has_method("set_owner_player"):
		bag.set_owner_player(killer)
	if bag.has_method("set_has_pet"):
		bag.set_has_pet(has_pet)


# =============================================================================
# UI / VISUAL EFFECTS
# =============================================================================

func _spawn_floating_label(amount: int, type: int) -> void:
	# damage numbers go to the FloatingLabels container (always-on-top,
	# not y-sorted) if it exists, else fall back to the scene root.
	var lbl: Node = FLOATING_LABEL_SCENE.instantiate()
	var container: Node = get_tree().get_first_node_in_group("floatinglabels")
	if container == null:
		container = get_tree().current_scene
	container.add_child(lbl)
	lbl.global_position = global_position + Vector2(0, -30)
	lbl.show_number(amount, type, 0.5)
