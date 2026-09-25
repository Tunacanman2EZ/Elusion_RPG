# optionsscreen.gd — the options panel, opened from the HUD's Options button
# or by pressing Escape with nothing else open.
# attached to res://scene/ui/menus/optionsscreen.tscn.
#
# =============================================================================
# THE PANEL IS A VIEW OF Settings, WHICH IS THE ONE THAT DECIDES ANYTHING
# =============================================================================
# Nothing here stores a preference, applies one, or writes a file. Every
# control does the same two things: read its value out of Settings when the
# panel opens, and hand a new one back when the player moves it. Settings
# coerces it, applies it, saves it and says so.
#
# That is why there is no OK or Cancel. A slider that only takes effect when
# you press a button is a slider you have to audition twice — once by ear and
# once by memory. Everything here is live, and "Reset to defaults" is the undo.
#
# =============================================================================
# WHAT WAS HERE BEFORE
# =============================================================================
# The HUD's Options button has existed the whole time, wired to a handler that
# read, in full:
#
#     func _on_options_pressed() -> void:
#         print("options pressed (not yet implemented)")
#
# and the login screen carried a styled "Settings" button connected to nothing
# at all. That one is gone — a button that has never done anything is worse
# than no button, because a player who presses it concludes the game is broken
# rather than that the feature is absent.
extends Control


# =============================================================================
# SIGNALS
# =============================================================================

signal closed


# =============================================================================
# NODE REFERENCES
# =============================================================================

@onready var close_button:  Button       = get_node_or_null("%optionsclosebutton")
@onready var reset_button:  Button       = get_node_or_null("%optionsresetbutton")

@onready var master_slider: HSlider      = get_node_or_null("%mastervolume")
@onready var music_slider:  HSlider      = get_node_or_null("%musicvolume")
@onready var sfx_slider:    HSlider      = get_node_or_null("%sfxvolume")

@onready var master_value:  Label        = get_node_or_null("%mastervalue")
@onready var music_value:   Label        = get_node_or_null("%musicvalue")
@onready var sfx_value:     Label        = get_node_or_null("%sfxvalue")

@onready var fullscreen_toggle: CheckButton = get_node_or_null("%fullscreentoggle")
@onready var vsync_mode:        OptionButton = get_node_or_null("%vsyncmode")
@onready var frame_cap:         OptionButton = get_node_or_null("%framecap")
@onready var graphics_api:      OptionButton = get_node_or_null("%graphicsapi")
@onready var api_row:           Control      = get_node_or_null("%apirow")
@onready var api_note:          Label        = get_node_or_null("%apinote")
@onready var pacing_readout:    Label        = get_node_or_null("%pacingreadout")
@onready var pacing_hint:       Label        = get_node_or_null("%pacinghint")
@onready var window_size:       OptionButton = get_node_or_null("%windowsize")
@onready var damage_toggle:     CheckButton = get_node_or_null("%damagenumbers")
@onready var camera_zoom:       HSlider      = get_node_or_null("%camerazoom")
@onready var camera_zoom_value: Label        = get_node_or_null("%camerazoomvalue")
@onready var name_hue:          HSlider      = get_node_or_null("%namehue")
@onready var name_swatch:       PanelContainer = get_node_or_null("%namecolourswatch")
@onready var name_preview:      Label        = get_node_or_null("%namecolourpreview")

@onready var render_resolution: OptionButton = get_node_or_null("%renderresolution")
@onready var lighting:          OptionButton = get_node_or_null("%lighting")
@onready var background_limit:  CheckButton  = get_node_or_null("%backgroundlimit")
@onready var renderer:          OptionButton = get_node_or_null("%renderer")
@onready var renderer_note:     Label        = get_node_or_null("%renderernote")

