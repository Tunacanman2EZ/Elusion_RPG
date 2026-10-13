# healaura.gd - the healer's aura: a pillar of light comes down, and the ring
# it leaves on the floor heals whoever stands in it and burns the monsters
# (0.40.0).
#
# The owner sent the art (art/maincharacter/healaura.png, 25 frames of 64 x 64
# at 70 ms each, his "healer ff"): a green pillar slamming down, a ring on the
# ground with sparks rising off it, and white motes as it fades. Of it: "the
# character will not be there but will turn into an aoe", and asked who it
# should touch, "Heal players + hurt monsters". The healer drops one with a
# right-click (healer.gd, THE AURA).
#
# HIS ART AS HE DREW IT: its own size, every pixel his. The first cut drew it
# at 2x and carried the pillar's top row on up the screen, and the owner: "i
# can tell the image was streched keep it original size". The ring is 45 x 19
# px round the feet, as in the art; the blobs carry the heal further out.
# Unshaded, so it shows in a dark crypt.
#
# IN THE SKY, THEN ON THE FLOOR. While the pillar falls (frames 0-3) it is
# drawn over everyone (SKY_Z, as Blast is); from LANDS_ON it is a ring on the
# floor, drawn under whoever stands in it (FLOOR_Z, as a crater's glow is).
#
# WHO IS HEALED, decided as the beam lands (LANDS_ON):
#   inside the ring     the ring heals them: TICK_FRAMES - its frames, the half
#                       second it is brightest - each heal_each(), together
#                       HEAL_SHARE of their own maximum, while they stay in it.
#   outside, near       the owner: "green orbs spawn around the circle and each
#                       blob travels to players outside of the circle giving
#                       them hp". BLOBS green orbs lift off the ring and fly to
#                       the players outside it within SEEK_RANGE of its middle
#                       (healblob.gd), shared out in turn; the ones a player
#                       gets heal HEAL_SHARE between them. With nobody out
#                       there they lift off and fade.
# Every game heals its own player and nobody else's: a picture of somebody
# else's aura (remoteattacks.gd) heals you, inside or by its blobs, as your own
# does, and sends blobs to the pictures of the others for you to see. The
# presence server writes HEAL_SHARE down for everyone it saw within SEEK_RANGE
# (presence.py, THE AURA'S HEALS), so the server's healing check knows where
# the health came from.
#
# THE BURN, on the same ticks: each monster inside takes `damage` (the
# healer's, its own aura only - a picture's touches nothing), through
# take_damage(), so a monster this game does not run is hit where it is run.
#
# INSIDE is the ring as drawn - an ellipse, RADII round the node, REACH_PAD
# past the line - measured at the feet: a player's aim_ring_feet(), a
# monster's "bodyshape".
#
# THE BEAM, DRESSED. The owner: "is there any way we can make the beam look
# better?" - and of four ways offered, "Fade the top", "Glow + light" and
# "Falling sparkles". Each is its own node beside his frames, drawn here; his
# pixels stay as he drew them:
#   the shaft      SHAFT_HEIGHT px of light standing on the frame's top edge
#                  while the pillar falls, each column in the colour of the
#                  pillar's top row there, fading to nothing going up in a
#                  4 x 4 dither - so the beam comes out of the sky instead of
#                  ending in a lid. Its own texture (shaft_texture()): nothing
#                  of his is stretched.
#   the glow       a green halo, added, round the shaft and the falling
#                  pillar - fading in at the top as the shaft does, its foot
#                  following the pillar's down the frames (PILLAR_FOOT,
#                  measured off the art) - and round the ring once it lands,
#                  fading over RING_GLOW_FRAMES
#   the light      in a dark area (AuraBurn.scene_is_dark(): a CanvasModulate),
#                  a green PointLight2D rising as the beam falls and fading
#                  after it lands (light_energy()) - lighting the floor and
#                  whoever stands near. Switched with `enabled`, never
#                  `visible`, as the tank's is: Settings' simple lighting hides
#                  lights with `visible`
#   the sparkles   white and green pixels streaming down the shaft and the
#                  pillar while it falls, gone with it as it lands
class_name HealAura
extends Node2D


