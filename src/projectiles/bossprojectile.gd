# bossprojectile.gd — the boss's ground attack: a red ring marks a patch of
# floor, and a moment later a stone spike punches up through it.
#
# NAMED FOR ITS SCENE, NOT ITS BEHAVIOUR. bossprojectile.tscn already existed
# — five authored frames of a spike rising and sinking — with no script, no
# collision shape and no layer, so nothing could spawn it and it could not have
# hit anything if it had. The name is kept so the scene keeps its uid; nothing
# about this travels, and "projectile" is the wrong word for it.
#
#
# THE RING IS THE ATTACK. The spike on its own is a hit you take or you don't,
# decided by where you happened to be standing — the player never sees it
# coming and learns nothing from being hit. The ring turns it into a decision:
# the ground you are on is about to kill you, and you have telegraph_seconds to
# be somewhere else.
#
# THE RING DOES NOT FOLLOW. It is painted where the player stood at the moment
# the boss discharged, and it stays there. A telegraph that tracks its target
# is not a telegraph, it is a delayed guaranteed hit — there is no correct
# response to it, so it teaches nothing and just feels arbitrary.
#
#
# ONLY DAMAGES PLAYERS, for the same reason acidpuddle.gd does: this is an
# enemy's attack, and a boss killing itself on its own spikes is not a fight.
extends Area2D


# =============================================================================
# CONSTANTS
# =============================================================================

# Frame of the rise animation where the spike is at full extension — measured
# off the sheet rather than guessed, because the obvious guess is wrong. The
# five frames are: 0 a nub breaking the surface, 1 FULL HEIGHT, 2 full height
# narrowing, 3 sinking, 4 nearly gone. The midpoint frame is already on the way
# back down, so damage there lands after the spike visibly passed the player.
const IMPACT_FRAME := 1

# The animation's name inside the scene's SpriteFrames.
const RISE_ANIM := &"projectile"


# =============================================================================
# EXPORTED SETTINGS
# =============================================================================

# How long the ring is shown before the spike arrives. THE DIFFICULTY DIAL FOR
# THIS BOSS — it is the player's entire reaction window. Below about 0.5 it
# stops being a telegraph and becomes an unavoidable hit at any distance the
# player cannot cross in time.
@export var telegraph_seconds: float = 0.9

# Damage applied once, on IMPACT_FRAME, to every player inside the ring.
@export var damage: int = 22

# Named so a future armour or resistance system has something to match on,
# matching the convention acidpuddle.gd set with its "poison".
# The element this projectile deals. Element.Type is an int, not the
# StringName this used to be: an enum is checked when the file is parsed,
# and &"posion" was only ever going to be found by someone wondering why a
# resistance did nothing.
#
# Overwritten at spawn for anything an enemy fires — see
# BaseEnemy.spawn_projectile_node(), which stamps the caster's element on
# it so a water slime's shot IS water without a second scene existing.
@export var element: int = Element.Type.NONE

# THE ACID LEFT WHERE THE SPIKE WAS.
#
# bossenemy.gd has rolled for this on every pillar since the attack was
# written - PUDDLE_CHANCE, and the arithmetic above it about floor coverage -
# but this script had no leaves_puddle, so the assignment raised an error
# instead of setting anything and no puddle has ever appeared. The same hazard
# poisonprojectile.gd drops, spawned at the other end of the life cycle: that
# one leaves acid where a ball LANDS, this one leaves it where a spike
# RETRACTS.
#
# WHICH scene is Puddles.scene_for(element)'s call, not a preload here — there
# are nine of them now, one per element, each with its own colour, lifetime and
# tick authored in the file rather than scaled out of a table at spawn time.

