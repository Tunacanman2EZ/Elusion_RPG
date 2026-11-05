extends Node2D

const StatusEffects := preload("res://src/characters/statuseffects.gd")
const RangeRingScript := preload("res://src/shared/rangering.gd")
# descentlands.gd - THE LANDS SHINE IN THE DESCENT (0.124.0, step 1 of the
# commit folder's DESCENT_PLAN_3.txt). A child of the run (descentrun.gd
# _lands), over the room's floor.
#
# The owner, 4 Nov: "fields should use the bosses elemental hazards in this
# minigame so the wind pushing the player tunnel vision etc", "it has to be
# challenging we can add lasers", and of the Light Keeper's turning spokes,
# "basically prism attack is the same concept".
#
# THE KEEPER'S HAZARDS, WITH NO KEEPER IN THE ROOM. Every fight room from the
# second of a floor is part of its keeper's fight: the floor's boss, hidden
# (a CASTER: the boss's own scene, never drawn, never targeted, its brain and
# clocks stopped), throws its signature volley and its stalagmite shapes at
# you, turn about, every gap() seconds - the same code the bosses use
# (bossenemy.gd THE KITS: fire_volley(), _cast_stalagmites_from_cast()), so
# the same orbs, the same telegraphs and the same effects:
#   the Crypt (the Fire Keeper's)  PINCER, the floor left burning   burn
#   the Frozen Halls               FROST shards that lie as mines   chill
#   the Drowned Halls              TIDE walls with one moving gap   soaked
#   the Windworn Halls             GALE fans that shove, VORTEX     shove
#   the Shining Vault              PRISM spokes - the lasers        dazzle
#   the Deep Roots                 BOULDERS where you stood         root
#   the Dark Below                 a bit of every kit               wither
# A volley comes from somewhere you can see it coming: a ring of its land's
# colour closes for WARN seconds where it will start (the room's edge for a
# fan or a wall of orbs, open floor for a ring of spokes), then it fires at
# you. In the Deep two lands throw at once (two casters).
#
# THE FLOOR'S WEATHER, drawn in code (no art): snow, bubbles, gusts, motes,
# grit, embers, wisps - weather_for(), one CPUParticles2D over the floor.
#
# THE ORBS' EFFECTS STRONGER: the Descent's bullet zone carries every orb's
# element at effect_for() (the fields' are at half), stronger each floor.
#
# THE FLOOR ITSELF FIGHTS (0.127.0) - the owner, of the weather: "when i
# think of enviromental damage i mean bubbles or sparks that can catch a
# player on fire poison gas etc", "start building them". From the second
# room, every ENV gap the room's lands (one, or two mixed - descentrun.gd
# room_lands()) loose their own hazard on this game's player (begin_env(),
# _step_env()), each seen coming and stepped out of:
#   spark   (fire)   a bright ember drifting down - touched, you burn
#   hail    (ice)    a shadow grows, the stone lands - chilled
#   bubble  (water)  rising from the floor - touched, it pops: soaked
#   gust    (wind)   a lane of streaks thickens, then shoves you along it
#   flare   (light)  a mote swells and flashes - near it, tunnel vision
#   rock    (earth)  a shadow of falling grit, then the rock - rooted
#   wisp    (dark)   drifts after you - touched, withered (hits doubled)
#   gas     (poison) from floor 3: a green cloud seeps up and drifts -
#                    inside it, poison every GAS_TICK
# Each hits for env_hit() (more each floor), and at most every TOUCH_GAP.
# Drawn in code: what lies on the floor by this node, what floats by `_air`
# over the weather.
#
# AND THEY REACT (0.128.0, _react()) - the owner: "ok resume", after "when
# two weathers mix in one room ... they react to each other":
#   a bubble popped leaves a PUDDLE (soaked while you stand in it)
#   a spark in a gas cloud      - the cloud EXPLODES (fire, twice the hit)
#   a spark through hail's shadow - it melts before it lands: a puddle
#   a spark into water          - put out, in a puff of STEAM
#   a flare flashing over puddles - the light runs through them (SHOCK)
#   hail landing on a puddle    - it freezes to ICE (chilled on it)
#   a gust                      - blows what floats and the gas along it

