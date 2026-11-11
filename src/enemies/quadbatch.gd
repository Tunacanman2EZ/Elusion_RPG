extends RefCounted
# =============================================================================
# QUADS IN ONE CALL (0.143.0, the arenas' refinement)
# =============================================================================
# The owner, after wave three was measured: "our goal is to still have room
# for more phsics so we need a lot of refinement". The arenas drew every quad
# with its own draw_primitive() - two fresh arrays and a call into the engine
# a quad, and a disc was sixteen to twenty of them, its corners worked out with
# sin() and cos() each time. Godot batched them into one draw call on the
# card, but the processor paid for every one: about half a millisecond a
# frame for wave three's floors in the container.
#
# A batch keeps one set of arrays for a layer, fills them in place (they grow
# once and are kept), draws a filled oval as a fan from a table of corners
# made once, and hands the whole layer to the engine in ONE call
# (RenderingServer.canvas_item_add_triangle_array) when its drawing is done.
# What is drawn is the same triangles in the same colours.
#
# Use: begin() in the layer's draw callback, quad()/oval()/band() for each
# shape, then end(layer). paint() does the three for a draw function.
#
# Two more savings, each measured on wave three (zz/wave3/bench.gd):
#   SMALL      an oval or rim narrower than SMALL px is drawn with half the
#              corners (10): a glow the size of a coin looks the same.
#   THE FLOOR  what lies on the floor - frost, cracks, pits, pools, the lava -
#              changes slowly, so an arena redraws its floor layer every
#              FLOOR_EVERY frames (turn()), each arena on its own frame; what
#              moves through the air (snow, embers, streaks) every frame.

const SEGMENTS := 20
const SMALL := 14.0
const FLOOR_EVERY := 2

static var _corners: PackedVector2Array = PackedVector2Array()
# Triangles handed over by every batch (for a bench; nothing reads it in play).
static var handed: int = 0

var points: PackedVector2Array = PackedVector2Array()
var colours: PackedColorArray = PackedColorArray()
var order: PackedInt32Array = PackedInt32Array()
var _n: int = 0
var _i: int = 0


static func corners() -> PackedVector2Array:
	"""The unit circle's SEGMENTS corners, worked out once."""
	if _corners.is_empty():
		_corners.resize(SEGMENTS)
		for s in SEGMENTS:
			var a: float = float(s) * TAU / SEGMENTS
			_corners[s] = Vector2(cos(a), sin(a))
	return _corners


static func turn(owner: Object, every: int) -> bool:
	"""Whether `owner` redraws this frame, once every `every` frames, on a
	frame of its own (its instance id), so several do not all land on one."""
	return (Engine.get_process_frames() + owner.get_instance_id()) % maxi(1, every) == 0


func begin() -> void:
	_n = 0
	_i = 0


func size() -> int:
	"""Triangles waiting to be drawn."""
	@warning_ignore("integer_division")
	return _i / 3


func _room(more_points: int, more_order: int) -> void:
	if _n + more_points > points.size():
		var grow: int = maxi(64, maxi(points.size() * 2, _n + more_points))
		points.resize(grow)
		colours.resize(grow)
	if _i + more_order > order.size():
		order.resize(maxi(96, maxi(order.size() * 2, _i + more_order)))


func quad(p: Vector2, q: Vector2, r: Vector2, t: Vector2, colour: Color) -> void:
	"""The quad p q r t, as draw_primitive() drew it (p q r and p r t)."""
	_room(4, 6)
	points[_n] = p
	points[_n + 1] = q
	points[_n + 2] = r
	points[_n + 3] = t
	colours[_n] = colour
	colours[_n + 1] = colour
	colours[_n + 2] = colour
	colours[_n + 3] = colour
	order[_i] = _n
	order[_i + 1] = _n + 1
	order[_i + 2] = _n + 2
	order[_i + 3] = _n
	order[_i + 4] = _n + 2
	order[_i + 5] = _n + 3
	_n += 4
	_i += 6


func oval(middle: Vector2, rx: float, ry: float, colour: Color) -> void:
	"""A filled oval round `middle`, rx across and ry down."""
	var c: PackedVector2Array = corners()
	var step: int = 2 if maxf(rx, ry) < SMALL else 1
	@warning_ignore("integer_division")
	var count: int = SEGMENTS / step
	_room(count + 1, count * 3)
	points[_n] = middle
	colours[_n] = colour
	for k in count:
		var s: int = k * step
		points[_n + 1 + k] = middle + Vector2(c[s].x * rx, c[s].y * ry)
		colours[_n + 1 + k] = colour
		order[_i] = _n
		order[_i + 1] = _n + 1 + k
		order[_i + 2] = _n + 1 + (k + 1) % count
		_i += 3
	_n += count + 1


func band(middle: Vector2, rx: float, ry: float, inner: float, colour: Color) -> void:
	"""An oval's rim: from `inner` of the way out (0 to 1) to its edge."""
	var c: PackedVector2Array = corners()
	var step: int = 2 if maxf(rx, ry) < SMALL else 1
	@warning_ignore("integer_division")
	var count: int = SEGMENTS / step
	_room(count * 2, count * 6)
	for k in count:
		var s: int = k * step
		var edge := Vector2(c[s].x * rx, c[s].y * ry)
		points[_n + 2 * k] = middle + edge * inner
		points[_n + 2 * k + 1] = middle + edge
		colours[_n + 2 * k] = colour
		colours[_n + 2 * k + 1] = colour
	for k in count:
		var a: int = _n + 2 * k
		var b: int = _n + 2 * ((k + 1) % count)
		order[_i] = a
		order[_i + 1] = b
		order[_i + 2] = b + 1
		order[_i + 3] = a
		order[_i + 4] = b + 1
		order[_i + 5] = a + 1
		_i += 6
	_n += count * 2


func end(on: CanvasItem) -> void:
	"""Hand everything since begin() to `on`'s canvas item in one call."""
	if _i == 0 or on == null:
		return
	RenderingServer.canvas_item_add_triangle_array(on.get_canvas_item(), order.slice(0, _i),
		points.slice(0, _n), colours.slice(0, _n))
	@warning_ignore("integer_division")
	handed += _i / 3
	_i = 0
	_n = 0


func paint(on: CanvasItem, body: Callable) -> void:
	"""(A layer's draw callback.) begin(), `body`, end(on)."""
	begin()
	body.call()
	end(on)
