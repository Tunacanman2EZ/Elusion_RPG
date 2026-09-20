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
# THE GOLD CURVE
# =============================================================================
# How much gold one bag holds: randint(unit, unit * GOLD_SPREAD), where `unit`
# steps by GOLD_TIER_RATIO for each loot tier.
#
# WHY THIS IS GEOMETRIC, AND WHY THAT MATTERS MORE THAN THE NUMBERS. The roll
# used to be randint(max_loot_tier, max_loot_tier * 25) — LINEAR in tier. Every
# price in the game is geometric: ItemData.value climbs x2.6 per tier for gear
# and x2.4 for potions. Linear income against geometric prices means purchasing
# power DECAYS as you climb:
#
#     tier 1:  13 gold/kill,  a potion costs  25  ->   1.9 kills
#     tier 5:  65 gold/kill,  a potion costs 830  ->  12.8 kills
#
# A tier-5 player was nearly seven times poorer in real terms than a tier-1
# player. Two things follow, and the second is the serious one: progression
# feels like getting poorer, and THE OPTIMAL GOLD FARM BECOMES THE STARTING
# ZONE — best income-to-cost ratio and the fastest kills. Any player who works
# that out stops playing the rest of the game.
#
# Matching the ratio to the price curve holds kills-per-purchase flat at every
# tier, so relative prices stop depending on where you are. Tune the economy
# once instead of per tier, forever.
#
# TIER 1 IS UNCHANGED ON PURPOSE. unit = 1 there, so the roll is still
# randint(1, 25) and the early game plays exactly as it did.
const GOLD_TIER_RATIO := 2.6

# The tier-1 unit. The mean roll is this x (1 + GOLD_SPREAD) / 2, so 1 here
# means 13 gold from a tier-1 kill.
const GOLD_BASE_UNIT := 1.0

# Width of the roll, as a multiple of the unit. Was the bare 25 in the old
# expression; named so the spread and the curve can be tuned separately.
const GOLD_SPREAD := 25


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
#   tier 4 -> 1 in 108    was "reserved for the boss"
#   tier 5 -> 1 in 72     the ember tier and the bosses that unlock it
#   tier 6 -> 1 in 54
#   tier 7 -> 1 in 36
#   tier 8 -> 1 in 27     the highest tier any item is authored at
#
# THE TABLE HAS TO COVER EVERY TIER AN ITEM EXISTS AT, and it did not.
#
# max_loot_tier does two unrelated jobs: it caps which item tiers may drop, and
# it keys this table. Ember gear is tier 5, so unlocking it for the bosses meant
# raising them to tier 5 and 6 — which walked them straight off the end of a
# table that stopped at 4, into PET_ODDS_FALLBACK. All seven bosses were sitting
# on 1 in 1296, the WORST odds in the game, while a tier 3 elemental had 1 in
# 216. The line above used to read "reserved for the boss" and meant the exact
# opposite of what was happening.
#
# Nothing errored, nothing warned. The fallback did precisely what it promises
# and the promise was the problem. Items are authored up to tier 8, so the table
# now runs to 8 and the same trap cannot spring again on the next tier.
#
# The curve past 4 deliberately FLATTENS rather than continuing to halve: 72,
# 54, 36, 27. A boss you kill a handful of times a session does not need the
# same steepness as trash you kill hundreds of.
const PET_ODDS_BY_TIER := {
	1: 1296,
	2: 648,
	3: 216,
	4: 108,
	5: 72,
	6: 54,
	7: 36,
	8: 27,
}

# Used when max_loot_tier isn't in the table above (a tier 9+ enemy added later,
# or a corrupted value). Deliberately on the stingy side: a missing entry should
# never accidentally make a pet common.
#
# It should now be genuinely unreachable for authored content — see the note
# above. If you find yourself hitting it, extend the table rather than leaning
# on this, because landing here silently makes your BEST enemy your WORST pet
# source and nothing anywhere will tell you.
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

# How much further than flee_range an enemy retreats once it has STARTED
# fleeing. See the hysteresis note in _handle_combat() for why a bare threshold
# produces a twitch instead of a retreat. 1.8 means an archer with a flee_range
# of 50 backs off to 90 before it turns and shoots again, which is a real kite
# rather than a flinch.
#
# ONLY APPLIES TO ENEMIES THAT OVERRIDE get_flee_speed() ABOVE THEIR CHASE
# SPEED. Everything else keeps the plain flee_range threshold - see the gate in
# _handle_combat() for why giving this to an enemy slower than the player
# stops it ever fighting again.
const FLEE_RELEASE_FACTOR := 1.8

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

# The direction the WALK animation is facing, kept apart from attack_direction
# so it can carry hysteresis. Navigation returns a cardinal that alternates axis
# on a diagonal path; feeding that straight to the sprite strobed it. This holds
# the last steady facing and only turns when the heading clearly changes - see
# where it is set in the chase block, and Facing.from_vec_stable().
var _walk_facing: String = "down"
var spawn_position: Vector2 = Vector2.ZERO
var is_returning_home: bool = false

# Latched while backing away, so the retreat runs to a real distance instead of
# stopping the instant flee_range is crossed. See _handle_combat().
var _is_fleeing: bool = false

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

	# AFTER the sprite is wired, so the tint a placed instance was authored with
	# is what a hit flash restores to. See _default_modulate.
	if has_node("animatedsprite2d"):
		_default_modulate = ($animatedsprite2d as AnimatedSprite2D).modulate

	_setup_navigation()
	# AFTER the mask is set above, not before - the separation query reads the
	# enemies layer this enemy was just added to, and it needs get_rid() to
	# exclude itself, which only exists once the node is in the tree.
	_setup_separation()

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
		# Frozen mid-attack, EXCEPT for easing out from under the player. The
		# attack is not interrupted; see _standoff_velocity().
		velocity = _standoff_velocity()
		move_and_slide()
		return

	var dist_to_player: float = global_position.distance_to(player.global_position)

	if dist_to_player > leash_range:
		# Cleared here rather than left latched: an enemy that leashed out mid
		# retreat should come back as a fresh chaser, not resume a retreat from
		# a player who is no longer anywhere near it.
		_is_fleeing = false
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
# LOCAL AVOIDANCE  (NEW)
# =============================================================================
# WHY COLLISION ALONE IS NOT ENOUGH, and why enemies queued up behind each
# other before this existed.
#
# Collision stops enemies OVERLAPPING. It does nothing about them QUEUEING.
# Two enemies walking toward the same point meet body to body, move_and_slide()
# simply refuses the frame for the one behind, and it keeps pressing into the
# back of the one in front for as long as they both want that spot. That is the
# "stuck behind each other" symptom exactly, and no amount of collision-shape
# tuning fixes it, because collision is the thing CAUSING it. The enemy at the
# back is not confused about where to go - it is doing the right thing into an
# obstacle it has no rule for going around.
#
# So give it that rule. It is TWO separate mechanisms, and keeping them apart is
# the point - the first version of this section tried to do both jobs with one
# and did neither:
#
#   1. SPREADING (_separation_push). A soft push away from nearby neighbours,
#      blended into the heading. This biases a pack to fan out on the approach
#      so fewer of them end up in single file to begin with. It is a nudge, and
#      it is only ever a nudge.
#
#   2. UNSTICKING (_is_step_blocked + _pick_detour). Before committing to a
#      step, look at the space that step moves into. If a neighbour is standing
#      there, turn a quarter and take that step instead, and hold that turn long
#      enough to actually get past. This is a DECISION, not a blend, and it is
#      the part that breaks a queue.
#
# Mechanism 2 exists because mechanism 1 cannot do its job here, for a reason
# that is pure arithmetic rather than tuning: movement snaps to a cardinal, and
# a blend of "mostly forward, somewhat sideways" always snaps back to forward.
# The note on SEPARATION_WEIGHT works the numbers through.
#
# Three properties worth knowing before touching any of it:
#
#   * WITH NO NEIGHBOURS NEARBY, _steered_direction_to returns the plain
#     navigation answer and nothing here runs. A lone enemy moves precisely as
#     it did before this section existed - this cannot change single combat.
#   * Movement stays strictly 4-directional. The heading bends and the step can
#     turn a corner, but every step is still up/down/left/right.
#   * Only neighbours actually IN THE WAY block anything - ahead, within a body
#     length, and close to the line of travel. In a pack nearly every enemy has
#     somebody near it, and treating all of them as obstacles would freeze the
#     whole fight.
#
# This does NOT replace the formation slots or the stuck-reclaim escalation.
# Slots decide WHERE each enemy is headed; this decides how it gets there when
# something is in the way. Both still run.

