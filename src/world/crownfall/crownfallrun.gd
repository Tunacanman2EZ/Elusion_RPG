# crownfallrun.gd - CROWNFALL's play (0.162.0): a brick breaker through the
# seven monster kingdoms (crownfallmaps.gd has the story and the maps).
#
# The owner: "draw out a brick breaker let me see a video", then "improve the
# game ui majorly and make the bricks more structural brick breaker games were
# known for bonuses and complex maps", then the story and "a ton of new maps".
# Two sketches came first (zz/brickpic.gd, zz/brickpic2.gd); this is the game.
#
# WHAT IS ON SCREEN, all drawn here in code at VIEW (1280 x 720) - the screen
# (crownfallscreen.gd) shows it in a SubViewport, scaled:
#   - the arena (ARENA), its stone frame, and in it the map: bricks set in the
#     stone of the place they belong to, so a hole reads as a hole in a wall;
#   - the paddle, glowing so its ends show from the corner of the eye;
#   - TRACERS - bright streaks along a faint line (the owner kept the idea for
#     this game): the aim before a launch, each ball's own path, the laser;
#   - the top bar (kingdom, map, score, the run's gold, the combo meter,
#     lives), the left panel (bonuses on, and what can fall), the right panel
#     (how much is broken, the kingdom's five maps);
#   - between runs, the kingdom map (State.KINGDOMS): seven kingdoms, the made
#     one's maps to pick from.
#
# THE RULES:
#   - The paddle follows `target_x` (the mouse, keys or a finger, set by the
#     screen). A ball waits on it, aimed, until launch().
#   - A map is cleared when every brick that can break is broken - blight
#     included, which grows back (BLIGHT_EVERY). A citadel is cleared when
#     its ruler falls. Cleared, the next map comes; the run's gold is the sum
#     of what each map cleared pays (`pays`, the server's table, handed in at
#     Go), and the server pays it at Leave.
#   - Every ball lost is a life (LIVES); with none left the run is over.
#   - Bonuses fall from ? bricks and every BONUS_EVERY bricks: the paddle
#     catches them (BONUS, BONUS_ORDER).
#   - A citadel's ruler (the kingdom's monster, from its own art, recoloured
#     by its land) walks its hall, takes the ball's
#     hits, and throws at the paddle: a hit stuns it for STUN_SECONDS.
# No class_name; the screen preloads it.
extends Node2D

const Maps := preload("res://src/world/crownfall/crownfallmaps.gd")
const Boss := preload("res://src/world/crownfall/crownfallboss.gd")

signal map_cleared(index: int)
signal life_lost
signal run_over
signal said(text: String)

enum State { KINGDOMS, AIM, PLAY, CLEARED, OVER }

const VIEW := Vector2(1280, 720)
const ARENA := Rect2(160, 86, 960, 620)
# THE GRID (the owner: "make the maps bigger", "dense maps with designs in
# the bricks"): Maps.COLS (32) bricks of CW x CH across the arena's 960, up
# to Maps.ROWS_MOST (18) rows, the first at MAP_TOP.
const CW := 30.0
const CH := 15.0
const MAP_TOP := 112.0
const ROW_GAP := 2.0
const PADDLE_Y := 662.0
const PADDLE_W := 140.0
const PADDLE_WIDE := 230.0
const PADDLE_SPEED := 1700.0
const SHIELD_Y := 694.0
const BALL_R := 6.0
const SPEED := 560.0
const SLOW_SHARE := 0.62
const MOST_BALLS := 6
const LIVES := 3
const CLEARED_SECONDS := 2.6
const BLIGHT_EVERY := 9.0
const BLIGHT_MOST := 6
# A bonus every BONUS_EVERY bricks (the maps hold hundreds now), at most
# CAPS_MOST falling at once - a ? brick always drops one, the cap aside.
const BONUS_EVERY := 30
const CAPS_MOST := 3
# A reaction says its name at most every REACT_WORD_GAP seconds; a clash says
# nothing (the owner's pictures: words piled up).
const REACT_WORD_GAP := 0.3
const CAPSULE_FALL := 175.0
const LASER_EVERY := 0.28
const STUN_SECONDS := 0.8
const MIRROR_BEND := 22.0
const STEEPEST_FLAT := 0.28
const AIM_SWAY := 50.0
const AIM_SWAY_SPEED := 1.6
const WORD_TRIES := 8
# The kingdom map's panel: the picked kingdom's maps, five stretches of five,
# each stretch ending in its boss.
const MAP_PANEL := Rect2(340, 352, 600, 288)
const NODE_GAP := Vector2(100, 44)
const CRUMBLE_SECONDS := 1.6
const BANNER_SECONDS := 2.4
const WORD_GAP := 6.0
const SCORE := {"land": 50, "stone": 120, "tnt": 80, "bonus": 150, "blight": 60, "heart": 1500, "crystal": 120,
	"key": 200, "gold": 400, "rune": 150, "shell": 100, "prism": 120, "mimic": 100, "plague": 80, "mix": 150,
	"guard": 150, "clam": 250, "buoy": 80, "bubble": 60}
const LAND_OF := {"l": "light", "a": "wind", "w": "water", "i": "ice", "e": "earth", "f": "fire", "d": "dark"}
const COLOURS := {
	"dark": Color(0.427, 0.157, 0.851), "fire": Color(1.0, 0.416, 0.122), "earth": Color(0.631, 0.384, 0.027),
	"ice": Color(0.404, 0.91, 0.976), "water": Color(0.231, 0.51, 0.965), "wind": Color(0.655, 0.953, 0.816),
	"light": Color(0.992, 0.902, 0.541),
}
const BLIGHT := Color(0.42, 0.62, 0.24)
const MIRROR_BLUE := Color(0.36, 0.55, 0.92)
# THE SIDE LANES (the owner: "a small gap on the left and right of the maps
# use unbreakable brick"): SIDE_GAP of open floor between each wall and the
# bricks - every map drawn a touch narrower to fit, so no design loses a
# column - and an iron RAIL down the field's side from the arena's top to the
# foot of its rows, open only at two gates GATE_H tall. A ball in a lane
# comes back down unless it is aimed through a gate.
const SIDE_GAP := 32.0
const FIELD_X := 192.0      # ARENA.position.x + SIDE_GAP
const FIELD_W := 896.0      # ARENA.size.x - 2 * SIDE_GAP
const RAIL_W := 5.0
const GATE_H := 36.0
# THE GUARD (the owner: "bricks that protect for defense"): two hits, and
# while it stands no brick touching it - the eight round it - can be hurt.
const GUARD_GLOW := Color(0.55, 0.75, 1.0)
# THE ELEMENTS MIXED (the owner: "we can mix elements in bricks if needed for
# more effects"): the ball takes the element of each land brick it breaks
# (`el`), and breaking another land's while it carries one sets the two off.
const ELEMENTS := ["light", "wind", "water", "ice", "earth", "fire", "dark"]
const REACTIONS := {
	"fire+ice": "steam", "fire+wind": "firestorm", "ice+water": "glacier", "water+wind": "storm",
	"earth+fire": "magma", "ice+wind": "blizzard", "dark+light": "eclipse",
}
const REACTION_WORDS := {"steam": "STEAM!", "firestorm": "FIRESTORM!", "glacier": "GLACIER!", "storm": "STORM!",
	"magma": "MAGMA!", "blizzard": "BLIZZARD!", "eclipse": "ECLIPSE!", "clash": "CLASH!"}
# A mixed brick (a digit on the map) is its reaction waiting to be broken.
const MIXED := {"1": "steam", "2": "firestorm", "3": "glacier", "4": "storm", "5": "magma", "6": "blizzard",
	"7": "eclipse"}
const MIX_LANDS := {"steam": ["fire", "ice"], "firestorm": ["fire", "wind"], "glacier": ["water", "ice"],
	"storm": ["water", "wind"], "magma": ["earth", "fire"], "blizzard": ["ice", "wind"], "eclipse": ["light", "dark"],
	"clash": ["light", "light"]}
const STORM_JUMPS := 4
const STORM_REACH := 260.0
const DRIP_DEPTH := 6
const DRIP_SPEED := 380.0
const SHARD_DEPTH := 6
const SHATTER_STEP := 0.06
const REACT_DEPTH := 2
# A BALL HITS A BOSS FOR BALL_HIT; a laser for 1 (crownfallboss.gd's HP).
const BALL_HIT := 3
const BOSS_HIT_GAP := 0.2
# HOW FAR A REACTION REACHES (measured with the bot, M3: a firestorm burning
# the whole row, and the mixed bricks it burnt each going off, cleared 90%
# of The Mixing Well in under six seconds): a firestorm burns FIRESTORM_REACH
# cells each way; an eclipse hits the ECLIPSE_MOST bricks of the land most
# left nearest it; a mixed brick goes off only when the ball breaks it or a
# reaction does - never a burn, a drip, a shatter or TNT.
const FIRESTORM_REACH := 5
# FIRE SPREADS to the fire bricks touching it, FIRE_SPREAD steps from the
# brick that caught at most (a 48-wide band of fire burnt down whole).
const FIRE_SPREAD := 3
# THE CORE SHATTERED sends a shockwave (the owner: "making the pupil act as
# a high-value weak point"): every brick within CORE_BLAST takes a hit, and
# a bonus always falls.
const CORE_BLAST := 130.0
const ECLIPSE_MOST := 16
# THE NEW BRICKS, and the ones that change
const RUNE_CYCLE := 3.6
const RUNE_LIT := 1.6
const PRISM_EVERY := 1.2
const BUMPER_KICK := 1.4
const PORTAL_WAIT := 0.25
const CRYSTAL_SPREAD := 24.0
const CORRUPT_CHANCE := 0.5
const DRIFT_REACH := 3
const DRIFT_SPEED := 0.8
const PORTAL_HUES := [Color(0.62, 0.32, 0.95), Color(0.2, 0.85, 0.8), Color(1.0, 0.45, 0.75), Color(1.0, 0.6, 0.2)]
# THE LAST FEW BRICKS (the owner's video: a long chase for the last four):
# with PULL_BELOW or fewer standing, they glow and a rising ball turns
# toward the nearest, PULL_TURN degrees a second at most.
const PULL_BELOW := 6
const PULL_TURN := 40.0
const UNBREAKABLE := ["iron", "mirror", "bumper", "portal", "lock", "whirl"]
# THE KINGDOM OF WIND (0.163.0): GUSTS - bands of a map's rows ("gusts" in
# its data: [first row, last row, way]) that push a ball sideways while it is
# in them, GUST_PUSH a second; WHIRLS (W) that never break and fling the ball
# off in a direction of their own; KITES (k) - wind bricks that bob up and
# down into the room above and below them, KITE_REACH cells at most.
const GUST_PUSH := 900.0
const KITE_REACH := 2
const KITE_SPEED := 1.3
# THE KINGDOM OF WATER (0.164.0) - "a tide that rebuilds what you leave too
# long". THE TIDE: a map's "tide" is the row it reaches up to. Every
# TIDE_EVERY the water rises from the foot of the rows (TIDE_RISE), stands
# TIDE_HIGH and falls; as it stands, every cell under the mark broken more
# than TIDE_WAIT ago comes back as a one-hit water brick - TIDE_MOST at most a
# tide, the oldest first, never where a ball is, never a core, a Guard, a key,
# a lock or a bonus's cell. BUOYS (u): a water brick that floats up into the
# hole above it, a cell each BUOY_RISE. BUBBLES (o): broken, a bubble rises up
# the column at BUBBLE_SPEED and breaks the first brick it meets. CLAMS (Q):
# open CLAM_OPEN of every CLAM_CYCLE, each at its own moment; shut, nothing
# hurts them; open, one hit, and the pearl always drops a bonus.
const TIDE_EVERY := 30.0
const TIDE_RISE := 2.5
const TIDE_HIGH := 2.0
const TIDE_WAIT := 20.0
const TIDE_MOST := 12
const TIDE_KEEP := ["heart", "guard", "key", "lock", "bonus"]
const BUOY_RISE := 0.3
const BUBBLE_SPEED := 300.0
const CLAM_CYCLE := 5.0
const CLAM_OPEN := 2.0
const GOLD := Color(1.0, 0.82, 0.38)
const INK := Color(0.93, 0.95, 1.0)
const PANEL := Color(0.055, 0.06, 0.1, 0.94)
const EDGE := Color(0.36, 0.32, 0.27)
const BONUS_ORDER := ["multi", "laser", "shield", "wide", "fire", "slow"]
const BONUS := {
	"wide": {"name": "Wide", "land": "earth", "secs": 9.0},
	"laser": {"name": "Laser", "land": "fire", "secs": 6.0},
	"multi": {"name": "x3 Balls", "land": "light", "secs": 0.0},
	"shield": {"name": "Shield", "land": "water", "secs": 8.0},
	"fire": {"name": "Fireball", "land": "fire", "secs": 6.0},
	"slow": {"name": "Slow", "land": "ice", "secs": 6.0},
}

var state: State = State.KINGDOMS
# The map now, where this run began, and the maps cleared before it (the
# server's count: the next map to clear is `furthest`).
var map_index: int = 0
var start_index: int = 0
var furthest: int = 0
var selected: int = 0
var cleared: int = 0
var pays: Dictionary = {}
var lives: int = LIVES
var score: int = 0
var combo: int = 0
var best_combo: int = 0
var target_x: float = 640.0
var paddle_x: float = 640.0
var paddle_w: float = PADDLE_W
var stunned: float = 0.0
var tugged: float = 0.0         # hooked by the Harpooner: slowed, pulled to tug_x
var tug_x: float = 640.0
var aim: float = -PI / 2.0
var t: float = 0.0
var bricks: Array = []
var cells: Dictionary = {}       # Vector2i -> brick
var footprint: Dictionary = {}   # Vector2i -> true: where the map had bricks
var breakable: int = 0
var broken: int = 0
var balls: Array = []
var bolts: Array = []
var caps: Array = []
var active: Dictionary = {}
var parts: Array = []
var words: Array = []
var rings: Array = []
# The map's boss (crownfallboss.gd), or null; it walks `hall`, the R cells.
var boss = null
var hall := Rect2()
var rows_count: int = 0
# THIS MAP'S GRID (the owner: "we can even make the map bigger in some"): a
# map Maps.COLS wide has bricks CW x CH; a big one, Maps.BIG_COLS wide, has
# smaller ones, so the same arena holds more - every brick drawn at its own
# size (_draw_brick scales the standard brick to it).
var cols: int = Maps.COLS
var cw: float = CW
var ch: float = CH
var gap: float = ROW_GAP
var _jolt := Vector2.ZERO
# What the new bricks and the mixing leave going: lava falling down a column,
# lightning and shards drawn a moment, the eclipse's dark, the drifters, the
# prisms, and the keys still to break.
var drips: Array = []
var zaps: Array = []
var movers: Array = []
var gusts: Array = []          # {"y0", "y1", "way"} in px, this map's gusts
var tide_mark: int = -1        # the row this map's tide reaches up to; -1 none
var tide_t: float = 0.0        # how far into its cycle the tide is
var gone_at: Dictionary = {}   # Vector2i -> when the cell's brick broke
var placed: Dictionary = {}    # Vector2i -> the kind the map put there
var buoys: Array = []
var bubbles: Array = []        # {"p", "last"}: rising, to break what they meet
var prisms: Array = []
var keys_left: int = 0
var rails: Array = []          # the lanes' iron rails (in bricks too, off the grid)
var pulling: bool = false
var _eclipse: float = 0.0
var _reacting: int = 0
var _react_said: float = -1.0
var _new_balls: Array = []
var running_by_clock: bool = true
var aim_sways: bool = true
# What the waiting ball says (the screen sets it for a phone).
var launch_hint: String = "Click or Space to launch"
# The kingdom map's last line: how to go in, the picked map's name for %s
# (the owner: "make keyboard/controller navigation completely
# self-explanatory"). The screen sets it for a phone.
var map_hint: String = "Enter / Space: enter %s   ·   Esc: leave"
var rng := RandomNumberGenerator.new()

var _combo_t: float = 0.0
var _blight_t: float = BLIGHT_EVERY
var _laser_t: float = 0.0
var _muzzle: float = 0.0
var _shake: float = 0.0
var _shield_flash: float = 0.0
var _healed: float = 0.0
var _cleared_t: float = 0.0
var _next_bonus: int = 0
var _banner_t: float = 0.0
var _popped: Array = []
var _font: Font
var _bold: FontVariation


func _ready() -> void:
	_font = ThemeDB.fallback_font
	_bold = FontVariation.new()
	_bold.base_font = _font
	_bold.variation_embolden = 0.9
	rng.randomize()


func _process(delta: float) -> void:
	if running_by_clock:
		step(minf(delta, 0.05))


# ---------------------------------------------------------------- the run --

func show_kingdoms(furthest_cleared: int) -> void:
	"""The kingdom map, the next map to clear picked."""
	state = State.KINGDOMS
	furthest = clampi(furthest_cleared, 0, Maps.made_count())
	selected = mini(furthest, Maps.made_count() - 1)
	_clear_map()
	queue_redraw()


func can_start_at(index: int) -> bool:
	"""A map may be started from once every map before it is cleared."""
	return index >= 0 and index < Maps.made_count() and index <= furthest


func begin(index: int) -> void:
	"""A run from map `index`."""
	start_index = clampi(index, 0, Maps.made_count() - 1)
	lives = LIVES
	score = 0
	cleared = 0
	best_combo = 0
	_load(start_index)


func gold_now() -> int:
	"""What this run's cleared maps pay, by the server's table."""
	var out: int = 0
	var each: Array = pays.get("maps", []) if pays.get("maps") is Array else []
	for i in cleared:
		var at: int = start_index + i
		if at < each.size():
			out += int(each[at])
	return out


func playing() -> bool:
	return state in [State.AIM, State.PLAY, State.CLEARED]


func launch() -> void:
	if state == State.AIM and stunned <= 0.0:
		state = State.PLAY
		for b in balls:
			if b["v"] == Vector2.ZERO:
				b["v"] = Vector2.from_angle(aim) * SPEED


