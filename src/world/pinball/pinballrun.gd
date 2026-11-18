# pinballrun.gd - THE BEHOLDER'S TABLE (0.167.0): a pinball table in three
# floors - the town, the big field, the Beholder's lair - built in 3D in its
# own world (pinballscreen.gd shows it over the town). It was grown in the
# owner's sandbox (zz/pinball5..11) and moved in whole: the physics, the
# table, his art on it, the heroes and monsters, the lands' effects.
#
# THE TABLE (the owner, after a photograph of Stern's Venom: "a guide on
# bottom left and right of board switches and levers i do not want the
# layout to be too easy"): on each floor a fan of shots across the top, the
# slingshots, inlanes and outlanes with their guides at the foot, rollover
# lanes over the jets (the flippers move the lit lane), orbits with one-way
# gates. The town: the Tower orbit and its spinner, the left ramp round the
# Portal, the Bone Wall, the Crowned's keep (a Siege), the climb, the right
# ramp round the Caged Spirit, the right orbit to the Well, L-V-L. The
# field: the two eyes, the ramps, the climb, R-U-N, the high wire off a
# little flipper. The lair: the Beholder, the eyestalks, the Spiral.
#
# PLAYED: the screen calls press(side, down) for the flippers (every flipper
# of that side, on every floor) and plunge(down) for the plunger - held, it
# pulls; let go, the ball goes as hard as it was pulled. Three balls (and
# any extra won); the last one lost ends the game (`over`, game_over).
# `attract` plays it by itself, as the sandbox did.
#
# A FRAME: the table steps at FPS whatever the screen's rate (an
# accumulator), STEPS times a step. The camera only slides up and down the
# table, smoothly, with slack round the ball (the owner, of the sandbox's
# film: "looks a little wobbly"), and nothing here is blended by physics
# interpolation (moved in _process, it would be drawn between ticks).
# Drawing: the floor that never changes painted once, what moves on a floor
# only while it is on screen, the still meshes joined (the sandbox's
# pinball9 numbers: 1,631 draws a frame to 666).
extends Node

signal game_over

const W := 1240.0
const H := 3600.0
const CX := 600.0
const BALL_R := 10.0
const GRAVITY := 1050.0
const MAX_SPEED := 2100.0
const FPS := 60.0
const STEPS := 8
const BALLS := 3
const PULL_SECONDS := 0.9
const LAUNCH_LEAST := 1250.0
const LAUNCH_MOST := 2150.0
const FLIP_SPEED := 20.0
const FLIP_LEN := 140.0
const REST := 0.49
const UP := -0.47
const WALL_BOUNCE := 0.4
const FLIP_BOUNCE := 0.25
const BUMPER_KICK := 560.0
const SLING_KICK := 450.0
const EYE_R := 60.0
const EYE_HP := 2
const SAVE_SECONDS := 8.0
# a ball within STILL_REACH of one spot for STILL_SECONDS is nudged, up to
# NUDGE_UP up and NUDGE_SIDE to either side
const STILL_REACH := 24.0
const STILL_SECONDS := 1.5
const NUDGE_UP := 640.0
const NUDGE_SIDE := 260.0
# a ride on a level stretch never goes slower than this (px/s)
const RIDE_CRAWL := 90.0
# PHONES (0.168.0): a phone's browser draws the table lighter - no shadows,
# no glow, the fill lights out (the ambient raised to stand in for them),
# the 3D drawn at PHONE_3D_SCALE of the picture (the panel and words stay
# sharp), each floor's moving layer and each eye painted at PHONE_PAINT of
# their size. The table plays exactly the same.
const PHONE_3D_SCALE := 0.75
const PHONE_PAINT := 0.5
const PHONE_AMBIENT := 0.95
# COOLER ON A PHONE (0.168.4): the owner, "phone started to overheat on
# minigame". A phone's browser draws with the Compatibility renderer, where
# every light a mesh is in draws that mesh again - so there the table has no
# lights of its own (bumpers, eyes, the Beholder, the portal, the tower; the
# raised ambient and the meshes' own glow stand in). And its panel, each
# floor's moving layer and each eye are painted every PHONE_EVERY frames, the
# moving layers' and eyes' pictures drawn only then (UPDATE_ONCE), not every
# frame. (pinballscreen.gd also stops drawing the HUD under the table.)
const PHONE_EVERY := 2
# each side wall's bounce-back: from BOUNCE_FROM (x, height over the foot)
# to the outlane's outer wall at BOUNCE_TO_Y over the foot - from 0.168.3
# the wall's whole lower part (it began at x 190, 404 over the foot)
const BOUNCE_FROM := Vector2(100.0, 486.0)
const BOUNCE_TO_Y := 385.0
# where a kick throws the ball (px/s; x toward the middle): the bounce-back,
# and the low kickback in the outlane (it was straight up its lane, and a
# ball came back down the same wall: 9 of 29 drained that side)
const BOUNCE_AIM := Vector2(270.0, -1120.0)
const LOW_KICK_AIM := Vector2(80.0, -1900.0)
# THE PRONGS (0.168.4): from the corner where the catcher meets the outlane's
# outer wall, a post sticks in over the outlane's mouth to PRONG_TIP (x,
# height over the foot) - the owner: "we need to add prongs on both of these
# corners its to easy for the ball to fall down". The mouth was 65 px from
# that corner to the inlane's post (three balls wide); past the prong's tip
# it is 35, room for one ball and a half. A plain player's drains fell by
# about half with any prong tried (290, 297, 304) - see CLAUDE.md
const PRONG_TIP := Vector2(300.0, 378.0)
const KICK_CREAM := Color(0.95, 0.9, 0.8)
# the plunger's bar, beside the panel (its lane is under it)
const LAUNCH_BOX := Rect2(818, 450, 26, 222)
# the camera never looks lower than this far above its floor's foot
const CAM_FOOT := 290.0
# THE VIEW (0.168.4): the owner, "i cannot see all of the right side of the
# map we need to zoom out on the board just a little bit". At 52 degrees and
# 1.55 to the side the right wall and the plunger's lane sat under the LAUNCH
# bar; 56, moved over to 2.1, shows the right outlane, its KICK and the wall
# clear of it, and the left side still in
const CAM_FOV := 56.0
const CAM_SIDE := 2.1
# it looks CAM_LEAD seconds along the ball's way (no faster than LEAD_MOST
# px/s), and never lets the ball more than CAM_DOWN below its line or CAM_UP
# above (a still camera shows 240 below and 900 above)
const CAM_LEAD := 0.15
const LEAD_MOST := 1800.0
const CAM_DOWN := 170.0
const CAM_UP := 650.0
const CAM_FAST := 6.0
const FALL_FAST := 1500.0
# THE UPDRAFT (0.168.3; the wind land's effect, a gale before): its lift, as
# a share of gravity, and the fall speed (px/s) a ball is eased toward in it,
# UPDRAFT_EASE of the way a second
const UPDRAFT_LIFT := 0.45
const UPDRAFT_FALL := 700.0
const UPDRAFT_EASE := 3.0
const S := 0.01
const FLOORS := [
	{"name": "THE TOWN SQUARE", "short": "TOWN", "y0": 2400.0, "yb": 3600.0, "h": 0.0, "opens": 0},
	{"name": "THE BIG FIELD", "short": "FIELD", "y0": 1200.0, "yb": 2300.0, "h": 0.6, "opens": 1200000},
	{"name": "THE BEHOLDER'S LAIR", "short": "LAIR", "y0": 0.0, "yb": 1100.0, "h": 1.2, "opens": 5000000},
]
const COLOURS := {
	"dark": Color(0.427, 0.157, 0.851), "fire": Color(1.0, 0.416, 0.122), "earth": Color(0.631, 0.384, 0.027),
	"ice": Color(0.404, 0.91, 0.976), "water": Color(0.231, 0.51, 0.965), "wind": Color(0.655, 0.953, 0.816),
	"light": Color(0.992, 0.902, 0.541),
}
const ORDER := ["light", "wind", "water", "ice", "earth", "fire", "dark"]
const RANKS := ["WANDERER", "SQUIRE", "KNIGHT", "WARDEN", "CROWN-BREAKER"]
# Crownfall's reactions, the same two lands each
const MIX := {"steam": ["fire", "ice"], "firestorm": ["fire", "wind"], "glacier": ["water", "ice"],
	"storm": ["water", "wind"], "magma": ["earth", "fire"], "blizzard": ["ice", "wind"], "eclipse": ["light", "dark"]}
# The four heroes' words, the shot that lights each, and its power
const WORDS := ["MAGE", "WARR", "TANK", "HEAL"]
const POWER := {"MAGE": "METEOR SHOWER", "WARR": "WHIRLWIND", "TANK": "SHIELD", "HEAL": "BALL SAVE"}
const HERO := {"MAGE": Color(0.55, 0.45, 1.0), "WARR": Color(1.0, 0.42, 0.3), "TANK": Color(0.45, 0.8, 1.0),
	"HEAL": Color(0.55, 1.0, 0.6)}
const GOLD := Color(1.0, 0.82, 0.38)
const INK := Color(0.93, 0.95, 1.0)
const EDGE := Color(0.45, 0.34, 0.2)
const PORTAL := Vector2(300, 2768)
const PORTAL_RING := Vector2(300, 2700)
const LAIR := Vector2(600, 610)
const BEHOLDER := Vector2(600, 380)
const BEHOLDER_R := 100.0
const SHIELD_Y := 3556.0
# THE MAGE'S TOWER: the orbit's ball climbs round it
const TOWER := Vector2(150, 2560)
const TOWER_R := 62.0
const TOWER_TOP := 1.4
# THE LANDS' EFFECTS: one at a time, on the whole table
const EFFECT_FIRST := 6.0
# LIGHTER THAN WATER (0.168.4): the owner, "with the water i want to pretend
# the ball is lighter then water". Under the tide the water lifts the ball by
# TIDE_BUOY times gravity when it is all under (so more than it weighs), by
# as much of that as is under at the surface, and takes TIDE_DRAG of its
# speed a second: it rises, rides the waves bobbing, and comes down with the
# water as the tide goes out. (It was lifted by 0.55 of gravity, and sank.)
const TIDE_BUOY := 1.6
const TIDE_DRAG := 4.0
# the waves on the tide: how high, how close, how fast (the picture's own)
const WAVE_HIGH := 7.0
const WAVE_EVERY := 0.03
const WAVE_SPEED := 4.0
const EFFECT_GAP := 8.4
const EFFECT_LEN := 6.4
const WARN := 1.5
# the order the lands come in when the ball carries none new (the demo's:
# the blackout third, so it is seen in play)
const EFFECT_ORDER := ["wind", "earth", "dark", "ice", "fire", "water", "light"]
const EFFECT := {"fire": "LAVA VENTS", "water": "HIGH TIDE", "ice": "DEEP FROST", "wind": "UPDRAFT", "earth": "QUAKE",
	"light": "DAZZLE", "dark": "BLACKOUT"}
const EFFECT_SUB := {"fire": "THE FIRE LAND  ·  VENTS THROW THE BALL", "water": "THE WATER LAND  ·  THE BALL FLOATS",
	"ice": "THE ICE LAND  ·  THE BALL SKATES", "wind": "THE WIND LAND  ·  THE BALL HANGS",
	"earth": "THE EARTH LAND  ·  BREAK THE ROCKS", "light": "THE LIGHT LAND  ·  EVERY SCORE x2",
	"dark": "THE DARK LAND  ·  MONSTERS x3"}
const VENTS := [[Vector2(300, 2900), Vector2(600, 2800), Vector2(900, 2920)],
	[Vector2(450, 1640), Vector2(750, 1640), Vector2(600, 1720)], [Vector2(250, 600), Vector2(950, 600), Vector2(600, 190)]]
const ROCK_SPOTS := [[Vector2(480, 2860), Vector2(720, 2960), Vector2(380, 3070), Vector2(820, 3080), Vector2(640, 2860),
	Vector2(260, 2910)], [Vector2(450, 1560), Vector2(750, 1560), Vector2(600, 1640), Vector2(360, 1880), Vector2(840, 1880),
	Vector2(600, 1300)], [Vector2(300, 420), Vector2(900, 420), Vector2(520, 700), Vector2(680, 700), Vector2(250, 650),
	Vector2(950, 650)]]
# THE SHOTS, counted
const SHOTS := ["TOWER", "UP2", "XL", "XR", "XL2", "XR2", "UP3", "SPIRAL", "WIRE", "CAGE"]
const SHOT_NAME := {"TOWER": "TOWER", "UP2": "CLIMB", "XL": "LEFT RAMP", "XR": "RIGHT RAMP", "XL2": "FIELD L",
	"XR2": "FIELD R", "UP3": "CLIMB 2", "SPIRAL": "SPIRAL", "WIRE": "HIGH WIRE", "CAGE": "CAGED SPIRIT"}
# THE NEW MECHANICS: where they stand
const SPIN_AT := Vector2(75, 3005)
const SPIN_HALF := 50.0
const WELL_EVERY := 16
const SKEL_Y := 2770.0
const SKEL_X := [428.0, 456.0, 484.0, 512.0]
const SKEL_W := 25.0
const MAGNET := Vector2(600, 3112)
const CAGE_X := 900.0
const CAGE_TOP := 2640.0
const CAGE_REST := 2800.0
const CAGE_MOUTH := 2822.0
const SPIRIT_C := Color(0.6, 0.9, 1.0)
const WELL := Vector2(1058, 2640)
const KEEP := Vector2(600, 2645)
const KEEP_BACK := 2600.0
const BRIDGE_Y := 2690.0
# THE TOWN AS A REAL TABLE: the left ramp (the right is its mirror), the
# climb, the top lanes, the right orbit
const XL_PTS := [Vector2(400, 2860), Vector2(392, 2750), Vector2(365, 2655), Vector2(305, 2590), Vector2(245, 2605),
	Vector2(215, 2680), Vector2(212, 2800), Vector2(222, 2950), Vector2(245, 3100), Vector2(285, 3230), Vector2(325, 3300),
	Vector2(350, 3335)]
const XL_HIGH := [0.0, 0.14, 0.28, 0.4, 0.44, 0.42, 0.36, 0.28, 0.2, 0.12, 0.06, 0.03]
const LANES_X := [760.0, 830.0, 900.0, 970.0]
const LANE_WORD := "LVL"
# THE TOP LANES, a set on the town and one on the field: the floor, the
# four guides, the line a ball rolls through, the word they spell
const LANE_SETS := [{"fl": 0, "xs": LANES_X, "y": 2470.0, "top": 2426.0, "word": "LVL", "done": "LEVEL UP"},
	{"fl": 1, "xs": [515.0, 570.0, 630.0, 685.0], "y": 1268.0, "top": 1226.0, "word": "RUN", "done": "THE RUNES ARE READ"}]
const STALK_Y := 640.0
const STALKS := [[300.0, 330.0, 360.0], [814.0, 844.0, 874.0]]
const ORBIT_X := 1110.0
const GATE_HP := 3
const SIEGE_SECONDS := 25.0
const MINI_PIVOT := Vector2(60, 1640)
const WIRE_PTS := [Vector2(120, 1520), Vector2(130, 1420), Vector2(170, 1330), Vector2(260, 1270), Vector2(420, 1235),
	Vector2(600, 1225), Vector2(780, 1235), Vector2(940, 1270), Vector2(1030, 1330), Vector2(1080, 1440),
	Vector2(1090, 1600), Vector2(1060, 1780), Vector2(990, 1910), Vector2(900, 2010), Vector2(850, 2045)]
const WIRE_HIGH := [0.62, 0.82, 1.02, 1.2, 1.34, 1.38, 1.38, 1.34, 1.26, 1.16, 1.02, 0.88, 0.76, 0.67, 0.62]
# THE OWNER'S ART: sheet, frame, rows, how big on the table, feet below centre
const MOB_ART := {
	"skeleton": {"tex": "res://art/enemy/skeleton.png", "size": 64, "n": 6, "right": 64, "left": 320, "ps": 0.023, "feet": 16.0},
	"fire": {"tex": "res://art/enemy/firesprite.png", "size": 128, "n": 7, "right": 128, "left": 256, "ps": 0.016, "feet": 21.0},
	"storm": {"tex": "res://art/enemy/electricsprite.png", "size": 128, "n": 7, "right": 128, "left": 256, "ps": 0.017, "feet": 28.0},
	"crowned": {"tex": "res://art/enemy/boss.png", "size": 64, "n": 9, "right": 64, "left": 64, "ps": 0.03, "feet": 22.0},
}
const MOB_NAME := {"skeleton": "SKELETON", "fire": "FIRE SPRITE", "storm": "STORM SPRITE", "crowned": "THE CROWNED"}
const MOB_COLOUR := {"skeleton": Color(0.95, 0.92, 0.8), "fire": Color(1.0, 0.5, 0.15), "storm": Color(0.45, 0.85, 1.0),
	"crowned": Color(1.0, 0.4, 0.4)}
const HERO_ART := {
	"MAGE": {"tex": "res://art/maincharacter/mage.png", "size": 64, "rows": [[1344, 6]], "ps": 0.024, "feet": 21.0,
		"crop": Rect2(3, 3, 52, 52)},
	"WARR": {"tex": "res://art/maincharacter/warrior.png", "size": 64, "rows": [[320, 7], [384, 7], [512, 7], [448, 7]],
		"ps": 0.026, "feet": 29.0, "crop": Rect2(10, 11, 52, 52)},
	"TANK": {"tex": "res://art/maincharacter/tank.png", "size": 128, "rows": [[0, 6]], "ps": 0.02, "feet": 21.0,
		"crop": Rect2(40, 39, 50, 50)},
	"HEAL": {"tex": "res://art/maincharacter/2.png", "size": 64, "rows": [[0, 8]], "ps": 0.022, "feet": 16.0,
		"crop": Rect2(4, 6, 44, 44)},
}
# THE PACK'S ITEMS (Clockwork Raven Studios, Caio Carlos): whole cells, unchanged
const EYE_ORDER := ["fire", "ice", "earth", "water", "wind", "light"]
const COIN := {"skeleton": "coppercoin", "fire": "silvercoin", "storm": "goldcoin", "crowned": "goldpile"}
const HERO_NAME := {"MAGE": "THE MAGE", "WARR": "THE WARRIOR", "TANK": "THE TANK", "HEAL": "THE HEALER"}
const HERO_DOES := {"MAGE": "rains meteors from her tower", "WARR": "throws spinning axes round the ball",
	"TANK": "stands on the drain, lights the kickbacks", "HEAL": "saves the ball, lights an extra"}

var rng := RandomNumberGenerator.new()
var vrng := RandomNumberGenerator.new()
var segs: Array = []
var seg_bands: Array = []
var bumpers: Array = []
var eyes: Array = []
var targets: Array = []
var balls: Array = []
var flippers: Array = []
var ramps: Array = []
var ramp_at: Dictionary = {}
var sparks: Array = []
var popups: Array = []
var banners: Array = []
var meteors: Array = []
var lit: Dictionary = {}
var words: Dictionary = {}
var open_floors: Array = [true, false, false]
var score: int = 0
var shown: float = 0.0
var ball_no: int = 1
var multiplier: int = 1
var multiball: bool = false
var kickbacks: Array = [false, false]
var holds: Dictionary = {}
var shield_t: float = 0.0
var whirl_t: float = 0.0
var save_until: float = SAVE_SECONDS
var slime_gone: float = 0.0
var beholder: Dictionary = {"p": BEHOLDER, "flash": 0.0, "open": false, "hp": 0}
var beam_a: float = PI / 2.0
var beam_w: float = 0.0
var extra_lit: bool = false
var shake: float = 0.0
var t: float = 0.0
var frame: int = 0
var launched_at: float = -100.0
var pull: float = 0.0
var pulling: float = 0.0
var plunger_seg: Dictionary = {}
var stats: Dictionary = {}
var rank: int = 0
var done: Dictionary = {}
var quiet: bool = false
var mobs: Array = []
var horde: Array = []
var horde_at: float = -100.0
var slain: int = 0
var rocks: Array = []
var effect: Dictionary = {}
var next_effect: float = EFFECT_FIRST
var effects_shown: Array = []
var tower_ball: Dictionary = {}
var to_add: Array = []
var tries: Dictionary = {}
var makes: Dictionary = {}
var cards: Array = []
var heals: Array = []
var mage_until: float = -100.0
var eye_drops: Array = []
var synergy: int = 0
var cues: Array = []
var glow_mats: Array = []
var stripe_mats: Array = []
var loot: Array = []
var spinner: Dictionary = {}
var lanes: Array = [[false, false, false], [false, false, false]]
var lane_x: int = 1
var spins_to_well: int = 0
var skels: Array = []
var skels_back: float = -1.0
var skel_level: int = 0
var magnet_lit: bool = false
var spirit: Dictionary = {}
var well: Dictionary = {}
var gate: Dictionary = {}
var siege: Dictionary = {}
var _font: Font
var seed_now: int = 0
var headless: bool = false
var attract: bool = false
# drawn as for a phone (on_phone(), or the suite's pretend_phone)
var light: bool = false
static var pretend_phone: bool = false
var paused: bool = false
# BUILT WHEN ASKED (0.168.3): the screen's loading cover builds the 3D table
# a step of its own (build_world_now()), so its bar moves and the first draw
# - the slow part on a phone - happens behind it
var build_later: bool = false
var over: bool = false
var extra_balls: int = 0
var controls_hint: String = "Z / LEFT  ·  M / RIGHT  ·  HOLD SPACE"
# the game's gold so far, or PRACTICE (0.168.0): the screen's to say, drawn
# on the title row under Leave
var purse_text: String = ""
var purse_colour: Color = GOLD
var cam_y: float = 3200.0
var cam_h: float = 0.0
var _acc: float = 0.0
var _pressed: Dictionary = {}
var _plunging: bool = false
var star_at := PackedVector2Array()
var star_sp := PackedFloat32Array()
var star_r := PackedFloat32Array()
var star_a := PackedFloat32Array()
var _bold: FontVariation


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_font = ThemeDB.fallback_font
	_bold = FontVariation.new()
	_bold.base_font = _font
	_bold.variation_embolden = 0.9
	if seed_now == 0:
		seed_now = randi() % 1000000 + 1
	quiet = headless
	light = on_phone()
	_reset(seed_now)
	if not headless and not build_later:
		_build_world()


func build_world_now() -> void:
	"""The 3D table, built and placed as the first frame will show it."""
	if headless:
		return
	if world == null:
		_build_world()
	_follow(true)
	_sync_world()


static func on_phone() -> bool:
	"""A phone, or a tablet, in a browser or not (the Endless's own test)."""
	return pretend_phone or OS.has_feature("web_android") or OS.has_feature("web_ios") \
		or OS.has_feature("android") or OS.has_feature("ios")


func _process(delta: float) -> void:
	if over or paused:
		return
	_acc = minf(_acc + delta, 4.0 / FPS)
	var stepped: bool = false
	while _acc >= 1.0 / FPS:
		_acc -= 1.0 / FPS
		_advance()
		stepped = true
	if cam3 != null:
		_follow(false, delta)
		if stepped:
			_sync_world()


func step_frames(n: int) -> void:
	"""The table's own clock moved on n steps, drawn or not (the suite)."""
	for i in n:
		if over:
			return
		_advance()


func press(side: int, down: bool) -> void:
	"""A flipper button: -1 left, 1 right. Every flipper of that side, on
	every floor, answers it; pressing moves the lit top lanes (the levers)."""
	var key: String = "left" if side < 0 else "right"
	if down and not bool(_pressed.get(key, false)):
		for fl in 3:
			_lane_change(1.0 if side < 0 else -1.0, fl)
	_pressed[key] = down


func plunge(down: bool) -> void:
	"""The plunger: held it pulls, let go it launches."""
	_plunging = down


func pressed_side(f: Dictionary) -> bool:
	return bool(_pressed.get("left" if float(f["side"]) > 0.0 else "right", false))


# =============================================================================
# THE TABLE
# =============================================================================

func floor_of(y: float) -> int:
	if y >= 2400.0:
		return 0
	if y >= 1200.0:
		return 1
	return 2


func height_at(y: float) -> float:
	return float(FLOORS[floor_of(y)]["h"])


func _mx(x: float) -> float:
	return 2.0 * CX - x


func _wall(a: Vector2, b: Vector2, kind: String = "wall") -> Dictionary:
	var s := {"a": a, "b": b, "r": 3.0, "kind": kind}
	segs.append(s)
	return s


func _chain(pts: Array, kind: String = "wall") -> void:
	for i in pts.size() - 1:
		_wall(pts[i], pts[i + 1], kind)


func _arc(c: Vector2, rx: float, ry: float, a0: float, a1: float, n: int) -> Array:
	var out: Array = []
	for i in n + 1:
		var ang: float = lerpf(a0, a1, float(i) / n)
		out.append(c + Vector2(cos(ang) * rx, sin(ang) * ry))
	return out


func _base(yb: float, fl: int, outlanes: bool, top: float) -> void:
	"""A floor's foot: funnels, (outlanes,) inlanes, slingshots, flippers."""
	for side in [1.0, -1.0]:
		var m := func(x: float) -> float: return x if side > 0.0 else _mx(x)
		if outlanes:
			# THE BOUNCE-BACKS (0.168.2): the owner, "ball hits bumpers on right
			# then just falls down to the lose a ball area the bounce backs are
			# too low on the board" - each side wall slid straight into its
			# outlane's mouth (93 px, the inlane beside it 42), so a ball down a
			# side was gone: off the right bumpers, untouched, 45 of 80. The
			# wall's foot, just over the outlane, is that side's KICKBACK now,
			# moved up the board: while its KICK is lit a ball coming down it
			# is thrown back up the table and the light is spent (the old one
			# low in the outlane shares it); dark, it rolls in. Always on, it
			# saved nearly everything: a plain player's games went from about
			# 130 s to 400 s, his median score from 10M to 77M.
			# HIGHER (0.168.3): "the gutter catchers are still to low to
			# actually bounce the ball back into the game". It is the wall's
			# whole lower part now, from BOUNCE_FROM; lit, any touch kicks (a
			# roll down it pressed too lightly for a slingshot's 110 px/s), and
			# the ball is thrown at BOUNCE_AIM, up and toward the middle.
			_chain([Vector2(m.call(20.0), top), Vector2(m.call(BOUNCE_FROM.x), yb - BOUNCE_FROM.y)])
			var bounce: Dictionary = _wall(Vector2(m.call(BOUNCE_FROM.x), yb - BOUNCE_FROM.y),
				Vector2(m.call(270.0), yb - BOUNCE_TO_Y), "kick")
			bounce["flash"] = 0.0
			bounce["r"] = 4.0
			bounce["bounce"] = true
			bounce["kb"] = 0 if side > 0.0 else 1
			_wall(Vector2(m.call(270.0), yb - BOUNCE_TO_Y), Vector2(m.call(270.0), yb))
			_wall(Vector2(m.call(270.0), yb - BOUNCE_TO_Y), Vector2(m.call(PRONG_TIP.x), yb - PRONG_TIP.y))
			_chain([Vector2(m.call(330.0), yb - 360), Vector2(m.call(330.0), yb - 250), Vector2(m.call(444.0), yb - 146)])
		else:
			_chain([Vector2(m.call(20.0), top), Vector2(m.call(326.0), yb - 336), Vector2(m.call(330.0), yb - 250),
				Vector2(m.call(444.0), yb - 146)])
		var a := Vector2(m.call(372.0), yb - 350)
		var b := Vector2(m.call(372.0), yb - 262)
		var c := Vector2(m.call(430.0), yb - 215)
		var k: Dictionary = _wall(a, c, "kick")
		k["flash"] = 0.0
		k["r"] = 4.0
		_wall(a, b)
		_wall(b, c)
		flippers.append({"pivot": Vector2(m.call(450.0), yb - 140), "side": side, "len": FLIP_LEN, "a": REST, "adot": 0.0,
			"hold": 0.0, "cool": 0.0, "aim": 0.5, "late": 0.0, "floor": fl})


func _ramp_box(pts: Array) -> Rect2:
	var box := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		box = box.expand(p)
	return box.grow(30.0)


func _ramp(what_name: String, pts: Array, high: Array, lock: int = 0, pull_k: float = 0.85) -> void:
	var r := {"name": what_name, "pts": pts, "high": high, "mouth": pts[0], "lock": lock, "pull": pull_k, "flash": 0.0,
		"box": _ramp_box(pts)}
	if lock > 0:
		r["gate"] = _wall((pts[0] as Vector2) + Vector2(-42, -10), (pts[0] as Vector2) + Vector2(42, -10), "lock")
		r["gate"]["floor"] = lock
	ramps.append(r)
	ramp_at[what_name] = r


func _mirror(pts: Array) -> Array:
	var out: Array = []
	for p in pts:
		out.append(Vector2(_mx((p as Vector2).x), (p as Vector2).y))
	return out


