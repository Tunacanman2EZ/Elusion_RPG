# healerrun.gd - THE HEALER'S RUN (0.98.0): a shooter like the old Nintendo
# space games, with the healer as the ship. Step 1 of the commit folder's
# HEALER_RUN_PLAN.txt.
#
# The owner, 31 Oct: "healer is constantly walking forward in a loop basically
# add some upgrades drop some enemies and healer trys to avoid running into
# enemies but can also kill them i was thinking power up like those old space
# games", "the character is only walking forward because the scene is moving
# enemies are coming down randomly generated like a dungeon player has free
# movement but scene keeps progressing", "players goal is to kill everything as
# quick as possible", "first power up 2 bullets then 4 then 6 the 8", and "make
# the path wider".
#
# ITS OWN WORLD. The run lives in a SubViewport with a world of its own
# (healerrunscreen.gd), 640 x 360 drawn at whole multiples - so nothing here
# touches the area the player stands in, its physics, its monsters or the
# server. Nothing is reported: the monsters are pictures of the game's own
# monsters moved by this script, not monsters (no BaseEnemy, no kill reports).
# Step 3 of the plan pays gold at the end, through the server.
#
# THE SCENE MOVES, NOT HER. Everything that fights is in screen space, centred
# on this node's origin: the healer, her shots, the monsters, their bullets
# (the shared BulletField). Only `terrain` scrolls - down, at scroll_speed() -
# and it is laid ahead as it comes (_lay_terrain()): the underground floor, the
# crypt's side walls, and every SECTION_LENGTH a section drawn at random - a
# hall, a row of pillars with gaps, a colonnade, a crossing with one way
# through - "like a dungeon". What scrolls off the bottom is freed.
#
# THE RUN: STRETCHES stretches of WAVES_PER_STRETCH waves, each stretch one of
# the lands (a random order, so no two runs are alike), then that last land's
# boss, then the goal marker. A wave comes when the last is dead - or when its
# time is up, on top of what is left: killing fast makes the run fast.
#
# HER SHOTS: unlimited, always firing (SHOT_GAP); a power-up takes her from 1
# to 2, 4, 6, then 8 (SHOT_STEPS, shot_offsets()). Lives: LIVES_START, a
# potion one more (to LIVES_MOST); one hit is one life, then BLINK_SECONDS
# untouchable, one shot step lost and the screen's bullets cleared.
#
# IT GETS HARDER WITH HER (the old games' hidden rank): rank() is the stretch
# plus her shot step, less one for every life lost, held to 0..RANK_MOST. Rank
# makes the monsters tougher (foe_health()), their bullets faster
# (bullet_speed()), their shots more often (fire_gap()), the waves bigger
# (group_extra()) and quicker to come (wave_time()), and the scroll a little
# faster (scroll_speed()).
#
# No class_name: preloaded by healerrunscreen.gd and the suite.
extends Node2D

signal finished(won: bool)

enum State { READY, RUNNING, BOSS, GOAL, WON, LOST }

const VIEW := Vector2(640.0, 360.0)
const HALF := Vector2(320.0, 180.0)
# THE PATH: 480 of the view's 640 (the owner: "make the path wider"); the dark
# either side holds the screen's words.
const PATH_HALF := 240.0
const WALL_PIECE := "res://scene/crypt/wallsidetall.tscn"
const WALL_STEP := 58.0
const TILE := 16
const FLOOR_SET := "res://scene/world/underground.tres"
const SECTION_LENGTH := 300.0
# The first stretch of path is bare: it starts easy.
const CLEAR_START := 700.0

const STRETCHES := 5
const WAVES_PER_STRETCH := 5
const READY_SECONDS := 1.6
const BANNER_SECONDS := 2.2
const WAVE_GAP := 1.0

const LIVES_START := 3
const LIVES_MOST := 5
const BLINK_SECONDS := 2.0
const SHOT_STEPS := [1, 2, 4, 6, 8]
const SHOT_GAP := 0.12
const SHOT_SPEED := 420.0
const SHOT_DAMAGE := 1.0
const SHOT_MOST := 320
const MOVE_SPEED := 150.0
const FOCUS_SPEED := 70.0
# Her hitbox: a few pixels at her middle, as the old games had it - the sprite
# is decoration.
const HITBOX := 2.5
const HITBOX_AT := Vector2(0.0, -10.0)
const BODY := 5.0
const SHOT_COLOUR := Color(0.55, 1.0, 0.62)

const RANK_MOST := 10
const SCROLL_START := 26.0
const SCROLL_PER_STRETCH := 6.0
const SCROLL_PER_RANK := 1.5
const BULLET_SPEED := 105.0

# What each kind of monster is: its health before rank, how big it is to a
# shot, and its chance of dropping a power-up or a potion.
const KINDS := {
	"sprite": {"health": 3.0, "radius": 9.0, "power": 0.05, "potion": 0.02},
	"slime": {"health": 7.0, "radius": 9.0, "power": 0.10, "potion": 0.03},
	"mage": {"health": 12.0, "radius": 11.0, "power": 0.30, "potion": 0.06},
	"sniper": {"health": 8.0, "radius": 10.0, "power": 0.25, "potion": 0.05},
	"boss": {"health": 260.0, "radius": 24.0, "power": 0.0, "potion": 0.0},
}
# After this many kills with no power-up, the next kill drops one.
const POWER_PITY := 25
const WAVE_KINDS := ["vee", "sweep", "mages", "slimes", "arcs", "snipers"]

const LANDS := [Element.Type.LIGHT, Element.Type.WIND, Element.Type.WATER, Element.Type.ICE,
	Element.Type.EARTH, Element.Type.FIRE, Element.Type.DARK]
# Each land's monsters (scene/enemy/<id>.tscn); "" where a land has none.
const SPRITES := {Element.Type.DARK: "darksprite", Element.Type.LIGHT: "lightsprite", Element.Type.ICE: "icesprite",
	Element.Type.WIND: "windsprite", Element.Type.EARTH: "earthsprite", Element.Type.FIRE: "firesprite",
	Element.Type.WATER: "watersprite"}
