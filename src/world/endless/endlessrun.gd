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
#             Every elite_gap() from stage 2, real monsters of that land
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
# THE ELITES AND BOSSES ARE WORTH NOTHING YET: they carry RUN_MARK, so they
# report no kill and are never respawned; since 0.93.3 they are shared with a
# party like any monster (monstersync.gd), where they carried the owner's
# stress-copy mark and were this game's alone. Paying for a run - the chest -
# is the server's, and comes later.
#
# A PARTY (0.93.3). The owner: "we need a 4 player party plan but can play
# solo duo or 3 or 4". With others in the arena (the party's own -
# endlessparty.gd says who leads and passes the rest):
#   COUNTDOWN  the first through the door starts COUNTDOWN_SECONDS on every
#              screen; the door is held open (cryptdoor.gd hold()) so the
#              party comes through together. At zero the clock starts.
#   RUNNING    the leader's game spawns and brings the elites; the others
#              follow its line. Each new stage holds the door open
#              DOOR_OPEN_SECONDS, so whoever is in the corridor - late, or back
#              from a fall - can walk in.
#   A FALL     wakes the player in the corridor, as alone, and the run goes on
#              while anybody is in. Back in at the next stage, on the health
#              resting has brought back: the corridor heals nobody (the
#              server's healing check would take a heal back).
#   OVER       when nobody is in. One result for the party, and your own kills.
# The party is scaled (party_crowd(), party_health(), party_elites(),
# party_boss()): more slimes, a little tougher, more elites, much tougher
# bosses - never harder-hitting slimes, since each player is hurt only by the
# slimes on their own screen.
extends Node

const SwarmScript := preload("res://src/world/endless/swarm.gd")
const PartyScript := preload("res://src/world/endless/endlessparty.gd")
const SpikePath := preload("res://src/world/endless/spikepath.gd")
const StatusEffects := preload("res://src/characters/statuseffects.gd")
const Targets := preload("res://src/shared/targets.gd")

const STAGE_SECONDS := 60.0
# The lands in order, then round again: the bands' own order.
const STAGE_LANDS := [Element.Type.LIGHT, Element.Type.WIND, Element.Type.WATER,
	Element.Type.ICE, Element.Type.EARTH, Element.Type.FIRE, Element.Type.DARK]
# THE ELITE WAVES (0.93.3, the owner: "we need to spawn more elites in as time
# progresses"): a wave every elite_gap() seconds - ELITE_GAP_START less
# ELITE_GAP_STEP a stage, never under ELITE_GAP_MIN - of elites_at() (1 +
# stage/2, from stage 2) and the party's extra (party_elites()); never more
# than elites_alive_cap() alive at once - each is a full monster, so the cap
# keeps the frame steady - and a wave waits while the arena is full. About 24
# a minute at stage 10 alone, against 8 before.
const ELITE_GAP_START := 32.0
const ELITE_GAP_STEP := 2.0
const ELITE_GAP_MIN := 15.0
const ELITES_ALIVE := 40
const ELITES_ALIVE_EACH := 10
# FEEL EACH LAND (0.93.3, the owner: "we need to really feel each elements
# effect"). The swarm's touch puts the land's effect on you (swarm.gd
# touch_effect, at most one every EFFECT_GAP), but wind's shove comes from its
# spike paths (spikepath.gd): one near you every SPIKE_GAP seconds, the first
# SPIKE_FIRST into the stage, a line of up to SPIKE_COUNT spikes at a random
# angle starting SPIKE_LEAD behind you and passing within SPIKE_MISS of you,
# each tick hitting for stage_touch() x SPIKE_HIT. The floor takes the land's
# colour - a wash of it added over the arena (`floor_wash`, FLOOR_WASH strong,
# eased in over FLOOR_TINT_SECONDS; the floor is too dark for a multiplied
# tint to show) - and the stage's banner says what the land does (LAND_FELT).
const SPIKE_GAP := 3.5
const SPIKE_FIRST := 2.0
const SPIKE_COUNT := 10
const SPIKE_LEAD := 140.0
const SPIKE_MISS := 24.0
const SPIKE_HIT := 2
const FLOOR_WASH := 0.12
const FLOOR_TINT_SECONDS := 2.0
# Over the floor (-10), under the swarm (-1) and everything standing.
const WASH_Z := -9
const LAND_FELT := {
	Element.Type.LIGHT: "The light dazzles you",
	Element.Type.WIND: "Spikes rise and throw you back",
	Element.Type.WATER: "Soaked, your defence is halved",
	Element.Type.ICE: "The cold freezes you",
	Element.Type.EARTH: "The earth roots you",
	Element.Type.FIRE: "The fire burns you",
	Element.Type.DARK: "The dark doubles every hit",
}
const BOSS_EVERY := 5
# How many swarmlings a second may come in, at stage 1 and for each stage more.
const SPAWN_RATE := 25.0
const SPAWN_RATE_STEP := 15.0
# How long the arena stays as it was once the run is over, before it empties.
const CLEAR_AFTER := 2.0
# A run's elites and bosses (BaseEnemy.get_enemy_id(), monstersync.gd).
const RUN_MARK := &"run_extra"
# A party: how long the door waits for it, and stays open at each new stage.
const COUNTDOWN_SECONDS := 5.0
const DOOR_OPEN_SECONDS := 3.0
# A party run is not over while somebody says they are in; for this long after
# it starts (or changes hands) nobody has had time to say so.
const START_GRACE := 2.0
# How far apart a party's fallen wake in the corridor (wake_for()).
const WAKE_STEP := 22.0

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

