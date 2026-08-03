# loginmenu.gd — local login screen, entry point before character select.
#
# WHY: minimal local username/password gate before entering character
# select. this is a fully local, no-server game — there's no real backend
# to authenticate against, so this is closer to a local "profile" system
# than true account security. passwords are still hashed rather than
# stored in plaintext, since real players (beta testers) type real
# credentials here and may reuse passwords elsewhere.
#
# SECURITY NOTES (read before touching):
# - passwords are hashed (SHA-256) before ever touching disk, both when
#   registering (save_new_user) and when checking login (check_user_password).
#   never store or compare plaintext passwords here.
# - "remember me" only remembers the USERNAME, not the password — a
#   one-way hash can't be reversed to autofill a password field, and
#   storing the plaintext password separately just for autofill would
#   defeat the point of hashing. returning players retype their password;
#   their username still prefills.
# - ADMIN_USERNAME grants a hardcoded admin flag on login match — kept
#   as-is, flagging its existence here since it's a meaningful
#   access-control detail.
# - this is still not real account security (no salt, no rate limiting) —
#   fine for a local single-player login gate, not something to reuse
#   anywhere server-facing.
#
# SCENE STRUCTURE NOTE: cleaned up to match ONLY the nodes that actually
# exist in loginmenu.tscn. the previous version referenced
# CharacterPanel/CharacterButton/ConfirmButton, none of which exist
# anywhere in this scene — that whole block was dead code here. real
# character selection lives in whatever scene char_select_scene points to.
#
# SIGNAL CONNECTIONS: _on_login_button_pressed and _on_exit_button_pressed
# are wired to loginbutton/exitbutton's "pressed" signal via the editor
# (Node > Signals), not via code. Godot doesn't automatically keep signal
# connections in sync with node renames — if these stop firing, reconnect
# them in the editor.
extends Control


# =============================================================================
# CONSTANTS
# =============================================================================

# grants a hardcoded admin flag on login — see class comment above.
const ADMIN_USERNAME := "Tunacan"


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

	load_remembered_user()


# =============================================================================
# LOGIN / REGISTER
# =============================================================================

func _on_login_button_pressed() -> void:
	var username: String = %usernamelineedit.text.strip_edges()
	var password: String = %passwordlineedit.text.strip_edges()
	var error_label: Label = %errorlabel

	# --- input validation ---
	if username.is_empty() or password.is_empty():
		error_label.text = "Please fill in both fields."
		return
	if not is_valid_input(username):
		error_label.text = "Username: letters, numbers, and _ only."
		return
	if not is_valid_input(password):
		error_label.text = "Password: letters, numbers, and _ only."
		return

	# --- remember me (username only — see class comment) ---
	if %rememberme.button_pressed:
		save_remembered_user(username)
	else:
		save_remembered_user("")

	# --- login / register ---
	if is_username_taken(username):
		if check_user_password(username, password):
			error_label.text = ""
			_complete_login(username)
		else:
			error_label.text = "Incorrect password."
	else:
		save_new_user(username, password)
		error_label.text = "Account created! Logging in..."
		_complete_login(username)


func _complete_login(username: String) -> void:
	# NEW: load THIS user's own character data FIRST — both the admin
	# grant below and character select depend on it already being loaded.
	# see CharacterData.load_for_user()'s comment for why this matters.
	CharacterData.load_for_user(username)
	_grant_admin_if_applicable(username)
	_go_to_character_select()


func _go_to_character_select() -> void:
	if char_select_scene == null:
		push_warning("LoginMenu: char_select_scene not assigned in the Inspector — cannot continue")
		return
	get_tree().change_scene_to_packed(char_select_scene)


func _grant_admin_if_applicable(username: String) -> void:
	# CHANGED: used to just print a message every login, nothing persisted.
	# now actually writes to CharacterData.is_admin (only once — checked
	# first so this doesn't call save_data() on every single admin login).
	# see CharacterData.gd's comment on get_is_admin()/set_is_admin() for
	# why this is modeled as a persisted flag rather than a live check.
	if username == ADMIN_USERNAME:
		if not CharacterData.get_is_admin():
			CharacterData.set_is_admin(true)
			print("Admin privileges granted and persisted.")
		else:
			print("Admin login (already persisted).")
	else:
		print("Standard user login.")


func _on_exit_button_pressed() -> void:
	get_tree().quit()


# =============================================================================
# VALIDATION
# =============================================================================

func is_valid_input(input_str: String) -> bool:
	var regex := RegEx.new()
	regex.compile("^[a-zA-Z0-9_]+$")
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


# =============================================================================
# LOCAL ACCOUNT STORAGE
# =============================================================================
# local-only "accounts" — no server involved. passwords are hashed
# (SHA-256), never stored or compared as plaintext. NOTE: stored key
# changed from "password" to "password_hash" — any account registered
# under the old plaintext format will need to register again, since old
# entries won't have a password_hash value to check against.

func is_username_taken(username: String) -> bool:
	var config := ConfigFile.new()
	var err := config.load("user://users.cfg")
	if err == OK:
		return username in config.get_sections()
	return false


func save_new_user(username: String, password: String) -> void:
	var config := ConfigFile.new()
	config.load("user://users.cfg")
	config.set_value(username, "password_hash", password.sha256_text())
	config.save("user://users.cfg")


func check_user_password(username: String, password: String) -> bool:
	var config := ConfigFile.new()
	var err := config.load("user://users.cfg")
	if err != OK:
		return false

	var stored_hash: String = config.get_value(username, "password_hash", "")
	if stored_hash != "":
		return stored_hash == password.sha256_text()

	# MIGRATION FALLBACK: this account was registered under the OLD
	# plaintext-password format (before hashing was added), so it has no
	# password_hash yet. check the legacy plaintext key instead — if it
	# matches, silently upgrade the entry to the hashed format and remove
	# the plaintext key, so this fallback only ever runs once per account
	# and the plaintext password never gets trusted or stored again.
	var legacy_plaintext: String = config.get_value(username, "password", "")
	if legacy_plaintext != "" and legacy_plaintext == password:
		config.set_value(username, "password_hash", password.sha256_text())
		config.erase_section_key(username, "password")
		config.save("user://users.cfg")
		return true

	return false
