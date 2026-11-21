# highscores.gd - the Highscores window: every minigame's top ten (0.169.0).
#
# The owner: "i want a global highscore option here for all minigames top 10
# on each", and "this will help me see if anyone plays my minigames". Stats >
# Highscores, under Kingdom.
#
# A BUTTON A MINIGAME along the top, then that board: place, the player and
# what they did - the Endless's and the Forge's longest run, the Healer's
# Run's most waves (and bosses), Cut the Cloth's most rounds, Crownfall's most
# maps, the Beholder's Table's best score. Your row is in green; off the ten,
# your own place is under it. The line above says what the board ranks and
# how many players are on it.
#
# THE SERVER RANKS, THIS ONLY READS: GET /api/minigames/top (the API's
# minigames/, "THE TOP TEN") - every board in one answer, read when the
# window opens and on Refresh, never polled. Names are accounts': a best is
# an account's, not one character's.
#
# Built by the HUD on first use (characterhud.gd toggle_highscores()), no
# class_name, so a fresh checkout needs no editor rescan.
extends Control


signal closed()


const PATH := "/api/minigames/top"
const REQUEST_TIMEOUT := 6.0

const NAME_COLOUR := Color(0.95, 0.92, 0.84)
const DETAIL_COLOUR := Color(0.7, 0.66, 0.6)
const VALUE_COLOUR := Color(1, 0.9, 0.5)
const YOU_COLOUR := Color(0.6, 0.9, 0.7)
# A minigame's button: dim, and gold while its board is the one showing.
const BUTTON_DIM := Color(0.72, 0.68, 0.6)
const BUTTON_PICKED := Color(1, 0.86, 0.45)
# The first three places: gold, silver, bronze.
const PLACE_COLOURS := [Color(1, 0.84, 0.35), Color(0.84, 0.86, 0.9), Color(0.86, 0.6, 0.38)]
const ROW_HEIGHT := 28.0

# The boards before the server has answered, so the window is never empty -
# the server's own list replaces it (a minigame it adds gets a button).
const KNOWN := [
	["endless", "The Endless"], ["healerrun", "The Healer's Run"], ["forge", "The Forge"],
	["cloth", "Cut the Cloth"], ["crownfall", "Crownfall"], ["pinball", "The Beholder's Table"],
]
# What each kind of board ranks, said above it.
const RANKS := {
	"seconds": "Longest run",
	"waves": "Most waves in one run",
	"rounds": "Most rounds in one run",
	"maps": "Most maps cleared",
	"score": "Best score",
}

@onready var close_button: Button = get_node_or_null("%closebutton")
@onready var games_grid: GridContainer = get_node_or_null("%gamesgrid")
@onready var summary_label: Label = get_node_or_null("%summarylabel")
@onready var refresh_button: Button = get_node_or_null("%refreshbutton")
@onready var list: VBoxContainer = get_node_or_null("%list")
@onready var notice_label: Label = get_node_or_null("%noticelabel")

# Where a request goes; a seam for the suite, which answers it itself.
var fetch: Callable = Callable(self, "_fetch")
# The board picked; kept while the game runs, so reopening shows it again.
var board_id: String = "endless"
# The last answer's boards, by id, and their order.
var boards: Dictionary = {}
var order: Array[String] = []
var game_buttons: Dictionary = {}

var _window: PanelWindow
var _group := ButtonGroup.new()
var _busy: bool = false


func _ready() -> void:
	_window = PanelWindow.attach(self, "highscores")
	if close_button != null:
		close_button.pressed.connect(close)
	if refresh_button != null:
		refresh_button.pressed.connect(refresh)
	var known: Array = []
	for entry in KNOWN:
		known.append({"id": entry[0], "name": entry[1]})
	_build_buttons(known)
	visible = false


# =============================================================================
# OPENING AND CLOSING
# =============================================================================

func open() -> void:
	visible = true
	# FRESH ON EVERY OPEN: a run may have ended while it was shut.
	await refresh()


func close() -> void:
	visible = false
	closed.emit()


func toggle() -> void:
	if visible:
		close()
	else:
		await open()