func _load(index: int) -> void:
	_clear_map()
	map_index = index
	var data: Dictionary = Maps.MAPS[index]
	var heart := Rect2()
	var heart_cells: Array = []
	var portals: Array = []
	var drifting: Array = []
	var kites: Array = []
	var rows: Array = data["rows"]
	cols = str(rows[0]).length() if not rows.is_empty() else Maps.COLS
	cw = FIELD_W / cols
	ch = CH if cols <= Maps.COLS else floorf(cw * 0.5)
	gap = ROW_GAP if cols <= Maps.COLS else 1.0
	for row in rows.size():
		var line: String = rows[row]
		for col in line.length():
			var letter: String = line[col]
			if letter == ".":
				continue
			var r := _cell(col, row)
			if letter == "R":
				hall = r if hall.size == Vector2.ZERO else hall.merge(r)
				continue
			if letter == "<":
				drifting.append(Vector2i(col, row))
				continue
			if letter == "k":
				kites.append(Vector2i(col, row))
				continue
			footprint[Vector2i(col, row)] = true
			match letter:
				"H":
					heart = r if heart.size == Vector2.ZERO else heart.merge(r)
					heart_cells.append(Vector2i(col, row))
				"S":
					_add(col, row, "stone", "", 3)
				"I":
					_add(col, row, "iron", "", 0)
				"M":
					_add(col, row, "mirror", "light", 0)
				"T":
					_add(col, row, "tnt", "fire", 1)
				"?":
					_add(col, row, "bonus", "light", 1)
				"B":
					_add(col, row, "blight", "", 1)
				"C":
					_add(col, row, "crystal", "ice", 1)
				"U":
					_add(col, row, "bumper", "light", 0)
				"O":
					portals.append(_add(col, row, "portal", "dark", 0))
				"K":
					_add(col, row, "key", "light", 1)
				"L":
					_add(col, row, "lock", "", 0)
				"G":
					_add(col, row, "gold", "light", 2)
				"N":
					var rune := _add(col, row, "rune", "light", 1)
					rune["phase"] = fmod((col + row) * 0.37, RUNE_CYCLE)
				"Z":
					_add(col, row, "shell", "", 1)
				"X":
					var prism := _add(col, row, "prism", "light", 1)
					prism["phase"] = (col * 3 + row) * 0.29
					prisms.append(prism)
				"D":
					_add(col, row, "guard", "light", 2)
				"W":
					var whirl := _add(col, row, "whirl", "wind", 0)
					whirl["phase"] = (col + row) * 0.7
				"Y":
					_add(col, row, "mimic", "", 1)
				"u":
					buoys.append(_add(col, row, "buoy", "water", 1))
				"o":
					_add(col, row, "bubble", "water", 1)
				"Q":
					var clam := _add(col, row, "clam", "water", 1)
					clam["phase"] = fmod((col * 2 + row) * 0.61, CLAM_CYCLE)
				"p":
					_add(col, row, "plague", "", 2)
				"1", "2", "3", "4", "5", "6", "7":
					var mix := _add(col, row, "mix", MIX_LANDS[MIXED[letter]][0], 1)
					mix["mix"] = MIXED[letter]
				_:
					var land: String = LAND_OF.get(letter, "light")
					_add(col, row, "land", land, 2 if land == "earth" else 1)
	if heart.size != Vector2.ZERO:
		# THE CORE IS ONE BRICK over every H cell: each cell names it, so the
		# blight cannot grow into the core while it stands.
		var k := _brick(heart, "heart", "light", 6)
		k["cells"] = heart_cells
		bricks.append(k)
		for c in heart_cells:
			cells[c] = k
	# PORTALS GO IN PAIRS, in reading order; one left over is a wall.
	for i in range(0, portals.size() - 1, 2):
		portals[i]["to"] = portals[i + 1]
		portals[i + 1]["to"] = portals[i]
		portals[i]["pair"] = i >> 1
		portals[i + 1]["pair"] = i >> 1
	_make_drifters(drifting)
	_make_kites(kites, rows.size())
	for g in data.get("gusts", []):
		var y0: float = MAP_TOP + int(g[0]) * (ch + gap) - gap
		var y1: float = minf(MAP_TOP + (int(g[1]) + 1) * (ch + gap), PADDLE_Y - 90.0)
		gusts.append({"y0": y0, "y1": y1, "way": signf(float(g[2]))})
	tide_mark = int(data.get("tide", -1))
	tide_t = 0.0
	for k in bricks:
		if _breaks(k):
			breakable += 1
		if k.has("cell"):
			placed[k["cell"]] = k["kind"]
		for c in k.get("cells", []):
			placed[c] = k["kind"]
		if k["kind"] == "key":
			keys_left += 1
	rows_count = rows.size()
	_make_rails(index)
	if data.get("boss") is Dictionary and hall.size != Vector2.ZERO:
		boss = Boss.new()
		boss.setup(self, data["boss"], str(Maps.kingdom_of(index).get("land", "light")), hall, ARENA, PADDLE_Y, VIEW.y)
	_reset_ball()
	_banner_t = BANNER_SECONDS
	said.emit("%s - map %d of %d" % [data["name"], Maps.in_kingdom(index) + 1, Maps.MAPS_A_KINGDOM])
	queue_redraw()


func _clear_map() -> void:
	bricks.clear()
	cells.clear()
	footprint.clear()
	balls.clear()
	bolts.clear()
	caps.clear()
	parts.clear()
	words.clear()
	rings.clear()
	active.clear()
	drips.clear()
	zaps.clear()
	movers.clear()
	prisms.clear()
	rails.clear()
	gusts.clear()
	buoys.clear()
	bubbles.clear()
	gone_at.clear()
	placed.clear()
	tide_mark = -1
	tide_t = 0.0
	_new_balls.clear()
	keys_left = 0
	pulling = false
	_eclipse = 0.0
	_popped.clear()
	breakable = 0
	broken = 0
	combo = 0
	stunned = 0.0
	tugged = 0.0
	hall = Rect2()
	rows_count = 0
	if boss != null:
		boss.clear()
	boss = null
	_healed = 0.0
	_blight_t = BLIGHT_EVERY


func _cell(col: int, row: int) -> Rect2:
	return Rect2(FIELD_X + col * cw + 1.0, MAP_TOP + row * (ch + gap), cw - 2.0, ch)


func cell_at(at: Vector2) -> Vector2i:
	"""The grid cell a point is in."""
	return Vector2i(int(floor((at.x - FIELD_X) / cw)), int(floor((at.y - MAP_TOP) / (ch + gap))))


func _bricks_near(at: Vector2) -> Array:
	"""THE BRICKS A BALL AT `at` COULD TOUCH: those in its cell and the eight
	round it (every brick names its cells in `cells`, the core all four) -
	never the whole map, which at 32 x 18 is hundreds."""
	var mid: Vector2i = cell_at(at)
	var out: Array = []
	for r in range(mid.y - 1, mid.y + 2):
		for c in range(mid.x - 1, mid.x + 2):
			var k: Variant = cells.get(Vector2i(c, r))
			if k != null and not out.has(k):
				out.append(k)
	for k in movers:
		if k["hp"] > 0 and (k["rect"] as Rect2).grow(BALL_R + 4.0).has_point(at):
			out.append(k)
	for k in rails:
		if (k["rect"] as Rect2).grow(BALL_R + 4.0).has_point(at):
			out.append(k)
	return out


func field_bottom() -> float:
	"""The foot of the map's rows."""
	return MAP_TOP + maxi(rows_count, 1) * (ch + gap)


func _add(col: int, row: int, kind: String, land: String, hp: int) -> Dictionary:
	var k := _brick(_cell(col, row), kind, land, hp)
	k["cell"] = Vector2i(col, row)
	bricks.append(k)
	cells[Vector2i(col, row)] = k
	return k


func _brick(r: Rect2, kind: String, land: String, hp: int) -> Dictionary:
	return {"rect": r, "kind": kind, "land": land, "hp": hp, "most": hp, "flash": 0.0, "burn": -1.0}


func _breaks(k: Dictionary) -> bool:
	return not UNBREAKABLE.has(k["kind"])


func _make_rails(index: int) -> void:
	"""THE LANES' RAILS: iron down each side of the field, from the arena's
	top to the foot of the rows, broken by two gates GATE_H tall - a third of
	the way down and two thirds, shifted a row or two map by map."""
	var pitch: float = ch + gap
	var rows_in: int = maxi(rows_count, 4)
	var apart: int = ceili(GATE_H / pitch) + 3
	var first: int = clampi(roundi(rows_in * 0.3) + index % 2, 1, maxi(1, rows_in - apart))
	var second: int = clampi(roundi(rows_in * 0.65) - index % 3, first + apart, maxi(first + apart, rows_in))
	var foot: float = field_bottom()
	var spans: Array = []
	for g in [first, second]:
		var top: float = MAP_TOP + g * pitch - gap
		spans.append(Vector2(top, top + GATE_H))
	spans.append(Vector2(foot, foot))
	for x in [FIELD_X - RAIL_W, FIELD_X + FIELD_W]:
		var y: float = ARENA.position.y
		for span in spans:
			if span.x > y + 4.0:
				var k := _brick(Rect2(x, y, RAIL_W, minf(span.x, foot) - y), "iron", "", 0)
				k["rail"] = true
				bricks.append(k)
				rails.append(k)
			y = maxf(y, span.y)
			if y >= foot:
				break


func gates() -> Array:
	"""The gates in the left rail, as (top, bottom) - the pictures' and the
	suite's."""
	var out: Array = []
	var left: Array = rails.filter(func(k: Dictionary) -> bool: return (k["rect"] as Rect2).position.x < FIELD_X)
	for i in range(left.size() - 1):
		out.append(Vector2((left[i]["rect"] as Rect2).end.y, (left[i + 1]["rect"] as Rect2).position.y))
	return out


func _guarded(k: Dictionary) -> bool:
	"""Whether a Guard touching `k` stands (a Guard is never guarded)."""
	if k["kind"] == "guard":
		return false
	var own: Array = k.get("cells", [k["cell"]] if k.has("cell") else [])
	for c in own:
		for d in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(1, 0),
				Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]:
			var o: Variant = cells.get(c + d)
			if o != null and o["kind"] == "guard" and o["hp"] > 0:
				return true
	return false


func _make_kites(spots: Array, rows_in: int) -> void:
	"""KITES (k): wind bricks bobbing up and down into the empty cells above
	and below them, KITE_REACH at most, each on its own beat. Off the grid,
	like drifters: the ball finds them in `movers`."""
	for c in spots:
		var up: int = 0
		while up < KITE_REACH and c.y - up - 1 >= 0 and not cells.has(Vector2i(c.x, c.y - up - 1)) \
				and not spots.has(Vector2i(c.x, c.y - up - 1)):
			up += 1
		var down: int = 0
		while down < KITE_REACH and c.y + down + 1 < rows_in + KITE_REACH and not cells.has(Vector2i(c.x, c.y + down + 1)) \
				and not spots.has(Vector2i(c.x, c.y + down + 1)):
			down += 1
		var k := _brick(_cell(c.x, c.y), "land", "wind", 1)
		k["kite"] = true
		k["home"] = (k["rect"] as Rect2).position.y
		k["lo"] = -up * (ch + gap)
		k["hi"] = down * (ch + gap)
		k["phase"] = (c.x * 0.9 + c.y * 0.4)
		bricks.append(k)
		movers.append(k)


func _gusts(dt: float) -> void:
	"""A ball in a gust's band is pushed its way, its speed kept."""
	if gusts.is_empty():
		return
	for b in balls:
		var v: Vector2 = b["v"]
		if v == Vector2.ZERO:
			continue
		for g in gusts:
			if (b["p"] as Vector2).y >= float(g["y0"]) and (b["p"] as Vector2).y <= float(g["y1"]):
				var speed: float = v.length()
				v.x += float(g["way"]) * GUST_PUSH * dt
				v = steady(v.normalized() * speed)
		b["v"] = v


func fling(b: Dictionary, at: Vector2) -> void:
	"""A whirl's or a whirlwind's throw: the ball off from `at` in a direction
	of its own (never flat), at least full speed."""
	var speed: float = maxf((b["v"] as Vector2).length(), SPEED)
	b["v"] = steady(Vector2.from_angle(rng.randf() * TAU) * speed)
	_burst(at, COLOURS["wind"], 12, 240.0, 0.0)


func _make_drifters(spots: Array) -> void:
	"""DRIFTERS (`<`): runs of light bricks along a row that slide back and
	forth into the empty cells beside them, at most DRIFT_REACH each way. Not
	on the grid (`cells`): the ball finds them in `movers`."""
	var runs: Array = []
	spots.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	for c in spots:
		if not runs.is_empty() and (runs[-1] as Array)[-1] == c - Vector2i(1, 0):
			(runs[-1] as Array).append(c)
		else:
			runs.append([c])
	for one in runs:
		var first: Vector2i = one[0]
		var last: Vector2i = one[-1]
		var left: int = 0
		while left < DRIFT_REACH and first.x - left - 1 >= 0 and not cells.has(Vector2i(first.x - left - 1, first.y)):
			left += 1
		var right: int = 0
		while right < DRIFT_REACH and last.x + right + 1 < cols and not cells.has(Vector2i(last.x + right + 1, last.y)):
			right += 1
		var phase: float = rng.randf() * TAU
		for c in one:
			var k := _brick(_cell(c.x, c.y), "land", "light", 1)
			k["home"] = (k["rect"] as Rect2).position.x
			k["lo"] = -left * cw
			k["hi"] = right * cw
			k["phase"] = phase
			bricks.append(k)
			movers.append(k)


func _reset_ball() -> void:
	balls.clear()
	balls.append(_ball(Vector2(paddle_x, PADDLE_Y - BALL_R - 8.0), Vector2.ZERO))
	state = State.AIM


func _ball(p: Vector2, v: Vector2) -> Dictionary:
	return {"p": p, "v": v, "trail": PackedVector2Array()}


func step(dt: float) -> void:
	t += dt
	_combo_t -= dt
	if _combo_t <= 0.0:
		combo = 0
	_shake = maxf(0.0, _shake - dt * 2.5)
	_muzzle = maxf(0.0, _muzzle - dt * 6.0)
	_shield_flash = maxf(0.0, _shield_flash - dt * 3.0)
	stunned = maxf(0.0, stunned - dt)
	tugged = maxf(0.0, tugged - dt)
	_banner_t = maxf(0.0, _banner_t - dt)
	_effects(dt)
	if state == State.KINGDOMS or state == State.OVER:
		queue_redraw()
		return
	for key in active.keys():
		active[key] -= dt
		if active[key] <= 0.0:
			active.erase(key)
	paddle_w = move_toward(paddle_w, PADDLE_WIDE if active.has("wide") else PADDLE_W, 400.0 * dt)
	var half: float = paddle_w / 2.0
	if stunned <= 0.0:
		var want: float = clampf(target_x, ARENA.position.x + half, ARENA.end.x - half)
		paddle_x = move_toward(paddle_x, want, PADDLE_SPEED * (0.3 if tugged > 0.0 else 1.0) * dt)
	if tugged > 0.0:
		paddle_x = move_toward(paddle_x, tug_x, 170.0 * dt)
	paddle_x = clampf(paddle_x, ARENA.position.x + half, ARENA.end.x - half)
	if state == State.CLEARED:
		_cleared_t -= dt
		_healed = minf(1.0, _healed + dt)
		_crumbles(dt)
		if _cleared_t <= 0.0:
			_next_map()
		queue_redraw()
		return
	if state == State.AIM:
		# THE AIM SWAYS while the ball waits (mouse, keys and a finger alike):
		# launch when it points where you want.
		if aim_sways:
			aim = deg_to_rad(-90.0 + AIM_SWAY * sin(t * AIM_SWAY_SPEED))
		for b in balls:
			b["p"] = Vector2(paddle_x, PADDLE_Y - BALL_R - 8.0)
	else:
		var speed: float = SPEED * (SLOW_SHARE if active.has("slow") else 1.0)
		_pull(dt)
		_gusts(dt)
		for b in balls:
			if b["v"] != Vector2.ZERO:
				b["v"] = (b["v"] as Vector2).normalized() * move_toward((b["v"] as Vector2).length(), speed, 600.0 * dt)
			b["portal_t"] = maxf(0.0, float(b.get("portal_t", 0.0)) - dt)
			b["boss_t"] = maxf(0.0, float(b.get("boss_t", 0.0)) - dt)
			_move(b, dt)
		if not _new_balls.is_empty():
			balls.append_array(_new_balls)
			_new_balls.clear()
		var kept: Array = []
		for b in balls:
			if b["p"].y > VIEW.y + 20.0:
				_burst(Vector2(b["p"].x, ARENA.end.y - 6.0), Color(1.0, 0.35, 0.3), 16, 180.0)
			else:
				kept.append(b)
		balls = kept
		if balls.is_empty():
			_lose_life()
	_lasers(dt)
	_boss_step(dt)
	_bricks_move(dt)
	_blight(dt)
	_tide(dt)
	_burns(dt)
	_capsules(dt)
	if state == State.PLAY or state == State.AIM:
		_check_cleared()
	queue_redraw()


func set_aim(angle: float) -> void:
	"""Where the waiting ball will go, held still (pictures and the suite):
	straight up, give or take 60 degrees."""
	aim_sways = false
	aim = clampf(angle, deg_to_rad(-150.0), deg_to_rad(-30.0))


static func steady(v: Vector2) -> Vector2:
	"""A ball never runs flat along a row: at least STEEPEST_FLAT of its
	speed goes up or down, so it always comes back to the paddle."""
	var speed: float = v.length()
	if speed <= 0.0:
		return v
	var d: Vector2 = v / speed
	if absf(d.y) < STEEPEST_FLAT:
		var x: float = sqrt(1.0 - STEEPEST_FLAT * STEEPEST_FLAT)
		d = Vector2(x if d.x >= 0.0 else -x, STEEPEST_FLAT if d.y >= 0.0 else -STEEPEST_FLAT)
	return d * speed


func _lose_life() -> void:
	lives -= 1
	combo = 0
	active.clear()
	bolts.clear()
	life_lost.emit()
	if lives <= 0:
		state = State.OVER
		run_over.emit()
		return
	_say(Vector2(640, 420), "A LIFE LOST", Color(1.0, 0.45, 0.4), 30, 1.2)
	_reset_ball()


func _check_cleared() -> void:
	var done: bool
	if boss != null:
		done = not boss.alive()
	else:
		done = broken >= breakable and breakable > 0
	if not done:
		return
	state = State.CLEARED
	_cleared_t = CLEARED_SECONDS
	cleared += 1
	balls.clear()
	caps.clear()
	var pay: int = 0
	var each: Array = pays.get("maps", []) if pays.get("maps") is Array else []
	if map_index < each.size():
		pay = int(each[map_index])
	var map_name: String = str(Maps.MAPS[map_index]["name"])
	_say(Vector2(640, 380), "%s - CLEARED" % map_name.to_upper(), GOLD, 34, CLEARED_SECONDS)
	if pay > 0:
		_say(Vector2(640, 424), "+%d gold" % pay, GOLD, 24, CLEARED_SECONDS)
	_say(Vector2(640, 462), "The land heals.", Color(0.6, 0.95, 0.55), 20, CLEARED_SECONDS)
	map_cleared.emit(map_index)


func _next_map() -> void:
	var nxt: int = map_index + 1
	furthest = maxi(furthest, nxt)
	if nxt >= Maps.made_count():
		state = State.OVER
		run_over.emit()
		return
	_load(nxt)


# ---------------------------------------------------------------- the ball --

