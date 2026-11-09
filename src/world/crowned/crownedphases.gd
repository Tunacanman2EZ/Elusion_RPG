# crownedphases.gd - THE CROWNED, REMADE, step 2 (0.134.1): its last three
# phases and the lying room, from the commit folder's CROWNED_PLAN.txt. The
# owner, of the plan: "sounds good".
#
# A child of crownedfight.gd, which steps it while the fight is on with the
# boss's share of health left. Every game runs its own, for its own player,
# as the floor's hazards are (descentlands.gd): nothing new on the wire.
#
#   2. THE SEALING (below SEALING_FROM, the mage's chapter): meteors fall in
#      storms across the floor and at you (descentlands.gd "meteor": a warning
#      circle, a fireball, a scorch; A STORM, NOT A FEW, below, since
#      0.134.7); and the lava creeps in from the walls - the
#      floor taken away ring by ring (LAVA_TILE, the town's own bubbling lava
#      under it), to LAVA_MOST rings and back (lava_depth_at()), its front
#      glowing before it comes. Lava burns (LAVA_TIMES of a hazard). It came
#      5 rings in; the owner: "that is actually pretty cool for the lave to
#      get closer to the middle" - 7, then "bring the lava even closer to the
#      middle": 9 - and then "we want player be be forced into a box
#      basically": it closes in from every side at once to a square box,
#      BOX_CELLS lava cells (256 px) a side round the middle - faster from the
#      long sides (dry_rect()), LAVA_MOST steps of LAVA_RISE. And the rift's
#      volcano windows show only while it floods (crownedrift.gd `flood`).
#   3. THE TRAP (below TRAP_FROM, the warrior's): it calls a horde - the
#      Endless's swarm (swarm.gd), HORDE_CROWD slimes (HORDE_PHONE on a
#      phone, endlessrun.gd on_phone()), of every land - while lasers come
#      every TRAP_LASER_GAP in one of LASER_SHAPES, in turn: the Crowned's
#      own hunting wheel (here, below), then descentlands.gd's sweep wall
#      to wall, cage closing on you and beam that pulses to a beat.
#   4. THE TEAR (below TEAR_FROM, the cloth's): pieces of the floor
#      (TEAR_PIECE square) crack (TEAR_WARN) and fall into the rift beneath
#      (crownedrift.gd shows through), and knit back after TEAR_OPEN. Every
#      TEAR_GAP a pattern is cut across the whole map (cut_pattern(): a row
#      or a column with gaps, a ring round the middle, or a scatter kept
#      apart), TEAR_PATTERNS of them at once - and always the piece under
#      you. The owner, playing it: "there need to be more map cutting i think
#      patterns need to be spread out more", then "more squares", and "if
#      we doubles the size of the squares might be cooler" (128 px). Fall in:
#      TEAR_TIMES of a hazard, and you climb out on the nearest solid floor.
#      The Crowned flickers through all seven lands (FLICKER_SECONDS): its
#      kit and its colour change each time.
#
# THE LYING ROOM, phases 2 to 4: LIE_SHARE of what warns before it falls is an
# illusion (descentlands.gd false_share - the circle shimmers); and every
# LIE_GAP or so the walls shimmer and fade a moment, or the floor washes in
# the wrong land's colour.
#
# When the fight ends (the boss falls or turns away), end() puts the room
# back: the floor whole, the lava gone, the horde gone, the walls solid.
#
# No class_name: preload it by path.
extends Node2D

const RiftScript := preload("res://src/world/crowned/crownedrift.gd")
const StatusEffects := preload("res://src/characters/statuseffects.gd")
const SwarmScript := preload("res://src/world/endless/swarm.gd")
const EndlessRunScript := preload("res://src/world/endless/endlessrun.gd")
const LandsScript := preload("res://src/world/descent/descentlands.gd")

const SEALING_FROM := 0.75
const TRAP_FROM := 0.5
const TEAR_FROM := 0.25
const NAMES := {2: "The Sealing", 3: "The Trap", 4: "The Tear"}

# A STORM, NOT A FEW (0.134.7). The owner: "i want it to flood meteors in
# the map instead of dropping a few remember with 4 people the game balance
# is rough". It was one meteor at your feet every two seconds, sometimes two.
# Now, every STORM_GAP_LEAST to STORM_GAP_MOST seconds (random, so it cannot
# be counted), a storm of STORM_SECONDS: meteors fall at STORM_RATE a second
# across the floor the lava has left (dry_rect()), STORM_AIMED of them at
# you - each with its warning circle, as before. The rate grows by
# STORM_PARTY_SHARE for every other player fighting the Crowned
# (bossenemy.gd fight_targets()), up to STORM_PARTY_MOST: a boss whose
# health already grows with its party now hits like it too. Each game drops
# its own storm for its own player, as every lands hazard is (nothing is
# sent), so four players each dodge a storm two and a half times as thick.
const STORM_FIRST := 2.0
const STORM_GAP_LEAST := 6.5
const STORM_GAP_MOST := 9.5
const STORM_SECONDS := 3.5
const STORM_RATE := 7.0
const STORM_PARTY_SHARE := 0.5
const STORM_PARTY_MOST := 4
const STORM_AIMED := 0.3
# ON THE LAND, NOT THE LAVA (the same 0.134.7; the owner, of the clip:
# "lets keep them on the land not the lava"). A meteor's whole warning
# circle is on dry floor - STORM_MARGIN is its radius and a little - and
# dry where the lava will be when it lands (a meteor waits METEOR_WARN, and
# the lava may rise in that time), the ones aimed at you included.
const STORM_MARGIN := 42.0
const LAVA_TILE := 32
const LAVA_CELL := Vector2i(0, 5)
const LAVA_MOST := 12
const LAVA_RISE := 0.9
const BOX_CELLS := 8
const LAVA_HOLD := 4.0
const LAVA_FALL := 0.5
const LAVA_REST := 3.0
const LAVA_TIMES := 0.8
const LAVA_WARN := 1.0

