# crownedphases.gd - THE CROWNED, REMADE, step 2 (0.134.1): its last three
# phases and the lying room, from the commit folder's CROWNED_PLAN.txt. The
# owner, of the plan: "sounds good".
#
# A child of crownedfight.gd, which steps it while the fight is on with the
# boss's share of health left. Every game runs its own, for its own player,
# as the floor's hazards are (descentlands.gd): nothing new on the wire.
#
#   2. THE SEALING (below SEALING_FROM, the mage's chapter): meteors fall where
#      you stand (descentlands.gd "meteor": a warning circle, a fireball, a
#      scorch), METEOR_GAP apart; and the lava creeps in from the walls - the
#      floor taken away ring by ring (LAVA_TILE, the town's own bubbling lava
#      under it), to LAVA_MOST rings and back (lava_depth_at()), its front
#      glowing before it comes. Lava burns (LAVA_TIMES of a hazard).
#   3. THE TRAP (below TRAP_FROM, the warrior's): it calls a horde - the
#      Endless's swarm (swarm.gd), HORDE_CROWD slimes (HORDE_PHONE on a
#      phone, endlessrun.gd on_phone()), of every land - while an X of lasers
#      crosses the room every TRAP_LASER_GAP (descentlands.gd cross_lasers()).
#   4. THE TEAR (below TEAR_FROM, the cloth's): pieces of the floor
#      (TEAR_PIECE square) crack (TEAR_WARN) and fall into the rift beneath
#      (crownedrift.gd shows through), TEAR_COUNT every TEAR_GAP - one where
#      you stand - and knit back after TEAR_OPEN. Fall in: TEAR_TIMES of a
#      hazard, and you climb out on the nearest solid floor. The Crowned
#      flickers through all seven lands (FLICKER_SECONDS): its kit and its
#      colour change each time.
#
# THE LYING ROOM, phases 2 to 4: LIE_SHARE of what warns before it falls is an
# illusion (descentlands.gd false_share - the circle shimmers); and every
# LIE_GAP or so the walls shimmer and fade a moment, or the floor washes in
# the wrong land's colour.
#
# When the fight ends (the boss falls or turns away), end() puts the room
# back: the floor whole, the lava gone, the horde gone, the walls solid.
#
# No class_name: preload it by path.
extends Node2D

const RiftScript := preload("res://src/world/crowned/crownedrift.gd")
const StatusEffects := preload("res://src/characters/statuseffects.gd")
const SwarmScript := preload("res://src/world/endless/swarm.gd")
const EndlessRunScript := preload("res://src/world/endless/endlessrun.gd")

const SEALING_FROM := 0.75
const TRAP_FROM := 0.5
const TEAR_FROM := 0.25
const NAMES := {2: "The Sealing", 3: "The Trap", 4: "The Tear"}

const METEOR_GAP := 2.0
const METEOR_SECOND := 0.4
const LAVA_TILE := 32
const LAVA_CELL := Vector2i(0, 5)
const LAVA_MOST := 5
const LAVA_RISE := 1.4
const LAVA_HOLD := 4.0
const LAVA_FALL := 0.8
const LAVA_REST := 3.0
const LAVA_TIMES := 0.8
const LAVA_WARN := 1.0

const HORDE_CROWD := 300
const HORDE_PHONE := 150
const HORDE_RATE := 60.0
const HORDE_HP := 90.0
const HORDE_SPEED := 85.0
const HORDE_TOUCH := 9
const HORDE_RECOLOUR := 4.0
const TRAP_LASER_GAP := 5.0
const TRAP_LASER_FIRST := 2.0
const BACK_WALL_GAP := 6.0

const TEAR_PIECE := 64
# Lava cells along a tear piece's side, and floor cells along a lava cell's.
const TEAR_PER := 2
const FLOOR_PER := 2
const TEAR_GAP := 2.4
const TEAR_COUNT := 2
const TEAR_MOST := 10
const TEAR_WARN := 1.4
const TEAR_OPEN := 7.0
const TEAR_DROP := 0.5
const TEAR_TIMES := 2.0
const FLICKER_SECONDS := 1.6

const LIE_SHARE := 0.25
const LIE_GAP_LEAST := 2.5
const LIE_GAP_MOST := 5.0
const LIE_WALLS := 3

