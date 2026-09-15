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
# PET DROP ODDS BY LOOT TIER
# =============================================================================
# "one in N per kill", keyed by the enemy's max_loot_tier. An enemy only ever
# drops its OWN pet variant (pet_drop_id), so this number is literally how
# many of that specific enemy you expect to kill for that specific pet — it is
# not competing with any other pet in a shared pool.
#
# ANCHORED ON THE DICE THIS REPLACES. The old _roll_pet() rolled 3d6 and
# required all three sixes: exactly 1 in 216. Tier 3 keeps that number, so the
# enemies that already felt right are unchanged, and the other tiers are tuned
# around it rather than invented from nothing.
#
# Powers of six alone are too coarse to tune across four tiers (the next step
# down from 216 is 1296 — a 6x jump), so these are plain "1 in N" integers.
# Change any number here and only that tier moves.
#
#   tier 1 -> 1 in 1296   weakest trash; you kill a great many of them
#   tier 2 -> 1 in 648    mid-tier
#   tier 3 -> 1 in 216    unchanged from the original triple-six
#   tier 4 -> 1 in 108    reserved for the boss
const PET_ODDS_BY_TIER := {
	1: 1296,
	2: 648,
	3: 216,
	4: 108,
}

# Used when max_loot_tier isn't in the table above (a tier 5+ enemy added
# later, or a corrupted value). Deliberately on the stingy side: a missing
# entry should never accidentally make a pet common.
const PET_ODDS_FALLBACK := 1296


# =============================================================================
# EXPORTED SETTINGS
# =============================================================================

# THE ENEMY'S REWARD PROFILE — everything that decides what a kill is worth.
#
# Subclasses assign this from a .tres in data/enemies/ at the top of their
# _ready(), and _apply_enemy_data() below copies it into the fields underneath.
#
# WHY IT IS A RESOURCE AND NOT A BLOCK OF ASSIGNMENTS:
# these numbers used to be statements inside each subclass's _ready(), executed
# at spawn time on the player's machine. That works only while the CLIENT
# decides what a kill is worth. The server cannot read a statement — the export
# tool proved it, instantiating every enemy scene and writing out five identical
# enemies with the defaults below, because no script had run. As data it can be
# read by Godot and by Python, from one authored file.
@export var enemy_data: EnemyData

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

# How good this enemy's drops can get. Gates item rolls (nothing above this
# tier can appear — see _pick_weighted_item_id), scales gold, and now sets the
# pet odds via PET_ODDS_BY_TIER below.
#
# EVERY ENEMY LEFT THIS AT 1 UNTIL NOW, which had a consequence nobody would
# have guessed from reading it: _pick_weighted_item_id() skips any item whose
# tier exceeds max_tier, so tinyhealthpotion (tier 2) could not drop from
# ANYTHING in the game. It wasn't rare, it was unreachable. Each subclass sets
# this in _ready() now, next to its max_hp.
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

# Optional SECOND pet for the same enemy, awarded instead of pet_drop_id on
# a winning roll — see _pick_pet_id(). Empty (the default) means this enemy
# has exactly one pet and rare_pet_chance is ignored entirely.
#
# Used by the poison slime, which can give either the small or the large
# slime companion from one kill, but never both.
@export var rare_pet_drop_id: String = ""

# Probability (0..1) that a winning pet roll awards rare_pet_drop_id rather
# than pet_drop_id. Only consulted when rare_pet_drop_id is set.
@export var rare_pet_chance: float = 0.25

