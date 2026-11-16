# crownfallboss.gd - a Crownfall boss (0.162.0): the fight on every fifth map.
#
# The owner: "more bosses for other maps". Every kingdom has the same five, made
# from its own land's monsters and drawn from their own art (sprite_of()):
#   map 5    the Slime King (its large slime) - SPLITS: every SPLIT_EVERY hits
#            he spits a small slime that hops across the bricks, planting
#            blight where it lands on nothing; the ball kills one.
#   map 10   the Sprite (its sprite) - DARTS about its hall and BLINKS to
#            another spot every BLINK_EVERY, throwing sparks in pairs.
#   map 15   the Sniper (its bush sniper) - MARKS A COLUMN where the paddle
#            is (a line for AIM_SECONDS), then fires down it: a paddle still
#            under it is stunned. Get out of the line.
#   map 20   the Bush Mage (its bush mage) - four WARDS circle it and stop the
#            ball (each breaks, and grows back after WARD_BACK), and every
#            REBUILD_EVERY it rebuilds broken bricks near its hall as stone.
#   map 25   the ruler (the land's own boss, the crown) - throws; under two
#            thirds of its health it splits like the Slime King, under a third
#            it marks columns like the Sniper too.
# THE KINGDOM OF WIND (0.163.0) has its own five, from its own monsters:
#   map 5    the Gale King (its large slime) - splits like the Slime King,
#            and every GALE_EVERY stamps: a gust out of him knocks every
#            ball within GALE_REACH sideways, away from him.
#   map 10   the Whirlwind (its sprite) - darts and blinks like the Sprite,
#            and every WHIRL_EVERY spins up a vortex that wanders the open
#            field: a ball it touches is caught, spun SPIN_SECONDS and
#            thrown out any way at all (the owner's "whirlwind throws balls
#            diff directions").
#   map 15   the Gust Sniper (its bush sniper) - fires a FAN of three shots
#            at the paddle (five under half its health).
#   map 20   the Storm Mage (its bush mage) - wards and rebuilding like the
#            Bush Mage, and a WIND WALL under his hall WALL_ON in every
#            WALL_EVERY that blows a rising ball back down.
#   map 25   the Tempest (the wind's boss, the crown) - throws; a TORNADO
#            that never stops wanders the field, catching balls and throwing
#            them out any way; under two thirds he splits, under a third a
#            second tornado comes.
# THE KINGDOM OF WATER (0.164.0) has its own five:
#   map 5    the Tide King (its large slime) - splits like the Slime King,
#            but his young turn to water bricks where they land on nothing;
#            and every TIDE_CALL_EVERY he calls the tide in early.
#   map 10   the Undine (its sprite) - darts and throws sparks like the
#            Sprite; every DIVE_EVERY it dives under the water, where nothing
#            can hit it (DIVE_SECONDS), and comes up somewhere else in a
#            SPLASH that throws every ball within SPLASH_REACH away from it.
#   map 15   the Harpooner (its bush sniper) - aims a harpoon at the paddle
#            down a line it shows (AIM_SECONDS), then throws: a paddle still
#            there is hooked, tugged toward him and slowed (TUG_SECONDS); the
#            rope hangs ROPE_SECONDS as a wall the ball bounces off.
#   map 20   the Tide Mage (its bush mage) - a BUBBLE round him that takes
#            BUBBLE_HITS to pop, then he is open BUBBLE_DOWN before it forms
#            again; every REBUILD_EVERY he raises bubble bricks near his hall.
#   map 25   the Leviathan (the water's boss, the crown) - throws; every
#            WAVE_EVERY a TIDAL WAVE crosses the field: the balls it passes
#            are carried along its way, and it leaves WAVE_BRICKS water bricks
#            in its wake at most; under two thirds he splits (his young turn
#            to water like the Tide King's), at half health he dives once,
#            and under a third the waves come faster.
# Every one walks its hall (the map's R cells), takes the ball's and the
# lasers' hits, and - but the Sniper - throws at the paddle (a hit stuns it).
# It is down at no health: the run says so, and its walls crumble.
#
# Data and rules only, plus its own drawing (draw(), called inside the run's
# _draw()). The pictures - its own and its minions' - are AnimatedSprite2D
# children of the run. No class_name; the run preloads it.
extends RefCounted

const KINDS := ["slimeking", "sprite", "sniper", "mage", "ruler",
	"galeking", "whirlwind", "gustsniper", "stormmage", "tempest",
	"tideking", "undine", "harpooner", "tidemage", "leviathan"]
# Each kingdom's five, in the order of its stretches.
const KINDS_OF := {"light": ["slimeking", "sprite", "sniper", "mage", "ruler"],
	"wind": ["galeking", "whirlwind", "gustsniper", "stormmage", "tempest"],
	"water": ["tideking", "undine", "harpooner", "tidemage", "leviathan"]}
# TOUGH (the owner: "bosses die too fast we really need to buff up bosses",
# and "hitting with a ball does a bit more damage"): a ball's hit is the run's
# BALL_HIT (3), a laser's 1, and a fight is about twice the ball hits it was.
const HP := {"slimeking": 180, "sprite": 160, "sniper": 190, "mage": 200, "ruler": 300,
	"galeking": 220, "whirlwind": 200, "gustsniper": 240, "stormmage": 250, "tempest": 380,
	"tideking": 240, "undine": 220, "harpooner": 260, "tidemage": 275, "leviathan": 420}
# How big each is drawn (their frames differ: a slime 48 px, a mage 150).
const SCALE := {"slimeking": 3.0, "sprite": 1.7, "sniper": 2.3, "mage": 1.3, "ruler": 2.2, "minion": 1.25,
	"galeking": 3.0, "whirlwind": 1.7, "gustsniper": 2.3, "stormmage": 1.3, "tempest": 2.2,
	"tideking": 3.0, "undine": 1.7, "harpooner": 2.3, "tidemage": 1.3, "leviathan": 2.2}
