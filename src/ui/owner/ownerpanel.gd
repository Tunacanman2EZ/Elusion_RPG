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
# RESULTS ARE ON SCREEN. They used to go to the Output console only, through
# _say(), which also printed nothing at all outside a debug build - so in an
# exported game "View account", a kick, a ban, a rank change and closing the
# server all did their work in silence, and the one panel for acting on other
# people was the one that never said what it had done. Every _say() now lands
# in the results box at the bottom of the panel (and still in the console in a
# debug build, tagged, for grepping).
#
# A WINDOW LIKE THE OTHER SIXTEEN. PanelWindow gives it a header to drag, edges
# to resize and a remembered position, and the x in the header closes it - as
# do backquote and Esc. It was a fixed box pinned to the top-left with no way
# out but the key that opened it.
#
# THREE TABS, NO SCROLLING. Account (look up, sanctions, rank, moving people),
# Testing (your own character) and Server (the switch). The tab strip sizes to
# its tallest tab - use_hidden_tabs_for_min_size - so switching tabs never
# resizes the window under the mouse, and the results box takes what is left.
extends Control


# =============================================================================
# NODE REFERENCES
# =============================================================================

@onready var username_input: LineEdit = %usernameinput
@onready var view_button: Button = %viewbutton
# BESIDE VIEW ACCOUNT, and about the same name (0.7.5; the owner, 6 Oct: "roll
# back and give player item might be useful"). Give item opens the item
# catalogue with this name in its Give to box; Save history opens the window
# that lists their character's snapshots and restores one. Both are windows of
# their own, owned by the HUD like the catalogue always was, because a grid of
# pictures and a list of twenty snapshots need more room than this tab has -
# and the row costs the tab no height.
@onready var give_button: Button = get_node_or_null("%givebutton")
@onready var history_button: Button = get_node_or_null("%historybutton")

# THE WINDOW'S OWN PARTS. get_node_or_null like the rest, for the same reason.
@onready var close_button: Button = get_node_or_null("%ownerclosebutton")
@onready var tabs: TabContainer = get_node_or_null("%ownertabs")
@onready var results: RichTextLabel = get_node_or_null("%ownerresults")
@onready var results_clear: Button = get_node_or_null("%ownerresultsclear")

# The tab titles. Written here rather than taken from the node names, which are
# lowercase like every other node in the project.
const TAB_TITLES := ["Account", "Testing", "Server"]

# What each kind of result looks like in the box. Four, because there are four
# answers: it worked, it did not, it needs you to do something first, and the
# plain facts of an account view.
const SAY_GOOD := Color(0.55, 0.86, 0.6)
const SAY_BAD := Color(0.95, 0.55, 0.5)
const SAY_WARN := Color(0.95, 0.82, 0.5)
const SAY_NOTE := Color(0.78, 0.82, 0.87)
const SAY_HEAD := Color(0.93, 0.73, 0.3)
# The colour the old inline status lines were, kept for the quick answers the
# Testing tab and the teleport row give.
const SAY_STATUS := Color(0.95, 0.85, 0.62)

# Held, not discarded: PanelWindow is a RefCounted carrying the drag state, and
# letting it go frees it and the panel quietly stops being draggable.
var _window: PanelWindow

# Matches the "[GM] " / "[OWNER] " / "[SERVER] " tag the console lines carry.
# On screen it is noise - the whole panel is the GM's.
var _tag := RegEx.create_from_string("^\\[[A-Z]+\\] ")

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
@onready var catalogue_button: Button = get_node_or_null("%cataloguebutton")
@onready var gifts_button: Button = get_node_or_null("%giftsbutton")
@onready var level_input: LineEdit = get_node_or_null("%levelinput")
@onready var level_button: Button = get_node_or_null("%levelbutton")
@onready var skill_pick: OptionButton = get_node_or_null("%skillpick")
@onready var skill_input: LineEdit = get_node_or_null("%skillinput")
@onready var skill_button: Button = get_node_or_null("%skillbutton")
# MOVE PLAYERS. Its own name box since 0.7.4 - it used to read %usernameinput
# at the top of the tab, a screen away, and said so in its own heading. Under it
# the list of who is online, each with their own Bring and Go to.
@onready var move_name_input: LineEdit = get_node_or_null("%movenameinput")
@onready var tp_bring_button: Button = get_node_or_null("%tpbringbutton")
@onready var tp_goto_button: Button = get_node_or_null("%tpgotobutton")
@onready var tp_everyone_button: Button = get_node_or_null("%tpeveryonebutton")
@onready var online_label: Label = get_node_or_null("%onlinelabel")
@onready var online_refresh: Button = get_node_or_null("%onlinerefresh")
@onready var online_list: VBoxContainer = get_node_or_null("%onlinelist")

@onready var god_mode_button: CheckButton = get_node_or_null("%godmodebutton")
@onready var pvp_button: CheckButton = get_node_or_null("%pvpbutton")
@onready var trade_button: CheckButton = get_node_or_null("%tradebutton")
# The Server tab's minimum build (0.11.8): old versions must update.
@onready var minbuild_button: CheckButton = get_node_or_null("%minbuildbutton")
@onready var minbuild_status: Label = get_node_or_null("%minbuildstatus")
# THE CO-OWNERS' SWITCH (0.21.0), the owner's alone.
@onready var coowner_button: CheckButton = get_node_or_null("%coownerbutton")
@onready var coowner_status: Label = get_node_or_null("%coownerstatus")
# The performance readout (PerfOverlay). It was the backslash key until 0.7.1.
@onready var perf_button: CheckButton = get_node_or_null("%perfbutton")
@onready var rare_button: CheckButton = get_node_or_null("%rarebutton")
@onready var common_button: CheckButton = get_node_or_null("%commonbutton")

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
const RANKS := ["player", "mod", "dev", "coowner", "owner"]

var _armed_action: String = ""
var _armed_label: String = ""
var _armed_until: float = 0.0


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	visible = false
	_window = PanelWindow.attach(self, "owner")
	# At the largest text sizes the tabs are taller than the screen (0.8.0).
	_window.keep_scroll_fitted(get_node_or_null("%tabsscroll") as ScrollContainer)

	if close_button != null and not close_button.pressed.is_connected(close):
		close_button.pressed.connect(close)
	if results_clear != null and results != null \
			and not results_clear.pressed.is_connected(results.clear):
		results_clear.pressed.connect(results.clear)
	if tabs != null:
		for i in range(mini(tabs.get_tab_count(), TAB_TITLES.size())):
			tabs.set_tab_title(i, TAB_TITLES[i])
	if view_button != null and not view_button.pressed.is_connected(_on_view_pressed):
		view_button.pressed.connect(_on_view_pressed)
	if give_button != null and not give_button.pressed.is_connected(_on_give_pressed):
		give_button.pressed.connect(_on_give_pressed)
	if history_button != null and not history_button.pressed.is_connected(_on_history_pressed):
		history_button.pressed.connect(_on_history_pressed)

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
	if catalogue_button != null and not catalogue_button.pressed.is_connected(_on_catalogue_pressed):
		catalogue_button.pressed.connect(_on_catalogue_pressed)
	if gifts_button != null and not gifts_button.pressed.is_connected(show_what_i_have_given):
		gifts_button.pressed.connect(show_what_i_have_given)
	if level_button != null and not level_button.pressed.is_connected(_on_level_pressed):
		level_button.pressed.connect(_on_level_pressed)
	if level_input != null:
		level_input.text_submitted.connect(func(_t): _on_level_pressed())
	_populate_skills()
	if skill_button != null and not skill_button.pressed.is_connected(_on_skill_pressed):
		skill_button.pressed.connect(_on_skill_pressed)
	if skill_input != null:
		skill_input.text_submitted.connect(func(_t): _on_skill_pressed())

	if tp_bring_button != null and not tp_bring_button.pressed.is_connected(_on_teleport_pressed):
		tp_bring_button.pressed.connect(_on_teleport_pressed.bind("bring"))
	if tp_goto_button != null and not tp_goto_button.pressed.is_connected(_on_teleport_pressed):
		tp_goto_button.pressed.connect(_on_teleport_pressed.bind("goto"))
	if tp_everyone_button != null \
			and not tp_everyone_button.pressed.is_connected(_on_teleport_pressed):
		tp_everyone_button.pressed.connect(_on_teleport_pressed.bind("everyone"))
	if move_name_input != null and not move_name_input.text_submitted.is_connected(_on_move_name_submitted):
		move_name_input.text_submitted.connect(_on_move_name_submitted)
	if online_refresh != null and not online_refresh.pressed.is_connected(refresh_online):
		online_refresh.pressed.connect(refresh_online)
	_set_teleport_status("")

	# GOD MODE. A CheckButton rather than a Button, because it has two states
	# and the control should say which one it is in without being pressed.
	if god_mode_button != null \
			and not god_mode_button.toggled.is_connected(_on_god_mode_toggled):
		god_mode_button.toggled.connect(_on_god_mode_toggled)
	_sync_god_mode_button()

	if pvp_button != null and not pvp_button.toggled.is_connected(_on_pvp_toggled):
		pvp_button.toggled.connect(_on_pvp_toggled)
	if trade_button != null and not trade_button.toggled.is_connected(_on_trade_toggled):
		trade_button.toggled.connect(_on_trade_toggled)
	if minbuild_button != null and not minbuild_button.toggled.is_connected(_on_minbuild_toggled):
		minbuild_button.toggled.connect(_on_minbuild_toggled)
	if coowner_button != null and not coowner_button.toggled.is_connected(_on_coowner_toggled):
		coowner_button.toggled.connect(_on_coowner_toggled)
	if perf_button != null and not perf_button.toggled.is_connected(_on_perf_toggled):
		perf_button.toggled.connect(_on_perf_toggled)
	_sync_perf_button()
	if rare_button != null and not rare_button.toggled.is_connected(_on_rare_toggled):
		rare_button.toggled.connect(_on_rare_toggled)
	if common_button != null and not common_button.toggled.is_connected(_on_common_toggled):
		common_button.toggled.connect(_on_common_toggled)
	_sync_rare_button()

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


