# staffpanel.gd — kick, ban, unban, promote and demote from the HUD.
# attached to res://scene/ui/staff/staffpanel.tscn, opened by the Staff button
# that characterhud.gd shows to mods, devs and the owner.
#
# =============================================================================
# THE SERVER DECIDES; THIS PANEL ONLY DECLINES TO OFFER
# =============================================================================
# Every action here is an endpoint that already existed - /api/staff/kick, ban,
# unban and PUT /api/staff/role - each behind require_role("mod") and
# can_act_on(). Before this panel the only way to reach them was the owner's
# backquote console: type a name blind, read the answer in Godot's Output.
#
# So nothing in this file is a permission. actions_for() hides buttons the
# server would refuse, which is a courtesy to whoever is using it, and the
# server still refuses them if a patched client shows them anyway.
#
# THE RULES IT MIRRORS, all from app.py:
#   can_act_on       you may act only on someone STRICTLY below you, so a mod
#                    cannot touch a mod and nobody touches the owner.
#   MAX_MOD_BAN_DAYS a mod may ban for up to 30 days, never permanently.
#   set_account_role you cannot grant a rank at or above your own, so a dev
#                    makes mods and only the owner makes devs. "owner" is
#                    never granted - it comes from ELUSION_OWNER.
#
# =============================================================================
# EVERYTHING ASKS TWICE
# =============================================================================
# The first press arms a button and relabels it "Confirm ...?", the second
# within ARM_SECONDS does it. Same pattern as ownerpanel.gd, for the same
# reason: a ban is one mis-click from the row above. Selecting a different
# account disarms, so a button armed for one person can never fire at another.
extends Control


signal closed


# =============================================================================
# CONSTANTS
# =============================================================================

# Lowest to highest. The same order as ROLES in app.py; an unknown rank reads
# as the lowest, as role_for() does, so a newer server naming a rank this build
# has never heard of is never taken for more than a player.
const RANKS: PackedStringArray = ["player", "mod", "dev", "owner"]

# Ban lengths offered as buttons. Days, because that is what the endpoint
# takes. All within MAX_MOD_BAN_DAYS, so a mod gets every one of them and only
# "Permanent" depends on rank.
const BAN_PRESETS: Array[int] = [1, 7, 30]

const ARM_SECONDS := 4.0
const ARMED_PROMPT := "Press again within %d seconds to confirm." % int(ARM_SECONDS)

# The list re-reads while open, so "online" stays true to the minute. The
# server's window is 45 seconds; ten here keeps the dots current without
# making the panel the busiest thing talking to the server.
const AUTO_REFRESH_SECONDS := 10.0

const COLOUR_ONLINE := Color(0.55, 0.9, 0.5)
const COLOUR_OFFLINE := Color(0.62, 0.6, 0.56)
const COLOUR_BANNED := Color(1.0, 0.45, 0.4)
const COLOUR_OK := Color(0.72, 0.9, 0.6)
const COLOUR_PROBLEM := Color(1.0, 0.65, 0.25)


# =============================================================================
# NODE REFERENCES
# =============================================================================

@onready var close_button:    Button        = %staffclosebutton
@onready var you_label:       Label         = %staffyoulabel
@onready var search_input:    LineEdit      = %staffsearch
@onready var online_only:     CheckBox      = %staffonlineonly
@onready var account_list:    VBoxContainer = %staffaccountlist
@onready var empty_label:     Label         = %staffemptylabel
@onready var count_label:     Label         = %staffcountlabel
@onready var pick_hint:       Label         = %staffpickhint
@onready var detail_box:      Control       = %staffdetail
@onready var name_label:      Label         = %staffnamelabel
@onready var presence_label:  Label         = %staffpresencelabel
@onready var rank_label:      Label         = %staffranklabel
@onready var ban_label:       Label         = %staffbanlabel
@onready var reach_label:     Label         = %staffreachlabel
@onready var reason_input:    LineEdit      = %staffreason
@onready var kick_button:     Button        = %staffkickbutton
@onready var ban_row:         HBoxContainer = %staffbanrow
@onready var permanent_button: Button       = %staffpermanentbutton
@onready var unban_button:    Button        = %staffunbanbutton
@onready var rank_row:        HBoxContainer = %staffrankrow
@onready var promote_button:  Button        = %staffpromotebutton
@onready var demote_button:   Button        = %staffdemotebutton
@onready var notice_label:    Label         = %staffnotice
@onready var refresh_button:  Button        = %staffrefreshbutton


