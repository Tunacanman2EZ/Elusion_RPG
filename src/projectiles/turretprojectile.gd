# turretprojectile.gd — the healer's magic orb: a light-green spell that weaves
# toward the nearest enemy and pops on the first one it reaches.
#
# usage:
# - healer.gd._fire_projectile() spawns this scene and sets direction, speed,
#   damage, owner_group, and caster
# - on spawn the orb latches onto the nearest enemy, curves toward that enemy's
#   BODY (not its origin) while weaving side to side (~), and deals its damage
#   the instant it gets within reach of the enemy — then despawns.
#
# =============================================================================
# THE HIT SYSTEM — PER-FRAME DISTANCE, NOT PHYSICS SIGNALS  (this is the fix)
# =============================================================================
# Every enemy's real hurtbox is TINY and OFF-CENTRE. On the slimes it's an 8px
# circle offset to (-1, -5) from the enemy's ROOT — and the root sits at the
# creature's FEET, with the sprite drawn ~18px above it. So the visible slime is
# a ~48px blob whose actual hittable area is a little circle floating near its
# middle.
#
# The old orb homed at `enemy.global_position` (the FEET) and left hits to the
# physics engine's body_entered/area_entered signals. Between aiming below the
# body and the weave rocking the orb off-line, it kept threading past that little
# circle without ever overlapping it — so no signal, no damage, and the shot
# just weaved off and expired. That is the bug that read as "the orb reaches the
# enemy and does nothing / vanishes."
#
# The fix is the system RotMG and Darza's Dominion use: forget the physics
# engine. Every physics frame we measure the orb's distance to each live enemy's
# HURTBOX centre and, the moment it's within `hurtbox radius + hit_pad`, we deal
# the damage and despawn. No collision layers, no monitoring flags, no signal
# timing — just geometry we control. `collision_mask` is zeroed and monitoring is
# turned off so the physics engine can NEVER despawn this orb early; the only
# things that end it are a hit or its lifetime.
#
# We read the enemy's hurtbox node LIVE each frame (its global position and shape
# radius), so this stays correct no matter how a variant is offset or scaled —
# e.g. the small-slime form — without hard-coding any numbers per enemy.
#
# =============================================================================
# MOVEMENT — WEAVE + HOMING
# =============================================================================
#   HOMING: `direction` is steered toward the latched enemy's BODY every frame
#           with the shared Homing helper — a turn RATE, not a snap, so it curves
#           the way the pet orbs do (see homing.gd). latched on spawn, dropped
#           once past so it never boomerangs.
#   WEAVE:  the orb travels along `direction` rocked side to side by a sine, so
#           it snakes (~) toward the target. the amplitude is an ANGLE, so the
#           weave looks the same at any speed. the forgiving hit radius above is
#           what lets the weave stay lively without ever costing a hit.
#
# =============================================================================
# ALWAYS GLOWS — UNSHADED
# =============================================================================
# the sprite is given an UNSHADED material in _ready so a dark scene's
# CanvasModulate and lights cannot dim it — it always shows its own light-green
# art at full brightness. one static material is shared by every orb.
#
# sprite orientation: the sprite NEVER rotates — a floating orb, not a thrown
# arrow. the weave moves the orb's PATH, not its facing.
#
# friendly fire: owner_group identifies who fired ("player" for healer shots).
# the orb never damages anything in its owner's group.
#
# XP ON HIT: grants XP back to whoever fired this — see _grant_caster_xp(),
# same pattern as slashwave.gd (warrior) and spelltargetcircle.gd (mage).
#
# =============================================================================
# THE ORB, DRESSED (0.36.0)
# =============================================================================
# The owner, of the healer's attack: keep the orb he paid for and mix in "the
# bullets from crypt" - the glowing orbs the Field's monsters fire
# (bulletfield.gd) - "and adding a effect also", with their patterns too.
#
#   the core    a white-hot core on the paid orb's ball and a soft green glow
#               behind it, added and unshaded: the crypt bullet's look, so it
#               pops in the dark
#   the trail   green wisps left behind it, single pixels that rise and fade,
#               and that stay a moment after it is gone (_let_go_of_trail())
#   the splash  where it hits, a handful of green sparks and a small ring of
#               air (Blast.BlastRing), drawn over whoever was hit
#   a fan orb   `fan` set: one of the two the healer throws beside every
#               FAN_EVERY-th shot (healer.gd, THE FAN). It IS a crypt bullet -
#               the paid sprite hidden, the crypt orb's pixels in its place -
#               and flies like one, straight, no homing and no weave.
#
# The orb's root is drawn at 2x (turretprojectile.tscn), so everything added
# here is scaled by half to come out in the world's own pixels.
#
# LONGER, GLOWING TRAILS AND THE GOLDEN DOUBLE (0.37.0). The owner: "make the
# glowing trails longer and add a 20% chance to deal dbl damage on 1 main
# projectile" - "can make a diff color if needed". The wisps last TRAIL_SECONDS
# (0.8, was 0.35), twice as many, added so they glow, and drift up less, so
# each orb draws a line behind it. A `doubled` orb (healer.gd, THE DOUBLE) is
# gold - the healer's halo's colour: its flame tinted, its glow, core, wisps
# and splash gold, the splash bigger - so a double hit is seen as it flies.
extends Area2D

