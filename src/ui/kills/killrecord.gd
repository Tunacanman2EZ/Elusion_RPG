# killrecord.gd - the Kills window: every monster, with its picture, and how
# many of each you have killed - and everybody (0.9.0).
#
# The owner, 7 Oct: "lets make a button in game that records all players kills
# with icons of the enemies". Social > Kills, or K.
#
# TWO TABS:
#   You       this character's kills of each monster, most first, and when the
#             last one fell; then every monster it has not killed yet, greyed,
#             so the list is also what is left to find.
#   Everyone  every player's kills of each monster added up, how many players
#             have killed it, who has killed the most (an account, its
#             characters together) and your own share.
#
# THE SERVER COUNTS, THIS ONLY READS: GET /api/kills and /api/kills/everyone
# (app.py, THE KILL RECORD). Paid kills only - a monster that grants nothing,
# like a large slime that splits instead of dying, is never on it. The record
# began on a date (`since`), and the summary line says which: a count that
# starts at zero should say why.
#
# THE PICTURES are the monsters' own art (EnemyPortraits), loaded a row at a
# time as the list is drawn.
extends Control
class_name KillRecord


signal closed()


const REQUEST_TIMEOUT := 6.0
# A tab read this recently is drawn from what it said; switching back and
# forth should not be a request each time.
const FRESH_SECONDS := 15.0

const PORTRAIT_SIZE := Vector2(40, 40)
const NAME_COLOUR := Color(0.95, 0.92, 0.84)
const DETAIL_COLOUR := Color(0.7, 0.66, 0.6)
const COUNT_COLOUR := Color(1, 0.9, 0.5)
const YOU_COLOUR := Color(0.6, 0.9, 0.7)
const NOT_YET := Color(1, 1, 1, 0.38)

enum Tab { YOU, EVERYONE }

@onready var header_label: Label = get_node_or_null("%headerlabel")
@onready var close_button: Button = get_node_or_null("%closebutton")
@onready var yours_button: Button = get_node_or_null("%yoursbutton")
@onready var everyone_button: Button = get_node_or_null("%everyonebutton")
@onready var summary_label: Label = get_node_or_null("%summarylabel")
@onready var list: VBoxContainer = get_node_or_null("%list")
@onready var notice_label: Label = get_node_or_null("%noticelabel")

var tab: int = Tab.YOU
# Where a request goes; a seam for the suite, which answers it itself.
var fetch: Callable = Callable(self, "_fetch")

var _window: PanelWindow
var _answers: Dictionary = {}     # Tab -> the last answer's data
var _answered_at: Dictionary = {} # Tab -> when, in seconds since start
var _busy: bool = false


func _ready() -> void:
	_window = PanelWindow.attach(self, "kills")
	if close_button != null:
		close_button.pressed.connect(close)
	var group := ButtonGroup.new()
	for button in [yours_button, everyone_button]:
		if button != null:
			button.button_group = group
	if yours_button != null:
		yours_button.pressed.connect(show_tab.bind(Tab.YOU))
	if everyone_button != null:
		everyone_button.pressed.connect(show_tab.bind(Tab.EVERYONE))
	visible = false


# =============================================================================
# OPENING AND CLOSING
# =============================================================================

func open() -> void:
	visible = true
	# FRESH ON EVERY OPEN: kills happen while it is shut.
	_answers.clear()
	await show_tab(tab)


func close() -> void:
	visible = false
	closed.emit()


func toggle() -> void:
	if visible:
		close()
	else:
		await open()


func show_tab(which: int) -> void:
	tab = which
	if yours_button != null:
		yours_button.set_pressed_no_signal(which == Tab.YOU)
	if everyone_button != null:
		everyone_button.set_pressed_no_signal(which == Tab.EVERYONE)
	var now: float = Time.get_ticks_msec() / 1000.0
	if _answers.has(which) and now - float(_answered_at.get(which, -1000.0)) < FRESH_SECONDS:
		render(which, _answers[which])
		return
	await load_tab(which)


func load_tab(which: int) -> void:
	if _busy:
		return
	_busy = true
	_say("")
	if summary_label != null:
		summary_label.text = "Counting..."
	var path: String = "/api/kills?slot=%d" % CharacterData.active_character_index \
		if which == Tab.YOU else "/api/kills/everyone"
	var res: Dictionary = await fetch.call(path)
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
	var data: Dictionary = res.get("data", {}) if res.get("data", {}) is Dictionary else {}
	_answers[which] = data
	_answered_at[which] = Time.get_ticks_msec() / 1000.0
	if tab == which:
		render(which, data)


func _fetch(path: String) -> Dictionary:
	return await Api.get_json(path, REQUEST_TIMEOUT)


static func refusal_text(res: Dictionary) -> String:
	var status: int = int(res.get("status", 0))
	var message: String = str(res.get("error", ""))
	if status == 0:
		return message if message != "" else "No connection to the server."
	if status == 404:
		# A game newer than its server: the record is a server change too.
		return "This server does not keep a kill record yet."
	return message if message != "" else "Could not read the kill record (HTTP %d)." % status


func _say(line: String) -> void:
	if notice_label != null:
		notice_label.text = line
		notice_label.visible = line != ""


# =============================================================================
# THE LIST
# =============================================================================

