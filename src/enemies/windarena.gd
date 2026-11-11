# windarena.gd - the Wind boss's arena (0.140.0): the crosswind and its
# windbreaks, gust lanes and the tornado. The second of the six arenas from
# the Docs plan "Boss fights: arenas that fight back", pictured first
# (wind_arena_plan.png); of the windbreaks the owner chose "Wind only": they
# stop the wind and walking, never an orb.
#
# MADE BY THE BOSS like the Light Keeper's (bossenemy.gd _keep_arena(), its
# kit's "arena"), where lightarena.gd's wanted() says, as
# "windarena<its shared number>" in the area's effects container. Gone with
# its boss.
#
# THREE STEPS, by the boss's phase:
#   one    THE CROSSWIND: a wind across the room, turned by the leader every
#          WIND_TURN (one of eight ways, never the same twice) and eased round
#          over WIND_SWING. Streaks show it, an arrow over the boss points it.
#          It carries you (StatusEffects.drift(), WIND_DRIFT - never as fast
#          as walking) and bends every orb in flight (BulletField.wind,
#          ORB_BEND). TWO WINDBREAKS - pairs of the crypt's pillars, solid to
#          walking (the walls layer), never to orbs - leave calm air behind
#          them (sheltered()), so they are places to stand.
#   two    and GUST LANES: the leader lays a lane along the wind through each
#          player in the fight; it thickens for GUST_WARN, then blows - in it,
#          a share of your health (GUST_SHARE) and a slide along the wind.
#   three  and THE TORNADO: it forms in the room's middle and wanders where
#          the leader sends it, pulling you in within TWISTER_REACH (a pull:
#          walking beats it), flinging you out of its core, and carrying the
#          orbs round it (BulletField swirl).
#
# THE SAME ON EVERY SCREEN: the windbreaks stand where the room says; the
# wind's way, each gust and the tornado's course are the leader's, sent as
# world events ("la", monstersync.gd -> the boss's net_arena() -> hear()), and
# each game moves and hurts only its own player.
#
# DRAWN IN QUADS ONLY (draw_primitive), on one layer over everything standing:
# Godot draws a run of them in one call (lightarena.gd, zz/light/drawbench).
#
# No class_name: preload it by path.
extends Node2D

const LightArena := preload("res://src/enemies/lightarena.gd")
const StatusEffects := preload("res://src/characters/statuseffects.gd")
const SpikeFx := preload("res://src/projectiles/spikefx.gd")
const BossProjectile := preload("res://src/projectiles/bossprojectile.gd")
const Targets := preload("res://src/shared/targets.gd")
const HitSource := preload("res://src/shared/hitsource.gd")
const LagTests := preload("res://src/systems/lagtests.gd")
const SettingsScript := preload("res://src/systems/settings.gd")

const GROUP := &"wind_arena"
const MINT := Color(0.654902, 0.9529412, 0.8156863)

# THE WINDBREAKS: where each stands from the room's middle (clear of the
# gauntlet's gates and the dirt's candelabras), its two pillars this far
# either side, and the calm behind it: this long down the wind, this wide
# across (narrowing a little with distance).
const BREAK_SPOTS := [Vector2(-95, 40), Vector2(85, -55)]
const BREAK_GAP := 10.0
const LEE_LONG := 80.0
const LEE_HALF := 24.0
const LEE_NARROWS := 0.12
const PILLAR_SCENE := "res://scene/crypt/pillar.tscn"
# The walls layer (a boss gate's bars): the player and monsters mask it; the
# bullets' walls are built from layer 1, so an orb passes.
const BODY_LAYER := 2
const PILLAR_ROOM := 12.0
const PILLAR_LOOK := 0.5

# THE CROSSWIND: how often it turns, how long it takes to come round, how hard
# it carries you by phase (px/s), how hard it bends an orb (px/s each
# second), how many streaks show it (half on a phone), how fast they run.
const WIND_TURN := 10.0
const WIND_SWING := 1.2
const WIND_DRIFT := [26.0, 32.0, 38.0]
const ORB_BEND := 40.0
const STREAKS := 120
const STREAK_RUN := 0.55

