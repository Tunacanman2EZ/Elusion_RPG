# clothrun.gd - CUT THE CLOTH (0.130.0; step 2, 0.131.0): the old map's slime
# plague, cut away piece by piece. Played over the screen from town
# (clothscreen.gd), in a world of its own: nothing here touches the area you
# stand in or your character; the server is asked only at Go and at the end,
# by the screen.
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
# or LINE (the cut in progress); a BORDER of OWN round it. The shot moves over
# what is cut away - fast (SAFE_SPEED: "the bullet needs to travel fast on
# the edges when selecting a spot to slice"), by the shortest way
# (`_astar`, over OWN cells) - and from an EDGE (an OWN cell touching cloth),
# held, it burns a LINE through the cloth (CUT_SPEED); back on OWN the line
# closes: it is cut away, and with it every piece of cloth no slime is on
# (_close(): a flood from each slime); a piece a slime is on stays. A slime
# that finds itself on cut-away cloth all the same dissolves. A slime touching
# the open line, or the shot itself while it cuts, costs a life: the line is
# gone and the shot is back where it started (lose_life()). Let go of cut
# mid-cut and the shot waits there.
#
# ROUNDS (0.131.0, the owner: "add the other stuff now"): cut away target_for()
# of the cloth to clear a round; the next has more slimes, faster. LIVES
# lives (LIVES_MOST with the Life pickup); none left, the run is over.
#   - EACH ROUND IS A LAND (land_of(): light, wind, water, ice, earth, fire,
#     dark, round again), the map drawn its way and ONE effect (LAND_RULES):
#     light's flares dazzle slimes still; wind's gusts shove them; water's wet
#     patches halve the cut; ice slides the shot - once cutting it cannot
#     stop; earth's rocks are already cut and the slimes bounce off them;
#     fire's fuse burns back along a line left standing still; dark leaves
#     only the shot's light. The owner: "weathered, burnt parchment for
#     volcanic areas, frost-bitten edges for tundra regions".
#   - SLIMES MOVE BY THEIR COLOUR (MOVES): water bounces, wind zigzags, earth
#     hops, fire hunts the open line, ice glides fast, light darts, dark fades.
#   - EDGE SAWS from round 2 (saws_for()): they ride the cut edge, and touch
#     the shot while it is on it - the edge is not safe.
#   - ELITES from round 3 (elites_for()), bigger slimes with a trick: the
#     hunter chases the line (or the shot); the splitter splits in two when a
#     cut takes enough of the cloth; the gnawer chews the cut edge back into
#     cloth. The owner: "corrupted, faster, or splitting slimes as the plague
#     mutates".
#   - A BOSS EVERY BOSS_EVERY ROUNDS: the Plague Mother, huge and slow, who
#     spits slimes; the round is cleared by sealing her into a piece no more
#     than SEAL_SHARE of the cloth.
#   - ENDLESS AFTER ENDLESS_AFTER: the rounds go on, faster each.
#   - PICKUPS cut free (PICKUPS): Swift, Ward, Slow, Life - a pickup is had
#     when the cloth it sits on is cut away or the shot crosses it. Nothing
#     lasts past the run ("upgrades or no?": no permanent upgrades).
#   - GOLD: each round cleared pays (gold_for_round(), the server's table at
#     Go in `pays`); the server pays it, held to the time the run took.
#
# CONTROLS (the screen sets them; "on pc it should react like the ring around
# characters it just drags the belluet to the spot you mouse is", and on a
# phone "a joystick"): `aim` (a point on the board, the mouse) or `steer` (a
# direction, keys or the stick) moves the shot; `cut_held` (the left button,
# Space, or the Slice button) cuts.
#
# THE LOOK, all drawn in code but the slimes (the game's own) and the shot
# (the healer's, turretprojectile.gd's own pieces): a linen cloth with a
# faded map's ink, darker to its edges, coloured by its land (`_board`, drawn
# again only when the board changes); the dark under it where it is cut;
# frayed edges; the open cut as the shot's dotted glowing trail (`_fx`); a
# cut piece dissolving cell by cell into green motes.
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
const ELITE_R := 9.0
const BOSS_R := 16.0
const LIVES := 3
const LIVES_MOST := 5
const TARGET_FIRST := 0.75
const TARGET_STEP := 0.01
const TARGET_MOST := 0.85
const SLIMES_FIRST := 3
const SLIMES_MOST := 7
const SPEED_STEP := 0.05
const ENDLESS_AFTER := 10
const SPEED_STEP_ENDLESS := 0.04
const SPEED_MOST := 2.0
# THE BOSS: every BOSS_EVERY rounds, with BOSS_SLIMES slimes and her brood.
const BOSS_EVERY := 5
const BOSS_SLIMES := 2
const SEAL_SHARE := 0.2
const BOSS_SPEED := 0.6
const BROOD_SECONDS := 7.0
const BROOD_MOST := 4
# EDGE SAWS and ELITES.
const SAW_SPEED := 70.0
const SAW_R := 6.0
const ELITE_TRICKS := ["hunter", "splitter", "gnawer"]
const ELITE_SPEED := 0.9
const TURN_RATE := 1.8
const GNAW_GAP := 0.6
const GNAW_KEEP := 4
const SPLIT_SHARE := 0.02
const DISSOLVE := 0.6
const CLEARED_SECONDS := 1.6
const HIT_SECONDS := 0.6
const GRACE_SECONDS := 1.0
# A dissolve redraws the cloth in steps, not every frame (a redraw is a pass
# over every cell).
const DISSOLVE_STEP := 0.1
# THE LANDS, in the bands' order, and what each does.
const LANDS := ["light", "wind", "water", "ice", "earth", "fire", "dark"]
const LAND_NAMES := {"light": "The Shining Map", "wind": "The Windworn Map", "water": "The Drowned Map",
	"ice": "The Frozen Map", "earth": "The Stone Map", "fire": "The Burnt Map", "dark": "The Dark Map"}
const LAND_RULES := {"light": "Flares dazzle the slimes still",
	"wind": "Gusts shove the slimes - watch the streaks",
	"water": "Wet cloth cuts at half speed",
	"ice": "The shot slides - once cutting it cannot stop",
	"earth": "Rocks: already cut, and the slimes bounce off them",
	"fire": "Stand still mid-cut and the fuse burns back to you",
	"dark": "Only the shot's light to see by"}
# [linen, its edges' tint, the threads, the dark under it]
const LOOKS := {
	"light": [Color(0.93, 0.85, 0.64), Color(0.62, 0.45, 0.12, 0.30), Color(0.98, 0.92, 0.74), Color(0.07, 0.06, 0.10)],
	"wind": [Color(0.84, 0.81, 0.70), Color(0.40, 0.42, 0.38, 0.34), Color(0.93, 0.91, 0.82), Color(0.05, 0.06, 0.08)],
	"water": [Color(0.80, 0.79, 0.70), Color(0.18, 0.28, 0.40, 0.36), Color(0.90, 0.90, 0.84), Color(0.03, 0.05, 0.10)],
	"ice": [Color(0.87, 0.90, 0.92), Color(0.55, 0.75, 0.92, 0.42), Color(0.97, 0.99, 1.0), Color(0.04, 0.06, 0.11)],
	"earth": [Color(0.80, 0.67, 0.49), Color(0.36, 0.24, 0.10, 0.36), Color(0.88, 0.78, 0.62), Color(0.06, 0.045, 0.04)],
	"fire": [Color(0.80, 0.61, 0.40), Color(0.20, 0.07, 0.02, 0.55), Color(0.86, 0.70, 0.52), Color(0.07, 0.03, 0.03)],
	"dark": [Color(0.66, 0.60, 0.62), Color(0.16, 0.10, 0.22, 0.45), Color(0.74, 0.68, 0.72), Color(0.03, 0.02, 0.05)],
}
# The slimes: each land's scene (fire is the water slime in fire's colours).
const SLIME_SCENES := {"water": "waterslime", "ice": "iceslime", "light": "lightslime", "dark": "darkslime",
	"wind": "windslime", "earth": "earthslime", "fire": "waterslime"}
const MOVES := {"water": "bounce", "ice": "glide", "wind": "zigzag", "earth": "hop", "fire": "hunt",
	"light": "dart", "dark": "fade"}
