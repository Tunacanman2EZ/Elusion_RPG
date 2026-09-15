# adminpanel.gd — minimal admin-only debug tool for viewing another
# player's save data without disturbing the admin's own active session.
# toggled via the backquote key in characterhud.gd, gated behind Api.is_owner
# — non-admins pressing F8 get nothing, not even a hint this panel exists.
#
# v1 deliberately keeps this simple: results print to the Output console
# rather than a dedicated display widget, matching this project's existing
# debug-key workflow (print-based diagnostics) rather than building a new
# visual result panel before knowing what admin tooling actually gets used.
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
	# enforcement lives in CharacterData.admin_peek_user_save() itself
	# (fail-closed if the current session isn't actually an admin) — this
	# UI-level check is just a friendlier early exit, not the real gate.
	if not Api.is_owner:
		return

	if username_input == null:
		return
	var username: String = username_input.text.strip_edges()
	if username == "":
		return

	var data: Dictionary = CharacterData.admin_peek_user_save(username)
	if data.is_empty():
		if OS.is_debug_build():
			print("ADMIN: no save found for user '%s'" % username)
		return

	_print_save_summary(username, data)


# =============================================================================
# DISPLAY (console-printed — see class comment on why, for now)
# =============================================================================

func _print_save_summary(username: String, data: Dictionary) -> void:
	# one guard for the whole dump rather than a dozen — everything below is
	# a single block of console output and either all of it runs or none does.
	#
	# Gating loses nothing real: this panel already writes to stdout instead
	# of into its own UI, and a player running a Release build from a desktop
	# icon has no console to read it in. The actual fix is to render this into
	# the panel — the class comment's "for now" has been load-bearing for a
	# while — at which point this guard comes out along with the prints.
	if not OS.is_debug_build():
		return

	print("========== ADMIN VIEW: %s ==========" % username)
	print("version: %s" % str(data.get("version")))
	print("saved_at: %s" % str(data.get("saved_at")))

	var account: Dictionary = data.get("account_data", {})
	print("--- account_data ---")
	print("  lusions: %s" % str(account.get("lusions")))
	print("  bank_gold: %s" % str(account.get("bank_gold")))
	print("  is_admin: %s" % str(account.get("is_admin")))

	var slots: Array = data.get("character_slots", [])
	print("--- character_slots ---")
	for i in range(slots.size()):
		var slot = slots[i]
		if slot == null:
			print("  [%d] empty" % i)
			continue
		print("  [%d] %s — level %s, hp %s/%s, gold %s" % [
			i, str(slot.get("character")), str(slot.get("level")),
			str(slot.get("hp")), str(slot.get("max_hp")), str(slot.get("gold"))
		])
	print("=====================================")