func refresh() -> void:
	if _busy:
		return
	_busy = true
	_say("")
	if summary_label != null:
		summary_label.text = "Reading..."
	var res: Dictionary = await fetch.call(PATH)
	# PAST AN AWAIT: logging out frees every window, and a door changes the
	# scene, while the request is out.
	if not is_instance_valid(self) or not is_inside_tree():
		return
	_busy = false
	if not bool(res.get("ok", false)):
		_say(refusal_text(res))
		if summary_label != null:
			summary_label.text = ""
		return
	var data: Dictionary = res.get("data", {}) if res.get("data") is Dictionary else {}
	show_answer(data)


func _fetch(path: String) -> Dictionary:
	return await Api.get_json(path, REQUEST_TIMEOUT)


static func refusal_text(res: Dictionary) -> String:
	var status: int = int(res.get("status", 0))
	var message: String = str(res.get("error", ""))
	if status == 0:
		return message if message != "" else "No connection to the server."
	if status == 404:
		# A game newer than its server: the boards are a server change too.
		return "This server does not keep highscores yet."
	return message if message != "" else "Could not read the highscores (HTTP %d)." % status


func _say(line: String) -> void:
	if notice_label != null:
		notice_label.text = line
		notice_label.visible = line != ""


# =============================================================================
# THE BOARDS
# =============================================================================

func show_answer(data: Dictionary) -> void:
	"""Every board from the answer; the picked one drawn."""
	boards.clear()
	var listed: Array = data.get("boards", []) if data.get("boards") is Array else []
	var shown: Array = []
	for board in listed:
		if board is Dictionary and str(board.get("id", "")) != "":
			boards[str(board.get("id"))] = board
			shown.append(board)
	if not shown.is_empty():
		_build_buttons(shown)
	if not boards.has(board_id) and not order.is_empty():
		board_id = order[0]
	show_board(board_id)


func _build_buttons(listed: Array) -> void:
	"""A button a minigame, in the order given. Rebuilt only when the list
	of minigames changes."""
	var ids: Array[String] = []
	for board in listed:
		ids.append(str((board as Dictionary).get("id", "")))
	if games_grid == null:
		return
	if ids != order:
		for old in games_grid.get_children():
			games_grid.remove_child(old)
			old.queue_free()
		game_buttons.clear()
		for board in listed:
			var id: String = str((board as Dictionary).get("id", ""))
			var button := Button.new()
			button.name = id
			button.toggle_mode = true
			button.button_group = _group
			button.focus_mode = Control.FOCUS_NONE
			button.clip_text = true
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.custom_minimum_size = Vector2(0, 30)
			button.add_theme_font_size_override("font_size", 13)
			# THE BOARD SHOWING READS BRIGHT: the theme draws a pressed toggle
			# much as an unpressed one.
			button.add_theme_color_override("font_color", BUTTON_DIM)
			for state in ["font_pressed_color", "font_hover_pressed_color"]:
				button.add_theme_color_override(state, BUTTON_PICKED)
			button.pressed.connect(show_board.bind(id))
			games_grid.add_child(button)
			game_buttons[id] = button
		order = ids
	for board in listed:
		var id: String = str((board as Dictionary).get("id", ""))
		var button: Button = game_buttons.get(id) as Button
		if button == null:
			continue
		button.text = short_name(str((board as Dictionary).get("name", id)))
		button.tooltip_text = str((board as Dictionary).get("name", id))
		if (board as Dictionary).has("players"):
			var players: int = int((board as Dictionary).get("players", 0))
			button.tooltip_text += " - %d %s" % [players, "player" if players == 1 else "players"]


static func short_name(full: String) -> String:
	"""'The Beholder's Table' fits a button as 'Beholder's Table'."""
	return full.trim_prefix("The ") if full.length() > 14 else full


