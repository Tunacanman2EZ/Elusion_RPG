# forgerun.gd - THE FORGE (step 1; the owner's alone while it is built): the
# tank's minigame, as the Healer's Run is the healer's, the Stand the mage's
# and the Descent the warrior's - but open to every class, the tank getting
# the most from it. A volcano; the lava always wins; the score is how long.
#
# THE OWNER'S STORY: "the tank lived generations making armor but eventually
# fate decided the lava would rise and the master smith fell with his own
# creations in a rough life cycle where life is temporary one day his armor
# will be a lagacy for the next person". And the rules he set: "lava should
# fill like slices of pie preventing lava from spilling into that tiny circle"
# (the tank's light, standing on the anvil), "enemies spawn close and closer",
# "i need players to catch on fire and tanks gear just turns a little red",
# "everyone dies but time can be added to set a highscore", "as the map gets
# smaller enemies flood", and "open to any class but the tank benefits the
# most do to the armor he wears this is his world".
#
# THE ISLAND (scene/forge.tscn, written by buildforge.gd from the MAP
# numbers below): a disc of floor in a ring of lava, the anvil in the middle.
# The lava lies under the whole island too, so a slice floods by its floor
# being taken away. Only lava that meets floor bubbles (BUBBLING, the town's
# animated tile); the rest is its first frame, still (STILL) - the owner:
# "the lava is graphics heavy so i need to use it wisely".
#
#   WAITING    stand at the anvil (START_REACH) for START_HOLD to light it.
#   COUNTDOWN  COUNTDOWN_SECONDS, then the clock starts.
#   RUNNING    heat fills (fill_seconds(), quicker each flood); from WARN_AT
#              the next slice glows and the falls pour twice as fast; full,
#              the slice floods (FLOOD_SECONDS, rim to the light), and heat
#              starts again. ORDER is opposite slices in turn. Once all
#              SLICES are gone, THE VOLCANO ERUPTS (below): rocks on
#              glowing circles, faster and more, until they fall.
#
# THE LIGHT THE LAVA NEVER ENTERS: SAFE_TANK (294 px - the tank's own light,
# playerlight.tscn's 256 px glow at texture_scale 2.3, round the anvil) when
# the player is a tank, SAFE_OTHER (210 px, the anvil's own glow) otherwise.
# The anvil's glow is sized to it.
#
# FIRE (0.121.0: every class): out of wading time (THE ANVIL'S GEAR, below),
# anyone in the lava catches fire - LAVA_BURN of their health a tick through
# Player.take_damage() as fire, and the effects' burn, drawn as flames on them
# (Flames). The tank burns too now, but fire bites him less: in the Forge his
# fire hits land at TANK_FIRE (hit_scale(), asked by Player.damage_taken()) -
# the owner: "His armour repels fire, so fire sprites and lava splash do less
# to him". His gear still turns red (TANK_RED, more in the lava and as the
# heat climbs).
#
# THE ANVIL'S GEAR (0.121.0). The owner's rules: "He wades lava longest. Every
# class burns in lava, but each forged piece buys the tank about twice as much
# wading time as anyone else", "He forges fastest. Anyone can work the anvil,
# but the tank's swings count fully and other classes' count for less", then
# "lets add the gear to make the minigame funner". Stand still at the anvil
# (FORGE_REACH) holding the interact key and the hammer swings (a spark every
# HAMMER_EVERY): piece_seconds() - PIECE_TANK for the tank, PIECE_OTHER for
# anyone else - forges the next of PIECES, in-run only. Each piece is
# WADE_TANK (tank) or WADE_OTHER seconds in the lava before the fire starts:
# wade_left drains while you stand in it and comes back WADE_REFILL a second
# on the floor. The hammer cannot fight - the sprites keep coming.
#
# THE VOLCANO ERUPTS (0.121.0). The owner: "no point in the fire damage at
# the end we need the screen to start shaking and we can use the giant meteor
# impact to simulate the volcano erupting". With every slice gone the light is
# the only floor; the volcano throws rocks - the mage's meteor, ERUPT_SCALE
# times as big, a picture that hits nothing itself - each onto a glowing
# circle ERUPT_WARN before it lands. Landing within ERUPT_RADIUS is
# erupt_hit() of your health as fire, more with every rock fallen; half are
# thrown at where you stand (ERUPT_AIMED); a volley grows by a rock every
# ERUPT_MORE_EVERY seconds and the gap shortens to ERUPT_FASTEST, so
# everyone falls in the end. The screen rumbles from the last flood
# (RUMBLE_*) and jolts at each impact near you (IMPACT_SHAKE). Wading time is
# how you step out of the light to dodge.
#
# THE ISLAND IS WIPED (0.122.0). The owner, of the rain: "amaing we need the
# giant impact to wipe the field at the end the meteors were awesome", "you
# know the field wipe on mages minigame" - the Stand's star. FINALE_AT into
# the volcano it throws its heart: FINALE_FALL before, a shadow spreads out
# from the anvil over the whole island (Marks, finale_shadow()), a giant rock
# comes down out of the sky onto the anvil - drawn on the screen itself by
# forgehud.gd (heart_at()), so it is seen at any zoom - the rain and the fire
# sprites stop (RAIN_STOPS), and the ground shakes harder; on landing a fire blast on the anvil and on every fire sprite
# (gone with it, paying nothing), a white flash (forgehud.gd flash()) and the
# hardest jolt (FINALE_SHAKE); FINALE_HOLD later the run is over for everyone
# still standing - knock_out(), "The volcano took the island at ...". The
# rain's ramp still takes the unlucky sooner; the heart takes the rest.
#
# THE FIRE SPRITES step out of the lava's edges (edge_spot(): the rim of an
# open slice, the light's rim of a flooded one, the sides where the two meet,
# by length) - so each flood brings them closer to the anvil - more often and
# more at once with every flood (spawn_gap(), alive_cap()). They carry the
# stress test's mark: no kill report, never shared or numbered, never
# respawned, pay nothing.
#
# THE TANK'S WALKWAYS (the owner: "what if the tanks aura can push back lava
# only where he is standing to create safe walkways for the team"): while a
# tank's aura is on, the lava inside its ring (the aura's own ellipse,
# aura_ellipse()) is island again - the floor's own tiles laid back - and
# stays so WALK_LINGER after the ring has moved on, then melts. A walkway is
# no lava for anyone (in_lava()), and no fire sprite steps out of one. The
# aura's mana is what it costs.
#
# ICE ESSENCE (the art pack's iceessence.png): one at a time, out in an open
# slice, never in the one about to flood; walk over it and the heat drops by
# ESSENCE_COOL of a fill - time added.
#
# A FALL IS NOT A DEATH (as in the Endless and the Descent):
# Player.take_damage() asks knock_out() first - you wake beside the anvil on
# 1 health, every effect cleared, and the run is over: "The forge held 4:12".
#
# WHAT IT PAYS: since 0.120.0, every fire sprite's loot into your chest (the
# server's pets and mythics ten times rarer here since 0.121.0). The legacy
# armour, a party of four and the high-score board are the next steps.
extends Node

const StatusEffects := preload("res://src/characters/statuseffects.gd")

enum State { WAITING, COUNTDOWN, RUNNING }

# ---- THE MAP (buildforge.gd writes the island from these) --------------------
const CENTRE := Vector2(1280, 1280)
const RADIUS := 960.0
const BAND := 192.0
const TILE := 16
const LAVA_TILE := 32
const LAVA_CELL := Vector2i(0, 5)
const BUBBLING := 0
const STILL := 1
# How near floor a lava cell's middle may be and still bubble.
const BUBBLE_REACH := 40.0

# ---- THE PIE ------------------------------------------------------------------
const SLICES := 8
# Slice k is centred on k eighths of a turn clockwise from north.
const SLICE_NAMES := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
# Opposite slices in turn: lanes on every side, the harder way.
const ORDER := [0, 4, 2, 6, 1, 5, 3, 7]
const SAFE_TANK := 294.0
const SAFE_OTHER := 210.0
const TANK_CLASS := "tank"

# ---- STARTING -----------------------------------------------------------------
const START_REACH := 56.0
const START_HOLD := 1.0
const COUNTDOWN_SECONDS := 3.0

