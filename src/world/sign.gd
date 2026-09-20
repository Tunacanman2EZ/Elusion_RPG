# sign.gd — world-placed readable sign. shows a text panel when the player
# walks into the detection area, hides it on exit.
#
# scene setup:
# - Area2D root (this script)
# - a "signpanel" child (PanelContainer) — this is what actually gets
#   shown/hidden/faded now, NOT the label directly. if this project has a
#   global UI theme set (Project Settings → GUI → Theme), a plain
#   PanelContainer should automatically pick up the same brown/gold look
#   already used by the inventory/loot bag/stats screens, with zero extra
#   styling needed. if there's no global theme, copy the StyleBoxFlat from
#   an existing panel (e.g. the stats screen's mainpanel) onto this one.
# - a "label" child NESTED INSIDE signpanel (not directly under the Area2D
#   root anymore) — holds the sign's text, styled/positioned in the editor
# - CollisionShape2D sized to the area where the sign should be readable
#
# CHANGED: previously toggled the Label's visibility directly, with
# nothing behind it — readable only by accident depending on whatever
# happened to be in the background at that moment. now toggles a panel
# (with the label nested inside it), and fades rather than hard-cuts.
extends Area2D


# =============================================================================
# EXPORTED SETTINGS
# =============================================================================

# how long the fade in/out takes. set to 0 for an instant toggle instead
# of a fade, if you'd rather keep it simple.
@export var fade_duration: float = 0.2


# =============================================================================
# NODE REFERENCES
# =============================================================================

# the panel that holds the sign's text — this is what actually gets
# shown/hidden/faded now. the label is nested inside it, so toggling the
# panel's visibility handles both together.
@onready var panel: Control = $signpanel
@onready var label: Label = $signpanel/label


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# start hidden — sign only reveals its text when the player approaches
	panel.visible = false
	panel.modulate.a = 0.0


# =============================================================================
# AREA SIGNAL HANDLERS
# =============================================================================

func _on_body_entered(body: Node) -> void:
	# reveal the panel when the player enters the detection area.
	# ignores enemies, projectiles, drops — only the player triggers reveal.
	if body.is_in_group("player"):
		_fade_panel(true)


func _on_body_exited(body: Node) -> void:
	# hide the panel when the player leaves the detection area
	if body.is_in_group("player"):
		_fade_panel(false)


# =============================================================================
# FADE
# =============================================================================

# The fade currently running, kept so the next one can cancel it rather than
# race it. See _fade_panel().
var _fade_tween: Tween = null


func _fade_panel(show_panel: bool) -> void:
	if fade_duration <= 0.0:
		# instant toggle instead of a fade, if fade_duration is set to 0
		panel.visible = show_panel
		panel.modulate.a = 1.0 if show_panel else 0.0
		return

	if show_panel:
		panel.visible = true

	# KILL THE PREVIOUS FADE FIRST. Enter and exit each start a tween, and the
	# exit one ends with `panel.visible = false` unconditionally. Step out of
	# range and back in within fade_duration (0.2s by default) and the old exit
	# tween finishes DURING the new fade-in and hides a panel that is now at
	# full alpha — invisible text for the whole approach, until you leave and
	# come back slowly.
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()

	var tween := create_tween()
	_fade_tween = tween
	var target_alpha: float = 1.0 if show_panel else 0.0
	tween.tween_property(panel, "modulate:a", target_alpha, fade_duration)

	if not show_panel:
		tween.finished.connect(func(): panel.visible = false)
		return
