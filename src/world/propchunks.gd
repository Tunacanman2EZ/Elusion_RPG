# propchunks.gd - the Big Field's walls and decor are drawn only near the
# view. Added to every area by AreaRegistry, the way the sleeper is; an area
# whose props are not in chunks gets none.
#
# WHY. The Big Field is 2,717 wall pieces and 172 props - 11,948 pictures,
# lights and bodies under ysortworld/props - and nearly all of them are off
# screen. Off screen is not free under a y-sorted parent: the renderer still
# gathers and sorts every one of them every frame. Measured in the
# container: 12,000 off-screen sprites cost 6.6-7.1 ms a frame y-sorted, 3.1
# not, 1.7 hidden; in the Big Field, hiding ysortworld/props took a frame
# from 22.7 ms to 17.1.
#
# HOW. buildbigfield.gd puts every wall and prop in a chunk of its group
# (crypt/walls/c3_2, crypt/decor/c3_2): a y-sorted Node2D at the origin for
# the CHUNK px square its foot stands in, in the group GROUP, with the
# rectangle everything in it can draw kept as its meta REACH - every
# picture, and every light at the brightest its flicker swells to. Here, a
# chunk is shown while its reach touches the view (SHOW_MARGIN round it) and
# hidden once it is HIDE_MARGIN away - two distances, so one at the edge
# does not flick on and off as the player shuffles. A hidden chunk's reach
# is off the screen, so what the screen shows is what it showed before,
# pixel for pixel. The doors, the arrival portal and the pillar plugs are
# not in chunks: the doors' paths are their names on the wire
# (Presence.lever_name()), and the rest are a handful of nodes.
#
# STILL SORTED WITH EVERYBODY. A y-sorted node inside a y-sorted node has its
# children sorted with its parent's (Godot's nested Y-sort), so a wall in a
# chunk still sorts against the player and the monsters exactly as it did
# one level up - walls, then doors, then decor, in the same order on a tie.
#
# HIDDEN IS ONLY NOT DRAWN. visible does not touch physics: a hidden wall
# blocks feet and bullets as before, and the navigation is the floor's own
# region, baked in the scene.
#
# EVERY FRAME, JUST BEFORE IT IS DRAWN. Four comparisons a frame ask whether
# the view is still inside the rectangle the chunks were last shown for; when
# it is not - a walk of SHOW_MARGIN, a jump through a door or portal, an
# arrival, the camera zoom setting or Sharp pixels widening the view (1x is
# the widest, the whole 1280 x 720) - the chunks are looked at again at once.
# It is asked in _process and again on RenderingServer.frame_pre_draw, after
# every timer, tween and deferred call of the frame, so nothing moves the
# camera between the look and the picture. A full look also runs CHECK_SECONDS
# apart, to hide what has fallen far behind.
#
# SHOWN AT ONCE, HIDDEN A FEW A FRAME. Hiding or showing a chunk tells every
# node in it (0.1-0.35 ms a chunk, measured), and arriving hid some fifty in
# one look - 7 ms. A chunk left shown a little longer changes nothing on
# screen, so a look hides at most HIDES_PER_LOOK and the next frames finish
# the job; a chunk the view needs is always shown in the look that finds it.
extends Node

const NODE_NAME := "propchunks"
# The builders' chunks, and what each keeps of itself.
const GROUP := &"propchunk"
const REACH := &"reach"
# How big a chunk is, in px - buildbigfield.gd's chunk_size by default.
const CHUNK := 1024
# Shown while its reach is within SHOW_MARGIN of the view, hidden past
# HIDE_MARGIN.
const SHOW_MARGIN := 128.0
const HIDE_MARGIN := 512.0
const CHECK_SECONDS := 0.25
const HIDES_PER_LOOK := 4

# Off shows every chunk and leaves them shown: for measuring, and an escape
# hatch.
var enabled: bool = true:
	set(value):
		enabled = value
		if not enabled:
			show_all()
		else:
			refresh(true)

var _chunks: Array[CanvasItem] = []
# Each chunk's reach, in the world's space.
var _reaches: Array[Rect2] = []
# Every chunk touching this is shown; a view inside it needs no look.
var _cover: Rect2 = Rect2()
var _since: float = 0.0
# Far chunks a look left shown, for the next frame's look.
var _hides_waiting: bool = false


static func add_to(scene: Node) -> Node:
	"""A helper for `scene`'s chunks, or null when it has none."""
	if scene == null or not scene.is_inside_tree():
		return null
	var found: Array[CanvasItem] = []
	for node in scene.get_tree().get_nodes_in_group(GROUP):
		if node is CanvasItem and node.has_meta(REACH) and scene.is_ancestor_of(node):
			found.append(node as CanvasItem)
	if found.is_empty():
		return null
	var helper := (load("res://src/world/propchunks.gd") as GDScript).new() as Node
	helper.name = NODE_NAME
	helper.call("take", found)
	scene.add_child(helper)
	return helper