# THE GUST LANES, by phase how often (0 none); the warning, how long the blow
# is drawn, the lane's half width and half length, the share of your health,
# and the slide (times a shove, seconds).
const GUST_GAP := [0.0, 4.0, 3.0]
const GUST_WARN := 0.9
const GUST_BLOW := 0.35
const GUST_HALF := 16.0
const GUST_LONG := 220.0
const GUST_SHARE := 0.05
const GUST_SLIDE := 1.6
const GUST_SLIDE_SECONDS := 0.5

# THE TORNADO: how often the leader sends it somewhere new, how fast it goes,
# how far it pulls and how hard, its core, the share of your health a fling
# takes, the fling's slide, at most one fling this often; how fast it turns
# the orbs round it.
const TWISTER_RETARGET := 2.5
const TWISTER_SPEED := 45.0
const TWISTER_REACH := 95.0
const TWISTER_PULL := 40.0
const TWISTER_CORE := 16.0
const TWISTER_SHARE := 0.06
const TWISTER_FLING := 2.0
const TWISTER_FLING_SECONDS := 0.6
const TWISTER_GAP := 1.5
const SWIRL_RATE := 2.2
# Furthest from its boss anything the leader sends may be put.
const EVENT_REACH := 1200.0

const DRAW_Z := 17
const END_SECONDS := 0.8

var boss: Node2D = null
var phase: int = -1
# The wind's way now (radians) and where it is turning to.
var angle: float = 0.0
var angle_to: float = 0.0
# [pillar, pillar] a windbreak, or [] until there is room for it.
var breaks: Array = []
# [middle, angle, age, blown] each.
var gusts: Array = []
var twister: Vector2 = Vector2.INF
var twister_to: Vector2 = Vector2.INF
var _turn_clock: float = 0.0
var _gust_clock: float = 0.0
var _twister_clock: float = 0.0
var _fling_left: float = 0.0
var _pillar_clock: float = 0.0
var _zone: BulletZone = null
var _layer: Node2D = null
var _middle: Vector2 = Vector2.ZERO
var _room: Rect2 = Rect2()
var _clock: float = 0.0
var _ending: float = -1.0
var _fade: float = 0.0


static func make(for_boss: Node2D) -> Node2D:
	if not LightArena.wanted(for_boss):
		return null
	var container: Node = for_boss.get_tree().get_first_node_in_group(&"groundeffects")
	var arena := (load("res://src/enemies/windarena.gd") as GDScript).new() as Node2D
	arena.set(&"boss", for_boss)
	arena.name = name_for(for_boss)
	container.add_child(arena)
	return arena


static func name_for(for_boss: Node2D) -> String:
	return "windarena%d" % maxi(int(for_boss.get(&"net_id")), 0)


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(LagTests.GROUP)
	y_sort_enabled = true
	_zone = BulletZone.find(self)
	_middle = boss.global_position
	_room = Rect2(_middle - Vector2(300, 300), Vector2(600, 600))
	var room: Rect2 = LightArena.room_of(self)
	if room.has_area():
		_middle = room.get_center()
		_room = room
	_layer = Node2D.new()
	_layer.name = "wind"
	_layer.z_index = DRAW_Z
	_layer.z_as_relative = false
	_layer.draw.connect(_draw_wind)
	add_child(_layer)
	for k in BREAK_SPOTS.size():
		breaks.append([])
	_place_pillars()
	show_tests()


# =============================================================================
# THE WINDBREAKS
# =============================================================================

func _place_pillars() -> void:
	"""Each windbreak whose spot is clear of walls, bodies and players now;
	the rest are looked at again in a moment."""
	var scene: PackedScene = load(PILLAR_SCENE) as PackedScene
	if scene == null:
		return
	for k in BREAK_SPOTS.size():
		if not (breaks[k] as Array).is_empty():
			continue
		var at: Vector2 = _middle + BREAK_SPOTS[k]
		var both: Array = [at + Vector2(-BREAK_GAP, 0), at + Vector2(BREAK_GAP, 0)]
		if not (_clear(both[0]) and _clear(both[1])):
			continue
		var pair: Array = []
		for spot in both:
			var pillar: Node2D = scene.instantiate() as Node2D
			pillar.name = "pillar%d%s" % [k, "a" if pair.is_empty() else "b"]
			var body: CollisionObject2D = pillar.get_node_or_null(^"body") as CollisionObject2D
			if body != null:
				body.collision_layer = BODY_LAYER
				body.collision_mask = 0
			add_child(pillar)
			pillar.global_position = spot
			pillar.reset_physics_interpolation()
			pair.append(pillar)
		breaks[k] = pair
		_puff(at)


