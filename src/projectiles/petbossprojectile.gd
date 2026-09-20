# petbossprojectile.gd — the boss's spike eruption, turned around to hit
# ENEMIES instead of the player. This is the boss pet's whole attack.
#
# WHY THIS IS NOT bossprojectile.gd WITH A DIFFERENT MASK. That script's
# _is_damageable_player() checks is_in_group(&"player") by name, and its own
# header says it "ONLY DAMAGES PLAYERS" on purpose, the same way acidpuddle.gd
# does. Flipping collision_mask on the scene would have let the pet's spike
# OVERLAP enemies and then damage nobody — a hitbox that connects and does
# nothing, which is the worst kind of bug to find later. So this is the
# pet-side counterpart, and it is modelled on petvine.gd (the project's
# existing "pet drops a hazard on the target" script) rather than on the boss.
#
# SHRUNKEN IN THE SCENE, NOT HERE. The eruption art and its CircleShape2D are
# authored at the boss's full radius 20. petbossprojectile.tscn scales the root
# Area2D to 0.35, which moves the sprite, the hitbox and the telegraph ring
# together and keeps them from drifting apart — the same reasoning bossenemy.gd
# gives for scaling the node instead of resizing the shape. Editing the radius
# here would resize every other spike on screen, because sub-resources are
# shared between instances of a scene unless made local.
extends Area2D


# =============================================================================
# CONSTANTS
# =============================================================================

# Frame of the rise animation where the spike is at full extension. Taken from
# bossprojectile.gd, which measured it off the sheet rather than guessing: the
# five frames are 0 a nub breaking the surface, 1 FULL HEIGHT, 2 full height
# narrowing, 3 sinking, 4 nearly gone. The midpoint frame is already on the way
# back down, so damage there would land after the spike visibly passed.
const IMPACT_FRAME := 1

# The animation's name inside the scene's SpriteFrames.
const RISE_ANIM := &"projectile"

# The pool this leaves behind. A FIXED SCENE, not a Puddles.scene_for() lookup
# like bossprojectile.gd does: that table maps an ELEMENT to its pool, and the
# boss stamps its own element onto every spike so a fire boss leaves fire. The
# boss pet has no element — it is one pet with the original art, dropped by all
# seven Crowned — so there is nothing to look up and poison is simply what it
# leaves.
#
# Safe to preload: petpoisonpuddle.tscn runs acidpuddle.gd, not this script, so
# there is no cycle of the kind Puddles.gd exists to avoid.
const PUDDLE_SCENE := preload("res://scene/projectiles/petpoisonpuddle.tscn")


# =============================================================================
# EXPORTED SETTINGS
# =============================================================================

# Set by pet.gd::_fire_vine() from the pet's own projectile_damage, already
# scaled by the owner's stats. The default is only what a loose instance in the
# editor would do.
@export var damage: int = 54

# Which group this eruption damages. "enemies" is the point of the whole file;
# it is exported anyway to match petvine.gd's shape.
@export var target_group: String = "enemies"

# How long the ring is shown before the spike arrives.
#
# MUCH SHORTER THAN THE BOSS'S. On the boss this is the difficulty dial and
# sits at 0.52-0.9, because it is the player's entire reaction window. Nothing
# here is reacting — enemies do not dodge — so every millisecond of telegraph
# is dead time between the pet casting and the hit landing. It is kept non-zero
# only so the spike reads as a boss attack rather than appearing from nowhere.
@export var telegraph_seconds: float = 0.18

# Radius of the drawn warning ring, in the node's LOCAL space, so it shrinks
# with the root scale exactly like the sprite and the hitbox do. Matched to the
# authored CircleShape2D radius so the ring shows where the spike will actually
# connect, rather than a size someone picked by eye.
@export var ring_radius: float = 20.0

@export var ring_color: Color = Color(0.9, 0.12, 0.12, 0.85)


# =============================================================================
# PUDDLE
# =============================================================================

# Whether the spike leaves acid as it sinks, the way the boss's does.
@export var leaves_puddle: bool = true

# HOW OFTEN, and it is deliberately not 1.0. A pet attacks about every two
# seconds and a pool lasts three, so a puddle on every cast would mean the
# ground under a fight is permanently wet and the pet's real attack — the spike
# — stops being the thing you read. Half is often enough to matter and sparse
# enough to still be an event.
#
# bossenemy.gd uses 0.35 for the same reason from the other side. Raise this to
# 1.0 if you want to watch it work.
@export_range(0.0, 1.0, 0.01) var puddle_chance: float = 0.5

# Zero defers to the scene, which is where the authored values live. Same
# deference bossprojectile.gd uses, and for the same reason: the pool's tick and
# lifetime belong in the file you can open and look at, not in an override that
# silently wins.
@export var puddle_tick_damage: int = 0
@export var puddle_lifetime: float = 0.0


# =============================================================================
# STATE
# =============================================================================

var _has_damaged: bool = false
var _erupting: bool = false
var _telegraph_age: float = 0.0


# =============================================================================
# NODE REFERENCES
# =============================================================================

@onready var sprite: AnimatedSprite2D = $animatedsprite2d


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	if not _validate_animation():
		queue_free()
		return

	# Hidden until the ring has finished filling. The spike is the payload, not
	# the warning — showing it during the telegraph would mean looking at the
	# thing that is about to hit while it cannot.
	sprite.visible = false

	sprite.frame_changed.connect(_on_frame_changed)
	sprite.animation_finished.connect(_on_animation_finished)

	queue_redraw()


