extends Node2D
# spikefx.gd - what a boss's spikes draw on the floor and in the air, drawn
# together (0.137.5): the warning rings, the sparks, and the pools.
#
# The owner: "when 16 spikes raise up leave poin clouds ... and there is a
# huge measurement of speed going on", and "if i have 3 bosses all doing that
# at once you see the issue". Three bosses casting together on the container's
# GL (zz/benchspikes, THREE): 500 to 1,100 draw calls a frame. Each spike drew
# its own ring - a filled circle and an outline, two draws, drawn again every
# frame of its warning - each eruption made a CPUParticles2D of its own (a draw
# each, 130 to 500 alive), a spike of an element with no scene of its own made
# itself a material (so no two could be drawn together), and the pools sat in
# the world's y-sort between them. A phone's browser pays for every draw.
#
# One of these in each effects container ("groundeffects"), made with the area
# by AreaRegistry (add_to(); shaderwarm.gd warms the shaders) or by the first
# spike that needs one (of()):
#   - THE RINGS: one MultiMesh, an instance a spike while it warns. The shader
#     (spikerings.gdshader) grows the fill from the instance's start and
#     length, so nothing is written while the spikes warn, only when a warning
#     starts or ends. The warnings END here too (_process()): a spike has no
#     _process of its own.
#   - THE SPARKS: one MultiMesh, an instance a BURST - every spark of it a
#     quad of the mesh, its flight worked out by spikesparks.gdshader from the
#     element's numbers - written once, when the spike erupts.
#   - THE POOLS a spike leaves: a holder an element (puddles_for()), so pools
#     of one element are drawn together.
#
# ON THE FLOOR, UNDER EVERYTHING STANDING. This node stands at SORT_Y, far off
# the top of any map, so the world's y-sort draws it first: the pools, then
# the rings over them, then all that stands - the spikes, the players, the
# boss. A ring used to be sorted by its middle, so it was drawn over the feet
# of anybody in its upper half, and a pool over the spikes behind it. The
# sparks are drawn above everything (z_index 1), as before.
#
# HALF FLOATS. On the web (the Compatibility renderer) a MultiMesh's colour
# and custom data reach the GPU as 16-bit floats - about three figures - so a
# time there is on a clock that comes round every WRAP seconds: an age is
# (now - start) mod WRAP, true for anything younger than that. Nothing here
# lives that long: a ring goes when its spike erupts, a burst when its sparks
# are spent.
#
# ONLY WHAT IS ALIVE IS DRAWN. Both MultiMeshes are kept packed - one that
# ends is replaced by the last (_remove_ring_at(), _spend_bursts()) - and
# draw only as many instances as there are.

const LagTests := preload("res://src/systems/lagtests.gd")
const RING_SHADER := preload("res://src/projectiles/spikerings.gdshader")
const SPARK_SHADER := preload("res://src/projectiles/spikesparks.gdshader")

const NODE_NAME := "spikefx"
const META := &"spike_fx"
# Far above the top of any map: first in the world's y-sort.
const SORT_Y := -100000.0
const WRAP := 16.0
# The fill and the outline, as draw_circle() and draw_arc(..., 32, ..., 2.0,
# true) drew them: a 2 px line with a soft edge a pixel wide.
const FILL_POINTS := 48
const RING_POINTS := 32
const RING_HALF := 1.0
const FEATHER := 1.0
# The most sparks one burst has (wind's 30).
const BURST_QUADS := 32
# Element.Type's count: the shader's tables.
const ELEMENTS := 10
# Instances to begin with; doubled whenever they are all in use.
const ROOM := 64
# Floats an instance: a 2D transform (8), a colour (4), custom data (4).
const RING_STRIDE := 16
# A burst has no colour of its own: transform and custom data.
const SPARK_STRIDE := 12
# THE SHADERS ARE WARMED BY shaderwarm.gd (0.156.0): every look the game
# draws, as the first area of a session arrives. This drew its own - a pool,
# a tinted spike, a ring and a burst - since 0.137.5 (the first cast of a
# session was 106 and 176 ms frames with the driver's cache empty).

