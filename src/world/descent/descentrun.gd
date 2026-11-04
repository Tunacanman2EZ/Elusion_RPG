# descentrun.gd - THE DESCENT (0.112.0, step 1 of the commit folder's
# DESCENT_PLAN.txt; the owner's alone while it is built): a roguelike run
# down a crypt, room by room, played as your own warrior - THE WARRIOR'S
# minigame, as the Healer's Run is the healer's and the Stand the mage's
# (the card lets a warrior in, minigamescard.gd).
#
# The owner, of roguelike_mockup.png: "that looks so cool incredible simply
# the best lets try it out", then "this will be the warriors decent".
#
# ONE ROOM, MANY TIMES: the area (scene/descent.tscn, builddescent.gd) is a
# single crypt room the screen's size - its walls, two doors in the back wall
# (descentdoor.gd), one in the front where you come in. Going through a door
# fades the screen, clears the room, dresses it again (_dress()) and puts you
# at its front: the next room.
#
#   WAITING  between runs: both doors open, marked with the way down. Walk
#            through either to begin (start_run()).
#   FIGHT    the doors shut; a pack of the floor's monsters comes at you
#            (_spawn_pack(): more each room, tougher each floor). An elite
#            room brings an elite too; the last room is the floor's keeper.
#   PICK     the room is clear and it promised an upgrade: three cards
#            (DescentBoons.offers()), one taken (pick()).
#   CLEAR    the doors open, each marked with what the next room holds
#            (_open_doors(): an upgrade, gold, or an elite - gold and an
#            upgrade both). Walk through the one you want.
#
# ROOMS fights a floor, then its keeper (FLOORS: the Crypt, the Frozen Halls,
# the Dark Below). Beating the third keeper wins the run.
#
# STEP 1 OF THE SECOND PLAN (0.115.0) - the owner: "feels pretty boring and
# chars die fast". A WARD (descentboons.gd) over your health, full at the
# start and again at every room cleared; the crypt's monsters hit for half on
# the first floor, 0.7 on the second, 0.9 on the third (FLOORS' "taken"); a
# room starts at three monsters and never holds more than PACK_MOST; and the
# pack comes in waves (waves_for()), each from the room's edges, every spot
# glowing MARK_SECONDS before its monster steps out (_marks).
#
# STEP 2 (0.115.0): FOUR MORE DOORS. A SHRINE (a fight, then a rare or
# better pick - the floor's monsters hitting SHRINE_CURSE harder after it), a
# TREASURE (half a pack, TREASURE_GOLD times a room's gold), a CHALLENGE (clear
# it inside challenge_seconds() for a rare or better pick, or none) and a REST
# (no fight: the ward full and half again, REST_OVER, for the next room, a
# fire in the middle - and the time to let your health come back). And the
# new upgrades' hooks: a kill counts for Momentum, a fall may be Second Wind.
#
# AND THE DOUBLE AXE (step 2's second half): its mythic upgrades are offered
# to a warrior wearing it (wears_axe(); a keeper's pick always holds one), and
# AXE FURY - every kill fills descentboons.gd's `fury`; full, Q in a fight
# (_unhandled_input()) throws a giant spinning axe (GiantAxe) that spirals in
# round the room for FURY_SECONDS, cutting what it meets for FURY_SWINGS
# swings, each monster at most every FURY_HIT_GAP.
#
# A REROLL (0.116.0; the owner: "we still need the reroll option also we can add gold
# to if needed"): three new cards for the same pick, REROLL_FREE free a floor,
# then paid from the run's gold - REROLL_GOLD, then twice it, three times...
# (reroll_cost()), counted again each floor.
#
# A FALL IS NOT A DEATH (as in the Endless): Player.take_damage() asks
# knock_out() first - you wake at the room's front on 1 health, every effect
# cleared, and the run is over. Your gear and bag are as they were.
#
# WHAT IT PAYS, IN STEP 1: nothing. The gold is counted for the run; the
# server pays it in step 3. The monsters carry the stress test's mark
# (stresscrowd.gd's META): no kill report, never shared or numbered, never
# respawned - this game's alone.
extends Node

const Boons := preload("res://src/world/descent/descentboons.gd")
const StatusEffects := preload("res://src/characters/statuseffects.gd")

enum State { WAITING, FIGHT, PICK, CLEAR, TRAVEL }

