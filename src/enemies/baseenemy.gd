# base class for all enemies — inherited by bushmage, bushsniper,
# electricsprite, firesprite.
#
# behavior model:
# - look up the player on _ready via "player" group lookup
# - every physics frame: update direction to player, decide whether to
#   flee, attack, chase, or return home based on distance + leash
# - attack animations play with is_attacking=true blocking movement until
#   _on_animation_finished clears the flag
# - subclasses override get_move_speed() and fire_projectile()
#
# leash system: enemies remember spawn position and return home if the
# player gets more than leash_range away, preventing map-wide migration.
#
# stacking avoidance: overlapping enemies nudge apart via velocity every
# 3rd frame (staggered per instance id).
#
# loot drops:
# on death, rolls two INDEPENDENT things:
#   1. bag drop (bag_drop_chance) — gold + tier-gated items
#   2. pet drop — three d6, all sixes (1/216) drops this enemy's signature
#      pet (pet_drop_id). a won pet forces a bag to spawn to hold it.
# gold is guaranteed in any bag.
#
# projectile spawning:
# spawn_projectile_node() parents projectiles into the y-sorted "projectiles"
# container so they depth-sort against characters. deferred to avoid the
# "can't change state while flushing queries" physics error.
extends CharacterBody2D
class_name BaseEnemy


# =============================================================================
# CONSTANTS
# =============================================================================

const FLOATING_LABEL_SCENE := preload("res://scene/ui/floatinglabel.tscn")
const LOOTBAG_SCENE := preload("res://scene/interactables/lootbag.tscn")

const STACK_AVOID_DISTANCE := 24.0
const STACK_AVOID_FORCE := 20.0
const HOME_ARRIVAL_THRESHOLD := 4.0

const BAG_ITEM_SLOTS := 8
const LARGE_GOLD_THRESHOLD := 100
const GOLD_SMALL_ID := "smallamountofgold"
const GOLD_LARGE_ID := "largeamountofgold"


# =============================================================================
# EXPORTED SETTINGS
# =============================================================================

@export var max_hp:           int   = 50

@export var attack_cooldown:  float = 2.0
@export var attack_range:     float = 200.0
@export var flee_range:       float = 40.0

@export var leash_range:      float = 400.0

@export var xp_reward:        int = 20
@export var attack_xp_reward: int = 5


# =============================================================================
# EXPORTED SETTINGS — LOOT DROPS
# =============================================================================

@export var bag_drop_chance: float = 0.30
@export var max_loot_tier: int = 1
@export var slot_fill_chance: float = 0.35
@export var pet_drop_id: String = ""


# =============================================================================
# SIGNALS
# =============================================================================

signal damaged(amount: int)
signal died


# =============================================================================
# STATE
# =============================================================================

var hp: int
var player: CharacterBody2D = null
var attack_direction: String = "down"
var attack_ready: bool = true
var is_attacking: bool = false
var current_anim: String = ""
var spawn_position: Vector2 = Vector2.ZERO
var is_returning_home: bool = false


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	hp = max_hp
	add_to_group("enemies")
	spawn_position = global_position

	_resolve_player()
	_wire_attack_timer()
	_wire_healthbar()
	_wire_animated_sprite()

	play_idle_animation("down")


func _physics_process(_delta: float) -> void:
	if player == null:
		_resolve_player()
		return

	if not is_returning_home:
		attack_direction = _get_direction_to_player()

	if is_attacking:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var dist_to_player: float = global_position.distance_to(player.global_position)

	if dist_to_player > leash_range:
		_handle_return_home()
		return

	is_returning_home = false
	_handle_combat(dist_to_player)

	if (Engine.get_physics_frames() + get_instance_id()) % 3 == 0:
		_avoid_stacking_with_others()


# =============================================================================
# INITIALIZATION HELPERS
# =============================================================================

func _resolve_player() -> void:
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]


func _wire_attack_timer() -> void:
	if not has_node("attacktimer"):
		return
	$attacktimer.wait_time = attack_cooldown
	$attacktimer.one_shot  = true
	if not $attacktimer.timeout.is_connected(_on_attack_timer_timeout):
		$attacktimer.timeout.connect(_on_attack_timer_timeout)


func _on_attack_timer_timeout() -> void:
	attack_ready = true


func _wire_healthbar() -> void:
	if not has_node("healthbar"):
		return
	var bar: Range = $healthbar
	bar.min_value = 0
	bar.max_value = max_hp
	bar.step      = 1
	bar.value     = hp


func _wire_animated_sprite() -> void:
	if not has_node("animatedsprite2d"):
		return
	var sprite: AnimatedSprite2D = $animatedsprite2d
	if not sprite.animation_finished.is_connected(_on_animation_finished):
		sprite.animation_finished.connect(_on_animation_finished)


