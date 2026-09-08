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

# how long to wait before giving up on a request, in seconds.
const TIMEOUT := 10.0

# where the session token is cached between launches
const SESSION_PATH := "user://session.cfg"


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


# =============================================================================
# REQUESTS
# =============================================================================

func get_json(path: String) -> Dictionary:
	return await _request(HTTPClient.METHOD_GET, path, {})


func post(path: String, body: Dictionary) -> Dictionary:
	return await _request(HTTPClient.METHOD_POST, path, body)


func put(path: String, body: Dictionary) -> Dictionary:
	return await _request(HTTPClient.METHOD_PUT, path, body)


func _request(method: int, path: String, body: Dictionary) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT
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
		return _failure(0, "Could not reach the server.")

	# suspends here until the response lands — this is why every caller
	# has to await. result[] is [result, response_code, headers, body].
	var result: Array = await http.request_completed
	http.queue_free()

	var request_result: int = result[0]
	var status: int = result[1]
	var raw_body: PackedByteArray = result[3]

	if request_result != HTTPRequest.RESULT_SUCCESS:
		return _failure(status, _describe_transport_failure(request_result))

	var data: Variant = {}
	if raw_body.size() > 0:
		var parsed: Variant = JSON.parse_string(raw_body.get_string_from_utf8())
		if parsed != null:
			data = parsed

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

	var res := await get_json("/api/auth/session")
	if res.ok:
		username = res.data.get("username", username)
		is_admin = bool(res.data.get("is_admin", false))
		return true

	_clear_session()
	return false


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
