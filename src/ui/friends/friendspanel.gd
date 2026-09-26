# friendspanel.gd — who you know, who is on, and who is waiting for an answer.
#
# THE LIST IS THE SERVER'S, NOT THIS PANEL'S. Everything below is drawn from
# one GET /api/friends and thrown away on the next one. There is no local copy
# to fall out of step, no "optimistic" row added before the server has agreed,
# and every button does its work by asking and then re-reading the whole list.
# A friends list that disagrees with the server about who your friends are is
# worse than a slow one.
#
# WHY A REQUEST HAS TO BE ACCEPTED. Appearing on somebody's list is standing
# permission to watch when they are online. One-sided adding would mean anyone
# who knows your name can follow you around the clock without you ever being
# asked, so the server keeps a request pending until it is answered - see the
# friends table in app.py. This panel is the answering.
extends Control


# How often an open panel re-reads. Presence is the only thing here that goes
# stale on its own, and the server calls somebody offline after 45 seconds of
# silence, so a slower refresh than this would show green dots for people who
# had already gone.
const REFRESH_SECONDS := 15.0

# Matches the server's own username rule. Checked here so an obviously
# impossible name is refused at the keyboard rather than by a round trip.
const NAME_PATTERN := "^[A-Za-z0-9_]{3,20}$"

# THE CROWN, AND THE THIRD PLACE THAT DRAWS IT.
# It is over the owner's head in the world (player.gd) and beside their name in
# chat (chatpanel.gd), and it was missing here - so the one account that is
# meant to be recognisable everywhere looked like anybody else on the one screen
# that is nothing but a list of names.
#
# SIZED AT THE ART'S OWN 26x15, for the same reason chat pins its [img] to those
# numbers: this is pixel art with an outline, and any other size smears it.
const CROWN_PATH := "res://art/enemy/behemothcrown.png"
const CROWN_SIZE := Vector2(26, 15)

# The one rank that wears it. Dev, mod and player get their colour and no more.
const CROWN_RANK := "owner"


var _in_flight: bool = false
var _busy: bool = false
var _name_check := RegEx.new()

@onready var rows: VBoxContainer = get_node_or_null("%friendsrows")
@onready var add_entry: LineEdit = get_node_or_null("%friendsaddentry")
@onready var add_button: Button = get_node_or_null("%friendsaddbutton")
@onready var close_button: Button = get_node_or_null("%friendsclosebutton")
@onready var refresh_button: Button = get_node_or_null("%friendsrefreshbutton")
@onready var notice: Label = get_node_or_null("%friendsnotice")
@onready var count_label: Label = get_node_or_null("%friendscount")


func _ready() -> void:
	add_to_group("friendspanel")
	visible = false
	_name_check.compile(NAME_PATTERN)

	if add_button != null:
		add_button.pressed.connect(_on_add_pressed)
	if add_entry != null:
		add_entry.max_length = 20
		add_entry.text_submitted.connect(func(_t): _on_add_pressed())
	if close_button != null:
		close_button.pressed.connect(close)
	if refresh_button != null:
		refresh_button.pressed.connect(func(): _load())

	_set_notice("")

	var timer := Timer.new()
	timer.name = "FriendsRefresh"
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
	if add_entry != null:
		add_entry.release_focus()


func _on_refresh_timeout() -> void:
	if visible:
		_load()


# =============================================================================
# READING THE LIST
# =============================================================================

func _load() -> void:
	if _in_flight or not Api.is_logged_in():
		return
	_in_flight = true

	var res: Dictionary = await Api.get_json("/api/friends", Api.PROBE_TIMEOUT)

	# PAST AN AWAIT - the panel may be gone.
	if not is_instance_valid(self) or not is_inside_tree():
		return
	_in_flight = false

	if not res.get("ok", false):
		_show_message(_failure_text(res))
		return

	var data = res.get("data", {})
	if data is Dictionary:
		_repaint(data)


# NOT _draw(). That name belongs to CanvasItem - it is the virtual Godot calls
# to paint a node, it takes no arguments, and declaring one that does is a
# parse error rather than a shadowed function. Which is the good outcome: had
# it taken none, this would have quietly become the paint callback and run on
# every redraw.
func _repaint(data: Dictionary) -> void:
	if rows == null:
		return

	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()

	var friends: Array = data.get("friends", [])
	var incoming: Array = data.get("incoming", [])
	var outgoing: Array = data.get("outgoing", [])
	var now: int = int(data.get("now", 0))

	if count_label != null:
		var online: int = 0
		for person in friends:
			if person is Dictionary and bool(person.get("online", false)):
				online += 1
		count_label.text = "%d online of %d" % [online, friends.size()]

	# REQUESTS FIRST. They are the only thing in this panel that is waiting on
	# the player to do something, and burying them under the friends list is
	# how a request sits unanswered for a week.
	if not incoming.is_empty():
		_add_heading("Waiting for your answer", Color(1.0, 0.82, 0.42))
		for person in incoming:
			if person is Dictionary:
				_add_row(person, now, "incoming")

	_add_heading("Friends", Color(0.85, 0.78, 0.62))
	if friends.is_empty():
		_add_note("Nobody yet. Type a name above to ask somebody.")
	else:
		for person in friends:
			if person is Dictionary:
				_add_row(person, now, "friend")

	if not outgoing.is_empty():
		_add_heading("Asked, no answer yet", Color(0.7, 0.66, 0.58))
		for person in outgoing:
			if person is Dictionary:
				_add_row(person, now, "outgoing")


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


