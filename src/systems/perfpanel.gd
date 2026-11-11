# perfpanel.gd - the performance readout, drawn as a panel (0.136.0).
#
# The owner: "can we remake the entire screen for read out improve it"
# (pictured first, readout_mock.png, then "build it"). It was one Label of
# seventeen rows over the game, its spike lines running under the hotbar and
# the waystone bar. Now a panel at the top left, as wide as WIDTH, drawn by
# this one Control from what perfoverlay.gd measures (show_data(), five times
# a second):
#
#   the title - the area, the stress test's multiplier, the frame cap - and
#     Copy, which puts the whole readout as text on the clipboard;
#   fps and ms a frame, big, in tone() - green within the budget, amber
#     over it, red past a hitch - with the budget and the worst;
#   a graph of the last GRAPH_FRAMES frames, the same colours, lines at the
#     budget and the hitch;
#   WHERE THE FRAME GOES - one bar, physics, scripts, drawing and waiting,
#     each in its colour (PART_COLOURS), as the frames since the last look
#     split on average;
#   THE WORLD - a grid of counts;
#   SPIKES - the newest few and the worst, each with its cause's colour.
#
# The text readout (PerfOverlay.readout()) is still written and is what
# Copy copies; it is only not shown. Mouse clicks pass through everything but
# Copy.
extends Control

const WIDTH := 392.0
const PAD := 10.0
# One frame a GRAPH_STEP px column: the graph's width over that.
const GRAPH_STEP := 2.0
const GRAPH_FRAMES := int((WIDTH - 2.0 * PAD) / GRAPH_STEP)
const GRAPH_HEIGHT := 64.0
const GRAPH_TOP_MS := 50.0
const SPIKES_SHOWN := 3
# The lag points shown, the likeliest first; Copy has them all.
const LAG_SHOWN := 3
const COPY_RECT := Rect2(WIDTH - PAD - 56.0, 6.0, 56.0, 17.0)
const TITLE_LINE := 12.0
const UNCAP_RECT := Rect2(WIDTH - PAD - 56.0 - 6.0 - 66.0, 6.0, 66.0, 17.0)

const BACK := Color(0.05, 0.045, 0.07, 0.86)
const EDGE := Color(0.62, 0.50, 0.28)
const HEAD := Color(0.95, 0.80, 0.45)
const TEXT := Color(0.90, 0.90, 0.86)
const SOFT := Color(0.62, 0.64, 0.70)
const OUTLINE := Color(0, 0, 0, 0.8)
const GOOD := Color(0.45, 0.90, 0.55)
const WARN := Color(1.0, 0.75, 0.30)
const BAD := Color(1.0, 0.38, 0.32)
# The parts of a frame, in the bar's order.
const PARTS := ["physics", "scripts", "drawing", "waiting"]
const PART_COLOURS := {
	"physics": Color(0.35, 0.65, 1.0),
	"scripts": Color(1.0, 0.62, 0.25),
	"drawing": Color(0.75, 0.50, 1.0),
	"waiting": Color(0.50, 0.50, 0.55),
}
const PART_NAMES := {
	"physics": "physics",
	"scripts": "scripts",
	"drawing": "drawing",
	"waiting": "waiting: screen, driver",
}

# Where Copy sends the text (a seam for the suite), and where it gets it.
var copy_to: Callable = DisplayServer.clipboard_set
# Whether the game is uncapped now, and the switch (seams for the suite).
var is_uncapped: Callable = func() -> bool: return Settings.uncapped
var set_uncapped: Callable = Settings.set_uncapped
var text_source: Callable = Callable()

var _data: Dictionary = {}
var _copy: Control = null
var _uncap: Control = null
var _copy_word: String = "Copy"
var _copied_left: float = 0.0


static func tone(ms: float, budget: float = 1000.0 / 60.0, hitch: float = 25.0) -> Color:
	"""A frame's colour: within the budget (and a hair over), over it, or a
	hitch."""
	if ms <= budget * 1.05:
		return GOOD
	if ms <= hitch:
		return WARN
	return BAD