func close() -> void:
	# The x, and Esc through characterhud.gd's hide_panel(). Hiding is the whole
	# of closing: _on_visibility_changed() disarms anything half-confirmed.
	visible = false


func _process(_delta: float) -> void:
	# Disarm on a timer rather than on the next click. A button left reading
	# "Confirm ban?" is a trap for whoever looks at this panel next.
	if _armed_action != "" and Time.get_ticks_msec() / 1000.0 > _armed_until:
		_disarm()


# =============================================================================
# GIVE ITEM AND SAVE HISTORY - windows the HUD owns, opened on this name
# =============================================================================

# WHERE THEY OPEN, as a Callable so the suite can see the call without a HUD:
# (method on the HUD, username) -> whether a HUD took it.
var open_window: Callable = Callable(self, "_open_hud_window")


func _on_give_pressed() -> void:
	if not Api.is_owner:
		return
	var who: String = username_input.text.strip_edges() if username_input != null else ""
	if who == "":
		_say("[GM] type a username above, then Give item.", SAY_WARN)
		return
	if not open_window.call("open_item_spawner_for", who):
		_say("[GM] the item catalogue opens from inside the game.", SAY_WARN)
		return
	_say("[GM] the item catalogue is open with %s in Give to - click an item to give it, or set their level beside the name." % who, SAY_NOTE)


func _on_history_pressed() -> void:
	if not Api.is_owner:
		return
	var who: String = username_input.text.strip_edges() if username_input != null else ""
	if who == "":
		_say("[GM] type a username above, then Save history.", SAY_WARN)
		return
	if not open_window.call("open_save_history", who):
		_say("[GM] the save history opens from inside the game.", SAY_WARN)


func _open_hud_window(method: String, who: String) -> bool:
	var hud: Node = get_tree().get_first_node_in_group("hud") if is_inside_tree() else null
	if hud == null or not hud.has_method(method):
		return false
	hud.call(method, who)
	return true


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
			_say("[OWNER] could not reach the server: %s" % str(res.get("error", "")), SAY_BAD)
		elif status == 404:
			# 404 IS TWO ANSWERS HERE, and they cannot be told apart on purpose.
			# require_role() answers "Not found" to a non-staff caller so a 403
			# does not confirm the route exists - so this is either "no such
			# account" or "you are not staff". Say both rather than guess.
			_say("[OWNER] no account called '%s' - or this account is not staff." % username, SAY_BAD)
		else:
			_say("[OWNER] server refused (%d): %s" % [status, str(res.get("error", ""))], SAY_BAD)
		return

	var data = res.get("data", {})
	if data is Dictionary:
		_print_save_summary(username, data)
	else:
		_say("[OWNER] unexpected response shape for '%s'" % username, SAY_BAD)


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
		"everyone":
			# So _disarm() puts "Bring everyone" back. Without this entry the
			# button stays reading "Confirm?" for ever after a timeout, which is
			# the trap ARM_SECONDS exists to prevent.
			return tp_everyone_button
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
		_say("[GM] type a username first.", SAY_WARN)
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
		_say("[GM] %s '%s'? press again within %d seconds." % [action, username, int(ARM_SECONDS)], SAY_WARN)
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
			_say("[GM] could not reach the server: %s" % str(res.get("error", "")), SAY_BAD)
		elif status == 404:
			# The same two answers the view button gets, and for the same
			# reason - require_role() hides itself behind "Not found", and so
			# does a target you cannot act on. Do not guess which.
			_say("[GM] no account called '%s' - or it is out of your reach." % username, SAY_BAD)
		else:
			_say("[GM] %s refused (%d): %s" % [action, status, str(res.get("error", ""))], SAY_BAD)
		return

	var data = res.get("data", {})
	if action == "kick" and data is Dictionary:
		# The count is the useful part: zero means they were already gone.
		_say("[GM] signed '%s' out of %s place(s)." % [username, str(data.get("sessions_ended", 0))], SAY_GOOD)
	else:
		_say("[GM] %s ok: %s" % [action, str(data)], SAY_GOOD)

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

	var mine: int = RANKS.find(Api.own_rank())
	if mine < 0:
		mine = 0
	# coowner and owner are never offered: they come from the server's
	# environment, and the rank route refuses them.
	mine = mini(mine, Api.GRANTABLE_RANKS.size())

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
		_say("[GM] type a username first.", SAY_WARN)
		return

	var new_role: String = ""
	if role_option != null and role_option.selected >= 0:
		new_role = str(RANKS[role_option.get_selected_id()])
	if new_role == "":
		_say("[GM] pick a rank first.", SAY_WARN)
		return

	if role_button != null:
		role_button.disabled = true
	var res: Dictionary = await Api.put("/api/staff/role", {"username": username, "role": new_role})
	if role_button != null:
		role_button.disabled = false

	if not res.get("ok", false):
		var status: int = int(res.get("status", 0))
		if status == 0:
			_say("[GM] could not reach the server: %s" % str(res.get("error", "")), SAY_BAD)
		elif status == 404:
			# The same two answers every other target lookup gives, for the same
			# reason - require_role() hides behind "Not found" and so does a
			# target out of your reach. Do not guess which.
			_say("[GM] no account called '%s' - or it is out of your reach." % username, SAY_BAD)
		else:
			_say("[GM] rank change refused (%d): %s" % [status, str(res.get("error", ""))], SAY_BAD)
		return

	var data = res.get("data", {})
	if data is Dictionary:
		_say("[GM] %s: %s -> %s" % [
			username, str(data.get("was", "?")), str(data.get("role", new_role))], SAY_GOOD)
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
		# The flags these two mirror live elsewhere (GameState, PerfOverlay),
		# so they are re-read on every open rather than remembered.
		_sync_god_mode_button()
		_sync_perf_button()
		_sync_rare_button()
		# SERVER STATE, so it is asked rather than remembered - the same rule
		# the maintenance switch follows. The owner may have thrown it from
		# another machine.
		await _refresh_pvp()
		await _refresh_trade()
		await _refresh_minbuild()
		await refresh_coowners()
		await refresh_online()
	else:
		_disarm()


# =============================================================================
# GOD MODE
# =============================================================================
# The switch writes GameState.god_mode, which take_damage() reads with the rank
# re-checked per hit. It is the only way in since 0.7.1: Ctrl+G went with the
# rest of the debug keys, and Api.GOD_MODE_MIN_ROLE became "owner" with it.

