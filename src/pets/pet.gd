# pet.gd — a companion entity. a shrunk, ally-flipped version of an enemy:
# instead of hunting the player, it FOLLOWS the player and attacks the nearest
# ENEMY within aggro range.
#
# supports two attack archetypes so different pets play differently:
#   PROJECTILE — fires projectile_scene at range, traveling toward the target
#   VINE       — spawns projectile_scene AT THE TARGET's position, no travel
#
# design: composition, NOT inheritance from BaseEnemy. every combat value is
# an export so each pet variant tunes individually.
#
# attack animation lock: while _is_attacking is true, _update_follow skips
# walk/idle animation changes so movement doesn't stomp the attack visual.
#
# render order:
# - projectile attacks parent under the "projectiles" group (Y-sorted
#   Projectiles container) so they depth-sort with characters.
# - vine attacks parent under the "groundeffects" group (Y-sorted
#   GroundEffects container) so they root at the target's feet, under bodies.
#
# DEFERRED SPAWN TIMING (IMPORTANT):
# _parent_to_group() deliberately uses add_child.call_deferred() rather than
# add_child() directly, to avoid mutating the tree mid-physics-frame. that
# means the spawned node's _ready() — and therefore any @onready vars on it,
# like a sprite reference — does NOT run until later in the same frame's
# deferred-call flush. calling a method like fire()/shoot_vector() on that
# node SYNCHRONOUSLY right after spawning it will hit those @onready vars
# before they're assigned (still null), crashing with "Invalid access to
# property or key '...' on a base object of type 'Nil'". both _fire_vine()
# and _fire_projectile() defer their trigger call for exactly this reason —
# deferred calls run in the order they were queued, so the deferred add_child
# (which triggers _ready()) always completes before the deferred fire/shoot
# call runs, even though both were queued within the same physics frame.
extends CharacterBody2D
class_name Pet


# =============================================================================
# ATTACK TYPE
# =============================================================================

enum AttackType { PROJECTILE, VINE }


# =============================================================================
# EXPORTED SETTINGS — PER-PET TUNING
# =============================================================================

@export var attack_type: AttackType = AttackType.PROJECTILE
@export var projectile_scene: PackedScene = null
@export var projectile_damage: int = 5
@export var aggro_range: float = 250.0
@export var attack_cooldown: float = 2.0
@export var move_speed: float = 100.0
@export var follow_distance: float = 60.0
@export var teleport_distance: float = 600.0
@export var scale_factor: float = 0.5


# =============================================================================
# STATE
# =============================================================================

var player: Node = null
var _attack_ready: bool = true
var _current_target: Node = null
var _is_attacking: bool = false


# =============================================================================
# NODE REFERENCES
# =============================================================================

@onready var attack_timer: Timer = _make_attack_timer()


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	add_to_group("pets")
	scale = Vector2(scale_factor, scale_factor)
	_resolve_player()

	if has_node("animatedsprite2d"):
		var sprite: AnimatedSprite2D = $animatedsprite2d
		if sprite.sprite_frames != null and sprite.sprite_frames.has_animation("idledown"):
			sprite.play("idledown")
		if not sprite.animation_finished.is_connected(_on_sprite_animation_finished):
			sprite.animation_finished.connect(_on_sprite_animation_finished)


func _make_attack_timer() -> Timer:
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = attack_cooldown
	add_child(t)
	t.timeout.connect(func(): _attack_ready = true)
	return t


func _physics_process(_delta: float) -> void:
	if player == null:
		_resolve_player()
		return

	_update_follow()

	_current_target = _find_nearest_enemy()

	if _current_target != null and _attack_ready:
		_fire_at(_current_target)


# =============================================================================
# PLAYER RESOLUTION
# =============================================================================

func _resolve_player() -> void:
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]


# =============================================================================
# FOLLOW MOVEMENT
# =============================================================================

func _update_follow() -> void:
	var to_player: Vector2 = player.global_position - global_position
	var dist: float = to_player.length()

	if dist > teleport_distance:
		global_position = player.global_position - to_player.normalized() * follow_distance
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if dist > follow_distance:
		velocity = to_player.normalized() * move_speed
		if not _is_attacking:
			_play_walk(to_player)
	else:
		velocity = Vector2.ZERO
		if not _is_attacking:
			_play_idle()

	move_and_slide()


# =============================================================================
# TARGETING
# =============================================================================

func _find_nearest_enemy() -> Node:
	var nearest: Node = null
	var nearest_dist: float = aggro_range

	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		var d: float = global_position.distance_to(enemy.global_position)
		if d <= nearest_dist:
			nearest = enemy
			nearest_dist = d

	return nearest


# =============================================================================
# ATTACK
# =============================================================================

