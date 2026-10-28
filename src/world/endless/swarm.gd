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
# ONE SWARM FOR A PARTY (0.93.3). Every game in a party's arena moves its own
# copy of the swarm, and the copies are kept the same by what changes them,
# never by where 3,000 slimes stand (endlessparty.gd passes it):
#   - BORN IN THE SAME SLOTS, AT THE SAME SPOTS. The game leading the run picks
#     the slots (take_slots()) and a seed; spawn_batch() places every slime
#     from that seed alone, so every copy draws the same slime in the same
#     slot. Each slot remembers the batch it was born in (gen).
#   - HIT BY NUMBER. A blow landed here is told as [slot, batch, damage]
#     (struck); one landed elsewhere is applied by hurt_remote(), and only to
#     the slime of that batch - a slot dead and born again since takes
#     nothing. Every copy takes every hit, so every copy's count is the same
#     and each slime dies on every screen.
#   - EACH GOES FOR THE NEAREST. `others` holds where the party's other
#     players stand (drawn by presence); a slime heads for whichever of them,
#     or this game's player, is nearest. Only this game's player is hurt here:
#     each player is hurt by the slimes on their own screen.
# A game that walks in mid-run is sent every slime as it stands
# (export_alive(), import_alive()). The copies drift a few px apart, as each
# game sees the others a tenth of a second late; a slime is its number, and a
# death is a death wherever it is drawn. Alone, none of this is used, and the
# swarm runs as it did. Nothing it does is worth anything to the server yet.
extends Node2D

signal killed(at: Vector2)
## A blow this game landed (not one told by another game): which slot, the
## batch it was born in, the whole damage, and whether it died of it.
signal struck(slot: int, batch: int, damage: int, died: bool)

const SwarmProxy := preload("res://src/world/endless/swarmproxy.gd")
const StatusEffects := preload("res://src/characters/statuseffects.gd")
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
# ROOM OF ITS OWN (0.93.3): in a cell with others, each is eased away from
# the middle of them, this many px a second for each other one there. The
# neighbour cells' counts move a crowd; this keeps slimes in one cell from
# standing on each other - the owner's video showed them stacked in columns,
# a hop drawn through the one above it.
const SPREAD := 22.0
# How many slimes a cell holds before those in it stop pressing on toward
# the player (24 px is about two slimes' room).
const CROWD_ROOM := 2
# AND EACH ITS OWN ROOM, NEAR THE PLAYER (0.93.3): within ROOM_REACH of the
# player - the crowd on screen - every slime keeps ROOM px from every other,
# eased apart up to ROOM_PUSH px a second when two stand on one spot. Found
# through a hash of ROOM-sized cells built each step for those near alone:
# all three thousand, pair by pair, would cost a frame's work in GDScript.
const ROOM := 15.0
const ROOM_PUSH := 80.0
const ROOM_REACH := 260.0
# How close one comes to the player before it stops: it is touching them.
const TOUCH := 14.0
const TOUCH_SECONDS := 0.5
const TOUCH_MOST := 5
# THE LAND'S EFFECT RIDES THE TOUCH (0.93.3, the owner: "we need to really
# feel each elements effect"): a touch that hurts you also puts `touch_effect`
# on you (statuseffects.gd), at most once every EFFECT_GAP seconds - a crowd
# touches you twice a second, and the ice stages would hold you frozen.
const EFFECT_GAP := 1.5
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
# The land's effect on a touch, set at each stage (endlessrun.gd
# touch_effect_for()); &"" for none.
var touch_effect: StringName = &""

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
var gen := PackedInt32Array()       # the batch it was born in (0.93.3)
var elem := PackedByteArray()       # and its land, for a game walking in

# ONE SWARM FOR A PARTY: where the party's other players stand - each slime
# goes for the nearest of them and this game's player. Set each frame by
# endlessparty.gd; empty alone.
var others := PackedVector2Array()