# ---- THE HEAT -----------------------------------------------------------------
const HEAT_SECONDS := 40.0
const HEAT_QUICKER := 0.9
const HEAT_FASTEST := 18.0
const WARN_AT := 0.8
const FLOOD_SECONDS := 2.5
# A repaint of the bubbling cells at the front every this much, not every frame.
const FRONT_REPAINT := 0.1
const FALLS_PER_FLOOD := 0.12
const FALLS_WARNING := 2.0

# ---- FIRE ---------------------------------------------------------------------
const BURN_TICK := 0.5
const LAVA_BURN := 0.12
const TANK_RED := Color(1.0, 0.5, 0.42)

# ---- THE FIRE SPRITES ---------------------------------------------------------
const MARK := &"stress_copy"
const SPRITE := "firesprite"
const NOTICE := 2600.0
const SPAWN_EVERY := 3.0
const SPAWN_QUICKER := 0.8
const SPAWN_FASTEST := 0.5
const ALIVE_FIRST := 10
const ALIVE_PER_FLOOD := 5
const HEALTH_PER_FLOOD := 0.15
const SPAWN_CLEAR := 110.0
# How far into the lava past an edge a sprite steps out.
const EDGE_IN := 22.0

# ---- WHAT IT PAYS (0.120.0) ---------------------------------------------------
# The owner, 4 Nov: "Rewards + daily wait". Go asks the server, once a day as
# the Endless (minigamescard.gd). Every fire sprite slain pays its own loot -
# no XP - into this character's chest by the arrival (the Endless's chest,
# endlesschest.gd, for CHEST_GAME): it carries CHEST_META, so BaseEnemy._die()
# sends it to Combat.report_endless_kill() and POST /api/minigames/kill, and
# the server holds the kills to schedule(). It still carries the stress test's
# MARK: no ordinary kill, never shared or numbered. And each run's time goes
# to POST /api/minigames/best (best_post), which keeps the best.
const CHEST_GAME := "forge"
const CHEST_META := &"chest_game"
const ChestScript := preload("res://src/world/endless/endlesschest.gd")
# Beside the arrival, in the light.
const CHEST_SPOT := CENTRE + Vector2(72, 124)
# The volcano as the server believes it: this long, and everybody has fallen.
const VOLCANO_BELIEVED := 60
# The chest's arrow shows to a player this near the anvil while no run is on.
const CHEST_BECKON := Rect2(CENTRE - Vector2(320, 320), Vector2(640, 640))

# ---- THE TANK'S WALKWAYS ------------------------------------------------------
const WALK_LINGER := 3.0
const WALK_REPAINT := 0.1
# The aura's ellipse when it cannot be read off the tank (tank.tscn: a capsule
# 42.3 round and 147.6 long, laid on its side, 13.5 px over his feet).
const AURA_HALF := Vector2(73.8, 42.3)
const AURA_OFFSET := Vector2(-0.9, -13.5)

# ---- THE ANVIL'S GEAR (0.121.0) ----------------------------------------------
const FORGE_REACH := 56.0
const PIECES := ["helm", "chestplate", "gauntlets", "greaves", "boots"]
const PIECE_TANK := 6.0
const PIECE_OTHER := 12.0
const HAMMER_EVERY := 0.4
# Faster than this (px/s) is walking, not hammering.
const STILL_SPEED := 12.0
const WADE_TANK := 8.0
const WADE_OTHER := 4.0
const WADE_REFILL := 2.0
# The tank's fire hits in the Forge.
const TANK_FIRE := 0.6

# ---- THE VOLCANO ERUPTS (0.121.0) ---------------------------------------------
const MeteorScene := preload("res://scene/projectiles/meteor.tscn")
const ERUPT_FIRST := 1.0
const ERUPT_GAP := 1.6
const ERUPT_QUICKER := 0.94
const ERUPT_FASTEST := 0.35
const ERUPT_WARN := 1.2
# The danger circle is the giant meteor's own hit: meteor.gd's HIT_RADIUS (44)
# at ERUPT_SCALE - its ring of fire is drawn that size, so what glows is what
# hits.
const ERUPT_SCALE := 1.8
const ERUPT_RADIUS := 79.0
const ERUPT_HIT := 0.5
const ERUPT_HIT_STEP := 0.02
const ERUPT_AIMED := 0.5
const ERUPT_AIM_SPREAD := 40.0
const ERUPT_MORE_EVERY := 15.0
# Rocks fall on the light and this far past it, over the lava.
const ERUPT_PAST := 60.0
const RUMBLE_EVERY := 0.2
const RUMBLE_PX := 1.0
const RUMBLE_GROW := 0.05
const RUMBLE_MOST := 3.0
const IMPACT_NEAR := 220.0
const IMPACT_SHAKE := Vector2(7.0, 0.45)

# ---- THE ISLAND IS WIPED (0.122.0) --------------------------------------------
const FINALE_AT := 45.0
const FINALE_FALL := 3.0
const FINALE_HOLD := 1.6
const RAIN_STOPS := 1.0
# Where the heart lands, over the anvil (forgehud.gd draws its fall).
const FINALE_LAND := Vector2(0.0, -20.0)
# Its shadow on the island, growing from FINALE_SHADOW_FROM, and the afterglow.
const FINALE_SHADOW_FROM := 80.0
const FINALE_SHADOW := 900.0
const FINALE_AFTERGLOW := 1.6
const FINALE_RUMBLE := 6.0
const FINALE_SHAKE := Vector2(14.0, 1.2)
const FINALE_BLAST := 180.0
const SKY_Z := 30

# ---- ICE ESSENCE --------------------------------------------------------------
const ESSENCE_ART := "res://art/pack/materials/iceessence.png"
const ESSENCE_FIRST := 10.0
const ESSENCE_EVERY := 16.0
const ESSENCE_LIFE := 14.0
const ESSENCE_COOL := 0.3
const ESSENCE_REACH := 26.0
# Never nearer the anvil than this share of the radius.
const ESSENCE_NEAR := 0.5

@export var entry_spot: Vector2 = CENTRE + Vector2(0, 110)

var state: int = State.WAITING
var elapsed: float = 0.0
var heat: float = 0.0
var floods: int = 0
var flooded: Dictionary = {}
var flooding: int = -1
var front: float = RADIUS
var safe: float = SAFE_OTHER
var slain: int = 0
var essences: int = 0
var best: float = 0.0
var last_result: String = ""
var monsters: Array = []
var hud: Node = null
# THE SUITE'S SEAMS: the player and the class, standing in for the real ones.
var player_override: Node2D = null
var class_override: String = ""
# The chest (0.120.0), and where a run's time is sent - Api.post in the game,
# a stand-in in the suite.
var chest: Node2D = null
var best_post: Callable = Callable()
# The server's word on the best, after the last run's time was sent.
var server_best: int = 0

var _rng := RandomNumberGenerator.new()
var _hold: float = 0.0
var _count: float = 0.0
var _burn_clock: float = 0.0
var _spawn_clock: float = 0.0
var _essence: Node2D = null
var _essence_clock: float = 0.0
var _ground: TileMapLayer = null
var _lava: TileMapLayer = null
var _ground_saved: Dictionary = {}
var _flood_floor: Array = []
var _flood_lava: Array = []
var _front_clock: float = 0.0
var _marks: Node2D = null
var _reddened: CanvasItem = null
var _falls_speed: float = -1.0
# Walkway cells (16 px floor cells) and the run time each melts at.
var _cooled: Dictionary = {}
var _walk_clock: float = 0.0
# THE ANVIL'S GEAR: pieces forged this run, the hammer's progress on the next
# (seconds), and the wading time left.
var pieces: int = 0
var forging: float = 0.0
var wade_left: float = 0.0
# -1 reads the interact key; 0 or 1 is a test's hand on it.
var hammer_override: int = -1
var _hammering: bool = false
var _hammer_clock: float = 0.0
var _sparks: Node2D = null
# THE ERUPTION: how long the volcano has thrown, the rocks in the air
# ({"at", "left", "meteor"}), the next volley's clock, rocks landed.
var volcano_seconds: float = 0.0
var rocks: Array = []
var rocks_fallen: int = 0
var _erupt_clock: float = 0.0
var _rumble_clock: float = 0.0
var _jolt_left: float = 0.0
# THE ISLAND IS WIPED: "" until the heart is thrown, "falling", "landed".
var finale: String = ""
var finale_afterglow: float = 0.0
var _wiped: bool = false
var _sky: Node2D = null