const GLIDE_SPEED := 1.3
const ZIG_SECONDS := 0.6
const ZIG_TURN := 0.9
const HOP_CYCLE := 1.0
const HOP_STILL := 0.45
const HOP_SPEED := 2.0
const DART_CYCLE := 1.6
const DART_SECONDS := 0.25
const DART_SPEED := 2.6
const DART_REST := 0.8
const FADE_SPEED := 2.1
# THE LANDS' EFFECTS.
const FLARE_GAP := 5.5
const FLARE_WARN := 0.9
const FLARE_FLASH := 0.4
const FLARE_R := 52.0
const DAZE_SECONDS := 1.8
const GUST_GAP := 7.0
const GUST_WARN := 1.0
const GUST_SECONDS := 1.6
const GUST_PUSH := 46.0
const WET_PATCHES := 4
const WET_SLOW := 0.5
const ROCKS := 4
const FUSE_AFTER := 0.5
const FUSE_SPEED := 30.0
const DARK_RADIUS := 95.0
# PICKUPS.
const PICKUPS := ["swift", "ward", "slow", "life"]
const PICKUP_FIRST := 8.0
const PICKUP_GAP := 13.0
const PICKUP_SECONDS := 15.0
const PICKUP_MOST := 2
const LIFE_CHANCE := 6
const SWIFT_SECONDS := 10.0
const SWIFT_SPEED := 1.6
const SLOW_SECONDS := 8.0
const SLOW_SPEED := 0.5
# GOLD for each round cleared, as the server pays it (its own table, handed
# over at Go, wins: `pays`).
const ROUND_GOLD := [100, 150, 200, 300, 600, 400, 500, 600, 700, 1500]
const ENDLESS_GOLD := 800
const ENDLESS_BOSS_GOLD := 1600
const MOTE_GREEN := Color(0.55, 0.95, 0.42)

enum State { PLAYING, CLEARED, OVER }

signal hurt
signal round_cleared(which: int)
signal run_over(reached: int)
signal said(text: String)

var grid := PackedByteArray()
var edge := PackedByteArray()
var rock := PackedByteArray()
var wet := PackedByteArray()
var state: int = State.PLAYING
# Whether a round has begun (the warmer loads freely before).
var begun: bool = false
var round_now: int = 1
var land: String = "light"
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
var saws: Array = []
var pickups: Array = []
var flares: Array = []
var dissolving: Dictionary = {}
var hit_left: float = 0.0
var grace_left: float = 0.0
var cleared_left: float = 0.0
var ward: bool = false
var swift_left: float = 0.0
var slow_left: float = 0.0
var gust_dir := Vector2.ZERO
var gust_warn: float = 0.0
var gust_on: float = 0.0
var fuse: float = -1.0
var boss_share: float = 1.0
# The server's table at Go ({"rounds": [...], "endless": n, "endless_boss": n}).
var pays: Dictionary = {}
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
var _astar: AStarGrid2D = null
var _board: Node2D = null
var _under: Node2D = null
var _fx: Node2D = null
var _foes_node: Node2D = null
var _dark: Sprite2D = null
var _bullet: Node2D = null
var _flame: AnimatedSprite2D = null
var _line_wisps: CPUParticles2D = null
var _last_line_size: int = -1
var _specks := PackedVector2Array()
var _edges: Array = []
var _near_goal := Vector2i(-1, -1)
var _near_cell := Vector2i(-1, -1)
var _redraw_left: float = 0.0
var _last_step := Vector2i.ZERO
var _still: float = 0.0
var _pickup_left: float = PICKUP_FIRST
var _flare_left: float = FLARE_GAP
var _gust_left: float = GUST_GAP
var _gust_seed: int = 0
var _wet_spots: Array = []
var _rock_spots: Array = []


static func target_for(which: int) -> float:
	return minf(TARGET_MOST, TARGET_FIRST + TARGET_STEP * float(which - 1))


static func slimes_for(which: int) -> int:
	if is_boss_round(which):
		return BOSS_SLIMES
	return mini(SLIMES_MOST, SLIMES_FIRST + floori(float(which - 1) * 0.6))


static func speed_for(which: int) -> float:
	"""5% faster a round to round ENDLESS_AFTER, then 4% a round, at most
	SPEED_MOST."""
	if which <= ENDLESS_AFTER:
		return 1.0 + SPEED_STEP * float(which - 1)
	return minf(SPEED_MOST, 1.0 + SPEED_STEP * float(ENDLESS_AFTER - 1) + SPEED_STEP_ENDLESS * float(which - ENDLESS_AFTER))


static func saws_for(which: int) -> int:
	"""Edge saws: one from round 2, two from 5, three from 8, four from 14."""
	if which < 2:
		return 0
	if which < 5:
		return 1
	if which < 8:
		return 2
	return 3 if which < 14 else 4


static func elites_for(which: int) -> int:
	"""Elites: one from round 3, two from 6, three from 9, four from 15 - none
	on a boss's round."""
	if which < 3 or is_boss_round(which):
		return 0
	if which < 6:
		return 1
	if which < 9:
		return 2
	return 3 if which < 15 else 4


static func is_boss_round(which: int) -> bool:
	return which > 0 and which % BOSS_EVERY == 0


static func land_of(which: int) -> String:
	return LANDS[(which - 1) % LANDS.size()]


static func gold_for_round(which: int, table: Dictionary = {}) -> int:
	"""What clearing round `which` pays: the server's table if it gave one."""
	var rounds: Array = table.get("rounds", ROUND_GOLD) as Array
	if which >= 1 and which <= rounds.size():
		return int(rounds[which - 1])
	if is_boss_round(which):
		return int(table.get("endless_boss", ENDLESS_BOSS_GOLD))
	return int(table.get("endless", ENDLESS_GOLD))


func _ready() -> void:
	# MEASURE HERE (0.152.0): the readout's Measure names this minigame.
	add_to_group(&"minigame_run")
	# READY BEFORE THEY COME (0.152.0, scenewarmer.gd): each land's slime and
	# the turret's shot, loaded before the first cut and between rounds.
	var warmer: Node = (load("res://src/systems/scenewarmer.gd") as GDScript).call("add_to", self)
	warmer.set("calm", func() -> bool: return not begun or state != State.PLAYING)
	warmer.call("warm", scenes_to_warm())
	_rng.seed = seed_value if seed_value != 0 else randi()
	_astar = AStarGrid2D.new()
	_astar.region = Rect2i(0, 0, COLS, ROWS)
	_astar.cell_size = Vector2.ONE
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_astar.update()
	_board = Node2D.new()
	_board.name = "board"
	_board.draw.connect(_draw_board)
	add_child(_board)
	_under = Node2D.new()
	_under.name = "under"
	_under.z_index = 1
	_under.draw.connect(_draw_under)
	add_child(_under)
	_foes_node = Node2D.new()
	_foes_node.name = "slimes"
	_foes_node.z_index = 2
	add_child(_foes_node)
	_make_dark()
	_fx = Node2D.new()
	_fx.name = "fx"
	_fx.z_index = 4
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


func _in_board(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < COLS and c.y < ROWS


func _inner() -> int:
	return (COLS - 2 * BORDER) * (ROWS - 2 * BORDER)


# =============================================================================
# A ROUND
# =============================================================================

func begin(which: int) -> void:
	"""A fresh cloth for round `which`, of its land: the border cut away, the
	shot on it, its slimes, saws, elites or boss, and its land's rocks or wet."""
	round_now = which
	land = land_of(which)
	state = State.PLAYING
	begun = true
	grid.resize(COLS * ROWS)
	edge.resize(COLS * ROWS)
	rock.resize(COLS * ROWS)
	wet.resize(COLS * ROWS)
	rock.fill(0)
	wet.fill(0)
	for y in ROWS:
		for x in COLS:
			grid[_i(x, y)] = OWN if x < BORDER or y < BORDER or x >= COLS - BORDER or y >= ROWS - BORDER else OPEN
	line = []
	cutting = false
	dissolving = {}
	pickups = []
	flares = []
	fuse = -1.0
	_still = 0.0
	_path = []
	_last_step = Vector2i.ZERO
	gust_warn = 0.0
	gust_on = 0.0
	_pickup_left = PICKUP_FIRST
	_flare_left = FLARE_GAP * 0.6
	_gust_left = GUST_GAP * 0.6
	boss_share = 1.0
	cutter = Vector2i(int(COLS * 0.5), ROWS - 1)
	cutter_px = px(cutter)
	_jump = true
	for f in foes:
		(f["sprite"] as Node).queue_free()
	foes = []
	saws = []
	_rock_spots = []
	_wet_spots = []
	if land == "earth":
		_stamp_rocks()
	if land == "water":
		_stamp_wet()
	var n: int = slimes_for(which)
	for k in n:
		var kind: String = land if k % 2 == 0 else LANDS[(floori(float(k) / 2.0) + which) % LANDS.size()]
		if kind == land and k % 2 == 1:
			kind = LANDS[(LANDS.find(land) + 3) % LANDS.size()]
		_add_slime(kind, _spawn_spot(FOE_R), Vector2.from_angle(_rng.randf_range(0.35, 1.2) + float(k) * PI / 2.0), "small", "")
	for k in elites_for(which):
		var trick: String = ELITE_TRICKS[(which + k) % ELITE_TRICKS.size()]
		_add_slime(land, _spawn_spot(ELITE_R), Vector2.from_angle(_rng.randf() * TAU), "elite", trick)
	if is_boss_round(which):
		var at := ORIGIN + Vector2(COLS * CELL * 0.5, ROWS * CELL * 0.42)
		_add_slime(land, at, Vector2.from_angle(_rng.randf_range(0.4, 1.1)), "boss", "")
	_mark_edges()
	_count()
	for k in saws_for(which):
		_add_saw(k)
	_dark.visible = land == "dark"
	_board.queue_redraw()
	_under.queue_redraw()


func _spawn_spot(r: float) -> Vector2:
	"""A place on the cloth for a slime: in the board's middle band, off the
	rocks, away from the shot's side."""
	for tries in 40:
		var at := ORIGIN + Vector2(_rng.randf_range(0.15, 0.85) * COLS * CELL, _rng.randf_range(0.15, 0.68) * ROWS * CELL)
		var ok: bool = true
		for d in [Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r), Vector2.ZERO]:
			ok = ok and state_at(at + d) == OPEN
		if ok:
			return at
	return ORIGIN + Vector2(COLS * CELL * 0.5, ROWS * CELL * 0.4)


