# guildpanel.gd — your guild, who is in it, and what your rank lets you do.
#
# THE ROSTER IS THE SERVER'S, NOT THIS PANEL'S. Everything drawn below comes
# from one GET /api/guild and is thrown away on the next one. No local copy to
# fall out of step, no row added optimistically before the server has agreed,
# and every button does its work by asking and then re-reading the whole
# answer. Same shape as the friends panel next door, for the same reason.
#
# THE PANEL SHOWS THREE DIFFERENT THINGS depending on where you stand, and
# they are three states rather than three screens:
#
#   no guild, no invitations   ->  a box to name one, and what founding costs
#   no guild, invitations      ->  the same, plus who has asked you
#   in a guild                 ->  the roster, and the buttons your rank allows
#
# WHAT IT DELIBERATELY DOES NOT DO: decide anything. Which buttons appear is a
# courtesy - the server refuses an officer trying to remove another officer
# whether or not this panel drew the button, and it answers 404 rather than
# 403 so the refusal does not confirm what it refused.
extends Control

# Api's static helpers, called on the script and not on the autoload: a static
# function called through an instance is a warning in the editor's debugger.
const ApiScript := preload("res://src/systems/api.gd")


# How often an open panel re-reads. Presence is the only thing here that goes
# stale on its own, and the server calls somebody offline after 45 seconds of
# silence, so anything slower shows green dots for people who have gone.
const REFRESH_SECONDS := 15.0

# Matches the server's own rule, so an impossible name is refused at the
# keyboard rather than by a round trip. See GUILD_NAME_PATTERN in app.py.
#
# TWELVE, DOWN FROM TWENTY-FOUR, and the reason is on the other side of the
# screen rather than in the database: the name is now drawn above a head, on
# every chat line its members write, on the players menu and on the kingdom
# board. At 24 characters that is a banner following somebody around.
#
# THIS REFUSES; IT DOES NOT DECIDE. The server's pattern is the rule and this is
# a courtesy that saves a round trip - which is why MAX_NAME below is also sent
# to the LineEdit rather than being a second, quietly different number.
const NAME_PATTERN := "^[A-Za-z0-9][A-Za-z0-9 '\\-]{2,11}$"

# The same twelve, as a number, because a LineEdit needs one and reading it out
# of the pattern above would be parsing a regex to find out what it says.
const MAX_NAME := 12

# A username, which is a different limit and always was. Kept beside MAX_NAME so
# the two cannot be confused for copies of each other.
const MAX_USERNAME := 20

# The server's own ladder, lowest first. Used only to decide which buttons to
# offer; the server decides whether they work.
const RANKS := ["member", "officer", "leader"]

const RANK_LABELS := {
	"leader": "Leader",
	"officer": "Officer",
	"member": "Member",
}

# For a sentence: "Ana is now an officer.", not "Ana is now Officer."
const RANK_WITH_ARTICLE := {
	"leader": "the leader",
	"officer": "an officer",
	"member": "a member",
}

# GUILD RANK, as a colour and a mark. Names are drawn in the colour each
# player chose - the same colour they have in chat and over their head - so
# guild rank is worn beside the name instead: a gold crown for the leader and a
# blue diamond for an officer, and the group headings in the same colours.
# Members wear nothing, which is what makes the other two stand out.
const RANK_COLOURS := {
	"leader": Color(1.0, 0.84, 0.42),
	"officer": Color(0.62, 0.8, 1.0),
	"member": Color(0.78, 0.74, 0.66),
}
const RANK_MARKS := {"leader": "♛", "officer": "◆"}

# How a name is drawn: its player's colour, with the owner's crown or MOD / DEV
# in front. Shared with chat, friends and the players menu.
const NameTag := preload("res://src/shared/nametag.gd")

# The roster's groups, in the order drawn, and what each is called over its
# rows. PLURAL BY COUNT - "Officers" over one officer reads as a typo.
const GROUP_HEADINGS := {
	"leader": ["Leader", "Leader"],
	"officer": ["Officer", "Officers"],
	"member": ["Member", "Members"],
}

const ONLINE_COLOUR := Color(0.45, 0.9, 0.5)
const OFFLINE_COLOUR := Color(0.45, 0.42, 0.38)
const HEADING_COLOUR := Color(0.85, 0.78, 0.62)
const WAITING_COLOUR := Color(1.0, 0.82, 0.42)
const DANGER_COLOUR := Color(0.85, 0.45, 0.4)
const QUIET_COLOUR := Color(0.62, 0.58, 0.52)

# Online and not, as SHAPES as well as colours - a filled dot and a hollow one
# - so the difference does not depend on telling green from grey. They were
# "+" and "-", which read as buttons that add and remove somebody.
const DOT_ONLINE := "●"
const DOT_OFFLINE := "○"

# The dot's column, so a name and the character line under it start at the
# same x whatever the dot's glyph measures.
const DOT_WIDTH := 12

# The "3 h ago" column in the activity list, right-aligned so the sentences
# beside it start in one line.
const ACTIVITY_WHEN_WIDTH := 64

# HOW LONG A "SURE?" STAYS ARMED. The same four seconds as the staff and GM
# panels, for the same reason: long enough to mean it, short enough that a
# button left armed by a stray click does not go off a minute later.
const ARM_SECONDS := 4.0