const HORDE_CROWD := 300
const HORDE_PHONE := 150
const HORDE_RATE := 60.0
const HORDE_HP := 90.0
const HORDE_SPEED := 85.0
const HORDE_TOUCH := 9
const HORDE_RECOLOUR := 4.0
const TRAP_LASER_GAP := 5.0
const TRAP_LASER_FIRST := 2.0
const LASER_SHAPES := ["wheel", "sweep", "cage", "pulse"]
# THE HUNTING WHEEL (0.134.7), in the place of the X and of the lands' thin
# pinwheel. The owner, of the X: "i do not really like it"; of the gaze
# that first took its place: "a pinwheel laser might be even cooler", and
# he chose one that hunts you, with "5 beams". WHEEL_ARMS thick beams from
# the Crowned's eye to the walls, turning together:
#   - opened with you in the middle of a gap, WHEEL_WARN of threads first;
#   - the arm coming round at you sets the pace - WHEEL_SLOW where you
#     stand while it is a whole gap away, rising to WHEEL_FAST as it closes
#     (a walk is 90, player.gd speed): it creeps, then lunges. Close in to
#     the eye it is held to WHEEL_TURN_MOST, but a gap there is short;
#   - it turns one way, then the other, every WHEEL_FLIP_LEAST to
#     WHEEL_FLIP_MOST at random, easing through a stop (WHEEL_EASE) - the
#     stop is the tell;
#   - an arm on you hits WHEEL_TIMES as the Crowned's land every WHEEL_TICK
#     (the lands' TOUCH_GAP), through the lands' `_env_hit()`.
# So you live in a gap and move with it. Drawn by this script
# (`_wheel_view`). Each game turns its own wheel at its own player, as
# every other shape is cast at its own player.
const WHEEL_ARMS := 5
const WHEEL_WARN := 1.0
const WHEEL_SECONDS := 6.0
const WHEEL_SLOW := 40.0
const WHEEL_FAST := 80.0
const WHEEL_TURN_MOST := 1.4
const WHEEL_EASE := 1.6
const WHEEL_FLIP_LEAST := 1.5
const WHEEL_FLIP_MOST := 3.0
const WHEEL_HALF := 13.0
const WHEEL_SLACK := 6.0
const WHEEL_TICK := 0.6
const WHEEL_TIMES := 0.8
const WHEEL_EYE := Vector2(0, -6)
const WHEEL_FADE := 0.3
const BACK_WALL_GAP := 6.0

const TEAR_PIECE := 128
# Lava cells along a tear piece's side, and floor cells along a lava cell's.
const TEAR_PER := 4
const FLOOR_PER := 2
const TEAR_GAP := 1.8
const TEAR_PATTERNS := 2
const TEAR_SCATTER := 6
const TEAR_SCATTER_APART := 2
const TEAR_MOST := 20
const PATTERNS := ["row", "column", "ring", "scatter"]
const TEAR_WARN := 1.4
const TEAR_OPEN := 7.0
const TEAR_DROP := 0.5
const TEAR_TIMES := 2.0
const FLICKER_SECONDS := 1.6

const LIE_SHARE := 0.25
const LIE_GAP_LEAST := 2.5
const LIE_GAP_MOST := 5.0
const LIE_WALLS := 3

const LANDS := [Element.Type.LIGHT, Element.Type.WIND, Element.Type.WATER, Element.Type.ICE,
	Element.Type.EARTH, Element.Type.FIRE, Element.Type.DARK]

# Set by crownedfight.gd.
var fight: Node2D = null
var lands: Node2D = null
var room: Rect2 = Rect2()
var ground: TileMapLayer = null

var phase: int = 0
var phase_clock: float = 0.0
var lava: TileMapLayer = null
var lava_depth: int = 0
# Ground cells taken away, and what they held: Vector2i -> [source, atlas, alternative].
var _taken: Dictionary = {}
var _flooded: Dictionary = {}
var swarm: Node2D = null
# Tear pieces: Vector2i -> {"t": seconds, "open": bool}.
var tears: Dictionary = {}
var falls: int = 0
var lies: int = 0
var _storm_wait: float = 0.0
var _storm_left: float = 0.0
var _storm_carry: float = 0.0
var _storm_rate: float = 0.0
# How many storms have begun, and meteors dropped by them (the suite).
var storms: int = 0
var storm_meteors: int = 0
var _laser_left: float = 0.0
var lasers_cast: int = 0
# The wheel: how long it has turned (below 0: not), where its first arm
# points, how fast it turns now (signed), which way it means to, when it
# next turns back, its land, and how many there have been (the suite).
var wheel_t: float = -1.0
var wheel_angle: float = 0.0
var wheel_spin: float = 0.0
var wheel_dir: float = 1.0
var wheel_land: int = Element.Type.DARK
var wheels: int = 0
var _wheel_flip_left: float = 0.0
var _wheel_hit_left: float = 0.0
var _wheel_view: Node2D = null
var _horde_owed: float = 0.0
var _recolour_left: float = 0.0
var _tear_left: float = 0.0
var _flicker_left: float = 0.0
var _lie_left: float = LIE_GAP_LEAST
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


static func phase_for(share: float) -> int:
	"""Which phase a boss with `share` of its health left is in."""
	if share > SEALING_FROM:
		return 1
	if share > TRAP_FROM:
		return 2
	if share > TEAR_FROM:
		return 3
	return 4


