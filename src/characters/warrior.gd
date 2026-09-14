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
#     2. which hitboxXXXX / wavespawnXXXX node is treated as "active" for
#        this swing — STILL 4-way (see note below), independent of the
#        animation's granularity.
# - the SLASHWAVE now travels at a true 360 angle toward the cursor, via
#   slashwave.gd's shoot_vector() (its animation still snaps to nearest
#   cardinal internally — that part is unchanged, just the travel line).
# - MELEE HIT DETECTION is still cardinal-snapped (4-way): hitboxleft/right/
#   up/down are 4 fixed pre-placed Area2D nodes. the animation upgraded to
#   8-way independently of this — if/when 4 more hitbox + wavespawn nodes
#   get added for the diagonals, _get_active_hitbox() and _spawn_slashwave()
#   can switch from _cardinal_from_direction() to _octant_from_direction()
#   to match. not done here — pending a decision on whether that scene work
#   is worth it, since a single rotating hitbox would be MORE precise than
#   the 8-pose art can visually justify anyway.
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

# This class's stat curve. See ClassData — hp_base and friends used to be
# literals in _set_stat_curve() below, which meant the server knew your level
# and your class and still could not work out your maximum health.
const CLASS_DATA := preload("res://data/classes/warrior.tres")


# =============================================================================
# CONSTANTS
# =============================================================================

# preloaded slash wave projectile scene
const SLASHWAVE_SCENE := preload("res://scene/projectiles/slashwave.tscn")

# cardinal directions array — used by detection helpers to avoid 4x duplication
const CARDINAL_DIRECTIONS := ["left", "right", "up", "down"]

# NEW: 8 directions in angle order starting at 0° (right), going clockwise
# in screen space (Y+ is down). index = round(angle / 45°), wrapped to 0-7.
# used only for animation selection right now — see _octant_from_direction().
const OCTANT_DIRECTIONS := [
	"right", "downright", "down", "downleft",
	"left", "upleft", "up", "upright"
]


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

# NEW: how far in front of the warrior the slashwave spawns, along the exact
# aim direction — replaces picking one of the 4 fixed wavespawnXXXX markers.
# same muzzle-offset technique pet.gd already uses for its own projectile
# spawning. this is what actually makes the slashwave full 360, not just its
# travel direction (which shoot_vector() already handled) — the SPAWN POINT
# now scales continuously with aim angle too, instead of always launching
# from one of 4 fixed positions and flying off at an angle from there.
#
# CHANGED: reduced from 24 to 10 — confirmed the wave was spawning several
# tiles away from the character, visually disconnected from the swing
# itself. if it's STILL spawning far away after this, check the warrior
# scene's Inspector for an explicit override on this exact field — as an
# @export, a value set there takes precedence over whatever this script
# declares as default.
@export var wave_muzzle_offset: float = 10.0

# NEW: how fast the attack animation itself plays, independent of walk/sprint
# speed. Doesn't change WHICH frames trigger damage/wave (contact_frame_start/
# end and wave_spawn_frame are still frame-index based, not time-based) — it
# just compresses the whole swing into less real time. Tune to taste; this is
# a practical mitigation for the cardinal-snap mismatch (the pose can be up
# to 45° off from your actual cursor aim while moving) — a faster swing means
# that mismatched pose is visible for less time, even though it doesn't fix
# the underlying snap.
#
# CHANGED: 1.5 -> 2.2 for a noticeably snappier swing. attack_lock_duration
# (the recovery window before you can attack again) scales down
# automatically with this too, since it's computed from the real animation
# duration — you don't need to separately tune that to feel the difference.
@export var attack_animation_speed: float = 3.5

# NEW: safety-net backstop, separate from animation_finished. if an attack
# animation's Loop property is ever accidentally left ON in the SpriteFrames
# editor, animation_finished NEVER fires for it (looping animations don't
# "finish"), which would leave is_attacking stuck true FOREVER — permanently
# freezing the swing on screen and blocking all future attacks, since
# attack_action() guards on `if is_attacking: return`. pet.gd already hit
# this exact trap and worked around it the same way (see its
# _release_attack_lock_after).
#
# CHANGED: this is now a MINIMUM floor rather than the actual timer value —
# attack_action() computes the real animation duration from whichever clip
# is actually playing and uses whichever is larger. only matters as a
# fallback if that computation fails for some reason (missing animation,
# zero FPS). you shouldn't need to tune this by hand anymore.
@export var attack_lock_duration: float = 1.0


# =============================================================================
# STATE
# =============================================================================

var _hit_this_swing: Array[Node] = []
var _wave_spawned_this_swing: bool = false

# NEW: increments every time a new swing starts. the safety-net timer
# captures whatever ID was current when IT was scheduled — if a newer swing
# has started by the time that timer actually fires, its captured ID won't
# match _swing_id anymore, and it knows it's stale and does nothing instead
# of reaching into whatever swing happens to be running now. fixes rapid
# double/triple-clicking cancelling a LATER swing via a leftover timer from
# an EARLIER one that already finished normally.
var _swing_id: int = 0

