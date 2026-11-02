# magestand.gd - THE MAGE'S STAND (0.107.0, step 2 of the commit folder's
# MAGES_STAND_PLAN.txt; the owner's alone while it is built).
#
# The owner: "mage would use mythic weapon stand on a wall and protect the
# portal from enemies going in", "we can use the door as the gate enemies
# break it then run through to the portal enemies should flood in in waves
# progressivly getting harder", "make field of view longer for this one so
# players can see further out", "there will be no limit on meteors the goal
# will be to spam them because hordes will come strong and move fast", "the
# door need to be slightly transparent so we can see enemies behind it".
#
# THE PLACE (fixed, VIEW across - half as far again each way as the Healer's
# Run): outside, most of it, where the waves come from; the wall low across
# it (the crypt's brick face, its cap stones on top for her to walk, the
# crypt door as the gate between two pillars, drawn see-through - DOOR_SEE);
# inside, a strip at the bottom, the portal. Monsters and the wall share one
# y-sorted layer (`world`), so a monster at the gate is drawn behind it.
#
# HER: the mage with the Meteorite, walking the wall's top (`steer`, the move
# keys) and raining meteors where you aim (`aim` and `casting`, set by the
# screen from the mouse) - no count, the cast gap the only limit. A meteor
# falls FALL_SECONDS with its shadow and ring, blasts BLAST_REACH (one in
# five critical), and leaves a crater burning BURN_SECONDS.
#
# THE GATE AND THE PORTAL: monsters queue at the gate and hit it (at most
# GATE_HITTERS at once); at nought it breaks and they run through to the
# portal, each draining it (`portal`). Nought there: the run is over. After a
# wave the gate is mended DOOR_MEND of its most - a broken one put back.
#
# WAVES: more, faster and tougher each time (wave_count(), wave_speed(),
# wave_health()), the land changing every LAND_WAVES; no last one - the score
# is the waves held.
#
# Step 3 brings elites, keepers, shooters and lives, and upgrades; step 4 the
# leaderboards and the gate's levels; step 5 the party.
#
# No class_name: preloaded by magestandscreen.gd and the suite.
extends Node2D

signal finished

enum State { READY, WAVE, BETWEEN, LOST }

const RunScript := preload("res://src/world/healerrun/healerrun.gd")

const VIEW := Vector2(960.0, 540.0)
const HALF := Vector2(480.0, 270.0)
const PATH_HALF := 330.0
# THE WALL: its foot, the gate's gap either side of the middle, and where she
# stands (her picture's middle) on its caps.
const FOOT := 178.0
const GATE_HALF := 39.0
const WALK_Y := FOOT - 54.0
const WALK_SPEED := 130.0
# As far either way as she walks: the wall's ends, short of the side walls.
const WALK_HALF := PATH_HALF - 24.0
const WALL_PIECES := {101: "res://scene/crypt/wallrun4.tscn", 51: "res://scene/crypt/wallrun2.tscn",
	26: "res://scene/crypt/wallrun1.tscn", 17: "res://scene/crypt/pillar.tscn"}
