# sign.gd — world-placed readable sign. shows its Label child when the
# player walks into the detection area, hides it on exit.
#
# scene setup:
# - Area2D root (this script)
# - Label child named "Label" (CamelCase) with the sign text already filled in
# - CollisionShape2D sized to the area where the label should be readable
#
# the label can be styled and positioned in the editor — this script just
# toggles its visibility. for richer behavior (typewriter effect, dialogue
# trees, NPC speech), this is a good template to extend from.
extends Area2D


# =============================================================================
# NODE REFERENCES
# =============================================================================

# the label that holds the sign's text. shown only when the player is nearby.
@onready var label: Label = $label


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# start hidden — sign only reveals its text when the player approaches
	label.visible = false


# =============================================================================
# AREA SIGNAL HANDLERS
# =============================================================================

func _on_body_entered(body: Node) -> void:
	# show the label when the player enters the detection area.
	# ignores enemies, projectiles, drops — only the player triggers reveal.
	if body.is_in_group("player"):
		label.visible = true


func _on_body_exited(body: Node) -> void:
	# hide the label when the player leaves the detection area
	if body.is_in_group("player"):
		label.visible = false
