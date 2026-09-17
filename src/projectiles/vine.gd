# vine.gd — stationary directional vine attack spawned by bushmage.
# the vine plays a stretch animation in one of 4 cardinal directions,
# damages the player on its impact frame, and despawns when the
# animation finishes.
#
# spawn flow:
# 1. bushmage's attack animation hits frame 3
# 2. bushmage spawns this scene at its own position
# 3. fire(direction) is called by bushmage to set the animation
# 4. vine plays vineleft / vineright / vineup / vinedown
# 5. damage applied on DAMAGE_FRAME of its own animation
# 6. queue_free() on animation_finished
extends Area2D


# =============================================================================
# EXPORTED SETTINGS
# =============================================================================

# damage dealt to the player on the impact frame
@export var damage: int = 9

# frame of the vine animation where damage is dealt.
# tune to match the visual peak of the vine reaching the player.
@export var impact_frame: int = 4


# =============================================================================
# STATE
# =============================================================================

# tracks whether damage has been applied this animation cycle,
# so a vine can't double-hit if its hitbox overlaps the player
# across multiple frames.
var _has_damaged: bool = false


# =============================================================================
# NODE REFERENCES
# =============================================================================

@onready var sprite: AnimatedSprite2D = $animatedsprite2d


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# wire animation hooks for damage timing and auto-despawn
	sprite.frame_changed.connect(_on_frame_changed)
	sprite.animation_finished.connect(_on_animation_finished)


# =============================================================================
# PUBLIC API
# =============================================================================

func fire(direction: String) -> void:
	# called by bushmage after spawning. picks the right directional
	# animation and starts playback. invalid direction strings fall back
	# to "down" so the vine never silently fails to render.
	var anim_name: String = "vine" + direction
	if not sprite.sprite_frames.has_animation(anim_name):
		push_warning("Vine: missing animation '%s', falling back to vinedown" % anim_name)
		anim_name = "vinedown"
	sprite.play(anim_name)


# =============================================================================
# DAMAGE TRIGGER
# =============================================================================

func _on_frame_changed() -> void:
	# damage fires once on impact_frame. _has_damaged guards against
	# the player walking back into the vine during later frames and
	# taking damage twice.
	if _has_damaged:
		return
	if sprite.frame == impact_frame:
		_apply_damage_to_overlapping_players()
		_has_damaged = true


func _apply_damage_to_overlapping_players() -> void:
	# scan everything currently inside the vine's collision area and
	# damage any player-grouped body that exposes take_damage.
	for body in get_overlapping_bodies():
		if body.is_in_group("player") and body.has_method("take_damage"):
			body.take_damage(damage)


# =============================================================================
# CLEANUP
# =============================================================================

func _on_animation_finished() -> void:
	# vine retracts and despawns when its animation completes.
	# Loop must be OFF on all 4 directional animations or this never fires.
	queue_free()
