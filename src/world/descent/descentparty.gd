# descentparty.gd - THE DESCENT TOGETHER (0.126.0, step 2 of the commit
# folder's DESCENT_PLAN_3.txt).
#
# The owner: "lets set up party", "everyone has to die at some point even
# with a party of 4", "any class can join". A party has a Descent of its own
# (the presence server seats it there - "dr" in its welcome, presence.py THE
# DESCENT TOGETHER), and this passes the run between the games in it as "en"
# messages (Presence.send_run(), run_received). Nothing here is used alone:
# with nobody else in the room, active() is false and the run plays as it
# always did.
#
# WHO DECIDES WHAT. The game leading the room (the earliest in, as for any
# area's monsters - Presence.leader_for()) runs the run, and its monsters are
# the room's (descentrun.gd PARTY_MARK: shared by monstersync.gd like any
# area's, worth nothing). Its LINE ("r", descentrun.gd line()): the run's key,
# the state, the floor, the room and its kind, the two doors and whether they
# are open, the room's number of travels, the countdown, how many the run is
# scaled for and the gold - when it changes and every LINE_EVERY. The others
# follow it (descentrun.gd follow_line()): the same rooms, the same doors,
# their own picks, ward and gold, and their own hazards, aimed at their own
# player (descentlands.gd).
# Every game tells its own line ("me", descentrun.gd my_line()): the run's
# key, down or standing, picked or still choosing, and the door it walked
# into (0 none, 1 left, 2 right) - and "go" when it walks through a door
# before the run, which starts the countdown.
extends Node

const AREA := "descent"
const TICK_SECONDS := 0.2
const LINE_EVERY := 1.0
const ME_EVERY := 1.0
const GO_EVERY := 1.0

var run: Node = null
# The presence link: the Presence autoload in the game, a stand-in in the
# suite - anything with descent_rooms(), my_id(), leader_for(), sharers(),
# remotes(), send_run() and the run_received and lead_changed signals.
var link: Node = null

var _tick_left: float = 0.0
var _line_left: float = 0.0
var _me_left: float = 0.0
var _go_left: float = 0.0
var _last_line: Array = []
var _last_me: Array = []
# (Leader.) Each other player's last line: id -> [key, out, picked, door].
var _members: Dictionary = {}


func _ready() -> void:
	if link == null:
		link = Presence
	if link.has_signal("run_received"):
		link.run_received.connect(_on_run)
	if link.has_signal("lead_changed"):
		link.lead_changed.connect(_on_lead)


func shares() -> bool:
	"""Whether the server seats the Descent a room per party - so the run's
	monsters may be shared (descentrun.gd _bring())."""
	return link != null and link.has_method("descent_rooms") and bool(link.call("descent_rooms"))


func active() -> bool:
	"""A party run to share: a server that seats it, a game leading the room,
	and somebody else in it."""
	return shares() and int(link.call("sharers")) > 0 and int(link.call("leader_for", AREA)) >= 0


func leads() -> bool:
	"""Whether this game runs the run: alone, or the room's leader."""
	return not active() or int(link.call("leader_for", AREA)) == int(link.call("my_id"))


func members() -> int:
	"""How many players are in the room, this one included."""
	return 1 + int(link.call("sharers")) if active() else 1


func _here() -> Array:
	var here: Dictionary = link.call("remotes") if link.has_method("remotes") else {}
	return here.keys()


func all_out(key: int) -> bool:
	"""(Leader.) Every other player here says they are down in this run - one
	not heard from yet is watching, and holds nothing up."""
	for id in _here():
		var line: Array = _members.get(id, [])
		if line.size() >= 2 and int(line[0]) == key and int(line[1]) == 0:
			return false
	return true


func all_picked(key: int) -> bool:
	"""(Leader.) Every other player here has taken their pick this room."""
	for id in _here():
		var line: Array = _members.get(id, [])
		if line.size() >= 3 and int(line[0]) == key and int(line[2]) == 0:
			return false
	return true


# WHO SPENT IT (0.152.0): this minigame's own frame, timed, so a slow
# frame on the readout names it (PerfOverlay.spend()).
func _process(delta: float) -> void:
	var spent_from: int = Time.get_ticks_usec()
	_timed_process(delta)
	PerfOverlay.spend(&"descent party", Time.get_ticks_usec() - spent_from)


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
	"""(Not leading.) This game's player walked through a door before the run:
	the leader starts the countdown."""
	if active() and not leads() and _go_left <= 0.0:
		_go_left = GO_EVERY
		link.call("send_run", {"go": 1})


func _on_run(from_id: int, data: Dictionary) -> void:
	if run == null:
		return
	var leading: bool = leads()
	if data.get("r") is Array and not leading:
		run.call("follow_line", data["r"])
	if data.get("me") is Array and (data["me"] as Array).size() >= 4:
		var me: Array = []
		for n in (data["me"] as Array).slice(0, 4):
			me.append(int(n))
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