# =============================================================================
# STATE
# =============================================================================

var _accounts: Array = []          # as the server sent them, sorted
var _server_now: int = 0           # the server's clock at the last read
var _selected: String = ""         # a username, so a refresh keeps the choice
var _loading: bool = false
var _acting: bool = false
var _seconds_until_refresh: float = AUTO_REFRESH_SECONDS

# ARMED-THEN-CONFIRMED. The action carries everything needed to perform it, so
# the second press does exactly what the first press described.
var _armed: Dictionary = {}        # {"key", "button", "label", "until"}
var _preset_buttons: Array[Button] = []


# =============================================================================
# THE RULES, AS PURE FUNCTIONS (the test suite calls these directly)
# =============================================================================

static func rank_index(rank: String) -> int:
	var at: int = RANKS.find(rank)
	return at if at >= 0 else 0


static func actions_for(viewer_rank: String, entry: Dictionary) -> Dictionary:
	# What to OFFER for one account. The server's `actionable` and this
	# client's own reading must BOTH agree before anything is offered: the
	# first is the authority, and the second stops a panel that has not
	# caught up with a demotion from showing buttons its user just lost.
	var mine: int = rank_index(viewer_rank)
	var theirs: int = rank_index(str(entry.get("role", "player")))
	var reach: bool = bool(entry.get("actionable", false)) and mine > theirs
	var senior: bool = mine >= rank_index("dev")

	# Promote one step, but never to your own rank or beyond, and never to
	# owner. A dev promoting a mod would be making a dev: refused by the
	# server, so not offered here.
	var promote_to: String = ""
	var demote_to: String = ""
	if reach and senior:
		var up: int = theirs + 1
		if up < mine and up <= rank_index("dev"):
			promote_to = RANKS[up]
		if theirs > 0:
			demote_to = RANKS[theirs - 1]

	return {
		"kick": reach,
		"ban": reach,
		"ban_permanent": reach and senior,
		"unban": reach and bool(entry.get("banned", false)),
		"promote_to": promote_to,
		"demote_to": demote_to,
	}


static func sort_accounts(accounts: Array) -> Array:
	# Online first - they are who a kick is for - then by name, ignoring case.
	var out: Array = accounts.duplicate()
	out.sort_custom(func(a, b):
		var a_on: bool = bool(a.get("online", false))
		var b_on: bool = bool(b.get("online", false))
		if a_on != b_on:
			return a_on
		return str(a.get("username", "")).naturalnocasecmp_to(str(b.get("username", ""))) < 0)
	return out


static func filter_accounts(accounts: Array, text: String, only_online: bool) -> Array:
	var needle: String = text.strip_edges().to_lower()
	var out: Array = []
	for entry in accounts:
		if only_online and not bool(entry.get("online", false)):
			continue
		if needle != "" and str(entry.get("username", "")).to_lower().find(needle) < 0:
			continue
		out.append(entry)
	return out


static func describe_presence(entry: Dictionary, server_now: int) -> String:
	if bool(entry.get("online", false)):
		return "Online now"
	var seen: int = int(entry.get("last_seen_at", 0))
	if seen <= 0 or server_now <= 0:
		return "Offline"
	var ago: int = maxi(0, server_now - seen)
	if ago < 3600:
		return "Last seen %d min ago" % maxi(1, int(ago / 60.0))
	if ago < 86400:
		return "Last seen %d h ago" % int(ago / 3600.0)
	return "Last seen %d days ago" % int(ago / 86400.0)


