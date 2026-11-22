# choicebox.gd - what the hero may say, for the player to pick (0.172.0).
#
# The owner: "the thing about chatting in games is a is a convo b is a convo
# and so is c thats what makes chat branching amazing", then "lets add another
# number that says trade" - "the issue was people did not know you could
# trade the shop keep". talk.gd offers a script's "?" lines here: a row a
# choice, numbered, in the speech bubbles' paper (speechbubble.gd), hanging
# under the hero with its tail pointing up. The row under the mouse is lit;
# a click, a tap or its number key picks it, and says `picked` with its
# place. Nothing is said for it - the branch that follows does the talking.
#
# THE NUMBER KEYS ARE THE HOTBAR'S TOO: a pick is taken in _input and kept
# from everything after it, so pressing 1 picks the first answer and drinks
# no potion. A click or tap on a row is kept the same way; one elsewhere
# goes on to the game.
#
# No class_name: preload it by path, made with offer().
extends Node2D

signal picked(choice: int)

const Bubble := preload("res://src/shared/speechbubble.gd")
# The row under the mouse.
const LIT := Color(0.85, 0.66, 0.3, 0.35)
const ROW_GAP := 2.0
# Up to nine: a number key each.
const MOST := 9

var choices: Array = []
var labels: Array = []
var lit: int = -1
var row_size: Vector2 = Vector2.ZERO
var taken: bool = false


static func offer(over: Node2D, said: Array, at: Vector2) -> Node2D:
	"""A box under `over`, its tail's tip at `at`, offering `said` (words)."""
	var box: Node2D = (load("res://src/shared/choicebox.gd") as GDScript).new()
	box.name = "choicebox"
	box.set("choices", said.slice(0, MOST))
	over.add_child(box)
	box.position = at
	return box


static func row_text(place: int, words: String) -> String:
	return "%d  %s" % [place + 1, words]


func _ready() -> void:
	z_index = Bubble.Z
	z_as_relative = false
	for i in choices.size():
		var label := Label.new()
		label.name = "choice%d" % (i + 1)
		label.text = row_text(i, str(choices[i]))
		label.add_theme_font_size_override("font_size", Bubble.FONT_SIZE)
		label.add_theme_color_override("font_color", Bubble.INK)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.scale = Vector2(Bubble.SCALE, Bubble.SCALE)
		add_child(label)
		labels.append(label)
		var wants: Vector2 = label.get_minimum_size() * Bubble.SCALE
		row_size = Vector2(maxf(row_size.x, wants.x), maxf(row_size.y, wants.y))
	_place_rows()


func paper() -> Rect2:
	var size: Vector2 = Vector2(row_size.x, row_size.y * choices.size() + ROW_GAP * maxi(choices.size() - 1, 0)) \
		+ Bubble.PAD * 2.0
	return Rect2(Vector2(-size.x / 2.0, Bubble.TAIL), size)


func row_rect(i: int) -> Rect2:
	var box: Rect2 = paper()
	return Rect2(box.position.x + 1.0, box.position.y + Bubble.PAD.y + i * (row_size.y + ROW_GAP) - 1.0,
		box.size.x - 2.0, row_size.y + 2.0)


func row_at(local: Vector2) -> int:
	for i in choices.size():
		if row_rect(i).has_point(local):
			return i
	return -1


func _place_rows() -> void:
	var box: Rect2 = paper()
	for i in labels.size():
		(labels[i] as Label).position = Vector2(box.position.x + Bubble.PAD.x,
			box.position.y + Bubble.PAD.y + i * (row_size.y + ROW_GAP))
	queue_redraw()


func _process(_delta: float) -> void:
	var under: int = row_at(get_local_mouse_position())
	if under != lit:
		lit = under
		queue_redraw()


func choose(i: int) -> void:
	if taken or i < 0 or i >= choices.size():
		return
	taken = true
	picked.emit(i)


func _input(event: InputEvent) -> void:
	if taken:
		return
	if event is InputEventKey and event.pressed and not event.is_echo():
		var key: int = (event as InputEventKey).keycode
		var place: int = -1
		if key >= KEY_1 and key <= KEY_9:
			place = key - KEY_1
		elif key >= KEY_KP_1 and key <= KEY_KP_9:
			place = key - KEY_KP_1
		if place >= 0 and place < choices.size():
			get_viewport().set_input_as_handled()
			choose(place)
		return
	var pressed_at: Variant = null
	if event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		pressed_at = (event as InputEventMouseButton).position
	elif event is InputEventScreenTouch and event.pressed:
		pressed_at = (event as InputEventScreenTouch).position
	if pressed_at == null:
		return
	var row: int = row_at(get_global_transform_with_canvas().affine_inverse() * (pressed_at as Vector2))
	if row >= 0:
		get_viewport().set_input_as_handled()
		choose(row)


func _draw() -> void:
	var box: Rect2 = paper()
	var style := StyleBoxFlat.new()
	style.bg_color = Bubble.PAPER
	style.border_color = Bubble.EDGE
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	draw_style_box(style, box)
	var tail := PackedVector2Array([Vector2(-Bubble.TAIL, Bubble.TAIL + 1.0), Vector2(Bubble.TAIL, Bubble.TAIL + 1.0), Vector2.ZERO])
	draw_colored_polygon(tail, Bubble.PAPER)
	draw_polyline(PackedVector2Array([Vector2(-Bubble.TAIL, Bubble.TAIL), Vector2.ZERO, Vector2(Bubble.TAIL, Bubble.TAIL)]), Bubble.EDGE, 1.0)
	if lit >= 0:
		draw_rect(row_rect(lit), LIT)