var _in_flight: bool = false
var _busy: bool = false
var _rank: String = ""
var _in_guild: bool = false
var _found_cost: int = 0
var _name_check := RegEx.new()

# The last answer, kept so a click can redraw without asking the server again.
var _last_data: Dictionary = {}

# WHOSE ACTIONS ARE OPEN, by name, so the fifteen-second refresh redraws the
# roster with the same row still open instead of snapping it shut under the
# cursor of somebody about to press Promote.
var _open_member: String = ""

# ARMED BY KEY, NOT BY BUTTON. Every repaint builds new buttons, so a flag on a
# button would be forgotten by the refresh landing between the two presses; the
# key outlives the button and the new one is drawn armed.
var _armed: Dictionary = {}        # {"key": String, "until": float}

# THE SUITE'S DOOR INTO A REQUEST. Left invalid in the game, where every button
# here is Api.post(). The suite sets it to answer as the server would, so what
# the panel does with an answer is tested without a server.
var post_request: Callable = Callable()

@onready var rows: VBoxContainer = get_node_or_null("%guildrows")
@onready var title: Label = get_node_or_null("%guildtitle")
@onready var tag_label: Label = get_node_or_null("%guildtag")
@onready var count_label: Label = get_node_or_null("%guildcount")
@onready var fill_bar: ProgressBar = get_node_or_null("%guildfill")
@onready var entry: LineEdit = get_node_or_null("%guildentry")
@onready var action_button: Button = get_node_or_null("%guildactionbutton")
@onready var action_panel: PanelContainer = get_node_or_null("%actionpanel")
@onready var close_button: Button = get_node_or_null("%guildclosebutton")
@onready var notice: Label = get_node_or_null("%guildnotice")
@onready var footer: HBoxContainer = get_node_or_null("%footerbox")
@onready var leave_button: Button = get_node_or_null("%guildleavebutton")
@onready var disband_button: Button = get_node_or_null("%guilddisbandbutton")


# Drag by the header, resize from any edge, and come back where it was left.
# One component for all sixteen panels - see src/shared/panelwindow.gd for why
# this is not thirty lines copied into each of them.
#
# HELD IN A MEMBER, not discarded. It is a RefCounted carrying the drag state
# and the signal connections; letting it go frees it and the panel quietly
# stops responding.
var _window: PanelWindow


func _ready() -> void:
	_window = PanelWindow.attach(self, "guild")
	add_to_group("guildpanel")
	visible = false
	_name_check.compile(NAME_PATTERN)

	if action_button != null:
		action_button.pressed.connect(_on_action_pressed)
	if entry != null:
		entry.max_length = MAX_NAME
		entry.text_submitted.connect(func(_t): _on_action_pressed())
	if close_button != null:
		close_button.pressed.connect(close)
	# NO REFRESH BUTTON. There was one, labelled "R", beside the x - a letter
	# nobody could read as "refresh" - for a roster that already re-reads
	# itself every REFRESH_SECONDS and after every button pressed here.
	if leave_button != null:
		leave_button.pressed.connect(_on_leave_pressed)
	if disband_button != null:
		disband_button.pressed.connect(_on_disband_pressed)

	_set_notice("")

	var timer := Timer.new()
	timer.name = "GuildRefresh"
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
	_armed = {}
	_open_member = ""
	if entry != null:
		entry.release_focus()


func is_open() -> bool:
	return visible


func _on_refresh_timeout() -> void:
	if visible:
		_load()


# =============================================================================
# READING IT
# =============================================================================

func _load() -> void:
	if _in_flight or not Api.is_logged_in():
		return
	_in_flight = true

	var res: Dictionary = await Api.get_json("/api/guild", Api.PROBE_TIMEOUT)

	# PAST AN AWAIT - the panel may be gone.
	if not is_instance_valid(self) or not is_inside_tree():
		return
	_in_flight = false

	if not res.get("ok", false):
		_show(_failure_text(res))
		return

	var data = res.get("data", {})
	if data is Dictionary:
		_repaint(data)


