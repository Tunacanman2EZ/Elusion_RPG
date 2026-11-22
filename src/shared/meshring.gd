# meshring.gd - a MultiMesh rewritten often, drawn without stalling the
# browser (0.173.2, 0.174.2).
#
# The owner's limit sweep in his browser (21 Nov), "either way we need to
# optimize all of that": 20 archers took drawing from 1.3 ms a frame to 17.1,
# and the large slime, both sprites, the dark boss and the horde stopped on
# slow frames of 20 to 25 ms while their usual frames were 2 to 4. Skeletons
# and bush mages, which put nothing in a MultiMesh, never did.
#
# 0.173.2 guessed that the card was still drawing from the buffer being
# rewritten, and gave each drawer a RING of MultiMeshes so a send never goes
# to the one on screen. Measured since on his card, that changed nothing; it
# is kept because it costs nothing.
#
# THE COUNT DRAWN IS THE STALL (0.174.2). The owner: "yes" to measuring the
# horde's fill, "this game needs to be strong to love". On his card, 1,000
# slimes filling the Testing Ground gave 50 to 85 frames over 14 ms, each with
# about 20 ms of drawing, all while the horde walked onto the screen - and
# none once it stood: 1,000 drawn then cost 1.3 ms. Changing the order of the
# sends, never resizing, the lights off, slimes a quarter the size, plain
# colours and skipping their clear pixels all left it at 47 to 83. Godot's
# Compatibility renderer gives every instanced draw a step the size of the
# number of instances drawn (glVertexAttribDivisor(..., instance_count),
# rasterizer_canvas_gles3.cpp _enable_attributes()), and the browser builds
# its drawing anew for each number it has not seen. Walking on, the horde's
# count changed twenty times a second.
#
# So each MultiMesh draws EVERY ONE OF ITS SLOTS (visible_instance_count -1),
# and the slots past `count` are sent blank - all zeros, a transform of no
# size, so nothing of them is drawn - from a strip of zeros joined on with
# no loop in GDScript. The number drawn changes only with the slots, in
# powers of two (slots_for()), and the browser keeps the few it has built.
# Measured the same way: 18 and 30 slow frames, the worst 16 ms, no stall
# of 20. What is drawn is the same, instance for instance.
#
# `shown` (and shown_on() for a drawer) is how many are really drawn; the
# MultiMesh's visible_instance_count no longer says it.
#
# No class_name: preload it by path. Made with new(), worn with wear().
extends RefCounted

# MultiMeshes round: the one on screen, the one before it, and the one sent to.
const RING := 3
# The fewest slots one holds: a handful of bullets never resizes it.
const LEAST := 64
# How many of a MultiMesh's slots hold something, on the MultiMesh itself.
const SHOWN_META := &"ring_shown"

var drawer: MultiMeshInstance2D = null
var meshes: Array[MultiMesh] = []
# Floats an instance takes in the buffers sent (12 a bullet, 16 a slime).
var stride: int = 12
# How many the drawer draws now.
var shown: int = 0
# Sends made, and resizes (the suite reads them).
var sends: int = 0
var resizes: int = 0
var _turn: int = 0
# Zeros: the blank slots joined onto a send, grown to the widest gap yet.
var _blank := PackedFloat32Array()


func wear(on: MultiMeshInstance2D, floats: int) -> void:
	"""`on` draws from this ring from now: its own MultiMesh and RING - 1 more
	of the same kind (format, mesh, bounds), none of them interpolated."""
	drawer = on
	stride = floats
	var first: MultiMesh = on.multimesh
	meshes = [first]
	for k in RING - 1:
		meshes.append(_like(first))
	_turn = 0
	shown = maxi(first.visible_instance_count, 0)
	first.set_meta(SHOWN_META, shown)


static func _like(of: MultiMesh) -> MultiMesh:
	var multi := MultiMesh.new()
	multi.transform_format = of.transform_format
	multi.use_colors = of.use_colors
	multi.use_custom_data = of.use_custom_data
	multi.mesh = of.mesh
	multi.custom_aabb = of.custom_aabb
	multi.instance_count = 0
	multi.set_meta(SHOWN_META, 0)
	# As the drawers' own (0.93.5): a buffer rewritten in another order must
	# not be blended by the engine.
	RenderingServer.multimesh_set_physics_interpolated(multi.get_rid(), false)
	return multi


func set_bounds(box: AABB) -> void:
	"""Where the renderer is told the instances are, for every one round."""
	for multi in meshes:
		multi.custom_aabb = box


func current() -> MultiMesh:
	return drawer.multimesh if drawer != null else null


static func shown_on(on: MultiMeshInstance2D) -> int:
	"""How many instances `on` really draws: what its ring sent, or for a
	MultiMesh no ring sends to, its visible_instance_count."""
	if on == null or on.multimesh == null:
		return 0
	var multi: MultiMesh = on.multimesh
	if multi.has_meta(SHOWN_META):
		return int(multi.get_meta(SHOWN_META))
	return multi.visible_instance_count if multi.visible_instance_count >= 0 else multi.instance_count


static func slots_for(count: int, have: int, most: int) -> int:
	"""How many slots a MultiMesh holding `have` should hold to draw `count`:
	`have` while it fits and is not over four times too big, else the power of
	two at or above `count` (LEAST at the least) - never more than `most`, the
	buffer's own size."""
	if have >= count and have <= maxi(LEAST, count * 4) and have <= most:
		return have
	return mini(maxi(LEAST, nearest_po2(count)), most)


func send(buffer: PackedFloat32Array, count: int) -> void:
	"""The first `count` instances of `buffer` (`stride` floats each) drawn
	from now, the rest of the MultiMesh's slots sent blank. Nothing is sent
	while nothing was and nothing is drawn."""
	if drawer == null or stride <= 0:
		return
	var most: int = buffer.size() / stride
	count = mini(count, most)
	if count <= 0:
		if shown != 0:
			var on_screen: MultiMesh = current()
			on_screen.visible_instance_count = 0
			on_screen.set_meta(SHOWN_META, 0)
			shown = 0
		return
	_turn = (_turn + 1) % meshes.size()
	var multi: MultiMesh = meshes[_turn]
	var slots: int = slots_for(count, multi.instance_count, most)
	if multi.instance_count != slots:
		multi.instance_count = slots
		resizes += 1
	multi.buffer = _with_blanks(buffer, count, slots, most)
	# Every slot, whatever `count` is: the number drawn stays put.
	multi.visible_instance_count = -1
	multi.set_meta(SHOWN_META, count)
	if drawer.multimesh != multi:
		drawer.multimesh = multi
	shown = count
	sends += 1


func _with_blanks(buffer: PackedFloat32Array, count: int, slots: int, most: int) -> PackedFloat32Array:
	"""`slots` instances: the first `count` of `buffer`, then blank ones."""
	if count >= slots:
		return buffer if slots == most else buffer.slice(0, slots * stride)
	var gap: int = (slots - count) * stride
	if _blank.size() < gap:
		_blank.resize(gap)
		_blank.fill(0.0)
	var sent: PackedFloat32Array = buffer.slice(0, count * stride)
	sent.append_array(_blank if _blank.size() == gap else _blank.slice(0, gap))
	return sent
