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
# Every one walks its hall (the map's R cells), takes the ball's and the
# lasers' hits, and - but the Sniper - throws at the paddle (a hit stuns it).
# It is down at no health: the run says so, and its walls crumble.
#
# Data and rules only, plus its own drawing (draw(), called inside the run's
# _draw()). The pictures - its own and its minions' - are AnimatedSprite2D
# children of the run. No class_name; the run preloads it.
extends RefCounted

const KINDS := ["slimeking", "sprite", "sniper", "mage", "ruler"]
# TOUGH (the owner: "bosses die too fast we really need to buff up bosses",
# and "hitting with a ball does a bit more damage"): a ball's hit is the run's
# BALL_HIT (3), a laser's 1, and a fight is about twice the ball hits it was.
const HP := {"slimeking": 180, "sprite": 160, "sniper": 190, "mage": 200, "ruler": 300}
# How big each is drawn (their frames differ: a slime 48 px, a mage 150).
const SCALE := {"slimeking": 3.0, "sprite": 1.7, "sniper": 2.3, "mage": 1.3, "ruler": 2.2, "minion": 1.25}
const BODY := {"slimeking": Vector2(66, 46), "sprite": Vector2(40, 40), "sniper": Vector2(44, 52),
	"mage": Vector2(56, 64), "ruler": Vector2(70, 70)}
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
	if kind == "mage":
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
	_step_shots(dt)
	_step_minions(dt, playing)


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
	var splits: bool = kind == "slimeking" or (kind == "ruler" and hp * 3 < most * 2)
	if splits and hp > 0:
		var every: int = SPLIT_EVERY if kind == "slimeking" else RULER_SPLIT_EVERY
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
		return true
	return false


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
			if rng.randf() < PLANT_CHANCE:
				run.call("plant_blight", m["p"])
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
