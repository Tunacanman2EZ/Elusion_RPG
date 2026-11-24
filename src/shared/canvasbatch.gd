# canvasbatch.gd - a picture's shapes handed to the engine in ONE call (0.176.1).
#
# The owner: "work on this", of Crownfall's side panels at 214 draws each
# time they are painted. Measured (zz/batchprobe): the engine draws filled
# rects and lines together, but every circle, polygon, arc, polyline and rect
# outline is a draw call of its own - and a rect or line between two of them
# is one more. The bar and the two panels were 182 of them a repaint, and 22
# for their words (already written together, _write_held_words()).
#
# This stands in for the CanvasItem a drawing function draws on (`_cv` in
# crownfallrun.gd): it has the draw_* calls that function uses, with the
# engine's own arguments, and makes each into the triangles the engine would
# have made (zz/primprobe counted them): a filled circle is a fan of
# CIRCLE_SEGMENTS, an outline or an arc a polyline, a polyline a quad a
# segment with no joints, a rect outline four rects round its edge, a
# polygon Geometry2D's own triangles. end() hands them all to a canvas item
# in one RenderingServer.canvas_item_add_triangle_array, in the order they
# were drawn, so what is over what is unchanged. Words are not shapes: draw
# them on the canvas item itself, after end().
#
# A line of no width (-1, the engine's hairline) is drawn a pixel wide.
#
# No class_name: preload it by path.
extends RefCounted

const CIRCLE_SEGMENTS := 64

var points: PackedVector2Array = PackedVector2Array()
var colours: PackedColorArray = PackedColorArray()
var order: PackedInt32Array = PackedInt32Array()
var _n: int = 0
var _i: int = 0
# Shapes handed over by the last end() (the suite's).
var last_triangles: int = 0


func begin() -> void:
	_n = 0
	_i = 0


func end(on: CanvasItem) -> void:
	"""Everything since begin(), onto `on`'s canvas item in one call."""
	@warning_ignore("integer_division")
	last_triangles = _i / 3
	if _i > 0 and on != null:
		RenderingServer.canvas_item_add_triangle_array(on.get_canvas_item(), order.slice(0, _i),
			points.slice(0, _n), colours.slice(0, _n))
	_n = 0
	_i = 0


func _room(more_points: int, more_order: int) -> void:
	if _n + more_points > points.size():
		var grow: int = maxi(256, maxi(points.size() * 2, _n + more_points))
		points.resize(grow)
		colours.resize(grow)
	if _i + more_order > order.size():
		order.resize(maxi(384, maxi(order.size() * 2, _i + more_order)))


func _quad(p: Vector2, q: Vector2, r: Vector2, t: Vector2, colour: Color) -> void:
	_room(4, 6)
	points[_n] = p
	points[_n + 1] = q
	points[_n + 2] = r
	points[_n + 3] = t
	for k in 4:
		colours[_n + k] = colour
	order[_i] = _n
	order[_i + 1] = _n + 1
	order[_i + 2] = _n + 2
	order[_i + 3] = _n
	order[_i + 4] = _n + 2
	order[_i + 5] = _n + 3
	_n += 4
	_i += 6


func _box(r: Rect2, colour: Color) -> void:
	_quad(r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), colour)


func _segment(a: Vector2, b: Vector2, colour: Color, width: float) -> void:
	var along: Vector2 = b - a
	if along.length_squared() <= 0.0:
		return
	var side: Vector2 = Vector2(-along.y, along.x).normalized() * ((width if width > 0.0 else 1.0) * 0.5)
	_quad(a + side, b + side, b - side, a - side, colour)


func _shape(at: PackedVector2Array, tint: PackedColorArray) -> void:
	"""A polygon as the engine fills it: Geometry2D's triangles."""
	var tris: PackedInt32Array = Geometry2D.triangulate_polygon(at)
	if tris.is_empty():
		return
	_room(at.size(), tris.size())
	for k in at.size():
		points[_n + k] = at[k]
		colours[_n + k] = tint[k] if tint.size() == at.size() else tint[0]
	for k in tris.size():
		order[_i + k] = _n + tris[k]
	_n += at.size()
	_i += tris.size()


# ---- the engine's calls --------------------------------------------------------

func draw_rect(rect: Rect2, color: Color, filled: bool = true, width: float = -1.0, _antialiased: bool = false) -> void:
	if filled:
		_box(rect.abs(), color)
		return
	var r: Rect2 = rect.abs()
	if width <= 0.0:
		var corners := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end,
			Vector2(r.position.x, r.end.y), r.position])
		draw_polyline(corners, color, width)
		return
	var o: float = width * 0.5
	_box(Rect2(r.position + Vector2(-o, -o), Vector2(r.size.x + width, width)), color)
	_box(Rect2(r.position + Vector2(r.size.x - o, o), Vector2(width, r.size.y - width)), color)
	_box(Rect2(r.position + Vector2(-o, r.size.y - o), Vector2(r.size.x + width, width)), color)
	_box(Rect2(r.position + Vector2(-o, o), Vector2(width, r.size.y - width)), color)


func draw_line(from: Vector2, to: Vector2, color: Color, width: float = -1.0, _antialiased: bool = false) -> void:
	_segment(from, to, color, width)


func draw_polyline(at: PackedVector2Array, color: Color, width: float = -1.0, _antialiased: bool = false) -> void:
	for k in at.size() - 1:
		_segment(at[k], at[k + 1], color, width)


func draw_arc(center: Vector2, radius: float, start_angle: float, end_angle: float, point_count: int,
		color: Color, width: float = -1.0, _antialiased: bool = false) -> void:
	if point_count < 2:
		return
	var turn: float = clampf(end_angle - start_angle, -TAU, TAU)
	var at := PackedVector2Array()
	at.resize(point_count)
	for k in point_count:
		var a: float = start_angle + turn * (float(k) / float(point_count - 1))
		at[k] = center + Vector2(cos(a), sin(a)) * radius
	draw_polyline(at, color, width)


func draw_circle(position: Vector2, radius: float, color: Color, filled: bool = true, width: float = -1.0,
		_antialiased: bool = false) -> void:
	if not filled:
		draw_arc(position, radius, 0.0, TAU, CIRCLE_SEGMENTS + 1, color, width)
		return
	_room(CIRCLE_SEGMENTS + 1, CIRCLE_SEGMENTS * 3)
	points[_n] = position
	colours[_n] = color
	for k in CIRCLE_SEGMENTS:
		var a: float = float(k) * TAU / CIRCLE_SEGMENTS
		points[_n + 1 + k] = position + Vector2(cos(a), sin(a)) * radius
		colours[_n + 1 + k] = color
		order[_i] = _n
		order[_i + 1] = _n + 1 + k
		order[_i + 2] = _n + 1 + (k + 1) % CIRCLE_SEGMENTS
		_i += 3
	_n += CIRCLE_SEGMENTS + 1


func draw_colored_polygon(at: PackedVector2Array, color: Color, _uvs: PackedVector2Array = PackedVector2Array(),
		_texture: Texture2D = null) -> void:
	_shape(at, PackedColorArray([color]))


func draw_polygon(at: PackedVector2Array, tints: PackedColorArray, _uvs: PackedVector2Array = PackedVector2Array(),
		_texture: Texture2D = null) -> void:
	if tints.is_empty():
		return
	_shape(at, tints)