func _sync_god_mode_button() -> void:
	if god_mode_button == null:
		return
	# NO SIGNAL. Writing button_pressed fires toggled, which would call the
	# handler, which would flip the flag we are trying to mirror.
	god_mode_button.set_pressed_no_signal(GameState.god_mode)
	god_mode_button.disabled = not Api.role_at_least(Api.GOD_MODE_MIN_ROLE)


func _on_god_mode_toggled(pressed: bool) -> void:
	# THE RANK IS CHECKED HERE TOO, not only on the way into the panel. A
	# disabled button is a UI state, and a UI state is not an authorisation.
	if not Api.role_at_least(Api.GOD_MODE_MIN_ROLE):
		_sync_god_mode_button()
		_set_testing_status("[GM] god mode needs %s or above."
			% Api.rank_name(Api.GOD_MODE_MIN_ROLE))
		return

	GameState.god_mode = pressed

	# THE STATUS LINE NAMES THE COST, because the surprising half is not that
	# you stopped dying - it is that defense stops training. take_damage()
	# returns before gain_defense_xp(), so a session spent testing in god mode
	# trains no defense at all, and a flat skill bar an hour later is a worse way
	# to find that out.
	if pressed:
		_set_testing_status("[GM] god mode ON - no damage taken, and no defence XP.")
	else:
		_set_testing_status("[GM] god mode OFF.")

	print("[GM] god mode %s (%s)" % ["ON" if pressed else "OFF", Api.username])


# =============================================================================
# THE PERFORMANCE READOUT
# =============================================================================
# PerfOverlay's numbers in the top-left: frame rate and its worst moment, frame
# time against the 60 fps budget, nodes, physics, draw calls, memory and
# requests a second. It was the backslash key, in debug builds only; the owner
# asked for it here (6 Oct, "add to menu instead and remove backslash"), and
# here it works on the exported game too, because the panel is the gate.

func _sync_perf_button() -> void:
	if perf_button == null:
		return
	perf_button.set_pressed_no_signal(PerfOverlay.is_shown())


func _on_perf_toggled(pressed: bool) -> void:
	PerfOverlay.set_shown(pressed)
	if pressed:
		_set_testing_status("Performance readout ON - top left. Worst counts from now.")
	else:
		_set_testing_status("Performance readout OFF.")


# =============================================================================
# ALWAYS ROLL THE 1% (0.18.1)
# =============================================================================
# Every mythic attack takes its rare roll while this is on: every meteor pulls,
# every axe throw is bloody, every Dynamite throw is five sticks. The owner,
# offered it after not seeing two of them in an evening: "yes that sounds
# amazing". It writes GameState.force_rare_rolls, which Player.rare_forced()
# reads with the rank checked again - god mode's arrangement, for god mode's
# reasons.

func _sync_rare_button() -> void:
	# Both roll switches, the 1% and (0.18.2) the 10%.
	var allowed: bool = Api.role_at_least(Api.GOD_MODE_MIN_ROLE)
	if rare_button != null:
		rare_button.set_pressed_no_signal(GameState.force_rare_rolls)
		rare_button.disabled = not allowed
	if common_button != null:
		common_button.set_pressed_no_signal(GameState.force_common_rolls)
		common_button.disabled = not allowed


func _on_rare_toggled(pressed: bool) -> void:
	if not Api.role_at_least(Api.GOD_MODE_MIN_ROLE):
		_sync_rare_button()
		_set_testing_status("[GM] the rare roll needs %s or above." % Api.rank_name(Api.GOD_MODE_MIN_ROLE))
		return
	GameState.force_rare_rolls = pressed
	if pressed:
		_set_testing_status("[GM] rare rolls ON - every meteor pulls, every axe throw is bloody, every Dynamite throw is five sticks.")
	else:
		_set_testing_status("[GM] rare rolls OFF - back to 1 in 100.")
	print("[GM] rare rolls %s (%s)" % ["ON" if pressed else "OFF", Api.username])


# ALWAYS ROLL THE 10% (0.18.2). Its sibling: every meteor cast is two, every
# axe throw is wide, every Dynamite throw is three sticks. The owner: "do
# another switch for 10% casts". GameState.force_common_rolls, read through
# Player.common_forced() with the rank checked there too.
func _on_common_toggled(pressed: bool) -> void:
	if not Api.role_at_least(Api.GOD_MODE_MIN_ROLE):
		_sync_rare_button()
		_set_testing_status("[GM] the 10%% roll needs %s or above." % Api.rank_name(Api.GOD_MODE_MIN_ROLE))
		return
	GameState.force_common_rolls = pressed
	if pressed:
		_set_testing_status("[GM] 10% rolls ON - every meteor cast is two, every axe throw is wide, every Dynamite throw is three sticks.")
	else:
		_set_testing_status("[GM] 10% rolls OFF - back to 1 in 10.")
	print("[GM] 10%% rolls %s (%s)" % ["ON" if pressed else "OFF", Api.username])


# =============================================================================
# TELEPORT
# =============================================================================
# The server has had POST /api/staff/teleport for a while and characterhud.gd has
# always known how to RECEIVE one. Nothing had ever ISSUED one - the feature was
# built from both ends and never joined in the middle.
#
# THREE ACTIONS, AND ONLY TWO OF THEM ARE REQUESTS:
#
#   bring     the named account comes to where you are standing
#   everyone  every account on the server does, spaced by the server, announced
#             in chat - owner only, and armed-then-confirmed like a ban
#   goto      YOU move to them. No order is queued for anybody: position is
#             client-written, so going somewhere is a local act and sending a
#             request for it would be theatre.
#
# WHY A SAFE SPOT IS COMPUTED FOR EVERY ONE OF THEM. teleport_offset(0) in
# app.py is (0, 0), so a single teleport lands exactly on the destination - and
# the destination is wherever the person who pressed the button is standing. Two
# characters in one spot is what the request asked for and not what anybody
# meant. For "everyone" it is worse: slot 0 is somebody, and they land inside
# the owner.

func _on_teleport_pressed(action: String) -> void:
	await teleport(action, _move_name())


func _on_move_name_submitted(_text: String) -> void:
	# Enter in the name box brings them: the action a typed name is usually for.
	await teleport("bring", _move_name())


func _move_name() -> String:
	return "" if move_name_input == null else move_name_input.text.strip_edges()


func teleport(action: String, username: String) -> void:
	"""bring / goto / everyone, for `username` (ignored by everyone). The row
	buttons in the online list and the buttons under the name box both come
	here."""
	# The client gate is a courtesy; require_role("dev") and the owner check on
	# `everyone` are the real ones, on the side the player does not control.
	if not Api.role_at_least("dev") and not Api.is_owner:
		return

	var body: CharacterBody2D = get_tree().get_first_node_in_group("player") as CharacterBody2D
	if body == null:
		_set_teleport_status("[GM] no character in the world to teleport to or from.")
		return

	if action == "goto":
		await _teleport_go_to_them(username)
		return

	if action == "everyone":
		# ARMED, like a ban. This moves every account on the server and posts a
		# broadcast; it is the single widest button on this panel.
		if _armed_action != "everyone":
			_disarm()
			_armed_action = "everyone"
			_armed_until = Time.get_ticks_msec() / 1000.0 + ARM_SECONDS
			if tp_everyone_button != null:
				_armed_label = tp_everyone_button.text
				tp_everyone_button.text = "Confirm?"
			_set_teleport_status("[GM] move EVERYONE in the game here? press again within %d seconds."
				% int(ARM_SECONDS))
			return
		_disarm()

	if action == "bring" and username == "":
		_set_teleport_status("[GM] type a name, or pick somebody from the list below.")
		return

	# WHERE THEY LAND: beside the person who pressed the button, never on them.
	# start_ring 1 skips the anchor itself for exactly that reason.
	var spot: Vector2 = SafeSpot.find(body, body.global_position, 1)
	if spot == Vector2.INF:
		_set_teleport_status("[GM] nowhere clear to put anybody here - move and try again.")
		return

	var payload: Dictionary = {"x": spot.x, "y": spot.y}
	if action == "everyone":
		payload["everyone"] = true
	else:
		payload["username"] = username

	var res: Dictionary = await post_request.call("/api/staff/teleport", payload)
	if not is_instance_valid(self) or not is_inside_tree():
		return

	if not res.get("ok", false):
		var status: int = int(res.get("status", 0))
		if status == 0:
			_set_teleport_status("[GM] could not reach the server.")
		elif status == 403:
			_set_teleport_status("[GM] %s" % str(res.get("error", "refused")))
		elif status == 404:
			_set_teleport_status("[GM] no account called '%s' - or out of your reach." % username)
		else:
			_set_teleport_status("[GM] refused (%d): %s" % [status, str(res.get("error", ""))])
		return

	var data: Dictionary = res.get("data", {}) if res.get("data") is Dictionary else {}
	if action == "everyone":
		_set_teleport_status("[GM] moving %d players to %s, spaced %dpx apart."
			% [int(data.get("moved", 0)), str(data.get("area", "")),
			   int(float(data.get("spacing", 0.0)))])
	else:
		# QUEUED, NOT DONE. The order sits until their client polls and acks it,
		# so saying "moved" would be a lie about somebody who is offline.
		_set_teleport_status("[GM] '%s' will be moved to %s on their next poll."
			% [username, str(data.get("area", ""))])


