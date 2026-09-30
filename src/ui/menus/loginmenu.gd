# loginmenu.gd — login screen, entry point before character select.
#
# CHANGED: this used to be a fully local profile gate — usernames and
# SHA-256 password hashes lived in user://users.cfg on the player's own
# machine. Accounts are now real: the server owns them, hashes passwords
# with a salt, and hands back a session token. See src/systems/api.gd.
#
# WHAT THIS MEANS FOR THE CODE HERE:
# - _on_login_button_pressed() is now a coroutine. Every server call
#   suspends until the response arrives, so the function can no longer
#   just branch on a return value. This is why it awaits.
# - the button is disabled while a request is in flight. Without that, an
#   impatient double-click fires two registrations for the same account
#   and the second one fails confusingly.
# - the local account helpers (is_username_taken / save_new_user /
#   check_user_password) are gone. Nothing reads user://users.cfg anymore.
#   Old local accounts do NOT migrate — players register once against the
#   server. There are few enough testers for that to be fine.
#
# SIGNING IN NEVER MAKES AN ACCOUNT. The button used to log you in if the
# account existed and silently create it if not - so a returning player who
# mistyped their own name got a brand new, empty account, a recovery-email
# prompt for it, and every character "gone". A new player now chooses
# "Create an account", types the password twice, and only then is one made.
# See CREATE AN ACCOUNT below.
#
# RANK: not decided here, and never mirrored into a save. It used to be a
# hardcoded username comparison running on the player's own machine, which
# anyone could patch out or fake. The server decides it, returns it with the
# login response, and Api.role holds it in memory for as long as the session
# lasts. owner > dev > mod > player, and nothing on disk has a say.
#
# SECURITY NOTES (read before touching):
# - no password ever touches disk here. "remember me" stores the USERNAME
#   and the session token — never the password — and with the box clear it
#   stores neither (Api.keep_signed_in).
# - the token in user://session.cfg is a bearer credential. Anyone with
#   the file can act as that account until it expires, same as a browser
#   cookie. That's the accepted tradeoff for not retyping a password.
# - client-side validation below is a courtesy so the player gets an
#   instant error instead of a round trip. The server validates everything
#   again and its answer is the one that counts.
#
# SIGNAL CONNECTIONS: all connected via code in _ready() below (not the
# editor's Node > Signals panel) — a code connection always points at
# whatever function currently has this name, with no separate stored link
# that can go stale if a node gets renamed later.
extends Control


# =============================================================================
# CONSTANTS
# =============================================================================

# mirrors the server's MIN_PASSWORD_LENGTH in app.py. Kept in sync by hand;
# if they ever disagree the server wins and the player sees its message.
const MIN_PASSWORD_LENGTH := 8

const WebPage := preload("res://src/systems/webpage.gd")

# Colours for the connection banner. Deliberately NOT the red that %errorlabel
# uses: "the server is down" is a statement about the world, not a complaint
# about what the player typed, and colouring it like a validation error makes
# people retype a password that was never wrong.
const STATUS_WORKING := Color(0.75, 0.72, 0.62)   # muted grey — "checking"
const STATUS_OFFLINE := Color(1.0, 0.65, 0.25)    # amber — "something is up"
const STATUS_ONLINE := Color(0.55, 0.85, 0.5)     # green — "server is up"

# How often the login screen re-checks the server while it sits open, so a
# server that comes up (or goes down) after this screen loaded is reflected
# without the player touching anything. The startup probe answers the
# question once; this keeps answering it.
const RECONNECT_POLL_SECONDS := 5.0

# Matches the server's six digit code. Used only to light the tick and to stop
# a half-typed code being submitted - the SERVER decides whether a code is
# right, and it counts every wrong guess against a five try ceiling.
const RECOVER_CODE_LENGTH := 6

# Green, for the recovery tick and its success line.
const STATUS_GOOD := Color(0.43, 0.84, 0.49)

# FOUR COLOURS FOR %errorlabel, because the server gives four kinds of answer and
# this label used to render all of them in one red.
#
# The red is not a mistake - it is a theme_override in loginmenu.tscn and it was
# right for the case it was written for. What it could not do is change. So
# "Connecting..." and "Loading characters..." - the two things that mean it is
# WORKING - arrived in the same red as "Incorrect password", and the recovery
# form, the email prompt and the connection banner on this very screen all
# already took a colour per state (_recover_say, _email_say, _set_status). The
# main line was the one that did not.
#
# The split that matters is the last two. "What you typed is wrong" asks the
# player to try again; "the door is shut to you" does not, and telling a banned
# player in the same red as a typo asks them to retype a password that was never
# the problem. Measured against app.py: /login answers 200/400/401/403/429 and
# /register answers 201/400/403/409/429, so this is four states because there
# are four, not because four is a nice number.
const SAY_WORKING := STATUS_WORKING              # grey  - a request is in flight
const SAY_GOOD := STATUS_GOOD                    # green - you are in
const SAY_REFUSED := Color(1.0, 0.4, 0.4)        # red   - what you typed is wrong
const SAY_BLOCKED := Color(1.0, 0.78, 0.28)      # amber - the door is shut anyway

# SAY_REFUSED is the exact colour loginmenu.tscn already overrides the label to,
# so the one case that was already right does not shift by a shade.


# =============================================================================
# EXPORTED SETTINGS
# =============================================================================

# assigned in the Inspector — points at the character select scene. BOTH
# success paths below (existing-user login, new-user registration) use
# this single source of truth instead of a hardcoded path string, which is
# what caused the original "Cannot open file res://scenes/CharacterSelect.tscn"
# crash (wrong folder name/casing, plus a second hardcoded path that had
# drifted out of sync with this one).
@export var char_select_scene: PackedScene


# =============================================================================
# STATE
# =============================================================================

# guards against overlapping submissions while a request is in flight.
var _request_in_flight: bool = false

# Guards the background reconnect probe: skip a tick while the previous one
# is still waiting out its timeout, so a dead server can't stack requests.
var _reconnect_probe_in_flight: bool = false

