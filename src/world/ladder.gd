# ladder.gd — teleport trigger that changes to a different scene, for the
# field <-> boss ladder pair specifically. same core teleport pattern as
# leavetown.gd (fade out, swap scenes, fade back in via the SceneTransition
# autoload), but as its own dedicated script rather than reusing that one —
# clearer at a glance what this node actually is, and skips
# leavetown.gd's vanish-after-first-use feature entirely, since that was
# built for a deliberately one-way portal (fieldteleport) and doesn't apply
# here — a ladder should stay usable in both directions indefinitely.
#
# uses the SAME target_spawn_id + FieldPortal pairing pattern already
# proven for field/leavetown: set target_spawn_id here to the portal_id of
# a FieldPortal marker in the DESTINATION scene, so the player lands at a
# specific spot instead of wherever that scene's player node happens to be
# placed by default.
extends Area2D


# =============================================================================
# EXPORTED SETTINGS
# =============================================================================

# assign in the Inspector — the scene this ladder leads to.
@export var destination_scene: PackedScene

# if set, stored on GameState right before transitioning, so the
# destination scene knows which FieldPortal marker to place the player at.
# leave empty to fall back to that scene's own default player placement.
@export var target_spawn_id: String = ""


# =============================================================================
# STATE
# =============================================================================

var can_teleport := true


# =============================================================================
# COLLISION HANDLERS
# =============================================================================

func _on_body_entered(body):
	if body and can_teleport and (body.name == "Player" or body.is_in_group("player")):
		can_teleport = false
		if destination_scene == null:
			push_warning("Ladder (%s): destination_scene not assigned in the Inspector" % name)
			return
		if target_spawn_id != "":
			GameState.next_spawn_id = target_spawn_id
		SceneTransition.change_scene(destination_scene)


func _on_body_exited(body):
	if body and (body.name == "Player" or body.is_in_group("player")):
		can_teleport = true