# In this order: the wire (endlessparty.gd's line) carries the number.
enum State { WAITING, RUNNING, OVER, COUNTDOWN }

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
var _elite_left: float = ELITE_GAP_START
var _spike_left: float = SPIKE_FIRST
var _spike_rng := RandomNumberGenerator.new()
# The wash of the land's colour over the arena's floor, and what it eases
# toward (floor_tint_for()); clear outside a run.
var floor_wash: ColorRect = null
var floor_goal: Color = Color(0, 0, 0, 0)
var _extras: Array = []
var _hud: Node = null
var _clear_left: float = -1.0
var _last_result: String = ""
# A PARTY (0.93.3).
var party: Node = null
# How many players this run is scaled for (1 alone).
var players: int = 1
# This game's player is in the run: past the door, on the arena's floor.
var my_in: bool = false
var countdown_left: float = 0.0
# (Leader.) The door held open this much longer.
var door_left: float = 0.0
var door_open: bool = false
# The party's line, as the leader last said it (followers) or says it.
var party_slain: int = 0
var party_in: int = 0
var _grace_left: float = 0.0
# Whether this game ran the run last frame (take_over()).
var _led: bool = true


func _ready() -> void:
	add_to_group(&"endless_run")
	_spike_rng.randomize()
	floor_wash = ColorRect.new()
	floor_wash.name = "landwash"
	floor_wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	floor_wash.position = arena_rect.position
	floor_wash.size = arena_rect.size
	floor_wash.z_index = WASH_Z
	floor_wash.color = Color(0, 0, 0, 0)
	var adding := CanvasItemMaterial.new()
	adding.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	floor_wash.material = adding
	get_parent().add_child.call_deferred(floor_wash)
	swarm = SwarmScript.new()
	swarm.set("arena", arena_rect)
	(swarm.get("keep_out") as Array).append(corridor_rect)
	var ground: Node = get_parent().get_node_or_null("ysortworld/groundeffects")
	(ground if ground != null else get_parent()).add_child.call_deferred(swarm)
	_hud = (load("res://src/world/endless/endlesshud.gd") as GDScript).new()
	_hud.set("run", self)
	add_child(_hud)
	if party == null:
		party = PartyScript.new()
		party.name = "party"
		party.set("run", self)
		add_child(party)
	# ONE WAY IN (0.93.3): the owner, "the door needs to be 1 way entry also".
	# The way out is the Minigames card's Leave (minigamescard.gd), or the
	# corridor's ladder for anybody who never went through.
	_one_way_door.call_deferred()


func _one_way_door() -> void:
	var door: Node = get_node_or_null(door_path)
	if door != null and door.has_method("one_way"):
		door.call("one_way", true)


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
	return 0 if stage_number < 2 else 1 + stage_number / 2


static func elite_gap(stage_number: int) -> float:
	return maxf(ELITE_GAP_MIN, ELITE_GAP_START - ELITE_GAP_STEP * float(maxi(1, stage_number)))


static func elites_alive_cap(count: int) -> int:
	return ELITES_ALIVE + ELITES_ALIVE_EACH * (clampi(count, 1, 4) - 1)