# RECOVERY. Every one is fetched with get_node_or_null and null-guarded, so an
# older copy of loginmenu.tscn without these nodes still opens and still logs
# people in - it simply has no recovery form.
@onready var login_form: Control = get_node_or_null("%loginform")
@onready var recover_form: Control = get_node_or_null("%recoverform")
@onready var recover_link_button: Button = get_node_or_null("%recoverlinkbutton")
@onready var recover_email: LineEdit = get_node_or_null("%recoveremail")
@onready var recover_send_button: Button = get_node_or_null("%recoversendbutton")
@onready var recover_code: LineEdit = get_node_or_null("%recovercode")
@onready var recover_code_light: Label = get_node_or_null("%recovercodelight")
@onready var recover_new_password: LineEdit = get_node_or_null("%recovernewpassword")
@onready var recover_confirm_password: LineEdit = get_node_or_null("%recoverconfirmpassword")
@onready var recover_submit_button: Button = get_node_or_null("%recoversubmitbutton")
@onready var recover_status: Label = get_node_or_null("%recoverstatus")
@onready var recover_back_button: Button = get_node_or_null("%recoverbackbutton")

# THE RECOVERY ADDRESS PROMPT, shown after a successful sign-in when the server
# says this account has no confirmed address. Same null-guarding as above.
@onready var email_form: Control = get_node_or_null("%emailform")
@onready var email_address: LineEdit = get_node_or_null("%emailaddress")
@onready var email_send_button: Button = get_node_or_null("%emailsendbutton")
@onready var email_code: LineEdit = get_node_or_null("%emailcode")
@onready var email_code_light: Label = get_node_or_null("%emailcodelight")
@onready var email_confirm_button: Button = get_node_or_null("%emailconfirmbutton")
@onready var email_status: Label = get_node_or_null("%emailstatus")

# The password the player just signed in with. POST /api/account/email demands
# it - a session alone must not be able to set the recovery address, or a
# stolen token could point recovery at the thief's inbox - and the player has
# only just typed it, so asking a second time would be theatre. Cleared the
# moment the address is confirmed.
var _password_for_email: String = ""

# Where to go once the address is confirmed. Held because the prompt interrupts
# the sign-in and we have to resume it afterwards.
var _pending_username: String = ""


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# THE TOWN STARTS LOADING NOW, ON A WORKER THREAD, WHILE THE PLAYER TYPES.
	# It used to load before this screen could appear at all - see the notes in
	# AreaRegistry's "LOADING AHEAD". The name is characterselect.gd's
	# WORLD_AREA; the suite holds the two to the same area. In a build without
	# threads (the browser's) this asks for nothing - there the load would BE
	# the wait; see AreaRegistry.loads_in_background().
	AreaRegistry.prefetch("elusion")

	# HIDDEN IN THE SCENE FILE, SHOWN HERE.
	#
	# Both this and the player HUD are CanvasLayers, so the 2D editor draws them
	# over the map at a fixed screen position that does not scale with zoom -
	# which makes laying tiles at 30% zoom impossible. They are saved with
	# visible = false so the editor shows the world, and turned on here the
	# moment they enter the tree at runtime.
	#
	# THIS LINE IS WHAT MAKES THAT SAFE. Hiding them without it means they are
	# hidden in the game too, with no error and nothing in the log - the HUD just
	# is not there. If you ever see that, this is the line that went missing.
	visible = true

	# NEW: connect via code rather than relying on editor-made signal
	# connections (Node > Signals panel) — those don't automatically stay
	# in sync with node renames, which is what caused the confusion here.
	# a code connection always points at whatever function currently has
	# this name, with no separate stored link that can go stale.
	if not %loginbutton.pressed.is_connected(_on_login_button_pressed):
		%loginbutton.pressed.connect(_on_login_button_pressed)
	if not %exitbutton.pressed.is_connected(_on_exit_button_pressed):
		%exitbutton.pressed.connect(_on_exit_button_pressed)

	# A PAGE CANNOT CLOSE ITS OWN TAB. In a browser quit() stops the engine and
	# leaves a frozen picture where the game was, so there is no Exit to offer -
	# and its row and the rule above it go too, or the panel ends in a line
	# over an empty band.
	if WebPage.in_browser():
		_hide_exit_row()
		# The loader in web/shell.html covers the canvas until this screen has
		# drawn once, so the engine's boot splash never shows between the two.
		RenderingServer.frame_post_draw.connect(func() -> void: WebPage.mark_ready(),
			CONNECT_ONE_SHOT)

	# NEW: pressing Enter while either field is focused submits the form,
	# same as clicking Login. LineEdit's text_submitted signal passes the
	# field's text as an argument, which _on_login_button_pressed() doesn't
	# take — the wrapper closures below just discard that argument and
	# call the existing handler exactly as the button already does, rather
	# than changing that function's signature to accommodate this.
	if not %usernamelineedit.text_submitted.is_connected(_on_login_field_submitted):
		%usernamelineedit.text_submitted.connect(_on_login_field_submitted)
	if not %passwordlineedit.text_submitted.is_connected(_on_login_field_submitted):
		%passwordlineedit.text_submitted.connect(_on_login_field_submitted)
	_build_code_box()
	_build_create_account()

	# NEW: the banner follows reachability for as long as this screen is open,
	# not just at startup. If the player leaves the game sitting here and
	# starts the server, the next request that succeeds clears the warning on
	# its own.
	if not Api.connection_changed.is_connected(_on_connection_changed):
		Api.connection_changed.connect(_on_connection_changed)

	# Keep the server's state live for as long as this screen is open, not
	# just at startup — see _start_reconnect_poll().
	_start_reconnect_poll()

	_wire_recovery()
	_wire_email_prompt()

	load_remembered_user()

	# SIGNED OUT FROM THE SERVER'S SIDE - a kick, a ban, or a login that ran
	# out while the game was open. characterhud.gd's heartbeat put the reason
	# here on the way out; show it once and let it go, so a later normal logout
	# does not repeat it.
	#
	# AMBER, not red. A kick or a ban is the door being shut on somebody, not a
	# password they got wrong, and in red this line reads as "your login failed"
	# to the one player who most needs to understand it did not.
	if Api.signout_notice != "":
		_say(Api.signout_notice, SAY_BLOCKED)
		Api.signout_notice = ""

	await _check_connection_and_resume()


func _on_login_field_submitted(_new_text: String) -> void:
	_on_login_button_pressed()


# =============================================================================
# STAFF LOGIN CODE
# =============================================================================
# A staff account with a confirmed address needs a code from its email as well
# as the password (STAFF LOGIN CODES in app.py). The server answers the first
# login with 202 and where the code went; this box appears under the password,
# and the same button sends the login again with the code in it.

# Built here rather than in loginmenu.tscn: a node the scene does not have
# cannot be lost by the editor re-saving it, and most players never see it.
var login_code_box: LineEdit = null
# The account the code box belongs to. A code is for one account, so changing
# the username puts the box away.
var _code_for: String = ""