# THE SPIKE IS TINTED, NOT HUE-ROTATED, and the measurement is why.
#
# boss.png's spike row is 84% near-grey rock with a few fully saturated
# highlights. element_recolour.gdshader rotates the hue of CHROMATIC pixels and
# skips the greys - so pointed at this art it repaints sixteen specks and
# leaves the spike grey. hearth_warm.gdshader does the exact opposite: it tints
# the pixels BELOW the saturation threshold and leaves the saturated ones
# alone, which is what turns the rock itself into fire or ice while the hot
# tips keep their own light.
#
# The slag takes the other shader, because slime.png's splat is 100% chromatic
# at 0.88 saturation and rotates cleanly. Two shaders, each used where its
# measurement says it works.
const SPIKE_SHADER := preload("res://src/shared/hearth_warm.gdshader")

# How much light the tinted rock throws. Matches hearth_warm's own default.
const SPIKE_LIFT := 0.30


# =============================================================================
# WHAT EACH ELEMENT DOES TO A SPIKE
# =============================================================================
# Six bosses that differ only in colour are one boss painted six ways. These
# are the numbers that make them fight differently.
#
# EVERY LEVER HERE IS ONE THAT CANNOT LIE. ring_radius is deliberately NOT in
# this table even though it is the obvious knob: the drawn ring uses it, but
# the damage comes from get_overlapping_bodies() against the CollisionShape2D,
# so scaling the ring alone would paint a warning that does not match the thing
# it is warning about. `size` below goes through the node's scale, which moves
# the hitbox, the sprite and the ring together — the same reasoning
# bossenemy.gd's SCALED, NOT RESIZED comment sets out.
#
# READ THESE AS "how do I dodge it":
#   telegraph  <1 gives you less warning, >1 more
#   size       how much floor the spike claims
#   damage     what it costs to be wrong
#   ring_alpha how clearly you can SEE the warning (dark is the mechanic)
#   puddle     chance multiplier on bossenemy.gd's PUDDLE_CHANCE roll
#   extra      additional puddles scattered around the first
#
# WHAT THE ACID DOES ONCE IT IS DOWN IS NOT HERE ANY MORE. This table used to
# carry life and tick columns and scale the one acid scene by them at spawn.
# There are nine puddle scenes now, and a lifetime living in two places is a
# lifetime that will disagree with itself — edit icepuddle.tscn, watch boss
# spikes ignore you, spend an evening on it. The scene owns what the hazard is;
# this table owns what the SPIKE does about it.
const ELEMENT_PROFILE := {
	# The plain spike, exactly as authored.
	Element.Type.NONE: {
		"telegraph": 1.00, "size": 1.00, "damage": 1.00, "ring_alpha": 1.00,
		"puddle": 1.0, "extra": 0,
	},
	# Does not hit harder — makes the ground it touched a problem.
	Element.Type.FIRE: {
		"telegraph": 1.00, "size": 1.00, "damage": 1.00, "ring_alpha": 1.00,
		"puddle": 1.3, "extra": 0,
	},
	# Slow, wide, and leaves a slick. Easy to see, hard to leave.
	#
	# THE 0.8 PAYS FOR icepuddle.tscn'S SIZE, the same way water's 0.5 pays for
	# its extra: 2. Ice is scaled 1.25 everywhere it appears - the spike, the
	# shot, the pool - and a pool scaled 1.25 covers 1.56x the floor, because
	# area goes as the square. At the old 1.2 multiplier that put ice at 35% of
	# the room in standing slick, against a 15% budget. At 0.8 it is 23%, beside
	# fire and poison, and ice still has the longest-lived and largest individual
	# pool in the game — there are simply fewer of them.
	Element.Type.ICE: {
		"telegraph": 1.35, "size": 1.25, "damage": 0.90, "ring_alpha": 1.00,
		"puddle": 0.8, "extra": 0,
	},
	# A snap. Barely any warning, small, gone without a trace.
	Element.Type.WIND: {
		"telegraph": 0.60, "size": 0.80, "damage": 0.90, "ring_alpha": 1.00,
		"puddle": 0.0, "extra": 0,
	},
	# The opposite: plenty of warning, and enormous.
	Element.Type.EARTH: {
		"telegraph": 1.30, "size": 1.35, "damage": 1.25, "ring_alpha": 1.00,
		"puddle": 1.0, "extra": 0,
	},
	# The fastest thing in the fight, and leaves nothing behind.
	Element.Type.LIGHT: {
		"telegraph": 0.55, "size": 1.00, "damage": 1.15, "ring_alpha": 1.00,
		"puddle": 0.0, "extra": 0,
	},
	# THE RING IS THE MECHANIC — normal timing and size, but you can
	# barely see it. Learn the pattern instead of reading it — the one
	# effect here that changes how you play rather than how much it hurts.
	Element.Type.DARK: {
		"telegraph": 1.00, "size": 1.00, "damage": 1.10, "ring_alpha": 0.22,
		"puddle": 1.0, "extra": 0,
	},
	# Spreads. One spike, three pools.
	#
	# THE 0.5 IS NOT WATER BEING SHY, IT IS THE extra: 2 BEING PAID FOR. Every
	# other element leaves one pool when it rolls; water leaves three, so an
	# equal chance is triple the floor. It sat at 1.4 and covered 54% of the
	# room in standing water - past the 44% swamp line bossenemy.gd's
	# PUDDLE_CHANCE comment was written to stay under, and worse than that
	# before the lifetimes moved into the scenes. At 0.5 x 3 pools it lands at
	# 19%, beside fire and ice, and water still SPREADS: it just does it less
	# often rather than doing it three times as much.
	Element.Type.WATER: {
		"telegraph": 1.00, "size": 1.05, "damage": 0.85, "ring_alpha": 1.00,
		"puddle": 0.5, "extra": 2,
	},
	# Here and gone: almost no telegraph, small, brief, vicious.
	Element.Type.LIGHTNING: {
		"telegraph": 0.50, "size": 0.85, "damage": 1.20, "ring_alpha": 1.00,
		"puddle": 0.8, "extra": 0,
	},
	# The original acid this whole system was built around.
	Element.Type.POISON: {
		"telegraph": 1.10, "size": 1.00, "damage": 0.85, "ring_alpha": 1.00,
		"puddle": 1.4, "extra": 0,
	},
}