static func touch_effect_for(land: int) -> StringName:
	"""What the swarm's touch puts on you in this land: the land's own effect
	(statuseffects.gd), but none in wind - its spike paths shove instead."""
	if land == Element.Type.WIND:
		return &""
	return StatusEffects.for_element(land)


static func floor_tint_for(land: int) -> Color:
	var colour: Color = Element.colour_for(land)
	return Color(colour.r, colour.g, colour.b, FLOOR_WASH)


# A PARTY'S SCALING (0.93.3), for 1 to 4 players: the plan's table, to be tuned
# by playing. The crowd still stops at the swarm's MOST.
static func party_crowd(count: int) -> float:
	return 1.0 + 0.5 * float(clampi(count, 1, 4) - 1)


static func party_health(count: int) -> float:
	return 1.0 + 0.2 * float(clampi(count, 1, 4) - 1)


static func party_elites(count: int) -> int:
	return clampi(count, 1, 4) - 1


static func party_boss(count: int) -> float:
	return 1.0 + 0.75 * float(clampi(count, 1, 4) - 1)


static func crowd_for(stage_number: int, count: int) -> int:
	return mini(SwarmScript.MOST, roundi(float(stage_crowd(stage_number)) * party_crowd(count)))


static func clock_text(seconds: float) -> String:
	var s: int = int(seconds)
	return "%02d:%02d" % [s / 60, s % 60]


# =============================================================================
# EACH FRAME
# =============================================================================

func shared() -> bool:
	"""A party run: somebody else is in the arena (endlessparty.gd)."""
	return party != null and party.call("active")


func leading() -> bool:
	"""This game runs the run: alone, or the party's leader."""
	return party == null or party.call("leads")


func in_arena(at: Vector2) -> bool:
	"""On the arena's floor, past the door - not in the corridor."""
	return arena_rect.has_point(at) and not corridor_rect.has_point(at)


func _process(delta: float) -> void:
	var player: Node2D = _player()
	my_in = (state == State.RUNNING or state == State.COUNTDOWN) and player != null \
		and player.get("is_dying") != true and in_arena(player.global_position)
	_ease_floor(delta)
	if state == State.WAITING:
		if player != null and start_rect.has_point(player.global_position):
			if not shared():
				start()
			elif leading():
				begin_countdown()
			else:
				party.call("ask_go")
		return
	if state == State.COUNTDOWN:
		countdown_left = maxf(0.0, countdown_left - delta)
		if leading() and countdown_left <= 0.0:
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
	# Wind's spike paths: every game raises its own, for its own player.
	_tick_spikes(delta, player)
	var lead_now: bool = leading()
	if lead_now and not _led:
		# THE LEADER LEFT and this game is next in line - or the link went and
		# it is alone: the run is ours now, from where it stands, before
		# anything is judged by who has said they are in.
		take_over()
	_led = lead_now
	if not lead_now:
		return
	_grace_left -= delta
	if door_left > 0.0:
		door_left -= delta
		if door_left <= 0.0:
			_set_door(false)
	# A PARTY RUN IS OVER WHEN NOBODY IS IN: each game says whether its player
	# is (endlessparty.gd "me").
	if shared() and _grace_left <= 0.0 and not my_in and int(party.call("others_in")) == 0:
		_end_run()
		return
	# THE CROWD FILLS AT A RATE, not all at once - a thousand at a stage's
	# turn would arrive as a wall.
	var short: int = crowd_for(stage, players) - int(swarm.get("alive"))
	if short > 0:
		_spawn_owed += (SPAWN_RATE + SPAWN_RATE_STEP * float(stage)) * party_crowd(players) * delta
		var now_count: int = mini(short, int(_spawn_owed))
		if now_count > 0:
			_spawn_owed -= float(now_count)
			if shared():
				party.call("spawn", now_count, _avoid_points(), roundi(stage_health(stage) * party_health(players)),
					land_of(stage))
			else:
				swarm.call("spawn", now_count, player.global_position if player != null else arena_rect.get_center())
	else:
		_spawn_owed = 0.0
	_elite_left -= delta
	if _elite_left <= 0.0:
		var wave: int = elites_at(stage) + (party_elites(players) if stage >= 2 else 0)
		var room: int = elites_alive_cap(players) - elites_alive()
		if wave > 0 and room <= 0:
			# THE ARENA IS FULL: the wave waits for room, and comes with it.
			_elite_left = 0.0
		else:
			_elite_left = elite_gap(stage)
			for i in mini(wave, room):
				_bring(_elite_scene(stage, i))


