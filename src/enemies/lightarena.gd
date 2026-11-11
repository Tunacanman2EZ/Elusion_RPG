# lightarena.gd - the Light Keeper's arena (0.139.0): mirrors, flares and the
# eclipse. The first of the six bosses' arenas that fight back - the Docs plan
# "Boss fights: arenas that fight back", agreed with the owner ("lets build
# it", and of the mirrors: "Yes, players break them"), pictured first in
# light_arena_plan.png.
#
# MADE BY THE BOSS (bossenemy.gd _keep_arena(), its kit's "arena"), in the
# Boss Arena and the Endless (ARENA_AREAS), once it is loose; in the area's
# effects container, as "lightarena<its shared number>". It goes with its boss:
# dying, leashed home past its phase, or freed - the panes shatter, the dark
# lifts, and it frees itself.
#
# THREE STEPS, by the boss's phase (_current_phase(), from its health, so
# every screen agrees):
#   one    FOUR MIRRORS (panes) stand round the room's middle (PANE_SPOTS). An
#          orb of any volley that reaches one is turned back off its face -
#          painted into the area's bullet walls (BulletZone.paint_mirror(),
#          BulletField MIRRORS), so it costs an orb one cell read, as a wall
#          does - and drawn white from then on. Each is angled so a spoke
#          from the middle goes along the room's side (PANE_SENDS): a ring of
#          turning spokes becomes a lattice whose gaps move.
#   two    and FLARES: a mote swells near each player in the fight for
#          FLARE_SWELL, then flashes; within FLARE_RADIUS at the flash, a
#          share of your health (FLARE_SHARE) and dazzled.
#   three  and THE ECLIPSE: the room goes dark (ECLIPSE_DARK) but for a light
#          round the boss, each standing mirror and each player - a little
#          round you. The orbs (z 20), the flares and the spikes' warning rings
#          (lifted, spikefx.gd lift_rings()) stay above the dark: nothing that
#          hurts is hidden, only where it is safe to stand.
#
# YOU CAN BREAK A MIRROR: PANE_HITS blows of yours (any attack - it stands in
# "enemies" with a hurtbox, as the Endless's stand-ins do, with the
# stress-copy mark so nothing that numbers, counts or respawns monsters sees
# it, and never aimed at) shatter it: its bounces stop, and in the eclipse its
# light goes out. It grows back at the next phase. Solid while it stands (the
# walls layer, as a boss gate's bars), so nobody walks through glass.
#
# THE SAME ON EVERY SCREEN. The panes stand where the room says (its floor's
# middle, the same in every game), and the phase is the boss's health. A flare is the
# leader's: its game picks the spots and sends them ("la", monstersync.gd),
# and every game makes the same flares, each hurting only its own player. A
# mirror broken anywhere is broken everywhere: the game that broke it tells
# the others as the levers do (Presence.tell_lever(); the pane is in "levers"
# with follow_pull()), under a name with the phase in it ("pane2p1"), so a
# pull from a phase gone by finds no pane.
#
# No class_name: preload it by path.
extends Node2D

const StatusEffects := preload("res://src/characters/statuseffects.gd")
const SpikeFx := preload("res://src/projectiles/spikefx.gd")
const BossProjectile := preload("res://src/projectiles/bossprojectile.gd")
const Targets := preload("res://src/shared/targets.gd")
const HitSource := preload("res://src/shared/hitsource.gd")
const LagTests := preload("res://src/systems/lagtests.gd")

const GROUP := &"light_arena"
# Where an arena may stand: the Boss Arena's gauntlet and the Endless. The
# Descent's keepers have their rooms' own hazards. `everywhere` for the suite
# and the bench.
const ARENA_AREAS := ["bossarena", "endless"]
static var everywhere: bool = false

