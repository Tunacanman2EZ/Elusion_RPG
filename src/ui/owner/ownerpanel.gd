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

# RANK AND THE SERVER SWITCH, optional and null-guarded for the same reason as
# the sanction buttons above: this script is committed from outside the editor
# and the scene is not, so a hard @onready on a node that does not exist yet
# would take the whole panel down with it.
#
# SCENE SETUP (editor work):
#   an OptionButton, unique name "roleoption"     - filled in code, see RANKS
#   a Button   with unique name "rolebutton"       - apply that rank
#   a LineEdit with unique name "maintenancemessageinput" - what players are told
#   a Button   with unique name "maintenancebutton"       - close / reopen
#   a Label    with unique name "maintenancestatus"       - the switch as it is
@onready var role_option: OptionButton = get_node_or_null("%roleoption")
@onready var role_button: Button = get_node_or_null("%rolebutton")
@onready var maintenance_message_input: LineEdit = get_node_or_null("%maintenancemessageinput")
@onready var maintenance_button: Button = get_node_or_null("%maintenancebutton")
@onready var maintenance_status: Label = get_node_or_null("%maintenancestatus")

# THE TESTING ROW. get_node_or_null like everything below it, so a build whose
# scene predates these controls opens the panel instead of failing on _ready.
@onready var gold_input: LineEdit = get_node_or_null("%goldinput")
@onready var gold_button: Button = get_node_or_null("%goldbutton")
@onready var gold_bank_button: Button = get_node_or_null("%goldbankbutton")
@onready var item_input: LineEdit = get_node_or_null("%iteminput")
@onready var item_count_input: LineEdit = get_node_or_null("%itemcountinput")
@onready var item_button: Button = get_node_or_null("%itembutton")
@onready var testing_status: Label = get_node_or_null("%testingstatus")

# What the switch looked like the last time we asked. The button has to know
# whether pressing it closes or reopens, and asking the server at press time
# would make the FIRST press a question and the second one the action.
var _server_closed: bool = false

# The server button's two faces, built once from whatever the scene handed it,
# so the SHAPE (corners, padding) stays in the .tscn and only the colours move.
# Closing signs everyone out and reads red; reopening only lets people back in
# and reads green. A toggle that looks identical in both directions is how the
# wrong one gets pressed.
var _style_close: StyleBoxFlat = null
var _style_close_hover: StyleBoxFlat = null
var _style_reopen: StyleBoxFlat = null
var _style_reopen_hover: StyleBoxFlat = null

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

# THE RANK LADDER, mirroring ROLES in app.py. Order is the comparison: index 0
# is the lowest. Kept as a list rather than free text because a typed rank is a
# rank that can be typo'd - "moderator" is not a rank, and the only way the
# panel could tell you so was to send it and let the server refuse.
#
# 'owner' is in the list to be COMPARED AGAINST, never to be granted. The
# server's users.role has a CHECK that refuses it outright; it comes from
# ELUSION_OWNER in the environment, which is what makes it the one rank no
# request can hand out.
const RANKS := ["player", "mod", "dev", "owner"]

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

	if role_button != null and not role_button.pressed.is_connected(_on_role_pressed):
		role_button.pressed.connect(_on_role_pressed)

	if maintenance_button != null:
		if not maintenance_button.pressed.is_connected(_on_maintenance_pressed):
			maintenance_button.pressed.connect(_on_maintenance_pressed.bind("maintenance"))

	if gold_button != null and not gold_button.pressed.is_connected(_on_gold_pressed):
		gold_button.pressed.connect(_on_gold_pressed.bind(false))
	if gold_bank_button != null \
			and not gold_bank_button.pressed.is_connected(_on_gold_pressed):
		gold_bank_button.pressed.connect(_on_gold_pressed.bind(true))
	if gold_input != null:
		gold_input.text_submitted.connect(func(_t): _on_gold_pressed(false))
	if item_button != null and not item_button.pressed.is_connected(_on_item_pressed):
		item_button.pressed.connect(_on_item_pressed)
	if item_input != null:
		item_input.text_submitted.connect(func(_t): _on_item_pressed())
	_set_testing_status("")

	# The switch is server state, not panel state, so the panel has to ask.
	# Re-asked every time it is opened rather than only here: the owner may have
	# thrown it from another machine, and a stale button is a button that closes
	# a server somebody already reopened.
	if not visibility_changed.is_connected(_on_visibility_changed):
		visibility_changed.connect(_on_visibility_changed)
	_build_server_button_styles()
	_populate_ranks()
	_refresh_maintenance()


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
		"maintenance":
			return maintenance_button
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