const WARN := 0.7
# The first throw this long after the pack comes; then every gap().
const FIRST := 2.5
const GAP_FIRST := 7.5
const GAP_STEP := 0.6
const GAP_LEAST := 3.0
# A ring of spokes starts on open floor this far from you.
const RING_NEAR := 130.0
const RING_FAR := 230.0
# The orbs' effects: this strong on the first floor, more each floor.
const EFFECTS_FIRST := 0.7
const EFFECTS_STEP := 0.05
const EFFECTS_MOST := 1.0
# Volleys that spread from a point in every direction, rather than at you.
const RINGS := [&"prism", &"vortex"]
const WEATHER_Z := 3
# A second land's weather, mixed in, thins both to this share.
const MIX_THIN := 0.6
# THE FLOOR ITSELF (0.127.0): the first hazard this long after the pack, then
# every env_gap(); how hard they hit; at most one hit this often; how near a
# touch counts; poison gas from this floor (an index), this often a gap.
const ENV_FIRST := 3.0
const ENV_GAP_FIRST := 4.0
const ENV_GAP_STEP := 0.3
const ENV_GAP_LEAST := 1.6
const ENV_HIT_FIRST := 8
const ENV_HIT_STEP := 4
const TOUCH_GAP := 0.6
const TOUCH_SLACK := 8.0
const GAS_FROM := 2
const GAS_CHANCE := 0.35
const GAS_TICK := 0.5
const AIR_Z := 7
# AND THEY REACT (0.128.0): a puddle and ice, how long and how wide; how far a
# flare's light runs through puddles; how far a hail freezes one; how far a
# gust blows what is in its lane; an explosion's reach past the cloud.
const PUDDLE_LIFE := 4.0
const PUDDLE_WARN := 0.5
const PUDDLE_R := 18.0
const ICE_LIFE := 5.0
const SHOCK_REACH := 1.5
const FREEZE_REACH := 24.0
const GUST_PUSH := 70.0
const BLAST_PAST := 12.0
const KIND_FOR := {Element.Type.FIRE: "spark", Element.Type.ICE: "hail", Element.Type.WATER: "bubble",
	Element.Type.WIND: "gust", Element.Type.LIGHT: "flare", Element.Type.EARTH: "rock", Element.Type.DARK: "wisp"}

var run: Node = null
var phase: int = 0
var every: float = GAP_FIRST
var _casters: Array = []
var _left: float = -1.0
var _turn: int = 0
# [origin, seconds left, caster, volley name, aim, reach, colour]
var _warns: Array = []
var _weathers: Array = []
var _weather_lands: Array = []
var thrown: int = 0
# THE FLOOR ITSELF (0.127.0).
var env_lands: Array = []
var env_floor: int = 0
var env_every: float = ENV_GAP_FIRST
var hazards: Array = []
var env_made: int = 0
var env_hits: int = 0
var _env_left: float = -1.0
var _touch_left: float = 0.0
var _air: Node2D = null
# What a hazard made this step (a puddle, a blast), joined after it.
var _born: Array = []
var reactions: Dictionary = {}


static func gap(floor_index: int) -> float:
	"""Seconds between throws on this floor (a run's floor index)."""
	return maxf(GAP_LEAST, GAP_FIRST - GAP_STEP * float(floor_index))


static func phase_for(floor_index: int) -> int:
	"""Which of the kits' three phases the hazards throw: 0 on floors 1-3, 1
	on 4-6, 2 from the seventh."""
	return clampi(floori(float(floor_index) / 3.0), 0, 2)


static func effect_for(floor_index: int) -> float:
	return minf(EFFECTS_MOST, EFFECTS_FIRST + EFFECTS_STEP * float(floor_index))


func begin(keeper_ids: Array, floor_index: int, faster: bool = false) -> void:
	"""Hazards for this room: a caster for each of `keeper_ids`, throwing
	every gap() (half that when `faster`, an Impossible room's)."""
	end()
	phase = phase_for(floor_index) if not faster else 2
	every = gap(floor_index) * (0.5 if faster else 1.0)
	_left = FIRST
	for id in keeper_ids:
		var caster: Node2D = _make_caster(str(id))
		if caster != null:
			_casters.append(caster)


func end() -> void:
	"""No hazards: the casters freed, the marks gone, the floor quiet."""
	for caster in _casters:
		if is_instance_valid(caster):
			(caster as Node).queue_free()
	_casters = []
	_warns = []
	_left = -1.0
	env_lands = []
	hazards = []
	_env_left = -1.0
	queue_redraw()
	if _air != null and is_instance_valid(_air):
		_air.queue_redraw()


func active() -> bool:
	return not _casters.is_empty()


func step(delta: float) -> void:
	"""The run's FIGHT, after the pack has come: count down, mark, throw -
	and the floor's own hazards."""
	_step_env(delta)
	if _casters.is_empty():
		return
	var still: Array = []
	for warn in _warns:
		warn[1] = float(warn[1]) - delta
		if float(warn[1]) <= 0.0:
			_fire(warn)
		else:
			still.append(warn)
	_warns = still
	queue_redraw()
	_left -= delta
	if _left > 0.0:
		return
	_left = every
	var caster: Node2D = _casters[_turn % _casters.size()]
	_turn += 1
	if not is_instance_valid(caster):
		return
	var me: Node2D = run.call("_player") as Node2D if run != null else null
	if me == null:
		return
	# Turn about: a volley, then the stalagmites, then a volley...
	if _turn % 2 == 1 or not (me is CharacterBody2D):
		_mark_volley(caster, me)
	else:
		caster.set("player", me)
		caster.call("_cast_stalagmites_from_cast")
		thrown += 1


