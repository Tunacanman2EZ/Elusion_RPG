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

# Api's and Settings' static helpers, called on the script and not on the
# autoload: a static function called through an instance is a warning in the
# editor's debugger.
const ApiScript := preload("res://src/systems/api.gd")
const SettingsScript := preload("res://src/systems/settings.gd")


# =============================================================================
# THE HELP BUBBLE (0.64.0) - WHAT EVERY SETTING DOES, IN PLAIN WORDS
# =============================================================================
# The owner, 20 Oct: "what if a player changes settings unknowingly maybe we
# need a hud explaining i really want to think about all playes some people
# may not even know what vulkan is", then "maybe a tool tip or something".
#
# A BUBBLE, NOT GODOT'S TOOLTIP. A tooltip shows only to a mouse, only after
# a wait, and Godot's runs on in one long line; half the players here are on
# a phone. So point at a setting - its name or its control - tap it, or reach
# it with the keyboard, and a bubble beside it says at once what it does,
# what most players want, and when to change it. The controls carry no
# tooltip of their own any more - it would only say the same thing, late.
#
# IT TAKES NO ROOM. The window is laid out to fit a 720-high screen without
# scrolling (see "Options opens at the size it was drawn at"); a strip along
# the bottom, tried first, broke that. The bubble floats over the panel.
#
# WHAT IS SET ODDLY IS MARKED (help_warnings()): a player who turned V-Sync
# off, or the volume to nothing, without meaning to sees a line in the title
# bar the moment Options opens, and that setting's name in orange; pointing
# at it says why, and "Reset to defaults" puts it back.
#
# Keyed by each control's unique name. _test_options_explain_themselves()
# fails on any control in the panel that has no entry here.
const HELP := {
	"mastervolume": "How loud the whole game is - music and sound effects together. At 0% the game is silent.",
	"musicvolume": "How loud the music is, on its own.",
	"sfxvolume": "How loud everything else is: swings, spells, doors, monsters and the menus.",
	"textsize": "Makes all the writing in the game bigger - for a big screen, or one across the room. Most players: Normal.",
	"fontstyle": "The style of letters every window, button and name is written in. Chat keeps its own, for its emoji. Most players: Standard.",
	"camerazoom": "How close the camera sits. Lower pulls it back so you see more of the world around you - the mouse wheel and the zoom keys (- and =) do it too. 3.00x is how the game is drawn to be seen.",
	"namehue": "The colour of your name over your head, to tell it apart from everyone else's in a crowd.",
	"damagenumbers": "The numbers that fly up when something is hit - they show what your weapon is doing. Turn them off for a calmer screen. Most players: On.",
	"chatfilter": "Hides rude words in chat. It changes only what you see, not what anyone types. Most players: On.",
	"projectilebrightness": "How bright arrows, orbs, spikes and bullets are. They are the brightest things on the screen; lower this if a big fight is hard on your eyes.",
	"accountemailbutton": "The email address that can get your account back if you forget your password.",
	"accountpasswordbutton": "Change the password you sign in with. You will need your current one.",
	"accountdeletebutton": "Delete your account for good: every character, your bank, your friends and your chat lines. It cannot be undone.",
	"screenpick": "Which screen the game plays on, if you have more than one. It opens there next time too.",
	"windowmode": "Windowed: a window you can move. Borderless fullscreen: fills the screen and lets you switch away instantly. Exclusive fullscreen: takes the screen over - usually the smoothest.",
	"windowsize": "How big the window is when it is not fullscreen. The number in brackets is how many times the game's own 1280 x 720.",
	"vsyncmode": "Keeps the game in step with your screen, so the picture never tears (looks split across) when you move. Most players: On. Off is for testing; Adaptive and Fast are for a graphics card that ignores On.",
	"framecap": "The most pictures a second the game will draw. With V-Sync On, leave it Unlimited - your screen already sets the pace. To keep a laptop cool, Battery saver is the easy way.",
	"renderresolution": "Full draws writing and windows as sharp as your screen allows. 1280 x 720 draws them smaller and stretches them: softer, but less work for a slow computer. The world looks the same either way.",
	"lighting": "Full: candles, lanterns and the dark of the crypts. Simple: no lights and the dark lifted - the biggest saving on a slow computer. Most players: Full.",
	# The three numbers are Settings' own, filled in by help_for().
	"backgroundlimit": "While you are in another window, the game draws only %d pictures a second, so it does not slow your computer or drain its battery. Most players: On.",
	"batterysaver": "Draws at most %d pictures a second - half the work, so a laptop or phone lasts longer and stays cooler. Movement is a little less smooth. Most players: Off, unless on battery.",
	"screenrest": "Dims the screen after %d minutes with no key or touch, so a phone does not heat up and nothing burns into the screen. Any key or touch brings it back.",
	"brightness": "Darkens everything the game draws - easier on the eyes at night, and less power on many phone screens. 100% is the game as drawn.",
	"renderer": "How the game draws. Standard suits nearly every computer. Compatibility is for an old or unusual graphics card - try it if the game looks wrong. Takes effect when you restart the game.",
	"graphicsapi": "How the game talks to your graphics card (Windows only). Vulkan suits most. Direct3D 12 is Windows' own - try it if the picture stutters or tears with V-Sync On. Takes effect when you restart the game.",
	"aimrings": "The ring under you, with a ball where your attack goes - and the red one under each monster, with its dot on whoever it is after. Most players: On.",
	"rangecircles": "The dashed circles: how close you can come to a monster before it notices you, how far it chases you once it has, and how far a mythic weapon reaches.",
	"othersattacks": "Other players' waves, axes, spells, dynamite, orbs and auras. Off hides them all - a healer's aura still heals you. Most players: On.",
	"optionscreditsbutton": "Who made the art and the sound, everyone who has supported the game, and the engine's licences.",
	"optionskeysbutton": "Opens the Controls card, with every key as a button to change it.",
	"optionsresetbutton": "Puts every setting here back the way the game first started - except Renderer and Graphics API, which wait for a restart and are changed only by hand.",
	"optionsclosebutton": "Close Options. Everything you changed is already saved.",
}
const HELP_COLOUR := Color(0.9, 0.85, 0.75)
# Orange, not the title's gold, so it reads as "look at this".
const HELP_WARNING_COLOUR := Color(1.0, 0.62, 0.32)
# Each warning's setting, and the control that sets it.
const HELP_WARNED_CONTROL := {
	"volume_master": "mastervolume", "vsync": "vsyncmode", "frame_cap": "framecap", "brightness": "brightness",
}
# The bubble's widest, in px; narrower on a narrow panel.
const HELP_BUBBLE_WIDTH := 360.0
# How long after the pointer leaves a setting its bubble goes, in seconds -
# long enough to cross from a setting's name to its control without a flicker.
const HELP_HIDE_SECONDS := 0.15
# Below this, Brightness is worth a word - it is easy to drag down by mistake.
const HELP_DIM_BRIGHTNESS := 0.7