func _stamp_rocks() -> void:
	"""Earth's rocks: a few lumps of cut-away cloth on the map, rock to the
	eye, which the slimes bounce off and the cut may close on."""
	for k in ROCKS:
		for tries in 30:
			var c := Vector2i(_rng.randi_range(14, COLS - 15), _rng.randi_range(10, ROWS - 18))
			var r: int = _rng.randi_range(3, 5)
			var clear: bool = true
			for spot in _rock_spots:
				clear = clear and Vector2(c).distance_to(Vector2((spot as Array)[0])) > 22.0
			if not clear:
				continue
			_rock_spots.append([c, r])
			for y in range(c.y - r - 1, c.y + r + 2):
				for x in range(c.x - r - 1, c.x + r + 2):
					var bump: float = 0.6 * sin(float(x * 7 + y * 3 + k))
					if Vector2(x - c.x, (y - c.y) * 1.25).length() <= float(r) + bump:
						grid[_i(x, y)] = OWN
						rock[_i(x, y)] = 1
			break


func _stamp_wet() -> void:
	"""Water's wet patches, where the cut goes at WET_SLOW."""
	for k in WET_PATCHES:
		var c := Vector2i(_rng.randi_range(12, COLS - 13), _rng.randi_range(8, ROWS - 12))
		var r: int = _rng.randi_range(7, 11)
		_wet_spots.append([c, r])
		for y in range(maxi(BORDER, c.y - r), mini(ROWS - BORDER, c.y + r + 1)):
			for x in range(maxi(BORDER, c.x - r - 3), mini(COLS - BORDER, c.x + r + 4)):
				var bump: float = 1.2 * sin(float(x) * 0.7 + float(k)) + 1.0 * cos(float(y) * 0.9)
				if Vector2(x - c.x, (y - c.y) * 1.4).length() <= float(r) + bump:
					wet[_i(x, y)] = 1


func _look_for(kind: String) -> Dictionary:
	var look: Dictionary = HealerRun.look_of_scene("res://scene/enemy/%s.tscn" % SLIME_SCENES.get(kind, "waterslime"))
	if kind == "fire":
		var data: EnemyData = load("res://data/enemies/waterslime.tres") as EnemyData
		var fired: Dictionary = look.duplicate()
		fired["material"] = BaseEnemy.element_material(data, Element.Type.FIRE) if data != null else look.get("material")
		return fired
	return look


func _add_slime(kind: String, at: Vector2, dir: Vector2, size: String, trick: String) -> Dictionary:
	"""A slime of `kind` - "small", an "elite" with its `trick`, or the "boss" -
	at `at`, going `dir`."""
	var look: Dictionary = _look_for(kind)
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = look.get("frames")
	sprite.material = look.get("material")
	sprite.offset = look.get("offset", Vector2.ZERO)
	var grow: float = 0.8 if size == "small" else (1.25 if size == "elite" else 2.1)
	sprite.scale = (look.get("scale", Vector2.ONE) as Vector2) * grow
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if sprite.sprite_frames != null and str(look.get("walk", "")) != "":
		sprite.play(str(look.get("walk")))
		sprite.speed_scale = 0.6 if size == "boss" else 1.0
	sprite.position = at
	_foes_node.add_child(sprite)
	var r: float = FOE_R if size == "small" else (ELITE_R if size == "elite" else BOSS_R)
	var f: Dictionary = {"p": at, "v": dir.normalized() * FOE_SPEED * speed_for(round_now), "sprite": sprite,
		"dead": -1.0, "kind": kind, "move": "bounce" if size == "boss" else str(MOVES.get(kind, "bounce")),
		"r": r, "size": size, "trick": trick, "t": _rng.randf() * 3.0, "dazed": 0.0, "zig": 1.0,
		"gnaw": GNAW_GAP, "brood": BROOD_SECONDS * 0.6}
	if trick != "":
		sprite.modulate = Color(1.15, 1.0, 1.0) if trick == "hunter" else (Color(1.0, 1.1, 0.9) if trick == "splitter" else Color(0.95, 0.95, 1.15))
	foes.append(f)
	return f


func _add_saw(k: int) -> void:
	"""An edge saw on the border's edge (never round a rock), as far round it
	from the shot as can be."""
	if _edges.is_empty():
		return
	var far: Array = []
	for c in _edges:
		var e: Vector2i = c
		var rim: bool = e.x < BORDER or e.y < BORDER or e.x >= COLS - BORDER or e.y >= ROWS - BORDER
		if rim and absi(e.x - cutter.x) + absi(e.y - cutter.y) > 60:
			far.append(e)
	var at: Vector2i = far[_rng.randi() % far.size()] if not far.is_empty() else _edges[_rng.randi() % _edges.size()]
	saws.append({"c": at, "prev": at, "px": px(at), "step": 0.0, "spin": float(k)})


func _mark_edges() -> void:
	"""Where the shot may start a cut and the saws ride: cut-away cells that
	touch cloth (each cell of cloth marks the cut-away cells round it)."""
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
	_sync_astar()
	if not is_edge(cutter) and not _edges.is_empty():
		cutter = _nearest_edge(cutter)
		cutter_px = px(cutter)
	for s in saws:
		if not is_edge(s["c"]) and not _edges.is_empty():
			s["c"] = _nearest_edge(s["c"])
			s["prev"] = s["c"]


func _sync_astar() -> void:
	"""The shot's ways: every cut-away cell, in runs a row."""
	if _astar == null:
		return
	for y in ROWS:
		var x: int = 0
		while x < COLS:
			var own: bool = grid[_i(x, y)] == OWN
			var run: int = 1
			while x + run < COLS and (grid[_i(x + run, y)] == OWN) == own:
				run += 1
			_astar.fill_solid_region(Rect2i(x, y, run, 1), not own)
			x += run
	_path = []


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
	var own: int = 0
	for y in range(BORDER, ROWS - BORDER):
		for x in range(BORDER, COLS - BORDER):
			if grid[_i(x, y)] == OWN:
				own += 1
	taken = float(own) / float(_inner())


func _piece_share(from: Vector2) -> float:
	"""How much of the cloth the piece under `from` is."""
	var c := cell_at(from)
	if grid[_i(c.x, c.y)] == OWN:
		return 0.0
	var seen := PackedByteArray()
	seen.resize(COLS * ROWS)
	var todo: Array = [_i(c.x, c.y)]
	seen[_i(c.x, c.y)] = 1
	var n: int = 0
	while not todo.is_empty():
		var i: int = todo.pop_back()
		n += 1
		for m in [i - 1, i + 1, i - COLS, i + COLS]:
			if m >= 0 and m < grid.size() and seen[m] == 0 and grid[m] != OWN:
				seen[m] = 1
				todo.append(m)
	return float(n) / float(_inner())


# =============================================================================
# EACH FRAME
# =============================================================================

# WHO SPENT IT (0.152.0): this minigame's own frame, timed, so a slow
# frame on the readout names it (PerfOverlay.spend()).
func _physics_process(delta: float) -> void:
	var spent_from: int = Time.get_ticks_usec()
	_timed_physics_process(delta)
	PerfOverlay.spend(&"cut the cloth", Time.get_ticks_usec() - spent_from)


func _timed_physics_process(delta: float) -> void:
	_t += delta
	hit_left = maxf(0.0, hit_left - delta)
	grace_left = maxf(0.0, grace_left - delta)
	swift_left = maxf(0.0, swift_left - delta)
	slow_left = maxf(0.0, slow_left - delta)
	_step_dissolve(delta)
	match state:
		State.PLAYING:
			_move_shot(delta)
			if state == State.PLAYING:
				_move_slimes(delta)
			if state == State.PLAYING:
				_move_saws(delta)
			if state == State.PLAYING:
				_land_effects(delta)
				_tick_pickups(delta)
		State.CLEARED:
			cleared_left -= delta
			if cleared_left <= 0.0:
				begin(round_now + 1)
		State.OVER:
			pass
	_place_bullet()
	_fx.queue_redraw()
	_under.queue_redraw()


func _shot_speed() -> float:
	var speed: float = CUT_SPEED if cutting or cut_held else SAFE_SPEED
	if swift_left > 0.0:
		speed *= SWIFT_SPEED if cutting or cut_held else 1.2
	if cutting and wet[_i(cutter.x, cutter.y)] == 1:
		speed *= WET_SLOW
	return speed