func _build_code_box() -> void:
	var form: Node = get_node_or_null("%loginform")
	var password: Node = get_node_or_null("%passwordlineedit")
	if form == null or password == null or login_code_box != null:
		return
	login_code_box = LineEdit.new()
	login_code_box.name = "logincode"
	login_code_box.placeholder_text = "6-digit code from your email"
	login_code_box.alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Room for "183 774", as it was copied out of the mail.
	login_code_box.max_length = 7
	login_code_box.visible = false
	form.add_child(login_code_box)
	form.move_child(login_code_box, password.get_index() + 1)
	login_code_box.text_submitted.connect(_on_login_field_submitted)
	var name_box: LineEdit = get_node_or_null("%usernamelineedit")
	if name_box != null:
		name_box.text_changed.connect(func(_text: String) -> void: _put_code_box_away())


func _typed_login_code(username: String) -> String:
	"""What goes in the login's `code`: the box, for the account it was asked
	for, spaces out. "" sends none - which asks the server for a new code."""
	if login_code_box == null or not login_code_box.visible or username != _code_for:
		return ""
	return login_code_box.text.replace(" ", "").strip_edges()


func _show_code_step(username: String, res: Dictionary) -> void:
	"""The server wants the emailed code. 202: one is on its way. 400: the one
	typed was wrong or has run out, and the box stays for another go."""
	if login_code_box == null:
		_build_code_box()
	_code_for = username
	var data: Dictionary = res.get("data", {}) if res.get("data") is Dictionary else {}
	if login_code_box != null:
		login_code_box.visible = true
		if int(res.get("status", 0)) == 202:
			login_code_box.text = ""
		if login_code_box.is_inside_tree():
			login_code_box.grab_focus()
	if int(res.get("status", 0)) == 202:
		var button: Button = get_node_or_null("%loginbutton")
		_say("Staff login: we emailed a code to %s. Type it in and press %s." % [
			str(data.get("sent_to", "your recovery address")),
			button.text if button != null else "the button"], SAY_WORKING)
	else:
		_say(str(data.get("message", res.get("error", "That code is not right."))), SAY_REFUSED)


func _put_code_box_away() -> void:
	_code_for = ""
	if login_code_box != null:
		login_code_box.text = ""
		login_code_box.visible = false


# =============================================================================
# CREATE AN ACCOUNT
# =============================================================================
# The one way an account is made. The same form, with the password asked twice
# and the button saying what it will do - a player can see which of the two
# they are about to press. Built here, like the code box, so the scene file does
# not have to change and an editor re-save cannot lose it.
#
# TWICE, because a new account's password has never been typed before: one
# slip on the first go and nobody - the player included - knows what it is.

const CREATE_LINK_TEXT := "Create an account"
const SIGN_IN_LINK_TEXT := "Have an account? Sign in"
const CREATE_BUTTON_TEXT := "Create account"

var create_link: Button = null
var confirm_box: LineEdit = null
var _creating: bool = false
# What the scene calls the sign-in button, so leaving create mode puts it back.
var _sign_in_text: String = ""
# The last "no answer" line said under the button - see _on_connection_changed().
var _no_answer_line: String = ""


func _build_create_account() -> void:
	var form: Node = get_node_or_null("%loginform")
	var password: Node = get_node_or_null("%passwordlineedit")
	if form == null or password == null or confirm_box != null:
		return
	confirm_box = LineEdit.new()
	confirm_box.name = "confirmpassword"
	confirm_box.placeholder_text = "Password again"
	confirm_box.alignment = HORIZONTAL_ALIGNMENT_CENTER
	confirm_box.secret = true
	confirm_box.visible = false
	form.add_child(confirm_box)
	form.move_child(confirm_box, password.get_index() + 1)
	confirm_box.text_submitted.connect(_on_login_field_submitted)

	# Under "Forgot password?", dressed the same: a small flat link.
	create_link = Button.new()
	create_link.name = "createlink"
	create_link.flat = true
	create_link.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	create_link.add_theme_font_size_override("font_size", 12)
	create_link.text = CREATE_LINK_TEXT
	var anchor: Node = get_node_or_null("%recoverlinkbutton")
	form.add_child(create_link)
	if anchor != null:
		form.move_child(create_link, anchor.get_index() + 1)
	create_link.pressed.connect(func() -> void: _set_creating(not _creating))

	var button: Button = get_node_or_null("%loginbutton")
	_sign_in_text = button.text if button != null else "Sign in"


func _set_creating(on: bool) -> void:
	"""Between signing in and making an account. What was typed stays; what was
	said about the other form goes."""
	_creating = on
	_put_code_box_away()
	if confirm_box != null:
		confirm_box.text = ""
		confirm_box.visible = on
	if create_link != null:
		create_link.text = SIGN_IN_LINK_TEXT if on else CREATE_LINK_TEXT
	var button: Button = get_node_or_null("%loginbutton")
	if button != null:
		button.text = CREATE_BUTTON_TEXT if on else _sign_in_text
	var forgot: Control = get_node_or_null("%recoverlinkbutton")
	if forgot != null:
		forgot.visible = not on
	_say("Choose a name and a password - you will type the password twice." if on else "",
		SAY_WORKING)
	var name_box: LineEdit = get_node_or_null("%usernamelineedit")
	if name_box != null and name_box.is_inside_tree():
		name_box.grab_focus()


func _create_account(username: String, password: String) -> void:
	var again: String = Api.clean_password(confirm_box.text) if confirm_box != null else password
	if again != password:
		_say("The two passwords are not the same. Type them again.", SAY_REFUSED)
		return

	_say("Creating your account...", SAY_WORKING)
	_set_busy(true)
	var created: Dictionary = await Api.register(username, password)
	_set_busy(false)

	if created.ok:
		_set_creating(false)
		_welcome(username)
		await _enter_game(username, password)
		if not CharacterData.load_failed:
			_say("", SAY_WORKING)
		return

	# HERE, AND ONLY HERE, "TAKEN" IS THE RIGHT WORD. This is a sign-up form,
	# so a 409 is the name somebody already has - possibly the player, who
	# meant to sign in. Names are not case-sensitive, so "tunacan" is taken
	# when "Tunacan" exists.
	if created.status == 409:
		_say("That name is taken. Pick another - or, if it is yours, go back and sign in.",
			SAY_REFUSED)
		return
	var line: String = describe_login_refusal(created)
	_say(line, _refusal_colour(created))
	if int(created.get("status", 0)) == 0:
		_no_answer_line = line


