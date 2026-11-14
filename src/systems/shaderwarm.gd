extends Node
# shaderwarm.gd - EVERY LOOK DRAWN ONCE, OUT OF SIGHT (0.156.0): each way
# the game draws, drawn as the first area of a session arrives, so no fight
# is the frame that builds it.
#
# The owner's phone, a boss fight in the Testing Ground: one frame of
# 3,243 ms, "waiting" - the browser and the graphics card, not the game's
# code - with spikes going and pools landing; then "WE NEED TO LOOK INTO
# EVERY CRACK". A graphics card draws with a program built from the shader
# and the way it is drawn (a sprite, a line, a shape, a crowd of copies), and
# Godot builds each one the first time it is drawn - on a phone in the
# browser that can hold the screen for a long time. Measured in the
# container (zz/firstdraw2.gd, every program Mesa built put on the fight's
# clock): 36 built before a fight, then 4 or 5 in the middle of every one -
# the hit flash on the first blow, the death crumble and the dust of the
# first monster to die, the sparks of the first strike - for every class.
#
# HOW. Once a session, START_AFTER frames after the first area arrives,
# every look below is drawn at the middle of the view, under everything
# (z CANVAS_ITEM_Z_MIN, below the floor) and WARM_ALPHA faint, each in the
# ways it is drawn (Mode), for WARM_FRAMES frames - not as nodes but as the
# renderer's own items, so nothing of them thinks, collides, counts as a
# monster or plays a sound. With lighting "full" each is drawn again lit, by
# a light of its own (GHOST_LIGHT, which lights only them): a lit thing
# needs a program of its own. Godot builds one program for each shader's
# code, so a shader written in code (SHADER_CODE) is warm for every copy.
#
# A NEW LOOK goes in here: a .gdshader in SHADER_FILES, a shader written in
# code in SHADER_CODE, a CanvasItemMaterial's blend and light in PLAIN_LOOKS.
# _test_every_look_is_warmed() fails on one left out. The readout marks
# "first draws" when something is drawn that was not warmed (look_key(),
# perfoverlay.gd), so a freeze with one in it names the cause.

const NODE_NAME := "shaderwarm"
const PATH := "res://src/systems/shaderwarm.gd"
const WARM_ALPHA := 0.02
const WARM_FRAMES := 3
const START_AFTER := 2
# A light layer nothing in the game uses: the ghost light lights only ghosts.
const GHOST_LIGHT := 1 << 19

enum Mode { QUAD, LINE, SHAPE, COPIES }
const ALL_MODES := [Mode.QUAD, Mode.LINE, Mode.SHAPE, Mode.COPIES]

# Every shader file the game draws with, and how it is drawn.
const SHADER_FILES := {
	"res://src/shared/death_crumble.gdshader": [Mode.QUAD],
	"res://src/shared/hitflash.gdshader": [Mode.QUAD],
	"res://src/shared/element_recolour.gdshader": [Mode.QUAD],
	"res://src/shared/stone_blend.gdshader": [Mode.QUAD],
	"res://src/shared/hearth_warm.gdshader": [Mode.QUAD],
	"res://src/shared/bossgate.gdshader": [Mode.QUAD],
	"res://src/world/crowned/riftvoid.gdshader": [Mode.QUAD],
	"res://src/world/endless/swarm.gdshader": [Mode.COPIES],
	"res://src/projectiles/spikesparks.gdshader": [Mode.COPIES],
	"res://src/projectiles/spikerings.gdshader": [Mode.COPIES],
}

# Shaders written in code: [script, its constant, how it is drawn].
const SHADER_CODE := [
	["res://src/shared/bulletfield.gd", "SHADER_CODE", [Mode.COPIES]],
	["res://src/characters/statuseffects.gd", "DAZZLE_SHADER", [Mode.QUAD]],
	["res://src/enemies/waterarena.gd", "RAIN_SHADER", [Mode.COPIES]],
	["res://src/enemies/lightarena.gd", "DARK_SHADER", [Mode.QUAD]],
	["res://src/enemies/icearena.gd", "FOG_SHADER", [Mode.QUAD]],
	["res://src/enemies/icearena.gd", "SNOW_SHADER", [Mode.QUAD, Mode.COPIES]],
	["res://src/world/healerrun/healerrun.gd", "DARK_SHADER", [Mode.QUAD]],
	["res://src/ui/menus/mapscreen.gd", "FOG_SHADER", [Mode.QUAD, Mode.SHAPE]],
]

