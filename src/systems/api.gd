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
# CONCURRENCY: on the desktop, every JSON request goes through _pool (see
# connectionpool.gd), which keeps up to six connections open and reuses them,
# one request at a time each. In a browser, and for pictures, a fresh
# HTTPRequest node is created per call and freed afterwards. Reusing one shared
# node breaks the moment two systems call at once — the second request
# clobbers the first's in-flight state.
#
# RESULT SHAPE: every method resolves to a Dictionary:
#   ok      bool    — true for 2xx
#   status  int     — HTTP status, or 0 if the request never left the machine
#   data    Variant — parsed JSON body, or {} when there wasn't one
#   error   String  — human-readable reason, "" on success
extends Node

const ConnectionPool := preload("res://src/systems/connectionpool.gd")


# =============================================================================
# CONFIGURATION
# =============================================================================

# WHERE THE SERVER IS. Resolved once at startup, in this order:
#
#   0. the page's own address, in a browser build - and nothing else there
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

const WebPage := preload("res://src/systems/webpage.gd")

# WHICH BUILD THIS IS, stamped on every request.
#
# THE SERVER COULD NOT TELL ONE BUILD FROM ANOTHER BEFORE THIS. It could not
# refuse a build with a known bug, could not ask a player to update, and - the
# worst of the three - a change to the wire did not FAIL on an old build, it
# half-worked. Quietly, on exactly the copies nobody can reach.
#
# IT HAD TO SHIP WITH THE FIRST BUILD OR NEVER COVER IT. The header can be
# added at any time and its absence read as "from before this existed", which
# works - but every copy released before then is permanently in that bucket,
# and it is the oldest code, which is the code most worth being able to reason
# about.
#
# MONOTONIC INTEGER, NOT A VERSION STRING. The only question the server asks is
# "older than", and integers answer it without a parser. DISPLAY_VERSION is for
# humans and the server never reads it - so the two can be renumbered
# independently and neither can break the other.
#
# RAISE THIS WHENEVER THE WIRE CHANGES, not on every build. It is what the
# server compares against, so a number that moves for cosmetic reasons makes
# the minimum meaningless.
#
# 2: the backpack and the bank became the server's - drags, the bin and piles
# are requests, and a save carries no bag - and logins send an install id.
# 3: dropped gear carries its quality roll in its item id ("ironsword~d107"),
# which ItemRegistry reads; a build-2 game shows such a piece as the error item.
# 4: armour's roll ends in the element it resists ("jadechest~a104h96r605",
# GameConstants.RESIST_*); a build-3 game reads such an id as a malformed roll.
# Matches CURRENT_CLIENT_BUILD in app.py.
const BUILD := 4
# MAJOR.MINOR.PATCH: 0.x until launch, the middle number for a new chunk of
# the game, the last for fixes. Shown on the login screen and under Menu
# (GameConstants.version_text()), and the Windows export's file version is it
# with .0 after. CLAUDE.md, "The version", says when each number moves.
const DISPLAY_VERSION := "0.16.0"

# The header the build rides on. Matches CLIENT_BUILD_HEADER in app.py, and
# that is a contract: renaming one without the other disables the gate silently,
# because an absent header reads as a very old client and the server is not
# refusing anybody by default.
const BUILD_HEADER := "X-Elusion-Build"

static var BASE_URL: String = DEFAULT_BASE_URL

# WHAT THE SERVER SAID ABOUT BUILDS, last time anything asked /api/status.
#
# -1 MEANS "NOT ASKED YET" rather than 0, because 0 is a real answer from the
# server meaning "the gate is off". A client that treated "no answer" as "gate
# off" would look identical to one that had checked, which is the difference
# between knowing and assuming.
static var server_min_build: int = -1
static var server_current_build: int = -1


static func clean_password(text: String) -> String:
	"""THE ONE RULE FOR A PASSWORD FIELD: surrounding spaces are not part of it.

	The login screen always trimmed, and the server never does - so the login
	screen's rule IS the rule for every account made there. Options (change
	password, confirm email) and account recovery sent what was typed as it
	was, so a new password set there with a trailing space was stored with it,
	and the login screen could never send it again: 401, then 409 from the
	register attempt, then "Incorrect password." on a password the player had
	typed correctly. Every password field goes through this now."""
	return text.strip_edges()


static func build_is_outdated() -> bool:
	"""True when the server knows of a newer build than this one.

	NOT THE SAME QUESTION AS "will I be refused". The refusal threshold is
	server_min_build; this is server_current_build, which is only "there is
	something newer". They are deliberately separate so the client can say
	"an update is available" long before the day anything is turned away -
	which is the whole value of shipping the gate disarmed."""
	return server_current_build > BUILD


static func build_is_refused() -> bool:
	"""True when this build is below the server's minimum and will be refused."""
	return server_min_build > 0 and BUILD < server_min_build


