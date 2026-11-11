# eartharena.gd - the Earth boss's arena (0.143.0): fault lines, falling rock
# and the quake. The fifth of the six arenas from the Docs plan "Boss fights:
# arenas that fight back". The owner: "ok next boss".
#
# MADE BY THE BOSS like the others (bossenemy.gd _keep_arena(), its kit's
# "arena"), where lightarena.gd's wanted() says, in the room room_of() says
# (never the Endless's corridor), as "eartharena<its shared number>". Gone
# with its boss.
#
#   one    THE BOX (0.144.0; it was a fault line across the room - the owner:
#          "spike wall need to be more like a box that traps players in"):
#          every FAULT_GAP the leader cracks a square of dust round a player,
#          BOX_HALF each way, for FAULT_WARN; then stalagmites rise on its four
#          sides for FAULT_LIFE: solid to walking (the walls layer), never to
#          an orb - the spikes are low and the orbs fly over - so whoever is
#          inside is trapped with the boss's orbs. Risen under you, it hits
#          (FAULT_SHARE) and throws you to the side most of you was on.
#   two    and FALLING ROCK: a shadow of grit near each player for ROCK_WARN,
#          then the rock lands - within ROCK_RADIUS, ROCK_SHARE as earth, and
#          rooted. Into a box with somebody in it, on them.
#
# THE ELEMENTS MIX (0.144.0, lightarena.gd react()): a rock on an ice wall
# shatters it (SHATTER); a box risen in the Fire boss's lava holds it back
# (POCKET - firearena.gd asks holds_back()).
#   three  and THE QUAKE: pieces of the floor crack (PIT_WARN) and drop away
#          for PIT_LIFE, then knit back - the Crowned's floor tear, fewer and
#          smaller. Standing in one as it opens, or walking in, you fall: a
#          share of your health (PIT_SHARE, at most every PIT_GAP) and thrown
#          out over its edge.
#
# THE SAME ON EVERY SCREEN: every fault, rock and pit is the leader's, sent as
# "la" world events; each game hurts only its own player.
#
# DRAWN IN QUADS ONLY: the cracks, shadows and pits on the floor (sorted
# first, as the tide), the stalagmites in pieces among everyone (each piece
# sorted by its own feet, so you stand behind or in front of the spikes).
#
# No class_name: preload it by path.
extends Node2D

const LightArena := preload("res://src/enemies/lightarena.gd")
const QuadBatch := preload("res://src/enemies/quadbatch.gd")
const StatusEffects := preload("res://src/characters/statuseffects.gd")
const SpikeFx := preload("res://src/projectiles/spikefx.gd")
const BossProjectile := preload("res://src/projectiles/bossprojectile.gd")
const Targets := preload("res://src/shared/targets.gd")
const HitSource := preload("res://src/shared/hitsource.gd")
const LagTests := preload("res://src/systems/lagtests.gd")

const GROUP := &"earth_arena"
const DUST := Color(0.62, 0.52, 0.38)
const ROCK := Color(0.42, 0.35, 0.29)
const ROCK_LIT := Color(0.62, 0.53, 0.42)

# FAULT LINES, by phase how often; how far along the line from the boss to the
# player it cracks (least, most); how far it may turn from square across it;
# how long it runs either way (cut to the room), the warning, how long the
# stalagmites stand, a piece's length, the spikes' height, how near the line
# counts as under it, and its share.
const FAULT_GAP := [8.0, 7.0, 6.0]
const BOX_HALF := 52.0
const FAULT_WARN := 1.6
const FAULT_LIFE := 3.5
const FAULT_RISE := 0.25
const PIECE := 48.0
const SPIKE_HIGH := 24.0
const FAULT_UNDER := 10.0
const FAULT_SHARE := 0.06
const BODY_LAYER := 2

# FALLING ROCK, by phase how often (0 none); the warning, its reach, how near a
# player, its share.
const ROCK_GAP := [0.0, 2.2, 1.6]
const ROCK_WARN := 1.0
const ROCK_RADIUS := 20.0
const ROCK_NEAR := 40.0
const ROCK_SHARE := 0.06
const ICE_GROUP := &"ice_arena"
const FIRE_GROUP := &"fire_arena"

