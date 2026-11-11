# firearena.gd - the Fire boss's arena (0.143.0): lava vents, embers and the
# rising lava. The last of the six arenas from the Docs plan "Boss fights:
# arenas that fight back". The owner: "next boss".
#
# MADE BY THE BOSS like the others (bossenemy.gd _keep_arena(), its kit's
# "arena"), where lightarena.gd's wanted() says, in the room room_of() says
# (never the Endless's corridor), as "firearena<its shared number>". Gone
# with its boss.
#
#   one    LAVA VENTS: VENTS cracks stand on a ring round the room's middle.
#          Every SWEEP_GAP the leader starts a sweep from one of them, round
#          one way, SWEEP_LENGTH long: each glows for VENT_WARN, erupts in a
#          column of fire (within VENT_RADIUS: VENT_SHARE as fire, burning)
#          and leaves a pool that burns while you stand in it (POOL_LIFE),
#          the next VENT_STEP after - so a sweep never doubles back; follow
#          it.
#   two    and EMBERS: the leader lets one fall over each player every
#          EMBER_GAP; it drifts down EMBER_FALL, swaying, and one that touches
#          you sets you burning (EMBER_SHARE).
#   three  and THE LAVA RISES: from the room's edges, over LAVA_RISE, until
#          only LAVA_KEEP of the room is left in the middle (the Boss Arena's
#          dirt square). In it, LAVA_SHARE every LAVA_GAP, burning. Hold the
#          middle.
#
# THE SAME ON EVERY SCREEN: the vents stand where the room says, each sweep
# and ember is the leader's ("la"), every game plays them on its own clock;
# the lava follows the boss's phase. Each game hurts only its own player.
#
# DRAWN IN QUADS ONLY: the vents, pools and lava on the floor (sorted first,
# as the tide), the columns and embers over everything.
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

const GROUP := &"fire_arena"
const EMBER := Color(1.0, 0.62, 0.2)
const LAVA := Color(0.86, 0.27, 0.08)
const LAVA_LIT := Color(1.0, 0.72, 0.25)

# THE VENTS: how many on the ring, the ring's size (a share of the room's
# half each way); a sweep, by phase how often, how many vents, the gap
# between two; a vent's warning, its column, its reach and share; the pool's
# life, reach and how often it burns you.
const VENTS := 8
const RING := 0.7
const SWEEP_GAP := [7.0, 6.0, 5.0]
const SWEEP_LENGTH := [5, 6, 6]
const VENT_STEP := 0.35
const VENT_WARN := 0.8
const VENT_BURST := 0.5
const VENT_RADIUS := 22.0
const VENT_SHARE := 0.07
const POOL_LIFE := 3.0
const POOL_RADIUS := 20.0
const POOL_GAP := 0.6
const POOL_SHARE := 0.02

# THE EMBERS, by phase how often (0 none); how high over the player one
# starts, how far either side, how fast it falls and sways, how long it
# lives, how near touches, its share.
const EMBER_GAP := [0.0, 1.2, 0.9]
const EMBER_HIGH := 130.0
const EMBER_SPREAD := 60.0
const EMBER_FALL := 45.0
const EMBER_SWAY := 14.0
const EMBER_LIFE := 3.5
const EMBER_TOUCH := 8.0
const EMBER_SHARE := 0.03

# THE LAVA (phase three): how much of the room it leaves in the middle (a
# share across, a share down - the Boss Arena's dirt square: the owner,
# "Deeper"), how long it takes to rise or ebb, how often it takes its share.
const LAVA_KEEP := Vector2(0.45, 0.5)
# WITH PARTNERS (0.143.0, a wave): the lava leaves half the room, not the dirt
# square alone, while another boss is loose here, and creeps back to LAVA_KEEP
# over LAVA_RISE once Fire fights alone.
const LAVA_KEEP_SHARED := Vector2(0.7, 0.72)
# Glints drifting on the lava (24: the refinement; it was 40).
const GLINTS := 24
const LAVA_RISE := 3.0
const LAVA_GAP := 0.8
const LAVA_SHARE := 0.04

const SWEEP_FIRST := 2.0
const DRAW_Z := 17
const END_SECONDS := 0.8

