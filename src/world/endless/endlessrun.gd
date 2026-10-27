# endlessrun.gd - the endless run: a corridor, a door, and a horde that grows
# until you fall (0.93.0).
#
# The owner: "a endless type map where monsters increase difficulty as time
# progresses", "a corridor with a door as the first area then when walking
# through the door the spawn begins with a timer pumping out monsters and
# elites and occasionally 1 of the elemental bosses", and of dying: "if player
# dies they can walk to the chest and collect". This is the first step of it,
# in this game alone (the party's shared horde and the server's chest come
# next):
#
#   WAITING   the player stands in the corridor. The crypt door at its end
#             opens with the interact key, as every crypt door does.
#   RUNNING   the moment the player steps through it into the arena
#             (start_rect), the clock starts and the door shuts and stays
#             shut (cryptdoor.gd's lock()). Every STAGE_SECONDS is a stage:
#             the swarm (swarm.gd) grows toward stage_crowd(), each new
#             swarmling tougher, faster and harder-hitting (stage_health(),
#             stage_speed(), stage_touch()), in the next land's colour
#             (STAGE_LANDS: light and wind first, dark last, round again).
#             Every ELITE_SECONDS from stage 2, real monsters of that land
#             join it (ELITES); every BOSS_EVERY stages, that land's boss.
#   OVER      the player falls: they wake in the corridor (knock_out()), the
#             run ends, the arena empties and the door unlocks.
#
# A FALL HERE IS NOT A DEATH. Player.take_damage() asks knock_out() before it
# starts dying; inside a run the player is left on 1 health and put back in the
# corridor, keeping everything they carry and wear. Nothing is healed - health
# comes back the ordinary way, by regeneration, so the server's healing check
# (which allows regeneration and nothing it cannot explain) has nothing to
# clamp.
#
# THE ELITES AND BOSSES ARE THIS GAME'S AND WORTH NOTHING YET: they carry the
# owner's stress-copy mark (stresscrowd.gd), so they report no kill, are never
# shared and never counted. Paying for a run - the chest - is the server's,
# and comes with the next step.
extends Node

const SwarmScript := preload("res://src/world/endless/swarm.gd")

const STAGE_SECONDS := 60.0
# The lands in order, then round again: the bands' own order.
const STAGE_LANDS := [Element.Type.LIGHT, Element.Type.WIND, Element.Type.WATER,
	Element.Type.ICE, Element.Type.EARTH, Element.Type.FIRE, Element.Type.DARK]
const ELITE_SECONDS := 30.0
const BOSS_EVERY := 5
# How many swarmlings a second may come in, at stage 1 and for each stage more.
const SPAWN_RATE := 25.0
const SPAWN_RATE_STEP := 15.0
# How long the arena stays as it was once the run is over, before it empties.
const CLEAR_AFTER := 2.0
const STRESS_MARK := &"stress_copy"

# Each land's monsters that come as elites, and its boss.
const ELITES := {
	Element.Type.LIGHT: ["lightsprite", "lightbushmage", "lightfiresprite", "lightbushsniper"],
	Element.Type.WIND: ["windsprite", "windbushmage", "windfiresprite", "windbushsniper"],
	Element.Type.WATER: ["watersprite", "waterbushmage", "waterfiresprite", "waterbushsniper"],
	Element.Type.ICE: ["icesprite", "icebushmage", "icefiresprite", "icebushsniper"],
	Element.Type.EARTH: ["earthsprite", "bushmage", "earthfiresprite", "earthbushsniper"],
	Element.Type.FIRE: ["firesprite", "firebushmage"],
	Element.Type.DARK: ["darksprite", "darkbushmage", "darkfiresprite", "darkbushsniper"],
}
const BOSSES := {
	Element.Type.LIGHT: "lightboss", Element.Type.WIND: "windboss",
	Element.Type.WATER: "waterboss", Element.Type.ICE: "iceboss",
	Element.Type.EARTH: "earthboss", Element.Type.FIRE: "fireboss",
	Element.Type.DARK: "bossenemy",
}
const LAND_NAMES := {
	Element.Type.LIGHT: "Light", Element.Type.WIND: "Wind", Element.Type.WATER: "Water",
	Element.Type.ICE: "Ice", Element.Type.EARTH: "Earth", Element.Type.FIRE: "Fire",
	Element.Type.DARK: "Dark",
}