const BODY := {"slimeking": Vector2(66, 46), "sprite": Vector2(40, 40), "sniper": Vector2(44, 52),
	"mage": Vector2(56, 64), "ruler": Vector2(70, 70),
	"galeking": Vector2(66, 46), "whirlwind": Vector2(40, 40), "gustsniper": Vector2(44, 52),
	"stormmage": Vector2(56, 64), "tempest": Vector2(70, 70),
	"tideking": Vector2(66, 46), "undine": Vector2(40, 40), "harpooner": Vector2(44, 52),
	"tidemage": Vector2(56, 64), "leviathan": Vector2(70, 70)}
const WALK_SPEED := 110.0
const THROW_EVERY := 2.3
const SHOT_SPEED := 250.0
const STUN_SECONDS := 0.8
# THE SLIME KING'S SPLIT
const SPLIT_EVERY := 15   # damage, so every five ball hits
const MINIONS_MOST := 5
const HOP_SECONDS := 0.55
const HOP_HEIGHT := 26.0
const MINION_R := 12.0
const PLANT_CHANCE := 0.55
# THE SPRITE
const DART_SPEED := 320.0
const BLINK_EVERY := 3.5
const SPARK_EVERY := 1.6
const SPARK_SPEED := 330.0
# THE SNIPER (and the ruler's last third)
const SNIPE_EVERY := 3.4
const AIM_SECONDS := 1.0
const BEAM_SECONDS := 0.3
const BEAM_HALF := 14.0
# THE BUSH MAGE
const WARDS := 4
const WARD_RING := 54.0
const WARD_R := 9.0
const WARD_SPIN := 1.6
const WARD_BACK := 6.0
const REBUILD_EVERY := 5.0
const REBUILD_COUNT := 3
# THE RULER
const RULER_SPLIT_EVERY := 18   # damage, so every six ball hits
# THE GALE KING
const GALE_EVERY := 3.2
const GALE_REACH := 320.0
const GALE_KICK := 380.0
const GALE_SHOWN := 0.5
# THE WHIRLWIND, and the Tempest's tornado
const WHIRL_EVERY := 4.5
const WHIRL_LIFE := 6.0
const VORTEX_R := 44.0
const TORNADO_R := 62.0
const VORTEX_SPEED := 70.0
const SPIN_SECONDS := 0.6
const FREE_SECONDS := 0.5
# THE GUST SNIPER
const FAN_EVERY := 3.0
const FAN_SPREAD := 16.0
# THE STORM MAGE
const WALL_EVERY := 6.0
const WALL_ON := 2.5
const WALL_TALL := 26.0
# THE TIDE KING
const TIDE_CALL_EVERY := 12.0
# THE UNDINE, and the Leviathan's one dive
const DIVE_EVERY := 6.0
const DIVE_SECONDS := 2.0
const SPLASH_REACH := 260.0
const SPLASH_KICK := 1.15
# THE HARPOONER
const HARPOON_EVERY := 3.6
const HARPOON_SPEED := 1100.0
const TUG_SECONDS := 1.2
const ROPE_SECONDS := 1.2
# THE TIDE MAGE
const BUBBLE_HITS := 3
const BUBBLE_R := 50.0
const BUBBLE_DOWN := 5.0
# THE LEVIATHAN
const WAVE_EVERY := 9.0
const WAVE_SPEED := 460.0
const WAVE_WARN := 0.8
const WAVE_W := 46.0
const WAVE_BRICKS := 8

var run: Node2D = null
# The run's arena, its paddle's line and the foot of its view, handed in.
var arena := Rect2()
var paddle_y: float = 0.0
var view_bottom: float = 0.0
var kind: String = "slimeking"
var title: String = ""
var enemy_id: String = ""
var minion_id: String = ""
var land: String = "light"
var crowned: bool = false
var hall := Rect2()
var p := Vector2.ZERO
var hp: int = 30
var most: int = 30
var dir: float = 1.0
var flash: float = 0.0
var throw_t: float = THROW_EVERY
var hits_since_split: int = 0
var shots: Array = []
var dest := Vector2.ZERO
var blink_t: float = BLINK_EVERY
var snipe_t: float = SNIPE_EVERY
var aim_left: float = 0.0
var beam_left: float = 0.0
var beam_x: float = 0.0
var rebuild_t: float = REBUILD_EVERY
# Each ward: {back} - how long until it grows back (0: up).
var wards: Array = []
var _beam_hit: bool = false
var gale_t: float = GALE_EVERY
var gales: Array = []           # {"p", "age"}: the Gale King's stamps, drawn
var vortices: Array = []        # {"p", "v", "life", "r", "forever"}
var whirl_t: float = WHIRL_EVERY
var fan_t: float = FAN_EVERY
var wall_t: float = WALL_EVERY
var wall_left: float = 0.0
var second_storm: bool = false
var call_t: float = TIDE_CALL_EVERY
var dive_t: float = DIVE_EVERY
var dive_left: float = 0.0       # under the water: nothing can hit it
var dived: bool = false          # the Leviathan's one dive taken
var splashes: Array = []         # {"p", "age"}, drawn
# The harpoon: aimed (aim_left, along harpoon_from -> harpoon_to), flying
# (harpoon_u 0..1), then its rope hanging (rope_left).
var harpoon_t: float = HARPOON_EVERY
var harpoon_from := Vector2.ZERO
var harpoon_to := Vector2.ZERO
var harpoon_u: float = -1.0
var harpoon_aim: float = 0.0
var rope_left: float = 0.0
var bubble_hits: int = BUBBLE_HITS
var bubble_down: float = 0.0
# The Leviathan's wave: {"x", "way", "warn", "made"}; null between.
var wave = null
var wave_t: float = WAVE_EVERY
# Each minion: {p, from, to, t (into its hop), rest, sprite}.
var minions: Array = []
var sprite: AnimatedSprite2D = null