func _on_connection_changed(online: bool) -> void:
	# The banner tracks the SERVER's state from open to close: green the moment
	# it answers, amber while it is unreachable. It is a separate line from
	# %errorlabel by design — that one carries login progress and validation
	# ("Incorrect password"), which are about the account, not about whether the
	# server is there. The two answer different questions and never contradict.
	if online:
		_set_status(Api.describe_online(), STATUS_ONLINE)
		# AND THE LINE THAT SAID IT WAS NOT. A login pressed while the server was
		# down left "Can't reach the server" under the button, and it stayed
		# there under a green "Server online" banner until the next press - two
		# lines on one panel saying opposite things.
		var said: Label = get_node_or_null("%errorlabel") as Label
		if said != null and _no_answer_line != "" and said.text == _no_answer_line:
			_say("", SAY_WORKING)
		_no_answer_line = ""
	else:
		_set_status(Api.describe_offline(), STATUS_OFFLINE)


# =============================================================================
# LIVE RECONNECT
# =============================================================================

func _start_reconnect_poll() -> void:
	# A repeating, low-cost re-check so the server's state stays live for as long
	# as this screen is open. connection_changed already drives the banner; the
	# one thing missing on an idle login screen is anything that makes a request
	# when nobody is clicking. Without this the amber "no connection" line is
	# frozen the instant it appears — the player can start app.py and the screen
	# never notices until they try to log in and make a request by hand. This is
	# what turns "start the server, then restart the game" into "start the
	# server, wait a moment".
	#
	# The timer is a child of this screen, so it is freed with it: the poll
	# stops on its own the moment login succeeds and the scene changes.
	if has_node("ReconnectPoll"):
		return
	var timer := Timer.new()
	timer.name = "ReconnectPoll"
	timer.wait_time = RECONNECT_POLL_SECONDS
	timer.one_shot = false
	timer.autostart = true
	timer.timeout.connect(_on_reconnect_poll_timeout)
	add_child(timer)


func _on_reconnect_poll_timeout() -> void:
	# Skip while the player's own login request is in flight — that request is
	# already keeping reachability current, and a probe on top of it would only
	# race to report the same thing. Skip while a previous probe is still
	# waiting out its own timeout too, so a dead server can never stack requests.
	if _request_in_flight or _reconnect_probe_in_flight:
		return

	_reconnect_probe_in_flight = true
	# The result is deliberately discarded. get_json() updates reachability in
	# api.gd as a side effect (_set_online), and THAT fires connection_changed on
	# any change — the signal, not this return value, is what moves the banner.
	# This call exists only to make the request happen. PROBE_TIMEOUT, not the
	# full budget: nobody is watching this one.
	await Api.get_json("/api/auth/session", Api.PROBE_TIMEOUT)
	_reconnect_probe_in_flight = false


# =============================================================================
# RECOVERY  -  "I forgot my password"
# =============================================================================
#
# The whole flow lives on this screen: ask for a code by email, type the six
# digits in, choose a new password. There is no web page to bounce through and
# nothing to hand off to a browser.
#
# WHAT THIS CODE DOES NOT DO IS DECIDE ANYTHING. The tick below turns green when
# the code LOOKS like a code - six digits - and that is all it means. Whether it
# IS the code is the server's call, and a wrong one costs one of five tries. A
# client that claimed to validate the code would either be lying or would be a
# way to guess it for free.

func _wire_recovery() -> void:
	# One table rather than five near-identical ifs, so a sixth control is a row
	# instead of another paragraph.
	var wiring := [
		[recover_link_button, _on_recover_link_pressed],
		[recover_back_button, _on_recover_back_pressed],
		[recover_send_button, _on_recover_send_pressed],
		[recover_submit_button, _on_recover_submit_pressed],
	]
	for pair in wiring:
		var button: Button = pair[0]
		var handler: Callable = pair[1]
		if button != null and not button.pressed.is_connected(handler):
			button.pressed.connect(handler)

	if recover_code != null:
		if not recover_code.text_changed.is_connected(_on_recover_code_changed):
			recover_code.text_changed.connect(_on_recover_code_changed)

	_show_recovery(false)


func _show_recovery(on: bool) -> void:
	if recover_form == null:
		return
	recover_form.visible = on
	if login_form != null:
		login_form.visible = not on
	if on:
		_recover_say("", STATUS_WORKING)
		if recover_code != null:
			recover_code.text = ""
		if recover_new_password != null:
			recover_new_password.text = ""
		if recover_confirm_password != null:
			recover_confirm_password.text = ""
		_on_recover_code_changed("")


func _recover_say(message: String, color: Color) -> void:
	if recover_status == null:
		return
	recover_status.text = message
	recover_status.add_theme_color_override("font_color", color)


func _on_recover_link_pressed() -> void:
	_show_recovery(true)


func _on_recover_back_pressed() -> void:
	_show_recovery(false)


func _on_recover_code_changed(new_text: String) -> void:
	# THE GREEN LIGHT. Format only - see this section's header.
	var digits: String = new_text.strip_edges()
	var looks_right: bool = digits.length() == RECOVER_CODE_LENGTH and digits.is_valid_int()
	if recover_code_light != null:
		recover_code_light.text = "OK" if looks_right else ""
	if recover_submit_button != null:
		recover_submit_button.disabled = not looks_right


func _on_recover_send_pressed() -> void:
	var address: String = "" if recover_email == null else recover_email.text.strip_edges()
	if address == "":
		_recover_say("Type the email address on your account.", STATUS_OFFLINE)
		return

	if recover_send_button != null:
		recover_send_button.disabled = true
	var res: Dictionary = await Api.post("/api/auth/recover", {"email": address})
	if recover_send_button != null:
		recover_send_button.disabled = false

	if int(res.get("status", 0)) == 0:
		_recover_say(Api.describe_offline(), STATUS_OFFLINE)
		return
	if int(res.get("status", 0)) == 429:
		_recover_say(str(res.get("error", "Too many requests. Try again later.")), STATUS_OFFLINE)
		return

	# THE SAME SENTENCE WHETHER OR NOT THE ADDRESS EXISTS, because the server
	# answers the same way on purpose - it will not say which addresses have
	# accounts, and a client that rephrased the answer would give that away on
	# the server's behalf.
	var data = res.get("data", {})
	var line: String = "If that address is on an account, a code is on its way."
	if data is Dictionary and str(data.get("message", "")) != "":
		line = str(data.get("message"))
	_recover_say(line, STATUS_WORKING)


