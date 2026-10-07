# settings.gd — the player's own preferences: volume, window, performance,
# damage numbers.
# Autoloaded as `Settings`.
#
# =============================================================================
# THESE ARE NOT SAVE DATA, AND THAT IS THE WHOLE REASON THIS FILE EXISTS
# =============================================================================
# Everything else the player owns — level, gold, what is in the bag, what is
# worn — lives on the server, because the server is the authority and a file
# the player can edit is not. None of that reasoning applies here.
#
# A volume slider belongs to the MACHINE, not the account. Turning the music
# down on a laptop should not turn it down on a desktop, an account with four
# characters has one set of speakers between them, and there is nothing to
# cheat: a player who edits this file to give themselves 200% volume has
# achieved loud.
#
# So it is a ConfigFile in user://, which is the one place in this project
# where "the client owns it" is the correct answer rather than a hole.
#
# =============================================================================
# EVERY SETTING IS DECLARED ONCE, IN DEFAULTS
# =============================================================================
# The dictionary below is the whole schema: a key's default IS its type, its
# presence in the file is optional, and an unknown key in the file is ignored.
# Adding a setting is one line there and one control in optionsscreen.tscn —
# nothing here has to learn about it, because _apply() dispatches on the key.
#
# A KEY THAT IS NOT IN DEFAULTS CANNOT BE SET. get_value() and set_value()
# both refuse it loudly. The alternative is a typo'd key that stores fine,
# reads back as null, and turns into "why is my music setting not saving".
extends Node


# =============================================================================
# SIGNALS
# =============================================================================

# Emitted after a value has been stored AND applied. The options screen does
# not listen to it — it is the one doing the setting — but anything else that
# wants to react to a preference change reads it here rather than polling.
signal changed(key: String, value: Variant)


# =============================================================================
# THE SCHEMA
# =============================================================================

const CONFIG_PATH := "user://options.cfg"
const SECTION := "options"

# =============================================================================
# THE TWO BUSES THE VOLUME SLIDERS MOVE — AND WHY THEY DID NOT EXIST
# =============================================================================
# audio.gd::_ready() has always set `p.bus = "SFX"` on twenty sound players and
# `_music_player.bus = "Music"`, and set_bus_volume() has always carried a
# warning for the case where those names resolve to nothing:
#
#     "Audio: no bus named '%s' — check default_bus_layout.tres"
#
# There was no default_bus_layout.tres, and project.godot did not name one. So
# every sound in the game played on Master, and the one function written for
# this screen — its header says so, "Audio.set_bus_volume("SFX", 0.7)  # for
# the Options sliders" — warned once per call and did nothing.
#
# Nothing was broken loudly enough to notice, because audio on the wrong bus
# still plays. It would have been noticed the first time someone dragged a
# slider and heard no difference.
#
# The file now exists with Master, Music and SFX, and project.godot's
# [audio] buses/default_bus_layout points at it. A layout that is present but
# unreferenced is a file, not a layout. MUSIC AND SFX BOTH SEND TO MASTER,
# which is why the master slider needs no special wiring: it moves the bus the
# other two feed into.

const DEFAULTS := {
	# --- audio, linear 0.0 - 1.0 ---
	# Linear rather than decibels because that is what a slider is. Audio's
	# set_bus_volume() does the logarithmic conversion, and mutes outright at
	# zero — linear_to_db(0.0) is -inf, which is not a number a mixer enjoys.
	"volume_master": 1.0,
	"volume_music": 0.7,
	"volume_sfx": 1.0,

	# --- display ---
	# WHICH SCREEN THE GAME PLAYS ON, as Godot numbers them (not Windows'
	# "Display 1/2/3" - the two orders need not agree, which is why Options
	# names a screen by its size and refresh rate). -1 IS "WHEREVER IT OPENS",
	# and the default: nothing moves a window the player never placed. Set by
	# the Monitor picker, and by dragging the window to another screen - see
	# MONITORS AND WINDOW MODES below. BEFORE window_mode: load applies keys in
	# this order, and the window has to be on its screen before it fills it.
	"screen": -1,

	# WINDOWED, BORDERLESS OR EXCLUSIVE - see MONITORS AND WINDOW MODES. It was
	# a `fullscreen` bool, which meant borderless; an options.cfg from before
	# carries that and load_settings() reads it as this.
	"window_mode": "windowed",

	# WHERE THE WINDOW WAS ON THAT SCREEN: its top-left, counted from the
	# screen's own top-left, so it is never negative - a screen to the left of
	# the main one has negative desktop coordinates, which an absolute -1 could
	# not tell apart from "nowhere". -1 is "nowhere yet". Written by the window
	# watch, not a control, and used for the next launch: the exported game
	# starts there (override.cfg), so nothing moves.
	"window_x": -1,
	"window_y": -1,

	# V-SYNC IS A MODE NOW, NOT A SWITCH, and it is the whole frame-pacing
	# story - read the FRAME PACING section below before touching either of
	# these two. "on" is the default because it is the only setting that can
	# make tearing impossible; the others exist for a driver that overrides it.
	#   off       no sync, no cap unless frame_cap says so; tears
	#   on        FIFO - waits for the screen; the classic, tear-free
	#   adaptive  syncs when the game is faster than the screen, tears when
	#             it is slower, so a slow frame never becomes a doubled one
	#   fast      mailbox - tear-free AND uncapped, lowest latency; the driver
	#             shows the newest frame each refresh and discards the rest
	"vsync": "on",

	# 0 IS "NO CAP" AND IS THE DEFAULT. With vsync on, the screen paces the
	# game and any cap is redundant or harmful (a cap BELOW the refresh rate
	# drops a frame every second - a visible hitch). With vsync off, an
	# uncapped game tears in slices too thin to see; it is a cap NEAR the
	# refresh rate that makes tearing visible. See FRAME PACING.
	"frame_cap": 0,

	# Windowed size, ignored while fullscreen. 1280x720 is the project's own
	# viewport size, so the default is "no scaling at all".
	"window_width": 1280,
	"window_height": 720,

	# --- performance ---
	# See the PERFORMANCE section below for what each of these costs, measured.
	#
	# RENDER RESOLUTION. "screen" draws the 2D canvas at the window's own
	# resolution - the project's canvas_items stretch, sharpest text. "low"
	# draws it at the project's 1280x720 and scales the finished frame up -
	# viewport stretch. The world is pixel art at 3x zoom either way, so the
	# world looks the same; text and UI edges are what get blockier.
	"render_resolution": "screen",

	# "full" is every Light2D and the crypt's darkness as authored. "simple"
	# turns the lights off and lifts the darkness so nothing becomes unplayably
	# dim - the single biggest cost in any lit area.
	"lighting": "full",

	# Drop to BACKGROUND_FPS while the game is not the focused window. On by
	# default: nobody is watching those frames, and a laptop on battery or a
	# second monitor running a video should not pay for them.
	"background_fps_limit": true,

	# --- game ---
	# The numbers that fly off things when they are hit. On by default, because
	# they are how the game tells you what a weapon is doing — and optional,
	# because a screen full of them is a real complaint.
	"damage_numbers": true,

	# THE CHAT LANGUAGE FILTER. On by default: a new player's first minute in
	# world chat should not be the worst of it, and anyone who wants it raw
	# can say so. Display only - see src/ui/chat/chatfilter.gd.
	"chat_filter": true,

	# HOW CLOSE THE CAMERA SITS. 3.0 is what all four class scenes were built
	# with and is the default, so nobody who never opens this sees a change.
	# Lower numbers pull back and show more of the world.
	#
	# 3.0 IS THE CEILING, not a suggestion. The art is 64x64 (128 for the
	# tank), and past 3x the game stops being pixel art and starts being big
	# rectangles - there is nothing above it worth offering.
	#
	# 2.0 IS THE FLOOR. It started at 1.0 and that was too far back: at 1x a
	# 64px character is 64 screen pixels, the faces go, and a nameplate over
	# their head is smaller than the character. Two is as far out as the art
	# holds up.
	"camera_zoom": 3.0,

	# THE COLOUR OF YOUR OWN NAME, as a hue in degrees. A hue and nothing else:
	# saturation and value are fixed at NAME_SATURATION and NAME_VALUE below,
	# because those are the two that decide whether a name is READABLE over
	# grass, stone and water, and they are not a choice worth letting somebody
	# make badly. One slider, and every position on it works.
	#
	# 45 is the default because at the fixed saturation it comes out as almost
	# exactly the parchment colour ordinary names already had, so nobody who
	# never opens this sees a change.
	"name_hue": 45.0,
}