func _mark_volley(caster: Node2D, me: Node2D) -> void:
	var kind: StringName = caster.call("_pick_volley", phase)
	var target: Vector2 = me.global_position
	var origin: Vector2 = _ring_spot(target) if kind in RINGS else run.call("_edge_spot")
	var element: int = int(caster.call("current_element"))
	_warns.append([origin, WARN, caster, "%s%d:%d" % [kind, phase, randi() % 64], (target - origin).angle(),
		origin.distance_to(target), Element.colour_for(element)])
	queue_redraw()


func _fire(warn: Array) -> void:
	var caster: Node2D = warn[2]
	if not is_instance_valid(caster):
		return
	# Aimed again as it fires, at where you are now.
	var me: Node2D = run.call("_player") as Node2D if run != null else null
	var origin: Vector2 = warn[0]
	var aim: float = float(warn[4])
	var reach: float = float(warn[5])
	if me != null:
		aim = (me.global_position - origin).angle()
		reach = origin.distance_to(me.global_position)
	caster.call("fire_volley", BulletZone.find(self), origin, aim, str(warn[3]), reach)
	thrown += 1


func _ring_spot(target: Vector2) -> Vector2:
	var rect: Rect2 = run.get("room_rect")
	var inner: Rect2 = rect.grow(-40.0)
	for attempt in 24:
		var at: Vector2 = Vector2(randf_range(inner.position.x, inner.end.x), randf_range(inner.position.y, inner.end.y))
		var far: float = at.distance_to(target)
		if far >= RING_NEAR and far <= RING_FAR:
			return at
	return inner.get_center()


func _make_caster(id: String) -> Node2D:
	"""THE KEEPER, HIDDEN: its own scene, so its own volleys, shapes, damage
	and element - not drawn, not in "enemies" (nothing aims at it, nothing
	hits it), its brain, clocks and body stopped; marked as the run's (no
	kill, never shared or numbered)."""
	var path: String = "res://scene/enemy/%s.tscn" % id
	if not ResourceLoader.exists(path) or run == null or run.get_parent() == null:
		return null
	var caster := (load(path) as PackedScene).instantiate() as Node2D
	caster.name = "hazard_%s" % id
	caster.set_meta(&"stress_copy", true)
	caster.set_meta(&"descent_caster", true)
	caster.visible = false
	var rect: Rect2 = run.get("room_rect")
	caster.position = Vector2(rect.get_center().x, rect.position.y - 40.0)
	run.get_parent().add_child(caster)
	for group in [&"enemies", &"bosses", &"unpushable"]:
		if caster.is_in_group(group):
			caster.remove_from_group(group)
	caster.set_process(false)
	caster.set_physics_process(false)
	if caster is CollisionObject2D:
		(caster as CollisionObject2D).collision_layer = 0
		(caster as CollisionObject2D).collision_mask = 0
	for child in caster.find_children("*", "", true, false):
		if child is Timer:
			(child as Timer).stop()
		elif child is Area2D:
			(child as Area2D).set_deferred("monitoring", false)
			(child as Area2D).set_deferred("monitorable", false)
		elif child is CollisionObject2D:
			(child as CollisionObject2D).collision_layer = 0
	return caster


