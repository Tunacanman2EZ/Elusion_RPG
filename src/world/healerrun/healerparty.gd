# healerparty.gd - the Healer's Run with the party (0.105.0).
#
# The owner: "i was thinking we could make the field bigger and scale the
# minigame a little by making it to where you can join with your party", and
# of the gold: "each player". The plan is the commit folder's
# HEALER_RUN_PARTY_PLAN.txt. Nothing here is used alone: with nobody else in
# the room, active() is false and the run plays as it always did.
#
# WHERE. A game playing the run with a server that says "hr" in its welcome
# tells the presence server it stands in "healerrun" (Presence.state_override,
# set by healerrunscreen.gd), and the server seats it in its party's room, as
# the Endless's arena. The party's healers are drawn there from their steps.
#
# WHO DECIDES WHAT. The game leading the room (the earliest in) runs the run;
# every game moves and shoots its own copy of every monster. What crosses is
# "en" (Presence.send_run(), run_received) - whole numbers only:
#   - THE LINE ("r", leader's): key, state, tier, wave in tier, waves done,
#     bosses beaten, the fire (tenths), players, the clock (tenths), the three
#     lands, started - healerrun.gd line() / follow_line().
#   - WHAT IS BORN ("sp", leader's): each decision as an event - key, number,
#     type, seed, rank, tier, wave in tier, land, players, then its own
#     numbers. Every game makes the same monsters from it with the same seed
#     (healerrun.gd apply_event()).
#   - HITS ("h", anyone's): [slot, batch, damage]; a batch is key x BATCH_SPAN
#     plus the event's number, so another run's hits never land. Every game
#     takes every hit, so a monster dies on every screen.
#   - EACH PLAYER ("me", everyone's, to everyone): key, flags (READY, DONE,
#     OUT), power-ups taken, lives, kills, gold - the leader pushes the fire
#     back for every power-up and ends the run when nobody is in; every screen
#     draws the party's board from them (roster()).
# A KEY A RUN: the leader picks it while the party waits. A game that hears a
# run already begun plays its own, alone - joining half way would pay for
# what others did.
#
# READY, THEN A COUNTDOWN (the owner: "we need a ready for all players then a
# countdown and still have the option to leave incase some one goes afk and
# noone can ready", "noone starts ahead everyone starts at the same time").
# Each player presses Ready (set_ready(), said in "me"); with everyone in the
# room ready the leader counts COUNTDOWN_SECONDS, in the line (started
# COUNTING and the tenths left), and every screen counts the same seconds from
# what it heard. At nought each begins (start_now) - the leader's line saying
# begun starts anybody whose count ran slow. Somebody new in the room, or not
# ready, stops the count (counting_stopped) until the last CANCEL_LATE of it.
# The countdown is when each game asks the server for its run of the day
# (counting_began, the screen's): Leave before it costs nothing.
extends Node

signal start_now
signal counting_began
signal counting_stopped

const AREA := "healerrun"
const TICK_SECONDS := 0.2
const LINE_EVERY := 0.5
const ME_EVERY := 1.0
# Events in one run at most: a hit's batch is key x BATCH_SPAN + event.
const BATCH_SPAN := 2000
const KEY_MOST := 1000000
# The presence server's limits (presence.py RUN_BATCHES_MOST, MAX_RUN_HITS).
const EVENTS_A_MESSAGE := 16
const HITS_MOST := 256
# A line's started: waiting, begun, counting down; and a game playing alone
# (no key).
const WAITING := 0
const BEGUN := 1
const COUNTING := 2
const ALONE := -1
const COUNTDOWN_SECONDS := 3.0
# A count heard this far from this game's is taken as the leader's.
const COUNTDOWN_SLACK := 0.3
# Under this much of it left the count is not stopped: it would reach the
# others after they began.
const CANCEL_LATE := 0.6
# Each player's own line: [key, flags, power-ups, lives, kills, gold].
const READY := 1
const DONE := 2
const OUT := 4
const ME_SIZE := 6

var run: Node = null
# The presence link: the Presence autoload, or the suite's stand-in.
var link: Node = null
# This run's key, the leader's choosing: 0 until chosen or heard, ALONE when
# this game plays its own.
var key: int = 0
# This game's power-ups, told to the leader (the fire is the leader's).
var pushes: int = 0
# Monsters this player's blows finished (healerrun.gd _strike()).
var kills: int = 0
# This player pressed Ready.
var said_ready: bool = false
# The countdown: seconds left, -1 when not counting.
var counting: float = -1.0
# The leader's fire, as last heard (followers draw it).
var line_fire: float = 0.0
var heard_begun: bool = false
# The suite's door: this player's name on the board.
var own_name: Callable = Callable(self, "_own_name")

