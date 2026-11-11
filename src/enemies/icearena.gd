# icearena.gd - the Ice boss's arena (0.142.0): slick frost, walls of ice,
# hail and the blizzard. The fourth of the six arenas from the Docs plan
# "Boss fights: arenas that fight back". The owner: "next boss".
#
# MADE BY THE BOSS like the others (bossenemy.gd _keep_arena(), its kit's
# "arena"), where lightarena.gd's wanted() says, in the room lightarena.gd's
# room_of() says (never the Endless's corridor), as "icearena<its shared
# number>". Gone with its boss.
#
#   one    FROST: the leader lays a patch near a player in the fight every
#          FROST_GAP. It forms over FROST_FORM, then lies FROST_LIFE. On it you
#          skid - your walk comes round slowly (GRIP), the difference a drift
#          (StatusEffects.drift(), up to SKID_MOST) - and are chilled (as
#          ground: never to freezing).
#          WALLS OF ICE: every WALL_GAP the leader raises a short wall behind a
#          player, across the line from the boss, so backing away meets ice.
#          A line of frost warns (WALL_WARN), the wall rises, stands
#          WALL_LIFE and shatters. It stops walking (the walls layer) and orbs
#          (BulletZone.paint_solid()). WALL_HITS blows of yours break it
#          sooner - a door - and every game hears it as a lever pull, as the
#          Light Keeper's mirrors do.
#   two    and HAIL: a shadow grows near each player for HAIL_WARN, the stone
#          lands - within HAIL_RADIUS, HAIL_SHARE of your health as ice and
#          chilled.
#   three  and THE BLIZZARD: snow blows across the room and a white fog
#          closes in round the screen's edges (a CanvasLayer under the
#          dazzle's), and the frost comes faster.
#
# THE SAME ON EVERY SCREEN: every patch, wall and stone is the leader's, sent
# as "la" world events (monstersync.gd -> the boss's net_arena() -> hear());
# each game hurts and skids only its own player.
#
# DRAWN IN QUADS ONLY: the frost, warnings and shadows on the floor (sorted
# before everything, as the Water boss's tide), the walls among everyone, the
# snow over everything, the fog in one rect.
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
const SettingsScript := preload("res://src/systems/settings.gd")

const GROUP := &"ice_arena"
const FROST_INK := Color(0.82, 0.93, 1.0)
const ICE := Color(0.62, 0.86, 1.0)

# FROST, by phase: how often the leader lays a patch, its radius; how long it
# takes to form, how long it lies, the most at once; how slowly your walk
# comes round on it (higher grips sooner), the most a skid carries you, how
# often it chills.
const FROST_GAP := [5.0, 4.0, 2.5]
const FROST_RADIUS := [40.0, 44.0, 52.0]
const FROST_FORM := 0.8
const FROST_LIFE := 12.0
const FROST_MOST := 6
const FROST_NEAR := Vector2(20.0, 60.0)
const GRIP := 3.0
const SKID_MOST := 160.0
const CHILL_GAP := 1.0

# THE WALLS: how often (by phase), how far behind the player, its blocks and
# their size, the warning, the rise, how long it stands, how many of your
# blows break it, how many wall names go round (the levers' book on the
# server holds 32 names an area).
const WALL_GAP := [6.0, 5.0, 4.0]
const WALL_BEHIND := 45.0
const WALL_BLOCKS := 5
const BLOCK := 16.0
const WALL_THICK := 10.0
const WALL_HIGH := 22.0
const WALL_WARN := 0.7
const WALL_RISE := 0.3
const WALL_LIFE := 6.0
const WALL_HITS := 3
const WALL_NAMES := 10
# Spots a frost tries before it waits (the floor book, lightarena.gd).
const TRIES := 4
const BODY_LAYER := 2
const HURT_LAYER := 8
const STRESS_MARK := &"stress_copy"

# HAIL, by phase how often (0 none); the warning, its reach, its share.
const HAIL_GAP := [0.0, 2.0, 1.4]
const HAIL_WARN := 0.9
const HAIL_RADIUS := 18.0
const HAIL_NEAR := 40.0
const HAIL_SHARE := 0.05