const WALLS_ART := "res://art/floordecoration/floorwalls.png"
const CAP_REGION := Rect2(326, 118, 9, 58)
const DOOR_ART := "res://art/floordecoration/cryptdoor.png"
# The door, see-through enough to show what is behind it.
const DOOR_SEE := 0.62
const PORTAL_AT := Vector2(0.0, 232.0)
const PORTAL_REACH := 20.0
const PORTAL_MOST := 100
const PORTAL_FRAMES := "res://art/teleport/teleportframes.tres"
const MAGE_SCENE := "res://scene/characters/mage.tscn"
const METEOR_TEXTURE := "res://art/maincharacter/meteor.png"
const FLOOR_SET := "res://scene/world/underground.tres"
const TILE := 16
# THE METEORS: no count - the gap between casts is the limit.
const CAST_GAP := 0.33
const FALL_SECONDS := 0.45
const SKY := Vector2(70.0, -150.0)
const BLAST_REACH := 36.0
const BLAST_DAMAGE := 10.0
const CRIT_CHANCE := 0.2
const CRIT_MULT := 2.0
const BURN_SECONDS := 2.5
const BURN_REACH := 30.0
const BURN_DPS := 4.0
const FIRE := Color(1.0, 0.55, 0.15)
# THE GATE.
const DOOR_MOST := 400.0
const DOOR_HIT := 4.0
const GATE_HITTERS := 10
const DOOR_MEND := 0.25
# THE WAVES.
const READY_SECONDS := 1.5
const BETWEEN_SECONDS := 3.0
const WAVE_FIRST := 24
const WAVE_MORE := 10
const GROUP_FIRST := 8
const GROUP_GAP := 1.2
const LAND_WAVES := 3
const MONSTERS_MOST := 400
const BANNER_SECONDS := 2.2
const KINDS := {"sprite": {"health": 6.0, "speed": 48.0, "radius": 8.0, "drain": 1},
	"slime": {"health": 14.0, "speed": 32.0, "radius": 9.0, "drain": 2}}
const MONSTER_Z := 0
const HER_Z := 6
# The ground's marks under the monsters, over the floor.
const MARKS_Z := -1
const SKY_Z := 30


class Monster extends Node2D:
	var kind: String = ""
	var health: float = 1.0
	var most: float = 1.0
	var speed: float = 30.0
	var radius: float = 8.0
	var drain: int = 1
	# Where at the gate it heads for: along it, and how far back it queues.
	var stop_x: float = 0.0
	var stop_y: float = 0.0
	var at_gate: bool = false
	# Past the gate, running for the portal.
	var through: bool = false
	var flash: float = 0.0
	var dying: float = -1.0
	var sprite: AnimatedSprite2D = null


# The ground's marks and the sky's trails, drawn from the run's lists each
# frame: one node each, not one a meteor.
class Marks extends Node2D:
	var run: Node2D = null
	var sky: bool = false

	func _draw() -> void:
		if run == null:
			return
		if sky:
			for fall in run.get("falling"):
				var done: float = 1.0 - clampf(float(fall["left"]) / FALL_SECONDS, 0.0, 1.0)
				var at: Vector2 = fall["at"]
				var stone: Vector2 = (at + SKY).lerp(at, done * done)
				for k in 8:
					var t: float = float(k) / 8.0
					draw_circle(stone + (SKY.normalized() * 10.0 * k), 7.0 - k * 0.7,
						Color(1.0, 0.45 + t * 0.3, 0.1, (0.75 - t * 0.7)))
			if bool(run.get("showing_aim")):
				var aim: Vector2 = run.get("aim")
				draw_arc(aim, 22.0, 0.0, TAU, 32, Color(1.0, 0.85, 0.5, 0.9), 1.0)
				draw_line(aim + Vector2(-6, 0), aim + Vector2(6, 0), Color(1.0, 0.85, 0.5, 0.9), 1.0)
				draw_line(aim + Vector2(0, -6), aim + Vector2(0, 6), Color(1.0, 0.85, 0.5, 0.9), 1.0)
			return
		for crater in run.get("craters"):
			var at: Vector2 = crater["at"]
			var fade: float = clampf(float(crater["left"]) / BURN_SECONDS, 0.0, 1.0)
			draw_set_transform(at, 0.0, Vector2(1.0, 0.55))
			draw_circle(Vector2.ZERO, BURN_REACH, Color(1.0, 0.35, 0.05, 0.25 * fade))
			draw_circle(Vector2.ZERO, BURN_REACH * 0.6, Color(1.0, 0.55, 0.15, 0.4 * fade))
			draw_circle(Vector2.ZERO, 9.0, Color(0.2, 0.12, 0.1, 0.9 * fade))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			var flick: float = float(crater["seed"]) + float(crater["left"]) * 9.0
			for k in 7:
				var p := at + Vector2(sin(flick * 1.3 + k * 2.1) * 20.0, cos(k * 1.7) * 6.0)
				var tall: float = (6.0 + 5.0 * absf(sin(flick + k))) * fade
				draw_colored_polygon(PackedVector2Array([p + Vector2(-3, 0), p + Vector2(3, 0), p + Vector2(0, -tall)]),
					Color(1.0, 0.6 + 0.3 * absf(sin(k + flick)), 0.15, 0.85 * fade))
		for fall in run.get("falling"):
			var done: float = 1.0 - clampf(float(fall["left"]) / FALL_SECONDS, 0.0, 1.0)
			var at: Vector2 = fall["at"]
			draw_set_transform(at, 0.0, Vector2(1.0, 0.5))
			draw_circle(Vector2.ZERO, 8.0 + 14.0 * done, Color(0.0, 0.0, 0.0, 0.2 + 0.25 * done))
			draw_arc(Vector2.ZERO, BLAST_REACH, 0.0, TAU, 40, Color(FIRE, 0.4 + 0.4 * done), 2.0)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


