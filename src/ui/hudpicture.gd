extends Node
# hudpicture.gd - the bar along the bottom drawn once, and again only when it
# changes (0.155.0). The owner, of the HUD's draw calls: "lets do this The
# HUD", then "yes upgrade and improve as needed".
#
# MEASURED FIRST (zz/drawparts.gd, xvfb + opengl3): the HUD was 96 of the 107
# draw calls of an empty Testing Ground, every frame - the hotbar 51, the nav
# bar 33, health, mana and stamina 12 - though most frames nothing on it moves.
#
# THE TRICK is Godot's own: a CanvasLayer with a custom_viewport draws into
# that viewport instead of the screen, while its Controls stay in the main
# window's tree - so clicks, hovers, tooltips and drags to and from the bag
# work exactly as before (zz/hudprobe: 40 buttons 85 draw calls -> 4, a click
# and a drag each way still landing). So:
# - The nav bar and the hotbar (PARTS) move into `layer`, a CanvasLayer of
#   the HUD's own layer number at the nav bar's place among the HUD's
#   children, so what is over or under them for the mouse is as it was
#   (windows and dropdowns after them, over them).
# - `layer` draws into `sub`, a SubViewport the size of the strip the parts
#   cover, stretched as the window stretches the game (size_2d_override), so
#   letters are drawn at the screen's size and a pixel of the picture is a
#   pixel of the screen (_fit(), drawn_scale(), whole_step()).
# - `shown`, a Sprite2D in the HUD where the nav bar was, puts the picture
#   on the screen pixel for pixel: one draw call.
# - `sub` draws only when asked (UPDATE_ONCE): when anything in the parts
#   redraws, shows or hides, moves or resizes, comes or goes, when the window
#   changes size - and every SAFETY_SECONDS, in case something changed without
#   saying so.
#
# Health, mana and stamina stay as they were, drawn every frame: in a fight
# they change all the time (stamina every frame of a sprint), and a picture
# redrawn every frame costs more than drawing them.
#
# The picture is premultiplied (a see-through pixel drawn into a clear picture
# keeps its colour already multiplied by its alpha), so `shown` blends it so.
#
# MEASURED AFTER (zz/hudshot.gd, xvfb + opengl3): an empty Testing Ground 111
# draw calls a frame -> 28; 20 archers fighting you 166 -> 83, the picture
# drawn 2 times a second (the safety's); a phone's layout (five keys, Menu)
# 66 -> 32. The same pixels as before at the game's own size and at Low; at a
# window between sizes (1.5 times, 1366 wide) an edge here and there lands a
# pixel over, as the screen would round it either way.

const PARTS: Array[StringName] = [&"navframe", &"hotbar"]
const LAYER_NAME := "barpicture"
const SHOWN_NAME := "barpictureshown"
const SAFETY_SECONDS := 0.5
# Room round the parts for what is drawn past their edges (a shadow, a glow).
const MARGIN := 6.0

# Off, a HUD made after keeps its bar drawn every frame, as before 0.155.0
# (zz/hudshot's before, and a way back).
static var enabled: bool = true

var hud: CanvasLayer = null
var layer: CanvasLayer = null
var sub: SubViewport = null
var shown: Sprite2D = null
# How many times the picture was drawn, and what it covers on the screen in
# screen pixels - for the suite and the readout.
var redraws: int = 0
var strip_px: Rect2i = Rect2i()
var _asked_frame: int = -1
var _safety: float = 0.0


static func attach(on: CanvasLayer) -> Node:
	"""Puts `on`'s nav bar and hotbar in a picture. Returns the node, or null
	where there is nothing to put (a HUD without them)."""
	if on == null or not on.is_inside_tree() or not enabled:
		return null
	var parts: Array = []
	for part_name in PARTS:
		var part: Node = on.get_node_or_null(NodePath("%" + String(part_name)))
		if part is Control and part.get_parent() == on:
			parts.append(part)
	if parts.is_empty():
		return null
	return picture_parts(on, parts, "hudpicture", LAYER_NAME)


static func picture_parts(on: CanvasLayer, parts: Array, node_name: String, layer_name: String) -> Node:
	"""ANY LAYER'S PARTS AS ONE PICTURE (0.155.1): the HUD's bar (attach()),
	the readout's panel (perfoverlay.gd) and the Testing Ground's
	(testingground.gd) - each drawn by many calls, changing a few times a
	second at most. `parts` are children of `on`; they move into a layer
	named `layer_name` at the first one's place. Null where nothing can be."""
	if on == null or not on.is_inside_tree() or not enabled or parts.is_empty():
		return null
	for part in parts:
		if not (part is Control) or (part as Node).get_parent() != on:
			return null
	var picture: Node = (load("res://src/ui/hudpicture.gd") as GDScript).new()
	picture.name = node_name
	on.add_child(picture)
	picture.call("_build", on, parts, layer_name)
	return picture


