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

# WHERE THE SERVER IS. Resolved once at startup, in this order:
#
#   1. --server=https://host  on the command line
#   2. ELUSION_SERVER         in the environment
#   3. user://server.cfg      a one-line override beside the save data
#   4. DEFAULT_BASE_URL       the local dev server
#
# IT USED TO BE A `const`, AND THAT WAS A SHIPPING BUG WAITING TO HAPPEN. A
# const cannot be changed without a rebuild, so an exported build carried
# "127.0.0.1" with it: every player who ran it would have the client quietly
# try THEIR OWN machine, find nothing, and show "can't reach the server" with
# no hint that the address was the problem. The one thing that must differ
# between a dev run and a real build was the one thing that could not.
#
# THE FILE OVERRIDE IS THE IMPORTANT ONE. Command line and environment are for
# development; user://server.cfg is how an already-exported build gets pointed
# somewhere new - moving host, or standing up a test server - without asking
# anyone to rebuild or reinstall. It holds the URL and nothing else.
const DEFAULT_BASE_URL := "http://127.0.0.1:5000"
const SERVER_OVERRIDE_FILE := "user://server.cfg"

static var BASE_URL: String = DEFAULT_BASE_URL


static func _resolve_base_url() -> String:
	for argument in OS.get_cmdline_args():
		if argument.begins_with("--server="):
			# CHECKED LIKE THE OTHER TWO. A bare `--server=` with nothing after
			# it used to return "" straight out of here, which is the one
			# outcome this whole function must not produce: an empty BASE_URL
			# makes every request a malformed address, and the game reports it
			# as "cannot reach the server" rather than as a bad argument.
			var from_args: String = argument.substr("--server=".length()).strip_edges()
			if from_args != "":
				return _clean_base_url(from_args)

	var from_env: String = OS.get_environment("ELUSION_SERVER").strip_edges()
	if from_env != "":
		return _clean_base_url(from_env)

	if FileAccess.file_exists(SERVER_OVERRIDE_FILE):
		var handle := FileAccess.open(SERVER_OVERRIDE_FILE, FileAccess.READ)
		if handle != null:
			var line: String = handle.get_line().strip_edges()
			handle.close()
			# A blank or commented file means "no override" rather than an empty
			# URL - an empty BASE_URL would make every request fail with a
			# malformed address instead of falling back to the default.
			if line != "" and not line.begins_with("#"):
				return _clean_base_url(line)

	return DEFAULT_BASE_URL


static func _clean_base_url(raw: String) -> String:
	"""Normalise an override, or refuse it and fall back.

	TWO MISTAKES THAT LOOK LIKE AN OUTAGE. Both produce a client that cannot
	reach anything while reporting only that the server is down, so both are
	worth catching where the value enters rather than where a request fails.

	A MISSING SCHEME - `--server=example.com` - is not a URL HTTPRequest can
	use, and the failure surfaces as a connection error indistinguishable from
	the host being offline. Refused, with a line saying why, and the default
	kept so the game still starts.

	A TRAILING SLASH is harmless-looking and produces `https://host//api/...`
	on every call, because every path in this file already begins with one.
	Most servers forgive it; a proxy matching on exact paths may not.
	"""
	var url: String = raw.strip_edges()
	while url.ends_with("/"):
		url = url.substr(0, url.length() - 1)

	if not (url.begins_with("http://") or url.begins_with("https://")):
		push_warning("Api: ignoring server override %s - it needs http:// or https://" % raw)
		print("[BOOT] Api: ignoring server override %s (no scheme); using %s"
			% [raw, DEFAULT_BASE_URL])
		return DEFAULT_BASE_URL

	return url

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

# HOW OFTEN THE GAME TELLS THE SERVER IT IS STILL HERE, while a character is in
# the world. characterhud.gd owns the timer; this is the one statement of the
# number. It pairs with ONLINE_WINDOW_SECONDS = 45 in app.py - three beats - so
# one slow request does not show a player as gone.
#
# It is also how a kick lands. See heartbeat().
const HEARTBEAT_SECONDS := 15.0


