# remoteplayer.gd - another player, drawn in your world.
#
# Presence (src/systems/presence.gd) makes one of these for everyone the
# presence server says is in your area, and tells it where they are and what
# they are doing about ten times a second. It is a PICTURE of a player, not a
# player: no body to collide with, no hurtbox, no script of theirs running, and
# not in the "player" group - everything that asks for "the player" means you,
# and finds you.
#
# WHAT IT DRAWS, from the class's own scene so it can never look different from
# the real thing: the body sprite with the same frames, offset and speed; the
# tank's aura rings when they are lit; a nameplate built like yours (the name in
# their chosen colour, the guild tag above it, the crown or MOD / DEV badge);
# and their pet, following behind.
#
# SMOOTH, NOT EXACT. Updates arrive ten times a second at best, so the body
# eases toward the newest position rather than jumping to it, and snaps only
# when the gap is too wide to be a walk (a teleport, a door).
#
# AND, SINCE 0.7.0, SOMETHING THE AREA'S MONSTERS CAN CHASE - on the game that
# runs them (monstersync.gd). It joins "remoteplayers", carries a "bodyshape"
# marker where the class's real body circle sits (a boss aims at the floor
# under you, not at your node's origin) and a `velocity` worked out from how
# it moves (a boss leads a running target). It is still not in "player", and
# still cannot be hurt here: a monster's shot at this body is hurting the real
# player on THEIR screen, where their game draws the same shot.
extends Node2D

# Preloaded rather than a class_name, as player.gd does; nametag.gd says why.
const NameTag := preload("res://src/shared/nametag.gd")


# How quickly the body closes on where it was last said to be. Per second, as
# an exponential: at 15 it covers 95% of a gap in a fifth of a second.
const FOLLOW_RATE := 15.0
# A gap wider than this is a jump, not a walk: snap.
const SNAP_DISTANCE := 160.0
# The pet trails this far behind, and follows more lazily.
const PET_TRAIL := 22.0
const PET_FOLLOW_RATE := 6.0
const PET_WALK_SPEED := 8.0
# The sprites a class scene may carry: the body, and the tank's two auras.
const BODY := "animatedsprite2d"
const EFFECTS := ["ring", "firering"]

# What the class scenes say about their sprites, read once per class: building
# a body must not instantiate a whole player scene every time somebody walks in.
static var _class_parts: Dictionary = {}
static var _body_offsets: Dictionary = {}
static var _pet_parts: Dictionary = {}
static var _plate_consts: Dictionary = {}

var user_id: int = -1
var class_id: String = ""
var display_name: String = ""
var role: String = "player"
var hue: Variant = null
var guild_tag: String = ""
var level: int = 1
var anim: String = "idledown"
var effects: Array = []
var pet_id: String = ""
# Whether their game shares monsters (presence "v" 2). One that does not is
# fighting its own, so the monsters here are not theirs to chase.
var shares: bool = false
# How fast they are moving, worked out from the positions that arrive - the
# same thing a CharacterBody2D's velocity says about the local player.
var velocity: Vector2 = Vector2.ZERO
var _target_at_msec: int = -1

var _target: Vector2 = Vector2.ZERO
var _placed: bool = false
var _body: AnimatedSprite2D = null
var _plate: Label = null
var _crown: TextureRect = null
var _badge: Label = null
var _plate_zoom: float = -1.0
var _pet: AnimatedSprite2D = null
var _pet_face: String = "down"


func _ready() -> void:
	if user_id >= 0:
		name = "remote_%d" % user_id
	add_to_group(&"remoteplayers")


func _exit_tree() -> void:
	# THE PET IS A SIBLING, so it sorts with the world rather than with this
	# body; it has to be taken away with it.
	if _pet != null and is_instance_valid(_pet):
		_pet.queue_free()
	_pet = null


# =============================================================================
# WHO, AND WHERE
# =============================================================================

func set_identity(entry: Dictionary) -> void:
	"""Who this is: a join entry from the presence server. Rebuilds the body
	when the class changes and repaints the plate."""
	user_id = int(entry.get("id", user_id))
	var new_class: String = str(entry.get("cls", ""))
	display_name = str(entry.get("name", ""))
	role = str(entry.get("role", "player"))
	hue = entry.get("hue")
	guild_tag = str(entry.get("guild", ""))
	level = int(entry.get("lvl", 1))
	shares = int(entry.get("v", 0)) >= 2
	if new_class != class_id or _body == null:
		class_id = new_class
		_build_body()
		_place_body_marker()
	_build_plate()
	_paint_plate()


func place(at: Vector2) -> void:
	"""Put it here now, no easing - where somebody is when they first appear."""
	_target = at
	position = at
	_placed = true
	if _pet != null:
		_pet.position = at + Vector2(0, -2)


