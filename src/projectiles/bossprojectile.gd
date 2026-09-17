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
@export var damage_type: StringName = &"physical"

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
		target.take_damage(damage, damage_type)


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
		queue_free()
