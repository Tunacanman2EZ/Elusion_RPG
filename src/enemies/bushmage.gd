# bushmage enemy — caster that summons a stationary vine attack in front of
# itself, stretching toward the player. Presses in to its wedge on the ring
# around the player (Formation.RING_RADIUS, 36px) and casts from there. It never
# retreats.
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
# WHY THIS CLASS STILL REPLACES BaseEnemy._physics_process. It uses the same
# formation slots every other enemy does, so the reason is no longer positioning
# - it is that BaseEnemy's state machine can flee and hold fire, and this one
# must do neither. A mage that backs off is the exact bug this class was rebuilt
# to remove, and a mage that stops to check attack_range before casting would
# hold position outside a reach it is already well inside.
#
# The cost of overriding is real and has bitten before: BaseEnemy grows a rule,
# this class does not get it. The leash below is the scar from the last time.
# Anything added to BaseEnemy._physics_process needs a decision about this file.
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

# WHERE THE MAGE CASTS FROM: its wedge on the ring, at Formation.RING_RADIUS.
#
# desired_distance and distance_tolerance USED TO LIVE HERE and are gone. They
# held the mage at 24px from the player, and 24px is a number with a consequence
# nobody had worked out: only SEVEN bodies of radius 10 fit shoulder to shoulder
# on a circle that small. Mage eight onward had nowhere to stand, so they pressed
# against the ones already there and circled looking for a gap that could not
# exist. The ring radius is 36, where exactly eleven fit - so the eighth, ninth,
# tenth and eleventh mages now have a place to be, and the twelfth is the first
# one left outside.
#
# The vine damages a 150x149 box centred where it spawns, reaching about 75px in
# every direction, so casting from 36px lands comfortably. Standing on the ring
# is not standing back.

# How close to the PLAYER a mage has to be before it will cast.
#
# Set past ring 2 (56px) on purpose, so the mages that could not fit on the
# inner ring still fight instead of standing behind the front rank watching.
# Still well inside the vine's ~75px reach, so every cast this permits is a cast
# that can actually connect.
const CAST_RANGE := Formation.RING_RADIUS + 24.0

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
	# attack_range in particular could not move: it is derived from the ring
	# geometry, so it is not a number you can write down in a data file.
	attack_cooldown = 1.2
	# Kept EQUAL to CAST_RANGE rather than near it. This class decides its own
	# casts from CAST_RANGE, but inherited code still reads attack_range, and two
	# numbers that mean "close enough to fight" will eventually disagree.
	attack_range    = CAST_RANGE

	# COMMIT TO THE CHASE. The default leash is 400, so the mage gave up and
	# walked home the moment the player got that far - which is exactly why the
	# mages in the field sat at the edge casting into empty space. A rush-in
	# caster pursues across the room instead of guarding a spot.
	leash_range = 1500.0

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

	# while attacking, freeze in place and let the animation play out - except
	# for easing out from under the player, which does not interrupt the cast.
	# See BaseEnemy._standoff_velocity().
	if is_attacking:
		velocity = _standoff_velocity()
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

	# TAKE A PLACE ON THE RING AND CAST FROM IT.
	#
	# THIS IS A RETURN TO THE FORMATION, AND THE HISTORY MATTERS because the last
	# time mages used it they cast from across the room. Two causes, both dealt
	# with rather than worked around:
	#
	#   * They BACKED OFF when the player closed. That kiting branch is gone and
	#     is not coming back - a mage never retreats now.
	#   * Their slot sat on a square grid whose ring was 40 to 60px out, tuned by
	#     a stride constant that moved the radius and the spacing together. Now
	#     the ring is a fixed 36px, which is inside the vine's reach with room to
	#     spare, and the count is derived from it instead of fighting it.
	#
	# What the formation buys that charging the player does not: eleven mages get
	# eleven DIFFERENT places to stand, all of them in casting range, spread the
	# whole way around. Charging one point means they all want the same pixel and
	# the ones behind spend the fight circling for a gap.
	var slot_target: Vector2 = _get_slot_target_position()

	# CAST WHEN THE SPELL CAN REACH, not when standing exactly on the wedge.
	#
	# Slot arrival is a 6px window around a point that moves with the player, and
	# movement here is cardinal-only - so a mage chasing a player who is actually
	# running would keep just missing that window and never fire a single vine.
	# Whether a vine lands is a question about range to the PLAYER, so ask that
	# instead, and keep walking to the wedge the rest of the time. The result is
	# a mage that closes and casts on the way in rather than casting only once
	# parked, which is the aggression the formation was supposed to add to, not
	# replace.
	if attack_ready and dist <= CAST_RANGE and _has_line_of_sight(player.global_position):
		velocity = _standoff_velocity()
		move_and_slide()
		_trigger_attack()
		return

	if global_position.distance_to(slot_target) > Formation.ARRIVAL_THRESHOLD:
		_press_to(slot_target)
	else:
		_hold_and_attack()


# =============================================================================
# MOVEMENT MODES
# =============================================================================

func _press_to(slot_target: Vector2) -> void:
	# PUSH IN AND TAKE THE SPOT. _steered_direction_to takes a clear line when
	# there is one, routes around walls when there is not, and goes AROUND other
	# enemies in the way rather than into them - which is what lets a mage work
	# its way through the crowd already standing on the ring instead of jamming
	# behind them.
	#
	# MOVE by the steered heading, FACE toward the player. The heading turns
	# corners while going around people and would spin the sprite with it; what
	# the player should see is a mage bearing down on them the whole time.
	var pos_before: Vector2 = global_position
	var step: String = _steered_direction_to(slot_target)
	velocity = _vec_from_dir(step) * get_move_speed()
	move_and_slide()
	_walk_facing = Facing.from_vec_stable(player.global_position - global_position, _walk_facing)
	play_walk_animation(_walk_facing)
	_record_nav_movement_result(pos_before)


func _hold_and_attack() -> void:
	# in the sweet spot — stop and cast when ready, otherwise idle.
	#
	# NOT QUITE STOPPED: the standoff still runs, so a mage the player walks
	# onto slides out from underneath instead of being stood on. It is zero
	# whenever there is no overlap, which is nearly always, so this is the same
	# "hold still and cast" it has always been.
	velocity = _standoff_velocity()
	move_and_slide()
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
	# FASTER THAN THE PLAYER (base 90) on purpose. A caster that means to rush in
	# and cast at close range cannot be slower than the thing it is chasing, or
	# it never closes the gap - it just trails the player to its leash limit and
	# gives up. This is the other half of why the mages hung back.
	return 115.0


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
