# spelltargetcircle.gd — stalagmite spell that drops at a target position.
# spawned by mage.gd at cursor position. plays a fall animation, damages
# enemies inside the radius on impact frame, despawns when animation ends.
#
# spawn flow:
# 1. mage casts → instantiates this scene at cursor position
# 2. mage sets explosion_damage based on magic skill
# 3. _ready validates the animation, plays "fall", queues redraw of the
#    targeting ring
# 4. on frame 4 (visual impact), damage applies to all enemies inside the
#    Area2D's collision shape
# 5. on animation_finished, the scene despawns
#
# why frame 4:
# the 8-frame "fall" animation peaks visually at frame 4 (stalagmite slams
# into the ground). damage on frame 4 syncs the gameplay hit with the
# visual impact. adjust if you retime the animation.
#
# scene structure:
# - Area2D root (this script)
# - stalagmiteprojectile (AnimatedSprite2D) — sprite offset upward in the
#   scene so the stalagmite renders above ground and falls down through
#   animation frames
# - CollisionShape2D — circular, matches circle_radius for AoE detection
extends Area2D


# =============================================================================
# CONSTANTS
# =============================================================================

# frame of the "fall" animation where damage is applied.
# tune to match the visual impact (stalagmite touching ground).
const IMPACT_FRAME := 4


# =============================================================================
# STATE
# =============================================================================

# damage dealt to enemies on impact frame — set by mage when spawning.
# scales with the mage's magic skill (magic × damage_per_magic in mage.gd).
var explosion_damage: int = 0

# visual radius of the target ring drawn on the ground.
# does NOT control the actual damage area — that's the CollisionShape2D
# on the Area2D root. keep this value matched to that shape's radius.
var circle_radius: float = 14.0


# =============================================================================
# NODE REFERENCES
# =============================================================================

# the falling stalagmite sprite. positioned in the scene with a Y-offset so
# it renders ABOVE the ground at frame 0 and falls down through frame 4.
@onready var anim: AnimatedSprite2D = $stalagmiteprojectile


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# validate the animation setup defensively — without these guards, a
	# missing or empty animation would crash on play() with a cryptic error.
	# fail loudly with a queue_free so dev catches the issue immediately.
	if not _validate_animation():
		queue_free()
		return

	anim.animation_finished.connect(_on_animation_finished)
	anim.frame_changed.connect(_on_frame_changed)
	anim.play("fall")

	# trigger _draw so the targeting ring renders on the first frame
	queue_redraw()


func _validate_animation() -> bool:
	# checks the AnimatedSprite2D exists, has the "fall" animation, and that
	# the animation has at least one frame. returns true if everything's
	# valid, false otherwise (caller queue_free's on false).
	if anim == null:
		push_error("spelltargetcircle: stalagmiteprojectile AnimatedSprite2D not found")
		return false
	if not anim.sprite_frames.has_animation("fall"):
		push_error("spelltargetcircle: SpriteFrames missing 'fall' animation")
		return false
	if anim.sprite_frames.get_frame_count("fall") == 0:
		push_error("spelltargetcircle: 'fall' animation has zero frames")
		return false
	return true


# =============================================================================
# VISUAL TARGETING RING
# =============================================================================

func _draw() -> void:
	# red ring on the ground at spell position — shows the AoE radius.
	# rendered every frame _draw is called, but since the circle is static
	# we only queue_redraw once on _ready (no per-frame overdraw cost).
	var outline_color: Color = Color(1.0, 0.1, 0.1, 0.75)
	var line_thickness: float = 2.0
	draw_arc(
		Vector2.ZERO,
		circle_radius,
		0,
		TAU,
		32,
		outline_color,
		line_thickness,
		true,
	)


# =============================================================================
# IMPACT / DAMAGE
# =============================================================================

func _on_frame_changed() -> void:
	# damage fires on IMPACT_FRAME — the visual moment the stalagmite hits
	# the ground. naturally fires once per cast since the animation doesn't
	# loop and only one cast spawns this scene.
	if anim.animation != "fall":
		return
	if anim.frame != IMPACT_FRAME:
		return
	_apply_area_damage()


func _apply_area_damage() -> void:
	# damage all enemies currently inside the Area2D's collision shape.
	# scans get_overlapping_bodies at the moment of impact — enemies that
	# enter the area AFTER this frame are not hit (instant AoE, no DoT).
	for body in get_overlapping_bodies():
		if not body.is_in_group("enemies"):
			continue
		if not body.has_method("take_damage"):
			continue
		body.take_damage(explosion_damage)


# =============================================================================
# CLEANUP
# =============================================================================

func _on_animation_finished() -> void:
	# despawn when the fall animation completes.
	# guarded against finishing OTHER animations in case future variants
	# play multiple sequences (impact debris, residual particles, etc.).
	if anim.animation == "fall":
		queue_free()