func setup(on_run: Node2D, info: Dictionary, land_id: String, the_hall: Rect2, the_arena: Rect2,
		paddle_line: float, foot: float) -> void:
	run = on_run
	arena = the_arena
	paddle_y = paddle_line
	view_bottom = foot
	kind = str(info.get("kind", "slimeking"))
	if not KINDS.has(kind):
		kind = "slimeking"
	title = str(info.get("name", "The Guardian"))
	enemy_id = str(info.get("enemy", ""))
	minion_id = str(info.get("minion", ""))
	crowned = bool(info.get("crown", false))
	land = land_id
	hall = the_hall
	most = int(HP.get(kind, 30))
	hp = most
	p = hall.get_center() + Vector2(0, 4)
	dest = p
	if kind == "tempest":
		vortices.append(_vortex(TORNADO_R, true))
	if kind == "mage" or kind == "stormmage":
		for i in WARDS:
			wards.append({"back": 0.0})
	if enemy_id != "":
		sprite = sprite_of(enemy_id, float(SCALE.get(kind, 2.0)))
		if sprite != null:
			run.add_child(sprite)
			sprite.position = p


func alive() -> bool:
	return hp > 0


func body_rect() -> Rect2:
	var size: Vector2 = BODY.get(kind, Vector2(60, 50))
	return Rect2(p - size / 2.0, size)


func clear() -> void:
	"""Its pictures gone with the map."""
	if sprite != null and is_instance_valid(sprite):
		sprite.queue_free()
	sprite = null
	for m in minions:
		_free_minion(m)
	minions.clear()
	shots.clear()


func step(dt: float, playing: bool) -> void:
	flash = maxf(0.0, flash - dt * 5.0)
	if hp > 0 and playing:
		match kind:
			"sprite":
				_dart(dt)
			"sniper":
				_walk(dt, 0.55)
				_snipe(dt)
			"mage":
				_walk(dt, 0.7)
				_ward_step(dt)
				_throw(dt, 1.3)
			"galeking":
				_walk(dt, 1.0)
				_throw(dt, 1.0)
				_gale(dt)
			"whirlwind":
				_dart(dt)
				whirl_t -= dt
				if whirl_t <= 0.0:
					whirl_t = WHIRL_EVERY * (0.75 if hp * 2 < most else 1.0)
					vortices.append(_vortex(VORTEX_R, false))
			"gustsniper":
				_walk(dt, 0.55)
				_fan(dt)
			"stormmage":
				_walk(dt, 0.7)
				_ward_step(dt)
				_throw(dt, 1.3)
				_wall(dt)
			"tempest":
				_walk(dt, 0.8)
				_throw(dt, 0.8 if hp * 3 < most else 1.0)
				if hp * 3 < most and not second_storm:
					second_storm = true
					vortices.append(_vortex(TORNADO_R, true))
			"tideking":
				_walk(dt, 1.0)
				_throw(dt, 1.0)
				call_t -= dt
				if call_t <= 0.0:
					call_t = TIDE_CALL_EVERY * (0.75 if hp * 2 < most else 1.0)
					run.call("tide_now")
					flash = 0.6
			"undine":
				_dive(dt)
				if dive_left <= 0.0:
					_dart(dt)
			"harpooner":
				_walk(dt, 0.5)
				_harpoon(dt)
			"tidemage":
				_walk(dt, 0.7)
				_throw(dt, 1.3)
				_bubble_step(dt)
			"leviathan":
				if hp * 2 < most and not dived:
					dived = true
					dive_left = DIVE_SECONDS + 0.5
					dest = _hall_spot()
					run.call("burst_at", p, land, 24)
				if dive_left > 0.0:
					_dive(dt)
				else:
					_walk(dt, 0.8)
					_throw(dt, 0.8 if hp * 3 < most else 1.0)
				_wave(dt)
			"ruler":
				_walk(dt, 0.8)
				_throw(dt, 0.8 if hp * 3 < most else 1.0)
				if hp * 3 < most:
					_snipe(dt)
			_:
				_walk(dt, 1.0)
				_throw(dt, 1.0)
	if sprite != null and is_instance_valid(sprite):
		sprite.position = p + Vector2(0, -6)
		sprite.visible = hp > 0
		sprite.self_modulate = Color(1, 1, 1).lerp(Color(4, 4, 4), flash * 0.5)
		sprite.modulate.a = 0.18 if dive_left > 0.0 else 1.0
	_step_shots(dt)
	_step_minions(dt, playing)
	_step_winds(dt, playing)
	for s in splashes:
		s["age"] += dt
	splashes = splashes.filter(func(s: Dictionary) -> bool: return float(s["age"]) < GALE_SHOWN)
	rope_left = maxf(0.0, rope_left - dt)


func hittable() -> bool:
	"""Whether a ball or a laser can strike its body now: alive, not under
	the water, not inside its bubble."""
	return hp > 0 and dive_left <= 0.0 and not (kind == "tidemage" and bubble_hits > 0)


func _walk(dt: float, pace: float) -> void:
	p.x += dir * WALK_SPEED * pace * dt
	if p.x < hall.position.x + 40.0 or p.x > hall.end.x - 40.0:
		dir = -dir
		p.x = clampf(p.x, hall.position.x + 40.0, hall.end.x - 40.0)


func _throw(dt: float, every: float) -> void:
	throw_t -= dt
	if throw_t <= 0.0:
		throw_t = THROW_EVERY * every * (0.7 if hp * 2 < most else 1.0)
		var from: Vector2 = p + Vector2(0, 24)
		var to := Vector2(float(run.get("paddle_x")), paddle_y)
		shots.append({"p": from, "v": (to - from).normalized() * SHOT_SPEED})


func _hall_spot() -> Vector2:
	var rng: RandomNumberGenerator = run.get("rng")
	return Vector2(rng.randf_range(hall.position.x + 36.0, hall.end.x - 36.0),
		rng.randf_range(hall.position.y + 24.0, maxf(hall.position.y + 24.0, hall.end.y - 20.0)))


func _dart(dt: float) -> void:
	"""THE SPRITE: darts from spot to spot in its hall, blinks every
	BLINK_EVERY, and throws sparks in pairs."""
	p = p.move_toward(dest, DART_SPEED * dt)
	if p.distance_to(dest) < 4.0:
		dest = _hall_spot()
	blink_t -= dt
	if blink_t <= 0.0:
		blink_t = BLINK_EVERY
		run.call("burst_at", p, land, 14)
		p = _hall_spot()
		dest = _hall_spot()
		flash = 1.0
		run.call("burst_at", p, land, 14)
	throw_t -= dt
	if throw_t <= 0.0:
		throw_t = SPARK_EVERY * (0.75 if hp * 2 < most else 1.0)
		var to := Vector2(float(run.get("paddle_x")), paddle_y)
		for turn in [-12.0, 12.0]:
			shots.append({"p": p + Vector2(0, 16), "v": (to - p).normalized().rotated(deg_to_rad(turn)) * SPARK_SPEED})