func _reset(s: int) -> void:
	rng.seed = s
	vrng.seed = 7
	for list in [segs, bumpers, eyes, targets, balls, flippers, ramps, sparks, popups, banners, meteors, mobs, horde, rocks,
			to_add, cards, heals, effects_shown]:
		list.clear()
	effect = {}
	next_effect = EFFECT_FIRST
	tower_ball = {}
	tries.clear()
	makes.clear()
	slain = 0
	horde_at = -100.0
	mage_until = -100.0
	eye_drops.clear()
	synergy = 0
	cues.clear()
	loot.clear()
	ramp_at.clear()
	lit.clear()
	done.clear()
	holds.clear()
	words = {"MAGE": 0, "WARR": 0, "TANK": 0, "HEAL": 0}
	open_floors = [true, false, false]
	score = 0
	shown = 0.0
	ball_no = 1
	multiplier = 1
	multiball = false
	kickbacks = [true, true]
	shield_t = 0.0
	whirl_t = 0.0
	save_until = SAVE_SECONDS
	slime_gone = 0.0
	beholder = {"p": BEHOLDER, "flash": 0.0, "open": false, "hp": 0}
	extra_lit = false
	rank = 0
	t = 0.0
	frame = 0
	stats = {"bumpers": 0, "eyes": 0, "jackpots": 0, "multiball_at": -1.0, "up2": 0, "up3": 0, "down": 0,
		"orbits": 0, "xr": 0, "xl": 0, "cross2": 0, "spiral": 0, "lair": 0, "portal": 0, "warp": 0, "targets": 0,
		"lost": 0, "saved": 0, "nudges": 0, "kickbacks": 0, "reactions": 0, "words": 0, "word_at": -1.0,
		"slime": 0, "beholder": 0, "extra": 0, "floor2_first": -1.0, "floor3_first": -1.0, "meteor": 0, "tower": 0,
		"locks": 0, "free": 0, "slain": 0, "horde": 0, "horde_kills": 0, "rocks": 0, "vents": 0, "effects": 0, "heroes": 0, "eye_drops": 0, "synergy": 0, "synergy_kills": 0, "dark_at": -1.0}
	# ---- the ground floor: the plunger's lane up the right ----
	var y0: float = 2400.0
	var yb: float = 3600.0
	_chain(_arc(Vector2(220, y0 + 200), 200, 200, PI, PI * 1.5, 10), "outer")
	_wall(Vector2(220, y0), Vector2(1020, y0), "outer")
	_chain(_arc(Vector2(1020, y0 + 200), 200, 200, PI * 1.5, TAU, 10), "outer")
	_wall(Vector2(20, y0 + 200), Vector2(20, yb - 560), "outer")
	_wall(Vector2(1220, y0 + 200), Vector2(1220, yb), "outer")
	_wall(Vector2(1180, yb), Vector2(1180, y0 + 260))
	_wall(Vector2(1180, y0 + 260), Vector2(1218, y0 + 192), "gate")
	_wall(Vector2(1180, yb - 18), Vector2(1220, yb - 18))
	plunger_seg = segs[segs.size() - 1]
	_base(yb, 0, true, yb - 560)
	# THE ORBITS: the tower lane's guide on the left, the right orbit's on
	# the right (its foot turns a ball coming down back onto the field);
	# the shield over the drain
	_wall(Vector2(110, y0 + 330), Vector2(110, y0 + 500))
	_wall(Vector2(ORBIT_X, y0 + 300), Vector2(ORBIT_X, y0 + 500))
	# the orbit's gate: up through it, but a ball coming back down rolls off
	# it onto the field, not down the side into the outlane
	_wall(Vector2(1178, y0 + 530), Vector2(ORBIT_X + 2.0, y0 + 590), "gate")
	_wall(Vector2(520, SHIELD_Y), Vector2(680, SHIELD_Y), "shield")
	# THE TOP LANES: three, between four short guides
	for ls in LANE_SETS:
		for x in ls["xs"]:
			_wall(Vector2(x, float(ls["top"])), Vector2(x, float(ls["top"]) + 66.0))
	lanes = [[false, false, false], [false, false, false]]
	lane_x = 1
	# THE JETS, under the lanes
	for b in [["fire", 785, 165], ["water", 880, 128], ["wind", 965, 186]]:
		bumpers.append({"p": Vector2(b[1], y0 + b[2]), "r": 30.0, "el": b[0], "flash": 0.0, "cool": 0.0})
	var els: Array = ["light", "dark", "earth", "ice"]
	for i in 4:
		targets.append({"rect": Rect2(112, y0 + 340 + i * 46, 12, 34), "el": els[i], "down": false, "flash": 0.0, "bank": 0})
	targets.append({"rect": Rect2(ORBIT_X - 14.0, y0 + 380, 12, 40), "el": "extra", "down": false, "flash": 0.0, "bank": -1})
	# THE RAMPS: up from the middle, round a loop, down a side to the inlane
	_ramp("XL", XL_PTS, XL_HIGH)
	_ramp("XR", _mirror(XL_PTS), XL_HIGH)
	for nm in ["XL", "XR"]:
		ramp_at[nm]["mw"] = 40.0
		ramp_at[nm]["mh"] = 20.0
	# THE MAGE'S TOWER: up the orbit lane, then two and a quarter turns round
	# a tower; short of the top it rolls back down
	var tw: Array = [Vector2(65, 2990), Vector2(65, 2860), Vector2(66, 2740), Vector2(74, 2640)]
	var hw: Array = [0.0, 0.03, 0.08, 0.15]
	for i in 37:
		var ang: float = PI + i * TAU / 16.0
		tw.append(TOWER + Vector2(cos(ang), sin(ang)) * TOWER_R)
		hw.append(lerpf(0.22, TOWER_TOP, i / 36.0))
	_ramp("TOWER", tw, hw, 0, 0.85)
	ramp_at["TOWER"]["climb_from"] = 4
	ramp_at["TOWER"]["climb_k"] = 2.6
	ramp_at["TOWER"]["mw"] = 44.0
	ramp_at["TOWER"]["mh"] = 50.0
	ramp_at["TOWER"]["vmin"] = 200.0
	# THE CLIMB: right of the keep, up past the lanes to the field
	_ramp("UP2", [Vector2(690, 2800), Vector2(694, 2660), Vector2(700, 2520), Vector2(700, 2420), Vector2(700, 2340),
		Vector2(660, 2240), Vector2(580, 2140), Vector2(480, 2060)],
		[0.0, 0.3, 0.6, 0.82, 0.9, 0.78, 0.68, 0.62], 1, 0.5)
	# ---- the second floor: the two eyes ----
	y0 = 1200.0
	yb = 2300.0
	_chain(_arc(Vector2(220, y0 + 200), 200, 200, PI, PI * 1.5, 10), "outer")
	_wall(Vector2(220, y0), Vector2(980, y0), "outer")
	_chain(_arc(Vector2(980, y0 + 200), 200, 200, PI * 1.5, TAU, 10), "outer")
	_wall(Vector2(20, y0 + 200), Vector2(20, yb - 700), "outer")
	_wall(Vector2(1180, y0 + 200), Vector2(1180, yb - 700), "outer")
	_base(yb, 1, false, yb - 700)
	# the field's right orbit, with its gate, round to the lanes
	# its guide ends 40 px over the gate's lower end's line (0.168.0): it
	# ended level with it, 22 px from the gate, and a ball coming down the
	# orbit stuck between them
	_wall(Vector2(1100, y0 + 220), Vector2(1100, y0 + 400))
	_wall(Vector2(1178, y0 + 410), Vector2(1102, y0 + 462), "gate")
	eyes.append({"p": Vector2(300, 1670), "hp": EYE_HP, "flash": 0.0, "cool": 0.0, "open": false})
	eyes.append({"p": Vector2(900, 1670), "hp": EYE_HP, "flash": 0.0, "cool": 0.0, "open": false})
	for b in [["light", 520, 1390], ["dark", 680, 1390], ["ice", 550, 1500], ["fire", 650, 1500]]:
		bumpers.append({"p": Vector2(b[1], b[2]), "r": 30.0, "el": b[0], "flash": 0.0, "cool": 0.0})
	_ramp("XL2", [Vector2(430, 1760), Vector2(420, 1640), Vector2(360, 1500), Vector2(330, 1400), Vector2(420, 1305),
		Vector2(780, 1305), Vector2(890, 1400), Vector2(1000, 1580), Vector2(1000, 1800), Vector2(920, 1960), Vector2(850, 2040)],
		[0.6, 0.7, 0.82, 0.9, 0.95, 0.95, 0.9, 0.82, 0.72, 0.65, 0.62])
	_ramp("XR2", [Vector2(770, 1760), Vector2(780, 1640), Vector2(840, 1500), Vector2(870, 1400), Vector2(780, 1345),
		Vector2(420, 1345), Vector2(310, 1400), Vector2(200, 1580), Vector2(200, 1800), Vector2(280, 1960), Vector2(350, 2040)],
		[0.6, 0.66, 0.74, 0.78, 0.8, 0.8, 0.78, 0.74, 0.68, 0.63, 0.61])
	_ramp("UP3", [Vector2(600, 1790), Vector2(600, 1620), Vector2(600, 1440), Vector2(600, 1260),
		Vector2(600, 1140), Vector2(600, 1000), Vector2(560, 900), Vector2(520, 850)],
		[0.6, 0.85, 1.02, 1.15, 1.3, 1.36, 1.28, 1.22], 2, 0.5)
	# ---- the top floor: the Beholder ----
	yb = 1100.0
	_chain(_arc(Vector2(600, 400), 580, 380, PI, TAU, 40), "outer")
	_base(yb, 2, false, 400.0)
	for b in [["wind", 430, 280], ["water", 770, 280], ["earth", 420, 520], ["light", 780, 520]]:
		bumpers.append({"p": Vector2(b[1], b[2]), "r": 30.0, "el": b[0], "flash": 0.0, "cool": 0.0})
	# THE EYESTALKS: two banks of three drop targets, either side of the lair
	for bi in 2:
		for x in STALKS[bi]:
			targets.append({"rect": Rect2(float(x), STALK_Y, 26, 12), "el": "dark", "down": false, "flash": 0.0, "bank": 2 + bi})
	_ramp("SPIRAL", [Vector2(400, 760), Vector2(330, 640), Vector2(280, 440), Vector2(320, 240), Vector2(460, 130),
		Vector2(740, 130), Vector2(880, 240), Vector2(920, 440), Vector2(870, 640), Vector2(850, 780), Vector2(850, 850)],
		[1.2, 1.32, 1.45, 1.55, 1.62, 1.62, 1.55, 1.45, 1.34, 1.26, 1.22])
	_reset_new()
	# THE MONSTERS: the owner's own, walking the floors
	mobs.append(_mob("skeleton", 0, "line", Vector2(330, 2955), Vector2(560, 2955), 0.55, 0.0))
	mobs.append(_mob("fire", 0, "line", Vector2(640, 2965), Vector2(870, 2965), 0.7, 1.5))
	mobs.append(_mob("skeleton", 1, "line", Vector2(420, 1880), Vector2(780, 1880), 0.5, 0.7))
	mobs.append(_mob("storm", 1, "orbit", Vector2(600, 1445), Vector2(190, 100), 0.6, 0.0))
	mobs.append(_mob("storm", 2, "orbit", BEHOLDER, Vector2(300, 185), 0.45, 0.0))
	mobs.append(_mob("storm", 2, "orbit", BEHOLDER, Vector2(300, 185), 0.45, PI))
	_band_walls()
	_new_ball()


const BAND := 100.0


func _band_walls() -> void:
	"""THE WALLS BY HEIGHT: each band of BAND px lists the walls a ball in it
	could touch (the same test _hit_walls makes, with room), in their order -
	so a ball asks a dozen walls, not all of them, and meets them as before."""
	seg_bands.clear()
	for i in int(H / BAND) + 2:
		seg_bands.append([])
	for i in segs.size():
		var sg: Dictionary = segs[i]
		var lo: float = minf((sg["a"] as Vector2).y, (sg["b"] as Vector2).y) - 30.0
		var hi: float = maxf((sg["a"] as Vector2).y, (sg["b"] as Vector2).y) + 30.0
		if sg == plunger_seg:
			lo -= 20.0
			hi += 40.0
		for band in range(maxi(0, int(floor(lo / BAND))), mini(seg_bands.size() - 1, int(floor(hi / BAND))) + 1):
			(seg_bands[band] as Array).append(i)


func _mob(kind: String, fl: int, path: String, a: Vector2, b: Vector2, speed: float, phase: float) -> Dictionary:
	var hp: int = 2 if kind == "skeleton" else 1
	return {"kind": kind, "fl": fl, "path": path, "a": a, "b": b, "speed": speed, "phase": phase, "hp": hp, "max": hp,
		"r": 24.0 if kind == "skeleton" else 22.0, "back": -100.0, "died": -100.0, "hurt": -100.0, "dpos": a,
		"worth": {"skeleton": 150000, "fire": 200000, "storm": 250000}[kind]}


func _mob_at(m: Dictionary) -> Vector2:
	var ang: float = t * float(m["speed"]) + float(m["phase"])
	if m["path"] == "line":
		return (m["a"] as Vector2).lerp(m["b"], 0.5 - 0.5 * cos(ang))
	var r: Vector2 = m["b"]
	return (m["a"] as Vector2) + Vector2(cos(ang) * r.x, sin(ang) * r.y)


func _mob_right(m: Dictionary) -> bool:
	var ang: float = t * float(m["speed"]) + float(m["phase"])
	if m["path"] == "line":
		return sin(ang) * ((m["b"] as Vector2).x - (m["a"] as Vector2).x) > 0.0
	return -sin(ang) > 0.0


func _alive(m: Dictionary) -> bool:
	return t >= float(m["back"])


func _new_ball() -> void:
	balls.append({"p": Vector2(1200, 3571), "v": Vector2.ZERO, "held": true, "trail": [], "tint": INK, "slow": 0.0,
		"land": "", "lane": 0.0})
	pulling = 0.0


# =============================================================================
# A FRAME
# =============================================================================

func _advance() -> void:
	frame += 1
	t = frame / FPS
	var dt: float = 1.0 / (FPS * STEPS)
	for i in STEPS:
		_plunger(dt)
		for f in flippers:
			if attract:
				_think(f)
			elif pressed_side(f):
				f["hold"] = 1.0
				f["late"] = 0.0
			else:
				f["hold"] = 0.0
			_move_flipper(f, dt)
		beam_w = 0.5 * 0.8 * cos(t * 0.5)
		beam_a = PI / 2.0 + 0.8 * sin(t * 0.5)
		for ball in balls:
			_step_ball(ball, dt)
			var trail: Array = ball["trail"]
			trail.push_front(ball["p"])
			if trail.size() > 20:
				trail.pop_back()
		_balls_meet()
		_spirit_step(dt)
		_magnet_step(dt)
		_holds(dt)
		_locks()
		_drains()
	_opens()
	_settle_targets()
	_new_frame()
	_land_effects()
	_march()
	if synergy > 0 and not _synergy_on():
		synergy = 0
	var k: float = 1.0 / FPS
	shake = maxf(0.0, shake - k)
	shield_t = maxf(0.0, shield_t - k)
	whirl_t = maxf(0.0, whirl_t - k)
	slime_gone = maxf(0.0, slime_gone - k)
	beholder["flash"] = maxf(0.0, float(beholder["flash"]) - k * 2.5)
	shown = minf(float(score), shown + maxf(1.0, (score - shown) * 0.18))
	for b in bumpers:
		b["flash"] = maxf(0.0, b["flash"] - k * 4.0)
		b["cool"] = maxf(0.0, b["cool"] - k)
	for e in eyes:
		e["flash"] = maxf(0.0, e["flash"] - k * 2.5)
		e["cool"] = maxf(0.0, e["cool"] - k)
	for r in ramps:
		r["flash"] = maxf(0.0, r["flash"] - k * 1.5)
	for r in rocks:
		r["flash"] = maxf(0.0, float(r["flash"]) - k)
	for s in segs:
		if s["kind"] == "kick":
			s["flash"] = maxf(0.0, s["flash"] - k * 4.0)
	# the mage's meteors land, one by one
	for m in meteors:
		if not m.get("hit", false) and t >= float(m["at"]):
			m["hit"] = true
			var at: Vector2 = _meteor_end(m)
			stats["meteor"] += 1
			if m.has("mob") and _alive(m["mob"]):
				_wound(m["mob"], 9, at, true)
			elif m.has("b"):
				bumpers[m["b"]]["flash"] = 1.0
			# the blast: slimes and rocks near it go too
			for h in horde:
				if _horde_on(h) and _horde_at(h).distance_to(at) < 80.0:
					_splat(h, true)
			for r in rocks:
				if not r["gone"] and t >= float(r["land"]) and (r["p"] as Vector2).distance_to(at) < 80.0:
					_break_rock(r, true)
			_gain(50000, at + Vector2(0, -50), COLOURS["fire"])
			_burst(at, COLOURS["fire"], 22)
			shake = maxf(shake, 0.3)
	meteors = meteors.filter(func(m: Dictionary) -> bool: return t < float(m["at"]) + 0.6)
	for lo in loot:
		lo["p"] += lo["v"] * k
		lo["v"] *= 0.93
		lo["vh"] = float(lo["vh"]) - 9.0 * k
		lo["h"] = float(lo["h"]) + float(lo["vh"]) * k
		if float(lo["h"]) < 0.0:
			lo["h"] = 0.0
			lo["vh"] = -float(lo["vh"]) * 0.45
		lo["life"] = float(lo["life"]) - k
		if float(lo["life"]) <= 0.0:
			_burst(lo["p"], GOLD, 6)
	loot = loot.filter(func(lo: Dictionary) -> bool: return float(lo["life"]) > 0.0)
	for sp in sparks:
		sp["p"] += sp["v"] * k
		sp["lift"] = float(sp.get("lift", 0.0)) + float(sp.get("rise", 0.0)) * k
		sp["v"] *= 0.9
		sp["life"] -= k
	sparks = sparks.filter(func(sp: Dictionary) -> bool: return sp["life"] > 0.0)
	for pp in popups:
		pp["life"] -= k
	popups = popups.filter(func(pp: Dictionary) -> bool: return pp["life"] > 0.0)
	if not banners.is_empty():
		banners[0]["life"] -= k
		if banners[0]["life"] <= 0.0:
			banners.pop_front()
	for fl in [1, 2]:
		if stats["floor%d_first" % (fl + 1)] < 0.0:
			for ball in balls:
				if not ball.has("ride") and not ball["held"] and floor_of((ball["p"] as Vector2).y) == fl:
					stats["floor%d_first" % (fl + 1)] = t


func _opens() -> void:
	for fl in [1, 2]:
		if not open_floors[fl] and score >= int(FLOORS[fl]["opens"]):
			open_floors[fl] = true
			_banner("%s IS OPEN" % FLOORS[fl]["name"], "SHOOT THE CLIMB", GOLD)
			_mission("open%d" % (fl + 1))
			for r in ramps:
				if r["lock"] == fl:
					r["flash"] = 1.0
					_burst(r["mouth"], GOLD, 24)


func _plunger(dt: float) -> void:
	for ball in balls:
		if not ball["held"]:
			continue
		if attract:
			pulling += dt
			pull = clampf((pulling - 0.4) / 0.9, 0.0, 1.0)
		elif _plunging:
			pulling += dt
			pull = clampf(pulling / PULL_SECONDS, 0.0, 1.0)
		ball["p"] = Vector2(1200, 3571 + pull * 18.0)
		var go: bool = pulling >= 1.45 if attract else (not _plunging and pulling > 0.0)
		if go:
			ball["held"] = false
			ball["v"] = Vector2(0, -(rng.randf_range(2000.0, 2100.0) if attract else lerpf(LAUNCH_LEAST, LAUNCH_MOST, pull)))
			launched_at = t
			save_until = maxf(save_until, t + SAVE_SECONDS)
			pulling = 0.0
	if balls.all(func(b: Dictionary) -> bool: return not b["held"]):
		pull = maxf(0.0, pull - dt * 8.0)
	var y: float = 3582.0 + pull * 18.0
	plunger_seg["a"] = Vector2(1180, y)
	plunger_seg["b"] = Vector2(1220, y)


func _step_ball(ball: Dictionary, dt: float) -> void:
	if ball.has("wait"):
		ball["wait"] = float(ball["wait"]) - dt
		if float(ball["wait"]) > 0.0:
			return
		ball.erase("wait")
	if ball["held"] or ball.has("sunk"):
		return
	if ball.has("ride"):
		_ride(ball, dt)
		return
	var v: Vector2 = ball["v"]
	v.y += GRAVITY * dt
	if v.length() > MAX_SPEED:
		v = v.normalized() * MAX_SPEED
	ball["v"] = v
	ball["p"] += v * dt
	ball["lane"] = maxf(0.0, float(ball["lane"]) - dt)
	_hit_walls(ball)
	_hit_bumpers(ball)
	_hit_targets(ball)
	_hit_eyes(ball)
	_hit_beholder(ball)
	_hit_slime(ball)
	_hit_mobs(ball)
	_hit_horde(ball)
	_hit_rocks(ball)
	_axes(ball)
	_feel(ball, dt)
	_hit_flippers(ball)
	_beam(ball, dt)
	if _new_parts(ball, dt):
		return
	_sensors(ball)
	# STUCK, NUDGED (0.168.0): a ball that has stayed within STILL_REACH of
	# one spot for STILL_SECONDS is nudged out - lying still, or rattling in
	# a corner (one did in the Field's right orbit, for ever, at a speed
	# that never read as slow). Never a ball cradled on a flipper held up:
	# that one is the player's to hold. Nor one afloat on the tide (0.168.4).
	var here: Vector2 = ball["p"]
	if ball.has("sunk") or ball.has("ride") or _cradled(here) or _afloat(here) \
			or here.distance_to(ball.get("anchor", here)) > STILL_REACH:
		ball["slow"] = 0.0
		ball["anchor"] = here
	else:
		ball["slow"] += dt
		if ball["slow"] > STILL_SECONDS:
			ball["slow"] = 0.0
			stats["nudges"] += 1
			if here.x > 1180.0 and here.y > 3400.0 and not attract:
				ball["held"] = true
				ball["v"] = Vector2.ZERO
				pulling = 0.0
			elif here.x > 1180.0 and here.y > 2400.0:
				ball["v"] = Vector2(0, -2000)
			else:
				ball["v"] = Vector2(rng.randf_range(-NUDGE_SIDE, NUDGE_SIDE), -rng.randf_range(NUDGE_UP * 0.75, NUDGE_UP))


func _cradled(at: Vector2) -> bool:
	"""Whether a ball at `at` lies on a flipper that is held up."""
	for f in flippers:
		if float(f["hold"]) > 0.5 and at.distance_to(f["pivot"]) < float(f["len"]) + BALL_R * 2.0:
			return true
	return false


func _sensors(ball: Dictionary) -> void:
	var p: Vector2 = ball["p"]
	var v: Vector2 = ball["v"]
	var fl: int = floor_of(p.y)
	# a ramp's mouth, going up fast enough (and its floor open)
	for r in ramps:
		var m: Vector2 = r["mouth"]
		if absf(p.x - m.x) < float(r.get("mw", 38.0)) and absf(p.y - m.y) < float(r.get("mh", 18.0)) \
				and v.y < -float(r.get("vmin", 300.0)) and (r["lock"] == 0 or (open_floors[r["lock"]] and not multiball)) \
				and v.normalized().dot(((r["pts"][1] as Vector2) - m).normalized()) > 0.55:
			ball["ride"] = r["name"]
			ball["s"] = 0.0
			ball["rv"] = v.length() * 0.92
			tries[r["name"]] = int(tries.get(r["name"], 0)) + 1
			return
	# the scoops: the Portal on the ground floor, the lair on the top
	for hole in [["portal", PORTAL], ["lair", LAIR]]:
		if p.distance_to(hole[1]) < 24.0 and v.length() < 1700.0 and not holds.has(hole[0]):
			_sink(ball, hole[0], hole[1])
			return
	# a chute down: off the foot of an upper floor - but in a multiball the
	# ball is out, so the balls never part floors
	if fl > 0 and p.y > float(FLOORS[fl]["yb"]) - 4.0 and multiball:
		ball["out"] = true
		if not quiet:
			popups.append({"p": p + Vector2(0, -60), "text": "OUT", "life": 0.9, "c": Color(0.95, 0.4, 0.35)})
		return
	if fl > 0 and p.y > float(FLOORS[fl]["yb"]) - 4.0:
		var cliff: float = float(FLOORS[fl - 1]["y0"])
		var land_y: float = cliff + 130.0
		var x: float = clampf(p.x, 300.0, 900.0)
		ball["ride"] = "CHUTE"
		ball["chute"] = {"pts": [p, Vector2(x, cliff - 8.0), Vector2(x, cliff + 14.0), Vector2(x, land_y)],
			"high": [float(FLOORS[fl]["h"]), float(FLOORS[fl]["h"]), float(FLOORS[fl - 1]["h"]) + 0.02, float(FLOORS[fl - 1]["h"]) + 0.02]}
		ball["s"] = 0.0
		ball["rv"] = 500.0
		stats["down"] += 1
		_banner("DOWN A FLOOR", "", INK)
		return
	# the inlanes, going down: HEAL
	var yb: float = FLOORS[fl]["yb"]
	if v.y > 0.0 and p.y > yb - 300.0 and p.y < yb - 260.0 and float(ball["lane"]) <= 0.0:
		if (p.x > 330.0 and p.x < 372.0) or (p.x > 828.0 and p.x < 870.0):
			ball["lane"] = 0.8
			_gain(20000, p + Vector2(0, -30), HERO["HEAL"])
			_letter("HEAL", p)
	# the kickbacks, in the ground floor's outlanes
	if fl == 0 and p.y > 3480.0 and v.y > 0.0:
		for side in 2:
			var inside: bool = (p.x > 270.0 and p.x < 330.0) if side == 0 else (p.x > 870.0 and p.x < 930.0)
			if inside and kickbacks[side]:
				kickbacks[side] = false
				stats["kickbacks"] += 1
				var inward: float = 1.0 if side == 0 else -1.0
				ball["v"] = Vector2(inward * LOW_KICK_AIM.x + rng.randf_range(-20.0, 20.0), LOW_KICK_AIM.y)
				_banner("KICKBACK", "", COLOURS["fire"])
				_burst(p, COLOURS["fire"], 14)


func _sink(ball: Dictionary, what_name: String, at: Vector2) -> void:
	ball["sunk"] = what_name
	ball["p"] = at
	ball["v"] = Vector2.ZERO
	holds[what_name] = {"t": 1.3, "ball": ball}
	shake = 0.25
	_burst(at, COLOURS["dark"].lightened(0.4), 26)
	if what_name == "lair":
		stats["lair"] += 1
		_drop_eye(at)
		if done.has("crowned") or (open_floors[2] and done.has("eyes")):
			_gain(1000000, at + Vector2(0, -60), GOLD)
			_banner("THE BOSS AWAITS", "1,000,000", Color(1.0, 0.4, 0.4))
		else:
			_gain(500000, at + Vector2(0, -60), COLOURS["dark"].lightened(0.4))
			_banner("THE BEHOLDER'S LAIR", "500,000", COLOURS["dark"].lightened(0.4))
		_mission("lair")
	else:
		stats["portal"] += 1
		_gain(100000, at + Vector2(0, -60), COLOURS["dark"].lightened(0.4))


func _holds(dt: float) -> void:
	for what_name in holds.keys():
		var h: Dictionary = holds[what_name]
		h["t"] = float(h["t"]) - dt
		if h["t"] > 0.0:
			continue
		var ball: Dictionary = h["ball"]
		holds.erase(what_name)
		if not ball.has("sunk"):
			continue
		ball.erase("sunk")
		if what_name == "portal":
			if open_floors[1] and not multiball and rng.randf() < 0.6:
				# THE WARP: out of the Portal and onto the second floor
				stats["warp"] += 1
				ball["p"] = Vector2(600, 1880)
				ball["v"] = Vector2(rng.randf_range(-200.0, 200.0), 300.0)
				ball["trail"] = []
				_banner("WARP!", "TO THE SECOND FLOOR", COLOURS["dark"].lightened(0.45))
				_burst(PORTAL, COLOURS["dark"].lightened(0.4), 30)
				_burst(ball["p"], COLOURS["dark"].lightened(0.4), 30)
				continue
			_mystery(ball)
			ball["p"] = PORTAL + Vector2(-20, 30)
			ball["v"] = Vector2(-380.0, 420.0)
		elif what_name == "lair":
			ball["p"] = LAIR + Vector2(0, 30)
			ball["v"] = Vector2(rng.randf_range(-260.0, 260.0), 520.0)
		else:
			_release(what_name, ball)


func _mystery(_ball: Dictionary) -> void:
	var pick: int = rng.randi() % 4
	match pick:
		0:
			_gain(500000, PORTAL + Vector2(0, -60), GOLD)
			_banner("MYSTERY", "500,000", GOLD)
		1:
			kickbacks = [true, true]
			_banner("MYSTERY", "KICKBACKS LIT", GOLD)
		2:
			var w: String = WORDS[rng.randi() % 4]
			_banner("MYSTERY", "A LETTER OF %s" % w, GOLD)
			_letter(w, PORTAL)
		_:
			save_until = t + 12.0
			_banner("MYSTERY", "BALL SAVE", GOLD)


func _ride(ball: Dictionary, dt: float) -> void:
	"""ON A RAMP OR DOWN A CHUTE: the ball runs along a path, slowing as it
	climbs and speeding as it falls; short of a ramp's top it rolls back."""
	var what_name: String = ball["ride"]
	var path: Dictionary = ball["chute"] if what_name == "CHUTE" else ramp_at[what_name]
	var pts: Array = path["pts"]
	var lens: Array = []
	var total: float = 0.0
	for i in pts.size() - 1:
		var l: float = (pts[i] as Vector2).distance_to(pts[i + 1])
		lens.append(l)
		total += l
	var s: float = ball["s"]
	var i: int = _seg_at(lens, s)
	var a: Vector2 = pts[i]
	var b: Vector2 = pts[i + 1]
	var slope: float = (b.y - a.y) / maxf(1.0, lens[i])
	if what_name == "CHUTE":
		slope = 0.6
	elif path.has("climb_from") and i >= int(path["climb_from"]):
		# round the tower: it is the height that is climbed, not the table
		var hs: Array = path["high"]
		slope = -(float(hs[i + 1]) - float(hs[i])) * 100.0 / maxf(1.0, lens[i]) * float(path["climb_k"])
	ball["rv"] = float(ball["rv"]) + GRAVITY * float(path.get("pull", 1.0)) * slope * dt - float(ball["rv"]) * 0.12 * dt
	# ON THE FLAT (0.168.0): a ball slow on a level stretch (the top of XL2,
	# XR2) crawls on at RIDE_CRAWL the way it was going - it used to stop
	# there, on its ride, for ever
	if absf(slope) < 0.05 and absf(float(ball["rv"])) < RIDE_CRAWL:
		ball["rv"] = RIDE_CRAWL * (-1.0 if float(ball["rv"]) < 0.0 else 1.0)
	s += float(ball["rv"]) * dt
	if s <= 0.0:
		ball.erase("ride")
		ball["p"] = (pts[0] as Vector2) + Vector2(0, 14)
		ball["v"] = Vector2(0, absf(float(ball["rv"])) + 80.0)
		if what_name != "CHUTE" and not quiet:
			popups.append({"p": (pts[0] as Vector2) + Vector2(0, -60), "text": "SO CLOSE", "life": 0.9, "c": Color(INK, 0.8)})
		return
	if s >= total:
		if what_name != "CHUTE":
			makes[what_name] = int(makes.get(what_name, 0)) + 1
		if what_name == "TOWER":
			ball.erase("ride")
			ball["p"] = TOWER
			ball["v"] = Vector2.ZERO
			ramp_at[what_name]["flash"] = 1.0
			_tower_top(ball)
			return
		var dir: Vector2 = ((pts[pts.size() - 1] as Vector2) - (pts[pts.size() - 2] as Vector2)).normalized()
		ball["p"] = pts[pts.size() - 1]
		ball["v"] = dir * maxf(260.0, float(ball["rv"]))
		ball.erase("ride")
		ball.erase("chute")
		if what_name != "CHUTE":
			ramp_at[what_name]["flash"] = 1.0
			_made(what_name, pts[pts.size() - 1])
		return
	ball["s"] = s
	ball["p"] = _path_at(pts, lens, s)
	ball["lift"] = _lift_at(path["high"], lens, s)


func _made(what_name: String, at: Vector2) -> void:
	match what_name:
		"XR":
			stats["xr"] += 1
			_gain(150000, at + Vector2(0, -50), HERO["TANK"])
			_letter("TANK", at, 2)
		"XL":
			stats["xl"] += 1
			_gain(150000, at + Vector2(0, -50), HERO["WARR"])
			_letter("WARR", at, 2)
		"XL2", "XR2":
			stats["cross2"] += 1
			_gain(150000, at + Vector2(0, -50), COLOURS["light"])
			_banner("CROSSOVER", "150,000", COLOURS["light"])
		"SPIRAL":
			stats["spiral"] += 1
			_gain(250000, at + Vector2(0, -50), COLOURS["dark"].lightened(0.4))
			_banner("SPIRAL", "THE BEHOLDER STIRS", COLOURS["dark"].lightened(0.4))
			beholder["open"] = true
		"UP2":
			stats["up2"] += 1
			_gain(250000, at + Vector2(0, -50), GOLD)
			_banner("UP TO THE SECOND FLOOR", "250,000", GOLD)
		"WIRE":
			stats["wire"] += 1
			_gain(350000, at + Vector2(0, -50), GOLD)
			_banner("THE HIGH WIRE", "350,000  ·  A LETTER OF HEAL", GOLD)
			_letter("HEAL", at)
		"UP3":
			stats["up3"] += 1
			_gain(500000, at + Vector2(0, -50), GOLD)
			_banner("UP TO THE TOP FLOOR", "500,000", GOLD)


func _seg_at(lens: Array, s: float) -> int:
	var at: float = 0.0
	for i in lens.size():
		if s < at + float(lens[i]):
			return i
		at += float(lens[i])
	return lens.size() - 1


func _path_at(pts: Array, lens: Array, s: float) -> Vector2:
	var at: float = 0.0
	for i in lens.size():
		var l: float = lens[i]
		if s <= at + l:
			return (pts[i] as Vector2).lerp(pts[i + 1], (s - at) / maxf(0.001, l))
		at += l
	return pts[pts.size() - 1]


func _lift_at(high: Array, lens: Array, s: float) -> float:
	var at: float = 0.0
	for i in lens.size():
		var l: float = lens[i]
		if s <= at + l:
			return lerpf(high[i], high[i + 1], clampf((s - at) / maxf(0.001, l), 0.0, 1.0))
		at += l
	return high[high.size() - 1]