func step(delta: float, share: float) -> void:
	var want: int = phase_for(share)
	if want != phase:
		enter(want)
	phase_clock += delta
	var me: Node2D = fight.call("_player") as Node2D if fight != null else null
	match phase:
		2:
			_step_sealing(delta, me)
		3:
			_step_trap(delta, me)
		4:
			_step_tear(delta, me)
	if phase >= 2:
		_step_lies(delta)
	queue_redraw()


func enter(next: int) -> void:
	"""Into phase `next`: what the last one left is cleared, the new one set."""
	var last: int = phase
	phase = next
	phase_clock = 0.0
	if last == 2:
		set_lava_depth(0)
		_tell_rift_flood(0.0)
	if last == 3:
		_clear_horde()
	if last == 4:
		knit_all()
	if lands != null:
		lands.set("false_share", LIE_SHARE if next >= 2 else 0.0)
		lands.set("env_floor", maxi(int(lands.get("env_floor")), 4))
	var boss: Node2D = fight.get("boss") if fight != null else null
	match next:
		2:
			_storm_wait = STORM_FIRST
			_storm_left = 0.0
			_mood(Element.Type.FIRE, boss)
		3:
			_laser_left = TRAP_LASER_FIRST
			_horde_owed = 0.0
			_recolour_left = 0.0
			_mood(Element.Type.DARK, boss)
		4:
			_tear_left = 1.0
			_flicker_left = 0.0
			_mood(Element.Type.DARK, boss)
	if fight != null and NAMES.has(next):
		fight.call("say", str(NAMES[next]))
	# The realm cracks faster as the fight goes on (crownedrift.gd).
	var rift: Node = fight.get("rift") if fight != null else null
	if rift != null:
		rift.set("intensity", 1.0 + 0.6 * float(maxi(0, next - 1)))


func _mood(land: int, boss: Node2D) -> void:
	"""The boss in `land`, the floor washed and the weather falling in it."""
	if boss != null and is_instance_valid(boss):
		boss.set("crown_land", land)
		fight.call("_tint_boss", land)
	fight.call("mood", land)


func end() -> void:
	"""The fight over: the room put back."""
	wheel_t = -1.0
	if _wheel_view != null:
		_wheel_view.queue_redraw()
	set_lava_depth(0)
	knit_all()
	_clear_horde()
	if lands != null:
		lands.set("false_share", 0.0)
	for wall in _walls():
		(wall as CanvasItem).modulate = Color(1, 1, 1, 1)
	var rift: Node = fight.get("rift") if fight != null else null
	if rift != null:
		rift.set("intensity", 1.0)
	_tell_rift_flood(0.0)
	phase = 0
	queue_redraw()


# =============================================================================
# THE SEALING
# =============================================================================

func _step_sealing(delta: float, me: Node2D) -> void:
	if me != null and lands != null:
		_step_storm(delta, me)
	set_lava_depth(lava_depth_at(phase_clock))
	_lava_swallows()
	_tell_rift_flood(float(lava_depth) / float(LAVA_MOST))
	if me != null and in_lava(_feet(me)) and lands != null:
		lands.call("_env_hit", me, LAVA_TIMES, Element.Type.FIRE, StatusEffects.BURN, _feet(me))


func _tell_rift_flood(share: float) -> void:
	var rift: Node = fight.get("rift") if fight != null else null
	if rift != null:
		rift.set("flood", share)


static func lava_depth_at(seconds: float) -> int:
	"""How many rings of the floor the lava holds `seconds` into the Sealing:
	rising a ring every LAVA_RISE to LAVA_MOST, held LAVA_HOLD, falling a ring
	every LAVA_FALL, gone for LAVA_REST, and again."""
	var rise: float = LAVA_RISE * LAVA_MOST
	var fall: float = LAVA_FALL * LAVA_MOST
	var t: float = fmod(maxf(0.0, seconds), rise + LAVA_HOLD + fall + LAVA_REST)
	if t < rise:
		return int(floor(t / LAVA_RISE))
	if t < rise + LAVA_HOLD:
		return LAVA_MOST
	if t < rise + LAVA_HOLD + fall:
		return LAVA_MOST - int(floor((t - rise - LAVA_HOLD) / LAVA_FALL)) - 1
	return 0


func _lava_span() -> Rect2i:
	"""The lava cells (LAVA_TILE, from the ground's corner) whose middles are
	on the room's floor."""
	var origin: Vector2 = ground.global_position if ground != null else Vector2.ZERO
	var x0: int = ceili((room.position.x - origin.x - LAVA_TILE / 2.0) / LAVA_TILE)
	var y0: int = ceili((room.position.y - origin.y - LAVA_TILE / 2.0) / LAVA_TILE)
	var x1: int = floori((room.end.x - origin.x - LAVA_TILE / 2.0) / LAVA_TILE)
	var y1: int = floori((room.end.y - origin.y - LAVA_TILE / 2.0) / LAVA_TILE)
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)


func _closing(depth: int) -> Vector2i:
	"""How many cells in from each side the lava holds at `depth` - the two
	sides meeting the BOX_CELLS square together at LAVA_MOST."""
	var span: Rect2i = _lava_span()
	var share: float = clampf(float(depth) / float(LAVA_MOST), 0.0, 1.0)
	return Vector2i(roundi(share * floorf(float(span.size.x - BOX_CELLS) / 2.0)),
		roundi(share * floorf(float(span.size.y - BOX_CELLS) / 2.0)))


func dry_at(cell: Vector2i, depth: int) -> bool:
	"""Whether lava cell `cell` is still floor at `depth`."""
	var span: Rect2i = _lava_span()
	var closing: Vector2i = _closing(depth)
	return mini(cell.x - span.position.x, span.end.x - 1 - cell.x) >= closing.x \
		and mini(cell.y - span.position.y, span.end.y - 1 - cell.y) >= closing.y


