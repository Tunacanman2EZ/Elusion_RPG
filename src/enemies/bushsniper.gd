# bushsniper enemy — ranged archer that fires arrows at the player
extends BaseEnemy
class_name BushSniper

const ARROW_SCENE := preload("res://scene/arrow.tscn")
const ARROW_RELEASE_FRAME := 5

@onready var sprite: AnimatedSprite2D = $animatedsprite2d
@onready var spawn_nodes := {
	"left":  $arrowspawnleft,
	"right": $arrowspawnright,
	"up":    $arrowspawntop,
	"down":  $arrowspawnbottom,
}

func _ready() -> void:
	max_hp = 80
	attack_cooldown = 2.0
	attack_range = 200.0
	flee_range = 50.0
	super._ready()
	sprite.frame_changed.connect(_on_frame_changed)

func get_move_speed() -> float:
	return 80.0

func _on_frame_changed() -> void:
	# fires exactly once each time the attack animation reaches frame 5
	if sprite.animation.begins_with("attack") and sprite.frame == ARROW_RELEASE_FRAME:
		fire_projectile()

func fire_projectile() -> void:
	var spawn_node: Marker2D = spawn_nodes.get(attack_direction)
	if spawn_node == null or player == null:
		return
	var arrow := ARROW_SCENE.instantiate()
	get_tree().current_scene.add_child.call_deferred(arrow)
	arrow.global_position = spawn_node.global_position
	# aim at the player's current position at the moment of release
	var to_player: Vector2 = player.global_position - spawn_node.global_position
	arrow.shoot_vector(to_player)
