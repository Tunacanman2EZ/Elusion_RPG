# clothparty.gd - CUT THE CLOTH TOGETHER (0.161.0). The owner: "i was thinking
# of making cut the cloth 4 player and if players lines crash into each other
# they also die", and of who loses a life: "only the player that crashed into
# it".
#
# Nothing here is used alone: with nobody else in the room, active() is false
# and the cloth is cut as it always was.
#
# WHERE. A game cutting the cloth with a server that says "cc" in its welcome
# tells the presence server it stands in "cloth" (Presence.state_override, set
# by clothscreen.gd), and the server seats it in its party's room, as the
# Mage's Stand's. Its steps are where its shot rides; the party's shots are
# read from their steps (Presence.world_override, clothrun.gd `others`, never
# drawn as bodies).
#
# SEATS. Everyone in the run, by account id, lowest first: the first starts
# at the bottom of the cloth, the second the top, then the left and the right
# (clothrun.gd SEAT_STARTS). Kept from the start of the run.
#
# WHO DECIDES WHAT. The game leading the room (the earliest in) runs the
# slimes, the saws, the lands' flares and gusts, the pickups and every piece
# cut away; each game rides its own shot and cuts its own line. What crosses
# is "en" (Presence.send_run(), run_received) - whole numbers only:
#   - THE LINE ("r", the leader's): key, the run's state, the round, started
#     (waiting, begun or counting down), the countdown (tenths), how much is
#     cut (thousandths), the Plague Mother's piece (thousandths), Slow left
#     (tenths), players.
#   - WHAT THE LEADER DECIDES ("sp"): each decision an event - key, number,
#     type, then its own numbers, done once by every game: a round begun with
#     its seed (EV_ROUND - every game makes the same cloth, slimes and saws
#     from it), a piece cut away as row spans (EV_CUT), cloth gnawed back
#     (EV_OPEN), a round cleared (EV_CLEAR), a pickup out and gone (EV_PICKUP,
#     EV_GONE - and who took it), a flare and a gust (EV_FLARE, EV_GUST), the
#     run over (EV_OVER). And, numbered 0, where the slimes and saws are now
#     (SNAP), ten times a second: the others move their copies between.
#   - EACH GAME'S OWN CUT ("h", anyone's): [x, code, row + 1], the code
#     stamp() x KIND_SPAN plus what it is - a cell added to its cut (ADD), its
#     cut lost (DROP), its cut closed (CLOSE), a pickup crossed (TAKE, the
#     pickup's number in x). Every game marks the others' cuts on its cloth
#     (clothrun.gd OTHER); a shot that runs into one crashes, and only that
#     player loses a life. The leader cuts away what a closed cut leaves no
#     slime and no other open cut in, for everyone.
#   - EACH PLAYER ("me", everyone's): key, flags (READY, OUT), lives, the
#     rounds cleared while still in. Every screen draws the party from them;
#     the run is over when everybody is out.
# A KEY A RUN: the leader picks it while the party waits. A game that hears a
# run already begun cuts its own, alone. The stamp is the key and the round,
# so a cut from another run, or a round gone, never lands.
#
# READY, THEN A COUNTDOWN - the Stand's (magestandparty.gd): each presses
# Ready; everyone ready, the leader counts COUNTDOWN_SECONDS and every screen
# counts with it; at nought each begins (start_now).
extends Node

signal start_now
signal counting_began
signal counting_stopped

const AREA := "cloth"
const TICK_SECONDS := 0.1
const LINE_EVERY := 0.5
const ME_EVERY := 1.0
const KEY_MOST := 1000000
# "h": [x, stamp() * KIND_SPAN + kind, row + 1]; the stamp is key x
# ROUND_SPAN plus the round.
const KIND_SPAN := 16
const ROUND_SPAN := 64
const ADD := 1
const DROP := 2
const CLOSE := 3
const TAKE := 4
# The presence server's limits (presence.py RUN_BATCHES_MOST, RUN_BATCH_MOST,
# MAX_RUN_HITS, RUN_SLOTS), and how many numbers a message carries at most
# (MAX_RUN_BYTES is 32 KB).
const BATCHES_MOST := 16
const BATCH_MOST := 700
const HITS_MOST := 256
const SLOTS_MOST := 8192
const NUMBERS_A_MESSAGE := 3000
# A line's started: waiting, begun, counting down; and a game cutting alone.
const WAITING := 0
const BEGUN := 1
const COUNTING := 2
const ALONE := -1
const COUNTDOWN_SECONDS := 3.0
const COUNTDOWN_SLACK := 0.3
const CANCEL_LATE := 0.6
const LINE_SIZE := 9
# Each player's own line: [key, flags, lives, rounds cleared].
const READY := 1
const OUT := 2
const ME_SIZE := 4
# clothrun.gd State.OVER, as the line says it.
const OVER_STATE := 2
# The leader's events.
const EV_ROUND := 1
const EV_CUT := 2
const EV_OPEN := 3
const EV_CLEAR := 4
const EV_PICKUP := 5
const EV_GONE := 6
const EV_FLARE := 7
const EV_GUST := 8
const EV_OVER := 9
const EV_SAY := 10
const SNAP := 20