enum State { WAITING, RUNNING, OVER }

# Set by the scene (src/tools/buildendless.gd writes them).
@export var arena_rect: Rect2 = Rect2(24, 24, 1488, 1344)
@export var corridor_rect: Rect2 = Rect2(690, 980, 160, 420)
@export var start_rect: Rect2 = Rect2(729, 930, 78, 52)
@export var wake_spot: Vector2 = Vector2(768, 1240)
@export var door_path: NodePath = NodePath("../ysortworld/props/rundoor")

var state: int = State.WAITING
var elapsed: float = 0.0
var stage: int = 0
var best: float = 0.0
var swarm: Node2D = null
var _spawn_owed: float = 0.0
var _elite_left: float = ELITE_SECONDS
var _extras: Array = []
var _hud: Node = null
var _clear_left: float = -1.0
var _last_result: String = ""


func _ready() -> void:
	add_to_group(&"endless_run")
	swarm = SwarmScript.new()
	swarm.set("arena", arena_rect)
	(swarm.get("keep_out") as Array).append(corridor_rect)
	var ground: Node = get_parent().get_node_or_null("ysortworld/groundeffects")
	(ground if ground != null else get_parent()).add_child.call_deferred(swarm)
	_hud = (load("res://src/world/endless/endlesshud.gd") as GDScript).new()
	_hud.set("run", self)
	add_child(_hud)


# =============================================================================
# THE NUMBERS - static, so the suite can read the curve without a run
# =============================================================================

static func land_of(stage_number: int) -> int:
	return int(STAGE_LANDS[(maxi(1, stage_number) - 1) % STAGE_LANDS.size()])


static func stage_crowd(stage_number: int) -> int:
	"""How many swarmlings the arena fills to at this stage: 60 at the first,
	then more each stage, never past the swarm's MOST (3,000)."""
	var s: int = maxi(1, stage_number) - 1
	return mini(SwarmScript.MOST, 60 + 90 * s + 12 * s * s)


static func stage_health(stage_number: int) -> float:
	"""A new swarmling's health: 24 at the first stage, a fifth more each one
	after - the crowd stops growing at 3,000, so this is what keeps climbing."""
	return 24.0 * pow(1.22, maxi(1, stage_number) - 1)


static func stage_speed(stage_number: int) -> float:
	return minf(95.0, 50.0 + 3.0 * float(maxi(1, stage_number)))


static func stage_touch(stage_number: int) -> int:
	return 3 + 2 * maxi(1, stage_number)


static func elites_at(stage_number: int) -> int:
	return 0 if stage_number < 2 else 1 + stage_number / 3


static func clock_text(seconds: float) -> String:
	var s: int = int(seconds)
	return "%02d:%02d" % [s / 60, s % 60]


# =============================================================================
# EACH FRAME
# =============================================================================

func _process(delta: float) -> void:
	if state == State.WAITING:
		var player: Node2D = _player()
		if player != null and start_rect.has_point(player.global_position):
			start()
		return
	if state == State.OVER:
		if _clear_left >= 0.0:
			_clear_left -= delta
			if _clear_left < 0.0:
				_clear_arena()
		return
	elapsed += delta
	var now: int = 1 + int(elapsed / STAGE_SECONDS)
	if now != stage:
		_enter_stage(now)
	# THE CROWD FILLS AT A RATE, not all at once - a thousand at a stage's
	# turn would arrive as a wall.
	var short: int = stage_crowd(stage) - int(swarm.get("alive"))
	if short > 0:
		_spawn_owed += (SPAWN_RATE + SPAWN_RATE_STEP * float(stage)) * delta
		var now_count: int = mini(short, int(_spawn_owed))
		if now_count > 0:
			_spawn_owed -= float(now_count)
			var player: Node2D = _player()
			swarm.call("spawn", now_count, player.global_position if player != null else arena_rect.get_center())
	else:
		_spawn_owed = 0.0
	_elite_left -= delta
	if _elite_left <= 0.0:
		_elite_left = ELITE_SECONDS
		for i in elites_at(stage):
			_bring(_elite_scene(stage, i))