func _ready() -> void:
	add_to_group(&"forge_run")
	_rng.randomize()
	var area: Node = get_parent()
	if area != null:
		_ground = area.get_node_or_null("ground") as TileMapLayer
		_lava = area.get_node_or_null("lava") as TileMapLayer
	if _ground != null:
		for cell in _ground.get_used_cells():
			_ground_saved[cell] = [_ground.get_cell_source_id(cell), _ground.get_cell_atlas_coords(cell)]
	_marks = Marks.new()
	_marks.run = self
	_sparks = Sparks.new()
	_sky = Wipe.new()
	_sky.set("run", self)
	if area != null:
		area.add_child.call_deferred(_marks)
		area.add_child.call_deferred(_sparks)
		area.add_child.call_deferred(_sky)
	hud = (load("res://src/world/forge/forgehud.gd") as GDScript).new()
	hud.set("run", self)
	add_child(hud)
	_size_light()
	# THE CHEST (0.120.0): what the fire sprites paid, kept on the server.
	chest = ChestScript.new()
	chest.name = "forgechest"
	chest.set("game", CHEST_GAME)
	chest.set("empty_words", "Your chest is empty - every fire sprite you slay pays into it.")
	chest.position = CHEST_SPOT
	chest.set("corridor", CHEST_BECKON)
	var props: Node = area.get_node_or_null("ysortworld/interactables") if area != null else null
	if props != null or area != null:
		(props if props != null else area).add_child.call_deferred(chest)


func _exit_tree() -> void:
	_unredden()


func _player() -> Node2D:
	if player_override != null:
		return player_override if is_instance_valid(player_override) else null
	return get_tree().get_first_node_in_group(&"player") as Node2D if is_inside_tree() else null


func is_tank() -> bool:
	if class_override != "":
		return class_override == TANK_CLASS
	return str(CharacterData.active_class_id()) == TANK_CLASS


func running() -> bool:
	return state == State.RUNNING


func countdown_left() -> float:
	return _count if state == State.COUNTDOWN else 0.0


func hold_share() -> float:
	return clampf(_hold / START_HOLD, 0.0, 1.0)


func _size_light() -> void:
	safe = SAFE_TANK if is_tank() else SAFE_OTHER
	var glow: PointLight2D = get_parent().get_node_or_null("forgeglow") as PointLight2D if get_parent() != null else null
	if glow != null:
		# The glow's texture is 256 px across: its reach is half that, scaled.
		glow.texture_scale = safe / 128.0


# =============================================================================
# THE GEOMETRY
# =============================================================================

static func at_angle(angle: float, r: float) -> Vector2:
	"""A point `r` from the centre, `angle` clockwise from north."""
	return CENTRE + Vector2(sin(angle), -cos(angle)) * r


static func slice_of(at: Vector2) -> int:
	var v: Vector2 = at - CENTRE
	return int(fposmod(atan2(v.x, -v.y) + PI / SLICES, TAU) / (TAU / SLICES)) % SLICES


static func slice_middle(k: int) -> float:
	return k * TAU / SLICES


static func floor_cell_mid(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * TILE + TILE / 2.0, cell.y * TILE + TILE / 2.0)


static func lava_cell_mid(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * LAVA_TILE + LAVA_TILE / 2.0, cell.y * LAVA_TILE + LAVA_TILE / 2.0)


static func lake_cells() -> Array:
	"""Every lava cell: under the whole island and the ring round it."""
	var out: Array = []
	var outer: float = RADIUS + BAND
	var reach: int = int(ceil(outer / LAVA_TILE)) + 1
	var middle := Vector2i(floori(CENTRE.x / LAVA_TILE), floori(CENTRE.y / LAVA_TILE))
	for y in range(-reach, reach + 1):
		for x in range(-reach, reach + 1):
			var cell := middle + Vector2i(x, y)
			if lava_cell_mid(cell).distance_to(CENTRE) <= outer:
				out.append(cell)
	return out


static func floor_at(at: Vector2, gone: Dictionary, light: float, going: int = -1, going_to: float = RADIUS) -> bool:
	"""Is there island under `at`, with the slices in `gone` flooded to the
	light and slice `going` flooded down to `going_to`?"""
	var d: float = at.distance_to(CENTRE)
	if d > RADIUS:
		return false
	if d <= light:
		return true
	var k: int = slice_of(at)
	if gone.has(k):
		return false
	if k == going:
		return d <= going_to
	return true


static func bubbles(cell: Vector2i, gone: Dictionary, light: float, going: int = -1, going_to: float = RADIUS) -> bool:
	"""A lava cell bubbles when it can be seen (not every corner under island)
	and island lies within BUBBLE_REACH of it."""
	var mid: Vector2 = lava_cell_mid(cell)
	var h: float = LAVA_TILE / 2.0 - 1.0
	var covered: bool = true
	for corner in [Vector2(-h, -h), Vector2(h, -h), Vector2(-h, h), Vector2(h, h)]:
		if not floor_at(mid + corner, gone, light, going, going_to):
			covered = false
			break
	if covered:
		return false
	var r: float = BUBBLE_REACH
	var s: float = BUBBLE_REACH * 0.7
	for o in [Vector2.ZERO, Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r),
			Vector2(s, s), Vector2(-s, s), Vector2(s, -s), Vector2(-s, -s)]:
		if floor_at(mid + o, gone, light, going, going_to):
			return true
	return false


func in_lava(at: Vector2) -> bool:
	return at.distance_to(CENTRE) <= RADIUS + BAND + 64.0 \
		and not floor_at(at, flooded, safe, flooding, front) and not walkway_at(at)


func walkway_at(at: Vector2) -> bool:
	return _cooled.has(Vector2i(floori(at.x / TILE), floori(at.y / TILE)))


func next_slice() -> int:
	return int(ORDER[floods]) if floods < SLICES else -1


func warning() -> bool:
	"""The next slice glows and the falls race: heat past WARN_AT, or a flood
	under way."""
	return running() and (flooding >= 0 or (floods < SLICES and heat >= WARN_AT))


func volcano() -> bool:
	"""Every slice gone: the volcano erupts."""
	return running() and floods >= SLICES and flooding < 0


func fill_seconds() -> float:
	return maxf(HEAT_FASTEST, HEAT_SECONDS * pow(HEAT_QUICKER, floods))


func spawn_gap() -> float:
	return maxf(SPAWN_FASTEST, SPAWN_EVERY * pow(SPAWN_QUICKER, floods))


func alive_cap() -> int:
	return ALIVE_FIRST + ALIVE_PER_FLOOD * floods


func spawn_count() -> int:
	return 1 + floods / 3


func health_scale() -> float:
	return 1.0 + HEALTH_PER_FLOOD * floods


# THE SCHEDULE THE SERVER HOLDS A KILL TO (0.120.0). The server cannot see a
# run, so it holds the fire sprites reported since the Go to what this could
# have sent by then (minigames/services.py forge_ceiling()) - AT ITS FASTEST:
# each phase is a flood's heat filling with no ice essence cooling it, and the
# flood itself left out, so the next phase's quicker spawns start sooner than
# they can. Written into gamedata.json by exportgamedata.gd (the scene's name
# turned into its enemy id), so after changing the spawns, the heat or the cap
# alive, re-export and copy the file to the API. _test_the_forge_pays()
# fails when gamedata.json no longer says what this does.
static func schedule() -> Dictionary:
	var phases: Array = []
	for k in SLICES:
		phases.append({
			"seconds": snappedf(maxf(HEAT_FASTEST, HEAT_SECONDS * pow(HEAT_QUICKER, k)), 0.01),
			"gap": snappedf(maxf(SPAWN_FASTEST, SPAWN_EVERY * pow(SPAWN_QUICKER, k)), 0.001),
			"count": 1 + k / 3,
		})
	return {
		"sprite_scenes": [SPRITE],
		"phases": phases,
		"volcano": {"gap": snappedf(maxf(SPAWN_FASTEST, SPAWN_EVERY * pow(SPAWN_QUICKER, SLICES)), 0.001),
			"count": 1 + SLICES / 3},
		"volcano_believed": VOLCANO_BELIEVED,
		"alive_most": ALIVE_FIRST + ALIVE_PER_FLOOD * SLICES,
	}