static func no_answer_text() -> String:
	"""The line for a request nothing answered.

	"Is it running?" is a question for whoever runs the server, and it was the
	sentence every player got - in chat, friends, guilds and the transport
	error below. A debug build keeps it, because there it is almost always you
	and app.py; a shipped one says something a player can act on."""
	if OS.is_debug_build():
		return "No answer from the server. Is it running?"
	return "No answer from the server. Try again in a moment."


static func build_notice() -> String:
	"""What the login screen says about this build, or "" when it is current.

	THE TWO FUNCTIONS ABOVE HAD NO CALLER. Their docstring says the gate ships
	disarmed so the client can say "an update is available" long before
	anything is turned away - and nothing said it. refresh_build_info() fetched
	both numbers on every login screen and nothing read server_current_build.

	A browser build updates by being reloaded, so it says that instead of
	asking for a download."""
	var how: String = "Refresh the page to update." if OS.has_feature("web") \
		else "Please update to keep playing."
	if build_is_refused():
		return "This version of the game is too old to connect. " + how
	if build_is_outdated():
		return "A newer version of the game is out. " + how.replace("to keep playing", "when you can")
	return ""


static func _resolve_base_url() -> String:
	# A BROWSER BUILD TALKS TO THE ADDRESS IT WAS LOADED FROM. The API sends no
	# cross-site headers, so a browser refuses any other address - it was
	# measured doing exactly that to 127.0.0.1:5000 from a page on :8061. The
	# site serves the game and passes /api/ to the server (DEPLOY.md in the API
	# repository), which makes the page's origin the one address that works.
	# No override is read there: none of the three can name a working address.
	if OS.has_feature("web"):
		var from_page: String = web_base_url(WebPage.origin())
		if from_page != "":
			return from_page

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


static func web_base_url(origin: String) -> String:
	"""The API address for a page served from `origin`, or "" for none.

	window.location.origin is the string "null" for a page opened from disk,
	and the engine cannot start from one anyway; only http(s) is an answer."""
	var cleaned: String = origin.strip_edges()
	if not (cleaned.begins_with("https://") or cleaned.begins_with("http://")):
		return ""
	return _clean_base_url(cleaned)


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


# WHO THIS CLIENT IS, whenever that changes: a login, a resume, a signout, or a
# promotion that arrived on a heartbeat.
#
# WHY A SIGNAL AND NOT A POLL. Rank is re-read every 15 seconds and changes
# almost never, so anything that paints it - the nameplate over the player's
# head, the colour of their name in chat - would otherwise have to check a
# string it already knows on a timer of its own, forever, to catch an event
# that happens once. Listeners connect once and are told.
signal identity_changed(new_username: String, new_role: String)

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

# Whether this account still owes us a confirmed recovery address.
#
# Held in memory only, like is_owner and role, and re-read from the server on
# every login, register and resume. It is a PROMPT, not a permission - the
# server never refuses anything because of it, it simply keeps answering
# "true" until an address has been confirmed, and the login screen keeps
# asking. Nothing on disk has a say.
var needs_email: bool = false

# A staff account the server let in on its password alone, because there was
# nowhere to send a login code: no confirmed address, or no mail on the server
# (STAFF LOGIN CODES in app.py). Memory only, re-read on every login. The HUD
# says so once per login; _told_staff_unprotected is what makes it once.
var staff_unprotected: bool = false
var _told_staff_unprotected: bool = false

# This account's rank, as the server understands it. The chain of command runs
# owner > dev > mod > player, and there is no fifth rank. Same rules as is_owner
# - memory only, re-read on every login and resume, never written to
# session.cfg.
var role: String = "player"

# What the login screen should say when the game was signed out FROM THE
# SERVER'S SIDE - a kick, a ban, or a login that simply ran out. Set by
# forget_session(), shown once by loginmenu.gd, and cleared there.
var signout_notice: String = ""

# "REMEMBER ME", AND WHAT IT HAS TO MEAN. The login screen sets this from its
# checkbox before signing in; a token loaded from disk sets it too, since only a
# remembered login is ever written there.
#
# Off, the token lives in memory only and session.cfg is removed - so closing
# the game signs you out. It used to be written either way, and the box only
# decided whether the NAME was filled in: on a school or library computer the
# next person to open the game walked straight into your account.
var keep_signed_in: bool = false

# The last 401 heartbeat() was given, so the screen that acts on it can say WHY
# - see signout_notice_for().
var last_refusal: Dictionary = {}

const SIGNED_OUT_NOTICE := "You were signed out by the server."
const SIGNED_IN_ELSEWHERE_NOTICE := "This account signed in somewhere else, so this game was signed out."


# The rank god mode requires. ONE statement of the policy, asserted by the
# suite, rather than a copy in player.gd and another in ownerpanel.gd that drift
# apart the first time it is tuned.
#
# THE OWNER, SINCE 0.7.1. It was "dev", because Ctrl+G was the way a dev had in;
# the keys are gone (see player.gd, "DEBUG KEYS (REMOVED)") and the switch on
# the owner panel is the only way in, so the rank says what is true.
#
# It grants nothing either way: take_damage() returns before the hp change AND
# before the defense XP, so an invincible character earns exactly what a
# stationary one does. hp is client-written and only clamped server-side (E-9),
# so a modified client could always refuse to die - this keeps an HONEST build
# honest, which is the whole of what a client-side gate can buy.
const GOD_MODE_MIN_ROLE := "owner"


