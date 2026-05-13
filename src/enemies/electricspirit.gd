# electricspirit enemy — ranged magic caster that fires electric orbs
extends BaseEnemy
class_name ElectricSpirit

const ELECTRIC_ORB_SCENE := preload("res://scene/enemy/magicprojectile.tscn")
const ORB_RELEASE_FRAME := 5  # tune to match your attack animation

@onready var sprite: AnimatedSprite2D = $animatedsprite2d
@onready var spawn_nodes := {
	"left":  $orbspawnleft,
	"right": $orbspawnright,
	"up":    $orbspawntop,
	"down":  $orbspawnbottom,
}

func _ready() -> void:
	max_hp = 60
	attack_cooldown = 2.5
	attack_range = 280.0
	flee_range = 50.0
	super._ready()
	sprite.frame_changed.connect(_on_frame_changed)

func get_move_speed() -> float:
	return 90.0

func _on_frame_changed() -> void:
	# fire orb at frame 5 of any attack animation, exactly once per swing
	if sprite.animation.begins_with("attack") and sprite.frame == ORB_RELEASE_FRAME:
		fire_projectile()

func fire_projectile() -> void:
	var spawn_node: Marker2D = spawn_nodes.get(attack_direction)
	if spawn_node == null or player == null:
		return

	var orb := ELECTRIC_ORB_SCENE.instantiate()

	# add to dedicated projectiles container if it exists, else current scene
	var projectiles := get_tree().get_first_node_in_group("projectiles")
	if projectiles == null:
		projectiles = get_tree().current_scene
	projectiles.add_child.call_deferred(orb)

	orb.global_position = spawn_node.global_position

	# track the player at the moment of release — same pattern as arrow
	if orb.has_method("shoot_vector"):
		var to_player: Vector2 = player.global_position - spawn_node.global_position
		orb.shoot_vector(to_player)
	else:
		# fallback for orbs that only support cardinal directions
		orb.shoot(attack_direction)