# How far the extra pools water throws land from the spike, in pixels.
const SPREAD_RADIUS := 26.0


# =============================================================================
# THE BURST EACH SPIKE THROWS
# =============================================================================
# The firepit's embers, given one profile per element so a fire spike does not
# throw the same shower an ice one does. Colour comes from Element.colour_for()
# rather than being repeated here - the table is about MOTION.
#
# gravity is the giveaway for most of them: negative rises, positive falls.
# Fire and poison go up, earth and water arc and come back, dark sinks, and
# wind and light barely travel before they are spent.
#
# NONE is absent on purpose. A spike with no element throws nothing, the same
# rule the tint and the slag follow.
const ELEMENT_SPARKS := {
	# Embers, rising and dying. The firepit's, in the boss arena.
	Element.Type.FIRE: {
		"count": 26, "life": 0.75, "gravity": Vector2(0, -52),
		"spread": 22.0, "vmin": 24.0, "vmax": 58.0, "smin": 0.9, "smax": 2.0,
	},
	# Shards drifting down slowly. Cold does not rush.
	Element.Type.ICE: {
		"count": 18, "life": 1.10, "gravity": Vector2(0, 14),
		"spread": 38.0, "vmin": 16.0, "vmax": 40.0, "smin": 0.8, "smax": 1.6,
	},
	# Scattered wide and fast, then gone. Nothing lingers.
	Element.Type.WIND: {
		"count": 30, "life": 0.50, "gravity": Vector2(0, -6),
		"spread": 90.0, "vmin": 110.0, "vmax": 180.0, "smin": 0.6, "smax": 1.3,
	},
	# Heavy debris thrown up and falling back. It has weight.
	Element.Type.EARTH: {
		"count": 22, "life": 0.80, "gravity": Vector2(0, 150),
		"spread": 44.0, "vmin": 50.0, "vmax": 110.0, "smin": 1.2, "smax": 2.6,
	},
	# A flash outward in every direction, spent almost at once.
	Element.Type.LIGHT: {
		"count": 28, "life": 0.40, "gravity": Vector2(0, -10),
		"spread": 180.0, "vmin": 90.0, "vmax": 150.0, "smin": 0.7, "smax": 1.5,
	},
	# Wisps sinking rather than rising. Everything else goes up.
	Element.Type.DARK: {
		"count": 16, "life": 1.20, "gravity": Vector2(0, 26),
		"spread": 30.0, "vmin": 12.0, "vmax": 34.0, "smin": 1.0, "smax": 2.2,
	},
	# Droplets arcing up and coming back down.
	Element.Type.WATER: {
		"count": 24, "life": 0.85, "gravity": Vector2(0, 120),
		"spread": 50.0, "vmin": 60.0, "vmax": 120.0, "smin": 0.8, "smax": 1.8,
	},
	# Here and gone, like the spike that threw them.
	Element.Type.LIGHTNING: {
		"count": 20, "life": 0.30, "gravity": Vector2(0, -30),
		"spread": 120.0, "vmin": 140.0, "vmax": 220.0, "smin": 0.5, "smax": 1.2,
	},
	# Slow bubbles, the way the acid behaves once it lands.
	Element.Type.POISON: {
		"count": 14, "life": 1.30, "gravity": Vector2(0, -30),
		"spread": 26.0, "vmin": 14.0, "vmax": 32.0, "smin": 1.0, "smax": 2.2,
	},
}

