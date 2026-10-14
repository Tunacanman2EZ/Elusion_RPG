# partypanel.gd - Social > Party: who you are with, and asking somebody to
# join (0.42.0).
#
# The owner: "we need to be able to start parties so we need a tab for
# parties", and of what it should show: the members - each one's class,
# level, area and health - with party chat and each other on the map besides
# (chatpanel.gd's Party tab, mapscreen.gd).
#
# THE SERVER KEEPS THE PARTY (app.py, PARTIES); this window reads GET
# /api/party and posts each action, and every route answers with the whole
# party again, so the window draws exactly what the server holds. Two to
# four: anybody with no party may ask somebody, and the party is made when
# they accept; the leader asks, removes and hands it on; down to one, it is
# gone. An invitation waits two minutes for an answer.
#
# HEALTH, LIVE WHERE IT CAN BE: yours from your own character, a member in your
# area from their picture (remoteplayer.gd, THEIR AIM AND THEIR HEALTH), and
# anybody else from their last save - read again every REFRESH_SECONDS while
# the window is open.
extends Control
class_name PartyPanel


signal closed()


const REQUEST_TIMEOUT := 6.0
const REFRESH_SECONDS := 3.0
const NAME_COLOUR := Color(0.95, 0.92, 0.84)
const DETAIL_COLOUR := Color(0.72, 0.68, 0.62)
const AWAY_COLOUR := Color(0.55, 0.52, 0.5)
const GOOD_COLOUR := Color(0.6, 0.9, 0.7)
const LEADER_COLOUR := Color(1.0, 0.82, 0.42)

@onready var close_button: Button = get_node_or_null("%closebutton")
@onready var summary_label: Label = get_node_or_null("%summarylabel")
@onready var list: VBoxContainer = get_node_or_null("%list")
@onready var invites_box: VBoxContainer = get_node_or_null("%invites")
@onready var invite_row: HBoxContainer = get_node_or_null("%inviterow")
@onready var invite_name: LineEdit = get_node_or_null("%invitename")
@onready var invite_button: Button = get_node_or_null("%invitebutton")
@onready var leave_button: Button = get_node_or_null("%leavebutton")
@onready var notice_label: Label = get_node_or_null("%noticelabel")

# Where requests go; seams for the suite, which answers them itself.
var fetch: Callable = Callable(self, "_fetch")
var send: Callable = Callable(self, "_send")
# The last answer from the server.
var answer: Dictionary = {}

var _window: PanelWindow
var _timer: Timer = null
var _busy: bool = false


func _ready() -> void:
	_window = PanelWindow.attach(self, "party")
	if close_button != null:
		close_button.pressed.connect(close)
	if invite_button != null:
		invite_button.pressed.connect(_on_invite_pressed)
	if invite_name != null:
		invite_name.text_submitted.connect(func(_text: String) -> void: _on_invite_pressed())
	if leave_button != null:
		leave_button.pressed.connect(_on_leave_pressed)
	_timer = Timer.new()
	_timer.name = "refresh"
	_timer.wait_time = REFRESH_SECONDS
	_timer.timeout.connect(_on_refresh)
	add_child(_timer)
	visible = false


# =============================================================================
# OPENING AND CLOSING
# =============================================================================

func open() -> void:
	visible = true
	if _timer != null:
		_timer.start()
	await load_party()


func close() -> void:
	visible = false
	if _timer != null:
		_timer.stop()
	closed.emit()


func toggle() -> void:
	if visible:
		close()
	else:
		await open()


func _on_refresh() -> void:
	if visible and not _busy:
		await load_party(true)


# =============================================================================
# THE SERVER
# =============================================================================

func load_party(quiet: bool = false) -> void:
	if _busy:
		return
	_busy = true
	if not quiet:
		_say("")
	var res: Dictionary = await fetch.call("/api/party")
	# PAST AN AWAIT: logging out frees every window, a door changes the scene.
	if not is_instance_valid(self) or not is_inside_tree():
		return
	_busy = false
	if not bool(res.get("ok", false)):
		if not quiet:
			_say(refusal_text(res))
		return
	take(res.get("data", {}) if res.get("data", {}) is Dictionary else {})


func take(data: Dictionary) -> void:
	"""An answer from any party route: remember it, tell Party, draw it."""
	answer = data
	Party.apply(data.get("party") if data.get("party") is Dictionary else null)
	render()