func _draw() -> void:
	_draw_floor_hazards()
	for warn in _warns:
		var at: Vector2 = warn[0]
		var left: float = clampf(float(warn[1]) / WARN, 0.0, 1.0)
		var colour: Color = warn[6]
		draw_set_transform(at, 0.0, Vector2(1.0, 0.6))
		draw_circle(Vector2.ZERO, 6.0 + 4.0 * (1.0 - left), Color(colour, 0.35 + 0.4 * (1.0 - left)))
		draw_arc(Vector2.ZERO, 8.0 + 22.0 * left, 0.0, TAU, 28, Color(colour * 1.6, 0.95), 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# =============================================================================
# THE WEATHER
# =============================================================================

static func weather_for(land: int) -> Dictionary:
	"""Each land's weather: how many, how long each lives, its colour, which
	way and how fast it goes, its pull, its size, and its shape ("dot" or
	"streak")."""
	match land:
		Element.Type.ICE:
			return {"amount": 70, "life": 8.0, "colour": Color(0.92, 0.97, 1.0, 0.8), "dir": Vector2(0.15, 1),
				"speed": [10.0, 24.0], "gravity": Vector2(0, 6), "size": [0.5, 1.1], "shape": "dot"}
		Element.Type.WATER:
			return {"amount": 45, "life": 6.0, "colour": Color(0.55, 0.8, 1.0, 0.5), "dir": Vector2(0, -1),
				"speed": [6.0, 14.0], "gravity": Vector2(0, -8), "size": [0.5, 1.3], "shape": "ring"}
		Element.Type.WIND:
			return {"amount": 34, "life": 2.6, "colour": Color(0.85, 1.0, 0.9, 0.35), "dir": Vector2(1, 0.12),
				"speed": [170.0, 260.0], "gravity": Vector2.ZERO, "size": [0.7, 1.2], "shape": "streak"}
		Element.Type.LIGHT:
			return {"amount": 55, "life": 6.0, "colour": Color(1.0, 0.92, 0.55, 0.75), "dir": Vector2(0, -1),
				"speed": [3.0, 10.0], "gravity": Vector2(0, -4), "size": [0.4, 1.0], "shape": "dot"}
		Element.Type.EARTH:
			return {"amount": 45, "life": 4.0, "colour": Color(0.62, 0.48, 0.32, 0.8), "dir": Vector2(0, 1),
				"speed": [0.0, 12.0], "gravity": Vector2(0, 45), "size": [0.4, 0.8], "shape": "dot"}
		Element.Type.FIRE:
			return {"amount": 40, "life": 4.0, "colour": Color(1.0, 0.55, 0.2, 0.85), "dir": Vector2(0, -1),
				"speed": [8.0, 22.0], "gravity": Vector2(0, -22), "size": [0.4, 0.9], "shape": "dot"}
		Element.Type.DARK:
			return {"amount": 30, "life": 7.0, "colour": Color(0.62, 0.38, 0.95, 0.4), "dir": Vector2(0, -1),
				"speed": [2.0, 8.0], "gravity": Vector2(0, -5), "size": [1.4, 2.8], "shape": "dot"}
	return {}


func set_weather(land: int, rect: Rect2) -> void:
	"""The floor's weather over `rect` (none for a land with none)."""
	set_weathers([land], rect)


func set_weathers(lands: Array, rect: Rect2) -> void:
	"""Each land's weather over `rect`, thinned when two mix (0.127.0: a
	room may mix a second land's in). The old ones go first."""
	var same: bool = lands == _weather_lands and not _weathers.is_empty()
	for w in _weathers:
		same = same and is_instance_valid(w)
	if same:
		return
	for w in _weathers:
		if is_instance_valid(w):
			# Out of the tree now, so the next takes the name "weather".
			if (w as Node).get_parent() == self:
				remove_child(w)
			(w as Node).queue_free()
	_weathers = []
	_weather_lands = lands.duplicate()
	for k in lands.size():
		var parts: CPUParticles2D = _make_weather(int(lands[k]), rect, MIX_THIN if lands.size() > 1 else 1.0)
		if parts == null:
			continue
		parts.name = "weather" if _weathers.is_empty() else "weather%d" % (_weathers.size() + 1)
		add_child(parts)
		parts.reset_physics_interpolation()
		# Kept, so the next room's takes its place (0.126.1: it was never kept,
		# and every floor's weather piled on the last).
		_weathers.append(parts)


func _make_weather(land: int, rect: Rect2, share: float) -> CPUParticles2D:
	var w: Dictionary = weather_for(land)
	if w.is_empty():
		return null
	var parts := CPUParticles2D.new()
	parts.z_index = WEATHER_Z
	parts.position = rect.get_center()
	parts.amount = maxi(4, roundi(float(w["amount"]) * share))
	parts.lifetime = float(w["life"])
	parts.preprocess = float(w["life"])
	parts.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	parts.emission_rect_extents = rect.size / 2.0
	parts.direction = w["dir"]
	parts.spread = 12.0
	parts.initial_velocity_min = float(w["speed"][0])
	parts.initial_velocity_max = float(w["speed"][1])
	parts.gravity = w["gravity"]
	parts.scale_amount_min = float(w["size"][0])
	parts.scale_amount_max = float(w["size"][1])
	parts.color = w["colour"]
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.2, Color(1, 1, 1, 1))
	fade.add_point(0.8, Color(1, 1, 1, 1))
	parts.color_ramp = fade
	parts.texture = _speck(str(w["shape"]))
	if str(w["shape"]) == "streak":
		parts.particle_flag_align_y = true
	var adding := CanvasItemMaterial.new()
	adding.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	parts.material = adding
	return parts


static func _speck(shape: String) -> ImageTexture:
	"""A speck drawn in code: a soft dot, a ring (a bubble), or a thin
	streak along its flight."""
	var size := Vector2i(2, 12) if shape == "streak" else Vector2i(6, 6)
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var middle := Vector2(size) / 2.0 - Vector2(0.5, 0.5)
	for y in size.y:
		for x in size.x:
			var a: float
			if shape == "streak":
				a = 1.0 - absf(float(y) - middle.y) / (float(size.y) / 2.0)
			else:
				var d: float = Vector2(x, y).distance_to(middle) / 3.0
				a = clampf(1.0 - d, 0.0, 1.0) if shape == "dot" else (1.0 if d > 0.55 and d < 1.0 else 0.0)
			image.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(image)



# =============================================================================
# THE FLOOR ITSELF (0.127.0)
# =============================================================================

static func env_gap(floor_index: int) -> float:
	return maxf(ENV_GAP_LEAST, ENV_GAP_FIRST - ENV_GAP_STEP * float(floor_index))


static func env_hit(floor_index: int) -> int:
	return ENV_HIT_FIRST + ENV_HIT_STEP * floor_index


