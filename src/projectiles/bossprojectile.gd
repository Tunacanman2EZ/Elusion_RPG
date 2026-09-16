# bossprojectile.gd — the boss's ground attack: a red ring marks a patch of
# floor, and a moment later a stone spike punches up through it.
#
# NAMED FOR ITS SCENE, NOT ITS BEHAVIOUR. bossprojectile.tscn already existed
# — five authored frames of a spike rising and sinking — with no script, no
# collision shape and no layer, so nothing could spawn it and it could not have
# hit anything if it had. The name is kept so the scene keeps its uid; nothing
# about this travels, and "projectile" is the wrong word for it.
#
#
# THE RING IS THE ATTACK. The spike on its own is a hit you take or you don't,
# decided by where you happened to be standing — the player never sees it
# coming and learns nothing from being hit. The ring turns it into a decision:
# the ground you are on is about to kill you, and you have telegraph_seconds to
# be somewhere else.
#
# THE RING DOES NOT FOLLOW. It is painted where the player stood at the moment
# the boss discharged, and it stays there. A telegraph that tracks its target
# is not a telegraph, it is a delayed guaranteed hit — there is no correct
# response to it, so it teaches nothing and just feels arbitrary.
#
#
# ONLY DAMAGES PLAYERS, for the same reason acidpuddle.gd does: this is an
# enemy's attack, and a boss killing itself on its own spikes is not a fight.
extends Area2D


# =============================================================================
# CONSTANTS
# =============================================================================

# The animation's name inside the scene's SpriteFrames.
const RISE_ANIM := &"projectile"


# =============================================================================
# EXPORTED SETTINGS
# =============================================================================

# How long the ring is shown before the spike arrives. THE DIFFICULTY DIAL FOR
# THIS BOSS — it is the player's entire reaction window. Below about 0.5 it
# stops being a telegraph and becomes an unavoidable hit at any distance the
# player cannot cross in time.
@export var telegraph_seconds: float = 0.9

# Frame of the rise animation where the hazard is at full extension.
#
# EXPORTED, NOT A CONSTANT, because it belongs to the ART and there is now more
# than one set. The stone pillar's five frames are: 0 a nub breaking the
# surface, 1 FULL HEIGHT, 2 full height narrowing, 3 sinking, 4 nearly gone -
# so 1. The spike gate on spikegate.png runs down, half, up, half, and reaches
# full extension on 2.
#
# MEASURE IT OFF THE SHEET RATHER THAN GUESSING, because the obvious guess -
# the middle frame - is wrong for both of them. Set it too early and the hit
# lands before the hazard is visibly out of the ground; too late and it lands
# after it has visibly passed the player. Either way the player is hit by
# something they can see is not touching them.
@export var impact_frame: int = 1

# Damage applied once, on impact_frame, to every player inside the ring.
@export var damage: int = 18

# Named so a future armour or resistance system has something to match on,
# matching the convention acidpuddle.gd set with its "poison".
@export var damage_type: StringName = &"physical"

# Whether the spike leaves acid behind when it sinks back down.
#
# THE SAME MECHANIC THE POISON BALL ALREADY HAS, and deliberately the same
# scene - see poisonprojectile.gd::_leave_puddle(). What it does to this fight
# is turn a dodged attack into a lasting cost: ground the boss has already hit
# stops being ground you can stand on, so a long fight slowly runs out of floor.
#
# SET PER PILLAR BY THE BOSS, not left true for all of them. bossenemy.gd rolls
# PUDDLE_CHANCE for each one, because a cast can be sixty-five pillars and every
# one of them leaving acid floods the room - see puddle_lifetime below for the
# numbers. The default stays true so anything else spawning this scene still
# gets the behaviour without knowing about that.
@export var leaves_puddle: bool = true

# What the acid this pillar leaves is worth, overriding acidpuddle.tscn's own
# defaults.
#
# THE PUDDLE'S DEFAULTS ARE TUNED FOR A POISON BALL - one puddle, occasionally,
# from a single slime. This boss can put sixty-five pillars down in one cast,
# and at the scene's 4s lifetime that is a hundred and twenty pools alive at
# once covering 70% of the room. Not hard: unplayable, and unreadable with it.
#
# So the boss's acid is SHORTER and MEANER than the slime's. 2.5s keeps the
# floor changing rather than disappearing, and 8 a tick makes the ground it
# denies actually worth avoiding - the scene's 3 is 6 damage a second, which
# against a 180hp warrior is background noise.
@export var puddle_lifetime: float = 2.5
@export var puddle_tick_damage: int = 8