func _move_shot(delta: float) -> void:
	var speed: float = _shot_speed()
	_step_left -= delta
	var steps: int = 0
	var moved: bool = false
	while _step_left <= 0.0 and steps < 8:
		steps += 1
		_step_left += float(CELL) / speed
		var next: Vector2i = _next_cell()
		if next == cutter:
			_step_left = 0.0
			break
		_step_to(next)
		moved = true
		if state != State.PLAYING:
			break
		speed = _shot_speed()
	if cutting:
		_still = 0.0 if moved else _still + delta
	cutter_px = cutter_px.move_toward(px(cutter), maxf(speed, SAFE_SPEED) * delta * 1.2)


func _next_cell() -> Vector2i:
	"""Where the shot goes next: over what is cut away, or cutting into the
	cloth - on ice, once cutting, on and on."""
	var want_cut: bool = cut_held
	var sliding: bool = cutting and land == "ice" and _last_step != Vector2i.ZERO
	if cutting and not want_cut and not sliding:
		return cutter
	var chosen: Vector2i = cutter
	if not want_cut and sliding:
		chosen = cutter
	elif aim != null:
		var goal: Vector2i = cell_at(aim)
		if cutting or (want_cut and is_edge(cutter)):
			chosen = _stair_toward(goal)
			if chosen == cutter and not cutting:
				chosen = _ride_toward(goal)
		else:
			chosen = _ride_toward(goal)
	elif steer.length() >= 0.3:
		var dir := Vector2i(int(signf(steer.x)), 0) if absf(steer.x) >= absf(steer.y) else Vector2i(0, int(signf(steer.y)))
		var n: Vector2i = cutter + dir
		if cutting or (want_cut and is_edge(cutter) and _in_board(n) and grid[_i(n.x, n.y)] == OPEN):
			chosen = n if _may_enter(n, true) else cutter
		elif _in_board(n) and grid[_i(n.x, n.y)] == OWN:
			chosen = n
		else:
			# against the cloth: along it, round its corner
			for side in [Vector2i(dir.y, dir.x), Vector2i(-dir.y, -dir.x)]:
				var s: Vector2i = cutter + side
				if is_edge(s) and is_edge(n + side):
					chosen = s
					break
			if chosen == cutter:
				for side in [Vector2i(dir.y, dir.x), Vector2i(-dir.y, -dir.x)]:
					var s2: Vector2i = cutter + side
					if is_edge(s2):
						chosen = s2
						break
	if sliding and (chosen == cutter or chosen - cutter == -_last_step):
		var on: Vector2i = cutter + _last_step
		chosen = on if _may_enter(on, true) else cutter
	return chosen


func _stair_toward(goal: Vector2i) -> Vector2i:
	"""A step into the cloth toward `goal`: along the longer way first, then
	the other (a stair of cells, so the flood never leaks)."""
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
	return cutter


func _may_enter(n: Vector2i, cutting_now: bool) -> bool:
	if not _in_board(n):
		return false
	var s: int = grid[_i(n.x, n.y)]
	if s == LINE:
		return false
	if cutting_now:
		return s == OPEN or (s == OWN and cutting)
	return s == OWN


func _ride_toward(goal: Vector2i) -> Vector2i:
	"""The next cell on the shortest way over what is cut away to `goal` - or,
	when `goal` is cloth, to the edge cell nearest it (the way is found again
	when that changes)."""
	var target: Vector2i = goal if _in_board(goal) and grid[_i(goal.x, goal.y)] == OWN else _nearest_edge(goal)
	if target == cutter:
		return cutter
	var fresh: bool = target != _path_goal or _path.is_empty()
	if not fresh:
		var head: Vector2i = _path[0]
		fresh = grid[_i(head.x, head.y)] != OWN or absi(head.x - cutter.x) + absi(head.y - cutter.y) != 1
	if fresh:
		_path_goal = target
		_path = Array(_astar.get_id_path(cutter, target)) if grid[_i(cutter.x, cutter.y)] == OWN else []
		if not _path.is_empty() and _path[0] == cutter:
			_path.pop_front()
	if _path.is_empty():
		return cutter
	return _path.pop_front()


func _step_to(next: Vector2i) -> void:
	"""One cell: on cloth it is cut (the line grows); back on what is cut
	away from a cut, the cut closes."""
	var s: int = grid[_i(next.x, next.y)]
	_last_step = next - cutter
	if s == OPEN:
		if not cutting:
			cutting = true
			cut_from = cutter
			line = []
			fuse = -1.0
			_still = 0.0
		grid[_i(next.x, next.y)] = LINE
		line.append(next)
		cutter = next
		_take_pickup_at(next)
	elif s == OWN and cutting:
		cutter = next
		_close()
	elif s == OWN:
		cutter = next


func _close() -> void:
	"""The cut meets what is cut away: it is cut away, and so is every piece
	of cloth no slime is on."""
	var before: float = taken
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
	fuse = -1.0
	_still = 0.0
	_path = []
	_mark_edges()
	_count()
	_motes(gone)
	_redraw_left = DISSOLVE_STEP
	_board.queue_redraw()
	# what was cut free
	for p in pickups.duplicate():
		var pc: Vector2i = p["c"]
		if grid[_i(pc.x, pc.y)] == OWN:
			_take(p)
	# the splitter splits when enough is cut
	if taken - before >= SPLIT_SHARE:
		for f in foes.duplicate():
			if float(f["dead"]) < 0.0 and str(f["trick"]) == "splitter":
				_split(f)
	if is_boss_round(round_now):
		var mother: Dictionary = _mother()
		boss_share = _piece_share(mother["p"]) if not mother.is_empty() else 0.0
		if mother.is_empty() or boss_share <= SEAL_SHARE:
			if not mother.is_empty():
				mother["dead"] = 0.0
				_motes(_burst_points(mother["p"], 40.0, 120))
			said.emit("The Plague Mother is sealed!")
			_clear_round()
		return
	if taken >= target_for(round_now):
		_clear_round()


func _clear_round() -> void:
	state = State.CLEARED
	cleared_left = CLEARED_SECONDS
	best = maxi(best, round_now)
	best_ever = maxi(best_ever, round_now)
	round_cleared.emit(round_now)


func _mother() -> Dictionary:
	for f in foes:
		if str(f["size"]) == "boss" and float(f["dead"]) < 0.0:
			return f
	return {}


func _hit(from: Variant = null) -> void:
	"""Something reached the shot or its open line: the Ward takes it, or a
	life is lost - never twice inside GRACE_SECONDS."""
	if grace_left > 0.0 or state != State.PLAYING:
		return
	if ward:
		ward = false
		grace_left = GRACE_SECONDS
		hit_left = 0.3
		if from is Dictionary and (from as Dictionary).has("v"):
			(from as Dictionary)["v"] = -((from as Dictionary)["v"] as Vector2)
		said.emit("The Ward held!")
		return
	lose_life()


func lose_life() -> void:
	"""A slime touched the open cut: it is gone, the shot back where it
	started, a life less."""
	for c in line:
		grid[_i(c.x, c.y)] = OPEN
	line = []
	cutting = false
	fuse = -1.0
	_still = 0.0
	cutter = cut_from if _in_board(cut_from) and grid[_i(cut_from.x, cut_from.y)] == OWN else _nearest_edge(cut_from)
	cutter_px = px(cutter)
	_jump = true
	_path = []
	lives -= 1
	hit_left = HIT_SECONDS
	grace_left = GRACE_SECONDS
	hurt.emit()
	if lives <= 0:
		state = State.OVER
		best = maxi(best, round_now - 1)
		run_over.emit(round_now)


# =============================================================================
# THE SLIMES
# =============================================================================

func _slime_speed(f: Dictionary) -> float:
	var speed: float = FOE_SPEED * speed_for(round_now)
	match str(f["size"]):
		"elite":
			speed *= ELITE_SPEED
		"boss":
			speed *= BOSS_SPEED
	if slow_left > 0.0:
		speed *= SLOW_SPEED
	return speed


