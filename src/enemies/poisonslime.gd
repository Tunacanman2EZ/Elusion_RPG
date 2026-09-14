# poisonslime.gd — the poison slime, in one script for one scene.
#
# THE WHOLE LIFECYCLE, in order:
#
#   1. A LARGE slime sits in the world firing acid balls at range. It fires
#      on a specific animation frame (like fireprojectile, not turret-style),
#      so the ball leaves the sprite when the art actually spits it.
#
#   2. The player comes within duplicate_range and the large slime
#      DUPLICATES ONCE. There are now two larges, and NEITHER may duplicate
#      again — the copy is born with the flag already spent.
#
#   3. Each large, independently, drops to split_hp_ratio of its max HP,
#      HITFLASHES, and CONVERTS into small_count small slimes. Two larges
#      therefore become eight smalls.
#
#   4. Small slimes transform into a bow and fire arrows. They have real
#      deaths (a 5-frame dissolve) and roll real loot.
#
# THE LARGE SLIME NEVER DIES. It has no death animation on the sheet —
# only a hitflash — and that is the design, not an omission: it converts
# instead of dying. _die() below is overridden to route a large into the
# split, so even a single hit big enough to take it from 60% to zero turns
# into a split rather than a corpse.
#
# ONE ENTITY, TWO FORMS: `is_small` is the only thing that separates them.
# It picks the animation set ("smallwalkleft" vs "walkleft"), the projectile
# (arrow vs acid ball), the stat block, and whether the duplicate/split
# paths are available at all.
#
# THE RECURSION GUARD MATTERS MORE THAN ANYTHING ELSE HERE. A small slime
# that could duplicate or split would produce slimes without limit and hang
# the game in seconds. Both paths are gated on `is_small` FIRST, before any
# other check, and the spawn helper marks every child as having already
# duplicated. Do not remove either guard to "simplify" this.
extends BaseEnemy
class_name PoisonSlime

# TWO PROFILES, ONE SCENE. This is the clearest case for making rewards data:
# poisonslime.tscn is a 35 hp mob that drops loot and carries both slime pets,
# AND a 220 hp one that drops nothing at all because it never dies — _die()
# routes it into _begin_split() and it is consumed. The server has to be able to
# tell those apart, and a name is the only way it ever will.
const SMALL_DATA := preload("res://data/enemies/poisonslimesmall.tres")
const LARGE_DATA := preload("res://data/enemies/poisonslimelarge.tres")


# =============================================================================
# CONSTANTS
# =============================================================================

# loaded at runtime rather than preload()ed: this scene's script cannot
# preload the scene it is attached to without Godot reporting a cyclic
# dependency. load() caches after the first call, so the cost is one-time.
const SELF_SCENE_PATH := "res://scene/enemy/poisonslime.tscn"

const POISONBALL_SCENE := preload("res://scene/projectiles/poisonball.tscn")

# the small slime's own green arrow, from slime2.png. NOT bushsniper's
# arrow.tscn — that one is brown and belongs to a different enemy. Both run
# the same arrow.gd; only the sprite and hitbox differ.
const ARROW_SCENE := preload("res://scene/projectiles/poisonarrow.tscn")

# directional spawn markers, named the same way the animations are: the
# large form has no prefix, the small form takes a "small" one.
#
#   projectileleft        projectileright        projectiletop        projectilebottom
#   smallprojectileleft   smallprojectileright   smallprojectiletop   smallprojectilebottom
#
# Two sets because the two forms fire from genuinely different places — the
# acid ball leaves a large blob's body, the arrow leaves a bow the small
# slime is holding at a different height. Sharing one set would spawn the
# arrow somewhere inside the slime.
#
# _projectile_origin() degrades in steps rather than failing: it looks for
# this form's marker, falls back to the large one, and finally to the
# slime's own centre. So the slime works with none of them placed and gets
# more accurate as you add them — no need to do all eight at once.
const MARKER_NAMES := {
	"left":  "projectileleft",
	"right": "projectileright",
	"up":    "projectiletop",
	"down":  "projectilebottom",
}


# =============================================================================
# EXPORTED SETTINGS — FORM
# =============================================================================

# false = the large slime, true = one of the smalls it becomes. Placed
# instances in a level should always be LARGE; smalls are only ever created
# by _split_into_smalls() below.
@export var is_small: bool = false


# =============================================================================
# EXPORTED SETTINGS — STAT BLOCKS
# =============================================================================
# Applied in _ready() BEFORE super._ready(), because BaseEnemy._ready() does
# `hp = max_hp` and would otherwise start every slime on the wrong pool.