func _move(b: Dictionary, dt: float) -> void:
	var steps: int = 6
	for i in steps:
		var prev: Vector2 = b["p"]
		var p: Vector2 = prev + b["v"] * dt / steps
		if p.x - BALL_R < ARENA.position.x or p.x + BALL_R > ARENA.end.x:
			b["v"].x = -b["v"].x
			p.x = clampf(p.x, ARENA.position.x + BALL_R, ARENA.end.x - BALL_R)
		if p.y - BALL_R < ARENA.position.y:
			b["v"].y = absf(b["v"].y)
			p.y = ARENA.position.y + BALL_R
		if b["v"].y > 0.0 and p.y + BALL_R >= PADDLE_Y - 7.0 and p.y < PADDLE_Y + 8.0 \
				and absf(p.x - paddle_x) <= paddle_w / 2.0 + BALL_R:
			var off: float = clampf((p.x - paddle_x) / (paddle_w / 2.0), -1.0, 1.0)
			b["v"] = Vector2.from_angle(deg_to_rad(-90.0 + off * 58.0)) * b["v"].length()
			p.y = PADDLE_Y - 7.0 - BALL_R
			combo = 0
			_burst(p, GOLD, 8, 140.0)
		if active.has("shield") and b["v"].y > 0.0 and p.y + BALL_R >= SHIELD_Y:
			b["v"].y = -absf(b["v"].y)
			p.y = SHIELD_Y - BALL_R
			_shield_flash = 1.0
			_burst(p, COLOURS["water"], 12, 200.0, 1.4)
		if boss != null and boss.alive():
			if boss.hittable() and boss.body_rect().grow(BALL_R).has_point(p):
				# off the boss the way it came - up off its head, down off its
				# feet - and one hit a touch: a ball pressed into it, or caught
				# between it and the hall's roof, counts once a BOSS_HIT_GAP
				b["v"].y = -absf(b["v"].y) if p.y < boss.p.y else absf(b["v"].y)
				p.y = prev.y
				if float(b.get("boss_t", 0.0)) <= 0.0:
					b["boss_t"] = BOSS_HIT_GAP
					_hit_boss(BALL_HIT)
			var killed: int = boss.ball_touch(p, BALL_R)
			if killed > 0:
				score += 300 * killed
			var ward: Vector2 = boss.ward_touch(p, BALL_R)
			if ward != Vector2.INF:
				b["v"] = (p - ward).normalized() * (b["v"] as Vector2).length()
				p = prev
		for k in _bricks_near(p):
			var r: Rect2 = k["rect"]
			if (k["hp"] > 0 or not _breaks(k)) and r.grow(BALL_R).has_point(p):
				if k["kind"] == "portal" and k.has("to"):
					# A PORTAL: in one, out of its pair, the way it was going.
					if float(b.get("portal_t", 0.0)) > 0.0:
						continue
					var out: Dictionary = k["to"]
					var d: Vector2 = (b["v"] as Vector2).normalized()
					p = (out["rect"] as Rect2).get_center() + d * (ch * 0.5 + BALL_R + 4.0)
					b["portal_t"] = PORTAL_WAIT
					k["flash"] = 1.0
					out["flash"] = 1.0
					_burst((k["rect"] as Rect2).get_center(), PORTAL_HUES[int(k.get("pair", 0)) % PORTAL_HUES.size()], 10, 160.0, 0.0)
					_burst(p, PORTAL_HUES[int(k.get("pair", 0)) % PORTAL_HUES.size()], 10, 160.0, 0.0)
					break
				if k["kind"] == "whirl":
					# A WHIRL throws the ball off any way it likes
					p = prev
					fling(b, r.get_center())
					k["flash"] = 1.0
					score += 10
					break
				if k["kind"] == "bumper":
					# A BUMPER kicks the ball straight off its middle, faster.
					var away: Vector2 = (p - r.get_center()).normalized()
					if away == Vector2.ZERO:
						away = Vector2.UP
					b["v"] = away * maxf((b["v"] as Vector2).length(), SPEED) * BUMPER_KICK
					p = prev
					k["flash"] = 1.0
					score += 10
					_burst(r.get_center(), Color(1.0, 0.6, 0.85), 8, 200.0, 0.0)
					break
				var through: bool = active.has("fire") and _breaks(k) and not _shut(k)
				if not through:
					var was_out_x: bool = prev.x < r.position.x - BALL_R + 0.5 or prev.x > r.end.x + BALL_R - 0.5
					if was_out_x:
						b["v"].x = -b["v"].x
						p.x = prev.x
					else:
						b["v"].y = -b["v"].y
						p.y = prev.y
				if k["kind"] == "mirror":
					# A MIRROR BENDS THE BALL it throws back: a fixed turn,
					# one way on even cells and the other on odd, so a mirror
					# can be learned and aimed off.
					var c: Vector2i = k["cell"]
					var turn: float = MIRROR_BEND if (c.x + c.y) % 2 == 0 else -MIRROR_BEND
					b["v"] = (b["v"] as Vector2).rotated(deg_to_rad(turn))
					k["flash"] = 1.0
					_burst(p, COLOURS["light"], 6, 200.0, 0.0)
				else:
					_damage(k, 99 if through else 1, b)
				break
		b["v"] = steady(b["v"])
		b["p"] = p
		var trail: PackedVector2Array = b["trail"]
		trail.append(p)
		if trail.size() > 48:
			trail.remove_at(0)
		b["trail"] = trail


func _damage(k: Dictionary, n: int, b) -> void:
	var mid: Vector2 = (k["rect"] as Rect2).get_center()
	k["flash"] = 1.0
	if not _breaks(k) or _shut(k):
		# iron, a mirror, a lock - or a rune while it is dark, a clam while it
		# is shut: nothing
		_burst(mid, Color(0.85, 0.88, 0.95), 6, 160.0)
		return
	if k["hp"] <= 0:
		return
	if _guarded(k):
		# A GUARD STANDS BESIDE IT: the blow glances off its shield
		k["warded"] = 1.0
		_burst(mid, GUARD_GLOW, 5, 120.0, 0.0)
		return
	if bool(k.get("frozen", false)):
		n = 99
	if k["kind"] == "shell" and k["hp"] - n <= 0:
		# A SHELL HARDENS: the blow that would break it turns it to stone.
		k["kind"] = "stone"
		k["hp"] = 2
		k["most"] = 3
		_burst(mid, Color(0.93, 0.72, 0.62), 10, 140.0)
		_say(mid + Vector2(0, -12), "HARDENED", Color(0.8, 0.78, 0.74), 16, 0.7)
		return
	k["hp"] -= n
	var c: Color = _colour_of(k)
	if k["hp"] > 0:
		_burst(mid, c, 7, 150.0)
		return
	k["hp"] = 0
	if k.has("cell"):
		cells.erase(k["cell"])
		gone_at[k["cell"]] = t
	for spot in k.get("cells", []):
		cells.erase(spot)
		gone_at[spot] = t
	broken += 1
	combo += 1
	_combo_t = 1.7
	best_combo = maxi(best_combo, combo)
	score += int(round(int(SCORE.get(k["kind"], 50)) * _multiplier()))
	for mark in [10, 20, 30]:
		if combo == mark and not _popped.has(mark):
			_popped.append(mark)
			_say(Vector2(640, 430), "COMBO x%d!" % combo, COLOURS["fire"], 38, 1.3)
	_shake = minf(1.0, _shake + 0.15)
	if bool(k.get("frozen", false)):
		_shatter_round(k)
	if k.has("cell"):
		_tell_mimics(k)
	match k["kind"]:
		"tnt":
			_explode(mid)
		"bonus":
			_burst(mid, GOLD, 26, 260.0, 0.3)
			_drop(mid)
		"heart":
			_burst(mid, COLOURS["light"], 70, 420.0, 0.2)
			_burst(mid, BLIGHT, 40, 300.0, -0.2)
			rings.append({"p": mid, "age": 0.0, "most": 0.7, "c": COLOURS["light"], "r": CORE_BLAST + 40.0})
			_say(mid + Vector2(0, -30), "CORE SHATTERED!", COLOURS["light"], 32, 1.6)
			_shake = 1.0
			_drop(mid)
			for o in bricks:
				if o["hp"] > 0 and _breaks(o) and (o["rect"] as Rect2).get_center().distance_to(mid) < CORE_BLAST:
					_damage(o, 1, null)
		"stone":
			_burst(mid, Color(0.6, 0.58, 0.55), 18, 220.0)
		"blight", "plague":
			_burst(mid, BLIGHT, 16, 200.0, -0.3)
		"crystal":
			# A CRYSTAL SPLITS THE BALL that breaks it.
			_burst(mid, Color(0.8, 0.97, 1.0), 20, 260.0, 0.2)
			if b is Dictionary and balls.size() + _new_balls.size() < MOST_BALLS:
				var twin := _ball(b["p"], (b["v"] as Vector2).rotated(deg_to_rad(CRYSTAL_SPREAD if rng.randf() < 0.5 else -CRYSTAL_SPREAD)))
				twin["el"] = b.get("el", "")
				_new_balls.append(twin)
		"key":
			_burst(mid, GOLD, 20, 220.0, 0.2)
			keys_left -= 1
			if keys_left <= 0:
				_open_locks()
			else:
				_say(mid + Vector2(0, -14), "%d KEY%s LEFT" % [keys_left, "" if keys_left == 1 else "S"], GOLD, 16, 0.9)
		"gold":
			_burst(mid, GOLD, 30, 280.0, 1.2)
			_burst(mid, Color(1.0, 0.95, 0.6), 12, 200.0, -0.2)
			_say(mid + Vector2(0, -12), "+%d" % int(SCORE["gold"]), GOLD, 18, 0.8)
		"mix":
			_burst(mid, c, 14, 220.0)
			if b is Dictionary or _reacting > 0:
				_react(str(k["mix"]), k, mid)
		"mimic":
			_burst(mid, Color(0.7, 0.68, 0.8), 12, 180.0)
		"clam":
			# A CLAM BROKEN OPEN: its pearl always drops a bonus
			_burst(mid, Color(0.95, 0.95, 1.0), 22, 240.0, 0.3)
			_say(mid + Vector2(0, -14), "PEARL!", Color(0.92, 0.94, 1.0), 16, 0.8)
			_drop(mid)
		"bubble":
			# A BUBBLE BROKEN: one rises up the column
			_burst(mid, COLOURS["water"].lightened(0.3), 12, 160.0, -0.4)
			bubbles.append({"p": mid, "last": k.get("cell", cell_at(mid))})
		"buoy":
			_burst(mid, Color(0.95, 0.35, 0.3), 12, 180.0, 1.0)
			_burst(mid, COLOURS["water"], 8, 140.0, 1.2)
		_:
			# a land brick or a prism (breaking as the land it shows)
			_land_breaks(k, mid, b)
			if b is Dictionary:
				_charge(b, str(k["land"]), k, mid)
	if broken % BONUS_EVERY == 0 and caps.size() < CAPS_MOST:
		_drop(mid)


func _land_breaks(k: Dictionary, mid: Vector2, b) -> void:
	var c: Color = COLOURS.get(k["land"], Color.WHITE)
	match k["land"]:
		"fire":
			_burst(mid, c, 18, 240.0)
			var step: int = int(k.get("spark", 0))
			if step < FIRE_SPREAD:
				for o in _bricks_near(mid):
					if o["hp"] > 0 and o["kind"] == "land" and o["land"] == "fire" and o["burn"] < 0.0 \
							and (o["rect"] as Rect2).grow(6.0).intersects(k["rect"]):
						o["burn"] = 0.22
						o["spark"] = step + 1
		"ice":
			_burst(mid, c, 18, 280.0, 0.4)
		"water":
			_burst(mid, c, 18, 220.0, 1.6)
		"wind":
			_burst(mid, c, 14, 360.0, 0.0)
			if b is Dictionary:
				b["v"] = (b["v"] as Vector2).rotated(deg_to_rad(16.0 if rng.randf() < 0.5 else -16.0))
		"dark":
			_burst(mid, c, 16, 160.0, -0.4)
		_:
			_burst(mid, c, 16, 220.0, 0.3)


func _explode(at: Vector2) -> void:
	rings.append({"p": at, "age": 0.0, "most": 0.45, "c": COLOURS["fire"], "r": 80.0})
	_burst(at, COLOURS["fire"], 40, 380.0)
	_shake = 1.0
	for o in bricks:
		if o["hp"] > 0 and _breaks(o) and (o["rect"] as Rect2).get_center().distance_to(at) < 78.0:
			if o["kind"] == "tnt":
				o["burn"] = 0.12
			else:
				_damage(o, 2, null)


func _burns(dt: float) -> void:
	for k in bricks:
		if k["burn"] >= 0.0 and k["hp"] > 0:
			k["burn"] -= dt
			if rng.randf() < 0.7:
				var r: Rect2 = k["rect"]
				parts.append({"p": Vector2(rng.randf_range(r.position.x, r.end.x), r.position.y),
					"v": Vector2(rng.randf_range(-20, 20), rng.randf_range(-90, -40)), "life": 0.45, "most": 0.45,
					"c": COLOURS["fire"], "s": 2.2, "g": -0.3})
			if k["burn"] < 0.0:
				_damage(k, 99, null)


func _blight(dt: float) -> void:
	"""THE BLIGHT GROWS BACK: every BLIGHT_EVERY, each blight brick spreads
	into one empty cell beside it that the map once held, or corrupts a land
	brick beside it into plague-stone - at most BLIGHT_MOST at a time."""
	_blight_t -= dt
	if _blight_t > 0.0:
		return
	_blight_t = BLIGHT_EVERY
	var grown: int = 0
	var sources: Array = []
	for k in bricks:
		if k["kind"] == "blight" and k["hp"] > 0:
			sources.append(k)
	for k in sources:
		if grown >= BLIGHT_MOST:
			break
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var c: Vector2i = k["cell"] + d
			if footprint.has(c) and not cells.has(c) and not _ball_near(_cell(c.x, c.y)):
				var nk := _add(c.x, c.y, "blight", "", 1)
				nk["flash"] = 1.0
				breakable += 1
				_burst(_cell(c.x, c.y).get_center(), BLIGHT, 8, 90.0, -0.2)
				grown += 1
				break
			var near: Variant = cells.get(c)
			if near != null and near["kind"] == "land" and near["hp"] > 0 and rng.randf() < CORRUPT_CHANCE:
				# THE PLAGUE CORRUPTS: a land brick beside the blight turns to
				# plague-stone, two hits
				near["kind"] = "plague"
				near["hp"] = 2
				near["most"] = 2
				near["flash"] = 1.0
				_burst((near["rect"] as Rect2).get_center(), BLIGHT, 8, 90.0, -0.2)
				grown += 1
				break
	if grown > 0:
		_say(Vector2(640, 470), "The blight spreads", BLIGHT.lightened(0.3), 18, 1.0)
	# broken bricks stay in the list for the drawing's sake; the grid forgets them
	bricks = bricks.filter(func(k): return k["hp"] > 0 or not _breaks(k) or k["kind"] != "blight")


func _ball_near(r: Rect2) -> bool:
	for b in balls:
		if r.grow(BALL_R * 3.0).has_point(b["p"]):
			return true
	return false


# ---------------------------------------------------------------- the elements mixed --

func _rune_lit(k: Dictionary) -> bool:
	"""A RUNE is breakable only while lit: RUNE_LIT of every RUNE_CYCLE, each
	at its own moment."""
	return fmod(t + float(k.get("phase", 0.0)), RUNE_CYCLE) < RUNE_LIT


func clam_open(k: Dictionary) -> float:
	"""How open a clam is, 0 shut to 1: open CLAM_OPEN of every CLAM_CYCLE,
	easing a fifth of a second either side."""
	var u: float = fmod(t + float(k.get("phase", 0.0)), CLAM_CYCLE)
	if u >= CLAM_OPEN:
		return 0.0
	return clampf(minf(u, CLAM_OPEN - u) / 0.2, 0.0, 1.0)


func _shut(k: Dictionary) -> bool:
	"""Hard to every blow right now: a rune while it is dark, a clam while it
	is shut."""
	match k["kind"]:
		"rune":
			return not _rune_lit(k)
		"clam":
			return clam_open(k) <= 0.0
	return false


# ---------------------------------------------------------------- the tide --

func tide_level() -> float:
	"""How far up its mark the tide stands, 0 to 1."""
	if tide_mark < 0:
		return 0.0
	var u: float = tide_t - (TIDE_EVERY - 2.0 * TIDE_RISE - TIDE_HIGH)
	if u <= 0.0:
		return 0.0
	if u < TIDE_RISE:
		return smoothstep(0.0, 1.0, u / TIDE_RISE)
	if u < TIDE_RISE + TIDE_HIGH:
		return 1.0
	return 1.0 - smoothstep(0.0, 1.0, (u - TIDE_RISE - TIDE_HIGH) / TIDE_RISE)


func tide_line() -> float:
	"""The tide's mark in px: the top of its row."""
	return MAP_TOP + tide_mark * (ch + gap) - gap


func tide_y() -> float:
	"""Where the water stands now, in px."""
	return lerpf(field_bottom() + 6.0, tide_line(), tide_level())


func tide_now() -> void:
	"""The tide comes in at once (the Tide King's call), when it is out."""
	var low: float = TIDE_EVERY - 2.0 * TIDE_RISE - TIDE_HIGH
	if tide_mark >= 0 and tide_t < low - 0.05:
		tide_t = low - 0.05


func _tide(dt: float) -> void:
	"""The tide's cycle: it says when it comes in, and rebuilds as it stands."""
	if tide_mark < 0:
		return
	var low: float = TIDE_EVERY - 2.0 * TIDE_RISE - TIDE_HIGH
	var before: float = tide_t
	tide_t += dt
	if before < low and tide_t >= low:
		_say(Vector2(640, 470), "THE TIDE COMES IN", COLOURS["water"].lightened(0.35), 20, 1.4)
	if before < low + TIDE_RISE and tide_t >= low + TIDE_RISE:
		tide_rebuild()
	if tide_t >= TIDE_EVERY:
		tide_t -= TIDE_EVERY


func tide_rebuild() -> int:
	"""THE TIDE REBUILDS WHAT YOU LEFT: every empty cell under the mark that
	the map once held, broken more than TIDE_WAIT ago, comes back as a water
	brick - the oldest first, TIDE_MOST at most."""
	var spots: Array = []
	for c in footprint.keys():
		if c.y < tide_mark or cells.has(c) or TIDE_KEEP.has(str(placed.get(c, ""))):
			continue
		if t - float(gone_at.get(c, t)) < TIDE_WAIT:
			continue
		var r := _cell(c.x, c.y)
		if _ball_near(r) or (hall.size != Vector2.ZERO and hall.grow(2.0).intersects(r)):
			continue
		spots.append(c)
	spots.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return float(gone_at[a]) < float(gone_at[b]))
	var made: int = 0
	for c in spots.slice(0, TIDE_MOST):
		var k := _add(c.x, c.y, "land", "water", 1)
		k["tide"] = true
		k["flash"] = 1.0
		gone_at.erase(c)
		breakable += 1
		made += 1
		_burst(_cell(c.x, c.y).get_center(), COLOURS["water"].lightened(0.2), 8, 120.0, -0.3)
	if made > 0:
		_say(Vector2(640, 500), "THE TIDE REBUILDS %d" % made, COLOURS["water"].lightened(0.35), 18, 1.2)
	return made


func _waters(dt: float) -> void:
	"""Buoys float up into the holes above them; bubbles rise and burst."""
	for k in buoys:
		if k["hp"] <= 0:
			continue
		var home: Vector2i = k["cell"]
		if k.has("rise"):
			k["rise"] = float(k["rise"]) - dt
			var to: Rect2 = _cell(home.x, home.y)
			var r: Rect2 = to
			r.position.y += (ch + gap) * clampf(float(k["rise"]) / BUOY_RISE, 0.0, 1.0)
			k["rect"] = r
			if float(k["rise"]) <= 0.0:
				k.erase("rise")
				k["rect"] = to
			continue
		var up: Vector2i = home + Vector2i(0, -1)
		if footprint.has(up) and not cells.has(up) and not _ball_near(_cell(up.x, up.y)):
			cells.erase(home)
			gone_at[home] = t
			cells[up] = k
			k["cell"] = up
			k["rise"] = BUOY_RISE
			_burst(_cell(home.x, home.y).get_center(), COLOURS["water"].lightened(0.3), 5, 90.0, -0.5)
	for bu in bubbles:
		bu["p"].y -= BUBBLE_SPEED * dt
		var c: Vector2i = cell_at(bu["p"])
		if c != bu["last"]:
			bu["last"] = c
			var o: Variant = cells.get(c)
			if o != null and (o["hp"] > 0 or not _breaks(o)):
				_damage(o, 1, null)
				bu["dead"] = true
				_burst(bu["p"], COLOURS["water"].lightened(0.45), 10, 150.0, -0.2)
		if bu["p"].y < ARENA.position.y + 6.0:
			bu["dead"] = true
	bubbles = bubbles.filter(func(bu): return not bu.get("dead", false))