func _step_storm(delta: float, me: Node2D) -> void:
	if _storm_left > 0.0:
		_storm_left -= delta
		_storm_carry += _storm_rate * delta
		while _storm_carry >= 1.0:
			_storm_carry -= 1.0
			_drop_storm_meteor(me)
		if _storm_left <= 0.0:
			_storm_wait = _rng.randf_range(STORM_GAP_LEAST, STORM_GAP_MOST)
		return
	_storm_wait -= delta
	if _storm_wait <= 0.0:
		begin_storm()


func begin_storm() -> void:
	"""A storm starts: STORM_SECONDS of meteors at the rate this fight's
	size asks for."""
	var boss: Node2D = fight.get("boss") if fight != null else null
	var fighters: int = (boss.call("fight_targets") as Array).size() \
		if boss != null and is_instance_valid(boss) and boss.has_method("fight_targets") else 1
	_storm_rate = storm_rate_for(fighters)
	_storm_left = STORM_SECONDS
	_storm_carry = 0.0
	storms += 1


static func storm_rate_for(fighters: int) -> float:
	"""Meteors a second in a storm for `fighters` players (1 to
	STORM_PARTY_MOST counted)."""
	return STORM_RATE * (1.0 + STORM_PARTY_SHARE * float(clampi(fighters, 1, STORM_PARTY_MOST) - 1))


func _lava_swallows() -> void:
	"""A scorch the lava has risen over is gone - a meteor that landed on
	the land does not go on burning in the lava (ON THE LAND, NOT THE LAVA)."""
	if lands == null or lava_depth <= 0:
		return
	var dry: Rect2 = dry_rect(lava_depth)
	for hz in lands.get("hazards"):
		if str(hz.get("k", "")) == "scorch" and not dry.has_point(hz["p"]):
			hz["done"] = true


func storm_floor() -> Rect2:
	"""Where a storm's meteors fall: the floor the lava leaves until they
	land - now, or METEOR_WARN from now if it will be deeper then - kept
	STORM_MARGIN in from its edge, so no circle reaches the lava."""
	var landing: int = maxi(lava_depth, lava_depth_at(phase_clock + LandsScript.METEOR_WARN))
	var dry: Rect2 = dry_rect(landing)
	if dry.size.x <= STORM_MARGIN * 2.0 or dry.size.y <= STORM_MARGIN * 2.0:
		return dry
	return dry.grow(-STORM_MARGIN)


func _drop_storm_meteor(me: Node2D) -> void:
	var hz: Dictionary = lands.call("spawn_env", "meteor", me)
	storm_meteors += 1
	if hz.is_empty():
		return
	var floor_rect: Rect2 = storm_floor()
	if _rng.randf() < STORM_AIMED:
		# At you - but pulled onto the land if you stand at its edge.
		var at: Vector2 = hz["p"]
		hz["p"] = Vector2(clampf(at.x, floor_rect.position.x, floor_rect.end.x),
			clampf(at.y, floor_rect.position.y, floor_rect.end.y))
		return
	hz["p"] = Vector2(_rng.randf_range(floor_rect.position.x, floor_rect.end.x),
		_rng.randf_range(floor_rect.position.y, floor_rect.end.y))


func dry_rect(depth: int) -> Rect2:
	"""The floor the lava leaves at `depth`, in the world."""
	var span: Rect2i = _lava_span()
	var closing: Vector2i = _closing(depth)
	var origin: Vector2 = ground.global_position if ground != null else Vector2.ZERO
	return Rect2(origin + Vector2((span.position + closing) * LAVA_TILE), Vector2((span.size - closing * 2) * LAVA_TILE))


func ring_of(cell: Vector2i) -> int:
	"""How many rings in from the walls a lava cell is (0: against them)."""
	var span: Rect2i = _lava_span()
	return mini(mini(cell.x - span.position.x, span.end.x - 1 - cell.x),
		mini(cell.y - span.position.y, span.end.y - 1 - cell.y))


func lava_cell_at(at: Vector2) -> Vector2i:
	var origin: Vector2 = ground.global_position if ground != null else Vector2.ZERO
	return Vector2i(floori((at.x - origin.x) / LAVA_TILE), floori((at.y - origin.y) / LAVA_TILE))


func in_lava(at: Vector2) -> bool:
	return _flooded.has(lava_cell_at(at))


func set_lava_depth(depth: int) -> void:
	"""The lava holding `depth` rings of the floor: the floor taken from the
	cells it reaches, given back to those it leaves."""
	if depth == lava_depth:
		return
	lava_depth = depth
	if depth > 0 and lava == null:
		_make_lava()
	var span: Rect2i = _lava_span()
	var want: Dictionary = {}
	if depth > 0:
		for y in range(span.position.y, span.end.y):
			for x in range(span.position.x, span.end.x):
				var cell := Vector2i(x, y)
				if not dry_at(cell, depth):
					want[cell] = true
	for cell in _flooded.keys():
		if not want.has(cell):
			_flooded.erase(cell)
			if lava != null:
				lava.erase_cell(cell)
			if not _torn_at(cell):
				_give_back(_ground_cells(cell))
	for cell in want.keys():
		if not _flooded.has(cell):
			_flooded[cell] = true
			lava.set_cell(cell, 0, LAVA_CELL)
			_take(_ground_cells(cell))


func _make_lava() -> void:
	lava = TileMapLayer.new()
	lava.name = "crownlava"
	lava.tile_set = RiftScript.lava_tiles()
	lava.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	lava.z_index = (ground.z_index - 1) if ground != null else -11
	lava.position = ground.position if ground != null else Vector2.ZERO
	var holder: Node = ground.get_parent() if ground != null else self
	holder.add_child(lava)


func _ground_cells(lava_cell: Vector2i) -> Array:
	"""The four floor cells under one lava cell."""
	var cells: Array = []
	for dy in FLOOR_PER:
		for dx in FLOOR_PER:
			cells.append(Vector2i(lava_cell.x * FLOOR_PER + dx, lava_cell.y * FLOOR_PER + dy))
	return cells