func _on_animation_finished() -> void:
	if not has_node("animatedsprite2d"):
		return
	var sprite: AnimatedSprite2D = $animatedsprite2d
	if sprite.animation.begins_with("attack"):
		is_attacking = false
		play_idle_animation(attack_direction)


# =============================================================================
# COMBAT / MOVEMENT
# =============================================================================

func _handle_combat(dist_to_player: float) -> void:
	if dist_to_player < flee_range:
		var flee_dir: String = _get_direction_from_vec(global_position - player.global_position)
		velocity = _vec_from_dir(flee_dir) * get_move_speed()
		move_and_slide()
		play_walk_animation(flee_dir)
		return

	if dist_to_player < attack_range:
		velocity = Vector2.ZERO
		if attack_ready:
			_trigger_attack()
		else:
			play_idle_animation(attack_direction)
		return

	var to_player: String = _get_direction_from_vec(player.global_position - global_position)
	velocity = _vec_from_dir(to_player) * get_move_speed()
	move_and_slide()
	play_walk_animation(to_player)


func _handle_return_home() -> void:
	var dist_from_spawn: float = global_position.distance_to(spawn_position)

	if dist_from_spawn > HOME_ARRIVAL_THRESHOLD:
		is_returning_home = true
		var return_dir: String = _get_direction_from_vec(spawn_position - global_position)
		velocity = _vec_from_dir(return_dir) * get_move_speed()
		move_and_slide()
		play_walk_animation(return_dir)
	else:
		is_returning_home = false
		velocity = Vector2.ZERO
		play_idle_animation("down")


func _trigger_attack() -> void:
	attack_ready = false
	is_attacking = true
	if has_node("attacktimer"):
		$attacktimer.start()
	play_attack_animation(attack_direction)


func _avoid_stacking_with_others() -> void:
	var others: Array = get_tree().get_nodes_in_group("enemies")
	for other in others:
		if other == self:
			continue
		var d: float = global_position.distance_to(other.global_position)
		if d < STACK_AVOID_DISTANCE and d > 0:
			velocity += (global_position - other.global_position).normalized() * STACK_AVOID_FORCE


# =============================================================================
# SUBCLASS OVERRIDE POINTS
# =============================================================================

func get_move_speed() -> float:
	return 80.0


func fire_projectile() -> void:
	pass


# =============================================================================
# PROJECTILE SPAWNING
# =============================================================================

func spawn_projectile_node(projectile: Node, spawn_pos: Vector2) -> void:
	# parent a projectile into the y-sorted "projectiles" container so it
	# depth-sorts correctly against characters. falls back to the scene root
	# if the container is missing (wrongly-sorted but still functional).
	#
	# add_child + position are BOTH deferred: deferred add avoids the
	# "can't change state while flushing queries" physics error when a
	# projectile spawns during a collision, and deferred position ensures
	# global_position is applied AFTER the node is actually in the tree.
	var container: Node = get_tree().get_first_node_in_group("projectiles")
	if container == null:
		container = get_tree().current_scene
	container.add_child.call_deferred(projectile)
	projectile.set_deferred("global_position", spawn_pos)


# =============================================================================
# ANIMATION HELPERS
# =============================================================================

func _set_animation(new_anim: String) -> void:
	if new_anim == "" or not has_node("animatedsprite2d"):
		return
	if new_anim == current_anim:
		return

	var sprite: AnimatedSprite2D = $animatedsprite2d
	if not sprite.sprite_frames.has_animation(new_anim):
		push_warning("%s: missing animation '%s'" % [name, new_anim])
		return

	current_anim = new_anim
	sprite.play(new_anim)


func play_walk_animation(dir: String) -> void:
	if dir != "":
		_set_animation("walk" + dir)


func play_attack_animation(dir: String) -> void:
	if dir != "":
		_set_animation("attack" + dir)


func play_idle_animation(dir: String) -> void:
	if dir != "":
		_set_animation("idle" + dir)


# =============================================================================
# DIRECTION HELPERS
# =============================================================================

func _get_direction_to_player() -> String:
	if player == null:
		return attack_direction
	return _get_direction_from_vec(player.global_position - global_position)


func _get_direction_from_vec(vec: Vector2) -> String:
	if abs(vec.x) > abs(vec.y):
		return "right" if vec.x > 0 else "left"
	elif abs(vec.y) > 0:
		return "down" if vec.y > 0 else "up"
	return ""


func _vec_from_dir(dir: String) -> Vector2:
	match dir:
		"left":  return Vector2.LEFT
		"right": return Vector2.RIGHT
		"up":    return Vector2.UP
		"down":  return Vector2.DOWN
	return Vector2.ZERO


# =============================================================================
# DAMAGE AND DEATH
# =============================================================================

