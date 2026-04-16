"""
Login and Character Select UI Controller (Godot 4.5)

WHY: Handles user authentication, character choice, and transition into the game.
HOW: Orchestrates login/register, input validation, remember-me, and admin check.
WHAT: Centralizes UI logic for login and character selection screens.
TODO:
 - Add email/password recovery options.
 - Support guest/demo logins.
 - Refactor to move data/storage logic into dedicated managers.
 - Improve UI/UX (animations, error popups).
"""
extends Control

# ------------------------ CONFIG / CONSTANTS ------------------------
# Used to give admin rights to specified username—editable for production.
const ADMIN_USERNAME = "Tunacan"

# ------------------------ CHARACTER SELECT --------------------------
var selected_index := -1  # Which character the user picked in select screen

@export var char_select_scene : PackedScene  # Assigned in editor, points to character select scene

"""
Prepares UI at startup:
- Detects which screen is active (login/character select) using node existence.
- Preloads any remembered credentials if present.
- Sets up initial character selection state if that panel is visible.
TODO: Bring in a state machine framework for cleaner screen logic.
"""
func _ready():
	if has_node("%UsernameLineEdit"):
		load_remembered_user()
	if has_node("CharacterPanel"):
		update_selection_display()

"""
Handles a character button getting pressed.
WHY: Selects which character slot is active for game entry.
TODO: Highlight active character button visually.
"""
func _on_CharacterButton_pressed(index):
	selected_index = index
	update_selection_display()

"""
When user confirms selection, either starts the game or shows an error.
WHY: Prevents game start without a character; stores which slot is chosen.
TODO: Add animation or feedback on successful selection.
"""
func _on_ConfirmButton_pressed():
	if selected_index < 0:
		show_error("Select a character first!")
		return
	CharacterData.active_character_index = selected_index
	get_tree().change_scene_to_file("res://scenes/Elusion.tscn")

"""
Updates the visual highlight for currently selected character.
WHY: UX feedback for selection.
TODO: Implement visual highlight/animation for clarity.
"""
func update_selection_display():
	pass  # Implement highlight code

"""
Shows errors to player via label or fallback to console.
WHY: Centralizes error reporting for login/character selection.
TODO: Show timed popups or shake effect on error.
"""
func show_error(message):
	if has_node("%ErrorLabel"):
		%ErrorLabel.text = message
	else:
		print(message)

# ------------------------ LOGIN LOGIC -------------------------------

"""
Handles logic for login/register button.
WHY: Validates input, supports login/registration, configures “remember me”, and transitions user on success.
TODO: Add async loading, feedback on connection issues, more granular error messages.
"""
func _on_Login_Button_pressed():
	var username = %UsernameLineEdit.text.strip_edges()
	var password = %PasswordLineEdit.text.strip_edges()
	var error_label = %ErrorLabel

	# --- INPUT VALIDATION ---
	if username.is_empty() or password.is_empty():
		error_label.text = "Please fill in both fields."
		return
	if not is_valid_input(username):
		error_label.text = "Username: letters, numbers, and _ only."
		return
	if not is_valid_input(password):
		error_label.text = "Password: letters, numbers, and _ only."
		return

	# --- REMEMBER ME SUPPORT ---
	if %RememberMe.pressed:
		save_remembered_user(username, password)
	else:
		save_remembered_user("", "")

	# --- LOGIN/REGISTER FLOW ---
	if is_username_taken(username):
		# Existing user: check password
		if check_user_password(username, password):
			error_label.text = ""
			if username == ADMIN_USERNAME:
				print("Admin privileges granted!")
			else:
				print("Standard user login.")
			get_tree().change_scene_to_packed(char_select_scene)
		else:
			error_label.text = "Incorrect password."
	else:
		# Register new user if username not taken
		save_new_user(username, password)
		error_label.text = "Account created! Logging in..."
		if username == ADMIN_USERNAME:
			print("Admin privileges granted!")
		else:
			print("Standard user login.")
		get_tree().change_scene_to_file("res://scenes/CharacterSelect.tscn")

"""
Exit game when user clicks exit/Quit.
WHY: Makes UI complete—standard option.
"""
func _on_ExitButton_pressed():
	get_tree().quit()

"""
Checks if an input only has allowed characters for usernames/passwords.
WHY: Basic security and sanity check—could be strengthened for production.
TODO: Support longer passwords, enforce length criteria, etc.
"""
func is_valid_input(input_str):
	var regex = RegEx.new()
	regex.compile("^[a-zA-Z0-9_]+$")
	return regex.search(input_str) != null

"""
Remembers user credentials for quick login.
WHY: Makes repeated play easier—never store plain passwords in release!
TODO: Hash password, encrypt config, or use platform credential store!
"""
func save_remembered_user(username, password):
	var config = ConfigFile.new()
	config.set_value("login", "remembered_username", username)
	config.set_value("login", "remembered_password", password)
	config.save("user://remembered_user.cfg")

"""
Loads any saved credentials into the login UI.
WHY: Streamlines user experience for returning players.
"""
func load_remembered_user():
	var config = ConfigFile.new()
	var err = config.load("user://remembered_user.cfg")
	if err == OK:
		var remembered_user = config.get_value("login", "remembered_username", "")
		var remembered_pass = config.get_value("login", "remembered_password", "")
		%UsernameLineEdit.text = remembered_user
		%PasswordLineEdit.text = remembered_pass
		%RememberMe.button_pressed = (remembered_user != "" or remembered_pass != "")

"""
Checks if the given username has already been registered.
WHY: Prevents duplicate accounts, enforces unique usernames.
TODO: Move to async logic or a DB back-end later.
"""
func is_username_taken(username):
	var config = ConfigFile.new()
	var err = config.load("user://users.cfg")
	if err == OK:
		return username in config.get_sections()
	return false

"""
Registers a new user in the config (simple local storage for demo).
WHY: Lightweight test of registration workflow—NOT FOR PRODUCTION.
TODO: Migrate to server auth and hashed passwords.
"""
func save_new_user(username, password):
	var config = ConfigFile.new()
	config.load("user://users.cfg")
	config.set_value(username, "password", password)
	config.save("user://users.cfg")

"""
Checks a user's password against stored value.
WHY: Basic local login check—must be replaced by server logic for real games.
"""
func check_user_password(username, password):
	var config = ConfigFile.new()
	var err = config.load("user://users.cfg")
	if err == OK:
		return config.get_value(username, "password", "") == password
	return false