# =============================================================================
# CONNECTION STATE
# =============================================================================

# Emitted only when reachability actually CHANGES, not on every request — a
# UI listening to this wants to know the moment the world changed, and would
# otherwise get an event per call saying the same thing.
signal connection_changed(online: bool)

# An authenticated request came back 401 while this client held a token.
#
# NOT PROOF THE SESSION IS GONE, and nothing should act on it alone: changing a
# password answers 401 for a mistyped CURRENT password, and signing out a
# player for a typo would be absurd. It means "ask now rather than in up to
# fifteen seconds" - characterhud.gd answers it with an immediate heartbeat(),
# and heartbeat() is what decides.
signal unauthorized_seen

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

# set by login()/register(), cleared by logout(). the token is the only thing
# that proves who this client is — username and role are conveniences echoed by
# the server, never something we decide locally.
var token: String = ""
var username: String = ""

# Whether this account is the server's OWNER, as the server understands it.
#
# Held only in memory and never written to session.cfg. A permission that lives
# in a file is a permission that can be edited; this one has to come from a
# login response every time.
#
# It is still only good for hiding buttons. The server decides for real - see
# require_owner in app.py.
var is_owner: bool = false

# This account's rank, as the server understands it. The chain of command runs
# owner > dev > mod > player, and there is no fifth rank. Same rules as is_owner
# - memory only, re-read on every login and resume, never written to
# session.cfg.
var role: String = "player"

# What the login screen should say when the game was signed out FROM THE
# SERVER'S SIDE - a kick, a ban, or a login that simply ran out. Set by
# forget_session(), shown once by loginmenu.gd, and cleared there.
var signout_notice: String = ""


# The rank the in-game debug shortcuts require. Defined here rather than in
# player.gd so there is ONE statement of the policy - the test suite asserts
# against this constant, and a rule with two copies is a rule that drifts.
#
# Pets, gear, lusions and skill XP are things a player earns. Staff get the
# shortcut because staff have to test what players do the slow way.
const DEBUG_KEYS_MIN_ROLE := "mod"


func role_at_least(minimum: String) -> bool:
	# Mirrors role_at_least() in app.py, and for the same reason: "mod or
	# above" should be one comparison rather than an expression repeated at
	# every call site.
	#
	# An unrecognised rank sorts as the LOWEST, never the highest. A response
	# from a newer server naming a rank this build has never heard of must not
	# be read as more privilege than the player has.
	var order: PackedStringArray = ["player", "mod", "dev", "owner"]
	var mine: int = order.find(role)
	var needed: int = order.find(minimum)
	if mine < 0 or needed < 0:
		return false
	return mine >= needed


func is_logged_in() -> bool:
	return token != ""


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# Resolved before anything can make a request. Printed because a client
	# pointed at the wrong server looks exactly like a server that is down.
	BASE_URL = _resolve_base_url()
	if BASE_URL != DEFAULT_BASE_URL:
		print("[BOOT] Api: server override in effect — %s" % BASE_URL)
	_load_session()

	# deliberately NOT awaited. _ready() stays an ordinary function and no
	# other autoload's initialisation waits on a network round trip; the log
	# line just lands a moment later than the rest of the boot output.
	_log_server_reachability()


