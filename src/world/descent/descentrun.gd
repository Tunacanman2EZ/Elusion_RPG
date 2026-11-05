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
# ROOMS fights a floor, then its keeper (FLOORS). Beating the last keeper
# wins the run.
#
# SEVEN FLOORS, AND SUPER HARD (0.123.0) - the owner: "we need more enemies in
# the descent and we need more then 3 levels we also make sure all bosses are
# hitting", then "we need more elites this needs to be super hard". A floor
# for every land, each its own monsters and its land's boss as the keeper
# (the Crypt, the Frozen Halls, the Drowned Halls, the Windworn Halls, the
# Shining Vault, the Deep Roots, the Dark Below), four rooms and the keeper
# a floor - 35 fights; beating the seventh keeper wins. Each floor below the
# Crypt is washed in its land's colour (_wash_floor()). Packs start at five
# and reach PACK_MOST, in waves of up to WAVE_MOST; every fight room brings
# elites (elites_for(): one, one more every ELITES_FLOORS floors, an elite
# room ELITE_ROOM_MORE more); and a keeper hits at its floor's
# "keeper_taken" (the seven bosses measured on one warrior differ eight
# times over - wind 15 a second, dark 116 - so each is lifted to its place
# on a ladder) and calls its floor's monsters and elites every
# KEEPER_CALL_SECONDS (_step_keeper()), who fall when it does.
#
# STEP 1 OF THE THIRD PLAN (0.124.0, the commit folder's DESCENT_PLAN_3.txt) -
# the owner: "double bosses impossible rooms we need effects added also lets
# make those elements shine", "everyone has to die at some point", and
# "fields should use the bosses elemental hazards in this minigame".
#   - THE LANDS SHINE (descentlands.gd, _lands): every fight room from the
#     second of a floor throws its keeper's own volleys and stalagmites at
#     you (the Light Keeper's PRISM spokes are the lasers), each floor has
#     its weather, its line under the banner ("felt"), a stronger wash, and
#     the orbs' effects grow stronger each floor.
#   - DOUBLE KEEPERS (keepers_for()): from floor 4 the keeper comes with the
#     last floor's keeper beside it, an ECHO (KEEPER_ECHO_HEALTH of its
#     health, its hits held to its own floor's ladder by ECHO_HIT); on floor
#     7 and in the Deep, another drawn from the rest.
#   - IMPOSSIBLE ROOMS: from floor IMPOSSIBLE_FROM + 1 a door may promise one
#     (IMPOSSIBLE_CHANCE, once a floor): IMPOSSIBLE_PACK packs at once, an
#     elite in every wave, a keeper of another land in the middle, the
#     hazards twice as often - for an epic or better pick and
#     IMPOSSIBLE_GOLD rooms' gold.
#   - (0.126.0) THE DESCENT TOGETHER (descentparty.gd, `party`): in a party's
#     own Descent the leader's game runs the run and its monsters are the
#     room's (PARTY_MARK), the others follow its line - the same rooms and
#     doors, their own picks, ward, gold and hazards. A door before the run
#     starts a COUNTDOWN; the first through a door between rooms chooses it
#     for everybody; the doors open once everybody has picked (or after
#     PICK_WAIT). A fall leaves you DOWN (Boons.out: nothing hits you, a
#     ghost at the front) until the room is clear, when you stand with half
#     a ward; the run ends when the whole party is down. Scaled for the
#     party (PARTY_CROWD, PARTY_HEALTH, PARTY_BOSS, an elite more a player).
#   - THE DEEP: past the Dark Keeper the run goes on - the seven floors
#     again (floor_info() names them "the Deep"), every number up each time
#     round (deep_round()), until you fall. The best run is the deepest.
#
# STEP 1 OF THE SECOND PLAN (0.115.0) - the owner: "feels pretty boring and
# chars die fast". A WARD (descentboons.gd) over your health, full at the
# start and again at every room cleared; the crypt's monsters hit for half on
# the first floor, 0.7 on the second, 0.9 on the third (FLOORS' "taken"; a
# keeper at full since 0.123.0, taken_for()); a
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
# THE WARRIOR'S STORY (0.123.0), the owner's: "the warrior was battle tested
# his whole life monsters were always a threat; dungeons were progressive
# trials for acquiring power some hero's acquired powers and died shortly
# after. Dungeons are massive loot pillars that can raise a entire economy;
# the warrior already had 2 power's a slash that could cut through anything,
# and a devastating double axe that could change size and be controlled at
# will. having a family is not uncommon everyone has someone to protect but
# this dungeon was different it was a trap the amount of enemies and elites
# that were flooding into the dungeon was overwhelming. The warrior did not
# have unlimited stamina or magic". STORY, in the game's story screen
# (StoryScreen), the first time a character arrives in the crypt (field.gd
# story_seen(), key STORY_KEY) - only in the real area, never on a suite's
# stand-in (player_override, or a parent that is not the current scene).
#
# WHAT IT PAYS, IN STEP 1: nothing. The gold is counted for the run; the
# server pays it in step 3. The monsters carry the stress test's mark
# (stresscrowd.gd's META): no kill report, never shared or numbered, never
# respawned - this game's alone.
extends Node

const Boons := preload("res://src/world/descent/descentboons.gd")
const Field := preload("res://src/world/field.gd")
const LandsScript := preload("res://src/world/descent/descentlands.gd")
const PartyScript := preload("res://src/world/descent/descentparty.gd")
const STORY_KEY := "#warrior"
const STORY := [
	"The warrior was battle-tested his whole life. Monsters were always a threat.",
	"Dungeons were trials of power - some heroes won their powers there and died soon after. And every dungeon was a pillar of loot, rich enough to raise an entire economy.",
	"He already carried two powers: a slash that could cut through anything, and a devastating double axe that could change its size and move at his will.",
	"Having a family is not uncommon - everyone has someone to protect. But this dungeon was different. It was a trap.",
	"Enemies and elites flooded in, more than anyone could hold - and the warrior did not have unlimited stamina or magic.",
]
const StatusEffects := preload("res://src/characters/statuseffects.gd")