# ACCOUNT. Null-guarded like every other control here, so an older copy of
# optionsscreen.tscn without these still opens and still changes the volume.
@onready var account_email_value:    Label    = get_node_or_null("%accountemailvalue")
@onready var account_email_button:   Button   = get_node_or_null("%accountemailbutton")
@onready var account_password_button: Button  = get_node_or_null("%accountpasswordbutton")
@onready var account_email_form:     Control  = get_node_or_null("%accountemailform")
@onready var account_email_input:    LineEdit = get_node_or_null("%accountemailinput")
@onready var account_email_password: LineEdit = get_node_or_null("%accountemailpassword")
@onready var account_email_send:     Button   = get_node_or_null("%accountemailsend")
@onready var account_email_code:     LineEdit = get_node_or_null("%accountemailcode")
@onready var account_email_verify:   Button   = get_node_or_null("%accountemailverify")
@onready var account_password_form:  Control  = get_node_or_null("%accountpasswordform")
@onready var account_current_password: LineEdit = get_node_or_null("%accountcurrentpassword")
@onready var account_new_password:   LineEdit = get_node_or_null("%accountnewpassword")
@onready var account_confirm_password: LineEdit = get_node_or_null("%accountconfirmpassword")
@onready var account_password_save:  Button   = get_node_or_null("%accountpasswordsave")
@onready var account_status:         Label    = get_node_or_null("%accountstatus")

const ACCOUNT_OK := Color(0.43, 0.84, 0.49)
const ACCOUNT_BAD := Color(0.95, 0.55, 0.45)
const ACCOUNT_PLAIN := Color(0.70, 0.75, 0.82)

# The readout is polled, not signalled: nothing announces that the driver has
# started ignoring vsync. Half a second is fast enough to watch a change take
# effect and slow enough that the number is readable rather than a blur.
const READOUT_SECONDS := 0.5
var _readout_accum: float = 0.0

# Labels for the pickers, in the same order as the constants they mirror.
const VSYNC_LABELS := {
	"off": "Off", "on": "On", "adaptive": "Adaptive", "fast": "Fast (no cap)",
}
const API_LABELS := {"vulkan": "Vulkan", "d3d12": "Direct3D 12"}
const RESOLUTION_LABELS := {"screen": "Full (sharpest)", "low": "1280 x 720 (fastest)"}
const LIGHTING_LABELS := {"full": "Full", "simple": "Simple (fastest)"}
# forward_plus is never offered, but a project could be switched to it by
# hand, and the note should still name what is running.
const RENDERER_LABELS := {
	"mobile": "Standard", "gl_compatibility": "Compatibility", "forward_plus": "Forward+",
}


# =============================================================================
# STATE
# =============================================================================

# True while refresh() is writing values INTO the controls. Every control's
# changed signal fires whether a human moved it or a line of code did, so
# without this, opening the panel would write all eight settings straight back
# to Settings — harmless, but it would save the file on every open and emit a
# `changed` at anything listening.
var _refreshing: bool = false


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	_populate_window_sizes()
	_connect_controls()
	_connect_account()

	# Nothing here runs per frame; this is for the day the options panel is
	# reachable from a paused state. A panel whose sliders stop responding
	# because the tree is paused is a bad way to find that out.
	process_mode = Node.PROCESS_MODE_ALWAYS

	visible = false


func _populate_window_sizes() -> void:
	if window_size == null:
		return
	window_size.clear()
	# `option`, not `size` — this script extends Control, which already has a
	# `size` property, and the loop variable would shadow it.
	#
	# THE MULTIPLIER IS THE POINT, not decoration - it is what tells a player
	# that 2560x1440 is twice the game's own 1280x720 rather than an arbitrary
	# bigger number.
	#
	# IT IS A FLOAT NOW. This used to be whole numbers only, and any size that
	# was not a whole multiple printed with no multiplier at all - because
	# project.godot used integer scaling and a fractional one would have been a
	# lie. It scales fractionally now, so 1920x1080 really is 1.5x and says so.
	var base_height: float = float(ProjectSettings.get_setting(
		"display/window/size/viewport_height", 720))
	for option in Settings.WINDOW_SIZES:
		if base_height <= 0.0:
			window_size.add_item("%d x %d" % [option.x, option.y])
			continue
		var factor: float = float(option.y) / base_height
		# "2x", not "2.00x", when it lands exactly - a whole multiple is worth
		# recognising, because those are the ones with a perfect pixel grid.
		var shown: String = ("%dx" % int(round(factor))) \
			if is_equal_approx(factor, round(factor)) else ("%.2fx" % factor)
		window_size.add_item("%d x %d   (%s)" % [option.x, option.y, shown])