const SHEET := "res://art/maincharacter/healaura.png"
const FRAME_SIZE := 64
const FRAMES := 25
# The artist's timing: 70 ms a frame.
const FPS := 1000.0 / 70.0
# Where the ring's middle is drawn in a frame, from the frame's middle, in the
# art's pixels - x 10 to 54, y 40 to 58, so (0.5, 17.5), taken to the whole
# pixel so the frame lands on whole pixels.
const RING_FROM_MIDDLE := Vector2(0.0, 17.0)
# The ring's half-width and half-height.
const RADII := Vector2(22.0, 9.0)
const REACH_PAD := 4.0
# The pillar lands on this frame.
const LANDS_ON := 4
const TICK_FRAMES: Array[int] = [4, 6, 8, 10]
# All the ticks together - or all the blobs one player gets - heal this share
# of the healed one's maximum health.
const HEAL_SHARE := 0.25
const BLOBS := 8
# How far from the ring's middle the blobs go looking.
const SEEK_RANGE := 200.0
const SKY_Z := 5
const FLOOR_Z := -1
# THE BEAM, DRESSED. Where the pillar is in the art: from x PILLAR_LEFT,
# PILLAR_WIDTH across, from the frame's top; its sides end on row PILLAR_FOOT
# in each falling frame, and its rounded foot comes on below.
const PILLAR_LEFT := 10
const PILLAR_WIDTH := 45
const PILLAR_FOOT: Array[int] = [12, 30, 39, 50]
# The shaft's colour if the art will not load.
const PILLAR_COLOUR := Color8(181, 247, 102, 159)
const SHAFT_HEIGHT := 96
const GLOW_COLOUR := Color(0.6, 1.0, 0.4)
const GLOW_SPREAD := 6
const GLOW_ALPHA := 0.22
const RING_GLOW_FRAMES := 10
const LIGHT_COLOUR := Color(0.55, 1.0, 0.45)
const LIGHT_ENERGY := 1.0
# How far the light reaches round the ring, and how flat it lies.
const LIGHT_REACH := 70.0
const LIGHT_FLAT := 0.6
const LIGHT_TEXTURE := preload("res://scene/crypt/lightgradient.tres")
# The light is out by this frame.
const LIGHT_OUT_ON := 16
const SPARKLES := 28

# Each monster inside takes this much a tick; 0 for none (a picture).
var damage: int = 0
var element: int = Element.Type.NONE
var cosmetic: bool = false
# Who the heal is for: this game's own player - or, for the tests, whoever
# they set.
var heal_target: Node = null
var ticks_done: int = 0
var healed: int = 0
# The blobs sent as the beam landed, for the tests.
var blobs: Array[HealBlob] = []

# Whether this area is dark, for the light - set as it is made; the tests set it.
var dark: bool = false
var shaft: Sprite2D = null
var beam_glow: Sprite2D = null
var ring_glow: Sprite2D = null
var light: PointLight2D = null
var sparkles: CPUParticles2D = null

var _picture: AnimatedSprite2D = null
var _last_ticked: int = -1
var _landed: bool = false
# Whether this game's own player was inside the ring as the beam landed: the
# ring heals them, not the blobs.
var _me_inside: bool = false

static var _frames: SpriteFrames = null
static var _shaft: ImageTexture = null
static var _beam_glow: ImageTexture = null
static var _ring_glow: ImageTexture = null


static func drop(parent: Node, at: Vector2, tick_damage: int = 0, is_cosmetic: bool = false) -> HealAura:
	"""An aura with its ring's middle at `at` (in the world). Frees itself."""
	var aura := HealAura.new()
	aura.name = "healaura"
	aura.damage = 0 if is_cosmetic else maxi(tick_damage, 0)
	aura.cosmetic = is_cosmetic
	parent.add_child(aura)
	aura.global_position = at
	aura.reset_physics_interpolation()
	return aura


