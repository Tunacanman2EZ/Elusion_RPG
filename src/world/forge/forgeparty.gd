# forgeparty.gd - THE FORGE TOGETHER (0.160.0, step 3 of the commit folder's
# FORGE_PLAN.txt: "2 to 4 in one run - one heat, one flood order, one clock,
# shared monsters, a fall waits by the anvil while the rest fight on; scaled
# by party size").
#
# A party has a Forge of its own: the presence server seats it there for a
# game that says "fp" in its hello ("fr" in its welcome, presence.py THE
# FORGE TOGETHER), and this passes the run between the games in it as "en"
# messages (Presence.send_run(), run_received). Nothing here is used alone:
# with nobody else on the island, active() is false and the run plays as it
# always did.
#
# WHO DECIDES WHAT. The game leading the room (the earliest in, as for any
# area's monsters - Presence.leader_for()) runs the run: the heat, the
# floods, the ice essence and the fire sprites - the sprites shared by
# monstersync.gd like any area's (forgerun.gd MARK), and booked by the
# server, so every player's blows are counted and every player's own chest
# is filled. Its LINE ("r", forgerun.gd line()): the run's key, the state,
# the clock, the heat, the floods, the slice flooding and its front, the
# countdown, how many the run is scaled for, the light round the anvil, the
# volcano's clock, where the essence lies and the party's kills - when it
# changes and every LINE_EVERY. The others follow it (forgerun.gd
# follow_line()): the same island, sinking the same way, their own fire,
# wading, forging and rocks, aimed at their own player.
# Every game tells its own line ("me", forgerun.gd my_line()): the run's key,
# down or standing, how many essences it has walked over and (0.161.0) its
# Ready - and "go" when its player lights the forge before a run, which
# starts the countdown.
extends Node

const AREA := "forge"
const TICK_SECONDS := 0.2
const LINE_EVERY := 1.0
const ME_EVERY := 1.0
const GO_EVERY := 1.0

var run: Node = null
# The presence link: the Presence autoload in the game, a stand-in in the
# suite - anything with forge_rooms(), my_id(), leader_for(), sharers(),
# remotes(), send_run() and the run_received and lead_changed signals.
var link: Node = null

var _tick_left: float = 0.0
var _line_left: float = 0.0
var _me_left: float = 0.0
var _go_left: float = 0.0
var _last_line: Array = []
var _last_me: Array = []
# Each other player's last line: id -> [key, down, essences, Ready - 1 for a
# game from before 0.161.0, which says nothing of it].
var _members: Dictionary = {}


func _ready() -> void:
	if link == null:
		link = Presence
	if link.has_signal("run_received"):
		link.run_received.connect(_on_run)
	if link.has_signal("lead_changed"):
		link.lead_changed.connect(_on_lead)


func shares() -> bool:
	"""Whether the server seats a party's Forge together (its welcome's
	"fr")."""
	return link != null and link.has_method("forge_rooms") and bool(link.call("forge_rooms"))


func active() -> bool:
	"""A party run to share: a server that seats it, a game leading the room,
	and somebody else in it."""
	return shares() and int(link.call("sharers")) > 0 and int(link.call("leader_for", AREA)) >= 0


func leads() -> bool:
	"""Whether this game runs the run: alone, or the room's leader."""
	return not active() or int(link.call("leader_for", AREA)) == int(link.call("my_id"))


func members() -> int:
	"""How many players are on the island, this one included."""
	return 1 + int(link.call("sharers")) if active() else 1


func others() -> Array:
	"""The other players' pictures on the island (remoteplayer.gd)."""
	var here: Dictionary = link.call("remotes") if link != null and link.has_method("remotes") else {}
	var out: Array = []
	for id in here.keys():
		if is_instance_valid(here[id]):
			out.append(here[id])
	return out


func _here() -> Array:
	var here: Dictionary = link.call("remotes") if link.has_method("remotes") else {}
	return here.keys()


func all_down(key: int) -> bool:
	"""(Leader.) Every other player here says they are down in this run - one
	not heard from yet is watching, and holds nothing up."""
	for id in _here():
		var line: Array = _members.get(id, [])
		if line.size() >= 2 and int(line[0]) == key and int(line[1]) == 0:
			return false
	return true


func ready_of(id: int) -> int:
	"""READY FIRST (0.161.0): 1 when that player has said Ready (or its game
	is from before and says nothing of it), 0 when not, -1 when not heard."""
	var line: Array = _members.get(id, [])
	return int(line[3]) if line.size() >= 4 else -1


func standing(key: int) -> int:
	"""(Leader.) How many of the others are still standing in this run."""
	var n: int = 0
	for id in _here():
		var line: Array = _members.get(id, [])
		if line.size() >= 2 and int(line[0]) == key and int(line[1]) == 0:
			n += 1
	return n


# WHO SPENT IT (0.152.0): this minigame's own frame, timed, so a slow
# frame on the readout names it (PerfOverlay.spend()).
func _process(delta: float) -> void:
	var spent_from: int = Time.get_ticks_usec()
	_timed_process(delta)
	PerfOverlay.spend(&"forge party", Time.get_ticks_usec() - spent_from)


func _timed_process(delta: float) -> void:
	if run == null:
		return
	if not active():
		_members.clear()
		return
	_go_left -= delta
	_tick_left -= delta
	_line_left -= delta
	_me_left -= delta
	if _tick_left <= 0.0:
		_tick_left = TICK_SECONDS
		flush()


func flush() -> void:
	"""What this game has to say this tick: the leader's line, and its own."""
	if not active():
		return
	var message: Dictionary = {}
	if leads():
		var line: Array = run.call("line")
		if line != _last_line or _line_left <= 0.0:
			message["r"] = line
			_last_line = line
			_line_left = LINE_EVERY
	var me: Array = run.call("my_line")
	if me != _last_me or _me_left <= 0.0:
		message["me"] = me
		_last_me = me
		_me_left = ME_EVERY
	if not message.is_empty():
		link.call("send_run", message)


func line_now() -> void:
	"""The leader's line goes out with the next tick, whatever its timer."""
	_line_left = 0.0
	_tick_left = 0.0


func me_now() -> void:
	"""This game's own line goes out with the next tick."""
	_me_left = 0.0
	_tick_left = 0.0


func ask_go() -> void:
	"""(Not leading.) This game's player lit the forge before the run: the
	leader starts the countdown."""
	if active() and not leads() and _go_left <= 0.0:
		_go_left = GO_EVERY
		link.call("send_run", {"go": 1})


func _on_run(from_id: int, data: Dictionary) -> void:
	if run == null:
		return
	var leading: bool = leads()
	if data.get("r") is Array and not leading:
		run.call("follow_line", data["r"])
	if data.get("me") is Array and (data["me"] as Array).size() >= 3:
		var me: Array = []
		for n in (data["me"] as Array).slice(0, 4):
			me.append(int(n))
		if me.size() < 4:
			me.append(1)
		_members[from_id] = me
		if leading and active():
			run.call("party_me", from_id, me)
	if leading and active() and int(data.get("go", 0)) == 1:
		run.call("party_go")


func _on_lead(area: String, _leader_id: int, _sharers: int) -> void:
	if area != AREA:
		return
	_line_left = 0.0
	if run != null and active() and leads():
		run.call("take_over")
