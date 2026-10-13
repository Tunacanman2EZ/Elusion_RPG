# auraburn.gd - the tank's fire aura, burning on the ground (0.34.0).
#
# The owner, 13 Oct, with a picture of the tank's lit aura: "i want us to
# elavate the animation by adding effects and born on the ground" - and, asked
# how the ground should burn, "Both": the floor inside the ring glows and
# flickers with small flames while it is lit, and the ground it passes over is
# left scorched, with dying embers, for a few seconds.
#
# WHAT IT ADDS, all of it following the fire ring's own visibility (tank.tscn's
# "firering", shown by _activate_aura() and by a Dynamite throw, hidden by
# _deactivate_aura()):
#
#   the ring       unshaded, so in a dark area it is fire rather than an orange
#                  line the night has dimmed, and pulsing a little brighter
#   the glow       the floor inside the ring lit orange, in pixel bands -
#                  brightest just inside the flames, spilling a little past
#                  them - flickering on two timescales (lightflicker.gd's
#                  header says why two), fading in as the aura lights and out
#                  as it goes
#   a light        in a dark area (one with a CanvasModulate, the same test the
#                  player's carried light uses), a PointLight2D flickering with
#                  the glow, lighting the floor, the props and the monsters
#                  round the ring. Settings' "simple" lighting hides it like
#                  every other light; it is switched with `enabled`, never
#                  `visible`, so the two do not fight.
#   flames         small tongues of fire licking up off the floor inside the
#                  ring, drawn like the sparks on the ring's own art
#   embers         sparks rising off the ring's line and drifting up
#   scorch         blackened patches left on the ground under the ring, each
#                  with a few embers that cool and die, fading over a few
#                  seconds (scorchmarks.gd). A few a second standing still, and
#                  more as the ring moves, so a walk leaves a burnt path.
#
# ON EVERYONE'S SCREEN. A remote tank (remoteplayer.gd) is drawn from the same
# scene's "firering" sprite and shows or hides it as the presence server says,
# so it carries one of these too, and its aura burns the ground the same.
#
# UNDER THE FIRE RING, ON THE FLOOR. A y-sorted body (the tank's) draws its
# children in order of height, so this is placed a hair above the highest of
# its pictures and draws everything down at the fire ring's middle (the aim
# ring does the same, aimring.gd). The highest is the fire ring itself, whose
# frame is placed by its top-left corner, 131 px up: so the glow is drawn
# before the ring's line - added on top of it, it turned the orange line white
# in the first recording - and before any monster standing inside the ring,
# which stands in the light rather than under it.
#
# MEASURED OFF THE ART. The fire ring's ellipse in its 128 px frames, which are
# drawn from their top-left corner, not centred: the middle of its 2 px line
# runs 51 px to each side and 30 up and down round (64, 83) - outer edge 12 to
# 116 across, 52 to 114 down, the same in all six frames. Where the frame is
# drawn and how big is read off the sprite, so moving the ring in the editor
# moves all of this with it. _test_the_tank_aura_burns measures the PNG.
class_name AuraBurn
extends Node2D


const FIRE_FRAME := Vector2(128.0, 128.0)
const FIRE_FROM_FRAME_CORNER := Vector2(64.0, 83.0)
const FIRE_HALF := Vector2(51.0, 30.0)

# How long it takes to light, and to go out.
const LIGHT_UP_SECONDS := 0.3
const GO_OUT_SECONDS := 0.6

# THE GLOW. Its colour, its strongest alpha (at the band just inside the
# flames), and how far past the ring it spills, as a share of the ring.
const GLOW_COLOUR := Color(1.0, 0.45, 0.12)
const GLOW_ALPHA := 0.2
const GLOW_SPILL := 1.2
# How bright the middle is, against the band by the flames.
const GLOW_MIDDLE := 0.4
const GLOW_LEVELS := 6

# THE FLICKER: a slow swell and a fast flicker, summed sines at frequencies
# that do not divide into each other (lightflicker.gd).
const SWELL := 0.16
const SWELL_HZ := 0.43
const FLICKER := 0.09
const FLICKER_HZ := 4.7
# How much brighter than its art the ring pulses.
const RING_PULSE := 0.12

# THE LIGHT, in a dark area: its reach, as a share of the ring.
const LIGHT_COLOUR := Color(1.0, 0.56, 0.24)
const LIGHT_ENERGY := 0.95
const LIGHT_REACH := 1.45
const LIGHT_TEXTURE := preload("res://scene/crypt/lightgradient.tres")