func _take(cells: Array) -> void:
	if ground == null:
		return
	for cell in cells:
		if _taken.has(cell):
			continue
		var source: int = ground.get_cell_source_id(cell)
		if source < 0:
			continue
		_taken[cell] = [source, ground.get_cell_atlas_coords(cell), ground.get_cell_alternative_tile(cell)]
		ground.erase_cell(cell)


func _give_back(cells: Array) -> void:
	if ground == null:
		return
	for cell in cells:
		if not _taken.has(cell):
			continue
		var held: Array = _taken[cell]
		ground.set_cell(cell, int(held[0]), held[1], int(held[2]))
		_taken.erase(cell)


# =============================================================================
# THE TRAP
# =============================================================================

func horde_size() -> int:
	return HORDE_PHONE if EndlessRunScript.on_phone() else HORDE_CROWD


func _step_trap(delta: float, me: Node2D) -> void:
	if swarm == null:
		_make_horde()
	_recolour_left -= delta
	if _recolour_left <= 0.0:
		_recolour_left = HORDE_RECOLOUR
		swarm.set("element", int(LANDS[_rng.randi() % LANDS.size()]))
	var short: int = horde_size() - int(swarm.get("alive"))
	if short > 0:
		_horde_owed += HORDE_RATE * delta
		var count: int = mini(short, int(_horde_owed))
		if count > 0:
			_horde_owed -= float(count)
			swarm.call("spawn", count, me.global_position if me != null else room.get_center())
	_laser_left -= delta
	if _laser_left <= 0.0 and me != null and lands != null:
		_laser_left = TRAP_LASER_GAP
		cast_lasers(str(LASER_SHAPES[lasers_cast % LASER_SHAPES.size()]), me)
		lasers_cast += 1
	_step_wheel(delta, me)


func cast_lasers(shape: String, me: Node2D) -> void:
	"""One of the Trap's laser shapes, in a random land."""
	var land: int = int(LANDS[_rng.randi() % LANDS.size()])
	match shape:
		"sweep":
			lands.call("sweep", me, land)
		"cage":
			lands.call("cage", me, land)
		"pulse":
			lands.call("pulse_beam", me, land)
		_:
			begin_wheel(me)


func wheel_eye() -> Vector2:
	"""Where the Crowned looks from."""
	var boss: Node2D = fight.get("boss") if fight != null else null
	return (boss.global_position if boss != null and is_instance_valid(boss) else room.get_center()) + WHEEL_EYE


func wheel_gap() -> float:
	"""The angle between two arms."""
	return TAU / float(WHEEL_ARMS)


func begin_wheel(me: Node2D) -> void:
	"""The wheel opens: you in the middle of a gap, turning either way."""
	var at_me: float = (me.global_position - wheel_eye()).angle() if me != null else 0.0
	wheel_angle = at_me + wheel_gap() * 0.5
	wheel_dir = 1.0 if _rng.randf() < 0.5 else -1.0
	wheel_spin = 0.0
	_wheel_flip_left = _rng.randf_range(WHEEL_FLIP_LEAST, WHEEL_FLIP_MOST)
	var boss: Node2D = fight.get("boss") if fight != null else null
	var land: int = int(boss.get("crown_land")) if boss != null and is_instance_valid(boss) and boss.get("crown_land") != null else 0
	wheel_land = land if land in LANDS else Element.Type.DARK
	wheel_t = 0.0
	_wheel_hit_left = 0.0
	wheels += 1
	if _wheel_view == null:
		_wheel_view = Node2D.new()
		_wheel_view.name = "wheel"
		_wheel_view.top_level = true
		_wheel_view.z_index = LandsScript.AIR_Z
		_wheel_view.draw.connect(_draw_wheel)
		add_child(_wheel_view)


func wheel_end(arm: int) -> Vector2:
	"""Where an arm meets the room's edge."""
	var eye: Vector2 = wheel_eye()
	var dir := Vector2.from_angle(wheel_angle + wheel_gap() * float(arm))
	var far: float = INF
	for axis in 2:
		var d: float = dir[axis]
		if absf(d) < 0.0001:
			continue
		var edge: float = room.end[axis] if d > 0.0 else room.position[axis]
		far = minf(far, (edge - eye[axis]) / d)
	return eye + dir * (maxf(far, 0.0) if far != INF else 0.0)


func wheel_coming(at: Vector2) -> float:
	"""How far the arm coming round at a body at `at` still has to turn
	(0: on it, up to a whole gap: one just went by)."""
	return fposmod(((at - wheel_eye()).angle() - wheel_angle) * wheel_dir, wheel_gap())


func wheel_target(at: Vector2) -> float:
	"""How fast the wheel means to turn, signed, hunting a body at `at`:
	WHEEL_SLOW where it stands with the coming arm a gap away, WHEEL_FAST
	as it closes, held to WHEEL_TURN_MOST."""
	var closeness: float = 1.0 - wheel_coming(at) / wheel_gap()
	var sweep: float = lerpf(WHEEL_SLOW, WHEEL_FAST, closeness)
	return wheel_dir * minf(WHEEL_TURN_MOST, sweep / maxf(1.0, at.distance_to(wheel_eye())))


func wheel_touches(at: Vector2) -> int:
	"""Which arm a body at `at` stands in, or -1."""
	var eye: Vector2 = wheel_eye()
	for arm in WHEEL_ARMS:
		var near: Vector2 = Geometry2D.get_closest_point_to_segment(at, eye, wheel_end(arm))
		if at.distance_to(near) <= WHEEL_HALF + WHEEL_SLACK:
			return arm
	return -1