static func reaction_of(a: String, b: String) -> String:
	"""What two lands do when the ball mixes them: a named reaction, or a
	clash."""
	var pair: Array = [a, b]
	pair.sort()
	return str(REACTIONS.get("%s+%s" % [pair[0], pair[1]], "clash"))


func _charge(b: Dictionary, land: String, k: Dictionary, at: Vector2) -> void:
	"""THE BALL CARRIES WHAT IT BREAKS: a land brick broken while it carries
	another land sets the two off, and it carries the new one on."""
	var had: String = str(b.get("el", ""))
	if had != "" and had != land:
		_react(reaction_of(had, land), k, at)
	b["el"] = land


func _react(kind: String, k: Dictionary, at: Vector2) -> void:
	"""A REACTION round the brick `k` at `at` (its cell, even broken). A
	reaction that breaks a mixed brick sets that one off too, REACT_DEPTH
	deep at most."""
	if _reacting >= REACT_DEPTH:
		return
	_reacting += 1
	var lands: Array = MIX_LANDS.get(kind, ["light", "light"])
	var colour: Color = COLOURS[lands[0]].lerp(COLOURS[lands[1]], 0.5)
	score += 100
	if kind != "clash" and t - _react_said >= REACT_WORD_GAP:
		_react_said = t
		_say(at + Vector2(0, -16), str(REACTION_WORDS.get(kind, "!")), colour.lightened(0.2), 20, 0.7)
	var home: Vector2i = k["cell"] if k.has("cell") else cell_at(at)
	match kind:
		"steam":
			# fire and ice: a blast of steam round it
			rings.append({"p": at, "age": 0.0, "most": 0.4, "c": Color(0.95, 0.97, 1.0), "r": 70.0})
			_burst(at, Color(0.95, 0.97, 1.0), 30, 260.0, -0.6)
			for o in _bricks_in(home, 1, 1):
				_damage(o, 2, null)
		"firestorm":
			# fire and wind: the row burns, outward from it, FIRESTORM_REACH each way
			_burst(at, COLOURS["fire"], 24, 320.0, -0.2)
			for o in bricks:
				if o["hp"] > 0 and _breaks(o) and o.has("cell") and (o["cell"] as Vector2i).y == home.y and o["burn"] < 0.0 \
						and absi((o["cell"] as Vector2i).x - home.x) <= FIRESTORM_REACH:
					o["burn"] = 0.05 + absf((o["cell"] as Vector2i).x - home.x) * 0.04
		"glacier":
			# water and ice: everything round it freezes; a frozen brick breaks
			# at a touch, and its frozen neighbours shatter with it
			rings.append({"p": at, "age": 0.0, "most": 0.5, "c": COLOURS["ice"], "r": 90.0})
			for o in _bricks_in(home, 2, 1):
				o["frozen"] = true
				o["flash"] = 1.0
		"storm":
			# water and wind: lightning jumps to the bricks round it
			var near: Array = []
			for o in bricks:
				if o["hp"] > 0 and _breaks(o) and (o["rect"] as Rect2).get_center().distance_to(at) < STORM_REACH:
					near.append(o)
			near.shuffle()
			for o in near.slice(0, STORM_JUMPS):
				_zap(at, (o["rect"] as Rect2).get_center(), Color(0.75, 0.9, 1.0))
				_damage(o, 1, null)
		"magma":
			# earth and fire: lava drips down the column, through what is below
			drips.append({"p": at, "left": DRIP_DEPTH, "last": home})
		"blizzard":
			# ice and wind: shards up the column above it
			var hit: int = 0
			var top: Vector2 = at
			for row in range(home.y - 1, -1, -1):
				var o: Variant = cells.get(Vector2i(home.x, row))
				if o != null and o["hp"] > 0 and _breaks(o):
					_damage(o, 1, null)
					top = (o["rect"] as Rect2).get_center()
					hit += 1
					if hit >= SHARD_DEPTH:
						break
			_zap(at, top + Vector2(0, -10), COLOURS["ice"].lightened(0.3))
		"eclipse":
			# light and dark: the ECLIPSE_MOST bricks of the land most left nearest
			# it take a hit
			var count: Dictionary = {}
			for o in bricks:
				if o["hp"] > 0 and o["kind"] == "land":
					count[o["land"]] = int(count.get(o["land"], 0)) + 1
			var most: String = ""
			for land in count:
				if most == "" or int(count[land]) > int(count[most]):
					most = land
			_eclipse = 0.5
			var dimmed: Array = []
			for o in bricks:
				if o["hp"] > 0 and o["kind"] == "land" and o["land"] == most:
					dimmed.append(o)
			dimmed.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return (x["rect"] as Rect2).get_center().distance_to(at) < (y["rect"] as Rect2).get_center().distance_to(at))
			for o in dimmed.slice(0, ECLIPSE_MOST):
				_damage(o, 1, null)
		_:
			# any other two: a clash - a spark into a brick beside it
			_burst(at, Color(1.0, 0.95, 0.8), 14, 300.0, 0.0)
			var round_it: Array = _bricks_in(home, 1, 1)
			if not round_it.is_empty():
				_damage(round_it[rng.randi_range(0, round_it.size() - 1)], 1, null)
	_reacting -= 1


func _bricks_in(home: Vector2i, wide: int, tall: int) -> Array:
	"""The breakable bricks standing within `wide` cells across and `tall`
	down or up of `home`, on the grid."""
	var out: Array = []
	for row in range(home.y - tall, home.y + tall + 1):
		for col in range(home.x - wide, home.x + wide + 1):
			var o: Variant = cells.get(Vector2i(col, row))
			if o != null and o["hp"] > 0 and _breaks(o) and not out.has(o):
				out.append(o)
	return out


func _zap(from: Vector2, to: Vector2, c: Color) -> void:
	"""A bolt drawn a moment, jagged, from `from` to `to`."""
	var pts := PackedVector2Array([from])
	var steps: int = 5
	for i in range(1, steps):
		var at: Vector2 = from.lerp(to, float(i) / steps)
		pts.append(at + Vector2(rng.randf_range(-9, 9), rng.randf_range(-9, 9)))
	pts.append(to)
	zaps.append({"pts": pts, "age": 0.0, "c": c})


func _shatter_round(k: Dictionary) -> void:
	"""A frozen brick broken: its frozen neighbours shatter a moment later."""
	var home: Vector2i = k["cell"] if k.has("cell") else cell_at((k["rect"] as Rect2).get_center())
	_burst((k["rect"] as Rect2).get_center(), COLOURS["ice"].lightened(0.3), 10, 200.0, 0.6)
	for o in _bricks_in(home, 1, 1):
		if bool(o.get("frozen", false)) and not o.has("shatter"):
			o["shatter"] = SHATTER_STEP


func _tell_mimics(k: Dictionary) -> void:
	"""A MIMIC becomes what broke beside it: the brick's kind, land and full
	strength."""
	if not ["land", "stone", "tnt", "bonus", "gold", "crystal", "shell", "plague", "prism", "mix", "blight"].has(k["kind"]):
		return
	var home: Vector2i = k["cell"]
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var m: Variant = cells.get(home + d)
		if m != null and m["kind"] == "mimic" and m["hp"] > 0:
			m["kind"] = k["kind"]
			m["land"] = k["land"]
			m["hp"] = int(k["most"])
			m["most"] = int(k["most"])
			if k.has("mix"):
				m["mix"] = k["mix"]
			if k["kind"] == "prism":
				m["phase"] = k.get("phase", 0.0)
				prisms.append(m)
			m["flash"] = 1.0
			_burst((m["rect"] as Rect2).get_center(), Color(0.75, 0.7, 0.9), 10, 160.0, 0.0)


func _open_locks() -> void:
	"""Every key broken: every lock shatters (they never counted to clear)."""
	_say(Vector2(640, 400), "THE LOCKS OPEN!", GOLD, 28, 1.2)
	for o in bricks:
		if o["kind"] == "lock" and o["hp"] >= 0:
			o["kind"] = "opened"
			o["hp"] = 0
			if o.has("cell"):
				cells.erase(o["cell"])
			_burst((o["rect"] as Rect2).get_center(), GOLD, 14, 240.0, 0.4)


func _bricks_move(dt: float) -> void:
	"""What moves among the bricks each tick: drifters slide, prisms turn,
	lava falls, frozen bricks shatter, buoys float, bubbles rise, bolts and
	the eclipse fade."""
	_waters(dt)
	for k in movers:
		if k["hp"] > 0:
			# a Rect2 is a value: set a copy, then put it back
			var r: Rect2 = k["rect"]
			if k.has("kite"):
				var w: float = 0.5 + 0.5 * sin(t * KITE_SPEED + float(k["phase"]))
				r.position.y = float(k["home"]) + lerpf(float(k["lo"]), float(k["hi"]), w)
			else:
				var u: float = 0.5 + 0.5 * sin(t * DRIFT_SPEED + float(k["phase"]))
				r.position.x = float(k["home"]) + lerpf(float(k["lo"]), float(k["hi"]), u)
			k["rect"] = r
	for k in prisms:
		if k["hp"] > 0 and k["kind"] == "prism":
			k["land"] = ELEMENTS[int(floor((t + float(k["phase"])) / PRISM_EVERY)) % ELEMENTS.size()]
	for k in bricks:
		if k.has("shatter") and k["hp"] > 0:
			k["shatter"] -= dt
			if k["shatter"] <= 0.0:
				k.erase("shatter")
				_damage(k, 99, null)
		if k.has("warded"):
			k["warded"] -= dt * 2.5
			if k["warded"] <= 0.0:
				k.erase("warded")
	for d in drips:
		d["p"].y += DRIP_SPEED * dt
		var c: Vector2i = cell_at(d["p"])
		if c != d["last"]:
			d["last"] = c
			var o: Variant = cells.get(c)
			if o != null and o["hp"] > 0 and _breaks(o):
				_damage(o, 1, null)
				d["left"] -= 1
		if rng.randf() < 0.6:
			parts.append({"p": d["p"] + Vector2(rng.randf_range(-4, 4), 0), "v": Vector2(rng.randf_range(-20, 20), -40),
				"life": 0.4, "most": 0.4, "c": COLOURS["fire"], "s": 2.4, "g": 0.4})
		if d["left"] <= 0 or d["p"].y > field_bottom() + 20.0:
			d["dead"] = true
	drips = drips.filter(func(d): return not d.get("dead", false))
	for z in zaps:
		z["age"] += dt
	zaps = zaps.filter(func(z): return z["age"] < 0.3)
	_eclipse = maxf(0.0, _eclipse - dt)


func _pull(dt: float) -> void:
	"""THE LAST FEW BRICKS CALL THE BALL: PULL_BELOW or fewer standing that
	can be hurt now - a guarded brick waits for its Guard - and no boss, a
	rising ball turns toward the nearest."""
	var left: int = breakable - broken
	pulling = false
	if boss != null or left <= 0 or left > PULL_BELOW * 8:
		return
	var targets: Array = []
	for k in bricks:
		if k["hp"] > 0 and _breaks(k) and not _guarded(k):
			targets.append((k["rect"] as Rect2).get_center())
	pulling = not targets.is_empty() and targets.size() <= PULL_BELOW
	if not pulling:
		return
	for b in balls:
		var v: Vector2 = b["v"]
		if v.y >= 0.0 or targets.is_empty():
			continue
		var best: Vector2 = targets[0]
		for at in targets:
			if (at as Vector2).distance_to(b["p"]) < best.distance_to(b["p"]):
				best = at
		var want: float = v.angle_to(best - (b["p"] as Vector2))
		var turn: float = clampf(want, -deg_to_rad(PULL_TURN) * dt, deg_to_rad(PULL_TURN) * dt)
		b["v"] = v.rotated(turn)


# ---------------------------------------------------------------- bonuses --

func _drop(at: Vector2) -> void:
	var kind: String = BONUS_ORDER[_next_bonus % BONUS_ORDER.size()]
	_next_bonus += 1
	caps.append({"p": at, "kind": kind})


func _capsules(dt: float) -> void:
	for c in caps:
		c["p"].y += CAPSULE_FALL * dt
		if absf(c["p"].x - paddle_x) < paddle_w / 2.0 + 20.0 and absf(c["p"].y - PADDLE_Y) < 14.0:
			c["taken"] = true
			_take(c["kind"])
	caps = caps.filter(func(c): return not c.get("taken", false) and c["p"].y < VIEW.y + 30.0)


func _take(kind: String) -> void:
	var info: Dictionary = BONUS[kind]
	_say(Vector2(paddle_x, PADDLE_Y - 46.0), str(info["name"]).to_upper() + "!", COLOURS[info["land"]], 26, 1.1)
	_burst(Vector2(paddle_x, PADDLE_Y - 8.0), COLOURS[info["land"]], 24, 260.0)
	if kind == "multi":
		var more: Array = []
		for b in balls:
			for a in [-22.0, 22.0]:
				if balls.size() + more.size() < MOST_BALLS and b["v"] != Vector2.ZERO:
					more.append(_ball(b["p"], (b["v"] as Vector2).rotated(deg_to_rad(a))))
		balls.append_array(more)
	else:
		active[kind] = float(info["secs"])


func _lasers(dt: float) -> void:
	if active.has("laser") and state == State.PLAY:
		_laser_t -= dt
		if _laser_t <= 0.0:
			_laser_t = LASER_EVERY
			_muzzle = 1.0
			for side in [-1.0, 1.0]:
				var from := Vector2(paddle_x + side * (paddle_w / 2.0 - 12.0), PADDLE_Y - 14.0)
				bolts.append({"p": from, "from": from})
	for bolt in bolts:
		bolt["p"].y -= 950.0 * dt
		if boss != null and boss.alive():
			if boss.hittable() and boss.body_rect().has_point(bolt["p"]):
				_hit_boss(1)
				bolt["dead"] = true
				continue
			if boss.ball_touch(bolt["p"], 4.0) > 0 or boss.ward_touch(bolt["p"], 3.0) != Vector2.INF:
				bolt["dead"] = true
				continue
		for k in _bricks_near(bolt["p"]):
			if (k["hp"] > 0 or not _breaks(k)) and (k["rect"] as Rect2).has_point(bolt["p"]):
				_damage(k, 1, null)
				bolt["dead"] = true
				break
		if bolt["p"].y < ARENA.position.y:
			bolt["dead"] = true
	bolts = bolts.filter(func(b): return not b.get("dead", false))


func _multiplier() -> float:
	return minf(4.0, 1.0 + floorf(combo / 5.0) * 0.5)


# ---------------------------------------------------------------- the boss --

func _boss_step(dt: float) -> void:
	if boss != null:
		boss.step(dt, state == State.PLAY)
		if state == State.PLAY:
			boss.work_balls(balls, dt)


func gale_from(at: Vector2, reach: float, kick: float) -> void:
	"""THE GALE KING'S STAMP: every ball within `reach` of `at` is knocked
	away from it sideways, its speed kept."""
	for b in balls:
		var v: Vector2 = b["v"]
		if v == Vector2.ZERO or (b["p"] as Vector2).distance_to(at) > reach:
			continue
		var away: float = 1.0 if (b["p"] as Vector2).x >= at.x else -1.0
		b["v"] = steady((v + Vector2(away * kick, 0.0)).normalized() * v.length())
		_burst(b["p"], COLOURS["wind"], 6, 160.0, 0.0)


func stun_paddle(seconds: float, at: Vector2, land: String) -> void:
	"""A boss's shot hit the paddle (crownfallboss.gd)."""
	stunned = seconds
	_burst(at, COLOURS.get(land, Color.WHITE), 20, 240.0)
	_say(Vector2(paddle_x, PADDLE_Y - 40.0), "STUNNED", Color(1.0, 0.5, 0.45), 22, 0.9)


func tug_paddle(seconds: float, to_x: float, land: String) -> void:
	"""THE HARPOONER'S HOOK: the paddle slowed and pulled toward `to_x`."""
	tugged = seconds
	tug_x = to_x
	_burst(Vector2(paddle_x, PADDLE_Y - 6.0), COLOURS.get(land, Color.WHITE), 18, 220.0)
	_say(Vector2(paddle_x, PADDLE_Y - 40.0), "HOOKED!", Color(1.0, 0.65, 0.35), 22, 0.9)


func splash_from(at: Vector2, reach: float, kick: float) -> void:
	"""A SPLASH (the Undine, the Leviathan surfacing): every ball within
	`reach` thrown straight away from `at`, a touch faster."""
	for b in balls:
		var v: Vector2 = b["v"]
		if v == Vector2.ZERO or (b["p"] as Vector2).distance_to(at) > reach:
			continue
		var away: Vector2 = ((b["p"] as Vector2) - at).normalized()
		if away == Vector2.ZERO:
			away = Vector2.DOWN
		b["v"] = steady(away * maxf(v.length(), SPEED) * kick)
		_burst(b["p"], COLOURS["water"], 6, 160.0, 0.0)
	_burst(at, COLOURS["water"].lightened(0.3), 30, 300.0, 0.8)
	_say(at + Vector2(0, -40), "SPLASH!", COLOURS["water"].lightened(0.4), 20, 0.7)


func plant_water(at: Vector2) -> bool:
	"""THE TIDE KING'S YOUNG: a water brick where one lands, when the cell is
	empty, on the map's grid and not the hall. Whether it took."""
	var c: Vector2i = cell_at(at)
	if c.x < 0 or c.x >= cols or c.y < 0 or c.y >= maxi(rows_count, 1) or cells.has(c):
		return false
	if hall.size != Vector2.ZERO and hall.grow(2.0).intersects(_cell(c.x, c.y)):
		return false
	var k := _add(c.x, c.y, "land", "water", 1)
	k["flash"] = 1.0
	k["tide"] = true
	footprint[c] = true
	breakable += 1
	_burst(_cell(c.x, c.y).get_center(), COLOURS["water"], 12, 140.0, -0.2)
	return true


func wave_brick(x: float, below: float) -> bool:
	"""THE LEVIATHAN'S WAKE: a water brick in an empty cell of the column at
	`x` the map once held, under `below`, no ball near. Whether one was."""
	var col: int = int(floor((x - FIELD_X) / cw))
	if col < 0 or col >= cols:
		return false
	var spots: Array = []
	for row in rows_count:
		var c := Vector2i(col, row)
		var r := _cell(col, row)
		if footprint.has(c) and not cells.has(c) and r.position.y > below and not _ball_near(r):
			spots.append(c)
	if spots.is_empty():
		return false
	var c: Vector2i = spots[rng.randi_range(0, spots.size() - 1)]
	var k := _add(c.x, c.y, "land", "water", 1)
	k["flash"] = 1.0
	k["tide"] = true
	gone_at.erase(c)
	breakable += 1
	return true


func burst_at(at: Vector2, land: String, n: int) -> void:
	_burst(at, COLOURS.get(land, Color.WHITE), n, 220.0)


func rebuild_near(n: int, around: Rect2, kind: String = "stone") -> void:
	"""THE BUSH MAGE REBUILDS: the `n` broken cells nearest its hall (cells the
	map once held, empty now) come back as stone, two hits - or, the Tide
	Mage's, as bubble bricks."""
	var spots: Array = []
	for c in footprint.keys():
		if not cells.has(c):
			spots.append(c)
	var foot: Vector2 = Vector2(around.get_center().x, around.end.y)
	spots.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return _cell(a.x, a.y).get_center().distance_to(foot) < _cell(b.x, b.y).get_center().distance_to(foot))
	var made: int = 0
	for c in spots:
		if made >= n:
			break
		if _ball_near(_cell(c.x, c.y)):
			continue
		var k: Dictionary
		if kind == "bubble":
			k = _add(c.x, c.y, "bubble", "water", 1)
		else:
			k = _add(c.x, c.y, "stone", "", 2)
			k["most"] = 3
		k["flash"] = 1.0
		gone_at.erase(c)
		breakable += 1
		made += 1
		_burst(_cell(c.x, c.y).get_center(), Color(0.6, 0.58, 0.55), 8, 120.0, -0.2)
	if made > 0:
		_say(Vector2(around.get_center().x, around.end.y + 30.0), "REBUILT", Color(0.75, 0.72, 0.68), 16, 0.8)