# The range the slider offers and the value is clamped to. Read by the options
# screen so the two cannot disagree about what is allowed.
const CAMERA_ZOOM_MIN := 2.0
const CAMERA_ZOOM_MAX := 3.0
const CAMERA_ZOOM_STEP := 0.25

# The hue wheel, and the two numbers that are not on the slider.
#
# HALF SATURATION, FULL VALUE. A fully saturated name is a thin bright line
# that vibrates against the grass; half of it gives a pastel that the black
# outline can hold. Full value because the world is dark and every name has to
# win against it.
const NAME_HUE_MIN := 0.0
const NAME_HUE_MAX := 359.0
const NAME_HUE_STEP := 5.0
const NAME_SATURATION := 0.5
const NAME_VALUE := 1.0

# EVERY 16:9 SIZE WORTH OFFERING, which it did not used to be.
#
# THIS LIST USED TO BE 1x, 2x, 3x AND NOTHING ELSE, and the comment here
# explained why at length: project.godot set stretch/scale_mode="integer", so
# the canvas was only ever drawn at a whole multiple and the remainder became a
# border. At 1600x900 the game rendered at 1x - pixel for pixel identical to
# 1280x720 - inside a window with 160px of black down each side, so offering
# that size would have been offering the same picture with more letterbox.
#
# 1920x1080 WAS THE ONE THAT HURT. It is the most common monitor there is and
# it is 1.5x of 1280x720, so under integer scaling FULLSCREEN on a 1080p screen
# drew the game at 1x in the middle of the display with a thick black frame
# around it. That is not fullscreen working; that is fullscreen refusing.
#
# project.godot now sets scale_mode="fractional", so the canvas is drawn at
# whatever multiple fits and 1.5x is a real scale. aspect="keep" is pinned
# alongside it, which is what keeps the viewport exactly 1280x720 in game units
# at every window size - so every offset in every .tscn still lands where it
# was placed, and a wider monitor gets bars rather than a stretched picture.
#
# The cost is that at a fractional scale the pixel grid is uneven: at 1.5x some
# source pixels land on two screen pixels and some on one. On a 16:9 screen the
# alternative was a black border, so this is the better trade - and anyone who
# wants the perfect grid can pick 1280x720 or 2560x1440, which are whole
# multiples and have no unevenness at all.
const WINDOW_SIZES := [
	Vector2i(1280, 720),    # 1.0x - exact
	Vector2i(1600, 900),    # 1.25x
	Vector2i(1920, 1080),   # 1.5x  - the common monitor
	Vector2i(2560, 1440),   # 2.0x  - exact
	Vector2i(3840, 2160),   # 3.0x  - exact
]


# A WINDOW BIGGER THAN THE SCREEN IS SHRUNK TO THE BIGGEST SIZE THAT FITS.
#
# Found on day 1 by the owner: Options offered 2560x1440 and 3840x2160 on a
# smaller monitor, and picking one left a window hanging off the screen with
# its title bar out of reach - Options and the window's own controls with it.
# The way back was editing options.cfg by hand. Now a size that does not fit
# is greyed out in the picker, and one that arrives anyway - from the file,
# or from a session on a bigger monitor - is brought down when it is read
# (_normalise), so the window is never made bigger than the screen.
#
# Per side, against the list: on a 1920x1080 screen with a taskbar and a title
# bar, 2560 becomes 1600 and 1440 becomes 900. Every size on the list is 16:9,
# so the two sides land on the same entry. Nothing fits below 1280x720, which
# is also the smallest window the game allows, so that is the floor.
static func fit_window_side(value: int, room: int, side: int) -> int:
	if room <= 0 or value <= room:
		return value
	var best: int = WINDOW_SIZES[0][side]
	for option in WINDOW_SIZES:
		if option[side] <= room:
			best = maxi(best, option[side])
	return best


static func window_fits(want: Vector2i, room: Vector2i) -> bool:
	if room.x <= 0 or room.y <= 0:
		return true
	return want.x <= room.x and want.y <= room.y


func window_room() -> Vector2i:
	"""The biggest window this screen has room for: the usable part of the
	screen the window is on (the taskbar is not usable), less the window's own
	title bar and borders. ZERO when the platform cannot say - headless, or a
	browser - and then nothing is shrunk or greyed out."""
	if DisplayServer.get_name() == "headless" or OS.has_feature("web"):
		return Vector2i.ZERO
	var usable: Vector2i = DisplayServer.screen_get_usable_rect(
		DisplayServer.window_get_current_screen()).size
	if usable.x <= 0 or usable.y <= 0:
		return Vector2i.ZERO
	var frame: Vector2i = DisplayServer.window_get_size_with_decorations() \
		- DisplayServer.window_get_size()
	return usable - Vector2i(maxi(frame.x, 0), maxi(frame.y, 0))


# =============================================================================
# STATE
# =============================================================================

var _values: Dictionary = {}

# Whether the game window has focus. Starts true: a game that just launched is
# the thing the player is looking at, and the first FOCUS_OUT says otherwise.
var _focused: bool = true

# True while load() is applying the file, so the whole startup does not emit
# eight `changed` signals at anything that happens to be listening.
var _loading: bool = false


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# ALWAYS, EVEN WHEN PAUSED. Nothing here runs per frame, but a settings
	# autoload that stops processing when the tree pauses cannot apply a change
	# made from a pause menu — which is exactly where options screens live in
	# most games, and where this one may end up.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_enforce_minimum_window()
	# BEFORE load_settings(), and before any world scene exists: every Light2D
	# and CanvasModulate that ever enters the tree passes through here, so a
	# candle in a scene loaded an hour from now obeys the lighting setting
	# without that scene, or the candle, knowing it exists.
	get_tree().node_added.connect(_on_node_added)
	load_settings()
	# AFTER the file: the screen and the mode are applied, so the remembered
	# spot is on the right screen. Then the watch, which notices drags.
	_place_window_at_launch()
	_start_window_watch()


func _notification(what: int) -> void:
	# The background limit. See "background_fps_limit" in DEFAULTS.
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			_focused = false
			_apply_fps_cap()
		NOTIFICATION_APPLICATION_FOCUS_IN:
			_focused = true
			_apply_fps_cap()


