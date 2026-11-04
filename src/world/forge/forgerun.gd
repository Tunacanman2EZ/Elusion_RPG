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
#              SLICES are gone, THE VOLCANO: everyone burns, harder each
#              tick (FINAL_BURN), until they fall.
#
# THE LIGHT THE LAVA NEVER ENTERS: SAFE_TANK (294 px - the tank's own light,
# playerlight.tscn's 256 px glow at texture_scale 2.3, round the anvil) when
# the player is a tank, SAFE_OTHER (210 px, the anvil's own glow) otherwise.
# The anvil's glow is sized to it.
#
# FIRE: anyone but the tank catches fire in the lava - LAVA_BURN of their
# health a tick through Player.take_damage() as fire, and the effects' burn,
# drawn as flames on them (Flames). The tank does not: his gear turns red
# (TANK_RED, more in the lava and as the heat climbs). In THE VOLCANO the tank
# burns too.
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
# WHAT IT PAYS, IN STEP 1: nothing. Forging, the legacy armour, a party of
# four and the high-score board are the next steps.
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
const FINAL_BURN := 0.06
const FINAL_BURN_STEP := 0.01
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

# ---- THE TANK'S WALKWAYS ------------------------------------------------------
const WALK_LINGER := 3.0
const WALK_REPAINT := 0.1
# The aura's ellipse when it cannot be read off the tank (tank.tscn: a capsule
# 42.3 round and 147.6 long, laid on its side, 13.5 px over his feet).
const AURA_HALF := Vector2(73.8, 42.3)
const AURA_OFFSET := Vector2(-0.9, -13.5)

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

var _rng := RandomNumberGenerator.new()
var _hold: float = 0.0
var _count: float = 0.0
var _burn_clock: float = 0.0
var _final_ticks: int = 0
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
	if area != null:
		area.add_child.call_deferred(_marks)
	hud = (load("res://src/world/forge/forgehud.gd") as GDScript).new()
	hud.set("run", self)
	add_child(hud)
	_size_light()


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
	"""Every slice gone: everyone burns."""
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
			_step_fire(delta)
			_step_spawns(delta)
			_step_essence(delta)
	_paint_falls()
	_paint_tank()
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
	_final_ticks = 0
	_spawn_clock = 1.0
	_essence_clock = ESSENCE_FIRST
	if hud != null:
		hud.call("announce", "Hold the forge", "Fire sprites step out of the lava - the heat floods a slice when full")


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
			hud.call("announce", "The volcano wakes", "Every slice is gone - the heat takes everyone now")


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
	if volcano():
		var share: float = FINAL_BURN + FINAL_BURN_STEP * _final_ticks
		_final_ticks += 1
		_burn(player, maxi(1, roundi(most * share)))
	elif in_lava(player.global_position) and not is_tank():
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

func _step_spawns(delta: float) -> void:
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
	if essences > 0:
		words += "  -  %d ice essence" % essences
	last_result = words
	best = maxf(best, held)
	_clear_monsters()
	_drop_essence()
	state = State.WAITING
	heat = 0.0
	floods = 0
	_flood_floor = []
	_flood_lava = []
	_reset_map()
	_unredden()
	if hud != null:
		hud.call("show_result", words)


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