func elites_alive() -> int:
	"""This run's elites and bosses still standing (the leader's count)."""
	var alive: int = 0
	for monster in _extras:
		if is_instance_valid(monster) and monster.get("is_dying") != true:
			alive += 1
	return alive


func _tick_spikes(delta: float, player: Node2D) -> void:
	if land_of(stage) != Element.Type.WIND or player == null or not my_in:
		_spike_left = SPIKE_FIRST
		return
	_spike_left -= delta
	if _spike_left <= 0.0:
		_spike_left = SPIKE_GAP
		raise_spikes(player)


func raise_spikes(near: Node2D) -> Node2D:
	"""A spike path across the floor near `near` (spikepath.gd): a line at a
	random angle, starting SPIKE_LEAD behind them and passing within
	SPIKE_MISS of them, cut where it would leave the arena's floor. Null when
	too little of it would be on the floor."""
	if near == null:
		return null
	var direction: Vector2 = Vector2.RIGHT.rotated(_spike_rng.randf() * TAU)
	var start: Vector2 = Targets.body_point(near) - direction * SPIKE_LEAD \
		+ direction.orthogonal() * _spike_rng.randf_range(-SPIKE_MISS, SPIKE_MISS)
	var first: int = -1
	var count: int = 0
	for i in SPIKE_COUNT:
		if in_arena(start + direction * SpikePath.SPACING * i):
			if first < 0:
				first = i
			count += 1
		elif first >= 0:
			break
	if count < 3:
		return null
	var container: Node = get_parent().get_node_or_null("ysortworld/groundeffects")
	if container == null:
		container = get_parent()
	var path: Node2D = SpikePath.new()
	path.name = "spikepath"
	path.set("direction", direction)
	path.set("count", count)
	path.set("damage", stage_touch(stage) * SPIKE_HIT)
	path.set("target", near)
	container.add_child(path)
	path.global_position = start + direction * SpikePath.SPACING * first
	path.reset_physics_interpolation()
	return path


func _exit_tree() -> void:
	# The wash is the area's child, not the run's: it goes with the run.
	if floor_wash != null and is_instance_valid(floor_wash):
		floor_wash.queue_free()


func _ease_floor(delta: float) -> void:
	"""The floor's wash eases toward floor_goal while a run is on, and away
	once it is over, over about FLOOR_TINT_SECONDS."""
	if floor_wash == null or not is_instance_valid(floor_wash):
		return
	var goal: Color = floor_goal if state == State.RUNNING else Color(floor_goal.r, floor_goal.g, floor_goal.b, 0.0)
	var now: Color = floor_wash.color
	if now == goal:
		return
	var to: Color = now.lerp(goal, clampf(3.0 * delta / FLOOR_TINT_SECONDS, 0.0, 1.0))
	if absf(to.r - goal.r) + absf(to.g - goal.g) + absf(to.b - goal.b) + absf(to.a - goal.a) < 0.004:
		to = goal
	floor_wash.color = to


func _avoid_points() -> PackedVector2Array:
	"""Where new slimes keep clear of: every player of the party on the
	floor (this one's, and the others as drawn here)."""
	var points := PackedVector2Array()
	var player: Node2D = _player()
	if player != null and in_arena(player.global_position):
		points.append(player.global_position)
	if party != null:
		for at in party.call("other_positions"):
			if in_arena(at):
				points.append(at)
	if points.is_empty():
		points.append(arena_rect.get_center())
	return points


func begin_countdown() -> void:
	"""(A party's leader.) Somebody stepped through the door: the run starts in
	COUNTDOWN_SECONDS, and the door is held open until then."""
	if state != State.WAITING:
		return
	_clear_arena()
	state = State.COUNTDOWN
	countdown_left = COUNTDOWN_SECONDS
	_set_door(true)
	party.call("line_now")


func party_go() -> void:
	"""(A party's leader.) Another player stepped through the door first."""
	if state == State.WAITING:
		begin_countdown()