func take_damage(amount: int, _type: StringName = &"physical") -> void:
	hp = max(hp - amount, 0)
	damaged.emit(amount)

	_spawn_floating_label(amount, 0)

	if has_node("healthbar"):
		var bar: Range = $healthbar
		if bar.max_value != max_hp:
			bar.max_value = max_hp
		bar.value = hp

	if hp <= 0:
		_die()


func _die() -> void:
	var killer: Node = player

	if killer and killer.has_method("gain_xp"):
		killer.gain_xp(xp_reward)
		if killer.has_method("gain_attack_xp"):
			killer.gain_attack_xp(attack_xp_reward)

	_roll_and_spawn_loot(killer)

	died.emit()
	queue_free()


# =============================================================================
# DROPS
# =============================================================================

func _roll_and_spawn_loot(killer: Node) -> void:
	var pet_won: bool = _roll_pet()
	var bag_drops: bool = randf() <= bag_drop_chance

	if not bag_drops and not pet_won:
		return

	var contents: Array = _build_bag_contents()

	if pet_won:
		contents.append({ "item_id": pet_drop_id, "quantity": 1 })

	_spawn_loot_bag(contents, killer, pet_won)


func _roll_pet() -> bool:
	if pet_drop_id == "":
		return false
	if not ItemRegistry.has_item(pet_drop_id):
		return false

	var d1: int = randi_range(1, 6)
	var d2: int = randi_range(1, 6)
	var d3: int = randi_range(1, 6)
	return d1 == 6 and d2 == 6 and d3 == 6


func _build_bag_contents() -> Array:
	var contents: Array = []

	var gold_amount: int = randi_range(max_loot_tier, max_loot_tier * 25)
	var gold_id: String = GOLD_LARGE_ID if gold_amount >= LARGE_GOLD_THRESHOLD else GOLD_SMALL_ID
	if ItemRegistry.has_item(gold_id):
		contents.append({ "item_id": gold_id, "quantity": gold_amount })

	for i in range(BAG_ITEM_SLOTS):
		if randf() <= slot_fill_chance:
			var picked_id: String = _pick_weighted_item_id(max_loot_tier)
			if picked_id != "":
				contents.append({ "item_id": picked_id, "quantity": 1 })

	return contents


func _pick_weighted_item_id(max_tier: int) -> String:
	var candidates: Array = []
	var weights: Array = []
	var total_weight: int = 0

	for item in ItemRegistry.get_all_items():
		if item.tier > max_tier:
			continue
		if item.type == ItemData.Type.PET:
			continue
		if item.type == ItemData.Type.QUEST:
			continue
		if item.type == ItemData.Type.CURRENCY:
			continue

		var w: int = (max_tier - item.tier) + 1
		if w < 1:
			w = 1

		candidates.append(item.item_id)
		weights.append(w)
		total_weight += w

	if candidates.is_empty() or total_weight <= 0:
		return ""

	var roll: int = randi() % total_weight
	var cumulative: int = 0
	for i in range(candidates.size()):
		cumulative += weights[i]
		if roll < cumulative:
			return candidates[i]

	return candidates[candidates.size() - 1]


func _spawn_loot_bag(contents: Array, killer: Node, has_pet: bool) -> void:
	if LOOTBAG_SCENE == null:
		push_warning("BaseEnemy: LOOTBAG_SCENE not loaded — no bag spawned")
		return

	var bag: Node = LOOTBAG_SCENE.instantiate()
	bag.global_position = global_position

	call_deferred("_finish_spawn_loot_bag", bag, contents, killer, has_pet)


func _finish_spawn_loot_bag(bag: Node, contents: Array, killer: Node, has_pet: bool) -> void:
	# parent loot bags into the y-sorted world so they sort with characters.
	# prefer a "lootbags" container, fall back to "projectiles", then scene root.
	var container: Node = get_tree().get_first_node_in_group("lootbags")
	if container == null:
		container = get_tree().get_first_node_in_group("projectiles")
	if container == null:
		container = get_tree().current_scene
	container.add_child(bag)

	if bag.has_method("set_contents"):
		bag.set_contents(contents)
	if bag.has_method("set_owner_player"):
		bag.set_owner_player(killer)
	if bag.has_method("set_has_pet"):
		bag.set_has_pet(has_pet)


# =============================================================================
# UI / VISUAL EFFECTS
# =============================================================================

func _spawn_floating_label(amount: int, type: int) -> void:
	# damage numbers go to the FloatingLabels container (always-on-top,
	# not y-sorted) if it exists, else fall back to the scene root.
	var lbl: Node = FLOATING_LABEL_SCENE.instantiate()
	var container: Node = get_tree().get_first_node_in_group("floatinglabels")
	if container == null:
		container = get_tree().current_scene
	container.add_child(lbl)
	lbl.global_position = global_position + Vector2(0, -30)
	lbl.show_number(amount, type, 0.5)