var alive: int = 0
var slain: int = 0
# Of `slain`, the ones this game's own blows finished.
var my_slain: int = 0
# The batch the next spawn() is (alone; a party's leader numbers its own).
var batch: int = 0
var _high: int = 0                  # one past the highest cell ever used
var _free: PackedInt32Array = PackedInt32Array()
var _step_left: float = 0.0
var _touch_left: float = 0.0
var _touching: int = 0
var _effect_left: float = 0.0
var _grid := PackedInt32Array()
# Where the swarmlings in each cell stand, added up (for the middle of them).
var _sum_x := PackedFloat32Array()
var _sum_y := PackedFloat32Array()
# THE ORDER THEY ARE DRAWN IN, back to front (0.93.3): every swarmling not
# gone, by where its feet stand, so one nearer the bottom of the screen is
# drawn over the one behind it, as y-sorting draws everything standing. A
# MultiMesh draws its instances in buffer order; drawn by slot, a slime
# hopping up was drawn under or over its neighbours by chance - "the slimes
# are glitching when they jump". Kept from step to step and put right by an
# insertion sort, which is quick on an order that has barely changed.
var _order := PackedInt32Array()
# The room each near slime is being given this step (_rx, _ry, unit-ish), who
# was near (to clear them next step), and the hash they were found through.
var _rx := PackedFloat32Array()
var _ry := PackedFloat32Array()
var _near := PackedInt32Array()
var _room_head := PackedInt32Array()
var _room_next := PackedInt32Array()
var _gw: int = 1
var _gh: int = 1
var _mesh: MultiMeshInstance2D = null
var _material: ShaderMaterial = null
var _buffer := PackedFloat32Array()
var _proxies: Array = []
# The swarmlings the stand-ins stand on, nearest first (_place_proxies()).
var _held := PackedInt32Array()
var _rng := RandomNumberGenerator.new()
# The party's other players this step, those on the arena's floor (`others`).
var _others_now := PackedVector2Array()


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
	_rx.resize(MOST)
	_ry.resize(MOST)
	_room_next.resize(MOST)
	hp.resize(MOST)
	timer.resize(MOST)
	flash.resize(MOST)
	phase.resize(MOST)
	hue.resize(MOST)
	gen.resize(MOST)
	elem.resize(MOST)
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
	# NOT PHYSICS-INTERPOLATED (0.93.5). The owner, with a video: "they are
	# litterally zipping accross the field", "when they jump their graphics
	# split accross the screen". The project interpolates physics, and Godot
	# then draws a MultiMesh's instance k between where instance k was in the
	# last buffer and where it is in this one - by INDEX. Since 0.93.3 each
	# write is sorted by the feet (_sort_order()), so instance k is a
	# different slime from one write to the next, and every slain or new one
	# shifts all behind it: each step about two in three drawn slimes slid
	# from another slime's spot, half of them over 200 px, for a physics tick
	# (zz/swarmzip, 400 slimes in a fight). The walk between steps is the
	# shader's own (`blend`, from bx/by), so there is nothing for the engine
	# to blend: off on the node and on the MultiMesh, as bulletfield.gd's
	# orbs (12 Oct).
	_mesh.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_mesh)
	RenderingServer.multimesh_set_physics_interpolated(multi.get_rid(), false)


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
	_sum_x.resize(_gw * _gh)
	_sum_y.resize(_gw * _gh)


func clear() -> void:
	"""Every swarmling gone at once - the run is over."""
	for i in _high:
		state[i] = 0
	alive = 0
	_high = 0
	_free = PackedInt32Array()
	_order = PackedInt32Array()
	_write_buffer()
	_park_proxies()


# =============================================================================
# BORN AND DYING
# =============================================================================