# THE QUAKE (phase three): how often, how far from a player, the pit's size,
# the warning, how long it stays open, its share and how often it takes it,
# how far out it throws you.
const PIT_GAP := 1.8
const PIT_NEAR := 50.0
const PIT_RADIUS := 26.0
const PIT_WARN := 1.2
const PIT_LIFE := 3.5
const PIT_SHARE := 0.08
const PIT_GAP_HIT := 1.0
const PIT_THROW := 1.4
# Spots a pit tries before it waits (the floor book, lightarena.gd).
const TRIES := 4

# Furthest from its boss anything the leader sends may be put.
const EVENT_REACH := 1200.0
const END_SECONDS := 0.8


# =============================================================================
# A PIECE OF A FAULT'S WALL
# =============================================================================

class Ridge extends Node2D:
	# One piece of a fault's stalagmites: its own node, so it sorts by its own
	# feet among everyone, with its own body.
	var half: Vector2 = Vector2.ZERO
	var rise: float = 0.0
	var seed_no: int = 0
	var _body: StaticBody2D = null

	func build(along: Vector2, length: float) -> void:
		half = along * length * 0.5
		var bar := RectangleShape2D.new()
		bar.size = Vector2(length, 8.0)
		_body = StaticBody2D.new()
		_body.name = "rock"
		_body.collision_layer = BODY_LAYER
		_body.collision_mask = 0
		var foot := CollisionShape2D.new()
		foot.shape = bar
		foot.rotation = along.angle()
		foot.disabled = true
		_body.add_child(foot)
		add_child(_body)

	func set_solid(on: bool) -> void:
		for shape in _body.get_children():
			(shape as CollisionShape2D).set_deferred(&"disabled", not on)

	func _draw() -> void:
		if rise <= 0.0:
			return
		var a: Vector2 = -half
		var b: Vector2 = half
		var spikes: int = maxi(2, roundi(half.length() * 2.0 / 9.0))
		for k in spikes:
			var t0: float = float(k) / spikes
			var t1: float = float(k + 1) / spikes
			var p: Vector2 = a.lerp(b, t0)
			var q: Vector2 = a.lerp(b, t1)
			var tall: float = SPIKE_HIGH * rise * (0.7 + 0.3 * fmod(float(k + seed_no) * 0.618, 1.0))
			var tip: Vector2 = (p + q) * 0.5 + Vector2(0.0, -tall)
			draw_primitive(PackedVector2Array([p, q, tip, tip]), PackedColorArray([ROCK]), PackedVector2Array())
			draw_primitive(PackedVector2Array([p, (p + q) * 0.5, tip, tip]), PackedColorArray([ROCK_LIT]), PackedVector2Array())


# =============================================================================
# THE ARENA
# =============================================================================

var boss: Node2D = null
var phase: int = -1
# [from, to, age, ridges, risen] each.
var faults: Array = []
# [where, age] each.
var rocks: Array = []
# [where, age, opened] each.
var pits: Array = []
var _fault_clock: float = 3.0
var _rock_clock: float = 0.0
var _pit_clock: float = 0.0
var _pit_hit_left: float = 0.0
var _zone: BulletZone = null
var _floor: Node2D = null
# Every quad of a layer, handed over in one call (quadbatch.gd).
var _quads := QuadBatch.new()
var _room: Rect2 = Rect2()
var _clock: float = 0.0
var _ending: float = -1.0


static func make(for_boss: Node2D) -> Node2D:
	if not LightArena.wanted(for_boss):
		return null
	var container: Node = for_boss.get_tree().get_first_node_in_group(&"groundeffects")
	var arena := (load("res://src/enemies/eartharena.gd") as GDScript).new() as Node2D
	arena.set(&"boss", for_boss)
	arena.name = name_for(for_boss)
	container.add_child(arena)
	return arena


static func name_for(for_boss: Node2D) -> String:
	return "eartharena%d" % maxi(int(for_boss.get(&"net_id")), 0)


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(LagTests.GROUP)
	add_to_group(LightArena.FLOOR_GROUP)
	y_sort_enabled = true
	_zone = BulletZone.find(self)
	_room = LightArena.room_of(self)
	if not _room.has_area():
		_room = Rect2(boss.global_position - Vector2(300, 300), Vector2(600, 600))
	_floor = Node2D.new()
	_floor.name = "ground"
	_floor.position = Vector2(0.0, SpikeFx.SORT_Y - 1.0)
	_floor.draw.connect(_quads.paint.bind(_floor, _draw_floor))
	add_child(_floor)
	_floor.reset_physics_interpolation()
	show_tests()


# =============================================================================
# EACH FRAME
# =============================================================================