# Per-enemy override for the pet odds. 0 means "use PET_ODDS_BY_TIER".
# Set this in the Inspector when one specific enemy should differ from every
# other enemy at its tier.
@export var pet_odds_override: int = 0


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
	# FIRST, before anything reads these fields — `hp = max_hp` on the very next
	# line would otherwise fill the health pool from BaseEnemy's default of 50
	# rather than this enemy's real maximum.
	_apply_enemy_data()

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
# CHANGED: "stuck" is now measured against how far this enemy SHOULD have
# moved, and counted in seconds rather than frames.
#
# The old test was `moved_distance < 2.0` per physics frame. The project runs
# at 180 physics ticks per second, and the fastest enemy in the game is the
# small slime at 70 px/s - which is 0.39 px per frame. So a perfectly healthy
# enemy moving at full speed was ALWAYS under the 2.0 threshold, the counter
# incremented every single frame, and the else-branch that resets it was
# unreachable during normal movement.
#
# The visible result: every enemy flipped to its secondary axis after 28ms and
# called _release_slot() after 133ms, forever. Formation slots were dropped and
# re-claimed about seven times a second, so enemies never settled into the ring
# and bunched around the player instead - the exact thing the slot system was
# built to prevent.
#
# A fraction of expected movement is both tick-rate independent and speed
# independent, which the old constant was neither.
const STUCK_MOVE_FRACTION := 0.25
const STUCK_SECONDS_BEFORE_SWITCH := 0.08

# NEW: if even the axis-swap fallback hasn't resolved things after this
# much longer, the real problem likely isn't a static wall — it's another
# enemy also trying to reach a nearby/conflicting slot, and both enemies
# swapping axes can just steer them back into each other repeatedly (a
# standoff neither side's local axis-swap can break on its own). at this
# point the enemy gives up on its current slot entirely and claims a
# different one — a bigger, more decisive move than nudging direction,
# which is what actually breaks a two-enemy deadlock.
const STUCK_SECONDS_BEFORE_RECLAIM := 0.4

var _prefer_secondary_axis: bool = false
var _stuck_time: float = 0.0

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
const FORMATION_RING_COUNT := 3

# Tiles between one slot and the next.
#
# WAS EFFECTIVELY 1, which is why enemies looked piled even when the formation
# was working. A slot is 20px from its neighbour, but the large slime's sprite
# is 31px wide - so two enemies standing in adjacent slots overlap by 11px, and
# their collision bodies (radius 5, so 10px across) are far too small for
# physics to push them apart. The art was three times wider than the thing
# keeping them separated.
#
# A stride of 2 puts a full empty tile between every pair of neighbours: 40px
# between centres against a 31px sprite, so roughly 9px of clear ground. That
# is the "solid square apart" spacing.
#
# Ring 1 still sits 40px from the player, so no attack range changes.
# Slot count goes 8 + 16 + 24 = 48, still more than any real encounter.
const FORMATION_SLOT_STRIDE := 2

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
		var d: int = ring * FORMATION_SLOT_STRIDE
		for dx in range(-d, d + 1, FORMATION_SLOT_STRIDE):
			for dy in range(-d, d + 1, FORMATION_SLOT_STRIDE):
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
	var raw: Vector2 = player.global_position + Vector2(offset.x, offset.y) * tile_size

	# CLAMPED, because a slot is just an arithmetic offset from the player and
	# arithmetic knows nothing about walls. Stand the player against geometry
	# and half the formation ring lands INSIDE it - enemies then path toward a
	# point that does not exist, grind into the wall, and pile up at the
	# nearest corner because they are all failing in the same direction.
	return clamp_to_navigation(raw)


