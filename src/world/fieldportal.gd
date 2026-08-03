# fieldportal.gd — marks a specific point in a scene as a named arrival
# spot, so a portal in a DIFFERENT scene can tell the game "when the
# player arrives, put them here" instead of just wherever the player node
# happens to be manually placed in the new scene's file.
#
# reusable anywhere a scene ends up with more than one possible arrival
# point — e.g. field's town-side portal today, and a future ladder's own
# separate landing spot, each needing the player to end up somewhere
# different depending on how they got there.
#
# USAGE:
# - attach to a Node2D marking the exact spot the player should appear at
# - set portal_id to something unique within this scene (e.g. "town_entrance")
# - whatever triggers the scene change stores this same id on GameState
#   before transitioning (see leavetown.gd's target_spawn_id)
# - the new scene's own root script reads that id and searches for the
#   matching FieldPortal to position the player at
extends Node2D
class_name FieldPortal

@export var portal_id: String = ""

func _ready() -> void:
	add_to_group("fieldportals")