func _clear(spot: Vector2) -> bool:
	if _zone != null and (not _zone.field.bounds.has_point(spot) or _zone.field.is_wall(spot)):
		return false
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	if space == null:
		return true
	var circle := CircleShape2D.new()
	circle.radius = PILLAR_ROOM
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.transform = Transform2D(0.0, spot + Vector2(0, -6))
	query.collide_with_bodies = true
	return space.intersect_shape(query, 1).is_empty()


func _puff(at: Vector2) -> void:
	var fx: Node2D = SpikeFx.of(get_parent())
	if fx != null and BossProjectile.ELEMENT_SPARKS.has(Element.Type.WIND):
		fx.call(&"burst", at + Vector2(0, -12), Element.Type.WIND, Vector2(BREAK_GAP + 8.0, 10.0),
			BossProjectile.ELEMENT_SPARKS[Element.Type.WIND])


func standing() -> int:
	"""How many windbreaks stand."""
	var n: int = 0
	for pair in breaks:
		if not (pair as Array).is_empty():
			n += 1
	return n


func sheltered(at: Vector2) -> bool:
	"""In the calm behind a windbreak."""
	var way: Vector2 = Vector2.from_angle(angle)
	for k in breaks.size():
		if (breaks[k] as Array).is_empty():
			continue
		var back: Vector2 = at - (_middle + BREAK_SPOTS[k])
		var along: float = back.dot(way)
		if along <= 0.0 or along >= LEE_LONG:
			continue
		if absf(back.dot(way.orthogonal())) < LEE_HALF - along * LEE_NARROWS:
			return true
	return false


# =============================================================================
# EACH FRAME
# =============================================================================

func _process(delta: float) -> void:
	_clock += delta
	if _ending >= 0.0:
		_end_step(delta)
		return
	if not _boss_here():
		_end()
		return
	_fade = minf(1.0, _fade + delta)
	var now: int = int(boss.call(&"_current_phase"))
	if now != phase:
		_to_phase(now)
	if name != name_for(boss):
		name = name_for(boss)
	var leader: bool = not bool(boss.get(&"net_mirror"))
	_pillar_clock -= delta
	if _pillar_clock <= 0.0:
		_pillar_clock = PILLAR_LOOK
		if standing() < breaks.size():
			_place_pillars()
	if leader:
		_lead(delta)
	angle = rotate_toward(angle, angle_to, PI / WIND_SWING * delta)
	var way: Vector2 = Vector2.from_angle(angle)
	if _zone != null:
		_zone.field.wind = way * ORB_BEND
	_carry(way)
	_age_gusts(delta)
	_move_twister(delta)
	_layer.queue_redraw()


func _boss_here() -> bool:
	if not is_instance_valid(boss) or not boss.is_inside_tree():
		return false
	return not (bool(boss.get(&"_dying")) or bool(boss.get(&"_death_resolved")) or bool(boss.get(&"gated")))


func _to_phase(now: int) -> void:
	phase = now
	_gust_clock = 0.8
	if phase >= 2 and twister == Vector2.INF:
		twister = _middle
		twister_to = _middle
		_twister_clock = 0.0
		PerfOverlay.mark(&"tornado forms")
	elif phase < 2:
		twister = Vector2.INF
		if _zone != null:
			_zone.field.swirl_radius = 0.0


func _lead(delta: float) -> void:
	"""(Leader.) The wind's turns, the gusts and the tornado's course, for
	every screen."""
	_turn_clock -= delta
	if _turn_clock <= 0.0:
		_turn_clock = WIND_TURN
		var ways: int = 8
		var was: int = posmod(roundi(angle_to / (TAU / ways)), ways)
		var next: int = (was + 1 + randi() % (ways - 1)) % ways
		var a: float = float(next) * TAU / ways
		hear_wind(a)
		_send({"h": "wind", "a": snappedf(a, 0.0001)})
	var gap: float = float(GUST_GAP[clampi(phase, 0, 2)])
	if gap > 0.0:
		_gust_clock -= delta
		if _gust_clock <= 0.0:
			_gust_clock = gap
			for body in boss.call(&"fight_targets"):
				var through: Vector2 = Targets.body_point(body)
				add_gust(through, angle_to)
				_send({"h": "gust", "x": snappedf(through.x, 0.1), "y": snappedf(through.y, 0.1),
					"a": snappedf(angle_to, 0.0001)})
	if twister != Vector2.INF:
		_twister_clock -= delta
		if _twister_clock <= 0.0:
			_twister_clock = TWISTER_RETARGET
			var to: Vector2 = _middle
			var bodies: Array = boss.call(&"fight_targets")
			if not bodies.is_empty():
				to = Targets.body_point(bodies[randi() % bodies.size()])
			to = (to + Vector2.from_angle(randf() * TAU) * randf_range(20.0, 70.0)).clamp(_room.position, _room.end)
			twister_to = to
			_send({"h": "twister", "x": snappedf(to.x, 0.1), "y": snappedf(to.y, 0.1)})


