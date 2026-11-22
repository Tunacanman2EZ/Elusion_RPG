# fxparticles.gd - every particle cloud of a viewport drawn together, a draw a
# layer, worked out on the card (0.174.4).
#
# The owner, of his card's Every effect sweep: "we need to majorly refine
# mages meteor and mages spike and dynamite". Measured on his card (zz bench
# v16), firing them steadily in the Testing Ground: meteors 20 a second kept
# 500 CPUParticles2D going at once, mage spikes 40 a second 368, dynamite 60
# a second 634 - each worked out by the processor, sent to the card and drawn
# on its own every frame - and hiding them took 3.1 to 3.7 ms off the
# drawing, about half of it.
#
# HOW. An effect makes an fxemitter.gd where it made a CPUParticles2D. The
# emitter joins the drawer of its viewport (of(), made on first use) and
# takes a slot in its LAYER's MultiMesh - a layer is the emitters of one z
# index, texture and lighting - and nothing more happens to it until it
# moves, shows or hides, or starts or stops: its transform, when it began and
# stopped, its seed and its rows are written to its slot then, and
# fxparticles.gdshader works out every particle from them and the clock
# (`now`). What a cloud's numbers are - amount, lifetime, shape, speeds,
# gravity, orbit, sizes - is a row of `params`, and its colours and scale
# curve rows of `ramps`; clouds alike share rows, so the textures change
# when a new kind of cloud first appears.
#
# A cloud left behind in the world (local_coords off) is drawn from where its
# emitter is now, less how fast it is moving times each particle's age: a
# falling meteor's trail stays behind it, straight back along its fall.
#
# Drawn in one MultiMesh per layer through meshring.gd, so the browser sees
# a count that changes only in steps. No class_name: preload it by path.
extends Node2D

const MeshRing := preload("res://src/shared/meshring.gd")
const FxEmitter := preload("res://src/shared/fxemitter.gd")
const SHADER := preload("res://src/shared/fxparticles.gdshader")
# The same, drawn unshaded (a CanvasItemMaterial's LIGHT_MODE_UNSHADED).
const UNSHADED_SHADER := preload("res://src/shared/fxparticles_unshaded.gdshader")
const NODE_NAME := "fxparticles"
const META := &"fx_particles"
# The most particles a cloud draws (the quads of the mesh): the most any
# effect asks for is a meteor's pulling swirl's 64.
const MOST := 64
# Floats an emitter's slot takes: transform 8, colour 4, custom 4.
const STRIDE := 16
const PARAM_WIDTH := 8
const RAMP_WIDTH := 32
# Rows kept before they are all written again: a cloud whose numbers change
# as it goes (a meteor's ring of fire narrowing) takes a new row each time,
# and rows nobody uses any more are only let go this way.
const MOST_ROWS := 512
# The faded-by-a-parent are looked at one in FADE_TURNS a frame.
const FADE_TURNS := 4
# Rows the textures start with: what a fight's clouds take, so they are not
# made bigger (a new texture on the card) in the middle of one.
const FIRST_ROWS := 64
# A layer is closed up (_close_up()) once it has this many slots and half of
# them are free.
const CLOSE_UP_FROM := 32

# The clock every particle is worked out on, in seconds.
var now: float = 0.0
# Layers by key: {"mmi", "mat", "ring", "buffer", "emitters" (by slot),
# "free" (how many slots under "high" are empty), "high", "dirty"}.
var _groups: Dictionary = {}
# Emitters faded by a parent (follow_fades): their alpha read in turns.
var _fading: Array = []
var _fade_turn: int = 0
# Emitters joined since the last frame, in the order they were made: their
# slots taken in that order (_take()).
var _joining: Array = []
var _params_image: Image = null
var _params_texture: ImageTexture = null
var _params_rows: Dictionary = {}
var _params_dirty: bool = false
var _ramps_image: Image = null
var _ramps_texture: ImageTexture = null
var _ramp_rows: Dictionary = {}
# A ramp's or curve's row by what it is (bytes of its stops), so one made
# again is not sampled again.
var _ramp_keys: Dictionary = {}
var _ramps_dirty: bool = false
var _touched: Dictionary = {}
var _moving: Dictionary = {}
var _mesh: ArrayMesh = null
var _rng := RandomNumberGenerator.new()
# How many emitters, for the suite and the readout.
var emitters: int = 0
# How many times every row was let go (MOST_ROWS), for the suite.
var rows_started_again: int = 0
# How many times an emitter was written, for the suite.
var writes: int = 0
var _rows_full: bool = false


