# bulletfield.gd - enemy bullets as a few packed arrays and ONE draw.
#
# WHAT USES IT: BulletZone (src/world/bulletzone.gd), which an area turns on
# with field.gd's `bullet_zone` - the Field since 0.22.0 - and the bullet-hell
# preview (scene/prototype/bullethellpreview.tscn), which is where it began.
#
# WHY NOT ONE NODE PER BULLET, which is what every other projectile in the game
# is (scene/projectiles/arrow.tscn: an Area2D, a Sprite2D, a collision shape, a
# visibility notifier and a script with its own _physics_process). That is
# right for dozens and wrong for hundreds: every one is a node in the tree, a
# body in the physics server and a separate script call every frame. Measured
# headless on 11 Oct, 4,000 of them cost 14.89 ms a frame as arrows and 1.66 ms
# here.
#
# AN ENEMY BULLET ONLY HAS TO HIT ONE THING: the player this game draws (see
# monstersync.gd, "EACH GAME IS HURT ONLY BY WHAT IT DRAWS"). So there is no
# physics. Each bullet is a slot in packed arrays; a frame moves every slot,
# checks one cell of the wall grid, measures one distance to the player's
# hitbox, and writes two numbers into a MultiMesh buffer that the renderer
# draws in a single call. Removing a bullet swaps the last one into its slot,
# so nothing is ever searched for or shifted.
#
# UNSHADED, AND THAT IS NOT COSMETIC. The Field is a crypt under a
# CanvasModulate of (0.28, 0.3, 0.4). Drawn like everything else, an orb came
# out a dim smudge on the dark floor - a frame grabbed under that modulate
# measured its white-hot core at (71, 77, 102). `render_mode unshaded` keeps
# both the modulate and the lights off it: the same core measured (255, 255,
# 255). A bullet you cannot see is the one thing a bullet hell may not have.
#
# THE TEXTURE AND SHADER ARE MADE HERE, not loaded: an 8x8 orb whose red
# channel marks the white core, tinted per bullet by the instance colour, which
# is the element's own (Element.colour_for). No art file, so it runs in a
# clone without the private art pack.
class_name BulletField
extends Node2D


# Floats per bullet in the MultiMesh buffer: a 2D transform is 8
# (x.x, y.x, pad, origin.x, x.y, y.y, pad, origin.y), the colour is 4 more.
const STRIDE: int = 12

# Drawn sizes in pixels. The orb is 8x8, so these are 1:1 and 2:1 - whole
# multiples, or nearest-neighbour filtering smears the pixel art.
const SMALL_SIZE: float = 8.0
const BIG_SIZE: float = 16.0

# How far from its centre a bullet counts as touching. Smaller than it is
# drawn, on purpose: the rim is decoration, and a hit the player cannot see
# coming is what makes a bullet hell feel unfair.
const SMALL_RADIUS: float = 2.5
const BIG_RADIUS: float = 5.5

# The bullet's own colour is taken in vertex(): by fragment(), COLOR has
# already been multiplied by the texture, which tinted every bullet the orb's
# green in the first preview.
const SHADER_CODE: String = """
shader_type canvas_item;
render_mode unshaded;
// r = white-hot core, g = brightness of the body, a = coverage.
varying vec4 tint;
void vertex() {
	tint = COLOR;
}
void fragment() {
	vec4 orb = texture(TEXTURE, UV);
	COLOR = vec4(mix(tint.rgb * orb.g, vec3(1.0), orb.r), orb.a * tint.a);
}
"""

@export var capacity: int = 12000

# Bullets leaving this rectangle are gone. The zone sets it to the area's
# floor; the preview to its arena.
#
# IT IS ALSO WHERE THE RENDERER IS TOLD THE BULLETS ARE (custom_aabb). Left to
# itself it culled the whole MultiMesh by a box around the world origin, so
# the preview - whose arena is centred on the origin - drew every orb, and the
# Field, where the player stands 900 px from it, drew none.
var bounds: Rect2 = Rect2(-400.0, -260.0, 800.0, 520.0):
	set(value):
		bounds = value
		_fit_culling()
var count: int = 0

# How long the last step() took, in microseconds.
var last_step_usec: int = 0

# What the last step() hit, one entry per bullet: (damage, element). Read it
# after step(); it is cleared at the start of the next one.
var hits: Array[Vector2i] = []

var _pos: PackedVector2Array = PackedVector2Array()
var _vel: PackedVector2Array = PackedVector2Array()
var _turn: PackedFloat32Array = PackedFloat32Array()
var _age: PackedFloat32Array = PackedFloat32Array()
var _life: PackedFloat32Array = PackedFloat32Array()
var _radius: PackedFloat32Array = PackedFloat32Array()
var _damage: PackedInt32Array = PackedInt32Array()
var _element: PackedInt32Array = PackedInt32Array()
var _grazed: PackedByteArray = PackedByteArray()
var _buffer: PackedFloat32Array = PackedFloat32Array()
var _multimesh: MultiMesh = null

