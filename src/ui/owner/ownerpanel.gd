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
	if not Api.is_owner:
		return

	if username_input == null:
		return
	var username: String = username_input.text.strip_edges()
	if username == "":
		return

	# NOT BUILT, AND SAYS SO RATHER THAN LYING.
	#
	# This used to call CharacterData.admin_peek_user_save(), which read
	# user://character_<name>.save through a throwaway LocalStorage. Those files
	# stopped existing when characters moved into the server's database, so the
	# read found nothing and the panel rendered "that user has no characters"
	# for every name you typed. Being told the wrong thing confidently is worse
	# than being told the feature is missing.
	#
	# It needs a GET /api/staff/user/<name> behind require_role("mod"), and
	# _print_save_summary() below is the display half waiting for it.
	push_warning("OwnerPanel: viewing another player's save needs a server endpoint (GET /api/staff/user/<name>). Not built yet.")
	if OS.is_debug_build():
		print("[OWNER] save viewing is not implemented - no server endpoint yet")


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

	print("========== OWNER VIEW: %s ==========" % username)
	print("version: %s" % str(data.get("version")))
	print("saved_at: %s" % str(data.get("saved_at")))

	var account: Dictionary = data.get("account_data", {})
	print("--- account_data ---")
	print("  lusions: %s" % str(account.get("lusions")))
	print("  bank_gold: %s" % str(account.get("bank_gold")))

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