# Written in code and drawn from the first frame, so never first in a fight.
const NOT_WARMED := {
	"res://src/ui/touchpad.gd": "a phone's hotbar slots, bent round (ROUND_SHADER)",
}

# The CanvasItemMaterials the game makes - [blend, light] - and the plain
# look (no material); each drawn every way.
const PLAIN_LOOKS := [
	[CanvasItemMaterial.BLEND_MODE_MIX, CanvasItemMaterial.LIGHT_MODE_UNSHADED],
	[CanvasItemMaterial.BLEND_MODE_ADD, CanvasItemMaterial.LIGHT_MODE_NORMAL],
	[CanvasItemMaterial.BLEND_MODE_ADD, CanvasItemMaterial.LIGHT_MODE_UNSHADED],
	[CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA, CanvasItemMaterial.LIGHT_MODE_NORMAL],
]

# Once a session: Godot keeps what it built.
static var _done: bool = false
# Every look_key() drawn here, for the readout's "first draws".
static var warmed: Dictionary = {}
# A shader's look by its code, kept by the Shader's instance id.
static var _code_keys: Dictionary = {}

var _items: Array[RID] = []
var _light: RID = RID()
# A crowd of copies of two shapes (a QuadMesh, and a flat mesh of points
# and UVs, as spikefx.gd and the ice arena's snow make), each four ways -
# with colours and custom data, custom data only, colours only, neither - as
# the game's MultiMeshes and particles are laid out (a phone's browser can
# build a program again for each).
var _multimeshes: Array[RID] = []
# What the ghosts draw with, held until they go.
var _keep: Array = []
var _frames: int = 0
# How many ghosts were drawn (the suite reads it).
var drawn: int = 0


static func add_to(scene: Node) -> Node:
	"""The session's warming, for the first area to arrive: null after."""
	if _done or scene == null:
		return null
	_done = true
	var warm: Node = (load(PATH) as GDScript).new()
	warm.name = NODE_NAME
	scene.add_child(warm)
	return warm


static func looks() -> Array:
	"""[material or null, modes] for every look below."""
	var out: Array = [[null, ALL_MODES]]
	for pair in PLAIN_LOOKS:
		var plain := CanvasItemMaterial.new()
		plain.blend_mode = int(pair[0]) as CanvasItemMaterial.BlendMode
		plain.light_mode = int(pair[1]) as CanvasItemMaterial.LightMode
		out.append([plain, ALL_MODES])
	for path in SHADER_FILES:
		var shader: Shader = load(path) as Shader
		if shader != null:
			var mat := ShaderMaterial.new()
			mat.shader = shader
			out.append([mat, SHADER_FILES[path]])
	for entry in SHADER_CODE:
		var script: Script = load(str(entry[0])) as Script
		if script == null:
			continue
		var code: Variant = script.get_script_constant_map().get(str(entry[1]))
		if not code is String:
			continue
		var shader := Shader.new()
		shader.code = code
		var mat := ShaderMaterial.new()
		mat.shader = shader
		out.append([mat, entry[2]])
	return out


static func look_key(item: CanvasItem) -> int:
	"""How `item` is drawn, as one number: its material's look and its mode.
	A ShaderMaterial is its shader's code (one program a code), a
	CanvasItemMaterial its blend and light, none is 0."""
	var material: Material = item.material
	if material == null and item.use_parent_material and item.get_parent() is CanvasItem:
		material = (item.get_parent() as CanvasItem).material
	return _material_key(material) * 4 + int(mode_of(item))


static func mode_of(item: CanvasItem) -> Mode:
	if item is CPUParticles2D or item is GPUParticles2D or item is MultiMeshInstance2D:
		return Mode.COPIES
	if item is Polygon2D or item is Line2D or item is MeshInstance2D:
		return Mode.SHAPE
	return Mode.QUAD


static func _material_key(material: Material) -> int:
	if material == null:
		return 0
	if material is CanvasItemMaterial:
		var plain := material as CanvasItemMaterial
		return 1 + int(plain.blend_mode) * 8 + int(plain.light_mode) * 2 + (1 if plain.particles_animation else 0) * 64
	if material is ShaderMaterial:
		var shader: Shader = (material as ShaderMaterial).shader
		if shader == null:
			return 0
		var id: int = shader.get_instance_id()
		if not _code_keys.has(id):
			_code_keys[id] = absi(shader.code.hash()) + 1000
		return int(_code_keys[id])
	return 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == START_AFTER:
		_draw_ghosts()
	elif _frames >= START_AFTER + WARM_FRAMES:
		_clear()
		queue_free()


