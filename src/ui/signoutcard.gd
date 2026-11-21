# signoutcard.gd - a card over the game when staff ended it (0.169.0).
#
# The owner: "when rolling back a account i want it to let the player know by
# counting down on their screen or a loading screen that says your account was
# rolled back", and "same with being kicked staff kicked you". A rollback or a
# kick used to drop the player on the sign-in screen with "You were signed out
# by the server." Now the HUD (characterhud.gd _forced_signout()) puts this up
# first: what happened, in a sentence, and "Back to sign in in 5..." counting
# down, the game paused under it so nothing can hurt the player while they
# read. Then the sign-in screen, which says it again.
#
# The words are Api.signout_card_for()'s, from the server's 401 (app.py
# _remember_ended(), KICKED_MESSAGE, ROLLED_BACK_MESSAGE). Built in code, no
# class_name; made by the HUD with SignoutCard.new().
extends CanvasLayer


# How long the card stays before the sign-in screen.
const SECONDS := 5
const WIDTH := 440.0
const TITLE_COLOUR := Color(0.95, 0.85, 0.6)
const LINE_COLOUR := Color(0.9, 0.87, 0.8)
const CLOCK_COLOUR := Color(0.7, 0.66, 0.6)

var title_label: Label
var line_label: Label
var clock_label: Label
# Seconds a step of the countdown waits; the suite sets it to nothing.
var step_seconds: float = 1.0


func _init() -> void:
	name = "signoutcard"
	layer = 120
	# It runs while the game under it is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.name = "dim"
	dim.color = Color(0, 0, 0, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Clicks stop here: nothing under it answers while it is up.
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var middle := CenterContainer.new()
	middle.set_anchors_preset(Control.PRESET_FULL_RECT)
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(middle)
	var panel := PanelContainer.new()
	panel.name = "panel"
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0.07, 0.06, 0.05, 0.97)
	frame.border_color = Color(0.78, 0.64, 0.36)
	frame.set_border_width_all(2)
	frame.set_corner_radius_all(4)
	frame.set_content_margin_all(22.0)
	panel.add_theme_stylebox_override("panel", frame)
	middle.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	title_label = _label("title", 24, TITLE_COLOUR)
	column.add_child(title_label)
	line_label = _label("line", 16, LINE_COLOUR)
	line_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line_label.custom_minimum_size = Vector2(WIDTH, 0)
	column.add_child(line_label)
	clock_label = _label("clock", 14, CLOCK_COLOUR)
	column.add_child(clock_label)


func _label(label_name: String, size: int, colour: Color) -> Label:
	var label := Label.new()
	label.name = label_name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	return label


func _exit_tree() -> void:
	# NEVER LEAVE THE GAME PAUSED: the sign-in screen, or whatever comes next
	# if something else changed the scene first, starts running.
	if get_tree() != null and get_tree().paused:
		get_tree().paused = false


static func clock_text(left: int) -> String:
	return "Back to sign in in %d..." % left


func show_card(card: Dictionary) -> void:
	title_label.text = str(card.get("title", ""))
	line_label.text = str(card.get("line", ""))
	clock_label.text = clock_text(SECONDS)


func count_down() -> void:
	"""SECONDS, a second at a time, on a timer that runs while the game is
	paused. Returns when it reaches nothing."""
	for left in range(SECONDS, 0, -1):
		clock_label.text = clock_text(left)
		if step_seconds > 0.0:
			await get_tree().create_timer(step_seconds, true).timeout
		else:
			await get_tree().process_frame
		if not is_instance_valid(self) or not is_inside_tree():
			return