# =============================================================================
# RANK
# =============================================================================

func _populate_ranks() -> void:
	# ONLY RANKS BELOW YOUR OWN. The server enforces this anyway - it refuses to
	# grant a rank at or above the caller's - but offering a choice that is
	# always going to be refused is a worse way to learn the rule than simply
	# not offering it. As owner you see all three; a dev sees player and mod.
	if role_option == null:
		return

	var mine: int = RANKS.find("owner") if Api.is_owner else RANKS.find(Api.role)
	if mine < 0:
		mine = 0

	# Rebuilt rather than filtered in place, because rank can change under us -
	# the owner may have just demoted the account this client is logged in as.
	var keep: int = role_option.get_selected_id() if role_option.item_count > 0 else -1
	role_option.clear()
	for i in range(mine):
		role_option.add_item(RANKS[i], i)

	if role_option.item_count == 0:
		return
	# Restore the previous pick when it is still on offer, so reopening the
	# panel does not silently move the selection to something else.
	for i in range(role_option.item_count):
		if role_option.get_item_id(i) == keep:
			role_option.select(i)
			return
	role_option.select(0)


func _on_role_pressed() -> void:
	# The server decides for real, and it enforces a rule this panel cannot:
	# you may not grant a rank at or above your own, so only the owner makes a
	# dev. 'owner' itself is not settable at all - it comes from ELUSION_OWNER
	# in the server's environment, which is what makes it the one rank no
	# request can hand out.
	if Api.role != "mod" and Api.role != "dev" and not Api.is_owner:
		return

	var username: String = "" if username_input == null else username_input.text.strip_edges()
	if username == "":
		_say("[GM] type a username first.")
		return

	var new_role: String = ""
	if role_option != null and role_option.selected >= 0:
		new_role = str(RANKS[role_option.get_selected_id()])
	if new_role == "":
		_say("[GM] pick a rank first.")
		return

	if role_button != null:
		role_button.disabled = true
	var res: Dictionary = await Api.put("/api/staff/role", {"username": username, "role": new_role})
	if role_button != null:
		role_button.disabled = false

	if not res.get("ok", false):
		var status: int = int(res.get("status", 0))
		if status == 0:
			_say("[GM] could not reach the server: %s" % str(res.get("error", "")))
		elif status == 404:
			# The same two answers every other target lookup gives, for the same
			# reason - require_role() hides behind "Not found" and so does a
			# target out of your reach. Do not guess which.
			_say("[GM] no account called '%s' - or it is out of your reach." % username)
		else:
			_say("[GM] rank change refused (%d): %s" % [status, str(res.get("error", ""))])
		return

	var data = res.get("data", {})
	if data is Dictionary:
		_say("[GM] %s: %s -> %s" % [
			username, str(data.get("was", "?")), str(data.get("role", new_role))])
	_on_view_pressed()


# =============================================================================
# THE SERVER SWITCH
# =============================================================================

func _on_visibility_changed() -> void:
	# Asked again on every open, because the switch is SERVER state: the owner
	# may have thrown it from another machine, and a stale button is one that
	# closes a server somebody already reopened.
	if visible:
		_refresh_maintenance()
		_populate_ranks()
	else:
		_disarm()


func _refresh_maintenance() -> void:
	# /api/status carries no token and needs no rank - it is the same call the
	# login screen makes before anyone has logged in.
	if maintenance_button == null and maintenance_status == null:
		return

	var res: Dictionary = await Api.get_json("/api/status")
	if not res.get("ok", false):
		_set_maintenance_display(_server_closed, "(could not read the server's state)")
		return

	var data = res.get("data", {})
	if not (data is Dictionary):
		return

	_server_closed = bool(data.get("maintenance", false))
	var detail: String = ""
	if _server_closed:
		detail = str(data.get("message", ""))
		var left: int = int(data.get("seconds_left", 0))
		if left > 0:
			detail += "  (%ds left to save)" % left
	_set_maintenance_display(_server_closed, detail)