const LANDS := [Element.Type.LIGHT, Element.Type.WIND, Element.Type.WATER, Element.Type.ICE,
	Element.Type.EARTH, Element.Type.FIRE, Element.Type.DARK]

# Set by crownedfight.gd.
var fight: Node2D = null
var lands: Node2D = null
var room: Rect2 = Rect2()
var ground: TileMapLayer = null

var phase: int = 0
var phase_clock: float = 0.0
var lava: TileMapLayer = null
var lava_depth: int = 0
# Ground cells taken away, and what they held: Vector2i -> [source, atlas, alternative].
var _taken: Dictionary = {}
var _flooded: Dictionary = {}
var swarm: Node2D = null
# Tear pieces: Vector2i -> {"t": seconds, "open": bool}.
var tears: Dictionary = {}
var falls: int = 0
var lies: int = 0
var _meteor_left: float = 0.0
var _laser_left: float = 0.0
var _horde_owed: float = 0.0
var _recolour_left: float = 0.0
var _tear_left: float = 0.0
var _flicker_left: float = 0.0
var _lie_left: float = LIE_GAP_LEAST
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


static func phase_for(share: float) -> int:
	"""Which phase a boss with `share` of its health left is in."""
	if share > SEALING_FROM:
		return 1
	if share > TRAP_FROM:
		return 2
	if share > TEAR_FROM:
		return 3
	return 4


func step(delta: float, share: float) -> void:
	var want: int = phase_for(share)
	if want != phase:
		enter(want)
	phase_clock += delta
	var me: Node2D = fight.call("_player") as Node2D if fight != null else null
	match phase:
		2:
			_step_sealing(delta, me)
		3:
			_step_trap(delta, me)
		4:
			_step_tear(delta, me)
	if phase >= 2:
		_step_lies(delta)
	queue_redraw()


func enter(next: int) -> void:
	"""Into phase `next`: what the last one left is cleared, the new one set."""
	var last: int = phase
	phase = next
	phase_clock = 0.0
	if last == 2:
		set_lava_depth(0)
	if last == 3:
		_clear_horde()
	if last == 4:
		knit_all()
	if lands != null:
		lands.set("false_share", LIE_SHARE if next >= 2 else 0.0)
		lands.set("env_floor", maxi(int(lands.get("env_floor")), 4))
	var boss: Node2D = fight.get("boss") if fight != null else null
	match next:
		2:
			_meteor_left = 1.0
			_mood(Element.Type.FIRE, boss)
		3:
			_laser_left = TRAP_LASER_FIRST
			_horde_owed = 0.0
			_recolour_left = 0.0
			_mood(Element.Type.DARK, boss)
		4:
			_tear_left = 1.0
			_flicker_left = 0.0
			_mood(Element.Type.DARK, boss)
	if fight != null and NAMES.has(next):
		fight.call("say", str(NAMES[next]))


func _mood(land: int, boss: Node2D) -> void:
	"""The boss in `land`, the floor washed and the weather falling in it."""
	if boss != null and is_instance_valid(boss):
		boss.set("crown_land", land)
		fight.call("_tint_boss", land)
	fight.call("mood", land)


func end() -> void:
	"""The fight over: the room put back."""
	set_lava_depth(0)
	knit_all()
	_clear_horde()
	if lands != null:
		lands.set("false_share", 0.0)
	for wall in _walls():
		(wall as CanvasItem).modulate = Color(1, 1, 1, 1)
	phase = 0
	queue_redraw()


# =============================================================================
# THE SEALING
# =============================================================================

func _step_sealing(delta: float, me: Node2D) -> void:
	_meteor_left -= delta
	if _meteor_left <= 0.0 and me != null and lands != null:
		_meteor_left = METEOR_GAP
		lands.call("spawn_env", "meteor", me)
		if _rng.randf() < METEOR_SECOND:
			lands.call("spawn_env", "meteor", me)
	set_lava_depth(lava_depth_at(phase_clock))
	if me != null and in_lava(_feet(me)) and lands != null:
		lands.call("_env_hit", me, LAVA_TIMES, Element.Type.FIRE, StatusEffects.BURN, _feet(me))