const MARK := &"stress_copy"
const ROOMS := 6
const FLOORS := [
	{"name": "the Crypt", "monsters": ["skeleton", "skeletonsoldier"], "elites": ["skeletonelite"],
		"keeper": "fireboss", "keeper_name": "The Fire Keeper", "health": 1.0, "taken": 0.5},
	{"name": "the Frozen Halls", "monsters": ["icesprite", "iceslime", "icebushmage"],
		"elites": ["icefiresprite", "icebushsniper"], "keeper": "iceboss", "keeper_name": "The Ice Keeper",
		"health": 1.6, "taken": 0.7},
	{"name": "the Dark Below", "monsters": ["darksprite", "darkslime", "darkbushmage"],
		"elites": ["darkfiresprite", "darkbushsniper"], "keeper": "bossenemy", "keeper_name": "The Dark Keeper",
		"health": 2.3, "taken": 0.9},
]
# What a door can promise, and how often.
const KINDS := ["upgrade", "gold", "elite", "shrine", "treasure", "challenge", "rest"]
const KIND_WEIGHTS := [30, 22, 18, 8, 8, 8, 6]
# A Treasure pays this many rooms' gold for half a pack; a Rest's ward is this
# much over a full one; a Challenge gives CHALLENGE_BASE seconds and
# CHALLENGE_EACH more a monster.
const TREASURE_GOLD := 3
const REST_OVER := 1.5
const CHALLENGE_BASE := 15.0
const CHALLENGE_EACH := 2.0
const REST_FIRE := "res://scene/crypt/candlecluster.tscn"
# AXE FURY: the giant axe's time, laps, reach, size, cut and how often it may
# cut one monster; the room it spirals round, as shares of the floor.
const FURY_SECONDS := 2.4
const FURY_LAPS := 2.0
const FURY_REACH := 56.0
const FURY_SCALE := 3.5
const FURY_SWINGS := 3
const FURY_HIT_GAP := 0.5
const FURY_RADII := Vector2(0.4, 0.32)
const AXE_SCENE := "res://scene/projectiles/spinningaxe.tscn"
# A REROLL: this many free a floor, then the first paid one this much gold,
# each after it this much more.
const REROLL_FREE := 1
const REROLL_GOLD := 20


# THE GIANT AXE: the Double Axe's own spin, FURY_SCALE times, spiralling in
# round the room's middle and cutting what it meets.
class GiantAxe extends Node2D:
	var centre: Vector2 = Vector2.ZERO
	var radii: Vector2 = Vector2.ZERO
	var angle: float = 0.0
	var cut: int = 0
	var t: float = 0.0
	var hit_at: Dictionary = {}
	var hits: int = 0

	func step(delta: float) -> void:
		t += delta
		if t >= FURY_SECONDS:
			queue_free()
			return
		angle += TAU * FURY_LAPS / FURY_SECONDS * delta
		var inward: float = 1.0 - 0.75 * t / FURY_SECONDS
		global_position = centre + Vector2(cos(angle) * radii.x, sin(angle) * radii.y) * inward
		if not is_inside_tree():
			return
		for enemy in get_tree().get_nodes_in_group("enemies"):
			var e := enemy as Node2D
			if e == null or not e.has_method("take_damage") \
					or e.global_position.distance_to(global_position) > FURY_REACH:
				continue
			var id: int = e.get_instance_id()
			if t - float(hit_at.get(id, -100.0)) >= FURY_HIT_GAP:
				hit_at[id] = t
				e.call("take_damage", cut)
				hits += 1
		queue_redraw()

	func _physics_process(delta: float) -> void:
		step(delta)

	func _draw() -> void:
		draw_set_transform(Vector2(0, 10), 0.0, Vector2(1.0, 0.5))
		draw_circle(Vector2.ZERO, FURY_REACH, Color(1.0, 0.55, 0.2, 0.14))
		draw_arc(Vector2.ZERO, FURY_REACH, 0.0, TAU, 40, Color(1.8, 1.0, 0.4, 0.7), 2.0)