func _make_sub(view_name: String) -> void:
	sub = SubViewport.new()
	sub.name = view_name
	sub.transparent_bg = true
	sub.disable_3d = true
	sub.gui_disable_input = true
	sub.render_target_update_mode = SubViewport.UPDATE_DISABLED
	sub.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	var root: Viewport = hud.get_viewport()
	sub.canvas_item_default_texture_filter = root.canvas_item_default_texture_filter
	sub.canvas_item_default_texture_repeat = root.canvas_item_default_texture_repeat
	sub.snap_2d_transforms_to_pixel = root.snap_2d_transforms_to_pixel
	sub.snap_2d_vertices_to_pixel = root.snap_2d_vertices_to_pixel
	sub.use_hdr_2d = root.use_hdr_2d
	sub.msaa_2d = root.msaa_2d
	add_child(sub)


func _make_shown() -> Sprite2D:
	# A Sprite2D, not a TextureRect: a Control's place is rounded to a whole
	# unit of the game, which at a scale of 1.5 is half a screen pixel off.
	var picture := Sprite2D.new()
	picture.name = SHOWN_NAME
	picture.centered = false
	# Placed, never moved by the physics: not blended from where it was.
	picture.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var blend := CanvasItemMaterial.new()
	blend.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	picture.material = blend
	picture.texture = sub.get_texture()
	return picture


func _listen() -> void:
	hud.visibility_changed.connect(_on_hud_shown)
	hud.get_viewport().size_changed.connect(ask)
	get_tree().node_added.connect(_on_node_added)
	get_tree().node_removed.connect(_on_node_removed)


func _build(on: CanvasLayer, parts: Array, layer_name: String) -> void:
	hud = on
	var place: int = (parts[0] as Node).get_index()
	_make_sub(layer_name + "view")
	layer = CanvasLayer.new()
	layer.name = layer_name
	layer.layer = hud.layer
	layer.custom_viewport = sub
	layer.visible = hud.visible
	hud.add_child(layer)
	hud.move_child(layer, place)
	for part in parts:
		(part as Node).reparent(layer, false)
	shown = _make_shown()
	shown.name = layer_name + "shown"
	hud.add_child(shown)
	hud.move_child(shown, layer.get_index())
	for item in [layer] + layer.find_children("*", "", true, false):
		_wire(item as Node)
	_listen()
	ask()


func detach() -> void:
	"""Puts the parts back in the HUD, drawn every frame as before, and takes
	the picture away (the suite's before, and a way back)."""
	if layer == null or hud == null:
		return
	var place: int = layer.get_index()
	var parts: Array = layer.get_children()
	for part in parts:
		(part as Node).reparent(hud, false)
		hud.move_child(part, place)
		place += 1
	_stop_listening()
	for item in parts:
		for each in [item] + (item as Node).find_children("*", "", true, false):
			_unwire(each as Node)
	shown.queue_free()
	layer.queue_free()
	queue_free()
	shown = null
	layer = null


func _stop_listening() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
	if get_tree().node_removed.is_connected(_on_node_removed):
		get_tree().node_removed.disconnect(_on_node_removed)
	if hud.get_viewport().size_changed.is_connected(ask):
		hud.get_viewport().size_changed.disconnect(ask)
	if hud.visibility_changed.is_connected(_on_hud_shown):
		hud.visibility_changed.disconnect(_on_hud_shown)


func bar_parts() -> Array:
	return layer.get_children() if layer != null else []


func ask() -> void:
	"""Draw the picture again this frame - once, however many things ask."""
	if sub == null or not is_inside_tree():
		return
	var frame: int = Engine.get_process_frames()
	if frame == _asked_frame:
		return
	_asked_frame = frame
	_safety = 0.0
	_fit()
	sub.render_target_update_mode = SubViewport.UPDATE_ONCE
	redraws += 1


func _process(delta: float) -> void:
	if layer == null or not layer.visible or not hud.visible:
		return
	_safety += delta
	if _safety >= SAFETY_SECONDS:
		ask()