# THE MIRRORS. Where each stands from the middle of the room (the bullets'
# floor, BulletField.bounds - the Boss Arena's (0, 0), the Endless's arena),
# and which way it sends a spoke from there (it is angled for that): the top
# two down the room's sides, the bottom two up them. Clear of the gauntlet's
# gates (wave two's stand at (+-115, -105)) and the dirt's candelabras.
const PANE_SPOTS := [Vector2(-132, -15), Vector2(132, -15), Vector2(-120, 104), Vector2(120, 104)]
const PANE_SENDS := [Vector2(0, 1), Vector2(0, 1), Vector2(0, -1), Vector2(0, -1)]
# Half its length along the floor, and how tall it stands.
const PANE_HALF := 26.0
const PANE_HIGH := 28.0
# Blows of yours that break one; how long one takes to grow back; how long it
# glows when an orb comes off it, or a blow lands.
const PANE_HITS := 4
const PANE_GROW := 0.6
const PANE_FLASH := 0.25
const HIT_FLASH := 0.12
# The walls layer (a boss gate's bars: the player and the monsters mask it)
# and the monsters' hurt layer.
const BODY_LAYER := 2
const HURT_LAYER := 8
const STRESS_MARK := &"stress_copy"

# THE FLARES, by phase: how often the leader throws them (0, none), how long
# one swells before it flashes, how long the flash is drawn, how far it
# reaches, how far from a player it is put, and its share of your health.
const FLARE_GAP := [0.0, 3.0, 2.2]
const FLARE_SWELL := 1.1
const FLARE_FLASH := 0.3
const FLARE_RADIUS := 52.0
const FLARE_NEAREST := 30.0
const FLARE_FURTHEST := 80.0
const FLARE_SHARE := 0.08
# Furthest from the boss's home a flare heard from the leader may be put.
const FLARE_REACH := 900.0

# THE ECLIPSE: how dark; how long it takes to fall and to lift; its lights
# (radius each); and where it is drawn - under the orbs (z 20), the flares
# (FLARE_Z) and the lifted rings, over everything standing.
const ECLIPSE_DARK := 0.86
const ECLIPSE_IN := 1.5
const ECLIPSE_OUT := 1.0
const LIGHT_BOSS := 84.0
const LIGHT_PANE := 58.0
const LIGHT_ME := 44.0
const LIGHT_OTHERS := 34.0
const LIGHTS_MOST := 12
const ECLIPSE_Z := 15
const FLARE_Z := 17
# How far past the bullets' floor the dark reaches: past any view.
const DARK_MARGIN := 700.0
# How long the arena takes to go once its boss has.
const END_SECONDS := 1.0

const DARK_SHADER := """
shader_type canvas_item;
// The eclipse: dark, but for up to 12 lights (x, y, radius) in world space.
// Unshaded: the room's own lights (the boss's glow, the candles) would light
// the dark itself grey.
render_mode unshaded;
uniform float amount = 0.0;
uniform vec4 lights[12];
uniform int count = 0;
varying vec2 world;
void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}
void fragment() {
	float lit = 0.0;
	for (int i = 0; i < 12; i++) {
		if (i >= count) {
			break;
		}
		float d = distance(world, lights[i].xy);
		lit = max(lit, 1.0 - smoothstep(lights[i].z * 0.55, lights[i].z, d));
	}
	COLOR = vec4(0.02, 0.01, 0.05, amount * (1.0 - lit));
}
"""


# =============================================================================
# A MIRROR
# =============================================================================