func _fire_at(target: Node) -> void:
	if projectile_scene == null:
		push_warning("Pet: projectile_scene not assigned")
		return

	var dir: Vector2 = (target.global_position - global_position).normalized()

	match attack_type:
		AttackType.PROJECTILE:
			_fire_projectile(dir)
		AttackType.VINE:
			_fire_vine(target, dir)

	_is_attacking = true
	_play_attack(dir)

	_attack_ready = false
	attack_timer.wait_time = attack_cooldown
	attack_timer.start()

	# release the attack animation lock after a short fixed window instead of
	# relying on animation_finished (which never fires if the attack anim loops).
	_release_attack_lock_after(0.4)


func _release_attack_lock_after(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	_is_attacking = false


func _fire_projectile(dir: Vector2) -> void:
	# flying projectile → parent to the "projectiles" group (Y-sorted),
	# spawn at a small muzzle offset in front of the pet toward the target
	# so the orb has clear space to render + travel even at point-blank,
	# then aim.
	var projectile: Node = projectile_scene.instantiate()
	_parent_to_group(projectile, "projectiles")

	# muzzle offset — tune MUZZLE_OFFSET to taste after testing
	var muzzle_offset: float = 24.0
	var spawn_pos: Vector2 = global_position + dir * muzzle_offset
	projectile.set_deferred("global_position", spawn_pos)

	if "damage" in projectile:
		projectile.damage = projectile_damage

	# NEW: deferred for the same reason as _fire_vine's fire() call below —
	# see the DEFERRED SPAWN TIMING note at the top of this file. this
	# wasn't crashing visibly (unlike petvine.gd's fire()), but it's the
	# identical latent timing bug: if any projectile's shoot_vector() ever
	# touches an @onready sprite reference, it'll hit the same null crash
	# the moment that code path changes. deferring here costs nothing and
	# closes the gap for all projectile types at once, not just the ones
	# lucky enough not to have tripped it yet.
	if projectile.has_method("shoot_vector"):
		projectile.call_deferred("shoot_vector", dir)


func _fire_vine(target: Node, dir: Vector2) -> void:
	# ground-rooted vine → parent to the "groundeffects" group (Y-sorted),
	# spawn AT THE TARGET's position so it roots at their feet.
	var vine: Node = projectile_scene.instantiate()
	_parent_to_group(vine, "groundeffects")
	vine.set_deferred("global_position", target.global_position)
	if "damage" in vine:
		vine.damage = projectile_damage

	# NEW: fire() must be deferred — _parent_to_group's add_child is itself
	# deferred, so vine._ready() (and its @onready sprite assignment) hasn't
	# run yet at this point in the same physics frame. calling fire()
	# synchronously here is exactly what produced "Invalid access to
	# property or key 'sprite_frames' on a base object of type 'Nil'" —
	# petvine.gd's fire() touches sprite.sprite_frames immediately, and
	# sprite was still unassigned. deferring queues fire() to run right
	# after the deferred add_child completes _ready(), in the same
	# end-of-frame flush, in queue order — so sprite is guaranteed set.
	if vine.has_method("fire"):
		vine.call_deferred("fire", _dir_to_cardinal(dir))


func _parent_to_group(node: Node, group_name: String) -> void:
	# parent under the named group container (a Y-sorted node inside
	# YSortWorld) if one exists, matching how enemy attacks parent so
	# depth-sorting stays consistent. falls back to the scene root.
	# uses call_deferred so we don't mutate the tree mid-physics-frame.
	var container: Node = get_tree().get_first_node_in_group(group_name)
	if container == null:
		container = get_tree().current_scene
	container.add_child.call_deferred(node)


func _dir_to_cardinal(dir: Vector2) -> String:
	if abs(dir.x) > abs(dir.y):
		return "right" if dir.x > 0 else "left"
	return "down" if dir.y > 0 else "up"


# =============================================================================
# ANIMATION HELPERS
# =============================================================================

func _play_walk(dir: Vector2) -> void:
	_play_directional("walk", dir)


func _play_attack(dir: Vector2) -> void:
	_play_directional("attack", dir)


func _play_idle() -> void:
	if has_node("animatedsprite2d"):
		var sprite: AnimatedSprite2D = $animatedsprite2d
		if sprite.sprite_frames != null and sprite.sprite_frames.has_animation("idledown"):
			if sprite.animation != "idledown":
				sprite.play("idledown")


func _play_directional(prefix: String, dir: Vector2) -> void:
	if not has_node("animatedsprite2d"):
		return
	var sprite: AnimatedSprite2D = $animatedsprite2d
	if sprite.sprite_frames == null:
		return
	var suffix: String
	if abs(dir.x) > abs(dir.y):
		suffix = "right" if dir.x > 0 else "left"
	else:
		suffix = "down" if dir.y > 0 else "up"
	var anim := prefix + suffix
	if sprite.sprite_frames.has_animation(anim) and sprite.animation != anim:
		sprite.play(anim)


# =============================================================================
# ATTACK ANIMATION LOCK
# =============================================================================

func _on_sprite_animation_finished() -> void:
	if not has_node("animatedsprite2d"):
		return
	var sprite: AnimatedSprite2D = $animatedsprite2d
	if sprite.animation.begins_with("attack"):
		_is_attacking = false
