# presence.gd - other players in your world, and you in theirs.
#
# Autoload. While a character is in the world and the game is logged in, this
# keeps a WebSocket open to the presence server (presence.py, beside the API),
# says where the player stands and how they are moving whenever that changes
# (at most ten times a second), and draws everybody else in the same area as a
# RemotePlayer (src/characters/remoteplayer.gd) with their name, their pet and
# what they are doing.
#
# THE SOCKET NEVER SEES THE LOGIN. It asks the API for a ticket
# (POST /api/presence/ticket) and hands that over instead; the API's answer
# also says where the socket is (socket_url), so a browser build reaches it
# through the same address it loaded from. A ticket lasts two minutes and is
# renewed every minute, which is how a level-up or a new guild reaches other
# people's screens.
#
# WHO SOMEBODY IS COMES FROM THE SERVER. This game only sends where it is,
# which animation its body is playing, which aura is lit and which pet is out;
# names, ranks, colours, levels and the pets they may show are the server's.
#
# NOTHING HERE IS ESSENTIAL. No presence server, a dropped connection, a
# refused ticket: the game plays exactly as before, nobody else is drawn, and
# this tries again later (RETRY_SECONDS). It never tells the player.
#
# AND, SINCE 0.7.0, THE AREA'S MONSTERS. The server names one game in each
# area the LEADER (the one that has been there longest); that game runs the
# monsters and the others draw them. This file only carries the notes - who
# leads ("lead"), the leader's world ("w"), a follower's hits ("h") and the
# server asking the leader to send someone everything ("need") - and hands
# them to the area's MonsterSync (src/world/monstersync.gd) through the signals
# below. A server from before 0.7.0 never names a leader, and every game then
# fights its own monsters exactly as it used to.
#
# AND, SINCE 0.10.0, THE SERVER'S BOOKS. A server whose welcome says "books"
# keeps its own count of every monster's health from the leader's world and
# everybody's hits (presence.py, combatbook.py) - E3_SCOPE.md option C, step 1:
# it watches, and nothing in play changes. For that the leader sends its world
# even when nobody else is in the area, with its own player's hits inside it
# (monstersync.gd), and the ticket is renewed at once after an equip, so the
# server holds hits to the weapon actually in hand.
#
# AND, SINCE 0.19.0, ATTACKS AND LEVERS. The owner, after his first game with
# somebody else: "i could not see their attacks but they could see mine the had
# to lower the gate to boss". A server whose welcome says "x" passes both on:
#   - tell_attack(): the class scripts say what they threw, cast or fired; it
#     goes out with the next state, every attack made since, each with this
#     game's clock. Other games draw a picture of it (remoteattacks.gd) that
#     touches nothing - the hits still go as hits.
#   - tell_lever(): lever.gd says it was pulled; the others pull theirs, and the
#     server remembers it for the area, so a game walking in later is told
#     ("levers") and opens what is open.
# And every state carries this game's clock ("ts"), which the others play our
# steps back on (remoteplayer.gd, PLAYED BACK) - the "lag wobble" the owner saw
# running past somebody was their picture chasing steps that came unevenly.
extends Node

# The shared-monster wire this game speaks; the server's welcome says whether
# it does too. 3 (0.10.0) is 2 plus the leader's own hits inside its world.
const SHARED_VERSION := 3
# The oldest server wire this game shares monsters with.
const SHARED_MINIMUM := 2

# Who runs this area's monsters: the leader's account id, -1 for nobody (or no
# link at all), and how many other games share them.
signal lead_changed(area: String, leader_id: int, sharers: int)
# The leader's world, as it sent it. Only ever from the area's current leader:
# the server drops anyone else's.
signal world_received(data: Dictionary)
# (Leader only.) Another game's hits, as [[monster id, damage, element], ...].
signal hits_received(from_id: int, hits: Array)
# (Leader only.) The server asks for everything to be sent to this game.
signal world_needed(for_id: int)

const RemotePlayer := preload("res://src/characters/remoteplayer.gd")