class Pane extends Node2D:
	var arena: Node2D = null
	var index: int = 0
	# Its ends on the floor, from its middle (where it stands).
	var half: Vector2 = Vector2.ZERO
	var hits: int = 0
	var broken: bool = false
	var grow: float = 1.0
	var flash: float = 0.0
	var hit_flash: float = 0.0
	var clock: float = 0.0
	var _box: Area2D = null
	var _wall: StaticBody2D = null

	func _init() -> void:
		add_to_group(&"enemies")
		add_to_group(&"levers")
		set_meta(STRESS_MARK, true)

	func build(along: Vector2) -> void:
		half = along * PANE_HALF
		var bar := RectangleShape2D.new()
		bar.size = Vector2(PANE_HALF * 2.0, 6.0)
		_wall = StaticBody2D.new()
		_wall.name = "glass"
		_wall.collision_layer = BODY_LAYER
		_wall.collision_mask = 0
		var foot := CollisionShape2D.new()
		foot.shape = bar
		foot.rotation = along.angle()
		_wall.add_child(foot)
		add_child(_wall)
		_box = Area2D.new()
		_box.name = "hurtbox"
		_box.collision_layer = HURT_LAYER
		_box.collision_mask = 0
		_box.monitoring = false
		var face := RectangleShape2D.new()
		face.size = Vector2(PANE_HALF * 2.0, 14.0)
		var shape := CollisionShape2D.new()
		shape.shape = face
		shape.rotation = along.angle()
		shape.position = Vector2(0.0, -PANE_HIGH * 0.4)
		_box.add_child(shape)
		add_child(_box)

	func take_damage(_amount: float, _element: int = 0) -> void:
		if arena != null and not broken and grow >= 1.0:
			arena.call(&"pane_hit", index)

	func can_be_aimed_at() -> bool:
		# Never picked by an aim (the touch aim, a pet, the mage's spike):
		# you break one by hitting it, not by the game choosing it for you.
		return false

	func follow_pull(on: bool) -> void:
		# Somebody else's game broke it (lightarena.gd, THE SAME ON EVERY
		# SCREEN).
		if on and arena != null:
			arena.call(&"break_pane", index, false)

	func stands() -> bool:
		return not broken

	func set_solid(on: bool) -> void:
		for shape in _wall.get_children():
			(shape as CollisionShape2D).set_deferred(&"disabled", not on)
		_box.set_deferred(&"monitorable", on)

	func _process(delta: float) -> void:
		clock += delta
		flash = maxf(0.0, flash - delta)
		hit_flash = maxf(0.0, hit_flash - delta)
		if grow < 1.0 and not broken:
			grow = minf(1.0, grow + delta / PANE_GROW)
		queue_redraw()

	func _draw() -> void:
		# QUADS ONLY (draw_primitive): Godot draws a run of them in one call,
		# so the four panes cost the area one or two draws; drawn with lines,
		# polygons and a circle they were twenty (zz/light/drawbench).
		var a: Vector2 = -half
		var b: Vector2 = half
		# Its plinth and shadow stand whether or not the glass does.
		_bar(a + Vector2(0, 2), b + Vector2(0, 2), 5.0, Color(0, 0, 0, 0.45))
		_bar(a, b, 4.0, Color(0.35, 0.33, 0.38))
		if broken:
			return
		var up := Vector2(0, -PANE_HIGH * grow)
		var lit: float = maxf(flash / PANE_FLASH, hit_flash / HIT_FLASH)
		var glass := Color(0.86, 0.93, 1.0, 0.55 * grow).lerp(Color(1.0, 0.97, 0.8, 0.9 * grow), lit)
		_fill(a, b, b + up, a + up, glass)
		# A streak of light across it, moving.
		var s: float = fmod(clock * 0.35 + float(index) * 0.27, 1.0)
		var s2: float = minf(s + 0.18, 1.0)
		_fill(a.lerp(b, s), a.lerp(b, s2), a.lerp(b, s2) + up, a.lerp(b, s) + up, Color(1, 1, 1, 0.35 * grow))
		# Cracks, one more each blow.
		for c in hits:
			var at: float = 0.25 + 0.5 * fmod(float(c) * 0.37 + float(index) * 0.11, 1.0)
			var top: Vector2 = a.lerp(b, at) + up * 0.85
			var bend: Vector2 = top + Vector2(5.0, PANE_HIGH * 0.3 * grow)
			_bar(top, bend, 1.0, Color(1, 1, 1, 0.8))
			_bar(bend, top + Vector2(-2.0, PANE_HIGH * 0.6 * grow), 1.0, Color(1, 1, 1, 0.8))
		var rim := Color(1.0, 0.96, 0.75, 0.95 * grow)
		_bar(a, a + up, 1.0, rim)
		_bar(a + up, b + up, 1.0, rim)
		_bar(b + up, b, 1.0, rim)
		# Its glow: two squares turned an eighth apart, a soft octagon.
		var glow := Color(1.0, 0.95, 0.7, (0.05 + 0.12 * lit) * grow)
		var c0: Vector2 = (a + b) * 0.5 + up * 0.5
		for turn in 2:
			var r: Vector2 = Vector2(16.0, 0.0).rotated(float(turn) * PI * 0.25)
			_fill(c0 + r, c0 + r.orthogonal(), c0 - r, c0 - r.orthogonal(), glow)

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
# One a spot (PANE_SPOTS); null where a pane would stand in a wall.
var panes: Array = []
# [where, age, flashed] each.
var flares: Array = []
var eclipse: float = 0.0
var _flare_clock: float = 0.0
var _zone: BulletZone = null
var _flare_layer: Node2D = null
var _dark: Node2D = null
var _dark_material: ShaderMaterial = null
var _ending: float = -1.0
var _rings_lifted: bool = false


