# skeleton.gd - the crypt's skeleton: it walks at you and swings its sword
# (0.60.0).
#
# THE OWNER, 19 Oct: "lets add skeletons" - Ahvassa's sheet - in "the 5 elite
# alcoves", fighting by "chase and sword swing". The first monster in the game
# that fights up close apart from the boss, so it swings the boss's way
# (bossenemy.gd, _land_swing()): the blow is checked ON THE FRAME THE BLADE
# LANDS, against wherever the player is then, so stepping out of reach during
# the wind-up works. A skeleton that has started swinging at you is a warning,
# not a hit.
#
# THE SHEET (art/enemy/skeleton.png, Ahvassa): 64 px frames, four direction
# groups top to bottom - facing right, left, down, up - each an idle of 8, a
# walk of 6, an attack of 8 and a blank row. Which side is which is read off
# the skull: its eyes are on the side it faces, and the first group's are on
# the right. Every direction runs at the same speed (an animation that
# changes rate as the body turns is a bug the art pipeline has caught before).
# There are no death and no hitflash rows: a skeleton breaks up the way every
# monster without a death of its own does (deathburst.gd), and flashes the
# artist's white over its own frame like every other (hitflash.gd).
#
# FIVE OF THEM, ONE PER ALCOVE. scene/enemy/skeleton.tscn is the body; each of
# skeletonguard, -warden, -knight, -champion and -lord.tscn is it with its
# band's profile (data/enemies/), the way the element variants are built - a
# respawn rebuilds a monster from its scene file, so the profile has to live
# there, not on the placed instance.
extends BaseEnemy


# The first band's, for a skeleton placed without a variant scene.
const ENEMY_DATA := preload("res://data/enemies/skeletonguard.tres")

# The frame the blade lands on, 0-based: the wide arc of the attack row. At
# ATTACK_FPS that is 0.6 s after the swing starts - the time a player has to
# step out of reach.
const SWING_FRAME := 6
const ATTACK_FPS := 10.0

# Collision layer 3, the players' - the bit value, as bossenemy.gd has it.
const PLAYER_PHYSICS_LAYER := 4

# How far the swing reaches, from the skeleton's feet. Inside it the skeleton
# stops and swings; the inner ring of the formation (24 px) is inside it.
@export var melee_range: float = 36.0

# HOW FAR IN IT STANDS TO FIGHT: this much inside its reach, from the player's
# BODY. A formation slot is 24 px out on the inner ring but 44 and 64 on the
# outer two (formation.gd), past a sword - a skeleton handed one of those while
# a pack held the inner ring would stand there and never swing. So it keeps its
# slot's bearing and comes in to fighting_distance().
#
# FROM THE BODY, NOT THE ORIGIN, which is somewhere else for every class
# (Targets.body_point()): the tank's body is 8 to 46 px above its origin, so a
# skeleton 28 px south of the origin swung 36 px at a body 36 px away and
# missed, every time (the suite found it). Both where it stands and whether it
# is in reach are measured to the body.
const STAND_IN_MARGIN := 8.0

var _swing_landed: bool = false

@onready var sprite: AnimatedSprite2D = $animatedsprite2d


func _ready() -> void:
	if enemy_data == null:
		enemy_data = ENEMY_DATA

	# Combat tuning; the profile is in the .tres.
	attack_cooldown = 1.8
	attack_range = melee_range
	# It never backs off: there is nothing to keep its distance for.
	flee_range = 0.0

	super._ready()

	if not sprite.frame_changed.is_connected(_on_frame_changed):
		sprite.frame_changed.connect(_on_frame_changed)


func get_move_speed() -> float:
	return 90.0


func fighting_distance() -> float:
	"""How far from a player it stands to swing: inside its reach."""
	return maxf(melee_range - STAND_IN_MARGIN, 0.0)


func _get_slot_target_position() -> Vector2:
	# Its slot round the player, brought in to fighting_distance() of the
	# body when the slot is further out than that. A slot inside it is left
	# as it is.
	var slot: Vector2 = super._get_slot_target_position()
	if not is_instance_valid(player):
		return slot
	var body: Vector2 = target_point()
	var out: Vector2 = slot - body
	var reach: float = fighting_distance()
	if out.length() <= reach:
		return slot
	return clamp_to_navigation(body + out.normalized() * reach)


func _handle_combat(_dist_to_player: float) -> void:
	# In reach is measured to the body, like where it stands (STAND_IN_MARGIN).
	super._handle_combat(global_position.distance_to(target_point()))


func swing_damage() -> int:
	"""What one blow deals: the profile's own number."""
	if enemy_data != null and enemy_data.projectile_damage > 0:
		return enemy_data.projectile_damage
	return 10


func _trigger_attack() -> void:
	_swing_landed = false
	super._trigger_attack()


func _on_frame_changed() -> void:
	# A MIRROR'S SWING IS A PICTURE. The blow is the leader's, and arrives from
	# monstersync.gd as "m", which runs _land_swing() here against this game's
	# own player.
	if net_mirror:
		return
	if not sprite.animation.begins_with("attack"):
		_swing_landed = false
		return
	if _swing_landed or sprite.frame != SWING_FRAME:
		return
	_swing_landed = true
	_land_swing()


func _land_swing() -> void:
	"""The blow: every player in reach, once each, now."""
	for target in players_in_reach():
		target.take_damage(swing_damage(), current_element())

	# SHARED MONSTERS: the blow lands on every screen. Each other game runs the
	# same query round its copy, against its own player.
	if _net_sync != null and not net_mirror:
		_net_sync.leader_event(self, {"k": "m"})


func players_in_reach() -> Array:
	"""Every player the blade reaches from where it stands now, once each: a
	player's body, or its hurtbox, within melee_range of the feet - the boss's
	query (bossenemy.gd _land_swing()).

	ONLY THE HURTBOX AMONG A PLAYER'S AREAS. The tank's aura is an Area2D on
	the players' layer too, 150 px across, and it is there whether the ring is
	lit or not; counted as the tank, it let a sword hit a tank from 100 px off
	to its side."""
	var shape := CircleShape2D.new()
	shape.radius = melee_range
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, global_position)
	query.collision_mask = PLAYER_PHYSICS_LAYER
	query.collide_with_bodies = true
	query.collide_with_areas = true
	var ignore_self: Array[RID] = [get_rid()]
	query.exclude = ignore_self

	var found: Array = []
	var already: Array[int] = []
	for hit in get_world_2d().direct_space_state.intersect_shape(query, 16):
		var node: Object = hit.get("collider")
		if node == null or not is_instance_valid(node):
			continue
		var target: Node = node as Node
		if node is Area2D:
			if (node as Area2D).name != &"hurtbox":
				continue
			target = (node as Area2D).get_parent()
		if target == null or not target.is_in_group(&"player") or not target.has_method(&"take_damage"):
			continue
		var id: int = target.get_instance_id()
		if id in already:
			continue
		already.append(id)
		found.append(target)
	return found