func _capsule(p: Vector2, a: Vector2, b: Vector2, ra: float, rb: float) -> Dictionary:
	var ab: Vector2 = b - a
	var u: float = clampf((p - a).dot(ab) / maxf(0.001, ab.length_squared()), 0.0, 1.0)
	var c: Vector2 = a + ab * u
	var d: Vector2 = p - c
	var reach: float = BALL_R + lerpf(ra, rb, u)
	var dist: float = d.length()
	if dist >= reach or dist < 0.0001:
		return {}
	return {"n": d / dist, "depth": reach - dist, "c": c, "u": u}


func _hit_walls(ball: Dictionary) -> void:
	var p0: Vector2 = ball["p"]
	var band: int = clampi(int(floor(p0.y / BAND)), 0, seg_bands.size() - 1)
	for i in seg_bands[band]:
		var s: Dictionary = segs[i]
		var kind: String = s["kind"]
		if kind == "gate" and (ball["v"] as Vector2).y <= 0.0:
			continue
		if kind == "lock" and open_floors[s["floor"]] and not multiball:
			continue
		if kind == "shield" and shield_t <= 0.0:
			continue
		if kind == "bridge" and gate["open"]:
			continue
		var a: Vector2 = s["a"]
		var b: Vector2 = s["b"]
		if p0.y < minf(a.y, b.y) - 30.0 or p0.y > maxf(a.y, b.y) + 30.0:
			continue
		var hit: Dictionary = _capsule(ball["p"], a, b, s["r"], s["r"])
		if hit.is_empty():
			continue
		var n: Vector2 = hit["n"]
		ball["p"] += n * float(hit["depth"])
		var v: Vector2 = ball["v"]
		var vn: float = v.dot(n)
		if vn < 0.0:
			v -= n * vn * (1.0 + WALL_BOUNCE)
			v -= (v - n * v.dot(n)) * 0.004
			var bounce_back: bool = s.get("bounce", false)
			if kind == "kick" and t - float(s.get("kick_t", -9.0)) > 0.35 \
					and (kickbacks[int(s["kb"])] if bounce_back else -vn > 110.0):
				s["kick_t"] = t
				if bounce_back:
					# a bounce-back, lit: any touch, a roll down it too, throws
					# the ball back up the table toward the middle, and that
					# side's kickback is spent
					var inward: float = 1.0 if int(s["kb"]) == 0 else -1.0
					v = Vector2(inward * BOUNCE_AIM.x + rng.randf_range(-30.0, 30.0), BOUNCE_AIM.y)
					kickbacks[int(s["kb"])] = false
					stats["kickbacks"] += 1
					_banner("KICKBACK", "", COLOURS["fire"])
				else:
					v += n * SLING_KICK
				s["flash"] = 1.0
				_gain(1100, hit["c"], GOLD)
				_burst(hit["c"], GOLD, 6)
			if kind == "shield":
				v.y = minf(v.y, -900.0)
				_burst(hit["c"], HERO["TANK"], 10)
			if kind == "bridge" and -vn > 150.0:
				_gate_hit(hit["c"])
			ball["v"] = v


func _hit_bumpers(ball: Dictionary) -> void:
	for b in bumpers:
		var d: Vector2 = ball["p"] - b["p"]
		var reach: float = float(b["r"]) + BALL_R
		if d.length_squared() >= reach * reach or d.length_squared() < 0.0001:
			continue
		var n: Vector2 = d.normalized()
		ball["p"] = b["p"] + n * reach
		var v: Vector2 = ball["v"]
		var vn: float = v.dot(n)
		if vn < 0.0:
			v -= n * vn * 1.6
		ball["v"] = v + n * BUMPER_KICK
		if b["cool"] > 0.0:
			continue
		b["cool"] = 0.08
		b["flash"] = 1.0
		stats["bumpers"] += 1
		var land: String = b["el"]
		_gain(10000 * (2 if _in_tide(b["p"]) else 1), b["p"] + n * 44.0, COLOURS[land])
		_burst(b["p"] + n * float(b["r"]), COLOURS[land], 10)
		_light(land)
		# THE LANDS MIX: a ball carrying one land into another's bumper
		var had: String = ball.get("land", "")
		if had != "" and had != land:
			var kind: String = _reaction(had, land)
			if kind != "":
				_react(kind, b)
		ball["land"] = land
		ball["tint"] = COLOURS[land]


func _reaction(a: String, b: String) -> String:
	for kind in MIX:
		var pair: Array = MIX[kind]
		if (pair[0] == a and pair[1] == b) or (pair[0] == b and pair[1] == a):
			return kind
	return ""


func _react(kind: String, at: Dictionary) -> void:
	"""A REACTION: its name on the display, and every bumper on that floor
	goes off with it."""
	stats["reactions"] += 1
	var pair: Array = MIX[kind]
	var c: Color = (COLOURS[pair[0]] as Color).lerp(COLOURS[pair[1]], 0.5)
	_gain(250000, (at["p"] as Vector2) + Vector2(0, -80), c.lightened(0.2))
	_banner(kind.to_upper() + "!", "%s + %s  ·  250,000" % [str(pair[0]).to_upper(), str(pair[1]).to_upper()], c.lightened(0.3))
	var fl: int = floor_of((at["p"] as Vector2).y)
	for b in bumpers:
		if floor_of((b["p"] as Vector2).y) == fl:
			b["flash"] = 1.0
			_burst(b["p"], c, 12)
			_gain(10000, (b["p"] as Vector2) + Vector2(0, -40), c)
	shake = 0.2


func _hit_targets(ball: Dictionary) -> void:
	for tg in targets:
		if tg["down"]:
			continue
		var r: Rect2 = tg["rect"]
		var p: Vector2 = ball["p"]
		var c := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
		var d: Vector2 = p - c
		if d.length_squared() >= BALL_R * BALL_R or d.length_squared() < 0.0001:
			continue
		var n: Vector2 = d.normalized()
		ball["p"] = c + n * BALL_R
		var v: Vector2 = ball["v"]
		var vn: float = v.dot(n)
		if vn < 0.0:
			v -= n * vn * 1.4
		ball["v"] = v
		tg["flash"] = 1.0
		if tg["el"] == "extra":
			if extra_lit:
				extra_lit = false
				stats["extra"] += 1
				extra_balls += 1
				_gain(500000, r.get_center() + Vector2(0, 40), Color(0.5, 1.0, 0.55))
				_banner("EXTRA BALL!", "SHOOT AGAIN", Color(0.5, 1.0, 0.55))
			else:
				_gain(25000, r.get_center() + Vector2(0, 40), Color(0.5, 1.0, 0.55))
			continue
		tg["down"] = true
		stats["targets"] += 1
		_gain(25000, r.get_center() + Vector2(40, 0), COLOURS[tg["el"]])
		_burst(r.get_center(), COLOURS[tg["el"]], 12)
		_light(tg["el"])


func _hit_eyes(ball: Dictionary) -> void:
	for e in eyes:
		var at: Vector2 = e["p"]
		var d: Vector2 = ball["p"] - at
		var reach: float = EYE_R + BALL_R
		if d.length_squared() >= reach * reach or d.length_squared() < 0.0001:
			continue
		var n: Vector2 = d.normalized()
		ball["p"] = at + n * reach
		var v: Vector2 = ball["v"]
		var vn: float = v.dot(n)
		if vn < 0.0:
			v -= n * vn * 1.6
		ball["v"] = v
		if e["cool"] > 0.0 or -vn < 150.0:
			continue
		e["cool"] = 0.4
		e["flash"] = 1.0
		shake = 0.2
		stats["eyes"] += 1
		_burst(at + n * EYE_R, COLOURS["dark"].lightened(0.3), 16)
		if multiball:
			stats["jackpots"] += 1
			_drop_loot(at, 1, "goldpile", 3)
			_drop_loot(at, 1, "goldcoin", 6)
			_gain(500000, at + Vector2(0, -90), GOLD)
			_banner("JACKPOT!", "1,000,000", GOLD)
			continue
		_gain(50000, at + Vector2(0, -90), COLOURS["dark"].lightened(0.4))
		if e["open"]:
			continue
		e["hp"] = int(e["hp"]) - 1
		if e["hp"] <= 0:
			e["open"] = true
			if eyes.all(func(x: Dictionary) -> bool: return x["open"]):
				_multiball()
			else:
				_banner("ONE EYE OPEN", "NOW THE OTHER", COLOURS["dark"].lightened(0.4))


func _hit_beholder(ball: Dictionary) -> void:
	var d: Vector2 = ball["p"] - BEHOLDER
	var reach: float = BEHOLDER_R + BALL_R
	if d.length_squared() >= reach * reach or d.length_squared() < 0.0001:
		return
	var n: Vector2 = d.normalized()
	ball["p"] = BEHOLDER + n * reach
	var v: Vector2 = ball["v"]
	var vn: float = v.dot(n)
	if vn < 0.0:
		v -= n * vn * 1.6
	ball["v"] = v + n * 160.0
	if float(beholder["flash"]) > 0.6 or -vn < 150.0:
		return
	beholder["flash"] = 1.0
	stats["beholder"] += 1
	shake = 0.3
	var worth: int = 250000 if beholder["open"] else 100000
	_gain(worth, BEHOLDER + Vector2(0, -150), COLOURS["dark"].lightened(0.45))
	_burst(BEHOLDER + n * BEHOLDER_R, COLOURS["dark"].lightened(0.4), 20)
	_drop_eye(BEHOLDER + n * (BEHOLDER_R + 30.0))
	beholder["open"] = false


func slime_at() -> Vector2:
	return Vector2(600.0 + 250.0 * sin(t * 0.55), 3035.0)


func _hit_slime(ball: Dictionary) -> void:
	"""THE SLIME: a little one hops across the ground floor. A secret."""
	if slime_gone > 0.0:
		return
	var at: Vector2 = slime_at()
	var d: Vector2 = ball["p"] - at
	if d.length() > 30.0 or floor_of((ball["p"] as Vector2).y) != 0:
		return
	slime_gone = 9.0
	stats["slime"] += 1
	ball["v"] = (ball["v"] as Vector2) * 0.6 + d.normalized() * 300.0
	_gain(1000000, at + Vector2(0, -60), Color(0.5, 1.0, 0.4))
	_banner("SLIME SPLAT!", "A SECRET  ·  1,000,000", Color(0.5, 1.0, 0.4))
	_burst(at, Color(0.45, 0.95, 0.35), 34)


func _beam(ball: Dictionary, dt: float) -> void:
	"""THE BEHOLDER'S BEAM sweeps the top floor: a ball in it is pushed the
	way it sweeps - never drained."""
	var p: Vector2 = ball["p"]
	if floor_of(p.y) != 2:
		return
	var dir := Vector2(cos(beam_a), sin(beam_a))
	var rel: Vector2 = p - BEHOLDER
	var along: float = rel.dot(dir)
	var side: Vector2 = dir.orthogonal()
	if along > BEHOLDER_R and along < 620.0 and absf(rel.dot(side)) < 26.0:
		ball["v"] = (ball["v"] as Vector2) + side * signf(beam_w) * -1400.0 * dt


func _multiball() -> void:
	multiball = true
	multiplier = 2
	if stats["multiball_at"] < 0.0:
		stats["multiball_at"] = t
	_banner("BOTH EYES OPEN", "MULTIBALL", COLOURS["dark"].lightened(0.35))
	_mission("eyes")
	var tints: Array = [COLOURS["fire"], COLOURS["ice"]]
	for i in 2:
		var e: Dictionary = eyes[i]
		balls.append({"p": (e["p"] as Vector2) + Vector2(0, 80), "v": Vector2(-260.0 if i == 0 else 260.0, 220.0),
			"held": false, "trail": [], "tint": tints[i], "slow": 0.0, "land": "", "lane": 0.0})
		_burst(e["p"], COLOURS["dark"].lightened(0.4), 24)


func _hit_flippers(ball: Dictionary) -> void:
	var p: Vector2 = ball["p"]
	var touched: bool = false
	for f in flippers:
		var a: Vector2 = f["pivot"]
		if absf(p.y - a.y) > 170.0:
			continue
		var tip: Vector2 = a + _dir(f) * float(f["len"])
		var hit: Dictionary = _capsule(ball["p"], a, tip, 12.0, 7.0)
		if hit.is_empty():
			continue
		var n: Vector2 = hit["n"]
		ball["p"] += n * float(hit["depth"])
		var arm: float = (hit["c"] as Vector2).distance_to(a)
		var vp: Vector2 = _ddir(f) * float(f["adot"]) * arm
		var rel: Vector2 = ball["v"] - vp
		var vn: float = rel.dot(n)
		touched = true
		if vn < 0.0:
			rel -= n * vn * (1.0 + FLIP_BOUNCE)
			ball["v"] = vp + rel
			if float(f["adot"]) < 0.0:
				ball["aim_f"] = f
	# the attract mode's nudge goes on as the ball leaves the flipper
	if not touched and ball.has("aim_f") and attract:
		var fl: Dictionary = ball["aim_f"]
		ball.erase("aim_f")
		_aim_shot(ball, fl)


func _aim_shot(ball: Dictionary, f: Dictionary) -> void:
	"""THE ATTRACT MODE'S PLAYER: most flips are nudged a few degrees toward
	what the table wants next. The rest go where they go."""
	var v: Vector2 = ball["v"]
	if v.length() < 500.0 or v.y > 0.0 or rng.randf() > 0.82:
		return
	var goal: Vector2 = _goal(f, ball["p"])
	var want: float = (goal - (ball["p"] as Vector2)).angle()
	var most: float = 1.25 if goal.x < 100.0 else 0.6
	var turn: float = clampf(wrapf(want - v.angle(), -PI, PI), -most, most)
	ball["v"] = v.rotated(turn) * maxf(1.0, 1900.0 / v.length())


func _goal(f: Dictionary, at: Vector2) -> Vector2:
	var fresh: Vector2 = _goal_new(f, float(f["side"]) > 0.0)
	if fresh != Vector2.INF:
		return fresh
	if f.get("upper", false):
		return Vector2(330, 2660) if rng.randf() < 0.45 else Vector2(60, 2880)
	var left: bool = float(f["side"]) > 0.0
	match int(f["floor"]):
		0:
			# the fan: the right flipper takes the left shots across, the left
			# flipper the right ones
			var r0: float = rng.randf()
			if not left and r0 < (0.42 if stats["free"] == 0 else 0.2):
				return Vector2(58, 2900)
			if open_floors[1] and not multiball and r0 < 0.55:
				return ramp_at["UP2"]["mouth"]
			var pick: int = rng.randi() % 5
			if left:
				return [ramp_at["XR"]["mouth"], Vector2(1145, 2900), Vector2(KEEP.x, BRIDGE_Y), Vector2(CAGE_X, CAGE_MOUTH + 6.0),
					ramp_at["XR"]["mouth"]][pick]
			return [ramp_at["XL"]["mouth"], PORTAL, Vector2(KEEP.x, BRIDGE_Y), Vector2(470, SKEL_Y + 7.0), ramp_at["XL"]["mouth"]][pick]
		1:
			if multiball:
				return eyes[1]["p"] if left else eyes[0]["p"]
			if eyes.all(func(e: Dictionary) -> bool: return e["open"]) or done.has("eyes"):
				if open_floors[2] and rng.randf() < 0.7:
					return ramp_at["UP3"]["mouth"]
				return ramp_at["XR2"]["mouth"] if left else ramp_at["XL2"]["mouth"]
			for e in eyes:
				if not e["open"] and rng.randf() < 0.8:
					return e["p"]
			return ramp_at["XR2"]["mouth"] if left else ramp_at["XL2"]["mouth"]
		_:
			var pick2: int = rng.randi() % 3
			return [LAIR, BEHOLDER, ramp_at["SPIRAL"]["mouth"]][pick2]


func _dir(f: Dictionary) -> Vector2:
	var a: float = f["a"]
	return Vector2(cos(a) * float(f["side"]), sin(a))


func _ddir(f: Dictionary) -> Vector2:
	var a: float = f["a"]
	return Vector2(-sin(a) * float(f["side"]), cos(a))


func _move_flipper(f: Dictionary, dt: float) -> void:
	f["hold"] = maxf(0.0, f["hold"] - dt)
	f["cool"] = maxf(0.0, f["cool"] - dt)
	if f["late"] > 0.0:
		f["late"] = maxf(0.0, f["late"] - dt)
		if f["late"] <= 0.0:
			f["hold"] = 0.24
	var target: float = UP if f["hold"] > 0.0 else REST
	if f["a"] > target:
		f["adot"] = -FLIP_SPEED
		f["a"] = maxf(target, f["a"] - FLIP_SPEED * dt)
	elif f["a"] < target:
		f["adot"] = FLIP_SPEED * 0.45
		f["a"] = minf(target, f["a"] + FLIP_SPEED * 0.45 * dt)
	else:
		f["adot"] = 0.0


func _think(f: Dictionary) -> void:
	if f["hold"] > 0.0 or f["cool"] > 0.0 or f["late"] > 0.0:
		return
	var a: Vector2 = f["pivot"]
	var dir := Vector2(cos(REST) * float(f["side"]), sin(REST))
	var up: Vector2 = dir.orthogonal()
	if up.y > 0.0:
		up = -up
	for ball in balls:
		if ball["held"] or ball.has("ride") or ball.has("sunk"):
			continue
		var rel: Vector2 = ball["p"] - a
		var u: float = rel.dot(dir) / float(f["len"])
		var above: float = rel.dot(up)
		if u > float(f["aim"]) and u < 1.08 and above > -2.0 and above < 42.0 and (ball["v"] as Vector2).y > -60.0:
			f["cool"] = 0.4
			f["aim"] = rng.randf_range(0.15, 0.8)
			if rng.randf() < 0.08:
				f["late"] = 0.1
			else:
				f["hold"] = 0.24
			_lane_change(float(f["side"]), int(f["floor"]))
			return


func _balls_meet() -> void:
	for i in balls.size():
		for j in range(i + 1, balls.size()):
			var bi: Dictionary = balls[i]
			var bj: Dictionary = balls[j]
			if bi["held"] or bj["held"] or bi.has("ride") or bj.has("ride") or bi.has("sunk") or bj.has("sunk"):
				continue
			var d: Vector2 = bj["p"] - bi["p"]
			var dist: float = d.length()
			if dist >= BALL_R * 2.0 or dist < 0.0001:
				continue
			var n: Vector2 = d / dist
			var push: float = (BALL_R * 2.0 - dist) / 2.0
			bi["p"] -= n * push
			bj["p"] += n * push
			var rel: float = ((bj["v"] as Vector2) - (bi["v"] as Vector2)).dot(n)
			if rel < 0.0:
				bi["v"] += n * rel * 0.9
				bj["v"] -= n * rel * 0.9


func _drains() -> void:
	var before: int = balls.size()
	balls = balls.filter(func(b: Dictionary) -> bool: return (b["p"] as Vector2).y < H + 20.0 and not b.get("out", false))
	if balls.size() == before:
		return
	if balls.size() == 1 and multiball:
		multiball = false
		multiplier = 1
		for e in eyes:
			e["open"] = false
			e["hp"] = EYE_HP
	if not balls.is_empty():
		return
	if t < save_until:
		stats["saved"] += 1
		_banner("BALL SAVED", "THE HEALER", HERO["HEAL"])
		heals.append(t)
	else:
		stats["lost"] += 1
		ball_no += 1
		if ball_no > BALLS + extra_balls and not attract:
			over = true
			_banner("GAME OVER", _thousands(score), GOLD)
			game_over.emit()
			return
		_banner("BALL %d" % ball_no, "KICKBACKS LIT", INK)
		kickbacks = [true, true]
	multiball = false
	multiplier = 1
	_new_ball()


func _settle_targets() -> void:
	for tg in targets:
		tg["flash"] = maxf(0.0, tg["flash"] - 1.0 / FPS * 3.0)
	var bank: Array = targets.filter(func(x: Dictionary) -> bool: return x["bank"] == 0)
	if bank.all(func(x: Dictionary) -> bool: return x["down"]):
		if not bank[0].has("back"):
			bank[0]["back"] = t + 2.0
			kickbacks = [true, true]
			_banner("TARGETS DOWN", "KICKBACKS LIT", COLOURS["earth"].lightened(0.3))
			_gain(200000, (bank[1]["rect"] as Rect2).get_center() + Vector2(60, 0), GOLD)
		elif t >= float(bank[0]["back"]):
			bank[0].erase("back")
			for x in bank:
				x["down"] = false
	# the eyestalks: a bank down opens the Beholder
	for bi in [2, 3]:
		var stalks: Array = targets.filter(func(x: Dictionary) -> bool: return x["bank"] == bi)
		if stalks.is_empty() or not stalks.all(func(x: Dictionary) -> bool: return x["down"]):
			continue
		if not stalks[0].has("back"):
			stalks[0]["back"] = t + 2.5
			stats["stalks"] += 1
			beholder["open"] = true
			_banner("THE EYESTALKS FALL", "THE BEHOLDER OPENS", COLOURS["dark"].lightened(0.45))
			_gain(300000, (stalks[1]["rect"] as Rect2).get_center() + Vector2(0, -50), COLOURS["dark"].lightened(0.45))
		elif t >= float(stalks[0]["back"]):
			stalks[0].erase("back")
			for x in stalks:
				x["down"] = false


func _light(el: String) -> void:
	if lit.has(el):
		return
	lit[el] = t
	if lit.size() == ORDER.size():
		_gain(1000000, Vector2(CX, 3360), GOLD)
		_banner("ALL SEVEN LANDS", "1,000,000", GOLD)
		lit.clear()


func _letter(word: String, at: Vector2, n_letters: int = 1) -> void:
	"""A HERO'S LETTER: the next letter of the word its shot spells (the big
	shots light two). The whole word sets off that hero's power."""
	words[word] = mini(4, int(words[word]) + n_letters)
	var n: int = words[word]
	if n < 4:
		if not quiet:
			popups.append({"p": at + Vector2(0, -80), "text": word.substr(0, n) + "_".repeat(4 - n), "life": 1.0, "c": HERO[word]})
		return
	words[word] = 0
	stats["words"] += 1
	if stats["word_at"] < 0.0:
		stats["word_at"] = t
	done["word_" + word] = t
	_gain(500000, at + Vector2(0, -80), HERO[word])
	_banner(str(HERO_NAME[word]) + "!", str(POWER[word]) + "  ·  500,000", HERO[word])
	stats["heroes"] += 1
	if not quiet:
		cards.append({"w": word, "at": t})
	match word:
		"MAGE":
			# from her tower: the monsters first, then the bumpers
			var aims: Array = []
			for mob in mobs:
				if int(mob["fl"]) == 0 and _alive(mob):
					aims.append({"mob": mob})
			for r in rocks:
				if not r["gone"] and int(r["fl"]) == 0:
					aims.append({"rock": r})
			for i in bumpers.size():
				if floor_of((bumpers[i]["p"] as Vector2).y) == 0:
					aims.append({"b": i})
			for j in 8:
				var m: Dictionary = (aims[j % aims.size()] as Dictionary).duplicate()
				m["at"] = t + 0.9 + j * 0.38
				meteors.append(m)
			mage_until = t + 0.9 + 8 * 0.38 + 0.8
		"WARR":
			whirl_t = 10.0
		"TANK":
			shield_t = 20.0
			if not (kickbacks[0] and kickbacks[1]):
				stats["relit"] += 1
			kickbacks = [true, true]
		"HEAL":
			save_until = t + 15.0
			extra_lit = true
			heals.append(t)
	if WORDS.all(func(w: String) -> bool: return done.has("word_" + w)) and not done.has("heroes"):
		done["heroes"] = t
		_gain(2000000, at + Vector2(0, -120), GOLD)
		_banner("THE FOUR HEROES", "2,000,000", GOLD)


func _mission(what: String) -> void:
	if done.has(what):
		return
	done[what] = t
	rank = mini(rank + 1, RANKS.size() - 1)
	_banner("RANK UP", RANKS[rank], GOLD)


func _gain(points: int, at: Vector2, c: Color) -> void:
	var worth: int = points * multiplier * lane_x * (3 if whirl_t > 0.0 else 1) * (2 if _effect_is("light") else 1)
	score += worth
	if quiet:
		return
	popups.append({"p": at, "text": "+" + _thousands(worth), "life": 0.9, "c": c})


func _burst(at: Vector2, c: Color, n: int) -> void:
	if quiet:
		return
	for i in n:
		var ang: float = vrng.randf() * TAU
		sparks.append({"p": at, "v": Vector2(cos(ang), sin(ang)) * vrng.randf_range(80.0, 260.0),
			"life": vrng.randf_range(0.25, 0.55), "c": c})


func _banner(text: String, sub: String, c: Color) -> void:
	if quiet:
		return
	while banners.size() >= 2:
		banners.pop_back()
	if not banners.is_empty():
		banners[0]["life"] = minf(float(banners[0]["life"]), 0.5)
	banners.append({"text": text, "sub": sub, "life": 1.5, "c": c})


func _judge() -> float:
	var good: float = 0.0
	var f2: float = stats["floor2_first"]
	var f3: float = stats["floor3_first"]
	if f2 > 0.0:
		good += 22.0 - absf(f2 - 19.0)
	if f3 > 0.0:
		good += 26.0 - absf(f3 - 62.0)
	good += minf(stats["locks"], 1) * 14.0 + minf(stats["free"], 1) * 32.0 + minf(stats["tower"], 3) * 3.0
	good += minf(stats["slain"], 8) * 2.5 + minf(stats["horde"], 1) * 10.0 + minf(stats["horde_kills"], 5) * 2.0
	good += minf(stats["rocks"], 4) * 1.5 + minf(stats["vents"], 3) * 2.0
	for w in WORDS:
		if done.has("word_" + w):
			good += 7.0
	good += minf(stats["reactions"], 2) * 3.0 + minf(stats["slime"], 1) * 8.0 + minf(stats["meteor"], 8) * 0.8
	good += minf(stats["xl"] + stats["xr"], 3) * 3.0 + minf(stats["warp"], 1) * 4.0 + minf(stats["eyes"], 6) * 1.0
	good += minf(stats["eye_drops"], 3) * 2.0
	good += minf(stats["synergy"], 4) * 6.0 + minf(stats["synergy_kills"], 6) * 2.0
	var dark_at: float = stats["dark_at"]
	if dark_at > 12.0 and dark_at < 46.0:
		good += 14.0
	# the new mechanics, each seen at least once
	good += minf(stats["spins"], 20) * 0.3 + minf(stats["skel_banks"], 2) * 8.0 + minf(stats["magnet"], 2) * 8.0
	good += minf(stats["trips"], 3) * 3.0 + minf(stats["spirit"], 1) * 10.0 + minf(stats["wire"], 2) * 8.0
	good += minf(stats["well"], 2) * 8.0 + minf(stats["gate_hits"], 4) * 2.0 + minf(stats["gate_down"], 1) * 10.0
	good += minf(stats["siege"], 1) * 24.0 + minf(stats["siege_won"], 1) * 20.0 + minf(stats["relit"], 1) * 4.0
	good += minf(stats["lanes"], 6) * 1.0 + minf(stats["lane_ups"], 1) * 8.0 + minf(stats["portal"], 2) * 3.0
	good += minf(stats["stalks"], 1) * 8.0
	good -= stats["lost"] * 12.0 + stats["nudges"] * 5.0
	return good


# =============================================================================
# THE MAGE'S TOWER
# =============================================================================

func _tower_top(ball: Dictionary) -> void:
	"""THE TOWER'S TOP: the first ball up is held in the crystal; the next
	one up sets it free - a free ball, and both come down."""
	stats["tower"] += 1
	_gain(250000, TOWER + Vector2(0, -100), HERO["MAGE"])
	_burst(TOWER, HERO["MAGE"], 26)
	_letter("MAGE", TOWER, 2)
	if tower_ball.is_empty():
		ball["lock_me"] = true
		stats["locks"] += 1
		_banner("BALL LOCKED", "THE TOWER HOLDS IT  ·  CLIMB AGAIN", HERO["MAGE"].lightened(0.2))
		return
	stats["free"] += 1
	_banner("FREE BALL!", "TOWER MULTIBALL  ·  1,000,000", GOLD)
	_drop_loot(TOWER + Vector2(60, 60), 0, "goldpile", 3)
	_drop_loot(TOWER + Vector2(60, 60), 0, "goldcoin", 6)
	_gain(1000000, TOWER + Vector2(0, -140), GOLD)
	shake = 0.3
	var freed: Dictionary = tower_ball
	tower_ball = {}
	freed.erase("locked")
	_drop_from_tower(freed, 0.0)
	_drop_from_tower(ball, 0.75)
	to_add.append(freed)
	multiball = true
	multiplier = 2


func _drop_from_tower(ball: Dictionary, wait: float) -> void:
	ball["ride"] = "CHUTE"
	ball["chute"] = {"pts": [TOWER, TOWER + Vector2(62, 40), TOWER + Vector2(105, 95), TOWER + Vector2(130, 150)],
		"high": [TOWER_TOP + 0.04, 0.9, 0.25, 0.02]}
	ball["s"] = 0.0
	ball["rv"] = 260.0
	ball["p"] = TOWER
	ball["lift"] = TOWER_TOP + 0.04
	ball["trail"] = []
	if wait > 0.0:
		ball["wait"] = wait


func _locks() -> void:
	"""A ball the tower took leaves the table; a freed one comes back; with
	none left in play the next waits at the plunger - nothing lost."""
	for ball in balls.duplicate():
		if ball.get("lock_me", false):
			ball.erase("lock_me")
			ball["locked"] = true
			balls = balls.filter(func(b: Dictionary) -> bool: return not is_same(b, ball))
			tower_ball = ball
	for ball in to_add:
		balls.append(ball)
	to_add.clear()
	if balls.is_empty():
		_new_ball()


# =============================================================================
# THE MONSTERS
# =============================================================================

func _meteor_end(m: Dictionary) -> Vector2:
	if m.has("rock"):
		return m["rock"]["p"]
	if m.has("mob"):
		var mob: Dictionary = m["mob"]
		return _mob_at(mob) if _alive(mob) else mob["dpos"]
	return bumpers[m["b"]]["p"]


func _hit_mobs(ball: Dictionary) -> void:
	var p: Vector2 = ball["p"]
	var fl: int = floor_of(p.y)
	for m in mobs:
		if int(m["fl"]) != fl or not _alive(m):
			continue
		var at: Vector2 = _mob_at(m)
		var d: Vector2 = p - at
		var reach: float = float(m["r"]) + BALL_R
		if d.length_squared() >= reach * reach or d.length_squared() < 0.0001:
			continue
		var n: Vector2 = d.normalized()
		ball["p"] = at + n * reach
		var v: Vector2 = ball["v"]
		var vn: float = v.dot(n)
		if vn < 0.0:
			v -= n * vn * 1.5
		ball["v"] = v + n * 240.0
		_wound(m, 1, at)


func _synergy_on() -> bool:
	"""A hero at work (the Warrior's axes, the Mage's meteors) while a land's
	effect is on."""
	return (whirl_t > 0.0 or t < mage_until) and not effect.is_empty() and t >= float(effect["from"]) and t < float(effect["to"])


func _hero_kill(at: Vector2, worth: int) -> void:
	"""SYNERGY: each kill a hero makes in a land's effect raises it, x2 to
	x5, and pays the kill again that many times less one."""
	if not _synergy_on():
		return
	synergy = 2 if synergy == 0 else mini(5, synergy + 1)
	stats["synergy"] = maxi(int(stats["synergy"]), synergy)
	stats["synergy_kills"] += 1
	if synergy == 2:
		var hero: String = "THE WARRIOR" if whirl_t > 0.0 else "THE MAGE"
		_banner("SYNERGY!", "%s IN THE %s" % [hero, EFFECT[effect["land"]]], GOLD)
		_cue("synergy")
	_gain(worth * (synergy - 1), at + Vector2(0, -100), GOLD)
	if not quiet:
		popups.append({"p": at + Vector2(0, -160), "text": "SYNERGY x%d" % synergy, "life": 1.0, "c": GOLD})