static func env_count(floor_index: int) -> int:
	"""How many hazards each gap: one, one more every three floors."""
	return 1 + floori(float(floor_index) / 3.0)


func begin_env(lands: Array, floor_index: int, faster: bool = false) -> void:
	"""The floor's own hazards for this room, from `lands`' kinds."""
	env_lands = []
	for land in lands:
		if KIND_FOR.has(int(land)):
			env_lands.append(int(land))
	env_floor = floor_index
	env_every = env_gap(floor_index) * (0.5 if faster else 1.0)
	hazards = []
	_env_left = ENV_FIRST if not env_lands.is_empty() else -1.0
	if _air == null or not is_instance_valid(_air):
		_air = Node2D.new()
		_air.name = "air"
		_air.z_index = AIR_Z
		# Sparks, flares, wisps and blasts glow: not darkened with the room
		# (0.128.0 - an explosion in the Dark Below read as a grey disc).
		_air.material = RangeRingScript.unshaded()
		_air.draw.connect(_draw_air)
		add_child(_air)


func _step_env(delta: float) -> void:
	if env_lands.is_empty() and hazards.is_empty():
		return
	var me: Node2D = run.call("_player") as Node2D if run != null else null
	_touch_left -= delta
	if not env_lands.is_empty():
		_env_left -= delta
		if _env_left <= 0.0 and me != null:
			_env_left = env_every
			for i in env_count(env_floor):
				spawn_env(str(KIND_FOR[env_lands[randi() % env_lands.size()]]), me)
			if env_floor >= GAS_FROM and randf() < GAS_CHANCE:
				spawn_env("gas", me)
	var still: Array = []
	_born = []
	for hz in hazards:
		if _step_hazard(hz, delta, me):
			still.append(hz)
	hazards = still
	_react(me)
	hazards.append_array(_born)
	_born = []
	queue_redraw()
	if _air != null and is_instance_valid(_air):
		_air.queue_redraw()


func spawn_env(kind: String, me: Node2D) -> Dictionary:
	"""One hazard of `kind`, placed for this game's player."""
	var rect: Rect2 = run.get("room_rect") if run != null else Rect2(0, 0, 640, 360)
	var at: Vector2 = me.global_position
	var hz: Dictionary = {"k": kind, "t": 0.0, "w": 0.0, "life": 8.0, "r": 8.0, "p": at, "v": Vector2.ZERO,
		"done": false, "tick": 0.0}
	match kind:
		"spark":
			hz["p"] = Vector2(randf_range(rect.position.x + 10.0, rect.end.x - 10.0), rect.position.y + 6.0)
			hz["v"] = Vector2(randf_range(-25.0, 25.0), randf_range(35.0, 55.0))
			hz["r"] = 7.0
		"bubble":
			hz["p"] = Vector2(randf_range(rect.position.x + 10.0, rect.end.x - 10.0), rect.end.y - 8.0)
			hz["v"] = Vector2(0.0, -randf_range(22.0, 38.0))
			hz["life"] = 10.0
			hz["r"] = 9.0
		"wisp":
			hz["p"] = run.call("_edge_spot") if run != null and run.has_method("_edge_spot") else rect.position
			hz["life"] = 9.0
			hz["speed"] = 32.0 + 3.0 * float(env_floor)
		"hail":
			hz["p"] = _near(at, 60.0, rect)
			hz["w"] = 0.9
			hz["life"] = 1.15
			hz["r"] = 20.0
		"flare":
			hz["p"] = _near(at, 80.0, rect)
			hz["w"] = 1.0
			hz["life"] = 1.3
			hz["r"] = 60.0
		"rock":
			hz["p"] = _near(at, 50.0, rect)
			hz["w"] = 1.1
			hz["life"] = 1.4
			hz["r"] = 20.0
		"gust":
			hz["p"] = Vector2(rect.get_center().x, clampf(at.y + randf_range(-30.0, 30.0), rect.position.y + 20.0, rect.end.y - 20.0))
			hz["dir"] = 1.0 if randf() < 0.5 else -1.0
			hz["h"] = 40.0
			hz["w"] = 1.0
			hz["life"] = 1.35
		"gas":
			hz["p"] = _near(at, 120.0, rect)
			hz["v"] = Vector2.from_angle(randf() * TAU) * 8.0
			hz["w"] = 1.2
			hz["life"] = 7.2
			hz["r"] = 46.0
	hazards.append(hz)
	env_made += 1
	return hz


func _near(at: Vector2, reach: float, rect: Rect2) -> Vector2:
	var spot: Vector2 = at + Vector2.from_angle(randf() * TAU) * randf_range(0.0, reach)
	var inner: Rect2 = rect.grow(-12.0)
	return Vector2(clampf(spot.x, inner.position.x, inner.end.x), clampf(spot.y, inner.position.y, inner.end.y))


