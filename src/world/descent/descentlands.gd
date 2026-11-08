extends Node2D

const StatusEffects := preload("res://src/characters/statuseffects.gd")
const RangeRingScript := preload("res://src/shared/rangering.gd")
const Boons := preload("res://src/world/descent/descentboons.gd")
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
# Each hits for env_amount() (a share of your health, more each floor), and
# at most every TOUCH_GAP.
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
# LOUDER (0.129.0) - the owner: "i didnt really see lasers or much going on
# we need to amplify effects and eviromental damages". Sooner, more often,
# more at once (env_count()), bigger; and each hit is a share of your health
# (env_share(): ENV_SHARE_FIRST, ENV_SHARE_STEP more a floor, at most
# ENV_SHARE_MOST), landed as it is - past armour and the ward
# (descentboons.gd exact_once) - so it hurts whatever you wear.
const ENV_FIRST := 2.0
const ENV_GAP_FIRST := 3.0
const ENV_GAP_STEP := 0.25
const ENV_GAP_LEAST := 1.2
const ENV_SHARE_FIRST := 0.06
const ENV_SHARE_STEP := 0.01
const ENV_SHARE_MOST := 0.2
const TOUCH_GAP := 0.6
const TOUCH_SLACK := 8.0
const GAS_FROM := 2
const GAS_CHANCE := 0.35
const GAS_TICK := 0.5
# A breath of gas at this share of a hazard's hit.
const GAS_TIMES := 0.35
const AIR_Z := 7
# LASERS (0.129.0) - the owner: "we can add lasers", "i didnt really see
# lasers". A beam across the room through a spot near you, in a land's
# colour: a thin flickering line for LASER_WARN, then LASER_FIRE of beam,
# LASER_HALF each side of its line, hitting for LASER_HIT of a hazard with
# the land's effect. Each gap at laser_chance(); from LASER_SPIN_FROM it
# turns as it burns (LASER_SPIN a second, LASER_FIRE_SPIN long), from
# LASER_TWO_FROM two cross.
const LASER_WARN := 1.0
const LASER_FIRE := 0.5
const LASER_FIRE_SPIN := 1.3
const LASER_HALF := 7.0
const LASER_HIT := 1.5
const LASER_CHANCE_FIRST := 0.45
const LASER_CHANCE_STEP := 0.08
const LASER_SPIN_FROM := 3
const LASER_SPIN := 0.55
const LASER_TWO_FROM := 4
# THEY BEND AND CARRY THEIR LAND (0.134.1) - the owner, of the crossing
# lasers: "the x lasers are cool but i need them to bend and carry effects
# with them", choosing "curve and whip":
#   - A BEAM IS AN ARC (beam_points()): through its spot, leaving it along
#     its angle, bent so its ends lie up to LASER_BEND of its half-length off
#     its straight line (a long beam bends as far as a short one, for its
#     size, and never curls) - and the bend sways from one side to the other
#     and back every LASER_WHIP_SECONDS, while it warns and while it burns.
#     The two of an X sway opposite ways. It meets the room's walls at both
#     ends.
#   - ITS LAND RIDES ALONG IT (motes()): while it warns, LASER_MOTES embers,
#     frost, drops, gusts, sparks, grit or shadow run out along it from its
#     spot, so you see which land is coming.
#   - EACH LAND FIRES ITS OWN BEAM (_draw_design(); the owner chose these
#     from a sheet of ideas, "amazing"): light forked lightning that crackles
#     (redrawn every LIGHTNING_FLICKER), fire a braided flame with licks,
#     ice a cracked crystal with shards, water a rolling wave with foam and
#     bubbles, wind gale threads with curls and leaves, earth a fault line
#     throwing up rocks, dark a void tendril that writhes, with eyes. All drawn
#     in code along the same bent line; what it hits is the same.
#   - AND IT LEAVES ITS LAND WHERE IT BURNED (_leave_trail()): as it fades,
#     along its last shape within LASER_TRAIL_REACH of its spot, every
#     LASER_TRAIL_STEP (light every other one) - fire a SCORCH (burns while
#     you stand in it), ice ICE, water a PUDDLE, light a FLARE that flashes,
#     earth RUBBLE (roots, once), dark a SHADE (withers, once). Each grows in
#     over LASER_TRAIL_WARN, so you can step off. Wind leaves nothing: it
#     blows what floats near it along the beam, and its hit carries you along
#     it. They react as the rest do: a scorch is put out by a puddle (steam),
#     explodes gas, melts hail; a flare runs through puddles.
#   - WHERE AN X CROSSES (its spot) the two flash in both lands' colours as
#     they fire, and their trails meet there - fire over water is steam.
const LASER_BEND := 0.25
const LASER_WHIP_SECONDS := 2.2
const LASER_STEP := 12.0
const LASER_MOTES := 16
const LASER_MOTE_SPEED := 0.35
const LASER_MOTE_SWAY := 13.0
const LIGHTNING_FLICKER := 0.07
# METEORS (0.134.1, the Crowned's second phase, crownedphases.gd): a fireball
# where a player stands, a warning circle first (METEOR_WARN), METEOR_TIMES
# of a hazard as fire with a burn, and a scorch left where it struck.
const METEOR_WARN := 1.3
const METEOR_R := 38.0
const METEOR_TIMES := 1.6
# FALSE WARNINGS (0.134.1, the Crowned's lying room): with false_share above
# 0, that share of what warns before it falls (FAKEABLE) is an illusion - its
# circle shimmers, it hits nobody, starts no reaction, and breaks into violet
# light where it lands. The tell is the shimmer.
const FAKEABLE := ["hail", "rock", "flare", "meteor"]
const LASER_TRAIL_REACH := 150.0
const LASER_TRAIL_STEP := 50.0
const LASER_TRAIL_R := 15.0
const LASER_TRAIL_WARN := 0.4
# The last of a beam's burn this long before it is gone is when it leaves its land.
const LASER_TRAIL_BEFORE := 0.2
const SCORCH_LIFE := 3.0
const RUBBLE_LIFE := 4.0
const SHADE_LIFE := 3.5
# What each land's laser leaves where it burned ("" - nothing: wind blows).
const TRAIL_FOR := {Element.Type.FIRE: "scorch", Element.Type.ICE: "ice", Element.Type.WATER: "puddle",
	Element.Type.WIND: "", Element.Type.LIGHT: "flare", Element.Type.EARTH: "rubble", Element.Type.DARK: "shade"}
# Each land's effect, for a laser.
const EFFECT_FOR := {Element.Type.FIRE: &"burn", Element.Type.ICE: &"chill", Element.Type.WATER: &"soaked",
	Element.Type.WIND: &"shove", Element.Type.LIGHT: &"dazzle", Element.Type.EARTH: &"root", Element.Type.DARK: &"wither"}
