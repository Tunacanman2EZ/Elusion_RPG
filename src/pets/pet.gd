# pet.gd — a companion entity. a shrunk, ally-flipped version of an enemy:
# instead of hunting the player, it FOLLOWS the player and attacks the nearest
# ENEMY within aggro range.
#
# supports two attack archetypes so different pets play differently:
#   PROJECTILE — fires projectile_scene at range, traveling toward the target
#   VINE       — spawns projectile_scene AT THE TARGET's position, no travel
#
# design: composition, NOT inheritance from BaseEnemy. every combat value is
# an export so each pet variant tunes individually.
#
# attack animation lock: while _is_attacking is true, _update_follow skips
# walk/idle animation changes so movement doesn't stomp the attack visual.
#
# render order:
# - projectile attacks parent under the "projectiles" group (Y-sorted
#   Projectiles container) so they depth-sort with characters.
# - vine attacks parent under the "groundeffects" group (Y-sorted
#   GroundEffects container) so they root at the target's feet, under bodies.
#
# DEFERRED SPAWN TIMING (IMPORTANT):
# _parent_to_group() deliberately uses add_child.call_deferred() rather than
# add_child() directly, to avoid mutating the tree mid-physics-frame. that
# means the spawned node's _ready() — and therefore any @onready vars on it,
# like a sprite reference — does NOT run until later in the same frame's
# deferred-call flush. calling a method like fire()/shoot_vector() on that
# node SYNCHRONOUSLY right after spawning it will hit those @onready vars
# before they're assigned (still null), crashing with "Invalid access to
# property or key '...' on a base object of type 'Nil'". both _fire_vine()
# and _fire_projectile() defer their trigger call for exactly this reason —
# deferred calls run in the order they were queued, so the deferred add_child
# (which triggers _ready()) always completes before the deferred fire/shoot
# call runs, even though both were queued within the same physics frame.
extends CharacterBody2D
class_name Pet


# =============================================================================
# ATTACK TYPE
# =============================================================================

enum AttackType { PROJECTILE, VINE }


# =============================================================================
# EXPORTED SETTINGS — PER-PET TUNING
# =============================================================================

@export var attack_type: AttackType = AttackType.PROJECTILE
@export var projectile_scene: PackedScene = null
@export var projectile_damage: int = 5
# How far a pet will look for a target, measured from ITSELF.
#
# 280 matches the longest-ranged enemy in the game (electricsprite.gd), and it
# is set here rather than per-scene because no pet scene overrides it — one
# number, one place.
#
# WHY IT HAS TO EXCEED THE ENEMY'S, not merely equal it: this is measured from
# the pet, and a pet trails the player by follow_distance (60). An enemy that
# opens fire from 260 away from the PLAYER is 320 away from a pet sitting
# behind them, so a pet matched at 280 would sit and watch its owner get shot.
# The gap between 280 and the enemies' 200-280 spread is what buys back that
# trailing distance.
@export var aggro_range: float = 280.0
@export var attack_cooldown: float = 2.0
@export var move_speed: float = 100.0
@export var follow_distance: float = 60.0
@export var teleport_distance: float = 600.0
@export var scale_factor: float = 0.5

# Name prefix of the per-direction Marker2D children that say where a
# projectile leaves this pet. The four suffixes are always top, bottom, left
# and right — so "orbspawn" finds orbspawntop, orbspawnbottom, orbspawnleft
# and orbspawnright, which is exactly how every pet scene already names them.
#
# Left EMPTY (the default) a pet keeps the old behaviour: the shot spawns
# MUZZLE_OFFSET pixels from the pet's centre, straight toward the target.
# That was the ONLY behaviour until now, which is why those orbspawn* and
# arrowspawn* markers sat in the scenes entirely unread — nothing in this
# script had ever looked a marker up. Set this on a pet and its markers start
# mattering; leave it blank and nothing about that pet changes.
@export var muzzle_marker_prefix: String = ""

