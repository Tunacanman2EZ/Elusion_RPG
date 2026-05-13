# firesprite enemy — ranged magic caster that fires fire orbs at the player
# slightly tougher than electricspirit but shorter range, faster shots
extends BaseEnemy
class_name FireSprite

const FIRE_ORB_SCENE := preload("res://scene/enemy/fireprojectile.tscn")
const ORB_RELEASE_FRAME := 5  # tune to match your attack animation

@onready var sprite: AnimatedSprite2D = $animatedsprite2d
@onready var spawn_nodes := {
	"left":  $orbspawnleft,
	"right": $orbspawnright,
	"up":    $orbspawntop,
	"down":  $orbspawnbottom,
}

func _ready() -> void:
	max_hp = 70
	attack_cooldown = 2.0
	attack_range = 240.0
	flee_range = 50.0
	super._ready()

	# guard against double connection — editor may have connected this already
	if not sprite.frame_changed.is_connected(_on_frame_changed):
		sprite.frame_changed.connect(_on_frame_changed)

func get_move_speed() -> float:
	return 85.0

func _on_frame_changed() -> void:
	# fire orb at frame 5 of any attack animation, exactly once per cast
	if sprite.animation.begins_with("attack") and sprite.frame == ORB_RELEASE_FRAME:
		fire_projectile()

func fire_projectile() -> void:
	var spawn_node: Marker2D = spawn_nodes.get(attack_direction)
	if spawn_node == null or player == null:
		return

	var orb := FIRE_ORB_SCENE.instantiate()

	# add to dedicated projectiles container if it exists, else current scene
	var projectiles := get_tree().get_first_node_in_group("projectiles")
	if projectiles == null:
		projectiles = get_tree().current_scene
	projectiles.add_child(orb)

	orb.global_position = spawn_node.global_position

	# track the player at the moment of release — like the arrow
	if orb.has_method("shoot_vector"):
		var to_player: Vector2 = player.global_position - spawn_node.global_position
		orb.shoot_vector(to_player)
	else:
		# fallback for orbs that only support cardinal directions
		orb.shoot(attack_direction)