# =============================================================================
# THE RUN
# =============================================================================

func _process(delta: float) -> void:
	match state:
		State.WAITING:
			var player: Node2D = _player()
			if player != null and player.global_position.distance_to(CENTRE) <= START_REACH:
				_hold += delta
				if _hold >= START_HOLD:
					begin_countdown()
			else:
				_hold = 0.0
		State.COUNTDOWN:
			_count -= delta
			if _count <= 0.0:
				start_run()
		State.RUNNING:
			elapsed += delta
			_step_heat(delta)
			_step_flood(delta)
			_step_walkways(delta)
			_step_anvil(delta)
			_step_wading(delta)
			_step_fire(delta)
			_step_spawns(delta)
			_step_essence(delta)
			_step_eruption(delta)
			_step_rumble(delta)
	_paint_falls()
	_paint_tank()
	_process_chest()
	if _marks != null and is_instance_valid(_marks):
		_marks.queue_redraw()


func begin_countdown() -> void:
	_size_light()
	state = State.COUNTDOWN
	_count = COUNTDOWN_SECONDS
	_hold = 0.0
	if hud != null:
		hud.call("announce", "The forge is lit", "The lava rises in %d..." % int(COUNTDOWN_SECONDS))


func start_run() -> void:
	_size_light()
	state = State.RUNNING
	elapsed = 0.0
	heat = 0.0
	floods = 0
	flooded = {}
	flooding = -1
	front = RADIUS
	slain = 0
	essences = 0
	_burn_clock = BURN_TICK
	_spawn_clock = 1.0
	_essence_clock = ESSENCE_FIRST
	pieces = 0
	forging = 0.0
	wade_left = 0.0
	_hammering = false
	volcano_seconds = 0.0
	rocks_fallen = 0
	_erupt_clock = ERUPT_FIRST
	_rumble_clock = 0.0
	_jolt_left = 0.0
	_clear_rocks()
	finale = ""
	finale_afterglow = 0.0
	_wiped = false
	if hud != null:
		hud.call("announce", "Hold the forge", "Hold %s at the anvil to forge armour - it buys time in the lava"
			% ControlsPanel.action_key("interact"))


func _step_heat(delta: float) -> void:
	if floods >= SLICES or flooding >= 0:
		return
	heat = minf(1.0, heat + delta / fill_seconds())
	if heat >= 1.0:
		_flood_next()


func _flood_next() -> void:
	flooding = next_slice()
	front = RADIUS
	_front_clock = 0.0
	# The slice's floor, furthest first, taken as the front passes it.
	_flood_floor = []
	if _ground != null:
		for cell in _ground.get_used_cells():
			var mid: Vector2 = floor_cell_mid(cell)
			if slice_of(mid) == flooding and mid.distance_to(CENTRE) > safe:
				_flood_floor.append([mid.distance_to(CENTRE), cell])
	_flood_floor.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	# The lava cells whose bubbling can change: the slice's own and those
	# straddling its sides.
	_flood_lava = []
	if _lava != null:
		var h: float = LAVA_TILE / 2.0
		for cell in _lava.get_used_cells():
			var mid: Vector2 = lava_cell_mid(cell)
			var touches: bool = slice_of(mid) == flooding
			if not touches:
				for corner in [Vector2(-h, -h), Vector2(h, -h), Vector2(-h, h), Vector2(h, h)]:
					if slice_of(mid + corner) == flooding:
						touches = true
						break
			if touches:
				_flood_lava.append([mid.distance_to(CENTRE), cell])
	if hud != null:
		hud.call("announce", "The lava rises", "from the %s" % str(SLICE_NAMES[flooding]))


func _step_flood(delta: float) -> void:
	if flooding < 0:
		return
	front = maxf(safe, front - (RADIUS - safe) / FLOOD_SECONDS * delta)
	while not _flood_floor.is_empty() and float(_flood_floor[0][0]) > front:
		var entry: Array = _flood_floor.pop_front()
		if _ground != null:
			_ground.erase_cell(entry[1])
	_front_clock -= delta
	if _front_clock <= 0.0:
		_front_clock = FRONT_REPAINT
		_repaint(_flood_lava, front - 64.0, front + 140.0)
	if front <= safe:
		for entry in _flood_floor:
			if _ground != null:
				_ground.erase_cell(entry[1])
		_flood_floor = []
		flooded[flooding] = true
		var done: int = flooding
		flooding = -1
		floods += 1
		heat = 0.0
		_repaint(_flood_lava)
		_flood_lava = []
		# An essence lying in the slice is lost to it.
		if _essence != null and is_instance_valid(_essence) and slice_of(_essence.global_position) == done \
				and _essence.global_position.distance_to(CENTRE) > safe:
			_drop_essence()
		if hud != null and floods >= SLICES:
			hud.call("announce", "The volcano erupts", "Watch the glowing circles - the rocks fall faster and faster")


func _repaint(entries: Array, from_d: float = -INF, to_d: float = INF) -> void:
	"""Bubbling or still, as the island now lies, for the cells listed
	([distance, cell]) between from_d and to_d."""
	if _lava == null:
		return
	for entry in entries:
		var d: float = float(entry[0])
		if d < from_d or d > to_d:
			continue
		var cell: Vector2i = entry[1]
		var want: int = BUBBLING if bubbles(cell, flooded, safe, flooding, front) else STILL
		if _lava.get_cell_source_id(cell) != want:
			_lava.set_cell(cell, want, LAVA_CELL)


func _reset_map() -> void:
	"""The island back as built, and its lava with it."""
	if _ground != null:
		for cell in _cooled:
			if not _ground_saved.has(cell):
				_ground.erase_cell(cell)
	_cooled = {}
	if _ground != null:
		for cell in _ground_saved:
			if _ground.get_cell_source_id(cell) == -1:
				var saved: Array = _ground_saved[cell]
				_ground.set_cell(cell, int(saved[0]), saved[1])
	flooded = {}
	flooding = -1
	front = RADIUS
	if _lava != null:
		var all: Array = []
		for cell in _lava.get_used_cells():
			var mid: Vector2 = lava_cell_mid(cell)
			var d: float = mid.distance_to(CENTRE)
			# Only cells near the shore or inside it can have changed.
			if d <= RADIUS + BUBBLE_REACH + LAVA_TILE:
				all.append([d, cell])
		_repaint(all)


# =============================================================================
# THE TANK'S WALKWAYS
# =============================================================================

func aura_ellipse(player: Node2D) -> Array:
	"""[centre, half-width, half-height] of the tank's aura on the floor, read
	off its own shape (a capsule on its side), or AURA_HALF."""
	var half: Vector2 = AURA_HALF
	var offset: Vector2 = AURA_OFFSET
	var shape_node: CollisionShape2D = player.get_node_or_null(^"aura/collisionshape2d") as CollisionShape2D
	if shape_node != null and shape_node.shape is CapsuleShape2D:
		var capsule := shape_node.shape as CapsuleShape2D
		var lying: bool = absf(sin(shape_node.rotation)) > 0.7
		half = Vector2(capsule.height / 2.0, capsule.radius) if lying else Vector2(capsule.radius, capsule.height / 2.0)
		offset = (shape_node.get_parent() as Node2D).position + shape_node.position
	return [player.global_position + offset, half.x, half.y]


func _step_walkways(delta: float) -> void:
	_walk_clock -= delta
	if _walk_clock > 0.0:
		return
	_walk_clock = WALK_REPAINT
	var player: Node2D = _player()
	if player != null and is_tank() and player.get("aura_active") == true:
		_cool(aura_ellipse(player))
	# Melt what the ring has left behind long enough.
	var melted: Array = []
	for cell in _cooled:
		if float(_cooled[cell]) <= elapsed:
			melted.append(cell)
	for cell in melted:
		_cooled.erase(cell)
		if _ground != null and not floor_at(floor_cell_mid(cell), flooded, safe, flooding, front):
			_ground.erase_cell(cell)