func _snipe(dt: float) -> void:
	"""THE SNIPER: a column marked where the paddle is, AIM_SECONDS, then a
	beam down it for BEAM_SECONDS - the paddle under it is stunned, once."""
	if beam_left > 0.0:
		beam_left -= dt
		var paddle_x: float = float(run.get("paddle_x"))
		if absf(paddle_x - beam_x) < float(run.get("paddle_w")) / 2.0 + BEAM_HALF and not _beam_hit:
			_beam_hit = true
			run.call("stun_paddle", STUN_SECONDS, Vector2(beam_x, paddle_y), land)
		return
	if aim_left > 0.0:
		aim_left -= dt
		if aim_left <= 0.0:
			beam_left = BEAM_SECONDS
			_beam_hit = false
		return
	snipe_t -= dt
	if snipe_t <= 0.0:
		snipe_t = SNIPE_EVERY * (0.75 if hp * 2 < most else 1.0)
		aim_left = AIM_SECONDS
		beam_x = float(run.get("paddle_x"))



func _ward_step(dt: float) -> void:
	"""THE BUSH MAGE: its wards grow back; it rebuilds broken bricks."""
	for w in wards:
		w["back"] = maxf(0.0, float(w["back"]) - dt)
	rebuild_t -= dt
	if rebuild_t <= 0.0:
		rebuild_t = REBUILD_EVERY
		run.call("rebuild_near", REBUILD_COUNT, hall)


func ward_at(i: int) -> Vector2:
	return p + Vector2.from_angle(float(run.get("t")) * WARD_SPIN + i * TAU / WARDS) * WARD_RING


func ward_touch(at: Vector2, reach: float) -> Vector2:
	"""A ward the ball (or a laser) at `at` meets: it breaks, and where it
	stood is handed back to bounce off. Vector2.INF for none."""
	if hp <= 0:
		return Vector2.INF
	if kind == "tidemage" and bubble_hits > 0:
		# THE TIDE MAGE'S BUBBLE: a hit off it, BUBBLE_HITS and it pops
		if p.distance_to(at) <= BUBBLE_R + reach:
			bubble_hits -= 1
			flash = 0.5
			run.call("burst_at", at, land, 8)
			if bubble_hits <= 0:
				bubble_down = BUBBLE_DOWN
				run.call("burst_at", p, land, 30)
				splashes.append({"p": p, "age": 0.0})
			return p
		return Vector2.INF
	for i in wards.size():
		if float(wards[i]["back"]) <= 0.0:
			var w: Vector2 = ward_at(i)
			if w.distance_to(at) <= WARD_R + reach:
				wards[i]["back"] = WARD_BACK
				run.call("burst_at", w, land, 10)
				return w
	return Vector2.INF


func _step_shots(dt: float) -> void:
	var paddle_x: float = float(run.get("paddle_x"))
	var paddle_w: float = float(run.get("paddle_w"))
	for s in shots:
		s["p"] += s["v"] * dt
		if absf(s["p"].x - paddle_x) < paddle_w / 2.0 + 6.0 and absf(s["p"].y - paddle_y) < 12.0:
			s["dead"] = true
			run.call("stun_paddle", STUN_SECONDS, s["p"], land)
		if s["p"].y > view_bottom:
			s["dead"] = true
	shots = shots.filter(func(s: Dictionary) -> bool: return not s.get("dead", false))


func hit(n: int) -> bool:
	"""`n` hits taken; true when this one brought it down."""
	if hp <= 0:
		return false
	hp = maxi(0, hp - n)
	flash = 1.0
	var kingly: bool = kind == "slimeking" or kind == "galeking" or kind == "tideking"
	var splits: bool = kingly or ((kind == "ruler" or kind == "tempest" or kind == "leviathan") and hp * 3 < most * 2)
	if splits and hp > 0:
		var every: int = SPLIT_EVERY if kingly else RULER_SPLIT_EVERY
		hits_since_split += n
		while hits_since_split >= every:
			hits_since_split -= every
			_split()
	if hp <= 0:
		for m in minions:
			run.call("burst_at", m["p"], land, 14)
			_free_minion(m)
		minions.clear()
		shots.clear()
		vortices.clear()
		wall_left = 0.0
		wave = null
		rope_left = 0.0
		harpoon_u = -1.0
		aim_left = 0.0
		dive_left = 0.0
		return true
	return false


# ---------------------------------------------------------------- the waters --

func _dive(dt: float) -> void:
	"""UNDER THE WATER: nothing can hit it; it drifts to a new spot in its
	hall and comes up in a SPLASH. The Undine dives every DIVE_EVERY, the
	Leviathan once (step())."""
	if dive_left > 0.0:
		dive_left -= dt
		p = p.move_toward(dest, DART_SPEED * 0.6 * dt)
		if dive_left <= 0.0:
			dive_left = 0.0
			splashes.append({"p": p, "age": 0.0})
			run.call("splash_from", p, SPLASH_REACH, SPLASH_KICK)
			flash = 1.0
		return
	if kind != "undine":
		return
	dive_t -= dt
	if dive_t <= 0.0:
		dive_t = DIVE_EVERY * (0.75 if hp * 2 < most else 1.0)
		dive_left = DIVE_SECONDS
		dest = _hall_spot()
		run.call("burst_at", p, land, 18)