# =============================================================================
# FRAME PACING - WHAT THE "BAND OF STATIC" ACTUALLY IS, AND WHAT IS NOT A FIX
# =============================================================================
# A monitor draws top to bottom, sixty times a second. If the game swaps in a
# new frame while a draw is in progress, the top of the screen shows the old
# frame and the bottom shows the new one, with a horizontal shear line where
# they meet. That is a tear. When the picture is moving - walking - the two
# halves are offset by however far things moved between those frames, and the
# line is visible.
#
# WHERE THE LINE SITS depends on when in the scan the swap lands, and HOW FAST
# IT MOVES is the difference between the game's frame rate and the screen's:
#
#     game fps    screen Hz    difference    the line sweeps the screen every
#     60          59.94        0.06 /s       16.7 s   - a slow crawling band
#     59          60.00        1.00 /s       1.0 s    - a wave, once a second
#     2000        60.00        ~33 tears per refresh, each a fraction of a pixel
#
# THE PREVIOUS VERSION OF THIS FILE HAD THE LAST TWO ROWS THE WRONG WAY ROUND.
# It capped the game at ceil(Hz) - 1, on the reasoning that a seam sweeping
# once a second moves "too fast to read as an object". It does not. A shear
# line rolling down the screen once a second during every walk is exactly the
# "waves of static" that got reported. The cap was the regression: before it,
# project.godot's flat 60 gave the slow crawl; after it, the wave.
#
# WHAT IS ACTUALLY TRUE about the third row: at 2000 fps the frame changes 33
# times per scan, and consecutive frames differ by 90 px/s / 2000 = 0.05 px.
# The shear at each tear is smaller than a pixel. Uncapped with vsync off does
# not LOOK torn - it is the setting competitive players run. It is a cap close
# to the refresh rate that makes tearing worst, because it makes each tear a
# whole frame of motion wide and moves it slowly enough to follow.
#
# THE ONLY CURE IS VSYNC. A cap of any value changes the seam's speed, never
# its existence. V-sync "on" holds the swap until the scan finishes, and then
# there is no seam to have a speed. So:
#
#   - the default is vsync on, cap 0, and the screen paces the game
#   - no code here ever sets a cap by itself any more. The cap is the
#     player's, and is 0 unless they say otherwise
#   - the options screen shows what the ENGINE is doing right now - screen Hz,
#     frames actually drawn, vsync mode in effect - because the one thing that
#     can still defeat this is a graphics driver overriding vsync from outside
#     the game, and the only way to see that is to compare the number the game
#     asked for with the number it is getting
#
# THAT OVERRIDE IS NOT HYPOTHETICAL. On the machine this was found on, with
# vsync requested, removing the cap produced 2625 fps on a 60 Hz screen. Vsync
# was being asked for and not delivered - which is a driver control panel
# setting (AMD: "Wait for Vertical Refresh", "Enhanced Sync"), not anything a
# game can fix. pacing_report() below is how the options screen says so.

# The four modes, in the order the options screen lists them.
const VSYNC_MODES := ["off", "on", "adaptive", "fast"]

# Caps the options screen offers. 0 first because it is the default and the
# right answer whenever vsync is working. The rest are common panel rates; a
# cap is worth offering at all because an uncapped game with vsync off draws
# thousands of frames a second and turns the GPU into a heater.
#
# 30 IS FOR THE WEAKEST MACHINES: one that manages 40-50 fps looks smoother
# held at a steady 30 than wandering, and runs cooler doing it. On a 60 Hz
# screen it is exactly every other refresh, so it does not hitch the way a
# cap just under the refresh rate does.
#
# -1 IS "MATCH SCREEN": the refresh rate of the screen the window is on,
# rounded - 60 on a 59.94 Hz television, 100 on a 100 Hz ultrawide - and it
# follows the window to another screen. It is for the case MONITORS AND WINDOW
# MODES describes: a window on one screen being paced by another. Second in
# the list, after Unlimited, because it is the one worth trying first.
const FRAME_CAP_MATCH := -1
const FRAME_CAPS := [0, FRAME_CAP_MATCH, 30, 60, 120, 144, 165, 240, 360]


# `mode_name`, not `name`: Node.name exists, and a parameter by that name
# shadows it - Godot warns, and testrunner.gd already says so in its harness.
static func vsync_mode_for(mode_name: String) -> int:
	match mode_name:
		"off":      return DisplayServer.VSYNC_DISABLED
		"adaptive": return DisplayServer.VSYNC_ADAPTIVE
		"fast":     return DisplayServer.VSYNC_MAILBOX
		_:          return DisplayServer.VSYNC_ENABLED


static func vsync_name_for(mode: int) -> String:
	match mode:
		DisplayServer.VSYNC_DISABLED: return "off"
		DisplayServer.VSYNC_ADAPTIVE: return "adaptive"
		DisplayServer.VSYNC_MAILBOX:  return "fast"
		_:                            return "on"


static func normalise_vsync(value: Variant) -> String:
	# THE OLD FILE STORED A BOOL. Every options.cfg written before this change
	# has `vsync=true` or `vsync=false`, and ConfigFile hands those back as
	# bools. They mean "on" and "off"; anything else unrecognised means the
	# default, because the alternative is a stored value the apply step does
	# not understand silently becoming whatever the match falls through to.
	if typeof(value) == TYPE_BOOL:
		return "on" if value else "off"
	var s: String = str(value).to_lower()
	if s == "true":  return "on"
	if s == "false": return "off"
	return s if s in VSYNC_MODES else "on"


static func normalise_frame_cap(value: Variant) -> int:
	# FRAME_CAP_MATCH is the one negative with a meaning; any other means
	# nothing, and 0 is the honest spelling of "no cap".
	var cap: int = int(value)
	return cap if cap == FRAME_CAP_MATCH else maxi(0, cap)


func pacing_report() -> Dictionary:
	# WHAT THE ENGINE IS DOING, NOT WHAT IT WAS ASKED TO DO. Both are read live.
	# `overridden` is the one line the whole section exists for: vsync was
	# requested, nothing is capping, and the game is drawing far more frames
	# than the screen can show. A driver is ignoring the request. Nothing in
	# this file can change that; the options screen can at least say it.
	#
	# `timed_by` IS THE OTHER ANSWER TO "MORE FRAMES THAN THE SCREEN SHOWS"
	# (0.7.6): the frames match ANOTHER screen's rate, so the driver is not
	# ignoring V-Sync - Windows is pacing this window by a different monitor.
	# See timed_by_screen(). When it says so, `overridden` does not, because
	# the cure is different.
	var screen: int = DisplayServer.window_get_current_screen()
	var refresh: float = _known_rate(DisplayServer.screen_get_refresh_rate(screen))
	var fps: float = Engine.get_frames_per_second()
	var mode: String = vsync_name_for(DisplayServer.window_get_vsync_mode())
	var cap: int = Engine.max_fps
	var others: Array = []
	for entry in screens():
		if int(entry["index"]) != screen:
			others.append(float(entry["hz"]))
	var timed_by: float = timed_by_screen(refresh, fps, mode, cap, others)
	var overridden: bool = (timed_by <= 0.0 and mode != "off" and mode != "fast" and cap == 0
		and refresh > 0.0 and fps > refresh * 1.5)
	return {
		"refresh": refresh, "fps": fps, "vsync": mode, "cap": cap,
		"overridden": overridden, "timed_by": timed_by,
	}


# =============================================================================
# MONITORS AND WINDOW MODES - ONE WINDOW, THREE SCREENS, THREE CLOCKS
# =============================================================================
# The owner, 7 Oct: "the game runs really rough on my screen but only this
# screen not my other 2". His desk: a 180 Hz LG UltraGear (FreeSync), a 100 Hz
# LG UltraWide and a 59.94 Hz Samsung - three refresh rates, and the game was
# rough only on the slowest.
#
# A WINDOW IS COMPOSITED. In a window, or borderless fullscreen (which on
# Windows is still a window), the game hands its frames to the desktop
# compositor, and V-Sync waits on a vertical blank - which, with screens at
# different rates, need not be the blank of the screen the window is on. A
# game paced at 100 frames a second shown on a 59.94 Hz screen gets one frame
# on some refreshes and two on others: movement that walks, stops, walks.
# Godot's own guide to stutter says to use exclusive fullscreen on Windows for
# exactly this, and a Godot forum report (4.5, two screens at 144 and 60 Hz)
# found borderless fullscreen running at another screen's rate.
#
# SO THERE ARE THREE THINGS TO CHOOSE, AND OPTIONS HAS ALL THREE:
#   - Window mode: windowed, borderless (the old "Fullscreen" switch), or
#     EXCLUSIVE - the game takes that one screen over, presents to it
#     directly, and V-Sync is that screen's. Alt-tab is slower and the
#     screen may blink on the way in; that is its whole cost.
#   - Monitor: which screen, by size and refresh rate.
#   - Frame cap: Match screen - the game draws as many frames as this screen
#     shows, whoever is pacing it.
# And the pacing readout says which screen is timing the game when it is not
# this one (timed_by_screen()).
#
# WHERE IT WAS IS REMEMBERED, and the next launch STARTS there rather than
# opening on the main screen and jumping: the exported game writes the screen,
# the mode and the window's spot into override.cfg, the file Godot reads
# before it makes the window (display_override()). Nothing is written when the
# player never placed the window anywhere, and nothing at all in the editor -
# whose override.cfg is the project's own, and whose game may be embedded.
#
# A SCREEN THAT IS GONE IS NOT FOLLOWED. A remembered screen past the number
# there are now, or a spot no screen contains, is ignored, and a window that
# opens off every screen is brought back to the middle of the main one
# (_rescue_offscreen_window()).

