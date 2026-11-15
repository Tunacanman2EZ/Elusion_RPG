# magestandparty.gd - THE MAGE'S STAND TOGETHER (0.161.0, step 5 of the
# commit folder's MAGES_STAND_PLAN.txt: "2 players can be on left 2 can be on
# right", and section 9: "the leader decides the waves, hits count
# everywhere, the gate and the portal are the leader's count; Ready, the
# countdown and the board"). The owner: "the forge should be 4 player mages
# stand also".
#
# Nothing here is used alone: with nobody else in the room, active() is false
# and the Stand plays as it always did.
#
# WHERE. A game playing the Stand with a server that says "ms" in its welcome
# tells the presence server it stands in "magestand" (Presence.state_override,
# set by magestandscreen.gd), and the server seats it in its party's room, as
# the Healer's Run's. The party's mages are drawn on the wall from their steps
# (Presence.world_override, magestand.gd `others`), every one as the mage
# (Presence.class_override).
#
# SEATS. Everyone in the run, by account id, lowest first: the first on the
# left of the gate, the second on the right, and so on - two each side for
# four (magestand.gd side_for()). Kept from the start of the run.
#
# WHO DECIDES WHAT. The game leading the room (the earliest in) runs the
# waves, the gate, the wall and the portal; every game moves its own copy of
# every monster. What crosses is "en" (Presence.send_run(), run_received) -
# whole numbers only:
#   - THE LINE ("r", the leader's, magestand.gd line() / follow_line()): key,
#     state, wave, waves held, the gate (tenths), the portal, the wall's two
#     sides (each three stretches packed - WALL_BASE), the star (STAR_CODES)
#     and the hits on it, players, started (waiting, begun or counting down),
#     the countdown (tenths), the clock (tenths), where the next group comes
#     in, and whether the next wave waits on the party's picks.
#   - WHAT COMES IN ("sp", the leader's): each decision as an event - key,
#     number, type, seed, then its own numbers. A group (EVENT_GROUP): the
#     wave, players, how many, where, how many of the wave are still to come.
#     Every game makes the same monsters from it with the same seed
#     (magestand.gd apply_event()). The star dropped (EVENT_STAR_DROP: where)
#     and the star called (EVENT_STAR_CALL: how many groups were in - those
#     alone are hit).
#   - HITS ("h", anyone's): [slot, batch, damage]; a batch is key x
#     BATCH_SPAN plus the group's number, so another run's hits never land.
#     Every game takes every hit, so a monster dies on every screen. A batch
#     under BATCH_SPAN is no monster's: it is a PICTURE of a meteor - [x +
#     PICTURE_X, kind, y + PICTURE_Y] - so the party's meteors fall on every
#     screen, hitting nothing there (their hits come as hits); a kind of
#     PULL_PICTURE plus a reach is the pull, dragging the same pack on every
#     screen.
#   - EACH PLAYER ("me", everyone's): key, flags (READY, PICKING), the waves
#     its picks are done through, its kills, its meteors on the lying star,
#     the Repair cards it took and the star called - the leader claims the
#     star, mends the wall and calls the star for them; every screen draws the
#     board from them (roster()).
# A KEY A RUN: the leader picks it while the party waits. A game that hears a
# run already begun plays its own, alone.
#
# READY, THEN A COUNTDOWN - the Healer's Run's (healerparty.gd): each presses
# Ready; everyone ready, the leader counts COUNTDOWN_SECONDS and every screen
# counts with it; at nought each begins (start_now).
#
# THE PICK WAITS FOR THE PARTY: after the waves that bring a pick, the leader
# holds the next wave until every player here has picked (all_picked()) - at
# most PICK_WAIT_MOST, so somebody away from the keys cannot hold it for
# ever; they pick when they are back, and cast once they have.
extends Node

signal start_now
signal counting_began
signal counting_stopped