static func describe_ban(ban: Variant) -> String:
	if not (ban is Dictionary):
		return "Not banned"
	var until: String = "permanently"
	if not bool(ban.get("permanent", false)):
		# Local time, to the minute - see describe_login_refusal() in
		# loginmenu.gd for why not the raw UTC string.
		var local: int = int(ban.get("expires_at", 0)) \
			+ int(Time.get_time_zone_from_system().get("bias", 0)) * 60
		until = "until " + Time.get_datetime_string_from_unix_time(local, true).substr(0, 16)
	var line: String = "Banned %s by %s" % [until, str(ban.get("banned_by", "?"))]
	var reason: String = str(ban.get("reason", ""))
	if reason != "":
		line += "\n\"%s\"" % reason
	return line


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	visible = false
	close_button.pressed.connect(close_panel)
	refresh_button.pressed.connect(_on_refresh_pressed)
	search_input.text_changed.connect(func(_t): _render_list())
	online_only.toggled.connect(func(_on): _render_list())

	kick_button.pressed.connect(_on_action_pressed.bind(kick_button, "kick", 0))
	permanent_button.pressed.connect(_on_action_pressed.bind(permanent_button, "ban", -1))
	unban_button.pressed.connect(_on_action_pressed.bind(unban_button, "unban", 0))
	promote_button.pressed.connect(_on_action_pressed.bind(promote_button, "promote", 0))
	demote_button.pressed.connect(_on_action_pressed.bind(demote_button, "demote", 0))

	# The day buttons are made here from BAN_PRESETS, ahead of Permanent, so
	# the lengths live in one list rather than in a scene and a script.
	for days in BAN_PRESETS:
		var button := Button.new()
		button.text = "%d day%s" % [days, "" if days == 1 else "s"]
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_action_pressed.bind(button, "ban", days))
		ban_row.add_child(button)
		ban_row.move_child(button, ban_row.get_child_count() - 2)
		_preset_buttons.append(button)

	_show_detail(null)


func _process(delta: float) -> void:
	if not visible:
		return
	if not _armed.is_empty() and Time.get_ticks_msec() / 1000.0 > float(_armed["until"]):
		_disarm()
	_seconds_until_refresh -= delta
	if _seconds_until_refresh <= 0.0:
		_seconds_until_refresh = AUTO_REFRESH_SECONDS
		_load()


# =============================================================================
# OPEN / CLOSE
# =============================================================================

func open_panel() -> void:
	visible = true
	you_label.text = "You: %s" % my_rank()
	_seconds_until_refresh = AUTO_REFRESH_SECONDS
	await _load()


func close_panel() -> void:
	_disarm()
	visible = false
	# Focus goes with it. A reason box left focused behind a closed panel
	# would go on eating keystrokes nobody can see.
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused != null and is_ancestor_of(focused):
		focused.release_focus()
	closed.emit()


func toggle_panel() -> void:
	if visible:
		close_panel()
	else:
		await open_panel()


static func my_rank() -> String:
	return "owner" if Api.is_owner else Api.role


# =============================================================================
# LOADING
# =============================================================================

func _on_refresh_pressed() -> void:
	_seconds_until_refresh = AUTO_REFRESH_SECONDS
	await _load()


func _load() -> void:
	if _loading:
		return
	_loading = true
	refresh_button.disabled = true
	var res: Dictionary = await Api.get_json("/api/staff/users")
	_loading = false
	# PAST AN AWAIT: the panel can be closed, or the whole HUD freed by a
	# scene change, while the server was answering.
	if not is_instance_valid(self) or not is_inside_tree():
		return
	refresh_button.disabled = false

	if not res.get("ok", false):
		if int(res.get("status", 0)) == 404:
			# require_role answers a non-staff caller with 404. Reaching here
			# means this account was demoted while the panel was open.
			_accounts = []
			_render_list()
			_say("The server no longer lists you as staff.", false)
		else:
			_say(str(res.get("error", "Could not load accounts.")), false)
		return

	var data: Variant = res.get("data", {})
	if not (data is Dictionary):
		_say("Unexpected answer from the server.", false)
		return
	_server_now = int(data.get("now", 0))
	var accounts: Array = []
	for entry in data.get("accounts", []):
		if entry is Dictionary:
			accounts.append(entry)
	_accounts = sort_accounts(accounts)
	you_label.text = "You: %s" % my_rank()
	_render_list()


# =============================================================================
# THE LIST
# =============================================================================