# A pack: PACK_FIRST + the room's number + PACK_FLOOR a floor down, never
# over PACK_MOST (0.115.0: it began at 4 and reached 13).
const PACK_FIRST := 2
const PACK_FLOOR := 2
const PACK_MOST := 10
# IN WAVES (0.115.0): the next comes when this many or fewer are left of the
# last, or after WAVE_SECONDS; each monster's spot glows MARK_SECONDS first.
const WAVE_NEXT_AT := 1
const WAVE_SECONDS := 9.0
const MARK_SECONDS := 0.7
const ROOM_HEALTH_STEP := 0.1
# An elite: this much health, this much bigger (twice: the crypt's elite is
# an elite already - three times made a 12,456-health skeleton).
const ELITE_HEALTH := 2.0
const ELITE_SIZE := 1.25
# The keeper's health over its own (a single player, not the boss room's crowd).
const KEEPER_HEALTH := 1.0
const GOLD_BASE := 15
const ELITE_GOLD := 1.5
const KEEPER_GOLD := 4
# Seconds after you come in before the pack does; the fade each way.
const FIGHT_DELAY := 0.9
const FADE_SECONDS := 0.25
# Monsters come for you from anywhere in the room.
const NOTICE := 900.0
# THE CAMERA HELD TO THE ROOM (its limits): the room is bigger than the
# view, so the camera follows you, but never past the room's walls into the
# dark - the bottom room enough for the front wall over the HUD's bars.
const CAMERA_LIMITS := Rect2(0, 0, 640, 408)
# None placed nearer the player than this.
const SPAWN_CLEAR := 90.0
# The ward's ring, under your feet (from your origin), and how wide.
const WARD_RING_AT := Vector2(0, 12)
const WARD_RING_RADIUS := 13.0
const DECOR := ["res://scene/crypt/skullpile.tscn", "res://scene/crypt/bones.tscn", "res://scene/crypt/urn.tscn",
	"res://scene/crypt/potpair.tscn", "res://scene/crypt/ribcage.tscn", "res://scene/crypt/gravestone.tscn",
	"res://scene/crypt/skullcandles.tscn", "res://scene/crypt/cratestack.tscn", "res://scene/crypt/skullbones.tscn",
	"res://scene/crypt/potlarge.tscn", "res://scene/crypt/rubble2.tscn", "res://scene/crypt/candlecluster.tscn"]

# Set by builddescent.gd: the floor monsters stand on, where you come in, and
# the doors.
@export var room_rect: Rect2 = Rect2(22, 92, 596, 230)
@export var entry_spot: Vector2 = Vector2(320, 300)
@export var left_door_path: NodePath = NodePath("../ysortworld/props/doorleft")
@export var right_door_path: NodePath = NodePath("../ysortworld/props/doorright")

var state: int = State.WAITING
var floor_index: int = 0
var room: int = 0
var room_kind: String = ""
var gold: int = 0
var slain: int = 0
var picks: int = 0
var offers: Array = []
var best: String = ""
var last_result: String = ""
var doors: Array = []
var monsters: Array = []
var hud: Node = null
# The suite's door: who the run is for.
var player_override: Node2D = null

var _rng := RandomNumberGenerator.new()
var _fight_in: float = -1.0
var _travel_t: float = 0.0
var _travel_to: String = ""
var _travelled: bool = false
var _decor: Node2D = null
var _held_camera: Camera2D = null
# The waves still to come (each an Array of [enemy id, health, elite]), the
# monsters marked and about to step out ([id, spot, health, elite, seconds
# left]), the seconds since the last wave, and the floor's glowing marks.
var _waves: Array = []
var _coming: Array = []
var _wave_clock: float = 0.0
var _marks: Node2D = null
var _ward_ring: Node2D = null
# A Challenge's seconds left (counted from the pack's coming), and whether it
# was beaten.
var challenge_left: float = 0.0
var challenge_won: bool = false
# Rerolls: the free ones left this floor, the paid ones made this floor, and
# the rule the pick on the table was drawn by (so a reroll keeps it).
var rerolls_free: int = 0
var rerolls_paid: int = 0
var _offer_at_least: String = ""


func _ready() -> void:
	add_to_group(&"descent_run")
	_rng.randomize()
	hud = (load("res://src/world/descent/descenthud.gd") as GDScript).new()
	hud.set("run", self)
	add_child(hud)
	for path in [left_door_path, right_door_path]:
		var door: Node = get_node_or_null(path)
		if door != null:
			doors.append(door)
			door.connect("walked_in", _on_walked_in)
	_set_doors(true, "begin", "begin")


func _exit_tree() -> void:
	Boons.clear()
	_drop_ward_ring()


func _player() -> Node2D:
	if player_override != null:
		return player_override if is_instance_valid(player_override) else null
	return get_tree().get_first_node_in_group(&"player") as Node2D if is_inside_tree() else null


func floor_info() -> Dictionary:
	return FLOORS[clampi(floor_index, 0, FLOORS.size() - 1)]


func running() -> bool:
	return state != State.WAITING


# =============================================================================
# THE RUN
# =============================================================================

func start_run() -> void:
	Boons.clear()
	Boons.active = true
	floor_index = 0
	room = 0
	gold = 0
	slain = 0
	picks = 0
	rerolls_free = REROLL_FREE
	rerolls_paid = 0
	fill_ward()
	_go("upgrade")


func fill_ward(over: float = 1.0) -> void:
	"""The ward full again (descentboons.gd): at the start, and at every room
	cleared (`over` a Rest's half again). Shown round your feet (_ward_ring)
	and on the HUD."""
	var player: Node2D = _player()
	Boons.fill_ward(int(player.get("max_hp")) if player != null and "max_hp" in player else 0, over)
	_place_ward_ring()