func _ready() -> void:
	position = Vector2(8, 8)
	size = Vector2(WIDTH, 200)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# DRAWN HERE, NOT A Button: the game's theme makes a button 30 px tall.
	_copy = Control.new()
	_copy.name = "copy"
	_copy.mouse_filter = Control.MOUSE_FILTER_STOP
	_copy.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_copy.tooltip_text = "The whole readout as text, ready to paste"
	_copy.position = COPY_RECT.position
	_copy.size = COPY_RECT.size
	_copy.gui_input.connect(_on_copy_input)
	_copy.mouse_entered.connect(queue_redraw)
	_copy.mouse_exited.connect(queue_redraw)
	add_child(_copy)
	# UNCAP (0.137.0): V-Sync and the frame cap off while the readout is open
	# - Settings.set_uncapped(). Not in a browser, where the page sets the pace.
	_uncap = Control.new()
	_uncap.name = "uncap"
	_uncap.mouse_filter = Control.MOUSE_FILTER_STOP
	_uncap.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_uncap.tooltip_text = "V-Sync and the frame cap off while the readout is open, to see the game's top speed.\nNothing is saved; closing the readout puts them back."
	_uncap.position = UNCAP_RECT.position
	_uncap.size = UNCAP_RECT.size
	_uncap.gui_input.connect(_on_uncap_input)
	_uncap.mouse_entered.connect(queue_redraw)
	_uncap.mouse_exited.connect(queue_redraw)
	_uncap.visible = not OS.has_feature("web")
	add_child(_uncap)
	set_process(false)


func copy_text() -> void:
	"""The readout's text to the clipboard; the button says so a moment."""
	if not text_source.is_valid():
		return
	copy_to.call(str(text_source.call()))
	_copy_word = "Copied"
	_copied_left = 1.5
	set_process(true)
	queue_redraw()


func toggle_uncapped() -> void:
	set_uncapped.call(not bool(is_uncapped.call()))
	queue_redraw()


func _on_uncap_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		toggle_uncapped()
		_uncap.accept_event()


func _on_copy_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		copy_text()
		_copy.accept_event()


func _process(delta: float) -> void:
	_copied_left -= delta
	if _copied_left <= 0.0:
		_copy_word = "Copy"
		set_process(false)
		queue_redraw()


func show_data(data: Dictionary) -> void:
	_data = data
	size = Vector2(WIDTH, _height_for(data))
	queue_redraw()


func panel_height() -> float:
	return size.y