func _process(delta: float) -> void:
	_clock += delta
	if _ending >= 0.0:
		_ending += delta
		_floor.queue_redraw()
		if _ending >= END_SECONDS:
			queue_free()
		return
	if not _boss_here():
		_end()
		return
	var now: int = LightArena.arena_phase(self)
	if now != phase:
		phase = now
	if name != name_for(boss):
		name = name_for(boss)
	if not bool(boss.get(&"net_mirror")):
		_lead(delta)
	_age(delta)
	_pits_on_you(delta)
	if QuadBatch.turn(self, QuadBatch.FLOOR_EVERY):
		_floor.queue_redraw()


func _boss_here() -> bool:
	if not is_instance_valid(boss) or not boss.is_inside_tree():
		return false
	return not (bool(boss.get(&"_dying")) or bool(boss.get(&"_death_resolved")) or bool(boss.get(&"gated")))


func _p(table: Array) -> float:
	return float(table[clampi(phase, 0, 2)])


# WHO IS IN THE FIGHT, LOOKED UP FOUR TIMES A SECOND (0.143.0, the
# refinement): the leader's clocks asked the boss every frame
# (fight_targets(), a walk over everyone), about a third of this arena's frame.
const LOOK_SECONDS := 0.25
var _fight: Array = []
var _look_left: float = 0.0


func _fighters(delta: float) -> Array:
	"""(Leader.) The boss's fight_targets(), kept LOOK_SECONDS."""
	_look_left -= delta
	if _look_left <= 0.0:
		_look_left = LOOK_SECONDS
		_fight = boss.call(&"fight_targets")
	for body in _fight:
		if not is_instance_valid(body):
			_fight = _fight.filter(func(b: Variant) -> bool: return is_instance_valid(b))
			break
	return _fight


func _lead(delta: float) -> void:
	"""(Leader.) The faults, the rocks and the quake, for every screen."""
	var bodies: Array = _fighters(delta)
	if bodies.is_empty():
		return
	_fault_clock -= delta
	if _fault_clock <= 0.0:
		_fault_clock = LightArena.paced(self, _p(FAULT_GAP))
		var at: Vector2 = Targets.body_point(bodies[randi() % bodies.size()])
		add_box(at)
		_send({"h": "box", "x": snappedf(at.x, 0.1), "y": snappedf(at.y, 0.1)})
	var gap: float = _p(ROCK_GAP)
	if gap > 0.0:
		_rock_clock -= delta
		if _rock_clock <= 0.0:
			_rock_clock = LightArena.paced(self, gap)
			for body in bodies:
				var who: Vector2 = Targets.body_point(body)
				# Trapped in a box: the rock comes down on you.
				var at: Vector2 = who if boxed(who) else _inside(who + Vector2.from_angle(randf() * TAU) * randf() * ROCK_NEAR)
				add_rock(at)
				_send({"h": "rock", "x": snappedf(at.x, 0.1), "y": snappedf(at.y, 0.1)})
	if phase >= 2:
		_pit_clock -= delta
		if _pit_clock <= 0.0:
			_pit_clock = LightArena.paced(self, PIT_GAP)
			var who: Vector2 = Targets.body_point(bodies[randi() % bodies.size()])
			# THE FLOOR BOOK (lightarena.gd): a few tries, or this pit waits.
			for _try in TRIES:
				var at: Vector2 = _inside(who + Vector2.from_angle(randf() * TAU) * randf() * PIT_NEAR)
				if LightArena.may_take(self, at, PIT_RADIUS):
					add_pit(at)
					_send({"h": "pit", "x": snappedf(at.x, 0.1), "y": snappedf(at.y, 0.1)})
					break


func _inside(at: Vector2) -> Vector2:
	return at.clamp(_room.position + Vector2(24, 24), _room.end - Vector2(24, 24))


func _send(event: Dictionary) -> void:
	event["k"] = "la"
	if boss.has_method(&"arena_event"):
		boss.call(&"arena_event", event)


func hear(event: Dictionary) -> void:
	"""(Follower, from the leader's "la".) Only what it knows, near its boss."""
	if _ending >= 0.0:
		return
	var at := Vector2(float(event.get("x", 0.0)), float(event.get("y", 0.0)))
	if at.distance_to(boss.global_position) > EVENT_REACH:
		return
	match str(event.get("h", "")):
		"box":
			add_box(at)
		"rock":
			add_rock(at)
		"pit":
			add_pit(at)


# =============================================================================
# THE FAULTS
# =============================================================================