func _connect_controls() -> void:
	# value_changed FIRES CONTINUOUSLY WHILE DRAGGING, which is what makes a
	# volume slider usable at all — you hear the result while your hand is
	# still on it. Settings.set_value() returns early when the value has not
	# actually changed, so a drag that crosses the same step twice does not
	# write the file twice.
	if master_slider != null:
		master_slider.value_changed.connect(_on_master_changed)
	if music_slider != null:
		music_slider.value_changed.connect(_on_music_changed)
	if sfx_slider != null:
		sfx_slider.value_changed.connect(_on_sfx_changed)
	if camera_zoom != null:
		# THE RANGE COMES FROM Settings, not from the .tscn. The scene carries
		# the same numbers so the slider looks right in the editor, but this is
		# what makes them true - one statement of what is allowed, and the
		# clamp in Settings._normalise() agrees with it by construction.
		camera_zoom.min_value = Settings.CAMERA_ZOOM_MIN
		camera_zoom.max_value = Settings.CAMERA_ZOOM_MAX
		camera_zoom.step = Settings.CAMERA_ZOOM_STEP
		camera_zoom.value_changed.connect(_on_camera_zoom_changed)
	if name_hue != null:
		name_hue.min_value = Settings.NAME_HUE_MIN
		name_hue.max_value = Settings.NAME_HUE_MAX
		name_hue.step = Settings.NAME_HUE_STEP
		name_hue.value_changed.connect(_on_name_hue_changed)

	if fullscreen_toggle != null:
		fullscreen_toggle.toggled.connect(_on_fullscreen_toggled)
	if vsync_mode != null:
		vsync_mode.clear()
		for mode_name in Settings.VSYNC_MODES:
			vsync_mode.add_item(VSYNC_LABELS.get(mode_name, mode_name))
		vsync_mode.item_selected.connect(_on_vsync_selected)
	if frame_cap != null:
		frame_cap.clear()
		for cap in Settings.FRAME_CAPS:
			frame_cap.add_item("Unlimited" if int(cap) == 0 else "%d fps" % int(cap))
		frame_cap.item_selected.connect(_on_frame_cap_selected)
	if graphics_api != null:
		graphics_api.clear()
		for api in Settings.GRAPHICS_APIS:
			graphics_api.add_item(API_LABELS.get(api, api))
		graphics_api.item_selected.connect(_on_graphics_api_selected)
	# WINDOWS ONLY. The setting the picker writes is driver.windows, and on any
	# other platform the row would be a control that does nothing - which is
	# this project's least favourite kind of control.
	if api_row != null and OS.get_name() != "Windows":
		api_row.visible = false
	if window_size != null:
		window_size.item_selected.connect(_on_window_size_selected)
	if damage_toggle != null:
		damage_toggle.toggled.connect(_on_damage_numbers_toggled)

	if render_resolution != null:
		render_resolution.clear()
		for choice in Settings.RENDER_RESOLUTIONS:
			render_resolution.add_item(RESOLUTION_LABELS.get(choice, choice))
		render_resolution.item_selected.connect(_on_render_resolution_selected)
	if lighting != null:
		lighting.clear()
		for choice in Settings.LIGHTING_MODES:
			lighting.add_item(LIGHTING_LABELS.get(choice, choice))
		lighting.item_selected.connect(_on_lighting_selected)
	if background_limit != null:
		background_limit.toggled.connect(_on_background_limit_toggled)
	if renderer != null:
		renderer.clear()
		for method in Settings.RENDERERS:
			renderer.add_item(RENDERER_LABELS.get(method, method))
		renderer.item_selected.connect(_on_renderer_selected)

	if close_button != null:
		close_button.pressed.connect(close)
	if reset_button != null:
		reset_button.pressed.connect(_on_reset_pressed)