# NOT _draw(). That name belongs to CanvasItem - it is the virtual Godot calls
# to paint a node, it takes no arguments, and one that takes an argument is a
# parse error rather than a shadowed function. Which is the good outcome: had
# it taken none, this would have quietly become the paint callback.
func _repaint(data: Dictionary) -> void:
	if rows == null:
		return
	_last_data = data

	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()

	_in_guild = bool(data.get("in_guild", false))
	_rank = str(data.get("rank", ""))
	_found_cost = int(data.get("cost", 0))
	var now: int = int(data.get("now", 0))

	var invites: Array = data.get("invites", [])
	var guild: Dictionary = data.get("guild", {}) if data.get("guild") is Dictionary \
		else {}
	var members: Array = guild.get("members", []) if guild.get("members") is Array else []

	# A ROW THAT HAS GONE CANNOT STAY OPEN. Somebody removed by another officer
	# between two refreshes would otherwise leave _open_member naming nobody,
	# and the next person to join under that name would arrive with their
	# actions already showing.
	if _open_member != "" and not members.any(
			func(p): return p is Dictionary and str(p.get("username", "")) == _open_member):
		_open_member = ""

	_dress_header(guild)
	_dress_controls(guild)

	# INVITATIONS FIRST. They are the only thing here waiting on the player to
	# do something, and burying them under a roster is how one sits unanswered
	# for a week.
	if not invites.is_empty():
		_add_heading("Waiting for your answer", WAITING_COLOUR)
		for one in invites:
			if one is Dictionary:
				_add_invite(one)

	if not _in_guild:
		if invites.is_empty():
			_add_note("You are not in a guild yet. Name one above to found it,"
				+ " or wait for somebody to invite you.")
		return

	# GROUPED BY RANK, each under its own heading. The heading used to be the
	# VIEWER's rank over the whole roster - so a member saw "Member" printed
	# above the leader's name, and the leader saw "Leader" above everybody.
	for group in group_members(members):
		var rank_name: String = group[0]
		var people: Array = group[1]
		_add_heading(heading_for(rank_name, people.size()),
			RANK_COLOURS.get(rank_name, HEADING_COLOUR))
		for person in people:
			_add_member(person, now)

	# A GUILD OF ONE IS WHERE EVERY GUILD STARTS, and it used to be a single row
	# above a panel of empty space. What that space is for, on the first day, is
	# the three things a new leader does not know yet.
	if members.size() <= 1:
		_add_heading("Getting started", HEADING_COLOUR)
		for line in guide_for(str(guild.get("tag", "")), _rank_at_least("officer")):
			_add_note(line)

	# WHAT HAS HAPPENED, at the bottom: who joined, left, was promoted or
	# removed, and when. The server writes it (guild_events) and sends the
	# newest dozen; a member who was away finds out here rather than by
	# noticing somebody is missing.
	var history: Array = guild.get("activity", []) if guild.get("activity") is Array else []
	if not history.is_empty():
		_add_heading("Recent activity", HEADING_COLOUR)
		for event in history:
			if event is Dictionary:
				_add_activity(event, now)


static func group_members(members: Array) -> Array:
	"""The roster as [[rank, [people...]], ...], leader first, empty groups left out.

	GROUPED HERE RATHER THAN TRUSTING THE ORDER. The server sorts leader, officer,
	member and the panel drew the rows in that order - but a heading drawn on the
	assumption that the rows arrive sorted is a heading one query change away from
	sitting over the wrong people. A rank this build has never heard of is a
	member, the lowest, as everywhere else on this ladder.
	"""
	var buckets := {"leader": [], "officer": [], "member": []}
	for person in members:
		if not (person is Dictionary):
			continue
		var rank_name: String = str(person.get("rank", "member"))
		if not buckets.has(rank_name):
			rank_name = "member"
		buckets[rank_name].append(person)
	var out: Array = []
	for rank_name in ["leader", "officer", "member"]:
		if not buckets[rank_name].is_empty():
			var people: Array = buckets[rank_name]
			people.sort_custom(func(x, y): return _before(x, y))
			out.append([rank_name, people])
	return out


static func _before(a: Dictionary, b: Dictionary) -> bool:
	# ONLINE FIRST - the people you can talk to right now - then whoever was
	# on most recently, then by name so the order is the same every time.
	var a_on: bool = bool(a.get("online", false))
	var b_on: bool = bool(b.get("online", false))
	if a_on != b_on:
		return a_on
	var a_seen: int = int(a.get("last_seen_at", 0))
	var b_seen: int = int(b.get("last_seen_at", 0))
	if not a_on and a_seen != b_seen:
		return a_seen > b_seen
	return str(a.get("username", "")).naturalnocasecmp_to(str(b.get("username", ""))) < 0


static func heading_for(rank_name: String, count: int) -> String:
	var words: Array = GROUP_HEADINGS.get(rank_name, ["Member", "Members"])
	if count <= 1:
		return str(words[0])
	return "%s · %d" % [words[1], count]


static func guide_for(tag: String, may_invite: bool) -> PackedStringArray:
	"""What a brand-new guild needs to know, in the space it used to leave empty."""
	var out := PackedStringArray()
	var shown: String = Api.guild_tag_text(tag)
	if shown != "":
		out.append("%s is your guild's tag. Everyone sees it beside your name -" % shown
			+ " above your head, in chat and on the players list.")
	if may_invite:
		out.append("Invite somebody by typing their name above. They answer from"
			+ " their own Guild panel.")
	out.append("Talk to the guild on the Guild tab in chat.")
	return out