# Whether a wall stands between this and what it would hit (0.69.1,
# src/shared/targets.gd).
const Targets := preload("res://src/shared/targets.gd")


# =============================================================================
# EXPORTED SETTINGS
# =============================================================================

# how long (seconds) before the projectile auto-despawns if it never reaches an
# enemy.
@export var max_lifetime: float = 3.5

# Magic XP to the caster on a successful hit, reported to the server. No attack
# XP: attack trains at the kill, on the server (Player.apply_server_attack()).
@export var magic_xp_on_hit: int = 5

# HOMING — degrees per second the orb may turn to follow the enemy it latched
# onto on spawn. a rate, not a snap (see homing.gd). 0 makes it a straight shot.
@export var homing_turn_rate: float = 200.0

# WEAVE — the ~ motion. amplitude is how far (in degrees) the travel direction
# rocks off the homing heading; frequency is how fast it oscillates. set the
# amplitude to 0 for a clean homing arc with no snake.
@export var weave_amplitude_deg: float = 22.0
@export var weave_frequency: float = 12.0

# HIT REACH — extra pixels added to the enemy's own hurtbox radius to decide when
# the orb "reaches" it. Bigger = pops a touch sooner / more forgiving; smaller =
# has to bury deeper into the body first. This plus the enemy's live hurtbox
# radius is the whole hit test — see the header. Tune here if the orb feels like
# it pops too early or grazes past.
@export var hit_pad: float = 14.0


# =============================================================================
# CONFIGURED ON SPAWN
# =============================================================================
# set by the spawner (healer.gd) immediately after instantiate(), BEFORE
# add_child, so _ready sees correct values.

var direction: Vector2 = Vector2.RIGHT
var speed: float = 400.0
var damage: int = 8
var owner_group: String = "player"
# A PICTURE OF SOMEBODY ELSE'S (0.19.0). With `cosmetic` set, this is a copy of
# an attack another player made, drawn on this screen from the presence
# server's word (remoteattacks.gd): it flies, spins, falls and burns exactly as
# theirs does, and it touches nothing - no hit, no XP, no camera shake, and
# nothing set off or pulled. The monsters are the area's leader's and every
# hit still travels as a hit; this is only what the owner asked to see: "i
# could not see their attacks but they could see mine".
# A picture still homes and still goes out on the monster it reaches.
var cosmetic: bool = false
var caster: Node = null
# One of the healer's fan orbs (THE ORB, DRESSED).
var fan: bool = false
# A main orb that rolled the double (healer.gd, THE DOUBLE): gold. Set before
# add_child(), like `fan`.
var doubled: bool = false


# =============================================================================
# STATE
# =============================================================================

# fallback reach (px) when an enemy exposes no readable hurtbox shape — a slime's
# hurtbox is radius 8, so this covers a body of roughly that size on its own.
const DEFAULT_ENEMY_RADIUS: float = 10.0

# accumulated lifetime — triggers queue_free at max_lifetime.
var _lifetime: float = 0.0