func _render_list() -> void:
	for child in account_list.get_children():
		child.queue_free()

	var shown: Array = filter_accounts(_accounts, search_input.text, online_only.button_pressed)
	var online_count: int = 0
	for entry in _accounts:
		if bool(entry.get("online", false)):
			online_count += 1

	empty_label.visible = shown.is_empty()
	empty_label.text = "No accounts match." if not _accounts.is_empty() else "No accounts loaded."
	count_label.text = "%d accounts · %d online" % [_accounts.size(), online_count]

	for entry in shown:
		account_list.add_child(_make_row(entry))

	# The selection survives a refresh by NAME. If that account has dropped out
	# of the filtered view, the detail stays on it anyway - filtering the list
	# should not quietly change who the buttons are aimed at.
	_show_detail(_entry_named(_selected))


func _make_row(entry: Dictionary) -> Button:
	var name_text: String = str(entry.get("username", "?"))
	var tags: PackedStringArray = []
	var rank: String = str(entry.get("role", "player"))
	if rank != "player":
		tags.append(rank)
	if bool(entry.get("banned", false)):
		tags.append("banned")
	if name_text == Api.username:
		tags.append("you")

	var row := Button.new()
	row.focus_mode = Control.FOCUS_NONE
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.toggle_mode = true
	row.button_pressed = name_text == _selected
	row.text = "%s %s%s" % [
		"●" if bool(entry.get("online", false)) else "○",
		name_text,
		("   " + ", ".join(tags)) if not tags.is_empty() else "",
	]
	var colour: Color = COLOUR_OFFLINE
	if bool(entry.get("banned", false)):
		colour = COLOUR_BANNED
	elif bool(entry.get("online", false)):
		colour = COLOUR_ONLINE
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		row.add_theme_color_override(state, colour)
	# The name rides on the row itself rather than being read back out of its
	# label, which carries a dot and tags around it.
	row.set_meta("username", name_text)
	row.pressed.connect(_on_row_pressed.bind(name_text))
	return row


func _on_row_pressed(username: String) -> void:
	if username != _selected:
		_disarm()
		reason_input.text = ""
	_selected = username
	for child in account_list.get_children():
		if child is Button:
			child.set_pressed_no_signal(str(child.get_meta("username", "")) == username)
	_show_detail(_entry_named(username))


func _entry_named(username: String) -> Dictionary:
	if username == "":
		return {}
	for entry in _accounts:
		if str(entry.get("username", "")) == username:
			return entry
	return {}


# =============================================================================
# THE DETAIL
# =============================================================================

func _show_detail(entry: Variant) -> void:
	if not (entry is Dictionary) or entry.is_empty():
		detail_box.visible = false
		pick_hint.visible = true
		return
	detail_box.visible = true
	pick_hint.visible = false

	var can: Dictionary = actions_for(my_rank(), entry)
	name_label.text = str(entry.get("username", "?"))
	presence_label.text = describe_presence(entry, _server_now)
	presence_label.add_theme_color_override("font_color",
		COLOUR_ONLINE if bool(entry.get("online", false)) else COLOUR_OFFLINE)
	rank_label.text = "Rank: %s" % str(entry.get("role", "player"))
	ban_label.text = describe_ban(entry.get("ban"))
	ban_label.add_theme_color_override("font_color",
		COLOUR_BANNED if bool(entry.get("banned", false)) else COLOUR_OFFLINE)

	var reach: bool = bool(can["kick"])
	reach_label.visible = not reach
	if name_label.text == Api.username:
		reach_label.text = "This is you."
	else:
		reach_label.text = "Your rank does not reach this account."

	reason_input.editable = reach
	kick_button.disabled = not can["kick"]
	for button in _preset_buttons:
		button.disabled = not can["ban"]
	permanent_button.disabled = not can["ban_permanent"]
	unban_button.disabled = not can["unban"]

	# The rank row exists only for devs and the owner - the rank changes the
	# user asked for were theirs, and a mod could never make one anyway.
	rank_row.visible = rank_index(my_rank()) >= rank_index("dev")
	promote_button.visible = can["promote_to"] != ""
	demote_button.visible = can["demote_to"] != ""
	if can["promote_to"] != "":
		promote_button.text = "Promote to %s" % can["promote_to"]
	if can["demote_to"] != "":
		demote_button.text = "Demote to %s" % can["demote_to"]

	# Re-applying the labels above would wipe an armed "Confirm ...?" - put it
	# back, so a refresh landing between the two presses does not disarm it
	# silently while the timer says otherwise.
	if not _armed.is_empty() and is_instance_valid(_armed["button"]):
		(_armed["button"] as Button).text = _confirm_text(str(_armed["key"]))