static func help_for(key: String) -> String:
	"""HELP's words for a control, with Settings' own numbers in them."""
	var text: String = str(HELP.get(key, ""))
	match key:
		"backgroundlimit":
			return text % SettingsScript.BACKGROUND_FPS
		"batterysaver":
			return text % SettingsScript.SAVER_FPS
		"screenrest":
			return text % roundi(SettingsScript.REST_AFTER / 60.0)
	return text


static func help_warnings(volume_master: float, vsync: String, cap: int,
		screen_hz: float, bright: float) -> Array:
	"""What is set oddly, worst first, as [setting key, plain words, a few
	words for the title bar]. Static so the suite can ask about any
	combination without changing the player's settings."""
	var out: Array = []
	if volume_master <= 0.0:
		out.append(["volume_master", "Master volume is at 0%, so the game is silent.",
			"Master volume is at 0% - the game is silent"])
	if vsync == "off":
		out.append(["vsync", "V-Sync is Off, so the picture can tear (look split across) when you move. Most players want On.",
			"V-Sync is Off - the picture can tear"])
	elif cap > 0 and screen_hz > 0.0 and float(cap) < screen_hz - 1.0:
		out.append(["frame_cap", "The frame cap (%d) is below your screen's %d Hz, which can stutter. Most players want Unlimited." % [cap, roundi(screen_hz)],
			"The frame cap is below your screen's speed"])
	if bright < HELP_DIM_BRIGHTNESS:
		out.append(["brightness", "Brightness is at %d%%, so the whole game is darkened." % roundi(bright * 100.0),
			"Brightness is at %d%%" % roundi(bright * 100.0)])
	return out


# =============================================================================
# SIGNALS
# =============================================================================

signal closed

# "Change keys" (0.8.0). The keys are changed on the Controls card, which the
# HUD owns; this only asks for it.
signal keys_requested

# "Credits" (0.11.1): the Credits window, which the HUD owns, like the keys.
signal credits_requested


# =============================================================================
# NODE REFERENCES
# =============================================================================

@onready var close_button:  Button       = get_node_or_null("%optionsclosebutton")
@onready var reset_button:  Button       = get_node_or_null("%optionsresetbutton")
@onready var keys_button:   Button       = get_node_or_null("%optionskeysbutton")
@onready var credits_button: Button      = get_node_or_null("%optionscreditsbutton")

@onready var master_slider: HSlider      = get_node_or_null("%mastervolume")
@onready var music_slider:  HSlider      = get_node_or_null("%musicvolume")
@onready var sfx_slider:    HSlider      = get_node_or_null("%sfxvolume")

@onready var master_value:  Label        = get_node_or_null("%mastervalue")
@onready var music_value:   Label        = get_node_or_null("%musicvalue")
@onready var sfx_value:     Label        = get_node_or_null("%sfxvalue")

# THE WINDOW MODE AND THE MONITOR (0.7.6) - see MONITORS AND WINDOW MODES in
# settings.gd. The mode picker replaced a Fullscreen switch, which was
# borderless; the monitor picker names each screen by size and refresh rate.
@onready var window_mode:       OptionButton = get_node_or_null("%windowmode")
@onready var screen_pick:       OptionButton = get_node_or_null("%screenpick")
@onready var screen_row:        Control      = get_node_or_null("%screenrow")
@onready var vsync_mode:        OptionButton = get_node_or_null("%vsyncmode")
@onready var frame_cap:         OptionButton = get_node_or_null("%framecap")
@onready var graphics_api:      OptionButton = get_node_or_null("%graphicsapi")
@onready var api_row:           Control      = get_node_or_null("%apirow")
@onready var api_note:          Label        = get_node_or_null("%apinote")
@onready var pacing_readout:    Label        = get_node_or_null("%pacingreadout")
@onready var pacing_hint:       Label        = get_node_or_null("%pacinghint")
@onready var window_size:       OptionButton = get_node_or_null("%windowsize")
@onready var text_size:         OptionButton = get_node_or_null("%textsize")
@onready var font_style:        OptionButton = get_node_or_null("%fontstyle")
@onready var damage_toggle:     CheckButton = get_node_or_null("%damagenumbers")
@onready var chat_filter_toggle: CheckButton = get_node_or_null("%chatfilter")
@onready var aim_rings_toggle:  CheckButton = get_node_or_null("%aimrings")
@onready var range_circles_toggle: CheckButton = get_node_or_null("%rangecircles")
@onready var others_attacks_toggle: CheckButton = get_node_or_null("%othersattacks")
@onready var camera_zoom:       HSlider      = get_node_or_null("%camerazoom")
@onready var camera_zoom_value: Label        = get_node_or_null("%camerazoomvalue")
@onready var name_hue:          HSlider      = get_node_or_null("%namehue")
@onready var name_swatch:       PanelContainer = get_node_or_null("%namecolourswatch")
@onready var name_preview:      Label        = get_node_or_null("%namecolourpreview")