const PUDDLE_SCENE := preload("res://scene/projectiles/acidpuddle.tscn")

# Radius of the drawn ring. KEEP THIS MATCHED TO THE CollisionShape2D in the
# scene — this value is only what the player is shown, and the shape is what
# actually decides the hit. They are two numbers describing one circle, which
# is exactly the kind of pair that drifts apart; spelltargetcircle.gd carries
# the same warning about the same mistake.
@export var ring_radius: float = 20.0

# Ring colour. Alpha here is the outline's; the fill uses a fraction of it.
@export var ring_color: Color = Color(0.9, 0.12, 0.12, 0.85)


# Prints what each spike did at its impact moment: when it fired, off which
# path, and how many players it found. OFF BY DEFAULT and worth turning on the
# moment a spike looks like it passed through someone - it is the difference
# between "the hit did not happen" and "the hit happened and found nobody",
# which are two completely different bugs and look identical on screen.
@export var debug_impacts: bool = false


# =============================================================================
# STATE
# =============================================================================

var _telegraph_age: float = 0.0
var _erupting: bool = false

# Time since the spike started rising, and how long into that rise the hit is
# authored to land. See _measure_impact_delay().
var _erupt_age: float = 0.0
var _impact_delay: float = 0.0

# One damage application per eruption. frame_changed can fire more than once
# for a frame if the animation is restarted, and every character here carries
# both a body and a hurtbox area — arrow.gd's `_spent` latch exists for the
# same reason and its comment explains the double-damage bug in full.
var _spent: bool = false


# =============================================================================
# NODE REFERENCES
# =============================================================================

@onready var anim: AnimatedSprite2D = $animatedsprite2d


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	if not _validate_animation():
		queue_free()
		return

	# Hidden until the ring has finished filling. The spike is the payload,
	# not the warning — showing it during the telegraph would mean the player
	# is looking at the thing that is about to hurt them while it cannot.
	anim.visible = false

	anim.frame_changed.connect(_on_frame_changed)
	anim.animation_finished.connect(_on_animation_finished)

	_impact_delay = _measure_impact_delay()

	queue_redraw()


# How far into the rise the hit lands, in seconds, read off the authored frame
# durations.
#
# WHY THIS EXISTS AT ALL, when frame_changed already tells us the moment: because
# frame_changed is not a promise. It fires when the sprite's frame CHANGES, so
# any frame the engine steps straight over is a frame that never arrives - and
# this fight spawns sixty-five of these in one instant, which is exactly when
# frames get stepped over. It also depends on the animation actually starting
# from the beginning, which in turn depends on what frame the scene happened to
# be saved on.
#
# A spike that visibly erupts on the player and does nothing is the worst bug
# this fight can have, and it fails silently. So the animation decides how the
# hit LOOKS and this decides that it HAPPENS; whichever gets there first wins and
# _spent makes sure it is only counted once.
func _measure_impact_delay() -> float:
	var frames: SpriteFrames = anim.sprite_frames
	var speed: float = frames.get_animation_speed(RISE_ANIM)
	if speed <= 0.0:
		return 0.0

	# Summed rather than assumed equal - both these scenes hold their impact
	# frame several times longer than the rest.
	var total: float = 0.0
	var upto: int = mini(impact_frame, frames.get_frame_count(RISE_ANIM))
	for i in range(upto):
		total += frames.get_frame_duration(RISE_ANIM, i)
	return total / speed


func _validate_animation() -> bool:
	# Loud, early failure. Without these a missing animation throws inside
	# play() with an error that names neither this scene nor the caller.
	if anim == null:
		push_error("bossprojectile: animatedsprite2d not found")
		return false
	if anim.sprite_frames == null:
		push_error("bossprojectile: animatedsprite2d has no SpriteFrames")
		return false
	if not anim.sprite_frames.has_animation(RISE_ANIM):
		push_error("bossprojectile: SpriteFrames missing '%s' animation" % RISE_ANIM)
		return false
	if anim.sprite_frames.get_frame_count(RISE_ANIM) <= impact_frame:
		push_error("bossprojectile: '%s' has too few frames for impact_frame %d"
			% [RISE_ANIM, impact_frame])
		return false
	return true