# The master switch. Off by default so any other user of this scene gets no
# surprise hazards; bossenemy.gd turns it on for its eruptions.
@export var leaves_puddle: bool = false

# THE ROLL LIVES HERE, NOT IN THE CALLER, and that is what lets the element
# table scale it honestly. bossenemy.gd used to roll PUDDLE_CHANCE itself and
# hand down a bool — but a bool cannot be multiplied, so "fire leaves acid 30%
# more often" had nowhere to apply. bossenemy.gd now passes the chance and this
# rolls it against the element's multiplier.
@export_range(0.0, 1.0, 0.01) var puddle_chance: float = 0.35

# 0 means "whatever the element's puddle scene says". Same convention as
# EnemyData.projectile_damage: a zero is deference, not a value.
@export var puddle_tick_damage: int = 0

# Seconds the acid lasts. 0 means "whatever the element's puddle scene says",
# the same deference as the line above, and it is the default because the scene
# is now where that number is authored.
@export var puddle_lifetime: float = 0.0

# BOSS POOLS ARE SHORTER THAN THE SAME ELEMENT'S POOL FROM ANYTHING ELSE, and
# this is the one number that says so.
#
# A slime throws one acid ball. A spike carpet puts sixty pillars down in a few
# seconds and every one of them rolls for a pool - bossenemy.gd's PUDDLE_CHANCE
# comment works the floor coverage out, and it works it out against a pool life
# near 2.5s. The scenes range 1.0 to 5.0 because that is what those hazards are
# worth on their own; run ice's 5.0 through a carpet unscaled and the arena is
# a floor with holes in it rather than a fight.
#
# A SCALE, NOT AN ABSOLUTE, so the elements keep their shape relative to each
# other: at 0.6 ice still lingers two and a half times as long as lightning,
# which is the whole reason they were given different numbers.
@export_range(0.1, 2.0, 0.05) var puddle_life_scale: float = 0.6

# Radius of the drawn ring. KEEP THIS MATCHED TO THE CollisionShape2D in the
# scene — this value is only what the player is shown, and the shape is what
# actually decides the hit. They are two numbers describing one circle, which
# is exactly the kind of pair that drifts apart; spelltargetcircle.gd carries
# the same warning about the same mistake.
@export var ring_radius: float = 20.0

# Ring colour. Alpha here is the outline's; the fill uses a fraction of it.
@export var ring_color: Color = Color(0.9, 0.12, 0.12, 0.85)


