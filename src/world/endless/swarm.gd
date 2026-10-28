# swarm.gd - the endless run's horde: thousands of small slimes, cheap (0.93.0).
#
# The owner: an endless map whose monsters get harder as time goes on, "for 4
# players and maybe 3000 enemies". A real monster is a whole creature - its
# own node, navigation, collision, threat rings, attacks and a health bar -
# and the 16x stress test showed his PC holds about 6,000 of those standing
# about, not 3,000 all chasing at once. So the horde is not made of monsters.
# Each swarmling is a row in a few packed arrays:
#
#   - NO NODE. Where it stands, which way it is going, its health and its
#     state are numbers here (px, py, hp, state...). Nothing of it is in the
#     scene tree, the physics world or the navigation map.
#   - ONE DRAW. Every swarmling is an instance of one MultiMesh, drawn with
#     swarm.gdshader from the small slime's own sheet, recoloured to the run's
#     element. The shader picks the frame and facing, and draws the walk
#     between this step and the last, so the crowd moves smoothly while it
#     thinks only STEPS_PER_SECOND (20) times a second.
#   - NO PATHFINDING. Each one heads for the player and is pushed off where
#     the crowd is thick (a grid of how many stand in each CELL), and kept in
#     the arena and out of the corridor by rectangles.
#
# IT IS HIT BY EVERY ATTACK THE GAME HAS, through a few stand-ins. Every
# player attack - a sword's swing, a wave, a spike, an orb, a pet's arrow -
# finds what it hits by touching a hurtbox whose parent is in the "enemies"
# group and has take_damage(). PROXIES (96) such stand-ins (swarmproxy.gd)
# are moved each physics tick onto the swarmlings nearest the player, and a
# blow on one is a blow on the swarmling it stands on. A swarmling further
# off cannot be hit, which is as it should be: nothing reaches that far.
#
# IT HITS BACK BY TOUCH: every TOUCH_SECONDS the player takes one hit,
# touch_damage for each swarmling against them up to TOUCH_MOST, through
# Player.take_damage() - armour, resistance, god mode and the defence XP as
# for any hit.
#
# THIS GAME'S ALONE (0.93.0, the first step): the swarm runs here and chases
# this game's player. Sharing it between a party - one start for every game,
# kills sent in batches - and paying for it are the next steps; until then a
# swarmling is worth nothing to the server, like the owner's stress copies.
extends Node2D

signal killed(at: Vector2)

const SwarmProxy := preload("res://src/world/endless/swarmproxy.gd")
const SHADER := preload("res://src/world/endless/swarm.gdshader")
const SHEET := preload("res://art/enemy/slime.png")

const MOST := 3000
const STEPS_PER_SECOND := 20.0
const STEP := 1.0 / STEPS_PER_SECOND
# The grid the crowd is counted on, in px.
const CELL := 24.0
# How hard a thick cell pushes, in px a second for each swarmling more than
# its neighbour has.
const PUSH := 14.0
# HOW QUICKLY ONE TURNS: each step it moves this much of the way from how it
# was going to how it wants to go. The crowd's counts jump from step to step,
# and a swarmling that obeyed them at once shook on the spot (the owner: "the
# enemies are kind of wobbly"); carried, the jumps even out into a walk.
const STEER := 0.25
# Its own sideways wander, a fraction of its stride, and how slowly it sways.
const WANDER := 0.12
const WANDER_RATE := 0.0011
# Which way it faces changes only once the other way leads by this much, so
# one going diagonally does not flip between rows every step.
const FACE_LEAD := 1.35
# How close one comes to the player before it stops: it is touching them.
const TOUCH := 14.0
const TOUCH_SECONDS := 0.5
const TOUCH_MOST := 5
# How long it takes to die (the death row's five frames), and to flash.
const DYING_SECONDS := 0.45
const FLASH_SECONDS := 0.12
# The stand-ins that take the hits, and how far from the player they reach.
const PROXIES := 96
const PROXY_REACH := 420.0
# Drawn the size of the Field's small slimes.
const DRAW_SCALE := 1.0
# UNDER EVERYTHING STANDING: the player, the monsters and the walls draw over
# the crowd (z 0), the floor under it (-10). One MultiMesh cannot be y-sorted
# among them, and a horde over the player hides the one thing to watch.
const DRAW_Z := -1
# Where a new one may appear: never this near the player.
const SPAWN_CLEAR := 260.0

