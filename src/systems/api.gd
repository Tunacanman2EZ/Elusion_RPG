# api.gd — HTTP client for the Elusion backend. Registered as an autoload
# so any scene can reach it as `Api`.
#
# WHY THIS EXISTS: every call to the server is asynchronous. Godot's
# HTTPRequest fires a request, then emits request_completed some frames
# later — there is no way to make it return a value inline the way
# LocalStorage.load() does. Rather than sprinkle signal wiring through
# every caller, this wraps the whole dance in a single awaitable method:
#
#     var res := await Api.post("/api/auth/login", {...})
#     if res.ok:
#         print(res.data["token"])
#
# CONCURRENCY: a fresh HTTPRequest node is created per call and freed
# afterwards. Reusing one shared node breaks the moment two systems call
# at once — the second request clobbers the first's in-flight state.
#
# RESULT SHAPE: every method resolves to a Dictionary:
#   ok      bool    — true for 2xx
#   status  int     — HTTP status, or 0 if the request never left the machine
#   data    Variant — parsed JSON body, or {} when there wasn't one
#   error   String  — human-readable reason, "" on success
extends Node


# =============================================================================
# CONFIGURATION
# =============================================================================

# Point this at the Flask dev server while building. Swap to
# "https://www.elusionrpg.com" once it's deployed — nothing else changes.
const BASE_URL := "http://127.0.0.1:5000"

# how long to wait before giving up on a request, in seconds. This is the
# budget for a request the PLAYER ASKED FOR — they pressed Login and are
# watching a spinner, so it is worth waiting out a slow server.
const TIMEOUT := 10.0

# The budget for a request the player did NOT ask for: the startup probe that
# checks whether the server is up and whether a cached token still works.
#
# WHY IT IS SHORTER: nobody is waiting on this on purpose, and until it
# resolves the login screen does not know what to tell the player. Ten seconds
# of "we don't know yet" at the exact moment someone is trying to type their
# password is the worst possible place to spend it.
const PROBE_TIMEOUT := 3.0

# where the session token is cached between launches
const SESSION_PATH := "user://session.cfg"


# =============================================================================
# CONNECTION STATE
# =============================================================================

# Emitted only when reachability actually CHANGES, not on every request — a
# UI listening to this wants to know the moment the world changed, and would
# otherwise get an event per call saying the same thing.
signal connection_changed(online: bool)

# Whether the last request got an answer of ANY kind. A 401 counts as online:
# the question is whether the server is there, not whether it liked us.
#
# Starts false and means "not known to be online yet", which is the honest
# state before the first request rather than an optimistic guess.
var server_online: bool = false

# Whether server_online means anything yet.
#
# WITHOUT THIS, server_online IS AMBIGUOUS: false means both "we asked and it is
# down" and "we have not asked". A caller that skips work when the server is
# down would then skip it forever in a Release build, where nothing probes at
# startup — _log_server_reachability() is debug-only. Kills silently never
# reporting is a far worse bug than the wasted requests this exists to avoid.
var reachability_known: bool = false


func is_known_offline() -> bool:
	# True only when something has actually asked and got no answer.
	return reachability_known and not server_online


# =============================================================================
# SESSION STATE
# =============================================================================

# set by login()/register(), cleared by logout(). the token is the only
# thing that proves who this client is — is_admin and username are
# conveniences echoed by the server, never something we decide locally.
var token: String = ""
var username: String = ""
var is_admin: bool = false


func is_logged_in() -> bool:
	return token != ""


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	_load_session()

	# deliberately NOT awaited. _ready() stays an ordinary function and no
	# other autoload's initialisation waits on a network round trip; the log
	# line just lands a moment later than the rest of the boot output.
	_log_server_reachability()