func _splat(h: Dictionary, by_hero: bool) -> void:
	var at: Vector2 = _horde_at(h)
	h["dead"] = t
	h["dpos"] = at
	stats["horde_kills"] += 1
	_gain(100000, at + Vector2(0, -60), Color(0.5, 1.0, 0.4))
	_burst(at, Color(0.45, 0.95, 0.35), 20)
	_drop_loot(at, int(h["fl"]), "coppercoin", 3)
	if by_hero:
		_hero_kill(at, 100000)


func _break_rock(r: Dictionary, by_hero: bool) -> void:
	r["flash"] = 0.2
	r["hp"] = 0
	r["gone"] = true
	stats["rocks"] += 1
	_gain(75000, (r["p"] as Vector2) + Vector2(0, -60), COLOURS["earth"].lightened(0.3))
	_burst(r["p"], COLOURS["earth"].lightened(0.2), 24)
	if by_hero:
		_hero_kill(r["p"], 75000)


func _wound(m: Dictionary, dmg: int, at: Vector2, by_hero: bool = false) -> void:
	if not _alive(m) or t < float(m["hurt"]) + 0.25:
		return
	m["hurt"] = t
	m["hp"] = int(m["hp"]) - dmg
	var c: Color = MOB_COLOUR[m["kind"]]
	if int(m["hp"]) > 0:
		_gain(25000, at + Vector2(0, -60), c)
		_burst(at, c, 8)
		return
	m["died"] = t
	m["dpos"] = at
	m["back"] = t + 7.0
	m["hp"] = m["max"]
	slain += 1
	stats["slain"] += 1
	_gain(int(m["worth"]) * (3 if _effect_is("dark") else 1), at + Vector2(0, -70), c)
	_burst(at, c, 30)
	_drop_loot(at, int(m["fl"]), COIN[m["kind"]], 5)
	_drop_loot(at, int(m["fl"]), "lootbag", 1)
	if m["kind"] == "storm" and int(m["fl"]) == 2:
		_drop_eye(at)
	if by_hero:
		_hero_kill(at, int(m["worth"]))
	shake = maxf(shake, 0.15)
	if not quiet:
		popups.append({"p": at + Vector2(0, -130), "text": str(MOB_NAME[m["kind"]]) + " SLAIN", "life": 1.1, "c": c})
	if slain % 5 == 0:
		_start_horde()


func _drop_eye(at: Vector2) -> void:
	"""THE BEHOLDER'S EYES: his hits, his lair and his storm guards each give
	up the eye of a land. All six, and the crowned eye opens the boss."""
	if eye_drops.size() >= EYE_ORDER.size():
		return
	var el: String = EYE_ORDER[eye_drops.size()]
	eye_drops.append(el)
	stats["eye_drops"] += 1
	_drop_loot(at, floor_of(at.y), "eye_" + el, 1)
	if not quiet:
		popups.append({"p": at + Vector2(0, -110), "text": "THE %s EYE" % el.to_upper(), "life": 1.1, "c": (COLOURS[el] as Color).lightened(0.3)})
	if eye_drops.size() == EYE_ORDER.size():
		done["crowned"] = t
		_gain(1000000, at + Vector2(0, -150), GOLD)
		_banner("THE CROWNED EYE", "SIX EYES TAKEN  ·  THE BOSS AWAITS", GOLD)
		_drop_loot(at, floor_of(at.y), "eye_crowned", 1)


func _drop_loot(at: Vector2, fl: int, key: String, n: int) -> void:
	"""Loot out of a monster: the pack's coins and bags, thrown up, bouncing,
	then collected with a sparkle. Only looks; the score has it already."""
	if quiet:
		return
	for i in n:
		var ang: float = vrng.randf() * TAU
		loot.append({"p": at, "v": Vector2(cos(ang), sin(ang) * 0.6) * vrng.randf_range(60.0, 220.0), "h": 0.25,
			"vh": vrng.randf_range(2.2, 3.6), "key": key, "fl": fl, "life": vrng.randf_range(1.2, 1.7) + (0.6 if key.begins_with("eye") else 0.0)})
	while loot.size() > 40:
		loot.pop_front()


func _start_horde() -> void:
	"""THE HORDE: every fifth monster slain, a line of slimes marches across
	the floor the ball is on. Each one splats for 100,000."""
	if balls.is_empty():
		return
	var fl: int = 1 if floor_of((_focus()["p"] as Vector2).y) == 1 else 0
	horde.clear()
	for i in 7:
		horde.append({"i": i, "fl": fl, "dead": -100.0, "dpos": Vector2.ZERO})
	horde_at = t
	stats["horde"] += 1
	_banner("THE HORDE RISES!", "SPLAT THE SLIMES  ·  100,000 EACH", Color(0.5, 1.0, 0.4))


func _horde_at(h: Dictionary) -> Vector2:
	var fl: int = h["fl"]
	var x0: float = 90.0 if fl == 0 else 280.0
	var y: float = 3175.0 if fl == 0 else 1880.0
	return Vector2(x0 + (t - horde_at) * 120.0 - int(h["i"]) * 80.0, y)


func _horde_on(h: Dictionary) -> bool:
	if float(h["dead"]) > 0.0:
		return false
	var x: float = _horde_at(h).x
	return x >= (80.0 if int(h["fl"]) == 0 else 270.0) and x <= (1120.0 if int(h["fl"]) == 0 else 930.0)


func _march() -> void:
	if horde.is_empty():
		return
	var last: float = _horde_at(horde[horde.size() - 1]).x
	if last > (1120.0 if int(horde[0]["fl"]) == 0 else 930.0):
		horde.clear()


func _hit_horde(ball: Dictionary) -> void:
	var p: Vector2 = ball["p"]
	for h in horde:
		if not _horde_on(h) or floor_of(p.y) != int(h["fl"]):
			continue
		var at: Vector2 = _horde_at(h)
		var d: Vector2 = p - at
		if d.length() > 30.0:
			continue
		ball["v"] = (ball["v"] as Vector2) * 0.85 + d.normalized() * 220.0
		_splat(h, false)


# =============================================================================
# THE LANDS' EFFECTS
# =============================================================================

func _effect_is(land: String) -> bool:
	"""The land's effect is on - not while it is only being warned of."""
	return not effect.is_empty() and effect["land"] == land and t >= float(effect["from"])


func _warning_of() -> String:
	"""The land whose effect is coming, during its WARN seconds; else ""."""
	if effect.is_empty() or t >= float(effect["from"]):
		return ""
	return effect["land"]


func _cue(what_name: String) -> void:
	"""A SOUND'S PLACE: the owner records every sound himself; this names
	where each one goes (warn_<land>, land_<land>, synergy) and plays nothing."""
	cues.append([t, what_name])


func _fx_k() -> float:
	"""How strongly the effect holds: in over half a second, out over the last."""
	if effect.is_empty():
		return 0.0
	return clampf((t - float(effect["from"])) / 0.5, 0.0, 1.0) * clampf((float(effect["to"]) - t) / 0.6, 0.0, 1.0)


func _tide_y(fl: int) -> float:
	var y0: float = FLOORS[fl]["y0"]
	var yb: float = FLOORS[fl]["yb"]
	if not _effect_is("water"):
		return yb + 1000.0
	var k: float = clampf((t - float(effect["from"])) / 1.2, 0.0, 1.0) * clampf((float(effect["to"]) - t) / 0.9, 0.0, 1.0)
	return yb - (yb - y0) * 0.42 * k


func _in_tide(p: Vector2) -> bool:
	return p.y > _tide_y(floor_of(p.y))


func _surface_at(x: float, fl: int) -> float:
	"""The tide's surface at x, waves and all, on floor fl."""
	return _tide_y(fl) + sin(x * WAVE_EVERY + t * WAVE_SPEED) * WAVE_HIGH


func _afloat(p: Vector2) -> bool:
	"""A ball riding the tide's surface."""
	return _effect_is("water") and absf(p.y - _surface_at(p.x, floor_of(p.y))) < BALL_R * 3.0


func _vent_on(i: int) -> bool:
	return _effect_is("fire") and fmod(t - float(effect["from"]) + i * 0.55, 1.65) < 0.5


func _land_effects() -> void:
	if not effect.is_empty() and t >= float(effect["to"]):
		for r in rocks:
			if not r["gone"]:
				r["gone"] = true
				_burst(r["p"], COLOURS["earth"].lightened(0.2), 10)
		effect = {}
		next_effect = t + EFFECT_GAP - EFFECT_LEN
	if effect.is_empty():
		if t >= next_effect and not balls.is_empty():
			_start_effect()
		return
	if t < float(effect["from"]):
		return
	if not effect["begun"]:
		effect["begun"] = true
		var land: String = effect["land"]
		_banner(EFFECT[land], EFFECT_SUB[land], (COLOURS[land] as Color).lightened(0.25))
		_cue("land_" + land)
		if land == "dark" and float(stats["dark_at"]) < 0.0:
			stats["dark_at"] = t
	var age: float = t - float(effect["from"])
	match str(effect["land"]):
		"earth":
			if fmod(age, 1.1) < 1.0 / FPS:
				shake = maxf(shake, 0.55)
			for r in rocks:
				if not r.get("landed", false) and t >= float(r["land"]):
					r["landed"] = true
					shake = maxf(shake, 0.35)
					_burst(r["p"], COLOURS["earth"].lightened(0.35), 14)
		"fire":
			if quiet:
				return
			for fl in 3:
				for i in 3:
					if _vent_on(i):
						var at: Vector2 = VENTS[fl][i]
						for j in 2:
							sparks.append({"p": at + Vector2(vrng.randf_range(-24, 24), vrng.randf_range(-10, 10)),
								"v": Vector2(vrng.randf_range(-30, 30), vrng.randf_range(-60, 0)), "life": vrng.randf_range(0.5, 0.9),
								"c": COLOURS["fire"].lerp(Color(1, 0.9, 0.4), vrng.randf()), "rise": vrng.randf_range(0.9, 1.8)})


func _start_effect() -> void:
	var ball: Dictionary = _focus()
	var land: String = ball.get("land", "")
	if land == "" or effects_shown.has(land):
		land = ""
		for l in EFFECT_ORDER:
			if not effects_shown.has(l):
				land = l
				break
	if land == "":
		effects_shown.clear()
		land = ORDER[rng.randi() % ORDER.size()]
	effects_shown.append(land)
	effect = {"land": land, "warn": t, "from": t + WARN, "to": t + WARN + EFFECT_LEN, "begun": false}
	stats["effects"] += 1
	_banner(str(EFFECT[land]) + " COMING", "IN 1.5 SECONDS  ·  " + str(EFFECT_SUB[land]).get_slice("  ·  ", 1),
		(COLOURS[land] as Color).lightened(0.25))
	_cue("warn_" + land)
	if land == "earth":
		_drop_rocks(floor_of((ball["p"] as Vector2).y))


func _drop_rocks(fl: int) -> void:
	rocks.clear()
	var spots: Array = (ROCK_SPOTS[fl] as Array).duplicate()
	for i in 5:
		var at: Vector2 = spots.pop_at(rng.randi() % spots.size())
		rocks.append({"p": at, "fl": fl, "land": t + WARN + 0.3 + i * 0.4, "hp": 2, "flash": 0.0, "gone": false, "r": 22.0})


func _hit_rocks(ball: Dictionary) -> void:
	var p: Vector2 = ball["p"]
	for r in rocks:
		if r["gone"] or t < float(r["land"]) or floor_of(p.y) != int(r["fl"]):
			continue
		var at: Vector2 = r["p"]
		var d: Vector2 = p - at
		var reach: float = float(r["r"]) + BALL_R
		if d.length_squared() >= reach * reach or d.length_squared() < 0.0001:
			continue
		var n: Vector2 = d.normalized()
		ball["p"] = at + n * reach
		var v: Vector2 = ball["v"]
		var vn: float = v.dot(n)
		if vn < 0.0:
			v -= n * vn * 1.5
		ball["v"] = v + n * 380.0
		if float(r["flash"]) > 0.0:
			continue
		r["flash"] = 0.2
		r["hp"] = int(r["hp"]) - 1
		if int(r["hp"]) > 0:
			_gain(30000, at + Vector2(0, -60), COLOURS["earth"].lightened(0.3))
			_burst(at, COLOURS["earth"].lightened(0.2), 8)
		else:
			r["gone"] = true
			stats["rocks"] += 1
			_gain(75000, at + Vector2(0, -60), COLOURS["earth"].lightened(0.3))
			_burst(at, COLOURS["earth"].lightened(0.2), 24)


func _feel(ball: Dictionary, dt: float) -> void:
	"""THE BALL FEELS THE LAND: floats in the tide, skates on frost, is
	held up by the updraft, thrown by a vent - once the warning is over."""
	if effect.is_empty() or t < float(effect["from"]):
		return
	var k: float = _fx_k()
	var p: Vector2 = ball["p"]
	match str(effect["land"]):
		"water":
			# lighter than water: lifted by the share of it under the surface
			var under: float = clampf((p.y + BALL_R - _surface_at(p.x, floor_of(p.y))) / (BALL_R * 2.0), 0.0, 1.0)
			if under > 0.0:
				var v: Vector2 = ball["v"] * (1.0 - TIDE_DRAG * under * dt * k)
				v.y -= GRAVITY * TIDE_BUOY * under * dt * k
				ball["v"] = v
		"wind":
			# THE UPDRAFT (0.168.3): the gale blew sideways, and halved and
			# stilled over the flippers (0.168.0) it still blew the ball into
			# the outlane on its side - 22 of 150 balls against 4 in still air.
			# The owner: "keep blowing the ball into the gutter", and he chose
			# an updraft over gusts that swing or a wind to the middle. It
			# blows up the table: the ball hangs and falls slower, its fall
			# eased toward UPDRAFT_FALL; never pushed sideways.
			var v: Vector2 = ball["v"]
			v.y -= GRAVITY * UPDRAFT_LIFT * dt * k
			if v.y > UPDRAFT_FALL:
				v.y = lerpf(v.y, UPDRAFT_FALL, minf(1.0, UPDRAFT_EASE * dt * k))
			ball["v"] = v
		"ice":
			var v: Vector2 = ball["v"]
			if v.length() < 1300.0:
				ball["v"] = v * (1.0 + 0.5 * dt * k)
		"fire":
			var fl: int = floor_of(p.y)
			for i in 3:
				var vent: Vector2 = VENTS[fl][i]
				if _vent_on(i) and p.distance_to(vent) < 46.0 and t - float(ball.get("vent_t", -9.0)) > 0.5:
					ball["vent_t"] = t
					ball["v"] = Vector2(rng.randf_range(-280.0, 280.0), -1250.0)
					stats["vents"] += 1
					_gain(40000, vent + Vector2(0, -60), COLOURS["fire"])
					_burst(vent, COLOURS["fire"], 16)


func _axes(ball: Dictionary) -> void:
	"""THE WARRIOR'S AXES spin round every ball while the whirlwind lasts."""
	if whirl_t <= 0.0:
		return
	var p: Vector2 = ball["p"]
	for j in 2:
		var a: float = t * 9.0 + j * PI
		var at: Vector2 = p + Vector2(cos(a), sin(a)) * 48.0
		for m in mobs:
			if int(m["fl"]) == floor_of(p.y) and _alive(m) and at.distance_to(_mob_at(m)) < float(m["r"]) + 12.0:
				_wound(m, 1, _mob_at(m), true)
		for r in rocks:
			if not r["gone"] and t >= float(r["land"]) and at.distance_to(r["p"]) < 30.0 and float(r["flash"]) <= 0.0:
				_break_rock(r, true)
		for h in horde:
			if _horde_on(h) and int(h["fl"]) == floor_of(p.y) and at.distance_to(_horde_at(h)) < 30.0:
				_splat(h, true)


static func _thousands(n: int) -> String:
	var s: String = str(absi(n))
	var out: String = ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out



# =============================================================================
# THE TABLE IN 3D
# =============================================================================

var world: Node3D
var cam3: Camera3D
var floor_vp: SubViewport
var floor_node: Node2D
var moving_vps: Array = []
var moving_nodes: Array = []
var floor_boxes: Array = []
var floor_seen: Array = [true, true, true]
var eye_vps: Array = []
var eye_floor: Array = []
var band_lo: float = 0.0
var band_hi: float = 0.0
const FLOOR_TOP := [2400.0, 1200.0, 0.0]
const FLOOR_SHADER := """shader_type spatial;
// the floor: what never changes (painted once) under what moves (painted
// while this floor is on screen) - the moving layer's colour comes
// premultiplied, as a canvas on a clear target leaves it
uniform sampler2D still : source_color, filter_linear;
uniform sampler2D moving : source_color, filter_linear;
uniform vec2 still_scale = vec2(1.0);
uniform vec2 still_offset = vec2(0.0);
uniform float glow = 0.5;
void fragment() {
	vec4 s = texture(still, UV * still_scale + still_offset);
	vec4 m = texture(moving, UV);
	float a = m.a + s.a * (1.0 - m.a);
	if (a < 0.5) {
		discard;
	}
	vec3 c = m.rgb + s.rgb * (1.0 - m.a);
	ALBEDO = c;
	EMISSION = c * glow;
	ROUGHNESS = 0.35;
}
"""
var eye_nodes: Array = []
var eye_lights: Array = []
var hud_node: Node2D
# the panel down the right, painted on its own (every PHONE_EVERY frames on a phone)
var panel_node: Node2D
var _paint_frame: int = 0
var back_node: Node2D
var cv: CanvasItem
var ball_nodes: Array = []
var ball_mats: Array = []
var flipper_nodes: Array = []
var target_nodes: Array = []
var gate_nodes: Array = []
var kick_nodes: Array = []
var plunger_node: MeshInstance3D
var portal_node: Node3D
var portal_light: OmniLight3D
var beam_node: Node3D
var shield_node: MeshInstance3D
var slime_node: Sprite3D
var slime_frames: Array = []
var beholder_light: OmniLight3D
var pip_vp: SubViewport
var pip_cam: Camera3D
var pip_ball: Dictionary = {}
var pip_look := Vector3.ZERO
var look := Vector3.ZERO
var pull_back: float = 1.0
var cam_floor: int = 0
var focus_ball: Dictionary = {}
var mob_frames: Dictionary = {}
var horde_nodes: Array = []
var rock_nodes: Array = []
var axe_nodes: Array = []
var axe_frames: Array = []
var hero_frames: Dictionary = {}
var hero_tex: Dictionary = {}
var mage_node: Sprite3D
var tank_node: Sprite3D
var ring_node: Sprite3D
var ring_frames: Array = []
var healer_node: Sprite3D
var aura_node: Sprite3D
var aura_frames: Array = []
var lock_node: MeshInstance3D
var lock_mat: StandardMaterial3D
var crystal: MeshInstance3D
var tower_light: OmniLight3D
var sun_light: DirectionalLight3D
var world_env: Environment
var fills: Array = []
var floor_mats: Array = []
var tiles: Dictionary = {}
var flowers: Dictionary = {}
var meteor_tex: Texture2D
var pack: Dictionary = {}
var extra_keep: Array = []
var still_joined: int = 0
var loot_nodes: Array = []


func _w(p: Vector2, y: float = 0.0) -> Vector3:
	return Vector3(p.x * S - W * S / 2.0, y, p.y * S - H * S / 2.0)


