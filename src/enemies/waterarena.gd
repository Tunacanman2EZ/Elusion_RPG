# waterarena.gd - the Water boss's arena (0.141.0): the tide, its bubbles and
# the whirlpool. The third of the six arenas from the Docs plan "Boss fights:
# arenas that fight back", pictured first (water_arena_plan.png); the owner
# chose the water drawn as a band ("Drawn band"), not painted in tiles.
#
# MADE BY THE BOSS like the Light Keeper's and the Wind boss's (bossenemy.gd
# _keep_arena(), its kit's "arena"), where lightarena.gd's wanted() says, as
# "waterarena<its shared number>". Gone with its boss.
#
# THE TIDE: the leader sends one in from a side of the room (never the same
# side twice running), with a seed. Every game then plays the same tide on its
# own clock: the side SHINES wet for TIDE_WARN, the water comes in over
# TIDE_IN to a third of the room (half in phase three), stays TIDE_HOLD, goes
# out over TIDE_OUT; the leader sends the next TIDE_REST after. In it you are
# soaked (your defence halved - StatusEffects SOAKED, renewed while you stand
# in it) and wade (StatusEffects.wade(), your walk times WADE_SCALE).
#   phase two    BUBBLES rise in the water while it stands, from the tide's
#                seed - the same bubbles on every screen. One that touches
#                you pops: a share of your health (BUBBLE_SHARE) and soaked.
#   phase three  THE WHIRLPOOL in the middle of the water: in the water it
#                pulls you toward it (a pull - walking beats it), and its
#                core drags you under (WHIRL_SHARE, at most every WHIRL_GAP).
#
# A TIDE YOU FEEL (0.144.0). The owner: "when water floods the land feels
# like nothing happens" - its soak and its slow were real and quiet. Now:
#   THE CREST    the water comes in behind a band of foam, CREST_DEPTH deep;
#                caught by it you are hit (CREST_SHARE), soaked and thrown
#                inland (once a tide).
#   THE CURRENT  in the water you are carried along it (CURRENT px/s, its way
#                from the tide's seed) - with the Wind boss here, its wind
#                carries you instead (windarena.gd, harder in the water).
#   "Soaked"     over your head as you step in; wading is StatusEffects'
#                WADE_SCALE (0.55, it was 0.7); splashes round every feet in
#                it.
#
# THE ELEMENTS MIX (0.144.0, lightarena.gd react()), with the Wind boss:
#   UPWIND   the leader sends the tide from the side the wind comes from, and
#            it comes UPWIND_DEPTH times as far ("d" with the tide).
#   RAIN     the tornado crossing the water lifts it: the leader sends "rain";
#            for RAIN_SECONDS everyone in the room is soaked, rain falls (on
#            the card, as the Ice boss's snow) and the water drains away.
# (A gust over the water throwing spray is the Wind boss's, windarena.gd.)
#
# ON THE FLOOR: drawn under everyone standing in it - its layer sorted before
# everything in the effects container (above the floor's own tiles, under the
# spikes' rings, as spikefx.gd's SORT_Y) - in quads only (one draw call for
# the run, lightarena.gd).
#
# No class_name: preload it by path.
extends Node2D

const LightArena := preload("res://src/enemies/lightarena.gd")
const QuadBatch := preload("res://src/enemies/quadbatch.gd")
const StatusEffects := preload("res://src/characters/statuseffects.gd")
const SpikeFx := preload("res://src/projectiles/spikefx.gd")
const Targets := preload("res://src/shared/targets.gd")
const HitSource := preload("res://src/shared/hitsource.gd")
const LagTests := preload("res://src/systems/lagtests.gd")
const SettingsScript := preload("res://src/systems/settings.gd")

const GROUP := &"water_arena"
const WATER := Color(0.36, 0.62, 0.96)
const FOAM := Color(1.0, 1.0, 1.0)

# THE TIDE: the sides (left, right, top, bottom); how long each part lasts;
# how far in it comes by phase (a share of the room across); how often it
# soaks you while you stand in it.
const SIDES := 4
const TIDE_WARN := 1.5
const TIDE_IN := 1.2
const TIDE_HOLD := 4.5
const TIDE_OUT := 1.2
const TIDE_REST := 1.5
const TIDE_DEPTH := [0.34, 0.34, 0.5]
const SHINE_DEPTH := 34.0
const SOAK_GAP := 0.5
# The leader's first tide this long after the arena is made.
const FIRST_TIDE := 1.0