# the enemy this orb is curving toward and testing against. latched on spawn,
# dropped once passed (see _home / homing.gd's is_past). null when there was no
# enemy to seek — the orb then just weaves along the direction it was fired.
var _homing_target: Node2D = null

# has this orb already spent its one hit? guards against a second hit in the same
# frame before queue_free() takes effect.
var _spent: bool = false

# advances every physics frame; drives the weave's sine.
var _time: float = 0.0

# shared unshaded material so the orb ignores scene lighting. static: one for
# every orb, built lazily on the first spawn.
static var _glow_material: CanvasItemMaterial = null
static var _added_material: CanvasItemMaterial = null
static var _crypt_orb: ImageTexture = null
static var _core: ImageTexture = null

# The healer's green, for the crypt orb and the wisps: the paid orb's own
# brightest body colour.
const ORB_GREEN := Color(0.55, 0.95, 0.42)
# The ball of the paid orb, from the middle of its 32 px frame.
const BALL := Vector2(-0.5, 0.3)
# The root's scale, undone for what is added in world pixels.
const ROOT_SCALE := 2.0
# The glow behind the paid orb, in the orb's own (2x) pixels: a little past
# its ball (6 across), and faint - at 5 and 0.35 the first recording drew
# every orb as a green blob twice its size.
const GLOW_RADIUS := 4
const GLOW_ALPHA := 0.25
const TRAIL_SECONDS := 0.8
# Wisps a second an orb leaves, and a fan orb (smaller) leaves.
const TRAIL_WISPS := 24
const FAN_TRAIL_WISPS := 16
# The double's gold, on the flame (over 1 brightens: the green flame comes out
# a yellow-gold) and on everything added.
const DOUBLE_TINT := Color(2.0, 0.95, 0.5)
const GOLD := Color(1.0, 0.82, 0.3)
const SPLASH_SECONDS := 0.4

var _trail: CPUParticles2D = null


# =============================================================================
# LIFECYCLE
# =============================================================================

# The nearest enemy is looked for on the first physics frame; see _ready().
var _seek_pending: bool = false


func _ready() -> void:
	# WE OWN HITS OURSELVES (see header). Kill every physics-engine path so it can
	# neither despawn this orb early nor fight our per-frame check: no mask means
	# nothing is detected, monitoring off means no body/area signals fire at all.
	collision_mask = 0
	collision_layer = 0
	monitoring = false
	monitorable = false

	# ALWAYS GLOW + animate. unshaded material so a dark scene can't dim the orb;
	# play the shimmer so it isn't a frozen frame. shared material via the static.
	var sprite: AnimatedSprite2D = get_node_or_null("animatedsprite2d")
	if sprite != null:
		if _glow_material == null:
			_glow_material = CanvasItemMaterial.new()
			_glow_material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		sprite.material = _glow_material
		if sprite.sprite_frames != null and sprite.sprite_frames.has_animation(&"projectile"):
			sprite.play(&"projectile")

	# LATCH A TARGET ON SPAWN, not every frame. re-acquiring mid-flight makes a
	# shot chase whatever wanders closest and reads as a bug; the pet orbs latch
	# the same way. no enemy → _homing_target stays null and the orb just weaves.
	# A fan orb flies like a crypt bullet: straight.
	if fan:
		homing_turn_rate = 0.0
		weave_amplitude_deg = 0.0
	else:
		# ON THE FIRST FRAME, NOT HERE (0.56.0). _ready() runs inside the
		# spawner's add_child(), before it sets the orb's position - so the
		# nearest enemy was looked for from the world's origin, and an orb
		# could swing off toward a monster nowhere near the healer.
		_seek_pending = true
	_dress(sprite)