func _place_ward_ring() -> void:
	var player: Node2D = _player()
	if player == null:
		return
	if _ward_ring == null or not is_instance_valid(_ward_ring) or _ward_ring.get_parent() != player:
		if _ward_ring != null and is_instance_valid(_ward_ring):
			_ward_ring.queue_free()
		_ward_ring = Node2D.new()
		_ward_ring.name = "wardring"
		_ward_ring.z_index = -1
		_ward_ring.draw.connect(_draw_ward_ring)
		player.add_child(_ward_ring)
		_ward_ring.position = WARD_RING_AT
		_ward_ring.reset_physics_interpolation()
	_ward_ring.queue_redraw()


func _drop_ward_ring() -> void:
	if _ward_ring != null and is_instance_valid(_ward_ring):
		_ward_ring.queue_free()
	_ward_ring = null


func _draw_ward_ring() -> void:
	"""A gold ring round your feet, as bright as the ward is full."""
	if Boons.ward <= 0 or Boons.ward_most <= 0:
		return
	var full: float = float(Boons.ward) / float(Boons.ward_most)
	_ward_ring.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
	_ward_ring.draw_circle(Vector2.ZERO, WARD_RING_RADIUS, Color(1.0, 0.82, 0.3, 0.08 + 0.12 * full))
	_ward_ring.draw_arc(Vector2.ZERO, WARD_RING_RADIUS, -PI / 2.0, -PI / 2.0 + TAU * full, 32,
		Color(1.6, 1.25, 0.5, 0.45 + 0.5 * full), 1.5)


func _go(kind: String) -> void:
	"""Through a door: the screen fades, and the next room is dressed behind
	it (_arrive())."""
	state = State.TRAVEL
	_travel_to = kind
	_travel_t = 0.0
	_travelled = false
	_set_doors(false, "", "")


func _arrive(kind: String) -> void:
	if kind == "down":
		floor_index += 1
		room = 0
		kind = "upgrade"
		Boons.new_floor()
		rerolls_free = REROLL_FREE
		rerolls_paid = 0
	room += 1
	room_kind = "keeper" if room > ROOMS else kind
	Boons.floor_taken = float(floor_info().get("taken", 1.0))
	Boons.room_kills = 0
	challenge_left = 0.0
	challenge_won = false
	_clear_monsters()
	_dress()
	if room_kind == "rest":
		_light_fire()
	var player: Node2D = _player()
	if player != null:
		player.global_position = entry_spot
		player.reset_physics_interpolation()
		if player.has_method("snap_camera"):
			player.call("snap_camera")
	_fight_in = FIGHT_DELAY
	if hud != null:
		hud.call("announce", room_title(), _room_line())
	# A REST: no fight. The ward full and half again; the doors open as the
	# fade ends (_process()).
	if room_kind == "rest":
		_fight_in = -1.0
		fill_ward(REST_OVER)


func room_title() -> String:
	if room_kind == "keeper":
		return str(floor_info()["keeper_name"])
	return "Floor %d - room %d" % [floor_index + 1, room]


func _room_line() -> String:
	match room_kind:
		"elite":
			return "An elite waits here"
		"gold":
			return "Gold when it is clear"
		"keeper":
			return "The keeper of %s" % str(floor_info()["name"])
		"shrine":
			return "A shrine: a stronger upgrade - and the floor hits harder after"
		"treasure":
			return "Treasure, lightly guarded"
		"challenge":
			return "Clear it in %d seconds for a rare upgrade" % roundi(challenge_seconds())
		"rest":
			return "A rest: your ward full and half again for the next room"
	return "An upgrade when it is clear"


func _process(delta: float) -> void:
	_hold_camera()
	match state:
		State.TRAVEL:
			_travel_t += delta
			if hud != null:
				hud.call("fade", 1.0 - absf(_travel_t - FADE_SECONDS) / FADE_SECONDS)
			if not _travelled and _travel_t >= FADE_SECONDS:
				_travelled = true
				_arrive(_travel_to)
			if _travel_t >= FADE_SECONDS * 2.0:
				if hud != null:
					hud.call("fade", 0.0)
				state = State.FIGHT
				if room_kind == "rest":
					_open_doors()
		State.FIGHT:
			if _fight_in >= 0.0:
				_fight_in -= delta
				if _fight_in < 0.0:
					_spawn_pack()
			else:
				_step_waves(delta)
				if room_kind == "challenge":
					challenge_left = maxf(0.0, challenge_left - delta)
				if living() == 0 and _coming.is_empty() and _waves.is_empty():
					challenge_won = room_kind == "challenge" and challenge_left > 0.0
					_room_cleared()
	if _ward_ring != null and is_instance_valid(_ward_ring):
		_ward_ring.queue_redraw()