static func sprite_frames() -> SpriteFrames:
	"""The 25 frames, cut from the sheet once."""
	if _frames != null:
		return _frames
	var sheet: Texture2D = load(SHEET) as Texture2D
	var frames := SpriteFrames.new()
	frames.add_animation(&"aura")
	frames.set_animation_loop(&"aura", false)
	frames.set_animation_speed(&"aura", FPS)
	if sheet != null:
		for i in FRAMES:
			var cut := AtlasTexture.new()
			cut.atlas = sheet
			cut.region = Rect2(i * FRAME_SIZE, 0, FRAME_SIZE, FRAME_SIZE)
			frames.add_frame(&"aura", cut)
	_frames = frames
	return frames


static func heal_each(max_hp: int) -> int:
	"""One tick's heal for a maximum of `max_hp`."""
	return maxi(1, ceili(float(max_hp) * HEAL_SHARE / float(TICK_FRAMES.size())))


func _ready() -> void:
	z_as_relative = false
	z_index = SKY_Z
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_picture = AnimatedSprite2D.new()
	_picture.name = "picture"
	_picture.sprite_frames = sprite_frames()
	# The ring's middle on the node: the frame drawn up by where it sits in it.
	_picture.offset = -RING_FROM_MIDDLE
	var unshaded := CanvasItemMaterial.new()
	unshaded.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_picture.material = unshaded
	add_child(_picture)
	_dress_up()
	_picture.frame_changed.connect(_on_frame_changed)
	_picture.animation_finished.connect(queue_free)
	_picture.play(&"aura")


func _on_frame_changed() -> void:
	reached(_picture.frame)


# =============================================================================
# THE BEAM, DRESSED - see the header
# =============================================================================

static func frame_top_left() -> Vector2:
	"""Where the frame's top-left corner is, from the node."""
	return -RING_FROM_MIDDLE - Vector2(FRAME_SIZE, FRAME_SIZE) / 2.0


static func pillar_top_left() -> Vector2:
	return frame_top_left() + Vector2(PILLAR_LEFT, 0.0)


func _dress_up() -> void:
	dark = AuraBurn.scene_is_dark(get_tree()) if is_inside_tree() else dark
	var added := CanvasItemMaterial.new()
	added.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	added.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var unshaded := CanvasItemMaterial.new()
	unshaded.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	# The halo first, so the pillar is drawn over it.
	beam_glow = Sprite2D.new()
	beam_glow.name = "beamglow"
	beam_glow.centered = false
	beam_glow.texture = beam_glow_texture()
	beam_glow.region_enabled = true
	beam_glow.position = pillar_top_left() - Vector2(GLOW_SPREAD, SHAFT_HEIGHT)
	beam_glow.material = added
	beam_glow.modulate = GLOW_COLOUR
	add_child(beam_glow)
	move_child(beam_glow, 0)
	ring_glow = Sprite2D.new()
	ring_glow.name = "ringglow"
	ring_glow.texture = ring_glow_texture()
	ring_glow.material = added
	ring_glow.modulate = GLOW_COLOUR
	ring_glow.z_index = -1
	ring_glow.visible = false
	add_child(ring_glow)
	shaft = Sprite2D.new()
	shaft.name = "shaft"
	shaft.centered = false
	shaft.texture = shaft_texture()
	shaft.material = unshaded
	shaft.position = pillar_top_left() - Vector2(0.0, SHAFT_HEIGHT)
	add_child(shaft)
	light = PointLight2D.new()
	light.name = "light"
	light.color = LIGHT_COLOUR
	light.texture = LIGHT_TEXTURE
	# The texture is 256 px across.
	light.texture_scale = LIGHT_REACH * 2.0 / 256.0
	light.scale = Vector2(1.0, LIGHT_FLAT)
	add_child(light)
	sparkles = CPUParticles2D.new()
	sparkles.name = "sparkles"
	sparkles.amount = SPARKLES
	sparkles.lifetime = 0.45
	sparkles.lifetime_randomness = 0.3
	sparkles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	# Over the shaft, the pillar's width less its faint edges; already
	# streaming as the beam appears.
	sparkles.emission_rect_extents = Vector2(PILLAR_WIDTH / 2.0 - 6.0, SHAFT_HEIGHT / 2.0)
	sparkles.position = pillar_top_left() + Vector2(PILLAR_WIDTH / 2.0, -SHAFT_HEIGHT / 2.0)
	sparkles.preprocess = 0.45
	sparkles.direction = Vector2.DOWN
	sparkles.spread = 0.0
	sparkles.gravity = Vector2.ZERO
	sparkles.initial_velocity_min = 140.0
	sparkles.initial_velocity_max = 200.0
	sparkles.color_ramp = sparkle_colours()
	sparkles.material = unshaded
	sparkles.z_index = 1
	sparkles.emitting = true
	add_child(sparkles)
	_dress(0)