enum State { WAITING, FIGHT, PICK, CLEAR, TRAVEL, COUNTDOWN }

const MARK := &"stress_copy"
const ROOMS := 4
# Each floor: its land (the wash over its floor, none for the Crypt), its
# monsters and elites, its keeper; "health" multiplies its monsters' health
# (and its keeper's), "taken" every hit on you in its rooms, "keeper_taken"
# in its keeper's room (taken_for()).
const FLOORS := [
	{"name": "the Crypt", "felt": "The fire burns you", "land": Element.Type.NONE, "monsters": ["skeleton", "skeletonsoldier"],
		"elites": ["skeletonelite"], "keeper": "fireboss", "keeper_name": "The Fire Keeper",
		"health": 1.0, "taken": 0.5, "keeper_taken": 1.1},
	{"name": "the Frozen Halls", "felt": "The cold freezes you", "land": Element.Type.ICE, "monsters": ["icesprite", "iceslime", "icebushmage"],
		"elites": ["icefiresprite", "icebushsniper"], "keeper": "iceboss", "keeper_name": "The Ice Keeper",
		"health": 1.6, "taken": 0.65, "keeper_taken": 2.9},
	{"name": "the Drowned Halls", "felt": "Soaked, your defence is halved", "land": Element.Type.WATER, "monsters": ["watersprite", "waterslime", "waterbushmage"],
		"elites": ["waterfiresprite", "waterbushsniper"], "keeper": "waterboss", "keeper_name": "The Water Keeper",
		"health": 2.6, "taken": 0.8, "keeper_taken": 4.1},
	{"name": "the Windworn Halls", "felt": "The wind throws you about", "land": Element.Type.WIND, "monsters": ["windsprite", "windslime", "windbushmage"],
		"elites": ["windfiresprite", "windbushsniper"], "keeper": "windboss", "keeper_name": "The Wind Keeper",
		"health": 4.0, "taken": 0.9, "keeper_taken": 6.5},
	{"name": "the Shining Vault", "felt": "The light blinds you", "land": Element.Type.LIGHT, "monsters": ["lightsprite", "lightslime", "lightbushmage"],
		"elites": ["lightfiresprite", "lightbushsniper"], "keeper": "lightboss", "keeper_name": "The Light Keeper",
		"health": 5.5, "taken": 1.0, "keeper_taken": 2.5},
	{"name": "the Deep Roots", "felt": "The earth roots you", "land": Element.Type.EARTH, "monsters": ["earthsprite", "earthslime", "bushmage"],
		"elites": ["earthfiresprite", "earthbushsniper"], "keeper": "earthboss", "keeper_name": "The Earth Keeper",
		"health": 3.4, "taken": 1.1, "keeper_taken": 2.1},
	{"name": "the Dark Below", "felt": "The dark doubles every hit", "land": Element.Type.DARK, "monsters": ["darksprite", "darkslime", "darkbushmage"],
		"elites": ["darkfiresprite", "darkbushsniper"], "keeper": "bossenemy", "keeper_name": "The Dark Keeper",
		"health": 2.4, "taken": 1.2, "keeper_taken": 0.7},
]
# What a door can promise, and how often.
const KINDS := ["upgrade", "gold", "elite", "shrine", "treasure", "challenge", "rest", "impossible"]
# An Impossible room is never rolled with the rest: _open_doors() offers one.
const KIND_WEIGHTS := [30, 22, 18, 8, 8, 8, 6, 0]
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
# over PACK_MOST (0.115.0: it began at 4 and reached 13, then 3 and 10; since
# 0.123.0, five on the first room and 20 at the bottom).
const PACK_FIRST := 4
const PACK_FLOOR := 2
const PACK_MOST := 20
# IN WAVES (0.115.0): the next comes when this many or fewer are left of the
# last, or after WAVE_SECONDS; each monster's spot glows MARK_SECONDS first.
# A wave holds WAVE_MOST at most, and a pack comes in WAVES_MOST at most.
const WAVE_NEXT_AT := 2
const WAVE_MOST := 5
const WAVES_MOST := 4
# ELITES IN EVERY FIGHT (0.123.0, elites_for()): ELITES_FIRST, one more every
# ELITES_FLOORS floors down; an elite room ELITE_ROOM_MORE more; a Treasure none.
const ELITES_FIRST := 1
const ELITES_FLOORS := 2
const ELITE_ROOM_MORE := 2
# THE KEEPER CALLS ITS FLOOR (0.123.0, _step_keeper()): KEEPER_CALL_FIRST
# seconds in, then every KEEPER_CALL_SECONDS, KEEPER_CALL_SIZE + the floor's
# number of its monsters and keeper_call_elites() elites - none while
# KEEPER_ADDS_MOST stand. When it falls, they do.
const KEEPER_CALL_FIRST := 8.0
const KEEPER_CALL_SECONDS := 18.0
const KEEPER_CALL_SIZE := 2
const KEEPER_ADDS_MOST := 12
# A floor below the Crypt is washed in its land's colour, this strong, added.
const FLOOR_WASH := 0.16
# DOUBLE KEEPERS (0.124.0, keepers_for()): from this floor (an index) the
# keeper brings an echo; an echo's health and how hard it hits, against its
# own floor's keeper_taken.
const DOUBLE_FROM := 3
const KEEPER_ECHO_HEALTH := 0.6
const ECHO_HIT := 0.6
# IMPOSSIBLE ROOMS (0.124.0): from this floor (an index), this often a pair of
# doors, once a floor; how many packs, the gold, the keeper's health.
const IMPOSSIBLE_FROM := 2
const IMPOSSIBLE_CHANCE := 0.2
const IMPOSSIBLE_PACK := 3
const IMPOSSIBLE_GOLD := 5
const IMPOSSIBLE_KEEPER_HEALTH := 0.6
const IMPOSSIBLE_WAVES := 8
# THE DEEP (0.124.0): each time round, this much more health, harder hits,
# more elites a room and a bigger pack.
const DEEP_HEALTH_STEP := 0.6
const DEEP_TAKEN_STEP := 0.25
const DEEP_ELITES := 2
const DEEP_PACK := 4
# THE DESCENT TOGETHER (0.126.0): the run's monsters shared with the party;
# the countdown at the start; how long the doors wait for everybody's pick;
# the scaling for 1 to 4 players (the Endless's table, to tune by playing);
# a fallen player's look; the kinds as the line carries them.
const PARTY_MARK := &"party_copy"
const COUNTDOWN_SECONDS := 5.0
const PICK_WAIT := 20.0
const PARTY_CROWD := [1.0, 1.0, 1.5, 2.0, 2.5]
const PARTY_HEALTH := [1.0, 1.0, 1.2, 1.4, 1.6]
const PARTY_BOSS := [1.0, 1.0, 1.75, 2.5, 3.25]
const OUT_ALPHA := 0.4
# A ROOM'S WEATHER (0.127.0, room_lands()): from this floor (an index) a
# second land may mix in, this often and this much more each floor down;
# always in the Deep.
const MIX_FROM := 2
const MIX_CHANCE := 0.25
const MIX_STEP := 0.1
const ALL_LANDS := [Element.Type.FIRE, Element.Type.ICE, Element.Type.WATER, Element.Type.WIND,
	Element.Type.LIGHT, Element.Type.EARTH, Element.Type.DARK]