# THE BLIZZARD: how long it takes to close in, the snow (half on a phone),
# and the fog: the clear middle and the thickest at the edges (shares of the
# screen's height from its middle), its layer (under the dazzle's 40).
const BLIZZARD_IN := 2.0
const SNOW := 140
const FOG_CLEAR := 0.32
const FOG_EDGE := 0.62
const FOG_THICK := 0.72
const FOG_Z := 30
const FOG_REACH := 1600.0
# Furthest from its boss anything the leader sends may be put.
const EVENT_REACH := 1200.0
const SNOW_Z := 17
const END_SECONDS := 0.8

# THE SNOW ON THE CARD (0.143.0, the refinement): the blizzard's SNOW flakes
# are one MultiMesh, each flake placed by its shader from its own number and
# the clock - the sums _draw_snow() did for 140 flakes every frame - so the
# processor does nothing for them. A phone shows half (visible_instance_count).
const SNOW_SHADER := """
shader_type canvas_item;
uniform vec2 middle;
uniform vec2 way;
uniform float span;
uniform vec4 room;
uniform float amount = 0.0;
varying float keep;
void vertex() {
	float k = float(INSTANCE_ID);
	float lane = fract(k * 0.6180339);
	float run = fract(k * 0.3713 + TIME * 0.35);
	vec2 across = vec2(way.y, -way.x);
	vec2 at = middle + across * (lane - 0.5) * span + way * (run - 0.5) * span;
	keep = (at.x >= room.x && at.y >= room.y && at.x <= room.z && at.y <= room.w) ? 1.0 : 0.0;
	float size = 1.0 + fract(k * 0.77) * 1.5;
	VERTEX = at + VERTEX * size * keep;
}
void fragment() {
	COLOR = vec4(1.0, 1.0, 1.0, 0.75 * amount * keep);
}
"""

const FOG_SHADER := """
shader_type canvas_item;
// The blizzard's fog: clear round the screen's middle, white at its edges.
uniform float amount = 0.0;
uniform float clear_from = 0.32;
uniform float edge = 0.62;
void fragment() {
	vec2 from_middle = (SCREEN_UV - vec2(0.5)) * vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0);
	float d = length(from_middle);
	float fog = smoothstep(clear_from, edge, d);
	COLOR = vec4(0.92, 0.96, 1.0, amount * fog);
}
"""


# =============================================================================
# A WALL OF ICE
# =============================================================================

class Wall extends Node2D:
	var arena: Node2D = null
	var id: int = 0
	var half: Vector2 = Vector2.ZERO
	var age: float = 0.0
	var hits: int = 0
	var broken: bool = false
	var hit_flash: float = 0.0
	var _box: Area2D = null
	var _body: StaticBody2D = null

	func _init() -> void:
		add_to_group(&"enemies")
		add_to_group(&"levers")
		set_meta(STRESS_MARK, true)

	func build(along: Vector2) -> void:
		half = along * (BLOCK * WALL_BLOCKS * 0.5)
		var bar := RectangleShape2D.new()
		bar.size = Vector2(BLOCK * WALL_BLOCKS, WALL_THICK)
		_body = StaticBody2D.new()
		_body.name = "ice"
		_body.collision_layer = BODY_LAYER
		_body.collision_mask = 0
		var foot := CollisionShape2D.new()
		foot.shape = bar
		foot.rotation = along.angle()
		foot.disabled = true
		_body.add_child(foot)
		add_child(_body)
		_box = Area2D.new()
		_box.name = "hurtbox"
		_box.collision_layer = HURT_LAYER
		_box.collision_mask = 0
		_box.monitoring = false
		_box.monitorable = false
		var face := RectangleShape2D.new()
		face.size = Vector2(BLOCK * WALL_BLOCKS, 16.0)
		var shape := CollisionShape2D.new()
		shape.shape = face
		shape.rotation = along.angle()
		shape.position = Vector2(0.0, -WALL_HIGH * 0.4)
		_box.add_child(shape)
		add_child(_box)

	func stands() -> bool:
		return not broken and age >= WALL_WARN

	func set_solid(on: bool) -> void:
		for shape in _body.get_children():
			(shape as CollisionShape2D).set_deferred(&"disabled", not on)
		_box.set_deferred(&"monitorable", on)

	func take_damage(_amount: float, _element: int = 0) -> void:
		if arena != null and stands():
			arena.call(&"wall_hit", self)

	func can_be_aimed_at() -> bool:
		return false

	func follow_pull(on: bool) -> void:
		if on and arena != null:
			arena.call(&"break_wall", self, false)

	func _draw() -> void:
		var a: Vector2 = -half
		var b: Vector2 = half
		if age < WALL_WARN:
			# The warning: a line of frost where it will rise.
			var warn: float = age / WALL_WARN
			_bar(a, b, 3.0 + 3.0 * warn, Color(FROST_INK, 0.25 + 0.45 * warn))
			return
		if broken:
			return
		var rise: float = clampf((age - WALL_WARN) / WALL_RISE, 0.0, 1.0)
		var up := Vector2(0.0, -WALL_HIGH * rise)
		var lit: float = hit_flash / 0.12
		_bar(a + Vector2(0, 2), b + Vector2(0, 2), WALL_THICK, Color(0, 0, 0, 0.35))
		for k in WALL_BLOCKS:
			var p: Vector2 = a.lerp(b, float(k) / WALL_BLOCKS)
			var q: Vector2 = a.lerp(b, float(k + 1) / WALL_BLOCKS)
			var tone: float = 0.85 + 0.15 * fmod(float(k) * 0.37 + float(id) * 0.13, 1.0)
			var glass := Color(ICE.r * tone, ICE.g * tone, ICE.b, 0.72).lerp(Color(1, 1, 1, 0.9), lit)
			_fill(p, q, q + up, p + up, glass)
			_fill(p + up, q + up, q + up + Vector2(0, -3), p + up + Vector2(0, -3), Color(1, 1, 1, 0.7))
		for c in hits:
			var at: Vector2 = a.lerp(b, 0.2 + 0.6 * fmod(float(c) * 0.41 + float(id) * 0.07, 1.0)) + up * 0.8
			_bar(at, at + Vector2(4, WALL_HIGH * 0.35 * rise), 1.0, Color(1, 1, 1, 0.85))

	func _fill(p: Vector2, q: Vector2, r: Vector2, t: Vector2, colour: Color) -> void:
		draw_primitive(PackedVector2Array([p, q, r, t]), PackedColorArray([colour]), PackedVector2Array())

	func _bar(from: Vector2, to: Vector2, width: float, colour: Color) -> void:
		var side: Vector2 = (to - from).orthogonal().normalized() * width * 0.5
		_fill(from - side, to - side, to + side, from + side, colour)