static func of(node: Node) -> Node:
	"""The drawer of `node`'s viewport, made if it has none: in the current
	scene for the game's own view, in the viewport itself for a SubViewport's
	world."""
	if node == null or not node.is_inside_tree():
		return null
	var view: Viewport = node.get_viewport()
	var holder: Node = view
	if view == node.get_tree().root:
		holder = node.get_tree().current_scene if node.get_tree().current_scene != null else view
	var had: Variant = holder.get_meta(META) if holder.has_meta(META) else null
	# Made this frame and not in the tree yet is still the one.
	if is_instance_valid(had) and had is Node and not (had as Node).is_queued_for_deletion():
		return had as Node
	var drawer: Node2D = (load("res://src/shared/fxparticles.gd") as GDScript).new()
	drawer.name = NODE_NAME
	holder.set_meta(META, drawer)
	holder.add_child.call_deferred(drawer)
	return drawer


func _init() -> void:
	# At the world's origin whatever it is under: the shader reads the
	# emitter's transform as the instance's alone.
	top_level = true
	_rng.randomize()
	_params_image = Image.create(PARAM_WIDTH, FIRST_ROWS, false, Image.FORMAT_RGBAF)
	_params_texture = ImageTexture.create_from_image(_params_image)
	_ramps_image = Image.create(RAMP_WIDTH, FIRST_ROWS, false, Image.FORMAT_RGBA8)
	_ramps_texture = ImageTexture.create_from_image(_ramps_image)
	_mesh = _quads()


func _ready() -> void:
	position = Vector2.ZERO
	reset_physics_interpolation()


func _quads() -> ArrayMesh:
	# MOST quads; UV.x the particle's number plus the corner's x (0 or
	# 0.999), UV.y the corner's y. Where each corner is, the shader says.
	var points := PackedVector2Array()
	var uvs := PackedVector2Array()
	var colours := PackedColorArray()
	var index := PackedInt32Array()
	for i in MOST:
		var at: int = points.size()
		for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
			points.append(Vector2.ZERO)
			uvs.append(Vector2(float(i) + corner.x * 0.999, corner.y))
			colours.append(Color.WHITE)
		index.append_array([at, at + 1, at + 2, at, at + 2, at + 3])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_INDEX] = index
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# ---- what an emitter tells it ------------------------------------------------

func add(e: FxEmitter) -> void:
	"""It joins: a slot in its layer at its first write, this frame's end -
	by then whoever made it has set its z index, texture and material."""
	e.fx_slot = -1
	e.fx_group = ""
	e.fx_seed = _rng.randi_range(0, 2047)
	e.fx_t0 = now
	e.fx_t1 = 1.0e9 if e.emitting else now - 1000.0
	e.fx_params_dirty = true
	e.fx_key_dirty = true
	e.fx_alpha = -1.0
	e.fx_was = e.global_position
	if e.fx_glide_pending:
		# Asked to glide before it joined: its start on this clock.
		e.fx_glide_pending = false
		e.fx_glide_start = now + e.fx_glide_start
	emitters += 1
	_joining.append(e)
	_touched[e] = true
	if e.follow_fades:
		_fading.append(e)
	set_process(true)


func remove(e: FxEmitter) -> void:
	_let_go(e)
	_touched.erase(e)
	_moving.erase(e)
	_fading.erase(e)
	emitters -= 1