# This container's clock: the spikes' warnings and the sparks' flights are
# timed on it, by the frame's delta as each spike used to time its own.
var now: float = 0.0

var _rings: MultiMeshInstance2D = null
var _ring_mat: ShaderMaterial = null
# Untyped, so a spike freed without leaving can still be read and dropped.
var _ring_spikes: Array = []
var _ring_end: Array[float] = []
var _ring_buf := PackedFloat32Array()
var _slot_of: Dictionary = {}
# Spikes whose place is written at the next flush: one is placed after it is
# added (bossenemy.gd _spawn_one_eruption()), so not at add_ring().
var _unplaced: Array = []
var _rings_changed: bool = false

var _sparks: MultiMeshInstance2D = null
var _spark_mat: ShaderMaterial = null
var _spark_buf := PackedFloat32Array()
var _spark_end: Array[float] = []
var _sparks_changed: bool = false
# A burst's own number (0-127), so its sparks are rolled the same wherever it
# moves in the buffer.
var _burst_no: int = 0
var _motion: Array = []
var _shape: Array = []
var _tint: Array = []
var _known: Dictionary = {}

# SEE-THROUGH IN FRONT OF YOU (0.149.0). The owner, of a boss's spikes
# standing round his warrior: "character is behind wall". A spike lower on
# the screen than the player is drawn over them (the world's y-sort), so a
# ring of them was a wall nobody could see through. While a spike stands
# (stand(), from its eruption) and covers this game's player, its picture
# eases to SEE_THROUGH; clear of them, back to whole. Only its picture: the
# hit is the spike's, as it was. Here, once a frame for every spike, so a
# spike still has no _process of its own.
const SEE_THROUGH := 0.35
# Alpha a second, so a spike fades in a few frames rather than blinking.
const FADE_RATE := 8.0
# What a spike's picture covers from its foot, at scale 1 (boss.png's rise,
# frames 1-2: about 40 px wide, 44 px up from where it stands).
const SPIKE_HALF_WIDTH := 20.0
const SPIKE_HEIGHT := 44.0
# What a player's picture covers from where it stands (the warrior's frames:
# its sprite sits 13 px down and 16 up, so the feet are 13 px below the
# origin), and where the y-sort reads it - its sprite, at the feet.
const PLAYER_BOX := Rect2(-17.0, -22.0, 32.0, 35.0)
const PLAYER_FEET := 13.0
# Untyped, as _ring_spikes: one freed while standing is dropped at the next look.
var _standing: Array = []
# Whose picture the spikes keep clear of: the suite's stand-in, or null for
# this game's player (the "player" group).
var see_for: Node2D = null


static func add_to(scene: Node) -> Node2D:
	"""The area's: in its effects container (ysortworld/groundeffects), made
	if there is none."""
	if scene == null:
		return null
	var container: Node = scene.get_node_or_null(^"ysortworld/groundeffects")
	if container == null:
		return null
	return of(container)


static func of(container: Node) -> Node2D:
	"""The one in `container`, made if it has none."""
	if container == null:
		return null
	var had: Variant = container.get_meta(META) if container.has_meta(META) else null
	if is_instance_valid(had) and had is Node2D and (had as Node).get_parent() == container:
		return had as Node2D
	var fx := (load("res://src/projectiles/spikefx.gd") as GDScript).new() as Node2D
	fx.name = NODE_NAME
	container.set_meta(META, fx)
	container.add_child(fx)
	container.move_child(fx, 0)
	return fx


func _ready() -> void:
	position = Vector2(0.0, SORT_Y)
	reset_physics_interpolation()
	_rings = _make_mesh("rings", _ring_mesh(), RING_SHADER, true)
	_ring_mat = _rings.material as ShaderMaterial
	_sparks = _make_mesh("sparks", _spark_mesh(), SPARK_SHADER, false)
	_sparks.z_index = 1
	_spark_mat = _sparks.material as ShaderMaterial
	for i in ELEMENTS:
		_motion.append(Vector4.ZERO)
		_shape.append(Vector4.ZERO)
		_tint.append(Vector4.ZERO)
	# The GM panel's lag tests hide what they say (lagtests.gd).
	add_to_group(LagTests.GROUP)
	show_tests()
	set_process(not _ring_spikes.is_empty() or not _spark_end.is_empty())