var _events: int = 0
var _outbox: Array = []
var _hits: Dictionary = {}
var _frac: Dictionary = {}
# Every other player's latest "me", by id.
var _members: Dictionary = {}
var _pushes_seen: Dictionary = {}
var _applied: Dictionary = {}
var _last_line: Array = []
var _last_me: Array = []
var _line_left: float = 0.0
var _tick_left: float = 0.0
var _me_left: float = 0.0
var _was_leading: bool = true
var _started: bool = false
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
	"""Whether the server seats the run a room per party."""
	if link == null:
		return false
	return bool(link.call("healer_rooms")) if link.has_method("healer_rooms") else bool(link.runs())


func active() -> bool:
	"""Whether there is a party run to share: the room, somebody else in it,
	somebody leading it, and this game not playing alone."""
	return key != ALONE and rooms() and int(link.sharers()) > 0 and int(link.leader_for(AREA)) >= 0


func leads() -> bool:
	"""Whether this game runs the run: alone, or the room's leader."""
	return not active() or int(link.leader_for(AREA)) == int(link.my_id())


func members() -> int:
	"""How many are in the room, this one included."""
	return 1 + int(link.sharers()) if active() else 1


func _here() -> Array:
	"""The others in the room, by id, in order."""
	var ids: Array = (link.remotes() as Dictionary).keys() if link.has_method("remotes") else []
	ids.sort()
	return ids


func name_of(id: int) -> String:
	"""A player's name as drawn here, or "a player"."""
	var body: Variant = (link.remotes() as Dictionary).get(id) if link.has_method("remotes") else null
	if is_instance_valid(body):
		for field in ["display_name", "username", "player_name"]:
			if field in body and str(body.get(field)) != "":
				return str(body.get(field))
	return "a player"


func leader_name() -> String:
	"""The leading player's name, as drawn here, or "the leader"."""
	if not active():
		return "the leader"
	var said: String = name_of(int(link.leader_for(AREA)))
	return "the leader" if said == "a player" else said


func _own_name() -> String:
	return str(Api.username) if str(Api.username) != "" else "You"


func flags_of(id: int) -> int:
	var said: Variant = _members.get(id)
	return int((said as Array)[1]) if said is Array and (said as Array).size() >= 2 else 0


func everyone_out() -> bool:
	"""(Leader.) Whether every other player here is out of lives or through."""
	for id in _here():
		if not _members.has(int(id)) or flags_of(int(id)) & (OUT | DONE) == 0:
			return false
	return true


func everyone_ready() -> bool:
	"""Whether this player and everyone else in the room has said Ready."""
	if not said_ready:
		return false
	for id in _here():
		if flags_of(int(id)) & READY == 0:
			return false
	return true


func my_flags() -> int:
	var flags: int = READY if said_ready else 0
	if run != null and is_instance_valid(run):
		var state: int = int(run.get("state"))
		if state == 4:
			flags |= DONE
		elif bool(run.get("ghost")) or state == 5:
			flags |= OUT
	return flags


func my_line() -> Array:
	"""This player's own line: key, flags, power-ups, lives, kills, gold."""
	var lives: int = int(run.get("lives")) if run != null and is_instance_valid(run) and not bool(run.get("ghost")) else 0
	var gold: int = int(run.call("gold_now")) if run != null and is_instance_valid(run) else 0
	return [key, my_flags(), pushes, lives, kills, gold]


func roster() -> Array:
	"""The party's board: this player first, then the others in the room -
	each {name, flags, lives, kills, gold, heard, me}."""
	var mine: Array = my_line()
	var rows: Array = [{"name": str(own_name.call()), "flags": int(mine[1]), "lives": int(mine[3]),
		"kills": int(mine[4]), "gold": int(mine[5]), "heard": true, "me": true}]
	if not active():
		return rows
	for id in _here():
		var said: Variant = _members.get(int(id))
		var line: Array = said if said is Array and (said as Array).size() >= ME_SIZE else [0, 0, 0, 0, 0, 0]
		rows.append({"name": name_of(int(id)), "flags": int(line[1]), "lives": int(line[3]), "kills": int(line[4]),
			"gold": int(line[5]), "heard": said is Array, "me": false})
	return rows


func party_gold() -> int:
	"""The whole party's gold: each player's own run, added up."""
	var total: int = 0
	for row in roster():
		total += int(row["gold"])
	return total


# =============================================================================
# READY AND THE COUNTDOWN
# =============================================================================

func set_ready(on: bool) -> void:
	"""This player is ready (or not), said at once."""
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
	"""The countdown, on every screen: at nought, everyone begins."""
	if _started or counting < 0.0:
		return
	counting = maxf(0.0, counting - delta)
	if counting <= 0.0:
		_begin_now()


func _begin_now() -> void:
	if _started:
		return
	_started = true
	counting = -1.0
	start_now.emit()


# =============================================================================
# THE LEADER'S HALF
# =============================================================================