# WHY A BLENDED PUSH ALONE DOES NOTHING HERE, which is worth writing down
# because the first version of this section was exactly that and it did not
# work at all.
#
# Movement snaps to a cardinal. Take the actual failure case: enemy A directly
# behind enemy B, both walking right. A's heading is (1, 0); the push away from
# B is (-1, 0), swung a quarter turn to (0, 1) so it reads as "go around" - and
# the blended steer is (1, 0.9). Then the snap picks the dominant axis, |1| beats
# |0.9|, and the answer is "right". Into B. Again.
#
# The sideways nudge can never win that comparison while the weight is under
# 1.0, and raising it over 1.0 only means the enemy sidesteps when it is already
# touching. The blend is the wrong shape of tool: a vector sum expresses
# "mostly forward, a bit sideways", and then the snap throws away the "bit".
#
# So the push below is kept ONLY for what it is genuinely good at - biasing an
# approaching pack to fan out before anyone is blocked - and the actual
# unsticking is a decision, not a blend: look at the tile ahead, and if a
# neighbour is standing in it, turn a quarter and take that step instead. See
# _is_step_blocked() and _pick_detour().
const SEPARATION_WEIGHT := 0.9

# How far away another enemy still registers at all.
#
# SIZED FROM THE ACTUAL BODY, not from the sprite. The body shape in every enemy
# scene is a CapsuleShape2D of radius 10, so an enemy is 20px wide and two of
# them touch when their centres are 20px apart. The first version of this used
# 26, which left six pixels of warning before contact at a closing speed of over
# 100px/s - the neighbour was effectively never seen until it was already being
# shoved. Two body widths gives the steering room to act.
const SEPARATION_RADIUS := 40.0

# The step-ahead test. LOOKAHEAD is how far down the intended step to care about
# (a bit over one body width, so a blocker is seen just before contact rather
# than after). HALF_WIDTH is how far to either side still counts as being in the
# way.
#
# HALF_WIDTH WAS 20.0 AND THAT NUMBER MADE ENEMIES PACE ON THE SPOT. It was set
# to the exact distance at which two radius-10 bodies collide, which sounds
# correct and is a trap: adjacent slots on ring 1 are 20.28px apart. So every
# enemy standing peacefully in formation had its neighbours sitting 0.28px from
# the blocked threshold, and sub-pixel jitter flipped the answer between
# "blocked" and "clear" from one frame to the next - detour sideways, step
# forward, detour back, forever. The test was not wrong about geometry; it was
# being asked a question whose answer was a coin flip.
#
# 14 is comfortably inside the 20.28px formation spacing, so a neighbour standing
# beside this enemy never registers, while somebody genuinely planted in front of
# it still does. Grazing contact is left to collision sliding, which is what
# collision is good at - this test is only for "there is a body in my way and I
# should go around it".
const AVOID_LOOKAHEAD := 26.0
const AVOID_HALF_WIDTH := 14.0

# Inside this distance of the target, the detour machinery switches off.
#
# An enemy this close is PARKING, not navigating - and parking is exactly where
# the block test is least reliable, because arriving in formation means coming
# to rest with neighbours a body's width away on either side. Let the separation
# push and ordinary collision settle the last few pixels; they do it without
# ever changing their minds.
const AVOID_DISABLE_RANGE := 24.0

# Once an enemy commits to going around something, it holds that turn for this
# long before reconsidering.
#
# WITHOUT THIS IT SHUFFLES AND GETS NOWHERE. Step aside once and the forward
# path is instantly clear again, so next frame it steps forward, so it is
# blocked again, so it steps aside - at 180 physics ticks a second. That is not
# a detour, it is a vibration. A fifth of a second is long enough to actually
# clear the obstacle at any enemy speed in the game.
const DETOUR_COMMIT_SECONDS := 0.2

# How long after the last block an enemy keeps going around things the SAME way.
#
# Long enough to cover the gaps between blocks while circling a crowd - step
# aside, move freely for a moment, get blocked by the next body along, and it is
# still the same detour as far as this enemy is concerned. Short enough that an
# enemy which genuinely got clear picks a fresh side next time rather than
# orbiting a memory. One second is several body lengths at any enemy speed.
const DETOUR_SIDE_MEMORY := 1.0

# =============================================================================
# PLAYER STANDOFF
# =============================================================================
# STOPS THE PLAYER STANDING ON TOP OF AN ENEMY, without taking away the ability
# to walk through a pack.
#
# The player's collision mask deliberately excludes the enemies layer - you wade
# through a crowd instead of being walled in by it, which was a decision made on
# purpose. The consequence nobody asked for is that NOTHING pushes an enemy out
# from under you: walk onto a mage holding position and the two sprites simply
# occupy the same pixels.
#
# So the enemy yields instead. Not by fleeing, and not by interrupting whatever
# it is doing - it keeps casting or shooting throughout. It just declines to
# stand inside you.
#
# SIZED FROM BOTH BODIES: the enemy's is a capsule of radius 10 and the player's
# is a circle of radius 7, so 17px between centres is exactly touching. This is
# the point of contact, not a comfortable distance - the intent is no overlap,
# not personal space.
const PLAYER_STANDOFF := 17.0

# Slow on purpose. Being eased out from under the player should read as being
# shouldered aside, not as backing away - a fast standoff is indistinguishable
# from the kiting that bush mages were explicitly rebuilt to stop doing.
const STANDOFF_SPEED := 40.0


# The velocity that eases this enemy out from under the player. Vector2.ZERO
# whenever they are not actually overlapping, which is almost always - so every
# "hold position" site below can use it unconditionally in place of
# Vector2.ZERO and behave exactly as it did before when there is no overlap.
func _standoff_velocity() -> Vector2:
	if not is_instance_valid(player):
		return Vector2.ZERO

	var away: Vector2 = global_position - player.global_position
	var d: float = away.length()
	if d >= PLAYER_STANDOFF:
		return Vector2.ZERO

	if d <= 0.01:
		# Dead centre on the player, so there is no "away" to compute. Back out
		# along the way this enemy came, which is the direction it is facing.
		away = -Facing.to_vec(_walk_facing)
		if away == Vector2.ZERO:
			away = Vector2.DOWN
		d = 1.0

	# Scaled by how deep the overlap is, so it eases out and settles at the
	# contact point rather than popping to it and jittering there.
	var depth: float = (PLAYER_STANDOFF - d) / PLAYER_STANDOFF
	return (away / d) * STANDOFF_SPEED * depth

# Bit VALUE of the enemies layer, not its number. Enemies sit on layer 4, and a
# mask is a bitmask, so layer 4 is 2^(4-1) = 8. Getting this wrong does not
# error - it silently queries the wrong layer and the push is always zero.
const SEPARATION_MASK := 8

# Enough neighbours to steer sensibly in a crowd without paying for a query
# that returns the whole pack. Past this many bodies at once, the extra ones
# barely move the summed direction anyway.
const SEPARATION_MAX_NEIGHBOURS := 8

# Built once and reused every frame. A fresh CircleShape2D and query object per
# physics frame per enemy is pure garbage generation for a value that never
# changes - only the transform moves.
var _separation_query: PhysicsShapeQueryParameters2D = null

# The detour currently committed to, and how long is left on it.
var _detour_dir: String = ""
var _detour_time: float = 0.0

# WHICH WAY this enemy is going around things: -1 left, +1 right, 0 no detour in
# progress. Held across separate blocks so the turns add up to an arc rather
# than cancelling out - see _pick_detour() for the pacing bug this fixes.
var _detour_side: int = 0
var _detour_side_time: float = 0.0


func _setup_separation() -> void:
	var shape := CircleShape2D.new()
	shape.radius = SEPARATION_RADIUS

	_separation_query = PhysicsShapeQueryParameters2D.new()
	_separation_query.shape = shape
	_separation_query.collision_mask = SEPARATION_MASK
	_separation_query.collide_with_bodies = true
	# Areas are OFF deliberately. bushmage carries four attack Area2Ds on the
	# enemies layer, and counting those as traffic would leave every mage
	# permanently convinced it was surrounded by its own hitboxes.
	_separation_query.collide_with_areas = false
	# Excluded by RID, so this enemy never repels itself. Typed explicitly
	# because `exclude` is an Array[RID] and an untyped literal has to be
	# converted on assignment.
	var ignore_self: Array[RID] = [get_rid()]
	_separation_query.exclude = ignore_self


# Where the nearby enemies are, as offsets FROM this enemy TO each of them.
# Empty when alone, which is what every caller below keys off.
func _nearby_enemy_offsets() -> Array[Vector2]:
	var offsets: Array[Vector2] = []
	if _separation_query == null:
		return offsets

	_separation_query.transform = Transform2D(0.0, global_position)
	var space_state := get_world_2d().direct_space_state
	var hits: Array[Dictionary] = space_state.intersect_shape(
		_separation_query, SEPARATION_MAX_NEIGHBOURS)
	if hits.is_empty():
		return offsets

	# ONE ENTRY PER ENEMY, not one per collision shape. intersect_shape reports
	# every overlapping SHAPE, and these bodies carry more than one on this
	# layer, so without this a single neighbour standing there would count
	# several times over.
	var counted: Dictionary = {}

	for hit in hits:
		var other: Object = hit.get("collider")
		if other == null or not is_instance_valid(other):
			continue
		if other == self or not (other is Node2D):
			continue

		var id: int = other.get_instance_id()
		if counted.has(id):
			continue
		counted[id] = true

		offsets.append((other as Node2D).global_position - global_position)

	return offsets


