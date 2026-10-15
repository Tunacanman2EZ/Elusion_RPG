# onlinechart.gd - who was online, against time, with the events on it
# (0.49.0, the Event report window).
#
# The owner's: "player count online vs time". The server counts who is online
# once a minute and keeps the most it saw in each five minutes (the API's
# events/ package, online_samples); the report hands over the last seven days
# of those rows, and this draws them:
#
#   - two lines: PLAYERS (the player rank, the owner and co-owners left out)
#     and EVERYONE (staff too), with a legend - identity is never colour alone
#   - each event that was on as a pale band, named where the name fits
#   - hover: a crosshair, and the time, both counts and the events on then
#
# A five minutes with no row is nobody: an open game polls. Before the counting
# began there are no rows either, and the chart says from when it counts.
#
# Drawn the data-viz way: one axis, whole-number ticks, hairline grid, 2px
# lines, the players' line with a faint wash under it, text in text colours
# (never the series colour), an 8px end dot ringed in the surface colour. The
# two series colours were checked for colour-blind separation and contrast on
# this surface (blue #3987e5, orange #d95926 on #12161d).
class_name OnlineChart
extends Control


const SURFACE := Color("#12161d")
const GRID := Color("#262c35")
const TEXT := Color("#e6e9ee")
const MUTED := Color("#9aa3af")
const PLAYERS := Color("#3987e5")
const EVERYONE := Color("#d95926")
const BAND := Color(1.0, 1.0, 1.0, 0.06)
const BAND_HOVER := Color(1.0, 1.0, 1.0, 0.1)
const PAD_LEFT := 30.0
const PAD_RIGHT := 26.0
const PAD_TOP := 24.0
const PAD_BOTTOM := 20.0
const FONT_SIZE := 11

# The buckets, oldest first: one per `step` seconds from `from_at`.
var from_at: int = 0
var step: int = 300
var players: Array[int] = []
var everyone: Array[int] = []
# The events on in the time drawn: {start, end, name}.
var bands: Array[Dictionary] = []
# When the counting began (0: not known).
var counting_since: int = 0
# The bucket under the mouse, or -1.
var hover: int = -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_exited.connect(func() -> void:
		hover = -1
		queue_redraw())


static func fill(online: Variant, start: int, end: int, every: int) -> Dictionary:
	"""The rows the server sent, as two arrays one bucket each - a bucket with
	no row is 0. {"players": [...], "everyone": [...]}."""
	var count: int = maxi(0, ceili(float(end - start) / float(maxi(1, every))))
	var out_players: Array[int] = []
	var out_everyone: Array[int] = []
	out_players.resize(count)
	out_everyone.resize(count)
	out_players.fill(0)
	out_everyone.fill(0)
	if online is Array:
		for row in online:
			if not (row is Dictionary):
				continue
			@warning_ignore("integer_division")
			var index: int = (int(row.get("at", 0)) - start) / maxi(1, every)
			if index < 0 or index >= count:
				continue
			out_players[index] = maxi(0, int(row.get("players", 0)))
			out_everyone[index] = maxi(0, int(row.get("everyone", 0)))
	return {"players": out_players, "everyone": out_everyone}


func show_online(data: Dictionary) -> void:
	"""The report's "online", "chart_from", "sample_seconds" and events."""
	step = maxi(60, int(data.get("sample_seconds", 300)))
	var now: int = int(data.get("now", 0))
	from_at = int(data.get("chart_from", now - 7 * 86400))
	var filled: Dictionary = fill(data.get("online", []), from_at, now, step)
	players = filled["players"]
	everyone = filled["everyone"]
	counting_since = int(data.get("sampling_since", 0))
	bands = []
	var events: Variant = data.get("events", [])
	if events is Array:
		for event in events:
			if event is Dictionary and int(event.get("ended_at", event.get("ends_at", 0))) > from_at:
				bands.append({"start": maxi(from_at, int(event.get("starts_at", 0))),
					"end": mini(now, int(event.get("ended_at", event.get("ends_at", 0)))),
					"name": str(event.get("name", ""))})
	hover = -1
	queue_redraw()


func peak() -> int:
	var most: int = 0
	for value in everyone:
		most = maxi(most, value)
	for value in players:
		most = maxi(most, value)
	return most


static func ticks(top: int) -> Array[int]:
	"""Whole-number ticks from 0 to at least `top`: every one up to 5, then
	about four steps."""
	var out: Array[int] = []
	var most: int = maxi(1, top)
	var every: int = 1 if most <= 5 else ceili(most / 4.0)
	var at: int = 0
	while true:
		out.append(at)
		if at >= most:
			break
		at += every
	return out