# THE WALLS, as a grid of cells: 1 is solid. A bullet whose centre enters a
# solid cell is gone. Built once per area by BulletZone (set_walls); empty
# means no walls, which is what the preview has.
var _walls: PackedByteArray = PackedByteArray()
var _walls_origin: Vector2 = Vector2.ZERO
var _walls_cell: float = 8.0
var _walls_size: Vector2i = Vector2i.ZERO


func _ready() -> void:
	_pos.resize(capacity)
	_vel.resize(capacity)
	_turn.resize(capacity)
	_age.resize(capacity)
	_life.resize(capacity)
	_radius.resize(capacity)
	_damage.resize(capacity)
	_element.resize(capacity)
	_grazed.resize(capacity)
	_buffer.resize(capacity * STRIDE)

	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2.ONE
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_2D
	_multimesh.use_colors = true
	_multimesh.mesh = quad
	_multimesh.instance_count = capacity
	_multimesh.visible_instance_count = 0

	var shader: Shader = Shader.new()
	shader.code = SHADER_CODE
	var shading: ShaderMaterial = ShaderMaterial.new()
	shading.shader = shader

	_fit_culling()

	var drawer: MultiMeshInstance2D = MultiMeshInstance2D.new()
	drawer.name = "bullets"
	drawer.multimesh = _multimesh
	drawer.texture = orb_texture()
	drawer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	drawer.material = shading
	add_child(drawer)


func _fit_culling() -> void:
	if _multimesh == null:
		return
	var box: Rect2 = bounds.grow(BIG_SIZE)
	_multimesh.custom_aabb = AABB(Vector3(box.position.x, box.position.y, -1.0),
		Vector3(box.size.x, box.size.y, 2.0))


func set_walls(cells: PackedByteArray, origin: Vector2, cell: float, size: Vector2i) -> void:
	_walls = cells
	_walls_origin = origin
	_walls_cell = maxf(cell, 1.0)
	_walls_size = size


func is_wall(at: Vector2) -> bool:
	if _walls.is_empty():
		return false
	var cx: int = floori((at.x - _walls_origin.x) / _walls_cell)
	var cy: int = floori((at.y - _walls_origin.y) / _walls_cell)
	if cx < 0 or cy < 0 or cx >= _walls_size.x or cy >= _walls_size.y:
		return false
	return _walls[cy * _walls_size.x + cx] != 0


func spawn(origin: Vector2, angle: float, speed: float, colour: Color, big: bool = false,
		turn: float = 0.0, catch_up: float = 0.0, life: float = 14.0,
		damage: int = 0, element: int = 0) -> void:
	# catch_up: how late this shot is. A pattern fires on its own clock, not on
	# frames, so a shot that was due a few milliseconds before this frame is
	# moved on by those milliseconds. That is what puts the same bullet in the
	# same place on every screen, whatever each one's frame rate.
	if count >= capacity:
		return
	var velocity: Vector2 = Vector2.from_angle(angle) * speed
	var at: Vector2 = origin + velocity * catch_up
	if turn != 0.0 and catch_up > 0.0:
		# A curving shot caught up along its ARC, not along a straight line:
		# the chord of a turn of (turn * catch_up) radians, pointed halfway
		# round it. Straight-then-turn put a late orb several pixels off the
		# one fired on time.
		var swept: float = turn * catch_up
		var chord: float = 2.0 * speed / turn * sin(swept * 0.5)
		at = origin + Vector2.from_angle(angle + swept * 0.5) * chord
		velocity = velocity.rotated(swept)

	var i: int = count
	_pos[i] = at
	_vel[i] = velocity
	_turn[i] = turn
	_age[i] = catch_up
	_life[i] = life
	_radius[i] = BIG_RADIUS if big else SMALL_RADIUS
	_damage[i] = damage
	_element[i] = element
	_grazed[i] = 0

	var size: float = BIG_SIZE if big else SMALL_SIZE
	var o: int = i * STRIDE
	_buffer[o] = size
	_buffer[o + 1] = 0.0
	_buffer[o + 2] = 0.0
	_buffer[o + 3] = roundf(at.x)
	_buffer[o + 4] = 0.0
	_buffer[o + 5] = size
	_buffer[o + 6] = 0.0
	_buffer[o + 7] = roundf(at.y)
	_buffer[o + 8] = colour.r
	_buffer[o + 9] = colour.g
	_buffer[o + 10] = colour.b
	_buffer[o + 11] = colour.a
	count += 1