# The summed push away from nearby enemies. Length at most 1.0.
#
# This is the SPREADING half of the system, not the unsticking half - it biases
# an approaching pack apart so fewer of them end up in single file to begin
# with. It cannot turn an enemy out of a queue on its own; see the note on
# SEPARATION_WEIGHT for the arithmetic on why.
func _separation_push(offsets: Array[Vector2]) -> Vector2:
	var push: Vector2 = Vector2.ZERO

	for o in offsets:
		var d: float = o.length()

		if d <= 0.01:
			# EXACTLY STACKED. There is no "away" to compute, and handing both
			# enemies the same default direction would keep them stacked
			# forever. The instance id picks a stable per-enemy angle, so two
			# bodies in one spot pull apart different ways and stay apart.
			push += Vector2.RIGHT.rotated(float(get_instance_id() % 360) * 0.0174532925)
			continue

		if d >= SEPARATION_RADIUS:
			continue

		push += (-o / d) * (1.0 - d / SEPARATION_RADIUS)

	return push.limit_length(1.0)


# Is another enemy standing in the space this step moves into?
#
# A neighbour counts only if it is AHEAD along the step, within one body length,
# and close enough to the line of travel that the two bodies would actually
# touch. Anything beside or behind this enemy blocks nothing - which matters,
# because in a pack almost every enemy has somebody near it, and treating all of
# them as obstacles would leave nobody able to move at all.
func _is_step_blocked(dir_vec: Vector2, offsets: Array[Vector2]) -> bool:
	if dir_vec == Vector2.ZERO:
		return false

	var side: Vector2 = Vector2(-dir_vec.y, dir_vec.x)
	for o in offsets:
		var along: float = o.dot(dir_vec)
		if along <= 0.0 or along > AVOID_LOOKAHEAD:
			continue
		if absf(o.dot(side)) < AVOID_HALF_WIDTH:
			return true
	return false


# The quarter turn: given a blocked step, which way to go around.
# Returns "" when both sides are blocked too.
#
# WHY THE SIDE IS REMEMBERED, and the bug that made it necessary.
#
# The first version chose the side fresh each time, preferring whichever one
# pointed more toward the target. That sounds right and produces pacing. Watch
# it: a mage below the player is blocked going up, so it steps right - and now
# the player is up and to its LEFT, so the moment it re-decides it steps back
# left, which puts the player up and to its right again. Left, right, left,
# right, forever, a few pixels from where it started. The rule that was supposed
# to make the detour efficient is exactly the rule that prevented it finishing.
#
# So the side is chosen ONCE and held for DETOUR_SIDE_MEMORY after the last time
# this enemy was blocked. Turning the same way relative to travel, over and over,
# traces an arc - so a blocked enemy circles whatever is in its way instead of
# rocking against it, and around a crowded player that reads as the pack
# swarming for an opening rather than milling about.
func _pick_detour(blocked_dir: String, heading: Vector2, offsets: Array[Vector2]) -> String:
	var forward: Vector2 = Facing.to_vec(blocked_dir)
	if forward == Vector2.ZERO:
		return ""

	var left:  Vector2 = Vector2(forward.y, -forward.x)
	var right: Vector2 = Vector2(-forward.y, forward.x)

	var first:  Vector2 = left
	var second: Vector2 = right
	var first_side: int = -1

	if _detour_side != 0:
		# ALREADY GOING AROUND SOMETHING. Keep turning the same way. This is
		# what turns a sequence of quarter turns into an arc instead of a
		# wobble, and it is the whole point of the memory.
		if _detour_side > 0:
			first = right
			second = left
			first_side = 1
	else:
		# FIRST BLOCK OF THIS DETOUR. Prefer the side that still makes progress
		# toward the target; if the target is dead ahead both are equally good,
		# so split by instance id - stable per enemy, and it stops two enemies
		# in one jam both dodging the same way and staying jammed.
		var left_score:  float = heading.dot(left)
		var right_score: float = heading.dot(right)
		if right_score > left_score:
			first = right
			second = left
			first_side = 1
		elif is_equal_approx(left_score, right_score) and get_instance_id() % 2 == 0:
			first = right
			second = left
			first_side = 1

	if not _is_step_blocked(first, offsets):
		_detour_side = first_side
		return Facing.from_vec(first)

	# Preferred side blocked too - take the other one, and REMEMBER that, so the
	# arc continues that way from here rather than flipping back next block.
	if not _is_step_blocked(second, offsets):
		_detour_side = -first_side
		return Facing.from_vec(second)

	# Both sides blocked. The memory is left exactly as it was: no turn was
	# taken, so there is nothing to record, and clearing it here would throw
	# away the direction of an arc this enemy is halfway through.
	return ""


# The heading this enemy would take with nobody in the way: the raw vector the
# navigation logic wants to move along, BEFORE it is snapped to a cardinal.
#
# Split out of _get_direction_to_point_via_navigation() so avoidance can bend
# the heading while it is still a vector. Snapping first and steering after
# would mean choosing between four answers, which cannot express "go around".
func _heading_vector_to(target_pos: Vector2) -> Vector2:
	if _has_line_of_sight(target_pos):
		_prefer_secondary_axis = false
		_stuck_time = 0.0
		return target_pos - global_position

	if nav_agent == null:
		return target_pos - global_position

	nav_agent.target_position = target_pos
	return nav_agent.get_next_path_position() - global_position


# What moving code should call: the cardinal step toward target_pos, routed
# around walls by navigation and around other enemies by the rules above.
func _steered_direction_to(target_pos: Vector2) -> String:
	var heading: Vector2 = _heading_vector_to(target_pos)
	var offsets: Array[Vector2] = _nearby_enemy_offsets()

	# The side memory ages out on its own. It is refreshed below every time this
	# enemy is actually blocked, so it only expires once it has genuinely been
	# travelling freely for DETOUR_SIDE_MEMORY.
	_detour_side_time -= get_physics_process_delta_time()
	if _detour_side_time <= 0.0:
		_detour_side_time = 0.0
		_detour_side = 0

	# NOBODY NEARBY. Byte for byte the plain navigation answer, wall-slide
	# fallback included. This is the guarantee that everything in this section
	# is invisible to an enemy fighting alone.
	if offsets.is_empty():
		_detour_dir = ""
		_detour_time = 0.0
		return _snap_heading(heading)

	# The heading, biased away from neighbours. Spreads an approaching pack;
	# does not by itself unstick anything.
	var steer: Vector2 = heading.normalized() + _separation_push(offsets) * SEPARATION_WEIGHT
	var preferred: String = _snap_heading(steer)

	# ARRIVING, NOT NAVIGATING. Close to the target, the detour logic is off -
	# see AVOID_DISABLE_RANGE. The separation push above still runs, so enemies
	# still ease apart as they settle; they just stop asking a yes/no question
	# whose answer flips on sub-pixel noise.
	if global_position.distance_to(target_pos) <= AVOID_DISABLE_RANGE:
		_detour_dir = ""
		_detour_time = 0.0
		return preferred

	# HOLD A DETOUR ALREADY IN PROGRESS, unless it has itself become blocked.
	if _detour_time > 0.0:
		_detour_time -= get_physics_process_delta_time()
		if Facing.is_direction(_detour_dir) \
				and not _is_step_blocked(Facing.to_vec(_detour_dir), offsets):
			return _detour_dir
		_detour_dir = ""
		_detour_time = 0.0

	if not _is_step_blocked(Facing.to_vec(preferred), offsets):
		return preferred

	# BLOCKED, so refresh the side memory. Everything from here down is one
	# continuous detour as far as this enemy is concerned, even with stretches
	# of clear ground between the blocks - that is what makes a run of quarter
	# turns come out as an arc around the crowd rather than a rocking motion.
	_detour_side_time = DETOUR_SIDE_MEMORY

	var detour: String = _pick_detour(preferred, heading, offsets)
	if detour == "":
		# BOXED IN ON THREE SIDES. Keep pressing forward and let the existing
		# escalation handle it: _record_nav_movement_result() flips the axis
		# after 0.08s of no progress and drops the formation slot entirely
		# after 0.4s, which re-targets this enemy somewhere else in the ring.
		return preferred

	_detour_dir = detour
	_detour_time = DETOUR_COMMIT_SECONDS
	return detour


# The cardinal snap, honouring the wall-slide fallback.
#
# Read _prefer_secondary_axis AFTER _heading_vector_to and never before: a clear
# line of sight clears that flag inside it, so checking first acts on the
# previous frame's answer.
func _snap_heading(vec: Vector2) -> String:
	if _prefer_secondary_axis:
		return _get_secondary_direction_from_vec(vec)
	return _get_direction_from_vec(vec)


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
# The SHAPE of the formation lives in Formation. These names stay here as
# aliases because subclasses inherit them and an alias costs nothing.
#
# TILE_SIZE AND FORMATION_SLOT_STRIDE ARE GONE, not renamed. They described a
# square grid of whole tiles, and the formation is now a ring of angular wedges
# with no tiles and no stride in it - see the header of formation.gd. Keeping
# the old names pointed at something else would be worse than removing them:
# anything still reading them was reasoning about a grid that no longer exists,
# and should fail loudly rather than quietly get a number that means something
# different. Nothing in the project referenced either one.
const FORMATION_RING_COUNT := Formation.RING_COUNT
const SLOT_ARRIVAL_THRESHOLD := Formation.ARRIVAL_THRESHOLD