func _step_wheel(delta: float, me: Node2D) -> void:
	if wheel_t < 0.0:
		return
	wheel_t += delta
	if wheel_t >= WHEEL_WARN + WHEEL_SECONDS:
		wheel_t = -1.0
		if _wheel_view != null:
			_wheel_view.queue_redraw()
		return
	if wheel_t >= WHEEL_WARN:
		_wheel_flip_left -= delta
		if _wheel_flip_left <= 0.0:
			_wheel_flip_left = _rng.randf_range(WHEEL_FLIP_LEAST, WHEEL_FLIP_MOST)
			wheel_dir = -wheel_dir
		var want: float = wheel_target(me.global_position) if me != null else wheel_dir * WHEEL_SLOW / 200.0
		wheel_spin = move_toward(wheel_spin, want, WHEEL_EASE * delta)
		wheel_angle = wrapf(wheel_angle + wheel_spin * delta, -PI, PI)
		if me != null and lands != null:
			_wheel_hit_left -= delta
			var arm: int = wheel_touches(me.global_position) if _wheel_hit_left <= 0.0 else -1
			if arm >= 0:
				# Held off while another hazard's touch is still running
				# (the lands' TOUCH_GAP): tried again next frame, not lost.
				var before: int = int(lands.get("env_hits"))
				var near: Vector2 = Geometry2D.get_closest_point_to_segment(me.global_position, wheel_eye(), wheel_end(arm))
				lands.call("_env_hit", me, WHEEL_TIMES, wheel_land,
					LandsScript.EFFECT_FOR.get(wheel_land, StatusEffects.DAZZLE), near)
				if int(lands.get("env_hits")) > before:
					_wheel_hit_left = WHEEL_TICK
	if _wheel_view != null:
		_wheel_view.queue_redraw()


func _draw_wheel() -> void:
	if wheel_t < 0.0 or _wheel_view == null:
		return
	var eye: Vector2 = wheel_eye()
	var colour: Color = Element.colour_for(wheel_land)
	var v: Node2D = _wheel_view
	if wheel_t < WHEEL_WARN:
		# The eye gathering, and where each arm will burn.
		var share: float = wheel_t / WHEEL_WARN
		var tell: Color = colour.lightened(0.5)
		for arm in WHEEL_ARMS:
			var end: Vector2 = wheel_end(arm)
			v.draw_line(eye, end, Color(colour, 0.06 + 0.1 * share), WHEEL_HALF * 2.0)
			v.draw_line(eye, end, Color(tell, 0.45 + 0.45 * share), 1.5 + 2.0 * share)
		v.draw_circle(eye, 4.0 + 12.0 * share, Color(colour, 0.25 + 0.35 * share))
		v.draw_circle(eye, 2.0 + 5.0 * share, Color(1.0, 1.0, 1.0, 0.5 + 0.4 * share))
		return
	var left: float = WHEEL_WARN + WHEEL_SECONDS - wheel_t
	var fade: float = clampf(left / WHEEL_FADE, 0.0, 1.0) * clampf((wheel_t - WHEEL_WARN) / 0.12, 0.0, 1.0)
	var flicker: float = 0.88 + 0.12 * sin(wheel_t * 41.0)
	var body := Color(colour.lightened(0.15), 0.55 * fade * flicker)
	var core := Color(colour.lightened(0.5), 0.9 * fade)
	for arm in WHEEL_ARMS:
		var end: Vector2 = wheel_end(arm)
		v.draw_line(eye, end, Color(colour, 0.16 * fade), WHEEL_HALF * 3.2)
		v.draw_line(eye, end, body, WHEEL_HALF * 2.0)
		v.draw_line(eye, end, core, WHEEL_HALF * 0.9)
		v.draw_line(eye, end, Color(1.0, 1.0, 1.0, 0.95 * fade), 3.0)
		# Pulses running out along it, so it reads as pouring from the eye.
		var length: float = eye.distance_to(end)
		var dir: Vector2 = (end - eye) / maxf(length, 1.0)
		for k in 4:
			var at: float = fmod(wheel_t * 420.0 + float(k) * length / 4.0, maxf(length, 1.0))
			v.draw_arc(eye + dir * at, WHEEL_HALF * 0.75, 0.0, TAU, 12, Color(1.0, 1.0, 1.0, 0.35 * fade), 1.5)
		v.draw_circle(end, WHEEL_HALF * 0.9, Color(colour, 0.45 * fade))
	v.draw_circle(eye, WHEEL_HALF * (1.3 + 0.15 * sin(wheel_t * 18.0)), Color(colour, 0.6 * fade))
	v.draw_circle(eye, WHEEL_HALF * 0.6, Color(1.0, 1.0, 1.0, 0.9 * fade))


func _make_horde() -> void:
	swarm = SwarmScript.new()
	swarm.name = "crownhorde"
	swarm.set("arena", room)
	swarm.set("max_hp", HORDE_HP)
	swarm.set("speed", HORDE_SPEED)
	swarm.set("touch_damage", HORDE_TOUCH)
	swarm.set("element", Element.Type.DARK)
	swarm.call("draw_in_front_of", room.position.y - BACK_WALL_GAP)
	var holder: Node = null
	if fight != null and fight.get_parent() != null:
		holder = fight.get_parent().get_node_or_null("ysortworld/groundeffects")
	(holder if holder != null else self).add_child(swarm)


func _clear_horde() -> void:
	if swarm != null and is_instance_valid(swarm):
		swarm.call("clear")
		swarm.queue_free()
	swarm = null


# =============================================================================
# THE TEAR
# =============================================================================