func set_target(at: Vector2) -> void:
	if not _placed:
		place(at)
		return
	# THE SPEED IS THE GAP OVER THE TIME BETWEEN REPORTS, eased so one late
	# packet does not read as a sprint. A gap a walk could not make is a jump
	# (a door, a teleport) and says nothing about speed.
	var now: int = Time.get_ticks_msec()
	if _target_at_msec >= 0:
		var seconds: float = maxf(float(now - _target_at_msec) / 1000.0, 0.05)
		var step: Vector2 = (at - _target) / seconds
		velocity = Vector2.ZERO if (at - _target).length() > SNAP_DISTANCE else velocity.lerp(step, 0.6)
	_target_at_msec = now
	_target = at


func is_dying() -> bool:
	"""Playing their death: nothing to chase any more."""
	return anim.begins_with("death")


static func body_offset(cls: String) -> Vector2:
	"""Where the class's body circle sits from its origin - (0, 13) for a
	warrior, (-0.9, -16.2) for a tank - read once from the class scene."""
	if _body_offsets.has(cls):
		return _body_offsets[cls]
	var offset := Vector2.ZERO
	var path: String = "res://scene/characters/%s.tscn" % cls
	if cls != "" and ResourceLoader.exists(path):
		var packed: PackedScene = load(path) as PackedScene
		var instance: Node = packed.instantiate() if packed != null else null
		if instance != null:
			var shape: Node2D = instance.get_node_or_null("bodyshape") as Node2D
			if shape != null:
				offset = shape.position
			instance.free()
	_body_offsets[cls] = offset
	return offset


func _place_body_marker() -> void:
	# A MARKER, NOT A SHAPE. Named like the real one so boss aiming code that
	# asks get_node_or_null("bodyshape") finds the floor under them; it has no
	# collision, so nothing can bump into or hit it.
	var marker: Node2D = get_node_or_null("bodyshape") as Node2D
	if marker == null:
		marker = Node2D.new()
		marker.name = "bodyshape"
		add_child(marker)
	marker.position = body_offset(class_id)


func set_motion(new_anim: String, new_effects: Array, new_pet: String) -> void:
	"""What they are doing: the body's animation, the auras lit, the pet out."""
	if new_anim != anim or (_body != null and not _body.is_playing()):
		anim = new_anim
		_play_body()
	effects = new_effects.duplicate()
	for effect in EFFECTS:
		var sprite: AnimatedSprite2D = get_node_or_null(effect) as AnimatedSprite2D
		if sprite == null:
			continue
		var lit: bool = effects.has(effect)
		if lit and not sprite.visible:
			sprite.visible = true
			if sprite.sprite_frames != null and sprite.sprite_frames.has_animation(effect):
				sprite.play(effect)
			else:
				sprite.play()
		elif not lit and sprite.visible:
			sprite.visible = false
			sprite.stop()
	if new_pet != pet_id:
		pet_id = new_pet
		_build_pet()


func target() -> Vector2:
	return _target


func pet_sprite() -> AnimatedSprite2D:
	return _pet


func plate() -> Label:
	return _plate


# =============================================================================
# EVERY FRAME
# =============================================================================

func _process(delta: float) -> void:
	if position.distance_to(_target) > SNAP_DISTANCE:
		position = _target
	else:
		position = position.lerp(_target, 1.0 - exp(-delta * FOLLOW_RATE))
	if _plate != null and absf(_camera_zoom() - _plate_zoom) > 0.001:
		_place_plate()
	_follow_with_pet(delta)


# =============================================================================
# THE BODY
# =============================================================================

static func class_parts(cls: String) -> Array:
	"""[{name, frames, position, offset, scale, speed_scale, texture_filter,
	centered, z_index, animation}] for a class scene's body and auras, read once."""
	if _class_parts.has(cls):
		return _class_parts[cls]
	var parts: Array = []
	var path: String = "res://scene/characters/%s.tscn" % cls
	if cls != "" and ResourceLoader.exists(path):
		var packed: PackedScene = load(path) as PackedScene
		var instance: Node = packed.instantiate() if packed != null else null
		if instance != null:
			for part_name in [BODY] + EFFECTS:
				var sprite: AnimatedSprite2D = instance.get_node_or_null(part_name) as AnimatedSprite2D
				if sprite != null and sprite.sprite_frames != null:
					parts.append(_describe(part_name, sprite))
			instance.free()
	_class_parts[cls] = parts
	return parts


static func _describe(part_name: String, sprite: AnimatedSprite2D) -> Dictionary:
	return {
		"name": part_name, "frames": sprite.sprite_frames, "position": sprite.position,
		"offset": sprite.offset, "scale": sprite.scale, "speed_scale": sprite.speed_scale,
		"texture_filter": sprite.texture_filter, "centered": sprite.centered,
		"z_index": sprite.z_index, "animation": sprite.animation,
	}