const LINE_KINDS := ["", "upgrade", "gold", "elite", "shrine", "treasure", "challenge", "rest", "impossible",
	"keeper", "down", "begin"]
const WASH_Z := -9
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
var _keeper: Node2D = null
var _keepers: Array = []
var _lands: Node2D = null
var _impossible_floor: int = -1
var deepest: int = -1
var party: Node = null
var run_key: int = 0
var players: int = 1
var travel_seq: int = 0
var countdown_left: float = 0.0
var my_door: int = 0
var _door_kinds: Array = ["", ""]
var _pick_wait: float = 0.0
var _line: Array = []
var room_lands: Array = []
var _keeper_call: float = 0.0
var _wash: ColorRect = null
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
	_tell_story.call_deferred()
	party = PartyScript.new()
	party.name = "descentparty"
	party.set("run", self)
	add_child(party)


func tells_story() -> bool:
	"""The warrior's story is told in the real crypt only, once a character."""
	if player_override != null or not is_inside_tree() or get_tree().current_scene != get_parent():
		return false
	# A WARRIOR'S STORY (0.124.0: every class may come down now).
	if str(CharacterData.active_class_id()) not in ["warrior", ""]:
		return false
	return not Field.story_seen(Field.story_key() + STORY_KEY)


func _tell_story() -> void:
	if not tells_story():
		return
	Field.mark_story_seen(Field.story_key() + STORY_KEY)
	var screen := StoryScreen.new()
	get_parent().add_child(screen)
	screen.play(STORY, true)


func _exit_tree() -> void:
	Boons.clear()
	_drop_ward_ring()


func _player() -> Node2D:
	if player_override != null:
		return player_override if is_instance_valid(player_override) else null
	return get_tree().get_first_node_in_group(&"player") as Node2D if is_inside_tree() else null


func floor_info() -> Dictionary:
	"""This floor's row of FLOORS - in the Deep, the seven again, named so."""
	var info: Dictionary = FLOORS[maxi(0, floor_index) % FLOORS.size()]
	if deep_round() == 0:
		return info
	var deep: Dictionary = info.duplicate()
	deep["name"] = "the Deep %d: %s" % [deep_round(), str(info["name"])]
	return deep


func deep_round() -> int:
	"""0 on the seven floors; 1 the first time round the Deep, and on."""
	return floori(float(maxi(0, floor_index)) / float(FLOORS.size()))


func keepers_for() -> Array:
	"""[keeper id, health, hit scale] for each keeper of this floor's keeper
	room: its own, and from DOUBLE_FROM an echo - the last floor's keeper
	before floor 7, then one of the others drawn at random."""
	var info: Dictionary = floor_info()
	var made: Array = [[str(info["keeper"]), float(info["health"]) * KEEPER_HEALTH * deep_health() * party_scale(PARTY_BOSS), 1.0]]
	if floor_index < DOUBLE_FROM:
		return made
	var other: Dictionary
	if floor_index < FLOORS.size() - 1:
		other = FLOORS[floor_index - 1]
	else:
		var rest: Array = FLOORS.filter(func(f: Dictionary) -> bool: return str(f["keeper"]) != str(info["keeper"]))
		other = rest[_rng.randi_range(0, rest.size() - 1)]
	made.append([str(other["keeper"]), float(other["health"]) * KEEPER_ECHO_HEALTH * deep_health() * party_scale(PARTY_BOSS),
		float(other["keeper_taken"]) / float(info["keeper_taken"]) * ECHO_HIT])
	return made


func deep_health() -> float:
	return 1.0 + DEEP_HEALTH_STEP * float(deep_round())


func hazard_keepers() -> Array:
	"""Whose hazards this room throws (descentlands.gd): the floor's keeper -
	in the Deep, another land's with it."""
	var ids: Array = [str(floor_info()["keeper"])]
	if deep_round() > 0:
		ids.append(str(FLOORS[(floor_index + 3) % FLOORS.size()]["keeper"]))
	return ids


