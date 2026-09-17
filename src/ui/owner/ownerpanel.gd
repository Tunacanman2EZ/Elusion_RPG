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


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	visible = false
	if view_button != null and not view_button.pressed.is_connected(_on_view_pressed):
		view_button.pressed.connect(_on_view_pressed)


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