func _move_slimes(delta: float) -> void:
	for f in foes.duplicate():
		if float(f["dead"]) >= 0.0:
			continue
		var sprite: AnimatedSprite2D = f["sprite"]
		var p: Vector2 = f["p"]
		var v: Vector2 = f["v"]
		var r: float = float(f["r"])
		if state_at(p) == OWN:
			f["dead"] = 0.0
			continue
		f["t"] = float(f["t"]) + delta
		var t: float = float(f["t"])
		var dazed: float = float(f["dazed"])
		if dazed > 0.0:
			f["dazed"] = dazed - delta
		var speed: float = _slime_speed(f)
		var dir: Vector2 = v.normalized()
		var lift: float = 0.0
		match str(f["move"]):
			"glide":
				speed *= GLIDE_SPEED
			"zigzag":
				if fmod(t, ZIG_SECONDS) < delta:
					f["zig"] = -float(f["zig"])
					dir = dir.rotated(ZIG_TURN * float(f["zig"]))
			"hop":
				var phase: float = fmod(t, HOP_CYCLE)
				if phase < HOP_STILL:
					speed = 0.0
				else:
					speed *= HOP_SPEED
					lift = sin((phase - HOP_STILL) / (HOP_CYCLE - HOP_STILL) * PI) * 6.0
			"hunt":
				if not line.is_empty():
					dir = _turn_toward(dir, _nearest_line_px(p) - p, delta)
			"dart":
				speed *= DART_SPEED if fmod(t, DART_CYCLE) < DART_SECONDS else DART_REST
			"fade":
				sprite.modulate.a = 0.22 + 0.78 * (0.5 + 0.5 * cos(t * FADE_SPEED))
		if str(f["trick"]) == "hunter":
			var prey: Vector2 = _nearest_line_px(p) if not line.is_empty() else cutter_px
			dir = _turn_toward(dir, prey - p, delta)
		if dazed > 0.0:
			speed = 0.0
		var step: Vector2 = dir * speed * delta
		if gust_on > 0.0:
			step += gust_dir * GUST_PUSH * delta
		if v != Vector2.ZERO or gust_on > 0.0:
			var nx := p + Vector2(step.x, 0.0)
			var probe_x := nx + Vector2(signf(step.x) * r, 0.0)
			if step.x != 0.0 and state_at(probe_x) == OWN:
				dir.x = -dir.x
				if str(f["trick"]) == "gnawer":
					_gnaw(f, cell_at(probe_x))
			else:
				p = nx
			var ny := p + Vector2(0.0, step.y)
			var probe_y := ny + Vector2(0.0, signf(step.y) * r)
			if step.y != 0.0 and state_at(probe_y) == OWN:
				dir.y = -dir.y
				if str(f["trick"]) == "gnawer":
					_gnaw(f, cell_at(probe_y))
			else:
				p = ny
		f["p"] = p
		if v != Vector2.ZERO:
			f["v"] = dir.normalized() * _slime_speed(f)
		sprite.position = p + Vector2(0.0, -lift)
		f["gnaw"] = float(f["gnaw"]) - delta
		if str(f["size"]) == "boss":
			_brood(f, delta)
		# the open line, or the shot cutting it
		if cutting:
			if p.distance_to(cutter_px) <= r + 4.0:
				_hit(f)
				return
			for d in [Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r), Vector2.ZERO,
					Vector2(r, r) * 0.7, Vector2(-r, r) * 0.7, Vector2(r, -r) * 0.7, Vector2(-r, -r) * 0.7]:
				if state_at(p + d) == LINE:
					_hit(f)
					return


func _turn_toward(dir: Vector2, want: Vector2, delta: float) -> Vector2:
	if want.length() < 0.5 or dir == Vector2.ZERO:
		return dir
	var angle: float = dir.angle_to(want)
	return dir.rotated(clampf(angle, -TURN_RATE * delta, TURN_RATE * delta))


func _nearest_line_px(from: Vector2) -> Vector2:
	var best_px: Vector2 = cutter_px
	var best_d: float = INF
	for k in range(0, line.size(), 3):
		var q: Vector2 = px(line[k])
		var d: float = from.distance_squared_to(q)
		if d < best_d:
			best_d = d
			best_px = q
	return best_px


func _gnaw(f: Dictionary, at: Vector2i) -> void:
	"""The gnawer chews the cut edge back into cloth - never the border, a
	rock, near the shot, or while a cut is open."""
	if float(f["gnaw"]) > 0.0 or cutting:
		return
	f["gnaw"] = GNAW_GAP
	var chewed: Array = []
	for d in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var c: Vector2i = at + d
		if c.x < BORDER or c.y < BORDER or c.x >= COLS - BORDER or c.y >= ROWS - BORDER:
			continue
		var i: int = _i(c.x, c.y)
		if grid[i] != OWN or rock[i] == 1 or absi(c.x - cutter.x) + absi(c.y - cutter.y) <= GNAW_KEEP:
			continue
		var on_saw: bool = false
		for s in saws:
			on_saw = on_saw or s["c"] == c
		if on_saw:
			continue
		grid[i] = OPEN
		dissolving.erase(i)
		chewed.append(c)
	if chewed.is_empty():
		return
	_mark_edges()
	_count()
	_board.queue_redraw()


func _split(f: Dictionary) -> void:
	"""The splitter splits: two slimes of its kind where it stood."""
	f["dead"] = 0.0
	var dir: Vector2 = (f["v"] as Vector2).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	for turn in [PI / 2.0, -PI / 2.0]:
		_add_slime(str(f["kind"]), f["p"], dir.rotated(turn), "small", "")
	said.emit("The splitter split in two!")


func _brood(f: Dictionary, delta: float) -> void:
	"""The Plague Mother spits a slime every BROOD_SECONDS, while fewer than
	BROOD_MOST small ones are about."""
	f["brood"] = float(f["brood"]) - delta
	if float(f["brood"]) > 0.0:
		return
	f["brood"] = BROOD_SECONDS
	var smalls: int = 0
	for g in foes:
		if float(g["dead"]) < 0.0 and str(g["size"]) == "small":
			smalls += 1
	if smalls >= BROOD_MOST + BOSS_SLIMES:
		return
	_add_slime(str(f["kind"]), f["p"], Vector2.from_angle(_rng.randf() * TAU), "small", "")


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
# THE SAWS
# =============================================================================

func _move_saws(delta: float) -> void:
	"""Each saw rides the cut edge, straight on where it can, and touches the
	shot when the shot is on the edge (not cutting)."""
	var speed: float = SAW_SPEED * minf(1.5, speed_for(round_now)) * (SLOW_SPEED if slow_left > 0.0 else 1.0)
	for s in saws:
		s["spin"] = float(s["spin"]) + delta * 14.0
		s["step"] = float(s["step"]) - delta
		var guard: int = 0
		while float(s["step"]) <= 0.0 and guard < 4:
			guard += 1
			s["step"] = float(s["step"]) + float(CELL) / speed
			_saw_step(s)
		s["px"] = (s["px"] as Vector2).move_toward(px(s["c"]), speed * delta * 1.3)
		if not cutting and (s["px"] as Vector2).distance_to(cutter_px) <= SAW_R + 4.0:
			_hit(null)
			return


func _saw_step(s: Dictionary) -> void:
	var c: Vector2i = s["c"]
	var prev: Vector2i = s["prev"]
	var ahead: Vector2i = c - prev
	var ways: Array = []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = c + d
		if n != prev and is_edge(n):
			ways.append(n)
	var next: Vector2i = prev
	if ways.has(c + ahead) and ahead != Vector2i.ZERO and _rng.randf() < 0.85:
		next = c + ahead
	elif not ways.is_empty():
		next = ways[_rng.randi() % ways.size()]
	s["prev"] = c
	s["c"] = next


# =============================================================================
# THE LANDS' EFFECTS
# =============================================================================

func _land_effects(delta: float) -> void:
	match land:
		"light":
			_flare_left -= delta
			if _flare_left <= 0.0:
				_flare_left = FLARE_GAP
				var at: Vector2 = _spawn_spot(4.0)
				if not foes.is_empty() and _rng.randf() < 0.6:
					var f: Dictionary = foes[_rng.randi() % foes.size()]
					if float(f["dead"]) < 0.0:
						at = (f["p"] as Vector2) + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(4.0, 26.0)
				flares.append({"at": at, "warn": FLARE_WARN, "flash": 0.0})
			for fl in flares.duplicate():
				if float(fl["warn"]) > 0.0:
					fl["warn"] = float(fl["warn"]) - delta
					if float(fl["warn"]) <= 0.0:
						fl["flash"] = FLARE_FLASH
						for f in foes:
							if float(f["dead"]) < 0.0 and (f["p"] as Vector2).distance_to(fl["at"]) <= FLARE_R + float(f["r"]):
								f["dazed"] = DAZE_SECONDS * (0.5 if str(f["size"]) == "boss" else 1.0)
				else:
					fl["flash"] = float(fl["flash"]) - delta
					if float(fl["flash"]) <= 0.0:
						flares.erase(fl)
		"wind":
			if gust_on > 0.0:
				gust_on -= delta
			elif gust_warn > 0.0:
				gust_warn -= delta
				if gust_warn <= 0.0:
					gust_on = GUST_SECONDS
			else:
				_gust_left -= delta
				if _gust_left <= 0.0:
					_gust_left = GUST_GAP
					gust_dir = Vector2.from_angle(float(_rng.randi_range(0, 7)) * PI / 4.0)
					gust_warn = GUST_WARN
					_gust_seed = _rng.randi()
		"fire":
			if cutting and _still >= FUSE_AFTER and not line.is_empty():
				fuse = maxf(fuse, 0.0) + FUSE_SPEED * delta
				if fuse >= float(line.size() - 1):
					fuse = -1.0
					said.emit("The fuse caught you!")
					_hit(null)
			elif fuse >= 0.0:
				fuse -= FUSE_SPEED * delta
				if fuse < 0.0:
					fuse = -1.0


# =============================================================================
# PICKUPS
# =============================================================================