func taken_for(kind: String) -> float:
	"""How hard this floor's monsters hit in a room of this kind (Boons'
	`floor_taken`). A KEEPER HITS AT FULL (0.123.0) - the owner: "fire boss in
	warriors run was doing 0 damage to warrior". At the first floor's half, on
	top of every hit's half and the defence tier, the Fire Keeper's orbs and
	burns came to 1 each and its spikes to 13, and the ward soaked the first
	72 of them: a warrior's health never moved. The softer hits are for the
	crypt's packs; the keeper is the floor's test - since the seven floors,
	at its floor's "keeper_taken", which lifts the weak ones to the ladder."""
	var deeper: float = 1.0 + DEEP_TAKEN_STEP * float(deep_round())
	if kind == "keeper":
		return float(floor_info().get("keeper_taken", 1.0)) * deeper
	return float(floor_info().get("taken", 1.0)) * deeper


func running() -> bool:
	return state != State.WAITING and state != State.COUNTDOWN


func party_on() -> bool:
	"""In a Descent with somebody else (descentparty.gd active())."""
	return party != null and is_instance_valid(party) and bool(party.call("active"))


func following() -> bool:
	"""This game follows the room's leader: it runs no monsters of its own."""
	return party_on() and not bool(party.call("leads"))


func party_scale(table: Array) -> float:
	return float(table[clampi(players, 0, table.size() - 1)])


# =============================================================================
# THE RUN
# =============================================================================

func start_run() -> void:
	Boons.clear()
	Boons.active = true
	floor_index = 0
	_impossible_floor = -1
	if run_key == 0:
		run_key = randi_range(1, 1 << 30)
	players = int(party.call("members")) if party_on() else 1
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
	my_door = 0
	if not following():
		travel_seq += 1
	if party != null and is_instance_valid(party):
		party.call("line_now")


func _arrive(kind: String) -> void:
	# FOLLOWING (0.126.0): the leader's floor, room and kind, whatever this
	# game counted.
	if following() and _line.size() >= 12:
		var to_floor: int = int(_line[2])
		if to_floor != floor_index:
			Boons.new_floor()
			rerolls_free = REROLL_FREE
			rerolls_paid = 0
		floor_index = to_floor
		room = int(_line[3]) - 1
		kind = kind_of(int(_line[4]))
	elif kind == "down":
		floor_index += 1
		room = 0
		kind = "upgrade"
		Boons.new_floor()
		rerolls_free = REROLL_FREE
		rerolls_paid = 0
	room += 1
	room_kind = "keeper" if room > ROOMS else kind
	Boons.floor_taken = taken_for(room_kind)
	Boons.room_kills = 0
	challenge_left = 0.0
	challenge_won = false
	_clear_monsters()
	_dress()
	_wash_floor()
	room_lands = lands_for_room()
	_dress_land()
	if room_kind == "rest":
		_light_fire()
	var player: Node2D = _player()
	if player != null:
		player.global_position = entry_spot
		player.reset_physics_interpolation()
		if player.has_method("snap_camera"):
			player.call("snap_camera")
		# A WARRIOR'S AXE COMES WITH YOU (0.123.0, warrior.gd put_axes_away()):
		# left spinning, it stayed in the next room.
		if player.has_method("put_axes_away"):
			player.call("put_axes_away")
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
		return str(floor_info()["keeper_name"]) + (" and an echo" if floor_index >= DOUBLE_FROM else "")
	if room_kind == "impossible":
		return "Impossible"
	return "Floor %d - room %d" % [floor_index + 1, room]


