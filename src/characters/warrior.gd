# warrior character — fast melee fighter with cursor-aimed attacks.
# the warrior's signature: free melee swings plus mana-gated slashwave
# projectiles for extended reach, letting the warrior compete with ranged
# classes against electric/fire enemies they can't safely approach.
#
# class identity:
# - balanced HP / mana / stamina, fast move speed
# - free melee swing (always available, no resource cost)
# - mana-gated slashwave projectile during contact frames (extends reach)
# - attack skill climbs 50% faster than for any other class landing the same
#   hits (see _set_skill_proficiency)
#
# THE STAT CURVE IS NOT WRITTEN DOWN HERE ON PURPOSE. It lives in
# data/classes/warrior.tres and nowhere else. It used to be listed in this
# comment as well, which is a second copy that cannot be checked against the
# first — and the moment the .tres is retuned the comment is a lie that reads
# like documentation. CLASS_DATA below is the one source.
#
# damage architecture:
# 'attack' is the SKILL stat (player progression, 1->99 like other skills).
# it is NOT the damage value. damage = base_melee_damage scaled by the shared
# get_damage_multiplier(). when the equipment system is built,
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
# CURSOR-AIM ATTACK
# -----------------
# - triggered by EITHER spacebar OR right-click, both dispatched by
#   player.gd's _poll_attack_pressed() for every class alike. warrior used to
#   poll right-click privately to avoid colliding with mage's separate
#   right-click cast; that collision was imaginary, since mage's
#   attack_action() IS that cast, so all four copies of the poll are gone.
# - on trigger, we read get_global_mouse_position() and compute a direction
#   vector from the warrior to the cursor. that direction drives:
#     1. which attack animation plays — snapped to the nearest of 8 equal
#        45° wedges (4 cardinals + 4 diagonals) via _octant_from_direction(),
#        NOT player.gd's get_attack_animation() (that one stays 4-way, since
#        mage/tank/healer don't have diagonal art). falls back silently to
#        a cardinal animation if the diagonal clip doesn't exist yet. the
#        four diagonals (attackupleft/upright/downleft/downright) are NOT
#        in warrior.tscn — this is known and expected, not an oversight,
#        which is why the fallback no longer warns about it. drop the
#        fallback entirely once all 8 attack animations are in.
#     2. which hitboxXXXX node is treated as "active" for this swing —
#        STILL 4-way (see note below), independent of the animation's
#        granularity.
# - the SLASHWAVE is full 360 in every way that can be felt: it spawns along
#   the exact aim angle (see wave_muzzle_offset), travels along it via
#   slashwave.gd's shoot_vector(), and cuts along it — that file rotates one
#   collision box onto the travel angle rather than picking one of four
#   axis-aligned ones. only its SPRITE still snaps to the nearest of four,
#   because only four were drawn.
# - MELEE HIT DETECTION is still cardinal-snapped (4-way): hitboxleft/right/
#   up/down are 4 fixed pre-placed Area2D nodes. the swing's cardinal is now
#   resolved ONCE (see _resolve_swing_cardinal — the tuned bias/hysteresis) and
#   handed to both the hitbox and the animation fallback, so what you see and
#   what you hit stay in step. if/when 4 more hitbox nodes get added for the
#   diagonals, that resolver is the single place to switch to 8-way. not done
#   here — pending a decision on whether that scene work is worth it, since a
#   single rotating hitbox would be MORE precise than the 8-pose art can
#   visually justify anyway.
# - warrior does not freeze movement during the swing (player.gd's
#   attack_locks_movement is set false below), so you keep walking while
#   attacking.
#
# attack flow:
# 1. attack_action reads cursor direction, resolves EVERYTHING that stays
#    fixed for this swing (animation, lock duration, active hitbox), plays
#    the animation, resets per-swing state
# 2. _on_frame_changed during contact frames (2-5): scan hitbox, damage enemies
# 3. _on_frame_changed on the release frame (wave_spawn_frame, clamped to the
#    clip — see _swing_wave_frame): spawn slashwave if mana permits
# 4. each enemy can only be hit ONCE per swing (cleave, no multi-tick)
extends "res://src/characters/player.gd"

# This class's stat curve. See ClassData — hp_base and friends used to be
# literals in _set_stat_curve() below, which meant the server knew your level
# and your class and still could not work out your maximum health.
const CLASS_DATA := preload("res://data/classes/warrior.tres")
# How fast this class walks, before agility and sprinting (player.gd). A
# constant so the exporter can read it: presence.py holds a character to it
# (gamedata.py, "COMBAT BOUNDS").
const CLASS_SPEED := 200


# =============================================================================
# CONSTANTS
# =============================================================================

# preloaded slash wave projectile scene
const SLASHWAVE_SCENE := preload("res://scene/projectiles/slashwave.tscn")

# The sparks (strikefx.gd, 0.38.0).
const Strike := preload("res://src/shared/strikefx.gd")

# THE DOUBLE AXE'S ATTACK. With it equipped, attack throws the axe and attack
# again calls it back - see spinningaxe.gd. The swing animation still plays as
# the throw, but it carries no hitbox and no slash wave: the axe is the hit.
const SPINNING_AXE_SCENE := preload("res://scene/projectiles/spinningaxe.tscn")

# The axe while it is out of the warrior's hand, or null. Read with
# is_instance_valid(): the axe frees itself when it is caught, and a scene
# change frees it with everything else.
var _axe: SpinningAxe = null
# THE ROLL's two chances (spinningaxe.gd), as vars so a test can make a roll
# certain either way, as Player.double_cast_chance is.
var axe_wide_chance: float = SpinningAxe.WIDE_CHANCE
var axe_blood_chance: float = SpinningAxe.BLOOD_CHANCE