const TICKET_PATH := "/api/presence/ticket"
# At most this often, and only when something changed.
const SEND_SECONDS := 0.1
# A ticket lives two minutes; a fresh one every minute.
const RENEW_SECONDS := 60.0
# After a failure, wait this long before trying again, then longer.
const RETRY_SECONDS: Array = [2.0, 5.0, 10.0, 30.0]
# What a body may be said to be doing: the player scenes' own animation names,
# and the server's rule (presence.py ANIM_PATTERN).
const ANIM_PATTERN := "^(idle|walk|attack|death|hitflash)(up|down|left|right)$"
# The tank's auras, drawn on the body.
const EFFECTS: Array = ["ring", "firering"]
# How long a "go to them" (meet()) waits for them to be drawn before giving up.
const MEET_SECONDS := 10.0
# The server's MAX_ATTACKS_PER_MESSAGE: attack pictures sent with one state.
const MAX_ATTACKS_PER_SEND := 16
# What the server takes as a lever's name: a node path in the area's scene
# (presence.py LEVER_PATTERN).
const LEVER_PATTERN := "^[A-Za-z0-9_/-]{1,128}$"

# Off switch, for a test or a future setting.
var enabled: bool = true
# WHERE A TICKET COMES FROM AND WHERE BODIES GO, as seams for the suite. In the
# game: Api.post, and the local player's own parent (the area's y-sort world).
var request_ticket: Callable
var world_override: Node = null
# And where a message goes: the socket, or (the suite) anything that takes it.
var send_override: Callable = Callable()

var _socket: WebSocketPeer = null
var _phase: String = "off"     # off, ticket, connecting, open, waiting
var _ticket: String = ""
var _url: String = ""
var _my_id: int = -1
var _send_clock: float = 0.0
var _renew_clock: float = 0.0
var _retry_clock: float = 0.0
var _failures: int = 0
var _last_state: Dictionary = {}
var _world: Node = null
var _remotes: Dictionary = {}     # user id -> RemotePlayer
var _sync_pending: bool = false
var _anim_rule: RegEx = RegEx.create_from_string(ANIM_PATTERN)
var _server_shares: bool = false
var _server_books: bool = false
# Whether the server passes on attacks and levers (its welcome's "x").
var _server_relays: bool = false
# Attack pictures waiting for the next send: [kind, ts, ox, oy, tx, ty, delay ms, flags].
var _attacks: Array = []
var _lever_rule: RegEx = RegEx.create_from_string(LEVER_PATTERN)
# The clock this game puts on what it sends, in ms. A seam for the suite.
var clock_override_ms: int = -1
var _lead_area: String = ""
var _leader_id: int = -1
var _lead_sharers: int = 0
# The account meet() is waiting to stand beside, and until when.
var _meet_name: String = ""
var _meet_until_msec: int = 0


func _init() -> void:
	request_ticket = _post_ticket


func _post_ticket(path: String, body: Dictionary) -> Dictionary:
	return await Api.post(path, body)


# =============================================================================
# THE LOOP
# =============================================================================

func _process(delta: float) -> void:
	var player: Node = _local_player()
	if not enabled or player == null or not Api.is_logged_in():
		if _phase != "off":
			stop()
		return
	_follow_world(player)
	match _phase:
		"off":
			_begin()
		"waiting":
			_retry_clock -= delta
			if _retry_clock <= 0.0:
				_phase = "off"
		"connecting", "open":
			_pump(delta, player)
	if _meet_name != "":
		_try_meet(player)


func phase() -> String:
	return _phase


func remotes() -> Dictionary:
	return _remotes


func stop() -> void:
	"""Close the socket and take everybody else off the screen."""
	if _socket != null:
		_socket.close(1000, "leaving")
	_socket = null
	_phase = "off"
	_my_id = -1
	_clear_remotes()
	_lose_lead()


# =============================================================================
# SHARED MONSTERS
# =============================================================================

func shares() -> bool:
	"""True while the link is open to a server that shares monsters."""
	return _phase == "open" and _server_shares and _my_id >= 0


func books() -> bool:
	"""True while the link is open to a server that keeps books on the
	monsters: the leader sends its world even alone, its own hits inside."""
	return shares() and _server_books


func relays() -> bool:
	"""True while the link is open to a server that passes on attacks and
	levers (0.19.0)."""
	return _phase == "open" and _server_relays and _my_id >= 0


func clock_ms() -> int:
	"""This game's clock, as it goes on the wire ("ts")."""
	return clock_override_ms if clock_override_ms >= 0 else Time.get_ticks_msec()


