# nettestlogin.gd — Net-Test branch, screen 1 of 3.
#
# The smallest thing that can prove Api.login() works: two fields, two
# buttons, one status line. No art, no theme, no transitions.
#
# WHY THE UI IS BUILT IN CODE rather than laid out in the .tscn: this branch
# exists to be read as a git history, one endpoint per commit. A .tscn diff is
# unreadable noise — reordered nodes, regenerated ids, sub-resources. A script
# diff shows exactly what changed about the integration. The scene file is a
# one-node stub on purpose.
extends Control


# =============================================================================
# NODES (built in _ready)
# =============================================================================

var _username: LineEdit
var _password: LineEdit
var _login_button: Button
var _register_button: Button
var _status: Label

var _busy: bool = false


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	_build_ui()

	# A cached token from a previous run is still worth trying — it saves
	# retyping a password on every test cycle. resume_session() clears it
	# itself if the server rejects it, so a stale token can't strand us.
	if Api.is_logged_in():
		_set_status("Resuming session...")
		_set_busy(true)
		var resumed: bool = await Api.resume_session()
		_set_busy(false)
		if resumed:
			_go_to_select()
			return
		_set_status("Session expired. Log in again.")


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_CENTER)
	root.custom_minimum_size = Vector2(320, 0)
	root.add_theme_constant_override("separation", 8)
	root.position = Vector2(-160, -140)
	add_child(root)

	var title := Label.new()
	title.text = "ELUSION — NET TEST"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	root.add_child(title)

	var server := Label.new()
	server.text = Api.BASE_URL
	server.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	server.add_theme_font_size_override("font_size", 11)
	server.modulate = Color(1, 1, 1, 0.5)
	root.add_child(server)

	root.add_child(_spacer(12))

	root.add_child(_label("Username"))
	_username = LineEdit.new()
	_username.placeholder_text = "username"
	root.add_child(_username)

	root.add_child(_label("Password"))
	_password = LineEdit.new()
	_password.placeholder_text = "password"
	_password.secret = true
	root.add_child(_password)

	root.add_child(_spacer(12))

	_login_button = Button.new()
	_login_button.text = "Log in"
	_login_button.pressed.connect(_on_login)
	root.add_child(_login_button)

	_register_button = Button.new()
	_register_button.text = "Register"
	_register_button.pressed.connect(_on_register)
	root.add_child(_register_button)

	root.add_child(_spacer(12))

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(320, 40)
	root.add_child(_status)

	# Enter submits, because typing a password and reaching for the mouse
	# forty times in a test session is its own small misery.
	_username.text_submitted.connect(func(_t): _on_login())
	_password.text_submitted.connect(func(_t): _on_login())


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.modulate = Color(1, 1, 1, 0.7)
	return l


func _spacer(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c


# =============================================================================
# ACTIONS
# =============================================================================

func _on_login() -> void:
	if _busy:
		return
	if not _validate():
		return

	_set_busy(true)
	_set_status("Logging in...")

	var res: Dictionary = await Api.login(_username.text, _password.text)

	_set_busy(false)

	if res.ok:
		_password.text = ""
		_go_to_select()
		return

	# Api._describe_api_error() already turned the server's body into a
	# sentence, including the deliberately identical 401 that a wrong password
	# and a nonexistent username both produce.
	_set_status(res.error)


func _on_register() -> void:
	if _busy:
		return
	if not _validate():
		return

	_set_busy(true)
	_set_status("Creating account...")

	var res: Dictionary = await Api.register(_username.text, _password.text)

	_set_busy(false)

	if res.ok:
		_password.text = ""
		_go_to_select()
		return

	_set_status(res.error)


func _validate() -> bool:
	# Client-side checks are a courtesy to save a round trip. The server
	# validates independently and is the only opinion that counts — see
	# validate_credentials() in app.py.
	if _username.text.strip_edges() == "":
		_set_status("Enter a username.")
		return false
	if _password.text == "":
		_set_status("Enter a password.")
		return false
	return true


# =============================================================================
# STATE
# =============================================================================

func _set_busy(busy: bool) -> void:
	_busy = busy
	_login_button.disabled = busy
	_register_button.disabled = busy


func _set_status(text: String) -> void:
	_status.text = text


func _go_to_select() -> void:
	get_tree().change_scene_to_file("res://scene/nettest/nettestselect.tscn")