# THE REACH RING (0.29.0, rangering.gd) - the owner: "now we need one for
# range on warrior like distance for attack". A dashed line round the warrior
# at how far a mythic's attack reaches: with the Double Axe, the furthest it
# flies plus the reach of its blade (190).
#
# MYTHIC ONLY SINCE 0.29.1. 0.29.0 drew one for the sword too, read off its
# four hitboxes - 25 to 32 px, about the warrior's own width - and the owner,
# seeing it: "i need to change when holding mythic to show the change in range
# also" / "that small circle for warrir for range with that weapon is not
# needed". So with anything but a mythic in hand there is no line. The slash
# wave never had one: it flies until it hits a wall or leaves the screen.
const REACH_COLOUR := Color(1.0, 0.95, 0.8, 0.3)
var _reach_ring: RangeRing = null
# How far the weapon in hand reaches, as the ring shows it: 0 for no ring.
var _mythic_reach: float = 0.0

# cardinal directions array — used by _detect_hitboxes() to avoid 4x duplication
const CARDINAL_DIRECTIONS := ["left", "right", "up", "down"]

# 8 directions in angle order starting at 0° (right), going clockwise
# in screen space (Y+ is down). index = round(angle / 45°), wrapped to 0-7.
# used only for animation selection right now — see _octant_from_direction().
const OCTANT_DIRECTIONS := [
	"right", "downright", "down", "downleft",
	"left", "upleft", "up", "upright"
]

# =============================================================================
# 4-WAY SWING TUNING  (until the 4 diagonal attack frames exist)
# =============================================================================
# Both knobs affect ONLY diagonal aims — a clearly horizontal or vertical aim is
# untouched by either. Exported so they can be dialed in the Inspector without
# touching code.

# Favors the LEFT/RIGHT swing on a diagonal aim. The old rule snapped a perfect
# 45° aim to VERTICAL (abs(x) > abs(y) is false when they're equal), so walking
# left and attacking with the cursor even a little high flipped the swing to UP.
# >1 widens the horizontal cone: at 1.3, left/right keep winning until the aim is
# within ~38° of straight up or down. 1.0 restores the old dominant-axis rule.
@export var swing_horizontal_bias: float = 1.3

# Hysteresis. Holds the CURRENT swing facing until the other axis beats it by
# this margin, so sweeping the cursor across the 45° line during rapid swings
# doesn't strobe between two cardinals. 1.0 = off; ~1.3 = noticeably sticky.
# Off by default, so the bias above is the only change to feel first.
@export var swing_facing_stickiness: float = 1.0

# The cardinal the previous swing resolved to — the state the hysteresis needs.
var _last_swing_cardinal: String = ""


# A direction vector shorter than this counts as "no direction at all", which
# happens when the cursor sits exactly on the player. Compared against
# length_squared() so neither of the two hot paths that use it takes a sqrt:
# this is 0.001 squared.
const AIM_EPSILON_SQUARED: float = 0.000001


# =============================================================================
# EXPORTED SETTINGS — DAMAGE WINDOW
# =============================================================================

@export var contact_frame_start: int = 2
@export var contact_frame_end:   int = 5
@export var wave_spawn_frame: int = 6


# =============================================================================
# EXPORTED SETTINGS — DAMAGE VALUES
# =============================================================================

@export var base_melee_damage: int = 24
@export var wave_damage_ratio: float = 0.75
@export var slashwave_mana_cost: int = 10

# How far in front of the warrior the slashwave spawns, along the exact aim
# direction. Same muzzle-offset technique pet.gd uses for its own projectile
# spawning, and it replaced four fixed wavespawn Marker2D nodes that have
# since been deleted from warrior.tscn.
#
# THE MARKERS WERE THE BUG, not a thing worth keeping. Travel direction was
# already true 360 via shoot_vector(), but the LAUNCH POINT snapped to one of
# 4 fixed spots and flew off at an angle from there, so a diagonal swing
# visibly threw its wave from the wrong place. An offset along the aim vector
# scales continuously with the angle; four markers cannot.
#
# Reduced from 24 to 10 — the wave was spawning several tiles from the
# character, visually disconnected from the swing. If it is STILL spawning far
# away, check the warrior scene's Inspector for an explicit override on this
# exact field — as an @export, a value set there beats whatever this script
# declares as default.
@export var wave_muzzle_offset: float = 10.0

# How fast the attack animation itself plays, independent of walk/sprint
# speed. Doesn't change WHICH frames trigger damage/wave (contact_frame_start/
# end and wave_spawn_frame are frame-index based, not time-based) — it just
# compresses the whole swing into less real time. This is also a practical
# mitigation for the cardinal-snap mismatch (the pose can be up to 45° off
# from your actual cursor aim while moving): a faster swing means that
# mismatched pose is on screen for less time, even though it doesn't fix the
# underlying snap.
#
# attack_lock_duration scales down with this automatically, since it is
# computed from the real animation duration — no need to tune that separately.
@export var attack_animation_speed: float = 3.5

# Safety-net backstop, separate from animation_finished. If an attack
# animation's Loop property is ever accidentally left ON in the SpriteFrames
# editor, animation_finished NEVER fires for it (looping animations don't
# "finish"), which would leave is_attacking stuck true FOREVER — permanently
# freezing the swing on screen and blocking all future attacks, since
# attack_action() guards on `if is_attacking: return`. pet.gd hit this exact
# trap and works around it the same way (see its _release_attack_lock_after).
#
# This is a MINIMUM floor rather than the actual timer value — attack_action()
# computes the real animation duration from whichever clip is actually playing
# and uses whichever is larger. It only decides the outcome when that
# computation can't run at all (missing animation, zero FPS).
@export var attack_lock_duration: float = 1.0


# =============================================================================
# STATE
# =============================================================================

