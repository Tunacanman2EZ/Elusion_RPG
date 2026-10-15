# stirglow.gd - the glow under a monster of the land that is stirring (0.46.0).
#
# The owner, after trying the stirring lands: "i did not notice dps change on
# enemies or anything". A fire stir changed the fire monsters and nothing said
# which ones those were. So every monster of the stirring land stands in a
# pulsing pool of its land's colour, under its feet, while the stir lasts -
# whichever game runs it - and the glow goes the moment the stir does.
#
# SIZED LIKE THE THREAT RING (threatring.gd), from the monster's footprint and
# hurtbox, a little wider; a boss gets a boss-sized glow. Added as the
# monster's first child, so it draws under everything the monster draws,
# rings included.
class_name StirGlow
extends Node2D


# Its half-width and half-height, per pixel of the monster's radius - wider
# than the threat ring (1.8 x 0.8), so the ring sits inside it.
const PER_RADIUS := Vector2(2.3, 1.05)
const SMALLEST_RADIUS := 8.0
# Below the middle of the footprint, where the threat ring sits.
const BELOW_FOOTPRINT := 4.0
# One breath, in seconds, and how bright it is at its dimmest and brightest.
const PULSE_SECONDS := 1.6
const DIMMEST := 0.45
const BRIGHTEST := 0.95
# The pool: three ellipses, the outer faint, the inner strong - (share of the
# size, alpha).
const LAYERS := [[1.0, 0.16], [0.74, 0.24], [0.48, 0.34]]

var monster: BaseEnemy = null
var radii: Vector2 = Vector2(18.0, 8.0)
var colour: Color = Color(1, 1, 1, 0)
var _clock: float = 0.0


static func on(enemy: BaseEnemy) -> StirGlow:
	"""A glow for `enemy`, its first child, hidden until its land stirs."""
	var glow := StirGlow.new()
	glow.name = "stirglow"
	glow.monster = enemy
	var footprint: Node2D = enemy.get_node_or_null(^"bodyshape") as Node2D
	var radius: float = maxf(maxf(_radius_of(footprint), _radius_of(enemy.get_node_or_null(^"hurtbox/collisionshape2d"))),
		SMALLEST_RADIUS)
	glow.radii = Vector2(radius * PER_RADIUS.x, radius * PER_RADIUS.y)
	glow.position = (footprint.position if footprint != null else Vector2.ZERO) + Vector2(0.0, BELOW_FOOTPRINT)
	glow.visible = false
	enemy.add_child(glow)
	enemy.move_child(glow, 0)
	return glow


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


func lit() -> bool:
	"""Whether it shows: the monster is alive and of the land stirring now."""
	if monster == null or not is_instance_valid(monster):
		return false
	var land: int = Lands.stirring()
	return land != 0 and monster.current_element() == land and monster.hp > 0 and not monster._death_resolved


func _process(delta: float) -> void:
	var glowing: bool = lit()
	if glowing != visible:
		visible = glowing
	if not glowing:
		return
	var want: Color = Element.colour_for(Lands.stirring()).lightened(0.25)
	if not want.is_equal_approx(colour):
		colour = want
		queue_redraw()
	_clock = fmod(_clock + delta, PULSE_SECONDS)
	var breath: float = 0.5 - 0.5 * cos(TAU * _clock / PULSE_SECONDS)
	modulate.a = lerpf(DIMMEST, BRIGHTEST, breath)


func _draw() -> void:
	# An ellipse is a circle drawn in a squashed space.
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, radii.y / maxf(radii.x, 0.001)))
	for layer in LAYERS:
		draw_circle(Vector2.ZERO, radii.x * float(layer[0]), Color(colour, float(layer[1])))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