# =============================================================================
# OPENING AND CLOSING
# =============================================================================

func open() -> void:
	# REFRESHED ON EVERY OPEN, not once in _ready(). Settings can change from
	# somewhere else — a reset, a future keybind screen, a value corrected on
	# load — and a panel showing what was true the first time it was built is
	# how a UI starts lying.
	refresh()
	visible = true


func close() -> void:
	visible = false
	closed.emit()


func refresh() -> void:
	_refreshing = true

	# Asked on every open: the address can change from the login screen too.
	_refresh_account()

	if master_slider != null:
		master_slider.value = float(Settings.get_value("volume_master"))
	if music_slider != null:
		music_slider.value = float(Settings.get_value("volume_music"))
	if sfx_slider != null:
		sfx_slider.value = float(Settings.get_value("volume_sfx"))
	if camera_zoom != null:
		camera_zoom.value = float(Settings.get_value("camera_zoom"))
	if name_hue != null:
		name_hue.value = float(Settings.get_value("name_hue"))
	_update_camera_label()
	_update_name_swatch()

	_update_volume_labels()

	if fullscreen_toggle != null:
		fullscreen_toggle.button_pressed = bool(Settings.get_value("fullscreen"))
	if vsync_mode != null:
		vsync_mode.selected = Settings.VSYNC_MODES.find(str(Settings.get_value("vsync")))
	if frame_cap != null:
		# A cap the list does not offer (a hand-edited 100) selects nothing,
		# for the same reason the window-size picker does below.
		frame_cap.selected = Settings.FRAME_CAPS.find(int(Settings.get_value("frame_cap")))
	if graphics_api != null:
		graphics_api.selected = Settings.GRAPHICS_APIS.find(Settings.graphics_api_requested())
	_update_api_note()
	_update_pacing_readout()
	if damage_toggle != null:
		damage_toggle.button_pressed = bool(Settings.get_value("damage_numbers"))

	if render_resolution != null:
		render_resolution.selected = Settings.RENDER_RESOLUTIONS.find(
			str(Settings.get_value("render_resolution")))
	if lighting != null:
		lighting.selected = Settings.LIGHTING_MODES.find(str(Settings.get_value("lighting")))
	if background_limit != null:
		background_limit.button_pressed = bool(Settings.get_value("background_fps_limit"))
	if renderer != null:
		renderer.selected = Settings.RENDERERS.find(Settings.renderer_requested())
	_update_renderer_note()

	if window_size != null:
		var current := Vector2i(int(Settings.get_value("window_width")),
								int(Settings.get_value("window_height")))
		var index: int = Settings.WINDOW_SIZES.find(current)
		# A SIZE THE LIST DOES NOT HAVE selects nothing rather than snapping to
		# the first entry. The player may have dragged the window corner, and
		# silently reporting 1280x720 at that point would be the panel telling
		# them something they can see is untrue.
		window_size.selected = index

	_update_window_size_enabled()

	_refreshing = false


# =============================================================================
# ACCOUNT  -  recovery email and password
# =============================================================================
#
# Both of these already existed on the server and had nowhere to be used from:
# POST /api/account/email (and its verify) were only reachable from the login
# screen's first-time prompt, and POST /api/auth/password had no client at all.
# This is the screen you come back to afterwards.
#
# BOTH DEMAND THE CURRENT PASSWORD, and the server is what enforces it. That is
# the rule that stops a stolen session being upgraded into a stolen account: a
# thief holding a token can neither change the password nor repoint recovery at
# their own inbox without knowing the password they do not have.