var boss: Node2D = null
var phase: int = -1
# Where each vent stands.
var vents: PackedVector2Array = PackedVector2Array()
# [vent, age, erupted] each: a vent's turn in a sweep.
var turns: Array = []
# [where, age] each.
var pools: Array = []
# [from, age, sway phase] each.
var embers: Array = []
var lava: float = 0.0
# What the lava leaves now: LAVA_KEEP alone, LAVA_KEEP_SHARED with partners.
var keep: Vector2 = LAVA_KEEP
var _sweep_clock: float = SWEEP_FIRST
var _ember_clock: float = 0.0
var _pool_left: float = 0.0
var _lava_left: float = 0.0
var _floor: Node2D = null
# Every quad of a layer, handed over in one call (quadbatch.gd).
var _quads := QuadBatch.new()
var _air: Node2D = null
var _room: Rect2 = Rect2()
var _clock: float = 0.0
var _ending: float = -1.0


static func make(for_boss: Node2D) -> Node2D:
	if not LightArena.wanted(for_boss):
		return null
	var container: Node = for_boss.get_tree().get_first_node_in_group(&"groundeffects")
	var arena := (load("res://src/enemies/firearena.gd") as GDScript).new() as Node2D
	arena.set(&"boss", for_boss)
	arena.name = name_for(for_boss)
	container.add_child(arena)
	return arena


static func name_for(for_boss: Node2D) -> String:
	return "firearena%d" % maxi(int(for_boss.get(&"net_id")), 0)


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(LagTests.GROUP)
	add_to_group(LightArena.FLOOR_GROUP)
	_room = LightArena.room_of(self)
	if not _room.has_area():
		_room = Rect2(boss.global_position - Vector2(300, 300), Vector2(600, 600))
	var middle: Vector2 = _room.get_center()
	for k in VENTS:
		var a: float = float(k) * TAU / VENTS - PI * 0.5
		vents.append(middle + Vector2(cos(a) * _room.size.x, sin(a) * _room.size.y) * 0.5 * RING)
	_floor = Node2D.new()
	_floor.name = "lava"
	_floor.position = Vector2(0.0, SpikeFx.SORT_Y - 1.0)
	_floor.draw.connect(_quads.paint.bind(_floor, _draw_floor))
	add_child(_floor)
	_floor.reset_physics_interpolation()
	_air = Node2D.new()
	_air.name = "fire"
	_air.z_index = DRAW_Z
	_air.z_as_relative = false
	_air.draw.connect(_quads.paint.bind(_air, _draw_air))
	add_child(_air)
	show_tests()


# =============================================================================
# EACH FRAME
# =============================================================================

func _process(delta: float) -> void:
	_clock += delta
	if _ending >= 0.0:
		_ending += delta
		lava = maxf(0.0, lava - delta / END_SECONDS)
		_floor.queue_redraw()
		_air.queue_redraw()
		if _ending >= END_SECONDS:
			queue_free()
		return
	if not _boss_here():
		_end()
		return
	var now: int = int(boss.call(&"_current_phase"))
	if now != phase:
		phase = now
	if name != name_for(boss):
		name = name_for(boss)
	if not bool(boss.get(&"net_mirror")):
		_lead(delta)
	_age(delta)
	lava = clampf(lava + (delta if phase >= 2 else -delta) / LAVA_RISE, 0.0, 1.0)
	var want: Vector2 = LAVA_KEEP_SHARED if LightArena.partners(boss) > 0 else LAVA_KEEP
	keep = keep.move_toward(want, delta * (LAVA_KEEP_SHARED - LAVA_KEEP).length() / LAVA_RISE)
	_on_you(delta)
	if QuadBatch.turn(self, QuadBatch.FLOOR_EVERY):
		_floor.queue_redraw()
	_air.queue_redraw()


func _boss_here() -> bool:
	if not is_instance_valid(boss) or not boss.is_inside_tree():
		return false
	return not (bool(boss.get(&"_dying")) or bool(boss.get(&"_death_resolved")) or bool(boss.get(&"gated")))


func _lead(delta: float) -> void:
	"""(Leader.) The sweeps and the embers, for every screen."""
	_sweep_clock -= delta
	if _sweep_clock <= 0.0:
		_sweep_clock = LightArena.paced(self, float(SWEEP_GAP[clampi(phase, 0, 2)]))
		var start: int = randi() % VENTS
		var way: int = 1 if randi() % 2 == 0 else -1
		var count: int = int(SWEEP_LENGTH[clampi(phase, 0, 2)])
		start_sweep(start, way, count)
		_send({"h": "sweep", "s": start, "d": way, "n": count})
	var gap: float = float(EMBER_GAP[clampi(phase, 0, 2)])
	if gap > 0.0:
		_ember_clock -= delta
		if _ember_clock <= 0.0:
			_ember_clock = LightArena.paced(self, gap)
			for body in boss.call(&"fight_targets"):
				var from: Vector2 = Targets.body_point(body) + Vector2(randf_range(-EMBER_SPREAD, EMBER_SPREAD), -EMBER_HIGH)
				add_ember(from)
				_send({"h": "ember", "x": snappedf(from.x, 0.1), "y": snappedf(from.y, 0.1)})


