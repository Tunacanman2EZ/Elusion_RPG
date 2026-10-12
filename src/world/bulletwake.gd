# bulletwake.gd - orbs shed from a flying projectile, opening behind it in a V.
#
# The owner, of the sniper's helix (0.24.0): "if only the arrow hits its
# pointless howabout the vortex stays but it sprays bullet like a < if the
# arrow fired left". A child of the projectile it rides: every INTERVAL it
# sheds a pair of orbs from where the projectile is, flying back and out to
# either side, so the arrow draws a chevron behind itself - its point at the
# arrow, its arms trailing. It stops when the projectile does (a wall, a body,
# its lifetime), because it goes with it.
#
# Each game fires its own copy of the arrow (monstersync.gd's "b"), so each
# sheds its own wake; on the screen of the player the arrow hit, it stops
# there, which is the only screen it can hurt.
class_name BulletWake
extends Node


var zone: BulletZone = null
var interval: float = 0.08
var spread: float = 0.55          # radians off straight back, each side
var speed: float = 55.0
var most: int = 14                # pairs, at most
var damage: int = 1
var element: int = 0

var _clock: float = 0.0
var _shed: int = 0


static func on(projectile: Node, into: BulletZone, orb_damage: int, orb_element: int) -> BulletWake:
	"""A wake for `projectile`, added as its child: it starts when the
	projectile enters the tree and ends when it leaves."""
	var wake := BulletWake.new()
	wake.name = "wake"
	wake.zone = into
	wake.damage = orb_damage
	wake.element = orb_element
	projectile.add_child(wake)
	return wake


func _process(delta: float) -> void:
	var host: Node2D = get_parent() as Node2D
	if host == null or zone == null or not is_instance_valid(zone) or _shed >= most:
		return
	_clock += delta
	while _clock >= interval and _shed < most:
		_clock -= interval
		shed_once(host.global_position, _heading(host))


func shed_once(at: Vector2, heading: Vector2) -> void:
	"""One pair, from `at`, for a projectile flying `heading`."""
	if heading == Vector2.ZERO:
		return
	var back: float = (-heading).angle()
	var colour: Color = BulletZone.shot_colour(element)
	for side in [-1.0, 1.0]:
		zone.field.spawn(at, back + spread * side, speed, colour, false, 0.0, 0.0, BulletZone.LIFE,
			damage, element)
	_shed += 1


func _heading(host: Node) -> Vector2:
	# The arrow keeps a velocity; the fire, electric and poison projectiles a
	# direction. Either is the way it is flying.
	var v: Variant = host.get("velocity")
	if v is Vector2 and (v as Vector2) != Vector2.ZERO:
		return (v as Vector2).normalized()
	var d: Variant = host.get("direction")
	if d is Vector2:
		return (d as Vector2).normalized()
	return Vector2.ZERO