func _process(delta: float) -> void:
	if _erupting:
		# The backstop described on _measure_impact_delay(). It costs one float
		# add per spike per frame and it is the only thing here that cannot be
		# skipped, dropped or thrown off by what frame the scene was saved on.
		if not _spent:
			_erupt_age += delta
			if _erupt_age >= _impact_delay:
				_apply_impact("timer")
		return

	_telegraph_age += delta

	# Redrawn every frame ONLY while the ring is filling — this is the one
	# thing here that actually animates, and _draw returns immediately once
	# the spike takes over, so there is no per-frame cost afterwards.
	queue_redraw()

	if _telegraph_age >= telegraph_seconds:
		_erupt()


func _erupt() -> void:
	_erupting = true
	anim.visible = true

	# WOUND BACK TO THE START EXPLICITLY, rather than trusting play() to do it.
	# play() only rewinds a finished animation when it can tell the animation is
	# finished, which it decides from the frame and frame_progress the node
	# currently holds - and those are saved into the scene file, so whatever
	# frame the sprite happened to be parked on in the editor when it was last
	# saved becomes the runtime starting state. secondbossprojectile.tscn was
	# saved sitting on its LAST frame at full progress; a spike that starts there
	# is over before it can pass through its impact frame, and it does nothing.
	anim.stop()
	anim.set_frame_and_progress(0, 0.0)
	anim.play(RISE_ANIM)

	# Clears the ring in the same frame the spike appears.
	queue_redraw()


# =============================================================================
# THE RING
# =============================================================================

func _draw() -> void:
	# Drawn rather than authored as a sprite because the fill has to track a
	# tunable duration. A pre-rendered ring animation would silently stop
	# matching telegraph_seconds the moment anyone changed it.
	if _erupting:
		return

	var progress: float = clampf(
		_telegraph_age / maxf(telegraph_seconds, 0.001), 0.0, 1.0)

	# The fill grows from the centre outward, so "full" reads as "now" without
	# the player having to time anything consciously.
	var fill: Color = ring_color
	fill.a = ring_color.a * 0.3
	draw_circle(Vector2.ZERO, ring_radius * progress, fill)

	# The outline is at full radius from the first frame, so the dangerous area
	# is known immediately — only the timing is in question, never the extent.
	draw_arc(Vector2.ZERO, ring_radius, 0.0, TAU, 32, ring_color, 2.0, true)


# =============================================================================
# IMPACT
# =============================================================================

func _on_frame_changed() -> void:
	if _spent or not _erupting:
		return
	if anim.animation != RISE_ANIM:
		return

	# AT OR PAST, not exactly on. An engine that steps from frame 1 to frame 3
	# in one hitch has skipped the impact frame, and an equality test treats that
	# as "the hit never came". The latch below is what keeps it to one hit.
	if anim.frame < impact_frame:
		return

	_apply_impact("frame")


func _apply_impact(via: String) -> void:
	if _spent:
		return
	_spent = true

	var hit: Array[Node] = _overlapping_player_nodes()
	if debug_impacts:
		print("[SPIKE] impact via %s at frame %d, %.2fs in, %d target(s)"
			% [via, anim.frame, _erupt_age, hit.size()])

	_damage_players(hit)


func _damage_players(targets: Array[Node]) -> void:
	# ONE hit per player, however many of their collision nodes are inside the
	# ring. A character with a body and a hurtbox on the same layer would
	# otherwise take the spike twice — see acidpuddle.gd, which dedupes by
	# instance id for exactly this reason.
	var already_hit: Array[int] = []

	for target in targets:
		var id: int = target.get_instance_id()
		if id in already_hit:
			continue
		already_hit.append(id)
		target.take_damage(damage, damage_type)


func _overlapping_player_nodes() -> Array[Node]:
	# Both lists, because some things collide as bodies and some expose a
	# hurtbox Area2D whose PARENT is the real character.
	var found: Array[Node] = []

	for body in get_overlapping_bodies():
		if _is_damageable_player(body):
			found.append(body)

	for area in get_overlapping_areas():
		var parent: Node = area.get_parent()
		if _is_damageable_player(parent):
			found.append(parent)

	_add_players_by_distance(found)
	return found