func spawn(count: int, avoid: Vector2) -> int:
	"""Up to `count` new swarmlings on the arena's edges, none within
	SPAWN_CLEAR of `avoid` (the player). Returns how many came. Alone: a
	party's leader uses take_slots() and spawn_batch(), which every copy can
	repeat."""
	var made: int = 0
	batch += 1
	for n in count:
		if alive >= MOST:
			break
		var spot: Vector2 = _edge_spot(avoid)
		if spot == Vector2.INF:
			break
		var slots: PackedInt32Array = take_slots(1)
		if slots.is_empty():
			break
		_place(slots[0], spot, _rng.randf(), batch, max_hp, element)
		made += 1
	return made


func take_slots(count: int) -> PackedInt32Array:
	"""(The run's leader.) Up to `count` empty slots, taken: the freed first,
	then new ones. A slot not used after all goes back by give_back()."""
	var out := PackedInt32Array()
	while out.size() < count and alive + out.size() < MOST:
		if not _free.is_empty():
			var i: int = _free[_free.size() - 1]
			_free.resize(_free.size() - 1)
			if state[i] != 0 or out.has(i):
				continue
			out.append(i)
		elif _high < MOST:
			out.append(_high)
			_high += 1
		else:
			break
	return out


func give_back(slots: PackedInt32Array) -> void:
	for i in slots:
		if i >= 0 and i < _high and state[i] == 0:
			_free.append(i)


func rebuild_free() -> void:
	"""Every empty slot below the highest used, free: a game that has only
	followed another's slots knows none of its own (it leads now)."""
	_free = PackedInt32Array()
	for i in _high:
		if state[i] == 0:
			_free.append(i)


func spawn_batch(number: int, seed_value: int, slots: PackedInt32Array, avoid: PackedVector2Array,
		health: float, land: int) -> PackedInt32Array:
	"""ONE SWARM FOR A PARTY: slimes into exactly these slots, each at a spot
	drawn from `seed_value` alone, clear of every point in `avoid` - so every
	game given the same batch makes the same slimes. A slot whose spot could
	not be found stays empty, on every copy alike. Returns the slots used."""
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var used := PackedInt32Array()
	for i in slots:
		if i < 0 or i >= MOST:
			continue
		var spot: Vector2 = _edge_spot_from(rng, avoid)
		var sway: float = rng.randf()
		if spot == Vector2.INF:
			continue
		if i >= _high:
			for k in range(_high, i):
				_free.append(k)
			_high = i + 1
		_place(i, spot, sway, number, health, land)
		used.append(i)
	batch = maxi(batch, number)
	return used


func _place(i: int, spot: Vector2, sway: float, number: int, health: float, land: int) -> void:
	if state[i] == 1:
		alive -= 1
	px[i] = spot.x
	py[i] = spot.y
	bx[i] = spot.x
	by[i] = spot.y
	vx[i] = 0.0
	vy[i] = 0.0
	_order.append(i)
	hp[i] = health
	timer[i] = 0.0
	flash[i] = 0.0
	phase[i] = sway
	facing[i] = 2
	state[i] = 1
	hue[i] = Element.hue_for(land)
	gen[i] = number
	elem[i] = land
	alive += 1


func _edge_spot(avoid: Vector2) -> Vector2:
	return _edge_spot_from(_rng, PackedVector2Array([avoid]))


func _edge_spot_from(rng: RandomNumberGenerator, avoid: PackedVector2Array) -> Vector2:
	var inner: Rect2 = arena.grow(-12.0)
	for attempt in 8:
		var side: int = rng.randi_range(0, 3)
		var spot: Vector2
		match side:
			0: spot = Vector2(rng.randf_range(inner.position.x, inner.end.x), inner.position.y)
			1: spot = Vector2(rng.randf_range(inner.position.x, inner.end.x), inner.end.y)
			2: spot = Vector2(inner.position.x, rng.randf_range(inner.position.y, inner.end.y))
			_: spot = Vector2(inner.end.x, rng.randf_range(inner.position.y, inner.end.y))
		if _kept_out(spot):
			continue
		var clear: bool = true
		for point in avoid:
			if spot.distance_to(point) < SPAWN_CLEAR:
				clear = false
				break
		if clear:
			return spot
	return Vector2.INF