@onready var render_resolution: OptionButton = get_node_or_null("%renderresolution")
@onready var lighting:          OptionButton = get_node_or_null("%lighting")
@onready var background_limit:  CheckButton  = get_node_or_null("%backgroundlimit")
# 0.54.0: for a phone's battery.
@onready var battery_saver:     CheckButton  = get_node_or_null("%batterysaver")
@onready var brightness:        HSlider      = get_node_or_null("%brightness")
@onready var brightness_value:  Label        = get_node_or_null("%brightnessvalue")
# 0.55.0: the owner's "a slider for bullet projectile brightness", and a rest
# for a screen left untouched - against a phone heating and a HUD burning in.
@onready var projectile_brightness:       HSlider     = get_node_or_null("%projectilebrightness")
@onready var projectile_brightness_value: Label       = get_node_or_null("%projectilebrightnessvalue")
@onready var screen_rest:                 CheckButton = get_node_or_null("%screenrest")
# Says what the Battery saver and Rest the screen do, in Settings' numbers.
@onready var battery_hint:                Label       = get_node_or_null("%batteryhint")
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
const ACCOUNT_PLAIN := Color(0.78, 0.74, 0.66)
# DELETING THE ACCOUNT (0.90.0): the second press must come this soon after
# the first ("Sure?"), or it disarms.
const DELETE_ARM_MSEC := 4000

# Built in code beside the email and password forms (_build_delete_account()).
var account_delete_button: Button = null
var account_delete_form: VBoxContainer = null
var account_delete_name: LineEdit = null
var account_delete_password: LineEdit = null
var account_delete_go: Button = null
var _delete_armed_until: int = 0
# The server's answer, for the suite: a Callable(path, body) -> Dictionary
# stands in for Api.post; empty is the real one.
var delete_request: Callable = Callable()

# The readout is polled, not signalled: nothing announces that the driver has
# started ignoring vsync. Half a second is fast enough to watch a change take
# effect and slow enough that the number is readable rather than a blur.
const READOUT_SECONDS := 0.5
var _readout_accum: float = 0.0

# Labels for the pickers, in the same order as the constants they mirror.
const VSYNC_LABELS := {
	"off": "Off", "on": "On", "adaptive": "Adaptive", "fast": "Fast (no cap)",
}
const WINDOW_MODE_LABELS := {
	"windowed": "Windowed", "borderless": "Borderless fullscreen",
	"exclusive": "Exclusive fullscreen",
}
const API_LABELS := {"vulkan": "Vulkan", "d3d12": "Direct3D 12"}
# One word and the number, so "Larger" is not a guess at how much larger.
const TEXT_SIZE_LABELS := ["Normal", "Large", "Larger", "Largest"]


static func text_size_label(index: int) -> String:
	var share: float = float(Settings.TEXT_SIZES[index])
	var word: String = TEXT_SIZE_LABELS[index] if index < TEXT_SIZE_LABELS.size() else ""
	return "%s (%d%%)" % [word, roundi(share * 100.0)]


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

# Drag by the header, resize from any edge, and come back where it was left.
# One component for all sixteen panels - see src/shared/panelwindow.gd for why
# this is not thirty lines copied into each of them.
#
# HELD IN A MEMBER, not discarded. It is a RefCounted carrying the drag state
# and the signal connections; letting it go frees it and the panel quietly
# stops responding.
var _window: PanelWindow


func _ready() -> void:
	_window = PanelWindow.attach(self, "options")
	# At the largest text size the two columns are taller than the screen.
	_window.keep_scroll_fitted(get_node_or_null("%columnsscroll") as ScrollContainer)
	_populate_window_sizes()
	_connect_controls()
	_connect_account()
	_build_help()

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


# A SIZE BIGGER THAN THIS SCREEN IS GREYED OUT, AND SAYS WHY. Picking one used
# to put the window's title bar off the top of the screen, with no way back but
# editing options.cfg - see fit_window_side() in settings.gd. Asked on every
# open rather than once, because the window may be on a different monitor by
# now. `room` is a parameter so the test can hand it a small screen.
const TOO_BIG_SUFFIX := "  - too big for this screen"


