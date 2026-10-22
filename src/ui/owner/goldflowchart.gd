# goldflowchart.gd - gold minted against gold burned, day by day, with the net
# (0.74.0, the GM panel's Economy tab).
#
# The owner: "A daily report of where gold comes from and where it goes, by
# source." The server reads it off the ledger (GET /api/owner/economy/flow);
# this draws its days:
#
#   - MINTED as a column UP from the zero line, BURNED as a column DOWN from
#     it, one day a column - the same gold on the same axis, so a day that
#     printed more than it destroyed has the taller column above the line
#   - THE NET as a line through the days (a dot on each while there is room),
#     in a neutral ink: it is minted less burned, not a third kind of gold
#   - a legend, so identity is never colour alone; hover says the day and its
#     three numbers
#
# Why not OnlineChart or HoursChart: those count people, from zero up. This is
# gold that both appears and vanishes, and the one honest picture of that is
# one axis with zero in the middle of it.
#
# Drawn the data-viz way, the house's other two charts' way: one axis, clean
# compact ticks, hairline grid, columns no wider than 24 px with a 4 px round
# data end and a square foot on the zero line, a 2 px surface gap between
# days, text in text colours. The two colours are OnlineChart's (blue #3987e5,
# orange #d95926 on #12161d), checked again for this pair: colour-blind
# separation dE 26.8, contrast above 3:1 on the surface.
class_name GoldFlowChart
extends Control


const SURFACE := Color("#12161d")
const GRID := Color("#262c35")
const ZERO := Color("#3a424e")
const TEXT := Color("#e6e9ee")
const MUTED := Color("#9aa3af")
const MINTED := Color("#3987e5")
const BURNED := Color("#d95926")
const NET := Color("#c9ced6")
const PAD_LEFT := 34.0
const PAD_RIGHT := 6.0
const PAD_TOP := 22.0
const PAD_BOTTOM := 18.0
const FONT_SIZE := 11
const MOST_BAR := 24.0
const GAP := 2.0
# A dot on every day only while the days are far enough apart to hold one.
const DOTS_FROM := 10.0

# One per day, oldest first, as the server sends them: {day, start, minted,
# burned, net}.
var days: Array[Dictionary] = []
# The day under the mouse, or -1.
var hover: int = -1

var _up_style: StyleBoxFlat
var _down_style: StyleBoxFlat


func _init() -> void:
	custom_minimum_size = Vector2(250, 94)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_up_style = _bar_style(MINTED, true)
	_down_style = _bar_style(BURNED, false)


func _ready() -> void:
	mouse_exited.connect(func() -> void:
		hover = -1
		queue_redraw())


