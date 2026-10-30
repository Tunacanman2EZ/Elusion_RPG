# beckonarrow.gd - a small gold arrow that bobs over something, pointing down
# at it: "this, here". The Endless's chest has its own copy with a line of
# words under it (endlesschest.gd, "Grab your loot"); this one is the arrow
# alone, for a lever (0.97.0, the owner: "we also need to put arrows above
# levers in the game so players can see").
#
# Drawn as the map's arrow is: a filled shape outlined in black, so it reads on
# the dark crypt floor and on grass alike. Its tip is the node's origin; it
# bobs BOB pixels up and down, a whole pixel at a time, SPEED radians a second.
# It thinks only while shown. Unshaded, like the aim rings (RangeRing.unshaded()):
# the Field's darkness turned it a dull olive.
extends Node2D

const BOB := 2.0
const SPEED := 4.0
const COLOUR := Color(1.0, 0.86, 0.45)
const EDGE := Color(0, 0, 0, 0.85)

# Where the tip rests (the parent's coordinates); the bob moves round it.
var rest: Vector2 = Vector2.ZERO
var _bob: float = 0.0


static func make(at: Vector2) -> Node2D:
	"""An arrow with its tip resting at `at`, drawn over the world (z 3)."""
	var arrow: Node2D = (load("res://src/shared/beckonarrow.gd") as GDScript).new()
	arrow.name = "beckonarrow"
	arrow.z_index = 3
	arrow.material = RangeRing.unshaded()
	arrow.set("rest", at)
	arrow.position = at
	return arrow


func _ready() -> void:
	visibility_changed.connect(_on_visibility_changed)
	set_process(visible)


func show_it(on: bool) -> void:
	"""Shown or hidden; shown again, it starts its bob from the top."""
	if on == visible:
		return
	visible = on
	_bob = 0.0
	position = rest


func _on_visibility_changed() -> void:
	set_process(is_visible_in_tree())


func _process(delta: float) -> void:
	_bob = fmod(_bob + delta * SPEED, TAU)
	position = rest + Vector2(0.0, roundf(sin(_bob) * BOB))


func _draw() -> void:
	var points := PackedVector2Array([Vector2(0, 0), Vector2(-6, -7), Vector2(-2, -7), Vector2(-2, -11),
		Vector2(2, -11), Vector2(2, -7), Vector2(6, -7)])
	var ring := points.duplicate()
	ring.append(points[0])
	draw_polyline(ring, EDGE, 2.0)
	draw_colored_polygon(points, COLOUR)