func _on_recover_submit_pressed() -> void:
	var address: String = "" if recover_email == null else recover_email.text.strip_edges()
	var code: String = "" if recover_code == null else recover_code.text.strip_edges()
	var new_password: String = "" if recover_new_password == null else Api.clean_password(recover_new_password.text)
	var confirm: String = "" if recover_confirm_password == null else Api.clean_password(recover_confirm_password.text)

	if address == "":
		_recover_say("Type the email address on your account.", STATUS_OFFLINE)
		return
	if new_password != confirm:
		_recover_say("Those two passwords do not match.", STATUS_OFFLINE)
		return
	if new_password.length() < MIN_PASSWORD_LENGTH:
		_recover_say("Password must be at least %d characters." % MIN_PASSWORD_LENGTH, STATUS_OFFLINE)
		return

	if recover_submit_button != null:
		recover_submit_button.disabled = true
	var res: Dictionary = await Api.post("/api/auth/reset", {
		"email": address, "code": code, "new_password": new_password,
	})
	if recover_submit_button != null:
		recover_submit_button.disabled = false

	if not res.get("ok", false):
		if int(res.get("status", 0)) == 0:
			_recover_say(Api.describe_offline(), STATUS_OFFLINE)
		else:
			_recover_say(str(res.get("error", "That code is wrong or has expired.")), STATUS_OFFLINE)
		return

	# Back to the sign-in form with the good news on it. The new password is
	# deliberately NOT used to log in automatically: every session on the
	# account was just destroyed, which is the point of recovering it, and
	# signing straight back in would be a strange thing to do silently.
	_show_recovery(false)
	_set_status("Password updated - sign in with your new password.", STATUS_GOOD)
	if %passwordlineedit != null:
		%passwordlineedit.text = ""


# =============================================================================
# RECOVERY ADDRESS PROMPT
# =============================================================================
#
# Every account gets asked for one, once, on the way in. The server answers
# `needs_email` on login, register and every heartbeat, and keeps answering
# true until an address has been CONFIRMED by a code sent to it - so an
# existing account picks one up the next time its owner signs in, and a typo
# does not count.
#
# IT IS A PROMPT, NOT A PERMISSION. The server refuses nothing over this, and
# the player can say "Not now" (see below): the only person it protects is the
# player being asked, and an account with no address is one nobody can recover
# - which is theirs to decide, not ours to hold them at the door over. A server
# with no mail set up does not ask at all (needs_recovery_email() in app.py).

func _wire_email_prompt() -> void:
	if email_send_button != null:
		if not email_send_button.pressed.is_connected(_on_email_send_pressed):
			email_send_button.pressed.connect(_on_email_send_pressed)
	if email_confirm_button != null:
		if not email_confirm_button.pressed.is_connected(_on_email_confirm_pressed):
			email_confirm_button.pressed.connect(_on_email_confirm_pressed)
	if email_code != null:
		if not email_code.text_changed.is_connected(_on_email_code_changed):
			email_code.text_changed.connect(_on_email_code_changed)

	if email_form != null:
		email_form.visible = false
		_build_email_later()


# "NOT NOW". The prompt had no way past it but a code arriving, and a code
# depends on a mail server this screen cannot see: a slow inbox, a spam folder,
# a sending limit reached on launch day, and a new player sat at a form with
# only Exit to press. The address matters - it is the only way back into an
# account - so the prompt still comes at every typed sign-in until one is
# confirmed, and Options has the same form. It just no longer holds the door.
const EMAIL_LATER_TEXT := "Not now - add one later in Options"
var email_later_button: Button = null


func _build_email_later() -> void:
	if email_form == null or email_later_button != null:
		return
	email_later_button = Button.new()
	email_later_button.name = "emaillaterbutton"
	email_later_button.flat = true
	email_later_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	email_later_button.add_theme_font_size_override("font_size", 12)
	email_later_button.text = EMAIL_LATER_TEXT
	email_form.add_child(email_later_button)
	if email_confirm_button != null and email_confirm_button.get_parent() == email_form:
		email_form.move_child(email_later_button, email_confirm_button.get_index() + 1)
	email_later_button.pressed.connect(_on_email_later_pressed)


func _on_email_later_pressed() -> void:
	# The password was held only for the address; it goes now either way.
	_password_for_email = ""
	if email_form != null:
		email_form.visible = false
	_email_say("", STATUS_WORKING)
	await _complete_login(_pending_username)


func _show_email_prompt(username: String, password: String) -> void:
	_pending_username = username
	_password_for_email = password

	if email_form == null:
		# An older scene without the prompt must not strand anybody at a blank
		# screen - go on into the game and leave the account without an address.
		await _complete_login(username)
		return

	if login_form != null:
		login_form.visible = false
	if recover_form != null:
		recover_form.visible = false
	email_form.visible = true

	_set_status("", STATUS_WORKING)
	_email_say("", STATUS_WORKING)
	if email_code != null:
		email_code.text = ""
	_on_email_code_changed("")


func _email_say(message: String, color: Color) -> void:
	if email_status == null:
		return
	email_status.text = message
	email_status.add_theme_color_override("font_color", color)


func _on_email_code_changed(new_text: String) -> void:
	var digits: String = new_text.strip_edges()
	var looks_right: bool = digits.length() == RECOVER_CODE_LENGTH and digits.is_valid_int()
	if email_code_light != null:
		email_code_light.text = "OK" if looks_right else ""
	if email_confirm_button != null:
		email_confirm_button.disabled = not looks_right


func _on_email_send_pressed() -> void:
	var address: String = "" if email_address == null else email_address.text.strip_edges()
	if address == "":
		_email_say("Type an email address first.", STATUS_OFFLINE)
		return

	if email_send_button != null:
		email_send_button.disabled = true
	var res: Dictionary = await Api.post("/api/account/email", {
		"email": address, "password": _password_for_email,
	})
	if email_send_button != null:
		email_send_button.disabled = false

	if not res.get("ok", false):
		if int(res.get("status", 0)) == 0:
			_email_say(Api.describe_offline(), STATUS_OFFLINE)
		else:
			_email_say(str(res.get("error", "That address was not accepted.")), STATUS_OFFLINE)
		return

	_email_say("Code sent. Check that inbox, then type the six digits above.", STATUS_WORKING)


