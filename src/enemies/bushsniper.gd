# bushsniper enemy — ranged archer that fires arrows at the player.
# uses BaseEnemy's default flee/attack/chase pattern. on each attack
# animation cycle, fires a tracking arrow at the player's position at
# the moment of release (frame 5).
#
# attack flow:
# 1. BaseEnemy._physics_process puts bushsniper in attack range
# 2. _trigger_attack plays directional attack animation
# 3. animation reaches ARROW_RELEASE_FRAME (frame 5)
# 4. fire_projectile spawns an arrow at the directional spawn marker
# 5. arrow aims at the player's CURRENT position (lead-tracking shot)
# 6. arrow travels in a straight line until hit, wall, or lifetime expiry
#
# directional spawn markers:
# four Marker2D children (arrowspawnleft/right/top/bottom) define where
# arrows emerge based on which direction bushsniper is facing. positioned
# at the bow tip in each direction so arrows visually originate correctly.
extends BaseEnemy
class_name BushSniper


# =============================================================================
# CONSTANTS
# =============================================================================

# preloaded arrow scene — instantiated on each shot
const ARROW_SCENE := preload("res://scene/projectiles/arrow.tscn")

# frame of the attack animation where the arrow is released.
# matches the visual peak where the bow string snaps back. adjust if you
# retime the attack animation.
const ARROW_RELEASE_FRAME := 5


# =============================================================================
# NODE REFERENCES
# =============================================================================

@onready var sprite: AnimatedSprite2D = $animatedsprite2d

# spawn markers per direction — arrows emerge from the correct side of
# bushsniper's sprite based on which way it's facing.
@onready var spawn_nodes: Dictionary = {
	"left":  $arrowspawnleft,
	"right": $arrowspawnright,
	"up":    $arrowspawntop,
	"down":  $arrowspawnbottom,
}


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# class-specific stat overrides BEFORE super._ready() so BaseEnemy
	# wires the healthbar and attack timer with the right values
	max_hp          = 80
	attack_cooldown = 2.0
	attack_range    = 200.0
	flee_range      = 50.0

	super._ready()

	# wire frame_changed so we can fire the arrow on ARROW_RELEASE_FRAME
	sprite.frame_changed.connect(_on_frame_changed)


# =============================================================================
# SUBCLASS OVERRIDES
# =============================================================================

func get_move_speed() -> float:
	return 80.0


func fire_projectile() -> void:
	# spawn an arrow at the directional spawn marker, aimed at the player's
	# position at the moment of release. uses call_deferred for the add_child
	# so we don't mutate the scene tree mid-physics-frame.
	var spawn_node: Marker2D = spawn_nodes.get(attack_direction)
	if spawn_node == null or player == null:
		return

	var arrow: Node = ARROW_SCENE.instantiate()
	get_tree().current_scene.add_child.call_deferred(arrow)
	arrow.global_position = spawn_node.global_position

	# aim at the player's current position — straight-line shot, no lead.
	var to_player: Vector2 = player.global_position - spawn_node.global_position
	arrow.shoot_vector(to_player)


# =============================================================================
# ANIMATION HOOKS
# =============================================================================

func _on_frame_changed() -> void:
	# fires the arrow exactly once each time the attack animation reaches
	# the release frame. since the attack animation is non-looping (Loop OFF
	# in SpriteFrames) and BaseEnemy._trigger_attack only restarts when the
	# animation NAME changes, this fires once per attack cycle.
	if not sprite.animation.begins_with("attack"):
		return
	if sprite.frame != ARROW_RELEASE_FRAME:
		return
	fire_projectile()