# =============================================================================
# STATE
# =============================================================================

var _telegraph_age: float = 0.0
var _erupting: bool = false

# One damage application per eruption. frame_changed can fire more than once
# for a frame if the animation is restarted, and every character here carries
# both a body and a hurtbox area — arrow.gd's `_spent` latch exists for the
# same reason and its comment explains the double-damage bug in full.
var _spent: bool = false

# Filled by _apply_element_profile() from the table above. They exist as state
# rather than being read from the table at use time so that a designer can
# still override any of them on a placed instance without the element silently
# winning.
var _puddle_chance_scale: float = 1.0
var _puddle_extra: int = 0


# =============================================================================
# NODE REFERENCES
# =============================================================================

@onready var anim: AnimatedSprite2D = $animatedsprite2d


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	if not _validate_animation():
		queue_free()
		return

	# BEFORE ANYTHING READS telegraph_seconds, which _process() does on the very
	# next frame. This is also why bossenemy.gd sets element, damage, scale and
	# telegraph_seconds BEFORE add_child() rather than after: add_child is what
	# runs _ready(), so a profile applied here would otherwise be multiplying
	# values the caller has not set yet. poisonslime.gd's _spawn_slime() carries
	# the same note for the same reason.
	_apply_element_profile()

	# Hidden until the ring has finished filling. The spike is the payload,
	# not the warning — showing it during the telegraph would mean the player
	# is looking at the thing that is about to hurt them while it cannot.
	anim.visible = false

	anim.frame_changed.connect(_on_frame_changed)
	anim.animation_finished.connect(_on_animation_finished)

	queue_redraw()


func _validate_animation() -> bool:
	# Loud, early failure. Without these a missing animation throws inside
	# play() with an error that names neither this scene nor the caller.
	if anim == null:
		push_error("bossprojectile: animatedsprite2d not found")
		return false
	if anim.sprite_frames == null:
		push_error("bossprojectile: animatedsprite2d has no SpriteFrames")
		return false
	if not anim.sprite_frames.has_animation(RISE_ANIM):
		push_error("bossprojectile: SpriteFrames missing '%s' animation" % RISE_ANIM)
		return false
	if anim.sprite_frames.get_frame_count(RISE_ANIM) <= IMPACT_FRAME:
		push_error("bossprojectile: '%s' has too few frames for IMPACT_FRAME %d"
			% [RISE_ANIM, IMPACT_FRAME])
		return false
	return true


func _process(delta: float) -> void:
	if _erupting:
		return

	_telegraph_age += delta

	# Redrawn every frame ONLY while the ring is filling — this is the one
	# thing here that actually animates, and _draw returns immediately once
	# the spike takes over, so there is no per-frame cost afterwards.
	queue_redraw()

	if _telegraph_age >= telegraph_seconds:
		_erupt()


func _erupt() -> void:
	_erupting = true
	anim.visible = true
	anim.play(RISE_ANIM)
	# Clears the ring in the same frame the spike appears.
	queue_redraw()

	# ON THE ERUPTION, not on the telegraph. The burst is the spike arriving;
	# throwing it while the ring is still filling would announce the hit early
	# and undo the whole point of a telegraph.
	_burst_sparks()