func _connect_account() -> void:
	var wiring := [
		[account_email_button, _on_account_email_button],
		[account_password_button, _on_account_password_button],
		[account_email_send, _on_account_email_send],
		[account_email_verify, _on_account_email_verify],
		[account_password_save, _on_account_password_save],
	]
	for pair in wiring:
		var button: Button = pair[0]
		var handler: Callable = pair[1]
		if button != null and not button.pressed.is_connected(handler):
			button.pressed.connect(handler)

	_show_account_form(null)


func _account_say(message: String, color: Color) -> void:
	if account_status == null:
		return
	account_status.text = message
	account_status.add_theme_color_override("font_color", color)


func _show_account_form(which) -> void:
	# One at a time, and both closed by default - this is a settings panel, not
	# a form people are meant to be staring at.
	if account_email_form != null:
		account_email_form.visible = which == account_email_form
	if account_password_form != null:
		account_password_form.visible = which == account_password_form
	if which == null:
		_account_say("", ACCOUNT_PLAIN)


func _refresh_account() -> void:
	if account_email_value == null:
		return
	if not Api.is_logged_in():
		account_email_value.text = "not signed in"
		return

	var res: Dictionary = await Api.get_json("/api/account/email", Api.PROBE_TIMEOUT)
	if not res.get("ok", false):
		account_email_value.text = "unavailable"
		return

	var data = res.get("data", {})
	if not (data is Dictionary):
		return

	# The server only ever returns it masked - see _mask_email() in app.py. The
	# raw address is never sent to any client, including this one.
	if not bool(data.get("has_email", false)):
		account_email_value.text = "none set"
		account_email_value.add_theme_color_override("font_color", ACCOUNT_BAD)
	elif bool(data.get("verified", false)):
		account_email_value.text = str(data.get("email", ""))
		account_email_value.add_theme_color_override("font_color", ACCOUNT_OK)
	else:
		account_email_value.text = "%s (unconfirmed)" % str(data.get("email", ""))
		account_email_value.add_theme_color_override("font_color", ACCOUNT_BAD)


func _on_account_email_button() -> void:
	var opening: bool = account_email_form != null and not account_email_form.visible
	_show_account_form(account_email_form if opening else null)


func _on_account_password_button() -> void:
	var opening: bool = account_password_form != null and not account_password_form.visible
	_show_account_form(account_password_form if opening else null)


func _on_account_email_send() -> void:
	var address: String = "" if account_email_input == null else account_email_input.text.strip_edges()
	var password: String = "" if account_email_password == null else account_email_password.text
	if address == "" or password == "":
		_account_say("Enter the new address and your current password.", ACCOUNT_BAD)
		return

	if account_email_send != null:
		account_email_send.disabled = true
	var res: Dictionary = await Api.post("/api/account/email",
		{"email": address, "password": password})
	if account_email_send != null:
		account_email_send.disabled = false

	if not res.get("ok", false):
		_account_say(str(res.get("error", "That was not accepted.")), ACCOUNT_BAD)
		return

	# The password is not needed again and should not sit in a text box.
	if account_email_password != null:
		account_email_password.text = ""
	_account_say("Code sent. Check that inbox and enter the six digits.", ACCOUNT_PLAIN)
	_refresh_account()


func _on_account_email_verify() -> void:
	var code: String = "" if account_email_code == null else account_email_code.text.strip_edges()
	if code == "":
		_account_say("Enter the code from your email.", ACCOUNT_BAD)
		return

	if account_email_verify != null:
		account_email_verify.disabled = true
	var res: Dictionary = await Api.post("/api/account/email/verify", {"code": code})
	if account_email_verify != null:
		account_email_verify.disabled = false

	if not res.get("ok", false):
		_account_say(str(res.get("error", "That code is wrong or has expired.")), ACCOUNT_BAD)
		return

	Api.needs_email = false
	if account_email_code != null:
		account_email_code.text = ""
	if account_email_input != null:
		account_email_input.text = ""
	_show_account_form(null)
	_account_say("Recovery address confirmed.", ACCOUNT_OK)
	_refresh_account()


