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
# PLAYED BACK, NOT CHASED (0.19.0). Steps arrive about ten times a second, and
# not evenly: the game sends on its clock, the server passes them on on its
# own, and the network adds its own wait. This body used to ease toward the
# newest step - fast just after one arrived, slowing as it closed in, waiting
# for the next - and the owner, running past the first other player he played
# with: "i noticed some lag wobble". Now every step is kept with the time on
# THEIR clock it was taken (the state's "ts"), and the body is drawn
# PLAYBACK_DELAY behind the newest, moving between the two steps either side
# of that moment at the speed they really walked. So it is a fifth of a second
# behind where they are, and it moves evenly. A step too far from the last to
# be a walk (a door, a teleport) is a jump, made when the playback reaches it.
# What they are doing - the animation, the aura, the pet - changes when the
# playback reaches the step that says so, so the walk stops where they stopped.
#
# AND THEIR ATTACKS (0.19.0). The presence server passes on a picture of every
# attack they make, with the same clock; hear_attacks() holds each until the
# playback reaches it, and remoteattacks.gd spawns it - a meteor falls as this
# body finishes the cast. A thrown axe flies home to this body (`axe`).
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


# PLAYED BACK (see the top): how far behind their newest step the body is
# drawn. Two of the server's ticks, so a step that waited for one, or a late
# one, has arrived before the playback needs it.
const PLAYBACK_DELAY := 0.2
# How often their game sends a step while they move.
const STEP_SECONDS := 0.1
# Two steps further apart than this were a stop and a start: their game sends
# nothing while they stand still, so the walk began a step before the second.
const PAUSE_SECONDS := 0.35
# Steps kept at most - a couple of seconds of them.
const MAX_STEPS := 40
# THE LINK BETWEEN THEIR CLOCK AND OURS is how far ours runs ahead: the least
# any reading of theirs took to get here over the last CLOCK_WINDOW seconds -
# the quickest the road has been lately. When that moves by more than
# CLOCK_DEADBAND the link follows it at CLOCK_SLEW seconds a second, so the
# playback runs a little fast or slow for a moment rather than skipping; a
# change bigger than CLOCK_SNAP (a first guess from a stale join, a road that
# changed) is made at once. Inside the deadband nothing moves: measured
# between two games, the quickest road wanders by a few milliseconds as old
# readings leave the window, and following every one of those wanders made
# the walk speed up and slow down by a tenth.
const CLOCK_WINDOW := 4.0
const CLOCK_DEADBAND := 0.03
const CLOCK_SLEW := 0.05
const CLOCK_SNAP := 0.5
# Their clock going back further than this is their game starting again: the
# playback starts again with it.
const CLOCK_RESTART := 1.0
# Attack pictures waiting for the playback, at most.
const MAX_ATTACKS_WAITING := 64
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
# The clock the playback reads, in seconds: the engine's, unless the suite sets
# one (any value of nought or more) to step through a playback by hand.
static var clock_override: float = -1.0

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
# The picture of their Double Axe while it is out (remoteattacks.gd).
var axe: Node = null

var _target: Vector2 = Vector2.ZERO
# THE PLAYBACK: [their seconds, position, animation, effects, pet] for every
# step not yet played past, oldest first; how far our clock runs ahead of
# theirs, and when that was last learned; the step whose motion is showing;
# and the attack pictures waiting, as [their seconds, attack].
var _steps: Array = []
var _clock_gap: float = 0.0
var _clock_aim: float = 0.0
var _clock_known: bool = false
var _clock_moved_at: float = 0.0
var _clock_settling: bool = false
var _clock_seen: Array = []   # [our seconds, how far ahead ours was], the last CLOCK_WINDOW
var _shown_step: float = -INF
var _waiting: Array = []
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


func place(at: Vector2, ts: int = -1) -> void:
	"""Put it here now, no easing - where somebody is when they first appear.
	`ts` is their clock at that moment, when the join carried it: the playback
	starts from there."""
	_target = at
	position = at
	_placed = true
	# A new start: what was learned of their clock is forgotten with it.
	_clock_known = false
	_clock_seen = []
	_steps = [[_their_time(ts), at, anim, effects.duplicate(), pet_id]]
	_shown_step = float(_steps[0][0])
	velocity = Vector2.ZERO
	if _pet != null:
		_pet.position = at + Vector2(0, -2)


func set_target(at: Vector2, ts: int = -1) -> void:
	"""A step to here, doing what they were already doing."""
	push_step(at, anim, effects, pet_id, ts)


func push_step(at: Vector2, new_anim: String, new_effects: Array, new_pet: String, ts: int = -1) -> void:
	"""A step from the presence server: where they are and what they are doing,
	at `ts` on their clock (-1: a game that sends none, timed by when the step
	arrived here). Played back PLAYBACK_DELAY behind the newest - see the top."""
	if not _placed:
		place(at, ts)
		set_motion(new_anim, new_effects, new_pet)
		return
	var t: float = _their_time(ts)
	if not _steps.is_empty():
		var last: Array = _steps.back()
		var last_t: float = float(last[0])
		if t < last_t - CLOCK_RESTART:
			# Their game started again: so does the playback, from here.
			place(at, ts)
			set_motion(new_anim, new_effects, new_pet)
			return
		if t <= last_t:
			return   # an older step than one already here
		var from: Vector2 = last[1]
		if t - last_t > PAUSE_SECONDS:
			# They stood still, then set off: from where they stood, a step ago.
			_steps.append([t - STEP_SECONDS, from, new_anim, new_effects.duplicate(), new_pet])
			last_t = t - STEP_SECONDS
		# THE SPEED IS THE STEP OVER THE TIME BETWEEN THEM, on their clock, eased
		# so one odd step does not read as a sprint. A gap a walk could not make is
		# a jump (a door, a teleport) and says nothing about speed.
		var seconds: float = maxf(t - last_t, 0.05)
		velocity = Vector2.ZERO if (at - from).length() > SNAP_DISTANCE \
			else velocity.lerp((at - from) / seconds, 0.6)
	_steps.append([t, at, new_anim, new_effects.duplicate(), new_pet])
	while _steps.size() > MAX_STEPS:
		_steps.pop_front()
	_target = at