func _teleport_go_to_them(username: String) -> void:
	if username == "":
		_set_teleport_status("[GM] type a name, or pick somebody from the list below.")
		return

	# WHERE THEY ARE PLAYING, from the who-is-online list: the character they
	# are in right now, not the one saved last. It used to read
	# /api/staff/user/<name> and go to the area of their most recent save, which
	# for somebody offline is a room they are not in.
	var res: Dictionary = await online_request.call("/api/players/online")
	if not is_instance_valid(self) or not is_inside_tree():
		return
	if not res.get("ok", false):
		_set_teleport_status("[GM] could not reach the server.")
		return
	var entry: Dictionary = _online_entry(res, username)
	if entry.is_empty():
		_set_teleport_status("[GM] '%s' is not online." % username)
		return
	var area: String = str(entry.get("area", ""))
	if not AreaRegistry.has_area(area):
		_set_teleport_status("[GM] '%s' is in '%s', which this build does not know."
			% [username, area])
		return

	# BESIDE THEM, through the presence link. The server knows the AREA and
	# nothing finer, but Presence draws everyone in your area where they stand,
	# so once their picture is here, standing beside them is a local move.
	# Presence.meet() waits for that, through the change of area below - which
	# frees this panel, so the waiting cannot live here. Position is
	# client-written, so no request is sent for any of it: going somewhere is
	# a local act, and /api/staff/teleport refuses acting on yourself anyway.
	var who: String = str(entry.get("username", username))
	if area == AreaRegistry.current_area_id():
		if Presence.meet(who):
			_set_teleport_status("[GM] beside '%s'." % who)
		elif Presence.phase() != "open":
			_set_teleport_status("[GM] '%s' is here in %s, but this game is not drawing other players right now."
				% [who, AreaRegistry.display_name(area)])
		else:
			_set_teleport_status("[GM] '%s' is here in %s - you will be put beside them when they are drawn."
				% [who, AreaRegistry.display_name(area)])
		return
	Presence.meet(who)
	_set_teleport_status("[GM] going to %s - you will land beside '%s'."
		% [AreaRegistry.display_name(area), who])
	AreaRegistry.go_to(area)


# =============================================================================
# WHO IS ONLINE
# =============================================================================
# The owner, 6 Oct: "pick who from a list". GET /api/players/online - the same
# list every player's Players window reads: account, character, level and the
# area they are playing in - each row with its own Bring and Go to. Clicking a
# name puts it in the name boxes too, so a view or a sanction is one click away.
# Asked on every open of the panel and on Refresh; not polled, because a list
# that reorders itself under the mouse is a list you misclick on.

# Swapped by the suite for a stand-in, like status_request and post_request.
var online_request: Callable = Callable(Api, "get_json")


func refresh_online() -> void:
	if online_list == null:
		return
	var res: Dictionary = await online_request.call("/api/players/online")
	if not is_instance_valid(self) or not is_inside_tree() or online_list == null:
		return
	for child in online_list.get_children():
		child.queue_free()
	if not res.get("ok", false):
		_online_note("Could not reach the server.")
		_set_online_count(-1)
		return
	var data: Dictionary = res.get("data", {}) if res.get("data") is Dictionary else {}
	var players: Array = data.get("players", []) if data.get("players") is Array else []
	var shown: int = 0
	for entry in players:
		if not (entry is Dictionary):
			continue
		# NOT YOU: nobody brings or visits themselves, and the server refuses
		# the first anyway.
		if str(entry.get("username", "")).to_lower() == Api.username.to_lower():
			continue
		online_list.add_child(_online_row(entry))
		shown += 1
	if shown == 0:
		_online_note("Nobody else is online.")
	_set_online_count(shown)


func _set_online_count(n: int) -> void:
	if online_label != null:
		online_label.text = "MOVE PLAYERS" if n < 0 else "MOVE PLAYERS - %d ONLINE" % n


func _online_note(text: String) -> void:
	var note := Label.new()
	note.text = text
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", SAY_NOTE)
	online_list.add_child(note)


func _online_row(entry: Dictionary) -> HBoxContainer:
	var who: String = str(entry.get("username", ""))
	var row := HBoxContainer.new()
	row.name = "row_" + who.validate_node_name()
	row.add_theme_constant_override("separation", 4)
	var pick := Button.new()
	pick.name = "pick"
	pick.flat = true
	pick.focus_mode = Control.FOCUS_NONE
	pick.clip_text = true
	pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick.add_theme_font_size_override("font_size", 12)
	var character: String = str(entry.get("name", ""))
	var area_text: String = AreaRegistry.display_name(str(entry.get("area", "")))
	if bool(entry.get("with_you", false)):
		area_text += " (here)"
	pick.text = "%s · %s Lv %d · %s" % [who, character, int(entry.get("level", 1)), area_text]
	# THE WHOLE LINE IN THE TOOLTIP: a long character name clips the area off
	# the end of the row.
	pick.tooltip_text = "%s\nClick to put %s in the name boxes." % [pick.text, who]
	pick.pressed.connect(_pick_name.bind(who))
	row.add_child(pick)
	for spec in [["bring", "Bring", "Bring %s to where you are standing"],
			["goto", "Go to", "Go to %s and stand beside them"]]:
		var button := Button.new()
		button.name = str(spec[0])
		button.text = str(spec[1])
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(52, 0)
		button.add_theme_font_size_override("font_size", 12)
		button.tooltip_text = str(spec[2]) % who
		button.pressed.connect(teleport.bind(str(spec[0]), who))
		row.add_child(button)
	return row


func _pick_name(who: String) -> void:
	if move_name_input != null:
		move_name_input.text = who
	if username_input != null:
		username_input.text = who


func _online_entry(res: Dictionary, username: String) -> Dictionary:
	"""`username`'s row in a /api/players/online answer, ignoring case, or {}."""
	var data: Dictionary = res.get("data", {}) if res.get("data") is Dictionary else {}
	var players: Array = data.get("players", []) if data.get("players") is Array else []
	var wanted: String = username.strip_edges().to_lower()
	for entry in players:
		if entry is Dictionary and str(entry.get("username", "")).to_lower() == wanted:
			return entry
	return {}


func _set_teleport_status(line: String) -> void:
	# INTO THE RESULTS BOX, like everything else. It was a label under the
	# buttons that appeared when there was something to say - which made the
	# tab taller than the window it was in the moment it spoke. "" meant
	# "clear the label"; with no label there is nothing to clear.
	if line != "":
		_say(line, SAY_STATUS)


# =============================================================================
# PVP
# =============================================================================
# SERVER STATE, not panel state, and not client state - which is the whole
# reason to build the switch before the combat that reads it. "May other players
# hurt me" has to be answered by the server; a flag in a client is a flag an
# attacker sets. Putting it in the right place first means the damage path has
# an authority to ask when it exists, rather than growing one in a hurry beside
# the thing that needed it.
#
# WHAT IT DOES TODAY, and the button's tooltip says the same: it announces in
# chat - the same broadcast path the maintenance notice uses - and it appears on
# /api/status for every client including one on the login screen. It does NOT
# make anybody damageable, because nothing in this game can damage another
# player yet. Saying otherwise on this panel would be a control describing a
# wire nobody ran.

func _refresh_pvp() -> void:
	# /api/status carries it and needs no token, so this works even in the
	# moment after a session ends.
	var res: Dictionary = await Api.get_json("/api/status")
	if not is_instance_valid(self) or not is_inside_tree() or pvp_button == null:
		return
	if not res.get("ok", false):
		return
	var data: Dictionary = res.get("data", {}) if res.get("data") is Dictionary else {}
	# NO SIGNAL. Writing button_pressed fires toggled, which would post the
	# state we are only trying to display.
	pvp_button.set_pressed_no_signal(bool(data.get("pvp", false)))
	pvp_button.disabled = not Api.is_owner