func _send(event: Dictionary) -> void:
	event["k"] = "la"
	if boss.has_method(&"arena_event"):
		boss.call(&"arena_event", event)


func hear(event: Dictionary) -> void:
	"""(Follower, from the leader's "la".) Only what it knows, and only near
	its boss."""
	if _ending >= 0.0:
		return
	var at := Vector2(float(event.get("x", 0.0)), float(event.get("y", 0.0)))
	match str(event.get("h", "")):
		"wind":
			hear_wind(float(event.get("a", 0.0)))
		"gust":
			if at.distance_to(boss.global_position) <= EVENT_REACH:
				add_gust(at, float(event.get("a", 0.0)))
		"twister":
			if at.distance_to(boss.global_position) <= EVENT_REACH:
				twister_to = at.clamp(_room.position, _room.end)


func hear_wind(a: float) -> void:
	angle_to = wrapf(a, -PI, PI)
	PerfOverlay.mark(&"wind turns")


# =============================================================================
# WHAT IT DOES TO YOU
# =============================================================================

func _me() -> Node2D:
	var me: Node2D = get_tree().get_first_node_in_group(&"player") as Node2D
	if me == null or bool(me.get(&"is_dying")):
		return null
	return me


func _carry(way: Vector2) -> void:
	"""This game's player, out of the calm, carried by the wind."""
	var me: Node2D = _me()
	if me == null or phase < 0:
		return
	var at: Vector2 = Targets.body_point(me)
	if not LightArena.in_room(self, at) or sheltered(at):
		return
	var fx: Node = StatusEffects.of(me)
	if fx != null and fx.has_method(&"drift"):
		fx.call(&"drift", way * float(WIND_DRIFT[clampi(phase, 0, 2)]))


func add_gust(through: Vector2, a: float) -> void:
	gusts.append([through, a, 0.0, false])


func in_gust(gust: Array, at: Vector2) -> bool:
	var way: Vector2 = Vector2.from_angle(float(gust[1]))
	var off: Vector2 = at - (gust[0] as Vector2)
	return absf(off.dot(way)) <= GUST_LONG and absf(off.dot(way.orthogonal())) <= GUST_HALF


func _age_gusts(delta: float) -> void:
	var i: int = 0
	while i < gusts.size():
		var gust: Array = gusts[i]
		gust[2] = float(gust[2]) + delta
		if not bool(gust[3]) and float(gust[2]) >= GUST_WARN:
			gust[3] = true
			_blow(gust)
		if float(gust[2]) >= GUST_WARN + GUST_BLOW:
			gusts.remove_at(i)
			continue
		i += 1


func _blow(gust: Array) -> void:
	PerfOverlay.mark(&"gusts blow")
	var me: Node2D = _me()
	if me == null or not me.has_method(&"take_damage"):
		return
	var at: Vector2 = Targets.body_point(me)
	if not in_gust(gust, at):
		return
	var way: Vector2 = Vector2.from_angle(float(gust[1]))
	var amount: int = maxi(1, roundi(float(me.get(&"max_hp")) * GUST_SHARE))
	HitSource.blame(HitSource.of(boss, "gust"))
	me.call(&"take_damage", amount, Element.Type.WIND)
	if StatusEffects.apply_to(me, StatusEffects.SHOVE, 0, at - way * 20.0, false, 1.0):
		StatusEffects.slide(me, GUST_SLIDE, GUST_SLIDE_SECONDS)