const WINDOW_MODES := ["windowed", "borderless", "exclusive"]

# How often the window watch looks at where the window is. Nothing tells a
# program it was dragged to another screen; once a second is quicker than a
# player can look for the change.
const WINDOW_WATCH_SECONDS := 1.0

# THE override.cfg KEYS THIS FILE OWNS, and only these: display_override()
# writes them and erases the ones it does not want, and leaves every other key
# - the renderer, the graphics API - alone.
const DISPLAY_OVERRIDE_KEYS := [
	"window/size/mode", "window/size/initial_screen",
	"window/size/initial_position_type", "window/size/initial_position",
]


static func window_mode_for(mode_name: String) -> int:
	match mode_name:
		"borderless": return DisplayServer.WINDOW_MODE_FULLSCREEN
		"exclusive":  return DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		_:            return DisplayServer.WINDOW_MODE_WINDOWED


static func normalise_window_mode(value: Variant) -> String:
	# THE OLD FILE STORED `fullscreen` AS A BOOL, which was borderless. A bool
	# that reaches here means that; anything unknown is windowed.
	if typeof(value) == TYPE_BOOL:
		return "borderless" if value else "windowed"
	return normalise_choice(value, WINDOW_MODES, "windowed")


static func timed_by_screen(refresh: float, fps: float, vsync: String, cap: int,
		others: Array) -> float:
	"""The refresh rate of ANOTHER screen this game's frames are keeping time
	with, or 0.0. True when V-Sync is meant to be pacing (on or adaptive), the
	game draws clearly more frames than this screen shows, nothing caps it
	below that, and the number of frames is within a few of another screen's
	rate. 100 fps on a 59.94 Hz screen beside a 100 Hz one is that; 2400 fps
	is a driver ignoring V-Sync, which pacing_report() calls `overridden`."""
	if vsync == "off" or vsync == "fast" or refresh <= 0.0:
		return 0.0
	if fps <= refresh * 1.2 or (cap > 0 and float(cap) <= refresh * 1.2):
		return 0.0
	for hz in others:
		var other: float = float(hz)
		if other > refresh * 1.2 and absf(fps - other) <= maxf(3.0, other * 0.08):
			return other
	return 0.0


func screens() -> Array:
	"""Every screen there is: {index, size, position, hz, primary}. Empty when
	the platform has no screens to choose between - headless, a browser."""
	var out: Array = []
	if DisplayServer.get_name() == "headless" or OS.has_feature("web"):
		return out
	var primary: int = DisplayServer.get_primary_screen()
	for i in DisplayServer.get_screen_count():
		out.append({
			"index": i,
			"size": DisplayServer.screen_get_size(i),
			"position": DisplayServer.screen_get_position(i),
			"hz": _known_rate(DisplayServer.screen_get_refresh_rate(i)),
			"primary": i == primary,
		})
	return out


static func screen_label(entry: Dictionary) -> String:
	"""How Options names a screen: "1920 x 1080, 60 Hz (main)". By size and
	rate, never by number - Godot's order is not Windows' Display 1/2/3."""
	var dims: Vector2i = entry.get("size", Vector2i.ZERO)
	var hz: float = float(entry.get("hz", -1.0))
	var text: String = "%d x %d" % [dims.x, dims.y]
	if hz > 0.0:
		text += ", %d Hz" % roundi(hz)
	if bool(entry.get("primary", false)):
		text += " (main)"
	return text


func current_screen_hz() -> float:
	if DisplayServer.get_name() == "headless":
		return -1.0
	return _known_rate(DisplayServer.screen_get_refresh_rate(DisplayServer.window_get_current_screen()))


static func _known_rate(hz: float) -> float:
	# A SCREEN THAT CANNOT SAY ITS RATE answers -1 - or, on a virtual X
	# display, NaN, which compares false with everything and slips past a
	# "> 0" test in the wrong direction. Both mean "unknown" here.
	return -1.0 if is_nan(hz) or hz <= 0.0 else hz


static func display_override(mode_name: String, screen: int, spot: Vector2i,
		origin: Vector2i, screen_count: int) -> Dictionary:
	"""The override.cfg [display] keys for the next launch: {key: value}, with
	null for a key to erase. Nothing (every key erased) when the player never
	chose a screen or the remembered one is gone. Windowed with a remembered
	spot (relative to the screen, whose desktop origin is `origin`) starts AT
	that spot; anything else is centred on the screen."""
	var out: Dictionary = {}
	for key in DISPLAY_OVERRIDE_KEYS:
		out[key] = null
	if screen < 0 or screen >= screen_count:
		return out
	out["window/size/mode"] = window_mode_for(mode_name)
	out["window/size/initial_screen"] = screen
	if mode_name == "windowed" and spot.x >= 0 and spot.y >= 0:
		out["window/size/initial_position_type"] = 0   # Absolute
		out["window/size/initial_position"] = origin + spot
	else:
		out["window/size/initial_position_type"] = 3   # Center of Other Screen
	return out


func _writes_display_override() -> bool:
	# An exported desktop game only. See MONITORS AND WINDOW MODES.
	return not OS.has_feature("editor") and not OS.has_feature("web") \
		and DisplayServer.get_name() != "headless"


func _write_display_override() -> void:
	if not _writes_display_override():
		return
	var screen: int = int(get_value("screen"))
	var count: int = DisplayServer.get_screen_count()
	var origin: Vector2i = DisplayServer.screen_get_position(screen) \
		if screen >= 0 and screen < count else Vector2i.ZERO
	write_display_override_to(_override_path(), display_override(str(get_value("window_mode")),
		screen, Vector2i(int(get_value("window_x")), int(get_value("window_y"))), origin, count))


static func write_display_override_to(path: String, want: Dictionary) -> void:
	"""Write display_override()'s keys into the override.cfg at `path`: set
	the ones with a value, erase the ones that are null, and leave every other
	key in the file - the renderer, the graphics API - as it is. Nothing is
	written when nothing would change. Static, with the path handed in, so the
	suite can run it against a file of its own."""
	var cfg := ConfigFile.new()
	cfg.load(path)   # a missing file is fine; it starts empty
	var changed_any: bool = false
	for key in want:
		var value: Variant = want[key]
		if value == null:
			if cfg.has_section_key("display", key):
				cfg.erase_section_key("display", key)
				changed_any = true
		elif cfg.get_value("display", key, null) != value:
			cfg.set_value("display", key, value)
			changed_any = true
	if not changed_any:
		return
	var err: int = cfg.save(path)
	if err != OK:
		push_warning("Settings: could not write %s (error %d)." % [path, err])


