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
	"vsync": true,

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

# The window sizes the options screen offers. All 16:9, all at or above the
# project's 1280x720 viewport, so nothing here ever scales the UI DOWN — see
# the note in optionsscreen.gd about why that matters for text.
const WINDOW_SIZES := [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
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
	load_settings()


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
	var typed: Variant = _coerce(value, DEFAULTS[key])
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
		_:
			return value


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
	# reapplies eight things whenever one changes. Setting the window mode has
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
			var want_vsync: int = (DisplayServer.VSYNC_ENABLED if bool(value)
				else DisplayServer.VSYNC_DISABLED)
			if DisplayServer.window_get_vsync_mode() != want_vsync:
				DisplayServer.window_set_vsync_mode(want_vsync)
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