# NEW: which frame of the attack animation actually releases the shot, the
# same idea as bushsniper.gd's ARROW_RELEASE_FRAME. the projectile used to
# spawn BEFORE the animation had played a single frame, so the pet fired and
# then wound up.
#
# -1 means "fire immediately", which is the old behaviour — a pet whose
# release frame hasn't been picked yet keeps working exactly as it did.
# set it to the frame where the art visibly throws/looses/casts.
@export var release_frame: int = -1


# =============================================================================
# STATE
# =============================================================================

# NEW: who this pet belongs to. set by whoever spawns it — see player.gd's
# summon_pet() / _restore_active_pet() / the debug spawners — and set BEFORE
# add_child(), so it's already in place when _ready() resolves the player.
#
# WHY THIS EXISTS AT ALL: _resolve_player() used to take
# get_nodes_in_group("player")[0], i.e. whichever player node happens to sit
# first in the group. With exactly one player that is always the right
# answer. With two it is an arbitrary one — and once this is networked,
# potentially a DIFFERENT one on each client, so your pet could visibly
# follow someone else's character on their screen and yours on yours.
# A pet's owner is a fact, not something to infer from tree order.
var owner_player: Node = null

var player: Node = null
var _attack_ready: bool = true
var _current_target: Node = null
var _is_attacking: bool = false

# NEW: an attack that's mid-animation, waiting for release_frame. the target
# and direction are captured at the START of the swing rather than read again
# at release, so the shot goes where the pet was aiming when it committed.
#
# _pending_target IS EXPECTED TO GO STALE. release_frame deliberately puts
# several frames between committing to an attack and the shot leaving, and an
# enemy can die inside that window — usually to this pet's own previous shot.
# Nothing here holds a reference that keeps it alive, so by release time it can
# be a freed Object. Always read it through _consume_pending_target().
var _awaiting_release: bool = false
var _pending_target: Node = null
var _pending_dir: Vector2 = Vector2.ZERO


# =============================================================================
# NODE REFERENCES
# =============================================================================

@onready var attack_timer: Timer = _make_attack_timer()


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	add_to_group("pets")
	scale = Vector2(scale_factor, scale_factor)
	_resolve_player()

	if has_node("animatedsprite2d"):
		var sprite: AnimatedSprite2D = $animatedsprite2d
		if sprite.sprite_frames != null and sprite.sprite_frames.has_animation("idledown"):
			sprite.play("idledown")
		if not sprite.animation_finished.is_connected(_on_sprite_animation_finished):
			sprite.animation_finished.connect(_on_sprite_animation_finished)
		# NEW: drives the release_frame shot — see _on_sprite_frame_changed().
		if not sprite.frame_changed.is_connected(_on_sprite_frame_changed):
			sprite.frame_changed.connect(_on_sprite_frame_changed)


func _make_attack_timer() -> Timer:
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = attack_cooldown
	add_child(t)
	t.timeout.connect(func(): _attack_ready = true)
	return t


func _physics_process(_delta: float) -> void:
	# is_instance_valid(), NOT == null. A freed node is not null - it is a
	# dangling reference, and touching one throws. _resolve_player() below
	# already knew this and said so in its own comment; this guard, twenty
	# lines above it, did not. The player is freed on death and on every scene
	# change, so a stale reference here reached _update_follow() and touched a
	# freed instance every physics tick.
	if not is_instance_valid(player):
		_resolve_player()
		return

	_update_follow()

	_current_target = _find_nearest_enemy()

	if _current_target != null and _attack_ready:
		_fire_at(_current_target)


# =============================================================================
# PLAYER RESOLUTION
# =============================================================================

func _resolve_player() -> void:
	# CHANGED: prefer the explicit owner. see owner_player's comment for why
	# the group lookup below is not good enough on its own.
	#
	# is_instance_valid() rather than != null: a freed node is NOT null, it's
	# a dangling reference, and touching one throws "Attempt to call function
	# on a previously freed instance". this matters here because the player
	# gets freed on death and on every scene change.
	if is_instance_valid(owner_player):
		player = owner_player
		return

	# fallback for a pet nobody claimed — correct while there is exactly one
	# player, arbitrary the moment there is more than one.
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]


# =============================================================================
# FOLLOW MOVEMENT
# =============================================================================