func _mat(c: Color, metal: float = 0.0, rough: float = 0.5, glow: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = glow
	return m


func _put(mesh: Mesh, m: Material, at: Vector3, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = at
	(parent if parent != null else world).add_child(mi)
	return mi


func _box_between(a: Vector2, b: Vector2, base: float, high: float, thick: float, m: Material) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = Vector3(a.distance_to(b) * S + thick, high, thick)
	var mi: MeshInstance3D = _put(bm, m, _w((a + b) / 2.0, base + high / 2.0))
	mi.rotation.y = -(b - a).angle()
	return mi


func _cyl(r: float, h: float, m: Material, at: Vector3, r_bottom: float = -1.0) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r if r_bottom < 0.0 else r_bottom
	cm.height = h
	cm.radial_segments = 28
	return _put(cm, m, at)


func _light_at(p: Vector3, c: Color, reach: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = c
	l.omni_range = reach
	l.position = p
	l.visible = not light
	world.add_child(l)
	return l


func _eye_dome(at: Vector2, r: float, base: float, node: Node2D) -> MeshInstance3D:
	"""An eye: a dome with the eye painted on it, seen from above."""
	var vp := SubViewport.new()
	var k: float = PHONE_PAINT if light else 1.0
	vp.size = Vector2i(int(256 * k), int(256 * k))
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	eye_vps.append(vp)
	eye_floor.append(floor_of(at.y))
	node.scale *= k
	vp.add_child(node)
	var dome := SphereMesh.new()
	dome.radius = r * S
	dome.height = r * S
	dome.is_hemisphere = true
	dome.radial_segments = 48
	dome.rings = 24
	var sh := Shader.new()
	sh.code = """shader_type spatial;
uniform sampler2D tex : source_color, filter_linear;
uniform float radius = 1.0;
varying vec2 top_uv;
void vertex() { top_uv = VERTEX.xz / (2.0 * radius) + 0.5; }
void fragment() { vec4 c = texture(tex, top_uv); ALBEDO = c.rgb; EMISSION = c.rgb * 0.3; ROUGHNESS = 0.35; }
"""
	var em := ShaderMaterial.new()
	em.shader = sh
	em.set_shader_parameter("tex", vp.get_texture())
	em.set_shader_parameter("radius", r * S)
	var d: MeshInstance3D = _put(dome, em, _w(at, base))
	d.scale = Vector3(1, 0.75, 1)
	var ring := TorusMesh.new()
	ring.inner_radius = r * S * 0.98
	ring.outer_radius = r * S * 1.14
	_put(ring, _mat(GOLD.darkened(0.15), 0.85, 0.3), _w(at, base + 0.02))
	return d


func _frames(path: String, y: int, size: int, n: int) -> Array:
	var tex: Texture2D = load(path)
	var out: Array = []
	for i in n:
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(i * size, y, size, size)
		out.append(at)
	return out


func _sprite(ps: float) -> Sprite3D:
	var sp := Sprite3D.new()
	sp.pixel_size = ps
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sp.shaded = false
	sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(sp)
	return sp


func _tile(path: String, x: int, y: int, size: int = 32, scale: int = 2) -> ImageTexture:
	"""One cell of the owner's tiles, doubled with nearest - the floors are
	his town, his field and his lair."""
	var img: Image = (load(path) as Texture2D).get_image()
	if img.is_compressed():
		img.decompress()
	var cell: Image = img.get_region(Rect2i(x, y, size, size))
	cell.resize(size * scale, size * scale, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(cell)


func _build_world() -> void:
	world = Node3D.new()
	add_child(world)
	tiles = {"grass": _tile("res://art/tiles/tiles2.png", 32, 32), "cobble": _tile("res://art/tiles/tiles5.png", 32, 32),
		"dirt": _tile("res://art/tiles/tiles3.png", 64, 64), "snow": _tile("res://art/tiles/tiles7.png", 64, 64),
		"lavarock": _tile("res://art/tiles/tiles8.png", 64, 64), "water": _tile("res://art/tiles/propsandterrain.png", 32, 128),
		"lava": _tile("res://art/tiles/propsandterrain.png", 32, 160), "sand": _tile("res://art/tiles/underground.png", 32, 160)}
	for f in ["redflower", "whiteflower", "plant", "plant2", "plant3"]:
		flowers[f] = load("res://art/tiles/%s.png" % f)
	meteor_tex = load("res://art/maincharacter/meteor.png")
	for el in ORDER:
		pack["ess_" + el] = load("res://art/pack/materials/%sessence.png" % el)
	for el in EYE_ORDER + ["crowned"]:
		pack["eye_" + el] = load("res://art/pack/materials/%sbeholdereye.png" % el)
	for c in ["coppercoin", "silvercoin", "goldcoin", "goldpile"]:
		pack[c] = load("res://art/pack/currency/%s.png" % c)
	pack["lootbag"] = load("res://art/pack/tiles/lootbag2.png")
	for p in ["largehealthpotion", "greaterhealthpotion"]:
		pack[p] = load("res://art/pack/consumables/%s.png" % p)
	# THE FLOOR: what never changes painted once, whole; what moves painted
	# per floor, and only while that floor is on screen
	floor_vp = SubViewport.new()
	floor_vp.size = Vector2i(int(W), int(H))
	floor_vp.transparent_bg = true
	floor_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(floor_vp)
	floor_node = Node2D.new()
	floor_node.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	floor_node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	floor_vp.add_child(floor_node)
	floor_node.draw.connect(_paint_still)
	var floor_sh := Shader.new()
	floor_sh.code = FLOOR_SHADER
	for fl in 3:
		var top: float = FLOOR_TOP[fl]
		var mvp := SubViewport.new()
		var k: float = PHONE_PAINT if light else 1.0
		mvp.size = Vector2i(int(W * k), int(1200 * k))
		mvp.transparent_bg = true
		mvp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(mvp)
		var mn := Node2D.new()
		mn.scale = Vector2(k, k)
		mn.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		mn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		mvp.add_child(mn)
		mn.draw.connect(_paint_moving.bind(fl, mn))
		moving_vps.append(mvp)
		moving_nodes.append(mn)
		var plane := PlaneMesh.new()
		plane.size = Vector2(W * S, 1200.0 * S)
		var fm := ShaderMaterial.new()
		fm.shader = floor_sh
		fm.set_shader_parameter("still", floor_vp.get_texture())
		fm.set_shader_parameter("moving", mvp.get_texture())
		fm.set_shader_parameter("still_scale", Vector2(1, 1200.0 / H))
		fm.set_shader_parameter("still_offset", Vector2(0, top / H))
		floor_mats.append(fm)
		var pm: MeshInstance3D = _put(plane, fm, _w(Vector2(W / 2.0, top + 600.0), float(FLOORS[fl]["h"])))
		pm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		floor_boxes.append(AABB(pm.position + plane.get_aabb().position - Vector3(0, 0.05, 0), plane.get_aabb().size + Vector3(0, 0.6, 0)))
	var stone := _mat(Color(0.14, 0.09, 0.2), 0.1, 0.8)
	var trim := _mat(GOLD.darkened(0.15), 0.85, 0.3)
	trim.emission_enabled = true
	trim.emission = GOLD
	trim.emission_energy_multiplier = 0.0
	glow_mats.append([trim, 0.9])
	for c in [[1200.0, 0.6, 1.2], [2400.0, 0.0, 0.6]]:
		var bm := BoxMesh.new()
		bm.size = Vector3(W * S, c[2] - c[1], 0.1)
		_put(bm, stone, _w(Vector2(W / 2.0, c[0]), (c[1] + c[2]) / 2.0) + Vector3(0, 0, -0.05))
		var edge := BoxMesh.new()
		edge.size = Vector3(W * S, 0.03, 0.06)
		_put(edge, trim, _w(Vector2(W / 2.0, c[0]), c[2] + 0.015))
	var wood := _mat(Color(0.16, 0.08, 0.2), 0.2, 0.55)
	for x in [-6.0, 1246.0]:
		var bm := BoxMesh.new()
		bm.size = Vector3(0.24, 1.9, H * S)
		_put(bm, wood, _w(Vector2(x, H / 2.0), 0.45))
		var top := BoxMesh.new()
		top.size = Vector3(0.26, 0.03, H * S)
		_put(top, trim, _w(Vector2(x, H / 2.0), 1.41))
	# the walls, the rails and the posts
	var rail := _mat(Color(0.82, 0.72, 0.5), 0.9, 0.25)
	rail.emission_enabled = true
	rail.emission = Color(1.0, 0.85, 0.55)
	rail.emission_energy_multiplier = 0.0
	glow_mats.append([rail, 1.4])
	var rubber := _mat(Color(0.95, 0.93, 0.88), 0.0, 0.6)
	for s in segs:
		var a: Vector2 = s["a"]
		var b: Vector2 = s["b"]
		if s == plunger_seg:
			continue
		var h: float = height_at((a.y + b.y) / 2.0)
		match str(s["kind"]):
			"outer":
				_box_between(a, b, h, 0.3, 0.1, wood)
				_box_between(a, b, h + 0.3, 0.02, 0.12, trim)
			"kick":
				kick_nodes.append(_box_between(a, b, h, 0.14, 0.07, _mat(KICK_CREAM, 0.0, 0.5, 0.2)))
			"gate":
				_box_between(a, b, h, 0.1, 0.02, trim)
			"lock":
				var g: MeshInstance3D = _box_between(a, b, h, 0.3, 0.06, _mat(Color(0.95, 0.3, 0.25), 0.4, 0.3, 0.6))
				gate_nodes.append([g, s, h])
			"shield":
				var sm := _mat(HERO["TANK"], 0.0, 0.2, 2.2)
				sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				sm.albedo_color = Color(HERO["TANK"], 0.7)
				shield_node = _box_between(a, b, h, 0.1, 0.06, sm)
			_:
				_box_between(a, b, h, 0.16, 0.05, rail)
	var posts: Array = [Vector2(110, 2730), Vector2(110, 2900), Vector2(ORBIT_X, 2700), Vector2(ORBIT_X, 2900)]
	for ls in LANE_SETS:
		for x in ls["xs"]:
			posts.append(Vector2(float(x), float(ls["top"])))
	for fl in 3:
		var yb: float = FLOORS[fl]["yb"]
		for side in [1.0, -1.0]:
			var tops: Array = [Vector2(330, yb - 360), Vector2(372, yb - 350), Vector2(PRONG_TIP.x, yb - PRONG_TIP.y)] if fl == 0 \
				else [Vector2(326, yb - 336), Vector2(372, yb - 350)]
			for p in tops:
				posts.append(Vector2(p.x if side > 0.0 else _mx(p.x), p.y))
			var tri: Array = [Vector2(372, yb - 350), Vector2(372, yb - 262), Vector2(430, yb - 215)]
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			st.set_normal(Vector3.UP)
			for v in tri:
				st.add_vertex(_w(Vector2(v.x if side > 0.0 else _mx(v.x), v.y), float(FLOORS[fl]["h"]) + 0.14))
			var tm := _mat(Color(0.22, 0.12, 0.3), 0.1, 0.5)
			tm.cull_mode = BaseMaterial3D.CULL_DISABLED
			_put(st.commit(), tm, Vector3.ZERO)
	for p in posts:
		_cyl(0.06, 0.2, rubber, _w(p, height_at(p.y) + 0.1))
		_cyl(0.035, 0.04, trim, _w(p, height_at(p.y) + 0.22))
	# the pop bumpers
	for b in bumpers:
		var c: Color = COLOURS[b["el"]]
		var p: Vector2 = b["p"]
		var h: float = height_at(p.y)
		var r: float = float(b["r"]) * S
		_cyl(r * 1.3, 0.03, trim, _w(p, h + 0.015))
		b["body"] = _cyl(r, 0.22, _mat(c, 0.2, 0.35, 0.3), _w(p, h + 0.13), r * 1.08)
		b["cap"] = _cyl(r * 0.72, 0.05, _mat(Color(0.98, 0.96, 0.9), 0.0, 0.3, 0.2), _w(p, h + 0.265))
		b["light"] = _light_at(_w(p, h + 0.7), c, 1.6)
		var ess: Sprite3D = _sprite(float(b["r"]) * S * 1.3 / 14.0)
		ess.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		ess.axis = Vector3.AXIS_Y
		ess.texture = pack["ess_" + str(b["el"])]
		b["ess"] = ess
	# the two eyes, and the Beholder
	for e in eyes:
		var n := Node2D.new()
		n.draw.connect(_paint_eye.bind(e, n))
		_eye_dome(e["p"], EYE_R, 0.6, n)
		eye_nodes.append(n)
		eye_lights.append(_light_at(_w(e["p"], 1.5), COLOURS["dark"].lightened(0.3), 2.6))
	var bn := Node2D.new()
	bn.draw.connect(_paint_eye.bind(beholder, bn))
	_eye_dome(BEHOLDER, BEHOLDER_R, 1.2, bn)
	eye_nodes.append(bn)
	beholder_light = _light_at(_w(BEHOLDER, 2.6), COLOURS["dark"].lightened(0.35), 4.0)
	beam_node = Node3D.new()
	beam_node.position = _w(BEHOLDER, 1.23)
	world.add_child(beam_node)
	var beam := BoxMesh.new()
	beam.size = Vector3(5.2, 0.02, 0.36)
	var bmat := _mat(Color(1.0, 0.25, 0.3), 0.0, 0.5, 2.0)
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.albedo_color = Color(1.0, 0.25, 0.3, 0.45)
	_put(beam, bmat, Vector3(1.0 + 2.6, 0, 0), beam_node)
	# the lair and the Portal's scoop: rings round the holes
	for hole in [[LAIR, 1.21], [PORTAL, 0.01]]:
		var lring := TorusMesh.new()
		lring.inner_radius = 0.22
		lring.outer_radius = 0.3
		_put(lring, trim, _w(hole[0], hole[1]))
	# THE PORTAL: a ring stood on end, turning
	portal_node = Node3D.new()
	portal_node.position = _w(PORTAL_RING, 0.47)
	world.add_child(portal_node)
	var pring := TorusMesh.new()
	pring.inner_radius = 0.36
	pring.outer_radius = 0.45
	pring.rings = 48
	var pr: MeshInstance3D = _put(pring, _mat(COLOURS["dark"].lightened(0.25), 0.6, 0.3, 1.2), Vector3.ZERO, portal_node)
	pr.rotation.x = PI / 2.0
	var disc := QuadMesh.new()
	disc.size = Vector2(0.72, 0.72)
	var dmat := _mat(Color(0.55, 0.3, 1.0), 0.0, 0.5, 2.5)
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.albedo_color = Color(0.55, 0.3, 1.0, 0.35)
	dmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_put(disc, dmat, Vector3.ZERO, portal_node)
	for side in [-1.0, 1.0]:
		_cyl(0.04, 0.47, trim, _w(PORTAL_RING + Vector2(side * 45.0, 0), 0.235))
	portal_light = _light_at(_w(PORTAL_RING, 1.2), Color(0.6, 0.35, 1.0), 2.6)
	# the targets, the plunger
	for tg in targets:
		var r: Rect2 = tg["rect"]
		var bm := BoxMesh.new()
		bm.size = Vector3(r.size.x * S, 0.2, r.size.y * S)
		var c: Color = Color(0.5, 1.0, 0.55) if tg["el"] == "extra" else COLOURS[tg["el"]]
		target_nodes.append(_put(bm, _mat(c, 0.1, 0.4, 0.35), _w(r.get_center(), height_at(r.get_center().y) + 0.1)))
	var pm := BoxMesh.new()
	pm.size = Vector3(0.3, 0.12, 0.08)
	plunger_node = _put(pm, trim, _w(Vector2(1200, 3586), 0.06))
	# the ramps: clear channels on legs, wire rails along them
	var wire := _mat(Color(0.85, 0.9, 1.0), 0.9, 0.2)
	wire.emission_enabled = true
	wire.emission = Color(0.7, 0.85, 1.0)
	wire.emission_energy_multiplier = 0.0
	glow_mats.append([wire, 1.6])
	for r in ramps:
		var pts: Array = r["pts"]
		var high: Array = r["high"]
		var lefts: Array = []
		var rights: Array = []
		for i in pts.size():
			var a: Vector2 = pts[maxi(0, i - 1)]
			var b: Vector2 = pts[mini(pts.size() - 1, i + 1)]
			var n: Vector2 = (b - a).normalized().orthogonal()
			lefts.append(_w((pts[i] as Vector2) + n * 18.0, high[i]))
			rights.append(_w((pts[i] as Vector2) - n * 18.0, high[i]))
		var st2 := SurfaceTool.new()
		st2.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in pts.size() - 1:
			for v in [lefts[i], rights[i], lefts[i + 1], rights[i], rights[i + 1], lefts[i + 1]]:
				st2.set_normal(Vector3.UP)
				st2.add_vertex(v)
		var tint: Color = {"XL": HERO["WARR"], "XR": HERO["TANK"], "UP2": GOLD, "UP3": GOLD, "SPIRAL": COLOURS["dark"].lightened(0.4)}.get(r["name"], Color(0.55, 0.8, 1.0))
		var rmat := _mat(Color(tint, 0.3), 0.0, 0.1, 0.3)
		rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rmat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_put(st2.commit(), rmat, Vector3.ZERO)
		for side in [lefts, rights]:
			for i in side.size() - 1:
				var a3: Vector3 = side[i] + Vector3(0, 0.08, 0)
				var b3: Vector3 = side[i + 1] + Vector3(0, 0.08, 0)
				var bm := BoxMesh.new()
				bm.size = Vector3(a3.distance_to(b3), 0.02, 0.02)
				var mi: MeshInstance3D = _put(bm, wire, (a3 + b3) / 2.0)
				mi.look_at_from_position((a3 + b3) / 2.0, b3, Vector3.UP if absf((b3 - a3).normalized().y) < 0.99 else Vector3.RIGHT)
				mi.rotate_object_local(Vector3.UP, PI / 2.0)
		for i in range(2, pts.size() - 1, 3):
			for side in [lefts, rights]:
				var top3: Vector3 = side[i]
				var under: float = height_at((pts[i] as Vector2).y)
				if top3.y - under > 0.05:
					_cyl(0.015, top3.y - under, wire, Vector3(top3.x, (top3.y + under) / 2.0, top3.z))
	# THE MAGE'S TOWER: the owner's cobble, gold bands, a crystal on top
	var tmat := _mat(Color(0.72, 0.68, 0.82), 0.05, 0.85)
	tmat.albedo_texture = tiles["cobble"]
	tmat.uv1_scale = Vector3(4, 3, 1)
	tmat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	_cyl(0.42, TOWER_TOP, tmat, _w(TOWER, TOWER_TOP / 2.0), 0.47)
	for hh in [0.4, 0.85, 1.25]:
		var band := TorusMesh.new()
		band.inner_radius = 0.42
		band.outer_radius = 0.47
		_put(band, trim, _w(TOWER, hh))
	_cyl(0.5, 0.06, trim, _w(TOWER, TOWER_TOP + 0.03))
	var gem := SphereMesh.new()
	gem.radius = 0.11
	gem.height = 0.38
	gem.radial_segments = 6
	gem.rings = 2
	crystal = _put(gem, _mat(HERO["MAGE"], 0.2, 0.15, 2.2), _w(TOWER, TOWER_TOP + 0.5))
	tower_light = _light_at(_w(TOWER, TOWER_TOP + 0.8), HERO["MAGE"], 2.8)
	var lb := SphereMesh.new()
	lb.radius = BALL_R * S
	lb.height = BALL_R * S * 2.0
	lock_mat = _mat(Color(0.86, 0.88, 0.94), 0.55, 0.16, 1.4)
	lock_mat.emission = HERO["MAGE"]
	lock_node = _put(lb, lock_mat, _w(TOWER, TOWER_TOP + 0.06 + BALL_R * S))
	# THE MONSTERS: the owner's sheets, a sprite each
	for kind in MOB_ART:
		var a: Dictionary = MOB_ART[kind]
		mob_frames[kind] = {"right": _frames(a["tex"], a["right"], a["size"], a["n"]),
			"left": _frames(a["tex"], a["left"], a["size"], a["n"])}
	for m in mobs:
		m["node"] = _sprite(float(MOB_ART[m["kind"]]["ps"]))
	for i in 7:
		horde_nodes.append(_sprite(0.02))
	for i in 5:
		var rn: Sprite3D = _sprite(0.012)
		rn.texture = load("res://art/tiles/c92.png")
		rock_nodes.append(rn)
	for i in 40:
		loot_nodes.append(_sprite(0.02))
	axe_frames = _frames("res://art/maincharacter/axe.png", 0, 24, 4)
	for i in 8:
		axe_nodes.append(_sprite(0.02))
	# THE HEROES: the owner's class sheets
	for w in HERO_ART:
		var a: Dictionary = HERO_ART[w]
		hero_tex[w] = load(a["tex"])
		var fr: Array = []
		for row in a["rows"]:
			fr.append_array(_frames(a["tex"], row[0], a["size"], row[1]))
		hero_frames[w] = fr
	mage_node = _sprite(float(HERO_ART["MAGE"]["ps"]))
	tank_node = _sprite(float(HERO_ART["TANK"]["ps"]) * 0.8)
	healer_node = _sprite(float(HERO_ART["HEAL"]["ps"]))
	ring_frames = _frames("res://art/maincharacter/smalltankring.png", 0, 128, 6)
	ring_node = _sprite(0.011)
	aura_frames = _frames("res://art/maincharacter/healaura.png", 0, 64, 25)
	aura_node = _sprite(0.026)
	# THE OWNER'S TOWN: trees and bushes in the corners, pillars in the lair
	for d in [["largetree", Vector2(130, 3330), 0.024, 25.0], ["largetree", Vector2(195, 3520), 0.024, 25.0],
			["largetree", Vector2(1070, 3330), 0.024, 25.0], ["largetree", Vector2(1005, 3520), 0.024, 25.0],
			["bush", Vector2(232, 3410), 0.02, 15.0], ["bush", Vector2(968, 3410), 0.02, 15.0],
			["largetree", Vector2(110, 2140), 0.022, 25.0], ["bush", Vector2(220, 2250), 0.02, 15.0],
			["largetree", Vector2(1090, 2140), 0.022, 25.0], ["bush", Vector2(980, 2250), 0.02, 15.0],
			["c122", Vector2(140, 900), 0.016, 28.0], ["c125", Vector2(240, 1030), 0.016, 28.0],
			["c122", Vector2(1060, 900), 0.016, 28.0], ["c125", Vector2(960, 1030), 0.016, 28.0]]:
		var ds: Sprite3D = _sprite(d[2])
		ds.texture = load("res://art/tiles/%s.png" % d[0])
		ds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		ds.position = _w(d[1], height_at((d[1] as Vector2).y) + float(d[3]) * float(d[2]))
	# the flippers
	for f in flippers:
		var pivot := Node3D.new()
		pivot.position = _w(f["pivot"], height_at((f["pivot"] as Vector2).y) + 0.07)
		world.add_child(pivot)
		var len: float = float(f["len"]) * S
		var ivory := _mat(Color(0.97, 0.95, 0.9), 0.0, 0.3)
		var fb := BoxMesh.new()
		fb.size = Vector3(len, 0.12, 0.17)
		_put(fb, ivory, Vector3(len / 2.0, 0, 0), pivot)
		var tip := CylinderMesh.new()
		tip.top_radius = 0.075
		tip.bottom_radius = 0.075
		tip.height = 0.12
		_put(tip, ivory, Vector3(len, 0, 0), pivot)
		var base := CylinderMesh.new()
		base.top_radius = 0.12
		base.bottom_radius = 0.12
		base.height = 0.13
		_put(base, ivory, Vector3.ZERO, pivot)
		var stripe := BoxMesh.new()
		stripe.size = Vector3(len * 0.9, 0.125, 0.05)
		var fc: Color = GOLD if f.get("upper", false) else [COLOURS["fire"], COLOURS["dark"].lightened(0.2), COLOURS["light"]][int(f["floor"])]
		var smat := _mat(fc, 0.0, 0.4, 0.5)
		stripe_mats.append(smat)
		_put(stripe, smat, Vector3(len / 2.0, 0.003, 0), pivot)
		var cap := CylinderMesh.new()
		cap.top_radius = 0.05
		cap.bottom_radius = 0.05
		cap.height = 0.14
		_put(cap, trim, Vector3.ZERO, pivot)
		flipper_nodes.append(pivot)
	# the balls, each its own material so a land can colour it
	for i in 4:
		var sm := SphereMesh.new()
		sm.radius = BALL_R * S
		sm.height = BALL_R * S * 2.0
		var chrome := _mat(Color(0.86, 0.88, 0.94), 0.55, 0.16)
		chrome.emission_enabled = true
		chrome.emission = Color.BLACK
		var mi: MeshInstance3D = _put(sm, chrome, Vector3.ZERO)
		mi.visible = false
		ball_nodes.append(mi)
		ball_mats.append(chrome)
	# THE SLIME: the owner's own slime, hopping across the ground floor
	var sheet: Texture2D = load("res://art/enemy/slime.png")
	for i in 5:
		var at := AtlasTexture.new()
		at.atlas = sheet
		at.region = Rect2(i * 48, 720, 48, 48)
		slime_frames.append(at)
	slime_node = Sprite3D.new()
	slime_node.texture = slime_frames[0]
	slime_node.pixel_size = 0.016
	slime_node.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	slime_node.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	slime_node.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	slime_node.shaded = false
	world.add_child(slime_node)
	# light, the sky for the chrome, the void behind, the camera
	var env := Environment.new()
	world_env = env
	env.background_mode = Environment.BG_CANVAS
	env.background_canvas_max_layer = -1
	var sky := Sky.new()
	var skym := ProceduralSkyMaterial.new()
	skym.sky_top_color = Color(0.35, 0.3, 0.6)
	skym.sky_horizon_color = Color(0.9, 0.7, 0.5)
	skym.ground_bottom_color = Color(0.1, 0.05, 0.15)
	skym.ground_horizon_color = Color(0.5, 0.35, 0.4)
	sky.sky_material = skym
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.4, 0.6)
	env.ambient_light_energy = PHONE_AMBIENT if light else 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.glow_enabled = not light
	env.glow_intensity = 0.7
	env.glow_bloom = 0.08
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun_light = sun
	sun.light_energy = 0.75
	sun.shadow_enabled = not light
	sun.directional_shadow_max_distance = 16.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.rotation = Vector3(deg_to_rad(-60), deg_to_rad(16), 0)
	world.add_child(sun)
	for p in [Vector2(400, 3250), Vector2(800, 3250), Vector2(350, 2700), Vector2(850, 2800), Vector2(400, 1950),
			Vector2(800, 1950), Vector2(600, 1500), Vector2(600, 800)]:
		var fill: OmniLight3D = _light_at(_w(p, height_at(p.y) + 1.8), Color(1.0, 0.85, 0.65), 4.5)
		fill.light_energy = 0.55
		fill.visible = not light
		fills.append(fill)
	if light:
		get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		get_viewport().scaling_3d_scale = PHONE_3D_SCALE
	cam3 = Camera3D.new()
	cam3.fov = CAM_FOV
	world.add_child(cam3)
	cam3.current = true
	cam3.h_offset = CAM_SIDE
	# the window onto a ball on another floor: a second camera, the same world
	var back_layer := CanvasLayer.new()
	back_layer.layer = -1
	add_child(back_layer)
	back_node = Node2D.new()
	back_layer.add_child(back_node)
	back_node.draw.connect(_paint_back)
	var layer := CanvasLayer.new()
	add_child(layer)
	panel_node = Node2D.new()
	panel_node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	layer.add_child(panel_node)
	panel_node.draw.connect(_paint_panel_layer)
	hud_node = Node2D.new()
	hud_node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	layer.add_child(hud_node)
	hud_node.draw.connect(_paint_hud)
	_build_new()
	_merge_still()
	_follow(true)
	_sync_world()


const CELL := 400.0


func _merge_still() -> void:
	"""THE STILL PIECES IN A FEW MESHES: every mesh straight under the world
	that never moves is joined with the others of its material in its CELL
	of the table - hundreds of rails, walls, posts and rims become a few
	dozen draws. A material shared keeps glowing as one (the blackout's).
	What moves, flashes on its own or hides is left alone."""
	var keep: Dictionary = {}
	for n in ball_nodes + target_nodes + kick_nodes + [plunger_node, shield_node, crystal, lock_node]:
		keep[n] = true
	for g in gate_nodes:
		keep[g[0]] = true
	for b in bumpers:
		keep[b["body"]] = true
		keep[b["cap"]] = true
	for n in extra_keep:
		keep[n] = true
	var groups: Dictionary = {}
	for ch in world.get_children():
		if not (ch is MeshInstance3D) or keep.has(ch):
			continue
		var mi: MeshInstance3D = ch
		if mi.material_override == null or mi.mesh == null or mi.mesh.get_surface_count() != 1 or not mi.visible:
			continue
		var at: Vector3 = mi.global_transform * mi.mesh.get_aabb().get_center()
		var cell := Vector2i(int(floor((at.x / S + W / 2.0) / CELL)), int(floor((at.z / S + H / 2.0) / CELL)))
		var key: Array = [mi.material_override, mi.mesh is PrimitiveMesh, cell,
			mi.cast_shadow]
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(mi)
	var joined: int = 0
	for key in groups:
		var list: Array = groups[key]
		if list.size() < 2:
			continue
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for mi in list:
			st.append_from((mi as MeshInstance3D).mesh, 0, (mi as MeshInstance3D).transform)
		var one := MeshInstance3D.new()
		one.mesh = st.commit()
		one.material_override = key[0]
		one.cast_shadow = key[3]
		world.add_child(one)
		for mi in list:
			world.remove_child(mi)
			(mi as Node).queue_free()
		joined += list.size()
	still_joined = joined


func _focus() -> Dictionary:
	"""The ball the camera follows: one climbing to a new floor or sunk in a
	scoop takes it; else the one it had; else the lowest."""
	for ball in balls:
		var ride: String = ball.get("ride", "")
		if ride == "UP2" or ride == "UP3" or ride == "TOWER" or ball.has("sunk"):
			focus_ball = ball
			return ball
	for ball in balls:
		if is_same(ball, focus_ball):
			return ball
	var best: Dictionary = balls[0]
	for ball in balls:
		if (ball["p"] as Vector2).y > (best["p"] as Vector2).y:
			best = ball
	focus_ball = best
	return best


func _ball_height(ball: Dictionary) -> float:
	if ball.has("ride"):
		return float(ball.get("lift", 0.0)) + 0.02
	return height_at((ball["p"] as Vector2).y) - (0.06 if ball.has("sunk") else 0.0)


func _follow(snap: bool, dt: float = 1.0 / 60.0) -> void:
	"""THE CAMERA slides up and down the table only - never sideways - and
	lets the ball move inside a window before it follows, easing there
	(the sandbox's camera chased the ball's every move: "a little wobbly").
	With more than one ball on its floor it pulls back to hold them all."""
	if cam3 == null or balls.is_empty():
		return
	var ball: Dictionary = _focus()
	var p: Vector2 = ball["p"]
	var fl: int = floor_of(p.y)
	var mid: Vector2 = p
	var spread: float = 0.0
	var count: int = 1
	pip_ball = {}
	for other in balls:
		if is_same(other, ball) or other["held"]:
			continue
		var q: Vector2 = other["p"]
		if floor_of(q.y) == fl:
			if not other.has("ride"):
				mid += q
				count += 1
				spread = maxf(spread, q.distance_to(p))
		elif pip_ball.is_empty():
			pip_ball = other
	mid /= float(count)
	# a falling ball is followed faster (0.168.2): up to CAM_FAST more a
	# second at FALL_FAST px/s, so the view is down on the flippers before it
	var falling: float = 0.0
	if not ball["held"] and not ball.has("ride") and not ball.has("sunk"):
		falling = clampf(float((ball["v"] as Vector2).y) / FALL_FAST, 0.0, 1.0)
	var k: float = 1.0 if snap else 1.0 - exp(-dt * (3.2 + CAM_FAST * falling))
	var want_pull: float = clampf(1.0 + (spread - 250.0) / 800.0, 1.0, 1.75)
	pull_back = want_pull if snap else lerpf(pull_back, want_pull, k * 0.5)
	# LOOK AHEAD (0.168.2): the owner, "when the ball is falling fast the camera
	# dousnt track it very well and it flies past my flippers before i can
	# see" - eased at 3.2 a second, a ball at 2,000 px/s ran 600 px ahead of
	# it, off the foot of the screen with the flippers. The camera now aims
	# CAM_LEAD seconds along the ball's way (at most LEAD_MOST px/s of it)...
	var ahead: float = 0.0
	if not ball["held"] and not ball.has("ride") and not ball.has("sunk"):
		ahead = clampf(float((ball["v"] as Vector2).y), -LEAD_MOST, LEAD_MOST) * CAM_LEAD
	var aim_y: float = mid.y + ahead
	# the slack: the ball may wander 170 px up and 110 down before it pulls
	var want_y: float = cam_y
	if snap:
		want_y = mid.y
	elif aim_y < cam_y - 170.0:
		want_y = aim_y + 170.0
	elif aim_y > cam_y + 110.0:
		want_y = aim_y - 110.0
	# never past the floor's foot (0.168.0): a ball on the plunger is at the
	# very bottom, and the view fell half off the table into the stars
	want_y = minf(want_y, float(FLOORS[fl]["yb"]) - CAM_FOOT)
	cam_y = lerpf(cam_y, want_y, k)
	# ...and never lets it out of sight: no more than CAM_DOWN below its line
	# (the screen shows 240) nor CAM_UP above - past that it moves with the
	# ball, that frame. The floor's foot still holds it.
	cam_y = clampf(cam_y, p.y - CAM_DOWN, p.y + CAM_UP)
	cam_y = minf(cam_y, float(FLOORS[fl]["yb"]) - CAM_FOOT)
	cam_h = lerpf(cam_h, _ball_height(ball), k)
	look = _w(Vector2(CX, cam_y - 150.0), cam_h)
	cam3.position = look + Vector3(0, 6.6, 5.6) * pull_back
	cam3.look_at(look, Vector3.UP)
	if shake > 0.0:
		cam3.position += Vector3(sin(t * 61.0), sin(t * 47.0) * 0.6, 0.0) * shake * 0.05
	cam_floor = fl


func _sync_world() -> void:
	for i in ball_nodes.size():
		var mi: MeshInstance3D = ball_nodes[i]
		if i >= balls.size():
			mi.visible = false
			continue
		var ball: Dictionary = balls[i]
		mi.visible = true
		mi.position = _w(ball["p"], _ball_height(ball) + BALL_R * S)
		var m: StandardMaterial3D = ball_mats[i]
		var tint: Color = ball["tint"]
		m.emission = Color.BLACK if tint == INK else tint
		m.emission_energy_multiplier = 0.0 if tint == INK else (0.9 + (1.5 if whirl_t > 0.0 else 0.0))
		if _effect_is("dark"):
			m.emission = Color(0.85, 0.75, 1.0) if tint == INK else tint
			m.emission_energy_multiplier = maxf(m.emission_energy_multiplier, 2.4 * _fx_k())
	for i in flippers.size():
		(flipper_nodes[i] as Node3D).rotation.y = -_dir(flippers[i]).angle()
	for b in bumpers:
		var f: float = b["flash"]
		(b["light"] as OmniLight3D).light_energy = 0.35 + 3.0 * f
		((b["body"] as MeshInstance3D).material_override as StandardMaterial3D).emission_energy_multiplier = 0.3 + 2.2 * f
		(b["cap"] as MeshInstance3D).position.y = height_at((b["p"] as Vector2).y) + 0.265 - 0.05 * f
		(b["ess"] as Sprite3D).position = _w(b["p"], height_at((b["p"] as Vector2).y) + 0.293 - 0.05 * f)
	for i in targets.size():
		var th: float = height_at((targets[i]["rect"] as Rect2).get_center().y)
		(target_nodes[i] as MeshInstance3D).position.y = th + (-0.2 if targets[i]["down"] else 0.1)
	for g in gate_nodes:
		var s: Dictionary = g[1]
		var node: MeshInstance3D = g[0]
		var want: float = float(g[2]) + (-0.32 if open_floors[s["floor"]] and not multiball else 0.15)
		node.position.y = lerpf(node.position.y, want, 0.2)
	var k: int = 0
	for s in segs:
		if s["kind"] == "kick":
			var mat := (kick_nodes[k] as MeshInstance3D).material_override as StandardMaterial3D
			var burn := 0.0
			if s.get("bounce", false):
				# a bounce-back burns in the kickback's colour while its KICK is lit
				var on: bool = kickbacks[int(s["kb"])]
				mat.albedo_color = COLOURS["fire"] if on else KICK_CREAM
				mat.emission = mat.albedo_color
				burn = 0.8 if on else 0.0
			mat.emission_energy_multiplier = 0.2 + burn + 2.5 * float(s["flash"])
			k += 1
	shield_node.visible = shield_t > 0.0
	plunger_node.position = _w(Vector2(1200, 3586 + pull * 18.0), 0.06)
	portal_node.rotation.y = t * 1.6
	portal_light.light_energy = 1.0 + 0.6 * sin(t * 4.0) + (2.5 if holds.has("portal") else 0.0)
	beam_node.rotation.y = -beam_a
	beholder_light.light_energy = 0.6 + 2.5 * float(beholder["flash"]) + (1.0 if beholder["open"] else 0.0)
	for i in eyes.size():
		var e: Dictionary = eyes[i]
		var pulse: float = 0.5 + 0.5 * sin(t * (6.0 if e["open"] else 2.0) + i)
		(eye_lights[i] as OmniLight3D).light_energy = 0.3 + pulse * (1.4 if e["open"] else 0.4) + 2.0 * float(e["flash"])
	_sync_elusion()
	_sync_new()
	slime_node.visible = slime_gone <= 0.0
	var hop: float = absf(sin(t * 3.2))
	slime_node.position = _w(slime_at(), 0.38 + hop * 0.35)
	slime_node.texture = slime_frames[int(t * 8.0) % slime_frames.size()]
	_floors_on_screen()
	_paint_frame += 1
	var paint_now: bool = not light or _paint_frame % PHONE_EVERY == 0
	for fl in 3:
		_paint_layer(moving_vps[fl], moving_nodes[fl], floor_seen[fl], paint_now)
	for i in eye_nodes.size():
		_paint_layer(eye_vps[i], eye_nodes[i], floor_seen[eye_floor[i]], paint_now)
	back_node.queue_redraw()
	hud_node.queue_redraw()
	if paint_now:
		panel_node.queue_redraw()


func _paint_layer(vp: SubViewport, node: Node2D, seen: bool, paint_now: bool) -> void:
	"""A painted layer: off the screen, not drawn; on it, painted and drawn
	every frame - on a phone every PHONE_EVERY, its picture drawn once then."""
	if not seen:
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	elif not light:
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		node.queue_redraw()
	elif paint_now:
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		node.queue_redraw()


func _sync_elusion() -> void:
	# the monsters walk, flash when hit, burst when slain, grow back
	for m in mobs:
		var node: Sprite3D = m["node"]
		var a: Dictionary = MOB_ART[m["kind"]]
		var dying: float = t - float(m["died"])
		var back: float = t - float(m["back"])
		if not _alive(m) and dying > 0.3:
			node.visible = false
			continue
		node.visible = true
		var pos: Vector2 = _mob_at(m) if _alive(m) else m["dpos"]
		var hover: float = 0.0 if m["kind"] == "skeleton" else 0.26 + 0.07 * sin(t * 3.0 + float(m["phase"]))
		node.position = _w(pos, float(FLOORS[m["fl"]]["h"]) + hover + float(a["feet"]) * float(a["ps"]))
		var fr: Array = mob_frames[m["kind"]]["right" if _mob_right(m) else "left"]
		node.texture = fr[int(t * 9.0 + float(m["phase"]) * 3.0) % fr.size()]
		var sc: float = 1.0
		if not _alive(m):
			sc = 1.0 + dying * 3.0
			node.modulate = Color(3.0, 3.0, 3.0)
		elif back < 0.35:
			sc = clampf(back / 0.35, 0.05, 1.0)
			node.modulate = Color(1.8, 1.8, 2.2)
		elif t - float(m["hurt"]) < 0.15:
			node.modulate = Color(3.0, 1.0, 1.0)
		else:
			node.modulate = Color(1, 1, 1)
		node.scale = Vector3.ONE * sc
	# the horde of slimes
	for i in horde_nodes.size():
		var node: Sprite3D = horde_nodes[i]
		if i >= horde.size():
			node.visible = false
			continue
		var h: Dictionary = horde[i]
		var fl: int = h["fl"]
		var dead: float = float(h["dead"])
		if dead > 0.0 and t - dead < 0.3:
			node.visible = true
			node.position = _w(h["dpos"], float(FLOORS[fl]["h"]) + 0.38)
			node.scale = Vector3.ONE * (1.0 + (t - dead) * 4.0)
			node.modulate = Color(2.5, 3.0, 2.5)
		elif _horde_on(h):
			node.visible = true
			node.scale = Vector3.ONE
			node.modulate = Color(1, 1, 1)
			node.position = _w(_horde_at(h), float(FLOORS[fl]["h"]) + 0.38 + absf(sin(t * 6.0 + int(h["i"]))) * 0.25)
			node.texture = slime_frames[int(t * 8.0 + int(h["i"])) % slime_frames.size()]
		else:
			node.visible = false
	# the rocks of the quake, falling and landing
	for i in rock_nodes.size():
		var node: Sprite3D = rock_nodes[i]
		if i >= rocks.size() or rocks[i]["gone"] or float(rocks[i]["land"]) - t > 0.45:
			node.visible = false
			continue
		var r: Dictionary = rocks[i]
		var fall: float = maxf(0.0, float(r["land"]) - t)
		node.visible = true
		node.position = _w(r["p"], float(FLOORS[r["fl"]]["h"]) + 28.0 * 0.012 + fall / 0.45 * 3.4)
		node.modulate = Color(2.2, 2.0, 1.8) if float(r["flash"]) > 0.0 else Color(1, 1, 1)
	# the loot: the pack's coins, bags, eyes
	for i in loot_nodes.size():
		var node: Sprite3D = loot_nodes[i]
		if i >= loot.size():
			node.visible = false
			continue
		var lo: Dictionary = loot[i]
		var key: String = lo["key"]
		node.visible = true
		node.texture = pack[key]
		node.pixel_size = 0.016 if key == "lootbag" else (0.03 if key.begins_with("eye") else 0.02)
		node.position = _w(lo["p"], float(FLOORS[lo["fl"]]["h"]) + 0.14 + float(lo["h"]) * 0.3)
	# the warrior's axes, round every ball
	var ai: int = 0
	if whirl_t > 0.0:
		for ball in balls:
			if ball["held"] or ball.has("sunk") or ai >= axe_nodes.size():
				continue
			for j in 2:
				var ang: float = t * 9.0 + j * PI
				var node: Sprite3D = axe_nodes[ai]
				node.visible = true
				node.position = _w((ball["p"] as Vector2) + Vector2(cos(ang), sin(ang)) * 48.0, _ball_height(ball) + 0.22)
				node.texture = axe_frames[int(t * 16.0 + j * 2) % axe_frames.size()]
				ai += 1
	for k in range(ai, axe_nodes.size()):
		(axe_nodes[k] as Sprite3D).visible = false
	# the heroes on the table
	mage_node.visible = t < mage_until
	if mage_node.visible:
		var mf: Array = hero_frames["MAGE"]
		mage_node.position = _w(TOWER + Vector2(0, 14), TOWER_TOP + 0.06 + 21.0 * float(HERO_ART["MAGE"]["ps"]))
		mage_node.texture = mf[int(t * 10.0) % mf.size()]
	tank_node.visible = shield_t > 0.0
	ring_node.visible = shield_t > 0.0
	if tank_node.visible:
		var tf: Array = hero_frames["TANK"]
		tank_node.position = _w(Vector2(600, SHIELD_Y - 8), 21.0 * float(HERO_ART["TANK"]["ps"]) * 0.8)
		tank_node.texture = tf[int(t * 8.0) % tf.size()]
		ring_node.position = _w(Vector2(600, SHIELD_Y + 4), 0.3)
		ring_node.texture = ring_frames[int(t * 10.0) % ring_frames.size()]
	var heal_age: float = t - (float(heals[heals.size() - 1]) if not heals.is_empty() else -100.0)
	healer_node.visible = heal_age < 1.9
	aura_node.visible = heal_age < 1.25
	if healer_node.visible:
		var hf: Array = hero_frames["HEAL"]
		healer_node.position = _w(Vector2(600, 3478), 16.0 * float(HERO_ART["HEAL"]["ps"]))
		healer_node.texture = hf[int(t * 10.0) % hf.size()]
		healer_node.scale = Vector3.ONE * clampf(heal_age / 0.2, 0.1, 1.0) * clampf((1.9 - heal_age) / 0.2, 0.1, 1.0)
	if aura_node.visible:
		aura_node.position = _w(Vector2(600, 3486), 0.62)
		aura_node.texture = aura_frames[clampi(int(heal_age * 20.0), 0, aura_frames.size() - 1)]
	# the tower: its crystal turns, its light pulses, a locked ball glows
	crystal.rotation.y = t * 1.6
	crystal.position.y = TOWER_TOP + 0.5 + 0.05 * sin(t * 2.0)
	lock_node.visible = not tower_ball.is_empty()
	lock_mat.emission_energy_multiplier = 1.0 + 0.8 * sin(t * 6.0)
	tower_light.light_energy = 0.8 + 0.4 * sin(t * 3.0) + (1.6 if not tower_ball.is_empty() else 0.0) + 3.0 * float(ramp_at["TOWER"]["flash"])
	# the lands' light: a blackout dims the table, dazzle lights it
	var fx: float = _fx_k()
	var dark: float = fx if _effect_is("dark") else 0.0
	if _warning_of() == "dark" and fmod(t * 13.0, 1.0) < 0.35:
		dark = 0.7 * clampf((t - float(effect["warn"])) / WARN, 0.0, 1.0)
	var bright: float = fx if _effect_is("light") else 0.0
	sun_light.light_energy = 0.75 * (1.0 - 0.92 * dark) + 0.5 * bright
	world_env.ambient_light_energy = (PHONE_AMBIENT if light else 0.55) * (1.0 - 0.85 * dark) + 0.35 * bright
	for f in fills:
		(f as OmniLight3D).light_energy = 0.55 * (1.0 - 0.95 * dark)
	for fm in floor_mats:
		(fm as ShaderMaterial).set_shader_parameter("glow", 0.42 * (1.0 - 0.85 * dark) + 0.25 * bright)
	# in the dark the table's metal glows: rails, rims, flippers
	for gm in glow_mats:
		(gm[0] as StandardMaterial3D).emission_energy_multiplier = float(gm[1]) * dark
	for sm in stripe_mats:
		(sm as StandardMaterial3D).emission_energy_multiplier = 0.5 + 3.5 * dark


func _floors_on_screen() -> void:
	"""Which floors the camera sees this frame: the screen's four corners
	cast onto each floor's level make the patch in view; a floor is seen
	when its box meets that patch (or the view looks above its level)."""
	var vs: Vector2 = get_viewport().get_visible_rect().size
	for fl in 3:
		var h: float = FLOORS[fl]["h"]
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		var ok: bool = true
		for c in [Vector2.ZERO, Vector2(vs.x, 0), Vector2(0, vs.y), vs]:
			var o: Vector3 = cam3.project_ray_origin(c)
			var d: Vector3 = cam3.project_ray_normal(c)
			if d.y > -0.001:
				ok = false
				break
			var q: Vector3 = o + d * ((h - o.y) / d.y)
			lo = lo.min(Vector2(q.x, q.z))
			hi = hi.max(Vector2(q.x, q.z))
		var box: AABB = floor_boxes[fl]
		floor_seen[fl] = not ok or not (hi.x < box.position.x or lo.x > box.end.x or hi.y < box.position.z or lo.y > box.end.z)


func _screen(p: Vector2, lift: float = 0.25) -> Vector2:
	return cam3.unproject_position(_w(p, height_at(p.y) + lift))


# =============================================================================
# PAINTING
# =============================================================================

func _paint_back() -> void:
	cv = back_node
	cv.draw_rect(Rect2(0, 0, 1280, 720), Color(0.015, 0.012, 0.03))
	for i in 8:
		cv.draw_circle(Vector2(420, 380), 560.0 - i * 64.0, Color(0.2, 0.08, 0.36, 0.035))
	if star_at.is_empty():
		var stars := RandomNumberGenerator.new()
		stars.seed = 99
		for i in 260:
			star_at.append(Vector2(stars.randf() * 860.0, stars.randf() * 720.0))
			star_sp.append(stars.randf_range(1.0, 3.0))
			star_r.append(stars.randf_range(0.6, 1.6))
			star_a.append(stars.randf_range(0.15, 0.6))
	for i in 260:
		var tw: float = 0.5 + 0.5 * sin(t * star_sp[i] + i)
		var r: float = star_r[i]
		cv.draw_rect(Rect2(star_at[i] - Vector2(r, r), Vector2(r, r) * 2.0), Color(0.8, 0.8, 1.0, star_a[i] * (0.6 + 0.4 * tw)))


func _floor_shape(fl: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var y0: float = FLOORS[fl]["y0"]
	var yb: float = FLOORS[fl]["yb"]
	if fl == 2:
		for p in _arc(Vector2(600, 400), 600, 400, PI, TAU, 40):
			out.append(p)
		out.append(Vector2(1240, yb + 100))
		out.append(Vector2(0, yb + 100))
		return out
	for p in _arc(Vector2(220, y0 + 200), 220, 220, PI, PI * 1.5, 10):
		out.append(p)
	for p in _arc(Vector2(1020, y0 + 200), 220, 220, PI * 1.5, TAU, 10):
		out.append(p)
	out.append(Vector2(1240, yb + 100 if fl > 0 else yb))
	out.append(Vector2(0, yb + 100 if fl > 0 else yb))
	return out


func _tiled(pts: PackedVector2Array, tex: Texture2D, tint: Color, shift: Vector2 = Vector2.ZERO) -> void:
	var uvs := PackedVector2Array()
	for p in pts:
		uvs.append((p + shift) / 64.0)
	cv.draw_colored_polygon(pts, tint, uvs, tex)


func _circle_pts(c: Vector2, r: float, n: int = 40) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		out.append(c + Vector2(cos(i * TAU / n), sin(i * TAU / n)) * r)
	return out


func _path(pts: PackedVector2Array, tex: Texture2D, tint: Color) -> void:
	"""A path of the owner's cobble, edged dark the way his tiles are."""
	_tiled(pts, tex, tint)
	var loop := pts.duplicate()
	loop.append(pts[0])
	cv.draw_polyline(loop, Color(0.1, 0.07, 0.06, 0.75), 5.0)


func _rect_pts(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


func _floor_paths(fl: int) -> void:
	var cob: Texture2D = tiles["cobble"]
	var ct := Color(0.8, 0.78, 0.84)
	match fl:
		0:
			# the town square: the high street up to the climb, the slime's
			# road across it, a plaza round the Portal, the tower's foot
			_path(_rect_pts(Rect2(40, 2972, 1140, 76)), cob, ct)
			_path(_rect_pts(Rect2(548, 2440, 104, 1130)), cob, ct)
			_path(_circle_pts(PORTAL, 86.0), cob, ct)
			_path(_circle_pts(TOWER, 104.0), cob, ct)
			_path(_rect_pts(Rect2(1180, 2600, 40, 1000)), cob, ct)
			var spots: Array = [["redflower", Vector2(250, 3120)], ["whiteflower", Vector2(950, 3130)], ["plant3", Vector2(820, 3205)],
				["plant", Vector2(385, 3195)], ["redflower", Vector2(470, 2470)], ["whiteflower", Vector2(330, 2480)],
				["plant2", Vector2(1050, 2920)], ["redflower", Vector2(160, 2880)]]
			for s in spots:
				cv.draw_texture_rect(flowers[s[0]], Rect2((s[1] as Vector2) - Vector2(32, 32), Vector2(64, 64)), false)
		1:
			# the big field: cobble round the two eyes and up the middle
			_path(_rect_pts(Rect2(552, 1220, 96, 1080)), cob, ct)
			for e in eyes:
				_path(_circle_pts(e["p"], 150.0), cob, ct)
			for s in [["plant", Vector2(200, 1460)], ["plant3", Vector2(1000, 1460)], ["redflower", Vector2(460, 1880)],
					["whiteflower", Vector2(740, 1880)]]:
				cv.draw_texture_rect(flowers[s[0]], Rect2((s[1] as Vector2) - Vector2(32, 32), Vector2(64, 64)), false)
		2:
			# the lair: a ring of stone round the Beholder, lava in the corners
			_path(_circle_pts(BEHOLDER, 290.0, 56), cob, Color(0.62, 0.56, 0.66))
			for c in [Vector2(140, 800), Vector2(1060, 800)]:
				cv.draw_circle(c, 82.0, Color(0.12, 0.04, 0.02))


func _paint_effect(fl: int) -> void:
	"""THE LAND'S EFFECT, painted on every floor in the owner's tiles - and
	before it, its warning."""
	if effect.is_empty():
		return
	if t < float(effect["from"]):
		_paint_warning(fl)
		return
	var k: float = _fx_k()
	var land: String = effect["land"]
	var y0: float = FLOORS[fl]["y0"]
	var yb: float = FLOORS[fl]["yb"]
	var shape: PackedVector2Array = _floor_shape(fl)
	var r := RandomNumberGenerator.new()
	r.seed = 17 + fl
	match land:
		"water":
			var ty: float = _tide_y(fl)
			if ty < yb:
				_tiled(_rect_pts(Rect2(0, ty, 1240, yb - ty)), tiles["water"], Color(1, 1, 1, 0.8), Vector2(t * 26.0, sin(t * 1.3) * 12.0))
				var wave := PackedVector2Array()
				for i in 64:
					wave.append(Vector2(i * 20.0, _surface_at(i * 20.0, fl)))
				cv.draw_polyline(wave, Color(0.88, 0.96, 1.0, 0.9), 5.0)
		"ice":
			_tiled(shape, tiles["snow"], Color(0.8, 0.92, 1.0, 0.36 * k))
			for i in 16:
				var p := Vector2(r.randf_range(60, 1180), r.randf_range(y0 + 120, yb - 60))
				var line := PackedVector2Array([p])
				for j in 4:
					p += Vector2(r.randf_range(-60, 60), r.randf_range(-60, 60))
					line.append(p)
				cv.draw_polyline(line, Color(0.75, 0.95, 1.0, 0.7 * k), 3.0)
		"fire":
			cv.draw_colored_polygon(shape, Color(1.0, 0.3, 0.05, 0.12 * k))
			for i in 3:
				var at: Vector2 = VENTS[fl][i]
				var on: bool = _vent_on(i)
				cv.draw_circle(at, 58.0, Color(0.12, 0.03, 0.02, 0.9 * k))
				_tiled(_circle_pts(at, 46.0, 28), tiles["lava"], Color(1, 1, 1, k), Vector2(t * 14.0, t * 9.0))
				if on:
					cv.draw_circle(at, 72.0, Color(1.0, 0.55, 0.1, 0.3 * k))
					cv.draw_arc(at, 60.0, 0, TAU, 32, Color(1.0, 0.85, 0.4, 0.9 * k), 4.0)
		"wind":
			# the updraft: streaks rising up the floor
			for i in 50:
				var x: float = r.randf_range(40.0, 1200.0)
				var len: float = r.randf_range(70.0, 180.0)
				var y: float = yb - fposmod(r.randf() * (yb - y0) + t * 620.0 * r.randf_range(0.8, 1.3), yb - y0)
				cv.draw_line(Vector2(x, y), Vector2(x, minf(yb, y + len)), Color(0.85, 1.0, 0.95, 0.5 * k), 4.0)
				cv.draw_circle(Vector2(x, y), 3.0, Color(1, 1, 1, 0.6 * k))
		"earth":
			cv.draw_colored_polygon(shape, Color(0.3, 0.18, 0.05, 0.16 * k))
			for i in 10:
				var p := Vector2(r.randf_range(80, 1160), r.randf_range(y0 + 150, yb - 80))
				var line := PackedVector2Array([p])
				for j in 5:
					p += Vector2(r.randf_range(-70, 70), r.randf_range(-50, 50))
					line.append(p)
				cv.draw_polyline(line, Color(0.12, 0.06, 0.02, 0.85 * k), 5.0)
			for rk in rocks:
				if int(rk["fl"]) == fl and not rk["gone"]:
					var fall: float = clampf((float(rk["land"]) - t) / 0.45, 0.0, 1.0)
					if float(rk["land"]) - t < 0.45:
						cv.draw_circle((rk["p"] as Vector2) + Vector2(6, 10), 26.0 * (1.0 - fall * 0.6), Color(0, 0, 0, 0.45 * (1.0 - fall)))
		"light":
			var c := Vector2(CX, (y0 + yb) / 2.0)
			cv.draw_colored_polygon(shape, Color(1.0, 0.9, 0.5, 0.1 * k))
			for i in 16:
				var ang: float = i * TAU / 16.0 + t * 0.6
				cv.draw_colored_polygon(PackedVector2Array([c, c + Vector2(cos(ang), sin(ang)) * 1400.0,
					c + Vector2(cos(ang + 0.07), sin(ang + 0.07)) * 1400.0]), Color(1.0, 0.92, 0.6, 0.16 * k))
		"dark":
			cv.draw_colored_polygon(shape, Color(0.0, 0.0, 0.02, 0.64 * k))
			for ball in balls:
				if floor_of((ball["p"] as Vector2).y) == fl:
					cv.draw_circle(ball["p"], 110.0, Color(0.6, 0.45, 1.0, 0.1 * k))
					cv.draw_circle(ball["p"], 60.0, Color(0.7, 0.55, 1.0, 0.14 * k))


func _paint_warning(fl: int) -> void:
	"""THE WARNING: for WARN seconds the floor shows what is coming - the
	updraft's first streaks, frost creeping in from the edges, the rocks'
	shadows, the line the tide will reach, the vents glowing under the
	floor, the gold coming up, the lights failing."""
	var land: String = effect["land"]
	var kw: float = clampf((t - float(effect["warn"])) / WARN, 0.0, 1.0)
	var blink: float = 0.5 + 0.5 * sin(t * 14.0)
	var y0: float = FLOORS[fl]["y0"]
	var yb: float = FLOORS[fl]["yb"]
	var shape: PackedVector2Array = _floor_shape(fl)
	var r := RandomNumberGenerator.new()
	r.seed = 17 + fl
	match land:
		"wind":
			for i in 26:
				var x: float = r.randf_range(40.0, 1200.0)
				var y: float = yb - fposmod(r.randf() * (yb - y0) + t * 320.0, yb - y0)
				cv.draw_line(Vector2(x, y), Vector2(x, minf(yb, y + 90.0)), Color(0.85, 1.0, 0.95, 0.3 * kw), 3.0)
		"ice":
			var reach: float = 40.0 + 170.0 * kw
			for band in [Rect2(0, y0, reach, yb - y0), Rect2(1240.0 - reach, y0, reach, yb - y0), Rect2(0, y0, 1240, reach)]:
				for poly in Geometry2D.intersect_polygons(shape, _rect_pts(band)):
					_tiled(poly, tiles["snow"], Color(0.8, 0.92, 1.0, 0.55))
		"earth":
			for rk in rocks:
				if int(rk["fl"]) == fl:
					cv.draw_circle((rk["p"] as Vector2) + Vector2(6, 10), 8.0 + 16.0 * kw, Color(0, 0, 0, 0.45 * kw))
					cv.draw_arc(rk["p"], 30.0, 0, TAU, 24, Color(COLOURS["earth"].lightened(0.3), 0.8 * blink * kw), 3.0)
		"water":
			var ty: float = yb - (yb - y0) * 0.42
			var x: float = 0.0
			while x < 1240.0:
				cv.draw_line(Vector2(x, ty), Vector2(x + 34.0, ty), Color(0.6, 0.85, 1.0, 0.35 + 0.55 * blink), 4.0)
				x += 56.0
		"fire":
			for i in 3:
				var at: Vector2 = VENTS[fl][i]
				cv.draw_circle(at, 50.0, Color(0.12, 0.03, 0.02, 0.6 * kw))
				cv.draw_arc(at, 46.0, 0, TAU, 28, Color(1.0, 0.5, 0.1, (0.3 + 0.6 * blink) * kw), 4.0)
		"light":
			cv.draw_colored_polygon(shape, Color(1.0, 0.9, 0.5, 0.08 * kw))
		"dark":
			if fmod(t * 13.0, 1.0) < 0.35:
				cv.draw_colored_polygon(shape, Color(0, 0, 0.02, 0.45 * kw))


func _letter_lamp(at: Vector2, ch: String, c: Color, on: bool) -> void:
	cv.draw_rect(Rect2(at - Vector2(15, 15), Vector2(30, 30)), Color(c, 0.85 if on else 0.14))
	cv.draw_rect(Rect2(at - Vector2(15, 15), Vector2(30, 30)), Color(c.lightened(0.3), 0.9 if on else 0.4), false, 2.0)
	_text(at + Vector2(0, 8), ch, 20, Color(0.05, 0.03, 0.08) if on else Color(c, 0.75), null, true, 1.0, 0)


func _word_lamps(word: String, pts: Array) -> void:
	var n: int = words[word]
	var fresh: bool = done.has("word_" + word) and t - float(done["word_" + word]) < 2.0
	for i in 4:
		var on: bool = i < n or (fresh and frame % 10 < 6)
		_letter_lamp(pts[i], word[i], HERO[word], on)


func _paint_still() -> void:
	"""THE FLOOR THAT NEVER CHANGES, painted once: the owner's tiles, the
	paths and flowers, the shade, the floors' names, the sockets of the
	seven lands, the holes and the shadows of what never moves."""
	cv = floor_node
	var base: Array = ["grass", "dirt", "lavarock"]
	var tint: Array = [Color(0.66, 0.74, 0.64), Color(0.8, 0.72, 0.7), Color(0.85, 0.76, 0.82)]
	for fl in 3:
		var shape: PackedVector2Array = _floor_shape(fl)
		var y0: float = FLOORS[fl]["y0"]
		var yb: float = FLOORS[fl]["yb"]
		_tiled(shape, tiles[base[fl]], tint[fl])
		_floor_paths(fl)
		# the back of each floor in shadow, the front a little
		var cols := PackedColorArray()
		for p in shape:
			var k: float = clampf((p.y - y0) / (yb - y0), 0.0, 1.0)
			cols.append(Color(0.04, 0.02, 0.08, 0.42 * (1.0 - k) * (1.0 - k) + 0.12 * k))
		cv.draw_polygon(shape, cols)
		if fl > 0:
			cv.draw_rect(Rect2(0, yb, 1240, 100), Color(0.1, 0.07, 0.14))
		_text(Vector2(CX, yb - 22.0), str(FLOORS[fl]["name"]), 22, Color(GOLD, 0.55), null, true, 1.0, 3)
	# the ground floor's rays, and the seven lands' sockets
	for i in 12:
		var ang: float = PI + i * PI / 11.0
		var c := Vector2(CX, 3330)
		cv.draw_colored_polygon(PackedVector2Array([c, c + Vector2(cos(ang), sin(ang)) * 1000.0, c + Vector2(cos(ang + 0.08), sin(ang + 0.08)) * 1000.0]),
			Color(COLOURS[ORDER[i % 7]], 0.06))
	for i in ORDER.size():
		var p := Vector2(CX - 126.0 + i * 42.0, 3405.0 + absf(i - 3) * 6.0)
		cv.draw_circle(p, 18.0, Color(0.05, 0.03, 0.08, 0.85))
		cv.draw_arc(p, 18.0, 0, TAU, 24, Color(COLOURS[ORDER[i]], 0.7), 2.0)
	cv.draw_circle(PORTAL, 22.0, Color(0.0, 0.0, 0.0, 0.95))
	for e in eyes:
		cv.draw_circle(e["p"] + Vector2(8, 12), EYE_R + 8.0, Color(0, 0, 0, 0.4))
	cv.draw_circle(BEHOLDER + Vector2(10, 16), BEHOLDER_R + 10.0, Color(0, 0, 0, 0.45))
	cv.draw_circle(LAIR, 24.0, Color(0, 0, 0, 0.95))
	_paint_still_more()


func _in_band(p: Vector2, reach: float = 120.0) -> bool:
	"""On the floor being painted (with room for what crosses its edge)."""
	return p.y > band_lo - reach and p.y < band_hi + reach


func _paint_moving(fl: int, node: Node2D) -> void:
	"""WHAT MOVES ON ONE FLOOR, painted while that floor is on screen: the
	land's effect and its warning, shadows of what walks, the lamps, the
	inserts, the turning circles."""
	cv = node
	var top: float = FLOOR_TOP[fl]
	band_lo = top
	band_hi = top + 1200.0
	cv.draw_set_transform(Vector2(0, -top))
	var yb: float = FLOORS[fl]["yb"]
	if fl == 2:
		for c in [Vector2(140, 800), Vector2(1060, 800)]:
			_tiled(_circle_pts(c, 72.0, 28), tiles["lava"], Color(1, 1, 1), Vector2(t * 8.0, t * 5.0))
	if fl > 0:
		for i in 9:
			_chevron_down(Vector2(200.0 + i * 100.0, yb + 50.0), Color(GOLD, 0.25 + 0.4 * (0.5 + 0.5 * sin(t * 5.0 - i * 0.8))))
	_paint_effect(fl)
	# the monsters' and the heroes' shadows
	for m in mobs:
		if _alive(m) and int(m["fl"]) == fl:
			var sp: Vector2 = _mob_at(m)
			cv.draw_circle(sp + Vector2(5, 10), 20.0, Color(0, 0, 0, 0.35 if m["kind"] == "skeleton" else 0.22))
	for h in horde:
		if _horde_on(h) and _in_band(_horde_at(h), 30.0):
			cv.draw_circle(_horde_at(h) + Vector2(4, 8), 16.0, Color(0, 0, 0, 0.3))
	var chase: float = 0.5 + 0.5 * sin(t * 5.0)
	if fl == 0:
		# the tower's foot: a mage's circle, turning
		for i in 3:
			var r: float = 86.0 + i * 12.0
			cv.draw_arc(TOWER, r, t * (0.8 - i * 0.5), t * (0.8 - i * 0.5) + PI * 1.4, 40, Color(HERO["MAGE"], 0.55), 3.0)
		for i in ORDER.size():
			var el: String = ORDER[i]
			var p := Vector2(CX - 126.0 + i * 42.0, 3405.0 + absf(i - 3) * 6.0)
			if lit.has(el):
				cv.draw_circle(p, 26.0, Color(COLOURS[el], 0.35))
				cv.draw_texture_rect(pack["ess_" + el], Rect2(p - Vector2(16, 16), Vector2(32, 32)), false)
		for i in 11:
			_chevron_up(Vector2(1200, 3520.0 - i * 100.0), Color(GOLD, 0.2 + 0.7 * (0.5 + 0.5 * sin(t * 6.0 - i * 1.1))))
		# the heroes' letters along their shots
		_word_lamps("MAGE", [Vector2(65, 2925), Vector2(65, 2875), Vector2(65, 2825), Vector2(65, 2775)])
		var warr: Array = []
		var tank: Array = []
		for i in 4:
			warr.append(Vector2(XL_PTS[0].x, 2975.0 + i * 44.0))
			tank.append(Vector2(1200.0 - XL_PTS[0].x, 2975.0 + i * 44.0))
		_word_lamps("WARR", warr)
		_word_lamps("TANK", tank)
		_word_lamps("HEAL", [Vector2(300, 3310), Vector2(351, 3300), Vector2(849, 3300), Vector2(900, 3310)])
		_paint_kicks()
	for b in bumpers:
		if _in_band(b["p"]):
			cv.draw_circle(b["p"], float(b["r"]) + 20.0, Color(COLOURS[b["el"]], 0.22 + 0.5 * float(b["flash"])))
	for tg in targets:
		var r: Rect2 = tg["rect"]
		if not _in_band(r.get_center()):
			continue
		if tg["el"] == "extra":
			_text(r.get_center() + Vector2(0, 34), "EXTRA BALL", 13, Color(0.5, 1.0, 0.55, 1.0 if extra_lit and frame % 16 < 10 else 0.3), null, true)
			if extra_lit:
				cv.draw_texture_rect(pack["greaterhealthpotion"], Rect2(r.get_center() + Vector2(-16, 42), Vector2(32, 32)), false)
		else:
			var lamp: Vector2 = r.get_center() + (Vector2(0, 26) if int(tg["bank"]) >= 2 else Vector2(34, 0))
			_diamond(lamp, 8.0, Color(COLOURS[tg["el"]].lightened(0.3), 0.95 if tg["down"] else 0.3))
	if fl == 0:
		# the Portal's scoop, swirling
		for i in 4:
			var r: float = 34.0 + i * 16.0
			cv.draw_arc(PORTAL, r, t * 2.0 + i, t * 2.0 + i + PI * 1.2, 24, Color(0.6, 0.35, 1.0, 0.45), 3.0)
		# the shots' inserts
		_arrow_insert(Vector2(XL_PTS[0].x, 2918), -PI / 2.0, "RAMP", HERO["WARR"], maxf(float(ramp_at["XL"]["flash"]), chase * 0.6))
		_arrow_insert(Vector2(1200.0 - XL_PTS[0].x, 2918), -PI / 2.0, "RAMP", HERO["TANK"], maxf(float(ramp_at["XR"]["flash"]), (1.0 - chase) * 0.6))
		_arrow_insert(Vector2(1145, 3070), -PI / 2.0, "ORBIT", GOLD, 0.3 + 0.4 * (1.0 - chase))
		# the top lanes: LVL, lit as they are rolled through
		for li in 3:
			var c := Vector2((float(LANES_X[li]) + float(LANES_X[li + 1])) / 2.0, 2462.0)
			_letter_lamp(c, LANE_WORD[li], GOLD, lanes[0][li])
		if lane_x > 1:
			_text(Vector2(865, 2528), "x%d" % lane_x, 16, GOLD, null, true, 1.0, 0)
		_arrow_insert(Vector2(65, 3060), -PI / 2.0, "TOWER", HERO["MAGE"], maxf(float(ramp_at["TOWER"]["flash"]), 0.3 + 0.4 * chase))
		if not tower_ball.is_empty():
			_text(Vector2(150, 2700), "FREE BALL", 16, Color(GOLD, 1.0 if frame % 16 < 10 else 0.4), null, true)
		_arrow_insert(PORTAL + Vector2(0, 88), -PI / 2.0, "PORTAL", Color(0.65, 0.4, 1.0), 0.4 + 0.6 * chase)
	for nm in ["UP2", "UP3"]:
		var r: Dictionary = ramp_at[nm]
		var m: Vector2 = r["mouth"]
		if not (_in_band(m + Vector2(0, 92)) or _in_band(m + Vector2(0, 186))):
			continue
		var open: bool = open_floors[r["lock"]] and not multiball
		_arrow_insert(m + Vector2(0, 92), -PI / 2.0, "CLIMB" if open else "SHUT", GOLD if open else Color(0.95, 0.3, 0.25),
			1.0 if open and frame % 16 < 10 else 0.35)
		if multiball and open_floors[r["lock"]]:
			_text(m + Vector2(0, 186), "SHUT IN MULTIBALL", 14, Color(0.95, 0.5, 0.45), null, true)
		elif not open:
			_text(m + Vector2(0, 186), "OPENS AT %s" % _thousands(int(FLOORS[r["lock"]]["opens"])), 14, Color(INK, 0.7), null, true)
	if fl == 1:
		for e in eyes:
			for r in [90.0, 130.0, 175.0]:
				cv.draw_arc(e["p"], r, 0, TAU, 72, Color(COLOURS["dark"].lightened(0.25), 0.35 if e["open"] else 0.18), 3.0)
			for i in EYE_HP:
				var on: bool = e["open"] or i >= int(e["hp"])
				_diamond((e["p"] as Vector2) + Vector2((i - 0.5) * 30.0, EYE_R + 36.0), 9.0, Color(COLOURS["dark"].lightened(0.4), 0.95 if on else 0.25))
			_arrow_insert((e["p"] as Vector2) + Vector2(0, 160), -PI / 2.0, "EYE", COLOURS["dark"].lightened(0.35), 1.0 if e["open"] else 0.3 + 0.4 * chase)
		_arrow_insert(Vector2(430, 1830), -PI / 2.0, "RAMP", Color(0.55, 0.8, 1.0), maxf(float(ramp_at["XL2"]["flash"]), chase * 0.5))
		_arrow_insert(Vector2(770, 1830), -PI / 2.0, "RAMP", Color(0.55, 0.8, 1.0), maxf(float(ramp_at["XR2"]["flash"]), chase * 0.5))
		_arrow_insert(Vector2(1140, 1700), -PI / 2.0, "ORBIT", GOLD, 0.3 + 0.4 * (1.0 - chase))
		var xs1: Array = LANE_SETS[1]["xs"]
		for li in 3:
			var c := Vector2((float(xs1[li]) + float(xs1[li + 1])) / 2.0, 1260.0)
			_letter_lamp(c, str(LANE_SETS[1]["word"])[li], COLOURS["light"], lanes[1][li])
	if fl == 2:
		for i in 16:
			var ang: float = i * TAU / 16.0 + t * 0.1
			cv.draw_line(BEHOLDER + Vector2(cos(ang), sin(ang)) * 130.0, BEHOLDER + Vector2(cos(ang), sin(ang)) * 260.0,
				Color(COLOURS["dark"].lightened(0.3), 0.25), 3.0)
		var boss_lit: bool = done.has("crowned") or (open_floors[2] and done.has("eyes"))
		for i in 5:
			var r: float = 40.0 + i * 22.0
			cv.draw_arc(LAIR, r, t * (0.6 + i * 0.15), t * (0.6 + i * 0.15) + PI * 1.3, 40,
				Color(1.0, 0.4, 0.4, 0.5) if boss_lit else Color(COLOURS["dark"].lightened(0.3), 0.35), 4.0)
		_arrow_insert(LAIR + Vector2(0, 150), -PI / 2.0, "BOSS" if boss_lit else "LAIR", Color(1.0, 0.4, 0.4) if boss_lit else COLOURS["dark"].lightened(0.4),
			0.4 + 0.6 * chase)
		_arrow_insert(Vector2(400, 830), -PI / 2.0 + 0.4, "SPIRAL", COLOURS["dark"].lightened(0.45), maxf(float(ramp_at["SPIRAL"]["flash"]), chase * 0.5))
		for bank in STALKS:
			_text(Vector2(float(bank[1]) + 13.0, STALK_Y - 22.0), "EYESTALKS", 12, Color(COLOURS["dark"].lightened(0.5), 0.8), null, true, 1.0, 0)
	_paint_moving_more(fl, chase)
	# the ramps' shadows
	for r in ramps:
		var box: Rect2 = r["box"]
		if box.end.y < band_lo - 40.0 or box.position.y > band_hi + 40.0:
			continue
		var shadow := PackedVector2Array()
		for p in r["pts"]:
			shadow.append((p as Vector2) + Vector2(10, 16))
		cv.draw_polyline(shadow, Color(0, 0, 0, 0.3), 36.0)
	if fl == 0:
		var saving: bool = t < save_until and frame % 20 < 12
		_text(Vector2(CX, 3528), "SHOOT AGAIN", 16, Color(COLOURS["fire"], 0.9 if saving else 0.18), null, true, 1.0, 0)
		if saving:
			for x in [508.0, 692.0]:
				cv.draw_texture_rect(pack["largehealthpotion"], Rect2(Vector2(x - 16.0, 3492.0), Vector2(32, 32)), false)


func _paint_kicks() -> void:
	for side in 2:
		var p := Vector2(300 if side == 0 else 900, 3470)
		_diamond(p, 10.0, Color(COLOURS["fire"], 1.0 if kickbacks[side] else 0.2))
		_text(p + Vector2(0, -16), "KICK", 11, Color(INK, 0.6 if kickbacks[side] else 0.25), _font, true, 1.0, 0)


func _paint_eye(e: Dictionary, node: Node2D) -> void:
	cv = node
	var c := Vector2(128, 128)
	var dark: Color = COLOURS["dark"]
	var open: bool = e.get("open", false)
	var flash: float = e.get("flash", 0.0)
	cv.draw_rect(Rect2(0, 0, 256, 256), dark.darkened(0.6))
	cv.draw_circle(c, 112.0, Color(0.97, 0.94, 0.88).lerp(Color(1, 0.5, 0.55), flash * 0.6))
	for j in 14:
		var ang: float = j * TAU / 14.0 + 0.3 + (e["p"] as Vector2).x
		var from: Vector2 = c + Vector2(cos(ang), sin(ang)) * 110.0
		var mid: Vector2 = from.lerp(c, 0.25) + Vector2(sin(ang * 3.0), cos(ang * 2.0)) * 6.0
		cv.draw_polyline(PackedVector2Array([from, mid, mid.lerp(c, 0.3)]), Color(0.82, 0.22, 0.3, 0.6), 2.0)
	var to := Vector2.ZERO
	var near: float = INF
	for ball in balls:
		var d: float = (ball["p"] as Vector2).distance_to(e["p"])
		if d < near:
			near = d
			to = ((ball["p"] as Vector2) - (e["p"] as Vector2)).normalized() * 34.0
	var iris: Color = dark.lerp(GOLD, 0.65 if open else 0.0)
	cv.draw_circle(c + to, 50.0, iris.darkened(0.35))
	cv.draw_circle(c + to, 42.0, iris)
	for j in 18:
		var ang: float = j * TAU / 18.0
		cv.draw_line(c + to + Vector2(cos(ang), sin(ang)) * 18.0, c + to + Vector2(cos(ang), sin(ang)) * 44.0, Color(iris.lightened(0.4), 0.55), 2.0)
	var slit: float = 9.0 + 12.0 * flash
	cv.draw_colored_polygon(PackedVector2Array([c + to + Vector2(0, -36), c + to + Vector2(slit, 0), c + to + Vector2(0, 36),
		c + to + Vector2(-slit, 0)]), Color(0.04, 0.01, 0.07))
	cv.draw_circle(c + to + Vector2(-14, -16), 9.0, Color(1, 1, 1, 0.92))
	var blink: float = fmod(t + (e["p"] as Vector2).x * 0.01, 4.3)
	if blink > 4.1:
		var shut: float = sin((blink - 4.1) / 0.2 * PI)
		cv.draw_rect(Rect2(0, 0, 256, 128 * shut), dark.darkened(0.5))
		cv.draw_rect(Rect2(0, 256 - 128 * shut, 256, 128 * shut), dark.darkened(0.5))
	cv.draw_arc(c, 114.0, 0, TAU, 64, dark.lightened(0.1), 8.0)


func _paint_hud() -> void:
	cv = hud_node
	var dark_k: float = _fx_k() if _effect_is("dark") else 0.0
	if dark_k > 0.0:
		# IN THE DARK: the ball leaves a trail of light, the monsters' eyes glow
		for ball in balls:
			if ball.has("ride") or ball["held"]:
				continue
			var trail: Array = ball["trail"]
			for i in range(trail.size() - 1):
				var a2: Vector2 = _screen(trail[i], BALL_R * S)
				var b2: Vector2 = _screen(trail[i + 1], BALL_R * S)
				var fade: float = 1.0 - float(i) / trail.size()
				cv.draw_line(a2, b2, Color(0.75, 0.65, 1.0, 0.55 * fade * dark_k), 2.0 + 9.0 * fade)
		for mb in mobs:
			if not _alive(mb) or int(mb["fl"]) != cam_floor:
				continue
			var a: Dictionary = MOB_ART[mb["kind"]]
			var hover: float = 0.0 if mb["kind"] == "skeleton" else 0.26 + 0.07 * sin(t * 3.0 + float(mb["phase"]))
			var body: Vector3 = _w(_mob_at(mb), float(FLOORS[mb["fl"]]["h"]) + hover + float(a["feet"]) * float(a["ps"]))
			var mid: Vector2 = cam3.unproject_position(body)
			var eye_at: Vector2 = cam3.unproject_position(body + Vector3(0, 0.12, 0))
			var c: Color = MOB_COLOUR[mb["kind"]]
			cv.draw_arc(mid, 34.0, 0, TAU, 28, Color(c, 0.55 * dark_k), 3.0)
			for sx in [-1.0, 1.0]:
				cv.draw_circle(eye_at + Vector2(sx * 6.0, 0), 7.0, Color(c, 0.35 * dark_k))
				cv.draw_circle(eye_at + Vector2(sx * 6.0, 0), 2.8, Color(1, 1, 0.9, 0.95 * dark_k))
		for h in horde:
			if _horde_on(h) and int(h["fl"]) == cam_floor:
				var e2: Vector2 = cam3.unproject_position(_w(_horde_at(h), float(FLOORS[h["fl"]]["h"]) + 0.45))
				for sx in [-1.0, 1.0]:
					cv.draw_circle(e2 + Vector2(sx * 5.0, 0), 5.0, Color(0.5, 1.0, 0.4, 0.4 * dark_k))
					cv.draw_circle(e2 + Vector2(sx * 5.0, 0), 2.2, Color(1, 1, 0.9, 0.95 * dark_k))
	for sp in sparks:
		var lift: float = 0.2 + float(sp.get("lift", 0.0))
		var p: Vector2 = _screen(sp["p"], lift)
		var q: Vector2 = _screen((sp["p"] as Vector2) - (sp["v"] as Vector2) * 0.03, lift - float(sp.get("rise", 0.0)) * 0.03)
		cv.draw_line(p, q, Color(sp["c"], clampf(sp["life"] / 0.4, 0.0, 1.0)), 2.0)
	# the mage's meteors, falling onto the bumpers
	var tower_top: Vector2 = cam3.unproject_position(_w(TOWER, TOWER_TOP + 0.55))
	for m in meteors:
		var left: float = float(m["at"]) - t
		var end: Vector2 = _screen(_meteor_end(m), 0.3)
		if left > 0.0 and left < 0.6:
			# the owner's meteor, thrown from the mage's tower in an arc
			var k: float = 1.0 - left / 0.6
			var start: Vector2 = tower_top
			var arc := func(u: float) -> Vector2: return start.lerp(end, u) + Vector2(0, -260.0 * sin(u * PI))
			var head: Vector2 = arc.call(k)
			for j in 6:
				var u0: float = maxf(0.0, k - 0.05 * (j + 1))
				cv.draw_line(arc.call(u0), arc.call(maxf(0.0, u0 + 0.05)), Color(1.0, 0.55 + j * 0.05, 0.2, 0.55 - j * 0.08), 12.0 - j * 1.5)
			cv.draw_circle(head, 20.0, Color(1.0, 0.6, 0.2, 0.35))
			cv.draw_texture_rect(meteor_tex, Rect2(head - Vector2(18, 18), Vector2(36, 36)), false)
		elif left <= 0.0 and left > -0.4:
			cv.draw_arc(end, 20.0 + 140.0 * -left, 0, TAU, 32, Color(1.0, 0.6, 0.25, 1.0 + left * 2.5), 4.0)
	for pp in popups:
		var k: float = 1.0 - pp["life"] / 0.9
		var a: float = minf(1.0, pp["life"] * 2.5)
		var at: Vector2 = _screen(pp["p"], 0.5) + Vector2(0, -24.0 * k)
		if at.x < 850.0:
			_text(at, pp["text"], 16, Color(pp["c"], a), null, true, a)
	# a ball on another floor (rare now): a marker at the edge, no window
	if not pip_ball.is_empty():
		var up: bool = floor_of((pip_ball["p"] as Vector2).y) > cam_floor
		var label: String = "A BALL IN " + str(FLOORS[floor_of((pip_ball["p"] as Vector2).y)]["name"])
		var wd: float = _width(label, 14)
		var y: float = 30.0 if up else 690.0
		cv.draw_rect(Rect2(430.0 - wd / 2.0 - 34.0, y - 18.0, wd + 68.0, 28.0), Color(0, 0, 0, 0.62))
		var pulse: float = 0.6 + 0.4 * sin(t * 8.0)
		for sx in [-1.0, 1.0]:
			var c := Vector2(430.0 + sx * (wd / 2.0 + 18.0), y - 4.0)
			var tip: float = -7.0 if up else 7.0
			cv.draw_colored_polygon(PackedVector2Array([c + Vector2(0, tip), c + Vector2(7, -tip), c + Vector2(-7, -tip)]), Color(GOLD, pulse))
		_text(Vector2(430, y + 1.0), label, 14, Color(GOLD, 0.95), null, true)
	_paint_cards()
	_paint_launch()
	_draw_end()


func _paint_panel_layer() -> void:
	"""The panel, under the rest of the HUD (the game over's dimming covers it)."""
	cv = panel_node
	_paint_panel()
	cv = hud_node


func _hero_region(w: String, i: int) -> Rect2:
	var a: Dictionary = HERO_ART[w]
	var fr: Array = hero_frames[w]
	var at: AtlasTexture = fr[i % fr.size()]
	var crop: Rect2 = a["crop"]
	return Rect2(at.region.position + crop.position, crop.size)


func _paint_cards() -> void:
	"""A HERO ARRIVES: the owner's sprite, big, on a card, for a moment."""
	if cards.is_empty():
		return
	var c: Dictionary = cards[cards.size() - 1]
	var age: float = t - float(c["at"])
	if age > 3.0:
		return
	var w: String = c["w"]
	var slide: float = ease(clampf(age / 0.3, 0.0, 1.0), 0.4) - ease(clampf((age - 2.7) / 0.3, 0.0, 1.0), 2.0)
	var box := Rect2(lerpf(-300.0, 18.0, slide), 18, 270, 300)
	_panel(box, HERO[w])
	cv.draw_rect(Rect2(box.position + Vector2(10, 10), Vector2(250, 214)), Color(HERO[w], 0.12))
	for i in 8:
		cv.draw_circle(box.position + Vector2(135, 125), 100.0 - i * 11.0, Color(HERO[w], 0.035))
	cv.draw_texture_rect_region(hero_tex[w], Rect2(box.position + Vector2(35, 22), Vector2(200, 200)), _hero_region(w, int(age * 10.0)))
	_text(box.position + Vector2(135, 254), str(HERO_NAME[w]), 26, HERO[w], null, true)
	_text(box.position + Vector2(135, 280), str(HERO_DOES[w]), 13, Color(INK, 0.85), _font, true)


func _paint_launch() -> void:
	"""THE LAUNCH, SEEN (0.168.2): the plunger's lane is under the panel and
	below the foot of the view, so "i could not tell if it was charging up".
	While a ball waits on it, a bar beside the panel fills as it is pulled
	(`pull`), gold to fire, with a mark each quarter; full, it says MAX."""
	if attract or not balls.any(func(b: Dictionary) -> bool: return b["held"]):
		return
	var box := LAUNCH_BOX
	cv.draw_rect(box.grow(5.0), Color(0.02, 0.015, 0.04, 0.88))
	var h: float = box.size.y * clampf(pull, 0.0, 1.0)
	if h > 0.0:
		cv.draw_rect(Rect2(box.position.x, box.end.y - h, box.size.x, h), GOLD.lerp(COLOURS["fire"], pull))
	for i in range(1, 4):
		var y: float = box.end.y - box.size.y * i / 4.0
		cv.draw_line(Vector2(box.position.x, y), Vector2(box.end.x, y), Color(INK, 0.35), 1.0)
	cv.draw_rect(box.grow(5.0), Color(GOLD, 0.85), false, 2.0)
	_text(Vector2(box.get_center().x, box.position.y - 14.0), "LAUNCH", 12, GOLD, _font, true)
	if pull >= 1.0:
		_text(Vector2(box.get_center().x, box.end.y + 22.0), "MAX", 13, COLOURS["fire"], _font, true)


func _paint_panel() -> void:
	var r := Rect2(862, 8, 404, 704)
	_panel(r, COLOURS["dark"])
	var e := Vector2(920, 58)
	cv.draw_circle(e, 30.0, COLOURS["dark"].darkened(0.5))
	cv.draw_circle(e, 25.0, Color(0.97, 0.94, 0.88))
	cv.draw_circle(e + Vector2(3, 2), 11.0, COLOURS["dark"])
	cv.draw_colored_polygon(PackedVector2Array([e + Vector2(3, -8), e + Vector2(6, 2), e + Vector2(3, 12), e + Vector2(0, 2)]),
		Color(0.04, 0.01, 0.07))
	cv.draw_arc(e, 27.0, 0, TAU, 40, GOLD, 2.0)
	_text(Vector2(964, 58), "PINBALL", 36, GOLD)
	_text(Vector2(966, 82), "THE BEHOLDER'S TABLE", 13, Color(INK, 0.75), _font)
	if purse_text != "":
		_text(Vector2(1240 - _width(purse_text, 15), 84), purse_text, 15, purse_colour)
	var d := Rect2(880, 100, 368, 126)
	cv.draw_rect(d.grow(4), Color(0, 0, 0, 0.8))
	cv.draw_rect(d, Color(0.06, 0.025, 0.01))
	var amber := Color(1.0, 0.56, 0.16)
	var line: String = _thousands(int(shown))
	var sub: String = _prompt()
	var sub_c: Color = amber
	if not banners.is_empty():
		var bn: Dictionary = banners[0]
		line = str(bn["text"])
		sub = str(bn["sub"]) if str(bn["sub"]) != "" else _thousands(int(shown))
		sub_c = (bn["c"] as Color).lerp(amber, 0.4)
	var big: int = 42 if banners.is_empty() else 34
	while big > 16 and _width(line, big) > d.size.x - 24.0:
		big -= 2
	_text(Vector2(d.get_center().x, d.position.y + 62), line, big, amber, null, true, 1.0, 0)
	var small: int = 18
	while small > 10 and _width(sub, small) > d.size.x - 24.0:
		small -= 1
	_text(Vector2(d.get_center().x, d.position.y + 102), sub, small, sub_c, null, true, 1.0, 0)
	var y: float = d.position.y
	while y < d.end.y:
		cv.draw_line(Vector2(d.position.x, y), Vector2(d.end.x, y), Color(0, 0, 0, 0.55), 1.5)
		y += 4.0
	var x: float = d.position.x
	while x < d.end.x:
		cv.draw_line(Vector2(x, d.position.y), Vector2(x, d.end.y), Color(0, 0, 0, 0.55), 1.5)
		x += 4.0
	cv.draw_rect(d, Color(amber, 0.25), false, 1.0)
	_text(Vector2(890, 252), "BALL", 13, Color(GOLD, 0.8))
	for i in 3:
		var p := Vector2(948.0 + i * 26.0, 247.0)
		var on: bool = i >= ball_no - 1
		cv.draw_circle(p, 8.0, Color(0.75, 0.77, 0.85) if on else Color(0.3, 0.3, 0.36))
		cv.draw_circle(p + Vector2(-2.5, -2.5), 2.5, Color(1, 1, 1, 0.9 if on else 0.2))
	if not tower_ball.is_empty():
		cv.draw_circle(Vector2(1036, 247), 8.0, HERO["MAGE"].lightened(0.3))
		_text(Vector2(1050, 252), "LOCKED", 11, HERO["MAGE"].lightened(0.3))
	_text(Vector2(1240 - _width("RANK  " + RANKS[rank], 15), 253), "RANK  ", 13, Color(GOLD, 0.8))
	_text(Vector2(1240 - _width(RANKS[rank], 15), 253), RANKS[rank], 15, INK)
	_divider(268, 890, 1240, Color(GOLD, 0.6))
	# the heroes, their sprites beside their words
	_text(Vector2(1064, 288), "THE HEROES", 14, GOLD, null, true)
	for i in WORDS.size():
		var w: String = WORDS[i]
		var yy: float = 298.0 + i * 31.0
		var c: Color = HERO[w]
		var active: bool = (w == "TANK" and shield_t > 0.0) or (w == "WARR" and whirl_t > 0.0) or (w == "HEAL" and t < save_until) \
			or (w == "MAGE" and t < mage_until)
		cv.draw_rect(Rect2(884, yy, 360, 28), Color(c, 0.16 if active else 0.04))
		cv.draw_texture_rect_region(hero_tex[w], Rect2(887, yy - 3, 32, 32), _hero_region(w, int(t * 8.0) if active else 0))
		for j in 4:
			var box := Rect2(926 + j * 27, yy + 3, 23, 22)
			var on: bool = j < int(words[w])
			cv.draw_rect(box, Color(c, 0.9) if on else Color(c, 0.12))
			cv.draw_rect(box, Color(c, 0.8), false, 1.0)
			_text(box.get_center() + Vector2(0, 6), w[j], 14, Color(0.05, 0.03, 0.08) if on else Color(c, 0.85), null, true, 1.0, 0)
		var power: String = str(POWER[w])
		if w == "TANK" and shield_t > 0.0:
			power += "  %ds" % ceili(shield_t)
		elif w == "WARR" and whirl_t > 0.0:
			power += "  %ds" % ceili(whirl_t)
		_text(Vector2(1236 - _width(power, 12), yy + 19), power, 12, c if active else Color(INK, 0.55))
		if w == "HEAL" and t < save_until:
			cv.draw_texture_rect(pack["largehealthpotion"], Rect2(1214 - _width(power, 12), yy + 2, 24, 24), false)
	_divider(428, 890, 1240, Color(GOLD, 0.6))
	# the shots: made of tried, and the odds
	_text(Vector2(1064, 446), "THE SHOTS  ·  MADE / TRIED", 14, GOLD, null, true)
	for i in SHOTS.size():
		var nm: String = SHOTS[i]
		var box := Rect2(888 + (i % 2) * 178, 455 + (i / 2) * 21, 172, 19)
		var tr: int = int(tries.get(nm, 0))
		var mk: int = int(makes.get(nm, 0))
		var fl: float = float(ramp_at[nm]["flash"]) if ramp_at.has(nm) else float(spirit["flash"])
		var riding: bool = balls.any(func(b: Dictionary) -> bool: return b.get("ride", "") == nm)
		cv.draw_rect(box, Color(GOLD, 0.05 + 0.25 * fl + (0.12 if riding else 0.0)))
		if tr > 0:
			cv.draw_rect(Rect2(box.position + Vector2(0, box.size.y - 3), Vector2(box.size.x * mk / tr, 3)), Color(0.5, 1.0, 0.55, 0.85))
		_text(box.position + Vector2(6, 14), str(SHOT_NAME[nm]), 12, INK if tr > 0 else Color(INK, 0.45), _font)
		var right: String = ("%d/%d  %d%%" % [mk, tr, roundi(100.0 * mk / tr)]) if tr > 0 else "-"
		if riding:
			right = "CLIMBING..."
		_text(Vector2(box.end.x - 6 - _width(right, 12), box.position.y + 14), right, 12, GOLD if riding else Color(INK, 0.8))
	_divider(566, 890, 1240, Color(GOLD, 0.6))
	# the floors
	for i in 3:
		var box := Rect2(888 + i * 119, 576, 113, 36)
		var here: bool = cam_floor == i
		var open: bool = open_floors[i]
		cv.draw_rect(box, Color(GOLD, 0.16) if here else Color(1, 1, 1, 0.03))
		cv.draw_rect(box, Color(GOLD, 0.7 if here else 0.2), false, 1.0)
		_text(box.position + Vector2(56, 15), str(FLOORS[i]["short"]), 14, INK if open else Color(INK, 0.4), null, true, 1.0, 0)
		var right: String = "OPEN" if open else _short(maxi(0, int(FLOORS[i]["opens"]) - score)) + " TO GO"
		if multiball and i == cam_floor:
			right = "MULTIBALL"
		_text(box.position + Vector2(56, 31), right, 11, GOLD if open else Color(0.95, 0.4, 0.35), null, true, 1.0, 0)
	# the Beholder's eyes: six lands and the crowned one
	_text(Vector2(890, 641), "THE BEHOLDER'S EYES", 12, GOLD)
	for i in 7:
		var box := Rect2(1040 + i * 29, 620, 26, 26)
		var got: bool = i < eye_drops.size() if i < 6 else done.has("crowned")
		cv.draw_rect(box, Color(0.04, 0.02, 0.06, 0.9))
		cv.draw_rect(box, Color(GOLD if i == 6 else Color(COLOURS[EYE_ORDER[i]]), 0.7 if got else 0.25), false, 1.0)
		if got:
			cv.draw_texture_rect(pack["eye_" + ("crowned" if i == 6 else EYE_ORDER[i])], box.grow(-1), false)
	_divider(658, 890, 1240, Color(GOLD, 0.6))
	var m: int = multiplier * lane_x * (3 if whirl_t > 0.0 else 1) * (2 if _effect_is("light") else 1)
	_text(Vector2(940, 682), "x%d" % m, 15, GOLD if m > 1 else Color(INK, 0.5), null, true)
	if synergy > 0:
		var pulse: float = 0.6 + 0.4 * sin(t * 10.0)
		cv.draw_rect(Rect2(972, 667, 116, 22), Color(GOLD, 0.2 * pulse))
		_text(Vector2(1030, 683), "SYNERGY x%d" % synergy, 14, GOLD, null, true)
	else:
		_text(Vector2(1030, 682), "SLAIN  %d" % slain, 14, Color(INK, 0.8), null, true)
	var land_txt: String = "LANDS  %d / 7" % lit.size()
	var land_c: Color = Color(INK, 0.7)
	if _warning_of() != "":
		land_txt = "%s IN %.1f" % [EFFECT[effect["land"]], float(effect["from"]) - t]
		land_c = (COLOURS[effect["land"]] as Color).lightened(0.3) if frame % 10 < 6 else Color(INK, 0.5)
	elif not effect.is_empty():
		land_txt = "%s  %ds" % [EFFECT[effect["land"]], ceili(float(effect["to"]) - t)]
		land_c = (COLOURS[effect["land"]] as Color).lightened(0.3)
	_text(Vector2(1168, 682), land_txt, 14, land_c, null, true)
	_text(Vector2(1064, 704), controls_hint, 11, Color(INK, 0.5), _font, true)


static func _short(n: int) -> String:
	if n >= 1000000:
		return "%.1fM" % (n / 1000000.0)
	if n >= 1000:
		return "%dK" % (n / 1000)
	return str(n)


func _prompt() -> String:
	var fl: int = cam_floor
	if fl == 0 and not tower_ball.is_empty():
		return "CLIMB THE TOWER FOR A FREE BALL"
	if not open_floors[1]:
		return "2ND FLOOR IN %s" % _thousands(maxi(0, int(FLOORS[1]["opens"]) - score))
	if fl == 0:
		return "SHOOT THE CLIMB"
	if fl == 1:
		if multiball:
			return "SHOOT THE EYES FOR JACKPOT"
		if not done.has("eyes"):
			return "OPEN BOTH EYES"
		return "SHOOT THE CLIMB" if open_floors[2] else "TOP FLOOR IN %s" % _thousands(maxi(0, int(FLOORS[2]["opens"]) - score))
	return "SINK THE LAIR"


func _chevron_up(p: Vector2, c: Color) -> void:
	cv.draw_polyline(PackedVector2Array([p + Vector2(-10, 8), p, p + Vector2(10, 8)]), c, 3.0)


func _chevron_down(p: Vector2, c: Color) -> void:
	cv.draw_polyline(PackedVector2Array([p + Vector2(-14, -10), p, p + Vector2(14, -10)]), c, 4.0)


func _arrow_insert(at: Vector2, ang: float, label: String, c: Color, on: float) -> void:
	var d := Vector2(cos(ang), sin(ang))
	var n := d.orthogonal()
	var pts := PackedVector2Array([at + d * 34.0, at + n * 20.0 - d * 8.0, at + n * 10.0 - d * 8.0, at + n * 10.0 - d * 30.0,
		at - n * 10.0 - d * 30.0, at - n * 10.0 - d * 8.0, at - n * 20.0 - d * 8.0])
	cv.draw_colored_polygon(pts, Color(c, 0.18 + 0.8 * on))
	pts.append(pts[0])
	cv.draw_polyline(pts, Color(c.lightened(0.3), 0.6 + 0.4 * on), 2.0)
	_text(at - d * 48.0 + Vector2(0, 6), label, 16, Color(INK, 0.5 + 0.5 * on), null, true, 1.0, 3)


func _draw_end() -> void:
	"""The game over: the table dims under the screen's score, and the pack's
	art is credited."""
	if not over:
		return
	cv.draw_rect(Rect2(0, 0, 1280, 720), Color(0.02, 0.02, 0.04, 0.6))
	_text(Vector2(430, 700), "items: Clockwork Raven Studios (Caio Carlos)", 12, Color(INK, 0.5), _font, true)

func _panel(r: Rect2, tint: Color = GOLD) -> void:
	cv.draw_rect(Rect2(r.position + Vector2(3, 5), r.size), Color(0, 0, 0, 0.45))
	var top := Color(0.085, 0.09, 0.14, 0.98)
	var foot := Color(0.04, 0.042, 0.07, 0.98)
	cv.draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([top, top, foot, foot]))
	cv.draw_rect(Rect2(r.position + Vector2(2, 2), Vector2(r.size.x - 4, 1.5)), Color(1, 1, 1, 0.08))
	cv.draw_rect(r, EDGE, false, 2.0)
	cv.draw_rect(r.grow(-4), Color(tint, 0.22), false, 1.0)
	for corner in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		_diamond(corner, 5.0, GOLD)


func _diamond(at: Vector2, size: float, c: Color) -> void:
	cv.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -size), at + Vector2(size, 0), at + Vector2(0, size),
		at + Vector2(-size, 0)]), c)
	cv.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -size * 0.45), at + Vector2(size * 0.45, 0),
		at + Vector2(0, size * 0.45), at + Vector2(-size * 0.45, 0)]), Color(c.darkened(0.6), c.a))