func _set_door(open: bool) -> void:
	door_open = open
	var door: Node = get_node_or_null(door_path)
	if door == null:
		return
	if open:
		if door.has_method("hold"):
			door.call("hold", true)
	elif door.has_method("lock"):
		door.call("lock", state == State.RUNNING)
	if leading() and party != null:
		party.call("line_now")


func start() -> void:
	"""The player has stepped through the door (alone), or the party's
	countdown is over: the clock starts and the door shuts behind them."""
	if state == State.RUNNING:
		return
	var counted: bool = state == State.COUNTDOWN
	if not counted:
		_clear_arena()
	# NOBODY CAME THROUGH: the countdown ran out with the party all back in the
	# corridor. No run.
	if counted and shared() and not my_in and int(party.call("others_in")) == 0:
		state = State.WAITING
		_set_door(false)
		return
	state = State.RUNNING
	elapsed = 0.0
	stage = 0
	_spawn_owed = 0.0
	_elite_left = elite_gap(1)
	_grace_left = START_GRACE
	players = int(party.call("members")) if party != null and shared() else 1
	swarm.set("slain", 0)
	swarm.set("my_slain", 0)
	door_left = 0.0
	_set_door(false)
	_enter_stage(1)
	Audio.play("teleport")


func take_over() -> void:
	"""The party's leader left and this game is next in line: the run carries
	on from where it stands, run from here now."""
	(swarm as Node).call("rebuild_free")
	_grace_left = START_GRACE
	_spawn_owed = 0.0
	_elite_left = minf(_elite_left, elite_gap(stage))


func _enter_stage(number: int) -> void:
	stage = number
	var land: int = land_of(stage)
	if leading() and shared():
		# The party as it is now: one who came in late counts from here.
		players = maxi(players, int(party.call("members")))
	swarm.set("element", land)
	swarm.set("max_hp", stage_health(stage) * party_health(players))
	swarm.set("speed", stage_speed(stage))
	swarm.set("touch_damage", stage_touch(stage))
	swarm.set("touch_effect", touch_effect_for(land))
	floor_goal = floor_tint_for(land)
	_spike_left = SPIKE_FIRST
	if _hud != null:
		_hud.call("announce", "Stage %d  ·  %s" % [stage, LAND_NAMES.get(land, "?")], str(LAND_FELT.get(land, "")))
	if not leading():
		return
	if stage % BOSS_EVERY == 0:
		_bring(_boss_scene(stage), party_boss(players))
	# THE DOOR OPENS AT EACH NEW STAGE, for a party: whoever is in the corridor
	# - late, or back from a fall - walks in.
	if shared() and stage >= 2:
		door_left = DOOR_OPEN_SECONDS
		_set_door(true)


func _elite_scene(stage_number: int, nth: int) -> String:
	var kinds: Array = ELITES.get(land_of(stage_number), ["lightsprite"])
	return "res://scene/enemy/%s.tscn" % kinds[(stage_number + nth) % kinds.size()]


func _boss_scene(stage_number: int) -> String:
	return "res://scene/enemy/%s.tscn" % BOSSES.get(land_of(stage_number), "lightboss")


func _bring(path: String, health_scale: float = 1.0) -> void:
	"""A real monster into the arena, at an edge away from the players, after
	them from the start (its notice and leash are the arena's size). In a
	party it is shared like any monster (monstersync.gd); a boss's health is
	`health_scale` times its own."""
	var packed: PackedScene = load(path) as PackedScene
	var container: Node = get_parent().get_node_or_null("ysortworld/enemies")
	if packed == null or container == null:
		return
	var avoid: PackedVector2Array = _avoid_points()
	var spot: Vector2 = Vector2.INF
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	spot = swarm.call("_edge_spot_from", rng, avoid)
	if spot == Vector2.INF:
		return
	var monster := packed.instantiate() as Node2D
	monster.set_meta(RUN_MARK, true)
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
	if health_scale > 1.0 and "max_hp" in monster:
		var most: int = roundi(float(monster.get("max_hp")) * health_scale)
		monster.set("max_hp", most)
		monster.set("hp", most)
		if monster.has_method("_refresh_health_display"):
			monster.call("_refresh_health_display")
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
	body.global_position = wake_for()
	body.reset_physics_interpolation()
	if body.has_method("snap_camera"):
		body.call("snap_camera")
	my_in = false
	if shared():
		# A PARTY GOES ON while anybody is in: back through the door at the
		# next stage.
		if _hud != null:
			_hud.call("announce", "You fell")
		if leading() and int(party.call("others_in")) == 0:
			_end_run()
		return true
	_end_run()
	return true