func _mark_window_sizes(room: Vector2i) -> void:
	if window_size == null:
		return
	for i in mini(window_size.item_count, Settings.WINDOW_SIZES.size()):
		var fits: bool = SettingsScript.window_fits(Settings.WINDOW_SIZES[i], room)
		var text: String = window_size.get_item_text(i).trim_suffix(TOO_BIG_SUFFIX)
		window_size.set_item_text(i, text if fits else text + TOO_BIG_SUFFIX)
		window_size.set_item_disabled(i, not fits)


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

	if window_mode != null:
		window_mode.clear()
		for mode_name in Settings.WINDOW_MODES:
			window_mode.add_item(WINDOW_MODE_LABELS.get(mode_name, mode_name))
		# A BROWSER HAS ONE FULLSCREEN: exclusive is greyed out there and says
		# why, rather than offered and quietly the same as borderless.
		if OS.has_feature("web"):
			var at: int = Settings.WINDOW_MODES.find("exclusive")
			window_mode.set_item_disabled(at, true)
			window_mode.set_item_text(at, "Exclusive fullscreen (desktop game only)")
		window_mode.item_selected.connect(_on_window_mode_selected)
	if screen_pick != null:
		screen_pick.item_selected.connect(_on_screen_selected)
	if vsync_mode != null:
		vsync_mode.clear()
		for mode_name in Settings.VSYNC_MODES:
			vsync_mode.add_item(VSYNC_LABELS.get(mode_name, mode_name))
		vsync_mode.item_selected.connect(_on_vsync_selected)
	if frame_cap != null:
		frame_cap.clear()
		for cap in Settings.FRAME_CAPS:
			frame_cap.add_item(frame_cap_label(int(cap), -1.0))
		frame_cap.item_selected.connect(_on_frame_cap_selected)
	if graphics_api != null:
		graphics_api.clear()
		for api in Settings.GRAPHICS_APIS:
			graphics_api.add_item(API_LABELS.get(api, api))
		graphics_api.item_selected.connect(_on_graphics_api_selected)
	_hide_rows_for(OS.get_name())
	if window_size != null:
		window_size.item_selected.connect(_on_window_size_selected)
	if text_size != null:
		text_size.clear()
		for i in Settings.TEXT_SIZES.size():
			text_size.add_item(text_size_label(i))
		text_size.item_selected.connect(_on_text_size_selected)
	if font_style != null:
		font_style.clear()
		for style in Settings.FONT_STYLE_ORDER:
			font_style.add_item(str(Settings.FONT_STYLES[style][0]))
		font_style.item_selected.connect(_on_font_style_selected)
	if damage_toggle != null:
		damage_toggle.toggled.connect(_on_damage_numbers_toggled)
	if chat_filter_toggle != null:
		chat_filter_toggle.toggled.connect(_on_chat_filter_toggled)
	if aim_rings_toggle != null:
		aim_rings_toggle.toggled.connect(_on_aim_rings_toggled)
	if range_circles_toggle != null:
		range_circles_toggle.toggled.connect(_on_range_circles_toggled)
	if others_attacks_toggle != null:
		others_attacks_toggle.toggled.connect(_on_others_attacks_toggled)

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
	if battery_saver != null:
		battery_saver.toggled.connect(_on_battery_saver_toggled)
	if brightness != null:
		# The range from Settings, as the camera's is.
		brightness.min_value = Settings.BRIGHTNESS_MIN
		brightness.max_value = Settings.BRIGHTNESS_MAX
		brightness.step = Settings.BRIGHTNESS_STEP
		brightness.value_changed.connect(_on_brightness_changed)
	if projectile_brightness != null:
		projectile_brightness.min_value = Settings.PROJECTILE_MIN
		projectile_brightness.max_value = 1.0
		projectile_brightness.step = Settings.PROJECTILE_STEP
		projectile_brightness.value_changed.connect(_on_projectile_brightness_changed)
	if screen_rest != null:
		screen_rest.toggled.connect(_on_screen_rest_toggled)
	if battery_hint != null:
		battery_hint.text = SettingsScript.power_hint()
	if renderer != null:
		renderer.clear()
		for method in Settings.RENDERERS:
			renderer.add_item(RENDERER_LABELS.get(method, method))
		renderer.item_selected.connect(_on_renderer_selected)

	if close_button != null:
		close_button.pressed.connect(close)
	if reset_button != null:
		reset_button.pressed.connect(_on_reset_pressed)
	if keys_button != null:
		keys_button.pressed.connect(keys_requested.emit)
	if credits_button != null:
		credits_button.pressed.connect(credits_requested.emit)


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
	show_resting_help()


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

	if window_mode != null:
		window_mode.selected = Settings.WINDOW_MODES.find(str(Settings.get_value("window_mode")))
	_refresh_screens(Settings.screens(), DisplayServer.window_get_current_screen())
	if vsync_mode != null:
		vsync_mode.selected = Settings.VSYNC_MODES.find(str(Settings.get_value("vsync")))
	if frame_cap != null:
		# A cap the list does not offer (a hand-edited 100) selects nothing,
		# for the same reason the window-size picker does below.
		_label_match_cap(Settings.current_screen_hz())
		frame_cap.selected = Settings.FRAME_CAPS.find(int(Settings.get_value("frame_cap")))
	if graphics_api != null:
		graphics_api.selected = Settings.GRAPHICS_APIS.find(Settings.graphics_api_requested())
	_update_api_note()
	_update_pacing_readout()
	if text_size != null:
		text_size.selected = Settings.TEXT_SIZES.find(float(Settings.get_value("text_size")))
	if font_style != null:
		font_style.selected = Settings.FONT_STYLE_ORDER.find(str(Settings.get_value("font")))
	if damage_toggle != null:
		damage_toggle.button_pressed = bool(Settings.get_value("damage_numbers"))
	if chat_filter_toggle != null:
		chat_filter_toggle.button_pressed = bool(Settings.get_value("chat_filter"))
	if aim_rings_toggle != null:
		aim_rings_toggle.button_pressed = bool(Settings.get_value("aim_rings"))
	if range_circles_toggle != null:
		range_circles_toggle.button_pressed = bool(Settings.get_value("range_circles"))
	if others_attacks_toggle != null:
		others_attacks_toggle.button_pressed = bool(Settings.get_value("others_attacks"))

	if render_resolution != null:
		render_resolution.selected = Settings.RENDER_RESOLUTIONS.find(
			str(Settings.get_value("render_resolution")))
	if lighting != null:
		lighting.selected = Settings.LIGHTING_MODES.find(str(Settings.get_value("lighting")))
	if background_limit != null:
		background_limit.button_pressed = bool(Settings.get_value("background_fps_limit"))
	if battery_saver != null:
		battery_saver.button_pressed = bool(Settings.get_value("battery_saver"))
	if brightness != null:
		brightness.value = float(Settings.get_value("brightness"))
	_update_brightness_label()
	if projectile_brightness != null:
		projectile_brightness.value = float(Settings.get_value("projectile_brightness"))
	_update_projectile_brightness_label()
	if screen_rest != null:
		screen_rest.button_pressed = bool(Settings.get_value("screen_rest"))
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
		_mark_window_sizes(Settings.window_room())

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

	_build_delete_account()
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
	if account_delete_form != null:
		account_delete_form.visible = which == account_delete_form
		if which != account_delete_form:
			_disarm_delete()
	if which == null:
		_account_say("", ACCOUNT_PLAIN)


func _refresh_account() -> void:
	if account_email_value == null:
		return
	if account_delete_button != null:
		account_delete_button.visible = Api.is_logged_in()
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
	var password: String = "" if account_email_password == null else ApiScript.clean_password(account_email_password.text)
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
	var current: String = "" if account_current_password == null else ApiScript.clean_password(account_current_password.text)
	var fresh: String = "" if account_new_password == null else ApiScript.clean_password(account_new_password.text)
	var again: String = "" if account_confirm_password == null else ApiScript.clean_password(account_confirm_password.text)

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


