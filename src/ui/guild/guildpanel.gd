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


# How often an open panel re-reads. Presence is the only thing here that goes
# stale on its own, and the server calls somebody offline after 45 seconds of
# silence, so anything slower shows green dots for people who have gone.
const REFRESH_SECONDS := 15.0

# Matches the server's own rule, so an impossible name is refused at the
# keyboard rather than by a round trip. See GUILD_NAME_PATTERN in app.py.
const NAME_PATTERN := "^[A-Za-z0-9][A-Za-z0-9 '\\-]{2,23}$"

# The server's own ladder, lowest first. Used only to decide which buttons to
# offer; the server decides whether they work.
const RANKS := ["member", "officer", "leader"]

const RANK_LABELS := {
	"leader": "Leader",
	"officer": "Officer",
	"member": "Member",
}

const RANK_COLOURS := {
	"leader": Color(1.0, 0.84, 0.42),
	"officer": Color(0.72, 0.86, 1.0),
	"member": Color(0.78, 0.74, 0.66),
}

const ONLINE_COLOUR := Color(0.45, 0.9, 0.5)
const OFFLINE_COLOUR := Color(0.45, 0.42, 0.38)
const HEADING_COLOUR := Color(0.85, 0.78, 0.62)
const WAITING_COLOUR := Color(1.0, 0.82, 0.42)


var _in_flight: bool = false
var _busy: bool = false
var _rank: String = ""
var _in_guild: bool = false
var _found_cost: int = 0
var _name_check := RegEx.new()

@onready var rows: VBoxContainer = get_node_or_null("%guildrows")
@onready var title: Label = get_node_or_null("%guildtitle")
@onready var count_label: Label = get_node_or_null("%guildcount")
@onready var entry: LineEdit = get_node_or_null("%guildentry")
@onready var action_button: Button = get_node_or_null("%guildactionbutton")
@onready var action_panel: PanelContainer = get_node_or_null("%actionpanel")
@onready var close_button: Button = get_node_or_null("%guildclosebutton")
@onready var refresh_button: Button = get_node_or_null("%guildrefreshbutton")
@onready var notice: Label = get_node_or_null("%guildnotice")
@onready var footer: HBoxContainer = get_node_or_null("%footerbox")
@onready var leave_button: Button = get_node_or_null("%guildleavebutton")
@onready var disband_button: Button = get_node_or_null("%guilddisbandbutton")


func _ready() -> void:
	add_to_group("guildpanel")
	visible = false
	_name_check.compile(NAME_PATTERN)

	if action_button != null:
		action_button.pressed.connect(_on_action_pressed)
	if entry != null:
		entry.max_length = 24
		entry.text_submitted.connect(func(_t): _on_action_pressed())
	if close_button != null:
		close_button.pressed.connect(close)
	if refresh_button != null:
		refresh_button.pressed.connect(func(): _load())
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

	_add_heading(RANK_LABELS.get(_rank, "Members"), HEADING_COLOUR)
	for person in guild.get("members", []):
		if person is Dictionary:
			_add_member(person, now)


func _dress_header(guild: Dictionary) -> void:
	if title != null:
		title.text = str(guild.get("name", "Guild")) if _in_guild else "Guild"
	if count_label == null:
		return
	if not _in_guild:
		count_label.text = "%s to found one" % GameConstants.gold_text(_found_cost)
		return

	var online: int = 0
	for person in guild.get("members", []):
		if person is Dictionary and bool(person.get("online", false)):
			online += 1
	count_label.text = "%d online of %d" % [online, int(guild.get("size", 0))]


func _dress_controls(_guild: Dictionary) -> void:
	# THE BOX CHANGES JOB WITH YOUR RANK. Outside a guild it names a new one;
	# inside, and only for an officer or the leader, it invites somebody. A
	# member sees no box at all rather than one that always refuses.
	var may_invite: bool = _in_guild and _rank_at_least("officer")

	if action_panel != null:
		action_panel.visible = (not _in_guild) or may_invite
	if entry != null:
		entry.placeholder_text = "Who do you want to invite?" if may_invite \
			else "Name your guild..."
		entry.max_length = 20 if may_invite else 24
	if action_button != null:
		action_button.text = "Invite" if may_invite else "Found"
		action_button.tooltip_text = (
			"They have to accept before they join."
			if may_invite
			else "Found a guild. It costs %d gold, and the gold is destroyed."
				% _found_cost)

	if footer != null:
		footer.visible = _in_guild
	if leave_button != null:
		leave_button.visible = _in_guild
		# A LEADER WITH PEOPLE UNDER THEM CANNOT WALK OUT, and the server says
		# so. The button stays, because the sentence it produces is the useful
		# part - hiding it would leave somebody wondering how to get out.
		leave_button.tooltip_text = (
			"Hand the guild on first, or disband it."
			if _rank == "leader"
			else "Leave this guild.")
	if disband_button != null:
		disband_button.visible = _in_guild and _rank == "leader"


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
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", colour)
	label.add_theme_font_size_override("font_size", 12)
	rows.add_child(label)


func _add_note(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color(0.6, 0.56, 0.5))
	label.add_theme_font_size_override("font_size", 11)
	rows.add_child(label)


func _row_frame() -> HBoxContainer:
	var frame := PanelContainer.new()
	frame.theme_type_variation = &"PanelSlot"
	rows.add_child(frame)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 3)
	margin.add_theme_constant_override("margin_bottom", 3)
	frame.add_child(margin)

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	margin.add_child(line)
	return line


func _small_button(text: String, hint: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = hint
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 11)
	button.pressed.connect(on_press)
	return button