func _apply_screen() -> void:
	# MOVES THE WINDOW ONLY WHEN IT IS NOT ALREADY THERE, and never for -1 or
	# a screen that is not plugged in any more.
	if DisplayServer.get_name() == "headless" or OS.has_feature("web"):
		return
	var want: int = int(get_value("screen"))
	if want < 0 or want >= DisplayServer.get_screen_count():
		return
	if DisplayServer.window_get_current_screen() == want:
		return
	# OUT OF FULLSCREEN TO MOVE, AND BACK IN THERE. An exclusive window owns
	# its screen; moving it as it is asks the driver for two transitions at
	# once.
	var mode: int = DisplayServer.window_get_mode()
	if mode != DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_current_screen(want)
	_window_watch_screen = want
	if mode == DisplayServer.WINDOW_MODE_WINDOWED:
		# A size chosen on a bigger screen may not fit this one, and Godot
		# moves a window by its corner: shrink to fit, then centre.
		set_value("window_width", int(get_value("window_width")))
		set_value("window_height", int(get_value("window_height")))
		_center_window()
	else:
		DisplayServer.window_set_mode(mode)
	_apply_fps_cap()


func _center_window() -> void:
	var screen: int = DisplayServer.window_get_current_screen()
	var usable: Rect2i = DisplayServer.screen_get_usable_rect(screen)
	var size: Vector2i = Vector2i(int(get_value("window_width")), int(get_value("window_height")))
	if DisplayServer.window_get_size() != size:
		DisplayServer.window_set_size(size)
	# Whole pixels, and an odd leftover puts the window one pixel left of
	# centre - see _apply_window_size().
	@warning_ignore("integer_division")
	DisplayServer.window_set_position(usable.position + (usable.size - size) / 2)


func _place_window_at_launch() -> void:
	# THE EDITOR'S HALF OF "WHERE IT WAS". An export starts there from
	# override.cfg and finds itself already in place; a game run from the
	# editor is moved once, here, after load_settings() put it on its screen.
	if DisplayServer.get_name() == "headless" or OS.has_feature("web"):
		return
	_rescue_offscreen_window()
	if str(get_value("window_mode")) != "windowed":
		return
	var spot := Vector2i(int(get_value("window_x")), int(get_value("window_y")))
	var screen: int = int(get_value("screen"))
	# A SCREEN THAT HAS GONE: the override.cfg written while it was plugged in
	# still names it, and Godot then opens the window in the main screen's top
	# corner. Centred instead; the watch records the screen it is on now.
	if screen >= DisplayServer.get_screen_count():
		_center_window()
		return
	if spot.x < 0 or spot.y < 0 or screen < 0 or screen >= DisplayServer.get_screen_count():
		return
	var at: Vector2i = DisplayServer.screen_get_position(screen) + spot
	if DisplayServer.window_get_position() == at:
		return
	var usable: Rect2i = DisplayServer.screen_get_usable_rect(screen)
	if usable.has_point(at):
		DisplayServer.window_set_position(at)


func _rescue_offscreen_window() -> void:
	# A WINDOW NO SCREEN CONTAINS is brought to the middle of the main one: a
	# remembered spot on a screen that has since been unplugged, or moved.
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		return
	# Half a window, in whole pixels: a centre one pixel off is still inside.
	@warning_ignore("integer_division")
	var centre: Vector2i = DisplayServer.window_get_position() + DisplayServer.window_get_size() / 2
	for i in DisplayServer.get_screen_count():
		if Rect2i(DisplayServer.screen_get_position(i), DisplayServer.screen_get_size(i)).has_point(centre):
			return
	DisplayServer.window_set_current_screen(DisplayServer.get_primary_screen())
	_center_window()


# The window watch's last look: which screen, and where. A move is recorded
# once it has held still for one look, so a drag across the desk is one write.
var _window_watch_screen: int = -1
var _window_watch_at: Vector2i = Vector2i(-1, -1)


func _start_window_watch() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("web"):
		return
	_window_watch_screen = DisplayServer.window_get_current_screen()
	var timer := Timer.new()
	timer.name = "windowwatch"
	timer.wait_time = WINDOW_WATCH_SECONDS
	timer.autostart = true
	timer.process_mode = Node.PROCESS_MODE_ALWAYS
	timer.timeout.connect(_watch_window)
	add_child(timer)


func _watch_window() -> void:
	"""Once a second: which screen the window is on, and where.

	ANOTHER SCREEN re-works Match screen's cap - the 100 Hz screen's 100 is the
	wrong number on the 60 Hz one - and becomes the screen to start on.
	A WINDOW THAT HAS STOPPED MOVING somewhere new is remembered, for the next
	launch. A minimised or maximised window is not a place."""
	var here: int = DisplayServer.window_get_current_screen()
	if here != _window_watch_screen:
		_window_watch_screen = here
		_apply_fps_cap()
	var mode: int = DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_MINIMIZED or mode == DisplayServer.WINDOW_MODE_MAXIMIZED:
		return
	note_window_place(here, DisplayServer.window_get_position() - DisplayServer.screen_get_position(here),
		mode == DisplayServer.WINDOW_MODE_WINDOWED)


func note_window_place(screen: int, spot: Vector2i, windowed: bool) -> void:
	"""Remember where the window is - its screen, and its top-left counted from
	that screen's - once it has held still for one look. Public so the suite
	can walk it through a drag without a desktop. A spot hanging off the
	screen's left or top edge is not remembered; the next launch centres it."""
	var settled: bool = spot == _window_watch_at
	_window_watch_at = spot
	if not settled:
		return
	if screen != int(get_value("screen")):
		set_value("screen", screen)
	if not windowed:
		return
	var keep: Vector2i = spot if spot.x >= 0 and spot.y >= 0 else Vector2i(-1, -1)
	if keep.x != int(get_value("window_x")) or keep.y != int(get_value("window_y")):
		set_value("window_x", keep.x)
		set_value("window_y", keep.y)


# =============================================================================
# PERFORMANCE - "ANYONE CAN RUN THIS GAME", MEASURED
# =============================================================================
# Every option here was measured before it was added, on the worst machine
# available: Godot 4.6.1, Compatibility renderer, Mesa llvmpipe - a graphics
# card simulated on two CPU cores, slower than any real GPU. Frame time, mean
# over a camera walk through the real scenes:
#
#                                   lights on    lights off
#     town        1280x720           18.9 ms      (no lights there)
#     boss arena  1280x720           37.4 ms      20.6 ms
#     field       1280x720           45.6 ms      22.3 ms
#     field       2560x1440 screen  166.6 ms      77.4 ms
#     field       2560x1440 low      55.7 ms      32.0 ms
#     field       3840x2160 screen  359.8 ms     172.2 ms
#     field       3840x2160 low      71.9 ms      45.8 ms
#
# Two things carry almost all of it. The twelve candle and lantern lights
# double the cost of any area they are in. And "screen" resolution means a
# 1440p or 4K window really does draw 4x or 9x the pixels of 720p - for a
# world that is 3x-zoomed pixel art and gains nothing from them. Those are
# the two options. Nothing else measured was worth a control.
#
# A real graphics card is far faster than that simulation, so the absolute
# numbers are not a prediction. The ratios are the point: on the weakest
# laptop a player might have, these two are the difference.

const RENDER_RESOLUTIONS := ["screen", "low"]
const LIGHTING_MODES := ["full", "simple"]

# While the window is in the background. Low enough to cost almost nothing,
# high enough that nothing time-driven stutters when you look back.
const BACKGROUND_FPS := 15

# How far "simple" lighting lifts a CanvasModulate toward white. The crypt's
# darkness is Color(0.28, 0.3, 0.4) and is only playable because candles
# light it; with the candles off, this is what keeps it readable.
const SIMPLE_AMBIENT_LIFT := 0.4

const _META_VISIBLE := &"_settings_authored_visible"
const _META_COLOUR := &"_settings_authored_colour"