# THE PARTICLES.
const FLAMES := 36
const EMBERS := 26
# Emission points, so the flames fill the floor and the embers leave the line.
const FLAME_POINTS := 120
const EMBER_POINTS := 72

# THE SCORCH: patches dropped under the ring - this many a second standing
# still, and one more for every SCORCH_EVERY_PX the ring moves. A jump further
# than SCORCH_JUMP (a portal, a respawn) is not a walk.
const SCORCH_PER_SECOND := 4.0
const SCORCH_EVERY_PX := 7.0
const SCORCH_JUMP := 64.0
# How far out from the middle a patch can land, as a share of the ring.
const SCORCH_REACH := 0.92

# The glows already drawn, one per ring size: every tank's ring is the same.
static var _glow_textures: Dictionary = {}
static var _flame_texture: ImageTexture = null

# The fire ring this follows, and its ellipse in the body's space.
var fire: AnimatedSprite2D = null
var centre: Vector2 = Vector2.ZERO
var radii: Vector2 = FIRE_HALF
# 0 out, 1 burning: what everything here is drawn at.
var heat: float = 0.0
var lit: bool = false
var flames: CPUParticles2D = null
var embers: CPUParticles2D = null
var light: PointLight2D = null
var _clock: float = 0.0
var _glow: Texture2D = null
var _scorch_owed: float = 0.0
var _last_spot: Vector2 = Vector2.ZERO
var _has_last_spot: bool = false
var _dark: bool = false


static func on(body: Node2D) -> AuraBurn:
	"""The burn for `body`'s fire ring, as its first child - or null for a body
	with no "firering". Once."""
	var ring: AnimatedSprite2D = body.get_node_or_null(^"firering") as AnimatedSprite2D
	if ring == null:
		return null
	var burn: AuraBurn = body.get_node_or_null(^"auraburn") as AuraBurn
	if burn != null:
		return burn
	burn = AuraBurn.new()
	burn.name = "auraburn"
	burn.fire = ring
	burn.centre = fire_centre(ring)
	burn.radii = FIRE_HALF * ring.scale.abs()
	burn.position = Vector2(0.0, placed_at(body, burn.centre.y))
	body.add_child(burn)
	body.move_child(burn, 0)
	return burn


static func fire_centre(ring: AnimatedSprite2D) -> Vector2:
	"""The middle of the fire ring's ellipse, in its parent's space."""
	var corner: Vector2 = ring.offset - (FIRE_FRAME / 2.0 if ring.centered else Vector2.ZERO)
	return ring.position + (corner + FIRE_FROM_FRAME_CORNER) * ring.scale


static func placed_at(body: Node2D, middle_y: float) -> float:
	"""A hair above the highest of the body's pictures - the fire ring, the
	small ring, the body - so a y-sorted body draws this first; the middle of
	the ring when it has none."""
	var highest: float = INF
	for part in [^"firering", ^"animatedsprite2d", ^"ring"]:
		var picture: Node2D = body.get_node_or_null(part) as Node2D
		if picture != null:
			highest = minf(highest, picture.position.y)
	return middle_y if highest == INF else minf(middle_y, highest - 0.5)


static func scene_is_dark(tree: SceneTree) -> bool:
	"""An area with a CanvasModulate is a dark one (player.gd asks the same of
	its carried light)."""
	var scene: Node = tree.current_scene if tree != null else null
	if scene == null:
		return false
	return not scene.find_children("*", "CanvasModulate", true, false).is_empty()


func drawn_at() -> Vector2:
	"""The middle of the ring, in this node's space."""
	return centre - position


func _ready() -> void:
	var glowing := CanvasItemMaterial.new()
	glowing.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	glowing.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = glowing
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_glow = glow_texture(radii)
	flames = _make_flames()
	embers = _make_embers()
	light = _make_light()
	# The ring is fire: the night does not dim it.
	var unshaded := CanvasItemMaterial.new()
	unshaded.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	fire.material = unshaded
	fire.visibility_changed.connect(_follow_fire)
	_clock = randf() * 100.0
	_follow_fire()


func _follow_fire() -> void:
	if fire == null or not is_instance_valid(fire):
		return
	var now_lit: bool = fire.visible
	if now_lit and not lit:
		_has_last_spot = false
		_scorch_owed = 0.0
		_dark = scene_is_dark(get_tree()) if is_inside_tree() else false
	lit = now_lit
	flames.emitting = lit
	embers.emitting = lit
	set_process(true)