# REMOVED: large_max_hp / small_max_hp. Both were read only by _ready(), and
# both values now live in poisonslimelarge.tres and poisonslimesmall.tres. A
# leftover export here would look authoritative in the Inspector and be read by
# nothing, which is a worse state than not having it.
@export var large_attack_cooldown: float = 2.2
@export var large_attack_range: float = 240.0
@export var large_move_speed: float = 45.0


@export var small_attack_cooldown: float = 2.6
@export var small_attack_range: float = 220.0
@export var small_move_speed: float = 70.0

# The healthbar in the scene is authored for the LARGE slime — roughly 36px
# wide, sitting 37px above the origin. A small slime is about half that size,
# so on a small the same bar is wider than the sprite and floats well clear of
# it. With eight smalls on screen the bars stop reading as "enemy health" and
# start reading as free-floating UI, which is exactly how it looked in play.
#
# These only apply when is_small is true; the large keeps the scene values.
@export var small_healthbar_scale: float = 0.55
@export var small_healthbar_offset_y: float = -22.0


# =============================================================================
# EXPORTED SETTINGS — DUPLICATE
# =============================================================================

# how close the player must get before the large slime splits off its twin.
# Deliberately larger than attack_range so the duplication happens as you
# approach, not after you're already trading shots.
@export var duplicate_range: float = 300.0

# how far apart the twin appears. Large enough that the two don't spawn
# inside one another and shove each other around.
@export var duplicate_offset: float = 48.0


# =============================================================================
# EXPORTED SETTINGS — SPLIT
# =============================================================================

# fraction of max HP at which a large slime converts. 0.5 = half health.
@export var split_hp_ratio: float = 0.5

# how many smalls each large becomes.
@export var small_count: int = 4

# how far from the dying large the smalls appear, in a ring.
@export var split_radius: float = 34.0

# how long the hitflash plays before the conversion. The hitflash animations
# are 4 frames at 10 fps = 0.4s, so this matches the art.
@export var hitflash_duration: float = 0.4


# =============================================================================
# EXPORTED SETTINGS — ATTACK TIMING
# =============================================================================

# which frame of the attack animation releases the projectile — the same
# idea as bushsniper.gd's ARROW_RELEASE_FRAME.
#
# Both read off the sprite sheet rather than guessed:
#
#   large attack* — 9 frames. The mouth is widest at 3-4 and the acid ball
#   is visibly clear of the body by 5.
#
#   small attack* — 23 frames of bow transform. The slime flattens into a
#   crescent (2-8), forms a bow and nocks an arrow (9-11), holds it drawn
#   (12-13), and looses at 14. Everything after is the bow relaxing and the
#   slime reforming, so releasing any later fires from a bow that has
#   already gone slack.
@export var large_release_frame: int = 5
@export var small_release_frame: int = 14

# how long the small's death animation plays before the slime is actually
# removed and its loot rolled. smalldeath* is 5 frames at 10 fps.
@export var small_death_duration: float = 0.5


# =============================================================================
# STATE
# =============================================================================

# spent the moment this slime duplicates — AND set on the twin at birth, so
# a duplicate can never duplicate again. See _spawn_slime().
var _has_duplicated: bool = false

# guards the split against running twice. Both the HP threshold in
# take_damage() and the _die() override can reach it, and without this a
# large could convert into two batches of smalls.
var _has_split: bool = false