static func normalise_choice(value: Variant, allowed: Array, fallback: String) -> String:
	# Case-folded, and anything unrecognised becomes the default rather than a
	# value the apply step does not know.
	var s: String = str(value).to_lower()
	return s if s in allowed else fallback


static func content_scale_mode_for(render_resolution: String) -> Window.ContentScaleMode:
	return (Window.CONTENT_SCALE_MODE_VIEWPORT if render_resolution == "low"
		else Window.CONTENT_SCALE_MODE_CANVAS_ITEMS)


static func fps_cap_for(frame_cap: int, focused: bool, background_limit: bool,
		screen_hz: float = 0.0) -> int:
	# THE ONE PLACE THE CAP IS WORKED OUT. The player's cap in the foreground;
	# in the background, BACKGROUND_FPS or the player's cap, whichever is lower
	# - a player who capped at 10 does not get raised to 15 by alt-tabbing.
	# Match screen is the window's screen's rate, rounded; a screen that cannot
	# say its rate (headless, a browser) gets no cap rather than a guess.
	var cap: int = maxi(0, frame_cap)
	if frame_cap == FRAME_CAP_MATCH:
		cap = roundi(screen_hz) if screen_hz > 0.0 else 0
	if focused or not background_limit:
		return cap
	return BACKGROUND_FPS if cap == 0 else mini(cap, BACKGROUND_FPS)


static func simple_ambient(authored: Color) -> Color:
	var lifted: Color = authored.lerp(Color.WHITE, SIMPLE_AMBIENT_LIFT)
	lifted.a = authored.a
	return lifted


func _apply_fps_cap() -> void:
	# THE ONLY PLACE max_fps IS WRITTEN - see "frame_cap" in _apply().
	var want: int = fps_cap_for(int(get_value("frame_cap")), _focused,
		bool(get_value("background_fps_limit")), current_screen_hz())
	if Engine.max_fps != want:
		Engine.max_fps = want


func _on_node_added(node: Node) -> void:
	# Cheap for everything else: two type checks. This fires for every node
	# that enters the tree, and nearly all of them are neither.
	if node is Light2D or node is CanvasModulate:
		_apply_lighting_to(node, str(get_value("lighting")))
	elif node is Camera2D:
		# A CAMERA THAT ARRIVES AFTER THE SETTING DID. Every scene change
		# builds a new player with a new camera carrying the 3.0 its .tscn was
		# saved with, so without this the zoom would reset itself at every
		# doorway.
		_apply_camera_zoom_to(node as Camera2D, float(get_value("camera_zoom")))


func _apply_lighting_to(node: Node, mode: String) -> void:
	# AUTHORED VALUES ARE REMEMBERED ON THE NODE the first time it is touched,
	# so "full" restores exactly what the scene said rather than assuming every
	# light was visible and every ambience was one colour.
	#
	# VISIBLE, NOT ENABLED. player.gd switches its carried light's `enabled` on
	# and off depending on whether the scene is dark; writing `enabled` here
	# would fight it. Hiding the node turns the light off underneath whatever
	# player.gd decides.
	var simple: bool = mode == "simple"
	if node is Light2D:
		var light := node as Light2D
		if not light.has_meta(_META_VISIBLE):
			light.set_meta(_META_VISIBLE, light.visible)
		light.visible = false if simple else bool(light.get_meta(_META_VISIBLE))
	elif node is CanvasModulate:
		var ambience := node as CanvasModulate
		if not ambience.has_meta(_META_COLOUR):
			ambience.set_meta(_META_COLOUR, ambience.color)
		var authored: Color = ambience.get_meta(_META_COLOUR)
		ambience.color = simple_ambient(authored) if simple else authored


func name_colour(hue_degrees: float = -1.0) -> Color:
	"""
	The colour a player's own name is drawn in.

	Takes a hue so the options screen can preview one the player has not
	committed to yet; called with nothing, it answers for the saved setting.
	"""
	var hue: float = hue_degrees if hue_degrees >= 0.0 else float(get_value("name_hue"))
	# wrapf, not clamp: a hue is a wheel, and 360 is 0 rather than an error.
	return Color.from_hsv(wrapf(hue, 0.0, 360.0) / 360.0, NAME_SATURATION, NAME_VALUE)


func _apply_camera_zoom_to(camera: Camera2D, zoom: float) -> void:
	# ABSOLUTE, NOT A MULTIPLIER OF WHAT THE SCENE SAID. All four class scenes
	# are authored at 3.0, so an absolute value is the same thing here and is
	# the one a player can reason about: the number on the slider IS the zoom.
	var want: float = clampf(zoom, CAMERA_ZOOM_MIN, CAMERA_ZOOM_MAX)
	if not is_equal_approx(camera.zoom.x, want):
		camera.zoom = Vector2(want, want)


func _apply_camera_zoom_everywhere(zoom: float) -> void:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return
	for node in tree.root.find_children("*", "Camera2D", true, false):
		_apply_camera_zoom_to(node as Camera2D, zoom)


func _apply_lighting_everywhere(mode: String) -> void:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return
	for node in tree.root.find_children("*", "Light2D", true, false):
		_apply_lighting_to(node, mode)
	for node in tree.root.find_children("*", "CanvasModulate", true, false):
		_apply_lighting_to(node, mode)


# =============================================================================
# THE RENDERER - Standard or Compatibility, restart required
# =============================================================================
# Same home as the graphics API below, for the same reason: the renderer is
# chosen before any script runs, so it lives in override.cfg, not options.cfg.
#
#   mobile            "Standard". Vulkan or Direct3D 12. What project.godot
#                     names.
#   gl_compatibility  OpenGL 3.3. Runs on graphics hardware too old for
#                     Vulkan, and is often the faster of the two on weak
#                     integrated graphics - it is the renderer Godot itself
#                     recommends for low-end machines and for 2D.
#
# A MACHINE WITH NO VULKAN ALREADY GETS COMPATIBILITY. Measured: with the
# project's own "mobile" setting, on a machine without Vulkan, Godot 4.6.1
# prints "switching to OpenGL 3" and boots Compatibility. So this option is
# not what lets old hardware start the game - it is for hardware whose Vulkan
# exists but runs badly, and for comparing the two.
#
# Forward+ is deliberately not offered: it is Godot's high-end 3D renderer,
# the heaviest of the three, and gives a 2D game nothing.
#
# NOT TOUCHED BY reset(), like the API: silently switching a restart-required
# renderer under "Reset to defaults" is a surprise waiting for a laptop.

const RENDERERS := ["mobile", "gl_compatibility"]
const RENDERER_SETTING := "rendering/renderer/rendering_method"


func renderer_in_effect() -> String:
	# What is actually drawing, which after a fallback is not what was asked.
	return RenderingServer.get_current_rendering_method()


func renderer_booted_with() -> String:
	# What project.godot plus override.cfg asked for at launch.
	return str(ProjectSettings.get_setting(RENDERER_SETTING, "mobile"))


func renderer_requested() -> String:
	# What override.cfg says now, which becomes true on the next launch.
	var cfg := ConfigFile.new()
	if cfg.load(_override_path()) != OK:
		return renderer_booted_with()
	return str(cfg.get_value("rendering", "renderer/rendering_method",
		renderer_booted_with()))


func set_renderer(method: String) -> void:
	if method not in RENDERERS:
		push_error("Settings: unknown renderer '%s'" % method)
		return
	var path: String = _override_path()
	var cfg := ConfigFile.new()
	cfg.load(path)   # a missing file is fine; it starts empty
	cfg.set_value("rendering", "renderer/rendering_method", method)
	var err: int = cfg.save(path)
	if err != OK:
		push_warning("Settings: could not write %s (error %d)." % [path, err])