func _tick_pickups(delta: float) -> void:
	for p in pickups.duplicate():
		p["left"] = float(p["left"]) - delta
		if float(p["left"]) <= 0.0:
			pickups.erase(p)
	_pickup_left -= delta
	if _pickup_left > 0.0:
		return
	_pickup_left = PICKUP_GAP * _rng.randf_range(0.75, 1.25)
	if pickups.size() >= PICKUP_MOST:
		return
	var kind: String = "life" if lives < LIVES_MOST and _rng.randi() % LIFE_CHANCE == 0 \
		else ["swift", "ward", "slow"][_rng.randi() % 3]
	for tries in 30:
		var c := Vector2i(_rng.randi_range(BORDER + 6, COLS - BORDER - 7), _rng.randi_range(BORDER + 6, ROWS - BORDER - 7))
		if grid[_i(c.x, c.y)] != OPEN:
			continue
		var clear: bool = true
		for f in foes:
			clear = clear and (f["p"] as Vector2).distance_to(px(c)) > 40.0
		if clear:
			pickups.append({"kind": kind, "c": c, "left": PICKUP_SECONDS})
			return


func _take_pickup_at(c: Vector2i) -> void:
	for p in pickups.duplicate():
		var pc: Vector2i = p["c"]
		if absi(pc.x - c.x) <= 1 and absi(pc.y - c.y) <= 1:
			_take(p)


func _take(p: Dictionary) -> void:
	pickups.erase(p)
	match str(p["kind"]):
		"swift":
			swift_left = SWIFT_SECONDS
			said.emit("Swift! The shot is faster")
		"ward":
			ward = true
			said.emit("Ward! The next hit is taken for you")
		"slow":
			slow_left = SLOW_SECONDS
			said.emit("Slow! The slimes crawl")
		"life":
			lives = mini(LIVES_MOST, lives + 1)
			said.emit("A life!")
	_motes(_burst_points(px(p["c"]), 10.0, 24))


# =============================================================================
# WORDS AND GOLD
# =============================================================================

func gold_now() -> int:
	"""What the rounds cleared this run pay."""
	var gold: int = 0
	for which in range(1, best + 1):
		gold += gold_for_round(which, pays)
	return gold


func bosses_beaten() -> int:
	return floori(float(best) / float(BOSS_EVERY))


func round_title() -> String:
	if round_now > ENDLESS_AFTER:
		return "Endless %d" % (round_now - ENDLESS_AFTER)
	return "Round %d" % round_now


func land_name() -> String:
	return "The Plague Mother" if is_boss_round(round_now) else str(LAND_NAMES.get(land, ""))


func rule_line() -> String:
	if is_boss_round(round_now):
		return "Seal her into %d%% of the cloth" % roundi(SEAL_SHARE * 100.0)
	return str(LAND_RULES.get(land, ""))


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
	_bullet.z_index = 5
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
	_line_wisps.z_index = 4
	_line_wisps.scale_amount_max = 2.0
	add_child(_line_wisps)