func _on_pvp_toggled(pressed: bool) -> void:
	# OWNER ONLY, checked here and again on the server, which answers 404 rather
	# than 403 so the route does not confirm itself to anyone else.
	if not Api.is_owner:
		await _refresh_pvp()
		_set_testing_status("[GM] PvP is the owner's switch.")
		return

	var res: Dictionary = await Api.post("/api/server/pvp", {"on": pressed})
	if not is_instance_valid(self) or not is_inside_tree():
		return

	if not res.get("ok", false):
		# PUT BACK. The switch shows SERVER state, so a refused press must not
		# leave the button claiming something the server never agreed to.
		await _refresh_pvp()
		_set_testing_status("[GM] the server refused that: %s" % str(res.get("error", "")))
		return

	if pressed:
		_set_testing_status("[GM] %s has gone hostile. Announced in chat."
			% Api.username)
	else:
		_set_testing_status("[GM] %s has cooled off. Announced in chat." % Api.username)


# =============================================================================
# TRADING - the owner's switch on the one road between accounts
# =============================================================================
# The kill is still the game's word (SECURITY_NOTES E-3), so a cheated drop is
# real loot, and a trade is the only way it reaches anybody else. Off stops new
# trades; one already open may finish (the owner, 6 Oct: "allow trade to
# finish"). POST /api/server/trade, owner only; /api/status says where it is.
var status_request: Callable = Callable(Api, "get_json")


func _refresh_trade() -> void:
	if trade_button == null:
		return
	var res: Dictionary = await status_request.call("/api/status")
	if not is_instance_valid(self) or not is_inside_tree() or not res.get("ok", false):
		return
	var data: Dictionary = res.get("data", {}) if res.get("data") is Dictionary else {}
	# NO SIGNAL: showing the server's state must not post it back. An older
	# server says nothing about trade, and trading there is simply on.
	trade_button.set_pressed_no_signal(bool(data.get("trade", true)))
	trade_button.disabled = not Api.is_owner


func _on_trade_toggled(pressed: bool) -> void:
	if not Api.is_owner:
		await _refresh_trade()
		_say("Trading is the owner's switch.", SAY_BAD)
		return
	var res: Dictionary = await post_request.call("/api/server/trade", {"on": pressed})
	if not is_instance_valid(self) or not is_inside_tree():
		return
	if not res.get("ok", false):
		# PUT BACK, like PvP: the switch shows what the server holds.
		await _refresh_trade()
		_say("The server refused that: %s" % str(res.get("error", "")), SAY_BAD)
		return
	var data: Dictionary = res.get("data", {}) if res.get("data") is Dictionary else {}
	if pressed:
		_say("Trading is open. Announced in chat.", SAY_GOOD)
	else:
		var still_open: int = int(data.get("open_trades", 0))
		_say("Trading is off: nobody can open a new trade. %s Announced in chat." % (
			"No trade was open." if still_open == 0
			else "%d open trade%s may still finish." % [still_open, "" if still_open == 1 else "s"]),
			SAY_WARN)


# =============================================================================
# OLD VERSIONS MUST UPDATE - the minimum build (0.11.8)
# =============================================================================
# The server has refused a game older than a minimum it holds since the build
# gate went in (POST /api/server/minbuild, owner only), and nothing in the game
# could set it: the owner asked "how to raise client build", and the answer was
# a request with his token by hand. This is that request.
#
# ON MEANS "THIS GAME'S BUILD", never a number typed. Api.BUILD is the build of
# the game the owner is holding, and the server refuses a minimum newer than any
# game it knows - so the switch cannot lock its own owner out, and there is no
# box to mistype a 40 into. Off is 0: every version may play. The server keeps
# who set it and when, in the staff log.

func _refresh_minbuild() -> void:
	if minbuild_button == null:
		return
	var res: Dictionary = await status_request.call("/api/status")
	if not is_instance_valid(self) or not is_inside_tree() or not res.get("ok", false):
		return
	var data: Dictionary = res.get("data", {}) if res.get("data") is Dictionary else {}
	var minimum: int = int(data.get("min_client_build", 0))
	# NO SIGNAL: showing the server's state must not post it back.
	minbuild_button.set_pressed_no_signal(minimum > 0 and minimum >= Api.BUILD)
	minbuild_button.disabled = not Api.is_owner
	_show_minbuild(minimum)


func _show_minbuild(minimum: int) -> void:
	if minbuild_status == null:
		return
	if minimum <= 0:
		minbuild_status.text = "Every version of the game can play."
	else:
		minbuild_status.text = "Versions before build %d are told to update." % minimum


func _on_minbuild_toggled(pressed: bool) -> void:
	if not Api.is_owner:
		await _refresh_minbuild()
		_say("The minimum version is the owner's switch.", SAY_BAD)
		return
	var wanted: int = Api.BUILD if pressed else 0
	var res: Dictionary = await post_request.call("/api/server/minbuild", {"build": wanted})
	if not is_instance_valid(self) or not is_inside_tree():
		return
	if not res.get("ok", false):
		# PUT BACK: the switch shows what the server holds.
		await _refresh_minbuild()
		_say("The server refused that: %s" % str(res.get("error", "")), SAY_BAD)
		return
	var data: Dictionary = res.get("data", {}) if res.get("data") is Dictionary else {}
	var minimum: int = int(data.get("min_client_build", wanted))
	_show_minbuild(minimum)
	if minimum > 0:
		_say("Games older than build %d are now told to update before they can play." % minimum,
			SAY_WARN)
	else:
		_say("Every version of the game can play again.", SAY_GOOD)


# =============================================================================
# THE CO-OWNERS (0.21.0) - the owner's switch
# =============================================================================
# The owner, 10 Oct: "i would promote allmind to owner but there can only be 1
# however thats why i want to build another gate that allows him to enter", and
# "maybe a switch in my gm panel that gives him access as long as i leave it on".
# WHO it lets in is named in the server's .env (ELUSION_CO_OWNERS), where no
# request can write it; WHETHER they are in is this switch. On, they have every
# power the owner has, this panel included - except over the owner. Only THE
# owner throws it (Api.is_the_owner()); a co-owner sees it and cannot move it.

# Swapped by the suite for a stand-in, like status_request.
var coowner_request: Callable = Callable(Api, "get_json")


func refresh_coowners() -> void:
	if coowner_button == null:
		return
	var res: Dictionary = await coowner_request.call("/api/server/coowners")
	if not is_instance_valid(self) or not is_inside_tree():
		return
	if not res.get("ok", false):
		coowner_button.set_pressed_no_signal(false)
		coowner_button.disabled = true
		_show_coowners({}, int(res.get("status", 0)) == 404)
		return
	var data: Dictionary = res.get("data", {}) if res.get("data") is Dictionary else {}
	# NO SIGNAL: showing the server's state must not post it back.
	coowner_button.set_pressed_no_signal(bool(data.get("on", false)))
	# The owner's alone; and with nobody named there is nothing to switch on.
	var nobody: bool = (data.get("names", []) as Array).is_empty() and not bool(data.get("on", false))
	coowner_button.disabled = not Api.is_the_owner() or nobody
	_show_coowners(data)


func _show_coowners(data: Dictionary, no_switch: bool = false) -> void:
	if coowner_status == null:
		return
	coowner_status.text = coowner_line(data, no_switch)


static func coowner_line(data: Dictionary, no_switch: bool = false) -> String:
	"""What the line under the switch says, from GET /api/server/coowners."""
	# ONE SHORT LINE, like the minimum build's under it: a wrapping label in a
	# hidden tab measures as a column of single words and stretches the panel.
	if no_switch:
		return "This server has no co-owner switch yet."
	var names: Array = data.get("names", []) if data.get("names") is Array else []
	if names.is_empty():
		return "Nobody named in the server's ELUSION_CO_OWNERS."
	var who: String = ", ".join(PackedStringArray(names.map(func(n): return str(n))))
	if bool(data.get("on", false)):
		return "%s: in, with all you have but power over you." % who
	return "%s: out - just their own rank." % who