func _make_mesh(mesh_name: String, mesh: ArrayMesh, shader: Shader, colours: bool) -> MultiMeshInstance2D:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_2D
	multi.use_colors = colours
	multi.use_custom_data = true
	multi.mesh = mesh
	multi.instance_count = 0
	# Drawn wherever it is on screen: a MultiMesh filled through its buffer
	# keeps the bounds it had (swarm.gd set_arena()).
	multi.custom_aabb = AABB(Vector3(-1.0e6, -1.0e6, -1.0), Vector3(2.0e6, 2.0e6, 2.0))
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var made := MultiMeshInstance2D.new()
	made.name = mesh_name
	made.multimesh = multi
	made.material = mat
	# Drawn where they are written: nothing here moves between two buffers,
	# and an instance is a different spike from one write to the next (as
	# swarm.gd's, 0.93.5).
	made.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	RenderingServer.multimesh_set_physics_interpolated(multi.get_rid(), false)
	add_child(made)
	return made


func _ring_mesh() -> ArrayMesh:
	# The fill: a fan of unit directions from the middle (UV.x 0). The
	# outline: four circles of them (UV.x 1), UV.y each one's distance from
	# the radius, the outer two with no alpha - the soft edge.
	var points := PackedVector2Array()
	var uvs := PackedVector2Array()
	var colours := PackedColorArray()
	var index := PackedInt32Array()
	points.append(Vector2.ZERO)
	uvs.append(Vector2.ZERO)
	colours.append(Color.WHITE)
	for i in FILL_POINTS:
		points.append(Vector2.from_angle(TAU * i / FILL_POINTS))
		uvs.append(Vector2.ZERO)
		colours.append(Color.WHITE)
		index.append_array([0, 1 + i, 1 + (i + 1) % FILL_POINTS])
	var start: int = points.size()
	var offsets: Array = [-RING_HALF - FEATHER, -RING_HALF, RING_HALF, RING_HALF + FEATHER]
	var alphas: Array = [0.0, 1.0, 1.0, 0.0]
	for i in RING_POINTS:
		var way := Vector2.from_angle(TAU * i / RING_POINTS)
		for k in 4:
			points.append(way)
			uvs.append(Vector2(1.0, float(offsets[k])))
			colours.append(Color(1.0, 1.0, 1.0, float(alphas[k])))
	for i in RING_POINTS:
		var a: int = start + i * 4
		var b: int = start + ((i + 1) % RING_POINTS) * 4
		for k in 3:
			index.append_array([a + k, b + k, b + k + 1, a + k, b + k + 1, a + k + 1])
	return _mesh_of(points, uvs, colours, index)


func _spark_mesh() -> ArrayMesh:
	# A unit quad a spark, UV.x its number.
	var points := PackedVector2Array()
	var uvs := PackedVector2Array()
	var colours := PackedColorArray()
	var index := PackedInt32Array()
	for i in BURST_QUADS:
		var a: int = points.size()
		for corner in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]:
			points.append(corner)
			uvs.append(Vector2(float(i), 0.0))
			colours.append(Color.WHITE)
		index.append_array([a, a + 1, a + 2, a, a + 2, a + 3])
	return _mesh_of(points, uvs, colours, index)


static func _mesh_of(points: PackedVector2Array, uvs: PackedVector2Array,
		colours: PackedColorArray, index: PackedInt32Array) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_INDEX] = index
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# =============================================================================
# THE RINGS
# =============================================================================