# Floor it may stand on, and rectangles it must stay out of (the corridor).
var arena: Rect2 = Rect2(0, 0, 1024, 768)
var keep_out: Array[Rect2] = []

# What the run sets as it goes (endlessrun.gd).
var element: int = Element.Type.LIGHT
var max_hp: float = 30.0
var speed: float = 60.0
var touch_damage: int = 6

var px := PackedFloat32Array()
var py := PackedFloat32Array()
var bx := PackedFloat32Array()      # where it stood a step ago
var by := PackedFloat32Array()
var vx := PackedFloat32Array()      # how it is going, px a step
var vy := PackedFloat32Array()
var hp := PackedFloat32Array()
var timer := PackedFloat32Array()   # dying: seconds into it
var flash := PackedFloat32Array()
var phase := PackedFloat32Array()
var facing := PackedByteArray()
var state := PackedByteArray()      # 0 nobody, 1 alive, 2 dying
var hue := PackedFloat32Array()     # each one keeps the colour it was born

var alive: int = 0
var slain: int = 0
var _high: int = 0                  # one past the highest cell ever used
var _free: PackedInt32Array = PackedInt32Array()
var _step_left: float = 0.0
var _touch_left: float = 0.0
var _touching: int = 0
var _grid := PackedInt32Array()
var _gw: int = 1
var _gh: int = 1
var _mesh: MultiMeshInstance2D = null
var _material: ShaderMaterial = null
var _buffer := PackedFloat32Array()
var _proxies: Array = []
# The swarmlings the stand-ins stand on, nearest first (_place_proxies()).
var _held := PackedInt32Array()
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	name = "swarm"
	# One by one: a packed array in a list is a copy, so resizing it there
	# would resize nothing here.
	px.resize(MOST)
	py.resize(MOST)
	bx.resize(MOST)
	by.resize(MOST)
	vx.resize(MOST)
	vy.resize(MOST)
	hp.resize(MOST)
	timer.resize(MOST)
	flash.resize(MOST)
	phase.resize(MOST)
	hue.resize(MOST)
	facing.resize(MOST)
	state.resize(MOST)
	_buffer.resize(MOST * 16)


func _ready() -> void:
	_rng.randomize()
	_build_mesh()
	for i in PROXIES:
		var proxy: Node2D = SwarmProxy.new()
		proxy.set("swarm", self)
		add_child(proxy)
		_proxies.append(proxy)
	set_arena(arena)


func _build_mesh() -> void:
	# A quad the size of one cell of the sheet, its feet at the origin - the
	# Field's slime draws its cell 18 px above its feet.
	var half: float = 24.0 * DRAW_SCALE
	var top: float = -42.0 * DRAW_SCALE
	var bottom: float = 6.0 * DRAW_SCALE
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(-half, top), Vector2(half, top),
		Vector2(half, bottom), Vector2(-half, bottom)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var quad := ArrayMesh.new()
	quad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_2D
	multi.use_colors = true
	multi.use_custom_data = true
	multi.mesh = quad
	multi.instance_count = MOST
	multi.visible_instance_count = 0
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_mesh = MultiMeshInstance2D.new()
	_mesh.name = "drawn"
	_mesh.multimesh = multi
	_mesh.texture = SHEET
	_mesh.material = _material
	_mesh.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_mesh.z_index = DRAW_Z
	add_child(_mesh)


func set_arena(rect: Rect2) -> void:
	arena = rect
	# DRAWN WHEREVER THE ARENA IS ON SCREEN. A MultiMesh filled through its
	# buffer keeps the bounds it had, so up close the crowd was culled away
	# while the wide view still drew it; its bounds are the arena's, always.
	if _mesh != null:
		_mesh.multimesh.custom_aabb = AABB(Vector3(rect.position.x - 64.0, rect.position.y - 64.0, -1.0),
			Vector3(rect.size.x + 128.0, rect.size.y + 128.0, 2.0))
	_gw = maxi(1, int(ceil(rect.size.x / CELL)))
	_gh = maxi(1, int(ceil(rect.size.y / CELL)))
	_grid.resize(_gw * _gh)