static func header_line(guild: Dictionary, rank_name: String) -> String:
	"""The quiet line under the guild's name: how many, how many on, since when.

	ITS OWN LINE NOW, and that is the fix for the name. It used to share one row
	with the name, and a Label that shares a row gives way - so a guild called
	"the first" was drawn as "the", its own name cut short by a sentence about
	it. The name has the whole width to itself now.
	"""
	var members: Array = guild.get("members", []) if guild.get("members") is Array else []
	var online: int = 0
	for person in members:
		if person is Dictionary and bool(person.get("online", false)):
			online += 1

	# NOT `size`. Control already has one, and shadowing it warns at parse time -
	# see "Shadowing a base class property" in CLAUDE.md. A headcount, not a
	# dimension.
	var member_count: int = int(guild.get("size", members.size()))

	var parts := PackedStringArray()
	# "1 online of 1" IS ARITHMETIC ABOUT ONE PERSON, and that person is reading
	# it. A guild of one is the state every guild starts in, so it gets words.
	if member_count <= 1:
		parts.append("just you" if RANKS.find(rank_name) >= RANKS.find("officer")
			else "just you - ask an officer to invite somebody")
	else:
		parts.append("%d members, %d online" % [member_count, online])

	# FOUNDED. `created_at` had been on the wire since /api/guild was written and
	# nothing drew it; it is the one fact that makes a guild feel like it has a
	# history rather than a roster.
	var founded: String = LocalTime.date(int(guild.get("created_at", 0)))
	if founded != "":
		parts.append("founded %s" % founded)
	return "  ·  ".join(parts)


func _dress_header(guild: Dictionary) -> void:
	if title != null:
		title.text = str(guild.get("name", "Guild")) if _in_guild else "Guild"

	# THE TAG IN ITS OWN COLOUR, the one Api gives it everywhere else. This is
	# the one screen where a member finds out what everybody else sees, and it
	# should look here exactly as it looks beside their name in chat.
	if tag_label != null:
		var tag: String = Api.guild_tag_text(str(guild.get("tag", ""))) if _in_guild else ""
		tag_label.text = tag
		tag_label.visible = tag != ""
		tag_label.add_theme_color_override("font_color", Api.GUILD_TAG_COLOUR)

	# HOW FULL IT IS, as a thin bar under the line: a guild of 5 in 50 places
	# and one of 48 in 50 are different situations, and a number in a sentence
	# is the slowest way to tell them apart.
	if fill_bar != null:
		var members: Array = guild.get("members", []) if guild.get("members") is Array else []
		var capacity: int = int(guild.get("capacity", 0))
		fill_bar.visible = _in_guild and capacity > 0
		fill_bar.max_value = maxi(1, capacity)
		fill_bar.value = int(guild.get("size", members.size()))
		fill_bar.tooltip_text = "%d of %d places filled" % [int(fill_bar.value), capacity]

	if count_label == null:
		return
	if not _in_guild:
		count_label.text = "%s to found one" % GameConstants.gold_text(_found_cost)
		return
	count_label.text = header_line(guild, _rank)


static func footer_for(in_guild: bool, rank_name: String, member_count: int) -> Dictionary:
	"""Which footer buttons show, and what the dangerous one says.

	A LEADER ALONE HAS ONE WAY OUT, so they get one button. Leaving as the last
	member folds the guild on the server (see guild_leave(): "the last one out
	takes the guild with them"), which made Leave and Disband two buttons for the
	same act, one of them without a warning. It is called what it does.

	A leader with people under them keeps Leave, though the server refuses it:
	the refusal is the sentence that tells them how to get out.
	"""
	if not in_guild:
		return {"leave": false, "disband": false, "disband_text": ""}
	if rank_name == "leader" and member_count <= 1:
		return {"leave": false, "disband": true, "disband_text": "Close the guild"}
	if rank_name == "leader":
		return {"leave": true, "disband": true, "disband_text": "Disband"}
	return {"leave": true, "disband": false, "disband_text": ""}


func _dress_controls(guild: Dictionary) -> void:
	# THE BOX CHANGES JOB WITH YOUR RANK. Outside a guild it names a new one;
	# inside, and only for an officer or the leader, it invites somebody. A
	# member sees no box at all rather than one that always refuses.
	var may_invite: bool = _in_guild and _rank_at_least("officer")

	if action_panel != null:
		action_panel.visible = (not _in_guild) or may_invite
	if entry != null:
		entry.placeholder_text = "Who do you want to invite?" if may_invite \
			else "Name your guild..."
		entry.max_length = MAX_USERNAME if may_invite else MAX_NAME
	if action_button != null:
		action_button.text = "Invite" if may_invite else "Found"
		action_button.tooltip_text = (
			"They have to accept before they join."
			if may_invite
			else "Found a guild. It costs %d gold, and the gold is destroyed."
				% _found_cost)

	var members: Array = guild.get("members", []) if guild.get("members") is Array else []
	var shape: Dictionary = footer_for(_in_guild, _rank, int(guild.get("size", members.size())))
	if footer != null:
		footer.visible = _in_guild
	if leave_button != null:
		leave_button.visible = bool(shape["leave"])
		leave_button.tooltip_text = (
			"Hand the guild on first - open an officer's row - or disband it."
			if _rank == "leader"
			else "Leave this guild. An officer can invite you back.")
	if disband_button != null:
		disband_button.visible = bool(shape["disband"])
		disband_button.text = "Sure?" if _is_armed("disband") else str(shape["disband_text"])
		disband_button.tooltip_text = (
			"You are its only member. Closing it frees the name, and there is no undo."
			if str(shape["disband_text"]) == "Close the guild"
			else "Take the whole guild down. There is no undo.")


func _rank_at_least(minimum: String) -> bool:
	var mine: int = RANKS.find(_rank)
	var needed: int = RANKS.find(minimum)
	if mine < 0 or needed < 0:
		return false
	return mine >= needed