func act(path: String, body: Dictionary, done_line: String = "") -> bool:
	"""Post one action; every route answers with the party, drawn at once."""
	var res: Dictionary = await send.call(path, body)
	if not is_instance_valid(self) or not is_inside_tree():
		return false
	if not bool(res.get("ok", false)):
		_say(refusal_text(res))
		return false
	var data: Dictionary = res.get("data", {}) if res.get("data", {}) is Dictionary else {}
	if data.has("party"):
		take(data)
	else:
		await load_party(true)
	_say(done_line, true)
	return true


func _fetch(path: String) -> Dictionary:
	return await Api.get_json(path, REQUEST_TIMEOUT)


func _send(path: String, body: Dictionary) -> Dictionary:
	return await Api.post(path, body, REQUEST_TIMEOUT)


static func refusal_text(res: Dictionary) -> String:
	var status: int = int(res.get("status", 0))
	var message: String = str(res.get("error", ""))
	if status == 0:
		return message if message != "" else "No connection to the server."
	if status == 404 and message == "":
		# A game newer than its server: parties are a server change too.
		return "This server does not have parties yet."
	return message if message != "" else "Could not reach the party (HTTP %d)." % status


func _say(line: String, good: bool = false) -> void:
	if notice_label == null:
		return
	notice_label.text = line
	notice_label.visible = line != ""
	notice_label.add_theme_color_override("font_color", GOOD_COLOUR if good else Color(0.95, 0.55, 0.45))


# =============================================================================
# WHAT IT SHOWS
# =============================================================================

func party() -> Dictionary:
	return answer.get("party") if answer.get("party") is Dictionary else {}


func render() -> void:
	var p: Dictionary = party()
	var members: Array = p.get("members", []) if p.get("members", []) is Array else []
	var capacity: int = int(answer.get("capacity", p.get("capacity", 4)))
	var leading: bool = str(p.get("leader", "")) == Api.username
	if summary_label != null:
		if p.is_empty():
			summary_label.text = "You are in no party. Invite somebody to start one - up to %d of you." % capacity
		else:
			summary_label.text = "%d of %d - led by %s" % [members.size(), capacity, str(p.get("leader", ""))]
	if list != null:
		for child in list.get_children():
			list.remove_child(child)
			child.queue_free()
		for member in members:
			if member is Dictionary:
				list.add_child(member_row(member, leading))
	_render_invites()
	if invite_row != null:
		invite_row.visible = p.is_empty() or (leading and members.size() < capacity)
	if leave_button != null:
		leave_button.visible = not p.is_empty()


func member_row(member: Dictionary, leading: bool) -> Control:
	"""One member: their name (a star for the leader), what they are playing,
	where, their health - and, for the leader, Lead and Remove."""
	var who: String = str(member.get("username", ""))
	var row := VBoxContainer.new()
	row.name = "member_%s" % who
	row.add_theme_constant_override("separation", 2)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	row.add_child(top)
	var name_label := Label.new()
	name_label.name = "name"
	name_label.text = who
	name_label.add_theme_color_override("font_color", NAME_COLOUR if who == Api.username else Party.COLOUR)
	name_label.add_theme_font_size_override("font_size", 15)
	top.add_child(name_label)
	if bool(member.get("leader", false)):
		var lead_label := Label.new()
		lead_label.name = "leader"
		lead_label.text = "LEADER"
		lead_label.add_theme_color_override("font_color", LEADER_COLOUR)
		lead_label.add_theme_font_size_override("font_size", 11)
		top.add_child(lead_label)
	var detail := Label.new()
	detail.name = "detail"
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.text = detail_text(member)
	var online: bool = bool(member.get("online", false)) or who == Api.username
	detail.add_theme_color_override("font_color", DETAIL_COLOUR if online else AWAY_COLOUR)
	detail.add_theme_font_size_override("font_size", 13)
	detail.clip_text = true
	top.add_child(detail)
	if leading and who != Api.username:
		top.add_child(_small_button("Lead", "Hand the party to %s" % who,
			func() -> void: act("/api/party/lead", {"username": who}, "%s leads the party now." % who)))
		top.add_child(_small_button("Remove", "Take %s out of the party" % who,
			func() -> void: act("/api/party/kick", {"username": who}, "%s is out of the party." % who)))
	var bar := HealthStrip.new()
	bar.name = "health"
	bar.share = health_share(member)
	row.add_child(bar)
	return row