func _fit() -> void:
	"""The strip the parts cover, in screen pixels: the picture's size, where
	it is drawn from, and where `shown` puts it."""
	var root: Viewport = hud.get_viewport()
	var view: Rect2 = root.get_visible_rect()
	var scale: float = drawn_scale(root)
	var cover := Rect2()
	for item in layer.find_children("*", "Control", true, false):
		var control := item as Control
		if not control.is_visible_in_tree():
			continue
		var rect: Rect2 = control.get_global_rect()
		cover = rect if cover.has_area() == false else cover.merge(rect)
	if not cover.has_area():
		cover = Rect2(view.position, Vector2(1, 1))
	cover = cover.grow(MARGIN).intersection(view)
	if not cover.has_area():
		cover = Rect2(view.position, Vector2(1, 1))
	# Whole units of the game that are whole screen pixels too (at a scale of
	# 1.5, every second unit), so the picture is stretched by exactly the
	# window's scale and lands on the screen's own pixels.
	var step: int = whole_step(scale)
	var from := Vector2i(floori(cover.position.x / step) * step, floori(cover.position.y / step) * step)
	var to := Vector2i(ceili(cover.end.x / step) * step, ceili(cover.end.y / step) * step)
	var units := Rect2i(from, (to - from).max(Vector2i(step, step)))
	var px := Rect2i(Vector2i((Vector2(units.position) * scale).round()), Vector2i((Vector2(units.size) * scale).round()).max(Vector2i.ONE))
	if px != strip_px or sub.size_2d_override != units.size:
		strip_px = px
		sub.size = px.size
		# Stretched as the window stretches the game (size_2d_override), so
		# letters are drawn at the screen's own size, as the window draws
		# them; a scale in the transform alone draws them at the game's size
		# and stretches the result.
		sub.size_2d_override = units.size
		sub.size_2d_override_stretch = true
	sub.global_canvas_transform = Transform2D(0.0, -Vector2(units.position))
	shown.position = Vector2(units.position)
	shown.scale = Vector2(units.size) / Vector2(px.size)
	if layer.layer != hud.layer:
		layer.layer = hud.layer


static func whole_step(scale: float) -> int:
	"""The fewest units of the game that come to whole screen pixels at
	`scale` (1 at 1 or 2, 2 at 1.5, 4 at 1.25); 1 where none is near."""
	for step in range(1, 9):
		var px: float = scale * float(step)
		if absf(px - roundf(px)) < 0.001:
			return step
	return 1


static func drawn_scale(root: Viewport) -> float:
	"""The screen's pixels to a unit of the game, as the window DRAWS it, so
	the picture has as many pixels as the screen would have drawn: at Screen
	(canvas_items) the window's own pixels, its final transform's scale; at
	Low (viewport mode) the game's own size, one to one, stretched after."""
	var window := root as Window
	if window == null or window.content_scale_mode != Window.CONTENT_SCALE_MODE_CANVAS_ITEMS:
		return 1.0
	var scale: float = root.get_final_transform().get_scale().x
	return scale if scale > 0.0 else 1.0


func _on_hud_shown() -> void:
	# A CanvasLayer inside another is not hidden with it: hidden, the parts
	# must take no clicks either.
	layer.visible = hud.visible
	ask()


func _on_node_added(node: Node) -> void:
	# Each node that comes is told of on its own (a whole new branch, node by
	# node), so one at a time is all of it.
	if layer != null and layer.is_ancestor_of(node):
		_wire(node)
		ask()


func _on_node_removed(node: Node) -> void:
	if layer != null and layer.is_ancestor_of(node):
		ask()


func _wire(node: Node) -> void:
	"""Whatever `node` does to its look asks for a new picture: drawing
	(its value, text, icon, a hover), showing or hiding, moving or resizing."""
	if node is CanvasItem:
		var item := node as CanvasItem
		if not item.draw.is_connected(ask):
			item.draw.connect(ask)
		if not item.visibility_changed.is_connected(ask):
			item.visibility_changed.connect(ask)
	if node is Control:
		var control := node as Control
		if not control.item_rect_changed.is_connected(ask):
			control.item_rect_changed.connect(ask)


func _unwire(node: Node) -> void:
	if node is CanvasItem:
		var item := node as CanvasItem
		if item.draw.is_connected(ask):
			item.draw.disconnect(ask)
		if item.visibility_changed.is_connected(ask):
			item.visibility_changed.disconnect(ask)
	if node is Control and (node as Control).item_rect_changed.is_connected(ask):
		(node as Control).item_rect_changed.disconnect(ask)