func _let_go(e: FxEmitter) -> void:
	"""Its slot in its layer back: drawn nowhere until it takes another."""
	var key: String = e.fx_group
	var slot: int = e.fx_slot
	e.fx_slot = -1
	e.fx_group = ""
	if not _groups.has(key) or slot < 0:
		return
	var group: Dictionary = _groups[key]
	var buffer: PackedFloat32Array = group["buffer"]
	group["buffer"] = PackedFloat32Array()
	for k in STRIDE:
		buffer[slot * STRIDE + k] = 0.0
	group["buffer"] = buffer
	(group["emitters"] as Array)[slot] = null
	group["free"] = int(group["free"]) + 1
	group["dirty"] = true
	if int(group["free"]) * 2 >= int(group["high"]) and int(group["high"]) >= CLOSE_UP_FROM:
		_close_up(group)


func _take(e: FxEmitter, key: String) -> void:
	"""The next slot in the layer `key`. ALWAYS AFTER EVERY OTHER: a layer is
	drawn in slot order, and an effect's clouds are drawn in the order they
	were made, as siblings are (a blast's smoke behind its fire) - a freed
	slot is never handed out again until the layer closes up (_close_up())."""
	var group: Dictionary = _group(key, e)
	var slot: int = int(group["high"])
	group["high"] = slot + 1
	var buffer: PackedFloat32Array = group["buffer"]
	if buffer.size() < (slot + 1) * STRIDE:
		group["buffer"] = PackedFloat32Array()
		buffer.resize(maxi(STRIDE * 16, buffer.size() * 2))
		group["buffer"] = buffer
	var held: Array = group["emitters"]
	if held.size() < slot + 1:
		held.resize(maxi(16, held.size() * 2))
	held[slot] = e
	e.fx_group = key
	e.fx_slot = slot
	e.fx_key_dirty = false


func _close_up(group: Dictionary) -> void:
	"""The layer's emitters moved down over its freed slots, in the order
	they were: once half its slots are free."""
	var held: Array = group["emitters"]
	var buffer: PackedFloat32Array = group["buffer"]
	group["buffer"] = PackedFloat32Array()
	var high: int = int(group["high"])
	var to: int = 0
	for slot in high:
		var e: Variant = held[slot]
		if e == null or not is_instance_valid(e):
			held[slot] = null
			continue
		if to != slot:
			for k in STRIDE:
				buffer[to * STRIDE + k] = buffer[slot * STRIDE + k]
			held[to] = e
			held[slot] = null
			(e as FxEmitter).fx_slot = to
		to += 1
	for k in range(to * STRIDE, high * STRIDE):
		buffer[k] = 0.0
	group["buffer"] = buffer
	group["high"] = to
	group["free"] = 0
	group["dirty"] = true


func moved(e: FxEmitter) -> void:
	_moving[e] = true


func touched(e: FxEmitter) -> void:
	_touched[e] = true


func emitting_changed(e: FxEmitter) -> void:
	if e.emitting:
		e.fx_t0 = now
		e.fx_t1 = 1.0e9
	elif e.fx_t0 >= now:
		# Stopped the moment it started (made, then told to wait): nothing
		# came out, as a CPUParticles2D emits nothing before its first frame.
		e.fx_t1 = now - 1000.0
	else:
		e.fx_t1 = now
	_touched[e] = true


# ---- each frame -----------------------------------------------------------------