# =============================================================================
# THE GRAPHICS API - THE ONE SETTING THAT IS NOT IN DEFAULTS, ON PURPOSE
# =============================================================================
# Vulkan or Direct3D 12, Windows only, restart required. It is not in DEFAULTS
# because the engine has to read it BEFORE any script runs - the renderer is
# built before autoloads exist - so it cannot live in options.cfg. It lives in
# override.cfg beside the project (or the executable, in an export), which is
# a file Godot reads on top of project.godot at boot.
#
# WHY IT IS OFFERED AT ALL: when a driver overrides vsync on one API, it does
# not always override it on the other. D3D12 presents through DXGI and the
# desktop compositor, which on Windows 11 is a different path from Vulkan's
# swapchain, and the one more likely to be left alone. It is a thing to TRY,
# reported honestly as a restart-required experiment, not a promise.
#
# NOT TOUCHED BY reset(). Silently changing a restart-required renderer
# setting under "Reset to defaults" is a surprise waiting for a laptop.

const GRAPHICS_APIS := ["vulkan", "d3d12"]
const GRAPHICS_API_SETTING := "rendering/rendering_device/driver.windows"


func graphics_api_in_effect() -> String:
	# What the engine booted with, which is the only truthful answer until the
	# next restart.
	return str(ProjectSettings.get_setting(GRAPHICS_API_SETTING, "vulkan"))


func graphics_api_requested() -> String:
	# What override.cfg says, which becomes true on the next launch.
	var cfg := ConfigFile.new()
	if cfg.load(_override_path()) != OK:
		return graphics_api_in_effect()
	return str(cfg.get_value("rendering", "rendering_device/driver.windows",
		graphics_api_in_effect()))


func set_graphics_api(api: String) -> void:
	if api not in GRAPHICS_APIS:
		push_error("Settings: unknown graphics api '%s'" % api)
		return
	var path: String = _override_path()
	var cfg := ConfigFile.new()
	cfg.load(path)   # a missing file is fine; it starts empty
	cfg.set_value("rendering", "rendering_device/driver.windows", api)
	var err: int = cfg.save(path)
	if err != OK:
		push_warning("Settings: could not write %s (error %d)." % [path, err])


func _override_path() -> String:
	# Beside project.godot in the editor, beside the executable in an export.
	# Godot reads override.cfg from exactly those two places, and nowhere else.
	if OS.has_feature("editor"):
		return "res://override.cfg"
	return OS.get_executable_path().get_base_dir().path_join("override.cfg")


func _enforce_minimum_window() -> void:
	# THE WINDOW MAY NEVER BE SMALLER THAN THE CANVAS IT DRAWS.
	#
	# project.godot runs stretch/scale_mode="integer", which only ever draws at
	# 1x, 2x, 3x — there is no 0.9x. So in a window below 1280x720 the canvas
	# is still rendered at full size and simply does not fit: the picture is
	# cropped and the HUD, which is anchored to the bottom right, goes off the
	# edge of the window entirely.
	#
	# That is not a hypothetical. The editor's embedded Game view sizes itself
	# to whatever space the panel has — 1159x652 in one case — and produced
	# exactly that: a cropped world and no hotbar or health bars.
	#
	# A minimum size makes the window physically unable to enter that state.
	# It does NOT cover the editor's embedded view, which the editor sizes
	# itself and which this cannot reach; running un-embedded is the answer
	# there, and it is the better way to look at the game anyway.
	var minimum := Vector2i(
		int(ProjectSettings.get_setting("display/window/size/viewport_width", 1280)),
		int(ProjectSettings.get_setting("display/window/size/viewport_height", 720)))
	if minimum.x <= 0 or minimum.y <= 0:
		return

	DisplayServer.window_set_min_size(minimum)

	# And grow it if it is already too small, because a minimum applies to what
	# the user drags next, not to the size the window happens to start at.
	var current: Vector2i = DisplayServer.window_get_size()
	if current.x < minimum.x or current.y < minimum.y:
		DisplayServer.window_set_size(Vector2i(
			maxi(current.x, minimum.x), maxi(current.y, minimum.y)))


# =============================================================================
# READING AND WRITING
# =============================================================================

func get_value(key: String) -> Variant:
	if not DEFAULTS.has(key):
		push_error("Settings: no such setting '%s' — add it to DEFAULTS." % key)
		return null
	return _values.get(key, DEFAULTS[key])


func set_value(key: String, value: Variant) -> void:
	if not DEFAULTS.has(key):
		push_error("Settings: no such setting '%s' — add it to DEFAULTS." % key)
		return

	# COERCED TO THE DEFAULT'S TYPE, not stored as handed over. A ConfigFile
	# round-trips 1.0 as a float and 1 as an int, and a slider that happens to
	# land exactly on 1 would otherwise store an int where a float is expected
	# and read back as one on the next launch. The default is the type.
	var typed: Variant = _normalise(key, _coerce(value, DEFAULTS[key]))
	if _values.get(key, null) == typed and not _loading:
		return

	_values[key] = typed
	_apply(key, typed)

	if not _loading:
		save_settings()
		changed.emit(key, typed)


func reset() -> void:
	# Back to DEFAULTS, applied and saved. Every key, not just the ones that
	# have been touched — a file half-written by an older version should come
	# out of this completely current.
	for key in DEFAULTS:
		set_value(key, DEFAULTS[key])


func _coerce(value: Variant, like: Variant) -> Variant:
	match typeof(like):
		TYPE_BOOL:
			return bool(value)
		TYPE_INT:
			return int(value)
		TYPE_FLOAT:
			return float(value)
		TYPE_STRING:
			return str(value)
		_:
			return value


func _normalise(key: String, typed: Variant) -> Variant:
	# COERCION PINS THE TYPE; THIS PINS THE MEANING. A string is the right type
	# for vsync and still says nothing about whether "true" or "Adaptive" or
	# "banana" is a mode the apply step knows. Each key that has a vocabulary
	# gets one line here, and an unknown value becomes the default rather than
	# something the match statement silently falls through.
	match key:
		"vsync":
			return normalise_vsync(typed)
		"frame_cap":
			return normalise_frame_cap(typed)
		"render_resolution":
			return normalise_choice(typed, RENDER_RESOLUTIONS, "screen")
		"lighting":
			return normalise_choice(typed, LIGHTING_MODES, "full")
		"camera_zoom":
			# CLAMPED, NOT REFUSED. options.cfg is a text file a player can
			# edit, and a 40 in it should become the ceiling rather than a
			# camera so far in that the game is four tiles across.
			return clampf(float(typed), CAMERA_ZOOM_MIN, CAMERA_ZOOM_MAX)
		"name_hue":
			# WRAPPED, because the thing it names is a circle. 400 is 40 and
			# -20 is 340; neither is a mistake worth refusing.
			return wrapf(float(typed), 0.0, 360.0)
		"window_mode":
			return normalise_window_mode(typed)
		"screen", "window_x", "window_y":
			# -1 is "none", and nothing below it means anything else.
			return maxi(-1, int(typed))
		"window_width":
			# SHRUNK TO FIT THE SCREEN. See fit_window_side().
			return fit_window_side(int(typed), window_room().x, 0)
		"window_height":
			return fit_window_side(int(typed), window_room().y, 1)
		_:
			return typed


# =============================================================================
# THE FILE
# =============================================================================

func load_settings() -> void:
	_loading = true

	var config := ConfigFile.new()
	var err: int = config.load(CONFIG_PATH)

	# ERR_FILE_NOT_FOUND IS THE NORMAL CASE, not a failure: it is every first
	# launch. Anything else is a file that exists and could not be read, which
	# is worth a line in the log — the player is about to silently lose their
	# preferences and would otherwise have no idea why.
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_warning("Settings: could not read %s (error %d) — using defaults." % [CONFIG_PATH, err])

	for key in DEFAULTS:
		set_value(key, stored_value(config, key))

	_loading = false

	# Written back once at the end rather than on every key above, so a first
	# launch leaves a complete file and an upgraded one gains the new keys.
	save_settings()