# A box is [middle, age, ridges, risen, sides]: sides its four [from, to].

func add_box(at: Vector2) -> void:
	"""A box of stalagmites round `at` (kept inside the room), BOX_HALF each
	way: dust for FAULT_WARN, then it rises."""
	var m: Vector2 = at.clamp(_room.position + Vector2.ONE * (BOX_HALF + 8.0), _room.end - Vector2.ONE * (BOX_HALF + 8.0))
	var h: float = BOX_HALF
	var corners: Array = [m + Vector2(-h, -h), m + Vector2(h, -h), m + Vector2(h, h), m + Vector2(-h, h)]
	var sides: Array = []
	var ridges: Array = []
	for s in 4:
		var from: Vector2 = corners[s]
		var to: Vector2 = corners[(s + 1) % 4]
		sides.append([from, to])
		var length: float = from.distance_to(to)
		var count: int = maxi(1, ceili(length / PIECE))
		var way: Vector2 = (to - from).normalized()
		for k in count:
			var ridge := Ridge.new()
			ridge.name = "ridge%d_%d_%d" % [faults.size(), s, k]
			ridge.seed_no = k * 7 + s * 3 + faults.size()
			add_child(ridge)
			ridge.global_position = from.lerp(to, (float(k) + 0.5) / count)
			ridge.reset_physics_interpolation()
			ridge.build(way, length / count)
			ridges.append(ridge)
	faults.append([m, 0.0, ridges, false, sides])
	PerfOverlay.mark(&"faults crack")


func box_rect(box: Array) -> Rect2:
	return Rect2((box[0] as Vector2) - Vector2.ONE * BOX_HALF, Vector2.ONE * BOX_HALF * 2.0)


func boxed(at: Vector2) -> bool:
	"""Inside a box that has risen."""
	for box in faults:
		if bool(box[3]) and box_rect(box).has_point(at):
			return true
	return false


func holds_back(at: Vector2) -> bool:
	"""(POCKET, firearena.gd in_lava().) A risen box keeps the lava out."""
	return boxed(at)


func _rise(box: Array) -> void:
	box[3] = true
	for ridge in box[2]:
		(ridge as Ridge).set_solid(true)
	var m: Vector2 = box[0]
	var fx: Node2D = SpikeFx.of(get_parent())
	if fx != null and BossProjectile.ELEMENT_SPARKS.has(Element.Type.EARTH):
		for side in box[4]:
			var mid: Vector2 = ((side[0] as Vector2) + (side[1] as Vector2)) * 0.5
			fx.call(&"burst", mid, Element.Type.EARTH, Vector2(BOX_HALF, 4.0), BossProjectile.ELEMENT_SPARKS[Element.Type.EARTH])
	# POCKET: risen in the Fire boss's lava, it holds the lava back.
	var fire: Node = LightArena.partner(self, FIRE_GROUP)
	if fire != null and fire.has_method(&"lava_covers") and bool(fire.call(&"lava_covers", m)):
		LightArena.react(self, m, "Pocket", Element.Type.EARTH)
	# Risen under this game's player: a hit, and thrown to the side most of
	# it was on - in, or out.
	var me: Node2D = _me()
	if me == null:
		return
	var at: Vector2 = Targets.body_point(me)
	var nearest: float = INF
	for side in box[4]:
		var on: Vector2 = Geometry2D.get_closest_point_to_segment(at, side[0], side[1])
		nearest = minf(nearest, at.distance_to(on))
	if nearest > FAULT_UNDER:
		return
	var way: Vector2 = (m - at) if box_rect(box).has_point(at) else (at - m)
	if way.length() < 0.5:
		way = Vector2.DOWN
	_hit(me, FAULT_SHARE, "spike box", &"", at)
	if StatusEffects.apply_to(me, StatusEffects.SHOVE, 0, at - way.normalized() * 20.0, false, 1.0):
		StatusEffects.slide(me, 1.2, 0.3)


func _sink(box: Array) -> void:
	for ridge in box[2]:
		if is_instance_valid(ridge):
			(ridge as Node).queue_free()


func standing_faults() -> int:
	var n: int = 0
	for box in faults:
		if bool(box[3]):
			n += 1
	return n


# =============================================================================
# ROCKS AND PITS
# =============================================================================

func add_rock(at: Vector2) -> void:
	rocks.append([at, 0.0])


func add_pit(at: Vector2) -> void:
	pits.append([at, 0.0, false])