# Enemies already damaged by the swing in progress, held as instance IDs
# rather than Node references.
#
# TWO REASONS, AND THE SECOND IS THE REAL ONE. A Dictionary lookup is O(1)
# where scanning an Array is O(n) per candidate per contact frame — but with a
# handful of enemies in a hitbox that difference is noise. What matters is
# that a plain int cannot dangle: an enemy killed by the first contact frame
# is queue_free()d while this swing still has three frames to run, and an
# Array of Node references would spend them comparing against a freed object.
# The ID of a freed node simply never matches a live one again.
var _hit_this_swing: Dictionary = {}

var _wave_spawned_this_swing: bool = false

# Increments every time a new swing starts. The safety-net timer captures
# whatever ID was current when IT was scheduled — if a newer swing has started
# by the time that timer fires, its captured ID won't match _swing_id anymore,
# and it knows it's stale and does nothing instead of reaching into whatever
# swing happens to be running now. Fixes rapid double/triple-clicking
# cancelling a LATER swing via a leftover timer from an EARLIER one that
# already finished normally.
var _swing_id: int = 0

# EVERYTHING BELOW IS FIXED FOR THE LIFE OF ONE SWING, so it is resolved once
# in attack_action() instead of being recomputed on every contact frame.
#
# That is not only cheaper, it is the only version that is correct. The aim is
# deliberately captured at the instant the swing starts so a moving cursor
# can't change which hitbox is "live" partway through — and re-deriving the
# hitbox from that frozen aim on all four contact frames was four chances to
# get a different answer from the same input for no benefit.
var _swing_aim_direction: Vector2 = Vector2.DOWN
var _swing_hitbox: Area2D = null

# The frame this swing releases its wave on — wave_spawn_frame, unless that
# index does not exist in the clip being played.
#
# THE MATCH IS EXACT AND THE FAILURE IS SILENT. _on_frame_changed() compares
# `frame == wave_spawn_frame`, so a clip with fewer frames than that simply
# never reaches it: no wave, no warning, no error, and the swing otherwise
# looks completely normal. Every attack animation today is exactly 7 frames
# (0-6) against a wave_spawn_frame of 6 — the wave fires on the last frame
# with nothing to spare, and the first shorter clip anyone adds would delete
# the ability for that direction without saying so.
#
# Clamping to the clip's last frame means a shorter animation fires late
# rather than not at all, which is the failure worth having.
var _swing_wave_frame: int = 0

# =============================================================================
# THE WARRIOR'S BLOWS, SEEN AND FELT (0.38.0, 0.39.0)
# =============================================================================
# The owner: "the final character warrioe how can we make him better also",
# and all four of what was offered. Then, of 0.38.0's arc and the wave's
# afterimages: "its horrible ... the trails are bad i would say maybe the gold
# one is cool but no trails we can use projectiles from crypt to elavate" -
# so 0.39.0 took the arc and the trails out and put the crypt's orbs in, all
# four ways offered (bladeorb.gd).
#
#   the sparks       Strike.sparks() where the sword lands on each monster
#   the sword fan    on the first contact frame of every sword swing,
#                    SWORD_FAN_ORBS small steel crypt orbs flung the way it
#                    aims, SWORD_FAN_SPREAD_DEGREES apart, SWORD_FAN_REACH
#                    out, each for SWORD_FAN_SHARE of a swing
#   the weight       THE HIT-STOP: the first time a swing connects, the
#                    warrior's picture and the monster's stop for
#                    HITSTOP_SECONDS - a picture only: nothing in the fight is
#                    paused - and the camera gives a small shake (HIT_SHAKE).
#                    The swing lock ends when the swing's animation does
#                    (player.gd), so a held picture would make every next
#                    swing that much later; the warrior's plays the rest of the
#                    swing faster after the hold (swing_time_left()), and ends
#                    when it would have.
#   the finisher     every FINISHER_EVERY-th swing (3rd) throws a gold wave
#                    FINISHER_SCALE as big for FINISHER_MULT (1.5x) its damage,
#                    with gold sparks, gold orbs and a longer stop:
#                    FINISHER_FAN_ORBS fanned out beside the wave, and the
#                    wave's burst (slashwave.gd, THE BURST), each orb for
#                    FINISHER_ORB_SHARE of the wave. Not with the Double Axe:
#                    its swing is the throw.
#   the weave        two orbs crossing over every wave (slashwave.gd)
#
# The exporter writes the numbers, and the server's books allow for them.
const FINISHER_EVERY := 3
const FINISHER_MULT := 1.5
const FINISHER_SCALE := SlashWave.FINISHER_SCALE
const HITSTOP_SECONDS := 0.06
const FINISHER_HITSTOP_SECONDS := 0.09
const HIT_SHAKE := Vector2(0.8, 0.08)
const SWORD_FAN_ORBS := 3
const SWORD_FAN_SHARE := 0.1
const SWORD_FAN_SPREAD_DEGREES := 18.0
const SWORD_FAN_SPEED := 260.0
const SWORD_FAN_REACH := 70.0
# From the middle of the warrior's picture, this far along the aim: the blade.
const SWORD_FAN_FROM := 8.0
const FINISHER_FAN_ORBS := 4
const FINISHER_FAN_SPREAD_DEGREES := 12.0
const FINISHER_FAN_REACH := 300.0
const FINISHER_ORB_SHARE := 0.15

# Swings with the sword since the warrior was made, for THE FINISHER.
var _swings: int = 0
# This swing is the finisher.
var _finisher: bool = false
var _fanned_this_swing: bool = false
var _stopped_this_swing: bool = false

# right-click attack lives in Player (see its ATTACK INPUT section). The
# private tracker that used to sit here is gone, along with the reasoning
# about avoiding a collision with mage's cast — that collision was never real.
# mage's attack_action() IS its stalagmite cast, so routing right-click to
# attack_action() for everyone gives mage exactly the same cast it already had,
# through one path instead of two.


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


# =============================================================================
# STAT CURVE
# =============================================================================