func _update_follow() -> void:
	var to_player: Vector2 = player.global_position - global_position
	var dist: float = to_player.length()

	if dist > teleport_distance:
		global_position = player.global_position - to_player.normalized() * follow_distance
		# NEW: same discontinuity as teleporter.gd — this is a teleport, not
		# movement, so the renderer must not blend across the gap. Without
		# this the pet visibly streaks the whole way when it catches up.
		# See teleporter.gd's comment for the full explanation.
		reset_physics_interpolation()
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if dist > follow_distance:
		velocity = to_player.normalized() * move_speed
		if not _is_attacking:
			_play_walk(to_player)
	else:
		velocity = Vector2.ZERO
		if not _is_attacking:
			_play_idle()

	move_and_slide()


# =============================================================================
# TARGETING
# =============================================================================

func _find_nearest_enemy() -> Node:
	var nearest: Node = null
	var nearest_dist: float = aggro_range

	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		var d: float = global_position.distance_to(enemy.global_position)
		if d <= nearest_dist:
			nearest = enemy
			nearest_dist = d

	return nearest


# =============================================================================
# ATTACK
# =============================================================================

func _get_scaled_damage() -> int:
	# CHANGED: was pure level-based scaling. now reads the player's actual
	# attack+magic damage multiplier — the same get_damage_multiplier()
	# every class's own damage routes through (see player.gd) — at a flat
	# 50%. a pet contributes real, growing damage as the player invests in
	# attack/magic, but deliberately less than the player's own hits, so a
	# pet stays a meaningful helper rather than a second character.
	# computed live at fire time (not cached at spawn) so damage stays
	# current as the player's stats keep growing, without needing to
	# re-summon the pet. attack_cooldown (already exported, per-pet) is
	# the lever for making a specific pet variant hit harder/faster than a
	# regular enemy without touching this 50% ratio.
	if player == null or not player.has_method("get_damage_multiplier"):
		return projectile_damage
	return int(projectile_damage * player.get_damage_multiplier() * PET_STAT_SHARE)


# Fraction of the player's stat bonus a pet receives. Damage has always used
# this ratio; attack speed now uses the same one, so "a pet is half as good at
# this as you are" is one rule rather than two numbers that can drift apart.
const PET_STAT_SHARE: float = 0.5

# A pet can never attack faster than this, whatever the player's agility.
# attack_timer drives the attack ANIMATION as well as the shot, so a cooldown
# shorter than the animation would restart it every time and the pet would
# twitch on frame 0 forever instead of ever showing a throw.
const MIN_ATTACK_COOLDOWN: float = 0.35


func _get_scaled_cooldown() -> float:
	# Seconds between this pet's attacks, shortened by the player's agility.
	#
	# Read live at fire time, exactly like _get_scaled_damage() above, so a pet
	# keeps up as the player levels without needing to be re-summoned.
	#
	# HALF THE BONUS, NOT HALF THE SPEED. The player's multiplier is reduced to
	# its bonus (mult - 1), halved, then re-applied — so at agility 1 a pet is
	# exactly its authored attack_cooldown rather than being penalised for the
	# player having no agility yet. Dividing the cooldown by a half-multiplier
	# instead would make every pet permanently twice as slow as its own tuning.
	if player == null or not player.has_method("get_attack_speed_multiplier"):
		return attack_cooldown

	var bonus: float = player.get_attack_speed_multiplier() - 1.0
	var effective: float = 1.0 + bonus * PET_STAT_SHARE
	if effective <= 0.0:
		return attack_cooldown

	return maxf(MIN_ATTACK_COOLDOWN, attack_cooldown / effective)