var steer: Callable = Callable(self, "_read_steer")
# Set by the screen each frame: where the mouse points, in the run's own
# space, and whether the button is held.
var aim: Vector2 = Vector2(0.0, -100.0)
var casting: bool = false
var showing_aim: bool = true
var seed_value: int = 0

var state: int = State.READY
var wave: int = 0
var waves_held: int = 0
var slain: int = 0
var run_seconds: float = 0.0
var door: float = DOOR_MOST
var door_most: float = DOOR_MOST
var portal: int = PORTAL_MOST
var banner: String = ""
var banner_left: float = 0.0
var god: bool = false
var god_used: bool = false
var falling: Array = []
var craters: Array = []
var casts: int = 0
var crits: int = 0

var world: Node2D = null
var floor_layer: TileMapLayer = null
var monsters: Node2D = null
var mage: AnimatedSprite2D = null
var door_planks: Sprite2D = null
var door_parts: Array = []
var portal_sprite: AnimatedSprite2D = null
var ground_marks: Marks = null
var sky_marks: Marks = null

var _rng := RandomNumberGenerator.new()
var _fx_rng := RandomNumberGenerator.new()
var _left: float = READY_SECONDS
var _to_spawn: int = 0
var _group_in: float = 0.0
var _cast_in: float = 0.0
var _rocks: Dictionary = {}


func _ready() -> void:
	if seed_value != 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()
	_fx_rng.randomize()
	_build()


func _build() -> void:
	var dark := ColorRect.new()
	dark.color = Color(0.03, 0.03, 0.05)
	dark.position = -HALF - Vector2(40, 40)
	dark.size = VIEW + Vector2(80, 80)
	dark.z_index = -100
	add_child(dark)
	var ambience := CanvasModulate.new()
	ambience.color = Color(0.62, 0.62, 0.74)
	add_child(ambience)
	floor_layer = TileMapLayer.new()
	floor_layer.name = "floor"
	floor_layer.tile_set = load(FLOOR_SET) as TileSet
	floor_layer.collision_enabled = false
	floor_layer.navigation_enabled = false
	floor_layer.z_index = -10
	for y in range(floori(-HALF.y / TILE) - 1, ceili(HALF.y / TILE) + 1):
		for x in range(floori(-PATH_HALF / TILE), ceili(PATH_HALF / TILE)):
			floor_layer.set_cell(Vector2i(x, y), 1, Vector2i(_fx_rng.randi_range(1, 4), _fx_rng.randi_range(1, 3)))
	add_child(floor_layer)
	# Monsters, the wall and the gate share one layer sorted by y: whatever
	# is further down is drawn over what is behind it.
	world = Node2D.new()
	world.name = "world"
	world.y_sort_enabled = true
	add_child(world)
	monsters = Node2D.new()
	monsters.name = "monsters"
	monsters.y_sort_enabled = true
	world.add_child(monsters)
	_lay_walls()
	_lay_gate()
	_lay_portal()
	_make_mage()
	ground_marks = Marks.new()
	ground_marks.name = "ground"
	ground_marks.run = self
	ground_marks.z_index = MARKS_Z
	add_child(ground_marks)
	sky_marks = Marks.new()
	sky_marks.name = "sky"
	sky_marks.run = self
	sky_marks.sky = true
	sky_marks.z_index = SKY_Z
	add_child(sky_marks)
	# Beyond the side walls, dark over everything.
	for x in [-HALF.x - 40.0, PATH_HALF + 9.0]:
		var beyond := ColorRect.new()
		beyond.color = Color.BLACK
		beyond.position = Vector2(x, -HALF.y - 40.0)
		beyond.size = Vector2(HALF.x + 40.0 - PATH_HALF - 9.0, VIEW.y + 80.0)
		beyond.z_index = 50
		add_child(beyond)