func _log_server_reachability() -> void:
	# DEBUG ONLY, and purely informational — this never touches token,
	# username or is_admin. resume_session() is the function that judges a
	# cached session and clears it on rejection; this one only reports.
	#
	# WHY IT EXISTS: nothing at boot said whether the server was up. "My save
	# didn't load" and "I lost my character" are nearly always just app.py not
	# running, and there was no way to tell that apart from a real bug without
	# going and checking by hand.
	if not OS.is_debug_build():
		return

	# /api/auth/session is the probe because it already exists, is a GET, and
	# has no side effects. What matters is whether ANY HTTP response comes
	# back — a 401 from a missing or expired token still proves the server is
	# answering. Only status 0 means the request never left the machine.
	#
	# PROBE_TIMEOUT, not TIMEOUT: this is a boot log line. With the server down
	# it used to hold an HTTPRequest node open for ten seconds for the sake of
	# one print statement.
	var res: Dictionary = await get_json("/api/auth/session", PROBE_TIMEOUT)

	if int(res.get("status", 0)) == 0:
		print("[BOOT] Api: OFFLINE at %s — %s" % [BASE_URL, res.get("error", "")])
		return

	var session_note: String = "no cached session"
	if token != "":
		session_note = "cached session valid" if res.get("ok", false) else "cached session REJECTED"
	print("[BOOT] Api: reachable at %s (%s)" % [BASE_URL, session_note])


# =============================================================================
# REQUESTS
# =============================================================================

func get_json(path: String, timeout_override: float = 0.0) -> Dictionary:
	return await _request(HTTPClient.METHOD_GET, path, {}, timeout_override)


func post(path: String, body: Dictionary, timeout_override: float = 0.0) -> Dictionary:
	return await _request(HTTPClient.METHOD_POST, path, body, timeout_override)


func put(path: String, body: Dictionary) -> Dictionary:
	return await _request(HTTPClient.METHOD_PUT, path, body)


func _request(method: int, path: String, body: Dictionary, timeout_override: float = 0.0) -> Dictionary:
	var http := HTTPRequest.new()
	# 0.0 means "use the normal budget" rather than "no timeout" — an explicit
	# zero on HTTPRequest.timeout disables the timeout entirely, which is the
	# opposite of what a caller passing a smaller number wants.
	http.timeout = timeout_override if timeout_override > 0.0 else TIMEOUT
	add_child(http)

	var headers := PackedStringArray(["Content-Type: application/json"])
	if token != "":
		headers.append("Authorization: Bearer " + token)

	var payload := ""
	if not body.is_empty():
		payload = JSON.stringify(body)

	var err := http.request(BASE_URL + path, headers, method, payload)
	if err != OK:
		http.queue_free()
		_set_online(false)
		return _failure(0, "Could not reach the server.")

	# suspends here until the response lands — this is why every caller
	# has to await. result[] is [result, response_code, headers, body].
	var result: Array = await http.request_completed
	http.queue_free()

	var request_result: int = result[0]
	var status: int = result[1]
	var raw_body: PackedByteArray = result[3]

	if request_result != HTTPRequest.RESULT_SUCCESS:
		# A transport failure means no answer came back, so the server is not
		# reachable — whatever `status` says (it is 0 in this branch anyway).
		_set_online(false)
		return _failure(status, _describe_transport_failure(request_result))

	# Any HTTP status at all proves something is listening and answering. A
	# 401 or a 500 is still a server. This is the single place reachability is
	# decided, so every call in the game keeps it current for free.
	_set_online(true)

	var data: Variant = {}
	if raw_body.size() > 0:
		# JSON.new().parse(), NOT JSON.parse_string().
		#
		# They do the same job, but the static helper PUSHES AN ENGINE ERROR on
		# malformed input — and a server that returns a non-JSON body is an
		# ordinary thing, not a client bug. Flask in debug mode answers a 500
		# with an HTML traceback page, and every one of those produced a red
		# "Parse JSON failed. Error at line 0: Unexpected character" in the
		# Godot console, on top of the real error the response already carried.
		#
		# The instance form returns an error code and says nothing. The branch
		# below was already correct; it just could not stop the engine shouting
		# first.
		var json := JSON.new()
		if json.parse(raw_body.get_string_from_utf8()) == OK:
			data = json.data

	if status >= 200 and status < 300:
		return {"ok": true, "status": status, "data": data, "error": ""}

	return {
		"ok": false,
		"status": status,
		"data": data,
		"error": _describe_api_error(data, status),
	}


# =============================================================================
# AUTH
# =============================================================================

func login(user: String, password: String) -> Dictionary:
	var res := await post("/api/auth/login", {"username": user, "password": password})
	if res.ok:
		_adopt_session(res.data)
	return res


func register(user: String, password: String) -> Dictionary:
	var res := await post("/api/auth/register", {"username": user, "password": password})
	if res.ok:
		_adopt_session(res.data)
	return res


func logout() -> void:
	# tell the server to invalidate the token, but clear locally regardless
	# — a failed call shouldn't strand the player in a logged-in state.
	if token != "":
		await post("/api/auth/logout", {})
	_clear_session()