func _fire_at(target: Node) -> void:
	if projectile_scene == null:
		push_warning("Pet: projectile_scene not assigned")
		return

	var dir: Vector2 = (target.global_position - global_position).normalized()

	# CHANGED: the animation now starts FIRST. the shot used to be spawned
	# above this line, before _play_attack() had run a single frame — the pet
	# fired and then wound up.
	_is_attacking = true
	var anim: String = _play_attack(dir)

	_attack_ready = false
	attack_timer.wait_time = _get_scaled_cooldown()
	attack_timer.start()

	# with release_frame set, the shot leaves on the frame the art actually
	# throws it on (see _on_sprite_frame_changed). left at -1, or with no
	# attack animation to hang it on, it fires immediately as before.
	if release_frame < 0 or anim == "":
		_release_shot(target, dir)
	else:
		_pending_target = target
		_pending_dir = dir
		_awaiting_release = true

	# CHANGED: was a hardcoded 0.4s. every attack animation in the game is
	# longer than that — a 9-frame attack at 5 fps runs 1.8s — so the lock
	# dropped at roughly 22% and _update_follow immediately stomped the
	# attack with walk/idle. deriving it from the animation's own length
	# means changing an animation's fps in the editor now moves the lock
	# with it, instead of silently desyncing from it.
	#
	# NOTE this costs nothing in mobility: _update_follow() sets velocity and
	# calls move_and_slide() unconditionally. _is_attacking only gates which
	# ANIMATION plays, never whether the pet moves — so a pet holding its
	# attack animation still follows you at full speed.
	_release_attack_lock_after(_attack_anim_duration(anim))


func _consume_pending_target() -> Node:
	# Reads _pending_target once, downgrading a freed object to null, and
	# clears it so a stale reference can never be read twice.
	#
	# WHY A CALLER-SIDE CHECK, when _release_shot() already calls
	# is_instance_valid() on its argument: GDScript validates a TYPED
	# parameter at the call boundary, before the function body runs. Passing a
	# freed object to `target: Node` raises
	#
	#   Invalid type in function '_release_shot' ... the Object-derived class
	#   of argument 1 (previously freed) is not a subclass of the expected
	#   argument class
	#
	# and the guard inside never gets the chance to execute. A guard in the
	# callee cannot protect the callee's own signature. null, by contrast, is
	# a perfectly legal value for a typed Node parameter — so converting here
	# is what lets the existing check downstream do its job.
	var target: Node = _pending_target if is_instance_valid(_pending_target) else null
	_pending_target = null
	return target


func _release_shot(target: Node, dir: Vector2) -> void:
	# the actual spawn, shared by the fire-immediately and release_frame
	# paths so there's one definition of what an attack does.
	#
	# `target` may legitimately be null here — see _consume_pending_target().
	# That is not a reason to abandon the shot: a PROJECTILE flies along the
	# `dir` captured when the pet committed, so it still fires where it was
	# aiming even though whatever it aimed at is gone. Only a VINE, which
	# spawns AT the target, has nothing left to act on.
	match attack_type:
		AttackType.PROJECTILE:
			_fire_projectile(dir)
		AttackType.VINE:
			# vines spawn AT the target, so a target that died during the
			# wind-up has nowhere to put one.
			if is_instance_valid(target):
				_fire_vine(target, dir)


func _attack_anim_duration(anim: String) -> float:
	# how long the attack animation actually runs, in seconds.
	#
	# falls back to the old fixed window when there's nothing to measure: no
	# animation, or a LOOPING one — a loop never ends, so it can't define a
	# lock duration. that looping case is what the previous comment here was
	# worried about, and it's still handled; it just no longer punishes the
	# non-looping animations that every pet actually uses.
	const FALLBACK := 0.4
	if anim == "" or not has_node("animatedsprite2d"):
		return FALLBACK
	var sf: SpriteFrames = $animatedsprite2d.sprite_frames
	if sf == null or not sf.has_animation(anim):
		return FALLBACK
	if sf.get_animation_loop(anim):
		return FALLBACK
	var fps: float = sf.get_animation_speed(anim)
	if fps <= 0.0:
		return FALLBACK
	return float(sf.get_frame_count(anim)) / fps