func _on_email_confirm_pressed() -> void:
	var code: String = "" if email_code == null else email_code.text.strip_edges()

	if email_confirm_button != null:
		email_confirm_button.disabled = true
	var res: Dictionary = await Api.post("/api/account/email/verify", {"code": code})
	if email_confirm_button != null:
		email_confirm_button.disabled = false

	if not res.get("ok", false):
		if int(res.get("status", 0)) == 0:
			_email_say(Api.describe_offline(), STATUS_OFFLINE)
		else:
			_email_say(str(res.get("error", "That code is wrong or has expired.")), STATUS_OFFLINE)
		return

	# Confirmed. Drop the password we were holding for this and carry on into
	# the game exactly where the sign-in left off.
	Api.needs_email = false
	_password_for_email = ""
	if email_form != null:
		email_form.visible = false
	_email_say("", STATUS_WORKING)
	_set_status("Recovery address confirmed.", STATUS_GOOD)

	await _complete_login(_pending_username)


# =============================================================================
# AUTO-LOGIN
# =============================================================================

func _check_connection_and_resume() -> void:
	# Runs once on open. One request answers both questions: is the server
	# there, and is a cached token still good?
	#
	# FIXED — THE TYPING DELAY. This used to call _set_busy(true), which sets
	# `editable = false` on BOTH text fields, and then waited on a request
	# with the normal ten-second budget. With the server down, the first ten
	# seconds after the login screen appeared were spent with the username and
	# password boxes silently refusing input. They looked completely normal —
	# the caret sat in the field, the player typed, and nothing came out.
	#
	# Two things were wrong and both are fixed:
	#   1. The fields are no longer locked. _set_busy's second argument leaves
	#      them editable; only the submit button is disabled, which is all the
	#      double-click guard ever actually needed here.
	#   2. The probe now uses Api.PROBE_TIMEOUT (3s) instead of TIMEOUT (10s),
	#      because nobody asked for this request and nobody is watching it.
	#
	# This ran even with no cached token, because _log_server_reachability()
	# in api.gd was firing its own copy at the same time — so the delay showed
	# up on a fresh install too, with nothing to resume.
	_set_status("Checking server...", STATUS_WORKING)
	_set_busy(true, false)

	var probe: Dictionary = await Api.probe_and_resume()

	_set_busy(false)

	if not probe.get("online", false):
		_set_status(Api.describe_offline(), STATUS_OFFLINE)
		return

	_set_status(Api.describe_online(), STATUS_ONLINE)

	# THE BUILD, now that /api/status has been asked. Amber when this build will
	# be turned away, grey when there is simply something newer; nothing at all
	# when it is current. A notice the server already gave (a kick, a ban, a
	# refused build) is not written over.
	var build_note: String = Api.build_notice()
	var said: Label = get_node_or_null("%errorlabel") as Label
	if build_note != "" and (said == null or said.text == ""):
		_say(build_note, SAY_BLOCKED if Api.build_is_refused() else SAY_WORKING)

	if not probe.get("resumed", false):
		# Either there was no cached token, or the server rejected it. Neither
		# is worth a message — the form is right there.
		return

	# A valid session came back. But DON'T steal the screen from someone who
	# has already started typing: a player entering a password is telling us
	# they want a specific account, quite possibly not the remembered one.
	# Jumping to character select mid-keystroke would be the single most
	# jarring thing this screen could do.
	if %passwordlineedit.text != "":
		return

	# A RESUMED SESSION GOES IN, EVEN OWING AN ADDRESS. The prompt needs the
	# password (POST /api/account/email will not take a token instead - that is
	# what stops a stolen session redirecting recovery), and a resumed login
	# has none to offer. It used to stop here and ask for a typed sign-in every
	# time, which made "Remember me" do nothing for anyone who had pressed "Not
	# now" on the prompt. The prompt comes back at the next typed sign-in, and
	# Options has the same form.
	await _complete_login(Api.username)


# =============================================================================
# LOGIN / REGISTER
# =============================================================================

func _enter_game(username: String, password: String) -> void:
	# ONE DOOR INTO THE WORLD, so the recovery-address prompt cannot be skipped
	# by whichever of the sign-in paths somebody forgot to change. Both the
	# login and the register branch come through here.
	if Api.needs_email:
		await _show_email_prompt(username, password)
		return
	await _complete_login(username)


func _on_login_button_pressed() -> void:
	if _request_in_flight:
		return

	# SIGNED IN, BUT THE CHARACTERS DID NOT LOAD: the button tries the load
	# again rather than the login. Logging in a second time would work too,
	# but it would send a staff member another code and end the session this
	# screen already has. Only for the same name - a player who typed another
	# one wants that account.
	if _retry_load and Api.is_logged_in() \
			and %usernamelineedit.text.strip_edges().to_lower() == Api.username.to_lower():
		_retry_load = false
		_say("Loading your characters...", SAY_WORKING)
		_set_busy(true)
		await _complete_login(Api.username)
		_set_busy(false)
		return
	_retry_load = false

	var username: String = %usernamelineedit.text.strip_edges()
	var password: String = Api.clean_password(%passwordlineedit.text)

	# --- input validation (courtesy only — the server validates too) ---
	if username.is_empty() or password.is_empty():
		_say("Please fill in both fields.", SAY_REFUSED)
		return
	if not is_valid_username(username):
		_say("Username: letters, numbers, and _ only.", SAY_REFUSED)
		return
	if password.length() < MIN_PASSWORD_LENGTH:
		_say("Password must be at least %d characters." % MIN_PASSWORD_LENGTH, SAY_REFUSED)
		return

	# --- remember me: the name in the box, and staying signed in ---
	# Both or neither. See Api.keep_signed_in: with the box clear, closing the
	# game signs you out, and nothing on this computer opens your account.
	if %rememberme.button_pressed:
		save_remembered_user(username)
	else:
		save_remembered_user("")
	Api.keep_signed_in = %rememberme.button_pressed

	if _creating:
		await _create_account(username, password)
		return

	_say("Connecting...", SAY_WORKING)
	_set_busy(true)

	# --- try to log in first ---
	var res: Dictionary = await Api.login(username, password, _typed_login_code(username))

	# BEFORE res.ok, because the first step is a 202 - a 2xx with no token -
	# and BEFORE the 401 branch below: a wrong code is a 400 on purpose, since a
	# 401 here reads "Wrong name or password", and the password was right.
	if Api.needs_login_code(res):
		_set_busy(false)
		_show_code_step(username, res)
		return

	if res.ok:
		_put_code_box_away()
		_welcome(username)
		await _enter_game(username, password)
		_set_busy(false)
		# Not over the line saying the characters did not load - see
		# _complete_login().
		if not CharacterData.load_failed:
			_say("", SAY_WORKING)
		return

	# A 401 IS "WRONG NAME OR PASSWORD", AND THAT IS ALL IT IS. The server will
	# not say which - so the endpoint cannot be used to find out who plays - and
	# this screen no longer tries to find out by registering the name. That
	# guess is what turned a typo in your own name into a new, empty account.
	# The hint is for the new player who pressed the big button first.
	_set_busy(false)
	if res.status == 401:
		_say("Wrong name or password. New here? Choose \"%s\"." % CREATE_LINK_TEXT, SAY_REFUSED)
		return

	# anything else — server down, validation rejection, unexpected status
	var line: String = describe_login_refusal(res)
	_say(line, _refusal_colour(res))
	if int(res.get("status", 0)) == 0:
		_no_answer_line = line