func _add_invite(one: Dictionary) -> void:
	var which: String = str(one.get("guild", "?"))
	var line := _row_frame()

	var label := Label.new()
	label.text = "%s, from %s" % [which, str(one.get("by", "somebody"))]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color", WAITING_COLOUR)
	label.add_theme_font_size_override("font_size", 12)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	line.add_child(label)

	line.add_child(_small_button("Join", "Join %s" % which,
		func(): _respond(which, true)))
	line.add_child(_small_button("No", "Turn it down. They are not told.",
		func(): _respond(which, false)))


func _add_member(person: Dictionary, now: int) -> void:
	var who: String = str(person.get("username", "?"))
	var their_rank: String = str(person.get("rank", "member"))
	var online: bool = bool(person.get("online", false))
	var line := _row_frame()

	var dot := Label.new()
	dot.text = "+" if online else "-"
	dot.add_theme_color_override("font_color",
		ONLINE_COLOUR if online else OFFLINE_COLOUR)
	dot.add_theme_font_size_override("font_size", 13)
	line.add_child(dot)

	var name_label := Label.new()
	name_label.text = who
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# SAME COLOUR AS OVER THEIR HEAD AND IN CHAT. Api owns the mapping so the
	# three cannot drift apart. Guild rank is shown separately, beside it -
	# the two ladders are different things and colouring by both would say
	# neither clearly.
	name_label.add_theme_color_override("font_color",
		Api.colour_for_role(str(person.get("role", "player"))))
	name_label.add_theme_font_size_override("font_size", 12)
	line.add_child(name_label)

	var rank_label := Label.new()
	rank_label.text = RANK_LABELS.get(their_rank, their_rank)
	rank_label.add_theme_color_override("font_color",
		RANK_COLOURS.get(their_rank, OFFLINE_COLOUR))
	rank_label.add_theme_font_size_override("font_size", 10)
	line.add_child(rank_label)

	var seen := Label.new()
	seen.text = "online" if online else _last_seen_text(person, now)
	seen.add_theme_color_override("font_color", Color(0.62, 0.58, 0.52))
	seen.add_theme_font_size_override("font_size", 10)
	line.add_child(seen)

	for spec in _buttons_for(who, their_rank):
		line.add_child(_small_button(String(spec[0]), String(spec[1]), spec[2]))


func _buttons_for(who: String, their_rank: String) -> Array:
	# YOURSELF GETS NOTHING. Leaving is the footer's job, and a Remove button
	# beside your own name is a different action wearing the same word.
	if who.to_lower() == Api.username.to_lower():
		return []

	var out: Array = []
	var theirs: int = RANKS.find(their_rank)
	var mine: int = RANKS.find(_rank)

	# STRICTLY ABOVE, the same rule the server enforces. An officer sees no
	# buttons beside another officer, because pressing one would be refused.
	if mine <= theirs:
		return out

	if _rank == "leader":
		if their_rank == "member":
			out.append(["Promote", "Make %s an officer" % who,
				func(): _set_rank(who, "officer")])
		elif their_rank == "officer":
			out.append(["Demote", "Make %s a member again" % who,
				func(): _set_rank(who, "member")])
			out.append(["Hand on", "Make %s the leader. You become an officer."
				% who, func(): _set_rank(who, "leader")])

	out.append(["Remove", "Remove %s from the guild" % who,
		func(): _kick(who)])
	return out


func _last_seen_text(person: Dictionary, now: int) -> String:
	var seen: int = int(person.get("last_seen_at", 0))
	if seen <= 0 or now <= 0:
		return "offline"

	# AGED AGAINST THE SERVER'S CLOCK, which is why the answer carries one.
	# Measuring against this machine's clock shows "last seen in 3 hours" to
	# anybody whose system time is wrong, and plenty of them are.
	var gap: int = max(0, now - seen)
	if gap < 3600:
		return "%d min ago" % int(gap / 60.0)
	if gap < 86400:
		return "%d h ago" % int(gap / 3600.0)
	return "%d days ago" % int(gap / 86400.0)


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
			"Asked %s. They will see it next time they look." % typed)
	else:
		if _name_check.search(typed) == null:
			_show("A guild name is 3 to 24 characters: letters, numbers,"
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
		if rank == "leader" else "%s is now %s." % [who, RANK_LABELS.get(rank, rank)]
	await _act("/api/guild/rank", {"username": who, "rank": rank}, said)


func _on_leave_pressed() -> void:
	await _act("/api/guild/leave", {}, "You have left the guild.")


func _on_disband_pressed() -> void:
	# TWO PRESSES, UNLIKE EVERY OTHER BUTTON HERE. Removing one person is a
	# thing to undo by inviting them back; disbanding takes the name, the
	# roster and the channel with it and nothing brings those back. The
	# confirmation is the only place in this panel where the extra click is
	# worth what it costs.
	if disband_button == null:
		return
	if not disband_button.has_meta("armed"):
		disband_button.set_meta("armed", true)
		disband_button.text = "Sure?"
		_show("Press again to take the guild down. This cannot be undone.")
		await get_tree().create_timer(4.0).timeout
		if is_instance_valid(disband_button) and disband_button.has_meta("armed"):
			disband_button.remove_meta("armed")
			disband_button.text = "Disband"
			_set_notice("")
		return

	disband_button.remove_meta("armed")
	disband_button.text = "Disband"
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

	var res: Dictionary = await Api.post(path, body)

	if not is_instance_valid(self) or not is_inside_tree():
		return
	_busy = false

	if res.get("ok", false):
		_show(success_text + _payment_note(res))
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
		return "No answer from the server. Is it running?"
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