# WHO holds which slot, as opposed to where the slots are. Shared across every
# enemy instance, which is the whole mechanism: a slot claimed by one enemy is
# unavailable to the rest, so they spread out instead of stacking. Stays here
# rather than in Formation because it is live scene state - the values are node
# references, and they go stale when an enemy dies.
static var _slot_owners: Dictionary = {}  # slot_index (int) -> enemy instance

var _claimed_slot: int = -1

# How often an enemy reconsiders which slot it holds. See _ensure_slot_claimed().
const SLOT_REVIEW_SECONDS := 0.4
var _slot_review_time: float = 0.0

# How much better a slot has to be before an enemy will abandon the one it has.
#
# Its job is to stop enemies trading places over trivia. With bearing priced per
# degree it no longer blocks same-ring moves outright, and that is deliberate:
# 500 is worth about 62 degrees of arc, so an enemy WILL take a slot on its own
# ring that is a long way nearer to where it actually stands - which cancels a
# pointless hike rather than causing one - and will not shuffle one seat over.
const SLOT_SWITCH_MARGIN := 500.0

# NEW: excluded from the very next claim attempt, so releasing a
# genuinely blocked slot (see STUCK-RECLAIM in _record_nav_movement_result
# below) doesn't just immediately re-claim that same slot again if
# nothing else has changed yet.
var _last_released_slot: int = -1


# returns the world-space position this enemy should actually path
# toward — its claimed tile around the player. tile_size defaults to one
# wedge on the ring around the player.
#
# THE TILE_SIZE PARAMETER IS GONE, and its absence is the point. It let a caller
# ask to "hold further out" by scaling the grid, which in the wedge model is not
# a thing you can do without changing how many enemies fit - the radius and the
# count are the same fact stated two ways. A class that wants to stand further
# back belongs on an outer ring, not on a stretched copy of the inner one.
func _get_slot_target_position() -> Vector2:
	if not is_instance_valid(player):
		return global_position

	_ensure_slot_claimed()
	if _claimed_slot == -1:
		return player.global_position

	var raw: Vector2 = Formation.world_position(player.global_position, _claimed_slot)

	# CLAMPED, because a slot is just an arithmetic offset from the player and
	# arithmetic knows nothing about walls. Stand the player against geometry
	# and half the formation ring lands INSIDE it - enemies then path toward a
	# point that does not exist, grind into the wall, and pile up at the
	# nearest corner because they are all failing in the same direction.
	return clamp_to_navigation(raw)


# How good a slot is for THIS enemy. Lower is better.
#
# RING FIRST, BEARING SECOND, AND THAT ORDER IS THE WHOLE POINT.
#
# This used to score by raw distance, and raw distance cannot build a circle.
# Work it: an enemy approaching from the east, inner ring full on the east side.
# A free ring-2 slot to its east is 145px away; the free ring-1 slot on the WEST
# side is 208px away. Distance picks the ring-2 slot every time - so the pack
# stacks up in outer rings on whichever side it came from and the far half of
# the inner ring stays empty forever. That is the "all bunched on one side"
# screenshot, and no amount of steering fixes it, because the enemies were
# walking exactly where they were told to.
#
# RING PRIORITY IS STRONG BUT NOT ABSOLUTE, and the difference is visible.
#
# It WAS absolute - every ring-1 slot beat every ring-2 slot however far around
# the player it sat. That closes the circle perfectly and looks like the enemies
# have lost interest in you: an enemy standing at your shoulder abandons its spot
# and hikes the entire way around your back to take a marginally better one. From
# the player's side that is indistinguishable from wandering off.
#
# So bearing is now priced per degree: one ring inward is worth 1000, and arc
# around the player costs a weight per degree.
#
# THE WEIGHT IS NOT CONSTANT, AND THAT IS THE ACTUAL INSIGHT. Wandering is
# something only a NEARBY enemy can do. An enemy a hundred pixels out that angles
# round to the far side is not wandering, it is walking in - the arc costs it
# nothing it was not about to spend anyway, and it arrives having spread the pack
# evenly. An enemy already at the player's shoulder that sets off around their
# back for a marginally better slot is the thing that looks broken, because from
# the player's side it simply stopped attacking and left.
#
# So arc is nearly free far out and expensive on arrival. Far away: take the best
# place on the ring, wherever it is. Up close: stay and fight from where you are.
# A single flat weight cannot express that - tuning one trades trekking against
# how many enemies reach the inner ring, and every value is wrong somewhere.
const BEARING_WEIGHT_FAR  := 6.0      # break-even ~165 degrees: go where you like
const BEARING_WEIGHT_NEAR := 40.0     # break-even ~25 degrees: hold your ground
const BEARING_WEIGHT_FALLOFF := 120.0 # distance past the ring over which it climbs


func _bearing_weight(dist_to_anchor: float) -> float:
	var t: float = clampf(
		1.0 - (dist_to_anchor - Formation.RING_RADIUS) / BEARING_WEIGHT_FALLOFF, 0.0, 1.0)
	return lerpf(BEARING_WEIGHT_FAR, BEARING_WEIGHT_NEAR, t)


func _slot_score(slot: int, my_bearing: float, bearing_weight: float) -> float:
	var ring: float = float(Formation.ring_of(slot))
	var off_by: float = rad_to_deg(absf(angle_difference(my_bearing, Formation.bearing_of(slot))))
	return ring * 1000.0 + off_by * bearing_weight


func _ensure_slot_claimed() -> void:
	if not is_instance_valid(player):
		_claimed_slot = -1
		return

	var holds: bool = _claimed_slot != -1 and _slot_owners.get(_claimed_slot) == self

	# REVIEWED ON A TIMER RATHER THAN NEVER, and on a timer rather than every
	# frame. Never re-checking left an enemy marooned on ring 3 for the rest of
	# the fight after the enemy in front of it died; re-checking every frame at
	# 180Hz would have the whole pack trading places continuously.
	if holds:
		_slot_review_time -= get_physics_process_delta_time()
		if _slot_review_time > 0.0:
			return
	_slot_review_time = SLOT_REVIEW_SECONDS

	var anchor: Vector2 = player.global_position
	var to_anchor: Vector2 = global_position - anchor
	var my_bearing: float = to_anchor.angle()
	var bearing_weight: float = _bearing_weight(to_anchor.length())

	var current_score: float = INF
	if holds:
		current_score = _slot_score(_claimed_slot, my_bearing, bearing_weight)

	var candidates: Array = []
	for i in range(Formation.slot_count()):
		if i == _last_released_slot:
			continue  # don't immediately re-claim the slot just given up on
		if i == _claimed_slot:
			continue  # scored separately, above

		var slot_owner = _slot_owners.get(i)
		if slot_owner != null and is_instance_valid(slot_owner):
			continue

		candidates.append({
			"index": i,
			"world": Formation.world_position(anchor, i),
			"score": _slot_score(i, my_bearing, bearing_weight),
		})

	candidates.sort_custom(func(a, b): return a["score"] < b["score"])

	for candidate in candidates:
		# Sorted ascending, so the first candidate that fails to clear the margin
		# means nothing after it will either. See SLOT_SWITCH_MARGIN.
		if candidate["score"] > current_score - SLOT_SWITCH_MARGIN:
			break

		# A slot the navmesh has to drag further than the enemy is wide is a
		# slot inside a wall. Claiming it means walking at geometry forever, so
		# skip to the next best instead - which naturally spreads enemies onto
		# the side of the player that is actually open.
		var world: Vector2 = candidate["world"]
		if clamp_to_navigation(world).distance_to(world) > Formation.BODY_RADIUS:
			continue

		if holds and _slot_owners.get(_claimed_slot) == self:
			_slot_owners.erase(_claimed_slot)
		_slot_owners[candidate["index"]] = self
		_claimed_slot = candidate["index"]
		_last_released_slot = -1
		return

	if not holds:
		_claimed_slot = -1

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
	# REWRITTEN AS A THIN WRAPPER, same answer. The body moved to
	# _heading_vector_to() (see LOCAL AVOIDANCE above) so the steering code can
	# get at the heading as a VECTOR before it is snapped to a cardinal. This
	# function is the no-avoidance version and stays for callers that genuinely
	# want it - fleeing and walking home, where dodging other enemies is not
	# the point.
	#
	# ONE DIFFERENCE, stated rather than hidden: the old nav_agent == null
	# branch forced the primary axis even when the wall-slide fallback was
	# active. It now honours the fallback like every other path through here.
	# nav_agent is created in _ready() and is never null in practice, so this
	# is a change to an unreachable line.
	var heading: Vector2 = _heading_vector_to(target_pos)
	if _prefer_secondary_axis:
		return _get_secondary_direction_from_vec(heading)
	return _get_direction_from_vec(heading)