func _add_row(person: Dictionary, now: int, kind: String) -> void:
	var who: String = str(person.get("username", "?"))

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

	if kind == "friend":
		var dot := Label.new()
		dot.text = "+" if bool(person.get("online", false)) else "-"
		dot.add_theme_color_override("font_color",
			Color(0.45, 0.9, 0.5) if bool(person.get("online", false))
			else Color(0.45, 0.42, 0.38))
		dot.add_theme_font_size_override("font_size", 13)
		line.add_child(dot)

	# The crown goes BEFORE the name, where chat puts it, so the two read the
	# same way round.
	var role: String = str(person.get("role", "player"))
	if role == CROWN_RANK:
		var crown := TextureRect.new()
		crown.texture = load(CROWN_PATH) as Texture2D
		# EXPAND_IGNORE_SIZE or custom_minimum_size is only a floor and the art
		# sets the real width - the same trap the board header and the inventory
		# icon both hit. With it, 26x15 is exactly 26x15.
		crown.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		crown.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		crown.custom_minimum_size = CROWN_SIZE
		crown.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		crown.tooltip_text = "Owner"
		line.add_child(crown)

	var name_label := Label.new()
	name_label.text = who
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# SAME COLOUR AS OVER THEIR HEAD AND IN CHAT. Api owns the mapping so the
	# three cannot drift apart.
	name_label.add_theme_color_override("font_color", Api.colour_for_role(role))
	name_label.add_theme_font_size_override("font_size", 12)
	line.add_child(name_label)

	if kind == "friend":
		var status := Label.new()
		status.text = _presence_text(person, now)
		status.add_theme_color_override("font_color", Color(0.62, 0.58, 0.52))
		status.add_theme_font_size_override("font_size", 10)
		line.add_child(status)

	for spec in _buttons_for(kind, who):
		var button := Button.new()
		button.text = String(spec[0])
		button.tooltip_text = String(spec[1])
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 11)
		button.pressed.connect(spec[2])
		line.add_child(button)


func _buttons_for(kind: String, who: String) -> Array:
	if kind == "incoming":
		return [
			["Accept", "Add %s to your friends" % who, func(): _respond(who, true)],
			["No", "Turn the request down. They are not told." ,
				func(): _respond(who, false)],
		]
	if kind == "outgoing":
		return [["Cancel", "Take back your request to %s" % who,
			func(): _remove(who)]]
	return [["Remove", "Remove %s from your friends" % who,
		func(): _remove(who)]]


func _presence_text(person: Dictionary, now: int) -> String:
	if bool(person.get("online", false)):
		return "online"

	var seen: int = int(person.get("last_seen_at", 0))
	if seen <= 0 or now <= 0:
		return "offline"

	# AGED AGAINST THE SERVER'S CLOCK, which is why the response carries one.
	# Measuring against this machine's clock shows "last seen in 3 hours" to
	# anybody whose system time is wrong, and plenty of them are.
	var gap: int = max(0, now - seen)
	if gap < 3600:
		return "%d min ago" % int(gap / 60.0)
	if gap < 86400:
		return "%d h ago" % int(gap / 3600.0)
	return "%d days ago" % int(gap / 86400.0)


# =============================================================================
# CHANGING THE LIST
# =============================================================================

func _on_add_pressed() -> void:
	if add_entry == null or _busy:
		return

	var who: String = add_entry.text.strip_edges()
	if who == "":
		return

	if _name_check.search(who) == null:
		_show_message("A name is 3 to 20 letters, numbers or underscores.")
		return
	if who.to_lower() == Api.username.to_lower():
		_show_message("You cannot add yourself.")
		return

	await _act("/api/friends/request", {"username": who},
		"Asked %s. They will see it next time they look." % who)
	if is_instance_valid(self) and add_entry != null:
		add_entry.text = ""


func _respond(who: String, accept: bool) -> void:
	var said: String = "%s is on your list." % who if accept \
		else "Request from %s turned down." % who
	await _act("/api/friends/respond", {"username": who, "accept": accept}, said)


func _remove(who: String) -> void:
	await _act("/api/friends/remove", {"username": who}, "%s removed." % who)


func _act(path: String, body: Dictionary, success_text: String) -> void:
	# ONE PLACE SENDS AND ONE PLACE RE-READS. Every button here does the same
	# three things - ask, say what happened, redraw from the server - and
	# writing that out four times is four chances for one of them to forget
	# the redraw and leave the panel showing a list that is no longer true.
	if _busy:
		return
	_busy = true
	_set_notice("")

	var res: Dictionary = await Api.post(path, body)

	if not is_instance_valid(self) or not is_inside_tree():
		return
	_busy = false

	if res.get("ok", false):
		_show_message(success_text)
	else:
		_show_message(_failure_text(res))

	_load()


func _failure_text(res: Dictionary) -> String:
	# SAME BUG AS chatpanel.gd's _refusal HAD, and fixed the same way. The
	# server's sentence arrives in res["error"], already extracted by
	# Api._request; this looked for res["message"], which that layer does not
	# set, so "your friends list is full" and "you have already asked them"
	# both came out as "That did not work."
	var status: int = int(res.get("status", 0))
	var said: String = str(res.get("error", "")).strip_edges()

	if status == 0:
		return "No answer from the server. Is it running?"
	if status == 401:
		return "You are not signed in."
	if status == 404:
		return "No account by that name."

	# The server's own sentence for 400 and 409 - it is the one that knows
	# whose list is full, or that you have already asked.
	if said != "":
		return said
	return "That did not work (HTTP %d)." % status


func _show_message(text: String) -> void:
	_set_notice(text)


func _set_notice(text: String) -> void:
	if notice == null:
		return
	notice.text = text
	notice.visible = text != ""