func _kept_out(spot: Vector2) -> bool:
	for rect in keep_out:
		if rect.has_point(spot):
			return true
	return false


func hurt(i: int, amount: float) -> void:
	"""A blow on swarmling `i` (through a stand-in), landed by this game: told
	(struck) so a party's other copies take it too. Whole points, at least
	one, so every copy subtracts the same."""
	if i < 0 or i >= _high or state[i] != 1:
		return
	var dealt: int = maxi(1, roundi(amount))
	var died: bool = _take(i, float(dealt))
	if died:
		my_slain += 1
	struck.emit(i, gen[i], dealt, died)


func hurt_remote(i: int, number: int, amount: int) -> bool:
	"""A blow another game in the party landed on the slime of batch `number`
	in slot `i`. Nothing if that slime is gone (dead, or the slot born again
	since). Returns whether it died of it."""
	if i < 0 or i >= _high or state[i] != 1 or gen[i] != number or amount < 1:
		return false
	return _take(i, float(amount))


func _take(i: int, amount: float) -> bool:
	hp[i] -= amount
	flash[i] = FLASH_SECONDS
	if hp[i] > 0.0:
		return false
	state[i] = 2
	timer[i] = 0.0
	alive -= 1
	slain += 1
	killed.emit(Vector2(px[i], py[i]))
	return true


# Each slime a game walking in is sent: slot, batch, health, x, y, land.
const RECORD := 6


func export_alive() -> PackedInt32Array:
	"""Every living slime as whole numbers, RECORD to a slime, for a game that
	walked into the arena mid-run."""
	var out := PackedInt32Array()
	for i in _high:
		if state[i] == 1:
			out.append_array(PackedInt32Array([i, gen[i], maxi(1, ceili(hp[i])),
				roundi(px[i]), roundi(py[i]), elem[i]]))
	return out


func import_alive(records: PackedInt32Array) -> int:
	"""(A game that walked in.) The swarm as the leader's game has it: every
	slime it is sent, in its slot, and nothing else. Returns how many."""
	clear()
	var n: int = 0
	for k in range(0, records.size() - RECORD + 1, RECORD):
		var i: int = records[k]
		if i < 0 or i >= MOST:
			continue
		if i >= _high:
			_high = i + 1
		_place(i, Vector2(records[k + 3], records[k + 4]), fposmod(float(i) * 0.618034, 1.0),
			records[k + 1], float(records[k + 2]), records[k + 5])
		batch = maxi(batch, records[k + 1])
		n += 1
	rebuild_free()
	return n


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
	_others_now = PackedVector2Array()
	for point in others:
		if arena.has_point(point) and not _kept_out(point):
			_others_now.append(point)
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
	_effect_left = maxf(0.0, _effect_left - delta)
	if _touch_left <= 0.0:
		_touch_left = TOUCH_SECONDS
		if chasing and _touching > 0 and player.has_method("take_damage"):
			var hit: int = touch_damage * mini(_touching, TOUCH_MOST)
			player.call("take_damage", hit, element)
			touch_effect_on(player, hit)


func touch_effect_on(player: Node, hit: int) -> bool:
	"""The land's effect, on a touch that hurt (see EFFECT_GAP). True when it
	went on."""
	if touch_effect == &"" or _effect_left > 0.0 or player == null or not is_instance_valid(player):
		return false
	_effect_left = EFFECT_GAP
	return StatusEffects.apply_to(player, touch_effect, hit)


func _physics_process(_delta: float) -> void:
	_move_proxies()


