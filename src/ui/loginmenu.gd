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
# ADMIN: no longer decided here. It used to be a hardcoded username
# comparison running on the player's own machine, which anyone could patch
# out or fake. It's a database column now, returned by the login response,
# and mirrored into CharacterData so the rest of the game's existing
# get_is_admin() calls keep working unchanged.
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

	load_remembered_user()
	await _try_resume_session()


func _on_login_field_submitted(_new_text: String) -> void:
	_on_login_button_pressed()


# =============================================================================
# AUTO-LOGIN
# =============================================================================

func _try_resume_session() -> void:
	# NEW: if a token from a previous run is still valid, skip the form
	# entirely. Api loads the cached token in its own _ready(), so by the
	# time we get here it either has one or it doesn't.
	if not Api.is_logged_in():
		return

	%errorlabel.text = "Resuming session..."
	_set_busy(true)

	var resumed: bool = await Api.resume_session()

	_set_busy(false)

	if resumed:
		_complete_login(Api.username)
	else:
		# token expired or was revoked server-side — fall back to the form
		# without alarming the player about it.
		%errorlabel.text = ""


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
		_set_busy(false)
		error_label.text = ""
		_complete_login(username)
		return

	# a 401 means the credentials didn't match — but the server won't say
	# whether that's a wrong password or an account that doesn't exist yet,
	# so the only way to find out is to try creating it.
	if res.status == 401:
		var created: Dictionary = await Api.register(username, password)

		_set_busy(false)

		if created.ok:
			error_label.text = ""
			_complete_login(username)
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
	error_label.text = res.error


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

	CharacterData.load_for_user(canonical_username)
	_sync_admin_from_server()
	_go_to_character_select()


func _go_to_character_select() -> void:
	if char_select_scene == null:
		push_warning("LoginMenu: char_select_scene not assigned in the Inspector — cannot continue")
		return
	get_tree().change_scene_to_packed(char_select_scene)


func _sync_admin_from_server() -> void:
	# CHANGED: was a hardcoded `username == ADMIN_USERNAME` check running on
	# the player's machine. The flag now comes from the users table and
	# arrives in the login response; this just mirrors it into CharacterData
	# so existing get_is_admin() callers elsewhere keep working.
	#
	# Note this writes on every login rather than only on change — the
	# server's answer is authoritative, so a revoked admin has to be able
	# to drop back to false, not stay true because it was true once.
	if CharacterData.get_is_admin() != Api.is_admin:
		CharacterData.set_is_admin(Api.is_admin)


func _set_busy(busy: bool) -> void:
	# disables the form while a request is in flight, so a double-click
	# can't fire two submissions.
	_request_in_flight = busy
	%loginbutton.disabled = busy
	%usernamelineedit.editable = not busy
	%passwordlineedit.editable = not busy


func _on_exit_button_pressed() -> void:
	get_tree().quit()


# =============================================================================
# VALIDATION
# =============================================================================

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
