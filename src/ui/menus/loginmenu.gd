# loginmenu.gd — login screen, entry point before character select.
#
# CHANGED: this used to be a fully local profile gate — usernames and
# SHA-256 password hashes lived in user://users.cfg on the player's own
# machine. Accounts are now real: the server owns them, hashes passwords
# with a salt, and hands back a session token. See src/systems/api.gd.
#
# WHAT THIS MEANS FOR THE CODE HERE:
# - _on_login_button_pressed() is now a coroutine. Every server call
#   suspends until the response arrives, so the function can no longer
#   just branch on a return value. This is why it awaits.
# - the button is disabled while a request is in flight. Without that, an
#   impatient double-click fires two registrations for the same account
#   and the second one fails confusingly.
# - the local account helpers (is_username_taken / save_new_user /
#   check_user_password) are gone. Nothing reads user://users.cfg anymore.
#   Old local accounts do NOT migrate — players register once against the
#   server. There are few enough testers for that to be fine.
#
# ONE BUTTON, TWO OUTCOMES: the original screen logged you in if the
# account existed and silently created it if not. That's preserved, but it
# takes two calls now — the server deliberately returns the same error for
# "no such user" and "wrong password" so the endpoint can't be used to
# discover which usernames exist. The client therefore can't tell those
# apart either, so it tries login first (the common case for a returning
# player, one call) and only falls back to register on failure.
#
# RANK: not decided here, and never mirrored into a save. It used to be a
# hardcoded username comparison running on the player's own machine, which
# anyone could patch out or fake. The server decides it, returns it with the
# login response, and Api.role holds it in memory for as long as the session
# lasts. owner > dev > mod > player, and nothing on disk has a say.
#
# SECURITY NOTES (read before touching):
# - no password ever touches disk here. "remember me" stores the USERNAME
#   and the session token — never the password.
# - the token in user://session.cfg is a bearer credential. Anyone with
#   the file can act as that account until it expires, same as a browser
#   cookie. That's the accepted tradeoff for not retyping a password.
# - client-side validation below is a courtesy so the player gets an
#   instant error instead of a round trip. The server validates everything
#   again and its answer is the one that counts.
#
# SIGNAL CONNECTIONS: all connected via code in _ready() below (not the
# editor's Node > Signals panel) — a code connection always points at
# whatever function currently has this name, with no separate stored link
# that can go stale if a node gets renamed later.
extends Control


# =============================================================================
# CONSTANTS
# =============================================================================

# mirrors the server's MIN_PASSWORD_LENGTH in app.py. Kept in sync by hand;
# if they ever disagree the server wins and the player sees its message.
const MIN_PASSWORD_LENGTH := 8

# Colours for the connection banner. Deliberately NOT the red that %errorlabel
# uses: "the server is down" is a statement about the world, not a complaint
# about what the player typed, and colouring it like a validation error makes
# people retype a password that was never wrong.
const STATUS_WORKING := Color(0.75, 0.72, 0.62)   # muted grey — "checking"
const STATUS_OFFLINE := Color(1.0, 0.65, 0.25)    # amber — "something is up"


# =============================================================================
# EXPORTED SETTINGS
# =============================================================================

# assigned in the Inspector — points at the character select scene. BOTH
# success paths below (existing-user login, new-user registration) use
# this single source of truth instead of a hardcoded path string, which is
# what caused the original "Cannot open file res://scenes/CharacterSelect.tscn"
# crash (wrong folder name/casing, plus a second hardcoded path that had
# drifted out of sync with this one).
@export var char_select_scene: PackedScene


# =============================================================================
# STATE
# =============================================================================