func _lay_walls() -> void:
	# The side walls, as the Healer's Run's, over everything.
	var y: float = -HALF.y
	while y < HALF.y + RunScript.WALL_STEP:
		for x in [-PATH_HALF - 4.5, PATH_HALF + 4.5]:
			var side := _piece(RunScript.WALL_PIECE, Vector2(x, y), self)
			if side != null:
				side.z_index = RunScript.WALL_Z
		y += RunScript.WALL_STEP
	# The wall across: its face either side of the gate, laid end to end from
	# the gate out (the owner: "there is a gap on the right side of the
	# wall" - laid left to right, the right end stopped 13 px short), the last
	# piece running on under the side wall, where it is not seen.
	for side in [-1.0, 1.0]:
		var x0: float = GATE_HALF
		while x0 < PATH_HALF + 4.5:
			var room: float = PATH_HALF + 4.5 - x0
			var w: int = 101 if room >= 101.0 else (51 if room >= 51.0 else 26)
			_piece(str(WALL_PIECES[w]), Vector2(side * (x0 + w / 2.0), FOOT), world)
			x0 += w
	# Its top, where she walks: the crypt's caps (the side walls' column,
	# turned to run along it), two rows, stopping at the gatehouse. Not in
	# the sorted layer: she is drawn over them (HER_Z), monsters never reach.
	var caps := AtlasTexture.new()
	caps.atlas = load(WALLS_ART) as Texture2D
	caps.region = CAP_REGION
	for row in 2:
		for side in [-1.0, 1.0]:
			# From the gatehouse's pillar out, under the side wall at the end.
			var from_gate: float = GATE_HALF + 18.0
			while from_gate < PATH_HALF + 4.5:
				var cap := Sprite2D.new()
				cap.texture = caps
				cap.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				cap.rotation = PI / 2.0
				cap.position = Vector2(side * (from_gate + CAP_REGION.size.y / 2.0), FOOT - 32.5 - row * 9.0)
				cap.z_index = 1
				add_child(cap)
				from_gate += CAP_REGION.size.y
	for side in [-1.0, 1.0]:
		_piece("res://scene/crypt/pillar.tscn", Vector2(side * 48.0, FOOT + 2.0), world)
	# Outside: rubble and bones; inside: candles.
	for at in [Vector2(-260, -200), Vector2(250, -180), Vector2(-90, -120), Vector2(140, -40), Vector2(-280, 40)]:
		_piece("res://scene/crypt/rubble4.tscn", at, self).z_index = -5
	_piece("res://scene/crypt/skullpile.tscn", Vector2(290, -60), self).z_index = -5
	for at in [Vector2(-160, 236), Vector2(160, 236)]:
		_piece("res://scene/crypt/candelabra.tscn", at, world)