static func lava_depth_at(seconds: float) -> int:
	"""How many rings of the floor the lava holds `seconds` into the Sealing:
	rising a ring every LAVA_RISE to LAVA_MOST, held LAVA_HOLD, falling a ring
	every LAVA_FALL, gone for LAVA_REST, and again."""
	var rise: float = LAVA_RISE * LAVA_MOST
	var fall: float = LAVA_FALL * LAVA_MOST
	var t: float = fmod(maxf(0.0, seconds), rise + LAVA_HOLD + fall + LAVA_REST)
	if t < rise:
		return int(floor(t / LAVA_RISE))
	if t < rise + LAVA_HOLD:
		return LAVA_MOST
	if t < rise + LAVA_HOLD + fall:
		return LAVA_MOST - int(floor((t - rise - LAVA_HOLD) / LAVA_FALL)) - 1
	return 0


func _lava_span() -> Rect2i:
	"""The lava cells (LAVA_TILE, from the ground's corner) whose middles are
	on the room's floor."""
	var origin: Vector2 = ground.global_position if ground != null else Vector2.ZERO
	var x0: int = ceili((room.position.x - origin.x - LAVA_TILE / 2.0) / LAVA_TILE)
	var y0: int = ceili((room.position.y - origin.y - LAVA_TILE / 2.0) / LAVA_TILE)
	var x1: int = floori((room.end.x - origin.x - LAVA_TILE / 2.0) / LAVA_TILE)
	var y1: int = floori((room.end.y - origin.y - LAVA_TILE / 2.0) / LAVA_TILE)
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)


func ring_of(cell: Vector2i) -> int:
	"""How many rings in from the walls a lava cell is (0: against them)."""
	var span: Rect2i = _lava_span()
	return mini(mini(cell.x - span.position.x, span.end.x - 1 - cell.x),
		mini(cell.y - span.position.y, span.end.y - 1 - cell.y))


func lava_cell_at(at: Vector2) -> Vector2i:
	var origin: Vector2 = ground.global_position if ground != null else Vector2.ZERO
	return Vector2i(floori((at.x - origin.x) / LAVA_TILE), floori((at.y - origin.y) / LAVA_TILE))


func in_lava(at: Vector2) -> bool:
	return _flooded.has(lava_cell_at(at))


func set_lava_depth(depth: int) -> void:
	"""The lava holding `depth` rings of the floor: the floor taken from the
	cells it reaches, given back to those it leaves."""
	if depth == lava_depth:
		return
	lava_depth = depth
	if depth > 0 and lava == null:
		_make_lava()
	var span: Rect2i = _lava_span()
	var want: Dictionary = {}
	if depth > 0:
		for y in range(span.position.y, span.end.y):
			for x in range(span.position.x, span.end.x):
				var cell := Vector2i(x, y)
				if ring_of(cell) < depth:
					want[cell] = true
	for cell in _flooded.keys():
		if not want.has(cell):
			_flooded.erase(cell)
			if lava != null:
				lava.erase_cell(cell)
			if not _torn_at(cell):
				_give_back(_ground_cells(cell))
	for cell in want.keys():
		if not _flooded.has(cell):
			_flooded[cell] = true
			lava.set_cell(cell, 0, LAVA_CELL)
			_take(_ground_cells(cell))


func _make_lava() -> void:
	lava = TileMapLayer.new()
	lava.name = "crownlava"
	lava.tile_set = RiftScript.lava_tiles()
	lava.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	lava.z_index = (ground.z_index - 1) if ground != null else -11
	lava.position = ground.position if ground != null else Vector2.ZERO
	var holder: Node = ground.get_parent() if ground != null else self
	holder.add_child(lava)


func _ground_cells(lava_cell: Vector2i) -> Array:
	"""The four floor cells under one lava cell."""
	var cells: Array = []
	for dy in FLOOR_PER:
		for dx in FLOOR_PER:
			cells.append(Vector2i(lava_cell.x * FLOOR_PER + dx, lava_cell.y * FLOOR_PER + dy))
	return cells


func _take(cells: Array) -> void:
	if ground == null:
		return
	for cell in cells:
		if _taken.has(cell):
			continue
		var source: int = ground.get_cell_source_id(cell)
		if source < 0:
			continue
		_taken[cell] = [source, ground.get_cell_atlas_coords(cell), ground.get_cell_alternative_tile(cell)]
		ground.erase_cell(cell)


