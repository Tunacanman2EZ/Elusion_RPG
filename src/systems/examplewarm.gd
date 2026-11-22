extends Node
# examplewarm.gd - EVERY MONSTER DRAWN ONCE, FOR REAL, OUT OF SIGHT (0.174.0):
# one real copy of each kind an area can bring, drawn as the area arrives,
# so the first fight with it is not the frame that builds its drawing.
#
# The owner: "yes i need master work please this game needs to be strong to
# love". Measured on his graphics card in the browser (a frame log for 12 s
# after 20 monsters appear, one fresh load a case): the first load after a
# new build, 23 to 38 frames of about 25 ms - every one of them drawing, none
# of them the game's code - when a kind is first drawn; later loads 5 to 7.
# In the container, every program the graphics driver built was logged from a
# cold start: shaderwarm.gd already builds all but two of them before any
# fight. So most of it is the browser finishing its own drawing of each kind
# the first time that kind is really drawn. shaderwarm.gd draws stand-in
# squares; this draws the monsters themselves.
#
# HOW. START_AFTER frames after an area arrives (after shaderwarm.gd), each
# kind not drawn yet this session - the monsters in the area, and those its
# run says it may bring (scenes_wanted()) - is made as a PICTURE ONLY
# (BaseEnemy.WARM_GHOST): never processing, so it neither thinks nor collides,
# in no group, worth nothing (StressCrowd.META), its health bar and number
# and aim ring shown as in a fight. It stands at the middle of the view under
# everything (z CANVAS_ITEM_Z_MIN) and WARM_ALPHA faint, lit for LIT_FRAMES and
# then unlit for as many, with one of each shot it fires beside it (scripts
# off: a shot's picture only), and is freed. EACH_FRAME kinds a frame, so a
# long list is spread over the area's first moments. Bosses are left out:
# one comes at a time, and making one builds its arena.
#
# A PLACE THAT BRINGS MONSTERS LATER says so: a node in PROVIDERS with
# warm_examples() -> PackedStringArray of scene paths (endlessrun.gd, the
# Testing Ground). No class_name: preload it by path.

const StressCrowd := preload("res://src/world/stresscrowd.gd")
const NODE_NAME := "examplewarm"
const PATH := "res://src/systems/examplewarm.gd"
const PROVIDERS := &"warm_examples"
const SHOTS_FOLDER := "res://scene/projectiles/"
const WARM_ALPHA := 0.02
const START_AFTER := 6
const EACH_FRAME := 3
const LIT_FRAMES := 2

# The bench's switch (and the suite's): off, nothing is drawn.
static var enabled: bool = true
# Every scene drawn this session, so an area brings only what is new.
static var warmed: Dictionary = {}

var _queue: Array[String] = []
# [ghost, frames it has been drawn]
var _alive: Array = []
var _frames: int = 0
var _holder: Node2D = null
# How many kinds and shots were drawn (the suite reads them).
var kinds_drawn: int = 0
var shots_drawn: int = 0


static func add_to(scene: Node) -> Node:
	"""This area's warming, or null when switched off."""
	if not enabled or scene == null:
		return null
	var warm: Node = (load(PATH) as GDScript).new()
	warm.name = NODE_NAME
	scene.add_child(warm)
	return warm


static func forget() -> void:
	"""As if no kind had been drawn this session (the suite)."""
	warmed.clear()


static func scenes_wanted(tree: SceneTree) -> Array[String]:
	"""Every monster scene this area has or says it may bring, not drawn yet
	this session, each once."""
	var out: Array[String] = []
	if tree == null:
		return out
	for monster in tree.get_nodes_in_group(&"enemies"):
		_want(out, str(monster.scene_file_path))
	for source in tree.get_nodes_in_group(PROVIDERS):
		if source.has_method(&"warm_examples"):
			for path in source.call(&"warm_examples"):
				_want(out, str(path))
	return out


static func _want(into: Array[String], path: String) -> void:
	if path == "" or not path.ends_with(".tscn") or warmed.has(path) or into.has(path):
		return
	into.append(path)