# AND THEY REACT (0.128.0): a puddle and ice, how long and how wide; how far a
# flare's light runs through puddles; how far a hail freezes one; how far a
# gust blows what is in its lane; an explosion's reach past the cloud.
const PUDDLE_LIFE := 4.0
const PUDDLE_WARN := 0.5
const PUDDLE_R := 24.0
const ICE_LIFE := 5.0
const SHOCK_REACH := 1.5
const FREEZE_REACH := 24.0
const GUST_PUSH := 120.0
# WIND PUSHES HARDER, AND THINGS COME IN TURN (0.134.2). The owner, watching
# the Crowned: "wind needs a stronger push at wind drifts and it needs to fire
# at a separate time then the lasers the thing is sequences so that way things
# feel not everything is happening at 1 time".
#   - A gust (and a wind laser) shoves GUST_SHOVE times as hard as any other
#     shove (StatusEffects.push_harder()), and blows what floats GUST_PUSH.
#   - A wave of the floor's hazards no longer lands at once: each comes
#     ENV_STAGGER after the last (_queue), and the wave's laser comes
#     LASER_LATER of the gap after it, so it fires between the waves.
const GUST_SHOVE := 2.5
const ENV_STAGGER := 0.3
const LASER_LATER := 0.5
# NEW SHAPES OF LASER (0.134.2, the owner's "lets check it out" of a list of
# ideas): spawned by whoever runs the fight (crownedphases.gd's Trap):
#   - pinwheel(): PINWHEEL_ARMS beams through one spot, turning together.
#   - sweep(): one straight beam crossing the whole room, wall to wall, at
#     SWEEP_SPEED.
#   - cage(): four straight beams round the player, closing in at CAGE_SPEED
#     from CAGE_REACH and stopping CAGE_STOP short - stay in the middle.
#   - pulse_beam(): a beam that fires to a beat, PULSE_ON on and PULSE_OFF
#     off, PULSES times - it hurts only while on; dodge by timing.
#   - and where an X crosses it bursts (X_BLAST_R, X_BLAST_TIMES of a hazard
#     in the crossing land) as it fires - the crossing is the danger spot.
#   - A turning or moving beam shows faint ghosts of where it will sweep
#     while it warns (GHOSTS), so its path can be read.
const PINWHEEL_ARMS := 3
const SWEEP_SPEED := 170.0
const CAGE_REACH := 250.0
const CAGE_STOP := 70.0
const CAGE_SPEED := 120.0
const PULSE_ON := 0.35
const PULSE_OFF := 0.3
const PULSES := 5
const X_BLAST_R := 34.0
const X_BLAST_TIMES := 1.0
const GHOSTS := 3
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
# What the floor has yet to send this wave: [seconds until, kind].
var _queue: Array = []
# What share of FAKEABLE hazards are illusions (0: none - the Descent).
var false_share: float = 0.0
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
	_queue = []
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


static func env_share(floor_index: int) -> float:
	"""A hazard's share of your most health on this floor (0.129.0)."""
	return minf(ENV_SHARE_MOST, ENV_SHARE_FIRST + ENV_SHARE_STEP * float(floor_index))


static func env_amount(floor_index: int, most_health: int, times: float = 1.0) -> int:
	"""What a hazard `times` as hard takes from `most_health`."""
	return maxi(1, roundi(float(most_health) * env_share(floor_index) * times))


static func env_count(floor_index: int) -> int:
	"""How many hazards each gap: one, one more every two floors (two from
	floor 3)."""
	return 1 + floori(float(floor_index) / 2.0)


static func laser_chance(floor_index: int) -> float:
	return minf(1.0, LASER_CHANCE_FIRST + LASER_CHANCE_STEP * float(floor_index))


func begin_env(lands: Array, floor_index: int, faster: bool = false) -> void:
	"""The floor's own hazards for this room, from `lands`' kinds."""
	env_lands = []
	for land in lands:
		if KIND_FOR.has(int(land)):
			env_lands.append(int(land))
	env_floor = floor_index
	env_every = env_gap(floor_index) * (0.5 if faster else 1.0)
	hazards = []
	_queue = []
	_env_left = ENV_FIRST if not env_lands.is_empty() else -1.0
	_ensure_air()


func _ensure_air() -> void:
	"""The layer above everything that what flies is drawn on - made with the
	first floor's hazards, or the first hazard spawned without one (0.134.2:
	the Crowned's meteors and lasers below three quarters, in a fight joined
	after its crowns, were drawn nowhere)."""
	if _air == null or not is_instance_valid(_air):
		_air = Node2D.new()
		_air.name = "air"
		_air.z_index = AIR_Z
		# Sparks, flares, wisps and blasts glow: not darkened with the room
		# (0.128.0 - an explosion in the Dark Below read as a grey disc).
		_air.material = RangeRingScript.unshaded()
		# And what lies on the floor glows too (0.129.0): "i didnt really see
		# ... much going on".
		material = RangeRingScript.unshaded()
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
			var kinds: Array = []
			for i in env_count(env_floor):
				kinds.append(str(KIND_FOR[env_lands[randi() % env_lands.size()]]))
			if env_floor >= GAS_FROM and randf() < GAS_CHANCE:
				kinds.append("gas")
			for k in kinds.size():
				_queue.append([float(k) * ENV_STAGGER, kinds[k]])
			if randf() < laser_chance(env_floor):
				_queue.append([env_every * LASER_LATER, "laser"])
	var still: Array = []
	_born = []
	for hz in hazards:
		if _step_hazard(hz, delta, me):
			still.append(hz)
	hazards = still
	_react(me)
	hazards.append_array(_born)
	_born = []
	_send_queued(delta, me)
	queue_redraw()
	if _air != null and is_instance_valid(_air):
		_air.queue_redraw()


func _send_queued(delta: float, me: Node2D) -> void:
	"""The wave's hazards, each when its turn comes (ENV_STAGGER, LASER_LATER)."""
	if _queue.is_empty() or me == null:
		return
	var later: Array = []
	for item in _queue:
		item[0] = float(item[0]) - delta
		if float(item[0]) > 0.0:
			later.append(item)
			continue
		var kind: String = str(item[1])
		if kind == "laser":
			var beam: Dictionary = spawn_env("laser", me)
			if env_floor >= LASER_TWO_FROM:
				_cross(beam, spawn_env("laser", me))
		else:
			spawn_env(kind, me)
	_queue = later


func _cross(beam: Dictionary, cross: Dictionary) -> void:
	"""Make `cross` the other half of `beam`'s X."""
	cross["a"] = float(beam["a"]) + PI / 2.0
	cross["p"] = beam["p"]
	cross["ph"] = float(beam["ph"]) + PI
	cross["x_with"] = int(beam["e"])


func cross_lasers(me: Node2D, land: int, other_land: int) -> Array:
	"""An X of lasers near this game's player, of `land` and `other_land`."""
	var beam: Dictionary = spawn_env("laser", me)
	beam["e"] = land
	var cross: Dictionary = spawn_env("laser", me)
	cross["e"] = other_land
	_cross(beam, cross)
	return [beam, cross]