func _lay_gate() -> void:
	"""The crypt door as the gate, from its own art (the door scene's three
	pieces, without its script), see-through."""
	var art: Texture2D = load(DOOR_ART) as Texture2D
	var gate := Node2D.new()
	gate.name = "gate"
	gate.position = Vector2(0.0, FOOT)
	world.add_child(gate)
	for part in [[Rect2(14, 19, 9, 28), -30.0], [Rect2(23, 19, 21, 28), 0.0], [Rect2(44, 19, 9, 28), 30.0]]:
		var tex := AtlasTexture.new()
		tex.atlas = art
		tex.region = part[0]
		var piece := Sprite2D.new()
		piece.texture = tex
		piece.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		piece.scale = Vector2(2, 2)
		piece.position = Vector2(float(part[1]), -28.0)
		piece.modulate.a = DOOR_SEE
		gate.add_child(piece)
		door_parts.append(piece)
	door_planks = door_parts[1]


func _lay_portal() -> void:
	var glow := Node2D.new()
	glow.name = "portalglow"
	glow.position = PORTAL_AT
	glow.z_index = -1
	glow.draw.connect(_draw_portal_glow.bind(glow))
	add_child(glow)
	portal_sprite = AnimatedSprite2D.new()
	portal_sprite.name = "portal"
	portal_sprite.sprite_frames = load(PORTAL_FRAMES) as SpriteFrames
	if portal_sprite.sprite_frames != null:
		portal_sprite.play("default")
	portal_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portal_sprite.scale = Vector2(2.0, 2.0)
	portal_sprite.position = PORTAL_AT
	world.add_child(portal_sprite)


func _draw_portal_glow(glow: Node2D) -> void:
	var strength: float = clampf(float(portal) / PORTAL_MOST, 0.0, 1.0)
	for k in 6:
		glow.draw_circle(Vector2.ZERO, 42.0 - k * 6.0, Color(0.55, 0.35, 1.0, (0.05 + k * 0.025) * (0.3 + 0.7 * strength)))


func _make_mage() -> void:
	var look: Dictionary = RunScript.look_of_scene(MAGE_SCENE, false)
	mage = AnimatedSprite2D.new()
	mage.name = "mage"
	mage.sprite_frames = look.get("frames") as SpriteFrames
	mage.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mage.offset = look.get("offset", Vector2.ZERO)
	mage.position = Vector2(-150.0, WALK_Y)
	mage.z_index = HER_Z
	_play("idleup")
	var glow := (load("res://scene/characters/playerlight.tscn") as PackedScene).instantiate() as PointLight2D
	if glow != null:
		glow.enabled = true
		mage.add_child(glow)
	add_child(mage)


func _piece(path: String, at: Vector2, parent: Node) -> Node2D:
	if not ResourceLoader.exists(path):
		return null
	var p := (load(path) as PackedScene).instantiate() as Node2D
	p.position = at
	parent.add_child(p)
	return p


func _play(animation: String) -> void:
	if mage != null and mage.sprite_frames != null and mage.sprite_frames.has_animation(animation) \
			and mage.animation != animation:
		mage.play(animation)


# =============================================================================
# THE RUN, A FRAME AT A TIME
# =============================================================================

func _process(delta: float) -> void:
	step(delta)


func step(delta: float) -> void:
	"""One frame; the suite calls it with its own delta."""
	ground_marks.queue_redraw()
	sky_marks.queue_redraw()
	if state == State.LOST:
		return
	run_seconds += delta
	if god:
		god_used = true
	banner_left = maxf(0.0, banner_left - delta)
	if banner_left <= 0.0:
		banner = ""
	_walk(delta)
	_cast(delta)
	_falls(delta)
	_burn(delta)
	_move_monsters(delta)
	_waves(delta)
	var glow: Node2D = get_node_or_null("portalglow")
	if glow != null:
		glow.queue_redraw()