# =============================================================================
# THE ARENA
# =============================================================================

var boss: Node2D = null
var phase: int = -1
# [middle, radius, age] each.
var frost: Array = []
# Wall nodes standing or warning.
var walls: Array = []
# [where, age] each.
var hail: Array = []
var blizzard: float = 0.0
var _frost_clock: float = 1.5
var _wall_clock: float = 3.0
var _hail_clock: float = 0.0
var _wall_count: int = 0
var _chill_left: float = 0.0
var _glide: Vector2 = Vector2.ZERO
var _zone: BulletZone = null
var _floor: Node2D = null
# Every quad of a layer, handed over in one call (quadbatch.gd).
var _quads := QuadBatch.new()
var _air: Node2D = null
var _snow: MultiMeshInstance2D = null
var _snow_material: ShaderMaterial = null
var _snow_shown: float = -1.0
var _fog_shown: float = -1.0
var _snow_at: Vector2 = Vector2.INF
var _fog_layer: Node2D = null
var _fog: ColorRect = null
var _fog_material: ShaderMaterial = null
var _room: Rect2 = Rect2()
var _clock: float = 0.0
var _ending: float = -1.0


static func make(for_boss: Node2D) -> Node2D:
	if not LightArena.wanted(for_boss):
		return null
	var container: Node = for_boss.get_tree().get_first_node_in_group(&"groundeffects")
	var arena := (load("res://src/enemies/icearena.gd") as GDScript).new() as Node2D
	arena.set(&"boss", for_boss)
	arena.name = name_for(for_boss)
	container.add_child(arena)
	return arena


