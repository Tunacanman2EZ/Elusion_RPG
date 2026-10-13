# aimring.gd - a ring on the floor under the healer, with a ball on it that
# points where the next shot goes (0.26.0).
#
# The owner, 12 Oct: "what if we add a small circle under the character with a
# ball in it that is like a round slider in a sense to detect mouse and player
# can see the direction they click for much better accuracy ... the ball would
# move when player clicks on the screen to show the accuracy of aim". The
# healer fires a stream at the cursor ten times a second, and until now nothing
# on screen said which way that stream was about to go before it went.
#
# WHAT IT SHOWS IS THE SHOT'S OWN DIRECTION, read from the same function the
# shot uses (healer.gd's aim_direction_to()), never a second guess at it - a
# ring that pointed somewhere slightly different from the orbs would be worse
# than no ring.
#
# AN ELLIPSE, NOT A CIRCLE: a circle lying on the floor, seen from above at the
# game's angle. The ball sits on it at the aim's angle, so straight left is the
# left end and straight up the far side.
#
# THE RING BEHIND THE CHARACTER, THE BALL IN FRONT. The ring is the healer's
# first child, so it draws before the sprite: it is on the ground, under the
# feet. The ball is drawn on a child one layer up (z_index 1), because aiming
# up puts it on the far side of the ring - behind the legs, where the first
# recording lost it.
#
# UNSHADED, like the orbs (turretprojectile.gd, bulletfield.gd). Drawn like the
# floor, the Field's dark CanvasModulate took it down to a grey smudge in the
# first recording; an aid you cannot see is no aid.
#
# PLACED AT ONE HEIGHT, DRAWN AT ANOTHER (0.33.0, the mage's and the tank's -
# the owner: "meant mage and tank just aim ring"). Those two bodies are
# y-sorted: their children are drawn in order of height, not of the tree, and
# their pictures are placed well above their feet (the mage's 19 px). A ring
# placed at the feet would be drawn after the picture - over the robe. So it is
# placed a hair above the picture, where it is drawn first, and drawn
# `drawn_at` below that, round the feet. player.gd's _add_aim_ring() works the
# two out.
class_name AimRing
extends Node2D


# The ring's half-width and half-height, in world pixels.
const RADII := Vector2(18.0, 8.0)
const BALL_RADIUS := 2.0
const RING_COLOUR := Color(1.0, 0.95, 0.8, 0.22)
const BALL_COLOUR := Color(0.7, 1.0, 0.6, 0.85)
# While firing the ring and the ball brighten, and fall back over this long
# after the last shot.
const GLOW_SECONDS := 0.35

var aim: Vector2 = Vector2.RIGHT
# The ring's size and colours, the constants above unless a ring is made for
# something else - a monster's (threatring.gd, 0.28.0) is red and sized to it.
var radii: Vector2 = RADII
var ring_colour: Color = RING_COLOUR
var ball_colour: Color = BALL_COLOUR
# Where the middle of the ring is drawn, from where it is placed (above).
var drawn_at: Vector2 = Vector2.ZERO
# Whether the ring draws a line of its own. The tank's does not: it wears an
# orange ring at its feet already (tank.tscn's "ring"), and its ball rides
# that one rather than a second line just inside it.
var line: bool = true
var _glow: float = 0.0
var _ball: Node2D = null


func _init() -> void:
	var lit := CanvasItemMaterial.new()
	lit.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = lit
	_ball = Node2D.new()
	_ball.name = "ball"
	_ball.z_index = 1
	_ball.material = lit
	_ball.draw.connect(_draw_ball)
	add_child(_ball)


func point_at(direction: Vector2) -> void:
	"""Where the ball sits: `direction`, the way the next shot will go."""
	if direction == Vector2.ZERO:
		return
	if not direction.is_equal_approx(aim):
		aim = direction.normalized()
		_ball.queue_redraw()


func fired() -> void:
	"""A shot left: the ring brightens."""
	_glow = GLOW_SECONDS
	queue_redraw()
	_ball.queue_redraw()


func ball_position() -> Vector2:
	"""Where the ball is drawn, relative to the ring's centre: the point of the
	ellipse at the aim's angle."""
	return Vector2(aim.x * radii.x, aim.y * radii.y)


func centre() -> Vector2:
	"""The middle of the ring, in the world - where it is drawn, not where it
	is placed."""
	return to_global(drawn_at)


func _process(delta: float) -> void:
	if _glow > 0.0:
		_glow = maxf(_glow - delta, 0.0)
		queue_redraw()
		_ball.queue_redraw()


func _draw() -> void:
	if not line:
		return
	var lift: float = _glow / GLOW_SECONDS
	var ring: Color = ring_colour
	ring.a = lerpf(ring_colour.a, 0.6, lift)
	# Points rather than a squashed circle, so the line is as thin across the
	# top as down the sides.
	var points := PackedVector2Array()
	for k in 41:
		var a: float = TAU * k / 40.0
		points.append(drawn_at + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	draw_polyline(points, ring, 1.0)


func _draw_ball() -> void:
	var lift: float = _glow / GLOW_SECONDS
	var ball: Color = ball_colour
	ball.a = lerpf(ball_colour.a, 1.0, lift)
	_ball.draw_circle(drawn_at + ball_position(), BALL_RADIUS + lift * 0.8, ball)
