extends Control

# ------------------------ CONFIG --------------------------------
# Put your admin username here
const ADMIN_USERNAME = "Tunacan"  

# ------------------------ CHARACTER SELECT ----------------------
var selected_index := -1

@export var char_select_scene : PackedScene

func _ready():
	# Detect if we're on the login or character select scene (by node presence)
	if has_node("CenterContainer/VBoxContainer/UsernameLineEdit"):
		load_remembered_user()
	if has_node("CharacterPanel"): # Example parent for character selection
		update_selection_display()

# For character buttons - wire these in the editor, pass the correct index
func _on_CharacterButton_pressed(index):
	selected_index = index
	update_selection_display()

func _on_ConfirmButton_pressed():
	if selected_index < 0:
		show_error("Select a character first!")
		return
	CharacterData.active_character_index = selected_index
	get_tree().change_scene_to_file("res://scenes/Elusion.tscn")

func update_selection_display():
	# OPTIONAL: update UI to show which character button is highlighted
	pass

func show_error(message):
	if has_node("ErrorLabel"):
		$ErrorLabel.text = message
	else:
		print(message)


# ------------------------ LOGIN LOGIC ---------------------------

func _on_Login_Button_pressed():
	var username = $CenterContainer/VBoxContainer/UsernameLineEdit.text.strip_edges()
	var password = $CenterContainer/VBoxContainer/PasswordLineEdit.text.strip_edges()
	var error_label = $CenterContainer/VBoxContainer/ErrorLabel

	# Validate input
	if username.is_empty() or password.is_empty():
		error_label.text = "Please fill in both fields."
		return
	if not is_valid_input(username):
		error_label.text = "Username: letters, numbers, and _ only."
		return
	if not is_valid_input(password):
		error_label.text = "Password: letters, numbers, and _ only."
		return

	# Remember Me
	if $CenterContainer/VBoxContainer/RememberMe.pressed:
		save_remembered_user(username, password)
	else:
		save_remembered_user("", "")

	# Registration or login flow
	if is_username_taken(username):
		# Login
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
		# Register new
		save_new_user(username, password)
		error_label.text = "Account created! Logging in..."
		if username == ADMIN_USERNAME:
			print("Admin privileges granted!")
		else:
			print("Standard user login.")
		get_tree().change_scene_to_file("res://scenes/CharacterSelect.tscn")

func is_valid_input(input_str):
	var regex = RegEx.new()
	regex.compile("^[a-zA-Z0-9_]+$")
	return regex.search(input_str) != null

func save_remembered_user(username, password):
	var config = ConfigFile.new()
	config.set_value("login", "remembered_username", username)
	config.set_value("login", "remembered_password", password)
	config.save("user://remembered_user.cfg")

func load_remembered_user():
	var config = ConfigFile.new()
	var err = config.load("user://remembered_user.cfg")
	if err == OK:
		var remembered_user = config.get_value("login", "remembered_username", "")
		var remembered_pass = config.get_value("login", "remembered_password", "")
		$CenterContainer/VBoxContainer/UsernameLineEdit.text = remembered_user
		$CenterContainer/VBoxContainer/PasswordLineEdit.text = remembered_pass
		$CenterContainer/VBoxContainer/RememberMe.button_pressed = (remembered_user != "" or remembered_pass != "")

func is_username_taken(username):
	var config = ConfigFile.new()
	var err = config.load("user://users.cfg")
	if err == OK:
		return username in config.get_sections()
	return false

func save_new_user(username, password):
	var config = ConfigFile.new()
	config.load("user://users.cfg")
	config.set_value(username, "password", password)
	config.save("user://users.cfg")

func check_user_password(username, password):
	var config = ConfigFile.new()
	var err = config.load("user://users.cfg")
	if err == OK:
		return config.get_value(username, "password", "") == password
	return false