func _cool(ellipse: Array) -> void:
	"""The lava inside the ring laid back as island, for WALK_LINGER more."""
	var mid: Vector2 = ellipse[0]
	var a: float = float(ellipse[1])
	var b: float = float(ellipse[2])
	var lo := Vector2i(floori((mid.x - a) / TILE), floori((mid.y - b) / TILE))
	var hi := Vector2i(floori((mid.x + a) / TILE), floori((mid.y + b) / TILE))
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var cell := Vector2i(x, y)
			var at: Vector2 = floor_cell_mid(cell)
			var d: Vector2 = at - mid
			if (d.x * d.x) / (a * a) + (d.y * d.y) / (b * b) > 1.0:
				continue
			if at.distance_to(CENTRE) > RADIUS + BAND - 24.0:
				continue
			if floor_at(at, flooded, safe, flooding, front):
				continue
			if not _cooled.has(cell) and _ground != null:
				var tile: Array = _ground_saved.get(cell, [1, Vector2i(1 + posmod(x * 7 + y * 3, 4), 1 + posmod(x * 5 + y * 11, 3))])
				_ground.set_cell(cell, int(tile[0]), tile[1])
			_cooled[cell] = elapsed + WALK_LINGER


func walkway_cells() -> int:
	return _cooled.size()


# =============================================================================
# FIRE
# =============================================================================

func _step_fire(delta: float) -> void:
	_burn_clock -= delta
	if _burn_clock > 0.0:
		return
	_burn_clock = BURN_TICK
	var player: Node2D = _player()
	if player == null or player.get("is_dying") == true:
		return
	var most: float = float(player.get("max_hp")) if player.get("max_hp") != null else 100.0
	# Every class, once its wading time is spent (0.121.0); the volcano's end
	# is its rocks now (THE VOLCANO ERUPTS), not a burn on everyone.
	if in_lava(player.global_position) and wade_left <= 0.0:
		_burn(player, maxi(1, roundi(most * LAVA_BURN)))


func _burn(player: Node2D, amount: int) -> void:
	"""On fire: the blow as fire, the effects' burn on top (its tint), and
	flames drawn on them."""
	Flames.on(player)
	StatusEffects.apply_to(player, StatusEffects.BURN, amount)
	if player.has_method("take_damage"):
		player.call("take_damage", amount, Element.Type.FIRE)


func redness() -> float:
	"""How red the tank's gear is now: with the heat, more in the lava."""
	if not running() or not is_tank():
		return 0.0
	var player: Node2D = _player()
	var wading: bool = player != null and in_lava(player.global_position)
	return clampf(0.25 * heat + 0.05 * floods + (0.45 if wading else 0.0) + (0.4 if volcano() else 0.0), 0.0, 1.0)


func _paint_tank() -> void:
	var red: float = redness()
	if red <= 0.0:
		_unredden()
		return
	var player: Node2D = _player()
	var sprite: CanvasItem = player.get_node_or_null(^"animatedsprite2d") as CanvasItem if player != null else null
	if sprite == null:
		return
	_reddened = sprite
	sprite.modulate = Color.WHITE.lerp(TANK_RED, red)


func _unredden() -> void:
	if _reddened != null and is_instance_valid(_reddened):
		_reddened.modulate = Color.WHITE
	_reddened = null


func _paint_falls() -> void:
	var want: float = (1.0 + FALLS_PER_FLOOD * floods) * (FALLS_WARNING if warning() else 1.0)
	if is_equal_approx(want, _falls_speed) or not is_inside_tree():
		return
	_falls_speed = want
	for fall in get_tree().get_nodes_in_group(&"forge_falls"):
		(fall as AnimatedSprite2D).speed_scale = want


# =============================================================================
# THE FIRE SPRITES
# =============================================================================

# =============================================================================
# THE ANVIL'S GEAR (0.121.0)
# =============================================================================

func piece_seconds() -> float:
	"""How long the hammer takes over a piece: the tank's swings count fully."""
	return PIECE_TANK if is_tank() else PIECE_OTHER


func wade_each() -> float:
	"""The wading time one piece buys: the tank's, about twice anyone else's."""
	return WADE_TANK if is_tank() else WADE_OTHER


func wade_most() -> float:
	return wade_each() * pieces


func forging_share() -> float:
	"""How far the hammer is through the next piece, 0 to 1."""
	return clampf(forging / piece_seconds(), 0.0, 1.0)


func hammering() -> bool:
	return _hammering


func next_piece() -> String:
	return str(PIECES[pieces]) if pieces < PIECES.size() else ""


func _hand_on_the_hammer() -> bool:
	if hammer_override >= 0:
		return hammer_override == 1
	return Input.is_action_pressed("interact")


func _step_anvil(delta: float) -> void:
	"""Standing still at the anvil holding the interact key: the hammer."""
	var player: Node2D = _player()
	var was: bool = _hammering
	_hammering = false
	if player == null or player.get("is_dying") == true or pieces >= PIECES.size():
		return
	if player.global_position.distance_to(CENTRE) > FORGE_REACH or not _hand_on_the_hammer():
		return
	var moving: Variant = player.get("velocity")
	if moving is Vector2 and (moving as Vector2).length() > STILL_SPEED:
		return
	_hammering = true
	if not was:
		_hammer_clock = 0.0
	_hammer_clock -= delta
	if _hammer_clock <= 0.0:
		_hammer_clock = HAMMER_EVERY
		if _sparks != null and is_instance_valid(_sparks):
			_sparks.call("strike", CENTRE + Vector2(0, -6), _rng)
		if is_inside_tree():
			Audio.play_at("attack_hit", CENTRE)
	forging += delta
	if forging >= piece_seconds():
		forging = 0.0
		var made: String = next_piece()
		pieces += 1
		wade_left = wade_most()
		if is_inside_tree():
			Audio.play("skill_up")
		if hud != null:
			hud.call("toast", "Forged: the %s  -  %d of %d, %d s in the lava" % [made, pieces, PIECES.size(), roundi(wade_most())])


func _step_wading(delta: float) -> void:
	"""Wading time drains in the lava and comes back on the floor."""
	var player: Node2D = _player()
	if player == null:
		return
	if in_lava(player.global_position):
		wade_left = maxf(0.0, wade_left - delta)
	else:
		wade_left = minf(wade_most(), wade_left + WADE_REFILL * delta)


func hit_scale(player: Node, element: int) -> float:
	"""Player.damage_taken() asks: the tank's fire hits on the island land at
	TANK_FIRE - "His armour repels fire". 1 for anything else."""
	if element != Element.Type.FIRE or not is_tank() or not (player is Node2D) or player != _player():
		return 1.0
	if (player as Node2D).global_position.distance_to(CENTRE) > RADIUS + BAND + 200.0:
		return 1.0
	return TANK_FIRE


# =============================================================================
# THE VOLCANO ERUPTS (0.121.0)
# =============================================================================

func erupt_gap() -> float:
	return maxf(ERUPT_FASTEST, ERUPT_GAP * pow(ERUPT_QUICKER, rocks_fallen))


func volley_size() -> int:
	return 1 + int(volcano_seconds / ERUPT_MORE_EVERY)


func erupt_hit() -> float:
	"""A rock's share of your health (before your armour and the game's half),
	more with every rock fallen."""
	return ERUPT_HIT + ERUPT_HIT_STEP * rocks_fallen


func rock_spot(aimed: bool) -> Vector2:
	"""Where a rock comes down: by the player (aimed), or anywhere on the
	light and a little past it."""
	var player: Node2D = _player()
	if aimed and player != null:
		var near: Vector2 = player.global_position + Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * ERUPT_AIM_SPREAD
		var off: Vector2 = near - CENTRE
		if off.length() > safe + ERUPT_PAST:
			near = CENTRE + off.normalized() * (safe + ERUPT_PAST)
		return near
	return CENTRE + Vector2.from_angle(_rng.randf() * TAU) * sqrt(_rng.randf()) * (safe + ERUPT_PAST)