static func _bar_style(colour: Color, rounded_top: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = colour
	style.anti_aliasing = true
	if rounded_top:
		style.corner_radius_top_left = 4
		style.corner_radius_top_right = 4
	else:
		style.corner_radius_bottom_left = 4
		style.corner_radius_bottom_right = 4
	return style


func show_days(from_server: Variant) -> void:
	"""The flow's "days" for one currency, checked: a row that is not a
	dictionary is dropped, and a number that is not a number is 0."""
	days = []
	if from_server is Array:
		for row in from_server:
			if not (row is Dictionary):
				continue
			days.append({"day": str(row.get("day", "")), "start": int(row.get("start", 0)),
				"minted": maxi(0, int(row.get("minted", 0))), "burned": maxi(0, int(row.get("burned", 0))),
				"net": int(row.get("minted", 0)) - int(row.get("burned", 0))})
	hover = -1
	queue_redraw()


static func nice(top: int) -> int:
	"""The clean number an axis ends at, at or above `top`: 1, 2, 5 and their
	tens - 0 stays 0."""
	if top <= 0:
		return 0
	var power: float = pow(10.0, floorf(log(float(top)) / log(10.0)))
	for step in [1.0, 2.0, 5.0, 10.0]:
		if float(top) <= step * power:
			return roundi(step * power)
	return roundi(10.0 * power)


static func compact(amount: int) -> String:
	"""A tick's number: 900, 1.2K, 12K, 3.4M."""
	var size_of: int = absi(amount)
	var minus: String = "-" if amount < 0 else ""
	if size_of < 1000:
		return str(amount)
	if size_of < 1000000:
		var thousands: float = size_of / 1000.0
		return minus + (("%.1fK" % thousands).replace(".0K", "K") if thousands < 10.0 else "%dK" % roundi(thousands))
	var millions: float = size_of / 1000000.0
	return minus + (("%.1fM" % millions).replace(".0M", "M") if millions < 10.0 else "%dM" % roundi(millions))


func scale() -> Vector2i:
	"""(the top of the axis, how far below zero it goes), both clean."""
	var most_up: int = 0
	var most_down: int = 0
	for row in days:
		most_up = maxi(most_up, int(row["minted"]))
		most_down = maxi(most_down, int(row["burned"]))
	return Vector2i(nice(most_up), nice(most_down))


func _plot() -> Rect2:
	return Rect2(PAD_LEFT, PAD_TOP, maxf(1.0, size.x - PAD_LEFT - PAD_RIGHT), maxf(1.0, size.y - PAD_TOP - PAD_BOTTOM))


func _y_of(value: float, axis: Vector2i, plot: Rect2) -> float:
	"""Up is minted, down is burned; zero where their two spans meet."""
	var span: float = float(maxi(1, axis.x + axis.y))
	var zero_y: float = plot.position.y + plot.size.y * float(axis.x) / span
	if axis.x + axis.y == 0:
		zero_y = plot.position.y + plot.size.y * 0.5
	return zero_y - value / span * plot.size.y


func _slot(plot: Rect2) -> float:
	return plot.size.x / float(maxi(1, days.size()))


func _draw() -> void:
	var font: Font = get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), SURFACE)
	var plot: Rect2 = _plot()
	_draw_legend(font)
	if days.is_empty():
		draw_string(font, plot.position + Vector2(0, plot.size.y / 2.0), "Nothing read yet.",
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, MUTED)
		return
	var axis: Vector2i = scale()
	if axis == Vector2i.ZERO:
		draw_string(font, plot.position + Vector2(0, plot.size.y / 2.0), "No gold moved in these days.",
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, MUTED)
		return
	# The grid: the top, zero and the bottom, with their numbers.
	var zero_y: float = _y_of(0.0, axis, plot)
	for mark in [[float(axis.x), compact(axis.x)], [-float(axis.y), compact(-axis.y)]]:
		if is_zero_approx(float(mark[0])):
			continue
		var y: float = _y_of(float(mark[0]), axis, plot)
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), GRID, 1.0)
		draw_string(font, Vector2(2.0, y + 4.0), str(mark[1]), HORIZONTAL_ALIGNMENT_RIGHT, PAD_LEFT - 6.0, FONT_SIZE, MUTED)
	draw_string(font, Vector2(2.0, zero_y + 4.0), "0", HORIZONTAL_ALIGNMENT_RIGHT, PAD_LEFT - 6.0, FONT_SIZE, MUTED)
	# The columns, a surface gap between days, the foot square on zero.
	var slot: float = _slot(plot)
	var wide: float = clampf(slot - GAP, 1.0, MOST_BAR)
	for i in days.size():
		var x: float = plot.position.x + slot * i + (slot - wide) / 2.0
		var up: float = zero_y - _y_of(float(days[i]["minted"]), axis, plot)
		var down: float = _y_of(-float(days[i]["burned"]), axis, plot) - zero_y
		if hover == i:
			draw_rect(Rect2(plot.position.x + slot * i, plot.position.y, slot, plot.size.y), Color(1, 1, 1, 0.06))
		_bar(Rect2(x, zero_y - up, wide, up), true)
		_bar(Rect2(x, zero_y, wide, down), false)
	draw_line(Vector2(plot.position.x, zero_y), Vector2(plot.end.x, zero_y), ZERO, 1.0)
	# The net: a line through the days, ringed dots while there is room.
	var points := PackedVector2Array()
	for i in days.size():
		points.append(Vector2(plot.position.x + slot * (i + 0.5), _y_of(float(days[i]["net"]), axis, plot)))
	if points.size() > 1:
		draw_polyline(points, NET, 2.0, true)
	for i in points.size():
		if slot >= DOTS_FROM or i == points.size() - 1 or i == hover:
			draw_circle(points[i], 6.0, SURFACE)
			draw_circle(points[i], 4.0, NET)
	# The days: the first, the last, and the middle when there is room.
	var named: Array[int] = [0, days.size() - 1]
	if days.size() >= 5:
		named.insert(1, floori(days.size() / 2.0))
	for i in named:
		var label: String = short_day(str(days[i]["day"]))
		var label_wide: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		var at_x: float = clampf(plot.position.x + slot * (i + 0.5) - label_wide / 2.0, plot.position.x,
			plot.end.x - label_wide)
		draw_string(font, Vector2(at_x, plot.end.y + 14.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, MUTED)
	if hover >= 0 and hover < days.size():
		_draw_hover(font, plot, points[hover])


func _bar(rect: Rect2, up: bool) -> void:
	if rect.size.y < 0.5:
		return
	var style: StyleBoxFlat = _up_style if up else _down_style
	# The round end no larger than the column can hold.
	var radius: int = clampi(floori(minf(rect.size.x, rect.size.y * 2.0) / 2.0), 0, 4)
	if up:
		style.corner_radius_top_left = radius
		style.corner_radius_top_right = radius
	else:
		style.corner_radius_bottom_left = radius
		style.corner_radius_bottom_right = radius
	draw_style_box(style, rect)


func _draw_legend(font: Font) -> void:
	var x_at: float = PAD_LEFT
	for key in [[MINTED, "Minted", "bar"], [BURNED, "Burned", "bar"], [NET, "Net", "dot"]]:
		if key[2] == "bar":
			draw_rect(Rect2(x_at, 5.0, 10.0, 10.0), key[0])
		else:
			draw_line(Vector2(x_at - 2.0, 10.0), Vector2(x_at + 12.0, 10.0), key[0], 2.0)
			draw_circle(Vector2(x_at + 5.0, 10.0), 4.0, key[0])
		draw_string(font, Vector2(x_at + 15.0, 14.0), key[1], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT)
		x_at += 24.0 + font.get_string_size(key[1], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x


func _draw_hover(font: Font, plot: Rect2, point: Vector2) -> void:
	var lines: Array[String] = tooltip_lines(hover)
	var wide: float = 0.0
	for line in lines:
		wide = maxf(wide, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x)
	var box := Rect2(point.x + 10.0, plot.position.y + 2.0, wide + 14.0, 15.0 * lines.size() + 8.0)
	if box.end.x > size.x - 2.0:
		box.position.x = point.x - 10.0 - box.size.x
	box.position.x = maxf(2.0, box.position.x)
	draw_rect(box, Color(0.04, 0.05, 0.07, 0.95))
	draw_rect(box, GRID, false, 1.0)
	for i in lines.size():
		draw_string(font, box.position + Vector2(7.0, 16.0 + 15.0 * i), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1,
			FONT_SIZE, TEXT if i == 0 else MUTED)


func tooltip_lines(index: int) -> Array[String]:
	"""'Oct 22 (UTC)', 'Minted 1,234', 'Burned 900', 'Net +334'."""
	if index < 0 or index >= days.size():
		return []
	var row: Dictionary = days[index]
	var net: int = int(row["net"])
	return [short_day(str(row["day"])) + " (UTC)", "Minted %s" % GameConstants.commas(int(row["minted"])),
		"Burned %s" % GameConstants.commas(int(row["burned"])),
		"Net %s%s" % ["+" if net > 0 else ("-" if net < 0 else ""), GameConstants.commas(absi(net))]]


static func short_day(day: String) -> String:
	"""'2026-10-22' -> 'Oct 22'. Anything else as it came."""
	var parts: PackedStringArray = day.split("-")
	if parts.size() != 3 or not parts[1].is_valid_int() or not parts[2].is_valid_int():
		return day
	var month: int = parts[1].to_int()
	if month < 1 or month > 12:
		return day
	return "%s %d" % [["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][month - 1],
		parts[2].to_int()]


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and not days.is_empty():
		var index: int = day_under((event as InputEventMouseMotion).position.x)
		if index != hover:
			hover = index
			queue_redraw()


func day_under(x: float) -> int:
	"""The day whose column `x` is in, or -1 off the plot."""
	var plot: Rect2 = _plot()
	if x < plot.position.x or x > plot.end.x or days.is_empty():
		return -1
	return clampi(int((x - plot.position.x) / _slot(plot)), 0, days.size() - 1)
