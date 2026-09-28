# playerspanel.gd — who is playing right now, and where.
#
# THE HONEST VERSION OF PRESENCE, and the wording is chosen to match what the
# server actually knows rather than what a player might assume. There are no
# positions on the server and no remote bodies in the client - you cannot see
# another player at all yet, which /api/players/nearby says in its own comment.
# What the server DOES know is which area a character is in, so that is what
# this shows: who is on, and whether they are in the room with you.
#
# The server says so itself, in a `precision` field, and this panel reads that
# field rather than hardcoding the word "area". When real positions arrive the
# route starts saying something else and the heading follows it, instead of
# going on promising a distance nobody ever measured.
#
# ANYONE CAN OPEN IT. No rank, no friends list, no guild - it is the "who else
# is here" list every game has. What it discloses is every online player's
# account name, character, level and area to every other player, which is what
# such a list IS, and no more than the nameplate already over their head.
#
# ONLINE MEANS THE HEARTBEAT, not a live session. A token lasts thirty days and
# survives the game being closed; the server filters on last_seen_at within
# ONLINE_WINDOW_SECONDS, which is three missed beats. This panel does not
# re-derive that - it asks and prints.
extends Control


# How often an open panel re-reads. The server calls somebody offline after 45
# seconds of silence, so refreshing slower than this would leave people on the
# list who had already gone. Same number as the friends panel, for the same
# reason, and it only runs while the panel is open.
const REFRESH_SECONDS := 15.0

@onready var count_label: Label = get_node_or_null("%playerscount")
@onready var refresh_button: Button = get_node_or_null("%playersrefreshbutton")
@onready var close_button: Button = get_node_or_null("%playersclosebutton")
@onready var pvp_box: Control = get_node_or_null("%playerspvp")
@onready var pvp_label: Label = get_node_or_null("%playerspvplabel")
@onready var notice_label: Label = get_node_or_null("%playersnotice")
@onready var rows: VBoxContainer = get_node_or_null("%playersrows")

var _loading: bool = false


# Drag by the header, resize from any edge, and come back where it was left.
# One component for all sixteen panels - see src/shared/panelwindow.gd for why
# this is not thirty lines copied into each of them.
#
# HELD IN A MEMBER, not discarded. It is a RefCounted carrying the drag state
# and the signal connections; letting it go frees it and the panel quietly
# stops responding.
var _window: PanelWindow


func _ready() -> void:
	_window = PanelWindow.attach(self, "players")
	visible = false

	if refresh_button != null and not refresh_button.pressed.is_connected(_on_refresh_pressed):
		refresh_button.pressed.connect(_on_refresh_pressed)
	if close_button != null and not close_button.pressed.is_connected(close):
		close_button.pressed.connect(close)

	var timer := Timer.new()
	timer.name = "PlayersRefresh"
	timer.wait_time = REFRESH_SECONDS
	timer.one_shot = false
	timer.autostart = true
	timer.timeout.connect(_on_refresh_timeout)
	add_child(timer)


# =============================================================================
# OPENING AND CLOSING
# =============================================================================

func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	visible = true
	_set_notice("")
	_load()


func close() -> void:
	visible = false


func _on_refresh_timeout() -> void:
	# ONLY WHILE OPEN. A panel nobody has looked at should not be polling a
	# route every fifteen seconds for the whole session - the same rule the
	# guild panel states where it is built on first use.
	if visible:
		_load()


func _on_refresh_pressed() -> void:
	_load()


# =============================================================================
# THE LIST
# =============================================================================