# THE SECOND OPINION, and the reason this hazard stopped silently missing.
#
# Everything above is the physics server's answer, and it is only as good as the
# assumptions behind it: that this area's shape was registered and its overlap
# list refreshed before the hit was asked for, that the part of the player
# standing on this ground is on a layer this mask happens to include, and that
# monitoring was never switched off in between. Each of those is true most of
# the time, and when one is not, the spike erupts on the player and nothing
# happens - with nothing logged, because as far as the code is concerned it
# asked who was here and was told nobody.
#
# So the geometry is also checked directly. It is two or three distance tests
# against whoever is in the "player" group, it cannot disagree with what the
# player can see, and anything it finds that the overlap lists did not is a hit
# that would otherwise have been lost.
func _add_players_by_distance(found: Array[Node]) -> void:
	var reach: float = _hit_radius()
	if reach <= 0.0:
		return

	for node in get_tree().get_nodes_in_group(&"player"):
		if node in found or not _is_damageable_player(node):
			continue
		var target: Node2D = node as Node2D
		if target == null:
			continue

		# AGAINST THE BODY, NOT THE NODE ORIGIN. Where a character's collision
		# sits relative to their origin is a per-scene authoring choice and the
		# four playable classes do not agree: the warrior's body is 13px BELOW
		# its origin and the tank's is 18px ABOVE. Measuring to the origin means
		# a 31px disagreement about where the player is standing, depending on
		# who is playing.
		var body: Vector2 = _body_centre(target)
		if global_position.distance_to(body) <= reach + _body_radius(target):
			found.append(node)


# Radius of this spike's own hit circle, in world units.
#
# READ OFF THE SHAPE AND SCALED, never assumed: bossenemy.gd sizes its spikes by
# scaling the whole node, so the authored radius and the real one differ by
# whatever scale it chose. ring_radius is only what gets DRAWN, and the file
# already carries a warning about those two drifting apart - this one asks the
# shape, which is what actually decides a hit.
func _hit_radius() -> float:
	var node: CollisionShape2D = get_node_or_null("collisionshape2d") as CollisionShape2D
	var scaled: float = absf(global_scale.x)
	if node == null or not (node.shape is CircleShape2D):
		return ring_radius * scaled
	return (node.shape as CircleShape2D).radius * scaled


func _body_centre(target: Node2D) -> Vector2:
	var body: Node2D = target.get_node_or_null("bodyshape") as Node2D
	if body != null:
		return body.global_position
	return target.global_position


func _body_radius(target: Node2D) -> float:
	var body: CollisionShape2D = target.get_node_or_null("bodyshape") as CollisionShape2D
	if body == null:
		return 8.0
	var scaled: float = absf(body.global_scale.x)
	if body.shape is CircleShape2D:
		return (body.shape as CircleShape2D).radius * scaled
	if body.shape is CapsuleShape2D:
		return (body.shape as CapsuleShape2D).radius * scaled
	return 8.0 * scaled


func _is_damageable_player(node: Node) -> bool:
	return node != null \
		and node.is_in_group(&"player") \
		and node.has_method(&"take_damage")


# =============================================================================
# CLEANUP
# =============================================================================

func _on_animation_finished() -> void:
	# Guarded on the animation name in case a variant ever plays debris or a
	# settle sequence after the rise.
	if anim.animation == RISE_ANIM:
		# LAST CHANCE. A spike that ran its entire animation without ever landing
		# its hit is a bug by definition, whatever the reason - so it lands here
		# rather than being thrown away. If this is ever the path that fires,
		# debug_impacts will say so and the real cause is worth finding.
		_apply_impact("finished")
		_leave_puddle()
		queue_free()


func _leave_puddle() -> void:
	# ON THE WAY BACK DOWN, not on impact. The spike is the attack; the acid is
	# what the attack leaves behind, so it should appear as the stone sinks
	# rather than competing with the hit for the player's attention.
	if not leaves_puddle or PUDDLE_SCENE == null:
		return

	# Captured NOW. queue_free() is on the next line and global_position will
	# not exist by the time the deferred calls below run - the same reason
	# poisonprojectile.gd reads its landing position up front.
	var landing: Vector2 = global_position

	var container: Node = get_tree().get_first_node_in_group("groundeffects")
	if container == null:
		container = get_tree().current_scene
	if container == null:
		return

	var puddle: Node2D = PUDDLE_SCENE.instantiate()

	# DEFERRED, because this runs from an animation callback inside the physics
	# step, and adding a node to the tree there throws "Can't change this state
	# while flushing queries". Deferring onto the CONTAINER rather than onto
	# this node is what makes it safe despite the queue_free() below: the
	# container outlives the spike, so the call still has a live receiver.
	# Set BEFORE it enters the tree, unlike the position: acidpuddle reads these
	# in its own _ready(), so deferring them would apply them a frame after the
	# puddle had already started ticking on the scene's defaults.
	puddle.lifetime = puddle_lifetime
	puddle.tick_damage = puddle_tick_damage

	container.call_deferred("add_child", puddle)
	puddle.call_deferred("set", "global_position", landing)
	puddle.call_deferred("reset_physics_interpolation")