const SLIMES := {Element.Type.DARK: "darkslime", Element.Type.LIGHT: "lightslime", Element.Type.ICE: "iceslime",
	Element.Type.WIND: "windslime", Element.Type.EARTH: "earthslime", Element.Type.FIRE: "",
	Element.Type.WATER: "waterslime"}
const MAGES := {Element.Type.DARK: "darkbushmage", Element.Type.LIGHT: "lightbushmage", Element.Type.ICE: "icebushmage",
	Element.Type.WIND: "windbushmage", Element.Type.EARTH: "bushmage", Element.Type.FIRE: "firebushmage",
	Element.Type.WATER: "waterbushmage"}
const SNIPERS := {Element.Type.DARK: "darkbushsniper", Element.Type.LIGHT: "lightbushsniper",
	Element.Type.ICE: "icebushsniper", Element.Type.WIND: "windbushsniper", Element.Type.EARTH: "earthbushsniper",
	Element.Type.FIRE: "bushsniper", Element.Type.WATER: "waterbushsniper"}
const BOSSES := {Element.Type.DARK: "bossenemy", Element.Type.LIGHT: "lightboss", Element.Type.ICE: "iceboss",
	Element.Type.WIND: "windboss", Element.Type.EARTH: "earthboss", Element.Type.FIRE: "fireboss",
	Element.Type.WATER: "waterboss"}
const ESSENCES := {Element.Type.DARK: "darkessence", Element.Type.LIGHT: "lightessence", Element.Type.ICE: "iceessence",
	Element.Type.WIND: "windessence", Element.Type.EARTH: "earthessence", Element.Type.FIRE: "fireessence",
	Element.Type.WATER: "wateressence"}
const POTION_ITEM := "res://data/items/consumables/smallhealthpotion.tres"
const HEALER_SCENE := "res://scene/characters/healer.tscn"


# A monster of the run: a picture of one of the game's own, moved by its kind.
class Foe extends Node2D:
	var kind: String = ""
	var health: float = 1.0
	var most: float = 1.0
	var radius: float = 9.0
	var age: float = 0.0
	var velocity: Vector2 = Vector2.ZERO
	var side: float = 1.0
	var stop_y: float = 0.0
	var shoot_in: float = 0.0
	var casts_left: int = 0
	var leaving: bool = false
	var flash: float = 0.0
	var dying: float = -1.0
	var wave: int = 0
	# How a sprite flies: "dive" straight down, "sweep" across, "arc" in from a
	# side and back out the way it came.
	var path: String = ""
	var sprite: AnimatedSprite2D = null


# The suite's doors: which way she is steered, and whether she is focusing.
var steer: Callable = Callable(self, "_read_steer")
var focusing: Callable = Callable(self, "_read_focus")
var seed_value: int = 0

var state: int = State.READY
var lives: int = LIVES_START
var power: int = 0
var setbacks: int = 0
var stretch: int = 0
var wave_in_stretch: int = 0
var waves_done: int = 0
var run_seconds: float = 0.0
var slain: int = 0
var banner: String = ""
var banner_left: float = 0.0
var untouchable: float = 0.0
var scrolled: float = 0.0
var boss: Foe = null
var lands: Array = []

var terrain: Node2D = null
var floor_layer: TileMapLayer = null
var props: Node2D = null
var foes: Node2D = null
var drops: Node2D = null
var healer: Node2D = null
var healer_sprite: AnimatedSprite2D = null
var field: BulletField = null
var goal: Node2D = null

var _rng := RandomNumberGenerator.new()
var _state_left: float = READY_SECONDS
var _wave: int = 0
var _wave_due: float = 0.0
var _wave_started: float = 0.0
# During a stretch's banner, when its first wave comes; -1 otherwise.
var _between: float = -1.0
var _since_power: int = 0
var _shot_in: float = 0.0
var _shot_pos := PackedVector2Array()
var _shot_vel := PackedVector2Array()
var _shot_mesh: MultiMesh = null
var _shot_buffer := PackedFloat32Array()
var _painted_top: int = 1
var _painted_bottom: int = 0
var _wall_top: int = 1
var _section_top: float = -CLEAR_START
var _obstacles: Array = []
var _boss_cast: float = 0.0
var _boss_casting: int = 0
var _boss_shots: float = 0.0
var _boss_fired: int = 0
var _goal_paid: bool = false

static var _looks: Dictionary = {}