const AREA := "magestand"
const TICK_SECONDS := 0.2
const LINE_EVERY := 0.5
const ME_EVERY := 1.0
# Events in one run at most: a hit's batch is key x BATCH_SPAN + event.
const BATCH_SPAN := 2000
const KEY_MOST := 1000000
# The presence server's limits (presence.py RUN_BATCHES_MOST, MAX_RUN_HITS,
# RUN_SLOTS).
const EVENTS_A_MESSAGE := 16
const HITS_MOST := 256
const SLOTS_MOST := 8192
# A line's started: waiting, begun, counting down; and a game playing alone.
const WAITING := 0
const BEGUN := 1
const COUNTING := 2
const ALONE := -1
const COUNTDOWN_SECONDS := 3.0
const COUNTDOWN_SLACK := 0.3
const CANCEL_LATE := 0.6
# Each player's own line: [key, flags, picked through, kills, star hits,
# repairs, star calls].
const READY := 1
const PICKING := 2
const ME_SIZE := 7
const PICK_WAIT_MOST := 25.0
# magestand.gd State.LOST and State.PICK, as the line and my_line() say them.
const LOST_STATE := 3
const PICK_STATE := 4
# A meteor's picture: its kind in the batch, where it lands in the slot and
# the damage (both moved into the server's ranges).
const PICTURE_X := 512
const PICTURE_Y := 1000
const PICTURE_METEOR := 1
const PICTURE_CRIT := 2
const PICTURE_COMET := 3
const PICTURE_SMALL := 4
const PULL_PICTURE := 100
const PICTURES_MOST := 48

var run: Node = null
# The presence link: the Presence autoload, or the suite's stand-in.
var link: Node = null
var key: int = 0
var said_ready: bool = false
var counting: float = -1.0
var heard_begun: bool = false
# The waves this player's picks are done through (said in "me").
var picked_through: int = 0
# Counted for the leader: meteors on the lying star, Repair cards, star calls.
var star_strikes: int = 0
var repairs: int = 0
var calls: int = 0
# The suite's door: this player's name on the board.
var own_name: Callable = Callable(self, "_own_name")

var _events: int = 0
var _outbox: Array = []
var _hits: Dictionary = {}
var _frac: Dictionary = {}
var _pictures: Array = []
var _members: Dictionary = {}
var _seen: Dictionary = {}
var _applied: Dictionary = {}
var _last_line: Array = []
var _last_me: Array = []
var _line_left: float = 0.0
var _tick_left: float = 0.0
var _me_left: float = 0.0
var _was_leading: bool = true
var _started: bool = false
# The ids in the run, kept from its start (seats()).
var _seated: Array = []
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
	"""Whether the server seats the Stand a room per party."""
	if link == null:
		return false
	return bool(link.call("stand_rooms")) if link.has_method("stand_rooms") else bool(link.runs())


func active() -> bool:
	"""A party run to share: the room, somebody else in it, somebody leading
	it, and this game not playing alone."""
	return key != ALONE and rooms() and int(link.sharers()) > 0 and int(link.leader_for(AREA)) >= 0


func leads() -> bool:
	"""Whether this game runs the run: alone, or the room's leader."""
	return not active() or int(link.leader_for(AREA)) == int(link.my_id())


func members() -> int:
	return 1 + int(link.sharers()) if active() else 1


func take_seat_now() -> void:
	"""Before the run: her side as the party stands now."""
	if run != null and is_instance_valid(run) and not _started and active():
		run.call("take_seat", seat())


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


func _own_name() -> String:
	return str(Api.username) if str(Api.username) != "" else "You"


func _line_of(id: int) -> Array:
	var said: Variant = _members.get(id)
	return said if said is Array and (said as Array).size() >= ME_SIZE else []


func flags_of(id: int) -> int:
	var line: Array = _line_of(id)
	return int(line[1]) if not line.is_empty() else 0


func seats() -> Array:
	"""Everyone in the run by account id, lowest first - kept from its start;
	before it, everyone here."""
	if _started and not _seated.is_empty():
		return _seated
	var ids: Array = [int(link.my_id())] if link != null else [0]
	if active():
		for id in _here():
			ids.append(int(id))
	ids.sort()
	return ids


func seat() -> int:
	"""This player's place among them (magestand.gd side_for())."""
	return maxi(0, seats().find(int(link.my_id()) if link != null else 0))


func everyone_ready() -> bool:
	if not said_ready:
		return false
	for id in _here():
		if flags_of(int(id)) & READY == 0:
			return false
	return true