func _plot() -> Rect2:
	return Rect2(PAD_LEFT, PAD_TOP, maxf(1.0, size.x - PAD_LEFT - PAD_RIGHT), maxf(1.0, size.y - PAD_TOP - PAD_BOTTOM))


func _x_of(at: int, plot: Rect2) -> float:
	var span: float = float(maxi(1, players.size() * step))
	return plot.position.x + clampf(float(at - from_at) / span, 0.0, 1.0) * plot.size.x


func _y_of(value: float, top: int, plot: Rect2) -> float:
	return plot.end.y - (value / float(maxi(1, top))) * plot.size.y


func value_at(y: float, top: int, plot: Rect2) -> int:
	"""The count a point on a line stands for - _y_of() backwards."""
	return roundi((plot.end.y - y) / maxf(1.0, plot.size.y) * float(maxi(1, top)))


func _columns(values: Array[int], plot: Rect2) -> PackedVector2Array:
	"""The line's points: one per two pixels, each the most in the buckets it
	covers, so a short visit is not drawn away."""
	var points := PackedVector2Array()
	if values.is_empty():
		return points
	var top: int = ticks(peak()).back()
	var columns: int = maxi(2, int(plot.size.x / 2.0))
	for column in columns:
		var first: int = int(float(column) / columns * values.size())
		var last: int = maxi(first + 1, int(float(column + 1) / columns * values.size()))
		var most: int = 0
		for i in range(first, mini(last, values.size())):
			most = maxi(most, values[i])
		points.append(Vector2(plot.position.x + (float(column) + 0.5) / columns * plot.size.x,
			_y_of(float(most), top, plot)))
	return points


func _draw() -> void:
	var font: Font = get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), SURFACE)
	var plot: Rect2 = _plot()
	if players.is_empty():
		draw_string(font, plot.position + Vector2(0, plot.size.y / 2.0), "Nothing counted yet.",
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, MUTED)
		return
	var marks: Array[int] = ticks(peak())
	var top: int = marks.back()
	# The events, under everything.
	for band in bands:
		var left: float = _x_of(int(band["start"]), plot)
		var right: float = _x_of(int(band["end"]), plot)
		if right - left < 1.0:
			right = left + 1.0
		var on: bool = hover >= 0 and from_at + hover * step >= int(band["start"]) and from_at + hover * step < int(band["end"])
		draw_rect(Rect2(left, plot.position.y, right - left, plot.size.y), BAND_HOVER if on else BAND)
		var words: String = str(band["name"])
		var wide: float = font.get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE - 1).x
		if wide + 6.0 <= right - left:
			draw_string(font, Vector2(left + 3.0, plot.position.y + 12.0), words, HORIZONTAL_ALIGNMENT_LEFT, -1,
				FONT_SIZE - 1, MUTED)
	# Before the counting began: say so, and draw nothing there.
	if counting_since > from_at:
		var since_x: float = _x_of(counting_since, plot)
		draw_rect(Rect2(plot.position.x, plot.position.y, since_x - plot.position.x, plot.size.y), Color(0, 0, 0, 0.25))
	# The grid and the counts.
	for value in marks:
		var y: float = _y_of(float(value), top, plot)
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), GRID, 1.0)
		draw_string(font, Vector2(4.0, y + 4.0), str(value), HORIZONTAL_ALIGNMENT_RIGHT, PAD_LEFT - 8.0, FONT_SIZE, MUTED)
	# The days, at this computer's midnights.
	var day_start: int = _next_midnight(from_at)
	var span_end: int = from_at + players.size() * step
	while day_start < span_end:
		var x: float = _x_of(day_start, plot)
		draw_line(Vector2(x, plot.end.y), Vector2(x, plot.end.y + 3.0), GRID, 1.0)
		var parts: Dictionary = LocalTime.parts(day_start)
		var label: String = "%s %d" % [LocalTime.WEEKDAYS[int(parts.get("weekday", 0)) % 7], int(parts.get("day", 1))]
		draw_string(font, Vector2(x + 3.0, plot.end.y + 14.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, MUTED)
		day_start += 86400
	# The lines: everyone behind, players in front with its wash.
	var all_line: PackedVector2Array = _columns(everyone, plot)
	var player_line: PackedVector2Array = _columns(players, plot)
	# A WASH ONLY OVER SOMETHING: a polygon flat on the baseline cannot be
	# filled, and the engine says so in red.
	if players.max() > 0:
		var wash := PackedVector2Array(player_line)
		wash.append(Vector2(player_line[player_line.size() - 1].x, plot.end.y))
		wash.append(Vector2(player_line[0].x, plot.end.y))
		draw_colored_polygon(wash, Color(PLAYERS, 0.1))
	draw_polyline(all_line, EVERYONE, 2.0, true)
	draw_polyline(player_line, PLAYERS, 2.0, true)
	# The end: a dot on each, and its number in text colour - the number the
	# line ends at (the most in its last two pixels), said once where the two
	# end together.
	var labelled: Array[float] = []
	for pair in [[all_line, EVERYONE], [player_line, PLAYERS]]:
		var line: PackedVector2Array = pair[0]
		var end: Vector2 = line[line.size() - 1]
		draw_circle(end, 6.0, SURFACE)
		draw_circle(end, 4.0, pair[1])
		if labelled.any(func(y: float) -> bool: return absf(y - end.y) < 10.0):
			continue
		labelled.append(end.y)
		draw_string(font, end + Vector2(8.0, 4.0), str(value_at(end.y, top, plot)), HORIZONTAL_ALIGNMENT_LEFT, -1,
			FONT_SIZE, TEXT)
	# The legend.
	var x_at: float = PAD_LEFT
	for key in [[PLAYERS, "Players"], [EVERYONE, "Everyone, staff too"]]:
		draw_line(Vector2(x_at, 11.0), Vector2(x_at + 14.0, 11.0), key[0], 2.0)
		draw_string(font, Vector2(x_at + 18.0, 15.0), key[1], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT)
		x_at += 26.0 + font.get_string_size(key[1], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	if hover >= 0 and hover < players.size():
		_draw_hover(font, plot, top)


func _draw_hover(font: Font, plot: Rect2, top: int) -> void:
	var at: int = from_at + hover * step
	var x: float = _x_of(at, plot) + (plot.size.x / players.size()) / 2.0
	draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), MUTED, 1.0)
	for pair in [[everyone, EVERYONE], [players, PLAYERS]]:
		var point := Vector2(x, _y_of(float((pair[0] as Array)[hover]), top, plot))
		draw_circle(point, 6.0, SURFACE)
		draw_circle(point, 4.0, pair[1])
	var lines: Array[String] = tooltip_lines(hover)
	var wide: float = 0.0
	for line in lines:
		wide = maxf(wide, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x)
	var box := Rect2(x + 10.0, plot.position.y + 4.0, wide + 14.0, 16.0 * lines.size() + 8.0)
	if box.end.x > size.x - 2.0:
		box.position.x = x - 10.0 - box.size.x
	draw_rect(box, Color(0.04, 0.05, 0.07, 0.95))
	draw_rect(box, GRID, false, 1.0)
	for i in lines.size():
		draw_string(font, box.position + Vector2(7.0, 17.0 + 16.0 * i), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1,
			FONT_SIZE, TEXT if i == 0 else MUTED)


