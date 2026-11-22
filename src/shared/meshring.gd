# meshring.gd - a MultiMesh rewritten often, sent without waiting on the
# graphics card (0.173.2).
#
# The owner's limit sweep in his browser (21 Nov), "either way we need to
# optimize all of that": 20 archers took drawing from 1.3 ms a frame to 17.1,
# and the large slime, both sprites, the dark boss and the horde stopped on
# slow frames of 20 to 25 ms while their usual frames were 2 to 4. Skeletons
# and bush mages, which put nothing in a MultiMesh, never did. What the slow
# ones share: each frame they write a MultiMesh the card is still drawing.
#
# Godot's Compatibility renderer - the browser's - sends a MultiMesh's buffer
# whole, every time (glBufferData, GL_STATIC_DRAW), however few of it are
# drawn: the bullet field 12,000 slots a frame, bullets or none, the horde
# 5,000 twenty times a second. Rewriting a buffer the card has not finished
# drawing from makes the browser wait for the card or copy it - and that wait
# is counted as drawing.
#
# So a drawer wears a RING of MultiMeshes of one kind. Each send goes to the
# next one round, never the one on screen, and the drawer is turned to it; and
# each holds only what is used, in steps (slots_for()), not the whole buffer.
# What is drawn is the same, instance for instance.
#
# No class_name: preload it by path. Made with new(), worn with wear().
extends RefCounted

# MultiMeshes round: the one on screen, the one before it, and the one sent to.
const RING := 3
# The fewest slots one holds: a handful of bullets never resizes it.
const LEAST := 64

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


static func _like(of: MultiMesh) -> MultiMesh:
	var multi := MultiMesh.new()
	multi.transform_format = of.transform_format
	multi.use_colors = of.use_colors
	multi.use_custom_data = of.use_custom_data
	multi.mesh = of.mesh
	multi.custom_aabb = of.custom_aabb
	multi.instance_count = 0
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
	from now. Nothing is sent while nothing was and nothing is drawn."""
	if drawer == null or stride <= 0:
		return
	var most: int = buffer.size() / stride
	count = mini(count, most)
	if count <= 0:
		if shown != 0:
			current().visible_instance_count = 0
			shown = 0
		return
	_turn = (_turn + 1) % meshes.size()
	var multi: MultiMesh = meshes[_turn]
	var slots: int = slots_for(count, multi.instance_count, most)
	if multi.instance_count != slots:
		multi.instance_count = slots
		resizes += 1
	multi.buffer = buffer if slots == most else buffer.slice(0, slots * stride)
	multi.visible_instance_count = count
	if drawer.multimesh != multi:
		drawer.multimesh = multi
	shown = count
	sends += 1