static func shot_scenes(ghost: Node) -> Array[PackedScene]:
	"""The shots `ghost` fires: every scene under SHOTS_FOLDER its script (and
	the scripts it extends) holds, as its element's variant."""
	var out: Array[PackedScene] = []
	var element: int = int(ghost.call(&"current_element")) if ghost.has_method(&"current_element") else 0
	var script: Script = ghost.get_script() as Script
	while script != null:
		for value in script.get_script_constant_map().values():
			if not value is PackedScene:
				continue
			var packed: PackedScene = value
			if not packed.resource_path.begins_with(SHOTS_FOLDER):
				continue
			var variant: PackedScene = Projectiles.variant_of(packed, element)
			if variant != null and not out.has(variant):
				out.append(variant)
		script = script.get_base_script()
	return out


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	_frames += 1
	if _frames < START_AFTER:
		return
	if _frames == START_AFTER:
		_queue = scenes_wanted(get_tree())
		if _queue.is_empty():
			queue_free()
			return
		_holder = Node2D.new()
		_holder.name = "ghosts"
		_holder.z_as_relative = false
		_holder.z_index = RenderingServer.CANVAS_ITEM_Z_MIN
		_holder.modulate = Color(1.0, 1.0, 1.0, WARM_ALPHA)
		add_child(_holder)
		_place_holder()
	_age_ghosts()
	for n in EACH_FRAME:
		if _queue.is_empty():
			break
		_make(_queue.pop_front())
	if _queue.is_empty() and _alive.is_empty():
		PerfOverlay.mark(&"monsters warm", kinds_drawn)
		queue_free()


func _place_holder() -> void:
	var view: Viewport = get_viewport()
	if view == null:
		return
	_holder.global_position = view.get_canvas_transform().affine_inverse() * (view.get_visible_rect().size * 0.5)
	_holder.reset_physics_interpolation()


func _make(path: String) -> void:
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		warmed[path] = true
		return
	var ghost: Node = packed.instantiate()
	if not ghost is BaseEnemy or ghost is BossEnemy:
		ghost.free()
		warmed[path] = true
		return
	ghost.set_meta(BaseEnemy.WARM_GHOST, true)
	ghost.set_meta(StressCrowd.META, true)
	ghost.process_mode = Node.PROCESS_MODE_DISABLED
	_holder.add_child(ghost)
	ghost.reset_physics_interpolation()
	# As in a fight: after somebody, its bar and number shown, its ring lit.
	ghost.set(&"engaged", true)
	ghost.call(&"ensure_health_readout")
	# Its number too, which a monster shows once hurt (baseenemy.gd).
	var number: CanvasItem = ghost.get_node_or_null(^"healthbar/healthvalue") as CanvasItem
	if number != null:
		number.visible = true
	var drawn: Array = [ghost]
	var x: float = 0.0
	for shot in shot_scenes(ghost):
		var picture: Node = _picture_of(shot)
		if picture == null:
			continue
		x += 12.0
		if picture is Node2D:
			(picture as Node2D).position = Vector2(x, 0.0)
		_holder.add_child(picture)
		drawn.append(picture)
		shots_drawn += 1
	for node in drawn:
		_under_everything(node)
	_alive.append([drawn, 0, path])
	kinds_drawn += 1


static func _picture_of(shot: PackedScene) -> Node:
	"""A shot's picture: the scene with every script taken off, so nothing of
	it moves, times out, hits or sounds."""
	var picture: Node = shot.instantiate()
	var nodes: Array[Node] = [picture]
	nodes.append_array(picture.find_children("*", "", true, false))
	for node in nodes:
		node.set_script(null)
	picture.process_mode = Node.PROCESS_MODE_DISABLED
	return picture


static func _under_everything(root: Node) -> void:
	var nodes: Array[Node] = [root]
	nodes.append_array(root.find_children("*", "", true, false))
	for node in nodes:
		if node is CanvasItem:
			(node as CanvasItem).z_as_relative = false
			(node as CanvasItem).z_index = RenderingServer.CANVAS_ITEM_Z_MIN


func _age_ghosts() -> void:
	"""Lit for LIT_FRAMES, then unlit for as many (light_mask 0), then gone."""
	for k in range(_alive.size() - 1, -1, -1):
		var entry: Array = _alive[k]
		entry[1] = int(entry[1]) + 1
		if int(entry[1]) == LIT_FRAMES + 1:
			for node in entry[0]:
				if is_instance_valid(node):
					_unlit(node)
		elif int(entry[1]) > LIT_FRAMES * 2:
			for node in entry[0]:
				if is_instance_valid(node):
					(node as Node).queue_free()
			warmed[str(entry[2])] = true
			_alive.remove_at(k)


static func _unlit(root: Node) -> void:
	var nodes: Array[Node] = [root]
	nodes.append_array(root.find_children("*", "", true, false))
	for node in nodes:
		if node is CanvasItem:
			(node as CanvasItem).light_mask = 0