func _room_line() -> String:
	match room_kind:
		"elite":
			return "An elite waits here"
		"gold":
			return "Gold when it is clear"
		"keeper":
			return "The keeper of %s" % str(floor_info()["name"])
		"impossible":
			return "Everything at once - an epic pick if you live"
		"shrine":
			return "A shrine: a stronger upgrade - and the floor hits harder after"
		"treasure":
			return "Treasure, lightly guarded"
		"challenge":
			return "Clear it in %d seconds for a rare upgrade" % roundi(challenge_seconds())
		"rest":
			return "A rest: your ward full and half again for the next room"
	# THE FLOOR'S OWN LINE as you come down to it (0.124.0).
	if room == 1:
		return "%s - an upgrade when it is clear" % str(floor_info().get("felt", ""))
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
		State.COUNTDOWN:
			countdown_left = maxf(0.0, countdown_left - delta)
			if hud != null:
				hud.call("toast", "Down together in %d" % ceili(countdown_left))
			if countdown_left <= 0.0 and not following():
				start_run()
		State.CLEAR:
			# THE DOORS WAIT FOR EVERYBODY'S PICK (0.126.0), or PICK_WAIT.
			if party_on() and not following() and not _doors_open():
				_pick_wait -= delta
				if _pick_wait <= 0.0 or bool(party.call("all_picked", run_key)):
					_set_doors(true, str(_door_kinds[0]), str(_door_kinds[1]))
		State.FIGHT:
			if _fight_in >= 0.0:
				_fight_in -= delta
				if _fight_in < 0.0:
					_spawn_pack()
			elif following():
				if _lands != null and is_instance_valid(_lands):
					_lands.call("step", delta)
			else:
				_step_waves(delta)
				if _lands != null and is_instance_valid(_lands):
					_lands.call("step", delta)
				if room_kind == "keeper":
					_step_keeper(delta)
				if room_kind == "challenge":
					challenge_left = maxf(0.0, challenge_left - delta)
				if living() == 0 and _coming.is_empty() and _waves.is_empty():
					challenge_won = room_kind == "challenge" and challenge_left > 0.0
					_room_cleared()
	# THE WHOLE PARTY DOWN (0.126.0): the run is over.
	if running() and party_on() and not following() and Boons.out and bool(party.call("all_out", run_key)):
		_end_run(false)
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
	# The hazards stop with the fight.
	if _lands != null and is_instance_valid(_lands):
		_lands.call("end")
	# THE FALLEN STAND (0.126.0) - with half a ward, after the others' full.
	var stood: bool = _stand_up()
	# THE WARD FULL AGAIN for the next room (0.115.0).
	fill_ward()
	if stood:
		Boons.ward = Boons.ward_most / 2
	match room_kind:
		"gold":
			_pay(GOLD_BASE * (floor_index + 1))
			_open_doors()
		"elite":
			_pay(roundi(GOLD_BASE * (floor_index + 1) * ELITE_GOLD))
			_offer()
		"keeper":
			_pay(GOLD_BASE * (floor_index + 1) * KEEPER_GOLD)
			# NO BOTTOM (0.124.0): past the Dark Keeper, the Deep.
			if hud != null:
				var next_line: String = "Pick one - then down into the Deep" if floor_index + 1 >= FLOORS.size() \
					and deep_round() == 0 else "Pick one - then down to floor %d" % (floor_index + 2)
				hud.call("announce", "%s falls!" % str(info["keeper_name"]), next_line)
			_offer("rare")
		"impossible":
			_pay(GOLD_BASE * (floor_index + 1) * IMPOSSIBLE_GOLD)
			if hud != null:
				hud.call("announce", "You lived!", "An epic pick")
			_offer("epic")
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
	offers = Boons.offers(_rng, 3, at_least, _note_class(), room_kind == "keeper")
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
	offers = Boons.offers(_rng, 3, _offer_at_least, _note_class(), room_kind == "keeper", offers)
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
	# FOLLOWING (0.126.0): the leader's doors, as its line says.
	if following():
		_line_doors()
		return
	_pick_wait = PICK_WAIT
	if room_kind == "keeper":
		_show_doors("down", "down")
	elif room >= ROOMS:
		_show_doors("keeper", "keeper")
	else:
		var first: String = _roll_kind("")
		var second: String = _roll_kind(first)
		# AN IMPOSSIBLE ROOM (0.124.0): from IMPOSSIBLE_FROM, sometimes, once
		# a floor - the second door.
		if floor_index >= IMPOSSIBLE_FROM and _impossible_floor != floor_index \
				and _rng.randf() < IMPOSSIBLE_CHANCE:
			second = "impossible"
			_impossible_floor = floor_index
		_show_doors(first, second)


func _show_doors(left: String, right: String) -> void:
	"""The doors this room promises - open now, or in a party once everybody
	has picked (_process(), PICK_WAIT)."""
	_door_kinds = [left, right]
	_set_doors(not party_on() or bool(party.call("all_picked", run_key)), left, right)
	if party != null and is_instance_valid(party):
		party.call("line_now")


func _doors_open() -> bool:
	for door in doors:
		if is_instance_valid(door) and bool(door.get("open")):
			return true
	return false


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
			# TOGETHER (0.126.0): the countdown, on every screen.
			if not party_on():
				start_run()
			elif following():
				party.call("ask_go")
			else:
				party_go()
		State.CLEAR:
			if following():
				my_door = 1 + doors.find(door)
				party.call("me_now")
			else:
				_go(str(door.get("reward")))


# =============================================================================
# THE MONSTERS
# =============================================================================

func pack_size() -> int:
	var size: int = mini(PACK_MOST + DEEP_PACK * deep_round(), PACK_FIRST + room + PACK_FLOOR * floor_index)
	# A PARTY'S CROWD (0.126.0).
	size = roundi(float(size) * party_scale(PARTY_CROWD))
	if room_kind == "impossible":
		return size * IMPOSSIBLE_PACK
	# A Treasure is lightly guarded: half (rounded up).
	return ceili(size / 2.0) if room_kind == "treasure" else size


func challenge_seconds() -> float:
	# An elite counts for two (0.123.0: every fight brings them now).
	return CHALLENGE_BASE + CHALLENGE_EACH * (pack_size() + 2 * elites_for(room_kind))


static func waves_for(size: int) -> int:
	"""How many waves a pack of `size` comes in: WAVE_MOST to a wave, never
	more than WAVES_MOST."""
	return clampi(ceili(float(size) / float(WAVE_MOST)), 1, WAVES_MOST)


func elites_for(kind: String) -> int:
	"""How many elites a room of this kind brings on this floor (0.123.0)."""
	if kind in ["keeper", "treasure", "rest"]:
		return 0
	var count: int = ELITES_FIRST + floori(float(mini(floor_index, FLOORS.size() - 1)) / float(ELITES_FLOORS)) \
		+ DEEP_ELITES * deep_round() + maxi(0, players - 1)
	if kind == "elite":
		count += ELITE_ROOM_MORE
	if kind == "impossible":
		# One in every wave, at least.
		count = maxi(count, waves_in(pack_size()))
	return count


func waves_in(size: int) -> int:
	"""How many waves this room's pack of `size` comes in: an Impossible
	room's in up to IMPOSSIBLE_WAVES, the rest waves_for()."""
	if room_kind == "impossible":
		return clampi(ceili(float(size) / float(WAVE_MOST)), 1, IMPOSSIBLE_WAVES)
	return waves_for(size)


func keeper_call_elites() -> int:
	"""Elites in each of a keeper's calls: one, two from the fourth floor,
	three on the seventh."""
	return 1 + floori(float(floor_index) / 3.0)


func health_scale() -> float:
	return float(floor_info()["health"]) * (1.0 + ROOM_HEALTH_STEP * (room - 1)) * deep_health() \
		* party_scale(PARTY_HEALTH)


