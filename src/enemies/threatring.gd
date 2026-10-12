# threatring.gd - a monster's aim ring: a faint red ring round its feet with a
# red ball that points at the player it has picked out (0.28.0).
#
# The owner, 12 Oct, after the healer's and the warrior's rings: "i want the
# same ring for enemies but with a red dot and we will us detection to make the
# dot aim to the player". So the dot is the monster's own targeting made
# visible: it points at `player`, the body BaseEnemy chases and shoots at, and
# so - in a group - at whichever of you that monster is after.
#
# WHEN IT SHOWS. Only while the monster is after someone: its target is within
# leash_range (the distance it chases from - past it, it walks home), it is not
# held behind a gate, not frozen (the welcome story stops every monster's
# physics), and alive. A Field of thirty monsters would otherwise be thirty
# rings pointing at nothing.
#
# HOW CLOSE IT IS. The ball is dim while the monster is only chasing, and full
# red once you are inside its attack_range - it can shoot you from where it
# stands. It flashes as each attack begins (BaseEnemy._trigger_attack()).
#
# ON A FOLLOWER'S SCREEN (shared monsters, monstersync.gd) a copy of the monster
# has no target of its own - the leader's game runs it, and only where it is
# and what it plays are sent. The copy points at the player nearest to it,
# which is who the leader's picked too unless a target ran off.
#
# SIZED TO THE MONSTER from its own shapes: the ring sits a little below the
# middle of "bodyshape" (its footprint), and is as wide as the larger of that
# and its hurtbox, so a boss gets a boss-sized ring. A scaled monster scales it
# too - the ring is its child.
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

var monster: BaseEnemy = null
# Inside the monster's attack range: the full red.
var in_reach: bool = false


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
	refresh()


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
		return
	var who: Node2D = target()
	var after_someone: bool = who != null and not monster.gated and not monster._death_resolved \
		and monster.hp > 0 and monster.is_physics_processing()
	var to: Vector2 = Vector2.ZERO
	var apart: float = INF
	if after_someone:
		# The ball points at the body; how far apart they are is measured the
		# way the monster measures it (BaseEnemy._physics_process(), origin to
		# origin), so the ring shows and turns red exactly when it chases and
		# when it may shoot.
		to = Targets.body_point(who) - monster.global_position
		apart = monster.global_position.distance_to(who.global_position)
		after_someone = apart <= monster.leash_range
	visible = after_someone
	if not after_someone:
		return
	point_at(to)
	var close: bool = apart < monster.attack_range
	if close != in_reach:
		_tint(close)


func _tint(close: bool) -> void:
	in_reach = close
	var share: float = 1.0 if close else CHASING
	ring_colour = Color(RED_RING, RED_RING.a * share)
	ball_colour = Color(RED_BALL, RED_BALL.a * share)
	queue_redraw()
	if _ball != null:
		_ball.queue_redraw()
