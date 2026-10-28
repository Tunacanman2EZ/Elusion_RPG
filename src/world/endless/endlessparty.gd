# endlessparty.gd - the Endless run between a party (0.93.3).
#
# The owner: "we need a 4 player party plan but can play solo duo or 3 or 4",
# then "lets do it". A party has an arena of its own (the presence server
# seats it there, ONE ARENA A PARTY in presence.py), and this passes the run
# between the games in it as "en" messages (Presence.send_run(),
# run_received). Nothing here is used alone: with nobody else in the arena,
# active() is false and the run plays as it always did.
#
# WHO DECIDES WHAT. The game leading the arena (the earliest in, as for any
# area's monsters - Presence.leader_for()) runs the run:
#   - THE CLOCK: its line ("r", line()) - the state, the clock, the stage,
#     the countdown, whether the door is held open, how many the run is
#     scaled for, the party's kills and how many are in - when it changes and
#     every LINE_EVERY. The others follow it (endlessrun.gd follow_line()).
#   - THE SLIMES BORN: each batch ("sp") is its number, a seed, the health and
#     land, the points it kept clear of and the slots it fills
#     (batch_wire()). Every game makes the same slimes from it
#     (swarm.gd spawn_batch()).
#   - EVERYTHING, to a game that walks in mid-run ("need" -> "full"): its line
#     and every slime as it stands, in parts of PART_SLIMES.
# Every game tells:
#   - ITS HITS ON THE SWARM ("h"): [slot, batch, damage], every TICK_SECONDS
#     (0.2: five messages a second, inside the server's forty).
#     Every copy takes every hit, so the same slime dies on every screen.
#   - ITS PLAYER ("me"): [in the run, its own kills], when it changes and every
#     ME_EVERY. The leader ends the run when nobody is in.
#   - THE DOOR ("go"): its player stepped through first - the leader starts
#     the countdown.
# When the leader leaves, the presence server names the next game in line,
# which takes the run over where it stands (endlessrun.gd take_over(), from
# its own frame: before it judges whether anybody is in).
extends Node

const SwarmScript := preload("res://src/world/endless/swarm.gd")

const AREA := "endless"
# How often hits, slimes born and the players' lines go out: five messages a
# second. A game already sends the server ten states, ten attack pictures and
# ten monster messages a second, and it takes forty.
const TICK_SECONDS := 0.2
# The leader's line at least this often, and each player's own.
const LINE_EVERY := 1.0
const ME_EVERY := 1.0
# The presence server's own limits (presence.py MAX_RUN_HITS, RUN_BATCHES_MOST,
# RUN_BATCH_MOST, RUN_FULL_MOST): a batch's head is 5 numbers and two a point
# kept clear of, the rest its slots.
const HITS_MOST := 256
const BATCHES_MOST := 16
const BATCH_MOST := 700
const AVOID_MOST := 8
const BATCH_SLOTS_MOST := BATCH_MOST - 5 - 2 * AVOID_MOST
# Slimes in one part of everything: six numbers each, about 12 KB a part.
const PART_SLIMES := 400
# A game walking in that has heard nothing asks again after this long.
const NEED_AGAIN_SECONDS := 3.0
# How long a "go" waits before another may be sent.
const GO_EVERY := 1.0

var run: Node = null
# The presence link: the Presence autoload in the game, a stand-in in the
# suite - anything with runs(), my_id(), leader_for(), sharers(), remotes(),
# send_run() and the run_received and lead_changed signals.
var link: Node = null

var _tick_left: float = 0.0
var _line_left: float = 0.0
var _me_left: float = 0.0
var _go_left: float = 0.0
var _hits: Array = []
var _batches: Array = []
var _last_line: Array = []
var _last_me: Array = []
# (Leader.) Each other player's last line: id -> [in, kills].
var _members: Dictionary = {}
# (Follower.) Everything, arriving in parts: part -> its numbers.
var _parts: Dictionary = {}
var _asked: bool = false
var _need_left: float = 0.0
var _wired_swarm: Node = null


func _ready() -> void:
	if link == null:
		link = Presence
	if link.has_signal("run_received"):
		link.run_received.connect(_on_run)
	if link.has_signal("lead_changed"):
		link.lead_changed.connect(_on_lead)


# =============================================================================
# WHO IS HERE
# =============================================================================

func active() -> bool:
	"""Whether there is a party run to share: a server that passes it, a game
	leading the arena, and somebody else in it."""
	return link != null and link.runs() and link.sharers() > 0 and link.leader_for(AREA) >= 0


func leads() -> bool:
	"""Whether this game runs the run: alone, or the arena's leader."""
	return not active() or link.leader_for(AREA) == link.my_id()


func members() -> int:
	"""How many players are in the arena, this one included."""
	return 1 + link.sharers() if active() else 1