func spawn_env(kind: String, me: Node2D) -> Dictionary:
	"""One hazard of `kind`, placed for this game's player."""
	_ensure_air()
	var rect: Rect2 = run.get("room_rect") if run != null else Rect2(0, 0, 640, 360)
	var at: Vector2 = me.global_position
	var hz: Dictionary = {"k": kind, "t": 0.0, "w": 0.0, "life": 8.0, "r": 8.0, "p": at, "v": Vector2.ZERO,
		"done": false, "tick": 0.0}
	match kind:
		"spark":
			hz["p"] = Vector2(randf_range(rect.position.x + 10.0, rect.end.x - 10.0), rect.position.y + 6.0)
			hz["v"] = Vector2(randf_range(-25.0, 25.0), randf_range(35.0, 55.0))
			hz["r"] = 10.0
		"bubble":
			hz["p"] = Vector2(randf_range(rect.position.x + 10.0, rect.end.x - 10.0), rect.end.y - 8.0)
			hz["v"] = Vector2(0.0, -randf_range(22.0, 38.0))
			hz["life"] = 10.0
			hz["r"] = 13.0
		"wisp":
			hz["p"] = run.call("_edge_spot") if run != null and run.has_method("_edge_spot") else rect.position
			hz["life"] = 9.0
			hz["speed"] = 32.0 + 3.0 * float(env_floor)
		"hail":
			hz["p"] = _near(at, 60.0, rect)
			hz["w"] = 0.9
			hz["life"] = 1.15
			hz["r"] = 28.0
		"flare":
			hz["p"] = _near(at, 80.0, rect)
			hz["w"] = 1.0
			hz["life"] = 1.3
			hz["r"] = 80.0
		"rock":
			hz["p"] = _near(at, 50.0, rect)
			hz["w"] = 1.1
			hz["life"] = 1.4
			hz["r"] = 28.0
		"meteor":
			hz["p"] = _near(at, 24.0, rect)
			hz["w"] = METEOR_WARN
			hz["life"] = METEOR_WARN + 0.35
			hz["r"] = METEOR_R
		"gust":
			hz["p"] = Vector2(rect.get_center().x, clampf(at.y + randf_range(-30.0, 30.0), rect.position.y + 20.0, rect.end.y - 20.0))
			hz["dir"] = 1.0 if randf() < 0.5 else -1.0
			hz["h"] = 56.0
			hz["w"] = 1.0
			hz["life"] = 1.35
		"gas":
			hz["p"] = _near(at, 120.0, rect)
			hz["v"] = Vector2.from_angle(randf() * TAU) * 8.0
			hz["w"] = 1.2
			hz["life"] = 7.2
			hz["r"] = 58.0
		"laser":
			hz["p"] = _near(at, 40.0, rect)
			var turns: Array = [0.0, PI / 2.0, PI / 4.0, -PI / 4.0]
			hz["a"] = float(turns[randi() % turns.size()]) + randf_range(-0.2, 0.2)
			hz["e"] = int(env_lands[randi() % env_lands.size()]) if not env_lands.is_empty() else Element.Type.LIGHT
			hz["spin"] = (LASER_SPIN if randf() < 0.5 else -LASER_SPIN) if env_floor >= LASER_SPIN_FROM else 0.0
			hz["w"] = LASER_WARN
			hz["life"] = LASER_WARN + (LASER_FIRE_SPIN if env_floor >= LASER_SPIN_FROM else LASER_FIRE)
			hz["r"] = LASER_HALF
			hz["bend"] = LASER_BEND
			hz["ph"] = randf() * TAU
			hz["seed"] = randi()
	if kind in FAKEABLE and false_share > 0.0 and randf() < false_share:
		hz["fake"] = true
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
	match kind:
		"spark", "bubble":
			var p: Vector2 = hz["p"]
			p += (hz["v"] as Vector2) * delta
			if kind == "bubble":
				p.x += sin(t * 3.0 + p.y * 0.05) * 12.0 * delta
			hz["p"] = p
			# Out of the room, gone (0.129.0): a spark fell on through the
			# wall at the front, over it.
			var held: Rect2 = run.get("room_rect") if run != null else Rect2(0, 0, 640, 360)
			if not held.grow(6.0).has_point(p):
				return false
			if me != null and _touches(me, p, float(hz["r"])):
				var effect: StringName = StatusEffects.BURN if kind == "spark" else StatusEffects.SOAKED
				_env_hit(me, 1.0, Element.Type.FIRE if kind == "spark" else Element.Type.WATER, effect, p)
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
					_env_hit(me, 1.0, Element.Type.DARK, StatusEffects.WITHER, p)
					hz["done"] = true
		"hail", "rock", "flare", "meteor":
			if t >= float(hz["w"]) and not bool(hz.get("landed", false)):
				hz["landed"] = true
				var p: Vector2 = hz["p"]
				if bool(hz.get("fake", false)):
					# An illusion: it breaks where it lands, and that is all.
					reactions["illusion"] = int(reactions.get("illusion", 0)) + 1
					return true
				hz["just"] = true
				if kind == "meteor":
					var scorch: Dictionary = trail_patch("scorch", p)
					scorch["r"] = METEOR_R * 0.6
					scorch["w"] = 0.0
					_born.append(scorch)
				if me != null and _touches(me, p, float(hz["r"])):
					match kind:
						"meteor":
							_env_hit(me, METEOR_TIMES, Element.Type.FIRE, StatusEffects.BURN, p)
						"hail":
							_env_hit(me, 1.0, Element.Type.ICE, StatusEffects.CHILL, p)
						"rock":
							_env_hit(me, 1.5, Element.Type.EARTH, StatusEffects.ROOT, p)
						"flare":
							_env_hit(me, 1.0, Element.Type.LIGHT, StatusEffects.DAZZLE, p)
		"gust":
			if t >= float(hz["w"]) and not bool(hz.get("fired", false)):
				hz["fired"] = true
				hz["just"] = true
			if t >= float(hz["w"]) and not bool(hz.get("landed", false)) and me != null:
				var lane: float = float(hz["h"]) / 2.0
				if absf(me.global_position.y - (hz["p"] as Vector2).y) <= lane:
					hz["landed"] = true
					var from: Vector2 = me.global_position - Vector2(30.0 * float(hz["dir"]), 0.0)
					var hits_were: int = env_hits
					_env_hit(me, 1.0, Element.Type.WIND, StatusEffects.SHOVE, from)
					if env_hits > hits_were:
						StatusEffects.push_harder(me, GUST_SHOVE)
		"gas":
			hz["p"] = (hz["p"] as Vector2) + (hz["v"] as Vector2) * delta
			if t >= float(hz["w"]) and me != null and _touches(me, hz["p"], float(hz["r"])):
				hz["tick"] = float(hz["tick"]) - delta
				if float(hz["tick"]) <= 0.0:
					hz["tick"] = GAS_TICK
					Boons.exact_once = true
					me.call("take_damage", env_amount(env_floor, int(me.get("max_hp")), GAS_TIMES), Element.Type.POISON)
					Boons.exact_once = false
					env_hits += 1
		"puddle", "ice":
			if t >= float(hz["w"]) and me != null and _touches(me, hz["p"], float(hz["r"])):
				if kind == "puddle":
					_env_hit(me, 0.5, Element.Type.WATER, StatusEffects.SOAKED, hz["p"])
				else:
					_env_hit(me, 0.5, Element.Type.ICE, StatusEffects.CHILL, hz["p"])
		"laser":
			var e: int = int(hz["e"])
			if t >= float(hz["w"]):
				hz["a"] = float(hz["a"]) + float(hz["spin"]) * delta
				if hz.has("travel") and float(hz["travel"]) > 0.0:
					var move: float = minf(float(hz["travel"]), (hz["v"] as Vector2).length() * delta)
					hz["p"] = (hz["p"] as Vector2) + (hz["v"] as Vector2).normalized() * move
					hz["travel"] = float(hz["travel"]) - move
			hz["pts"] = beam_points(hz)
			if t >= float(hz["w"]):
				if not bool(hz.get("fired", false)):
					hz["fired"] = true
					hz["just"] = true
					if hz.has("x_with"):
						_cross_flash(hz, me)
					if e == Element.Type.WIND:
						_blow_along(hz)
				# One beam, one hit: a turning beam across a player stood still
				# hit twice in its 1.3 s (the bench, zz/descparty4.gd).
				if me != null and not bool(hz.get("landed", false)) and beam_on(hz):
					var near: Vector2 = closest_on_beam(hz, me.global_position)
					if me.global_position.distance_to(near) <= LASER_HALF + TOUCH_SLACK and _touch_left <= 0.0:
						hz["landed"] = true
						# Wind's carries you ALONG the beam, not off it.
						var from: Vector2 = near
						if e == Element.Type.WIND:
							from = me.global_position - beam_heading(hz, near) * 30.0
						var hits_were: int = env_hits
						_env_hit(me, LASER_HIT, e, EFFECT_FOR.get(e, StatusEffects.DAZZLE), from)
						if e == Element.Type.WIND and env_hits > hits_were:
							StatusEffects.push_harder(me, GUST_SHOVE)
				if t >= float(hz["life"]) - LASER_TRAIL_BEFORE and not bool(hz.get("left", false)):
					hz["left"] = true
					_leave_trail(hz)
		"scorch", "rubble", "shade":
			if t >= float(hz["w"]) and me != null and _touches(me, hz["p"], float(hz["r"])):
				match kind:
					"scorch":
						_env_hit(me, 0.5, Element.Type.FIRE, StatusEffects.BURN, hz["p"])
					"rubble":
						if not bool(hz.get("landed", false)) and _touch_left <= 0.0:
							hz["landed"] = true
							_env_hit(me, 0.5, Element.Type.EARTH, StatusEffects.ROOT, hz["p"])
					"shade":
						if not bool(hz.get("landed", false)) and _touch_left <= 0.0:
							hz["landed"] = true
							_env_hit(me, 0.5, Element.Type.DARK, StatusEffects.WITHER, hz["p"])
	return true


func _arc_point(p: Vector2, heading: float, curve: float, s: float) -> Vector2:
	"""The point `s` along an arc leaving `p` at `heading`, curving by `curve`
	(1 / its radius; 0 straight)."""
	if absf(curve) < 0.000001:
		return p + Vector2.from_angle(heading) * s
	return p + Vector2(sin(heading + curve * s) - sin(heading), cos(heading) - cos(heading + curve * s)) / curve