func _move_twister(delta: float) -> void:
	if twister == Vector2.INF:
		return
	twister = twister.move_toward(twister_to, TWISTER_SPEED * delta)
	if _zone != null:
		_zone.field.swirl_at = twister
		_zone.field.swirl_radius = TWISTER_REACH
		_zone.field.swirl_rate = SWIRL_RATE
	_fling_left = maxf(0.0, _fling_left - delta)
	var me: Node2D = _me()
	if me == null:
		return
	var at: Vector2 = Targets.body_point(me)
	var gap: float = at.distance_to(twister)
	if gap > TWISTER_REACH:
		return
	if gap <= TWISTER_CORE and _fling_left <= 0.0 and me.has_method(&"take_damage"):
		_fling_left = TWISTER_GAP
		var amount: int = maxi(1, roundi(float(me.get(&"max_hp")) * TWISTER_SHARE))
		HitSource.blame(HitSource.of(boss, "tornado"))
		me.call(&"take_damage", amount, Element.Type.WIND)
		if StatusEffects.apply_to(me, StatusEffects.SHOVE, 0, twister, false, 1.0):
			StatusEffects.slide(me, TWISTER_FLING, TWISTER_FLING_SECONDS)
		return
	var fx: Node = StatusEffects.of(me)
	if fx != null and fx.has_method(&"pull"):
		fx.call(&"pull", twister, 0.15, TWISTER_PULL)


# =============================================================================
# DRAWING (quads only)
# =============================================================================

func _fill(p: Vector2, q: Vector2, r: Vector2, t: Vector2, colour: Color) -> void:
	_layer.draw_primitive(PackedVector2Array([p, q, r, t]), PackedColorArray([colour]), PackedVector2Array())


func _bar(from: Vector2, to: Vector2, width: float, colour: Color) -> void:
	var side: Vector2 = (to - from).orthogonal().normalized() * width * 0.5
	_fill(from - side, to - side, to + side, from + side, colour)


func _draw_wind() -> void:
	var way: Vector2 = Vector2.from_angle(angle)
	var across: Vector2 = way.orthogonal()
	var fade: float = _fade if _ending < 0.0 else clampf(1.0 - _ending / END_SECONDS, 0.0, 1.0)
	var origin: Vector2 = _layer.global_position
	# The streaks: none in a windbreak's calm.
	var count: int = (STREAKS >> 1) if SettingsScript.on_phone() else STREAKS
	var span: float = _room.size.length()
	var middle: Vector2 = _room.get_center()
	for k in count:
		var lane: float = fmod(float(k) * 0.6180339, 1.0)
		var run: float = fmod(float(k) * 0.3713 + _clock * STREAK_RUN, 1.0)
		var at: Vector2 = middle + across * (lane - 0.5) * span + way * (run - 0.5) * span
		if not _room.has_point(at) or sheltered(at):
			continue
		var long: float = 18.0 + 18.0 * fmod(float(k) * 0.77, 1.0)
		_bar(at - origin, at + way * long - origin, 1.0, Color(MINT, 0.38 * fade))
	# The arrow over the boss.
	if is_instance_valid(boss):
		var head: Vector2 = boss.global_position + Vector2(0, -52) - origin
		var tip: Vector2 = head + way * 12.0
		var ink := Color(MINT, 0.9 * fade)
		_bar(head - way * 12.0, tip, 2.0, ink)
		_bar(tip, tip - way.rotated(0.6) * 6.0, 2.0, ink)
		_bar(tip, tip - way.rotated(-0.6) * 6.0, 2.0, ink)
	# The gust lanes, thickening, then blowing.
	for gust in gusts:
		var g_way: Vector2 = Vector2.from_angle(float(gust[1]))
		var g_across: Vector2 = g_way.orthogonal() * GUST_HALF
		var ends: Array = _clip(gust[0] as Vector2, g_way)
		if ends.is_empty():
			continue
		var a: Vector2 = (ends[0] as Vector2) - origin
		var b: Vector2 = (ends[1] as Vector2) - origin
		var grow: float = clampf(float(gust[2]) / GUST_WARN, 0.0, 1.0)
		var blowing: bool = bool(gust[3])
		_fill(a - g_across, b - g_across, b + g_across, a + g_across,
			Color(MINT, (0.32 if blowing else 0.06 + 0.14 * grow) * fade))
		_bar(a - g_across, b - g_across, 1.0, Color(MINT, (0.3 + 0.5 * grow) * fade))
		_bar(a + g_across, b + g_across, 1.0, Color(MINT, (0.3 + 0.5 * grow) * fade))
		for k in 16:
			var f: float = fmod(float(k) * 0.37 + _clock * (3.0 if blowing else 1.6), 1.0)
			var off: float = (fmod(float(k) * 0.618, 1.0) - 0.5) * 1.6
			var p: Vector2 = a.lerp(b, f) + g_across * off
			_bar(p, p + g_way * 26.0, 2.0, Color(1, 1, 1, (0.35 + 0.4 * grow) * fade))
	# The tornado: its reach on the floor, then a funnel of turning rings.
	if twister != Vector2.INF:
		var foot: Vector2 = twister - origin
		for s in 32:
			var a0: float = float(s) * TAU / 32.0
			_bar(foot + Vector2.from_angle(a0) * TWISTER_REACH, foot + Vector2.from_angle(a0 + TAU / 32.0) * TWISTER_REACH,
				1.0, Color(MINT, 0.18 * fade))
		_fill(foot + Vector2(-14, 0), foot + Vector2(0, -5), foot + Vector2(14, 0), foot + Vector2(0, 5),
			Color(0, 0, 0, 0.25 * fade))
		for i in 13:
			var rx: float = 6.0 + float(i) * 3.4
			var c: Vector2 = foot + Vector2(sin(_clock * 3.0 + float(i) * 0.5) * float(i) * 0.9, -float(i) * 7.0)
			var spin: float = _clock * 7.0 + float(i) * 0.9
			var ink := Color(0.88, 0.98, 0.94, (0.85 - float(i) * 0.03) * fade)
			for arm in 3:
				var from: float = spin + float(arm) * TAU / 3.0
				var last: Vector2 = c + Vector2(cos(from) * rx, sin(from) * rx * 0.32)
				for q in range(1, 7):
					var ang: float = from + float(q) * 0.25
					var next: Vector2 = c + Vector2(cos(ang) * rx, sin(ang) * rx * 0.32)
					_bar(last, next, 2.0, ink)
					last = next


