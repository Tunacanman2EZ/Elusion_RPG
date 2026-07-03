# firesprite enemy — ranged magic caster that fires fire orbs at the player.
# slightly tougher than electricspirit but shorter range, with faster shot
# cadence (2.0s cooldown vs electricspirit's 2.5s).
#
# uses BaseEnemy's default flee/attack/chase pattern. on each attack animation
# cycle, fires a fire-typed projectile at the player's position at the moment
# of release (frame 5).
#
# attack flow:
# 1. BaseEnemy._physics_process puts firesprite in attack range
# 2. _trigger_attack plays directional attack animation
# 3. animation reaches ORB_RELEASE_FRAME (frame 5)
# 4. fire_projectile spawns a fire orb at the directional spawn marker
# 5. orb aims at the player's CURRENT position (lead-tracking shot)
# 6. orb travels in a straight line until hit, wall, or screen exit
#
# projectile container:
# if a "projectiles" group node exists, orbs parent under it for tidier
# scene organization. otherwise they parent to the current scene root.
# matches bushsniper and electricspirit for consistency.
extends BaseEnemy
class_name FireSprite


# =============================================================================
# CONSTANTS
# =============================================================================

# preloaded fire orb scene — instantiated on each shot
const FIRE_ORB_SCENE := preload("res://scene/projectiles/fireprojectile.tscn")

# frame of the attack animation where the orb is released.
# tune to match the visual peak of the cast (hands release flame).
# adjust if you retime the attack animation.
const ORB_RELEASE_FRAME := 5


# =============================================================================
# NODE REFERENCES
# =============================================================================

@onready var sprite: AnimatedSprite2D = $animatedsprite2d

# spawn markers per direction — orbs emerge from the correct side of
# firesprite's sprite based on facing direction.
@onready var spawn_nodes: Dictionary = {
	"left":  $orbspawnleft,
	"right": $orbspawnright,
	"up":    $orbspawntop,
	"down":  $orbspawnbottom,
}


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# class-specific stat overrides BEFORE super._ready() so BaseEnemy
	# wires the healthbar and attack timer with the right values
	max_hp          = 70
	attack_cooldown = 2.0       # faster cadence than electricspirit (2.5)
	attack_range    = 240.0     # shorter reach than electricspirit (280)
	flee_range      = 50.0

	super._ready()

	# wire frame_changed so we can fire the orb on ORB_RELEASE_FRAME.
	# guarded against double-connection in case it's also wired in the editor.
	if not sprite.frame_changed.is_connected(_on_frame_changed):
		sprite.frame_changed.connect(_on_frame_changed)


# =============================================================================
# SUBCLASS OVERRIDES
# =============================================================================

func get_move_speed() -> float:
	return 85.0


func fire_projectile() -> void:
	# spawn a fire orb at the directional spawn marker, aimed at the
	# player's position at the moment of release.
	var spawn_node: Marker2D = spawn_nodes.get(attack_direction)
	if spawn_node == null or player == null:
		return

	var orb: Node = FIRE_ORB_SCENE.instantiate()
	_parent_to_projectiles_container(orb)
	orb.global_position = spawn_node.global_position

	# aim at the player's current position. orb won't track after firing —
	# if the player dodges between release and impact, the orb misses
	# (intentional gameplay risk, matches arrow and electric orb behavior).
	if orb.has_method("shoot_vector"):
		var to_player: Vector2 = player.global_position - spawn_node.global_position
		orb.shoot_vector(to_player)
	else:
		# fallback for orb implementations that only support cardinals
		orb.shoot(attack_direction)


# =============================================================================
# PROJECTILE PARENTING
# =============================================================================

func _parent_to_projectiles_container(orb: Node) -> void:
	# parent orbs under a "projectiles" group node if one exists in the
	# scene, otherwise under the current scene root. matches the same
	# helper in electricspirit for consistent scene organization.
	var projectiles: Node = get_tree().get_first_node_in_group("projectiles")
	if projectiles == null:
		projectiles = get_tree().current_scene
	projectiles.add_child(orb)


# =============================================================================
# ANIMATION HOOKS
# =============================================================================

func _on_frame_changed() -> void:
	# fire the orb exactly once per attack cycle, on ORB_RELEASE_FRAME.
	# since the attack animation is non-looping (Loop OFF in SpriteFrames)
	# and BaseEnemy._trigger_attack only restarts when the animation NAME
	# changes, this naturally fires once per attack without an extra guard.
	if not sprite.animation.begins_with("attack"):
		return
	if sprite.frame != ORB_RELEASE_FRAME:
		return
	fire_projectile()