# COROUTINE — callers must await. CharacterData.load_for_user() fetches every
# character from the server now, so this no longer returns before the data
# exists. Navigating to character select without awaiting would show four empty
# slots to a player who has four characters.
func _complete_login(typed_username: String) -> void:
	# NEW: load THIS user's own character data FIRST — character select
	# depends on it already being loaded.
	# see CharacterData.load_for_user()'s comment for why this matters.
	#
	# CHANGED: loads under the server's spelling of the name, not the one
	# that was typed into the box. THIS IS NOT COSMETIC — it is the whole
	# reason a save can appear to vanish:
	#
	#   - app.py declares `username TEXT ... UNIQUE COLLATE NOCASE`, so the
	#     login query `WHERE username = ?` matches case-INSENSITIVELY.
	#     typing "tunacan" successfully logs you into the account stored as
	#     "Tunacan". the server is right to do this; people don't remember
	#     capitalisation.
	#   - but CharacterData._save_path_for_user() builds a FILENAME from the
	#     name, and filenames keep their case: "Tunacan" is
	#     character_Tunacan.save, "tunacan" is character_tunacan.save.
	#
	# so logging in with different capitalisation than you registered with
	# used to hand you a real, authenticated session pointed at a save file
	# that had never existed — every character gone, nothing actually lost,
	# and no error anywhere to explain it. worse, creating a character then
	# WOULD write that second file, quietly splitting one account's saves
	# across two.
	#
	# the login response returns row["username"] — the canonical stored
	# spelling — and Api.username holds it. that is the authority. the typed
	# string is only a fallback for the case where the server somehow
	# didn't send one back.
	var canonical_username: String = typed_username
	if Api.username != "":
		canonical_username = Api.username

	# await, because load_for_user() now fetches every character from the server
	# instead of reading a local file. Without it, character select would open
	# against empty slots and the data would arrive after the screen had already
	# decided there were no characters.
	await CharacterData.load_for_user(canonical_username)
	# A LOAD THAT DID NOT ARRIVE IS NOT FOUR EMPTY SLOTS. Going on to character
	# select from here showed exactly that, and "Create" over a slot the server
	# still held pushed an empty backpack over the real one. Stay, say so, and
	# let the button try again.
	if CharacterData.load_failed:
		_show_load_failed()
		return
	_go_to_character_select()


# Set when the characters did not load; the next press retries the load.
var _retry_load: bool = false
const LOAD_FAILED_TEXT := "Your characters did not load - the server did not answer. Press %s to try again."


func _show_load_failed() -> void:
	_retry_load = true
	if email_form != null:
		email_form.visible = false
	if recover_form != null:
		recover_form.visible = false
	if login_form != null:
		login_form.visible = true
	var box: LineEdit = get_node_or_null("%usernamelineedit")
	if box != null and box.text.strip_edges() == "":
		box.text = Api.username
	var button: Button = get_node_or_null("%loginbutton")
	_say(LOAD_FAILED_TEXT % ("\"%s\"" % button.text if button != null else "the button"), SAY_BLOCKED)


func _go_to_character_select() -> void:
	if char_select_scene == null:
		push_warning("LoginMenu: char_select_scene not assigned in the Inspector — cannot continue")
		return
	get_tree().change_scene_to_packed(char_select_scene)


func _set_busy(busy: bool, lock_fields: bool = true) -> void:
	# Disables the form while a request is in flight, so a double-click can't
	# fire two submissions.
	#
	# lock_fields distinguishes the two kinds of wait this screen has, which
	# were previously treated as one:
	#
	#   SUBMIT (lock_fields = true) — the player pressed Login and is watching.
	#     Freezing the fields is correct: editing the username while it is
	#     being checked would leave the box disagreeing with the request.
	#
	#   BACKGROUND (lock_fields = false) — the startup probe. The player never
	#     asked for it and has no idea it is happening. Locking the fields here
	#     is what made the screen swallow keystrokes with the server down.
	#
	# The button is disabled either way; that is what the double-submit guard
	# actually requires.
	_request_in_flight = busy
	%loginbutton.disabled = busy
	if create_link != null:
		create_link.disabled = busy
	if lock_fields:
		%usernamelineedit.editable = not busy
		%passwordlineedit.editable = not busy
		if confirm_box != null:
			confirm_box.editable = not busy
	elif not busy:
		# Releasing a background wait must never leave a field disabled, even
		# if a submit locked them in the meantime.
		%usernamelineedit.editable = true
		%passwordlineedit.editable = true
		if confirm_box != null:
			confirm_box.editable = true


func _say(message: String, color: Color) -> void:
	# THE ONE WAY %errorlabel IS WRITTEN. Same shape as _recover_say() and
	# _email_say() beside it, so all four lines on this screen state their colour
	# at the call site and none of them inherit the last state's.
	#
	# Guarded like _set_status, for the same reason: an older copy of
	# loginmenu.tscn without the node keeps working rather than crashing on a
	# missing unique name. A login screen that cannot say why is bad; one that
	# cannot open is worse.
	var label: Label = get_node_or_null("%errorlabel")
	if label == null:
		return
	label.text = message
	label.add_theme_color_override("font_color", color)


func _welcome(typed_username: String) -> void:
	# THE SERVER'S SPELLING, not the one that was typed. `username TEXT UNIQUE
	# COLLATE NOCASE` means logging in as "tunacan" gets you into the account
	# stored as "Tunacan", and the login response carries row["username"] back.
	# Greeting somebody by the capitalisation they typed rather than the one their
	# account actually has is a small lie, and it is the same lie that used to
	# point a real session at a save file that had never existed - see
	# _complete_login(). If the server sent nothing, fall back to the typed name.
	var who: String = typed_username
	if Api.username != "":
		who = Api.username
	_say("Welcome, %s" % who, SAY_GOOD)