static func name_for(for_boss: Node2D) -> String:
	return "icearena%d" % maxi(int(for_boss.get(&"net_id")), 0)


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
	_floor.name = "frost"
	_floor.position = Vector2(0.0, SpikeFx.SORT_Y - 1.0)
	_floor.draw.connect(_quads.paint.bind(_floor, _draw_floor))
	add_child(_floor)
	_floor.reset_physics_interpolation()
	_air = Node2D.new()
	_air.name = "snow"
	_air.z_index = SNOW_Z
	_air.z_as_relative = false
	add_child(_air)
	_make_snow()
	# THE FOG UNDER THE HUD (0.143.0, the refinement): it was a CanvasLayer at
	# FOG_LAYER, over the HUD too - the health bars and hotbar went white in
	# a blizzard. Now it lies in the world over everything there (FOG_Z) and
	# under every CanvasLayer, a rect FOG_REACH past the room each way (only
	# what is on screen is drawn); the shader still reads the screen.
	_fog_layer = Node2D.new()
	_fog_layer.name = "fog"
	_fog_layer.top_level = true
	_fog_layer.z_index = FOG_Z
	_fog_layer.z_as_relative = false
	add_child(_fog_layer)
	_fog_layer.global_position = Vector2.ZERO
	_fog_layer.reset_physics_interpolation()
	_fog = ColorRect.new()
	_fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fog.position = _room.position - Vector2(FOG_REACH, FOG_REACH)
	_fog.size = _room.size + Vector2(FOG_REACH, FOG_REACH) * 2.0
	_fog_material = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = FOG_SHADER
	_fog_material.shader = shader
	_fog_material.set_shader_parameter(&"clear_from", FOG_CLEAR)
	_fog_material.set_shader_parameter(&"edge", FOG_EDGE)
	_fog.material = _fog_material
	_fog_layer.add_child(_fog)
	_fog_layer.visible = false
	show_tests()


# =============================================================================
# EACH FRAME
# =============================================================================

func _process(delta: float) -> void:
	_clock += delta
	if _ending >= 0.0:
		_ending += delta
		blizzard = maxf(0.0, blizzard - delta / END_SECONDS)
		_show_fog()
		_floor.queue_redraw()
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
	_on_you(delta)
	blizzard = clampf(blizzard + (delta if phase >= 2 else -delta) / BLIZZARD_IN, 0.0, 1.0)
	_show_fog()
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
	"""(Leader.) The frost, the walls and the hail, for every screen."""
	var bodies: Array = _fighters(delta)
	if bodies.is_empty():
		return
	_frost_clock -= delta
	if _frost_clock <= 0.0:
		_frost_clock = LightArena.paced(self, _p(FROST_GAP))
		var near: Vector2 = Targets.body_point(bodies[randi() % bodies.size()])
		var r: float = _p(FROST_RADIUS)
		# THE FLOOR BOOK (lightarena.gd): a few tries for a spot no partner
		# holds that leaves the room enough; none, and this frost waits.
		for _try in TRIES:
			var at: Vector2 = _inside(near + Vector2.from_angle(randf() * TAU) * randf_range(FROST_NEAR.x, FROST_NEAR.y))
			if LightArena.may_take(self, at, r):
				add_frost(at, r)
				_send({"h": "frost", "x": snappedf(at.x, 0.1), "y": snappedf(at.y, 0.1), "r": r})
				break
	_wall_clock -= delta
	if _wall_clock <= 0.0:
		_wall_clock = LightArena.paced(self, _p(WALL_GAP))
		var who: Vector2 = Targets.body_point(bodies[randi() % bodies.size()])
		var away: Vector2 = (who - boss.global_position).normalized()
		if away == Vector2.ZERO:
			away = Vector2.DOWN
		var at: Vector2 = _inside(who + away * WALL_BEHIND)
		var a: float = away.orthogonal().angle()
		if LightArena.may_take(self, at, BLOCK * WALL_BLOCKS * 0.5):
			_wall_count += 1
			add_wall(at, a, _wall_count)
			_send({"h": "wall", "x": snappedf(at.x, 0.1), "y": snappedf(at.y, 0.1), "a": snappedf(a, 0.0001), "n": _wall_count})
	var gap: float = _p(HAIL_GAP)
	if gap > 0.0:
		_hail_clock -= delta
		if _hail_clock <= 0.0:
			_hail_clock = LightArena.paced(self, gap)
			for body in bodies:
				var at: Vector2 = _inside(Targets.body_point(body) + Vector2.from_angle(randf() * TAU) * randf() * HAIL_NEAR)
				add_hail(at)
				_send({"h": "hail", "x": snappedf(at.x, 0.1), "y": snappedf(at.y, 0.1)})


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
		"frost":
			add_frost(at, clampf(float(event.get("r", 40.0)), 8.0, 80.0))
		"wall":
			add_wall(at, float(event.get("a", 0.0)), int(event.get("n", 0)))
		"hail":
			add_hail(at)


func add_frost(at: Vector2, r: float) -> void:
	frost.append([at, r, 0.0])
	while frost.size() > FROST_MOST:
		frost.pop_front()
	PerfOverlay.mark(&"frost forms")