func add_ring(spike: Node2D, telegraph: float, radius: float, colour: Color) -> void:
	"""`spike` warns from now for `telegraph` seconds; when that is up this
	calls its telegraph_over(). Placed where it stands at the next flush."""
	var id: int = spike.get_instance_id()
	if _slot_of.has(id):
		return
	var i: int = _ring_spikes.size()
	_ring_spikes.append(spike)
	_ring_end.append(now + telegraph)
	_slot_of[id] = i
	if _ring_buf.size() < (i + 1) * RING_STRIDE:
		_ring_buf.resize(maxi(ROOM, (i + 1) * 2) * RING_STRIDE)
	var o: int = i * RING_STRIDE
	for k in 8:
		_ring_buf[o + k] = 0.0
	_ring_buf[o + 8] = colour.r
	_ring_buf[o + 9] = colour.g
	_ring_buf[o + 10] = colour.b
	_ring_buf[o + 11] = colour.a
	_ring_buf[o + 12] = fposmod(now, WRAP)
	_ring_buf[o + 13] = telegraph
	_ring_buf[o + 14] = radius
	_ring_buf[o + 15] = 0.0
	_unplaced.append(spike)
	_rings_changed = true
	set_process(true)


func remove_ring(spike: Node) -> void:
	"""`spike` warns no longer (it erupted, or went)."""
	var id: int = spike.get_instance_id()
	if not _slot_of.has(id):
		return
	_remove_ring_at(int(_slot_of[id]))


func warning_count() -> int:
	return _ring_spikes.size()


func _remove_ring_at(i: int) -> void:
	var gone: Variant = _ring_spikes[i]
	if is_instance_valid(gone):
		_slot_of.erase((gone as Object).get_instance_id())
		_unplaced.erase(gone)
	else:
		_slot_of.erase(_id_at(i))
	var last: int = _ring_spikes.size() - 1
	if i != last:
		var moved: Variant = _ring_spikes[last]
		_ring_spikes[i] = moved
		_ring_end[i] = _ring_end[last]
		var o: int = i * RING_STRIDE
		var from: int = last * RING_STRIDE
		for k in RING_STRIDE:
			_ring_buf[o + k] = _ring_buf[from + k]
		_slot_of[(moved as Object).get_instance_id() if is_instance_valid(moved) else _id_at(last)] = i
	_ring_spikes.pop_back()
	_ring_end.pop_back()
	_rings_changed = true


func _id_at(i: int) -> int:
	# A spike freed without saying so: find its id by its slot.
	for id in _slot_of:
		if int(_slot_of[id]) == i:
			return int(id)
	return 0


# =============================================================================
# THE SPARKS
# =============================================================================

func burst(at: Vector2, element: int, patch: Vector2, numbers: Dictionary) -> void:
	"""A burst of `element`'s sparks from a patch `patch` either side of `at`
	(global), with bossprojectile.gd's ELEMENT_SPARKS row `numbers`."""
	if element <= 0 or element >= ELEMENTS:
		return
	_learn(element, numbers)
	var i: int = _spark_end.size()
	if _spark_buf.size() < (i + 1) * SPARK_STRIDE:
		_spark_buf.resize(maxi(ROOM, (i + 1) * 2) * SPARK_STRIDE)
	var o: int = i * SPARK_STRIDE
	var here: Vector2 = to_local(at)
	_spark_buf[o] = 1.0
	_spark_buf[o + 1] = 0.0
	_spark_buf[o + 2] = 0.0
	_spark_buf[o + 3] = here.x
	_spark_buf[o + 4] = 0.0
	_spark_buf[o + 5] = 1.0
	_spark_buf[o + 6] = 0.0
	_spark_buf[o + 7] = here.y
	_spark_buf[o + 8] = fposmod(now, WRAP)
	# The element and the burst's number in one (exact in a half float).
	_spark_buf[o + 9] = float(element + 16 * _burst_no)
	_burst_no = (_burst_no + 1) % 128
	_spark_buf[o + 10] = patch.x
	_spark_buf[o + 11] = patch.y
	_spark_end.append(now + float(numbers.get("life", 0.5)))
	_sparks_changed = true
	set_process(true)


func bursts_alive() -> int:
	return _spark_end.size()