# true once this slime is playing out a death or a split, so nothing tries
# to attack, move, or die a second time while that resolves.
var _is_resolving: bool = false


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# THE VARIANT IS PICKED HERE, ONCE, AND EVERYTHING ELSE FOLLOWS FROM IT.
	# enemy_data carries max_hp, so BaseEnemy._apply_enemy_data() fills the
	# health pool from whichever profile this is — the assignment that used to
	# happen on the next line.
	if enemy_data == null:
		enemy_data = SMALL_DATA if is_small else LARGE_DATA

	# Combat tuning stays here; only the reward profile moved.
	if is_small:
		attack_cooldown = small_attack_cooldown
		attack_range = small_attack_range
	else:
		attack_cooldown = large_attack_cooldown
		attack_range = large_attack_range

	# ONLY THE SMALLS ROLL — INCLUDING FOR THE LARGE.
	#
	# The large never dies: _die() routes it into _begin_split() and it is
	# consumed, so it has no death to drop anything from. Rather than bolt a
	# special-case roll onto the split, the large's pet chance is carried by
	# the four smalls it becomes — the same way its XP and its bag already are.
	# One roll site, one number to tune, and nothing to keep in sync.
	#
	# Unchanged behaviour; it just lives in the two .tres files now:
	#
	#   poisonslimesmall.tres  both slime pets, rare_pet_chance 0.20,
	#                          pet_odds_override 864, loot tier 1
	#   poisonslimelarge.tres  grants_rewards false, no bag, no pet, no XP
	#
	# The 864 is exactly 4 x 216, and that is the whole point: a large slime
	# always becomes four smalls, so clearing one encounter is four rolls at
	# 1 in 864, and 1 - (863/864)^4 = 1 in 216. That lands a full slime fight
	# on the same odds as a single bush mage kill — fair, given it is 220 hp
	# plus four 35 hp smalls. Retune it in the .tres, not here.

	super._ready()

	# after super._ready(), because BaseEnemy._wire_healthbar() runs in there
	# and sets min/max/value. It never touches geometry, so the size and
	# position fix has to happen here.
	_fit_healthbar_to_form()

	# frame-accurate firing, same as bushsniper.gd.
	if has_node("animatedsprite2d"):
		var sprite: AnimatedSprite2D = $animatedsprite2d
		if not sprite.frame_changed.is_connected(_on_frame_changed):
			sprite.frame_changed.connect(_on_frame_changed)


# ONE SCENE, TWO FORMS — the healthbar is the one node that didn't get the
# memo. Everything else keyed off `is_small` (stats, animation prefix,
# projectile, loot), but the bar kept the geometry authored for the large
# slime, so a small slime wore a bar wider than its own sprite, floating well
# above it. Eight of those on screen at once is why the field looked like it
# was covered in stray UI.
#
# Control.scale is used rather than resizing the box, because TextureProgressBar
# draws its textures at their own size unless nine-patch stretching is turned
# on — shrinking the rect alone would clip the bar instead of scaling it.
func _fit_healthbar_to_form() -> void:
	if not is_small:
		return
	if not has_node("healthbar"):
		return

	var bar: Control = $healthbar

	# derive the authored size from the offsets rather than reading `size`,
	# which isn't reliably laid out yet this early.
	var authored: Vector2 = Vector2(
		bar.offset_right - bar.offset_left,
		bar.offset_bottom - bar.offset_top
	)

	# scale about the bar's own centre. Without this, Control.scale shrinks
	# toward the top-left corner and the bar slides off the slime.
	bar.pivot_offset = authored * 0.5
	bar.scale = Vector2.ONE * small_healthbar_scale

	# and bring it down to sit just above the much shorter small sprite.
	bar.offset_top = small_healthbar_offset_y
	bar.offset_bottom = small_healthbar_offset_y + authored.y


func _physics_process(delta: float) -> void:
	# a slime mid-split or mid-death does not act.
	if _is_resolving:
		return

	super._physics_process(delta)
	_check_duplicate()


# =============================================================================
# ANIMATION NAMING
# =============================================================================
# BaseEnemy builds animation names as "walk" + dir, "attack" + dir and so
# on. The small form's clips are the same names with a "small" prefix
# (smallwalkleft, smallattackup...), so the three play_* helpers are
# overridden to insert it. Everything else in BaseEnemy keeps working
# unchanged, which is what lets both forms share one script.

func _anim_prefix() -> String:
	return "small" if is_small else ""


func play_walk_animation(dir: String) -> void:
	if dir != "":
		_set_animation(_anim_prefix() + "walk" + dir)


func play_attack_animation(dir: String) -> void:
	if dir != "":
		_set_animation(_anim_prefix() + "attack" + dir)


func play_idle_animation(dir: String) -> void:
	if dir != "":
		_set_animation(_anim_prefix() + "idle" + dir)


# =============================================================================
# ATTACKING
# =============================================================================

func get_move_speed() -> float:
	return small_move_speed if is_small else large_move_speed


func _trigger_attack() -> void:
	super._trigger_attack()
	# BaseEnemy clears is_attacking from _on_animation_finished(), which
	# cannot fire for a LOOPING animation — and smallattack* is currently
	# authored with loop on. Without this the small slime would begin its
	# bow transform and stay locked in it forever, never moving again.
	# Releasing on the animation's real duration works either way.
	_release_attack_after(_current_anim_duration())