func _clip(through: Vector2, way: Vector2) -> Array:
	"""A gust's lane from GUST_LONG back to GUST_LONG on, cut to the room."""
	var a: Vector2 = through - way * GUST_LONG
	var b: Vector2 = through + way * GUST_LONG
	var t0: float = 0.0
	var t1: float = 1.0
	var d: Vector2 = b - a
	for axis in 2:
		var lo: float = _room.position[axis]
		var hi: float = _room.end[axis]
		if absf(d[axis]) < 0.0001:
			if a[axis] < lo or a[axis] > hi:
				return []
			continue
		var u0: float = (lo - a[axis]) / d[axis]
		var u1: float = (hi - a[axis]) / d[axis]
		t0 = maxf(t0, minf(u0, u1))
		t1 = minf(t1, maxf(u0, u1))
	if t0 >= t1:
		return []
	return [a + d * t0, a + d * t1]


# =============================================================================
# THE END, AND THE LAG TEST
# =============================================================================

func _end() -> void:
	"""Its boss is gone: the wind drops, the windbreaks crumble, then it goes."""
	if _ending >= 0.0:
		return
	_ending = 0.0
	gusts.clear()
	twister = Vector2.INF
	if _zone != null:
		_zone.field.wind = Vector2.ZERO
		_zone.field.swirl_radius = 0.0
	for k in breaks.size():
		var pair: Array = breaks[k]
		if pair.is_empty():
			continue
		_puff(_middle + BREAK_SPOTS[k])
		for pillar in pair:
			(pillar as Node).queue_free()
		breaks[k] = []


func _end_step(delta: float) -> void:
	_ending += delta
	_layer.queue_redraw()
	if _ending >= END_SECONDS:
		queue_free()


func _exit_tree() -> void:
	# Freed with its area or its boss: the bullets' wind goes with it.
	if _zone != null and is_instance_valid(_zone):
		_zone.field.wind = Vector2.ZERO
		_zone.field.swirl_radius = 0.0


func show_tests() -> void:
	"""The GM panel's Arena lag test: the wind's streaks, lanes and tornado
	drawn or not (the windbreaks are the crypt's own art, and still stand)."""
	if _layer != null:
		_layer.visible = not LagTests.hide_arena