func _make_dark() -> void:
	"""Dark's night: everything under it dark but a pool round the shot (a
	big soft hole, moved with the shot), the slimes' eyes drawn over it."""
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.06, 0.13, 1.0])
	gradient.colors = PackedColorArray([Color(0.02, 0.01, 0.04, 0.0), Color(0.02, 0.01, 0.04, 0.15),
		Color(0.02, 0.01, 0.04, 0.93), Color(0.02, 0.01, 0.04, 0.95)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 512
	texture.height = 512
	_dark = Sprite2D.new()
	_dark.name = "dark"
	_dark.texture = texture
	_dark.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_dark.z_index = 3
	# the hole's soft edge is about 0.13 of half the texture across
	_dark.scale = Vector2.ONE * (DARK_RADIUS / (0.13 * 256.0))
	_dark.visible = false
	add_child(_dark)


func _wisps(count: int, shape: CPUParticles2D.EmissionShape, at_scale: float) -> CPUParticles2D:
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
	if _dark.visible:
		_dark.position = cutter_px
		_dark.reset_physics_interpolation()
	if line.size() != _last_line_size:
		_last_line_size = line.size()
		var points := PackedVector2Array()
		for c in line:
			points.append(px(c))
		_line_wisps.emitting = not points.is_empty()
		if not points.is_empty():
			_line_wisps.emission_points = points
			_line_wisps.amount = clampi(points.size() * 3, 24, 400)


func _burst_points(at: Vector2, radius: float, n: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for k in n:
		points.append(at + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf() * radius)
	return points


func _motes(points: PackedVector2Array) -> void:
	"""What is cut away rises off as green motes as it dissolves."""
	if points.is_empty():
		return
	var motes := _wisps(clampi(points.size(), 16, 600), CPUParticles2D.EMISSION_SHAPE_POINTS, 1.0)
	motes.z_index = 4
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

func _look(k: int) -> Color:
	return (LOOKS.get(land, LOOKS["light"]) as Array)[k]


func _void_colour(y: float) -> Color:
	var k: float = clampf((y - ORIGIN.y) / (ROWS * CELL), 0.0, 1.0)
	return _look(3).lerp(Color(0.012, 0.012, 0.024), k)


func _draw_board() -> void:
	"""The cloth, its ink, the dark where it is cut and the frayed edges, in
	its land's colours - drawn again only when the board changes."""
	var board := Rect2(ORIGIN, Vector2(COLS, ROWS) * CELL)
	var linen: Color = _look(0)
	_board.draw_rect(Rect2(Vector2.ZERO, VIEW), Color(0.03, 0.028, 0.05))
	_board.draw_rect(board, linen)
	var y: float = board.position.y
	while y < board.end.y:
		_board.draw_line(Vector2(board.position.x, y + 0.5), Vector2(board.end.x, y + 0.5), Color(linen.darkened(0.35), 0.10), 1.0)
		y += 2.0
	var x: float = board.position.x
	while x < board.end.x:
		_board.draw_line(Vector2(x + 0.5, board.position.y), Vector2(x + 0.5, board.end.y), Color(1.0, 0.97, 0.9, 0.07), 1.0)
		x += 2.0
	_draw_wet()
	_draw_ink(board)
	_draw_vignette(board)
	_draw_land_rim(board)
	for row in ROWS:
		var col: int = 0
		while col < COLS:
			var s: int = grid[_i(col, row)]
			var run: int = 1
			while col + run < COLS and grid[_i(col + run, row)] == s \
					and dissolving.has(_i(col, row)) == dissolving.has(_i(col + run, row)) \
					and rock[_i(col, row)] == rock[_i(col + run, row)]:
				run += 1
			if s == OWN and rock[_i(col, row)] == 0:
				var r := Rect2(ORIGIN + Vector2(col, row) * CELL, Vector2(run * CELL, CELL))
				_board.draw_rect(r, _void_colour(r.position.y))
				if dissolving.has(_i(col, row)):
					# each cell holds as light until its own moment, in no order
					for q in run:
						var lit: float = clampf(float(dissolving.get(_i(col + q, row), 0.0)) / DISSOLVE, 0.0, 1.0)
						var h: int = absi(((col + q) * 73856093) ^ (row * 19349663)) % 997
						if lit > float(h) / 997.0:
							_board.draw_rect(Rect2(ORIGIN + Vector2(col + q, row) * CELL, Vector2(CELL, CELL)),
								linen.lerp(Color(0.88, 1.0, 0.8), 0.35 + 0.65 * (1.0 - lit)))
			col += run
	for p in _specks:
		var pc := cell_at(p)
		if state_at(p) == OWN and rock[_i(pc.x, pc.y)] == 0 and not dissolving.has(_i(pc.x, pc.y)):
			_board.draw_rect(Rect2(p, Vector2(1, 1)), Color(0.7, 0.75, 1.0, 0.2))
	_draw_rocks()
	_draw_cut_edges()


func _draw_wet() -> void:
	"""Water's wet patches: darker, bluer cloth with a tide line."""
	if land != "water":
		return
	var stain: Color = Color(0.22, 0.45, 0.72, 0.20)
	for row in ROWS:
		var col: int = 0
		while col < COLS:
			if wet[_i(col, row)] == 0:
				col += 1
				continue
			var run: int = 1
			while col + run < COLS and wet[_i(col + run, row)] == 1:
				run += 1
			_board.draw_rect(Rect2(ORIGIN + Vector2(col, row) * CELL, Vector2(run * CELL, CELL)), stain)
			col += run
	for spot in _wet_spots:
		var c: Vector2 = px((spot as Array)[0])
		var r: float = float((spot as Array)[1]) * CELL
		_board.draw_set_transform(c, 0.0, Vector2(1.0, 1.0 / 1.4))
		_board.draw_circle(Vector2.ZERO, r * 0.7, Color(0.30, 0.55, 0.85, 0.10))
		_board.draw_arc(Vector2.ZERO, r * 0.35, 0.4, TAU - 0.2, 28, Color(0.85, 0.94, 1.0, 0.35), 1.0)
		_board.draw_arc(Vector2.ZERO, r * 0.6, 1.2, TAU + 0.6, 36, Color(0.85, 0.94, 1.0, 0.25), 1.0)
		_board.draw_arc(Vector2.ZERO, r * 0.95, 0.3, TAU - 0.4, 44, Color(0.15, 0.32, 0.5, 0.35), 1.0)
		_board.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_rocks() -> void:
	"""Earth's rocks: grey-brown stone, lit from the top left."""
	if _rock_spots.is_empty():
		return
	for row in ROWS:
		for col in COLS:
			if rock[_i(col, row)] == 0:
				continue
			var h: int = absi((col * 73856093) ^ (row * 19349663)) % 7
			var shade: Color = Color(0.46, 0.41, 0.36).lightened(float(h) * 0.02)
			var lit_side: bool = _in_board(Vector2i(col - 1, row - 1)) and rock[_i(col - 1, row - 1)] == 0
			var dark_side: bool = _in_board(Vector2i(col + 1, row + 1)) and rock[_i(col + 1, row + 1)] == 0
			if lit_side:
				shade = shade.lightened(0.22)
			elif dark_side:
				shade = shade.darkened(0.35)
			_board.draw_rect(Rect2(ORIGIN + Vector2(col, row) * CELL, Vector2(CELL, CELL)), shade)


func _draw_land_rim(board: Rect2) -> void:
	"""Each land's own mark on the parchment's rim: ice frost-bitten, fire
	burnt, wind worn to streaks, light gilded, dark starred."""
	match land:
		"ice":
			for k in 120:
				var h: int = absi(k * 2654435761) % 10007
				var along: float = float(h % 1000) / 1000.0
				var side: int = k % 4
				var reach: float = 4.0 + float((h >> 4) % 9)
				var at: Vector2 = [Vector2(board.position.x + board.size.x * along, board.position.y),
					Vector2(board.position.x + board.size.x * along, board.end.y),
					Vector2(board.position.x, board.position.y + board.size.y * along),
					Vector2(board.end.x, board.position.y + board.size.y * along)][side]
				var inward: Vector2 = [Vector2.DOWN, Vector2.UP, Vector2.RIGHT, Vector2.LEFT][side]
				var tilt: float = (float((h >> 8) % 7) - 3.0) * 0.15
				var tip: Vector2 = at + inward.rotated(tilt) * reach
				_board.draw_line(at, tip, Color(0.92, 0.97, 1.0, 0.75), 1.0)
				_board.draw_line(at.lerp(tip, 0.5), at.lerp(tip, 0.5) + inward.rotated(tilt + 0.8) * reach * 0.35,
					Color(0.85, 0.95, 1.0, 0.6), 1.0)
		"fire":
			for k in 90:
				var h: int = absi((k + 7) * 2654435761) % 10007
				var along: float = float(h % 1000) / 1000.0
				var side: int = k % 4
				var r: float = 5.0 + float((h >> 5) % 10)
				var at: Vector2 = [Vector2(board.position.x + board.size.x * along, board.position.y),
					Vector2(board.position.x + board.size.x * along, board.end.y),
					Vector2(board.position.x, board.position.y + board.size.y * along),
					Vector2(board.end.x, board.position.y + board.size.y * along)][side]
				_board.draw_circle(at, r * 1.6, Color(0.30, 0.12, 0.04, 0.16))
				_board.draw_circle(at, r, Color(0.10, 0.04, 0.02, 0.45))
		"wind":
			for k in 26:
				var h: int = absi((k + 3) * 2654435761) % 10007
				var at := board.position + Vector2(float(h % 600) / 600.0 * board.size.x, float((h >> 3) % 300) / 300.0 * board.size.y)
				var length: float = 30.0 + float((h >> 6) % 40)
				var points := PackedVector2Array()
				for q in 9:
					var t: float = float(q) / 8.0
					points.append(at + Vector2(t * length, sin(t * 4.0 + float(k)) * 2.5))
				_board.draw_polyline(points, Color(0.35, 0.36, 0.32, 0.16), 1.0)
		"light":
			_board.draw_rect(board, Color(1.0, 0.92, 0.55, 0.06))
		"dark":
			for k in 40:
				var h: int = absi((k + 11) * 2654435761) % 10007
				var at := board.position + Vector2(float(h % 600) / 600.0 * board.size.x, float((h >> 3) % 300) / 300.0 * board.size.y)
				_board.draw_rect(Rect2(at, Vector2(1, 1)), Color(0.35, 0.28, 0.45, 0.35))


func _draw_ink(board: Rect2) -> void:
	"""An old map's faded ink: a coast and its shallows, a dotted road, hills,
	a compass rose."""
	var ink := Color(0.30, 0.19, 0.11, 0.24) if land != "dark" else Color(0.18, 0.10, 0.24, 0.3)
	var coast := PackedVector2Array()
	var shallow := PackedVector2Array()
	var wave: float = float(LANDS.find(land)) * 0.9
	for k in 80:
		var t: float = float(k) / 79.0
		var yy: float = board.size.y * (0.58 + 0.10 * sin(t * 8.5 + 0.6 + wave) + 0.04 * sin(t * 21.0))
		coast.append(board.position + Vector2(t * board.size.x, yy))
		shallow.append(board.position + Vector2(t * board.size.x, yy + 9.0 + 3.0 * sin(t * 13.0)))
	_board.draw_polyline(coast, ink, 1.2)
	for k in range(0, shallow.size() - 1, 2):
		_board.draw_line(shallow[k], shallow[k + 1], Color(ink, ink.a * 0.6), 1.0)
	var road := PackedVector2Array()
	for k in 40:
		var t: float = float(k) / 39.0
		road.append(board.position + Vector2(board.size.x * (0.08 + 0.55 * t), board.size.y * (0.18 + 0.26 * t + 0.06 * sin(t * 6.0 + wave))))
	for k in range(0, road.size() - 1, 2):
		_board.draw_line(road[k], road[k + 1], ink, 1.0)
	for at in [Vector2(0.18, 0.12), Vector2(0.24, 0.16), Vector2(0.71, 0.14), Vector2(0.77, 0.19), Vector2(0.45, 0.30)]:
		var p: Vector2 = board.position + board.size * at
		_board.draw_polyline(PackedVector2Array([p + Vector2(-6, 3), p + Vector2(0, -4), p + Vector2(6, 3)]), ink, 1.1)
	var rose: Vector2 = board.position + Vector2(board.size.x - 34.0, board.size.y - 34.0)
	_board.draw_arc(rose, 14.0, 0.0, TAU, 32, ink, 1.0)
	for k in 4:
		var a: float = float(k) * PI / 2.0 - PI / 2.0
		var tip := rose + Vector2.from_angle(a) * 19.0
		var l := rose + Vector2.from_angle(a + PI / 2.0) * 3.0
		var r := rose + Vector2.from_angle(a - PI / 2.0) * 3.0
		_board.draw_colored_polygon(PackedVector2Array([tip, l, rose, r]), Color(ink, ink.a * (1.6 if k == 0 else 1.0)))


func _draw_vignette(board: Rect2) -> void:
	var dark: Color = _look(1)
	var clear := Color(dark, 0.0)
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
	var thread: Color = _look(2)
	var hem: Color = _look(0).darkened(0.45)
	for row in ROWS:
		for col in COLS:
			if grid[_i(col, row)] != OWN or edge[_i(col, row)] == 0:
				continue
			for d in [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1)]:
				var n: Vector2i = Vector2i(col, row) + d
				if not _in_board(n) or grid[_i(n.x, n.y)] == OWN:
					continue
				var cell := Rect2(ORIGIN + Vector2(col, row) * CELL, Vector2(CELL, CELL))
				if rock[_i(col, row)] == 0:
					var shade: float = 0.55 if d.y == -1 else (0.4 if d.x == -1 else 0.18)
					_board.draw_rect(cell, Color(0.0, 0.0, 0.0, shade))
				var rim: Vector2 = cell.get_center() + Vector2(d) * (CELL * 0.5)
				var side := Vector2(-d.y, d.x)
				_board.draw_line(rim - side * 2.0, rim + side * 2.0, Color(hem, 0.85), 1.0)
				if rock[_i(col, row)] == 1:
					continue
				var h: int = absi((col * 73856093) ^ (row * 19349663))
				for k in 2:
					var hh: int = (h >> (k * 5)) & 1023
					var reach: float = 0.8 + float(hh % 6) * 0.35
					var tilt: float = (float((hh >> 3) % 5) - 2.0) * 0.12
					var root := rim + side * (-1.0 + 2.0 * float(k))
					var out := (-Vector2(d)).rotated(tilt)
					_board.draw_line(root, root + out * reach, Color(thread.darkened(0.12), 0.45 + 0.08 * float(hh % 4)), 1.0, true)


func _draw_under() -> void:
	"""Under the slimes: their shadows, and a flare's warning ring."""
	for f in foes:
		if float(f["dead"]) < 0.0:
			var r: float = float(f["r"])
			_under.draw_set_transform((f["p"] as Vector2) + Vector2(0, r * 0.8), 0.0, Vector2(1.0, 0.45))
			_under.draw_circle(Vector2.ZERO, r + 1.0, Color(0.15, 0.08, 0.03, 0.28))
	_under.draw_set_transform(cutter_px + Vector2(0, 6), 0.0, Vector2(1.0, 0.45))
	_under.draw_circle(Vector2.ZERO, 8.0, Color(0.08, 0.12, 0.05, 0.3))
	_under.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for fl in flares:
		if float(fl["warn"]) > 0.0:
			var k: float = 1.0 - float(fl["warn"]) / FLARE_WARN
			_under.draw_arc(fl["at"], FLARE_R * k, 0.0, TAU, 40, Color(1.0, 0.9, 0.45, 0.35 + 0.4 * k), 1.5)
			_under.draw_circle(fl["at"], 3.0 + 3.0 * k, Color(1.0, 0.95, 0.7, 0.6))


func _draw_fx() -> void:
	"""What moves over the slimes: the open cut as the shot's dotted glowing
	trail (burnt where the fuse has run), the saws, the pickups, a flare's
	flash, the gusts' streaks, slimes' eyes in the dark, the Ward."""
	_draw_trail()
	for s in saws:
		_draw_saw(s["px"], float(s["spin"]))
	for p in pickups:
		_draw_pickup(p)
	for fl in flares:
		if float(fl["warn"]) <= 0.0:
			var a: float = clampf(float(fl["flash"]) / FLARE_FLASH, 0.0, 1.0)
			_fx.draw_circle(fl["at"], FLARE_R, Color(1.0, 0.95, 0.7, 0.35 * a))
			_fx.draw_circle(fl["at"], FLARE_R * 0.4, Color(1.0, 1.0, 0.9, 0.6 * a))
	if gust_warn > 0.0 or gust_on > 0.0:
		_draw_gust()
	if _dark.visible:
		for f in foes:
			if float(f["dead"]) < 0.0:
				var at: Vector2 = (f["sprite"] as Node2D).position
				var r: float = float(f["r"])
				var glow: Color = Element.COLOURS.get(_element_of(str(f["kind"])), Color.WHITE)
				_fx.draw_circle(at, r + 2.0, Color(glow, 0.12))
				_fx.draw_rect(Rect2(at + Vector2(-r * 0.4 - 1, -1), Vector2(2, 2)), Color(1.0, 0.95, 0.8, 0.9))
				_fx.draw_rect(Rect2(at + Vector2(r * 0.4 - 1, -1), Vector2(2, 2)), Color(1.0, 0.95, 0.8, 0.9))
	if ward:
		var pulse: float = 0.6 + 0.4 * sin(_t * 6.0)
		_fx.draw_arc(cutter_px, 10.0, 0.0, TAU, 32, Color(1.0, 0.85, 0.35, 0.7 * pulse), 1.5)


func _element_of(kind: String) -> int:
	match kind:
		"light":
			return Element.Type.LIGHT
		"wind":
			return Element.Type.WIND
		"water":
			return Element.Type.WATER
		"ice":
			return Element.Type.ICE
		"earth":
			return Element.Type.EARTH
		"fire":
			return Element.Type.FIRE
		"dark":
			return Element.Type.DARK
	return Element.Type.NONE


func _draw_trail() -> void:
	var n: int = line.size()
	var burnt: int = floori(fuse) if fuse >= 0.0 else -1
	for k in n:
		var c: Vector2i = line[k]
		var h: int = absi((c.x * 73856093) ^ (c.y * 19349663))
		var p: Vector2 = px(c) + Vector2(float(h % 3) - 1.0, float((h >> 3) % 3) - 1.0) * 0.6
		if k <= burnt:
			_fx.draw_rect(Rect2(p - Vector2(1, 1), Vector2(2, 2)), Color(0.15, 0.06, 0.03, 0.85))
			continue
		var age: float = float(n - 1 - k) / maxf(1.0, float(n))
		var twinkle: float = 0.7 + 0.3 * sin(_t * 8.0 + float(k) * 1.7)
		var colour: Color = Color(1.0, 1.0, 0.92).lerp(MOTE_GREEN, clampf(age * 3.0, 0.0, 1.0))
		_fx.draw_circle(p, 1.8, Color(0.15, 0.45, 0.15, 0.22 * twinkle))
		_fx.draw_rect(Rect2(p - Vector2(0.5, 0.5), Vector2(1, 1)), Color(colour, twinkle))
		if h % 5 == 0:
			_fx.draw_circle(p, 2.2, Color(0.55, 0.95, 0.42, 0.35 * twinkle))
			_fx.draw_rect(Rect2(p - Vector2(1, 1), Vector2(2, 2)), Color(1.0, 1.0, 0.92, twinkle))
	if burnt >= 0 and burnt < n:
		var spark: Vector2 = px(line[burnt])
		var flick: float = 0.7 + 0.3 * sin(_t * 30.0)
		_fx.draw_circle(spark, 4.0 * flick, Color(1.0, 0.45, 0.1, 0.45))
		_fx.draw_circle(spark, 2.0, Color(1.0, 0.85, 0.4, 0.95))


func _draw_saw(at: Vector2, spin: float) -> void:
	"""An edge saw: a steel disc with eight teeth, spinning."""
	var teeth := PackedVector2Array()
	for k in 16:
		var a: float = spin + float(k) * TAU / 16.0
		teeth.append(at + Vector2.from_angle(a) * (SAW_R + 1.5 if k % 2 == 0 else SAW_R - 1.0))
	_fx.draw_colored_polygon(teeth, Color(0.72, 0.74, 0.78))
	_fx.draw_circle(at, SAW_R - 2.0, Color(0.52, 0.54, 0.6))
	_fx.draw_arc(at, SAW_R - 2.5, spin, spin + 2.0, 8, Color(0.92, 0.94, 1.0, 0.8), 1.0)
	_fx.draw_circle(at, 1.5, Color(0.2, 0.2, 0.24))


func _draw_pickup(p: Dictionary) -> void:
	"""A pickup on the cloth: a coloured token, bobbing, blinking at the end."""
	var left: float = float(p["left"])
	if left < 3.0 and int(_t * 8.0) % 2 == 0:
		return
	var at: Vector2 = px(p["c"]) + Vector2(0.0, sin(_t * 3.0) * 1.2)
	var kind: String = str(p["kind"])
	var colour: Color = {"swift": Color(0.45, 0.95, 0.5), "ward": Color(1.0, 0.82, 0.3),
		"slow": Color(0.45, 0.7, 1.0), "life": Color(1.0, 0.35, 0.4)}.get(kind, Color.WHITE)
	_fx.draw_circle(at, 9.0, Color(colour, 0.18))
	_fx.draw_circle(at, 6.0, Color(0.08, 0.06, 0.1, 0.85))
	_fx.draw_arc(at, 6.0, 0.0, TAU, 24, colour, 1.2)
	match kind:
		"swift":
			for dx in [-2.0, 1.0]:
				_fx.draw_polyline(PackedVector2Array([at + Vector2(dx - 1.0, -2.5), at + Vector2(dx + 1.5, 0.0), at + Vector2(dx - 1.0, 2.5)]), colour, 1.2)
		"ward":
			_fx.draw_colored_polygon(PackedVector2Array([at + Vector2(-3, -3), at + Vector2(3, -3), at + Vector2(3, 0),
				at + Vector2(0, 3.5), at + Vector2(-3, 0)]), colour)
		"slow":
			_fx.draw_colored_polygon(PackedVector2Array([at + Vector2(-2.5, -3), at + Vector2(2.5, -3), at]), colour)
			_fx.draw_colored_polygon(PackedVector2Array([at, at + Vector2(2.5, 3), at + Vector2(-2.5, 3)]), colour)
		"life":
			_fx.draw_circle(at + Vector2(-1.3, -0.8), 1.7, colour)
			_fx.draw_circle(at + Vector2(1.3, -0.8), 1.7, colour)
			_fx.draw_colored_polygon(PackedVector2Array([at + Vector2(-3, -0.4), at + Vector2(3, -0.4), at + Vector2(0, 3)]), colour)


func _draw_gust() -> void:
	"""Wind's streaks: faint while it warns, strong while it blows."""
	var strong: bool = gust_on > 0.0
	var board := Rect2(ORIGIN, Vector2(COLS, ROWS) * CELL)
	var rng := RandomNumberGenerator.new()
	rng.seed = _gust_seed
	var drift: float = fmod(_t * (160.0 if strong else 40.0), 80.0)
	for k in 22:
		var at := board.position + Vector2(rng.randf() * board.size.x, rng.randf() * board.size.y)
		at += gust_dir * (drift - 40.0)
		var length: float = rng.randf_range(14.0, 30.0)
		var a: float = (0.45 if strong else 0.18) * (0.6 + 0.4 * rng.randf())
		_fx.draw_line(at, at + gust_dir * length, Color(0.95, 0.98, 1.0, a), 1.0)


func measure_label() -> String:
	"""Where this minigame stands, for the readout's Measure (placemeasure.gd)."""
	return "Cut the Cloth - round %d, %s" % [round_now, land]


static func scenes_to_warm() -> Array:
	"""Each round's slime, in the order the rounds come, and the turret's shot."""
	var out: Array = []
	for which in range(1, MOVES.size() + 1):
		var path: String = "res://scene/enemy/%s.tscn" % str(SLIME_SCENES.get(land_of(which), "waterslime"))
		if not out.has(path):
			out.append(path)
	out.append("res://scene/projectiles/turretprojectile.tscn")
	return out
