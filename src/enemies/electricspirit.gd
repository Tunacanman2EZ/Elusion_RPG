# electricspirit enemy — ranged magic caster that fires electric orbs.
# uses BaseEnemy's default flee/attack/chase pattern, similar to bushsniper
# but with magic projectiles and slightly longer attack range.
#
# attack flow:
# 1. BaseEnemy._physics_process puts spirit in attack range
# 2. _trigger_attack plays directional attack animation
# 3. animation reaches ORB_RELEASE_FRAME (frame 5)
# 4. fire_projectile spawns an orb at the directional spawn marker
# 5. orb aims at the player's CURRENT position (lead-tracking shot)
# 6. orb travels in a straight line until hit, wall, or lifetime expiry
#
# projectile container:
# if a "projectiles" group node exists, orbs parent under it for tidier
# scene organization. otherwise they parent to the current scene root.
# bushsniper does the same — keep both consistent.
extends BaseEnemy
class_name ElectricSpirit


# =============================================================================
# CONSTANTS
# =============================================================================

# preloaded orb scene — instantiated on each shot
const ELECTRIC_ORB_SCENE := preload("res://scene/projectiles/magicprojectile.tscn")

# frame of the attack animation where the orb is released.
# tune to match the visual peak of the cast (hand thrust forward, glow
# release). adjust if you retime the attack animation.
const ORB_RELEASE_FRAME := 5


# =============================================================================
# NODE REFERENCES
# =============================================================================

@onready var sprite: AnimatedSprite2D = $animatedsprite2d

# spawn markers per direction — orbs emerge from the correct side of the
# spirit's sprite based on facing direction.
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
	max_hp          = 60
	attack_cooldown = 2.5
	attack_range    = 280.0      # longer reach than bushsniper
	flee_range      = 50.0

	super._ready()

	# wire frame_changed so we can fire the orb on ORB_RELEASE_FRAME
	sprite.frame_changed.connect(_on_frame_changed)


# =============================================================================
# SUBCLASS OVERRIDES
# =============================================================================

func get_move_speed() -> float:
	return 90.0


func fire_projectile() -> void:
	# spawn an orb at the directional spawn marker, aimed at the player's
	# position at the moment of release.
	#
	# tries to parent the orb under a "projectiles" group node for tidier
	# scene organization — if no such node exists, falls back to the
	# current scene root.
	#
	# uses call_deferred so we don't mutate the scene tree mid-physics
	# frame (Godot warns otherwise during certain collision callbacks).
	var spawn_node: Marker2D = spawn_nodes.get(attack_direction)
	if spawn_node == null or player == null:
		return

	var orb: Node = ELECTRIC_ORB_SCENE.instantiate()
	_parent_to_projectiles_container(orb)
	orb.global_position = spawn_node.global_position

	# aim at the player's current position. orb won't track after firing —
	# if the player dodges between release and impact, the orb misses
	# (intentional gameplay risk, matches arrow behavior).
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
	# scene, otherwise under the current scene root. either way uses
	# call_deferred to defer the add_child until the physics step ends.
	var projectiles: Node = get_tree().get_first_node_in_group("projectiles")
	if projectiles == null:
		projectiles = get_tree().current_scene
	projectiles.add_child.call_deferred(orb)


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