# guards against overlapping submissions while a request is in flight.
var _request_in_flight: bool = false


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# HIDDEN IN THE SCENE FILE, SHOWN HERE.
	#
	# Both this and the player HUD are CanvasLayers, so the 2D editor draws them
	# over the map at a fixed screen position that does not scale with zoom -
	# which makes laying tiles at 30% zoom impossible. They are saved with
	# visible = false so the editor shows the world, and turned on here the
	# moment they enter the tree at runtime.
	#
	# THIS LINE IS WHAT MAKES THAT SAFE. Hiding them without it means they are
	# hidden in the game too, with no error and nothing in the log - the HUD just
	# is not there. If you ever see that, this is the line that went missing.
	visible = true

	# NEW: connect via code rather than relying on editor-made signal
	# connections (Node > Signals panel) — those don't automatically stay
	# in sync with node renames, which is what caused the confusion here.
	# a code connection always points at whatever function currently has
	# this name, with no separate stored link that can go stale.
	if not %loginbutton.pressed.is_connected(_on_login_button_pressed):
		%loginbutton.pressed.connect(_on_login_button_pressed)
	if not %exitbutton.pressed.is_connected(_on_exit_button_pressed):
		%exitbutton.pressed.connect(_on_exit_button_pressed)

	# NEW: pressing Enter while either field is focused submits the form,
	# same as clicking Login. LineEdit's text_submitted signal passes the
	# field's text as an argument, which _on_login_button_pressed() doesn't
	# take — the wrapper closures below just discard that argument and
	# call the existing handler exactly as the button already does, rather
	# than changing that function's signature to accommodate this.
	if not %usernamelineedit.text_submitted.is_connected(_on_login_field_submitted):
		%usernamelineedit.text_submitted.connect(_on_login_field_submitted)
	if not %passwordlineedit.text_submitted.is_connected(_on_login_field_submitted):
		%passwordlineedit.text_submitted.connect(_on_login_field_submitted)

	# NEW: the banner follows reachability for as long as this screen is open,
	# not just at startup. If the player leaves the game sitting here and
	# starts the server, the next request that succeeds clears the warning on
	# its own.
	if not Api.connection_changed.is_connected(_on_connection_changed):
		Api.connection_changed.connect(_on_connection_changed)

	load_remembered_user()

	# SIGNED OUT FROM THE SERVER'S SIDE - a kick, a ban, or a login that ran
	# out while the game was open. characterhud.gd's heartbeat put the reason
	# here on the way out; show it once and let it go, so a later normal logout
	# does not repeat it.
	if Api.signout_notice != "":
		%errorlabel.text = Api.signout_notice
		Api.signout_notice = ""

	await _check_connection_and_resume()


func _on_login_field_submitted(_new_text: String) -> void:
	_on_login_button_pressed()


func _on_connection_changed(online: bool) -> void:
	# Only ever CLEARS the banner. A request failing mid-login already writes
	# its own message into %errorlabel with more detail than this has, and
	# two lines saying the same thing in different colours reads as two
	# separate problems.
	if online:
		_set_status("", STATUS_WORKING)
	else:
		_set_status(Api.describe_offline(), STATUS_OFFLINE)


# =============================================================================
# AUTO-LOGIN
# =============================================================================

func _check_connection_and_resume() -> void:
	# Runs once on open. One request answers both questions: is the server
	# there, and is a cached token still good?
	#
	# FIXED — THE TYPING DELAY. This used to call _set_busy(true), which sets
	# `editable = false` on BOTH text fields, and then waited on a request
	# with the normal ten-second budget. With the server down, the first ten
	# seconds after the login screen appeared were spent with the username and
	# password boxes silently refusing input. They looked completely normal —
	# the caret sat in the field, the player typed, and nothing came out.
	#
	# Two things were wrong and both are fixed:
	#   1. The fields are no longer locked. _set_busy's second argument leaves
	#      them editable; only the submit button is disabled, which is all the
	#      double-click guard ever actually needed here.
	#   2. The probe now uses Api.PROBE_TIMEOUT (3s) instead of TIMEOUT (10s),
	#      because nobody asked for this request and nobody is watching it.
	#
	# This ran even with no cached token, because _log_server_reachability()
	# in api.gd was firing its own copy at the same time — so the delay showed
	# up on a fresh install too, with nothing to resume.
	_set_status("Checking server...", STATUS_WORKING)
	_set_busy(true, false)

	var probe: Dictionary = await Api.probe_and_resume()

	_set_busy(false)

	if not probe.get("online", false):
		_set_status(Api.describe_offline(), STATUS_OFFLINE)
		return

	_set_status("", STATUS_WORKING)

	if not probe.get("resumed", false):
		# Either there was no cached token, or the server rejected it. Neither
		# is worth a message — the form is right there.
		return

	# A valid session came back. But DON'T steal the screen from someone who
	# has already started typing: a player entering a password is telling us
	# they want a specific account, quite possibly not the remembered one.
	# Jumping to character select mid-keystroke would be the single most
	# jarring thing this screen could do.
	if %passwordlineedit.text != "":
		return

	await _complete_login(Api.username)


