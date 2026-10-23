# threatring.gd - a monster's aim ring: a faint red ring round its feet with a
# red ball that points at the player it has picked out (0.28.0).
#
# The owner, 12 Oct, after the healer's and the warrior's rings: "i want the
# same ring for enemies but with a red dot and we will us detection to make the
# dot aim to the player". So the dot is the monster's own targeting made
# visible: it points at `player`, the body BaseEnemy chases and shoots at, and
# so - in a group - at whichever of you that monster is after.
#
# WHEN IT SHOWS. Only while the monster is after someone - BaseEnemy.engaged,
# set as its target comes within notice_range or it is hit, cleared once they
# are past leash_range (0.30.0; until then, simply "within leash_range") - and
# is not held behind a gate, not frozen (the welcome story stops every
# monster's physics), and alive. A Field of thirty monsters would otherwise be
# thirty rings pointing at nothing.
#
# HOW CLOSE IT IS. The ball is dim while the monster is only chasing, and full
# red once you are inside its attack_range - it can shoot you from where it
# stands. It flashes as each attack begins (BaseEnemy._trigger_attack()).
#
# ON A FOLLOWER'S SCREEN (shared monsters, monstersync.gd) a copy of the monster
# has no target of its own - the leader's game runs it, and only where it is
# and what it plays are sent. The copy points at the player nearest to it,
# which is who the leader's picked too unless a target ran off, and works out
# whether it is after them by the same rule (keep_after(), and a hit on it).
#
# SIZED TO THE MONSTER from its own shapes: the ring sits a little below the
# middle of "bodyshape" (its footprint), and is as wide as the larger of that
# and its hurtbox, so a boss gets a boss-sized ring. A scaled monster scales it
# too - the ring is its child.
#
# AND HOW FAR IT NOTICES YOU (0.29.0). The owner: "enemies so i can see their
# detection range so a much bigger circle", shown "Always, faint". `sense` is
# a dashed circle (rangering.gd) round the monster's middle - where BaseEnemy
# measures from - shown whenever the monster could notice anyone (not gated,
# frozen or dead). Since 0.30.0 ("now fix monster leash and radius" - "Notice
# close, chase far") it is one of two lines:
#
#   not after anyone   notice_reach(), faint: cross it and it comes for you
#   after someone      leash_range, brighter: get past it and it lets you go
#
# In 0.29.0 both were the leash, 400 to 500 px - wider than the screen.
#
# CHEAP IN A CROWD (0.66.0). The owner's 4x stress test: every awake monster
# worked its ring out again every frame, and 790 of them cost 5.7 of the 9 ms
# the frame's scripts took. Now each looks again every REFRESH_SECONDS, each
# at its own moment (so a crowd's rings do not all land on one frame) - 20
# times a second is quicker than the eye follows a ball round a ring. And
# both rings are drawn on the floor (z -1, under every picture and prop, as a
# line on the ground should be), all of them with RangeRing's one material,
# so a crowd's rings are drawn together instead of one draw call each. A
# boss's stay at z 0 (see on()).
class_name ThreatRing
extends AimRing


const Targets := preload("res://src/shared/targets.gd")

const RED_RING := Color(1.0, 0.35, 0.3, 0.22)
const RED_BALL := Color(1.0, 0.2, 0.16, 0.95)
# How much of its colour the ring and ball keep while the monster is only
# chasing, out of its reach.
const CHASING := 0.45
# The ring's middle, below the middle of the footprint.
const BELOW_FOOTPRINT := 4.0
# Its half-width and half-height, per pixel of the monster's radius.
const PER_RADIUS := Vector2(1.8, 0.8)
const SMALLEST_RADIUS := 8.0
# The detection circle: faint while the monster is not after anyone, brighter
# once it is.
const SENSE_IDLE := Color(1.0, 0.35, 0.3, 0.14)
const SENSE_AFTER := Color(1.0, 0.35, 0.3, 0.32)

var monster: BaseEnemy = null
# Inside the monster's attack range: the full red.
var in_reach: bool = false
# The detection circle, the monster's child beside this ring.
var sense: RangeRing = null
# How often the ring looks again at who its monster is after, in seconds:
# while it is after somebody (the ball follows them), and while it is not
# (only its faint circle shows, and BaseEnemy says the moment it turns -
# look_now()).
const REFRESH_SECONDS := 0.05
const IDLE_REFRESH_SECONDS := 0.25
# On the floor: under the monster, every other picture and the props.
const FLOOR_Z := -1
var _refresh_in: float = 0.0