func _step_eruption(delta: float) -> void:
	finale_afterglow = maxf(0.0, finale_afterglow - delta)
	if volcano():
		volcano_seconds += delta
		_erupt_clock -= delta
		if _erupt_clock <= 0.0:
			_erupt_clock = erupt_gap()
			if volcano_seconds < FINALE_AT - RAIN_STOPS:
				for i in volley_size():
					throw_rock(rock_spot(_rng.randf() < ERUPT_AIMED))
		if finale == "" and volcano_seconds >= FINALE_AT - FINALE_FALL:
			_call_finale()
		if finale == "falling" and volcano_seconds >= FINALE_AT:
			_finale_lands()
		if finale == "landed" and volcano_seconds >= FINALE_AT + FINALE_HOLD:
			_finale_ends()
			return
	var landed: Array = []
	for rock in rocks:
		rock["left"] = float(rock["left"]) - delta
		if float(rock["left"]) <= 0.0:
			landed.append(rock)
	for rock in landed:
		rocks.erase(rock)
		_rock_lands(rock["at"])


func throw_rock(at: Vector2) -> void:
	"""A rock on its way: a glowing circle now (Marks), the giant meteor's fall
	timed to land on it ERUPT_WARN from now."""
	var rock: Dictionary = {"at": at, "left": ERUPT_WARN, "meteor": null}
	var area: Node = get_parent()
	if area != null and is_inside_tree():
		var meteor: Node2D = MeteorScene.instantiate() as Node2D
		meteor.set("cosmetic", true)
		meteor.set("delay", maxf(0.0, ERUPT_WARN - Meteor.FALL_SECONDS))
		meteor.scale = Vector2.ONE * ERUPT_SCALE
		area.add_child(meteor)
		meteor.global_position = at
		meteor.reset_physics_interpolation()
		rock["meteor"] = meteor
	rocks.append(rock)


func finale_done() -> float:
	"""How far down the heart is: 0 thrown, 1 landed."""
	return clampf((volcano_seconds - (FINALE_AT - FINALE_FALL)) / FINALE_FALL, 0.0, 1.0)


func finale_shadow() -> float:
	"""The heart's shadow on the island now: from the anvil out over it all."""
	var done: float = finale_done()
	return lerpf(FINALE_SHADOW_FROM, FINALE_SHADOW, done * done)


func _call_finale() -> void:
	"""THE HEART THROWN: its shadow spreads, and FINALE_FALL later it lands."""
	finale = "falling"
	if hud != null:
		hud.call("announce", "The volcano throws its heart!", "Nowhere on the island is safe")


func _finale_lands() -> void:
	"""Every fire sprite gone in a blast, the anvil's own blast, a flash, the
	hardest jolt."""
	finale = "landed"
	finale_afterglow = FINALE_AFTERGLOW
	_clear_rocks()
	var area: Node = get_parent()
	if area != null and is_inside_tree():
		Blast.spawn(area, CENTRE, &"dynamite", FINALE_BLAST, false)
		Blast.spawn(area, CENTRE, &"meteor", FINALE_BLAST * 0.6, false)
		for m in monsters:
			if is_instance_valid(m) and m is Node2D:
				Blast.spawn(area, (m as Node2D).global_position, &"dynamite", 28.0, false)
		Audio.play("meteor_impact")
		Audio.play("explosion")
	_clear_monsters()
	var player: Node2D = _player()
	if player != null and player.has_method("shake_camera"):
		player.call("shake_camera", FINALE_SHAKE.x, FINALE_SHAKE.y)
		_jolt_left = FINALE_SHAKE.y
	if hud != null:
		hud.call("announce", "The island is wiped!", "The volcano took everything")
		if hud.has_method("flash"):
			hud.call("flash")


func _finale_ends() -> void:
	"""The run is over for everyone still standing."""
	_wiped = true
	var player: Node2D = _player()
	if player == null or not bool(knock_out(player)):
		end_run()


func _rock_lands(at: Vector2) -> void:
	rocks_fallen += 1
	var area: Node = get_parent()
	if area != null and is_inside_tree():
		Blast.spawn(area, at, &"dynamite", ERUPT_RADIUS, false)
	var player: Node2D = _player()
	if player == null:
		return
	var near: float = player.global_position.distance_to(at)
	if near <= IMPACT_NEAR and player.has_method("shake_camera"):
		var strength: float = IMPACT_SHAKE.x * (1.0 - 0.6 * near / IMPACT_NEAR)
		player.call("shake_camera", strength, IMPACT_SHAKE.y)
		_jolt_left = IMPACT_SHAKE.y
	if near <= ERUPT_RADIUS and player.get("is_dying") != true and player.has_method("take_damage"):
		var most: float = float(player.get("max_hp")) if player.get("max_hp") != null else 100.0
		player.call("take_damage", maxi(1, roundi(most * erupt_hit())), Element.Type.FIRE)


func rumbling() -> bool:
	"""The ground shakes from the last flood on."""
	return running() and (volcano() or (floods == SLICES - 1 and flooding >= 0))


func rumble_px() -> float:
	if finale == "falling":
		return lerpf(RUMBLE_MOST, FINALE_RUMBLE, finale_done())
	return minf(RUMBLE_MOST, RUMBLE_PX + RUMBLE_GROW * volcano_seconds) if volcano() else RUMBLE_PX * 0.5


func _step_rumble(delta: float) -> void:
	_jolt_left = maxf(0.0, _jolt_left - delta)
	if not rumbling() or _jolt_left > 0.0:
		return
	_rumble_clock -= delta
	if _rumble_clock > 0.0:
		return
	_rumble_clock = RUMBLE_EVERY
	var player: Node2D = _player()
	if player != null and player.has_method("shake_camera"):
		player.call("shake_camera", rumble_px(), RUMBLE_EVERY + 0.05)


func _clear_rocks() -> void:
	for rock in rocks:
		var meteor: Variant = rock.get("meteor")
		if meteor is Node and is_instance_valid(meteor):
			(meteor as Node).queue_free()
	rocks = []


func _step_spawns(delta: float) -> void:
	if finale != "":
		return
	_spawn_clock -= delta
	if _spawn_clock > 0.0:
		return
	_spawn_clock = spawn_gap()
	for i in spawn_count():
		if living() >= alive_cap():
			return
		_bring(SPRITE, edge_spot(), health_scale())


func edges() -> Array:
	"""Every edge where lava meets island, with its length:
	["rim", slice], ["light", slice], ["side", spoke, flooded side]."""
	var out: Array = []
	for k in SLICES:
		if k == flooding:
			continue
		if flooded.has(k):
			out.append(["light", k, safe * TAU / SLICES])
		else:
			out.append(["rim", k, RADIUS * TAU / SLICES])
	for k in SLICES:
		var before: int = (k + SLICES - 1) % SLICES
		var a: bool = flooded.has(before)
		var b: bool = flooded.has(k)
		if a != b:
			out.append(["side", k, RADIUS - safe, -1.0 if a else 1.0])
	return out


func edge_spot() -> Vector2:
	"""Just inside the lava past an edge, by its length, clear of the player."""
	var all: Array = edges()
	var total: float = 0.0
	for e in all:
		total += float(e[2])
	var player: Node2D = _player()
	var mine: Vector2 = player.global_position if player != null else entry_spot
	var at: Vector2 = at_angle(0.0, RADIUS + EDGE_IN)
	for attempt in 16:
		var pick: float = _rng.randf() * total
		var chosen: Array = all[0] if not all.is_empty() else ["rim", 0, 1.0]
		for e in all:
			pick -= float(e[2])
			if pick <= 0.0:
				chosen = e
				break
		var half: float = TAU / SLICES / 2.0
		match str(chosen[0]):
			"rim":
				at = at_angle(slice_middle(int(chosen[1])) + _rng.randf_range(-half, half), RADIUS + EDGE_IN)
			"light":
				at = at_angle(slice_middle(int(chosen[1])) + _rng.randf_range(-half * 0.9, half * 0.9), safe + EDGE_IN)
			_:
				var r: float = _rng.randf_range(safe + 40.0, RADIUS - 20.0)
				var spoke: float = slice_middle(int(chosen[1])) - half
				# Into the flooded side: -1 when it is the slice before.
				at = at_angle(spoke + float(chosen[3]) * EDGE_IN / r, r)
		if at.distance_to(mine) >= SPAWN_CLEAR and in_lava(at):
			return at
	return at