func _draw() -> void:
	if _data.is_empty():
		return
	var font: Font = get_theme_default_font()
	var d: Dictionary = _data
	var budget: float = float(d.get("budget", 1000.0 / 60.0))
	var hitch: float = float(d.get("hitch_ms", 25.0))
	draw_rect(Rect2(Vector2.ZERO, size), BACK)
	draw_rect(Rect2(Vector2.ZERO, size), EDGE, false, 1.5)

	# ---- the title ------------------------------------------------------------------
	_text(font, Vector2(PAD, 18), "PERFORMANCE", 12, HEAD)
	var lit: bool = _copy != null and Rect2(Vector2.ZERO, COPY_RECT.size).has_point(_copy.get_local_mouse_position())
	draw_rect(COPY_RECT, Color(EDGE, 0.45 if lit else 0.22))
	draw_rect(COPY_RECT, EDGE, false, 1.0)
	_text(font, COPY_RECT.position + Vector2(0, 13), _copy_word, 11, TEXT, HORIZONTAL_ALIGNMENT_CENTER, COPY_RECT.size.x)
	if _uncap != null and _uncap.visible:
		var on: bool = bool(is_uncapped.call())
		var over: bool = Rect2(Vector2.ZERO, UNCAP_RECT.size).has_point(_uncap.get_local_mouse_position())
		draw_rect(UNCAP_RECT, Color(WARN, 0.35) if on else Color(EDGE, 0.45 if over else 0.22))
		draw_rect(UNCAP_RECT, WARN if on else EDGE, false, 1.0)
		_text(font, UNCAP_RECT.position + Vector2(0, 13), "Uncapped" if on else "Uncap", 11, WARN if on else TEXT,
			HORIZONTAL_ALIGNMENT_CENTER, UNCAP_RECT.size.x)
	_text(font, Vector2(PAD, 32), str(d.get("title", "")), 10, Color(d.get("title_colour", SOFT)))
	# Everything under the title's second line, TITLE_LINE lower.
	draw_set_transform(Vector2(0, TITLE_LINE))

	# ---- the big numbers ------------------------------------------------------------
	var frame_ms: float = float(d.get("frame_ms", 0.0))
	var colour: Color = tone(frame_ms, budget, hitch)
	var fps_text := "%d" % int(d.get("fps", 0))
	_text(font, Vector2(PAD, 52), fps_text, 30, colour)
	var fps_w: float = font.get_string_size(fps_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
	_text(font, Vector2(PAD + fps_w + 5.0, 52), "fps", 13, SOFT)
	var ms_text := "%.1f" % frame_ms
	var ms_x: float = PAD + fps_w + 40.0
	_text(font, Vector2(ms_x, 52), ms_text, 30, colour)
	var ms_w: float = font.get_string_size(ms_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
	_text(font, Vector2(ms_x + ms_w + 5.0, 52), "ms a frame", 13, SOFT)
	var worst: float = float(d.get("worst_ms", 0.0))
	_text(font, Vector2(PAD, 52), "worst %.0f ms" % worst if worst > 0.0 else "worst -", 12,
		tone(worst, budget, hitch) if worst > 0.0 else SOFT, HORIZONTAL_ALIGNMENT_RIGHT, WIDTH - 2.0 * PAD)

	# ---- the graph --------------------------------------------------------------------
	var graph := Rect2(PAD, 62, WIDTH - 2.0 * PAD, GRAPH_HEIGHT)
	draw_rect(graph, Color(0, 0, 0, 0.35))
	var frames: PackedFloat32Array = d.get("graph", PackedFloat32Array())
	var n: int = frames.size()
	for i in n:
		var ms: float = frames[i]
		var tall: float = minf(ms / GRAPH_TOP_MS, 1.0) * graph.size.y
		draw_rect(Rect2(graph.end.x - float(n - i) * GRAPH_STEP, graph.end.y - tall, GRAPH_STEP, tall),
			tone(ms, budget, hitch))
	for line in [[budget, Color(1, 1, 1, 0.35), "%.1f" % budget], [hitch, Color(BAD, 0.55), "%.0f" % hitch]]:
		var line_y: float = graph.end.y - float(line[0]) / GRAPH_TOP_MS * graph.size.y
		draw_dashed_line(Vector2(graph.position.x, line_y), Vector2(graph.end.x, line_y), line[1], 1.0, 4.0)
		_text(font, Vector2(graph.position.x + 3.0, line_y - 2.0), line[2], 9, line[1])
	var marks: Array = d.get("graph_marks", [])
	if marks.is_empty():
		_text(font, Vector2(graph.position.x, graph.position.y + 11.0),
			"the last %.0f s" % (float(GRAPH_FRAMES) / 60.0), 9, SOFT, HORIZONTAL_ALIGNMENT_RIGHT, graph.size.x - 3.0)
	_graph_marks(font, graph, n, frames, marks)
	var y: float = 142.0
	var key: Array = d.get("graph_key", [])
	if not key.is_empty():
		_graph_key(font, y - 2.0, key)
		y += 14.0
	_text(font, Vector2(PAD, y), str(d.get("hitches", "")), 12, TEXT)
	y += 15.0
	_text(font, Vector2(PAD, y), str(d.get("loads", "")), 10, SOFT)
	if not marks.is_empty():
		_text(font, Vector2(PAD, y), "graph: the last %.0f s" % (float(GRAPH_FRAMES) / 60.0), 10, SOFT,
			HORIZONTAL_ALIGNMENT_RIGHT, WIDTH - 2.0 * PAD)
	for verdict in d.get("verdict", []):
		y += 16.0
		_verdict(font, y, str(verdict[0]), str(verdict[1]))

	# ---- where the frame goes -----------------------------------------------------------
	y = _section(font, y + 9.0, "WHERE THE FRAME GOES")
	var split: Dictionary = d.get("split", {})
	var total: float = 0.0
	for part in PARTS:
		total += float(split.get(part, 0.0))
	var bar := Rect2(PAD, y, WIDTH - 2.0 * PAD, 14)
	draw_rect(bar, Color(0, 0, 0, 0.35))
	var px_per_ms: float = bar.size.x / maxf(maxf(total, budget), 0.001)
	var at: float = bar.position.x
	for part in PARTS:
		var w: float = float(split.get(part, 0.0)) * px_per_ms
		draw_rect(Rect2(at, bar.position.y, w, bar.size.y), PART_COLOURS[part])
		at += w
	if total > budget:
		var mark: float = bar.position.x + budget * px_per_ms
		draw_line(Vector2(mark, bar.position.y - 2.0), Vector2(mark, bar.end.y + 2.0), Color.WHITE, 1.5)
	y += 30.0
	for i in PARTS.size():
		var part: String = PARTS[i]
		var px: float = PAD + float(i % 2) * 196.0
		var py: float = y + floorf(i / 2.0) * 16.0
		draw_rect(Rect2(px, py - 9.0, 9, 9), PART_COLOURS[part])
		var label: String = PART_NAMES[part]
		if part == "physics" and int(split.get("ticks", 0)) > 0:
			label = "physics, %s" % _ticks_text(float(split.get("ticks", 0.0)))
		# The label gives way, never the number (0.139.0: "waiting: screen,
		# driver 6.8 ms" ran off the panel's edge in the owner's browser).
		var amount: String = "  %.1f ms" % float(split.get(part, 0.0))
		var column: float = (WIDTH - PAD - px - 14.0) if i % 2 == 1 else 196.0 - 18.0
		label = _fit(font, label, 12, column - font.get_string_size(amount, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x)
		_text(font, Vector2(px + 14.0, py), label + amount, 12, TEXT)
	y += 34.0
	# A size smaller, and cut to the panel if still too long (0.139.0:
	# "graphics card not measured" ran off its edge).
	_text(font, Vector2(PAD, y), _fit(font, str(d.get("ticks_line", "")), 10, WIDTH - 2.0 * PAD), 10, SOFT)

	# ---- the world -----------------------------------------------------------------------
	y = _section(font, y + 10.0, "THE WORLD")
	var cells: Array = d.get("world", [])
	for i in cells.size():
		var cell: Array = cells[i]
		var cx: float = PAD + float(i % 4) * 93.0
		var cy: float = y + floorf(i / 4.0) * 30.0
		_text(font, Vector2(cx, cy + 6.0), str(cell[0]), 10, SOFT)
		_text(font, Vector2(cx, cy + 20.0), str(cell[1]), 13, TEXT)
	@warning_ignore("integer_division")
	y += 30.0 * float((cells.size() + 3) / 4) + 2.0

	# ---- lag points -----------------------------------------------------------------------
	var lag: Array = d.get("lag", [])
	if not lag.is_empty():
		y = _section(font, y, "LAG POINTS  (what was happening when frames hitched)")
		y = _lag_rows(font, y, lag, d.get("lag_base", []))

	# ---- spikes --------------------------------------------------------------------------
	y = _section(font, y, "SPIKES  (newest first)")
	var spikes: Array = d.get("spikes", [])
	if spikes.is_empty():
		_text(font, Vector2(PAD, y + 4.0), "none since switched on", 11, SOFT)
		y += 16.0
	for spike in spikes:
		_spike_row(font, y + 4.0, spike, budget, hitch)
		y += _spike_height(spike)
	var worst_spike: Dictionary = d.get("worst_spike", {})
	if not worst_spike.is_empty():
		draw_line(Vector2(PAD, y - 1.0), Vector2(WIDTH - PAD, y - 1.0), Color(EDGE, 0.2), 1.0)
		_spike_row(font, y + 10.0, worst_spike, budget, hitch)
	draw_set_transform(Vector2.ZERO)


# A hitch's marker over its bar: the letter of what happened in it, on the
# colour of the part that took the time.
const MARK_SIZE := Vector2(11.0, 11.0)
const VERDICT_WORDS := {"great": ["GREAT", GOOD], "fix": ["FIX", BAD], "watch": ["WATCH", WARN]}


func _graph_marks(font: Font, graph: Rect2, n: int, frames: PackedFloat32Array, marks: Array) -> void:
	"""A marker over each hitch in the graph (`marks`: [frame, letter, part]),
	a faint stem down to its bar; two that would touch drawn as one."""
	var last_x: float = -100.0
	for mark in marks:
		var i: int = int(mark[0])
		var x: float = graph.end.x - float(n - i) * GRAPH_STEP + GRAPH_STEP * 0.5
		if x - last_x < MARK_SIZE.x + 1.0:
			continue
		last_x = x
		var colour: Color = PART_COLOURS.get(str(mark[2]), SOFT)
		var box := Rect2(Vector2(x - MARK_SIZE.x * 0.5, graph.position.y + 1.0), MARK_SIZE)
		var bar_top: float = graph.end.y - minf(frames[i] / GRAPH_TOP_MS, 1.0) * graph.size.y if i < frames.size() else graph.end.y
		if bar_top > box.end.y:
			draw_line(Vector2(x, box.end.y), Vector2(x, bar_top), Color(colour, 0.6), 1.0)
		draw_rect(box, Color(0, 0, 0, 0.7))
		draw_rect(box.grow(-1.0), colour)
		_text(font, box.position + Vector2(0, 9.5), str(mark[1]), 9, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, box.size.x)


func _graph_key(font: Font, y: float, key: Array) -> void:
	"""What the markers' letters stand for, those in the graph now."""
	var x: float = PAD
	for item in key:
		var colour: Color = PART_COLOURS.get(str(item[3]), SOFT) if item.size() > 3 else SOFT
		var box := Rect2(Vector2(x, y - 9.0), MARK_SIZE)
		draw_rect(box, colour)
		_text(font, box.position + Vector2(0, 9.5), str(item[0]), 9, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, box.size.x)
		var label: String = "%s ×%d" % [item[1], int(item[2])]
		_text(font, Vector2(x + MARK_SIZE.x + 4.0, y), label, 10, SOFT)
		x += MARK_SIZE.x + 4.0 + font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 10.0


func _verdict(font: Font, y: float, kind: String, text: String) -> void:
	"""GREAT, WATCH or FIX, and why."""
	var word: Array = VERDICT_WORDS.get(kind, ["", SOFT])
	var colour: Color = word[1]
	var badge := Rect2(PAD, y - 10.0, 44.0, 13.0)
	draw_rect(badge, Color(colour, 0.25))
	draw_rect(badge, colour, false, 1.0)
	_text(font, badge.position + Vector2(0, 10.0), str(word[0]), 9, colour, HORIZONTAL_ALIGNMENT_CENTER, badge.size.x)
	_text(font, Vector2(PAD + 52.0, y), _fit(font, text, 11, WIDTH - PAD - 52.0 - PAD), 11, TEXT)


static func _fit(font: Font, text: String, font_size: int, width: float) -> String:
	"""`text`, cut with an ellipsis to fit `width`."""
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= width:
		return text
	var cut: String = text
	while cut.length() > 1 and font.get_string_size(cut + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
		cut = cut.left(cut.length() - 1)
	return cut.strip_edges() + "…"


# Where a lag point's columns stand, and its bar.
const LAG_FRAMES_X := 196.0
const LAG_RATE_X := 286.0
const LAG_BAR := Rect2(326.0, -8.0, 56.0, 8.0)


func _lag_rows(font: Font, y: float, lag: Array, base: Array) -> float:
	"""Each kind of event: how many frames had it, how many of those hitched,
	and that share against the frames with none of them (`base`) - the one
	far above the rest is what makes the lag."""
	var base_rate: float = float(base[1]) / maxf(1.0, float(base[0])) if base.size() >= 2 else 0.0
	_text(font, Vector2(PAD, y + 2.0), "event", 10, SOFT)
	_text(font, Vector2(LAG_FRAMES_X, y + 2.0), "frames that hitched", 10, SOFT)
	y += 16.0
	for row in lag.slice(0, LAG_SHOWN):
		var frames: int = int(row[1])
		var hitched: int = int(row[2])
		var rate: float = float(hitched) / maxf(1.0, float(frames))
		var colour: Color = BAD if rate >= maxf(0.2, base_rate * 5.0) else (WARN if rate >= maxf(0.05, base_rate * 2.0) else TEXT)
		_lag_row(font, y, str(row[0]), "%d of %d" % [hitched, frames], rate, colour)
		y += 16.0
	if base.size() >= 2:
		_lag_row(font, y, "none of these", "%d of %s" % [int(base[1]), _thousands(int(base[0]))], base_rate, SOFT)
		y += 16.0
	return y + 2.0


func _lag_row(font: Font, y: float, label: String, count: String, rate: float, colour: Color) -> void:
	_text(font, Vector2(PAD, y), label, 12, colour)
	_text(font, Vector2(LAG_FRAMES_X, y), count, 11, TEXT)
	_text(font, Vector2(LAG_RATE_X, y), "%d%%" % roundi(rate * 100.0), 11, colour)
	var bar := Rect2(LAG_BAR.position + Vector2(0, y), LAG_BAR.size)
	draw_rect(bar, Color(0, 0, 0, 0.4))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(rate, 0.0, 1.0), bar.size.y)), colour)


static func _thousands(n: int) -> String:
	var digits := str(n)
	var out := ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return digits + out


func _spike_height(spike: Dictionary) -> float:
	return 28.0 if str(spike.get("marks", "")) != "" else 16.0


func _spike_row(font: Font, y: float, spike: Dictionary, budget: float, hitch: float) -> void:
	var ms: float = float(spike.get("ms", 0.0))
	_text(font, Vector2(PAD, y), "%.0f ms" % ms, 12, tone(ms, budget, hitch))
	_text(font, Vector2(PAD + 50.0, y), str(spike.get("ago", "")), 11, SOFT)
	draw_rect(Rect2(PAD + 116.0, y - 9.0, 9, 9), PART_COLOURS.get(str(spike.get("kind", "")), SOFT))
	# The cause cut to what the node count beside it leaves (0.139.0: "waiting:
	# screen, driver 6.8 ms" ran off the panel's edge).
	var nodes: String = str(spike.get("nodes", ""))
	var room: float = WIDTH - 2.0 * PAD - 130.0
	if nodes != "":
		room -= font.get_string_size(nodes, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 8.0
	_text(font, Vector2(PAD + 130.0, y), _fit(font, str(spike.get("cause", "")), 11, room), 11, TEXT)
	if nodes != "":
		_text(font, Vector2(PAD, y), nodes, 10, SOFT, HORIZONTAL_ALIGNMENT_RIGHT, WIDTH - 2.0 * PAD)
	# What happened in that frame, under it.
	var marks: String = str(spike.get("marks", ""))
	if marks != "":
		_text(font, Vector2(PAD + 130.0, y + 12.0), _fit(font, marks, 10, WIDTH - 2.0 * PAD - 130.0), 10, SOFT)


func _height_for(d: Dictionary) -> float:
	var cells: int = (d.get("world", []) as Array).size()
	var spikes: float = 0.0
	for spike in d.get("spikes", []):
		spikes += _spike_height(spike)
	spikes = maxf(16.0, spikes)
	var worst_spike: Dictionary = d.get("worst_spike", {})
	var worst: float = (2.0 + _spike_height(worst_spike)) if not worst_spike.is_empty() else 0.0
	var lag_rows: int = mini(LAG_SHOWN, (d.get("lag", []) as Array).size())
	var lag: float = (22.0 + 16.0 + 16.0 * float(lag_rows + (1 if (d.get("lag_base", []) as Array).size() >= 2 else 0)) + 2.0) \
		if lag_rows > 0 else 0.0
	@warning_ignore("integer_division")
	var world: float = 30.0 * float((cells + 3) / 4)
	var extra: float = 16.0 * float((d.get("verdict", []) as Array).size()) \
		+ (14.0 if not (d.get("graph_key", []) as Array).is_empty() else 0.0)
	return TITLE_LINE + 157.0 + extra + 9.0 + 22.0 + 30.0 + 34.0 + 10.0 + 22.0 + world + 2.0 + lag + 22.0 + spikes + worst + 10.0


func _section(font: Font, y: float, title: String) -> float:
	draw_line(Vector2(PAD, y), Vector2(WIDTH - PAD, y), Color(EDGE, 0.35), 1.0)
	_text(font, Vector2(PAD, y + 15.0), title, 11, HEAD)
	return y + 22.0


func _text(font: Font, at: Vector2, text: String, font_size: int, colour: Color,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	draw_string_outline(font, at, text, align, width, font_size, 3, OUTLINE)
	draw_string(font, at, text, align, width, font_size, colour)


static func _ticks_text(ticks: float) -> String:
	if is_equal_approx(ticks, roundf(ticks)):
		return "%d tick%s" % [int(ticks), "" if int(ticks) == 1 else "s"]
	return "%.1f ticks" % ticks