var run: Node = null
# The presence link: the Presence autoload, or the suite's stand-in.
var link: Node = null
var key: int = 0
var said_ready: bool = false
var counting: float = -1.0
var heard_begun: bool = false
# The suite's door: this player's name on the board.
var own_name: Callable = Callable(self, "_own_name")

var _events: int = 0
var _outbox: Array = []
var _cuts: Array = []
var _members: Dictionary = {}
var _applied: Dictionary = {}
var _last_line: Array = []
var _last_me: Array = []
var _line_left: float = 0.0
var _tick_left: float = 0.0
var _me_left: float = 0.0
var _started: bool = false
var _seated: Array = []
var _snap_seq: int = 0
var _snap_from: int = -1
var _snap_heard: int = 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	if link == null:
		link = Presence
	if link.has_signal("run_received"):
		link.run_received.connect(_on_run)


# =============================================================================
# WHO IS HERE
# =============================================================================

func rooms() -> bool:
	"""Whether the server seats the cloth a room per party."""
	if link == null:
		return false
	return bool(link.call("cloth_rooms")) if link.has_method("cloth_rooms") else bool(link.runs())


func active() -> bool:
	"""A party run to share: the room, somebody else in it, somebody leading
	it, and this game not cutting alone."""
	return key != ALONE and rooms() and int(link.sharers()) > 0 and int(link.leader_for(AREA)) >= 0


func leads() -> bool:
	"""Whether this game runs the run: alone, or the room's leader."""
	return not active() or int(link.leader_for(AREA)) == int(link.my_id())


func my_id() -> int:
	return int(link.my_id()) if link != null else 0


func members() -> int:
	return 1 + int(link.sharers()) if active() else 1


func _here() -> Array:
	var ids: Array = (link.remotes() as Dictionary).keys() if link.has_method("remotes") else []
	ids.sort()
	return ids


func name_of(id: int) -> String:
	var body: Variant = (link.remotes() as Dictionary).get(id) if link.has_method("remotes") else null
	if is_instance_valid(body):
		for field in ["display_name", "username", "player_name"]:
			if field in body and str(body.get(field)) != "":
				return str(body.get(field))
	return "a player"


func body_of(id: int) -> Node2D:
	"""The step-drawn picture of a player here (never shown: where its shot
	rides), or null."""
	var body: Variant = (link.remotes() as Dictionary).get(id) if link.has_method("remotes") else null
	return body as Node2D if is_instance_valid(body) and body is Node2D else null


func _own_name() -> String:
	return str(Api.username) if str(Api.username) != "" else "You"


func _line_of(id: int) -> Array:
	var said: Variant = _members.get(id)
	return said if said is Array and (said as Array).size() >= ME_SIZE else []


func flags_of(id: int) -> int:
	var line: Array = _line_of(id)
	return int(line[1]) if not line.is_empty() else 0


func in_run(id: int) -> bool:
	"""Whether a player here was heard in this run."""
	var line: Array = _line_of(id)
	return not line.is_empty() and int(line[0]) == key and key > 0


func cutters() -> Array:
	"""(In a run.) The others cutting now: [id, seat], every one in this run
	and not out."""
	var out: Array = []
	if not active():
		return out
	for id in _here():
		if in_run(int(id)) and flags_of(int(id)) & OUT == 0:
			out.append([int(id), seat_of(int(id))])
	return out


func seats() -> Array:
	"""Everyone in the run by account id, lowest first - kept from its start;
	before it, everyone here."""
	if _started and not _seated.is_empty():
		return _seated
	var ids: Array = [my_id()] if link != null else [0]
	if active():
		for id in _here():
			ids.append(int(id))
	ids.sort()
	return ids


func seat() -> int:
	return seat_of(my_id())


func seat_of(id: int) -> int:
	return maxi(0, seats().find(id))


func everyone_ready() -> bool:
	if not said_ready:
		return false
	for id in _here():
		if flags_of(int(id)) & READY == 0:
			return false
	return true


func all_out() -> bool:
	"""(Leader.) Everybody heard in this run is out of lives - this game too."""
	if run == null or not bool(run.get("out")):
		return false
	for id in _here():
		if in_run(int(id)) and flags_of(int(id)) & OUT == 0:
			return false
	return true