func _on_coowner_toggled(pressed: bool) -> void:
	if not Api.is_the_owner():
		await refresh_coowners()
		_say("Only the owner lets co-owners in or takes them out.", SAY_BAD)
		return
	var res: Dictionary = await post_request.call("/api/server/coowners", {"on": pressed})
	if not is_instance_valid(self) or not is_inside_tree():
		return
	if not res.get("ok", false):
		# PUT BACK: the switch shows what the server holds.
		await refresh_coowners()
		_say(_refused(res), SAY_BAD)
		return
	var data: Dictionary = res.get("data", {}) if res.get("data") is Dictionary else {}
	coowner_button.set_pressed_no_signal(bool(data.get("on", pressed)))
	_show_coowners(data)
	var who: String = ", ".join(PackedStringArray((data.get("names", []) as Array).map(func(n): return str(n))))
	if bool(data.get("on", pressed)):
		_say(("%s can use everything you can now - the GM panel on their next heartbeat. Every gift"
			+ " they make goes in the gifts ledger under their name.") % who, SAY_WARN)
	else:
		_say("%s is back to their own rank, from their next request." % who, SAY_GOOD)


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
			+ "runs out. press again within %d seconds." % int(ARM_SECONDS), SAY_WARN)
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
			_say("[SERVER] could not reach the server: %s" % str(res.get("error", "")), SAY_BAD)
		elif status == 404:
			_say("[SERVER] refused - this account is not the owner.", SAY_BAD)
		else:
			_say("[SERVER] refused (%d): %s" % [status, str(res.get("error", ""))], SAY_BAD)
		return

	var data = res.get("data", {})
	if data is Dictionary:
		if bool(data.get("maintenance", false)):
			_say("[SERVER] CLOSED. %d online; they have %ds to save before being signed out."
				% [int(data.get("online_now", 0)), int(data.get("grace_seconds", 0))], SAY_GOOD)
		else:
			_say("[SERVER] reopened - players can log in again.", SAY_GOOD)
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
# IT SPEAKS ON SCREEN. This comment used to say the rest of the panel worked
# "in total silence" in an exported build, and it did - every other result went
# through _say(), console only. Now everything, these included, lands in the
# results box at the bottom of the panel.

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

	# THE SERVER'S FIGURES, HANDED STRAIGHT OVER: the purse to the player, the
	# bank to CharacterData. It answers with both whichever pile it grew. The
	# bank one was not copied before, so a grant to the bank showed nowhere
	# until a relog.
	var body: Node = get_tree().get_first_node_in_group("player")
	CharacterData.adopt_server_gold({"carried_gold": int(data.get("gold", 0)),
		"bank_gold": int(data.get("bank_gold", 0))}, body)


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
	# redraw from it, found through the HUD's group the way the cooking screen
	# finds it.
	var data = res.get("data", {})
	# What it came to, when it is money (THE GIFTS LEDGER, 0.20.0).
	var money: String = ItemSpawner.money_text(data.get("worth") if data is Dictionary else null)
	var came_to: String = " (%s)" % money if money != "" else ""
	var container: Node = _open_inventory_container()
	if container != null and data is Dictionary:
		container.load_server_array(data.get("inventory", []))
		_set_testing_status("Added %d x %s to your bag%s." % [how_many, wanted, came_to])
		return

	# THE ITEM IS REAL EVEN WHEN NOTHING IS OPEN TO SHOW IT. Saying "nothing
	# happened" here would be a lie - it is on the server and will be in the
	# bag on the next load.
	_set_testing_status(
		"Added %d x %s%s - open the inventory to see it." % [how_many, wanted, came_to])


# THE ITEM CATALOGUE (itemspawner.gd) opens from here. It had a button of its
# own on the HUD's staff row; the owner wanted the testing tools in one place
# (5 Oct), and the catalogue stays a window of its own because a grid of
# pictures needs more room than this panel has. The HUD still owns it, so Esc
# and "is a panel open" keep working unchanged.
func _on_catalogue_pressed() -> void:
	var hud: Node = get_tree().get_first_node_in_group("hud") if is_inside_tree() else null
	if hud == null or not hud.has_method("toggle_item_spawner"):
		_set_testing_status("The item catalogue opens from inside the game.")
		return
	hud.toggle_item_spawner()


# THE GIFTS LEDGER (0.20.0; "What I've given" until 0.21.0, when a co-owner's
# gifts joined the owner's and it says who gave what). The owner, 10 Oct, after giving the first other
# player 10,990 Piles of Gold and deciding to keep it: "make a ledger for
# anthing i give to players so its accounted for if i ever ask how much did i
# inflate my server". The server writes a row for every gift as it is made -
# to a player, to yourself, gold put straight in - with what it was worth that
# day, and read the gifts from before back out of its logs once (THE GIFTS
# LEDGER in app.py). GET /api/staff/gifts adds it up; this prints it into the
# box below, beside the gold there is in the game now. On the server,
# giftwatch.py prints the same from the database.

const GIFTS_PATH := "/api/staff/gifts?recent=10"

# Swapped by the suite for a stand-in, like status_request.
var gifts_request: Callable = Callable(Api, "get_json")


func show_what_i_have_given() -> void:
	if not Api.is_owner:
		return
	if gifts_button != null:
		gifts_button.disabled = true
	var res: Dictionary = await gifts_request.call(GIFTS_PATH)
	if not is_instance_valid(self) or not is_inside_tree():
		return
	if gifts_button != null:
		gifts_button.disabled = false
	if not res.get("ok", false):
		if int(res.get("status", 0)) == 404:
			# The owner is never refused it, so a 404 is a server from before.
			_say("[GM] this server has no gifts ledger yet - update the API, then ask again.", SAY_WARN)
		else:
			_say("[GM] " + _refused(res), SAY_BAD)
		return
	var data: Variant = res.get("data", {})
	if not data is Dictionary:
		_say("[GM] the server did not say.", SAY_BAD)
		return
	var start: int = 0
	if results != null:
		# Read from the top, like an account view.
		results.scroll_following = false
		start = maxi(results.get_paragraph_count() - 1, 0)
	for line in gift_report_lines(data):
		_view_line(str(line[0]), line[1])
	if results != null:
		results.call_deferred("scroll_to_paragraph", start)


static func gift_report_lines(data: Dictionary) -> Array:
	"""GET /api/staff/gifts's answer as [text, colour] lines, in words."""
	var lines: Array = [["========== THE GIFTS LEDGER ==========", SAY_HEAD]]
	var totals: Dictionary = _as_dict(data.get("totals"))
	var since: int = _whole(data.get("ledger_since"))
	if since > 0:
		lines.append(["counted from %s, the first gift the server's logs remember" % LocalTime.full(since), SAY_NOTE])
	if _whole(totals.get("gifts")) == 0:
		lines.append(["Nothing given yet.", SAY_NOTE])
		return lines
	lines.append(["everything  : %s" % _gift_sum_text(totals), SAY_NOTE])
	lines.append(["to players  : %s" % _gift_sum_text(_as_dict(data.get("to_players"))), SAY_NOTE])
	# A giver to his own account - the owner's, or a co-owner's (0.21.0).
	lines.append(["to themselves: %s" % _gift_sum_text(_as_dict(data.get("to_yourself"))), SAY_NOTE])
	if _whole(totals.get("item_value")) > 0:
		lines.append(["  the items would sell to the shop for %s gold"
			% GameConstants.commas(_whole(totals.get("item_sells_for"))), SAY_NOTE])

	var economy: Dictionary = _as_dict(data.get("economy"))
	lines.append(["--- the gold in the game now ---", SAY_HEAD])
	lines.append(["  %s gold in purses and banks" % GameConstants.commas(_whole(economy.get("gold_now"))), SAY_NOTE])
	var share: Variant = data.get("share_of_gold_now")
	if (share is float or share is int) and _whole(totals.get("gold")) != 0:
		if float(share) > 1.0:
			# Piles given and not used yet: they count as given, and are in
			# nobody's purse, so a percentage would be thousands.
			lines.append(["  the gold given is more than all of it: a pile still in a bag", SAY_NOTE])
			lines.append(["  counts as given, and is in nobody's purse until it is used", SAY_NOTE])
		else:
			lines.append(["  the gold given is %.1f%% of that" % (float(share) * 100.0), SAY_NOTE])
			lines.append(["  (a pile still in a bag counts as given, and is in nobody's purse until it is used)", SAY_NOTE])

	# WHO GAVE IT (0.21.0), once there is more than the owner giving.
	var givers: Array = data.get("by_giver", []) if data.get("by_giver") is Array else []
	if givers.size() > 1:
		lines.append(["--- who gave it ---", SAY_HEAD])
		for entry in givers:
			var row: Dictionary = _as_dict(entry)
			lines.append(["  %s: %s" % [str(row.get("username", "?")), _gift_sum_text(row)], SAY_NOTE])

	var people: Array = data.get("by_player", []) if data.get("by_player") is Array else []
	if not people.is_empty():
		lines.append(["--- who got it, the most gold first ---", SAY_HEAD])
		for entry in people:
			var row: Dictionary = _as_dict(entry)
			lines.append(["  %s: %s" % [str(row.get("username", "?")), _gift_sum_text(row)], SAY_NOTE])

	var newest: Array = data.get("recent", []) if data.get("recent") is Array else []
	if not newest.is_empty():
		lines.append(["--- the newest ---", SAY_HEAD])
		var several: bool = givers.size() > 1
		for entry in newest:
			var row: Dictionary = _as_dict(entry)
			var item_id: String = str(row.get("item_id", ""))
			var what: String = "gold"
			if item_id != "":
				var item: ItemData = ItemRegistry.get_item(item_id)
				what = "%s × %s" % [GameConstants.commas(_whole(row.get("quantity"))),
					item.display_name if item != null else item_id]
			# "by AllMind" only when more than one has given: otherwise it is
			# the owner on every line.
			var by: String = " (by %s)" % str(row.get("by", "?")) if several else ""
			lines.append(["  %s  %s: %s, %s%s" % [LocalTime.full(_whole(row.get("at"))),
				str(row.get("username", "?")), what, _worth_text(row), by], SAY_NOTE])
	return lines


