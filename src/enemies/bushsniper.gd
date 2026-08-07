# bushsniper enemy — ranged archer that fires arrows at the player.
extends BaseEnemy
class_name BushSniper


# =============================================================================
# CONSTANTS
# =============================================================================

const ARROW_SCENE := preload("res://scene/projectiles/arrow.tscn")
const ARROW_RELEASE_FRAME := 5


# =============================================================================
# NODE REFERENCES
# =============================================================================

@onready var sprite: AnimatedSprite2D = $animatedsprite2d
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
	max_hp          = 80
	attack_cooldown = 2.0
	attack_range    = 200.0
	flee_range      = 50.0

	# NEW: pet_drop_id defaults to "" on every enemy (never set per-instance
	# in the editor), which meant _roll_pet() always bailed out immediately
	# before even rolling the dice — the entire triple-six pet-drop system
	# was completely non-functional, not just rare. guarded so an explicit
	# Inspector override still wins if one's ever set later.
	if pet_drop_id == "":
		pet_drop_id = "petsniper"

	super._ready()

	if not sprite.frame_changed.is_connected(_on_frame_changed):
		sprite.frame_changed.connect(_on_frame_changed)


# =============================================================================
# SUBCLASS OVERRIDES
# =============================================================================

func get_move_speed() -> float:
	return 80.0


func fire_projectile() -> void:
	# spawn an arrow at the directional spawn marker, aimed at the player's
	# position at the moment of release. parents into the y-sorted projectiles
	# container via the inherited helper so the arrow depth-sorts correctly.
	var spawn_node: Marker2D = spawn_nodes.get(attack_direction)
	if spawn_node == null or player == null:
		return
	var arrow: Node = ARROW_SCENE.instantiate()
	# aim BEFORE spawning — shoot_vector just sets velocity + rotation, which
	# don't require the node to be in the tree yet.
	var to_player: Vector2 = player.global_position - spawn_node.global_position
	arrow.shoot_vector(to_player)
	# parent into the y-sorted projectiles container at the marker position.
	spawn_projectile_node(arrow, spawn_node.global_position)


# =============================================================================
# ANIMATION HOOKS
# =============================================================================

func _on_frame_changed() -> void:
	if not sprite.animation.begins_with("attack"):
		return
	if sprite.frame != ARROW_RELEASE_FRAME:
		return
	fire_projectile()