# WHAT EACH RANK LOOKS LIKE - ON ITS BADGE. These used to paint the NAME: the
# owner's gold, a dev's blue, a mod's green, and the colour a player picked in
# Options was drawn over their own head and nowhere else. Names are the colour
# each player chose now (users.name_hue, drawn by src/shared/nametag.gd), and
# rank is worn as a badge - MOD, DEV - which these colour, and the owner's
# crown. Defined here, with the rank itself, so a MOD over a head and a MOD in
# chat cannot be two different greens.
#
# The player entry is still here for colour_for_role()'s fallback, and a
# player wears no badge to put it on.
const RANK_COLOURS := {
	"owner":  Color(1.0, 0.78, 0.35),
	"dev":    Color(0.62, 0.82, 1.0),
	"mod":    Color(0.55, 0.95, 0.68),
	"player": Color(0.95, 0.85, 0.6),
}


func colour_for_role(which: String) -> Color:
	# An unknown rank paints as a player, for the same reason role_at_least()
	# sorts one lowest: a newer server naming a rank this build has never heard
	# of must not be given a colour that says "staff".
	return RANK_COLOURS.get(which, RANK_COLOURS["player"])


# THE GUILD TAG'S COLOUR, in one place for the same reason RANK_COLOURS is one
# place. The tag is drawn on every chat line, on the players menu, on the
# kingdom board and over your own head, and four opinions about what a guild
# looks like is how it stops being recognisable at a glance - which is the
# entire point of having a tag.
#
# DELIBERATELY NOT A RANK COLOUR, and not near one. A guild is not a rank: the
# owner and a brand-new player can be in the same guild, and a tag tinted like
# staff would say something about its members that is not true. The violet is
# outside the four rank colours on purpose, so the tag and the name beside it
# are read as two different facts.
const GUILD_TAG_COLOUR := Color(0.72, 0.68, 0.86)


func guild_tag_text(tag: String) -> String:
	"""The tag as it is drawn anywhere: "[ELUSION]", or "" for no guild.

	THE BRACKETS LIVE HERE rather than at four call sites, so changing how a
	guild is written is one edit instead of four that can disagree.

	THE CLIENT DECIDES NOTHING ABOUT THE LETTERS. guild_tag() in app.py
	uppercases the name and bounds it at MAX_GUILD_NAME, and this only wraps
	what it sent. That is what stops a 24-character name founded under the old
	rule from drawing a banner over somebody's head: the bound is applied on the
	side that cannot be edited by whoever is holding the client.

	BBCODE IS NOT ESCAPED HERE, and a caller rendering into a RichTextLabel must
	pass this through its own escape exactly as it does a username. chatpanel's
	_escape() turns "[" into "[lb]", and this string begins with one.
	"""
	var trimmed: String = tag.strip_edges()
	return "" if trimmed == "" else "[%s]" % trimmed


func take_staff_unprotected_notice() -> bool:
	"""True once per login when this staff account came in without a code."""
	if not staff_unprotected or _told_staff_unprotected or not role_at_least("mod"):
		return false
	_told_staff_unprotected = true
	return true


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


func _set_identity(new_username: String, new_role: String, owner_flag: bool) -> void:
	# EVERY WRITE TO THESE THREE GOES THROUGH HERE. They are set from four
	# places - login, resume, heartbeat and signout - and a signal emitted from
	# three of them is a signal that is wrong on the fourth.
	#
	# The comparison is not an optimisation. heartbeat() runs every 15 seconds
	# and assigns the same rank almost every time; emitting on each of those
	# would have listeners rebuilding a label four times a minute forever.
	var changed: bool = (username != new_username
		or role != new_role
		or is_owner != owner_flag)
	username = new_username
	role = new_role
	is_owner = owner_flag
	if changed:
		identity_changed.emit(username, role)


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# Resolved before anything can make a request. Printed because a client
	# pointed at the wrong server looks exactly like a server that is down.
	BASE_URL = _resolve_base_url()
	if BASE_URL != DEFAULT_BASE_URL:
		print("[BOOT] Api: server override in effect — %s" % BASE_URL)
	# KEPT-OPEN CONNECTIONS, off the web. A browser keeps its own connections
	# open, and a no-threads web build has no HTTPClient sockets to keep anyway.
	if not OS.has_feature("web"):
		_pool = ConnectionPool.new()
		_pool.name = "connections"
		add_child(_pool)
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

