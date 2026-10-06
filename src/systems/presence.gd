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
# Each game still fights its own enemies: a player swinging at nothing is
# swinging at a monster in their own world. This is presence, not combat.
extends Node

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

# Off switch, for a test or a future setting.
var enabled: bool = true
# WHERE A TICKET COMES FROM AND WHERE BODIES GO, as seams for the suite. In the
# game: Api.post, and the local player's own parent (the area's y-sort world).
var request_ticket: Callable
var world_override: Node = null

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
		return
	if socket_state != WebSocketPeer.STATE_OPEN:
		return
	if _phase == "connecting":
		_phase = "open"
		_failures = 0
		_last_state = {}
		_sync_pending = false
		_renew_clock = 0.0
		_send({"t": "hello", "ticket": _ticket})
	while _socket != null and _socket.get_available_packet_count() > 0:
		var parsed: Variant = JSON.parse_string(_socket.get_packet().get_string_from_utf8())
		if parsed is Dictionary:
			handle_message(parsed)
	_send_clock += delta
	if _send_clock >= SEND_SECONDS:
		_send_clock = 0.0
		var now: Dictionary = state_for(player)
		if now != _last_state:
			_send(now)
			_last_state = now
		# AFTER THE STATE, NOT BEFORE: asked first, the server would answer
		# with the area it still had us in, and the new world would be filled
		# with people from the old one.
		if _sync_pending:
			_sync_pending = false
			_send({"t": "sync"})
	_renew_clock += delta
	if _renew_clock >= RENEW_SECONDS:
		_renew_clock = 0.0
		_renew()


func _renew() -> void:
	var res: Dictionary = await request_ticket.call(TICKET_PATH, {"slot": CharacterData.active_character_index})
	var data: Dictionary = res.get("data", {}) if res.get("data", {}) is Dictionary else {}
	if _phase == "open" and res.get("ok", false) and str(data.get("ticket", "")) != "":
		_ticket = str(data["ticket"])
		_send({"t": "renew", "ticket": _ticket})


func _send(message: Dictionary) -> void:
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


func _join(entry: Dictionary) -> void:
	var id: int = int(entry.get("id", -1))
	if id < 0 or id == _my_id or _world == null or not is_instance_valid(_world):
		return
	var body: Node2D = _remotes.get(id)
	var at: Vector2 = _local(Vector2(float(entry.get("x", 0.0)), float(entry.get("y", 0.0))))
	if body == null or not is_instance_valid(body):
		body = RemotePlayer.new()
		body.user_id = id
		_world.add_child(body)
		_remotes[id] = body
		body.set_identity(entry)
		body.place(at)
	else:
		body.set_identity(entry)
		body.set_target(at)
	var fx: Array = entry.get("fx", []) if entry.get("fx", []) is Array else []
	body.set_motion(str(entry.get("m", "idledown")), fx, str(entry.get("pet", "")))


func _move(move: Array) -> void:
	var id: int = int(move[0])
	if id == _my_id:
		return
	var body: Node2D = _remotes.get(id)
	if body == null or not is_instance_valid(body):
		return
	body.set_target(_local(Vector2(float(move[1]), float(move[2]))))
	body.set_motion(str(move[3]), move[4] if move[4] is Array else [], str(move[5]))


func _local(at: Vector2) -> Vector2:
	# THE WIRE CARRIES WORLD POSITIONS (state_for sends global_position) and a
	# body is placed inside the world node, so it is turned into that node's own
	# space. Today the containers sit at the origin and this changes nothing; it
	# is here so that moving one in the editor does not put everybody else a
	# room away from where they stand.
	return (_world as Node2D).to_local(at) if _world is Node2D and _world.is_inside_tree() else at


func _remove(id: int) -> void:
	var body: Node = _remotes.get(id)
	_remotes.erase(id)
	if body != null and is_instance_valid(body):
		body.queue_free()


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
	_send_clock = SEND_SECONDS
	_sync_pending = _phase == "open"