func flicker(at: float) -> float:
	"""The flame's brightness at clock `at`, round 1."""
	return 1.0 + SWELL * sin(at * TAU * SWELL_HZ) + FLICKER * sin(at * TAU * FLICKER_HZ) \
		+ FLICKER * 0.5 * sin(at * TAU * FLICKER_HZ * 2.37 + 1.3)


func _process(delta: float) -> void:
	_clock += delta
	heat = move_toward(heat, 1.0 if lit else 0.0, delta / (LIGHT_UP_SECONDS if lit else GO_OUT_SECONDS))
	var shine: float = flicker(_clock)
	if fire != null and is_instance_valid(fire):
		# Never darker than its art: the pulse only adds.
		var pulse: float = 1.0 + RING_PULSE * heat * clampf((shine - 1.0 + SWELL) / (2.0 * SWELL), 0.0, 1.0)
		fire.self_modulate = Color(pulse, pulse, pulse, 1.0)
	light.enabled = _dark and heat > 0.0
	light.energy = LIGHT_ENERGY * heat * shine
	if lit:
		_drop_scorch(delta)
	queue_redraw()
	if not lit and heat <= 0.0:
		set_process(false)


func _drop_scorch(delta: float) -> void:
	var spot: Vector2 = to_global(drawn_at())
	var moved: float = spot.distance_to(_last_spot) if _has_last_spot else 0.0
	if moved > SCORCH_JUMP:
		moved = 0.0
	_last_spot = spot
	_has_last_spot = true
	_scorch_owed += delta * SCORCH_PER_SECOND + moved / SCORCH_EVERY_PX
	if _scorch_owed < 1.0:
		return
	var ground: ScorchMarks = ScorchMarks.of(get_tree()) if is_inside_tree() else null
	while _scorch_owed >= 1.0:
		_scorch_owed -= 1.0
		if ground != null:
			ground.burn(spot + scorch_offset(randf(), randf()))


func scorch_offset(turn: float, out: float) -> Vector2:
	"""Where a patch lands from the middle of the ring, for two rolls of
	randf(): anywhere on the floor inside it, evenly."""
	var angle: float = turn * TAU
	var reach: float = sqrt(out) * SCORCH_REACH
	return Vector2(cos(angle) * radii.x, sin(angle) * radii.y) * reach


func _draw() -> void:
	if heat <= 0.0 or _glow == null:
		return
	var alpha: float = clampf(heat * flicker(_clock), 0.0, 1.5)
	var tint := Color(GLOW_COLOUR.r, GLOW_COLOUR.g, GLOW_COLOUR.b, minf(alpha, 1.0))
	var size: Vector2 = _glow.get_size()
	draw_texture(_glow, (drawn_at() - size / 2.0).round(), tint)


# =============================================================================
# THE PIECES
# =============================================================================

static func glow_band(d: float) -> float:
	"""How bright the glow is at `d`, the distance from the middle as a share
	of the ring (1 is the flames): GLOW_MIDDLE in the middle, rising to full
	just inside the flames, gone by GLOW_SPILL."""
	if d >= GLOW_SPILL:
		return 0.0
	if d <= 0.9:
		return lerpf(GLOW_MIDDLE, 1.0, smoothstep(0.0, 0.9, d))
	return lerpf(1.0, 0.0, (d - 0.9) / (GLOW_SPILL - 0.9))


static func glow_texture(ring_radii: Vector2) -> Texture2D:
	"""The glow for a ring this size, in GLOW_LEVELS steps with a 2 x 2 dither
	between them - a pixel-art glow rather than a smooth one."""
	var half := Vector2i(ceili(ring_radii.x * GLOW_SPILL), ceili(ring_radii.y * GLOW_SPILL))
	if _glow_textures.has(half):
		return _glow_textures[half]
	var image := Image.create(half.x * 2, half.y * 2, false, Image.FORMAT_RGBA8)
	var bayer: Array[float] = [0.0, 0.5, 0.75, 0.25]
	for y in half.y * 2:
		for x in half.x * 2:
			var at := Vector2((x + 0.5 - half.x) / ring_radii.x, (y + 0.5 - half.y) / ring_radii.y)
			var level: float = glow_band(at.length()) * GLOW_LEVELS
			var stepped: float = floorf(level + bayer[(y % 2) * 2 + (x % 2)]) / GLOW_LEVELS
			if stepped > 0.0:
				image.set_pixel(x, y, Color(1.0, 1.0, 1.0, minf(stepped, 1.0) * GLOW_ALPHA))
	var texture := ImageTexture.create_from_image(image)
	_glow_textures[half] = texture
	return texture