func ghost_lines(hz: Dictionary) -> Array:
	"""Where a turning or moving laser will sweep, GHOSTS faint lines of it."""
	var lines: Array = []
	var turning: bool = absf(float(hz.get("spin", 0.0))) > 0.0
	var moving: bool = hz.has("travel") and float(hz.get("travel", 0.0)) > 0.0
	if not turning and not moving:
		return lines
	var fire: float = float(hz["life"]) - float(hz["w"])
	for g in range(1, GHOSTS + 1):
		var share: float = float(g) / float(GHOSTS)
		var later: Dictionary = hz.duplicate()
		later.erase("pts")
		later["t"] = float(hz["w"]) + fire * share
		if turning:
			later["a"] = float(hz["a"]) + float(hz["spin"]) * fire * share
		if moving:
			later["p"] = (hz["p"] as Vector2) + (hz["v"] as Vector2).normalized() * float(hz["travel"]) * share
		lines.append(beam_points(later))
	return lines


func beam_curve(hz: Dictionary) -> float:
	"""How much the beam bends now (1 / the arc's radius): its ends up to
	LASER_BEND of its half-length off its straight line, swaying from one
	side to the other every LASER_WHIP_SECONDS."""
	var chord: Array = chord_ends(hz)
	var length: float = ((chord[1] as Vector2) - (chord[0] as Vector2)).length()
	if length < 1.0:
		return 0.0
	var sway: float = sin(TAU * float(hz["t"]) / LASER_WHIP_SECONDS + float(hz.get("ph", 0.0)))
	return 4.0 * float(hz.get("bend", 0.0)) / length * sway


func beam_points(hz: Dictionary) -> PackedVector2Array:
	"""A laser's line now, wall to wall: an arc through its spot, every
	LASER_STEP, from one end to the other."""
	var rect: Rect2 = (run.get("room_rect") if run != null else Rect2(0, 0, 640, 360)).grow(-4.0)
	var p: Vector2 = hz["p"]
	var heading: float = float(hz["a"])
	var curve: float = beam_curve(hz)
	var most: float = rect.size.length() * 1.5
	var halves: Array = []
	for way in [-1.0, 1.0]:
		var half := PackedVector2Array()
		var s: float = LASER_STEP
		while s <= most:
			var at: Vector2 = _arc_point(p, heading, curve, s * way)
			if not rect.has_point(at):
				# The last piece to the wall, so it meets it.
				var last: Vector2 = half[half.size() - 1] if not half.is_empty() else p
				half.append(_to_wall(last, at, rect))
				break
			half.append(at)
			s += LASER_STEP
		halves.append(half)
	var points := PackedVector2Array()
	var back: PackedVector2Array = halves[0]
	for k in range(back.size() - 1, -1, -1):
		points.append(back[k])
	points.append(p)
	points.append_array(halves[1])
	return points


func _to_wall(inside: Vector2, outside: Vector2, rect: Rect2) -> Vector2:
	"""Where the piece from `inside` to `outside` meets `rect`'s edge."""
	var lo: float = 0.0
	var hi: float = 1.0
	for k in 12:
		var mid: float = (lo + hi) / 2.0
		if rect.has_point(inside.lerp(outside, mid)):
			lo = mid
		else:
			hi = mid
	return inside.lerp(outside, lo)


func _beam_line(hz: Dictionary) -> PackedVector2Array:
	var pts: Variant = hz.get("pts")
	return pts if pts is PackedVector2Array and (pts as PackedVector2Array).size() >= 2 else beam_points(hz)


func closest_on_beam(hz: Dictionary, at: Vector2) -> Vector2:
	"""The point of the beam, as it is now, nearest `at`."""
	var line: PackedVector2Array = _beam_line(hz)
	var best: Vector2 = line[0]
	var best_d: float = INF
	for k in line.size() - 1:
		var q: Vector2 = Geometry2D.get_closest_point_to_segment(at, line[k], line[k + 1])
		var d: float = q.distance_squared_to(at)
		if d < best_d:
			best_d = d
			best = q
	return best


func beam_heading(hz: Dictionary, at: Vector2) -> Vector2:
	"""Which way the beam runs at its point nearest `at`, away from its spot."""
	var line: PackedVector2Array = _beam_line(hz)
	var p: Vector2 = hz["p"]
	var best: int = 0
	var best_d: float = INF
	for k in line.size() - 1:
		var d: float = line[k].distance_squared_to(at)
		if d < best_d:
			best_d = d
			best = k
	var along: Vector2 = (line[best + 1] - line[best]).normalized()
	if along.dot(at - p) < 0.0:
		along = -along
	return along if along != Vector2.ZERO else Vector2.from_angle(float(hz["a"]))


func motes(hz: Dictionary) -> PackedVector2Array:
	"""Where its land rides along the beam now: LASER_MOTES points, running
	out from its spot to both walls, swirling from one side of it to the
	other (up to LASER_MOTE_SWAY off its middle - on the beam they were lost
	in its glow)."""
	var line: PackedVector2Array = _beam_line(hz)
	var found := PackedVector2Array()
	if line.size() < 2:
		return found
	var middle: int = 0
	var p: Vector2 = hz["p"]
	for k in line.size():
		if line[k] == p:
			middle = k
			break
	for k in LASER_MOTES:
		var u: float = fmod(float(k) / float(LASER_MOTES) * 2.0 + float(hz["t"]) * LASER_MOTE_SPEED, 1.0)
		var to_end: bool = k % 2 == 0
		var reach: int = (line.size() - 1 - middle) if to_end else middle
		var index: float = float(middle) + (u * float(reach) if to_end else -u * float(reach))
		var lo: int = clampi(int(floor(index)), 0, line.size() - 1)
		var hi: int = mini(lo + 1, line.size() - 1)
		var on: Vector2 = line[lo].lerp(line[hi], index - floor(index))
		var along: Vector2 = (line[hi] - line[lo]).normalized() if hi != lo else Vector2.RIGHT
		var side: float = sin(float(hz["t"]) * 5.0 + float(k) * 1.7) * LASER_MOTE_SWAY
		found.append(on + along.orthogonal() * side)
	return found


func _leave_trail(hz: Dictionary) -> void:
	"""As it fades: its land left along its last shape near its spot."""
	var e: int = int(hz["e"])
	var kind: String = str(TRAIL_FOR.get(e, ""))
	if kind == "":
		return
	var p: Vector2 = hz["p"]
	var heading: float = float(hz["a"])
	var curve: float = beam_curve(hz)
	var gap: float = LASER_TRAIL_STEP * (2.0 if kind == "flare" else 1.0)
	var rect: Rect2 = (run.get("room_rect") if run != null else Rect2(0, 0, 640, 360)).grow(-8.0)
	var s: float = -floor(LASER_TRAIL_REACH / gap) * gap
	while s <= LASER_TRAIL_REACH + 0.01:
		var at: Vector2 = _arc_point(p, heading, curve, s)
		if rect.has_point(at):
			_born.append(trail_patch(kind, at))
		s += gap


func trail_patch(kind: String, at: Vector2) -> Dictionary:
	"""One piece of a laser's trail - grows in over LASER_TRAIL_WARN."""
	var hz: Dictionary = {"k": kind, "t": 0.0, "w": LASER_TRAIL_WARN, "life": 3.0, "r": LASER_TRAIL_R, "p": at,
		"v": Vector2.ZERO, "done": false, "tick": 0.0, "trail": true}
	match kind:
		"puddle":
			hz["life"] = PUDDLE_LIFE
		"ice":
			hz["life"] = ICE_LIFE
		"scorch":
			hz["life"] = SCORCH_LIFE
		"rubble":
			hz["life"] = RUBBLE_LIFE
		"shade":
			hz["life"] = SHADE_LIFE
		"flare":
			hz["w"] = 0.6
			hz["life"] = 0.9
			hz["r"] = 30.0
	return hz


