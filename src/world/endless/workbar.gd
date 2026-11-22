# workbar.gd - a thin bar of how full something is, drawn in code (0.175.1):
# the Testing Ground's work against the frame's budget, a sweep's progress,
# how many of a monster fit. The owner, of the Testing Ground's panel:
# "upgrade this ui".
#
# `fraction` fills it (0 to 1, more is drawn full), in `colour`; `marker`, if
# 0 or more, is a second value drawn as a short bright line (the slow frames);
# `tick`, if 0 or more, a fixed line across it (the 80% limit). As RISE it is
# a small upward triangle instead: a cost that grows with the crowd.
#
# No class_name: preload it by path.
extends Control

enum Shape { BAR, RISE }

# The work's colours, the Testing Ground's since 0.151.1: green under
# AMBER_AT of the budget, amber to it, red past it.
const GREEN := Color(0.55, 0.9, 0.5)
const AMBER := Color(1.0, 0.72, 0.35)
const RED := Color(1.0, 0.42, 0.38)
const AMBER_AT := 0.8
const BACK := Color(1.0, 1.0, 1.0, 0.08)
# The panel's gold and its text (testingground.gd COLOUR, COLOUR_TEXT).
const GOLD := Color(1.0, 0.86, 0.5)
const TEXT := Color(0.92, 0.88, 0.8)
const DARK_TEXT := Color(0.16, 0.1, 0.04)
const TICK := Color(1.0, 1.0, 1.0, 0.55)

var shape: int = Shape.BAR
var fraction: float = 0.0
var marker: float = -1.0
var tick: float = -1.0
var colour: Color = GREEN


static func make(height: float, wide: float = 0.0) -> Control:
	var bar: Control = (load("res://src/world/endless/workbar.gd") as GDScript).new()
	bar.custom_minimum_size = Vector2(wide, height)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wide <= 0.0:
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return bar


static func work_colour(median: float, p95: float, budget: float) -> Color:
	"""Green, amber or red for a frame's work: by the worse of the median and
	the slow ones (the 95th percentile) against `budget`."""
	var worst: float = maxf(median, p95)
	if worst > budget:
		return RED
	if worst > budget * AMBER_AT:
		return AMBER
	return GREEN


static func dress_choice(button: Button) -> void:
	"""One of a row of choices: the one chosen lit gold, so what is on reads
	at a glance (the Testing Ground's horde, 0.175.1)."""
	var plain := StyleBoxFlat.new()
	plain.bg_color = Color(1.0, 1.0, 1.0, 0.05)
	plain.border_color = Color(GOLD, 0.25)
	plain.set_border_width_all(1)
	plain.set_corner_radius_all(3)
	plain.set_content_margin_all(3.0)
	plain.content_margin_left = 7.0
	plain.content_margin_right = 7.0
	var hover: StyleBoxFlat = plain.duplicate()
	hover.bg_color = Color(1.0, 1.0, 1.0, 0.12)
	var lit: StyleBoxFlat = plain.duplicate()
	lit.bg_color = Color(GOLD, 0.9)
	lit.border_color = GOLD
	var held: StyleBoxFlat = plain.duplicate()
	held.bg_color = Color(1.0, 1.0, 1.0, 0.02)
	held.border_color = Color(GOLD, 0.1)
	button.add_theme_stylebox_override("normal", plain)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", lit)
	button.add_theme_stylebox_override("hover_pressed", lit)
	button.add_theme_stylebox_override("disabled", held)
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", DARK_TEXT)
	button.add_theme_color_override("font_hover_pressed_color", DARK_TEXT)


static func dress_go(button: Button, running: bool) -> void:
	"""Find the limit green while nothing runs, Stop red while a sweep does."""
	var look := StyleBoxFlat.new()
	look.bg_color = Color(0.62, 0.2, 0.16, 0.95) if running else Color(0.22, 0.46, 0.22, 0.95)
	look.border_color = look.bg_color.lightened(0.35)
	look.set_border_width_all(1)
	look.set_corner_radius_all(3)
	look.set_content_margin_all(3.0)
	look.content_margin_left = 9.0
	look.content_margin_right = 9.0
	var hover: StyleBoxFlat = look.duplicate()
	hover.bg_color = look.bg_color.lightened(0.15)
	button.add_theme_stylebox_override("normal", look)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", look)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)


static func row_look(odd: bool) -> StyleBoxFlat:
	"""A table row's back: every other one a shade lighter."""
	var look := StyleBoxFlat.new()
	look.bg_color = Color(1.0, 1.0, 1.0, 0.05 if odd else 0.0)
	look.set_corner_radius_all(2)
	look.content_margin_left = 4.0
	look.content_margin_right = 4.0
	look.content_margin_top = 1.0
	look.content_margin_bottom = 1.0
	return look


func show_value(full: float, colour_now: Color, marker_at: float = -1.0, tick_at: float = -1.0) -> void:
	"""Drawn again only when something changed."""
	if is_equal_approx(full, fraction) and colour_now == colour and is_equal_approx(marker_at, marker) \
			and is_equal_approx(tick_at, tick):
		return
	fraction = full
	colour = colour_now
	marker = marker_at
	tick = tick_at
	queue_redraw()


func _draw() -> void:
	if shape == Shape.RISE:
		var w: float = size.x
		var h: float = size.y
		draw_colored_polygon(PackedVector2Array([Vector2(w * 0.5, 0.0), Vector2(w, h), Vector2(0.0, h)]), colour)
		return
	draw_rect(Rect2(Vector2.ZERO, size), BACK)
	var filled: float = size.x * clampf(fraction, 0.0, 1.0)
	if filled > 0.0:
		draw_rect(Rect2(0.0, 0.0, filled, size.y), colour)
	if marker >= 0.0:
		var x: float = clampf(size.x * marker, 1.0, size.x - 1.0)
		draw_line(Vector2(x, 0.0), Vector2(x, size.y), colour.lightened(0.45), 2.0)
	if tick >= 0.0:
		var x: float = roundf(size.x * clampf(tick, 0.0, 1.0)) + 0.5
		draw_line(Vector2(x, -2.0), Vector2(x, size.y + 2.0), TICK, 1.0)
