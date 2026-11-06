# clothrun.gd - CUT THE CLOTH (0.130.0, step 1): the old map's slime plague,
# cut away piece by piece. Played over the screen from town
# (clothscreen.gd), in a world of its own: nothing here touches the area you
# stand in, the server or your character.
#
# THE OWNER'S STORY: "the town's first map maker drew the world on enchanted
# parchment; a long time ago the slime plague was stopped by cutting the land
# out from under it. The seal is failing and someone has to cut the cloth."
# And the game, the old Qix/Xonix one he missed: "a simple slice the map
# game", "cut an area smaller and if a enemy touches your line while cutting
# you lose a life", "x amount of map gone is required to win", "no
# characters", "this game is awesome because its simple and a good time
# sink". The healer's magic cuts it: "use the actual bullet with the glowing
# trails", "magic changes the way the cloth is cut".
#
# THE BOARD: COLS x ROWS cells of CELL px, each OPEN (cloth), OWN (cut away)
# or LINE (the cut in progress); a BORDER of OWN round it. The shot rides the
# EDGE - OWN cells touching cloth - fast (SAFE_SPEED: "the bullet needs to
# travel fast on the edges when selecting a spot to slice"). Holding cut it
# leaves the edge and burns a LINE through the cloth (CUT_SPEED); back on the
# edge the line closes: it is cut away, and with it every piece of cloth no
# slime is on (_close(): a flood from each slime); a piece a slime is on
# stays. A slime that finds itself on cut-away cloth all the same dissolves.
# A slime touching the open line, or the shot itself
# while it cuts, costs a life: the line is gone and the shot is back where it
# started (lose_life()). Let go of cut mid-cut and the shot waits there.
#
# ROUNDS: cut away target_for() of the cloth (75%, a point more a round, at
# most 85%) and the round is cleared; the next has slimes_for() slimes at
# speed_for(). LIVES lives; none left, the run is over and its round is the
# score (`best`, this session). Step 1 is that and nothing more - no elites,
# saws, movements, pickups or themed maps yet, and it pays nothing.
#
# CONTROLS (the screen sets them; "on pc it should react like the ring around
# characters it just drags the belluet to the spot you mouse is", and on a
# phone "a joystick"): `aim` (a point on the board, the mouse) or `steer` (a
# direction, keys or the stick) moves the shot; `cut_held` (the left button,
# Space, or the Slice button) cuts. With an aim the shot rides the edge to the
# edge cell nearest it, and cutting heads for it in any direction (a stair of
# cells, so the flood never leaks).
#
# THE LOOK, all drawn in code but the slimes (the game's own) and the shot
# (the healer's, turretprojectile.gd's own pieces): a linen cloth with a
# faded map's ink, darker to its edges (`_board`, drawn again only when the
# board changes); the dark under the world where it is cut, with a few
# specks; frayed edges, the cloth's shadow in the dark; the open cut as the
# shot's dotted glowing trail (`_fx`); a cut piece dissolving cell by cell
# into green motes.
#
# No class_name; clothscreen.gd makes it.
extends Node2D

const Shot := preload("res://src/projectiles/turretprojectile.gd")
const Sparkle := preload("res://src/characters/castsparkle.gd")
const HealerRun := preload("res://src/world/healerrun/healerrun.gd")

const VIEW := Vector2(640, 360)
const ORIGIN := Vector2(8, 30)
const CELL := 4
const COLS := 156
const ROWS := 81
const BORDER := 2
const OPEN := 0
const OWN := 1
const LINE := 2
const SAFE_SPEED := 300.0
const CUT_SPEED := 95.0
const FOE_SPEED := 52.0
const FOE_R := 6.0
const LIVES := 3
const TARGET_FIRST := 0.75
const TARGET_STEP := 0.01
const TARGET_MOST := 0.85
const SLIMES_FIRST := 3
const SLIMES_MOST := 7
const SPEED_STEP := 0.05
const SPEED_MOST := 1.6
const DISSOLVE := 0.6
const CLEARED_SECONDS := 1.6
const HIT_SECONDS := 0.6
# A dissolve redraws the cloth in steps, not every frame (a redraw is a pass
# over every cell).
const DISSOLVE_STEP := 0.1
const SLIME_KINDS := ["waterslime", "iceslime", "lightslime", "darkslime", "windslime", "earthslime"]
const LINEN := Color(0.86, 0.77, 0.61)
const INK := Color(0.30, 0.19, 0.11, 0.24)
const THREAD := Color(0.93, 0.86, 0.72)