static func _sprite_from(part: Dictionary) -> AnimatedSprite2D:
	var sprite := AnimatedSprite2D.new()
	sprite.name = str(part["name"])
	sprite.sprite_frames = part["frames"]
	sprite.position = part["position"]
	sprite.offset = part["offset"]
	sprite.scale = part["scale"]
	sprite.speed_scale = part["speed_scale"]
	sprite.texture_filter = part["texture_filter"]
	sprite.centered = part["centered"]
	sprite.z_index = part["z_index"]
	sprite.animation = part["animation"]
	return sprite


func _build_body() -> void:
	for part_name in [BODY] + EFFECTS:
		var old: Node = get_node_or_null(part_name)
		if old != null:
			remove_child(old)
			old.queue_free()
	_body = null
	for part in class_parts(class_id):
		var sprite: AnimatedSprite2D = _sprite_from(part)
		if sprite.name != BODY:
			sprite.visible = false
		add_child(sprite)
		if sprite.name == BODY:
			_body = sprite
			# Under the plate, which is added after.
			move_child(sprite, 0)
	if _body != null and not _body.animation_finished.is_connected(_on_body_finished):
		_body.animation_finished.connect(_on_body_finished)
	_play_body()
	_place_plate()


func _play_body() -> void:
	if _body == null or _body.sprite_frames == null:
		return
	var wanted: String = anim
	if not _body.sprite_frames.has_animation(wanted):
		# A class without that animation (a healer has no attack of its own):
		# stand facing the same way rather than show nothing.
		var facing: String = wanted.trim_prefix("attack").trim_prefix("hitflash")
		wanted = "idle" + facing if _body.sprite_frames.has_animation("idle" + facing) else "idledown"
	if _body.sprite_frames.has_animation(wanted):
		_body.play(wanted)


func _on_body_finished() -> void:
	# AN ATTACK GOES ON UNTIL THEY STOP. The game sends a state only when it
	# changes, so a player swinging again and again sends "attackdown" once;
	# the swing repeats here until something else arrives. Death holds its
	# last frame.
	if anim.begins_with("attack"):
		_play_body()


# =============================================================================
# THE NAMEPLATE, built like the player's own (player.gd, _setup_nameplate)
# =============================================================================

static func plate_constant(key: String, fallback: Variant) -> Variant:
	if _plate_consts.is_empty():
		var script: GDScript = load("res://src/characters/player.gd") as GDScript
		if script != null:
			_plate_consts = script.get_script_constant_map()
	return _plate_consts.get(key, fallback)


func _build_plate() -> void:
	if _plate != null:
		return
	var z: int = int(plate_constant("NAMEPLATE_Z", 60))
	_plate = Label.new()
	_plate.name = "nameplate"
	_plate.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_plate.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_plate.z_index = z
	_plate.add_theme_font_size_override("font_size", int(plate_constant("NAMEPLATE_FONT_SIZE", 12)))
	_plate.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_plate.add_theme_constant_override("outline_size", 5)
	add_child(_plate)

	var crown_texture: Texture2D = load(str(plate_constant("NAMEPLATE_CROWN_PATH", ""))) as Texture2D \
		if ResourceLoader.exists(str(plate_constant("NAMEPLATE_CROWN_PATH", ""))) else null
	if crown_texture != null:
		_crown = TextureRect.new()
		_crown.name = "nameplatecrown"
		_crown.texture = crown_texture
		_crown.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_crown.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_crown.size = crown_texture.get_size()
		_crown.z_index = z
		_crown.visible = false
		add_child(_crown)

	_badge = Label.new()
	_badge.name = "nameplatebadge"
	_badge.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge.z_index = z
	_badge.add_theme_font_size_override("font_size", int(plate_constant("NAMEPLATE_BADGE_FONT_SIZE", 9)))
	_badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_badge.add_theme_constant_override("outline_size", 4)
	_badge.visible = false
	add_child(_badge)


func _paint_plate() -> void:
	if _plate == null:
		return
	var text: String = display_name.strip_edges()
	var tag: String = Api.guild_tag_text(guild_tag)
	if text != "" and tag != "":
		text = "%s\n%s" % [tag, text]
	_plate.text = text
	_plate.visible = text != ""
	_plate.add_theme_color_override("font_color", NameTag.colour(hue))
	if _crown != null:
		_crown.visible = text != "" and NameTag.wears_crown(role)
	if _badge != null:
		var word: String = NameTag.badge(role)
		_badge.text = word
		_badge.visible = text != "" and word != ""
		if word != "":
			_badge.add_theme_color_override("font_color", NameTag.badge_colour(role))
	_place_plate()


