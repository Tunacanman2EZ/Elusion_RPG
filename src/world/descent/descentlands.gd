extends Node2D
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

var run: Node = null
var phase: int = 0
var every: float = GAP_FIRST
var _casters: Array = []
var _left: float = -1.0
var _turn: int = 0
# [origin, seconds left, caster, volley name, aim, reach, colour]
var _warns: Array = []
var _weather: CPUParticles2D = null
var _weather_land: int = -1
var thrown: int = 0


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
	"""No hazards: the casters freed, the marks gone."""
	for caster in _casters:
		if is_instance_valid(caster):
			(caster as Node).queue_free()
	_casters = []
	_warns = []
	_left = -1.0
	queue_redraw()


func active() -> bool:
	return not _casters.is_empty()


func step(delta: float) -> void:
	"""The run's FIGHT, after the pack has come: count down, mark, throw."""
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
	if land == _weather_land and _weather != null and is_instance_valid(_weather):
		return
	if _weather != null and is_instance_valid(_weather):
		_weather.queue_free()
	_weather = null
	_weather_land = land
	var w: Dictionary = weather_for(land)
	if w.is_empty():
		return
	var parts := CPUParticles2D.new()
	parts.name = "weather"
	parts.z_index = WEATHER_Z
	parts.position = rect.get_center()
	parts.amount = int(w["amount"])
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
	add_child(parts)
	parts.reset_physics_interpolation()


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
