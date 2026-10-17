# hourschart.gd - players online by hour of the day, in this computer's
# hours (0.50.0, the Lands window).
#
# The owner's "time zones (when each land is usually busy)": the server keeps
# who is online every five minutes (online_samples) and the insights average
# them by hour of the day, in UTC, over two weeks. This turns them to this
# computer's hours and draws them as 24 bars, with a hover that says the hour
# and the average.
#
# The data-viz way: one series, so no legend box (the window's line names
# it); bars no thicker than 24 px, rounded at the top and square at the
# baseline, a 2 px gap between them; hairline grid; the highest bar labelled,
# the rest on hover; text in text colours.
class_name HoursChart
extends Control


const SURFACE := Color("#12161d")
const GRID := Color("#262c35")
const TEXT := Color("#e6e9ee")
const MUTED := Color("#9aa3af")
const BAR := Color("#3987e5")
const BAR_HOVER := Color("#6aa6ee")
const PAD_LEFT := 30.0
const PAD_RIGHT := 8.0
const PAD_TOP := 14.0
const PAD_BOTTOM := 18.0
const FONT_SIZE := 11
const MOST_BAR := 24.0

# Players online on average, by this computer's hour of the day, 0-23.
var players: Array[float] = []
var hover: int = -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_exited.connect(func() -> void:
		hover = -1
		queue_redraw())


static func to_local(by_utc_hour: Variant, bias_minutes: int) -> Array[float]:
	"""The server's 24 averages (UTC hours) as this computer's hours: local
	hour h is UTC hour h less the offset, to the nearest hour."""
	var out: Array[float] = []
	out.resize(24)
	out.fill(0.0)
	if not (by_utc_hour is Array) or (by_utc_hour as Array).size() != 24:
		return out
	var shift: int = roundi(bias_minutes / 60.0)
	for hour in 24:
		out[hour] = maxf(0.0, float(by_utc_hour[posmod(hour - shift, 24)]))
	return out


static func local_hour(utc_hour: int, bias_minutes: int) -> String:
	"""A UTC hour of the day as this computer's clock: '20:00', '05:30'."""
	var minutes: int = posmod(utc_hour * 60 + bias_minutes, 1440)
	@warning_ignore("integer_division")
	return "%02d:%02d" % [minutes / 60, minutes % 60]


static func top_of(values: Array[float]) -> float:
	"""The axis top: the most, rounded up to a whole player (1 at least), so
	the line halfway is a clean number too."""
	var most: float = 0.0
	for value in values:
		most = maxf(most, value)
	return maxf(1.0, ceilf(most))


func show_hours(by_utc_hour: Variant, bias_minutes: int) -> void:
	players = to_local(by_utc_hour, bias_minutes)
	hover = -1
	queue_redraw()


func _plot() -> Rect2:
	return Rect2(PAD_LEFT, PAD_TOP, maxf(1.0, size.x - PAD_LEFT - PAD_RIGHT), maxf(1.0, size.y - PAD_TOP - PAD_BOTTOM))


func _bar_rect(hour: int, top: float, plot: Rect2) -> Rect2:
	var slot: float = plot.size.x / 24.0
	var wide: float = minf(MOST_BAR, slot - 2.0)
	var tall: float = (players[hour] / top) * plot.size.y
	return Rect2(plot.position.x + slot * hour + (slot - wide) / 2.0, plot.end.y - tall, wide, tall)


func _draw() -> void:
	var font: Font = get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), SURFACE)
	var plot: Rect2 = _plot()
	if players.size() != 24:
		return
	var top: float = top_of(players)
	for step in 3:
		var value: float = top * step / 2.0
		var y: float = plot.end.y - (value / top) * plot.size.y
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), GRID, 1.0)
		draw_string(font, Vector2(2.0, y + 4.0), _short(value), HORIZONTAL_ALIGNMENT_RIGHT, PAD_LEFT - 6.0, FONT_SIZE, MUTED)
	var most: int = 0
	for hour in 24:
		if players[hour] > players[most]:
			most = hour
		var bar: Rect2 = _bar_rect(hour, top, plot)
		if bar.size.y < 0.5:
			continue
		var style := StyleBoxFlat.new()
		style.bg_color = BAR_HOVER if hour == hover else BAR
		var round_top: int = int(minf(4.0, bar.size.y))
		style.corner_radius_top_left = round_top
		style.corner_radius_top_right = round_top
		draw_style_box(style, bar)
	for hour in [0, 6, 12, 18]:
		var slot: float = plot.size.x / 24.0
		draw_string(font, Vector2(plot.position.x + slot * hour, plot.end.y + 14.0), "%02d:00" % hour,
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, MUTED)
	if players[most] > 0.0 and hover < 0:
		var peak: Rect2 = _bar_rect(most, top, plot)
		draw_string(font, Vector2(peak.position.x - 4.0, peak.position.y - 3.0), _short(players[most]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT)
	if hover >= 0:
		var words: String = tooltip(hover)
		var wide: float = font.get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x + 14.0
		var at: Rect2 = _bar_rect(hover, top, plot)
		var box := Rect2(clampf(at.position.x - wide / 2.0, 2.0, size.x - wide - 2.0), 1.0, wide, 20.0)
		draw_rect(box, Color(0.04, 0.05, 0.07, 0.95))
		draw_rect(box, GRID, false, 1.0)
		draw_string(font, box.position + Vector2(7.0, 14.0), words, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT)


func tooltip(hour: int) -> String:
	"""'20:00-21:00: 1.4 players on average'."""
	return "%02d:00-%02d:00: %s player%s on average" % [hour, (hour + 1) % 24, _short(players[hour]),
		"" if is_equal_approx(players[hour], 1.0) else "s"]


static func _short(value: float) -> String:
	var text: String = "%.1f" % value
	return text.trim_suffix(".0")


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and players.size() == 24:
		var plot: Rect2 = _plot()
		var x: float = (event as InputEventMouseMotion).position.x
		var index: int = clampi(int((x - plot.position.x) / plot.size.x * 24.0), 0, 23) \
			if x >= plot.position.x and x <= plot.end.x else -1
		if index != hover:
			hover = index
			queue_redraw()


func busiest() -> Array[int]:
	"""The three hours with the most on average, most first - [] when nobody
	was counted."""
	var order: Array[int] = []
	for hour in 24:
		if players[hour] > 0.0:
			order.append(hour)
	order.sort_custom(func(a: int, b: int) -> bool: return players[a] > players[b] or (players[a] == players[b] and a < b))
	var out: Array[int] = []
	for hour in order:
		if out.size() < 3:
			out.append(hour)
	return out