func _physics_process(delta: float) -> void:
	if _seek_pending:
		_seek_pending = false
		_homing_target = _find_nearest_enemy()
	_time += delta

	# STEER FIRST, THEN MOVE — same order as petfireprojectile.gd. turning after
	# the move advances the orb along last frame's heading and then points it
	# elsewhere, lagging its own path by a frame.
	direction = _home(delta, direction)

	# THE WEAVE (~). rock the travel direction side to side by a sine. rotating the
	# heading (rather than adding a sideways velocity) keeps the weave centred on
	# the path instead of drifting off it.
	var wobble: float = sin(_time * weave_frequency) * deg_to_rad(weave_amplitude_deg)
	var travel: Vector2 = direction.rotated(wobble)
	var was: Vector2 = global_position
	global_position += travel * speed * delta

	# IT STOPS AT A WALL (0.69.1). With every physics path off (above), nothing
	# ever stopped it: it homed on a monster in the next room through the
	# masonry, and flew out over the black. A ray along this tick's step, the
	# way the spinning axe flies, and it bursts where it met the wall.
	if not Targets.clear_between(self, was, global_position):
		splash(get_parent(), global_position, doubled)
		_let_go_of_trail()
		queue_free()
		return

	# THE HIT — per-frame distance to each enemy's live hurtbox (see header).
	if not _spent:
		var enemy: Node2D = _enemy_in_reach()
		if enemy != null:
			_spent = true
			_hit(enemy)
			return

	# lifetime expiry — covers a shot that never reaches anything.
	_lifetime += delta
	if _lifetime >= max_lifetime:
		_let_go_of_trail()
		queue_free()


# =============================================================================
# HOMING
# =============================================================================

func _home(delta: float, heading: Vector2) -> Vector2:
	# steering off, or nothing to steer toward → fly straight (still weaves).
	if homing_turn_rate <= 0.0 or not is_instance_valid(_homing_target):
		_homing_target = null
		return heading

	# aim at the enemy's BODY, not its root origin — the root sits at the feet,
	# well below the hittable area, and homing at the feet was half the old miss.
	var to: Vector2 = _enemy_hit_point(_homing_target)

	# LATCHED, NOT RE-CHECKED. once the orb is level with or past its target it
	# drops it and flies straight — a shot that re-engages after overshooting
	# turns into a boomerang. same rule as petfireprojectile.gd.
	if Homing.is_past(heading, global_position, to):
		_homing_target = null
		return heading

	return Homing.steer(heading, global_position, to, homing_turn_rate, delta)


# =============================================================================
# HIT DETECTION  (pure geometry — no physics engine)
# =============================================================================

func _enemy_in_reach() -> Node2D:
	# the first live enemy whose hurtbox the orb is now touching. checks EVERY
	# enemy, not just the latched one, so a weaving orb still connects with a slime
	# that drifts into its path. distance is measured to the enemy's real hurtbox
	# centre and compared against that hurtbox's radius plus hit_pad.
	for node in get_tree().get_nodes_in_group("enemies"):
		if not (node is Node2D) or not is_instance_valid(node):
			continue
		var enemy: Node2D = node as Node2D
		# never damage our own team (defensive — enemies aren't in "player").
		if enemy.is_in_group(owner_group):
			continue
		if not enemy.has_method("take_damage"):
			continue
		# A CAGED BOSS OR A CORPSE IS NOT IN REACH (0.56.0): its take_damage()
		# refuses, and the orb was spent on it.
		if enemy.has_method("can_be_aimed_at") and not enemy.call("can_be_aimed_at"):
			continue
		var reach: float = _enemy_radius(enemy) + hit_pad
		if global_position.distance_squared_to(_enemy_hit_point(enemy)) <= reach * reach:
			return enemy
	return null


func _enemy_hit_point(enemy: Node2D) -> Vector2:
	# the enemy's hurtbox centre in world space. read live so it's right for a
	# moving, offset, or rescaled enemy. falls back to the root origin only if the
	# enemy has no hurtbox shape node at the conventional path.
	var shape_node: Node = enemy.get_node_or_null("hurtbox/collisionshape2d")
	if shape_node is Node2D:
		return (shape_node as Node2D).global_position
	return enemy.global_position


func _enemy_radius(enemy: Node2D) -> float:
	# the enemy's hurtbox radius in world pixels, read live from its shape and
	# scaled by the node's global scale. Circle and Capsule shapes both expose a
	# `radius`. anything without one falls back to DEFAULT_ENEMY_RADIUS.
	var shape_node: Node = enemy.get_node_or_null("hurtbox/collisionshape2d")
	if shape_node is CollisionShape2D:
		var shape: Shape2D = (shape_node as CollisionShape2D).shape
		if shape != null and "radius" in shape:
			var scale_x: float = absf((shape_node as Node2D).global_scale.x)
			return float(shape.radius) * scale_x
	return DEFAULT_ENEMY_RADIUS