# =============================================================================
# ACTIONS
# =============================================================================

func _on_action_pressed(button: Button, action: String, days: int) -> void:
	var entry: Dictionary = _entry_named(_selected)
	if entry.is_empty() or _acting:
		return

	var key: String = "%s:%d:%s" % [action, days, _selected]

	if action == "ban" and reason_input.text.strip_edges() == "":
		# Asked for BEFORE arming. The server requires one, and a confirm
		# that then fails on a missing reason is two clicks for an error.
		_say("Type a reason first - every ban needs one.", false)
		reason_input.grab_focus()
		return

	# FIRST PRESS ARMS.
	if _armed.get("key", "") != key:
		_disarm()
		_armed = {
			"key": key,
			"button": button,
			"label": button.text,
			"until": Time.get_ticks_msec() / 1000.0 + ARM_SECONDS,
		}
		button.text = _confirm_text(key)
		_say(ARMED_PROMPT, true)
		return

	# SECOND PRESS DOES IT.
	_disarm()
	await _perform(action, days, entry)


func _confirm_text(key: String) -> String:
	var parts: PackedStringArray = key.split(":")
	var action: String = parts[0]
	var days: int = int(parts[1])
	match action:
		"kick":
			return "Confirm kick?"
		"ban":
			return "Confirm permanent?" if days < 0 else "Confirm %dd?" % days
		"unban":
			return "Confirm unban?"
		"promote", "demote":
			return "Confirm?"
	return "Confirm?"


func _disarm() -> void:
	if _armed.is_empty():
		return
	var button: Variant = _armed.get("button")
	if is_instance_valid(button):
		(button as Button).text = str(_armed["label"])
	_armed = {}
	# The prompt goes with the arm. Left up, it tells whoever looks next to
	# press something that is no longer armed.
	if notice_label.text == ARMED_PROMPT:
		_say("", true)


func _perform(action: String, days: int, entry: Dictionary) -> void:
	var username: String = str(entry.get("username", ""))
	var reason: String = reason_input.text.strip_edges()
	var can: Dictionary = actions_for(my_rank(), entry)

	var res: Dictionary
	_acting = true
	match action:
		"kick":
			var body: Dictionary = {"username": username}
			if reason != "":
				body["reason"] = reason
			res = await Api.post("/api/staff/kick", body)
		"ban":
			# NO `days` MEANS PERMANENT, which is how the endpoint reads it.
			var body: Dictionary = {"username": username, "reason": reason}
			if days > 0:
				body["days"] = days
			res = await Api.post("/api/staff/ban", body)
		"unban":
			res = await Api.post("/api/staff/unban", {"username": username})
		"promote", "demote":
			var to: String = str(can["promote_to" if action == "promote" else "demote_to"])
			res = await Api.put("/api/staff/role", {"username": username, "role": to})
	_acting = false

	if not is_instance_valid(self) or not is_inside_tree():
		return

	if not res.get("ok", false):
		var status: int = int(res.get("status", 0))
		if status == 404:
			# The same answer for "no such account" and "out of your reach",
			# on purpose - see _moderation_target() in app.py.
			_say("Refused: %s is out of your reach (or gone)." % username, false)
		else:
			_say("Refused: %s" % str(res.get("error", "unknown error")), false)
		await _load()
		return

	var data: Variant = res.get("data", {})
	match action:
		"kick":
			var ended: int = int(data.get("sessions_ended", 0)) if data is Dictionary else 0
			if ended == 0:
				_say("%s had no live session - nothing to end." % username, true)
			else:
				_say("Kicked %s - they are back at the login screen within 15 seconds." % username, true)
		"ban":
			_say("Banned %s %s." % [username, "permanently" if days < 0 else "for %d day%s" % [days, "" if days == 1 else "s"]], true)
		"unban":
			_say("Unbanned %s. They can log in again." % username, true)
		"promote", "demote":
			_say("%s is now %s." % [username, str(data.get("role", "?")) if data is Dictionary else "?"], true)

	reason_input.text = ""
	await _load()


func _say(line: String, good: bool) -> void:
	notice_label.text = line
	notice_label.add_theme_color_override("font_color", COLOUR_OK if good else COLOUR_PROBLEM)