func _cross_flash(hz: Dictionary, me: Node2D = null) -> void:
	"""Where an X crosses: a flash in each of its two lands' colours, and a
	burst that hurts (X_BLAST_R)."""
	for e in [int(hz["e"]), int(hz["x_with"])]:
		var flash: Dictionary = _patch("burst", hz["p"])
		flash["e"] = e
		flash["life"] = 0.45
		flash["r"] = X_BLAST_R if e == int(hz["e"]) else X_BLAST_R * 0.7
		_born.append(flash)
	if me != null and _touches(me, hz["p"], X_BLAST_R):
		_touch_left = 0.0
		var land: int = int(hz["e"])
		_env_hit(me, X_BLAST_TIMES, land, EFFECT_FOR.get(land, StatusEffects.DAZZLE), hz["p"])


func beam_on(hz: Dictionary) -> bool:
	"""Whether a laser burns now: always while it fires, a pulsing one only on
	its beat."""
	var t: float = float(hz["t"]) - float(hz["w"])
	if t < 0.0:
		return false
	if not bool(hz.get("pulse", false)):
		return true
	return fmod(t, PULSE_ON + PULSE_OFF) < PULSE_ON


func _shaped(me: Node2D, land: int, at: Vector2, angle: float) -> Dictionary:
	"""A laser of `land` through `at` at `angle`, nothing else changed."""
	var hz: Dictionary = spawn_env("laser", me)
	hz["e"] = land
	hz["p"] = at
	hz["a"] = angle
	return hz


func pinwheel(me: Node2D, at: Vector2, land: int) -> Array:
	"""PINWHEEL_ARMS beams through `at`, turning together."""
	var made: Array = []
	var turn: float = randf() * PI
	var spin: float = LASER_SPIN if randf() < 0.5 else -LASER_SPIN
	var phase_of: float = randf() * TAU
	for k in PINWHEEL_ARMS:
		var arm: Dictionary = _shaped(me, land, at, turn + PI * float(k) / float(PINWHEEL_ARMS))
		arm["spin"] = spin
		arm["ph"] = phase_of + PI * float(k)
		arm["life"] = LASER_WARN + LASER_FIRE_SPIN * 1.4
		made.append(arm)
	return made


func sweep(me: Node2D, land: int) -> Dictionary:
	"""One straight beam crossing the whole room from wall to wall."""
	var rect: Rect2 = (run.get("room_rect") if run != null else Rect2(0, 0, 640, 360)).grow(-20.0)
	var across: bool = randf() < 0.5
	var forward: bool = randf() < 0.5
	var start: Vector2
	var heading: Vector2
	if across:
		start = Vector2(rect.get_center().x, rect.position.y if forward else rect.end.y)
		heading = Vector2(0, 1 if forward else -1)
	else:
		start = Vector2(rect.position.x if forward else rect.end.x, rect.get_center().y)
		heading = Vector2(1 if forward else -1, 0)
	var hz: Dictionary = _shaped(me, land, start, 0.0 if across else PI / 2.0)
	var span: float = rect.size.y if across else rect.size.x
	hz["spin"] = 0.0
	hz["bend"] = 0.0
	hz["v"] = heading * SWEEP_SPEED
	hz["travel"] = span
	hz["life"] = LASER_WARN + span / SWEEP_SPEED + 0.3
	return hz


func cage(me: Node2D, land: int) -> Array:
	"""Four straight beams round the player, closing in to CAGE_STOP."""
	var made: Array = []
	var rect: Rect2 = (run.get("room_rect") if run != null else Rect2(0, 0, 640, 360)).grow(-12.0)
	var centre: Vector2 = me.global_position
	var longest: float = 0.0
	var reaches: Array = []
	for k in 4:
		var side := Vector2.from_angle(PI / 2.0 * float(k)).round()
		# Held inside the room: a side by a wall starts at the wall.
		var room_left: float = [rect.end.x - centre.x, rect.end.y - centre.y, centre.x - rect.position.x, centre.y - rect.position.y][k]
		var reach: float = clampf(room_left, CAGE_STOP, CAGE_REACH)
		reaches.append(reach)
		longest = maxf(longest, reach - CAGE_STOP)
	for k in 4:
		var side := Vector2.from_angle(PI / 2.0 * float(k)).round()
		var reach: float = float(reaches[k])
		var hz: Dictionary = _shaped(me, land, centre + side * reach, PI / 2.0 * float(k) + PI / 2.0)
		hz["spin"] = 0.0
		hz["bend"] = 0.0
		hz["v"] = -side * CAGE_SPEED
		hz["travel"] = reach - CAGE_STOP
		hz["life"] = LASER_WARN + longest / CAGE_SPEED + 0.5
		made.append(hz)
	return made


func pulse_beam(me: Node2D, land: int) -> Dictionary:
	"""A beam that fires to a beat (PULSE_ON on, PULSE_OFF off, PULSES times)."""
	var hz: Dictionary = spawn_env("laser", me)
	hz["e"] = land
	hz["pulse"] = true
	hz["life"] = LASER_WARN + float(PULSES) * (PULSE_ON + PULSE_OFF)
	return hz


func _blow_along(hz: Dictionary) -> void:
	"""A wind laser fires: what floats near it is blown along it."""
	var rect: Rect2 = (run.get("room_rect") if run != null else Rect2(0, 0, 640, 360)).grow(-12.0)
	for other in hazards:
		if not (str(other["k"]) in ["spark", "bubble", "wisp", "gas"]) or bool(other["done"]):
			continue
		var at: Vector2 = other["p"]
		var near: Vector2 = closest_on_beam(hz, at)
		if at.distance_to(near) > 40.0:
			continue
		var to: Vector2 = at + beam_heading(hz, near) * GUST_PUSH
		other["p"] = Vector2(clampf(to.x, rect.position.x, rect.end.x), clampf(to.y, rect.position.y, rect.end.y))
		reactions["blown"] = int(reactions.get("blown", 0)) + 1


func beam_ends(hz: Dictionary) -> Array:
	"""A laser's two ends, where it meets the walls (beam_points())."""
	var line: PackedVector2Array = _beam_line(hz)
	return [line[0], line[line.size() - 1]]


func chord_ends(hz: Dictionary) -> Array:
	"""Where a laser would meet the walls unbent: its straight line through
	its spot, held to the room."""
	var rect: Rect2 = (run.get("room_rect") if run != null else Rect2(0, 0, 640, 360)).grow(-4.0)
	var dir := Vector2.from_angle(float(hz["a"]))
	var p: Vector2 = hz["p"]
	var lo: float = -INF
	var hi: float = INF
	for axis in 2:
		var d: float = dir[axis]
		if absf(d) < 0.0001:
			continue
		var t0: float = (rect.position[axis] - p[axis]) / d
		var t1: float = (rect.end[axis] - p[axis]) / d
		lo = maxf(lo, minf(t0, t1))
		hi = minf(hi, maxf(t0, t1))
	if lo > hi or lo == -INF:
		return [p, p]
	return [p + dir * lo, p + dir * hi]


var _paint := RandomNumberGenerator.new()


func _along(line: PackedVector2Array) -> PackedFloat32Array:
	"""How far along `line` each of its points is."""
	var out := PackedFloat32Array()
	var s: float = 0.0
	for k in line.size():
		if k > 0:
			s += line[k].distance_to(line[k - 1])
		out.append(s)
	return out


func _side(line: PackedVector2Array, k: int) -> Vector2:
	"""The way across `line` at its point `k`."""
	var lo: int = maxi(k - 1, 0)
	var hi: int = mini(k + 1, line.size() - 1)
	return (line[hi] - line[lo]).normalized().orthogonal()


func _swayed(line: PackedVector2Array, offsets: PackedFloat32Array) -> PackedVector2Array:
	"""`line` with each point moved across it by its offset, held at the ends."""
	var out := PackedVector2Array()
	var last: int = line.size() - 1
	for k in line.size():
		var held: float = clampf(minf(float(k), float(last - k)) / 2.0, 0.0, 1.0)
		out.append(line[k] + _side(line, k) * offsets[k] * held)
	return out


func _waved(line: PackedVector2Array, along: PackedFloat32Array, rate: float, shift: float, height: float) -> PackedVector2Array:
	var offsets := PackedFloat32Array()
	for k in line.size():
		offsets.append(sin(along[k] * rate + shift) * height)
	return _swayed(line, offsets)