func _spawn_pack() -> void:
	var info: Dictionary = floor_info()
	# FOLLOWING (0.126.0): the leader's monsters come through monstersync;
	# this game's own hazards, at its own player.
	if following():
		_begin_hazards()
		return
	if room_kind == "keeper":
		# DOUBLE KEEPERS (0.124.0): its own in the middle, an echo beside it.
		_keepers = []
		var made: Array = keepers_for()
		for k in made.size():
			var entry: Array = made[k]
			var off: float = 0.0 if made.size() == 1 else (-110.0 if k == 0 else 110.0)
			var boss: Node2D = _bring(str(entry[0]), _spot(Vector2(room_rect.get_center().x + off, room_rect.position.y + 80.0)),
				float(entry[1]), float(entry[2]))
			if boss != null:
				_keepers.append(boss)
		_keeper = _keepers[0] if not _keepers.is_empty() else null
		_keeper_call = KEEPER_CALL_FIRST
		return
	# IN WAVES (0.115.0): the pack split as evenly as it goes, the elite in
	# the last, and the first wave marked now.
	var kinds: Array = info["monsters"]
	var size: int = pack_size()
	var count: int = waves_in(size)
	_waves = []
	challenge_left = challenge_seconds()
	for w in count:
		_waves.append([])
	for i in size:
		(_waves[floori(float(i * count) / float(size))] as Array).append([str(kinds[_rng.randi_range(0, kinds.size() - 1)]), health_scale(), false])
	# ELITES IN EVERY FIGHT (0.123.0): the last wave's first, then the one
	# before it, round again.
	var elites: Array = info["elites"]
	for e in elites_for(room_kind):
		(_waves[count - 1 - e % count] as Array).append([str(elites[_rng.randi_range(0, elites.size() - 1)]),
			health_scale() * ELITE_HEALTH, true])
	# AN IMPOSSIBLE ROOM'S KEEPER (0.124.0): another land's, in the middle, at
	# IMPOSSIBLE_KEEPER_HEALTH, its hits held to its own floor's ladder.
	if room_kind == "impossible":
		var rest: Array = FLOORS.filter(func(f: Dictionary) -> bool: return str(f["keeper"]) != str(info["keeper"]))
		var other: Dictionary = rest[_rng.randi_range(0, rest.size() - 1)]
		_bring(str(other["keeper"]), _spot(room_rect.get_center()),
			float(other["health"]) * IMPOSSIBLE_KEEPER_HEALTH * deep_health(),
			float(other["keeper_taken"]) / float(info["taken"]) * ECHO_HIT)
	_next_wave()
	_begin_hazards()


func _begin_hazards() -> void:
	"""THE KEEPER'S HAZARDS (0.124.0): from the second room of a floor."""
	if room >= 2 and room_kind != "rest" and room_kind != "keeper":
		_lands_node().call("begin", hazard_keepers(), floor_index, room_kind == "impossible")
		# THE FLOOR ITSELF (0.127.0): the room's lands' own hazards.
		_lands_node().call("begin_env", room_lands, floor_index, room_kind == "impossible")


func _step_keeper(delta: float) -> void:
	"""THE KEEPER CALLS ITS FLOOR (0.123.0): its monsters and elites, marked
	at the room's edges like a wave, every KEEPER_CALL_SECONDS while it
	stands and fewer than KEEPER_ADDS_MOST do. When it falls, they fall
	with it and the room is clear."""
	if not keepers_standing():
		if not _coming.is_empty():
			_coming = []
			_paint_marks()
		for m in monsters:
			if is_instance_valid(m) and not _keepers.has(m) and not (m as Node).is_queued_for_deletion():
				(m as Node).queue_free()
		return
	_keeper_call -= delta
	if _keeper_call > 0.0:
		return
	_keeper_call = KEEPER_CALL_SECONDS
	if living() - _keepers.size() + _coming.size() >= KEEPER_ADDS_MOST:
		return
	var info: Dictionary = floor_info()
	var kinds: Array = info["monsters"]
	var elites: Array = info["elites"]
	for i in KEEPER_CALL_SIZE + floor_index:
		_coming.append([str(kinds[_rng.randi_range(0, kinds.size() - 1)]), _edge_spot(), health_scale(), false, MARK_SECONDS])
	for i in keeper_call_elites():
		_coming.append([str(elites[_rng.randi_range(0, elites.size() - 1)]), _edge_spot(),
			health_scale() * ELITE_HEALTH, true, MARK_SECONDS])
	_paint_marks()
	if hud != null:
		hud.call("toast", "%s calls for help!" % str(info["keeper_name"]))


func keepers_standing() -> bool:
	"""Any of this room's keepers still up (DOUBLE KEEPERS: the room is theirs
	until the last falls)."""
	for boss in _keepers:
		if is_instance_valid(boss) and int(boss.get("hp")) > 0 and not bool(boss.get("_death_resolved")):
			return true
	return false


func _lands_node() -> Node2D:
	"""The lands' hazards and weather (descentlands.gd), over the floor."""
	if _lands == null or not is_instance_valid(_lands):
		_lands = LandsScript.new()
		_lands.name = "descentlands"
		_lands.z_index = -1
		_lands.set("run", self)
		if get_parent() != null:
			get_parent().add_child(_lands)
	return _lands


func floor_land() -> int:
	"""The floor's own land - the Crypt's is its keeper's fire."""
	var land: int = int(floor_info().get("land", Element.Type.NONE))
	return land if land != Element.Type.NONE else Element.Type.FIRE


func lands_for_room() -> Array:
	"""A ROOM'S WEATHER (0.127.0): the floor's land, and from MIX_FROM
	sometimes a second (always in the Deep) - its weather and its hazards
	both. A game following takes the leader's (its line's last number)."""
	var lands: Array = [floor_land()]
	var mixed: int = -1
	if following() and _line.size() >= 13:
		mixed = int(_line[12])
	elif deep_round() > 0 or (floor_index >= MIX_FROM
			and _rng.randf() < MIX_CHANCE + MIX_STEP * float(floor_index - MIX_FROM)):
		var others: Array = ALL_LANDS.filter(func(l: int) -> bool: return l != lands[0])
		mixed = int(others[_rng.randi_range(0, others.size() - 1)])
	if mixed >= 0 and mixed != int(lands[0]):
		lands.append(mixed)
	return lands


