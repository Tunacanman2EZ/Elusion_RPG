# passwordprompt.gd - "Enter your password to do this" (0.44.0).
#
# STEP-UP (app.py, TOKEN LIFECYCLE): the most powerful routes - ranks, bans,
# gold and items, rollback, the server's switches - want the password typed in
# the last fifteen minutes, so a stolen token alone cannot do them. When the
# server asks, Api asks this (Api.confirm_handler, set by the HUD): the
# password typed here goes to POST /api/auth/confirm and the request is sent
# again. Cancel sends nothing, and the window that asked says the server's
# words.
#
# Nothing typed here is kept: the box is cleared and freed with the prompt.
extends PanelContainer
class_name PasswordPrompt


signal answered(password: String)

var message_label: Label
var box: LineEdit
var ok_button: Button
var cancel_button: Button
var _done: bool = false


func _init() -> void:
	name = "passwordprompt"
	custom_minimum_size = Vector2(340, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 12)
	add_child(pad)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	pad.add_child(column)
	message_label = Label.new()
	message_label.name = "message"
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(message_label)
	box = LineEdit.new()
	box.name = "password"
	box.secret = true
	box.placeholder_text = "Your password"
	box.text_submitted.connect(func(_text: String) -> void: _answer(box.text))
	column.add_child(box)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	column.add_child(row)
	ok_button = Button.new()
	ok_button.name = "confirm"
	ok_button.text = "Confirm"
	ok_button.pressed.connect(func() -> void: _answer(box.text))
	row.add_child(ok_button)
	cancel_button = Button.new()
	cancel_button.name = "cancel"
	cancel_button.text = "Cancel"
	cancel_button.pressed.connect(func() -> void: _answer(""))
	row.add_child(cancel_button)


func ask(message: String) -> void:
	message_label.text = (message if message != "" else "Enter your password to do this.") \
		+ "\nIt is asked again after a quarter of an hour."
	if is_inside_tree():
		box.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_answer("")


func _answer(password: String) -> void:
	if _done:
		return
	_done = true
	box.text = ""
	answered.emit(password)