func _dress(frame: int) -> void:
	"""The dressing on `frame`: the shaft, the glow and the sparkles while it
	falls, the ring's glow after, the light throughout."""
	var falling: bool = frame < LANDS_ON
	shaft.visible = falling
	beam_glow.visible = falling
	if falling:
		# Down to where the pillar's sides end in this frame.
		var foot: float = frame_top_left().y + PILLAR_FOOT[clampi(frame, 0, PILLAR_FOOT.size() - 1)] + 1.0
		beam_glow.region_rect = Rect2(0.0, 0.0, beam_glow.texture.get_width(), foot - beam_glow.position.y)
	# Gone with the beam: no sparkles left in an empty sky.
	sparkles.emitting = falling
	sparkles.visible = falling
	ring_glow.visible = not falling and frame < LANDS_ON + RING_GLOW_FRAMES
	if ring_glow.visible:
		ring_glow.modulate.a = 1.0 - float(frame - LANDS_ON) / float(RING_GLOW_FRAMES)
	var energy: float = light_energy(frame)
	light.enabled = dark and energy > 0.0
	light.energy = LIGHT_ENERGY * energy


static func light_energy(frame: int) -> float:
	"""How bright the light is on `frame`, of its most: rising as the beam
	falls, full as it lands, out by LIGHT_OUT_ON."""
	if frame < LANDS_ON:
		return 0.4 + 0.6 * float(frame) / float(LANDS_ON)
	return clampf(float(LIGHT_OUT_ON - frame) / float(LIGHT_OUT_ON - LANDS_ON), 0.0, 1.0)


static func shaft_texture() -> ImageTexture:
	"""The shaft: PILLAR_WIDTH x SHAFT_HEIGHT, each column in the colour of the
	pillar's top row there and a share of its alpha - all of it at the foot,
	where it meets the art, none at the top - in quarters, with a 4 x 4 dither
	between, on whole pixels."""
	if _shaft != null:
		return _shaft
	var columns: Array[Color] = []
	var sheet: Texture2D = load(SHEET) as Texture2D
	var art: Image = sheet.get_image() if sheet != null else null
	if art != null and art.is_compressed():
		art.decompress()
	for x in PILLAR_WIDTH:
		columns.append(art.get_pixel(PILLAR_LEFT + x, 0) if art != null else PILLAR_COLOUR)
	var bayer: Array[int] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
	var image := Image.create(PILLAR_WIDTH, SHAFT_HEIGHT, false, Image.FORMAT_RGBA8)
	for y in SHAFT_HEIGHT:
		# 0 at the top, 1 at the foot, rising slowly then faster.
		var up: float = pow(float(y + 1) / float(SHAFT_HEIGHT), 1.6) * 4.0
		for x in PILLAR_WIDTH:
			var threshold: float = (float(bayer[(y % 4) * 4 + (x % 4)]) + 0.5) / 16.0
			var share: float = (floorf(up) + (1.0 if up - floorf(up) > threshold else 0.0)) / 4.0
			if share > 0.0:
				var colour: Color = columns[x]
				colour.a *= minf(share, 1.0)
				image.set_pixel(x, y, colour)
	_shaft = ImageTexture.create_from_image(image)
	return _shaft


