# bushmage enemy — melee attacker that uses directional vine attack boxes
# chases the player and holds at roughly 1 tile away, then attacks
extends BaseEnemy
class_name BushMage

@export var attack_power: int = 8
@export var desired_distance: float = 32.0  # 1 tile — adjust to your tile size
@export var distance_tolerance: float = 4.0  # dead zone to prevent jitter
@export var contact_frame: int = 3  # frame of attack anim where damage is dealt

@onready var sprite: AnimatedSprite2D = $animatedsprite2d

func _ready() -> void:
	max_hp = 80
	attack_cooldown = 1.2
	attack_range = desired_distance + 8.0  # attack range slightly larger than hold distance
	# flee_range left at default but bushmage ignores it — see _physics_process
	super._ready()
	sprite.frame_changed.connect(_on_frame_changed)

func get_move_speed() -> float:
	return 75.0

func _physics_process(_delta: float) -> void:
	# we override BaseEnemy's _physics_process entirely because bushmage
	# uses chase-and-hold behavior instead of the default flee/attack/idle.
	if player == null:
		var players := get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			player = players[0]
		return

	var dist := global_position.distance_to(player.global_position)
	attack_direction = _get_direction_to_player()

	if dist > desired_distance + distance_tolerance:
		# too far — chase the player
		var chase_dir := _get_direction_from_vec(player.global_position - global_position)
		velocity = _vec_from_dir(chase_dir) * get_move_speed()
		move_and_slide()
		play_walk_animation(chase_dir)

	elif dist < desired_distance - distance_tolerance:
		# too close — back off
		var back_dir := _get_direction_from_vec(global_position - player.global_position)
		velocity = _vec_from_dir(back_dir) * get_move_speed()
		move_and_slide()
		play_walk_animation(back_dir)

	else:
		# in the sweet spot — stop and attack
		velocity = Vector2.ZERO
		play_attack_animation(attack_direction)
		if attack_ready:
			_trigger_attack()

	# inherited stacking avoidance, staggered by instance id
	if (Engine.get_physics_frames() + get_instance_id()) % 3 == 0:
		_avoid_stacking_with_others()

func _on_frame_changed() -> void:
	# deal damage exactly at the contact frame of the attack animation
	if sprite.animation.begins_with("attack") and sprite.frame == contact_frame:
		_deal_melee_damage()

func _deal_melee_damage() -> void:
	# checks the directional attack box for overlapping bodies and damages the player
	var box_name := "attackbox" + attack_direction
	if not has_node(box_name):
		return
	var box := get_node(box_name)
	if not box is Area2D:
		return
	for body in box.get_overlapping_bodies():
		if body.is_in_group("player") and body.has_method("take_damage"):
			body.take_damage(attack_power)

# fire_projectile is the BaseEnemy hook name — bushmage doesn't use it,
# but we keep an empty override for documentation. damage flows through
# _on_frame_changed -> _deal_melee_damage instead.
func fire_projectile() -> void:
	pass