func _release_attack_after(seconds: float) -> void:
	if seconds <= 0.0:
		return
	await get_tree().create_timer(seconds).timeout
	if not is_instance_valid(self) or _is_resolving:
		return
	if is_attacking:
		is_attacking = false
		play_idle_animation(attack_direction)


func _current_anim_duration() -> float:
	# length of whatever clip is playing right now, in seconds.
	if not has_node("animatedsprite2d"):
		return 0.0
	var sprite: AnimatedSprite2D = $animatedsprite2d
	var sf: SpriteFrames = sprite.sprite_frames
	if sf == null or not sf.has_animation(sprite.animation):
		return 0.0
	var fps: float = sf.get_animation_speed(sprite.animation)
	if fps <= 0.0:
		return 0.0
	return float(sf.get_frame_count(sprite.animation)) / fps


func _on_frame_changed() -> void:
	# release the projectile on the frame the art actually throws it.
	if _is_resolving or not has_node("animatedsprite2d"):
		return

	var sprite: AnimatedSprite2D = $animatedsprite2d
	if not sprite.animation.begins_with(_anim_prefix() + "attack"):
		return

	var release: int = small_release_frame if is_small else large_release_frame
	if sprite.frame != release:
		return

	fire_projectile()


func fire_projectile() -> void:
	# large spits an acid ball, small looses an arrow. Both aim at the
	# player's position at the moment of RELEASE, not at the start of the
	# wind-up, so a moving target is actually led.
	var scene: PackedScene = ARROW_SCENE if is_small else POISONBALL_SCENE
	if scene == null:
		return

	var origin: Vector2 = _projectile_origin(attack_direction)
	var projectile: Node = scene.instantiate()

	# aim BEFORE spawning — shoot_vector only sets velocity and rotation,
	# neither of which needs the node to be in the tree yet.
	if is_instance_valid(player) and projectile.has_method("shoot_vector"):
		projectile.shoot_vector(player.global_position - origin)
	elif projectile.has_method("shoot"):
		projectile.shoot(attack_direction)

	spawn_projectile_node(projectile, origin)


func _projectile_origin(dir: String) -> Vector2:
	# three steps down, so a missing marker never stops the slime firing:
	#   1. this form's own marker  (smallprojectileleft, or projectileleft)
	#   2. the large form's marker (so a small still fires from roughly
	#      the right side before its own markers are placed)
	#   3. the slime's centre
	var base_name: String = MARKER_NAMES.get(dir, "")
	if base_name == "":
		return global_position

	var marker: Node2D = get_node_or_null(_anim_prefix() + base_name) as Node2D
	if marker == null:
		marker = get_node_or_null(base_name) as Node2D

	if marker != null:
		return marker.global_position
	return global_position


# =============================================================================
# DUPLICATION  (large only, exactly once)
# =============================================================================

func _check_duplicate() -> void:
	# GUARD ORDER MATTERS: is_small first. A small slime must never reach
	# the spawn call below under any circumstance.
	if is_small or _has_duplicated:
		return
	if not is_instance_valid(player):
		return
	if global_position.distance_to(player.global_position) > duplicate_range:
		return

	# spend the flag BEFORE spawning. _spawn_slime() runs deferred, so
	# without this the next physics frame would arrive with the flag still
	# clear and queue a second twin.
	_has_duplicated = true

	# offset perpendicular to the player so the twin appears beside this
	# slime rather than in front of or behind it.
	var to_player: Vector2 = player.global_position - global_position
	var side: Vector2 = to_player.normalized().orthogonal() * duplicate_offset
	_spawn_slime(false, global_position + side)


# =============================================================================
# SPLITTING  (large only, exactly once)
# =============================================================================

func take_damage(amount: int, type: StringName = &"physical") -> void:
	super.take_damage(amount, type)

	# a large that survived the hit but crossed the threshold converts now.
	# One that was taken straight to zero is handled by _die() instead.
	if is_small or _has_split or _is_resolving:
		return
	if hp <= 0:
		return
	if float(hp) / float(max_hp) > split_hp_ratio:
		return

	_begin_split()


func _die() -> void:
	# LARGE: never actually dies. Anything that would kill it — including a
	# single hit large enough to skip past the 50% threshold entirely —
	# becomes the split instead. This is why the sheet has no large death
	# animation to play.
	if not is_small:
		if not _has_split:
			_begin_split()
		return

	# SMALL: a real death, but BaseEnemy._die() frees the node immediately
	# and never plays anything. Override to show smalldeath* first, then
	# hand back to BaseEnemy for the XP, the loot roll and the cleanup.
	if _is_resolving:
		return
	_is_resolving = true

	_stop_acting()
	_set_animation("smalldeath" + attack_direction)

	await get_tree().create_timer(small_death_duration).timeout
	if not is_instance_valid(self):
		return

	super._die()