static func make(for_boss: Node2D) -> Node2D:
	"""The arena of `for_boss`, in its area's effects container: null where
	it may not stand (wanted())."""
	if not wanted(for_boss):
		return null
	var container: Node = for_boss.get_tree().get_first_node_in_group(&"groundeffects")
	var arena := (load("res://src/enemies/lightarena.gd") as GDScript).new() as Node2D
	arena.set(&"boss", for_boss)
	arena.name = name_for(for_boss)
	container.add_child(arena)
	return arena


static func wanted(for_boss: Node2D) -> bool:
	"""In the Boss Arena or the Endless, with a bullet zone and somewhere to
	stand: never a Descent's hidden caster."""
	if for_boss == null or not for_boss.is_inside_tree() or for_boss.has_meta(&"descent_caster"):
		return false
	if not everywhere and not (AreaRegistry.current_area_id() in ARENA_AREAS):
		return false
	if BulletZone.find(for_boss) == null:
		return false
	return for_boss.get_tree().get_first_node_in_group(&"groundeffects") != null


static func name_for(for_boss: Node2D) -> String:
	"""lightarena<shared number>: the same on every game, for the levers."""
	return "lightarena%d" % maxi(int(for_boss.get(&"net_id")), 0)


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(LagTests.GROUP)
	# Its panes stand among everyone else, sorted by their feet.
	y_sort_enabled = true
	_zone = BulletZone.find(self)
	_flare_layer = Node2D.new()
	_flare_layer.name = "flares"
	_flare_layer.z_index = FLARE_Z
	_flare_layer.z_as_relative = false
	_flare_layer.draw.connect(_draw_flares)
	add_child(_flare_layer)
	_dark = Node2D.new()
	_dark.name = "eclipse"
	_dark.z_index = ECLIPSE_Z
	_dark.z_as_relative = false
	_dark_material = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = DARK_SHADER
	_dark_material.shader = shader
	_dark.material = _dark_material
	_dark.visible = false
	_dark.draw.connect(_draw_dark)
	add_child(_dark)
	_place_panes()
	show_tests()