func _read_steer() -> float:
	var dir: float = 0.0
	if Input.is_action_pressed("move_right"):
		dir += 1.0
	if Input.is_action_pressed("move_left"):
		dir -= 1.0
	return dir


func _walk(delta: float) -> void:
	var dir: float = clampf(float(steer.call()), -1.0, 1.0)
	mage.position.x = clampf(mage.position.x + dir * WALK_SPEED * delta, -WALK_HALF, WALK_HALF)
	mage.position.y = WALK_Y
	if casting:
		_play("attackup")
	elif dir < 0.0:
		_play("walkleft")
	elif dir > 0.0:
		_play("walkright")
	else:
		_play("idleup")


# =============================================================================
# THE METEORS
# =============================================================================

func _cast(delta: float) -> void:
	_cast_in = maxf(0.0, _cast_in - delta)
	if casting and _cast_in <= 0.0 and (state == State.WAVE or state == State.BETWEEN):
		_cast_in = CAST_GAP
		drop_meteor(aim)


func drop_meteor(at: Vector2) -> void:
	"""A meteor called down at `at` (held to the field)."""
	var spot := Vector2(clampf(at.x, -PATH_HALF + 6.0, PATH_HALF - 6.0), clampf(at.y, -HALF.y + 6.0, HALF.y - 6.0))
	var rock := Sprite2D.new()
	rock.texture = load(METEOR_TEXTURE) as Texture2D
	rock.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rock.z_index = SKY_Z + 1
	rock.position = spot + SKY
	add_child(rock)
	casts += 1
	var crit: bool = _rng.randf() < CRIT_CHANCE
	if crit:
		crits += 1
		rock.modulate = Color(1.6, 0.8, 0.6)
	falling.append({"at": spot, "left": FALL_SECONDS, "rock": rock, "crit": crit})


func _falls(delta: float) -> void:
	var still: Array = []
	for fall in falling:
		fall["left"] = float(fall["left"]) - delta
		var rock: Sprite2D = fall["rock"]
		var done: float = 1.0 - clampf(float(fall["left"]) / FALL_SECONDS, 0.0, 1.0)
		if is_instance_valid(rock):
			rock.position = (fall["at"] + SKY).lerp(fall["at"], done * done)
			rock.rotation += delta * 6.0
		if float(fall["left"]) > 0.0:
			still.append(fall)
		else:
			_land(fall)
	falling = still


func _land(fall: Dictionary) -> void:
	var at: Vector2 = fall["at"]
	var rock: Sprite2D = fall["rock"]
	if is_instance_valid(rock):
		rock.queue_free()
	var damage: float = BLAST_DAMAGE * (CRIT_MULT if bool(fall["crit"]) else 1.0)
	for node in monsters.get_children():
		var m := node as Monster
		if m != null and m.dying < 0.0 and m.position.distance_to(at) <= BLAST_REACH + m.radius:
			hurt(m, damage)
	craters.append({"at": at, "left": BURN_SECONDS, "seed": _fx_rng.randf() * 100.0})
	var burst = RunScript.Burst.new()
	burst.position = at
	burst.colour = Color(1.0, 0.4, 0.2) if bool(fall["crit"]) else FIRE
	burst.reach = BLAST_REACH * (1.3 if bool(fall["crit"]) else 1.0)
	burst.sparks = 12
	burst.life = 0.35
	burst.most = 0.35
	burst.z_index = SKY_Z - 1
	add_child(burst)


func _burn(delta: float) -> void:
	var still: Array = []
	for crater in craters:
		crater["left"] = float(crater["left"]) - delta
		if float(crater["left"]) <= 0.0:
			continue
		still.append(crater)
		var at: Vector2 = crater["at"]
		for node in monsters.get_children():
			var m := node as Monster
			if m != null and m.dying < 0.0 and m.position.distance_to(at) <= BURN_REACH + m.radius:
				hurt(m, BURN_DPS * delta)
	craters = still