func resume_session() -> bool:
	# called at startup when a cached token exists. returns true if the
	# server still accepts it, false if it expired or was revoked.
	if token == "":
		return false
	var probe: Dictionary = await probe_and_resume()
	return bool(probe.get("resumed", false))


func probe_and_resume() -> Dictionary:
	# ONE round trip that answers both questions the login screen has at
	# startup: is the server answering at all, and is the cached token still
	# good? Returns {"online": bool, "resumed": bool}.
	#
	# WHY THIS EXISTS: the login screen used to ask those separately, and with
	# the server down each question spent its own full timeout, in series,
	# while the form sat disabled. Both answers come out of the same response,
	# so there was never a reason to pay twice.
	#
	# "online" is deliberately independent of "resumed". A rejected token on a
	# healthy server is not a connection problem, and telling the player it is
	# would send them off to check their internet over an expired login.
	var res: Dictionary = await get_json("/api/auth/session", PROBE_TIMEOUT)

	if int(res.get("status", 0)) == 0:
		return {"online": false, "resumed": false}

	if token == "":
		return {"online": true, "resumed": false}

	if res.get("ok", false):
		username = res.data.get("username", username)
		is_admin = bool(res.data.get("is_admin", false))
		return {"online": true, "resumed": true}

	# Reached the server and it said no — the token expired or was revoked.
	_clear_session()
	return {"online": true, "resumed": false}


# =============================================================================
# SESSION PERSISTENCE
# =============================================================================

func _adopt_session(data: Dictionary) -> void:
	token = data.get("token", "")
	username = data.get("username", "")
	# register() doesn't echo is_admin — a brand new account never has it.
	is_admin = bool(data.get("is_admin", false))
	_save_session()


func _clear_session() -> void:
	token = ""
	username = ""
	is_admin = false
	DirAccess.remove_absolute(SESSION_PATH)


func _save_session() -> void:
	var config := ConfigFile.new()
	config.set_value("session", "token", token)
	config.set_value("session", "username", username)
	config.save(SESSION_PATH)


func _load_session() -> void:
	var config := ConfigFile.new()
	if config.load(SESSION_PATH) != OK:
		return
	token = config.get_value("session", "token", "")
	username = config.get_value("session", "username", "")


# =============================================================================
# CONNECTION TRACKING
# =============================================================================

func _set_online(state: bool) -> void:
	# Emits only on a real change. Without the early return every request in
	# the game would fire a connection_changed carrying the same value it
	# already had, and any listener that does real work on it — a banner
	# animation, a reconnect attempt — would run on every call.
	# Set even when the state has not changed: the first ANSWER is what makes
	# the flag meaningful, and the first answer is very often "still false".
	reachability_known = true

	if server_online == state:
		return
	server_online = state
	connection_changed.emit(state)


func describe_offline() -> String:
	# The player-facing reason the game can't reach the server. Kept here
	# rather than in the login screen because every screen that needs to say
	# it should say the same thing.
	#
	# Debug builds name the address, because when it's you it is almost always
	# app.py not running and the URL is the fastest way to confirm that. A
	# shipped build must never show a player a localhost address — it tells
	# them nothing and looks broken.
	if OS.is_debug_build():
		return "No connection — nothing answering at %s. Is app.py running?" % BASE_URL
	return "Can't reach the Elusion server. Check your connection and try again."


# =============================================================================
# ERROR MESSAGES
# =============================================================================

func _failure(status: int, message: String) -> Dictionary:
	return {"ok": false, "status": status, "data": {}, "error": message}


func _describe_transport_failure(request_result: int) -> String:
	# these are connection-level problems — the request never got an answer,
	# so there's no server message to show. the most common one by far is
	# "you forgot to start app.py".
	match request_result:
		HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CANT_RESOLVE:
			return "Can't reach the server. Is it running?"
		HTTPRequest.RESULT_TIMEOUT:
			return "The server took too long to respond."
		_:
			return "Connection failed."


func _describe_api_error(data: Variant, status: int) -> String:
	# the Flask side returns {"error": "...", "message": "..." | [...]}.
	# validation errors come back as an array of strings; everything else
	# is a single string.
	if data is Dictionary:
		var message: Variant = data.get("message")
		if message is Array and not message.is_empty():
			return str(message[0])
		if message is String and message != "":
			return message

	return "Something went wrong (HTTP %d)." % status