# HOW MANY REQUESTS THIS CLIENT HAS MADE, AND WHY IT IS WORTH COUNTING.
#
# This is the number that decides how many people the server can hold, and it
# is the only one on the perf overlay that is not about this machine at all.
#
# The frame counters answer "is the game smooth for me". This answers "what
# does one of me cost the server", and it is multiplied by every player at
# once: the load test puts the read ceiling around 800 requests a second, so a
# client that polls at 0.75/s fits about a thousand players on that box and one
# that polls at 3/s fits two hundred and fifty. Nobody notices adding a panel
# that refreshes every two seconds. Everybody notices the box it lands on.
#
# A ROLLING WINDOW, NOT A TOTAL. A total only says the session was long. What
# matters is the rate right now, with whatever panels happen to be open - which
# is the thing that changes as the game grows.
const REQUEST_WINDOW_SECONDS := 20.0

var _request_times: Array[float] = []
var _requests_total: int = 0


func _note_request() -> void:
	# Called from the one funnel every request goes through. Cheap by
	# construction: one append and a trim of whatever fell out of the window.
	var now: float = Time.get_ticks_msec() / 1000.0
	_requests_total += 1
	_request_times.append(now)
	var cutoff: float = now - REQUEST_WINDOW_SECONDS
	while not _request_times.is_empty() and _request_times[0] < cutoff:
		_request_times.remove_at(0)


func requests_per_second() -> float:
	"""The rate over the last REQUEST_WINDOW_SECONDS, for the perf overlay."""
	if _request_times.is_empty():
		return 0.0
	return float(_request_times.size()) / REQUEST_WINDOW_SECONDS


func requests_total() -> int:
	return _requests_total


func get_json(path: String, timeout_override: float = 0.0) -> Dictionary:
	return await _request(HTTPClient.METHOD_GET, path, {}, timeout_override)


func post(path: String, body: Dictionary, timeout_override: float = 0.0) -> Dictionary:
	return await _request(HTTPClient.METHOD_POST, path, body, timeout_override)


func put(path: String, body: Dictionary) -> Dictionary:
	return await _request(HTTPClient.METHOD_PUT, path, body)


# RAW BYTES GOING OUT, the mirror of get_bytes() below, and the only caller is
# the picture upload.
#
# WHY NOT BASE64 THROUGH post(). Because base64 is a third bigger, and the
# server refuses a body over four megabytes - so a four-megabyte photo becomes
# five and a half and bounces off a limit it is not actually over. The player
# would be told their picture was too big for a picture that was not. Binary
# costs nothing extra and fits the number that is written down.
#
# UNLIKE get_bytes, the ANSWER here is ordinary JSON, so it is read by the same
# function every other call uses. A raw POST that failed to notice a 401, or
# forgot to mark the server reachable, would be a second client with quietly
# different opinions.
func post_bytes(path: String, payload: PackedByteArray, content_type: String,
		extra_headers: Dictionary = {}, timeout_override: float = 0.0) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = timeout_override if timeout_override > 0.0 else TIMEOUT
	add_child(http)

	var headers := PackedStringArray(["Content-Type: " + content_type,
		# STAMPED HERE TOO, and this is the one most likely to be forgotten:
		# three functions in this file build headers and the gate is only as
		# good as the least of them. A route reached through a builder that
		# omitted this would read as a pre-versioning client forever.
		BUILD_HEADER + ": " + str(BUILD)])
	var sent_token: String = token
	if token != "":
		headers.append("Authorization: Bearer " + token)
	for key in extra_headers:
		headers.append("%s: %s" % [str(key), str(extra_headers[key])])

	var err := http.request_raw(BASE_URL + path, headers, HTTPClient.METHOD_POST, payload)
	if err != OK:
		http.queue_free()
		_set_online(false)
		return _failure(0, "Could not reach the server.")

	return await _read_answer(http, sent_token, path)


func get_bytes(path: String, timeout_override: float = 0.0) -> Dictionary:
	"""
	A GET whose answer is not JSON - a picture, so far.

	SEPARATE FROM _request() ON PURPOSE. That one parses every response as JSON
	and decides the server's reachability from it, and a PNG is neither JSON
	nor evidence of anything different. This is the same request with neither
	of those steps, returning {"ok": bool, "status": int, "bytes":
	PackedByteArray}.
	"""
	var http := HTTPRequest.new()
	http.timeout = timeout_override if timeout_override > 0.0 else TIMEOUT
	add_child(http)

	var headers := PackedStringArray([BUILD_HEADER + ": " + str(BUILD)])
	if token != "":
		headers.append("Authorization: Bearer " + token)

	_note_request()
	var err := http.request(BASE_URL + path, headers, HTTPClient.METHOD_GET)
	if err != OK:
		http.queue_free()
		return {"ok": false, "status": 0, "bytes": PackedByteArray()}

	var result: Array = await http.request_completed
	http.queue_free()

	var status: int = result[1]
	if result[0] != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "status": status, "bytes": PackedByteArray()}
	return {
		"ok": status >= 200 and status < 300,
		"status": status,
		"bytes": result[3] as PackedByteArray,
	}