func _divider(y: float, x0: float, x1: float, c: Color) -> void:
	var mid: float = (x0 + x1) / 2.0
	cv.draw_polygon(PackedVector2Array([Vector2(x0, y - 0.5), Vector2(mid, y - 1.0), Vector2(x1, y - 0.5), Vector2(x1, y + 0.5),
		Vector2(mid, y + 1.0), Vector2(x0, y + 0.5)]), PackedColorArray([Color(c, 0.0), Color(c, 0.6 * c.a), Color(c, 0.0),
		Color(c, 0.0), Color(c, 0.6 * c.a), Color(c, 0.0)]))
	_diamond(Vector2(mid, y), 3.5, c)


func _width(s: String, size: int) -> float:
	return _bold.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


func _text(at: Vector2, s: String, size: int, c: Color, f: Font = null, centre: bool = false, alpha: float = 1.0,
		outline: int = 4) -> void:
	var use: Font = _bold if f == null else f
	if centre:
		at.x -= use.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x / 2.0
	if outline > 0:
		cv.draw_string_outline(use, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, Color(0, 0, 0, 0.75 * alpha))
	cv.draw_string(use, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, c)


# =============================================================================
# THE NEW MECHANICS (pinball 9)
# =============================================================================
# THE SPINNER across the tower lane: a ball through it spins it, every half
# turn scores, and its spins light THE WELL. THE BONE WALL: four of the
# owner's skeletons standing at the top of the town; knock all four down and
# THE BEHOLDER'S GAZE lights - a magnet in the plaza that holds the next
# ball, spins it and flings it at a shot. THE CAGED SPIRIT: a second ball
# shut in a short lane; knock it to the top three times and it goes free
# with an eye of the Beholder. THE WELL on the high street: lit, it takes
# the ball and gives a prize from the pack (gold, coins, a potion, a loot
# bag). THE TANK'S shield lights the kickbacks again. On the field, THE
# CROWNED'S GATE (his gate) cracks over four hits and falls; the ball in the
# keep starts a SIEGE: the Crowned (his boss) walks the field for 25 s.
# And THE HIGH WIRE: a small flipper on the field's left feeds a wire ramp
# high over everything, down to the right inlane.