func _step_hazard(hz: Dictionary, delta: float, me: Node2D) -> bool:
	"""One hazard's moment; false when it is over."""
	hz["t"] = float(hz["t"]) + delta
	hz["just"] = false
	var t: float = float(hz["t"])
	var kind: String = str(hz["k"])
	if t >= float(hz["life"]) or bool(hz["done"]):
		return false
	var hit: int = env_hit(env_floor)
	match kind:
		"spark", "bubble":
			var p: Vector2 = hz["p"]
			p += (hz["v"] as Vector2) * delta
			if kind == "bubble":
				p.x += sin(t * 3.0 + p.y * 0.05) * 12.0 * delta
			hz["p"] = p
			if me != null and _touches(me, p, float(hz["r"])):
				var effect: StringName = StatusEffects.BURN if kind == "spark" else StatusEffects.SOAKED
				_env_hit(me, hit, Element.Type.FIRE if kind == "spark" else Element.Type.WATER, effect, p)
				hz["done"] = true
				# A BUBBLE POPPED LEAVES A PUDDLE (0.128.0).
				if kind == "bubble":
					_born.append(_patch("puddle", p))
		"wisp":
			if me != null:
				var p: Vector2 = hz["p"]
				p = p.move_toward(me.global_position, float(hz["speed"]) * delta)
				hz["p"] = p
				if _touches(me, p, float(hz["r"])):
					_env_hit(me, hit, Element.Type.DARK, StatusEffects.WITHER, p)
					hz["done"] = true
		"hail", "rock", "flare":
			if t >= float(hz["w"]) and not bool(hz.get("landed", false)):
				hz["landed"] = true
				hz["just"] = true
				var p: Vector2 = hz["p"]
				if me != null and _touches(me, p, float(hz["r"])):
					match kind:
						"hail":
							_env_hit(me, hit, Element.Type.ICE, StatusEffects.CHILL, p)
						"rock":
							_env_hit(me, hit * 2, Element.Type.EARTH, StatusEffects.ROOT, p)
						"flare":
							_env_hit(me, hit, Element.Type.LIGHT, StatusEffects.DAZZLE, p)
		"gust":
			if t >= float(hz["w"]) and not bool(hz.get("fired", false)):
				hz["fired"] = true
				hz["just"] = true
			if t >= float(hz["w"]) and not bool(hz.get("landed", false)) and me != null:
				var lane: float = float(hz["h"]) / 2.0
				if absf(me.global_position.y - (hz["p"] as Vector2).y) <= lane:
					hz["landed"] = true
					var from: Vector2 = me.global_position - Vector2(30.0 * float(hz["dir"]), 0.0)
					_env_hit(me, hit, Element.Type.WIND, StatusEffects.SHOVE, from)
		"gas":
			hz["p"] = (hz["p"] as Vector2) + (hz["v"] as Vector2) * delta
			if t >= float(hz["w"]) and me != null and _touches(me, hz["p"], float(hz["r"])):
				hz["tick"] = float(hz["tick"]) - delta
				if float(hz["tick"]) <= 0.0:
					hz["tick"] = GAS_TICK
					me.call("take_damage", maxi(1, roundi(float(hit) * 0.5)), Element.Type.POISON)
					env_hits += 1
		"puddle", "ice":
			if t >= float(hz["w"]) and me != null and _touches(me, hz["p"], float(hz["r"])):
				if kind == "puddle":
					_env_hit(me, maxi(1, hit / 2), Element.Type.WATER, StatusEffects.SOAKED, hz["p"])
				else:
					_env_hit(me, maxi(1, hit / 2), Element.Type.ICE, StatusEffects.CHILL, hz["p"])
	return true


func _patch(kind: String, at: Vector2) -> Dictionary:
	"""A puddle, ice, a blast or a puff of steam where a reaction left it."""
	var hz: Dictionary = {"k": kind, "t": 0.0, "w": 0.0, "life": 0.5, "r": PUDDLE_R, "p": at, "v": Vector2.ZERO,
		"done": false, "tick": 0.0}
	match kind:
		"puddle":
			hz["w"] = PUDDLE_WARN
			hz["life"] = PUDDLE_LIFE
		"ice":
			hz["life"] = ICE_LIFE
		"blast":
			hz["life"] = 0.4
	reactions[kind] = int(reactions.get(kind, 0)) + 1
	return hz