func send_before_leaving(method: String, path: String, body: Dictionary) -> bool:
	"""A request for a page that is closing or hidden: sent before this
	returns, finished by the browser whether or not the page survives, and its
	answer never read. False off the web, or with nobody signed in.

	Only for writes the server takes whole and as often as it is given them -
	the save sections are; a sale or a take from a loot bag is not. Nothing is
	learned from the answer, so a refusal here changes nothing on this side and
	the ordinary push, if the page comes back, sends the same thing again."""
	if not WebPage.in_browser() or token == "":
		return false
	# THE SAME THREE HEADERS AS EVERY OTHER REQUEST, the build among them.
	var headers := PackedStringArray(["Content-Type: application/json",
		BUILD_HEADER + ": " + str(BUILD),
		"Authorization: Bearer " + token])
	_note_request()
	return WebPage.send_now(BASE_URL + path, method, headers, JSON.stringify(body))


func _request(method: int, path: String, body: Dictionary, timeout_override: float = 0.0) -> Dictionary:
	# 0.0 means "use the normal budget" rather than "no timeout" — an explicit
	# zero on HTTPRequest.timeout disables the timeout entirely, which is the
	# opposite of what a caller passing a smaller number wants.
	var timeout: float = timeout_override if timeout_override > 0.0 else TIMEOUT

	var headers := PackedStringArray(["Content-Type: application/json",
		# EVERY REQUEST CARRIES THE BUILD. Not only the authenticated ones:
		# login and register are gated too, deliberately, because being let in
		# and then refused on the next call is worse than being told at the
		# door - and the login screen is the one place this client already
		# knows how to show a refusal.
		BUILD_HEADER + ": " + str(BUILD)])
	# Remembered, because the answer is only about THIS token. A logout and a
	# fresh login can both happen while a slow request is in flight, and a 401
	# for the old token says nothing about the new one.
	var sent_token: String = token
	if token != "":
		headers.append("Authorization: Bearer " + token)

	var payload := ""
	if not body.is_empty():
		payload = JSON.stringify(body)

	_note_request()
	if _pool != null:
		var job: ConnectionPool.Job = _pool.send(BASE_URL, method, path, headers, payload.to_utf8_buffer(), timeout)
		var answer: Array = await job.done
		return _answer_from(answer, sent_token, path)

	var http := HTTPRequest.new()
	http.timeout = timeout
	add_child(http)
	var err := http.request(BASE_URL + path, headers, method, payload)
	if err != OK:
		http.queue_free()
		_set_online(false)
		return _failure(0, "Could not reach the server.")

	return await _read_answer(http, sent_token, path)


# The kept-open connections, or null in a browser. See connectionpool.gd.
var _pool: ConnectionPool = null


# EVERY JSON ANSWER COMES THROUGH HERE, whatever shape the request was. Split
# out so post_bytes() can exist without becoming a second client with its own
# opinions about what a 401 means or what proves the server is up.
func _read_answer(http: HTTPRequest, sent_token: String, path: String) -> Dictionary:
	# suspends here until the response lands — this is why every caller
	# has to await. result[] is [result, response_code, headers, body].
	var result: Array = await http.request_completed
	http.queue_free()
	return _answer_from(result, sent_token, path)


# The pool's answers are the same array, so both paths are read here.
func _answer_from(result: Array, sent_token: String, path: String) -> Dictionary:
	var request_result: int = result[0]
	var status: int = result[1]
	var raw_body: PackedByteArray = result[3]

	if request_result != HTTPRequest.RESULT_SUCCESS:
		# A transport failure means no answer came back, so the server is not
		# reachable — whatever `status` says (it is 0 in this branch anyway).
		_set_online(false)
		return _failure(status, _describe_transport_failure(request_result))

	# A GATEWAY SAYING THE SERVER DID NOT ANSWER IS NOT THE SERVER ANSWERING.
	# In a browser the game reaches the API through the site (Caddy, or
	# web/serve.py at home), so with app.py down the page still gets an HTTP
	# answer: 502 Bad Gateway, or 504 when the proxy gave up waiting. Read as
	# "something answered", the login screen said "Connected to the Elusion
	# server." with the API down, and a login showed the proxy's own text ("The
	# API at http://127.0.0.1:5000 did not answer: <urlopen error ...>"). app.py
	# never answers 502 or 504 itself; 503 is its maintenance answer and stays
	# an answer. Status 0, so every caller reads it as "no answer", as it is.
	if status == 502 or status == 504:
		_set_online(false)
		return _failure(0, "Can't reach the server. Check your connection and try again.")

	# Any other HTTP status proves the server is listening and answering. A 401
	# or a 500 is still a server. This is the single place reachability is
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
			and path != "/api/auth/session" and path != "/api/auth/resume":
		unauthorized_seen.emit()

	# 426 UPGRADE REQUIRED - this build is older than the server's minimum.
	#
	# LEARNED FROM THE REFUSAL ITSELF rather than waiting for the next poll of
	# /api/status, because by the time this fires the client has already been
	# turned away from everything except that one route. The numbers are in the
	# body: the server names both the minimum and what this client claimed to
	# be, precisely so a player can read them back to somebody.
	#
	# NOT A SIGNAL. unauthorized_seen is a prompt to go and ASK - a 401 might be
	# a mistyped password and heartbeat() decides. This is not ambiguous: there
	# is one reason a server answers 426 and no probe would tell us more. So it
	# is recorded where every caller already looks, and signout_notice carries
	# the words to the login screen the same way a ban does.
	if status == 426:
		if data is Dictionary:
			server_min_build = int(data.get("min_build", server_min_build))
		signout_notice = "This version of the game is too old to connect." \
			+ " Please update to keep playing."

	return {
		"ok": false,
		"status": status,
		"data": data,
		"error": _describe_api_error(data, status),
	}