func all_picked(held: int) -> bool:
	"""(Leader.) Every other player here, heard in this run, has picked for
	the waves held - one not heard holds nothing up."""
	for id in _here():
		var line: Array = _line_of(int(id))
		if line.is_empty() or int(line[0]) != key:
			continue
		if int(line[2]) < held:
			return false
	return true


func my_line() -> Array:
	var flags: int = READY if said_ready else 0
	if run != null and is_instance_valid(run) and int(run.get("state")) == PICK_STATE:
		flags |= PICKING
	var kills: int = int(run.get("my_kills")) if run != null and is_instance_valid(run) else 0
	return [key, flags, picked_through, kills, star_strikes, repairs, calls]


func roster() -> Array:
	"""The party's board: this player first, then the others here - each
	{id, name, flags, kills, heard, me}."""
	var mine: Array = my_line()
	var rows: Array = [{"id": int(link.my_id()) if link != null else 0, "name": str(own_name.call()),
		"flags": int(mine[1]), "kills": int(mine[3]), "heard": true, "me": true}]
	if not active():
		return rows
	for id in _here():
		var line: Array = _line_of(int(id))
		rows.append({"id": int(id), "name": name_of(int(id)), "flags": int(line[1]) if not line.is_empty() else 0,
			"kills": int(line[3]) if not line.is_empty() else 0, "heard": not line.is_empty(), "me": false})
	return rows


func party_kills() -> int:
	var total: int = 0
	for row in roster():
		total += int(row["kills"])
	return total


# =============================================================================
# READY AND THE COUNTDOWN
# =============================================================================

func set_ready(on: bool) -> void:
	if _started or said_ready == on:
		return
	said_ready = on
	_me_left = 0.0
	_tick_left = 0.0
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


# =============================================================================
# THE LEADER'S HALF
# =============================================================================

func choose_key() -> void:
	if key == 0:
		key = _rng.randi_range(1, KEY_MOST - 1)


func announce(event: Array) -> Array:
	"""(Leader.) A decision, numbered and keyed, to go out with the next line;
	answered for the run to make here too."""
	choose_key()
	_events += 1
	var full: Array = [key, _events % BATCH_SPAN] + event
	_outbox.append(full)
	_applied[_events % BATCH_SPAN] = true
	return full


func _take(from_id: int, line: Array) -> void:
	"""(Leader.) A player's star hits, Repair cards and star calls, each new
	one done here."""
	var seen: Array = _seen.get(from_id, [0, 0, 0])
	for k in 3:
		var total: int = int(line[4 + k])
		for i in maxi(0, total - int(seen[k])):
			run.call(["party_star_hit", "party_repair", "party_call_star"][k])
		seen[k] = maxi(int(seen[k]), total)
	_seen[from_id] = seen


func _lead_the_wait() -> void:
	if _started:
		return
	var all_ready: bool = everyone_ready()
	if counting < 0.0 and all_ready:
		_start_counting(COUNTDOWN_SECONDS)
	elif counting > CANCEL_LATE and not all_ready:
		_stop_counting()


# =============================================================================
# EVERYONE'S HALF
# =============================================================================

func batch_of(event_no: int) -> int:
	return key * BATCH_SPAN + event_no


func tell_hit(batch: int, slot: int, damage: float) -> void:
	"""This game's player struck monster (batch, slot): whole points go out,
	the rest is kept for the next."""
	if not active() or batch < BATCH_SPAN or slot < 0 or slot >= SLOTS_MOST:
		return
	var id: String = "%d:%d" % [batch, slot]
	var sum: float = float(_frac.get(id, 0.0)) + damage
	var whole: int = int(floor(sum))
	_frac[id] = sum - whole
	if whole >= 1:
		_hits[id] = int(_hits.get(id, 0)) + whole


func tell_picture(at: Vector2, kind: int) -> void:
	"""A meteor of this player's, for the others to see fall (or the pull)."""
	if not active() or _pictures.size() >= PICTURES_MOST:
		return
	var x: int = clampi(roundi(at.x) + PICTURE_X, 0, SLOTS_MOST - 1)
	var y: int = clampi(roundi(at.y) + PICTURE_Y, 1, 100000)
	_pictures.append([x, clampi(kind, 1, BATCH_SPAN - 1), y])