# raycasts through PHYSICS collision (walls) to check for a clear line to
# the target — deliberately physics, not navigation, since this is the
# "do I even need pathfinding right now" gate, separate from the actual
# routing logic above.
#
# MASK 1 IS CORRECT HERE, AND THAT IS WORTH STATING because the layer is
# misleadingly named. Layer 1 reads as "ground" in Project Settings, but it
# is the layer every TileMap in this project puts its collision on - shop
# walls, building exteriors and the crypt all use it. Layer 2, named
# "walls", is used only by Area2Ds (prop triggers). So a raycast for
# geometry masks 1, not 2.
#
# It cannot hit enemies or the player: they are on layers 8 and 4, which
# this mask excludes. The only things that block a line here are the same
# things a fired projectile now dies on - see the mask on arrow.tscn and
# friends. Change one and you must change the other, or enemies will hold
# fire at things their shots would have passed, or shoot at things their
# shots cannot cross.
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
	bar.value     = _bar_displayable(bar, hp)
	_wire_health_readout(bar)


func _bar_displayable(bar: Range, amount: float) -> float:
	"""What to DRAW for this amount: the amount, or the smallest sliver the bar
	can actually render, whichever is larger. Zero draws zero.

	EMPTY HAS TO MEAN DEAD, and on these bars it did not by a wide margin. A
	TextureProgressBar fills a fraction of its progress texture, and these
	textures are tiny - monsterhpfull.png is 36px, bosshpfull.png is 64px. A
	fireboss has 2054 hit points, so one point is 0.03 of a pixel and the last
	THIRTY-TWO of them round away to nothing: the bar reads empty, the boss is
	still alive, and every hit after that looks like damage landing on a corpse.
	On an ordinary slime it is the last one or two, which is a moment; on a boss
	it is a stretch of the fight long enough to make it feel broken.

	CEILING, NOT JUST A FLOOR, because _wire_healthbar() sets step = 1: a Range
	snaps its value to whole multiples, so a fractional minimum would round back
	down and vanish again. Rounding up guarantees the sliver survives the snap.

	The same fix as characterhud.gd's _displayable(), with that one extra
	wrinkle. Both measure off the texture rather than hard-coding a width, so a
	bar with different art gets the floor its own art deserves."""
	if bar == null or amount <= 0.0:
		return 0.0

	var width: float = 100.0
	if bar is TextureProgressBar:
		var texture: Texture2D = (bar as TextureProgressBar).texture_progress
		if texture != null:
			width = float(texture.get_width())

	return maxf(amount, ceilf(bar.max_value / maxf(width, 1.0)))


# =============================================================================
# HEALTH READOUT — the number printed on the bar
# =============================================================================
#
# WHY A NUMBER AND NOT JUST A BAR. A bar answers "roughly how much is left",
# which is the wrong question against a boss with 2054 hit points: the
# difference between a fight you are winning and one you are losing is about
# forty points a swing, and forty points is half a pixel of a 64-pixel texture.
# _bar_displayable() above makes the bar stop LYING about the last few points.
# This makes it stop being VAGUE about all the rest.
#
# BUILT IN CODE, NOT IN THE SCENES. Six enemy scenes carry a healthbar node of
# their own and four more inherit or instance one of those, and every one of
# them authored its bar differently — three at scale 1, two at 0.5, the small
# slime at 0.55, offsets that centre on the sprite to within seven pixels. A
# label added by hand to each would be ten chances to get the counter-scale
# wrong and ten places to fix it when the camera zoom changes. Added here it
# lands on every enemy that has a bar at all, including the inherited ones,
# which is the whole set by definition.
const HEALTH_READOUT_NAME := "healthvalue"

# The camera zoom to assume when there is no camera to ask — every player class
# is authored at 3, and _ready() can run a frame before the player's camera
# becomes current. _layout_health_readout() re-reads the live zoom on the
# deferred pass and on every write, so this value is a starting guess, not a
# setting.
const HEALTH_READOUT_FALLBACK_ZOOM := 3.0

# Font size in SCREEN pixels, as a fraction of how tall the bar actually DRAWS.
# A monster bar is 8 art pixels seen at zoom 3, so 24 on screen, so 13pt text; a
# boss bar draws 30 and gets 17. That is the same proportion the player's HUD
# uses, and it is the PROPORTION rather than the number that is worth keeping —
# a fixed size would stop matching the bar the first time the camera zoom moves.
#
# THE FLOOR IS THE WHOLE POINT OF THE CLAMP. A small poison slime's bar draws at
# 0.55 scale and the fraction would hand it 7pt text: proportionate, and
# unreadable, which is not a trade worth making for something you still have to
# fight.
const HEALTH_READOUT_FONT_RATIO := 0.55
const HEALTH_READOUT_FONT_MIN := 12
const HEALTH_READOUT_FONT_MAX := 20

# How much wider than the bar the label's BOX is. The box is invisible; all it
# does is guarantee the text never hits the Control's minimum size, because a
# Label whose text outgrows its rect grows rightward and downward from its own
# top-left and the centring silently stops being centred. Three times the bar
# holds "2054 / 2054" on the narrowest bar in the game with room to spare.
const HEALTH_READOUT_BOX_FACTOR := 3.0

const HEALTH_READOUT_COLOUR := Color(1, 0.96, 0.9)

# THE NUMBER IS PRINTED ON A BRIGHT RED BAR, over whatever the world happens to
# put behind it. Plain white text on that reads fine in a screenshot and
# disappears in motion, which was the complaint. Three things fix it together
# and none of them does it alone: the size above, a synthetic bold, and an
# outline thick enough to put a hard dark edge between every stroke and the red
# underneath. FULLY OPAQUE, because at 0.85 the red showed through the outline
# and the edge it exists to draw went soft exactly where the contrast was worst.
const HEALTH_READOUT_OUTLINE_COLOUR := Color(0, 0, 0, 1)
const HEALTH_READOUT_EMBOLDEN := 0.35

# A QUARTER OF THE FONT, AND NOT MORE. Godot draws the outline OUTWARD from the
# glyph, so at 13pt — where the stems are under two pixels — a 4px outline is
# thicker than the letter it is outlining, and the digits stop being shapes and
# become black blobs with a white core. Thicker is not clearer past this point;
# it was the size and the weight that were wrong, not the edge.
const HEALTH_READOUT_OUTLINE_RATIO := 0.25
const HEALTH_READOUT_OUTLINE_MIN := 3
const HEALTH_READOUT_OUTLINE_MAX := 5


# ONE FontVariation FOR EVERY ENEMY IN THE GAME. A field holds thirty creatures
# and a boss room spawns more; each one building its own Font resource would be
# thirty copies of one object, rebuilt on every spawn and thrown away on every
# death.
#
# base_font IS LEFT UNSET ON PURPOSE. FontVariation falls back to the theme's
# own font when it has no base, so this emboldens whatever the project's font
# turns out to be rather than pinning today's default into this script — and if
# a real font is ever added to the theme, the readout picks it up with no edit
# here.
static var _readout_font_cache: FontVariation = null


static func _readout_font() -> FontVariation:
	if _readout_font_cache == null:
		_readout_font_cache = FontVariation.new()
		_readout_font_cache.variation_embolden = HEALTH_READOUT_EMBOLDEN
	return _readout_font_cache


func _wire_health_readout(bar: Range) -> void:
	if bar == null:
		return

	var label: Label = bar.get_node_or_null(HEALTH_READOUT_NAME) as Label
	if label == null:
		label = Label.new()
		label.name = HEALTH_READOUT_NAME
		# The bar sits over a creature that can be clicked and attacked; a label
		# that ate the click would make enemies wearing a full health bar
		# unselectable across the top half of their own sprite.
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", HEALTH_READOUT_COLOUR)
		label.add_theme_color_override("font_outline_color", HEALTH_READOUT_OUTLINE_COLOUR)
		label.add_theme_font_override("font", _readout_font())
		bar.add_child(label)

	_layout_health_readout(bar, label)
	_write_health_readout()

	# DEFERRED, because a subclass can still move the bar after this returns.
	# poisonslime.gd::_fit_healthbar_to_form() rescales the bar for the small
	# form in its own _ready(), AFTER super._ready() has run this — and the
	# counter-scale below is computed FROM that scale, so laid out once here the
	# eight smalls of a split would each wear a number 1.8x too big. A deferred
	# call runs at the end of the frame, by which time every _ready() in the
	# chain has had its say.
	_layout_health_readout.call_deferred(bar, label)


