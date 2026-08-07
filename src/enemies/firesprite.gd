# firesprite enemy — ranged magic caster that fires fire orbs at the player.
extends BaseEnemy
class_name FireSprite


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
	max_hp          = 70
	attack_cooldown = 2.0
	attack_range    = 240.0
	flee_range      = 50.0

	# NEW: pet_drop_id defaults to "" on every enemy (never set per-instance
	# in the editor), which meant _roll_pet() always bailed out immediately
	# before even rolling the dice — the entire triple-six pet-drop system
	# was completely non-functional, not just rare. guarded so an explicit
	# Inspector override still wins if one's ever set later.
	if pet_drop_id == "":
		pet_drop_id = "petfiresprite"

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