# THE BUBBLES (phase two on): one every BUBBLE_GAP while the water stands,
# each swelling over BUBBLE_LIFE; how near counts as touching; its share.
const BUBBLE_GAP := 0.45
const BUBBLE_LIFE := 1.6
const BUBBLE_TOUCH := 10.0
const BUBBLE_SHARE := 0.05
const BUBBLE_INSET := 12.0

# THE WHIRLPOOL (phase three): how hard it pulls, its core, the share it takes
# and how often.
const WHIRL_PULL := 40.0
const WHIRL_CORE := 18.0
const WHIRL_SHARE := 0.06
const WHIRL_GAP := 1.5

# A TIDE YOU FEEL and THE ELEMENTS MIX (above).
const CREST_DEPTH := 22.0
const CREST_SHARE := 0.04
const CREST_SLIDE := 1.4
const CURRENT := 34.0
const SPLASH_LOOK := 0.25
const WIND_GROUP := &"wind_arena"
const UPWIND_DEPTH := 1.3
const TIDE_DEEPEST := 0.6
const RAIN_SECONDS := 3.0
const RAIN_DROPS := 220
const RAIN_SHADER := """
shader_type canvas_item;
uniform vec4 room;
uniform float amount = 0.0;
varying float keep;
void vertex() {
	float k = float(INSTANCE_ID);
	float x = fract(k * 0.6180339);
	float fall = fract(k * 0.3713 + TIME * 1.6);
	vec2 at = vec2(room.x + x * (room.z - room.x) + fall * 40.0, room.y + fall * (room.w - room.y));
	keep = 1.0;
	VERTEX = at + VERTEX;
}
void fragment() {
	COLOR = vec4(0.78, 0.88, 1.0, 0.7 * amount);
}
"""

# Ripples drawn on the water (half on a phone).
const RIPPLES := 50
const END_SECONDS := 1.0

var boss: Node2D = null
var phase: int = -1
# The tide now: its side (-1 none), seed, age since it was sent, and the
# depth it was sent with.
var side: int = -1
var tide_seed: int = 0
var tide_age: float = 0.0
var tide_depth: float = 0.34
# [where, born at (tide age), popped] each, for the tide now.
var bubbles: Array = []
var _next_tide: float = FIRST_TIDE
var _soak_left: float = 0.0
var _whirl_left: float = 0.0
var _crest_caught: int = -1
var _wading: bool = false
var _splashers: Array = []
var _splash_look: float = 0.0
var rain_left: float = 0.0
var _rain: MultiMeshInstance2D = null
var _rain_material: ShaderMaterial = null
var _rain_shown: float = -1.0
var _tides: int = 0
var _bubble_rng := RandomNumberGenerator.new()
var _bubbles_made: int = 0
var _zone: BulletZone = null
var _layer: Node2D = null
# Every quad of a layer, handed over in one call (quadbatch.gd).
var _quads := QuadBatch.new()
var _room: Rect2 = Rect2()
var _clock: float = 0.0
var _ending: float = -1.0


static func make(for_boss: Node2D) -> Node2D:
	if not LightArena.wanted(for_boss):
		return null
	var container: Node = for_boss.get_tree().get_first_node_in_group(&"groundeffects")
	var arena := (load("res://src/enemies/waterarena.gd") as GDScript).new() as Node2D
	arena.set(&"boss", for_boss)
	arena.name = name_for(for_boss)
	container.add_child(arena)
	return arena


static func name_for(for_boss: Node2D) -> String:
	return "waterarena%d" % maxi(int(for_boss.get(&"net_id")), 0)


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(LagTests.GROUP)
	add_to_group(LightArena.FLOOR_GROUP)
	y_sort_enabled = true
	_zone = BulletZone.find(self)
	_room = LightArena.room_of(self)
	if not _room.has_area():
		_room = Rect2(boss.global_position - Vector2(300, 300), Vector2(600, 600))
	_layer = Node2D.new()
	_layer.name = "water"
	# Sorted before everything in the container, the spikes' rings included.
	_layer.position = Vector2(0.0, SpikeFx.SORT_Y - 1.0)
	_layer.draw.connect(_quads.paint.bind(_layer, _draw_water))
	add_child(_layer)
	_layer.reset_physics_interpolation()
	_make_rain()
	show_tests()