func add_hail(at: Vector2) -> void:
	hail.append([at, 0.0])


func add_wall(at: Vector2, a: float, n: int) -> void:
	var wall := Wall.new()
	wall.arena = self
	wall.id = n
	wall.name = "wall%d" % posmod(n, WALL_NAMES)
	# A wall of the same name still here (ten walls ago) gives way.
	for old in walls:
		if is_instance_valid(old) and old.name == wall.name:
			_remove_wall(old)
	add_child(wall)
	wall.global_position = at
	wall.reset_physics_interpolation()
	wall.build(Vector2.from_angle(a))
	walls.append(wall)


# =============================================================================
# THE WALLS
# =============================================================================

func _paint_key(wall: Wall) -> String:
	return "%s/%d" % [name, wall.id]


func _rise(wall: Wall) -> void:
	wall.set_solid(true)
	if _zone != null:
		_zone.paint_solid(_paint_key(wall), wall.global_position - wall.half, wall.global_position + wall.half,
			WALL_THICK, true)
	PerfOverlay.mark(&"ice walls rise")
	# Risen under this game's player: put out to the side it stood on.
	var me: Node2D = _me()
	if me == null:
		return
	var off: Vector2 = Targets.body_point(me) - wall.global_position
	var face: Vector2 = wall.half.orthogonal().normalized()
	if absf(off.dot(wall.half.normalized())) <= wall.half.length() and absf(off.dot(face)) <= WALL_THICK:
		var side: float = 1.0 if off.dot(face) >= 0.0 else -1.0
		if StatusEffects.apply_to(me, StatusEffects.SHOVE, 0, Targets.body_point(me) - face * side * 20.0, false, 1.0):
			StatusEffects.slide(me, 1.2, 0.3)


func wall_hit(wall: Wall) -> void:
	"""(Wall.take_damage.) A blow of this game's on `wall`."""
	if not wall.stands():
		return
	wall.hits += 1
	wall.hit_flash = 0.12
	if wall.hits >= WALL_HITS:
		Presence.tell_lever(wall, true)
		break_wall(wall, true)


func break_wall(wall: Wall, _ours: bool) -> void:
	if wall == null or wall.broken:
		return
	wall.broken = true
	wall.set_solid(false)
	if _zone != null:
		_zone.paint_solid(_paint_key(wall), Vector2.ZERO, Vector2.ZERO, 0.0, false)
	var fx: Node2D = SpikeFx.of(get_parent())
	if fx != null and BossProjectile.ELEMENT_SPARKS.has(Element.Type.ICE):
		fx.call(&"burst", wall.global_position + Vector2(0, -WALL_HIGH * 0.5), Element.Type.ICE,
			Vector2(wall.half.length(), WALL_HIGH * 0.4), BossProjectile.ELEMENT_SPARKS[Element.Type.ICE])


func _remove_wall(wall: Wall) -> void:
	break_wall(wall, false)
	walls.erase(wall)
	wall.queue_free()


func standing_walls() -> int:
	var n: int = 0
	for wall in walls:
		if is_instance_valid(wall) and (wall as Wall).stands():
			n += 1
	return n


# =============================================================================
# AGEING, AND WHAT IT DOES TO YOU
# =============================================================================

func _age(delta: float) -> void:
	var i: int = 0
	while i < frost.size():
		frost[i][2] = float(frost[i][2]) + delta
		if float(frost[i][2]) >= FROST_FORM + FROST_LIFE:
			frost.remove_at(i)
			continue
		i += 1
	for wall in walls.duplicate():
		var w: Wall = wall
		var was: float = w.age
		w.age += delta
		w.hit_flash = maxf(0.0, w.hit_flash - delta)
		if was < WALL_WARN and w.age >= WALL_WARN and not w.broken:
			_rise(w)
		if w.age >= WALL_WARN + WALL_RISE + WALL_LIFE:
			_remove_wall(w)
		else:
			w.queue_redraw()
	i = 0
	while i < hail.size():
		var stone: Array = hail[i]
		stone[1] = float(stone[1]) + delta
		if float(stone[1]) >= HAIL_WARN:
			_land(stone[0])
			hail.remove_at(i)
			continue
		i += 1