func _release_attack_lock_after(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	_is_attacking = false


const MUZZLE_OFFSET := 24.0


func _muzzle_position(dir: Vector2) -> Vector2:
	# Where a projectile is born. A directional Marker2D wins when the pet
	# names one (muzzle_marker_prefix); otherwise fall back to a fixed offset
	# from the pet's centre toward the target, which is what every pet did
	# before markers were read at all.
	#
	# The fallback isn't a failure case — it's correct for a round pet whose
	# shot leaves from the middle. Markers earn their keep when the art is
	# off-centre, like a mouth on one side of the sprite, where a shot from
	# the centre reads as coming out of nowhere.
	if muzzle_marker_prefix != "":
		var marker: Node = _find_muzzle_marker(dir)
		if marker is Node2D:
			return (marker as Node2D).global_position

	return global_position + dir * MUZZLE_OFFSET


func _find_muzzle_marker(dir: Vector2) -> Node:
	# MARKERS ARE top/bottom/left/right. One spelling, every scene, no
	# fallbacks — every pet scene in the project already names them this way
	# (orbspawntop, arrowspawnbottom, ...), so there is nothing to be lenient
	# about and a lenient lookup would only hide a typo.
	#
	# NOT to be confused with the ANIMATION suffixes, which are up/down/left/
	# right (walkup, idledown). Those are a separate naming scheme baked into
	# every SpriteFrames in the game and are not changing — see
	# _play_directional(). Same four directions, two different vocabularies,
	# because one names art and the other names nodes.
	var suffix: String
	if abs(dir.x) > abs(dir.y):
		suffix = "right" if dir.x > 0 else "left"
	else:
		suffix = "bottom" if dir.y > 0 else "top"

	return get_node_or_null(muzzle_marker_prefix + suffix)


func _fire_projectile(dir: Vector2) -> void:
	# flying projectile → parent to the "projectiles" group (Y-sorted), spawn
	# at this pet's muzzle for the direction it's facing, then aim.
	var projectile: Node = projectile_scene.instantiate()
	_parent_to_group(projectile, "projectiles")

	projectile.set_deferred("global_position", _muzzle_position(dir))

	if "damage" in projectile:
		projectile.damage = _get_scaled_damage()

	# NEW: deferred for the same reason as _fire_vine's fire() call below —
	# see the DEFERRED SPAWN TIMING note at the top of this file. this
	# wasn't crashing visibly (unlike petvine.gd's fire()), but it's the
	# identical latent timing bug: if any projectile's shoot_vector() ever
	# touches an @onready sprite reference, it'll hit the same null crash
	# the moment that code path changes. deferring here costs nothing and
	# closes the gap for all projectile types at once, not just the ones
	# lucky enough not to have tripped it yet.
	if projectile.has_method("shoot_vector"):
		projectile.call_deferred("shoot_vector", dir)

	# LAST IN THE QUEUE ON PURPOSE. Deferred calls flush in the order they were
	# queued, so by the time this runs the projectile is in the tree, at its
	# muzzle position, and pointed the right way — and rotation is part of the
	# transform being interpolated, so resetting before shoot_vector() would
	# leave the projectile spinning into its heading over one frame.
	#
	# Without it the shot is drawn once at the world origin and streaks to the
	# muzzle, through whatever walls are in between. See
	# BaseEnemy.spawn_projectile_node() for the full explanation.
	projectile.call_deferred("reset_physics_interpolation")


func _fire_vine(target: Node, dir: Vector2) -> void:
	# ground-rooted vine → parent to the "groundeffects" group (Y-sorted),
	# spawn AT THE TARGET's position so it roots at their feet.
	var vine: Node = projectile_scene.instantiate()
	_parent_to_group(vine, "groundeffects")
	vine.set_deferred("global_position", target.global_position)
	if "damage" in vine:
		vine.damage = _get_scaled_damage()

	# NEW: fire() must be deferred — _parent_to_group's add_child is itself
	# deferred, so vine._ready() (and its @onready sprite assignment) hasn't
	# run yet at this point in the same physics frame. calling fire()
	# synchronously here is exactly what produced "Invalid access to
	# property or key 'sprite_frames' on a base object of type 'Nil'" —
	# petvine.gd's fire() touches sprite.sprite_frames immediately, and
	# sprite was still unassigned. deferring queues fire() to run right
	# after the deferred add_child completes _ready(), in the same
	# end-of-frame flush, in queue order — so sprite is guaranteed set.
	if vine.has_method("fire"):
		vine.call_deferred("fire", _dir_to_cardinal(dir))

	# Queued last, after fire(), for the same reason as _fire_projectile above.
	vine.call_deferred("reset_physics_interpolation")


func _parent_to_group(node: Node, group_name: String) -> void:
	# parent under the named group container (a Y-sorted node inside
	# YSortWorld) if one exists, matching how enemy attacks parent so
	# depth-sorting stays consistent. falls back to the scene root.
	# uses call_deferred so we don't mutate the tree mid-physics-frame.
	var container: Node = get_tree().get_first_node_in_group(group_name)
	if container == null:
		container = get_tree().current_scene
	container.add_child.call_deferred(node)


func _dir_to_cardinal(dir: Vector2) -> String:
	if abs(dir.x) > abs(dir.y):
		return "right" if dir.x > 0 else "left"
	return "down" if dir.y > 0 else "up"


# =============================================================================
# ANIMATION HELPERS
# =============================================================================

func _play_walk(dir: Vector2) -> void:
	_play_directional("walk", dir)


func _play_attack(dir: Vector2) -> String:
	# CHANGED: returns the animation it played so the caller can measure its
	# length. force_restart is true because an attack must replay from frame
	# 0 every time — see _play_directional().
	return _play_directional("attack", dir, true)


func _play_idle() -> void:
	if has_node("animatedsprite2d"):
		var sprite: AnimatedSprite2D = $animatedsprite2d
		if sprite.sprite_frames != null and sprite.sprite_frames.has_animation("idledown"):
			if sprite.animation != "idledown":
				sprite.play("idledown")


func _play_directional(prefix: String, dir: Vector2, force_restart: bool = false) -> String:
	# CHANGED: now returns the animation name it settled on ("" if there
	# wasn't one), so _fire_at() can measure the attack's real duration.
	if not has_node("animatedsprite2d"):
		return ""
	var sprite: AnimatedSprite2D = $animatedsprite2d
	if sprite.sprite_frames == null:
		return ""
	var suffix: String
	if abs(dir.x) > abs(dir.y):
		suffix = "right" if dir.x > 0 else "left"
	else:
		suffix = "down" if dir.y > 0 else "up"
	var anim := prefix + suffix
	if not sprite.sprite_frames.has_animation(anim):
		return ""

	# NEW: force_restart exists for attacks. the `animation != anim` check
	# alone meant a SECOND attack in the same direction never called play()
	# again — the non-looping animation stayed parked on its final frame and
	# that shot had no visible wind-up at all. walk/idle still use the cheap
	# check, since restarting a loop every frame would freeze it on frame 0.
	if force_restart:
		sprite.play(anim)
		sprite.set_frame_and_progress(0, 0.0)
	elif sprite.animation != anim:
		sprite.play(anim)

	return anim


# =============================================================================
# ATTACK ANIMATION LOCK
# =============================================================================

func _on_sprite_frame_changed() -> void:
	# NEW: releases the shot on release_frame, mirroring bushsniper.gd's
	# _on_frame_changed(). uses >= rather than == so a frame skipped by a
	# dropped physics frame doesn't swallow the attack entirely.
	if not _awaiting_release:
		return
	if not has_node("animatedsprite2d"):
		return
	var sprite: AnimatedSprite2D = $animatedsprite2d
	if not sprite.animation.begins_with("attack"):
		return
	if sprite.frame < release_frame:
		return

	_awaiting_release = false
	_release_shot(_consume_pending_target(), _pending_dir)


func _on_sprite_animation_finished() -> void:
	if not has_node("animatedsprite2d"):
		return
	var sprite: AnimatedSprite2D = $animatedsprite2d
	if not sprite.animation.begins_with("attack"):
		return

	# NEW: failsafe. if release_frame was set past the last frame of the
	# animation, the frame callback never fires and the shot would be
	# silently swallowed — the pet would play a full attack and do nothing.
	# fire it here rather than lose it.
	if _awaiting_release:
		_awaiting_release = false
		_release_shot(_consume_pending_target(), _pending_dir)

	_is_attacking = false