# =============================================================================
# THE ROWS
# =============================================================================

func _add_heading(text: String, colour: Color) -> void:
	# A LITTLE AIR ABOVE EACH GROUP but the first, so "Officers" reads as the
	# start of something rather than one more row.
	if rows.get_child_count() > 0:
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 4)
		rows.add_child(gap)
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", colour)
	label.add_theme_font_size_override("font_size", 12)
	rows.add_child(label)


func _add_note(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# A wrapping Label needs a width it is allowed to be narrower than, or it
	# asks for the whole sentence on one line and pushes the panel wider.
	label.custom_minimum_size = Vector2(1, 0)
	label.add_theme_color_override("font_color", QUIET_COLOUR)
	label.add_theme_font_size_override("font_size", 11)
	rows.add_child(label)


func _row_frame() -> VBoxContainer:
	# A framed row: the line itself, and room under it for what opens.
	var frame := PanelContainer.new()
	frame.theme_type_variation = &"PanelSlot"
	rows.add_child(frame)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 3)
	margin.add_theme_constant_override("margin_bottom", 3)
	frame.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	margin.add_child(box)
	return box


func _line_in(box: VBoxContainer) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	box.add_child(line)
	return line


func _small_button(text: String, hint: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = hint
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 12)
	# WIDE ENOUGH TO READ. At the text's own width "No" was a 20px box with a
	# frame thicker than its letters.
	button.custom_minimum_size = Vector2(60, 22)
	button.pressed.connect(on_press)
	return button


func _add_invite(one: Dictionary) -> void:
	var which: String = str(one.get("guild", "?"))
	var line := _line_in(_row_frame())

	var label := Label.new()
	label.text = "%s, from %s" % [which, str(one.get("by", "somebody"))]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color", WAITING_COLOUR)
	label.add_theme_font_size_override("font_size", 12)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	line.add_child(label)

	line.add_child(_small_button("Join", "Join %s" % which,
		func(): _respond(which, true)))
	line.add_child(_small_button("Decline", "Turn it down. They are not told.",
		func(): _respond(which, false)))


func _add_member(person: Dictionary, now: int) -> void:
	var who: String = str(person.get("username", "?"))
	var their_rank: String = str(person.get("rank", "member"))
	var online: bool = bool(person.get("online", false))
	var mine: bool = who.to_lower() == Api.username.to_lower()
	var actions: PackedStringArray = actions_for(_rank, Api.username, who, their_rank)
	var box := _row_frame()
	var frame: PanelContainer = box.get_parent().get_parent() as PanelContainer
	frame.set_meta("username", who)
	box.add_theme_constant_override("separation", 1)
	var line := _line_in(box)

	var dot := Label.new()
	dot.name = "dot"
	dot.text = DOT_ONLINE if online else DOT_OFFLINE
	dot.add_theme_color_override("font_color", ONLINE_COLOUR if online else OFFLINE_COLOUR)
	dot.add_theme_font_size_override("font_size", 11)
	dot.custom_minimum_size = Vector2(DOT_WIDTH, 0)
	dot.tooltip_text = "Online" if online else "Offline"
	dot.mouse_filter = Control.MOUSE_FILTER_PASS
	line.add_child(dot)

	# THEIR NAME, IN THE COLOUR THEY CHOSE, with the owner's crown or MOD / DEV
	# in front - the same function chat and the friends list draw with.
	#
	# NOT CLIPPED. A clipping Label asks for no width at all, and beside the
	# expanding spacer it would be given none - the name would vanish. A
	# username is at most twenty characters and fits the row at full length.
	NameTag.add_to(line, who, str(person.get("role", "player")), person.get("name_hue"), 13)

	# THE GUILD RANK, WORN BESIDE THE NAME, since the name's colour is theirs.
	var mark: String = str(RANK_MARKS.get(their_rank, ""))
	if mark != "":
		var worn := Label.new()
		worn.name = "rankmark"
		worn.text = mark
		worn.add_theme_color_override("font_color", RANK_COLOURS.get(their_rank, HEADING_COLOUR))
		worn.add_theme_font_size_override("font_size", 12)
		worn.tooltip_text = "Guild leader" if their_rank == "leader" else "Officer"
		worn.mouse_filter = Control.MOUSE_FILTER_PASS
		line.add_child(worn)

	if mine:
		var you := Label.new()
		you.text = "you"
		you.add_theme_color_override("font_color", QUIET_COLOUR)
		you.add_theme_font_size_override("font_size", 10)
		line.add_child(you)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_PASS
	line.add_child(spacer)

	# WHERE THEY ARE, IF THEY ARE ON; WHEN THEY WERE, IF NOT. The dot already
	# says which. An area beside somebody who left three days ago would read
	# as now, so the server sends it either way and this shows it only live.
	var where := Label.new()
	where.name = "where"
	where.text = place_text(person) if online else presence_text(person, now)
	where.add_theme_color_override("font_color", QUIET_COLOUR)
	where.add_theme_font_size_override("font_size", 10)
	if where.text != "":
		line.add_child(where)

	# WHO THEY ARE PLAYING, on a quiet second line under the name: character,
	# class and level. Indented past the dot so the names stay one column.
	var playing: String = character_text(person)
	if playing != "":
		var second := HBoxContainer.new()
		second.add_theme_constant_override("separation", 6)
		box.add_child(second)
		var indent := Control.new()
		indent.custom_minimum_size = Vector2(DOT_WIDTH, 0)
		indent.mouse_filter = Control.MOUSE_FILTER_PASS
		second.add_child(indent)
		var who_as := Label.new()
		who_as.name = "character"
		who_as.text = playing
		who_as.add_theme_color_override("font_color", QUIET_COLOUR)
		who_as.add_theme_font_size_override("font_size", 10)
		second.add_child(who_as)

	if actions.is_empty():
		return

	# ACTIONS ON CLICK, not on every row. Two or three buttons on each line -
	# Demote, Hand on, Remove - squeezed the names and put Remove one slip away
	# from Promote on every row at once. Now a row that has something to offer
	# says so with an arrow, lights up under the pointer, and opens under
	# itself when clicked.
	var open_here: bool = _open_member == who
	var arrow := Label.new()
	arrow.name = "arrow"
	arrow.text = "▾" if open_here else "▸"
	arrow.add_theme_color_override("font_color", HEADING_COLOUR)
	arrow.add_theme_font_size_override("font_size", 13)
	line.add_child(arrow)

	frame.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	frame.tooltip_text = "What you can do about %s" % who
	frame.gui_input.connect(_on_member_input.bind(who))
	_light_up(frame, open_here)
	frame.mouse_entered.connect(func(): _light_up(frame, true))
	frame.mouse_exited.connect(func(): _light_up(frame, _open_member == who))

	if not open_here:
		return
	var strip := HBoxContainer.new()
	strip.name = "actions"
	strip.add_theme_constant_override("separation", 4)
	strip.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(strip)
	for action in actions:
		strip.add_child(_action_button(action, who))