func _set_stat_curve() -> void:
	# warrior: balanced HP, moderate mana for slashwave uptime, solid stamina.
	# called by player.gd._ready BEFORE recompute, so these drive max stats.
	_apply_class_data(CLASS_DATA)


# =============================================================================
# SKILL PROFICIENCY
# =============================================================================

func _set_skill_proficiency() -> void:
	# warrior's specialty: attack climbs 50% faster than any other class.
	# Attack trains at the kill and the SERVER applies this (its own
	# SKILL_PROFICIENCY, the same 1.5), so this entry is the client's copy of
	# the table rather than a multiplier anything here applies to attack.
	#
	# This replaced a flat +1 attack / +1 defense granted on every character
	# level-up. That fired no matter how the level was earned, so a warrior who
	# levelled on fishing XP got melee skill for it; this only pays out for
	# actually landing hits.
	skill_proficiency["attack"] = 1.5


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# class identity — always set, regardless of save state.
	character_name = "warrior"
	speed = CLASS_SPEED

	# don't freeze movement while is_attacking — warrior keeps walking through
	# its swing. mage/tank/healer are unaffected since this defaults to true on
	# the base class.
	attack_locks_movement = false

	# super._ready() calls _set_stat_curve(), loads save, recomputes maxes
	# from level, and fills resources to full. no manual stat block needed.
	super._ready()

	_detect_hitboxes()
	_wire_animation_signal()
	# THE AIM RING (0.26.0, player.gd): "add to warrior also".
	_add_aim_ring()
	# And how far the attack reaches (0.29.0).
	_add_reach_ring()


func _physics_process(delta: float) -> void:
	# parent handles movement (WASD), attack dispatch from BOTH spacebar and
	# right-click, animation switching, universal regen, and universal sprint.
	# warrior adds nothing to the input path any more.
	super._physics_process(delta)
	# The ball points where the next swing - its wave, or the axe - would go.
	_point_aim_ring(aim_direction_to(get_global_mouse_position()))
	if _reach_ring != null:
		_reach_ring.visible = _reach_ring_shown()


# =============================================================================
# INITIALIZATION HELPERS
# =============================================================================

func _detect_hitboxes() -> void:
	# get_node_or_null() rather than has_node() + get_node(), which walked the
	# same path twice to answer one question.
	for dir in CARDINAL_DIRECTIONS:
		hitboxes[dir] = get_node_or_null("hitbox" + dir) as Area2D


func _wire_animation_signal() -> void:
	if sprite == null:
		return
	if not sprite.frame_changed.is_connected(_on_frame_changed):
		sprite.frame_changed.connect(_on_frame_changed)


# =============================================================================
# DAMAGE CALCULATION
# =============================================================================

func _calculate_melee_damage() -> int:
	# Routes through player.gd's get_damage_multiplier(), the same shared
	# function every class's damage uses — folds in magic too, and keeps
	# warrior consistent with how tank/mage/healer's damage works underneath.
	# It replaced base_melee_damage + int((attack - 1) / 2), which was
	# attack-only, linear, and warrior's private formula.
	#
	# NEW: THE EQUIPPED WEAPON, ADDED RATHER THAN SUBSTITUTED. The note at the
	# top of this file asked for a substitution — "base_melee_damage should be
	# replaced by the equipped weapon's damage" — and that is not what happens,
	# deliberately. Replacing makes an unarmed warrior deal nothing, which turns
	# the first sword into a power switch rather than an upgrade; and the same
	# rule has to serve the tank, whose damage is an aura tick, and the healer,
	# who fires ten shots a second. Adding is the rule all four can share.
	#
	# ROLLED HERE, WHICH IS ONCE PER ENEMY. _try_damage() calls this per target,
	# so a five-target cleave rolls five times and the numbers that pop off the
	# five enemies differ — which is right, and is what the spread is for.
	#
	# roundi RATHER THAN int, which is a truncation this formula never should
	# have had: int() always rounds toward zero, so every multiplier below a
	# whole number lost a fraction of a point on every single hit. It cost the
	# healer most — 3 base damage truncated at a 1.16 multiplier is still 3 —
	# and it cost everyone something.
	return roundi((base_melee_damage + weapon_damage_roll()) * get_damage_multiplier())


func base_attack_damage() -> int:
	# See player.gd's base_attack_damage(). The warrior's is the one the other
	# three are scaled against — the weapon ladder is authored as a proportion
	# of this 24.
	return base_melee_damage


func attack_period() -> float:
	# One swing per lock. See player.gd's attack_period() for what reads this.
	# attack_lock_duration rather than _swing_lock_duration(), which measures
	# the real animation and needs a sprite in the tree — a tooltip is hovered
	# while standing still, and the exported value is the number being tuned.
	# hasten() applies agility, so the dps this feeds is the rate actually
	# being delivered rather than the base one.
	return hasten(attack_lock_duration)


# =============================================================================
# ATTACK ACTION
# =============================================================================