# =============================================================================
# DELETING THE ACCOUNT (0.90.0)
# =============================================================================
# The owner, of a database diagram that showed no way to remove an account:
# "lets fix all of those". POST /api/account/delete (the API's accountdelete/)
# takes the account's name typed and its password; this asks for both, and a
# second press of "Delete forever" within DELETE_ARM_MSEC. Gone means every
# character, the bank, friends, guild seat, chat lines and sign-ins; the name is
# free again. Built in code under the password form, like character select's
# delete, so the scene file is untouched.

func _build_delete_account() -> void:
	if account_delete_button != null or account_password_form == null:
		return
	var column: Node = account_password_form.get_parent()
	account_delete_button = Button.new()
	account_delete_button.name = "accountdeletebutton"
	account_delete_button.text = "Delete account..."
	account_delete_button.add_theme_font_size_override("font_size", 12)
	account_delete_button.add_theme_color_override("font_color", ACCOUNT_BAD)
	account_delete_button.pressed.connect(_on_account_delete_button)
	column.add_child(account_delete_button)
	column.move_child(account_delete_button, account_password_form.get_index() + 1)

	account_delete_form = VBoxContainer.new()
	account_delete_form.name = "accountdeleteform"
	account_delete_form.add_theme_constant_override("separation", 4)
	account_delete_form.visible = false
	var warning := Label.new()
	warning.name = "accountdeletewarning"
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warning.add_theme_font_size_override("font_size", 12)
	warning.add_theme_color_override("font_color", ACCOUNT_BAD)
	warning.text = delete_warning_text()
	account_delete_form.add_child(warning)
	account_delete_name = LineEdit.new()
	account_delete_name.name = "accountdeletename"
	account_delete_name.add_theme_font_size_override("font_size", 12)
	account_delete_name.text_changed.connect(_on_delete_typed)
	account_delete_form.add_child(account_delete_name)
	account_delete_password = LineEdit.new()
	account_delete_password.name = "accountdeletepassword"
	account_delete_password.secret = true
	account_delete_password.placeholder_text = "Your password"
	account_delete_password.add_theme_font_size_override("font_size", 12)
	account_delete_password.text_changed.connect(_on_delete_typed)
	account_delete_form.add_child(account_delete_password)
	account_delete_go = Button.new()
	account_delete_go.name = "accountdeletego"
	account_delete_go.text = "Delete forever"
	account_delete_go.add_theme_font_size_override("font_size", 12)
	account_delete_go.add_theme_color_override("font_color", ACCOUNT_BAD)
	account_delete_go.disabled = true
	account_delete_go.pressed.connect(_on_account_delete_go)
	account_delete_form.add_child(account_delete_go)
	column.add_child(account_delete_form)
	column.move_child(account_delete_form, account_delete_button.get_index() + 1)


static func delete_warning_text() -> String:
	return ("This deletes your account for good: every character and what they carry, your bank, "
		+ "your gold, your friends, your guild seat and your chat lines. It cannot be undone, "
		+ "and nobody - not even the owner - can bring it back. Type your account's name to go on.")


static func delete_ready(typed: String, username: String, password: String) -> bool:
	"""The account's name typed (any case, spaces round it forgiven) and a password."""
	return username != "" and typed.strip_edges().to_lower() == username.to_lower() and password != ""


func _on_account_delete_button() -> void:
	var opening: bool = account_delete_form != null and not account_delete_form.visible
	_show_account_form(account_delete_form if opening else null)
	if opening and account_delete_name != null:
		account_delete_name.placeholder_text = "Type %s" % Api.username
		_on_delete_typed("")


func _on_delete_typed(_text: String) -> void:
	_disarm_delete()
	if account_delete_go != null:
		account_delete_go.disabled = not delete_ready(
			account_delete_name.text if account_delete_name != null else "", Api.username,
			ApiScript.clean_password(account_delete_password.text) if account_delete_password != null else "")


func _disarm_delete() -> void:
	_delete_armed_until = 0
	if account_delete_go != null:
		account_delete_go.text = "Delete forever"


func _on_account_delete_go() -> void:
	if account_delete_go == null or account_delete_go.disabled:
		return
	var now: int = Time.get_ticks_msec()
	if now > _delete_armed_until:
		# THE FIRST PRESS ONLY ARMS IT.
		_delete_armed_until = now + DELETE_ARM_MSEC
		account_delete_go.text = "Sure? Press again to delete"
		_account_say("Press again within %d seconds to delete your account for good." % (DELETE_ARM_MSEC / 1000),
			ACCOUNT_BAD)
		return
	_disarm_delete()
	account_delete_go.disabled = true
	var body := {"confirm": account_delete_name.text.strip_edges(),
		"password": ApiScript.clean_password(account_delete_password.text)}
	var res: Dictionary = {}
	if delete_request.is_valid():
		res = await delete_request.call("/api/account/delete", body)
	else:
		res = await Api.post("/api/account/delete", body)
	if not is_instance_valid(self) or not is_inside_tree():
		return
	account_delete_go.disabled = false
	if not res.get("ok", false):
		var status: int = int(res.get("status", 0))
		_account_say("That password is not correct." if status == 401
			else str(res.get("error", "Your account was not deleted.")), ACCOUNT_BAD)
		return
	account_delete_password.text = ""
	_account_deleted()


func _account_deleted() -> void:
	"""GONE: back to the login screen, with the reason on it. The server ended
	every session already, so there is nobody to tell (forget_session)."""
	if delete_request.is_valid():
		return    # the suite stops here
	Api.forget_session("Your account is deleted. Thank you for playing Elusion.")
	CharacterData.clear_current_user()
	get_tree().change_scene_to_file("res://scene/ui/menus/loginmenu.tscn")


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
	window_size.disabled = str(Settings.get_value("window_mode")) != "windowed"


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