func _process(delta: float) -> void:
	now += delta
	if _rows_full:
		_start_rows_again()
	for e in _joining:
		if is_instance_valid(e) and (e as FxEmitter).fx_drawer == self and (e as FxEmitter).fx_slot < 0:
			_take(e as FxEmitter, _key_for(e as FxEmitter))
	_joining.clear()
	# Movers: where they are now and how fast they went; one still since the
	# last frame is written once more, standing.
	var still: Array = []
	for e in _moving:
		if not is_instance_valid(e):
			still.append(e)
			continue
		var f: FxEmitter = e as FxEmitter
		var at: Vector2 = f.global_position
		var was: Vector2 = f.fx_was
		f.fx_was = at
		_write(f, (at - was) / maxf(delta, 0.0001))
		if at == was:
			still.append(e)
	for e in still:
		_moving.erase(e)
	# Faded by a parent: a quarter of them looked at a frame (FADE_TURNS),
	# each written when its alpha has moved.
	if not _fading.is_empty():
		_fade_turn = (_fade_turn + 1) % FADE_TURNS
		var gone: bool = false
		for i in range(_fade_turn, _fading.size(), FADE_TURNS):
			var e: Variant = _fading[i]
			if not is_instance_valid(e):
				gone = true
				continue
			var f: FxEmitter = e as FxEmitter
			if not _moving.has(f) and not is_equal_approx(_alpha_of(f), f.fx_alpha):
				_touched[f] = true
		if gone:
			_fading = _fading.filter(func(x: Variant) -> bool: return is_instance_valid(x))
	for e in _touched:
		if is_instance_valid(e) and not _moving.has(e):
			_write(e as FxEmitter, Vector2.ZERO)
	_touched.clear()
	if _params_dirty:
		_params_dirty = false
		if _params_texture.get_size() == Vector2(_params_image.get_size()):
			_params_texture.update(_params_image)
		else:
			_params_texture.set_image(_params_image)
	if _ramps_dirty:
		_ramps_dirty = false
		if _ramps_texture.get_size() == Vector2(_ramps_image.get_size()):
			_ramps_texture.update(_ramps_image)
		else:
			_ramps_texture.set_image(_ramps_image)
	for key in _groups:
		var group: Dictionary = _groups[key]
		(group["mat"] as ShaderMaterial).set_shader_parameter(&"now", now)
		if bool(group["dirty"]):
			group["dirty"] = false
			(group["ring"] as MeshRing).send(group["buffer"], int(group["high"]))
	if emitters <= 0 and _moving.is_empty():
		set_process(false)


func _write(e: FxEmitter, velocity: Vector2) -> void:
	if e.fx_key_dirty:
		# In the layer of its z index, texture and lighting as they are now.
		e.fx_key_dirty = false
		var want: String = _key_for(e)
		if want != e.fx_group:
			_let_go(e)
			_take(e, want)
	var key: String = e.fx_group
	if not _groups.has(key):
		return
	writes += 1
	if e.fx_params_dirty:
		_rows_for(e)
	var group: Dictionary = _groups[key]
	# Taken out while written, so the array is not copied for the write.
	var buffer: PackedFloat32Array = group["buffer"]
	group["buffer"] = PackedFloat32Array()
	var o: int = e.fx_slot * STRIDE
	var xf: Transform2D = e.get_global_transform()
	var alpha: float = _alpha_of(e)
	e.fx_alpha = alpha
	buffer[o] = xf.x.x
	buffer[o + 1] = xf.y.x
	buffer[o + 2] = e.fx_t0
	buffer[o + 3] = xf.origin.x
	buffer[o + 4] = xf.x.y
	buffer[o + 5] = xf.y.y
	buffer[o + 6] = e.fx_t1
	buffer[o + 7] = xf.origin.y
	buffer[o + 8] = velocity.x
	buffer[o + 9] = velocity.y
	# A glide's start, from when it began emitting (a small number: the
	# colour is sent at half precision).
	buffer[o + 10] = e.fx_glide_start - e.fx_t0 if e.glide_seconds > 0.0 else 0.0
	buffer[o + 11] = alpha
	buffer[o + 12] = float(e.fx_seed)
	buffer[o + 13] = float(e.fx_row)
	buffer[o + 14] = float(e.fx_ramp)
	buffer[o + 15] = float(e.fx_curve)
	group["buffer"] = buffer
	group["dirty"] = true