func _log_server_reachability() -> void:
	# DEBUG ONLY, and purely informational — this never touches token,
	# username or role. probe_and_resume() is the function that judges a
	# cached session and clears it on rejection; this one only reports.
	#
	# WHY IT EXISTS: nothing at boot said whether the server was up. "My save
	# didn't load" and "I lost my character" are nearly always just app.py not
	# running, and there was no way to tell that apart from a real bug without
	# going and checking by hand.
	if not OS.is_debug_build():
		return

	# AND NOT IN A HEADLESS RUN, which in this project means testrunner.gd and
	# nothing else.
	#
	# _ready() deliberately does not await this, so the probe OUTLIVES ITS
	# CALLER: a suspended coroutine holding an HTTPRequest. The suite finishes in
	# well under a second and calls quit() while the probe is still sitting on
	# its three second timeout, so the engine tears down with a live
	# GDScriptFunctionState and prints "ObjectDB instances leaked at exit" on
	# every green run. That was the warning exactly - one leaked instance, and
	# orphan StringNames get_json, request_completed and completed.
	#
	# THE WARNING IS THE SMALL HALF. A test suite that makes a network call at
	# startup can behave differently depending on whether Flask happens to be
	# running on the machine, and that is a dependency nobody would ever think to
	# go looking for. It has been there since the suite was written and could not
	# be noticed, because the suite had never once run.
	#
	# A boot log line exists for somebody watching a console. Nothing watches a
	# headless run except a script reading the exit code.
	if DisplayServer.get_name() == "headless":
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
	var status: int = int(res.get("status", 0))

	if status == 0:
		print("[BOOT] Api: OFFLINE at %s — %s" % [BASE_URL, res.get("error", "")])
		return

	# ANSWERING IS NOT THE SAME AS BEING OURS, and this line used to conflate
	# them. "What matters is whether ANY HTTP response comes back" is true for
	# the question "is something listening" and false for the question the
	# player actually has, which is "why can I not log in".
	#
	# THE CASE IT COST AN EVENING. Flask's app.run() defaults to port 5000 and
	# so does DEFAULT_BASE_URL, so any other Flask project on this machine
	# takes the port Elusion wants. It then answers 404 to every path here -
	# which is an HTTP response, so this printed "reachable", and the 404 is
	# not a 2xx, so it also printed "cached session REJECTED". Both lines were
	# true and the conclusion they invited - "the server is up, my account is
	# broken" - was exactly wrong.
	#
	# 404 IS UNAMBIGUOUS. This endpoint exists on every version of the server
	# and answers 401 without a token, never 404. A 404 here means whatever
	# holds this port is not Elusion. 405 means the same thing from a server
	# that has the path but not the method.
	if status == 404 or status == 405:
		print("[BOOT] Api: WRONG SERVER at %s" % BASE_URL)
		print("       Something is listening there and it is not Elusion: HTTP %d"
			% status)
		print("       on /api/auth/session, a route this server always answers.")
		print("       Flask's app.run() defaults to port 5000 and so does this")
		print("       client, so another project of yours has probably taken it.")
		print("       Stop that one, or move Elusion with --server=,")
		print("       ELUSION_SERVER, or user://server.cfg.")
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
	# Remembered, because the answer is only about THIS token. A logout and a
	# fresh login can both happen while a slow request is in flight, and a 401
	# for the old token says nothing about the new one.
	var sent_token: String = token
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

	# See unauthorized_seen. The heartbeat's own path is excluded because
	# heartbeat() is already the thing deciding - announcing its answer back to
	# the listener that asked for it would just ask again.
	if status == 401 and sent_token != "" and sent_token == token \
			and path != "/api/auth/session":
		unauthorized_seen.emit()

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
		is_owner = bool(res.data.get("is_owner", false))
		role = str(res.data.get("role", "player"))
		return {"online": true, "resumed": true}

	# Reached the server and it said no — the token expired or was revoked.
	_clear_session()
	return {"online": true, "resumed": false}