func _reset_new() -> void:
	spinner = {"a": 0.0, "w": 0.0, "half": 0, "flash": 0.0}
	spins_to_well = WELL_EVERY
	skels.clear()
	for x in SKEL_X:
		skels.append({"x": x, "down": false, "flash": 0.0})
	skels_back = -1.0
	skel_level = 0
	magnet_lit = false
	spirit = {"y": CAGE_REST, "v": 0.0, "trips": 0, "flash": 0.0, "hit_t": -9.0}
	well = {"lit": false, "prize": "", "at": -9.0}
	gate = {"hp": GATE_HP, "open": false, "flash": 0.0, "hit_t": -9.0, "fall_t": -9.0, "rebuild": -1.0}
	siege = {}
	for k in ["spins", "skels", "skel_banks", "magnet", "trips", "spirit", "wire", "well", "gate_hits", "gate_down",
			"siege", "siege_won", "relit", "lanes", "lane_ups", "stalks"]:
		stats[k] = 0
	# the caged spirit's lane
	_wall(Vector2(CAGE_X - 30.0, CAGE_TOP), Vector2(CAGE_X - 30.0, CAGE_MOUTH))
	_wall(Vector2(CAGE_X + 30.0, CAGE_TOP), Vector2(CAGE_X + 30.0, CAGE_MOUTH))
	_wall(Vector2(CAGE_X - 30.0, CAGE_TOP), Vector2(CAGE_X + 30.0, CAGE_TOP))
	# the Crowned's keep: three walls and the drawbridge
	_wall(Vector2(KEEP.x - 55.0, KEEP_BACK), Vector2(KEEP.x - 55.0, BRIDGE_Y))
	_wall(Vector2(KEEP.x + 55.0, KEEP_BACK), Vector2(KEEP.x + 55.0, BRIDGE_Y))
	_wall(Vector2(KEEP.x - 55.0, KEEP_BACK), Vector2(KEEP.x + 55.0, KEEP_BACK))
	var br: Dictionary = _wall(Vector2(KEEP.x - 52.0, BRIDGE_Y), Vector2(KEEP.x + 52.0, BRIDGE_Y), "bridge")
	br["r"] = 4.0
	# the high wire's little flipper, on the field's left
	flippers.append({"pivot": MINI_PIVOT, "side": 1.0, "len": 84.0, "a": REST, "adot": 0.0, "hold": 0.0, "cool": 0.0,
		"aim": 0.5, "late": 0.0, "floor": 1, "mini": true})
	_ramp("WIRE", WIRE_PTS, WIRE_HIGH)
	ramp_at["WIRE"]["mw"] = 40.0
	ramp_at["WIRE"]["mh"] = 22.0