func _camera_zoom() -> float:
	var camera: Camera2D = get_viewport().get_camera_2d() if is_inside_tree() else null
	if camera != null and absf(camera.zoom.x) > 0.01:
		return absf(camera.zoom.x)
	return float(plate_constant("NAMEPLATE_FALLBACK_ZOOM", 3.0))


func _head_y() -> float:
	var heads: Dictionary = plate_constant("NAMEPLATE_HEAD_Y", {})
	if heads.has(class_id):
		return float(heads[class_id])
	return float(plate_constant("NAMEPLATE_FALLBACK_HEAD_Y", -40.0))


func _place_plate() -> void:
	if _plate == null:
		return
	_plate_zoom = _camera_zoom()
	var plate_scale: Vector2 = Vector2.ONE / _plate_zoom
	_plate.scale = plate_scale
	_plate.size = Vector2.ZERO
	var wanted: Vector2 = _plate.get_combined_minimum_size()
	var text_w: float = wanted.x * plate_scale.x
	var text_h: float = wanted.y * plate_scale.y
	var bottom: float = _head_y() - float(plate_constant("NAMEPLATE_GAP", 3.0))
	_plate.position = Vector2(-text_w * 0.5, bottom - text_h)
	var gap: float = float(plate_constant("NAMEPLATE_CROWN_GAP", 1.0)) * plate_scale.y
	if _crown != null and _crown.visible:
		_crown.scale = plate_scale
		var crown_size: Vector2 = _crown.size * plate_scale
		_crown.position = Vector2(-crown_size.x * 0.5, bottom - text_h - gap - crown_size.y)
	if _badge != null and _badge.visible:
		_badge.scale = plate_scale
		_badge.size = Vector2.ZERO
		var badge_size: Vector2 = _badge.get_combined_minimum_size() * plate_scale
		_badge.position = Vector2(-badge_size.x * 0.5, bottom - text_h - gap - badge_size.y)


# =============================================================================
# THE PET
# =============================================================================

static func pet_parts(item_id: String) -> Dictionary:
	"""The pet scene's body sprite, described, or {} for no such pet."""
	if _pet_parts.has(item_id):
		return _pet_parts[item_id]
	var part: Dictionary = {}
	var scene: PackedScene = PetController.pet_scene_for(item_id) if item_id != "" else null
	var instance: Node = scene.instantiate() if scene != null else null
	if instance != null:
		var sprite: AnimatedSprite2D = instance.get_node_or_null(BODY) as AnimatedSprite2D
		if sprite != null and sprite.sprite_frames != null:
			part = _describe("remotepet", sprite)
			part["root_scale"] = (instance as Node2D).scale if instance is Node2D else Vector2.ONE
		instance.free()
	_pet_parts[item_id] = part
	return part


func _build_pet() -> void:
	if _pet != null and is_instance_valid(_pet):
		_pet.queue_free()
	_pet = null
	if pet_id == "":
		return
	var part: Dictionary = pet_parts(pet_id)
	if part.is_empty() or get_parent() == null:
		return
	_pet = _sprite_from(part)
	_pet.scale = part["scale"] * part.get("root_scale", Vector2.ONE)
	_pet.name = "remotepet_%d" % user_id
	_pet.position = position + Vector2(0, -2)
	# A SIBLING, so the world's Y-sort puts it in front of or behind things by
	# where it stands, not by where its owner does.
	get_parent().add_child.call_deferred(_pet)
	_play_pet("idle")


func _follow_with_pet(delta: float) -> void:
	if _pet == null or not is_instance_valid(_pet):
		return
	var facing_vec: Vector2 = Facing.to_vec(_facing_of(anim))
	var anchor: Vector2 = position - facing_vec * PET_TRAIL
	var before: Vector2 = _pet.position
	_pet.position = before.lerp(anchor, 1.0 - exp(-delta * PET_FOLLOW_RATE))
	var step: Vector2 = _pet.position - before
	if delta > 0.0 and step.length() / delta > PET_WALK_SPEED:
		_pet_face = Facing.from_vec(step)
		_play_pet("walk")
	else:
		_play_pet("idle")


func _play_pet(kind: String) -> void:
	if _pet == null or _pet.sprite_frames == null:
		return
	var wanted: String = kind + _pet_face
	if _pet.sprite_frames.has_animation(wanted) and _pet.animation != wanted:
		_pet.play(wanted)
	elif not _pet.is_playing() and _pet.sprite_frames.has_animation(wanted):
		_pet.play(wanted)


static func _facing_of(anim_name: String) -> String:
	for direction in ["down", "up", "left", "right"]:
		if anim_name.ends_with(direction):
			return direction
	return "down"