func _step(target: Vector2, chasing: bool) -> void:
	"""One step of the whole crowd: count the grid, then move each one toward
	the player and off where it is thick."""
	_grid.fill(0)
	_sum_x.fill(0.0)
	_sum_y.fill(0.0)
	var ox: float = arena.position.x
	var oy: float = arena.position.y
	var gw: int = _gw
	var gh: int = _gh
	# The near ones' hash: ROOM-sized cells over the square round the player.
	for i in _near:
		_rx[i] = 0.0
		_ry[i] = 0.0
	var near := PackedInt32Array()
	var side: int = int(ceil(2.0 * ROOM_REACH / ROOM)) + 1
	_room_head.resize(side * side)
	_room_head.fill(-1)
	var hx: float = target.x - ROOM_REACH
	var hy: float = target.y - ROOM_REACH
	var reach2: float = ROOM_REACH * ROOM_REACH
	for i in _high:
		if state[i] == 1:
			var gx: int = clampi(int((px[i] - ox) / CELL), 0, gw - 1)
			var gy: int = clampi(int((py[i] - oy) / CELL), 0, gh - 1)
			var cell_at: int = gy * gw + gx
			_grid[cell_at] += 1
			_sum_x[cell_at] += px[i]
			_sum_y[cell_at] += py[i]
			var nx0: float = px[i] - target.x
			var ny0: float = py[i] - target.y
			if nx0 * nx0 + ny0 * ny0 <= reach2:
				var room_at: int = clampi(int((py[i] - hy) / ROOM), 0, side - 1) * side \
					+ clampi(int((px[i] - hx) / ROOM), 0, side - 1)
				_room_next[i] = _room_head[room_at]
				_room_head[room_at] = i
				near.append(i)
	_near = near
	_make_room(hx, hy, side)
	var left: float = arena.position.x + 6.0
	var right: float = arena.end.x - 6.0
	var top: float = arena.position.y + 6.0
	var bottom: float = arena.end.y - 6.0
	var stride: float = speed * STEP
	var push: float = PUSH * STEP
	var spread: float = SPREAD * STEP
	var touching: int = 0
	var tx: float = target.x
	var ty: float = target.y
	var others_now: PackedVector2Array = _others_now
	var n_others: int = others_now.size()
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
		# THE NEAREST PLAYER: this game's, or one of the party's others.
		var dx: float = tx - x
		var dy: float = ty - y
		var best: float = dx * dx + dy * dy if chasing else INF
		var mine: bool = chasing
		if n_others > 0:
			for o in n_others:
				var odx: float = others_now[o].x - x
				var ody: float = others_now[o].y - y
				var od2: float = odx * odx + ody * ody
				if od2 < best:
					best = od2
					dx = odx
					dy = ody
					mine = false
		var d: float = sqrt(best) if best < INF else 0.0
		var mx: float = 0.0
		var my: float = 0.0
		var gx2: int = clampi(int((x - ox) / CELL), 0, gw - 1)
		var gy2: int = clampi(int((y - oy) / CELL), 0, gh - 1)
		var here: int = _grid[gy2 * gw + gx2]
		var against: bool = false
		if best < INF:
			if d <= TOUCH:
				# Only this game's player is hurt here (each by their own copy).
				if mine:
					touching += 1
				against = true
			elif d > 0.001:
				# A little sideways wander, its own and slow, so a crowd does
				# not march in ruled lines.
				var wobble: float = sin(phase[i] * 40.0 + float(Time.get_ticks_msec()) * WANDER_RATE) * WANDER
				var nx: float = dx / d
				var ny: float = dy / d
				# IN A CROWD IT WAITS: past CROWD_ROOM in its cell it presses
				# on less, and not at all from CROWD_ROOM + 2 - so a horde
				# stands in ranks round the player instead of all of it
				# squeezing onto the same few px.
				var press: float = clampf(float(CROWD_ROOM + 2 - here) / 2.0, 0.0, 1.0)
				mx = (nx - ny * wobble) * stride * press
				my = (ny + nx * wobble) * stride * press
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
			# Away from the middle of the others in its cell; one standing on
			# that very spot goes its own way, the same way every step.
			var cell_here: int = gy2 * gw + gx2
			var ax: float = x - _sum_x[cell_here] / float(here)
			var ay: float = y - _sum_y[cell_here] / float(here)
			var apart: float = sqrt(ax * ax + ay * ay)
			if apart < 0.05:
				ax = cos(phase[i] * TAU)
				ay = sin(phase[i] * TAU)
				apart = 1.0
			mx += ax / apart * spread * float(here - 1)
			my += ay / apart * spread * float(here - 1)
		# Its own room, if it is near (_make_room()).
		mx += _rx[i] * ROOM_PUSH * STEP
		my += _ry[i] * ROOM_PUSH * STEP
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