# =============================================================================
# LOGIN / REGISTER
# =============================================================================

func _on_login_button_pressed() -> void:
	if _request_in_flight:
		return

	var username: String = %usernamelineedit.text.strip_edges()
	var password: String = %passwordlineedit.text.strip_edges()
	var error_label: Label = %errorlabel

	# --- input validation (courtesy only — the server validates too) ---
	if username.is_empty() or password.is_empty():
		error_label.text = "Please fill in both fields."
		return
	if not is_valid_username(username):
		error_label.text = "Username: letters, numbers, and _ only."
		return
	if password.length() < MIN_PASSWORD_LENGTH:
		error_label.text = "Password must be at least %d characters." % MIN_PASSWORD_LENGTH
		return

	# --- remember me (username only — see class comment) ---
	if %rememberme.button_pressed:
		save_remembered_user(username)
	else:
		save_remembered_user("")

	error_label.text = "Connecting..."
	_set_busy(true)

	# --- try to log in first ---
	var res: Dictionary = await Api.login(username, password)

	if res.ok:
		error_label.text = "Loading characters..."
		await _complete_login(username)
		_set_busy(false)
		error_label.text = ""
		return

	# a 401 means the credentials didn't match — but the server won't say
	# whether that's a wrong password or an account that doesn't exist yet,
	# so the only way to find out is to try creating it.
	if res.status == 401:
		var created: Dictionary = await Api.register(username, password)

		_set_busy(false)

		if created.ok:
			error_label.text = "Loading characters..."
			await _complete_login(username)
			error_label.text = ""
			return

		# 409 means the account DOES exist, so the original login failure
		# was a genuinely wrong password.
		if created.status == 409:
			error_label.text = "Incorrect password."
		else:
			error_label.text = created.error
		return

	# anything else — server down, validation rejection, unexpected status
	_set_busy(false)
	error_label.text = describe_login_refusal(res)


# COROUTINE — callers must await. CharacterData.load_for_user() fetches every
# character from the server now, so this no longer returns before the data
# exists. Navigating to character select without awaiting would show four empty
# slots to a player who has four characters.
func _complete_login(typed_username: String) -> void:
	# NEW: load THIS user's own character data FIRST — character select
	# depends on it already being loaded.
	# see CharacterData.load_for_user()'s comment for why this matters.
	#
	# CHANGED: loads under the server's spelling of the name, not the one
	# that was typed into the box. THIS IS NOT COSMETIC — it is the whole
	# reason a save can appear to vanish:
	#
	#   - app.py declares `username TEXT ... UNIQUE COLLATE NOCASE`, so the
	#     login query `WHERE username = ?` matches case-INSENSITIVELY.
	#     typing "tunacan" successfully logs you into the account stored as
	#     "Tunacan". the server is right to do this; people don't remember
	#     capitalisation.
	#   - but CharacterData._save_path_for_user() builds a FILENAME from the
	#     name, and filenames keep their case: "Tunacan" is
	#     character_Tunacan.save, "tunacan" is character_tunacan.save.
	#
	# so logging in with different capitalisation than you registered with
	# used to hand you a real, authenticated session pointed at a save file
	# that had never existed — every character gone, nothing actually lost,
	# and no error anywhere to explain it. worse, creating a character then
	# WOULD write that second file, quietly splitting one account's saves
	# across two.
	#
	# the login response returns row["username"] — the canonical stored
	# spelling — and Api.username holds it. that is the authority. the typed
	# string is only a fallback for the case where the server somehow
	# didn't send one back.
	var canonical_username: String = typed_username
	if Api.username != "":
		canonical_username = Api.username

	# await, because load_for_user() now fetches every character from the server
	# instead of reading a local file. Without it, character select would open
	# against empty slots and the data would arrive after the screen had already
	# decided there were no characters.
	await CharacterData.load_for_user(canonical_username)
	_go_to_character_select()