func plant_blight(at: Vector2) -> void:
	"""A SMALL SLIME PLANTS THE PLAGUE where it lands: a blight brick in the
	cell, when the cell is empty, on the map's grid and not the hall."""
	var c: Vector2i = cell_at(at)
	if c.x < 0 or c.x >= cols or c.y < 0 or c.y >= maxi(rows_count, 1) or cells.has(c):
		return
	if hall.size != Vector2.ZERO and hall.grow(2.0).intersects(_cell(c.x, c.y)):
		return
	var k := _add(c.x, c.y, "blight", "", 1)
	k["flash"] = 1.0
	footprint[c] = true
	breakable += 1
	_burst(_cell(c.x, c.y).get_center(), BLIGHT, 10, 120.0, -0.2)


func _crumble() -> void:
	"""THE BOSS FALLEN, ITS WALLS COME DOWN: every brick still standing that
	can break is given a moment in CRUMBLE_SECONDS to fall (no score - the
	map is already won). Iron and mirrors stay: they are the place."""
	for k in bricks:
		if k["hp"] > 0 and _breaks(k):
			var r: Rect2 = k["rect"]
			# from the hall outward: nearer the ruler, sooner
			var far: float = clampf(r.get_center().distance_to(boss.p) / 700.0, 0.0, 1.0)
			k["crumble"] = 0.15 + far * CRUMBLE_SECONDS + rng.randf_range(0.0, 0.25)


func _crumbles(dt: float) -> void:
	for k in bricks:
		if k.has("crumble") and k["hp"] > 0:
			k["crumble"] -= dt
			if k["crumble"] <= 0.0:
				k["hp"] = 0
				var mid: Vector2 = (k["rect"] as Rect2).get_center()
				_burst(mid, _colour_of(k), 10, 160.0, 1.2)
				_burst(mid, Color(0.6, 0.95, 0.55), 4, 90.0, -0.5)


func _hit_boss(n: int) -> void:
	if boss == null or not boss.alive():
		return
	var land: String = boss.land
	score += 200
	_burst(boss.p, COLOURS.get(land, Color.WHITE), 10, 200.0)
	if not boss.hit(n):
		return
	score += 5000
	_burst(boss.p, COLOURS.get(land, Color.WHITE), 80, 460.0, 0.2)
	_burst(boss.p, GOLD, 40, 320.0, -0.2)
	rings.append({"p": boss.p, "age": 0.0, "most": 0.9, "c": GOLD, "r": 220.0})
	# The moment is the boss's: what was on screen goes, so the cleared
	# lines always stand under it.
	words.clear()
	if boss.crowned:
		_say(Vector2(640, 330), "THE CROWN FALLS!", GOLD, 38, CLEARED_SECONDS)
	else:
		_say(Vector2(640, 330), "%s IS DEFEATED!" % str(boss.title).to_upper(), GOLD, 34, CLEARED_SECONDS)
	_crumble()
	_shake = 1.0


# ---------------------------------------------------------------- effects --

func _effects(dt: float) -> void:
	for k in bricks:
		k["flash"] = maxf(0.0, k["flash"] - dt * 5.0)
	for p in parts:
		p["p"] += p["v"] * dt
		p["v"] *= 0.94
		p["v"].y += 260.0 * dt * p.get("g", 1.0)
		p["life"] -= dt
	parts = parts.filter(func(p): return p["life"] > 0.0)
	for w in words:
		w["p"].y -= 30.0 * dt
		w["life"] -= dt
		w["age"] += dt
	words = words.filter(func(w): return w["life"] > 0.0)
	for r in rings:
		r["age"] += dt
	rings = rings.filter(func(r): return r["age"] < r["most"])


func _burst(at: Vector2, c: Color, n: int, speed: float, gravity: float = 1.0) -> void:
	for i in n:
		var v := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.3, 1.0) * speed
		var life: float = rng.randf_range(0.35, 0.8)
		parts.append({"p": at, "v": v, "life": life, "most": life, "c": c, "s": rng.randf_range(1.5, 3.2), "g": gravity})
	if parts.size() > 900:
		parts = parts.slice(parts.size() - 900)


func _say(at: Vector2, text: String, c: Color, size: int, life: float = 0.9) -> void:
	"""A WORD THAT POPS UP never lands on another (the owner, of the sketch:
	"SHIELD" and "3 BALLS!" stacked on top of each other): it is kept inside
	the arena, clear of the side panels, and moved up past every word on
	screen it would touch - asked again after each move, so a word moved off
	one cannot land on the next."""
	var w_px: float = _word_width(text, size)
	var half: float = w_px / 2.0 + 10.0
	at.x = clampf(at.x, ARENA.position.x + half, ARENA.end.x - half)
	for attempt in WORD_TRIES:
		var mine := _word_rect(at, w_px, size)
		var clash: Dictionary = {}
		for w in words:
			if _word_rect(w["p"], _word_width(w["text"], int(w["size"])), int(w["size"])).intersects(mine):
				clash = w
				break
		if clash.is_empty():
			break
		at.y = float(clash["p"].y) - float(clash["size"]) - WORD_GAP
	at.y = maxf(at.y, ARENA.position.y + size + 4.0)
	words.append({"p": at, "text": text, "life": life, "most": life, "c": c, "size": size, "age": 0.0})


func _word_width(text: String, size: int) -> float:
	if _bold == null:
		return text.length() * size * 0.6
	return _bold.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


static func _word_rect(at: Vector2, width: float, size: int) -> Rect2:
	"""Where a word drawn centred on `at` (its baseline) stands."""
	return Rect2(at.x - width / 2.0 - 6.0, at.y - size, width + 12.0, size + 6.0)


func _colour_of(k: Dictionary) -> Color:
	match k["kind"]:
		"stone":
			return Color(0.56, 0.54, 0.52)
		"iron":
			return Color(0.42, 0.45, 0.52)
		"mirror":
			return MIRROR_BLUE.lightened(0.4)
		"tnt":
			return Color(0.86, 0.16, 0.14)
		"bonus":
			return GOLD
		"blight":
			return BLIGHT
		"heart":
			return COLOURS["light"]
		"crystal":
			return Color(0.72, 0.93, 1.0)
		"key":
			return GOLD
		"gold":
			return Color(1.0, 0.76, 0.18)
		"shell":
			return Color(0.93, 0.74, 0.64)
		"mimic":
			return Color(0.58, 0.56, 0.68)
		"plague":
			return Color(0.3, 0.42, 0.22)
		"mix":
			return COLOURS[MIX_LANDS.get(str(k.get("mix", "clash")), ["light"])[0]]
		"rune":
			return Color(0.95, 0.8, 0.4)
		"bumper":
			return Color(1.0, 0.6, 0.85)
		"portal":
			return Color(0.6, 0.3, 0.9)
		"lock":
			return Color(0.42, 0.45, 0.52)
	return COLOURS.get(k["land"], Color.WHITE)


func _draw_frozen(r: Rect2) -> void:
	"""Ice over a frozen brick: one touch breaks it."""
	draw_rect(r.grow(1.0), Color(0.75, 0.95, 1.0, 0.45))
	draw_line(r.position + Vector2(3, 3), r.get_center() + Vector2(2, 1), Color(1, 1, 1, 0.8), 1.0)
	draw_line(r.get_center() + Vector2(2, 1), r.end - Vector2(4, 3), Color(1, 1, 1, 0.8), 1.0)
	draw_rect(r.grow(1.0), Color(0.9, 1.0, 1.0, 0.9), false, 1.0)


# ---------------------------------------------------------------- drawing --

func _draw() -> void:
	_draw_backdrop()
	if state == State.KINGDOMS:
		_draw_kingdoms()
		return
	var jolt := Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * _shake * 4.0
	_jolt = jolt
	draw_set_transform(jolt)
	_draw_arena()
	_draw_building()
	_draw_tide_body()
	_draw_gusts()
	_draw_rails()
	for k in bricks:
		if (k["hp"] > 0 or not _breaks(k)) and not k.has("rail"):
			var r: Rect2 = k["rect"]
			draw_rect(Rect2(r.position + Vector2(2, 3), r.size), Color(0, 0, 0, 0.38))
	for k in bricks:
		if (k["hp"] > 0 or not _breaks(k)) and not k.has("rail"):
			_draw_brick(k)
			if k.has("warded") and k["hp"] > 0:
				draw_rect((k["rect"] as Rect2).grow(1.5), Color(GUARD_GLOW, float(k["warded"])), false, 2.0)
			if bool(k.get("frozen", false)) and k["hp"] > 0:
				_draw_frozen(k["rect"])
			if pulling and k["hp"] > 0 and _breaks(k) and not _guarded(k):
				var glow: float = 0.5 + 0.5 * sin(t * 6.0)
				draw_rect((k["rect"] as Rect2).grow(3.0 + glow * 3.0), Color(GOLD, 0.35 + 0.35 * glow), false, 2.0)
	_draw_guards()
	_draw_tide_top()
	for bu in bubbles:
		var at: Vector2 = bu["p"] + Vector2(sin(t * 9.0 + bu["p"].y * 0.05) * 2.5, 0)
		draw_circle(at, 6.0, Color(COLOURS["water"], 0.25))
		draw_arc(at, 5.0, 0, TAU, 16, Color(0.8, 0.92, 1.0, 0.9), 1.4)
		draw_circle(at + Vector2(-1.8, -1.8), 1.3, Color(1, 1, 1, 0.9))
	for d in drips:
		draw_circle(d["p"], 9.0, Color(COLOURS["fire"], 0.3))
		draw_circle(d["p"], 5.0, Color(1.0, 0.55, 0.15))
		draw_circle(d["p"], 2.5, Color(1.0, 0.9, 0.6))
	for z in zaps:
		var a: float = 1.0 - float(z["age"]) / 0.3
		draw_polyline(z["pts"], Color(z["c"], 0.35 * a), 7.0, true)
		draw_polyline(z["pts"], Color(Color.WHITE, a), 2.0, true)
	if _eclipse > 0.0:
		draw_rect(ARENA, Color(0.05, 0.0, 0.12, 0.45 * _eclipse / 0.5))
	_draw_boss()
	if state == State.AIM:
		_draw_tracer(_path(Vector2(paddle_x, PADDLE_Y - BALL_R - 8.0), Vector2.from_angle(aim), 1000.0), INK, true)
	for bolt in bolts:
		_draw_tracer(PackedVector2Array([bolt["from"], bolt["p"]]), COLOURS["fire"], false, true)
	for c in caps:
		_draw_capsule(c)
	if active.has("shield"):
		var a: float = 0.55 + 0.25 * sin(t * 6.0) + _shield_flash * 0.4
		draw_line(Vector2(ARENA.position.x + 6, SHIELD_Y), Vector2(ARENA.end.x - 6, SHIELD_Y), Color(COLOURS["water"], a * 0.35), 10.0)
		draw_line(Vector2(ARENA.position.x + 6, SHIELD_Y), Vector2(ARENA.end.x - 6, SHIELD_Y), Color(0.7, 0.85, 1.0, a), 2.5)
	for b in balls:
		_draw_trail(b)
	for b in balls:
		_draw_ball(b)
	_draw_paddle()
	for r in rings:
		var u: float = r["age"] / r["most"]
		draw_arc(r["p"], r["r"] * u, 0, TAU, 48, Color(r["c"], 1.0 - u), 6.0 * (1.0 - u) + 1.0)
	for p in parts:
		var a: float = clampf(p["life"] / p["most"], 0.0, 1.0)
		draw_circle(p["p"], p["s"] * (0.5 + a * 0.5), Color(p["c"], a))
	for w in words:
		var a: float = clampf(w["life"] / 0.45, 0.0, 1.0)
		var pop: float = 1.0 + 0.35 * maxf(0.0, 1.0 - w["age"] / 0.12)
		_text(w["p"], w["text"], int(w["size"] * pop), Color(w["c"], a), null, true, a)
	draw_set_transform(Vector2.ZERO)
	_draw_banner()
	if state == State.AIM and _banner_t <= 0.0 and launch_hint != "":
		_text(Vector2(paddle_x, PADDLE_Y - 34.0), launch_hint, 14, Color(INK, 0.55 + 0.25 * sin(t * 3.0)), _font, true)
	_draw_hud()
	_draw_left_panel()
	_draw_right_panel()


func _draw_banner() -> void:
	"""A MAP OPENS WITH ITS NAME: a band across the arena, under the bricks
	and over the paddle, for BANNER_SECONDS - which map of the kingdom (or
	its citadel), its name, and its line."""
	if _banner_t <= 0.0 or state == State.KINGDOMS:
		return
	var a: float = clampf(_banner_t / 0.4, 0.0, 1.0) * clampf((BANNER_SECONDS - _banner_t) / 0.25, 0.0, 1.0)
	var data: Dictionary = Maps.MAPS[map_index]
	var kingdom: Dictionary = Maps.kingdom_of(map_index)
	var colour: Color = COLOURS.get(kingdom.get("land", "light"), GOLD)
	var band := Rect2(ARENA.position.x, 432, ARENA.size.x, 116)
	draw_rect(band, Color(0, 0, 0, 0.62 * a))
	draw_line(band.position, Vector2(band.end.x, band.position.y), Color(colour, 0.7 * a), 2.0)
	draw_line(Vector2(band.position.x, band.end.y), band.end, Color(colour, 0.7 * a), 2.0)
	var which: String = "MAP %d OF %d" % [Maps.in_kingdom(map_index) + 1, Maps.MAPS_A_KINGDOM]
	if data.get("boss") is Dictionary:
		which = ("THE CITADEL" if bool(data["boss"].get("crown", false)) else "A GUARDIAN") + "  ·  " + which
	_text(Vector2(640, 462), "%s  ·  %s" % [which, str(kingdom.get("name", "")).to_upper()], 14, Color(colour, a), null, true, a)
	_text(Vector2(640, 506), str(data["name"]).to_upper(), 40, Color(INK, a), null, true, a)
	_text(Vector2(640, 534), str(data["line"]), 16, Color(INK, 0.75 * a), _font, true, a)


func _draw_backdrop() -> void:
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(VIEW.x, 0), VIEW, Vector2(0, VIEW.y)]),
		PackedColorArray([Color(0.05, 0.05, 0.1), Color(0.05, 0.05, 0.1), Color(0.02, 0.02, 0.04), Color(0.02, 0.02, 0.04)]))
	for i in 70:
		var s := Vector2(fmod(i * 197.3, VIEW.x), fmod(i * 83.1 + 40.0, VIEW.y))
		draw_circle(s, 0.9 + (i % 3) * 0.4, Color(1, 1, 1, 0.06 + 0.05 * sin(t * 1.3 + i)))


func _draw_arena() -> void:
	var sick: float = 0.0 if breakable <= 0 else clampf(1.0 - float(broken) / float(breakable), 0.0, 1.0)
	sick *= 1.0 - _healed
	var top := Color(0.075, 0.08, 0.13).lerp(Color(0.09, 0.11, 0.06), sick * 0.8)
	var low := Color(0.04, 0.045, 0.075).lerp(Color(0.05, 0.07, 0.03), sick * 0.8)
	if _healed > 0.0:
		top = top.lerp(Color(0.08, 0.13, 0.1), _healed * 0.6)
		low = low.lerp(Color(0.05, 0.09, 0.06), _healed * 0.6)
	draw_polygon(PackedVector2Array([ARENA.position, Vector2(ARENA.end.x, ARENA.position.y), ARENA.end,
		Vector2(ARENA.position.x, ARENA.end.y)]), PackedColorArray([top, top, low, low]))
	for gx in range(int(ARENA.position.x) + 40, int(ARENA.end.x), 40):
		draw_line(Vector2(gx, ARENA.position.y), Vector2(gx, ARENA.end.y), Color(1, 1, 1, 0.022), 1.0)
	for gy in range(int(ARENA.position.y) + 40, int(ARENA.end.y), 40):
		draw_line(Vector2(ARENA.position.x, gy), Vector2(ARENA.end.x, gy), Color(1, 1, 1, 0.016), 1.0)
	# THE PLAGUE'S HAZE, thinning as the map is broken
	if sick > 0.0:
		for i in 7:
			var y: float = ARENA.end.y - 40.0 - i * 26.0 + sin(t * 0.7 + i) * 6.0
			draw_line(Vector2(ARENA.position.x, y), Vector2(ARENA.end.x, y), Color(BLIGHT, 0.035 * sick), 22.0)
	var jolt := Vector2.ZERO
	draw_set_transform(Vector2(paddle_x, PADDLE_Y + 14.0) + jolt, 0.0, Vector2(1.0, 0.22))
	for i in 5:
		draw_circle(Vector2.ZERO, paddle_w * (0.7 + i * 0.22), Color(GOLD, 0.05))
	draw_set_transform(_jolt)
	for i in 6:
		draw_rect(ARENA.grow(-i * 5.0), Color(0, 0, 0, 0.09), false, 5.0)
	draw_rect(ARENA.grow(7), EDGE, false, 10.0)
	draw_rect(ARENA.grow(13), Color(0.14, 0.12, 0.11), false, 2.0)
	draw_rect(ARENA.grow(2.5), Color(GOLD, 0.35), false, 1.5)
	for corner in [ARENA.position, Vector2(ARENA.end.x, ARENA.position.y), ARENA.end, Vector2(ARENA.position.x, ARENA.end.y)]:
		draw_colored_polygon(PackedVector2Array([corner + Vector2(0, -11), corner + Vector2(11, 0), corner + Vector2(0, 11),
			corner + Vector2(-11, 0)]), GOLD)
		draw_colored_polygon(PackedVector2Array([corner + Vector2(0, -5), corner + Vector2(5, 0), corner + Vector2(0, 5),
			corner + Vector2(-5, 0)]), Color(0.3, 0.2, 0.05))


func _draw_building() -> void:
	"""THE STONE THE BRICKS ARE SET IN: behind every cell the map held, so a
	hole reads as a hole in a wall and not a gap in a row."""
	for c in footprint.keys():
		var r := _cell(c.x, c.y).grow(1.5)
		draw_rect(r, Color(0.12, 0.115, 0.14))
	for c in footprint.keys():
		var r := _cell(c.x, c.y).grow(1.5)
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if footprint.has(c + d):
				continue
			match d:
				Vector2i(1, 0):
					draw_line(Vector2(r.end.x, r.position.y), r.end, Color(0.33, 0.31, 0.29), 2.0)
				Vector2i(-1, 0):
					draw_line(r.position, Vector2(r.position.x, r.end.y), Color(0.33, 0.31, 0.29), 2.0)
				Vector2i(0, 1):
					draw_line(Vector2(r.position.x, r.end.y), r.end, Color(0.33, 0.31, 0.29), 2.0)
				Vector2i(0, -1):
					draw_line(r.position, Vector2(r.end.x, r.position.y), Color(0.33, 0.31, 0.29), 2.0)
	if hall.size != Vector2.ZERO:
		draw_rect(hall.grow(2.0), Color(0.09, 0.08, 0.1))
		draw_rect(hall.grow(2.0), Color(GOLD, 0.25), false, 1.5)
		for i in 6:
			var x: float = hall.position.x + (i + 0.5) * hall.size.x / 6.0
			draw_line(Vector2(x, hall.position.y + 4), Vector2(x, hall.end.y - 4), Color(1, 1, 1, 0.04), 8.0)