func _spend_bursts() -> void:
	# A burst whose sparks are spent goes; the last takes its place.
	var i: int = _spark_end.size() - 1
	while i >= 0:
		if _spark_end[i] <= now:
			var last: int = _spark_end.size() - 1
			if i != last:
				_spark_end[i] = _spark_end[last]
				var o: int = i * SPARK_STRIDE
				var from: int = last * SPARK_STRIDE
				for k in SPARK_STRIDE:
					_spark_buf[o + k] = _spark_buf[from + k]
			_spark_end.pop_back()
			_sparks_changed = true
		i -= 1


func _learn(element: int, numbers: Dictionary) -> void:
	if _known.has(element) or _spark_mat == null:
		return
	_known[element] = true
	var gravity: Vector2 = numbers.get("gravity", Vector2.ZERO)
	_motion[element] = Vector4(gravity.x, gravity.y, float(numbers.get("vmin", 0.0)), float(numbers.get("vmax", 0.0)))
	_shape[element] = Vector4(float(numbers.get("smin", 1.0)), float(numbers.get("smax", 1.0)),
		float(numbers.get("life", 0.5)), deg_to_rad(float(numbers.get("spread", 0.0))))
	var colour: Color = Element.colour_for(element)
	_tint[element] = Vector4(colour.r, colour.g, colour.b, float(mini(int(numbers.get("count", 0)), BURST_QUADS)))
	_spark_mat.set_shader_parameter(&"motion", _motion)
	_spark_mat.set_shader_parameter(&"shape", _shape)
	_spark_mat.set_shader_parameter(&"tint", _tint)


# =============================================================================
# THE POOLS
# =============================================================================

func puddles_for(element: int) -> Node2D:
	"""Where a spike's pool of `element` goes: under the rings, beside the
	others of its element."""
	var holder_name := "puddles_%d" % element
	var holder: Node2D = get_node_or_null(NodePath(holder_name)) as Node2D
	if holder == null:
		holder = Node2D.new()
		holder.name = holder_name
		holder.visible = not LagTests.hide_pools
		add_child(holder)
		move_child(holder, 0)
	return holder


# THE ECLIPSE LIFTS THE RINGS (0.139.0): the Light Keeper's dark is drawn at
# z 15 (lightarena.gd), over everything standing; a spike's warning has to be
# seen in it, so while it falls the rings are drawn just above it.
const RINGS_LIFTED_Z := 16


func lift_rings(up: bool) -> void:
	"""The rings over the eclipse's dark (`up`), or back among the floor."""
	if _rings == null:
		return
	_rings.z_as_relative = not up
	_rings.z_index = RINGS_LIFTED_Z if up else 0


func show_tests() -> void:
	"""Rings, sparks and pools drawn or not as the GM panel's lag tests say
	(lagtests.gd). Only drawing: the spikes still warn, rise and hit."""
	if _rings != null:
		_rings.visible = not LagTests.hide_rings
	if _sparks != null:
		_sparks.visible = not LagTests.hide_sparks
	for child in get_children():
		if str(child.name).begins_with("puddles_"):
			(child as CanvasItem).visible = not LagTests.hide_pools
	# The spikes standing now ("Spikes", 0.150.0); one rising later reads it.
	for spike in _standing:
		if is_instance_valid(spike):
			var sprite: CanvasItem = (spike as Node).get(&"anim") as CanvasItem
			if sprite != null:
				sprite.visible = not LagTests.hide_spikes


static func pool_holder(container: Node, element: int) -> Node:
	"""puddles_for() of `container`'s, or `container` itself if it cannot
	have one."""
	var fx: Node2D = of(container)
	return fx.call(&"puddles_for", element) if fx != null else container


# =============================================================================
# EACH FRAME
# =============================================================================

func _process(delta: float) -> void:
	now += delta
	# The warnings that are up: each spike erupts (and leaves the rings).
	var i: int = _ring_spikes.size() - 1
	while i >= 0:
		if i < _ring_spikes.size() and now >= _ring_end[i]:
			var spike: Variant = _ring_spikes[i]
			if is_instance_valid(spike):
				if (spike as Node).has_method(&"telegraph_over"):
					(spike as Node).call(&"telegraph_over")
				# If it did not leave the rings itself.
				remove_ring(spike as Node)
			else:
				_remove_ring_at(i)
		i -= 1
	_spend_bursts()
	_flush()
	_see_through(delta)
	var clock: float = fposmod(now, WRAP)
	_ring_mat.set_shader_parameter(&"now_mod", clock)
	_spark_mat.set_shader_parameter(&"now_mod", clock)
	if _ring_spikes.is_empty() and _spark_end.is_empty() and _standing.is_empty():
		set_process(false)