func _step_tear(delta: float, me: Node2D) -> void:
	for piece in tears.keys():
		var held: Dictionary = tears[piece]
		held["t"] = float(held["t"]) + delta
		if not bool(held["open"]) and float(held["t"]) >= TEAR_WARN:
			held["open"] = true
			for cell in _piece_lava_cells(piece):
				if _flooded.has(cell):
					continue
				_take(_ground_cells(cell))
		elif bool(held["open"]) and float(held["t"]) >= TEAR_WARN + TEAR_OPEN:
			_knit(piece)
	_tear_left -= delta
	if _tear_left <= 0.0:
		_tear_left = TEAR_GAP
		if me != null:
			cut(piece_at(_feet(me)))
		var shapes: Array = PATTERNS.duplicate()
		shapes.shuffle()
		for k in TEAR_PATTERNS:
			cut_pattern(str(shapes[k % shapes.size()]))
	if me != null and fell_in(_feet(me)):
		_climb_out(me)
	_flicker_left -= delta
	if _flicker_left <= 0.0:
		_flicker_left = FLICKER_SECONDS
		var boss: Node2D = fight.get("boss") if fight != null else null
		if boss != null and is_instance_valid(boss):
			var now: int = int(boss.get("crown_land"))
			var land: int = now
			while land == now:
				land = int(LANDS[_rng.randi() % LANDS.size()])
			_mood(land, boss)


func _piece_span() -> Rect2i:
	"""The tear pieces over the room's floor (each TEAR_PIECE square, in lava
	cells from the lava's own span)."""
	var span: Rect2i = _lava_span()
	return Rect2i(0, 0, floori(float(span.size.x) / TEAR_PER), floori(float(span.size.y) / TEAR_PER))


func _piece_lava_cells(piece: Vector2i) -> Array:
	var span: Rect2i = _lava_span()
	var cells: Array = []
	for dy in TEAR_PER:
		for dx in TEAR_PER:
			cells.append(Vector2i(span.position.x + piece.x * TEAR_PER + dx, span.position.y + piece.y * TEAR_PER + dy))
	return cells


func piece_rect(piece: Vector2i) -> Rect2:
	var cells: Array = _piece_lava_cells(piece)
	var origin: Vector2 = ground.global_position if ground != null else Vector2.ZERO
	var first: Vector2i = cells[0]
	return Rect2(origin + Vector2(first * LAVA_TILE), Vector2(TEAR_PIECE, TEAR_PIECE))


func piece_at(at: Vector2) -> Vector2i:
	var span: Rect2i = _lava_span()
	var cell: Vector2i = lava_cell_at(at)
	return Vector2i(floori(float(cell.x - span.position.x) / TEAR_PER), floori(float(cell.y - span.position.y) / TEAR_PER))


func cut(piece: Vector2i) -> bool:
	"""Piece `piece` starts to crack, if it is on the floor, whole, and fewer
	than TEAR_MOST are cut."""
	if tears.has(piece) or tears.size() >= TEAR_MOST or not _piece_span().has_point(piece):
		return false
	tears[piece] = {"t": 0.0, "open": false, "seed": _rng.randi()}
	return true


func cut_pattern(shape: String) -> int:
	"""Cut `shape` across the whole floor; how many pieces began to crack."""
	var span: Rect2i = _piece_span()
	var pieces: Array = []
	match shape:
		"row":
			# Every other piece, so there is a way across; on an odd span the
			# ends too, so a short floor still cracks three (the room is a
			# quarter smaller since 0.134.7: six pieces by five).
			var y: int = _rng.randi_range(1, span.size.y - 2)
			var odd: int = 0 if span.size.x % 2 == 1 else _rng.randi() % 2
			for x in span.size.x:
				if x % 2 == odd:
					pieces.append(Vector2i(x, y))
		"column":
			var x: int = _rng.randi_range(1, span.size.x - 2)
			var odd: int = 0 if span.size.y % 2 == 1 else _rng.randi() % 2
			for y in span.size.y:
				if y % 2 == odd:
					pieces.append(Vector2i(x, y))
		"ring":
			var middle := Vector2(span.size) / 2.0 - Vector2(0.5, 0.5)
			var reach: float = _rng.randf_range(1.5, maxf(1.6, minf(middle.x, middle.y)))
			var count: int = int(TAU * reach / 2.0)
			var turn: float = _rng.randf() * TAU
			for k in count:
				var at: Vector2 = middle + Vector2.from_angle(turn + TAU * float(k) / float(count)) * reach
				pieces.append(Vector2i(roundi(at.x), roundi(at.y)))
		_:
			for tries in 60:
				if pieces.size() >= TEAR_SCATTER:
					break
				var piece := Vector2i(_rng.randi_range(0, span.size.x - 1), _rng.randi_range(0, span.size.y - 1))
				var clear: bool = true
				for other in pieces:
					clear = clear and maxi(absi(piece.x - (other as Vector2i).x), absi(piece.y - (other as Vector2i).y)) >= TEAR_SCATTER_APART
				if clear:
					pieces.append(piece)
	var made: int = 0
	for piece in pieces:
		if cut(piece):
			made += 1
	return made


func _torn_at(lava_cell: Vector2i) -> bool:
	for piece in tears.keys():
		if bool(tears[piece]["open"]) and lava_cell in _piece_lava_cells(piece):
			return true
	return false


func fell_in(at: Vector2) -> bool:
	var piece: Vector2i = piece_at(at)
	return tears.has(piece) and bool(tears[piece]["open"]) and piece_rect(piece).has_point(at)