func _draw_design(element: int, line: PackedVector2Array, t: float, fade: float, noise_seed: int) -> void:
	"""A firing laser, drawn as its land's own beam along its bent line."""
	if line.size() < 2 or fade <= 0.0:
		return
	var along: PackedFloat32Array = _along(line)
	match element:
		Element.Type.LIGHT:
			var gold := Color(1.0, 0.9, 0.45)
			_paint.seed = noise_seed + int(t / LIGHTNING_FLICKER)
			var jags := PackedFloat32Array()
			for k in line.size():
				jags.append(_paint.randf_range(-6.0, 6.0))
			var bolt: PackedVector2Array = _swayed(line, jags)
			_air.draw_polyline(bolt, Color(gold, 0.18 * fade), 16.0)
			_air.draw_polyline(bolt, Color(gold, 0.8 * fade), 5.0)
			_air.draw_polyline(bolt, Color(1.0, 1.0, 1.0, fade), 1.6)
			for f in 5:
				var from: int = _paint.randi_range(2, maxi(2, bolt.size() - 3))
				var heading: Vector2 = (bolt[mini(from + 1, bolt.size() - 1)] - bolt[from]).normalized()
				heading = heading.rotated(_paint.randf_range(0.5, 1.0) * (1.0 if f % 2 == 0 else -1.0))
				var fork := PackedVector2Array([bolt[from]])
				for q in 4:
					fork.append(fork[q] + heading.rotated(_paint.randf_range(-0.6, 0.6)) * _paint.randf_range(7.0, 12.0))
				_air.draw_polyline(fork, Color(gold, 0.55 * fade), 3.0)
				_air.draw_polyline(fork, Color(1.0, 1.0, 1.0, 0.9 * fade), 1.0)
		Element.Type.FIRE:
			_air.draw_polyline(line, Color(1.0, 0.35, 0.05, 0.16 * fade), 26.0)
			for strand in 2:
				var twist: PackedVector2Array = _waved(line, along, 0.07, PI * strand + t * 8.0, 7.0)
				_air.draw_polyline(twist, Color(1.0, 0.4, 0.08, 0.9 * fade), 5.0)
				_air.draw_polyline(twist, Color(1.0, 0.85, 0.35, fade), 1.8)
			for k in range(2, line.size() - 2, 3):
				var lick: float = 7.0 + 6.0 * absf(sin(t * 9.0 + float(k) * 1.3))
				var at: Vector2 = line[k]
				_air.draw_colored_polygon(PackedVector2Array([at + Vector2(-4, -2), at + Vector2(4, -2), at + Vector2(sin(t * 6.0 + float(k)) * 2.0, -2.0 - lick)]),
					Color(1.0, 0.5 + 0.25 * float(k % 2), 0.1, 0.85 * fade))
		Element.Type.ICE:
			var cyan := Color(0.55, 0.9, 1.0)
			var crystal := PackedVector2Array()
			var kink: float = 6.0
			for k in range(0, line.size(), 5):
				crystal.append(line[k] + _side(line, k) * kink * (0.0 if k == 0 else 1.0))
				kink = -kink
			crystal.append(line[line.size() - 1])
			_air.draw_polyline(crystal, Color(cyan, 0.2 * fade), 16.0)
			_air.draw_polyline(crystal, Color(cyan, 0.85 * fade), 4.0)
			_air.draw_polyline(crystal, Color(1.0, 1.0, 1.0, fade), 1.4)
			var glint: int = int(fmod(t * 9.0, float(crystal.size())))
			for k in range(1, crystal.size() - 1):
				var at: Vector2 = crystal[k]
				var out: Vector2 = _side(crystal, k) * (1.0 if k % 2 == 0 else -1.0)
				var across: Vector2 = out.orthogonal()
				var reach: float = 11.0 + 6.0 * absf(sin(float(k) * 1.3 + float(noise_seed % 7)))
				var shard := PackedVector2Array([at + across * 3.0, at + out * reach, at - across * 3.0, at - out * 2.0])
				_air.draw_colored_polygon(shard, Color(0.75, 0.95, 1.0, (0.95 if k == glint else 0.7) * fade))
				_air.draw_polyline(PackedVector2Array([shard[0], shard[1], shard[2]]), Color(1.0, 1.0, 1.0, 0.9 * fade), 1.0)
		Element.Type.WATER:
			var wave: PackedVector2Array = _waved(line, along, 0.09, -t * 6.0, 8.0)
			var crest: PackedVector2Array = _waved(line, along, 0.09, -t * 6.0, 8.0)
			for k in crest.size():
				crest[k] += Vector2(0, -4)
			_air.draw_polyline(wave, Color(0.2, 0.5, 1.0, 0.25 * fade), 24.0)
			_air.draw_polyline(wave, Color(0.25, 0.6, 1.0, 0.75 * fade), 11.0)
			_air.draw_polyline(crest, Color(0.75, 0.92, 1.0, 0.95 * fade), 2.0)
			for k in range(0, crest.size(), 2):
				if sin(along[k] * 0.09 - t * 6.0) > 0.6:
					_air.draw_circle(crest[k], 2.0, Color(1.0, 1.0, 1.0, 0.9 * fade))
			for b in 10:
				var k: int = (b * 7 + noise_seed % 5) % line.size()
				var rise: float = fmod(t * 14.0 + float(b) * 5.0, 22.0)
				_air.draw_arc(line[k] + Vector2(float((b * 13) % 21) - 10.0, 6.0 - rise), 2.0 + float(b % 3), 0.0, TAU, 12,
					Color(0.7, 0.9, 1.0, 0.8 * fade * (1.0 - rise / 22.0)), 1.0)
		Element.Type.WIND:
			for strand in 4:
				var thread: PackedVector2Array = _waved(line, along, 0.05, float(strand) * 2.1 + t * 7.0, 5.0 + 4.0 * float(strand))
				_air.draw_polyline(thread, Color(0.85, 1.0, 0.9, (0.75 - 0.12 * float(strand)) * fade), 1.6)
			for k in range(6, line.size() - 6, 10):
				var at: Vector2 = line[k] + _side(line, k) * sin(float(k) * 2.3) * 12.0
				var start: float = t * 6.0 + float(k)
				_air.draw_arc(at, 6.0, start, start + 4.6, 16, Color(0.9, 1.0, 0.92, 0.8 * fade), 1.4)
				_air.draw_arc(at, 3.0, start + 1.0, start + 5.0, 10, Color(0.9, 1.0, 0.92, 0.6 * fade), 1.2)
			for leaf in 6:
				var u: float = fmod(float(leaf) / 6.0 + t * 0.5, 1.0)
				var k: int = int(u * float(line.size() - 1))
				var at: Vector2 = line[k] + _side(line, k) * sin(t * 4.0 + float(leaf) * 2.0) * 14.0
				_air.draw_set_transform(at, t * 5.0 + float(leaf), Vector2(1.0, 0.45))
				_air.draw_circle(Vector2.ZERO, 4.0, Color(0.55, 0.85, 0.45, 0.9 * fade))
				_air.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		Element.Type.EARTH:
			_paint.seed = noise_seed
			var cracks := PackedFloat32Array()
			for k in line.size():
				cracks.append(_paint.randf_range(-4.0, 4.0))
			var crack: PackedVector2Array = _swayed(line, cracks)
			_air.draw_polyline(crack, Color(0.55, 0.38, 0.2, 0.35 * fade), 12.0)
			_air.draw_polyline(crack, Color(0.05, 0.03, 0.02, fade), 4.0)
			_air.draw_polyline(crack, Color(1.0, 0.55, 0.2, 0.7 * fade), 1.0)
			for k in range(2, line.size() - 2, 4):
				var at: Vector2 = line[k] + _side(line, k) * _paint.randf_range(-12.0, 12.0)
				var r: float = _paint.randf_range(4.0, 8.0)
				var lift: float = 4.0 + 10.0 * absf(sin(t * 5.0 + float(k) * 0.9))
				_air.draw_set_transform(at, 0.0, Vector2(1.0, 0.45))
				_air.draw_circle(Vector2.ZERO, r, Color(0.0, 0.0, 0.0, 0.35 * fade))
				_air.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				var rock := PackedVector2Array()
				var sides: int = 5 + k % 3
				for q in sides:
					rock.append(at + Vector2(0, -lift) + Vector2.from_angle(TAU * float(q) / float(sides) + _paint.randf_range(-0.3, 0.3)) * r * _paint.randf_range(0.7, 1.1))
				_air.draw_colored_polygon(rock, Color(Color(0.6, 0.47, 0.32).darkened(0.15 * float(k % 3)), fade))
				rock.append(rock[0])
				_air.draw_polyline(rock, Color(0.85, 0.72, 0.5, 0.8 * fade), 1.0)
		Element.Type.DARK:
			var writhe := PackedFloat32Array()
			for k in line.size():
				writhe.append(sin(along[k] * 0.045 + t * 3.0) * 6.0 + sin(along[k] * 0.17 - t * 5.0) * 2.5)
			var tendril: PackedVector2Array = _swayed(line, writhe)
			_air.draw_polyline(tendril, Color(0.5, 0.15, 0.8, 0.2 * fade), 26.0)
			_air.draw_polyline(tendril, Color(0.6, 0.3, 1.0, 0.85 * fade), 10.0)
			_air.draw_polyline(tendril, Color(0.03, 0.0, 0.06, fade), 7.0)
			for k in range(4, tendril.size() - 4, 7):
				var out: Vector2 = _side(tendril, k) * (1.0 if k % 2 == 0 else -1.0)
				var wisp := PackedVector2Array()
				for q in 6:
					wisp.append(tendril[k] + out * float(q) * 4.0 + out.orthogonal() * sin(float(q) * 1.2 + t * 6.0) * 4.0)
				_air.draw_polyline(wisp, Color(0.65, 0.35, 1.0, 0.6 * fade), 1.4)
			for eye in 4:
				var k: int = 4 + int(float(eye) * float(tendril.size() - 8) / 4.0)
				var blink: float = clampf(absf(sin(t * 2.0 + float(eye) * 1.7)) * 1.6, 0.15, 1.0)
				_air.draw_set_transform(tendril[k], 0.0, Vector2(1.0, blink))
				_air.draw_circle(Vector2.ZERO, 5.0, Color(0.03, 0.0, 0.06, fade))
				_air.draw_arc(Vector2.ZERO, 5.0, 0.0, TAU, 16, Color(0.75, 0.45, 1.0, fade), 1.2)
				_air.draw_circle(Vector2(1, -1), 1.3, Color(0.9, 0.7, 1.0, fade))
				_air.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		_:
			var colour: Color = Element.colour_for(element)
			_air.draw_polyline(line, Color(colour, 0.3 * fade), LASER_HALF * 4.0)
			_air.draw_polyline(line, Color(colour * 1.4, 0.85 * fade), LASER_HALF * 2.0)
			_air.draw_polyline(line, Color(1.0, 1.0, 1.0, 0.95 * fade), 3.0)