func _new_parts(ball: Dictionary, dt: float) -> bool:
	"""The new pieces a ball meets this step. True when one has taken it."""
	var p: Vector2 = ball["p"]
	var v: Vector2 = ball["v"]
	var fl: int = floor_of(p.y)
	if fl == 0:
		# THE SPINNER: crossing its line, inside the lane
		var before: float = p.y - v.y * dt
		if absf(p.x - SPIN_AT.x) < SPIN_HALF and (before - SPIN_AT.y) * (p.y - SPIN_AT.y) <= 0.0 and absf(v.y) > 60.0:
			spinner["w"] = minf(70.0, float(spinner["w"]) + absf(v.y) / 40.0)
			spinner["flash"] = 1.0
		# THE BONE WALL
		for sk in skels:
			if sk["down"]:
				continue
			var r := Rect2(float(sk["x"]), SKEL_Y, SKEL_W, 14.0)
			var c := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
			var d: Vector2 = p - c
			if d.length_squared() >= BALL_R * BALL_R or d.length_squared() < 0.0001:
				continue
			var n: Vector2 = d.normalized()
			ball["p"] = c + n * BALL_R
			var vn: float = v.dot(n)
			if vn < 0.0:
				v -= n * vn * 1.4
			ball["v"] = v
			sk["down"] = true
			sk["flash"] = 1.0
			stats["skels"] += 1
			_gain(50000, r.get_center() + Vector2(0, 40), Color(0.95, 0.92, 0.8))
			_burst(r.get_center(), Color(0.95, 0.92, 0.8), 14)
			_drop_loot(r.get_center() + Vector2(0, 20), 0, "coppercoin", 2)
			if skels.all(func(x: Dictionary) -> bool: return x["down"]):
				skel_level += 1
				stats["skel_banks"] += 1
				skels_back = t + 3.0
				magnet_lit = true
				_gain(250000 * skel_level, Vector2(650, SKEL_Y - 40), GOLD)
				_banner("THE BONE WALL FALLS", "THE BEHOLDER'S GAZE IS LIT", COLOURS["dark"].lightened(0.45))
			return false
		# THE CAGED SPIRIT: the ball against the ball in the cage
		var cp := Vector2(CAGE_X, float(spirit["y"]))
		var dc: Vector2 = p - cp
		if dc.length_squared() < (2.0 * BALL_R) * (2.0 * BALL_R) and dc.length_squared() > 0.0001:
			var n: Vector2 = dc.normalized()
			ball["p"] = cp + n * 2.0 * BALL_R
			var rel: Vector2 = v - Vector2(0, float(spirit["v"]))
			var vn: float = rel.dot(n)
			if vn < 0.0:
				var j: float = -vn * 0.96
				ball["v"] = v + n * j
				spirit["v"] = float(spirit["v"]) - n.y * j
				if -vn > 200.0 and t - float(spirit["hit_t"]) > 0.3:
					spirit["hit_t"] = t
					tries["CAGE"] = int(tries.get("CAGE", 0)) + 1
					_gain(20000, cp + Vector2(0, -40), SPIRIT_C)
		# THE BEHOLDER'S GAZE
		if magnet_lit and not holds.has("magnet") and p.distance_to(MAGNET) < 46.0 and v.length() < 1950.0:
			magnet_lit = false
			stats["magnet"] += 1
			_take(ball, "magnet", MAGNET, 0.85)
			_gain(100000, MAGNET + Vector2(0, -60), COLOURS["dark"].lightened(0.45))
			_banner("THE BEHOLDER'S GAZE", "HELD  ·  FLUNG", COLOURS["dark"].lightened(0.45))
			return true
		# THE WELL
		if well["lit"] and not holds.has("well") and p.distance_to(WELL) < 30.0 and v.length() < 1800.0:
			well["lit"] = false
			stats["well"] += 1
			_take(ball, "well", WELL, 1.5)
			_well_prize()
			return true
		# THE KEEP: the ball in it starts the siege
		if gate["open"] and siege.is_empty() and not holds.has("throne") and Rect2(KEEP.x - 52.0, KEEP_BACK, 104.0, BRIDGE_Y - KEEP_BACK - 8.0).has_point(p):
			_take(ball, "throne", KEEP, 1.4)
			_start_siege()
			return true
		# THE RIGHT ORBIT: lit, the Well takes the ball off its top
		if well["lit"] and not holds.has("well") and p.x > ORBIT_X and p.x < 1180.0 and p.y < 2700.0 and p.y > 2660.0 and v.y < -200.0:
			well["lit"] = false
			stats["well"] += 1
			_take(ball, "well", WELL, 1.5)
			_well_prize()
			return true
	# THE TOP LANES: a ball rolling down through one lights it
	for si in LANE_SETS.size():
		var ls: Dictionary = LANE_SETS[si]
		var ly: float = ls["y"]
		var before_y: float = p.y - v.y * dt
		if int(ls["fl"]) == fl and v.y > 0.0 and before_y < ly and p.y >= ly:
			var xs: Array = ls["xs"]
			for li in 3:
				if p.x > float(xs[li]) and p.x < float(xs[li + 1]):
					_lane(si, li, p)
	return false


func _lane(si: int, li: int, at: Vector2) -> void:
	var row: Array = lanes[si]
	if row[li]:
		_gain(10000, at + Vector2(0, -30), GOLD)
		return
	row[li] = true
	stats["lanes"] += 1
	_gain(30000, at + Vector2(0, -30), GOLD)
	if row.all(func(x: bool) -> bool: return x):
		lanes[si] = [false, false, false]
		lane_x = mini(4, lane_x + 1)
		stats["lane_ups"] += 1
		_banner(str(LANE_SETS[si]["done"]), "EVERY SCORE x%d" % lane_x, GOLD)


func _lane_change(side: float, fl: int) -> void:
	"""THE LEVERS: a flip moves its floor's lit top lanes along - the left
	flipper to the left, the right to the right."""
	for si in LANE_SETS.size():
		if int(LANE_SETS[si]["fl"]) != fl:
			continue
		var row: Array = lanes[si]
		if side > 0.0:
			lanes[si] = [row[1], row[2], row[0]]
		else:
			lanes[si] = [row[2], row[0], row[1]]


func _take(ball: Dictionary, what_name: String, at: Vector2, hold: float) -> void:
	ball["sunk"] = what_name
	ball["p"] = at
	ball["v"] = Vector2.ZERO
	holds[what_name] = {"t": hold, "ball": ball}
	shake = maxf(shake, 0.2)
	_burst(at, GOLD, 18)


func _release(what_name: String, ball: Dictionary) -> void:
	"""Out of one of the new holes: the magnet flings at a shot, the well and
	the keep put the ball back down the table."""
	match what_name:
		"magnet":
			var goal: Vector2 = PORTAL
			var up: Array = skels.filter(func(x: Dictionary) -> bool: return not x["down"])
			if not up.is_empty():
				goal = Vector2(float(up[rng.randi() % up.size()]["x"]) + SKEL_W / 2.0, SKEL_Y + 7.0)
			ball["p"] = MAGNET
			ball["v"] = (goal - MAGNET).normalized() * 1650.0
			_burst(MAGNET, COLOURS["dark"].lightened(0.45), 20)
		"well":
			ball["p"] = WELL + Vector2(0, 24)
			ball["v"] = Vector2(rng.randf_range(-160.0, 160.0), 380.0)
		"throne":
			ball["p"] = Vector2(KEEP.x, BRIDGE_Y + 22.0)
			ball["v"] = Vector2(rng.randf_range(-220.0, 220.0), 520.0)
		_:
			ball["v"] = Vector2(0, 300)


func _magnet_step(_dt: float) -> void:
	if holds.has("magnet"):
		var ball: Dictionary = holds["magnet"]["ball"]
		if ball.get("sunk", "") == "magnet":
			ball["p"] = MAGNET + Vector2(cos(t * 16.0), sin(t * 16.0)) * 9.0


func _spirit_step(dt: float) -> void:
	"""The caged ball rolls back down its lane; at the top it is a trip."""
	var sv: float = float(spirit["v"]) + GRAVITY * 0.9 * dt
	sv -= sv * 0.5 * dt
	var sy: float = float(spirit["y"]) + sv * dt
	var top: float = CAGE_TOP + 3.0 + BALL_R
	if sy <= top:
		sy = top
		if sv < -120.0:
			_spirit_trip()
		sv = -sv * 0.3
	if sy >= CAGE_REST:
		sy = CAGE_REST
		sv = minf(sv, 0.0)
	spirit["v"] = sv
	spirit["y"] = sy


func _spirit_trip() -> void:
	spirit["trips"] = int(spirit["trips"]) + 1
	spirit["flash"] = 1.0
	stats["trips"] += 1
	makes["CAGE"] = int(makes.get("CAGE", 0)) + 1
	var at := Vector2(CAGE_X, CAGE_TOP + 20.0)
	if int(spirit["trips"]) < 3:
		_gain(150000, at + Vector2(0, -50), SPIRIT_C)
		_banner("THE SPIRIT STIRS", "%d OF 3" % int(spirit["trips"]), SPIRIT_C)
		_burst(at, SPIRIT_C, 16)
		return
	spirit["trips"] = 0
	stats["spirit"] += 1
	_gain(750000, at + Vector2(0, -60), SPIRIT_C)
	_banner("THE CAGED SPIRIT IS FREE", "AN EYE OF THE BEHOLDER", SPIRIT_C)
	_burst(at, SPIRIT_C, 34)
	shake = maxf(shake, 0.3)
	_drop_eye(at)


func _well_prize() -> void:
	var pick: String = ["goldpile", "goldcoin", "largehealthpotion", "lootbag"][rng.randi() % 4]
	well["prize"] = pick
	well["at"] = t
	match pick:
		"goldpile":
			_gain(1500000, WELL + Vector2(0, -70), GOLD)
			_banner("THE WELL", "A PILE OF GOLD  ·  1,500,000", GOLD)
		"goldcoin":
			_gain(750000, WELL + Vector2(0, -70), GOLD)
			_banner("THE WELL", "GOLD COINS  ·  750,000", GOLD)
			_drop_loot(WELL, 0, "goldcoin", 6)
		"largehealthpotion":
			save_until = maxf(save_until, t + 15.0)
			_banner("THE WELL", "A HEALTH POTION  ·  BALL SAVE", HERO["HEAL"])
		_:
			_gain(250000, WELL + Vector2(0, -70), GOLD)
			_banner("THE WELL", "A LOOT BAG  ·  TWO LETTERS", GOLD)
			_letter(WORDS[rng.randi() % 4], WELL)
			_letter(WORDS[rng.randi() % 4], WELL)


func _gate_hit(at: Vector2) -> void:
	if gate["open"] or t - float(gate["hit_t"]) < 0.3:
		return
	gate["hit_t"] = t
	gate["hp"] = int(gate["hp"]) - 1
	gate["flash"] = 1.0
	stats["gate_hits"] += 1
	shake = maxf(shake, 0.18)
	_burst(at, Color(0.85, 0.55, 0.25), 14)
	if int(gate["hp"]) > 0:
		_gain(75000, at + Vector2(0, -40), GOLD)
		if not quiet:
			popups.append({"p": at + Vector2(0, -90), "text": "THE GATE  %d" % int(gate["hp"]), "life": 0.9, "c": GOLD})
		return
	gate["open"] = true
	gate["fall_t"] = t
	stats["gate_down"] += 1
	_gain(500000, at + Vector2(0, -60), GOLD)
	_banner("THE CROWNED'S GATE FALLS", "SHOOT THE KEEP", GOLD)


func _start_siege() -> void:
	"""THE SIEGE: the Crowned walks out onto the field; 25 s to bring him down."""
	stats["siege"] += 1
	var m: Dictionary = {"kind": "crowned", "fl": floor_of(KEEP.y), "path": "line", "a": Vector2(380, 2905), "b": Vector2(820, 2905),
		"speed": 0.55, "phase": PI / 2.0 - t * 0.55, "hp": 6, "max": 6, "r": 34.0, "back": t + 1.4, "died": -100.0,
		"hurt": -100.0, "dpos": Vector2(KEEP.x, 2905), "worth": 3000000}
	if crowned_node != null:
		m["node"] = crowned_node
	mobs.append(m)
	siege = {"mob": m, "until": t + 1.4 + SIEGE_SECONDS, "at": t}
	_gain(500000, KEEP + Vector2(0, -80), Color(1.0, 0.4, 0.4))
	_banner("SIEGE!", "THE CROWNED COMES OUT  ·  25s", Color(1.0, 0.4, 0.4))


func _new_frame() -> void:
	var k: float = 1.0 / FPS
	# the spinner: it turns, slows (slower in the updraft), counts half turns
	var w: float = spinner["w"]
	var a: float = float(spinner["a"]) + w * k
	spinner["w"] = w * exp(-(0.8 if _effect_is("wind") else 1.6) * k)
	if float(spinner["w"]) < 0.4:
		spinner["w"] = 0.0
	spinner["a"] = a
	spinner["flash"] = maxf(0.0, float(spinner["flash"]) - k * 3.0)
	var halves: int = int(floor(a / PI))
	while int(spinner["half"]) < halves:
		spinner["half"] = int(spinner["half"]) + 1
		stats["spins"] += 1
		score += 5000 * multiplier
		spins_to_well -= 1
		if spins_to_well <= 0:
			spins_to_well = WELL_EVERY
			if not well["lit"]:
				well["lit"] = true
				_banner("THE WELL IS LIT", "ON THE HIGH STREET", GOLD)
	# the bone wall stands again
	if skels_back > 0.0 and t >= skels_back:
		skels_back = -1.0
		for sk in skels:
			sk["down"] = false
	for sk in skels:
		sk["flash"] = maxf(0.0, float(sk["flash"]) - k * 3.0)
	spirit["flash"] = maxf(0.0, float(spirit["flash"]) - k * 2.0)
	gate["flash"] = maxf(0.0, float(gate["flash"]) - k * 3.0)
	# the siege: won, or the Crowned gets away; then the gate is built again
	if not siege.is_empty():
		var m: Dictionary = siege["mob"]
		if float(m["died"]) > float(siege["at"]):
			if t - float(m["died"]) > 0.4:
				stats["siege_won"] += 1
				_banner("THE CROWNED FALLS", "THE SIEGE IS WON", GOLD)
				_end_siege()
		elif t > float(siege["until"]):
			_banner("THE CROWNED ESCAPES", "THE GATE IS BUILT AGAIN", Color(1.0, 0.4, 0.4))
			_end_siege()
	if gate["open"] and siege.is_empty() and float(gate["rebuild"]) > 0.0 and t >= float(gate["rebuild"]):
		var inside: bool = balls.any(func(b: Dictionary) -> bool: return Rect2(KEEP.x - 58.0, KEEP_BACK, 116.0, BRIDGE_Y - KEEP_BACK + 14.0).has_point(b["p"]))
		if not inside:
			gate["open"] = false
			gate["hp"] = GATE_HP
			gate["rebuild"] = -1.0


func _end_siege() -> void:
	var m: Dictionary = siege["mob"]
	mobs.erase(m)
	siege = {}
	gate["rebuild"] = t + 2.0


func _goal_new(f: Dictionary, left: bool) -> Vector2:
	"""The attract mode's player wants the new shots too."""
	if f.get("mini", false):
		return ramp_at["WIRE"]["mouth"]
	var r: float = rng.randf()
	match int(f["floor"]):
		0:
			if not siege.is_empty() and _alive(siege["mob"]) and r < 0.6:
				return _mob_at(siege["mob"])
			if gate["open"] and siege.is_empty() and r < 0.6:
				return KEEP
			if well["lit"] and left and r < 0.45:
				return Vector2(1145, 2900)
			if magnet_lit and r < 0.3:
				return MAGNET
			if open_floors[1] and not multiball and stats["floor2_first"] < 0.0 and r < 0.5:
				return ramp_at["UP2"]["mouth"]
		1:
			if not left and r < 0.25:
				# up the field's left side: down the wall onto the wire's flipper
				return Vector2(150, 1440)
			if left and r < 0.18:
				return Vector2(1140, 1600)
		2:
			var want_bank: int = 3 if left else 2
			var up: Array = targets.filter(func(x: Dictionary) -> bool: return int(x["bank"]) == want_bank and not x["down"])
			if not up.is_empty() and r < 0.35:
				return (up[rng.randi() % up.size()]["rect"] as Rect2).get_center() + Vector2(0, 6)
	return Vector2.INF


func _map_extra() -> Array:
	return [["circle", MAGNET.x, MAGNET.y, 40, [200, 120, 255]], ["circle", WELL.x, WELL.y, 24, [255, 220, 90]],
		["line", SPIN_AT.x - SPIN_HALF, SPIN_AT.y, SPIN_AT.x + SPIN_HALF, SPIN_AT.y, [255, 255, 0]],
		["circle", CAGE_X, CAGE_REST, 10, [150, 220, 255]], ["circle", KEEP.x, KEEP.y, 26, [255, 90, 90]],
		["text", SPIN_AT.x + 10, SPIN_AT.y + 8, "SPIN", [255, 255, 0]]] + _map_skels()


func _map_skels() -> Array:
	var out: Array = []
	for x in SKEL_X:
		out.append(["line", x, SKEL_Y + 7.0, x + SKEL_W, SKEL_Y + 7.0, [240, 235, 210]])
	return out


# ---- the new pieces in 3D ---------------------------------------------------

var spinner_node: Node3D
var spinner_mat: StandardMaterial3D
var skel_sprites: Array = []
var skel_faces: Array = []
var magnet_mat: StandardMaterial3D
var spirit_node: MeshInstance3D
var spirit_mat: StandardMaterial3D
var well_item: Sprite3D
var gate_hinge: Node3D
var gate_mat: StandardMaterial3D
var door_node: MeshInstance3D
var crown_node: Sprite3D
var crowned_node: Sprite3D


func _build_new() -> void:
	var h0: float = 0.0
	var h1: float = float(FLOORS[floor_of(KEEP.y)]["h"])
	var metal := _mat(Color(0.82, 0.72, 0.5), 0.9, 0.25)
	# the spinner: a gold blade on an axle across the lane
	spinner_node = Node3D.new()
	spinner_node.position = _w(SPIN_AT, h0 + 0.14)
	world.add_child(spinner_node)
	var blade := BoxMesh.new()
	blade.size = Vector3(SPIN_HALF * 2.0 * S - 0.04, 0.13, 0.012)
	spinner_mat = _mat(GOLD, 0.8, 0.25, 0.2)
	_put(blade, spinner_mat, Vector3.ZERO, spinner_node)
	for sx in [-1.0, 1.0]:
		_cyl(0.025, 0.24, metal, _w(SPIN_AT + Vector2(sx * SPIN_HALF, 0), h0 + 0.12))
	# the bone wall: a ledge, and a skeleton on a stone for each target
	var stone := _mat(Color(0.3, 0.27, 0.32), 0.05, 0.85)
	var ledge := BoxMesh.new()
	ledge.size = Vector3((SKEL_X[3] + SKEL_W - SKEL_X[0] + 16.0) * S, 0.08, 0.1)
	_put(ledge, stone, _w(Vector2((SKEL_X[0] + SKEL_X[3] + SKEL_W) / 2.0, SKEL_Y - 10.0), h0 + 0.04))
	for x in SKEL_X:
		var face := BoxMesh.new()
		face.size = Vector3(SKEL_W * S, 0.14, 14.0 * S)
		var fm := _mat(Color(0.92, 0.88, 0.76), 0.0, 0.6, 0.15)
		var fn: MeshInstance3D = _put(face, fm, _w(Vector2(float(x) + SKEL_W / 2.0, SKEL_Y + 7.0), h0 + 0.07))
		skel_faces.append(fn)
		extra_keep.append(fn)
		var sp: Sprite3D = _sprite(0.019)
		sp.texture = mob_frames["skeleton"]["right"][0]
		sp.position = _w(Vector2(float(x) + SKEL_W / 2.0, SKEL_Y + 4.0), h0 + 0.14 + 16.0 * 0.019)
		skel_sprites.append(sp)
	# the Beholder's gaze: a socket in the plaza
	var disc := CylinderMesh.new()
	disc.top_radius = 0.3
	disc.bottom_radius = 0.32
	disc.height = 0.03
	disc.radial_segments = 32
	magnet_mat = _mat(COLOURS["dark"].lightened(0.3), 0.3, 0.3, 0.2)
	extra_keep.append(_put(disc, magnet_mat, _w(MAGNET, h0 + 0.015)))
	# the caged spirit: bars along its lane, and the ball inside
	var bar := _mat(Color(0.7, 0.85, 1.0), 0.8, 0.25)
	for sx in [-1.0, 1.0]:
		var y: float = CAGE_TOP + 12.0
		while y < CAGE_MOUTH:
			_cyl(0.008, 0.22, bar, _w(Vector2(CAGE_X + sx * 30.0, y), h0 + 0.11))
			y += 26.0
	var top_bar := BoxMesh.new()
	top_bar.size = Vector3(0.62, 0.02, 0.02)
	_put(top_bar, bar, _w(Vector2(CAGE_X, CAGE_TOP), h0 + 0.22))
	var sm := SphereMesh.new()
	sm.radius = BALL_R * S
	sm.height = BALL_R * S * 2.0
	spirit_mat = _mat(SPIRIT_C, 0.4, 0.2, 1.2)
	spirit_node = _put(sm, spirit_mat, _w(Vector2(CAGE_X, CAGE_REST), h0 + BALL_R * S))
	extra_keep.append(spirit_node)
	# the well: a stone rim, and what comes up out of it
	var rim := TorusMesh.new()
	rim.inner_radius = 0.22
	rim.outer_radius = 0.34
	rim.rings = 32
	_put(rim, stone, _w(WELL, h0 + 0.03))
	well_item = _sprite(0.022)
	well_item.visible = false
	# the Crowned's keep: the owner's cobble walls, battlements, his gate
	var keep_mat := _mat(Color(0.62, 0.58, 0.7), 0.05, 0.85)
	keep_mat.albedo_texture = tiles["cobble"]
	keep_mat.uv1_scale = Vector3(3, 1, 1)
	keep_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	for pair in [[Vector2(KEEP.x - 55.0, KEEP_BACK), Vector2(KEEP.x - 55.0, BRIDGE_Y)],
			[Vector2(KEEP.x + 55.0, KEEP_BACK), Vector2(KEEP.x + 55.0, BRIDGE_Y)],
			[Vector2(KEEP.x - 55.0, KEEP_BACK), Vector2(KEEP.x + 55.0, KEEP_BACK)]]:
		_box_between(pair[0], pair[1], h1, 0.3, 0.07, keep_mat)
	for i in 6:
		var x: float = KEEP.x - 55.0 + i * 22.0
		var cren := BoxMesh.new()
		cren.size = Vector3(0.09, 0.07, 0.08)
		_put(cren, keep_mat, _w(Vector2(x, KEEP_BACK), h1 + 0.335))
	for sx in [-1.0, 1.0]:
		for y in [KEEP_BACK + 22.0, KEEP_BACK + 66.0]:
			var cren := BoxMesh.new()
			cren.size = Vector3(0.08, 0.07, 0.09)
			_put(cren, keep_mat, _w(Vector2(KEEP.x + sx * 55.0, y), h1 + 0.335))
	gate_hinge = Node3D.new()
	gate_hinge.position = _w(Vector2(KEEP.x, BRIDGE_Y), h1)
	world.add_child(gate_hinge)
	var gq := QuadMesh.new()
	gq.size = Vector2(1.04, 0.3)
	gate_mat = _mat(Color(1, 1, 1), 0.0, 0.7)
	gate_mat.albedo_texture = load("res://art/doors/gateclosed.png")
	gate_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	gate_mat.uv1_scale = Vector3(3, 1, 1)
	gate_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	gate_mat.emission_enabled = true
	gate_mat.emission = Color(1.0, 0.7, 0.35)
	gate_mat.emission_energy_multiplier = 0.0
	_put(gq, gate_mat, Vector3(0, 0.15, 0.004), gate_hinge)
	var dq := QuadMesh.new()
	dq.size = Vector2(1.04, 0.3)
	var dmat := _mat(Color(1, 1, 1), 0.0, 0.8)
	dmat.albedo_texture = load("res://art/doors/gateopen.png")
	dmat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	dmat.uv1_scale = Vector3(3, 1, 1)
	door_node = _put(dq, dmat, _w(Vector2(KEEP.x, BRIDGE_Y), h1 + 0.15))
	door_node.visible = false
	extra_keep.append(door_node)
	crown_node = _sprite(0.012)
	crown_node.texture = load("res://art/enemy/behemothcrown.png")
	crowned_node = _sprite(float(MOB_ART["crowned"]["ps"]))
	crowned_node.visible = false
	for m in mobs:
		if m["kind"] == "crowned":
			m["node"] = crowned_node


func _sync_new() -> void:
	var h0: float = 0.0
	var h1: float = float(FLOORS[floor_of(KEEP.y)]["h"])
	spinner_node.rotation.x = float(spinner["a"])
	spinner_mat.emission_energy_multiplier = 0.2 + 1.8 * float(spinner["flash"])
	for i in skels.size():
		var sk: Dictionary = skels[i]
		var down: bool = sk["down"]
		(skel_faces[i] as MeshInstance3D).position.y = h0 + (-0.08 if down else 0.07)
		var sp: Sprite3D = skel_sprites[i]
		sp.visible = not down
		sp.modulate = Color(3.0, 3.0, 3.0) if float(sk["flash"]) > 0.6 else Color(1, 1, 1)
		if not down:
			var fr: Array = mob_frames["skeleton"]["right"]
			sp.texture = fr[int(t * 6.0 + i * 2) % fr.size()]
	var pulse: float = 0.5 + 0.5 * sin(t * 6.0)
	magnet_mat.emission_energy_multiplier = (1.4 + 1.6 * pulse) if magnet_lit or holds.has("magnet") else 0.15
	spirit_node.position = _w(Vector2(CAGE_X, float(spirit["y"])), h0 + BALL_R * S)
	spirit_mat.emission_energy_multiplier = 0.9 + 0.5 * sin(t * 3.0) + 3.0 * float(spirit["flash"])
	var wage: float = t - float(well["at"])
	well_item.visible = holds.has("well") and wage < 1.5
	if well_item.visible:
		well_item.texture = pack[well["prize"]]
		well_item.position = _w(WELL, h0 + 0.05 + minf(1.0, wage / 0.9) * 0.55 + 0.04 * sin(t * 5.0))
	# the gate: it flashes when struck, falls flat as a bridge when broken
	gate_mat.emission_energy_multiplier = 2.5 * float(gate["flash"])
	gate_mat.albedo_color = Color(1, 1, 1).lerp(Color(0.75, 0.5, 0.4), 1.0 - float(gate["hp"]) / float(GATE_HP)) if not gate["open"] else Color(1, 1, 1)
	var want: float = PI / 2.0 if gate["open"] else 0.0
	if gate["open"]:
		var fall: float = clampf((t - float(gate["fall_t"])) / 0.35, 0.0, 1.0)
		want = PI / 2.0 * fall * fall
	gate_hinge.rotation.x = want if gate["open"] else lerpf(gate_hinge.rotation.x, 0.0, 0.3)
	door_node.visible = gate["open"] or gate_hinge.rotation.x > 0.05
	crown_node.visible = siege.is_empty()
	crown_node.position = _w(Vector2(KEEP.x + 34.0, KEEP_BACK + 4.0), h1 + 0.43 + 0.04 * sin(t * 2.5))
	crown_node.modulate = Color(1.6, 1.4, 1.0) if gate["open"] else Color(1, 1, 1)
	if siege.is_empty():
		crowned_node.visible = false


# ---- the new pieces painted ---------------------------------------------------

func _paint_still_more() -> void:
	# the top lanes' floor, the spinner's lane, the bone wall's ledge, the
	# plaza's socket, the spirit's cage, the well, the keep's floor and its
	# throne
	for ls in LANE_SETS:
		var xs: Array = ls["xs"]
		cv.draw_rect(Rect2(float(xs[0]), float(ls["top"]) - 2.0, float(xs[3]) - float(xs[0]), 70.0), Color(0.05, 0.03, 0.08, 0.55))
	# the eyestalks' ledges
	for bank in STALKS:
		cv.draw_rect(Rect2(float(bank[0]) - 8.0, STALK_Y - 14.0, float(bank[2]) + 34.0 - float(bank[0]), 12.0), Color(0.12, 0.06, 0.16, 0.85))
	cv.draw_rect(Rect2(SPIN_AT.x - SPIN_HALF, SPIN_AT.y - 9.0, SPIN_HALF * 2.0, 18.0), Color(0.05, 0.03, 0.08, 0.55))
	cv.draw_rect(Rect2(SKEL_X[0] - 8.0, SKEL_Y - 18.0, SKEL_X[3] + SKEL_W - SKEL_X[0] + 16.0, 14.0), Color(0.12, 0.1, 0.14, 0.8))
	cv.draw_circle(MAGNET, 40.0, Color(0.05, 0.03, 0.08, 0.7))
	cv.draw_arc(MAGNET, 40.0, 0, TAU, 40, Color(GOLD, 0.45), 2.0)
	cv.draw_rect(Rect2(CAGE_X - 27.0, CAGE_TOP, 54.0, CAGE_MOUTH - CAGE_TOP), Color(0.04, 0.07, 0.12, 0.75))
	cv.draw_circle(WELL, 36.0, Color(0.3, 0.28, 0.32))
	cv.draw_circle(WELL, 23.0, Color(0.0, 0.0, 0.02, 0.97))
	cv.draw_rect(Rect2(KEEP.x - 52.0, KEEP_BACK + 3.0, 104.0, BRIDGE_Y - KEEP_BACK - 3.0), Color(0.1, 0.07, 0.1, 0.9))
	cv.draw_circle(KEEP, 24.0, Color(0.0, 0.0, 0.0, 0.95))
	cv.draw_arc(KEEP, 26.0, 0, TAU, 32, Color(1.0, 0.4, 0.4, 0.5), 2.0)


func _paint_moving_more(fl: int, chase: float) -> void:
	if fl == 0:
		_text(SPIN_AT + Vector2(SPIN_HALF + 26.0, 6.0), "%d" % spins_to_well, 14, Color(GOLD, 0.6 + 0.4 * float(spinner["flash"])), null, true, 1.0, 0)
		for i in skels.size():
			var sk: Dictionary = skels[i]
			_diamond(Vector2(float(sk["x"]) + SKEL_W / 2.0, SKEL_Y + 34.0), 8.0, Color(0.95, 0.92, 0.8, 0.95 if sk["down"] else 0.28))
		_arrow_insert(Vector2(SKEL_X[0] + 2.0 * SKEL_W, SKEL_Y + 96.0), -PI / 2.0, "BONES", Color(0.95, 0.92, 0.8), 0.25 + 0.5 * chase)
		var lit_m: bool = magnet_lit or holds.has("magnet")
		for i in 3:
			var r: float = 46.0 + i * 14.0 + (6.0 * sin(t * 6.0 - i) if lit_m else 0.0)
			cv.draw_arc(MAGNET, r, 0, TAU, 40, Color(COLOURS["dark"].lightened(0.4), (0.6 - i * 0.15) if lit_m else 0.12), 3.0)
		_text(MAGNET + Vector2(0, 74), "GAZE", 14, Color(COLOURS["dark"].lightened(0.5), 1.0 if lit_m and frame % 16 < 10 else 0.3), null, true, 1.0, 0)
		for i in 3:
			_diamond(Vector2(CAGE_X + 50.0, CAGE_TOP + 40.0 + i * 30.0), 8.0, Color(SPIRIT_C, 0.95 if i < int(spirit["trips"]) else 0.25))
		_arrow_insert(Vector2(CAGE_X, CAGE_MOUTH + 70.0), -PI / 2.0, "SPIRIT", SPIRIT_C, 0.3 + 0.5 * (1.0 - chase))
		if well["lit"] or holds.has("well"):
			cv.draw_circle(WELL, 30.0 + 4.0 * sin(t * 8.0), Color(GOLD, 0.35))
			cv.draw_arc(WELL, 40.0, 0, TAU, 40, Color(GOLD, 0.9), 3.0)
			_text(WELL + Vector2(0, 66), "THE WELL", 14, Color(GOLD, 1.0 if frame % 16 < 10 else 0.5), null, true, 1.0, 0)
		else:
			for i in 5:
				var x: float = WELL.x - 20.0 + i * 10.0
				cv.draw_line(Vector2(x, WELL.y - 18.0), Vector2(x, WELL.y + 18.0), Color(0.45, 0.42, 0.45, 0.9), 3.0)
	if fl == floor_of(KEEP.y):
		if not gate["open"]:
			for i in GATE_HP:
				_diamond(Vector2(KEEP.x + (i - 1.5) * 26.0, BRIDGE_Y + 30.0), 8.0, Color(GOLD, 0.95 if i < int(gate["hp"]) else 0.2))
			_arrow_insert(Vector2(KEEP.x, BRIDGE_Y + 90.0), -PI / 2.0, "GATE", GOLD, 0.3 + 0.5 * chase)
		elif siege.is_empty():
			_arrow_insert(Vector2(KEEP.x, BRIDGE_Y + 90.0), -PI / 2.0, "KEEP", Color(1.0, 0.4, 0.4), 1.0 if frame % 16 < 10 else 0.4)
		else:
			var left: float = maxf(0.0, float(siege["until"]) - t)
			_text(Vector2(KEEP.x, BRIDGE_Y + 44.0), "SIEGE  %ds" % ceili(left), 16, Color(1.0, 0.4, 0.4, 1.0 if frame % 16 < 10 else 0.6), null, true, 1.0, 0)
	if fl == 1:
		var m: Vector2 = ramp_at["WIRE"]["mouth"]
		_arrow_insert(m + Vector2(0, 80), -PI / 2.0, "WIRE", GOLD, maxf(float(ramp_at["WIRE"]["flash"]), 0.3 + 0.4 * chase))