func _ensure_slot_claimed() -> void:
	_ensure_slot_defs_built()

	# already own a valid slot — keep it. reshuffling every frame would
	# just make enemies constantly swap places instead of settling.
	if _claimed_slot != -1 and _slot_owners.get(_claimed_slot) == self:
		return

	# NEAREST free slot, not the first one in the list.
	#
	# SLOT_DEFS is built ring by ring in a fixed order, so taking the first
	# free entry handed out tiles by index rather than by proximity. An enemy
	# approaching from the south would happily claim a tile on the NORTH side
	# and walk straight through the player to reach it - so chasers crossed
	# each other's paths and bunched in transit, which is what the formation
	# was supposed to stop. Picking the closest free tile means each enemy
	# settles on its own side and paths stop intersecting.
	if not is_instance_valid(player):
		_claimed_slot = -1
		return

	var anchor: Vector2 = player.global_position

	# Gather the free slots and sort by how close they are to US, then take the
	# first one that is actually standable. Sorting before validating keeps the
	# navmesh queries cheap - the nearest slot is usually fine, so this costs
	# one or two lookups rather than one per slot.
	var candidates: Array = []
	for i in range(SLOT_DEFS.size()):
		if i == _last_released_slot:
			continue  # don't immediately re-claim the slot just given up on

		var slot_owner = _slot_owners.get(i)
		if slot_owner != null and is_instance_valid(slot_owner):
			continue

		var offset: Vector2i = SLOT_DEFS[i]["tile_offset"]
		var slot_world: Vector2 = anchor + Vector2(offset.x, offset.y) * TILE_SIZE
		candidates.append({
			"index": i,
			"world": slot_world,
			"distance": global_position.distance_squared_to(slot_world),
		})

	candidates.sort_custom(func(a, b): return a["distance"] < b["distance"])

	for candidate in candidates:
		# A slot the navmesh has to drag more than half a tile to reach is a
		# slot inside a wall. Claiming it means walking at geometry forever, so
		# skip to the next nearest instead - which naturally spreads enemies
		# onto the side of the player that is actually open.
		var world: Vector2 = candidate["world"]
		if clamp_to_navigation(world).distance_to(world) > TILE_SIZE * 0.5:
			continue

		_slot_owners[candidate["index"]] = self
		_claimed_slot = candidate["index"]
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
		_stuck_time = 0.0
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
	# the OPPOSITE axis choice from _get_direction_from_vec - the wall-slide
	# fallback described above. The arithmetic lives in Facing now; this stays
	# as a name the navigation code already calls.
	return Facing.secondary_from_vec(vec)


# called after move_and_slide() by any caller using navigation-routed
# movement — tracks CONSECUTIVE frames of minimal movement (see the
# CHANGED note above for why a single-frame check was too noisy) and only
# flips _prefer_secondary_axis on once genuinely, persistently stuck.
# resets immediately the moment real movement resumes, on either axis.
#
# NEW: escalates further if the axis-swap alone still isn't working —
# see STUCK_SECONDS_BEFORE_RECLAIM's comment above for why (most likely
# another enemy contesting a nearby slot, not a static wall). releasing
# the slot here means the very next _get_slot_target_position call
# (next frame) claims a different one automatically.
func _record_nav_movement_result(pos_before: Vector2) -> void:
	var moved_distance: float = global_position.distance_to(pos_before)
	var delta: float = get_physics_process_delta_time()

	# What a clear, unobstructed frame of movement looks like for THIS enemy at
	# THIS tick rate. Comparing against a fraction of it is what makes the test
	# survive a change to either.
	var expected_distance: float = get_move_speed() * delta

	if moved_distance < expected_distance * STUCK_MOVE_FRACTION:
		_stuck_time += delta
	else:
		_stuck_time = 0.0
		_prefer_secondary_axis = false

	_prefer_secondary_axis = _stuck_time >= STUCK_SECONDS_BEFORE_SWITCH

	if _stuck_time >= STUCK_SECONDS_BEFORE_RECLAIM:
		_release_slot()
		_stuck_time = 0.0
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


# How far a navmesh snap is allowed to move a point before we refuse it.
#
# NavigationServer2D.map_get_closest_point() returns Vector2.ZERO on an empty
# or unbaked map rather than reporting failure - which is exactly the "walks to
# the world origin" bug this helper exists to prevent. So a snap that displaced
# the point further than any legitimate correction is treated as a bad answer
# and discarded.
const NAV_SNAP_MAX_DISTANCE: float = 240.0


# Pull a position onto the baked navigation mesh.
#
# The invariant this protects: nothing this enemy spawns or walks toward may
# sit outside the walkable world. Physics collision alone does not give you
# that - a body can be PLACED inside a wall, and move_and_slide() will happily
# keep it there. The navmesh is the authority on where the world actually is.
func clamp_to_navigation(pos: Vector2) -> Vector2:
	var world: World2D = get_world_2d()
	if world == null:
		return pos

	var map: RID = world.navigation_map
	if not map.is_valid():
		return pos

	# named nav_point, not snapped — snapped() is a global GDScript function
	# (it rounds a value to the nearest multiple of a step). A local of that
	# name shadows it for the rest of this function, so any later call to the
	# real snapped() here would silently resolve to a Vector2 instead.
	var nav_point: Vector2 = NavigationServer2D.map_get_closest_point(map, pos)
	if nav_point.distance_to(pos) > NAV_SNAP_MAX_DISTANCE:
		return pos

	return nav_point


