# storyscreen.gd — full black-screen narration overlay with centered text,
# shown one paragraph at a time. REPLACES the earlier TextSequence attempt
# (which floated text above a character in the world) — this is
# screen-space instead (a CanvasLayer), covering the whole viewport
# regardless of camera position, which is what an actual "black box" needs.
#
# kept deliberately generic, same intent as before: reusable for the
# credits sequence later, not story-specific. this script only knows how
# to fade to black and show text blocks one at a time — it has no idea
# what a "player" or "field scene" is.
#
# USAGE:
#   var screen := StoryScreen.new()
#   get_tree().current_scene.add_child(screen)
#   screen.finished.connect(_on_story_finished)
#   screen.play(["Many heroes have reincarnated to a place of untold horror..."])
#
# entirely code-built, no companion .tscn needed — same approach as
# SceneTransition's fade overlay.
#
# SKIP: any keypress or click skips the entire remaining sequence, same
# behavior as the deleted TextSequence had.
extends CanvasLayer
class_name StoryScreen


# =============================================================================
# SIGNALS
# =============================================================================

signal finished()


# =============================================================================
# EXPORTED SETTINGS
# =============================================================================

@export var fade_duration: float = 1.0
@export var seconds_per_block: float = 5.0
@export var text_width: float = 800.0
@export var font_size: int = 24


# =============================================================================
# STATE
# =============================================================================

var _blocks: Array = []
var _current_index: int = 0
var _background: ColorRect = null
var _label: Label = null
var _panel: PanelContainer = null
var _is_playing: bool = false


# =============================================================================
# PUBLIC API
# =============================================================================

func play(blocks: Array, start_already_black: bool = false) -> void:
	# NEW: start_already_black skips this screen's own fade-to-black
	# entirely, appearing fully opaque from the first frame instead.
	# WHY: when this plays immediately after a SceneTransition scene
	# change, two INDEPENDENT fades were racing each other —
	# SceneTransition's own fade-in (revealing the new scene) finished
	# faster than this screen's fade TO black, leaving a real gap where
	# the player was briefly visible underneath before this caught up
	# and covered it. starting already-black removes the race entirely.
	if blocks.is_empty():
		finished.emit()
		queue_free()
		return

	_blocks = blocks
	_current_index = 0
	_is_playing = true

	layer = 100  # render above everything, HUD included — same as SceneTransition

	_build_background(start_already_black)
	_build_label()

	if start_already_black:
		_show_current_block()
	else:
		_fade_in_screen()


# =============================================================================
# BUILD
# =============================================================================

func _build_background(start_already_black: bool = false) -> void:
	_background = ColorRect.new()
	_background.color = Color(0, 0, 0, 1.0 if start_already_black else 0.0)
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_background)


func _build_label() -> void:
	# CHANGED: text now sits inside a bordered panel (dark fill, gold
	# trim) instead of floating bare on the black backdrop — matches the
	# same brown/gold visual language already used everywhere else in
	# this project (inventory, stats, the sign). the full-screen black
	# ColorRect from _build_background() stays as the backdrop; this
	# panel sits centered on top of it.
	_panel = PanelContainer.new()

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.09, 0.07, 0.92)   # dark brown, mostly opaque
	style.border_color = Color(0.85, 0.65, 0.2)      # warm gold
	style.border_width_left = 4
	style.border_width_right = 4
	style.border_width_top = 4
	style.border_width_bottom = 4
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	_panel.add_theme_stylebox_override("panel", style)

	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(text_width, 0)
	_panel.size = Vector2(text_width, 0)
	_panel.position = Vector2(-text_width / 2.0, -100)
	_panel.modulate.a = 0.0

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	_label.add_theme_font_size_override("font_size", font_size)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD

	_panel.add_child(_label)
	add_child(_panel)


# =============================================================================
# PLAYBACK
# =============================================================================

func _fade_in_screen() -> void:
	var tween := create_tween()
	tween.tween_property(_background, "color:a", 1.0, fade_duration)
	tween.tween_callback(_show_current_block)


func _show_current_block() -> void:
	if _current_index >= _blocks.size():
		_fade_out_and_finish()
		return

	_label.text = _blocks[_current_index]

	# CHANGED: fades _panel now (border + fill + text together) instead
	# of just _label — so the bordered box appears/disappears as one
	# cohesive unit rather than the frame staying static while only the
	# text fades.
	var tween := create_tween()
	tween.tween_property(_panel, "modulate:a", 1.0, fade_duration * 0.5)
	tween.tween_interval(seconds_per_block)
	tween.tween_property(_panel, "modulate:a", 0.0, fade_duration * 0.5)
	tween.tween_callback(_advance_block)


func _advance_block() -> void:
	_current_index += 1
	_show_current_block()


func _fade_out_and_finish() -> void:
	var tween := create_tween()
	tween.tween_property(_background, "color:a", 0.0, fade_duration)
	tween.tween_callback(_finish)


# =============================================================================
# SKIP / FINISH
# =============================================================================

func _unhandled_input(event: InputEvent) -> void:
	if not _is_playing:
		return
	if (event is InputEventKey and event.pressed) or (event is InputEventMouseButton and event.pressed):
		_finish()


func _finish() -> void:
	if not _is_playing:
		return
	_is_playing = false
	finished.emit()
	queue_free()