func _place_panes() -> void:
	var home: Vector2 = boss.global_position
	if _zone != null and _zone.field.bounds.size.x < 100000.0:
		home = _zone.field.bounds.get_center()
	for k in PANE_SPOTS.size():
		var at: Vector2 = home + PANE_SPOTS[k]
		var from_home: Vector2 = (at - home).normalized()
		var face: Vector2 = ((PANE_SENDS[k] as Vector2).normalized() - from_home).normalized()
		var along: Vector2 = face.orthogonal()
		if not _room_for(at, along):
			panes.append(null)
			continue
		var pane := Pane.new()
		pane.arena = self
		pane.index = k
		pane.name = "pane%dp0" % k
		add_child(pane)
		pane.global_position = at
		pane.reset_physics_interpolation()
		pane.build(along)
		panes.append(pane)
		_paint(k, true)


func _room_for(at: Vector2, along: Vector2) -> bool:
	"""Open floor along its whole foot: inside the bullets' floor, no wall
	cell, nothing solid (walls, gates) under it."""
	if _zone == null:
		return false
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var query := PhysicsPointQueryParameters2D.new()
	query.collision_mask = 1 | BODY_LAYER
	query.collide_with_bodies = true
	for n in 5:
		var point: Vector2 = at + along * PANE_HALF * (float(n) / 2.0 - 1.0)
		if not _zone.field.bounds.has_point(point) or _zone.field.is_wall(point):
			return false
		query.position = point
		if space != null and not space.intersect_point(query, 1).is_empty():
			return false
	return true


func _paint(k: int, on: bool) -> void:
	var pane: Pane = panes[k]
	if pane == null or _zone == null:
		return
	_zone.paint_mirror(k, pane.global_position - pane.half, pane.global_position + pane.half, on)


func standing() -> int:
	"""How many mirrors stand."""
	var n: int = 0
	for pane in panes:
		if pane != null and (pane as Pane).stands():
			n += 1
	return n


# =============================================================================
# EACH FRAME
# =============================================================================

func _process(delta: float) -> void:
	if _ending >= 0.0:
		_end_step(delta)
		return
	if not _boss_here():
		_end()
		return
	var now: int = int(boss.call(&"_current_phase"))
	if now != phase:
		_to_phase(now)
	if name != name_for(boss):
		name = name_for(boss)
	# The leader throws the flares; everyone else is told (hear()).
	var gap: float = float(FLARE_GAP[clampi(phase, 0, 2)])
	if gap > 0.0 and not bool(boss.get(&"net_mirror")):
		_flare_clock -= delta
		if _flare_clock <= 0.0:
			_flare_clock = gap
			_throw_flares()
	_age_flares(delta)
	_flash_panes()
	_step_eclipse(delta, phase == 2)


func _boss_here() -> bool:
	if not is_instance_valid(boss) or not boss.is_inside_tree():
		return false
	return not (bool(boss.get(&"_dying")) or bool(boss.get(&"_death_resolved")) or bool(boss.get(&"gated")))


func _to_phase(now: int) -> void:
	"""A new phase: every mirror stands again, under the phase's name."""
	phase = now
	_flare_clock = 0.6
	for pane in panes:
		if pane == null:
			continue
		var p: Pane = pane
		p.name = "pane%dp%d" % [p.index, phase]
		p.hits = 0
		if p.broken:
			p.broken = false
			p.grow = 0.0
			p.set_solid(true)
			_paint(p.index, true)


func pane_hit(k: int) -> void:
	"""(Pane.take_damage.) A blow of this game's on mirror k."""
	var pane: Pane = panes[k] if k >= 0 and k < panes.size() else null
	if pane == null or pane.broken:
		return
	pane.hits += 1
	pane.hit_flash = HIT_FLASH
	if pane.hits >= PANE_HITS:
		# Everyone else's breaks too, by its name now (before anything
		# changes it).
		Presence.tell_lever(pane, true)
		break_pane(k, true)