func _hold_camera() -> void:
	"""The player's camera kept to the room (CAMERA_LIMITS) - once a camera."""
	var player: Node2D = _player()
	var camera: Camera2D = player.get_node_or_null("camera2d") as Camera2D if player != null else null
	if camera == null or camera == _held_camera:
		return
	_held_camera = camera
	camera.limit_left = int(CAMERA_LIMITS.position.x)
	camera.limit_top = int(CAMERA_LIMITS.position.y)
	camera.limit_right = int(CAMERA_LIMITS.end.x)
	camera.limit_bottom = int(CAMERA_LIMITS.end.y)


func living() -> int:
	var count: int = 0
	var still: Array = []
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


func _room_cleared() -> void:
	var info: Dictionary = floor_info()
	# THE WARD FULL AGAIN for the next room (0.115.0).
	fill_ward()
	match room_kind:
		"gold":
			_pay(GOLD_BASE * (floor_index + 1))
			_open_doors()
		"elite":
			_pay(roundi(GOLD_BASE * (floor_index + 1) * ELITE_GOLD))
			_offer()
		"keeper":
			_pay(GOLD_BASE * (floor_index + 1) * KEEPER_GOLD)
			if floor_index >= FLOORS.size() - 1:
				_end_run(true)
				return
			if hud != null:
				hud.call("announce", "%s falls!" % str(info["keeper_name"]), "Pick one - then down to floor %d" % (floor_index + 2))
			_offer("rare")
		"shrine":
			Boons.shrine_taken *= 1.0 + Boons.SHRINE_CURSE
			if hud != null:
				hud.call("announce", "The shrine answers", "A stronger pick - the floor hits harder now")
			_offer("rare")
		"treasure":
			_pay(GOLD_BASE * (floor_index + 1) * TREASURE_GOLD)
			_open_doors()
		"challenge":
			if challenge_won:
				if hud != null:
					hud.call("announce", "Challenge beaten!", "A rare upgrade")
				_offer("rare")
			else:
				if hud != null:
					hud.call("announce", "Too slow", "No upgrade this time")
				_open_doors()
		_:
			_offer()


func _pay(amount: int) -> void:
	var paid: int = roundi(float(amount) * Boons.gold_factor())
	gold += paid
	if hud != null:
		hud.call("toast", "+%d gold" % paid)


func _offer(at_least: String = "") -> void:
	_offer_at_least = at_least
	offers = Boons.offers(_rng, 3, at_least, wears_axe(), room_kind == "keeper")
	if offers.is_empty():
		_open_doors()
		return
	state = State.PICK
	if hud != null:
		hud.call("show_pick", offers)


func reroll_cost() -> int:
	"""What the next reroll costs: nothing while a free one is left."""
	return 0 if rerolls_free > 0 else REROLL_GOLD * (rerolls_paid + 1)


func can_reroll() -> bool:
	return state == State.PICK and (rerolls_free > 0 or gold >= reroll_cost())


func reroll() -> bool:
	"""Three new cards for this pick, by the same rule (a keeper's mythic, a
	Shrine's rare), the ones on the table left out while there are others."""
	if not can_reroll():
		return false
	if rerolls_free > 0:
		rerolls_free -= 1
	else:
		var cost: int = reroll_cost()
		gold -= cost
		rerolls_paid += 1
		if hud != null:
			hud.call("toast", "-%d gold" % cost)
	offers = Boons.offers(_rng, 3, _offer_at_least, wears_axe(), room_kind == "keeper", offers)
	if hud != null:
		hud.call("show_pick", offers)
	return true


func pick(index: int) -> bool:
	"""One of the cards taken: its level for the rest of the run."""
	if state != State.PICK or index < 0 or index >= offers.size():
		return false
	Boons.take(str(offers[index]))
	picks += 1
	offers = []
	if hud != null:
		hud.call("hide_pick")
	_open_doors()
	return true


func _open_doors() -> void:
	state = State.CLEAR
	if room_kind == "keeper":
		_set_doors(true, "down", "down")
	elif room >= ROOMS:
		_set_doors(true, "keeper", "keeper")
	else:
		var first: String = _roll_kind("")
		_set_doors(true, first, _roll_kind(first))


func _roll_kind(not_this: String) -> String:
	var total: int = 0
	for k in KINDS.size():
		if KINDS[k] != not_this:
			total += int(KIND_WEIGHTS[k])
	var roll: int = _rng.randi_range(1, total)
	for k in KINDS.size():
		if KINDS[k] == not_this:
			continue
		roll -= int(KIND_WEIGHTS[k])
		if roll <= 0:
			return str(KINDS[k])
	return "upgrade"