func clear() -> void:
	"""Every swarmling gone at once - the run is over."""
	for i in _high:
		state[i] = 0
	alive = 0
	_high = 0
	_free = PackedInt32Array()
	_write_buffer()
	_park_proxies()


# =============================================================================
# BORN AND DYING
# =============================================================================

func spawn(count: int, avoid: Vector2) -> int:
	"""Up to `count` new swarmlings on the arena's edges, none within
	SPAWN_CLEAR of `avoid` (the player). Returns how many came."""
	var made: int = 0
	var colour: float = Element.hue_for(element)
	for n in count:
		if alive >= MOST:
			break
		var spot: Vector2 = _edge_spot(avoid)
		if spot == Vector2.INF:
			break
		var i: int
		if not _free.is_empty():
			i = _free[_free.size() - 1]
			_free.resize(_free.size() - 1)
		elif _high < MOST:
			i = _high
			_high += 1
		else:
			break
		px[i] = spot.x
		py[i] = spot.y
		bx[i] = spot.x
		by[i] = spot.y
		vx[i] = 0.0
		vy[i] = 0.0
		hp[i] = max_hp
		timer[i] = 0.0
		flash[i] = 0.0
		phase[i] = _rng.randf()
		facing[i] = 2
		state[i] = 1
		hue[i] = colour
		alive += 1
		made += 1
	return made


func _edge_spot(avoid: Vector2) -> Vector2:
	var inner: Rect2 = arena.grow(-12.0)
	for attempt in 8:
		var side: int = _rng.randi_range(0, 3)
		var spot: Vector2
		match side:
			0: spot = Vector2(_rng.randf_range(inner.position.x, inner.end.x), inner.position.y)
			1: spot = Vector2(_rng.randf_range(inner.position.x, inner.end.x), inner.end.y)
			2: spot = Vector2(inner.position.x, _rng.randf_range(inner.position.y, inner.end.y))
			_: spot = Vector2(inner.end.x, _rng.randf_range(inner.position.y, inner.end.y))
		if spot.distance_to(avoid) < SPAWN_CLEAR or _kept_out(spot):
			continue
		return spot
	return Vector2.INF


func _kept_out(spot: Vector2) -> bool:
	for rect in keep_out:
		if rect.has_point(spot):
			return true
	return false


func hurt(i: int, amount: float) -> void:
	"""A blow on swarmling `i` (through a stand-in)."""
	if i < 0 or i >= _high or state[i] != 1:
		return
	hp[i] -= amount
	flash[i] = FLASH_SECONDS
	if hp[i] <= 0.0:
		state[i] = 2
		timer[i] = 0.0
		alive -= 1
		slain += 1
		killed.emit(Vector2(px[i], py[i]))


func is_alive(i: int) -> bool:
	return i >= 0 and i < _high and state[i] == 1


# =============================================================================
# EACH FRAME
# =============================================================================

func _process(delta: float) -> void:
	var player: Node2D = get_tree().get_first_node_in_group(&"player") as Node2D
	var target: Vector2 = player.global_position if player != null else arena.get_center()
	var chasing: bool = player != null and player.get("is_dying") != true \
		and arena.has_point(target) and not _kept_out(target)
	_step_left -= delta
	var steps: int = 0
	while _step_left <= 0.0 and steps < 2:
		_step_left += STEP
		_step(target, chasing)
		steps += 1
	if _step_left < -STEP:
		_step_left = 0.0
	if steps > 0:
		_write_buffer()
		_place_proxies()
	_material.set_shader_parameter("blend", clampf(1.0 - _step_left / STEP, 0.0, 1.0))
	# THE TOUCH, counted at each step and dealt on its own clock.
	_touch_left -= delta
	if _touch_left <= 0.0:
		_touch_left = TOUCH_SECONDS
		if chasing and _touching > 0 and player.has_method("take_damage"):
			player.call("take_damage", touch_damage * mini(_touching, TOUCH_MOST), element)


func _physics_process(_delta: float) -> void:
	_move_proxies()