# =============================================================================
# AUTH
# =============================================================================

func refresh_build_info() -> Dictionary:
	"""Ask /api/status what it thinks of builds, and remember the answer.

	/api/status IS THE ONE ROUTE THE BUILD GATE NEVER REFUSES, which is what
	makes this reachable exactly when it is needed. A client turned away from
	everything else can still get here and find out why, instead of being
	refused into silence.

	NOTHING IS WRITTEN WHEN THE SERVER CANNOT BE REACHED. A failed request
	leaves both statics at whatever they were - -1 if never asked - because
	"could not ask" and "the gate is off" are different answers and only one of
	them is worth acting on. A client that read a timeout as `min_build = 0`
	would cheerfully report that it was current, which is the failure this whole
	feature exists to remove.

	Returns the answer, so probe_and_resume() can read "is the server there"
	from it rather than asking again."""
	var res: Dictionary = await get_json("/api/status", PROBE_TIMEOUT)
	if not res.get("ok", false) or not (res.get("data") is Dictionary):
		return res
	server_min_build = int(res.data.get("min_client_build", server_min_build))
	server_current_build = int(res.data.get("current_client_build", server_current_build))
	return res


func login(user: String, password: String, code: String = "") -> Dictionary:
	# `code` is the staff login code from the email; see needs_login_code().
	var body := {"username": user, "password": password, "install": install_id()}
	if code != "":
		body["code"] = code
	# THIS COMPUTER'S PROOF, if a code has been typed on it before. A staff
	# login with it needs no code. Sent for every account: the server ignores
	# it for players, and this client does not know who is staff until after.
	var device: String = device_token_for(user)
	if device != "":
		body["device"] = device
	var res := await post("/api/auth/login", body)
	# A 202 is a 2xx with no token in it. Adopting it would save an empty
	# session and walk into the game signed in as nobody.
	if res.ok and not needs_login_code(res):
		_adopt_session(res.data)
		if res.data is Dictionary and str(res.data.get("device_token", "")) != "":
			_remember_device(user, str(res.data["device_token"]))
	return res


# =============================================================================
# ONE CODE PER COMPUTER
# =============================================================================
# A staff login that got in with an emailed code is answered with a device
# token (TRUSTED DEVICES in app.py). Kept here, per account, and sent with the
# next login from this computer so it is not asked again - for thirty days, or
# until the account's rank or password changes.
#
# ITS OWN FILE, NOT session.cfg. The session goes when "Remember me" is off or
# the player logs out; this is about the computer, not the session, and a mod
# who never ticks Remember me would otherwise be asked every single time -
# which is the complaint this exists to answer. It is no password: the server
# checks it only after the password and the ban.
const DEVICES_PATH := "user://devices.cfg"


func device_token_for(user: String) -> String:
	var file := ConfigFile.new()
	if file.load(DEVICES_PATH) != OK:
		return ""
	return str(file.get_value("devices", user.strip_edges().to_lower(), ""))


func _remember_device(user: String, device: String) -> void:
	var file := ConfigFile.new()
	file.load(DEVICES_PATH)
	file.set_value("devices", user.strip_edges().to_lower(), device)
	file.save(DEVICES_PATH)


# =============================================================================
# THIS COPY OF THE GAME
# =============================================================================
# A random id made the first time the game runs, kept in its own file and sent
# with every login, registration and resume (INSTALL IDS in app.py). A banned
# player who changes their address with a VPN is still at the same computer,
# and the server will not make them a new account from it.
#
# NOT A SECRET AND NOT A PASSWORD. It proves nothing about who is playing - a
# family shares a computer - and the server keeps only its hash and never sends
# it anywhere. ITS OWN FILE, like devices.cfg: it belongs to the computer, so
# logging out or unticking Remember me must not throw it away, or logging out
# would be all it took to get a fresh one.
const INSTALL_PATH := "user://install.cfg"

var _install_id: String = ""


func install_id() -> String:
	if _install_id != "":
		return _install_id
	var file := ConfigFile.new()
	if file.load(INSTALL_PATH) == OK:
		var kept: String = str(file.get_value("install", "id", ""))
		if kept.length() == 64 and kept.is_valid_hex_number():
			_install_id = kept
			return _install_id
	_install_id = _fresh_install_id()
	file.set_value("install", "id", _install_id)
	file.save(INSTALL_PATH)
	return _install_id


