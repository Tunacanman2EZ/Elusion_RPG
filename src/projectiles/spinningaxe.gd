# spinningaxe.gd - the warrior's attack while the Double Axe is equipped.
#
# The owner's design, day 2: "we can right click on a spot it will spin until
# right clicked again then it will come back". So the axe has three states:
#
#   OUT        thrown from the warrior to the spot aimed at, cutting every
#              enemy it passes on the way, once each
#   SPINNING   turning in place, cutting everything within its reach every
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
# THE WHIRLWIND AND THE BLEED (0.14.0). The owner: "we need to add a effect
# to double axe also to give it that feel", after the Meteorite's burning
# crater and Dynamite's smoulder, and of all three, "powerful but balanced".
#   - WHIRLWIND: its reach grows with its spin, from HIT_RADIUS when it lands
#     to REACH_AT_TOP times that at SPIN_MAX_RATE, and the wind it makes is
#     drawn - streaks circling it and dust swept round with them, fainter and
#     slower at 1x, thick and fast at the top. A pack around it is cut by
#     more of the axe the longer it is left. What it reaches a second on any
#     one enemy is unchanged; the area is the upgrade.
#   - BLEED: every cut - out, spinning or home - opens a wound on what it cut
#     (bleed.gd): a quarter of a swing every half second for two seconds after
#     the last cut, one wound per enemy, red drops falling from it. The books
#     allow for it: axe_bleed_share and axe_bleed_every in gamedata.json.
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

# MATCHED to the CollisionShape2D in spinningaxe.tscn: the reach as it flies
# and as it lands. Left spinning, the reach grows with the rate to
# REACH_AT_TOP times this (WHIRLWIND, above) - on this axe's own copy of the
# shape, never the scene's, which every axe shares.
const HIT_RADIUS := 20.0
const REACH_AT_TOP := 1.6

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
# Cuts open wounds (bleed.gd). The suite turns it off to count the cuts alone.
var wounds: bool = true

# The whirlwind: this axe's own circle, the angle the wind has turned through,
# and the dust swept round with it.
var _circle: CircleShape2D = null
var _swirl: float = 0.0
var _whirl: CPUParticles2D = null

@onready var spin: AnimatedSprite2D = $spin
@onready var shadow: Sprite2D = $shadow


func _ready() -> void:
	spin.position = Vector2(0, -HEIGHT)
	spin.play("spin")
	shadow.texture = Blast.shadow_texture(6, 3)
	shadow.modulate.a = 0.7
	# ITS OWN CIRCLE. The scene's CircleShape2D is one resource every axe
	# shares; growing that one would grow every warrior's axe at once.
	var hitshape: CollisionShape2D = get_node_or_null("hitshape")
	if hitshape != null and hitshape.shape is CircleShape2D:
		_circle = (hitshape.shape as CircleShape2D).duplicate()
		_circle.radius = HIT_RADIUS
		hitshape.shape = _circle
	_build_whirl()


func _build_whirl() -> void:
	# Dust on the rim of the reach, swept round it. Squares, whole pixels.
	_whirl = CPUParticles2D.new()
	_whirl.name = "whirl"
	_whirl.amount = 28
	_whirl.lifetime = 0.6
	_whirl.emitting = false
	_whirl.local_coords = true
	_whirl.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE_SURFACE
	_whirl.emission_sphere_radius = HIT_RADIUS
	_whirl.gravity = Vector2.ZERO
	_whirl.direction = Vector2(0, -1)
	_whirl.spread = 180.0
	_whirl.initial_velocity_min = 0.0
	_whirl.initial_velocity_max = 4.0
	_whirl.orbit_velocity_min = 0.7
	_whirl.orbit_velocity_max = 1.1
	_whirl.scale_amount_min = 1.5
	_whirl.scale_amount_max = 2.5
	_whirl.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	ramp.colors = PackedColorArray([Color(0.95, 0.95, 0.9, 0.0), Color(0.85, 0.85, 0.8, 0.8), Color(0.7, 0.7, 0.68, 0.0)])
	_whirl.color_ramp = ramp
	add_child(_whirl)


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
				if _whirl != null:
					_whirl.emitting = true
		State.SPINNING:
			# The rate for this step is the rate it had at the start of it,
			# so the first tick still lands TICK_SECONDS after it stops.
			var rate: float = spin_rate()
			_spun += delta
			_tick += delta * rate
			_swirl = fmod(_swirl + delta * TAU * 1.2 * rate, TAU * 8.0)
			if spin != null:
				spin.speed_scale = rate
			_wind_up()
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
	_calm()