# NEW: the cursor-aim direction captured at the moment this swing started.
# used instead of last_direction to pick the animation AND the active
# hitbox/wavespawn for the whole swing, so a moving cursor mid-swing
# doesn't change which hitbox is "live" partway through.
var _swing_aim_direction: Vector2 = Vector2.DOWN

# right-click attack now lives in Player (see its ATTACK INPUT section).
# the private tracker that used to sit here is gone, along with the reasoning
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
	_apply_class_data(CLASS_DATA)


# =============================================================================
# SKILL PROFICIENCY  (NEW)
# =============================================================================

func _set_skill_proficiency() -> void:
	# warrior's specialty: attack climbs 50% faster than any other class
	# landing the same hits. every class still gains SOME attack XP from
	# any hit (see player.gd's gain_attack_xp()) — this is what keeps
	# warrior true to its melee identity despite that being universal now.
	# starting value, tune to taste.
	skill_proficiency["attack"] = 1.5


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
	# parent handles movement (WASD), attack dispatch from BOTH spacebar and
	# right-click, animation switching, universal regen, and universal sprint.
	# warrior adds nothing to the input path any more.
	super._physics_process(delta)


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
	# CHANGED: was base_melee_damage + int((attack - 1) / 2) — attack-only,
	# linear, and specific to warrior's own formula. now routes through
	# player.gd's get_damage_multiplier(), same shared function every
	# class's damage uses — folds in magic too, and keeps warrior
	# consistent with how tank/mage/healer's damage now works underneath.
	return int(base_melee_damage * get_damage_multiplier())


# =============================================================================
# ATTACK ACTION
# =============================================================================

func attack_action() -> void:
	if is_attacking:
		return

	_set_active()
	is_attacking = true
	_swing_id += 1
	var this_swing_id: int = _swing_id

	_hit_this_swing.clear()
	_wave_spawned_this_swing = false

	# NEW: aim toward the cursor instead of last WASD direction. fall back
	# to last_direction if the cursor is sitting exactly on the player
	# (zero-length vector, e.g. controller/edge case) so we never animate
	# toward a garbage direction.
	var to_cursor: Vector2 = get_global_mouse_position() - global_position
	_swing_aim_direction = to_cursor.normalized() if to_cursor.length() > 0.001 else last_direction

	# NEW: sync last_direction to the aim. without this, get_idle_animation()
	# (called by player.gd once the swing animation finishes) reads
	# last_direction — which is ONLY ever updated by actual WASD movement,
	# never by this cursor-aim attack. that meant the swing itself would
	# correctly face wherever you aimed, then immediately snap back to
	# idle facing whatever direction you last WALKED the moment it
	# finished — e.g. aiming right while your last move was leftward would
	# show a rightward swing that instantly reverted to facing left.
	last_direction = _swing_aim_direction

	# NEW: 8-directional animation instead of player.gd's 4-way
	# get_attack_animation(). falls back to the nearest cardinal if the
	# diagonal clip isn't in the SpriteFrames yet — this lets code/testing
	# proceed before all 8 attack animations exist.
	#
	# CHANGED: this fallback used to push_warning() every time it fired.
	# Since the four diagonals genuinely aren't drawn yet, that meant a
	# warning on essentially every swing — most mouse aims aren't perfectly
	# cardinal — burying real warnings under known, expected noise. The
	# missing clips are documented in the class comment above instead.
	# REMOVE the fallback entirely once the artist delivers all 4 diagonals.
	var anim: String = "attack" + _octant_from_direction(_swing_aim_direction)
	if sprite != null:
		if not sprite.sprite_frames.has_animation(anim):
			anim = "attack" + _cardinal_from_direction(_swing_aim_direction)
		if sprite.sprite_frames.has_animation(anim):
			sprite.play(anim)
			sprite.frame = 0
			sprite.speed_scale = attack_animation_speed

	# CHANGED: attack_lock_duration was a static guessed value — if the
	# REAL animation (which varies by direction/frame count, especially
	# now with 8-way animations coming from different sources) actually
	# takes longer than that guess, this safety-net timer would fire
	# BEFORE the animation naturally finished, forcibly interrupting the
	# swing mid-play and snapping to idle early. this was a real
	# cancellation bug, not just a facing mismatch. now: compute the real
	# duration directly from whichever clip is actually playing (frame
	# count ÷ FPS ÷ speed scale), and use whichever is LARGER between that
	# and attack_lock_duration — so the timer is always comfortably longer
	# than the real swing and can only ever fire as a true backstop (Loop
	# accidentally left on), never during normal correct playback.
	var lock_duration: float = attack_lock_duration
	if sprite != null and sprite.sprite_frames != null and sprite.sprite_frames.has_animation(anim):
		var frame_count: int = sprite.sprite_frames.get_frame_count(anim)
		var fps: float = sprite.sprite_frames.get_animation_speed(anim)
		if fps > 0.0 and attack_animation_speed > 0.0:
			var real_duration: float = (float(frame_count) / fps) / attack_animation_speed
			lock_duration = max(attack_lock_duration, real_duration + 0.2)

	_release_attack_lock_after(lock_duration, this_swing_id)