func _set_doors(open: bool, left: String, right: String) -> void:
	var kinds: Array = [left, right]
	for i in doors.size():
		var door: Node = doors[i]
		if is_instance_valid(door):
			door.call("set_reward", str(kinds[i]) if i < kinds.size() else "")
			door.call("set_open", open)


func _on_walked_in(door: Node2D) -> void:
	match state:
		State.WAITING:
			start_run()
		State.CLEAR:
			_go(str(door.get("reward")))


# =============================================================================
# THE MONSTERS
# =============================================================================

func pack_size() -> int:
	var size: int = mini(PACK_MOST, PACK_FIRST + room + PACK_FLOOR * floor_index)
	# A Treasure is lightly guarded: half (rounded up).
	return ceili(size / 2.0) if room_kind == "treasure" else size


func challenge_seconds() -> float:
	return CHALLENGE_BASE + CHALLENGE_EACH * pack_size()


static func waves_for(size: int) -> int:
	"""How many waves a pack of `size` comes in."""
	return 1 if size <= 4 else (2 if size <= 7 else 3)


func health_scale() -> float:
	return float(floor_info()["health"]) * (1.0 + ROOM_HEALTH_STEP * (room - 1))


func _spawn_pack() -> void:
	var info: Dictionary = floor_info()
	if room_kind == "keeper":
		_bring(str(info["keeper"]), _spot(Vector2(room_rect.get_center().x, room_rect.position.y + 80.0)),
			float(info["health"]) * KEEPER_HEALTH)
		return
	# IN WAVES (0.115.0): the pack split as evenly as it goes, the elite in
	# the last, and the first wave marked now.
	var kinds: Array = info["monsters"]
	var size: int = pack_size()
	var count: int = waves_for(size)
	_waves = []
	challenge_left = challenge_seconds()
	for w in count:
		_waves.append([])
	for i in size:
		(_waves[floori(float(i * count) / float(size))] as Array).append([str(kinds[_rng.randi_range(0, kinds.size() - 1)]), health_scale(), false])
	if room_kind == "elite":
		var elites: Array = info["elites"]
		(_waves[count - 1] as Array).append([str(elites[_rng.randi_range(0, elites.size() - 1)]),
			health_scale() * ELITE_HEALTH, true])
	_next_wave()


func _next_wave() -> void:
	"""The next wave marked on the floor, at the room's edges."""
	if _waves.is_empty():
		return
	var wave: Array = _waves.pop_front()
	for entry in wave:
		_coming.append([entry[0], _edge_spot(), entry[1], entry[2], MARK_SECONDS])
	_wave_clock = 0.0
	_paint_marks()


func waves_left() -> int:
	return _waves.size()


func _step_waves(delta: float) -> void:
	_wave_clock += delta
	if not _coming.is_empty():
		var still: Array = []
		for entry in _coming:
			entry[4] = float(entry[4]) - delta
			if float(entry[4]) <= 0.0:
				var monster: Node2D = _bring(str(entry[0]), entry[1], float(entry[2]))
				if monster != null and bool(entry[3]):
					_dress_elite(monster)
			else:
				still.append(entry)
		_coming = still
		_paint_marks()
	if not _waves.is_empty() and _coming.is_empty() \
			and (living() <= WAVE_NEXT_AT or _wave_clock >= WAVE_SECONDS):
		_next_wave()


func _dress_elite(elite: Node2D) -> void:
	elite.scale = Vector2(ELITE_SIZE, ELITE_SIZE)
	elite.set_meta(&"descent_elite", true)
	var ring := Node2D.new()
	ring.name = "elitering"
	ring.z_index = -1
	ring.draw.connect(_draw_elite_ring.bind(ring))
	elite.add_child(ring)


func _edge_spot() -> Vector2:
	"""Somewhere along the room's back wall or its sides, clear of the
	player - where a wave steps out from."""
	var player: Node2D = _player()
	var mine: Vector2 = player.global_position if player != null else entry_spot
	for attempt in 24:
		var at: Vector2
		match _rng.randi_range(0, 2):
			0:
				at = Vector2(_rng.randf_range(room_rect.position.x + 24.0, room_rect.end.x - 24.0),
					room_rect.position.y + _rng.randf_range(10.0, 30.0))
			1:
				at = Vector2(room_rect.position.x + _rng.randf_range(14.0, 34.0),
					_rng.randf_range(room_rect.position.y + 10.0, room_rect.end.y - 60.0))
			_:
				at = Vector2(room_rect.end.x - _rng.randf_range(14.0, 34.0),
					_rng.randf_range(room_rect.position.y + 10.0, room_rect.end.y - 60.0))
		if at.distance_to(mine) >= SPAWN_CLEAR:
			return at
	return _spot()