static func _gift_sum_text(sums: Dictionary) -> String:
	"""'274,750,000 gold, 199 lusions, items worth 400 (14 gifts)'."""
	return "%s (%s)" % [_worth_text(sums), GameConstants.counted(_whole(sums.get("gifts")), "gift")]


static func _worth_text(row: Dictionary) -> String:
	var parts: Array = []
	if _whole(row.get("gold")) != 0:
		parts.append("%s gold" % GameConstants.commas(_whole(row.get("gold"))))
	if _whole(row.get("lusions")) != 0:
		parts.append(GameConstants.counted(_whole(row.get("lusions")), "lusion"))
	if _whole(row.get("item_value")) != 0:
		parts.append("items worth %s" % GameConstants.commas(_whole(row.get("item_value"))))
	return ", ".join(parts) if not parts.is_empty() else "nothing"


static func _as_dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


static func _whole(value: Variant) -> int:
	# JSON's numbers arrive as floats, and a null is not a number.
	return int(value) if value is int or value is float else 0


# YOUR LEVEL, ON THE SERVER. It was a SpinBox in the Items window, and a
# SpinBox keeps typed text in its LineEdit until Enter or until it loses focus:
# the owner typed 99, pressed a button that takes no focus, and the request
# carried the 29 already in the box. Here it is a LineEdit like the gold and
# item rows beside it, read as typed when the button is pressed.
#
# /api/staff/level is @require_owner and changes only the caller's own
# character: XP from zero, the maxima for the new level, the pools full and
# recorded as a level-up grant, so the healing check does not call it a cheat.
const LEVEL_MAX := 99  # STAFF_LEVEL_MAX in app.py

# Where the request goes and where its answer lands, as Callables so the suite
# can watch them without a server or a character (the Items window's pattern).
var post_request: Callable = Callable(Api, "post")
var apply_level: Callable = _apply_level
var apply_skills: Callable = _apply_skills


