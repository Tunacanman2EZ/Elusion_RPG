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
# orbs parent under the "projectiles" group node (the Y-sorted Projectiles
# container inside YSortWorld) so they depth-sort correctly against
# characters. falls back to the current scene root if the group is missing.
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

	# loot tier — 60 hp caster. gates which items can roll (nothing above this
	# tier can drop), scales gold, and sets the pet odds via
	# BaseEnemy.PET_ODDS_BY_TIER (tier 2 = 1 in 648).
	max_loot_tier   = 2

	# NEW: pet_drop_id defaults to "" on every enemy (never set per-instance
	# in the editor), which meant _roll_pet() always bailed out immediately
	# before even rolling the dice — the entire triple-six pet-drop system
	# was completely non-functional, not just rare. guarded so an explicit
	# Inspector override still wins if one's ever set later.
	if pet_drop_id == "":
		pet_drop_id = "petelectricsprite"

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
	# parents the orb under the "projectiles" group (the Y-sorted Projectiles
	# container) so it depth-sorts against characters. uses call_deferred so
	# we don't mutate the scene tree mid-physics-frame.
	var spawn_node: Marker2D = spawn_nodes.get(attack_direction)
	if spawn_node == null or player == null:
		return

	var orb: Node = ELECTRIC_ORB_SCENE.instantiate()
	_parent_to_projectiles_container(orb)

	# defer the position set too — the orb isn't in the tree until the
	# deferred add_child runs, so set global_position deferred to match.
	orb.set_deferred("global_position", spawn_node.global_position)

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
	# parent orbs under the "projectiles" group node (Y-sorted Projectiles
	# container inside YSortWorld). falls back to the current scene root if
	# the group node is missing. call_deferred defers the add_child until
	# the physics step ends, avoiding mid-frame scene-tree mutation errors.
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