# WHO SPENT IT (0.152.0): this minigame's own frame, timed, so a slow
# frame on the readout names it (PerfOverlay.spend()).
func _process(delta: float) -> void:
	var spent_from: int = Time.get_ticks_usec()
	_timed_process(delta)
	PerfOverlay.spend(&"stand party", Time.get_ticks_usec() - spent_from)


func _timed_process(delta: float) -> void:
	if run == null or link == null:
		return
	if not active():
		_hits.clear()
		_pictures.clear()
		_outbox.clear()
		_was_leading = true
		if counting >= 0.0 and not _started:
			_stop_counting()
		return
	var leading: bool = leads()
	if leading and not _was_leading:
		# THE OLD LEADER WENT: this game runs the run from where it stands.
		run.call("take_over")
	_was_leading = leading
	_tick_left -= delta
	_line_left -= delta
	_me_left -= delta
	if leading:
		choose_key()
		_lead_the_wait()
	take_seat_now()
	_count(delta)
	if _tick_left <= 0.0 or (leading and not _outbox.is_empty()):
		_tick_left = TICK_SECONDS
		flush()


func flush() -> void:
	"""What this game has to say: the leader's line and what came in; the
	hits and meteors since the last beat; this player's own line."""
	if not active():
		return
	var message: Dictionary = {}
	if leads():
		choose_key()
		var line: Array = run.call("line")
		if line != _last_line or _line_left <= 0.0 or not _outbox.is_empty():
			_line_left = LINE_EVERY
			_last_line = line
			message["r"] = line
			if not _outbox.is_empty():
				message["sp"] = _outbox.slice(0, EVENTS_A_MESSAGE)
				_outbox = _outbox.slice(EVENTS_A_MESSAGE)
	if key <= 0:
		_hits.clear()
		_pictures.clear()
	else:
		var out: Array = _pictures.slice(0, HITS_MOST)
		_pictures.clear()
		for id in _hits.keys():
			if out.size() >= HITS_MOST:
				break
			var parts: PackedStringArray = str(id).split(":")
			out.append([int(parts[1]), int(parts[0]), mini(int(_hits[id]), 100000)])
		_hits.clear()
		if not out.is_empty():
			message["h"] = out
		var me: Array = my_line()
		if me != _last_me or _me_left <= 0.0:
			_me_left = ME_EVERY
			_last_me = me
			message["me"] = me
	if not message.is_empty():
		link.send_run(message)


func me_now() -> void:
	_me_left = 0.0
	_tick_left = 0.0


func _on_run(from_id: int, data: Dictionary) -> void:
	if run == null or not is_instance_valid(run) or key == ALONE:
		return
	if data.get("r") is Array and from_id == int(link.leader_for(AREA)) and not leads():
		var line: Array = data["r"]
		if line.size() >= 16:
			var their_key: int = int(line[0])
			var begun: bool = int(line[11]) == BEGUN
			if key == 0:
				if begun and int(line[1]) == LOST_STATE:
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
				var started_now: int = int(line[11])
				if started_now == COUNTING and said_ready:
					var left: float = float(line[12]) / 10.0
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
			run.call("follow_line", line)
	if data.get("sp") is Array and not leads():
		for event in data["sp"]:
			if event is Array and (event as Array).size() >= 4 and int(event[0]) == key and key > 0:
				var no: int = int(event[1])
				if not _applied.has(no):
					_applied[no] = true
					run.call("apply_event", event)
	if data.get("h") is Array and key > 0:
		for hit in data["h"]:
			if not (hit is Array) or (hit as Array).size() != 3:
				continue
			var batch: int = int(hit[1])
			if batch < BATCH_SPAN:
				run.call("show_picture", Vector2(float(int(hit[0]) - PICTURE_X), float(int(hit[2]) - PICTURE_Y)), batch)
				continue
			@warning_ignore("integer_division")
			if batch / BATCH_SPAN == key:
				run.call("strike_remote", int(hit[0]), batch, float(hit[2]))
	if data.get("me") is Array:
		var me: Array = data["me"]
		if me.size() >= ME_SIZE and int(me[0]) == key and key > 0:
			_members[from_id] = me.duplicate()
			if leads() and _started:
				_take(from_id, me)
			else:
				# Kept by every game, so a new leader does none of them twice.
				_seen[from_id] = [int(me[4]), int(me[5]), int(me[6])]