static func _fresh_install_id() -> String:
	# CRYPTO WHEN THE BUILD HAS IT, asked for by name so a build without the
	# module still compiles. Unpredictable matters a little: an id somebody
	# could guess is an id they could send to get a stranger's computer
	# refused. The fallback is only for a build that cannot do better.
	var bytes := PackedByteArray()
	if ClassDB.class_exists("Crypto"):
		var crypto: Object = ClassDB.instantiate("Crypto")
		if crypto != null:
			bytes = crypto.call("generate_random_bytes", 32)
	if bytes.size() != 32:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		bytes = PackedByteArray()
		for i in 32:
			bytes.append(rng.randi_range(0, 255))
	return bytes.hex_encode()


static func needs_login_code(res: Dictionary) -> bool:
	"""True when the login is a staff account's and wants the emailed code:
	the first step (202), or a code that was wrong or has run out (400). The
	server only asks after the password and the ban check have passed - see
	STAFF LOGIN CODES in app.py."""
	var data: Variant = res.get("data", {})
	return data is Dictionary and bool(data.get("code_required", false))


func register(user: String, password: String) -> Dictionary:
	var res := await post("/api/auth/register",
		{"username": user, "password": password, "install": install_id()})
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
	# THE BUILD NUMBERS FIRST, and this IS a second request where the comment
	# above argues against paying twice. The argument changed, for one reason:
	# /api/status is the only route the build gate never refuses, so it is the
	# only one that still answers when this build is the problem. Asking
	# /api/auth/session first and stopping on its refusal would leave the player
	# reading "could not resume your session" about a version mismatch.
	#
	# ONE EXTRA REQUEST, ONCE, ON THE LOGIN SCREEN. Not per frame and not per
	# poll - this runs where somebody is already waiting for a server to answer,
	# and it is the only moment the answer matters.
	var status_res: Dictionary = await refresh_build_info()

	# A REMEMBERED LOGIN IS CARRIED ON A NEW TOKEN. One login at a time: a
	# second copy of the game opened on this computer finds this same token,
	# and checking it with GET /api/auth/session would let both run on one
	# session. POST /api/auth/resume swaps it, and ends every other session on
	# the account - the other copy is told it was signed in somewhere else.
	# Nothing remembered: the /api/status answer above already says whether the
	# server is there. This asked /api/auth/session again, which answers 401 to
	# nobody signed in, and in a browser every 401 is a red line in the console.
	var res: Dictionary
	if token != "":
		res = await post("/api/auth/resume", {"install": install_id()}, PROBE_TIMEOUT)
		# A server from before the route: check the token the old way.
		if int(res.get("status", 0)) == 404:
			res = await get_json("/api/auth/session", PROBE_TIMEOUT)
	else:
		res = status_res

	if int(res.get("status", 0)) == 0:
		return {"online": false, "resumed": false}

	if token == "":
		return {"online": true, "resumed": false}

	if res.get("ok", false):
		var fresh: String = str(res.data.get("token", ""))
		if fresh != "":
			token = fresh
			_save_session()
		_set_identity(
			str(res.data.get("username", username)),
			str(res.data.get("role", "player")),
			bool(res.data.get("is_owner", false)))
		needs_email = bool(res.data.get("needs_email", false))
		adopt_name_hue(res.data)
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
	if verdict == "revoked":
		last_refusal = res
	if verdict == "ok" and res.get("data") is Dictionary:
		# Username is passed through unchanged: this response carries one, but
		# a heartbeat is not where an account gets renamed, and reading it here
		# would make a missing field look like a rename.
		_set_identity(username,
			str(res.data.get("role", role)),
			bool(res.data.get("is_owner", is_owner)))
	return verdict


# =============================================================================
# THE NAME COLOUR, KEPT ON THE SERVER
# =============================================================================
# The hue a player picks in Options used to live in options.cfg and nowhere
# else, so it was drawn over their own head and nowhere else. The server keeps
# it now (users.name_hue) and sends it with every name; this is the half that
# keeps the two in step.
#
#   SERVER WINS ON LOGIN. A second machine draws the colour chosen on the
#   first, so the login answer's hue is written into Settings.
#   THE SLIDER WINS AFTER THAT. Moving it pushes the new hue, once the slider
#   has stopped for NAME_HUE_PUSH_DELAY - a drag across the wheel is dozens of
#   changes and should be one request.
#   A COLOUR CHOSEN BEFORE THE SERVER KEPT ONE IS UPLOADED, not lost: an
#   account the server has no hue for, on a machine that has a non-default
#   one, sends it.

const NAME_HUE_PUSH_DELAY := 0.6

# What the server last confirmed it holds, or null for "nothing chosen". A push
# that would send the same number is not sent, which is also what stops the
# login's own write into Settings from echoing straight back up.
var _synced_name_hue: Variant = null
var _name_hue_push: int = 0