func _send(event: Dictionary) -> void:
	event["k"] = "la"
	if boss.has_method(&"arena_event"):
		boss.call(&"arena_event", event)


func hear(event: Dictionary) -> void:
	"""(Follower, from the leader's "la".) Only what it knows."""
	if _ending >= 0.0:
		return
	match str(event.get("h", "")):
		"sweep":
			start_sweep(int(event.get("s", 0)), 1 if int(event.get("d", 1)) >= 0 else -1,
				clampi(int(event.get("n", 5)), 1, VENTS))
		"ember":
			var from := Vector2(float(event.get("x", 0.0)), float(event.get("y", 0.0)))
			if from.distance_to(boss.global_position) <= 1200.0:
				add_ember(from)


func start_sweep(start: int, way: int, count: int) -> void:
	"""A sweep round the ring from vent `start`, `way` round, `count` vents:
	each one's turn VENT_STEP after the last."""
	for k in count:
		turns.append([posmod(start + way * k, VENTS), -VENT_STEP * k, false])


func add_ember(from: Vector2) -> void:
	embers.append([from, 0.0, fmod(from.x * 0.37, TAU)])


func ember_at(ember: Array) -> Vector2:
	var t: float = float(ember[1])
	return (ember[0] as Vector2) + Vector2(sin(t * 2.2 + float(ember[2])) * EMBER_SWAY, EMBER_FALL * t)


# =============================================================================
# AGEING, AND WHAT IT DOES TO YOU
# =============================================================================

func _age(delta: float) -> void:
	var i: int = 0
	while i < turns.size():
		var turn: Array = turns[i]
		turn[1] = float(turn[1]) + delta
		if not bool(turn[2]) and float(turn[1]) >= VENT_WARN:
			turn[2] = true
			_erupt(int(turn[0]))
		if float(turn[1]) >= VENT_WARN + VENT_BURST:
			turns.remove_at(i)
			continue
		i += 1
	i = 0
	while i < pools.size():
		pools[i][1] = float(pools[i][1]) + delta
		if float(pools[i][1]) >= POOL_LIFE:
			pools.remove_at(i)
			continue
		i += 1
	i = 0
	while i < embers.size():
		embers[i][1] = float(embers[i][1]) + delta
		if float(embers[i][1]) >= EMBER_LIFE:
			embers.remove_at(i)
			continue
		i += 1


func _erupt(vent: int) -> void:
	var at: Vector2 = vents[vent]
	pools.append([at, 0.0])
	PerfOverlay.mark(&"vents erupt")
	var fx: Node2D = SpikeFx.of(get_parent())
	if fx != null and BossProjectile.ELEMENT_SPARKS.has(Element.Type.FIRE):
		fx.call(&"burst", at, Element.Type.FIRE, Vector2(10, 4), BossProjectile.ELEMENT_SPARKS[Element.Type.FIRE])
	var me: Node2D = _me()
	if me != null and Targets.body_point(me).distance_to(at) <= VENT_RADIUS:
		_hit(me, VENT_SHARE, "vent", at)


func _me() -> Node2D:
	var me: Node2D = get_tree().get_first_node_in_group(&"player") as Node2D
	if me == null or bool(me.get(&"is_dying")):
		return null
	return me


func dry() -> Rect2:
	"""What the lava leaves: the room, shrinking to `keep` of it (LAVA_KEEP,
	or LAVA_KEEP_SHARED with partners)."""
	var left: Vector2 = _room.size * (Vector2.ONE - (Vector2.ONE - keep) * lava)
	return Rect2(_room.get_center() - left * 0.5, left)


func in_lava(at: Vector2) -> bool:
	"""In the risen lava: in the room, out of what it leaves dry."""
	return lava > 0.0 and _room.has_point(at) and not dry().has_point(at)


func takes_floor(at: Vector2) -> bool:
	"""(The floor book, lightarena.gd.) The risen lava and the pools."""
	if in_lava(at):
		return true
	for pool in pools:
		if at.distance_to(pool[0]) <= POOL_RADIUS:
			return true
	return false