func _on_account_password_save() -> void:
	var current: String = "" if account_current_password == null else account_current_password.text
	var fresh: String = "" if account_new_password == null else account_new_password.text
	var again: String = "" if account_confirm_password == null else account_confirm_password.text

	if current == "" or fresh == "":
		_account_say("Fill in your current and new password.", ACCOUNT_BAD)
		return
	if fresh != again:
		_account_say("Those two passwords do not match.", ACCOUNT_BAD)
		return

	if account_password_save != null:
		account_password_save.disabled = true
	var res: Dictionary = await Api.post("/api/auth/password",
		{"current_password": current, "new_password": fresh})
	if account_password_save != null:
		account_password_save.disabled = false

	if not res.get("ok", false):
		_account_say(str(res.get("error", "That did not work.")), ACCOUNT_BAD)
		return

	# EVERY SESSION WAS JUST DESTROYED, including this one, and the server
	# handed back a replacement token in the same response. Adopting it is what
	# keeps the player in the game instead of being thrown to the login screen
	# by their own password change.
	var data = res.get("data", {})
	if data is Dictionary:
		Api.adopt_new_token(str(data.get("token", "")))

	for field in [account_current_password, account_new_password, account_confirm_password]:
		if field != null:
			field.text = ""
	_show_account_form(null)
	_account_say("Password updated. Other devices were signed out.", ACCOUNT_OK)


func _update_volume_labels() -> void:
	# PERCENTAGES, NOT 0.00 - 1.00. The stored value is linear gain because
	# that is what the mixer wants; nobody thinks in linear gain.
	if master_value != null and master_slider != null:
		master_value.text = "%d%%" % roundi(master_slider.value * 100.0)
	if music_value != null and music_slider != null:
		music_value.text = "%d%%" % roundi(music_slider.value * 100.0)
	if sfx_value != null and sfx_slider != null:
		sfx_value.text = "%d%%" % roundi(sfx_slider.value * 100.0)


func _update_window_size_enabled() -> void:
	# GREYED OUT WHILE FULLSCREEN, because it does nothing there and a control
	# that does nothing is worse than one that is visibly unavailable. The
	# stored preference is untouched — it takes effect on the way back out.
	if window_size == null:
		return
	window_size.disabled = bool(Settings.get_value("fullscreen"))


# =============================================================================
# CONTROL HANDLERS
# =============================================================================

func _on_master_changed(value: float) -> void:
	_update_volume_labels()
	if _refreshing:
		return
	Settings.set_value("volume_master", value)


func _on_music_changed(value: float) -> void:
	_update_volume_labels()
	if _refreshing:
		return
	Settings.set_value("volume_music", value)


func _on_sfx_changed(value: float) -> void:
	_update_volume_labels()
	if _refreshing:
		return
	Settings.set_value("volume_sfx", value)

	# A SLIDER YOU CANNOT HEAR IS A SLIDER YOU CANNOT SET. Music is playing
	# already, so the music slider proves itself; sound effects only happen
	# when something happens, and setting their volume in a quiet menu would
	# otherwise be done entirely by faith.
	Audio.play("ui_click")


func _on_camera_zoom_changed(value: float) -> void:
	_update_camera_label()
	if _refreshing:
		return
	# APPLIED WHILE THE HAND IS STILL ON THE SLIDER, like the volume ones
	# above. Settings pushes it straight at the live camera, so the world
	# behind this panel pulls back as you drag - which is the only way to
	# choose a camera distance.
	Settings.set_value("camera_zoom", value)


func _update_camera_label() -> void:
	if camera_zoom_value == null or camera_zoom == null:
		return
	camera_zoom_value.text = "%.2fx" % camera_zoom.value


func _on_name_hue_changed(_value: float) -> void:
	_update_name_swatch()
	if _refreshing:
		return
	Settings.set_value("name_hue", _value)