func hear_attacks(attacks: Array) -> void:
	"""Attack pictures from the presence server, [[kind, ts, ox, oy, tx, ty,
	delay, flags]]: each spawned (remoteattacks.gd) when the playback reaches
	the moment they made it."""
	for attack in attacks:
		if not (attack is Array) or (attack as Array).size() < 8:
			continue
		if not RemoteAttacks.KINDS.has(str(attack[0])):
			continue
		_waiting.append([_their_time(int(attack[1])), attack])
	_waiting.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
	while _waiting.size() > MAX_ATTACKS_WAITING:
		_waiting.pop_front()


func attacks_waiting() -> int:
	return _waiting.size()


static func clock() -> float:
	"""The playback's clock, in seconds."""
	return clock_override if clock_override >= 0.0 else float(Time.get_ticks_usec()) / 1000000.0


func playhead() -> float:
	"""The moment on their clock the body is drawn at: their newest, less
	PLAYBACK_DELAY, as near as the link between the clocks says."""
	return clock() - _clock_gap - PLAYBACK_DELAY


func _their_time(ts: int) -> float:
	# A reading of their clock, in their seconds, and what it says about the
	# link (see CLOCK_WINDOW). No reading - a game from before 0.19.0 - is
	# timed by when it arrived here: their clock is ours.
	var here: float = clock()
	if ts < 0:
		_learn_clock(here, 0.0)
		return here
	var t: float = float(ts) / 1000.0
	_learn_clock(here, here - t)
	return t


func _learn_clock(here: float, ahead: float) -> void:
	_clock_seen.append([here, ahead])
	while _clock_seen.size() > 1 and float(_clock_seen[0][0]) < here - CLOCK_WINDOW:
		_clock_seen.pop_front()
	var aim: float = INF
	for seen in _clock_seen:
		aim = minf(aim, float(seen[1]))
	_clock_aim = aim
	if not _clock_known or absf(aim - _clock_gap) > CLOCK_SNAP:
		_clock_gap = aim
		_clock_moved_at = here
		_clock_settling = false
	_clock_known = true


func _settle_clock() -> void:
	# Out of the deadband, the link moves to what the window says, CLOCK_SLEW
	# at a time, all the way; inside it, it stays.
	var here: float = clock()
	if absf(_clock_aim - _clock_gap) > CLOCK_DEADBAND:
		_clock_settling = true
	if _clock_settling:
		_clock_gap = move_toward(_clock_gap, _clock_aim, CLOCK_SLEW * maxf(here - _clock_moved_at, 0.0))
		_clock_settling = absf(_clock_aim - _clock_gap) > 0.0005
	_clock_moved_at = here


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
	"""Where their newest step put them - ahead of where the body is drawn."""
	return _target


func _on_axe_caught() -> void:
	# spinningaxe.gd calls this as the picture of their axe reaches this body.
	axe = null
	Audio.play_at("axe_catch", global_position)


func pet_sprite() -> AnimatedSprite2D:
	return _pet


func plate() -> Label:
	return _plate


# =============================================================================
# EVERY FRAME
# =============================================================================

func _process(delta: float) -> void:
	_settle_clock()
	_play_back()
	_fire_due_attacks()
	if _plate != null and absf(_camera_zoom() - _plate_zoom) > 0.001:
		_place_plate()
	_follow_with_pet(delta)


func _play_back() -> void:
	if _steps.is_empty():
		return
	var head: float = playhead()
	# Every step the playback is past goes, but the last of them: it is where
	# the body is coming from.
	while _steps.size() >= 2 and float(_steps[1][0]) <= head:
		_steps.pop_front()
	var from: Array = _steps[0]
	var at: Vector2 = from[1]
	if _steps.size() >= 2 and head > float(from[0]):
		var to: Array = _steps[1]
		var to_at: Vector2 = to[1]
		var span: float = float(to[0]) - float(from[0])
		# Too far to walk: stay until the playback reaches it, then jump.
		if span > 0.0 and at.distance_to(to_at) <= SNAP_DISTANCE:
			at = at.lerp(to_at, clampf((head - float(from[0])) / span, 0.0, 1.0))
	position = at
	if head >= float(from[0]) and float(from[0]) != _shown_step:
		_shown_step = float(from[0])
		set_motion(str(from[2]), from[3], str(from[4]))


func _fire_due_attacks() -> void:
	if _waiting.is_empty():
		return
	var head: float = playhead()
	while not _waiting.is_empty() and float(_waiting[0][0]) <= head:
		var due: Array = _waiting.pop_front()
		RemoteAttacks.fire(self, due[1])


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
