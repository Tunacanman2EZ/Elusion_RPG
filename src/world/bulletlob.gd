# bulletlob.gd - a shot lobbed over everything to a spot on the floor, which
# bursts where it lands: the large slime's mortar (0.25.0).
#
# The owner, 12 Oct, picking from a list of ways to make slimes dangerous:
# "2 and 3" - a mortar blob lobbed to where you stand, and acid that settles on
# the floor. This is the first. It punishes standing still, which the slimes'
# straight shots never did: they were all aimed where you were, so walking
# sideways beat every one of them.
#
# WHAT FLIES IS THE ARTIST'S SHOT - the large slime's own acid ball sprite,
# taken off its scene (poisonslime.gd's _lob_art) and carried along the arc,
# drawn larger at the top of it so it reads as height. It flies OVER walls,
# monsters and players: nothing touches it in the air, which is what a lob is.
# The spot it will land on is marked on the floor from the moment it leaves -
# the crater's edge, filling in as it falls - because a hit you could not see
# coming is the one thing a bullet hell may not have.
#
# WHERE IT LANDS, three things, all this game's own:
#   the impact   one big orb on the spot for IMPACT_LIFE, carrying the acid
#                ball's full damage - the hit the ball would have been
#   the crater   a ring of orbs that leave the spot and settle a little way
#                out (BulletField.spawn_settling), lying there as mines
#   the puddle   the element's acid pool (Puddles.scene_for) - the same one the
#                ball leaves when it hits someone anywhere else in the game
#
# EVERY SCREEN LANDS IT: a follower's copy of the slime fires the same lob from
# the leader's "b" (monstersync.gd), and like every orb here it can hurt only
# the player of the game that draws it.
class_name BulletLob
extends Node2D


# The impact is an orb that lies on the spot this long: long enough to be
# met by a player standing there, short enough that the crater is what stays.
const IMPACT_LIFE: float = 0.15
# How high the arc rises: this much of the distance flown, and at least
# RISE_LEAST px, so even a lob at someone's feet goes up before it comes down.
const RISE_SHARE: float = 0.3
const RISE_LEAST: float = 28.0
# The art is drawn up to (1 + ART_GROWS) times its size at the top of the arc.
const ART_GROWS: float = 1.0
# Where the crater's ring starts: past the impact orb's reach on a player at the
# spot (BulletField.BIG_RADIUS + BulletZone.HITBOX_RADIUS, 11.5) and past what a
# ring orb of its own would reach from the middle.
const RING_STARTS_OUT: float = 12.0

var zone: BulletZone = null
var from: Vector2 = Vector2.ZERO
var to: Vector2 = Vector2.ZERO
var aim: float = 0.0
var flight: float = 1.0
var art: Node2D = null
var element: int = 0
var impact_damage: int = 1
var ring: int = 8
var ring_speed: float = 120.0
var crater: float = 40.0
var ring_damage: int = 1
var puddle: PackedScene = null

var _age: float = 0.0
var _landed: bool = false


func _ready() -> void:
	if art != null and art.get_parent() == null:
		add_child(art)
	_place()


func _process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	"""Moves the lob on by `delta` seconds, landing it when its flight is up."""
	if _landed:
		return
	_age += delta
	if _age >= flight:
		land()
		return
	_place()


func progress() -> float:
	return clampf(_age / maxf(flight, 0.001), 0.0, 1.0)


func height() -> float:
	"""How far above the floor the shot is now: a parabola, 0 at both ends."""
	var t: float = progress()
	var top: float = maxf(from.distance_to(to) * RISE_SHARE, RISE_LEAST)
	return top * 4.0 * t * (1.0 - t)


func _place() -> void:
	var t: float = progress()
	if art != null:
		art.position = to_local(from.lerp(to, t) - Vector2(0.0, height()))
		art.scale = Vector2.ONE * (1.0 + ART_GROWS * 4.0 * t * (1.0 - t))
	queue_redraw()


func _draw() -> void:
	var t: float = progress()
	var colour: Color = BulletZone.shot_colour(element)
	var spot: Vector2 = to_local(to)
	# The crater's edge, and its floor filling in as the shot comes down.
	draw_circle(spot, maxf(crater, 6.0) * t, Color(colour, 0.16))
	draw_arc(spot, maxf(crater, 6.0), 0.0, TAU, 40, Color(colour, 0.75), 1.0)
	# The shadow, on the floor under the shot.
	draw_set_transform(to_local(from.lerp(to, t)), 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2.ZERO, 4.0, Color(0.0, 0.0, 0.0, 0.35))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func land() -> void:
	if _landed:
		return
	_landed = true
	if zone != null and is_instance_valid(zone):
		zone.field.spawn(to, aim, 0.0, BulletZone.shot_colour(element), true, 0.0, 0.0, IMPACT_LIFE,
			impact_damage, element)
		# THE RING LEAVES FROM JUST OUTSIDE THE IMPACT'S REACH (0.25.3). Every
		# orb that reaches a player lands now, so a ring born on the spot would
		# hit a player standing there eight more times on top of the impact. The
		# spot is the acid ball's; the crater is for whoever was near it.
		zone.fire_ring(to, aim, ring, ring_speed, ring_damage, element, false, crater, RING_STARTS_OUT)
	_leave_puddle()
	queue_free()


func _leave_puddle() -> void:
	# The same pool, placed the same way, as poisonprojectile.gd's on a hit.
	if puddle == null or not is_inside_tree():
		return
	var pool: Node = puddle.instantiate()
	if "element" in pool:
		pool.set("element", element)
	pool.set("spawn_at", to)
	var container: Node = get_tree().get_first_node_in_group(&"groundeffects")
	if container == null:
		container = get_tree().current_scene
	if container == null:
		pool.free()
		return
	container.add_child.call_deferred(pool)