func _update_name_swatch() -> void:
	# THE SWATCH IS THE NAME ITSELF, drawn the way it is drawn over the
	# character: the same fixed saturation, the same black outline. A plain
	# rectangle of colour would look fine at every hue and tell you nothing
	# about which ones are actually readable as a name.
	if name_hue == null or name_preview == null:
		return

	var picked: Color = Settings.name_colour(name_hue.value)
	name_preview.add_theme_color_override("font_color", picked)

	if name_swatch == null:
		return
	# A DARK PANEL BEHIND IT, because the name is read against the world and
	# the world is dark. Shown on the options screen's own pale blue it would
	# look like a different colour entirely.
	var behind := StyleBoxFlat.new()
	behind.bg_color = Color(0.09, 0.12, 0.08, 1.0)
	behind.border_width_left = 1
	behind.border_width_top = 1
	behind.border_width_right = 1
	behind.border_width_bottom = 1
	behind.border_color = Color(0.25, 0.33, 0.43, 1.0)
	behind.corner_radius_top_left = 2
	behind.corner_radius_top_right = 2
	behind.corner_radius_bottom_right = 2
	behind.corner_radius_bottom_left = 2
	name_swatch.add_theme_stylebox_override("panel", behind)


func _on_fullscreen_toggled(pressed: bool) -> void:
	if _refreshing:
		return
	Settings.set_value("fullscreen", pressed)
	_update_window_size_enabled()


func _on_vsync_selected(index: int) -> void:
	if _refreshing:
		return
	if index < 0 or index >= Settings.VSYNC_MODES.size():
		return
	Settings.set_value("vsync", Settings.VSYNC_MODES[index])
	_readout_accum = READOUT_SECONDS   # show the effect on the next frame


func _on_frame_cap_selected(index: int) -> void:
	if _refreshing:
		return
	if index < 0 or index >= Settings.FRAME_CAPS.size():
		return
	Settings.set_value("frame_cap", int(Settings.FRAME_CAPS[index]))
	_readout_accum = READOUT_SECONDS


func _on_graphics_api_selected(index: int) -> void:
	if _refreshing:
		return
	if index < 0 or index >= Settings.GRAPHICS_APIS.size():
		return
	Settings.set_graphics_api(Settings.GRAPHICS_APIS[index])
	_update_api_note()


func _update_api_note() -> void:
	# SAYS WHEN A RESTART IS OWED. The picker shows what override.cfg asks for;
	# the engine is still running whatever it booted with, and a player who
	# picked Direct3D 12 and saw nothing change would reasonably conclude the
	# option is broken rather than pending.
	if api_note == null:
		return
	var requested: String = Settings.graphics_api_requested()
	var running: String = Settings.graphics_api_in_effect()
	if requested == running:
		api_note.text = "running on %s" % API_LABELS.get(running, running)
	else:
		api_note.text = "restart to switch to %s" % API_LABELS.get(requested, requested)


func _process(delta: float) -> void:
	if not visible:
		return
	_readout_accum += delta
	if _readout_accum < READOUT_SECONDS:
		return
	_readout_accum = 0.0
	_update_pacing_readout()


func _update_pacing_readout() -> void:
	# THE LINE THIS SCREEN EXISTS FOR. Every other control here is a request;
	# this is the answer. "Screen 60 Hz - drawing 60 fps - V-Sync on" means the
	# request was honoured. "Screen 60 Hz - drawing 2400 fps - V-Sync on" means
	# the graphics driver is overriding the game, and no setting on this screen
	# can change that - so the hint underneath says where the setting that can
	# lives.
	if pacing_readout == null:
		return
	var r: Dictionary = Settings.pacing_report()
	var cap_text: String = "" if int(r["cap"]) == 0 else ", cap %d" % int(r["cap"])
	pacing_readout.text = "Screen %s Hz  -  drawing %d fps  -  V-Sync %s%s" % [
		("%.0f" % float(r["refresh"])) if float(r["refresh"]) > 0.0 else "?",
		int(round(float(r["fps"]))),
		VSYNC_LABELS.get(str(r["vsync"]), str(r["vsync"])).to_lower(),
		cap_text]
	if pacing_hint != null:
		pacing_hint.visible = bool(r["overridden"])
		if bool(r["overridden"]):
			pacing_hint.text = ("Your graphics driver is overriding V-Sync. "
				+ "AMD: Wait for Vertical Refresh -> \"Off, unless application specifies\", Enhanced Sync off. "
				+ "NVIDIA: Vertical sync -> \"Use the 3D application setting\". "
				+ "Or try Direct3D 12 below.")