func attack_action() -> void:
	# With the Double Axe out, attack is the call back - and it is answered
	# before the swing lock, so the axe comes home even mid-throw-animation.
	var axe_mode: bool = equipped_weapon_attack() == ItemData.WeaponAttack.SPINNING_AXE
	if axe_mode and axe_is_out():
		_axe.recall()
		return

	if is_attacking:
		return

	_set_active()
	is_attacking = true

	# The swing itself, not the connect. attack_hit fires separately from
	# BaseEnemy.take_damage() when it lands, so a miss still sounds like a
	# swing and a hit sounds like both.
	Audio.play("attack_swing")

	_swing_id += 1
	var this_swing_id: int = _swing_id

	_hit_this_swing.clear()
	_wave_spawned_this_swing = false
	_fanned_this_swing = false
	_stopped_this_swing = false
	_finisher = false

	# Aim toward the cursor instead of the last WASD direction. Fall back to
	# last_direction if the cursor is sitting exactly on the player
	# (zero-length vector, e.g. controller/edge case) so we never animate
	# toward a garbage direction.
	_swing_aim_direction = aim_direction_to(get_global_mouse_position())
	_aim_ring_fired()
	if _reach_ring != null:
		_reach_ring.fired()

	# Sync last_direction to the aim. Without this, get_idle_animation()
	# (called by player.gd once the swing animation finishes) reads
	# last_direction — which is ONLY ever updated by actual WASD movement,
	# never by this cursor-aim attack. That meant the swing itself would
	# correctly face wherever you aimed, then immediately snap back to idle
	# facing whatever direction you last WALKED the moment it finished — e.g.
	# aiming right while your last move was leftward would show a rightward
	# swing that instantly reverted to facing left.
	last_direction = _swing_aim_direction

	# Direction resolved ONCE here (with the 4-way tuning above applied), then
	# handed to BOTH the hitbox and the animation. Resolving it once is not just
	# tidiness: _resolve_swing_cardinal() advances the hysteresis state, so
	# calling it twice per swing would double-step it and could let the hitbox
	# and the sprite disagree about which way this swing went.
	var swing_cardinal: String = _resolve_swing_cardinal(_swing_aim_direction)
	_swing_hitbox = _resolve_swing_hitbox(swing_cardinal)
	if axe_mode:
		# THE SWING IS THE THROW. No hitbox, and the wave counts as already
		# spawned, so _on_frame_changed() below plays the animation and does
		# nothing else.
		_swing_hitbox = null
		_wave_spawned_this_swing = true
		throw_axe(get_global_mouse_position())
	else:
		_swings += 1
		_finisher = finisher_on(_swings)

	var anim: String = _resolve_swing_animation(swing_cardinal)
	_swing_wave_frame = _resolve_wave_frame(anim)

	if anim != "":
		sprite.play(anim)
		sprite.frame = 0
		sprite.speed_scale = _agile_animation_speed()

	_release_attack_lock_after(_swing_lock_duration(anim), this_swing_id)


func aim_direction_to(point: Vector2) -> Vector2:
	"""The way a swing at `point` goes - the cursor, for a real one - from the
	warrior's origin, which is the middle of its picture (its sprite is drawn
	3 px above it and its feet 13 below). The aim ring reads this too, so the
	ball and the wave cannot disagree. The cursor exactly on the warrior
	keeps the last facing."""
	var to_point: Vector2 = point - global_position
	if to_point.length_squared() <= AIM_EPSILON_SQUARED:
		return last_direction
	return to_point.normalized()


func aim_ring_feet() -> Vector2:
	# The aim ring (player.gd): the warrior's feet are 13 px below its origin
	# (bodyshape), and the ring sits a hair above them so the sprite - also at
	# 13, in a y-sorted body - is drawn after it.
	return Vector2(0.0, 12.5)


func _resolve_swing_hitbox(cardinal: String) -> Area2D:
	return hitboxes.get(cardinal)


func _resolve_swing_animation(cardinal: String) -> String:
	# Returns the clip to play, or "" when there is nothing playable — which
	# is not fatal: the swing still deals damage, it just doesn't animate.
	#
	# `cardinal` is the already-tuned 4-way fallback, resolved once by the caller
	# so the animation and the hitbox agree. The 8-way octant is still tried
	# FIRST and straight off the raw aim, so the moment a diagonal clip is drawn
	# it takes over untouched by the fallback's horizontal bias.
	#
	# sprite_frames IS CHECKED FOR NULL HERE, and it did not used to be. The
	# lock-duration block below guarded it and this one didn't, so a warrior
	# whose SpriteFrames failed to load crashed on the first swing rather than
	# swinging invisibly. One resolution now serves both, so the two can't
	# disagree about that again.
	if sprite == null or sprite.sprite_frames == null:
		return ""

	var frames: SpriteFrames = sprite.sprite_frames

	# 8-directional first. Falls back to the tuned cardinal if the diagonal
	# clip isn't in the SpriteFrames yet, which lets code and testing proceed
	# before all 8 attack animations exist.
	#
	# This fallback used to push_warning() every time it fired. Since the four
	# diagonals genuinely aren't drawn yet, that meant a warning on essentially
	# every swing — most mouse aims aren't perfectly cardinal — burying real
	# warnings under known, expected noise. The missing clips are documented in
	# the class comment instead. REMOVE the fallback entirely once the artist
	# delivers all 4 diagonals.
	var anim: String = "attack" + _octant_from_direction(_swing_aim_direction)
	if frames.has_animation(anim):
		return anim

	anim = "attack" + cardinal
	if frames.has_animation(anim):
		return anim

	return ""


func _resolve_wave_frame(anim: String) -> int:
	# See _swing_wave_frame for why this clamps rather than trusting the export.
	if anim == "":
		return wave_spawn_frame

	var last_frame: int = sprite.sprite_frames.get_frame_count(anim) - 1
	if last_frame < 0:
		return wave_spawn_frame

	return mini(wave_spawn_frame, last_frame)


func _agile_animation_speed() -> float:
	# THE SWING HAS TO PLAY AS FAST AS IT LANDS, which is why agility is
	# applied to the animation here and not only to the cooldown.
	#
	# _swing_lock_duration() below takes maxf(attack_lock_duration, the real
	# animation duration). So shortening only the exported cooldown would do
	# nothing at all past a modest agility: the animation length would win the
	# maxf and the warrior would keep swinging at the base rate no matter how
	# high the stat went. Speeding the clip up shortens the real duration by
	# the same factor, so both halves of that maxf scale together.
	#
	# It also keeps the swing looking like what it is. A warrior attacking
	# twice as often with a swing that still takes a full second to play would
	# have the second swing start before the first had visibly finished.
	return attack_animation_speed * get_attack_speed_multiplier()