static func stored_value(config: ConfigFile, key: String) -> Variant:
	"""What the file says for `key`, or its default.

	THE OLD `fullscreen` SWITCH is read once as the window mode it meant -
	borderless - and is then gone: save_settings() writes only DEFAULTS' keys.
	Normalised here, because set_value() would first coerce the bool to the
	string "true", which is no mode at all."""
	if key == "window_mode" and not config.has_section_key(SECTION, key) \
			and config.has_section_key(SECTION, "fullscreen"):
		return normalise_window_mode(bool(config.get_value(SECTION, "fullscreen")))
	return config.get_value(SECTION, key, DEFAULTS[key])


func save_settings() -> void:
	var config := ConfigFile.new()
	for key in _values:
		config.set_value(SECTION, key, _values[key])

	var err: int = config.save(CONFIG_PATH)
	if err != OK:
		push_warning("Settings: could not write %s (error %d)." % [CONFIG_PATH, err])


# =============================================================================
# APPLYING
# =============================================================================

func _apply(key: String, value: Variant) -> void:
	# DISPATCHED ON THE KEY, one branch each, rather than an apply_all() that
	# reapplies nine things whenever one changes. Setting the window mode has
	# a visible cost — the window flickers — and doing it because the SFX
	# slider moved is the kind of thing that reads as a bug.
	match key:
		"volume_master":
			Audio.set_bus_volume("Master", float(value))
		"volume_music":
			Audio.set_bus_volume("Music", float(value))
		"volume_sfx":
			Audio.set_bus_volume("SFX", float(value))
		"screen":
			_apply_screen()
			if not _loading:
				_write_display_override()
		"window_mode":
			_apply_window_mode()
			if not _loading:
				_write_display_override()
		"window_x", "window_y":
			# Nothing to do to the window - it is already there; this is where
			# the next launch starts. See note_window_place().
			if not _loading:
				_write_display_override()
		"window_width", "window_height":
			_apply_window_size()
		"vsync":
			# ONLY IF IT IS ACTUALLY DIFFERENT. Changing the vsync mode makes
			# the renderer rebuild its swapchain, and doing that once per
			# launch to set it to the value it already had is a real change to
			# how the first frames are presented in exchange for nothing.
			var want_vsync: int = vsync_mode_for(str(value))
			if DisplayServer.window_get_vsync_mode() != want_vsync:
				DisplayServer.window_set_vsync_mode(want_vsync)
		"frame_cap":
			# max_fps IS WRITTEN IN ONE PLACE, _apply_fps_cap(). It used to be
			# written by a once-a-second poll that chose ceil(refresh) - 1 on its own, which
			# is the regression the FRAME PACING section describes. Now the cap
			# is the player's number or nothing - or, in the background, the
			# background limit. fps_cap_for() works out which.
			_apply_fps_cap()
		"background_fps_limit":
			_apply_fps_cap()
		"render_resolution":
			var want_scale: Window.ContentScaleMode = content_scale_mode_for(str(value))
			if get_tree().root.content_scale_mode != want_scale:
				get_tree().root.content_scale_mode = want_scale
		"lighting":
			_apply_lighting_everywhere(str(value))
		"camera_zoom":
			_apply_camera_zoom_everywhere(float(value))
		"name_hue":
			# Nothing pushed anywhere. player.gd listens on `changed` and
			# repaints its own plate - the colour belongs to the character,
			# not to a list this autoload would have to keep.
			pass
		"damage_numbers":
			# Read where the labels are spawned rather than pushed anywhere —
			# see player.gd and baseenemy.gd. Nothing to apply.
			pass
		"chat_filter":
			# The chat window listens on `changed` and redraws its log.
			pass


func _apply_window_mode() -> void:
	# THREE MODES NOW (0.7.6) - see MONITORS AND WINDOW MODES.
	#
	#   windowed     a window, at the stored size
	#   borderless   WINDOW_MODE_FULLSCREEN: no decorations, the size of the
	#                screen, still composited by the desktop like any window.
	#                What the old "Fullscreen" switch did; it alt-tabs at once.
	#   exclusive    WINDOW_MODE_EXCLUSIVE_FULLSCREEN: the game takes that one
	#                screen over and presents to it directly, so V-Sync is that
	#                screen's own. Godot's stutter guide recommends it on
	#                Windows.
	#
	# Exclusive was tried here once, alone, on the theory that it would settle
	# the tearing band in FRAME PACING; it did not, and was dropped. That was a
	# driver ignoring V-Sync. A window on a 60 Hz screen paced by a 180 Hz one
	# is a different problem, and this is what it wants.
	#
	# A BROWSER HAS ONE FULLSCREEN, so exclusive is borderless there.
	var mode_name: String = str(get_value("window_mode"))
	var want_mode: int = window_mode_for(mode_name)
	if OS.has_feature("web") and want_mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		want_mode = DisplayServer.WINDOW_MODE_FULLSCREEN

	# NOTHING HAPPENS IF THE WINDOW IS ALREADY LIKE THIS — see the note in
	# _apply_window_size() for why that matters more than it looks.
	var now: int = DisplayServer.window_get_mode()
	if now != want_mode:
		# FROM ONE FULLSCREEN TO THE OTHER BY WAY OF A WINDOW: each is a
		# different kind of window to the driver, and a straight swap is two
		# transitions asked for at once.
		if now != DisplayServer.WINDOW_MODE_WINDOWED and want_mode != DisplayServer.WINDOW_MODE_WINDOWED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_mode(want_mode)

	# The stored size is reapplied on the way OUT of fullscreen, because
	# leaving fullscreen restores whatever size the window had before it — not
	# necessarily the one the player chose.
	if mode_name == "windowed":
		_apply_window_size()


func _apply_window_size() -> void:
	# IGNORED WHILE FULLSCREEN, and not stored any differently. A player who
	# picks 1600x900 while fullscreen has expressed a preference about their
	# window; it takes effect when there is a window again.
	if str(get_value("window_mode")) != "windowed":
		return

	var size := Vector2i(int(get_value("window_width")), int(get_value("window_height")))
	if size.x <= 0 or size.y <= 0:
		return

	# THE WINDOW IS LEFT ALONE WHEN IT IS ALREADY THE RIGHT SIZE, and on a
	# default launch it always is — the default here is 1280x720, which is the
	# project's own viewport, which is the size Godot just made the window.
	#
	# This matters more than a saved resize call. Before this autoload existed,
	# a launch created the window once and never touched it again. With it, every
	# launch resized and repositioned the window a frame or two in, whether or
	# not anything differed. On Windows that is enough to change how the window
	# is presented — moving it between the compositor's composed and direct
	# paths — which is invisible in a screen recording, because a recorder
	# captures the frames the game submits rather than what the desktop does
	# with them afterwards.
	#
	# So: apply a preference when it IS one, and otherwise leave startup exactly
	# as it was before this file existed.
	if DisplayServer.window_get_size() == size:
		return

	DisplayServer.window_set_size(size)

	# CENTRED AFTER A RESIZE, because Godot grows the window from its top-left
	# corner. Going from 1280x720 to 2560x1440 on a 1080p screen otherwise puts
	# most of the window, and the whole HUD, off the bottom right of the
	# display with no way to drag it back.
	var screen: int = DisplayServer.window_get_current_screen()
	var usable: Rect2i = DisplayServer.screen_get_usable_rect(screen)

	# INTEGER DIVISION IS THE ANSWER HERE, not a rounding accident. Everything
	# on this line is a Vector2i — window_set_position() takes whole pixels,
	# and there is no such thing as half a pixel of window origin. An odd
	# leftover puts the window one pixel left of centre, which is the correct
	# amount of wrong.
	@warning_ignore("integer_division")
	DisplayServer.window_set_position(
		usable.position + (usable.size - size) / 2)