func tell_attack(kind: String, from: Vector2, to: Vector2, delay: float = 0.0, flags: int = 0) -> void:
	"""A picture of an attack this player just made, for everyone else in the
	area (remoteattacks.gd draws it): which kind (RemoteAttacks.KINDS), where
	it starts and where it is aimed, in world positions, how long after now it
	goes (a second meteor, a stick in a bundle) and its rolls. Sent with the
	next state; nothing at all while no server is passing them on."""
	if not relays() or _attacks.size() >= MAX_ATTACKS_PER_SEND:
		return
	_attacks.append([kind, clock_ms(), snappedf(from.x, 0.1), snappedf(from.y, 0.1),
		snappedf(to.x, 0.1), snappedf(to.y, 0.1), clampi(roundi(delay * 1000.0), 0, 3000), flags])


func attacks_queued() -> Array:
	return _attacks


func tell_lever(lever: Node, on: bool) -> void:
	"""This player pulled `lever`: everyone else in the area pulls theirs."""
	var called: String = lever_name(lever)
	if relays() and called != "":
		_send({"t": "l", "n": called, "on": on})


func lever_name(lever: Node) -> String:
	"""What a lever is called on the wire: its path in the scene, which every
	game that loaded the scene has the same - or "" when it has none the
	server would take."""
	var scene: Node = get_tree().current_scene if is_inside_tree() else null
	if scene == null or lever == null or not lever.is_inside_tree() or not scene.is_ancestor_of(lever):
		return ""
	var path: String = String(scene.get_path_to(lever))
	return path if _lever_rule.search(path) != null else ""


func _pull_lever(called: String, on: bool) -> void:
	# Looked for among the levers by name, never by get_node(): the name came
	# over the wire.
	for lever in get_tree().get_nodes_in_group(&"levers"):
		if lever.has_method("follow_pull") and lever_name(lever) == called:
			lever.follow_pull(on)


func renew_soon() -> void:
	"""A fresh ticket now rather than within the minute - after an equip, so
	the server's books hold hits to the weapon in hand."""
	if _phase == "open":
		_renew_clock = RENEW_SECONDS


func my_id() -> int:
	return _my_id


func leader_for(area: String) -> int:
	"""Who leads `area`, as last heard: an account id, -1 for nobody, or -2
	when nothing has been heard about that area since arriving in it."""
	return _leader_id if area != "" and area == _lead_area else -2


func sharers() -> int:
	return _lead_sharers


func send_world(data: Dictionary, to: int = -1) -> void:
	"""(Leader.) The area's monsters, to everyone else in it or to one game."""
	if not shares():
		return
	var message: Dictionary = {"t": "w", "d": data}
	if to >= 0:
		message["to"] = to
	_send(message)


func send_hits(hits: Array) -> void:
	"""(Follower.) Hits for the leader to apply, [[monster, damage, element]]."""
	if not shares() or hits.is_empty():
		return
	_send({"t": "h", "p": hits})


func request_world() -> void:
	"""(Follower.) Ask again for everything: the server tells this game who
	leads and has the leader send it the whole area ("sync")."""
	if _phase == "open":
		_send({"t": "sync"})


func _lose_lead() -> void:
	# THE LINK IS GONE, so nobody leads anything we can hear. Whoever was
	# following takes their monsters back and fights alone, as before 0.7.0.
	var area: String = _lead_area
	var had: bool = _leader_id != -1 or _lead_area != ""
	_lead_area = ""
	_leader_id = -1
	_lead_sharers = 0
	if had:
		lead_changed.emit(area, -1, 0)


func _local_player() -> Node:
	return get_tree().get_first_node_in_group("player") if is_inside_tree() else null


func _begin() -> void:
	_phase = "ticket"
	var res: Dictionary = await request_ticket.call(TICKET_PATH, {"slot": CharacterData.active_character_index})
	if _phase != "ticket":
		return   # stopped while asking
	var data: Dictionary = res.get("data", {}) if res.get("data", {}) is Dictionary else {}
	_ticket = str(data.get("ticket", ""))
	_url = str(data.get("socket_url", ""))
	if not res.get("ok", false) or _ticket == "" or _url == "":
		_wait()
		return
	_socket = WebSocketPeer.new()
	# ROOM FOR A WHOLE AREA. A leader sends a game that walks in every monster
	# it runs at once (Big Field: 128 of them, in parts of 60), and Godot's
	# default buffers are 64 KB each way. A megabyte is a few frames of video.
	_socket.inbound_buffer_size = 1 << 20
	_socket.outbound_buffer_size = 1 << 20
	if _socket.connect_to_url(_url) != OK:
		_socket = null
		_wait()
		return
	_phase = "connecting"