func _land(at: Vector2) -> void:
	PerfOverlay.mark(&"hail lands")
	var fx: Node2D = SpikeFx.of(get_parent())
	if fx != null and BossProjectile.ELEMENT_SPARKS.has(Element.Type.ICE):
		fx.call(&"burst", at, Element.Type.ICE, Vector2(6, 3), BossProjectile.ELEMENT_SPARKS[Element.Type.ICE])
	var me: Node2D = _me()
	if me == null or not me.has_method(&"take_damage"):
		return
	if Targets.body_point(me).distance_to(at) > HAIL_RADIUS or not LightArena.may_hit(me, self):
		return
	var amount: int = maxi(1, roundi(float(me.get(&"max_hp")) * HAIL_SHARE))
	HitSource.blame(HitSource.of(boss, "hail"))
	me.call(&"take_damage", amount, Element.Type.ICE)
	StatusEffects.apply_to(me, StatusEffects.CHILL, amount, at, false, 1.0)


func _me() -> Node2D:
	var me: Node2D = get_tree().get_first_node_in_group(&"player") as Node2D
	if me == null or bool(me.get(&"is_dying")):
		return null
	return me


func on_frost(at: Vector2) -> bool:
	"""On a patch that has formed."""
	for patch in frost:
		if float(patch[2]) >= FROST_FORM and at.distance_to(patch[0]) <= float(patch[1]):
			return true
	return false


func takes_floor(at: Vector2) -> bool:
	"""(The floor book, lightarena.gd.) Frost, forming or formed, and a
	standing wall."""
	for patch in frost:
		if at.distance_to(patch[0]) <= float(patch[1]):
			return true
	for wall in walls:
		if not is_instance_valid(wall) or not (wall as Wall).stands():
			continue
		var middle: Vector2 = (wall as Wall).global_position
		var on: Vector2 = Geometry2D.get_closest_point_to_segment(at, middle - (wall as Wall).half, middle + (wall as Wall).half)
		if on.distance_to(at) <= WALL_THICK:
			return true
	return false


func _on_you(delta: float) -> void:
	_chill_left = maxf(0.0, _chill_left - delta)
	var me: Node2D = _me()
	if me == null:
		return
	var own: Vector2 = Vector2.ZERO
	var moving: Variant = me.get(&"velocity")
	if moving is Vector2:
		own = moving
	var at: Vector2 = Targets.body_point(me)
	if not on_frost(at) or not LightArena.in_room(self, at):
		_glide = own
		return
	# The skid: your walk comes round slowly; the difference carries you.
	_glide = _glide.lerp(own, clampf(GRIP * delta, 0.0, 1.0))
	var fx: Node = StatusEffects.of(me)
	if fx != null and fx.has_method(&"drift"):
		fx.call(&"drift", _glide - own, 0.1, SKID_MOST)
	if _chill_left <= 0.0:
		_chill_left = CHILL_GAP
		StatusEffects.apply_to(me, StatusEffects.CHILL, 0, Vector2.INF, true, 1.0)


# =============================================================================
# DRAWING (quads only)
# =============================================================================

func _fill(_on: CanvasItem, p: Vector2, q: Vector2, r: Vector2, t: Vector2, colour: Color) -> void:
	# Into the layer's batch (quadbatch.gd: the whole layer in one call).
	_quads.quad(p, q, r, t, colour)


func _ring(_on: CanvasItem, middle: Vector2, r: float, ry: float, colour: Color, solid: bool) -> void:
	# A flat ring (or a filled disc) round `middle`.
	if solid:
		_quads.oval(middle, r, ry, colour)
	else:
		_quads.band(middle, r, ry, 0.92, colour)