func _draw_mote(element: int, at: Vector2, k: int, t: float, alpha: float, line: PackedVector2Array) -> void:
	"""One piece of a land riding along a laser (motes())."""
	if alpha <= 0.0:
		return
	var wob: float = sin(t * 7.0 + float(k) * 1.9)
	match element:
		Element.Type.FIRE:
			var up := Vector2(wob * 2.0, -3.0 - 2.0 * absf(wob))
			_air.draw_circle(at + up, 4.6, Color(1.0, 0.4, 0.08, 0.55 * alpha))
			_air.draw_circle(at + up, 2.4, Color(1.0, 0.92, 0.55, alpha))
		Element.Type.ICE:
			var spin: float = t * 3.0 + float(k)
			for q in 2:
				var arm := Vector2.from_angle(spin + float(q) * PI / 2.0) * 5.0
				_air.draw_line(at - arm, at + arm, Color(0.85, 0.97, 1.0, alpha), 1.6)
		Element.Type.WATER:
			_air.draw_circle(at, 3.6, Color(0.35, 0.65, 1.0, 0.9 * alpha))
			_air.draw_circle(at + Vector2(-1.1, -1.1), 1.2, Color(1.0, 1.0, 1.0, alpha))
		Element.Type.WIND:
			var along: Vector2 = Vector2.RIGHT
			if line.size() >= 2:
				along = (line[line.size() - 1] - line[0]).normalized()
			_air.draw_line(at - along * 9.0 + Vector2(0, wob * 2.0), at + along * 9.0, Color(0.88, 1.0, 0.92, 0.85 * alpha), 1.8)
		Element.Type.LIGHT:
			var twinkle: float = 3.5 + 2.0 * absf(wob)
			_air.draw_line(at - Vector2(twinkle, 0), at + Vector2(twinkle, 0), Color(1.0, 0.97, 0.7, alpha), 1.6)
			_air.draw_line(at - Vector2(0, twinkle), at + Vector2(0, twinkle), Color(1.0, 0.97, 0.7, alpha), 1.6)
		Element.Type.EARTH:
			_air.draw_rect(Rect2(at + Vector2(-2.5, -2.5 + wob), Vector2(5.0, 4.5)), Color(0.72, 0.56, 0.38, alpha))
		Element.Type.DARK:
			_air.draw_circle(at, 4.6, Color(0.25, 0.05, 0.4, 0.65 * alpha))
			_air.draw_circle(at, 2.0, Color(0.78, 0.5, 1.0, alpha))
		_:
			_air.draw_circle(at, 2.0, Color(1.0, 1.0, 1.0, alpha))


func burst_at(at: Vector2, element: int) -> void:
	"""A stacked element's burst on the player (descentrun.gd _burst()): a
	flash in its colour."""
	var flash: Dictionary = _patch("burst", at)
	flash["e"] = element
	flash["life"] = 0.5
	flash["r"] = 34.0
	hazards.append(flash)


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
	for hz in hazards:
		if bool(hz["done"]):
			continue
		var kind: String = str(hz["k"])
		var p: Vector2 = hz["p"]
		if kind == "spark" or (kind == "scorch" and float(hz["t"]) >= float(hz["w"])):
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
								_env_hit(me, 2.0, Element.Type.FIRE, StatusEffects.BURN, other["p"])
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
								_env_hit(me, 1.5, Element.Type.LIGHT, StatusEffects.DAZZLE, other["p"])
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