func _land(at: Vector2) -> void:
	PerfOverlay.mark(&"rocks fall")
	var fx: Node2D = SpikeFx.of(get_parent())
	if fx != null and BossProjectile.ELEMENT_SPARKS.has(Element.Type.EARTH):
		fx.call(&"burst", at, Element.Type.EARTH, Vector2(8, 3), BossProjectile.ELEMENT_SPARKS[Element.Type.EARTH])
	# SHATTER: a rock on the Ice boss's wall breaks it, a door early. Every
	# screen has the rock and the wall, so each breaks its own.
	var ice: Node = LightArena.partner(self, ICE_GROUP)
	if ice != null and ice.has_method(&"wall_near"):
		var wall: Variant = ice.call(&"wall_near", at, ROCK_RADIUS)
		if wall != null:
			ice.call(&"break_wall", wall, false)
			LightArena.react(self, at, "Shatter", Element.Type.ICE)
	var me: Node2D = _me()
	if me != null and Targets.body_point(me).distance_to(at) <= ROCK_RADIUS:
		_hit(me, ROCK_SHARE, "rock", StatusEffects.ROOT, at)


func open_pit(at: Vector2) -> bool:
	"""A pit open under `at`."""
	for pit in pits:
		if bool(pit[2]) and at.distance_to(pit[0]) <= PIT_RADIUS:
			return true
	return false


func takes_floor(at: Vector2) -> bool:
	"""(The floor book, lightarena.gd.) A pit, cracking or open."""
	for pit in pits:
		if at.distance_to(pit[0]) <= PIT_RADIUS:
			return true
	return false


func _pits_on_you(delta: float) -> void:
	_pit_hit_left = maxf(0.0, _pit_hit_left - delta)
	var me: Node2D = _me()
	if me == null or _pit_hit_left > 0.0:
		return
	var at: Vector2 = Targets.body_point(me)
	for pit in pits:
		if not bool(pit[2]) or at.distance_to(pit[0]) > PIT_RADIUS:
			continue
		_pit_hit_left = PIT_GAP_HIT
		_hit(me, PIT_SHARE, "quake", &"", pit[0])
		if StatusEffects.apply_to(me, StatusEffects.SHOVE, 0, pit[0], false, 1.0):
			StatusEffects.slide(me, PIT_THROW, 0.4)
		return


# =============================================================================
# AGEING, AND WHAT IT DOES TO YOU
# =============================================================================

func _age(delta: float) -> void:
	var i: int = 0
	while i < faults.size():
		var box: Array = faults[i]
		box[1] = float(box[1]) + delta
		var age: float = float(box[1])
		if not bool(box[3]) and age >= FAULT_WARN:
			_rise(box)
		var rise: float = clampf((age - FAULT_WARN) / FAULT_RISE, 0.0, 1.0)
		var sink: float = clampf((FAULT_WARN + FAULT_LIFE - age) / FAULT_RISE, 0.0, 1.0)
		var now: float = minf(rise, sink)
		for ridge in box[2]:
			if is_instance_valid(ridge) and not is_equal_approx((ridge as Ridge).rise, now):
				(ridge as Ridge).rise = now
				(ridge as Ridge).queue_redraw()
		if age >= FAULT_WARN + FAULT_LIFE:
			_sink(box)
			faults.remove_at(i)
			continue
		i += 1
	i = 0
	while i < rocks.size():
		rocks[i][1] = float(rocks[i][1]) + delta
		if float(rocks[i][1]) >= ROCK_WARN:
			_land(rocks[i][0])
			rocks.remove_at(i)
			continue
		i += 1
	i = 0
	while i < pits.size():
		var pit: Array = pits[i]
		pit[1] = float(pit[1]) + delta
		if not bool(pit[2]) and float(pit[1]) >= PIT_WARN:
			pit[2] = true
			PerfOverlay.mark(&"floor drops")
		if float(pit[1]) >= PIT_WARN + PIT_LIFE:
			pits.remove_at(i)
			continue
		i += 1


func _me() -> Node2D:
	var me: Node2D = get_tree().get_first_node_in_group(&"player") as Node2D
	if me == null or bool(me.get(&"is_dying")):
		return null
	return me


func _hit(me: Node2D, share: float, what: String, effect: StringName, from: Vector2) -> void:
	if not me.has_method(&"take_damage") or not LightArena.may_hit(me, self):
		return
	var amount: int = maxi(1, roundi(float(me.get(&"max_hp")) * share))
	HitSource.blame(HitSource.of(boss, what))
	me.call(&"take_damage", amount, Element.Type.EARTH)
	if effect != &"":
		StatusEffects.apply_to(me, effect, amount, from, false, 1.0)