func _build_server_button_styles() -> void:
	# Duplicated from the scene rather than written here, so restyling the panel
	# in the editor keeps working and this only ever changes two colours.
	if maintenance_button == null:
		return
	var normal: StyleBox = maintenance_button.get_theme_stylebox("normal")
	var hovered: StyleBox = maintenance_button.get_theme_stylebox("hover")
	if not (normal is StyleBoxFlat) or not (hovered is StyleBoxFlat):
		return

	_style_close = (normal as StyleBoxFlat).duplicate()
	_style_close_hover = (hovered as StyleBoxFlat).duplicate()

	_style_reopen = (normal as StyleBoxFlat).duplicate()
	_style_reopen.bg_color = Color(0.098, 0.235, 0.157)
	_style_reopen.border_color = Color(0.251, 0.525, 0.349)

	_style_reopen_hover = (hovered as StyleBoxFlat).duplicate()
	_style_reopen_hover.bg_color = Color(0.149, 0.341, 0.227)
	_style_reopen_hover.border_color = Color(0.361, 0.702, 0.471)


func _set_maintenance_display(closed: bool, detail: String) -> void:
	if maintenance_button != null:
		# THE BUTTON SAYS WHAT PRESSING IT DOES, not what the state is. A toggle
		# labelled with its current state is ambiguous in exactly the situation
		# where being wrong is expensive - and the colour says it a second time.
		maintenance_button.text = "Reopen server" if closed else "Close server"
		var box: StyleBoxFlat = _style_reopen if closed else _style_close
		var box_hover: StyleBoxFlat = _style_reopen_hover if closed else _style_close_hover
		if box != null:
			maintenance_button.add_theme_stylebox_override("normal", box)
		if box_hover != null:
			maintenance_button.add_theme_stylebox_override("hover", box_hover)
		maintenance_button.add_theme_color_override(
			"font_color", Color(0.62, 0.88, 0.70) if closed else Color(0.95, 0.66, 0.62))
	if maintenance_status != null:
		maintenance_status.text = ("CLOSED - %s" % detail) if closed else "Server is OPEN"
		# Colour carries the state faster than the words do, on a panel where
		# reading it wrong signs everyone out.
		maintenance_status.add_theme_color_override(
			"font_color", Color(0.94, 0.55, 0.36) if closed else Color(0.43, 0.84, 0.49))


func _on_maintenance_pressed(action: String) -> void:
	# Owner only, and the server agrees: require_owner answers 404 to everyone
	# else - the same 404 every owner route gives, so a refusal does not confirm
	# the route exists.
	if not Api.is_owner:
		return

	# REOPENING NEEDS NO CONFIRMATION. Closing signs everyone out once the save
	# window runs down; reopening only lets people back in. Making the safe
	# direction slower is how a server stays shut longer than it had to.
	if not _server_closed and _armed_action != action:
		_disarm()
		_armed_action = action
		_armed_until = Time.get_ticks_msec() / 1000.0 + ARM_SECONDS
		if maintenance_button != null:
			_armed_label = maintenance_button.text
			maintenance_button.text = "Confirm close?"
		_say("[SERVER] close the server? everyone is signed out once the save window "
			+ "runs out. press again within %d seconds." % int(ARM_SECONDS))
		return

	_disarm()

	var body: Dictionary = {"on": not _server_closed}
	if not _server_closed and maintenance_message_input != null:
		var message: String = maintenance_message_input.text.strip_edges()
		if message != "":
			body["message"] = message

	if maintenance_button != null:
		maintenance_button.disabled = true
	var res: Dictionary = await Api.post("/api/server/maintenance", body)
	if maintenance_button != null:
		maintenance_button.disabled = false

	if not res.get("ok", false):
		var status: int = int(res.get("status", 0))
		if status == 0:
			_say("[SERVER] could not reach the server: %s" % str(res.get("error", "")))
		elif status == 404:
			_say("[SERVER] refused - this account is not the owner.")
		else:
			_say("[SERVER] refused (%d): %s" % [status, str(res.get("error", ""))])
		return

	var data = res.get("data", {})
	if data is Dictionary:
		if bool(data.get("maintenance", false)):
			_say("[SERVER] CLOSED. %d online; they have %ds to save before being signed out."
				% [int(data.get("online_now", 0)), int(data.get("grace_seconds", 0))])
		else:
			_say("[SERVER] reopened - players can log in again.")
	await _refresh_maintenance()