func _find_nearest_enemy() -> Node2D:
	# nearest live enemy by squared distance to its hurtbox, chosen once on spawn.
	# no aggro-range gate (unlike the pet's version) — the player already aimed the
	# shot, so the orb just needs something to curve toward.
	var nearest: Node2D = null
	var nearest_d: float = INF
	for node in get_tree().get_nodes_in_group("enemies"):
		if not (node is Node2D) or not is_instance_valid(node):
			continue
		var enemy: Node2D = node as Node2D
		var d: float = global_position.distance_squared_to(_enemy_hit_point(enemy))
		if d >= nearest_d:
			continue
		# NOT ONE BEHIND A WALL, or asleep and unseen in another room (0.69.1):
		# the orb would curve off into the masonry after it.
		if not enemy.is_visible_in_tree() or not Targets.can_reach(self, global_position, enemy):
			continue
		nearest_d = d
		nearest = enemy
	return nearest


# =============================================================================
# DAMAGE
# =============================================================================

func _hit(enemy: Node2D) -> void:
	# deal the damage, pay out the caster's XP, and despawn. take_damage's second
	# arg (element) defaults, so one arg is correct here — see baseenemy.take_damage.
	if not cosmetic:
		enemy.take_damage(damage)
		_grant_caster_xp()
	splash(get_parent(), global_position, doubled)
	_let_go_of_trail()
	queue_free()


func _grant_caster_xp() -> void:
	# null-guarded since caster isn't guaranteed to be set (e.g. an enemy-fired
	# turret variant shouldn't grant the player skill XP at all).
	if caster == null:
		return
	if caster.has_method("gain_magic_xp"):
		caster.gain_magic_xp(magic_xp_on_hit)


# =============================================================================
# THE ORB, DRESSED (0.36.0) - see the header
# =============================================================================

func _dress(sprite: AnimatedSprite2D) -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if fan:
		# A crypt bullet: the paid sprite hidden, the crypt orb's pixels shown.
		if sprite != null:
			sprite.visible = false
		var orb := Sprite2D.new()
		orb.name = "cryptorb"
		orb.texture = crypt_orb_texture()
		orb.scale = Vector2.ONE / ROOT_SCALE
		orb.material = _unshaded()
		add_child(orb)
	else:
		# The paid orb with the crypt bullet's glow behind and core on top -
		# gold, and brighter, on a double.
		if doubled and sprite != null:
			sprite.self_modulate = DOUBLE_TINT
		var glow := Sprite2D.new()
		glow.name = "glow"
		glow.texture = Blast.disc_texture(GLOW_RADIUS + 1, Color(1.0, 0.95, 0.7), GOLD.darkened(0.2)) if doubled \
			else Blast.disc_texture(GLOW_RADIUS, Color(0.8, 1.0, 0.7), ORB_GREEN.darkened(0.3))
		glow.modulate = Color(1, 1, 1, GLOW_ALPHA * (1.6 if doubled else 1.0))
		glow.position = BALL
		glow.material = _added()
		add_child(glow)
		move_child(glow, 0)
		var core := Sprite2D.new()
		core.name = "core"
		core.texture = core_texture()
		core.position = BALL
		if doubled:
			core.modulate = Color(1.0, 0.95, 0.75)
		core.material = _added()
		add_child(core)
	_trail = _make_trail()
	add_child(_trail)


func _make_trail() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.name = "trail"
	p.amount = FAN_TRAIL_WISPS if fan else TRAIL_WISPS
	p.lifetime = TRAIL_SECONDS
	p.lifetime_randomness = 0.4
	p.local_coords = false
	p.scale = Vector2.ONE / ROOT_SCALE
	p.position = BALL
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 2.0
	p.direction = Vector2.UP
	p.spread = 180.0
	p.initial_velocity_min = 0.0
	p.initial_velocity_max = 3.0
	p.gravity = Vector2(0.0, -5.0)
	p.color_ramp = gold_colours() if doubled else CastSparkle.colours(CastSparkle.HEAL)
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Added, so the wisps glow.
	p.material = _added()
	p.emitting = true
	return p