func _give_back(cells: Array) -> void:
	if ground == null:
		return
	for cell in cells:
		if not _taken.has(cell):
			continue
		var held: Array = _taken[cell]
		ground.set_cell(cell, int(held[0]), held[1], int(held[2]))
		_taken.erase(cell)


# =============================================================================
# THE TRAP
# =============================================================================

func horde_size() -> int:
	return HORDE_PHONE if EndlessRunScript.on_phone() else HORDE_CROWD


func _step_trap(delta: float, me: Node2D) -> void:
	if swarm == null:
		_make_horde()
	_recolour_left -= delta
	if _recolour_left <= 0.0:
		_recolour_left = HORDE_RECOLOUR
		swarm.set("element", int(LANDS[_rng.randi() % LANDS.size()]))
	var short: int = horde_size() - int(swarm.get("alive"))
	if short > 0:
		_horde_owed += HORDE_RATE * delta
		var count: int = mini(short, int(_horde_owed))
		if count > 0:
			_horde_owed -= float(count)
			swarm.call("spawn", count, me.global_position if me != null else room.get_center())
	_laser_left -= delta
	if _laser_left <= 0.0 and me != null and lands != null:
		_laser_left = TRAP_LASER_GAP
		var first: int = int(LANDS[_rng.randi() % LANDS.size()])
		var second: int = int(LANDS[_rng.randi() % LANDS.size()])
		lands.call("cross_lasers", me, first, second)


func _make_horde() -> void:
	swarm = SwarmScript.new()
	swarm.name = "crownhorde"
	swarm.set("arena", room)
	swarm.set("max_hp", HORDE_HP)
	swarm.set("speed", HORDE_SPEED)
	swarm.set("touch_damage", HORDE_TOUCH)
	swarm.set("element", Element.Type.DARK)
	swarm.call("draw_in_front_of", room.position.y - BACK_WALL_GAP)
	var holder: Node = null
	if fight != null and fight.get_parent() != null:
		holder = fight.get_parent().get_node_or_null("ysortworld/groundeffects")
	(holder if holder != null else self).add_child(swarm)


func _clear_horde() -> void:
	if swarm != null and is_instance_valid(swarm):
		swarm.call("clear")
		swarm.queue_free()
	swarm = null


# =============================================================================
# THE TEAR
# =============================================================================

func _step_tear(delta: float, me: Node2D) -> void:
	for piece in tears.keys():
		var held: Dictionary = tears[piece]
		held["t"] = float(held["t"]) + delta
		if not bool(held["open"]) and float(held["t"]) >= TEAR_WARN:
			held["open"] = true
			for cell in _piece_lava_cells(piece):
				if _flooded.has(cell):
					continue
				_take(_ground_cells(cell))
		elif bool(held["open"]) and float(held["t"]) >= TEAR_WARN + TEAR_OPEN:
			_knit(piece)
	_tear_left -= delta
	if _tear_left <= 0.0:
		_tear_left = TEAR_GAP
		var made: int = 0
		if me != null:
			if cut(piece_at(_feet(me))):
				made += 1
		var tries: int = 0
		while made < TEAR_COUNT and tries < 20:
			tries += 1
			var span: Rect2i = _piece_span()
			if cut(Vector2i(_rng.randi_range(span.position.x, span.end.x - 1), _rng.randi_range(span.position.y, span.end.y - 1))):
				made += 1
	if me != null and fell_in(_feet(me)):
		_climb_out(me)
	_flicker_left -= delta
	if _flicker_left <= 0.0:
		_flicker_left = FLICKER_SECONDS
		var boss: Node2D = fight.get("boss") if fight != null else null
		if boss != null and is_instance_valid(boss):
			var now: int = int(boss.get("crown_land"))
			var land: int = now
			while land == now:
				land = int(LANDS[_rng.randi() % LANDS.size()])
			_mood(land, boss)


func _piece_span() -> Rect2i:
	"""The tear pieces over the room's floor (each TEAR_PIECE square, in lava
	cells from the lava's own span)."""
	var span: Rect2i = _lava_span()
	return Rect2i(0, 0, floori(float(span.size.x) / TEAR_PER), floori(float(span.size.y) / TEAR_PER))