func _layout_health_readout(bar: Range, label: Label) -> void:
	"""Counter-scale the label so its text renders at one screen pixel per font
	pixel, and centre it on the bar's ART.

	THE MATHS, ONCE, BECAUSE IT IS THE ONLY SUBTLE PART. A label under a parent
	whose global scale is g, seen through a camera zoomed z, draws each of its
	own local units at s * g * z screen pixels, where s is the label's own
	scale. Set s = 1 / (g * z) and that product is exactly 1: a font_size of N
	lands on N screen pixels, on the pixel grid, crisp. Any other value resamples
	the glyphs and is the blurry text the shop panel had.

	CENTRED ON THE TEXTURE, NOT ON THE RECT. A TextureProgressBar draws its
	textures at their own size from its top-left corner and ignores the rest of
	its rect unless nine-patch stretching is on — and these rects are junk left
	over from authoring, 160 and even 480 units wide around a 36-unit texture.
	Centring on `bar.size` would put the number a long way off to the right of
	the bar it belongs to."""
	# BOTH CHECKED, because this also runs deferred: an enemy killed in the same
	# frame it spawned frees its bar between the call being queued and the queue
	# being drained, and a freed Object is not `null`.
	if not is_instance_valid(bar) or not is_instance_valid(label):
		return

	var art := Vector2(36.0, 8.0)
	if bar is TextureProgressBar:
		var texture: Texture2D = (bar as TextureProgressBar).texture_progress
		if texture != null:
			art = Vector2(texture.get_size())

	# Screen pixels per unit of the bar's own local space.
	#
	# THE GLOBAL SCALE, NOT bar.scale. They are the same number today — every
	# enemy root sits at scale 1 — and reading the local one would keep working
	# right up until somebody scales an enemy to make a bigger variant, at which
	# point the bar would grow and the number on it would not.
	var render: float = maxf(absf(bar.get_global_transform().get_scale().x), 0.01) * _camera_zoom()

	# Sized off the bar's DRAWN height — art.y is in the bar's own units, art.y *
	# render is what the player actually sees — so the number keeps its
	# proportion to the bar at any zoom or bar scale.
	var font_px: int = clampi(
		roundi(art.y * render * HEALTH_READOUT_FONT_RATIO),
		HEALTH_READOUT_FONT_MIN,
		HEALTH_READOUT_FONT_MAX)
	label.add_theme_font_size_override("font_size", font_px)
	label.add_theme_constant_override("outline_size", clampi(
		roundi(float(font_px) * HEALTH_READOUT_OUTLINE_RATIO),
		HEALTH_READOUT_OUTLINE_MIN,
		HEALTH_READOUT_OUTLINE_MAX))

	label.scale = Vector2.ONE / render

	var box: Vector2 = art * render * HEALTH_READOUT_BOX_FACTOR
	label.size = box
	# box / render is the box's size expressed in the bar's local units, which is
	# what has to be centred against the art.
	label.position = (art - box / render) * 0.5


func _write_health_readout() -> void:
	"""Print the REAL health, never bar.value.

	bar.value is the DISPLAYABLE health — _bar_displayable() lifts it to the
	smallest sliver the texture can draw, so a boss on its last 12 points shows
	a value of 33 there. Printing that would take the one honest number on
	screen and make it agree with the rounding it exists to expose."""
	if not has_node("healthbar"):
		return
	var bar: Range = $healthbar
	var label: Label = bar.get_node_or_null(HEALTH_READOUT_NAME) as Label
	if label == null:
		return
	label.text = "%d / %d" % [maxi(hp, 0), maxi(max_hp, 1)]


func _camera_zoom() -> float:
	var viewport: Viewport = get_viewport()
	if viewport != null:
		var camera: Camera2D = viewport.get_camera_2d()
		if camera != null:
			return maxf(absf(camera.zoom.x), 0.01)
	return HEALTH_READOUT_FALLBACK_ZOOM


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
	# FLEE, WITH HYSTERESIS AND ITS OWN SPEED. Both halves are needed before an
	# archer actually backs off rather than appearing to.
	#
	# HYSTERESIS: the old test was a bare `dist < flee_range`. Cross that line by
	# one pixel and the enemy stops fleeing, so the player - who is still walking
	# forward - is immediately inside it again. The result is a dither on the
	# boundary at 180 ticks a second, which does not read as retreating; it reads
	# as twitching in place. Once fleeing, keep fleeing until a real gap exists.
	# GATED ON THIS ENEMY ACTUALLY BEING ABLE TO COMPLETE A RETREAT, which is
	# not a detail - ungated, this hysteresis breaks every enemy in the game
	# except the archer.
	#
	# The player moves at 90. The boss moves at 45, the fire sprite at 85, the
	# electric sprite at exactly 90, and none of them override get_flee_speed().
	# Widening their release distance means they must reach a gap they are
	# physically incapable of opening against a player who is simply walking
	# forward - so they would retreat forever and never attack again. The old
	# bare threshold was right for them: back off a step, hit the line, turn and
	# fight.
	#
	# An enemy that overrides get_flee_speed() upward has opted into kiting and
	# can actually make the distance, so it gets the wider band.
	var flee_threshold: float = flee_range
	if _is_fleeing and get_flee_speed() > get_move_speed():
		flee_threshold = flee_range * FLEE_RELEASE_FACTOR

	if flee_range > 0.0 and dist_to_player < flee_threshold:
		_is_fleeing = true
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
		# STEERED, so a retreating archer goes around whatever is behind it
		# instead of reversing into its own back line and stopping dead.
		var flee_dir: String = _steered_direction_to(flee_target)
		velocity = _vec_from_dir(flee_dir) * get_flee_speed()
		move_and_slide()
		_walk_facing = Facing.from_vec_stable(flee_target - global_position, _walk_facing)
		play_walk_animation(_walk_facing)
		_record_nav_movement_result(flee_pos_before)
		return

	_is_fleeing = false

	# BEING IN RANGE IS NOT THE SAME AS BEING ABLE TO SHOOT.
	#
	# Every fired projectile now masks the ground layer and dies on geometry,
	# so an enemy that opens fire through a wall deletes its own arrow against
	# the masonry and then stands there doing it again on every cooldown. Range
	# decides whether attacking is worth trying; line of sight decides whether
	# it is possible at all.
	#
	# NO LINE MEANS FALL THROUGH TO THE CHASE BELOW, not stop and idle. An enemy
	# that cannot see you should come around and find you - that is what makes a
	# wall cover rather than a permanent shield.
	#
	# Same raycast and same mask as the navigation gate in
	# _get_direction_to_point_via_navigation(), deliberately: "I can path
	# straight to you" and "I can shoot you" are one question, and asking it
	# twice is how the two answers start disagreeing.
	if dist_to_player < attack_range and _has_line_of_sight(player.global_position):
		velocity = _standoff_velocity()
		move_and_slide()
		if attack_ready:
			_trigger_attack()
		else:
			play_idle_animation(attack_direction)
		return

	# Routes toward this enemy's claimed WEDGE on the ring around the player
	# (see SLOT SYSTEM above and the header of formation.gd) rather than at the
	# player's raw position — which is what spreads a pack into a circle around
	# you instead of a scrum on the side they happened to come from.
	var slot_target: Vector2 = _get_slot_target_position()

	# NEW: essentially arrived at the claimed slot — stop and hold
	# instead of continuing to chase it. see SLOT_ARRIVAL_THRESHOLD's
	# comment above for why this is what actually stops the
	# animation-flip jitter at close range.
	if global_position.distance_to(slot_target) < SLOT_ARRIVAL_THRESHOLD:
		velocity = _standoff_velocity()
		move_and_slide()
		play_idle_animation(attack_direction)
		return

	var pos_before: Vector2 = global_position
	# STEERED, not raw. Same navigation underneath, plus a push around any enemy
	# standing in the way - see LOCAL AVOIDANCE. With nobody near it returns the
	# identical heading, so an enemy chasing alone behaves exactly as before.
	var to_player: String = _steered_direction_to(slot_target)
	velocity = _vec_from_dir(to_player) * get_move_speed()
	move_and_slide()
	# MOVE by the nav heading, FACE toward the target. The nav heading flips axis
	# frame to frame on a diagonal (that is the "flipping"); the vector to the
	# slot is steady, and the hysteresis keeps even a slow pass through 45 degrees
	# from strobing the sprite. Movement is unchanged - only what the walk
	# animation shows.
	_walk_facing = Facing.from_vec_stable(slot_target - global_position, _walk_facing)
	play_walk_animation(_walk_facing)
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

	# A VALID MAP WITH NOTHING BAKED INTO IT IS THE DANGEROUS CASE, and it is
	# not the same as an invalid one. Every scene has a navigation map; a scene
	# with no NavigationRegion2D just has an EMPTY one - and
	# map_get_closest_point() answers an empty map with Vector2.ZERO, the world
	# origin, rather than reporting failure.
	#
	# The distance guard below was supposed to catch that, and it only catches
	# it when the query happens to be far from the origin. The boss room has no
	# navmesh and its floor spans the origin, so fighting within 240px of (0, 0)
	# there silently collapsed EVERY point passed through here onto that one
	# spot: a thirty-five pillar wall became one pillar stacked on itself, and
	# every formation slot in the room was rejected as unreachable.
	#
	# Asking whether the map has any regions is the question that was actually
	# meant. No regions means nothing to clamp to, so nothing is clamped.
	if NavigationServer2D.map_get_regions(map).is_empty():
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
		_walk_facing = Facing.from_vec_stable(spawn_position - global_position, _walk_facing)
		play_walk_animation(_walk_facing)
	else:
		is_returning_home = false
		velocity = Vector2.ZERO
		play_idle_animation("down")


