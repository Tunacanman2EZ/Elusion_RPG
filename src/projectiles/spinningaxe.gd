# spinningaxe.gd - the warrior's attack while the Double Axe is equipped.
#
# The owner's design, day 2: "we can right click on a spot it will spin until
# right clicked again then it will come back". So the axe has three states:
#
#   OUT        thrown from the warrior to the spot aimed at, cutting every
#              enemy it passes on the way, once each
#   SPINNING   turning in place, cutting everything within HIT_RADIUS every
#              TICK_SECONDS - faster the longer it is left (SPIN UP, below) -
#              for as long as the warrior leaves it there
#   RETURNING  attack again and it flies back to the warrior's hand, cutting
#              everything it passes on the way home, once each
#
# Attack is Space or right-click for every class, so either one throws and
# either one calls it back - warrior.gd's attack_action() decides which.
#
# IT COMES HOME ON ITS OWN in three cases, because each is a way to leave it
# working with nobody playing:
#   - the warrior walks more than LEASH away from it;
#   - the warrior is away from the keyboard (Player.is_afk(), the same three
#     minutes that stop skill XP - an axe left grinding a spawn point is the
#     pet-in-a-corner problem from player.gd's AFK note, and gets the same
#     answer);
#   - the warrior dies, leaves the area or takes the axe off, in which case it
#     is simply gone - there is no hand to return to.
#
# DAMAGE. A pass (out or back) hits for one sword swing, warrior.gd's
# _calculate_melee_damage(), which already has the axe's own damage in it. A
# spin tick hits for the share of a swing its tick is of a swing's time, so a
# spinning axe deals a swinging warrior's damage per second to everything near
# it - the area is the upgrade, not a bigger number. Left spinning, it speeds
# up to SPIN_MAX_RATE times that.
#
# SPIN UP (0.11.9). The owner: "double axe needs to speed up when left
# deployed". From the moment it starts spinning its rate climbs evenly from 1x
# to SPIN_MAX_RATE over SPIN_RAMP_SECONDS and stays there. The ticks come
# faster - each still a tick's share of a swing, so the damage a second climbs
# with the rate - and the picture spins faster with them. Every throw starts at
# 1x again, so the reward is for leaving it where it is. The server's books
# allow for the top rate: the exporter writes SPIN_MAX_RATE into gamedata.json
# as the warrior's axe_spin_max_rate, and gamedata.combat_bounds() reads it.
#
# THE TIMELINE IS ADVANCED BY advance(), which _physics_process calls with the
# frame's delta; a test calls it directly.
class_name SpinningAxe
extends Area2D


enum State { OUT, SPINNING, RETURNING }

const FLY_SPEED := 260.0
const RETURN_SPEED := 320.0

# The furthest it can be thrown. A spot further than this is taken as the
# direction to throw in, and the axe stops here.
const MAX_THROW := 170.0

# Walk further than this from a spinning axe and it comes home.
const LEASH := 260.0

# How close it has to come back before the warrior has caught it.
const CATCH_DISTANCE := 10.0

# What stops a throw: physics layers 1 and 2, where the areas keep their walls
# (the field's are on layer 1, the town's on 2). The axe flies over enemies -
# it cuts them on the way - and stops only at something solid.
const WALL_LAYERS := 0b11

const TICK_SECONDS := 0.25

# SPIN UP: the most the rate climbs to, and how long it takes to get there.
const SPIN_MAX_RATE := 2.0
const SPIN_RAMP_SECONDS := 4.0

# MATCHED to the CollisionShape2D in spinningaxe.tscn.
const HIT_RADIUS := 20.0

# The axe flies at about waist height: its picture is drawn this far above the
# node, and the node - with its shadow - is on the ground. That is what lets it
# sort in front of and behind enemies by where it really is.
const HEIGHT := 7.0

var caster: Node2D = null
var target: Vector2 = Vector2.ZERO
var state: State = State.OUT

# Enemies already cut on this pass, by instance id - see slashwave.gd's
# _hit_targets for why ids and not nodes. Cleared when a pass begins.
var _passed: Dictionary = {}
var _tick: float = 0.0
# Seconds spent spinning since this throw landed; spin_rate() reads it.
var _spun: float = 0.0
var hits_dealt: int = 0

@onready var spin: AnimatedSprite2D = $spin
@onready var shadow: Sprite2D = $shadow


func _ready() -> void:
	spin.position = Vector2(0, -HEIGHT)
	spin.play("spin")
	shadow.texture = Blast.shadow_texture(6, 3)
	shadow.modulate.a = 0.7


