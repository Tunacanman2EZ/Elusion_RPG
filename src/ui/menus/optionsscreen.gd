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

@onready var render_resolution: OptionButton = get_node_or_null("%renderresolution")
@onready var lighting:          OptionButton = get_node_or_null("%lighting")
@onready var background_limit:  CheckButton  = get_node_or_null("%backgroundlimit")
@onready var renderer:          OptionButton = get_node_or_null("%renderer")
@onready var renderer_note:     Label        = get_node_or_null("%renderernote")

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
	# THE MULTIPLIER IS THE POINT, not decoration. With integer scaling these
	# sizes are the only ones that fill their window edge to edge, and saying
	# "2x" beside 2560x1440 explains why the list skips 1600x900 and 1920x1080
	# rather than leaving it looking like an oversight.
	var base_height: int = int(ProjectSettings.get_setting(
		"display/window/size/viewport_height", 720))
	for option in Settings.WINDOW_SIZES:
		# Integer division on purpose: every entry in WINDOW_SIZES is a whole
		# multiple of the viewport by construction, so there is no remainder to
		# lose. The guard below catches the case where someone adds one that
		# isn't, rather than printing a rounded-down lie.
		@warning_ignore("integer_division")
		var factor: int = (option.y / base_height) if base_height > 0 else 0
		if base_height <= 0 or factor * base_height != option.y:
			factor = 0
		if factor > 0:
			window_size.add_item("%d x %d   (%dx)" % [option.x, option.y, factor])
		else:
			window_size.add_item("%d x %d" % [option.x, option.y])


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

	if master_slider != null:
		master_slider.value = float(Settings.get_value("volume_master"))
	if music_slider != null:
		music_slider.value = float(Settings.get_value("volume_music"))
	if sfx_slider != null:
		sfx_slider.value = float(Settings.get_value("volume_sfx"))

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