func _trigger_attack() -> void:
	# THE BACKSTOP FOR SUBCLASSES THAT NEVER CALL _handle_combat().
	#
	# BushMage and PoisonSlime run their own _physics_process and reach an
	# attack through their own branches, so the sight check in _handle_combat()
	# never runs for them. This is the point every path funnels through, so the
	# rule is enforced here too rather than being copied into each subclass -
	# and a future enemy with its own movement gets it for free.
	#
	# Returns WITHOUT consuming attack_ready or starting the cooldown timer, so
	# the shot lands the instant the line opens instead of after another full
	# cooldown. Stepping out of cover should be punished immediately.
	if is_instance_valid(player) and not _has_line_of_sight(player.global_position):
		return

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


func get_flee_speed() -> float:
	# HOW FAST THIS ENEMY BACKS OFF, kept separate from how fast it advances.
	#
	# An archer that retreats at its chase speed cannot retreat. The player's
	# base speed is 90 and the sniper's is 80, so "run away" resolved to "get
	# walked down while facing the wrong way and not shooting" - it was trying
	# the whole time and losing the race by ten pixels a second. A class whose
	# entire job is holding range has to be able to open it.
	#
	# Defaults to the chase speed, so this changes nothing for any enemy that
	# does not override it.
	return get_move_speed()


func fire_projectile() -> void:
	pass


# =============================================================================
# PROJECTILE SPAWNING
# =============================================================================

const ELEMENT_SHADER := preload("res://src/shared/element_recolour.gdshader")


# An element set on THIS INSTANCE, overriding whatever its EnemyData says.
# -1 means "no override — use the resource".
#
# THIS EXISTS FOR THINGS THAT SPAWN OTHER THINGS. The large poison slime bursts
# into four smalls, and _spawn_slime() hands each child `is_small` and nothing
# else — so a child resolves its own EnemyData in _ready() and is born with the
# SMALL profile's element whatever its parent was. A water slime bursting into
# four earth slimes is the kind of thing nobody notices in code and everybody
# notices on screen.
#
# An override rather than writing to enemy_data, because EnemyData is a shared
# Resource: mutating it would recolour every slime already on the map, and the
# next one to spawn would inherit whatever the last one decided.
var element_override: int = -1


func current_element() -> int:
	# The element this instance actually is. Prefer the per-instance override,
	# fall back to the resource, and treat "no data at all" as physical.
	if element_override >= 0:
		return element_override
	if enemy_data == null:
		return Element.Type.NONE
	return enemy_data.element


func _should_recolour() -> bool:
	# TWO GATES, AND THE FIRST ONE IS THE IMPORTANT ONE.
	#
	# recolour_to_element is opt-in, so an original sheet is drawn as the artist
	# drew it unless a resource explicitly asks to be a palette swap. Read
	# EnemyData.recolour_to_element for what went wrong when this was the other
	# way round. element_override is the runtime escape hatch and counts as
	# asking, because nothing sets it by accident.
	if enemy_data == null or not enemy_data.recolour_to_element:
		if element_override < 0:
			return false

	# NONE IS NOT A RECOLOUR. Physical is steel — near-grey — so rotating a
	# sprite onto it would drain the art rather than characterise it.
	return current_element() != Element.Type.NONE


func _apply_element_recolour() -> void:
	# Rotates this creature's art to its element's hue. See
	# element_recolour.gdshader for why this is a shader and not a modulate:
	# multiplying cannot move a hue, and three of the five creature sheets in
	# this project are saturated enough that a tint only ever darkens them.
	#
	# THIS IS FOR DERIVED VARIANTS ONLY. The whole point of the shader is
	# turning ONE sheet into a family of creatures; pointed at the sheet it was
	# derived from, it overwrites the original with a recolour of itself.
	if not _should_recolour():
		return

	var sprite: AnimatedSprite2D = get_node_or_null("animatedsprite2d")
	if sprite == null:
		return

	# A FRESH MATERIAL PER ENEMY, for the same reason slashwave.gd builds a
	# fresh shape: a Material is a Resource, and one shared between instances
	# would mean the last slime to spawn decided the colour of every slime
	# already on screen.
	var mat := ShaderMaterial.new()
	mat.shader = ELEMENT_SHADER
	mat.set_shader_parameter("element_hue", Element.hue_for(current_element()))
	mat.set_shader_parameter("saturation_scale", enemy_data.saturation_scale)
	sprite.material = mat


func _recolour_projectile(projectile: Node) -> void:
	# The sprite may be the projectile itself or a child of it — the scenes in
	# this project do both — so try the node first and then look for one.
	#
	# SAME GATE AS THE BODY, and for the same reason. The poison slime's shot is
	# drawn green because it is poison; recolouring it to match an element the
	# creature was only filed under would throw away a deliberate piece of art
	# and, worse, do it inconsistently with the creature throwing it.
	if not _should_recolour():
		return

	var target: CanvasItem = projectile as CanvasItem
	for child in projectile.get_children():
		if child is AnimatedSprite2D or child is Sprite2D:
			target = child as CanvasItem
			break
	if target == null:
		return

	# THE SCENE WINS, AND FOR ALMOST EVERY SHOT THE SCENE IS WHAT GOT HERE.
	#
	# Projectiles.variant_of() hands each family's spawner a scene that already
	# carries an authored ShaderMaterial in the right hue — one Resource shared
	# by every instance of icearrow.tscn rather than a fresh one per arrow. This
	# guard is what stops the line below throwing that away and going back to
	# allocating per bullet.
	#
	# WHAT IS LEFT BELOW IS THE FALLBACK, and it is worth keeping: an element in
	# the roster with no variant scene built for it yet still comes out the right
	# colour, just at the old cost. A missing file degrades, it does not break.
	if target.material != null:
		return

	var mat := ShaderMaterial.new()
	mat.shader = ELEMENT_SHADER
	mat.set_shader_parameter("element_hue", Element.hue_for(current_element()))
	mat.set_shader_parameter("saturation_scale",
		enemy_data.saturation_scale if enemy_data != null else 1.0)
	target.material = mat


func spawn_projectile_node(projectile: Node, spawn_pos: Vector2) -> void:
	# parent a projectile into the y-sorted "projectiles" container so it
	# depth-sorts correctly against characters. falls back to the scene root
	# if the container is missing (wrongly-sorted but still functional).
	#
	# add_child + position are BOTH deferred: deferred add avoids the
	# "can't change state while flushing queries" physics error when a
	# projectile spawns during a collision, and deferred position ensures
	# global_position is applied AFTER the node is actually in the tree.
	# THE SHOT WEARS ITS CASTER'S ELEMENT. Applied here, in the one function
	# every enemy's projectile passes through, rather than on each projectile
	# scene — which is how the pets ended up with a rust-tinted root cancelling
	# a green sprite. An elemental variant recoloured through its .tres gets a
	# matching shot for free, with nothing to keep in sync.
	#
	# WHITE IS A NO-OP, so every enemy that has not been given a tint fires
	# exactly what its scene authored.
	if enemy_data != null and enemy_data.body_tint != Color.WHITE and projectile is CanvasItem:
		(projectile as CanvasItem).modulate = enemy_data.body_tint

	# Same shape for the damage: 0 leaves the projectile scene's own number
	# alone, so nothing that has not opted in changes.
	if enemy_data != null and enemy_data.projectile_damage > 0 and "damage" in projectile:
		projectile.damage = enemy_data.projectile_damage

	# THE SHOT INHERITS THE CASTER'S ELEMENT, which is what makes six recoloured
	# slimes six DIFFERENT enemies rather than one enemy in six coats of paint.
	# A water slime's poison ball deals water damage because the slime is water,
	# not because a second poisonball scene exists.
	#
	# current_element() rather than enemy_data.element, so a slime split off a
	# water parent passes its water down with it — see element_override.
	if "element" in projectile:
		projectile.element = current_element()

	# And the shot LOOKS like it too. Same shader, same hue, so the orb leaving
	# a water slime is the blue the slime is.
	_recolour_projectile(projectile)

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


# Does this enemy's sheet carry this animation?
#
# Checked BEFORE calling _set_animation() for anything optional, because that
# function warns about a missing animation - correct when a walk cycle is
# absent, noise when the answer is "this enemy simply has no hit flash", which
# is true of most of them.
func _has_animation(anim_name: String) -> bool:
	if anim_name == "" or not has_node("animatedsprite2d"):
		return false
	var frames: SpriteFrames = ($animatedsprite2d as AnimatedSprite2D).sprite_frames
	return frames != null and frames.has_animation(anim_name)


# How long an animation actually runs, in seconds.
#
# READ OFF THE ART rather than written down next to it. A death animation that
# is held for a hardcoded duration goes wrong the moment the sheet is re-timed
# or a frame is added, and it goes wrong SILENTLY - either the corpse vanishes
# mid-dissolve or it lies there after the animation ended. Per-frame durations
# are summed rather than assumed equal, because SpriteFrames allows them to
# differ and this project's own art pipeline notes warn that they drift.
func _animation_seconds(anim_name: String) -> float:
	if not _has_animation(anim_name):
		return 0.0
	var frames: SpriteFrames = ($animatedsprite2d as AnimatedSprite2D).sprite_frames
	var speed: float = frames.get_animation_speed(anim_name)
	if speed <= 0.0:
		return 0.0
	var total: float = 0.0
	for i in range(frames.get_frame_count(anim_name)):
		total += frames.get_frame_duration(anim_name, i)
	return total / speed


