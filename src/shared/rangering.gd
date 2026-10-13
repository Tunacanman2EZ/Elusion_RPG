# rangering.gd - a dashed line on the floor at a distance: how far something
# reaches (0.29.0).
#
# The owner, 13 Oct, after the monsters' red rings: "now we need one for range
# on warrior like distance for attack and enemies so i can see their detection
# range so a much bigger circle" - and, asked when a monster's should show,
# "Always, faint".
#
# Two users:
#   a monster's DETECTION   threatring.gd - a circle round it: how close you
#                           can come before it notices you (faint), and once
#                           it is after you, how far you have to get before it
#                           lets you go (brighter) - 0.30.0's notice_range and
#                           leash_range.
#   the warrior's REACH     warrior.gd - how far its sword cuts, each way, or
#                           with the Double Axe how far the axe flies and cuts.
#
# DASHED, where the aim rings are solid: an aim ring says which way, a range
# ring says how far, and thirty of them overlapping in the Field have to stay
# out of the way of everything else on the floor.
#
# NOT SQUASHED. The aim rings are drawn as ellipses because they stand for a
# circle on the floor seen at the game's angle. A range is the game's own
# measure - global_position.distance_to(), the same in every direction - so the
# line is drawn where that measure is reached, which is a circle in world
# space. Drawn any other way it would show a monster noticing you from further
# off sideways than it does.
#
# FOUR REACHES, BLENDED. The warrior's sword reaches a different distance each
# way (its four hitboxes are drawn by hand), so the line takes `reach_left`,
# `reach_right`, `reach_up` and `reach_down` and blends between them (cos^2 /
# sin^2): exact straight out each way, smooth between. A circle is the four
# the same.
class_name RangeRing
extends Node2D


const DASH := 9.0
const GAP := 7.0
const WIDTH := 1.0
# How bright the line goes as it flashes, and how long it takes to fade back.
const GLOW_ALPHA := 0.7
const GLOW_SECONDS := 0.35
# A line this short has no dashes worth the name; one this long is enough.
const FEWEST_DASHES := 12
const MOST_DASHES := 720

var reach_left: float = 0.0
var reach_right: float = 0.0
var reach_up: float = 0.0
var reach_down: float = 0.0
var colour: Color = Color(1.0, 1.0, 1.0, 0.2)
var _glow: float = 0.0


func _init() -> void:
	# Unshaded, like the aim rings: the Field's CanvasModulate would otherwise
	# take a faint line down to nothing.
	var lit := CanvasItemMaterial.new()
	lit.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = lit
	set_process(false)


func set_radius(radius: float) -> void:
	set_reaches(radius, radius, radius, radius)


func set_reaches(left: float, right: float, up: float, down: float) -> void:
	if is_equal_approx(left, reach_left) and is_equal_approx(right, reach_right) \
			and is_equal_approx(up, reach_up) and is_equal_approx(down, reach_down):
		return
	reach_left = left
	reach_right = right
	reach_up = up
	reach_down = down
	queue_redraw()


func set_colour(to: Color) -> void:
	if to.is_equal_approx(colour):
		return
	colour = to
	queue_redraw()


func radius_at(angle: float) -> float:
	"""How far the line is from the middle at `angle` (0 is right, PI/2 down):
	the reach that way, blended between the four."""
	var c: float = cos(angle)
	var s: float = sin(angle)
	return c * c * (reach_left if c < 0.0 else reach_right) + s * s * (reach_up if s < 0.0 else reach_down)


func farthest() -> float:
	return maxf(maxf(reach_left, reach_right), maxf(reach_up, reach_down))


func fired() -> void:
	"""Flashes it, as an attack goes."""
	_glow = GLOW_SECONDS
	set_process(true)
	queue_redraw()


func dash_count() -> int:
	var around: float = TAU * farthest()
	return clampi(int(around / (DASH + GAP)), FEWEST_DASHES, MOST_DASHES)


func _process(delta: float) -> void:
	_glow = maxf(_glow - delta, 0.0)
	queue_redraw()
	if _glow <= 0.0:
		set_process(false)


func _draw() -> void:
	if farthest() <= 0.0:
		return
	var line: Color = colour
	line.a = lerpf(colour.a, maxf(colour.a, GLOW_ALPHA), _glow / GLOW_SECONDS)
	var dashes: int = dash_count()
	var share: float = DASH / (DASH + GAP)
	var points := PackedVector2Array()
	for k in dashes:
		var a0: float = TAU * k / dashes
		var a1: float = TAU * (k + share) / dashes
		points.append(Vector2.from_angle(a0) * radius_at(a0))
		points.append(Vector2.from_angle(a1) * radius_at(a1))
	draw_multiline(points, line, WIDTH)