func _on_level_pressed() -> void:
	if level_input == null:
		return
	if not Api.is_owner:
		_set_testing_status("Setting a level is the owner's.")
		return

	var typed: String = level_input.text.strip_edges()
	if typed == "":
		_set_testing_status("Type a level first.")
		return
	if not typed.is_valid_int() or int(typed) < 1 or int(typed) > LEVEL_MAX:
		_set_testing_status("A level is a whole number from 1 to %d." % LEVEL_MAX)
		return

	var wanted: int = int(typed)
	_set_testing_status("Asking the server for level %d..." % wanted)
	var res: Dictionary = await post_request.call("/api/staff/level", {
		"slot": CharacterData.active_character_index,
		"level": wanted,
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

	apply_level.call(data)
	_set_testing_status("Level %d, from %d. XP starts again from zero." % [
		int(data.get("level", wanted)), int(data.get("was", 0))])


func _apply_level(data: Dictionary) -> void:
	# THE SERVER'S ANSWER, COPIED: player.apply_server_level() takes the level,
	# the XP and the pools the server stored, so the bars match it at once.
	var body: Node = get_tree().get_first_node_in_group("player") if is_inside_tree() else null
	if body != null and body.has_method("apply_server_level"):
		body.apply_server_level(data)


# =============================================================================
# SKILL LEVELS - the owner's own, set on the server
# =============================================================================
# The owner, 6 Oct: "i want full control of my stats in admin panel so i can do
# more testing". The level row's twin: pick a skill (or all six), type a
# level, and /api/staff/skill sets it on the character being played. The
# skill names are the server's (STAFF_SKILL_ORDER in app.py); the words are
# what the Stats window calls them.
const SKILL_CHOICES := [
	["all", "All skills"], ["attack", "Attack"], ["defense", "Defense"],
	["agility", "Agility"], ["magic", "Magic"], ["fishing", "Fishing"],
	["cooking", "Cooking"],
]
const SKILL_MAX := 99  # MAX_SKILL_LEVEL in app.py


func _populate_skills() -> void:
	if skill_pick == null or skill_pick.item_count > 0:
		return
	for choice in SKILL_CHOICES:
		skill_pick.add_item(str(choice[1]))
		skill_pick.set_item_metadata(skill_pick.item_count - 1, str(choice[0]))
	skill_pick.select(0)


func chosen_skill() -> String:
	if skill_pick == null or skill_pick.selected < 0:
		return "all"
	return str(skill_pick.get_item_metadata(skill_pick.selected))


func _on_skill_pressed() -> void:
	if skill_input == null:
		return
	if not Api.is_owner:
		_set_testing_status("Setting a skill is the owner's.")
		return

	var typed: String = skill_input.text.strip_edges()
	if typed == "":
		_set_testing_status("Type a skill level first.")
		return
	if not typed.is_valid_int() or int(typed) < 1 or int(typed) > SKILL_MAX:
		_set_testing_status("A skill level is a whole number from 1 to %d." % SKILL_MAX)
		return

	var skill: String = chosen_skill()
	var words: String = "every skill" if skill == "all" else skill.capitalize()
	var wanted: int = int(typed)
	_set_testing_status("Asking the server for %s at %d..." % [words, wanted])
	var res: Dictionary = await post_request.call("/api/staff/skill", {
		"slot": CharacterData.active_character_index,
		"skill": skill,
		"level": wanted,
	})

	if not is_instance_valid(self) or not is_inside_tree():
		return
	if not res.get("ok", false):
		_set_testing_status(_refused(res))
		return
	var data = res.get("data", {})
	if not (data is Dictionary) or not (data.get("skills", null) is Dictionary):
		_set_testing_status("The server did not say what happened.")
		return

	apply_skills.call(data)
	var skills: Dictionary = data["skills"]
	if skill == "all":
		_set_testing_status("Every skill is level %d now." % int(data.get("level", wanted)))
	else:
		var entry: Dictionary = skills.get(skill, {}) if skills.get(skill, {}) is Dictionary else {}
		_set_testing_status("%s %d, from %d." % [words, int(entry.get("level", wanted)),
			int(entry.get("was", 0))])


func _apply_skills(data: Dictionary) -> void:
	# THE SERVER'S ANSWER, COPIED, like _apply_level(): the player takes the
	# levels the server stored, so damage, defense and speed use them at once.
	var body: Node = get_tree().get_first_node_in_group("player") if is_inside_tree() else null
	if body != null and body.has_method("apply_server_skills"):
		body.apply_server_skills(data)


func _open_inventory_container() -> Node:
	# THROUGH THE "hud" GROUP, exactly as the cooking screen does. This
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
	# The same, and for the same reason as _set_teleport_status().
	if line != "":
		_say(line, SAY_STATUS)


func _say(line: String, colour: Color = SAY_NOTE) -> void:
	# ONE PLACE EVERY RESULT GOES THROUGH. On screen always; in the console only
	# in a debug build, and there with its tag, so the old grep still works.
	if OS.is_debug_build():
		print(line)
	if results != null:
		# A fresh result is followed; an account view turns this off while it
		# writes, so it can be read from the top.
		results.scroll_following = true
	_write(line, colour)


func _write(line: String, colour: Color) -> void:
	# add_text, never append_text: a username or an error from the server is
	# data, and BBCode in it would be markup.
	if results == null:
		return
	results.push_color(colour)
	results.add_text(_tag.sub(line, ""))
	results.pop()
	results.newline()


func _view_line(line: String, colour: Color = SAY_NOTE) -> void:
	# A line of an account view: into the box without turning following back
	# on, and to the console in a debug build like everything else.
	if OS.is_debug_build():
		print(line)
	_write(line, colour)


func _when(unix_seconds: int) -> String:
	# THIS WAS PRINTING UTC AND SAYING NOTHING ABOUT IT. It was the fourth copy
	# of the unix-to-wall-clock conversion in this project and the only one
	# that had lost the timezone offset, so every last-login and ban date in
	# the owner panel was seven hours out in Denver and thirteen in Sydney -
	# wrong in a way that looks exactly like right. Four copies is how that
	# happens; there is one now, in src/shared/localtime.gd.
	if unix_seconds <= 0:
		return "never"
	return LocalTime.full(unix_seconds)


# =============================================================================
# DISPLAY - the results box, and the console in a debug build
# =============================================================================

static func linked_how(entry: Dictionary) -> String:
	"""What a linked account shares with the one being looked at: addresses,
	the same computer (the game's install id - see INSTALL IDS in app.py), or
	both. The computer is the half a VPN does not change."""
	var parts: Array[String] = []
	var addresses: int = int(entry.get("shared_addresses", 0))
	if addresses > 0:
		# Spelled out rather than GameConstants.counted(): this is static, so
		# the testrunner can read it without building the panel.
		parts.append("shares %d %s, quietest holds %s" % [
			addresses, "address" if addresses == 1 else "addresses",
			str(entry.get("quietest_address_accounts")),
		])
	var computers: int = int(entry.get("shared_computers", 0))
	if computers > 0:
		parts.append("same computer%s" % (
			"" if computers == 1 else " (%d of them)" % computers))
		var crowd: int = int(entry.get("quietest_computer_accounts", 0))
		if crowd > 2:
			parts[-1] += ", %d accounts on it" % crowd
	return ", ".join(parts) if not parts.is_empty() else "linked"


func _print_save_summary(username: String, data: Dictionary) -> void:
	# RENDERS THE SERVER'S SHAPE, not a save file's. The previous version read
	# `version`, `saved_at`, `account_data` and `character_slots` from
	# user://character_<name>.save - keys that stopped existing when characters
	# moved into the database. It is the endpoint's payload now, and the two are
	# kept in step by GET /api/staff/user/<name> being the only source.
	#
	# READ FROM THE TOP. Following is turned off so thirty lines do not scroll
	# the name you asked about out of sight, and the box is scrolled back to
	# where this view starts once it is written.
	#
	# NOT CLEARED FIRST. A rank change reports "mod -> dev" and then shows the
	# account again; clearing here wiped the confirmation the moment it landed.
	# The box is a log, and Clear is a button.
	var start: int = 0
	if results != null:
		results.scroll_following = false
		start = maxi(results.get_paragraph_count() - 1, 0)
	_view_line("========== %s ==========" % str(data.get("username", username)), SAY_HEAD)
	_view_line("rank      : %s" % str(data.get("role", "?")))
	_view_line("created   : %s" % _when(int(data.get("created_at", 0))))
	_view_line("lusions   : %s" % str(data.get("lusions", 0)))

	var ban = data.get("ban")
	if ban is Dictionary:
		_view_line("BANNED    : %s" % str(ban), SAY_BAD)
	else:
		_view_line("banned    : no")

	var characters: Array = data.get("characters", [])
	_view_line("--- characters (%d) ---" % characters.size(), SAY_HEAD)
	if characters.is_empty():
		_view_line("  none")
	for entry in characters:
		if entry is Dictionary:
			_view_line("  [%s] %s the %s - level %s, in %s, saved %s" % [
				str(entry.get("slot")), str(entry.get("name")),
				str(entry.get("class_id")), str(entry.get("level")),
				str(entry.get("area")), _when(int(entry.get("updated_at", 0))),
			])

	var logins = data.get("logins", {})
	if logins is Dictionary:
		_view_line("--- logins ---", SAY_HEAD)
		_view_line("  %s, %s failed, from %s" % [
			GameConstants.counted(int(logins.get("total", 0)), "attempt"),
			str(logins.get("failed", 0)),
			GameConstants.counted(int(logins.get("addresses", 0)), "address", "addresses"),
		])
		var locked: int = int(logins.get("locked_until", 0))
		if locked > Time.get_unix_time_from_system():
			_view_line("  LOCKED OUT until %s" % _when(locked), SAY_BAD)
		elif int(logins.get("consecutive_failures", 0)) > 0:
			_view_line("  %s consecutive failures right now" % str(logins.get("consecutive_failures")))

		# The count is always shown; the addresses themselves only to someone
		# who could act on this account. See the note on can_act_on() in app.py.
		if not logins.get("addresses_visible", false):
			_view_line("  (addresses withheld - you cannot act on this account)")
		for attempt in logins.get("recent", []):
			if attempt is Dictionary:
				_view_line("  %s  %s  %s %s" % [
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
		_view_line("--- signed in now (%d) ---" % live, SAY_HEAD)
		if live == 0:
			_view_line("  nowhere - a kick would do nothing")
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
				_view_line("  expires %s  (%s left)" % [
					_when(int(entry.get("expires_at", 0))),
					GameConstants.counted(days_left, "day"),
				])

	# OTHER ACCOUNTS ON THE SAME ADDRESSES. Surfaced, never acted on - see
	# _linked_accounts() in app.py for why a link is reported with its strength
	# instead of as a verdict. A crowded address links strangers.
	var linked = data.get("linked_accounts", {})
	if linked is Dictionary:
		var accounts: Array = linked.get("accounts", [])
		if not linked.get("visible", false):
			_view_line("--- linked accounts ---", SAY_HEAD)
			_view_line("  (withheld - you cannot act on this account)")
		elif accounts.is_empty():
			_view_line("--- linked accounts (0) ---", SAY_HEAD)
		else:
			_view_line("--- linked accounts (%d%s) ---" % [
				accounts.size(), ", more exist" if linked.get("truncated", false) else "",
			], SAY_HEAD)
			for entry in accounts:
				if entry is Dictionary:
					var banned = entry.get("ban")
					_view_line("  %-18s %-6s %s%s" % [
						str(entry.get("username")),
						str(entry.get("strength")),
						linked_how(entry),
						"  [BANNED]" if banned is Dictionary else "",
					])
			_view_line("  'weak' means what they share is crowded - a carrier, a campus or")
			_view_line("  a library computer links strangers. Read it, do not act on it alone.")

	var kills: Array = data.get("kills", [])
	_view_line("--- kills reported (%d kinds) ---" % kills.size(), SAY_HEAD)
	if kills.is_empty():
		_view_line("  none")
	for kill in kills:
		if kill is Dictionary:
			_view_line("  %-18s x%-5s %s xp, last %s" % [
				str(kill.get("enemy_id")), str(kill.get("count")),
				str(kill.get("xp_total")), _when(int(kill.get("last_at", 0))),
			])

	var history: Array = data.get("staff_history", [])
	if not history.is_empty():
		_view_line("--- staff history ---", SAY_HEAD)
		for entry in history:
			if entry is Dictionary:
				_view_line("  %s  %s by %s  %s" % [
					_when(int(entry.get("at", 0))), str(entry.get("action")),
					str(entry.get("by")), str(entry.get("detail", "")),
				])

	_view_line("=====================================", SAY_HEAD)
	if results != null:
		# Deferred: the lines above are laid out on the next frame, and a
		# scroll asked for before then lands on a box that has no height yet.
		results.call_deferred("scroll_to_paragraph", start)