func render(which: int, data: Dictionary) -> void:
	"""Draw one tab's answer: the summary line, then a row per monster."""
	if list == null:
		return
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	var rows: Array = data.get("kills", []) if data.get("kills", []) is Array else []
	var counted: Dictionary = {}
	for row in rows:
		if row is Dictionary:
			counted[str(row.get("enemy_id", ""))] = true
			list.add_child(_row(which, row))
	# THEN WHAT NOBODY - OR YOU - HAS KILLED YET, greyed, by name: the record
	# is also the list of what is left to find.
	for monster in EnemyPortraits.roster():
		var enemy_id: String = str(monster["enemy_id"])
		if not counted.has(enemy_id):
			list.add_child(_row(which, {"enemy_id": enemy_id, "kills": 0}))
	if summary_label != null:
		summary_label.text = summary(which, data, EnemyPortraits.roster().size())


static func summary(which: int, data: Dictionary, roster_size: int) -> String:
	var total: int = int(data.get("total", 0))
	var since: String = since_text(int(data.get("since", 0)))
	if which == Tab.YOU:
		var kinds: int = int(data.get("kinds", 0))
		if total == 0:
			return "No kills yet%s." % since
		return "%s %s - %d of %d kinds of monster%s." % [count_text(total),
			"kill" if total == 1 else "kills", kinds, roster_size, since]
	var players: int = int(data.get("players", 0))
	if total == 0:
		return "Nobody has killed anything yet%s." % since
	return "%s %s by %d %s%s." % [count_text(total), "kill" if total == 1 else "kills",
		players, "player" if players == 1 else "players", since]


static func since_text(since: int) -> String:
	if since <= 0:
		return ""
	# THE PLAYER'S DATE, not UTC's: a record that began at 02:00 UTC on 7 Oct
	# began on the evening of the 6th in Denver.
	var day: Dictionary = LocalTime.parts(since)
	const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	return ", counted since %d %s %d" % [int(day["day"]), MONTHS[clampi(int(day["month"]) - 1, 0, 11)], int(day["year"])]


static func count_text(n: int) -> String:
	# 12,345 - a big number with its thousands marked, as the kingdom board
	# writes gold.
	var digits: String = str(absi(n))
	var out: String = ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-" if n < 0 else "") + digits + out


static func ago_text(at: int, now: int) -> String:
	var seconds: int = maxi(now - at, 0)
	if seconds < 60:
		return "just now"
	if seconds < 3600:
		return "%d min ago" % floori(seconds / 60.0)
	if seconds < 86400:
		return "%d h ago" % floori(seconds / 3600.0)
	var days: int = floori(seconds / 86400.0)
	return "%d %s ago" % [days, "day" if days == 1 else "days"]


static func detail_text(which: int, row: Dictionary, me: String, now: int) -> String:
	var kills: int = int(row.get("kills", 0))
	if which == Tab.YOU:
		if kills <= 0:
			return "Not killed yet"
		return "Last one %s" % ago_text(int(row.get("last_at", now)), now)
	if kills <= 0:
		return "Nobody has killed one yet"
	var players: int = int(row.get("players", 0))
	var top: String = str(row.get("top", ""))
	var line: String = "%d %s - most: %s" % [players, "player" if players == 1 else "players",
		"you" if top == me and me != "" else top]
	if top != me and int(row.get("yours", 0)) > 0:
		line += " (%s) - you: %s" % [count_text(int(row.get("top_kills", 0))), count_text(int(row.get("yours", 0)))]
	else:
		line += " (%s)" % count_text(int(row.get("top_kills", 0)))
	return line


func _row(which: int, row: Dictionary) -> Control:
	var enemy_id: String = str(row.get("enemy_id", ""))
	var kills: int = int(row.get("kills", 0))
	var box := HBoxContainer.new()
	box.name = "row_" + enemy_id
	box.add_theme_constant_override("separation", 10)

	var portrait := TextureRect.new()
	portrait.name = "portrait"
	portrait.custom_minimum_size = PORTRAIT_SIZE
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var picture: Dictionary = EnemyPortraits.picture(enemy_id)
	if not picture.is_empty():
		portrait.texture = picture.get("texture")
		portrait.material = picture.get("material")
		portrait.modulate = picture.get("modulate", Color.WHITE)
	box.add_child(portrait)

	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_theme_constant_override("separation", 0)
	var name_label := Label.new()
	name_label.name = "name"
	name_label.text = EnemyPortraits.display_name(enemy_id)
	name_label.add_theme_color_override("font_color", NAME_COLOUR)
	name_label.add_theme_font_size_override("font_size", 14)
	words.add_child(name_label)
	var detail := Label.new()
	detail.name = "detail"
	detail.text = detail_text(which, row, Api.username, int(Time.get_unix_time_from_system()))
	detail.add_theme_color_override("font_color",
		YOU_COLOUR if which == Tab.EVERYONE and str(row.get("top", "")) == Api.username and Api.username != "" else DETAIL_COLOUR)
	detail.add_theme_font_size_override("font_size", 11)
	words.add_child(detail)
	box.add_child(words)

	var count := Label.new()
	count.name = "count"
	count.text = count_text(kills) if kills > 0 else "-"
	count.custom_minimum_size = Vector2(56, 0)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count.add_theme_color_override("font_color", COUNT_COLOUR)
	count.add_theme_font_size_override("font_size", 16)
	box.add_child(count)
	# A little room between the count and the list's scrollbar.
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(4, 0)
	box.add_child(gap)

	if kills <= 0:
		box.modulate = NOT_YET
	return box