func _piece_lava_cells(piece: Vector2i) -> Array:
	var span: Rect2i = _lava_span()
	var cells: Array = []
	for dy in TEAR_PER:
		for dx in TEAR_PER:
			cells.append(Vector2i(span.position.x + piece.x * TEAR_PER + dx, span.position.y + piece.y * TEAR_PER + dy))
	return cells


func piece_rect(piece: Vector2i) -> Rect2:
	var cells: Array = _piece_lava_cells(piece)
	var origin: Vector2 = ground.global_position if ground != null else Vector2.ZERO
	var first: Vector2i = cells[0]
	return Rect2(origin + Vector2(first * LAVA_TILE), Vector2(TEAR_PIECE, TEAR_PIECE))


func piece_at(at: Vector2) -> Vector2i:
	var span: Rect2i = _lava_span()
	var cell: Vector2i = lava_cell_at(at)
	return Vector2i(floori(float(cell.x - span.position.x) / TEAR_PER), floori(float(cell.y - span.position.y) / TEAR_PER))


func cut(piece: Vector2i) -> bool:
	"""Piece `piece` starts to crack, if it is on the floor, whole, and fewer
	than TEAR_MOST are cut."""
	if tears.has(piece) or tears.size() >= TEAR_MOST or not _piece_span().has_point(piece):
		return false
	tears[piece] = {"t": 0.0, "open": false, "seed": _rng.randi()}
	return true


func _torn_at(lava_cell: Vector2i) -> bool:
	for piece in tears.keys():
		if bool(tears[piece]["open"]) and lava_cell in _piece_lava_cells(piece):
			return true
	return false


func fell_in(at: Vector2) -> bool:
	var piece: Vector2i = piece_at(at)
	return tears.has(piece) and bool(tears[piece]["open"]) and piece_rect(piece).has_point(at)


func _climb_out(me: Node2D) -> void:
	"""Fallen through: hurt, and up again on the nearest solid floor."""
	var at: Vector2 = _feet(me)
	falls += 1
	if lands != null:
		lands.set("_touch_left", 0.0)
		lands.call("_env_hit", me, TEAR_TIMES, Element.Type.DARK, StatusEffects.WITHER, at)
	var best: Vector2 = room.get_center()
	var best_d: float = INF
	var hole: Rect2 = piece_rect(piece_at(at))
	for k in 16:
		var out: Vector2 = hole.get_center() + Vector2.from_angle(TAU * float(k) / 16.0) * (TEAR_PIECE * 0.75 + 10.0)
		if not room.grow(-12.0).has_point(out) or fell_in(out) or in_lava(out):
			continue
		var d: float = out.distance_squared_to(at)
		if d < best_d:
			best_d = d
			best = out
	me.global_position = best - (_feet(me) - me.global_position)
	me.reset_physics_interpolation()


func _knit(piece: Vector2i) -> void:
	tears.erase(piece)
	for cell in _piece_lava_cells(piece):
		if not _flooded.has(cell):
			_give_back(_ground_cells(cell))


func knit_all() -> void:
	for piece in tears.keys():
		_knit(piece)
	tears = {}


# =============================================================================
# THE LYING ROOM
# =============================================================================

func _step_lies(delta: float) -> void:
	_lie_left -= delta
	if _lie_left > 0.0:
		return
	_lie_left = _rng.randf_range(LIE_GAP_LEAST, LIE_GAP_MOST)
	lies += 1
	if _rng.randf() < 0.5:
		var walls: Array = _walls()
		for k in mini(LIE_WALLS, walls.size()):
			var wall: CanvasItem = walls[_rng.randi() % walls.size()]
			var shimmer: Tween = wall.create_tween()
			shimmer.tween_property(wall, "modulate", Color(0.75, 0.55, 1.0, 0.3), 0.12)
			shimmer.tween_property(wall, "modulate", Color(1, 1, 1, 1), 0.5)
	elif fight != null:
		fight.call("flash_wash", int(LANDS[_rng.randi() % LANDS.size()]))