# =============================================================================
# DRAWING (quads only, on the floor)
# =============================================================================

func _fill(p: Vector2, q: Vector2, r: Vector2, t: Vector2, colour: Color) -> void:
	# Into the floor's batch (quadbatch.gd: the whole floor in one call).
	_quads.quad(p, q, r, t, colour)


func _bar(from: Vector2, to: Vector2, width: float, colour: Color) -> void:
	var side: Vector2 = (to - from).orthogonal().normalized() * width * 0.5
	_fill(from - side, to - side, to + side, from + side, colour)


func _disc(middle: Vector2, r: float, colour: Color, solid: bool) -> void:
	if solid:
		_quads.oval(middle, r, r * 0.55, colour)
	else:
		_quads.band(middle, r, r * 0.55, 0.9, colour)


func _crack(from: Vector2, to: Vector2, width: float, colour: Color, jag: float) -> void:
	# A jagged crack from `from` to `to`.
	var steps: int = maxi(2, ceili(from.distance_to(to) / 14.0))
	var across: Vector2 = (to - from).orthogonal().normalized()
	var last: Vector2 = from
	for k in range(1, steps + 1):
		var t: float = float(k) / steps
		var wiggle: float = 0.0 if k == steps else (fmod(float(k) * 0.618, 1.0) - 0.5) * jag
		var next: Vector2 = from.lerp(to, t) + across * wiggle
		_bar(last, next, width, colour)
		last = next


func _draw_floor() -> void:
	var o: Vector2 = _floor.global_position
	var fade: float = 1.0 if _ending < 0.0 else clampf(1.0 - _ending / END_SECONDS, 0.0, 1.0)
	for box in faults:
		var age: float = float(box[1])
		var warn: float = clampf(age / FAULT_WARN, 0.0, 1.0)
		for side in box[4]:
			var from: Vector2 = (side[0] as Vector2) - o
			var to: Vector2 = (side[1] as Vector2) - o
			if not bool(box[3]):
				_crack(from, to, 2.0 + 6.0 * warn, Color(DUST, (0.25 + 0.4 * warn) * fade), 0.0)
			_crack(from, to, 1.5, Color(0.12, 0.09, 0.07, 0.8 * fade), 4.0)
	for stone in rocks:
		var m: Vector2 = (stone[0] as Vector2) - o
		var grow: float = clampf(float(stone[1]) / ROCK_WARN, 0.0, 1.0)
		_disc(m, ROCK_RADIUS * grow, Color(0, 0, 0, (0.2 + 0.35 * grow) * fade), true)
		_disc(m, ROCK_RADIUS, Color(DUST, (0.3 + 0.5 * grow) * fade), false)
	for pit in pits:
		var m: Vector2 = (pit[0] as Vector2) - o
		var t: float = float(pit[1])
		if not bool(pit[2]):
			var warn: float = clampf(t / PIT_WARN, 0.0, 1.0)
			for k in 6:
				var out: Vector2 = Vector2.from_angle(float(k) * TAU / 6.0 + 0.4) * PIT_RADIUS * (0.5 + 0.5 * warn)
				_crack(m, m + Vector2(out.x, out.y * 0.55), 1.5, Color(0.12, 0.09, 0.07, (0.4 + 0.5 * warn) * fade), 3.0)
		else:
			var closing: float = clampf((PIT_WARN + PIT_LIFE - t) / 0.4, 0.0, 1.0)
			_disc(m, PIT_RADIUS * closing, Color(0.03, 0.02, 0.02, 0.92 * fade), true)
			_disc(m, PIT_RADIUS * closing, Color(DUST, 0.6 * fade), false)


# =============================================================================
# THE END, AND THE LAG TEST
# =============================================================================

func _end() -> void:
	"""Its boss is gone: the stalagmites sink, the floor knits, then it goes."""
	if _ending >= 0.0:
		return
	_ending = 0.0
	for fault in faults:
		_sink(fault)
	faults.clear()
	rocks.clear()
	pits.clear()


func show_tests() -> void:
	"""The GM panel's Arena lag test: the cracks, shadows and pits drawn or
	not (they still hurt; the stalagmites stand)."""
	if _floor != null:
		_floor.visible = not LagTests.hide_arena