func _paint_marks() -> void:
	"""Each coming monster's spot, a ring on the floor that closes as it comes."""
	if _marks == null or not is_instance_valid(_marks):
		var holder: Node = get_parent()
		if holder == null or _coming.is_empty():
			return
		_marks = Node2D.new()
		_marks.name = "wavemarks"
		_marks.z_index = -1
		_marks.draw.connect(_draw_marks)
		holder.add_child(_marks)
	_marks.queue_redraw()


func _draw_marks() -> void:
	for entry in _coming:
		var at: Vector2 = entry[1]
		var left: float = clampf(float(entry[4]) / MARK_SECONDS, 0.0, 1.0)
		var colour := Color(1.0, 0.45, 0.25) if bool(entry[3]) else Color(0.75, 0.55, 1.0)
		_marks.draw_set_transform(at, 0.0, Vector2(1.0, 0.5))
		_marks.draw_circle(Vector2.ZERO, 10.0, Color(colour, 0.18 + 0.3 * (1.0 - left)))
		_marks.draw_arc(Vector2.ZERO, 6.0 + 10.0 * left, 0.0, TAU, 20, Color(colour * 1.6, 0.9), 1.5)


func _draw_elite_ring(ring: Node2D) -> void:
	ring.draw_set_transform(Vector2(0, 2), 0.0, Vector2(1.0, 0.5))
	ring.draw_circle(Vector2.ZERO, 14.0, Color(1.0, 0.5, 0.2, 0.3))
	ring.draw_arc(Vector2.ZERO, 14.0, 0.0, TAU, 24, Color(1.8, 1.0, 0.5, 0.95), 1.5)


func _spot(prefer: Vector2 = Vector2.INF) -> Vector2:
	"""Somewhere on the floor, clear of the player (and of the room's front,
	where they come in)."""
	if prefer != Vector2.INF:
		return prefer
	var player: Node2D = _player()
	var mine: Vector2 = player.global_position if player != null else entry_spot
	var area := Rect2(room_rect.position + Vector2(16, 12), room_rect.size - Vector2(32, 70))
	for attempt in 24:
		var at := Vector2(_rng.randf_range(area.position.x, area.end.x), _rng.randf_range(area.position.y, area.end.y))
		if at.distance_to(mine) >= SPAWN_CLEAR:
			return at
	return area.position + Vector2(_rng.randf() * area.size.x, 0.0)


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
	"""A monster down, counted once - as it falls (living() sees it), not a
	second later when its body goes: Momentum is felt at the kill."""
	if not running() or monster.has_meta(&"descent_fallen"):
		return
	monster.set_meta(&"descent_fallen", true)
	slain += 1
	Boons.note_kill()


func _clear_monsters() -> void:
	for m in monsters:
		if is_instance_valid(m):
			(m as Node).tree_exiting.disconnect(_on_monster_gone)
			(m as Node).queue_free()
	monsters.clear()
	_waves = []
	_coming = []
	_paint_marks()


# =============================================================================
# THE DOUBLE AXE AND AXE FURY (0.115.0)
# =============================================================================

func wears_axe() -> bool:
	"""The player has the Double Axe on: its mythic upgrades and Fury are theirs."""
	var player: Node2D = _player()
	return player != null and player.has_method("equipped_weapon_attack") \
		and int(player.call("equipped_weapon_attack")) == ItemData.WeaponAttack.SPINNING_AXE


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.keycode != KEY_Q:
		return
	if unleash_fury() != null:
		get_viewport().set_input_as_handled()


