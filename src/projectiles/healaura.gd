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

var _picture: AnimatedSprite2D = null
var _last_ticked: int = -1
var _landed: bool = false
# Whether this game's own player was inside the ring as the beam landed: the
# ring heals them, not the blobs.
var _me_inside: bool = false

static var _frames: SpriteFrames = null


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
	_picture.frame_changed.connect(_on_frame_changed)
	_picture.animation_finished.connect(queue_free)
	_picture.play(&"aura")


func _on_frame_changed() -> void:
	reached(_picture.frame)


func reached(frame: int) -> void:
	"""What happens on `frame`: the landing, and the ticks."""
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