func _validate_animation() -> bool:
	# Loud, early failure. Without these a missing animation throws inside
	# play() with an error that names neither this scene nor the caller.
	if sprite == null:
		push_error("petbossprojectile: animatedsprite2d not found")
		return false
	if sprite.sprite_frames == null:
		push_error("petbossprojectile: animatedsprite2d has no SpriteFrames")
		return false
	if not sprite.sprite_frames.has_animation(RISE_ANIM):
		push_error("petbossprojectile: SpriteFrames missing '%s' animation" % RISE_ANIM)
		return false
	if sprite.sprite_frames.get_frame_count(RISE_ANIM) <= IMPACT_FRAME:
		push_error("petbossprojectile: '%s' has too few frames for IMPACT_FRAME %d"
			% [RISE_ANIM, IMPACT_FRAME])
		return false
	return true


func _process(delta: float) -> void:
	if _erupting:
		return

	_telegraph_age += delta

	# Redrawn every frame ONLY while the ring is filling. _draw() returns
	# immediately once the spike takes over, so there is no per-frame cost
	# after that.
	queue_redraw()

	if _telegraph_age >= telegraph_seconds:
		_erupt()


func _erupt() -> void:
	_erupting = true
	sprite.visible = true
	sprite.play(RISE_ANIM)
	# Clears the ring in the same frame the spike appears.
	queue_redraw()


# =============================================================================
# PUBLIC API
# =============================================================================

func fire(_direction: String) -> void:
	# pet.gd::_fire_vine() calls this with a cardinal so a directional hazard
	# can pick its clip. The eruption has ONE animation and comes straight up
	# out of the ground, so there is nothing to face and the argument is
	# ignored — the parameter stays because pet.gd calls fire() on anything
	# that has the method, and dropping it would be a silent arity error.
	#
	# Deliberately does NOT play here. _process() starts the animation when the
	# telegraph expires; playing it now would show the spike during the warning.
	pass


# =============================================================================
# DAMAGE TRIGGER
# =============================================================================

func _on_frame_changed() -> void:
	if _has_damaged:
		return
	if sprite.frame == IMPACT_FRAME:
		_apply_damage_to_overlapping_enemies()
		_has_damaged = true


func _apply_damage_to_overlapping_enemies() -> void:
	# Mirrors petvine.gd exactly, including using bodies rather than areas: an
	# enemy that carries both a body and a hurtbox would otherwise be hit twice
	# by one spike.
	for body in get_overlapping_bodies():
		if body.is_in_group(target_group) and body.has_method("take_damage"):
			body.take_damage(damage)


# =============================================================================
# TELEGRAPH RING
# =============================================================================

func _draw() -> void:
	if _erupting:
		return

	var fill: float = 1.0
	if telegraph_seconds > 0.0:
		fill = clampf(_telegraph_age / telegraph_seconds, 0.0, 1.0)

	# Outline at full size plus a filling disc, so the ring reads as a countdown
	# rather than a static decal — the same tell the boss uses, just faster.
	draw_arc(Vector2.ZERO, ring_radius, 0.0, TAU, 32, ring_color, 2.0, true)
	if fill > 0.0:
		var inner: Color = ring_color
		inner.a *= 0.35
		draw_circle(Vector2.ZERO, ring_radius * fill, inner)


# =============================================================================
# CLEANUP
# =============================================================================

func _on_animation_finished() -> void:
	_leave_puddle()
	queue_free()


func _leave_puddle() -> void:
	# AT THE END OF THE SPIKE, not at the start — the acid is what the spike
	# leaves behind as it sinks. Straight from bossprojectile.gd, and the timing
	# is the whole point of putting it here rather than in _erupt().
	if not leaves_puddle:
		return
	if randf() >= clampf(puddle_chance, 0.0, 1.0):
		return

	# CAPTURED NOW. queue_free() runs immediately after this returns, so reading
	# global_position off this node any later reads it off something on its way
	# out.
	var landing: Vector2 = global_position

	# The y-sorted ground container, so acid draws UNDER characters. Same lookup
	# and same fallback as bossprojectile.gd and pet.gd::_parent_to_group() — a
	# level with no container still gets its pool, just sorted wrong.
	var container: Node = get_tree().get_first_node_in_group("groundeffects")
	if container == null:
		container = get_tree().current_scene
	if container == null:
		return

	# TYPED AS AcidPuddle, not Node2D. bossprojectile.gd uses Node2D here and
	# every property it then sets is an unsafe access the compiler cannot check
	# — it has to, because Puddles.scene_for() can return any of nine scenes.
	# This one knows exactly what it is instantiating, so spawn_at, tick_damage
	# and lifetime are checked when the file is parsed rather than trusted.
	var puddle: AcidPuddle = PUDDLE_SCENE.instantiate()

	if puddle_tick_damage > 0:
		puddle.tick_damage = puddle_tick_damage
	if puddle_lifetime > 0.0:
		puddle.lifetime = puddle_lifetime

	# acidpuddle.gd reads spawn_at in _ready() and places itself, which is why
	# this is set BEFORE add_child rather than assigning global_position after.
	puddle.spawn_at = landing
	container.add_child(puddle)