func _walls() -> Array:
	var found: Array = []
	if fight == null or fight.get_parent() == null:
		return found
	var props: Node = fight.get_parent().get_node_or_null("ysortworld/props")
	if props == null:
		return found
	for child in props.get_children():
		var from: String = (child as Node).scene_file_path
		if child is CanvasItem and ("/wall" in from or "/pillar" in from):
			found.append(child)
	return found


static func _feet(body: Node2D) -> Vector2:
	return body.global_position + Vector2(0, 10)


# =============================================================================
# DRAWN: the lava's front, the cracks, the falling pieces
# =============================================================================

func _draw() -> void:
	if phase == 2 and ground != null:
		var span: Rect2i = _lava_span()
		var origin: Vector2 = ground.global_position
		var next_depth: int = lava_depth_at(phase_clock + LAVA_WARN)
		var pulse: float = 0.5 + 0.5 * sin(phase_clock * 8.0)
		for ring_depth in [lava_depth, next_depth]:
			var warn: bool = ring_depth != lava_depth
			if ring_depth <= 0 or (warn and ring_depth < lava_depth):
				continue
			var inner := Rect2(origin + Vector2((span.position + Vector2i(ring_depth, ring_depth)) * LAVA_TILE),
				Vector2((span.size - Vector2i(ring_depth * 2, ring_depth * 2)) * LAVA_TILE))
			draw_rect(inner, Color(1.0, 0.45, 0.1, (0.35 + 0.4 * pulse) if warn else 0.5), false, 4.0 if warn else 3.0)
	for piece in tears.keys():
		var held: Dictionary = tears[piece]
		var area: Rect2 = piece_rect(piece)
		var t: float = float(held["t"])
		if not bool(held["open"]):
			var k: float = clampf(t / TEAR_WARN, 0.0, 1.0)
			var shake := Vector2(sin(t * 40.0), cos(t * 37.0)) * 1.5 * k
			var pulse: float = 0.5 + 0.5 * sin(t * 14.0)
			draw_rect(Rect2(area.position + shake, area.size), Color(0.6, 0.3, 1.0, 0.1 + 0.15 * k), true)
			draw_rect(Rect2(area.position + shake, area.size), Color(0.75, 0.5, 1.0, 0.3 + 0.5 * k * pulse), false, 2.0)
			_paint_rng_cracks(area, int(held["seed"]), k, shake)
		else:
			var drop: float = clampf((t - TEAR_WARN) / TEAR_DROP, 0.0, 1.0)
			if drop < 1.0:
				var shrink: float = 1.0 - drop
				var falling := Rect2(area.get_center() - area.size * shrink / 2.0, area.size * shrink)
				draw_rect(falling, Color(0.16, 0.13, 0.2, 1.0 - drop * 0.8))
			# The rift's light at the rim, and its stars inside.
			for ring in 4:
				draw_rect(area.grow(-2.0 - 3.0 * float(ring)), Color(0.7, 0.45, 1.0, 0.4 - 0.09 * float(ring)), false, 3.0)
			draw_rect(area, Color(0.9, 0.75, 1.0, 0.95), false, 2.0)
			var seed_value: int = int(held["seed"])
			for k in 6:
				var spot := Vector2(fmod(float((seed_value >> k) % 61) + t * (6.0 + float(k)), area.size.x - 8.0) + 4.0,
					fmod(float((seed_value >> (k + 3)) % 59) + float(k) * 9.0, area.size.y - 8.0) + 4.0)
				draw_circle(area.position + spot, 1.4, Color(1.0, 0.9, 1.0, 0.5 + 0.5 * sin(t * 5.0 + float(k))))


func _paint_rng_cracks(area: Rect2, seed_value: int, k: float, shake: Vector2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var middle: Vector2 = area.get_center() + shake
	for arm in 5:
		var heading: float = rng.randf() * TAU
		var line := PackedVector2Array([middle])
		var reach: float = (area.size.x * 0.55) * k
		var steps: int = 4
		for q in steps:
			heading += rng.randf_range(-0.6, 0.6)
			line.append(line[q] + Vector2.from_angle(heading) * reach / float(steps))
		draw_polyline(line, Color(0.05, 0.02, 0.08, 0.9), 3.0)
		draw_polyline(line, Color(0.85, 0.6, 1.0, 0.85 * k), 1.5)