func _exit_tree() -> void:
	_clear()


func _draw_ghosts() -> void:
	var view: Viewport = get_viewport()
	if view == null or view.world_2d == null:
		return
	var canvas: RID = view.world_2d.canvas
	var centre: Vector2 = view.get_canvas_transform().affine_inverse() * (view.get_visible_rect().size * 0.5)
	var lit: bool = str(Settings.get_value("lighting")) == "full"
	var texture: Texture2D = _white()
	_keep.append(texture)
	var quad := QuadMesh.new()
	quad.size = Vector2(4.0, 4.0)
	_keep.append(quad)
	var flat := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(-2, -2), Vector2(2, -2), Vector2(2, 2), Vector2(-2, 2)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	flat.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_keep.append(flat)
	for shape in [quad, flat]:
		for layout in [[true, true], [false, true], [true, false], [false, false]]:
			var multi: RID = RenderingServer.multimesh_create()
			RenderingServer.multimesh_set_mesh(multi, (shape as Mesh).get_rid())
			RenderingServer.multimesh_allocate_data(multi, 1, RenderingServer.MULTIMESH_TRANSFORM_2D,
				bool(layout[0]), bool(layout[1]))
			RenderingServer.multimesh_instance_set_transform_2d(multi, 0, Transform2D.IDENTITY)
			_multimeshes.append(multi)
	for look in looks():
		var material: Material = look[0]
		if material != null:
			_keep.append(material)
		for mode in look[1]:
			_ghost(canvas, centre, material, int(mode), 0, texture)
			if lit:
				_ghost(canvas, centre, material, int(mode), GHOST_LIGHT, texture)
			warmed[_material_key(material) * 4 + int(mode)] = true
	if lit:
		_light = RenderingServer.canvas_light_create()
		RenderingServer.canvas_light_attach_to_canvas(_light, canvas)
		RenderingServer.canvas_light_set_texture(_light, texture.get_rid())
		RenderingServer.canvas_light_set_texture_scale(_light, 4.0)
		RenderingServer.canvas_light_set_transform(_light, Transform2D(0.0, centre))
		RenderingServer.canvas_light_set_item_cull_mask(_light, GHOST_LIGHT)
		RenderingServer.canvas_light_set_z_range(_light, RenderingServer.CANVAS_ITEM_Z_MIN, RenderingServer.CANVAS_ITEM_Z_MIN)
		RenderingServer.canvas_light_set_enabled(_light, true)
	PerfOverlay.mark(&"shaders warm", drawn)


func _ghost(canvas: RID, at: Vector2, material: Material, mode: int, light_mask: int, texture: Texture2D) -> void:
	var item: RID = RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(item, canvas)
	RenderingServer.canvas_item_set_z_index(item, RenderingServer.CANVAS_ITEM_Z_MIN)
	RenderingServer.canvas_item_set_modulate(item, Color(1.0, 1.0, 1.0, WARM_ALPHA))
	RenderingServer.canvas_item_set_light_mask(item, light_mask)
	RenderingServer.canvas_item_set_transform(item, Transform2D(0.0, at))
	if material != null:
		RenderingServer.canvas_item_set_material(item, material.get_rid())
	var tex: RID = texture.get_rid()
	match mode:
		Mode.QUAD:
			RenderingServer.canvas_item_add_texture_rect(item, Rect2(-2.0, -2.0, 4.0, 4.0), tex)
		Mode.LINE:
			RenderingServer.canvas_item_add_line(item, Vector2(-2.0, 0.0), Vector2(2.0, 0.0), Color.WHITE)
		Mode.SHAPE:
			RenderingServer.canvas_item_add_polygon(item,
				PackedVector2Array([Vector2(-2.0, -2.0), Vector2(2.0, -2.0), Vector2(0.0, 2.0)]),
				PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE]),
				PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.ONE]), tex)
		Mode.COPIES:
			for multi in _multimeshes:
				RenderingServer.canvas_item_add_multimesh(item, multi, tex)
	_items.append(item)
	drawn += 1


func _clear() -> void:
	for item in _items:
		RenderingServer.free_rid(item)
	_items.clear()
	if _light.is_valid():
		RenderingServer.free_rid(_light)
		_light = RID()
	for multi in _multimeshes:
		RenderingServer.free_rid(multi)
	_multimeshes.clear()
	_keep.clear()


static func _white() -> Texture2D:
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	return ImageTexture.create_from_image(image)