func others_in() -> int:
	"""(Leader.) How many of the others say they are in the run."""
	var n: int = 0
	var here: Dictionary = link.remotes() if link.has_method("remotes") else {}
	for id in _members.keys():
		if not here.has(id):
			continue
		if int((_members[id] as Array)[0]) == 1:
			n += 1
	return n


func member_kills() -> Dictionary:
	var out := {}
	for id in _members.keys():
		out[id] = int((_members[id] as Array)[1])
	return out


func other_positions() -> PackedVector2Array:
	"""Where the party's other players stand, as drawn here."""
	var out := PackedVector2Array()
	if not active() or not link.has_method("remotes"):
		return out
	for body in (link.remotes() as Dictionary).values():
		if is_instance_valid(body) and body is Node2D:
			out.append((body as Node2D).global_position)
	return out


# =============================================================================
# EACH FRAME
# =============================================================================

func _process(delta: float) -> void:
	if run == null:
		return
	var swarm: Node = run.get("swarm")
	_wire(swarm)
	if swarm != null:
		swarm.set("others", other_positions())
	var leading: bool = leads()
	if not active():
		_hits.clear()
		_batches.clear()
		_members.clear()
		_asked = false
		return
	if not leading:
		_need_left -= delta
		if not _asked or _need_left <= 0.0 and run.get("state") == 0 and _parts.is_empty() and _never_heard():
			_ask_for_everything()
	_go_left -= delta
	_tick_left -= delta
	_line_left -= delta
	_me_left -= delta
	if _tick_left <= 0.0:
		_tick_left = TICK_SECONDS
		flush()


var _heard_line: bool = false


func _never_heard() -> bool:
	return not _heard_line


func ask_everything() -> void:
	"""(Not leading.) Ask the leader for the run as it stands, now."""
	if active() and not leads():
		_ask_for_everything()


func _ask_for_everything() -> void:
	_asked = true
	_need_left = NEED_AGAIN_SECONDS
	link.send_run({"need": 1})


func _wire(swarm: Node) -> void:
	if swarm == _wired_swarm:
		return
	if _wired_swarm != null and is_instance_valid(_wired_swarm) and _wired_swarm.is_connected("struck", _on_struck):
		_wired_swarm.disconnect("struck", _on_struck)
	_wired_swarm = swarm
	if swarm != null and swarm.has_signal("struck"):
		swarm.connect("struck", _on_struck)


func _on_struck(slot: int, number: int, damage: int, _died: bool) -> void:
	if active():
		_hits.append([slot, number, mini(damage, 100000)])


func flush() -> void:
	"""What this game has to say this tick: the leader's line and its slimes
	born, everybody's hits and their own line - in as few messages as the
	server's limits allow."""
	if not active():
		return
	var leading: bool = leads()
	var first: Dictionary = {}
	if leading:
		var line: Array = run.call("line")
		if line != _last_line or _line_left <= 0.0:
			first["r"] = line
			_last_line = line
			_line_left = LINE_EVERY
	var me: Array = [1 if bool(run.get("my_in")) else 0, int(run.get("swarm").get("my_slain"))]
	if me != _last_me or _me_left <= 0.0:
		first["me"] = me
		_last_me = me
		_me_left = ME_EVERY
	var message: Dictionary = first
	var sent: int = 0
	# At most two a tick; anything more waits for the next.
	while sent < 2:
		if leading and not _batches.is_empty():
			message["sp"] = _batches.slice(0, BATCHES_MOST)
			_batches = _batches.slice(BATCHES_MOST)
		if not _hits.is_empty():
			message["h"] = _hits.slice(0, HITS_MOST)
			_hits = _hits.slice(HITS_MOST)
		if message.is_empty():
			break
		link.send_run(message)
		sent += 1
		message = {}


func line_now() -> void:
	"""The leader's line goes out with the next tick, whatever its timer."""
	_line_left = 0.0
	_tick_left = 0.0


func ask_go() -> void:
	"""(Not leading.) This game's player stepped through the door first."""
	if active() and _go_left <= 0.0:
		_go_left = GO_EVERY
		link.send_run({"go": 1})


# =============================================================================
# THE LEADER'S SLIMES
# =============================================================================