func _dress_land() -> void:
	"""The floor's weather (the Crypt's is its keeper's embers) and how
	strongly the orbs carry their element here."""
	if room_lands.is_empty():
		room_lands = lands_for_room()
	_lands_node().call("set_weathers", room_lands, room_rect)
	var zone: BulletZone = BulletZone.find(self)
	if zone != null:
		zone.element_effects = true
		zone.effect_strength = LandsScript.effect_for(floor_index)


func _wash_floor() -> void:
	"""Each floor below the Crypt washed in its land's colour (0.123.0): a
	ColorRect over the floor, added, under everything standing."""
	var land: int = int(floor_info().get("land", Element.Type.NONE))
	if _wash == null or not is_instance_valid(_wash):
		if get_parent() == null:
			return
		_wash = ColorRect.new()
		_wash.name = "floorwash"
		_wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_wash.position = room_rect.position
		_wash.size = room_rect.size
		_wash.z_index = WASH_Z
		var adding := CanvasItemMaterial.new()
		adding.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_wash.material = adding
		get_parent().add_child(_wash)
	var colour: Color = Element.colour_for(land)
	_wash.color = Color(colour.r, colour.g, colour.b, FLOOR_WASH) if land != Element.Type.NONE else Color(0, 0, 0, 0)


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


func _bring(enemy_id: String, at: Vector2, health: float, hits: float = 1.0) -> Node2D:
	var path: String = "res://scene/enemy/%s.tscn" % enemy_id
	var packed: PackedScene = load(path) as PackedScene if ResourceLoader.exists(path) else null
	var container: Node = get_parent().get_node_or_null("ysortworld/enemies") if get_parent() != null else null
	if packed == null or container == null:
		return null
	var monster := packed.instantiate() as Node2D
	monster.set_meta(MARK, true)
	# SHARED WITH THE PARTY (0.126.0) wherever the server seats the Descent a
	# room per party - so a friend walking in sees the room as it stands.
	if party != null and is_instance_valid(party) and bool(party.call("shares")):
		monster.set_meta(PARTY_MARK, true)
	# ITS OWN HITS, SCALED (0.124.0: an echo keeper's, an Impossible room's):
	# its own copy of its numbers, before _ready() reads them.
	if not is_equal_approx(hits, 1.0):
		_scale_hits(monster, hits)
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


func _scale_hits(monster: Node, hits: float) -> void:
	var data: Variant = monster.get("enemy_data")
	if data is EnemyData:
		var mine: EnemyData = (data as EnemyData).duplicate()
		if mine.projectile_damage > 0:
			mine.projectile_damage = maxi(1, roundi(mine.projectile_damage * hits))
		monster.set("enemy_data", mine)
	for stat in ["attack_power", "melee_power"]:
		if stat in monster:
			monster.set(stat, maxi(1, roundi(float(monster.get(stat)) * hits)))


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
	_keepers = []
	if _lands != null and is_instance_valid(_lands):
		_lands.call("end")
	# And what they fired (0.119.2): a room's end, a fall or the bottom.
	BulletZone.clear_enemy_shots(self)
	_waves = []
	_coming = []
	_paint_marks()


# =============================================================================
# THE DOUBLE AXE AND AXE FURY (0.115.0)
# =============================================================================

func _note_class() -> bool:
	"""EVERY CLASS ITS OWN (0.124.0): who is playing and which mythic weapon
	they wear, for the upgrades on offer (descentboons.gd fits()); true when
	they wear one, so its mythics may come."""
	var player: Node2D = _player()
	# The class is the player's own script (warrior.gd, mage.gd, ...).
	var cls: String = ""
	if player != null and player.get_script() != null:
		cls = (player.get_script() as Script).resource_path.get_file().get_basename()
	Boons.class_now = cls if cls in ["warrior", "mage", "tank", "healer"] else "warrior"
	var attack: int = int(player.call("equipped_weapon_attack")) if player != null and player.has_method("equipped_weapon_attack") \
		else ItemData.WeaponAttack.NONE
	Boons.weapon_now = Boons.weapon_for(attack)
	return Boons.weapon_now != ""


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
	# DOWN, NOT OUT (0.126.0): in a party the run goes on while anybody stands.
	if running() and party_on():
		Boons.out = true
		body.modulate.a = OUT_ALPHA
		if hud != null:
			hud.call("announce", "You are down", "You get up when the room is clear")
		party.call("me_now")
		return true
	if running():
		_end_run(false)
	return true


func _stand_up() -> bool:
	"""A fallen player stands when the room is clear (0.126.0)."""
	if not Boons.out:
		return false
	Boons.out = false
	var player: Node2D = _player()
	if player != null:
		player.modulate.a = 1.0
	if hud != null:
		hud.call("toast", "Back on your feet")
	return true


# =============================================================================
# THE DESCENT TOGETHER (0.126.0, descentparty.gd)
# =============================================================================

static func code_of(kind: String) -> int:
	return maxi(0, LINE_KINDS.find(kind))


static func kind_of(code: int) -> String:
	return str(LINE_KINDS[code]) if code >= 0 and code < LINE_KINDS.size() else ""