func spin_rate() -> float:
	"""How fast it is spinning: 1 when it lands, climbing evenly to
	SPIN_MAX_RATE over SPIN_RAMP_SECONDS, then holding there."""
	return 1.0 + (SPIN_MAX_RATE - 1.0) * _wound_up()


func reach() -> float:
	"""How far it cuts: HIT_RADIUS flying and as it lands, growing with the
	spin to HIT_RADIUS * REACH_AT_TOP (WHIRLWIND)."""
	if state != State.SPINNING:
		return HIT_RADIUS
	return HIT_RADIUS * (1.0 + (REACH_AT_TOP - 1.0) * _wound_up())


func _wound_up() -> float:
	# How far up the spin it is: 0 when it lands, 1 at the top.
	if SPIN_RAMP_SECONDS <= 0.0:
		return 1.0
	return clampf(_spun / SPIN_RAMP_SECONDS, 0.0, 1.0)


func _wind_up() -> void:
	# The whirlwind keeps up with the spin: the circle that cuts, the dust on
	# its rim and the streaks drawn round it.
	var r: float = reach()
	if _circle != null:
		_circle.radius = r
	if _whirl != null:
		var rate: float = spin_rate()
		_whirl.emission_sphere_radius = r
		_whirl.orbit_velocity_min = 0.7 * rate
		_whirl.orbit_velocity_max = 1.1 * rate
		_whirl.modulate.a = lerpf(0.4, 1.0, _wound_up())
	queue_redraw()


func _calm() -> void:
	# Out of the spin - flying home, or thrown again: back to its own reach.
	if _circle != null:
		_circle.radius = HIT_RADIUS
	if _whirl != null:
		_whirl.emitting = false
	queue_redraw()


func _draw() -> void:
	# The wind, while it spins: four streaks on the rim of the reach and four
	# inside them turning faster, fainter and shorter at 1x, brighter and
	# longer at the top.
	if state != State.SPINNING:
		return
	var up: float = _wound_up()
	var r: float = reach()
	var a: float = lerpf(0.2, 0.6, up)
	var length: float = lerpf(0.5, 1.1, up)
	for ring in 2:
		var radius: float = r if ring == 0 else r * 0.62
		var turn: float = _swirl * (1.0 + 0.5 * ring) + 0.5 * ring
		var colour := Color(0.92, 0.95, 1.0, a if ring == 0 else a * 0.7)
		for i in 4:
			var from: float = turn + TAU * i / 4.0
			draw_arc(Vector2.ZERO, radius, from, from + length, 12, colour, 2.0 if ring == 0 else 1.0, false)


func throw_to(from: Vector2, aimed_at: Vector2) -> void:
	# Called once, by the warrior, after the axe is in the tree.
	global_position = from
	reset_physics_interpolation()
	var flight: Vector2 = aimed_at - from
	if flight.length() > MAX_THROW:
		flight = flight.normalized() * MAX_THROW
	target = from + flight
	state = State.OUT
	_passed.clear()
	_spun = 0.0
	_calm()


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
		var swing: int = _swing_damage()
		_cut(enemy, swing, swing)


func _cut_everything_near() -> void:
	var swing_seconds: float = _swing_seconds()
	var swing: int = _swing_damage()
	var damage: int = maxi(1, roundi(float(swing) * TICK_SECONDS / swing_seconds))
	for enemy in _enemies_touching():
		_cut(enemy, damage, swing)


func _cut(enemy: Node, damage: int, swing: int) -> void:
	if not enemy.has_method("take_damage"):
		return
	enemy.take_damage(damage)
	hits_dealt += 1
	# The wound is a share of a whole swing, whatever share of one this cut
	# was (bleed.gd).
	if wounds and swing > 0:
		Bleed.open(enemy, swing, caster)


func _swing_damage() -> int:
	if caster.has_method("_calculate_melee_damage"):
		return int(caster._calculate_melee_damage())
	return 0


func _swing_seconds() -> float:
	if caster.has_method("attack_period"):
		return maxf(0.05, float(caster.attack_period()))
	return 1.0