func _harpoon(dt: float) -> void:
	"""THE HARPOONER: a line to where the paddle is, AIM_SECONDS, then the
	harpoon down it; a paddle still there is hooked; the rope hangs."""
	if harpoon_u >= 0.0:
		harpoon_u += dt * HARPOON_SPEED / maxf(1.0, harpoon_from.distance_to(harpoon_to))
		if harpoon_u >= 1.0:
			harpoon_u = -1.0
			rope_left = ROPE_SECONDS
			var paddle_x: float = float(run.get("paddle_x"))
			if absf(paddle_x - harpoon_to.x) < float(run.get("paddle_w")) / 2.0 + 8.0:
				run.call("tug_paddle", TUG_SECONDS, harpoon_from.x, land)
			else:
				run.call("burst_at", harpoon_to, land, 10)
		return
	if harpoon_aim > 0.0:
		harpoon_aim -= dt
		if harpoon_aim <= 0.0:
			harpoon_u = 0.0
		return
	harpoon_t -= dt
	if harpoon_t <= 0.0:
		harpoon_t = HARPOON_EVERY * (0.7 if hp * 2 < most else 1.0)
		harpoon_aim = AIM_SECONDS
		harpoon_from = p + Vector2(0, 20)
		harpoon_to = Vector2(float(run.get("paddle_x")), paddle_y)


func _bubble_step(dt: float) -> void:
	"""THE TIDE MAGE: his bubble forms again BUBBLE_DOWN after it pops; he
	raises bubble bricks near his hall every REBUILD_EVERY."""
	if bubble_hits <= 0:
		bubble_down -= dt
		if bubble_down <= 0.0:
			bubble_hits = BUBBLE_HITS
			run.call("burst_at", p, land, 16)
	rebuild_t -= dt
	if rebuild_t <= 0.0:
		rebuild_t = REBUILD_EVERY
		run.call("rebuild_near", REBUILD_COUNT, hall, "bubble")


func _wave(dt: float) -> void:
	"""THE LEVIATHAN'S TIDAL WAVE: a warning at one side (WAVE_WARN), then a
	wall of water across the field at WAVE_SPEED, leaving a few water bricks
	in its wake."""
	var rng: RandomNumberGenerator = run.get("rng")
	if wave == null:
		wave_t -= dt
		if wave_t <= 0.0:
			wave_t = WAVE_EVERY * (0.7 if hp * 3 < most else 1.0)
			var way: float = 1.0 if rng.randf() < 0.5 else -1.0
			wave = {"x": arena.position.x if way > 0.0 else arena.end.x, "way": way, "warn": WAVE_WARN, "made": 0,
				"n": rng.randi()}
		return
	if float(wave["warn"]) > 0.0:
		wave["warn"] = float(wave["warn"]) - dt
		return
	wave["x"] = float(wave["x"]) + float(wave["way"]) * WAVE_SPEED * dt
	if int(wave["made"]) < WAVE_BRICKS and rng.randf() < dt * 6.0:
		if bool(run.call("wave_brick", float(wave["x"]) - float(wave["way"]) * WAVE_W, hall.end.y)):
			wave["made"] = int(wave["made"]) + 1
	if float(wave["x"]) < arena.position.x - WAVE_W or float(wave["x"]) > arena.end.x + WAVE_W:
		wave = null


func wave_band() -> Rect2:
	"""The wall of water as it stands (empty between waves and while it warns)."""
	if wave == null or float(wave["warn"]) > 0.0:
		return Rect2()
	var top: float = hall.end.y + 8.0
	return Rect2(float(wave["x"]) - WAVE_W / 2.0, top, WAVE_W, paddle_y - 70.0 - top)


# ---------------------------------------------------------------- the winds --

func _gale(dt: float) -> void:
	"""THE GALE KING STAMPS: a gust out of him, every ball near knocked away."""
	gale_t -= dt
	if gale_t > 0.0:
		return
	gale_t = GALE_EVERY * (0.75 if hp * 2 < most else 1.0)
	gales.append({"p": p, "age": 0.0})
	run.call("gale_from", p, GALE_REACH, GALE_KICK)
	flash = 0.6


func _fan(dt: float) -> void:
	"""THE GUST SNIPER: a fan of shots at the paddle, wider under half health."""
	fan_t -= dt
	if fan_t > 0.0:
		return
	var hurt: bool = hp * 2 < most
	fan_t = FAN_EVERY * (0.75 if hurt else 1.0)
	var from: Vector2 = p + Vector2(0, 24)
	var at := Vector2(float(run.get("paddle_x")), paddle_y)
	var n: int = 5 if hurt else 3
	for i in n:
		var turn: float = (i - (n - 1) / 2.0) * FAN_SPREAD
		shots.append({"p": from, "v": (at - from).normalized().rotated(deg_to_rad(turn)) * SHOT_SPEED})


func _wall(dt: float) -> void:
	"""THE STORM MAGE'S WIND WALL: up WALL_ON in every WALL_EVERY."""
	if wall_left > 0.0:
		wall_left -= dt
		return
	wall_t -= dt
	if wall_t <= 0.0:
		wall_t = WALL_EVERY
		wall_left = WALL_ON


func wall_rect() -> Rect2:
	return Rect2(hall.position.x - 20.0, hall.end.y + 2.0, hall.size.x + 40.0, WALL_TALL)


func _field_box() -> Rect2:
	"""Where a vortex may wander: the open floor between the bricks and the
	paddle, the walls' width."""
	var top: float = float(run.call("field_bottom")) + 34.0
	var foot: float = paddle_y - 110.0
	if foot - top < 60.0:
		top = foot - 60.0
	return Rect2(arena.position.x + 50.0, top, arena.size.x - 100.0, foot - top)


func _vortex(radius: float, forever: bool) -> Dictionary:
	var rng: RandomNumberGenerator = run.get("rng")
	var box: Rect2 = _field_box()
	var at := Vector2(rng.randf_range(box.position.x, box.end.x), rng.randf_range(box.position.y, box.end.y))
	run.call("burst_at", at, land, 18)
	return {"p": at, "v": Vector2.from_angle(rng.randf() * TAU) * VORTEX_SPEED, "life": WHIRL_LIFE,
		"r": radius, "forever": forever}