func show_board(id: String) -> void:
	board_id = id
	for key in game_buttons:
		(game_buttons[key] as Button).set_pressed_no_signal(key == id)
	if list == null:
		return
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	var board: Dictionary = boards.get(id, {})
	if summary_label != null:
		summary_label.text = summary(board) if not board.is_empty() else ""
	if board.is_empty():
		return
	var counts: String = str(board.get("counts", "score"))
	var top: Array = board.get("top", []) if board.get("top") is Array else []
	for row in top:
		if row is Dictionary:
			list.add_child(_row(row, counts, bool(row.get("you", false))))
	if top.is_empty():
		var empty := Label.new()
		empty.name = "empty"
		empty.text = "Nobody has a score here yet - be the first."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_color_override("font_color", DETAIL_COLOUR)
		empty.add_theme_font_size_override("font_size", 13)
		list.add_child(empty)
	# YOU, OFF THE TEN: your own place under it.
	var you: Variant = board.get("you")
	if you is Dictionary and int((you as Dictionary).get("place", 0)) > top.size():
		var gap := Label.new()
		gap.name = "gap"
		gap.text = "..."
		gap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		gap.add_theme_color_override("font_color", DETAIL_COLOUR)
		list.add_child(gap)
		var mine: Dictionary = (you as Dictionary).duplicate()
		mine["name"] = Api.username if Api.username != "" else "You"
		list.add_child(_row(mine, counts, true))


static func summary(board: Dictionary) -> String:
	"""'Most waves in one run - 5 players.'"""
	var players: int = int(board.get("players", 0))
	var ranks: String = str(RANKS.get(str(board.get("counts", "")), "Best"))
	if players == 0:
		return "%s - nobody yet." % ranks
	return "%s - %d %s." % [ranks, players, "player" if players == 1 else "players"]


static func place_text(place: int) -> String:
	"""1st, 2nd, 3rd, 4th ... 11th, 12th, 13th, 21st."""
	var tens: int = place % 100
	var suffix: String = "th"
	if tens < 11 or tens > 13:
		match place % 10:
			1:
				suffix = "st"
			2:
				suffix = "nd"
			3:
				suffix = "rd"
	return "%d%s" % [place, suffix]


static func value_text(counts: String, value: int, bosses: int = 0) -> String:
	"""What a row did, in the board's own words."""
	match counts:
		"seconds":
			return _clock(value)
		"waves":
			var waves: String = "%d %s" % [value, "wave" if value == 1 else "waves"]
			if bosses > 0:
				waves += ", %d %s" % [bosses, "boss" if bosses == 1 else "bosses"]
			return waves
		"rounds":
			return "%d %s" % [value, "round" if value == 1 else "rounds"]
		"maps":
			return "%d %s" % [value, "map" if value == 1 else "maps"]
	return GameConstants.commas(value)


static func _clock(seconds: int) -> String:
	"""4:12, or 1:02:03 past an hour."""
	var s: int = maxi(0, seconds)
	@warning_ignore("integer_division")
	var hours: int = s / 3600
	@warning_ignore("integer_division")
	var minutes: int = (s % 3600) / 60
	if hours > 0:
		return "%d:%02d:%02d" % [hours, minutes, s % 60]
	return "%d:%02d" % [minutes, s % 60]


func _row(row: Dictionary, counts: String, yours: bool) -> Control:
	var place: int = int(row.get("place", 0))
	var box := HBoxContainer.new()
	box.name = "row_%d" % place
	box.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	box.add_theme_constant_override("separation", 10)
	var place_label := Label.new()
	place_label.name = "place"
	place_label.text = place_text(place)
	place_label.custom_minimum_size = Vector2(44, 0)
	place_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	place_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	place_label.add_theme_color_override("font_color",
		PLACE_COLOURS[place - 1] if place >= 1 and place <= PLACE_COLOURS.size() else DETAIL_COLOUR)
	place_label.add_theme_font_size_override("font_size", 15)
	box.add_child(place_label)
	var name_label := Label.new()
	name_label.name = "name"
	name_label.text = str(row.get("name", "?")) + ("  (you)" if yours else "")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_color_override("font_color", YOU_COLOUR if yours else NAME_COLOUR)
	name_label.add_theme_font_size_override("font_size", 15)
	box.add_child(name_label)
	var value_label := Label.new()
	value_label.name = "value"
	value_label.text = value_text(counts, int(row.get("value", 0)), int(row.get("bosses", 0)))
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.add_theme_color_override("font_color", YOU_COLOUR if yours else VALUE_COLOUR)
	value_label.add_theme_font_size_override("font_size", 15)
	box.add_child(value_label)
	var at: int = int(row.get("at", 0))
	if at > 0:
		box.tooltip_text = "Set %s" % LocalTime.full(at)
		box.mouse_filter = Control.MOUSE_FILTER_PASS
	return box