func _apply_element_profile() -> void:
	# MULTIPLIERS, NOT VALUES. Everything here scales what the caller already
	# decided, so a pattern's own stagger survives: bossenemy.gd gives the lance
	# and the carpet different telegraphs per spike so the attack rolls outward,
	# and an element that replaced the number outright would flatten that back
	# into one clock.
	var p: Dictionary = ELEMENT_PROFILE.get(element, ELEMENT_PROFILE[Element.Type.NONE])

	telegraph_seconds = maxf(0.05, telegraph_seconds * float(p["telegraph"]))
	damage = maxi(1, int(round(damage * float(p["damage"]))))

	# Through scale, so the hitbox moves with the drawing. See the table header.
	var size: float = float(p["size"])
	if not is_equal_approx(size, 1.0):
		scale *= size

	# THE RING STAYS RED, whatever the element.
	#
	# It was briefly tinted per element and that was worse: the ring is not
	# decoration, it is the one piece of UI in this fight that means "stand
	# somewhere else", and a warning that changes colour depending on which
	# boss you drew is a warning you have to re-learn each time. One colour for
	# danger, always, is the more useful kind of consistency — the ELEMENT is
	# told by the spike and the slag it leaves, which are the things you look
	# at after you have already moved.
	#
	# Only the ALPHA is element-driven, and only for dark. See its profile row:
	# a ring you can barely see is a mechanic, not a palette choice.
	ring_color.a = ring_color.a * float(p["ring_alpha"])

	_apply_spike_tint()

	_puddle_chance_scale = float(p["puddle"])
	_puddle_extra = int(p["extra"])


func _apply_spike_tint() -> void:
	# NONE IS NOT A TINT. Physical's colour is steel, near-grey, so tinting a
	# grey spike with it would wash it paler and say nothing. A spike with no
	# element keeps exactly the pixels the artist drew - the same rule
	# BaseEnemy._apply_element_recolour() states for creatures.
	if element == Element.Type.NONE:
		return
	if anim == null:
		return

	# THE SCENE WINS. icebossprojectile.tscn and its five siblings carry an
	# authored hearth_warm material, shared by every instance of that scene, and
	# bossenemy.gd hands the right one to _spawn_one_eruption(). This guard is
	# what makes that worth doing.
	#
	# IT IS THE BIGGEST SINGLE SAVING IN THE FIGHT. A carpet is sixty-five
	# spikes, and the line below used to build sixty-five Materials for it — in
	# the same frame the pattern is also placing sixty-five Area2Ds and rolling
	# for a pool on each. Now it builds none.
	#
	# What is left is the fallback for an element with no spike scene of its own.
	if anim.material != null:
		return

	var mat := ShaderMaterial.new()
	mat.shader = SPIKE_SHADER
	mat.set_shader_parameter("warmth", 1.0)
	mat.set_shader_parameter("warm_tint", Element.colour_for(element))
	mat.set_shader_parameter("lift", SPIKE_LIFT)
	anim.material = mat


func _burst_sparks() -> void:
	# A STANDALONE EMITTER, NOT A CHILD, and that is the whole reason this is
	# not four lines. This node queue_free()s the moment its rise animation
	# ends, and a child emitter dies with it - so the last third of every burst
	# would be cut off mid-air. Parenting into the same ground container the
	# slag uses lets the sparks outlive the spike that threw them, which is what
	# they have to do to look like anything.
	#
	# Built in code rather than added to bossprojectile.tscn for the reason the
	# firepit's embers are: the editor rewrites an open scene from its in-memory
	# copy on save, and this project has already lost committed .tscn edits that
	# way. A node the script makes cannot be clobbered by a save that did not
	# know about it.
	if not ELEMENT_SPARKS.has(element):
		return

	var p: Dictionary = ELEMENT_SPARKS[element]

	var container: Node = get_tree().get_first_node_in_group("groundeffects")
	if container == null:
		container = get_tree().current_scene
	if container == null:
		return

	var burst := CPUParticles2D.new()
	burst.name = "spikesparks"
	burst.emitting = false
	burst.one_shot = true

	# EXPLOSIVENESS 1.0 is what makes this a burst rather than a fountain: every
	# particle is emitted on the same frame instead of spread across `lifetime`.
	burst.explosiveness = 1.0
	burst.amount = int(p["count"])
	burst.lifetime = float(p["life"])

	# Emitted into world space so the sparks keep travelling after this spike is
	# gone, rather than being dragged around by a transform that no longer
	# exists.
	burst.local_coords = false

	burst.direction = Vector2.UP
	burst.spread = float(p["spread"])
	burst.gravity = p["gravity"]
	burst.initial_velocity_min = float(p["vmin"])
	burst.initial_velocity_max = float(p["vmax"])
	burst.scale_amount_min = float(p["smin"])
	burst.scale_amount_max = float(p["smax"])

	# Emitted across the spike's footprint rather than from a single point, so a
	# big earth spike throws a wide shower and a small wind one does not.
	burst.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	burst.emission_rect_extents = Vector2(ring_radius * 0.5, 3.0) * scale

	burst.color_ramp = _spark_ramp()
	burst.z_index = 1

	container.add_child(burst)
	burst.global_position = global_position
	burst.reset_physics_interpolation()
	burst.emitting = true

	_free_after(burst, float(p["life"]) + 0.25)