func _swing_lock_duration(anim: String) -> float:
	# attack_lock_duration was once a static guessed value — and if the REAL
	# animation (which varies by direction and frame count, especially with
	# 8-way art arriving from different sources) took longer than that guess,
	# the safety-net timer fired BEFORE the animation naturally finished,
	# forcibly interrupting the swing mid-play and snapping to idle early.
	# That was a real cancellation bug, not just a facing mismatch.
	#
	# So: compute the real duration from whichever clip is actually playing
	# (frame count ÷ FPS ÷ speed scale) and take whichever is LARGER. The timer
	# is then always comfortably longer than the real swing and can only fire
	# as a true backstop (Loop accidentally left on), never during normal
	# correct playback.
	# BOTH HALVES OF THE maxf ARE HASTENED BY AGILITY, or neither is. The floor
	# is hasten(attack_lock_duration) and the real duration is computed from
	# the same sped-up clip that is actually playing, so a fast warrior does
	# not get held by a backstop meant for a slow one.
	# `swing_speed`, not `speed` — player.gd declares `speed` as the movement
	# stat and this script extends it, so a local by that name shadows it for
	# the rest of the function. Nothing here reads movement speed, which is
	# exactly why it would have gone unnoticed.
	var swing_speed: float = _agile_animation_speed()
	if anim == "" or swing_speed <= 0.0:
		return hasten(attack_lock_duration)

	var fps: float = sprite.sprite_frames.get_animation_speed(anim)
	if fps <= 0.0:
		return hasten(attack_lock_duration)

	var frame_count: int = sprite.sprite_frames.get_frame_count(anim)
	var real_duration: float = (float(frame_count) / fps) / swing_speed
	return maxf(hasten(attack_lock_duration), real_duration + 0.2)


func _release_attack_lock_after(seconds: float, swing_id: int) -> void:
	# see attack_lock_duration's comment above for why this exists, and
	# _swing_id's comment for why the ID check below is necessary.
	await get_tree().create_timer(seconds).timeout

	# THE VALIDITY CHECK COMES FIRST because every check after it reads a
	# member of `self`. This awaits a wall-clock timer, and a scene change
	# during the swing frees the warrior while that timer keeps running — so
	# by the time execution resumes here there may be nothing left to ask
	# about a swing ID.
	if not is_instance_valid(self) or not is_inside_tree():
		return

	# stale timer from an OLDER swing that already finished normally — a
	# newer swing has started since this one was scheduled. do nothing;
	# acting here would cancel whatever swing is ACTUALLY in progress now.
	if swing_id != _swing_id:
		return

	# If the player died mid-swing, this timer is STILL scheduled from before
	# death — the death sequence never resets is_attacking itself, only
	# is_dying. Without this check, the timer would fire during the death
	# animation and forcibly overwrite it with an idle pose via
	# sprite.play(get_idle_animation()) below, before the death animation ever
	# got a chance to finish and fire animation_finished. That is exactly what
	# silently skipped the game-over transition: the death animation plays for
	# a moment, then gets stomped by this leftover timer, never completing.
	if is_dying:
		return

	if is_attacking:
		is_attacking = false
		if sprite != null:
			sprite.play(get_idle_animation())


func _on_frame_changed() -> void:
	if not is_attacking:
		return
	if sprite == null:
		return
	if not sprite.animation.begins_with("attack"):
		return

	var frame: int = sprite.frame

	if frame >= contact_frame_start and not _fanned_this_swing and _swing_hitbox != null:
		_fanned_this_swing = true
		fling_sword_fan()

	if frame >= contact_frame_start and frame <= contact_frame_end:
		_deal_melee_damage()

	if frame == _swing_wave_frame and not _wave_spawned_this_swing:
		_spawn_slashwave()
		_wave_spawned_this_swing = true


# =============================================================================
# MELEE DAMAGE
# =============================================================================

func _deal_melee_damage() -> void:
	if _swing_hitbox == null:
		return

	# NO XP HERE. A swing used to add 5 attack XP per enemy it touched, on this
	# screen only - attack trains at the kill, on the server, and that is the
	# number the bar shows now (Player.apply_server_attack()).
	for area in _swing_hitbox.get_overlapping_areas():
		_try_damage(area.get_parent())

	for body in _swing_hitbox.get_overlapping_bodies():
		_try_damage(body)


func _try_damage(target: Node) -> int:
	# Returns 1 when this call actually damaged something, 0 otherwise, so the
	# caller can pay the XP for a whole pass in one go.
	if target == null:
		return 0
	if not target.is_in_group("enemies"):
		return 0

	var target_id: int = target.get_instance_id()
	if _hit_this_swing.has(target_id):
		return 0

	if not target.has_method("take_damage"):
		return 0

	_hit_this_swing[target_id] = true
	target.take_damage(_calculate_melee_damage())
	if target is Node2D and is_inside_tree():
		Strike.sparks(get_parent(), Strike.hit_point(target as Node2D),
			Strike.GOLD if _finisher else Strike.STEEL)
	if not _stopped_this_swing:
		_stopped_this_swing = true
		_hit_stop(target)
	return 1


func fling_sword_fan(into: Node = null) -> Array[BladeOrb]:
	"""THE SWORD FAN: SWORD_FAN_ORBS crypt orbs off the blade, the way the
	swing aims - gold on the finisher. Into the area's projectiles, or `into`
	(the tests)."""
	var orbs: Array[BladeOrb] = []
	var parent: Node = into if into != null else _projectiles_parent()
	if parent == null:
		return orbs
	var each: int = maxi(1, int(_calculate_melee_damage() * SWORD_FAN_SHARE))
	var from: Vector2 = global_position + _swing_aim_direction * SWORD_FAN_FROM
	for way in BladeOrb.fan_ways(_swing_aim_direction, SWORD_FAN_ORBS, SWORD_FAN_SPREAD_DEGREES, false):
		orbs.append(BladeOrb.fire(parent, from, way, SWORD_FAN_SPEED, SWORD_FAN_REACH, each,
			BladeOrb.GOLD if _finisher else BladeOrb.STEEL))
	return orbs