func _step_winds(dt: float, playing: bool) -> void:
	for g in gales:
		g["age"] += dt
	gales = gales.filter(func(g: Dictionary) -> bool: return float(g["age"]) < GALE_SHOWN)
	if not playing:
		return
	var box: Rect2 = _field_box()
	for v in vortices:
		v["p"] += v["v"] * dt
		if v["p"].x < box.position.x or v["p"].x > box.end.x:
			v["v"].x = -v["v"].x
		if v["p"].y < box.position.y or v["p"].y > box.end.y:
			v["v"].y = -v["v"].y
		v["p"] = Vector2(clampf(v["p"].x, box.position.x, box.end.x), clampf(v["p"].y, box.position.y, box.end.y))
		if not bool(v["forever"]):
			v["life"] -= dt
	vortices = vortices.filter(func(v: Dictionary) -> bool: return bool(v["forever"]) or float(v["life"]) > 0.0)


func work_balls(balls: Array, dt: float) -> void:
	"""What the winds do to the balls: a vortex catches one it touches and
	spins it SPIN_SECONDS, then throws it out any way (the run's fling()); the
	Storm Mage's wall blows a rising ball back down."""
	for b in balls:
		if b.has("spin"):
			var on: Dictionary = b["spin_on"]
			b["spin"] = float(b["spin"]) - dt
			b["spin_a"] = float(b["spin_a"]) + dt * 14.0
			b["p"] = (on["p"] as Vector2) + Vector2.from_angle(float(b["spin_a"])) * float(on["r"]) * 0.45
			b["v"] = Vector2.ZERO
			if float(b["spin"]) <= 0.0 or hp <= 0:
				b.erase("spin")
				b.erase("spin_on")
				b["free_t"] = FREE_SECONDS
				run.call("fling", b, b["p"])
			continue
		b["free_t"] = maxf(0.0, float(b.get("free_t", 0.0)) - dt)
		if float(b["free_t"]) <= 0.0 and hp > 0:
			for v in vortices:
				if (b["p"] as Vector2).distance_to(v["p"]) < float(v["r"]):
					b["spin"] = SPIN_SECONDS
					b["spin_on"] = v
					b["spin_a"] = ((b["p"] as Vector2) - (v["p"] as Vector2)).angle()
					b["v"] = Vector2.ZERO
					run.call("burst_at", b["p"], land, 10)
					break
		if rope_left > 0.0 and hp > 0:
			# THE HARPOONER'S ROPE: a wall while it hangs
			var q: Vector2 = Geometry2D.get_closest_point_to_segment(b["p"], harpoon_from, harpoon_to)
			var off: Vector2 = (b["p"] as Vector2) - q
			if off.length() < 8.0:
				var n: Vector2 = off.normalized() if off.length() > 0.01 else (harpoon_to - harpoon_from).orthogonal().normalized()
				if (b["v"] as Vector2).dot(n) < 0.0:
					b["v"] = (b["v"] as Vector2).bounce(n)
					run.call("burst_at", b["p"], land, 4)
		var band: Rect2 = wave_band()
		if band.size != Vector2.ZERO and hp > 0 and band.has_point(b["p"]) and int(b.get("wave_n", -1)) != int(wave["n"]):
			# THE TIDAL WAVE carries the ball its way
			b["wave_n"] = int(wave["n"])
			var v: Vector2 = b["v"]
			b["v"] = Vector2(float(wave["way"]), 0.44 * (1.0 if v.y >= 0.0 else -1.0)).normalized() * maxf(v.length(), 1.0)
			run.call("burst_at", b["p"], land, 6)
		if wall_left > 0.0 and hp > 0 and (b["v"] as Vector2).y < 0.0 and wall_rect().has_point(b["p"]):
			var rng: RandomNumberGenerator = run.get("rng")
			b["v"] = Vector2((b["v"] as Vector2).x + rng.randf_range(-60.0, 60.0), absf((b["v"] as Vector2).y))
			run.call("burst_at", b["p"], land, 6)


# ---------------------------------------------------------------- the split --

func _split() -> void:
	"""THE SLIME KING SPLITS: a small slime hops out of him onto the bricks."""
	if minions.size() >= MINIONS_MOST:
		return
	var m := {"p": p, "from": p, "to": _hop_target(p), "t": 0.0, "rest": 0.0, "sprite": null}
	if minion_id != "":
		var art: AnimatedSprite2D = sprite_of(minion_id, float(SCALE["minion"]))
		if art != null:
			run.add_child(art)
			art.position = p
			m["sprite"] = art
	minions.append(m)
	run.call("burst_at", p, land, 16)


func _hop_target(from: Vector2) -> Vector2:
	"""Where a small slime hops next: somewhere on the brick field below the
	hall, a few cells off - downward more often than not."""
	var rng: RandomNumberGenerator = run.get("rng")
	var area := Rect2(arena.position.x + 20.0, hall.end.y + 30.0, arena.size.x - 40.0,
		maxf(60.0, float(run.call("field_bottom")) - hall.end.y - 30.0))
	var to: Vector2 = from + Vector2(rng.randf_range(-170.0, 170.0), rng.randf_range(-40.0, 110.0))
	return Vector2(clampf(to.x, area.position.x, area.end.x), clampf(to.y, area.position.y, area.end.y))


func _step_minions(dt: float, playing: bool) -> void:
	var rng: RandomNumberGenerator = run.get("rng")
	for m in minions:
		if not playing:
			break
		if m["rest"] > 0.0:
			m["rest"] -= dt
			if m["rest"] <= 0.0:
				m["from"] = m["p"]
				m["to"] = _hop_target(m["p"])
				m["t"] = 0.0
			continue
		m["t"] = minf(1.0, m["t"] + dt / HOP_SECONDS)
		var u: float = m["t"]
		m["p"] = (m["from"] as Vector2).lerp(m["to"], u)
		if u >= 1.0:
			m["rest"] = rng.randf_range(0.5, 1.3)
			if land == "water":
				# THE TIDE KING'S YOUNG turn to water where they land on nothing
				if rng.randf() < PLANT_CHANCE and bool(run.call("plant_water", m["p"])):
					m["gone"] = true
			elif rng.randf() < PLANT_CHANCE:
				run.call("plant_blight", m["p"])
	for m in minions:
		if m.get("gone", false):
			_free_minion(m)
	minions = minions.filter(func(m: Dictionary) -> bool: return not m.get("gone", false))
	for m in minions:
		var art: AnimatedSprite2D = m["sprite"]
		if art != null and is_instance_valid(art):
			art.position = m["p"] + Vector2(0, -sin(PI * float(m["t"])) * HOP_HEIGHT * (1.0 if m["rest"] <= 0.0 else 0.0) - 6.0)