func _on_you(delta: float) -> void:
	_pool_left = maxf(0.0, _pool_left - delta)
	_lava_left = maxf(0.0, _lava_left - delta)
	var me: Node2D = _me()
	if me == null:
		return
	var at: Vector2 = Targets.body_point(me)
	if not LightArena.in_room(self, at):
		return
	var i: int = 0
	while i < embers.size():
		if ember_at(embers[i]).distance_to(at) <= EMBER_TOUCH:
			_hit(me, EMBER_SHARE, "ember", ember_at(embers[i]))
			embers.remove_at(i)
			continue
		i += 1
	if _pool_left <= 0.0:
		for pool in pools:
			if at.distance_to(pool[0]) <= POOL_RADIUS:
				_pool_left = POOL_GAP
				_hit(me, POOL_SHARE, "lava pool", pool[0], true)
				break
	if _lava_left <= 0.0 and in_lava(at):
		_lava_left = LAVA_GAP
		_hit(me, LAVA_SHARE, "lava", at, true)
		PerfOverlay.mark(&"lava burns")


func _hit(me: Node2D, share: float, what: String, from: Vector2, ground: bool = false) -> void:
	if not me.has_method(&"take_damage") or not LightArena.may_hit(me, self):
		return
	var amount: int = maxi(1, roundi(float(me.get(&"max_hp")) * share))
	HitSource.blame(HitSource.of(boss, what))
	me.call(&"take_damage", amount, Element.Type.FIRE)
	StatusEffects.apply_to(me, StatusEffects.BURN, amount, from, ground, 1.0)


# =============================================================================
# DRAWING (quads only)
# =============================================================================

func _fill(_on: CanvasItem, p: Vector2, q: Vector2, r: Vector2, t: Vector2, colour: Color) -> void:
	# Into the layer's batch (quadbatch.gd: the whole layer in one call).
	_quads.quad(p, q, r, t, colour)


func _disc(_on: CanvasItem, middle: Vector2, r: float, colour: Color) -> void:
	_quads.oval(middle, r, r * 0.55, colour)


func _draw_floor() -> void:
	var o: Vector2 = _floor.global_position
	var fade: float = 1.0 if _ending < 0.0 else clampf(1.0 - _ending / END_SECONDS, 0.0, 1.0)
	# The vents: a dark crack each, glowing as its turn comes.
	var glow: PackedFloat32Array = PackedFloat32Array()
	glow.resize(VENTS)
	for turn in turns:
		glow[int(turn[0])] = maxf(glow[int(turn[0])], clampf(float(turn[1]) / VENT_WARN, 0.0, 1.0))
	for k in VENTS:
		var m: Vector2 = vents[k] - o
		_fill(_floor, m + Vector2(-10, 0), m + Vector2(-2, -3), m + Vector2(10, 1), m + Vector2(2, 3), Color(0.1, 0.05, 0.03, 0.8 * fade))
		if glow[k] > 0.0:
			_disc(_floor, m, 6.0 + 12.0 * glow[k], Color(EMBER, (0.3 + 0.5 * glow[k]) * fade))
	# The pools.
	for pool in pools:
		var left: float = clampf((POOL_LIFE - float(pool[1])) / 0.5, 0.0, 1.0)
		var m: Vector2 = (pool[0] as Vector2) - o
		_disc(_floor, m, POOL_RADIUS, Color(LAVA, 0.75 * left * fade))
		_disc(_floor, m, POOL_RADIUS * 0.5, Color(LAVA_LIT, 0.6 * left * fade))
	# The risen lava, from the walls in.
	if lava > 0.0:
		var outer := Rect2(_room.position - o, _room.size)
		var inner := Rect2(dry().position - o, dry().size)
		var deep: float = minf(inner.position.x - outer.position.x, inner.position.y - outer.position.y)
		var ink := Color(LAVA, 0.8 * fade)
		_fill(_floor, outer.position, Vector2(outer.end.x, outer.position.y), Vector2(inner.end.x, inner.position.y), inner.position, ink)
		_fill(_floor, Vector2(outer.end.x, outer.position.y), outer.end, inner.end, Vector2(inner.end.x, inner.position.y), ink)
		_fill(_floor, outer.end, Vector2(outer.position.x, outer.end.y), Vector2(inner.position.x, inner.end.y), inner.end, ink)
		_fill(_floor, Vector2(outer.position.x, outer.end.y), outer.position, inner.position, Vector2(inner.position.x, inner.end.y), ink)
		# Glints on it, and its bright edge.
		for k in GLINTS:
			var along: float = fmod(float(k) * 0.618 + _clock * 0.03, 1.0)
			var into: float = fmod(float(k) * 0.381, 1.0) * deep
			var g: Vector2 = _on_band(outer, along, into)
			var shine: float = 0.5 + 0.5 * sin(_clock * 3.0 + float(k))
			_fill(_floor, g + Vector2(-4, 0), g + Vector2(0, -1.5), g + Vector2(4, 0), g + Vector2(0, 1.5),
				Color(LAVA_LIT, 0.7 * shine * fade))
		var edge := Color(LAVA_LIT, 0.8 * fade)
		_fill(_floor, inner.position, Vector2(inner.end.x, inner.position.y), Vector2(inner.end.x, inner.position.y + 2), inner.position + Vector2(0, 2), edge)
		_fill(_floor, Vector2(inner.position.x, inner.end.y - 2), Vector2(inner.end.x, inner.end.y - 2), inner.end, Vector2(inner.position.x, inner.end.y), edge)
		_fill(_floor, inner.position, inner.position + Vector2(2, 0), Vector2(inner.position.x + 2, inner.end.y), Vector2(inner.position.x, inner.end.y), edge)
		_fill(_floor, Vector2(inner.end.x - 2, inner.position.y), Vector2(inner.end.x, inner.position.y), inner.end, Vector2(inner.end.x - 2, inner.end.y), edge)