static func finisher_on(swing: int) -> bool:
	"""Whether sword swing number `swing` (the first is 1) is THE FINISHER."""
	return swing > 0 and swing % FINISHER_EVERY == 0


func _hit_stop(target: Node) -> void:
	"""THE HIT-STOP: the warrior's picture and the monster's held still for a
	moment, and a small shake. Pictures only - the fight goes on."""
	var seconds: float = FINISHER_HITSTOP_SECONDS if _finisher else HITSTOP_SECONDS
	# Each picture held, and the speed it goes on at after.
	var held: Array[AnimatedSprite2D] = []
	var speeds: Array[float] = []
	var theirs: AnimatedSprite2D = target.get_node_or_null(^"animatedsprite2d") as AnimatedSprite2D
	if theirs != null:
		held.append(theirs)
		speeds.append(theirs.speed_scale)
	# The warrior's own: the rest of the swing played in what is left of it
	# after the hold, so it ends - and the swing lock with it - on time. Not
	# held at all so near the end that it would have to rush.
	if sprite != null:
		var left: float = swing_time_left(sprite)
		if left > seconds * 2.0:
			held.append(sprite)
			speeds.append(sprite.speed_scale * left / (left - seconds))
	for picture in held:
		picture.speed_scale = 0.0
	shake_camera(HIT_SHAKE.x * (1.5 if _finisher else 1.0), HIT_SHAKE.y)
	var tree: SceneTree = get_tree() if is_inside_tree() else (target.get_tree() if target.is_inside_tree() else null)
	if tree == null:
		return
	await tree.create_timer(seconds).timeout
	for i in held.size():
		# Only a picture still held: one that has played something else since
		# (a new swing sets its own speed) is left alone.
		if is_instance_valid(held[i]) and held[i].speed_scale == 0.0:
			held[i].speed_scale = speeds[i]


static func swing_time_left(picture: AnimatedSprite2D) -> float:
	"""Seconds until `picture`'s animation ends at its speed now - 0 for one
	that loops, is stopped, or has nothing to play."""
	var frames: SpriteFrames = picture.sprite_frames
	var anim: StringName = picture.animation
	if frames == null or not frames.has_animation(anim) or frames.get_animation_loop(anim) or picture.speed_scale <= 0.0:
		return 0.0
	var fps: float = frames.get_animation_speed(anim)
	var count: int = frames.get_frame_count(anim)
	if fps <= 0.0 or picture.frame >= count:
		return 0.0
	var left: float = -picture.frame_progress * frames.get_frame_duration(anim, picture.frame)
	for f in range(picture.frame, count):
		left += frames.get_frame_duration(anim, f)
	return maxf(left, 0.0) / fps / picture.speed_scale


# =============================================================================
# THE DOUBLE AXE
# =============================================================================

func axe_is_out() -> bool:
	return _axe != null and is_instance_valid(_axe) and not _axe.is_queued_for_deletion()


func throw_axe(aimed_at: Vector2) -> SpinningAxe:
	# Public so a test can throw one without a mouse. Returns the axe.
	if axe_is_out():
		return _axe
	_axe = SPINNING_AXE_SCENE.instantiate()
	_axe.caster = self
	# THE ROLL (spinningaxe.gd, 0.18.0): one throw in ten wide, one in a
	# hundred bloody, rolled apart - and before add_child(), because the axe
	# builds its circle, its dust and its blood at what it rolled.
	_axe.wide = common_forced() or SpinningAxe.rolls(randf(), axe_wide_chance)
	_axe.bloody = rare_forced() or SpinningAxe.rolls(randf(), axe_blood_chance)
	spawn_parent().add_child(_axe)
	_axe.throw_to(global_position, aimed_at)
	Audio.play("axe_throw")
	# A picture of it for everyone else in the area (0.19.0, remoteattacks.gd).
	Presence.tell_attack("axe", global_position, _axe.target, 0.0,
		RemoteAttacks.flags_for_axe(_axe.wide, _axe.bloody))
	return _axe


func _on_axe_caught() -> void:
	# spinningaxe.gd calls this as it frees itself in the warrior's hand.
	_axe = null
	Audio.play("axe_catch")


func _on_gear_changed() -> void:
	# The axe taken off while it is out: it is back in the bag, so the one in
	# the world goes. There is nothing to wait for it to fly back to.
	if axe_is_out() and equipped_weapon_attack() != ItemData.WeaponAttack.SPINNING_AXE:
		_axe.queue_free()
		_axe = null
	# The axe put on or taken off shows or hides the reach ring.
	_fit_reach_ring()


# =============================================================================
# THE REACH RING (0.29.0; a mythic's only since 0.29.1)
# =============================================================================

func _add_reach_ring() -> void:
	"""The dashed line round the warrior at its mythic's reach, once - hidden
	while what is in hand is not one. Round its origin, which is where a throw
	is measured from; in the warrior's y-sorted body that is above the sprite
	(13), so it draws under it."""
	if _reach_ring != null:
		return
	_reach_ring = RangeRing.new()
	_reach_ring.name = "reachring"
	_reach_ring.colour = REACH_COLOUR
	add_child(_reach_ring)
	move_child(_reach_ring, 0)
	_fit_reach_ring()


func _fit_reach_ring() -> void:
	_show_reach_for(equipped_weapon_attack())


func _show_reach_for(weapon_attack: int) -> void:
	"""The ring for the weapon in hand (an ItemData.WeaponAttack): at its reach,
	or hidden for one with none to show. Not `attack`, which is the attack skill
	(player.gd)."""
	_mythic_reach = mythic_reach(weapon_attack)
	if _reach_ring == null:
		return
	if _mythic_reach > 0.0:
		_reach_ring.set_radius(_mythic_reach)
	_reach_ring.visible = _reach_ring_shown()