func _make_room(hx: float, hy: float, side: int) -> void:
	"""For each near slime, the way out of the others within ROOM of it,
	each weighed by how far inside ROOM it is (0 at the edge, 1 on the same
	spot) - two on one spot part along their own phases, the same way each
	step, so nothing shakes."""
	var room2: float = ROOM * ROOM
	for i in _near:
		var x: float = px[i]
		var y: float = py[i]
		var cx: int = clampi(int((x - hx) / ROOM), 0, side - 1)
		var cy: int = clampi(int((y - hy) / ROOM), 0, side - 1)
		var sx: float = 0.0
		var sy: float = 0.0
		for row in range(maxi(0, cy - 1), mini(side, cy + 2)):
			for col in range(maxi(0, cx - 1), mini(side, cx + 2)):
				var j: int = _room_head[row * side + col]
				while j >= 0:
					if j != i:
						var dx: float = x - px[j]
						var dy: float = y - py[j]
						var d2: float = dx * dx + dy * dy
						if d2 < room2:
							var d: float = sqrt(d2)
							if d < 0.01:
								var way: float = (phase[i] - phase[j]) * TAU
								dx = cos(way)
								dy = sin(way)
								d = 1.0
							var inside: float = (ROOM - minf(d, ROOM)) / ROOM
							sx += dx / d * inside
							sy += dy / d * inside
					j = _room_next[j]
		_rx[i] = clampf(sx, -1.5, 1.5)
		_ry[i] = clampf(sy, -1.5, 1.5)


func _write_buffer() -> void:
	"""Every swarmling not gone, back to front (_sort_order()), into the
	MultiMesh in one go: the transform (where it stands now), the colour
	(flash, dying, shown) and the custom data (the step back, facing and
	phase, hue)."""
	_sort_order()
	var buf: PackedFloat32Array = _buffer
	var k: int = 0
	for i in _order:
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
		buf[k + 11] = 1.0
		buf[k + 12] = bx[i] - px[i]
		buf[k + 13] = by[i] - py[i]
		buf[k + 14] = float(facing[i]) + phase[i] * 0.99
		buf[k + 15] = hue[i]
		k += 16
	var multi: MultiMesh = _mesh.multimesh
	# The whole buffer, always: MultiMesh takes one of exactly its size. Past
	# the order's end it holds old cells, and visible_instance_count draws
	# none of them.
	multi.buffer = buf
	multi.visible_instance_count = _order.size()


func _sort_order() -> void:
	"""_order without the gone, back to front by where each stands: an
	insertion sort, in place, so a crowd that has moved a few px since the
	last step costs about one pass."""
	var order: PackedInt32Array = _order
	_order = PackedInt32Array()
	# Once each: a slot freed and born again between two writes is in the
	# order twice.
	var seen := PackedByteArray()
	seen.resize(_high)
	var kept: int = 0
	for i in order:
		if state[i] != 0 and seen[i] == 0:
			seen[i] = 1
			order[kept] = i
			kept += 1
	order.resize(kept)
	for k in range(1, kept):
		var i: int = order[k]
		var at: float = py[i]
		var j: int = k - 1
		while j >= 0 and py[order[j]] > at:
			order[j + 1] = order[j]
			j -= 1
		order[j + 1] = i
	_order = order


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
