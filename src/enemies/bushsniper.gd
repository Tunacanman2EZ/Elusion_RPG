# bushsniper enemy — ranged archer that fires arrows at the player.
extends BaseEnemy
class_name BushSniper

# This enemy's reward profile — see BaseEnemy.enemy_data.
const ENEMY_DATA := preload("res://data/enemies/bushsniper.tres")


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
	if enemy_data == null:
		enemy_data = ENEMY_DATA

	# Combat tuning only — the reward profile lives in the .tres now.
	attack_cooldown = 2.0
	attack_range    = 200.0

	# THE KITE BAND. Inside 50 the archer backs off; BaseEnemy's flee hysteresis
	# then carries it out to 90 (flee_range * FLEE_RELEASE_FACTOR) before it
	# stops, turns and shoots again. Both numbers sit well inside attack_range,
	# so it is never retreating out of its own reach - it is making room, which
	# is what an archer is for.
	flee_range      = 50.0

	super._ready()

	if not sprite.frame_changed.is_connected(_on_frame_changed):
		sprite.frame_changed.connect(_on_frame_changed)


# =============================================================================
# SUBCLASS OVERRIDES
# =============================================================================

func get_move_speed() -> float:
	return 80.0


func get_flee_speed() -> float:
	# FASTER THAN THE PLAYER (base 90), and this is the whole reason the archer
	# never appeared to run away. It advances at 80, and it was retreating at 80
	# too - so a player simply walking toward it closed ten pixels every second
	# no matter what the archer did. It was fleeing the entire time and losing.
	#
	# Deliberately only a little faster: 105 opens a gap over a couple of
	# seconds rather than instantly, so the player can still corner it by
	# cutting it off rather than by out-running it. Kept under the bush mage's
	# 115 charge speed, so a mage still closes on an archer's position.
	return 105.0


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