func adopt_name_hue(data: Dictionary) -> void:
	_watch_name_hue()
	var theirs: Variant = data.get("name_hue")
	if theirs is int or theirs is float:
		_synced_name_hue = int(theirs)
		if int(round(float(Settings.get_value("name_hue")))) != int(theirs):
			Settings.set_value("name_hue", float(theirs))
		return
	_synced_name_hue = null
	if not is_equal_approx(float(Settings.get_value("name_hue")),
			float(Settings.DEFAULTS["name_hue"])):
		push_name_hue_soon()


func _watch_name_hue() -> void:
	# CONNECTED HERE, not in _ready(). Settings is declared after Api in
	# project.godot, so at Api's _ready() it may not exist yet; by the time
	# anybody has logged in, every autoload has.
	if not Settings.changed.is_connected(_on_setting_changed):
		Settings.changed.connect(_on_setting_changed)


func _on_setting_changed(key: String, _value: Variant) -> void:
	if key == "name_hue":
		push_name_hue_soon()


func name_hue_to_push() -> int:
	"""The hue the server should hold, or -1 when it already holds it."""
	var hue: int = wrapi(int(round(float(Settings.get_value("name_hue")))), 0, 360)
	if _synced_name_hue != null and int(_synced_name_hue) == hue:
		return -1
	return hue


func push_name_hue_soon() -> void:
	# A GENERATION, like the staff panel's searches: every change takes a
	# number, and only the last one to finish waiting is sent.
	_name_hue_push += 1
	var mine: int = _name_hue_push
	await get_tree().create_timer(NAME_HUE_PUSH_DELAY).timeout
	if mine != _name_hue_push or token == "":
		return
	var hue: int = name_hue_to_push()
	if hue < 0:
		return
	var res: Dictionary = await put("/api/account/name-colour", {"hue": hue})
	if res.get("ok", false):
		_synced_name_hue = hue


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


static func signout_notice_for(res: Dictionary) -> String:
	"""What the login screen says after the server ended this game's session.

	SOMEWHERE ELSE IS ITS OWN SENTENCE. One login at a time (app.py): signing
	in on another computer, or opening a second copy of the game, ends this
	one's session, and the server's 401 says so. "Signed out by the server"
	would read as a kick - to a player who did it themselves a minute ago."""
	var data: Variant = res.get("data", {})
	if data is Dictionary and bool(data.get("signed_in_elsewhere", false)):
		return SIGNED_IN_ELSEWHERE_NOTICE
	return SIGNED_OUT_NOTICE


func adopt_new_token(new_token: String) -> void:
	# A PASSWORD CHANGE DESTROYS EVERY SESSION AND ISSUES ONE REPLACEMENT in the
	# same response, so the player who made the change stays logged in while
	# everyone else is thrown out. This adopts that replacement.
	#
	# NOT _adopt_session(). That reads username, role and is_owner out of the
	# payload it is given, and this payload carries none of them - so it would
	# reset the name to "" and the rank to "player". A password change that
	# quietly demoted the owner would be a memorable bug.
	if new_token == "":
		return
	token = new_token
	_save_session()


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
	_set_identity(
		str(data.get("username", "")),
		str(data.get("role", "player")),
		bool(data.get("is_owner", false)))
	needs_email = bool(data.get("needs_email", false))
	staff_unprotected = bool(data.get("staff_unprotected", false))
	_told_staff_unprotected = false
	adopt_name_hue(data)

	# _save_session() writes the token and username only. is_owner is
	# deliberately not among them — it is re-read from the server on every
	# login and resume, so there is nothing on disk to tamper with.
	_save_session()


func _clear_session() -> void:
	token = ""
	staff_unprotected = false
	_set_identity("", "player", false)
	DirAccess.remove_absolute(SESSION_PATH)


func _save_session() -> void:
	# Not remembered: nothing on disk, and nothing left over from a login that
	# was. See keep_signed_in.
	if not keep_signed_in:
		DirAccess.remove_absolute(SESSION_PATH)
		return
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
	# Only a remembered login is ever written, so one on disk was remembered.
	keep_signed_in = token != ""


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


func describe_online() -> String:
	# The player-facing confirmation that the server is reachable — the positive
	# twin of describe_offline(), kept beside it so both wordings live in one
	# place and every screen says the same thing.
	#
	# Debug builds name the address for the same reason describe_offline() does:
	# when it's you, the address is the fastest way to confirm you're pointed at
	# the right server. A shipped build never shows a player a raw URL.
	if OS.is_debug_build():
		return "Server online at %s — ready when you are." % BASE_URL
	return "Connected to the Elusion server."


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
			return "Can't reach the server. Is it running?" if OS.is_debug_build() \
				else "Can't reach the server. Check your connection and try again."
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
	#
	# A SHIPPED BUILD SAYS NEITHER, and never prints the address - the rule
	# describe_offline() states. A player cannot restart anybody's server.
	if status == 404:
		if not OS.is_debug_build():
			return "The server cannot do that right now."
		return ("%s has no such route. If you just added it, restart the "
			+ "server — otherwise another local Flask project may have taken "
			+ "the port.") % BASE_URL

	return "Something went wrong (HTTP %d)." % status
