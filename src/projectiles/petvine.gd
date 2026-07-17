# petvine.gd — pet attack that erupts UNDER the target enemy (like a root/trap
# effect), rather than traveling as a projectile. spawns directly at the
# target's position, plays its animation, and damages enemies overlapping on
# the impact frame. mirrors vine.gd's stationary-AoE behavior, but is spawned
# AT the enemy instead of at the attacker, and targets "enemies" not "player".
extends Area2D


# =============================================================================
# EXPORTED SETTINGS
# =============================================================================

@export var damage: int = 4
@export var impact_frame: int = 4

# which group this vine damages. pets set "enemies".
@export var target_group: String = "enemies"


# =============================================================================
# STATE
# =============================================================================

var _has_damaged: bool = false


# =============================================================================
# NODE REFERENCES
# =============================================================================

@onready var sprite: AnimatedSprite2D = $animatedsprite2d


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	sprite.frame_changed.connect(_on_frame_changed)
	sprite.animation_finished.connect(_on_animation_finished)


# =============================================================================
# PUBLIC API
# =============================================================================

func fire(direction: String) -> void:
	# direction is kept for animation variety/flavor (which directional vine
	# clip plays), even though the vine no longer travels — it erupts in place
	# wherever pet.gd positioned it (at the target).
	var anim_name: String = "vine" + direction
	if not sprite.sprite_frames.has_animation(anim_name):
		push_warning("PetVine: missing animation '%s', falling back to vinedown" % anim_name)
		anim_name = "vinedown"
	sprite.play(anim_name)


# =============================================================================
# DAMAGE TRIGGER
# =============================================================================

func _on_frame_changed() -> void:
	if _has_damaged:
		return
	if sprite.frame == impact_frame:
		_apply_damage_to_overlapping_enemies()
		_has_damaged = true


func _apply_damage_to_overlapping_enemies() -> void:
	for body in get_overlapping_bodies():
		if body.is_in_group(target_group) and body.has_method("take_damage"):
			body.take_damage(damage)


# =============================================================================
# CLEANUP
# =============================================================================

func _on_animation_finished() -> void:
	queue_free()