enum State { PLAYING, CLEARED, OVER }

signal hurt
signal round_cleared(which: int)
signal run_over(reached: int)

var grid := PackedByteArray()
var edge := PackedByteArray()
var state: int = State.PLAYING
var round_now: int = 1
var lives: int = LIVES
var taken: float = 0.0
var best: int = 0
static var best_ever: int = 0
var cutter := Vector2i.ZERO
var cutter_px := Vector2.ZERO
var cutting: bool = false
var cut_from := Vector2i.ZERO
var line: Array = []
var foes: Array = []
var dissolving: Dictionary = {}
var hit_left: float = 0.0
var cleared_left: float = 0.0
# Controls, set by the screen each frame.
var aim: Variant = null
var steer := Vector2.ZERO
var cut_held: bool = false
var seed_value: int = 0

var _rng := RandomNumberGenerator.new()
var _step_left: float = 0.0
var _t: float = 0.0
var _heading := Vector2.UP
var _jump: bool = false
var _path: Array = []
var _path_goal := Vector2i(-1, -1)
var _board: Node2D = null
var _fx: Node2D = null
var _foes_node: Node2D = null
var _bullet: Node2D = null
var _flame: AnimatedSprite2D = null
var _line_wisps: CPUParticles2D = null
var _last_line_size: int = -1
var _redraw_left: float = 0.0
var _specks := PackedVector2Array()
var _edges: Array = []
var _near_goal := Vector2i(-1, -1)
var _near_cell := Vector2i(-1, -1)


static func target_for(which: int) -> float:
	return minf(TARGET_MOST, TARGET_FIRST + TARGET_STEP * float(which - 1))


static func slimes_for(which: int) -> int:
	return mini(SLIMES_MOST, SLIMES_FIRST + floori(float(which - 1) * 0.6))


static func speed_for(which: int) -> float:
	return minf(SPEED_MOST, 1.0 + SPEED_STEP * float(which - 1))


func _ready() -> void:
	_rng.seed = seed_value if seed_value != 0 else randi()
	_board = Node2D.new()
	_board.name = "board"
	_board.draw.connect(_draw_board)
	add_child(_board)
	_foes_node = Node2D.new()
	_foes_node.name = "slimes"
	_foes_node.z_index = 1
	add_child(_foes_node)
	_fx = Node2D.new()
	_fx.name = "fx"
	_fx.z_index = 2
	_fx.draw.connect(_draw_fx)
	add_child(_fx)
	_make_bullet()
	for k in 140:
		_specks.append(ORIGIN + Vector2(_rng.randf() * COLS * CELL, _rng.randf() * ROWS * CELL))
	begin(1)
	_place_bullet()


func _i(x: int, y: int) -> int:
	return y * COLS + x


func px(c: Vector2i) -> Vector2:
	"""A cell's middle, on the board."""
	return ORIGIN + Vector2(c) * CELL + Vector2(CELL, CELL) * 0.5


func cell_at(p: Vector2) -> Vector2i:
	var c := Vector2i(((p - ORIGIN) / CELL).floor())
	return Vector2i(clampi(c.x, 0, COLS - 1), clampi(c.y, 0, ROWS - 1))


func state_at(p: Vector2) -> int:
	var c := cell_at(p)
	return grid[_i(c.x, c.y)]