# =============================================================================
# TESTING YOUR OWN SYSTEMS
# =============================================================================
# WHY THIS IS IN THE OWNER PANEL AND NOT ON A DEBUG KEY.
#
# The F-key grants are gated on OS.is_debug_build(), so they exist when the
# game is run from the editor and vanish the moment it is exported - which is
# exactly when the shops, the bank, trading, reviving and founding a guild
# most need exercising. A server whose owner cannot put gold on it is a server
# whose economy cannot be tested by the person who wrote it.
#
# SELF ONLY, AND THE SERVER SAYS SO. /api/staff/gold is @require_owner and
# takes no target; these boxes cannot reach another account even by trying.
#
# IT SPEAKS ON SCREEN, NOT THROUGH _say(). Everything else in this panel
# reports with _say(), which prints only in a debug build - so in an exported
# build the panel does its work in total silence. That is a bug of its own;
# this section at least does not repeat it.

func _on_gold_pressed(to_bank: bool) -> void:
	if gold_input == null:
		return

	var typed: String = gold_input.text.strip_edges()
	if typed == "":
		_set_testing_status("Type an amount first.")
		return
	if not typed.lstrip("-").is_valid_int():
		_set_testing_status("That is not a number.")
		return

	var amount: int = int(typed)
	if amount == 0:
		_set_testing_status("Zero would do nothing.")
		return

	_set_testing_status("Asking the server...")
	var res: Dictionary = await Api.post("/api/staff/gold", {
		"slot": CharacterData.active_character_index,
		"amount": amount,
		"bank": to_bank,
	})

	if not is_instance_valid(self) or not is_inside_tree():
		return
	if not res.get("ok", false):
		_set_testing_status(_refused(res))
		return

	var data = res.get("data", {})
	if not (data is Dictionary):
		_set_testing_status("The server did not say what happened.")
		return

	_set_testing_status("Carrying %d, bank %d." % [
		int(data.get("gold", 0)), int(data.get("bank_gold", 0))])

	# THE SERVER'S FIGURE, HANDED STRAIGHT TO THE PLAYER. set_gold() takes the
	# balance rather than a delta for exactly this reason - see its own note -
	# so there is no adding up to get wrong here.
	if not to_bank:
		var body: Node = get_tree().get_first_node_in_group("player")
		if body != null and body.has_method("set_gold"):
			body.set_gold(int(data.get("gold", 0)))


func _on_item_pressed() -> void:
	if item_input == null:
		return

	var wanted: String = item_input.text.strip_edges()
	if wanted == "":
		_set_testing_status("Type an item id first.")
		return

	var how_many: int = 1
	if item_count_input != null:
		var typed: String = item_count_input.text.strip_edges()
		if typed != "" and typed.is_valid_int():
			how_many = max(1, int(typed))

	_set_testing_status("Asking the server...")
	var res: Dictionary = await Api.post("/api/staff/grant", {
		"slot": CharacterData.active_character_index,
		"item_id": wanted,
		"quantity": how_many,
	})

	if not is_instance_valid(self) or not is_inside_tree():
		return
	if not res.get("ok", false):
		_set_testing_status(_refused(res))
		return

	# THE SERVER HANDS BACK THE WHOLE BAG, and the open inventory is told to
	# redraw from it - the same two lines the debug key uses, through the same
	# group lookup, so the two cannot drift.
	var data = res.get("data", {})
	var container: Node = _open_inventory_container()
	if container != null and data is Dictionary:
		container.load_server_array(data.get("inventory", []))
		_set_testing_status("Added %d x %s to your bag." % [how_many, wanted])
		return

	# THE ITEM IS REAL EVEN WHEN NOTHING IS OPEN TO SHOW IT. Saying "nothing
	# happened" here would be a lie - it is on the server and will be in the
	# bag on the next load.
	_set_testing_status(
		"Added %d x %s - open the inventory to see it." % [how_many, wanted])


func _open_inventory_container() -> Node:
	# THROUGH THE "hud" GROUP, exactly as player.gd's debug grant does. This
	# panel is a child of the HUD today and reaching upward by name is what
	# breaks the day somebody moves it.
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud == null or hud.inventory_screen == null:
		return null
	return hud.inventory_screen.get_node_or_null("%inventorycontainer")


func _refused(res: Dictionary) -> String:
	# THE SERVER'S OWN SENTENCE WHEN THERE IS ONE. Api._request has already
	# pulled it out of the body into `error`.
	var status: int = int(res.get("status", 0))
	var said: String = str(res.get("error", "")).strip_edges()
	if status == 0:
		return "No answer from the server. Is it running?"
	if status == 404 and (said == "" or said == "Not found."):
		return "The server does not allow that, or has no such route - restart it?"
	if said != "":
		return said
	return "Refused (HTTP %d)." % status


func _set_testing_status(line: String) -> void:
	if testing_status == null:
		return
	testing_status.text = line
	testing_status.visible = line != ""


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