func _make_rain() -> void:
	"""RAIN: one MultiMesh of streaks over the room, placed on the card."""
	var streak := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(-0.6, -6), Vector2(0.6, -6), Vector2(1.6, 4), Vector2(0.4, 4)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	streak.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_2D
	multi.mesh = streak
	multi.instance_count = RAIN_DROPS
	multi.visible_instance_count = (RAIN_DROPS >> 1) if SettingsScript.on_phone() else RAIN_DROPS
	multi.custom_aabb = AABB(Vector3(-1.0e6, -1.0e6, -1.0), Vector3(2.0e6, 2.0e6, 2.0))
	for k in RAIN_DROPS:
		multi.set_instance_transform_2d(k, Transform2D.IDENTITY)
	_rain_material = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = RAIN_SHADER
	_rain_material.shader = shader
	_rain = MultiMeshInstance2D.new()
	_rain.name = "rain"
	_rain.multimesh = multi
	_rain.material = _rain_material
	_rain.visible = false
	_rain.top_level = true
	_rain.z_index = 17
	_rain.z_as_relative = false
	# Placed by its shader, never moved between two buffers.
	_rain.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	RenderingServer.multimesh_set_physics_interpolated(multi.get_rid(), false)
	add_child(_rain)
	_rain.global_position = Vector2.ZERO
	_rain_material.set_shader_parameter(&"room", Vector4(_room.position.x, _room.position.y, _room.end.x, _room.end.y))


# =============================================================================
# THE TIDE
# =============================================================================

func flood() -> Rect2:
	"""The water now (an empty rect when there is none)."""
	if side < 0:
		return Rect2()
	var reach: float = _reach()
	if reach <= 0.0:
		return Rect2()
	var across: float = (_room.size.x if side < 2 else _room.size.y) * tide_depth * reach
	match side:
		0:
			return Rect2(_room.position, Vector2(across, _room.size.y))
		1:
			return Rect2(Vector2(_room.end.x - across, _room.position.y), Vector2(across, _room.size.y))
		2:
			return Rect2(_room.position, Vector2(_room.size.x, across))
	return Rect2(Vector2(_room.position.x, _room.end.y - across), Vector2(_room.size.x, across))


func takes_floor(at: Vector2) -> bool:
	"""(The floor book, lightarena.gd.) The water, and where it shines."""
	return flood().has_point(at) or shine().has_point(at)


func shine() -> Rect2:
	"""Where the next water shines wet first (an empty rect but while it
	warns)."""
	if side < 0 or tide_age >= TIDE_WARN:
		return Rect2()
	match side:
		0:
			return Rect2(_room.position, Vector2(SHINE_DEPTH, _room.size.y))
		1:
			return Rect2(Vector2(_room.end.x - SHINE_DEPTH, _room.position.y), Vector2(SHINE_DEPTH, _room.size.y))
		2:
			return Rect2(_room.position, Vector2(_room.size.x, SHINE_DEPTH))
	return Rect2(Vector2(_room.position.x, _room.end.y - SHINE_DEPTH), Vector2(_room.size.x, SHINE_DEPTH))


func _reach() -> float:
	"""How far in the water is, 0 to 1, by the tide's age."""
	var t: float = tide_age - TIDE_WARN
	if t <= 0.0:
		return 0.0
	if t < TIDE_IN:
		return t / TIDE_IN
	t -= TIDE_IN
	if t < TIDE_HOLD:
		return 1.0
	t -= TIDE_HOLD
	return clampf(1.0 - t / TIDE_OUT, 0.0, 1.0)


func standing() -> bool:
	"""The water all the way in."""
	var t: float = tide_age - TIDE_WARN - TIDE_IN
	return side >= 0 and t >= 0.0 and t < TIDE_HOLD


func tide_over() -> bool:
	return side < 0 or tide_age >= TIDE_WARN + TIDE_IN + TIDE_HOLD + TIDE_OUT


