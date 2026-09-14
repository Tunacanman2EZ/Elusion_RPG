# firesprite enemy — ranged magic caster that fires fire orbs at the player.
extends BaseEnemy
class_name FireSprite

# This enemy's reward profile — see BaseEnemy.enemy_data.
const ENEMY_DATA := preload("res://data/enemies/firesprite.tres")


# =============================================================================
# CONSTANTS
# =============================================================================

const FIRE_ORB_SCENE := preload("res://scene/projectiles/fireprojectile.tscn")
const ORB_RELEASE_FRAME := 5


# =============================================================================
# NODE REFERENCES
# =============================================================================

@onready var sprite: AnimatedSprite2D = $animatedsprite2d
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
	if enemy_data == null:
		enemy_data = ENEMY_DATA

	# Combat tuning only — the reward profile lives in the .tres now.
	attack_cooldown = 2.0
	attack_range    = 240.0
	flee_range      = 50.0

	super._ready()

	if not sprite.frame_changed.is_connected(_on_frame_changed):
		sprite.frame_changed.connect(_on_frame_changed)


# =============================================================================
# SUBCLASS OVERRIDES
# =============================================================================

func get_move_speed() -> float:
	return 85.0


func fire_projectile() -> void:
	# spawn a fire orb at the directional spawn marker, aimed at the player's
	# position at release. parents into the y-sorted projectiles container.
	var spawn_node: Marker2D = spawn_nodes.get(attack_direction)
	if spawn_node == null or player == null:
		return
	var orb: Node = FIRE_ORB_SCENE.instantiate()
	# aim before spawning
	if orb.has_method("shoot_vector"):
		var to_player: Vector2 = player.global_position - spawn_node.global_position
		orb.shoot_vector(to_player)
	elif orb.has_method("shoot"):
		orb.shoot(attack_direction)
	spawn_projectile_node(orb, spawn_node.global_position)


# =============================================================================
# ANIMATION HOOKS
# =============================================================================

func _on_frame_changed() -> void:
	if not sprite.animation.begins_with("attack"):
		return
	if sprite.frame != ORB_RELEASE_FRAME:
		return
	fire_projectile()
