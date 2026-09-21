# settings.gd — the player's own preferences: volume, window, damage numbers.
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
	"fullscreen": false,

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

	# --- game ---
	# The numbers that fly off things when they are hit. On by default, because
	# they are how the game tells you what a weapon is doing — and optional,
	# because a screen full of them is a real complaint.
	"damage_numbers": true,
}

# WHOLE MULTIPLES OF THE VIEWPORT, AND NOTHING ELSE.
#
# project.godot sets stretch/scale_mode="integer", so the canvas is only ever
# drawn at 1x, 2x, 3x and the remainder becomes a border. That makes every
# other size in this list a lie: at 1600x900 the game still renders at 1x —
# identical pixels to 1280x720 — inside a window with 160px of black down each
# side. The player picks a bigger number and gets the same picture with more
# letterbox, which reads as the option doing nothing.
#
# 1920x1080 is the one worth naming, because it is the most common monitor
# there is and it is NOT a whole multiple of 1280x720 (it is 1.5x). Anyone on
# a 1080p screen wants fullscreen, which letterboxes honestly, rather than a
# windowed 1920x1080 that is 1x with a thick frame.
#
# So: 1x, 2x, 3x. The options screen prints the multiplier beside each one.
const WINDOW_SIZES := [
	Vector2i(1280, 720),    # 1x
	Vector2i(2560, 1440),   # 2x
	Vector2i(3840, 2160),   # 3x
]


# =============================================================================
# STATE
# =============================================================================

var _values: Dictionary = {}

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
	load_settings()


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
const FRAME_CAPS := [0, 60, 120, 144, 165, 240, 360]


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
	# Negative means nothing; 0 is the honest spelling of "no cap".
	return maxi(0, int(value))


func pacing_report() -> Dictionary:
	# WHAT THE ENGINE IS DOING, NOT WHAT IT WAS ASKED TO DO. Both are read live.
	# `overridden` is the one line the whole section exists for: vsync was
	# requested, nothing is capping, and the game is drawing far more frames
	# than the screen can show. A driver is ignoring the request. Nothing in
	# this file can change that; the options screen can at least say it.
	var screen: int = DisplayServer.window_get_current_screen()
	var refresh: float = DisplayServer.screen_get_refresh_rate(screen)
	var fps: float = Engine.get_frames_per_second()
	var mode: String = vsync_name_for(DisplayServer.window_get_vsync_mode())
	var cap: int = Engine.max_fps
	var overridden: bool = (mode != "off" and mode != "fast" and cap == 0
		and refresh > 0.0 and fps > refresh * 1.5)
	return {
		"refresh": refresh, "fps": fps, "vsync": mode, "cap": cap,
		"overridden": overridden,
	}


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
		set_value(key, config.get_value(SECTION, key, DEFAULTS[key]))

	_loading = false

	# Written back once at the end rather than on every key above, so a first
	# launch leaves a complete file and an upgraded one gains the new keys.
	save_settings()


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
		"fullscreen":
			_apply_window_mode()
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
			# THE ONLY PLACE max_fps IS WRITTEN. It used to be written by a
			# once-a-second poll that chose ceil(refresh) - 1 on its own, which
			# is the regression the FRAME PACING section describes. Now the cap
			# is the player's number or nothing.
			if Engine.max_fps != int(value):
				Engine.max_fps = int(value)
		"damage_numbers":
			# Read where the labels are spawned rather than pushed anywhere —
			# see player.gd and baseenemy.gd. Nothing to apply.
			pass


func _apply_window_mode() -> void:
	# BORDERLESS FULLSCREEN, which is what WINDOW_MODE_FULLSCREEN means in Godot:
	# a window with no decorations, sized to the screen, still composited by the
	# desktop like any other window. WINDOW_MODE_EXCLUSIVE_FULLSCREEN is the one
	# that takes the display over outright.
	#
	# Borderless is the right default for this game — it alt-tabs instantly and
	# behaves on a multi-monitor desk, which exclusive does not. Exclusive was
	# tried here on the theory that taking the compositor out of the presentation
	# path would settle a tearing problem; it did not, so it is not worth the
	# cost it carries.
	var want_fullscreen: bool = bool(get_value("fullscreen"))
	var want_mode: int = (DisplayServer.WINDOW_MODE_FULLSCREEN
		if want_fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)

	# NOTHING HAPPENS IF THE WINDOW IS ALREADY LIKE THIS — see the note in
	# _apply_window_size() for why that matters more than it looks.
	if DisplayServer.window_get_mode() != want_mode:
		DisplayServer.window_set_mode(want_mode)

	# The stored size is reapplied on the way OUT of fullscreen, because
	# leaving fullscreen restores whatever size the window had before it — not
	# necessarily the one the player chose.
	if not want_fullscreen:
		_apply_window_size()


func _apply_window_size() -> void:
	# IGNORED WHILE FULLSCREEN, and not stored any differently. A player who
	# picks 1600x900 while fullscreen has expressed a preference about their
	# window; it takes effect when there is a window again.
	if bool(get_value("fullscreen")):
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