static func reach_of(piece: Node2D) -> Rect2:
	"""Everything `piece` can draw, in its parent's space: each Sprite2D's
	picture and each PointLight2D's light at its biggest (lightflicker.gd
	swells a light's texture_scale by up to (swell_amount + flicker_amount)
	x reach_response). Anything else that may draw is given UNKNOWN_REACH
	round it - the suite holds that there is none."""
	var out := Rect2(piece.position, Vector2.ZERO)
	for node in [piece] + piece.find_children("*", "", true, false):
		var item := node as CanvasItem
		if item == null:
			continue
		var xf: Transform2D = _to_parent_of(item as Node, piece)
		if item is Sprite2D:
			out = out.merge(xf * (item as Sprite2D).get_rect())
		elif item is PointLight2D:
			var light := item as PointLight2D
			if light.texture == null:
				continue
			var grow: float = 1.0
			if "reach_response" in light:
				grow += (float(light.get("swell_amount")) + float(light.get("flicker_amount"))) \
					* float(light.get("reach_response"))
			var size: Vector2 = light.texture.get_size() * light.texture_scale * grow
			out = out.merge(xf * Rect2(light.offset - size / 2.0, size))
		elif not draws_nothing(item):
			out = out.merge(Rect2(xf.origin, Vector2.ZERO).grow(UNKNOWN_REACH))
	return out


# For a piece with something drawn this does not know how to measure.
const UNKNOWN_REACH := 256.0


static func draws_nothing(item: CanvasItem) -> bool:
	"""A plain Node2D, body, area or shape with no script draws nothing
	(collision shapes only in the editor's debug view)."""
	if item.get_script() != null:
		return false
	return item.get_class() in ["Node2D", "StaticBody2D", "Area2D", "CollisionShape2D", "CollisionPolygon2D"]


static func _to_parent_of(node: Node, piece: Node2D) -> Transform2D:
	# By hand, as mapbackdrop.gd's: the builder measures pieces that are not in
	# the tree.
	var xf := Transform2D()
	var at: Node = node
	while at != null:
		if at is Node2D:
			xf = (at as Node2D).transform * xf
		if at == piece:
			break
		at = at.get_parent()
	return xf


func take(chunks: Array[CanvasItem]) -> void:
	_chunks = chunks
	_reaches.clear()
	for chunk in _chunks:
		var reach: Rect2 = chunk.get_meta(REACH)
		var to_world: Transform2D = (chunk as Node2D).get_global_transform() if chunk is Node2D else Transform2D()
		_reaches.append(to_world * reach)


func _ready() -> void:
	# Paused or not: a menu can be open while somebody else's door moves you.
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not RenderingServer.frame_pre_draw.is_connected(_on_pre_draw):
		RenderingServer.frame_pre_draw.connect(_on_pre_draw)
	refresh(true)


func _exit_tree() -> void:
	# Nothing is shown back: this leaves with its area, and showing fifty
	# chunks on the way out would be 5 ms spent on a scene being freed.
	if RenderingServer.frame_pre_draw.is_connected(_on_pre_draw):
		RenderingServer.frame_pre_draw.disconnect(_on_pre_draw)


func _process(delta: float) -> void:
	_since += delta
	if _since >= CHECK_SECONDS or _hides_waiting:
		_since = 0.0
		refresh(true)
	else:
		refresh()


func _on_pre_draw() -> void:
	refresh()


func refresh(force: bool = false) -> bool:
	"""Shows the chunks near the view and hides the far ones - only when the
	view has left the rectangle they were last shown for, or `force`. True
	when it looked."""
	if not enabled or not is_inside_tree():
		return false
	var view: Rect2 = view_rect()
	if not view.has_area():
		show_all()
		return true
	if not force and _cover.encloses(view):
		return false
	var near: Rect2 = view.grow(SHOW_MARGIN)
	var far: Rect2 = view.grow(HIDE_MARGIN)
	var hides_left: int = HIDES_PER_LOOK
	_hides_waiting = false
	for i in _chunks.size():
		var chunk: CanvasItem = _chunks[i]
		if not is_instance_valid(chunk):
			continue
		var reach: Rect2 = _reaches[i]
		if reach.intersects(near, true):
			if not chunk.visible:
				chunk.visible = true
		elif chunk.visible and not reach.intersects(far, true):
			if hides_left > 0:
				chunk.visible = false
				hides_left -= 1
			else:
				_hides_waiting = true
	_cover = near
	return true


func show_all() -> void:
	for chunk in _chunks:
		if is_instance_valid(chunk) and not chunk.visible:
			chunk.visible = true
	_cover = Rect2()
	_hides_waiting = false


func shown() -> int:
	"""How many chunks are shown - for the suite and the bench."""
	var count: int = 0
	for chunk in _chunks:
		if is_instance_valid(chunk) and chunk.visible:
			count += 1
	return count


func chunk_count() -> int:
	return _chunks.size()


func view_rect() -> Rect2:
	"""What this game's screen shows of the world (enemysleeper.gd's
	view_rect(), without its margin): all four corners, so a turned camera
	is covered too."""
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return Rect2()
	var to_world: Transform2D = viewport.get_canvas_transform().affine_inverse()
	var size: Vector2 = viewport.get_visible_rect().size
	var view := Rect2(to_world * Vector2.ZERO, Vector2.ZERO)
	view = view.expand(to_world * size)
	view = view.expand(to_world * Vector2(size.x, 0.0))
	return view.expand(to_world * Vector2(0.0, size.y))