func _step(target: Vector2, chasing: bool) -> void:
	"""One step of the whole crowd: count the grid, then move each one toward
	the player and off where it is thick."""
	_grid.fill(0)
	var ox: float = arena.position.x
	var oy: float = arena.position.y
	var gw: int = _gw
	var gh: int = _gh
	for i in _high:
		if state[i] == 1:
			var gx: int = clampi(int((px[i] - ox) / CELL), 0, gw - 1)
			var gy: int = clampi(int((py[i] - oy) / CELL), 0, gh - 1)
			_grid[gy * gw + gx] += 1
	var left: float = arena.position.x + 6.0
	var right: float = arena.end.x - 6.0
	var top: float = arena.position.y + 6.0
	var bottom: float = arena.end.y - 6.0
	var stride: float = speed * STEP
	var push: float = PUSH * STEP
	var touching: int = 0
	var tx: float = target.x
	var ty: float = target.y
	for i in _high:
		var s: int = state[i]
		if s == 0:
			continue
		if flash[i] > 0.0:
			flash[i] = maxf(0.0, flash[i] - STEP)
		if s == 2:
			timer[i] += STEP
			bx[i] = px[i]
			by[i] = py[i]
			if timer[i] >= DYING_SECONDS:
				state[i] = 0
				_free.append(i)
			continue
		var x: float = px[i]
		var y: float = py[i]
		bx[i] = x
		by[i] = y
		var dx: float = tx - x
		var dy: float = ty - y
		var d: float = sqrt(dx * dx + dy * dy)
		var mx: float = 0.0
		var my: float = 0.0
		var against: bool = false
		if chasing:
			if d <= TOUCH:
				touching += 1
				against = true
			elif d > 0.001:
				# A little sideways wander, its own and slow, so a crowd does
				# not march in ruled lines.
				var wobble: float = sin(phase[i] * 40.0 + float(Time.get_ticks_msec()) * WANDER_RATE) * WANDER
				var nx: float = dx / d
				var ny: float = dy / d
				mx = (nx - ny * wobble) * stride
				my = (ny + nx * wobble) * stride
		var gx2: int = clampi(int((x - ox) / CELL), 0, gw - 1)
		var gy2: int = clampi(int((y - oy) / CELL), 0, gh - 1)
		var here: int = _grid[gy2 * gw + gx2]
		if here > 1:
			var l: int = _grid[gy2 * gw + gx2 - 1] if gx2 > 0 else here
			var r: int = _grid[gy2 * gw + gx2 + 1] if gx2 < gw - 1 else here
			var u: int = _grid[(gy2 - 1) * gw + gx2] if gy2 > 0 else here
			var dn: int = _grid[(gy2 + 1) * gw + gx2] if gy2 < gh - 1 else here
			# Against the player it is shoved half as hard: the ring round
			# them settles instead of churning.
			var shove: float = push * (0.5 if against else 1.0)
			mx += float(l - r) * shove
			my += float(u - dn) * shove
		# Carried from the last step, never a full turn at once.
		mx = lerpf(vx[i], mx, STEER)
		my = lerpf(vy[i], my, STEER)
		vx[i] = mx
		vy[i] = my
		x = clampf(x + mx, left, right)
		y = clampf(y + my, top, bottom)
		for rect in keep_out:
			if rect.has_point(Vector2(x, y)):
				# Out the nearest side.
				# Never out a side that leaves the floor: a corridor walled
				# into the arena's foot has only three.
				var to_left: float = x - rect.position.x if rect.position.x - 0.5 >= left else INF
				var to_right: float = rect.end.x - x if rect.end.x + 0.5 <= right else INF
				var to_top: float = y - rect.position.y if rect.position.y - 0.5 >= top else INF
				var to_bottom: float = rect.end.y - y if rect.end.y + 0.5 <= bottom else INF
				var least: float = minf(minf(to_left, to_right), minf(to_top, to_bottom))
				if least == to_top:
					y = rect.position.y - 0.5
				elif least == to_left:
					x = rect.position.x - 0.5
				elif least == to_right:
					x = rect.end.x + 0.5
				else:
					y = rect.end.y + 0.5
		if absf(mx) > 0.2 or absf(my) > 0.2:
			var sideways: bool = facing[i] <= 1
			if sideways and absf(my) > absf(mx) * FACE_LEAD:
				sideways = false
			elif not sideways and absf(mx) > absf(my) * FACE_LEAD:
				sideways = true
			if sideways:
				facing[i] = 0 if mx > 0.0 else 1
			else:
				facing[i] = 2 if my > 0.0 else 3
		px[i] = x
		py[i] = y
	_touching = touching