func break_pane(k: int, _ours: bool) -> void:
	"""Mirror k shatters: no more bounces, no light in the dark, nothing
	solid, until the next phase."""
	var pane: Pane = panes[k] if k >= 0 and k < panes.size() else null
	if pane == null or pane.broken:
		return
	pane.broken = true
	pane.set_solid(false)
	_paint(k, false)
	PerfOverlay.mark(&"mirrors break")
	var fx: Node2D = SpikeFx.of(get_parent())
	if fx != null and BossProjectile.ELEMENT_SPARKS.has(Element.Type.LIGHT):
		fx.call(&"burst", pane.global_position + Vector2(0, -PANE_HIGH * 0.5), Element.Type.LIGHT,
			Vector2(PANE_HALF, PANE_HIGH * 0.4), BossProjectile.ELEMENT_SPARKS[Element.Type.LIGHT])


func _flash_panes() -> void:
	if _zone == null:
		return
	for k in _zone.field.bounces:
		if k >= 0 and k < panes.size() and panes[k] != null:
			(panes[k] as Pane).flash = PANE_FLASH


# =============================================================================
# THE FLARES
# =============================================================================

func _throw_flares() -> void:
	"""(Leader.) One near each player in the fight, for every screen."""
	for body in boss.call(&"fight_targets"):
		var near: Vector2 = Targets.body_point(body)
		var spot: Vector2 = near + Vector2.from_angle(randf() * TAU) * randf_range(FLARE_NEAREST, FLARE_FURTHEST)
		if boss.has_method(&"clamp_to_navigation"):
			spot = boss.call(&"clamp_to_navigation", spot)
		add_flare(spot)
		if boss.has_method(&"arena_event"):
			boss.call(&"arena_event", {"k": "la", "h": "flare",
				"x": snappedf(spot.x, 0.1), "y": snappedf(spot.y, 0.1)})


func hear(event: Dictionary) -> void:
	"""(Follower, from the leader's "la".) A flare where the leader put it -
	only near this arena's boss."""
	if str(event.get("h", "")) != "flare" or _ending >= 0.0:
		return
	var at := Vector2(float(event.get("x", 0.0)), float(event.get("y", 0.0)))
	if at.distance_to(boss.global_position) <= FLARE_REACH:
		add_flare(at)


func add_flare(at: Vector2) -> void:
	flares.append([at, 0.0, false])


func _age_flares(delta: float) -> void:
	if flares.is_empty():
		return
	var i: int = 0
	while i < flares.size():
		var flare: Array = flares[i]
		flare[1] = float(flare[1]) + delta
		if not bool(flare[2]) and float(flare[1]) >= FLARE_SWELL:
			flare[2] = true
			_flash(flare[0])
		if float(flare[1]) >= FLARE_SWELL + FLARE_FLASH:
			flares.remove_at(i)
			continue
		i += 1
	_flare_layer.queue_redraw()


func _flash(at: Vector2) -> void:
	"""A flare flashes: this game's player, if near, is hit and dazzled."""
	PerfOverlay.mark(&"flares flash")
	var me: Node2D = get_tree().get_first_node_in_group(&"player") as Node2D
	if me == null or not me.has_method(&"take_damage") or bool(me.get(&"is_dying")):
		return
	if Targets.body_point(me).distance_to(at) > FLARE_RADIUS:
		return
	var amount: int = maxi(1, roundi(float(me.get(&"max_hp")) * FLARE_SHARE))
	HitSource.blame(HitSource.of(boss, "flare"))
	me.call(&"take_damage", amount, Element.Type.LIGHT)
	StatusEffects.apply_to(me, StatusEffects.DAZZLE, amount, at, false, 1.0)


func _draw_flares() -> void:
	for flare in flares:
		var at: Vector2 = _flare_layer.to_local(flare[0])
		var t: float = float(flare[1])
		if t < FLARE_SWELL:
			var g: float = t / FLARE_SWELL
			_flare_layer.draw_arc(at, FLARE_RADIUS, 0.0, TAU, 40, Color(1.0, 0.92, 0.55, 0.25 + 0.35 * g), 1.0)
			_flare_layer.draw_circle(at, 3.0 + 9.0 * g, Color(1.0, 0.95, 0.6, 0.4 + 0.5 * g))
		else:
			var after: float = clampf((t - FLARE_SWELL) / FLARE_FLASH, 0.0, 1.0)
			_flare_layer.draw_circle(at, FLARE_RADIUS * (0.6 + 0.4 * after), Color(1.0, 1.0, 0.85, 0.7 * (1.0 - after)))