static func on(enemy: BaseEnemy) -> ThreatRing:
	"""A ring for `enemy`, added as its first child so it draws under it,
	hidden until the monster is after someone."""
	var ring := ThreatRing.new()
	ring.name = "threatring"
	ring.monster = enemy
	var footprint: Node2D = enemy.get_node_or_null(^"bodyshape") as Node2D
	var radius: float = maxf(maxf(_radius_of(footprint), _radius_of(enemy.get_node_or_null(^"hurtbox/collisionshape2d"))),
		SMALLEST_RADIUS)
	ring.radii = Vector2(radius * PER_RADIUS.x, radius * PER_RADIUS.y)
	ring.position = (footprint.position if footprint != null else Vector2.ZERO) + Vector2(0.0, BELOW_FOOTPRINT)
	ring._tint(false)
	ring.visible = false
	# A BOSS'S STAYS IN THE WORLD, at z 0 as every ring was before. There is one
	# boss in its room - nothing to draw together with - and the crypt arena lays
	# its dais on "grounddecals" at z 0, which would cover a ring on the floor.
	var floor_z: int = 0 if enemy.is_in_group(&"unpushable") else FLOOR_Z
	ring.z_index = floor_z
	# The ball stays where it was drawn, over the world (it was z 1 on a ring
	# at 0): +2 on a ring at -1.
	ring._ball.z_index = 1 - floor_z
	ring._refresh_in = randf() * REFRESH_SECONDS
	# The detection circle round the monster's middle, where BaseEnemy measures
	# from. Added first, so the ring ends up the first child and it the second:
	# both before the monster's own picture.
	ring.sense = RangeRing.new()
	ring.sense.name = "detectionring"
	ring.sense.colour = SENSE_IDLE
	ring.sense.visible = false
	ring.sense.z_index = floor_z
	enemy.add_child(ring.sense)
	enemy.move_child(ring.sense, 0)
	enemy.add_child(ring)
	enemy.move_child(ring, 0)
	return ring


static func _radius_of(node: Node) -> float:
	var shaped: CollisionShape2D = node as CollisionShape2D
	if shaped == null or shaped.shape == null:
		return 0.0
	var shape: Shape2D = shaped.shape
	if shape is CircleShape2D:
		return (shape as CircleShape2D).radius
	if shape is CapsuleShape2D:
		return (shape as CapsuleShape2D).radius
	if shape is RectangleShape2D:
		return (shape as RectangleShape2D).size.x * 0.5
	return 0.0


func _process(delta: float) -> void:
	super._process(delta)
	_refresh_in -= delta
	if _refresh_in > 0.0:
		return
	# Kept in step, so each ring keeps its own moment in the crowd's cycle.
	# A MONSTER WAITING ITS TURN (BaseEnemy, SEATS) stands still, so its ring
	# looks at the idle pace: at 16x that is 300 rings of 360 (0.76.0).
	var every: float = REFRESH_SECONDS if monster != null and monster.engaged and not monster.waiting_turn \
		else IDLE_REFRESH_SECONDS
	_refresh_in = maxf(_refresh_in + every, 0.0)
	refresh()


func look_now() -> void:
	"""Its monster has just turned after somebody, or let them go: look again
	this frame rather than at the next turn of the clock."""
	_refresh_in = 0.0


func target() -> Node2D:
	"""Who the dot points at: the monster's own target, or - for a follower's
	copy, which has none - the player nearest to it."""
	if monster == null:
		return null
	if is_instance_valid(monster.player):
		return monster.player
	if monster.net_mirror and monster.is_inside_tree():
		return Targets.nearest(monster.get_tree(), monster.global_position)
	return null


func refresh() -> void:
	"""Shown or not, where the ball points, and how red."""
	if monster == null or not is_instance_valid(monster):
		visible = false
		if sense != null and is_instance_valid(sense):
			sense.visible = false
		return
	var who: Node2D = target()
	var awake: bool = not monster.gated and not monster._death_resolved \
		and monster.hp > 0 and monster.is_physics_processing()
	var after_someone: bool = false
	var to: Vector2 = Vector2.ZERO
	var apart: float = INF
	if who != null and awake:
		# The ball points at the body; how far apart they are is measured the
		# way the monster measures it (BaseEnemy._physics_process(), origin to
		# origin), so the ring turns red exactly when it may shoot.
		to = Targets.body_point(who) - monster.global_position
		apart = monster.global_position.distance_to(who.global_position)
		# WHETHER IT IS AFTER THEM is the monster's own: its AI keeps
		# `engaged` (BaseEnemy.keep_after()). A follower's copy runs no AI, so
		# the same rule is applied here, to the player nearest it.
		if monster.net_mirror:
			monster.keep_after(apart)
		after_someone = monster.engaged and apart <= monster.leash_range
	_sense(awake, after_someone)
	# AIM RINGS SWITCHED OFF in Options (0.31.0) hide this one too; it is the
	# monster's aim ring.
	visible = after_someone and bool(Settings.get_value("aim_rings"))
	if not after_someone:
		return
	point_at(to)
	var close: bool = apart < monster.attack_range
	if close != in_reach:
		_tint(close)


func _sense(awake: bool, after_someone: bool) -> void:
	"""The detection circle: there whenever the monster could notice anyone -
	as wide as it notices from, or once it is after someone as wide as it
	chases, and brighter."""
	if sense == null or not is_instance_valid(sense):
		return
	# RANGE CIRCLES SWITCHED OFF in Options (0.31.0): none at all.
	sense.visible = awake and bool(Settings.get_value("range_circles"))
	if not awake:
		return
	# Not after anyone: how close you can come. After someone: how far they
	# have to get.
	sense.set_radius(monster.leash_range if after_someone else monster.notice_reach())
	sense.set_colour(SENSE_AFTER if after_someone else SENSE_IDLE)


func _tint(close: bool) -> void:
	in_reach = close
	var share: float = 1.0 if close else CHASING
	ring_colour = Color(RED_RING, RED_RING.a * share)
	ball_colour = Color(RED_BALL, RED_BALL.a * share)
	queue_redraw()
	if _ball != null:
		_ball.queue_redraw()