func _handle_return_home() -> void:
	_release_slot()
	var dist_from_spawn: float = global_position.distance_to(spawn_position)

	if dist_from_spawn > HOME_ARRIVAL_THRESHOLD:
		is_returning_home = true
		# THROUGH NAVIGATION, not a straight line. This used to take the raw
		# vector home and walk it cardinally, which meant an enemy leashing
		# back across any wall ground straight into it - or, when spawn_position
		# was wrong, marched clean off the playable area. The chase already had
		# tested routing that falls back to a direct line when the way is clear;
		# there was never a reason for the walk home to have its own worse copy.
		var return_dir: String = _get_direction_to_point_via_navigation(spawn_position)
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

	# FIXED: EVERY ENEMY PROJECTILE IN THE GAME FLASHED AT THE WORLD ORIGIN
	# before appearing at the muzzle — a streak across the room and straight
	# through walls, one frame long.
	#
	# This project runs physics interpolation, so the renderer draws each node
	# blended between its previous and current physics transforms. A node that
	# has just entered the tree has no meaningful previous transform: it is
	# whatever the projectile scene was authored at, which is (0, 0). So the
	# first rendered frame is a blend from the world origin toward the muzzle.
	#
	# reset_physics_interpolation() collapses previous and current to the same
	# value, leaving nothing to blend. It has to run AFTER global_position is
	# set, which is why it is deferred too — deferred calls flush in the order
	# they were queued, so this lands after the set above rather than before it.
	#
	# WHY IT ONLY SHOWS UP NOW: the streak has always been here, but it lasts
	# exactly one physics tick. At 180 ticks/second that was 5.6ms and invisible.
	# At 80 it is 12.5ms, and 12.5ms of movement is something an eye catches.
	# Identical cause to the mage's sliding spell circle — this is the same bug
	# in the one place every enemy projectile passes through.
	projectile.call_deferred("reset_physics_interpolation")


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
	# Returns "" for a zero vector, which navigation relies on: "no heading" is
	# a real answer and must not be coerced into a direction. The animation code
	# in player.gd wants the opposite - see Facing.from_vec_total().
	return Facing.from_vec(vec)


func _vec_from_dir(dir: String) -> Vector2:
	return Facing.to_vec(dir)


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


func get_enemy_id() -> String:
	# The name this enemy reports to the server when it is killed. Empty means
	# "not a payable enemy" — either no profile was assigned, or this variant
	# deliberately awards nothing, like the large slime that splits instead of
	# dying. Either way the server has nothing to look up and no reason to pay.
	if enemy_data == null:
		return ""
	if not enemy_data.grants_rewards:
		return ""
	return enemy_data.enemy_id


func _apply_enemy_data() -> void:
	# Copies the profile onto this node. The fields stay as @export vars rather
	# than being read through enemy_data everywhere, so every existing reference
	# in this class and its subclasses keeps working unchanged — this is a change
	# of where the numbers COME FROM, not of how they are used.
	if enemy_data == null:
		# Loud, because the failure is otherwise invisible: the enemy works, it
		# fights, it dies, and it quietly pays out BaseEnemy's placeholder
		# defaults instead of its own.
		push_warning("%s: no enemy_data assigned — using BaseEnemy defaults (50 hp, 20 xp, tier 1). Assign one from data/enemies/." % name)
		return

	max_hp            = enemy_data.max_hp
	xp_reward         = enemy_data.xp_reward
	attack_xp_reward  = enemy_data.attack_xp_reward
	bag_drop_chance   = enemy_data.bag_drop_chance
	max_loot_tier     = enemy_data.max_loot_tier
	max_item_slots    = enemy_data.max_item_slots
	slot_fill_chance  = enemy_data.slot_fill_chance
	pet_drop_id       = enemy_data.pet_drop_id
	rare_pet_drop_id  = enemy_data.rare_pet_drop_id
	rare_pet_chance   = enemy_data.rare_pet_chance
	pet_odds_override = enemy_data.pet_odds_override


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

	# TWO SOUNDS FOR ONE EVENT, AND THAT IS DELIBERATE.
	#
	# "attack_hit" is YOUR feedback that you connected — non-positional,
	# because the question it answers is "did that land?", which is about you
	# rather than about where in the world it happened. "enemy_hurt" is the
	# thing out there reacting, so it attenuates with distance.
	#
	# Nothing in this game damages an enemy except the player and their pet, so
	# "an enemy took damage" and "you connected" are the same event. If that
	# ever stops being true, this needs a source argument.
	#
	# Either id can be left empty in audio.gd's registry and the other still
	# works. That is the point of calling by id rather than by stream.
	Audio.play("attack_hit")

	if hp <= 0:
		_die()
		return

	# Survival only. A killing blow gets the death sound instead — otherwise
	# you hear the thing grunt and die in the same frame.
	Audio.play_at("enemy_hurt", global_position)