func _on_zoom_from_the_world(key: String, value: Variant) -> void:
	"""THE WHEEL MOVES THE SLIDER (0.95.0): zoomed from the world with the
	panel open, the slider and its number follow."""
	if key != "camera_zoom" or camera_zoom == null:
		return
	camera_zoom.set_value_no_signal(float(value))
	_update_camera_label()


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
	# the world is dark. Shown on the options screen's own brown it would
	# look like a different colour entirely.
	var behind := StyleBoxFlat.new()
	behind.bg_color = Color(0.09, 0.12, 0.08, 1.0)
	behind.border_width_left = 1
	behind.border_width_top = 1
	behind.border_width_right = 1
	behind.border_width_bottom = 1
	behind.border_color = Color(0.4, 0.33, 0.22, 1.0)
	behind.corner_radius_top_left = 2
	behind.corner_radius_top_right = 2
	behind.corner_radius_bottom_right = 2
	behind.corner_radius_bottom_left = 2
	name_swatch.add_theme_stylebox_override("panel", behind)


func _on_window_mode_selected(index: int) -> void:
	if _refreshing:
		return
	if index < 0 or index >= Settings.WINDOW_MODES.size():
		return
	Settings.set_value("window_mode", Settings.WINDOW_MODES[index])
	_update_window_size_enabled()
	_readout_accum = READOUT_SECONDS


# The screens the Monitor picker lists, in its order: Settings.screens()
# entries. Kept so a pick can be turned back into a screen index.
var _screens_listed: Array = []


func _refresh_screens(listed: Array, here: int) -> void:
	"""Fill the Monitor picker from Settings.screens(), with the screen the
	window is on selected. ONE SCREEN, OR NONE (a browser), IS NO CHOICE, and
	the row is hidden rather than offering a list of one."""
	_screens_listed = listed
	if screen_pick == null:
		return
	screen_pick.clear()
	for entry in listed:
		screen_pick.add_item(SettingsScript.screen_label(entry))
		if int(entry["index"]) == here:
			screen_pick.select(screen_pick.item_count - 1)
	if screen_row != null:
		screen_row.visible = listed.size() > 1


func _on_screen_selected(index: int) -> void:
	if _refreshing:
		return
	if index < 0 or index >= _screens_listed.size():
		return
	Settings.set_value("screen", int(_screens_listed[index]["index"]))
	# The cap's Match screen label and the sizes that fit are this screen's
	# now; refresh() asks again.
	refresh()


static func frame_cap_label(cap: int, screen_hz: float) -> String:
	"""What the Frame cap picker calls a cap. Match screen names the number it
	is today, on this screen, when the screen can say."""
	if cap == 0:
		return "Unlimited"
	if cap == SettingsScript.FRAME_CAP_MATCH:
		return "Match screen" if screen_hz <= 0.0 else "Match screen (%d)" % roundi(screen_hz)
	return "%d fps" % cap


func _label_match_cap(screen_hz: float) -> void:
	if frame_cap == null:
		return
	var at: int = Settings.FRAME_CAPS.find(Settings.FRAME_CAP_MATCH)
	if at >= 0 and at < frame_cap.item_count:
		frame_cap.set_item_text(at, frame_cap_label(Settings.FRAME_CAP_MATCH, screen_hz))


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


static func rows_hidden_on(os_name: String) -> Array:
	"""The display rows that would be a control doing nothing on `os_name` -
	this project's least favourite kind of control.

	- "api": the picker writes driver.windows, so the row is Windows only.
	- A browser ("Web") owns the window and its size, paces every frame itself
	  whatever V-Sync is set to, and has one renderer, Compatibility - with no
	  folder beside an executable for override.cfg to keep a choice in."""
	var rows: Array = []
	if os_name != "Windows":
		rows.append("api")
	if os_name == "Web":
		rows.append_array(["window", "vsync", "renderer", "screen"])
	return rows


func _hide_rows_for(os_name: String) -> void:
	var rows: Dictionary = {
		"api": [api_row],
		"window": [window_size.get_parent() if window_size != null else null],
		"vsync": [vsync_mode.get_parent() if vsync_mode != null else null],
		"renderer": [renderer.get_parent() if renderer != null else null, renderer_note],
		"screen": [screen_row],
	}
	for row_name in rows_hidden_on(os_name):
		for row in rows[row_name]:
			if row != null:
				row.visible = false


static func pacing_line(r: Dictionary, os_name: String) -> String:
	"""The readout for a Settings.pacing_report().

	A browser paces every frame itself and reports no refresh rate, so there it
	says so, rather than "Screen ? Hz" and a V-Sync setting with no row."""
	var cap_text: String = "" if int(r["cap"]) == 0 else ", cap %d" % int(r["cap"])
	if os_name == "Web":
		return "Drawing %d fps  -  paced by the browser%s" % [int(round(float(r["fps"]))), cap_text]
	return "Screen %s Hz  -  drawing %d fps  -  V-Sync %s%s" % [
		("%.0f" % float(r["refresh"])) if float(r["refresh"]) > 0.0 else "?",
		int(round(float(r["fps"]))),
		VSYNC_LABELS.get(str(r["vsync"]), str(r["vsync"])).to_lower(),
		cap_text]


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
	pacing_readout.text = pacing_line(r, OS.get_name())
	if pacing_hint != null:
		var hint: String = pacing_hint_for(r)
		pacing_hint.visible = hint != ""
		if hint != "":
			pacing_hint.text = hint
	# The window may have been dragged to another screen while Options is open.
	_label_match_cap(float(r["refresh"]))


static func pacing_hint_for(r: Dictionary) -> String:
	"""The line under the readout, or "" when there is nothing to fix.

	ANOTHER SCREEN IS TIMING THE GAME (timed_by) comes first, because its cure
	is here on this screen: the owner's 59.94 Hz Samsung beside a 180 Hz and a
	100 Hz screen. A DRIVER IGNORING V-SYNC is a setting outside the game."""
	var timed_by: float = float(r.get("timed_by", 0.0))
	if timed_by > 0.0:
		return ("This screen is %d Hz, but the game is drawing about %d frames a second - "
			+ "the pace of your %d Hz screen. Pick Exclusive fullscreen above, "
			+ "or Frame cap: Match screen.") % [roundi(float(r["refresh"])),
				roundi(float(r["fps"])), roundi(timed_by)]
	if bool(r.get("overridden", false)):
		return ("Your graphics driver is overriding V-Sync. "
			+ "AMD: Wait for Vertical Refresh -> \"Off, unless application specifies\", Enhanced Sync off. "
			+ "NVIDIA: Vertical sync -> \"Use the 3D application setting\". "
			+ "Or try Direct3D 12 below.")
	return ""


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


