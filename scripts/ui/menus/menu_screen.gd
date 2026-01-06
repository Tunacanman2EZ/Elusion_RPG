extends CanvasLayer

const ADMIN_USERNAME = "Tunacan"
var selected_index := -1

var char_select_scene: PackedScene = preload("res://scenes/ui/menus/CharacterSelect.tscn")
var elusion_scene: PackedScene = preload("res://scenes/Elusion.tscn")

func _ready():
	# Show login if present, else char select if present
	if has_node("CenterContainer/VBoxContainer/UsernameLineEdit"):
		load_remembered_user()
		# Optionally show login UI, hide char select UI if both present
	if has_node("CharacterPanel"):
		selected_index = -1
		update_selection_display()

# ------------------- MAIN MENU BUTTONS (optional) -------------------
func _on_Play_Button_pressed():
	get_tree().change_scene_to_packed(char_select_scene)

# ------------------- CHARACTER SELECT -------------------
func _on_character_button_pressed(index):
	selected_index = index
	update_selection_display()

func _on_confirm_button_pressed():
	if selected_index < 0:
		show_error("Select a character first!")
		return
	CharacterData.active_character_index = selected_index
	get_tree().change_scene_to_packed(elusion_scene)

func update_selection_display():
	# To highlight the selected character button, implement as needed
	pass

func show_error(message):
	if has_node("ErrorLabel"):
		$ErrorLabel.text = message
	else:
		print(message)

# ------------------- LOGIN LOGIC -------------------
func _on_login_button_pressed():
	var username = $CenterContainer/VBoxContainer/UsernameLineEdit.text.strip_edges()
	var password = $CenterContainer/VBoxContainer/PasswordLineEdit.text.strip_edges()
	var error_label = $CenterContainer/VBoxContainer/ErrorLabel

	if username.is_empty() or password.is_empty():
		error_label.text = "Please fill in both fields."
		return
	if not is_valid_input(username) or not is_valid_input(password):
		error_label.text = "Letters, numbers, and _ only."
		return

	if $CenterContainer/VBoxContainer/RememberMe.button_pressed:
		save_remembered_user(username, password)
	else:
		save_remembered_user("", "")

	if is_username_taken(username):
		if check_user_password(username, password):
			error_label.text = ""
			if username == ADMIN_USERNAME:
				print("Admin privileges granted!")
			get_tree().change_scene_to_packed(char_select_scene)
		else:
			error_label.text = "Incorrect password."
	else:
		save_new_user(username, password)
		error_label.text = "Account created! Logging in..."
		if username == ADMIN_USERNAME:
			print("Admin privileges granted!")
		get_tree().change_scene_to_packed(char_select_scene)

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
		var saved_pass = config.get_value(username, "password", "")
		return saved_pass == password
	return false

# ------------------- UI HOOKS -------------------
# Connect each character button signal in editor with an index,
# or change to accept a sender and parse its metadata/index property.

# For scene navigation, always use get_tree().change_scene_to_file(path)
# For future, consider using an autoload for persistent state.
