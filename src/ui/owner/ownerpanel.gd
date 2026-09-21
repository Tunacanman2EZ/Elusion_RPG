# ownerpanel.gd — owner-only debug tool for viewing another player's save
# data without disturbing the owner's own active session.
#
# Toggled with the backquote key in characterhud.gd and gated on Api.is_owner.
# Anyone who is not the owner gets no response at all, not even a hint the
# panel exists.
#
# THE OWNER SPECIFICALLY, not "staff". A mod or a dev is a rank the owner hands
# out and can take back; the owner is named in the server's environment
# (ELUSION_OWNER) and is the one account that cannot be granted or revoked.
# Reading other people's saves belongs to the narrowest of the four.
#
# v1 deliberately keeps this simple: results print to the Output console
# rather than a dedicated display widget, matching this project's existing
# debug-key workflow (print-based diagnostics) rather than building a new
# visual result panel before knowing what owner tooling actually gets used.
#
# IT NOW READS THE SERVER. GET /api/staff/user/<name> exists, so this panel no
# longer says "not built" - it shows rank, ban state, characters, the login
# summary, grouped kill reports and the staff history. The console is still
# where it lands; drawing it into the panel needs scene work.
#
# SCENE SETUP (can't be done from chat — do this in the editor):
# - a Control (or PanelContainer) root with this script attached
# - a child LineEdit, marked unique name "usernameinput"
# - a child Button, marked unique name "viewbutton"
extends Control


# =============================================================================
# NODE REFERENCES
# =============================================================================

@onready var username_input: LineEdit = %usernameinput
@onready var view_button: Button = %viewbutton

# THE SANCTION BUTTONS ARE OPTIONAL, and every one of them is null-guarded.
#
# This script is committed from outside the editor and the scene is not, so a
# hard @onready on a node that does not exist yet would make the whole panel
# fail to load - taking the working view button with it. Absent buttons simply
# do nothing, which means the scene can gain them one at a time.
#
# SCENE SETUP (editor work, same as the input and view button above):
#   a Button with unique name "kickbutton"      - sign out everywhere
#   a Button with unique name "banbutton"       - ban, using the days field
#   a Button with unique name "unbanbutton"     - lift a ban
#   a LineEdit with unique name "daysinput"     - blank or 0 means permanent
#   a LineEdit with unique name "reasoninput"   - required by the server for a ban
@onready var kick_button: Button = get_node_or_null("%kickbutton")
@onready var ban_button: Button = get_node_or_null("%banbutton")
@onready var unban_button: Button = get_node_or_null("%unbanbutton")
@onready var days_input: LineEdit = get_node_or_null("%daysinput")
@onready var reason_input: LineEdit = get_node_or_null("%reasoninput")

# ARMED-THEN-CONFIRMED, because a ban is one click from a typo.
#
# A ConfirmationDialog is the obvious answer and it is scene work this script
# cannot do. This needs no new nodes: the first press arms the button and
# renames it, the second within ARM_SECONDS performs it, and anything else -
# a different button, the timer running out, a new lookup - disarms it.
#
# The window is short on purpose. A button that stays armed is a button that
# gets pressed later by somebody who has forgotten what it was armed for.
const ARM_SECONDS := 4.0

var _armed_action: String = ""
var _armed_label: String = ""
var _armed_until: float = 0.0


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	visible = false
	if view_button != null and not view_button.pressed.is_connected(_on_view_pressed):
		view_button.pressed.connect(_on_view_pressed)

	# bind(), so one handler serves all three and the action name travels with
	# the press rather than being inferred from which button is disabled.
	for pair in [[kick_button, "kick"], [ban_button, "ban"], [unban_button, "unban"]]:
		var button: Button = pair[0]
		if button != null and not button.pressed.is_connected(_on_sanction_pressed):
			button.pressed.connect(_on_sanction_pressed.bind(String(pair[1])))


func _process(_delta: float) -> void:
	# Disarm on a timer rather than on the next click. A button left reading
	# "Confirm ban?" is a trap for whoever looks at this panel next.
	if _armed_action != "" and Time.get_ticks_msec() / 1000.0 > _armed_until:
		_disarm()