func _react(me: Node2D) -> void:
	"""AND THEY REACT (0.128.0): what one hazard does to another this step."""
	var hit: int = env_hit(env_floor)
	for hz in hazards:
		if bool(hz["done"]):
			continue
		var kind: String = str(hz["k"])
		var p: Vector2 = hz["p"]
		if kind == "spark":
			for other in hazards:
				if bool(other["done"]) or is_same(other, hz):
					continue
				var near: float = p.distance_to(other["p"])
				match str(other["k"]):
					"gas":
						# THE CLOUD EXPLODES.
						if float(other["t"]) >= float(other["w"]) and near <= float(other["r"]):
							other["done"] = true
							hz["done"] = true
							var blast: Dictionary = _patch("blast", other["p"])
							blast["r"] = float(other["r"]) + BLAST_PAST
							_born.append(blast)
							if me != null and _touches(me, other["p"], float(blast["r"])):
								_touch_left = 0.0
								_env_hit(me, hit * 2, Element.Type.FIRE, StatusEffects.BURN, other["p"])
					"hail":
						# MELTED BEFORE IT LANDS.
						if not bool(other.get("landed", false)) and near <= float(other["r"]):
							other["done"] = true
							hz["done"] = true
							_born.append(_patch("puddle", other["p"]))
					"bubble", "puddle":
						# PUT OUT.
						if near <= float(other["r"]):
							hz["done"] = true
							_born.append(_patch("steam", p))
				if bool(hz["done"]):
					break
		elif bool(hz.get("just", false)):
			match kind:
				"flare":
					# THE LIGHT RUNS THROUGH THE PUDDLES.
					for other in hazards:
						if str(other["k"]) == "puddle" and not bool(other["done"]) \
								and p.distance_to(other["p"]) <= float(hz["r"]) * SHOCK_REACH:
							other["shock"] = float(other["t"])
							reactions["shock"] = int(reactions.get("shock", 0)) + 1
							if me != null and _touches(me, other["p"], float(other["r"])):
								_touch_left = 0.0
								_env_hit(me, roundi(float(hit) * 1.5), Element.Type.LIGHT, StatusEffects.DAZZLE, other["p"])
				"hail":
					# FROZEN TO ICE.
					for other in hazards:
						if str(other["k"]) == "puddle" and not bool(other["done"]) \
								and p.distance_to(other["p"]) <= FREEZE_REACH + float(other["r"]):
							other["done"] = true
							_born.append(_patch("ice", other["p"]))
				"gust":
					# BLOWN ALONG THE LANE - held in the room.
					var lane: float = float(hz["h"]) / 2.0
					var rect: Rect2 = (run.get("room_rect") if run != null else Rect2(0, 0, 640, 360)).grow(-12.0)
					for other in hazards:
						if str(other["k"]) in ["spark", "bubble", "wisp", "gas"] and not bool(other["done"]) \
								and absf((other["p"] as Vector2).y - p.y) <= lane:
							var to: Vector2 = (other["p"] as Vector2) + Vector2(GUST_PUSH * float(hz["dir"]), 0.0)
							other["p"] = Vector2(clampf(to.x, rect.position.x, rect.end.x), to.y)
							reactions["blown"] = int(reactions.get("blown", 0)) + 1


func _touches(me: Node2D, at: Vector2, radius: float) -> bool:
	return me.global_position.distance_to(at) <= radius + TOUCH_SLACK


func _env_hit(me: Node2D, amount: int, element: int, effect: StringName, from: Vector2) -> void:
	"""A hazard lands on this game's player - at most every TOUCH_GAP."""
	if _touch_left > 0.0 or not me.has_method("take_damage"):
		return
	_touch_left = TOUCH_GAP
	me.call("take_damage", amount, element)
	StatusEffects.apply_to(me, effect, amount, from, false, 1.0)
	env_hits += 1