func my_line() -> Array:
	var flags: int = READY if said_ready else 0
	var lives: int = 0
	var cleared: int = 0
	if run != null and is_instance_valid(run):
		if bool(run.get("out")):
			flags |= OUT
		lives = int(run.get("lives"))
		cleared = int(run.get("best"))
	return [key, flags, lives, cleared]


func roster() -> Array:
	"""The party's board: this player first, then the others here - each
	{id, name, flags, lives, heard, me}."""
	var mine: Array = my_line()
	var rows: Array = [{"id": my_id(), "name": str(own_name.call()), "flags": int(mine[1]),
		"lives": int(mine[2]), "heard": true, "me": true}]
	if not active():
		return rows
	for id in _here():
		var line: Array = _line_of(int(id))
		rows.append({"id": int(id), "name": name_of(int(id)), "flags": int(line[1]) if not line.is_empty() else 0,
			"lives": int(line[2]) if not line.is_empty() else 0, "heard": not line.is_empty(), "me": false})
	return rows


# =============================================================================
# READY AND THE COUNTDOWN
# =============================================================================

func set_ready(on: bool) -> void:
	if _started or said_ready == on:
		return
	said_ready = on
	me_now()
	if not on and counting >= 0.0 and leads() and counting > CANCEL_LATE:
		_stop_counting()


func _start_counting(seconds: float) -> void:
	counting = seconds
	counting_began.emit()


func _stop_counting() -> void:
	counting = -1.0
	counting_stopped.emit()


func _count(delta: float) -> void:
	if _started or counting < 0.0:
		return
	counting = maxf(0.0, counting - delta)
	if counting <= 0.0:
		_begin_now()


func _begin_now() -> void:
	if _started:
		return
	_seated = seats()
	_started = true
	counting = -1.0
	start_now.emit()


func started() -> bool:
	return _started


func _lead_the_wait() -> void:
	if _started:
		return
	var all_ready: bool = everyone_ready()
	if counting < 0.0 and all_ready:
		_start_counting(COUNTDOWN_SECONDS)
	elif counting > CANCEL_LATE and not all_ready:
		_stop_counting()


# =============================================================================
# WHAT CROSSES
# =============================================================================

func choose_key() -> void:
	if key == 0:
		key = _rng.randi_range(1, KEY_MOST - 1)


func stamp() -> int:
	"""This run and its round: what every cut says it belongs to."""
	var which: int = int(run.get("round_now")) if run != null and is_instance_valid(run) else 0
	return key * ROUND_SPAN + posmod(which, ROUND_SPAN)


func announce(event: Array) -> void:
	"""(Leader.) A decision, numbered and keyed, to go out with the next
	line. Nothing alone."""
	if not active() or not leads():
		return
	choose_key()
	_events += 1
	_outbox.append([key, _events] + event)


func tell(kind: int, x: int = 0, y: int = 0) -> void:
	"""This game's own cut: a cell added, the cut lost or closed, a pickup
	crossed - in the order it happened."""
	if not active() or key <= 0:
		return
	_cuts.append([clampi(x, 0, SLOTS_MOST - 1), stamp() * KIND_SPAN + kind, clampi(y + 1, 1, 100000)])


# WHO SPENT IT (0.152.0): this minigame's own frame, timed, so a slow
# frame on the readout names it (PerfOverlay.spend()).
func _process(delta: float) -> void:
	var spent_from: int = Time.get_ticks_usec()
	_timed_process(delta)
	PerfOverlay.spend(&"cloth party", Time.get_ticks_usec() - spent_from)


func _timed_process(delta: float) -> void:
	if run == null or link == null:
		return
	if not active():
		_cuts.clear()
		_outbox.clear()
		if counting >= 0.0 and not _started:
			_stop_counting()
		run.call("forget_gone", [])
		return
	# THE OLD LEADER WENT: the run sees it (clothrun.gd take_over()).
	var leading: bool = leads()
	_tick_left -= delta
	_line_left -= delta
	_me_left -= delta
	if leading:
		choose_key()
		_lead_the_wait()
	_count(delta)
	if _tick_left <= 0.0:
		_tick_left = TICK_SECONDS
		var here: Array = []
		for id in _here():
			if in_run(int(id)):
				here.append(int(id))
		run.call("forget_gone", here)
		flush()