func heartbeat() -> String:
	# "I am still here" - see HEARTBEAT_SECONDS. Resolves to one of:
	#
	#   "ok"        the session is live. Rank is re-read on the way through, so
	#               a promotion or demotion reaches the HUD within one beat.
	#   "revoked"   the server has no such session: kicked, banned, or expired.
	#   "offline"   no verdict. Nothing about the login is known.
	#   "stale"     the token changed while this was in flight. Ignore it.
	#   "none"      there is no login to check - a scene run straight from
	#               the editor, say. Nothing to sign out of, so nothing happens.
	#
	# A kick deletes the player's sessions and a ban does too, but a client
	# that never asks never finds out - which is how a kicked player used to go
	# on playing until they happened to restart. This is the asking.
	if token == "":
		return "none"
	var asked_with: String = token
	var res: Dictionary = await get_json("/api/auth/session", PROBE_TIMEOUT)
	if token != asked_with:
		return "stale"
	var verdict: String = heartbeat_verdict(res)
	if verdict == "ok" and res.get("data") is Dictionary:
		role = str(res.data.get("role", role))
		is_owner = bool(res.data.get("is_owner", is_owner))
	return verdict


func heartbeat_verdict(res: Dictionary) -> String:
	# The judgement on its own, so the test suite can pin it without a server.
	# Not static: Api is reached as an autoload instance, and calling a static
	# function through an instance is a warning in the editor.
	#
	# ONLY A 401 SIGNS ANYONE OUT. Everything else that is not a success - no
	# answer, a 500, a 404 from some other program holding the port - says
	# nothing about whether this login is valid. Throwing a player to the
	# login screen because the server hiccuped would turn every restart of
	# app.py into a mass kick.
	if res.get("ok", false):
		return "ok"
	if int(res.get("status", 0)) == 401:
		return "revoked"
	return "offline"


func forget_session(notice: String) -> void:
	# The server already ended this session, so there is nobody to tell -
	# Api.logout() would spend a request on a token that no longer exists.
	# Keep the reason for the login screen and drop the token.
	signout_notice = notice
	_clear_session()


# =============================================================================
# SESSION PERSISTENCE
# =============================================================================

func _adopt_session(data: Dictionary) -> void:
	token = data.get("token", "")
	username = data.get("username", "")
	is_owner = bool(data.get("is_owner", false))
	role = str(data.get("role", "player"))

	# _save_session() writes the token and username only. is_owner is
	# deliberately not among them — it is re-read from the server on every
	# login and resume, so there is nothing on disk to tamper with.
	_save_session()


func _clear_session() -> void:
	token = ""
	username = ""
	is_owner = false
	role = "player"
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

	# NO PARSEABLE MESSAGE, and for 404 that is itself the diagnosis - but it
	# narrows to TWO things, not one, and the first version named only the
	# second of them.
	#
	# Every 404 this server raises on purpose - an unknown account, a staff
	# route hiding from a non-staff caller - carries {"error", "message"} and
	# is answered above. Reaching here with a 404 means the body was HTML,
	# which our error handler never produces and Flask's own unknown-route
	# page always does. So: SOME Flask app answered, and it has no such route.
	#
	# THAT IS EITHER A STALE SERVER OR A DIFFERENT ONE, and the mechanism
	# cannot tell them apart because they produce the identical response.
	#
	#   stale     the route was added and the process was not restarted. The
	#             overwhelmingly common one in development, and the only one
	#             with a fix the reader can act on in five seconds.
	#   different Flask's app.run() defaults to 5000 and so does this client,
	#             so any other Flask project on this machine takes the port.
	#
	# THE FIRST VERSION ASSERTED THE SECOND and cost real confusion: a new
	# endpoint went in, the server was not restarted, and the client announced
	# that something else had taken the port. A diagnostic that names one cause
	# out of two is worse than one that names both - it does not merely fail to
	# help, it sends the reader somewhere.
	#
	# Ordered by likelihood, because a message is read top-down and the first
	# line is the one that gets acted on.
	if status == 404:
		return ("%s has no such route. If you just added it, restart the "
			+ "server — otherwise another local Flask project may have taken "
			+ "the port.") % BASE_URL

	return "Something went wrong (HTTP %d)." % status