func _draw_floor_hazards() -> void:
	for hz in hazards:
		var t: float = float(hz["t"])
		var w: float = maxf(0.001, float(hz["w"]))
		var p: Vector2 = hz["p"]
		var kind: String = str(hz["k"])
		var grow: float = clampf(t / w, 0.0, 1.0)
		match kind:
			"hail", "rock":
				var colour := Color(0.85, 0.95, 1.0) if kind == "hail" else Color(0.55, 0.42, 0.3)
				if not bool(hz.get("landed", false)):
					draw_set_transform(p, 0.0, Vector2(1.0, 0.55))
					draw_circle(Vector2.ZERO, float(hz["r"]) * grow, Color(0.0, 0.0, 0.0, 0.25 + 0.3 * grow))
					draw_arc(Vector2.ZERO, float(hz["r"]), 0.0, TAU, 24, Color(colour, 0.7), 1.5)
				else:
					var after: float = clampf((t - w) / 0.3, 0.0, 1.0)
					draw_set_transform(p, 0.0, Vector2(1.0, 0.55))
					draw_arc(Vector2.ZERO, float(hz["r"]) * (1.0 + after), 0.0, TAU, 24, Color(colour * 1.5, 1.0 - after), 3.0)
			"flare":
				draw_set_transform(p, 0.0, Vector2(1.0, 0.6))
				draw_arc(Vector2.ZERO, float(hz["r"]), 0.0, TAU, 32, Color(1.0, 0.9, 0.5, 0.35 + 0.4 * grow), 1.5)
			"gust":
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				var rect: Rect2 = run.get("room_rect") if run != null else Rect2(0, 0, 640, 360)
				var lane := Rect2(rect.position.x, p.y - float(hz["h"]) / 2.0, rect.size.x, float(hz["h"]))
				var live: bool = t >= w
				draw_rect(lane, Color(0.85, 1.0, 0.9, 0.08 + 0.12 * grow if not live else 0.3))
				for k in 7:
					var x: float = lane.position.x + fmod(float(k) * 97.0 + t * 260.0 * float(hz["dir"]), lane.size.x)
					if x < lane.position.x:
						x += lane.size.x
					var y: float = lane.position.y + float(k * 6 % int(maxf(1.0, lane.size.y)))
					draw_line(Vector2(x, y), Vector2(x + 18.0 * float(hz["dir"]), y), Color(0.9, 1.0, 0.95, 0.25 + 0.5 * grow), 1.0)
			"puddle", "ice":
				var fade: float = clampf((float(hz["life"]) - t) / 0.6, 0.0, 1.0)
				var colour := Color(0.35, 0.6, 1.0, 0.35) if kind == "puddle" else Color(0.8, 0.95, 1.0, 0.5)
				if kind == "puddle" and t < w:
					colour.a *= grow
				if hz.has("shock") and t - float(hz["shock"]) < 0.35:
					colour = Color(1.0, 0.95, 0.5, 0.75)
				draw_set_transform(p, 0.0, Vector2(1.0, 0.55))
				draw_circle(Vector2.ZERO, float(hz["r"]), Color(colour, colour.a * fade))
				draw_arc(Vector2.ZERO, float(hz["r"]), 0.0, TAU, 20, Color(colour * 1.4, 0.6 * fade), 1.0)
				if kind == "ice":
					var shine := Color(1.0, 1.0, 1.0, 0.7 * fade)
					draw_line(Vector2(-8, -5), Vector2(-2, -9), shine, 1.0)
					draw_line(Vector2(2, 4), Vector2(9, -1), shine, 1.0)
			"gas":
				var alpha: float = (0.12 + 0.1 * sin(t * 4.0)) if t >= w else 0.08 * grow
				for k in 5:
					var off := Vector2.from_angle(float(k) * 1.26 + t * 0.4) * float(hz["r"]) * 0.45
					draw_set_transform(p + off, 0.0, Vector2(1.0, 0.7))
					draw_circle(Vector2.ZERO, float(hz["r"]) * 0.6, Color(0.35, 0.85, 0.25, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_air() -> void:
	for hz in hazards:
		var p: Vector2 = hz["p"]
		var t: float = float(hz["t"])
		match str(hz["k"]):
			"spark":
				_air.draw_circle(p, 6.0, Color(1.0, 0.5, 0.15, 0.25))
				_air.draw_circle(p, 3.0, Color(1.0, 0.8, 0.4, 0.95))
			"bubble":
				_air.draw_arc(p, float(hz["r"]), 0.0, TAU, 20, Color(0.6, 0.85, 1.0, 0.85), 1.5)
				_air.draw_circle(p + Vector2(-3, -3), 1.5, Color(1, 1, 1, 0.8))
			"wisp":
				_air.draw_circle(p, 9.0, Color(0.55, 0.3, 0.95, 0.25))
				_air.draw_circle(p, 4.0, Color(0.8, 0.6, 1.0, 0.9))
			"blast":
				# Over everything, as the flare's flash is (0.128.0).
				var b: float = clampf(t / float(hz["life"]), 0.0, 1.0)
				var reach: float = float(hz["r"])
				_air.draw_set_transform(p, 0.0, Vector2(1.0, 0.6))
				_air.draw_circle(Vector2.ZERO, reach * (0.5 + 0.5 * b), Color(1.0, 0.45, 0.1, 0.55 * (1.0 - b)))
				_air.draw_circle(Vector2.ZERO, reach * (0.25 + 0.3 * b), Color(1.0, 0.9, 0.55, 0.85 * (1.0 - b)))
				for k in 10:
					var ray := Vector2.from_angle(float(k) * TAU / 10.0 + 0.3)
					_air.draw_line(ray * reach * (0.3 + 0.5 * b), ray * reach * (0.55 + 0.6 * b), Color(1.0, 0.8, 0.35, 1.0 - b), 2.0)
				_air.draw_arc(Vector2.ZERO, reach * (0.6 + 0.6 * b), 0.0, TAU, 28, Color(1.0, 0.85, 0.4, 1.0 - b), 3.0)
				_air.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"steam":
				var rise: float = clampf(t / float(hz["life"]), 0.0, 1.0)
				for k in 3:
					_air.draw_circle(p + Vector2(float(k - 1) * 5.0, -14.0 * rise - float(k) * 3.0), 4.0 + 3.0 * rise,
						Color(0.95, 0.95, 1.0, 0.45 * (1.0 - rise)))
			"flare":
				var w: float = maxf(0.001, float(hz["w"]))
				if t < w:
					_air.draw_circle(p, 3.0 + 10.0 * (t / w), Color(1.0, 0.95, 0.6, 0.4 + 0.5 * (t / w)))
				else:
					var after: float = clampf((t - w) / 0.3, 0.0, 1.0)
					_air.draw_circle(p, float(hz["r"]) * (0.6 + 0.4 * after), Color(1.0, 1.0, 0.85, 0.7 * (1.0 - after)))