func _climb_out(me: Node2D) -> void:
	"""Fallen through: hurt, and up again on the nearest solid floor."""
	var at: Vector2 = _feet(me)
	falls += 1
	if lands != null:
		lands.set("_touch_left", 0.0)
		lands.call("_env_hit", me, TEAR_TIMES, Element.Type.DARK, StatusEffects.WITHER, at)
	var best: Vector2 = room.get_center()
	var best_d: float = INF
	var hole: Rect2 = piece_rect(piece_at(at))
	for reach in [0.75, 1.25, 1.75, 2.5, 3.5]:
		for k in 16:
			var out: Vector2 = hole.get_center() + Vector2.from_angle(TAU * float(k) / 16.0) * (TEAR_PIECE * float(reach) + 10.0)
			if not room.grow(-12.0).has_point(out) or fell_in(out) or in_lava(out):
				continue
			var d: float = out.distance_squared_to(at)
			if d < best_d:
				best_d = d
				best = out
		if best_d < INF:
			break
	me.global_position = best - (_feet(me) - me.global_position)
	me.reset_physics_interpolation()


func _knit(piece: Vector2i) -> void:
	tears.erase(piece)
	for cell in _piece_lava_cells(piece):
		if not _flooded.has(cell):
			_give_back(_ground_cells(cell))


func knit_all() -> void:
	for piece in tears.keys():
		_knit(piece)
	tears = {}


# =============================================================================
# THE LYING ROOM
# =============================================================================

func _step_lies(delta: float) -> void:
	_lie_left -= delta
	if _lie_left > 0.0:
		return
	_lie_left = _rng.randf_range(LIE_GAP_LEAST, LIE_GAP_MOST)
	lies += 1
	if _rng.randf() < 0.5:
		var walls: Array = _walls()
		for k in mini(LIE_WALLS, walls.size()):
			var wall: CanvasItem = walls[_rng.randi() % walls.size()]
			var shimmer: Tween = wall.create_tween()
			shimmer.tween_property(wall, "modulate", Color(0.75, 0.55, 1.0, 0.3), 0.12)
			shimmer.tween_property(wall, "modulate", Color(1, 1, 1, 1), 0.5)
	elif fight != null:
		fight.call("flash_wash", int(LANDS[_rng.randi() % LANDS.size()]))


func _walls() -> Array:
	var found: Array = []
	if fight == null or fight.get_parent() == null:
		return found
	var props: Node = fight.get_parent().get_node_or_null("ysortworld/props")
	if props == null:
		return found
	for child in props.get_children():
		var from: String = (child as Node).scene_file_path
		if child is CanvasItem and ("/wall" in from or "/pillar" in from):
			found.append(child)
	return found


static func _feet(body: Node2D) -> Vector2:
	return body.global_position + Vector2(0, 10)


# =============================================================================
# DRAWN: the lava's front, the cracks, the falling pieces
# =============================================================================

func _draw() -> void:
	if phase == 2 and ground != null:
		var next_depth: int = lava_depth_at(phase_clock + LAVA_WARN)
		var pulse: float = 0.5 + 0.5 * sin(phase_clock * 8.0)
		for ring_depth in [lava_depth, next_depth]:
			var warn: bool = ring_depth != lava_depth
			if ring_depth <= 0 or (warn and ring_depth < lava_depth):
				continue
			var inner: Rect2 = dry_rect(ring_depth)
			draw_rect(inner, Color(1.0, 0.45, 0.1, (0.35 + 0.4 * pulse) if warn else 0.5), false, 4.0 if warn else 3.0)
	for piece in tears.keys():
		var held: Dictionary = tears[piece]
		var area: Rect2 = piece_rect(piece)
		var t: float = float(held["t"])
		if not bool(held["open"]):
			var k: float = clampf(t / TEAR_WARN, 0.0, 1.0)
			var shake := Vector2(sin(t * 40.0), cos(t * 37.0)) * 1.5 * k
			var pulse: float = 0.5 + 0.5 * sin(t * 14.0)
			draw_rect(Rect2(area.position + shake, area.size), Color(0.6, 0.3, 1.0, 0.1 + 0.15 * k), true)
			draw_rect(Rect2(area.position + shake, area.size), Color(0.75, 0.5, 1.0, 0.3 + 0.5 * k * pulse), false, 2.0)
			_paint_rng_cracks(area, int(held["seed"]), k, shake)
		else:
			var drop: float = clampf((t - TEAR_WARN) / TEAR_DROP, 0.0, 1.0)
			if drop < 1.0:
				var shrink: float = 1.0 - drop
				var falling := Rect2(area.get_center() - area.size * shrink / 2.0, area.size * shrink)
				draw_rect(falling, Color(0.16, 0.13, 0.2, 1.0 - drop * 0.8))
			# The rift's light at the rim, and its stars inside.
			for ring in 4:
				draw_rect(area.grow(-2.0 - 3.0 * float(ring)), Color(0.7, 0.45, 1.0, 0.4 - 0.09 * float(ring)), false, 3.0)
			draw_rect(area, Color(0.9, 0.75, 1.0, 0.95), false, 2.0)
			var seed_value: int = int(held["seed"])
			for k in 6:
				var spot := Vector2(fmod(float((seed_value >> k) % 61) + t * (6.0 + float(k)), area.size.x - 8.0) + 4.0,
					fmod(float((seed_value >> (k + 3)) % 59) + float(k) * 9.0, area.size.y - 8.0) + 4.0)
				draw_circle(area.position + spot, 1.4, Color(1.0, 0.9, 1.0, 0.5 + 0.5 * sin(t * 5.0 + float(k))))


func _paint_rng_cracks(area: Rect2, seed_value: int, k: float, shake: Vector2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var middle: Vector2 = area.get_center() + shake
	for arm in 5:
		var heading: float = rng.randf() * TAU
		var line := PackedVector2Array([middle])
		var reach: float = (area.size.x * 0.55) * k
		var steps: int = 4
		for q in steps:
			heading += rng.randf_range(-0.6, 0.6)
			line.append(line[q] + Vector2.from_angle(heading) * reach / float(steps))
		draw_polyline(line, Color(0.05, 0.02, 0.08, 0.9), 3.0)
		draw_polyline(line, Color(0.85, 0.6, 1.0, 0.85 * k), 1.5)