func _small_button(words: String, hint: String, then: Callable) -> Button:
	var button := Button.new()
	button.text = words
	button.tooltip_text = hint
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(64, 24)
	button.add_theme_font_size_override("font_size", 12)
	button.pressed.connect(then)
	return button


static func detail_text(member: Dictionary) -> String:
	"""'Lv 12 Warrior - Field', or '- away' for somebody not on."""
	var cls: String = str(member.get("class_id", ""))
	var level: int = int(member.get("level", 0))
	var bits: Array[String] = []
	if level > 0 and cls != "":
		bits.append("Lv %d %s" % [level, cls.capitalize()])
	var area: String = str(member.get("area", ""))
	var online: bool = bool(member.get("online", false)) or str(member.get("username", "")) == Api.username
	if not online:
		bits.append("away")
	elif area != "":
		bits.append(AreaRegistry.display_name(area))
	return " - ".join(bits)


func health_share(member: Dictionary) -> float:
	"""How full their health is, 0 to 1 - live where this game can see them."""
	var who: String = str(member.get("username", ""))
	if who == Api.username:
		var me: Node = get_tree().get_first_node_in_group(&"player") if is_inside_tree() else null
		if me != null and "hp" in me and "max_hp" in me and int(me.get("max_hp")) > 0:
			return clampf(float(me.get("hp")) / float(me.get("max_hp")), 0.0, 1.0)
	var picture: Node = Presence.remote_named(who) if is_inside_tree() else null
	if picture != null and int(picture.get("health_percent")) >= 0:
		return float(picture.get("health_percent")) / 100.0
	var most: int = int(member.get("max_hp", 0))
	return clampf(float(member.get("hp", 0)) / float(most), 0.0, 1.0) if most > 0 else 0.0


func _render_invites() -> void:
	if invites_box == null:
		return
	for child in invites_box.get_children():
		invites_box.remove_child(child)
		child.queue_free()
	var waiting: Array = answer.get("invites", []) if answer.get("invites", []) is Array else []
	for one in waiting:
		if not (one is Dictionary):
			continue
		var from: String = str(one.get("from", ""))
		var row := HBoxContainer.new()
		row.name = "invite_%s" % from
		row.add_theme_constant_override("separation", 6)
		var words := Label.new()
		words.text = "%s invites you to their party" % from
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.add_theme_color_override("font_color", Party.COLOUR)
		words.add_theme_font_size_override("font_size", 13)
		row.add_child(words)
		row.add_child(_small_button("Join", "Join %s's party" % from,
			func() -> void: act("/api/party/respond", {"from": from, "accept": true}, "You are in %s's party." % from)))
		row.add_child(_small_button("No", "Turn it down",
			func() -> void: act("/api/party/respond", {"from": from, "accept": false})))
		invites_box.add_child(row)
	invites_box.visible = invites_box.get_child_count() > 0


# =============================================================================
# ASKING AND LEAVING
# =============================================================================

func _on_invite_pressed() -> void:
	if invite_name == null:
		return
	var who: String = invite_name.text.strip_edges()
	if who == "":
		_say("Type a name to invite.")
		return
	if await act("/api/party/invite", {"username": who},
			"Asked %s - the invitation waits two minutes." % who):
		invite_name.text = ""


func invite_player(who: String) -> void:
	"""Asked from elsewhere - a right-click in the players list: the window
	opens and the invitation goes from it, so its answer is seen."""
	if not visible:
		await open()
	if invite_name != null:
		invite_name.text = who
	_on_invite_pressed()


func _on_leave_pressed() -> void:
	await act("/api/party/leave", {}, "You left the party.")


# =============================================================================
# A MEMBER'S HEALTH
# =============================================================================

class HealthStrip extends Control:
	"""A member's health: a thin bar across the row, green to red as it falls."""
	var share: float = 1.0

	func _init() -> void:
		custom_minimum_size = Vector2(0, 5)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.07, 0.09, 0.9))
		var colour: Color = Color(0.35, 0.85, 0.35) if share > 0.5 \
			else (Color(0.95, 0.8, 0.25) if share > 0.25 else Color(0.9, 0.25, 0.2))
		var filled: float = roundf(size.x * clampf(share, 0.0, 1.0))
		if filled > 0.0:
			draw_rect(Rect2(Vector2.ZERO, Vector2(filled, size.y)), colour)