static func beam_glow_texture() -> ImageTexture:
	"""The halo round the shaft and the pillar: full across the pillar, gone
	GLOW_SPREAD px past each side, in steps; from the shaft's top - where it
	fades in as the shaft does, in the same dither - to the frame's foot. Shown
	down to the pillar's foot (region_rect); never scaled."""
	if _beam_glow != null:
		return _beam_glow
	var width: int = PILLAR_WIDTH + GLOW_SPREAD * 2
	var height: int = SHAFT_HEIGHT + FRAME_SIZE
	var bayer: Array[int] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	for y in height:
		var up: float = pow(minf(float(y + 1) / float(SHAFT_HEIGHT), 1.0), 1.6) * 4.0
		for x in width:
			var out: int = maxi(GLOW_SPREAD - x, x - (PILLAR_WIDTH + GLOW_SPREAD - 1))
			var across: float = 1.0 if out <= 0 else floorf((1.0 - float(out) / float(GLOW_SPREAD + 1)) * 3.0) / 3.0
			var threshold: float = (float(bayer[(y % 4) * 4 + (x % 4)]) + 0.5) / 16.0
			var down: float = minf((floorf(up) + (1.0 if up - floorf(up) > threshold else 0.0)) / 4.0, 1.0)
			if across > 0.0 and down > 0.0:
				image.set_pixel(x, y, Color(1.0, 1.0, 1.0, across * down * GLOW_ALPHA))
	_beam_glow = ImageTexture.create_from_image(image)
	return _beam_glow


static func ring_glow_texture() -> Texture2D:
	"""The floor lit round the ring: an ellipse a little past it, in pixel
	bands with a 2 x 2 dither, brightest at the ring's line."""
	if _ring_glow != null:
		return _ring_glow
	var half := Vector2i(ceili(RADII.x * 1.3), ceili(RADII.y * 1.3))
	var image := Image.create(half.x * 2, half.y * 2, false, Image.FORMAT_RGBA8)
	var bayer: Array[float] = [0.0, 0.5, 0.75, 0.25]
	for y in half.y * 2:
		for x in half.x * 2:
			var d: float = Vector2((x + 0.5 - half.x) / RADII.x, (y + 0.5 - half.y) / RADII.y).length()
			var level: float = (lerpf(0.4, 1.0, d) if d <= 1.0 else maxf(1.0 - (d - 1.0) / 0.3, 0.0)) * 5.0
			var stepped: float = floorf(level + bayer[(y % 2) * 2 + (x % 2)]) / 5.0
			if stepped > 0.0:
				image.set_pixel(x, y, Color(1.0, 1.0, 1.0, minf(stepped, 1.0) * GLOW_ALPHA * 1.4))
	_ring_glow = ImageTexture.create_from_image(image)
	return _ring_glow


static func sparkle_colours() -> Gradient:
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	ramp.colors = PackedColorArray([Color(1.0, 1.0, 1.0), Color(0.82, 1.0, 0.6), Color(0.6, 1.0, 0.4, 0.0)])
	return ramp


func reached(frame: int) -> void:
	"""What happens on `frame`: the dressing, the landing, and the ticks."""
	if shaft != null:
		_dress(frame)
	if frame >= LANDS_ON:
		z_index = FLOOR_Z
		if not _landed:
			_landed = true
			land()
	if frame in TICK_FRAMES and frame != _last_ticked:
		_last_ticked = frame
		tick()


func my_player() -> Node2D:
	"""This game's own player - or whoever the tests set."""
	if heal_target != null:
		return heal_target as Node2D
	if is_inside_tree():
		return get_tree().get_first_node_in_group(&"player") as Node2D
	return null