func _on_battery_saver_toggled(pressed: bool) -> void:
	if _refreshing:
		return
	Settings.set_value("battery_saver", pressed)


func _on_brightness_changed(value: float) -> void:
	_update_brightness_label()
	if _refreshing:
		return
	# Applied while the hand is on the slider, like the camera: the screen
	# behind this window darkens as you drag.
	Settings.set_value("brightness", value)


func _update_brightness_label() -> void:
	if brightness_value == null or brightness == null:
		return
	brightness_value.text = "%d%%" % roundi(brightness.value * 100.0)


func _on_projectile_brightness_changed(value: float) -> void:
	_update_projectile_brightness_label()
	if _refreshing:
		return
	# The next shot fired is drawn at it - and every one already flying is
	# redrawn (Settings._apply_projectile_brightness()).
	Settings.set_value("projectile_brightness", value)


func _update_projectile_brightness_label() -> void:
	if projectile_brightness_value == null or projectile_brightness == null:
		return
	projectile_brightness_value.text = "%d%%" % roundi(projectile_brightness.value * 100.0)


func _on_screen_rest_toggled(pressed: bool) -> void:
	if _refreshing:
		return
	Settings.set_value("screen_rest", pressed)


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


func _on_text_size_selected(index: int) -> void:
	if _refreshing or index < 0 or index >= Settings.TEXT_SIZES.size():
		return
	Settings.set_value("text_size", Settings.TEXT_SIZES[index])


func _on_font_style_selected(index: int) -> void:
	if _refreshing or index < 0 or index >= Settings.FONT_STYLE_ORDER.size():
		return
	Settings.set_value("font", Settings.FONT_STYLE_ORDER[index])


func _on_chat_filter_toggled(pressed: bool) -> void:
	if _refreshing:
		return
	Settings.set_value("chat_filter", pressed)


func _on_aim_rings_toggled(pressed: bool) -> void:
	if _refreshing:
		return
	Settings.set_value("aim_rings", pressed)


func _on_range_circles_toggled(pressed: bool) -> void:
	if _refreshing:
		return
	Settings.set_value("range_circles", pressed)


func _on_others_attacks_toggled(pressed: bool) -> void:
	if _refreshing:
		return
	Settings.set_value("others_attacks", pressed)


func _on_reset_pressed() -> void:
	# THE UNDO FOR A PANEL WITH NO CANCEL. Everything here applies live, so
	# this is what a player reaches for after turning something off and losing
	# track of what it was.
	Settings.reset()
	refresh()
	show_resting_help()


# =============================================================================
# THE HELP BUBBLE - see HELP at the top
# =============================================================================

var help_bubble: PanelContainer = null
var help_label: Label = null
var help_warning_label: Label = null
var help_header: Label = null
var _help_key: String = ""
var _help_token: int = 0
# Each warned setting's name label, and the colour the scene drew it in - a
# mark taken off puts that back, not the theme's plain white.
var _name_colours: Dictionary = {}


func _build_help() -> void:
	"""The bubble and the title bar's line, built here so the scene keeps its
	layout. Then every control in HELP - and the row it sits in, so pointing
	at its name works too - shows its bubble when pointed at, tapped or
	reached with the keyboard."""
	help_bubble = PanelContainer.new()
	help_bubble.name = "helpbubble"
	help_bubble.top_level = true
	help_bubble.z_index = 50
	help_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var look := StyleBoxFlat.new()
	look.bg_color = Color(0.07, 0.055, 0.035, 1.0)
	look.border_color = Color(0.6, 0.45, 0.2, 0.9)
	look.set_border_width_all(1)
	look.set_corner_radius_all(5)
	look.content_margin_left = 10
	look.content_margin_right = 10
	look.content_margin_top = 6
	look.content_margin_bottom = 7
	help_bubble.add_theme_stylebox_override("panel", look)
	var lines := VBoxContainer.new()
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.add_theme_constant_override("separation", 4)
	help_bubble.add_child(lines)
	help_warning_label = _bubble_label("helpwarning", HELP_WARNING_COLOUR)
	lines.add_child(help_warning_label)
	help_label = _bubble_label("helptext", HELP_COLOUR)
	lines.add_child(help_label)
	help_bubble.visible = false
	add_child(help_bubble)

	# The title bar's line: clipped, so it never widens the window.
	var header: Node = get_node_or_null("mainpanel/margincontainer/vboxcontainer/headerpanel/hboxcontainer")
	if header != null:
		help_header = Label.new()
		help_header.name = "helpheader"
		help_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		help_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		help_header.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		help_header.clip_text = true
		help_header.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		help_header.add_theme_font_size_override("font_size", 13)
		help_header.add_theme_color_override("font_color", HELP_WARNING_COLOUR)
		help_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
		header.add_child(help_header)
		var close_at: Node = header.get_node_or_null("optionsclosebutton")
		if close_at != null:
			header.move_child(help_header, close_at.get_index())

	for key in HELP:
		var control := get_node_or_null("%" + str(key)) as Control
		if control == null:
			continue
		control.tooltip_text = ""
		_point_help_at(control, str(key))
		# The row it sits in, and the name written beside it - but not the
		# footer, which is three buttons and no name.
		var row := control.get_parent() as Control
		if row is HBoxContainer and str(row.name).ends_with("row") and row.name != &"footerrow":
			row.tooltip_text = ""
			for part in row.get_children():
				if part is Label:
					(part as Label).tooltip_text = ""
			_point_help_at(row, str(key))
	Settings.changed.connect(_on_setting_changed_for_help)
	Settings.changed.connect(_on_zoom_from_the_world)
	show_resting_help()