func _draw_rails() -> void:
	"""The lanes' floor a shade darker, and their iron rails: dark steel, a
	lit edge, rivets, and a gold cap at each gate."""
	for x in [ARENA.position.x, FIELD_X + FIELD_W + RAIL_W]:
		draw_rect(Rect2(x, ARENA.position.y, SIDE_GAP - RAIL_W, field_bottom() - ARENA.position.y), Color(0, 0, 0, 0.18))
	for k in rails:
		var r: Rect2 = k["rect"]
		draw_rect(r.grow(1.0), Color(GOLD, 0.22))
		draw_rect(r, Color(0.34, 0.37, 0.45).lerp(Color.WHITE, float(k["flash"]) * 0.5))
		draw_rect(Rect2(r.position, Vector2(1.5, r.size.y)), Color(0.8, 0.84, 0.92))
		for y in range(int(r.position.y) + 10, int(r.end.y) - 4, 24):
			draw_circle(Vector2(r.get_center().x, y), 1.2, Color(0.75, 0.78, 0.85))
		for y in [r.position.y, r.end.y]:
			if y > ARENA.position.y + 1.0:
				draw_rect(Rect2(r.position.x - 1.5, y - 1.5, r.size.x + 3.0, 3.0), GOLD)


func _draw_gusts() -> void:
	"""A gust: a faint band of its own, streaks running its way through it,
	and chevrons at its edges pointing that way."""
	for g in gusts:
		var y0: float = g["y0"]
		var y1: float = g["y1"]
		var way: float = g["way"]
		draw_rect(Rect2(ARENA.position.x, y0, ARENA.size.x, y1 - y0), Color(COLOURS["wind"], 0.05))
		var lanes: int = maxi(2, int((y1 - y0) / 11.0))
		for i in lanes:
			var y: float = y0 + (i + 0.5) * (y1 - y0) / lanes
			var run_x: float = fposmod(t * 260.0 * way + i * 137.0, ARENA.size.x + 120.0) - 60.0
			for j in 3:
				var x: float = ARENA.position.x + fposmod(run_x + j * (ARENA.size.x / 3.0), ARENA.size.x)
				draw_line(Vector2(x, y), Vector2(x - way * 46.0, y), Color(COLOURS["wind"], 0.28), 2.0)
		for edge in [ARENA.position.x + 12.0, ARENA.end.x - 12.0]:
			var mid: float = (y0 + y1) / 2.0
			draw_polyline(PackedVector2Array([Vector2(edge - way * 5.0, mid - 7.0), Vector2(edge + way * 5.0, mid),
				Vector2(edge - way * 5.0, mid + 7.0)]), Color(COLOURS["wind"], 0.7), 2.0)


func _draw_tide_body() -> void:
	"""THE TIDE: its mark in each lane and faint across the field, always; the
	water itself from the foot of the rows up to where it stands, under the
	bricks."""
	if tide_mark < 0:
		return
	var mark: float = tide_line()
	var blue: Color = COLOURS["water"]
	for x in range(int(FIELD_X) + 4, int(FIELD_X + FIELD_W) - 4, 14):
		draw_line(Vector2(x, mark), Vector2(x + 6, mark), Color(blue, 0.18), 1.0)
	for x in [ARENA.position.x + 4.0, FIELD_X + FIELD_W + RAIL_W + 4.0]:
		for i in 2:
			var y: float = mark - 3.0 + i * 5.0
			draw_polyline(PackedVector2Array([Vector2(x, y), Vector2(x + 5, y - 2.5), Vector2(x + 10, y), Vector2(x + 15, y - 2.5),
				Vector2(x + 20, y)]), Color(blue.lightened(0.3), 0.75), 1.4)
	var level: float = tide_level()
	if level <= 0.0:
		return
	var top: float = tide_y()
	var foot: float = field_bottom() + 6.0
	draw_rect(Rect2(ARENA.position.x, top, ARENA.size.x, foot - top), Color(blue, 0.16 + 0.06 * level))
	for i in 3:
		var y: float = top + 14.0 + i * 22.0
		if y < foot - 4.0:
			draw_line(Vector2(ARENA.position.x, y), Vector2(ARENA.end.x, y), Color(blue.lightened(0.2), 0.05), 6.0)


func _draw_tide_top() -> void:
	"""Over the bricks: the water they stand in, tinting them blue, and its
	surface - a moving wave, foam on its crests."""
	var level: float = tide_level()
	if tide_mark < 0 or level <= 0.0:
		return
	var top: float = tide_y()
	draw_rect(Rect2(ARENA.position.x, top, ARENA.size.x, field_bottom() + 6.0 - top), Color(COLOURS["water"], 0.2 * level))
	var pts := PackedVector2Array()
	var x: float = ARENA.position.x
	while x <= ARENA.end.x:
		pts.append(Vector2(x, top + sin(x * 0.045 + t * 3.0) * 3.0 + sin(x * 0.11 - t * 2.0) * 1.5))
		x += 8.0
	draw_polyline(pts, Color(COLOURS["water"].lightened(0.25), 0.55 * level), 4.0)
	draw_polyline(pts, Color(0.88, 0.95, 1.0, 0.8 * level), 1.5)


func _draw_half_shell(mid: Vector2, w: float, h: float, up: bool, c: Color) -> void:
	"""Half an ellipse, flat side to `mid`: up, the clam's lid; down, its foot."""
	var pts := PackedVector2Array([mid + Vector2(-w, 0)])
	for i in range(1, 12):
		var a: float = PI * i / 12.0
		pts.append(mid + Vector2(-cos(a) * w, sin(a) * h * (-1.0 if up else 1.0)))
	pts.append(mid + Vector2(w, 0))
	draw_colored_polygon(pts, c)
	for i in [-1, 0, 1]:
		draw_line(mid, mid + Vector2(i * w * 0.55, h * 0.8 * (-1.0 if up else 1.0)), Color(0, 0, 0, 0.25), 1.0)


func _draw_guards() -> void:
	"""Round every standing Guard, the cells it shields: a soft blue frame."""
	var pulse: float = 0.5 + 0.5 * sin(t * 3.0)
	for k in bricks:
		if k["kind"] == "guard" and k["hp"] > 0 and k.has("cell"):
			var c: Vector2i = k["cell"]
			var box: Rect2 = _cell(c.x - 1, c.y - 1).merge(_cell(c.x + 1, c.y + 1)).grow(2.0)
			draw_rect(box, Color(GUARD_GLOW, 0.05 + 0.04 * pulse))
			draw_rect(box, Color(GUARD_GLOW, 0.4 + 0.25 * pulse), false, 1.5)


func _draw_brick(k: Dictionary) -> void:
	"""A brick at its own size: on a big map the standard brick (CW - 2 by
	CH) is drawn scaled down into its rect."""
	var r: Rect2 = k["rect"]
	var standard := Vector2(CW - 2.0, CH)
	if r.size.is_equal_approx(standard) or k["kind"] == "heart":
		_draw_brick_in(k, r)
		return
	draw_set_transform(_jolt + r.position, 0.0, r.size / standard)
	_draw_brick_in(k, Rect2(Vector2.ZERO, standard))
	draw_set_transform(_jolt)


func _draw_brick_in(k: Dictionary, r: Rect2) -> void:
	var c: Color = _colour_of(k)
	var flash: float = k["flash"]
	var lit: float = 0.5 + 0.5 * sin(t * 40.0) if k["burn"] >= 0.0 else 0.0
	var mid: Vector2 = r.get_center()
	match k["kind"]:
		"iron":
			draw_rect(r, Color(0.2, 0.22, 0.27).lerp(Color.WHITE, flash * 0.5))
			draw_rect(Rect2(r.position, Vector2(r.size.x, 3)), Color(0.62, 0.66, 0.75))
			draw_rect(r, GOLD.darkened(0.3), false, 1.5)
			for x in [r.position.x + 4, r.end.x - 4]:
				for y in [r.position.y + 4, r.end.y - 4]:
					draw_circle(Vector2(x, y), 1.4, Color(0.75, 0.78, 0.85))
			return
		"mirror":
			# A DEEPER BLUE THAN ANY STONE (the owner: mirrors beside grey
			# stone should "pop immediately as angled deflectors"), with a
			# soft blue rim and the glint along its slant.
			draw_rect(r.grow(1.5), Color(MIRROR_BLUE, 0.35 + 0.15 * sin(t * 2.0 + r.position.x * 0.05)), false, 2.0)
			draw_rect(r, MIRROR_BLUE.darkened(0.25).lerp(Color.WHITE, flash * 0.7))
			draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.5)), MIRROR_BLUE.lerp(Color.WHITE, 0.15 + flash * 0.6))
			var shine: float = 0.5 + 0.5 * sin(t * 2.0 + r.position.x * 0.05)
			draw_line(r.position + Vector2(4, r.size.y - 3), r.position + Vector2(r.size.x - 4, 3), Color(1, 1, 1, 0.55 + 0.4 * shine), 2.5)
			draw_rect(r, Color(0.85, 0.93, 1.0, 0.8), false, 1.2)
			return
		"bumper":
			# round, pink, and it lights when struck
			var ring_r: float = r.size.y * 0.5 + 1.0
			draw_circle(mid, ring_r + 3.0 + flash * 3.0, Color(1.0, 0.45, 0.8, 0.25 + flash * 0.3))
			draw_circle(mid, ring_r, Color(0.55, 0.18, 0.45).lerp(Color.WHITE, flash * 0.5))
			draw_circle(mid, ring_r - 3.0, Color(1.0, 0.55, 0.85).lerp(Color.WHITE, flash * 0.6))
			draw_circle(mid + Vector2(-2, -2), 2.0, Color(1, 1, 1, 0.9))
			return
		"portal":
			# a swirl, its pair's colour
			var hue: Color = PORTAL_HUES[int(k.get("pair", 0)) % PORTAL_HUES.size()] if k.has("to") else Color(0.4, 0.4, 0.45)
			draw_rect(r, Color(0.06, 0.03, 0.1))
			for i in 3:
				var a0: float = t * 3.0 + i * TAU / 3.0
				draw_arc(mid, 6.0 - i * 1.5, a0, a0 + PI * 1.2, 10, Color(hue.lerp(Color.WHITE, flash * 0.6), 0.9 - i * 0.2), 1.6)
			draw_rect(r, Color(hue, 0.8), false, 1.2)
			return
		"whirl":
			# A WHIRL: a pinwheel always turning, faster when struck
			draw_rect(r, Color(0.08, 0.16, 0.14))
			var spin: float = t * (5.0 + flash * 14.0) + float(k.get("phase", 0.0))
			for i in 4:
				var a: float = spin + i * TAU / 4.0
				var tip: Vector2 = mid + Vector2.from_angle(a) * (r.size.y * 0.5 + 2.0)
				var side: Vector2 = mid + Vector2.from_angle(a + 0.9) * (r.size.y * 0.32)
				draw_colored_polygon(PackedVector2Array([mid, tip, side]), COLOURS["wind"].lerp(Color.WHITE, 0.15 + flash * 0.5))
			draw_circle(mid, 2.0, Color(1, 1, 1, 0.9))
			draw_rect(r, Color(COLOURS["wind"], 0.6), false, 1.2)
			return
		"guard":
			# A GUARD: a steel plate, a gold shield on it (dimmed once struck)
			draw_rect(r, Color(0.22, 0.3, 0.45).lerp(Color.WHITE, flash * 0.5))
			draw_rect(Rect2(r.position, Vector2(r.size.x, 3)), Color(0.55, 0.68, 0.9))
			var crest := PackedVector2Array([mid + Vector2(-5, -5), mid + Vector2(5, -5), mid + Vector2(5, 0),
				mid + Vector2(0, 6), mid + Vector2(-5, 0)])
			draw_colored_polygon(crest, GOLD if k["hp"] >= 2 else GOLD.darkened(0.45))
			crest.append(crest[0])
			draw_polyline(crest, Color(0.3, 0.2, 0.05), 1.0)
			draw_rect(r, GUARD_GLOW, false, 1.5)
			return
		"lock":
			draw_rect(r, Color(0.2, 0.22, 0.27).lerp(Color.WHITE, flash * 0.4))
			draw_rect(r, GOLD.darkened(0.3), false, 1.5)
			draw_arc(mid + Vector2(0, -1), 3.5, PI, TAU, 10, GOLD, 1.6)
			draw_rect(Rect2(mid + Vector2(-4.5, -1), Vector2(9, 6)), GOLD)
			draw_circle(mid + Vector2(0, 2), 1.2, Color(0.2, 0.15, 0.05))
			return
		"rune":
			var on: float = 1.0 if _rune_lit(k) else 0.0
			draw_rect(r, Color(0.12, 0.13, 0.2).lerp(Color(0.45, 0.35, 0.12), on * 0.6).lerp(Color.WHITE, flash * 0.4))
			var glyph: Color = Color(1.0, 0.85, 0.35, 0.35 + on * 0.65)
			draw_polyline(PackedVector2Array([mid + Vector2(0, -5), mid + Vector2(5, 0), mid + Vector2(0, 5), mid + Vector2(-5, 0),
				mid + Vector2(0, -5)]), glyph, 1.4)
			draw_line(mid + Vector2(0, -5), mid + Vector2(0, 5), glyph, 1.2)
			if on > 0.0:
				draw_rect(r.grow(1.5), Color(1.0, 0.85, 0.35, 0.5), false, 1.5)
			else:
				draw_rect(r, Color(0.4, 0.45, 0.6, 0.6), false, 1.0)
			return
		"mix":
			# two lands, split on the diagonal
			var lands: Array = MIX_LANDS.get(str(k.get("mix", "clash")), ["light", "light"])
			var a_col: Color = COLOURS[lands[0]].lerp(Color.WHITE, flash * 0.5)
			var b_col: Color = COLOURS[lands[1]].lerp(Color.WHITE, flash * 0.5)
			draw_rect(r, a_col.darkened(0.15))
			draw_colored_polygon(PackedVector2Array([Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
				b_col.darkened(0.1))
			draw_rect(Rect2(r.position, Vector2(r.size.x, 2)), Color(1, 1, 1, 0.4))
			var spark: float = 0.6 + 0.4 * sin(t * 6.0 + r.position.x)
			draw_line(mid + Vector2(-3, -3), mid + Vector2(3, 3), Color(1, 1, 1, spark), 1.4)
			draw_line(mid + Vector2(-3, 3), mid + Vector2(3, -3), Color(1, 1, 1, spark), 1.4)
			draw_rect(r, Color(1, 1, 1, 0.35), false, 1.0)
			return
		"clam":
			# A CLAM: its lid lifts when it opens, the pearl shining inside
			var o: float = clam_open(k)
			draw_rect(r, Color(0.08, 0.14, 0.24).lerp(Color.WHITE, flash * 0.4))
			var shell := Color(0.72, 0.62, 0.78).lerp(Color.WHITE, flash * 0.5)
			var hinge: Vector2 = mid + Vector2(0, 2.0)
			if o > 0.0:
				draw_circle(hinge + Vector2(0, -2.0 * o), 3.4, Color(1, 1, 1, 0.25 * o))
				draw_circle(hinge + Vector2(0, -2.0 * o), 2.6, Color(0.96, 0.96, 1.0, o))
			_draw_half_shell(hinge, r.size.x * 0.4, r.size.y * 0.42, false, shell.darkened(0.15))
			_draw_half_shell(hinge + Vector2(0, -1.0 - 4.5 * o), r.size.x * 0.4, r.size.y * 0.5, true, shell)
			draw_rect(r, Color(0.85, 0.75, 0.95, 0.4 + 0.5 * o), false, 1.2)
			return
		"heart":
			var pulse: float = 0.5 + 0.5 * sin(t * 3.0)
			var hw: float = r.size.x * 0.46
			var hh: float = r.size.y * 0.5 + 3.0
			draw_circle(mid, hw + 6.0 + pulse * 5.0, Color(BLIGHT, 0.10 + 0.05 * pulse))
			var gem := PackedVector2Array([mid + Vector2(0, -hh), mid + Vector2(hw, 0), mid + Vector2(0, hh), mid + Vector2(-hw, 0)])
			draw_colored_polygon(gem, BLIGHT.darkened(0.3).lerp(COLOURS["light"], 0.25 + pulse * 0.2).lerp(Color.WHITE, flash * 0.6))
			draw_colored_polygon(PackedVector2Array([gem[0], gem[1], mid]), Color(1, 1, 1, 0.25))
			draw_polyline(PackedVector2Array([gem[0], gem[1], gem[2], gem[3], gem[0]]), COLOURS["light"], 2.0)
			for i in k["most"]:
				draw_circle(mid + Vector2(-12.5 + i * 5.0, hh + 6.0), 2.0, COLOURS["light"] if i < k["hp"] else Color(1, 1, 1, 0.15))
			return
	var base: Color = c.darkened(0.38).lerp(COLOURS["fire"], lit * 0.6).lerp(Color.WHITE, flash * 0.55)
	draw_rect(r, base)
	draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.48)), c.lerp(Color.WHITE, 0.1).lerp(Color.WHITE, flash * 0.55))
	draw_rect(Rect2(r.position, Vector2(r.size.x, 2)), Color(1, 1, 1, 0.38))
	draw_rect(Rect2(r.position.x, r.end.y - 2, r.size.x, 2), Color(0, 0, 0, 0.4))
	var ink := Color(1, 1, 1, 0.6)
	if k.has("tide"):
		# BROUGHT BACK BY THE TIDE: foam along its top
		for i in 4:
			draw_arc(Vector2(r.position.x + 3.5 + i * (r.size.x - 7.0) / 3.0, r.position.y + 2.0), 2.4, 0, PI, 6,
				Color(0.9, 0.97, 1.0, 0.8), 1.2)
	if k.has("kite"):
		# A KITE: a cross-spar, and a tail of bows fluttering under it
		draw_line(Vector2(mid.x, r.position.y + 1), Vector2(mid.x, r.end.y - 1), Color(1, 1, 1, 0.45), 1.0)
		for i in 3:
			var at: Vector2 = Vector2(mid.x + sin(t * 6.0 + i + r.position.y) * 3.0, r.end.y + 4.0 + i * 5.0)
			draw_line(at + Vector2(-3, -2), at + Vector2(3, 2), Color(COLOURS["fire"], 0.85), 2.0)
			draw_line(at + Vector2(-3, 2), at + Vector2(3, -2), Color(COLOURS["fire"], 0.85), 2.0)
	match k["kind"]:
		"stone":
			draw_line(Vector2(r.position.x, mid.y), Vector2(r.end.x, mid.y), Color(0, 0, 0, 0.28), 1.0)
			draw_line(Vector2(mid.x - 6, r.position.y), Vector2(mid.x - 6, mid.y), Color(0, 0, 0, 0.28), 1.0)
			draw_line(Vector2(mid.x + 8, mid.y), Vector2(mid.x + 8, r.end.y), Color(0, 0, 0, 0.28), 1.0)
			if k["hp"] <= 2:
				draw_polyline(PackedVector2Array([r.position + Vector2(6, 2), mid + Vector2(-3, 1), mid + Vector2(5, -3)]), Color(0, 0, 0, 0.7), 1.4)
			if k["hp"] <= 1:
				draw_polyline(PackedVector2Array([mid + Vector2(-3, 1), mid + Vector2(2, 7), r.end - Vector2(5, 2)]), Color(0, 0, 0, 0.7), 1.4)
		"tnt":
			draw_rect(Rect2(r.position.x + 4, mid.y - 2, r.size.x - 8, 4), Color(0.25, 0.08, 0.05))
			draw_circle(mid + Vector2(11, -5), 1.8 + sin(t * 20.0), Color(1, 0.8, 0.3))
			_text(mid + Vector2(0, 4), "TNT", 9, Color(1, 0.95, 0.85), null, true, 1.0, 0)
		"bonus":
			var glow: float = 0.5 + 0.5 * sin(t * 5.0)
			draw_rect(r.grow(2.0 + glow * 2.0), Color(GOLD, 0.25 * glow), false, 2.0)
			_text(mid + Vector2(0, 5), "?", 13, Color(0.35, 0.22, 0.02), null, true, 1.0, 0)
		"blight", "plague":
			for i in 3:
				var at: Vector2 = mid + Vector2(-7 + i * 7, sin(t * 3.0 + i + r.position.x) * 1.5)
				draw_circle(at, 1.8, Color(0.75, 0.95, 0.35, 0.8))
			if k["kind"] == "plague":
				draw_rect(r, Color(0.1, 0.16, 0.06, 0.8), false, 1.5)
				if k["hp"] <= 1:
					draw_line(r.position + Vector2(5, 2), mid + Vector2(2, 3), Color(0, 0, 0, 0.6), 1.2)
		"crystal":
			draw_colored_polygon(PackedVector2Array([mid + Vector2(0, -6), mid + Vector2(7, 0), mid + Vector2(0, 6), mid + Vector2(-7, 0)]),
				Color(1, 1, 1, 0.85))
			draw_colored_polygon(PackedVector2Array([mid + Vector2(0, -6), mid + Vector2(7, 0), mid]), Color(0.6, 0.9, 1.0, 0.9))
		"key":
			draw_circle(mid + Vector2(-6, 0), 3.2, Color(0.4, 0.26, 0.04))
			draw_line(mid + Vector2(-3, 0), mid + Vector2(8, 0), Color(0.4, 0.26, 0.04), 1.8)
			draw_line(mid + Vector2(5, 0), mid + Vector2(5, 3), Color(0.4, 0.26, 0.04), 1.6)
			draw_line(mid + Vector2(8, 0), mid + Vector2(8, 3), Color(0.4, 0.26, 0.04), 1.6)
		"gold":
			draw_circle(mid, 4.5, Color(1.0, 0.92, 0.5))
			draw_arc(mid, 4.5, 0, TAU, 14, Color(0.55, 0.38, 0.05), 1.2)
			var sweep: float = fmod(t * 0.8 + r.position.x * 0.01, 1.6) - 0.3
			if sweep >= 0.0 and sweep <= 1.0:
				var x: float = r.position.x + r.size.x * sweep
				draw_line(Vector2(x, r.position.y + 1), Vector2(x - 4, r.end.y - 1), Color(1, 1, 1, 0.6), 2.0)
			if k["hp"] <= 1:
				draw_line(r.position + Vector2(4, 1), mid + Vector2(-1, 2), Color(0, 0, 0, 0.5), 1.2)
		"shell":
			for i in 3:
				draw_arc(mid + Vector2(0, 6), 3.0 + i * 3.0, PI * 1.15, PI * 1.85, 10, Color(0.55, 0.35, 0.3, 0.8), 1.2)
		"prism":
			for i in ELEMENTS.size():
				var w: float = r.size.x / ELEMENTS.size()
				draw_rect(Rect2(r.position.x + i * w, r.end.y - 3, w, 3), COLOURS[ELEMENTS[i]])
			draw_colored_polygon(PackedVector2Array([mid + Vector2(0, -5), mid + Vector2(5, 3), mid + Vector2(-5, 3)]), Color(1, 1, 1, 0.75))
		"buoy":
			# A BUOY: a red float banded white, its lamp blinking
			var float_r := Rect2(mid.x - r.size.x * 0.28, r.position.y + 2.5, r.size.x * 0.56, r.size.y - 5.0)
			draw_rect(float_r, Color(0.9, 0.24, 0.2).lerp(Color.WHITE, flash * 0.5))
			draw_rect(Rect2(float_r.position.x, mid.y - 1.5, float_r.size.x, 3.0), Color(0.97, 0.95, 0.92))
			draw_rect(Rect2(float_r.position, Vector2(float_r.size.x, 1.5)), Color(1, 1, 1, 0.45))
			var blink: float = 0.5 + 0.5 * sin(t * 5.0 + r.position.x * 0.07)
			draw_circle(Vector2(mid.x, float_r.position.y + 0.5), 1.6, Color(1.0, 0.95, 0.55, 0.4 + 0.6 * blink))
			draw_line(Vector2(r.position.x + 2, r.end.y - 2.5), Vector2(r.end.x - 2, r.end.y - 2.5), Color(0.8, 0.92, 1.0, 0.5), 1.0)
		"bubble":
			# A BUBBLE BRICK: bubbles caught in it, wobbling
			for i in 3:
				var at: Vector2 = mid + Vector2(-7 + i * 7, sin(t * 4.0 + i * 1.7 + r.position.x) * 2.0)
				draw_arc(at, 2.2 + (i % 2) * 1.2, 0, TAU, 10, Color(0.85, 0.95, 1.0, 0.85), 1.1)
		"mimic":
			var shimmer: float = 0.5 + 0.5 * sin(t * 4.0 + r.position.x * 0.1)
			draw_arc(mid, 4.0, t * 4.0, t * 4.0 + PI * 1.4, 10, Color(1, 1, 1, 0.5 + 0.4 * shimmer), 1.4)
			draw_circle(mid + Vector2(5, 3), 1.2, Color(1, 1, 1, 0.7))
		"land":
			match k["land"]:
				"fire":
					draw_colored_polygon(PackedVector2Array([mid + Vector2(0, -5), mid + Vector2(3.5, 1.5), mid + Vector2(0, 5), mid + Vector2(-3.5, 1.5)]), ink)
				"ice":
					for a in 3:
						var d := Vector2.from_angle(a * PI / 3.0) * 4.5
						draw_line(mid - d, mid + d, ink, 1.3)
				"water":
					draw_arc(mid + Vector2(-3.5, 1), 3.5, PI, TAU, 8, ink, 1.2)
					draw_arc(mid + Vector2(3.5, 1), 3.5, 0, PI, 8, ink, 1.2)
				"wind":
					draw_line(mid + Vector2(-6, -2), mid + Vector2(4, -2), ink, 1.2)
					draw_line(mid + Vector2(-4, 2.5), mid + Vector2(6, 2.5), ink, 1.2)
				"earth":
					draw_rect(Rect2(mid - Vector2(3.5, 3.5), Vector2(7, 7)), ink, false, 1.2)
					if k["hp"] == 1:
						draw_polyline(PackedVector2Array([r.position + Vector2(5, 0), mid + Vector2(-2, 2), r.end - Vector2(6, 0)]), Color(0, 0, 0, 0.6), 1.3)
				"light":
					draw_circle(mid, 2.5, ink)
				"dark":
					draw_arc(mid, 4.5, 0, TAU, 14, ink, 1.2)