func wake_for() -> Vector2:
	"""Where this game's player wakes from a fall: wake_spot alone; in a party,
	a step to one side by its account, so two who fell are not drawn on top
	of each other."""
	if not shared():
		return wake_spot
	var me: int = int(party.get("link").call("my_id")) if party.get("link") != null else 0
	return wake_spot + Vector2((float(posmod(me, 4)) - 1.5) * WAKE_STEP, 0.0)


func _end_run() -> void:
	var was_party: bool = shared()
	state = State.OVER
	best = maxf(best, elapsed)
	door_left = 0.0
	door_open = false
	if was_party:
		_last_result = "The party lasted %s  ·  stage %d  ·  %s slain  ·  %s yours" % [clock_text(elapsed), stage,
			GameConstants.commas(int(swarm.get("slain"))), GameConstants.commas(int(swarm.get("my_slain")))]
	else:
		_last_result = "You lasted %s  ·  stage %d  ·  %s slain" % [clock_text(elapsed), stage,
			GameConstants.commas(int(swarm.get("slain")))]
	if _hud != null:
		_hud.call("show_result", _last_result, clock_text(best))
	_clear_left = CLEAR_AFTER
	if was_party and leading():
		party.call("line_now")


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
	door_open = false
	if state == State.OVER:
		state = State.WAITING
		if leading() and party != null:
			party.call("line_now")


# =============================================================================
# THE PARTY'S LINE (endlessparty.gd)
# =============================================================================

func line() -> Array:
	"""(Leader.) The run as one line of whole numbers: state, clock (ms),
	stage, countdown (ms), door held open, players it is scaled for, the
	party's kills, how many are in."""
	var in_now: int = (1 if my_in else 0) + (int(party.call("others_in")) if party != null else 0)
	return [state, roundi(elapsed * 1000.0), stage, roundi(countdown_left * 1000.0), 1 if door_open else 0,
		players, int(swarm.get("slain")), in_now]


func follow_line(numbers: Array) -> void:
	"""(Not leading.) The leader's line: this game's run follows it."""
	if numbers.size() < 8:
		return
	var said: int = int(numbers[0])
	var clock: float = float(numbers[1]) / 1000.0
	players = maxi(1, int(numbers[5]))
	party_slain = int(numbers[6])
	party_in = int(numbers[7])
	match said:
		State.WAITING:
			if state == State.OVER or state == State.COUNTDOWN or state == State.RUNNING:
				_clear_arena()
				state = State.WAITING
		State.COUNTDOWN:
			if state != State.COUNTDOWN:
				if state != State.WAITING:
					_clear_arena()
				state = State.COUNTDOWN
			countdown_left = float(numbers[3]) / 1000.0
		State.RUNNING:
			if state != State.RUNNING:
				if state == State.OVER:
					_clear_arena()
				state = State.RUNNING
				stage = 0
				swarm.set("slain", 0)
				swarm.set("my_slain", 0)
				elapsed = clock
				Audio.play("teleport")
				# JOINED PART-WAY (this game missed the start, or thought the
				# run over): the slimes born so far are the leader's to send.
				if clock > 1.0 and party != null:
					party.call("ask_everything")
			if absf(elapsed - clock) > 0.5:
				elapsed = clock
			if int(numbers[2]) != stage and int(numbers[2]) >= 1:
				_enter_stage(int(numbers[2]))
		State.OVER:
			if state == State.RUNNING:
				elapsed = clock
				_end_run()
	var held: bool = int(numbers[4]) == 1
	if held != door_open:
		_set_door(held)


func follow_everything(numbers: Array, slimes: PackedInt32Array) -> void:
	"""(A game that walked in.) The leader's line and every slime as they
	stand."""
	follow_line(numbers)
	if state == State.RUNNING or state == State.COUNTDOWN:
		swarm.call("import_alive", slimes)


# The suite's seam: the player this run is about, instead of the "player"
# group's (two runs in one tree, each its own game).
var player_override: Node2D = null


func _player() -> Node2D:
	if player_override != null:
		return player_override if is_instance_valid(player_override) else null
	return get_tree().get_first_node_in_group(&"player") as Node2D if is_inside_tree() else null


func result_line() -> String:
	return _last_result