static func _alpha_of(e: Node2D) -> float:
	"""How opaque it is drawn: its own and every parent's modulate, as a
	CanvasItem's is; nothing while hidden."""
	if not e.is_visible_in_tree():
		return 0.0
	var a: float = e.self_modulate.a
	var at: Node = e
	while at is CanvasItem:
		a *= (at as CanvasItem).modulate.a
		at = at.get_parent()
	return a


# ---- layers ------------------------------------------------------------------------

func _key_for(e: FxEmitter) -> String:
	var tex: Texture2D = e.texture
	return "%d|%d|%d" % [_z_of(e), tex.get_instance_id() if tex != null else 0, 1 if e.unshaded() else 0]


static func _z_of(node: Node) -> int:
	"""The z index it is drawn at: its own, and its parents' while relative."""
	var z: int = 0
	var at: Node = node
	while at is CanvasItem:
		z += (at as CanvasItem).z_index
		if not (at as CanvasItem).z_as_relative:
			break
		at = at.get_parent()
	return clampi(z, RenderingServer.CANVAS_ITEM_Z_MIN, RenderingServer.CANVAS_ITEM_Z_MAX)


func _group(key: String, e: FxEmitter) -> Dictionary:
	if _groups.has(key):
		return _groups[key]
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_2D
	multi.use_colors = true
	multi.use_custom_data = true
	multi.mesh = _mesh
	multi.instance_count = 0
	multi.custom_aabb = AABB(Vector3(-1.0e6, -1.0e6, -1.0), Vector3(2.0e6, 2.0e6, 2.0))
	var mat := ShaderMaterial.new()
	mat.shader = UNSHADED_SHADER if e.unshaded() else SHADER
	mat.set_shader_parameter(&"params", _params_texture)
	mat.set_shader_parameter(&"ramps", _ramps_texture)
	var tex: Texture2D = e.texture
	mat.set_shader_parameter(&"textured", tex != null)
	mat.set_shader_parameter(&"tex_size", tex.get_size() if tex != null else Vector2.ONE)
	var mmi := MultiMeshInstance2D.new()
	mmi.name = "layer_%d" % _groups.size()
	mmi.multimesh = multi
	mmi.material = mat
	mmi.texture = tex
	mmi.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mmi.z_as_relative = false
	mmi.z_index = _z_of(e)
	# Written where they are: nothing here is blended between two buffers.
	mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	RenderingServer.multimesh_set_physics_interpolated(multi.get_rid(), false)
	add_child(mmi)
	var ring := MeshRing.new()
	ring.wear(mmi, STRIDE)
	var group: Dictionary = {"mmi": mmi, "mat": mat, "ring": ring, "buffer": PackedFloat32Array(),
		"emitters": [], "free": 0, "high": 0, "dirty": false}
	_groups[key] = group
	return group


# ---- rows --------------------------------------------------------------------------

func _rows_for(e: FxEmitter) -> void:
	e.fx_params_dirty = false
	var initial_row: int = _ramp_row(e.color_initial_ramp) if e.color_initial_ramp != null else -1
	var curve_row: int = _curve_row(e.scale_amount_curve) if e.scale_amount_curve != null else -1
	var numbers: PackedFloat32Array = e.fx_numbers(MOST)
	numbers[25] = 1.0 if initial_row >= 0 else 0.0
	numbers[26] = float(maxi(initial_row, 0))
	numbers[27] = 1.0 if curve_row >= 0 else 0.0
	e.fx_row = _param_row(numbers)
	e.fx_ramp = _ramp_row(e.color_ramp)
	e.fx_curve = curve_row


func _param_row(numbers: PackedFloat32Array) -> int:
	var key: PackedByteArray = numbers.to_byte_array()
	if _params_rows.has(key):
		return int(_params_rows[key])
	if _params_rows.size() >= MOST_ROWS:
		_rows_full = true
	var row: int = _params_rows.size()
	if row >= _params_image.get_height():
		var bigger := Image.create(PARAM_WIDTH, _params_image.get_height() * 2, false, Image.FORMAT_RGBAF)
		bigger.blit_rect(_params_image, Rect2i(Vector2i.ZERO, _params_image.get_size()), Vector2i.ZERO)
		_params_image = bigger
	for k in PARAM_WIDTH:
		_params_image.set_pixel(k, row, Color(numbers[k * 4], numbers[k * 4 + 1], numbers[k * 4 + 2], numbers[k * 4 + 3]))
	_params_rows[key] = row
	_params_dirty = true
	return row