func _begin_split() -> void:
	if is_small or _has_split:
		return
	_has_split = true
	_is_resolving = true

	_stop_acting()
	_set_animation("hitflash" + attack_direction)

	await get_tree().create_timer(hitflash_duration).timeout
	if not is_instance_valid(self):
		return

	_split_into_smalls()

	# the large is consumed by the split — no death animation, no bag, no XP,
	# no pet roll. Everything it was worth is now walking around as four
	# smalls, the pet chance included (see the pet_odds_override in _ready).
	queue_free()


func _split_into_smalls() -> void:
	# ring placement so the four don't stack on one another. They shove
	# apart anyway via enemy-vs-enemy collision, but starting them spread
	# out avoids a frame of overlap and the shunt that follows it.
	for i in range(small_count):
		var angle: float = TAU * (float(i) / float(small_count))
		var offset: Vector2 = Vector2(cos(angle), sin(angle)) * split_radius
		_spawn_slime(true, global_position + offset)


# =============================================================================
# SPAWNING
# =============================================================================

func _spawn_slime(small: bool, at_position: Vector2) -> void:
	# NOTE the parameter name. This was `spawn_position`, which shadows
	# BaseEnemy's own `spawn_position` — and that one means something quite
	# different: the enemy's HOME, recorded in _ready() and used by
	# _handle_return_home() to leash it back. Two unrelated meanings under
	# one name inside a function that spawns things is a trap for whoever
	# reads it next.
	var scene: PackedScene = load(SELF_SCENE_PATH)
	if scene == null:
		push_error("PoisonSlime: could not load %s" % SELF_SCENE_PATH)
		return

	var slime: Node = scene.instantiate()

	# CONFIGURE BEFORE THE NODE ENTERS THE TREE. is_small decides the stat
	# block in _ready(), and add_child() is what runs _ready() — set it
	# afterwards and the slime has already initialised as the wrong form.
	slime.is_small = small

	# EVERY child is born with its duplication spent, small or large. This
	# is the second half of the recursion guard: the twin from
	# _check_duplicate() must not duplicate again, and a small must never
	# duplicate at all.
	slime._has_duplicated = true

	# a small can never split either — it has no smaller form to become.
	slime._has_split = true if small else false

	var parent: Node = get_parent()
	if parent == null:
		parent = get_tree().current_scene
	parent.call_deferred("add_child", slime)

	# position after the deferred add, for the same reason projectiles do:
	# the node must be in the tree before global_position means anything.
	# SNAP ONTO THE NAVMESH FIRST. The split scatters four smalls at fixed
	# offsets around the parent, and nothing about a fixed offset knows where
	# the walls are - so a slime that dies with its back to a wall was placing
	# children inside it, or past the edge of the map entirely. Physics will
	# not push them out, because move_and_slide() only resists moving INTO a
	# wall; it has no opinion about already being in one.
	var safe_position: Vector2 = clamp_to_navigation(at_position)

	slime.call_deferred("set", "global_position", safe_position)

	# AND spawn_position explicitly, because _ready() already ran.
	#
	# add_child() runs the child's _ready() immediately, and BaseEnemy._ready()
	# captures `spawn_position = global_position` - which at that instant is
	# still (0,0), because the line above has not been applied yet. Every
	# runtime-spawned slime therefore believed its home was the world origin.
	#
	# That matters because the leash at BaseEnemy._physics_process sends an
	# enemy home once the player is further than leash_range, and
	# _handle_return_home() walks a STRAIGHT CARDINAL LINE with no navigation.
	# So getting 400px away from a split sent all four smalls plus the twin
	# marching through the walls to the top-left corner of the map, where they
	# idled forever - emptying the encounter.
	#
	# Deferred calls run in the order they are queued, so this lands after the
	# position above and records the real home.
	slime.call_deferred("set", "spawn_position", safe_position)

	slime.call_deferred("reset_physics_interpolation")


# =============================================================================
# SHARED TEARDOWN
# =============================================================================

func _stop_acting() -> void:
	# freeze a slime that's mid-split or mid-death: no movement, no further
	# hits landing on it, no colliding with the player while it plays out.
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