func hurt(m: Monster, damage: float) -> void:
	if m.dying >= 0.0:
		return
	m.health -= damage
	m.flash = 0.08
	if m.health <= 0.0:
		m.dying = 0.25
		slain += 1


# =============================================================================
# THE HORDE, THE GATE AND THE PORTAL
# =============================================================================

func wave_count(n: int) -> int:
	return WAVE_FIRST + WAVE_MORE * (maxi(1, n) - 1)


static func wave_speed(n: int) -> float:
	"""Faster each wave, to twice as fast."""
	return minf(2.0, 1.0 + 0.06 * (maxi(1, n) - 1))


static func wave_health(n: int) -> float:
	return 1.0 + 0.15 * (maxi(1, n) - 1)


static func wave_hit(n: int) -> float:
	return 1.0 + 0.1 * (maxi(1, n) - 1)


func land() -> int:
	return int(RunScript.LANDS[((maxi(1, wave) - 1) / LAND_WAVES) % RunScript.LANDS.size()])


func land_name() -> String:
	return Element.name_for(land()).capitalize()


func living() -> int:
	var count: int = 0
	for node in monsters.get_children():
		var m := node as Monster
		if m != null and m.dying < 0.0:
			count += 1
	return count


func spawn(kind: String, at: Vector2) -> Monster:
	var element: int = land()
	var scene_id: String = str(RunScript.SPRITES.get(element, "windsprite")) if kind == "sprite" \
		else str(RunScript.SLIMES.get(element, ""))
	if scene_id == "":
		scene_id = str(RunScript.SPRITES.get(element, "windsprite"))
	var info: Dictionary = KINDS[kind]
	var m := Monster.new()
	m.kind = kind
	m.most = float(info["health"]) * wave_health(wave)
	m.health = m.most
	m.speed = float(info["speed"]) * wave_speed(wave) * _rng.randf_range(0.85, 1.15)
	m.radius = float(info["radius"])
	m.drain = int(info["drain"])
	m.stop_x = _rng.randf_range(-GATE_HALF + 6.0, GATE_HALF - 6.0)
	m.stop_y = pow(_rng.randf(), 1.5) * 70.0
	m.position = at
	m.z_index = MONSTER_Z
	var look: Dictionary = RunScript.look_of_scene("res://scene/enemy/%s.tscn" % scene_id)
	m.sprite = AnimatedSprite2D.new()
	m.sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	m.sprite.sprite_frames = look.get("frames") as SpriteFrames
	m.sprite.material = look.get("material") as Material
	m.sprite.self_modulate = look.get("modulate", Color.WHITE)
	m.sprite.offset = look.get("offset", Vector2.ZERO)
	m.sprite.scale = look.get("scale", Vector2.ONE)
	m.add_child(m.sprite)
	var walk: String = str(look.get("walk", ""))
	if walk != "":
		m.sprite.play(walk)
	monsters.add_child(m)
	return m


func _move_monsters(delta: float) -> void:
	var hitters: int = 0
	for node in monsters.get_children():
		var m := node as Monster
		if m == null:
			continue
		if m.dying >= 0.0:
			m.dying -= delta
			m.modulate.a = clampf(m.dying / 0.25, 0.0, 1.0)
			if m.dying <= 0.0:
				_gone(m)
			continue
		m.flash = maxf(0.0, m.flash - delta)
		m.modulate = Color(2.2, 2.2, 2.2) if m.flash > 0.0 else Color.WHITE
		if not m.through and door <= 0.0 and m.position.y >= FOOT - 40.0 and absf(m.position.x) <= GATE_HALF:
			m.through = true
		if m.through:
			# THROUGH THE GATE: for the portal.
			var to_portal: Vector2 = PORTAL_AT - m.position
			if to_portal.length() <= PORTAL_REACH:
				_into_portal(m)
				continue
			m.position += to_portal.limit_length(m.speed * delta)
			continue
		var goal := Vector2(m.stop_x, FOOT - 26.0 - m.stop_y)
		if door <= 0.0:
			goal = Vector2(m.stop_x * 0.6, FOOT - 20.0)
		var to_goal: Vector2 = goal - m.position
		if to_goal.length() <= 1.5:
			m.position = goal
			m.at_gate = door > 0.0
		else:
			m.at_gate = false
			m.position += to_goal.limit_length(m.speed * delta)
		if m.at_gate:
			hitters += 1
	if door > 0.0 and hitters > 0 and not god:
		door = maxf(0.0, door - DOOR_HIT * wave_hit(wave) * mini(hitters, GATE_HITTERS) * delta)
		if door <= 0.0:
			_break_gate()