# =============================================================================
# VIEW ACTION
# =============================================================================

func _on_view_pressed() -> void:
	# Api.is_owner only hides the button. The server is the gate, and it has to
	# be, because this client is the thing an attacker controls.
	#
	# NOTE ON RANK: the endpoint itself is require_role("mod"), because a mod
	# about to ban someone needs to be able to look first - and it gates IP
	# addresses behind can_act_on() so that is safe. This panel stays owner-only
	# because that is what it was built as; widening it is a product decision,
	# not a missing capability.
	if not Api.is_owner:
		return

	if username_input == null:
		return
	var username: String = username_input.text.strip_edges()
	if username == "":
		return

	# One request at a time. Without this, an impatient double-click fires two
	# and the second answer overwrites the first in the console, which reads as
	# the panel showing the wrong account.
	if view_button != null:
		view_button.disabled = true

	var res: Dictionary = await Api.get_json("/api/staff/user/" + username.uri_encode())

	if view_button != null:
		view_button.disabled = false

	if not res.get("ok", false):
		var status: int = int(res.get("status", 0))
		if status == 0:
			_say("[OWNER] could not reach the server: %s" % str(res.get("error", "")))
		elif status == 404:
			# 404 IS TWO ANSWERS HERE, and they cannot be told apart on purpose.
			# require_role() answers "Not found" to a non-staff caller so a 403
			# does not confirm the route exists - so this is either "no such
			# account" or "you are not staff". Say both rather than guess.
			_say("[OWNER] no account called '%s' - or this account is not staff." % username)
		else:
			_say("[OWNER] server refused (%d): %s" % [status, str(res.get("error", ""))])
		return

	var data = res.get("data", {})
	if data is Dictionary:
		_print_save_summary(username, data)
	else:
		_say("[OWNER] unexpected response shape for '%s'" % username)


# =============================================================================
# SANCTIONS
# =============================================================================

func _button_for(action: String) -> Button:
	match action:
		"kick":
			return kick_button
		"ban":
			return ban_button
		"unban":
			return unban_button
	return null


func _disarm() -> void:
	var button: Button = _button_for(_armed_action)
	if button != null and _armed_label != "":
		button.text = _armed_label
	_armed_action = ""
	_armed_label = ""
	_armed_until = 0.0


func _on_sanction_pressed(action: String) -> void:
	# THE CLIENT GATE IS A COURTESY. require_role("mod") on the server is the
	# real one, and it has to be - this client is the thing an attacker
	# controls. Checking here only keeps an ordinary player from firing a
	# request that was always going to be refused.
	#
	# STAFF, NOT OWNER. Reading another player's save stayed owner-only because
	# that is what this panel was built as. Sanctions are different: a mod who
	# cannot act has no reason to have the panel at all, and the server already
	# decides who may act on whom via can_act_on().
	if Api.role != "mod" and Api.role != "dev" and not Api.is_owner:
		return

	var username: String = "" if username_input == null else username_input.text.strip_edges()
	if username == "":
		_say("[GM] type a username first.")
		return

	var button: Button = _button_for(action)

	# FIRST PRESS ARMS. See ARM_SECONDS for why this is not a dialog.
	if _armed_action != action:
		_disarm()
		_armed_action = action
		_armed_until = Time.get_ticks_msec() / 1000.0 + ARM_SECONDS
		if button != null:
			_armed_label = button.text
			button.text = "Confirm %s?" % action
		_say("[GM] %s '%s'? press again within %d seconds." % [action, username, int(ARM_SECONDS)])
		return

	_disarm()

	var body: Dictionary = {"username": username}
	var reason: String = "" if reason_input == null else reason_input.text.strip_edges()
	if reason != "":
		body["reason"] = reason

	if action == "ban":
		# BLANK OR ZERO MEANS PERMANENT, matching the endpoint. Sent as an
		# explicit `permanent` rather than by omitting days, so the intent is
		# in the request instead of being inferred from what is missing.
		var days_text: String = "" if days_input == null else days_input.text.strip_edges()
		var days: int = int(days_text) if days_text.is_valid_int() else 0
		if days > 0:
			body["days"] = days
		else:
			body["permanent"] = true

	if button != null:
		button.disabled = true
	var res: Dictionary = await Api.post("/api/staff/%s" % action, body)
	if button != null:
		button.disabled = false

	if not res.get("ok", false):
		var status: int = int(res.get("status", 0))
		if status == 0:
			_say("[GM] could not reach the server: %s" % str(res.get("error", "")))
		elif status == 404:
			# The same two answers the view button gets, and for the same
			# reason - require_role() hides itself behind "Not found", and so
			# does a target you cannot act on. Do not guess which.
			_say("[GM] no account called '%s' - or it is out of your reach." % username)
		else:
			_say("[GM] %s refused (%d): %s" % [action, status, str(res.get("error", ""))])
		return

	var data = res.get("data", {})
	if action == "kick" and data is Dictionary:
		# The count is the useful part: zero means they were already gone.
		_say("[GM] signed '%s' out of %s place(s)." % [username, str(data.get("sessions_ended", 0))])
	else:
		_say("[GM] %s ok: %s" % [action, str(data)])

	# Re-read, so the panel shows the result rather than the state before it.
	_on_view_pressed()