func _spark_ramp() -> Gradient:
	# A RAW Gradient. CPUParticles2D.color_ramp is typed Gradient; it is
	# ParticleProcessMaterial, which the GPU emitter uses, whose equivalent is a
	# GradientTexture1D. The two read the same-named property as different
	# types, and wrapping this would be a hard parse error.
	var tint: Color = Element.colour_for(element)

	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	ramp.colors = PackedColorArray([
		# Starts brighter than the element's own colour so the spark reads as
		# something hot rather than as a coloured dot, then settles onto the
		# element and fades out.
		Color(minf(tint.r + 0.35, 1.0), minf(tint.g + 0.35, 1.0), minf(tint.b + 0.35, 1.0), 1.0),
		Color(tint.r, tint.g, tint.b, 0.8),
		Color(tint.r * 0.5, tint.g * 0.5, tint.b * 0.5, 0.0),
	])
	return ramp


func _free_after(node: Node, seconds: float) -> void:
	# A one_shot emitter stops emitting but does not free itself, and these are
	# spawned sixty-five at a time. Without this a long fight leaves a few
	# thousand finished emitters parented to the ground container.
	await get_tree().create_timer(seconds).timeout

	# PAST AN AWAIT. A SceneTreeTimer belongs to the tree rather than to either
	# node here, so it outlives a scene change - the same guard every await in
	# src/world/ carries.
	if is_instance_valid(node):
		node.queue_free()


# =============================================================================
# THE RING
# =============================================================================

func _draw() -> void:
	# Drawn rather than authored as a sprite because the fill has to track a
	# tunable duration. A pre-rendered ring animation would silently stop
	# matching telegraph_seconds the moment anyone changed it.
	if _erupting:
		return

	var progress: float = clampf(
		_telegraph_age / maxf(telegraph_seconds, 0.001), 0.0, 1.0)

	# The fill grows from the centre outward, so "full" reads as "now" without
	# the player having to time anything consciously.
	var fill: Color = ring_color
	fill.a = ring_color.a * 0.3
	draw_circle(Vector2.ZERO, ring_radius * progress, fill)

	# The outline is at full radius from the first frame, so the dangerous area
	# is known immediately — only the timing is in question, never the extent.
	draw_arc(Vector2.ZERO, ring_radius, 0.0, TAU, 32, ring_color, 2.0, true)


# =============================================================================
# IMPACT
# =============================================================================

func _on_frame_changed() -> void:
	if _spent or not _erupting:
		return
	if anim.animation != RISE_ANIM:
		return
	if anim.frame != IMPACT_FRAME:
		return

	_spent = true
	_damage_players_inside()


func _damage_players_inside() -> void:
	# ONE hit per player, however many of their collision nodes are inside the
	# ring. A character with a body and a hurtbox on the same layer would
	# otherwise take the spike twice — see acidpuddle.gd, which dedupes by
	# instance id for exactly this reason.
	var already_hit: Array[int] = []

	for target in _overlapping_player_nodes():
		var id: int = target.get_instance_id()
		if id in already_hit:
			continue
		already_hit.append(id)
		target.take_damage(damage, element)


func _overlapping_player_nodes() -> Array[Node]:
	# Both lists, because some things collide as bodies and some expose a
	# hurtbox Area2D whose PARENT is the real character.
	var found: Array[Node] = []

	for body in get_overlapping_bodies():
		if _is_damageable_player(body):
			found.append(body)

	for area in get_overlapping_areas():
		var parent: Node = area.get_parent()
		if _is_damageable_player(parent):
			found.append(parent)

	return found