func _reach_ring_shown() -> bool:
	"""A mythic in hand, alive, and Range circles on in Options (0.31.0)."""
	return _mythic_reach > 0.0 and not is_dying and bool(Settings.get_value("range_circles"))


func mythic_reach(weapon_attack: int) -> float:
	"""How far a mythic's attack reaches from the warrior's origin, or 0 for
	any other weapon - the sword's own reach is about the warrior's width, and
	the owner wants no line for it. The Double Axe's is the furthest it can be
	thrown plus its blade (SpinningAxe.HIT_RADIUS) where it lands."""
	if weapon_attack == ItemData.WeaponAttack.SPINNING_AXE:
		return SpinningAxe.MAX_THROW + SpinningAxe.HIT_RADIUS
	return 0.0


# =============================================================================
# SLASHWAVE PROJECTILE
# =============================================================================

func _spawn_slashwave() -> void:
	if mana < slashwave_mana_cost:
		return

	mana -= slashwave_mana_cost

	var wave: SlashWave = SLASHWAVE_SCENE.instantiate()
	_parent_to_projectiles_container(wave)

	# Spawn position comes from the aim vector — a small offset in front of the
	# warrior, along the exact aimed direction. See wave_muzzle_offset for why
	# this replaced four fixed Marker2D nodes.
	wave.global_position = global_position + _swing_aim_direction * wave_muzzle_offset

	# The wave is added to the tree ABOVE and positioned on the line before
	# this one. With common/physics_interpolation=true that ordering means its
	# first rendered frame is blended from wherever the node sat on entering
	# the tree to the muzzle — so the wave visibly smears out of the
	# container's origin instead of appearing at the sword. Same discontinuity
	# as teleporter.gd; same one-line fix.
	wave.reset_physics_interpolation()

	wave.damage = int(_calculate_melee_damage() * wave_damage_ratio * (FINISHER_MULT if _finisher else 1.0))
	# THE FINISHER's wave: gold, and bigger - its hitbox too. Before
	# shoot_vector(), which builds the hitbox and dresses the wave.
	if _finisher:
		wave.finisher = true
		wave.hitbox_scale = FINISHER_SCALE
		wave.burst_damage = maxi(1, int(wave.damage * FINISHER_ORB_SHARE))

	# Identifies the warrior for slashwave.gd's magic-XP-on-hit — see that
	# file's class comment for why the wave (not the swing) grants magic XP,
	# while melee keeps granting attack XP as before.
	wave.caster = self
	wave.shoot_vector(_swing_aim_direction)
	# THE FINISHER's fan: gold orbs flying out beside its wave, as fast.
	if _finisher:
		for way in BladeOrb.fan_ways(_swing_aim_direction, FINISHER_FAN_ORBS, FINISHER_FAN_SPREAD_DEGREES, true):
			BladeOrb.fire(wave.get_parent(), wave.global_position + SlashWave.SPRITE_CENTRE, way, wave.speed,
				FINISHER_FAN_REACH, wave.burst_damage, BladeOrb.GOLD)
	Presence.tell_attack("slash", wave.global_position,
		wave.global_position + _swing_aim_direction * RemoteAttacks.AIM_AHEAD, 0.0,
		RemoteAttacks.FLAG_SWORD_FAN | (RemoteAttacks.FLAG_FINISHER if _finisher else 0))


func _parent_to_projectiles_container(wave: Node) -> void:
	_projectiles_parent().add_child(wave)


func _projectiles_parent() -> Node:
	"""Where the warrior's projectiles go: the area's "projectiles" node, or
	the area itself - or, out of the tree (the tests), the warrior's parent."""
	if not is_inside_tree():
		return get_parent()
	var container: Node = get_tree().get_first_node_in_group("projectiles")
	return container if container != null else get_tree().current_scene


# =============================================================================
# DIRECTION HELPERS
# =============================================================================

# The TUNED 4-way choice for a swing: the nearest cardinal, but with a horizontal
# bias and optional hysteresis applied so the fallback feels smooth with only the
# four drawn frames. Used for the hitbox and for the animation fallback; the raw
# 8-way octant is resolved separately and is never touched by this.
#
# The bias is a pre-scale of x before the compare — stretching the aim
# horizontally makes left/right win over a wider cone, which is exactly "a
# slightly-off-horizontal aim should still swing sideways". Facing.from_vec_stable
# then applies the hysteresis against the last swing's facing (margin 1.0 = none).
# Has a side effect on purpose: it records the chosen cardinal for next time, so
# it must run exactly once per swing.
func _resolve_swing_cardinal(dir: Vector2) -> String:
	var biased := Vector2(dir.x * swing_horizontal_bias, dir.y)
	var chosen := Facing.from_vec_stable(biased, _last_swing_cardinal, swing_facing_stickiness)
	_last_swing_cardinal = chosen
	return chosen


# Snaps a direction vector to the nearest of 8 equal 45° wedges (4 cardinals +
# 4 diagonals), for the 8-directional attack animations.
#
# atan2(dir.y, dir.x) gives the angle in radians (-π to π); dividing by PI/4
# (45° in radians) and rounding lands on the nearest of 8 evenly-spaced octant
# indices. The % handling normalizes negative results, since GDScript's % on
# negatives doesn't wrap the way you'd want on its own (e.g. -1 % 8 == -1,
# not 7).
func _octant_from_direction(dir: Vector2) -> String:
	if dir.length_squared() < AIM_EPSILON_SQUARED:
		return "down"
	var angle: float = atan2(dir.y, dir.x)
	var octant: int = int(round(angle / (PI / 4.0)))
	octant = ((octant % 8) + 8) % 8
	return OCTANT_DIRECTIONS[octant]