func start_tide(from_side: int, sent_seed: int, deeper: float = 1.0) -> void:
	"""A tide from `from_side`, with `sent_seed` for its bubbles - here and,
	from the leader, on every screen; `deeper` times as far (UPWIND)."""
	side = clampi(from_side, 0, SIDES - 1)
	tide_seed = sent_seed
	tide_age = 0.0
	_tides += 1
	tide_depth = minf(float(TIDE_DEPTH[clampi(phase, 0, 2)]) * clampf(deeper, 1.0, UPWIND_DEPTH), TIDE_DEEPEST)
	bubbles.clear()
	_bubbles_made = 0
	_bubble_rng.seed = sent_seed
	PerfOverlay.mark(&"tide comes")


# =============================================================================
# EACH FRAME
# =============================================================================

func _process(delta: float) -> void:
	_clock += delta
	if _ending >= 0.0:
		_ending += delta
		_layer.queue_redraw()
		if _rain != null:
			_rain.visible = false
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
	if side >= 0:
		tide_age += delta
	if not bool(boss.get(&"net_mirror")):
		_lead(delta)
		_lead_rain()
	if phase >= 1 and standing():
		_make_bubbles()
	rain_left = maxf(0.0, rain_left - delta)
	_show_rain()
	_splash_look -= delta
	if _splash_look <= 0.0:
		_splash_look = SPLASH_LOOK
		_splashers = Targets.all(get_tree()).filter(func(b: Variant) -> bool: return b is Node2D and is_instance_valid(b))
	_wet(delta)
	_layer.queue_redraw()


func _show_rain() -> void:
	var amount: float = clampf(minf(rain_left, RAIN_SECONDS - rain_left) / 0.4, 0.0, 1.0) if rain_left > 0.0 else 0.0
	_rain.visible = amount > 0.0 and not LagTests.hide_arena
	if _rain.visible and not is_equal_approx(amount, _rain_shown):
		_rain_shown = amount
		_rain_material.set_shader_parameter(&"amount", amount)


func _boss_here() -> bool:
	if not is_instance_valid(boss) or not boss.is_inside_tree():
		return false
	return not (bool(boss.get(&"_dying")) or bool(boss.get(&"_death_resolved")) or bool(boss.get(&"gated")))


func _lead(delta: float) -> void:
	"""(Leader.) The next tide once this one is out and the floor has
	rested."""
	if not tide_over():
		return
	_next_tide -= delta
	if _next_tide > 0.0:
		return
	_next_tide = LightArena.paced(self, TIDE_REST)
	var next: int = randi() % SIDES
	if next == side:
		next = (next + 1 + randi() % (SIDES - 1)) % SIDES
	var deeper: float = 1.0
	# UPWIND: with the Wind boss here, from where the wind comes, and further.
	var wind: Node = LightArena.partner(self, WIND_GROUP)
	if wind != null:
		next = upwind_side(Vector2.from_angle(float(wind.get(&"angle_to"))))
		deeper = UPWIND_DEPTH
	var sent: int = randi() % 1000000
	start_tide(next, sent, deeper)
	if deeper > 1.0:
		LightArena.react(self, _room.get_center(), "Upwind", Element.Type.WIND)
	if boss.has_method(&"arena_event"):
		boss.call(&"arena_event", {"k": "la", "h": "tide", "s": next, "n": sent, "d": snappedf(deeper, 0.01)})


static func upwind_side(blowing: Vector2) -> int:
	"""The side of the room the wind comes from: blowing right, the left."""
	if absf(blowing.x) >= absf(blowing.y):
		return 0 if blowing.x > 0.0 else 1
	return 2 if blowing.y > 0.0 else 3


func _lead_rain() -> void:
	"""(Leader.) RAIN: the Wind boss's tornado over the standing water."""
	if rain_left > 0.0 or not standing():
		return
	var wind: Node = LightArena.partner(self, WIND_GROUP)
	if wind == null:
		return
	var twister: Vector2 = wind.get(&"twister")
	if twister != Vector2.INF and flood().has_point(twister):
		start_rain(twister)
		if boss.has_method(&"arena_event"):
			boss.call(&"arena_event", {"k": "la", "h": "rain", "x": snappedf(twister.x, 0.1), "y": snappedf(twister.y, 0.1)})