func living() -> int:
	var still: Array = []
	var count: int = 0
	for m in monsters:
		if not is_instance_valid(m):
			continue
		if int(m.get("hp")) > 0 and not bool(m.get("_death_resolved")):
			count += 1
		else:
			_note_fallen(m)
		still.append(m)
	monsters = still
	return count


func _bring(enemy_id: String, at: Vector2, health: float) -> Node2D:
	var path: String = "res://scene/enemy/%s.tscn" % enemy_id
	var packed: PackedScene = load(path) as PackedScene if ResourceLoader.exists(path) else null
	var container: Node = get_parent().get_node_or_null("ysortworld/enemies") if get_parent() != null else null
	if packed == null or container == null:
		return null
	var monster := packed.instantiate() as Node2D
	monster.set_meta(MARK, true)
	monster.set_meta(CHEST_META, CHEST_GAME)
	if "notice_range" in monster:
		monster.set("notice_range", NOTICE)
	if "leash_range" in monster:
		monster.set("leash_range", NOTICE)
	# Before add_child(): BaseEnemy._ready() reads its spot as home.
	monster.position = at
	container.add_child(monster)
	monster.global_position = at
	monster.reset_physics_interpolation()
	if "spawn_position" in monster:
		monster.set("spawn_position", at)
	if health > 1.0 and "max_hp" in monster:
		var most: int = roundi(float(monster.get("max_hp")) * health)
		monster.set("max_hp", most)
		monster.set("hp", most)
		if monster.has_method("_refresh_health_display"):
			monster.call("_refresh_health_display")
	monster.tree_exiting.connect(_on_monster_gone.bind(monster))
	monsters.append(monster)
	return monster


func _on_monster_gone(monster: Node) -> void:
	if int(monster.get("hp")) <= 0:
		_note_fallen(monster)


func _note_fallen(monster: Node) -> void:
	if not running() or monster.has_meta(&"forge_fallen"):
		return
	monster.set_meta(&"forge_fallen", true)
	slain += 1


func _clear_monsters() -> void:
	for m in monsters:
		if is_instance_valid(m):
			(m as Node).tree_exiting.disconnect(_on_monster_gone)
			(m as Node).queue_free()
	monsters.clear()


# =============================================================================
# ICE ESSENCE
# =============================================================================

func _step_essence(delta: float) -> void:
	if _essence != null and is_instance_valid(_essence):
		var left: float = float(_essence.get("left")) - delta
		_essence.set("left", left)
		var player: Node2D = _player()
		if player != null and player.global_position.distance_to(_essence.global_position) <= ESSENCE_REACH:
			take_essence()
		elif left <= 0.0:
			_drop_essence()
		return
	_essence_clock -= delta
	if _essence_clock <= 0.0:
		_essence_clock = ESSENCE_EVERY
		_lay_essence()


func essence_spot() -> Vector2:
	"""Out in an open slice - never the one about to flood - far from the
	anvil; INF when there is none."""
	var open: Array = []
	for k in SLICES:
		if not flooded.has(k) and k != flooding and k != next_slice():
			open.append(k)
	if open.is_empty():
		return Vector2.INF
	var k: int = open[_rng.randi_range(0, open.size() - 1)]
	var half: float = TAU / SLICES / 2.0
	return at_angle(slice_middle(k) + _rng.randf_range(-half * 0.8, half * 0.8),
		_rng.randf_range(RADIUS * ESSENCE_NEAR, RADIUS - 70.0))


func _lay_essence() -> void:
	var at: Vector2 = essence_spot()
	var props: Node = get_parent().get_node_or_null("ysortworld/props") if get_parent() != null else null
	if at == Vector2.INF or props == null:
		return
	_essence = Essence.new()
	_essence.set("left", ESSENCE_LIFE)
	_essence.position = at
	props.add_child(_essence)
	_essence.reset_physics_interpolation()
	if hud != null:
		hud.call("toast", "Ice essence to the %s" % str(SLICE_NAMES[slice_of(at)]))


func take_essence() -> void:
	heat = maxf(0.0, heat - ESSENCE_COOL)
	essences += 1
	_drop_essence()
	if hud != null:
		hud.call("toast", "Ice essence - the forge cools")


func _drop_essence() -> void:
	if _essence != null and is_instance_valid(_essence):
		_essence.queue_free()
	_essence = null


# =============================================================================
# THE END
# =============================================================================

func knock_out(player: Node) -> bool:
	"""Player.take_damage(), on the blow that would kill: here you wake beside
	the anvil on 1 health, every effect cleared, and the run is over. Off the
	island, false - the ordinary death goes ahead."""
	if player == null or not (player is Node2D) or not is_inside_tree():
		return false
	var body := player as Node2D
	if body.global_position.distance_to(CENTRE) > RADIUS + BAND + 200.0:
		return false
	player.set("hp", 1)
	var effects: Node = StatusEffects.of(player)
	if effects != null and effects.has_method("clear_all"):
		effects.call("clear_all")
	body.global_position = entry_spot
	body.reset_physics_interpolation()
	if body.has_method("snap_camera"):
		body.call("snap_camera")
	if state != State.WAITING:
		end_run()
	return true


static func clock_text(seconds: float) -> String:
	var s: int = int(seconds)
	return "%d:%02d" % [s / 60, s % 60]


func end_run() -> void:
	var held: float = elapsed
	var words: String = "The forge held %s  -  %d of %d slices flooded  -  %d slain" % [clock_text(held), floods, SLICES, slain]
	if _wiped:
		words = "The volcano took the island at %s  -  %d slain" % [clock_text(held), slain]
	if essences > 0:
		words += "  -  %d ice essence" % essences
	if pieces > 0:
		words += "  -  %d of %d armour forged" % [pieces, PIECES.size()]
	last_result = words
	best = maxf(best, held)
	_send_time(held)
	_clear_monsters()
	BulletZone.clear_enemy_shots(self)
	_drop_essence()
	_clear_rocks()
	state = State.WAITING
	heat = 0.0
	floods = 0
	pieces = 0
	forging = 0.0
	wade_left = 0.0
	_hammering = false
	volcano_seconds = 0.0
	finale = ""
	_wiped = false
	_flood_floor = []
	_flood_lava = []
	_reset_map()
	_unredden()
	if hud != null:
		hud.call("show_result", words)


func _send_time(held: float) -> void:
	"""The run's time to the server, which keeps the best (0.120.0). Not
	awaited by end_run(): the result is said now, the server's best when it
	answers."""
	if held < 1.0:
		return
	if not best_post.is_valid() and not Api.is_logged_in():
		return
	var body: Dictionary = {"game": CHEST_GAME, "seconds": int(held)}
	var res: Dictionary
	if best_post.is_valid():
		res = await best_post.call("/api/minigames/best", body)
	else:
		res = await Api.post("/api/minigames/best", body, 6.0)
	if not is_instance_valid(self) or not is_inside_tree() or not res.get("ok", false):
		return
	var data: Dictionary = res.get("data", {}) if res.get("data") is Dictionary else {}
	server_best = maxi(server_best, int(data.get("best", 0)))
	best = maxf(best, float(server_best))
	if bool(data.get("new_best", false)) and hud != null and hud.has_method("toast"):
		hud.call("toast", "A new best: %s" % clock_text(float(server_best)))


func _process_chest() -> void:
	"""The chest's arrow is for a player near the anvil while no run is on."""
	if chest != null and is_instance_valid(chest):
		chest.set("corridor", Rect2() if state != State.WAITING else CHEST_BECKON)


# =============================================================================
# WHAT IS DRAWN
# =============================================================================