func _on_window_size_selected(index: int) -> void:
	if _refreshing:
		return
	if index < 0 or index >= Settings.WINDOW_SIZES.size():
		return
	# `chosen`, not `size` — Control already has a `size` property and a local
	# by that name shadows it.
	var chosen: Vector2i = Settings.WINDOW_SIZES[index]
	# WIDTH THEN HEIGHT, two set_value() calls, and the resize happens twice.
	# It is a window resize, not a render pass, and the alternative is a
	# compound "window_size" key that Settings would have to special-case
	# through its coercion, its file and its apply dispatch to save one frame
	# of flicker that nobody will see.
	Settings.set_value("window_width", chosen.x)
	Settings.set_value("window_height", chosen.y)


func _on_render_resolution_selected(index: int) -> void:
	if _refreshing:
		return
	if index < 0 or index >= Settings.RENDER_RESOLUTIONS.size():
		return
	Settings.set_value("render_resolution", Settings.RENDER_RESOLUTIONS[index])


func _on_lighting_selected(index: int) -> void:
	if _refreshing:
		return
	if index < 0 or index >= Settings.LIGHTING_MODES.size():
		return
	Settings.set_value("lighting", Settings.LIGHTING_MODES[index])


func _on_background_limit_toggled(pressed: bool) -> void:
	if _refreshing:
		return
	Settings.set_value("background_fps_limit", pressed)


func _on_renderer_selected(index: int) -> void:
	if _refreshing:
		return
	if index < 0 or index >= Settings.RENDERERS.size():
		return
	Settings.set_renderer(Settings.RENDERERS[index])
	_update_renderer_note()


static func renderer_note_for(requested: String, booted: String, running: String) -> String:
	# THREE DIFFERENT TRUTHS, and the note says which one applies.
	#
	#   requested != booted   the player changed it; nothing happens until a
	#                         restart, and a picker that seemed to do nothing
	#                         would read as broken.
	#   running != booted     Godot fell back - asked for Standard, found no
	#                         Vulkan, and is drawing with OpenGL. Worth saying:
	#                         it explains why Standard "does nothing" here.
	#   otherwise             what is running.
	var name_of := func(method: String) -> String:
		return RENDERER_LABELS.get(method, method)
	if requested != booted:
		return "restart to switch to %s" % name_of.call(requested)
	if running != booted:
		return "running %s - this PC has no Vulkan, so the game switched itself" % name_of.call(running)
	return "running %s" % name_of.call(running)


func _update_renderer_note() -> void:
	var requested: String = Settings.renderer_requested()
	if renderer_note != null:
		renderer_note.text = renderer_note_for(requested, Settings.renderer_booted_with(),
			Settings.renderer_in_effect())
	# THE API ONLY MEANS ANYTHING TO STANDARD. Vulkan versus Direct3D 12 is a
	# choice inside the Standard renderer; Compatibility is OpenGL either way.
	# Greyed out rather than hidden, with the note saying why.
	if graphics_api != null:
		graphics_api.disabled = requested == "gl_compatibility"
	if api_note != null and requested == "gl_compatibility":
		api_note.text = "not used by Compatibility"
	elif api_note != null:
		_update_api_note()


func _on_damage_numbers_toggled(pressed: bool) -> void:
	if _refreshing:
		return
	Settings.set_value("damage_numbers", pressed)


func _on_reset_pressed() -> void:
	# THE UNDO FOR A PANEL WITH NO CANCEL. Everything here applies live, so
	# this is what a player reaches for after turning something off and losing
	# track of what it was.
	Settings.reset()
	refresh()