func _is_damageable_player(node: Node) -> bool:
	return node != null \
		and node.is_in_group(&"player") \
		and node.has_method(&"take_damage")


# =============================================================================
# CLEANUP
# =============================================================================

func _on_animation_finished() -> void:
	# Guarded on the animation name in case a variant ever plays debris or a
	# settle sequence after the rise.
	if anim.animation == RISE_ANIM:
		_leave_puddle()
		queue_free()


func _leave_puddle() -> void:
	# AT THE END OF THE SPIKE, not at the start. The acid is what the spike
	# leaves behind as it sinks, so it appears as the animation finishes - which
	# also means a player who dodged the eruption has already moved, and is not
	# handed a puddle on top of themselves for their trouble.
	if not leaves_puddle:
		return

	# The element's multiplier on the caller's chance. Wind and light are 0.0
	# here — they leave nothing at all, which is as much a part of how they
	# fight as the fast telegraph is.
	if randf() >= clampf(puddle_chance * _puddle_chance_scale, 0.0, 1.0):
		return

	# Captured NOW. queue_free() runs immediately after this returns, so reading
	# global_position inside the deferred calls below would be reading it off a
	# node that is on its way out.
	var landing: Vector2 = global_position

	# The y-sorted ground container, so acid draws UNDER characters. Same
	# lookup and same fallback as poisonprojectile.gd and bushmage's vine — a
	# level missing the container still gets its puddle, just sorted wrong.
	var container: Node = get_tree().get_first_node_in_group("groundeffects")
	if container == null:
		container = get_tree().current_scene
	if container == null:
		return

	_drop_one_puddle(container, landing)

	# WATER SPREADS. One spike, several pools, thrown a little way out so the
	# shape on the floor is a splash rather than a stack. Every other element
	# has extra = 0 and never enters this loop.
	for i in range(_puddle_extra):
		var angle: float = randf() * TAU
		var dist: float = SPREAD_RADIUS * sqrt(randf())
		_drop_one_puddle(container, landing + Vector2(cos(angle), sin(angle)) * dist)


func _drop_one_puddle(container: Node, at: Vector2) -> void:
	# THE SPIKE'S ELEMENT PICKS THE SCENE. A fire boss leaving green acid behind
	# is the kind of drift the element work exists to stop, and this is where it
	# is stopped — one lookup instead of a recolour, a lifetime and a tick
	# applied to the wrong scene three lines apart.
	#
	# This is also why bossenemy.gd stamps the caster's element onto the
	# eruption: without that, every boss on the floor drops poison.
	var puddle: Node2D = Puddles.scene_for(element).instantiate()

	# Redundant for nine of the ten cases — the scene already carries it — and
	# kept for the tenth. scene_for() falls back to poison for an element with
	# no scene of its own, and the pool should still deal the damage TYPE it was
	# made with even when it is wearing someone else's art.
	puddle.element = element

	# The explicit override wins; zero defers to the scene, which is where the
	# per-element tick now lives.
	if puddle_tick_damage > 0:
		puddle.tick_damage = puddle_tick_damage

	# Same deference, plus the boss-carpet scale. See puddle_life_scale for why
	# a spike's pool is shorter than the same element's pool from a slime.
	if puddle_lifetime > 0.0:
		puddle.lifetime = puddle_lifetime
	elif not is_equal_approx(puddle_life_scale, 1.0):
		puddle.lifetime = maxf(0.2, puddle.lifetime * puddle_life_scale)

	# ONE DEFERRED CALL, not three. The pool places itself in _ready() from
	# spawn_at, so the position and the interpolation reset no longer need
	# queueing separately — at sixty pools that is a hundred and twenty fewer
	# deferred calls in a frame already erupting sixty-five spikes.
	puddle.spawn_at = at
	container.call_deferred("add_child", puddle)