func start_rain(at: Vector2) -> void:
	"""RAIN: the water lifted - it rains RAIN_SECONDS and the floor drains."""
	rain_left = RAIN_SECONDS
	if not tide_over():
		# The water goes out now.
		tide_age = maxf(tide_age, TIDE_WARN + TIDE_IN + TIDE_HOLD)
	LightArena.react(self, at, "Rain", Element.Type.WATER)


func hear(event: Dictionary) -> void:
	"""(Follower, from the leader's "la".) A tide - only what it knows."""
	if _ending >= 0.0:
		return
	match str(event.get("h", "")):
		"tide":
			start_tide(int(event.get("s", 0)), int(event.get("n", 0)), float(event.get("d", 1.0)))
		"rain":
			start_rain(Vector2(float(event.get("x", 0.0)), float(event.get("y", 0.0))))


func _make_bubbles() -> void:
	"""The tide's bubbles due by now, from its seed: the same on every
	screen."""
	var t: float = tide_age - TIDE_WARN - TIDE_IN
	var water: Rect2 = flood().grow(-BUBBLE_INSET)
	while float(_bubbles_made) * BUBBLE_GAP <= t and water.size.x > 0.0 and water.size.y > 0.0:
		var at := Vector2(water.position.x + _bubble_rng.randf() * water.size.x,
			water.position.y + _bubble_rng.randf() * water.size.y)
		bubbles.append([at, tide_age, false])
		_bubbles_made += 1


func inland() -> Vector2:
	"""The way the tide comes in."""
	match side:
		0:
			return Vector2.RIGHT
		1:
			return Vector2.LEFT
		2:
			return Vector2.DOWN
	return Vector2.UP


func coming_in() -> bool:
	var t: float = tide_age - TIDE_WARN
	return side >= 0 and t > 0.0 and t < TIDE_IN


func _from_front(at: Vector2) -> float:
	"""How far behind the water's front `at` is."""
	var water: Rect2 = flood()
	match side:
		0:
			return water.end.x - at.x
		1:
			return at.x - water.position.x
		2:
			return water.end.y - at.y
	return at.y - water.position.y


func whirlpool() -> Vector2:
	"""The whirlpool's middle, or INF: phase three, while there is water."""
	if phase < 2 or _reach() <= 0.0:
		return Vector2.INF
	return flood().get_center()


# =============================================================================
# WHAT IT DOES TO YOU
# =============================================================================

func _me() -> Node2D:
	var me: Node2D = get_tree().get_first_node_in_group(&"player") as Node2D
	if me == null or bool(me.get(&"is_dying")):
		return null
	return me


func _wet(delta: float) -> void:
	_soak_left = maxf(0.0, _soak_left - delta)
	_whirl_left = maxf(0.0, _whirl_left - delta)
	var me: Node2D = _me()
	if me == null:
		return
	var at: Vector2 = Targets.body_point(me)
	# The bubbles: a touch pops one.
	for bubble in bubbles:
		if bool(bubble[2]):
			continue
		var age: float = tide_age - float(bubble[1])
		if age >= BUBBLE_LIFE:
			bubble[2] = true
			continue
		if at.distance_to(bubble[0]) <= BUBBLE_TOUCH * (0.5 + age / BUBBLE_LIFE):
			bubble[2] = true
			_hit(me, BUBBLE_SHARE, "bubble", bubble[0])
			PerfOverlay.mark(&"bubbles pop")
	# RAIN: soaked wherever you stand in the room.
	if rain_left > 0.0 and LightArena.in_room(self, at) and _soak_left <= 0.0:
		_soak_left = SOAK_GAP
		StatusEffects.apply_to(me, StatusEffects.SOAKED, 0, Vector2.INF, true, 1.0)
	var water: Rect2 = flood()
	if water.size.x <= 0.0 or not water.has_point(at) or not LightArena.in_room(self, at):
		_wading = false
		return
	var fx: Node = StatusEffects.of(me)
	if fx != null and fx.has_method(&"wade"):
		fx.call(&"wade")
	var inward: Vector2 = inland()
	# THE CREST: caught by the front coming in - hit, soaked, thrown inland.
	if _crest_caught != _tides and coming_in() and _from_front(at) <= CREST_DEPTH:
		_crest_caught = _tides
		_hit(me, CREST_SHARE, "wave", at - inward * 20.0)
		if StatusEffects.apply_to(me, StatusEffects.SHOVE, 0, at - inward * 20.0, false, 1.0):
			StatusEffects.slide(me, CREST_SLIDE, 0.4)
	# Stepping in: soaked, and it says so.
	if not _wading or _soak_left <= 0.0:
		_soak_left = SOAK_GAP
		StatusEffects.apply_to(me, StatusEffects.SOAKED, 0, Vector2.INF, _wading, 1.0)
	_wading = true
	# THE CURRENT: carried along the water (the wind does it with the Wind boss here).
	if fx != null and fx.has_method(&"drift") and LightArena.partner(self, WIND_GROUP) == null:
		var along: Vector2 = inward.orthogonal() * (1.0 if tide_seed % 2 == 0 else -1.0)
		fx.call(&"drift", along * CURRENT)
	var pool: Vector2 = whirlpool()
	if pool == Vector2.INF:
		return
	if at.distance_to(pool) <= WHIRL_CORE:
		if _whirl_left <= 0.0:
			_whirl_left = WHIRL_GAP
			_hit(me, WHIRL_SHARE, "whirlpool", pool)
	elif fx != null and fx.has_method(&"pull"):
		fx.call(&"pull", pool, 0.15, WHIRL_PULL, get_instance_id())