func _release_attack_lock_after(seconds: float, swing_id: int) -> void:
	# see attack_lock_duration's comment above for why this exists, and
	# _swing_id's comment for why the ID check below is necessary.
	await get_tree().create_timer(seconds).timeout

	# stale timer from an OLDER swing that already finished normally — a
	# newer swing has started since this one was scheduled. do nothing;
	# acting here would cancel whatever swing is ACTUALLY in progress now.
	if swing_id != _swing_id:
		return

	# NEW: if the player died mid-swing, this timer is STILL scheduled
	# from before death — the death sequence never resets is_attacking
	# itself, only is_dying. without this check, this timer would fire
	# during the death animation and forcibly overwrite it with an idle
	# pose via sprite.play(get_idle_animation()) below, before the death
	# animation ever gets a chance to finish and fire animation_finished.
	# that's exactly what silently skipped the game-over transition: the
	# death animation plays for a moment, then gets stomped by this
	# leftover timer, never actually completing.
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

	mana -= slashwave_mana_cost

	var wave: SlashWave = SLASHWAVE_SCENE.instantiate()
	_parent_to_projectiles_container(wave)

	# CHANGED: spawn position is now computed directly from the aim vector
	# (a small offset in front of the warrior, along the exact aimed
	# direction) instead of picking one of 4 fixed wavespawnXXXX Marker2D
	# nodes. this is what makes the slashwave genuinely full 360 — travel
	# direction was already true 360 via shoot_vector() below, but the
	# LAUNCH POINT was still snapping to one of 4 fixed spots and flying
	# off at an angle from there, which could look slightly offset from
	# the true aim on a diagonal swing. same muzzle-offset technique
	# pet.gd already uses for its own projectile spawning.
	wave.global_position = global_position + _swing_aim_direction * wave_muzzle_offset

	# NEW: the wave is added to the tree ABOVE and positioned here, on the
	# line before this one. With common/physics_interpolation=true that
	# ordering means its first rendered frame is blended from wherever the
	# node sat on entering the tree to the muzzle — so the wave visibly
	# smears out of the container's origin instead of appearing at the
	# sword. Same discontinuity as teleporter.gd; same one-line fix.
	wave.reset_physics_interpolation()

	wave.damage = int(_calculate_melee_damage() * wave_damage_ratio)
	# NEW: identifies the warrior for slashwave.gd's magic-XP-on-hit — see
	# that file's class comment for why the wave (not the swing) grants
	# magic XP, while melee keeps granting attack XP as before.
	wave.caster = self
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
# (cursor-based) instead of last_direction (WASD-based). STILL USED for
# hitbox/wavespawn selection (4-way) and as the fallback if a diagonal
# animation is missing — see _octant_from_direction() below for the 8-way
# version now used for animation selection.
func _cardinal_from_direction(dir: Vector2) -> String:
	if abs(dir.x) > abs(dir.y):
		return "right" if dir.x > 0 else "left"
	else:
		return "down" if dir.y > 0 else "up"


# NEW: snaps a direction vector to the nearest of 8 equal 45° wedges
# (4 cardinals + 4 diagonals), for the new 8-directional attack animations.
# atan2(dir.y, dir.x) gives the angle in radians (-π to π); dividing by
# PI/4 (45° in radians) and rounding lands on the nearest of 8 evenly-spaced
# octant indices. the % handling normalizes negative results, since
# GDScript's % on negatives doesn't wrap the way you'd want on its own
# (e.g. -1 % 8 == -1, not 7).
func _octant_from_direction(dir: Vector2) -> String:
	if dir.length() < 0.001:
		return "down"
	var angle: float = atan2(dir.y, dir.x)
	var octant: int = int(round(angle / (PI / 4.0)))
	octant = ((octant % 8) + 8) % 8
	return OCTANT_DIRECTIONS[octant]


# =============================================================================
# LEVEL-UP SKILL BONUS  (REMOVED)
# =============================================================================
# CHANGED: used to grant a flat +1 attack / +1 defense on every character
# level-up, regardless of how the level was earned. now that
# skill_proficiency exists (see _set_skill_proficiency() above), that job
# is handled more precisely — attack actually climbs faster for warrior
# specifically because warrior is the one landing melee hits, not just
# because the character leveled up from ANY combat. no override needed
# here anymore; falls back to player.gd's no-op base.
