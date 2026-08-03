# scenetransition.gd — AUTOLOAD. reusable fade-to-black scene transition.
# call SceneTransition.change_scene(packed_scene) from anywhere instead of
# get_tree().change_scene_to_packed() directly, so every scene change in
# the game gets the same smooth fade instead of an abrupt cut — masks any
# brief load hitch instead of it reading as a stutter.
#
# WHY AN AUTOLOAD: autoloads live outside the "current scene" tree that
# gets freed on a scene change, so this CanvasLayer + its fade overlay
# survive the exact scene swap they're covering up. a fade rect placed
# inside a normal scene would get destroyed along with everything else the
# moment the scene changes.
#
# ENTIRELY CODE-DRIVEN: the fade overlay (a full-screen ColorRect) is built
# in _ready() rather than requiring a companion .tscn — register this
# script directly as an autoload in Project Settings, nothing else needed.
#
# SETUP: Project > Project Settings > Autoload > add this script, name it
# "SceneTransition" (matches how it's called below and in leavetown.gd).
extends CanvasLayer


# =============================================================================
# EXPORTED SETTINGS
# =============================================================================

@export var fade_duration: float = 0.3


# =============================================================================
# STATE
# =============================================================================

var _fade_rect: ColorRect = null

# guards against a second change_scene() call stacking on top of one
# already in progress (e.g. player somehow re-triggers a teleport during
# the fade-out window).
var _is_transitioning: bool = false


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	layer = 100  # render above everything else, HUD included
	_build_fade_rect()


func _build_fade_rect() -> void:
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 0)  # starts fully transparent
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE  # never blocks clicks
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_fade_rect)


# =============================================================================
# PUBLIC API
# =============================================================================

func change_scene(scene: PackedScene) -> void:
	if _is_transitioning:
		return
	if scene == null:
		push_warning("SceneTransition: change_scene() called with a null PackedScene")
		return

	_is_transitioning = true
	await _fade_out()

	get_tree().change_scene_to_packed(scene)

	# scene changes are deferred in Godot — give the new scene a couple
	# frames to actually finish swapping in and run its own _ready() before
	# we reveal it. one frame is often enough but two is a safer margin
	# against a visible pop-in if the new scene does any heavy setup.
	await get_tree().process_frame
	await get_tree().process_frame

	await _fade_in()
	_is_transitioning = false


# =============================================================================
# FADE HELPERS
# =============================================================================

func _fade_out() -> void:
	var tween := create_tween()
	tween.tween_property(_fade_rect, "color:a", 1.0, fade_duration)
	await tween.finished


func _fade_in() -> void:
	var tween := create_tween()
	tween.tween_property(_fade_rect, "color:a", 0.0, fade_duration)
	await tween.finished