func _wait() -> void:
	_socket = null
	_phase = "waiting"
	_retry_clock = float(RETRY_SECONDS[mini(_failures, RETRY_SECONDS.size() - 1)])
	_failures += 1


func _pump(delta: float, player: Node) -> void:
	_socket.poll()
	var socket_state: int = _socket.get_ready_state()
	if socket_state == WebSocketPeer.STATE_CLOSED:
		if OS.is_debug_build():
			print("[PRESENCE] closed (%d %s)" % [_socket.get_close_code(), _socket.get_close_reason()])
		_clear_remotes()
		_wait()
		_lose_lead()
		return
	if socket_state != WebSocketPeer.STATE_OPEN:
		return
	if _phase == "connecting":
		_phase = "open"
		_failures = 0
		_last_state = {}
		_sync_pending = false
		_renew_clock = 0.0
		_server_shares = false
		_server_books = false
		_server_relays = false
		_attacks = []
		_send({"t": "hello", "ticket": _ticket, "v": SHARED_VERSION})
	while _socket != null and _socket.get_available_packet_count() > 0:
		var parsed: Variant = JSON.parse_string(_socket.get_packet().get_string_from_utf8())
		if parsed is Dictionary:
			handle_message(parsed)
	_send_clock += delta
	if _send_clock >= SEND_SECONDS:
		# ON THE BEAT, not a beat after the frame that crossed it: zeroing it
		# made every send a little late, and the steps went out a tenth and a
		# bit apart against the server's tenth (remoteplayer.gd, PLAYED BACK).
		_send_clock = minf(_send_clock - SEND_SECONDS, SEND_SECONDS)
		send_tick(player)
	_renew_clock += delta
	if _renew_clock >= RENEW_SECONDS:
		_renew_clock = 0.0
		_renew()


func send_tick(player: Node) -> void:
	"""One beat of sending: the state if it changed, the attacks made since the
	last beat, and a sync if one is owed."""
	var now: Dictionary = state_for(player)
	if now != _last_state:
		# The clock goes on the wire and not into the comparison, or every
		# state would be new and a player standing still would send ten.
		var out: Dictionary = now.duplicate()
		out["ts"] = clock_ms()
		_send(out)
		_last_state = now
	# The attacks since the last send, after the state: the server checks each
	# against where the newest state put us.
	if not _attacks.is_empty():
		if relays():
			_send({"t": "x", "e": _attacks})
		_attacks = []
	# AFTER THE STATE, NOT BEFORE: asked first, the server would answer with
	# the area it still had us in, and the new world would be filled with
	# people from the old one.
	if _sync_pending:
		_sync_pending = false
		_send({"t": "sync"})


func _renew() -> void:
	var res: Dictionary = await request_ticket.call(TICKET_PATH, {"slot": CharacterData.active_character_index})
	var data: Dictionary = res.get("data", {}) if res.get("data", {}) is Dictionary else {}
	if _phase == "open" and res.get("ok", false) and str(data.get("ticket", "")) != "":
		_ticket = str(data["ticket"])
		_send({"t": "renew", "ticket": _ticket})


func _send(message: Dictionary) -> void:
	if send_override.is_valid():
		send_override.call(message)
		return
	if _socket != null and _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_socket.send_text(JSON.stringify(message))


# =============================================================================
# WHAT THIS PLAYER IS DOING
# =============================================================================

