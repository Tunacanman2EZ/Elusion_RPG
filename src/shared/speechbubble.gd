# speechbubble.gd - words over somebody's head, a line at a time (0.132.0).
#
# The owner, 5 Nov: "the thing im missing is background scenes so my
# alternative is to use chat bubbles", then the shopkeeper's first lines, and
# "we can make multiple chat bubbles for when a player walks in again". The
# world is the background: a bubble is said where the character stands.
#
# say(over, lines, at) puts a bubble on `over` (a child, so it moves with
# them and goes when they go), `at` from their origin - the tail's tip. Each
# line types out (TYPE_RATE letters a second), stays READ_SECONDS plus
# PER_LETTER a letter, and gives way to the next; after the last the bubble
# fades and frees itself. Drawn over the room (Z), in world pixels at SCALE so
# the words stay sharp at every camera zoom.
#
# times_said(key) / note_said(key): how often a character has been greeted
# by somebody, kept beside the stories in the seen file (ControlsPanel's
# seen_path, section "talk"), so a sequence of greetings goes on where it was.
#
# No class_name: preload it by path.
extends Node2D

signal finished()

const TYPE_RATE := 40.0
const READ_SECONDS := 1.4
const PER_LETTER := 0.045
const FADE_SECONDS := 0.3
const Z := 60
const SCALE := 0.4
const FONT_SIZE := 16
const MAX_WIDTH := 250.0
const PAD := Vector2(5.0, 3.0)
const TAIL := 4.0
const PAPER := Color(0.97, 0.93, 0.82, 0.96)
const INK := Color(0.16, 0.11, 0.07)
const EDGE := Color(0.32, 0.22, 0.12)

var lines: Array = []
var line_index: int = 0
var label: Label = null
var _shown: float = 0.0
var _held: float = 0.0
var _fading: float = -1.0
# The line's words, laid out: their size in the label's own pixels.
var words_size: Vector2 = Vector2.ZERO


static func say(over: Node2D, said: Array, at: Vector2) -> Node2D:
	"""A bubble over `over`, its tail's tip at `at`, saying `said` in turn."""
	var bubble: Node2D = (load("res://src/shared/speechbubble.gd") as GDScript).new()
	bubble.name = "speechbubble"
	bubble.set("lines", said.duplicate())
	bubble.position = at
	over.add_child(bubble)
	bubble.reset_physics_interpolation()
	return bubble


static func times_said(key: String) -> int:
	var cfg := ConfigFile.new()
	if cfg.load(ControlsPanel.seen_path) != OK:
		return 0
	return int(cfg.get_value("talk", key.replace("/", "|"), 0))


static func note_said(key: String) -> void:
	var cfg := ConfigFile.new()
	# READ THEN WRITE, so the stories and every other character survive.
	cfg.load(ControlsPanel.seen_path)
	var k: String = key.replace("/", "|")
	cfg.set_value("talk", k, int(cfg.get_value("talk", k, 0)) + 1)
	cfg.save(ControlsPanel.seen_path)


func _ready() -> void:
	z_index = Z
	z_as_relative = false
	label = Label.new()
	label.name = "words"
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", INK)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Laid out for the whole line before it types, so a word never jumps to
	# the next row half way through.
	label.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.scale = Vector2(SCALE, SCALE)
	add_child(label)
	_show_line()


func _show_line() -> void:
	if line_index >= lines.size():
		_fading = FADE_SECONDS
		return
	var text: String = str(lines[line_index])
	label.text = text
	label.visible_characters = 0
	_shown = 0.0
	_held = 0.0
	# As wide as the line wants, up to MAX_WIDTH, then wrapped - the paper as
	# tall as the label's own rows (a wrapped Label's size can keep the
	# height of a narrower layout).
	var font: Font = label.get_theme_font("font")
	var width: float = minf(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x + 2.0, MAX_WIDTH)
	label.custom_minimum_size = Vector2(width, 0.0)
	label.size = Vector2(width, 0.0)
	var rows: int = maxi(label.get_line_count(), 1)
	var tall: float = rows * label.get_line_height() + (rows - 1) * label.get_theme_constant("line_spacing")
	words_size = Vector2(width, tall)
	label.size = words_size
	queue_redraw()


func _process(delta: float) -> void:
	if _fading >= 0.0:
		_fading -= delta
		modulate.a = clampf(_fading / FADE_SECONDS, 0.0, 1.0)
		if _fading <= 0.0:
			finished.emit()
			queue_free()
		return
	if lines.is_empty():
		_fading = 0.0
		return
	var letters: int = str(lines[line_index]).length()
	if label.visible_characters < letters and label.visible_characters >= 0:
		_shown += delta * TYPE_RATE
		label.visible_characters = mini(int(_shown), letters)
		if label.visible_characters >= letters:
			label.visible_characters = -1
		return
	_held += delta
	if _held >= READ_SECONDS + PER_LETTER * letters:
		line_index += 1
		_show_line()


func box() -> Rect2:
	"""The paper, in this node's pixels: centred over the tail's tip."""
	var words: Vector2 = words_size * SCALE
	var size: Vector2 = words + PAD * 2.0
	return Rect2(Vector2(-size.x / 2.0, -TAIL - size.y), size)


func _draw() -> void:
	if label == null:
		return
	var paper: Rect2 = box()
	label.position = paper.position + PAD
	label.size = words_size
	var style := StyleBoxFlat.new()
	style.bg_color = PAPER
	style.border_color = EDGE
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	draw_style_box(style, paper)
	var tail := PackedVector2Array([Vector2(-TAIL, -TAIL - 1.0), Vector2(TAIL, -TAIL - 1.0), Vector2(0.0, 0.0)])
	draw_colored_polygon(tail, PAPER)
	draw_polyline(PackedVector2Array([Vector2(-TAIL, -TAIL), Vector2(0.0, 0.0), Vector2(TAIL, -TAIL)]), EDGE, 1.0)