func _bubble_label(label_name: String, colour: Color) -> Label:
	var label := Label.new()
	label.name = label_name
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", colour)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _point_help_at(control: Control, key: String) -> void:
	control.mouse_entered.connect(show_help.bind(key))
	control.focus_entered.connect(show_help.bind(key))
	control.mouse_exited.connect(_hide_help_soon)
	control.focus_exited.connect(_hide_help_soon)


func show_help(key: String) -> void:
	"""The bubble beside the setting under the pointer: what it does, and
	first, in orange, why it is marked if it is."""
	if help_bubble == null or not HELP.has(key):
		return
	_help_token += 1
	_help_key = key
	help_label.text = help_for(key)
	var warned: String = ""
	for warning in _current_warnings():
		if str(HELP_WARNED_CONTROL.get(str(warning[0]), "")) == key:
			warned = str(warning[1]) + " Reset to defaults puts it back."
	help_warning_label.text = warned
	help_warning_label.visible = warned != ""
	_place_bubble(key)
	# Again once the labels have wrapped to the width: only then is the
	# bubble's height, and so whether it fits under the row, known.
	_place_bubble.call_deferred(key)


func help_text() -> String:
	"""What the bubble says, warning first."""
	if help_label == null or help_bubble == null or not help_bubble.visible:
		return ""
	if help_warning_label.visible:
		return help_warning_label.text + "\n" + help_label.text
	return help_label.text


func header_text() -> String:
	return help_header.text if help_header != null else ""


func _place_bubble(key: String) -> void:
	# Its width first, then where it fits: under the setting's row, or over
	# it when under would run past the panel's bottom.
	var control := get_node_or_null("%" + key) as Control
	var panel := get_node_or_null("mainpanel") as Control
	if control == null or panel == null or key != _help_key:
		return
	var anchor: Control = control
	var row := control.get_parent() as Control
	if row is HBoxContainer and str(row.name).ends_with("row") and row.name != &"footerrow":
		anchor = row
	var area: Rect2 = panel.get_global_rect()
	var width: float = minf(HELP_BUBBLE_WIDTH, area.size.x - 16.0)
	var inner: float = width - 20.0
	help_label.custom_minimum_size = Vector2(inner, 0)
	help_warning_label.custom_minimum_size = Vector2(inner, 0)
	help_bubble.size = Vector2(width, 0)
	help_bubble.reset_size()
	var tall: float = help_bubble.get_combined_minimum_size().y
	var at: Rect2 = anchor.get_global_rect()
	# Under the row only while it stays over the settings - never over the
	# footer's buttons, which a player may be about to press.
	var floor_y: float = area.end.y - 8.0
	var scroll := get_node_or_null("%columnsscroll") as Control
	if scroll != null:
		floor_y = scroll.get_global_rect().end.y
	var y: float = at.end.y + 4.0
	if y + tall > floor_y:
		y = at.position.y - tall - 4.0
	var x: float = clampf(at.position.x, area.position.x + 8.0, area.end.x - width - 8.0)
	help_bubble.global_position = Vector2(x, maxf(y, area.position.y + 8.0))
	help_bubble.visible = true


func _hide_help_soon() -> void:
	# Not at once: crossing from a setting's name to its control leaves one
	# and enters the other, and the bubble should not blink in between.
	if not is_inside_tree():
		return
	get_tree().create_timer(HELP_HIDE_SECONDS).timeout.connect(_hide_help_if_still.bind(_help_token))


func _hide_help_if_still(token: int) -> void:
	# Nothing else was pointed at since: the bubble goes.
	if token == _help_token:
		hide_help()


func hide_help() -> void:
	_help_key = ""
	if help_bubble != null:
		help_bubble.visible = false


func show_resting_help() -> void:
	"""Nothing pointed at: the bubble goes, and what is set oddly is marked -
	a line in the title bar, and each such setting's name in orange."""
	hide_help()
	var warnings: Array = _current_warnings()
	var marked: Dictionary = {}
	for warning in warnings:
		marked[str(HELP_WARNED_CONTROL.get(str(warning[0]), ""))] = true
	for key in HELP_WARNED_CONTROL.values():
		var name_label: Label = setting_name_label(str(key))
		if name_label == null:
			continue
		if not _name_colours.has(key):
			# null when the scene gave the name no colour of its own. An if, not
			# a one-line `x if y else null`: a Color and a null are not one type,
			# and the 4.7 editor warns on that (INCOMPATIBLE_TERNARY).
			var drawn_in: Variant = null
			if name_label.has_theme_color_override("font_color"):
				drawn_in = name_label.get_theme_color("font_color")
			_name_colours[key] = drawn_in
		if marked.has(key):
			name_label.add_theme_color_override("font_color", HELP_WARNING_COLOUR)
		elif _name_colours[key] == null:
			name_label.remove_theme_color_override("font_color")
		else:
			name_label.add_theme_color_override("font_color", _name_colours[key])
	if help_header == null:
		return
	if warnings.is_empty():
		help_header.text = ""
	elif warnings.size() == 1:
		help_header.text = "Heads up: %s." % str(warnings[0][2])
	else:
		help_header.text = "Heads up: %d settings are set unusually - they are in orange." % warnings.size()


func setting_name_label(key: String) -> Label:
	"""The name written beside a setting's control, in its row."""
	var control := get_node_or_null("%" + key) as Control
	if control == null or control.get_parent() == null:
		return null
	return control.get_parent().get_node_or_null("label") as Label


func _current_warnings() -> Array:
	return help_warnings(float(Settings.get_value("volume_master")), str(Settings.get_value("vsync")),
		int(Settings.get_value("frame_cap")), Settings.current_screen_hz(),
		float(Settings.get_value("brightness")))


func _on_setting_changed_for_help(key: String, _value: Variant) -> void:
	# The marks follow the setting at once - and the bubble open on it says
	# the new thing, so V-Sync turned Off says why where the player is looking.
	# ONLY THE SETTINGS A WARNING READS: the window watch writes where the
	# window is whenever it moves, and that must not shut a bubble being read.
	if not visible or _refreshing or not HELP_WARNED_CONTROL.has(key):
		return
	var open_on: String = _help_key
	show_resting_help()
	if open_on != "":
		show_help(open_on)