func state_for(player: Node) -> Dictionary:
	"""The state message for this body: where it is, which animation its sprite
	is playing (only the names the server takes), which aura is lit, which pet
	is out. Positions to a tenth of a pixel, as the server keeps them, so a
	player standing still sends nothing."""
	var sprite: AnimatedSprite2D = player.get_node_or_null("animatedsprite2d") as AnimatedSprite2D
	var anim: String = String(sprite.animation) if sprite != null else ""
	if _anim_rule.search(anim) == null:
		anim = player.get_idle_animation() if player.has_method("get_idle_animation") else "idledown"
		if _anim_rule.search(anim) == null:
			anim = "idledown"
	var fx: Array = []
	for effect in EFFECTS:
		var node: CanvasItem = player.get_node_or_null(effect) as CanvasItem
		if node != null and node.visible:
			fx.append(effect)
	var at: Vector2 = (player as Node2D).global_position if player is Node2D else Vector2.ZERO
	return {
		"t": "s",
		"a": AreaRegistry.current_area_id(),
		"x": snappedf(at.x, 0.1),
		"y": snappedf(at.y, 0.1),
		"m": anim,
		"fx": fx,
		"pet": str(player.get("active_pet_id")) if "active_pet_id" in player else "",
	}


# =============================================================================
# WHAT THE SERVER SAYS
# =============================================================================

func handle_message(message: Dictionary) -> void:
	match str(message.get("t", "")):
		"welcome":
			_my_id = int(message.get("id", -1))
			_server_shares = int(message.get("v", 0)) >= SHARED_MINIMUM
			_server_books = typeof(message.get("books")) == TYPE_BOOL and bool(message["books"])
			_server_relays = int(message.get("x", 0)) >= 1
		"join":
			for entry in message.get("p", []):
				if entry is Dictionary:
					_join(entry)
		"moves":
			for move in message.get("p", []):
				if move is Array and move.size() >= 6:
					_move(move)
		"leave":
			for id in message.get("ids", []):
				_remove(int(id))
		"bye":
			if OS.is_debug_build():
				print("[PRESENCE] the server said goodbye: %s" % str(message.get("why", "")))
		"lead":
			_lead_area = str(message.get("a", ""))
			_leader_id = int(message.get("id", -1))
			_lead_sharers = maxi(int(message.get("n", 0)), 0)
			lead_changed.emit(_lead_area, _leader_id, _lead_sharers)
		"need":
			world_needed.emit(int(message.get("id", -1)))
		"w":
			if message.get("d") is Dictionary:
				world_received.emit(message["d"])
		"h":
			var batch: Variant = message.get("p")
			if batch is Array:
				hits_received.emit(int(message.get("from", -1)), batch)
		"x":
			var found: Variant = _remotes.get(int(message.get("id", -1)))
			if is_instance_valid(found) and message.get("e") is Array:
				(found as Node).hear_attacks(message["e"])
		"l":
			if int(message.get("id", -1)) != _my_id and typeof(message.get("on")) == TYPE_BOOL:
				_pull_lever(str(message.get("n", "")), bool(message["on"]))
		"levers":
			for pulled in message.get("p", []):
				if pulled is Array and pulled.size() == 2 and typeof(pulled[1]) == TYPE_BOOL:
					_pull_lever(str(pulled[0]), bool(pulled[1]))


# =============================================================================
# GOING TO SOMEBODY
# =============================================================================
# The GM panel's "Go to" (0.7.4; the owner, 6 Oct: "Go to lands next to them").
# The server stores which AREA a character is in and nothing finer, so the
# button used to take you to the room's entrance and leave you to find them.
# But this link draws everyone in your area where they stand, so once their
# picture is here, standing beside them is a local move - the same as every
# other move of yourself, with nothing to ask the server.
#
# meet() asks for it once: now, if they are already drawn, or as soon as they
# are - after the change of area the panel starts, which frees the panel, so
# the waiting lives here in the autoload. It gives up after MEET_SECONDS, so a
# meeting that never happens cannot pull you across a room a minute later, and
# says which way it went over your head.

func meet(username: String) -> bool:
	"""Stand beside `username` as soon as their picture is drawn here. True if
	that happened at once."""
	_meet_name = username.strip_edges()
	_meet_until_msec = Time.get_ticks_msec() + int(MEET_SECONDS * 1000.0)
	return _try_meet(_local_player())


func meeting() -> String:
	"""Who meet() is still waiting for, or ""."""
	return _meet_name


func remote_named(username: String) -> Node2D:
	"""The picture of `username` in this area, or null. Account names are unique
	ignoring case, the way the server compares them."""
	var wanted: String = username.strip_edges().to_lower()
	for found in _remotes.values():
		if is_instance_valid(found) and str((found as Node).get("display_name")).to_lower() == wanted:
			return found
	return null