func unleash_fury() -> Node2D:
	"""Q with the Fury full, in a fight, the Double Axe on: the giant axe."""
	if state != State.FIGHT or not Boons.fury_full() or not wears_axe():
		return null
	var holder: Node = get_parent()
	var player: Node2D = _player()
	if holder == null or player == null:
		return null
	Boons.fury = 0
	var giant := GiantAxe.new()
	giant.name = "giantaxe"
	giant.z_index = 5
	giant.centre = room_rect.get_center()
	giant.radii = room_rect.size * FURY_RADII
	var from: Vector2 = player.global_position - giant.centre
	giant.angle = atan2(from.y / maxf(giant.radii.y, 1.0), from.x / maxf(giant.radii.x, 1.0))
	var swing: int = int(player.call("_calculate_melee_damage")) if player.has_method("_calculate_melee_damage") else 50
	giant.cut = swing * FURY_SWINGS
	if ResourceLoader.exists(AXE_SCENE):
		var axe: Node = (load(AXE_SCENE) as PackedScene).instantiate()
		var spin: AnimatedSprite2D = axe.get_node_or_null("spin") as AnimatedSprite2D
		if spin != null:
			var sprite := AnimatedSprite2D.new()
			sprite.name = "spin"
			sprite.sprite_frames = spin.sprite_frames
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sprite.scale = Vector2(FURY_SCALE, FURY_SCALE) * spin.scale
			sprite.speed_scale = 2.5
			giant.add_child(sprite)
			sprite.play(spin.animation)
		axe.free()
	holder.add_child(giant)
	giant.global_position = giant.centre + Vector2(cos(giant.angle) * giant.radii.x, sin(giant.angle) * giant.radii.y)
	giant.reset_physics_interpolation()
	if hud != null:
		hud.call("announce", "AXE FURY!", "")
	return giant


func _light_fire() -> void:
	"""A Rest's fire, in the middle of the room."""
	if _decor == null or not is_instance_valid(_decor) or not ResourceLoader.exists(REST_FIRE):
		return
	var fire := (load(REST_FIRE) as PackedScene).instantiate() as Node2D
	fire.name = "restfire"
	fire.position = room_rect.get_center()
	_decor.add_child(fire)


func _dress() -> void:
	"""The room's things, new each room: along its edges, out of the way."""
	if _decor != null and is_instance_valid(_decor):
		_decor.queue_free()
	var props: Node = get_parent().get_node_or_null("ysortworld/props") if get_parent() != null else null
	if props == null:
		return
	_decor = Node2D.new()
	_decor.name = "roomthings"
	_decor.y_sort_enabled = true
	props.add_child(_decor)
	var count: int = _rng.randi_range(4, 7)
	for i in count:
		var path: String = str(DECOR[_rng.randi_range(0, DECOR.size() - 1)])
		var side: int = _rng.randi_range(0, 3)
		var at: Vector2
		match side:
			0:
				at = Vector2(room_rect.position.x + _rng.randf_range(10.0, 40.0), _rng.randf_range(room_rect.position.y + 20.0, room_rect.end.y - 30.0))
			1:
				at = Vector2(room_rect.end.x - _rng.randf_range(10.0, 40.0), _rng.randf_range(room_rect.position.y + 20.0, room_rect.end.y - 30.0))
			2:
				at = Vector2(_rng.randf_range(room_rect.position.x + 20.0, room_rect.position.x + 120.0), room_rect.position.y + _rng.randf_range(4.0, 20.0))
			_:
				at = Vector2(_rng.randf_range(room_rect.end.x - 120.0, room_rect.end.x - 20.0), room_rect.position.y + _rng.randf_range(4.0, 20.0))
		var thing := (load(path) as PackedScene).instantiate() as Node2D
		thing.position = at
		_decor.add_child(thing)


# =============================================================================
# A FALL, AND THE END
# =============================================================================

func knock_out(player: Node) -> bool:
	"""Player.take_damage(), on the blow that would kill: here you wake at the
	room's front on 1 health, every effect cleared, and the run is over. Off
	this area, false - the ordinary death goes ahead."""
	if player == null or not (player is Node2D) or not is_inside_tree():
		return false
	var body := player as Node2D
	if not room_rect.grow(96.0).has_point(body.global_position):
		return false
	player.set("hp", 1)
	var effects: Node = StatusEffects.of(player)
	if effects != null and effects.has_method("clear_all"):
		effects.call("clear_all")
	# SECOND WIND (0.115.0): once a floor, you stay standing where you are,
	# on 1 health and a full ward, and the run goes on.
	if running() and Boons.second_wind():
		fill_ward()
		if hud != null:
			hud.call("announce", "Second Wind!", "Back on your feet - your ward is full")
		return true
	body.global_position = entry_spot
	body.reset_physics_interpolation()
	if body.has_method("snap_camera"):
		body.call("snap_camera")
	if running():
		_end_run(false)
	return true


func _end_run(won: bool) -> void:
	var words: String = ("You reached the bottom!" if won else "You fell on floor %d, room %d" % [floor_index + 1, room]) \
		+ "  -  %d slain  -  %d upgrades  -  %d gold" % [slain, picks, gold]
	last_result = words
	if won or best == "":
		best = words
	_clear_monsters()
	Boons.clear()
	_drop_ward_ring()
	offers = []
	state = State.WAITING
	room = 0
	room_kind = ""
	_set_doors(true, "begin", "begin")
	if hud != null:
		hud.call("hide_pick")
		hud.call("show_result", words, won)