func _light_up(frame: PanelContainer, lit: bool) -> void:
	# THE ROW UNDER THE POINTER, AND THE OPEN ONE, LOOK PICKED UP: a shade
	# lighter, with a gold edge. Built from the theme's own slot box, so it is
	# the same shape and only brighter, rather than a second design.
	if not is_instance_valid(frame):
		return
	if not lit:
		frame.remove_theme_stylebox_override("panel")
		return
	var base: StyleBox = frame.get_theme_stylebox("panel", &"PanelSlot")
	var bright: StyleBox = base.duplicate() if base != null else StyleBoxFlat.new()
	if bright is StyleBoxFlat:
		var flat: StyleBoxFlat = bright as StyleBoxFlat
		flat.bg_color = flat.bg_color.lightened(0.08)
		flat.border_color = Color(0.85, 0.72, 0.42)
	frame.add_theme_stylebox_override("panel", bright)


static func character_text(person: Dictionary) -> String:
	"""'Kaelen · Warrior · lvl 12', or "" for a member with no character yet."""
	var character: String = str(person.get("character", ""))
	if character == "":
		return ""
	var parts := PackedStringArray([character])
	var class_id: String = str(person.get("class_id", ""))
	if class_id != "":
		parts.append(class_id.capitalize())
	var level: int = int(person.get("level", 0))
	if level > 0:
		parts.append("lvl %d" % level)
	return " · ".join(parts)


static func place_text(person: Dictionary) -> String:
	"""Where an online member is: 'in Field'. "" when the server did not say."""
	var area: String = str(person.get("area", ""))
	return "" if area == "" else "in %s" % AreaRegistry.display_name(area)


static func describe_event(event: Dictionary) -> String:
	"""One line of the guild's history, in words: 'lead made offi an officer'.

	A KIND THIS BUILD HAS NEVER HEARD OF still says who did what to whom, in
	the server's own word for it, rather than vanishing.
	"""
	var actor: String = str(event.get("actor", ""))
	var target: String = str(event.get("target", ""))
	match str(event.get("kind", "")):
		"founded":
			return "%s founded the guild" % actor
		"joined":
			return "%s joined" % actor
		"left":
			return "%s left" % actor
		"invited":
			return "%s invited %s" % [actor, target]
		"promoted":
			return "%s made %s an officer" % [actor, target]
		"demoted":
			return "%s made %s a member" % [actor, target]
		"leader":
			return "%s handed the guild to %s" % [actor, target]
		"removed":
			return "%s removed %s" % [actor, target]
		"renamed":
			# NO NAME FOR WHO DID IT - the server leaves it out on purpose.
			return "Staff renamed the guild from %s" % str(event.get("detail", "?"))
	return ("%s %s %s" % [actor, str(event.get("kind", "?")), target]).strip_edges()


func _add_activity(event: Dictionary, now: int) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	rows.add_child(line)

	var when := Label.new()
	when.text = ago_text(int(event.get("at", 0)), now)
	when.custom_minimum_size = Vector2(ACTIVITY_WHEN_WIDTH, 0)
	when.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	when.add_theme_color_override("font_color", OFFLINE_COLOUR.lightened(0.15))
	when.add_theme_font_size_override("font_size", 10)
	when.tooltip_text = LocalTime.full(int(event.get("at", 0)))
	when.mouse_filter = Control.MOUSE_FILTER_PASS
	line.add_child(when)

	var what := Label.new()
	what.text = describe_event(event)
	what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	what.custom_minimum_size = Vector2(1, 0)
	what.add_theme_color_override("font_color", QUIET_COLOUR)
	what.add_theme_font_size_override("font_size", 11)
	line.add_child(what)