func ball_touch(at: Vector2, reach: float) -> int:
	"""A ball (or a laser) at `at`: every small slime it touches is killed.
	How many."""
	var killed: int = 0
	var kept: Array = []
	for m in minions:
		if (m["p"] as Vector2).distance_to(at) <= MINION_R + reach:
			killed += 1
			run.call("burst_at", m["p"], land, 18)
			_free_minion(m)
		else:
			kept.append(m)
	minions = kept
	return killed


func _free_minion(m: Dictionary) -> void:
	var art: AnimatedSprite2D = m.get("sprite")
	if art != null and is_instance_valid(art):
		art.queue_free()
	m["sprite"] = null


# ---------------------------------------------------------------- drawing --

func draw(c: CanvasItem, colour: Color, ink: Color) -> void:
	"""Its shots, a body for a build with no art, its minions' shadows, and
	its health over the hall."""
	if hp > 0 and (sprite == null or not is_instance_valid(sprite)):
		c.draw_circle(p, 26.0, colour.darkened(0.2).lerp(Color.WHITE, flash * 0.6))
		c.draw_circle(p + Vector2(-8, -4), 4.0, Color(0.1, 0.1, 0.1))
		c.draw_circle(p + Vector2(8, -4), 4.0, Color(0.1, 0.1, 0.1))
	for m in minions:
		var at: Vector2 = m["p"]
		c.draw_set_transform(at + Vector2(0, 8), 0.0, Vector2(1.0, 0.4))
		c.draw_circle(Vector2.ZERO, 11.0, Color(0, 0, 0, 0.35))
		c.draw_set_transform(Vector2.ZERO)
		var art: AnimatedSprite2D = m["sprite"]
		if art == null or not is_instance_valid(art):
			var up: float = sin(PI * float(m["t"])) * HOP_HEIGHT * (1.0 if m["rest"] <= 0.0 else 0.0)
			c.draw_circle(at - Vector2(0, up), MINION_R, colour)
	for s in shots:
		c.draw_circle(s["p"], 12.0, Color(colour, 0.25))
		c.draw_circle(s["p"], 6.0, colour)
		c.draw_circle(s["p"], 3.0, Color(1, 1, 1))
	if hp > 0 and aim_left > 0.0:
		# the Sniper's mark: a dashed line down the column, quickening
		var a: float = 0.35 + 0.5 * absf(sin((AIM_SECONDS - aim_left) * 14.0))
		var y: float = hall.end.y
		while y < paddle_y + 10.0:
			c.draw_line(Vector2(beam_x, y), Vector2(beam_x, minf(y + 10.0, paddle_y + 10.0)), Color(1.0, 0.3, 0.25, a), 2.0)
			y += 18.0
	if beam_left > 0.0:
		var top := Vector2(beam_x, hall.end.y)
		var foot := Vector2(beam_x, paddle_y + 14.0)
		c.draw_line(top, foot, Color(colour, 0.35), BEAM_HALF * 2.0)
		c.draw_line(top, foot, Color(1, 1, 1, 0.9), 4.0)
	var now: float = float(run.get("t"))
	for g in gales:
		var u: float = float(g["age"]) / GALE_SHOWN
		c.draw_arc(g["p"], GALE_REACH * u, 0, TAU, 48, Color(colour.lightened(0.3), 0.6 * (1.0 - u)), 4.0 * (1.0 - u) + 1.0)
	for v in vortices:
		var r: float = v["r"]
		var fade: float = 1.0 if bool(v["forever"]) else clampf(float(v["life"]) / 0.6, 0.0, 1.0)
		c.draw_circle(v["p"], r + 6.0, Color(colour, 0.06 * fade))
		c.draw_circle(v["p"], r, Color(colour.darkened(0.6), 0.35 * fade))
		for i in 4:
			var a0: float = now * (7.0 - i) + i * 1.6
			c.draw_arc(v["p"], r * (0.3 + 0.2 * i), a0, a0 + 3.6, 18, Color(colour.lightened(0.45), (0.95 - i * 0.12) * fade), 3.5)
		for i in 5:
			var a: float = now * 5.0 + i * TAU / 5.0
			c.draw_circle((v["p"] as Vector2) + Vector2.from_angle(a) * r * 0.85, 2.2, Color(1, 1, 1, 0.7 * fade))
	if wall_left > 0.0 and hp > 0:
		var w: Rect2 = wall_rect()
		c.draw_rect(w, Color(colour, 0.18))
		for x in range(int(w.position.x) + 14, int(w.end.x), 34):
			var y: float = w.position.y + fposmod(now * 60.0 + x, w.size.y)
			c.draw_polyline(PackedVector2Array([Vector2(x - 6, y - 4), Vector2(x, y + 3), Vector2(x + 6, y - 4)]),
				Color(colour.lightened(0.4), 0.8), 2.0)
	for sp in splashes:
		var u: float = float(sp["age"]) / GALE_SHOWN
		c.draw_arc(sp["p"], SPLASH_REACH * u, 0, TAU, 48, Color(colour.lightened(0.4), 0.7 * (1.0 - u)), 5.0 * (1.0 - u) + 1.0)
	if hp > 0 and dive_left > 0.0:
		# under the water: ripples where it swims
		for i in 3:
			var r: float = fmod(now * 40.0 + i * 14.0, 42.0)
			c.draw_arc(p, r, 0, TAU, 24, Color(colour.lightened(0.4), 0.6 * (1.0 - r / 42.0)), 2.0)
	if hp > 0 and harpoon_aim > 0.0:
		# the Harpooner's mark: a dashed line to where the paddle was
		var a: float = 0.35 + 0.5 * absf(sin((AIM_SECONDS - harpoon_aim) * 14.0))
		var d: Vector2 = (harpoon_to - harpoon_from)
		var steps: int = int(d.length() / 18.0)
		for i in steps:
			var u0: float = float(i) / steps
			c.draw_line(harpoon_from + d * u0, harpoon_from + d * minf(1.0, u0 + 10.0 / d.length()), Color(1.0, 0.55, 0.3, a), 2.0)
	if hp > 0 and (harpoon_u >= 0.0 or rope_left > 0.0):
		var head: Vector2 = harpoon_from.lerp(harpoon_to, clampf(harpoon_u, 0.0, 1.0)) if harpoon_u >= 0.0 else harpoon_to
		var fade: float = 1.0 if harpoon_u >= 0.0 else clampf(rope_left / 0.3, 0.0, 1.0)
		c.draw_line(harpoon_from, head, Color(0.75, 0.6, 0.4, 0.9 * fade), 3.0)
		c.draw_line(harpoon_from, head, Color(1.0, 0.9, 0.7, 0.5 * fade), 1.0)
		var dir2: Vector2 = (harpoon_to - harpoon_from).normalized()
		var side: Vector2 = dir2.orthogonal()
		c.draw_colored_polygon(PackedVector2Array([head + dir2 * 10.0, head + side * 6.0 - dir2 * 4.0, head - side * 6.0 - dir2 * 4.0]),
			Color(0.85, 0.88, 0.95, fade))
	if hp > 0 and kind == "tidemage" and bubble_hits > 0:
		c.draw_circle(p, BUBBLE_R, Color(colour, 0.12))
		c.draw_arc(p, BUBBLE_R, 0, TAU, 40, Color(0.85, 0.95, 1.0, 0.75), 2.0)
		c.draw_arc(p, BUBBLE_R - 6.0, PI * 1.1, PI * 1.45, 10, Color(1, 1, 1, 0.8), 3.0)
		for i in BUBBLE_HITS - bubble_hits:
			var a0: float = 0.7 + i * 2.1
			c.draw_polyline(PackedVector2Array([p + Vector2.from_angle(a0) * BUBBLE_R, p + Vector2.from_angle(a0 + 0.15) * BUBBLE_R * 0.7,
				p + Vector2.from_angle(a0 - 0.1) * BUBBLE_R * 0.5]), Color(1, 1, 1, 0.8), 1.5)
	if wave != null and hp > 0:
		if float(wave["warn"]) > 0.0:
			var edge: float = float(wave["x"]) + float(wave["way"]) * 20.0
			var blink: float = 0.4 + 0.6 * absf(sin(now * 12.0))
			for i in 4:
				var y: float = hall.end.y + 60.0 + i * 70.0
				c.draw_polyline(PackedVector2Array([Vector2(edge - float(wave["way"]) * 8.0, y - 12.0), Vector2(edge + float(wave["way"]) * 8.0, y),
					Vector2(edge - float(wave["way"]) * 8.0, y + 12.0)]), Color(colour.lightened(0.4), blink), 3.0)
		else:
			var band: Rect2 = wave_band()
			c.draw_rect(band, Color(colour, 0.32))
			c.draw_rect(Rect2(band.position.x + (band.size.x * 0.5 if float(wave["way"]) < 0.0 else 0.0), band.position.y,
				band.size.x * 0.5, band.size.y), Color(colour.lightened(0.3), 0.25))
			var front: float = band.end.x if float(wave["way"]) > 0.0 else band.position.x
			var y2: float = band.position.y
			while y2 < band.end.y:
				c.draw_line(Vector2(front, y2), Vector2(front - float(wave["way"]) * 8.0, y2 + 6.0), Color(0.9, 0.97, 1.0, 0.85), 2.0)
				y2 += 12.0
			c.draw_arc(Vector2(front - float(wave["way"]) * 12.0, band.position.y + 10.0), 14.0,
				PI if float(wave["way"]) > 0.0 else 0.0, PI * 2.0 if float(wave["way"]) > 0.0 else PI, 10, Color(1, 1, 1, 0.85), 3.0)
	for i in wards.size():
		if float(wards[i]["back"]) <= 0.0 and hp > 0:
			var w: Vector2 = ward_at(i)
			c.draw_circle(w, WARD_R + 4.0, Color(colour, 0.2))
			c.draw_circle(w, WARD_R, colour.darkened(0.3))
			c.draw_arc(w, WARD_R, 0, TAU, 16, Color(1, 1, 1, 0.8), 1.5)