func _ready() -> void:
	# Moved every frame from _process: nothing to blend between physics ticks.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_rng.seed = seed_value if seed_value != 0 else int(Time.get_ticks_usec())
	lands = LANDS.duplicate()
	for i in range(lands.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var swap: Variant = lands[i]
		lands[i] = lands[j]
		lands[j] = swap
	var dark := ColorRect.new()
	dark.color = Color(0.02, 0.02, 0.03)
	dark.position = -HALF - Vector2(40, 40)
	dark.size = VIEW + Vector2(80, 80)
	dark.z_index = -100
	add_child(dark)
	var ambience := CanvasModulate.new()
	ambience.color = Color(0.55, 0.55, 0.65)
	add_child(ambience)
	# BEYOND THE WALLS IS DARK, over everything: a monster coming in from a
	# side comes from behind the wall, and nothing is drawn under the
	# screen's words either side.
	for x in [-HALF.x - 40.0, PATH_HALF + 9.0]:
		var beyond := ColorRect.new()
		beyond.color = Color(0.0, 0.0, 0.0)
		beyond.position = Vector2(x, -HALF.y - 40.0)
		beyond.size = Vector2(HALF.x + 40.0 - PATH_HALF - 9.0, VIEW.y + 80.0)
		beyond.z_index = 50
		add_child(beyond)
	terrain = Node2D.new()
	terrain.name = "terrain"
	add_child(terrain)
	floor_layer = TileMapLayer.new()
	floor_layer.name = "floor"
	floor_layer.tile_set = load(FLOOR_SET) as TileSet
	floor_layer.collision_enabled = false
	floor_layer.navigation_enabled = false
	terrain.add_child(floor_layer)
	props = Node2D.new()
	props.name = "props"
	terrain.add_child(props)
	drops = Node2D.new()
	drops.name = "drops"
	add_child(drops)
	foes = Node2D.new()
	foes.name = "foes"
	add_child(foes)
	_make_healer()
	_make_shots()
	field = BulletField.new()
	field.name = "bullets"
	field.capacity = 2500
	field.bounds = Rect2(-HALF - Vector2(24, 24), VIEW + Vector2(48, 48))
	add_child(field)
	_lay_terrain()
	banner = "Get ready"
	banner_left = READY_SECONDS


func _make_healer() -> void:
	healer = Node2D.new()
	healer.name = "healer"
	healer.position = Vector2(0.0, HALF.y - 50.0)
	var look: Dictionary = look_of_scene(HEALER_SCENE, false)
	healer_sprite = AnimatedSprite2D.new()
	healer_sprite.sprite_frames = look.get("frames") as SpriteFrames
	healer_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	healer_sprite.offset = look.get("offset", Vector2.ZERO)
	healer.add_child(healer_sprite)
	if healer_sprite.sprite_frames != null and healer_sprite.sprite_frames.has_animation("walkup"):
		healer_sprite.play("walkup")
	var glow := (load("res://scene/characters/playerlight.tscn") as PackedScene).instantiate() as PointLight2D
	if glow != null:
		glow.enabled = true
		healer.add_child(glow)
	add_child(healer)


func _make_shots() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_shot_mesh = MultiMesh.new()
	_shot_mesh.transform_format = MultiMesh.TRANSFORM_2D
	_shot_mesh.use_colors = true
	_shot_mesh.mesh = quad
	_shot_mesh.instance_count = SHOT_MOST
	_shot_mesh.visible_instance_count = 0
	_shot_buffer.resize(SHOT_MOST * BulletField.STRIDE)
	var shader := Shader.new()
	shader.code = BulletField.SHADER_CODE
	var shading := ShaderMaterial.new()
	shading.shader = shader
	var drawer := MultiMeshInstance2D.new()
	drawer.name = "shots"
	drawer.multimesh = _shot_mesh
	drawer.texture = BulletField.orb_texture()
	drawer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	drawer.material = shading
	# Rewritten every frame, in whatever order: never blended by the engine.
	drawer.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(drawer)
	RenderingServer.multimesh_set_physics_interpolated(_shot_mesh.get_rid(), false)


# =============================================================================
# THE NUMBERS
# =============================================================================

func rank() -> int:
	return clampi(stretch + power - setbacks, 0, RANK_MOST)


static func foe_health(base: float, at_rank: int) -> float:
	return base * (1.0 + 0.18 * at_rank)


static func bullet_speed(at_rank: int) -> float:
	return BULLET_SPEED * (1.0 + 0.06 * at_rank)


static func fire_gap(base: float, at_rank: int) -> float:
	return base * maxf(0.5, 1.0 - 0.05 * at_rank)


static func group_extra(at_rank: int) -> int:
	return at_rank / 3


static func wave_time(at_rank: int) -> float:
	return maxf(8.0, 14.0 - 0.6 * at_rank)


func scroll_speed() -> float:
	return SCROLL_START + SCROLL_PER_STRETCH * mini(stretch, STRETCHES - 1) + SCROLL_PER_RANK * rank()


static func shot_offsets(count: int) -> Array:
	"""[x offset, angle in degrees from straight up] for each shot of a volley:
	2 side by side, then each step a pair fanning wider (the owner's 2, 4, 6,
	8). One goes straight up from her middle."""
	if count <= 1:
		return [[0.0, 0.0]]
	var out: Array = [[-4.0, 0.0], [4.0, 0.0]]
	var spread: float = 7.0
	while out.size() < count:
		out.append([-6.0, -spread])
		out.append([6.0, spread])
		spread += 8.0
	return out


func land() -> int:
	return int(lands[mini(stretch, STRETCHES - 1)])


func time_text() -> String:
	var whole: int = int(run_seconds)
	return "%d:%02d" % [whole / 60, whole % 60]


func land_name(element: int) -> String:
	return Element.name_for(element).capitalize()


# =============================================================================
# EACH FRAME
# =============================================================================

func _process(delta: float) -> void:
	step(minf(delta, 0.05))


func step(delta: float) -> void:
	"""One frame of the run; the suite calls it with its own delta."""
	if state == State.WON or state == State.LOST:
		return
	banner_left = maxf(0.0, banner_left - delta)
	if banner_left <= 0.0:
		banner = ""
	if state == State.READY:
		_state_left -= delta
		_scroll(delta * 0.5)
		_move_healer(delta)
		if _state_left <= 0.0:
			state = State.RUNNING
			_start_wave()
		return
	run_seconds += delta
	untouchable = maxf(0.0, untouchable - delta)
	_scroll(delta)
	_move_healer(delta)
	_fire(delta)
	_move_shots(delta)
	_move_foes(delta)
	_move_drops(delta)
	var hit: Vector2i = field.step(delta, healer.position + HITBOX_AT, HITBOX, 0.0, untouchable > 0.0)
	if hit.x > 0:
		hurt()
	healer.visible = untouchable <= 0.0 or int(untouchable * 12.0) % 2 == 0
	match state:
		State.RUNNING:
			_waves(delta)
		State.BOSS:
			_boss_step(delta)
		State.GOAL:
			if goal != null and goal.position.y + terrain.position.y >= healer.position.y - 20.0:
				_finish(true)


func _scroll(delta: float) -> void:
	scrolled += scroll_speed() * delta
	terrain.position.y = roundf(scrolled)
	_lay_terrain()
	# What scrolls stands on the floor: pushed by a pillar she cannot get past
	# and she is crushed off the bottom of the screen.
	for o in _obstacles:
		var rect: Rect2 = o["rect"]
		rect.position.y += terrain.position.y
		healer.position = _pushed_out(healer.position, BODY, rect)
	if healer.position.y > HALF.y + 6.0:
		hurt()
		healer.position.y = HALF.y - 50.0


func _move_healer(delta: float) -> void:
	var dir: Vector2 = steer.call()
	if dir.length() > 1.0:
		dir = dir.normalized()
	var speed: float = FOCUS_SPEED if bool(focusing.call()) else MOVE_SPEED
	var at: Vector2 = healer.position + dir * speed * delta
	at.x = clampf(at.x, -PATH_HALF + 8.0, PATH_HALF - 8.0)
	at.y = clampf(at.y, -HALF.y + 30.0, HALF.y - 12.0)
	for o in _obstacles:
		var rect: Rect2 = o["rect"]
		rect.position.y += terrain.position.y
		at = _pushed_out(at, BODY, rect)
	healer.position = at


static func _pushed_out(point: Vector2, radius: float, rect: Rect2) -> Vector2:
	"""`point`, a circle of `radius`, out of `rect` the shortest way."""
	var grown: Rect2 = rect.grow(radius)
	if not grown.has_point(point):
		return point
	var left: float = point.x - grown.position.x
	var right: float = grown.end.x - point.x
	var up: float = point.y - grown.position.y
	var down: float = grown.end.y - point.y
	var least: float = minf(minf(left, right), minf(up, down))
	if least == down:
		return Vector2(point.x, grown.end.y)
	if least == up:
		return Vector2(point.x, grown.position.y)
	if least == left:
		return Vector2(grown.position.x, point.y)
	return Vector2(grown.end.x, point.y)


func _read_steer() -> Vector2:
	var dir := Vector2.ZERO
	if Input.is_action_pressed("move_right"): dir.x += 1.0
	if Input.is_action_pressed("move_left"): dir.x -= 1.0
	if Input.is_action_pressed("move_down"): dir.y += 1.0
	if Input.is_action_pressed("move_up"): dir.y -= 1.0
	return dir


func _read_focus() -> bool:
	return Input.is_action_pressed("sprint")


# =============================================================================
# HER SHOTS
# =============================================================================

func _fire(delta: float) -> void:
	_shot_in -= delta
	if _shot_in > 0.0:
		return
	_shot_in += SHOT_GAP
	var from: Vector2 = healer.position + Vector2(0.0, -16.0)
	for shot in shot_offsets(int(SHOT_STEPS[power])):
		if _shot_pos.size() >= SHOT_MOST:
			break
		_shot_pos.append(from + Vector2(float(shot[0]), 0.0))
		_shot_vel.append(Vector2.UP.rotated(deg_to_rad(float(shot[1]))) * SHOT_SPEED)


func shots_flying() -> int:
	return _shot_pos.size()


func _move_shots(delta: float) -> void:
	var i: int = 0
	while i < _shot_pos.size():
		var at: Vector2 = _shot_pos[i] + _shot_vel[i] * delta
		var spent: bool = at.y < -HALF.y - 12.0 or absf(at.x) > PATH_HALF + 4.0
		if not spent:
			for o in _obstacles:
				var rect: Rect2 = o["art"]
				rect.position.y += terrain.position.y
				if rect.has_point(at):
					spent = true
					break
		if not spent:
			for foe in foes.get_children():
				var f := foe as Foe
				if f == null or f.dying >= 0.0 or f.position.y < -HALF.y - 8.0:
					continue
				if at.distance_squared_to(f.position + Vector2(0, -8)) <= (f.radius + 3.0) * (f.radius + 3.0):
					_strike(f, SHOT_DAMAGE)
					spent = true
					break
		if spent:
			var last: int = _shot_pos.size() - 1
			_shot_pos[i] = _shot_pos[last]
			_shot_vel[i] = _shot_vel[last]
			_shot_pos.resize(last)
			_shot_vel.resize(last)
			continue
		_shot_pos[i] = at
		i += 1
	for k in _shot_pos.size():
		var o: int = k * BulletField.STRIDE
		var dir: Vector2 = _shot_vel[k].normalized()
		_shot_buffer[o] = -dir.y * 6.0
		_shot_buffer[o + 1] = dir.x * 9.0
		_shot_buffer[o + 2] = 0.0
		_shot_buffer[o + 3] = roundf(_shot_pos[k].x)
		_shot_buffer[o + 4] = dir.x * 6.0
		_shot_buffer[o + 5] = dir.y * -9.0
		_shot_buffer[o + 6] = 0.0
		_shot_buffer[o + 7] = roundf(_shot_pos[k].y)
		_shot_buffer[o + 8] = SHOT_COLOUR.r
		_shot_buffer[o + 9] = SHOT_COLOUR.g
		_shot_buffer[o + 10] = SHOT_COLOUR.b
		_shot_buffer[o + 11] = 1.0
	_shot_mesh.buffer = _shot_buffer
	_shot_mesh.visible_instance_count = _shot_pos.size()


func _strike(f: Foe, damage: float) -> void:
	f.health -= damage
	f.flash = 0.08
	if f.health <= 0.0:
		_kill(f)


func _kill(f: Foe) -> void:
	f.dying = 0.25
	slain += 1
	_since_power += 1
	var info: Dictionary = KINDS.get(f.kind, {})
	var potion_odds: float = float(info.get("potion", 0.0)) * maxf(0.4, 1.0 - 0.12 * stretch)
	if f.kind != "boss":
		if _since_power >= POWER_PITY or _rng.randf() < float(info.get("power", 0.0)):
			_drop("power", f.position)
			_since_power = 0
		elif _rng.randf() < potion_odds:
			_drop("potion", f.position)
	if f == boss:
		_boss_down()


# =============================================================================
# LIVES AND DROPS
# =============================================================================

func hurt() -> void:
	"""One hit, one life: she blinks, loses a shot step, and the screen's
	bullets go - a breath before the next."""
	if untouchable > 0.0 or state == State.WON or state == State.LOST or state == State.READY:
		return
	lives -= 1
	setbacks += 1
	power = maxi(0, power - 1)
	untouchable = BLINK_SECONDS
	field.clear()
	if lives <= 0:
		_finish(false)


func gain_power() -> void:
	power = mini(SHOT_STEPS.size() - 1, power + 1)
	_say("Shots %d" % int(SHOT_STEPS[power]))


func gain_life() -> void:
	lives = mini(LIVES_MOST, lives + 1)
	_say("A life more" if lives < LIVES_MOST else "Lives full")


func _say(words: String) -> void:
	"""A short word in the banner - unless a stretch's or the gate's is up."""
	if banner_left > 1.2 and banner != "" and not banner.begins_with("Shots") and not banner.begins_with("A life") \
			and not banner.begins_with("Lives"):
		return
	banner = words
	banner_left = 1.0


func _drop(what: String, at: Vector2) -> void:
	var item_path: String = POTION_ITEM if what == "potion" \
		else "res://data/items/materials/%s.tres" % str(ESSENCES.get(land(), "lightessence"))
	var item: Resource = load(item_path) if ResourceLoader.exists(item_path) else null
	var icon := Sprite2D.new()
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var texture: Texture2D = item.get("icon") as Texture2D if item != null else null
	if texture != null:
		icon.texture = texture
		var size: Vector2 = texture.get_size()
		icon.scale = Vector2.ONE * (14.0 / maxf(1.0, maxf(size.x, size.y)))
	icon.set_meta(&"drop", what)
	icon.position = at
	drops.add_child(icon)


func _move_drops(delta: float) -> void:
	for node in drops.get_children():
		var icon := node as Node2D
		icon.position.y += (scroll_speed() + 25.0) * delta
		if icon.position.distance_to(healer.position + HITBOX_AT) <= 16.0:
			if str(icon.get_meta(&"drop")) == "potion":
				gain_life()
			else:
				gain_power()
			_gone(icon)
		elif icon.position.y > HALF.y + 20.0:
			_gone(icon)


# =============================================================================
# THE WAVES
# =============================================================================

func _waves(_delta: float) -> void:
	if _between >= 0.0:
		if run_seconds >= _between:
			_between = -1.0
			_start_wave()
		return
	if wave_left() == 0 and _wave_due > run_seconds + WAVE_GAP:
		_wave_due = run_seconds + WAVE_GAP
	if run_seconds >= _wave_due:
		_next_wave()


func wave_left() -> int:
	"""How many of the newest wave are still standing."""
	var left: int = 0
	for foe in foes.get_children():
		var f := foe as Foe
		if f != null and f.wave == _wave and f.dying < 0.0:
			left += 1
	return left


func _next_wave() -> void:
	waves_done += 1
	wave_in_stretch += 1
	if wave_in_stretch >= WAVES_PER_STRETCH:
		wave_in_stretch = 0
		stretch += 1
		if stretch >= STRETCHES:
			_start_boss()
			return
		banner = "Stretch %d - the %s lands" % [stretch + 1, land_name(land())]
		banner_left = BANNER_SECONDS
		_between = run_seconds + BANNER_SECONDS
		return
	_start_wave()


func _start_wave() -> void:
	_wave += 1
	_wave_started = run_seconds
	_wave_due = run_seconds + wave_time(rank())
	if waves_done == 0:
		banner = "Stretch 1 - the %s lands" % land_name(land())
		banner_left = BANNER_SECONDS
	spawn_wave(_pick_kind())


func _pick_kind() -> String:
	# The first waves are the gentlest: a V, then a sweep.
	if waves_done == 0:
		return "vee"
	if waves_done == 1:
		return "sweep"
	return str(WAVE_KINDS[_rng.randi_range(0, WAVE_KINDS.size() - 1)])


func spawn_wave(kind: String) -> Array:
	"""One wave of `kind`, of this stretch's land. Returned for the suite."""
	var made: Array = []
	var r: int = rank()
	var top: float = -HALF.y - 24.0
	match kind:
		"vee":
			var count: int = mini(9, 5 + group_extra(r))
			var centre: float = _rng.randf_range(-PATH_HALF + 90.0, PATH_HALF - 90.0)
			for i in count:
				var off: float = float(i) - float(count - 1) / 2.0
				var f := _foe("sprite", Vector2(centre + off * 26.0, top - absf(off) * 22.0))
				f.path = "dive"
				f.velocity = Vector2(0.0, 70.0 + 5.0 * r)
				f.shoot_in = _rng.randf_range(1.2, 2.4)
				made.append(f)
		"sweep":
			var count: int = mini(10, 6 + group_extra(r))
			var side: float = -1.0 if _rng.randf() < 0.5 else 1.0
			var row_y: float = _rng.randf_range(-HALF.y + 40.0, -HALF.y + 90.0)
			for i in count:
				var f := _foe("sprite", Vector2(-side * (PATH_HALF + 20.0 + i * 30.0), row_y))
				f.side = side
				f.path = "sweep"
				f.velocity = Vector2(side * 95.0, 10.0)
				f.shoot_in = _rng.randf_range(0.8, 2.0)
				made.append(f)
		"mages":
			var count: int = 2 + (1 if r >= 4 else 0)
			for i in count:
				var x: float = (float(i) - float(count - 1) / 2.0) * 150.0
				var f := _foe("mage", Vector2(x, top))
				f.velocity = Vector2(0.0, 60.0)
				f.stop_y = -HALF.y + 70.0 + _rng.randf_range(0.0, 30.0)
				f.casts_left = 3
				f.shoot_in = 1.0
				made.append(f)
		"slimes":
			var count: int = 4 + group_extra(r)
			for i in count:
				var f := _foe("slime", Vector2(_rng.randf_range(-PATH_HALF + 30.0, PATH_HALF - 30.0),
					top - _rng.randf_range(0.0, 80.0)))
				f.velocity = Vector2(0.0, 32.0 + 3.0 * r)
				f.side = _rng.randf_range(0.0, TAU)
				made.append(f)
		"arcs":
			var count: int = 6 + group_extra(r)
			for i in count:
				var side: float = -1.0 if i % 2 == 0 else 1.0
				var f := _foe("sprite", Vector2(side * (PATH_HALF + 16.0), -HALF.y - 10.0 - float(i / 2) * 34.0))
				f.side = side
				f.path = "arc"
				f.velocity = Vector2(-side * 110.0, 70.0)
				f.shoot_in = _rng.randf_range(1.0, 2.0)
				made.append(f)
		"snipers":
			for side in [-1.0, 1.0]:
				var f := _foe("sniper", Vector2(side * (PATH_HALF - 50.0), top))
				f.velocity = Vector2(0.0, 55.0)
				f.stop_y = -HALF.y + 45.0
				f.side = side
				f.casts_left = 6 + group_extra(r)
				f.shoot_in = 1.0
				made.append(f)
	return made


func _foe(kind: String, at: Vector2) -> Foe:
	var element: int = land()
	var scene_id: String = ""
	match kind:
		"sprite":
			scene_id = str(SPRITES.get(element, "windsprite"))
		"slime":
			scene_id = str(SLIMES.get(element, ""))
			if scene_id == "":
				scene_id = str(SPRITES.get(element, "windsprite"))
		"mage":
			scene_id = str(MAGES.get(element, "bushmage"))
		"sniper":
			scene_id = str(SNIPERS.get(element, "bushsniper"))
		"boss":
			scene_id = str(BOSSES.get(element, "bossenemy"))
	var f := Foe.new()
	f.kind = kind
	f.wave = _wave
	var info: Dictionary = KINDS.get(kind, {})
	f.most = foe_health(float(info.get("health", 3.0)), rank())
	f.health = f.most
	f.radius = float(info.get("radius", 9.0))
	f.position = at
	var look: Dictionary = look_of_scene("res://scene/enemy/%s.tscn" % scene_id)
	f.sprite = AnimatedSprite2D.new()
	f.sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	f.sprite.sprite_frames = look.get("frames") as SpriteFrames
	f.sprite.material = look.get("material") as Material
	f.sprite.self_modulate = look.get("modulate", Color.WHITE)
	f.sprite.offset = look.get("offset", Vector2.ZERO)
	f.sprite.scale = look.get("scale", Vector2.ONE)
	f.add_child(f.sprite)
	var walk: String = str(look.get("walk", ""))
	if walk != "":
		f.sprite.play(walk)
	foes.add_child(f)
	return f


func _move_foes(delta: float) -> void:
	var r: int = rank()
	var colour: Color = Element.colour_for(land())
	for foe in foes.get_children():
		var f := foe as Foe
		if f == null:
			continue
		if f.dying >= 0.0:
			f.dying -= delta
			f.modulate.a = clampf(f.dying / 0.25, 0.0, 1.0)
			f.scale = Vector2.ONE * (1.0 + (0.25 - f.dying) * 1.2)
			if f.dying <= 0.0:
				_gone(f)
			continue
		f.age += delta
		f.flash = maxf(0.0, f.flash - delta)
		f.modulate = Color(2.2, 2.2, 2.2) if f.flash > 0.0 else Color.WHITE
		match f.kind:
			"sprite":
				if f.path == "arc":
					# In from a side, bending back out the way it came.
					f.velocity.x += f.side * 140.0 * delta
				f.position += f.velocity * delta
				f.shoot_in -= delta
				if f.shoot_in <= 0.0 and f.position.y > -HALF.y + 10.0 and f.position.y < HALF.y - 120.0:
					f.shoot_in = fire_gap(2.6, r)
					_aimed(f.position, colour, bullet_speed(r))
			"slime":
				f.position.y += f.velocity.y * delta
				f.position.x += sin(f.age * 2.2 + f.side) * 22.0 * delta
			"mage", "sniper":
				if not f.leaving and f.position.y < f.stop_y:
					f.position.y = minf(f.stop_y, f.position.y + f.velocity.y * delta)
				elif f.leaving:
					f.position.y += 90.0 * delta
				else:
					f.shoot_in -= delta
					if f.shoot_in <= 0.0:
						if f.kind == "mage":
							_fan(f.position, colour, 5 + r / 3, 0.7, bullet_speed(r) * 0.9)
							f.shoot_in = fire_gap(1.8, r)
						else:
							_aimed(f.position, colour, bullet_speed(r) * 1.6)
							f.shoot_in = fire_gap(1.1, r)
						f.casts_left -= 1
						if f.casts_left <= 0:
							f.leaving = true
			"boss":
				pass
		if f.kind != "boss":
			if f.position.distance_to(healer.position + HITBOX_AT) < f.radius + BODY - 2.0:
				hurt()
				if f.kind == "sprite":
					_kill(f)
			if f.position.y > HALF.y + 40.0 or absf(f.position.x) > HALF.x + 120.0:
				_gone(f)


static func _gone(node: Node) -> void:
	"""Out of the run at once - off its parent this frame, freed after - so
	nothing later in the same step counts it again."""
	var parent: Node = node.get_parent()
	if parent != null:
		parent.remove_child(node)
	node.queue_free()


func _aimed(from: Vector2, colour: Color, speed: float) -> void:
	var aim: float = ((healer.position + HITBOX_AT) - from).angle()
	field.spawn(from, aim, speed, colour)


func _fan(from: Vector2, colour: Color, count: int, spread: float, speed: float) -> void:
	var aim: float = ((healer.position + HITBOX_AT) - from).angle()
	for k in count:
		var share: float = 0.0 if count == 1 else float(k) / float(count - 1) - 0.5
		field.spawn(from, aim + share * spread, speed, colour, k == count / 2)


# =============================================================================
# THE BOSS AND THE GOAL
# =============================================================================

func _start_boss() -> void:
	state = State.BOSS
	stretch = STRETCHES - 1
	wave_in_stretch = WAVES_PER_STRETCH - 1
	banner = "The gate - and its keeper"
	banner_left = BANNER_SECONDS
	_wave += 1
	boss = _foe("boss", Vector2(0.0, -HALF.y - 60.0))
	_boss_cast = 2.5
	_boss_casting = -1


func _boss_step(delta: float) -> void:
	if boss == null or not is_instance_valid(boss) or boss.dying >= 0.0:
		return
	var home := Vector2(sin(boss.age * 0.6) * 140.0, -HALF.y + 70.0)
	boss.position = boss.position.move_toward(home, 60.0 * delta)
	var r: int = rank()
	var colour: Color = Element.colour_for(land())
	_boss_cast -= delta
	if _boss_casting < 0 and _boss_cast <= 0.0:
		_boss_casting = _rng.randi_range(0, 3)
		_boss_shots = 0.0
		_boss_fired = 0
	if _boss_casting < 0:
		return
	_boss_shots -= delta
	if _boss_shots > 0.0:
		return
	var from: Vector2 = boss.position + Vector2(0.0, -12.0)
	match _boss_casting:
		0:
			var n: int = 16 + 2 * r
			var turn: float = (PI / n) * float(_boss_fired % 2)
			for k in n:
				field.spawn(from, turn + TAU * k / n, bullet_speed(r) * 0.7, colour)
			_boss_shots = 0.7
		1:
			_fan(from, colour, 7 + r / 2, 0.9, bullet_speed(r))
			_boss_shots = 0.5
		2:
			var gap_at: float = _rng.randf_range(-PATH_HALF + 40.0, PATH_HALF - 100.0)
			var x: float = -PATH_HALF + 6.0
			while x < PATH_HALF:
				if x < gap_at or x > gap_at + 64.0:
					field.spawn(Vector2(x, -HALF.y + 4.0), PI / 2.0, bullet_speed(r) * 0.6, colour)
				x += 20.0
			_boss_shots = 1.0
		3:
			for k in 4:
				field.spawn(from, _boss_fired * 0.23 + TAU * k / 4.0, bullet_speed(r) * 0.75, colour)
			_boss_shots = 0.07
	_boss_fired += 1
	var volleys: int = [3, 5, 3, 40][_boss_casting]
	if _boss_fired >= volleys:
		_boss_casting = -1
		_boss_cast = 1.4


func boss_share() -> float:
	if boss == null or not is_instance_valid(boss):
		return 0.0
	return clampf(boss.health / boss.most, 0.0, 1.0)


func _boss_down() -> void:
	state = State.GOAL
	field.clear()
	banner = "The way is open"
	banner_left = BANNER_SECONDS
	# THE GOAL MARKER, laid ahead on the path: two pillars, the gold arrow
	# over the way between them, and what reaching it is worth.
	goal = Node2D.new()
	goal.name = "goal"
	goal.position = Vector2(0.0, -terrain.position.y - HALF.y - 40.0)
	for x in [-36.0, 36.0]:
		var pillar := (load("res://scene/crypt/pillar.tscn") as PackedScene).instantiate() as Node2D
		pillar.position = Vector2(x, 0.0)
		goal.add_child(pillar)
	var arrow: Node2D = (load("res://src/shared/beckonarrow.gd") as GDScript).call("make", Vector2(0.0, -22.0))
	goal.add_child(arrow)
	var goal_sign := Label.new()
	goal_sign.text = "GOAL - 1000 gold"
	goal_sign.add_theme_font_size_override("font_size", 10)
	goal_sign.add_theme_color_override("font_color", Color(1.0, 0.86, 0.45))
	goal_sign.add_theme_color_override("font_outline_color", Color.BLACK)
	goal_sign.add_theme_constant_override("outline_size", 3)
	goal_sign.position = Vector2(-44.0, -52.0)
	goal.add_child(goal_sign)
	props.add_child(goal)


func _finish(won: bool) -> void:
	state = State.WON if won else State.LOST
	field.clear()
	_shot_pos.resize(0)
	_shot_vel.resize(0)
	_shot_mesh.visible_instance_count = 0
	banner = ""
	finished.emit(won)


func result_text() -> String:
	if state == State.WON:
		return "Cleared in %s - %d slain" % [time_text(), slain]
	if stretch >= STRETCHES or state == State.BOSS:
		return "Fell at the gate after %s - %d slain" % [time_text(), slain]
	return "Fell in stretch %d, wave %d, after %s - %d slain" % [mini(stretch + 1, STRETCHES),
		wave_in_stretch + 1, time_text(), slain]


func goal_reached() -> bool:
	return state == State.WON


# =============================================================================
# THE PATH, LAID AHEAD AS IT COMES
# =============================================================================

func _lay_terrain() -> void:
	var top: float = -terrain.position.y - HALF.y - 64.0
	var bottom: float = -terrain.position.y + HALF.y + 64.0
	# The floor, a row of tiles at a time.
	var want_top: int = floori(top / TILE)
	while _painted_top > want_top:
		_painted_top -= 1
		for c in range(-int(PATH_HALF) / TILE, int(PATH_HALF) / TILE):
			floor_layer.set_cell(Vector2i(c, _painted_top), 1, Vector2i(_rng.randi_range(1, 4), _rng.randi_range(1, 3)))
	var want_bottom: int = floori(bottom / TILE)
	while _painted_bottom > want_bottom:
		for c in range(-int(PATH_HALF) / TILE, int(PATH_HALF) / TILE):
			floor_layer.erase_cell(Vector2i(c, _painted_bottom))
		_painted_bottom -= 1
	if _painted_bottom < _painted_top:
		_painted_bottom = _painted_top
	# The side walls, a piece every WALL_STEP.
	var wall_want: int = floori(top / WALL_STEP)
	while _wall_top > wall_want:
		_wall_top -= 1
		for x in [-PATH_HALF - 4.5, PATH_HALF + 4.5]:
			var piece := (load(WALL_PIECE) as PackedScene).instantiate() as Node2D
			piece.position = Vector2(x, float(_wall_top) * WALL_STEP)
			piece.set_meta(&"wall", true)
			props.add_child(piece)
	# A section ahead every SECTION_LENGTH.
	while _section_top > top:
		_section_top -= SECTION_LENGTH
		_lay_section(_section_top)
	# What has gone by.
	for piece in props.get_children():
		if piece != goal and (piece as Node2D).position.y > bottom + 40.0:
			_gone(piece)
	var kept: Array = []
	for o in _obstacles:
		if (o["rect"] as Rect2).position.y < bottom + 40.0:
			kept.append(o)
	_obstacles = kept


func _lay_section(at_y: float) -> void:
	"""A piece of the dungeon from at_y up SECTION_LENGTH: decoration always,
	and - past the start - one of the shapes that change how the path plays."""
	for i in _rng.randi_range(1, 3):
		var decor: Array = ["res://scene/crypt/candelabra.tscn", "res://scene/crypt/skullpile.tscn",
			"res://scene/crypt/bones.tscn", "res://scene/crypt/rubble2.tscn", "res://scene/crypt/rubble4.tscn"]
		var path: String = str(decor[_rng.randi_range(0, decor.size() - 1)])
		var x: float = (PATH_HALF - 18.0) * (-1.0 if _rng.randf() < 0.5 else 1.0)
		if path.ends_with("bones.tscn") or path.contains("rubble"):
			x = _rng.randf_range(-PATH_HALF + 20.0, PATH_HALF - 20.0)
		_prop(path, Vector2(x, at_y + _rng.randf_range(20.0, SECTION_LENGTH - 20.0)))
	# Nothing in the way at the start, nor at the gate: the boss is enough.
	if at_y > -CLEAR_START or state == State.BOSS or state == State.GOAL:
		return
	match _rng.randi_range(0, 3):
		0:
			pass  # a hall: nothing in the way
		1:
			# A row of pillars, gaps between.
			var y: float = at_y + SECTION_LENGTH * 0.5
			var x: float = -PATH_HALF + _rng.randf_range(50.0, 90.0)
			while x < PATH_HALF - 40.0:
				_pillar(Vector2(x, y))
				x += _rng.randf_range(90.0, 130.0)
		2:
			# A colonnade: pillars down both sides of the middle.
			var y: float = at_y + 40.0
			while y < at_y + SECTION_LENGTH - 30.0:
				_pillar(Vector2(-110.0, y))
				_pillar(Vector2(110.0, y))
				y += 80.0
		3:
			# A crossing: a wall of pillars with one way through.
			var y: float = at_y + SECTION_LENGTH * 0.5
			var gap: float = _rng.randf_range(-PATH_HALF + 70.0, PATH_HALF - 70.0)
			var x: float = -PATH_HALF + 12.0
			while x < PATH_HALF - 8.0:
				if absf(x - gap) > 48.0:
					_pillar(Vector2(x, y))
				x += 24.0


func _prop(path: String, at: Vector2) -> Node2D:
	if not ResourceLoader.exists(path):
		return null
	var piece := (load(path) as PackedScene).instantiate() as Node2D
	piece.position = at
	props.add_child(piece)
	return piece


func _pillar(at: Vector2) -> void:
	_prop("res://scene/crypt/pillar.tscn", at)
	# Its foot (pillar.tscn's body) stops her; its whole picture stops a shot.
	_obstacles.append({"rect": Rect2(at + Vector2(-8.5, -12.0), Vector2(17.0, 12.0)),
		"art": Rect2(at + Vector2(-8.5, -30.0), Vector2(17.0, 30.0))})


func obstacle_count() -> int:
	return _obstacles.size()


# =============================================================================
# PICTURES OF THE GAME'S OWN
# =============================================================================

static func look_of_scene(path: String, instance: bool = true) -> Dictionary:
	"""{frames, material, modulate, offset, scale, walk} of the first
	AnimatedSprite2D in the scene at `path`, read from an instance that is never
	added (its scripts' _ready never run), its element's recolour as the world
	draws it (BaseEnemy.element_material). {} when there is none."""
	if _looks.has(path):
		return _looks[path]
	var out: Dictionary = {}
	var packed: PackedScene = load(path) as PackedScene if ResourceLoader.exists(path) else null
	if packed != null and not instance:
		# A player's scene is read, never made: none of its scripts run.
		var state_of: SceneState = packed.get_state()
		for n in state_of.get_node_count():
			if state_of.get_node_type(n) != &"AnimatedSprite2D":
				continue
			out = {"frames": null, "offset": Vector2.ZERO, "scale": Vector2.ONE, "walk": "walkup",
				"modulate": Color.WHITE, "material": null}
			for p in state_of.get_node_property_count(n):
				match state_of.get_node_property_name(n, p):
					&"sprite_frames":
						out["frames"] = state_of.get_node_property_value(n, p)
					&"offset":
						out["offset"] = state_of.get_node_property_value(n, p)
					&"scale":
						out["scale"] = state_of.get_node_property_value(n, p)
			break
		_looks[path] = out
		return out
	if packed != null:
		var node: Node = packed.instantiate()
		var sprite: AnimatedSprite2D = null
		for child in node.get_children():
			if child is AnimatedSprite2D:
				sprite = child
				break
		if sprite != null and sprite.sprite_frames != null:
			var frames: SpriteFrames = sprite.sprite_frames
			var walk: String = ""
			for wanted in ["walkdown", "idledown", "walkup"]:
				if frames.has_animation(wanted) and frames.get_frame_count(wanted) > 0:
					walk = wanted
					break
			out = {"frames": frames, "offset": sprite.offset, "scale": sprite.scale * ((node as Node2D).scale
				if node is Node2D else Vector2.ONE), "walk": walk, "modulate": Color.WHITE, "material": null}
			var data: Variant = node.get("enemy_data")
			if data is EnemyData:
				var element: int = int((data as EnemyData).element)
				var override: Variant = node.get("element_override")
				if override is int and int(override) >= 0:
					element = int(override)
				var recolour: bool = (data as EnemyData).recolour_to_element or (override is int and int(override) >= 0)
				if recolour and element != Element.Type.NONE:
					out["material"] = BaseEnemy.element_material(data, element)
				out["modulate"] = (data as EnemyData).body_tint
		node.free()
	_looks[path] = out
	return out