func _env_hit(me: Node2D, times: float, element: int, effect: StringName, from: Vector2) -> void:
	"""A hazard `times` as hard lands on this game's player - at most every
	TOUCH_GAP: a share of its most health (env_amount()), harder for its
	stacks of the element, past armour and the ward (0.129.0)."""
	if _touch_left > 0.0 or not me.has_method("take_damage"):
		return
	_touch_left = TOUCH_GAP
	var amount: int = maxi(1, roundi(float(env_amount(env_floor, int(me.get("max_hp")), times)) * Boons.stack_scale(element)))
	Boons.exact_once = true
	me.call("take_damage", amount, element)
	Boons.exact_once = false
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
			"hail", "rock", "meteor":
				var colour := Color(0.85, 0.95, 1.0) if kind == "hail" else Color(0.55, 0.42, 0.3)
				if kind == "meteor":
					colour = Color(1.0, 0.5, 0.15)
				var fake: bool = bool(hz.get("fake", false))
				var ring: float = float(hz["r"])
				if fake:
					# The tell: an illusion's circle shimmers.
					ring *= 1.0 + 0.06 * sin(t * 17.0)
					colour = colour.lerp(Color(0.8, 0.6, 1.0), 0.3 + 0.25 * sin(t * 9.0))
				if fake and bool(hz.get("landed", false)):
					var gone: float = clampf((t - w) / 0.35, 0.0, 1.0)
					draw_set_transform(p, 0.0, Vector2(1.0, 0.55))
					draw_arc(Vector2.ZERO, ring * (1.0 + 0.5 * gone), 0.0, TAU, 24, Color(0.85, 0.65, 1.0, 1.0 - gone), 2.0)
					for k in 8:
						var spark := Vector2.from_angle(float(k) * TAU / 8.0) * ring * (0.4 + 0.8 * gone)
						draw_circle(spark, 2.0, Color(0.9, 0.75, 1.0, 1.0 - gone))
				elif not bool(hz.get("landed", false)):
					draw_set_transform(p, 0.0, Vector2(1.0, 0.55))
					draw_circle(Vector2.ZERO, ring * grow, Color(0.0, 0.0, 0.0, 0.25 + 0.3 * grow))
					draw_arc(Vector2.ZERO, ring, 0.0, TAU, 24, Color(colour, 0.7), 1.5)
				else:
					var after: float = clampf((t - w) / 0.3, 0.0, 1.0)
					draw_set_transform(p, 0.0, Vector2(1.0, 0.55))
					draw_arc(Vector2.ZERO, float(hz["r"]) * (1.0 + after), 0.0, TAU, 24, Color(colour * 1.5, 1.0 - after), 3.0)
			"flare":
				draw_set_transform(p, 0.0, Vector2(1.0, 0.6))
				var flare_colour := Color(1.0, 0.9, 0.5, 0.35 + 0.4 * grow)
				var flare_r: float = float(hz["r"])
				if bool(hz.get("fake", false)):
					flare_r *= 1.0 + 0.05 * sin(t * 17.0)
					flare_colour = Color(flare_colour.lerp(Color(0.8, 0.6, 1.0), 0.3 + 0.25 * sin(t * 9.0)), flare_colour.a)
				draw_arc(Vector2.ZERO, flare_r, 0.0, TAU, 32, flare_colour, 1.5)
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
				if (kind == "puddle" or bool(hz.get("trail", false))) and t < w:
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
			"scorch", "rubble", "shade":
				var fade: float = clampf((float(hz["life"]) - t) / 0.6, 0.0, 1.0) * grow
				var r: float = float(hz["r"])
				draw_set_transform(p, 0.0, Vector2(1.0, 0.55))
				match kind:
					"scorch":
						draw_circle(Vector2.ZERO, r, Color(0.12, 0.05, 0.02, 0.55 * fade))
						draw_arc(Vector2.ZERO, r, 0.0, TAU, 20, Color(1.0, 0.45, 0.1, 0.7 * fade), 1.5)
						draw_set_transform(p, 0.0, Vector2.ONE)
						for k in 3:
							var x: float = (float(k) - 1.0) * r * 0.55
							var lick: float = 5.0 + 4.0 * absf(sin(t * 9.0 + float(k) * 2.1 + p.x * 0.1))
							draw_colored_polygon(PackedVector2Array([Vector2(x - 3.0, 1.0), Vector2(x + 3.0, 1.0),
								Vector2(x, 1.0 - lick)]), Color(1.0, 0.55 + 0.2 * float(k % 2), 0.15, 0.85 * fade))
					"rubble":
						draw_circle(Vector2.ZERO, r, Color(0.35, 0.26, 0.18, 0.5 * fade))
						draw_set_transform(p, 0.0, Vector2.ONE)
						for k in 4:
							var at := Vector2.from_angle(float(k) * 1.7 + p.y * 0.05) * r * 0.5
							draw_rect(Rect2(at - Vector2(2.5, 2.0), Vector2(5.0, 4.0)), Color(0.62, 0.5, 0.36, 0.9 * fade))
					"shade":
						var pulse: float = 0.5 + 0.5 * sin(t * 5.0 + p.x * 0.07)
						draw_circle(Vector2.ZERO, r, Color(0.2, 0.05, 0.3, (0.45 + 0.15 * pulse) * fade))
						draw_arc(Vector2.ZERO, r * (0.8 + 0.2 * pulse), 0.0, TAU, 20, Color(0.7, 0.4, 1.0, 0.6 * fade), 1.0)
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
				var sr: float = float(hz["r"])
				_air.draw_circle(p, sr * 1.1, Color(1.0, 0.45, 0.1, 0.22))
				_air.draw_circle(p, sr * 0.6, Color(1.0, 0.6, 0.2, 0.6))
				_air.draw_circle(p, sr * 0.3, Color(1.0, 0.95, 0.7, 1.0))
			"bubble":
				_air.draw_arc(p, float(hz["r"]), 0.0, TAU, 20, Color(0.6, 0.85, 1.0, 0.85), 1.5)
				_air.draw_circle(p + Vector2(-3, -3), 1.5, Color(1, 1, 1, 0.8))
			"wisp":
				_air.draw_circle(p, 13.0, Color(0.55, 0.3, 0.95, 0.25))
				_air.draw_circle(p, 6.0, Color(0.8, 0.6, 1.0, 0.9))
			"meteor":
				if not bool(hz.get("landed", false)):
					# Falling from up and to the left, its tail streaming back up
					# the way it came (it was drawn ahead of it - "the fire balls
					# look upside down").
					var fall: float = clampf(t / maxf(0.001, float(hz["w"])), 0.0, 1.0)
					var from := Vector2(-110.0, -300.0)
					var at: Vector2 = p + from * (1.0 - fall * fall)
					var back: Vector2 = from.normalized()
					for k in range(6, 0, -1):
						var behind: Vector2 = at + back * float(k) * 7.0
						var fade: float = 1.0 - float(k) / 7.0
						_air.draw_circle(behind, 3.0 + 4.0 * fade, Color(1.0, 0.35 + 0.3 * fade, 0.08, 0.15 + 0.45 * fade))
					_air.draw_circle(at, 9.0, Color(1.0, 0.45, 0.1, 0.45))
					_air.draw_circle(at, 6.5, Color(1.0, 0.65, 0.2, 0.95))
					_air.draw_circle(at + back * 1.5, 3.2, Color(1.0, 0.95, 0.7, 1.0))
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
			"laser":
				var e: int = int(hz["e"])
				var colour: Color = Element.colour_for(e)
				var line: PackedVector2Array = _beam_line(hz)
				var ends: Array = [line[0], line[line.size() - 1]]
				var warn: float = maxf(0.001, float(hz["w"]))
				var riding: PackedVector2Array = motes(hz)
				if t < warn:
					var k: float = t / warn
					var flick: float = 0.3 + 0.4 * k + 0.25 * absf(sin(t * 20.0)) * k
					for ghost in ghost_lines(hz):
						_air.draw_polyline(ghost, Color(colour * 1.2, 0.18 * k), 1.0)
					_air.draw_polyline(line, Color(colour * 1.3, flick), 1.0 + 2.0 * k)
					for end in ends:
						_air.draw_circle(end, 2.0 + 3.0 * k, Color(colour * 1.4, 0.9))
					for m in riding.size():
						_draw_mote(e, riding[m], m, t, 0.45 * k, line)
				else:
					var f: float = clampf((t - warn) / maxf(0.01, float(hz["life"]) - warn), 0.0, 1.0)
					var fade: float = 1.0 if f < 0.8 else (1.0 - f) / 0.2
					if beam_on(hz):
						_draw_design(e, line, t, fade, int(hz.get("seed", 0)))
					else:
						_air.draw_polyline(line, Color(colour * 1.3, 0.45 * fade), 2.0)
					for end in ends:
						_air.draw_circle(end, 9.0, Color(colour * 1.5, 0.6 * fade))
						_air.draw_circle(end, 4.0, Color(1.0, 1.0, 1.0, fade))
			"burst":
				var bb: float = clampf(t / float(hz["life"]), 0.0, 1.0)
				var tint: Color = Element.colour_for(int(hz.get("e", 0)))
				var reach: float = float(hz["r"])
				_air.draw_set_transform(p, 0.0, Vector2(1.0, 0.6))
				_air.draw_circle(Vector2.ZERO, reach * (0.4 + 0.6 * bb), Color(tint, 0.45 * (1.0 - bb)))
				for k in 8:
					var ray := Vector2.from_angle(float(k) * TAU / 8.0)
					_air.draw_line(ray * reach * (0.3 + 0.6 * bb), ray * reach * (0.6 + 0.8 * bb), Color(tint * 1.5, 1.0 - bb), 2.5)
				_air.draw_arc(Vector2.ZERO, reach * (0.5 + 0.8 * bb), 0.0, TAU, 32, Color(tint * 1.6, 1.0 - bb), 3.0)
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