func _draw_floor() -> void:
	var o: Vector2 = _floor.global_position
	var fade: float = 1.0 if _ending < 0.0 else clampf(1.0 - _ending / END_SECONDS, 0.0, 1.0)
	for patch in frost:
		var m: Vector2 = (patch[0] as Vector2) - o
		var r: float = float(patch[1])
		var age: float = float(patch[2])
		var form: float = clampf(age / FROST_FORM, 0.0, 1.0)
		var going: float = clampf((FROST_FORM + FROST_LIFE - age) / 1.0, 0.0, 1.0)
		var a: float = form * going * fade
		_ring(_floor, m, r * (0.6 + 0.4 * form), r * 0.6 * (0.6 + 0.4 * form), Color(FROST_INK, 0.32 * a), true)
		_ring(_floor, m, r, r * 0.6, Color(1, 1, 1, 0.5 * a), false)
		for k in 6:
			var g: Vector2 = m + Vector2(cos(float(k) * 2.4 + float(r)) * r * 0.6, sin(float(k) * 2.4) * r * 0.35)
			var twinkle: float = 0.5 + 0.5 * sin(_clock * 4.0 + float(k) * 1.7)
			_fill(_floor, g + Vector2(-2, 0), g + Vector2(0, -2), g + Vector2(2, 0), g + Vector2(0, 2), Color(1, 1, 1, 0.8 * twinkle * a))
	for stone in hail:
		var m: Vector2 = (stone[0] as Vector2) - o
		var grow: float = clampf(float(stone[1]) / HAIL_WARN, 0.0, 1.0)
		_ring(_floor, m, HAIL_RADIUS * grow, HAIL_RADIUS * 0.55 * grow, Color(0, 0, 0, (0.2 + 0.3 * grow) * fade), true)
		_ring(_floor, m, HAIL_RADIUS, HAIL_RADIUS * 0.55, Color(ICE, (0.3 + 0.5 * grow) * fade), false)


func _make_snow() -> void:
	"""The blizzard's flakes: one MultiMesh, placed on the card (SNOW_SHADER)."""
	var diamond := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(-1, 0), Vector2(0, -1), Vector2(1, 0), Vector2(0, 1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	diamond.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_2D
	multi.mesh = diamond
	multi.instance_count = SNOW
	multi.visible_instance_count = (SNOW >> 1) if SettingsScript.on_phone() else SNOW
	multi.custom_aabb = AABB(Vector3(-1.0e6, -1.0e6, -1.0), Vector3(2.0e6, 2.0e6, 2.0))
	for k in SNOW:
		multi.set_instance_transform_2d(k, Transform2D.IDENTITY)
	_snow_material = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = SNOW_SHADER
	_snow_material.shader = shader
	_snow_material.set_shader_parameter(&"way", Vector2(1.0, 0.45).normalized())
	_snow_material.set_shader_parameter(&"span", _room.size.length())
	_snow = MultiMeshInstance2D.new()
	_snow.name = "flakes"
	_snow.multimesh = multi
	_snow.material = _snow_material
	_snow.visible = false
	# Placed by its shader, never moved between two buffers.
	_snow.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	RenderingServer.multimesh_set_physics_interpolated(multi.get_rid(), false)
	_air.add_child(_snow)


func _show_fog() -> void:
	_fog_layer.visible = blizzard > 0.0 and not LagTests.hide_arena
	if _fog_layer.visible and not is_equal_approx(blizzard, _fog_shown):
		_fog_shown = blizzard
		_fog_material.set_shader_parameter(&"amount", FOG_THICK * blizzard)
	if _snow != null:
		_snow.visible = blizzard > 0.0
		if _snow.visible and not is_equal_approx(blizzard, _snow_shown):
			_snow_shown = blizzard
			_snow_material.set_shader_parameter(&"amount", blizzard)
		var o: Vector2 = _air.global_position
		if _snow.visible and o != _snow_at:
			# The room in the layer's own space (once, and again if it moved).
			_snow_at = o
			_snow_material.set_shader_parameter(&"middle", _room.get_center() - o)
			_snow_material.set_shader_parameter(&"room", Vector4(_room.position.x - o.x, _room.position.y - o.y,
				_room.end.x - o.x, _room.end.y - o.y))


# =============================================================================
# THE END, AND THE LAG TEST
# =============================================================================

func _end() -> void:
	"""Its boss is gone: the walls shatter, the frost and fog go, then it
	does."""
	if _ending >= 0.0:
		return
	_ending = 0.0
	hail.clear()
	for wall in walls.duplicate():
		_remove_wall(wall)
	frost.clear()


func _exit_tree() -> void:
	# Freed with its area: the bullets' painted walls go with it.
	if _zone != null and is_instance_valid(_zone):
		for wall in walls:
			if is_instance_valid(wall):
				_zone.paint_solid(_paint_key(wall), Vector2.ZERO, Vector2.ZERO, 0.0, false)


func show_tests() -> void:
	"""The GM panel's Arena lag test: the frost, snow and fog drawn or not
	(the walls stand, and the frost still skids you)."""
	var off: bool = LagTests.hide_arena
	if _floor != null:
		_floor.visible = not off
	if _air != null:
		_air.visible = not off
	if _fog_layer != null:
		_show_fog()