func tooltip_lines(index: int) -> Array[String]:
	"""'Sat 14:05', 'Players 2 - everyone 3', and the events on then."""
	var at: int = from_at + index * step
	var out: Array[String] = [LocalTime.stamp(at, from_at + players.size() * step)]
	if counting_since > 0 and at < counting_since - step:
		out.append("Not counted yet")
		return out
	out.append("Players %d - everyone %d" % [players[index], everyone[index]])
	for band in bands:
		if at + step > int(band["start"]) and at < int(band["end"]):
			out.append(str(band["name"]))
	return out


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and not players.is_empty():
		var plot: Rect2 = _plot()
		var x: float = (event as InputEventMouseMotion).position.x
		var index: int = -1
		if x >= plot.position.x and x <= plot.end.x:
			index = bucket_under(x, plot)
		if index != hover:
			hover = index
			queue_redraw()


func bucket_under(x: float, plot: Rect2) -> int:
	"""The bucket the line shows at `x`: of the buckets in that two-pixel
	column, the one with the most online - so the hover's dot sits on the
	line, and a short visit can be found."""
	var columns: int = maxi(2, int(plot.size.x / 2.0))
	var column: int = clampi(int((x - plot.position.x) / plot.size.x * columns), 0, columns - 1)
	var first: int = int(float(column) / columns * players.size())
	var last: int = mini(players.size(), maxi(first + 1, int(float(column + 1) / columns * players.size())))
	var best: int = first
	for i in range(first, last):
		if everyone[i] + players[i] > everyone[best] + players[best]:
			best = i
	return clampi(best, 0, players.size() - 1)


static func _next_midnight(at: int) -> int:
	"""The first of this computer's midnights after `at`."""
	var parts: Dictionary = LocalTime.parts(at)
	var into: int = int(parts.get("hour", 0)) * 3600 + int(parts.get("minute", 0)) * 60 + int(parts.get("second", 0))
	return at - into + 86400