func _break_gate() -> void:
	"""Broken: its planks down in the gap, and they run for the portal."""
	door_planks.rotation = 1.45
	door_planks.position = Vector2(4.0, -6.0)
	door_planks.modulate = Color(0.55, 0.45, 0.4, DOOR_SEE)
	banner = "The gate is broken!"
	banner_left = BANNER_SECONDS


func _mend_gate() -> void:
	"""After a wave: mended DOOR_MEND of its most - a broken one put back."""
	door = minf(door_most, door + door_most * DOOR_MEND)
	door_planks.rotation = 0.0
	door_planks.position = Vector2(0.0, -28.0)
	door_planks.modulate = Color(1.0, 1.0, 1.0, DOOR_SEE)


func gate_broken() -> bool:
	return door <= 0.0


func _into_portal(m: Monster) -> void:
	if not god:
		portal = maxi(0, portal - m.drain)
	_gone(m)
	if portal <= 0 and state != State.LOST:
		state = State.LOST
		banner = "The portal fell"
		banner_left = BANNER_SECONDS * 3.0
		finished.emit()


static func _gone(node: Node) -> void:
	var parent: Node = node.get_parent()
	if parent != null:
		parent.remove_child(node)
	node.queue_free()


func _waves(delta: float) -> void:
	match state:
		State.READY, State.BETWEEN:
			_left -= delta
			if _left <= 0.0:
				_start_wave()
		State.WAVE:
			if _to_spawn > 0:
				_group_in -= delta
				if _group_in <= 0.0 and monsters.get_child_count() < MONSTERS_MOST:
					_group_in = GROUP_GAP
					_spawn_group()
			elif living() == 0:
				_end_wave()


func _start_wave() -> void:
	wave += 1
	_to_spawn = wave_count(wave)
	_group_in = 0.0
	state = State.WAVE
	banner = "Wave %d - the %s lands" % [wave, land_name()]
	banner_left = BANNER_SECONDS


func _spawn_group() -> void:
	"""One group of the wave flooding in from the top: bigger each wave."""
	var size: int = mini(_to_spawn, GROUP_FIRST + wave)
	var centre: float = _rng.randf_range(-PATH_HALF + 60.0, PATH_HALF - 60.0)
	for i in size:
		var kind: String = "sprite" if _rng.randf() < 0.5 else "slime"
		var at := Vector2(clampf(centre + _rng.randf_range(-70.0, 70.0), -PATH_HALF + 12.0, PATH_HALF - 12.0),
			-HALF.y - 12.0 - _rng.randf_range(0.0, 40.0))
		spawn(kind, at)
	_to_spawn -= size


func _end_wave() -> void:
	waves_held = wave
	state = State.BETWEEN
	_left = BETWEEN_SECONDS
	_mend_gate()
	banner = "Wave %d held" % wave
	banner_left = BANNER_SECONDS


func time_text() -> String:
	var whole: int = int(run_seconds)
	return "%d:%02d" % [whole / 60, whole % 60]


func result_text() -> String:
	return "The portal fell in wave %d.\n%s held - %d slain" % [wave, waves_words(waves_held), slain]


static func waves_words(count: int) -> String:
	return "1 wave" if count == 1 else "%d waves" % count