func _write_buffer() -> void:
	"""Every cell up to the highest used, into the MultiMesh in one go: the
	transform (where it stands now), the colour (flash, dying, shown) and the
	custom data (the step back, facing and phase, hue)."""
	var buf: PackedFloat32Array = _buffer
	var k: int = 0
	for i in _high:
		var s: int = state[i]
		buf[k] = 1.0
		buf[k + 1] = 0.0
		buf[k + 2] = 0.0
		buf[k + 3] = px[i]
		buf[k + 4] = 0.0
		buf[k + 5] = 1.0
		buf[k + 6] = 0.0
		buf[k + 7] = py[i]
		buf[k + 8] = flash[i] / FLASH_SECONDS if s == 1 else 0.0
		buf[k + 9] = clampf(timer[i] / DYING_SECONDS, 0.01, 1.0) if s == 2 else 0.0
		buf[k + 10] = 0.0
		buf[k + 11] = 1.0 if s != 0 else 0.0
		buf[k + 12] = bx[i] - px[i]
		buf[k + 13] = by[i] - py[i]
		buf[k + 14] = float(facing[i]) + phase[i] * 0.99
		buf[k + 15] = hue[i]
		k += 16
	var multi: MultiMesh = _mesh.multimesh
	# The whole buffer, always: MultiMesh takes one of exactly its size. Past
	# _high it holds old cells, and visible_instance_count draws none of them.
	multi.buffer = buf
	multi.visible_instance_count = _high


# =============================================================================
# THE STAND-INS
# =============================================================================

func _place_proxies() -> void:
	"""Which swarmlings the stand-ins stand on, once a step. A STAND-IN KEEPS
	ITS SWARMLING while it lives and is within PROXY_REACH: what was put on
	one - a bleed biting it - belongs to that swarmling, and a stand-in moved
	to the nearest each step carried a wound from slime to slime (the owner:
	"bleed damage is spreading"). Only a free one takes the nearest not held,
	by distance bands, not a sort - a sort of three thousand is the cost this
	file exists to avoid. _move_proxies() keeps each on its swarmling every
	physics tick."""
	var player: Node2D = get_tree().get_first_node_in_group(&"player") as Node2D
	if player == null or alive == 0:
		_park_proxies()
		return
	var at: Vector2 = player.global_position
	var reach2: float = PROXY_REACH * PROXY_REACH
	if _held.size() != _proxies.size():
		_held.resize(_proxies.size())
		_held.fill(-1)
	var taken := {}
	var empty: int = 0
	for p in _held.size():
		var i: int = _held[p]
		if i >= 0 and state[i] == 1:
			var hx: float = px[i] - at.x
			var hy: float = py[i] - at.y
			if hx * hx + hy * hy <= reach2:
				taken[i] = true
				continue
		_held[p] = -1
		empty += 1
	if empty > 0:
		var bands: Array = [[], [], [], [], [], []]
		var band_size: float = PROXY_REACH / float(bands.size())
		for i in _high:
			if state[i] != 1 or taken.has(i):
				continue
			var dx: float = px[i] - at.x
			var dy: float = py[i] - at.y
			var d2: float = dx * dx + dy * dy
			if d2 > reach2:
				continue
			(bands[mini(bands.size() - 1, int(sqrt(d2) / band_size))] as Array).append(i)
		var p: int = 0
		for band in bands:
			for i in band:
				while p < _held.size() and _held[p] >= 0:
					p += 1
				if p >= _held.size():
					break
				_held[p] = i
	_move_proxies()


func _move_proxies() -> void:
	"""Each stand-in onto its swarmling, where it is drawn this frame; the
	rest out of the way."""
	var blend: float = clampf(1.0 - _step_left / STEP, 0.0, 1.0)
	for p in _proxies.size():
		var proxy: Node2D = _proxies[p]
		var i: int = _held[p] if p < _held.size() else -1
		if i >= 0 and state[i] == 1:
			proxy.call("stand_on", i, Vector2(lerpf(bx[i], px[i], blend), lerpf(by[i], py[i], blend)))
		else:
			proxy.call("stand_on", -1, Vector2.ZERO)


func _park_proxies() -> void:
	_held.resize(_proxies.size())
	_held.fill(-1)
	for proxy in _proxies:
		(proxy as Node2D).call("stand_on", -1, Vector2.ZERO)