func is_edge(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < COLS and c.y < ROWS and edge[_i(c.x, c.y)] == 1


# =============================================================================
# A ROUND
# =============================================================================

func begin(which: int) -> void:
	"""A fresh cloth for round `which`: the border cut away, the shot on it,
	slimes_for() slimes at speed_for()."""
	round_now = which
	state = State.PLAYING
	grid.resize(COLS * ROWS)
	edge.resize(COLS * ROWS)
	for y in ROWS:
		for x in COLS:
			grid[_i(x, y)] = OWN if x < BORDER or y < BORDER or x >= COLS - BORDER or y >= ROWS - BORDER else OPEN
	line = []
	cutting = false
	dissolving = {}
	_path = []
	cutter = Vector2i(int(COLS * 0.5), ROWS - 1)
	cutter_px = px(cutter)
	_jump = true
	for f in foes:
		(f["sprite"] as Node).queue_free()
	foes = []
	for k in slimes_for(which):
		_add_slime(k)
	_mark_edges()
	_count()
	_board.queue_redraw()


func _add_slime(k: int) -> void:
	var kind: String = SLIME_KINDS[k % SLIME_KINDS.size()]
	var look: Dictionary = HealerRun.look_of_scene("res://scene/enemy/%s.tscn" % kind)
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = look.get("frames")
	sprite.material = look.get("material")
	sprite.offset = look.get("offset", Vector2.ZERO)
	sprite.scale = (look.get("scale", Vector2.ONE) as Vector2) * 0.8
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if sprite.sprite_frames != null and str(look.get("walk", "")) != "":
		sprite.play(str(look.get("walk")))
	var at := ORIGIN + Vector2(_rng.randf_range(0.2, 0.8) * COLS * CELL, _rng.randf_range(0.2, 0.7) * ROWS * CELL)
	var dir := Vector2.from_angle(_rng.randf_range(0.35, 1.2) + float(k) * PI / 2.0)
	sprite.position = at
	_foes_node.add_child(sprite)
	foes.append({"p": at, "v": dir * FOE_SPEED * speed_for(round_now), "sprite": sprite, "dead": -1.0})


func _mark_edges() -> void:
	"""Where the shot may ride: cut-away cells that touch cloth (each cell of
	cloth marks the cut-away cells round it)."""
	edge.fill(0)
	for y in ROWS:
		for x in COLS:
			if grid[_i(x, y)] == OWN:
				continue
			for dy in range(-1, 2):
				var ny: int = y + dy
				if ny < 0 or ny >= ROWS:
					continue
				for dx in range(-1, 2):
					var nx: int = x + dx
					if nx >= 0 and nx < COLS and grid[_i(nx, ny)] == OWN:
						edge[_i(nx, ny)] = 1
	_edges = []
	for i in edge.size():
		if edge[i] == 1:
			_edges.append(Vector2i(i % COLS, floori(float(i) / float(COLS))))
	_near_goal = Vector2i(-1, -1)
	if not is_edge(cutter):
		cutter = _nearest_edge(cutter)
		cutter_px = px(cutter)


func _nearest_edge(to: Vector2i) -> Vector2i:
	"""The edge cell nearest `to` (kept while `to` stays the same)."""
	if to == _near_goal:
		return _near_cell
	var best_cell := to
	var best_d: int = 1 << 30
	for c in _edges:
		var e: Vector2i = c
		var d: int = (e.x - to.x) * (e.x - to.x) + (e.y - to.y) * (e.y - to.y)
		if d < best_d:
			best_d = d
			best_cell = e
	_near_goal = to
	_near_cell = best_cell
	return best_cell


func _count() -> void:
	var inner: int = (COLS - 2 * BORDER) * (ROWS - 2 * BORDER)
	var own: int = 0
	for y in range(BORDER, ROWS - BORDER):
		for x in range(BORDER, COLS - BORDER):
			if grid[_i(x, y)] == OWN:
				own += 1
	taken = float(own) / float(inner)


# =============================================================================
# EACH FRAME
# =============================================================================

func _physics_process(delta: float) -> void:
	_t += delta
	hit_left = maxf(0.0, hit_left - delta)
	_step_dissolve(delta)
	match state:
		State.PLAYING:
			_move_shot(delta)
			_move_slimes(delta)
		State.CLEARED:
			cleared_left -= delta
			if cleared_left <= 0.0:
				begin(round_now + 1)
		State.OVER:
			pass
	_place_bullet()
	_fx.queue_redraw()


func _move_shot(delta: float) -> void:
	var speed: float = CUT_SPEED if cutting or cut_held else SAFE_SPEED
	_step_left -= delta
	var steps: int = 0
	while _step_left <= 0.0 and steps < 8:
		steps += 1
		_step_left += float(CELL) / speed
		var next: Vector2i = _next_cell()
		if next == cutter:
			_step_left = 0.0
			break
		_step_to(next)
		if state != State.PLAYING:
			break
		speed = CUT_SPEED if cutting else SAFE_SPEED
	cutter_px = cutter_px.move_toward(px(cutter), maxf(speed, SAFE_SPEED) * delta * 1.2)


func _next_cell() -> Vector2i:
	"""Where the shot goes next: along the edge, or cutting into the cloth."""
	var want_cut: bool = cut_held
	if cutting and not want_cut:
		return cutter
	if aim != null:
		var goal: Vector2i = cell_at(aim)
		if cutting or (want_cut and is_edge(cutter)):
			var d: Vector2i = goal - cutter
			if d == Vector2i.ZERO:
				return cutter
			var first := Vector2i(signi(d.x), 0) if absi(d.x) >= absi(d.y) else Vector2i(0, signi(d.y))
			var second := Vector2i(0, signi(d.y)) if first.x != 0 else Vector2i(signi(d.x), 0)
			for step in [first, second]:
				if step == Vector2i.ZERO:
					continue
				var n: Vector2i = cutter + step
				if _may_enter(n, true):
					return n
			if cutting:
				return cutter
		return _edge_step_toward(goal)
	if steer.length() < 0.3:
		return cutter
	var dir := Vector2i(int(signf(steer.x)), 0) if absf(steer.x) >= absf(steer.y) else Vector2i(0, int(signf(steer.y)))
	var n: Vector2i = cutter + dir
	if cutting or (want_cut and is_edge(cutter) and _in_board(n) and grid[_i(n.x, n.y)] == OPEN):
		return n if _may_enter(n, true) else cutter
	# Along the edge: straight on if it is edge, else round its corner.
	if is_edge(n):
		return n
	var sides: Array = [Vector2i(dir.y, dir.x), Vector2i(-dir.y, -dir.x)]
	for side in sides:
		if is_edge(cutter + side) and is_edge(n + side):
			return cutter + side
	for side in sides:
		if is_edge(cutter + side):
			return cutter + side
	return cutter


func _in_board(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < COLS and c.y < ROWS


func _may_enter(n: Vector2i, cutting_now: bool) -> bool:
	if not _in_board(n):
		return false
	var s: int = grid[_i(n.x, n.y)]
	if s == LINE:
		return false
	if cutting_now:
		return s == OPEN or (s == OWN and cutting)
	return is_edge(n)


func _edge_step_toward(goal: Vector2i) -> Vector2i:
	"""The next edge cell on the way to the edge cell nearest `goal` (the
	path is found again when that changes)."""
	var target: Vector2i = goal if is_edge(goal) else _nearest_edge(goal)
	if target == cutter:
		return cutter
	if target != _path_goal or _path.is_empty() or not is_edge(_path[0]):
		_path_goal = target
		_path = _edge_path(cutter, target)
	if _path.is_empty():
		return cutter
	return _path.pop_front()


func _edge_path(from: Vector2i, to: Vector2i) -> Array:
	"""The shortest way along the edge, four-connected."""
	var came: Dictionary = {from: from}
	var todo: Array = [from]
	var head: int = 0
	while head < todo.size():
		var c: Vector2i = todo[head]
		head += 1
		if c == to:
			break
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if not came.has(n) and is_edge(n):
				came[n] = c
				todo.append(n)
	if not came.has(to):
		return []
	var path: Array = []
	var at: Vector2i = to
	while at != from:
		path.push_front(at)
		at = came[at]
	return path


func _step_to(next: Vector2i) -> void:
	"""One cell: on cloth it is cut (the line grows); back on the edge from
	a cut, the cut closes."""
	var s: int = grid[_i(next.x, next.y)]
	if s == OPEN:
		if not cutting:
			cutting = true
			cut_from = cutter
			line = []
		grid[_i(next.x, next.y)] = LINE
		line.append(next)
		cutter = next
	elif s == OWN and cutting:
		cutter = next
		_close()
	elif s == OWN:
		cutter = next


func _close() -> void:
	"""The cut meets the edge: it is cut away, and so is every piece of cloth
	no slime is on."""
	for c in line:
		grid[_i(c.x, c.y)] = OWN
		dissolving[_i(c.x, c.y)] = DISSOLVE
	var seen := PackedByteArray()
	seen.resize(COLS * ROWS)
	var todo: Array = []
	for f in foes:
		if float(f["dead"]) >= 0.0:
			continue
		var c := cell_at(f["p"])
		if grid[_i(c.x, c.y)] == OPEN and seen[_i(c.x, c.y)] == 0:
			seen[_i(c.x, c.y)] = 1
			todo.append(c)
	while not todo.is_empty():
		var c: Vector2i = todo.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if not _in_board(n):
				continue
			var i: int = _i(n.x, n.y)
			if seen[i] == 0 and grid[i] == OPEN:
				seen[i] = 1
				todo.append(n)
	var gone := PackedVector2Array()
	for i in grid.size():
		if grid[i] == OPEN and seen[i] == 0:
			grid[i] = OWN
			dissolving[i] = DISSOLVE
			if i % 3 == 0:
				gone.append(ORIGIN + Vector2(i % COLS, floori(float(i) / float(COLS))) * CELL + Vector2(CELL, CELL) * 0.5)
	line = []
	cutting = false
	_path = []
	_mark_edges()
	_count()
	_motes(gone)
	_redraw_left = DISSOLVE_STEP
	_board.queue_redraw()
	if taken >= target_for(round_now):
		state = State.CLEARED
		cleared_left = CLEARED_SECONDS
		best = maxi(best, round_now)
		best_ever = maxi(best_ever, round_now)
		round_cleared.emit(round_now)


func lose_life() -> void:
	"""A slime touched the open cut: it is gone, the shot back where it
	started, a life less."""
	for c in line:
		grid[_i(c.x, c.y)] = OPEN
	line = []
	cutting = false
	cutter = cut_from
	cutter_px = px(cutter)
	_jump = true
	_path = []
	lives -= 1
	hit_left = HIT_SECONDS
	hurt.emit()
	if lives <= 0:
		state = State.OVER
		best = maxi(best, round_now - 1)
		run_over.emit(round_now)


func _move_slimes(delta: float) -> void:
	for f in foes:
		var sprite: AnimatedSprite2D = f["sprite"]
		if float(f["dead"]) >= 0.0:
			continue
		var p: Vector2 = f["p"]
		var v: Vector2 = f["v"]
		if state_at(p) == OWN:
			f["dead"] = 0.0
			continue
		var nx := p + Vector2(v.x * delta, 0.0)
		if state_at(nx + Vector2(signf(v.x) * FOE_R, 0.0)) == OWN:
			v.x = -v.x
		else:
			p = nx
		var ny := p + Vector2(0.0, v.y * delta)
		if state_at(ny + Vector2(0.0, signf(v.y) * FOE_R)) == OWN:
			v.y = -v.y
		else:
			p = ny
		f["p"] = p
		f["v"] = v
		sprite.position = p
		if cutting:
			if p.distance_to(cutter_px) <= FOE_R + 4.0:
				lose_life()
				return
			for d in [Vector2(FOE_R, 0), Vector2(-FOE_R, 0), Vector2(0, FOE_R), Vector2(0, -FOE_R), Vector2.ZERO]:
				if state_at(p + d) == LINE:
					lose_life()
					return


func _step_dissolve(delta: float) -> void:
	for f in foes:
		if float(f["dead"]) >= 0.0:
			f["dead"] = float(f["dead"]) + delta
			var sprite: AnimatedSprite2D = f["sprite"]
			sprite.modulate.a = maxf(0.0, 1.0 - float(f["dead"]) / DISSOLVE)
			sprite.scale *= 1.0 + delta * 1.2
	if dissolving.is_empty():
		return
	_redraw_left -= delta
	if _redraw_left > 0.0:
		return
	var stepped: float = DISSOLVE_STEP - _redraw_left
	_redraw_left = DISSOLVE_STEP
	for i in dissolving.keys():
		dissolving[i] = float(dissolving[i]) - stepped
		if float(dissolving[i]) <= 0.0:
			dissolving.erase(i)
	_board.queue_redraw()


func slimes_left() -> int:
	return foes.filter(func(f: Dictionary) -> bool: return float(f["dead"]) < 0.0).size()


# =============================================================================
# THE SHOT
# =============================================================================

func _make_bullet() -> void:
	"""The healer's shot as turretprojectile.gd dresses it: drawn at 2x, its
	glow behind and white-hot core on top (added), its wisp trail; and wisps
	rising off the whole open cut."""
	var look: Dictionary = HealerRun.look_of_scene("res://scene/projectiles/turretprojectile.tscn")
	_bullet = Node2D.new()
	_bullet.name = "shot"
	_bullet.z_index = 3
	add_child(_bullet)
	var dressed := Node2D.new()
	dressed.scale = Vector2(Shot.ROOT_SCALE, Shot.ROOT_SCALE)
	_bullet.add_child(dressed)
	var glow := Sprite2D.new()
	glow.texture = Blast.disc_texture(Shot.GLOW_RADIUS, Color(0.8, 1.0, 0.7), Shot.ORB_GREEN.darkened(0.3))
	glow.modulate = Color(1, 1, 1, Shot.GLOW_ALPHA)
	glow.position = Shot.BALL
	glow.material = Shot._added()
	dressed.add_child(glow)
	_flame = AnimatedSprite2D.new()
	_flame.sprite_frames = look.get("frames")
	if _flame.sprite_frames != null:
		_flame.play(_flame.sprite_frames.get_animation_names()[0])
	dressed.add_child(_flame)
	var core := Sprite2D.new()
	core.texture = Shot.core_texture()
	core.position = Shot.BALL
	core.material = Shot._added()
	dressed.add_child(core)
	dressed.add_child(_wisps(Shot.TRAIL_WISPS, CPUParticles2D.EMISSION_SHAPE_SPHERE, 1.0 / Shot.ROOT_SCALE))
	_line_wisps = _wisps(24, CPUParticles2D.EMISSION_SHAPE_POINTS, 1.0)
	_line_wisps.emitting = false
	_line_wisps.z_index = 2
	_line_wisps.scale_amount_max = 2.0
	add_child(_line_wisps)


func _wisps(count: int, shape: int, at_scale: float) -> CPUParticles2D:
	"""The shot's wisps (turretprojectile.gd _make_trail()): single pixels that
	rise and fade, added so they glow."""
	var p := CPUParticles2D.new()
	p.amount = count
	p.lifetime = Shot.TRAIL_SECONDS
	p.lifetime_randomness = 0.4
	p.local_coords = false
	p.scale = Vector2.ONE * at_scale
	p.position = Shot.BALL if shape == CPUParticles2D.EMISSION_SHAPE_SPHERE else Vector2.ZERO
	p.emission_shape = shape
	p.emission_sphere_radius = 2.0
	p.direction = Vector2.UP
	p.spread = 180.0
	p.initial_velocity_max = 3.0
	p.gravity = Vector2(0.0, -5.0)
	p.color_ramp = Sparkle.colours(Sparkle.HEAL)
	p.material = Shot._added()
	return p


func _place_bullet() -> void:
	var moved: Vector2 = cutter_px - _bullet.position
	if moved.length() > 0.3:
		_heading = _heading.lerp(moved.normalized(), 0.35).normalized()
	_bullet.position = cutter_px
	if _jump:
		_jump = false
		_bullet.reset_physics_interpolation()
	# The flame's tip trails it (turretprojectile.gd _face_flight()).
	_flame.rotation = _heading.angle() - PI / 2.0
	_bullet.visible = state != State.OVER and (hit_left <= 0.0 or int(_t * 12.0) % 2 == 0)
	if line.size() != _last_line_size:
		_last_line_size = line.size()
		var points := PackedVector2Array()
		for c in line:
			points.append(px(c))
		_line_wisps.emitting = not points.is_empty()
		if not points.is_empty():
			_line_wisps.emission_points = points
			_line_wisps.amount = clampi(points.size() * 3, 24, 400)


func _motes(points: PackedVector2Array) -> void:
	"""What is cut away rises off as green motes as it dissolves."""
	if points.is_empty():
		return
	var motes := _wisps(clampi(points.size(), 16, 600), CPUParticles2D.EMISSION_SHAPE_POINTS, 1.0)
	motes.z_index = 2
	motes.one_shot = true
	motes.explosiveness = 0.85
	motes.lifetime = 0.9
	motes.lifetime_randomness = 0.5
	motes.emission_points = points
	motes.spread = 40.0
	motes.initial_velocity_min = 8.0
	motes.initial_velocity_max = 22.0
	motes.gravity = Vector2(0.0, -12.0)
	motes.scale_amount_max = 2.0
	motes.emitting = true
	add_child(motes)
	get_tree().create_timer(1.6).timeout.connect(motes.queue_free)


# =============================================================================
# DRAWING
# =============================================================================

func _void_colour(y: float) -> Color:
	var k: float = clampf((y - ORIGIN.y) / (ROWS * CELL), 0.0, 1.0)
	return Color(0.055, 0.045, 0.10).lerp(Color(0.012, 0.012, 0.024), k)


func _draw_board() -> void:
	"""The cloth, its ink, the dark where it is cut and the frayed edges -
	drawn again only when the board changes (a cut, a dissolve, a round)."""
	var board := Rect2(ORIGIN, Vector2(COLS, ROWS) * CELL)
	_board.draw_rect(Rect2(Vector2.ZERO, VIEW), Color(0.03, 0.028, 0.05))
	_board.draw_rect(board, LINEN)
	var y: float = board.position.y
	while y < board.end.y:
		_board.draw_line(Vector2(board.position.x, y + 0.5), Vector2(board.end.x, y + 0.5), Color(0.62, 0.50, 0.34, 0.10), 1.0)
		y += 2.0
	var x: float = board.position.x
	while x < board.end.x:
		_board.draw_line(Vector2(x + 0.5, board.position.y), Vector2(x + 0.5, board.end.y), Color(1.0, 0.97, 0.9, 0.07), 1.0)
		x += 2.0
	_draw_ink(board)
	_draw_vignette(board)
	for row in ROWS:
		var col: int = 0
		while col < COLS:
			var s: int = grid[_i(col, row)]
			var run: int = 1
			while col + run < COLS and grid[_i(col + run, row)] == s \
					and dissolving.has(_i(col, row)) == dissolving.has(_i(col + run, row)):
				run += 1
			if s == OWN:
				var r := Rect2(ORIGIN + Vector2(col, row) * CELL, Vector2(run * CELL, CELL))
				_board.draw_rect(r, _void_colour(r.position.y))
				if dissolving.has(_i(col, row)):
					# each cell holds as light until its own moment, in no order
					for q in run:
						var lit: float = clampf(float(dissolving.get(_i(col + q, row), 0.0)) / DISSOLVE, 0.0, 1.0)
						var h: int = absi(((col + q) * 73856093) ^ (row * 19349663)) % 997
						if lit > float(h) / 997.0:
							_board.draw_rect(Rect2(ORIGIN + Vector2(col + q, row) * CELL, Vector2(CELL, CELL)),
								LINEN.lerp(Color(0.88, 1.0, 0.8), 0.35 + 0.65 * (1.0 - lit)))
			col += run
	for p in _specks:
		if state_at(p) == OWN and not dissolving.has(_i(cell_at(p).x, cell_at(p).y)):
			_board.draw_rect(Rect2(p, Vector2(1, 1)), Color(0.7, 0.75, 1.0, 0.2))
	_draw_cut_edges()


func _draw_ink(board: Rect2) -> void:
	"""An old map's faded ink: a coast and its shallows, a dotted road, hills,
	a compass rose."""
	var coast := PackedVector2Array()
	var shallow := PackedVector2Array()
	for k in 80:
		var t: float = float(k) / 79.0
		var yy: float = board.size.y * (0.58 + 0.10 * sin(t * 8.5 + 0.6) + 0.04 * sin(t * 21.0))
		coast.append(board.position + Vector2(t * board.size.x, yy))
		shallow.append(board.position + Vector2(t * board.size.x, yy + 9.0 + 3.0 * sin(t * 13.0)))
	_board.draw_polyline(coast, INK, 1.2)
	for k in range(0, shallow.size() - 1, 2):
		_board.draw_line(shallow[k], shallow[k + 1], Color(INK, INK.a * 0.6), 1.0)
	var road := PackedVector2Array()
	for k in 40:
		var t: float = float(k) / 39.0
		road.append(board.position + Vector2(board.size.x * (0.08 + 0.55 * t), board.size.y * (0.18 + 0.26 * t + 0.06 * sin(t * 6.0))))
	for k in range(0, road.size() - 1, 2):
		_board.draw_line(road[k], road[k + 1], INK, 1.0)
	for at in [Vector2(0.18, 0.12), Vector2(0.24, 0.16), Vector2(0.71, 0.14), Vector2(0.77, 0.19), Vector2(0.45, 0.30)]:
		var p: Vector2 = board.position + board.size * at
		_board.draw_polyline(PackedVector2Array([p + Vector2(-6, 3), p + Vector2(0, -4), p + Vector2(6, 3)]), INK, 1.1)
	var rose: Vector2 = board.position + Vector2(board.size.x - 34.0, board.size.y - 34.0)
	_board.draw_arc(rose, 14.0, 0.0, TAU, 32, INK, 1.0)
	for k in 4:
		var a: float = float(k) * PI / 2.0 - PI / 2.0
		var tip := rose + Vector2.from_angle(a) * 19.0
		var l := rose + Vector2.from_angle(a + PI / 2.0) * 3.0
		var r := rose + Vector2.from_angle(a - PI / 2.0) * 3.0
		_board.draw_colored_polygon(PackedVector2Array([tip, l, rose, r]), Color(INK, INK.a * (1.6 if k == 0 else 1.0)))


func _draw_vignette(board: Rect2) -> void:
	var dark := Color(0.42, 0.28, 0.14, 0.32)
	var clear := Color(0.42, 0.28, 0.14, 0.0)
	var w: float = 40.0
	var a := board.position
	var b := board.end
	_board.draw_polygon(PackedVector2Array([a, Vector2(b.x, a.y), Vector2(b.x, a.y + w), Vector2(a.x, a.y + w)]), PackedColorArray([dark, dark, clear, clear]))
	_board.draw_polygon(PackedVector2Array([Vector2(a.x, b.y - w), Vector2(b.x, b.y - w), b, Vector2(a.x, b.y)]), PackedColorArray([clear, clear, dark, dark]))
	_board.draw_polygon(PackedVector2Array([a, Vector2(a.x + w, a.y), Vector2(a.x + w, b.y), Vector2(a.x, b.y)]), PackedColorArray([dark, clear, clear, dark]))
	_board.draw_polygon(PackedVector2Array([Vector2(b.x - w, a.y), Vector2(b.x, a.y), b, Vector2(b.x - w, b.y)]), PackedColorArray([clear, dark, dark, clear]))


func _draw_cut_edges() -> void:
	"""Where the cloth meets the dark: its shadow cast into the dark, a darker
	hem, and a fringe of loose threads."""
	for row in ROWS:
		for col in COLS:
			if grid[_i(col, row)] != OWN or edge[_i(col, row)] == 0:
				continue
			for d in [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1)]:
				var n: Vector2i = Vector2i(col, row) + d
				if not _in_board(n) or grid[_i(n.x, n.y)] == OWN:
					continue
				var cell := Rect2(ORIGIN + Vector2(col, row) * CELL, Vector2(CELL, CELL))
				var shade: float = 0.55 if d.y == -1 else (0.4 if d.x == -1 else 0.18)
				_board.draw_rect(cell, Color(0.0, 0.0, 0.0, shade))
				var rim: Vector2 = cell.get_center() + Vector2(d) * (CELL * 0.5)
				var side := Vector2(-d.y, d.x)
				_board.draw_line(rim - side * 2.0, rim + side * 2.0, Color(0.48, 0.36, 0.22, 0.85), 1.0)
				var h: int = absi((col * 73856093) ^ (row * 19349663))
				for k in 2:
					var hh: int = (h >> (k * 5)) & 1023
					var reach: float = 0.8 + float(hh % 6) * 0.35
					var tilt: float = (float((hh >> 3) % 5) - 2.0) * 0.12
					var root := rim + side * (-1.0 + 2.0 * float(k))
					var out := (-Vector2(d)).rotated(tilt)
					_board.draw_line(root, root + out * reach, Color(THREAD.darkened(0.12), 0.45 + 0.08 * float(hh % 4)), 1.0, true)


func _draw_fx() -> void:
	"""What moves: the slimes' shadows, the open cut as the shot's dotted
	glowing trail, and the shot's own shadow."""
	for f in foes:
		if float(f["dead"]) < 0.0:
			_fx.draw_set_transform(f["p"] + Vector2(0, 5), 0.0, Vector2(1.0, 0.45))
			_fx.draw_circle(Vector2.ZERO, 7.0, Color(0.15, 0.08, 0.03, 0.28))
	_fx.draw_set_transform(cutter_px + Vector2(0, 6), 0.0, Vector2(1.0, 0.45))
	_fx.draw_circle(Vector2.ZERO, 8.0, Color(0.08, 0.12, 0.05, 0.3))
	_fx.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var n: int = line.size()
	for k in n:
		var c: Vector2i = line[k]
		var h: int = absi((c.x * 73856093) ^ (c.y * 19349663))
		var p: Vector2 = px(c) + Vector2(float(h % 3) - 1.0, float((h >> 3) % 3) - 1.0) * 0.6
		var age: float = float(n - 1 - k) / maxf(1.0, float(n))
		var twinkle: float = 0.7 + 0.3 * sin(_t * 8.0 + float(k) * 1.7)
		var colour: Color = Color(1.0, 1.0, 0.92).lerp(Color(0.55, 0.95, 0.42), clampf(age * 3.0, 0.0, 1.0))
		_fx.draw_circle(p, 1.8, Color(0.15, 0.45, 0.15, 0.22 * twinkle))
		_fx.draw_rect(Rect2(p - Vector2(0.5, 0.5), Vector2(1, 1)), Color(colour, twinkle))
		if h % 5 == 0:
			_fx.draw_circle(p, 2.2, Color(0.55, 0.95, 0.42, 0.35 * twinkle))
			_fx.draw_rect(Rect2(p - Vector2(1, 1), Vector2(2, 2)), Color(1.0, 1.0, 0.92, twinkle))
