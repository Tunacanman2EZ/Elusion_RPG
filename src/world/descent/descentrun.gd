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
		"keeper": "fireboss", "keeper_name": "The Fire Keeper", "health": 1.0},
	{"name": "the Frozen Halls", "monsters": ["icesprite", "iceslime", "icebushmage"],
		"elites": ["icefiresprite", "icebushsniper"], "keeper": "iceboss", "keeper_name": "The Ice Keeper",
		"health": 1.6},
	{"name": "the Dark Below", "monsters": ["darksprite", "darkslime", "darkbushmage"],
		"elites": ["darkfiresprite", "darkbushsniper"], "keeper": "bossenemy", "keeper_name": "The Dark Keeper",
		"health": 2.3},
]
# What a door can promise, and how often.
const KINDS := ["upgrade", "gold", "elite"]
const KIND_WEIGHTS := [40, 35, 25]
# A pack: PACK_FIRST + the room's number + PACK_FLOOR a floor down.
const PACK_FIRST := 3
const PACK_FLOOR := 2
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
	_go("upgrade")


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
	room += 1
	room_kind = "keeper" if room > ROOMS else kind
	_clear_monsters()
	_dress()
	var player: Node2D = _player()
	if player != null:
		player.global_position = entry_spot
		player.reset_physics_interpolation()
		if player.has_method("snap_camera"):
			player.call("snap_camera")
	_fight_in = FIGHT_DELAY
	if hud != null:
		hud.call("announce", room_title(), _room_line())


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
		State.FIGHT:
			if _fight_in >= 0.0:
				_fight_in -= delta
				if _fight_in < 0.0:
					_spawn_pack()
			elif living() == 0:
				_room_cleared()


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
		still.append(m)
	monsters = still
	return count


func _room_cleared() -> void:
	var info: Dictionary = floor_info()
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
			_offer()
		_:
			_offer()


func _pay(amount: int) -> void:
	var paid: int = roundi(float(amount) * Boons.gold_factor())
	gold += paid
	if hud != null:
		hud.call("toast", "+%d gold" % paid)


func _offer() -> void:
	offers = Boons.offers(_rng)
	if offers.is_empty():
		_open_doors()
		return
	state = State.PICK
	if hud != null:
		hud.call("show_pick", offers)


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
	return PACK_FIRST + room + PACK_FLOOR * floor_index


func health_scale() -> float:
	return float(floor_info()["health"]) * (1.0 + ROOM_HEALTH_STEP * (room - 1))


func _spawn_pack() -> void:
	var info: Dictionary = floor_info()
	if room_kind == "keeper":
		_bring(str(info["keeper"]), _spot(Vector2(room_rect.get_center().x, room_rect.position.y + 80.0)),
			float(info["health"]) * KEEPER_HEALTH)
		return
	var kinds: Array = info["monsters"]
	for i in pack_size():
		_bring(str(kinds[_rng.randi_range(0, kinds.size() - 1)]), _spot(), health_scale())
	if room_kind == "elite":
		var elites: Array = info["elites"]
		var elite: Node2D = _bring(str(elites[_rng.randi_range(0, elites.size() - 1)]), _spot(),
			health_scale() * ELITE_HEALTH)
		if elite != null:
			elite.scale = Vector2(ELITE_SIZE, ELITE_SIZE)
			elite.set_meta(&"descent_elite", true)
			var ring := Node2D.new()
			ring.name = "elitering"
			ring.z_index = -1
			ring.draw.connect(_draw_elite_ring.bind(ring))
			elite.add_child(ring)


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
	if running() and int(monster.get("hp")) <= 0:
		slain += 1


func _clear_monsters() -> void:
	for m in monsters:
		if is_instance_valid(m):
			(m as Node).tree_exiting.disconnect(_on_monster_gone)
			(m as Node).queue_free()
	monsters.clear()


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
	offers = []
	state = State.WAITING
	room = 0
	room_kind = ""
	_set_doors(true, "begin", "begin")
	if hud != null:
		hud.call("hide_pick")
		hud.call("show_result", words, won)