func _die() -> void:
	# Second layer of the same guard. take_damage() is the usual route in, but
	# anything holding a reference can call _die() directly, and the loot roll
	# must not be reachable twice by any path.
	if _death_resolved:
		return
	_death_resolved = true

	_release_slot()

	# THE SERVER DECIDES WHAT THIS KILL WAS WORTH.
	#
	# This used to grant the XP and roll the loot right here, on the player's
	# machine — which meant a modified client could award itself every pet in
	# the game. Combat.report_kill() posts the enemy's id and renders whatever
	# comes back.
	#
	# NOT AWAITED, and it must not be: queue_free() is two lines down, and a
	# coroutine suspended on a freed node is silently dropped by Godot. Combat
	# is an autoload, so it outlives this corpse and can wait for the network.
	# Position is passed by value for the same reason — global_position will not
	# exist by the time the bag is spawned.
	Combat.report_kill(get_enemy_id(), global_position, player)

	# BEFORE queue_free(), and through the autoload rather than a player node
	# on this enemy. audio.gd's header is about exactly this case: a player
	# parented to the thing making the sound dies with it, so an enemy playing
	# its own death sound gets freed mid-playback. The one sound in the game
	# guaranteed to be cut off would be the one marking a death.
	#
	# global_position is read here rather than passed to a deferred call for
	# the same reason the kill report reads it here — it will not exist in a
	# frame's time.
	Audio.play_at("enemy_death", global_position)

	died.emit()
	queue_free()


# =============================================================================
# DROPS
# =============================================================================

# =============================================================================
# LOOT ROLLING  (REMOVED — THE SERVER DOES THIS NOW)
# =============================================================================
# _roll_and_spawn_loot(), _roll_pet(), _pick_pet_id(), get_pet_odds(),
# _build_bag_contents() and _pick_weighted_item_id() used to live here: about
# 120 lines deciding, on the player's own machine, how much gold dropped, which
# items rolled, and whether the 1-in-864 pet came up.
#
# They are ports in gamedata.py now, rolled with the server's SystemRandom.
# Nothing the client does can make that roll come up more often than it should,
# because the client never runs it.
#
# PET_ODDS_BY_TIER and the GOLD_* constants above stay. They are not used by
# this class any more — exportgamedata.gd reads them out of it, so this file is
# still where those numbers are authored, and gamedata.json is the copy the
# server reads.


# _spawn_loot_bag() and _resolve_loot_container() moved to combat.gd.
#
# They had to. The long comment they carried was about NEVER DEFERRING ONTO THE
# CORPSE — a deferred call onto the dying enemy worked for every enemy except
# the small poison slime, which awaits its death animation, so smalls never
# dropped a bag. Waiting on a network round trip makes that far worse: the
# enemy is certainly gone by the time the response lands.
#
# An autoload is always in the tree, so Combat can hold the position, wait as
# long as it takes, and still resolve a container afterwards.


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
	# Damage numbers streak from the world origin without this — see
	# spawn_projectile_node() for the mechanism.
	lbl.reset_physics_interpolation()
	lbl.show_number(amount, type, 0.5)