func _try_meet(player: Node) -> bool:
	if _meet_name == "":
		return false
	var me: CharacterBody2D = player as CharacterBody2D
	if Time.get_ticks_msec() > _meet_until_msec:
		if me != null and me.has_method("show_notice"):
			me.show_notice("%s is not here any more - they may have moved on." % _meet_name)
		_meet_name = ""
		return false
	var them: Node2D = remote_named(_meet_name)
	if me == null or them == null or not them.is_inside_tree():
		return false
	# BESIDE, NOT ON: start_ring 1 skips their own spot, as "Bring here" does.
	var spot: Vector2 = SafeSpot.find(me, them.global_position, 1)
	if spot == Vector2.INF:
		spot = them.global_position
	var name_met: String = _meet_name
	_meet_name = ""
	AreaRegistry.place_player(spot)
	if me.has_method("show_notice"):
		me.show_notice("Beside %s." % name_met)
	return true


func _join(entry: Dictionary) -> void:
	var id: int = int(entry.get("id", -1))
	if id < 0 or id == _my_id or _world == null or not is_instance_valid(_world):
		return
	# Untyped until checked: see _remove() for what a freed entry does to a
	# typed variable.
	var found: Variant = _remotes.get(id)
	var body: Node2D = found if is_instance_valid(found) else null
	var at: Vector2 = _local(Vector2(float(entry.get("x", 0.0)), float(entry.get("y", 0.0))))
	var fx: Array = entry.get("fx", []) if entry.get("fx", []) is Array else []
	var ts: int = _clock_of(entry.get("ts", -1))
	if body == null:
		body = RemotePlayer.new()
		body.user_id = id
		_world.add_child(body)
		_remotes[id] = body
		body.set_identity(entry)
		# Doing it before placing it: the playback starts from that step.
		body.set_motion(str(entry.get("m", "idledown")), fx, str(entry.get("pet", "")))
		body.place(at, ts)
	else:
		body.set_identity(entry)
		body.push_step(at, str(entry.get("m", "idledown")), fx, str(entry.get("pet", "")), ts)


func _move(move: Array) -> void:
	var id: int = int(move[0])
	if id == _my_id:
		return
	var found: Variant = _remotes.get(id)
	if not is_instance_valid(found):
		return
	var body: Node2D = found
	# The seventh, their clock, since 0.19.0; a server from before sends six.
	body.push_step(_local(Vector2(float(move[1]), float(move[2]))), str(move[3]),
		move[4] if move[4] is Array else [], str(move[5]), _clock_of(move[6]) if move.size() >= 7 else -1)


static func _clock_of(value: Variant) -> int:
	# A clock from the wire: a whole number of ms, or -1 for none.
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return -1
	return int(value) if float(value) >= 0.0 else -1


func _local(at: Vector2) -> Vector2:
	# THE WIRE CARRIES WORLD POSITIONS (state_for sends global_position) and a
	# body is placed inside the world node, so it is turned into that node's own
	# space. Today the containers sit at the origin and this changes nothing; it
	# is here so that moving one in the editor does not put everybody else a
	# room away from where they stand.
	return (_world as Node2D).to_local(at) if _world is Node2D and _world.is_inside_tree() else at


func _remove(id: int) -> void:
	# UNTYPED ON PURPOSE. When the world goes first - a death sends the game to
	# the game-over screen, freeing every body in it, and the link stops after -
	# the entry is a freed object, and assigning one to a typed variable is a
	# SCRIPT ERROR before is_instance_valid() ever gets to look at it.
	var body: Variant = _remotes.get(id)
	_remotes.erase(id)
	if is_instance_valid(body):
		(body as Node).queue_free()


func _clear_remotes() -> void:
	for id in _remotes.keys():
		_remove(int(id))


func _follow_world(player: Node) -> void:
	# A NEW SCENE IS A NEW WORLD, even in the same area - a revive in town
	# reloads it - and every body drawn in the old one went with it. Forget
	# them, send the state again at once, and ask to be told who is here
	# ("sync"): the server only announces people when somebody changes area.
	var world: Node = world_override if world_override != null else player.get_parent()
	if world == _world:
		return
	_clear_remotes()
	_world = world
	_last_state = {}
	# Attacks made in the old world are no picture of anything in the new one.
	_attacks = []
	_send_clock = SEND_SECONDS
	_sync_pending = _phase == "open"