func _draw_boss() -> void:
	"""The boss's own drawing (its shots, its minions' shadows), and its health
	along the arena's top over its hall."""
	if boss == null:
		return
	var c: Color = COLOURS.get(boss.land, Color.WHITE)
	boss.draw(self, c, INK)
	var bar := Rect2(hall.position.x + 20, ARENA.position.y + 9, hall.size.x - 40, 6)
	draw_rect(bar.grow(2), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * float(boss.hp) / float(boss.most), bar.size.y)), c)
	_text(Vector2(hall.position.x + 10, hall.position.y + 14), str(boss.title), 12, INK)


func _draw_capsule(c: Dictionary) -> void:
	var info: Dictionary = BONUS[c["kind"]]
	var col: Color = COLOURS[info["land"]]
	var p: Vector2 = c["p"]
	p.x = clampf(p.x, ARENA.position.x + 42.0, ARENA.end.x - 42.0)
	var r := Rect2(p - Vector2(30, 11), Vector2(60, 22))
	draw_circle(p, 28.0, Color(col, 0.12 + 0.06 * sin(t * 8.0)))
	draw_rect(r, col.darkened(0.45))
	draw_rect(Rect2(r.position, Vector2(r.size.x, 9)), col)
	draw_circle(Vector2(r.position.x, p.y), 11.0, col.darkened(0.2))
	draw_circle(Vector2(r.end.x, p.y), 11.0, col.darkened(0.2))
	_draw_icon(c["kind"], p, Color(1, 1, 1), 1.0)


func _draw_icon(kind: String, p: Vector2, ink: Color, s: float) -> void:
	match kind:
		"multi":
			for i in 3:
				draw_circle(p + Vector2(-8 + i * 8, 0) * s, 3.2 * s, ink)
		"wide":
			draw_line(p + Vector2(-11, 0) * s, p + Vector2(11, 0) * s, ink, 2.5 * s)
			draw_colored_polygon(PackedVector2Array([p + Vector2(-14, 0) * s, p + Vector2(-8, -5) * s, p + Vector2(-8, 5) * s]), ink)
			draw_colored_polygon(PackedVector2Array([p + Vector2(14, 0) * s, p + Vector2(8, -5) * s, p + Vector2(8, 5) * s]), ink)
		"laser":
			for x in [-5.0, 5.0]:
				draw_line(p + Vector2(x, 7) * s, p + Vector2(x, -6) * s, ink, 2.5 * s)
				draw_circle(p + Vector2(x, -7) * s, 2.0 * s, ink)
		"shield":
			draw_arc(p + Vector2(0, 6) * s, 11.0 * s, PI * 1.15, PI * 1.85, 12, ink, 2.5 * s)
		"fire":
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -9) * s, p + Vector2(6, 2) * s, p + Vector2(0, 8) * s,
				p + Vector2(-6, 2) * s]), ink)
		"slow":
			for a in 3:
				var d := Vector2.from_angle(a * PI / 3.0) * 8.0 * s
				draw_line(p - d, p + d, ink, 2.0 * s)


func _draw_ball(b: Dictionary) -> void:
	var p: Vector2 = b["p"]
	var fire: bool = active.has("fire")
	var el: String = str(b.get("el", ""))
	var core: Color = Color(1.0, 0.75, 0.4) if fire else Color(0.92, 0.99, 1.0)
	var halo: Color = COLOURS["fire"] if fire else Color(0.7, 0.95, 1.0)
	if not fire and el != "":
		# CHARGED: the ball wears the land it carries
		halo = COLOURS[el]
		core = COLOURS[el].lerp(Color.WHITE, 0.55)
	draw_circle(p, BALL_R * 2.8, Color(halo, 0.10))
	draw_circle(p, BALL_R * 1.7, Color(halo, 0.24))
	draw_circle(p, BALL_R, core)
	draw_circle(p + Vector2(-2.3, -2.3), BALL_R * 0.35, Color(1, 1, 1))


func _draw_paddle() -> void:
	var half: float = paddle_w / 2.0
	var r := Rect2(paddle_x - half, PADDLE_Y - 7.0, paddle_w, 14.0)
	var glow: Color = Color(0.6, 0.6, 0.7) if stunned > 0.0 else GOLD
	for i in 4:
		draw_rect(r.grow(3.0 + i * 3.0), Color(glow, 0.09 - i * 0.018))
	draw_rect(r, Color(0.2, 0.18, 0.25))
	draw_circle(Vector2(r.position.x, PADDLE_Y), 7.0, Color(0.2, 0.18, 0.25))
	draw_circle(Vector2(r.end.x, PADDLE_Y), 7.0, Color(0.2, 0.18, 0.25))
	draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 5.0), glow)
	draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 2.0), Color(1, 0.95, 0.8))
	var core: float = 0.6 + 0.4 * sin(t * 6.0)
	draw_line(Vector2(r.position.x + 14, PADDLE_Y + 2), Vector2(r.end.x - 14, PADDLE_Y + 2), Color(0.55, 0.95, 1.0, core), 2.0)
	for x in [r.position.x, r.end.x]:
		draw_circle(Vector2(x, PADDLE_Y), 4.0, glow)
		draw_circle(Vector2(x, PADDLE_Y), 2.0, Color(1, 1, 1))
	if active.has("laser"):
		for side in [-1.0, 1.0]:
			var cx: float = paddle_x + side * (half - 12.0)
			draw_rect(Rect2(cx - 4, PADDLE_Y - 15, 8, 10), Color(0.75, 0.25, 0.12))
			draw_rect(Rect2(cx - 2, PADDLE_Y - 18, 4, 4), Color(1, 0.7, 0.4))
			if _muzzle > 0.0:
				draw_circle(Vector2(cx, PADDLE_Y - 20), 6.0 * _muzzle, Color(1, 0.85, 0.5, _muzzle))


func _path(from: Vector2, dir: Vector2, length: float) -> PackedVector2Array:
	"""Where a ball from `from` along `dir` goes: off the walls, to the first
	row of bricks it meets, and no further than the paddle's line."""
	var pts := PackedVector2Array([from])
	var p := from
	var d := dir
	var left := length
	for i in 4:
		var hit_t: float = INF
		var normal := Vector2.ZERO
		if d.x < 0.0:
			var tx: float = (ARENA.position.x + BALL_R - p.x) / d.x
			if tx < hit_t:
				hit_t = tx
				normal = Vector2.RIGHT
		if d.x > 0.0:
			var tx: float = (ARENA.end.x - BALL_R - p.x) / d.x
			if tx < hit_t:
				hit_t = tx
				normal = Vector2.LEFT
		if d.y > 0.0:
			var tp: float = (PADDLE_Y - 10.0 - p.y) / d.y
			if tp < hit_t:
				hit_t = tp
				normal = Vector2.ZERO
		if d.y < 0.0:
			var ty: float = (ARENA.position.y + BALL_R - p.y) / d.y
			for k in bricks:
				if k["hp"] <= 0 and _breaks(k):
					continue
				var r: Rect2 = (k["rect"] as Rect2).grow(BALL_R)
				var tb: float = (r.end.y - p.y) / d.y
				if tb > 0.0 and tb < ty:
					var x: float = p.x + d.x * tb
					if x >= r.position.x and x <= r.end.x:
						ty = tb
			if ty < hit_t:
				hit_t = ty
				normal = Vector2.DOWN
		if hit_t == INF or hit_t > left:
			pts.append(p + d * left)
			break
		p = p + d * hit_t
		pts.append(p)
		left -= hit_t
		if normal == Vector2.ZERO:
			break
		d = d.bounce(normal)
	return pts


func _draw_tracer(pts: PackedVector2Array, c: Color, aiming: bool, bolt: bool = false) -> void:
	"""A TRACER: the faint line, and bright streaks running along it."""
	if pts.size() < 2:
		return
	draw_polyline(pts, Color(c, 0.24 if bolt else 0.22), 2.0, true)
	var lens: Array = []
	var total: float = 0.0
	for i in pts.size() - 1:
		var l: float = pts[i].distance_to(pts[i + 1])
		lens.append(l)
		total += l
	if bolt:
		var seg := _segment_along(pts, lens, total - 34.0, total)
		if seg.size() >= 2:
			draw_polyline(seg, Color(c, 0.3), 9.0, true)
			draw_polyline(seg, Color(1, 0.9, 0.7), 3.0, true)
		return
	var spacing: float = 170.0
	var head: float = fmod(t * 1500.0, spacing)
	while head < total:
		var seg := _segment_along(pts, lens, head - 46.0, head)
		if seg.size() >= 2:
			var fade: float = 1.0 - head / total if aiming else 1.0
			draw_polyline(seg, Color(c, 0.25 * fade), 9.0, true)
			draw_polyline(seg, Color(c, 0.95 * fade), 3.5, true)
			draw_circle(seg[seg.size() - 1], 3.0, Color(1, 1, 1, fade))
		head += spacing