func _refusal_colour(res: Dictionary) -> Color:
	# WHICH REFUSALS ARE NOT ABOUT THE PASSWORD. 403 is a ban or a blocked
	# connection, 429 is a throttle, 503 is the server closing - none of them get
	# better by retyping anything, so none of them are dressed as a typo.
	#
	# Everything else is red: 401, the 400s the server rejects a bad username or
	# a short password with, and status 0, which is api.gd's "no answer at all".
	# Status 0 is deliberately NOT amber, because the connection banner is
	# already amber and already saying the server is unreachable - two amber
	# lines saying the same thing is one of them repeating itself.
	var status: int = int(res.get("status", 0))
	if status == 403 or status == 429 or status == 503:
		return SAY_BLOCKED
	return SAY_REFUSED


func _set_status(message: String, color: Color) -> void:
	# The connection banner, separate from %errorlabel. Guarded with
	# has_node so an older copy of loginmenu.tscn without the node keeps
	# working instead of crashing on a missing unique name.
	if not has_node("%statuslabel"):
		return
	var label: Label = $"%statuslabel"
	label.text = message
	label.add_theme_color_override("font_color", color)
	label.visible = message != ""


func _on_exit_button_pressed() -> void:
	get_tree().quit()


func _hide_exit_row() -> void:
	var row: Node = %exitbutton.get_parent()
	for node in [row, get_node_or_null("centercontainer/mainpanel/margincontainer/vboxcontainer/hseparator2")]:
		if node is CanvasItem:
			node.visible = false


# =============================================================================
# VALIDATION
# =============================================================================

static func describe_login_refusal(res: Dictionary) -> String:
	# A BAN SAYS HOW LONG AND WHY. The server has always sent both with its
	# 403 - `ban` carries permanent, expires_at and the reason staff typed -
	# and this screen showed only "This account is banned until further
	# notice", which for a seven-day ban is not even true.
	var data: Variant = res.get("data", {})
	if int(res.get("status", 0)) == 403 and data is Dictionary and data.get("ban") is Dictionary:
		var ban: Dictionary = data["ban"]
		var line: String = "This account is banned permanently."
		if not bool(ban.get("permanent", false)):
			# LOCAL TIME, to the minute. The server's clock is unix time and
			# get_datetime_string_from_unix_time() reads it as UTC, which for
			# most players is a date that is off by hours. LocalTime.full() is
			# the one place that conversion lives now - there were four copies
			# of it and one of them had lost the offset entirely.
			line = "This account is banned until %s." % \
				LocalTime.full(int(ban.get("expires_at", 0)))

			# AND HOW LONG THAT IS, because a date is a fact and a duration is
			# the answer to the question actually being asked. "Until Fri 3 Oct
			# 14:22" makes somebody count on their fingers; "2 days, 4 hours"
			# does not.
			#
			# COMPUTED ONCE, NOT TICKING, and that is deliberate rather than
			# lazy. A ticking clock earns its keep when the number is about to
			# matter - the connection countdown in the HUD is ninety seconds and
			# every one of them counts. A ban is measured in days, nobody sits
			# watching it, and a second-by-second redraw on the login screen
			# would be work spent on a number that changes meaningfully once an
			# hour.
			var left: int = int(ban.get("expires_at", 0)) - int(Time.get_unix_time_from_system())
			var remaining: String = describe_ban_remaining(left)
			if remaining != "":
				line += "  (%s left)" % remaining
		var reason: String = str(ban.get("reason", ""))
		if reason != "":
			line += "\nReason: %s" % reason
		return line
	return str(res.get("error", ""))


static func describe_ban_remaining(seconds: int) -> String:
	"""How much of a ban is left, in the largest two units that say something.

	Static and pure so the suite can check it without a server or a ban: hand it
	a number of seconds, read the sentence.

	EMPTY WHEN IT HAS RUN OUT, rather than "0 minutes". A ban whose clock has
	passed but whose row the server has not cleared yet is not something to
	announce a countdown for - the next login attempt will simply succeed.
	"""
	if seconds <= 0:
		return ""

	# Each remainder is handed to the next line, so every discarded fraction is
	# accounted for by the unit below it - the truncation is the arithmetic, not
	# a slip. Said out loud with the annotation, as chatpanel.gd does.
	@warning_ignore("integer_division")
	var days: int = seconds / 86400
	@warning_ignore("integer_division")
	var hours: int = (seconds % 86400) / 3600
	@warning_ignore("integer_division")
	var minutes: int = (seconds % 3600) / 60

	if days > 0:
		if hours > 0:
			return "%d day%s, %d hour%s" % [days, "" if days == 1 else "s",
				hours, "" if hours == 1 else "s"]
		return "%d day%s" % [days, "" if days == 1 else "s"]
	if hours > 0:
		if minutes > 0:
			return "%d hour%s, %d minute%s" % [hours, "" if hours == 1 else "s",
				minutes, "" if minutes == 1 else "s"]
		return "%d hour%s" % [hours, "" if hours == 1 else "s"]
	# UNDER AN HOUR, rounded UP to the next minute. Telling somebody "0 minutes"
	# when there are forty seconds left is the one version of this that is wrong.
	return "%d minute%s" % [maxi(1, int(ceil(float(minutes + 1)))),
		"" if minutes == 0 else "s"]


func is_valid_username(input_str: String) -> bool:
	# mirrors USERNAME_PATTERN in app.py.
	var regex := RegEx.new()
	regex.compile("^[a-zA-Z0-9_]{3,20}$")
	return regex.search(input_str) != null


# =============================================================================
# REMEMBER ME (username only — see class comment re: why not password too)
# =============================================================================

func save_remembered_user(username: String) -> void:
	var config := ConfigFile.new()
	config.set_value("login", "remembered_username", username)
	config.save("user://remembered_user.cfg")


func load_remembered_user() -> void:
	var config := ConfigFile.new()
	var err := config.load("user://remembered_user.cfg")
	if err == OK:
		var remembered_user: String = config.get_value("login", "remembered_username", "")
		%usernamelineedit.text = remembered_user
		# CHANGED: was %rememberme.pressed, which reads the SIGNAL object
		# (always truthy) rather than the checkbox's actual toggle state —
		# meaning "remember me" was very likely always behaving as checked
		# regardless of the real box state. .button_pressed is the correct
		# property for current toggle state.
		%rememberme.button_pressed = remembered_user != ""