func _ramp_row(ramp: Gradient) -> int:
	"""A colour ramp's row (none: white all its life). Found by what the ramp
	is - its stops, colours and blending, as bytes - so a blast's ramps, made
	new for every blast, are sampled once."""
	var key := PackedByteArray([0])
	if ramp != null:
		key = ramp.offsets.to_byte_array()
		key.append_array(ramp.colors.to_byte_array())
		key.append(int(ramp.interpolation_mode))
	if _ramp_keys.has(key):
		return int(_ramp_keys[key])
	var colours := PackedColorArray()
	colours.resize(RAMP_WIDTH)
	for k in RAMP_WIDTH:
		colours[k] = ramp.sample(float(k) / float(RAMP_WIDTH - 1)) if ramp != null else Color.WHITE
	var row: int = _ramp_like(colours)
	_ramp_keys[key] = row
	return row


func _start_rows_again() -> void:
	"""Every row let go, and every emitter's taken again at its next write
	(this frame's end). At the start of a frame, before anything is written."""
	_rows_full = false
	_params_rows.clear()
	_ramp_rows.clear()
	_ramp_keys.clear()
	_params_image = Image.create(PARAM_WIDTH, FIRST_ROWS, false, Image.FORMAT_RGBAF)
	_ramps_image = Image.create(RAMP_WIDTH, FIRST_ROWS, false, Image.FORMAT_RGBA8)
	_params_dirty = true
	_ramps_dirty = true
	rows_started_again += 1
	for key in _groups:
		for e in (_groups[key] as Dictionary)["emitters"]:
			if e != null and is_instance_valid(e):
				(e as FxEmitter).fx_params_dirty = true
				_touched[e] = true


func _curve_row(curve: Curve) -> int:
	"""A scale curve's row: its value over the particle's life, a quarter of
	it in red (so up to 4). Found by its points, as the ramps are."""
	var points := PackedFloat32Array([1.0])
	for i in curve.point_count:
		var at: Vector2 = curve.get_point_position(i)
		points.append_array([at.x, at.y, curve.get_point_left_tangent(i), curve.get_point_right_tangent(i)])
	var key: PackedByteArray = points.to_byte_array()
	if _ramp_keys.has(key):
		return int(_ramp_keys[key])
	var colours := PackedColorArray()
	colours.resize(RAMP_WIDTH)
	for k in RAMP_WIDTH:
		var v: float = curve.sample_baked(float(k) / float(RAMP_WIDTH - 1))
		colours[k] = Color(clampf(v / 4.0, 0.0, 1.0), 0.0, 0.0, 1.0)
	var row: int = _ramp_like(colours)
	_ramp_keys[key] = row
	return row


func _ramp_like(colours: PackedColorArray) -> int:
	var key: PackedByteArray = colours.to_byte_array()
	if _ramp_rows.has(key):
		return int(_ramp_rows[key])
	if _ramp_rows.size() >= MOST_ROWS:
		_rows_full = true
	var row: int = _ramp_rows.size()
	if row >= _ramps_image.get_height():
		var bigger := Image.create(RAMP_WIDTH, _ramps_image.get_height() * 2, false, Image.FORMAT_RGBA8)
		bigger.blit_rect(_ramps_image, Rect2i(Vector2i.ZERO, _ramps_image.get_size()), Vector2i.ZERO)
		_ramps_image = bigger
	for k in RAMP_WIDTH:
		_ramps_image.set_pixel(k, row, colours[k])
	_ramp_rows[key] = row
	_ramps_dirty = true
	return row