# The direction word to build an animation name from. attack_direction is kept
# pointed at the player every frame, which is the right way for a corpse or a
# flinch to face; the fallback only matters before a player has been resolved.
func _facing_for_animation() -> String:
	if Facing.is_direction(attack_direction):
		return attack_direction
	return Facing.DOWN


# THE HIT FLASH IS DRAWN OVER WHATEVER FRAME IS ALREADY ON SCREEN, which is why
# it never interrupts anything.
#
# WHAT THE ART ALREADY TOLD US. hitflashdown on the boss sheet is three frames:
# the normal pose, the SAME pose blanked to pure white, then the normal pose
# again. It was never a flinch animation - it is a hand-drawn white-out, which
# is exactly the effect below, just baked into frames.
#
# So the first version of this played those frames, and that was the mistake.
# Swapping the animation does not just flash the enemy, it also throws away the
# pose it was holding: a boss hit mid-cast snapped out of its cast, the vine or
# the spike keyed to a frame of that animation never spawned, and for the boss
# the _on_animation_finished() that clears is_attacking never fired, freezing it
# for good. To avoid all that the flash had to be suppressed during attacks -
# and since the boss casts for 1.0s of every 1.5s, about two hits in three
# landed with a damage number and no flash at all. That is the "not syncing".
#
# Recolouring the pixels has none of those problems. The pose is untouched, so a
# boss flashes white MID-SWING and keeps swinging, and every hit lands its own
# flash because there is no animation state to collide with.
#
# THE SAME MECHANISM THE PLAYER USES, deliberately, after a detour through a
# shader that was a mistake.
#
# That version attached a ShaderMaterial to every enemy sprite and mixed the
# pixels toward white. It flashed correctly, but it changed the thing it was
# supposed to leave alone: the enemy now rendered through a custom shader at all
# times, and it carried a state that could get STUCK. flash_amount lives on the
# material, so a tween killed part-way - by a scene change, a pause, anything
# that stops tweens - leaves the sprite permanently part-white with nothing to
# put it back. A washed-out boss that never recovers is a far worse bug than a
# flash that is a little subtle on a dark sprite.
#
# A modulate tween cannot get stuck in the same way: modulate is a plain
# property with a known resting value, every flash ends by tweening back to it,
# and with no material attached the sprite renders exactly as authored.
#
# HOW FAST, AND WHY THIS NUMBER. The player's flash is
# maxf(0.05, hit_flash_duration * (1.0 - reduction)), so a character actually
# flashes somewhere between 0.150s undefended and 0.075s at the defence cap.
# Enemies were pinned at 0.150 - the SLOWEST a character ever flashes, and twice
# as slow as a well-defended one. Side by side in the same fight, the enemy
# flash visibly lagged the player's. 0.08 sits with a defended character, which
# is what the player spends most of the game being.
@export var hit_flash_duration: float = 0.08

# Brighter than white, so it overexposes rather than merely whitening. Exactly
# the value player.gd flashes to.
const HIT_FLASH_COLOR := Color(2.0, 2.0, 2.0, 1.0)

# CAPTURED AT READY RATHER THAN ASSUMED WHITE. bushmage3 in field.tscn is placed
# with a red modulate, and there will be more tinted variants - restoring to a
# hardcoded white would strip a variant's colour the first time it was hit and
# never give it back.
var _default_modulate: Color = Color.WHITE

# Held so a second hit can cancel the tween still running from the first.
# Without this the older tween keeps writing modulate on its own schedule and
# drags the new flash back toward default early.
var _hit_flash_tween: Tween = null


func play_hit_flash() -> void:
	if _dying or not has_node("animatedsprite2d"):
		return
	var sprite: AnimatedSprite2D = $animatedsprite2d

	if _hit_flash_tween != null and _hit_flash_tween.is_valid():
		_hit_flash_tween.kill()

	# Snap ON, ease OFF - that shape is what reads as an impact rather than a
	# pulse. Same two-step tween as player.gd::_play_hit_flash().
	_hit_flash_tween = create_tween()
	_hit_flash_tween.tween_property(sprite, "modulate", HIT_FLASH_COLOR, 0.0)
	_hit_flash_tween.tween_property(sprite, "modulate", _default_modulate, hit_flash_duration)


func _stop_acting() -> void:
	# Freeze an enemy that is playing out a death or some other resolution: no
	# movement, no further hits landing on it, no colliding with the player
	# while it finishes.
	#
	# LIFTED FROM poisonslime.gd, which had the only copy. It was never
	# slime-specific - every line of it is guarded by has_node - and the boss
	# needs exactly the same thing to play its death. A second identical copy
	# is how the four direction-picker implementations in this project drifted
	# apart (see the header of facing.gd), so it moved instead of being cloned.
	set_physics_process(false)
	velocity = Vector2.ZERO
	is_attacking = false

	if has_node("hurtbox"):
		$hurtbox.set_deferred("monitoring", false)
		$hurtbox.set_deferred("monitorable", false)
	if has_node("bodyshape"):
		$bodyshape.set_deferred("disabled", true)
	if has_node("attacktimer"):
		$attacktimer.stop()


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

# True from the moment a death animation STARTS PLAYING until the frame the
# death actually resolves. Distinct from _death_resolved on purpose: the loot
# roll and the kill report must still be reachable exactly once AFTER the
# animation, so the resolved flag cannot be set early — but nothing should be
# able to damage, move or re-kill the enemy while the corpse plays out either.
var _dying: bool = false



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

	# Applied to the enemy ITSELF rather than to a sprite, so it covers every
	# visual the scene carries — sprite, health bar, any effect node — the same
	# way a pet's root modulate does. See EnemyData.body_tint.
	modulate          = enemy_data.body_tint

	_apply_element_recolour()

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


func take_damage(amount: int, _element: int = Element.Type.NONE) -> void:
	# _dying as well as _death_resolved: a corpse playing out its death
	# animation is still a live node for about a second, and without this it
	# would keep taking hits, spawning damage numbers and re-entering _die().
	if _death_resolved or _dying:
		return

	hp = max(hp - amount, 0)
	damaged.emit(amount)

	_spawn_floating_label(amount, 0)

	if has_node("healthbar"):
		var bar: Range = $healthbar
		if bar.max_value != max_hp:
			bar.max_value = max_hp
		bar.value = _bar_displayable(bar, hp)
		_write_health_readout()

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

	# Survival only, both of them, and for the same reason. A killing blow gets
	# the death sound and the death animation instead — otherwise you hear the
	# thing grunt and die in the same frame, and the flash cuts off the death.
	play_hit_flash()
	Audio.play_at("enemy_hurt", global_position)


func _die() -> void:
	# Second layer of the same guard. take_damage() is the usual route in, but
	# anything holding a reference can call _die() directly, and the loot roll
	# must not be reachable twice by any path.
	if _death_resolved or _dying:
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

	# THE DEATH ANIMATION PLAYS LAST, AFTER EVERYTHING THAT MATTERS HAS ALREADY
	# HAPPENED, and the ordering is the whole point.
	#
	# The obvious build is to animate first and resolve afterwards. It is wrong:
	# the kill report, the XP and the loot would then sit behind a one-second
	# await on a node that can be freed at any moment — leave the scene or die
	# yourself while the boss is dissolving and is_instance_valid() comes back
	# false, the function returns, and the kill silently pays nothing. A boss
	# kill is the worst possible thing to lose to a timing accident.
	#
	# So the kill is fully resolved above and the corpse is then free to take as
	# long as it likes. If it does get freed mid-animation, nothing is lost;
	# only the dissolve was cut short.
	#
	# THE HOLD IS THE ANIMATION'S OWN LENGTH, read off the SpriteFrames rather
	# than written down here, so re-timing the art cannot leave a corpse
	# lingering or cut it off halfway.
	#
	# Enemies whose sheet has no death* frames — which is all of them except the
	# boss right now — skip straight to queue_free() exactly as before.
	#
	# THE NAME IS DELIBERATELY UNPREFIXED. poisonslime.gd has an _anim_prefix()
	# that turns its small form's clips into smallwalkdown, smallidleleft and so
	# on, and routing this through it would find smalldeathdown — then play it a
	# SECOND time, because poisonslime._die() has already shown its own death and
	# awaited it before handing control up. Leaving this unprefixed is what keeps
	# that override authoritative: _has_animation("death" + dir) is false for
	# both slime forms, so neither reaches this branch at all.
	var death_anim: String = "death" + _facing_for_animation()
	if _has_animation(death_anim):
		_dying = true
		_stop_acting()
		_set_animation(death_anim)
		await get_tree().create_timer(_animation_seconds(death_anim)).timeout
		if not is_instance_valid(self):
			return

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
	# TURNED OFF BY THE OPTIONS SCREEN, if the player asked. This is the side
	# that produces most of them — one per hit per enemy, and a warrior
	# cleaving five at once produces five — which is exactly why the switch
	# exists. Only DAMAGE is gated; see player.gd's copy of this guard.
	if type == FloatingLabel.Type.DAMAGE and not Settings.get_value("damage_numbers"):
		return

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