func start() -> void:
	"""The player has stepped through the door: the clock starts and the door
	shuts behind them."""
	if state == State.RUNNING:
		return
	_clear_arena()
	state = State.RUNNING
	elapsed = 0.0
	stage = 0
	_spawn_owed = 0.0
	_elite_left = ELITE_SECONDS
	swarm.set("slain", 0)
	var door: Node = get_node_or_null(door_path)
	if door != null and door.has_method("lock"):
		door.call("lock", true)
	_enter_stage(1)
	Audio.play("teleport")


func _enter_stage(number: int) -> void:
	stage = number
	var land: int = land_of(stage)
	swarm.set("element", land)
	swarm.set("max_hp", stage_health(stage))
	swarm.set("speed", stage_speed(stage))
	swarm.set("touch_damage", stage_touch(stage))
	if _hud != null:
		_hud.call("announce", "Stage %d  ·  %s" % [stage, LAND_NAMES.get(land, "?")])
	if stage % BOSS_EVERY == 0:
		_bring(_boss_scene(stage))


func _elite_scene(stage_number: int, nth: int) -> String:
	var kinds: Array = ELITES.get(land_of(stage_number), ["lightsprite"])
	return "res://scene/enemy/%s.tscn" % kinds[(stage_number + nth) % kinds.size()]


func _boss_scene(stage_number: int) -> String:
	return "res://scene/enemy/%s.tscn" % BOSSES.get(land_of(stage_number), "lightboss")


func _bring(path: String) -> void:
	"""A real monster into the arena, at an edge away from the player, after
	the player from the start (its notice and leash are the arena's size)."""
	var packed: PackedScene = load(path) as PackedScene
	var container: Node = get_parent().get_node_or_null("ysortworld/enemies")
	if packed == null or container == null:
		return
	var player: Node2D = _player()
	var spot: Vector2 = swarm.call("_edge_spot", player.global_position if player != null else arena_rect.get_center())
	if spot == Vector2.INF:
		return
	var monster := packed.instantiate() as Node2D
	monster.set_meta(STRESS_MARK, true)
	var far: float = arena_rect.size.length()
	if "notice_range" in monster:
		monster.set("notice_range", far)
	if "leash_range" in monster:
		monster.set("leash_range", far)
	# Before add_child(): BaseEnemy._ready() reads its spot as home.
	monster.position = spot
	container.add_child(monster)
	monster.global_position = spot
	monster.reset_physics_interpolation()
	if "spawn_position" in monster:
		monster.set("spawn_position", spot)
	_extras.append(monster)


# =============================================================================
# A FALL
# =============================================================================

func knock_out(player: Node) -> bool:
	"""Player.take_damage(), on the blow that would kill: inside a run, the
	player wakes in the corridor on 1 health and the run is over. Anywhere
	else, false - the ordinary death goes ahead."""
	if state != State.RUNNING or player == null or not (player is Node2D):
		return false
	var body := player as Node2D
	if not arena_rect.grow(32.0).has_point(body.global_position):
		return false
	player.set("hp", 1)
	body.global_position = wake_spot
	body.reset_physics_interpolation()
	if body.has_method("snap_camera"):
		body.call("snap_camera")
	_end_run()
	return true


func _end_run() -> void:
	state = State.OVER
	best = maxf(best, elapsed)
	_last_result = "You lasted %s  ·  stage %d  ·  %s slain" % [clock_text(elapsed), stage,
		GameConstants.commas(int(swarm.get("slain")))]
	if _hud != null:
		_hud.call("show_result", _last_result, clock_text(best))
	_clear_left = CLEAR_AFTER


func _clear_arena() -> void:
	_clear_left = -1.0
	swarm.call("clear")
	for monster in _extras:
		if is_instance_valid(monster):
			(monster as Node).queue_free()
	_extras.clear()
	var door: Node = get_node_or_null(door_path)
	if door != null and door.has_method("lock"):
		door.call("lock", false)
	if state == State.OVER:
		state = State.WAITING


func _player() -> Node2D:
	return get_tree().get_first_node_in_group(&"player") as Node2D if is_inside_tree() else null


func result_line() -> String:
	return _last_result