# =============================================================================
# THE ECLIPSE
# =============================================================================

func _step_eclipse(delta: float, dark: bool) -> void:
	var was: float = eclipse
	if dark:
		eclipse = minf(1.0, eclipse + delta / ECLIPSE_IN)
	else:
		eclipse = maxf(0.0, eclipse - delta / ECLIPSE_OUT)
	if eclipse > 0.0 and was <= 0.0:
		PerfOverlay.mark(&"eclipse falls")
	_lift_rings(eclipse > 0.0)
	_dark.visible = eclipse > 0.0 and not LagTests.hide_arena
	if not _dark.visible:
		return
	var lights: Array[Vector4] = []
	if is_instance_valid(boss):
		lights.append(Vector4(boss.global_position.x, boss.global_position.y - 12.0, LIGHT_BOSS, 0.0))
	for pane in panes:
		if pane != null and (pane as Pane).stands():
			var p: Pane = pane
			var middle: Vector2 = p.global_position + Vector2(0.0, -PANE_HIGH * 0.5)
			lights.append(Vector4(middle.x, middle.y, LIGHT_PANE * p.grow, 0.0))
	var me: Node = get_tree().get_first_node_in_group(&"player")
	for body in Targets.all(get_tree()):
		if lights.size() >= LIGHTS_MOST:
			break
		if body is Node2D:
			var at: Vector2 = Targets.body_point(body)
			lights.append(Vector4(at.x, at.y - 8.0, LIGHT_ME if body == me else LIGHT_OTHERS, 0.0))
	var count: int = lights.size()
	while lights.size() < LIGHTS_MOST:
		lights.append(Vector4.ZERO)
	_dark_material.set_shader_parameter(&"amount", ECLIPSE_DARK * eclipse)
	_dark_material.set_shader_parameter(&"lights", lights)
	_dark_material.set_shader_parameter(&"count", count)
	_dark.queue_redraw()


func _draw_dark() -> void:
	var rect: Rect2 = _zone.field.bounds.grow(DARK_MARGIN) if _zone != null else Rect2(-2000, -2000, 4000, 4000)
	_dark.draw_rect(Rect2(_dark.to_local(rect.position), rect.size), Color.WHITE)


func _lift_rings(up: bool) -> void:
	if up == _rings_lifted:
		return
	_rings_lifted = up
	var fx: Node2D = SpikeFx.of(get_parent())
	if fx != null and fx.has_method(&"lift_rings"):
		fx.call(&"lift_rings", up)


# =============================================================================
# THE END, AND THE LAG TEST
# =============================================================================

func _end() -> void:
	"""Its boss is gone: the panes shatter, the dark lifts, then it goes."""
	if _ending >= 0.0:
		return
	_ending = 0.0
	flares.clear()
	_flare_layer.queue_redraw()
	for k in panes.size():
		break_pane(k, false)


func _end_step(delta: float) -> void:
	_ending += delta
	_step_eclipse(delta, false)
	if _ending >= END_SECONDS and eclipse <= 0.0:
		_lift_rings(false)
		queue_free()


func show_tests() -> void:
	"""The GM panel's lag test (lagtests.gd hide_arena): the arena drawn or
	not - its mirrors still turn orbs and stop you, its flares still burn."""
	var off: bool = LagTests.hide_arena
	for pane in panes:
		if pane != null:
			(pane as Node2D).visible = not off
	if _flare_layer != null:
		_flare_layer.visible = not off
	if _dark != null:
		_dark.visible = eclipse > 0.0 and not off