func _on_band(outer: Rect2, along: float, into: float) -> Vector2:
	# A point `into` px in from the edge, `along` the way round the room.
	var round_trip: float = 2.0 * (outer.size.x + outer.size.y)
	var d: float = along * round_trip
	if d < outer.size.x:
		return outer.position + Vector2(d, into)
	d -= outer.size.x
	if d < outer.size.y:
		return Vector2(outer.end.x - into, outer.position.y + d)
	d -= outer.size.y
	if d < outer.size.x:
		return Vector2(outer.end.x - d, outer.end.y - into)
	d -= outer.size.x
	return Vector2(outer.position.x + into, outer.end.y - d)


func _draw_air() -> void:
	var o: Vector2 = _air.global_position
	var fade: float = 1.0 if _ending < 0.0 else clampf(1.0 - _ending / END_SECONDS, 0.0, 1.0)
	# The columns of fire.
	for turn in turns:
		if not bool(turn[2]):
			continue
		var t: float = clampf((float(turn[1]) - VENT_WARN) / VENT_BURST, 0.0, 1.0)
		var m: Vector2 = vents[int(turn[0])] - o
		var tall: float = 46.0 * sin(t * PI)
		var wide: float = VENT_RADIUS * (0.6 + 0.4 * (1.0 - t))
		_fill(_air, m + Vector2(-wide, 0), m + Vector2(wide, 0), m + Vector2(wide * 0.3, -tall), m + Vector2(-wide * 0.3, -tall),
			Color(EMBER, 0.75 * (1.0 - t * 0.5) * fade))
		_fill(_air, m + Vector2(-wide * 0.5, 0), m + Vector2(wide * 0.5, 0), m + Vector2(wide * 0.1, -tall * 0.8),
			m + Vector2(-wide * 0.1, -tall * 0.8), Color(1.0, 0.95, 0.6, 0.8 * (1.0 - t * 0.5) * fade))
	# The embers.
	for ember in embers:
		var p: Vector2 = ember_at(ember) - o
		var flicker: float = 0.7 + 0.3 * sin(_clock * 12.0 + float(ember[2]) * 5.0)
		_fill(_air, p + Vector2(-7, 0), p + Vector2(0, -7), p + Vector2(7, 0), p + Vector2(0, 7), Color(EMBER, 0.25 * flicker * fade))
		_fill(_air, p + Vector2(-4, 0), p + Vector2(0, -4), p + Vector2(4, 0), p + Vector2(0, 4), Color(EMBER, 0.9 * flicker * fade))
		_fill(_air, p + Vector2(-2, 0), p + Vector2(0, -2), p + Vector2(2, 0), p + Vector2(0, 2), Color(1, 0.95, 0.7, fade))


# =============================================================================
# THE END, AND THE LAG TEST
# =============================================================================

func _end() -> void:
	"""Its boss is gone: the vents go cold, the lava ebbs, then it goes."""
	if _ending < 0.0:
		_ending = 0.0
		turns.clear()
		embers.clear()
		pools.clear()


func show_tests() -> void:
	"""The GM panel's Arena lag test: the vents, lava, columns and embers
	drawn or not (they still burn)."""
	var off: bool = LagTests.hide_arena
	if _floor != null:
		_floor.visible = not off
	if _air != null:
		_air.visible = not off