func flush() -> void:
	"""What this game has to say: the leader's line, its decisions and the
	slimes where they are; this game's own cut since the last beat; this
	player's own line."""
	if not active():
		return
	var message: Dictionary = {}
	if leads():
		choose_key()
		var line: Array = party_line()
		var batches: Array = []
		var numbers: int = 0
		while not _outbox.is_empty() and batches.size() < BATCHES_MOST - 1 \
				and numbers + (_outbox[0] as Array).size() <= NUMBERS_A_MESSAGE:
			var event: Array = _outbox.pop_front()
			numbers += event.size()
			batches.append(event)
		if _started and bool(run.call("snapshot_due")):
			_snap_seq += 1
			var snap: Array = [key, 0, SNAP, _snap_seq] + (run.call("snapshot") as Array)
			batches.append(snap.slice(0, BATCH_MOST))
		if line != _last_line or _line_left <= 0.0 or not batches.is_empty():
			_line_left = LINE_EVERY
			_last_line = line
			message["r"] = line
		if not batches.is_empty():
			message["sp"] = batches
	if key > 0:
		if not _cuts.is_empty():
			message["h"] = _cuts.slice(0, HITS_MOST)
			_cuts = _cuts.slice(HITS_MOST)
		var me: Array = my_line()
		if me != _last_me or _me_left <= 0.0:
			_me_left = ME_EVERY
			_last_me = me
			message["me"] = me
	else:
		_cuts.clear()
	if not message.is_empty():
		link.send_run(message)


func party_line() -> Array:
	"""(Leader.) The run's line: [key, state, round, started, countdown
	(tenths), cut (thousandths), her piece (thousandths), Slow left (tenths),
	players]."""
	var started_now: int = BEGUN if _started else (COUNTING if counting >= 0.0 else WAITING)
	var numbers: Array = run.call("line_numbers") if run != null and is_instance_valid(run) else [0, 1, 0, 1000, 0, 1]
	return [key, int(numbers[0]), int(numbers[1]), started_now, roundi(maxf(0.0, counting) * 10.0),
		int(numbers[2]), int(numbers[3]), int(numbers[4]), int(numbers[5])]


func me_now() -> void:
	_me_left = 0.0
	_tick_left = 0.0


func _on_run(from_id: int, data: Dictionary) -> void:
	if run == null or not is_instance_valid(run) or key == ALONE:
		return
	var leader: int = int(link.leader_for(AREA))
	if data.get("r") is Array and from_id == leader and not leads():
		var line: Array = data["r"]
		if line.size() >= LINE_SIZE:
			var their_key: int = int(line[0])
			var begun: bool = int(line[3]) == BEGUN
			if key == 0:
				if begun and int(line[1]) == OVER_STATE:
					# THE LAST RUN, OVER: wait for the leader's next.
					return
				if begun:
					# A RUN ALREADY BEGUN, heard by a game just come: its own.
					key = ALONE
					return
				key = their_key
			elif their_key != key:
				if heard_begun or begun or _started:
					return
				key = their_key
				_last_me = []
			if not _started:
				var started_now: int = int(line[3])
				if started_now == COUNTING and said_ready:
					var left: float = float(line[4]) / 10.0
					if counting < 0.0:
						_start_counting(left)
					elif absf(counting - left) > COUNTDOWN_SLACK:
						counting = left
				elif started_now == WAITING and counting >= 0.0:
					_stop_counting()
			if begun and not heard_begun:
				heard_begun = true
				if said_ready or _started:
					_begin_now()
				else:
					# BEGUN WITHOUT THIS PLAYER READY: its own.
					key = ALONE
					counting = -1.0
					return
			if _started:
				run.call("follow_line", line)
	# The leader's decisions before anybody's cuts: a round begun, then its
	# cells (a round's cuts and its seed can come in one message).
	if data.get("sp") is Array and not leads() and key > 0 and _started and from_id == leader:
		for event in data["sp"]:
			if not (event is Array) or (event as Array).size() < 3 or int(event[0]) != key:
				continue
			var no: int = int(event[1])
			if no == 0:
				if int(event[2]) == SNAP and (event as Array).size() >= 4:
					var seq: int = int(event[3])
					if from_id != _snap_from or seq > _snap_heard:
						_snap_from = from_id
						_snap_heard = seq
						run.call("apply_snapshot", (event as Array).slice(4))
				continue
			var said: String = "%d:%d" % [from_id, no]
			if not _applied.has(said):
				_applied[said] = true
				run.call("apply_event", from_id, (event as Array).slice(2))
	if data.get("h") is Array and key > 0 and _started:
		for cut in data["h"]:
			if not (cut is Array) or (cut as Array).size() != 3:
				continue
			var code: int = int(cut[1])
			@warning_ignore("integer_division")
			if code / KIND_SPAN != stamp():
				continue
			run.call("party_heard", from_id, code % KIND_SPAN, int(cut[0]), int(cut[2]) - 1)
	if data.get("me") is Array:
		var me: Array = data["me"]
		if me.size() >= ME_SIZE and int(me[0]) == key and key > 0:
			_members[from_id] = me.duplicate()