func _let_go_of_trail() -> void:
	"""The wisps outlive the orb by their own lifetime: handed to the orb's
	parent, stopped, and freed once the last has faded."""
	if _trail == null or not is_instance_valid(_trail) or get_parent() == null:
		return
	var trail: CPUParticles2D = _trail
	_trail = null
	trail.emitting = false
	trail.reparent(get_parent())
	get_tree().create_timer(TRAIL_SECONDS + 0.1).timeout.connect(trail.queue_free)


static func splash(parent: Node, at: Vector2, big: bool = false) -> Node2D:
	"""Where an orb lands: green sparks thrown out and a small ring of air,
	over whoever was hit - gold, twice the sparks and a wider ring for a
	double. Frees itself."""
	if parent == null:
		return null
	var root := Node2D.new()
	root.name = "orbsplash"
	root.z_as_relative = false
	root.z_index = 5
	root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var sparks := CPUParticles2D.new()
	sparks.name = "sparks"
	sparks.one_shot = true
	sparks.explosiveness = 0.95
	sparks.amount = 16 if big else 8
	sparks.lifetime = SPLASH_SECONDS
	sparks.lifetime_randomness = 0.3
	sparks.direction = Vector2.UP
	sparks.spread = 180.0
	sparks.initial_velocity_min = 25.0
	sparks.initial_velocity_max = 55.0
	sparks.damping_min = 30.0
	sparks.damping_max = 60.0
	sparks.color_ramp = gold_colours() if big else CastSparkle.colours(CastSparkle.HEAL)
	sparks.material = _unshaded()
	sparks.emitting = true
	root.add_child(sparks)
	var ring := Blast.BlastRing.new()
	ring.name = "ring"
	ring.reach = 15.0 if big else 9.0
	ring.colour = Color(1.0, 0.9, 0.55, 0.95) if big else Color(0.75, 1.0, 0.65, 0.9)
	root.add_child(ring)
	parent.add_child(root)
	root.global_position = at
	root.get_tree().create_timer(SPLASH_SECONDS + 0.1).timeout.connect(root.queue_free)
	return root


static func gold_colours() -> Gradient:
	"""The double's wisps and sparks: white, then the halo's gold, fading
	to a deep orange."""
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	ramp.colors = PackedColorArray([Color(1.0, 1.0, 0.9), GOLD, Color(0.85, 0.45, 0.1, 0.0)])
	return ramp


static func crypt_orb_texture() -> ImageTexture:
	"""The Field's bullet (bulletfield.gd's orb_texture()), coloured here
	rather than by its shader: a white-hot core, the healer's green body, a
	darker rim. 8 x 8."""
	if _crypt_orb != null:
		return _crypt_orb
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	for y in 8:
		for x in 8:
			var gap: float = Vector2(x - 3.5, y - 3.5).length()
			if gap <= 1.6:
				image.set_pixel(x, y, Color.WHITE)
			elif gap <= 2.6:
				image.set_pixel(x, y, ORB_GREEN)
			elif gap <= 3.9:
				image.set_pixel(x, y, Color(ORB_GREEN.r * 0.55, ORB_GREEN.g * 0.55, ORB_GREEN.b * 0.55))
	_crypt_orb = ImageTexture.create_from_image(image)
	return _crypt_orb


static func core_texture() -> ImageTexture:
	"""Two by two pixels of white, on the paid orb's ball."""
	if _core != null:
		return _core
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 1.0, 0.95, 0.85))
	_core = ImageTexture.create_from_image(image)
	return _core


static func _unshaded() -> CanvasItemMaterial:
	if _glow_material == null:
		_glow_material = CanvasItemMaterial.new()
		_glow_material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return _glow_material


static func _added() -> CanvasItemMaterial:
	if _added_material == null:
		_added_material = CanvasItemMaterial.new()
		_added_material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		_added_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _added_material