func spawn(count: int, avoid: PackedVector2Array, health: int, land: int) -> int:
	"""(Leader.) `count` new slimes, made here and told to every game as one
	batch they can make the same from. Returns how many came."""
	var swarm: Node = run.get("swarm")
	var slots: PackedInt32Array = swarm.call("take_slots", mini(count, BATCH_SLOTS_MOST))
	if slots.is_empty():
		return 0
	var points := PackedVector2Array()
	for point in avoid:
		if points.size() >= AVOID_MOST:
			break
		points.append(Vector2(roundf(point.x), roundf(point.y)))
	var number: int = int(swarm.get("batch")) + 1
	var seed_value: int = randi() & 0x3fffffff
	var used: PackedInt32Array = swarm.call("spawn_batch", number, seed_value, slots, points, float(health), land)
	if used.size() < slots.size():
		var back := PackedInt32Array()
		for i in slots:
			if not used.has(i):
				back.append(i)
		swarm.call("give_back", back)
	if not used.is_empty():
		_batches.append(batch_wire(number, seed_value, health, land, points, used))
	return used.size()


static func batch_wire(number: int, seed_value: int, health: int, land: int, avoid: PackedVector2Array,
		slots: PackedInt32Array) -> Array:
	"""A batch on the wire: [number, seed, health, land, points, x, y, ...,
	slot, slot, ...] - whole numbers, as the server takes them."""
	var out: Array = [number, seed_value, health, land, avoid.size()]
	for point in avoid:
		out.append(int(point.x))
		out.append(int(point.y))
	for i in slots:
		out.append(i)
	return out


func apply_batch(wire: Array) -> int:
	"""(Not leading.) The leader's batch, made here exactly as it made it."""
	if wire.size() < 5:
		return 0
	var points: int = int(wire[4])
	if points < 0 or points > AVOID_MOST or wire.size() < 5 + 2 * points:
		return 0
	var avoid := PackedVector2Array()
	for k in points:
		avoid.append(Vector2(float(wire[5 + 2 * k]), float(wire[6 + 2 * k])))
	var slots := PackedInt32Array()
	for k in range(5 + 2 * points, wire.size()):
		slots.append(int(wire[k]))
	var swarm: Node = run.get("swarm")
	var used: PackedInt32Array = swarm.call("spawn_batch", int(wire[0]), int(wire[1]), slots, avoid,
		float(wire[2]), int(wire[3]))
	return used.size()


# =============================================================================
# WHAT THE OTHERS SAY
# =============================================================================

func _on_run(from_id: int, data: Dictionary) -> void:
	if run == null:
		return
	var leading: bool = leads()
	var swarm: Node = run.get("swarm")
	if data.get("full") is Array:
		if not leading:
			_take_part(data)
	if data.get("r") is Array and not leading:
		_heard_line = true
		run.call("follow_line", data["r"])
	if data.get("sp") is Array and not leading:
		for wire in data["sp"]:
			if wire is Array:
				apply_batch(wire)
	if data.get("h") is Array and swarm != null:
		for hit in data["h"]:
			if hit is Array and (hit as Array).size() == 3:
				swarm.call("hurt_remote", int(hit[0]), int(hit[1]), int(hit[2]))
	if data.get("me") is Array and (data["me"] as Array).size() >= 2:
		_members[from_id] = [int(data["me"][0]), int(data["me"][1])]
	if leading and active():
		if int(data.get("go", 0)) == 1:
			run.call("party_go")
		if int(data.get("need", 0)) == 1:
			send_everything(from_id)


func _on_lead(area: String, _leader_id: int, _sharers: int) -> void:
	if area != AREA:
		return
	# Somebody came or went, or the run changed hands: the leader's line goes
	# out at once. Only a game that has not heard the run yet asks for
	# everything (it asks on its first frame) - every copy in the arena
	# already holds the same slimes, whoever leads them now.
	_line_left = 0.0


func send_everything(to: int) -> void:
	"""(Leader.) The run as it stands, to a game that walked in: the line and
	every slime, in parts."""
	var line: Array = run.call("line")
	var slimes: PackedInt32Array = run.get("swarm").call("export_alive")
	var per: int = PART_SLIMES * SwarmScript.RECORD
	var parts: int = maxi(1, ceili(float(slimes.size()) / float(per)))
	for part in parts:
		var numbers: Array = [line.size()]
		numbers.append_array(line)
		numbers.append_array(Array(slimes.slice(part * per, (part + 1) * per)))
		link.send_run({"full": numbers, "part": part, "parts": parts}, to)


func _take_part(data: Dictionary) -> void:
	var parts: int = int(data.get("parts", 1))
	var part: int = int(data.get("part", 0))
	if parts < 1 or part < 0 or part >= parts:
		return
	_parts[part] = data["full"]
	if _parts.size() < parts:
		return
	var slimes := PackedInt32Array()
	var line: Array = []
	for k in parts:
		var numbers: Array = _parts.get(k, [])
		if numbers.is_empty():
			_parts.clear()
			return
		var head: int = int(numbers[0])
		line = numbers.slice(1, 1 + head)
		for v in numbers.slice(1 + head):
			slimes.append(int(v))
	_parts.clear()
	_heard_line = true
	run.call("follow_everything", line, slimes)