static func can_be_healed(body: Node) -> bool:
	return body is Node2D and body.has_method(&"heal") and not bool(body.get("is_dying"))


func land() -> void:
	"""The beam is down: who the ring heals, and the blobs for everyone
	outside it."""
	var me: Node2D = my_player()
	_me_inside = me != null and inside(feet_of(me))
	var others: Array[Node2D] = []
	if me != null and not _me_inside and can_be_healed(me):
		others.append(me)
	if is_inside_tree():
		for picture in get_tree().get_nodes_in_group(&"remoteplayers"):
			if picture is Node2D and picture != me:
				others.append(picture as Node2D)
	var out: Array[Node2D] = outside_near(others)
	var shares: Dictionary = {}
	for i in BLOBS:
		if not out.is_empty():
			var whom: Node2D = out[i % out.size()]
			shares[whom] = int(shares.get(whom, 0)) + 1
	for i in BLOBS:
		var at: Vector2 = global_position + ring_point(i)
		var whom: Node2D = out[i % out.size()] if not out.is_empty() else null
		var mine: bool = whom != null and whom == me
		var amount: int = 0
		if mine:
			amount = maxi(1, ceili(float(int(me.get("max_hp"))) * HEAL_SHARE / float(shares[me])))
		var blob: HealBlob = HealBlob.send(get_parent() if get_parent() != null else self, at,
			whom, amount, mine)
		blobs.append(blob)


func outside_near(bodies: Array[Node2D]) -> Array[Node2D]:
	"""Of `bodies`, the ones outside the ring and within SEEK_RANGE of its
	middle - the blobs' players, nearest first."""
	var out: Array[Node2D] = []
	for body in bodies:
		var feet: Vector2 = feet_of(body)
		if not inside(feet) and feet.distance_to(global_position) <= SEEK_RANGE:
			out.append(body)
	var middle: Vector2 = global_position
	var nearer := func(a: Node2D, b: Node2D) -> bool:
		return feet_of(a).distance_squared_to(middle) < feet_of(b).distance_squared_to(middle)
	out.sort_custom(nearer)
	return out


static func ring_point(i: int) -> Vector2:
	"""Where blob `i` lifts off: evenly round the ring's line, from its
	middle, on whole pixels."""
	var angle: float = TAU * float(i) / float(BLOBS)
	return Vector2(cos(angle) * RADII.x, sin(angle) * RADII.y).round()


func tick() -> void:
	"""One tick: heal this game's own player if it was inside as the beam
	landed and still is, and burn every monster inside - this healer's own
	aura only."""
	ticks_done += 1
	var me: Node2D = my_player()
	if _me_inside and can_be_healed(me) and inside(feet_of(me)):
		var amount: int = heal_each(int(me.get("max_hp")))
		me.call("heal", amount)
		healed += amount
	if cosmetic or damage <= 0 or not is_inside_tree():
		return
	for monster in get_tree().get_nodes_in_group(&"enemies"):
		if monster is Node2D and monster.has_method(&"take_damage") and inside(feet_of(monster as Node2D)):
			monster.call("take_damage", damage, element)


func inside(point: Vector2) -> bool:
	"""Whether `point`, in the world, is inside the ring."""
	var d: Vector2 = point - global_position
	var rx: float = RADII.x + REACH_PAD
	var ry: float = RADII.y + REACH_PAD
	return (d.x * d.x) / (rx * rx) + (d.y * d.y) / (ry * ry) <= 1.0


static func feet_of(body: Node2D) -> Vector2:
	"""Where a body stands: a player's feet, a monster's footprint."""
	if body.has_method(&"aim_ring_feet"):
		return body.global_position + (body.call("aim_ring_feet") as Vector2)
	var footprint: Node2D = body.get_node_or_null(^"bodyshape") as Node2D
	return footprint.global_position if footprint != null else body.global_position