func _physics_process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	# `== true` rather than bool(): get() is null on a caster with no such
	# member, and bool(null) is an error, not a false.
	if caster == null or not is_instance_valid(caster) or caster.get("is_dying") == true:
		queue_free()
		return

	match state:
		State.OUT:
			var stopped_short: bool = _fly_out(FLY_SPEED * delta)
			_cut_what_it_passes()
			if stopped_short or global_position.distance_to(target) < 0.5:
				state = State.SPINNING
				_tick = 0.0
				_spun = 0.0
		State.SPINNING:
			# The rate for this step is the rate it had at the start of it,
			# so the first tick still lands TICK_SECONDS after it stops.
			var rate: float = spin_rate()
			_spun += delta
			_tick += delta * rate
			if spin != null:
				spin.speed_scale = rate
			while _tick >= TICK_SECONDS:
				_tick -= TICK_SECONDS
				_cut_everything_near()
			if global_position.distance_to(caster.global_position) > LEASH \
					or (caster.has_method("is_afk") and caster.is_afk()):
				recall()
		State.RETURNING:
			_fly_toward(caster.global_position, RETURN_SPEED * delta)
			_cut_what_it_passes()
			if global_position.distance_to(caster.global_position) <= CATCH_DISTANCE:
				if caster.has_method("_on_axe_caught"):
					caster._on_axe_caught()
				queue_free()


func recall() -> void:
	# Attack pressed again, or one of the reasons at the top. A second press
	# while it is already on its way back changes nothing.
	if state == State.RETURNING:
		return
	state = State.RETURNING
	_passed.clear()
	if spin != null:
		spin.speed_scale = 1.0


func spin_rate() -> float:
	"""How fast it is spinning: 1 when it lands, climbing evenly to
	SPIN_MAX_RATE over SPIN_RAMP_SECONDS, then holding there."""
	if SPIN_RAMP_SECONDS <= 0.0:
		return SPIN_MAX_RATE
	return 1.0 + (SPIN_MAX_RATE - 1.0) * clampf(_spun / SPIN_RAMP_SECONDS, 0.0, 1.0)


func throw_to(from: Vector2, aimed_at: Vector2) -> void:
	# Called once, by the warrior, after the axe is in the tree.
	global_position = from
	reset_physics_interpolation()
	var reach: Vector2 = aimed_at - from
	if reach.length() > MAX_THROW:
		reach = reach.normalized() * MAX_THROW
	target = from + reach
	state = State.OUT
	_passed.clear()
	_spun = 0.0


func _fly_toward(where: Vector2, step: float) -> void:
	global_position = global_position.move_toward(where, step)


func _fly_out(step: float) -> bool:
	# One frame of the throw. Returns true when a wall stopped it, in which
	# case it is left just short of the wall to spin there.
	#
	# A RAY, NOT THE AREA'S OVERLAPS. Walls are static - a TileMapLayer's
	# tiles, or a StaticBody2D - and this Area2D, moved by hand each frame,
	# never reported one as overlapping: it flew straight through a test wall
	# in the suite. A ray along this frame's step asks the physics space
	# directly and cannot miss it, however fast the axe is going.
	var from: Vector2 = global_position
	var to: Vector2 = from.move_toward(target, step)
	if is_inside_tree() and from != to:
		var query := PhysicsRayQueryParameters2D.create(from, to, WALL_LAYERS)
		query.collide_with_areas = false
		var hit: Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			var at: Vector2 = hit.get("position", to)
			global_position = at - (to - from).normalized() * 2.0
			return true
	global_position = to
	return false


# =============================================================================
# CUTTING
# =============================================================================

func _enemies_touching() -> Array[Node]:
	# Bodies and hurtbox areas both, the way slashwave.gd reads them, folded to
	# one entry per enemy - a creature with a body AND a hurtbox would
	# otherwise be cut twice by one tick.
	var seen: Dictionary = {}
	var found: Array[Node] = []
	for body in get_overlapping_bodies():
		if body.is_in_group("enemies") and not seen.has(body.get_instance_id()):
			seen[body.get_instance_id()] = true
			found.append(body)
	for area in get_overlapping_areas():
		var owner_node: Node = area.get_parent()
		if owner_node != null and owner_node.is_in_group("enemies") and not seen.has(owner_node.get_instance_id()):
			seen[owner_node.get_instance_id()] = true
			found.append(owner_node)
	return found


func _cut_what_it_passes() -> void:
	for enemy in _enemies_touching():
		var id: int = enemy.get_instance_id()
		if _passed.has(id):
			continue
		_passed[id] = true
		_cut(enemy, _swing_damage())


func _cut_everything_near() -> void:
	var swing: float = _swing_seconds()
	var damage: int = maxi(1, roundi(float(_swing_damage()) * TICK_SECONDS / swing))
	for enemy in _enemies_touching():
		_cut(enemy, damage)


func _cut(enemy: Node, damage: int) -> void:
	if not enemy.has_method("take_damage"):
		return
	enemy.take_damage(damage)
	hits_dealt += 1


func _swing_damage() -> int:
	if caster.has_method("_calculate_melee_damage"):
		return int(caster._calculate_melee_damage())
	return 0


func _swing_seconds() -> float:
	if caster.has_method("attack_period"):
		return maxf(0.05, float(caster.attack_period()))
	return 1.0