func _say(line: String) -> void:
	# One place that decides whether console output happens, so the debug-build
	# guard is not repeated at every call site and cannot drift between them.
	if OS.is_debug_build():
		print(line)


func _when(unix_seconds: int) -> String:
	if unix_seconds <= 0:
		return "never"
	return Time.get_datetime_string_from_unix_time(unix_seconds, true)


# =============================================================================
# DISPLAY (console-printed — see class comment on why, for now)
# =============================================================================

func _print_save_summary(username: String, data: Dictionary) -> void:
	# RENDERS THE SERVER'S SHAPE, not a save file's. The previous version read
	# `version`, `saved_at`, `account_data` and `character_slots` from
	# user://character_<name>.save - keys that stopped existing when characters
	# moved into the database. It is the endpoint's payload now, and the two are
	# kept in step by GET /api/staff/user/<name> being the only source.
	#
	# STILL PRINTED RATHER THAN DRAWN. Adding result widgets needs scene edits,
	# which is the same "for now" the class comment has carried for a while. The
	# guard lives in _say() rather than here so a Release build silently shows
	# nothing rather than half of this.
	_say("========== OWNER VIEW: %s ==========" % str(data.get("username", username)))
	_say("rank      : %s" % str(data.get("role", "?")))
	_say("created   : %s" % _when(int(data.get("created_at", 0))))
	_say("lusions   : %s" % str(data.get("lusions", 0)))

	var ban = data.get("ban")
	if ban is Dictionary:
		_say("BANNED    : %s" % str(ban))
	else:
		_say("banned    : no")

	var characters: Array = data.get("characters", [])
	_say("--- characters (%d) ---" % characters.size())
	if characters.is_empty():
		_say("  none")
	for entry in characters:
		if entry is Dictionary:
			_say("  [%s] %s the %s - level %s, in %s, saved %s" % [
				str(entry.get("slot")), str(entry.get("name")),
				str(entry.get("class_id")), str(entry.get("level")),
				str(entry.get("area")), _when(int(entry.get("updated_at", 0))),
			])

	var logins = data.get("logins", {})
	if logins is Dictionary:
		_say("--- logins ---")
		_say("  %s attempts, %s failed, from %s address(es)" % [
			str(logins.get("total", 0)), str(logins.get("failed", 0)),
			str(logins.get("addresses", 0)),
		])
		var locked: int = int(logins.get("locked_until", 0))
		if locked > Time.get_unix_time_from_system():
			_say("  LOCKED OUT until %s" % _when(locked))
		elif int(logins.get("consecutive_failures", 0)) > 0:
			_say("  %s consecutive failures right now" % str(logins.get("consecutive_failures")))

		# The count is always shown; the addresses themselves only to someone
		# who could act on this account. See the note on can_act_on() in app.py.
		if not logins.get("addresses_visible", false):
			_say("  (addresses withheld - you cannot act on this account)")
		for attempt in logins.get("recent", []):
			if attempt is Dictionary:
				_say("  %s  %s  %s %s" % [
					_when(int(attempt.get("at", 0))),
					"ok  " if attempt.get("ok", false) else "FAIL",
					str(attempt.get("reason", "")),
					str(attempt.get("ip", "")),
				])

	# WHERE THEY ARE SIGNED IN RIGHT NOW, which is the number that decides
	# between a kick and a ban - and the one this panel could not show at all
	# until the endpoint carried it. login_attempts answers "who has been
	# trying"; this answers "who is holding a key".
	#
	# No token is printed because none is sent. The server omits it rather than
	# masking it, so there is nothing here to leak.
	var sessions = data.get("sessions", {})
	if sessions is Dictionary:
		var live: int = int(sessions.get("active", 0))
		_say("--- signed in now (%d) ---" % live)
		if live == 0:
			_say("  nowhere - a kick would do nothing")
		for entry in sessions.get("list", []):
			if entry is Dictionary:
				# Days remaining rather than a date: against a fixed token ttl
				# that is also how OLD the session is, which is the reading
				# that matters. Nearly the full ttl means it just signed in.
				# WHOLE DAYS ON PURPOSE, said out loud rather than left as a
				# warning. tools/audit.py hunts undocumented int/int for a
				# reason - a discarded remainder is usually a rounding bug -
				# so where it IS intended the project annotates it with why.
				#
				# A session with 29.6 days left reads as 29, and that is the
				# honest rendering: the number is there to say "this is old"
				# or "this just signed in", and rounding 29.6 up to 30 would
				# make a day-old session look brand new.
				@warning_ignore("integer_division")
				var days_left: int = int(entry.get("expires_in", 0)) / 86400
				_say("  expires %s  (%d day(s) left)" % [
					_when(int(entry.get("expires_at", 0))),
					days_left,
				])

	# OTHER ACCOUNTS ON THE SAME ADDRESSES. Surfaced, never acted on - see
	# _linked_accounts() in app.py for why a link is reported with its strength
	# instead of as a verdict. A crowded address links strangers.
	var linked = data.get("linked_accounts", {})
	if linked is Dictionary:
		var accounts: Array = linked.get("accounts", [])
		if not linked.get("visible", false):
			_say("--- linked accounts ---")
			_say("  (withheld - you cannot act on this account)")
		elif accounts.is_empty():
			_say("--- linked accounts (0) ---")
		else:
			_say("--- linked accounts (%d%s) ---" % [
				accounts.size(), ", more exist" if linked.get("truncated", false) else "",
			])
			for entry in accounts:
				if entry is Dictionary:
					var banned = entry.get("ban")
					_say("  %-18s %-6s %s%s" % [
						str(entry.get("username")),
						str(entry.get("strength")),
						"shares %s address(es), quietest holds %s" % [
							str(entry.get("shared_addresses")),
							str(entry.get("quietest_address_accounts")),
						],
						"  [BANNED]" if banned is Dictionary else "",
					])
			_say("  'weak' means the shared address is crowded - a carrier or a")
			_say("  campus links strangers. Read it, do not act on it alone.")

	var kills: Array = data.get("kills", [])
	_say("--- kills reported (%d kinds) ---" % kills.size())
	if kills.is_empty():
		_say("  none")
	for kill in kills:
		if kill is Dictionary:
			_say("  %-18s x%-5s %s xp, last %s" % [
				str(kill.get("enemy_id")), str(kill.get("count")),
				str(kill.get("xp_total")), _when(int(kill.get("last_at", 0))),
			])

	var history: Array = data.get("staff_history", [])
	if not history.is_empty():
		_say("--- staff history ---")
		for entry in history:
			if entry is Dictionary:
				_say("  %s  %s by %s  %s" % [
					_when(int(entry.get("at", 0))), str(entry.get("action")),
					str(entry.get("by")), str(entry.get("detail", "")),
				])

	_say("=====================================")