func _go_to_character_select() -> void:
	if char_select_scene == null:
		push_warning("LoginMenu: char_select_scene not assigned in the Inspector — cannot continue")
		return
	get_tree().change_scene_to_packed(char_select_scene)


func _set_busy(busy: bool, lock_fields: bool = true) -> void:
	# Disables the form while a request is in flight, so a double-click can't
	# fire two submissions.
	#
	# lock_fields distinguishes the two kinds of wait this screen has, which
	# were previously treated as one:
	#
	#   SUBMIT (lock_fields = true) — the player pressed Login and is watching.
	#     Freezing the fields is correct: editing the username while it is
	#     being checked would leave the box disagreeing with the request.
	#
	#   BACKGROUND (lock_fields = false) — the startup probe. The player never
	#     asked for it and has no idea it is happening. Locking the fields here
	#     is what made the screen swallow keystrokes with the server down.
	#
	# The button is disabled either way; that is what the double-submit guard
	# actually requires.
	_request_in_flight = busy
	%loginbutton.disabled = busy
	if lock_fields:
		%usernamelineedit.editable = not busy
		%passwordlineedit.editable = not busy
	elif not busy:
		# Releasing a background wait must never leave a field disabled, even
		# if a submit locked them in the meantime.
		%usernamelineedit.editable = true
		%passwordlineedit.editable = true


func _set_status(message: String, color: Color) -> void:
	# The connection banner, separate from %errorlabel. Guarded with
	# has_node so an older copy of loginmenu.tscn without the node keeps
	# working instead of crashing on a missing unique name.
	if not has_node("%statuslabel"):
		return
	var label: Label = $"%statuslabel"
	label.text = message
	label.add_theme_color_override("font_color", color)
	label.visible = message != ""


func _on_exit_button_pressed() -> void:
	get_tree().quit()


# =============================================================================
# VALIDATION
# =============================================================================

static func describe_login_refusal(res: Dictionary) -> String:
	# A BAN SAYS HOW LONG AND WHY. The server has always sent both with its
	# 403 - `ban` carries permanent, expires_at and the reason staff typed -
	# and this screen showed only "This account is banned until further
	# notice", which for a seven-day ban is not even true.
	var data: Variant = res.get("data", {})
	if int(res.get("status", 0)) == 403 and data is Dictionary and data.get("ban") is Dictionary:
		var ban: Dictionary = data["ban"]
		var line: String = "This account is banned permanently."
		if not bool(ban.get("permanent", false)):
			# LOCAL TIME, to the minute. The server's clock is unix time and
			# get_datetime_string_from_unix_time() reads it as UTC, which for
			# most players is a date that is off by hours.
			var local: int = int(ban.get("expires_at", 0)) \
				+ int(Time.get_time_zone_from_system().get("bias", 0)) * 60
			line = "This account is banned until %s." % \
				Time.get_datetime_string_from_unix_time(local, true).substr(0, 16)
		var reason: String = str(ban.get("reason", ""))
		if reason != "":
			line += "\nReason: %s" % reason
		return line
	return str(res.get("error", ""))


func is_valid_username(input_str: String) -> bool:
	# mirrors USERNAME_PATTERN in app.py.
	var regex := RegEx.new()
	regex.compile("^[a-zA-Z0-9_]{3,20}$")
	return regex.search(input_str) != null


# =============================================================================
# REMEMBER ME (username only — see class comment re: why not password too)
# =============================================================================

func save_remembered_user(username: String) -> void:
	var config := ConfigFile.new()
	config.set_value("login", "remembered_username", username)
	config.save("user://remembered_user.cfg")


func load_remembered_user() -> void:
	var config := ConfigFile.new()
	var err := config.load("user://remembered_user.cfg")
	if err == OK:
		var remembered_user: String = config.get_value("login", "remembered_username", "")
		%usernamelineedit.text = remembered_user
		# CHANGED: was %rememberme.pressed, which reads the SIGNAL object
		# (always truthy) rather than the checkbox's actual toggle state —
		# meaning "remember me" was very likely always behaving as checked
		# regardless of the real box state. .button_pressed is the correct
		# property for current toggle state.
		%rememberme.button_pressed = remembered_user != ""