func stand(spike: Node2D) -> void:
	"""`spike` has erupted and stands until it goes: faded while it covers
	this game's player (SEE-THROUGH IN FRONT OF YOU)."""
	_standing.append(spike)
	set_process(true)


func standing_count() -> int:
	return _standing.size()


static func covers(spike_at: Vector2, spike_scale: float, player_at: Vector2) -> bool:
	"""Whether a spike standing at `spike_at` is drawn over a player at
	`player_at`: in front of them (lower on the screen, so the y-sort draws it
	after) and over their picture."""
	if spike_at.y <= player_at.y + PLAYER_FEET:
		return false
	var half: float = SPIKE_HALF_WIDTH * spike_scale
	var tall: float = SPIKE_HEIGHT * spike_scale
	var spike_box := Rect2(spike_at.x - half, spike_at.y - tall, half * 2.0, tall)
	return spike_box.intersects(Rect2(player_at + PLAYER_BOX.position, PLAYER_BOX.size))


func _see_through(delta: float) -> void:
	if _standing.is_empty():
		return
	var me: Node2D = see_for
	if me == null and is_inside_tree():
		me = get_tree().get_first_node_in_group(&"player") as Node2D
	var step: float = FADE_RATE * delta
	var i: int = _standing.size() - 1
	while i >= 0:
		var spike: Variant = _standing[i]
		if not is_instance_valid(spike) or (spike as Node).is_queued_for_deletion():
			_standing.remove_at(i)
			i -= 1
			continue
		var sprite: CanvasItem = (spike as Node).get(&"anim") as CanvasItem
		if sprite != null:
			var at: Vector2 = (spike as Node2D).global_position
			var want: float = SEE_THROUGH if me != null \
				and covers(at, absf((spike as Node2D).global_scale.y), me.global_position) else 1.0
			var colour: Color = sprite.modulate
			if colour.a != want:
				colour.a = move_toward(colour.a, want, step)
				sprite.modulate = colour
		i -= 1


func _place(slot: int, t: Transform2D) -> void:
	var o: int = slot * RING_STRIDE
	_ring_buf[o] = t.x.x
	_ring_buf[o + 1] = t.y.x
	_ring_buf[o + 2] = 0.0
	_ring_buf[o + 3] = t.origin.x
	_ring_buf[o + 4] = t.x.y
	_ring_buf[o + 5] = t.y.y
	_ring_buf[o + 6] = 0.0
	_ring_buf[o + 7] = t.origin.y


func _flush() -> void:
	if not _unplaced.is_empty():
		var inverse: Transform2D = global_transform.affine_inverse()
		for k in _unplaced.size():
			var spike: Variant = _unplaced[k]
			if not is_instance_valid(spike) or not _slot_of.has((spike as Object).get_instance_id()):
				continue
			_place(int(_slot_of[(spike as Object).get_instance_id()]), inverse * (spike as Node2D).global_transform)
		_unplaced.clear()
		_rings_changed = true
	if _rings_changed:
		_rings_changed = false
		var multi: MultiMesh = _rings.multimesh
		var room: int = int(_ring_buf.size() / float(RING_STRIDE))
		if multi.instance_count != room:
			multi.instance_count = room
		multi.buffer = _ring_buf
		multi.visible_instance_count = _ring_spikes.size()
	if _sparks_changed:
		_sparks_changed = false
		var multi: MultiMesh = _sparks.multimesh
		var room: int = int(_spark_buf.size() / float(SPARK_STRIDE))
		if multi.instance_count != room:
			multi.instance_count = room
		multi.buffer = _spark_buf
		multi.visible_instance_count = _spark_end.size()