static func flame_texture() -> ImageTexture:
	"""A tongue of fire three pixels wide, like the sparks drawn on the ring:
	a white core, yellow round it, orange at the ends."""
	if _flame_texture != null:
		return _flame_texture
	var rows: Array[String] = [".e.", ".o.", ".y.", "ywy", ".y.", ".o.", ".e."]
	var colours: Dictionary = {
		"w": Color(1.0, 1.0, 0.92, 1.0), "y": Color(1.0, 0.86, 0.45, 1.0),
		"o": Color(1.0, 0.55, 0.18, 0.95), "e": Color(0.9, 0.3, 0.08, 0.6),
	}
	var image := Image.create(3, rows.size(), false, Image.FORMAT_RGBA8)
	for y in rows.size():
		for x in 3:
			var key: String = rows[y][x]
			if colours.has(key):
				image.set_pixel(x, y, colours[key])
	_flame_texture = ImageTexture.create_from_image(image)
	return _flame_texture


func ellipse_points(count: int, filled: bool) -> PackedVector2Array:
	"""`count` points on the ring's line, or spread evenly over the floor
	inside it, round drawn_at()."""
	var points := PackedVector2Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1873
	for i in count:
		var angle: float = TAU * (i + rng.randf() * 0.5) / count
		var out: float = sqrt(rng.randf()) * 0.88 if filled else 1.0
		points.append(Vector2(cos(angle) * radii.x, sin(angle) * radii.y) * out)
	return points


func _unshaded() -> CanvasItemMaterial:
	var unshaded := CanvasItemMaterial.new()
	unshaded.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return unshaded


func _make_flames() -> CPUParticles2D:
	# A RAW Gradient for color_ramp - see firepit.gd's _ensure_embers().
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.15, 0.6, 1.0])
	ramp.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.0),
		Color(1.0, 0.97, 0.85, 1.0),
		Color(1.0, 0.62, 0.3, 0.85),
		Color(0.75, 0.2, 0.05, 0.0),
	])
	var p := CPUParticles2D.new()
	p.name = "flames"
	p.emitting = false
	p.amount = FLAMES
	p.lifetime = 0.75
	p.lifetime_randomness = 0.4
	p.local_coords = false
	p.texture = flame_texture()
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	p.emission_points = ellipse_points(FLAME_POINTS, true)
	p.direction = Vector2(0, -1)
	p.spread = 6.0
	p.gravity = Vector2(0, -8)
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 9.0
	p.color_ramp = ramp
	p.material = _unshaded()
	p.position = drawn_at()
	add_child(p)
	return p


func _make_embers() -> CPUParticles2D:
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	ramp.colors = PackedColorArray([
		Color(1.0, 0.95, 0.6, 1.0),
		Color(1.0, 0.5, 0.14, 0.9),
		Color(0.55, 0.1, 0.03, 0.0),
	])
	var p := CPUParticles2D.new()
	p.name = "embers"
	p.emitting = false
	p.amount = EMBERS
	p.lifetime = 1.4
	p.lifetime_randomness = 0.5
	p.local_coords = false
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	p.emission_points = ellipse_points(EMBER_POINTS, false)
	p.direction = Vector2(0, -1)
	p.spread = 24.0
	p.gravity = Vector2(0, -10)
	p.initial_velocity_min = 10.0
	p.initial_velocity_max = 24.0
	p.damping_min = 2.0
	p.damping_max = 6.0
	p.color_ramp = ramp
	p.material = _unshaded()
	p.position = drawn_at()
	add_child(p)
	return p


func _make_light() -> PointLight2D:
	var lamp := PointLight2D.new()
	lamp.name = "firelight"
	lamp.enabled = false
	lamp.color = LIGHT_COLOUR
	lamp.energy = 0.0
	lamp.texture = LIGHT_TEXTURE
	# The texture is 256 px across; this makes its edge LIGHT_REACH rings out,
	# and the node's scale squashes it to the ring's own shape.
	lamp.texture_scale = radii.x * LIGHT_REACH * 2.0 / 256.0
	lamp.scale = Vector2(1.0, radii.y / radii.x)
	lamp.position = drawn_at()
	add_child(lamp)
	return lamp