func line() -> Array:
	"""(Leader.) The run as the party follows it: [key, state, floor, room,
	kind, left door, right door, doors open, travels, countdown tenths,
	players, gold, the room's second land or -1 (0.127.0)] - whole numbers."""
	var left: String = str(doors[0].get("reward")) if doors.size() > 0 and is_instance_valid(doors[0]) else ""
	var right: String = str(doors[1].get("reward")) if doors.size() > 1 and is_instance_valid(doors[1]) else ""
	# ON THE WAY, WHERE TO: a game following arrives where this one will,
	# however the fades fall.
	var at: Array = [floor_index, room, room_kind]
	if state == State.TRAVEL and not _travelled:
		if _travel_to == "down":
			at = [floor_index + 1, 1, "upgrade"]
		else:
			at = [floor_index, room + 1, "keeper" if room + 1 > ROOMS else _travel_to]
	return [run_key, state, int(at[0]), int(at[1]), code_of(str(at[2])), code_of(left), code_of(right),
		1 if _doors_open() else 0, travel_seq, roundi(countdown_left * 10.0), players, gold,
		int(room_lands[1]) if room_lands.size() > 1 else -1]


func my_line() -> Array:
	"""This game's own: [key, down, picked, the door it walked into]."""
	return [run_key, 1 if Boons.out else 0, 0 if state == State.PICK else 1, my_door]


func party_go() -> void:
	"""(Leader.) Somebody walked through a door before the run: the countdown."""
	if state != State.WAITING:
		return
	run_key = randi_range(1, 1 << 30)
	state = State.COUNTDOWN
	countdown_left = COUNTDOWN_SECONDS
	if hud != null:
		hud.call("announce", "Together!", "The party goes down in %d" % int(COUNTDOWN_SECONDS))
	party.call("line_now")


func party_me(_from_id: int, me: Array) -> void:
	"""(Leader.) Another player's line: the door they walked into."""
	if me.size() < 4 or int(me[0]) != run_key or state != State.CLEAR or not _doors_open():
		return
	var which: int = int(me[3])
	if which >= 1 and which <= doors.size() and is_instance_valid(doors[which - 1]):
		_go(str(doors[which - 1].get("reward")))


func follow_line(wire: Array) -> void:
	"""(Following.) The leader's line: start, travel, clear and end with it."""
	if wire.size() < 12:
		return
	var key: int = int(wire[0])
	var their_state: int = int(wire[1])
	_line = wire
	players = int(wire[10])
	if their_state == State.WAITING:
		if running():
			_end_run(false)
		state = State.WAITING
		run_key = 0
		_set_doors(true, "begin", "begin")
		return
	if their_state == State.COUNTDOWN:
		if state == State.WAITING:
			state = State.COUNTDOWN
			if hud != null:
				hud.call("announce", "Together!", "The party goes down")
		run_key = key
		countdown_left = float(wire[9]) / 10.0
		return
	# A RUN ON: joined now if this game has not been in it - down, watching,
	# if it is already past its first room.
	if key != run_key or not running():
		var fresh: bool = int(wire[2]) == 0 and int(wire[3]) <= 1
		Boons.clear()
		Boons.active = true
		run_key = key
		gold = 0
		slain = 0
		picks = 0
		rerolls_free = REROLL_FREE
		rerolls_paid = 0
		travel_seq = -1
		fill_ward()
		if not fresh:
			Boons.out = true
			var me: Node2D = _player()
			if me != null:
				me.modulate.a = OUT_ALPHA
	if int(wire[8]) != travel_seq:
		travel_seq = int(wire[8])
		_go(kind_of(int(wire[4])))
		return
	# THE LEADER'S ROOM IS CLEAR: this game's own pick, pay and ward (a
	# Challenge won is one the leader offers a pick for).
	if state == State.FIGHT and _fight_in < 0.0 and (their_state == State.PICK or their_state == State.CLEAR):
		challenge_won = room_kind == "challenge" and their_state == State.PICK
		_room_cleared()
	if state == State.CLEAR:
		_line_doors()


func _line_doors() -> void:
	if _line.size() < 12:
		return
	_set_doors(int(_line[7]) == 1, kind_of(int(_line[5])), kind_of(int(_line[6])))


func take_over() -> void:
	"""(Now leading.) The old leader left: its monsters, mirrored here, are
	this game's now (monstersync hands them over) - the run carries on from
	this game's own frame."""
	if not running():
		return
	var container: Node = get_parent().get_node_or_null("ysortworld/enemies") if get_parent() != null else null
	if container != null:
		for m in container.get_children():
			if m is Node2D and m.has_meta(PARTY_MARK) and not monsters.has(m):
				monsters.append(m)
				if room_kind == "keeper" and (m as Node).is_in_group(&"bosses"):
					_keepers.append(m)
	_waves = []
	_coming = []
	if state == State.CLEAR and not _doors_open():
		_door_kinds = [kind_of(int(_line[5])) if _line.size() >= 12 else "upgrade",
			kind_of(int(_line[6])) if _line.size() >= 12 else "gold"]
		_pick_wait = 0.0


func _end_run(won: bool) -> void:
	var words: String = ("You reached the bottom!" if won else "You fell on floor %d, room %d" % [floor_index + 1, room]) \
		+ "  -  %d slain  -  %d upgrades  -  %d gold" % [slain, picks, gold]
	last_result = words
	# THE DEEPEST IS THE BEST (0.124.0: there is no bottom now).
	var depth: int = floor_index * 10 + room
	if won or best == "" or depth > deepest:
		best = words
		deepest = maxi(deepest, depth)
	_clear_monsters()
	Boons.clear()
	_drop_ward_ring()
	run_key = 0
	var standing: Node2D = _player()
	if standing != null:
		standing.modulate.a = 1.0
	var zone: BulletZone = BulletZone.find(self)
	if zone != null:
		zone.effect_strength = Field.FIELD_EFFECTS
	offers = []
	state = State.WAITING
	room = 0
	room_kind = ""
	_set_doors(true, "begin", "begin")
	if hud != null:
		hud.call("hide_pick")
		hud.call("show_result", words, won)