static func sprite_of(id: String, scale: float) -> AnimatedSprite2D:
	"""A MONSTER FROM ITS OWN ART: its scene's frames, `scale` times, recoloured
	by the same gates as EnemyPortraits._picture_of(). Null when this build has
	no art for it (a clone without art/pack) - the boss is drawn in code then."""
	var path: String = EnemyPortraits.scene_path(id)
	var packed: PackedScene = load(path) as PackedScene if ResourceLoader.exists(path) else null
	if packed == null:
		return null
	var node: Node = packed.instantiate()
	var found: AnimatedSprite2D = node as AnimatedSprite2D
	if found == null:
		for child in node.find_children("*", "AnimatedSprite2D", true, false):
			found = child
			break
	var out: AnimatedSprite2D = null
	if found != null and found.sprite_frames != null:
		var frames: SpriteFrames = found.sprite_frames
		var pose: String = ""
		for wanted in ["walkdown", "idledown"]:
			if frames.has_animation(wanted) and frames.get_frame_count(wanted) > 0:
				pose = wanted
				break
		if pose != "":
			out = AnimatedSprite2D.new()
			out.name = "boss_" + id
			out.sprite_frames = frames
			out.animation = pose
			out.scale = Vector2(scale, scale)
			out.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			var data: EnemyData = EnemyPortraits.data_for(id)
			var element: int = int(data.element) if data != null else Element.Type.NONE
			var override: Variant = node.get("element_override")
			if override is int and int(override) >= 0:
				element = int(override)
			var recolour: bool = (data != null and data.recolour_to_element) or (override is int and int(override) >= 0)
			if recolour and element != Element.Type.NONE:
				out.material = BaseEnemy.element_material(data, element)
			if data != null:
				out.modulate = data.body_tint
			out.play(pose)
	node.free()
	return out