func choose_key() -> void:
	"""(Leader, waiting.) This run's key, if it has none."""
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


func take_pushes(from_id: int, total: int) -> void:
	"""(Leader.) A player's power-ups: each new one pushes the fire back."""
	var seen: int = int(_pushes_seen.get(from_id, 0))
	_pushes_seen[from_id] = total
	for i in maxi(0, total - seen):
		run.call("push_fire")


func _lead_the_wait() -> void:
	"""(Leader, before the run.) Everyone ready: the count; somebody not (or
	somebody new) while it has time left: stopped."""
	if _started or bool(run.get("begun")):
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
	if not active() or batch < 0 or slot < 0 or slot >= 4096:
		return
	var id: String = "%d:%d" % [batch, slot]
	var sum: float = float(_frac.get(id, 0.0)) + damage
	var whole: int = int(floor(sum))
	_frac[id] = sum - whole
	if whole >= 1:
		_hits[id] = int(_hits.get(id, 0)) + whole


func _process(delta: float) -> void:
	if run == null or link == null:
		return
	if not active():
		_hits.clear()
		_outbox.clear()
		_was_leading = true
		if counting >= 0.0 and not _started:
			# EVERYBODY ELSE WENT: no count to keep.
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
	_count(delta)
	if leading:
		var line: Array = run.call("line")
		if line != _last_line or _line_left <= 0.0 or not _outbox.is_empty():
			_line_left = LINE_EVERY
			_last_line = line
			var message: Dictionary = {"r": line}
			if not _outbox.is_empty():
				message["sp"] = _outbox.slice(0, EVENTS_A_MESSAGE)
				_outbox = _outbox.slice(EVENTS_A_MESSAGE)
			link.send_run(message)
	if _tick_left <= 0.0:
		_tick_left = TICK_SECONDS
		flush()


func flush() -> void:
	"""The hits since the last beat, and this player's own line."""
	if not active() or key <= 0:
		_hits.clear()
		return
	var message: Dictionary = {}
	if not _hits.is_empty():
		var out: Array = []
		for id in _hits.keys():
			var parts: PackedStringArray = str(id).split(":")
			out.append([int(parts[1]), int(parts[0]), mini(int(_hits[id]), 1000000)])
			if out.size() >= HITS_MOST:
				break
		_hits.clear()
		message["h"] = out
	var me: Array = my_line()
	if me != _last_me or _me_left <= 0.0:
		_me_left = ME_EVERY
		_last_me = me
		message["me"] = me
	if not message.is_empty():
		link.send_run(message)


func _on_run(from_id: int, data: Dictionary) -> void:
	if run == null or not is_instance_valid(run) or key == ALONE:
		return
	if data.get("r") is Array and from_id == int(link.leader_for(AREA)):
		var line: Array = data["r"]
		if line.size() >= 13:
			var their_key: int = int(line[0])
			var started: int = int(line[12])
			var begun: bool = started == BEGUN
			if key == 0:
				if begun:
					# A RUN ALREADY BEGUN, heard by a game just come: it plays
					# its own - joining half way would be paid for others' work.
					key = ALONE
					return
				key = their_key
			elif their_key != key:
				if heard_begun or begun or _started:
					return
				# A new leader while the party waits, with a key of its own.
				key = their_key
				_last_me = []
			line_fire = float(line[6]) / 10.0
			run.call("follow_line", line)
			if not _started:
				if started == COUNTING and said_ready and line.size() >= 14:
					var left: float = float(line[13]) / 10.0
					if counting < 0.0:
						_start_counting(left)
					elif absf(counting - left) > COUNTDOWN_SLACK:
						counting = left
				elif started == WAITING and counting >= 0.0:
					# THE LEADER STOPPED THE COUNT.
					_stop_counting()
			if begun and not heard_begun:
				heard_begun = true
				if said_ready or _started:
					_begin_now()
				else:
					# BEGUN WITHOUT THIS PLAYER READY: it plays its own.
					key = ALONE
					counting = -1.0
					return
	if data.get("sp") is Array and not leads():
		for event in data["sp"]:
			if event is Array and (event as Array).size() >= 9 and int(event[0]) == key:
				var no: int = int(event[1])
				if not _applied.has(no):
					_applied[no] = true
					run.call("apply_event", event)
	if data.get("h") is Array:
		for hit in data["h"]:
			@warning_ignore("integer_division")
			if hit is Array and (hit as Array).size() == 3 and int(hit[1]) / BATCH_SPAN == key:
				run.call("strike_remote", int(hit[0]), int(hit[1]), float(hit[2]))
	if data.get("me") is Array:
		var me: Array = data["me"]
		if me.size() >= ME_SIZE and int(me[0]) == key and key > 0:
			_members[from_id] = me.duplicate()
			if leads():
				take_pushes(from_id, int(me[2]))