func _load() -> void:
	# ONE AT A TIME. The refresh button and the timer can land together, and two
	# replies arriving out of order would paint the older one last.
	if _loading:
		return
	_loading = true

	var res: Dictionary = await Api.get_json("/api/players/online", Api.PROBE_TIMEOUT)

	# PAST AN AWAIT. The panel may have been closed, or the scene changed, while
	# the request was out - see the measured table in combat.gd for why the
	# is_inside_tree() half is the one that fires.
	if not is_instance_valid(self) or not is_inside_tree():
		return
	_loading = false

	if not res.get("ok", false):
		_set_notice("Could not read the list. The server may be busy.")
		return

	var data: Dictionary = res.get("data", {}) if res.get("data") is Dictionary else {}
	var players: Array = data.get("players", []) if data.get("players") is Array else []

	_set_notice("")
	_paint_pvp(bool(data.get("pvp", false)))

	if count_label != null:
		count_label.text = "%d online" % int(data.get("online", players.size()))

	if rows == null:
		return
	for child in rows.get_children():
		child.queue_free()

	if players.is_empty():
		# NOT AN ERROR, and worded so it does not read like one. An empty list on
		# a small server at four in the morning is the truth.
		rows.add_child(_plain("Nobody else is playing right now."))
		return

	# HERE FIRST, THEN ELSEWHERE. The server marks with_you rather than making
	# this compare area strings, so the grouping cannot disagree with the answer
	# the server gave about its own precision.
	var here: Array = []
	var away: Array = []
	for entry in players:
		if not (entry is Dictionary):
			continue
		if bool(entry.get("with_you", false)):
			here.append(entry)
		else:
			away.append(entry)

	var where: String = str(data.get("area", ""))
	if not here.is_empty():
		var heading: String = "Nearby"
		if str(data.get("precision", "area")) == "area" and where != "":
			# THE SERVER'S OWN WORD FOR HOW PRECISE THIS IS. It says "area"
			# today, so the heading says the room rather than implying a
			# distance nobody measured.
			heading = "In %s with you" % where.capitalize()
		rows.add_child(_heading(heading))
		for entry in here:
			rows.add_child(_row(entry))

	if not away.is_empty():
		rows.add_child(_heading("Elsewhere"))
		for entry in away:
			rows.add_child(_row(entry))


func _row(entry: Dictionary) -> Control:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)

	var name_label := Label.new()
	var who: String = str(entry.get("username", "?"))
	var character: String = str(entry.get("name", ""))
	name_label.text = who if character == "" else "%s  (%s)" % [who, character]
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 12)

	# THE SAME COLOUR THE WORLD USES. Api.colour_for_role is what paints the
	# nameplate over their head and their name in chat; a fourth opinion about
	# what a dev looks like is how they stop being recognisable.
	name_label.add_theme_color_override("font_color",
		Api.colour_for_role(str(entry.get("role", "player"))))
	line.add_child(name_label)

	# WHO THEY RUN WITH, in its own label rather than glued onto the name. The
	# name label above expands to fill and would push the tag off the edge on a
	# long character name; a separate label keeps the tag and the level column
	# together at the right, where the eye is already scanning for facts about
	# the row rather than for the person's name.
	#
	# ADDED ONLY WHEN THERE IS ONE. An empty bracket pair beside everybody in no
	# guild would be a column of nothing, and the server sends "" rather than a
	# null precisely so this is one test.
	var tag: String = Api.guild_tag_text(str(entry.get("guild_tag", "")))
	if tag != "":
		var guild_label := Label.new()
		guild_label.text = tag
		guild_label.add_theme_font_size_override("font_size", 10)
		# THE SAME VIOLET AS THE CHAT LINE AND THE BOARD. Api owns it for the
		# same reason it owns colour_for_role: a guild that is a different
		# colour on each screen is not recognisable on any of them.
		guild_label.add_theme_color_override("font_color", Api.GUILD_TAG_COLOUR)
		guild_label.tooltip_text = "In %s" % str(entry.get("guild", tag))
		guild_label.mouse_filter = Control.MOUSE_FILTER_STOP
		line.add_child(guild_label)

	var where := Label.new()
	var area: String = str(entry.get("area", ""))
	where.text = "lvl %d  %s" % [int(entry.get("level", 1)), area.capitalize()]
	where.add_theme_font_size_override("font_size", 11)
	where.add_theme_color_override("font_color", Color(0.62, 0.58, 0.52))
	line.add_child(where)

	return line


func _heading(text: String) -> Control:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.6))
	return label


func _plain(text: String) -> Control:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(0.7, 0.66, 0.6))
	return label


func _paint_pvp(on: bool) -> void:
	# SHOWN HERE BECAUSE THIS IS WHERE PLAYERS ARE. A rule about whether other
	# people may hurt you belongs on the screen listing the other people.
	#
	# THE WORDING IS DELIBERATELY EXACT. The switch is real and the server holds
	# it, but nothing can damage another player yet - there are no positions on
	# the server and no remote bodies here. Saying "PvP is on" without the second
	# half would be this panel making a promise the game cannot keep, which is
	# the same failure as a comment describing a wire nobody ran.
	if pvp_box == null:
		return
	pvp_box.visible = on
	if on and pvp_label != null:
		# THE WORLD'S OWN WORDING, matching the line that goes out in chat, with
		# the honest half after it. "Hostile" is the event; "cannot hurt them
		# yet" is the truth, and a panel that printed only the first would be
		# promising combat this game does not have.
		pvp_label.text = "The owner has gone hostile. Nobody can damage anybody" \
			+ " yet - the switch is set and the combat is not built."


func _set_notice(text: String) -> void:
	if notice_label == null:
		return
	notice_label.text = text
	notice_label.visible = text != ""