static func ago_text(at: int, now: int) -> String:
	# The one copy lives in LocalTime now; this name stays for the trade panel.
	return LocalTime.ago(at, now)


static func actions_for(my_rank: String, me: String, who: String, their_rank: String) -> PackedStringArray:
	"""What the viewer may do to one member, as action ids, in the order offered.

	YOURSELF GETS NOTHING. Leaving is the footer's job, and a Remove button beside
	your own name is a different action wearing the same word.

	STRICTLY ABOVE, the same rule the server enforces: an officer is offered
	nothing against another officer, because pressing it would be refused.
	"""
	var out := PackedStringArray()
	if who.to_lower() == me.to_lower():
		return out
	var theirs: int = RANKS.find(their_rank)
	var mine: int = RANKS.find(my_rank)
	if mine < 0 or mine <= theirs:
		return out
	if my_rank == "leader":
		if their_rank == "member":
			out.append("promote")
		elif their_rank == "officer":
			out.append("demote")
			out.append("handon")
	out.append("remove")
	return out


func _action_button(action: String, who: String) -> Button:
	# THE TWO THAT CANNOT BE TAKEN BACK ASK TWICE. Promote and demote undo each
	# other; handing the guild on and removing somebody do not - one gives away
	# the leadership, the other takes somebody out of the guild and its channel.
	var key: String = "%s:%s" % [action, who]
	var spec: Array = {
		"promote": ["Promote", "Make %s an officer" % who],
		"demote": ["Demote", "Make %s a member again" % who],
		"handon": ["Make leader", "Hand the guild to %s. You become an officer." % who],
		"remove": ["Remove", "Remove %s from the guild" % who],
	}.get(action, [action, ""])
	var button := _small_button(
		"Sure?" if _is_armed(key) else str(spec[0]), str(spec[1]),
		func(): _on_action(action, who))
	button.set_meta("action", action)
	if action == "remove" or action == "handon":
		button.add_theme_color_override("font_color", DANGER_COLOUR)
	return button


func _on_member_input(event: InputEvent, who: String) -> void:
	if not (event is InputEventMouseButton) or not event.pressed \
			or event.button_index != MOUSE_BUTTON_LEFT:
		return
	_open_member = "" if _open_member == who else who
	_armed = {}
	_set_notice("")
	_repaint(_last_data)


func _on_action(action: String, who: String) -> void:
	if action == "remove" or action == "handon":
		if not _arm_or_fire("%s:%s" % [action, who],
				"Press again to remove %s from the guild." % who if action == "remove"
				else "Press again to make %s the leader. You become an officer." % who):
			return
	match action:
		"promote":
			await _set_rank(who, "officer")
		"demote":
			await _set_rank(who, "member")
		"handon":
			await _set_rank(who, "leader")
		"remove":
			await _kick(who)


func _is_armed(key: String) -> bool:
	return str(_armed.get("key", "")) == key \
		and Time.get_ticks_msec() / 1000.0 < float(_armed.get("until", 0.0))


func _arm_or_fire(key: String, warning: String) -> bool:
	# First press: arm, say what the second one will do, and return false.
	# Second press inside ARM_SECONDS: disarm and return true - go ahead.
	if _is_armed(key):
		_armed = {}
		return true
	_armed = {"key": key, "until": Time.get_ticks_msec() / 1000.0 + ARM_SECONDS}
	_show(warning)
	_repaint(_last_data)
	_disarm_later(key)
	return false


func _disarm_later(key: String) -> void:
	# PUT THE WORD BACK. A button left reading "Sure?" after the window has shut
	# says the next press will act when it will only arm again.
	await get_tree().create_timer(ARM_SECONDS).timeout
	if not is_instance_valid(self) or not is_inside_tree():
		return
	if str(_armed.get("key", "")) == key and not _is_armed(key):
		_armed = {}
		_set_notice("")
		_repaint(_last_data)


static func presence_text(person: Dictionary, now: int) -> String:
	var seen: int = int(person.get("last_seen_at", 0))
	if seen <= 0 or now <= 0:
		return "offline"

	# AGED AGAINST THE SERVER'S CLOCK, which is why the answer carries one.
	# Measuring against this machine's clock shows "last seen in 3 hours" to
	# anybody whose system time is wrong, and plenty of them are.
	return LocalTime.ago(seen, now)


# =============================================================================
# CHANGING IT
# =============================================================================

func _on_action_pressed() -> void:
	if entry == null or _busy:
		return

	var typed: String = entry.text.strip_edges()
	if typed == "":
		return

	if _in_guild and _rank_at_least("officer"):
		await _act("/api/guild/invite", {"username": typed},
			"Invited %s. Their Guild button lights up until they answer." % typed)
	else:
		if _name_check.search(typed) == null:
			_show("A guild name is 3 to %d characters: letters, numbers," % MAX_NAME
				+ " spaces, apostrophes and hyphens.")
			return
		# THE COST COMES OUT OF THE CHARACTER YOU ARE PLAYING, so the slot
		# has to be the one the rest of the game means by "you" - the same
		# index the inventory and the bank send.
		await _act("/api/guild/create",
			{"name": typed, "slot": CharacterData.active_character_index},
			"%s is founded. You are its leader." % typed)

	if is_instance_valid(self) and entry != null:
		entry.text = ""