func _segment_along(pts: PackedVector2Array, lens: Array, a: float, b: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var at: float = 0.0
	a = maxf(a, 0.0)
	for i in lens.size():
		var l: float = lens[i]
		var s0: float = at
		var s1: float = at + l
		if l > 0.0 and s1 >= a and s0 <= b:
			var p0: Vector2 = pts[i].lerp(pts[i + 1], clampf((a - s0) / l, 0.0, 1.0))
			var p1: Vector2 = pts[i].lerp(pts[i + 1], clampf((b - s0) / l, 0.0, 1.0))
			if out.is_empty():
				out.append(p0)
			out.append(p1)
		at = s1
	return out


func _draw_trail(b: Dictionary) -> void:
	var trail: PackedVector2Array = b["trail"]
	if trail.size() < 3:
		return
	var c: Color = Color(1.0, 0.7, 0.4) if active.has("fire") else Color(0.8, 0.97, 1.0)
	if not active.has("fire") and str(b.get("el", "")) != "":
		c = COLOURS[str(b["el"])].lerp(Color.WHITE, 0.3)
	draw_polyline(trail, Color(c, 0.2), 2.0, true)
	var n: int = trail.size()
	var head := trail.slice(maxi(0, n - 9), n)
	draw_polyline(head, Color(c, 0.25), 10.0, true)
	draw_polyline(head, Color(c, 0.95), 4.0, true)
	for k in [[20, 15, 0.6], [34, 30, 0.35]]:
		var bit := trail.slice(maxi(0, n - int(k[0])), maxi(0, n - int(k[1])))
		if bit.size() >= 2:
			draw_polyline(bit, Color(c, float(k[2])), 3.0, true)


# ---------------------------------------------------------------- the frame --

func _panel(r: Rect2) -> void:
	draw_rect(Rect2(r.position + Vector2(3, 4), r.size), Color(0, 0, 0, 0.4))
	draw_rect(r, PANEL)
	draw_rect(r, EDGE, false, 2.0)
	draw_rect(r.grow(-4), Color(GOLD, 0.18), false, 1.0)


func _text(at: Vector2, s: String, size: int, c: Color, f: Font = null, centre: bool = false, alpha: float = 1.0,
		outline: int = 4) -> void:
	var use: Font = _bold if f == null else f
	if centre:
		at.x -= use.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x / 2.0
	if outline > 0:
		draw_string_outline(use, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, Color(0, 0, 0, 0.75 * alpha))
	draw_string(use, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, c)


static func thousands(n: int) -> String:
	var s: String = str(absi(n))
	var out: String = ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


func _draw_hud() -> void:
	_panel(Rect2(10, 8, 1260, 64))
	var kingdom: Dictionary = Maps.kingdom_of(map_index)
	var colour: Color = COLOURS.get(kingdom.get("land", "light"), GOLD)
	var n: int = Maps.in_kingdom(map_index) + 1
	draw_rect(Rect2(24, 20, 74, 40), Color(colour, 0.16))
	draw_rect(Rect2(24, 20, 74, 40), colour, false, 1.5)
	_text(Vector2(61, 36), "MAP", 11, Color(colour, 0.85), null, true)
	_text(Vector2(61, 56), "%d / %d" % [n, Maps.MAPS_A_KINGDOM], 17, colour, null, true)
	_text(Vector2(112, 38), str(Maps.MAPS[map_index]["name"]), 20, INK)
	_text(Vector2(112, 58), str(kingdom.get("name", "")), 12, Color(INK, 0.6), _font)
	_text(Vector2(392, 36), "SCORE", 11, Color(INK, 0.6), _font)
	_text(Vector2(392, 60), thousands(score), 22, INK)
	var coin := Vector2(540, 40)
	draw_circle(coin, 13.0, Color(0.55, 0.38, 0.05))
	draw_circle(coin, 11.0, GOLD)
	draw_circle(coin + Vector2(-3, -3), 4.0, Color(1, 0.95, 0.75))
	_text(Vector2(560, 50), thousands(gold_now()), 26, INK)
	var m := Rect2(680, 28, 220, 12)
	var fill: float = clampf(fmod(float(combo), 5.0) / 5.0, 0.0, 1.0) if combo > 0 else 0.0
	draw_rect(m, Color(0, 0, 0, 0.5))
	draw_rect(Rect2(m.position, Vector2(m.size.x * fill, m.size.y)), COLOURS["fire"].lerp(GOLD, fill))
	draw_rect(m, Color(1, 1, 1, 0.25), false, 1.0)
	for i in range(1, 5):
		var x: float = m.position.x + m.size.x * i / 5.0
		draw_line(Vector2(x, m.position.y), Vector2(x, m.end.y), Color(0, 0, 0, 0.5), 1.0)
	_text(Vector2(680, 62), "COMBO %d" % combo, 13, Color(INK, 0.75))
	var mult: float = _multiplier()
	_text(Vector2(912, 46), "x%s" % (str(mult) if mult != floorf(mult) else str(int(mult))), 24,
		COLOURS["fire"] if mult > 1.0 else Color(INK, 0.5))
	_text(Vector2(1000, 36), "LIVES", 11, Color(INK, 0.6), _font)
	for i in LIVES:
		var lr := Rect2(1000 + i * 40, 46, 30, 7)
		var on: bool = i < lives
		draw_rect(lr.grow(2), Color(GOLD, 0.15 if on else 0.04))
		draw_rect(lr, Color(0.2, 0.18, 0.25) if on else Color(0.1, 0.1, 0.12))
		draw_rect(Rect2(lr.position, Vector2(lr.size.x, 3)), GOLD if on else Color(0.3, 0.3, 0.32))


func _draw_left_panel() -> void:
	var r := Rect2(10, 86, 138, 620)
	_panel(r)
	_text(Vector2(79, 112), "BONUSES", 14, GOLD, null, true)
	draw_line(Vector2(24, 122), Vector2(134, 122), Color(GOLD, 0.3), 1.0)
	var y: float = 140.0
	if active.is_empty():
		_text(Vector2(79, 156), "none on", 12, Color(INK, 0.4), _font, true)
	for kind in BONUS_ORDER:
		if not active.has(kind):
			continue
		var info: Dictionary = BONUS[kind]
		var col: Color = COLOURS[info["land"]]
		var box := Rect2(20, y, 118, 46)
		draw_rect(box, Color(col, 0.12))
		draw_rect(box, Color(col, 0.6), false, 1.0)
		draw_circle(Vector2(40, y + 23), 14.0, col.darkened(0.4))
		_draw_icon(kind, Vector2(40, y + 23), Color(1, 1, 1), 0.8)
		_text(Vector2(60, y + 21), info["name"], 13, INK)
		var left: float = clampf(active[kind] / float(info["secs"]), 0.0, 1.0)
		draw_rect(Rect2(60, y + 30, 70, 5), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(60, y + 30, 70 * left, 5), col)
		y += 54.0
	# THE BALL'S CHARGE: what it carries, so a mix can be aimed
	var el: String = str(balls[0].get("el", "")) if not balls.is_empty() else ""
	_text(Vector2(79, 432), "THE BALL", 11, Color(INK, 0.5), _font, true)
	var chip := Rect2(24, 442, 110, 26)
	draw_rect(chip, Color(COLOURS.get(el, Color(0.3, 0.3, 0.35)), 0.2 if el != "" else 0.08))
	draw_rect(chip, Color(COLOURS.get(el, Color(0.5, 0.5, 0.55)), 0.8 if el != "" else 0.3), false, 1.0)
	draw_circle(chip.position + Vector2(14, 13), 6.0, COLOURS.get(el, Color(0.6, 0.62, 0.7)))
	_text(chip.position + Vector2(27, 18), el.to_upper() if el != "" else "plain", 12, INK if el != "" else Color(INK, 0.45),
		null if el != "" else _font)
	_text(Vector2(79, 486), "break a land to", 10, Color(INK, 0.4), _font, true)
	_text(Vector2(79, 498), "carry it; mix two", 10, Color(INK, 0.4), _font, true)
	_text(Vector2(79, 520), "CAN FALL", 11, Color(INK, 0.5), _font, true)
	var i: int = 0
	for kind in BONUS_ORDER:
		var p := Vector2(38 + (i % 3) * 40, 548 + floorf(i / 3.0) * 40)
		draw_circle(p, 15.0, COLOURS[BONUS[kind]["land"]].darkened(0.45))
		draw_arc(p, 15.0, 0, TAU, 20, Color(COLOURS[BONUS[kind]["land"]], 0.8), 1.2)
		_draw_icon(kind, p, Color(1, 1, 1, 0.9), 0.7)
		i += 1
	_text(Vector2(79, 650), "? bricks drop", 11, Color(INK, 0.5), _font, true)
	_text(Vector2(79, 666), "one for sure", 11, Color(INK, 0.5), _font, true)


func _draw_right_panel() -> void:
	var r := Rect2(1132, 86, 138, 620)
	_panel(r)
	if boss != null:
		_text(Vector2(1201, 112), "THE RULER" if boss.crowned else "THE GUARDIAN", 14, GOLD, null, true)
	else:
		_text(Vector2(1201, 112), "THE WALLS", 14, GOLD, null, true)
	draw_line(Vector2(1146, 122), Vector2(1256, 122), Color(GOLD, 0.3), 1.0)
	var done: float
	if boss != null:
		done = 1.0 - float(boss.hp) / float(boss.most)
	else:
		done = float(broken) / float(maxi(1, breakable))
	var c := Vector2(1201, 190)
	draw_arc(c, 44.0, 0, TAU, 48, Color(1, 1, 1, 0.1), 9.0)
	draw_arc(c, 44.0, -PI / 2.0, -PI / 2.0 + TAU * done, 48, GOLD, 9.0)
	_text(c + Vector2(0, 8), "%d%%" % int(round(done * 100.0)), 22, INK, null, true)
	_text(Vector2(1201, 256), "%d left" % maxi(0, breakable - broken) if boss == null else "%d to go" % int(boss.hp),
		12, Color(INK, 0.6), _font, true)
	# THIS STRETCH: the five maps the one now is among, its boss last.
	var kingdom: Dictionary = Maps.kingdom_of(map_index)
	var at: int = Maps.in_kingdom(map_index)
	var first: int = at - at % Maps.BOSS_EVERY
	_text(Vector2(1201, 300), "MAPS %d - %d" % [first + 1, first + Maps.BOSS_EVERY], 13, GOLD, null, true)
	draw_line(Vector2(1146, 310), Vector2(1256, 310), Color(GOLD, 0.3), 1.0)
	# ALL FIVE ALWAYS (the owner: "adding the 5th node ... will complete the
	# tier ladder"): a map not built yet is a dim slot under its number, the
	# stretch's boss under its name.
	var mine: Array = Maps.maps_of(str(kingdom.get("id", "light")))
	for j in Maps.BOSS_EVERY:
		var slot: int = first + j
		var made: bool = slot < mine.size()
		var idx: int = int(mine[slot]) if made else -1
		var p := Vector2(1162, 340 + j * 52)
		var boss_slot: bool = j == Maps.BOSS_EVERY - 1
		if j < Maps.BOSS_EVERY - 1:
			draw_line(p + Vector2(0, 12), p + Vector2(0, 40), Color(1, 1, 1, 0.55 if made and idx < map_index else 0.2), 2.0)
		var here: bool = made and idx == map_index
		var done_map: bool = made and (idx < map_index or (here and state == State.CLEARED))
		var col: Color = GOLD if done_map else (COLOURS["fire"] if here else Color(1, 1, 1, 0.25 if made else 0.14))
		var radius: float = 12.0 if boss_slot else 10.0
		if here:
			draw_circle(p, radius + 5.0 + 2.0 * sin(t * 4.0), Color(col, 0.2))
		draw_circle(p, radius, col.darkened(0.3) if not here else col)
		draw_arc(p, radius, 0, TAU, 20, col, 1.5)
		if boss_slot:
			for side in [-1.0, 1.0]:
				var top: Vector2 = p + Vector2(0, -radius - 1.0)
				draw_colored_polygon(PackedVector2Array([top + Vector2(side * 3, 2), top + Vector2(side * 8, -5), top + Vector2(side * 8, 3)]), col)
		if done_map:
			draw_line(p + Vector2(-4, 0), p + Vector2(-1, 4), Color(1, 1, 1), 2.0)
			draw_line(p + Vector2(-1, 4), p + Vector2(5, -4), Color(1, 1, 1), 2.0)
		var slot_name: String
		if made:
			slot_name = Maps.short_name(idx)
		elif boss_slot:
			@warning_ignore("integer_division")
			slot_name = str(Maps.BOSS_SLOTS[mini(first / Maps.BOSS_EVERY, Maps.BOSS_SLOTS.size() - 1)])
		else:
			slot_name = "Map %d" % (slot + 1)
		_text(p + Vector2(16, 5), slot_name, 12, INK if made and idx <= map_index else Color(INK, 0.4 if made else 0.28),
			_font if not here else null)
	_text(Vector2(1201, 650), "Best combo", 11, Color(INK, 0.5), _font, true)
	_text(Vector2(1201, 674), "%d" % best_combo, 18, INK, null, true)


# ---------------------------------------------------------------- the kingdoms --

func kingdom_spot(i: int) -> Vector2:
	"""Where kingdom `i` sits on the kingdom map: an arc, gentlest at the left."""
	var u: float = float(i) / 6.0
	return Vector2(170.0 + u * 940.0, 270.0 - sin(u * PI) * 90.0)


func map_spot(index: int) -> Vector2:
	"""Where a made map's node sits in the kingdom panel (MAP_PANEL): its
	kingdom's maps in rows of five, each row a stretch ending in its boss."""
	return slot_spot(Maps.in_kingdom(index))


func slot_spot(slot: int) -> Vector2:
	"""Where the `slot`th map of a kingdom (from 0) sits, made or not."""
	@warning_ignore("integer_division")
	var stretch: int = slot / Maps.BOSS_EVERY
	return MAP_PANEL.position + Vector2(150.0 + (slot % Maps.BOSS_EVERY) * NODE_GAP.x, 74.0 + stretch * NODE_GAP.y)


func kingdom_at(point: Vector2) -> int:
	"""The made kingdom whose crest is at `point` (the kingdom map), or -1."""
	for i in Maps.KINGDOMS.size():
		if bool(Maps.KINGDOMS[i]["made"]) and kingdom_spot(i).distance_to(point) <= 46.0:
			return i
	return -1


func open_map_in(kingdom: int) -> int:
	"""The map to pick in a kingdom: the next to clear there, or its last once
	all are cleared; -1 while none of it is open."""
	if kingdom < 0 or kingdom >= Maps.KINGDOMS.size():
		return -1
	var mine: Array = Maps.maps_of(str(Maps.KINGDOMS[kingdom]["id"]))
	if mine.is_empty() or not can_start_at(int(mine[0])):
		return -1
	return mini(furthest, int(mine[-1]))


func kingdom_index(index: int) -> int:
	"""Which kingdom (in KINGDOMS) map `index` is in."""
	var id: String = str(Maps.kingdom_of(index).get("id", ""))
	for i in Maps.KINGDOMS.size():
		if Maps.KINGDOMS[i]["id"] == id:
			return i
	return 0


func pick_at(point: Vector2) -> int:
	"""The made map whose node is at `point` (the kingdom map), or -1: only
	the maps of the kingdom on show."""
	var shown: String = str(Maps.kingdom_of(selected).get("id", ""))
	for i in Maps.made_count():
		if str(Maps.MAPS[i]["kingdom"]) == shown and map_spot(i).distance_to(point) <= 20.0:
			return i
	return -1


func _draw_kingdoms() -> void:
	_text(Vector2(640, 70), "CROWNFALL", 40, GOLD, null, true)
	_text(Vector2(640, 102), "Seven kingdoms of plague-stone. Seven crowns. Break the walls, heal the land.", 16, Color(INK, 0.75), _font, true)
	# the road between them
	var road := PackedVector2Array()
	for i in 7:
		road.append(kingdom_spot(i))
	draw_polyline(road, Color(GOLD, 0.25), 3.0, true)
	for i in Maps.KINGDOMS.size():
		var k: Dictionary = Maps.KINGDOMS[i]
		var p: Vector2 = kingdom_spot(i)
		var c: Color = COLOURS[k["land"]]
		var made: bool = bool(k["made"])
		var theirs: Array = Maps.maps_of(k["id"])
		var cleared_all: bool = made and not theirs.is_empty() and furthest > int(theirs[-1])
		# EVERY CREST GLOWS ITS LAND (the owner: "giving Wind (teal), Water
		# (blue), Ice (cyan), and Earth (amber/green) those same subtle inner
		# glows"): a kingdom still to come is a dim crest with its colour
		# inside; one that is made is the bright one.
		draw_circle(p, 46.0, Color(c, 0.10 if made else 0.06))
		if made:
			draw_circle(p, 34.0, c.darkened(0.55))
		else:
			draw_circle(p, 34.0, Color(0.1, 0.1, 0.12).lerp(c, 0.16))
			draw_circle(p, 24.0, Color(c, 0.10))
			draw_circle(p, 14.0, Color(c, 0.08))
		draw_arc(p, 34.0, 0, TAU, 40, Color(c, 0.9 if made else 0.45), 2.5)
		# a castle on each
		var base: Vector2 = p + Vector2(0, 14)
		var castle := PackedVector2Array([base + Vector2(-20, 0), base + Vector2(-20, -22), base + Vector2(-14, -22), base + Vector2(-14, -16),
			base + Vector2(-6, -16), base + Vector2(-6, -30), base + Vector2(6, -30), base + Vector2(6, -16), base + Vector2(14, -16),
			base + Vector2(14, -22), base + Vector2(20, -22), base + Vector2(20, 0)])
		draw_colored_polygon(castle, Color(c, 0.85) if made else Color(0.3, 0.3, 0.33).lerp(c, 0.22))
		# the crown over it, gold while its ruler wears it
		var top: Vector2 = p + Vector2(0, -48)
		var crown := PackedVector2Array([top + Vector2(-12, 5), top + Vector2(-12, -5), top + Vector2(-6, 0), top + Vector2(0, -8),
			top + Vector2(6, 0), top + Vector2(12, -5), top + Vector2(12, 5)])
		draw_colored_polygon(crown, Color(0.35, 0.35, 0.37) if cleared_all else GOLD)
		_text(p + Vector2(0, 60), str(k["name"]).replace("The Kingdom of ", ""), 16, INK if made else Color(INK, 0.45), null, true)
		if not made:
			_text(p + Vector2(0, 78), "coming", 12, Color(INK, 0.35), _font, true)
		elif cleared_all:
			_text(p + Vector2(0, 78), "crown taken", 12, Color(0.6, 0.95, 0.55), _font, true)
	# THE PICKED MAP'S KINGDOM: its maps in five stretches of five, every
	# fifth a boss (horns over it; the citadel's a crown). A map not made yet
	# is a dim slot.
	var kingdom: Dictionary = Maps.kingdom_of(selected)
	var colour: Color = COLOURS.get(kingdom.get("land", "light"), GOLD)
	_panel(MAP_PANEL)
	_text(Vector2(MAP_PANEL.get_center().x, MAP_PANEL.position.y + 28), str(kingdom.get("name", "")).to_upper(), 15, GOLD, null, true)
	draw_line(MAP_PANEL.position + Vector2(20, 38), Vector2(MAP_PANEL.end.x - 20, MAP_PANEL.position.y + 38), Color(GOLD, 0.3), 1.0)
	var mine: Array = Maps.maps_of(str(kingdom.get("id", "")))
	var each: Array = pays.get("maps", []) if pays.get("maps") is Array else []
	for stretch in Maps.STRETCHES:
		var left: Vector2 = slot_spot(stretch * Maps.BOSS_EVERY)
		_text(Vector2(MAP_PANEL.position.x + 24, left.y + 5), "%d - %d" % [stretch * Maps.BOSS_EVERY + 1, (stretch + 1) * Maps.BOSS_EVERY],
			12, Color(INK, 0.5), _font)
		draw_line(left, slot_spot(stretch * Maps.BOSS_EVERY + Maps.BOSS_EVERY - 1), Color(GOLD, 0.18), 2.0)
	for slot in Maps.MAPS_A_KINGDOM:
		var p: Vector2 = slot_spot(slot)
		var made: bool = slot < mine.size()
		var i: int = int(mine[slot]) if made else -1
		var big: bool = (slot + 1) % Maps.BOSS_EVERY == 0
		var radius: float = 16.0 if big else 12.0
		if not made:
			draw_circle(p, radius, Color(0.1, 0.1, 0.12).lerp(colour, 0.06))
			draw_arc(p, radius, 0, TAU, 24, Color(colour, 0.18), 1.2)
			_text(p + Vector2(0, 4), str(slot + 1), 11, Color(INK, 0.22), _font, true)
			continue
		var open: bool = can_start_at(i)
		var done: bool = i < furthest
		var col: Color = GOLD if done else (colour if open else Color(1, 1, 1, 0.25))
		if i == selected:
			draw_circle(p, radius + 6.0 + 2.0 * sin(t * 4.0), Color(col, 0.25))
		if big:
			var crown: bool = Maps.MAPS[i].get("boss") is Dictionary and bool(Maps.MAPS[i]["boss"].get("crown", false))
			var top: Vector2 = p + Vector2(0, -radius - 2.0)
			if crown:
				draw_colored_polygon(PackedVector2Array([top + Vector2(-9, 3), top + Vector2(-9, -4), top + Vector2(-4, 0),
					top + Vector2(0, -6), top + Vector2(4, 0), top + Vector2(9, -4), top + Vector2(9, 3)]), col)
			else:
				for side in [-1.0, 1.0]:
					draw_colored_polygon(PackedVector2Array([top + Vector2(side * 4, 3), top + Vector2(side * 11, -7),
						top + Vector2(side * 10, 4)]), col)
		draw_circle(p, radius, col.darkened(0.35) if open else Color(0.15, 0.15, 0.17))
		draw_arc(p, radius, 0, TAU, 28, col, 1.8)
		if done:
			draw_line(p + Vector2(-5, 0), p + Vector2(-1, 5), Color(1, 1, 1), 2.2)
			draw_line(p + Vector2(-1, 5), p + Vector2(6, -5), Color(1, 1, 1), 2.2)
		else:
			_text(p + Vector2(0, 5), str(slot + 1), 13, INK if open else Color(INK, 0.4), null, true)
	var pick: Dictionary = Maps.MAPS[selected]
	var gold_words: String = ("   ·   %s gold" % thousands(int(each[selected]))) if selected < each.size() else ""
	_text(Vector2(640, 658), "MAP %d   ·   %s%s" % [Maps.in_kingdom(selected) + 1, str(pick["name"]).to_upper(), gold_words],
		16, INK, null, true)
	_text(Vector2(640, 678), str(pick["line"]), 13, Color(INK, 0.7), _font, true)
	_text(Vector2(640, 696), str(kingdom.get("trick", "")), 12, Color(COLOURS["light"], 0.8), _font, true)
	if map_hint != "":
		var hint: String = map_hint % str(pick["name"]) if map_hint.contains("%s") else map_hint
		_text(Vector2(640, 714), hint, 12, Color(INK, 0.45 + 0.15 * sin(t * 2.5)), _font, true)