func _hit(me: Node2D, share: float, what: String, from: Vector2) -> void:
	if not me.has_method(&"take_damage") or not LightArena.may_hit(me, self):
		return
	var amount: int = maxi(1, roundi(float(me.get(&"max_hp")) * share))
	HitSource.blame(HitSource.of(boss, what))
	me.call(&"take_damage", amount, Element.Type.WATER)
	StatusEffects.apply_to(me, StatusEffects.SOAKED, amount, from, false, 1.0)


# =============================================================================
# DRAWING (quads only, on the floor)
# =============================================================================

func _fill(p: Vector2, q: Vector2, r: Vector2, t: Vector2, colour: Color) -> void:
	_quads.quad(p, q, r, t, colour)


func _box(rect: Rect2, colour: Color) -> void:
	_fill(rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y), colour)


func _bar(from: Vector2, to: Vector2, width: float, colour: Color) -> void:
	var side_off: Vector2 = (to - from).orthogonal().normalized() * width * 0.5
	_fill(from - side_off, to - side_off, to + side_off, from + side_off, colour)


func _draw_water() -> void:
	var o: Vector2 = _layer.global_position
	var fade: float = 1.0 if _ending < 0.0 else clampf(1.0 - _ending / END_SECONDS, 0.0, 1.0)
	# The shine: where it comes from next, glinting.
	var wet: Rect2 = shine()
	if wet.size.x > 0.0:
		_box(Rect2(wet.position - o, wet.size), Color(0.75, 0.88, 1.0, (0.16 + 0.1 * sin(_clock * 6.0)) * fade))
		for k in 12:
			var g := Vector2(wet.position.x + fmod(float(k) * 0.37 + _clock * 0.4, 1.0) * wet.size.x,
				wet.position.y + fmod(float(k) * 0.61, 1.0) * wet.size.y) - o
			_bar(g - Vector2(4, 0), g + Vector2(4, 0), 1.0, Color(FOAM, 0.6 * fade))
	var water: Rect2 = flood()
	if water.size.x <= 0.0 or water.size.y <= 0.0:
		return
	var local := Rect2(water.position - o, water.size)
	_box(local, Color(WATER, 0.38 * fade))
	var count: int = (RIPPLES >> 1) if SettingsScript.on_phone() else RIPPLES
	for k in count:
		var x: float = local.position.x + fmod(float(k) * 0.618 + _clock * 0.05, 1.0) * local.size.x
		var y: float = local.position.y + fmod(float(k) * 0.381, 1.0) * local.size.y
		var w: float = 6.0 + 6.0 * fmod(float(k) * 0.77, 1.0)
		_bar(Vector2(x - w, y), Vector2(x + w, y + sin(_clock * 3.0 + float(k)) * 1.5), 1.0,
			Color(0.8, 0.92, 1.0, 0.35 * fade))
	# Foam along its edge in the room.
	var along_y: bool = side < 2
	var edge: float = 0.0
	match side:
		0:
			edge = local.end.x
		1:
			edge = local.position.x
		2:
			edge = local.end.y
		_:
			edge = local.position.y
	var span: float = local.size.y if along_y else local.size.x
	var start: float = local.position.y if along_y else local.position.x
	# THE CREST: coming in, a deep band of foam at its front.
	if coming_in():
		var back: float = -CREST_DEPTH if side == 0 or side == 2 else CREST_DEPTH
		for k in 18:
			var a0: float = start + float(k) / 18.0 * span
			var a1: float = start + float(k + 1) / 18.0 * span
			var lip: float = sin(_clock * 9.0 + float(k) * 1.3) * 3.0
			if along_y:
				_fill(Vector2(edge + back, a0), Vector2(edge + lip, a0), Vector2(edge + lip, a1), Vector2(edge + back, a1), Color(FOAM, 0.55 * fade))
			else:
				_fill(Vector2(a0, edge + back), Vector2(a1, edge + back), Vector2(a1, edge + lip), Vector2(a0, edge + lip), Color(FOAM, 0.55 * fade))
	# Splashes round every feet in it.
	for body in _splashers:
		if not is_instance_valid(body):
			continue
		var feet: Vector2 = Targets.body_point(body)
		if not water.has_point(feet):
			continue
		var f: Vector2 = feet - o
		for ring in 2:
			var grow: float = fmod(_clock * 1.6 + float(ring) * 0.5, 1.0)
			_quads.band(f, 6.0 + 12.0 * grow, (6.0 + 12.0 * grow) * 0.5, 0.8, Color(FOAM, 0.6 * (1.0 - grow) * fade))
	for k in 28:
		var a: float = start + (float(k) + fmod(_clock * 0.8, 1.0)) / 28.0 * span
		if along_y:
			_bar(Vector2(edge - 2.0, a), Vector2(edge + 2.0, a + 5.0), 2.0, Color(FOAM, 0.75 * fade))
		else:
			_bar(Vector2(a, edge - 2.0), Vector2(a + 5.0, edge + 2.0), 2.0, Color(FOAM, 0.75 * fade))
	# The bubbles, swelling.
	for bubble in bubbles:
		if bool(bubble[2]):
			continue
		var grow: float = clampf((tide_age - float(bubble[1])) / BUBBLE_LIFE, 0.0, 1.0)
		var c: Vector2 = (bubble[0] as Vector2) - o
		var r: float = 3.0 + 6.0 * grow
		for s in 10:
			_bar(c + Vector2.from_angle(float(s) * TAU / 10.0) * r, c + Vector2.from_angle(float(s + 1) * TAU / 10.0) * r,
				1.5, Color(0.85, 0.95, 1.0, 0.8 * fade))
		var shine_at: Vector2 = c + Vector2(-2.0, -2.0) * grow
		_fill(shine_at + Vector2(-1.5, 0), shine_at + Vector2(0, -1.5), shine_at + Vector2(1.5, 0), shine_at + Vector2(0, 1.5),
			Color(FOAM, 0.9 * fade))
	# The whirlpool.
	var pool: Vector2 = whirlpool()
	if pool != Vector2.INF:
		var m: Vector2 = pool - o
		for arm in 4:
			var last: Vector2 = m
			for q in 26:
				var r: float = 4.0 + float(q) * 2.3
				var ang: float = -_clock * 3.0 + float(arm) * TAU / 4.0 + float(q) * 0.28
				var next: Vector2 = m + Vector2(cos(ang) * r, sin(ang) * r * 0.55)
				if q > 0:
					_bar(last, next, 2.0, Color(0.85, 0.95, 1.0, 0.7 * fade))
				last = next
		_fill(m + Vector2(-8, 0), m + Vector2(0, -5), m + Vector2(8, 0), m + Vector2(0, 5), Color(0.05, 0.12, 0.3, 0.7 * fade))


# =============================================================================
# THE END, AND THE LAG TEST
# =============================================================================

func _end() -> void:
	"""Its boss is gone: the water drains away, then it goes."""
	if _ending < 0.0:
		_ending = 0.0
		bubbles.clear()


func show_tests() -> void:
	"""The GM panel's Arena lag test: the water drawn or not (it still soaks
	and slows you)."""
	if _layer != null:
		_layer.visible = not LagTests.hide_arena