func _respond(which: String, accept: bool) -> void:
	var said: String = "You are in %s." % which if accept \
		else "Turned down %s." % which
	await _act("/api/guild/respond", {"guild": which, "accept": accept}, said)


func _kick(who: String) -> void:
	await _act("/api/guild/kick", {"username": who},
		"%s is out of the guild." % who)


func _set_rank(who: String, rank: String) -> void:
	var said: String = "%s is now the leader. You are an officer." % who \
		if rank == "leader" else "%s is now %s." % [who, RANK_WITH_ARTICLE.get(rank, rank)]
	await _act("/api/guild/rank", {"username": who, "rank": rank}, said)


func _on_leave_pressed() -> void:
	await _act("/api/guild/leave", {}, "You have left the guild.")


func _on_disband_pressed() -> void:
	# TWO PRESSES. Removing one person is a thing to undo by inviting them back;
	# disbanding takes the name, the roster and the channel with it and nothing
	# brings those back. Armed by key, like Remove, so a refresh landing between
	# the presses redraws the button still reading "Sure?".
	if not _arm_or_fire("disband",
			"Press again to close the guild for good. This cannot be undone."):
		return
	await _act("/api/guild/disband", {}, "The guild is gone.")


func _act(path: String, body: Dictionary, success_text: String) -> void:
	# ONE PLACE SENDS AND ONE PLACE RE-READS. Every button here does the same
	# three things - ask, say what happened, redraw from the server - and
	# writing that out seven times is seven chances for one of them to forget
	# the redraw and leave the panel showing a roster that is no longer true.
	if _busy:
		return
	_busy = true
	_set_notice("")

	var res: Dictionary = {}
	if post_request.is_valid():
		res = await post_request.call(path, body)
	else:
		res = await Api.post(path, body)

	if not is_instance_valid(self) or not is_inside_tree():
		return
	_busy = false

	if res.get("ok", false):
		# GOLD THE SERVER TOOK, COPIED IN. Founding is paid from the purse and
		# then the bank, and the answer carries both balances after it. On day 1
		# nothing read them: a founder who paid 1,000 carried and 4,000 banked
		# went on seeing 1,000 and 4,500 until a relog, and the shop offered
		# what the server then refused.
		var paid = res.get("data", {})
		if paid is Dictionary:
			CharacterData.adopt_server_gold(paid, get_tree().get_first_node_in_group("player"))
		_show(success_text + _payment_note(res))
		# THE ROW'S JOB IS DONE. Promoted, demoted or gone, what it offered has
		# changed, and leaving it open would show the old choices for a moment.
		_open_member = ""
	else:
		_show(_failure_text(res))

	_load()


func _payment_note(res: Dictionary) -> String:
	# WHERE THE GOLD CAME FROM, when any did. Founding can be paid out of the
	# bank, and somebody who did not realise their pocket was nearly empty
	# should be able to see that the bank covered it rather than wondering
	# why the number moved.
	var data = res.get("data", {})
	if not (data is Dictionary) or not data.has("paid"):
		return ""

	var carried: int = int(data.get("from_carried", 0))
	var banked: int = int(data.get("from_bank", 0))
	if banked <= 0:
		return " It cost %d gold." % int(data.get("paid", 0))
	if carried <= 0:
		return " It cost %d gold, all from the bank." % int(data.get("paid", 0))
	return " It cost %d gold - %d carried and %d from the bank." % [
		int(data.get("paid", 0)), carried, banked]


func _failure_text(res: Dictionary) -> String:
	# THE SERVER'S OWN SENTENCE WHENEVER THERE IS ONE. Api._request has already
	# dug it out of the body and put it in `error`; reading res["message"] -
	# which that layer does not set - is the mistake the chat panel made, and
	# it turned every refusal into four useless words.
	var status: int = int(res.get("status", 0))
	var said: String = str(res.get("error", "")).strip_edges()

	if status == 0:
		return ApiScript.no_answer_text()
	if status == 401:
		return "You are not signed in."
	if status == 404:
		# 404 IS USUALLY THE SERVER DECLINING TO CONFIRM ANYTHING - it is what
		# a stranger gets and what somebody reaching above their rank gets, on
		# purpose, so this must not say which it was.
		#
		# BUT NOT ALWAYS. Those refusals all carry the literal "Not found.";
		# a 404 with anything else in it is a specific answer - "That slot is
		# empty" - and swallowing that would hide a real problem behind a
		# sentence about permissions.
		if said != "" and said != "Not found.":
			return said
		return "That is not something you can do."
	if said != "":
		return said
	return "That did not work (HTTP %d)." % status


func _show(text: String) -> void:
	_set_notice(text)


func _set_notice(text: String) -> void:
	if notice == null:
		return
	notice.text = text
	notice.visible = text != ""