class Marks extends Node2D:
	## The light's rim on the floor, and the next slice glowing as it warms.
	var run: Node = null

	func _init() -> void:
		name = "forgemarks"
		z_as_relative = false
		z_index = -9

	func _draw() -> void:
		if run == null:
			return
		var light: float = float(run.get("safe"))
		draw_arc(CENTRE, light, 0.0, TAU, 96, Color(1.0, 0.82, 0.5, 0.35), 2.0)
		# THE HAMMER (0.121.0): a ring round the anvil filling as a piece is
		# forged.
		var share: float = float(run.call("forging_share"))
		if share > 0.0:
			draw_arc(CENTRE, 30.0, -PI / 2.0, -PI / 2.0 + TAU * share, 48, Color(1.0, 0.8, 0.35, 0.9), 3.0)
		# THE ISLAND IS WIPED (0.122.0): the heart's shadow spreading over the
		# island, then the blast's afterglow - the Stand's star's way.
		var heart: String = str(run.get("finale"))
		if heart == "falling":
			var done: float = float(run.call("finale_done"))
			draw_set_transform(CENTRE, 0.0, Vector2(1.0, 0.75))
			var r: float = float(run.call("finale_shadow"))
			draw_circle(Vector2.ZERO, r, Color(0.0, 0.0, 0.0, 0.15 + 0.25 * done))
			draw_circle(Vector2.ZERO, r * 0.6, Color(0.0, 0.0, 0.0, 0.1 + 0.2 * done))
			draw_arc(Vector2.ZERO, r, 0.0, TAU, 128, Color(1.0, 0.45, 0.15, 0.5 + 0.4 * done), 6.0)
			draw_arc(Vector2.ZERO, r * 0.95, 0.0, TAU, 128, Color(1.0, 0.75, 0.3, 0.3 + 0.3 * done), 3.0)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var after: float = float(run.get("finale_afterglow")) / FINALE_AFTERGLOW
		if after > 0.0:
			draw_set_transform(CENTRE, 0.0, Vector2(1.0, 0.75))
			draw_circle(Vector2.ZERO, FINALE_SHADOW, Color(1.0, 0.45, 0.1, 0.25 * after))
			draw_circle(Vector2.ZERO, FINALE_SHADOW * 0.6, Color(1.0, 0.6, 0.2, 0.3 * after))
			draw_circle(Vector2.ZERO, 120.0, Color(0.15, 0.08, 0.06, 0.85 * after))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# THE ERUPTION (0.121.0): where each rock will land, brighter as it
		# comes.
		for rock in run.get("rocks"):
			var come: float = 1.0 - clampf(float(rock["left"]) / ERUPT_WARN, 0.0, 1.0)
			var at: Vector2 = rock["at"]
			draw_circle(at, ERUPT_RADIUS, Color(1.0, 0.3, 0.05, 0.12 + 0.28 * come))
			draw_arc(at, ERUPT_RADIUS, 0.0, TAU, 40, Color(1.0, 0.65, 0.2, 0.55 + 0.4 * come), 2.0)
			draw_arc(at, ERUPT_RADIUS * (1.0 - come), 0.0, TAU, 40, Color(1.0, 0.9, 0.5, 0.7), 1.5)
		if not bool(run.call("warning")):
			return
		var k: int = int(run.get("flooding"))
		if k < 0:
			k = int(run.call("next_slice"))
		if k < 0:
			return
		var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 160.0)
		var half: float = TAU / SLICES / 2.0
		var mid: float = k * TAU / SLICES
		var outer: float = float(run.get("front")) if int(run.get("flooding")) == k else RADIUS
		var points := PackedVector2Array()
		for i in 25:
			var a: float = mid - half + 2.0 * half * i / 24.0
			points.append(CENTRE + Vector2(sin(a), -cos(a)) * light)
		for i in 25:
			var a: float = mid + half - 2.0 * half * i / 24.0
			points.append(CENTRE + Vector2(sin(a), -cos(a)) * outer)
		draw_colored_polygon(points, Color(1.0, 0.35, 0.1, 0.08 + 0.14 * pulse))


class Wipe extends Node2D:
	## The heart's landing in the world (0.122.0), over everything: white
	## rings racing out across the island as the afterglow fades.
	var run: Node = null
	var _shown: bool = false

	func _init() -> void:
		name = "forgewipe"
		z_as_relative = false
		z_index = SKY_Z

	func _process(_delta: float) -> void:
		if run == null or not is_instance_valid(run):
			return
		if float(run.get("finale_afterglow")) > 0.0:
			queue_redraw()
			_shown = true
		elif _shown:
			queue_redraw()
			_shown = false

	func _draw() -> void:
		if run == null or not is_instance_valid(run):
			return
		var after: float = float(run.get("finale_afterglow")) / FINALE_AFTERGLOW
		if after <= 0.0:
			return
		var grown: float = 1.0 - after
		draw_set_transform(CENTRE, 0.0, Vector2(1.0, 0.75))
		draw_arc(Vector2.ZERO, FINALE_SHADOW * (0.3 + 0.9 * grown), 0.0, TAU, 128, Color(1.0, 0.95, 0.8, 0.9 * after), 10.0)
		draw_arc(Vector2.ZERO, FINALE_SHADOW * (0.4 + 1.0 * grown), 0.0, TAU, 128, Color(1.0, 0.7, 0.4, 0.5 * after), 5.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


class Sparks extends Node2D:
	## The hammer's sparks over the anvil (0.121.0): a handful of hot squares
	## thrown up at each swing, falling and fading.
	var bits: Array = []

	func _init() -> void:
		name = "forgesparks"
		z_as_relative = false
		z_index = 5

	func strike(at: Vector2, rng: RandomNumberGenerator) -> void:
		for i in 7:
			bits.append({"at": at, "v": Vector2(rng.randf_range(-70.0, 70.0), rng.randf_range(-130.0, -50.0)),
				"life": rng.randf_range(0.3, 0.55)})

	func _process(delta: float) -> void:
		if bits.is_empty():
			return
		var kept: Array = []
		for bit in bits:
			bit["life"] = float(bit["life"]) - delta
			if float(bit["life"]) <= 0.0:
				continue
			bit["v"] = (bit["v"] as Vector2) + Vector2(0, 260.0) * delta
			bit["at"] = (bit["at"] as Vector2) + (bit["v"] as Vector2) * delta
			kept.append(bit)
		bits = kept
		queue_redraw()

	func _draw() -> void:
		for bit in bits:
			var hot: float = clampf(float(bit["life"]) / 0.4, 0.0, 1.0)
			draw_rect(Rect2((bit["at"] as Vector2).round(), Vector2(2, 2)), Color(1.0, 0.75 + 0.25 * hot, 0.3 + 0.5 * hot, hot))


class Essence extends Node2D:
	## The ice essence lying on the island: the art pack's icon, a cold ring
	## that breathes, blinking its last three seconds.
	var left: float = 14.0

	func _ready() -> void:
		var art := Sprite2D.new()
		art.name = "art"
		art.texture = load(ESSENCE_ART) as Texture2D
		art.scale = Vector2(1.5, 1.5)
		art.position = Vector2(0, -12)
		art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(art)

	func _process(_delta: float) -> void:
		visible = left > 3.0 or int(Time.get_ticks_msec() / 150) % 2 == 0
		queue_redraw()

	func _draw() -> void:
		var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 200.0)
		draw_arc(Vector2.ZERO, 14.0 + 4.0 * pulse, 0.0, TAU, 32, Color(0.55, 0.9, 1.0, 0.75), 2.0)


class Flames extends Node2D:
	## Flames on a player who is burning: drawn while the effects' burn lasts.
	const NODE := &"forgeflames"
	var host: Node2D = null

	static func on(body: Node2D) -> void:
		if body.get_node_or_null(NodePath(String(NODE))) != null:
			return
		var made := Flames.new()
		made.name = String(NODE)
		made.host = body
		body.add_child(made)

	func _init() -> void:
		z_index = 2

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var fx: Node = StatusEffects.of(host)
		if fx == null or float(fx.get("burn_left")) <= 0.0:
			return
		var t: float = Time.get_ticks_msec() / 1000.0
		for i in 5:
			var x: float = -10.0 + 5.0 * i
			var lift: float = 14.0 + 6.0 * sin(t * 9.0 + i * 1.7)
			var base_y: float = -6.0 - 4.0 * absf(2.0 - i)
			var sway: float = 2.0 * sin(t * 7.0 + i)
			draw_colored_polygon(PackedVector2Array([Vector2(x - 3.5, base_y), Vector2(x + 3.5, base_y),
				Vector2(x + sway, base_y - lift)]), Color(1.0, 0.45, 0.1, 0.85))
			draw_colored_polygon(PackedVector2Array([Vector2(x - 1.8, base_y), Vector2(x + 1.8, base_y),
				Vector2(x + sway * 0.6, base_y - lift * 0.6)]), Color(1.0, 0.9, 0.35, 0.9))
