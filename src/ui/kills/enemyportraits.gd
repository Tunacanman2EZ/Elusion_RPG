# enemyportraits.gd - every monster that pays, by its enemy_id: its name and a
# picture of it, for the Kills window (0.9.0).
#
# THE PICTURE IS THE CREATURE'S OWN ART. Nothing in the project draws a
# monster's portrait - EnemyData has no icon - so this takes the first frame
# of the creature's own idle animation from its scene, and dresses it the way
# the world does: the element recolour its EnemyData asks for
# (BaseEnemy.element_material()) and its body tint. A new monster gets a
# picture by existing; nobody has to draw one.
#
# ITS SCENE, BY NAME. Every enemy scene under scene/enemy/ is named for its
# enemy_id, but for three: the base boss's scene is bossenemy.tscn, and both
# poison slimes are poisonslime.tscn, the small drawn with its "small"
# animations (the Elusion art pipeline: smallidledown, smallattackleft...).
# The suite checks every paying monster finds a scene and a picture.
#
# CACHED, and built a row at a time by the window: a scene's art is loaded the
# first time its row is drawn, and never again.
class_name EnemyPortraits
extends RefCounted


const ENEMY_DATA := "res://data/enemies/"
const ENEMY_SCENES := "res://scene/enemy/"

# enemy_id -> scene basename, where they differ.
const SCENE_FOR := {
	"boss": "bossenemy",
	"poisonslimelarge": "poisonslime",
	"poisonslimesmall": "poisonslime",
}
# enemy_id -> the prefix its animations carry in a scene shared with its other
# form.
const ANIM_PREFIX := {
	"poisonslimesmall": "small",
}
# The animation the picture is taken from, in order of preference.
const POSES := ["idledown", "walkdown", "idleleft", "walkleft"]

static var _roster: Array = []
static var _pictures: Dictionary = {}


static func roster() -> Array:
	"""Every monster that pays when killed, as {enemy_id, name, element},
	sorted by name. Read from data/enemies/ the way ItemRegistry reads items:
	ResourceLoader.list_directory(), so it works in an exported build."""
	if not _roster.is_empty():
		return _roster
	var out: Array = []
	for entry in ResourceLoader.list_directory(ENEMY_DATA):
		if not String(entry).ends_with(".tres"):
			continue
		var data: EnemyData = load(ENEMY_DATA + String(entry)) as EnemyData
		if data == null or data.enemy_id == "" or not data.grants_rewards:
			continue
		out.append({"enemy_id": data.enemy_id, "name": name_of(data), "element": int(data.element)})
	out.sort_custom(func(a, b): return String(a["name"]) < String(b["name"]))
	_roster = out
	return _roster


static func name_of(data: EnemyData) -> String:
	if data == null:
		return ""
	return data.display_name if data.display_name != "" else data.enemy_id.capitalize()


static func data_for(enemy_id: String) -> EnemyData:
	var path: String = ENEMY_DATA + enemy_id + ".tres"
	return load(path) as EnemyData if ResourceLoader.exists(path) else null


static func display_name(enemy_id: String) -> String:
	"""What a player reads for this monster - its own name, or a readable
	version of its id for one this build does not have (a newer server's)."""
	var data: EnemyData = data_for(enemy_id)
	return name_of(data) if data != null else enemy_id.capitalize()


static func scene_path(enemy_id: String) -> String:
	return ENEMY_SCENES + String(SCENE_FOR.get(enemy_id, enemy_id)) + ".tscn"


static func picture(enemy_id: String) -> Dictionary:
	"""{texture, material, modulate} for this monster, or {} when it has no
	scene or no art this build can find."""
	if _pictures.has(enemy_id):
		return _pictures[enemy_id]
	var out: Dictionary = {}
	var path: String = scene_path(enemy_id)
	var packed: PackedScene = load(path) as PackedScene if ResourceLoader.exists(path) else null
	if packed != null:
		# INSTANTIATED, NEVER ADDED: _ready() does not run, so nothing thinks,
		# spawns or makes a sound - it is only read and freed.
		var node: Node = packed.instantiate()
		out = _picture_of(node, enemy_id)
		node.free()
	_pictures[enemy_id] = out
	return out


static func _picture_of(node: Node, enemy_id: String) -> Dictionary:
	var sprite: AnimatedSprite2D = node.get_node_or_null("animatedsprite2d") as AnimatedSprite2D
	if sprite == null:
		for child in node.get_children():
			if child is AnimatedSprite2D:
				sprite = child
				break
	if sprite == null or sprite.sprite_frames == null:
		return {}
	var frames: SpriteFrames = sprite.sprite_frames
	var prefix: String = String(ANIM_PREFIX.get(enemy_id, ""))
	var pose: String = ""
	for wanted in POSES:
		if frames.has_animation(prefix + wanted) and frames.get_frame_count(prefix + wanted) > 0:
			pose = prefix + wanted
			break
	if pose == "":
		for anim in frames.get_animation_names():
			if String(anim).begins_with(prefix) and frames.get_frame_count(anim) > 0:
				pose = anim
				break
	if pose == "":
		return {}
	var data: EnemyData = data_for(enemy_id)
	var element: int = int(data.element) if data != null else Element.Type.NONE
	var override: Variant = node.get("element_override")
	if override is int and int(override) >= 0:
		element = int(override)
	# THE SAME TWO GATES AS BaseEnemy._should_recolour(): the resource asks for
	# a recolour (or the scene forces an element), and the element is not
	# physical's steel.
	var recolour: bool = (data != null and data.recolour_to_element) or (override is int and int(override) >= 0)
	return {
		"texture": cropped(frames.get_frame_texture(pose, 0)),
		"material": BaseEnemy.element_material(data, element) if recolour and element != Element.Type.NONE else null,
		"modulate": data.body_tint if data != null else Color.WHITE,
	}


static func cropped(texture: Texture2D) -> Texture2D:
	"""The frame cut down to the creature. A frame is a cell of the sheet, and
	a small sprite stands in the middle of a lot of nothing - drawn whole at 40
	pixels, a fire sprite was a speck. The cut is the frame's own opaque
	pixels (Image.get_used_rect()), as a region of the same atlas; a frame
	whose pixels cannot be read is drawn whole."""
	if texture == null:
		return null
	var image: Image = texture.get_image()
	if image == null or image.is_empty():
		return texture
	if image.is_compressed():
		image = image.duplicate()
		if image.decompress() != OK:
			return texture
	var used: Rect2i = image.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0 or used.size == image.get_size():
		return texture
	var cut := AtlasTexture.new()
	if texture is AtlasTexture:
		var atlas: AtlasTexture = texture
		cut.atlas = atlas.atlas
		cut.region = Rect2(atlas.region.position + Vector2(used.position), Vector2(used.size))
	else:
		cut.atlas = texture
		cut.region = Rect2(Vector2(used.position), Vector2(used.size))
	return cut


static func forget() -> void:
	"""For the suite: read everything again."""
	_roster = []
	_pictures.clear()