func step(delta: float, target: Vector2, target_radius: float, graze_radius: float,
		untouchable: bool) -> Vector2i:
	# Moves every bullet and answers (hits, grazes) against one hitbox; what
	# each hit carried is left in `hits`. A bullet that hits is spent. While
	# untouchable, bullets pass through, as they would through a ghost.
	var started: int = Time.get_ticks_usec()
	hits.clear()
	var grazes: int = 0
	var area: Rect2 = bounds
	var walled: bool = not _walls.is_empty()
	var i: int = 0
	while i < count:
		var velocity: Vector2 = _vel[i]
		var turn: float = _turn[i]
		var at: Vector2
		if turn != 0.0:
			# Along the arc's chord, half a turn in - the same sum spawn()
			# catches a late shot up with, so a curving orb lands in the same
			# place however the time is cut into frames.
			var swept: float = turn * delta
			var chord: float = velocity.length() * delta
			if absf(swept) > 0.000001:
				chord = 2.0 * velocity.length() / turn * sin(swept * 0.5)
			at = _pos[i] + velocity.rotated(swept * 0.5).normalized() * chord
			velocity = velocity.rotated(swept)
			_vel[i] = velocity
		else:
			at = _pos[i] + velocity * delta
		var age: float = _age[i] + delta
		if age > _life[i] or not area.has_point(at) or (walled and is_wall(at)):
			_remove(i)
			continue
		var reach: float = _radius[i] + target_radius
		var gap_squared: float = at.distance_squared_to(target)
		if gap_squared < reach * reach and not untouchable:
			hits.append(Vector2i(_damage[i], _element[i]))
			_remove(i)
			continue
		var near: float = reach + graze_radius
		if graze_radius > 0.0 and gap_squared < near * near and _grazed[i] == 0:
			_grazed[i] = 1
			grazes += 1
		_pos[i] = at
		_age[i] = age
		var o: int = i * STRIDE
		_buffer[o + 3] = roundf(at.x)
		_buffer[o + 7] = roundf(at.y)
		i += 1

	_multimesh.buffer = _buffer
	_multimesh.visible_instance_count = count
	last_step_usec = Time.get_ticks_usec() - started
	return Vector2i(hits.size(), grazes)


func position_of(i: int) -> Vector2:
	return _pos[i] if i >= 0 and i < count else Vector2.INF


func velocity_of(i: int) -> Vector2:
	return _vel[i] if i >= 0 and i < count else Vector2.ZERO


func damage_of(i: int) -> int:
	return _damage[i] if i >= 0 and i < count else 0


func element_of(i: int) -> int:
	return _element[i] if i >= 0 and i < count else -1


func colour_of(i: int) -> Color:
	if i < 0 or i >= count:
		return Color(0, 0, 0, 0)
	var o: int = i * STRIDE
	return Color(_buffer[o + 8], _buffer[o + 9], _buffer[o + 10], _buffer[o + 11])


func danger_at(point: Vector2, ahead: float, radius: float) -> float:
	# How crowded `point` will be in `ahead` seconds: every bullet's predicted
	# position within `radius`, weighted by closeness. Only the preview's
	# autopilot asks; nothing a player does goes through here.
	var total: float = 0.0
	var radius_squared: float = radius * radius
	for i in count:
		var future: Vector2 = _pos[i] + _vel[i] * ahead
		var gap_squared: float = future.distance_squared_to(point)
		if gap_squared < radius_squared:
			total += 1.0 / maxf(gap_squared, 4.0)
	return total


func clear() -> void:
	count = 0
	hits.clear()
	if _multimesh != null:
		_multimesh.visible_instance_count = 0


func _remove(i: int) -> void:
	var last: int = count - 1
	if i != last:
		_pos[i] = _pos[last]
		_vel[i] = _vel[last]
		_turn[i] = _turn[last]
		_age[i] = _age[last]
		_life[i] = _life[last]
		_radius[i] = _radius[last]
		_damage[i] = _damage[last]
		_element[i] = _element[last]
		_grazed[i] = _grazed[last]
		var o: int = i * STRIDE
		var from: int = last * STRIDE
		for k in STRIDE:
			_buffer[o + k] = _buffer[from + k]
	count = last


static func orb_texture() -> ImageTexture:
	# 8x8: a white-hot core (r), a lit body and a darker rim (g), and the rest
	# clear. Pixel centres are measured from (3.5, 3.5), so it is symmetric.
	var image: Image = Image.create(8, 8, false, Image.FORMAT_RGBA8)
	for y in 8:
		for x in 8:
			var gap: float = Vector2(x - 3.5, y - 3.5).length()
			var pixel: Color = Color(0.0, 0.0, 0.0, 0.0)
			if gap <= 1.6:
				pixel = Color(1.0, 1.0, 0.0, 1.0)
			elif gap <= 2.6:
				pixel = Color(0.0, 1.0, 0.0, 1.0)
			elif gap <= 3.9:
				pixel = Color(0.0, 0.55, 0.0, 1.0)
			image.set_pixel(x, y, pixel)
	return ImageTexture.create_from_image(image)
